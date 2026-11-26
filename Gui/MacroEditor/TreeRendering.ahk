
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
        cmdText := paramArr[1]

        if (SubStr(cmdText, 1, 2) == "🚫")
            return

        Cmd := GetCommandKey(GetCmdOnlyText(cmdText))

        IsSearch := Cmd == "搜索" || Cmd == "搜索Pro"
            || Cmd == "搜索All" || Cmd == "搜索Combo"
        IsIf := Cmd == "如果"
        IsIfPro := Cmd == "如果Pro"
        IsLoop := Cmd == "循环"

        if (!IsSearch && !IsIf && !IsIfPro && !IsLoop)
            return

        ; 避免重複建立相同命令的分支
        ParentID := this.MacroTreeViewCon.GetParent(root)
        while (ParentID) {
            if (StrSplit(this.MacroTreeViewCon.GetText(ParentID), "_")[1] == cmdText)
                return
            ParentID := this.MacroTreeViewCon.GetParent(ParentID)
        }

        Data := GetMacroCMDData(GetCmdStr(cmdText))

        ; 搜索无命中、未命中指令时不创建空分栏；有分支时保留真假对及其编辑入口。
        if (IsSearch && SplitMacro(Data.TrueMacro).Length == 0 && SplitMacro(Data.FalseMacro).Length == 0)
            return

        if (IsIf || IsSearch) {
            TrueRoot := this.MacroTreeViewCon.Add(
                GetLang("真"), root, this.GetCmdIconStr(GetLang("真")))
            FalseRoot := this.MacroTreeViewCon.Add(
                GetLang("假"), root, this.GetCmdIconStr(GetLang("假")))

            this.TreeAddSubTree(TrueRoot, GetLangMacro(Data.TrueMacro, 1))
            this.TreeAddSubTree(FalseRoot, GetLangMacro(Data.FalseMacro, 1))

            this.TreeAddControl(TrueRoot, IsIf ? Data.TrueControlType : "无")
            this.TreeAddControl(FalseRoot, IsIf ? Data.FalseControlType : "无")
        }
        else if (IsLoop) {
            iconStr := this.GetCmdIconStr(GetLang("循环次数"))
            countStr := Data.LoopCount == -1 ? GetLang("无限") : Data.LoopCount

            this.MacroTreeViewCon.Add(
                Format("{}:{}", GetLang("⎖循环次数"), countStr), root, iconStr)

            CondiType := CmdEnumZh(Data.CondiType, CmdEnumCondiNames())
            if (CondiType != "无") {
                CondiStr := CondiType == "继续条件"
                    ? GetLang("⎖继续条件：")
                    : GetLang("⎖退出条件：")
                ItemStr := CondiStr . LoopData.GetCondiStr(Data)

                this.MacroTreeViewCon.Add(ItemStr, root, this.GetCmdIconStr(GetLang("条件")))
            }

            BodyRoot := this.MacroTreeViewCon.Add(
                GetLang("循环体"), root, this.GetCmdIconStr(GetLang("循环体")))

            this.TreeAddSubTree(BodyRoot, GetLangMacro(Data.LoopBody, 1))
        }
        else if (IsIfPro) {
            iconStr := this.GetCmdIconStr(GetLang("条件"))

            loop Data.VariNameArr.Length {
                CondiStr := GetLang("条件：") . CompareProData.GetCondiStr(Data, A_Index)
                CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)

                this.TreeAddSubTree(CondiRoot, GetLangMacro(Data.MacroArr[A_Index], 1))
                this.TreeAddControl(CondiRoot, Data.ControlTypeArr[A_Index])
            }

            CondiRoot := this.MacroTreeViewCon.Add(
                GetLang("条件：以上都不是"), root, iconStr)

            this.TreeAddSubTree(CondiRoot, GetLangMacro(Data.DefaultMacro, 1))
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
