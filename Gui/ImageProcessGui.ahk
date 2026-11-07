#Requires AutoHotkey v2.0

; ===========================================================================
; 多点找图与模板图片处理—— XAML 版
;
; 用途：选取多点找图的基准点、自动补点，并裁剪 / 抠除 / 重命名模板。
;   布局：左栏参数、中栏画布（单画布）、右栏效果图与图片信息。
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
        this.ImageSelectAction := ""

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
        this.IgnoreTool := ""
        this.IgnoreBrushSize := 1
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this.AutoPointDensity := 50

        ; ---- 原图页工具状态机：idle / crop / erase ----
        this.OriginalTool := ""          ; "" / "crop" / "erase"（工具条是否出现）
        this.PointUndo := []             ; 多点页点位撤销快照
        this.SuperEntryChecked := false  ; 勾选框【超多点】的状态（进多点页时沿用）
        this._renderBusy := false        ; 渲染重入保护
        this._renderAgain := false       ; 渲染期间又有请求 → 结束后补渲
        this._thumbBusy := false         ; 缩略图渲染中（临时改 CanvasSide）
        this._selApplyShown := false     ; 裁剪 ✓ 当前是否已显示
        this._modeInfoText := ""         ; 右栏匹配方式提示（避免重复 Update）
        this.SampleMode := false
        this.SampleFrames := []          ; OffX/OffY 为样本原点在基准图中的坐标
        this.SampleThreshold := 12
        this.SampleFixedPos := false     ; 固定位置截屏
        this.SampleShotRect := ""        ; 固定区域 {x,y,w,h}
        this._samplePickRect := ""       ; 本次框选的矩形（薄回调 → 延迟处理）
        this.SamplePreviewPath := ""
        this.SamplePreviewSig := ""
        this._samplePreviewFailedSig := ""
        this._sampleAlignmentEffectFrame := 0
        this._sampleReadyPreviewBitmap := 0
        this._sampleReadyPreviewSession := -1
        this._sampleReadyPreviewRevision := -1
        this._sampleReadyPreviewThreshold := -1
        this._samplePending := false
        this._sampleTimer := ObjBindMethod(this, "_SampleFlushThreshold")
        this._sampleAlignTimer := ObjBindMethod(this, "_SampleAlignPending")
        this._sampleBusy := false
        this._sampleDirty := false
        this._sampleAlignScheduled := false
        this._sampleComputing := false
        this._sampleShotBusy := false
        this._sampleImportBusy := false
        this._sampleQueuedFrames := []
        this._samplePairCache := Map()
        this._sampleEdgeCache := Map()
        this._sampleEdgeCacheBytes := 0
        this._sampleEdgeCacheTick := 0
        this._sampleEdgeCacheHits := 0
        this._sampleEdgeCacheBuilds := 0
        this._sampleNativeAlignmentModules := Map()
        this._sampleAlignWorkers := []
        this._sampleWorkerDir := ""
        this._sampleWorkerRoot := A_ScriptDir
        this._sampleJobSeq := 0
        this._sampleAlignmentStats := 0
        this._sampleSession := 0
        this._sampleRevision := 0
        this._sampleSeq := 0
        this._sampleTemp := []
        this._sampleGarbage := []
        this._sampleShotAction := ObjBindMethod(this, "_SampleAreaPicked")
        this.CropDrag := ""              ; 裁剪拖拽状态 {mode, startImgX, startImgY, origX, origY}
        this._NameBase := ""             ; 当前文件名（不含扩展名），用于判断是否改动
        this._cropCursor := ""           ; 裁剪模式当前光标（避免重复设置）

        ; ---- 背景擦除（原图页）：涂抹，输出透明 PNG ----
        this.EraseOps := []              ; 每笔：{type:"stroke", size, points[]}
        this.EraseTool := ""             ; "" / "brush"
        this.EraseBrushSize := 8         ; 笔刷直径（原图像素）
        this.EraseDragging := false
        this.EraseCurrentOp := ""
        this._eraseOverlaySeq := 0
        this._selOverlaySeq := 0
        this._lastSelOverlay := ""
        this._ptsSeq := 0
        this._thumbTimer := ObjBindMethod(this, "_FlushThumb")
        this._eraseStrokeTimer := ObjBindMethod(this, "_PollEraseStroke")
        this._eraseOverlayTimer := ObjBindMethod(this, "_FlushEraseOverlay")
        this.MatchMode := ""
        this.EditorMode := "original"
        this.PointTool := ""
        this.ViewMode := "edit"         ; edit / effective

        this.CanvasSide := 420          ; 画布边长（物理像素）
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
        this._lastRightOverlay := ""
        this._lastMasked := ""
        this._lastThumb := ""
        this._lastIgnoreOverlay := ""
        this._infoSig := ""
    }

    ; ------------------------------------------------------------------
    ; 对外入口
    ; ------------------------------------------------------------------
    ShowGui(path, points := "", seedPoints := "", tol := 8, matchMode := ""
        , superSeedPoints := "", superTol := 8, superIgnoreData := "") {
        this._SampleCleanupTemp()
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
        this.IgnoreTool := ""
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this.MatchMode := matchMode == "super" && this.SuperSeedPoints.Length > 0
            ? "super" : (matchMode == "multi" && this.Points.Length > 0 ? "multi" : "")
        this.EditorMode := this.MatchMode == "" ? "original" : this.MatchMode
        this.PointTool := ""
        this.OriginalTool := ""
        this.PointUndo := []
        this.SuperEntryChecked := this.MatchMode == "super"
        this._infoSig := ""
        this._modeInfoText := ""      ; 窗口重建后控件是空的，缓存必须失效
        this._selApplyShown := false
        this.SampleMode := false
        this.SampleFixedPos := false
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
        contentInset := 17

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "44", "*")

        XAMLHost.AddTitleBar(main, title, titleHeight)

        ; ---- 工具栏 ----
        bar := main.Add("StackPanel").Grid_Row(1).Orientation("Horizontal")
            .VerticalAlignment("Center").Margin(contentInset ",0," contentInset ",0")

        this._AddBtn(bar, "BtnModeOriginal", GetLang("原图"), 64)
        this._AddBtn(bar, "BtnModeMultiPoint", GetLang("多点"), 64)
        bar.Add("Button").Name("BtnHelp").Content("?")
            .Width(24).Height(24).MinWidth(24).MinHeight(24).MaxWidth(24).MaxHeight(24)
            .Padding("0").Margin("10,0,0,0").FontSize("11").Cursor("Hand")
            .VerticalAlignment("Center").HorizontalAlignment("Center")
            .ToolTip(GetLang("图片处理说明"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; ---- 三栏骨架：每栏一张圆角卡片，靠左排；原图页收起左栏内容后右侧留白（按草图）----
        prev := main.Add("Grid").Grid_Row(2).Margin("17,10,17,12")
        prev.Cols("Auto", this.CanvasSide + 14, "12", "174", "*")

        ; ---- 左栏卡片：区块标题 + 控件；匹配页=选点参数，原图页=文件与图片编辑 ----
        leftCard := prev.Add("Border").Grid_Column(0).Name("LeftPanelCon").Width(224)
            .Margin("0,0,12,0").VerticalAlignment("Stretch")
            .CornerRadius("10").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        leftGrid := leftCard.Add("Grid").Margin("12,10,12,12")
        leftGrid.Rows("*", "Auto")
        leftGrid.Cols("*")
        panelsHost := leftGrid.Add("StackPanel").Grid_Row(0).Orientation("Vertical")

        ; ===== 匹配页（多点 / 按色自动）=====
        matchPanel := panelsHost.Add("StackPanel").Name("MatchControlsCon").Orientation("Vertical")

        ; 勾选【超多点】= 按色自动；不勾 = 手工点。（勾选框放在面板底部，见下）

        this._AddSection(matchPanel, GetLang("基准色"))
        seedRow := matchPanel.Add("Grid").Height(30).Margin("0,0,0,2")
        seedRow.Cols("64", "*", "32")
        seedRow.Add("TextBlock").Grid_Column(0).Text(GetLang("基准点")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        seedActions := seedRow.Add("StackPanel").Grid_Column(1).Grid_ColumnSpan(2)
            .Orientation("Horizontal").VerticalAlignment("Center")
        this._AddCrosshairBtn(seedActions, "BtnMultiSeedTool"
            , GetLang("点击图片选取基准颜色"))
        this._AddCrosshairBtn(seedActions, "BtnSuperSeedTool"
            , GetLang("点击图片选取基准颜色"))

        tolRow := matchPanel.Add("Grid").Height(30).Margin("0,0,0,2")
        tolRow.Cols("64", "*", "32")
        tolRow.Add("TextBlock").Grid_Column(0).Text(GetLang("容差")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        tolRow.Add("Slider").Grid_Column(1).Name("TolSlider")
            .VerticalAlignment("Center").Margin("0,0,6,0").Minimum(0).Maximum(255).Value(this.Tol)
            .ToolTip(GetLang("容差越高，可接受色差越大，也更易误匹配"))
        tolRow.Add("TextBlock").Grid_Column(2).Name("TolCon").Text(String(this.Tol))
            .FontSize("11").TextAlignment("Center").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")

        autoHost := matchPanel.Add("StackPanel").Name("AutoPointsCon").Orientation("Vertical")
        densityRow := autoHost.Add("Grid").Height(30).Margin("0,0,0,2")
        densityRow.Cols("64", "*", "32")
        densityRow.Add("TextBlock").Grid_Column(0).Text(GetLang("密集度")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        densityRow.Add("Slider").Grid_Column(1).Name("DensitySlider")
            .VerticalAlignment("Center").Margin("0,0,6,0").Minimum(0).Maximum(100).Value(this.AutoPointDensity)
            .ToolTip(GetLang("调节自动选点的覆盖密度"))
        densityRow.Add("TextBlock").Grid_Column(2).Name("DensityValueCon")
            .Text(String(this.AutoPointDensity)).FontSize("11").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        autoBtnHost := autoHost.Add("Grid").Height(30).Margin("0,0,0,2")
        this._AddBtn(autoBtnHost, "BtnAutoPoints", GetLang("自动补点"), 96
            , GetLang("按基准点和容差自动补点")).HorizontalAlignment("Right").Margin("0")

        this._AddSection(matchPanel, GetLang("工具栏"))
        toolRowL := matchPanel.Add("Grid").Name("MatchToolRowCon").Height(30).Margin("0,0,0,2")
        toolRowL.Cols("64", "Auto", "*")
        toolRowL.Add("TextBlock").Grid_Column(0).Name("ToolLabelCon").Text(GetLang("点位修改"))
            .FontSize("12").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        multiTools := toolRowL.Add("StackPanel").Grid_Column(1).Name("MultiPointEditToolsCon")
            .Orientation("Horizontal").VerticalAlignment("Center")
        this._AddIconBtn(multiTools, "BtnMultiPointTool", "✎"
            , GetLang("添加或移除匹配点")).Margin("0")
        superTools := toolRowL.Add("StackPanel").Grid_Column(1).Name("RightPreviewToolsCon")
            .Orientation("Horizontal").VerticalAlignment("Center").Visibility("Collapsed")
        this._AddIconBtn(superTools, "BtnIgnoreBrush", "✎"
            , GetLang("标记不参与匹配的区域")).Margin("0,0,4,0")
        this._AddIconBtn(superTools, "BtnIgnoreEraser", Chr(0xE75C)
            , GetLang("恢复被忽略的区域")).Margin("0")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")

        ; 画笔大小浮窗：点画笔 / 橡皮后在其下方出现
        brushSizePop := matchPanel.Add("Border").Name("BrushSizePopCon").Margin("64,6,0,0")
            .Padding("8,6").CornerRadius("6").HorizontalAlignment("Stretch")
            .Background("{DynamicResource BgColor}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Visibility("Collapsed")
        popGrid2 := brushSizePop.Add("Grid")
        popGrid2.Cols("40", "*", "26")
        popGrid2.Add("TextBlock").Grid_Column(0).Text(GetLang("大小")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        popGrid2.Add("Slider").Grid_Column(1).Name("IgnoreSizeSlider")
            .VerticalAlignment("Center").Margin("0,0,6,0").Minimum(1).Maximum(8).Value(this.IgnoreBrushSize)
            .ToolTip(GetLang("蒙版笔刷直径（像素）"))
        popGrid2.Add("TextBlock").Grid_Column(2).Name("IgnoreSizeVal")
            .Text(String(this.IgnoreBrushSize)).FontSize("11").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")

        ; ===== 底部行：左「超多点」勾选框 + 右动作条（仅匹配页显示）=====
        bottomRow := leftGrid.Add("Grid").Grid_Row(1).Name("LeftBottomCon").Height(28)
            .Margin("0,8,0,0")
        bottomRow.Cols("*", "Auto")
        bottomRow.Add("CheckBox").Name("ChkSuperPoint").Content(GetLang("超多点"))
            .FontSize("12").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Foreground("{DynamicResource TextMain}")
            .SetProp("IsChecked", this.SuperEntryChecked ? "True" : "False")
            .ToolTip(GetLang("勾选后按基准色匹配整幅图，可涂蒙版忽略干扰区"))

        actionsRow := bottomRow.Add("Grid").Grid_Column(1).Name("LeftActionsCon")
            .HorizontalAlignment("Right").VerticalAlignment("Center")
        actionsRow.Cols("Auto", "Auto")
        this._AddIconBtn(actionsRow, "BtnPointUndo", Chr(0xE7A7), GetLang("撤回上一次点位改动"))
            .Grid_Column(0).Margin("0,0,4,0")     ; 图标按钮之间统一 4px
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")
        this._AddIconBtn(actionsRow, "BtnIgnoreUndo", Chr(0xE7A7), GetLang("撤销上一步蒙版编辑"))
            .Grid_Column(0).Margin("0,0,4,0").Visibility("Collapsed")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")
        this._AddIconBtn(actionsRow, "BtnCanvasClear", Chr(0xE74D), GetLang("清除画布上的蒙版和基准点"))
            .Grid_Column(1).Margin("0")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")

        ; ===== 原图页 =====
        origPanel := panelsHost.Add("StackPanel").Name("OriginalPanelCon").Orientation("Vertical")
            .Visibility("Collapsed")

        editPanel := origPanel.Add("StackPanel").Name("ImageEditControlsCon").Orientation("Vertical")
        this._AddSection(editPanel, GetLang("文件属性"))
        renameRow := editPanel.Add("Grid").Name("RenameRowCon").Height(30).Margin("0,0,0,2")
        renameRow.Cols("*", "34", "34")
        renameRow.Add("TextBox").Grid_Column(0).Name("NameCon").Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        this._AddIconBtn(renameRow, "BtnSelectImage", Chr(0xE8E5), GetLang("选择图片"))
            .Grid_Column(1).Margin("4,0,0,0")
            .SetProp("FontFamily", "Segoe Fluent Icons, Segoe MDL2 Assets")
        this._AddIconBtn(renameRow, "BtnRename", "✓", GetLang("按输入名称重命名模板图片"))
            .Grid_Column(2).Margin("4,0,0,0")
            .IsEnabled("False").Foreground("{DynamicResource TextSub}")
            .SetProp("ToolTipService.ShowOnDisabled", "True")   ; 禁用态也能看到提示

        this._AddSection(editPanel, GetLang("图片处理"))

        ; 裁剪：框选 + 应用（框选后出现）
        cropRow := editPanel.Add("Grid").Name("CropSectionCon").Height(30).Margin("0,0,0,2")
        cropRow.Cols("56", "28", "*", "28")
        cropRow.Add("TextBlock").Grid_Column(0).Text(GetLang("裁剪")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        ; 裁剪图标：PS 那种两个直角折线（Path 手绘，不依赖图标字体）
        cropBtn := cropRow.Add("Button").Name("BtnCrop")
            .Width(28).Height(28).MinWidth(28).MaxWidth(28).MinHeight(28).Padding("0")
            .Cursor("Hand").Margin("0").VerticalAlignment("Center").Grid_Column(1)
            .ToolTip(GetLang("拖动框选要保留的区域，再点一次退出"))
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        ; 几何从 (0,0) 起画（含描边外扩），否则内容会在按钮里偏右下
        cropBtn.Add("Path").SetProp("Data", "M0.7,6.7 L0.7,0.7 L6.7,0.7 M11.3,16.3 L16.3,16.3 L16.3,11.3")
            .SetProp("Stroke", "{DynamicResource TextMain}").SetProp("StrokeThickness", "1.4")
            .SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .SetProp("Fill", "Transparent")
        this._AddIconBtn(cropRow, "BtnApply", "✓", GetLang("应用选区并替换模板图片"))
            .Grid_Column(3).Visibility("Collapsed")

        ; 抠除：画笔 / 笔擦 + 撤销 + 应用（有笔迹后出现）
        eraseRow := editPanel.Add("Grid").Name("EraseSectionCon").Height(30).Margin("0,0,0,2")
        eraseRow.Cols("56", "Auto", "*", "Auto")
        eraseRow.Add("TextBlock").Grid_Column(0).Text(GetLang("抠除")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        eraseTools := eraseRow.Add("StackPanel").Grid_Column(1).Orientation("Horizontal")
            .VerticalAlignment("Center")
        this._AddIconBtn(eraseTools, "BtnEraseBrush", "✎"
            , GetLang("涂抹要抠掉的背景，再点一次退出")).Margin("0,0,4,0")
        this._AddIconBtn(eraseTools, "BtnEraseEraser", Chr(0xE75C)
            , GetLang("擦掉已涂抹的区域")).Margin("0")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")
        eraseIcons := eraseRow.Add("StackPanel").Grid_Column(3).Orientation("Horizontal")
            .VerticalAlignment("Center")
        this._AddIconBtn(eraseIcons, "BtnEraseUndo", Chr(0xE7A7), GetLang("撤销上一笔"))
            .Margin("0,0,4,0").Visibility("Collapsed")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")
        this._AddIconBtn(eraseIcons, "BtnEraseApply", "✓"
            , GetLang("按涂抹区域生成透明底 PNG 并替换模板图片"))
            .Margin("0").Visibility("Collapsed")

        ; ---- 自动抠图区块：开始/退出 按钮（文案随模式切换）----
        ; 注意：必须放在 ImageEditControlsCon 之外——样本模式下该容器整体禁用，子控件无法覆盖
        this._AddSection(origPanel, GetLang("自动抠图"))
        autoRow := origPanel.Add("Grid").Name("AutoMaskRowCon").Height(30).Margin("0,0,0,2")
        autoRow.Cols("Auto", "*")
        this._AddBtn(autoRow, "BtnSampleTool", GetLang("开始"), 72)
            .HorizontalAlignment("Left").Margin("0")
            .ToolTip(GetLang("进入/退出样本抠图模式"))

        ; ---- 以下仅样本模式显示 ----
        importRow := origPanel.Add("Grid").Name("SampleImportCon").Height(30).Margin("0,0,0,2").Visibility("Collapsed")
        importRow.Cols("56", "28", "*")
        importRow.Add("TextBlock").Grid_Column(0).Text(GetLang("导入")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._AddIconBtn(importRow, "BtnSampleImport", Chr(0xE8E5), GetLang("选择样本图片"))
            .Grid_Column(1).HorizontalAlignment("Left").Margin("0")
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")

        ctl1 := origPanel.Add("Grid").Name("SampleCtl1Con").Height(30).Margin("0,0,0,2").Visibility("Collapsed")
        ctl1.Cols("56", "28", "*", "Auto")
        ctl1.Add("TextBlock").Grid_Column(0).Text(GetLang("截屏")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._AddIconBtn(ctl1, "BtnSampleShot", Chr(0xE722), GetLang("截屏并添加为样本")).Grid_Column(1)
            .SetProp("FontFamily", "Segoe MDL2 Assets").FontSize("15")
        ctl1.Add("CheckBox").Grid_Column(3).Name("ChkSampleFixed").Content(GetLang("固定位置"))
            .FontSize("11").VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
            .ToolTip(GetLang("勾选时自动截取与上一次相同的区域"))

        ctl2 := origPanel.Add("Grid").Name("SampleCtl2Con").Height(30).Margin("0,0,0,2").Visibility("Collapsed")
        ctl2.Cols("64", "*", "32")
        ctl2.Add("TextBlock").Grid_Column(0).Text(GetLang("稳定阈值")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        ctl2.Add("Slider").Grid_Column(1).Name("SampleThresholdSlider")
            .VerticalAlignment("Center").Margin("0,0,6,0").Minimum(0).Maximum(64).Value(this.SampleThreshold)
            .ToolTip(GetLang("阈值越小判定越严，越大越宽松"))
        ctl2.Add("TextBlock").Grid_Column(2).Name("SampleThresholdVal")
            .Text(String(this.SampleThreshold)).FontSize("11").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")

        ctl3 := origPanel.Add("Button").Name("BtnSampleExtract").Content(GetLang("✓ 提取并保存"))
            .Height(32).MinHeight(32).HorizontalAlignment("Stretch").Margin("0,0,0,2").Visibility("Collapsed")
            .IsEnabled("False")
            .FontSize("11").Cursor("Hand")
            .ToolTip(GetLang("生成透明底 PNG，存为新文件（分辨率 = 第 1 张样本）"))
            .SetProp("ToolTipService.ShowOnDisabled", "True")   ; 禁用态也要能看提示
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; 画笔大小浮窗：点画笔 / 笔擦后在下方出现
        brushPop := editPanel.Add("Border").Name("BrushPopCon").Margin("56,6,0,0")
            .Padding("8,6").CornerRadius("6").HorizontalAlignment("Stretch")
            .Background("{DynamicResource BgColor}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .Visibility("Collapsed")
        popGrid := brushPop.Add("Grid")
        popGrid.Cols("40", "*", "26")
        popGrid.Add("TextBlock").Grid_Column(0).Text(GetLang("大小")).FontSize("12")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        popGrid.Add("Slider").Grid_Column(1).Name("EraseBrushSlider")
            .VerticalAlignment("Center").Margin("0,0,6,0").Minimum(1).Maximum(8).Value(this.EraseBrushSize)
            .ToolTip(GetLang("涂抹笔刷直径（像素）"))
        popGrid.Add("TextBlock").Grid_Column(2).Name("EraseBrushVal")
            .Text(String(this.EraseBrushSize)).FontSize("11").TextAlignment("Center")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")

        ; ---- 中栏卡片：只有画布（工具条已并入左栏）----
        midCard := prev.Add("Border").Grid_Column(1).Name("MidPane").Width(this.CanvasSide + 14)
            .VerticalAlignment("Stretch")
            .CornerRadius("10").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        mid := midCard.Add("Grid").Margin("6,11,6,11")
        mid.Rows(this.CanvasSide)
        mid.Cols(this.CanvasSide)

        right := mid.Add("Border").Grid_Row(0).Name("RightPane")
            .Width(this.CanvasSide).Height(this.CanvasSide)
            .HorizontalAlignment("Center").ClipToBounds("True")
            .Background("#FF1E1E1E")
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
        ; 裁剪选区独立一层：只由 _RefreshSelectionOverlay 维护，_Render 不碰它
        rightCanvas.Add("Image").Name("CropOverlayImg").Width(this.CanvasSide).Height(this.CanvasSide)
            .Stretch("Fill").IsHitTestVisible("False").SetProp("Panel.ZIndex", "4")

        ; 样本抠图模式：可滚动的样本缩略图列表（3 列×20 行 = 60 张上限）
        samplePane := mid.Add("Border").Grid_Row(0).Name("SampleGridPane").Visibility("Collapsed")
            .Background("#FF1E1E1E")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .CornerRadius("4").ClipToBounds("True")
        sampleScroll := samplePane.Add("ScrollViewer").Name("SampleScroll")
        tilesWrap := sampleScroll.Add("WrapPanel").Margin("4")
        Loop 60 {
            i := A_Index
            tile := tilesWrap.Add("Grid").Name("SampleTile" i)
                .Width(120).Height(120).Margin("4").Visibility("Collapsed")
            tile.Add("Border").Name("SampleTileBorder" i).Background("#FF1E1E1E")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
                .CornerRadius("4").ClipToBounds("True")
            tile.Add("Image").Name("SampleThumbImg" i).Stretch("Uniform").Margin("4")
            ; 悬停命中层：提示只挂这一层；不需要提示时整层 Collapsed（折叠元素不触发提示，避免空提示框）
            tile.Add("Border").Name("SampleHitbox" i).Background("Transparent")
                .IsHitTestVisible("True")
            tile.Add("Button").Name("BtnSampleDel" i).Content("✕").Width(18).Height(18)
                .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,2,2,0")
                .FontSize("10").Padding("0").Cursor("Hand").FontWeight("Bold")
                .Foreground("#FFFFFFFF").Background("#99000000").BorderThickness("0")
                .ToolTip(GetLang("删除该样本"))
        }
        ; 点击右栏预览 → 中栏放大显示提取结果
        enlarge := mid.Add("Border").Grid_Row(0).Name("SampleEnlargePane").Visibility("Collapsed")
            .Background("#FF1E1E1E")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .CornerRadius("4").ClipToBounds("True")
        enlarge.Add("Image").Name("SampleEnlargeImg").Stretch("Uniform")

        ; ---- 右栏卡片：效果图（匹配页）/ 图片信息（原图页）+ 取消保存 ----
        sideCard := prev.Add("Border").Grid_Column(3).Name("SidePane").Width(174)
            .VerticalAlignment("Stretch")
            .CornerRadius("10").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        sideCol := sideCard.Add("Grid").Margin("12,12,12,12")
        sideCol.Rows("*", "Auto", "Auto", "Auto")

        effPanel := sideCol.Add("StackPanel").Grid_Row(0).Name("EffPanelCon").VerticalAlignment("Top")
            .HorizontalAlignment("Center")
        thumb := effPanel.Add("Border").Name("EffectiveThumbPane").Width(144).Height(144)
            .HorizontalAlignment("Center")
            .Background("#FF1E1E1E")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .CornerRadius("4").ClipToBounds("True").Cursor("Hand")
            .ToolTip(GetLang("点击切换有效图预览"))
        thumbImages := thumb.Add("Grid")
        thumbImages.Add("Image").Name("EffectiveThumbImg").Stretch("Uniform").IsHitTestVisible("False")
        thumbImages.Add("Image").Name("SamplePreviewImg").Stretch("Uniform").IsHitTestVisible("False")
            .Visibility("Collapsed")
        effPanel.Add("TextBlock").Name("SampleStatusText").Margin("0,6,0,0")
            .FontSize("11").TextAlignment("Center").TextWrapping("Wrap")
            .Foreground("{DynamicResource TextSub}").Visibility("Collapsed")
        effPanel.Add("TextBlock").Name("SampleUnalignedText").Margin("0,2,0,0")
            .FontSize("11").TextAlignment("Center").TextWrapping("Wrap")
            .Foreground("#FFFF9999").Visibility("Collapsed")

        infoPanel := sideCol.Add("StackPanel").Grid_Row(0).Name("InfoPanelCon")
            .VerticalAlignment("Top").Visibility("Collapsed")
        infoPanel.Add("TextBlock").Name("InfoSizeCon").Text("").FontSize("20")
            .Foreground("{DynamicResource TextMain}")
        infoPanel.Add("TextBlock").Name("InfoNameCon").Text("").FontSize("11").Margin("0,4,0,0")
            .TextTrimming("CharacterEllipsis").Foreground("{DynamicResource TextMain}")

        ; 当前保存所应用的匹配方式（横线上方）：标题 + 最多三行明细
        modeInfo := sideCol.Add("StackPanel").Grid_Row(1).Name("ModeInfoCon")
            .Margin("0,12,0,0").HorizontalAlignment("Stretch")
        modeInfo.Add("TextBlock").Name("ModeInfoTitle").Text("").FontSize("11")
            .TextAlignment("Left").FontWeight("Bold")
            .Foreground("{DynamicResource TextSub}")
        for i in [1, 2, 3]
            modeInfo.Add("TextBlock").Name("ModeInfo" i).Text("").FontSize("11")
                .TextAlignment("Left").Margin("0,2,0,0")
                .Foreground("{DynamicResource TextSub}").Visibility("Collapsed")

        sideCol.Add("Border").Grid_Row(2).Height("1").Margin("0,10,0,10")
            .Background("{DynamicResource ControlBorder}")

        sideBtns := sideCol.Add("StackPanel").Grid_Row(3).HorizontalAlignment("Center")
            .VerticalAlignment("Bottom")
        sideBtns.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(96).Height(32).MinHeight(32)
            .Cursor("Hand").ToolTip(GetLang("关闭并放弃本次点位修改"))
        sideBtns.Add("Button").Name("BtnSure").Content(GetLang("保存")).Width(96).Height(32).MinHeight(32)
            .Margin("0,8,0,0").Cursor("Hand").ToolTip(GetLang("应用点位设置并返回搜索窗口"))

        ; ---- 宿主 ----
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="' this._Esc(title) '" Width="890" Height="540" MinWidth="890" MinHeight="540"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; ---- 事件 ----
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing").Bind(windowToken))
        this.ui.OnEvent("EffectiveThumbPane", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnThumbClick"))
        this.ui.OnEvent("BtnCrop", "Click", ObjBindMethod(this, "OnCropSectionClick"))
        this.ui.OnEvent("BtnSelectImage", "Click", ObjBindMethod(this, "OnSelectImage"))
        this.ui.OnEvent("BtnApply", "Click", ObjBindMethod(this, "OnApplyCrop"))
        this.ui.OnEvent("BtnEraseBrush", "Click", ObjBindMethod(this, "OnEraseSectionClick"))
        this.ui.OnEvent("BtnEraseEraser", "Click", ObjBindMethod(this, "OnEraseEraserClick"))
        this.ui.OnEvent("BtnSampleTool", "Click", ObjBindMethod(this, "OnSampleToolClick"))
        this.ui.OnEvent("BtnSampleShot", "Click", ObjBindMethod(this, "_SampleShot"))
        this.ui.OnEvent("BtnSampleImport", "Click", ObjBindMethod(this, "_SampleImport"))
        this.ui.OnEvent("ChkSampleFixed", "Checked", ObjBindMethod(this, "_SampleFixedChanged", true))
        this.ui.OnEvent("ChkSampleFixed", "Unchecked", ObjBindMethod(this, "_SampleFixedChanged", false))
        this.ui.OnEvent("SampleThresholdSlider", "ValueChanged", ObjBindMethod(this, "_SampleThresholdChanged"))
        this.ui.OnEvent("BtnSampleExtract", "Click", ObjBindMethod(this, "_SampleExport"))
        loop 60
            this.ui.OnEvent("BtnSampleDel" A_Index, "Click", ObjBindMethod(this, "_SampleDelete", A_Index))
        this.ui.OnEvent("BtnEraseUndo", "Click", ObjBindMethod(this, "OnEraseUndo"))
        this.ui.OnEvent("BtnEraseApply", "Click", ObjBindMethod(this, "OnApplyErase"))
        this.ui.OnEvent("EraseBrushSlider", "ValueChanged", ObjBindMethod(this, "OnEraseBrushSlider"))
        this.ui.OnEvent("BtnModeOriginal", "Click", ObjBindMethod(this, "OnMatchMode", "original"))
        this.ui.OnEvent("BtnModeMultiPoint", "Click", ObjBindMethod(this, "OnModeMultiClick"))
        this.ui.OnEvent("ChkSuperPoint", "Checked", ObjBindMethod(this, "OnSuperPointCheck", true))
        this.ui.OnEvent("ChkSuperPoint", "Unchecked", ObjBindMethod(this, "OnSuperPointCheck", false))
        this.ui.OnEvent("BtnHelp", "Click", ObjBindMethod(this, "OnHelp"))
        this.ui.OnEvent("BtnMultiSeedTool", "Click", ObjBindMethod(this, "OnPointTool", "seed"))
        this.ui.OnEvent("BtnMultiPointTool", "Click", ObjBindMethod(this, "OnPointTool", "point"))
        this.ui.OnEvent("BtnSuperSeedTool", "Click", ObjBindMethod(this, "OnPointTool", "seed"))
        this.ui.OnEvent("BtnRename", "Click", ObjBindMethod(this, "OnRename"))
        this.ui.OnEvent("NameCon", "TextChanged", ObjBindMethod(this, "OnNameChanged"))
        this.ui.OnEvent("BtnCanvasClear", "Click", ObjBindMethod(this, "OnCanvasClear"))
        this.ui.OnEvent("BtnPointUndo", "Click", ObjBindMethod(this, "OnPointUndo"))
        this.ui.OnEvent("BtnAutoPoints", "Click", ObjBindMethod(this, "OnAutoSelectPoints"))
        this.ui.OnEvent("BtnIgnoreBrush", "Click", ObjBindMethod(this, "OnIgnoreTool", "brush"))
        this.ui.OnEvent("BtnIgnoreEraser", "Click", ObjBindMethod(this, "OnIgnoreTool", "eraser"))
        this.ui.OnEvent("IgnoreSizeSlider", "ValueChanged", ObjBindMethod(this, "OnIgnoreSizeSlider"))
        this.ui.OnEvent("BtnIgnoreUndo", "Click", ObjBindMethod(this, "OnIgnoreUndo"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnSure"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelButton"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancel"))
        this.ui.OnEvent("TolSlider", "ValueChanged", ObjBindMethod(this, "OnTolSlider"))
        this.ui.OnEvent("DensitySlider", "ValueChanged", ObjBindMethod(this, "OnDensitySlider"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnIgnoreDown"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnRightMove"))
        this.ui.OnEvent("RightCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnIgnoreUp"))

        this._ApplyModeStyle()
        this._SyncMatchModeUi()
    }

    OnHelp(*) {
        text := Format("{}`n{}`n`n{}`n{}`n{}`n`n{}`n{}"
            , GetLang("一、图片处理")
            , GetLang("改名：改完按右侧对勾应用。裁剪：框选保留区域后应用。抠除：画笔涂掉背景、笔擦擦回，再应用生成透明底。")
            , GetLang("二、多点搜图")
            , GetLang("用多个色块匹配；相似度=命中比例；可点击右上角效果图，查看搜索时参与的色块。操作流程：选基准点后可自动补点或手动增删，最多 256 点。")
            , GetLang("超多点：选基准色 + 容差匹配整幅图，蒙版涂抹区域不参与匹配。")
            , GetLang("三、自动抠图")
            , GetLang("采集 2 张以上同一区域的样本（截屏或导入），自动对齐后提取所有样本共同不变的像素，生成透明底 PNG。"))
        RmtDialog.Info(text, GetLang("图片处理说明"))
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
        if (this.SampleMode && this.EditorMode == "original") {
            method := dir > 0 ? "LineUp" : "LineDown"
            Loop 3
                this.ui.Update("SampleScroll", method, "")
            return
        }
        base := (this.Zoom > 0) ? this.Zoom : this._FitZoom()
        mouse := this._MouseCanvasPoint()
        ; 锚点 = 光标下的图像像素；光标落在图外（留白区）时收到图内最近的像素
        anchor := this._ToImageFloat(mouse.x, mouse.y, base, this.ViewX, this.ViewY)
        anchor.x := Min(Max(0, anchor.x), this.OrigW - 1)
        anchor.y := Min(Max(0, anchor.y), this.OrigH - 1)
        z := base * (dir > 0 ? 1.25 : 1 / 1.25)
        z := Min(32.0, Max(0.1, z))   ; 上限 3200%：小模板（几十像素）也能放大到看清单像素
        this.Zoom := Floor(z * 100) / 100

        ; 调整视口，使滚轮前光标下的原图像素仍位于同一画布位置。
        ; 鼠标坐标和画布尺寸都是 DIP，不需要再做缩放补偿。
        if (IsObject(anchor)) {
            layout := this._ViewLayout(this.Zoom)
            maxX := Max(0, this.OrigW - layout.viewW)
            maxY := Max(0, this.OrigH - layout.viewH)
            ; 取整：DLL 只能按整数像素出图，浮点视口会在高倍缩放下变成明显的错位/跳动
            this.ViewX := Min(maxX, Max(0, Round(anchor.x - (mouse.x - layout.offsetX) / layout.zoom)))
            this.ViewY := Min(maxY, Max(0, Round(anchor.y - (mouse.y - layout.offsetY) / layout.zoom)))
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

    ; 区块标题：两侧细线 + 10px 浅色字（结构标签，不是状态提示）
    _AddSection(parent, text) {
        sec := parent.Add("Grid").Height(20).Margin("0,10,0,4")
        sec.Cols("*", "Auto", "*")
        sec.Add("Border").Grid_Column(0).Height("1").VerticalAlignment("Center")
            .Background("{DynamicResource ControlBorder}")
        sec.Add("TextBlock").Grid_Column(1).Text(text).FontSize("10")
            .Margin("8,0").VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        sec.Add("Border").Grid_Column(2).Height("1").VerticalAlignment("Center")
            .Background("{DynamicResource ControlBorder}")
        return sec
    }

    ; 十字准星图标（圆圈 + 十字，Path 手绘；比字形大且不依赖字体）
    _AddCrosshairBtn(parent, name, tip := "") {
        btn := parent.Add("Button").Name(name)
            .Width(28).Height(28).MinWidth(28).MaxWidth(28).MinHeight(28).Padding("0")
            .Cursor("Hand").Margin("0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        if (tip != "")
            btn.ToolTip(tip)
        btn.Add("Path")
            .SetProp("Data", "M3,10 A7,7 0 1 0 17,10 A7,7 0 1 0 3,10 M10,0.8 L10,19.2 M0.8,10 L19.2,10")
            .SetProp("Stroke", "{DynamicResource TextMain}").SetProp("StrokeThickness", "1.5")
            .SetProp("StrokeStartLineCap", "Round").SetProp("StrokeEndLineCap", "Round")
            .SetProp("Fill", "Transparent")
        return btn
    }

    ; 28×28 图标按钮（✓ 应用 / ↺ 撤销）
    _AddIconBtn(parent, name, text, tip := "") {
        btn := parent.Add("Button").Name(name).Content(text)
            .Width(28).Height(28).MinWidth(28).MaxWidth(28).MinHeight(28).Padding("0")
            .FontSize("13").Cursor("Hand").Margin("0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        if (tip != "")
            btn.ToolTip(tip)
        return btn
    }


    _Esc(s) => StrReplace(StrReplace(StrReplace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

    _ResetInteraction() {
        this.Mode := ""
        this.CropDrag := ""
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
        this._RefreshSelectionOverlay()   ; 选区在独立叠加层上，必须显式清掉
        this._SyncApplyState()
    }

    ; ------------------------------------------------------------------
    ; 控件同步
    ; ------------------------------------------------------------------
    _SyncControls() {
        if (!IsObject(this.ui))
            return
        SplitPath(this.TemplatePath, , , , &nameNoExt)
        this._NameBase := nameNoExt
        try this.ui.Update("NameCon", "Text", nameNoExt)
        try this.ui.Update("BtnRename", "IsEnabled", "False")
        try this.ui.Update("BtnRename", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("TolCon", "Text", String(this.Tol))
        try this.ui.Update("TolSlider", "Value", this.Tol)
        try this.ui.Update("DensityValueCon", "Text", String(this.AutoPointDensity))
        try this.ui.Update("DensitySlider", "Value", this.AutoPointDensity)
        this._SyncApplyState()
        this._SyncImageInfo()
    }

    ; 右栏「图片信息」：尺寸 / 文件名 / 是否带透明通道
    ; _Render 每帧都会调到这里，签名没变就直接跳过，避免拖框时刷一堆无用的 Update
    _SyncImageInfo() {
        if (!IsObject(this.ui))
            return
        sig := this.TemplatePath "|" this.OrigW "x" this.OrigH
        if (sig == this._infoSig)
            return
        this._infoSig := sig
        SplitPath(this.TemplatePath, &fileName)
        try this.ui.Update("InfoSizeCon", "Text", Format("{} × {}", this.OrigW, this.OrigH))
        try this.ui.Update("InfoNameCon", "Text", fileName)
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
    ; 渲染重入保护：滚轮/容差定时器可能在 DllCall 期间打断线程，
    ; 若此时再进一次渲染，外层会拿着旧状态（如多点预览）的帧最后落地，覆盖新帧
    _Render() {
        if (this.SampleMode && this.EditorMode == "original") {
            this._SampleRefreshPreview()
            return
        }
        if (this._renderBusy || this._thumbBusy) {
            this._renderAgain := true      ; 记下这次请求，当前帧结束后补渲
            return
        }
        this._renderBusy := true
        try {
            this._RenderBody()
        } finally {
            this._renderBusy := false
        }
        if (this._renderAgain) {
            this._renderAgain := false
            this._Render()
        }
    }

    _RenderBody() {
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
        ; 有效图靠「压暗/未压暗」比对，网格线会同时画进两张图被误判成命中，所以该视图下不画网格
        showGrid := (this.Zoom >= 6.0 && this.ViewMode != "effective") ? 1 : 0

        previewSeeds := this.EditorMode == "original" ? [] :
            (this.EditorMode == "super" ? this.SuperSeedPoints : this.SeedPoints)
        try info := this._Call(renderViewX, renderViewY, vw, vh, zoomPercent, outOrig, outEff
            , showGrid, this._MultiPointText(previewSeeds), this.Tol)
        catch {
            info := { ret: -5, valid: 0, total: 0, ow: this.OrigW, oh: this.OrigH }
        }
        if (info.ret != 1)
        {
            return
        }

        this.OrigW := info.ow, this.OrigH := info.oh
        this._rendering := true
        this._renderedZoom := this.Zoom
        this._renderedViewX := renderViewX
        this._renderedViewY := renderViewY
        pointOverlayPath := this._CreateModePointOverlay()
        ignoreOverlayPath := this._CreateModeIgnoreOverlay()
        ; 底图三选一：
        ;   edit     → outEff（按容差压暗后的预览，这是调参的核心反馈）
        ;   original → outOrig（真原图）
        ;   effective→ 只留参与匹配的像素
        ; 有效图只在有效视图下生成：编辑视图显示的是压暗预览，缩略图另行生成，
        ; 这份逐像素结果没人看，白算（超多点尤其贵）→ 按需生成
        effectivePath := this.ViewMode == "effective"
            ? this._CreateEffectiveImage(outOrig, outEff, vw, vh, zoomPercent) : ""
        thumbPath := this._CreateEffectiveThumb()
        basePath := this.ViewMode == "original" ? outOrig : outEff
        if (this.ViewMode == "effective" && effectivePath != "")
            basePath := effectivePath
        showOverlay := this.ViewMode == "edit"
        ; 顺序：先变换 → 再换图。反序会「新图配旧位移」，渲染落地时看起来就是跳位
        sourceUpdates := []
        for update in this._PreviewTransformUpdates()
            sourceUpdates.Push(update)
        sourceUpdates.Push({ ControlName: "RightImg", PropertyName: "Source", Value: StrReplace(basePath, "\", "/") })
        sourceUpdates.Push({ ControlName: "RightPointOverlayImg", PropertyName: "Source"
            , Value: pointOverlayPath == "" ? "" : StrReplace(pointOverlayPath, "\", "/") })
        sourceUpdates.Push({ ControlName: "IgnoreOverlayImg", PropertyName: "Source"
            , Value: ignoreOverlayPath == "" ? "" : StrReplace(ignoreOverlayPath, "\", "/") })
        sourceUpdates.Push({ ControlName: "EffectiveThumbImg", PropertyName: "Source"
            , Value: StrReplace(thumbPath, "\", "/") })
        sourceUpdates.Push({ ControlName: "RightPointOverlayImg", PropertyName: "Visibility"
            , Value: showOverlay ? "Visible" : "Collapsed" })
        sourceUpdates.Push({ ControlName: "IgnoreOverlayImg", PropertyName: "Visibility"
            , Value: showOverlay ? "Visible" : "Collapsed" })
        try this.ui.BatchUpdate(sourceUpdates)

        oldRightOverlay := this._lastRightOverlay
        oldIgnoreOverlay := this._lastIgnoreOverlay
        oldMasked := this._lastMasked
        this._lastRightOverlay := pointOverlayPath
        this._lastIgnoreOverlay := ignoreOverlayPath
        this._lastMasked := effectivePath
        this._rendering := false
        if (oldRightOverlay != pointOverlayPath)
            try FileDelete(oldRightOverlay)
        if (oldIgnoreOverlay != ignoreOverlayPath)
            try FileDelete(oldIgnoreOverlay)
        if (oldMasked != effectivePath)
            try FileDelete(oldMasked)
        oldThumb := this._lastThumb
        this._lastThumb := thumbPath
        if (oldThumb != thumbPath)
            try FileDelete(oldThumb)
        if (this._ignoreOverlayRefreshPending) {
            this._ignoreOverlayRefreshPending := false
            this._RefreshIgnoreOverlay()
        }
        ; _Render 会把 IgnoreOverlayImg 的 Source 重置为空，编辑态下需要把擦除笔迹补画回去
        if (this.ViewMode == "edit")
            this._RefreshEraseOverlay()

        ; 清理上一帧
        try FileDelete(this._lastOrig)
        try FileDelete(this._lastEff)
        this._lastOrig := outOrig
        this._lastEff := outEff

        this._SyncCanvasActions()
        this._SyncImageInfo()
        ; 缩放/平移后按新视图重画选区（选区不烘进底图，靠叠加层常驻）
        if (this.Mode == "crop" && this.SelW > 0)
            this._RefreshSelectionOverlay()
    }

    _FitZoom() {
        if (this.OrigW <= 0 || this.OrigH <= 0)
            return 1.0
        z := Min(this.CanvasSide / this.OrigW, this.CanvasSide / this.OrigH, 32.0)
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
            , "Int", 0, "Int", 0, "Int", 0, "Int", 0   ; 选区改由叠加层绘制，DLL 不再烘黄框
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
    _XY(state, side := "R") {
        key := "RightCanvas"
        raw := (IsObject(state) && state.Has(key)) ? state[key] : ""
        if (!InStr(raw, ","))
            return { x: -1, y: -1 }
        parts := StrSplit(raw, ",")
        point := { x: Number(parts[1]), y: Number(parts[2]) }
        return this._CanvasPointToViewport(point)
    }

    _MouseCanvasPoint() {
        ; Query 返回的是 "x;y" 字符串（与 _RightCanvasPoint 一致），不是对象
        if (!IsObject(this.ui))
            return { x: this.CanvasSide / 2, y: this.CanvasSide / 2 }
        raw := ""
        try raw := String(this.ui.Query("RightCanvas>MouseLocal"))
        if (InStr(raw, ";")) {
            parts := StrSplit(raw, ";")
            if (parts.Length >= 2 && IsNumber(parts[1]) && IsNumber(parts[2])) {
                point := this._CanvasPointToViewport({ x: Number(parts[1]), y: Number(parts[2]) })
                if (point.x >= 0 && point.y >= 0 && point.x <= this.CanvasSide && point.y <= this.CanvasSide)
                    return point
            }
        }
        ; 拿不到光标位置时退回画布中心，保证缩放仍有明确中心
        return { x: this.CanvasSide / 2, y: this.CanvasSide / 2 }
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
        ; 画布坐标和画布尺寸都是 DIP，直接换算，不需要缩放补偿
        vx := (viewX == "") ? this.ViewX : viewX
        vy := (viewY == "") ? this.ViewY : viewY
        return { x: vx + (px - layout.offsetX) / layout.zoom
            , y: vy + (py - layout.offsetY) / layout.zoom }
    }

    _ToImage(px, py) {
        ; 画布坐标 → 原图坐标
        if (this.Zoom <= 0 || this.OrigW <= 0 || this.OrigH <= 0)
            return { x: 0, y: 0 }
        point := this._ToImageFloat(px, py)
        return { x: Floor(point.x), y: Floor(point.y) }
    }

    OnDown(side, state, ctrl, event) {
        if (side != "L" && side != "R")
            return
        p := this._XY(state, side)
        if (p.x < 0)
            return
        this.Dragging := true
        this.DragMoved := false
        this.DragStartX := p.x
        this.DragStartY := p.y
        this.DragViewX := this.ViewX
        this.DragViewY := this.ViewY

        if (this.Mode == "crop") {
            ; 命中：角标缩放 / 选区内部移动 / 空白新建，统一由 _CropHit 决定
            img := this._ToImage(p.x, p.y)
            mode := this._CropHit(p)
            this.CropDrag := { mode: mode, startImgX: img.x, startImgY: img.y
                , origX: this.SelX, origY: this.SelY }
            this.DragMoved := true
            if (mode == "new") {
                this.SelX := Min(Max(0, img.x), this.OrigW - 1)
                this.SelY := Min(Max(0, img.y), this.OrigH - 1)
                this.SelW := 0
                this.SelH := 0
                this._RefreshSelectionOverlay()   ; 清掉上一轮的选区框
            }
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

        ; 裁剪：新建 / 移动 / 角标缩放，统一走 _CropDragTo
        if (this.CropDrag != "") {
            this._CropDragTo(p)
            return
        }

        if (this.Mode == "") {
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
        this.CropDrag := ""
        this.Dragging := false
        p := this._XY(state, side)

        ; 裁剪：松手落在画布外也要结算选区，否则 ✓ 不会出现（叠加层已经画了框）
        if (this.Mode == "crop") {
            if (this.SelW < 2 || this.SelH < 2) {
                this.SelW := 0
                this.SelH := 0
            }
            this._RefreshSelectionOverlay()
            this._SyncApplyState()
            return
        }

        if (p.x < 0) {
            if (viewChanged)
                this._Render()
            return
        }

        ; 单画布：不再按左右区分，只看当前点位工具
        canEditPoints := (this.EditorMode == "multi" && this.PointTool != "")
            || (this.EditorMode == "super" && this.PointTool == "seed")
        if (this.Mode == "" && canEditPoints && !this.DragMoved && !viewChanged) {
            img := this._ToImage(p.x, p.y)
            if (img.x >= 0 && img.y >= 0 && img.x < this.OrigW && img.y < this.OrigH)
                this._ToggleMultiPoint(img.x, img.y, p.x, p.y)
            return
        }
        if (viewChanged)
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
        ; 原图页：涂抹走笔迹，其余交给框选/平移
        if (this.EditorMode == "original") {
            if (this.EraseTool == "") {
                if (this.Mode == "crop")
                    this._UpdateCropCursor(this._XY(state, "R"))
                this.OnMove("R", state, ctrl, event)
            }
            return
        }
        ; 匹配页：没开蒙版/橡皮时，拖动 = 平移画布
        if (this.EditorMode == "multi" || this.IgnoreTool == "")
            this.OnMove("R", state, ctrl, event)
    }

    OnIgnoreDown(state, ctrl, event) {
        ; 点位工具优先：选点时不应该触发蒙版涂抹
        if (this.EditorMode == "original") {
            if (this.EraseTool != "")
                this._EraseDown(state)
            else
                this.OnDown("R", state, ctrl, event)
            return
        }
        ; 超多点没开蒙版/橡皮时，按下同样走平移（选色工具的点击由 OnUp 处理）
        if (this.EditorMode == "multi" || this.IgnoreTool == "") {
            this.OnDown("R", state, ctrl, event)
            return
        }
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
        if (this.EditorMode == "original") {
            if (this.EraseTool != "") {
                if (!this.EraseDragging || !IsObject(this.EraseCurrentOp))
                    return
                imagePoint := this._IgnoreImagePoint(this._XY(state, "R"))
                if (IsObject(imagePoint))
                    this._AppendErasePoint(imagePoint)
                this._FinishEraseStroke()
            } else {
                this.OnUp("R", state, ctrl, event)
            }
            return
        }
        if (this.EditorMode == "multi" || this.IgnoreTool == "") {
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
        if (this.EditorMode != "super")
            return
        if (this.IgnoreDragging)
            this._FinishIgnoreStroke()
        SetTimer(this._ignoreStrokeTimer, 0)
        this.IgnoreTool := this.IgnoreTool == requestedTool ? "" : requestedTool
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        ; 与基准点互斥：选蒙版就退出选色
        if (this.IgnoreTool != "" && this.PointTool != "") {
            this.PointTool := ""
            this._SyncPointToolControls()
        }
        this._SyncIgnoreControls()
        this._RefreshIgnoreOverlay()
    }

    OnIgnoreSizeSlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("IgnoreSizeSlider")) ? state["IgnoreSizeSlider"] : ""
        if (!IsNumber(v))
            return
        this.IgnoreBrushSize := Max(1, Min(8, Integer(v)))
        try this.ui.Update("IgnoreSizeVal", "Text", String(this.IgnoreBrushSize))
    }

    _PushIgnoreUndo() {
        this.IgnoreUndo.Push(this._SerializeIgnoreData(this.IgnoreOps))
        if (this.IgnoreUndo.Length > 20)
            this.IgnoreUndo.RemoveAt(1)
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
        previous := this.IgnoreUndo.Pop()
        this._RestoreIgnoreData(previous)
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

    ; 点是否落在四角手柄上（画布坐标，容差 8）
    ; 裁剪命中的唯一判定：角标（缩放）/ 选区内部（移动）/ 空白（新建）
    _CropHit(p) {
        if (this.Mode != "crop" || this.OrigW <= 0 || p.x < 0)
            return ""
        if (this.SelW > 0 && this.SelH > 0) {
            hit := this._HitHandle(p.x, p.y)
            if (hit != "")
                return hit
            img := this._ToImage(p.x, p.y)
            if (img.x >= this.SelX && img.x < this.SelX + this.SelW
                && img.y >= this.SelY && img.y < this.SelY + this.SelH)
                return "move"
        }
        return "new"
    }

    ; 裁剪拖拽的唯一实现：按 CropDrag.mode 更新选区并刷新叠加层
    _CropDragTo(p) {
        img := this._ToImage(p.x, p.y)
        mode := this.CropDrag.mode
        if (mode == "new") {
            a := this._ToImage(this.DragStartX, this.DragStartY)
            x1 := Min(a.x, img.x), y1 := Min(a.y, img.y)
            x2 := Max(a.x, img.x) + 1, y2 := Max(a.y, img.y) + 1
            x1 := Min(Max(0, x1), this.OrigW - 1), y1 := Min(Max(0, y1), this.OrigH - 1)
            x2 := Min(Max(x1 + 1, x2), this.OrigW), y2 := Min(Max(y1 + 1, y2), this.OrigH)
            this.SelX := x1, this.SelY := y1, this.SelW := x2 - x1, this.SelH := y2 - y1
        } else if (mode == "move") {
            dx := img.x - this.CropDrag.startImgX, dy := img.y - this.CropDrag.startImgY
            this.SelX := Min(Max(0, this.CropDrag.origX + dx), this.OrigW - this.SelW)
            this.SelY := Min(Max(0, this.CropDrag.origY + dy), this.OrigH - this.SelH)
        } else {
            img.x := Min(Max(0, img.x), this.OrigW - 1)
            img.y := Min(Max(0, img.y), this.OrigH - 1)
            x2 := this.SelX + this.SelW
            y2 := this.SelY + this.SelH
            if (InStr(mode, "T")) {
                this.SelY := Min(img.y, y2 - 1)
                this.SelH := y2 - this.SelY
            } else {
                this.SelH := Max(1, img.y - this.SelY)
            }
            if (InStr(mode, "L")) {
                this.SelX := Min(img.x, x2 - 1)
                this.SelW := x2 - this.SelX
            } else {
                this.SelW := Max(1, img.x - this.SelX)
            }
        }
        this._RefreshSelectionOverlay()
        ; 选区达到可用尺寸就立刻让 ✓ 出现，不依赖松手位置
        hasSel := (this.SelW >= 2 && this.SelH >= 2)
        if (hasSel != this._selApplyShown) {
            this._selApplyShown := hasSel
            this._SyncApplyState()
        }
    }

    _HitHandle(px, py) {
        if (this.SelW <= 0 || this.SelH <= 0 || this.Zoom <= 0)
            return ""
        layout := this._ViewLayout(this.Zoom)
        x1 := layout.offsetX + (this.SelX - this.ViewX) * layout.zoom
        y1 := layout.offsetY + (this.SelY - this.ViewY) * layout.zoom
        x2 := layout.offsetX + (this.SelX + this.SelW - this.ViewX) * layout.zoom
        y2 := layout.offsetY + (this.SelY + this.SelH - this.ViewY) * layout.zoom
        tol := 8
        if (Abs(px - x1) <= tol && Abs(py - y1) <= tol)
            return "TL"
        if (Abs(px - x2) <= tol && Abs(py - y1) <= tol)
            return "TR"
        if (Abs(px - x1) <= tol && Abs(py - y2) <= tol)
            return "BL"
        if (Abs(px - x2) <= tol && Abs(py - y2) <= tol)
            return "BR"
        return ""
    }

    _ToggleMultiPoint(ix, iy, clickX, clickY) {
        ; 按预览中的标记位置命中，缩放时删除范围保持不变。
        if (this.EditorMode == "super" && this.PointTool != "seed")
            return
        if (this.EditorMode == "multi" && this.PointTool == "")
            return

        layout := this._ViewLayout(this.Zoom)
        hitRadius := 6

        if (this.EditorMode == "multi") {
            seedHit := this._FindPointHit(this.SeedPoints, layout, clickX, clickY, hitRadius)
            if (this.PointTool == "point" && seedHit > 0)
                return
            if (this.PointTool == "seed" && seedHit > 0) {
                removedSeed := this.SeedPoints[seedHit]
                this._PushPointUndo()
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
            if (this.EditorMode == "multi")
                this._PushPointUndo()
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
            this._PushPointUndo()
            this.Points.Push(point)
            if (isSeed)
                this.SeedPoints.Push(point)
        }
        if (this.MatchMode == "")
            this.MatchMode := this.EditorMode
        this._Render()
    }

    _CreateModePointOverlay() {
        ; 只有编辑态才画点位；原图 / 有效图要求零叠加
        if (this.ViewMode != "edit" || this.EditorMode == "original" || this.OrigW <= 0)
            return ""

        if (this.EditorMode == "super") {
            markerPoints := this.SuperSeedPoints
            markerSeeds := this.SuperSeedPoints
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

    ; 叠加层只有一个所有者：IgnoreOverlayImg 要么画超多点的忽略蒙版，要么画原图页的擦除笔迹。
    ; 两种模式互斥，所以合并成一个入口，避免两边互相清屏。
    _RefreshMaskOverlay() {
        if (!IsObject(this.ui))
            return
        if (this._rendering) {
            this._ignoreOverlayRefreshPending := true
            return
        }
        path := ""
        if (this.ViewMode == "edit" && this.OrigW > 0) {
            if (this.EditorMode == "super" && (this.IgnoreOps.Length > 0 || IsObject(this.IgnoreCurrentOp)))
                path := this._CreateIgnoreOverlay()
            else if (this.EditorMode == "original" && (this.EraseOps.Length > 0 || IsObject(this.EraseCurrentOp)))
                path := this._CreateEraseOverlay()
        }
        this._SetIgnoreOverlaySource(path)
        ; 涂抹过程中让右下角缩略图跟着变（一次性定时器，避免每 30ms 重算）
        SetTimer(this._thumbTimer, -150)
    }

    ; 只刷新缩略图，不重绘整个画布（涂抹时走这条，成本几十毫秒）
    _FlushThumb() {
        if (this.SampleMode && this.EditorMode == "original")
            return
        if (!IsObject(this.ui) || this.TemplatePath == "")
            return
        path := this._CreateEffectiveThumb()
        old := this._lastThumb
        this._lastThumb := path
        try this.ui.Update("EffectiveThumbImg", "Source", path == "" ? "" : StrReplace(path, "\", "/"))
        if (old != path)
            try FileDelete(old)
    }

    ; 兼容既有调用点
    _RefreshIgnoreOverlay() {
        this._RefreshMaskOverlay()
    }

    _CreateModeIgnoreOverlay() {
        if (this.ViewMode != "edit" || this.EditorMode != "super" || this.OrigW <= 0
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

    OnThumbClick(*) {
        if (this.SampleMode && this.EditorMode == "original") {
            showing := this.ui.Query("SampleEnlargePane>Visibility") == "Visible"
            try this.ui.Update("SampleEnlargePane", "Visibility", showing ? "Collapsed" : "Visible")
            try this.ui.Update("SampleGridPane", "Visibility", showing ? "Visible" : "Collapsed")
            return
        }
        this.SetViewMode(this.ViewMode == "effective" ? "edit" : "effective")
    }

    ; 缩略预览的选中态：外框加粗并换成强调色
    ; 右栏提示：当前状态下点保存会应用的匹配方式
    _SyncModeInfo() {
        if (!IsObject(this.ui))
            return
        lines := []
        if (this.EditorMode == "super") {
            title := GetLang("超多点")
            lines.Push(Format("{} {}", GetLang("基准点"), this.SuperSeedPoints.Length))
            lines.Push(Format("{} {}", GetLang("容差"), this.Tol))
        } else if (this.EditorMode == "multi") {
            title := GetLang("多点")
            lines.Push(Format("{} {}", GetLang("基准点"), this.SeedPoints.Length))
            lines.Push(Format("{} {}", GetLang("容差"), this.Tol))
            lines.Push(Format("{} {}", GetLang("总点数"), this.Points.Length))
        } else {
            title := this.SampleMode ? GetLang("样本抠图") : GetLang("原图")
        }
        sig := title
        for line in lines
            sig .= "|" line
        if (sig == this._modeInfoText)
            return
        this._modeInfoText := sig
        try this.ui.Update("ModeInfoTitle", "Text", title)
        for i in [1, 2, 3] {
            text := i <= lines.Length ? lines[i] : ""
            try this.ui.Update("ModeInfo" i, "Text", text)
            try this.ui.Update("ModeInfo" i, "Visibility", text == "" ? "Collapsed" : "Visible")
        }
    }

    _SyncThumbState() {
        if (!IsObject(this.ui))
            return
        active := this.ViewMode == "effective"
        try this.ui.Update("EffectiveThumbPane", "BorderThickness", active ? "3" : "1")
        try this.ui.Update("EffectiveThumbPane", "BorderBrush"
            , active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
    }

    ; 静默回到编辑态：只改状态，不触发重绘（调用方自己会 _Render）
    _ResetViewModeQuiet() {
        if (this.ViewMode == "edit")
            return
        this.ViewMode := "edit"
        this._SyncThumbState()
    }

    ; 视图互斥：edit（编辑，带叠加）/ effective（只留匹配色块）；original 保留给内部状态
    SetViewMode(mode) {
        if (this.ViewMode == mode)
            return
        this.ViewMode := mode
        this._SyncThumbState()
        this._Render()
    }

    _SyncMatchModeUi() {
        if (!IsObject(this.ui))
            return
        for name, active in Map(
            "BtnModeOriginal", this.EditorMode == "original",
            "BtnModeMultiPoint", this.EditorMode == "multi" || this.EditorMode == "super") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
        ; 勾选框状态不做程序化同步：初始态在 _Build 写死，之后只随用户操作变化
        isOriginal := this.EditorMode == "original"
        isMulti := this.EditorMode == "multi"
        isSeedMode := this.EditorMode == "super"
        ; 左栏两套内容互斥：匹配页参数 / 原图页文件与图片编辑
        try this.ui.Update("MatchControlsCon", "Visibility", isOriginal ? "Collapsed" : "Visible")
        try this.ui.Update("OriginalPanelCon", "Visibility", isOriginal ? "Visible" : "Collapsed")
        try this.ui.Update("ToolLabelCon", "Text", GetLang(isSeedMode ? "忽略蒙版" : "点位修改"))
        try this.ui.Update("LeftBottomCon", "Visibility", isOriginal ? "Collapsed" : "Visible")
        ; 样本预览和普通有效图使用独立图片源，避免延迟渲染互相覆盖。
        sampleOn := isOriginal && this.SampleMode
        try this.ui.Update("RightPane", "Visibility", sampleOn ? "Collapsed" : "Visible")
        try this.ui.Update("SampleGridPane", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("EffPanelCon", "Visibility", (sampleOn || !isOriginal) ? "Visible" : "Collapsed")
        try this.ui.Update("InfoPanelCon", "Visibility", (isOriginal && !sampleOn) ? "Visible" : "Collapsed")
        try this.ui.Update("SampleCtl1Con", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("SampleImportCon", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("SampleCtl2Con", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("BtnSampleExtract", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("SampleEnlargePane", "Visibility", "Collapsed")
        try this.ui.Update("SamplePreviewImg", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("SampleStatusText", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("SampleUnalignedText", "Visibility", sampleOn ? "Visible" : "Collapsed")
        try this.ui.Update("EffectiveThumbImg", "Visibility", sampleOn ? "Collapsed" : "Visible")
        try this.ui.Update("RightPreviewToolsCon", "Visibility", isSeedMode ? "Visible" : "Collapsed")
        try this.ui.Update("MultiPointEditToolsCon", "Visibility", isMulti ? "Visible" : "Collapsed")
        try this.ui.Update("BtnPointUndo", "Visibility", isMulti ? "Visible" : "Collapsed")
        try this.ui.Update("BtnIgnoreUndo", "Visibility", isSeedMode ? "Visible" : "Collapsed")
        try this.ui.Update("AutoPointsCon", "Visibility", isMulti ? "Visible" : "Collapsed")
        this._SyncModeInfo()
        this._SyncPointToolControls()
        this._SyncIgnoreControls()
        this._SyncOriginalToolUi()
        this._SyncCanvasActions()
        this._SyncSampleModeUi()
        this._SampleSyncControls()
    }

    _SyncSampleModeUi() {
        if (!IsObject(this.ui))
            return
        sampleOn := this.SampleMode && this.EditorMode == "original"
        enabled := sampleOn ? "False" : "True"
        try this.ui.Update("ImageEditControlsCon", "IsEnabled", enabled)
        try this.ui.Update("ImageEditControlsCon", "Opacity", sampleOn ? "0.55" : "1")
        for name in ["BtnModeOriginal", "BtnModeMultiPoint"] {
            try this.ui.Update(name, "IsEnabled", enabled)
            if (sampleOn) {
                try this.ui.Update(name, "Background", "{DynamicResource ControlBg}")
                try this.ui.Update(name, "BorderBrush", "{DynamicResource ControlBorder}")
                try this.ui.Update(name, "Foreground", "{DynamicResource TextSub}")
            }
        }
        try this.ui.Update("BtnHelp", "IsEnabled", enabled)
        try this.ui.Update("BtnHelp", "Foreground"
            , sampleOn ? "{DynamicResource TextSub}" : "{DynamicResource TextMain}")
        try this.ui.Update("BtnSampleTool", "IsEnabled", "True")
        try this.ui.Update("BtnSampleTool", "Content", sampleOn ? GetLang("退出") : GetLang("开始"))
        try this.ui.Update("BtnSampleTool", "Background"
            , sampleOn ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
        try this.ui.Update("BtnSampleTool", "BorderBrush"
            , sampleOn ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
        try this.ui.Update("BtnSampleTool", "Foreground"
            , sampleOn ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        try this.ui.Update("BtnCancel", "IsEnabled", enabled)
        try this.ui.Update("BtnCancel", "Foreground"
            , sampleOn ? "{DynamicResource TextSub}" : "{DynamicResource TextMain}")
        try this.ui.Update("BtnSure", "IsEnabled", enabled)
        try this.ui.Update("BtnSure", "Foreground"
            , sampleOn ? "{DynamicResource TextSub}" : "{DynamicResource TextMain}")
    }

    ; 顶栏「多点」：已在这一页（手工点或勾选超多点）时再点一次 = 关掉多点页
    OnModeMultiClick(*) {
        if (this.EditorMode == "multi" || this.EditorMode == "super")
            this.OnMatchMode("original")
        else
            this.OnMatchMode(this.SuperEntryChecked ? "super" : "multi")
    }

    ; 勾选框【超多点】：勾上 = 按色自动（原超多点整页并入），取消 = 手工点。
    ; 只换数据来源，算法与相似度语义沿用各自原有实现。
    OnSuperPointCheck(checked, *) {
        if (this.EditorMode != "multi" && this.EditorMode != "super")
            return
        this.SuperEntryChecked := checked
        target := checked ? "super" : "multi"
        if (this.MatchMode == target)
            return
        this.OnMatchMode(target)
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
        ; 与忽略蒙版互斥：选基准点就退出蒙版工具
        if (this.PointTool != "" && this.IgnoreTool != "")
            this._ClearIgnoreTool()
        this._SyncPointToolControls()
    }

    ; 退出忽略蒙版工具（画笔/橡皮），并清掉未完成的笔迹
    _ClearIgnoreTool() {
        if (this.IgnoreDragging)
            this._FinishIgnoreStroke()
        SetTimer(this._ignoreStrokeTimer, 0)
        this.IgnoreTool := ""
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this._SyncIgnoreControls()
        this._RefreshIgnoreOverlay()
    }

    _SyncIgnoreControls() {
        if (!IsObject(this.ui))
            return
        ; 画笔大小浮窗：选中画笔 / 橡皮时才展开
        try this.ui.Update("BrushSizePopCon", "Visibility"
            , (this.EditorMode == "super" && this.IgnoreTool != "") ? "Visible" : "Collapsed")
        for name, active in Map(
            "BtnIgnoreBrush", this.IgnoreTool == "brush",
            "BtnIgnoreEraser", this.IgnoreTool == "eraser") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
        try this.ui.Update("BtnIgnoreUndo", "IsEnabled", this.IgnoreUndo.Length > 0 ? "True" : "False")
        this._SyncCanvasActions()
    }

    OnMatchMode(requestedMode, *) {
        if (this.SampleMode && requestedMode != "original")
            this._SampleCleanupTemp()
        ; 切模式一律回到编辑态：原图/有效图只是临时查看，残留会让加点、涂抹看不到任何反馈
        this._ResetViewModeQuiet()
        ; 离开原图页时把未应用的裁剪/擦除痕迹丢掉
        if (this.OriginalTool != "" || this.EraseOps.Length > 0)
            this._ExitOriginalTool()
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


    _ExitOriginalTool() {
        if (this.EraseDragging)
            this._FinishEraseStroke()
        SetTimer(this._eraseStrokeTimer, 0)
        SetTimer(this._eraseOverlayTimer, 0)
        this.EraseDragging := false
        this.EraseCurrentOp := ""
        this.EraseTool := ""
        this.EraseOps := []
        this.Mode := ""
        this._ClearSelection()
        this._ResetCropCursor()
        this.OriginalTool := ""
    }

    ; 图片裁剪块：点一次进入框选，再点一次退出
    OnCropSectionClick(*) {
        if (!IsObject(this.ui) || this.EditorMode != "original")
            return
        if (this.SampleMode)
            this._SetSampleMode(false)
        if (this.OriginalTool == "crop") {
            this._ExitOriginalTool()
        } else {
            this._ExitOriginalTool()
            this.OriginalTool := "crop"
            this.Mode := "crop"
        }
        this._SyncOriginalToolUi()
        this._Render()
    }

    _ClearSelection() {
        this._selApplyShown := false
        this.CropDrag := ""
        this.Dragging := false
        this.DragMoved := false
        this.SelX := 0
        this.SelY := 0
        this.SelW := 0
        this.SelH := 0
        this._RefreshSelectionOverlay()
        this._SyncApplyState()
    }

    _ApplyModeStyle() {
        if (!IsObject(this.ui))
            return
        this._SyncThumbState()
        this._SyncOriginalToolUi()
        this._RefreshEraseOverlay()
    }

    ; 工具条显隐 + 选中态 + 应用按钮
    _SyncOriginalToolUi() {
        if (!IsObject(this.ui))
            return
        ; 工具按钮高亮当前激活的那个（再点一次即退出）
        for name, active in Map(
            "BtnCrop", this.Mode == "crop",
            "BtnEraseBrush", this.EraseTool == "brush",
            "BtnEraseEraser", this.EraseTool == "eraser") {
            try this.ui.Update(name, "Background", active ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update(name, "BorderBrush", active ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update(name, "Foreground", active ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
        ; 画笔大小浮窗：选中画笔或笔擦时才出现
        try this.ui.Update("BrushPopCon", "Visibility", this.EraseTool != "" ? "Visible" : "Collapsed")
        this._SyncApplyState()
    }

    ; 「应用」无选区 / 无笔迹时置灰
    _SyncApplyState() {
        if (!IsObject(this.ui))
            return
        hasSelection := this.SelW > 0 && this.SelH > 0
        hasStroke := this.EraseOps.Length > 0
        ; ✓ 只在有内容可应用时出现；出现即代表可点（不再单独设 IsEnabled）
        try this.ui.Update("BtnApply", "Visibility", hasSelection ? "Visible" : "Collapsed")
        try this.ui.Update("BtnApply", "IsEnabled", "True")
        try this.ui.Update("BtnEraseApply", "Visibility", hasStroke ? "Visible" : "Collapsed")
        try this.ui.Update("BtnEraseApply", "IsEnabled", "True")
        try this.ui.Update("BtnEraseUndo", "Visibility", hasStroke ? "Visible" : "Collapsed")
    }

    ; 中栏底右「清空」+ 撤回按钮的可用状态
    _SyncCanvasActions() {
        if (!IsObject(this.ui))
            return
        hasContent := (this.EditorMode == "super")
            ? (this.IgnoreOps.Length > 0 || this.SuperSeedPoints.Length > 0)
            : (this.Points.Length > 0)
        try this.ui.Update("BtnCanvasClear", "IsEnabled", hasContent ? "True" : "False")
        try this.ui.Update("BtnPointUndo", "IsEnabled"
            , (this.EditorMode == "multi" && this.PointUndo.Length > 0) ? "True" : "False")
        this._SyncModeInfo()
    }

    OnCanvasClear(*) {
        if (this.EditorMode == "super") {
            ; 超多点：忽略蒙版和基准点一起清
            this.OnIgnoreClear()
            this.OnClearPoints()
        } else if (this.EditorMode == "multi") {
            this.OnClearPoints()
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
        this._PushPointUndo()
        this.Points := selected
        this._Render()
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
            this._PushPointUndo()
            this.Points := []
            this.SeedPoints := []
        } else if (this.EditorMode == "super") {
            this.SuperSeedPoints := []
        } else {
            return
        }
        this.MatchMode := ""
        this._SyncCanvasActions()
        this._Render()
    }

    ; 多点页撤回：整组点位做快照，最多 20 步
    _PushPointUndo() {
        this.PointUndo.Push({points: this.Points.Clone(), seeds: this.SeedPoints.Clone()})
        if (this.PointUndo.Length > 20)
            this.PointUndo.RemoveAt(1)
        this._SyncCanvasActions()
    }

    OnPointUndo(*) {
        if (this.EditorMode != "multi" || this.PointUndo.Length < 1)
            return
        state := this.PointUndo.Pop()
        this.Points := state.points
        this.SeedPoints := state.seeds
        this._SyncCanvasActions()
        this._Render()
    }

    OnDensitySlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("DensitySlider")) ? state["DensitySlider"] : ""
        if (!IsNumber(v))
            return
        this.AutoPointDensity := Min(100, Max(0, Integer(v)))
        try this.ui.Update("DensityValueCon", "Text", String(this.AutoPointDensity))
    }

    ; ------------------------------------------------------------------
    ; ================================================================
    ; 背景擦除（原图页）：涂抹 → 透明底 PNG
    ; 只影响本窗口；落盘走与裁剪相同的替换管线，父窗口通过 CropAction 感知变化
    ; ================================================================
    ; 样本抠图：采集、对齐与原分辨率提取。
    ; Replace the active template and clear coordinates that belong to the previous image.
    OnSelectImage(*) {
        if (!IsObject(this.ui))
            return
        path := FileSelect(1, this.TemplatePath, GetLang("选择图片")
            , "Image Files (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp)")
        if (path == "")
            return
        path := StoreSearchImage(path)
        if (path == "" || !FileExist(path))
            return

        this._ReleaseFile()
        this._ExitOriginalTool()
        this.TemplatePath := path
        this.Points := []
        this.SeedPoints := []
        this.SuperSeedPoints := []
        this.SuperIgnoreData := ""
        this.IgnoreOps := []
        this.IgnoreUndo := []
        this.IgnoreTool := ""
        this.PointUndo := []
        this.MatchMode := ""
        this.EditorMode := "original"
        this.SuperEntryChecked := false
        this.NormalTolerance := 8
        this.SuperTolerance := 8
        this.Tol := 8
        this.EraseOps := []
        this.EraseTool := ""
        this.ViewMode := "edit"
        this.Zoom := 0
        this.OrigW := 0
        this.OrigH := 0
        this.ViewW := 0
        this.ViewH := 0
        this._ResetInteraction()
        this._ResetPreviewTransform()
        this._infoSig := ""
        this._modeInfoText := ""
        this._SyncControls()
        this._ApplyModeStyle()
        this._SyncMatchModeUi()
        this._Render()

        action := this.ImageSelectAction
        if (action != "")
            action(path)
    }

    OnSampleToolClick(*) {
        if (!IsObject(this.ui) || this.EditorMode != "original")
            return
        this._SetSampleMode(!this.SampleMode)
    }

    _SetSampleMode(on) {
        if (on == this.SampleMode)
            return
        this.SampleMode := on
        if (on) {
            this._ExitOriginalTool()
            SetTimer(this._thumbTimer, 0)
            this._SampleRetile()
            this._SampleRefreshPreview()
        } else {
            this._SampleCleanupTemp()
            this._Render()
        }
        this._SyncMatchModeUi()
    }

    _SampleShot(*) {
        if (!this.SampleMode || this.EditorMode != "original"
            || this._sampleShotBusy || this._sampleImportBusy || this._sampleComputing)
            return
        if (this._SampleCount() >= 60) {
            RmtDialog.Info(GetLang("样本最多 60 张"), GetLang("样本抠图"))
            return
        }
        session := this._sampleSession
        this._sampleShotBusy := true
        this._samplePickRect := ""
        this._SampleSyncControls()
        try {
            if (this.SampleFixedPos && IsObject(this.SampleShotRect))
                this._samplePickRect := this.SampleShotRect.Clone()
            else
                TogSelectArea(true, this._sampleShotAction, false)
            if (session == this._sampleSession)
                this._SampleShotPending(session)
        } catch as e {
            RmtDialog.Info(GetLang("截图处理失败：") e.Message, GetLang("样本抠图"))
        } finally {
            if (session == this._sampleSession) {
                this._samplePickRect := ""
                this._sampleShotBusy := false
                this._SampleSyncControls()
                if (!this._SampleDrainQueue() && this._samplePending)
                    SetTimer(this._sampleTimer, -1)
            }
        }
    }

    ; 框选回调只记录矩形，抓屏留到 TogSelectArea 完成清理之后。
    _SampleAreaPicked(x1, y1, x2, y2) {
        if (!this._sampleShotBusy || !this.SampleMode
            || Abs(x2 - x1) < 4 || Abs(y2 - y1) < 4)
            return
        this._samplePickRect := {x: Min(x1, x2), y: Min(y1, y2), w: Abs(x2 - x1), h: Abs(y2 - y1)}
    }

    _SampleShotPending(session) {
        if (session != this._sampleSession || !this.SampleMode || this._SampleCount() >= 60)
            return
        rect := this._samplePickRect
        if (!IsObject(rect))
            return
        bmp := 0, path := ""
        try {
            bmp := Gdip_BitmapFromScreen(rect.x "|" rect.y "|" rect.w "|" rect.h)
            if (bmp <= 0) {
                RmtDialog.Info(GetLang("截屏失败"), GetLang("样本抠图"))
                return
            }
            path := this._SampleTempPath()
            if (Gdip_SaveBitmapToFile(bmp, path) != 0) {
                RmtDialog.Info(GetLang("截屏失败"), GetLang("样本抠图"))
                return
            }
            if (session != this._sampleSession)
                return
            if (this._SampleAdd(path, rect, this.SampleFixedPos)) {
                this.SampleShotRect := rect.Clone()
                path := ""
            }
        } finally {
            if (bmp > 0)
                Gdip_DisposeImage(bmp)
            this._SampleDiscardPath(path)
        }
    }

    _SampleImport(*) {
        if (!this.SampleMode || this.EditorMode != "original"
            || this._sampleShotBusy || this._sampleImportBusy || this._sampleComputing)
            return
        if (this._SampleCount() >= 60) {
            RmtDialog.Info(GetLang("样本最多 60 张"), GetLang("样本抠图"))
            return
        }
        session := this._sampleSession
        this._sampleImportBusy := true
        this._SampleSyncControls()
        try {
            paths := FileSelect("M3", , GetLang("选择样本图片")
                , GetLang("图片文件 (*.png;*.jpg;*.jpeg;*.bmp)"))
            if (session == this._sampleSession && IsObject(paths) && paths.Length)
                this._SampleImportPaths(paths, session)
        } finally {
            if (session == this._sampleSession) {
                this._sampleImportBusy := false
                this._SampleSyncControls()
                if (!this._SampleDrainQueue() && this._samplePending)
                    SetTimer(this._sampleTimer, -1)
            }
        }
    }

    _SampleImportPaths(paths, session) {
        failed := 0, skipped := 0
        for index, source in paths {
            if (session != this._sampleSession || !this.SampleMode)
                break
            if (this._SampleCount() >= 60) {
                skipped := paths.Length - index + 1
                break
            }
            bmp := 0, path := ""
            try {
                bmp := Gdip_CreateBitmapFromFile(source)
                if (!bmp)
                    throw Error(GetLang("图片读取失败"))
                path := this._SampleTempPath()
                ; 独立 PNG 快照保留原像素，后续样本清理不接触用户文件。
                if (Gdip_SaveBitmapToFile(bmp, path) != 0 || session != this._sampleSession
                    || !this._SampleAdd(path))
                    throw Error(GetLang("图片读取失败"))
                path := ""
            } catch {
                failed += 1
            } finally {
                if (bmp)
                    Gdip_DisposeImage(bmp)
                this._SampleDiscardPath(path)
            }
        }
        if (session == this._sampleSession) {
            this._SampleRetile()
            if (failed || skipped)
                RmtDialog.Info(Format(GetLang("导入跳过：读取失败 {1} 张，超过上限 {2} 张")
                    , failed, skipped), GetLang("样本抠图"))
        }
    }

    _SampleFixedChanged(on, *) {
        this.SampleFixedPos := on
    }

    _SampleThresholdChanged(state, ctrl, event) {
        v := (IsObject(state) && state.Has("SampleThresholdSlider")) ? state["SampleThresholdSlider"] : ""
        if (!IsNumber(v))
            return
        value := Min(64, Max(0, Integer(v)))
        if (value != this.SampleThreshold) {
            this.SampleThreshold := value
        }
        try this.ui.Update("SampleThresholdVal", "Text", String(this.SampleThreshold))
        this._samplePending := true
        this._SampleSyncControls()
        SetTimer(this._sampleTimer, -150)
    }

    _SampleFlushThreshold(*) {
        if (this._samplePending && this.SampleMode) {
            this._samplePending := false
            this._SampleRefreshPreview()
        }
    }

    _SampleAdd(path, rect := "", fixed := false) {
        if (!this.SampleMode || this._SampleCount() >= 60)
            return false
        session := this._sampleSession
        w := 0, h := 0
        probe := Gdip_CreateBitmapFromFile(path)
        if (!probe)
            return false
        Gdip_GetImageDimensions(probe, &w, &h)
        Gdip_DisposeImage(probe)
        if (w < 1 || h < 1 || session != this._sampleSession || !this.SampleMode)
            return false
        this._sampleQueuedFrames.Push({Path: path, W: w, H: h, OffX: 0, OffY: 0
            , Aligned: false, Fixed: fixed, Rect: IsObject(rect) ? rect.Clone() : ""})
        if (!this._SampleDrainQueue() && !this._sampleImportBusy)
            this._SampleRetile()
        return true
    }

    _SampleCount() {
        return this.SampleFrames.Length + this._sampleQueuedFrames.Length
    }

    _SampleDrainQueue() {
        if (!this.SampleMode || this._sampleBusy || this._sampleComputing
            || this._sampleShotBusy || this._sampleImportBusy || !this._sampleQueuedFrames.Length)
            return false
        ; 只在计算快照释放后一次性提交，采集过程不使正在运行的对齐失效。
        wasCritical := A_IsCritical
        Critical "On"
        try {
            for frame in this._sampleQueuedFrames {
                frame.Aligned := this.SampleFrames.Length == 0
                if (!frame.Aligned && frame.Fixed && IsObject(frame.Rect)) {
                    baseRect := this.SampleFrames[1].Rect
                    rect := frame.Rect
                    frame.Aligned := IsObject(baseRect) && rect.x == baseRect.x && rect.y == baseRect.y
                        && rect.w == baseRect.w && rect.h == baseRect.h
                }
                frame.DeleteProp("Fixed")
                this.SampleFrames.Push(frame)
            }
            this._sampleQueuedFrames := []
            this._sampleRevision += 1
            this._sampleAlignScheduled := this.SampleFrames.Length > 1
        } finally {
            Critical wasCritical
        }
        this._SampleClearPreview()
        this._SampleRetile()
        this._SampleScheduleAlign()
        return true
    }

    _SampleDelete(i, *) {
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy
            || this._sampleQueuedFrames.Length
            || i < 1 || i > this.SampleFrames.Length)
            return
        path := this.SampleFrames[i].Path
        this._SampleDiscardReusableAlignmentEffect()
        this.SampleFrames.RemoveAt(i)
        this._sampleRevision += 1
        if (i == 1 && this.SampleFrames.Length) {
            newBase := this.SampleFrames[1]
            if (newBase.Aligned) {
                baseX := newBase.OffX, baseY := newBase.OffY
                for frame in this.SampleFrames {
                    if (frame.Aligned) {
                        frame.OffX -= baseX
                        frame.OffY -= baseY
                    } else
                        frame.OffX := 0, frame.OffY := 0
                    frame.AlignDiagnostic := ""
                }
                newBase.OffX := 0, newBase.OffY := 0
            } else {
                for idx, frame in this.SampleFrames {
                    frame.OffX := 0, frame.OffY := 0, frame.Aligned := idx == 1
                    frame.AlignDiagnostic := ""
                }
            }
        }
        this._SampleClearPreview()
        this._SampleRetile()
        this._SampleDiscardPath(path)
        this._SampleScheduleAlign()
    }

    _SampleRetile() {
        if (!IsObject(this.ui))
            return
        session := this._sampleSession
        revision := this._sampleRevision
        queuedCount := this._sampleQueuedFrames.Length
        committed := this.SampleFrames.Length
        frames := this.SampleFrames.Clone()
        for frame in this._sampleQueuedFrames
            frames.Push(frame)
        loop 60 {
            if (session != this._sampleSession || revision != this._sampleRevision
                || queuedCount != this._sampleQueuedFrames.Length)
                return
            i := A_Index
            has := i <= frames.Length
            frame := has ? frames[i] : ""
            try this.ui.Update("SampleTile" i, "Visibility", has ? "Visible" : "Collapsed")
            if (session != this._sampleSession || revision != this._sampleRevision
                || queuedCount != this._sampleQueuedFrames.Length)
                return
            if (has) {
                queued := i > committed
                try this.ui.Update("SampleThumbImg" i, "Source", StrReplace(frame.Path, "\", "/"))
                try this.ui.Update("SampleTileBorder" i, "BorderBrush"
                    , queued || frame.Aligned ? "{DynamicResource ControlBorder}" : "#FFFF3030")
                if (queued) {
                    tip := GetLang("等待对齐")
                } else if (!frame.Aligned) {
                    tip := GetLang("未对齐：计算时跳过该样本")   ; 只显示第一行，不追加诊断原因
                } else {
                    tip := ""                                 ; 已对齐（含基准）：不弹悬停提示
                }
                try this.ui.Update("SampleHitbox" i, "ToolTip", tip)
                try this.ui.Update("SampleHitbox" i, "Visibility", tip != "" ? "Visible" : "Collapsed")
                try this.ui.Update("BtnSampleDel" i, "ToolTip"
                    , Format(GetLang("删除样本 {1}"), i))
            } else {
                try this.ui.Update("SampleThumbImg" i, "Source", "")
                try this.ui.Update("SampleHitbox" i, "Visibility", "Collapsed")
            }
        }
        this._SampleSyncControls()
    }

    _SampleAlignedCount() {
        count := 0
        for frame in this.SampleFrames
            if (frame.Aligned)
                count += 1
        return count
    }

    _SampleSyncControls() {
        if (!IsObject(this.ui))
            return
        idle := !this._sampleBusy && !this._sampleComputing && !this._sampleShotBusy
            && !this._sampleImportBusy && !this._sampleQueuedFrames.Length
        canCollect := !this._sampleShotBusy && !this._sampleImportBusy
            && !this._sampleComputing && this._SampleCount() < 60
        active := this.SampleMode && this.EditorMode == "original"
        aligned := this._SampleAlignedCount()
        total := this.SampleFrames.Length
        if (this._sampleBusy)
            status := GetLang("当前状态：正在对齐")
        else if (this._sampleAlignScheduled || this._sampleQueuedFrames.Length)
            status := Format(GetLang("当前状态：等待对齐 {1}/{2}"), aligned, total)
        else if (aligned < 2)
            status := Format(GetLang("当前状态：已对齐 {1}/{2}，至少需要 2 张"), aligned, total)
        else if (this._sampleComputing || this._samplePending)
            status := Format(GetLang("当前状态：正在处理 {1}/{2}"), aligned, total)
        else if (this._samplePreviewFailedSig == (this._sampleRevision "|" this.SampleThreshold))
            status := Format(GetLang("当前状态：预览生成失败 {1}/{2}"), aligned, total)
        else if (this.SamplePreviewSig == (this._sampleRevision "|" this.SampleThreshold)
            && FileExist(this.SamplePreviewPath))
            status := Format(GetLang("当前状态：已对齐 {1}/{2}"), aligned, total)
        else
            status := Format(GetLang("当前状态：已对齐 {1}/{2}，预览待生成"), aligned, total)
        if (this._sampleQueuedFrames.Length && !this._sampleBusy)
            status .= "`n" Format(GetLang("待加入 {1} 张"), this._sampleQueuedFrames.Length)
        try this.ui.Update("SampleStatusText", "Text", status)
        unaligned := Max(0, this._SampleCount() - aligned)
        unalignedText := unaligned > 0 && !this._sampleBusy
            ? Format(GetLang("{1} 张未对齐"), unaligned) : ""
        try this.ui.Update("SampleUnalignedText", "Text", unalignedText)
        try this.ui.Update("SampleUnalignedText", "Foreground"
            , unaligned > 0 ? "#FFFF9999" : "{DynamicResource TextSub}")
        try this.ui.Update("SampleUnalignedText", "Visibility"
            , active && unaligned > 0 && !this._sampleBusy ? "Visible" : "Collapsed")
        try this.ui.Update("BtnSampleShot", "IsEnabled"
            , active && canCollect ? "True" : "False")
        try this.ui.Update("BtnSampleImport", "IsEnabled", active && canCollect ? "True" : "False")
        extractEnabled := active && idle && !this._sampleAlignScheduled && this._SampleAlignedCount() >= 2
        try this.ui.Update("BtnSampleExtract", "IsEnabled", extractEnabled ? "True" : "False")
        if (extractEnabled)
            extractTip := GetLang("生成透明底 PNG，存为新文件（分辨率 = 第 1 张样本）")
        else if (this._SampleCount() < 2)
            extractTip := GetLang("还不能提取：至少需要 2 张样本")
        else if (!idle || this._sampleAlignScheduled)
            extractTip := GetLang("还不能提取：正在处理中，请稍候")
        else
            extractTip := GetLang("还不能提取：已对齐样本不足 2 张，检查红框样本")
        try this.ui.Update("BtnSampleExtract", "ToolTip", extractTip)
        loop 60
            try this.ui.Update("BtnSampleDel" A_Index, "IsEnabled", idle ? "True" : "False")
        this._SyncSampleModeUi()
    }

    _SampleClearPreview() {
        old := this.SamplePreviewPath
        this.SamplePreviewPath := ""
        this.SamplePreviewSig := ""
        this._samplePreviewFailedSig := ""
        this._SampleDiscardReadyPreviewBitmap()
        if (IsObject(this.ui)) {
            try this.ui.Update("SamplePreviewImg", "Source", "")
            try this.ui.Update("SampleEnlargeImg", "Source", "")
        }
        if (!IsObject(this._sampleAlignmentEffectFrame)
            || this._sampleAlignmentEffectFrame.Path != old)
            this._SampleDiscardPath(old)
    }

    _SampleGetReusableAlignmentEffect(session, threshold) {
        frame := this._sampleAlignmentEffectFrame
        if (!IsObject(frame))
            return 0
        if (session != this._sampleSession || frame.Session != session
            || frame.Threshold != threshold || !this.SampleFrames.Length
            || frame.BasePath != this.SampleFrames[1].Path || !FileExist(frame.Path)) {
            this._SampleDiscardReusableAlignmentEffect()
            return 0
        }
        this._SampleCountAlignmentStat("alignmentEffectReuses")
        return frame
    }

    _SampleDiscardReusableAlignmentEffect() {
        frame := this._sampleAlignmentEffectFrame
        this._sampleAlignmentEffectFrame := 0
        if (IsObject(frame) && frame.Path != this.SamplePreviewPath)
            this._SampleDiscardPath(frame.Path)
    }

    _SampleDiscardReadyPreviewBitmap() {
        bitmap := this._sampleReadyPreviewBitmap
        this._sampleReadyPreviewBitmap := 0
        this._sampleReadyPreviewSession := -1
        this._sampleReadyPreviewRevision := -1
        this._sampleReadyPreviewThreshold := -1
        if (bitmap)
            Gdip_DisposeImage(bitmap)
    }

    _SampleTakeReadyPreviewBitmap(session, revision, threshold) {
        bitmap := this._sampleReadyPreviewBitmap
        valid := bitmap && this._sampleReadyPreviewSession == session
            && this._sampleReadyPreviewRevision == revision
            && this._sampleReadyPreviewThreshold == threshold
        this._sampleReadyPreviewBitmap := 0
        this._sampleReadyPreviewSession := -1
        this._sampleReadyPreviewRevision := -1
        this._sampleReadyPreviewThreshold := -1
        if (!valid && bitmap) {
            Gdip_DisposeImage(bitmap)
            return 0
        }
        if (valid)
            this._SampleCountAlignmentStat("effectPreviewReuses")
        return valid ? bitmap : 0
    }

    _SampleRefreshPreview() {
        if (!IsObject(this.ui) || !this.SampleMode || this.EditorMode != "original")
            return
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy
            || this._sampleAlignScheduled || this._sampleQueuedFrames.Length) {
            this._samplePending := true
            return
        }
        this._samplePending := false
        if (this._SampleAlignedCount() < 2) {
            this._SampleDiscardReusableAlignmentEffect()
            this._SampleClearPreview()
            return
        }
        threshold := this.SampleThreshold
        revision := this._sampleRevision
        session := this._sampleSession
        sig := revision "|" threshold
        if (this.SamplePreviewSig == sig && FileExist(this.SamplePreviewPath))
            return
        this._sampleComputing := true
        this._SampleSyncControls()
        pBmp := 0, rawBmp := 0, path := "", effectOrigin := {x: 0, y: 0}
        previewPublished := false
        try {
            rawBmp := this._SampleTakeReadyPreviewBitmap(session, revision, threshold)
            if (!rawBmp)
                rawBmp := this._SampleCompute(threshold)
            if (rawBmp) {
                pBmp := this._SampleCropToContent(rawBmp, effectOrigin)
                Gdip_DisposeImage(rawBmp)
                rawBmp := 0
            }
            if (!pBmp) {
                this._SampleClearPreview()
                this._samplePreviewFailedSig := sig
                return
            }
            previewPublished := this._SamplePublishPreview(
                pBmp, effectOrigin, session, revision, threshold)
            if (!previewPublished && session == this._sampleSession
                && revision == this._sampleRevision && threshold == this.SampleThreshold)
                this._samplePreviewFailedSig := sig
        } finally {
            if (rawBmp)
                Gdip_DisposeImage(rawBmp)
            if (pBmp)
                Gdip_DisposeImage(pBmp)
            this._SampleDiscardPath(path)
            this._sampleComputing := false
            this._SampleCollectGarbage()
            this._SampleSyncControls()
            if (!this._SampleDrainQueue()) {
                if (this._samplePending && this.SampleMode)
                    SetTimer(this._sampleTimer, -150)
            }
        }
    }

    _SamplePublishPreview(bitmap, origin, session, revision, threshold) {
        if (!bitmap || session != this._sampleSession || revision != this._sampleRevision
            || threshold != this.SampleThreshold || !this.SampleMode || this._sampleQueuedFrames.Length)
            return false
        path := this._SampleTempPath()
        try {
            if (Gdip_SaveBitmapToFile(bitmap, path) != 0)
                return false
            if (session != this._sampleSession || revision != this._sampleRevision
                || threshold != this.SampleThreshold || !this.SampleMode || this._sampleQueuedFrames.Length)
                return false
            old := this.SamplePreviewPath
            oldEffect := this._sampleAlignmentEffectFrame
            savedPath := path
            w := 0, h := 0
            Gdip_GetImageDimensions(bitmap, &w, &h)
            this.SamplePreviewPath := savedPath
            this.SamplePreviewSig := revision "|" threshold
            this._samplePreviewFailedSig := ""
            this._sampleAlignmentEffectFrame := {Path: savedPath, W: w, H: h
                , OffX: origin.x, OffY: origin.y, Aligned: true
                , AlphaAware: true, BasePath: this.SampleFrames[1].Path
                , Session: session, Threshold: threshold}
            try this.ui.Update("SamplePreviewImg", "Source", StrReplace(savedPath, "\", "/"))
            try this.ui.Update("SampleEnlargeImg", "Source", StrReplace(savedPath, "\", "/"))
            path := ""
            pathsToDiscard := Map()
            if (old != "" && old != savedPath)
                pathsToDiscard[old] := true
            if (IsObject(oldEffect) && oldEffect.Path != savedPath)
                pathsToDiscard[oldEffect.Path] := true
            for oldPath in pathsToDiscard
                this._SampleDiscardPath(oldPath)
            return true
        } finally {
            this._SampleDiscardPath(path)
        }
    }

    _SampleExport(*) {
        if (!this.SampleMode || this.EditorMode != "original")
            return
        if (this.SampleFrames.Length < 2) {
            RmtDialog.Info(GetLang("至少需要 2 张样本"), GetLang("样本抠图"))
            return
        }
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy
            || this._sampleAlignScheduled || this._sampleQueuedFrames.Length) {
            RmtDialog.Info(GetLang("样本处理中，请稍后再试"), GetLang("样本抠图"))
            return
        }
        if (this._SampleAlignedCount() < 2) {
            RmtDialog.Info(GetLang("至少需要 2 张已对齐样本"), GetLang("样本抠图"))
            return
        }
        dir := A_Desktop
        if (this.TemplatePath != "" && FileExist(this.TemplatePath)) {
            SplitPath(this.TemplatePath, , &dir0)
            if (DirExist(dir0))
                dir := dir0
        }
        prefix := dir "\" GetLang("样本抠图") "_" FormatTime(A_Now, "yyyyMMdd_HHmmss")
        savePath := prefix ".png"
        suffix := 1
        while (FileExist(savePath))
            savePath := prefix "_" suffix++ ".png"
        session := this._sampleSession, revision := this._sampleRevision
        threshold := this.SampleThreshold
        previewSig := revision "|" threshold
        this._sampleComputing := true
        this._SampleSyncControls()
        pBmp := 0, rawBmp := 0
        try {
            if (session != this._sampleSession || revision != this._sampleRevision
                || threshold != this.SampleThreshold)
                return
            previewSaved := false
            if (this.SamplePreviewSig == previewSig && FileExist(this.SamplePreviewPath)) {
                try {
                    FileCopy(this.SamplePreviewPath, savePath, 1)
                    previewSaved := FileExist(savePath)
                }
            }
            if (!previewSaved) {
                try FileDelete(savePath)
                rawBmp := this._SampleCompute(threshold)
                if (rawBmp) {
                    pBmp := this._SampleCropToContent(rawBmp)
                    Gdip_DisposeImage(rawBmp)
                    rawBmp := 0
                }
            }
            if (session != this._sampleSession || revision != this._sampleRevision
                || threshold != this.SampleThreshold || this._sampleQueuedFrames.Length) {
                if (previewSaved)
                    try FileDelete(savePath)
                return
            }
            if (!previewSaved && (!pBmp || Gdip_SaveBitmapToFile(pBmp, savePath) != 0)) {
                RmtDialog.Info(GetLang("提取失败"), GetLang("样本抠图"))
                return
            }
            RmtDialog.Info(GetLang("提取完成：") " " savePath, GetLang("样本抠图"))
        } finally {
            if (rawBmp)
                Gdip_DisposeImage(rawBmp)
            if (pBmp)
                Gdip_DisposeImage(pBmp)
            this._sampleComputing := false
            this._SampleCollectGarbage()
            this._SampleSyncControls()
            if (!this._SampleDrainQueue() && this._samplePending && this.SampleMode)
                SetTimer(this._sampleTimer, -150)
        }
    }

    _SampleCropToContent(bitmap, origin := 0) {
        if (!bitmap)
            return 0
        w := 0, h := 0
        Gdip_GetImageDimensions(bitmap, &w, &h)
        if (w < 1 || h < 1)
            return 0
        stride := 0, scan := 0, data := 0
        if (Gdip_LockBits(bitmap, 0, 0, w, h, &stride, &scan, &data) != 0)
            return 0
        left := w, top := h, right := -1, bottom := -1
        try {
            y := 0
            while (y < h) {
                row := scan + y * stride
                x := 0
                while (x < w) {
                    if ((NumGet(row + x * 4, "UInt") >> 24) >= 128) {
                        left := Min(left, x), right := Max(right, x)
                        top := Min(top, y), bottom := Max(bottom, y)
                    }
                    x += 1
                }
                y += 1
            }
        } finally {
            Gdip_UnlockBits(bitmap, &data)
        }
        if (right < left || bottom < top)
            return 0
        if (IsObject(origin))
            origin.x := left, origin.y := top
        return Gdip_CloneBitmapArea(bitmap, left, top, right - left + 1, bottom - top + 1)
    }

    ; 仅保留所有已对齐样本共同覆盖且颜色均匹配的像素。
    ; 返回 GDI+ 位图，调用方释放。内存中只同时保留输出和一张比较样本。
    _SampleCompute(threshold, frameSnapshot := unset, session := unset, revision := unset) {
        frames := IsSet(frameSnapshot) ? frameSnapshot : this.SampleFrames.Clone()
        session := IsSet(session) ? session : this._sampleSession
        revision := IsSet(revision) ? revision : this._sampleRevision
        if (frames.Length < 2)
            return 0
        alignedCount := 0
        for idx, frame in frames
            if (idx != 1 && frame.Aligned)
                alignedCount += 1
        if (!alignedCount)
            return 0
        base := frames[1]
        bw := base.W, bh := base.H
        pOut := Gdip_CreateBitmapFromFile(base.Path)
        if (!pOut)
            return 0
        s0 := 0, b0 := 0, d0 := 0
        outLocked := false, complete := false
        try {
            if (Gdip_LockBits(pOut, 0, 0, bw, bh, &s0, &b0, &d0) != 0)
                return 0
            outLocked := true
            observed := Buffer(bw * bh, 0)
            stable := Buffer(bw * bh, 0)
            comparisonCount := 0
            for idx, frame in frames
                if (idx != 1 && frame.Aligned)
                    comparisonCount += 1
            for idx, frame in frames {
                if (idx == 1 || !frame.Aligned)
                    continue
                if (revision != this._sampleRevision || session != this._sampleSession)
                    return 0
                bmp := Gdip_CreateBitmapFromFile(frame.Path)
                if (!bmp)
                    return 0
                si := 0, bi := 0, di := 0, locked := false
                try {
                    if (Gdip_LockBits(bmp, 0, 0, frame.W, frame.H, &si, &bi, &di) != 0)
                        return 0
                    locked := true
                    ox := frame.OffX, oy := frame.OffY
                    left := Max(0, ox), right := Min(bw, ox + frame.W)
                    top := Max(0, oy), bottom := Min(bh, oy + frame.H)
                    yy := top
                    while (yy < bottom) {
                        if (Mod(yy, 32) == 0
                            && (revision != this._sampleRevision || session != this._sampleSession))
                            return 0
                        row0 := b0 + yy * s0
                        rowI := bi + (yy - oy) * si
                        xx := left
                        while (xx < right) {
                            v0 := NumGet(row0 + xx * 4, "UInt")
                            if ((v0 >> 24) >= 128) {
                                pixel := yy * bw + xx
                                NumPut("UChar", NumGet(observed, pixel, "UChar") + 1, observed, pixel)
                                vi := NumGet(rowI + (xx - ox) * 4, "UInt")
                                if ((vi >> 24) >= 128
                                    && Max(Abs((vi & 255) - (v0 & 255))
                                        , Abs(((vi >> 8) & 255) - ((v0 >> 8) & 255))
                                        , Abs(((vi >> 16) & 255) - ((v0 >> 16) & 255))) <= threshold)
                                    NumPut("UChar", NumGet(stable, pixel, "UChar") + 1, stable, pixel)
                            }
                            xx += 1
                        }
                        yy += 1
                    }
                } finally {
                    if (locked)
                        Gdip_UnlockBits(bmp, &di)
                    Gdip_DisposeImage(bmp)
                }
            }
            yy := 0
            while (yy < bh) {
                row0 := b0 + yy * s0
                xx := 0
                while (xx < bw) {
                    v0 := NumGet(row0 + xx * 4, "UInt")
                    pixel := yy * bw + xx
                    votes := NumGet(observed, pixel, "UChar")
                    if ((v0 >> 24) < 128 || votes != comparisonCount
                        || NumGet(stable, pixel, "UChar") != votes)
                        NumPut("UInt", v0 & 0x00FFFFFF, row0 + xx * 4)
                    xx += 1
                }
                yy += 1
            }
            complete := revision == this._sampleRevision && session == this._sampleSession
            return complete ? pOut : 0
        } finally {
            if (outLocked)
                Gdip_UnlockBits(pOut, &d0)
            if (!complete)
                Gdip_DisposeImage(pOut)
        }
    }

    _SampleUpdateAlignmentEffect(bitmap, frame, threshold, session, revision, effectRegion := 0) {
        if (!bitmap || session != this._sampleSession || revision != this._sampleRevision)
            return false
        bw := 0, bh := 0
        Gdip_GetImageDimensions(bitmap, &bw, &bh)
        if (bw < 1 || bh < 1)
            return false
        sample := Gdip_CreateBitmapFromFile(frame.Path)
        if (!sample)
            return false
        sw := frame.W, sh := frame.H
        effectStride := 0, effectScan := 0, effectData := 0
        sampleStride := 0, sampleScan := 0, sampleData := 0
        effectLocked := false, sampleLocked := false
        try {
            if (Gdip_LockBits(bitmap, 0, 0, bw, bh
                , &effectStride, &effectScan, &effectData) != 0)
                return false
            effectLocked := true
            if (Gdip_LockBits(sample, 0, 0, sw, sh
                , &sampleStride, &sampleScan, &sampleData) != 0)
                return false
            sampleLocked := true
            left := IsObject(effectRegion) ? Max(0, effectRegion.OffX) : 0
            top := IsObject(effectRegion) ? Max(0, effectRegion.OffY) : 0
            right := IsObject(effectRegion)
                ? Min(bw, effectRegion.OffX + effectRegion.W) : bw
            bottom := IsObject(effectRegion)
                ? Min(bh, effectRegion.OffY + effectRegion.H) : bh
            this._SampleCountAlignmentStat("effectPixelsVisited"
                , Max(0, right - left) * Max(0, bottom - top))
            oy := top
            while (oy < bottom) {
                if (session != this._sampleSession || revision != this._sampleRevision)
                    return false
                effectRow := effectScan + oy * effectStride
                sampleY := oy - frame.OffY
                sampleRow := sampleY >= 0 && sampleY < sh
                    ? sampleScan + sampleY * sampleStride : 0
                ox := left
                while (ox < right) {
                    effectPixel := effectRow + ox * 4
                    current := NumGet(effectPixel, "UInt")
                    if ((current >> 24) >= 128) {
                        sampleX := ox - frame.OffX
                        if (!sampleRow || sampleX < 0 || sampleX >= sw) {
                            NumPut("UInt", current & 0x00FFFFFF, effectPixel)
                        } else {
                            observed := NumGet(sampleRow + sampleX * 4, "UInt")
                            if ((observed >> 24) < 128
                                || Max(Abs((observed & 255) - (current & 255))
                                    , Abs(((observed >> 8) & 255) - ((current >> 8) & 255))
                                    , Abs(((observed >> 16) & 255) - ((current >> 16) & 255))) > threshold)
                                NumPut("UInt", current & 0x00FFFFFF, effectPixel)
                        }
                    }
                    ox += 1
                }
                oy += 1
            }
            return session == this._sampleSession && revision == this._sampleRevision
        } finally {
            if (sampleLocked)
                Gdip_UnlockBits(sample, &sampleData)
            if (effectLocked)
                Gdip_UnlockBits(bitmap, &effectData)
            Gdip_DisposeImage(sample)
        }
    }

    _SampleSaveAlignmentEffect(bitmap, session, revision) {
        if (!bitmap || session != this._sampleSession || revision != this._sampleRevision)
            return 0
        origin := {x: 0, y: 0}
        cropped := this._SampleCropToContent(bitmap, origin)
        if (!cropped)
            return 0
        w := 0, h := 0
        Gdip_GetImageDimensions(cropped, &w, &h)
        path := this._SampleTempPath()
        try {
            if (Gdip_SaveBitmapToFile(cropped, path) != 0) {
                this._SampleDiscardPath(path)
                return 0
            }
            if (session != this._sampleSession || revision != this._sampleRevision) {
                this._SampleDiscardPath(path)
                return 0
            }
            return {Path: path, W: w, H: h, OffX: origin.x, OffY: origin.y
                , Aligned: true, AlphaAware: true}
        } finally {
            Gdip_DisposeImage(cropped)
        }
    }

    _SampleScheduleAlign() {
        this._sampleAlignScheduled := false
        if (this.SampleMode && this.SampleFrames.Length > 1)
            for idx, frame in this.SampleFrames
                if (idx > 1 && !frame.Aligned) {
                    this._sampleAlignScheduled := true
                    break
                }
        this._SampleSyncControls()
        if (!this._sampleAlignScheduled) {
            SetTimer(this._sampleAlignTimer, 0)
            this._SampleRefreshPreview()
            return
        }
        SetTimer(this._sampleAlignTimer, -150)
    }

    _SampleAlignPending(*) {
        if (!this.SampleMode || !IsObject(this.ui))
            return
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy) {
            this._sampleDirty := true
            SetTimer(this._sampleAlignTimer, -150)
            return
        }
        this._sampleAlignScheduled := false
        this._sampleBusy := true
        this._sampleDirty := false
        this._SampleSyncControls()
        parallelLimit := 4
        session := this._sampleSession, revision := this._sampleRevision
        stats := {startedAt: A_TickCount
            , plannedPairs: 0, executedPairs: 0, pairCacheHits: 0
            , edgeCacheHits: 0, edgeCacheBuilds: 0, fallbackPairs: 0
            , verifiedPairs: 0, fallbackSearches: 0, workerStarts: 0
            , effectBuilds: 0, effectRefreshes: 0, effectAnchoredPairs: 0
            , effectFallbackSearches: 0, effectPreviewReuses: 0, alignmentEffectReuses: 0
            , candidateConsensusAlignments: 0, adaptiveSerialBatches: 0
            , effectiveParallelLimit: 0, effectPixelsVisited: 0}
        this._sampleAlignmentStats := stats
        frames := []
        for frame in this.SampleFrames
            frames.Push(frame.Clone())
        progressEffectBitmap := 0, progressEffectFrame := 0
        progressEffectUpdates := 0, threshold := this.SampleThreshold
        alignmentEffectFrame := this._SampleGetReusableAlignmentEffect(session, threshold)
        referenceLimit := Min(12, frames.Length)
        try {
            madeProgress := true
            while (madeProgress) {
                madeProgress := false
                loop frames.Length {
                    i := A_Index
                    if (session != this._sampleSession || revision != this._sampleRevision)
                        return
                    if (i == 1 || frames[i].Aligned)
                        continue
                    refs := [1]
                    loop frames.Length {
                        j := frames.Length - A_Index + 1
                        if (j != 1 && j != i && frames[j].Aligned) {
                            if (refs.Length >= referenceLimit)
                                break
                            refs.Push(j)
                        }
                    }
                    matches := []
                    pairDiagnostics := []
                    candidateEffectFrame := IsObject(progressEffectFrame)
                        ? progressEffectFrame : alignmentEffectFrame
                    pairResults := this._SampleRunFastAlignmentBatch(
                        frames, refs, i, session, parallelLimit, candidateEffectFrame)
                    if (!IsObject(pairResults)) {
                        this._SampleCountAlignmentStat("fallbackSearches")
                        pairResults := this._SampleRunParallelAlignmentBatch(
                            frames, refs, i, session, parallelLimit)
                    }
                    if (session != this._sampleSession || revision != this._sampleRevision)
                        return
                    if (!IsObject(pairResults)) {
                        pairResults := []
                        for _, refIdx in refs {
                            this._SampleCountAlignmentStat("fallbackPairs")
                            pairDiagnostic := {refIdx: refIdx}
                            off := this._SampleGetPairAlignment(
                                frames[refIdx], frames[i], pairDiagnostic)
                            if (session != this._sampleSession || revision != this._sampleRevision)
                                return
                            pairResults.Push({refIdx: refIdx, offset: off, diagnostic: pairDiagnostic})
                        }
                    }
                    for pair in pairResults {
                        refIdx := pair.refIdx, off := pair.offset, pairDiagnostic := pair.diagnostic
                        if (IsObject(off))
                            matches.Push({ox: frames[refIdx].OffX + off.ox
                                , oy: frames[refIdx].OffY + off.oy, refIdx: refIdx
                                , score: off.score, margin: off.margin
                                , coverage: off.coverage, texture: off.texture})
                        if (IsObject(off)) {
                            pairDiagnostic.globalX := frames[refIdx].OffX + off.ox
                            pairDiagnostic.globalY := frames[refIdx].OffY + off.oy
                        }
                        if (pairDiagnostic.HasProp("candidateX")) {
                            pairDiagnostic.candidateGlobalX := frames[refIdx].OffX
                                + pairDiagnostic.candidateX
                            pairDiagnostic.candidateGlobalY := frames[refIdx].OffY
                                + pairDiagnostic.candidateY
                        }
                        pairDiagnostics.Push(pairDiagnostic)
                    }
                    resolutionDiagnostic := {}
                    aligned := this._SampleResolveAlignment(matches, resolutionDiagnostic)
                    if (!IsObject(aligned)) {
                        candidateConsensusDiagnostic := {}
                        aligned := this._SampleResolveCandidateConsensus(
                            matches, pairDiagnostics, candidateConsensusDiagnostic)
                        if (IsObject(aligned))
                            this._SampleCountAlignmentStat("candidateConsensusAlignments")
                    }
                    if (IsObject(aligned)) {
                        frames[i].OffX := aligned.ox
                        frames[i].OffY := aligned.oy
                        frames[i].Aligned := true
                        frames[i].AlignDiagnostic := ""
                        madeProgress := true
                        hasPending := this._SampleHasPendingAlignment(frames)
                        if (progressEffectBitmap) {
                            if (!this._SampleUpdateAlignmentEffect(progressEffectBitmap
                                , frames[i], threshold, session, revision, progressEffectFrame)) {
                                Gdip_DisposeImage(progressEffectBitmap)
                                progressEffectBitmap := 0
                                if (IsObject(progressEffectFrame))
                                    this._SampleDiscardPath(progressEffectFrame.Path)
                                progressEffectFrame := 0
                                progressEffectUpdates := 0
                            } else {
                                progressEffectUpdates += 1
                                if (hasPending && progressEffectUpdates >= 3) {
                                    refreshedEffect := this._SampleSaveAlignmentEffect(
                                        progressEffectBitmap, session, revision)
                                    if (IsObject(refreshedEffect)) {
                                        oldEffectPath := progressEffectFrame.Path
                                        progressEffectFrame := refreshedEffect
                                        progressEffectUpdates := 0
                                        this._SampleCountAlignmentStat("effectRefreshes")
                                        this._SampleDiscardPath(oldEffectPath)
                                    }
                                }
                            }
                        }
                        if (!progressEffectBitmap && hasPending) {
                            alignedFrameCount := 0
                            for alignedIdx, alignedFrame in frames
                                if (alignedIdx == 1 || alignedFrame.Aligned)
                                    alignedFrameCount += 1
                            if (alignedFrameCount >= 2) {
                                progressEffectBitmap := this._SampleCompute(
                                    threshold, frames, session, revision)
                                if (progressEffectBitmap) {
                                    progressEffectFrame := this._SampleSaveAlignmentEffect(
                                        progressEffectBitmap, session, revision)
                                    if (IsObject(progressEffectFrame))
                                        this._SampleCountAlignmentStat("effectBuilds")
                                    else {
                                        Gdip_DisposeImage(progressEffectBitmap)
                                        progressEffectBitmap := 0
                                    }
                                }
                            }
                        }
                    } else {
                        frames[i].AlignDiagnostic := this._SampleFormatAlignmentDiagnostic(
                            pairDiagnostics, candidateConsensusDiagnostic.HasProp("reason")
                                ? candidateConsensusDiagnostic.reason
                                : (matches.Length > 0 ? resolutionDiagnostic.reason : ""))
                    }
                }
            }
            if (session == this._sampleSession && revision == this._sampleRevision) {
                this.SampleFrames := frames
                this._sampleRevision += 1
                if (progressEffectBitmap) {
                    this._SampleDiscardReadyPreviewBitmap()
                    this._sampleReadyPreviewBitmap := progressEffectBitmap
                    this._sampleReadyPreviewSession := session
                    this._sampleReadyPreviewRevision := this._sampleRevision
                    this._sampleReadyPreviewThreshold := threshold
                    progressEffectBitmap := 0
                }
            }
        } finally {
            if (progressEffectBitmap)
                Gdip_DisposeImage(progressEffectBitmap)
            if (IsObject(progressEffectFrame))
                this._SampleDiscardPath(progressEffectFrame.Path)
            stats.totalMs := A_TickCount - stats.startedAt
            stats.startedAt := 0
            try OutputDebug("SampleAlignment " JSON.stringify(stats))
            this._sampleBusy := false
            this._SampleCollectGarbage()
            this._SampleRetile()
            if (!this._SampleDrainQueue()) {
                if (this._sampleDirty && this.SampleMode)
                    this._SampleScheduleAlign()
                else
                    this._SampleRefreshPreview()
            }
        }
    }

    _SampleHasPendingAlignment(frames) {
        for idx, frame in frames
            if (idx > 1 && !frame.Aligned)
                return true
        return false
    }

    _SampleCountAlignmentStat(name, amount := 1) {
        stats := this._sampleAlignmentStats
        if (IsObject(stats) && stats.HasProp(name))
            stats.%name% += amount
    }

    _SampleRunFastAlignmentBatch(frames, refs, sampleIdx, session, parallelLimit
        , progressEffectFrame := 0) {
        if (!refs.Length || !this.SampleMode)
            return 0
        anchorIdx := refs[1]
        anchorResults := this._SampleRunParallelAlignmentBatch(
            frames, [anchorIdx], sampleIdx, session, parallelLimit)
        if (IsObject(anchorResults) && IsObject(anchorResults[1].offset)) {
            anchor := anchorResults[1]
            targetX := frames[anchorIdx].OffX + anchor.offset.ox
            targetY := frames[anchorIdx].OffY + anchor.offset.oy
            validationTasks := []
            for refIdx in refs {
                if (refIdx == anchorIdx)
                    continue
                validationTasks.Push({refIdx: refIdx, sampleIdx: sampleIdx, mode: "verify"
                    , expectedX: targetX - frames[refIdx].OffX
                    , expectedY: targetY - frames[refIdx].OffY})
            }
            if (!validationTasks.Length)
                return anchorResults

            verified := this._SampleValidateAlignmentCandidate(frames, validationTasks
                , session, parallelLimit, anchorResults, targetX, targetY, 2)
            if (IsObject(verified))
                return verified
        }

        if (IsObject(progressEffectFrame) && refs.Length > 1) {
            effectResults := this._SampleRunProgressEffectBatch(
                frames, refs, sampleIdx, session, parallelLimit, progressEffectFrame)
            if (IsObject(effectResults))
                return effectResults
            this._SampleCountAlignmentStat("effectFallbackSearches")
        }
        return 0
    }

    _SampleRunProgressEffectBatch(frames, refs, sampleIdx, session, parallelLimit, effectFrame) {
        anchorIdx := refs[1]
        effectTask := {refIdx: anchorIdx, sampleIdx: sampleIdx, mode: "effect"
            , refRec: effectFrame}
        anchorResults := this._SampleRunPairTaskBatch(
            frames, [effectTask], session, parallelLimit)
        if (!IsObject(anchorResults) || !IsObject(anchorResults[1].offset))
            return 0

        anchor := anchorResults[1]
        targetX := effectFrame.OffX + anchor.offset.ox
        targetY := effectFrame.OffY + anchor.offset.oy
        validationTasks := []
        for refIdx in refs
            validationTasks.Push({refIdx: refIdx, sampleIdx: sampleIdx, mode: "verify"
                , expectedX: targetX - frames[refIdx].OffX
                , expectedY: targetY - frames[refIdx].OffY})

        effectOffset := {ox: targetX - frames[anchorIdx].OffX
            , oy: targetY - frames[anchorIdx].OffY
            , score: anchor.offset.score, margin: anchor.offset.margin
            , coverage: anchor.offset.coverage, texture: anchor.offset.texture}
        results := [{refIdx: anchorIdx, sampleIdx: sampleIdx
            , offset: effectOffset, diagnostic: anchor.diagnostic}]
        verified := this._SampleValidateAlignmentCandidate(frames, validationTasks
            , session, parallelLimit, [], targetX, targetY, 2, true)
        if (!IsObject(verified))
            return 0
        for result in verified
            results.Push(result)
        this._SampleCountAlignmentStat("effectAnchoredPairs")
        return results
    }

    _SampleValidateAlignmentCandidate(frames, tasks, session, parallelLimit
        , seedResults, targetX, targetY, minVotes := 2, requireBase := false) {
        results := seedResults.Clone(), matches := [], baseVerified := false
        for result in seedResults {
            ref := frames[result.refIdx]
            if (result.refIdx == 1)
                baseVerified := true
            matches.Push({ox: ref.OffX + result.offset.ox
                , oy: ref.OffY + result.offset.oy, refIdx: result.refIdx
                , score: result.offset.score, margin: result.offset.margin
                , coverage: result.offset.coverage, texture: result.offset.texture})
        }

        batchParallelLimit := this._SampleGetEffectivePairParallelLimit(
            frames, tasks, parallelLimit)
        batchSize := Min(4, batchParallelLimit)
        nextTask := 1
        while (nextTask <= tasks.Length) {
            batch := []
            loop Min(batchSize, tasks.Length - nextTask + 1) {
                batch.Push(tasks[nextTask])
                nextTask += 1
            }
            verified := this._SampleRunPairTaskBatch(
                frames, batch, session, parallelLimit)
            if (!IsObject(verified))
                return 0
            for result in verified {
                if (!IsObject(result.offset))
                    continue
                ref := frames[result.refIdx]
                results.Push(result)
                matches.Push({ox: ref.OffX + result.offset.ox
                    , oy: ref.OffY + result.offset.oy, refIdx: result.refIdx
                    , score: result.offset.score, margin: result.offset.margin
                    , coverage: result.offset.coverage, texture: result.offset.texture})
                if (result.refIdx == 1)
                    baseVerified := true
                this._SampleCountAlignmentStat("verifiedPairs")
            }

            targetVotes := 0
            for match in matches
                if (Abs(match.ox - targetX) <= 2 && Abs(match.oy - targetY) <= 2)
                    targetVotes += 1
            if (targetVotes >= minVotes && (!requireBase || baseVerified)) {
                resolutionDiagnostic := {}
                resolved := this._SampleResolveAlignment(matches, resolutionDiagnostic)
                if (IsObject(resolved) && Abs(resolved.ox - targetX) <= 2
                    && Abs(resolved.oy - targetY) <= 2)
                    return results
            }
        }
        return 0
    }

    _SampleFormatAlignmentDiagnostic(pairDiagnostics, consensusReason := "") {
        details := consensusReason != "" ? GetLang(consensusReason) : ""
        for pair in pairDiagnostics {
            reason := pair.HasProp("reason") ? pair.reason : "没有匹配候选"
            line := Format(GetLang("参考样本 {1}：{2}"), pair.refIdx, GetLang(reason))
            if (pair.HasProp("globalX"))
                line .= Format(" @ ({1},{2})", pair.globalX, pair.globalY)
            else if (pair.HasProp("candidateGlobalX"))
                line .= Format(" candidate@({1},{2})"
                    , pair.candidateGlobalX, pair.candidateGlobalY)
            if (pair.HasProp("score"))
                line .= Format(" (score={1}, margin={2}, coverage={3}, texture={4})"
                    , Round(pair.score, 3), Round(pair.margin, 3)
                    , Round(pair.coverage, 3), Round(pair.texture, 3))
            details .= (details == "" ? "" : "`n") line
        }
        return details
    }

    _SampleIsStrongAlignment(match) {
        return match.HasProp("score") && match.HasProp("margin")
            && match.HasProp("coverage") && match.HasProp("texture")
            && match.score <= 0.35 && match.margin >= Max(0.05, match.score * 0.15)
            && match.coverage >= 0.65 && match.texture >= 1
    }

    _SampleResolveCandidateConsensus(matches, pairDiagnostics, diagnostic := 0) {
        candidates := [], seenRefs := Map()
        for match in matches {
            seenRefs[match.refIdx] := true
            if (match.score <= 0.68 && match.coverage >= 0.4)
                candidates.Push(match)
        }
        for pair in pairDiagnostics {
            if (seenRefs.Has(pair.refIdx) || !pair.HasProp("candidateGlobalX")
                || !pair.HasProp("candidateGlobalY") || !pair.HasProp("score")
                || !pair.HasProp("coverage") || pair.score > 0.68 || pair.coverage < 0.4)
                continue
            candidates.Push({ox: pair.candidateGlobalX, oy: pair.candidateGlobalY
                , refIdx: pair.refIdx, score: pair.score, coverage: pair.coverage
                , texture: pair.HasProp("texture") ? pair.texture : 0})
            seenRefs[pair.refIdx] := true
        }
        if (candidates.Length < 3) {
            if (IsObject(diagnostic))
                diagnostic.reason := "参考样本候选共识不足"
            return 0
        }

        best := 0, bestCount := 0, bestStrongCount := 0, bestCost := 1.0e15
        for anchor in candidates {
            cluster := [], strongCount := 0, cost := 0
            minX := 1.0e15, maxX := -1.0e15, minY := 1.0e15, maxY := -1.0e15
            for candidate in candidates {
                if (Abs(candidate.ox - anchor.ox) > 2 || Abs(candidate.oy - anchor.oy) > 2)
                    continue
                cluster.Push(candidate)
                cost += candidate.score
                minX := Min(minX, candidate.ox), maxX := Max(maxX, candidate.ox)
                minY := Min(minY, candidate.oy), maxY := Max(maxY, candidate.oy)
                if (candidate.score <= 0.45 && candidate.coverage >= 0.65)
                    strongCount += 1
            }
            if (cluster.Length < 3 || strongCount < 1 || maxX - minX > 2 || maxY - minY > 2)
                continue
            if (cluster.Length > bestCount
                || (cluster.Length == bestCount && strongCount > bestStrongCount)
                || (cluster.Length == bestCount && strongCount == bestStrongCount
                    && cost < bestCost)) {
                best := cluster
                bestCount := cluster.Length
                bestStrongCount := strongCount
                bestCost := cost
            }
        }
        if (!IsObject(best)) {
            if (IsObject(diagnostic))
                diagnostic.reason := "参考样本候选共识不足"
            return 0
        }

        strongBaseCandidate := 0
        for match in matches
            if (match.refIdx == 1) {
                if (this._SampleIsStrongAlignment(match))
                    strongBaseCandidate := match
            }
        if (!IsObject(strongBaseCandidate))
            for pair in pairDiagnostics
                if (pair.refIdx == 1 && pair.HasProp("candidateGlobalX")
                    && pair.HasProp("candidateGlobalY") && pair.HasProp("score")
                    && pair.HasProp("coverage") && pair.score <= 0.35
                    && pair.coverage >= 0.65) {
                    strongBaseCandidate := {ox: pair.candidateGlobalX
                        , oy: pair.candidateGlobalY}
                    break
                }
        if (IsObject(strongBaseCandidate)) {
            agreesWithBase := false
            for candidate in best
                if (Abs(candidate.ox - strongBaseCandidate.ox) <= 2
                    && Abs(candidate.oy - strongBaseCandidate.oy) <= 2) {
                    agreesWithBase := true
                    break
                }
            if (!agreesWithBase) {
                if (IsObject(diagnostic))
                    diagnostic.reason := "基准与参考坐标冲突"
                return 0
            }
        }

        selected := best[1]
        for candidate in best
            if (candidate.score < selected.score
                || (candidate.score == selected.score && candidate.coverage > selected.coverage))
                selected := candidate
        return {ox: selected.ox, oy: selected.oy}
    }

    _SampleResolveAlignment(matches, diagnostic := 0) {
        if (!matches.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "没有匹配候选"
            return 0
        }
        clusters := []
        for _, match in matches {
            found := false
            for cluster in clusters {
                if (Abs(match.ox - cluster.anchor.ox) <= 3
                    && Abs(match.oy - cluster.anchor.oy) <= 3) {
                    cluster.items.Push(match)
                    found := true
                    break
                }
            }
            if (!found)
                clusters.Push({anchor: match, items: [match]})
        }
        best := 0, bestCount := 0, bestCost := 1.0e15, tied := false
        baseMatch := 0
        for match in matches
            if (match.refIdx == 1) {
                baseMatch := match
                break
            }
        for cluster in clusters {
            count := cluster.items.Length, cost := 0, includesBase := false
            minX := 1.0e15, maxX := -1.0e15, minY := 1.0e15, maxY := -1.0e15
            for match in cluster.items {
                cost += match.score
                if (match.refIdx == 1)
                    includesBase := true
                minX := Min(minX, match.ox), maxX := Max(maxX, match.ox)
                minY := Min(minY, match.oy), maxY := Max(maxY, match.oy)
            }
            if (count > bestCount
                || (count == bestCount && includesBase && !best.includesBase)
                || (count == bestCount && includesBase == best.includesBase && cost < bestCost)) {
                best := {items: cluster.items, includesBase: includesBase
                    , spreadX: maxX - minX, spreadY: maxY - minY}
                bestCount := count
                bestCost := cost
                tied := false
            } else if (count == bestCount && includesBase == best.includesBase && cost == bestCost)
                tied := true
        }
        if (tied) {
            if (IsObject(diagnostic))
                diagnostic.reason := "坐标结果冲突"
            return 0
        }
        if (best.spreadX > 2 || best.spreadY > 2) {
            if (IsObject(diagnostic))
                diagnostic.reason := "坐标结果分歧过大"
            return 0
        }
        if (IsObject(baseMatch) && !best.includesBase
            && this._SampleIsStrongAlignment(baseMatch)) {
            if (IsObject(diagnostic))
                diagnostic.reason := "基准与参考坐标冲突"
            return 0
        }
        if (!best.includesBase && bestCount < 2
            && !this._SampleIsStrongAlignment(best.items[1])) {
            if (IsObject(diagnostic))
                diagnostic.reason := "单参考结果置信度不足"
            return 0
        }
        if (best.includesBase && bestCount == 1
            && !this._SampleIsStrongAlignment(best.items[1])) {
            if (IsObject(diagnostic))
                diagnostic.reason := "基准匹配置信度不足"
            return 0
        }
        selected := best.items[1]
        for match in best.items
            if (match.score < selected.score
                || (match.score == selected.score && match.margin > selected.margin)
                || (match.score == selected.score && match.margin == selected.margin
                    && match.coverage > selected.coverage))
                selected := match
        return {ox: selected.ox, oy: selected.oy}
    }

    _SampleGetPairAlignment(refRec, sampleRec, diagnostic := 0) {
        key := refRec.Path "`n" sampleRec.Path
        cache := this._samplePairCache
        if (cache.Has(key)) {
            cached := cache[key]
            if (IsObject(diagnostic))
                for name, value in cached.Diagnostic.OwnProps()
                    diagnostic.%name% := value
            return IsObject(cached.Result) ? cached.Result.Clone() : 0
        }
        session := this._sampleSession
        details := {}
        result := this._AlignPairTo(refRec, sampleRec, details)
        if (IsObject(diagnostic))
            for name, value in details.OwnProps()
                diagnostic.%name% := value
        this._SampleStorePairAlignment(refRec, sampleRec, result, details, session)
        return result
    }

    _SampleStorePairAlignment(refRec, sampleRec, result, details, session := unset) {
        session := IsSet(session) ? session : this._sampleSession
        key := refRec.Path "`n" sampleRec.Path
        reason := details.HasProp("reason") ? details.reason : ""
        wasCritical := A_IsCritical
        Critical "On"
        try {
            if (session == this._sampleSession && this.SampleMode
                && (IsObject(result) || (reason != "" && reason != "图片读取失败"
                    && reason != "位图创建失败" && reason != "图像缩放失败" && reason != "像素读取失败")))
                this._samplePairCache[key] := {RefPath: refRec.Path, SamplePath: sampleRec.Path
                    , Result: IsObject(result) ? result.Clone() : 0, Diagnostic: details.Clone()}
        } finally {
            Critical wasCritical
        }
    }

    _SampleRunParallelAlignmentBatch(frames, refs, sampleIdx, session, parallelLimit := 4) {
        if (!refs.Length || !this.SampleMode)
            return 0
        tasks := []
        for refIdx in refs
            tasks.Push({refIdx: refIdx, sampleIdx: sampleIdx})
        return this._SampleRunPairTaskBatch(frames, tasks, session, parallelLimit)
    }

    _SampleRunPairTaskBatch(frames, tasks, session, parallelLimit := 4) {
        if (!this.SampleMode || !tasks.Length)
            return 0
        requestedParallelLimit := Min(4, Max(1, Integer(parallelLimit)))
        parallelLimit := this._SampleGetEffectivePairParallelLimit(
            frames, tasks, requestedParallelLimit)
        if (parallelLimit < requestedParallelLimit)
            this._SampleCountAlignmentStat("adaptiveSerialBatches")
        stats := this._sampleAlignmentStats
        if (IsObject(stats))
            stats.effectiveParallelLimit := Max(stats.effectiveParallelLimit, parallelLimit)
        results := [], pending := []
        results.Length := tasks.Length
        this._SampleCountAlignmentStat("plannedPairs", tasks.Length)
        for taskIndex, spec in tasks {
            refRec := spec.HasProp("refRec") ? spec.refRec : frames[spec.refIdx]
            sampleRec := frames[spec.sampleIdx]
            key := refRec.Path "`n" sampleRec.Path
            mode := spec.HasProp("mode") ? spec.mode : "align"
            if (mode == "align" && this._samplePairCache.Has(key)) {
                this._SampleCountAlignmentStat("pairCacheHits")
                diagnostic := {refIdx: spec.refIdx}
                offset := this._SampleGetPairAlignment(refRec, sampleRec, diagnostic)
                results[taskIndex] := {taskIndex: taskIndex, refIdx: spec.refIdx
                    , sampleIdx: spec.sampleIdx, offset: offset, diagnostic: diagnostic}
            } else
                pending.Push({taskIndex: taskIndex, refIdx: spec.refIdx
                    , sampleIdx: spec.sampleIdx, refRec: refRec, sampleRec: sampleRec
                    , mode: mode, cacheResult: mode == "align"
                    , expectedX: spec.HasProp("expectedX") ? spec.expectedX : 0
                    , expectedY: spec.HasProp("expectedY") ? spec.expectedY : 0})
        }
        if (!pending.Length) {
            ordered := []
            for taskIndex, spec in tasks
                ordered.Push(results[taskIndex])
            return ordered
        }
        if (!A_IsCompiled && !FileExist(this._sampleWorkerRoot "\Thread\Work.ahk"))
            return 0
        if (A_IsCompiled && !FileExist(this._sampleWorkerRoot "\Thread\Work.exe"))
            return 0

        waveResults := this._SampleRunPairWorkerBatch(pending, session, parallelLimit)
        if (!IsObject(waveResults)) {
            this._SampleStopAlignmentWorkers()
            return 0
        }
        for result in waveResults
            results[result.taskIndex] := result
        ordered := []
        for taskIndex, spec in tasks {
            if (!IsObject(results[taskIndex]))
                return 0
            ordered.Push(results[taskIndex])
        }
        return ordered
    }

    _SampleGetEffectivePairParallelLimit(frames, tasks, requestedLimit) {
        requestedLimit := Min(4, Max(1, Integer(requestedLimit)))
        if (requestedLimit <= 1)
            return requestedLimit

        maxPixels := 0
        for task in tasks {
            refRec := task.HasProp("refRec") ? task.refRec : frames[task.refIdx]
            sampleRec := frames[task.sampleIdx]
            maxPixels := Max(maxPixels, refRec.W * refRec.H, sampleRec.W * sampleRec.H)
        }

        nativeEdgeMap := !!this._SampleNativeAlignmentProc("SampleBuildEdgeMap")
        if (!nativeEdgeMap) {
            ; Without native edge-map construction, worker startup and IPC dominate small pairs.
            if (maxPixels <= 128 * 1024)
                return 1
            if (maxPixels <= 256 * 1024)
                return Min(2, requestedLimit)
        }
        return requestedLimit
    }

    _SampleRunPairWorkerBatch(pending, session, parallelLimit) {
        results := [], nextTask := 1, completedCount := 0
        try {
            workerCount := Min(parallelLimit, pending.Length)
            if (!this._SampleEnsureAlignmentWorkers(workerCount, session))
                return 0
            activeWorkers := []
            loop workerCount
                activeWorkers.Push(this._sampleAlignWorkers[A_Index])
            for worker in activeWorkers {
                if (session != this._sampleSession || !this.SampleMode)
                    return 0
                this._SampleAssignAlignmentTask(worker, pending[nextTask])
                nextTask += 1
            }

            while (completedCount < pending.Length) {
                if (session != this._sampleSession || !this.SampleMode)
                    return 0
                for worker in activeWorkers {
                    if (!worker.busy)
                        continue
                    if (FileExist(worker.resultPath)) {
                        task := worker.task
                        try {
                            response := JSON.parse(FileRead(worker.resultPath), false, false)
                            FileDelete(worker.resultPath)
                            if (response.error != "")
                                throw Error(response.error)
                            diagnostic := {refIdx: task.refIdx}
                            for name, value in response.diagnostic.OwnProps()
                                diagnostic.%name% := value
                            offset := response.match
                            if (IsObject(offset))
                                offset := {ox: offset.ox, oy: offset.oy, score: offset.score
                                    , margin: offset.margin, coverage: offset.coverage
                                    , texture: offset.texture}
                            else
                                offset := 0
                            if (task.cacheResult)
                                this._SampleStorePairAlignment(task.refRec, task.sampleRec
                                    , offset, response.diagnostic, session)
                            this._SampleCountAlignmentStat("executedPairs")
                            this._SampleCountAlignmentStat("edgeCacheHits", response.edgeCacheHits)
                            this._SampleCountAlignmentStat("edgeCacheBuilds", response.edgeCacheBuilds)
                            results.Push({taskIndex: task.taskIndex, refIdx: task.refIdx
                                , sampleIdx: task.sampleIdx, offset: offset, diagnostic: diagnostic})
                        } catch {
                            return 0
                        }
                        worker.busy := false
                        worker.task := 0
                        completedCount += 1
                        if (nextTask <= pending.Length) {
                            if (session != this._sampleSession || !this.SampleMode)
                                return 0
                            this._SampleAssignAlignmentTask(worker, pending[nextTask])
                            nextTask += 1
                        }
                        continue
                    }
                    if (!ProcessExist(worker.pid))
                        return 0
                }
                if (completedCount < pending.Length)
                    Sleep(5)
            }
            return results.Length == pending.Length ? results : 0
        } catch {
            return 0
        }
    }

    _SampleEnsureAlignmentWorkers(workerCount, session) {
        loop Min(workerCount, this._sampleAlignWorkers.Length) {
            if (!ProcessExist(this._sampleAlignWorkers[A_Index].pid)) {
                this._SampleStopAlignmentWorkers()
                break
            }
        }
        if (this._sampleWorkerDir == "") {
            this._sampleWorkerDir := A_Temp "\RMT_SampleAlign_" DllCall("GetCurrentProcessId") "_" Format("{:X}", ObjPtr(this))
            DirCreate(this._sampleWorkerDir)
        }
        while (this._sampleAlignWorkers.Length < workerCount) {
            if (session != this._sampleSession || !this.SampleMode)
                return false
            this._sampleJobSeq += 1
            prefix := this._sampleWorkerDir "\worker-" this._sampleJobSeq
            worker := {pid: 0, handle: 0, prefix: prefix
                , requestPath: prefix ".request.json", resultPath: prefix ".result.json"
                , readyPath: prefix ".ready", stopPath: prefix ".stop"
                , busy: false, task: 0}
            if (A_IsCompiled)
                command := '"' this._sampleWorkerRoot '\Thread\Work.exe"'
                    . ' --sample-align-worker "' prefix '" "4194304"'
            else
                command := '"' A_AhkPath '" "' this._sampleWorkerRoot '\Thread\Work.ahk"'
                    . ' --sample-align-worker "' prefix '" "4194304"'
            pid := 0, wasCritical := A_IsCritical
            Critical "On"
            try {
                Run(command, this._sampleWorkerRoot, "Hide", &pid)
                worker.pid := pid
                worker.handle := DllCall("OpenProcess", "uint", 0x00100001
                    , "int", false, "uint", worker.pid, "ptr")
                this._sampleAlignWorkers.Push(worker)
                this._SampleCountAlignmentStat("workerStarts")
            } finally {
                Critical wasCritical
            }
        }
        startedAt := A_TickCount
        loop {
            if (session != this._sampleSession || !this.SampleMode)
                return false
            readyCount := 0
            loop workerCount {
                worker := this._sampleAlignWorkers[A_Index]
                if (FileExist(worker.readyPath))
                    readyCount += 1
                else if (!ProcessExist(worker.pid))
                    return false
            }
            if (readyCount == workerCount)
                return true
            if (A_TickCount - startedAt > 10000)
                return false
            Sleep(10)
        }
    }

    _SampleAssignAlignmentTask(worker, task) {
        try FileDelete(worker.resultPath)
        try FileDelete(worker.requestPath)
        worker.task := task
        worker.busy := true
        jobData := Map("refPath", task.refRec.Path, "refW", task.refRec.W, "refH", task.refRec.H
            , "samplePath", task.sampleRec.Path, "sampleW", task.sampleRec.W, "sampleH", task.sampleRec.H
            , "mode", task.mode, "expectedX", task.expectedX, "expectedY", task.expectedY)
        FileAppend(JSON.stringify(jobData), worker.requestPath, "UTF-8")
    }

    _SampleStopAlignmentWorkers() {
        for worker in this._sampleAlignWorkers {
            handle := worker.handle
            if (!handle && ProcessExist(worker.pid))
                handle := DllCall("OpenProcess", "uint", 0x00100001, "int", false, "uint", worker.pid, "ptr")
            if (handle) {
                if (ProcessExist(worker.pid)) {
                    if (worker.busy)
                        DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                    else {
                        try FileAppend("stop", worker.stopPath, "UTF-8")
                        if (DllCall("WaitForSingleObject", "ptr", handle, "uint", 250, "uint") != 0)
                            DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                    }
                    DllCall("WaitForSingleObject", "ptr", handle, "uint", 1000, "uint")
                }
                DllCall("CloseHandle", "ptr", handle)
                worker.handle := 0
            }
            try FileDelete(worker.requestPath)
            try FileDelete(worker.resultPath)
            try FileDelete(worker.resultPath ".tmp")
            try FileDelete(worker.readyPath)
            try FileDelete(worker.stopPath)
        }
        this._sampleAlignWorkers := []
        if (this._sampleWorkerDir != "") {
            try DirDelete(this._sampleWorkerDir)
            this._sampleWorkerDir := ""
        }
    }

    _SampleGetAlignEdges(frame, w, h, original, diagnostic := 0) {
        alphaAware := frame.HasProp("AlphaAware") && frame.AlphaAware
        key := frame.Path "`n" (alphaAware ? "alpha-" : "")
            . (original ? "full" : w "x" h)
        cache := this._sampleEdgeCache
        this._sampleEdgeCacheTick += 1
        if (cache.Has(key)) {
            this._sampleEdgeCacheHits += 1
            cached := cache[key]
            cached.Tick := this._sampleEdgeCacheTick
            return cached.Edges
        }
        session := this._sampleSession
        bitmap := Gdip_CreateBitmapFromFile(frame.Path)
        scaled := 0
        try {
            if (!bitmap) {
                if (IsObject(diagnostic))
                    diagnostic.reason := "图片读取失败"
                return 0
            }
            if (!original) {
                scaled := Gdip_CreateBitmap(w, h)
                if (!scaled) {
                    if (IsObject(diagnostic))
                        diagnostic.reason := "位图创建失败"
                    return 0
                }
                graphics := Gdip_GraphicsFromImage(scaled)
                try {
                    Gdip_SetInterpolationMode(graphics, 7)
                    if (Gdip_DrawImage(graphics, bitmap, 0, 0, w, h) != 0) {
                        if (IsObject(diagnostic))
                            diagnostic.reason := "图像缩放失败"
                        return 0
                    }
                } finally {
                    Gdip_DeleteGraphics(graphics)
                }
            }
            edges := this._SampleBuildEdgeMapFromBitmap(
                original ? bitmap : scaled, w, h, alphaAware)
            this._sampleEdgeCacheBuilds += 1
            if (!edges.HasProp("Directions")) {
                if (IsObject(diagnostic))
                    diagnostic.reason := "像素读取失败"
                return 0
            }
            bytes := edges.Pixels.Size + edges.Directions.Size
            ; 只缓存像素缓冲区，按最近使用淘汰，避免大截图长期占用位图句柄和内存。
            limit := this.HasProp("_sampleEdgeCacheLimit")
                ? Max(0, Integer(this._sampleEdgeCacheLimit)) : 32 * 1024 * 1024
            wasCritical := A_IsCritical
            Critical "On"
            try {
                if (session == this._sampleSession && this.SampleMode && bytes <= limit) {
                    while (this._sampleEdgeCacheBytes + bytes > limit && this._sampleEdgeCache.Count) {
                        oldestKey := "", oldestTick := this._sampleEdgeCacheTick + 1
                        for entryKey, entry in this._sampleEdgeCache
                            if (entry.Tick < oldestTick)
                                oldestKey := entryKey, oldestTick := entry.Tick
                        this._sampleEdgeCacheBytes -= this._sampleEdgeCache[oldestKey].Bytes
                        this._sampleEdgeCache.Delete(oldestKey)
                    }
                    this._sampleEdgeCache[key] := {Path: frame.Path, Edges: edges
                        , Bytes: bytes, Tick: this._sampleEdgeCacheTick}
                    this._sampleEdgeCacheBytes += bytes
                }
            } finally {
                Critical wasCritical
            }
            return edges
        } finally {
            if (scaled)
                Gdip_DisposeImage(scaled)
            if (bitmap)
                Gdip_DisposeImage(bitmap)
        }
    }

    _SampleForgetAlignment(path) {
        wasCritical := A_IsCritical
        Critical "On"
        try {
            keys := []
            for key, entry in this._sampleEdgeCache
                if (entry.Path == path)
                    keys.Push(key)
            for key in keys {
                this._sampleEdgeCacheBytes -= this._sampleEdgeCache[key].Bytes
                this._sampleEdgeCache.Delete(key)
            }
            keys := []
            for key, entry in this._samplePairCache
                if (entry.RefPath == path || entry.SamplePath == path)
                    keys.Push(key)
            for key in keys
                this._samplePairCache.Delete(key)
        } finally {
            Critical wasCritical
        }
    }

    _SampleVerifyPairAtOffset(refRec, sampleRec, ox, oy, diagnostic := 0) {
        bw := refRec.W, bh := refRec.H, sw := sampleRec.W, sh := sampleRec.H
        left := Max(0, ox), right := Min(bw, ox + sw)
        top := Max(0, oy), bottom := Min(bh, oy + sh)
        if (right - left < 8 || bottom - top < 8) {
            if (IsObject(diagnostic)) {
                diagnostic.reason := "重叠范围过小"
                diagnostic.notComparable := true
            }
            return 0
        }

        edgeB := this._SampleGetAlignEdges(refRec, bw, bh, true, diagnostic)
        if (!IsObject(edgeB))
            return 0
        edgeS := this._SampleGetAlignEdges(sampleRec, sw, sh, true, diagnostic)
        if (!IsObject(edgeS))
            return 0
        if (!edgeB.Count || !edgeS.Count) {
            if (IsObject(diagnostic))
                diagnostic.reason := "缺少共同边缘"
            return 0
        }

        verified := this._RefineEdgeOffset(bw, bh, sw, sh, ox, oy, 1, edgeB, edgeS)
        if (!IsObject(verified)) {
            if (IsObject(diagnostic))
                diagnostic.reason := "候选位置无法精修"
            return 0
        }
        if (verified.score > 0.6 || verified.coverage < 0.35 || verified.texture < 0.5) {
            if (IsObject(diagnostic))
                diagnostic.reason := verified.score > 0.6 ? "匹配分数过高"
                    : verified.coverage < 0.35 ? "匹配覆盖率过低" : "匹配纹理不足"
            return 0
        }
        if (IsObject(diagnostic)) {
            diagnostic.score := verified.score
            diagnostic.margin := 0
            diagnostic.coverage := verified.coverage
            diagnostic.texture := verified.texture
            diagnostic.reason := "候选位置验证通过"
        }
        return {ox: verified.ox, oy: verified.oy, score: verified.score
            , margin: 0, coverage: verified.coverage, texture: verified.texture}
    }

    ; Effect templates contain only stable pixels, so use their multi-point anchors
    ; for a candidate offset instead of scanning every possible translation.
    _SampleAlignEffectCandidate(refRec, sampleRec, diagnostic := 0) {
        bw := refRec.W, bh := refRec.H, sw := sampleRec.W, sh := sampleRec.H
        scale := Min(64 / Max(bw, bh, sw, sh), 1.0)
        rw := Max(1, Round(bw * scale)), rh := Max(1, Round(bh * scale))
        sw2 := Max(1, Round(sw * scale)), sh2 := Max(1, Round(sh * scale))
        if (Min(rw, rh, sw2, sh2) < 4) {
            if (IsObject(diagnostic))
                diagnostic.reason := "图像尺寸不足"
            return 0
        }
        edgeB := this._SampleGetAlignEdges(refRec, rw, rh, false, diagnostic)
        if (!IsObject(edgeB))
            return 0
        edgeS := this._SampleGetAlignEdges(sampleRec, sw2, sh2, false, diagnostic)
        if (!IsObject(edgeS))
            return 0
        anchorCandidates := this._SampleMatchEdgeAnchors(edgeB, edgeS, rw, rh, sw2, sh2)
        if (!anchorCandidates.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "效果图多点候选不足"
            return 0
        }

        refinedReference := this._SampleGetAlignEdges(refRec, bw, bh, true, diagnostic)
        if (!IsObject(refinedReference))
            return 0
        refinedSample := this._SampleGetAlignEdges(sampleRec, sw, sh, true, diagnostic)
        if (!IsObject(refinedSample))
            return 0
        if (!refinedReference.Count || !refinedSample.Count) {
            if (IsObject(diagnostic))
                diagnostic.reason := "缺少共同边缘"
            return 0
        }
        refinedCandidates := []
        for candidate in anchorCandidates {
            refined := this._RefineEdgeOffset(bw, bh, sw, sh
                , Round(candidate.ox / scale), Round(candidate.oy / scale)
                , Ceil(2 / scale) + 1, refinedReference, refinedSample)
            if (IsObject(refined)) {
                refined.anchorVotes := candidate.anchorVotes
                refined.anchorMargin := candidate.anchorMargin
                this._SampleInsertAlignCandidate(refinedCandidates, refined
                    , Max(2, Ceil(0.5 / scale)), 8)
            }
        }
        if (!refinedCandidates.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "效果图候选无法精修"
            return 0
        }

        best := refinedCandidates[1]
        margin := refinedCandidates.Length > 1
            ? refinedCandidates[2].score - best.score : best.anchorMargin
        anchorVotes := best.anchorVotes
        anchorMargin := best.anchorMargin
        if (IsObject(diagnostic)) {
            diagnostic.candidateX := best.ox
            diagnostic.candidateY := best.oy
            diagnostic.score := best.score
            diagnostic.margin := margin
            diagnostic.coverage := best.coverage
            diagnostic.texture := best.texture
            diagnostic.anchorVotes := anchorVotes
            diagnostic.anchorMargin := anchorMargin
        }
        strongEdgeEvidence := refinedCandidates.Length > 1
            && best.score <= 0.38 && best.coverage >= 0.6
            && best.texture >= 8 && margin >= 0.12
        reason := ""
        if (anchorVotes < 1 && !strongEdgeEvidence)
            reason := "缺少稳定锚点"
        else if (anchorVotes == 1 && anchorMargin < 0.12)
            reason := "锚点置信度不足"
        else if (best.score > 0.6)
            reason := "匹配分数过高"
        else if (best.coverage < 0.35)
            reason := "匹配覆盖率过低"
        else if (best.texture < 0.5)
            reason := "匹配纹理不足"
        else if (margin < Max(0.04, best.score * 0.15))
            reason := "候选差距不足"
        if (reason != "") {
            if (IsObject(diagnostic))
                diagnostic.reason := reason
            return 0
        }
        if (IsObject(diagnostic))
            diagnostic.reason := "效果图多点匹配通过"
        return {ox: best.ox, oy: best.oy, score: best.score, margin: margin
            , coverage: best.coverage, texture: best.texture}
    }

    ; 忽略大面积平坦颜色，以共同边缘结构寻找平移；返回样本原点在参考图中的位置。
    _AlignPairTo(refRec, sampleRec, diagnostic := 0) {
        bw := refRec.W, bh := refRec.H, sw := sampleRec.W, sh := sampleRec.H
        scale := Min(64 / Max(bw, bh, sw, sh), 1.0)
        rw := Max(1, Round(bw * scale)), rh := Max(1, Round(bh * scale))
        sw2 := Max(1, Round(sw * scale)), sh2 := Max(1, Round(sh * scale))
        if (Min(rw, rh, sw2, sh2) < 4) {
            if (IsObject(diagnostic))
                diagnostic.reason := "图像尺寸不足"
            return 0
        }
        edgeB := this._SampleGetAlignEdges(refRec, rw, rh, false, diagnostic)
        if (!IsObject(edgeB))
            return 0
        edgeS := this._SampleGetAlignEdges(sampleRec, sw2, sh2, false, diagnostic)
        if (!IsObject(edgeS))
            return 0
        if (!edgeB.Count || !edgeS.Count) {
            if (IsObject(diagnostic))
                diagnostic.reason := "缺少共同边缘"
            return 0
        }
        anchorCandidates := this._SampleMatchEdgeAnchors(edgeB, edgeS, rw, rh, sw2, sh2)
        candidates := this._SampleSearchEdgeOffsets(edgeB, edgeS, rw, rh, sw2, sh2)
        for candidate in anchorCandidates
            this._SampleInsertAlignCandidate(candidates, candidate, 1, 8)
        if (!candidates.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "没有候选位置"
            return 0
        }
        refinedCandidates := []
        edgeBFull := this._SampleGetAlignEdges(refRec, bw, bh, true, diagnostic)
        if (!IsObject(edgeBFull))
            return 0
        edgeSFull := this._SampleGetAlignEdges(sampleRec, sw, sh, true, diagnostic)
        if (!IsObject(edgeSFull))
            return 0
        if (!edgeBFull.Count || !edgeSFull.Count) {
            if (IsObject(diagnostic))
                diagnostic.reason := "缺少共同边缘"
            return 0
        }
        for candidate in candidates {
            refined := this._RefineEdgeOffset(bw, bh, sw, sh
                , Round(candidate.ox / scale), Round(candidate.oy / scale), Ceil(2 / scale) + 1
                , edgeBFull, edgeSFull)
            if (IsObject(refined)) {
                refined.anchorVotes := candidate.HasProp("anchorVotes") ? candidate.anchorVotes : 0
                refined.anchorMargin := candidate.HasProp("anchorMargin") ? candidate.anchorMargin : 0
                this._SampleInsertAlignCandidate(refinedCandidates, refined
                    , Max(2, Ceil(0.5 / scale)), 8)
            }
        }
        if (!refinedCandidates.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "候选位置无法精修"
            return 0
        }
        best := refinedCandidates[1]
        margin := refinedCandidates.Length > 1
            ? refinedCandidates[2].score - best.score : 0
        anchorVotes := best.HasProp("anchorVotes") ? best.anchorVotes : 0
        anchorMargin := best.HasProp("anchorMargin") ? best.anchorMargin : 0
        if (IsObject(diagnostic)) {
            diagnostic.candidateX := best.ox
            diagnostic.candidateY := best.oy
            diagnostic.score := best.score
            diagnostic.margin := margin
            diagnostic.coverage := best.coverage
            diagnostic.texture := best.texture
            diagnostic.anchorVotes := anchorVotes
            diagnostic.anchorMargin := anchorMargin
        }
        strongEdgeEvidence := refinedCandidates.Length > 1
            && best.score <= 0.38 && best.coverage >= 0.6
            && best.texture >= 8 && margin >= 0.12
        reason := ""
        if (anchorVotes < 1 && !strongEdgeEvidence)
            reason := "缺少稳定锚点"
        else if (anchorVotes == 1 && anchorMargin < 0.12)
            reason := "锚点置信度不足"
        else if (best.score > 0.6)
            reason := "匹配分数过高"
        else if (best.coverage < 0.35)
            reason := "匹配覆盖率过低"
        else if (best.texture < 0.5)
            reason := "匹配纹理不足"
        else if (margin < Max(0.04, best.score * 0.15))
            reason := "候选差距不足"
        if (reason != "") {
            if (IsObject(diagnostic))
                diagnostic.reason := reason
            return 0
        }
        if (IsObject(diagnostic))
            diagnostic.reason := "匹配通过"
        return {ox: best.ox, oy: best.oy, score: best.score, margin: margin
            , coverage: best.coverage, texture: best.texture}
    }

    _SampleNativeAlignmentProc(exportName) {
        path := EnvGet("RMT_SAMPLE_ALIGN_DLL")
        if (path == "" || !FileExist(path)) {
            root := this._sampleWorkerRoot != "" ? this._sampleWorkerRoot : A_ScriptDir
            arch := A_PtrSize == 8 ? "x64" : "x86"
            path := root "\Plugins\OpenCV\" arch "\RMT_OpenCV.dll"
        }
        if (!FileExist(path))
            return 0
        if (!this._sampleNativeAlignmentModules.Has(path)) {
            module := DllCall("LoadLibraryExW", "Str", path, "Ptr", 0, "UInt", 0x8, "Ptr")
            this._sampleNativeAlignmentModules[path] := module
        }
        module := this._sampleNativeAlignmentModules[path]
        return module ? DllCall("GetProcAddress", "Ptr", module, "AStr", exportName, "Ptr") : 0
    }

    _SampleSearchEdgeOffsets(edgeB, edgeS, bw, bh, sw, sh) {
        candidates := []
        weights := this._SampleEdgeWeights()
        proc := this._SampleNativeAlignmentProc("SampleAlignEdgeOffsets")
        if (proc) {
            capacity := 8, output := Buffer(capacity * 40, 0), count := 0
            try ran := DllCall(proc
                , "Ptr", edgeB.Pixels.Ptr, "Ptr", edgeB.Directions.Ptr, "Int", bw, "Int", bh
                , "Ptr", edgeS.Pixels.Ptr, "Ptr", edgeS.Directions.Ptr, "Int", sw, "Int", sh
                , "Ptr", weights.Ptr, "Ptr", output.Ptr, "Int", capacity, "Int*", &count
                , "Cdecl Int")
            catch
                ran := 0
            if (ran) {
                loop Min(capacity, count) {
                    offset := (A_Index - 1) * 40
                    candidates.Push({ox: Round(NumGet(output, offset, "Double"))
                        , oy: Round(NumGet(output, offset + 8, "Double"))
                        , score: NumGet(output, offset + 16, "Double")
                        , coverage: NumGet(output, offset + 24, "Double")
                        , texture: NumGet(output, offset + 32, "Double")})
                }
                return candidates
            }
        }
        pixelsB := edgeB.Pixels, pixelsS := edgeS.Pixels
        directionsB := edgeB.Directions, directionsS := edgeS.Directions
        minArea := Ceil(Min(bw * bh, sw * sh) / 2)
        step := Max(1, Ceil(Max(bw, bh, sw, sh) / 24))
        offsetStep := Max(1, Ceil(Max(bw, bh, sw, sh) / 32))
        oy := -(sh - 4)
        while (oy <= bh - 4) {
            ox := -(sw - 4)
            while (ox <= bw - 4) {
                x0 := Max(1, ox), x1 := Min(bw - 1, ox + sw - 1)
                y0 := Max(1, oy), y1 := Min(bh - 1, oy + sh - 1)
                if ((x1 - x0) * (y1 - y0) >= minArea) {
                    massB := 0, massS := 0, shared := 0
                    y := y0
                    while (y < y1) {
                        x := x0
                        while (x < x1) {
                            idxB := y * bw + x, idxS := (y - oy) * sw + x - ox
                            va := NumGet(pixelsB, idxB, "UChar")
                            vb := NumGet(pixelsS, idxS, "UChar")
                            massB += va, massS += vb
                            if (va && vb) {
                                dirA := NumGet(directionsB, idxB, "UChar")
                                dirB := NumGet(directionsS, idxS, "UChar")
                                shared += Min(va, vb) * NumGet(weights, dirA * 8 + dirB, "UChar") * 0.5
                            }
                            x += step
                        }
                        y += step
                    }
                    minMass := Min(massB, massS)
                    if (minMass >= 24) {
                        coverage := shared / minMass
                        purity := (2 * shared) / Max(1, massB + massS)
                        score := 1 - (coverage * 0.7 + purity * 0.3)
                        texture := minMass / ((x1 - x0) * (y1 - y0))
                        if (coverage >= 0.2)
                            this._SampleInsertAlignCandidate(candidates
                                , {ox: ox, oy: oy, score: score, coverage: coverage
                                    , texture: texture}, Max(2, step), 8)
                    }
                }
                ox += offsetStep
            }
            oy += offsetStep
        }
        return candidates
    }

    _SampleMatchEdgeAnchors(edgeB, edgeS, bw, bh, sw, sh) {
        proc := this._SampleNativeAlignmentProc("SampleMatchEdgeAnchors")
        if (proc) {
            capacity := 8, output := Buffer(capacity * 64, 0), count := 0
            try ran := DllCall(proc
                , "Ptr", edgeB.Pixels.Ptr, "Ptr", edgeB.Directions.Ptr, "Int", bw, "Int", bh
                , "Ptr", edgeS.Pixels.Ptr, "Ptr", edgeS.Directions.Ptr, "Int", sw, "Int", sh
                , "Ptr", this._SampleEdgeWeights().Ptr
                , "Ptr", output.Ptr, "Int", capacity, "Int*", &count, "Cdecl Int")
            catch
                ran := 0
            if (ran) {
                candidates := []
                loop Min(capacity, count) {
                    offset := (A_Index - 1) * 64
                    candidates.Push({ox: Round(NumGet(output, offset, "Double"))
                        , oy: Round(NumGet(output, offset + 8, "Double"))
                        , score: NumGet(output, offset + 16, "Double")
                        , coverage: NumGet(output, offset + 24, "Double")
                        , margin: NumGet(output, offset + 32, "Double")
                        , texture: NumGet(output, offset + 40, "Double")
                        , anchorVotes: Round(NumGet(output, offset + 48, "Double"))
                        , anchorMargin: NumGet(output, offset + 56, "Double")})
                }
                return candidates
            }
        }
        minDimension := Min(bw, bh, sw, sh)
        patchSide := minDimension <= 40 || sw * sh > bw * bh
            ? Min(10, Max(4, minDimension // 3))
            : Min(8, Max(4, minDimension // 5))
        if (Min(bw, bh, sw, sh) <= patchSide + 2)
            return []
        patchArea := patchSide * patchSide
        minPatchMass := Max(24, patchArea * 2)
        weights := this._SampleEdgeWeights()
        pixelsB := edgeB.Pixels, pixelsS := edgeS.Pixels
        directionsB := edgeB.Directions, directionsS := edgeS.Directions
        massB := this._SampleEdgeIntegral(pixelsB, bw, bh)
        massSums := this._SampleEdgeIntegral(pixelsS, sw, sh)
        strideB := (bw + 1) * 4, strideS := (sw + 1) * 4
        patchBytes := patchSide * 4
        anchorStep := Max(1, patchSide // 3)
        ranked := []
        y := 1
        while (y + patchSide < bh) {
            x := 1
            while (x + patchSide < bw) {
                top := y * strideB + x * 4, bottom := top + patchSide * strideB
                mass := NumGet(massB, bottom + patchBytes, "UInt") - NumGet(massB, bottom, "UInt")
                    - NumGet(massB, top + patchBytes, "UInt") + NumGet(massB, top, "UInt")
                if (mass >= minPatchMass) {
                    pos := 1
                    while (pos <= ranked.Length && ranked[pos].mass >= mass)
                        pos += 1
                    if (pos <= 48) {
                        ranked.InsertAt(pos, {x: x, y: y, mass: mass})
                        if (ranked.Length > 48)
                            ranked.Pop()
                    }
                }
                x += anchorStep
            }
            y += anchorStep
        }
        anchors := []
        spacing := Max(3, patchSide // 2)
        for anchor in ranked {
            separated := true
            for selected in anchors {
                if (Max(Abs(anchor.x - selected.x), Abs(anchor.y - selected.y)) < spacing) {
                    separated := false
                    break
                }
            }
            if (separated) {
                anchors.Push(anchor)
                if (anchors.Length >= 8)
                    break
            }
        }
        votes := []
        for anchor in anchors {
            ; 零强度边缘不参与共享量；只预存有效像素，样本总量仍由完整窗口计算。
            points := Buffer(patchArea * 8, 0)
            pointBytes := 0, py := 0
            while (py < patchSide) {
                px := 0
                while (px < patchSide) {
                    idxB := (anchor.y + py) * bw + anchor.x + px
                    va := NumGet(pixelsB, idxB, "UChar")
                    if (va) {
                        NumPut("UInt", py * sw + px, "UChar", va
                            , "UChar", NumGet(directionsB, idxB, "UChar") * 8, points, pointBytes)
                        pointBytes += 8
                    }
                    px += 1
                }
                py += 1
            }
            matches := []
            y := 1
            while (y + patchSide < sh) {
                x := 1
                while (x + patchSide < sw) {
                    top := y * strideS + x * 4, bottom := top + patchSide * strideS
                    massS := NumGet(massSums, bottom + patchBytes, "UInt") - NumGet(massSums, bottom, "UInt")
                        - NumGet(massSums, top + patchBytes, "UInt") + NumGet(massSums, top, "UInt")
                    minMass := Min(anchor.mass, massS)
                    if (minMass >= minPatchMass) {
                        shared := 0, point := 0, origin := y * sw + x
                        while (point < pointBytes) {
                            idxS := origin + NumGet(points, point, "UInt")
                            vb := NumGet(pixelsS, idxS, "UChar")
                            if (vb) {
                                va := NumGet(points, point + 4, "UChar")
                                dirA := NumGet(points, point + 5, "UChar")
                                dirB := NumGet(directionsS, idxS, "UChar")
                                shared += Min(va, vb) * NumGet(weights, dirA + dirB, "UChar") * 0.5
                            }
                            point += 8
                        }
                        coverage := shared / minMass
                        purity := (2 * shared) / Max(1, anchor.mass + massS)
                        score := 1 - (coverage * 0.7 + purity * 0.3)
                        if (coverage >= 0.35)
                            this._SampleInsertAlignCandidate(matches
                                , {ox: x, oy: y, score: score, coverage: coverage}
                                , Max(2, patchSide // 3), 3)
                    }
                    x += 1
                }
                y += 1
            }
            if (!matches.Length)
                continue
            best := matches[1]
            margin := matches.Length > 1 ? matches[2].score - best.score : 1.0e15
            if (best.score <= 0.65 && best.coverage >= 0.4
                && margin >= Max(0.015, best.score * 0.08)) {
                votes.Push({ox: anchor.x - best.ox, oy: anchor.y - best.oy
                    , score: best.score, coverage: best.coverage, margin: margin
                    , texture: anchor.mass / patchArea})
            }
        }
        clusters := []
        for vote in votes {
            target := 0
            for cluster in clusters {
                if (Abs(vote.ox - cluster.anchor.ox) <= 2
                    && Abs(vote.oy - cluster.anchor.oy) <= 2) {
                    target := cluster
                    break
                }
            }
            if (IsObject(target))
                target.items.Push(vote)
            else
                clusters.Push({anchor: vote, items: [vote]})
        }
        candidates := []
        for cluster in clusters {
            itemCount := cluster.items.Length
            score := 0, coverage := 0, margin := 0, texture := 0, sumX := 0, sumY := 0
            for vote in cluster.items {
                score += vote.score, coverage += vote.coverage
                margin += vote.margin, texture += vote.texture
                sumX += vote.ox, sumY += vote.oy
            }
            score /= itemCount, coverage /= itemCount, margin /= itemCount, texture /= itemCount
            if ((itemCount >= 2 || (score <= 0.25 && coverage >= 0.75 && margin >= 0.12))
                && coverage >= 0.4)
                this._SampleInsertAlignCandidate(candidates
                    , {ox: Round(sumX / itemCount), oy: Round(sumY / itemCount)
                        , score: score, coverage: coverage, margin: margin, texture: texture
                        , anchorVotes: itemCount, anchorMargin: margin}
                    , 2, 8)
        }
        return candidates
    }

    _SampleEdgeIntegral(pixels, w, h) {
        stride := (w + 1) * 4
        sums := Buffer(stride * (h + 1), 0)
        y := 0
        while (y < h) {
            row := (y + 1) * stride, previous := y * stride, mass := 0
            x := 0
            while (x < w) {
                mass += NumGet(pixels, y * w + x, "UChar")
                x += 1
                NumPut("UInt", mass + NumGet(sums, previous + x * 4, "UInt"), sums, row + x * 4)
            }
            y += 1
        }
        return sums
    }

    _SampleBuildEdgeMap(scan, stride, w, h, alphaAware := false) {
        count := w * h
        gray := Buffer(count, 0)
        valid := alphaAware ? Buffer(count, 0) : 0
        raw := Buffer(count * 2, 0)
        pixels := Buffer(count, 0)
        directions := Buffer(count, 0)
        maxEdge := 0
        y := 0
        while (y < h) {
            row := scan + y * stride
            x := 0
            while (x < w) {
                value := NumGet(row + x * 4, "UInt")
                isValid := !alphaAware || (value >> 24) >= 128
                grayValue := (((value >> 16) & 255) * 77
                    + ((value >> 8) & 255) * 150 + (value & 255) * 29) >> 8
                NumPut("UChar", grayValue, gray, y * w + x)
                if (alphaAware)
                    NumPut("UChar", isValid, valid, y * w + x)
                x += 1
            }
            y += 1
        }
        y := 1
        while (y < h - 1) {
            x := 1
            while (x < w - 1) {
                idx := y * w + x
                if (alphaAware && (!NumGet(valid, idx, "UChar")
                    || !NumGet(valid, idx - 1, "UChar")
                    || !NumGet(valid, idx + 1, "UChar")
                    || !NumGet(valid, idx - w, "UChar")
                    || !NumGet(valid, idx + w, "UChar"))) {
                    x += 1
                    continue
                }
                dx := NumGet(gray, idx + 1, "UChar") - NumGet(gray, idx - 1, "UChar")
                dy := NumGet(gray, idx + w, "UChar") - NumGet(gray, idx - w, "UChar")
                gx := Abs(dx), gy := Abs(dy), edge := gx + gy
                if (gx * 2 < gy)
                    orientation := 2
                else if (gy * 2 < gx)
                    orientation := 0
                else
                    orientation := dx * dy >= 0 ? 1 : 3
                polarity := (orientation == 0 ? dx < 0
                    : orientation == 2 ? dy < 0 : dx < 0) ? 1 : 0
                direction := orientation * 2 + polarity
                NumPut("UShort", edge, raw, idx * 2)
                NumPut("UChar", direction, directions, idx)
                maxEdge := Max(maxEdge, edge)
                x += 1
            }
            y += 1
        }
        cutoff := Max(6, maxEdge * 0.08)
        mass := 0, edgeCount := 0
        if (maxEdge > cutoff) {
            y := 1
            while (y < h - 1) {
                x := 1
                while (x < w - 1) {
                    idx := y * w + x
                    edge := NumGet(raw, idx * 2, "UShort")
                    if (edge > cutoff) {
                        value := Min(255, Round((edge - cutoff) * 255 / (maxEdge - cutoff)))
                        NumPut("UChar", value, pixels, idx)
                        mass += value, edgeCount += 1
                    }
                    x += 1
                }
                y += 1
            }
        }
        return {Pixels: pixels, Directions: directions, Count: edgeCount, Mass: mass}
    }

    _SampleBuildEdgeMapFromBitmap(bitmap, w, h, alphaAware := false) {
        stride := 0, scan := 0, data := 0
        if (Gdip_LockBits(bitmap, 0, 0, w, h, &stride, &scan, &data) != 0)
            return {Pixels: Buffer(1, 0), Count: 0, Mass: 0}
        try {
            native := this._SampleBuildNativeEdgeMap(
                scan, stride, w, h, alphaAware)
            return IsObject(native)
                ? native : this._SampleBuildEdgeMap(scan, stride, w, h, alphaAware)
        }
        finally Gdip_UnlockBits(bitmap, &data)
    }

    _SampleBuildNativeEdgeMap(scan, stride, w, h, alphaAware := false) {
        proc := this._SampleNativeAlignmentProc("SampleBuildEdgeMap")
        if (!proc || w < 1 || h < 1)
            return 0
        count := w * h
        pixels := Buffer(count, 0)
        directions := Buffer(count, 0)
        edgeCount := 0, mass := Buffer(8, 0)
        try ran := DllCall(proc
            , "Ptr", scan, "Int", stride, "Int", w, "Int", h
            , "Int", alphaAware ? 1 : 0, "Ptr", pixels.Ptr, "Ptr", directions.Ptr
            , "Int*", &edgeCount, "Ptr", mass.Ptr, "Cdecl Int")
        catch
            ran := 0
        if (!ran)
            return 0
        return {Pixels: pixels, Directions: directions, Count: edgeCount
            , Mass: NumGet(mass, 0, "UInt64")}
    }

    _SampleEdgeSimilarity(dirA, dirB) {
        orientationA := dirA >> 1, orientationB := dirB >> 1
        difference := Abs(orientationA - orientationB)
        difference := Min(difference, 4 - difference)
        return difference == 0 ? 1 : difference == 1 ? 0.5 : 0
    }

    _SampleEdgeWeights() {
        static weights := 0
        if (!IsObject(weights)) {
            table := Buffer(64, 0)
            loop 8 {
                dirA := A_Index - 1
                loop 8 {
                    dirB := A_Index - 1
                    NumPut("UChar", this._SampleEdgeSimilarity(dirA, dirB) * 2, table, dirA * 8 + dirB)
                }
            }
            weights := table
        }
        return weights
    }

    _SampleInsertAlignCandidate(candidates, candidate, radius, limit) {
        for idx, current in candidates {
            if (Max(Abs(candidate.ox - current.ox), Abs(candidate.oy - current.oy)) <= radius) {
                currentVotes := current.HasProp("anchorVotes") ? current.anchorVotes : 0
                candidateVotes := candidate.HasProp("anchorVotes") ? candidate.anchorVotes : 0
                if (candidate.score > current.score
                    || (candidate.score == current.score
                        && Abs(candidate.ox) + Abs(candidate.oy) >= Abs(current.ox) + Abs(current.oy))) {
                    if (candidateVotes > currentVotes) {
                        current.anchorVotes := candidateVotes
                        current.anchorMargin := candidate.anchorMargin
                    }
                    return
                }
                if (currentVotes > candidateVotes) {
                    candidate.anchorVotes := currentVotes
                    candidate.anchorMargin := current.anchorMargin
                }
                candidates.RemoveAt(idx)
                break
            }
        }
        pos := 1
        while (pos <= candidates.Length
            && (candidates[pos].score < candidate.score
                || (candidates[pos].score == candidate.score
                    && Abs(candidates[pos].ox) + Abs(candidates[pos].oy)
                        <= Abs(candidate.ox) + Abs(candidate.oy))))
            pos += 1
        if (pos <= limit) {
            candidates.InsertAt(pos, candidate)
            if (candidates.Length > limit)
                candidates.Pop()
        }
    }

    _RefineEdgeOffset(bw, bh, sw, sh, ox0, oy0, radius, edgeB, edgeS) {
        weights := this._SampleEdgeWeights()
        proc := this._SampleNativeAlignmentProc("SampleRefineEdgeOffset")
        if (proc) {
            output := Buffer(40, 0)
            try nativeResult := DllCall(proc
                , "Ptr", edgeB.Pixels.Ptr, "Ptr", edgeB.Directions.Ptr, "Int", bw, "Int", bh
                , "Ptr", edgeS.Pixels.Ptr, "Ptr", edgeS.Directions.Ptr, "Int", sw, "Int", sh
                , "Int", ox0, "Int", oy0, "Int", radius, "Ptr", weights.Ptr
                , "Ptr", output.Ptr, "Cdecl Int")
            catch
                nativeResult := -1
            if (nativeResult >= 0) {
                if (!nativeResult)
                    return 0
                return {ox: Round(NumGet(output, 0, "Double"))
                    , oy: Round(NumGet(output, 8, "Double"))
                    , score: NumGet(output, 16, "Double")
                    , coverage: NumGet(output, 24, "Double")
                    , texture: NumGet(output, 32, "Double")}
            }
        }
        left := Max(0, ox0), right := Min(bw, ox0 + sw)
        top := Max(0, oy0), bottom := Min(bh, oy0 + sh)
        if (right - left < 8 || bottom - top < 8)
            return 0
        blockW := Min(120, right - left - radius * 2)
        blockH := Min(120, bottom - top - radius * 2)
        if (blockW < 8 || blockH < 8)
            return 0
        bx := left + (right - left - blockW) // 2
        by := top + (bottom - top - blockH) // 2
        pixelStep := Max(1, Ceil(Max(blockW, blockH) / 32))
        sampleTotal := Ceil(blockW / pixelStep) * Ceil(blockH / pixelStep)
        xs := [left + radius, bx, right - blockW - radius]
        ys := [top + radius, by, bottom - blockH - radius]
        blockStarts := [[bx, by]]
        for blockY in ys
            for blockX in xs
                if (blockX != bx || blockY != by)
                    blockStarts.Push([blockX, blockY])
        minMassRequired := Max(24, sampleTotal * 0.2)
        bestBlockScore := 1.0e15
        for blockStart in blockStarts {
            testX := blockStart[1], testY := blockStart[2]
            massTestB := 0, massTestS := 0, sharedTest := 0
            yy := 0
            while (yy < blockH) {
                xx := 0
                while (xx < blockW) {
                    idxB := (testY + yy) * bw + testX + xx
                    idxS := (testY - oy0) * sw + testX - ox0 + yy * sw + xx
                    va := NumGet(edgeB.Pixels, idxB, "UChar")
                    vb := NumGet(edgeS.Pixels, idxS, "UChar")
                    massTestB += va, massTestS += vb
                    if (va && vb) {
                        dirA := NumGet(edgeB.Directions, idxB, "UChar") * 8
                        dirB := NumGet(edgeS.Directions, idxS, "UChar")
                        sharedTest += Min(va, vb) * NumGet(weights, dirA + dirB, "UChar") * 0.5
                    }
                    xx += pixelStep
                }
                yy += pixelStep
            }
            minMassTest := Min(massTestB, massTestS)
            if (minMassTest < minMassRequired)
                continue
            coverageTest := sharedTest / minMassTest
            if (coverageTest < 0.25)
                continue
            purityTest := (2 * sharedTest) / Max(1, massTestB + massTestS)
            scoreTest := 1 - (coverageTest * 0.7 + purityTest * 0.3)
            if (scoreTest < bestBlockScore) {
                bestBlockScore := scoreTest
                bx := testX, by := testY
            }
        }
        pixelsS := edgeS.Pixels, directionsS := edgeS.Directions
        points := Buffer(sampleTotal * 8, 0)
        pointBytes := 0, massB := 0, yy := 0
        while (yy < blockH) {
            xx := 0
            while (xx < blockW) {
                idxB := (by + yy) * bw + bx + xx
                va := NumGet(edgeB.Pixels, idxB, "UChar")
                NumPut("UInt", yy * sw + xx, "UChar", va
                    , "UChar", NumGet(edgeB.Directions, idxB, "UChar") * 8, points, pointBytes)
                pointBytes += 8, massB += va
                xx += pixelStep
            }
            yy += pixelStep
        }
        bestScore := 1.0e15, bestOx := ox0, bestOy := oy0
        bestCoverage := 0, bestTexture := 0, found := false
        dy := -radius
        while (dy <= radius) {
            dx := -radius
            while (dx <= radius) {
                ox := ox0 + dx, oy := oy0 + dy
                massS := 0, shared := 0, point := 0
                ; 中心块四周已预留 radius，整个搜索范围内所有采样点均在两图内。
                origin := (by - oy) * sw + bx - ox
                while (point < pointBytes) {
                    idxS := origin + NumGet(points, point, "UInt")
                    va := NumGet(points, point + 4, "UChar")
                    vb := NumGet(pixelsS, idxS, "UChar")
                    massS += vb
                    if (va && vb) {
                        dirA := NumGet(points, point + 5, "UChar")
                        dirB := NumGet(directionsS, idxS, "UChar")
                        shared += Min(va, vb) * NumGet(weights, dirA + dirB, "UChar") * 0.5
                    }
                    point += 8
                }
                minMass := Min(massB, massS)
                if (minMass >= minMassRequired) {
                    coverage := shared / minMass
                    purity := (2 * shared) / Max(1, massB + massS)
                    score := 1 - (coverage * 0.7 + purity * 0.3)
                    texture := minMass / sampleTotal
                    if (coverage >= 0.25 && (score < bestScore
                        || (score == bestScore
                            && Abs(dx) + Abs(dy) < Abs(bestOx - ox0) + Abs(bestOy - oy0)))) {
                        bestScore := score
                        bestOx := ox, bestOy := oy
                        bestCoverage := coverage
                        bestTexture := texture
                        found := true
                    }
                }
                dx += 1
            }
            dy += 1
        }
        return found
            ? {ox: bestOx, oy: bestOy, score: bestScore
                , coverage: bestCoverage, texture: bestTexture} : 0
    }

    ; 从预测重叠区取中心块；LockBits 返回的 Scan0 从锁定区域左上角开始。
    _RefineOffset(pB, pS, bw, bh, sw, sh, ox0, oy0, radius) {
        left := Max(0, ox0), right := Min(bw, ox0 + sw)
        top := Max(0, oy0), bottom := Min(bh, oy0 + sh)
        if (right - left < 4 || bottom - top < 4)
            return 0
        blockW := Min(120, Max(4, right - left - radius * 2))
        blockH := Min(120, Max(4, bottom - top - radius * 2))
        bx := left + (right - left - blockW) // 2
        by := top + (bottom - top - blockH) // 2
        s0 := 0, b0 := 0, d0 := 0
        s1 := 0, b1 := 0, d1 := 0
        if (Gdip_LockBits(pB, bx, by, blockW, blockH, &s0, &b0, &d0) != 0)
            return 0
        lockedS := false
        try {
            rx := bx - ox0 - radius, ry := by - oy0 - radius
            clipX := Max(0, rx), clipY := Max(0, ry)
            clipW := Min(sw, rx + blockW + radius * 2) - clipX
            clipH := Min(sh, ry + blockH + radius * 2) - clipY
            if (clipW <= 0 || clipH <= 0
                || Gdip_LockBits(pS, clipX, clipY, clipW, clipH, &s1, &b1, &d1) != 0)
                return 0
            lockedS := true
            pixelStep := Max(1, Ceil(Max(blockW, blockH) / 32))
            textureCount := 0, sumR := 0, sumG := 0, sumB := 0
            sumR2 := 0, sumG2 := 0, sumB2 := 0
            yy := 0
            while (yy < blockH) {
                rowB := b0 + yy * s0
                xx := 0
                while (xx < blockW) {
                    vb := NumGet(rowB + xx * 4, "UInt")
                    if ((vb >> 24) >= 128) {
                        b := vb & 255, g := (vb >> 8) & 255, r := (vb >> 16) & 255
                        sumR += r, sumG += g, sumB += b
                        sumR2 += r * r, sumG2 += g * g, sumB2 += b * b
                        textureCount += 1
                    }
                    xx += pixelStep
                }
                yy += pixelStep
            }
            if (textureCount < 4)
                return 0
            varianceR := Max(0, sumR2 / textureCount - (sumR / textureCount) ** 2)
            varianceG := Max(0, sumG2 / textureCount - (sumG / textureCount) ** 2)
            varianceB := Max(0, sumB2 / textureCount - (sumB / textureCount) ** 2)
            texture := Max(Sqrt(varianceR), Sqrt(varianceG), Sqrt(varianceB))
            if (texture < 4)
                return 0
            sampleTotal := Ceil(blockW / pixelStep) * Ceil(blockH / pixelStep)
            bestScore := 1.0e15, bestOx := ox0, bestOy := oy0
            bestCoverage := 0
            found := false
            dy := -radius
            while (dy <= radius) {
                dx := -radius
                while (dx <= radius) {
                    ox := ox0 + dx, oy := oy0 + dy
                    lx0 := bx - ox - clipX, ly0 := by - oy - clipY
                    if (lx0 < 0 || ly0 < 0 || lx0 + blockW > clipW || ly0 + blockH > clipH) {
                        dx += 1
                        continue
                    }
                    sad := 0, count := 0
                    yy := 0
                    while (yy < blockH) {
                        rowB := b0 + yy * s0
                        rowS := b1 + (ly0 + yy) * s1 + lx0 * 4
                        xx := 0
                        while (xx < blockW) {
                            vb := NumGet(rowB + xx * 4, "UInt")
                            vs := NumGet(rowS + xx * 4, "UInt")
                            if ((vb >> 24) >= 128 && (vs >> 24) >= 128) {
                                sad += Abs((vb & 255) - (vs & 255))
                                    + Abs(((vb >> 8) & 255) - ((vs >> 8) & 255))
                                    + Abs(((vb >> 16) & 255) - ((vs >> 16) & 255))
                                count += 1
                            }
                            xx += pixelStep
                        }
                        yy += pixelStep
                    }
                    if (count >= Max(4, Ceil(sampleTotal * 0.5))) {
                        score := sad / (count * 3)
                        if (score < bestScore || (score == bestScore
                            && Abs(ox - ox0) + Abs(oy - oy0) < Abs(bestOx - ox0) + Abs(bestOy - oy0))) {
                            bestScore := score
                            bestOx := ox, bestOy := oy
                            bestCoverage := count / sampleTotal
                            found := true
                        }
                    }
                    dx += 1
                }
                dy += 1
            }
            ; 平均每通道差超过 32 时拒绝，不能把最小误差等同于可靠对齐。
            return found && bestScore <= 32
                ? {ox: bestOx, oy: bestOy, score: bestScore
                    , coverage: bestCoverage, texture: texture} : 0
        } finally {
            if (lockedS)
                Gdip_UnlockBits(pS, &d1)
            Gdip_UnlockBits(pB, &d0)
        }
    }

    _SampleTempPath() {
        this._sampleSeq += 1
        path := (A_Temp "\RMT_sample_" DllCall("GetCurrentProcessId") "_" this._windowToken
            "_" A_TickCount "_" this._sampleSeq ".png")
        this._sampleTemp.Push(path)
        return path
    }

    _SampleDiscardPath(path) {
        if (path == "")
            return
        this._SampleForgetAlignment(path)
        try FileDelete(path)
        if (FileExist(path))
            this._sampleGarbage.Push(path)
    }

    _SampleCollectGarbage() {
        remaining := []
        for path in this._sampleGarbage {
            try FileDelete(path)
            if (FileExist(path))
                remaining.Push(path)
        }
        this._sampleGarbage := remaining
    }

    _SampleCleanupTemp() {
        this._sampleSession += 1
        this._sampleRevision += 1
        this._SampleStopAlignmentWorkers()
        this._samplePairCache := Map()
        this._sampleEdgeCache := Map()
        this._sampleEdgeCacheBytes := 0
        this._sampleEdgeCacheTick := 0
        this.SampleMode := false
        SetTimer(this._sampleTimer, 0)
        SetTimer(this._sampleAlignTimer, 0)
        if (this._sampleShotBusy)
            try TogSelectArea(false)
        this._sampleShotBusy := false
        this._sampleImportBusy := false
        this._sampleAlignScheduled := false
        this._samplePending := false
        this._sampleDirty := false
        this._samplePickRect := ""
        this.SampleShotRect := ""
        this._SampleDiscardReusableAlignmentEffect()
        this._SampleClearPreview()
        paths := this._sampleTemp
        for frame in this.SampleFrames
            paths.Push(frame.Path)
        for frame in this._sampleQueuedFrames
            paths.Push(frame.Path)
        this.SampleFrames := []
        this._sampleQueuedFrames := []
        this._sampleTemp := []
        this._SampleRetile()
        for path in paths
            this._SampleDiscardPath(path)
        this._SampleCollectGarbage()
    }

    ; 抠除-画笔：进入涂抹；再点一次退出；从笔擦切回画笔
    OnEraseSectionClick(*) {
        if (!IsObject(this.ui) || this.EditorMode != "original")
            return
        if (this.SampleMode)
            this._SetSampleMode(false)
        if (this.OriginalTool != "erase") {
            this._ExitOriginalTool()
            this.OriginalTool := "erase"
            this.EraseTool := "brush"
        } else if (this.EraseTool == "brush") {
            this._ExitOriginalTool()
        } else {
            this.EraseTool := "brush"
        }
        this._SyncOriginalToolUi()
        this._RefreshEraseOverlay()
    }

    ; 抠除-笔擦：擦掉已涂抹的区域；再点一次退出
    OnEraseEraserClick(*) {
        if (!IsObject(this.ui) || this.EditorMode != "original")
            return
        if (this.SampleMode)
            this._SetSampleMode(false)
        if (this.OriginalTool != "erase") {
            this._ExitOriginalTool()
            this.OriginalTool := "erase"
            this.EraseTool := "eraser"
        } else if (this.EraseTool == "eraser") {
            this._ExitOriginalTool()
        } else {
            this.EraseTool := "eraser"
        }
        this._SyncOriginalToolUi()
        this._RefreshEraseOverlay()
    }

    OnEraseBrushSlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("EraseBrushSlider")) ? state["EraseBrushSlider"] : ""
        if (!IsNumber(v))
            return
        this.EraseBrushSize := Max(1, Min(8, Integer(v)))
        try this.ui.Update("EraseBrushVal", "Text", String(this.EraseBrushSize))
    }

    _EraseDown(state) {
        canvasPoint := this._XY(state, "R")
        imagePoint := this._IgnoreImagePoint(canvasPoint)
        if (!IsObject(imagePoint))
            return

        this.EraseDragging := true
        this.EraseCurrentOp := { type: "stroke", erase: this.EraseTool == "eraser"
            , size: this.EraseBrushSize, points: [imagePoint] }
        SetTimer(this._eraseStrokeTimer, 16)
        SetTimer(this._eraseOverlayTimer, 80)
        this._RefreshEraseOverlay()
    }

    _FlushEraseOverlay(*) {
        this._RefreshEraseOverlay()
    }

    _PollEraseStroke(*) {
        if (!this.EraseDragging || !IsObject(this.EraseCurrentOp))
            return
        imagePoint := this._IgnoreImagePoint(this._RightCanvasPoint())
        if (IsObject(imagePoint))
            this._AppendErasePoint(imagePoint)
        if (!(DllCall("GetAsyncKeyState", "Int", 0x01, "Short") & 0x8000))
            this._FinishEraseStroke()
    }

    _AppendErasePoint(imagePoint) {
        points := this.EraseCurrentOp.points
        last := points[points.Length]
        dx := imagePoint.x - last.x
        dy := imagePoint.y - last.y
        steps := Max(Abs(dx), Abs(dy))
        loop steps {
            x := Round(last.x + dx * A_Index / steps)
            y := Round(last.y + dy * A_Index / steps)
            previous := points[points.Length]
            if (previous.x != x || previous.y != y)
                points.Push({ x: x, y: y })
        }
    }

    _FinishEraseStroke() {
        if (!this.EraseDragging || !IsObject(this.EraseCurrentOp))
            return
        SetTimer(this._eraseStrokeTimer, 0)
        SetTimer(this._eraseOverlayTimer, 0)
        operation := this.EraseCurrentOp
        this.EraseDragging := false
        this.EraseCurrentOp := ""
        if (operation.points.Length < 1)
            return
        this.EraseOps.Push(operation)
        this._SyncEraseControls()
        this._RefreshEraseOverlay()
    }

    OnEraseUndo(*) {
        if (this.EraseOps.Length < 1)
            return
        this.EraseOps.RemoveAt(this.EraseOps.Length)
        this._SyncEraseControls()
        this._RefreshEraseOverlay()
    }

    ; 兼容既有调用点：笔迹数量变化后统一刷新工具条可用状态
    _SyncEraseControls() {
        if (!IsObject(this.ui))
            return
        this._SyncOriginalToolUi()
    }

    _RefreshEraseOverlay() {
        this._RefreshMaskOverlay()
    }

    ; 裁剪光标：手柄上给缩放光标、选区内给移动光标、其余十字
    _UpdateCropCursor(p) {
        if (!IsObject(this.ui))
            return
        hit := this._CropHit(p)
        cursor := "Cross"
        if (hit == "TL" || hit == "BR")
            cursor := "SizeNWSE"
        else if (hit == "TR" || hit == "BL")
            cursor := "SizeNESW"
        else if (hit == "move")
            cursor := "SizeAll"
        if (cursor == this._cropCursor)
            return
        this._cropCursor := cursor
        try this.ui.Update("RightCanvas", "Cursor", cursor)
    }

    _ResetCropCursor() {
        if (this._cropCursor == "")
            return
        this._cropCursor := ""
        if (IsObject(this.ui))
            try this.ui.Update("RightCanvas", "Cursor", "Arrow")
    }

    ; 裁剪选区叠加层：实时画黄框 + 四角手柄（与 DLL drawDecorations 同款样式），
    ; 拖动期间不整图重渲，松手后 _Render 把选区烘进底图
    _RefreshSelectionOverlay() {
        if (!IsObject(this.ui))
            return
        path := ""
        if (this.SelW > 0 && this.SelH > 0)
            path := this._CreateSelectionOverlay()
        try this.ui.Update("CropOverlayImg", "Source", path == "" ? "" : StrReplace(path, "\", "/"))
        if (this._lastSelOverlay != "" && this._lastSelOverlay != path)
            try FileDelete(this._lastSelOverlay)
        this._lastSelOverlay := path
    }

    _CreateSelectionOverlay() {
        this._selOverlaySeq += 1
        output := A_Temp "\RMT_fe_sel_" A_TickCount "_" this._windowToken "_" this._selOverlaySeq ".png"
        bitmap := 0, graphics := 0, pen := 0, handleBrush := 0
        try {
            ; 与 DLL 的网格线同一套取整规则（pasteX + Round(i * zoom)），否则框线会压在像素中间
            zF := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
            vX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
            vY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
            layout := this._ViewLayout(zF)
            x1 := Round(layout.offsetX + (this.SelX - vX) * zF)
            y1 := Round(layout.offsetY + (this.SelY - vY) * zF)
            x2 := Round(layout.offsetX + (this.SelX + this.SelW - vX) * zF)
            y2 := Round(layout.offsetY + (this.SelY + this.SelH - vY) * zF)
            rw := Max(1, x2 - x1)
            rh := Max(1, y2 - y1)
            bitmap := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!bitmap)
                return ""
            graphics := Gdip_GraphicsFromImage(bitmap)
            if (!graphics)
                return ""
            Gdip_SetSmoothingMode(graphics, 0)
            pen := Gdip_CreatePen(0xFF00DCFF, 1)
            handleBrush := Gdip_BrushCreateSolid(0xFF00DCFF)
            if (!pen || !handleBrush)
                return ""
            Gdip_DrawRectangle(graphics, pen, x1, y1, rw, rh)
            hs := 4
            for dx in [0, rw]
                for dy in [0, rh]
                    Gdip_FillRectangle(graphics, handleBrush, x1 + dx - hs, y1 + dy - hs, hs * 2 + 1, hs * 2 + 1)
            if (Gdip_SaveBitmapToFile(bitmap, output) != 0) {
                try FileDelete(output)
                return ""
            }
            return output
        } catch {
            try FileDelete(output)
            return ""
        } finally {
            if (handleBrush)
                try Gdip_DeleteBrush(handleBrush)
            if (pen)
                try Gdip_DeletePen(pen)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (bitmap)
                try Gdip_DisposeImage(bitmap)
        }
    }

    _CreateEraseOverlay() {
        this._eraseOverlaySeq += 1
        output := A_Temp "\RMT_fe_erase_" A_TickCount "_" this._windowToken "_" this._eraseOverlaySeq ".png"
        bitmap := 0, graphics := 0, brush := 0, clearBrush := 0
        try {
            bitmap := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!bitmap)
                return ""
            graphics := Gdip_GraphicsFromImage(bitmap)
            if (!graphics)
                return ""
            brush := Gdip_BrushCreateSolid(0x90FF7A18)
            clearBrush := Gdip_BrushCreateSolid(0x00000000)
            if (!brush || !clearBrush)
                return ""
            Gdip_GraphicsClear(graphics, 0x00000000)
            Gdip_SetSmoothingMode(graphics, 0)

            overlayZoom := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
            overlayViewX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
            overlayViewY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
            layout := this._ViewLayout(overlayZoom)

            for operation in this.EraseOps
                this._DrawEraseStroke(graphics, brush, clearBrush
                    , operation, layout, overlayViewX, overlayViewY)
            if (IsObject(this.EraseCurrentOp))
                this._DrawEraseStroke(graphics, brush, clearBrush
                    , this.EraseCurrentOp, layout, overlayViewX, overlayViewY)

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
            if (brush)
                try Gdip_DeleteBrush(brush)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (bitmap)
                try Gdip_DisposeImage(bitmap)
        }
    }

    _DrawEraseStroke(graphics, brush, clearBrush, operation, layout, viewX, viewY) {
        if (!IsObject(operation) || !operation.HasOwnProp("points"))
            return
        ; 笔擦笔迹把之前涂的擦回去
        if (operation.HasOwnProp("erase") && operation.erase)
            brush := clearBrush
        points := operation.points
        if (!IsObject(points) || points.Length == 0)
            return
        size := operation.size
        half := Floor((size - 1) / 2)
        Gdip_SetCompositingMode(graphics, 1)
        loop points.Length {
            point := points[A_Index]
            x1 := point.x - half
            y1 := point.y - half
            left := Round(layout.offsetX + (x1 - viewX) * layout.zoom)
            top := Round(layout.offsetY + (y1 - viewY) * layout.zoom)
            right := Round(layout.offsetX + (x1 + size - viewX) * layout.zoom)
            bottom := Round(layout.offsetY + (y1 + size - viewY) * layout.zoom)
            if (right <= 0 || bottom <= 0 || left >= this.CanvasSide || top >= this.CanvasSide)
                continue
            Gdip_FillRectangle(graphics, brush, left, top
                , Max(1, right - left), Max(1, bottom - top))
        }
        Gdip_SetCompositingMode(graphics, 0)
    }

    OnApplyErase(*) {
        if (this.EraseOps.Length < 1) {
            RmtDialog.Info(GetLang("请先涂抹或选取背景色"), GetLang("背景擦除"))
            return
        }
        src := this.TemplatePath
        if (src == "" || !FileExist(src))
            return

        tmp := A_Temp "\RMT_erase_tmp.png"
        try FileDelete(tmp)
        if (!this._EraseToPng(src, tmp)) {
            RmtDialog.Info(GetLang("背景擦除失败"), GetLang("背景擦除"))
            return
        }

        target := src
        ext := this._Ext(src)
        if (StrLower(ext) != ".png") {
            SplitPath(src, , &dir, , &nameNoExt)
            target := dir "\" nameNoExt ".png"
        }

        this._ReleaseFile()
        if (!this._MoveWithRetry(tmp, target)) {
            RmtDialog.Info(GetLang("覆盖原图失败：文件可能被占用"), GetLang("背景擦除"))
            return
        }
        if (target != src)
            try FileDelete(src)

        this.TemplatePath := target
        this.EraseOps := []
        this.EraseCurrentOp := ""
        this.EraseDragging := false
        ; 应用成功后收工具条、回初始态
        this.EraseTool := ""
        this.OriginalTool := ""
        this._SyncEraseControls()
        this._ApplyModeStyle()
        this._SyncMatchModeUi()
        this._Render()
        this._RefreshEraseOverlay()

        action := this.CropAction
        if (action != "")
            action(target, this.Points, this.SeedPoints, this.SuperSeedPoints, this.SuperIgnoreData)
    }

    ; 按笔迹生成 32 位 ARGB PNG（alpha=0 即透明）
    _EraseToPng(src, dst) {
        pSrc := Gdip_CreateBitmapFromFile(src)
        if (!pSrc)
            return false
        p32 := 0, graphics := 0, locked := false
        pMask := 0, mBd := 0, lockedMask := false
        try {
            w := 0, h := 0
            Gdip_GetImageDimensions(pSrc, &w, &h)
            if (w < 1 || h < 1)
                return false
            p32 := Gdip_CreateBitmap(w, h, 0x26200A)
            if (!p32)
                return false
            graphics := Gdip_GraphicsFromImage(p32)
            if (!graphics)
                return false
            Gdip_GraphicsClear(graphics, 0x00000000)
            Gdip_DrawImage(graphics, pSrc, 0, 0, w, h)
            Gdip_DeleteGraphics(graphics)
            graphics := 0

            ; 覆盖掩膜：按顺序盖章，笔擦把之前涂的覆盖清掉（与忽略蒙版同一套语义）
            pMask := Gdip_CreateBitmap(w, h, 0x26200A)
            if (!pMask)
                return false
            gMask := Gdip_GraphicsFromImage(pMask)
            if (!gMask) {
                Gdip_DisposeImage(pMask)
                return false
            }
            Gdip_GraphicsClear(gMask, 0x00000000)
            Gdip_DeleteGraphics(gMask)
            gMask := 0

            stride := 0, scan0 := 0, bd := 0
            if (Gdip_LockBits(p32, 0, 0, w, h, &stride, &scan0, &bd) != 0) {
                Gdip_DisposeImage(pMask)
                return false
            }
            locked := true
            mStride := 0, mScan0 := 0, mBd := 0
            if (Gdip_LockBits(pMask, 0, 0, w, h, &mStride, &mScan0, &mBd) != 0) {
                Gdip_UnlockBits(p32, &bd)
                locked := false
                Gdip_DisposeImage(pMask)
                return false
            }
            lockedMask := true

            ; 盖章：按顺序写掩膜（画笔=255，笔擦=0）
            for operation in this.EraseOps {
                radius := Max(1, Integer(operation.size) // 2)
                r2 := radius * radius
                isErase := (operation.HasOwnProp("erase") && operation.erase)
                for point in operation.points {
                    y0 := Max(0, point.y - radius), y1 := Min(h - 1, point.y + radius)
                    x0 := Max(0, point.x - radius), x1 := Min(w - 1, point.x + radius)
                    yy := y0
                    while (yy <= y1) {
                        dy := yy - point.y
                        maskRow := mScan0 + yy * mStride
                        xx := x0
                        while (xx <= x1) {
                            dx := xx - point.x
                            if (dx * dx + dy * dy <= r2)
                                NumPut("UChar", isErase ? 0 : 255, maskRow + xx * 4 + 3)
                            xx += 1
                        }
                        yy += 1
                    }
                }
            }
            Gdip_UnlockBits(pMask, &mBd)
            lockedMask := false

            ; 应用掩膜：覆盖到的地方把 alpha 清零
            yy := 0
            while (yy < h) {
                rowPtr := scan0 + yy * stride
                maskRow := mScan0 + yy * mStride
                xx := 0
                while (xx < w) {
                    if (NumGet(maskRow + xx * 4 + 3, "UChar") > 0) {
                        addr := rowPtr + xx * 4
                        NumPut("UInt", NumGet(addr, "UInt") & 0x00FFFFFF, addr)
                    }
                    xx += 1
                }
                yy += 1
            }

            Gdip_UnlockBits(p32, &bd)
            locked := false
            return Gdip_SaveBitmapToFile(p32, dst) == 0
        } catch {
            return false
        } finally {
            if (lockedMask)
                try Gdip_UnlockBits(pMask, &mBd)
            if (locked)
                try Gdip_UnlockBits(p32, &bd)
            if (pMask)
                try Gdip_DisposeImage(pMask)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (p32)
                try Gdip_DisposeImage(p32)
            try Gdip_DisposeImage(pSrc)
        }
    }

    ; 有效图：只保留真正参与匹配的采样点，其余一律不显示
    ;   多点   → this.Points（基准点与自动补点都在里面）
    ;   超多点 → this.SuperSeedPoints
    ; 点位按画布坐标画成小色块，颜色取该点采样到的颜色；缩得太小时至少 3px
    ; 右下角缩略图：整图适配、无网格、不随主视图缩放/平移
    ; 做法：临时把画布尺寸与视图状态换成「整图 fit」，复用主画布那套有效图逻辑，结束再还原
    _CreateEffectiveThumb() {
        if (this.TemplatePath == "" || !FileExist(this.TemplatePath))
            return ""
        pTpl := Gdip_CreateBitmapFromFile(this.TemplatePath)
        if (!pTpl)
            return ""
        w0 := 0, h0 := 0
        Gdip_GetImageDimensions(pTpl, &w0, &h0)
        Gdip_DisposeImage(pTpl)
        if (w0 < 1 || h0 < 1)
            return ""

        side := 144
        zoomPercent := Max(1, Round(Min(side / w0, side / h0) * 100))

        outBase := A_Temp "\RMT_fe_thumb_" A_TickCount "_" this._windowToken
        o1 := outBase "_o.png"
        o2 := outBase "_e.png"
        seedsText := this.EditorMode == "super" ? this._MultiPointText(this.SuperSeedPoints) : ""

        oldSide := this.CanvasSide
        oldZoom := this._renderedZoom
        oldX := this._renderedViewX
        oldY := this._renderedViewY
        path := ""
        ; 缩略图会临时改 CanvasSide / _renderedZoom，期间禁止其它渲染插进来
        this._thumbBusy := true
        try {
            this.CanvasSide := side
            this._renderedZoom := zoomPercent / 100
            this._renderedViewX := 0
            this._renderedViewY := 0
            info := this._Call(0, 0, 0, 0, zoomPercent, o1, o2, 0, seedsText, this.Tol)
            if (info.ret == 1)
                path := this._CreateEffectiveImage(o1, o2, w0, h0, zoomPercent, true)
        } catch {
            path := ""
        } finally {
            this.CanvasSide := oldSide
            this._renderedZoom := oldZoom
            this._renderedViewX := oldX
            this._renderedViewY := oldY
            this._thumbBusy := false
            try FileDelete(o1)
            try FileDelete(o2)
        }
        if (this._renderAgain) {
            this._renderAgain := false
            SetTimer(ObjBindMethod(this, "_Render"), -1)   ; 缩略图期间被挡下的渲染补上
        }
        return path
    }

    _CreateEffectiveImage(origPath, effPath, viewW, viewH, zoomPercent, smallMarkers := false) {
        ; 超多点：参与匹配的是「与基准色相近且未被忽略蒙版覆盖的像素」，不是那几个基准点
        if (this.EditorMode == "super")
            return this._CreateSuperEffectiveImage(origPath, effPath, viewW, viewH, zoomPercent)
        return this._CreatePointEffectiveImage(smallMarkers)
    }

    ; smallMarkers=true 仅用于右栏缩略图（整图塞进 108px，色块必须小）；
    ; 主画布有效视图按 1 图像像素 = 1 色块绘制，随缩放同步变大
    _CreatePointEffectiveImage(smallMarkers := false) {
        points := this.Points

        this._ptsSeq += 1
        output := A_Temp "\RMT_fe_pts_" A_TickCount "_" this._windowToken "_" this._ptsSeq ".png"
        bitmap := 0, graphics := 0, brush := 0
        try {
            bitmap := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!bitmap)
                return ""
            graphics := Gdip_GraphicsFromImage(bitmap)
            if (!graphics)
                return ""
            ; 深色底板：与超多点有效图统一，浅色采样点也看得见
            Gdip_GraphicsClear(graphics, 0xFF1E1E1E)
            Gdip_SetSmoothingMode(graphics, 0)

            if (IsObject(points) && points.Length > 0) {
                overlayZoom := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
                overlayViewX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
                overlayViewY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
                layout := this._ViewLayout(overlayZoom)

                for point in points {
                    colorText := StrUpper(RegExReplace(String(point.Color), "^#|^0[xX]"))
                    argb := 0xFFFF00FF
                    if (RegExMatch(colorText, "^[0-9A-F]{6}$"))
                        argb := 0xFF000000 | Integer("0x" colorText)

                    ; 缩略图：色块固定 2~4px 防糊成一团；主画布：1 图像像素 = 1 色块，随缩放变大
                    cell := this._PointMarkerBounds(point, layout, overlayViewX, overlayViewY)
                    size := smallMarkers ? Min(4, Max(2, Round(layout.zoom))) : Max(1, Round(layout.zoom))
                    x := cell.x + (cell.w - size) / 2
                    y := cell.y + (cell.h - size) / 2
                    w := size, h := size

                    brush := Gdip_BrushCreateSolid(argb)
                    if (brush) {
                        Gdip_FillRectangle(graphics, brush, x, y, w, h)
                        Gdip_DeleteBrush(brush)
                        brush := 0
                    }
                }
            }

            if (Gdip_SaveBitmapToFile(bitmap, output) != 0) {
                try FileDelete(output)
                return ""
            }
            return output
        } catch {
            return ""
        } finally {
            if (brush)
                try Gdip_DeleteBrush(brush)
            if (graphics)
                try Gdip_DeleteGraphics(graphics)
            if (bitmap)
                try Gdip_DisposeImage(bitmap)
        }
    }

    ; 超多点有效图：
    ;   参与匹配 = 「与基准色在容差内的像素」且不透明，减去「忽略蒙版覆盖的区域」
    ; 超多点有效图：深色底板 + 逐像素命中（按当前视口 420 画布计算，命中像素保留原色）
    _CreateSuperEffectiveImage(origPath, effPath, viewW, viewH, zoomPercent) {
        ; effPath 已不再使用，保留参数只为不动调用方
        if (!FileExist(origPath))
            return ""

        ; 种子色（RGB 三通道拆开，逐像素比较时不用取对象）
        seedR := [], seedG := [], seedB := []
        for seed in this.SuperSeedPoints {
            colorText := StrUpper(RegExReplace(String(seed.Color), "^#|^0[xX]"))
            if (!RegExMatch(colorText, "^[0-9A-F]{6}$"))
                continue
            value := Integer("0x" colorText)
            sr := (value >> 16) & 0xFF, sg := (value >> 8) & 0xFF, sb := value & 0xFF
            duplicated := false
            for i, existing in seedR {
                if (existing == sr && seedG[i] == sg && seedB[i] == sb) {
                    duplicated := true
                    break
                }
            }
            if (!duplicated)
                seedR.Push(sr), seedG.Push(sg), seedB.Push(sb)
        }
        tol := Min(255, Max(0, Integer(this.Tol)))

        output := A_Temp "\RMT_fe_super_" A_TickCount "_" this._windowToken ".png"
        maskBmp := 0, maskGfx := 0, maskBrush := 0, clearBrush := 0
        srcA := 0, pOrig := 0, pOut := 0
        gA := 0, gO := 0
        lockedA := false, lockedO := false, lockedM := false
        try {
            ; ---- 1) 输出画布：先铺深色底板（没有基准点时就只剩底板）----
            pOut := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!pOut)
                return ""
            gO := Gdip_GraphicsFromImage(pOut)
            if (!gO)
                return ""
            Gdip_GraphicsClear(gO, 0xFF1E1E1E)
            Gdip_DeleteGraphics(gO)
            gO := 0

            if (seedR.Length < 1) {
                if (Gdip_SaveBitmapToFile(pOut, output) != 0) {
                    try FileDelete(output)
                    return ""
                }
                return output
            }

            ; ---- 2) 忽略蒙版 → 画布大小的位图 ----
            maskBmp := Gdip_CreateBitmap(this.CanvasSide, this.CanvasSide, 0x26200A)
            if (!maskBmp)
                return ""
            maskGfx := Gdip_GraphicsFromImage(maskBmp)
            if (!maskGfx)
                return ""
            maskBrush := Gdip_BrushCreateSolid(0xFF000000)
            clearBrush := Gdip_BrushCreateSolid(0x00000000)
            if (!maskBrush || !clearBrush)
                return ""
            Gdip_GraphicsClear(maskGfx, 0x00000000)
            Gdip_SetSmoothingMode(maskGfx, 0)
            overlayZoom := this._renderedZoom > 0 ? this._renderedZoom : this.Zoom
            overlayViewX := this._renderedZoom > 0 ? this._renderedViewX : this.ViewX
            overlayViewY := this._renderedZoom > 0 ? this._renderedViewY : this.ViewY
            layout := this._ViewLayout(overlayZoom)
            for operation in this.IgnoreOps
                this._DrawIgnoreOperation(maskGfx, maskBrush, clearBrush, operation, layout, overlayViewX, overlayViewY)
            Gdip_DeleteGraphics(maskGfx)
            maskGfx := 0

            ; ---- 3) 原图（DLL 已按缩放贴好）----
            srcA := Gdip_CreateBitmapFromFile(origPath)
            if (!srcA)
                return ""
            w := 0, h := 0
            Gdip_GetImageDimensions(srcA, &w, &h)
            if (w < 1 || h < 1 || w != this.CanvasSide || h != this.CanvasSide)
                return ""

            pOrig := Gdip_CreateBitmap(w, h, 0x26200A)
            if (!pOrig)
                return ""
            gA := Gdip_GraphicsFromImage(pOrig)
            if (!gA)
                return ""
            Gdip_DrawImage(gA, srcA, 0, 0, w, h)
            Gdip_DeleteGraphics(gA)
            gA := 0

            sA := 0, bA := 0, dA := 0
            sO := 0, bO := 0, dO := 0
            sM := 0, bM := 0, dM := 0
            if (Gdip_LockBits(pOrig, 0, 0, w, h, &sA, &bA, &dA) != 0)
                return ""
            lockedA := true
            if (Gdip_LockBits(pOut, 0, 0, w, h, &sO, &bO, &dO) != 0)
                return ""
            lockedO := true
            if (Gdip_LockBits(maskBmp, 0, 0, w, h, &sM, &bM, &dM) != 0)
                return ""
            lockedM := true

            ; 复刻 DLL 的贴图几何：画布 w×h，缩放后的图像居中贴放
            zoom := zoomPercent / 100
            scaledW := Max(1, Round(viewW * zoom))
            scaledH := Max(1, Round(viewH * zoom))
            pasteX := (w - scaledW) // 2
            pasteY := (h - scaledH) // 2
            srcX := Max(0, -pasteX)
            srcY := Max(0, -pasteY)
            pasteX := Max(0, pasteX)
            pasteY := Max(0, pasteY)
            copyW := Min(scaledW - srcX, w - pasteX)
            copyH := Min(scaledH - srcY, h - pasteY)

            yy := 0
            while (yy < h) {
                rowA := bA + yy * sA
                rowO := bO + yy * sO
                rowM := bM + yy * sM
                insideY := (yy >= pasteY && yy < pasteY + copyH)
                xx := 0
                while (xx < w) {
                    ; 贴图区外保持底板
                    if (!insideY || xx < pasteX || xx >= pasteX + copyW) {
                        xx += 1
                        continue
                    }
                    ; 蒙版盖住的区域不参与匹配
                    if (((NumGet(rowM + xx * 4, "UInt") >> 24) & 0xFF) > 0) {
                        xx += 1
                        continue
                    }
                    vA := NumGet(rowA + xx * 4, "UInt")
                    if (((vA >> 24) & 0xFF) >= 128) {
                        b := vA & 0xFF, g := (vA >> 8) & 0xFF, r := (vA >> 16) & 0xFF
                        hit := false
                        for i, sr in seedR {
                            if (Abs(r - sr) <= tol && Abs(g - seedG[i]) <= tol && Abs(b - seedB[i]) <= tol) {
                                hit := true
                                break
                            }
                        }
                        ; 命中才落笔，强制不透明（掩膜视图，别被原图的半透明再削弱）
                        if (hit)
                            NumPut("UInt", 0xFF000000 | (vA & 0xFFFFFF), rowO + xx * 4)
                    }
                    xx += 1
                }
                yy += 1
            }

            Gdip_UnlockBits(pOut, &dO)
            lockedO := false
            if (Gdip_SaveBitmapToFile(pOut, output) != 0) {
                try FileDelete(output)
                return ""
            }
            return output
        } catch {
            return ""
        } finally {
            if (lockedM)
                try Gdip_UnlockBits(maskBmp, &dM)
            if (lockedO)
                try Gdip_UnlockBits(pOut, &dO)
            if (lockedA)
                try Gdip_UnlockBits(pOrig, &dA)
            if (gO)
                try Gdip_DeleteGraphics(gO)
            if (gA)
                try Gdip_DeleteGraphics(gA)
            if (pOut)
                try Gdip_DisposeImage(pOut)
            if (pOrig)
                try Gdip_DisposeImage(pOrig)
            if (srcA)
                try Gdip_DisposeImage(srcA)
            if (clearBrush)
                try Gdip_DeleteBrush(clearBrush)
            if (maskBrush)
                try Gdip_DeleteBrush(maskBrush)
            if (maskGfx)
                try Gdip_DeleteGraphics(maskGfx)
            if (maskBmp)
                try Gdip_DisposeImage(maskBmp)
        }
    }

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
        ; 应用成功后收工具条、清痕迹、回初始态
        this.Mode := ""
        this.OriginalTool := ""
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

    ; 名字改动后才显示重命名图标按钮
    OnNameChanged(*) {
        if (!IsObject(this.ui))
            return
        text := Trim(String(this.ui.Query("NameCon>Text")))
        canRename := (this.TemplatePath != "" && text != "" && text != this._NameBase)
        try this.ui.Update("BtnRename", "IsEnabled", canRename ? "True" : "False")
        try this.ui.Update("BtnRename", "Foreground"
            , canRename ? "{DynamicResource TextMain}" : "{DynamicResource TextSub}")
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
        try this.ui.Update("RightImg", "Source", "")
        try this.ui.Update("RightPointOverlayImg", "Source", "")
        try this.ui.Update("IgnoreOverlayImg", "Source", "")
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
        if (this.SampleMode)
            return
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

    OnCancelButton(*) {
        if (this.SampleMode)
            return
        this.OnCancel()
    }

    OnCancel(*) {
        this._Close()
    }

    OnWindowClosing(windowToken, state, ctrl, event) {
        if (windowToken != this._windowToken)
            return
        ; 用 X 关窗口也算确认，别把选好的颜色丢掉
        try this._Commit()
        this._SampleCleanupTemp()
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
        this._SampleCleanupTemp()
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
