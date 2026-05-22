#Requires AutoHotkey v2.0

class ToolRecordSettingGui {
    __new() {
        this.Gui := ""

        this.AutoLoosenCon := ""
        this.HoldMutiCon := ""
        this.KeyboardTogCon := ""
        this.MouseTogCon := ""
        this.MouseTrailModeCon := ""
        this.MouseTrailSpeedCon := ""
        this.JoyTogCon := ""
        this.JoyIntervalCon := ""

        this.ShowBorderCon := ""

        this.TrailTipCon3 := ""
        this.JoyTipCon := ""
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.Init()
    }

    Init() {
        this.AutoLoosenCon.Value := ToolCheckInfo.RecordAutoLoosen
        this.HoldMutiCon.Value := ToolCheckInfo.RecordHoldMuti
        this.KeyboardTogCon.Value := ToolCheckInfo.RecordKeyboard
        this.MouseTogCon.Value := ToolCheckInfo.RecordMouse
        this.MouseTrailModeCon.Value := ToolCheckInfo.RecordMouseTrail + 1
        this.MouseTrailSpeedCon.Value := ToolCheckInfo.RecordMouseTrailSpeed
        this.JoyTogCon.Value := ToolCheckInfo.RecordJoy
        this.JoyIntervalCon.Value := ToolCheckInfo.RecordJoyInterval
        this.ShowBorderCon.Value := ToolCheckInfo.RecordShowBorder
        this.OnTogClick()
        this.OnTrailModeChange()
    }

    AddGui() {
        MyGui := Gui(, GetLang("录制选项编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 5
        PosY := 10
        MyGui.Add("GroupBox", Format("x{} y{} w510 h320", PosX, PosY), GetLang("通用选项"))

        PosX := 20
        PosY += 25
        this.AutoLoosenCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("结束自动添加松开指令"))

        PosX += 245
        this.HoldMutiCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("长按多次录制"))

        PosX := 10
        PosY += 35
        MyGui.Add("GroupBox", Format("x{} y{} w500 h50", PosX, PosY), GetLang("键盘选项"))

        PosX += 10
        PosY += 25
        this.KeyboardTogCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("录制开关"))

        PosX := 10
        PosY += 40
        MyGui.Add("GroupBox", Format("x{} y{} w500 h100", PosX, PosY), GetLang("鼠标选项"))

        PosX := 20
        PosY += 25
        this.MouseTogCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("录制开关"))
        this.MouseTogCon.OnEvent("Click", (*) => this.OnTogClick())

        PosX += 245
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("鼠标轨迹"))
        PosX += 70
        this.MouseTrailModeCon := MyGui.Add("DropDownList", Format("x{} y{} w120 Choose2", PosX, PosY - 5), [GetLang("不录制"), GetLang("关键点位"), GetLang("关键点相对位移"), GetLang("全量")])
        this.MouseTrailModeCon.OnEvent("Change", (*) => this.OnTrailModeChange())

        PosY += 30
        PosX := 20
        this.TrailTipCon3 := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("轨迹速度(0~100)："))
        PosX += 130
        this.MouseTrailSpeedCon := MyGui.Add("Edit", Format("x{} y{} w60 h25", PosX, PosY - 3), "95")

        PosX := 10
        PosY += 45
        MyGui.Add("GroupBox", Format("x{} y{} w500 h55", PosX, PosY), GetLang("手柄选项"))

        PosX += 10
        PosY += 25
        this.JoyTogCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("录制开关"))
        this.JoyTogCon.OnEvent("Click", (*) => this.OnTogClick())

        PosX += 245
        this.JoyTipCon := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("检测间隔(ms)："))
        PosX += 130
        this.JoyIntervalCon := MyGui.Add("Edit", Format("x{} y{} w60 h25", PosX, PosY - 3), "50")

        PosX := 20
        PosY += 35
        this.ShowBorderCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("录制显示边框"))

        PosX := 100
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("恢复默认"))
        con.OnEvent("Click", (*) => this.OnRevertBtnClick())

        PosX := 300
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())

        MyGui.Show(Format("w{} h{}", 525, 395))
    }

    CheckIfValid() {
        return true
    }

    OnTogClick() {
        IsMouse := this.MouseTogCon.Value
        IsJoy := this.JoyTogCon.Value
        trailMode := this.MouseTrailModeCon.Value - 1
        isKeyPointTrail := (trailMode == 1 || trailMode == 2)
        isTrailSettingsEnabled := IsMouse && isKeyPointTrail

        this.MouseTrailModeCon.Enabled := IsMouse
        this.MouseTrailSpeedCon.Enabled := isTrailSettingsEnabled
        this.TrailTipCon3.Enabled := isTrailSettingsEnabled
        this.JoyIntervalCon.Enabled := IsJoy
        this.JoyTipCon.Enabled := isTrailSettingsEnabled
    }

    OnTrailModeChange() {
        this.OnTogClick()
    }

    OnRevertBtnClick() {
        this.AutoLoosenCon.Value := true
        this.HoldMutiCon.Value := false
        this.KeyboardTogCon.Value := true
        this.MouseTogCon.Value := true
        this.MouseTrailModeCon.Value := 2
        this.MouseTrailSpeedCon.Value := 95
        this.JoyTogCon.Value := false
        this.JoyIntervalCon.Value := 50
        this.ShowBorderCon.Value := true
    }

    OnSureBtnClick() {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        this.SaveData()
        this.Gui.Hide()
    }

    SaveData() {
        ToolCheckInfo.RecordAutoLoosen := this.AutoLoosenCon.Value
        ToolCheckInfo.RecordHoldMuti := this.HoldMutiCon.Value
        ToolCheckInfo.RecordKeyboard := this.KeyboardTogCon.Value
        ToolCheckInfo.RecordMouse := this.MouseTogCon.Value
        ToolCheckInfo.RecordMouseTrail := this.MouseTrailModeCon.Value - 1
        ToolCheckInfo.RecordMouseTrailSpeed := this.MouseTrailSpeedCon.Value
        ToolCheckInfo.RecordJoy := this.JoyTogCon.Value
        ToolCheckInfo.RecordJoyInterval := this.JoyIntervalCon.Value
        ToolCheckInfo.RecordShowBorder := this.ShowBorderCon.Value

        global IniFile, IniSection
        IniWrite(ToolCheckInfo.RecordAutoLoosen, IniFile, IniSection, "RecordAutoLoosen")
        IniWrite(ToolCheckInfo.RecordHoldMuti, IniFile, IniSection, "RecordHoldMuti")
        IniWrite(ToolCheckInfo.RecordKeyboard, IniFile, IniSection, "RecordKeyboard")
        IniWrite(ToolCheckInfo.RecordMouse, IniFile, IniSection, "RecordMouse")
        IniWrite(ToolCheckInfo.RecordMouseTrail, IniFile, IniSection, "RecordMouseTrail")
        IniWrite(ToolCheckInfo.RecordMouseTrailSpeed, IniFile, IniSection, "RecordMouseTrailSpeed")
        IniWrite(ToolCheckInfo.RecordJoy, IniFile, IniSection, "RecordJoy")
        IniWrite(ToolCheckInfo.RecordJoyInterval, IniFile, IniSection, "RecordJoyInterval")
        IniWrite(ToolCheckInfo.RecordShowBorder, IniFile, IniSection, "RecordShowBorder")
    }
}
