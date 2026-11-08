
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
