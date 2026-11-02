#Requires AutoHotkey v2.0

; ===========================================================================
; 多点找图与模板图片处理—— XAML 版
;
; 用途：选取多点找图的基准点、自动补点，并裁剪 / 重命名模板。
;   左画布显示原图，右画布显示基准颜色容差预览；裁剪时拖动框选保留区域。
;
; 注意：XAML 框架目前只派发左键事件（PreviewMouseLeftButtonDown/Move/Up），
;      滚轮由窗口内 AHK 热键接管，并保持鼠标下的图像位置。
; ===========================================================================
class ImageProcessGui {
    __new() {
        this.ui := ""
        this.OwnerHwnd := ""
        this._ownerDisabled := false
        this.SureAction := ""
        this.CropAction := ""
        this.ReleaseAction := ""

        this.TemplatePath := ""
        this.Tol := 8
        this.NormalTolerance := 8
        this.SuperTolerance := 8
        this.Points := []
        this.SeedPoints := []
        this.SuperSeedPoints := []
        this.SuperIgnoreData := ""
        this.IgnoreOps := []
        this.IgnoreUndo := []
        this.IgnoreRedo := []
        this.IgnoreTool := ""
        this.IgnoreBrushSize := 1
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this.AutoPointDensity := 50
        this.MatchMode := ""
        this.EditorMode := "original"
        this.PointTool := ""
        this.ShowLeftPointOverlay := true
        this.ShowRightPointOverlay := true

        this.CanvasSide := 340          ; 画布边长（物理像素）
        this.Zoom := 0                  ; 0 = 待适应
        this.ViewW := 0
        this.ViewH := 0
        this.ViewX := 0
        this.ViewY := 0
        this.OrigW := 0
        this.OrigH := 0

        this.SelX := 0                  ; 选区（原图坐标）
        this.SelY := 0
        this.SelW := 0
        this.SelH := 0

        this.Mode := ""                 ; "" / "crop"
        this.Resizing := ""             ; "" / "TL" / "TR" / "BL" / "BR"
        this.Dragging := false
        this.DragStartX := 0
        this.DragStartY := 0
        this.DragViewX := 0
        this.DragViewY := 0
        this.DragMoved := false

        this._hwnd := 0
        this._windowToken := 0
        this._committed := false
        this._seq := 0
        this._overlaySeq := 0
        this._ignoreOverlaySeq := 0
        this._wheelRenderTimer := ObjBindMethod(this, "_FlushWheelRender")
        this._toleranceRenderTimer := ObjBindMethod(this, "_FlushToleranceRender")
        this._ignoreOverlayTimer := ObjBindMethod(this, "_FlushIgnoreOverlay")
        this._ignoreStrokeTimer := ObjBindMethod(this, "_PollIgnoreStroke")
        this._rendering := false
        this._ignoreOverlayRefreshPending := false
        this._wheelPending := false
        this._renderedZoom := 0
        this._renderedViewX := 0
        this._renderedViewY := 0
        this._previewScale := 1
        this._previewOffsetX := 0
        this._previewOffsetY := 0
        this._lastOrig := ""
        this._lastEff := ""
        this._lastLeftOverlay := ""
        this._lastRightOverlay := ""
        this._lastIgnoreOverlay := ""
    }

    ; ------------------------------------------------------------------
    ; 对外入口
    ; ------------------------------------------------------------------
    ShowGui(path, points := "", seedPoints := "", tol := 8, matchMode := ""
        , superSeedPoints := "", superTol := 8, superIgnoreData := "") {
        this.TemplatePath := path
        this.NormalTolerance := (IsNumber(tol) && tol != "") ? Integer(tol) : 8
        this.SuperTolerance := (IsNumber(superTol) && superTol != "") ? Integer(superTol) : 8
        this.Points := IsObject(points) ? points.Clone() : []
        this.SeedPoints := IsObject(seedPoints) ? seedPoints.Clone() : (IsObject(points) ? points.Clone() : [])
        this.SuperSeedPoints := IsObject(superSeedPoints) ? superSeedPoints.Clone() : []
        parsedIgnoreOps := this._ParseIgnoreData(String(superIgnoreData))
        if (!IsObject(parsedIgnoreOps)) {
            RmtDialog.Info(GetLang("忽略蒙版数据无效"), GetLang("多点找图"))
            parsedIgnoreOps := []
        }
        this.IgnoreOps := parsedIgnoreOps
        this.SuperIgnoreData := this._SerializeIgnoreData(this.IgnoreOps)
        this.IgnoreUndo := []
        this.IgnoreRedo := []
        this.IgnoreTool := ""
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this.MatchMode := matchMode == "super" && this.SuperSeedPoints.Length > 0
            ? "super" : (matchMode == "multi" && this.Points.Length > 0 ? "multi" : "")
        this.EditorMode := this.MatchMode == "" ? "original" : this.MatchMode
        this.PointTool := ""
        this.Tol := this.MatchMode == "super" ? this.SuperTolerance : this.NormalTolerance
        this.Zoom := 0
        this.OrigW := 0
        this.OrigH := 0
        this.ViewW := 0
        this.ViewH := 0
        this._ResetPreviewTransform()
        this._ResetInteraction()
        this._committed := false

        ; 每次打开都重建窗口：避免复用旧窗口时控件状态不同步
        if (IsObject(this.ui)) {
            this._ReleasePreviewImages()
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
            this._RestoreOwner()
        }
        this._Build()
        if (!IsObject(this.ui))
            return
        this._DisableOwner()
        opened := false
        try opened := XamlWin.Open(this.ui, "", XamlWin.Owner(this))
        if (!opened) {
            this._RestoreOwner()
            return
        }

        this._BindWheel()
        this._SyncControls()
        this._SyncMatchModeUi()
        this._Render()
    }

    ; ------------------------------------------------------------------
    ; 建界面（只建一次）
    ; ------------------------------------------------------------------
    _Build() {
        this._windowToken += 1
        windowToken := this._windowToken
        title := GetLang("图片处理")
        titleHeight := "30"
        contentInset := 27

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "44", "Auto", "Auto", "*", "56")

        XAMLHost.AddTitleBar(main, title, titleHeight)

        ; ---- 工具栏 ----
        bar := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal")
            .VerticalAlignment("Center").Margin(contentInset ",0," contentInset ",0")

