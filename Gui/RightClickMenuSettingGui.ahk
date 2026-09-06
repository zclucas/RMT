#Requires AutoHotkey v2.0

; 右键菜单设置编辑器：XAML，颜色跟随通用主题
class RightClickMenuSettingGui {
    static instances := Map()
    static _opening := false

    ; 所有可用的一般右键菜单项（内部 key）
    static AllGeneralItems := ["Edit", "Skip", "Debug", "Insert", "Copy", "SharedCopy", "Paste", "Delete", "Separator"]
    ; 所有可用的分支循环体右键菜单项（内部 key）
    static AllBranchItems := ["Add", "BranchCopy", "BranchSharedCopy", "Paste", "Delete", "Separator"]

    __new() {
        this.ui := 0
        this.closed := true
        this._instanceKey := ""
        this._btnStyle := ""
        this._editBtnStyle := ""
        ; 编辑中的数据（内部 key 数组）
        this._generalActive := []
        this._generalAvail := []
        this._branchActive := []
        this._branchAvail := []
        ; 选中索引（0 = 未选）
        this._genActiveSelIdx := 0
        this._genAvailSelIdx := 0
        this._branchActiveSelIdx := 0
        this._branchAvailSelIdx := 0
    }

    ; 获取项目的显示名
    _ItemLabel(key) {
        labelMap := Map(
            "Edit",             GetLang("编辑"),
            "Skip",             GetLang("跳过指令"),
            "Debug",            GetLang("调试起点"),
            "Insert",           GetLang("插入指令"),
            "Copy",             GetLang("复制"),
            "SharedCopy",       GetLang("共享复制"),
            "Paste",            GetLang("粘贴"),
            "Delete",           GetLang("删除"),
            "Add",              GetLang("添加指令"),
            "BranchCopy",       GetLang("复制"),
            "BranchSharedCopy", GetLang("共享复制"),
            "Separator",        "───────",
        )
        return labelMap.Has(key) ? labelMap[key] : key
    }

