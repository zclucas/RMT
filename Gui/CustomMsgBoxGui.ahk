#Requires AutoHotkey v2.0

class CustomMsgBoxGui {
    __new() {
        this.Gui := ""
        this.TextCon := ""
        this.Desc := ""
    }

    ShowGui(Desc) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.TextCon.Value := Desc
    }

    AddGui() {
        MyGui := Gui(, GetLang("RMT输出弹窗"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 15
        this.TextCon := MyGui.Add("Edit", Format("x{} y{} w350 h150", PosX, PosY), "")

        PosY += 160
        PosX += 130
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        pos := GetCenterPosOnActiveMonitor(365, 220)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 365, 220))
    }

    OnSureBtnClick() {
        this.Gui.Hide()
    }
}
