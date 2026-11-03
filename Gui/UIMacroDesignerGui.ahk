#Requires AutoHotkey v2.0

; ===========================================================================
; 界面宏 · 自定义界面设计器（v0.2 · 画布式）
;
; 布局：左「画布」／右「属性」，画布就是浮窗本体，四角可拖动改尺寸。
;
; 交互约定：
;   - 点窗体空白 → 显示窗体属性
;   - 点窗体外画布 → 清除属性
;   - 点控件     → 选中，按住拖动可挪位置
;   - 四角手柄   → 拖动改面板尺寸
;   - 属性改动   → 立即回写并更新画布（不重建窗口）
;
; 为什么拖动要用 MouseGetPos 而不是事件坐标：
;   控件跟着鼠标移动时，它自身的局部坐标基本不变，算不出位移；
;   直接用屏幕坐标做差最稳，代价是按 DPI 缩放折算一次。
; ===========================================================================
class UIMacroDesignerGui {
    static instances := Map()
    static CanvasPad := 20
    static HandleSize := 14

    __new() {
        this.ui := ""
        this.closed := true
        this._instanceKey := ""
        this._foldIndex := 0        ; 折叠框数组下标（PanelMap / DestroyPanel 仍用它）
        this._foldKey := ""         ; 存储键（折叠框 ID），落盘/读盘/占用扫描用它
        this._schema := ""
        this._selId := ""
        this._windowSelected := false
        this._items := []
        this._targets := []
        this._targetsTruncated := false   ; 候选是否被截断（只影响提示文案）
        this._tableItem := ""             ; 当前 UI 表对象（绑定候选/渲染下拉框要用）
        this._boundMacroId := ""          ; 当前字段绑定所在的宏
        this._bindTargetsCtrlId := ""
        this._loading := false
        this._previewUi := ""

        this._dragMode := ""     ; "" / "move" / "resize"
        this._dragCorner := ""
        this._dragStartX := 0
        this._dragStartY := 0
        this._dragCtrlX := 0
        this._dragCtrlY := 0
        this._dragWinW := 0
        this._dragWinH := 0
        this._dragMoved := false
        this._dragStartDipX := 0
        this._dragStartDipY := 0
        this._dragHasDipStart := false
        this._dragLastEventTime := 0
        this._rebuilding := false
        this._hkHwnd := 0
        this._hkBound := false
        this._suppressClosingUntil := 0   ; 重建期间抑制 Closing 误判的时间戳
        this._page := 1                   ; 当前编辑页（1-based）
        this._sideSel := 0                ; 左侧已选控件类型索引（0=未选）
        ; 「回声」防护：程序化 Update 会让 WPF 异步回抛 SelectionChanged，
        ; _loading 只能防同步重入，防不住跨消息的回声。
    }

    ; ------------------------------------------------------------------
    ; 入口
    ; ------------------------------------------------------------------
    static ShowGui(foldIndex) {
        key := "fold" foldIndex

        if (UIMacroDesignerGui.instances.Has(key)) {
            oldInst := UIMacroDesignerGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            UIMacroDesignerGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        try {
            inst := UIMacroDesignerGui()
            inst._instanceKey := key
            inst._foldIndex := foldIndex
            inst._LoadData()
            inst._BuildAndShow()
            UIMacroDesignerGui.instances[key] := inst
        } catch as e {
            MsgBox("设计器打开失败：" e.Message "`n" e.What " @" e.Line, "自定义界面", "Icon!")
            return
        }
    }

    ; ------------------------------------------------------------------
    ; 数据
    ; ------------------------------------------------------------------
    _LoadData() {
        tableItem := GetTableBySymbol("UI")
        fold := (tableItem && tableItem.Folds.Length >= this._foldIndex) ? tableItem.Folds[this._foldIndex] : ""
        this._items := (tableItem && fold) ? GetFoldItems(tableItem, fold) : []

        this._tableItem := tableItem        ; 绑定候选要遍历宏行，留一份引用

        ; 存储键：优先折叠框 ID（稳定），取不到才退回数组下标
        this._foldKey := UIMacroSchema.FoldKey(fold)
        if (this._foldKey == "")
            this._foldKey := String(this._foldIndex)
        else
            UIMacroSchema.MigrateLegacy(this._foldIndex, this._foldKey)

        this._schema := ""
        parsed := UIMacroSchema.Parse(UIMacroSchema.ReadStoreByKey(this._foldKey))
        if (IsObject(parsed))
            this._schema := parsed
        if (!IsObject(this._schema))
            this._schema := UIMacroSchema.FromItems(this._items)

        ; 初次打开时不预选控件。
        this._selId := ""
    }

    ; ------------------------------------------------------------------
    ; 建窗口
    ; ------------------------------------------------------------------
    _BuildAndShow() {
        this.closed := false
        title := "自定义界面"
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "44", "*")

        XAMLHost.AddTitleBar(main, title, titleHeight)

        ; ---- 工具栏 ----
        bar := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal")
            .VerticalAlignment("Center").Margin("12,0,12,0")

        ; 分页用紧凑选择器，避免页数增加时挤压右侧操作按钮。
        ; 控件在左侧选择类型后，通过「添加」按钮加入画布。
        this._IconBtn(bar, "BtnPrevPage", Chr(0xE76B), "上一页", 26)
        bar.Add("ComboBox").Name("DsgPageCon").Width(78).Height(28).MinHeight(28)
            .Margin("0,0,3,0").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        this._IconBtn(bar, "BtnNextPage", Chr(0xE76C), "下一页", 26)
        this._IconBtn(bar, "BtnAddPage", Chr(0xE710), "添加页面", 28, true)
        this._IconBtn(bar, "BtnDeletePage", Chr(0xE74D), "删除当前页", 28)

        bar.Add("Border").Width("1").Height("20").Margin("8,0").Background("{DynamicResource ControlBorder}")

        this._ToolBtn(bar, "BtnReload", "刷新", 50)
        this._ToolBtn(bar, "BtnPreview", "预览", 56)
        this._ToolBtn(bar, "BtnSave", "保存", 56)
        this._ToolBtn(bar, "BtnCancel", "关闭", 56)

        ; ---- 主体 ----
        body := main.Add("Grid").Grid_Row(2).Margin("12,0,12,12")
        body.Cols(48, "6", "*", "12", "250")

        ; 画布工作区（Border 只能有一个子元素，所以外面套一层 Grid）
        wsHost := body.Add("Border").Grid_Column(2)
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
        wsGrid := wsHost.Add("Grid")
        wsGrid.Rows("24", "*")
        wsGrid.Add("TextBlock").Grid_Row(0).Text("设计画布").FontSize("11").Margin("8,6,0,0")
            .Foreground("{DynamicResource TextSub}")

        ; ---- 左侧图标栏：类型纵向排列，操作按钮固定在底部 ----
        sideHost := body.Add("Grid").Grid_Column(0)
        sideHost.Rows("*", "Auto")
        sideScroll := sideHost.Add("ScrollViewer").Grid_Row(0)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        side := sideScroll.Add("StackPanel")
        this._sideTypes := []
        this._sideExpand := Map("控件", true, "图形", true)

        ; 字段生成是独立工具，不属于控件类型列表。
        this._IconBtn(side, "BtnCreateFromField", Chr(0xE74C), "从字段生成控件", 30)

        ; 分组标题：控件
        gh := side.Add("Border").Name("SideGrpHdr0").Height(24)
            .Background("Transparent").Cursor("Hand")
        ghg := gh.Add("Grid")
        ghg.Add("TextBlock").Name("SideGrpCaret0").Text("▾").FontSize("9")
            .Foreground("{DynamicResource TextSub}").Margin("4,0,4,0")
            .HorizontalAlignment("Left").VerticalAlignment("Center")
        ghg.Add("TextBlock").Text("控件").FontSize("11")
            .Foreground("{DynamicResource TextSub}").Margin("16,0,0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Center")

        sideCtrlGrid := side.Add("UniformGrid").Name("SideCtrlGrid").Columns(1)
        for t in UIMacroSchema.ControlTypes() {
            this._SideRow(sideCtrlGrid, this._sideTypes.Length + 1, t)
            this._sideTypes.Push(t)
        }

        ; 分组标题：图形
        gh2 := side.Add("Border").Name("SideGrpHdr1").Height(24).Margin("0,2,0,0")
            .Background("Transparent").Cursor("Hand")
        ghg2 := gh2.Add("Grid")
        ghg2.Add("TextBlock").Name("SideGrpCaret1").Text("▾").FontSize("9")
            .Foreground("{DynamicResource TextSub}").Margin("4,0,4,0")
            .HorizontalAlignment("Left").VerticalAlignment("Center")
        ghg2.Add("TextBlock").Text("图形").FontSize("11")
            .Foreground("{DynamicResource TextSub}").Margin("16,0,0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Center")

        sideShapeGrid := side.Add("UniformGrid").Name("SideShapeGrid").Columns(1)
        for t in UIMacroSchema.ShapeTypes() {
            this._SideRow(sideShapeGrid, this._sideTypes.Length + 1, t)
            this._sideTypes.Push(t)
        }

        sideFooter := sideHost.Add("StackPanel").Grid_Row(1).Margin("0,8,0,0")
        sideFooter.Add("Border").Height("1").Margin("0,0,0,8")
            .Background("{DynamicResource ControlBorder}")
        addBtn := this._IconBtn(sideFooter, "BtnSideAdd", Chr(0xE710), "添加所选控件", 30, true)
        addBtn.IsEnabled("False")
        this._IconBtn(sideFooter, "BtnDel", Chr(0xE74D), "删除选中控件", 30)
        layerBtn := sideFooter.Add("Button").Name("BtnLayers")
            .Width(30).Height(28).MinHeight(28).Margin("0,0,3,3").Padding("0")
            .HorizontalAlignment("Center").Cursor("Hand").ToolTip("打开控件列表")
            .Foreground("{DynamicResource TextMain}").Background("Transparent").BorderThickness("0")
        layerGlyph := layerBtn.Add("Grid").Width(14).Height(14)
        layerGlyph.Add("Border").Width(9).Height(6).Margin("4,0,0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Top")
            .Background("Transparent").BorderBrush("{DynamicResource TextMain}").BorderThickness("1")
        layerGlyph.Add("Border").Width(9).Height(6).Margin("1,4,0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Top")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource TextMain}").BorderThickness("1")
        try layerBtn.InjectResources(UIMacroRenderer.BtnStyle)

        workspace := wsGrid.Add("Grid").Grid_Row(1).Name("Workspace")

        ; 画布外工作区独立命中，避免依赖父级隧道事件与子级异步回调的顺序。
        workspace.Add("Border").Name("WorkspaceBlank").Background("Transparent")

