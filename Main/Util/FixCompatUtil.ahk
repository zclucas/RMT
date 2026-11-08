#Requires AutoHotkey v2.0
#Include "CompatTov1-2.ahk"
#Include "Compatv1-3.ahk"

; 配置格式版本独立于 RMPK 容器版本和软件构建版本。
Compat_CurrentVersion() => "1.3"
Compat_VersionFile(dir) => dir "\RmtVersion.toml"

Compat_CompareVersion(left, right) {
    if (!RegExMatch(left, "^\d+\.\d+(?:\.\d+)?$") || !RegExMatch(right, "^\d+\.\d+(?:\.\d+)?$"))
        throw Error("无效的 RMT 配置版本：" left " / " right)
    a := StrSplit(left, "."), b := StrSplit(right, ".")
    loop 3 {
        x := A_Index <= a.Length ? Integer(a[A_Index]) : 0
        y := A_Index <= b.Length ? Integer(b[A_Index]) : 0
        if (x != y)
            return x > y ? 1 : -1
    }
    return 0
}

Compat_ReadVersion(dir) {
    path := Compat_VersionFile(dir)
    if (!FileExist(path))
        return "0.0"
    CfgInvalidate(path)
    version := CfgRead(path, "RMT", "ConfigVersion", "")
    Compat_CompareVersion(version, Compat_CurrentVersion())
    return version
}

Compat_WriteVersion(dir, version) {
    CfgWrite(version, Compat_VersionFile(dir), "RMT", "ConfigVersion")
}

; 新版本新增 CompatvN-M.ahk，并按目标版本顺序登记。
Compat_MigrationSteps() {
    return [{Version: "1.2.2", Run: CompatTo12_UpgradeDir},
        {Version: "1.3", Run: Compat13_UpgradeProfile}]
}

Compat_UpgradeDir(dir) {
    version := Compat_ReadVersion(dir)
    if (Compat_CompareVersion(version, Compat_CurrentVersion()) > 0)
        throw Error("配置版本 " version " 高于当前支持的 " Compat_CurrentVersion())
    loop files, dir "\*.toml" {
        CfgInvalidate(A_LoopFileFullPath)
        TomlUtil_Invalidate(A_LoopFileFullPath)
    }
    ; 仅转换存储格式，不在 INI 转换器中夹带版本语义迁移。
    conv := IniImport_ConvertDir(dir)
    if (conv["Failed"].Count) {
        msg := ""
        for name, err in conv["Failed"]
            msg .= name ": " err "`n"
        throw Error("配置转换失败：" msg)
    }
    changed := conv["Converted"] > 0
    for step in Compat_MigrationSteps() {
        if (Compat_CompareVersion(version, step.Version) >= 0)
            continue
        changed := step.Run.Call(dir) || changed
        ; 本阶段完整成功后才推进版本，失败不能标为已迁移。
        Compat_WriteVersion(dir, step.Version)
        version := step.Version
        changed := true
    }
    ; 路径搬迁不是版本升级：同版本包导入也需要定位包内图片。
    loop files, dir "\*.toml" {
        path := A_LoopFileFullPath
        for key, value in CfgSection(path, IniImport_Section()) {
            data := CompatParseData(value)
            if (IsObject(data) && CompatPath(path, data)) {
                CfgWrite(JSON.stringify(data, 0), path, IniImport_Section(), key)
                changed := true
            }
        }
    }
    return changed
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

Compat_InstallStagedTree(staged, currentDir, backup, verify) {
    global TomlUtil_Cache
    backedUp := false
    installed := false
    try {
        if (DirExist(currentDir)) {
            DirMove(currentDir, backup)
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
                DirMove(backup, currentDir)
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
Compat_ImportSettingsTree(source, currentDir, backupRoot, currentName) {
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
        for name in profiles {
            Compat_UpgradeDir(staged "\" name)
            list .= (list = "" ? "" : "π") name
            if (name = currentName)
                selected := name
        }
        if (selected = "")
            selected := profiles[1]
        setting := staged "\MainSettings.toml"
        CfgWrite(list, setting, "UserSettings", "SettingArrStr")
        CfgWrite(selected, setting, "UserSettings", "CurSettingName")
        CfgWrite(true, setting, "UserSettings", "IsReload")

        Compat_InstallStagedTree(staged, currentDir, paths.Backup, Compat_RepairInstalledSettings.Bind(currentDir, profiles))
        return {Names: list, Selected: selected, Backup: paths.Backup}
    } finally {
        ; staged 是在固定备份根下新建的独立目录，与源目录及当前配置不重合。
        if (DirExist(staged))
            try DirDelete(staged, true)
    }
}

Compat_ImportProfilePackage(file, root, backupRoot, name) {
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
            DirCopy(dest, paths.Stage)
        }
        FolderPackager.UnpackFile(file, paths.Stage)
        Compat_UpgradeDir(paths.Stage)
        Compat_InstallStagedTree(paths.Stage, dest, paths.Backup, Compat_UpgradeDir.Bind(dest))
    } finally {
        if (DirExist(paths.Stage))
            try DirDelete(paths.Stage, true)
    }
}
