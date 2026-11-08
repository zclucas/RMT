
    _BuildSideTreeContextMenus(host) {
        scrollStyle := IsObject(MyMacroGui) ? MyMacroGui._ContextMenuScrollStyle() : ""
        subStyle := IsObject(MyMacroGui) ? MyMacroGui._MenuItemSubmenuStyle() : ""
        treeCtxHost := host.Add("Border").Name("SideTreeCtxHost").Width("0").Height("0").Visibility("Collapsed")
        treeCtx := treeCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideTreeCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            treeCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            treeCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(treeCtx)
        else
            treeCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        treeCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        ; 编辑 | 复制、粘贴 | 上插、下插 | 跳过、调试起点 | 删除
        treeCtx.Add("MenuItem").Name("SideMenuEditCmd").Header(GetLang("编辑"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuCopyCmd").Header(GetLang("复制"))
        treeCtx.Add("MenuItem").Name("SideMenuPasteCmd").Header(GetLang("粘贴"))
        treeCtx.Add("Separator")
        miPre := treeCtx.Add("MenuItem").Name("SideMenuInsertPreCmd").Header(GetLang("上插指令"))
        this._AddSideCmdMenuItems(miPre, "SideMenuInsertPre_")
        miNext := treeCtx.Add("MenuItem").Name("SideMenuInsertNextCmd").Header(GetLang("下插指令"))
        this._AddSideCmdMenuItems(miNext, "SideMenuInsertNext_")
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuSkipCmd").Header(GetLang("跳过指令"))
        treeCtx.Add("MenuItem").Name("SideMenuDebugCmd").Header(GetLang("调试起点"))
        treeCtx.Add("MenuItem").Name("SideMenuBpCmd").Header(GetLang("断点"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("SideMenuDeleteCmd").Header(GetLang("删除"))

        branchCtxHost := host.Add("Border").Name("SideBranchCtxHost").Width("0").Height("0").Visibility("Collapsed")
        branchCtx := branchCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideBranchCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            branchCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            branchCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(branchCtx)
        else
            branchCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        branchCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        miAdd := branchCtx.Add("MenuItem").Name("SideMenuBranchAddCmd").Header(GetLang("添加指令"))
        this._AddSideCmdMenuItems(miAdd, "SideMenuBranchAdd_")
        branchCtx.Add("Separator")
        branchCtx.Add("MenuItem").Name("SideMenuBranchDelete").Header(GetLang("删除"))

        blankCtxHost := host.Add("Border").Name("SideTreeBlankCtxHost").Width("0").Height("0").Visibility("Collapsed")
        blankCtx := blankCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("SideTreeBlankCtxMenu")
            .MinWidth("180").Placement("MousePoint")
        if (scrollStyle != "")
            blankCtx.InjectResources(scrollStyle)
        if (subStyle != "")
            blankCtx.InjectResources(subStyle)
        if (IsObject(MyMacroGui))
            MyMacroGui._ApplyCtxMenuTheme(blankCtx)
        else
            blankCtx.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        blankCtx.FontSize(String(XAMLHost.PopupFontSizeDeclared()))
            .FontFamily((MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑")
        miBlank := blankCtx.Add("MenuItem").Name("SideMenuBlankInsertCmd").Header(GetLang("插入指令"))
        this._AddSideCmdMenuItems(miBlank, "SideMenuBlankInsert_")
        blankCtx.Add("MenuItem").Name("SideMenuBlankPasteCmd").Header(GetLang("粘贴"))
    }

    _AddSideCmdMenuItems(parentMi, namePrefix) {
        cmdArr := IsObject(MyMacroGui) ? MyMacroGui.CMDStrArr : []
        iconMap := IsObject(MyMacroGui) ? MyMacroGui.CmdIconFileMap : Map()
        for index, value in cmdArr {
            mi := parentMi.Add("MenuItem").Name(namePrefix index).Header(value)
            iconRel := iconMap.Has(value) ? iconMap[value] : ""
            if (iconRel != "") {
                full := StrReplace(A_WorkingDir "\" iconRel, "\", "/")
                if (FileExist(StrReplace(full, "/", "\")))
                    mi.Add("MenuItem.Icon").Add("Image").SetProp("Source", full).Width("16").Height("16")
            }
        }
    }

    _ApplySidePanelMode() {
        isTree := this.sidePanelMode == 1
        treeVis := isTree ? "Visible" : "Collapsed"
        aiVis := isTree ? "Collapsed" : "Visible"
        for t in this._useVirtual {
            try this.ui.Update("SideTreePane_" t, "Visibility", treeVis)
            try this.ui.Update("SideAiPane_" t, "Visibility", aiVis)
            try this.ui.Update("SideAiFoot_" t, "Visibility", aiVis)
            this._SyncSideModeBtn(t, isTree)
        }
        this._ApplySideToolsVisibility()
    }

    _BindSideTree(t) {
        if (this._sideTreeBound.Has(t))
            return
        this._sideTreeBound[t] := true
        if (!IsObject(this._sideTree))
            this._sideTree := SideLogicTree(this)
        this._BindLive("SideToolExpand_" t, "Click", ObjBindMethod(this, "OnSideToolExpand", t))
        this._BindLive("SideToolUndo_" t, "Click", ObjBindMethod(this, "OnSideToolUndo", t))
        this._BindLive("SideToolRedo_" t, "Click", ObjBindMethod(this, "OnSideToolRedo", t))
        this._BindLive("SideToolBack_" t, "Click", ObjBindMethod(this, "OnSideToolBack", t))
        this._BindLive("SideToolRecord_" t, "Click", ObjBindMethod(this, "OnSideToolRecord", t))
        this._sideDebugTools[t] := MacroDebugToolbar(this.ui, "SideToolDebug_" t, "SideToolDebugDot_" t
            , "SideTreeList_" t, MyMacroGui, ObjBindMethod(this, "OnSideDebugAction", t), true)
        this._BindLive("SideToolVar_" t, "Click", ObjBindMethod(this, "OnSideToolVar", t))
        this._BindLive("SideToolCmdTip_" t, "Click", ObjBindMethod(this, "OnSideToolCmdTip", t))
        this._BindLive("SideToolTop_" t, "Click", ObjBindMethod(this, "OnSideToolTop", t))
    }

    RefreshSideTree(t) {
        if (!IsObject(this.ui) || !this._useVirtual.Has(t))
            return
        if (!IsObject(this._sideTree))
            this._sideTree := SideLogicTree(this)
        emptyName := "SideTreeEmpty_" t
        item := this._ResolveSideTreeItem(t)
        selIdx := item ? GetItemIndexInTable(MySoftData.TableInfo[t], item.ID) : 0
        this._ApplyRowSel(t, selIdx)
        macroStr := ""
        bpStr := ""
        if (item && CheckIsMacroTable(t) && Trim(item.Macro) != "") {
            macroStr := GetLangMacro(item.Macro, 1)
            bpStr := item.HasProp("Breakpoints") ? item.Breakpoints : ""
        }
        this._sideTree.Load(t, macroStr, bpStr)
        this._sideTree.SyncToolToggles(t)
        hasCmd := Trim(macroStr) != ""
        try this.ui.Update(emptyName, "Visibility", hasCmd ? "Collapsed" : "Visible")
    }

    _WriteSideTreeMacroStr(t, macroStr) {
        item := this._ResolveSideTreeItem(t)
        if (!item)
            return
        item.Macro := GetLangMacro(macroStr, 2)
        HotReloadPublish(t, 0)
        idx := GetItemIndexInTable(MySoftData.TableInfo[t], item.ID)
        if (idx >= 1) {
            ; 避免 RefreshItemRow → RefreshSideTree 递归重建当前树
            this._suppressSideTreeRefresh := true
            try {
                if (this._useVirtual.Has(t) && IsObject(this._vl))
                    this._vl.RefreshRow(t, idx)
                else
                    this.RefreshItemRow(t, idx)
            } finally {
                this._suppressSideTreeRefresh := false
            }
        }
        emptyName := "SideTreeEmpty_" t
        try this.ui.Update(emptyName, "Visibility", Trim(macroStr) == "" ? "Visible" : "Collapsed")
    }

    ; 断点写回：更新条目字段 + 热重载广播（断点为独立字段，不动 Macro 文本，也不重建树）
    ; 树标记已由 MacroEditGui.SetBreakPoint 就地更新；此处仅落字段并广播到 Worker
    _WriteSideTreeBreakpoints(t, bpStr) {
        item := this._ResolveSideTreeItem(t)
        if (!item)
            return
        item.Breakpoints := bpStr
        HotReloadPublish(t, 0)
    }

    OnSideToolExpand(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        expandAll := !this._sideTree._allExpanded
        if (expandAll)
            ed.ExpandAll()
        else
            ed.CollapseAll()
        this._sideTree._allExpanded := expandAll
        this._SyncSideExpandBtn(t)
    }

    ; 下次点是展开 → E740（箭头分开）；下次点是收缩 → E73F（现图标）
    _SyncSideExpandBtn(t) {
        if (!IsObject(this.ui))
            return
        allExp := IsObject(this._sideTree) ? !!this._sideTree._allExpanded : true
        glyph := allExp ? Chr(0xE73F) : Chr(0xE740)
        try this.ui.Update("SideToolExpand_" t, "Content", glyph)
    }

    OnSideToolUndo(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Undo()
    }

    OnSideToolRedo(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Redo()
    }

    OnSideToolBack(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        ed.Backspace()
        ed._NotifyMacroChanged()
    }

    OnSideToolRecord(t, *) {
        OnClickToolRecordMacro(true)
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    HideSideDebugTools() {
        for , toolbar in this._sideDebugTools
            toolbar.Hide()
    }

    OnSideDebugAction(t, method, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (!IsObject(ed))
            return
        this._sideTree.Activate(t)
        MacroDebugToolbar.Run(ed, method)
    }

    ; ⚠️ 当前无调用方（侧栏「运行到下一断点」工具钮已随 F7 退休删除，
    ;    语义并入「继续」F5）；保留以备回退——勿当活代码引用。
    OnSideToolRunToBp(t, *) {
        if (!IsObject(this._sideTree))
            return
        this._sideTree.Activate(t)
        ed := this._sideTree.ActiveEditor()
        if (!IsObject(ed))
            ed := this._sideTree.Ensure(t)
        if (!IsObject(ed))
            return
        ed.ContinueRun()
    }

    OnSideToolVar(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (IsObject(ed)) {
            this._sideTree.Activate(t)
            ed.MenuHandler(GetLang("变量监视"))
        } else {
            if (MyVarListenGui.Gui != "" && MyVarListenGui.Gui.Hwnd) {
                style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                if (style & 0x10000000) {
                    MyVarListenGui.Gui.Hide()
                } else
                    MyVarListenGui.ShowGui()
            } else
                MyVarListenGui.ShowGui()
        }
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    OnSideToolCmdTip(t, *) {
        ed := IsObject(this._sideTree) ? this._sideTree.Ensure(t) : ""
        if (IsObject(ed)) {
            this._sideTree.Activate(t)
            ed.MenuHandler(GetLang("指令显示"))
        }
        if (IsObject(this._sideTree))
            this._sideTree.SyncToolToggles(t)
    }

    OnSideToolTop(t, *) {
        this._sideTopOn := !this._sideTopOn
        if (IsObject(this._sideTree))
            this._sideTree._topOn := this._sideTopOn
        try this.ui.Update("Window", "Topmost", this._sideTopOn ? "True" : "False")
        for tab in this._useVirtual {
            this.SyncSideToolToggle(tab, "Top", this._sideTopOn)
            this.SyncSideToolToggle(tab, "Top", this._sideTopOn, "SideAiTool")
        }
    }

    _FirstSideTreeItem(tableItem) {
        if (!IsObject(tableItem))
            return ""
        if (tableItem.Folds.Length >= 1) {
            fold := tableItem.Folds[1]
            for item in tableItem.Items {
                if (item.FoldID == fold.ID)
                    return item
            }
        }
        return tableItem.Items.Length >= 1 ? tableItem.Items[1] : ""
    }

    _SelectFirstSideTreeItem(t) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        item := this._FirstSideTreeItem(MySoftData.TableInfo[t])
        if (!item)
            return
        this._sideTreeSel[t] := item.ID
        this._ApplyRowSel(t, GetItemIndexInTable(MySoftData.TableInfo[t], item.ID))
    }

    _ResolveSideTreeItem(t) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return ""
        tableItem := MySoftData.TableInfo[t]
        id := this._sideTreeSel.Has(t) ? this._sideTreeSel[t] : ""
        if (id == "")
            return ""
        return tableItem.GetItem(id)
    }

    SelectSideTreeItem(t, index, openPanel := true, deferTree := false, *) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        tableItem := MySoftData.TableInfo[t]
        if (index < 1 || index > tableItem.Items.Length)
            return
        item := tableItem.Items[index]
        if (!item)
            return
        ; 事件回调会把 state 传到 openPanel；只有显式 false 才不展开
        doOpen := (openPanel != false && openPanel != 0)
        opened := false
        if (doOpen && !this._IsAiPanelOpen()) {
            this.aiAssistOpen := true
            this.sidePanelMode := 1
            this._ApplyAiPanelUi()
            this._ApplySidePanelMode()
            opened := true
        }
        ; 单击切到了别的宏：忘掉上次双击展开的目标，避免下次双击被误判成"折叠"
        if (!doOpen && this._dblOpenMacro.Has(t) && this._dblOpenMacro[t] != item.ID)
            this._dblOpenMacro.Delete(t)
        same := this._sideTreeSel.Has(t) && this._sideTreeSel[t] == item.ID
        this._sideTreeSel[t] := item.ID
        this._ApplyRowSel(t, index)
        if (this._IsAiPanelOpen() && this.sidePanelMode == 1 && (!same || opened)) {
            if (deferTree == true)
                SetTimer(ObjBindMethod(this, "RefreshSideTree", t), -1)
            else
                this.RefreshSideTree(t)
        }
    }

    ; 双击宏：展开/折叠右侧逻辑树。首次双击展开并显示该宏，再双击同一个即收起。
    ToggleMacroTree(t, index) {
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        tableItem := MySoftData.TableInfo[t]
        if (index < 1 || index > tableItem.Items.Length)
            return
        item := tableItem.Items[index]
        if (!item)
            return
        same := this._dblOpenMacro.Has(t) && this._dblOpenMacro[t] == item.ID
        if (same && this._IsAiPanelOpen() && this.sidePanelMode == 1) {
            this._dblOpenMacro.Delete(t)
            this.aiAssistOpen := false
            this._ApplyAiPanelUi()
            return
        }
        this._dblOpenMacro[t] := item.ID
        ; 双击要看到的是逻辑树：侧栏没开、或停在 AI 分支时先切过去
        if (!this._IsAiPanelOpen() || this.sidePanelMode != 1) {
            this.aiAssistOpen := true
            this.sidePanelMode := 1
            this._ApplyAiPanelUi()
            this._ApplySidePanelMode()
        }
        this.SelectSideTreeItem(t, index, false)
    }

    _ApplyRowSel(t, index) {
        if (t < 1)
            return
        if (this._useVirtual.Has(t) && IsObject(this._vl)) {
            this._vl.SetRowSel(t, index)
            return
        }
        if (this._rowSelIdx.Has(t)) {
            old := this._rowSelIdx[t]
            if (old != index && old >= 1)
                this._SetItemRowSelChrome(t, old, false)
        }
        if (index >= 1) {
            this._SetItemRowSelChrome(t, index, true)
            this._rowSelIdx[t] := index
        } else {
            this._rowSelIdx[t] := 0
        }
    }

    _SetItemRowSelChrome(t, i, on) {
        if (!this._IsRendered(t, i))
            return
        tableItem := MySoftData.TableInfo[t]
        item := (i >= 1 && i <= tableItem.Items.Length) ? tableItem.Items[i] : ""
        if (on) {
            this.ui.Update("ItemCard_" t "_" i, "Background", "{DynamicResource TabSelBg}")
            this.ui.Update("RowSelDot_" t "_" i, "Visibility", "Visible")
            this.ui.Update("RowSelMark_" t "_" i, "Visibility", "Visible")
        } else {
            bg := (item && (item.Forbid || GetItemFoldForbidState(tableItem, i))) ? "{DynamicResource ListRowForbidBg}" : "{DynamicResource ControlBg}"
            this.ui.Update("ItemCard_" t "_" i, "Background", bg)
            this.ui.Update("RowSelDot_" t "_" i, "Visibility", "Collapsed")
            this.ui.Update("RowSelMark_" t "_" i, "Visibility", "Collapsed")
        }
    }

    _SyncSideModeBtn(t, isTree) {
        this._PaintSideModeBtn("BtnSideModeTree_" t, isTree, "first")
        this._PaintSideModeBtn("BtnSideModeAi_" t, !isTree, "last")
    }

    _PaintSideModeBtn(name, on, which) {
        tag := (which == "last") ? (on ? "sel-last" : "last") : (on ? "sel-first" : "first")
        try this.ui.Update(name, "Tag", tag)
    }