    ShowGui() {
        key := "rightclickmenu"
        if (RightClickMenuSettingGui.instances.Has(key)) {
            oldInst := RightClickMenuSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            RightClickMenuSettingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (RightClickMenuSettingGui._opening)
            return
        RightClickMenuSettingGui._opening := true
        try {
            this._instanceKey := key
            this._LoadData()
            this._BuildAndShow()
            RightClickMenuSettingGui.instances[key] := this
        } finally {
            RightClickMenuSettingGui._opening := false
        }
    }

    _LoadData() {
        ; 一般菜单
        genActive := []
        genAvail := []
        savedGen := MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : ""
        if (savedGen != "") {
            for k in StrSplit(savedGen, ",") {
                k := Trim(k)
                if (k != "")
                    genActive.Push(k)
            }
        } else {
            genActive := ["Edit", "Skip", "Debug", "Separator", "Insert", "Separator", "Copy", "SharedCopy", "Paste", "Separator", "Delete"]
        }
        for item in RightClickMenuSettingGui.AllGeneralItems {
            if (item == "Separator") {
                genAvail.Push(item)
                continue
            }
            found := false
            for a in genActive {
                if (a == item) {
                    found := true
                    break
                }
            }
            if (!found)
                genAvail.Push(item)
        }
        this._generalActive := genActive
        this._generalAvail := genAvail

        ; 分支菜单
        branchActive := []
        branchAvail := []
        savedBranch := MainSoftData.HasProp("BranchContextMenu") ? MainSoftData.BranchContextMenu : ""
        if (savedBranch != "") {
            for k in StrSplit(savedBranch, ",") {
                k := Trim(k)
                if (k != "")
                    branchActive.Push(k)
            }
        } else {
            branchActive := ["Add", "Separator", "BranchCopy", "BranchSharedCopy", "Paste", "Separator", "Delete"]
        }
        for item in RightClickMenuSettingGui.AllBranchItems {
            if (item == "Separator") {
                branchAvail.Push(item)
                continue
            }
            found := false
            for a in branchActive {
                if (a == item) {
                    found := true
                    break
                }
            }
            if (!found)
                branchAvail.Push(item)
        }
        this._branchActive := branchActive
        this._branchAvail := branchAvail
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("右键菜单设置")
        titleHeight := "30"
        winW := 680
        winH := 540

        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        this._editBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; 标题栏
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; 主体
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,12,16,12")

        ; ===== 模块1：一般右键 =====
        body.Add("TextBlock").Text(GetLang("一般右键显示")).Foreground("{DynamicResource TextMain}").FontSize(13).FontWeight("SemiBold").Margin("0,0,0,8")
        genPanel := body.Add("Grid").Margin("0,0,0,14")
        genPanel.Cols("*", "50", "*")

        ; 左：已启用
        genLeft := genPanel.Add("Border").Grid_Column(0).BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").CornerRadius("4").Background("{DynamicResource InputBg}")
        genLeftStack := genLeft.Add("StackPanel")
        genLeftStack.Add("TextBlock").Text(GetLang("显示项目")).Foreground("{DynamicResource TextSub}").FontSize(11).Margin("6,4,6,2")
        genActiveList := genLeftStack.Add("ListBox").Name("GenActiveList").Height(140)
            .Background("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}").FontSize(12)

        ; 中间按钮
        genMid := genPanel.Add("StackPanel").Grid_Column(1).VerticalAlignment("Center").HorizontalAlignment("Center")
        genUpBtn := genMid.Add("Button").Name("BtnGenUp").Content(Chr(0xE70E))
            .Width(30).Height(28).Margin("0,0,0,4").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        genUpBtn.InjectResources(this._editBtnStyle)
        genDownBtn := genMid.Add("Button").Name("BtnGenDown").Content(Chr(0xE70D))
            .Width(30).Height(28).Margin("0,0,0,8").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        genDownBtn.InjectResources(this._editBtnStyle)
        genAddBtn := genMid.Add("Button").Name("BtnGenAdd").Content(Chr(0xE76B))
            .Width(30).Height(28).Margin("0,0,0,4").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        genAddBtn.InjectResources(this._editBtnStyle)
        genRemBtn := genMid.Add("Button").Name("BtnGenRemove").Content(Chr(0xE76C))
            .Width(30).Height(28).Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        genRemBtn.InjectResources(this._editBtnStyle)

        ; 右：可用
        genRight := genPanel.Add("Border").Grid_Column(2).BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").CornerRadius("4").Background("{DynamicResource InputBg}")
        genRightStack := genRight.Add("StackPanel")
        genRightStack.Add("TextBlock").Text(GetLang("可用项目")).Foreground("{DynamicResource TextSub}").FontSize(11).Margin("6,4,6,2")
        genAvailList := genRightStack.Add("ListBox").Name("GenAvailList").Height(140)
            .Background("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}").FontSize(12)

        ; ===== 模块2：分支循环体右键 =====
        body.Add("TextBlock").Text(GetLang("分支循环体右键显示")).Foreground("{DynamicResource TextMain}").FontSize(13).FontWeight("SemiBold").Margin("0,0,0,8")
        branchPanel := body.Add("Grid").Margin("0,0,0,16")
        branchPanel.Cols("*", "50", "*")

        ; 左：已启用
        branchLeft := branchPanel.Add("Border").Grid_Column(0).BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").CornerRadius("4").Background("{DynamicResource InputBg}")
        branchLeftStack := branchLeft.Add("StackPanel")
        branchLeftStack.Add("TextBlock").Text(GetLang("显示项目")).Foreground("{DynamicResource TextSub}").FontSize(11).Margin("6,4,6,2")
        branchActiveList := branchLeftStack.Add("ListBox").Name("BranchActiveList").Height(120)
            .Background("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}").FontSize(12)

        ; 中间按钮
        branchMid := branchPanel.Add("StackPanel").Grid_Column(1).VerticalAlignment("Center").HorizontalAlignment("Center")
        branchUpBtn := branchMid.Add("Button").Name("BtnBranchUp").Content(Chr(0xE70E))
            .Width(30).Height(28).Margin("0,0,0,4").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        branchUpBtn.InjectResources(this._editBtnStyle)
        branchDownBtn := branchMid.Add("Button").Name("BtnBranchDown").Content(Chr(0xE70D))
            .Width(30).Height(28).Margin("0,0,0,8").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        branchDownBtn.InjectResources(this._editBtnStyle)
        branchAddBtn := branchMid.Add("Button").Name("BtnBranchAdd").Content(Chr(0xE76B))
            .Width(30).Height(28).Margin("0,0,0,4").Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        branchAddBtn.InjectResources(this._editBtnStyle)
        branchRemBtn := branchMid.Add("Button").Name("BtnBranchRemove").Content(Chr(0xE76C))
            .Width(30).Height(28).Cursor("Hand")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
        branchRemBtn.InjectResources(this._editBtnStyle)

        ; 右：可用
        branchRight := branchPanel.Add("Border").Grid_Column(2).BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").CornerRadius("4").Background("{DynamicResource InputBg}")
        branchRightStack := branchRight.Add("StackPanel")
        branchRightStack.Add("TextBlock").Text(GetLang("可用项目")).Foreground("{DynamicResource TextSub}").FontSize(11).Margin("6,4,6,2")
        branchAvailList := branchRightStack.Add("ListBox").Name("BranchAvailList").Height(120)
            .Background("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}").FontSize(12)

        ; 底部按钮行
        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,4,0,0")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(90).Height(32).Margin("0,0,16,0")
        okBtn.InjectResources(this._btnStyle)
        cancelBtn := btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消"))
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(90).Height(32)
        cancelBtn.InjectResources(this._editBtnStyle)

        pos := GetCenterPosOnActiveMonitor(winW, winH)
        dipX := PhysToDip(pos.x)
        dipY := PhysToDip(pos.y)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="{}" ShowInTaskbar="False" Width="{}" Height="{}" Left="{}" Top="{}" Opacity="0"',
                title, winW, winH, dipX, dipY))
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelClick"))

