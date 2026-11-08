
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
