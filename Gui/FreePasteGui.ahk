class FreePasteGui {
    __new() {
        this.GuiMap := Map()
        this._wheelCb := ""
    }

    ShowGui() {
        this.AddGui()
        ; 订阅滚轮热键（粘贴窗口活动期间有效）
        if (!this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }
    }

    DestroyGui(gui) {
        hwnd := gui.Hwnd
        gui.Destroy()
        if (this.GuiMap.Has(hwnd))
            this.GuiMap.Delete(hwnd)
        ; 所有窗口都销毁后取消订阅滚轮热键
        if (this.GuiMap.Count == 0 && this._wheelCb) {
            WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
    }

    AddGui() {
        ; 检测剪贴板格式
        isImage := DllCall("IsClipboardFormatAvailable", "UInt", 8)  ; CF_DIB = 8
        isText := IsClipboardText()

        if (isImage || isText) {
            ; 创建GUI
            this.curGui := Gui("+AlwaysOnTop +ToolWindow -Caption -Resize -DPIScale")
            this.curGui.Title := "RMT-FreePaste"
            this.curGui.MarginX := !isImage && isText ? 10 : 0
            this.curGui.MarginY := !isImage && isText ? 10 : 0
            this.curGui.BackColor := "FFFFFF"  ; 默认背景色
            this.curGui.SetFont("S13 W550 Q2", MySoftData.FontType)

            guiData := FreePasteData(this.curGui)
            this.GuiMap.Set(this.curGui.Hwnd, guiData)
        }

        if (isImage) {
            CurrentDateTime := FormatTime(, "MM月dd日HH-mm-ss")
            filePath := A_WorkingDir "\Images\FreePaste\" CurrentDateTime ".png"
            SaveClipToBitmap(filePath)
            this.pic := this.curGui.Add("Picture", "", filePath)
            ; 获取实际图片尺寸
            this.pic.GetPos(, , &width, &height)

            guiData.InitImage(this.pic, width, height)
        }
        else if (isText) {
            clipText := A_Clipboard
            ; 创建文本控件时不要指定固定大小
            this.textCtrl := this.curGui.Add("Text", "", clipText)
            ; 获取实际文本尺寸
            this.textCtrl.GetPos(, , &textW, &textH)
            width := textW + this.curGui.MarginX * 2
            height := textH + this.curGui.MarginY * 2

            this.curGui.SetFont("S5")
            minCon := this.curGui.Add("Text", "", clipText)
            minCon.GetPos(, , &minW, &minH)
            minCon.Visible := false

            this.curGui.SetFont("S20")
            maxCon := this.curGui.Add("Text", "", clipText)
            maxCon.GetPos(, , &maxW, &maxH)
            maxCon.Visible := false

            guiData.InitText(this.textCtrl, minW, minH, maxW, maxH)
        }

        if (isImage || isText) {
            ; 添加透明覆盖控件（覆盖整个窗口）
            this.overlay := this.curGui.Add("Text", "x0 y0 w" width " h" height " BackgroundTrans +E0x200")
            ; 将事件绑定到覆盖控件
            this.overlay.OnEvent("Click", this.GuiDrag.Bind(this, this.curGui))
            this.overlay.OnEvent("DoubleClick", this.DoubleClick.Bind(this, this.curGui))
            guiData.InitOverlay(this.overlay)
            this.curGui.Show("w" width " h" height)
        }
    }

    DoubleClick(gui, *) {
        this.DestroyGui(gui)
        gui := ""
    }

    ; 拖动函数
    GuiDrag(gui, *) {
        PostMessage(0xA1, 2, , , gui)
    }

    _OnWheel(key) {
        this.OnScrollWheel(key)
    }

    OnScrollWheel(key) {
        MouseGetPos(&x, &y, &windId)
        if (!this.GuiMap.Has(windId))
            return

        isDown := InStr(key, "Down", "Off") ? true : false
        valueSymbol := isDown ? -1 : 1
        valueScale := isDown ? 0.85 : 1.15
        guiData := this.GuiMap[windId]
        if (guiData.Type == 1) {
            guiData.FontSize += valueSymbol
            guiData.FontSize := Min(guiData.FontSize, 20)
            guiData.FontSize := Max(guiData.FontSize, 5)
            adjustWid := guiData.FontSize == 5 || guiData.FontSize == 20 ? 0 : 30
            adjustHid := guiData.FontSize == 5 || guiData.FontSize == 20 ? 0 : 15
            width := guiData.TextMinWid + ((guiData.TextMaxWid - guiData.TextMinWid) / 15) * (guiData.FontSize - 5) +
            adjustWid
            height := guiData.TextMinHei + ((guiData.TextMaxHei - guiData.TextMinHei) / 15) * (guiData.FontSize - 5) + adjustHid

            guiData.TextCon.SetFont(Format("S{}", guiData.FontSize))
            guiData.TextCon.Redraw()
            guiData.TextCon.Move(, , width, height)
            guiData.OverlayCon.Move(, , width, height)
            guiData.Gui.Show("w" width " h" height)
        }

        if (guiData.Type == 2) {
            guiData.ImageWidth *= valueScale
            guiData.ImageHeight *= valueScale

            guiData.ImageCon.Move(, , guiData.ImageWidth, guiData.ImageHeight)
            guiData.OverlayCon.Move(, , guiData.ImageWidth, guiData.ImageHeight)
            guiData.ImageCon.Redraw()
            guiData.Gui.Show("w" guiData.ImageWidth " h" guiData.ImageHeight)
        }
    }
}

class FreePasteData {
    __New(gui) {
        this.Gui := gui
    }

    InitText(textCon, minWidth, minHeight, maxWidth, maxHeight) {
        this.Type := 1
        this.TextCon := textCon
        this.FontSize := 13
        this.TextMinWid := minWidth + this.Gui.MarginX * 2
        this.TextMaxWid := maxWidth + this.Gui.MarginX * 2
        this.TextMinHei := minHeight + this.Gui.MarginY * 2
        this.TextMaxHei := maxHeight + this.Gui.MarginY * 2
    }

    InitImage(imageCon, width, height) {
        this.Type := 2
        this.ImageCon := imageCon
        this.ImageWidth := width
        this.ImageHeight := height
    }

    InitOverlay(overlayCon) {
        this.OverlayCon := overlayCon
    }
}
