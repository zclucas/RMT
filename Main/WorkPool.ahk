#Requires AutoHotkey v2.0
class WorkPool {
    __New() {
        this.maxSize := MySoftData.MutiThreadNum
        this.pool := []              ; 对象池数组
        this.isDynamic := (this.maxSize == -1)
        this.dynamicMaxLimit := 10
        this.corePoolSize := MySoftData.DynamicCorePoolSize
        this.elasticTimeout := MySoftData.ElasticTimeout * 1000
        this.dynamicMinSize := this.corePoolSize
        this.currentMaxIndex := 0
        this.activeWorkers := Map()
        this.workerIdleTime := Map()
        this.recycledIndices := []
        this.shrinkTimerFunc := ""
        this.hwndMap := Map()
        this.pidMap := Map()
        this.MessageArr := []   ;消息数组，避免消息重复处理
        this.MessageMap := Map()
        this.mainPID := DllCall("GetCurrentProcessId")  ; 获取主进程PID

        if (this.isDynamic) {
            loop this.dynamicMinSize {
                this.CreateWorker(A_Index)
            }
        } else {
            loop this.maxSize {
                workPath := A_ScriptDir "\Thread\Work" A_Index ".exe"
                if (!FileExist(workPath) && this.maxSize <= 10) {
                    FileCopy(A_ScriptDir "\Thread\Work1.exe", workPath)
                }
                Run (Format("{} {} {} {}", workPath, MySoftData.MyGui.Hwnd, A_Index, this.mainPID))
                this.activeWorkers.Set(A_Index, workPath)
                this.currentMaxIndex := A_Index
            }
        }

        OnMessage(WM_LOAD_WORK, this.OnFinishLoad.Bind(this))  ; 工作器完成工作回调
        OnMessage(WM_RELEASE_WORK, this.OnRelease.Bind(this))  ; 工作器完成工作回调
        OnMessage(WM_STOP_MACRO, this.OnStopMacro.Bind(this))  ;终止其他宏
        OnMessage(WM_TR_MACRO, this.OnTriggerMacro.Bind(this)) ;触发宏
        OnMessage(WM_COPYDATA, this.OnGetCmd.Bind(this)) ;接收到命令

        if (this.isDynamic) {
            this.shrinkTimerFunc := ObjBindMethod(this, "IdleShrinkCheck")
            SetTimer(this.shrinkTimerFunc, 10000)
        }
    }

    __Delete() {
        if (this.isDynamic && this.shrinkTimerFunc != "") {
            SetTimer(this.shrinkTimerFunc, 0)
            this.shrinkTimerFunc := ""
        }
        this.Clear()
    }

    GetNextWorkerIndex() {
        if (this.recycledIndices.Length >= 1) {
            return this.recycledIndices.Pop()
        }
        return this.currentMaxIndex + 1
    }

    CreateWorker(workerIndex) {
        workPath := A_ScriptDir "\Thread\Work" workerIndex ".exe"
        if (!FileExist(workPath)) {
            FileCopy(A_ScriptDir "\Thread\Work1.exe", workPath)
        }
        Run (Format("{} {} {} {}", workPath, MySoftData.MyGui.Hwnd, workerIndex, this.mainPID))
        this.activeWorkers.Set(workerIndex, workPath)
        if (workerIndex > this.currentMaxIndex) {
            this.currentMaxIndex := workerIndex
        }
    }

    CheckHasFreeWorker() {
        if (this.isDynamic) {
            activeCount := this.activeWorkers.Count
            return this.pool.Length >= 1 || activeCount < this.dynamicMaxLimit
        }
        return this.pool.Length >= 1
    }

    CheckEnableMutiThread() {
        if (this.isDynamic)
            return true
        return this.maxSize >= 1
    }

    GetActiveCount() {
        return this.activeWorkers.Count - this.pool.Length
    }

    ; 从池中获取一个对象
    Get() {
        workPath := ""
        if (this.pool.Length >= 1) {
            workPath := this.pool.Pop()
            workerIndex := this.GetWorkIndex(workPath)
            this.workerIdleTime.Delete(workerIndex)
        } else if (this.isDynamic && this.activeWorkers.Count < this.dynamicMaxLimit) {
            newIndex := this.GetNextWorkerIndex()
            this.CreateWorker(newIndex)
        }
        return workPath
    }

