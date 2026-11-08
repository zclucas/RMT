
    _SampleEdgeIntegral(pixels, w, h) {
        stride := (w + 1) * 4
        sums := Buffer(stride * (h + 1), 0)
        y := 0
        while (y < h) {
            row := (y + 1) * stride, previous := y * stride, mass := 0
            x := 0
            while (x < w) {
                mass += NumGet(pixels, y * w + x, "UChar")
                x += 1
                NumPut("UInt", mass + NumGet(sums, previous + x * 4, "UInt"), sums, row + x * 4)
            }
            y += 1
        }
        return sums
    }

    _SampleBuildEdgeMap(scan, stride, w, h, alphaAware := false) {
        count := w * h
        gray := Buffer(count, 0)
        valid := alphaAware ? Buffer(count, 0) : 0
        raw := Buffer(count * 2, 0)
        pixels := Buffer(count, 0)
        directions := Buffer(count, 0)
        maxEdge := 0
        y := 0
        while (y < h) {
            row := scan + y * stride
            x := 0
            while (x < w) {
                value := NumGet(row + x * 4, "UInt")
                isValid := !alphaAware || (value >> 24) >= 128
                grayValue := (((value >> 16) & 255) * 77
                    + ((value >> 8) & 255) * 150 + (value & 255) * 29) >> 8
                NumPut("UChar", grayValue, gray, y * w + x)
                if (alphaAware)
                    NumPut("UChar", isValid, valid, y * w + x)
                x += 1
            }
            y += 1
        }
        y := 1
        while (y < h - 1) {
            x := 1
            while (x < w - 1) {
                idx := y * w + x
                if (alphaAware && (!NumGet(valid, idx, "UChar")
                    || !NumGet(valid, idx - 1, "UChar")
                    || !NumGet(valid, idx + 1, "UChar")
                    || !NumGet(valid, idx - w, "UChar")
                    || !NumGet(valid, idx + w, "UChar"))) {
                    x += 1
                    continue
                }
                dx := NumGet(gray, idx + 1, "UChar") - NumGet(gray, idx - 1, "UChar")
                dy := NumGet(gray, idx + w, "UChar") - NumGet(gray, idx - w, "UChar")
                gx := Abs(dx), gy := Abs(dy), edge := gx + gy
                if (gx * 2 < gy)
                    orientation := 2
                else if (gy * 2 < gx)
                    orientation := 0
                else
                    orientation := dx * dy >= 0 ? 1 : 3
                polarity := (orientation == 0 ? dx < 0
                    : orientation == 2 ? dy < 0 : dx < 0) ? 1 : 0
                direction := orientation * 2 + polarity
                NumPut("UShort", edge, raw, idx * 2)
                NumPut("UChar", direction, directions, idx)
                maxEdge := Max(maxEdge, edge)
                x += 1
            }
            y += 1
        }
        cutoff := Max(6, maxEdge * 0.08)
        mass := 0, edgeCount := 0
        if (maxEdge > cutoff) {
            y := 1
            while (y < h - 1) {
                x := 1
                while (x < w - 1) {
                    idx := y * w + x
                    edge := NumGet(raw, idx * 2, "UShort")
                    if (edge > cutoff) {
                        value := Min(255, Round((edge - cutoff) * 255 / (maxEdge - cutoff)))
                        NumPut("UChar", value, pixels, idx)
                        mass += value, edgeCount += 1
                    }
                    x += 1
                }
                y += 1
            }
        }
        return {Pixels: pixels, Directions: directions, Count: edgeCount, Mass: mass}
    }

    _SampleBuildEdgeMapFromBitmap(bitmap, w, h, alphaAware := false) {
        stride := 0, scan := 0, data := 0
        if (Gdip_LockBits(bitmap, 0, 0, w, h, &stride, &scan, &data) != 0)
            return {Pixels: Buffer(1, 0), Count: 0, Mass: 0}
        try {
            native := this._SampleBuildNativeEdgeMap(
                scan, stride, w, h, alphaAware)
            return IsObject(native)
                ? native : this._SampleBuildEdgeMap(scan, stride, w, h, alphaAware)
        }
        finally Gdip_UnlockBits(bitmap, &data)
    }

    _SampleBuildNativeEdgeMap(scan, stride, w, h, alphaAware := false) {
        proc := this._SampleNativeAlignmentProc("SampleBuildEdgeMap")
        if (!proc || w < 1 || h < 1)
            return 0
        count := w * h
        pixels := Buffer(count, 0)
        directions := Buffer(count, 0)
        edgeCount := 0, mass := Buffer(8, 0)
        try ran := DllCall(proc
            , "Ptr", scan, "Int", stride, "Int", w, "Int", h
            , "Int", alphaAware ? 1 : 0, "Ptr", pixels.Ptr, "Ptr", directions.Ptr
            , "Int*", &edgeCount, "Ptr", mass.Ptr, "Cdecl Int")
        catch
            ran := 0
        if (!ran)
            return 0
        return {Pixels: pixels, Directions: directions, Count: edgeCount
            , Mass: NumGet(mass, 0, "UInt64")}
    }

    _SampleEdgeSimilarity(dirA, dirB) {
        orientationA := dirA >> 1, orientationB := dirB >> 1
        difference := Abs(orientationA - orientationB)
        difference := Min(difference, 4 - difference)
        return difference == 0 ? 1 : difference == 1 ? 0.5 : 0
    }

    _SampleEdgeWeights() {
        static weights := 0
        if (!IsObject(weights)) {
            table := Buffer(64, 0)
            loop 8 {
                dirA := A_Index - 1
                loop 8 {
                    dirB := A_Index - 1
                    NumPut("UChar", this._SampleEdgeSimilarity(dirA, dirB) * 2, table, dirA * 8 + dirB)
                }
            }
            weights := table
        }
        return weights
    }

    _SampleInsertAlignCandidate(candidates, candidate, radius, limit) {
        for idx, current in candidates {
            if (Max(Abs(candidate.ox - current.ox), Abs(candidate.oy - current.oy)) <= radius) {
                currentVotes := current.HasProp("anchorVotes") ? current.anchorVotes : 0
                candidateVotes := candidate.HasProp("anchorVotes") ? candidate.anchorVotes : 0
                if (candidate.score > current.score
                    || (candidate.score == current.score
                        && Abs(candidate.ox) + Abs(candidate.oy) >= Abs(current.ox) + Abs(current.oy))) {
                    if (candidateVotes > currentVotes) {
                        current.anchorVotes := candidateVotes
                        current.anchorMargin := candidate.anchorMargin
                    }
                    return
                }
                if (currentVotes > candidateVotes) {
                    candidate.anchorVotes := currentVotes
                    candidate.anchorMargin := current.anchorMargin
                }
                candidates.RemoveAt(idx)
                break
            }
        }
        pos := 1
        while (pos <= candidates.Length
            && (candidates[pos].score < candidate.score
                || (candidates[pos].score == candidate.score
                    && Abs(candidates[pos].ox) + Abs(candidates[pos].oy)
                        <= Abs(candidate.ox) + Abs(candidate.oy))))
            pos += 1
        if (pos <= limit) {
            candidates.InsertAt(pos, candidate)
            if (candidates.Length > limit)
                candidates.Pop()
        }
    }

    _RefineEdgeOffset(bw, bh, sw, sh, ox0, oy0, radius, edgeB, edgeS) {
        weights := this._SampleEdgeWeights()
        proc := this._SampleNativeAlignmentProc("SampleRefineEdgeOffset")
        if (proc) {
            output := Buffer(40, 0)
            try nativeResult := DllCall(proc
                , "Ptr", edgeB.Pixels.Ptr, "Ptr", edgeB.Directions.Ptr, "Int", bw, "Int", bh
                , "Ptr", edgeS.Pixels.Ptr, "Ptr", edgeS.Directions.Ptr, "Int", sw, "Int", sh
                , "Int", ox0, "Int", oy0, "Int", radius, "Ptr", weights.Ptr
                , "Ptr", output.Ptr, "Cdecl Int")
            catch
                nativeResult := -1
            if (nativeResult >= 0) {
                if (!nativeResult)
                    return 0
                return {ox: Round(NumGet(output, 0, "Double"))
                    , oy: Round(NumGet(output, 8, "Double"))
                    , score: NumGet(output, 16, "Double")
                    , coverage: NumGet(output, 24, "Double")
                    , texture: NumGet(output, 32, "Double")}
            }
        }
        left := Max(0, ox0), right := Min(bw, ox0 + sw)
        top := Max(0, oy0), bottom := Min(bh, oy0 + sh)
        if (right - left < 8 || bottom - top < 8)
            return 0
        blockW := Min(120, right - left - radius * 2)
        blockH := Min(120, bottom - top - radius * 2)
        if (blockW < 8 || blockH < 8)
            return 0
        bx := left + (right - left - blockW) // 2
        by := top + (bottom - top - blockH) // 2
        pixelStep := Max(1, Ceil(Max(blockW, blockH) / 32))
        sampleTotal := Ceil(blockW / pixelStep) * Ceil(blockH / pixelStep)
        xs := [left + radius, bx, right - blockW - radius]
        ys := [top + radius, by, bottom - blockH - radius]
        blockStarts := [[bx, by]]
        for blockY in ys
            for blockX in xs
                if (blockX != bx || blockY != by)
                    blockStarts.Push([blockX, blockY])
        minMassRequired := Max(24, sampleTotal * 0.2)
        bestBlockScore := 1.0e15
        for blockStart in blockStarts {
            testX := blockStart[1], testY := blockStart[2]
            massTestB := 0, massTestS := 0, sharedTest := 0
            yy := 0
            while (yy < blockH) {
                xx := 0
                while (xx < blockW) {
                    idxB := (testY + yy) * bw + testX + xx
                    idxS := (testY - oy0) * sw + testX - ox0 + yy * sw + xx
                    va := NumGet(edgeB.Pixels, idxB, "UChar")
                    vb := NumGet(edgeS.Pixels, idxS, "UChar")
                    massTestB += va, massTestS += vb
                    if (va && vb) {
                        dirA := NumGet(edgeB.Directions, idxB, "UChar") * 8
                        dirB := NumGet(edgeS.Directions, idxS, "UChar")
                        sharedTest += Min(va, vb) * NumGet(weights, dirA + dirB, "UChar") * 0.5
                    }
                    xx += pixelStep
                }
                yy += pixelStep
            }
            minMassTest := Min(massTestB, massTestS)
            if (minMassTest < minMassRequired)
                continue
            coverageTest := sharedTest / minMassTest
            if (coverageTest < 0.25)
                continue
            purityTest := (2 * sharedTest) / Max(1, massTestB + massTestS)
            scoreTest := 1 - (coverageTest * 0.7 + purityTest * 0.3)
            if (scoreTest < bestBlockScore) {
                bestBlockScore := scoreTest
                bx := testX, by := testY
            }
        }
        pixelsS := edgeS.Pixels, directionsS := edgeS.Directions
        points := Buffer(sampleTotal * 8, 0)
        pointBytes := 0, massB := 0, yy := 0
        while (yy < blockH) {
            xx := 0
            while (xx < blockW) {
                idxB := (by + yy) * bw + bx + xx
                va := NumGet(edgeB.Pixels, idxB, "UChar")
                NumPut("UInt", yy * sw + xx, "UChar", va
                    , "UChar", NumGet(edgeB.Directions, idxB, "UChar") * 8, points, pointBytes)
                pointBytes += 8, massB += va
                xx += pixelStep
            }
            yy += pixelStep
        }
        bestScore := 1.0e15, bestOx := ox0, bestOy := oy0
        bestCoverage := 0, bestTexture := 0, found := false
        dy := -radius
        while (dy <= radius) {
            dx := -radius
            while (dx <= radius) {
                ox := ox0 + dx, oy := oy0 + dy
                massS := 0, shared := 0, point := 0
                ; 中心块四周已预留 radius，整个搜索范围内所有采样点均在两图内。
                origin := (by - oy) * sw + bx - ox
                while (point < pointBytes) {
                    idxS := origin + NumGet(points, point, "UInt")
                    va := NumGet(points, point + 4, "UChar")
                    vb := NumGet(pixelsS, idxS, "UChar")
                    massS += vb
                    if (va && vb) {
                        dirA := NumGet(points, point + 5, "UChar")
                        dirB := NumGet(directionsS, idxS, "UChar")
                        shared += Min(va, vb) * NumGet(weights, dirA + dirB, "UChar") * 0.5
                    }
                    point += 8
                }
                minMass := Min(massB, massS)
                if (minMass >= minMassRequired) {
                    coverage := shared / minMass
                    purity := (2 * shared) / Max(1, massB + massS)
                    score := 1 - (coverage * 0.7 + purity * 0.3)
                    texture := minMass / sampleTotal
                    if (coverage >= 0.25 && (score < bestScore
                        || (score == bestScore
                            && Abs(dx) + Abs(dy) < Abs(bestOx - ox0) + Abs(bestOy - oy0)))) {
                        bestScore := score
                        bestOx := ox, bestOy := oy
                        bestCoverage := coverage
                        bestTexture := texture
                        found := true
                    }
                }
                dx += 1
            }
            dy += 1
        }
        return found
            ? {ox: bestOx, oy: bestOy, score: bestScore
                , coverage: bestCoverage, texture: bestTexture} : 0
    }

    ; 从预测重叠区取中心块；LockBits 返回的 Scan0 从锁定区域左上角开始。
    _RefineOffset(pB, pS, bw, bh, sw, sh, ox0, oy0, radius) {
        left := Max(0, ox0), right := Min(bw, ox0 + sw)
        top := Max(0, oy0), bottom := Min(bh, oy0 + sh)
        if (right - left < 4 || bottom - top < 4)
            return 0
        blockW := Min(120, Max(4, right - left - radius * 2))
        blockH := Min(120, Max(4, bottom - top - radius * 2))
        bx := left + (right - left - blockW) // 2
        by := top + (bottom - top - blockH) // 2
        s0 := 0, b0 := 0, d0 := 0
        s1 := 0, b1 := 0, d1 := 0
        if (Gdip_LockBits(pB, bx, by, blockW, blockH, &s0, &b0, &d0) != 0)
            return 0
        lockedS := false
        try {
            rx := bx - ox0 - radius, ry := by - oy0 - radius
            clipX := Max(0, rx), clipY := Max(0, ry)
            clipW := Min(sw, rx + blockW + radius * 2) - clipX
            clipH := Min(sh, ry + blockH + radius * 2) - clipY
            if (clipW <= 0 || clipH <= 0
                || Gdip_LockBits(pS, clipX, clipY, clipW, clipH, &s1, &b1, &d1) != 0)
                return 0
            lockedS := true
            pixelStep := Max(1, Ceil(Max(blockW, blockH) / 32))
            textureCount := 0, sumR := 0, sumG := 0, sumB := 0
            sumR2 := 0, sumG2 := 0, sumB2 := 0
            yy := 0
            while (yy < blockH) {
                rowB := b0 + yy * s0
                xx := 0
                while (xx < blockW) {
                    vb := NumGet(rowB + xx * 4, "UInt")
                    if ((vb >> 24) >= 128) {
                        b := vb & 255, g := (vb >> 8) & 255, r := (vb >> 16) & 255
                        sumR += r, sumG += g, sumB += b
                        sumR2 += r * r, sumG2 += g * g, sumB2 += b * b
                        textureCount += 1
                    }
                    xx += pixelStep
                }
                yy += pixelStep
            }
            if (textureCount < 4)
                return 0
            varianceR := Max(0, sumR2 / textureCount - (sumR / textureCount) ** 2)
            varianceG := Max(0, sumG2 / textureCount - (sumG / textureCount) ** 2)
            varianceB := Max(0, sumB2 / textureCount - (sumB / textureCount) ** 2)
            texture := Max(Sqrt(varianceR), Sqrt(varianceG), Sqrt(varianceB))
            if (texture < 4)
                return 0
            sampleTotal := Ceil(blockW / pixelStep) * Ceil(blockH / pixelStep)
            bestScore := 1.0e15, bestOx := ox0, bestOy := oy0
            bestCoverage := 0
            found := false
            dy := -radius
            while (dy <= radius) {
                dx := -radius
                while (dx <= radius) {
                    ox := ox0 + dx, oy := oy0 + dy
                    lx0 := bx - ox - clipX, ly0 := by - oy - clipY
                    if (lx0 < 0 || ly0 < 0 || lx0 + blockW > clipW || ly0 + blockH > clipH) {
                        dx += 1
                        continue
                    }
                    sad := 0, count := 0
                    yy := 0
                    while (yy < blockH) {
                        rowB := b0 + yy * s0
                        rowS := b1 + (ly0 + yy) * s1 + lx0 * 4
                        xx := 0
                        while (xx < blockW) {
                            vb := NumGet(rowB + xx * 4, "UInt")
                            vs := NumGet(rowS + xx * 4, "UInt")
                            if ((vb >> 24) >= 128 && (vs >> 24) >= 128) {
                                sad += Abs((vb & 255) - (vs & 255))
                                    + Abs(((vb >> 8) & 255) - ((vs >> 8) & 255))
                                    + Abs(((vb >> 16) & 255) - ((vs >> 16) & 255))
                                count += 1
                            }
                            xx += pixelStep
                        }
                        yy += pixelStep
                    }
                    if (count >= Max(4, Ceil(sampleTotal * 0.5))) {
                        score := sad / (count * 3)
                        if (score < bestScore || (score == bestScore
                            && Abs(ox - ox0) + Abs(oy - oy0) < Abs(bestOx - ox0) + Abs(bestOy - oy0))) {
                            bestScore := score
                            bestOx := ox, bestOy := oy
                            bestCoverage := count / sampleTotal
                            found := true
                        }
                    }
                    dx += 1
                }
                dy += 1
            }
            ; 平均每通道差超过 32 时拒绝，不能把最小误差等同于可靠对齐。
            return found && bestScore <= 32
                ? {ox: bestOx, oy: bestOy, score: bestScore
                    , coverage: bestCoverage, texture: texture} : 0
        } finally {
            if (lockedS)
                Gdip_UnlockBits(pS, &d1)
            Gdip_UnlockBits(pB, &d0)
        }
    }
