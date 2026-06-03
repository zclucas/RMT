#Requires AutoHotkey v2.0

class EditHotkeyGui {
    __new() {
        this.Gui := ""
        this.ShowCon := ""
        this.KeyCon := ""
        this.OnlyTriggerKey := false
        this.TriggerStrBtnCon := ""
    }

    ShowGui(ShowCon, KeyCon, OnlyTriggerKey) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.ShowCon := ShowCon
        this.KeyCon := KeyCon
        this.OnlyTriggerKey := OnlyTriggerKey
        this.TriggerStrBtnCon.Enabled := !this.OnlyTriggerKey
    }

    AddGui() {
        MyGui := Gui(, GetLang("快捷方式编辑"))
        this.Gui := MyGui
        MyGui.SetFont("S12 W550 Q2", MySoftData.FontType)

        PosX := 75
        PosY := 30
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 50), GetLang("快捷键"))
        con.OnEvent("Click", (*) => this.OnEditHotKey(MyTriggerKeyGui))

        PosX += 150
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 50), GetLang("字串"))
        con.OnEvent("Click", (*) => this.OnEditHotKeyStr(MyTriggerStrGui))
        this.TriggerStrBtnCon := con

        pos := GetCenterPosOnActiveMonitor(420, 120)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 420, 120))
    }

    OnEditHotKey(gui) {
        triggerKey := this.KeyCon.Value
        gui.SureBtnAction := this.OnHotKeySureBtn.Bind(this)
        gui.ShowGui(triggerKey, 0, true)
        this.Gui.Hide()
    }

    OnEditHotKeyStr(gui) {
        triggerStr := this.KeyCon.Value
        gui.SureBtnAction := this.OnHotStrSureBtn.Bind(this)
        gui.ShowGui(triggerStr, 0, true)
        this.Gui.Hide()
    }

    OnHotKeySureBtn(sureTriggerStr, holdTime) {
        if (sureTriggerStr != "" && SubStr(sureTriggerStr, 1, 1) == "~") {
            sureTriggerStr := SubStr(sureTriggerStr, 2)
        }
        this.KeyCon.Value := sureTriggerStr
        this.KeyCon.Enabled := false
        this.KeyCon.Visible := true
        this.ShowCon.Visible := false
    }

    OnHotStrSureBtn(sureTriggerStr) {
        this.KeyCon.Value := sureTriggerStr
        this.KeyCon.Enabled := false
        this.KeyCon.Visible := true
        this.ShowCon.Visible := false
    }
}

OnOpenEditHotkeyGui(showCon, keyCon, OnlyTriggerKey, *) {
    MyEditHotkeyGui.ShowGui(showCon, keyCon, OnlyTriggerKey)
}
