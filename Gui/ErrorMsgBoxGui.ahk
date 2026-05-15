#Requires AutoHotkey v2.0

class ErrorMsgBoxGui {
    __new() {
        this.Gui := ""
        this.TextCon := ""
        this.Desc := ""
        this.ErrorList := []
    }

    ShowGui(Desc) {
        this.ErrorList.Push(Desc)
        
        if (this.Gui != "") {
            this.Gui.Show()
            this.TextCon.Value := this.GetErrorText()
        }
        else {
            this.AddGui()
        }
    }

    GetErrorText() {
        text := ""
        for i, error in this.ErrorList {
            if (i > 1)
                text .= "`n" . "=" . "=" . "=" . "=" . "=" . "`n"
            text .= error
        }
        return text
    }

    AddGui() {
        MyGui := Gui(, GetLang("RMT错误"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 15
        
        this.TextCon := MyGui.Add("Edit", Format("x{} y{} w500 h250 ReadOnly", PosX, PosY), "")
        this.TextCon.Value := this.GetErrorText()

        PosY += 260
        
        btnCopy := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("复制"))
        btnCopy.OnEvent("Click", (*) => this.OnCopyBtnClick())

        btnClear := MyGui.Add("Button", Format("x{} y{} w80", PosX + 90, PosY), GetLang("清空"))
        btnClear.OnEvent("Click", (*) => this.OnClearBtnClick())

        btnClose := MyGui.Add("Button", Format("x{} y{} w80", PosX + 180, PosY), GetLang("关闭"))
        btnClose.OnEvent("Click", (*) => this.OnCloseBtnClick())

        MyGui.OnEvent("Close", (*) => this.Gui.Hide())
        
        MyGui.Show(Format("w{} h{}", 520, 320))
    }

    OnCopyBtnClick() {
        if (this.TextCon.Value != "") {
            A_Clipboard := this.TextCon.Value
            ToolTipContent(GetLang("已复制"))
        }
    }

    OnClearBtnClick() {
        this.ErrorList := []
        this.TextCon.Value := ""
    }

    OnCloseBtnClick() {
        this.Gui.Hide()
    }
}