        ; 一般菜单按钮
        this.ui.OnEvent("BtnGenUp",     "Click", ObjBindMethod(this, "OnMoveUp",   "general"))
        this.ui.OnEvent("BtnGenDown",   "Click", ObjBindMethod(this, "OnMoveDown", "general"))
        this.ui.OnEvent("BtnGenAdd",    "Click", ObjBindMethod(this, "OnAddItem",  "general"))
        this.ui.OnEvent("BtnGenRemove", "Click", ObjBindMethod(this, "OnRemoveItem","general"))

        ; 分支菜单按钮
        this.ui.OnEvent("BtnBranchUp",     "Click", ObjBindMethod(this, "OnMoveUp",   "branch"))
        this.ui.OnEvent("BtnBranchDown",   "Click", ObjBindMethod(this, "OnMoveDown", "branch"))
        this.ui.OnEvent("BtnBranchAdd",    "Click", ObjBindMethod(this, "OnAddItem",  "branch"))
        this.ui.OnEvent("BtnBranchRemove", "Click", ObjBindMethod(this, "OnRemoveItem","branch"))

        ; 选择追踪
        this.ui.Track("GenActiveList")
        this.ui.Track("GenAvailList")
        this.ui.Track("BranchActiveList")
        this.ui.Track("BranchAvailList")
        this.ui.OnEvent("GenActiveList",    "SelectionChanged", ObjBindMethod(this, "OnSelChanged", "GenActiveList"))
        this.ui.OnEvent("GenAvailList",     "SelectionChanged", ObjBindMethod(this, "OnSelChanged", "GenAvailList"))
        this.ui.OnEvent("BranchActiveList", "SelectionChanged", ObjBindMethod(this, "OnSelChanged", "BranchActiveList"))
        this.ui.OnEvent("BranchAvailList",  "SelectionChanged", ObjBindMethod(this, "OnSelChanged", "BranchAvailList"))

