
    ;打开子指令编辑器 modeType 1:默认行尾追加 2:编辑修改 3:上方插入 4:下方插入 5:真假节点添加
    ; 子指令窗口是否正在显示（用于同类型多开判断）
    ; XAML 版用 _closed 生命周期标志判断（原生版用 WS_VISIBLE）
    IsSubGuiVisible(subGui) {
        return IsObject(subGui) && ObjHasOwnProp(subGui, "_closed") && !subGui._closed
    }

    ; 收集某共享子 GUI 同类型的全部实例（共享 + 多开额外实例）
    GetSubGuiInstances(sharedGui) {
        list := [sharedGui]
        for g in this.OpenedSubGuis {
            if (IsObject(g) && Type(g) == Type(sharedGui)) {
                if (ObjHasOwnProp(sharedGui, "CmdKey") && ObjHasOwnProp(g, "CmdKey") && g.CmdKey != sharedGui.CmdKey)
                    continue
                list.Push(g)
            }
        }
        return list
    }

    ; 同一编辑上下文（类型+mode+节点）已打开则复用并前置；不同节点可多开
    ResolveSubGuiInstance(sharedGui, modeType, itemId) {
        for g in this.GetSubGuiInstances(sharedGui) {
            if (!this.IsSubGuiVisible(g))
                continue
            openType := ObjHasOwnProp(g, "_OpenEditType") ? g._OpenEditType : ""
            openItem := ObjHasOwnProp(g, "_OpenItemId") ? g._OpenItemId : ""
            if (openType == modeType && openItem == itemId)
                return g
        }
        for g in this.GetSubGuiInstances(sharedGui) {
            if (!this.IsSubGuiVisible(g))
                return g
        }
        guiClass := ""
        for config in this.SubGuiConfig {
            if (this.SubGuiMap[GetLang(config.name)] == sharedGui) {
                guiClass := config.class
                break
            }
        }
        if (guiClass == "")
            return sharedGui
        newGui := guiClass()
        if (ObjHasOwnProp(sharedGui, "CmdKey"))
            newGui.CmdKey := sharedGui.CmdKey
        this.OpenedSubGuis.Push(newGui)
        return newGui
    }

    OnOpenSubGui(subGui, modeType := 1) {
        this.CmdEditType := modeType
        editType := modeType
        itemId := this.CurItemID

        ; 同节点再开：复用并覆盖前置；不同节点：多开新实例
        subGui := this.ResolveSubGuiInstance(sharedGui := subGui, modeType, itemId)
        subGui._OpenEditType := modeType
        subGui._OpenItemId := itemId

        if ObjHasOwnProp(subGui, "ParentTile") {
            parentTitle := ""
            try parentTitle := IsObject(this.Gui) ? this.Gui.Title : ""
            ParentTile := StrReplace(parentTitle, GetLang("编辑器"), "")
            subGui.ParentTile := ParentTile "-"
        }

        if (this._sideMode)
            subGui.OwnerHwnd := this.Hwnd()
        else if (MainSoftData.IsModalSubGui && IsObject(this.Gui) && this.Gui.Hwnd)
            subGui.OwnerHwnd := this.Gui.Hwnd
        else
            subGui.OwnerHwnd := ""

        ; 绑定打开时的编辑上下文，多开时互不干扰
        subGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr, editType, itemId)
        if (subGui.HasOwnProp("WindowBindingContext"))
            subGui.WindowBindingContext := this.WindowBindingContext

        if (modeType == 2) {
            ItemText := this.MacroTreeViewCon.GetText(this.CurItemID)
            ; 清理→和调试起点前缀
            ; 只清理位置标记→（前缀，不是方向箭头显示名）
            ItemText := CmdStripDebug(ItemText)
            if SubStr(ItemText, 1, 1) = "→"
                ItemText := SubStr(ItemText, 2)
            ; 还原显示名 + 转 BtnN → Joy* 后传给旧 GUI 编辑器
            ItemText := MySoftData.ParseCmdJoyDisplay(ItemText)
            ItemText := MySoftData.CmdJoyNToJoyFriendly(ItemText)
            CommandStr := GetCmdStr(ItemText)
            subGui.ShowGui(CommandStr)
            return
        }
        subGui.ShowGui("")
    }

    ;确定子指令编辑器（editType/itemId 为打开时捕获的上下文，多开时互不干扰）
    OnSubGuiSureBtnClick(CommandStr, editType := 1, itemId := 0) {
        if (!this._sideMode) {
            style := WinGetStyle(this.Gui.Hwnd)
            isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
            if (!isVisible)
                return
        }

        savedType := this.CmdEditType
        savedItem := this.CurItemID
        this.CmdEditType := editType
        if (itemId != 0)
            this.CurItemID := itemId

        if (editType == 1) {
            this.OnAddCmd(CommandStr)
        }
        else if (editType == 2) {
            this.OnModifyCmd(CommandStr)
        }
        else if (editType == 3) {
            this.OnPreInsertCmd(CommandStr)
        }
        else if (editType == 4) {
            this.OnNextInsertCmd(CommandStr)
        }
        else if (editType == 5) {
            this.OnSubNodeAddCmd(CommandStr)
        }

        this.CmdEditType := savedType
        this.CurItemID := savedItem
        if (!this._sideMode) {
            UIControls.RecordToggle := this.RecordMacroCon
            MainSoftData.MacroEditGui := this
        }
    }