    GetWorkPath(workIndex) {
        return A_ScriptDir "\Thread\Work" workIndex ".exe"
    }

    GetWorkIndex(workPath) {
        workIndex := StrReplace(workPath, A_ScriptDir "\Thread\Work")
        workIndex := StrReplace(workIndex, ".exe")
        return workIndex
    }

    GetWorkHwnd(workPath) {
        if (!this.hwndMap.Has(workPath)) {
            workIndex := StrReplace(workPath, A_ScriptDir "\Thread\Work")
            workIndex := StrReplace(workIndex, ".exe")
            try {
                hwnd := WinGetID("RMTWork" workIndex)
                this.hwndMap.Set(workPath, hwnd)
            }
        }
        return this.hwndMap.Get(workPath, 0)
    }

    GetActiveWorkerList() {
        list := []
        if (this.isDynamic) {
            for workPath in this.activeWorkers {
                list.Push(workPath)
            }
        } else {
            loop this.maxSize {
                list.Push(A_ScriptDir "\Thread\Work" A_Index ".exe")
            }
        }
        return list
    }

    ; 清空对象池
    Clear() {
        workerList := this.GetActiveWorkerList()
        loop workerList.Length {
            this.PostMessage(WM_CLEAR_WORK, workerList[A_Index], 0, 0)
        }
        this.pool := []
        this.activeWorkers := Map()
        this.workerIdleTime := Map()
        this.recycledIndices := []
        this.currentMaxIndex := 0
    }

    PostMessage(type, workPath, wParam, lParam) {
        hwnd := this.GetWorkHwnd(workPath)
        try {
            PostMessage(type, wParam, lParam, , "ahk_id " hwnd)
        }
    }

    SendMessage(type, workPath, str) {
        CopyDataStruct := Buffer(3 * A_PtrSize)  ; 分配结构的内存区域.
        ; 首先设置结构的 cbData 成员为字符串的大小, 包括它的零终止符:
        SizeInBytes := (StrLen(str) + 1) * 2
        NumPut("Ptr", SizeInBytes  ; 操作系统要求这个需要完成.
            , "Ptr", StrPtr(str)  ; 设置 lpData 为到字符串自身的指针.
            , CopyDataStruct, A_PtrSize)
        hwnd := this.GetWorkHwnd(workPath)
        try {
            SendMessage(type, 0, CopyDataStruct, , "ahk_id " hwnd)
        }
    }

    IdleShrinkCheck() {
        if (this.pool.Length <= this.corePoolSize)
            return
        now := A_TickCount
        shrinkIndices := []
        for workerIndex, idleTick in this.workerIdleTime {
            if ((now - idleTick) >= this.elasticTimeout) {
                shrinkIndices.Push(workerIndex)
            }
        }
        maxShrink := this.pool.Length - this.corePoolSize
        if (shrinkIndices.Length == 0 || maxShrink <= 0)
            return
        loop Min(shrinkIndices.Length, maxShrink) {
            targetIndex := shrinkIndices[A_Index]
            workPath := A_ScriptDir "\Thread\Work" targetIndex ".exe"
            this.PostMessage(WM_CLEAR_WORK, workPath, 0, 0)
            this.activeWorkers.Delete(targetIndex)
            this.workerIdleTime.Delete(targetIndex)
            this.hwndMap.Delete(workPath)
            this.pidMap.Delete(targetIndex)
            this.recycledIndices.Push(targetIndex)
            poolIndex := 0
            loop this.pool.Length {
                if (this.GetWorkIndex(this.pool[A_Index]) == targetIndex) {
                    poolIndex := A_Index
                    break
                }
            }
            if (poolIndex > 0) {
                this.pool.RemoveAt(poolIndex)
            }
        }
    }

    OnRelease(wParam, lParam, msg, hwnd) {
        tableIndex := wParam
        itemIndex := lParam
        tableItem := MySoftData.TableInfo[tableIndex]
        workerIndex := tableItem.IsWorkIndexArr[itemIndex]
        workPath := A_ScriptDir "\Thread\Work" workerIndex ".exe"
        this.pool.Push(workPath)
        this.workerIdleTime.Set(workerIndex, A_TickCount)
        tableItem.IsWorkIndexArr[itemIndex] := false
    }

