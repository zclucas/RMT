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

        this.StartTimeCon.Value := this.Data.StartTime
        this.EndTimeCon.Value := this.Data.EndTime
        this.TypeCon.Value := this.Data.Type
        this.CustomIntervalCon.Value := this.Data.CustomInterval
        this.IntervalUnitCon.Value := this.Data.CustomUnit
    }

    AddGui() {
        MyGui := Gui(, GetLang("定时编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

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
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w120", PosX, PosY - 3), GetLangArr(["单次", "每小时", "每天", "每周",
            "每月", "软件启动时","自定义"]))
        this.TypeCon.OnEvent("Change", (*) => this.OnChangeType())
        PosX += 200
        this.IntervalLabelCon := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("每次间隔："))
        PosX += 80
        this.CustomIntervalCon := MyGui.Add("Edit", Format("x{} y{} w110", PosX, PosY - 3), "")
        PosX += 115
        this.IntervalUnitCon := MyGui.Add("DropDownList", Format("x{} y{} w80", PosX, PosY -3), GetLangArr(["秒", "分钟", "小时", "天", "周"]))

        PosX := 250
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        MyGui.Show(Format("w{} h{}", 620, 150))
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
        isCustom := this.TypeCon.Value == 7

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
        Data.StartTime := FormatTime(this.StartTimeCon.Value, "yyyyMMddHHmmss")
        Data.EndTime := this.EndTimeCon.Value == "" ? "" : FormatTime(this.EndTimeCon.Value, "yyyyMMddHHmmss")
        Data.Type := this.TypeCon.Value
        Data.CustomInterval := this.CustomIntervalCon.Value
        Data.CustomUnit := this.IntervalUnitCon.Value
        saveStr := JSON.stringify(Data, 0)
        IniWrite(saveStr, TimingFile, IniSection, Data.SerialStr)
        if (MySoftData.DataCacheMap.Has(this.Data.SerialStr)) {
            MySoftData.DataCacheMap.Delete(this.Data.SerialStr)
        }
    }

    GetTimingData(SerialStr) {
        saveStr := IniRead(TimingFile, IniSection, SerialStr, "")
        if (!saveStr) {
            data := TimingData()
            data.SerialStr := SerialStr
            return data
        }

        data := JSON.parse(saveStr, , false)
        return data
    }
}
