
    InitMacroText(MacroStr) {
        this.MacroEditTextCon.Visible := this.EditModeCon.Value == 2

        content := RegExReplace(MacroStr, "[,，⫶]", "`n")
        this.MacroEditTextCon.Value := content
    }

    ShowContextMenu(ctrl, item, isRightClick, x, y) {
        if (item == 0)
            return

        ; 检查配置是否变化，若变化则废弃缓存重建
        genCfg := MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : ""
        if (this._lastGenCfg != genCfg)
            this.ContextMenu := ""

        if (this.ContextMenu == "") {
            this._lastGenCfg := genCfg
            this.ContextMenu := Menu()
            this.ContextMenu.IsSkip := true
            this.ContextMenu.IsDebug := true

            ; 构建插入指令子菜单（固定）
            insertSubMenu := Menu()
            for index, value in this.CMDStrArr {
                insertSubMenu.Add(value, this.ContentMenuHandler.Bind(this, "Next_" value))
                insertSubMenu.SetIcon(value, this.CMDIconFileArr[index])
            }

            ; 从配置加载顺序，若无则使用默认顺序
            genKeys := (genCfg != "") ? StrSplit(genCfg, ",") : ["Edit", "Skip", "Debug", "Separator", "Insert", "Separator", "Copy", "SharedCopy", "Paste", "Separator", "Delete"]

            for k in genKeys {
                switch k {
                    case "Separator":
                        this.ContextMenu.Add()
                    case "Edit":
                        this.ContextMenu.Add(GetLang("编辑"), (*) => this.ContentMenuHandler(GetLang("编辑")))
                    case "Skip":
                        this.ContextMenu.Add(GetLang("跳过指令"), (*) => this.ContentMenuHandler("Skip"))
                    case "Debug":
                        this.ContextMenu.Add(GetLang("调试起点"), (*) => this.ContentMenuHandler("Debug"))
                    case "Insert":
                        this.ContextMenu.Add(GetLang("插入指令"), insertSubMenu)
                    case "Copy":
                        this.ContextMenu.Add(GetLang("复制"), (*) => this.ContentMenuHandler(GetLang("复制")))
                    case "SharedCopy":
                        this.ContextMenu.Add(GetLang("共享复制"), (*) => this.ContentMenuHandler("SharedCopy"))
                    case "Paste":
                        this.ContextMenu.Add(GetLang("粘贴"), (*) => this.ContentMenuHandler(GetLang("粘贴")))
                    case "Delete":
                        this.ContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
                }
            }
        }

        ; 检查分支菜单配置是否变化
        branchCfg := MainSoftData.HasProp("BranchContextMenu") ? MainSoftData.BranchContextMenu : ""
        if (this._lastBranchCfg != branchCfg)
            this.BranchContextMenu := ""

        if (this.BranchContextMenu == "") {
            this._lastBranchCfg := branchCfg
            this.BranchContextMenu := Menu()

            ; 构建添加指令子菜单（固定）
            addSubMenu := Menu()
            for index, value in this.CMDStrArr {
                addSubMenu.Add(value, this.ContentMenuHandler.Bind(this, "Add_" value))
                addSubMenu.SetIcon(value, this.CMDIconFileArr[index])
            }

            ; 从配置加载顺序
            branchKeys := (branchCfg != "") ? StrSplit(branchCfg, ",") : ["Add", "Separator", "BranchCopy", "BranchSharedCopy", "Paste", "Separator", "Delete"]

            for k in branchKeys {
                switch k {
                    case "Separator":
                        this.BranchContextMenu.Add()
                    case "Add":
                        this.BranchContextMenu.Add(GetLang("添加指令"), addSubMenu)
                    case "BranchCopy":
                        this.BranchContextMenu.Add(GetLang("复制"), (*) => this.ContentMenuHandler("BranchCopy"))
                    case "BranchSharedCopy":
                        this.BranchContextMenu.Add(GetLang("共享复制"), (*) => this.ContentMenuHandler("BranchSharedCopy"))
                    case "Paste":
                        this.BranchContextMenu.Add(GetLang("粘贴"), (*) => this.ContentMenuHandler(GetLang("粘贴")))
                    case "Delete":
                        this.BranchContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
                }
            }
        }

        ; 右鍵只設定「右鍵操作目標」，絕對不改變目前多選狀態。
        ; MultiSelectItems / TreeView Select 狀態都保持原樣。
        this.CurItemID := item
        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        cleanItemText := CmdStripCurPos(itemText)
        isCondi := SubStr(cleanItemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        ; 清理→前缀用于菜单状态判断（→是运行时临时标记，不影响逻辑状态）
        if (cleanItemText == "" || SubStr(cleanItemText, 1, 1) == "⎖")
            return
        else if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体") || isCondi) {
            this.BranchContextMenu.Show(x, y)
        }
        else {
            CurSkipMenuText := this.ContextMenu.IsSkip ? GetLang("跳过指令") : GetLang("取消跳过")
            SkipMenuText := SubStr(cleanItemText, 1, 2) == "🚫" ? GetLang("取消跳过") : GetLang("跳过指令")
            if (CurSkipMenuText != SkipMenuText) {
                this.ContextMenu.Rename(CurSkipMenuText, SkipMenuText)
                this.ContextMenu.IsSkip := !this.ContextMenu.IsSkip
            }

            CurDebugMenuText := this.ContextMenu.IsDebug ? GetLang("调试起点") : GetLang("取消调试起点")
            DebugMenuText := CmdIsDebug(cleanItemText) ? GetLang("取消调试起点") : GetLang("调试起点")
            if (CurDebugMenuText != DebugMenuText) {
                this.ContextMenu.Rename(CurDebugMenuText, DebugMenuText)
                this.ContextMenu.IsDebug := !this.ContextMenu.IsDebug
            }

            this.ContextMenu.Show(x, y)
        }
    }

    _OnHotkey(key) {
        ; 去掉 ~ / $ 前缀后再比较（$ 用于防止 Send 再次触发自身热键）
        rawKey := key
        key := LTrim(key, "~$")
        ; 焦点在主窗口文本输入框里时，编辑类按键必须交还 WPF 原生处理：
        ; 本组热键（侧栏模式）注册在主窗口上且 $ 吞键，否则设置页等输入框无法复制/粘贴/撤销
        if (this._PassEditKeyToTextInput(key)) {
            Send(key)
            return
        }
        if (this._sideMode && !this._sideActive) {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && (!MyMainWin.aiAssistOpen || MyMainWin.sidePanelMode != 1))
                return
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin._sideTree)) {
                ed := MyMainWin._sideTree.ActiveEditor()
                if (IsObject(ed) && ed != this) {
                    ed._OnHotkey(rawKey)
                    return
                }
            }
            return
        }
        if (this._sideMode && IsSet(MyMainWin) && IsObject(MyMainWin) && (!MyMainWin.aiAssistOpen || MyMainWin.sidePanelMode != 1))
            return
        if (StrLower(key) == StrLower(this._GetContinueHotkey()))
            this.MenuHandler(this._ContinueLabel())
        else if (StrLower(key) == StrLower(this._GetStepOverHotkey()))
            this.MenuHandler(this._StepOverLabel())
        else if (StrLower(key) == StrLower(this._GetStepIntoHotkey()))
            this.MenuHandler(this._StepIntoLabel())
        else if (StrLower(key) == StrLower(this._GetStepOutHotkey()))
            this.MenuHandler(this._StepOutLabel())
        else if (StrLower(key) == StrLower(this._GetRunToCursorHotkey()))
            this.MenuHandler(this._RunToCursorLabel())
        else if (StrLower(key) == StrLower(this._GetToggleSkipHotkey()))
            this.MenuHandler(this._ToggleSkipLabel())
        else if (StrLower(key) == StrLower(this._GetRunAllHotkey()))
            this.MenuHandler(this._DebugRunLabel())
        else if (key == "Delete") {
            this.OnDeleteCmd()
        }
        else if (key == "^c") {
            ; 逻辑树模式：复制选中指令；文本模式：交还编辑框原生复制
            ; 非透传（无 ~）会吞掉按键，避免树控件收到 Ctrl+C 后响铃
            if (!this.MacroTreeViewCon.Visible)
                Send("^c")
            else if (this.CurItemID)
                this.ContentMenuHandler(GetLang("复制"))
        }
        else if (key == "^v") {
            if (!this.MacroTreeViewCon.Visible)
                Send("^v")
            else
                ; 空树/无选中时也允许粘贴到根层
                this.ContentMenuHandler(GetLang("粘贴"))
        }
        else if (key == "^z") {
            ; 文本模式：交还编辑框原生撤销；逻辑树模式：走快照撤销栈
            if (!this.MacroTreeViewCon.Visible)
                Send("^z")
            else
                this.Undo()
        }
        else if (key == "^y") {
            if (!this.MacroTreeViewCon.Visible)
                Send("^y")
            else
                this.Redo()
        }
    }

    ; 主窗口文本框正在编辑时，编辑类按键应交给 WPF 原生处理
    ; （侧栏模式把 $^c/$^v/$^z/$^y/Delete 注册在主窗口 hwnd 上，$ 会吞键且不转发）
    _PassEditKeyToTextInput(key) {
        if (!this._sideMode)
            return false
        if (key != "^c" && key != "^v" && key != "^z" && key != "^y" && key != "Delete")
            return false
        if (!IsSet(MyMainWin) || !IsObject(MyMainWin))
            return false
        return MyMainWin.HasProp("_textFocusName") && MyMainWin._textFocusName != ""
    }

    OnSoftKey(key, isDown) {
        if (!isDown)
            return

        if (StrLower(key) == StrLower(this._GetContinueHotkey()))
            this.MenuHandler(this._ContinueLabel())
        if (StrLower(key) == StrLower(this._GetStepIntoHotkey()))
            this.MenuHandler(this._StepIntoLabel())
        if (key == "delete") {
            try {
                focusedHwnd := DllCall("GetFocus", "Ptr")
                if (focusedHwnd = this.MacroTreeViewCon.hwnd)
                    this.OnDeleteCmd()
            }
        }
    }

    ; 从事件 state 读坐标。优先用绑定控件本地 DIP（控件名键），DragCoords 是窗口坐标，侧栏树偏移后不能拿来做 HitTest。
    _EventCoord(state, ctrlName) {
        coord := ""
        if (IsObject(state) && ctrlName != "" && state.Has(ctrlName))
            coord := state[ctrlName]
        else if (IsObject(state) && state.Has("DragCoords"))
            coord := state["DragCoords"]
        if (coord == "")
            return ""
        parts := StrSplit(coord, ",")
        if (parts.Length != 2)
            return ""
        return Trim(parts[1]) ";" Trim(parts[2])
    }

    ; 命中测试（坐标相对 ctrlName），返回 "tag|top/bottom" 或 ""
    _HitTest(ctrlName, coord) {
        if (!IsObject(this.ui) || coord == "")
            return ""
        return this.ui.Query(ctrlName ">HitTest:" coord)
    }

    _ApplyTreeDoubleClick() {
        state := this._dblState
        this._dblState := ""
        if (!IsObject(state))
            return
        this._OnTreeDoubleClick(state, "", "")
    }

    ; WPF 树双击：命中测试定位节点打开编辑器；WPF 默认双击展开/折叠，定向还原到双击前状态（不整树重渲染）
    _OnTreeDoubleClick(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        coord := this._EventCoord(state, this.treeName)
        if (coord == "")
            return
        ; 引擎在按下事件里带了命中行，优先用它，不用再发同步查询
        tagSlot := (IsObject(state) && state.Has("HitTag")) ? String(state["HitTag"]) : ""
        if (tagSlot == "")
            tagSlot := this._HitTest(this.treeName, coord)
        if (tagSlot == "")
            return
        hit := this._ResolveHit(tagSlot, coord)
        itemID := hit.id
        if (itemID == "")
            return
        ; 点在展开箭头上：只折叠，不打开编辑器；叶子无子节点则正常打开编辑器
        if (hit.expander && this.MacroTreeViewCon.GetChild(itemID) != 0)
            return
        this.OnDoubleClick(this.MacroTreeViewCon, itemID)
    }

    ; WPF 树左键按下：只负责双击与点选，拖拽已交给引擎（见 _BindTreeInteractionEvents 的 TreeDrag）
    _OnTreePreviewLeftDown(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        ; 双击：打开编辑器（C# 已对树条目双击置 Handled，阻止展开/折叠切换）
        clickCount := 1
        if (IsObject(state) && state.Has("ClickCount")) {
            cc := state["ClickCount"]
            if (IsNumber(cc))
                clickCount := Integer(cc)
        }
        if (clickCount >= 2) {
            ; 命中测试要查引擎，不能在事件回调里同步做，转伪线程
            this._dblState := state
            SetTimer(this._dblTick, -1)
            return
        }
        ; 点选：延后一拍，等 ListBox 完成原生选中后再做多选/分栏按钮处理
        this._treeClickCoord := this._EventCoord(state, this.treeName)
        ; 引擎在按下事件里已经把命中行的 Tag 带回来了，不用再发一条同步查询
        this._treeDownHit := (IsObject(state) && state.Has("HitTag")) ? String(state["HitTag"]) : ""
        SetTimer(ObjBindMethod(this, "_ProcessTreeLeftClick"), -20)
    }

    ; 左面板按钮按下：把"拖的是哪条指令"交给引擎，由引擎在窗口内跟手并在松手时回报落点
    _OnPanelDragStart(guiInstance, displayName, state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        this._extDragGui := guiInstance
        ; value = 目标树名|幽灵文本|插入线名|幽灵名|幽灵文本名
        try this.ui.Update("Window", "TreeDragExternal"
            , this.treeName "|" displayName "|" this.insertLineName "|" this.dragGhostName "|" this.dragGhostTxtName)
    }

    ; ==== 拖拽结果（命中/插入线/幽灵都在引擎内跑完，这里只落模型）====

    _OnTreeDragStartNative(state, ctrl, event) {
        ; 拖拽期间禁整棵重建：树一重建，源行和落点就都对不上了
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := true
    }

    _OnTreeDragCancelNative(state, ctrl, event) {
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
    }

    ; 复位拖拽态：窗口关闭/重建等路径会调。引擎侧由它自己的 Up/Cancel 收尾，
    ; 这里只把可能遗留的插入线和幽灵收掉，免得下次开窗看到残影。
    _DragEndReset() {
        if (IsObject(this.ui)) {
            try this.ui.Update(this.insertLineName, "Visibility", "Collapsed")
            try this.ui.Update(this.dragGhostName, "IsOpen", "False")
        }
    }

    ; 树内拖拽：payload = "source|target|slot"
    _OnTreeDropCommitted(state, ctrl, event) {
        raw := IsObject(state) && state.Has("TreeDrop") ? state["TreeDrop"] : ""
        this._OnTreeDragCancelNative(state, ctrl, event)
        if (raw == "")
            return
        parts := StrSplit(raw, "|")
        if (parts.Length < 2)
            return
        this._MoveTreeNodeTo(parts[1], parts[2], parts.Length >= 3 ? parts[3] : "")
    }

    ; 左侧指令拖进树：payload = "|target|slot"（source 为空），落点决定插入方式
    _OnTreeDropExternal(state, ctrl, event) {
        raw := IsObject(state) && state.Has("TreeDropExternal") ? state["TreeDropExternal"] : ""
        ; 拖拽已落定，吞掉紧随其后的那次 Click，否则会再开一次「新增指令」
        this._dragCancelledAt := A_TickCount
        this._OnTreeDragCancelNative(state, ctrl, event)
        gui := this._extDragGui
        this._extDragGui := ""
        if (!IsObject(gui))
            return
        parts := raw == "" ? [] : StrSplit(raw, "|")
        target := parts.Length >= 2 ? parts[2] : ""
        slot := parts.Length >= 3 ? parts[3] : ""
        this.CurItemID := target
        if (target == "") {
            this.OnOpenSubGui(gui, 1)
            return
        }
        text := this.MacroTreeViewCon.GetText(target)
        if (SubStr(CmdStripCurPos(text), 1, 1) == "⎖")
            return
        if (this.IsContainerNode(text)) {
            this.OnOpenSubGui(gui, 5)
        } else {
            this.OnOpenSubGui(gui, slot == "top" ? 3 : 4)
        }
    }

    ; 树内移动：target 为空 = 移到根部末尾；容器 = 放进去；普通行 = 插到上/下
    _MoveTreeNodeTo(source, target, slot) {
        if (source == "")
            return
        if (this._IsImmovableNode(this.MacroTreeViewCon.GetText(source)))
            return
        if (target == "") {
            this.MoveTreeViewItem(source, 0, 0, 1)
            return
        }
        if (target == source)
            return
        if (this.IsDescendantOrSelf(this.MacroTreeViewCon, source, target))
            return
        text := this.MacroTreeViewCon.GetText(target)
        if (this._IsImmovableNode(text) && !this.IsContainerNode(text))
            return
        if (this.IsContainerNode(text)) {
            this.MoveTreeViewItem(source, target, target, 5)
        } else {
            destParent := this.MacroTreeViewCon.GetParent(target)
            this.MoveTreeViewItem(source, destParent, target, slot == "top" ? 3 : 4)
        }
    }

    _ProcessTreeLeftClick() {
        if (!IsObject(this.ui))
            return
        coord := this._treeClickCoord
        if (coord == "")
            return
        tagSlot := this._treeDownHit
        this._treeDownHit := ""
        if (tagSlot == "")
            tagSlot := this._HitTest(this.treeName, coord)
        if (tagSlot == "") {
            this._ClearTreeSelection()
            return
        }
        hit := this._ResolveHit(tagSlot, coord)
        itemID := hit.id
        if (itemID == "") {
            this._ClearTreeSelection()
            return
        }
        ; 点在展开箭头上：切换展开/折叠（扁平列表无 WPF 原生箭头）；叶子无子节点则落到下方正常选择
        if (hit.expander) {
            if (this.MacroTreeViewCon.GetChild(itemID) != 0) {
                this.MacroTreeViewCon.Modify(itemID, this.MacroTreeViewCon.IsExpanded(itemID) ? "Collapse" : "Expand")
                return
            }
        }
        if (GetKeyState("Shift", "P"))
            this.SelectMultiRange(this.MultiSelectAnchor, itemID)
        else if (GetKeyState("Ctrl", "P"))
            this.ToggleMultiSelection(itemID)
        else
            this.SetSingleMultiSelection(itemID)
        this.CurItemID := itemID
        this.MacroTreeViewCon.Modify(itemID, "Select")
        try this.MacroTreeViewCon.Focus()
    }

    _ClearTreeSelection() {
        this.ClearMultiSelection()
        this.CurItemID := 0
        if (IsObject(this.MacroTreeViewCon) && this.MacroTreeViewCon.HasMethod("Unselect"))
            this.MacroTreeViewCon.Unselect()
        else if (IsObject(this.ui))
            try this.ui.Update(this.treeName, "SelectedIndex", "-1")
    }

    _OnTreePreviewKeyDown(state, ctrl, event) {
        if (this.EditModeCon.Value != 1)
            return
        if (this._sideMode && !this._sideActive) {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin._sideTree)) {
                ed := MyMainWin._sideTree.ActiveEditor()
                if (IsObject(ed) && ed != this) {
                    ed._OnTreePreviewKeyDown(state, ctrl, event)
                    return
                }
            }
            return
        }
        key := ""
        if (IsObject(event)) {
            if (event.HasProp("Key"))
                key := String(event.Key)
        } else if (event != "") {
            key := String(event)
            if (InStr(key, ":"))
                key := StrSplit(key, ":")[2]
        }
        mods := ""
        if (IsObject(state) && state.Has("KeyModifiers"))
            mods := state["KeyModifiers"]
        hasCtrl := InStr(mods, "Ctrl")
        if (key == "Delete" && !hasCtrl)
            this.OnDeleteCmd()
        else if (hasCtrl && (key == "C" || key == "c"))
            this.ContentMenuHandler(GetLang("复制"))
        else if (hasCtrl && (key == "V" || key == "v"))
            this.ContentMenuHandler(GetLang("粘贴"))
        else if (hasCtrl && (key == "Z" || key == "z"))
            this.Undo()
        else if (hasCtrl && (key == "Y" || key == "y"))
            this.Redo()
    }

    ; WPF 树右键按下：记录命中坐标，延迟弹右键菜单（命中不到节点不弹，不误改多选）
    _OnTreePreviewRightDown(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        this._rightClickCoord := this._EventCoord(state, this.treeName)
        this._rightDownHit := (IsObject(state) && state.Has("HitTag")) ? String(state["HitTag"]) : ""
        SetTimer(ObjBindMethod(this, "_ProcessTreeRightClick"), -20)
    }

    _ProcessTreeRightClick() {
        if (!IsObject(this.ui))
            return
        if (this._sideMode && !this._sideActive) {
            if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin._sideTree)) {
                ed := MyMainWin._sideTree.ActiveEditor()
                if (IsObject(ed) && ed != this) {
                    ed._rightClickCoord := this._rightClickCoord
                    ed._rightDownHit := this._rightDownHit
                    this._rightClickCoord := ""
                    this._rightDownHit := ""
                    ed._ProcessTreeRightClick()
                    return
                }
            }
        }
        coord := this._rightClickCoord
        this._rightClickCoord := ""
        if (coord == "")
            return
        tagSlot := this._rightDownHit
        this._rightDownHit := ""
        if (tagSlot == "")
            tagSlot := this._HitTest(this.treeName, coord)
        if (tagSlot == "") {
            this._ClearTreeSelection()
            this._OpenCtxMenu(this.blankCtxMenuName)
            return
        }
        itemID := this._ResolveHit(tagSlot, coord).id
        if (itemID == "") {
            this._ClearTreeSelection()
            this._OpenCtxMenu(this.blankCtxMenuName)
            return
        }
        this.SetSingleMultiSelection(itemID)
        this.CurItemID := itemID
        this.MacroTreeViewCon.Modify(itemID, "Select")
        try this.MacroTreeViewCon.Focus()
        itemText := this.MacroTreeViewCon.GetText(itemID)
        cleanItemText := CmdStripCurPos(itemText)
        if (cleanItemText == "" || SubStr(cleanItemText, 1, 1) == "⎖") {
            this.CurItemID := 0
            this._OpenCtxMenu(this.blankCtxMenuName)
            return
        }
        if (this.IsContainerNode(itemText)) {
            this._OpenCtxMenu(this.branchCtxMenuName)
            return
        }
        SkipMenuText := SubStr(cleanItemText, 1, 2) == "🚫" ? GetLang("取消跳过") : GetLang("跳过指令")
        DebugMenuText := CmdIsDebug(cleanItemText) ? GetLang("取消调试起点") : GetLang("调试起点")
        this.ui.Update(this.menuSkipName, "Header", SkipMenuText)
        this.ui.Update(this.menuDebugName, "Header", DebugMenuText)
        this._OpenCtxMenu(this.ctxMenuName)
    }

    _OpenCtxMenu(menuName) {
        if (!IsObject(this.ui) || menuName == "")
            return
        this._SyncCtxMenuFont(menuName)
        try this.ui.Update(menuName, "IsOpen", "True")
    }

    OnDoubleClick(ctrl, item) {
        if (item == 0)
            return
        this._DragEndReset()

        itemText := this.MacroTreeViewCon.GetText(item)
        if (itemText == "" || SubStr(itemText, 1, 1) == "⎖")
            return

        this.CurItemID := item
        if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体")) {
            if (this.SubMacroEditGui == "")
                this.SubMacroEditGui := MacroEditGui()

            macroStr := this.GetTreeMacroStr(this.CurItemID)
            ; F3：分支体子编辑器接入断点 —— 显示「断点」菜单；清空起始断点串避免重开串味；
            ; 保存时经 _OnSubEditorSure 把本次新增断点并入父树（见 _IngestChildBreakpoints）
            nodeID := this.CurItemID
            this.SubMacroEditGui._bpAllowed := true
            this.SubMacroEditGui._bpStr := ""
            this.SubMacroEditGui.SureBtnAction := (m) => this._OnSubEditorSure(nodeID, m, this.SubMacroEditGui)
            this.SubMacroEditGui.SureFocusCon := this.MacroTreeViewCon
            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.SubMacroEditGui.ParentTile := ParentTile "-"

            if (MainSoftData.IsModalSubGui && this.Gui != "") {
                this.SubMacroEditGui.OwnerHwnd := this.Gui.Hwnd
            }
            else {
                this.SubMacroEditGui.OwnerHwnd := ""
            }

            this.SubMacroEditGui.ShowGui(macroStr, false, this.WindowBindingContext)
            return
        }
        else if (SubStr(itemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")) {
            if (this.CompareProEditItemGui == "")
                this.CompareProEditItemGui := CompareProEditItemGui()
            this.CompareProEditItemGui.IsSubMacroEdit := true
            this.CompareProEditItemGui.WindowBindingContext := this.WindowBindingContext
            this.CompareProEditItemGui.SureBtnAction := this.OnSubNodeEdit.Bind(this, this.CurItemID)

            if (MainSoftData.IsModalSubGui && this.Gui != "") {
                this.CompareProEditItemGui.OwnerHwnd := this.Gui.Hwnd
            }
            else {
                this.CompareProEditItemGui.OwnerHwnd := ""
            }

            ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
            CommndStr := this.MacroTreeViewCon.GetText(ParentID)
            ItemNumber := this.GetItemNumber(this.CurItemID)
            this.CompareProEditItemGui.MacroEditShowGui(CommndStr, ItemNumber)
            return
        }

        ; 清理→前缀（⭐/🚫 由 GetCmdOnlyText / GetCmdStr 处理）
        cleanText := CmdStripCurPos(itemText)
        paramsArr := StrSplit(cleanText, "_")
        cmd := GetCmdOnlyText(paramsArr[1])
        ; 图形开始节点：用节点编辑器打开，不走普通指令 SubGui
        if (this._IsGraphStartCmd(cmd)) {
            this._OpenGraphNodeEditor(GetCmdStr(paramsArr[1]), GetCmdSymbol(paramsArr[1]))
            return
        }
        itemCmd := MySoftData.ParseCmdJoyDisplay(GetCmdStr(cleanText))
        itemCmd := MySoftData.CmdJoyNToJoyFriendly(itemCmd)
        if (cmd == GetLang("按键") && IsJoyLegacyKeyCmd(itemCmd))
            cmd := GetLang("手柄")
        if (cmd == GetLang("运行") && this._RunNeedsProEditor(GetCmdStr(cleanText)))
            cmd := GetLang("运行Pro")
        if (cmd == GetLang("搜索Pro") && this._SearchNeedsMultiEditor(GetCmdStr(cleanText)))
            cmd := GetLang("搜索Combo")
        if (!this.SubGuiMap.Has(cmd))
            return
        subGui := this.SubGuiMap[cmd]
        this.OnOpenSubGui(subGui, 2)
    }

    ; 旧多目标「搜索Pro」打开搜索Combo，避免单目标编辑器丢掉其余目标
    _SearchNeedsMultiEditor(cmdStr) {
        paramArr := StrSplit(GetCmdStr(cmdStr), "_")
        if (paramArr.Length < 1)
            return false
        try data := GetMacroCMDData(paramArr[1])
        catch
            return false
        if (!IsObject(data) || !ObjHasOwnProp(data, "SearchTargetArr") || !IsObject(data.SearchTargetArr))
            return false
        return data.SearchTargetArr.Length > 1
    }

    ; 旧「运行」若带 Pro 字段（模式/窗口/管道），编辑时打开运行Pro，避免保存时丢掉参数
    _RunNeedsProEditor(cmdStr) {
        paramArr := StrSplit(GetCmdStr(cmdStr), "_")
        if (paramArr.Length < 1)
            return false
        try data := GetMacroCMDData(paramArr[1])
        catch
            return false
        if (!IsObject(data))
            return false
        if (ObjHasOwnProp(data, "Mode") && IsNumber(data.Mode) && Integer(data.Mode) > 1)
            return true
        if (ObjHasOwnProp(data, "Option") && IsNumber(data.Option) && Integer(data.Option) != 1)
            return true
        return ObjHasOwnProp(data, "StdIn") || ObjHasOwnProp(data, "SaveNameArr") || ObjHasOwnProp(data, "Encoding")
    }

    ; 是否为「图形开始节点」序列码（逻辑树中的图入口指令）
    _IsGraphStartCmd(cmd) {
        key := GetLangKey(cmd)
        return key == "图形开始节点" || cmd == GetLang("图形开始节点")
    }

    ; 双击/编辑：打开嵌套节点编辑器，编辑该图形开始节点子图
    _OpenGraphNodeEditor(cmdStr, symbol := "") {
        itemId := this.CurItemID
        parentId := this.MacroTreeViewCon.GetParent(itemId)
        serial := GetLangMacro(cmdStr, 2)
        if (this.SubMacroGraphGui == "")
            this.SubMacroGraphGui := MacroGraphGui()
        this.SubMacroGraphGui.OwnerHwnd := (MainSoftData.IsModalSubGui && this.Gui != "") ? this.Gui.Hwnd : ""
        this.SubMacroGraphGui.ShowToTreeBtn := true
        this.SubMacroGraphGui.OnClosedAction := ""
        this.SubMacroGraphGui.SureBtnAction := (startSerial) => this._OnGraphNodeEditorSure(itemId, startSerial, symbol)
        ; 「逻辑树」：把该子图转成线性宏写回当前逻辑树（循环体等），不打开顶层编辑器
        this.SubMacroGraphGui.OnSwitchToTreeAction := (linear) => this._OnGraphNodeSwitchToTree(parentId, itemId, linear)
        this.SubMacroGraphGui.ShowGui(serial, this.WindowBindingContext)
    }

    ; 嵌套节点编辑器点「逻辑树」：子图转线性后写回所属分支并刷新树
    _OnGraphNodeSwitchToTree(parentId, itemId, linear) {
        displayLinear := GetLangMacro(linear, 1)
        if (displayLinear == "")
            displayLinear := " "
        if (parentId != 0) {
            try this.MacroTreeViewCon.GetText(parentId)
            catch
                return
            this.OnSubNodeEdit(parentId, displayLinear)
            return
        }
        ; 根级图形开始节点：用线性宏替换该节点（整段转线性记一次撤销）
        try this.MacroTreeViewCon.GetText(itemId)
        catch
            return
        this._PushUndo()
        this._BeginUndoBatch()
        this.CurItemID := itemId
        cmds := SplitMacro(displayLinear)
        if (cmds.Length == 0) {
            this.OnDeleteCmd()
            this._EndUndoBatch()
            return
        }
        this.OnModifyCmd(cmds[1])
        loop cmds.Length - 1 {
            this.OnNextInsertCmd(cmds[A_Index + 1])
            ; OnNextInsertCmd 后 CurItemID 仍指向原节点；插在其后需推进选中
            nextId := this.MacroTreeViewCon.GetNext(this.CurItemID)
            if (nextId)
                this.CurItemID := nextId
        }
        this._EndUndoBatch()
    }

    _OnGraphNodeEditorSure(itemId, startSerial, symbol := "") {
        ; 先清空回调，避免图形窗口关闭时再次保存并重复改树。
        if (this.SubMacroGraphGui != "")
            this.SubMacroGraphGui.SureBtnAction := ""
        if (itemId == "" || itemId == 0)
            return
        displayStr := symbol . GetLangMacro(startSerial, 1)
        ; 节点可能已被上次回写 RefreshTree 重建；失效则跳过
        try curText := this.MacroTreeViewCon.GetText(itemId)
        catch
            return
        ; 图内容已由 _SaveGraph 落盘；显示序列码未变则不必改树
        if (GetCmdStr(curText) == GetCmdStr(displayStr))
            return
        this.CurItemID := itemId
        ParentID := this.MacroTreeViewCon.GetParent(itemId)
        if (ParentID == 0) {
            this.OnModifyCmd(displayStr)
            return
        }
        ; 位于真/假/循环体/条件下：改子节点后按分支宏整体回写
        this.MacroTreeViewCon.Modify(itemId, , displayStr)
        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        if (RealItemID == 0)
            return
        try this.MacroTreeViewCon.GetText(RealItemID)
        catch
            return
        this.OnSubNodeEdit(ParentID, macroStr)
    }
