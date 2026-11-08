
    _SampleRunParallelAlignmentBatch(frames, refs, sampleIdx, session, parallelLimit := 4) {
        if (!refs.Length || !this.SampleMode)
            return 0
        tasks := []
        for refIdx in refs
            tasks.Push({refIdx: refIdx, sampleIdx: sampleIdx})
        return this._SampleRunPairTaskBatch(frames, tasks, session, parallelLimit)
    }

    _SampleRunPairTaskBatch(frames, tasks, session, parallelLimit := 4) {
        if (!this.SampleMode || !tasks.Length)
            return 0
        requestedParallelLimit := Min(4, Max(1, Integer(parallelLimit)))
        parallelLimit := this._SampleGetEffectivePairParallelLimit(
            frames, tasks, requestedParallelLimit)
        if (parallelLimit < requestedParallelLimit)
            this._SampleCountAlignmentStat("adaptiveSerialBatches")
        stats := this._sampleAlignmentStats
        if (IsObject(stats))
            stats.effectiveParallelLimit := Max(stats.effectiveParallelLimit, parallelLimit)
        results := [], pending := []
        results.Length := tasks.Length
        this._SampleCountAlignmentStat("plannedPairs", tasks.Length)
        for taskIndex, spec in tasks {
            refRec := spec.HasProp("refRec") ? spec.refRec : frames[spec.refIdx]
            sampleRec := frames[spec.sampleIdx]
            key := refRec.Path "`n" sampleRec.Path
            mode := spec.HasProp("mode") ? spec.mode : "align"
            if (mode == "align" && this._samplePairCache.Has(key)) {
                this._SampleCountAlignmentStat("pairCacheHits")
                diagnostic := {refIdx: spec.refIdx}
                offset := this._SampleGetPairAlignment(refRec, sampleRec, diagnostic)
                results[taskIndex] := {taskIndex: taskIndex, refIdx: spec.refIdx
                    , sampleIdx: spec.sampleIdx, offset: offset, diagnostic: diagnostic}
            } else
                pending.Push({taskIndex: taskIndex, refIdx: spec.refIdx
                    , sampleIdx: spec.sampleIdx, refRec: refRec, sampleRec: sampleRec
                    , mode: mode, cacheResult: mode == "align"
                    , expectedX: spec.HasProp("expectedX") ? spec.expectedX : 0
                    , expectedY: spec.HasProp("expectedY") ? spec.expectedY : 0})
        }
        if (!pending.Length) {
            ordered := []
            for taskIndex, spec in tasks
                ordered.Push(results[taskIndex])
            return ordered
        }
        if (!A_IsCompiled && !FileExist(this._sampleWorkerRoot "\Thread\Work.ahk"))
            return 0
        if (A_IsCompiled && !FileExist(this._sampleWorkerRoot "\Thread\Work.exe"))
            return 0

        waveResults := this._SampleRunPairWorkerBatch(pending, session, parallelLimit)
        if (!IsObject(waveResults)) {
            this._SampleStopAlignmentWorkers()
            return 0
        }
        for result in waveResults
            results[result.taskIndex] := result
        ordered := []
        for taskIndex, spec in tasks {
            if (!IsObject(results[taskIndex]))
                return 0
            ordered.Push(results[taskIndex])
        }
        return ordered
    }

    _SampleGetEffectivePairParallelLimit(frames, tasks, requestedLimit) {
        requestedLimit := Min(4, Max(1, Integer(requestedLimit)))
        if (requestedLimit <= 1)
            return requestedLimit

        maxPixels := 0
        for task in tasks {
            refRec := task.HasProp("refRec") ? task.refRec : frames[task.refIdx]
            sampleRec := frames[task.sampleIdx]
            maxPixels := Max(maxPixels, refRec.W * refRec.H, sampleRec.W * sampleRec.H)
        }

        nativeEdgeMap := !!this._SampleNativeAlignmentProc("SampleBuildEdgeMap")
        if (!nativeEdgeMap) {
            ; Without native edge-map construction, worker startup and IPC dominate small pairs.
            if (maxPixels <= 128 * 1024)
                return 1
            if (maxPixels <= 256 * 1024)
                return Min(2, requestedLimit)
        }
        return requestedLimit
    }

    _SampleRunPairWorkerBatch(pending, session, parallelLimit) {
        results := [], nextTask := 1, completedCount := 0
        try {
            workerCount := Min(parallelLimit, pending.Length)
            if (!this._SampleEnsureAlignmentWorkers(workerCount, session))
                return 0
            activeWorkers := []
            loop workerCount
                activeWorkers.Push(this._sampleAlignWorkers[A_Index])
            for worker in activeWorkers {
                if (session != this._sampleSession || !this.SampleMode)
                    return 0
                this._SampleAssignAlignmentTask(worker, pending[nextTask])
                nextTask += 1
            }

            while (completedCount < pending.Length) {
                if (session != this._sampleSession || !this.SampleMode)
                    return 0
                for worker in activeWorkers {
                    if (!worker.busy)
                        continue
                    if (FileExist(worker.resultPath)) {
                        task := worker.task
                        try {
                            response := JSON.parse(FileRead(worker.resultPath), false, false)
                            FileDelete(worker.resultPath)
                            if (response.error != "")
                                throw Error(response.error)
                            diagnostic := {refIdx: task.refIdx}
                            for name, value in response.diagnostic.OwnProps()
                                diagnostic.%name% := value
                            offset := response.match
                            if (IsObject(offset))
                                offset := {ox: offset.ox, oy: offset.oy, score: offset.score
                                    , margin: offset.margin, coverage: offset.coverage
                                    , texture: offset.texture}
                            else
                                offset := 0
                            if (task.cacheResult)
                                this._SampleStorePairAlignment(task.refRec, task.sampleRec
                                    , offset, response.diagnostic, session)
                            this._SampleCountAlignmentStat("executedPairs")
                            this._SampleCountAlignmentStat("edgeCacheHits", response.edgeCacheHits)
                            this._SampleCountAlignmentStat("edgeCacheBuilds", response.edgeCacheBuilds)
                            results.Push({taskIndex: task.taskIndex, refIdx: task.refIdx
                                , sampleIdx: task.sampleIdx, offset: offset, diagnostic: diagnostic})
                        } catch {
                            return 0
                        }
                        worker.busy := false
                        worker.task := 0
                        completedCount += 1
                        if (nextTask <= pending.Length) {
                            if (session != this._sampleSession || !this.SampleMode)
                                return 0
                            this._SampleAssignAlignmentTask(worker, pending[nextTask])
                            nextTask += 1
                        }
                        continue
                    }
                    if (!ProcessExist(worker.pid))
                        return 0
                }
                if (completedCount < pending.Length)
                    Sleep(5)
            }
            return results.Length == pending.Length ? results : 0
        } catch {
            return 0
        }
    }

    _SampleEnsureAlignmentWorkers(workerCount, session) {
        loop Min(workerCount, this._sampleAlignWorkers.Length) {
            if (!ProcessExist(this._sampleAlignWorkers[A_Index].pid)) {
                this._SampleStopAlignmentWorkers()
                break
            }
        }
        if (this._sampleWorkerDir == "") {
            this._sampleWorkerDir := A_Temp "\RMT_SampleAlign_" DllCall("GetCurrentProcessId") "_" Format("{:X}", ObjPtr(this))
            DirCreate(this._sampleWorkerDir)
        }
        while (this._sampleAlignWorkers.Length < workerCount) {
            if (session != this._sampleSession || !this.SampleMode)
                return false
            this._sampleJobSeq += 1
            prefix := this._sampleWorkerDir "\worker-" this._sampleJobSeq
            worker := {pid: 0, handle: 0, prefix: prefix
                , requestPath: prefix ".request.json", resultPath: prefix ".result.json"
                , readyPath: prefix ".ready", stopPath: prefix ".stop"
                , busy: false, task: 0}
            if (A_IsCompiled)
                command := '"' this._sampleWorkerRoot '\Thread\Work.exe"'
                    . ' --sample-align-worker "' prefix '" "4194304"'
            else
                command := '"' A_AhkPath '" "' this._sampleWorkerRoot '\Thread\Work.ahk"'
                    . ' --sample-align-worker "' prefix '" "4194304"'
            pid := 0, wasCritical := A_IsCritical
            Critical "On"
            try {
                Run(command, this._sampleWorkerRoot, "Hide", &pid)
                worker.pid := pid
                worker.handle := DllCall("OpenProcess", "uint", 0x00100001
                    , "int", false, "uint", worker.pid, "ptr")
                this._sampleAlignWorkers.Push(worker)
                this._SampleCountAlignmentStat("workerStarts")
            } finally {
                Critical wasCritical
            }
        }
        startedAt := A_TickCount
        loop {
            if (session != this._sampleSession || !this.SampleMode)
                return false
            readyCount := 0
            loop workerCount {
                worker := this._sampleAlignWorkers[A_Index]
                if (FileExist(worker.readyPath))
                    readyCount += 1
                else if (!ProcessExist(worker.pid))
                    return false
            }
            if (readyCount == workerCount)
                return true
            if (A_TickCount - startedAt > 10000)
                return false
            Sleep(10)
        }
    }

    _SampleAssignAlignmentTask(worker, task) {
        try FileDelete(worker.resultPath)
        try FileDelete(worker.requestPath)
        worker.task := task
        worker.busy := true
        jobData := Map("refPath", task.refRec.Path, "refW", task.refRec.W, "refH", task.refRec.H
            , "samplePath", task.sampleRec.Path, "sampleW", task.sampleRec.W, "sampleH", task.sampleRec.H
            , "mode", task.mode, "expectedX", task.expectedX, "expectedY", task.expectedY)
        FileAppend(JSON.stringify(jobData), worker.requestPath, "UTF-8")
    }

    _SampleStopAlignmentWorkers() {
        for worker in this._sampleAlignWorkers {
            handle := worker.handle
            if (!handle && ProcessExist(worker.pid))
                handle := DllCall("OpenProcess", "uint", 0x00100001, "int", false, "uint", worker.pid, "ptr")
            if (handle) {
                if (ProcessExist(worker.pid)) {
                    if (worker.busy)
                        DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                    else {
                        try FileAppend("stop", worker.stopPath, "UTF-8")
                        if (DllCall("WaitForSingleObject", "ptr", handle, "uint", 250, "uint") != 0)
                            DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                    }
                    DllCall("WaitForSingleObject", "ptr", handle, "uint", 1000, "uint")
                }
                DllCall("CloseHandle", "ptr", handle)
                worker.handle := 0
            }
            try FileDelete(worker.requestPath)
            try FileDelete(worker.resultPath)
            try FileDelete(worker.resultPath ".tmp")
            try FileDelete(worker.readyPath)
            try FileDelete(worker.stopPath)
        }
        this._sampleAlignWorkers := []
        if (this._sampleWorkerDir != "") {
            try DirDelete(this._sampleWorkerDir)
            this._sampleWorkerDir := ""
        }
    }
