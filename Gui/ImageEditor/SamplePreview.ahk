
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
            if (!this._SampleCommitQueuedFrames()) {
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
            if (!this._SampleCommitQueuedFrames() && this._samplePending && this.SampleMode)
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
