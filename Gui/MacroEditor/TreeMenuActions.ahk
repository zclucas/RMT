
    MenuHandler(cmdNextStr, *) {
        switch cmdNextStr {
            case GetLang("变量监视"):
            {
                if (MyVarListenGui.Gui != "" && MyVarListenGui.Gui.Hwnd) {
                    style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        this.ToolMenu.Uncheck(GetLang("变量监视"))
                        MyVarListenGui.Gui.Hide()
                        return
                    }
                }
                this.ToolMenu.Check(GetLang("变量监视"))
                MyVarListenGui.ShowGui()
            }
            case GetLang("指令显示"):
            {
                if (MyCMDTipGui.Gui != "" && MyCMDTipGui.Gui.Hwnd) {
                    style := WinGetStyle(MyCMDTipGui.Gui.Hwnd)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        MySoftData.CMDTip := false
                        SetCMDTipValue(false)
                        this.ToolMenu.Uncheck(GetLang("指令显示"))
                        MyCMDTipGui.Gui.Hide()
                        return
                    }
                }
                MySoftData.CMDTip := true
                SetCMDTipValue(true)
                MyCMDTipGui.ShowGui(GetLang("开启指令显示"))
                this.ToolMenu.Check(GetLang("指令显示"))
            }
            case GetLang("窗口置顶"):
            {
                this._topOn := !this._topOn
                if (IsObject(this.ui))
                    this.ui.Update("Window", "Topmost", this._topOn ? "True" : "False")
                this.ToolMenu.ToggleCheck(GetLang("窗口置顶"))
            }
            case this._DebugRunLabel():
            {
                item := this._SpecialItem()
                if (item && item.ColorState != 0)
                    return
                this.ResetDebugState()
                MacroStr := this.GetMacroStr()
                MacroStr := GetLangMacro(macroStr, 2)
                if (InStr(MacroStr, CmdDebugMark()))
                    MacroStr := StrSplit(MacroStr, CmdDebugMark(), 2)[2]
                else if (InStr(MacroStr, Chr(0x2B50)))
                    MacroStr := StrSplit(MacroStr, Chr(0x2B50), 2)[2]
                MyCMDTipGui.Hide()
                if (OnTriggerSepcialItemMacro(MacroStr))
                    Toast.Show(GetLang("调试运行结束"))
            }
            case this._ContinueLabel():
            {
                this.ContinueRun()
            }
            case this._StepOverLabel():
            {
                this.StepOver()
            }
            case this._StepIntoLabel():
            {
                this.StepInto()
            }
            case this._StepOutLabel():
            {
                this.StepOut()
            }
            case this._RunToCursorLabel():
            {
                this.RunToCursor()
            }
            case this._ToggleSkipLabel():
            {
                this.ToggleSkipSelected()
            }
            case GetLang("终止"):
            {
                KillSingleTableMacro(MySoftData.SpecialTableItem)
                this.ResetDebugState()
                if (MyCMDTipGui._IsVisible())
                    MyCMDTipGui.AddCMD(GetLang("终止"))
            }
        }
        this._SyncToolToggleDots()
    }

    ContentMenuHandler(cmdStr, *) {
        if (this._sideMode && !this._sideActive) {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin._sideTree)) {
                ed := MyMainWin._sideTree.ActiveEditor()
                if (IsObject(ed) && ed != this) {
                    ed.ContentMenuHandler(cmdStr)
                    return
                }
            }
            return
        }
        itemText := ""
        if (this.CurItemID)
            try itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        ; 清理→前缀用于状态判断
        cleanItemText := CmdStripCurPos(itemText)
        paramsArr := StrSplit(cmdStr, "_")
        if (paramsArr.Length == 2) {
            modeType := 5
            if (paramsArr[1] == "Pre")
                modeType := 3
            else if (paramsArr[1] == "Next")
                modeType := 4
            else if (paramsArr[1] == "Root")
                modeType := 1
            else if (paramsArr[1] == "Add")
                modeType := 5
            this.CmdEditType := modeType
            if (!this.SubGuiMap.Has(paramsArr[2]))
                return
            subGui := this.SubGuiMap[paramsArr[2]]
            this.OnOpenSubGui(subGui, modeType)
            return
        }

        switch cmdStr {
            case GetLang("编辑"):
            {
                paramsArr := StrSplit(cleanItemText, "_")
                cmd := GetCmdOnlyText(paramsArr[1])
                if (this._IsGraphStartCmd(cmd)) {
                    this._OpenGraphNodeEditor(GetCmdStr(paramsArr[1]), GetCmdSymbol(paramsArr[1]))
                    return
                }
                if (cmd == GetLang("运行") && this._RunNeedsProEditor(GetCmdStr(paramsArr[1])))
                    cmd := GetLang("运行Pro")
                if (cmd == GetLang("搜索Pro") && this._SearchNeedsMultiEditor(GetCmdStr(paramsArr[1])))
                    cmd := GetLang("搜索Combo")
                if (PromptUsesEditor(GetCmdStr(cleanItemText)))
                    cmd := GetLang("提示")
                if (!this.SubGuiMap.Has(cmd))
                    return
                subGui := this.SubGuiMap[cmd]
                this.OnOpenSubGui(subGui, 2)
            }
            case "Skip":
            {
                ; 薄封装：与 Ctrl+/ 同源（单条走 ids=[CurItemID]，语义完全一致）
                this.ToggleSkipSelected()
            }
            case "Debug":
                if (SubStr(cleanItemText, 1, 2) == "🚫") {
                    RmtDialog.Info(GetLang("跳过指令不可设置为调试起点"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                IsToDebug := !CmdIsDebug(cleanItemText)
                ; 解 G10：调试起点全局互斥——设新起点前先清除其它节点的 ▶/⭐，避免多起点并存
                if (IsToDebug)
                    this.ClearOtherDebugStarts(this.CurItemID)
                CommandStr := IsToDebug ? CmdDebugMark() cleanItemText : CmdStripDebug(cleanItemText)
                ; 调试标记是持久标记，由F6单步时FindDebugStartItem查找，不直接设DebugItemID
                this.OnModifyCmd(CommandStr)
            case "Bp":
            {
                ; F3：未接线持久化的实例不响应（与菜单隐藏双保险，杜绝误设静默丢失）
                if (!this._bpAllowed)
                    return
                ; 断点开关：🚫 禁用项 / ⎖ 配置行不可设断点（弹提示，不生效）
                if (SubStr(cleanItemText, 1, 2) == "🚫") {
                    RmtDialog.Info(GetLang("跳过指令不可设置断点"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                if (SubStr(cleanItemText, 1, 1) == "⎖") {
                    RmtDialog.Info(GetLang("该行不可设置断点"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                if (!this.CurItemID)
                    return
                ; 纯字段切换（独立 Brk_ 图标通道），绝不写 node.text
                curOn := this.MacroTreeViewCon.IsBreakPoint(this.CurItemID)
                this.MacroTreeViewCon.SetBreakPoint(this.CurItemID, !curOn)
                this._NotifyBpChanged()
            }
            case GetLang("复制"):
            {
                selectedItems := this.GetMultiSelectedItems()
                if (selectedItems.Length <= 1) {
                    newCmd := FullCopyCmd(cleanItemText)
                    SetClipboard(newCmd)
                    Toast.Show(GetLang("已复制"))
                    return
                }

                ; 多選複製：依 TreeView 中的原始順序輸出，以逗號組成可再次 SplitMacro() 的宏字串。
                copyStr := ""
                for itemID in selectedItems {
                    try {
                        text := this.MacroTreeViewCon.GetText(itemID)
                    } catch {
                        continue
                    }
                    text := CmdStripCurPos(CmdStripDebug(text))
                    if (text == "" || SubStr(text, 1, 1) == "⎖")
                        continue
                    cmd := FullCopyCmd(text)
                    if (cmd != "")
                        copyStr .= (copyStr == "" ? "" : ",") cmd
                }
                if (copyStr != "") {
                    SetClipboard(copyStr)
                    Toast.Show(GetLang("已复制"))
                }
            }
            case GetLang("粘贴"):
            {
                this.PasteClipboardCommands(A_Clipboard)
                if (Trim(A_Clipboard, " `t`r`n") != "")
                    Toast.Show(GetLang("已粘贴"))
            }
            case "SharedCopy":
            {
                ; 共享复制：原样复制指令文本，不重新分配内部序列号，方便分享到其他宏/其他设备
                selectedItems := this.GetMultiSelectedItems()
                if (selectedItems.Length <= 1) {
                    SetClipboard(cleanItemText)
                    Toast.Show(GetLang("已复制"))
                    return
                }

                copyStr := ""
                for itemID in selectedItems {
                    try {
                        text := this.MacroTreeViewCon.GetText(itemID)
                    } catch {
                        continue
                    }
                    text := CmdStripCurPos(CmdStripDebug(text))
                    if (text == "" || SubStr(text, 1, 1) == "⎖")
                        continue
                    if (text != "")
                        copyStr .= (copyStr == "" ? "" : ",") text
                }
                if (copyStr != "")
                    SetClipboard(copyStr)
                Toast.Show(GetLang("已复制"))
            }
            case "BranchCopy":
            {
                ; 分支／循环体容器不是实际指令，复制时应复制其内部宏内容。
                if (!this.IsContainerNode(cleanItemText))
                    return

                branchMacroStr := this.GetTreeMacroStr(this.CurItemID)
                if (branchMacroStr == "") {
                    SetClipboard("")
                } else {
                    cmds := SplitMacro(branchMacroStr)
                    copyStr := ""
                    for _, text in cmds {
                        text := Trim(text, " `t`r`n")
                        if (text == "")
                            continue
                        text := CmdStripCurPos(CmdStripDebug(text))
                        cmd := FullCopyCmd(text)
                        if (cmd != "")
                            copyStr .= (copyStr == "" ? "" : ",") cmd
                    }
                    SetClipboard(copyStr)
                }
                Toast.Show(GetLang("已复制"))
            }
            case "BranchSharedCopy":
            {
                ; 共享复制保留分支內部的原始宏文字，不重新分配内部序列号。
                if (!this.IsContainerNode(cleanItemText))
                    return

                branchMacroStr := this.GetTreeMacroStr(this.CurItemID)
                SetClipboard(branchMacroStr)
                Toast.Show(GetLang("已复制"))
                return
            }
            case GetLang("删除"):
            {
                this.OnDeleteCmd()
            }
        }
    }
