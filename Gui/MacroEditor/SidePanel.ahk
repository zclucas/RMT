
    ; 侧栏多实例只注册一次热键，由 ActiveEditor 转发
    AttachSidePanel(ui, names, onChanged := "", bindCtxMenu := true, bindHotkeys := true, onBpChanged := "") {
        if (!IsObject(ui))
            return
        this._sideMode := true
        this._closed := false
        this.ui := ui
        this.OnMacroChanged := onChanged
        this.OnBpChanged := onBpChanged
        ; F3：侧栏逻辑树断点持久化路径已通（OnBpChanged → 宿主 _WriteSideTreeBreakpoints），启用断点菜单
        this._bpAllowed := true
        if (IsObject(names)) {
            if (names.HasProp("treeName") && names.treeName != "")
                this.treeName := names.treeName
            if (names.HasProp("insertLineName") && names.insertLineName != "")
                this.insertLineName := names.insertLineName
            if (names.HasProp("dragGhostName") && names.dragGhostName != "")
                this.dragGhostName := names.dragGhostName
            if (names.HasProp("dragGhostTxtName") && names.dragGhostTxtName != "")
                this.dragGhostTxtName := names.dragGhostTxtName
            if (names.HasProp("ctxMenuName") && names.ctxMenuName != "")
                this.ctxMenuName := names.ctxMenuName
            if (names.HasProp("branchCtxMenuName") && names.branchCtxMenuName != "")
                this.branchCtxMenuName := names.branchCtxMenuName
            if (names.HasProp("blankCtxMenuName") && names.blankCtxMenuName != "")
                this.blankCtxMenuName := names.blankCtxMenuName
            if (names.HasProp("menuEditName") && names.menuEditName != "")
                this.menuEditName := names.menuEditName
            if (names.HasProp("menuSkipName") && names.menuSkipName != "")
                this.menuSkipName := names.menuSkipName
            if (names.HasProp("menuDebugName") && names.menuDebugName != "")
                this.menuDebugName := names.menuDebugName
            if (names.HasProp("menuBpName") && names.menuBpName != "")
                this.menuBpName := names.menuBpName
            if (names.HasProp("menuCopyName") && names.menuCopyName != "")
                this.menuCopyName := names.menuCopyName
            if (names.HasProp("menuPasteName") && names.menuPasteName != "")
                this.menuPasteName := names.menuPasteName
            if (names.HasProp("menuDeleteName") && names.menuDeleteName != "")
                this.menuDeleteName := names.menuDeleteName
            if (names.HasProp("menuBranchDeleteName") && names.menuBranchDeleteName != "")
                this.menuBranchDeleteName := names.menuBranchDeleteName
            if (names.HasProp("menuBlankPasteName") && names.menuBlankPasteName != "")
                this.menuBlankPasteName := names.menuBlankPasteName
            if (names.HasProp("menuInsertPrePrefix") && names.menuInsertPrePrefix != "")
                this.menuInsertPrePrefix := names.menuInsertPrePrefix
            if (names.HasProp("menuInsertNextPrefix") && names.menuInsertNextPrefix != "")
                this.menuInsertNextPrefix := names.menuInsertNextPrefix
            if (names.HasProp("menuBlankInsertPrefix") && names.menuBlankInsertPrefix != "")
                this.menuBlankInsertPrefix := names.menuBlankInsertPrefix
            if (names.HasProp("menuInsertPrefix") && names.menuInsertPrefix != "")
                this.menuInsertPrefix := names.menuInsertPrefix
            if (names.HasProp("menuBranchAddPrefix") && names.menuBranchAddPrefix != "")
                this.menuBranchAddPrefix := names.menuBranchAddPrefix
        }
        this.MacroTreeViewCon := MacroTreeAdapter(this.ui, this.treeName)
        this.MacroTreeViewCon.SetIconMap(this.IconFileByNumber)
        this.MacroTreeViewCon.Visible := true
        this.EditModeCon := SideEditModeCon(1)
        this.ToolMenu := SideToolMenuStub()
        hwnd := this.Hwnd()
        this.Gui := SideGuiFacade(hwnd, GetLang("逻辑树"))
        this.OwnerHwnd := ""
        if (!this._sideBound) {
            this._BindTreeInteractionEvents()
            if (bindCtxMenu)
                this._BindTreeContextMenuEvents()
            this.ui.Track(this.treeName)
            this._sideBound := true
        }
        if (bindHotkeys && this._hkIds.Length == 0 && hwnd)
            this._hkIds := WinHotkey.Register([this._GetContinueHotkey(), this._GetStepOverHotkey(), this._GetStepIntoHotkey(), this._GetStepOutHotkey(), this._GetRunToCursorHotkey(), "$" this._GetToggleSkipHotkey(), this._GetRunAllHotkey(), "Delete", "$^c", "$^v", "$^z", "$^y"], ObjBindMethod(this, "_OnHotkey"), hwnd)
    }

    SetSideActive(active) {
        this._sideActive := !!active
        if (!active)
            this._DragEndReset()
    }

    LoadSideMacro(MacroStr, bpStr := "") {
        if (!IsObject(this.MacroTreeViewCon))
            return
        this._bpStr := bpStr ? bpStr : ""
        this.InitTreeView(MacroStr)
        this.ClearMultiSelection()
        this.CurItemID := 0
        if (IsObject(this.MacroTreeViewCon) && this.MacroTreeViewCon.HasMethod("Unselect"))
            this.MacroTreeViewCon.Unselect()
    }

    _NotifyMacroChanged() {
        if (!this._sideMode || !IsObject(this.OnMacroChanged))
            return
        if (this._undoBatch > 0) {
            this._pendingSideNotify := true
            return
        }
        this._pendingSideNotify := false
        try this.OnMacroChanged.Call(this.GetMacroStr())
    }
