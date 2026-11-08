
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
