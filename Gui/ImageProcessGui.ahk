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
    ; 界面和 Worker 样本对齐共用这个入口，按职责引入 ImageEditor 下的方法。
    __new(allowMultiPoint := true) {
        this.AllowMultiPoint := allowMultiPoint
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
        this.MatchMode := ""
        if (this.AllowMultiPoint)
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
#Include ImageEditor\WindowLayout.ahk

    OnHelp(*) {
        text := GetLang("一、图片处理") "`n"
            . GetLang("改名：改完按右侧对勾应用。裁剪：框选保留区域后应用。抠除：画笔涂掉背景、笔擦擦回，再应用生成透明底。")
        if (this.AllowMultiPoint)
            text .= "`n`n" GetLang("二、多点搜图") "`n"
                . GetLang("用多个色块匹配；相似度=命中比例；可点击右上角效果图，查看搜索时参与的色块。操作流程：选基准点后可自动补点或手动增删，最多 256 点。") "`n"
                . GetLang("超多点：选基准色 + 容差匹配整幅图，蒙版涂抹区域不参与匹配。")
        text .= "`n`n" GetLang(this.AllowMultiPoint ? "三、自动抠图" : "二、自动抠图") "`n"
            . GetLang("采集 2 张以上同一区域的样本（截屏或导入），自动对齐后提取所有样本共同不变的像素，生成透明底 PNG。")
        RmtDialog.Info(text, GetLang("图片处理说明"))
    }
#Include ImageEditor\Canvas.ahk
#Include ImageEditor\IgnoreMask.ahk
#Include ImageEditor\CropAndPointSelection.ahk
#Include ImageEditor\CanvasOverlays.ahk
#Include ImageEditor\ToolModes.ahk
#Include ImageEditor\SampleCollection.ahk
#Include ImageEditor\SamplePreview.ahk
#Include ImageEditor\SampleAlignmentQueue.ahk
#Include ImageEditor\SampleAlignmentResults.ahk
#Include ImageEditor\SampleAlignmentWorkers.ahk
#Include ImageEditor\SampleAlignmentMatching.ahk
#Include ImageEditor\SampleAlignmentEdges.ahk
#Include ImageEditor\SampleTempFiles.ahk
#Include ImageEditor\Eraser.ahk
#Include ImageEditor\EffectiveImages.ahk
#Include ImageEditor\ImageFileActions.ahk

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
