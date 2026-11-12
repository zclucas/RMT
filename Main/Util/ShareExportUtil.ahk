#Requires AutoHotkey v2.0

; 选择性导出：将勾选的宏和模块写为现行配置目录。
; 依赖闭包复用 MergeUtil.CollectSourceConfigs（指令配置/变量都是 DataFileMap 序列码条目，含嵌套分支）
; 导入时由配置升级入口按目标目录校正图片路径。
class ShareExportUtil {

    ; 返回缺失依赖的序列号列表（顿号连接；空串=无缺失。不阻断导出）
    static ExportChecked(checkedItems, sourceDir, outDir, report := "") {
        if (checkedItems.Length == 0)
            throw Error(GetLang("没有可导出的宏"))

        if (DirExist(outDir))
            DirDelete(outDir, true)
        DirCreate(outDir)

        ; 1) 指令配置依赖闭包（含嵌套分支与变量）
        serials := MergeUtil.CollectAllResourceSerials(checkedItems)
        collected := Map()
        if (serials.Count)
            collected := MergeUtil.CollectSourceConfigs(sourceDir, serials)

        targets := Map()
        tableCounts := Map()
        for item in checkedItems {
            if (RegExMatch(item.Serial, "^([\w-]+)\.[\w-]+\.[\w-]+$", &path)) {
                tableID := path[1]
                tableCounts[tableID] := tableCounts.Get(tableID, 0) + 1
                targets[item.Serial] := tableCounts[tableID]
            }
        }
        for serial, info in collected {
            if (!IsObject(info))
                continue
            cmdType := info["类型"]
            if (!MySoftData.DataFileMap.Has(cmdType))
                continue
            dataFile := MySoftData.DataFileMap[cmdType]
            SplitPath dataFile, &baseName
            raw := info["配置"]
            if (cmdType == "宏操作") {
                data := TryParseCommandData(raw)
                if (IsObject(data) && data.HasOwnProp("MacroType") && data.MacroType != "当前宏") {
                    target := data.HasOwnProp("MacroSerial") ? data.MacroSerial : ""
                    data.Index := targets.Get(target, 0)
                    data.MacroSerial := data.Index ? target : ""
                    raw := JSON.stringify(data, 0)
                }
            }
            CfgWrite(raw, outDir "\" baseName, SettingSection, serial)
        }
        missingNames := []
        for serial, _ in serials {
            if (!collected.Has(serial))
                missingNames.Push(serial)
        }

        ; 2) 图片：整目录拷贝（导入端 CompatPath 按 Setting\...\Images 子串自动改写路径）
        if (DirExist(sourceDir "\Images")) {
            if (report)
                report(GetLang("正在复制配置文件"))
            DirCopy(sourceDir "\Images", outDir "\Images", true)
        }

