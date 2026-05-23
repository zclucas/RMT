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

        this.InitState()
    }

    InitState() {
        this.IsSoftHotKey := false
        for index, value in MySoftData.SoftHotKeyArr {
            key := LTrim(value, "~")
            key := StrLower(key)
            if (this.Key == key) {
                this.IsSoftHotKey := true
                break
            }
        }
    }

    IsOnlySoftHotkey() {
        if (this.OriDownArr.Length >= 1)
            return false
        if (this.OriLoosenArr.Length >= 1)
            return false
        if (this.OriLoosenStopArr.Length >= 1)
            return false
        if (this.OriTogArr.Length >= 1)
            return false
        if (this.OriHoldArr.Length >= 1)
            return false
        if (this.OriDblClickArr.Length >= 1)
            return false

        return true
    }

    AddData(info) {
        static PropNames := ["OriDownArr", "OriLoosenArr", "OriLoosenStopArr", "OriTogArr", "OriHoldArr", "OriDblClickArr"]
        this.%PropNames[info.GetTriggerType()]%.Push(info)
    }

    UpdataArr() {
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
        this.HandleSoftHotKeyDown()

        if (WindowHotkeyManager.IsManaged(this.Key) && WindowHotkeyManager.IsAnyWindowActive(this.Key))
            return

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
        this.HandleSoftHotKeyUp()

        if (WindowHotkeyManager.IsManaged(this.Key) && WindowHotkeyManager.IsAnyWindowActive(this.Key))
            return

        for index, value in this.LoosenArr {
            value.Action()
        }

        for index, value in this.LoosenStopArr {
            value.CancelAction()
        }

        this.DelHoldTimeChecker()
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

        if (AreKeysPressed(keyCombo))
            info.Action()
    }

    HandleSoftHotKeyDown() {
        if (!this.IsSoftHotKey)
            return

        if (this.Key == "wheelup" || this.Key == "wheeldown") {
            if (MyMouseInfo.CheckIfMatch("RMTv⎖⎖")) {
                MySlider.OnScrollWheel(this.Key)
            }

            if (MyMouseInfo.CheckIfMatch("RMT-FreePaste⎖⎖")) {
                MyFreePasteGui.OnScrollWheel(this.Key)
            }

            MyCMDTipGui.OnScrollWheel(this.Key)
        }

        isArrowKey1 := this.Key == "left" || this.Key == "right"
        isArrowKey2 := this.Key == "up" || this.Key == "down"
        isArrowKey := isArrowKey1 || isArrowKey2
        if (isArrowKey) {
            MyTargetGui.OnArrowKeyDown(this.Key)
        }

        if (this.Key == "lbutton") {
            if (MySoftData.SelectAreaAction != "") {
                SelectArea()
            }

            if (MySoftData.GetAreaAction != "") {
                OnGetSelectAreaDown(this.Key)
            }
        }

        if (WindowHotkeyManager.IsManaged(this.Key) && WindowHotkeyManager.HandleKey(this.Key, true))
            return
    }

    HandleSoftHotKeyUp() {
        if (!this.IsSoftHotKey)
            return

        if (this.Key == "lbutton") {
            if (MyMouseInfo.CheckIfMatch("RMT-Target⎖⎖")) {
                MyTargetGui.OnLButtonUp(this.Key)
            }

            if (MySoftData.GetAreaAction != "") {
                OnGetSelectAreaUp(this.Key)
            }
        }

        if (this.Key == "enter") {
            MyColorPanel.OnEnterUp(this.Key)
        }

        if (WindowHotkeyManager.IsManaged(this.Key) && WindowHotkeyManager.HandleKey(this.Key, false))
            return
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
            return MySoftData.CurMenuWheelIndex == this.foldIndex
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
                    MySubMacroStopAction(this.tableIndex, this.itemIndex)
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
                    MyWorkPool.BroadcastStop(this.tableIndex, this.itemIndex)
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
