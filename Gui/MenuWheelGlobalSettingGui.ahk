#Requires AutoHotkey v2.0

class MenuWheelGlobalSettingGui {
    __new() {
        this.Gui := ""
        this.FixedPosCon := ""
        this.SelectModeCon := ""
        this.ShowTooltipCon := ""
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
        this.FixedPosCon.Value := !!MySoftData.FixedMenuWheel
        this.SelectModeCon.Value := MySoftData.MenuWheelSelectMode
        this.ShowTooltipCon.Value := !!MySoftData.MenuWheelShowTooltip
    }

    AddGui() {
        MyGui := Gui(, GetLang("菜单轮设置"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 5
        PosY := 10
        MyGui.Add("GroupBox", Format("x{} y{} w400 h140", PosX, PosY), GetLang("通用选项"))

        PosX := 20
        PosY += 28
        this.FixedPosCon := MyGui.Add("Checkbox", Format("x{} y{} w350", PosX, PosY), GetLang("固定位置（屏幕中下方）"))

        PosY += 35
        this.SelectModeCon := MyGui.Add("DropDownList", Format("x{} y{} w200 Choose1", PosX, PosY), [GetLang("点击选择"), GetLang("划线选择")])

        PosY += 35
        this.ShowTooltipCon := MyGui.Add("Checkbox", Format("x{} y{} w350", PosX, PosY), GetLang("显示扇区名称提示"))

        PosX := 80
        PosY += 45
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("恢复默认"))
        con.OnEvent("Click", (*) => this.OnRevertBtnClick())

        PosX := 220
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())

        MyGui.Show(Format("w{} h{}", 420, 240))
    }

    CheckIfValid() {
        return true
    }

    OnRevertBtnClick() {
        this.FixedPosCon.Value := false
        this.SelectModeCon.Value := 1
        this.ShowTooltipCon.Value := true
    }

    OnSureBtnClick() {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        this.Gui.Hide()
    }

    SaveData() {
        MySoftData.FixedMenuWheel := !!this.FixedPosCon.Value
        MySoftData.MenuWheelSelectMode := this.SelectModeCon.Value
        MySoftData.MenuWheelShowTooltip := !!this.ShowTooltipCon.Value

        global IniFile, IniSection
        IniWrite(MySoftData.FixedMenuWheel, IniFile, IniSection, "FixedMenuWheel")
        IniWrite(MySoftData.MenuWheelSelectMode, IniFile, IniSection, "MenuWheelSelectMode")
        IniWrite(MySoftData.MenuWheelShowTooltip, IniFile, IniSection, "MenuWheelShowTooltip")
    }
}
