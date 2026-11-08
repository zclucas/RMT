
    _SampleScheduleAlign() {
        this._sampleAlignScheduled := false
        if (this.SampleMode && this.SampleFrames.Length > 1)
            for idx, frame in this.SampleFrames
                if (idx > 1 && !frame.Aligned) {
                    this._sampleAlignScheduled := true
                    break
                }
        this._SampleSyncControls()
        if (!this._sampleAlignScheduled) {
            SetTimer(this._sampleAlignTimer, 0)
            this._SampleRefreshPreview()
            return
        }
        SetTimer(this._sampleAlignTimer, -150)
    }

    _SampleAlignPending(*) {
        if (!this.SampleMode || !IsObject(this.ui))
            return
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy) {
            this._sampleDirty := true
            SetTimer(this._sampleAlignTimer, -150)
            return
        }
        this._sampleAlignScheduled := false
        this._sampleBusy := true
        this._sampleDirty := false
        this._SampleSyncControls()
        parallelLimit := 4
        session := this._sampleSession, revision := this._sampleRevision
        stats := {startedAt: A_TickCount
            , plannedPairs: 0, executedPairs: 0, pairCacheHits: 0
            , edgeCacheHits: 0, edgeCacheBuilds: 0, fallbackPairs: 0
            , verifiedPairs: 0, fallbackSearches: 0, workerStarts: 0
            , effectBuilds: 0, effectRefreshes: 0, effectAnchoredPairs: 0
            , effectFallbackSearches: 0, effectPreviewReuses: 0, alignmentEffectReuses: 0
            , candidateConsensusAlignments: 0, adaptiveSerialBatches: 0
            , effectiveParallelLimit: 0, effectPixelsVisited: 0}
        this._sampleAlignmentStats := stats
        frames := []
        for frame in this.SampleFrames
            frames.Push(frame.Clone())
        progressEffectBitmap := 0, progressEffectFrame := 0
        progressEffectUpdates := 0, threshold := this.SampleThreshold
        alignmentEffectFrame := this._SampleGetReusableAlignmentEffect(session, threshold)
        referenceLimit := Min(12, frames.Length)
        try {
            madeProgress := true
            while (madeProgress) {
                madeProgress := false
                loop frames.Length {
                    i := A_Index
                    if (session != this._sampleSession || revision != this._sampleRevision)
                        return
                    if (i == 1 || frames[i].Aligned)
                        continue
                    refs := [1]
                    loop frames.Length {
                        j := frames.Length - A_Index + 1
                        if (j != 1 && j != i && frames[j].Aligned) {
                            if (refs.Length >= referenceLimit)
                                break
                            refs.Push(j)
                        }
                    }
                    matches := []
                    pairDiagnostics := []
                    candidateEffectFrame := IsObject(progressEffectFrame)
                        ? progressEffectFrame : alignmentEffectFrame
                    pairResults := this._SampleRunFastAlignmentBatch(
                        frames, refs, i, session, parallelLimit, candidateEffectFrame)
                    if (!IsObject(pairResults)) {
                        this._SampleCountAlignmentStat("fallbackSearches")
                        pairResults := this._SampleRunParallelAlignmentBatch(
                            frames, refs, i, session, parallelLimit)
                    }
                    if (session != this._sampleSession || revision != this._sampleRevision)
                        return
                    if (!IsObject(pairResults)) {
                        pairResults := []
                        for _, refIdx in refs {
                            this._SampleCountAlignmentStat("fallbackPairs")
                            pairDiagnostic := {refIdx: refIdx}
                            off := this._SampleGetPairAlignment(
                                frames[refIdx], frames[i], pairDiagnostic)
                            if (session != this._sampleSession || revision != this._sampleRevision)
                                return
                            pairResults.Push({refIdx: refIdx, offset: off, diagnostic: pairDiagnostic})
                        }
                    }
                    for pair in pairResults {
                        refIdx := pair.refIdx, off := pair.offset, pairDiagnostic := pair.diagnostic
                        if (IsObject(off))
                            matches.Push({ox: frames[refIdx].OffX + off.ox
                                , oy: frames[refIdx].OffY + off.oy, refIdx: refIdx
                                , score: off.score, margin: off.margin
                                , coverage: off.coverage, texture: off.texture})
                        if (IsObject(off)) {
                            pairDiagnostic.globalX := frames[refIdx].OffX + off.ox
                            pairDiagnostic.globalY := frames[refIdx].OffY + off.oy
                        }
                        if (pairDiagnostic.HasProp("candidateX")) {
                            pairDiagnostic.candidateGlobalX := frames[refIdx].OffX
                                + pairDiagnostic.candidateX
                            pairDiagnostic.candidateGlobalY := frames[refIdx].OffY
                                + pairDiagnostic.candidateY
                        }
                        pairDiagnostics.Push(pairDiagnostic)
                    }
                    resolutionDiagnostic := {}
                    aligned := this._SampleResolveAlignment(matches, resolutionDiagnostic)
                    if (!IsObject(aligned)) {
                        candidateConsensusDiagnostic := {}
                        aligned := this._SampleResolveCandidateConsensus(
                            matches, pairDiagnostics, candidateConsensusDiagnostic)
                        if (IsObject(aligned))
                            this._SampleCountAlignmentStat("candidateConsensusAlignments")
                    }
                    if (IsObject(aligned)) {
                        frames[i].OffX := aligned.ox
                        frames[i].OffY := aligned.oy
                        frames[i].Aligned := true
                        frames[i].AlignDiagnostic := ""
                        madeProgress := true
                        hasPending := this._SampleHasPendingAlignment(frames)
                        if (progressEffectBitmap) {
                            if (!this._SampleUpdateAlignmentEffect(progressEffectBitmap
                                , frames[i], threshold, session, revision, progressEffectFrame)) {
                                Gdip_DisposeImage(progressEffectBitmap)
                                progressEffectBitmap := 0
                                if (IsObject(progressEffectFrame))
                                    this._SampleDiscardPath(progressEffectFrame.Path)
                                progressEffectFrame := 0
                                progressEffectUpdates := 0
                            } else {
                                progressEffectUpdates += 1
                                if (hasPending && progressEffectUpdates >= 3) {
                                    refreshedEffect := this._SampleSaveAlignmentEffect(
                                        progressEffectBitmap, session, revision)
                                    if (IsObject(refreshedEffect)) {
                                        oldEffectPath := progressEffectFrame.Path
                                        progressEffectFrame := refreshedEffect
                                        progressEffectUpdates := 0
                                        this._SampleCountAlignmentStat("effectRefreshes")
                                        this._SampleDiscardPath(oldEffectPath)
                                    }
                                }
                            }
                        }
                        if (!progressEffectBitmap && hasPending) {
                            alignedFrameCount := 0
                            for alignedIdx, alignedFrame in frames
                                if (alignedIdx == 1 || alignedFrame.Aligned)
                                    alignedFrameCount += 1
                            if (alignedFrameCount >= 2) {
                                progressEffectBitmap := this._SampleCompute(
                                    threshold, frames, session, revision)
                                if (progressEffectBitmap) {
                                    progressEffectFrame := this._SampleSaveAlignmentEffect(
                                        progressEffectBitmap, session, revision)
                                    if (IsObject(progressEffectFrame))
                                        this._SampleCountAlignmentStat("effectBuilds")
                                    else {
                                        Gdip_DisposeImage(progressEffectBitmap)
                                        progressEffectBitmap := 0
                                    }
                                }
                            }
                        }
                    } else {
                        frames[i].AlignDiagnostic := this._SampleFormatAlignmentDiagnostic(
                            pairDiagnostics, candidateConsensusDiagnostic.HasProp("reason")
                                ? candidateConsensusDiagnostic.reason
                                : (matches.Length > 0 ? resolutionDiagnostic.reason : ""))
                    }
                }
            }
            if (session == this._sampleSession && revision == this._sampleRevision) {
                this.SampleFrames := frames
                this._sampleRevision += 1
                if (progressEffectBitmap) {
                    this._SampleDiscardReadyPreviewBitmap()
                    this._sampleReadyPreviewBitmap := progressEffectBitmap
                    this._sampleReadyPreviewSession := session
                    this._sampleReadyPreviewRevision := this._sampleRevision
                    this._sampleReadyPreviewThreshold := threshold
                    progressEffectBitmap := 0
                }
            }
        } finally {
            if (progressEffectBitmap)
                Gdip_DisposeImage(progressEffectBitmap)
            if (IsObject(progressEffectFrame))
                this._SampleDiscardPath(progressEffectFrame.Path)
            stats.totalMs := A_TickCount - stats.startedAt
            stats.startedAt := 0
            try OutputDebug("SampleAlignment " JSON.stringify(stats))
            this._sampleBusy := false
            this._SampleCollectGarbage()
            this._SampleRetile()
            if (!this._SampleCommitQueuedFrames()) {
                if (this._sampleDirty && this.SampleMode)
                    this._SampleScheduleAlign()
                else
                    this._SampleRefreshPreview()
            }
        }
    }

    _SampleHasPendingAlignment(frames) {
        for idx, frame in frames
            if (idx > 1 && !frame.Aligned)
                return true
        return false
    }

    _SampleCountAlignmentStat(name, amount := 1) {
        stats := this._sampleAlignmentStats
        if (IsObject(stats) && stats.HasProp(name))
            stats.%name% += amount
    }

    _SampleRunFastAlignmentBatch(frames, refs, sampleIdx, session, parallelLimit
        , progressEffectFrame := 0) {
        if (!refs.Length || !this.SampleMode)
            return 0
        anchorIdx := refs[1]
        anchorResults := this._SampleRunParallelAlignmentBatch(
            frames, [anchorIdx], sampleIdx, session, parallelLimit)
        if (IsObject(anchorResults) && IsObject(anchorResults[1].offset)) {
            anchor := anchorResults[1]
            targetX := frames[anchorIdx].OffX + anchor.offset.ox
            targetY := frames[anchorIdx].OffY + anchor.offset.oy
            validationTasks := []
            for refIdx in refs {
                if (refIdx == anchorIdx)
                    continue
                validationTasks.Push({refIdx: refIdx, sampleIdx: sampleIdx, mode: "verify"
                    , expectedX: targetX - frames[refIdx].OffX
                    , expectedY: targetY - frames[refIdx].OffY})
            }
            if (!validationTasks.Length)
                return anchorResults

            verified := this._SampleValidateAlignmentCandidate(frames, validationTasks
                , session, parallelLimit, anchorResults, targetX, targetY, 2)
            if (IsObject(verified))
                return verified
        }

        if (IsObject(progressEffectFrame) && refs.Length > 1) {
            effectResults := this._SampleRunProgressEffectBatch(
                frames, refs, sampleIdx, session, parallelLimit, progressEffectFrame)
            if (IsObject(effectResults))
                return effectResults
            this._SampleCountAlignmentStat("effectFallbackSearches")
        }
        return 0
    }

    _SampleRunProgressEffectBatch(frames, refs, sampleIdx, session, parallelLimit, effectFrame) {
        anchorIdx := refs[1]
        effectTask := {refIdx: anchorIdx, sampleIdx: sampleIdx, mode: "effect"
            , refRec: effectFrame}
        anchorResults := this._SampleRunPairTaskBatch(
            frames, [effectTask], session, parallelLimit)
        if (!IsObject(anchorResults) || !IsObject(anchorResults[1].offset))
            return 0

        anchor := anchorResults[1]
        targetX := effectFrame.OffX + anchor.offset.ox
        targetY := effectFrame.OffY + anchor.offset.oy
        validationTasks := []
        for refIdx in refs
            validationTasks.Push({refIdx: refIdx, sampleIdx: sampleIdx, mode: "verify"
                , expectedX: targetX - frames[refIdx].OffX
                , expectedY: targetY - frames[refIdx].OffY})

        effectOffset := {ox: targetX - frames[anchorIdx].OffX
            , oy: targetY - frames[anchorIdx].OffY
            , score: anchor.offset.score, margin: anchor.offset.margin
            , coverage: anchor.offset.coverage, texture: anchor.offset.texture}
        results := [{refIdx: anchorIdx, sampleIdx: sampleIdx
            , offset: effectOffset, diagnostic: anchor.diagnostic}]
        verified := this._SampleValidateAlignmentCandidate(frames, validationTasks
            , session, parallelLimit, [], targetX, targetY, 2, true)
        if (!IsObject(verified))
            return 0
        for result in verified
            results.Push(result)
        this._SampleCountAlignmentStat("effectAnchoredPairs")
        return results
    }
