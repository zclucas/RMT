
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
