#Requires AutoHotkey v2.0
#Include "CompatDataUtil.ahk"
#Include "Compatv1-3.ahk"
#Include "Compatv1-3-1.ahk"
#Include "Compatv1-3-2.ahk"
#Include "Compatv1-3-5.ahk"
#Include "Compatv1-3-10.ahk"
#Include "Compatv1-3-11.ahk"
#Include "UIMacroSchema.ahk"

; 配置格式版本独立于 RMPK 容器版本和软件构建版本。
Compat_CurrentVersion() => "1.3.11"
Compat_VersionFile(dir) => dir "\RmtVersion.toml"

Compat_ReadVersion(dir) {
    path := Compat_VersionFile(dir)
    if (FileExist(path)) {
        CfgInvalidate(path)
        version := CfgRead(path, "RMT", "ConfigVersion", "")
        if (version != "")
            return version
        version := CfgRead(path, "RMT", "AppVersion", "")
        if (version != "")
            return version
    }
    ; 1.2.2 没有版本清单，使用 INI。无版本 TOML 不进入旧版语义转换。
    return FileExist(dir "\MacroFile.ini") || FileExist(dir "\MainSettings.ini") ? "1.2.2" : ""
}

Compat_WriteVersion(dir, version) {
    path := Compat_VersionFile(dir)
    root := Cfg_Load(path, true).Clone()
    manifest := Cfg_Seg(root, "RMT").Clone()
    manifest["ConfigVersion"] := version
    root["RMT"] := manifest
    Cfg_WriteRoot(root, path)
}

Compat_FlushProfile(dir) {
    CfgFlushDir(dir)
    UIMacroPanelStore.FlushDir(dir)
}

Compat_UpgradeDir(dir, installed := false) {
    dir := ResolvePathNoDotDot(dir)
    Compat_FlushProfile(dir)
    version := Compat_ReadVersion(dir)
    upgradePreview := installed && version == "1.3.6"
    upgradeMove := version == "1.3.7"
    upgradeControls := version == "1.3.8"
    upgradeOperands := version == "1.3.9"
    upgradeAssignments := version == "1.3.10"
    if (version != "" && version != "1.2.2" && version != Compat_CurrentVersion() && !upgradePreview && !upgradeMove && !upgradeControls && !upgradeOperands && !upgradeAssignments)
        throw Error("不支持直接升级配置版本 " version "。请选择 RMT 1.2.2 的配置，或使用当前版本导出的配置。")
    loop files, dir "\*.toml" {
        CfgInvalidate(A_LoopFileFullPath)
        TomlUtil_Invalidate(A_LoopFileFullPath)
    }
    changed := false
    if (version == "1.2.2") {
        ; 转换会逐个清理 INI。先记下来源版本，部分写入失败时仍可继续。
        Compat_WriteVersion(dir, "1.2.2")
        conv := IniImport_ConvertDir(dir)
        if (conv["Failed"].Count) {
            msg := ""
            for name, err in conv["Failed"]
                msg .= name ": " err "`n"
            throw Error("配置转换失败：" msg)
        }
        if (FileExist(dir "\MainSettings.toml"))
            Compat13_UpgradeSettings(dir)
        Compat13_UpgradeProfile(dir)
    } else if (upgradePreview) {
        ; 已安装的上一版预览配置只需迁移分支末尾的流程控制。
        Compat13_UpgradeCompareBranches(dir)
    }
    if (upgradeMove || upgradePreview)
        Compat13_ExpandMoveSerials(dir)
    changed := Compat13_UpgradeWindowCommands(dir) || changed
    ; 同版本预览配置也可能保留旧内置名称；替换幂等，不改变普通文字。
    changed := Compat13_UpgradeBuiltinVariables(dir) || changed
    changed := Compat13_UpgradeWindowBindings(dir) || changed
    if (version == "1.2.2" || upgradePreview || upgradeMove || upgradeControls || upgradeOperands)
        changed := Compat13_UpgradeConditionOperands(dir) || changed
    changed := Compat13_UpgradeVariableAssignments(dir) || changed
    ; 路径搬迁不是版本升级：同版本包导入也需要定位包内图片。
    loop files, dir "\*.toml" {
        path := A_LoopFileFullPath
        for key, value in CfgSection(path, IniImport_Section()) {
            data := TryParseCommandData(value)
            if (IsObject(data) && CompatPath(path, data)) {
                CfgWrite(JSON.stringify(data, 0), path, IniImport_Section(), key)
                changed := true
            }
        }
    }
    CfgFlushDir(dir)
    ; 转换与写盘完成后才更新版本，失败时可重新执行。
    if (version == "1.2.2" || upgradePreview || upgradeMove || upgradeControls || upgradeOperands || upgradeAssignments) {
        Compat_WriteVersion(dir, Compat_CurrentVersion())
        changed := true
    }
    return changed
}

