
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
