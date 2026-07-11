#Requires AutoHotkey v2.0

class VerticalSlider {
    __new() {
        this.tableItem := ""
        this.BaseOffsetY := 45      ;基础偏移值
        this.AeraHeight := 500       ;区域高度
        this.ContentHeight := ""    ;内容高度
        this.BarHeight := 550       ;滑动棒的高度
        this.BarMaxPosY := ""       ;滑动棒最大移动位置y
        this.CurBarOffsetPosY := ""       ;当前棒位置
        this.ShowSlider := false

        this.IsDragging := false
        this.DragOffsetPosY := 0      ;拖拽偏移位置Y
        this.DragAction := this.DragHandler.Bind(this)
        this._wheelCb := ""
    }

    ;内凹像素， 左边偏移（text左边点击不灵敏）
    SetStyleParams(Hindent, Vindent) {
        this.Hindent := Hindent
        this.Vindent := Vindent
        this.AreaCon.GetPos(&Ax, &Ay, &Aw, &Ah)
        this.AeraHeight := Ah - 2 * this.Vindent
    }

    SetSliderCon(AreaCon, BarCon) {
        this.AreaCon := AreaCon
        this.BarCon := BarCon
        this.BarCon.OnEvent("Click", this.OnDragBar.Bind(this))
        ; this.BindScrollHotkey("~WheelUp", this.OnScrollWheel.Bind(this))
        ; this.BindScrollHotkey("~WheelDown", this.OnScrollWheel.Bind(this))
        ; this.BindScrollHotkey("~+WheelUp", this.OnScrollWheel.Bind(this))
        ; this.BindScrollHotkey("~+WheelDown", this.OnScrollWheel.Bind(this))
    }

    SwitchTab(tableItem) {
        this.tableItem := tableItem
        this.UpdateContentHeight()
        this.BarHeight := ((this.AeraHeight + 2 * this.Vindent) / this.ContentHeight) * this.AeraHeight
        this.BarMaxPosY := this.AeraHeight - this.BarHeight
        this.CurBarOffsetPosY := this.tableItem.SliderValue * this.BarMaxPosY
        this.ShowSlider := this.ContentHeight > this.AeraHeight
        this.AreaCon.Visible := this.ShowSlider
        this.BarCon.Visible := this.ShowSlider

        ; 滚轮热键：仅在滑块可见时订阅
        if (this.ShowSlider && !this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }
        else if (!this.ShowSlider && this._wheelCb) {
            WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }

        if (!this.ShowSlider)
            return

        this.AreaCon.GetPos(&Ax, &Ay, &Aw, &Ah)
        this.BarCon.GetPos(&Bx, &By, &Bw, &Bh)
        PosY := Ay + this.CurBarOffsetPosY + this.Vindent
        this.BarCon.Move(Ax + this.Hindent, PosY, Aw - this.Hindent * 2, this.BarHeight)
    }

    RefreshTab() {
        this.SwitchTab(this.tableItem)
        ShowSlider := this.ContentHeight > this.AeraHeight
        OffSetPosY := (this.ContentHeight - this.AeraHeight - 2 * this.Vindent) * this.tableItem.SliderValue
        this.tableItem.OffSetPosY := ShowSlider ? OffSetPosY : 0
        UpdateItemConPos(this.tableItem, true)
    }

    OnValueChange(isDown) {
        UpdateItemConPos(this.tableItem, isDown)
    }

    BindScrollHotkey(key, action) {
        HotIfWinActive("RMTv")
        Hotkey(key, action)
        HotIfWinActive
    }

    _OnWheel(key) {
        this.OnScrollWheel(key)
    }

    OnScrollWheel(key) {
        if (!this.ShowSlider)
            return

        ; 主窗口不可见时不处理（避免对隐藏窗口操作导致窗口重新显示）
        if (MainSoftData.MyGui != "" && !WinExist("ahk_id " MainSoftData.MyGui.Hwnd))
            return

        ; 主窗口不激活时不处理（避免下拉框滚动时激活主窗口导致任务栏图标闪烁）
        if (MainSoftData.MyGui != "" && DllCall("GetForegroundWindow", "Ptr") != MainSoftData.MyGui.Hwnd)
            return

        isDown := InStr(key, "Down", "Off") ? true : false
        value := 80
        if ((value / this.BarMaxPosY) * (this.ContentHeight - this.AeraHeight - 2 * this.Vindent) >= 420) {
            value := (420 / (this.ContentHeight - this.AeraHeight - 2 * this.Vindent)) * this.BarMaxPosY
        }
        scrollValue := isDown ? value : -value
        this.AreaCon.GetPos(&Ax, &Ay, &Aw, &Ah)
        this.BarCon.GetPos(&Bx, &By, &Bw, &Bh)
        NewY := By + scrollValue
        NewY := Max(NewY, Ay + this.Vindent)
        NewY := Min(NewY, Ay + this.Vindent + this.BarMaxPosY)
        if (Integer(By) == Ceil(NewY) || Integer(By) == Floor(NewY))
            return
        this.BarCon.Move(Bx, NewY)
        this.CurBarOffsetPosY := NewY - Ay - this.Vindent
        this.tableItem.SliderValue := this.CurBarOffsetPosY / this.BarMaxPosY
        this.tableItem.OffSetPosY := (this.ContentHeight - this.AeraHeight - 2 * this.Vindent) * this.tableItem.SliderValue
        this.OnValueChange(isDown)
    }

    OnDragBar(*) {
        this.IsDragging := true
        MouseGetPos(&StartX, &StartY)
        this.BarCon.GetPos(&Bx, &By, &Bw, &Bh)
        this.DragOffsetPosY := StartY - By
        SetTimer(this.DragAction, 16)
    }

    DragHandler() {
        if (!GetKeyState("LButton") || !this.IsDragging) {
            this.IsDragging := false
            SetTimer(this.DragAction, 0)
            return
        }

        MouseGetPos(&CurrentX, &CurrentY)
        this.AreaCon.GetPos(&Ax, &Ay, &Aw, &Ah)
        this.BarCon.GetPos(&Bx, &By, &Bw, &Bh)
        NewY := CurrentY - this.DragOffsetPosY
        NewY := Max(NewY, Ay + this.Vindent)
        NewY := Min(NewY, Ay + this.Vindent + this.BarMaxPosY)
        isDown := NewY > By ? true : false
        if (Integer(By) == Ceil(NewY) || Integer(By) == Floor(NewY))
            return
        this.BarCon.Move(Bx, NewY)
        this.CurBarOffsetPosY := NewY - Ay - this.Vindent
        this.tableItem.SliderValue := this.CurBarOffsetPosY / this.BarMaxPosY
        this.tableItem.OffSetPosY := (this.ContentHeight - this.AeraHeight - 2 * this.Vindent) * this.tableItem.SliderValue
        this.OnValueChange(isDown)
    }

    UpdateContentHeight() {
        height := this.tableItem.UnderPosY - this.BaseOffsetY + 20
        for index, value in this.tableItem.FoldOffsetArr {
            height += value
        }
        this.ContentHeight := height
    }
}
