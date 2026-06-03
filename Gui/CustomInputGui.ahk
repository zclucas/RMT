#Requires AutoHotkey v2.0

class CustomInputGui {
    __new() {
        this.Gui := ""
        this.HideAction := ""
        this.SureAction := ""
        this.CloseAction := ""
    }

    ShowGui(Label, Content) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.LabelCon.Value := Label
        this.ContentCon.Value := Content
    }

    AddGui() {
        MyGui := Gui(, GetLang("输入弹窗"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        PosX := 10
        PosY := 15
        this.LabelCon := MyGui.Add("Text", Format("x{} y{} w350", PosX, PosY), "变量名：Data")

        PosX := 10
        PosY += 30
        this.ContentCon := MyGui.Add("Edit", Format("x{} y{} w350 h150", PosX, PosY), "")

        PosY += 160
        PosX += 130
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", this.OnSureBtnClick.Bind(this))
        MyGui.OnEvent("Close", this.OnCloseBtnClick.Bind(this))
        pos := GetCenterPosOnActiveMonitor(365, 250)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 365, 250))
    }

    OnSureBtnClick(*) {
        this.OnSure()
        this.OnHide()
        this.Gui.Hide()
    }

    OnCloseBtnClick(*) {
        this.OnClose()
        this.OnHide()
    }

    OnSure() {
        if (this.SureAction != "") {
            Action := this.SureAction
            Action(this.ContentCon.Text)
            this.SureAction := ""
        }
    }

    OnClose() {
        if (this.CloseAction != "") {
            Action := this.CloseAction
            Action()
            this.CloseAction := ""
        }
    }

    OnHide() {
        if (this.HideAction != "") {
            Action := this.HideAction
            Action()
            this.HideAction := ""
        }
    }
}
