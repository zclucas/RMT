#Requires AutoHotkey v2.0

class MenuWheelGui {
    static Hotkeys := ["1", "2", "3", "4", "5", "6", "7", "8"]

    __new() {
        this.Gui := ""
        this.MenuIndex := 1
        this.BtnConArr := []
        this.FocusCon := ""
        this.CurCenterPosX := 500
        this.CurCenterPosY := 500

        this.BtnRegions := Map() ; ✅按钮区域表
        this.DrawAction := this.DrawLine.Bind(this)

        this.DPIScale := A_ScreenDPI / 96

        WindowHotkeyManager.Register(this, MenuWheelGui.Hotkeys, this.OnSoftKey.Bind(this))
    }

    ; DPI缩放适配的坐标转换
    Scale(value) {
        return Round(value * this.DPIScale)
    }

    ShowGui(MenuIndex) {
        PreviousActiveWindow := WinExist("A")
        if (this.Gui != "") {
            this.Gui.Show(this.GetGuiShowPos() " NA")
        }
        else {
            this.AddGui()
        }
        this.Init(MenuIndex)
        try {
            WinActivate(PreviousActiveWindow)
        }
    }

    Init(MenuIndex) {
        this.MenuIndex := MenuIndex
        tableItem := MySoftData.TableInfo[3]
        loop 8 {
            remark := tableItem.RemarkArr[(MenuIndex - 1) * 8 + A_Index]
            btnName := remark != "" ? remark : "菜单配置" A_Index
            this.BtnConArr[A_Index].Text := btnName
        }
        if (!MySoftData.FixedMenuWheel)
            this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui("-Caption +AlwaysOnTop +ToolWindow", GetLang("菜单轮"))
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        MyGui.BackColor := "EEAA99"
        WinSetTransColor("EEAA99", MyGui)
        this.Gui := MyGui
        PosX := 0
        PosY := 0
        this.FocusCon := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), "")

        PosX := 130  ; 调整
        PosY := 10   ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置1"))
        con.OnEvent("Click", (*) => this.OnBtnClick(1))
        this.BtnConArr.Push(con)
        this.BtnRegions[1] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 225  ; 调整
        PosY := 55   ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置2"))
        con.OnEvent("Click", (*) => this.OnBtnClick(2))
        this.BtnConArr.Push(con)
        this.BtnRegions[2] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 260  ; 调整
        PosY := 110  ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置3"))
        con.OnEvent("Click", (*) => this.OnBtnClick(3))
        this.BtnConArr.Push(con)
        this.BtnRegions[3] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 225  ; 调整
        PosY := 165  ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置4"))
        con.OnEvent("Click", (*) => this.OnBtnClick(4))
        this.BtnConArr.Push(con)
        this.BtnRegions[4] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 130  ; 调整
        PosY := 210  ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置5"))
        con.OnEvent("Click", (*) => this.OnBtnClick(5))
        this.BtnConArr.Push(con)
        this.BtnRegions[5] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 35   ; 调整
        PosY := 165  ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置6"))
        con.OnEvent("Click", (*) => this.OnBtnClick(6))
        this.BtnConArr.Push(con)
        this.BtnRegions[6] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 0    ; 调整
        PosY := 110  ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置7"))
        con.OnEvent("Click", (*) => this.OnBtnClick(7))
        this.BtnConArr.Push(con)
        this.BtnRegions[7] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        PosX := 35   ; 调整
        PosY := 55   ; 调整
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("菜单配置8"))
        con.OnEvent("Click", (*) => this.OnBtnClick(8))
        this.BtnConArr.Push(con)
        this.BtnRegions[8] := { X: PosX, Y: PosY, W: 80, H: 30 } ; ✅记录区域

        MyGui.OnEvent("Close", (*) => this.ToggleFunc(false))
        MyGui.Show(Format("{} w{} h{} NA", this.GetGuiShowPos(), 340, 260))
    }

    GetGuiShowPos() {
        if (MySoftData.FixedMenuWheel) {
            this.CurCenterPosX := A_ScreenWidth * 0.5
            this.CurCenterPosY := A_ScreenHeight * 0.70
        }
        else {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.CurCenterPosX := mouseX
            this.CurCenterPosY := mouseY
        }
        offsetX := this.Scale(170)
        offsetY := this.Scale(130)
        return Format("x{} y{}", this.CurCenterPosX - offsetX, this.CurCenterPosY - offsetY)
    }

    OnSoftKey(key, isDown) {
        if (!isDown)
            return

        numberArr := ["1", "2", "3", "4", "5", "6", "7", "8"]
        loop numberArr.Length {
            if (key == numberArr[A_Index]) {
                index := Integer(key)
                if (!IsObject(this.Gui))
                    return

                style := WinGetStyle(this.Gui.Hwnd)
                isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                if (isVisible)
                    this.OnBtnClick(index)
            }
        }
    }

    OnBtnClick(index) {
        MySoftData.CurMenuWheelIndex := -1
        this.FocusCon.Focus()
        this.ToggleFunc(false)
        this.Gui.Hide()

        macroIndex := (this.MenuIndex - 1) * 8 + index
        TriggerMacroHandler(3, macroIndex)
        BindSoftHotKey()
        BindMenuHotKey()
        BindTabHotKey()
    }

    ToggleFunc(state) {
        if (state) {
            LineOverlay.Init()
            SetTimer(this.DrawAction, 15) ; 60fps
            this.RegisterGlobalHotkeys()
        } else {
            SetTimer(this.DrawAction, 0)
            LineOverlay.BeginFrame()
            LineOverlay.EndFrame()
            this.UnregisterGlobalHotkeys()
        }
    }

    RegisterGlobalHotkeys() {
        for key in MenuWheelGui.Hotkeys {
            capturedKey := key
            Hotkey("$*" capturedKey, ((*) => this.OnSoftKey(capturedKey, true)).Bind(this), "On")
        }
    }

    UnregisterGlobalHotkeys() {
        for key in MenuWheelGui.Hotkeys {
            capturedKey := key
            Hotkey("$*" capturedKey, ((*) => this.OnSoftKey(capturedKey, true)).Bind(this), "Off")
        }
    }

    DrawLine() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mx, &my

        LineOverlay.BeginFrame()
        LineOverlay.DrawLine(this.CurCenterPosX, this.CurCenterPosY, mx, my)
        LineOverlay.EndFrame()

        isHover := this.CheckMouseHover(mx, my) ; ✅检测悬停
        if (isHover)
            return

        this.CheckDistanceAndAngle(mx, my)
    }

    CheckMouseHover(mx, my) {
        for index, rect in this.BtnRegions {
            ; 计算屏幕坐标时考虑DPI缩放
            ScreenRectX := this.CurCenterPosX - this.Scale(170) + this.Scale(rect.X)
            ScreenRectY := this.CurCenterPosY - this.Scale(130) + this.Scale(rect.Y)

            if (mx >= ScreenRectX && mx <= ScreenRectX + this.Scale(rect.W)
            && my >= ScreenRectY && my <= ScreenRectY + this.Scale(rect.H)) {
                this.OnBtnClick(index)
                return true
            }
        }
    }

    CheckDistanceAndAngle(mx, my) {
        ; 计算相对坐标和距离
        deltaX := mx - this.CurCenterPosX
        deltaY := my - this.CurCenterPosY
        distance := Sqrt(deltaX * deltaX + deltaY * deltaY)

        ; 距离检查
        if (distance < this.Scale(160)) {
            return
        }

        ; 超简化的方向判断（基于坐标比值）
        ratio := Abs(deltaY / (deltaX != 0 ? deltaX : 0.001))  ; 避免除零

        if (Abs(deltaX) > Abs(deltaY)) {
            ; 水平方向为主
            if (deltaX > 0) {
                sector := (ratio < 0.414) ? 3 : (deltaY > 0 ? 4 : 2)  ; 右、右下、右上
            } else {
                sector := (ratio < 0.414) ? 7 : (deltaY > 0 ? 6 : 8)  ; 左、左下、左上
            }
        } else {
            ; 垂直方向为主
            if (deltaY > 0) {
                sector := (ratio > 2.414) ? 5 : (deltaX > 0 ? 4 : 6)  ; 下、右下、左下
            } else {
                sector := (ratio > 2.414) ? 1 : (deltaX > 0 ? 2 : 8)  ; 上、右上、左上
            }
        }
        ; 触发对应的事件
        this.OnBtnClick(sector)
    }
}
