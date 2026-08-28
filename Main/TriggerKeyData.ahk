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
        this.NeedReleaseBeforeRetrigger := false  ; 连续触发关闭时：需先松开才能再次触发

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
        ; 仅用 MyMouseInfo 匹配前台窗口，不依赖具体表；保留 tableItem 占位避免空引用
        tableItem := GetTableBySymbol("Normal")
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

        ; 连续触发关闭时：按下/开关/长按需先松开触发键才能再次触发
        blockRetrigger := !MainSoftData.ContinuousTrigger && this.NeedReleaseBeforeRetrigger

        for index, value in this.DownArr {
            if (blockRetrigger)
                continue
            if (index == 1 && MainSoftData.AutoLoosenModifier && SubStr(value.GetTK(), 1, 1) != "~")
                LoosenModifyKey(value.GetTK())
            value.Action()
        }

        for index, value in this.LoosenStopArr {
            value.Action()
        }

        for index, value in this.TogArr {
            if (blockRetrigger)
                continue
            if (index == 1 && MainSoftData.AutoLoosenModifier && SubStr(value.GetTK(), 1, 1) != "~")
                LoosenModifyKey(value.GetTK())
            value.Action()
        }

        ;如果检测到双击，则触发双击宏
        if (isDblClick) {
            for index, value in this.DblClickArr {
                value.Action()
            }
        }

        if (!blockRetrigger)
            this.SetHoldTimeChecker()

        if (!MainSoftData.ContinuousTrigger
            && (this.DownArr.Length > 0 || this.TogArr.Length > 0 || this.HoldArr.Length > 0))
            this.NeedReleaseBeforeRetrigger := true
    }

    OnTriggerKeyUp() {
        this.UpdataArr()
        this.NeedReleaseBeforeRetrigger := false

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

        if (AreKeysPressed(keyCombo)) {
            if (MainSoftData.AutoLoosenModifier && SubStr(info.GetTK(), 1, 1) != "~")
                LoosenModifyKey(info.GetTK())
            info.Action()
            if (!MainSoftData.ContinuousTrigger)
                this.NeedReleaseBeforeRetrigger := true
        }
    }
}

class TriggerKeyInfo {
    __New() {
        this.macroType := 1     ; 1:按键/字串等 item  2:菜单宏 fold  3:界面宏 fold
        this.tableID := ""      ;表唯一 ID
        this.itemID := ""       ;条目唯一 ID（macroType==1）
        this.foldID := ""       ;折叠框唯一 ID（macroType==2/3）

        this.forbidTrigger := false
    }

    ; 菜单宏 / 界面宏均为 Fold 级触发键
    IsFoldMacro() {
        return this.macroType == 2 || this.macroType == 3
    }

    ; 解析目标表对象（无则 ""）
    GetTable() {
        return GetTableByID(this.tableID)
    }

    ; 解析条目对象（macroType==1；无则 ""）
    GetItem() {
        if (this.macroType != 1)
            return ""
        t := GetTableByID(this.tableID)
        return t ? t.GetItem(this.itemID) : ""
    }

    ; 解析折叠框对象（macroType==2/3；无则 ""）
    GetFold() {
        if (!this.IsFoldMacro())
            return ""
        t := GetTableByID(this.tableID)
        return t ? t.GetFold(this.foldID) : ""
    }

    GetFrontStr() {
        if (this.macroType == 1) {
            t := GetTableByID(this.tableID)
            item := this.GetItem()
            if (!t || !item)
                return ""
            return GetItemFrontInfo(t, GetItemIndexInTable(t, item.ID))
        }
        fold := this.GetFold()
        return fold ? fold.FrontInfo : ""
    }

    GetTK() {
        if (this.macroType == 1) {
            item := this.GetItem()
            return item ? item.TK : ""
        }
        fold := this.GetFold()
        return fold ? fold.TK : ""
    }

    GetTriggerType() {      ;触发类型   "按下", "松开", "松止", "开关", "长按"
        if (this.macroType == 1) {
            item := this.GetItem()
            return item ? item.TriggerType : 1
        }
        if (this.macroType == 2) {
            fold := this.GetFold()
            return fold ? fold.TKType : 1
        }
        ; 界面宏固定按「按下」切换面板（与 BindUIPanelHotKey 约定一致）
        if (this.macroType == 3)
            return 1
        return 1
    }

    GetHoldTime() {
        if (this.macroType == 1) {
            item := this.GetItem()
            return item ? item.HoldTime : 500
        }
        if (this.macroType == 2) {
            fold := this.GetFold()
            return fold ? fold.HoldTime : 500
        }
        return 500
    }

    GetDblClickInterval() {
        return this.GetHoldTime()
    }

    GetWorkState() {
        if (this.macroType == 1) {
            item := this.GetItem()
            return item ? item.IsWorkIndex : false
        }
        if (this.macroType == 2) {
            t := GetTableByID(this.tableID)
            if (t) {
                for f, fold in t.Folds {
                    if (fold.ID == this.foldID)
                        return MainSoftData.CurMenuWheelIndex == f
                }
            }
            return false
        }
        if (this.macroType == 3) {
            ; 有任意该模块面板可见则视为工作中（长按等逻辑用）
            if (!IsSet(MyUIMacroGui) || !IsObject(MyUIMacroGui))
                return false
            for key, panelInfo in MyUIMacroGui.PanelMap {
                if (panelInfo.foldID == this.foldID && panelInfo.visible)
                    return true
            }
            return false
        }
        return false
    }

    Action() {
        if (this.forbidTrigger)
            return
        triggerType := this.GetTriggerType()
        if (this.macroType == 1) {
            t := GetTableByID(this.tableID)
            item := this.GetItem()
            if (!t || !item)
                return
            itemIndex := GetItemIndexInTable(t, item.ID)
            if (triggerType == 4) {
                ; 占用标记或 usePool 中仍有该宏的 Worker，都视为运行中 → 停止（避免脏标记导致误启动）
                isRunning := item.IsWorkIndex
                if (!isRunning && WorkPoolEnabled() && MyWorkPool.HasItemWork(t.ID, item.ID))
                    isRunning := true
                if (isRunning) {
                    MyStopMacro(t, itemIndex)
                    return
                }
                OnToggleTriggerMacro(t, itemIndex)
            }
            else
                TriggerMacroHandler(t, itemIndex)
        }
        else if (this.macroType == 2) {
            t := GetTableByID(this.tableID)
            if (!t)
                return
            foldIndex := GetFoldIndexInTable(t, this.foldID)
            if (triggerType == 3)
                this.forbidTrigger := true
            OpenMenuWheel(foldIndex, triggerType == 4)
        }
        else if (this.macroType == 3) {
            ; 界面宏：切换悬浮面板，绝不能误开菜单轮盘
            if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
                MyUIMacroGui.TogglePanel(this.foldID)
        }
    }

    CancelAction() {
        triggerType := this.GetTriggerType()
        if (this.macroType == 1) {
            if (triggerType == 3) {
                t := GetTableByID(this.tableID)
                item := this.GetItem()
                if (!t || !item)
                    return
                itemIndex := GetItemIndexInTable(t, item.ID)
                WorkerIndex := item.IsWorkIndex
                if (WorkerIndex != 0) {
                    MyStopMacro(t, itemIndex)
                    item.IsWorkIndex := 0
                    return
                }
                KillTableItemMacro(t, itemIndex)
            }
        }
        else if (this.macroType == 2) {
            if (triggerType == 3)
                this.forbidTrigger := false
            if (triggerType != 4)
                CloseMenuWheel()
        }
        ; macroType 3：按下切换，松开无需额外处理
    }
}
