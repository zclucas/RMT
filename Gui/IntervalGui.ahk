#Requires AutoHotkey v2.0

class IntervalGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.TimeVarCon := ""
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.Init(cmd)
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.TimeVarCon.Delete()
        this.TimeVarCon.Add(GetGuiVarArr())
        this.TimeVarCon.Text := GetLang("空")
        if (cmdArr.Length == 2) {
            this.TimeVarCon.Text := cmdArr[2]
        }
        else {
            this.TimeVarCon.Text := "500"
        }
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("间隔编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 35
        PosY := 20
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 90, 20), GetLang("时间(毫秒)："))

        PosX += 90
        this.TimeVarCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 2, 150), [])

        PosY += 40
        PosX := 110
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.Show(Format("w{} h{}", 320, 120))
    }

    OnClickSureBtn() {
        if (this.SureBtnAction == "")
            return

        timeText := this.TimeVarCon.Text
        if (IsNumber(timeText)) {
            if (IsFloat(timeText) || timeText < 0) {
                MsgBox(GetLang("请输入大于0的整数"))
                return
            }
        }

        action := this.SureBtnAction
        action(this.GetCmdStr())
        this.Gui.Hide()
    }

    GetCmdStr() {
        return Format("{}_{}", GetLang("间隔"), this.TimeVarCon.Text)
    }
}