        this._WriteMacroFile(checkedItems, outDir)
        CfgFlushDir(outDir)
        Compat_WriteVersion(outDir, Compat_CurrentVersion())
        return this._JoinName(missingNames)
    }

    static _JoinName(arr) {
        out := ""
        for i, v in arr {
            if (i > 1)
                out .= "、"
            out .= String(v)
        }
        return out
    }

    static _WriteMacroFile(checkedItems, outDir) {
        tables := Map()
        order := []
        reserved := Map()
        for source in checkedItems
            reserved[source.Serial] := true

        for source in checkedItems {
            if (source.TabIndex < 1 || !MySoftData.TableInfo.Has(source.TabIndex))
                continue
            symbol := GetTableSymbol(source.TabIndex)
            if (!IsItemSymbol(symbol))
                continue
            ; 保留源宏身份，宏操作引用可直接指向分享包中的对应宏。
            hasID := RegExMatch(source.Serial, "^(" symbol "(?:_\d+)?)\.[\w-]+\.[\w-]+$", &path)
            tableID := hasID ? path[1] : symbol
            if (!tables.Has(tableID)) {
                table := TableItem()
                table.ID := tableID
                table.Symbol := symbol
                table.Name := MySoftData.TableInfo[source.TabIndex].Name
                tables[tableID] := table
                order.Push(tableID)
            }
            table := tables[tableID]
            title := source.ModuleName != "" ? source.ModuleName : GetLang("默认模块")
            if (!table.Folds.Length || table.Folds[-1].Remark != title) {
                fold := MacroFold()
                fold.ID := tableID ".Module" (table.Folds.Length + 1)
                fold.Remark := title
                table.Folds.Push(fold)
            }
            fold := table.Folds[-1]
            item := MacroItem()
            item.FoldID := fold.ID
            if (hasID)
                item.ID := source.Serial
            else {
                loop {
                    item.ID := NewMacroPath(table, fold.ID)
                    if (!reserved.Has(item.ID))
                        break
                }
            }
            item.TK := source.TriggerKey
            item.Remark := source.Remark
            item.Macro := source.MacroStr
            item.PreMacro := source.HasOwnProp("PreMacro") ? source.PreMacro : ""
            item.PostMacro := source.HasOwnProp("PostMacro") ? source.PostMacro : ""
            table.Items.Push(item)
            table.RememberPath(item.ID)
        }

        tableList := []
        root := Map("table", tableList)
        for index, tableID in order {
            table := tables[tableID]
            table.RebuildIndex()
            tableList.Push(Map("id", tableID, "symbol", table.Symbol, "name", table.Name, "order", index))
            SaveTableItemInfoTomlCore(root, table)
        }
        TomlUtil_Write(root, outDir "\MacroFile.toml")
    }

    ; 由勾选内容给出默认分享名：单个宏用宏名，多个用来源配置名
    static SuggestName(checkedItems, sourceName) {
        if (checkedItems.Length == 1 && checkedItems[1].Remark != "")
            return this.SanitizeName(checkedItems[1].Remark)
        return this.SanitizeName(sourceName)
    }

    static SanitizeName(name) {
        name := RegExReplace(String(name), '[\\/:\*\?"<>\|]', "_")
        name := Trim(name)
        return (name == "") ? "分享" : SubStr(name, 1, 60)
    }

    ; ===== 一键分享入口：宏行 / 模块头按钮 → 导出打包 → 直接打开上传窗口 =====

    ; 单个宏 → 上传窗口（级别=宏）
    static ShareMacro(tableItem, i) {
        item := tableItem.Items[i]
        if (!IsObject(item))
            throw Error(GetLang("宏不存在"))
        shim := {
            TabIndex: tableItem.Index,
            Serial: item.ID,
            TriggerKey: item.TK,
            Remark: item.Remark,
            MacroStr: item.Macro,
            PreMacro: item.PreMacro,
            PostMacro: item.PostMacro,
            ModuleName: "",
            DisplayName: item.Remark,
            ResourceSerials: MergeUtil.ExtractResourceSerials(item.Macro "," item.PreMacro "," item.PostMacro)
        }
        arr := [shim]
        defaultName := this.SuggestName(arr, MySoftData.CurSettingName)
        this._ExportAndOpen(arr, defaultName, GetLang("宏"))
    }

    ; 整个模块（折叠框）下的全部宏 → 上传窗口（级别=模块）
    static ShareFold(tableItem, f) {
        fold := tableItem.Folds[f]
        if (!IsObject(fold))
            throw Error(GetLang("模块不存在"))
        arr := []
        for item in tableItem.Items {
            if (item.FoldID != fold.ID)
                continue
            arr.Push({
                TabIndex: tableItem.Index,
                Serial: item.ID,
                TriggerKey: item.TK,
                Remark: item.Remark,
                MacroStr: item.Macro,
                PreMacro: item.PreMacro,
                PostMacro: item.PostMacro,
                ModuleName: fold.Remark,
                DisplayName: item.Remark,
                ResourceSerials: MergeUtil.ExtractResourceSerials(item.Macro "," item.PreMacro "," item.PostMacro)
            })
        }
        if (arr.Length == 0)
            throw Error(GetLang("该模块下没有宏"))
        defaultName := this.SuggestName(arr, fold.Remark != "" ? fold.Remark : MySoftData.CurSettingName)
        this._ExportAndOpen(arr, defaultName, GetLang("模块"))
    }

    ; 导出勾选项 → 打包 .rmt → 打开上传窗口（分享包/名称预填）
    static _ExportAndOpen(checkedItems, defaultName, level) {
        sourceDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        if (sourceDir == "" || !DirExist(sourceDir))
            throw Error(GetLang("当前配置目录不存在"))

        package := this.BuildPackage(checkedItems, sourceDir, defaultName, XamlWin.ActiveOwner())

        if (package.Missing != "")
            RmtDialog.Info(GetLang("以下被引用的指令配置未找到，分享包可能不完整：") "`n" package.Missing, GetLang("提示"))

        ShareUploadGui.ShowGui(package.Path, defaultName, level)
    }

    static BuildPackage(checkedItems, sourceDir, name, owner) {
        ; 导出会按磁盘上的配置文件打包，而写配置现在是「改内存 + 延迟落盘」，
        ; 不先刷出去，刚改过的宏会以旧内容进包。
        try CfgFlushAll()
        try UIMacroSchema.FlushStore()
        return RmtProgress.Run(GetLang("导出配置"), GetLang("正在检查配置文件")
            , (progress) => this._BuildPackage(checkedItems, sourceDir, name, ObjBindMethod(progress, "Report")), owner)
    }

    static _BuildPackage(checkedItems, sourceDir, name, report) {
        outDir := A_Temp "\RMT_Export_" A_Now "_" A_TickCount "_" Random(1000, 9999)
        try {
            missing := this.ExportChecked(checkedItems, sourceDir, outDir, report)
            exportDir := A_Temp "\RMT_Export"
            DirCreate(exportDir)
            rmtPath := exportDir "\" name ".rmt"
            if (FileExist(rmtPath))
                FileDelete(rmtPath)
            report(GetLang("正在打包文件"))
            FolderPackager.PackFolder(outDir, rmtPath, "", report)
            return {Path: rmtPath, Missing: missing}
        } finally {
            try DirDelete(outDir, true)
        }
    }
}

; ===== 主窗口行/模块按钮的全局入口 =====

OnItemShareMacroBtnClick(tableItem, i, *) {
    try {
        ShareExportUtil.ShareMacro(tableItem, i)
    } catch as e {
        RmtDialog.Info(GetLang("分享失败: ") e.Message, GetLang("错误"))
    }
}

OnFoldShareBtnClick(tableItem, f, *) {
    try {
        ShareExportUtil.ShareFold(tableItem, f)
    } catch as e {
        RmtDialog.Info(GetLang("分享失败: ") e.Message, GetLang("错误"))
    }
}