        this._RefreshAllLists()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        RightClickMenuSettingGui._opening := false
        if (this._instanceKey != "" && RightClickMenuSettingGui.instances.Has(this._instanceKey))
            RightClickMenuSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        this.Close()
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    ; ======== 列表操作 ========

    _GetLists(which) {
        if (which == "general")
            return {active: this._generalActive, avail: this._generalAvail,
                    activeId: "GenActiveList", availId: "GenAvailList"}
        else
            return {active: this._branchActive, avail: this._branchAvail,
                    activeId: "BranchActiveList", availId: "BranchAvailList"}
    }

    ; scrollToIdx: 0-based 目標行，確保 bridge 在加入該項時 ScrollIntoView
    _RefreshList(listId, arr, scrollToIdx := -1) {
        if (!IsObject(this.ui) || this.closed)
            return
        this.ui.Update(listId, "ClearItems", "")

        if (scrollToIdx >= 0 && scrollToIdx < arr.Length) {
            ; 先加目標項之前的所有項（bridge 首次 prevIdx=-1 會 scroll 到第0項，之後保持 sel=0）
            for i, item in arr {
                if (i < scrollToIdx + 1)  ; 1-based < scrollToIdx+1 即 0-based < scrollToIdx
                    this.ui.Update(listId, "AddItem", this._ItemLabel(item))
            }
            ; 緊接著把 SelectedIndex 設為 -1，讓下一次 AddItem 觸發 ScrollIntoView
            this.ui.Update(listId, "SelectedIndex", "-1")
            ; 加入目標項：bridge 讀到 prevIdx=-1，選中並 ScrollIntoView 到此項
            this.ui.Update(listId, "AddItem", this._ItemLabel(arr[scrollToIdx + 1]))
            ; 加剩餘項：bridge 讀到 prevIdx=scrollToIdx，保留選中不再 scroll
            for i, item in arr {
                if (i > scrollToIdx + 1)
                    this.ui.Update(listId, "AddItem", this._ItemLabel(item))
            }
        } else {
            for item in arr
                this.ui.Update(listId, "AddItem", this._ItemLabel(item))
        }
    }

    _RefreshAllLists() {
        this._RefreshList("GenActiveList",    this._generalActive)
        this._RefreshList("GenAvailList",     this._generalAvail)
        this._RefreshList("BranchActiveList", this._branchActive)
        this._RefreshList("BranchAvailList",  this._branchAvail)
    }

    _GetSelIdx(listId) {
        if (!IsObject(this.ui) || this.closed)
            return -1
        raw := this.ui.Query(listId ">SelectedIndex")
        return (raw != "" && IsNumber(raw)) ? Integer(raw) : -1
    }

    OnSelChanged(listId, state := unset, ctrl := unset, event := unset) {
        ; 只记录选中状态供按钮使用，无需额外操作
    }

    OnMoveUp(which, state := unset, ctrl := unset, event := unset) {
        lists := this._GetLists(which)
        idx0 := this._GetSelIdx(lists.activeId) ; 0-based
        if (idx0 < 1 || idx0 >= lists.active.Length)
            return
        idx1 := idx0 + 1 ; 1-based
        tmp := lists.active[idx1]
        lists.active[idx1] := lists.active[idx1 - 1]
        lists.active[idx1 - 1] := tmp
        newSel := idx0 - 1  ; 0-based 目标行
        this._RefreshList(lists.activeId, lists.active, newSel)
    }

    OnMoveDown(which, state := unset, ctrl := unset, event := unset) {
        lists := this._GetLists(which)
        idx0 := this._GetSelIdx(lists.activeId) ; 0-based
        if (idx0 < 0 || idx0 >= lists.active.Length - 1)
            return
        idx1 := idx0 + 1 ; 1-based
        tmp := lists.active[idx1 + 1]
        lists.active[idx1 + 1] := lists.active[idx1]
        lists.active[idx1] := tmp
        newSel := idx0 + 1  ; 0-based 目标行
        this._RefreshList(lists.activeId, lists.active, newSel)
    }

