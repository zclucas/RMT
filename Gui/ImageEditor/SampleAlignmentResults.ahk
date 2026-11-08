
    _SampleValidateAlignmentCandidate(frames, tasks, session, parallelLimit
        , seedResults, targetX, targetY, minVotes := 2, requireBase := false) {
        results := seedResults.Clone(), matches := [], baseVerified := false
        for result in seedResults {
            ref := frames[result.refIdx]
            if (result.refIdx == 1)
                baseVerified := true
            matches.Push({ox: ref.OffX + result.offset.ox
                , oy: ref.OffY + result.offset.oy, refIdx: result.refIdx
                , score: result.offset.score, margin: result.offset.margin
                , coverage: result.offset.coverage, texture: result.offset.texture})
        }

        batchParallelLimit := this._SampleGetEffectivePairParallelLimit(
            frames, tasks, parallelLimit)
        batchSize := Min(4, batchParallelLimit)
        nextTask := 1
        while (nextTask <= tasks.Length) {
            batch := []
            loop Min(batchSize, tasks.Length - nextTask + 1) {
                batch.Push(tasks[nextTask])
                nextTask += 1
            }
            verified := this._SampleRunPairTaskBatch(
                frames, batch, session, parallelLimit)
            if (!IsObject(verified))
                return 0
            for result in verified {
                if (!IsObject(result.offset))
                    continue
                ref := frames[result.refIdx]
                results.Push(result)
                matches.Push({ox: ref.OffX + result.offset.ox
                    , oy: ref.OffY + result.offset.oy, refIdx: result.refIdx
                    , score: result.offset.score, margin: result.offset.margin
                    , coverage: result.offset.coverage, texture: result.offset.texture})
                if (result.refIdx == 1)
                    baseVerified := true
                this._SampleCountAlignmentStat("verifiedPairs")
            }

            targetVotes := 0
            for match in matches
                if (Abs(match.ox - targetX) <= 2 && Abs(match.oy - targetY) <= 2)
                    targetVotes += 1
            if (targetVotes >= minVotes && (!requireBase || baseVerified)) {
                resolutionDiagnostic := {}
                resolved := this._SampleResolveAlignment(matches, resolutionDiagnostic)
                if (IsObject(resolved) && Abs(resolved.ox - targetX) <= 2
                    && Abs(resolved.oy - targetY) <= 2)
                    return results
            }
        }
        return 0
    }

    _SampleFormatAlignmentDiagnostic(pairDiagnostics, consensusReason := "") {
        details := consensusReason != "" ? GetLang(consensusReason) : ""
        for pair in pairDiagnostics {
            reason := pair.HasProp("reason") ? pair.reason : "没有匹配候选"
            line := Format(GetLang("参考样本 {1}：{2}"), pair.refIdx, GetLang(reason))
            if (pair.HasProp("globalX"))
                line .= Format(" @ ({1},{2})", pair.globalX, pair.globalY)
            else if (pair.HasProp("candidateGlobalX"))
                line .= Format(" candidate@({1},{2})"
                    , pair.candidateGlobalX, pair.candidateGlobalY)
            if (pair.HasProp("score"))
                line .= Format(" (score={1}, margin={2}, coverage={3}, texture={4})"
                    , Round(pair.score, 3), Round(pair.margin, 3)
                    , Round(pair.coverage, 3), Round(pair.texture, 3))
            details .= (details == "" ? "" : "`n") line
        }
        return details
    }

    _SampleIsStrongAlignment(match) {
        return match.HasProp("score") && match.HasProp("margin")
            && match.HasProp("coverage") && match.HasProp("texture")
            && match.score <= 0.35 && match.margin >= Max(0.05, match.score * 0.15)
            && match.coverage >= 0.65 && match.texture >= 1
    }

    _SampleResolveCandidateConsensus(matches, pairDiagnostics, diagnostic := 0) {
        candidates := [], seenRefs := Map()
        for match in matches {
            seenRefs[match.refIdx] := true
            if (match.score <= 0.68 && match.coverage >= 0.4)
                candidates.Push(match)
        }
        for pair in pairDiagnostics {
            if (seenRefs.Has(pair.refIdx) || !pair.HasProp("candidateGlobalX")
                || !pair.HasProp("candidateGlobalY") || !pair.HasProp("score")
                || !pair.HasProp("coverage") || pair.score > 0.68 || pair.coverage < 0.4)
                continue
            candidates.Push({ox: pair.candidateGlobalX, oy: pair.candidateGlobalY
                , refIdx: pair.refIdx, score: pair.score, coverage: pair.coverage
                , texture: pair.HasProp("texture") ? pair.texture : 0})
            seenRefs[pair.refIdx] := true
        }
        if (candidates.Length < 3) {
            if (IsObject(diagnostic))
                diagnostic.reason := "参考样本候选共识不足"
            return 0
        }

        best := 0, bestCount := 0, bestStrongCount := 0, bestCost := 1.0e15
        for anchor in candidates {
            cluster := [], strongCount := 0, cost := 0
            minX := 1.0e15, maxX := -1.0e15, minY := 1.0e15, maxY := -1.0e15
            for candidate in candidates {
                if (Abs(candidate.ox - anchor.ox) > 2 || Abs(candidate.oy - anchor.oy) > 2)
                    continue
                cluster.Push(candidate)
                cost += candidate.score
                minX := Min(minX, candidate.ox), maxX := Max(maxX, candidate.ox)
                minY := Min(minY, candidate.oy), maxY := Max(maxY, candidate.oy)
                if (candidate.score <= 0.45 && candidate.coverage >= 0.65)
                    strongCount += 1
            }
            if (cluster.Length < 3 || strongCount < 1 || maxX - minX > 2 || maxY - minY > 2)
                continue
            if (cluster.Length > bestCount
                || (cluster.Length == bestCount && strongCount > bestStrongCount)
                || (cluster.Length == bestCount && strongCount == bestStrongCount
                    && cost < bestCost)) {
                best := cluster
                bestCount := cluster.Length
                bestStrongCount := strongCount
                bestCost := cost
            }
        }
        if (!IsObject(best)) {
            if (IsObject(diagnostic))
                diagnostic.reason := "参考样本候选共识不足"
            return 0
        }

        strongBaseCandidate := 0
        for match in matches
            if (match.refIdx == 1) {
                if (this._SampleIsStrongAlignment(match))
                    strongBaseCandidate := match
            }
        if (!IsObject(strongBaseCandidate))
            for pair in pairDiagnostics
                if (pair.refIdx == 1 && pair.HasProp("candidateGlobalX")
                    && pair.HasProp("candidateGlobalY") && pair.HasProp("score")
                    && pair.HasProp("coverage") && pair.score <= 0.35
                    && pair.coverage >= 0.65) {
                    strongBaseCandidate := {ox: pair.candidateGlobalX
                        , oy: pair.candidateGlobalY}
                    break
                }
        if (IsObject(strongBaseCandidate)) {
            agreesWithBase := false
            for candidate in best
                if (Abs(candidate.ox - strongBaseCandidate.ox) <= 2
                    && Abs(candidate.oy - strongBaseCandidate.oy) <= 2) {
                    agreesWithBase := true
                    break
                }
            if (!agreesWithBase) {
                if (IsObject(diagnostic))
                    diagnostic.reason := "基准与参考坐标冲突"
                return 0
            }
        }

        selected := best[1]
        for candidate in best
            if (candidate.score < selected.score
                || (candidate.score == selected.score && candidate.coverage > selected.coverage))
                selected := candidate
        return {ox: selected.ox, oy: selected.oy}
    }

    _SampleResolveAlignment(matches, diagnostic := 0) {
        if (!matches.Length) {
            if (IsObject(diagnostic))
                diagnostic.reason := "没有匹配候选"
            return 0
        }
        clusters := []
        for _, match in matches {
            found := false
            for cluster in clusters {
                if (Abs(match.ox - cluster.anchor.ox) <= 3
                    && Abs(match.oy - cluster.anchor.oy) <= 3) {
                    cluster.items.Push(match)
                    found := true
                    break
                }
            }
            if (!found)
                clusters.Push({anchor: match, items: [match]})
        }
        best := 0, bestCount := 0, bestCost := 1.0e15, tied := false
        baseMatch := 0
        for match in matches
            if (match.refIdx == 1) {
                baseMatch := match
                break
            }
        for cluster in clusters {
            count := cluster.items.Length, cost := 0, includesBase := false
            minX := 1.0e15, maxX := -1.0e15, minY := 1.0e15, maxY := -1.0e15
            for match in cluster.items {
                cost += match.score
                if (match.refIdx == 1)
                    includesBase := true
                minX := Min(minX, match.ox), maxX := Max(maxX, match.ox)
                minY := Min(minY, match.oy), maxY := Max(maxY, match.oy)
            }
            if (count > bestCount
                || (count == bestCount && includesBase && !best.includesBase)
                || (count == bestCount && includesBase == best.includesBase && cost < bestCost)) {
                best := {items: cluster.items, includesBase: includesBase
                    , spreadX: maxX - minX, spreadY: maxY - minY}
                bestCount := count
                bestCost := cost
                tied := false
            } else if (count == bestCount && includesBase == best.includesBase && cost == bestCost)
                tied := true
        }
        if (tied) {
            if (IsObject(diagnostic))
                diagnostic.reason := "坐标结果冲突"
            return 0
        }
        if (best.spreadX > 2 || best.spreadY > 2) {
            if (IsObject(diagnostic))
                diagnostic.reason := "坐标结果分歧过大"
            return 0
        }
        if (IsObject(baseMatch) && !best.includesBase
            && this._SampleIsStrongAlignment(baseMatch)) {
            if (IsObject(diagnostic))
                diagnostic.reason := "基准与参考坐标冲突"
            return 0
        }
        if (!best.includesBase && bestCount < 2
            && !this._SampleIsStrongAlignment(best.items[1])) {
            if (IsObject(diagnostic))
                diagnostic.reason := "单参考结果置信度不足"
            return 0
        }
        if (best.includesBase && bestCount == 1
            && !this._SampleIsStrongAlignment(best.items[1])) {
            if (IsObject(diagnostic))
                diagnostic.reason := "基准匹配置信度不足"
            return 0
        }
        selected := best.items[1]
        for match in best.items
            if (match.score < selected.score
                || (match.score == selected.score && match.margin > selected.margin)
                || (match.score == selected.score && match.margin == selected.margin
                    && match.coverage > selected.coverage))
                selected := match
        return {ox: selected.ox, oy: selected.oy}
    }

    _SampleGetPairAlignment(refRec, sampleRec, diagnostic := 0) {
        key := refRec.Path "`n" sampleRec.Path
        cache := this._samplePairCache
        if (cache.Has(key)) {
            cached := cache[key]
            if (IsObject(diagnostic))
                for name, value in cached.Diagnostic.OwnProps()
                    diagnostic.%name% := value
            return IsObject(cached.Result) ? cached.Result.Clone() : 0
        }
        session := this._sampleSession
        details := {}
        result := this._AlignPairTo(refRec, sampleRec, details)
        if (IsObject(diagnostic))
            for name, value in details.OwnProps()
                diagnostic.%name% := value
        this._SampleStorePairAlignment(refRec, sampleRec, result, details, session)
        return result
    }

    _SampleStorePairAlignment(refRec, sampleRec, result, details, session := unset) {
        session := IsSet(session) ? session : this._sampleSession
        key := refRec.Path "`n" sampleRec.Path
        reason := details.HasProp("reason") ? details.reason : ""
        wasCritical := A_IsCritical
        Critical "On"
        try {
            if (session == this._sampleSession && this.SampleMode
                && (IsObject(result) || (reason != "" && reason != "图片读取失败"
                    && reason != "位图创建失败" && reason != "图像缩放失败" && reason != "像素读取失败")))
                this._samplePairCache[key] := {RefPath: refRec.Path, SamplePath: sampleRec.Path
                    , Result: IsObject(result) ? result.Clone() : 0, Diagnostic: details.Clone()}
        } finally {
            Critical wasCritical
        }
    }
