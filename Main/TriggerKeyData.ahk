#Requires AutoHotkey v2.0

class TriggerKeyData {
    __New(Key) {
        this.Key := Key
        this.OriDownArr := []  ;按下触发
        this.OriLoosenArr := []    ;松开触发
        this.OriLoosenStopArr := []    ;松止
        this.OriTogArr := []   ;开关
        this.OriHoldArr := []  ;按长按
        this.OriDblClickArr := []  ;双击触发
        this.HoldActionMap := Map()

        this.DownArr := []
        this.LoosenArr := []
        this.LoosenStopArr := []
        this.TogArr := []
        this.HoldArr := []
        this.DblClickArr := []

        this.LastKeyDownTime := 0  ;上次按下时间（用于双击检测）
        this.DblClickInterval := 300  ;双击间隔时间（毫秒）

        ; 缓存相关字段（性能优化）
        this.cacheTime := 0          ;上次更新缓存的时间戳
        this.cacheValidDuration := 200  ;缓存有效期（毫秒），窗口切换通常不会频繁发生

        this.InitState()
    }

    InitState() {
    }

    AddData(info) {
        static PropNames := ["OriDownArr", "OriLoosenArr", "OriLoosenStopArr", "OriTogArr", "OriHoldArr", "OriDblClickArr"]
        this.%PropNames[info.GetTriggerType()]%.Push(info)
    }

    UpdataArr(forceUpdate := false) {
        now := A_TickCount

        ; 缓存检查：如果缓存有效且不是强制更新，跳过重建
        if (!forceUpdate && (now - this.cacheTime) < this.cacheValidDuration)
            return

        this.DownArr := []
        this.LoosenArr := []
        this.LoosenStopArr := []
        this.TogArr := []
        this.HoldArr := []
        this.DblClickArr := []

        MyMouseInfo.UpdateInfo()
        this.UpdateArrByFront(this.OriDownArr, this.DownArr)
        this.UpdateArrByFront(this.OriLoosenArr, this.LoosenArr)
        this.UpdateArrByFront(this.OriLoosenStopArr, this.LoosenStopArr)
        this.UpdateArrByFront(this.OriTogArr, this.TogArr)
        this.UpdateArrByFront(this.OriHoldArr, this.HoldArr)
        this.UpdateArrByFront(this.OriDblClickArr, this.DblClickArr)

        ;更新双击间隔时间为所有双击宏中的最小值
        if (this.DblClickArr.Length > 0) {
            minInterval := 300
            for index, value in this.DblClickArr {
                interval := value.GetDblClickInterval()
                if (interval < minInterval)
                    minInterval := interval
            }
            this.DblClickInterval := minInterval
        }

        ; 更新缓存时间戳
        this.cacheTime := now
    }

    UpdateArrByFront(OriArr, ResArr) {
        tableItem := MySoftData.TableInfo[1]
        for index, value in OriArr {
            infoStr := value.GetFrontStr()
            realInfoStr := GetParamsWinInfoStr(infoStr)
            if (realInfoStr == "")
                continue

            if (MyMouseInfo.CheckIfMatch(infoStr, false))
                ResArr.Push(value)
        }

        ; 如果没有找到任何符合条件的窗口
        if (ResArr.Length == 0) {
            for index, value in OriArr {
                infoStr := value.GetFrontStr()
                realInfoStr := GetParamsWinInfoStr(infoStr)
                if (realInfoStr == "")
                    ResArr.Push(value)
            }
        }
    }

    OnTriggerKeyDown() {
        this.UpdataArr()

        ;双击检测逻辑
        currentTime := A_TickCount
        isDblClick := (currentTime - this.LastKeyDownTime) <= this.DblClickInterval && this.LastKeyDownTime != 0
        this.LastKeyDownTime := currentTime

        for index, value in this.DownArr {
            if (index == 1 && SubStr(value.GetTK(), 1, 1) != "~")
                LoosenModifyKey(value.GetTK())

            value.Action()
        }

        for index, value in this.LoosenStopArr {
            value.Action()
        }

        for index, value in this.TogArr {
            value.Action()
        }

        ;如果检测到双击，则触发双击宏
        if (isDblClick) {
            for index, value in this.DblClickArr {
                value.Action()
            }
        }

        this.SetHoldTimeChecker()
    }

    OnTriggerKeyUp() {
        this.UpdataArr()

        for index, value in this.LoosenArr {
            value.Action()
        }

        for index, value in this.LoosenStopArr {
            value.CancelAction()
        }

        this.DelHoldTimeChecker()
    }

    ; 强制刷新缓存（在配置重载、窗口切换等关键事件时调用）
    ForceRefreshCache() {
        this.cacheTime := 0  ; 使缓存失效
    }