    OnAddItem(which, state := unset, ctrl := unset, event := unset) {
        lists := this._GetLists(which)
        availIdx := this._GetSelIdx(lists.availId)  ; 右侧选中项（0-based）
        if (availIdx < 0 || availIdx >= lists.avail.Length)
            return
        item := lists.avail[availIdx + 1]

        ; 插入位置：左侧当前选中项之后，未选中则追加末尾
        activeIdx := this._GetSelIdx(lists.activeId)  ; 0-based，-1=未选中
        insertAt := (activeIdx >= 0 && activeIdx < lists.active.Length)
            ? activeIdx + 2   ; 1-based 插入到选中项之后
            : lists.active.Length + 1   ; 末尾

        newActive := []
        for i, v in lists.active {
            if (i == insertAt)
                newActive.Push(item)
            newActive.Push(v)
        }
        if (insertAt > lists.active.Length)
            newActive.Push(item)

        if (which == "general") {
            this._generalActive := newActive
        } else {
            this._branchActive := newActive
        }

        ; 如果不是分割线，从可用列表中移除
        if (item != "Separator") {
            newAvail := []
            for i, v in lists.avail {
                if (i != availIdx + 1)
                    newAvail.Push(v)
            }
            if (which == "general") {
                this._generalAvail := newAvail
            } else {
                this._branchAvail := newAvail
            }
        }
        this._RefreshList(lists.activeId, (which == "general") ? this._generalActive : this._branchActive, insertAt - 1)
        this._RefreshList(lists.availId,  (which == "general") ? this._generalAvail  : this._branchAvail)
    }

    OnRemoveItem(which, state := unset, ctrl := unset, event := unset) {
        lists := this._GetLists(which)
        idx := this._GetSelIdx(lists.activeId)
        if (idx < 0 || idx >= lists.active.Length)
            return
        item := lists.active[idx + 1]
        newActive := []
        for i, v in lists.active {
            if (i != idx + 1)
                newActive.Push(v)
        }
        if (which == "general") {
            this._generalActive := newActive
            if (item != "Separator")
                this._generalAvail.Push(item)
        } else {
            this._branchActive := newActive
            if (item != "Separator")
                this._branchAvail.Push(item)
        }
        ; 删除后选中上一项（如果有），没有则不滚动
        newSel := (idx > 0) ? idx - 1 : (newActive.Length > 0 ? 0 : -1)
        this._RefreshList(lists.activeId, (which == "general") ? this._generalActive : this._branchActive, newSel)
        this._RefreshList(lists.availId, (which == "general") ? this._generalAvail : this._branchAvail)
    }

    OnConfirmClick(state := unset, ctrl := unset, event := unset) {
        global IniFile, IniSection
        ; 保存到 MainSoftData
        genStr := ""
        for i, k in this._generalActive {
            genStr .= (i > 1 ? "," : "") k
        }
        branchStr := ""
        for i, k in this._branchActive {
            branchStr .= (i > 1 ? "," : "") k
        }
        MainSoftData.GeneralContextMenu := genStr
        MainSoftData.BranchContextMenu := branchStr

        ; 同时兼容旧的 SharedCopy 标志（若 SharedCopy 在任一列表中则为 true）
        hasSharedCopy := false
        for k in this._generalActive {
            if (k == "SharedCopy") {
                hasSharedCopy := true
                break
            }
        }
        if (!hasSharedCopy) {
            for k in this._branchActive {
                if (k == "BranchSharedCopy") {
                    hasSharedCopy := true
                    break
                }
            }
        }
        MainSoftData.SharedCopy := hasSharedCopy

        ; 直接写入 ini，不需要等待全局保存
        try {
            IniWrite(genStr,           IniFile, IniSection, "GeneralContextMenu")
            IniWrite(branchStr,        IniFile, IniSection, "BranchContextMenu")
            IniWrite(hasSharedCopy,    IniFile, IniSection, "SharedCopy")
        }

        this.Close()
    }
}