        this._AddBtn(bar, "BtnModeOriginal", GetLang("原图"), 64, GetLang("裁剪或重命名模板图片"))
        this._AddBtn(bar, "BtnModeMultiPoint", GetLang("多点"), 64, GetLang("使用少量匹配点找图"))
        this._AddBtn(bar, "BtnModeSuperMultiPoint", GetLang("超多点"), 72
            , GetLang("按基准色和容差筛选，并可忽略干扰区"))
        bar.Add("Button").Name("BtnHelp").Content("?")
            .Width(24).Height(24).MinWidth(24).MinHeight(24).MaxWidth(24).MaxHeight(24)
            .Padding("0").Margin("2,0,8,0").FontSize("11").Cursor("Hand")
            .VerticalAlignment("Center").HorizontalAlignment("Center")
            .ToolTip(GetLang("图片处理说明"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        bar.Add("Button").Name("BtnFitView").Content(GetLang("适应"))
            .Width(58).Height(24).MinHeight(24).Margin("0,0,8,0").Padding("8,0")
            .FontSize("11").Cursor("Hand").VerticalAlignment("Center")
            .ToolTip(GetLang("恢复预览适应窗口"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        bar.Add("Border").Width("1").Height("20").Margin("4,0,8,0").Background("{DynamicResource ControlBorder}")

        bar.Add("TextBlock").Name("HintCon").Text(GetLang("滚轮缩放；关闭工具后拖动预览可平移")).FontSize("11")
            .VerticalAlignment("Center").Margin("12,0,0,0")
            .Foreground("{DynamicResource TextSub}")

        bar.Add("TextBlock").Name("ZoomCon").Text("100%")
            .FontSize("11").VerticalAlignment("Center").Margin("8,0,0,0")
            .Foreground("{DynamicResource TextSub}")

        ; ---- 双画布 ----
        prev := main.Add("Grid").Grid_Row(2).Margin(contentInset ",0")
        prev.Rows("24", this.CanvasSide, "Auto")
        prev.Cols(this.CanvasSide, "*", this.CanvasSide)

        prev.Add("CheckBox").Grid_Row(0).Grid_Column(0).Width(this.CanvasSide)
            .HorizontalAlignment("Center").Name("ShowLeftOverlayCon")
            .Content(GetLang("显示左侧叠加点位"))
            .IsChecked(this.ShowLeftPointOverlay ? "True" : "False").VerticalAlignment("Center")
            .ToolTip(GetLang("显示或隐藏左侧点位叠加"))
            .Foreground("{DynamicResource TextMain}").FontSize("11")
        prev.Add("CheckBox").Grid_Row(0).Grid_Column(2).Width(this.CanvasSide)
            .HorizontalAlignment("Center").Name("ShowRightOverlayCon")
            .Content(GetLang("显示右侧叠加点位"))
            .IsChecked(this.ShowRightPointOverlay ? "True" : "False").VerticalAlignment("Center")
            .ToolTip(GetLang("显示或隐藏右侧预览叠加"))
            .Foreground("{DynamicResource TextMain}").FontSize("11")

        left := prev.Add("Border").Grid_Row(1).Grid_Column(0).Width(this.CanvasSide).Height(this.CanvasSide)
            .HorizontalAlignment("Center").ClipToBounds("True")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        leftCanvas := left.Add("Canvas").Name("LeftCanvas").Width(this.CanvasSide).Height(this.CanvasSide).Background("Transparent")
        leftTransform := leftCanvas.Add("Canvas.RenderTransform").Add("TransformGroup")
        leftTransform.Add("ScaleTransform").SetProp("x:Name", "LeftPreviewScale")
        leftTransform.Add("TranslateTransform").SetProp("x:Name", "LeftPreviewTranslate")
        leftCanvas.SetProp("RenderTransformOrigin", "0,0")
        leftCanvas.Add("Image").Name("LeftImg").Width(this.CanvasSide).Height(this.CanvasSide).Stretch("Uniform")
        leftCanvas.Add("Image").Name("PointOverlayImg").Width(this.CanvasSide).Height(this.CanvasSide)
            .Stretch("Fill").IsHitTestVisible("False").SetProp("Panel.ZIndex", "2")

        multiPointEditTools := prev.Add("StackPanel").Name("MultiPointEditToolsCon").Grid_Row(2).Grid_Column(2)
            .Orientation("Horizontal").Width(this.CanvasSide).Height(28).Margin("0,8,0,0")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        multiPointEditTools.Add("TextBlock").Text(GetLang("点位修改")).FontSize("12")
            .VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        this._AddSmallBtn(multiPointEditTools, "BtnMultiPointTool", Chr(0xE70F), 28, GetLang("添加或移除匹配点"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13")

        rightTools := prev.Add("StackPanel").Name("RightPreviewToolsCon").Grid_Row(2).Grid_Column(2)
            .Orientation("Horizontal").Width(this.CanvasSide).Height(28).Margin("0,8,0,0")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        rightTools.Add("TextBlock").Name("IgnoreMaskLabelCon").Text(GetLang("忽略蒙版")).FontSize("12")
            .VerticalAlignment("Center").Margin("0,0,8,0").Foreground("{DynamicResource TextMain}")
        this._AddSmallBtn(rightTools, "BtnIgnoreBrush", Chr(0xE70F), 28, GetLang("标记不参与匹配的区域"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13")
        this._AddSmallBtn(rightTools, "BtnIgnoreEraser", Chr(0xE75C), 28, GetLang("恢复被忽略的区域"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13")
        rightTools.Add("Border").Width("1").Height("18").Margin("4,0,4,0")
            .Background("{DynamicResource ControlBorder}")
        rightTools.Add("TextBlock").Name("IgnoreSizeLabelCon").Text(GetLang("大小")).FontSize("11").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextSub}").Margin("0,0,6,0")
        this._AddSmallBtn(rightTools, "BtnIgnoreSize1", "1", 24, GetLang("1像素方形笔刷"))
            .Margin("0").BorderThickness("1,1,0,1")
        this._AddSmallBtn(rightTools, "BtnIgnoreSize2", "2", 24, GetLang("2像素方形笔刷"))
            .Margin("0").BorderThickness("1,1,0,1")
        this._AddSmallBtn(rightTools, "BtnIgnoreSize3", "3", 24, GetLang("3像素方形笔刷"))
            .Margin("0")
        rightTools.Add("Border").Width("1").Height("18").Margin("4,0,4,0")
            .Background("{DynamicResource ControlBorder}")
        this._AddSmallBtn(rightTools, "BtnIgnoreUndo", Chr(0xE7A7), 28, GetLang("撤销上一步蒙版编辑"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13")
        this._AddSmallBtn(rightTools, "BtnIgnoreClear", Chr(0xE74D), 28, GetLang("清空忽略区域"))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("13")

        right := prev.Add("Border").Grid_Row(1).Grid_Column(2).Width(this.CanvasSide).Height(this.CanvasSide)
            .HorizontalAlignment("Center").ClipToBounds("True")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        rightCanvas := right.Add("Canvas").Name("RightCanvas").Width(this.CanvasSide).Height(this.CanvasSide).Background("Transparent")
        rightTransform := rightCanvas.Add("Canvas.RenderTransform").Add("TransformGroup")
        rightTransform.Add("ScaleTransform").SetProp("x:Name", "RightPreviewScale")
        rightTransform.Add("TranslateTransform").SetProp("x:Name", "RightPreviewTranslate")
        rightCanvas.SetProp("RenderTransformOrigin", "0,0")
        rightCanvas.Add("Image").Name("RightImg").Width(this.CanvasSide).Height(this.CanvasSide).Stretch("Uniform")
        rightCanvas.Add("Image").Name("RightPointOverlayImg").Width(this.CanvasSide).Height(this.CanvasSide)
            .Stretch("Fill").IsHitTestVisible("False").SetProp("Panel.ZIndex", "2")
        rightCanvas.Add("Image").Name("IgnoreOverlayImg").Width(this.CanvasSide).Height(this.CanvasSide)
            .Stretch("Fill").IsHitTestVisible("False").SetProp("Panel.ZIndex", "3")

        ; ---- 参数区 ----
        p := main.Add("Grid").Grid_Row(3).Margin(contentInset ",12," contentInset ",0")
        p.Rows("*")
        p.Cols("*")

        originalTools := p.Add("Grid").Name("OriginalToolsCon")
        originalTools.Cols("*")
        originalTools.Rows("36", "34")
        fileNameRow := originalTools.Add("Grid").Grid_Row(0)
        fileNameRow.Cols("Auto", "8", "260", "Auto", "Auto", "*")
        fileNameRow.Add("TextBlock").Grid_Column(0).Text(GetLang("文件名：")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        fileNameRow.Add("TextBox").Grid_Column(2).Name("NameCon").Width(260).Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        fileNameRow.Add("TextBlock").Grid_Column(3).Name("ExtCon").Text(".png").FontSize("12")
            .VerticalAlignment("Center").Margin("8,0").Foreground("{DynamicResource TextSub}")
        fileNameRow.Add("Button").Grid_Column(4).Name("BtnRename").Content(GetLang("重命名"))
            .MinWidth(76).Height(28).MinHeight(28).Padding("10,0").FontSize("11").Cursor("Hand")
            .ToolTip(GetLang("按输入名称重命名模板图片"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        cropRow := originalTools.Add("Grid").Grid_Row(1)
        cropRow.Cols("Auto", "8", "Auto", "8", "Auto", "12", "*")
        cropRow.Add("TextBlock").Grid_Column(0).Text(GetLang("图片裁剪")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._AddBtn(cropRow, "BtnCrop", GetLang("裁剪"), 64, GetLang("拖动框选要保留的区域"))
            .Grid_Column(2)
        this._AddBtn(cropRow, "BtnApply", GetLang("应用裁剪"), 84, GetLang("应用选区并替换模板图片"))
            .Grid_Column(4)
        originalStatus := cropRow.Add("StackPanel").Grid_Column(6).Orientation("Horizontal")
            .VerticalAlignment("Center")
        originalStatus.Add("TextBlock").Name("OriginalStatCon")
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        originalStatus.Add("TextBlock").Name("NewSizeStatCon").Margin("8,0,0,0")
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        originalStatus.Add("TextBlock").Name("SelectionPositionStatCon").Margin("8,0,0,0")
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")

        matchTools := p.Add("Grid").Name("MatchControlsCon").SetProp("Grid.IsSharedSizeScope", "True")
        matchTools.Rows("36", "36", "Auto", "Auto")
        matchCols := matchTools.Add("Grid.ColumnDefinitions")
        for width in ["Auto", "8", "220", "8", "Auto", "12", "Auto", "*"] {
            column := matchCols.Add("ColumnDefinition").Width(width)
            if (A_Index == 1)
                column.SharedSizeGroup("ImageProcessLabel")
            else if (A_Index == 5)
                column.SharedSizeGroup("ImageProcessValue")
        }
        matchTools.Add("TextBlock").Grid_Row(0).Grid_Column(0).Name("PointCountLabelCon")
            .Text(GetLang("基准色：")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        seedActions := matchTools.Add("StackPanel").Grid_Row(0).Grid_Column(2).Grid_ColumnSpan(6)
            .Orientation("Horizontal").VerticalAlignment("Center")
        seedActions.Add("TextBlock").Name("SeedCountCon").MinWidth(72)
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddSmallBtn(seedActions, "BtnMultiSeedTool", Chr(0x2316), 28, GetLang("点击图片选取基准颜色"))
            .FontFamily("Segoe UI Symbol").FontSize("15").Margin("8,0,0,0")
        this._AddSmallBtn(seedActions, "BtnSuperSeedTool", Chr(0x2316), 28, GetLang("点击图片选取基准颜色"))
            .FontFamily("Segoe UI Symbol").FontSize("15").Margin("8,0,0,0")
        matchTools.Add("TextBlock").Grid_Row(1).Grid_Column(0).Name("TolLabelCon")
            .Text(GetLang("点位容差：")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        matchTools.Add("Slider").Grid_Row(1).Grid_Column(2).Name("TolSlider").Width(220)
            .VerticalAlignment("Center").Minimum(0).Maximum(255).Value(this.Tol)
            .ToolTip(GetLang("容差越高，可接受色差越大，也更易误匹配"))
        matchTools.Add("TextBlock").Grid_Row(1).Grid_Column(4).Name("TolRangeCon").Text(GetLang("0 ~ 255")).FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        matchTools.Add("TextBox").Grid_Row(1).Grid_Column(6).Name("TolCon").Width(52).Height(28).MinHeight(28)
            .HorizontalAlignment("Left")
            .VerticalAlignment("Center").VerticalContentAlignment("Center").TextAlignment("Center").FontSize("11")
            .ToolTip(GetLang("容差越高，可接受色差越大，也更易误匹配"))
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        autoHost := matchTools.Add("Grid").Grid_Row(2).Grid_Column(0).Grid_ColumnSpan(8)
            .Name("AutoPointsCon").Height(36)
        autoCols := autoHost.Add("Grid.ColumnDefinitions")
        for width in ["Auto", "8", "220", "8", "Auto", "12", "Auto", "*"] {
            column := autoCols.Add("ColumnDefinition").Width(width)
            if (A_Index == 1)
                column.SharedSizeGroup("ImageProcessLabel")
            else if (A_Index == 5)
                column.SharedSizeGroup("ImageProcessValue")
        }
        autoHost.Add("TextBlock").Grid_Column(0).Text(GetLang("密集度：")).FontSize("12").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        autoHost.Add("Slider").Grid_Column(2).Name("DensitySlider").Width(220)
            .VerticalAlignment("Center").Minimum(0).Maximum(100).Value(this.AutoPointDensity)
            .ToolTip(GetLang("调节自动选点的覆盖密度"))
        autoHost.Add("TextBlock").Grid_Column(4).Name("DensityValueCon").Text(String(this.AutoPointDensity) "%")
            .MinWidth(52).TextAlignment("Center").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        autoHost.Add("Button").Grid_Column(6).Name("BtnAutoPoints").Content(GetLang("自动选点"))
            .MinWidth(82).Height(28).MinHeight(28).Padding("10,0").FontSize("11").Cursor("Hand")
            .HorizontalAlignment("Left").VerticalAlignment("Center")
            .ToolTip(GetLang("按基准点和容差自动补点"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        pointActions := autoHost.Add("StackPanel").Grid_Column(7).Orientation("Horizontal")
            .VerticalAlignment("Center").Margin("12,0,0,0")
        pointActions.Add("TextBlock").Name("PointCountCon").MinWidth(52)
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        pointActions.Add("Button").Name("BtnClear").Content(GetLang("清空点位"))
            .MinWidth(76).Height(28).MinHeight(28).Margin("12,0,0,0").Padding("10,0").FontSize("11").Cursor("Hand")
            .ToolTip(GetLang("清除当前模式的点位"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        matchTools.Add("TextBlock").Grid_Row(3).Grid_Column(0).Grid_ColumnSpan(8).Name("MatchStatCon")
            .FontSize("11").VerticalAlignment("Center").Visibility("Collapsed")
            .Foreground("{DynamicResource TextSub}")

        ; ---- 底部按钮 ----
        btnRow := main.Add("StackPanel").Grid_Row(5).Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center").Margin("0,0,16,0")
        btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(90).Height(32).MinHeight(32)
            .Margin("0,0,10,0").Cursor("Hand").ToolTip(GetLang("关闭并放弃本次点位修改"))
        btnRow.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(90).Height(32).MinHeight(32)
            .Cursor("Hand").ToolTip(GetLang("应用点位设置并返回搜索窗口"))

        ; ---- 宿主 ----
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="' this._Esc(title) '" Width="784" Height="686"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; ---- 事件 ----
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing").Bind(windowToken))
        this.ui.OnEvent("ShowLeftOverlayCon", "Checked", ObjBindMethod(this, "OnPointOverlayVisibility", "L", true))
        this.ui.OnEvent("ShowLeftOverlayCon", "Unchecked", ObjBindMethod(this, "OnPointOverlayVisibility", "L", false))
        this.ui.OnEvent("ShowRightOverlayCon", "Checked", ObjBindMethod(this, "OnPointOverlayVisibility", "R", true))
        this.ui.OnEvent("ShowRightOverlayCon", "Unchecked", ObjBindMethod(this, "OnPointOverlayVisibility", "R", false))
        this.ui.OnEvent("BtnCrop", "Click", ObjBindMethod(this, "OnToggleCrop"))
        this.ui.OnEvent("BtnApply", "Click", ObjBindMethod(this, "OnApplyCrop"))
        this.ui.OnEvent("BtnModeOriginal", "Click", ObjBindMethod(this, "OnMatchMode", "original"))
        this.ui.OnEvent("BtnModeMultiPoint", "Click", ObjBindMethod(this, "OnMatchMode", "multi"))
        this.ui.OnEvent("BtnModeSuperMultiPoint", "Click", ObjBindMethod(this, "OnMatchMode", "super"))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnHelp"))
        this.ui.OnEvent("BtnFitView", "Click", ObjBindMethod(this, "OnFitView"))
        this.ui.OnEvent("BtnMultiSeedTool", "Click", ObjBindMethod(this, "OnPointTool", "seed"))
        this.ui.OnEvent("BtnMultiPointTool", "Click", ObjBindMethod(this, "OnPointTool", "point"))
        this.ui.OnEvent("BtnSuperSeedTool", "Click", ObjBindMethod(this, "OnPointTool", "seed"))
        this.ui.OnEvent("BtnRename", "Click", ObjBindMethod(this, "OnRename"))
        this.ui.OnEvent("BtnClear", "Click", ObjBindMethod(this, "OnClearPoints"))
        this.ui.OnEvent("BtnAutoPoints", "Click", ObjBindMethod(this, "OnAutoSelectPoints"))
        this.ui.OnEvent("BtnIgnoreBrush", "Click", ObjBindMethod(this, "OnIgnoreTool", "brush"))
        this.ui.OnEvent("BtnIgnoreEraser", "Click", ObjBindMethod(this, "OnIgnoreTool", "eraser"))
        for size in [1, 2, 3]
            this.ui.OnEvent("BtnIgnoreSize" size, "Click", ObjBindMethod(this, "OnIgnoreSize", size))
        this.ui.OnEvent("BtnIgnoreUndo", "Click", ObjBindMethod(this, "OnIgnoreUndo"))
        this.ui.OnEvent("BtnIgnoreClear", "Click", ObjBindMethod(this, "OnIgnoreClear"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnSure"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancel"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancel"))
        this.ui.OnEvent("TolSlider", "ValueChanged", ObjBindMethod(this, "OnTolSlider"))
        this.ui.OnEvent("TolCon", "TextChanged", ObjBindMethod(this, "OnTolTextChanged"))
        this.ui.OnEvent("DensitySlider", "ValueChanged", ObjBindMethod(this, "OnDensitySlider"))
        this.ui.OnEvent("LeftCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnDown").Bind("L"))
        this.ui.OnEvent("LeftCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnMove").Bind("L"))
        this.ui.OnEvent("LeftCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnUp").Bind("L"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnIgnoreDown"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnRightMove"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnIgnoreUp"))

        this._ApplyModeStyle()
        this._SyncMatchModeUi()
    }

    OnHelp(*) {
        text := Format("{}`n{}`n{}`n`n{}`n{}`n{}"
            , GetLang("搜图方法：")
            , GetLang("原图：使用普通搜图方式。")
            , GetLang("多点和超多点：通过多个色块匹配；相似度表示命中色块的比例。")
            , GetLang("使用说明：")
            , GetLang("多点：选取基准点后可自动补点，也可手动添加或移除匹配点。最多选择256个点。")
            , GetLang("超多点：选取基准色并设置容差；忽略蒙版中的涂抹区域不参与匹配。"))
        RmtDialog.Info(text, GetLang("图片处理说明"))
    }

    OnFitView(*) {
        if (!IsObject(this.ui))
            return
        this.Zoom := 0
        this.ViewX := 0
        this.ViewY := 0
        this._ApplyPreviewTransform()
        this._Render()
    }

    ; 框架不派发 MouseWheel，用 AHK 热键在对话框内接管滚轮
    _BindWheel() {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        this._hwnd := hwnd
        if (!hwnd)
            return
        try {
            HotIfWinActive("ahk_id " hwnd)
            Hotkey("WheelUp", (*) => this.OnWheel(1), "On")
            Hotkey("WheelDown", (*) => this.OnWheel(-1), "On")
            HotIfWinActive()
        }
    }

    _UnbindWheel() {
        this._CancelWheelRender()
        if (!this._hwnd)
            return
        try {
            HotIfWinActive("ahk_id " this._hwnd)
            Hotkey("WheelUp", "Off")
            Hotkey("WheelDown", "Off")
            HotIfWinActive()
        }
    }

    OnWheel(dir, *) {
        base := (this.Zoom > 0) ? this.Zoom : this._FitZoom()
        mouse := this._MouseCanvasPoint()
        anchor := ""
        if (mouse.x >= 0 && mouse.y >= 0 && mouse.x <= this.CanvasSide && mouse.y <= this.CanvasSide) {
            anchor := this._ToImageFloat(mouse.x, mouse.y, base, this.ViewX, this.ViewY)
            if (anchor.x < 0 || anchor.y < 0 || anchor.x >= this.OrigW || anchor.y >= this.OrigH)
                anchor := ""
        }
        z := base * (dir > 0 ? 1.25 : 1 / 1.25)
        z := Min(16.0, Max(0.1, z))
        this.Zoom := Floor(z * 100) / 100

        ; 调整视口，使滚轮前光标下的原图像素仍位于同一画布位置。
        if (IsObject(anchor)) {
            layout := this._ViewLayout(this.Zoom)
            scale := this._CanvasScale()
            cx := mouse.x / scale
            cy := mouse.y / scale
            maxX := Max(0, this.OrigW - layout.viewW)
            maxY := Max(0, this.OrigH - layout.viewH)
            this.ViewX := Min(maxX, Max(0, anchor.x - (cx - layout.offsetX) / layout.zoom))
            this.ViewY := Min(maxY, Max(0, anchor.y - (cy - layout.offsetY) / layout.zoom))
        }
        this._wheelPending := true
        this._ApplyPreviewTransform()
        SetTimer(this._wheelRenderTimer, -160)
    }

    _FlushWheelRender(*) {
        if (this._wheelPending && IsObject(this.ui)) {
            this._wheelPending := false
            this._Render()
        }
    }

    _CancelWheelRender() {
        try SetTimer(this._wheelRenderTimer, 0)
    }

    _ResetPreviewTransform() {
        this._CancelWheelRender()
        this._wheelPending := false
        this._renderedZoom := 0
        this._renderedViewX := 0
        this._renderedViewY := 0
        this._previewScale := 1
        this._previewOffsetX := 0
        this._previewOffsetY := 0
        if (!IsObject(this.ui))
            return
        try this.ui.BatchUpdate([
            { ControlName: "LeftPreviewScale", PropertyName: "ScaleX", Value: "1" },
            { ControlName: "LeftPreviewScale", PropertyName: "ScaleY", Value: "1" },
            { ControlName: "LeftPreviewTranslate", PropertyName: "X", Value: "0" },
            { ControlName: "LeftPreviewTranslate", PropertyName: "Y", Value: "0" },
            { ControlName: "RightPreviewScale", PropertyName: "ScaleX", Value: "1" },
            { ControlName: "RightPreviewScale", PropertyName: "ScaleY", Value: "1" },
            { ControlName: "RightPreviewTranslate", PropertyName: "X", Value: "0" },
            { ControlName: "RightPreviewTranslate", PropertyName: "Y", Value: "0" }
        ])
    }

    _AddBtn(parent, name, text, w, tip := "") {
        btn := parent.Add("Button").Name(name).Content(text)
            .MinWidth(w).Height(28).MinHeight(28).Padding("10,0").Margin("0,0,6,0").FontSize("11").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        if (tip != "")
            btn.ToolTip(tip)
        return btn
    }

    _AddSmallBtn(parent, name, text, w, tip := "") {
        btn := parent.Add("Button").Name(name).Content(text)
            .Width(w).Height(28).MinHeight(28).Padding("0").Margin("0,0,2,0").FontSize("11").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        if (tip != "")
            btn.ToolTip(tip)
        return btn
    }

    _Esc(s) => StrReplace(StrReplace(StrReplace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

    _ResetInteraction() {
        this.Mode := ""
        this.Resizing := ""
        this.Dragging := false
        this.DragMoved := false
        this.DragStartX := 0
        this.DragStartY := 0
        this.DragViewX := 0
        this.DragViewY := 0
        this.SelX := 0
        this.SelY := 0
        this.SelW := 0
        this.SelH := 0
        this.ViewX := 0
        this.ViewY := 0
    }

    ; ------------------------------------------------------------------
    ; 控件同步
    ; ------------------------------------------------------------------
    _SyncControls() {
        if (!IsObject(this.ui))
            return
        SplitPath(this.TemplatePath, , , , &nameNoExt)
        ext := this._Ext(this.TemplatePath)
        try this.ui.Update("NameCon", "Text", nameNoExt)
        try this.ui.Update("ExtCon", "Text", ext)
        try this.ui.Update("TolCon", "Text", String(this.Tol))
        try this.ui.Update("TolSlider", "Value", this.Tol)
        try this.ui.Update("DensityValueCon", "Text", String(this.AutoPointDensity) "%")
        try this.ui.Update("DensitySlider", "Value", this.AutoPointDensity)
        try this.ui.Update("BtnApply", "IsEnabled", (this.SelW > 0 && this.SelH > 0) ? "True" : "False")
    }

    _Ext(path) {
        SplitPath(path, , , &ext)
        ext := Trim(ext)
        if (ext = "")
            return ".png"
        return (SubStr(ext, 1, 1) = ".") ? ext : "." ext
    }

    ; ------------------------------------------------------------------
    ; 渲染
    ; ------------------------------------------------------------------
    _Render() {
        this._CancelToleranceRender()
        this._CancelWheelRender()
        this._wheelPending := false
        if (!IsObject(this.ui) || this.TemplatePath = "" || !FileExist(this.TemplatePath))
            return

        if (this.Zoom <= 0 && this.OrigW > 0)
            this.Zoom := this._FitZoom()

        zoomPercent := Max(1, Round(this.Zoom * 100))
        if (this.OrigW <= 0) {
            ; 先探一次原图尺寸
            probeBase := A_Temp "\RMT_fe_probe_" A_TickCount "_" this._seq
            probeOrig := probeBase "_o.png"
            probeEff := probeBase "_e.png"
            probe := this._Call(0, 0, 0, 0, zoomPercent, probeOrig, probeEff)
            try FileDelete(probeOrig)
            try FileDelete(probeEff)
            if (probe.ret != 1 || probe.ow <= 0) {
                this._SetModeStatus(GetLang("模板读取失败"))
                return
            }
            this.OrigW := probe.ow
            this.OrigH := probe.oh
            if (this.Zoom <= 0)
                this.Zoom := this._FitZoom()
            zoomPercent := Max(1, Round(this.Zoom * 100))
        }

        ; 视图尺寸
        layout := this._ViewLayout(this.Zoom)
        vw := layout.viewW
        vh := layout.viewH
        this.ViewW := vw
        this.ViewH := vh

        ; 夹住平移
        maxX := Max(0, this.OrigW - vw), maxY := Max(0, this.OrigH - vh)
        this.ViewX := Min(Max(0, this.ViewX), maxX)
        this.ViewY := Min(Max(0, this.ViewY), maxY)
        renderViewX := Min(maxX, Max(0, Round(this.ViewX)))
        renderViewY := Min(maxY, Max(0, Round(this.ViewY)))

        this._seq += 1
        outBase := A_Temp "\RMT_fe_" A_TickCount "_" this._seq
        outOrig := outBase "_o.png"
        outEff := outBase "_e.png"
        showGrid := this.Zoom >= 6.0 ? 1 : 0

        previewSeeds := this.EditorMode == "original" ? [] :
            (this.EditorMode == "super" ? this.SuperSeedPoints : this.SeedPoints)
        try info := this._Call(renderViewX, renderViewY, vw, vh, zoomPercent, outOrig, outEff
            , showGrid, this._MultiPointText(previewSeeds), this.Tol)
        catch {
            info := { ret: -5, valid: 0, total: 0, ow: this.OrigW, oh: this.OrigH }
        }
        if (info.ret != 1)
        {
            err := GetImageLastErrorText()
            this._SetModeStatus(err != "" ? err : GetLang("预览生成失败"))
            return
        }

        this.OrigW := info.ow, this.OrigH := info.oh
        this._rendering := true
        this._renderedZoom := this.Zoom
        try this.ui.Update("ZoomCon", "Text", Round(this.Zoom * 100) "%")
        this._renderedViewX := renderViewX
        this._renderedViewY := renderViewY
        leftPointOverlayPath := this._CreateModePointOverlay("L")
        rightPointOverlayPath := this._CreateModePointOverlay("R")
        ignoreOverlayPath := this._CreateModeIgnoreOverlay()
        sourceUpdates := [
            { ControlName: "LeftImg", PropertyName: "Source", Value: StrReplace(outOrig, "\", "/") },
            { ControlName: "RightImg", PropertyName: "Source", Value: StrReplace(outEff, "\", "/") },
            { ControlName: "PointOverlayImg", PropertyName: "Source"
                , Value: leftPointOverlayPath == "" ? "" : StrReplace(leftPointOverlayPath, "\", "/") },
            { ControlName: "RightPointOverlayImg", PropertyName: "Source"
                , Value: rightPointOverlayPath == "" ? "" : StrReplace(rightPointOverlayPath, "\", "/") },
            { ControlName: "IgnoreOverlayImg", PropertyName: "Source"
                , Value: ignoreOverlayPath == "" ? "" : StrReplace(ignoreOverlayPath, "\", "/") },
            { ControlName: "PointOverlayImg", PropertyName: "Visibility"
                , Value: this.ShowLeftPointOverlay ? "Visible" : "Collapsed" },
            { ControlName: "RightPointOverlayImg", PropertyName: "Visibility"
                , Value: this.ShowRightPointOverlay ? "Visible" : "Collapsed" },
            { ControlName: "IgnoreOverlayImg", PropertyName: "Visibility"
                , Value: this.ShowRightPointOverlay ? "Visible" : "Collapsed" }
        ]
        for update in this._PreviewTransformUpdates()
            sourceUpdates.Push(update)
        try this.ui.BatchUpdate(sourceUpdates)

        oldLeftOverlay := this._lastLeftOverlay
        oldRightOverlay := this._lastRightOverlay
        oldIgnoreOverlay := this._lastIgnoreOverlay
        this._lastLeftOverlay := leftPointOverlayPath
        this._lastRightOverlay := rightPointOverlayPath
        this._lastIgnoreOverlay := ignoreOverlayPath
        this._rendering := false
        if (oldLeftOverlay != leftPointOverlayPath)
            try FileDelete(oldLeftOverlay)
        if (oldRightOverlay != rightPointOverlayPath)
            try FileDelete(oldRightOverlay)
        if (oldIgnoreOverlay != ignoreOverlayPath)
            try FileDelete(oldIgnoreOverlay)
        if (this._ignoreOverlayRefreshPending) {
            this._ignoreOverlayRefreshPending := false
            this._RefreshIgnoreOverlay()
        }

        ; 清理上一帧
        try FileDelete(this._lastOrig)
        try FileDelete(this._lastEff)
        this._lastOrig := outOrig
        this._lastEff := outEff

        if (this.EditorMode == "original")
            this._SetOriginalStatus(info.ow, info.oh)
        else
            this._SetModeStatus("")
        try this.ui.Update("BtnApply", "IsEnabled", (this.SelW > 0 && this.SelH > 0) ? "True" : "False")
        this._RefreshProcessControls()
    }

    _FitZoom() {
        if (this.OrigW <= 0 || this.OrigH <= 0)
            return 1.0
        z := Min(this.CanvasSide / this.OrigW, this.CanvasSide / this.OrigH, 16.0)
        z := Floor(z * 100) / 100
        return Max(0.1, z)
    }

    ; 与 RenderImagePreview 使用同一套尺寸、缩放和居中规则。
    _ViewLayout(zoom := 0) {
        if (zoom <= 0)
            zoom := (this.Zoom > 0) ? this.Zoom : 1.0

        vw := Max(1, Floor(this.CanvasSide / zoom))
        vh := vw
        if (this.OrigW > 0 && vw > this.OrigW)
            vw := this.OrigW
        if (this.OrigH > 0 && vh > this.OrigH)
            vh := this.OrigH

        zoomPercent := Max(1, Round(zoom * 100))
        zs := zoomPercent / 100.0
        bw := Max(1, Round(vw * zs))
        bh := Max(1, Round(vh * zs))
        offsetX := Integer((this.CanvasSide - bw) / 2)
        offsetY := Integer((this.CanvasSide - bh) / 2)
        return { viewW: vw, viewH: vh, zoom: zs, offsetX: offsetX, offsetY: offsetY }
    }

    _Call(vx, vy, vw, vh, zoomPercent, outOrig, outEff, showGrid := 0, seedPoints := "", tolerance := 0) {
        valid := 0, total := 0, pw := 0, ph := 0, ow := 0, oh := 0
        bx := 0, by := 0, bw := 0, bh := 0
        ret := DllCall("RMT_OpenCV.dll\RenderImagePreview"
            , "Str", this.TemplatePath
            , "Int", this.CanvasSide, "Int", this.CanvasSide
            , "Int", vx, "Int", vy, "Int", vw, "Int", vh
            , "Int", this.SelX, "Int", this.SelY, "Int", this.SelW, "Int", this.SelH
            , "Int", showGrid, "Int", zoomPercent
            , "Str", seedPoints, "Int", tolerance
            , "Str", outOrig, "Str", outEff
            , "Int*", &valid, "Int*", &total, "Int*", &pw, "Int*", &ph
            , "Int*", &ow, "Int*", &oh, "Int*", &bx, "Int*", &by, "Int*", &bw, "Int*", &bh
            , "CDecl Int")
        return { ret: ret, valid: valid, total: total, ow: ow, oh: oh }
    }

    ; ------------------------------------------------------------------
    ; 交互
    ; ------------------------------------------------------------------
    _XY(state, side) {
        key := (side == "L") ? "LeftCanvas" : "RightCanvas"
        raw := (IsObject(state) && state.Has(key)) ? state[key] : ""
        if (!InStr(raw, ","))
            return { x: -1, y: -1 }
        parts := StrSplit(raw, ",")
        point := { x: Number(parts[1]), y: Number(parts[2]) }
        return this._CanvasPointToViewport(point)
    }

    _MouseCanvasPoint() {
        state := ""
        try state := this.ui.Query("LeftCanvas>MouseLocal", "RightCanvas>MouseLocal")
        if (!IsObject(state))
            return { x: -1, y: -1 }
        for side in ["L", "R"] {
            key := side == "L" ? "LeftCanvas>MouseLocal" : "RightCanvas>MouseLocal"
            raw := state.Has(key) ? String(state[key]) : ""
            if (!InStr(raw, ";"))
                continue
            parts := StrSplit(raw, ";")
            if (parts.Length < 2 || !IsNumber(parts[1]) || !IsNumber(parts[2]))
                continue
            point := this._CanvasPointToViewport({ x: Number(parts[1]), y: Number(parts[2]) })
            if (point.x >= 0 && point.y >= 0 && point.x <= this.CanvasSide && point.y <= this.CanvasSide)
                return point
        }
        return { x: -1, y: -1 }
    }

    _RightCanvasPoint() {
        if (!IsObject(this.ui))
            return ""
        raw := ""
        try raw := String(this.ui.Query("RightCanvas>MouseLocal"))
        if (!InStr(raw, ";"))
            return ""
        parts := StrSplit(raw, ";")
        if (parts.Length < 2 || !IsNumber(parts[1]) || !IsNumber(parts[2]))
            return ""
        return this._CanvasPointToViewport({ x: Number(parts[1]), y: Number(parts[2]) })
    }

    _CanvasPointToViewport(point) {
        return { x: point.x * this._previewScale + this._previewOffsetX
            , y: point.y * this._previewScale + this._previewOffsetY }
    }

    _PreviewTransformUpdates() {
        scale := 1, offsetX := 0, offsetY := 0
        if (this._renderedZoom > 0 && this.Zoom > 0) {
            base := this._ViewLayout(this._renderedZoom)
            target := this._ViewLayout(this.Zoom)
            scale := target.zoom / base.zoom
            offsetX := target.offsetX - scale * base.offsetX
                + (this._renderedViewX - this.ViewX) * target.zoom
            offsetY := target.offsetY - scale * base.offsetY
                + (this._renderedViewY - this.ViewY) * target.zoom
        }
        this._previewScale := scale
        this._previewOffsetX := offsetX
        this._previewOffsetY := offsetY
        return [
            { ControlName: "LeftPreviewScale", PropertyName: "ScaleX", Value: String(scale) },
            { ControlName: "LeftPreviewScale", PropertyName: "ScaleY", Value: String(scale) },
            { ControlName: "LeftPreviewTranslate", PropertyName: "X", Value: String(offsetX) },
            { ControlName: "LeftPreviewTranslate", PropertyName: "Y", Value: String(offsetY) },
            { ControlName: "RightPreviewScale", PropertyName: "ScaleX", Value: String(scale) },
            { ControlName: "RightPreviewScale", PropertyName: "ScaleY", Value: String(scale) },
            { ControlName: "RightPreviewTranslate", PropertyName: "X", Value: String(offsetX) },
            { ControlName: "RightPreviewTranslate", PropertyName: "Y", Value: String(offsetY) }
        ]
    }

    _ApplyPreviewTransform() {
        if (IsObject(this.ui))
            try this.ui.BatchUpdate(this._PreviewTransformUpdates())
    }

    _ToImageFloat(px, py, zoom := 0, viewX := "", viewY := "") {
        if (zoom <= 0)
            zoom := (this.Zoom > 0) ? this.Zoom : 1.0
        layout := this._ViewLayout(zoom)
        scale := this._CanvasScale()
        vx := (viewX == "") ? this.ViewX : viewX
        vy := (viewY == "") ? this.ViewY : viewY
        cx := px / scale
        cy := py / scale
        return { x: vx + (cx - layout.offsetX) / layout.zoom
            , y: vy + (cy - layout.offsetY) / layout.zoom }
    }

    _ToImage(px, py) {
        ; 画布坐标 → 原图坐标
        if (this.Zoom <= 0 || this.OrigW <= 0 || this.OrigH <= 0)
            return { x: 0, y: 0 }
        point := this._ToImageFloat(px, py)
        return { x: Floor(point.x), y: Floor(point.y) }
    }

    ; 元素实际宽度 ÷ 渲染宽度。正常是 1；若事件坐标是物理像素而控件是 DIP，则为 1.25
    _CanvasScale() {
        static cached := 0
        if (cached > 0)
            return cached
        w := 0
        try w := this.ui.Query("LeftCanvas>ActualWidth")
        if (IsNumber(w) && w > 0 && Abs(w - this.CanvasSide) > 0.5)
            cached := w / this.CanvasSide
        else
            cached := 1
        return cached
    }

    OnDown(side, state, ctrl, event) {
        if (side != "L" && side != "R")
            return
        p := this._XY(state, side)
        if (p.x < 0)
            return
        ; 先看是不是点在四角手柄上
        hit := side == "L" ? this._HitHandle(p.x, p.y) : ""
        if (hit != "") {
            this.Resizing := hit
            this.Dragging := true
            this.DragMoved := true
            this.DragStartX := p.x
            this.DragStartY := p.y
            this.DragViewX := this.ViewX
            this.DragViewY := this.ViewY
            return
        }

        this.Dragging := true
        this.DragMoved := false
        this.DragStartX := p.x
        this.DragStartY := p.y
        this.DragViewX := this.ViewX
        this.DragViewY := this.ViewY

        if (this.Mode == "crop") {
            img := this._ToImage(p.x, p.y)
            this.SelX := Min(Max(0, img.x), this.OrigW - 1)
            this.SelY := Min(Max(0, img.y), this.OrigH - 1)
            this.SelW := 0
            this.SelH := 0
        }
    }

    OnMove(side, state, ctrl, event) {
        if ((side != "L" && side != "R") || !this.Dragging)
            return
        p := this._XY(state, side)
        if (p.x < 0)
            return
        dx := p.x - this.DragStartX, dy := p.y - this.DragStartY
        if (Abs(dx) + Abs(dy) > 2)
            this.DragMoved := true

        if (this.Resizing != "") {
            img := this._ToImage(p.x, p.y)
            img.x := Min(Max(0, img.x), this.OrigW - 1)
            img.y := Min(Max(0, img.y), this.OrigH - 1)
            x2 := this.SelX + this.SelW
            y2 := this.SelY + this.SelH
            if (InStr(this.Resizing, "T")) {
                this.SelY := Min(img.y, y2 - 1)
                this.SelH := y2 - this.SelY
            } else {
                this.SelH := Max(1, img.y - this.SelY)
            }
            if (InStr(this.Resizing, "L")) {
                this.SelX := Min(img.x, x2 - 1)
                this.SelW := x2 - this.SelX
            } else {
                this.SelW := Max(1, img.x - this.SelX)
            }
            this._Render()
            return
        }

        if (this.Mode == "crop") {
            a := this._ToImage(this.DragStartX, this.DragStartY)
            b := this._ToImage(p.x, p.y)
            x1 := Min(a.x, b.x), y1 := Min(a.y, b.y)
            x2 := Max(a.x, b.x) + 1, y2 := Max(a.y, b.y) + 1
            x1 := Min(Max(0, x1), this.OrigW - 1), y1 := Min(Max(0, y1), this.OrigH - 1)
            x2 := Min(Max(x1 + 1, x2), this.OrigW), y2 := Min(Max(y1 + 1, y2), this.OrigH)
            this.SelX := x1, this.SelY := y1, this.SelW := x2 - x1, this.SelH := y2 - y1
            this._Render()
        }
        else if (this.Mode == "") {
            ; 平移
            if (this.Zoom > 0 && (this.OrigW > this.ViewW || this.OrigH > this.ViewH)) {
                maxX := Max(0, this.OrigW - this.ViewW)
                maxY := Max(0, this.OrigH - this.ViewH)
                this.ViewX := Min(maxX, Max(0, this.DragViewX - Floor(dx / this.Zoom)))
                this.ViewY := Min(maxY, Max(0, this.DragViewY - Floor(dy / this.Zoom)))
                this._ApplyPreviewTransform()
            }
        }
    }

    OnUp(side, state, ctrl, event) {
        if ((side != "L" && side != "R") || !this.Dragging)
            return
        viewChanged := this.ViewX != this.DragViewX || this.ViewY != this.DragViewY
        this.Resizing := ""             ; "" / "TL" / "TR" / "BL" / "BR"
        this.Dragging := false
        p := this._XY(state, side)
        if (p.x < 0) {
            if (viewChanged)
                this._Render()
            return
        }

        canEditPoints := (this.EditorMode == "multi"
            && ((side == "L" && this.PointTool == "seed") || (side == "R" && this.PointTool == "point")))
            || (this.EditorMode == "super" && side == "L" && this.PointTool == "seed")
        if (this.Mode == "" && canEditPoints && !this.DragMoved && !viewChanged) {
            img := this._ToImage(p.x, p.y)
            if (img.x >= 0 && img.y >= 0 && img.x < this.OrigW && img.y < this.OrigH)
                this._ToggleMultiPoint(img.x, img.y, p.x, p.y)
            return
        }
        if (this.Mode == "crop") {
            if (this.SelW < 2 || this.SelH < 2) {
                this.SelW := 0
                this.SelH := 0
            }
            this._Render()
        } else if (viewChanged)
            this._Render()
    }

    _ParseIgnoreData(text) {
        operations := []
        if (text == "")
            return operations
        if (StrLen(text) > 4 * 1024 * 1024)
            return ""

        totalPoints := 0
        for token in StrSplit(text, ";") {
            fields := StrSplit(token, ":")
            if (fields.Length > 0 && fields[1] == "R")
                continue

            if (fields.Length != 3 || (fields[1] != "B" && fields[1] != "E")
                || !this._IsIgnoreInteger(fields[2]) || fields[3] == "")
                return ""
            size := Integer(fields[2])
            if (size < 1 || size > 3)
                return ""
            points := []
            for pointText in StrSplit(fields[3], "|") {
                pointFields := StrSplit(pointText, ",")
                if (pointFields.Length != 2 || !this._IsIgnoreInteger(pointFields[1])
                    || !this._IsIgnoreInteger(pointFields[2]))
                    return ""
                points.Push({ x: Integer(pointFields[1]), y: Integer(pointFields[2]) })
                if (++totalPoints > 1000000)
                    return ""
            }
            operations.Push({
                type: "stroke", erase: fields[1] == "E", size: size, points: points
            })
            if (operations.Length > 100000)
                return ""
        }
        return operations
    }

    _IsIgnoreInteger(value) {
        value := String(value)
        if (StrLen(value) > 8 || !RegExMatch(value, "^-?\d+$"))
            return false
        try number := Integer(value)
        catch
            return false
        return number >= -1000000 && number <= 1000000
    }

    _SerializeIgnoreData(operations) {
        text := ""
        for operation in operations {
            token := ""
            if (operation.type == "stroke" && IsObject(operation.points)
                && operation.points.Length > 0) {
                pointsText := ""
                for point in operation.points
                    pointsText .= (pointsText == "" ? "" : "|") . Integer(point.x) "," Integer(point.y)
                token := (operation.erase ? "E:" : "B:") Integer(operation.size) ":" pointsText
            }
            if (token != "")
                text .= (text == "" ? "" : ";") token
        }
        return text
    }

    _IgnoreImagePoint(canvasPoint) {
        if (!IsObject(canvasPoint) || this.Zoom <= 0 || this.OrigW <= 0 || this.OrigH <= 0)
            return ""
        imagePoint := this._ToImageFloat(canvasPoint.x, canvasPoint.y)
        if (imagePoint.x < 0 || imagePoint.y < 0
            || imagePoint.x >= this.OrigW || imagePoint.y >= this.OrigH)
            return ""
        return { x: Floor(imagePoint.x), y: Floor(imagePoint.y) }
    }

    OnRightMove(state, ctrl, event) {
        if (this.EditorMode == "multi")
            this.OnMove("R", state, ctrl, event)
    }

    OnIgnoreDown(state, ctrl, event) {
        if (this.EditorMode == "multi") {
            this.OnDown("R", state, ctrl, event)
            return
        }
        if (this.EditorMode != "super" || this.IgnoreTool == "")
            return
        canvasPoint := this._XY(state, "R")
        imagePoint := this._IgnoreImagePoint(canvasPoint)
        if (!IsObject(imagePoint))
            return

        this.IgnoreDragging := true
        this.IgnoreCurrentOp := {
            type: "stroke", erase: this.IgnoreTool == "eraser",
            size: this.IgnoreBrushSize, points: [imagePoint]
        }
        this._CancelIgnoreOverlay()
        SetTimer(this._ignoreStrokeTimer, 16)
        SetTimer(this._ignoreOverlayTimer, 30)
        this._RefreshIgnoreOverlay()
    }

    _PollIgnoreStroke(*) {
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        canvasPoint := this._RightCanvasPoint()
        imagePoint := this._IgnoreImagePoint(canvasPoint)
        if (IsObject(imagePoint))
            this._AppendIgnorePoint(imagePoint)
        if (!(DllCall("GetAsyncKeyState", "Int", 0x01, "Short") & 0x8000)) {
            this._FinishIgnoreStroke()
        }
    }

    OnIgnoreUp(state, ctrl, event) {
        if (this.EditorMode == "multi") {
            this.OnUp("R", state, ctrl, event)
            return
        }
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        imagePoint := this._IgnoreImagePoint(this._XY(state, "R"))
        if (IsObject(imagePoint))
            this._AppendIgnorePoint(imagePoint)
        this._FinishIgnoreStroke()
    }

    _AppendIgnorePoint(imagePoint) {
        points := this.IgnoreCurrentOp.points
        last := points[points.Length]
        dx := imagePoint.x - last.x
        dy := imagePoint.y - last.y
        steps := Max(Abs(dx), Abs(dy))
        loop steps {
            x := Round(last.x + dx * A_Index / steps)
            y := Round(last.y + dy * A_Index / steps)
            point := { x: x, y: y }
            previous := points[points.Length]
            if (previous.x != x || previous.y != y)
                points.Push(point)
        }
    }

    _FinishIgnoreStroke() {
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        SetTimer(this._ignoreStrokeTimer, 0)
        this._CancelIgnoreOverlay()
        operation := this.IgnoreCurrentOp
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        if (operation.points.Length < 1)
            return
        this._PushIgnoreUndo()
        this.IgnoreOps.Push(operation)
        this.SuperIgnoreData := this._SerializeIgnoreData(this.IgnoreOps)
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
    }

    OnIgnoreTool(requestedTool, *) {
        if (this.IgnoreDragging)
            this._FinishIgnoreStroke()
        SetTimer(this._ignoreStrokeTimer, 0)
        this.IgnoreTool := this.IgnoreTool == requestedTool ? "" : requestedTool
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this._SyncIgnoreControls()
        this._RefreshIgnoreOverlay()
    }

    OnIgnoreSize(size, *) {
        this.IgnoreBrushSize := size
        this._SyncIgnoreControls()
    }

    _PushIgnoreUndo() {
        this.IgnoreUndo.Push(this._SerializeIgnoreData(this.IgnoreOps))
        if (this.IgnoreUndo.Length > 20)
            this.IgnoreUndo.RemoveAt(1)
        this.IgnoreRedo := []
    }

    _RestoreIgnoreData(data) {
        operations := this._ParseIgnoreData(data)
        if (!IsObject(operations))
            return false
        this.IgnoreOps := operations
        this.SuperIgnoreData := this._SerializeIgnoreData(operations)
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
        return true
    }

    OnIgnoreUndo(*) {
        if (this.IgnoreUndo.Length < 1)
            return
        this.IgnoreRedo.Push(this._SerializeIgnoreData(this.IgnoreOps))
        previous := this.IgnoreUndo.Pop()
        this._RestoreIgnoreData(previous)
    }

    OnIgnoreRedo(*) {
        if (this.IgnoreRedo.Length < 1)
            return
        this.IgnoreUndo.Push(this._SerializeIgnoreData(this.IgnoreOps))
        next := this.IgnoreRedo.Pop()
        this._RestoreIgnoreData(next)
    }

    OnIgnoreClear(*) {
        if (this.IgnoreOps.Length < 1)
            return
        this._PushIgnoreUndo()
        this.IgnoreOps := []
        this.SuperIgnoreData := ""
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
    }

    ; 点是否落在四角手柄上（画布像素，容差 8）
    _HitHandle(px, py) {
        if (this.SelW <= 0 || this.SelH <= 0 || this.Zoom <= 0)
            return ""
        scale := this._CanvasScale()
        cx := px / scale
        cy := py / scale
        layout := this._ViewLayout(this.Zoom)
        x1 := layout.offsetX + (this.SelX - this.ViewX) * layout.zoom
        y1 := layout.offsetY + (this.SelY - this.ViewY) * layout.zoom
        x2 := layout.offsetX + (this.SelX + this.SelW - this.ViewX) * layout.zoom
        y2 := layout.offsetY + (this.SelY + this.SelH - this.ViewY) * layout.zoom
        tol := 8
        if (Abs(cx - x1) <= tol && Abs(cy - y1) <= tol)
            return "TL"
        if (Abs(cx - x2) <= tol && Abs(cy - y1) <= tol)
            return "TR"
        if (Abs(cx - x1) <= tol && Abs(cy - y2) <= tol)
            return "BL"
        if (Abs(cx - x2) <= tol && Abs(cy - y2) <= tol)
            return "BR"
        return ""
    }

    _ToggleMultiPoint(ix, iy, clickX, clickY) {
        ; 按预览中的标记位置命中，缩放时删除范围保持不变。
        if (this.EditorMode == "super" && this.PointTool != "seed")
            return
        if (this.EditorMode == "multi" && this.PointTool == "")
            return

        scale := this._CanvasScale()
        clickX /= scale
        clickY /= scale
        layout := this._ViewLayout(this.Zoom)
        hitRadius := 6

        if (this.EditorMode == "multi") {
            seedHit := this._FindPointHit(this.SeedPoints, layout, clickX, clickY, hitRadius)
            if (this.PointTool == "point" && seedHit > 0)
                return
            if (this.PointTool == "seed" && seedHit > 0) {
                removedSeed := this.SeedPoints[seedHit]
                this.SeedPoints.RemoveAt(seedHit)
                this._RemovePointByCoordinate(this.Points, removedSeed)
                this._SyncMatchModeUi()
                this._Render()
                return
            }
        }

        activePoints := this.EditorMode == "super" ? this.SuperSeedPoints : this.Points
        nearest := this._FindPointHit(activePoints, layout, clickX, clickY, hitRadius)
        if (nearest > 0) {
            removed := activePoints[nearest]
            if (this.EditorMode == "super") {
                this.SuperSeedPoints.RemoveAt(nearest)
            } else if (this.PointTool == "point") {
                this.Points.RemoveAt(nearest)
            } else {
                ; 点到已有普通点时将它提升为基准点，不重复创建坐标。
                this.SeedPoints.Push(removed)
            }
            this._SyncMatchModeUi()
            this._Render()
            return
        }
        this._AddMultiPoint(ix, iy, this.EditorMode == "super" || this.PointTool == "seed")
    }

    _FindPointHit(points, layout, clickX, clickY, hitRadius := 6) {
        nearest := 0
        nearestDistance := 0x7FFFFFFF
        for index, point in points {
            marker := this._PointMarkerBounds(point, layout)
            markerX := marker.x + marker.w / 2
            markerY := marker.y + marker.h / 2
            dx := markerX - clickX
            dy := markerY - clickY
            hitX := Max(hitRadius, marker.w / 2 + 2)
            hitY := Max(hitRadius, marker.h / 2 + 2)
            distance := dx * dx + dy * dy
            if (Abs(dx) <= hitX && Abs(dy) <= hitY && distance < nearestDistance) {
                nearest := index
                nearestDistance := distance
            }
        }
        return nearest
    }

    _FindPointIndex(points, target) {
        for index, point in points
            if (point.X == target.X && point.Y == target.Y)
                return index
        return 0
    }

    _RemovePointByCoordinate(points, target) {
        index := this._FindPointIndex(points, target)
        if (index > 0)
            points.RemoveAt(index)
    }

    _AddMultiPoint(ix, iy, isSeed := false) {
        try {
            if (!MultiPointApiReady())
                return
        } catch {
            return
        }
        isSuperSeed := this.EditorMode == "super"
        activePoints := isSuperSeed ? this.SuperSeedPoints : this.Points
        if (activePoints.Length >= 256)
            return
        for point in activePoints
            if (point.X == ix && point.Y == iy)
                return

        r := 0, g := 0, b := 0, a := 255
        ret := DllCall("RMT_OpenCV.dll\GetImagePixelAtEx", "Str", this.TemplatePath
            , "Int", ix, "Int", iy, "Int*", &r, "Int*", &g, "Int*", &b, "Int*", &a, "CDecl Int")
        if (ret != 1 || a < 128)
            return
        color := Format("{:02X}{:02X}{:02X}", r, g, b)
        point := {X: ix, Y: iy, Color: color}
        if (isSuperSeed) {
            this.SuperSeedPoints.Push(point)
        } else {
            this.Points.Push(point)
            if (isSeed)
                this.SeedPoints.Push(point)
        }
        if (this.MatchMode == "")
            this.MatchMode := this.EditorMode
        this._Render()
    }

    _CreateModePointOverlay(side) {
        if (this.EditorMode == "original" || this.OrigW <= 0)
            return ""

        if (side == "L" && !this.ShowLeftPointOverlay)
            return ""
        if (side == "R" && !this.ShowRightPointOverlay)
            return ""

        if (this.EditorMode == "super") {
            markerPoints := this.SuperSeedPoints
            markerSeeds := this.SuperSeedPoints
        } else if (side == "L") {
            markerPoints := this.SeedPoints
            markerSeeds := this.SeedPoints
        } else {
            markerPoints := this.Points
            markerSeeds := this.SeedPoints
        }
        if (markerPoints.Length == 0)
            return ""
        return this._CreatePointOverlay(markerPoints, markerSeeds)
    }

    _CreatePointOverlay(points := "", seedPoints := "") {
        if (!IsObject(points))
            points := this.Points
        if (!IsObject(seedPoints))
            seedPoints := this.SeedPoints
        this._overlaySeq += 1
        output := A_Temp "\RMT_fe_overlay_" A_TickCount "_" this._windowToken "_" this._overlaySeq ".png"
        bitmap := 0, graphics := 0, seedBrush := 0, autoBrush := 0, outlinePen := 0
        try {
            ; 32 位 ARGB 位图保留透明背景；基准点用暖色，自动点用冷色。
            bitmap := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!bitmap)
                return ""
            graphics := Gdip_GraphicsFromImage(bitmap)
            if (!graphics)
                return ""
            seedBrush := Gdip_BrushCreateSolid(0x90F5A623)
            autoBrush := Gdip_BrushCreateSolid(0x9032C7D5)
            outlinePen := Gdip_CreatePen(0xC0FFFFFF, 1)
            if (!seedBrush || !autoBrush || !outlinePen)
                return ""
            Gdip_GraphicsClear(graphics, 0x00000000)
            Gdip_SetSmoothingMode(graphics, 0)

            seeds := Map()
            for point in seedPoints
                seeds[point.X "," point.Y] := true

            overlayZoom := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
            overlayViewX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
            overlayViewY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
            layout := this._ViewLayout(overlayZoom)
            for point in points {
                marker := this._PointMarkerBounds(point, layout, overlayViewX, overlayViewY)
                if (marker.x + marker.w < 0 || marker.y + marker.h < 0
                    || marker.x > this.CanvasSide || marker.y > this.CanvasSide)
                    continue
                brush := seeds.Has(point.X "," point.Y) ? seedBrush : autoBrush
                Gdip_FillRectangle(graphics, brush, marker.x, marker.y, marker.w, marker.h)
                if (marker.w >= 3 && marker.h >= 3)
                    Gdip_DrawRectangle(graphics, outlinePen, marker.x + 0.5, marker.y + 0.5
                        , marker.w - 1, marker.h - 1)
            }

            if (Gdip_SaveBitmapToFile(bitmap, output) != 0) {
                try FileDelete(output)
                return ""
            }
            return output
        } catch {
            try FileDelete(output)
            return ""
        } finally {
            if (outlinePen)
                try Gdip_DeletePen(outlinePen)
            if (autoBrush)
                try Gdip_DeleteBrush(autoBrush)
            if (seedBrush)
                try Gdip_DeleteBrush(seedBrush)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (bitmap)
                try Gdip_DisposeImage(bitmap)
        }
    }

    _PointMarkerBounds(point, layout, viewX := "", viewY := "") {
        if (viewX == "")
            viewX := this.ViewX
        if (viewY == "")
            viewY := this.ViewY
        cellX := layout.offsetX + (point.X - viewX) * layout.zoom
        cellY := layout.offsetY + (point.Y - viewY) * layout.zoom
        size := layout.zoom
        if (size < 1) {
            size := 6
            cellX += layout.zoom / 2 - size / 2
            cellY += layout.zoom / 2 - size / 2
        }
        return { x: cellX, y: cellY, w: size, h: size }
    }

    _RefreshIgnoreOverlay() {
        if (!IsObject(this.ui))
            return
        if (this._rendering) {
            this._ignoreOverlayRefreshPending := true
            return
        }
        try this.ui.Update("IgnoreOverlayImg", "Visibility", this.ShowRightPointOverlay ? "Visible" : "Collapsed")
        if (this.EditorMode != "super" || this.OrigW <= 0
            || (this.IgnoreOps.Length == 0 && !IsObject(this.IgnoreCurrentOp))) {
            this._SetIgnoreOverlaySource("")
            return
        }
        overlayPath := this._CreateIgnoreOverlay()
        this._SetIgnoreOverlaySource(overlayPath)
    }

    _CreateModeIgnoreOverlay() {
        if (this.EditorMode != "super" || this.OrigW <= 0
            || (this.IgnoreOps.Length == 0 && !IsObject(this.IgnoreCurrentOp)))
            return ""
        return this._CreateIgnoreOverlay()
    }

    _CreateIgnoreOverlay() {
        this._ignoreOverlaySeq += 1
        output := A_Temp "\RMT_fe_ignore_" A_TickCount "_" this._windowToken "_" this._ignoreOverlaySeq ".png"
        bitmap := 0, graphics := 0, maskBrush := 0, clearBrush := 0
        try {
            bitmap := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!bitmap)
                return ""
            graphics := Gdip_GraphicsFromImage(bitmap)
            if (!graphics)
                return ""
            maskBrush := Gdip_BrushCreateSolid(0x90F04444)
            clearBrush := Gdip_BrushCreateSolid(0x00000000)
            if (!maskBrush || !clearBrush)
                return ""
            Gdip_GraphicsClear(graphics, 0x00000000)
            Gdip_SetSmoothingMode(graphics, 0)

            overlayZoom := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
            overlayViewX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
            overlayViewY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
            layout := this._ViewLayout(overlayZoom)
            for operation in this.IgnoreOps
                this._DrawIgnoreOperation(graphics, maskBrush, clearBrush
                    , operation, layout, overlayViewX, overlayViewY)
            if (IsObject(this.IgnoreCurrentOp))
                this._DrawIgnoreOperation(graphics, maskBrush, clearBrush
                    , this.IgnoreCurrentOp, layout, overlayViewX, overlayViewY)

            if (Gdip_SaveBitmapToFile(bitmap, output) != 0) {
                try FileDelete(output)
                return ""
            }
            return output
        } catch {
            try FileDelete(output)
            return ""
        } finally {
            if (clearBrush)
                try Gdip_DeleteBrush(clearBrush)
            if (maskBrush)
                try Gdip_DeleteBrush(maskBrush)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (bitmap)
                try Gdip_DisposeImage(bitmap)
        }
    }

    _DrawIgnoreOperation(graphics, maskBrush, clearBrush, operation, layout, viewX, viewY) {
        points := operation.points
        if (!IsObject(points) || points.Length == 0)
            return
        brush := operation.erase ? clearBrush : maskBrush
        Gdip_SetCompositingMode(graphics, 1)
        loop points.Length {
            point := points[A_Index]
            x1 := point.x - Floor((operation.size - 1) / 2)
            y1 := point.y - Floor((operation.size - 1) / 2)
            x2 := x1 + operation.size
            y2 := y1 + operation.size
            left := Round(layout.offsetX + (x1 - viewX) * layout.zoom)
            top := Round(layout.offsetY + (y1 - viewY) * layout.zoom)
            right := Round(layout.offsetX + (x2 - viewX) * layout.zoom)
            bottom := Round(layout.offsetY + (y2 - viewY) * layout.zoom)
            if (right <= 0 || bottom <= 0 || left >= this.CanvasSide || top >= this.CanvasSide)
                continue
            Gdip_FillRectangle(graphics, brush, left, top
                , Max(1, right - left), Max(1, bottom - top))
        }
        Gdip_SetCompositingMode(graphics, 0)
    }

    _SetIgnoreOverlaySource(path) {
        oldOverlay := this._lastIgnoreOverlay
        this._lastIgnoreOverlay := path
        source := path == "" ? "" : StrReplace(path, "\", "/")
        try this.ui.Update("IgnoreOverlayImg", "Source", source)
        if (oldOverlay != path)
            try FileDelete(oldOverlay)
    }

    _FlushIgnoreOverlay(*) {
        this._RefreshIgnoreOverlay()
    }

    _CancelIgnoreOverlay() {
        try SetTimer(this._ignoreOverlayTimer, 0)
    }

    OnPointOverlayVisibility(side, isVisible, *) {
        if (side == "L") {
            this.ShowLeftPointOverlay := isVisible
            try this.ui.Update("PointOverlayImg", "Visibility", isVisible ? "Visible" : "Collapsed")
        } else {
            this.ShowRightPointOverlay := isVisible
            try this.ui.Update("RightPointOverlayImg", "Visibility", isVisible ? "Visible" : "Collapsed")
            try this.ui.Update("IgnoreOverlayImg", "Visibility", isVisible ? "Visible" : "Collapsed")
        }
    }

    _RefreshProcessControls() {
        if (!IsObject(this.ui))
            return
        activeSeeds := this.EditorMode == "super" ? this.SuperSeedPoints : this.SeedPoints
        try this.ui.Update("PointCountLabelCon", "Text", GetLang("基准色："))
        try this.ui.Update("SeedCountCon", "Text", Format(GetLang("{} 个颜色"), activeSeeds.Length))
        try this.ui.Update("PointCountCon", "Text", Format(GetLang("{} 个"), this.Points.Length))
    }

    _SyncMatchModeUi() {
        if (!IsObject(this.ui))
            return
        for name, active in Map(
            "BtnModeOriginal", this.EditorMode == "original",
            "BtnModeMultiPoint", this.EditorMode == "multi",
            "BtnModeSuperMultiPoint", this.EditorMode == "super") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
        isMatchMode := this.EditorMode != "original"
        isSeedMode := this.EditorMode == "super"
        try this.ui.Update("OriginalToolsCon", "Visibility", this.EditorMode == "original" ? "Visible" : "Collapsed")
        try this.ui.Update("MatchControlsCon", "Visibility", isMatchMode ? "Visible" : "Collapsed")
        try this.ui.Update("ShowLeftOverlayCon", "Visibility", isMatchMode ? "Visible" : "Collapsed")
        try this.ui.Update("ShowRightOverlayCon", "Visibility", isMatchMode ? "Visible" : "Collapsed")
        try this.ui.Update("RightPreviewToolsCon", "Visibility", isSeedMode ? "Visible" : "Collapsed")
        try this.ui.Update("MultiPointEditToolsCon", "Visibility", this.EditorMode == "multi" ? "Visible" : "Collapsed")
        try this.ui.Update("AutoPointsCon", "Visibility", this.EditorMode == "multi" ? "Visible" : "Collapsed")
        try this.ui.Update("TolLabelCon", "Text", GetLang(isSeedMode ? "基准色容差：" : "点位容差："))
        this._SyncPointToolControls()
        this._SyncIgnoreControls()
        this._RefreshProcessControls()
    }

    _SyncPointToolControls() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("BtnMultiSeedTool", "Visibility", this.EditorMode == "multi" ? "Visible" : "Collapsed")
        try this.ui.Update("BtnSuperSeedTool", "Visibility", this.EditorMode == "super" ? "Visible" : "Collapsed")
        for name, active in Map(
            "BtnMultiSeedTool", this.EditorMode == "multi" && this.PointTool == "seed",
            "BtnMultiPointTool", this.EditorMode == "multi" && this.PointTool == "point",
            "BtnSuperSeedTool", this.EditorMode == "super" && this.PointTool == "seed") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
    }

    OnPointTool(requestedTool, *) {
        if (this.EditorMode != "multi" && this.EditorMode != "super")
            return
        if (this.EditorMode == "super" && requestedTool != "seed")
            return
        this.PointTool := this.PointTool == requestedTool ? "" : requestedTool
        this._SyncPointToolControls()
    }

    _SyncIgnoreControls() {
        if (!IsObject(this.ui))
            return
        visible := this.EditorMode == "super" ? "Visible" : "Collapsed"
        for name in ["BtnIgnoreBrush", "BtnIgnoreEraser"
            , "BtnIgnoreSize1", "BtnIgnoreSize2", "BtnIgnoreSize3"
            , "BtnIgnoreUndo", "BtnIgnoreClear", "IgnoreSizeLabelCon"] {
            try this.ui.Update(name, "Visibility", visible)
        }
        for name, active in Map(
            "BtnIgnoreBrush", this.IgnoreTool == "brush",
            "BtnIgnoreEraser", this.IgnoreTool == "eraser",
            "BtnIgnoreSize1", this.IgnoreBrushSize == 1,
            "BtnIgnoreSize2", this.IgnoreBrushSize == 2,
            "BtnIgnoreSize3", this.IgnoreBrushSize == 3) {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
        try this.ui.Update("BtnIgnoreUndo", "IsEnabled", this.IgnoreUndo.Length > 0 ? "True" : "False")
        try this.ui.Update("BtnIgnoreClear", "IsEnabled", this.IgnoreOps.Length > 0 ? "True" : "False")
    }

    OnMatchMode(requestedMode, *) {
        if (requestedMode == "original") {
            if (this.EditorMode == "super")
                this.SuperTolerance := this.Tol
            else if (this.EditorMode == "multi")
                this.NormalTolerance := this.Tol
            if (this.IgnoreDragging)
                this._FinishIgnoreStroke()
            this.MatchMode := ""
            this.EditorMode := "original"
            this.PointTool := ""
            this.Mode := ""
            this._ClearSelection()
            this.Tol := this.NormalTolerance
            try this.ui.Update("TolCon", "Text", String(this.Tol))
            try this.ui.Update("TolSlider", "Value", this.Tol)
            this._ApplyModeStyle()
            this._SyncMatchModeUi()
            this._Render()
            return
        }

        if (this.EditorMode == "super")
            this.SuperTolerance := this.Tol
        else if (this.EditorMode == "multi")
            this.NormalTolerance := this.Tol
        this.MatchMode := this.MatchMode == requestedMode ? "" : requestedMode
        this.EditorMode := this.MatchMode == "" ? "original" : this.MatchMode
        this.PointTool := ""
        if (this.MatchMode != "super") {
            if (this.IgnoreDragging)
                this._FinishIgnoreStroke()
            SetTimer(this._ignoreStrokeTimer, 0)
            this.IgnoreTool := ""
            this.IgnoreDragging := false
            this.IgnoreCurrentOp := ""
        }
        this.Tol := requestedMode == "super" ? this.SuperTolerance : this.NormalTolerance
        try this.ui.Update("TolCon", "Text", String(this.Tol))
        try this.ui.Update("TolSlider", "Value", this.Tol)
        this._SyncMatchModeUi()
        this._Render()
    }

    _UpdateStatus(info := "") {
        if (!IsObject(this.ui))
            return
        width := IsObject(info) && info.HasOwnProp("ow") ? info.ow : this.OrigW
        height := IsObject(info) && info.HasOwnProp("oh") ? info.oh : this.OrigH
        if (this.EditorMode == "original")
            this._SetOriginalStatus(width, height)
        else
            this._SetModeStatus("")
    }

    _SetModeStatus(text) {
        if (this.EditorMode == "original") {
            try this.ui.Update("OriginalStatCon", "Text", text)
            for control in ["NewSizeStatCon", "SelectionPositionStatCon"] {
                try this.ui.Update(control, "Text", "")
                try this.ui.Update(control, "Visibility", "Collapsed")
            }
            return
        }
        try this.ui.Update("MatchStatCon", "Text", text)
        try this.ui.Update("MatchStatCon", "Visibility", text == "" ? "Collapsed" : "Visible")
    }

    _SetOriginalStatus(width, height) {
        if (!IsObject(this.ui))
            return
        hasSelection := this.SelW > 0 && this.SelH > 0
        try this.ui.Update("OriginalStatCon", "Text"
            , Format("{}  {}x{}", GetLang("原图"), width, height))
        try this.ui.Update("NewSizeStatCon", "Text"
            , hasSelection ? Format("{}  {}x{}", GetLang("新图"), this.SelW, this.SelH) : "")
        try this.ui.Update("NewSizeStatCon", "Visibility", hasSelection ? "Visible" : "Collapsed")
        try this.ui.Update("SelectionPositionStatCon", "Text"
            , hasSelection ? Format("·  @ ({},{})", this.SelX, this.SelY) : "")
        try this.ui.Update("SelectionPositionStatCon", "Visibility", hasSelection ? "Visible" : "Collapsed")
    }

    OnToggleCrop(*) {
        this.Mode := (this.Mode == "crop") ? "" : "crop"
        this._ClearSelection()
        this._ApplyModeStyle()
        this._Render()
    }

    _ClearSelection() {
        this.Resizing := ""
        this.Dragging := false
        this.DragMoved := false
        this.SelX := 0
        this.SelY := 0
        this.SelW := 0
        this.SelH := 0
        if (IsObject(this.ui))
            try this.ui.Update("BtnApply", "IsEnabled", "False")
    }

    _ApplyModeStyle() {
        if (!IsObject(this.ui))
            return
        for name, active in Map("BtnCrop", this.Mode == "crop") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
    }

    OnAutoSelectPoints(*) {
        if (!IsObject(this.ui))
            return
        if (this.SeedPoints.Length < 1) {
            RmtDialog.Info(GetLang("自动选点前请先选择一个点"), GetLang("多点找图"))
            return
        }

        toleranceText := String(this.ui.Query("TolCon>Text"))
        if (!RegExMatch(toleranceText, "^\d+$")) {
            RmtDialog.Info(GetLang("点位容差必须是整数"), GetLang("多点找图"))
            return
        }

        density := this.AutoPointDensity
        tolerance := Min(255, Max(0, Integer(toleranceText)))
        this.AutoPointDensity := density
        this.Tol := tolerance
        try this.ui.Update("DensitySlider", "Value", density)
        try this.ui.Update("TolCon", "Text", String(tolerance))
        try this.ui.Update("TolSlider", "Value", tolerance)

        if (!AutoSelectPointsApiReady()) {
            RmtDialog.Info(GetLang("当前 OpenCV 插件不支持自动选点"), GetLang("多点找图"))
            return
        }
        existing := this._MultiPointText(this.SeedPoints)
        output := Buffer(16384, 0)
        ret := 0
        try ret := DllCall("RMT_OpenCV.dll\AutoSelectImageMultiPoints", "Str", this.TemplatePath
            , "Str", existing, "Int", density, "Int", tolerance
            , "Str", ""
            , "Ptr", output.Ptr, "Int", output.Size // 2, "CDecl Int")
        catch {
            RmtDialog.Info(GetLang("自动选点失败"), GetLang("多点找图"))
            return
        }
        if (ret < 0) {
            err := GetImageLastErrorText()
            RmtDialog.Info(err != "" ? err : GetLang("自动选点失败"), GetLang("多点找图"))
            return
        }

        selectedText := StrGet(output, "UTF-16")
        selected := this._ParseMultiPointText(selectedText)
        if (selected.Length < 1) {
            RmtDialog.Info(GetLang("自动选点没有得到有效点位"), GetLang("多点找图"))
            return
        }
        this.Points := selected
        this._Render()
        this._SetStatus(Format(GetLang("自动选出 {} 个点（密集度 {}）"), selected.Length, density))
    }

    _MultiPointText(points := "") {
        if (!IsObject(points))
            points := this.Points
        text := ""
        for point in points
            text .= (text == "" ? "" : ";") Integer(point.X) "," Integer(point.Y) "," StrUpper(point.Color)
        return text
    }

    _ParseMultiPointText(text) {
        points := []
        for token in StrSplit(text, ";") {
            parts := StrSplit(token, ",")
            if (parts.Length != 3 || !RegExMatch(parts[1], "^\d+$")
                || !RegExMatch(parts[2], "^\d+$") || !RegExMatch(parts[3], "i)^[0-9A-F]{6}$"))
                return []
            points.Push({X: Integer(parts[1]), Y: Integer(parts[2]), Color: StrUpper(parts[3])})
        }
        return points
    }

    _SetStatus(text) {
        this._SetModeStatus(text)
    }

    OnTolSlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("TolSlider")) ? state["TolSlider"] : ""
        if (!IsNumber(v))
            return
        tolerance := Min(255, Max(0, Integer(v)))
        if (tolerance == this.Tol)
            return
        this.Tol := tolerance
        if (this.EditorMode == "super")
            this.SuperTolerance := tolerance
        else if (this.EditorMode == "multi")
            this.NormalTolerance := tolerance
        try this.ui.Update("TolCon", "Text", String(this.Tol))
        this._ScheduleToleranceRender()
    }

    OnTolTextChanged(*) {
        if (!IsObject(this.ui))
            return
        text := String(this.ui.Query("TolCon>Text"))
        if (!RegExMatch(text, "^\d+$"))
            return
        tolerance := Min(255, Max(0, Integer(text)))
        if (tolerance == this.Tol)
            return
        this.Tol := tolerance
        if (this.EditorMode == "super")
            this.SuperTolerance := tolerance
        else if (this.EditorMode == "multi")
            this.NormalTolerance := tolerance
        if (text != String(tolerance))
            try this.ui.Update("TolCon", "Text", String(tolerance))
        try this.ui.Update("TolSlider", "Value", tolerance)
        this._ScheduleToleranceRender()
    }

    _ScheduleToleranceRender() {
        try SetTimer(this._toleranceRenderTimer, -80)
    }

    _FlushToleranceRender(*) {
        if (IsObject(this.ui))
            this._Render()
    }

    _CancelToleranceRender() {
        try SetTimer(this._toleranceRenderTimer, 0)
    }

    OnClearPoints(*) {
        if (this.EditorMode == "multi") {
            this.Points := []
            this.SeedPoints := []
        } else if (this.EditorMode == "super") {
            this.SuperSeedPoints := []
        } else {
            return
        }
        this.MatchMode := ""
        this._Render()
    }

    OnDensitySlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("DensitySlider")) ? state["DensitySlider"] : ""
        if (!IsNumber(v))
            return
        this.AutoPointDensity := Min(100, Max(0, Integer(v)))
        try this.ui.Update("DensityValueCon", "Text", String(this.AutoPointDensity) "%")
    }

    ; ------------------------------------------------------------------
    ; 裁剪 / 重命名
    ; ------------------------------------------------------------------
    OnApplyCrop(*) {
        if (this.SelW < 2 || this.SelH < 2)
            return
        src := this.TemplatePath
        tmp := A_Temp "\RMT_crop_tmp.png"
        try FileDelete(tmp)
        ret := DllCall("RMT_OpenCV.dll\CropImageFile", "Str", src
            , "Int", this.SelX, "Int", this.SelY, "Int", this.SelW, "Int", this.SelH
            , "Str", tmp, "CDecl Int")
        if (ret != 1) {
            RmtDialog.Info(GetLang("裁剪失败"), GetLang("图片处理"))
            return
        }

        target := src
        ext := this._Ext(src)
        if (StrLower(ext) != ".png") {
            SplitPath(src, , &dir, , &nameNoExt)
            target := dir "\" nameNoExt ".png"
        }
        ; 先让预览和父窗口释放源文件，再删除/覆盖文件，避免 WPF 句柄导致裁剪失败。
        keptPoints := []
        keptSeeds := []
        keptSuperSeeds := []
        for point in this.Points {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptPoints.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        for point in this.SeedPoints {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptSeeds.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        for point in this.SuperSeedPoints {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptSuperSeeds.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        shiftedIgnoreOps := this._OffsetIgnoreOps(this.SelX, this.SelY)
        this._ReleaseFile()
        if (!this._MoveWithRetry(tmp, target)) {
            RmtDialog.Info(GetLang("覆盖原图失败：文件可能被占用"), GetLang("图片处理"))
            return
        }
        if (target != src)
            try FileDelete(src)

        this.TemplatePath := target
        this.Points := keptPoints
        this.SeedPoints := keptSeeds
        this.SuperSeedPoints := keptSuperSeeds
        this.IgnoreOps := shiftedIgnoreOps
        this.SuperIgnoreData := this._SerializeIgnoreData(this.IgnoreOps)
        if ((this.MatchMode == "multi" && this.Points.Length < 1)
            || (this.MatchMode == "super" && this.SuperSeedPoints.Length < 1)) {
            this.MatchMode := ""
            this.EditorMode := "original"
        }
        this.Tol := this.EditorMode == "super" ? this.SuperTolerance : this.NormalTolerance
        this.Zoom := 0
        this.OrigW := 0
        this.OrigH := 0
        this._ResetInteraction()
        this._SyncControls()
        this._ApplyModeStyle()
        this._SyncMatchModeUi()
        this._Render()

        action := this.CropAction
        if (action != "")
            action(target, this.Points, this.SeedPoints, this.SuperSeedPoints, this.SuperIgnoreData)
    }

    _OffsetIgnoreOps(offsetX, offsetY) {
        shifted := []
        for operation in this.IgnoreOps {
            points := []
            for point in operation.points
                points.Push({ x: point.x - offsetX, y: point.y - offsetY })
            shifted.Push({
                type: "stroke", erase: operation.erase, size: operation.size, points: points
            })
        }
        return shifted
    }

    OnRename(*) {
        name := Trim(String(this.ui.Query("NameCon>Text")))
        if (name == "" || this.TemplatePath == "")
            return
        SplitPath(this.TemplatePath, , &dir)
        ext := this._Ext(this.TemplatePath)
        name := this._StripExt(name)

        for bad in ["\", "/", ":", "*", "?", Chr(34), "<", ">", "|"]
            name := StrReplace(name, bad, "_")
        if (Trim(name) == "")
            return

        newPath := dir "\" name ext
        if (newPath == this.TemplatePath)
            return
        if FileExist(newPath) {
            RmtDialog.Info(GetLang("同名文件已存在"), GetLang("图片处理"))
            return
        }
        this._ReleaseFile()
        if (!this._MoveWithRetry(this.TemplatePath, newPath)) {
            RmtDialog.Info(GetLang("重命名失败：文件可能被占用"), GetLang("图片处理"))
            return
        }
        this.TemplatePath := newPath
        this._SyncControls()
        this._Render()

        action := this.CropAction
        if (action != "")
            action(newPath, this.Points, this.SeedPoints, this.SuperSeedPoints, this.SuperIgnoreData)
    }

    ; 让父窗口的缩略图先松开文件（WPF 的 Image.Source 会占用句柄）
    _ReleaseFile() {
        this._ReleasePreviewImages()
        action := this.ReleaseAction
        if (action != "")
            action()
        Sleep 80
    }

    ; 清空编辑器图片源，释放预览文件并避免显示占位图。
    _ReleasePreviewImages() {
        this._CancelToleranceRender()
        this._CancelIgnoreOverlay()
        try SetTimer(this._ignoreStrokeTimer, 0)
        this._rendering := false
        this._ignoreOverlayRefreshPending := false
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this._ResetPreviewTransform()
        if (!IsObject(this.ui))
            return
        try this.ui.Update("LeftImg", "Source", "")
        try this.ui.Update("RightImg", "Source", "")
        try this.ui.Update("PointOverlayImg", "Source", "")
        try this.ui.Update("RightPointOverlayImg", "Source", "")
        try this.ui.Update("IgnoreOverlayImg", "Source", "")
        oldLeftOverlay := this._lastLeftOverlay
        this._lastLeftOverlay := ""
        try FileDelete(oldLeftOverlay)
        oldRightOverlay := this._lastRightOverlay
        this._lastRightOverlay := ""
        try FileDelete(oldRightOverlay)
        oldIgnoreOverlay := this._lastIgnoreOverlay
        this._lastIgnoreOverlay := ""
        try FileDelete(oldIgnoreOverlay)
    }

    ; 移动/覆盖：失败重试几次（句柄释放有延迟）
    _MoveWithRetry(src, dst, tries := 5) {
        loop tries {
            try {
                FileMove(src, dst, true)
                return true
            } catch {
                Sleep 120
            }
        }
        return false
    }

    _StripExt(name) {
        return RegExReplace(name, "\.\w{1,5}$", "")
    }

    ; ------------------------------------------------------------------
    ; 收尾
    ; ------------------------------------------------------------------
    OnSure(*) {
        this._Commit()
        this._Close()
    }

    ; 回写当前值：点【确定】或直接关窗口都算确认
    _Commit() {
        if (!IsObject(this.ui) || this._committed)
            return
        v := String(this.ui.Query("TolCon>Text"))
        if (IsNumber(v))
            this.Tol := Min(255, Max(0, Integer(v)))
        if (this.EditorMode == "super")
            this.SuperTolerance := this.Tol
        else if (this.EditorMode == "multi")
            this.NormalTolerance := this.Tol
        this._committed := true
        if ((this.MatchMode == "multi" && this.Points.Length < 1)
            || (this.MatchMode == "super" && this.SuperSeedPoints.Length < 1))
            this.MatchMode := ""
        actionTol := this.NormalTolerance
        action := this.SureAction
        if (action != "")
            action(this.Points, this.SeedPoints, actionTol, this.MatchMode
                , this.SuperSeedPoints, this.SuperTolerance, this.SuperIgnoreData)
    }

    OnCancel(*) {
        this._Close()
    }

    OnWindowClosing(windowToken, state, ctrl, event) {
        if (windowToken != this._windowToken)
            return
        ; 用 X 关窗口也算确认，别把选好的颜色丢掉
        try this._Commit()
        this._UnbindWheel()
        this._ReleasePreviewImages()
        try FileDelete(this._lastOrig)
        try FileDelete(this._lastEff)
        this._lastOrig := ""
        this._lastEff := ""
        this._ResetInteraction()
        this._RestoreOwner()
        this.ui := ""
    }

    _Close() {
        this._UnbindWheel()
        this._ReleasePreviewImages()
        if (IsObject(this.ui))
            try this.ui.Update("Window", "Close", "")
        this.ui := ""
        try FileDelete(this._lastOrig)
        try FileDelete(this._lastEff)
        this._lastOrig := ""
        this._lastEff := ""
        this._ResetInteraction()
        this._RestoreOwner()
    }

    _DisableOwner() {
        if (this._ownerDisabled || !this.OwnerHwnd || !MainSoftData.IsModalSubGui)
            return
        try {
            SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            this._ownerDisabled := true
        }
    }

    _RestoreOwner() {
        if (!this._ownerDisabled)
            return
        this._ownerDisabled := false
        try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
    }
}
