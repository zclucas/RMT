#Requires AutoHotkey v2.0

class TimingGui {
    __new() {
        this.Gui := ""
        this.Data := ""
        this.IntervalLabelCon := ""
        this.IntervalUnitCon := ""

        this.StartTimeCon := ""
        this.EndTimeCon := ""
        this.TypeCon := ""
        this.CustomIntervalCon := ""
    }

    ShowGui(SerialStr) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.Init(SerialStr)
        this.OnChangeType()
    }

    Init(SerialStr) {
        this.SerialStr := SerialStr != "" ? SerialStr : GetCMDSerialStr("Timing")
        this.Data := this.GetTimingData(this.SerialStr)

        this.StartTimeCon.Value      := StampToTimeStr(this.Data.StartStamp)
        this.EndTimeCon.Value        := (this.Data.HasOwnProp("EndStamp") && this.Data.EndStamp) ? StampToTimeStr(this.Data.EndStamp) : ""
        this.TypeCon.Value           := this.Data.Type
        this.CustomIntervalCon.Value := this.Data.HasOwnProp("CustomInterval") ? this.Data.CustomInterval : "10"
        this.IntervalUnitCon.Value   := this.Data.HasOwnProp("CustomUnit")     ? this.Data.CustomUnit     : 2
    }

    AddGui() {
        MyGui := Gui(, GetLang("定时编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MainSoftData.FontType)

        PosX := 10
        PosY := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开始时间："))
        PosX += 80
        this.StartTimeCon := MyGui.Add("DateTime", Format("x{} y{} w190", PosX, PosY - 3), "yyyy-MM-dd HH:mm:ss")

        PosX += 200
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("结束时间："))
        PosX += 80
        this.EndTimeCon := MyGui.Add("DateTime", Format("x{} y{} w220 ChooseNone", PosX, PosY - 3), "yyyy-MM-dd HH:mm:ss")

        PosX := 10
        PosY += 40
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("定时类型："))
        con.Focus()
        PosX += 80
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w120", PosX, PosY - 3), GetLangArr(["单次", "软件启动时", "自定义"]))
        this.TypeCon.OnEvent("Change", (*) => this.OnChangeType())
        PosX += 200
        this.IntervalLabelCon := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("每次间隔："))
        PosX += 80
        this.CustomIntervalCon := MyGui.Add("Edit", Format("x{} y{} w110", PosX, PosY - 3), "")
        PosX += 115
        this.IntervalUnitCon := MyGui.Add("DropDownList", Format("x{} y{} w80", PosX, PosY -3), GetLangArr(["秒", "分钟", "小时", "天", "周", "月"]))

        PosX := 250
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        pos := GetCenterPosOnActiveMonitor(620, 150)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 620, 150))
    }

    CheckIfValid() {
        if (this.EndTimeCon.Value != "" && this.EndTimeCon.Value <= this.StartTimeCon.Value) {
            MsgBox(GetLang("勾选结束时间后，结束时间必须大于开始时间！！！"))
            return false
        }

        if (this.TypeCon.Value == 7 && IsFloat(this.CustomIntervalCon.Value)) {
            MsgBox(GetLang("每次间隔时间只能是整数！！"))
            return false
        }

        if (!IsNumber(this.CustomIntervalCon.Value) && this.CustomIntervalCon.Value <= 0) {
            MsgBox(GetLang("每次间隔需要输入大于零的数字！！！"))
            return false
        }

        return true
    }

    OnChangeType() {
        isCustom := this.TypeCon.Value == 3

        this.IntervalLabelCon.Visible := isCustom
        this.CustomIntervalCon.Visible := isCustom
        this.IntervalUnitCon.Visible := isCustom
    }

    OnSureBtnClick() {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        this.SaveTimingData()
        this.Gui.Hide()
    }

    SaveTimingData() {
        Data := this.Data
        ; Convert AHK datetime string from controls to Unix stamps for storage
        Data.StartStamp := TimeStrToStamp(FormatTime(this.StartTimeCon.Value, "yyyyMMddHHmmss"))
        Data.EndStamp   := this.EndTimeCon.Value == "" ? 0 : TimeStrToStamp(FormatTime(this.EndTimeCon.Value, "yyyyMMddHHmmss"))
        Data.Type := this.TypeCon.Value
        Data.CustomInterval := this.CustomIntervalCon.Value
        Data.CustomUnit := this.IntervalUnitCon.Value

        ; Build a minimal object — only save fields that are actually needed
        minimal := {}
        minimal.StartStamp := Data.StartStamp
        minimal.Type       := Data.Type
        if (Data.EndStamp)                ; omit when 0 (no end)
            minimal.EndStamp := Data.EndStamp
        if (Data.Type == 3) {             ; custom repeat only
            minimal.CustomInterval := Data.CustomInterval
            minimal.CustomUnit     := Data.CustomUnit
        }

        saveStr := JSON.stringify(minimal, 0)
        IniWrite(saveStr, TimingFile, IniSection, Data.SerialStr)

        if (MySoftData.DataCacheMap.Has(this.Data.SerialStr))
            MySoftData.DataCacheMap.Delete(this.Data.SerialStr)
    }

    GetTimingData(SerialStr) {
        saveStr := IniRead(TimingFile, IniSection, SerialStr, "")
        if (!saveStr) {
            data := TimingData()
            data.SerialStr := SerialStr
            return data
        }

        data := JSON.parse(saveStr, , false)

        ; SerialStr is omitted from JSON to avoid redundancy — restore it from the INI key
        data.SerialStr := SerialStr

        ; Migrate legacy StartTime/EndTime string fields to StartStamp/EndStamp
        if (data.HasOwnProp("StartTime") && !data.HasOwnProp("StartStamp")) {
            data.StartStamp := TimeStrToStamp(data.StartTime)
            if (data.HasOwnProp("EndTime") && data.EndTime != "")
                data.EndStamp := TimeStrToStamp(data.EndTime)
        }

        return data
    }
}