    SetHoldTimeChecker() {
        for _, value in this.HoldArr {
            isWork := value.GetWorkState()
            if (isWork)
                continue
            if (this.HoldActionMap.Has(value))
                continue
            holdTime := value.GetHoldTime()
            action := this.HoldTimeAction.Bind(this, value)
            SetTimer(action, -holdTime)
            this.HoldActionMap.Set(value, action)
        }
    }

    DelHoldTimeChecker() {
        for key, value in this.HoldActionMap {
            SetTimer(value, 0)
        }
        this.HoldActionMap := Map()
    }

    HoldTimeAction(info) {
        keyCombo := LTrim(info.GetTK(), "~")
        if (this.HoldActionMap.Has(info))
            this.HoldActionMap.Delete(info)

        ; 手柄键长按检测：将友好名（如 JoyBack）转为 AHK 原始键名（如 Joy7）
        if (RegExMatch(keyCombo, "Joy") && MySoftData && IsObject(MySoftData)) {
            joyMap := MySoftData.GetJoyToAhkMap()
            if (joyMap.Has(keyCombo))
                keyCombo := joyMap[keyCombo]
        }

        if (AreKeysPressed(keyCombo))
            info.Action()
    }
}

class TriggerKeyInfo {
    __New() {
        this.macroType := 1     ; 1:item 2:fold
        this.tableIndex := 1    ;table索引
        this.itemIndex := 1     ;item索引
        this.foldIndex := 1     ;折叠框索引

        this.forbidTrigger := false
    }

    GetFrontStr() {
        tableItem := MySoftData.TableInfo[this.tableIndex]
        if (this.macroType == 1)
            return GetItemFrontInfo(tableItem, this.itemIndex)
        else if (this.macroType == 2) {
            return tableItem.FoldInfo.FrontInfoArr[this.foldIndex]
        }
        return ""
    }

    GetTK() {
        tableItem := MySoftData.TableInfo[this.tableIndex]
        if (this.macroType == 1)
            return tableItem.TKArr[this.itemIndex]
        else if (this.macroType == 2) {
            return tableItem.FoldInfo.TKArr[this.foldIndex]
        }
        return 1
    }

    GetTriggerType() {      ;触发类型   "按下", "松开", "松止", "开关", "长按"
        tableItem := MySoftData.TableInfo[this.tableIndex]
        if (this.macroType == 1)
            return tableItem.TriggerTypeArr[this.itemIndex]
        else if (this.macroType == 2) {
            return tableItem.FoldInfo.TKTypeArr[this.foldIndex]
        }
        return 1
    }

    GetHoldTime() {
        tableItem := MySoftData.TableInfo[this.tableIndex]
        if (this.macroType == 1)
            return tableItem.HoldTimeArr[this.itemIndex]
        else if (this.macroType == 2) {
            return tableItem.FoldInfo.HoldTimeArr[this.foldIndex]
        }
        return 500
    }

    GetDblClickInterval() {
        return this.GetHoldTime()
    }

    GetWorkState() {
        tableItem := MySoftData.TableInfo[this.tableIndex]
        if (this.macroType == 1) {
            return tableItem.IsWorkIndexArr[this.itemIndex]
        }
        else {
            return MainSoftData.CurMenuWheelIndex == this.foldIndex
        }
    }

    Action() {
        if (this.forbidTrigger)
            return
        tableItem := MySoftData.TableInfo[this.tableIndex]
        triggerType := this.GetTriggerType()
        if (this.macroType == 1) {
            if (triggerType == 4) {
                WorkerIndex := tableItem.IsWorkIndexArr[this.itemIndex]
                if (WorkerIndex != 0) {       ;关闭开关
                    MyStopMacro(this.tableIndex, this.itemIndex)
                    return
                }
                OnToggleTriggerMacro(this.tableIndex, this.itemIndex)
            }
            else
                TriggerMacroHandler(this.tableIndex, this.itemIndex)
        }
        else {
            if (triggerType == 3)
                this.forbidTrigger := true
            OpenMenuWheel(this.foldIndex, triggerType == 4)
        }
    }

    CancelAction() {
        tableItem := MySoftData.TableInfo[this.tableIndex]
        triggerType := this.GetTriggerType()
        if (this.macroType == 1) {
            if (triggerType == 3) {
                WorkerIndex := tableItem.IsWorkIndexArr[this.itemIndex]
                if (WorkerIndex != 0) {
                    MyStopMacro(this.tableIndex, this.itemIndex)
                    tableItem.IsWorkIndexArr[this.itemIndex] := 0
                    return
                }
                KillTableItemMacro(tableItem, this.itemIndex)
            }
        }
        else {
            if (triggerType == 3)
                this.forbidTrigger := false
            if (triggerType != 4)
                CloseMenuWheel()
        }
    }
}
