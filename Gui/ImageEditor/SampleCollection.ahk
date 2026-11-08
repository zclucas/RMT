
    OnSampleToolClick(*) {
        if (!IsObject(this.ui) || this.EditorMode != "original")
            return
        this._SetSampleMode(!this.SampleMode)
    }

    _SetSampleMode(on) {
        if (on == this.SampleMode)
            return
        this.SampleMode := on
        if (on) {
            this._ExitOriginalTool()
            SetTimer(this._thumbTimer, 0)
            this._SampleRetile()
            this._SampleRefreshPreview()
        } else {
            this._SampleCleanupTemp()
            this._Render()
        }
        this._SyncMatchModeUi()
    }

    _SampleShot(*) {
        if (!this.SampleMode || this.EditorMode != "original"
            || this._sampleShotBusy || this._sampleImportBusy || this._sampleComputing)
            return
        if (this._SampleCount() >= 60) {
            RmtDialog.Info(GetLang("样本最多 60 张"), GetLang("样本抠图"))
            return
        }
        session := this._sampleSession
        this._sampleShotBusy := true
        this._samplePickRect := ""
        this._SampleSyncControls()
        try {
            if (this.SampleFixedPos && IsObject(this.SampleShotRect))
                this._samplePickRect := this.SampleShotRect.Clone()
            else
                TogSelectArea(true, this._sampleShotAction, false)
            if (session == this._sampleSession)
                this._SampleShotPending(session)
        } catch as e {
            RmtDialog.Info(GetLang("截图处理失败：") e.Message, GetLang("样本抠图"))
        } finally {
            if (session == this._sampleSession) {
                this._samplePickRect := ""
                this._sampleShotBusy := false
                this._SampleSyncControls()
                if (!this._SampleCommitQueuedFrames() && this._samplePending)
                    SetTimer(this._sampleTimer, -1)
            }
        }
    }

    ; 框选回调只记录矩形，抓屏留到 TogSelectArea 完成清理之后。
    _SampleAreaPicked(x1, y1, x2, y2) {
        if (!this._sampleShotBusy || !this.SampleMode
            || Abs(x2 - x1) < 4 || Abs(y2 - y1) < 4)
            return
        this._samplePickRect := {x: Min(x1, x2), y: Min(y1, y2), w: Abs(x2 - x1), h: Abs(y2 - y1)}
    }

    _SampleShotPending(session) {
        if (session != this._sampleSession || !this.SampleMode || this._SampleCount() >= 60)
            return
        rect := this._samplePickRect
        if (!IsObject(rect))
            return
        bmp := 0, path := ""
        try {
            bmp := Gdip_BitmapFromScreen(rect.x "|" rect.y "|" rect.w "|" rect.h)
            if (bmp <= 0) {
                RmtDialog.Info(GetLang("截屏失败"), GetLang("样本抠图"))
                return
            }
            path := this._SampleTempPath()
            if (Gdip_SaveBitmapToFile(bmp, path) != 0) {
                RmtDialog.Info(GetLang("截屏失败"), GetLang("样本抠图"))
                return
            }
            if (session != this._sampleSession)
                return
            if (this._SampleAdd(path, rect, this.SampleFixedPos)) {
                this.SampleShotRect := rect.Clone()
                path := ""
            }
        } finally {
            if (bmp > 0)
                Gdip_DisposeImage(bmp)
            this._SampleDiscardPath(path)
        }
    }

    _SampleImport(*) {
        if (!this.SampleMode || this.EditorMode != "original"
            || this._sampleShotBusy || this._sampleImportBusy || this._sampleComputing)
            return
        if (this._SampleCount() >= 60) {
            RmtDialog.Info(GetLang("样本最多 60 张"), GetLang("样本抠图"))
            return
        }
        session := this._sampleSession
        this._sampleImportBusy := true
        this._SampleSyncControls()
        try {
            paths := FileSelect("M3", , GetLang("选择样本图片")
                , GetLang("图片文件 (*.png;*.jpg;*.jpeg;*.bmp)"))
            if (session == this._sampleSession && IsObject(paths) && paths.Length)
                this._SampleImportPaths(paths, session)
        } finally {
            if (session == this._sampleSession) {
                this._sampleImportBusy := false
                this._SampleSyncControls()
                if (!this._SampleCommitQueuedFrames() && this._samplePending)
                    SetTimer(this._sampleTimer, -1)
            }
        }
    }

    _SampleImportPaths(paths, session) {
        failed := 0, skipped := 0
        for index, source in paths {
            if (session != this._sampleSession || !this.SampleMode)
                break
            if (this._SampleCount() >= 60) {
                skipped := paths.Length - index + 1
                break
            }
            bmp := 0, path := ""
            try {
                bmp := Gdip_CreateBitmapFromFile(source)
                if (!bmp)
                    throw Error(GetLang("图片读取失败"))
                path := this._SampleTempPath()
                ; 独立 PNG 快照保留原像素，后续样本清理不接触用户文件。
                if (Gdip_SaveBitmapToFile(bmp, path) != 0 || session != this._sampleSession
                    || !this._SampleAdd(path))
                    throw Error(GetLang("图片读取失败"))
                path := ""
            } catch {
                failed += 1
            } finally {
                if (bmp)
                    Gdip_DisposeImage(bmp)
                this._SampleDiscardPath(path)
            }
        }
        if (session == this._sampleSession) {
            this._SampleRetile()
            if (failed || skipped)
                RmtDialog.Info(Format(GetLang("导入跳过：读取失败 {1} 张，超过上限 {2} 张")
                    , failed, skipped), GetLang("样本抠图"))
        }
    }

    _SampleFixedChanged(on, *) {
        this.SampleFixedPos := on
    }

    _SampleThresholdChanged(state, ctrl, event) {
        v := (IsObject(state) && state.Has("SampleThresholdSlider")) ? state["SampleThresholdSlider"] : ""
        if (!IsNumber(v))
            return
        value := Min(64, Max(0, Integer(v)))
        if (value != this.SampleThreshold) {
            this.SampleThreshold := value
        }
        try this.ui.Update("SampleThresholdVal", "Text", String(this.SampleThreshold))
        this._samplePending := true
        this._SampleSyncControls()
        SetTimer(this._sampleTimer, -150)
    }

    _SampleFlushThreshold(*) {
        if (this._samplePending && this.SampleMode) {
            this._samplePending := false
            this._SampleRefreshPreview()
        }
    }

    _SampleAdd(path, rect := "", fixed := false) {
        if (!this.SampleMode || this._SampleCount() >= 60)
            return false
        session := this._sampleSession
        w := 0, h := 0
        probe := Gdip_CreateBitmapFromFile(path)
        if (!probe)
            return false
        Gdip_GetImageDimensions(probe, &w, &h)
        Gdip_DisposeImage(probe)
        if (w < 1 || h < 1 || session != this._sampleSession || !this.SampleMode)
            return false
        this._sampleQueuedFrames.Push({Path: path, W: w, H: h, OffX: 0, OffY: 0
            , Aligned: false, Fixed: fixed, Rect: IsObject(rect) ? rect.Clone() : ""})
        if (!this._SampleCommitQueuedFrames() && !this._sampleImportBusy)
            this._SampleRetile()
        return true
    }

    _SampleCount() {
        return this.SampleFrames.Length + this._sampleQueuedFrames.Length
    }

    _SampleCommitQueuedFrames() {
        if (!this.SampleMode || this._sampleBusy || this._sampleComputing
            || this._sampleShotBusy || this._sampleImportBusy || !this._sampleQueuedFrames.Length)
            return false
        ; 只在计算快照释放后一次性提交，采集过程不使正在运行的对齐失效。
        wasCritical := A_IsCritical
        Critical "On"
        try {
            for frame in this._sampleQueuedFrames {
                frame.Aligned := this.SampleFrames.Length == 0
                if (!frame.Aligned && frame.Fixed && IsObject(frame.Rect)) {
                    baseRect := this.SampleFrames[1].Rect
                    rect := frame.Rect
                    frame.Aligned := IsObject(baseRect) && rect.x == baseRect.x && rect.y == baseRect.y
                        && rect.w == baseRect.w && rect.h == baseRect.h
                }
                frame.DeleteProp("Fixed")
                this.SampleFrames.Push(frame)
            }
            this._sampleQueuedFrames := []
            this._sampleRevision += 1
            this._sampleAlignScheduled := this.SampleFrames.Length > 1
        } finally {
            Critical wasCritical
        }
        this._SampleClearPreview()
        this._SampleRetile()
        this._SampleScheduleAlign()
        return true
    }

    _SampleDelete(i, *) {
        if (this._sampleBusy || this._sampleComputing || this._sampleShotBusy || this._sampleImportBusy
            || this._sampleQueuedFrames.Length
            || i < 1 || i > this.SampleFrames.Length)
            return
        path := this.SampleFrames[i].Path
        this._SampleDiscardReusableAlignmentEffect()
        this.SampleFrames.RemoveAt(i)
        this._sampleRevision += 1
        if (i == 1 && this.SampleFrames.Length) {
            newBase := this.SampleFrames[1]
            if (newBase.Aligned) {
                baseX := newBase.OffX, baseY := newBase.OffY
                for frame in this.SampleFrames {
                    if (frame.Aligned) {
                        frame.OffX -= baseX
                        frame.OffY -= baseY
                    } else
                        frame.OffX := 0, frame.OffY := 0
                    frame.AlignDiagnostic := ""
                }
                newBase.OffX := 0, newBase.OffY := 0
            } else {
                for idx, frame in this.SampleFrames {
                    frame.OffX := 0, frame.OffY := 0, frame.Aligned := idx == 1
                    frame.AlignDiagnostic := ""
                }
            }
        }
        this._SampleClearPreview()
        this._SampleRetile()
        this._SampleDiscardPath(path)
        this._SampleScheduleAlign()
    }

    _SampleRetile() {
        if (!IsObject(this.ui))
            return
        session := this._sampleSession
        revision := this._sampleRevision
        queuedCount := this._sampleQueuedFrames.Length
        committed := this.SampleFrames.Length
        frames := this.SampleFrames.Clone()
        for frame in this._sampleQueuedFrames
            frames.Push(frame)
        loop 60 {
            if (session != this._sampleSession || revision != this._sampleRevision
                || queuedCount != this._sampleQueuedFrames.Length)
                return
            i := A_Index
            has := i <= frames.Length
            frame := has ? frames[i] : ""
            try this.ui.Update("SampleTile" i, "Visibility", has ? "Visible" : "Collapsed")
            if (session != this._sampleSession || revision != this._sampleRevision
                || queuedCount != this._sampleQueuedFrames.Length)
                return
            if (has) {
                queued := i > committed
                try this.ui.Update("SampleThumbImg" i, "Source", StrReplace(frame.Path, "\", "/"))
                try this.ui.Update("SampleTileBorder" i, "BorderBrush"
                    , queued || frame.Aligned ? "{DynamicResource ControlBorder}" : "#FFFF3030")
                if (queued) {
                    tip := GetLang("等待对齐")
                } else if (!frame.Aligned) {
                    tip := GetLang("未对齐：计算时跳过该样本")   ; 只显示第一行，不追加诊断原因
                } else {
                    tip := ""                                 ; 已对齐（含基准）：不弹悬停提示
                }
                try this.ui.Update("SampleHitbox" i, "ToolTip", tip)
                try this.ui.Update("SampleHitbox" i, "Visibility", tip != "" ? "Visible" : "Collapsed")
                try this.ui.Update("BtnSampleDel" i, "ToolTip"
                    , Format(GetLang("删除样本 {1}"), i))
            } else {
                try this.ui.Update("SampleThumbImg" i, "Source", "")
                try this.ui.Update("SampleHitbox" i, "Visibility", "Collapsed")
            }
        }
        this._SampleSyncControls()
    }

    _SampleAlignedCount() {
        count := 0
        for frame in this.SampleFrames
            if (frame.Aligned)
                count += 1
        return count
    }

    _SampleSyncControls() {
        if (!IsObject(this.ui))
            return
        idle := !this._sampleBusy && !this._sampleComputing && !this._sampleShotBusy
            && !this._sampleImportBusy && !this._sampleQueuedFrames.Length
        canCollect := !this._sampleShotBusy && !this._sampleImportBusy
            && !this._sampleComputing && this._SampleCount() < 60
        active := this.SampleMode && this.EditorMode == "original"
        aligned := this._SampleAlignedCount()
        total := this.SampleFrames.Length
        if (this._sampleBusy)
            status := GetLang("当前状态：正在对齐")
        else if (this._sampleAlignScheduled || this._sampleQueuedFrames.Length)
            status := Format(GetLang("当前状态：等待对齐 {1}/{2}"), aligned, total)
        else if (aligned < 2)
            status := Format(GetLang("当前状态：已对齐 {1}/{2}，至少需要 2 张"), aligned, total)
        else if (this._sampleComputing || this._samplePending)
            status := Format(GetLang("当前状态：正在处理 {1}/{2}"), aligned, total)
        else if (this._samplePreviewFailedSig == (this._sampleRevision "|" this.SampleThreshold))
            status := Format(GetLang("当前状态：预览生成失败 {1}/{2}"), aligned, total)
        else if (this.SamplePreviewSig == (this._sampleRevision "|" this.SampleThreshold)
            && FileExist(this.SamplePreviewPath))
            status := Format(GetLang("当前状态：已对齐 {1}/{2}"), aligned, total)
        else
            status := Format(GetLang("当前状态：已对齐 {1}/{2}，预览待生成"), aligned, total)
        if (this._sampleQueuedFrames.Length && !this._sampleBusy)
            status .= "`n" Format(GetLang("待加入 {1} 张"), this._sampleQueuedFrames.Length)
        try this.ui.Update("SampleStatusText", "Text", status)
        unaligned := Max(0, this._SampleCount() - aligned)
        unalignedText := unaligned > 0 && !this._sampleBusy
            ? Format(GetLang("{1} 张未对齐"), unaligned) : ""
        try this.ui.Update("SampleUnalignedText", "Text", unalignedText)
        try this.ui.Update("SampleUnalignedText", "Foreground"
            , unaligned > 0 ? "#FFFF9999" : "{DynamicResource TextSub}")
        try this.ui.Update("SampleUnalignedText", "Visibility"
            , active && unaligned > 0 && !this._sampleBusy ? "Visible" : "Collapsed")
        try this.ui.Update("BtnSampleShot", "IsEnabled"
            , active && canCollect ? "True" : "False")
        try this.ui.Update("BtnSampleImport", "IsEnabled", active && canCollect ? "True" : "False")
        extractEnabled := active && idle && !this._sampleAlignScheduled && this._SampleAlignedCount() >= 2
        try this.ui.Update("BtnSampleExtract", "IsEnabled", extractEnabled ? "True" : "False")
        if (extractEnabled)
            extractTip := GetLang("生成透明底 PNG，存为新文件（分辨率 = 第 1 张样本）")
        else if (this._SampleCount() < 2)
            extractTip := GetLang("还不能提取：至少需要 2 张样本")
        else if (!idle || this._sampleAlignScheduled)
            extractTip := GetLang("还不能提取：正在处理中，请稍候")
        else
            extractTip := GetLang("还不能提取：已对齐样本不足 2 张，检查红框样本")
        try this.ui.Update("BtnSampleExtract", "ToolTip", extractTip)
        loop 60
            try this.ui.Update("BtnSampleDel" A_Index, "IsEnabled", idle ? "True" : "False")
        this._SyncSampleModeUi()
    }
