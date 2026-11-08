
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