    OnFinishLoad(wParam, lParam, msg, hwnd) {
        workPath := A_ScriptDir "\Thread\Work" wParam ".exe"
        isInPool := false
        loop this.pool.Length {
            if (this.pool[A_Index] == workPath) {
                isInPool := true
                break
            }
        }
        if (!isInPool) {
            this.pool.Push(workPath)
        }
        this.workerIdleTime.Set(wParam, A_TickCount)
        if (!this.activeWorkers.Has(wParam)) {
            this.activeWorkers.Set(wParam, workPath)
        }
        if (wParam > this.currentMaxIndex) {
            this.currentMaxIndex := wParam
        }
    }

    OnStopMacro(wParam, lParam, msg, hwnd) {
        tableIndex := wParam
        itemIndex := lParam
        tableItem := MySoftData.TableInfo[tableIndex]
        WorkerIndex := tableItem.IsWorkIndexArr[itemIndex]
        if (WorkerIndex != 0) {
            workPath := MyWorkPool.GetWorkPath(WorkerIndex)
            MyWorkPool.PostMessage(WM_STOP_MACRO, workPath, tableIndex, itemIndex)
            return
        }

        KillTableItemMacro(tableItem, itemIndex)
    }

    OnTriggerMacro(wParam, lParam, msg, hwnd) {
        TriggerMacroHandler(wParam, lParam)
    }

    OnRecordMessage(Timestamp) {
        if (this.MessageMap.Has(Timestamp))
            return

        this.MessageMap.Set(Timestamp, 1)
        this.MessageArr.Push(Timestamp)
        if (this.MessageArr.Length >= 125) {
            delTimestamp := this.MessageArr.RemoveAt(1)
            this.MessageMap.Delete(delTimestamp)
        }
    }

    OnGetCmd(wParam, lParam, msg, hwnd) {
        workerList := this.GetActiveWorkerList()
        ;告知一下子进程收到信息
        loop workerList.Length {
            MyWorkPool.PostMessage(WM_RECEIVE_INFO, workerList[A_Index], wParam, 0)
        }

        if (this.MessageMap.Has(wParam))    ;接收过就不用再处理了
            return

        this.OnRecordMessage(wParam)
        StringAddress := NumGet(lParam, 2 * A_PtrSize, "Ptr")  ; 检索 CopyDataStruct 的 lpData 成员.
        Cmd := StrGet(StringAddress)  ; 从结构中复制字符串.
        paramArr := StrSplit(Cmd, "_")
        switch paramArr[1] {
            case "SetVari":
                GetNameAndValueByParamArr(&NameArr, &ValueArr, paramArr)
                SetGlobalVariable(NameArr, ValueArr, false)
            case "DelVari":
                NameArr := paramArr.Clone()
                NameArr.RemoveAt(1)
                DelGlobalVariable(NameArr)
            case "Report":
                CMDReport(SubStr(Cmd, 8))
            case "RMT指令":
                ExcuteRMTCMDAction(Cmd)
            case "ItemState":
                SetTableItemState(paramArr[2], Integer(paramArr[3]), Integer(paramArr[4]))
            case "PauseState":
                SetItemPauseState(paramArr[2], Integer(paramArr[3]), Integer(paramArr[4]))
            case "MsgBox":
                paramArr := StrSplit(Cmd, "_", , 2)
                MsgBoxContent(paramArr[2])
            case "ToolTip":
                ToolTipContent(paramArr[2])
            case "MacroCount":
                MacroCount(paramArr[2])
            case "Joy":
                ViGJoySetState(paramArr[2], paramArr[3], paramArr[4])
            case "SetArray":
                SetGlobalArray(paramArr[2], GetArray(paramArr[3]))
            case "CloneArray":
                CloneGlobalArray(GetArray(paramArr[2]), paramArr[3])
            case "DeleteArray":
                DeleteGlobalArray(paramArr[2])
            case "ModifyArray":
                ModifyGlobalArray(paramArr[2], paramArr[3], paramArr[4], paramArr[5], paramArr[6])
            case "InsertArray":
                InsertGlobalArray(paramArr[2], paramArr[3], paramArr[4], paramArr[5], paramArr[6])
            case "RemoveAtArray":
                RemoveAtGlobalArray(paramArr[2], paramArr[3], paramArr[4])
        }
    }
}
