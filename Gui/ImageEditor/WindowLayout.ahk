
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
            .Visibility(this.AllowMultiPoint ? "Visible" : "Collapsed")
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
