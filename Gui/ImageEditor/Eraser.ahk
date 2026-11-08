
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