CompatPath(FilePath, Data) {
    if (!IsObject(Data))
        return false
    SplitPath FilePath, , &settingDir

    changed := CompatPathTarget(settingDir, Data)
    if (ObjHasOwnProp(Data, "SearchTargetArr") && IsObject(Data.SearchTargetArr)) {
        for target in Data.SearchTargetArr {
            if (IsObject(target))
                changed := CompatPathTarget(settingDir, target) || changed
        }
    }
    return changed
}

CompatPathTarget(settingDir, Data) {
    if (!IsObject(Data) || !ObjHasOwnProp(Data, "SearchImagePath") || Data.SearchImagePath == "")
        return false
    ; 当前配置内仍有效的图片可以位于任意子目录。
    path := StrReplace(Data.SearchImagePath, "/", "\")
    if (!RegExMatch(path, "i)^(?:[a-z]:\\|\\\\)"))
        path := A_WorkingDir "\" path
    if (InStr(path, settingDir "\") == 1 && FileExist(path) && !DirExist(path))
        return false
    ; 优先识别配置的资源根，避免把同名配置或安装路径中的 Images 当成资源目录。
    ; 包内相对路径和导入临时目录仍可直接按 Images 定位。
    if (RegExMatch(Data.SearchImagePath, "i)(?:^|[\\/])Setting[\\/][^\\/]+[\\/]Images[\\/](.+)$", &m)
        || RegExMatch(Data.SearchImagePath, "i)(?:^|[\\/])Images[\\/](.+)$", &m)) {
        newPath := settingDir "\Images\" StrReplace(m[1], "/", "\")
        if (FileExist(newPath) && !DirExist(newPath)) {
            if (newPath = Data.SearchImagePath)
                return false
            Data.SearchImagePath := newPath
            return true
        }
    }
    ; 旧版“选择图片”只记录外部绝对路径。原图尚在时收进配置，导出才会携带。
    ; 变量名/表达式不按文件处理，缺失的原图也不伪造替代路径。
    if (RegExMatch(Data.SearchImagePath, "i)^(?:[a-z]:[\\/]|\\\\)")
        && FileExist(Data.SearchImagePath) && !DirExist(Data.SearchImagePath)) {
        newPath := StoreSearchImage(Data.SearchImagePath, settingDir)
        if (newPath != Data.SearchImagePath) {
            Data.SearchImagePath := newPath
            return true
        }
    }
    return false
}

Compat_IsSettingName(name) {
    return (StrLen(name) >= 1 && StrLen(name) <= 255
        && !RegExMatch(name, '[\x00-\x1F<>:"/\\|?*π]|^[ ]|[ .]$')
        && !RegExMatch(name, "i)^(CON|CONIN\$|CONOUT\$|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]) *(\.|$)"))
}

Compat_RejectReparseAncestors(path) {
    while (path != "") {
        FolderPackager._RejectReparsePoint(path)
        SplitPath path, , &parent
        if (parent = path)
            break
        path := parent
    }
}

; 不跟随目录联接或符号链接；检查每个条目后才继续向下。
Compat_CheckPlainTree(source) {
    dirs := [source]
    while dirs.Length {
        dir := dirs.Pop()
        loop files, dir "\*", "FD" {
            FolderPackager._RejectReparsePoint(A_LoopFileFullPath)
            if (InStr(A_LoopFileAttrib, "D"))
                dirs.Push(A_LoopFileFullPath)
        }
    }
}

Compat_StagePaths(backupRoot, prefix := "Setting") {
    DirCreate(backupRoot)
    nonce := DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount
    staged := backupRoot "\.import-" nonce
    backup := backupRoot "\" prefix FormatTime(, "MM月dd日HH-mm-ss") "-" nonce
    if (FileExist(staged) || FileExist(backup))
        throw Error(GetLang("配置导入临时目录已存在，请重试"))
    return {Stage: staged, Backup: backup}
}

Compat_InstallStagedTree(staged, currentDir, backup, verify, sourceDir := unset) {
    global TomlUtil_Cache
    if (!IsSet(sourceDir))
        sourceDir := currentDir
    backedUp := false
    installed := false
    try {
        if (DirExist(sourceDir)) {
            Compat_FlushProfile(sourceDir)
            loop files, sourceDir "\*", "D"
                Compat_FlushProfile(A_LoopFileFullPath)
            DirMove(sourceDir, backup)
            backedUp := true
        }
        DirMove(staged, currentDir)
        installed := true
        CfgInvalidate()
        TomlUtil_Cache.Clear()
        verify.Call()
    } catch as e {
        try {
            if (installed)
                DirMove(currentDir, staged)
            if (backedUp)
                DirMove(backup, sourceDir)
        } catch as restoreError {
            throw Error(e.Message "`n" GetLang("恢复原配置失败，备份位于：") backup "`n" restoreError.Message)
        } finally {
            CfgInvalidate()
            TomlUtil_Cache.Clear()
        }
        throw e
    }
}

Compat_RepairInstalledSettings(root, profiles) {
    ; 升级时收录的图片路径应指向最终目录。
    for name in profiles
        Compat_UpgradeDir(root "\" name)
}

; 在独立目录转换所有配置，通过后才替换当前目录，原配置作为可恢复备份保留。
Compat_ImportSettingsTree(source, currentDir, backupRoot, currentName, report := "", fallbackCount := 0) {
    source := ResolvePathNoDotDot(source)
    currentDir := ResolvePathNoDotDot(currentDir)
    backupRoot := ResolvePathNoDotDot(backupRoot)
    srcPrefix := StrLower(source "\")
    curPrefix := StrLower(currentDir "\")
    if (!DirExist(source) || InStr(srcPrefix, curPrefix) = 1 || InStr(curPrefix, srcPrefix) = 1
        || InStr(StrLower(backupRoot "\"), srcPrefix) = 1)
        throw Error(GetLang("请选择与当前配置不同的旧版配置目录"))
    if (FileExist(source "\MacroFile.ini") || FileExist(source "\MacroFile.toml"))
        throw Error(GetLang("需要选择若梦兔软件下的Setting文件"))
    for path in [source, currentDir, backupRoot]
        Compat_RejectReparseAncestors(path)
    Compat_CheckPlainTree(source)
    paths := Compat_StagePaths(backupRoot)
    staged := paths.Stage
    try {
        if (report)
            report(GetLang("正在复制配置文件"))
        DirCopy(source, staged)
        profiles := []
        loop files, staged "\*", "D" {
            if (!Compat_IsSettingName(A_LoopFileName))
                throw Error(GetLang("配置名不符合文件目录命名规则，请修改") ": " A_LoopFileName)
            profiles.Push(A_LoopFileName)
        }
        if (!profiles.Length)
            throw Error(GetLang("所选目录中没有可导入的配置"))
        Compat_UpgradeDir(staged)
        list := ""
        selected := ""
        for i, name in profiles {
            if (report)
                report(GetLang("正在转换配置") " " name, Round(100 * (i - 1) / profiles.Length))
            Compat_UpgradeDir(staged "\" name)
            list .= (list = "" ? "" : "π") name
            if (name = currentName)
                selected := name
        }
        if (selected = "")
            selected := profiles[1]
        setting := staged "\MainSettings.toml"
        ; 次数属于整套设置。源值缺失时保留当前运行计数，合法的 0 照常迁移。
        macroTotalCount := ReadMacroTotalCount(setting, fallbackCount)
        CfgWrite(macroTotalCount, setting, "UserSettings", "MacroTotalCount")
        CfgWrite(list, setting, "UserSettings", "SettingArrStr")
        CfgWrite(selected, setting, "UserSettings", "CurSettingName")
        CfgWrite(true, setting, "UserSettings", "IsReload")
        CfgFlushDir(staged)

        if (report)
            report(GetLang("正在应用配置"))
        Compat_InstallStagedTree(staged, currentDir, paths.Backup, Compat_RepairInstalledSettings.Bind(currentDir, profiles))
        return {Names: list, Selected: selected, Backup: paths.Backup, MacroTotalCount: macroTotalCount}
    } finally {
        ; staged 是在固定备份根下新建的独立目录，与源目录及当前配置不重合。
        if (DirExist(staged))
            try DirDelete(staged, true)
    }
}

Compat_ImportProfilePackage(file, root, backupRoot, name, commit := unset, report := "") {
    if (!Compat_IsSettingName(name))
        throw Error(GetLang("配置名不符合文件目录命名规则，请修改"))
    dest := root "\" name
    Compat_RejectReparseAncestors(dest)
    Compat_RejectReparseAncestors(backupRoot)
    paths := Compat_StagePaths(backupRoot, "Profile-")
    try {
        ; 覆盖导入保留原配置中包内没有的资源，校验通过前只改临时副本。
        if (DirExist(dest)) {
            Compat_CheckPlainTree(dest)
            Compat_FlushProfile(dest)
            DirCopy(dest, paths.Stage)
        }
        FolderPackager.UnpackFile(file, paths.Stage, report)
        if (report)
            report(GetLang("正在应用配置"))
        Compat_UpgradeDir(paths.Stage)
        verify := IsSet(commit) ? () => (Compat_UpgradeDir(dest), commit.Call()) : Compat_UpgradeDir.Bind(dest)
        Compat_InstallStagedTree(paths.Stage, dest, paths.Backup, verify)
    } finally {
        if (DirExist(paths.Stage))
            try DirDelete(paths.Stage, true)
    }
}

Compat_RenameProfile(projectDir, oldName, newName, commit) {
    Compat_TransferProfile(projectDir, oldName, newName, commit, true)
}

Compat_TransferProfile(projectDir, oldName, newName, commit, rename := false) {
    if (!Compat_IsSettingName(oldName) || !Compat_IsSettingName(newName))
        throw Error(GetLang("配置名不符合文件目录命名规则，请修改"))
    oldDir := projectDir "\Setting\" oldName
    newDir := projectDir "\Setting\" newName
    backupRoot := projectDir "\SettingOld"
    if (FileExist(newDir))
        throw Error(GetLang("配置名已存在"))
    for path in [oldDir, newDir, backupRoot]
        Compat_RejectReparseAncestors(path)
    Compat_CheckPlainTree(oldDir)
    paths := Compat_StagePaths(backupRoot, "Rename-")
    try {
        ; 先改副本，写盘或切换失败时可完整恢复原目录。
        Compat_FlushProfile(oldDir)
        DirCopy(oldDir, paths.Stage)
        rebase := Compat_RebaseProfilePath.Bind(oldDir, newDir, projectDir)
        loop files, paths.Stage "\*.toml" {
            file := A_LoopFileFullPath
            data := TomlUtil_Read(file)
            if (!TomlUtil_Valid(data))
                continue
            root := data.tomap()
            if (Compat_RebaseProfileValues(root, rebase))
                TomlUtil_Write(Compat_UnquoteTomlKeys(root), file)
        }
        verify := rename ? () => commit.Call(rebase) : () => (Compat_UpgradeDir(newDir), commit.Call(rebase))
        Compat_InstallStagedTree(paths.Stage, newDir, paths.Backup, verify, rename ? oldDir : newDir)
    } finally {
        if (DirExist(paths.Stage))
            try DirDelete(paths.Stage, true)
    }
}

; TOML 解析器保留各级键的引号，写入器会按需重新加引号。
Compat_UnquoteTomlKeys(value) {
    if (value is Map) {
        result := Map()
        for key, child in value
            result[TomlUtil_StripKey(key)] := Compat_UnquoteTomlKeys(child)
        return result
    }
    if (value is ArrayList) {
        result := ArrayList()
        for child in value
            result.add(Compat_UnquoteTomlKeys(child))
        return result
    }
    return value
}

; 路径可能是 TOML 字段，也可能在 JSON 指令、数组或组合搜索目标中。
Compat_RebaseProfileValues(values, rebase) {
    changed := false
    for key, value in values {
        if (value is Map || value is Array || value is ArrayList) {
            changed := Compat_RebaseProfileValues(value, rebase) || changed
            continue
        }
        if (Type(value) != "String")
            continue
        newValue := rebase.Call(value)
        if (newValue == value && RegExMatch(value, "^\s*(?:\{|\[)")) {
            data := ""
            try data := JSON.parse(value, true)
            if ((data is Map || data is Array) && Compat_RebaseProfileValues(data, rebase))
                newValue := JSON.stringify(data, 0)
        }
        if (newValue !== value) {
            values[key] := newValue
            changed := true
        }
    }
    return changed
}

Compat_RebaseProfilePath(oldDir, newDir, projectDir, value) {
    ; 运行指令的文件选择器会为程序路径加引号，参数保留原样。
    if (RegExMatch(value, '^"([^"]+)"(\s.*)?$', &quoted)) {
        path := Compat_RebaseProfilePath(oldDir, newDir, projectDir, quoted[1])
        return (path == quoted[1]) ? value : '"' path '"' quoted[2]
    }
    path := StrReplace(value, "/", "\")
    if (!InStr(path, "\") || RegExMatch(path, '[\x00-\x1F"<>|]'))
        return value
    absolute := RegExMatch(path, "i)^(?:[a-z]:\\|\\\\)")
    if (!absolute && (SubStr(path, 1, 1) == "\" || InStr(path, ":")))
        return value
    relativePrefix := ""
    if (!absolute && SubStr(path, 1, 2) == ".\") {
        relativePrefix := ".\"
        path := SubStr(path, 3)
    }
    ; Worker 的工作目录是 Thread，允许宏用 ..\Setting 引用配置文件。
    if (!absolute && InStr(path, "..\Setting\") == 1) {
        relativePrefix .= "..\"
        path := SubStr(path, 4)
    }
    trailingSlash := SubStr(path, -1) == "\" ? "\" : ""
    path := RTrim(absolute ? path : projectDir "\" path, "\")
    ; 统一分隔符并消去 . / ..，用目录边界排除同名前缀的其他配置。
    if (RegExMatch(path, '(?:^|\\)\.{1,2}(?:\\|$)')) {
        pathBuffer := Buffer(65536 * 2, 0)
        length := DllCall("GetFullPathNameW", "Str", path, "UInt", 65536, "Ptr", pathBuffer, "Ptr", 0)
        if (length > 0 && length < 65536)
            path := StrGet(pathBuffer, length)
    }
    prefixLen := StrLen(oldDir)
    if (path != oldDir && SubStr(path, 1, prefixLen + 1) != oldDir "\")
        return value
    target := newDir SubStr(path, prefixLen + 1) trailingSlash
    return absolute ? target : relativePrefix SubStr(target, StrLen(projectDir) + 2)
}
