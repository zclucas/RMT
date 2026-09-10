#Requires AutoHotkey v2.0

; 主窗口侧栏「逻辑树」宿主：每页签一个 MacroEditGui(reuseShared) 实例
; 依赖：由 GlobalUtil 在 MacroEditGui 之后 Include 本文件
class SideLogicTree {
    static CtxMenuBound := false
    static HotkeyBound := false

    __New(mainWin) {
        this.mainWin := mainWin
        this.editors := Map()
        this._topOn := false
        this._varOn := false
        this._cmdTipOn := false
        this._allExpanded := true   ; 默认树节点展开；工具钮切换全部展开/收起
    }

    Ensure(t) {
        if (this.editors.Has(t))
            return this.editors[t]
        if (!IsObject(this.mainWin) || !IsObject(this.mainWin.ui))
            return ""
        ed := MacroEditGui(true)
        names := {
            treeName: "SideTreeList_" t,
            insertLineName: "SideDragInsertLine_" t,
            dragGhostName: "SideDragGhost_" t,
            dragGhostTxtName: "SideDragGhostTxt_" t,
            ctxMenuName: "SideTreeCtxMenu",
            branchCtxMenuName: "SideBranchCtxMenu",
            blankCtxMenuName: "SideTreeBlankCtxMenu",
            menuEditName: "SideMenuEditCmd",
            menuSkipName: "SideMenuSkipCmd",
            menuDebugName: "SideMenuDebugCmd",
            menuBpName: "SideMenuBpCmd",
            menuCopyName: "SideMenuCopyCmd",
            menuPasteName: "SideMenuPasteCmd",
            menuDeleteName: "SideMenuDeleteCmd",
            menuBranchDeleteName: "SideMenuBranchDelete",
            menuBlankPasteName: "SideMenuBlankPasteCmd",
            menuInsertPrePrefix: "SideMenuInsertPre_",
            menuInsertNextPrefix: "SideMenuInsertNext_",
            menuBlankInsertPrefix: "SideMenuBlankInsert_",
            menuBranchAddPrefix: "SideMenuBranchAdd_"
        }
        bindCtx := !SideLogicTree.CtxMenuBound
        bindHk := !SideLogicTree.HotkeyBound
        onChanged := ObjBindMethod(this, "_OnMacroChanged", t)
        onBpChanged := ObjBindMethod(this, "_OnBpChanged", t)
        ed.AttachSidePanel(this.mainWin.ui, names, onChanged, bindCtx, bindHk, onBpChanged)
        if (bindCtx)
            SideLogicTree.CtxMenuBound := true
        if (bindHk)
            SideLogicTree.HotkeyBound := true
        this.editors[t] := ed
        return ed
    }

    Activate(t) {
        for tab, ed in this.editors
            ed.SetSideActive(tab == t)
        this.Ensure(t)
        if (this.editors.Has(t))
            this.editors[t].SetSideActive(true)
    }

    Load(t, macroStr, bpStr := "") {
        ed := this.Ensure(t)
        if (!IsObject(ed))
            return
        this.Activate(t)
        ed.LoadSideMacro(macroStr, bpStr)
    }

    Get(t) {
        return this.editors.Has(t) ? this.editors[t] : ""
    }

    ActiveEditor() {
        t := MainSoftData.TableIndex
        return this.Get(t)
    }

    _OnMacroChanged(t, macroStr) {
        if (!IsObject(this.mainWin))
            return
        this.mainWin._WriteSideTreeMacroStr(t, macroStr)
    }

    _OnBpChanged(t, bpStr) {
        if (!IsObject(this.mainWin))
            return
        this.mainWin._WriteSideTreeBreakpoints(t, bpStr)
    }

    SyncToolToggles(t) {
        if (!IsObject(this.mainWin) || !IsObject(this.mainWin.ui))
            return
        recordOn := false
        try recordOn := !!UIControls.ToolCheckRecord.Value
        this.mainWin.SyncSideToolToggle(t, "Record", recordOn)

        varOn := false
        if (IsSet(MyVarListenGui) && IsObject(MyVarListenGui) && MyVarListenGui.Gui != "") {
            try {
                style := WinGetStyle("ahk_id " MyVarListenGui.Gui.Hwnd)
                varOn := !!(style & 0x10000000)
            }
        }
        this._varOn := varOn
        this.mainWin.SyncSideToolToggle(t, "Var", varOn)

        tipOn := !!(MySoftData.HasProp("CMDTip") && MySoftData.CMDTip)
        if (IsSet(MyCMDTipGui) && IsObject(MyCMDTipGui) && MyCMDTipGui.Gui != "") {
            try {
                style := WinGetStyle("ahk_id " MyCMDTipGui.Gui.Hwnd)
                tipOn := tipOn && !!(style & 0x10000000)
            }
        }
        this._cmdTipOn := tipOn
        this.mainWin.SyncSideToolToggle(t, "CmdTip", tipOn)
        this.mainWin.SyncSideToolToggle(t, "Top", this._topOn)
        this.mainWin._SyncSideExpandBtn(t)
    }

    RefreshBranchLayout() {
        for tab, ed in this.editors {
            if (IsObject(ed) && IsObject(ed.MacroTreeViewCon))
                ed.MacroTreeViewCon.Render()
        }
    }
}
