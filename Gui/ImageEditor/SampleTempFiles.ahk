
    _SampleTempPath() {
        this._sampleSeq += 1
        path := (A_Temp "\RMT_sample_" DllCall("GetCurrentProcessId") "_" this._windowToken
            "_" A_TickCount "_" this._sampleSeq ".png")
        this._sampleTemp.Push(path)
        return path
    }

    _SampleDiscardPath(path) {
        if (path == "")
            return
        this._SampleForgetAlignment(path)
        try FileDelete(path)
        if (FileExist(path))
            this._sampleGarbage.Push(path)
    }

    _SampleCollectGarbage() {
        remaining := []
        for path in this._sampleGarbage {
            try FileDelete(path)
            if (FileExist(path))
                remaining.Push(path)
        }
        this._sampleGarbage := remaining
    }

    _SampleCleanupTemp() {
        this._sampleSession += 1
        this._sampleRevision += 1
        this._SampleStopAlignmentWorkers()
        this._samplePairCache := Map()
        this._sampleEdgeCache := Map()
        this._sampleEdgeCacheBytes := 0
        this._sampleEdgeCacheTick := 0
        this.SampleMode := false
        SetTimer(this._sampleTimer, 0)
        SetTimer(this._sampleAlignTimer, 0)
        if (this._sampleShotBusy)
            try TogSelectArea(false)
        this._sampleShotBusy := false
        this._sampleImportBusy := false
        this._sampleAlignScheduled := false
        this._samplePending := false
        this._sampleDirty := false
        this._samplePickRect := ""
        this.SampleShotRect := ""
        this._SampleDiscardReusableAlignmentEffect()
        this._SampleClearPreview()
        paths := this._sampleTemp
        for frame in this.SampleFrames
            paths.Push(frame.Path)
        for frame in this._sampleQueuedFrames
            paths.Push(frame.Path)
        this.SampleFrames := []
        this._sampleQueuedFrames := []
        this._sampleTemp := []
        this._SampleRetile()
        for path in paths
            this._SampleDiscardPath(path)
        this._SampleCollectGarbage()
    }
