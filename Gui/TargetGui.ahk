#Requires AutoHotkey v2.0

class TargetGui {
    __new() {
        this.Gui := ""

        this.GuiWidth := 64
        this.GuiHeight := 64

        this.SureAction := ""
        this._hkIds := []
        this._lbuttonCb := ""
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        MyColorPanel.SureAction := this.SureAction
        MyColorPanel.ShowGui()
        ; 注册方向键热键（目标窗口活动期间有效）
        if (this._hkIds.Length == 0) {
            this._hkIds := WinHotkey.Register(["Left", "Right", "Up", "Down"], ObjBindMethod(this, "_OnHotkey"))
        }
        ; 订阅 LButton 热键（目标窗口活动期间有效）
        if (!this._lbuttonCb) {
            this._lbuttonCb := ObjBindMethod(this, "_OnLButton")
            WinHotkey.SubscribeMouse("LButton", this._lbuttonCb)
        }
    }

    HideGui() {
        if (this._hkIds.Length > 0) {
            WinHotkey.UnregisterAll(this._hkIds)
            this._hkIds := []
        }
        if (this._lbuttonCb) {
            WinHotkey.UnsubscribeMouse("LButton", this._lbuttonCb)
            this._lbuttonCb := ""
        }
    }

    AddGui() {
        this.Gui := Gui("+AlwaysOnTop +ToolWindow -Caption -Resize -DPIScale")
        this.Gui.Title := "RMT-Target"
        this.Gui.SetFont("S13 W550 Q2", MySoftData.FontType)
        this.Gui.MarginX := 0
        this.Gui.MarginY := 0
        this.Gui.BackColor := "EEAA99" ; 这个颜色必须设置，但具体是什么颜色不重要
        WinSetTransColor("EEAA99", this.Gui)
        this.Gui.Add("Pic", Format("w{} h{}", 64, 64), "Images\Soft\Target.png")

        this.OverlayCon := this.Gui.Add("Text", "x0 y0 w" this.GuiWidth " h" this.GuiHeight " BackgroundTrans")
        this.OverlayCon.OnEvent("Click", this.GuiDrag.Bind(this))
        this.OverlayCon.OnEvent("DoubleClick", this.GuiDoubleClick.Bind(this))
        this.Gui.Show(Format("w{} h{}", this.GuiWidth, this.GuiHeight))
    }

    ; 拖动函数
    GuiDrag(*) {
        PostMessage(0xA1, 2, , , this.Gui)
        MyColorPanel.RefreshCoord()
    }

    OnLButtonUp(*) {
        this._OnLButton()
    }

    _OnLButton(*) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        MyColorPanel.RefreshCoord()
        MyColorPanel.RefreshMapImage()
    }

    _OnHotkey(key) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)
        if (!isVisible)
            return

        this.Gui.GetPos(&x, &y, &w, &h)
        if (key == "Left")
            x -= 1
        else if (key == "Right")
            x += 1
        else if (key == "Up")
            y -= 1
        else if (key == "Down")
            y += 1
        else
            return

        this.Gui.Move(x, y)
        MyColorPanel.RefreshCoord()
        MyColorPanel.RefreshMapImage()
    }

    ;双击确定关闭
    GuiDoubleClick(*) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        MyColorPanel.GuiDoubleClick()
    }

    OnArrowKeyDown(key) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        this.Gui.GetPos(&x, &y, &w, &h)
        if (key == "left")
            x -= 1
        if (key == "right")
            x += 1
        if (key == "up")
            y -= 1
        if (key == "down")
            y += 1

        this.Gui.Move(x, y)
        MyColorPanel.RefreshCoord()
        MyColorPanel.RefreshMapImage()
    }
}