        ; 工作区底板网格（节点编辑器那种）：先画线，再放面板，面板自然盖在上面。
        ; DrawingBrush 不能内联注入属性，所以用 1px 细线平铺。
        gridColor := "#14000000"
        loop 1200 // 16 {
            gp := A_Index * 16
            workspace.Add("Border").Width("1").Height(1200).Margin(gp ",0,0,0")
                .HorizontalAlignment("Left").VerticalAlignment("Top")
                .Background(gridColor).IsHitTestVisible("False")
            workspace.Add("Border").Width(1200).Height("1").Margin("0," gp ",0,0")
                .HorizontalAlignment("Left").VerticalAlignment("Top")
                .Background(gridColor).IsHitTestVisible("False")
        }

        ; 画布本体（= 浮窗内容区）
        canvas := workspace.Add("Grid").Name("DesignCanvas")
            .Width(Integer(this._schema.window.width))
            .Height(Integer(this._schema.window.height))
            .Margin(UIMacroDesignerGui.CanvasPad "," UIMacroDesignerGui.CanvasPad ",0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Top")
            .Background("{DynamicResource BgColor}")
            .ClipToBounds("True")

        ; 窗体空白独立命中；后续控件作为同级元素绘制在其上方。
        canvas.Add("Border").Name("CanvasBlank").Background("Transparent")

        this._ctrlMap := UIMacroRenderer.Render(canvas, this._schema, this._CanvasRenderOpt())

        ; 窗体外框独立覆盖显示，不参与画布命中。
        workspace.Add("Border").Name("WindowFrame")
            .Width(Integer(this._schema.window.width))
            .Height(Integer(this._schema.window.height))
            .Margin(UIMacroDesignerGui.CanvasPad "," UIMacroDesignerGui.CanvasPad ",0,0")
            .HorizontalAlignment("Left").VerticalAlignment("Top")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .IsHitTestVisible("False")

        ; 选中框（不参与命中）
        workspace.Add("Border").Name("SelBox").Visibility("Collapsed")
            .BorderBrush("{DynamicResource ActionBg}").BorderThickness("1")
            .IsHitTestVisible("False").HorizontalAlignment("Left").VerticalAlignment("Top")

        ; 四角拖拽手柄
        for corner in ["TL", "TR", "BL", "BR"] {
            handle := workspace.Add("Border").Name("H_" corner)
                .Width(UIMacroDesignerGui.HandleSize).Height(UIMacroDesignerGui.HandleSize)
                .Background("Transparent")
                .HorizontalAlignment("Left").VerticalAlignment("Top").Cursor("SizeNWSE")
            handle.Add("Border").Width(8).Height(8)
                .Background("{DynamicResource ActionBg}").CornerRadius("2")
                .HorizontalAlignment("Center").VerticalAlignment("Center")
                .IsHitTestVisible("False")
        }

        ; 右侧属性
        rp := body.Add("Border").Grid_Column(4)
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("4")
        propScroll := rp.Add("ScrollViewer")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        pp := propScroll.Add("StackPanel").Margin("10")

        propHeader := pp.Add("Grid").Cols("*", "Auto").Margin("0,0,0,2")
        propHeader.Add("TextBlock").Text("属性").FontSize("13").FontWeight("SemiBold")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        propHeader.Add("TextBlock").Name("TypeVal").Grid_Column(1).Text("-").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")

        ; 布局
        rowLayout := pp.Add("StackPanel").Name("rowLayout")
        this._PropSection(rowLayout, "布局", 4)
        rowXY := rowLayout.Add("Grid").Name("rowXY").Cols("*", "8", "*")
        this._PropRow(rowXY.Add("StackPanel").Grid_Column(0), "X", "XCon")
        this._PropRow(rowXY.Add("StackPanel").Grid_Column(2), "Y", "YCon")
        rowWH := rowLayout.Add("Grid").Name("rowWH").Cols("*", "8", "*")
        this._PropRow(rowWH.Add("StackPanel").Grid_Column(0), "宽", "WCon", "0 表示延伸到画布右侧")
        this._PropRow(rowWH.Add("StackPanel").Grid_Column(2), "高", "HCon")

        ; 外观
        rowAppearance := pp.Add("StackPanel").Name("rowAppearance")
        this._PropSection(rowAppearance, "外观")
        rowText := rowAppearance.Add("StackPanel").Name("rowText")
        this._PropRow(rowText, "文本", "TextCon")
        rowFontSize := rowAppearance.Add("Grid").Name("rowFontSize")
            .Cols("44", "*").Margin("0,0,0,6")
        rowFontSize.Add("TextBlock").Text("字号").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        fontSizeGrid := rowFontSize.Add("Grid").Grid_Column(1).Cols("27", "3", "*", "3", "27")
        fontMinus := this._IconBtn(fontSizeGrid, "BtnFontSizeDown", Chr(0xE738), "缩小字号", 24)
        fontMinus.Grid_Column(0)
        fontSizeGrid.Add("TextBox").Name("FontSizeCon").Grid_Column(2)
            .Height(26).MinHeight(26).Padding("4,0").FontSize("12")
            .VerticalContentAlignment("Center").HorizontalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ToolTip("自定义字号：8 到 48")
        fontPlus := this._IconBtn(fontSizeGrid, "BtnFontSizeUp", Chr(0xE710), "放大字号", 24)
        fontPlus.Grid_Column(4)
        rowTextColor := rowAppearance.Add("Grid").Name("rowTextColor")
            .Cols("44", "*").Margin("0,0,0,8")
        rowTextColor.Add("TextBlock").Text("文字色").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        colorRow := rowTextColor.Add("Grid").Grid_Column(1).Cols("*", "Auto", "4", "Auto")
        colorRow.Add("TextBlock").Name("TextColorMode").Text("跟随主题")
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        colorPick := colorRow.Add("Button").Name("BtnTextColorPick").Grid_Column(1)
            .Width(32).Height(26).MinHeight(26).Padding("0").Cursor("Hand")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ToolTip("选择文字颜色")
        colorPick.Add("Border").Name("TextColorSwatch").Width(20).Height(14)
            .Background("{DynamicResource UIPanelBtnText}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .IsHitTestVisible("False")
        colorReset := this._IconBtn(colorRow, "BtnTextColorReset", Chr(0xE777), "恢复主题颜色", 24)
        colorReset.Grid_Column(3)

        ; 图形专用
        rowShape := pp.Add("StackPanel").Name("rowShape").Visibility("Collapsed")
        this._PropSection(rowShape, "图形")
        shapeColorRow := rowShape.Add("Grid").Cols("44", "*").Margin("0,0,0,8")
        shapeColorRow.Add("TextBlock").Name("ShapeColorLabel").Text("颜色")
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        sc := shapeColorRow.Add("ComboBox").Name("ShapeColorCon").Grid_Column(1)
            .Height(26).MinHeight(26)
        sc.Add("ComboBoxItem").Content("跟随主题")
        sc.Add("ComboBoxItem").Content("强调色")
        sc.Add("ComboBoxItem").Content("次要色")

        ; 绑定摘要只读显示；修改绑定统一通过挑选器完成。
        rowBind := pp.Add("StackPanel").Name("rowBind")
        bindHeader := rowBind.Add("Grid").Cols("*", "Auto").Margin("0,8,0,6")
        bindHeader.Add("TextBlock").Text("绑定").FontSize("11").FontWeight("SemiBold")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        pb := this._IconBtn(bindHeader, "BtnFieldPicker", Chr(0xE74C), "选择绑定字段", 26, true)
        pb.Grid_Column(1).Height(26).MinHeight(26).Margin("0")

        bindRows := rowBind.Add("Grid").Name("BindSummaryRows")
            .Cols("44", "*").Rows("Auto", "Auto")
        bindRows.Add("TextBlock").Grid_Row(0).Text("宏").FontSize("11")
            .Margin("0,2,0,6").Foreground("{DynamicResource TextSub}")
        bindRows.Add("TextBlock").Name("MacroSummary").Grid_Row(0).Grid_Column(1)
            .Text("未设置").FontSize("12").Margin("0,0,0,6")
            .TextWrapping("Wrap").Foreground("{DynamicResource TextMain}")
        bindRows.Add("TextBlock").Grid_Row(1).Text("字段").FontSize("11")
            .Margin("0,2,0,4").Foreground("{DynamicResource TextSub}")
        bindRows.Add("TextBlock").Name("BindingSummary").Grid_Row(1).Grid_Column(1)
            .Text("未绑定").FontSize("12").Margin("0,0,0,4")
            .TextWrapping("Wrap").Foreground("{DynamicResource TextMain}")

        pp.Add("Border").Height("1").Margin("0,8,0,8").Background("{DynamicResource ControlBorder}")
        pp.Add("TextBlock").Name("PanelSizeCon").Text("面板：" UIMacroSchema.Summary(this._schema))
            .FontSize("10").TextWrapping("Wrap").Foreground("{DynamicResource TextSub}")

        ; ---- 宿主 ----
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="' title '" Width="1040" Height="700"')

        ; 恢复上次窗口位置（没有记录就沿用模板的居中）
        pos := this._LoadPos()
        if (pos != "")
            this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"'
                , 'Left="' pos.x '" Top="' pos.y '" WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', this._UIPanelResources())
        this.ui.xaml := StrReplace(this.ui.xaml, '%components%', '')

        ; ---- 事件 ----
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "_OnCancel"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("BtnDel", "Click", ObjBindMethod(this, "_OnDelete"))

        this.ui.OnEvent("ShapeColorCon", "SelectionChanged", ObjBindMethod(this, "_OnShapeColor"))
        this.ui.OnEvent("BtnReload", "Click", ObjBindMethod(this, "_OnReloadMacros"))
        this.ui.OnEvent("BtnSideAdd", "Click", ObjBindMethod(this, "_OnSideAddBtn"))
        this.ui.OnEvent("BtnLayers", "Click", ObjBindMethod(this, "_OnLayers"))
        loop this._sideTypes.Length
            this.ui.OnEvent("SideRow" A_Index, "MouseLeftButtonDown", ObjBindMethod(this, "_OnSidePick", A_Index))
        this.ui.OnEvent("BtnAddPage", "Click", ObjBindMethod(this, "_OnAddPage"))
        this.ui.OnEvent("BtnDeletePage", "Click", ObjBindMethod(this, "_OnDeletePage"))
        this.ui.OnEvent("BtnPreview", "Click", ObjBindMethod(this, "_OnPreview"))
        this.ui.OnEvent("BtnSave", "Click", ObjBindMethod(this, "_OnSave"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "_OnCancel"))

        ; 不绑定父级画布的预览事件；窗体内外空白由独立底层元素命中。

        this._BindCanvasControlEvents()
        for corner in ["TL", "TR", "BL", "BR"] {
            this.ui.OnEvent("H_" corner, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnHandleDown", corner))
            this.ui.OnEvent("H_" corner, "PreviewMouseMove", ObjBindMethod(this, "_OnHandleMove", corner))
            this.ui.OnEvent("H_" corner, "PreviewMouseLeftButtonUp", ObjBindMethod(this, "_OnHandleUp", corner))
        }

        this.ui.OnEvent("TextCon", "TextChanged", ObjBindMethod(this, "_OnTextChanged"))
        this.ui.OnEvent("FontSizeCon", "TextChanged", ObjBindMethod(this, "_OnFontSizeChanged"))
        this.ui.OnEvent("FontSizeCon", "LostFocus", ObjBindMethod(this, "_OnFontSizeCommit"))
        this.ui.OnEvent("BtnFontSizeDown", "Click", ObjBindMethod(this, "_OnFontSizeStep", -1))
        this.ui.OnEvent("BtnFontSizeUp", "Click", ObjBindMethod(this, "_OnFontSizeStep", 1))
        this.ui.OnEvent("XCon", "TextChanged", ObjBindMethod(this, "_OnPosChanged"))
        this.ui.OnEvent("YCon", "TextChanged", ObjBindMethod(this, "_OnPosChanged"))
        this.ui.OnEvent("WCon", "TextChanged", ObjBindMethod(this, "_OnSizeChanged"))
        this.ui.OnEvent("HCon", "TextChanged", ObjBindMethod(this, "_OnSizeChanged"))
        this.ui.OnEvent("WCon", "LostFocus", ObjBindMethod(this, "_OnWindowSizeLostFocus", "WCon"))
        this.ui.OnEvent("HCon", "LostFocus", ObjBindMethod(this, "_OnWindowSizeLostFocus", "HCon"))
        ; 独立底层分别处理窗体空白和窗体外空白，控件由透明命中层处理。
        this.ui.OnEvent("CanvasBlank", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnCanvasDown"))
        this.ui.OnEvent("WorkspaceBlank", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnWorkspaceBlankDown"))
        this.ui.OnEvent("SideGrpHdr0", "MouseLeftButtonDown", ObjBindMethod(this, "_OnSideGrp", "控件"))
        this.ui.OnEvent("SideGrpHdr1", "MouseLeftButtonDown", ObjBindMethod(this, "_OnSideGrp", "图形"))
        this.ui.OnEvent("BtnFieldPicker", "Click", ObjBindMethod(this, "_OnPickFromMacro"))
        this.ui.OnEvent("BtnTextColorPick", "Click", ObjBindMethod(this, "_OnPickTextColor"))
        this.ui.OnEvent("BtnTextColorReset", "Click", ObjBindMethod(this, "_OnResetTextColor"))
        this.ui.OnEvent("BtnCreateFromField", "Click", ObjBindMethod(this, "_OnCreateFromField"))
        this.ui.OnEvent("DsgPageCon", "SelectionChanged", ObjBindMethod(this, "_OnPageSelectionChanged"))
        this.ui.OnEvent("BtnPrevPage", "Click", ObjBindMethod(this, "_OnPrevPage"))
        this.ui.OnEvent("BtnNextPage", "Click", ObjBindMethod(this, "_OnNextPage"))

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            return

        ; 等 WPF 窗口句柄就绪：在此之前 Update/OnEvent 都发不出去
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd)
                break
            Sleep(50)
        }

        this._BindKeys()
        ; 首次建窗就把页码刷出来（否则要手动点一次刷新才出现）
        this._ReloadPageCombo()
        this._ApplySideGroups()
        this._SyncSideHighlight()
        this._SyncHandles()
        this._SyncProps()
        this._SyncPanelSize()
    }

    ; 工具栏分组竖线
    _Sep(bar) {
        bar.Add("Border").Width("1").Height("20").Margin("8,0").Background("{DynamicResource ControlBorder}")
    }

    _ToolBtn(parent, name, text, w) {
        return parent.Add("Button").Name(name).Content(text)
            .Width(w).Height(28).MinHeight(28).Margin("0,0,6,0")
            .FontSize("12").Padding("0").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
    }

    _IconBtn(parent, name, glyph, tip, width := 28, primary := false) {
        btn := parent.Add("Button").Name(name).Content(glyph)
            .Width(width).Height(28).MinHeight(28).Margin("0,0,3,3").Padding("0")
            .HorizontalAlignment("Center")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("14")
            .Cursor("Hand").ToolTip(tip)
            .Foreground(primary ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
            .Background(primary ? "{DynamicResource ActionBg}" : "Transparent")
            .BorderThickness("0")
        try btn.InjectResources(UIMacroRenderer.BtnStyle)
        return btn
    }

    _PropRow(parent, label, name, toolTip := "") {
        parent.Add("TextBlock").Text(label).FontSize("11").Margin("0,0,0,2")
            .Foreground("{DynamicResource TextSub}")
        input := parent.Add("TextBox").Name(name).Height(26).MinHeight(26).Margin("0,0,0,6")
            .FontSize("12").Padding("4,0").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (toolTip != "")
            input.ToolTip(toolTip)
    }

    _PropSection(parent, label, topMargin := 6) {
        parent.Add("TextBlock").Text(label).FontSize("11").FontWeight("SemiBold")
            .Margin("0," topMargin ",0,5").Foreground("{DynamicResource TextSub}")
    }

    ; ------------------------------------------------------------------
    ; 同步
    ; ------------------------------------------------------------------
    _SyncHandles() {
        updates := []
        this._AppendHandleUpdates(updates, true)
        try this.ui.BatchUpdate(updates)
    }

    _AppendHandleUpdates(updates, includeFrame := false) {
        w := Integer(this._schema.window.width)
        h := Integer(this._schema.window.height)
        pad := UIMacroDesignerGui.CanvasPad
        sz := UIMacroDesignerGui.HandleSize
        half := sz // 2
        if (includeFrame) {
            updates.Push({ ControlName: "WindowFrame", PropertyName: "Width", Value: String(w) })
            updates.Push({ ControlName: "WindowFrame", PropertyName: "Height", Value: String(h) })
        }
        pos := Map(
            "TL", Format("{},{},0,0", pad - half, pad - half),
            "TR", Format("{},{},0,0", pad + w - half, pad - half),
            "BL", Format("{},{},0,0", pad - half, pad + h - half),
            "BR", Format("{},{},0,0", pad + w - half, pad + h - half)
        )
        for corner, m in pos {
            updates.Push({ ControlName: "H_" corner, PropertyName: "Margin", Value: m })
        }
    }

    _SyncPanelSize() {
        try this.ui.Update("PanelSizeCon", "Text", "面板：" UIMacroSchema.Summary(this._schema))
    }

    _SyncProps() {
        if (!IsObject(this.ui))
            return
        this._loading := true
        try {
            this._SyncPropsCore()
        } catch {
            ; 属性面板刷新失败（控件未就绪等）不得影响画布选中框与后续交互
        } finally {
            this._loading := false
        }
        ; 无论属性面板是否刷新成功，选中框都必须同步，否则会停在上一处位置
        this._SyncSelBox()
        ; 控件列表若开着：高亮实时跟着选中项走（画布点控件也会触发这里）
        try UIMacroLayerGui.NotifySelection()
    }

    ; 属性行按状态显隐：窗体仅显示宽高，控件按类型显示对应属性。
    _SyncPropRows(isWin, showBind := true, showText := true, showSize := true, showTextStyle := true) {
        try this.ui.Update("rowLayout", "Visibility", showSize ? "Visible" : "Collapsed")
        try this.ui.Update("rowAppearance", "Visibility"
            , (!isWin && (showText || showTextStyle)) ? "Visible" : "Collapsed")
        try this.ui.Update("rowText", "Visibility", (!isWin && showText) ? "Visible" : "Collapsed")
        try this.ui.Update("rowFontSize", "Visibility", (!isWin && showTextStyle) ? "Visible" : "Collapsed")
        try this.ui.Update("rowTextColor", "Visibility", (!isWin && showTextStyle) ? "Visible" : "Collapsed")
        try this.ui.Update("rowXY", "Visibility", (!isWin && showSize) ? "Visible" : "Collapsed")
        try this.ui.Update("rowWH", "Visibility", showSize ? "Visible" : "Collapsed")
        try this.ui.Update("rowShape", "Visibility"
            , (!isWin && !showText && !showTextStyle) ? "Visible" : "Collapsed")
        try this.ui.Update("rowBind", "Visibility", (!isWin && showBind) ? "Visible" : "Collapsed")
    }

    _SyncPropsCore() {
        ctrl := UIMacroSchema.FindById(this._schema, this._selId)
        if (!ctrl) {
            if (this._windowSelected) {
                try this.ui.Update("TypeVal", "Text", "窗体")
                try this.ui.Update("TextCon", "Text", "")
                try this.ui.Update("XCon", "Text", "")
                try this.ui.Update("YCon", "Text", "")
                try this.ui.Update("WCon", "Text", String(this._schema.window.width))
                try this.ui.Update("HCon", "Text", String(this._schema.window.height))
                this._SyncTextStyleProps("")
                try this.ui.Update("MacroSummary", "Text", "")
                try this.ui.Update("BindingSummary", "Text", "")
                try this.ui.Update("SelBox", "Visibility", "Collapsed")
                this._SyncPropRows(true, false, false, true)
                return
            }
            ; 点击窗体外的画布后不显示窗体或控件属性。
            try this.ui.Update("TypeVal", "Text", "-")
            try this.ui.Update("TextCon", "Text", "")
            try this.ui.Update("XCon", "Text", "")
            try this.ui.Update("YCon", "Text", "")
            try this.ui.Update("WCon", "Text", "")
            try this.ui.Update("HCon", "Text", "")
            this._SyncTextStyleProps("")
            try this.ui.Update("MacroSummary", "Text", "")
            try this.ui.Update("BindingSummary", "Text", "")
            try this.ui.Update("SelBox", "Visibility", "Collapsed")
            this._SyncPropRows(true, false, false, false)
            return
        }
        try this.ui.Update("TypeVal", "Text", UIMacroSchema.TypeLabel(ctrl.type))
        try this.ui.Update("TextCon", "Text", ctrl.text)
        try this.ui.Update("XCon", "Text", String(ctrl.x))
        try this.ui.Update("YCon", "Text", String(ctrl.y))
        try this.ui.Update("WCon", "Text", String(ctrl.w))
        try this.ui.Update("HCon", "Text", String(ctrl.h))

        ; 图形颜色
        isShape := UIMacroSchema.IsShapeType(ctrl.type)
        if (isShape) {
            col := ctrl.HasProp("color") ? String(ctrl.color) : ""
            ci := (col == "accent") ? 1 : (col == "sub") ? 2 : 0
            try this.ui.Update("ShapeColorCon", "SelectedIndex", String(ci))
        }

        this._SyncTextStyleProps(ctrl)
        this._SyncPropRows(false, UIMacroSchema.CanBind(ctrl.type), !isShape, true, !isShape)
        if (UIMacroSchema.CanBind(ctrl.type)) {
            ctrlId := String(ctrl.id)
            bindMacroId := this._BindSourceMacroId(ctrl)
            if (ctrlId != this._bindTargetsCtrlId || bindMacroId != this._boundMacroId)
                this._ReloadBindTargets(ctrl)

            actionMacroId := this._ActionMacroId(ctrl)
            try this.ui.Update("MacroSummary", "Text", this._MacroLabel(bindMacroId))
            bindingText := "未绑定"
            if (actionMacroId != "") {
                bindingText := "触发宏"
            } else if (ctrl.HasProp("binding") && IsObject(ctrl.binding)) {
                bindingText := this._BindingDisplayLabel(ctrl)
            }
            try this.ui.Update("BindingSummary", "Text", bindingText)
        }
    }

    _SyncSelBox() {
        updates := []
        this._AppendSelBoxUpdates(updates)
        try this.ui.BatchUpdate(updates)
    }

    _AppendSelBoxUpdates(updates) {
        ctrl := UIMacroSchema.FindById(this._schema, this._selId)
        if (!ctrl) {
            updates.Push({ ControlName: "SelBox", PropertyName: "Visibility", Value: "Collapsed" })
            return
        }
        pad := UIMacroDesignerGui.CanvasPad
        w := UIMacroRenderer.ActualWidth(ctrl, this._schema.window.width)
        updates.Push({ ControlName: "SelBox", PropertyName: "Margin"
            , Value: Format("{},{},0,0", pad + Integer(ctrl.x) - 1, pad + Integer(ctrl.y) - 1) })
        updates.Push({ ControlName: "SelBox", PropertyName: "Width", Value: String(w + 2) })
        updates.Push({ ControlName: "SelBox", PropertyName: "Height", Value: String(Integer(ctrl.h) + 2) })
        updates.Push({ ControlName: "SelBox", PropertyName: "Visibility", Value: "Visible" })
    }

    _SyncTextStyleProps(ctrl) {
        if (!IsObject(ctrl) || UIMacroSchema.IsShapeType(ctrl.type)) {
            try this.ui.Update("FontSizeCon", "Text", "")
            try this.ui.Update("FontSizeCon", "IsEnabled", "False")
            try this.ui.Update("BtnFontSizeDown", "IsEnabled", "False")
            try this.ui.Update("BtnFontSizeUp", "IsEnabled", "False")
            try this.ui.Update("TextColorMode", "Text", "")
            try this.ui.Update("TextColorSwatch", "Background", "{DynamicResource UIPanelBtnText}")
            return
        }
        fontSize := ctrl.HasProp("fontSize")
            ? String(ctrl.fontSize) : String(UIMacroSchema.DefaultTextFontSize)
        textColor := ctrl.HasProp("textColor") ? String(ctrl.textColor) : ""
        try this.ui.Update("FontSizeCon", "Text", fontSize)
        try this.ui.Update("FontSizeCon", "IsEnabled", "True")
        try this.ui.Update("BtnFontSizeDown", "IsEnabled", "True")
        try this.ui.Update("BtnFontSizeUp", "IsEnabled", "True")
        try this.ui.Update("TextColorMode", "Text", textColor == "" ? "跟随主题" : "自定义")
        try this.ui.Update("TextColorSwatch", "Background"
            , textColor == "" ? this._TextColorResource(ctrl.type) : textColor)
    }

    _TextColorResource(type) {
        switch String(type) {
            case "Button":             return "{DynamicResource UIPanelBtnText}"
            case "Edit", "ComboBox":   return "{DynamicResource InputText}"
            default:                   return "{DynamicResource TextMain}"
        }
    }

    _DefaultTextColor(type) {
        key := ""
        switch String(type) {
            case "Button":             key := "Panel_BtnText"
            case "Edit", "ComboBox":   key := "Win_InputText"
            default:                   key := "Win_LabelColor"
        }
        return AppThemeUtil.ResolveColor(MainSoftData.ThemeColors, key)
    }

    ; ------------------------------------------------------------------
    ; 画布交互
    ; ------------------------------------------------------------------
    _OnCanvasDown(state, ctrl, event) {
        this._selId := ""
        this._windowSelected := true
        this._SyncProps()
    }

    _OnWorkspaceBlankDown(state, ctrl, event) {
        this._selId := ""
        this._windowSelected := false
        this._SyncProps()
    }

    _OnCtrlDown(id, state, ctrl, event) {
        MouseGetPos(&mx, &my)
        this._selId := String(id)
        this._windowSelected := false
        this._dragMode := "move"
        this._dragMoved := false
        this._dragStartX := mx
        this._dragStartY := my
        item := UIMacroSchema.FindById(this._schema, id)
        this._dragCtrlX := item ? Integer(item.x) : 0
        this._dragCtrlY := item ? Integer(item.y) : 0
        ; 拖快时鼠标会跑出控件，Move 事件断掉；用定时器接管，保证跟手
        SetTimer(ObjBindMethod(this, "_DragTick"), 15)
        this._SyncProps()
    }

    _OnCtrlMove(id, state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        if (this._dragMode != "move" || String(id) != this._selId)
            return
        MouseGetPos(&mx, &my)
        s := A_ScreenDPI / 96
        dx := Round((mx - this._dragStartX) / s)
        dy := Round((my - this._dragStartY) / s)
        if (Abs(dx) + Abs(dy) > 2)
            this._dragMoved := true
        if (!this._dragMoved)
            return

        item := UIMacroSchema.FindById(this._schema, id)
        if (!item)
            return
        item.x := this._SnapX(this._dragCtrlX + dx, item)
        item.y := this._SnapY(this._dragCtrlY + dy, item)
        this._MoveCtrlVisual(item)
        this._SyncSelBox()
        this._loading := true
        try {
            this.ui.Update("XCon", "Text", String(item.x))
            this.ui.Update("YCon", "Text", String(item.y))
        } finally {
            this._loading := false
        }
    }

    _OnCtrlUp(id, state, ctrl, event) {
        this._StopDrag()
    }

    _StopDrag() {
        SetTimer(ObjBindMethod(this, "_DragTick"), 0)
        this._dragMode := ""
    }

    ; 定时刷新：不依赖鼠标事件是否还落在控件上
    _DragTick() {
        if (this._dragMode == "" || !IsObject(this.ui)) {
            this._StopDrag()
            return
        }
        ; 松开鼠标时手可能已经不在手柄/控件上了，MouseUp 不会再派发过来，
        ; 这里直接读物理按键状态兜底，否则定时器会一直跑（角跟着鼠标跑）。
        if (!GetKeyState("LButton", "P")) {
            this._StopDrag()
            return
        }
        if (this._dragMode == "move" && this._selId != "")
            this._OnCtrlMove(this._selId, 0, 0, 0)
        else if (this._dragMode == "resize"
            && A_TickCount - this._dragLastEventTime >= 40)
            this._OnHandleMove(this._dragCorner, 0, 0, 0)
    }

    _MoveCtrlVisual(item) {
        if (!IsObject(this.ui))
            return
        name := UIMacroRenderer.NameOf(item.id)
        width := UIMacroRenderer.ActualWidth(item, this._schema.window.width)
        margin := Format("{},{},0,0", Integer(item.x), Integer(item.y))
        try this.ui.Update(name, "Margin", margin)
        try this.ui.Update(name, "Width", String(width))
        try this.ui.Update(UIMacroRenderer.HitNameOf(item.id), "Margin", margin)
        try this.ui.Update(UIMacroRenderer.HitNameOf(item.id), "Width", String(width))
    }

    ; ------------------------------------------------------------------
    ; 吸附：4px 网格 + 贴边/居中
    ; ------------------------------------------------------------------
    _SnapX(x, item) {
        this._ConstrainCtrlToWindow(item)
        panelW := Integer(this._schema.window.width)
        x := Round(x / 4) * 4
        if (Abs(x) <= 6)
            x := 0
        if (Integer(item.w) == 0)
            return Max(0, Min(panelW - 20, x))
        w := UIMacroRenderer.ActualWidth(item, panelW)
        if (Abs(x + w - panelW) <= 6)
            x := panelW - w
        if (Abs(x + w / 2 - panelW / 2) <= 6)
            x := Round((panelW - w) / 2)
        return Max(0, Min(panelW - w, x))
    }

    _SnapY(y, item) {
        this._ConstrainCtrlToWindow(item)
        panelH := Integer(this._schema.window.height)
        h := Integer(item.h)
        y := Round(y / 4) * 4
        if (Abs(y) <= 6)
            y := 0
        if (Abs(y + h - panelH) <= 6)
            y := panelH - h
        if (Abs(y + h / 2 - panelH / 2) <= 6)
            y := Round((panelH - h) / 2)
        return Max(0, Min(panelH - h, y))
    }

    ; ------------------------------------------------------------------
    ; 面板尺寸拖拽
    ; ------------------------------------------------------------------
    _ReadEventPoint(state, key) {
        if (!IsObject(state) || !state.Has(key))
            return ""
        parts := StrSplit(String(state[key]), ",")
        if (parts.Length < 2 || !IsNumber(parts[1]) || !IsNumber(parts[2]))
            return ""
        return { X: Float(parts[1]), Y: Float(parts[2]) }
    }

    _WindowDpiScale() {
        dpi := 0
        if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd)
            try dpi := DllCall("user32\GetDpiForWindow", "Ptr", this.ui.wpfHwnd, "UInt")
        if (!dpi)
            dpi := A_ScreenDPI
        return dpi / 96.0
    }

    _OnHandleDown(corner, state, ctrl, event) {
        this._selId := ""
        this._windowSelected := true
        this._SyncProps()
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        this._dragMode := "resize"
        this._dragCorner := corner
        this._dragStartX := mx
        this._dragStartY := my
        point := this._ReadEventPoint(state, "DragCoords")
        this._dragHasDipStart := IsObject(point)
        if (this._dragHasDipStart) {
            this._dragStartDipX := point.X
            this._dragStartDipY := point.Y
        }
        this._dragLastEventTime := A_TickCount
        this._dragWinW := Integer(this._schema.window.width)
        this._dragWinH := Integer(this._schema.window.height)
        SetTimer(ObjBindMethod(this, "_DragTick"), 15)
    }

    _OnHandleMove(corner, state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        if (this._dragMode != "resize" || corner != this._dragCorner)
            return
        point := this._ReadEventPoint(state, "DragCoords")
        if (IsObject(point) && this._dragHasDipStart) {
            this._dragLastEventTime := A_TickCount
            dx := Round(point.X - this._dragStartDipX)
            dy := Round(point.Y - this._dragStartDipY)
        } else {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            s := this._WindowDpiScale()
            dx := Round((mx - this._dragStartX) / s)
            dy := Round((my - this._dragStartY) / s)
        }

        w := this._dragWinW
        h := this._dragWinH
        if (InStr(corner, "R"))
            w := this._dragWinW + dx
        if (InStr(corner, "L"))
            w := this._dragWinW - dx
        if (InStr(corner, "B"))
            h := this._dragWinH + dy
        if (InStr(corner, "T"))
            h := this._dragWinH - dy

        this._SetWindowSize(Round(w / 4) * 4, Round(h / 4) * 4, true)
    }

    _OnHandleUp(corner, state, ctrl, event) {
        this._StopDrag()
    }

    ; ------------------------------------------------------------------
    ; 属性改动
    ; ------------------------------------------------------------------
    _OnTextChanged(*) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item)
            return
        item.text := this.ui.Query("TextCon")
        this._RefreshCtrlVisual(item)
    }

    _OnFontSizeChanged(*) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || UIMacroSchema.IsShapeType(item.type))
            return

        value := Trim(String(this.ui.Query("FontSizeCon")))
        if (!RegExMatch(value, "^\d{1,2}$"))
            return
        fontSize := Integer(value)
        if (fontSize < UIMacroSchema.MinTextFontSize || fontSize > UIMacroSchema.MaxTextFontSize)
            return
        item.fontSize := fontSize

        this._ConstrainCtrlToWindow(item)
        this._RefreshCtrlVisual(item)
        this._SyncCtrlHeightInput(item)
        this._SyncSelBox()
    }

    _OnFontSizeCommit(*) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || UIMacroSchema.IsShapeType(item.type))
            return

        value := Trim(String(this.ui.Query("FontSizeCon")))
        if (RegExMatch(value, "^\d{1,2}$")) {
            fontSize := Integer(value)
            if (fontSize >= UIMacroSchema.MinTextFontSize && fontSize <= UIMacroSchema.MaxTextFontSize)
                return
        }
        wasLoading := this._loading
        this._loading := true
        try this._SyncTextStyleProps(item)
        finally this._loading := wasLoading
    }

    _OnFontSizeStep(step, *) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || UIMacroSchema.IsShapeType(item.type))
            return

        currentSize := item.HasProp("fontSize")
            ? Integer(item.fontSize) : UIMacroSchema.DefaultTextFontSize
        item.fontSize := Max(UIMacroSchema.MinTextFontSize
            , Min(UIMacroSchema.MaxTextFontSize, currentSize + step))
        this._ConstrainCtrlToWindow(item)
        this._RefreshCtrlVisual(item)
        this._SyncCtrlHeightInput(item)
        this._SyncSelBox()
        this._SyncTextStyleProps(item)
    }

    _OnPickTextColor(*) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || UIMacroSchema.IsShapeType(item.type))
            return

        currentColor := item.HasProp("textColor") ? String(item.textColor) : this._DefaultTextColor(item.type)
        result := XColorPicker.Show({
            Title: "文字颜色",
            DefaultColor: currentColor,
            Owner: this.ui.wpfHwnd,
            Modal: true
        })
        if (result.Status != "OK")
            return
        color := UIMacroSchema.NormalizeTextColor(result.Color)
        if (color == "")
            return

        item.textColor := color
        this._RefreshCtrlVisual(item)
        this._SyncTextStyleProps(item)
    }

    _OnResetTextColor(*) {
        if (this._loading || this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || UIMacroSchema.IsShapeType(item.type))
            return
        if (item.HasProp("textColor"))
            item.DeleteProp("textColor")
        this._RefreshCtrlVisual(item)
        this._SyncTextStyleProps(item)
    }

    _OnPosChanged(*) {
        ; 无选择状态：X/Y 数值不适用（窗体位置由拖放/位置记忆管理）
        if (this._selId == "")
            return
        if (this._loading)
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item)
            return
        item.x := Max(0, this._NumOr(this.ui.Query("XCon"), item.x))
        item.y := Max(0, this._NumOr(this.ui.Query("YCon"), item.y))
        this._ConstrainCtrlToWindow(item)
        this._MoveCtrlVisual(item)
        this._SyncSelBox()
    }

    _OnSizeChanged(*) {
        if (this._loading)
            return
        if (this._windowSelected) {
            width := this._NumOr(this.ui.Query("WCon"), this._schema.window.width)
            height := this._NumOr(this.ui.Query("HCon"), this._schema.window.height)
            this._SetWindowSize(width, height)
            return
        }
        if (this._selId == "")
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item)
            return
        item.w := Max(0, Min(Integer(this._schema.window.width)
            , this._NumOr(this.ui.Query("WCon"), item.w)))
        minH := this._MinCtrlHeight(item)
        item.h := Max(minH, Min(UIMacroSchema.MaxCtrlHeight
            , Integer(this._schema.window.height)
            , this._NumOr(this.ui.Query("HCon"), item.h)))
        this._ConstrainCtrlToWindow(item)
        this._RefreshCtrlVisual(item)
        this._SyncCtrlHeightInput(item)
        this._SyncSelBox()
    }

    _ConstrainCtrlToWindow(item) {
        panelW := Integer(this._schema.window.width)
        panelH := Integer(this._schema.window.height)
        minH := this._MinCtrlHeight(item)
        item.h := Max(minH, Min(panelH, UIMacroSchema.MaxCtrlHeight, Integer(item.h)))

        if (Integer(item.w) == 0) {
            item.x := Max(0, Min(panelW - 20, Integer(item.x)))
        } else {
            item.w := Max(1, Min(panelW, Integer(item.w)))
            item.x := Max(0, Min(panelW - item.w, Integer(item.x)))
        }
        item.y := Max(0, Min(panelH - item.h, Integer(item.y)))
    }

    _MinCtrlHeight(item) {
        if (UIMacroSchema.IsShapeType(item.type))
            return 2
        minH := UIMacroSchema.MinCtrlHeight
        if (item.HasProp("fontSize"))
            minH := Max(minH, UIMacroSchema.MinTextHeight(item.fontSize))
        return minH
    }

    _SyncCtrlHeightInput(item) {
        wasLoading := this._loading
        this._loading := true
        try this.ui.Update("HCon", "Text", String(item.h))
        finally this._loading := wasLoading
    }

    _SetWindowSize(width, height, syncInputs := false) {
        oldPanelW := Integer(this._schema.window.width)
        oldPanelH := Integer(this._schema.window.height)
        newPanelW := Max(UIMacroSchema.MinWinWidth
            , Min(UIMacroSchema.MaxWinWidth, Integer(width)))
        newPanelH := Max(UIMacroSchema.MinWinHeight
            , Min(UIMacroSchema.MaxWinHeight, Integer(height)))

        if (newPanelW == oldPanelW && newPanelH == oldPanelH) {
            if (syncInputs && this._windowSelected)
                this._SyncWindowSizeInputs()
            return
        }

        this._schema.window.width := newPanelW
        this._schema.window.height := newPanelH
        updates := []
        for item in this._schema.controls {
            oldX := Integer(item.x)
            oldY := Integer(item.y)
            oldW := Integer(item.w)
            oldH := Integer(item.h)
            oldActualW := UIMacroRenderer.ActualWidth(item, oldPanelW)
            this._ConstrainCtrlToWindow(item)
            newActualW := UIMacroRenderer.ActualWidth(item, newPanelW)
            changed := (item.x != oldX || item.y != oldY || item.w != oldW
                || item.h != oldH || newActualW != oldActualW)
            id := String(item.id)
            if (changed && this._ctrlMap.Has(id)) {
                info := this._ctrlMap[id]
                this._AppendCtrlGeometryUpdates(updates, item, info)
            }
        }
        updates.Push({ ControlName: "DesignCanvas", PropertyName: "Width", Value: String(newPanelW) })
        updates.Push({ ControlName: "DesignCanvas", PropertyName: "Height", Value: String(newPanelH) })
        this._AppendHandleUpdates(updates, true)
        updates.Push({ ControlName: "PanelSizeCon", PropertyName: "Text"
            , Value: "面板：" UIMacroSchema.Summary(this._schema) })
        if (this._selId == "")
            this._AppendSelBoxUpdates(updates)
        if (this._selId != "")
            this._SyncProps()
        if (syncInputs && this._windowSelected) {
            updates.Push({ ControlName: "WCon", PropertyName: "Text", Value: String(newPanelW) })
            updates.Push({ ControlName: "HCon", PropertyName: "Text", Value: String(newPanelH) })
        }

        wasLoading := this._loading
        this._loading := true
        try this.ui.BatchUpdate(updates)
        finally this._loading := wasLoading
    }

    _AppendCtrlGeometryUpdates(updates, item, info) {
        margin := Format("{},{},0,0", Integer(item.x), Integer(item.y))
        width := String(UIMacroRenderer.ActualWidth(item, this._schema.window.width))
        height := String(item.h)
        for name in [info.name, info.HasProp("hitName") ? info.hitName : ""] {
            if (name == "")
                continue
            updates.Push({ ControlName: name, PropertyName: "Margin", Value: margin })
            updates.Push({ ControlName: name, PropertyName: "Width", Value: width })
            updates.Push({ ControlName: name, PropertyName: "Height", Value: height })
        }
    }

    _OnWindowSizeLostFocus(name, *) {
        if (this._windowSelected)
            this._SyncWindowSizeInputs(name)
    }

    _SyncWindowSizeInputs(name := "") {
        wasLoading := this._loading
        this._loading := true
        try {
            if (name == "" || name == "WCon") {
                try this.ui.Update("WCon", "Text", String(this._schema.window.width))
            }
            if (name == "" || name == "HCon") {
                try this.ui.Update("HCon", "Text", String(this._schema.window.height))
            }
        } finally {
            this._loading := wasLoading
        }
    }

    _NumOr(raw, def) {
        s := Trim(String(raw))
        if (s == "" || !IsInteger(s))
            return def
        return Integer(s)
    }

    ; 属性改动后重建该控件：类型可能变，重建整个窗口代价太大，
    ; v0.2 只处理「外观类」属性，位置尺寸直接 Update 即可。
    _RefreshCtrlVisual(item) {
        name := UIMacroRenderer.NameOf(item.id)
        hitName := UIMacroRenderer.HitNameOf(item.id)
        w := UIMacroRenderer.ActualWidth(item, this._schema.window.width)
        margin := Format("{},{},0,0", Integer(item.x), Integer(item.y))
        try this.ui.Update(name, "Margin", margin)
        try this.ui.Update(name, "Width", String(w))
        try this.ui.Update(name, "Height", String(item.h))
        try this.ui.Update(hitName, "Margin", margin)
        try this.ui.Update(hitName, "Width", String(w))
        try this.ui.Update(hitName, "Height", String(item.h))
        if (!UIMacroSchema.IsShapeType(item.type)) {
            fontSize := item.HasProp("fontSize")
                ? Integer(item.fontSize) : UIMacroSchema.DefaultTextFontSize
            textColor := item.HasProp("textColor")
                ? String(item.textColor) : this._TextColorResource(item.type)
            try this.ui.Update(name, "FontSizeCustom", String(fontSize))
            try this.ui.Update(name, "Foreground", textColor)
        }
        try {
            switch item.type {
                case "Button":
                    this.ui.Update(name, "Content", item.text)
                case "CheckBox":
                    this.ui.Update(name, "Content", item.text)
                case "Edit":
                    this.ui.Update(name, "Text", item.text)
                case "TextBlock":
                    this.ui.Update(name, "Text", item.text)
            }
        }
    }

    _ActionMacroId(ctrl) {
        if (!IsObject(ctrl) || !ctrl.HasProp("action"))
            return ""
        if (IsObject(ctrl.action) && ctrl.action.HasProp("macroId"))
            return String(ctrl.action.macroId)
        return ""
    }

    _MacroLabel(macroId) {
        if (macroId == "")
            return "未设置"
        tableItem := GetItemTableGlobal(macroId)
        if (!IsObject(tableItem) || !tableItem.HasProp("Items"))
            return "宏不存在（" macroId "）"
        macroType := this._MacroTypeLabel(tableItem)
        for i, item in tableItem.Items {
            if (String(item.ID) != String(macroId))
                continue
            remark := item.HasProp("Remark") ? Trim(String(item.Remark)) : ""
            label := macroType " " i
            if (remark != "")
                label .= ". " remark
            return label
        }
        return "宏不存在（" macroId "）"
    }

    _MacroTypeLabel(tableItem) {
        symbol := tableItem.HasProp("Symbol") ? String(tableItem.Symbol) : ""
        if (symbol != "") {
            for def in CreateDefaultTableDefs() {
                if (String(def[1]) == symbol)
                    return GetLang(String(def[2]))
            }
        }
        name := tableItem.HasProp("Name") ? Trim(GetLang(String(tableItem.Name))) : ""
        return name != "" ? name : (symbol != "" ? symbol : "宏")
    }

    ; 字段绑定优先决定挑选器的初始宏；未绑定字段时跟随触发宏。
    _BindSourceMacroId(ctrl) {
        if (IsObject(ctrl) && ctrl.HasProp("binding") && IsObject(ctrl.binding)
            && ctrl.binding.HasProp("macroId")) {
            mid := String(ctrl.binding.macroId)
            if (mid != "")
                return mid
        }
        return this._ActionMacroId(ctrl)
    }

    ; 加载当前字段所属宏的候选，仅用于摘要显示和旧格式路径恢复。
    _ReloadBindTargets(ctrl := "") {
        if (!IsObject(ctrl))
            ctrl := UIMacroSchema.FindById(this._schema, this._selId)
        this._bindTargetsCtrlId := IsObject(ctrl) ? String(ctrl.id) : ""
        this._targets := []
        this._targetsTruncated := false
        this._boundMacroId := this._BindSourceMacroId(ctrl)
        if (this._boundMacroId == "")
            return
        try {
            collected := UIMacroStepBinding.CollectTargetsForMacro(this._tableItem, this._boundMacroId)
            this._targets := collected.items
            this._targetsTruncated := collected.truncated
        }
        if (IsObject(ctrl))
            this._NormalizeDataBindingHops(ctrl)
    }

    _BindingDisplayLabel(ctrl) {
        binding := ctrl.binding
        this._NormalizeDataBindingHops(ctrl)
        mode := binding.HasProp("mode") ? String(binding.mode) : "step"
        fieldLabel := ""
        if (mode == "data") {
            spec := UIMacroStepBinding.SpecOfData(binding.kind, binding.field)
            fieldLabel := IsObject(spec) ? spec.label : "字段不可用"
            got := UIMacroStepBinding.ReadData(binding.serial, binding.field)
            if (!got.ok)
                return "目标已失效：" fieldLabel
        }
        if (mode == "skip") {
            got := UIMacroStepBinding.ReadSkipDeep(this._tableItem, binding)
            if (!got.ok)
                return "目标已失效：是否执行"
            fieldLabel := "是否执行"
        } else if (mode != "data") {
            spec := UIMacroStepBinding.SpecOfBindingDeep(this._tableItem, binding)
            if (!IsObject(spec) || !spec.HasProp("label"))
                return "目标已失效"
            fieldLabel := spec.label
        }
        stepLabel := this._BindingStepLabel(binding, mode)
        return stepLabel != "" ? stepLabel "_" fieldLabel : fieldLabel
    }

    _BindingStepLabel(binding, mode) {
        hops := binding.HasProp("hops") ? binding.hops : ""
        resolved := UIMacroStepBinding.ResolveContainer(this._tableItem, binding.macroId, hops)
        if (!resolved.ok)
            return ""

        stepNumber := 0
        command := ""
        if (mode == "data") {
            for i, text in UIMacroStepBinding.MacroSteps(resolved.text) {
                stepMode := UIMacroStepBinding.StepModeOf(text)
                if (String(stepMode.mode) != "data"
                    || String(stepMode.kind) != String(binding.kind)
                    || String(stepMode.serial) != String(binding.serial))
                    continue
                stepNumber := i
                command := stepMode.kind
                break
            }
        } else {
            stepNumber := Integer(binding.step)
            text := UIMacroStepBinding.GetStep(resolved.text, stepNumber)
            segs := UIMacroStepBinding.SplitStep(text)
            if (segs.Length)
                command := GetCmdStr(String(segs[1]))
        }
        if (stepNumber < 1 || command == "")
            return ""

        label := "第" stepNumber "步_" command
        pathLabel := this._BindingPathLabel(binding)
        return pathLabel != "" ? pathLabel "_" label : label
    }

    _BindingPathLabel(binding) {
        if (!binding.HasProp("hops") || !IsObject(binding.hops) || binding.hops.Length == 0)
            return ""
        label := ""
        for hop in binding.hops {
            obj := UIMacroStepBinding.GetDataObj(hop.serial)
            branchLabel := ""
            for container in UIMacroStepBinding.HopContainers(hop.kind, obj) {
                if (String(container.field) == String(hop.field)
                    && String(container.index) == String(hop.index)) {
                    branchLabel := container.label
                    break
                }
            }
            if (branchLabel == "")
                branchLabel := String(hop.field)
            label .= (label == "" ? "" : "_")
                . "第" hop.step "步_" hop.kind "_" branchLabel
        }
        return label
    }

    _DataBindingTargetMatches(binding) {
        key := UIMacroStepBinding.DataBindingKeyOf(
            binding.macroId, binding.kind, binding.serial, binding.field)
        firstTarget := ""
        firstPathKey := ""
        count := 0
        for target in this._targets {
            if (String(target.mode) != "data")
                continue
            targetKey := UIMacroStepBinding.DataBindingKeyOf(
                target.macroId, target.kind, target.serial, target.field)
            if (targetKey != key)
                continue
            pathKey := UIMacroStepBinding.HopsKey(target)
            if (count == 0) {
                firstTarget := target
                firstPathKey := pathKey
                count := 1
            } else if (pathKey != firstPathKey) {
                return { count: 2, target: firstTarget }
            }
        }
        return { count: count, target: firstTarget }
    }

    _NormalizeDataBindingHops(ctrl) {
        if (this._targetsTruncated || !IsObject(ctrl) || !ctrl.HasProp("binding")
            || !IsObject(ctrl.binding) || !ctrl.binding.HasProp("mode")
            || String(ctrl.binding.mode) != "data")
            return
        binding := ctrl.binding
        if (binding.HasProp("hops") && IsObject(binding.hops) && binding.hops.Length > 0)
            return
        matches := this._DataBindingTargetMatches(binding)
        if (matches.count == 1 && IsObject(matches.target)
            && matches.target.HasProp("hops") && IsObject(matches.target.hops)
            && matches.target.hops.Length > 0)
            binding.hops := matches.target.hops
    }

    ; 重填画布上下拉框控件的选项（绑定变了选项跟着变），并恢复当前值显示
    _ReloadCanvasCombo(ctrl) {
        if (!IsObject(ctrl))
            return
        this._loading := true
        try {
            name := UIMacroRenderer.NameOf(ctrl.id)
            this.ui.Update(name, "ClearItems", "")
            spec := UIMacroRenderer.SpecOfCtrl(ctrl, this._tableItem)
            options := UIMacroRenderer.OptionsOf(ctrl, spec, this._tableItem)
            if (IsObject(options)) {
                for pair in options
                    this.ui.Update(name, "AddItem", String(pair[2]))
            }
            ; 恢复当前值显示（新绑定参数的现值）
            val := ""
            if (ctrl.HasProp("binding") && IsObject(ctrl.binding)) {
                b := ctrl.binding
                if (String(b.mode) == "data") {
                    got := UIMacroStepBinding.ReadData(b.serial, b.field)
                    val := got.ok ? got.value : ""
                    spec := UIMacroStepBinding.SpecOfData(b.kind, b.field)
                } else if (IsObject(this._tableItem)) {
                    item := UIMacroStepBinding.FindMacroItem(this._tableItem, b.macroId)
                    if (IsObject(item)) {
                        val := UIMacroStepBinding.ReadParam(item.Macro, b.step, b.param)
                        spec := UIMacroStepBinding.SpecOfBinding(this._tableItem, b)
                    }
                }
            }
            UIMacroRenderer.SetValue(this.ui, ctrl.id, "ComboBox", val, spec)
        } catch {
        }
        this._loading := false
    }

    ; ------------------------------------------------------------------
    ; 增删（结构变化 → 重建窗口）
    ; ------------------------------------------------------------------
    ; 先选择类型，再由固定的「添加」按钮创建控件。
    _OnSidePick(idx, *) {
        if (idx < 1 || idx > this._sideTypes.Length)
            return
        this._sideSel := idx
        this._SyncSideHighlight()
    }

    _OnSideAddBtn(*) {
        if (this._sideSel < 1 || this._sideSel > this._sideTypes.Length)
            return
        this._AddByType(this._sideTypes[this._sideSel])
    }

    _SyncSideHighlight() {
        loop this._sideTypes.Length {
            selected := (A_Index == this._sideSel)
            try this.ui.Update("SideRow" A_Index, "BorderBrush"
                , selected ? "{DynamicResource ActionBg}" : "Transparent")
        }
        try this.ui.Update("BtnSideAdd", "IsEnabled", this._sideSel > 0 ? "True" : "False")
    }

    ; 图标网格只显示图形，类型名称通过悬停提示提供。
    _SideRow(parent, idx, type) {
        row := parent.Add("Border").Name("SideRow" idx)
            .Width(32).Height(30).Margin("1").CornerRadius("4")
            .Background("Transparent").BorderBrush("Transparent").BorderThickness("1")
            .HorizontalAlignment("Center").Cursor("Hand")
            .ToolTip(UIMacroSchema.TypeLabel(type))
        cell := row.Add("Grid")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        this._SideVisual(cell, type)
    }

    ; 使用简单几何预览，区分相近的交互控件类型。
    _SideVisual(cell, type) {
        fg := "{DynamicResource TextMain}"
        switch String(type) {
            case "Button":
                btn := cell.Add("Border").Width(18).Height(12).CornerRadius("3")
                    .Background("{DynamicResource UIPanelBtnColor}")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
                btn.Add("Border").Width(8).Height(1).CornerRadius("1")
                    .Background("{DynamicResource UIPanelBtnText}")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "CheckBox":
                cb := cell.Add("Grid").Width(13).Height(13)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
                cb.Add("Border").CornerRadius("2")
                    .Background("Transparent").BorderBrush(fg).BorderThickness("1")
                cb.Add("TextBlock").Text("✓").FontSize("9").FontWeight("Bold").Foreground(fg)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "Edit":
                edit := cell.Add("Border").Width(18).Height(12).CornerRadius("2")
                    .Background("Transparent").BorderBrush(fg).BorderThickness("1")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
                edit.Add("Border").Width(1).Height(7).Margin("4,0,0,0")
                    .HorizontalAlignment("Left").VerticalAlignment("Center")
                    .Background(fg)
            case "TextBlock":
                cell.Add("TextBlock").Text("Aa").FontSize("10").Foreground(fg)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "ComboBox":
                cbv := cell.Add("Grid").Width(18).Height(12)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
                cbv.Cols("*", "7")
                cbv.Add("Border").Grid_Column(0).CornerRadius("2,0,0,2")
                    .Background("Transparent").BorderBrush(fg).BorderThickness("1")
                arrow := cbv.Add("Border").Grid_Column(1).CornerRadius("0,2,2,0")
                    .Background("Transparent").BorderBrush(fg).BorderThickness("1")
                arrow.Add("TextBlock").Text("▾").FontSize("7").Foreground(fg)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "Rect":
                cell.Add("Border").Width(12).Height(12)
                    .Background("Transparent").BorderBrush(fg).BorderThickness("1")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "Ellipse":
                cell.Add("Ellipse").Width(12).Height(12)
                    .Fill("Transparent").Stroke(fg).StrokeThickness("1")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "LineH":
                cell.Add("Border").Width(16).Height(2).Background(fg)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            case "LineV":
                cell.Add("Border").Width(2).Height(16).Background(fg)
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
        }
    }

    ; 分组折叠
    _OnSideGrp(name, *) {
        cur := this._sideExpand.Has(name) ? this._sideExpand[name] : true
        this._sideExpand[name] := !cur
        this._ApplySideGroups()
    }

    _ApplySideGroups() {
        try this.ui.Update("SideCtrlGrid", "Visibility", this._sideExpand["控件"] ? "Visible" : "Collapsed")
        try this.ui.Update("SideShapeGrid", "Visibility", this._sideExpand["图形"] ? "Visible" : "Collapsed")
        try this.ui.Update("SideGrpCaret0", "Text", this._sideExpand["控件"] ? "▾" : "▸")
        try this.ui.Update("SideGrpCaret1", "Text", this._sideExpand["图形"] ? "▾" : "▸")
    }


    _AddByType(type) {
        if (this._schema.controls.Length >= UIMacroSchema.MaxControls) {
            MsgBox("最多 " UIMacroSchema.MaxControls " 个控件", "自定义界面", "Icon!")
            return ""
        }
        newId := UIMacroSchema.Add(this._schema, type, 12, 12 + this._schema.controls.Length * 6)
        if (newId == "")
            return ""
        ; 新控件归属当前编辑页
        newCtrl := UIMacroSchema.FindById(this._schema, newId)
        if (IsObject(newCtrl))
            newCtrl.page := this._page
        ; 图形自动压到底层：否则新加的线框/线会盖在已有控件上，挡住点击
        if (UIMacroSchema.IsShapeType(type))
            UIMacroSchema.SendToBack(this._schema, newId)
        this._selId := newId
        this._windowSelected := false
        this._Rebuild()
        return newId
    }

    _OnDelete(*) {
        if (this._selId == "")
            return
        if (!UIMacroSchema.Remove(this._schema, this._selId))
            return
        ; 删完自动选中剩下的第一个；留空会导致下一次 Delete 直接返回（看起来像只能删一个）
        this._selId := this._schema.controls.Length ? String(this._schema.controls[1].id) : ""
        this._windowSelected := false
        this._Rebuild()
    }

    _OnFront(*) {
        if (this._selId == "" || !UIMacroSchema.BringToFront(this._schema, this._selId))
            return
        this._Rebuild()
    }

    ; 图形颜色切换：只换画刷，不重建窗口
    _OnShapeColor(*) {
        if (this._loading)
            return
        item := UIMacroSchema.FindById(this._schema, this._selId)
        if (!item || !UIMacroSchema.IsShapeType(item.type))
            return
        idx := 0
        try idx := Integer(this.ui.Query("ShapeColorCon>SelectedIndex"))
        switch idx {
            case 1: item.color := "accent"
            case 2: item.color := "sub"
            default: item.color := ""
        }
        name := UIMacroRenderer.NameOf(item.id)
        brush := UIMacroRenderer.ShapeBrush(item)
        ; try 不能直接当 if 的单语句体（else 会解析失败），必须加花括号
        if (item.type == "Rect") {
            try this.ui.Update(name, "BorderBrush", brush)
        } else if (item.type == "Ellipse") {
            try this.ui.Update(name, "Stroke", brush)
        } else {
            try this.ui.Update(name, "Background", brush)
        }
    }

    ; 置底：方框/线压到最底层，避免挡住上面控件的点击
    _OnBack(*) {
        if (this._selId == "" || !UIMacroSchema.SendToBack(this._schema, this._selId))
            return
        this._Rebuild()
    }

    ; 宏可能在别处被新增、删除、改名或修改；重载摘要数据但保留画布草稿。
    _OnReloadMacros(*) {
        tableItem := ""
        try tableItem := GetTableBySymbol("UI")
        if (!IsObject(tableItem))
            return
        this._tableItem := tableItem
        fold := (tableItem.Folds.Length >= this._foldIndex) ? tableItem.Folds[this._foldIndex] : ""
        this._items := fold ? GetFoldItems(tableItem, fold) : []
        this._bindTargetsCtrlId := ""
        this._Rebuild()
    }

    ; ---------- 分页 ----------
    ; 从挑选器创建新控件并绑定，不依赖画布当前选中项。
    CreateBoundControl(target, ctrlType) {
        if (!IsObject(target))
            return ""
        mode := target.HasProp("mode") ? String(target.mode) : ""
        if (mode == "action")
            ctrlType := "Button"
        else if (mode == "skip")
            ctrlType := "CheckBox"
        else if (ctrlType == "")
            ctrlType := "Edit"
        if (!this._ValidateBindingTarget(target))
            return ""
        if (this._schema.controls.Length >= UIMacroSchema.MaxControls) {
            MsgBox("最多 " UIMacroSchema.MaxControls " 个控件", "自定义界面", "Icon!")
            return ""
        }

        label := this._NewControlLabel(target)
        newId := UIMacroSchema.Add(this._schema, ctrlType, 12, 12 + this._schema.controls.Length * 6)
        if (newId == "")
            return ""
        ctrl := UIMacroSchema.FindById(this._schema, newId)
        if (!IsObject(ctrl))
            return ""
        ctrl.page := this._page
        ctrl.text := label
        this._SetControlBinding(ctrl, target, ctrlType)
        this._selId := newId
        this._windowSelected := false
        this._Rebuild()
        return newId
    }

    ; 重新绑定：把挑选器选中的字段挂到「当前选中的控件」上，不生成新控件。
    ; 类型跟随挑选器中的选择；action 目标会把控件变成按钮。
    RebindSelected(target, ctrlType) {
        ctrl := UIMacroSchema.FindById(this._schema, this._selId)
        if (!IsObject(ctrl) || !IsObject(target))
            return ""
        if (!this._ValidateBindingTarget(target, ctrl.id))
            return ""
        this._SetControlBinding(ctrl, target, ctrlType)
        this._Rebuild()
        return this._selId
    }

    _ValidateBindingTarget(target, exceptId := "") {
        mode := target.HasProp("mode") ? String(target.mode) : ""
        if (mode == "action")
            return true
        key := UIMacroStepBinding.TargetKey(target)
        if (key != "" && (this._IsTargetBoundByAnotherControl(key, exceptId)
            || UIMacroStepBinding.IsOccupiedByKey(key, this._foldKey, this._foldIndex))) {
            MsgBox("该字段已被其它控件或面板绑定", "绑定冲突", "Icon!")
            return false
        }
        return true
    }

    _SetControlBinding(ctrl, target, ctrlType) {
        mode := target.HasProp("mode") ? String(target.mode) : ""
        if (mode != "action")
            try ctrl.DeleteProp("action")
        if (mode == "skip") {
            nb := { macroId: target.macroId, mode: "skip", step: target.step }
            if (target.HasProp("hops") && IsObject(target.hops) && target.hops.Length > 0)
                nb.hops := target.hops
            ctrl.binding := nb
            ctrl.type := "CheckBox"
        } else if (mode == "action") {
            ctrl.type := "Button"
            ctrl.action := { cmd: "RunMacro", macroId: target.macroId }
            try ctrl.DeleteProp("binding")
        } else if (mode == "data") {
            if (ctrlType != "")
                ctrl.type := ctrlType
            nb := { macroId: target.macroId, mode: "data"
                , kind: target.kind, serial: target.serial, field: target.field }
            if (target.HasProp("hops") && IsObject(target.hops) && target.hops.Length > 0)
                nb.hops := target.hops
            ctrl.binding := nb
        } else {
            if (ctrlType != "")
                ctrl.type := ctrlType
            nb := { macroId: target.macroId, mode: "step", step: target.step, param: target.param }
            if (target.HasProp("hops") && IsObject(target.hops) && target.hops.Length > 0)
                nb.hops := target.hops
            ctrl.binding := nb
        }
    }

    _NewControlLabel(target) {
        baseLabel := ""
        if (target.HasProp("mode") && String(target.mode) == "action") {
            item := GetItemGlobal(String(target.macroId))
            if (IsObject(item) && item.HasProp("Remark"))
                baseLabel := Trim(String(item.Remark))
            if (baseLabel == "")
                baseLabel := "运行"
        } else {
            baseLabel := target.HasProp("fieldLabel") && String(target.fieldLabel) != ""
                ? String(target.fieldLabel) : "参数"
        }
        label := baseLabel
        suffix := 2
        while (this._LabelUsed(label))
            label := baseLabel suffix++
        return label
    }

    _LabelUsed(label) {
        for ctrl in this._schema.controls {
            if (ctrl.HasProp("text") && String(ctrl.text) == String(label))
                return true
        }
        return false
    }

    _IsTargetBoundByAnotherControl(targetKey, exceptId) {
        for item in this._schema.controls {
            if (String(item.id) == String(exceptId) || !item.HasProp("binding")
                || !IsObject(item.binding))
                continue
            if (UIMacroStepBinding.BindingKey(item.binding) == targetKey)
                return true
        }
        return false
    }

    _ReloadPageCombo() {
        if (!IsObject(this.ui))
            return
        pages := (this._schema.window.HasProp("pages") ? Integer(this._schema.window.pages) : 1)
        if (this._page > pages)
            this._page := pages
        if (this._page < 1)
            this._page := 1
        batch := [{ ControlName: "DsgPageCon", PropertyName: "ClearItems", Value: "" }]
        loop pages
            batch.Push({ ControlName: "DsgPageCon", PropertyName: "AddItem"
                , Value: A_Index " / " pages })
        batch.Push({ ControlName: "DsgPageCon", PropertyName: "SelectedIndex", Value: String(this._page - 1) })
        batch.Push({ ControlName: "BtnPrevPage", PropertyName: "IsEnabled", Value: this._page > 1 ? "True" : "False" })
        batch.Push({ ControlName: "BtnNextPage", PropertyName: "IsEnabled", Value: this._page < pages ? "True" : "False" })
        batch.Push({ ControlName: "BtnAddPage", PropertyName: "IsEnabled", Value: pages < 20 ? "True" : "False" })
        batch.Push({ ControlName: "BtnDeletePage", PropertyName: "IsEnabled", Value: pages > 1 ? "True" : "False" })
        wasLoading := this._loading
        this._loading := true
        try {
            if (this.ui.HasMethod("BatchUpdate"))
                this.ui.BatchUpdate(batch)
            else {
                for e in batch
                    this.ui.Update(e.ControlName, e.PropertyName, e.Value)
            }
        } catch {
        } finally {
            this._loading := wasLoading
        }
    }

    _OnPageSelectionChanged(*) {
        if (this._loading)
            return
        pages := (this._schema.window.HasProp("pages") ? Integer(this._schema.window.pages) : 1)
        idx := -1
        try idx := Integer(this.ui.Query("DsgPageCon>SelectedIndex"))
        page := idx + 1
        if (page < 1 || page > pages || page == this._page)
            return
        this._SwitchPage(page)
    }

    _OnPrevPage(*) {
        if (this._page > 1)
            this._SwitchPage(this._page - 1)
    }

    _OnNextPage(*) {
        pages := this._schema.window.HasProp("pages") ? Integer(this._schema.window.pages) : 1
        if (this._page < pages)
            this._SwitchPage(this._page + 1)
    }

    ; 切页：清掉不属于新页的选中，再重画
    _SwitchPage(toPage) {
        this._page := Max(1, toPage)
        sel := UIMacroSchema.FindById(this._schema, this._selId)
        if (IsObject(sel)) {
            pg := (sel.HasProp("page") ? Integer(sel.page) : 1)
            if (pg != this._page)
                this._selId := ""
        }
        this._Rebuild()
    }

    ; 加一页：窗口尺寸不动（所有页共用 window.width/height，天然统一）
    _OnAddPage(*) {
        pages := (this._schema.window.HasProp("pages") ? Integer(this._schema.window.pages) : 1)
        if (pages >= 20) {
            MsgBox("最多 20 页", "自定义界面", "Icon!")
            return
        }
        this._schema.window.pages := pages + 1
        this._page := pages + 1
        this._selId := ""      ; 新页是空的：别把上一页的选中带过来
        this._Rebuild()
    }

    ; 删除当前页及其控件，并将后续页面编号前移。
    _OnDeletePage(*) {
        pages := this._schema.window.HasProp("pages") ? Integer(this._schema.window.pages) : 1
        if (pages <= 1)
            return

        page := this._page
        controlsOnPage := 0
        for ctrl in this._schema.controls {
            ctrlPage := ctrl.HasProp("page") ? Integer(ctrl.page) : 1
            if (ctrlPage == page)
                controlsOnPage += 1
        }
        if (controlsOnPage > 0
            && MsgBox("删除第 " page " 页及其 " controlsOnPage " 个控件？", "删除页面", "YesNo Icon? Default2")
                != "Yes")
            return

        i := this._schema.controls.Length
        while (i >= 1) {
            ctrl := this._schema.controls[i]
            ctrlPage := ctrl.HasProp("page") ? Integer(ctrl.page) : 1
            if (ctrlPage == page)
                this._schema.controls.RemoveAt(i)
            else if (ctrlPage > page)
                ctrl.page := ctrlPage - 1
            i -= 1
        }

        pages -= 1
        this._schema.window.pages := pages
        this._page := Min(page, pages)
        this._selId := ""
        this._windowSelected := false
        this._Rebuild()
    }

    ; 打开当前页控件列表
    _OnLayers(*) {
        UIMacroLayerGui.Show(this)
    }

    ; 供控件列表调用：选中某个控件并同步属性面板/选中框
    SelectControl(id) {
        if (!UIMacroSchema.FindById(this._schema, String(id)))
            return
        this._selId := String(id)
        this._windowSelected := false
        this._SyncProps()
    }

    ; 打开挑选器；已有绑定时定位到当前字段，未绑定时默认跟随触发宏。
    _OnPickFromMacro(*) {
        tableItem := ""
        try tableItem := GetTableBySymbol("UI")
        if (!IsObject(tableItem)) {
            MsgBox("宏表未就绪", "挑选器", "Icon!")
            return
        }
        selCtrl := UIMacroSchema.FindById(this._schema, this._selId)
        UIMacroFieldPicker.Show(tableItem, this._BindSourceMacroId(selCtrl), selCtrl, this)
    }

    ; 打开创建模式；保留当前控件的宏作为初始来源，但不把选择器置于重新绑定状态。
    _OnCreateFromField(*) {
        tableItem := ""
        try tableItem := GetTableBySymbol("UI")
        if (!IsObject(tableItem)) {
            MsgBox("宏表未就绪", "挑选器", "Icon!")
            return
        }
        selCtrl := UIMacroSchema.FindById(this._schema, this._selId)
        UIMacroFieldPicker.Show(tableItem, this._BindSourceMacroId(selCtrl), "", this, "create")
    }

    ; 设计器自带面板资源，避免依赖运行浮窗先行初始化。
    _UIPanelResources() {
        return '<SolidColorBrush x:Key="UIPanelBtnColor" Color="' MainSoftData.UIPanelBtnColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelBtnText" Color="' MainSoftData.UIPanelBtnText '"/>'
            . '<SolidColorBrush x:Key="UIPanelBgColor" Color="' MainSoftData.UIPanelBgColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleBg" Color="' MainSoftData.UIPanelTitleBg '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleText" Color="' MainSoftData.UIPanelTitleText '"/>'
    }

    ; 画布渲染参数（构建与原地重灌共用一份，避免两处样式漂移）
    _CanvasRenderOpt() {
        return {
            btnColor: "{DynamicResource UIPanelBtnColor}",
            btnTextColor: "{DynamicResource UIPanelBtnText}",
            textColor: "{DynamicResource TextMain}",
            inputBg: "{DynamicResource InputBg}",
            inputStroke: "{DynamicResource InputStroke}",
            inputTextColor: "{DynamicResource InputText}",
            ; 画布上图形必须可点选；浮窗运行时默认不命中（点击穿透到下面的控件）
            shapeHitTest: true,
            selectionOverlay: true,
            onlyPage: this._page,
            panelWidth: Integer(this._schema.window.width),
            tableItem: this._tableItem
        }
    }

    ; 控件鼠标事件：重灌后名字是新注册的，必须重绑
    _BindCanvasControlEvents() {
        for id, info in this._ctrlMap {
            eventName := info.HasProp("hitName") ? info.hitName : info.name
            this.ui.OnEvent(eventName, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnCtrlDown", id))
            this.ui.OnEvent(eventName, "PreviewMouseMove", ObjBindMethod(this, "_OnCtrlMove", id))
            this.ui.OnEvent(eventName, "PreviewMouseLeftButtonUp", ObjBindMethod(this, "_OnCtrlUp", id))
        }
    }

    ; 原地重灌画布：清空 DesignCanvas 的子项 → 重新注入控件 XAML。
    ; 窗口不重建 → 无闪烁、位置/焦点/滚动全保留、不触发任何 Window 生命周期事件。
    ; 失败返回 false，由 _Rebuild 回退到整窗重建（最坏等于旧表现）。
    _RefreshCanvas() {
        if (!IsObject(this.ui))
            return false
        try {
            ; 用一个临时 Grid 收集控件元素，取它的 XAML 字符串
            inner := XAML_Generator("Grid")
            inner.Add("Border").Name("CanvasBlank").Background("Transparent")
            this._ctrlMap := UIMacroRenderer.Render(inner, this._schema, this._CanvasRenderOpt())
            ; AddXamlItem 的解析错误只记日志；探针用于识别注入失败。
            inner.Add("TextBox").Name("CanvasProbe").Text("1")
                .Width(1).Height(1).Opacity(0).IsHitTestVisible("False")
            ; 必须剥掉首尾空白：ToString 以换行结尾，Update 会把换行转成 &#x0A;，
            ; 而根元素之后的字符引用属于「根级非法数据」，XamlReader.Parse 直接抛错
            ; （表现为画布清空后什么都没加回来 → 白板）。
            xaml := Trim(inner.ToString(), " `t`r`n")
            if (xaml == "")
                return false
            ; 单独解析时必须自带 WPF 命名空间：在窗口模板里靠根节点继承，
            ; 但 XamlReader.Load 是独立文档，缺 xmlns 会报「无法创建未知类型 Grid」。
            xaml := RegExReplace(xaml, '^<([A-Za-z_][A-Za-z0-9_:.]*)'
                , '<$1 xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
                . ' xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"', , 1)
            ; 命令协议用 | 分隔三段，值里出现 | 会被截断
            if (InStr(xaml, "|"))
                return false
            this.ui.Update("DesignCanvas", "ClearItems", "")
            this.ui.Update("DesignCanvas", "AddXamlItem", xaml)
            ; 解析失败不抛异常，只能回查。判定放宽：任一控件名或哨兵能查到值即视为成功，
            ; 避免「控件内容恰好为空」被误判成失败（那会白走一次整窗重建）。
            injected := ""
            for id, info in this._ctrlMap {
                v := this.ui.Query(info.name)
                if (v != "") {
                    injected := "ctrl:" info.name "=" v
                    break
                }
            }
            if (injected == "") {
                v := this.ui.Query("CanvasProbe")
                if (v != "")
                    injected := "probe=" v
            }
            ; 查询机制本身是否可用（工具栏控件一定存在）。不可用时无法判定，
            ; 按成功处理——否则每次结构变化都会白走一次整窗重建。
            qWorks := (this.ui.Query("BtnAddPage") != "") || (this.ui.Query("BtnLayers") != "")
            if (injected == "" && qWorks)
                return false
            ; 旧元素已销毁、名字已注销 → 新元素必须重绑事件（AHK 侧登记）
            this._BindCanvasControlEvents()
            ; 关键：事件是「建窗时烘进引擎」的，仅调 OnEvent 不会生效；
            ; 必须显式通知引擎把新元素的鼠标事件挂上，否则点不中、拖不动。
            bindList := "CanvasBlank:PreviewMouseLeftButtonDown"
            for id, info in this._ctrlMap {
                eventName := info.HasProp("hitName") ? info.hitName : info.name
                for evt in ["PreviewMouseLeftButtonDown", "PreviewMouseMove", "PreviewMouseLeftButtonUp"] {
                    bindList .= (bindList == "" ? "" : ",") eventName ":" evt
                }
            }
            if (bindList != "")
                this.ui.Update("DesignCanvas", "RebindEvents", bindList)
            this._SyncSelBox()
            this._SyncProps()
            try UIMacroLayerGui.NotifyIfOpen()
            ; 页码按钮的显隐也要刷：_Rebuild 走原地重灌时不会执行到函数尾部
            this._ReloadPageCombo()
            return true
        } catch {
            return false
        }
    }

    ; 增删控件优先只替换画布内容；注入失败时由 _Rebuild 回退到整窗重建。
    static UseInPlaceCanvas := true

    _Rebuild() {
        ; 类型迁移：旧规格曾把枚举/布尔字段生成过输入框（如 RMT 指令的 CmdStr），
        ; 现在升到标准控件。迁移发生在保存之前，所以下一次「保存」会把新类型固化。
        for ctrl in this._schema.controls {
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            b := ctrl.binding
            if (b.HasProp("mode") && String(b.mode) == "skip")
                continue
            spec := ""
            try {
                if (String(b.mode) == "data")
                    spec := UIMacroStepBinding.SpecOfData(b.kind, b.field)
                else
                    spec := UIMacroStepBinding.SpecOfBindingDeep(this._tableItem, b)
            } catch {
            }
            if (!IsObject(spec))
                continue
            cano := UIMacroStepBinding.CtrlTypeFor(spec)
            if (cano != "" && ctrl.type != cano && ctrl.type != "TextBlock")
                ctrl.type := cano
        }

        ; 原地重灌失败时保留整窗重建作为恢复路径。
        if (UIMacroDesignerGui.UseInPlaceCanvas && this._RefreshCanvas())
            return
        ; 整窗重建会关旧窗口，其 Closing 是「异步」到达的；置抑制窗口，
        ; 避免它被误当成用户关窗（会置 closed、注销实例、连累控件列表）。
        this._suppressClosingUntil := A_TickCount + 1500
        sel := this._selId
        oldUi := IsObject(this.ui) ? this.ui : ""
        ; 重建前的窗口才是当前位置的权威来源，先落盘，新窗口才不会跳回居中
        this._SavePos()
        this._UnbindKeys()
        this._rebuilding := true
        this._ctrlMap := Map()
        this._BuildAndShow()
        if (IsObject(oldUi)) {
            Sleep(60)
            try oldUi.Update("Window", "Close", "")
        }
        this._rebuilding := false
        if (sel != "" && UIMacroSchema.FindById(this._schema, sel)) {
            this._selId := sel
            this._SyncProps()
        }
        ; 控件列表若开着：控件增删/换序后同步列表
        try UIMacroLayerGui.NotifyIfOpen()
        this._ReloadPageCombo()
    }

    ; ------------------------------------------------------------------
    ; 预览 / 保存 / 关闭
    ; ------------------------------------------------------------------
    _OnPreview(*) {
        v := UIMacroSchema.Validate(this._schema)
        if (!v.ok) {
            MsgBox(v.msg, "自定义界面", "Icon!")
            return
        }
        pw := Integer(this._schema.window.width)
        ph := 30 + Integer(this._schema.window.height) + 8

        main := XAML_Generator("Grid").Background("{DynamicResource UIPanelBgColor}")
        main.Rows("30", "*")
        XAMLHost.AddTitleBar(main, "预览", "30")

        canvas := main.Add("Grid").Grid_Row(1).Margin("4,4,4,4").ClipToBounds("True")
        UIMacroRenderer.Render(canvas, this._schema, {
            btnColor: "{DynamicResource UIPanelBtnColor}",
            btnTextColor: "{DynamicResource UIPanelBtnText}",
            textColor: "{DynamicResource UIPanelBtnText}",
            inputBg: "{DynamicResource InputBg}",
            inputStroke: "{DynamicResource InputStroke}",
            inputTextColor: "{DynamicResource InputText}",
            panelWidth: pw,
            tableItem: this._tableItem
        })

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        pv := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        pv.xaml := StrReplace(pv.xaml, 'Width="940" Height="700"'
            , 'Title="预览" Width="' (pw + 12) '" Height="' ph '"')
        pv.xaml := StrReplace(pv.xaml, 'Background="Transparent"', 'Background="' MainSoftData.UIPanelBgColor '"')

        pv.xaml := StrReplace(pv.xaml, '%resources%', this._UIPanelResources())
        pv.xaml := StrReplace(pv.xaml, '%components%', '')

        if (IsObject(this._previewUi))
            try this._previewUi.Update("Window", "Close", "")
        pv.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "_ClosePreview"))
        pv.Show()
        this._previewUi := pv
    }

    _ClosePreview(*) {
        if (IsObject(this._previewUi)) {
            try this._previewUi.Update("Window", "Close", "")
            this._previewUi := ""
        }
    }

    _OnSave(*) {
        v := UIMacroSchema.Validate(this._schema)
        if (!v.ok) {
            MsgBox(v.msg, "自定义界面", "Icon!")
            return
        }

        global SettingFile, SettingSection

        json := UIMacroSchema.Serialize(this._schema)
        if (json == "") {
            MsgBox("生成配置失败（序列化返回空），请把这条信息发给我", "自定义界面", "Icon!")
            return
        }
        if (UIMacroSchema.WriteStoreByKey(this._foldKey, json)) {
            try this.ui.Update("TipCon", "Text", "已保存 " Format("{:02}:{:02}", A_Hour, A_Min))
            ; 保存即生效：销毁该面板缓存，下次触发按键会按新配置重建（无需重启）
            ; 用 DestroyFoldPanels：带前台信息的面板 key 是 "<idx>|<hwnd>"，
            ; 直接 DestroyPanel(idx) 会因 Has(idx) 不成立而静默失效。
            try {
                if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
                    MyUIMacroGui.DestroyFoldPanels(this._foldIndex)
            }
        } else {
            MsgBox("写入失败：" UIMacroSchema.StorePathByKey(this._foldKey), "自定义界面", "Icon!")
        }
    }

    ; ------------------------------------------------------------------
    ; 键盘：Delete 删除选中控件（XAML 只派发鼠标事件，键盘走 AHK 热键）
    ; ------------------------------------------------------------------
    _BindKeys() {
        hwnd := 0
        loop 40 {
            hwnd := 0
            try hwnd := this.ui.wpfHwnd
            if (hwnd)
                break
            Sleep(50)
        }
        if (!hwnd)
            return
        this._hkHwnd := hwnd
        ; 重建后的新窗口若不在前台，HotIfWinActive 条件不成立，Delete 会失效
        try WinActivate("ahk_id " hwnd)
        ; Delete 快捷键已停用：XAML 侧没有键盘事件，AHK 全局热键在这里不稳定，
        ; 删除统一走工具栏的「删除」按钮。
        return
    }

    _UnbindKeys() {
        if (!this._hkBound)
            return
        try Hotkey("Delete", "Off")
        this._hkBound := false
        this._hkHwnd := 0
    }

    _OnDeleteKey(*) {
        ; 全局注册，靠前台窗口判断归属；不是本窗口就把按键原样透传出去
        hwnd := 0
        try hwnd := this.ui.wpfHwnd
        if (!hwnd || DllCall("GetForegroundWindow", "Ptr") != hwnd) {
            Send("{Delete}")
            return
        }
        this._OnDelete()
    }

    ; ------------------------------------------------------------------
    ; 窗口位置记忆
    ; ------------------------------------------------------------------
    _PosPath() {
        ; 与面板配置同目录，但不随折叠框 ID 变化而丢失窗口位置
        p := UIMacroSchema.StorePathByKey(this._foldKey != "" ? this._foldKey : String(this._foldIndex))
        SplitPath(p, , &dir)
        return dir "\UIMacroDesigner.ini"
    }

    _LoadPos() {
        p := this._PosPath()
        if (!FileExist(p))
            return ""
        x := IniRead(p, "win", "x", "")
        y := IniRead(p, "win", "y", "")
        if (x == "" || y == "")
            return ""
        return { x: Integer(x), y: Integer(y) }
    }

    _SavePos() {
        if (!IsObject(this.ui))
            return

        ; 优先取 WPF 侧 Left/Top（DIP，和 XAML 设置同单位，不会因 DPI 漂移）
        x := ""
        y := ""
        try x := this.ui.Query("Window>Left")
        try y := this.ui.Query("Window>Top")

        if (x == "" || y == "") {
            ; 兜底：物理像素 → 除以 DPI 缩放换算成 DIP
            hwnd := 0
            try hwnd := this.ui.wpfHwnd
            if (!hwnd)
                return
            rect := Buffer(16, 0)
            if (!DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect))
                return
            scale := A_ScreenDPI / 96
            x := Round(NumGet(rect, 0, "Int") / scale)
            y := Round(NumGet(rect, 4, "Int") / scale)
        }

        p := this._PosPath()
        try {
            IniWrite(Integer(Round(x)), p, "win", "x")
            IniWrite(Integer(Round(y)), p, "win", "y")
        }
    }

    _OnCancel(*) {
        this.Close()
    }

    OnWindowClosing(state, ctrl, event) {
        ; 重建时旧窗口的 Closing 是异步到达的，可能晚于 _rebuilding 复位。
        ; 因此这里绝不碰 this.ui —— 它可能已指向新窗口；只清理实例映射。
        if (this._rebuilding)
            return
        ; 重建触发的异步 Closing：抑制期内一律忽略
        if (this._suppressClosingUntil != 0 && A_TickCount < this._suppressClosingUntil)
            return
        ; 这里不能直接关控件列表：重建时旧窗口的 Closing 是异步到达的，
        ; 到这一步 _rebuilding 已复位，会把「重建」误判成「关闭」。
        ; 控件列表改为自己定时检查设计器存活（见 UIMacroLayerGui._Watch）。
        this._UnbindKeys()
        this._SavePos()
        this.closed := true
        if (this._instanceKey != "" && UIMacroDesignerGui.instances.Has(this._instanceKey))
            UIMacroDesignerGui.instances.Delete(this._instanceKey)
    }

    Close() {
        this.closed := true
        ; 程序化关闭（取消按钮 / 换实例）同样带走控件列表
        try UIMacroLayerGui.CloseIfOpen()
        this._SavePos()
        this._UnbindKeys()
        if (IsObject(this._previewUi)) {
            try this._previewUi.Update("Window", "Close", "")
            this._previewUi := ""
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
        if (this._instanceKey != "" && UIMacroDesignerGui.instances.Has(this._instanceKey))
            UIMacroDesignerGui.instances.Delete(this._instanceKey)
    }

}
