#Requires AutoHotkey v2.0

class CMDTipGui {
    __new() {
        this.Gui := ""
        this.SureBtnAction := ""
        this.Data := ""
        this.isLoadParams := false
        this.ShowCount := 0
        this.ContentCon := ""
        this._wheelCb := ""
    }

    ShowGui(CMDStr) {
        if (!this.isLoadParams) {
            this.isLoadParams := true
            this.LoadParams()
        }

        if (this.Gui == "") {
            this.AddGui()
            this.OnToggleMacroWorkState()
        }
        else {
            style := WinGetStyle(this.Gui.Hwnd)
            isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
            if (!isVisible)
                this.Gui.Show(Format("NoActivate x{} y{} w{} h{}", this.PosX, this.PosY, this.Width, this.Height))
        }

        this.AddCMD(CMDStr)

        ; 订阅滚轮热键（仅首次或窗口重建时）
        if (!this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }
    }

    LoadParams() {
        this.PosX := MySoftData.CMDPosX
        this.PosY := MySoftData.CMDPosY
        this.Width := MySoftData.CMDWidth
        this.Height := MySoftData.CMDHeight
        this.BGColor := MySoftData.CMDBGColor
        this.RunBGColor := MySoftData.CMDRunBGColor
        this.Transparency := (Integer)(MySoftData.CMDTransparency * 2.55)
        this.FontSize := MySoftData.CMDFontSize
        this.FontColor := MySoftData.CMDFontColor
    }

    AddGui() {
        MyGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        this.Gui := MyGui
        MyGui.BackColor := this.BGColor
        MyGui.SetFont(Format("S{} W550 Q2 C{}", this.FontSize, this.FontColor), MySoftData.FontType)
        MyGui.Opt("+E0x20")  ; 点击穿透
        WinSetTransparent(this.Transparency, MyGui)  ; 设置透明度

        ; 添加文本控件（宽度和高度匹配窗口，自动换行）
        this.ContentCon := MyGui.Add("Edit", Format("x0 y0 w{} h{}", this.Width, this.Height), "")
        this.ContentCon.Opt("Background" this.BGColor)

        ; 显示窗口（固定宽高）
        MyGui.Show(Format("NoActivate  x{} y{} w{} h{}", this.PosX, this.PosY, this.Width, this.Height))
    }

    AddCMD(CMDStr) {
        this.ShowCount++
        if (this.ShowCount >= 100) {
            this.ShowCount--
            Pos := InStr(this.ContentCon.Value, "`n")
            this.ContentCon.Value := SubStr(this.ContentCon.Value, Pos + 1)
        }

        if (this.ContentCon.Value == "")
            this.ContentCon.Value := CMDStr
        else
            this.ContentCon.Value .= Format("`n{}", CMDStr)

        SendMessage(0xB6, 0, 10000, this.ContentCon)
    }

    Hide() {
        if (this.Gui == "")
            return

        this.ShowCount := 0
        this.ContentCon.Value := ""
        this.Gui.Hide()

        ; 取消订阅滚轮热键
        if (this._wheelCb) {
            WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
    }

    _OnWheel(key, *) {
        this.OnScrollWheel(key)
    }

    OnToggleMacroWorkState() {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        ColorStr := MySoftData.IsMacroWorking ? this.RunBGColor : this.BGColor
        this.Gui.BackColor := ColorStr
        this.ContentCon.Opt("Background" ColorStr)
        this.ContentCon.Redraw()
    }

    OnScrollWheel(key) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        ; 鼠标在窗口上才滑动
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        isOnWin := mouseX >= this.PosX && mouseY >= this.PosY
        isOnWin := isOnWin && mouseX <= this.PosX + this.Width && mouseY <= this.PosY + this.Height
        if (!isOnWin)
            return

        isDown := InStr(key, "Down", "Off") ? true : false
        ChangeValue := isDown ? 2 : -2
        SendMessage(0xB6, 0, ChangeValue, this.ContentCon) ; EM_LINESCROLL = 0xB6
    }
}
