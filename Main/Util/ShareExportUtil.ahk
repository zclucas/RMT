#Requires AutoHotkey v2.0

; 选择性导出：把勾选的宏/模块重排成一份自洽的最小配置目录（MacroFile.toml 扁平数组布局）
; 依赖闭包复用 MergeUtil.CollectSourceConfigs（指令配置/变量都是 DataFileMap 序列码条目，含嵌套分支）
; 导入端：UnpackFile → OnRepairSetting(Compat* 补齐数组字段) → CompatPath 自动改写图片路径
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
        if (GetObjectCount(serials) > 0)
            collected := MergeUtil.CollectSourceConfigs(sourceDir, serials)

        for serial, info in collected {
            if (!IsObject(info))
                continue
            cmdType := info["类型"]
            if (!MySoftData.DataFileMap.Has(cmdType))
                continue
            dataFile := MySoftData.DataFileMap[cmdType]
            SplitPath dataFile, &baseName
            CfgWrite(info["配置"], outDir "\" baseName, SettingSection, serial)
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

        ; 3) 宏定义：写 MacroFile.toml 扁平数组布局（π 分隔数组 + FoldInfo 模块分组）
        this._WriteMacroFileFlatToml(checkedItems, outDir)
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

    static _WriteMacroFileFlatToml(checkedItems, outDir) {
        macroFile := outDir "\MacroFile.toml"

        ; 按页签分组（保持勾选顺序）
        tabItems := Map()
        tabOrder := []
        for item in checkedItems {
            if (item.TabIndex < 1 || !MySoftData.TableInfo.Has(item.TabIndex))
                continue
            symbol := GetTableSymbol(item.TabIndex)
            if (!IsItemSymbol(symbol))
                continue
            if (!tabItems.Has(symbol)) {
                tabItems.Set(symbol, [])
                tabOrder.Push(symbol)
            }
            tabItems[symbol].Push(item)
        }

        for _, symbol in tabOrder {
            items := tabItems[symbol]
            n := items.Length

            tkArr := [], remarkArr := [], modeArr := [], macroArr := [], serialArr := []
            for item in items {
                tkArr.Push(this._FlatSafe(item.TriggerKey))
                remarkArr.Push(this._FlatSafe(item.Remark))
                modeArr.Push("1")
                serialArr.Push(item.Serial)
                ; 扁平格式用 ⫶ 承载换行
                macroArr.Push(this._FlatSafe(StrReplace(String(item.MacroStr), "`n", "⫶")))
            }

            CfgWrite(this._JoinPi(modeArr), macroFile, SettingSection, symbol "ModeArr")
            CfgWrite(this._JoinPi(tkArr), macroFile, SettingSection, symbol "TKArr")
            CfgWrite(this._JoinPi(remarkArr), macroFile, SettingSection, symbol "RemarkArr")
            CfgWrite(this._JoinPi(serialArr), macroFile, SettingSection, symbol "SerialArr")
            loop n
                CfgWrite(macroArr[A_Index], macroFile, SettingSection, symbol "MacroArr" A_Index)
            for i, item in items {
                for field in ["PreMacro", "PostMacro"] {
                    if (item.HasOwnProp(field) && item.%field% != "")
                        CfgWrite(this._FlatSafe(StrReplace(item.%field%, "`n", "⫶")), macroFile, SettingSection, symbol field "Arr" i)
                }
            }

            ; 其余结构数组字段缺省即可：导入端 CompatCMD 按 ModeArr 长度补齐

            ; FoldInfo：按模块连续段生成分组（勾选顺序即树顺序，同模块天然连续）
            spanArr := [], remarkJsonArr := []
            spanStart := 0, spanModule := ""
            i := 0
            for item in items {
                i++
                moduleName := (item.ModuleName != "") ? item.ModuleName : GetLang("默认模块")
                if (moduleName != spanModule) {
                    if (spanStart > 0) {
                        spanArr.Push(spanStart "-" (i - 1))
                        remarkJsonArr.Push(spanModule)
                    }
                    spanStart := i
                    spanModule := moduleName
                }
            }
            if (spanStart > 0) {
                spanArr.Push(spanStart "-" n)
                remarkJsonArr.Push(spanModule)
            }

            if (spanArr.Length > 0) {
                foldJson := this._BuildFoldJson(spanArr, remarkJsonArr)
                CfgWrite(foldJson, macroFile, SettingSection, symbol "FoldInfo")
            }
        }
    }

    ; π 是内部分隔符（U+03C0），正文里出现会破坏数组，替换为形近的「兀」
    static _FlatSafe(s) {
        s := StrReplace(String(s), "π", "兀")
        s := StrReplace(s, "`r", "")
        return s
    }

    static _JoinPi(arr) {
        out := ""
        for i, v in arr {
            if (i > 1)
                out .= "π"
            out .= String(v)
        }
        return out
    }

    static _JsonEsc(s) {
        s := StrReplace(String(s), "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    static _BuildFoldJson(spanArr, remarkArr) {
        out := '{"IndexSpanArr":['
        for i, v in spanArr {
            if (i > 1)
                out .= ","
            out .= '"' this._JsonEsc(v) '"'
        }
        out .= '],"RemarkArr":['
        for i, v in remarkArr {
            if (i > 1)
                out .= ","
            out .= '"' this._JsonEsc(v) '"'
        }
        out .= "]}"
        return out
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
            ModuleName: "",
            DisplayName: item.Remark,
            ResourceSerials: MergeUtil.ExtractResourceSerials(item.Macro)
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
                ModuleName: fold.Remark,
                DisplayName: item.Remark,
                ResourceSerials: MergeUtil.ExtractResourceSerials(item.Macro)
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
