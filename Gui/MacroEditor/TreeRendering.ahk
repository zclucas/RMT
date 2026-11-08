
    InitTreeView(MacroStr) {
        this.ResetDebugState()
        this.ClearMultiSelection()
        this.MacroTreeViewCon.Visible := this.EditModeCon.Value == 1
        cmdArr := SplitMacro(MacroStr)
        this.MacroTreeViewCon.Opt("-Redraw")
        this.MacroTreeViewCon.Delete()
        this.LastItemID := 0
        for cmdStr in cmdArr {
            ; 幂等迁移：历史版本曾把当前位置标记 → 写进宏串，这里统一清除让老配置自愈
            cmdStr := CmdStripCurPos(cmdStr)
            iconStr := this.GetCmdIconStr(cmdStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(cmdStr)
            root := this.MacroTreeViewCon.Add(displayStr, 0, iconStr)
            this.LastItemID := root
            this.TreeAddBranch(root, cmdStr)
        }
        ; 树重建后按缓存断点串重放标记（Render 前设字段，Render 读字段渲染 Brk_）
        this._ApplyBreakpoints(this._bpStr)
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    RefreshTree(itemID) {
        this.ClearMultiSelection()
        CommandStr := this.MacroTreeViewCon.GetText(itemID)
        paramsArr := StrSplit(CommandStr, "_")

        subItem := this.MacroTreeViewCon.GetChild(itemID)
        while (subItem) {
            this.MacroTreeViewCon.Delete(subItem)
            subItem := this.MacroTreeViewCon.GetChild(itemID)
        }
        this.TreeAddBranch(itemID, CommandStr)
        ; F5：增量重建子节点后按缓存断点串重放 Brk_ 标记（否则编辑容器后其子节点断点视觉丢失）
        this._ApplyBreakpoints(this._bpStr)
        ; 不再 TreeExpand：新节点默认 expanded，增量增删已呈现完整分支，无需全量重建
    }

    TreeAddBranch(root, cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        IsSkip := SubStr(paramArr[1], 1, 2) == "🚫"
        IsSearchCombo := InStr(paramArr[1], GetLang("搜索Combo")) || InStr(paramArr[1], GetLang("组合搜索")) || InStr(paramArr[1], GetLang("搜索Multi"))
        IsSearchPro := InStr(paramArr[1], GetLang("搜索Pro")) || InStr(paramArr[1], GetLang("搜索All"))
        IsSearch := InStr(paramArr[1], GetLang("搜索")) && !IsSearchPro && !IsSearchCombo
        IsIfPro := InStr(paramArr[1], GetLang("如果Pro"))
        IsIf := InStr(paramArr[1], GetLang("如果")) && !IsIfPro
        IsLoop := InStr(paramArr[1], GetLang("循环"))
        Cmd := GetCmdOnlyText(paramArr[1])
        SerialStr := GetCmdStr(paramArr[1])
        if (IsSkip)
            return
        if (!IsSearch && !IsSearchPro && !IsSearchCombo && !IsIf && !IsLoop && !IsIfPro)
            return

        ParentID := this.MacroTreeViewCon.GetParent(root)
        while (ParentID != 0) {
            itemText := this.MacroTreeViewCon.GetText(ParentID)
            itemParamArr := StrSplit(itemText, "_")
            ParentID := this.MacroTreeViewCon.GetParent(ParentID)
            if (itemParamArr[1] == paramArr[1])
                return
        }

        Data := GetMacroCMDData(SerialStr)
        if (IsIf || IsSearch || IsSearchPro || IsSearchCombo) {
            TrueMacro := GetLangMacro(Data.TrueMacro, 1)
            FalseMacro := GetLangMacro(Data.FalseMacro, 1)

            iconStr := this.GetCmdIconStr(GetLang("真"))
            trueRoot := this.MacroTreeViewCon.Add(GetLang("真"), root, iconStr)
            ControlType := IsIf ? Data.TrueControlType : "无"
            this.TreeAddSubTree(trueRoot, TrueMacro)
            this.TreeAddControl(trueRoot, ControlType)

            iconStr := this.GetCmdIconStr(GetLang("假"))
            falseRoot := this.MacroTreeViewCon.Add(GetLang("假"), root, iconStr)
            ControlType := IsIf ? Data.FalseControlType : "无"
            this.TreeAddSubTree(falseRoot, FalseMacro)
            this.TreeAddControl(falseRoot, ControlType)
        }
        else if (IsLoop) {
            iconStr := this.GetCmdIconStr(GetLang("循环次数"))
            countStr := Data.LoopCount == -1 ? GetLang("无限") : Data.LoopCount
            CountRoot := this.MacroTreeViewCon.Add(Format("{}:{}", GetLang("⎖循环次数"), countStr), root, iconStr)

            if (CmdEnumZh(Data.CondiType, CmdEnumCondiNames()) != "无") {
                iconStr := this.GetCmdIconStr(GetLang("条件"))
                CondiStr := CmdEnumZh(Data.CondiType, CmdEnumCondiNames()) == "继续条件" ? GetLang("⎖继续条件：") : GetLang("⎖退出条件：")
                ItemStr := CondiStr . LoopData.GetCondiStr(Data)
                CondiRoot := this.MacroTreeViewCon.Add(ItemStr, root, iconStr)
            }

            iconStr := this.GetCmdIconStr(GetLang("循环体"))
            BodyRoot := this.MacroTreeViewCon.Add(GetLang("循环体"), root, iconStr)
            LoopBody := GetLangMacro(Data.LoopBody, 1)
            this.TreeAddSubTree(BodyRoot, LoopBody)
        }
        else if (IsIfPro) {
            iconStr := this.GetCmdIconStr(GetLang("条件"))
            loop Data.VariNameArr.Length {
                CondiStr := GetLang("条件：") CompareProData.GetCondiStr(Data, A_Index)
                CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
                MacroStr := GetLangMacro(Data.MacroArr[A_Index], 1)
                this.TreeAddSubTree(CondiRoot, MacroStr)
                this.TreeAddControl(CondiRoot, Data.ControlTypeArr[A_Index])
            }

            CondiStr := GetLang("条件：以上都不是")
            CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
            DefaultMacro := GetLangMacro(Data.DefaultMacro, 1)
            this.TreeAddSubTree(CondiRoot, DefaultMacro)
            this.TreeAddControl(CondiRoot, Data.DefaultControlType)
        }
    }

    TreeAddControl(root, ControlType) {
        if (ControlType == "无")
            return

        iconStr := this.GetCmdIconStr(GetLang("流程控制"))
        ItemStr := GetLang("⎖流程控制：") . GetLang(ControlType)
        this.MacroTreeViewCon.Add(ItemStr, root, iconStr)
    }

    TreeAddSubTree(root, CommandStr) {
        if (CommandStr == "")
            return

        cmdArr := SplitMacro(CommandStr)
        for cmdStr in cmdArr {
            ; 幂等迁移：清除历史遗留在分支数据里的当前位置标记 →
            cmdStr := CmdStripCurPos(cmdStr)
            iconStr := this.GetCmdIconStr(cmdStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(cmdStr)
            subRoot := this.MacroTreeViewCon.Add(displayStr, root, iconStr)
            this.TreeAddBranch(subRoot, cmdStr)
        }
    }
