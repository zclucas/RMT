#Requires AutoHotkey v2.0
#Include WinRuleGui.ahk

class MMProGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.RuleMenu := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.FocusCon := ""
        this.RemarkCon := ""
        this.Data := ""
        this.ConfigDLCon := ""
        this.PosAction := () => this.RefreshMousePos()

        this.PosVarXCon := ""
        this.PosVarYCon := ""
        this.ActionTypeCon := ""
        this.MouseMoveModeCon := ""
        this.SpeedCon := ""
        this.CountCon := ""
        this.IntervalCon := ""
        this.HumanMouseTogCon := ""

        this.ConfigDLArr := []
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            if (this.OwnerHwnd != "") {
                this.Gui.Opt("+Owner" this.OwnerHwnd)
            }
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init(cmd)
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("移动Pro编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 3, 400), GetLang("F1:选取当前坐标"))

        PosX := 240
        Con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("定位取色器"))
        Con.OnEvent("Click", this.OnClickTargeterBtn.Bind(this))
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX + 102, PosY), "?")
        Con.OnEvent("Click", this.OnClickTargeterHelpBtn.Bind(this))

        PosX := 10
        PosY += 30
        this.MousePosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 180, 20), GetLang("当前鼠标位置:0,0"))

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 100), GetLang("屏幕规格："))
        PosX += 80
        this.ConfigDLCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 220), [])
        this.ConfigDLCon.OnEvent("Change", (*) => this.OnChangeConfig())
        PosX += 230
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 4, 50, 30), GetLang("编辑"))
        con.OnEvent("Click", this.OnEditScreenRule.Bind(this))

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标位置X:"))
        PosX += 80
        this.PosVarXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 5, 100), [])

        PosX := 240
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标位置Y:"))
        PosX += 80
        this.PosVarYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5 Center", PosX, PosY - 5, 100), [])

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("移动速度："))
        PosX += 80
        this.SpeedCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 100), "90")

        PosX := 240
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("鼠标动作："))
        PosX += 80
        this.ActionTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 5, 100), GetLangArr([
            "移动",
            "移动点击1次", "移动点击2次"]))
        this.ActionTypeCon.Value := 1

        PosX := 10
        PosY += 35
        this.CountTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("移动次数:"))
        PosX += 80
        this.CountCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 100), 1)

        PosX := 240
        this.IntervalTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("每次间隔："))
        PosX += 80
        this.IntervalCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 100), 1000)

        PosY += 30
        PosX := 90
        this.MouseMoveModeCon := MyGui.Add("DropDownList", Format("x{} y{} w120 Choose1", PosX, PosY), ["移动", "相对移动", "游戏视角"])
        this.MouseMoveModeCon.OnEvent("Change", (*) => this.OnTypeChange())

        PosX := 230
        this.HumanMouseTogCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 150), GetLang("启用拟真轨迹"))
        this.HumanMouseTogCon.OnEvent("Click", (*) => this.OnHumanMouseTogClick())

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("游戏视角：调整原神等第一人称，第三人称游戏视角"))

        PosY += 30
        PosX := 190
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 480, 340))
    }

    OnGuiClose() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("移动Pro")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        this.RefreshConfigDLArr()
        this.PosVarXCon.Delete()
        this.PosVarXCon.Add(this.DLVariableArr)
        this.PosVarXCon.Text := GetLang(this.Data.PosVarX)
        this.PosVarYCon.Delete()
        this.PosVarYCon.Add(this.DLVariableArr)
        this.PosVarYCon.Text := GetLang(this.Data.PosVarY)
        this.ActionTypeCon.Value := this.Data.ActionType

        MoveMode := ToolCheckInfo.RecordMouseMoveMode
        if (ObjHasOwnProp(this.Data, "MouseMoveMode"))
            MoveMode := this.Data.MouseMoveMode
        this.MouseMoveModeCon.Value := MoveMode + 1

        this.SpeedCon.Value := this.Data.Speed
        this.CountCon.Value := this.Data.Count
        this.IntervalCon.Value := this.Data.Interval
        this.HumanMouseTogCon.Value := ObjHasOwnProp(this.Data, "IsHumanMouse") ? this.Data.IsHumanMouse : 0

        this.OnTypeChange()
        this.OnHumanMouseTogClick()
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        if (!IsNumber(this.PosVarXCon.Text)) {
            MsgBox(GetLang("坐标X是变量时，编辑模式下无法执行"))
            return
        }

        if (!IsNumber(this.PosVarYCon.Text)) {
            MsgBox(GetLang("坐标Y是变量时，编辑模式下无法执行"))
            return
        }

        this.SaveMMProData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    RefreshConfigDLArr() {
        Arr := []
        Arr.Push(this.Data.ConfigName)
        loop this.Data.ConfigArr.Length {
            CurConfigData := this.Data.ConfigArr[A_Index]
            if (ObjHasOwnProp(CurConfigData, "ConfigName"))
                Arr.Push(CurConfigData.ConfigName)
        }
        this.ConfigDLArr := Arr

        this.ConfigDLCon.Delete()
        this.ConfigDLCon.Add(this.ConfigDLArr)
        this.ConfigDLCon.Text := this.Data.ConfigName
    }

    OnEditScreenRule(con, *) {
        if (this.RuleMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("修改"), (*) => this.OnRuleMenuHandler(GetLang("修改")))
            this.ContextMenu.Add(GetLang("增加"), (*) => this.OnRuleMenuHandler(GetLang("增加")))
            this.ContextMenu.Add(GetLang("删除"), (*) => this.OnRuleMenuHandler(GetLang("删除")))
        }
        con.GetPos(&x, &y)
        this.ContextMenu.Show(x, y)
    }

    OnRuleMenuHandler(Str) {
        if (Str == GetLang("修改")) {
            if (!ObjHasOwnProp(this, "WinRuleGui")) {
                this.WinRuleGui := WinRuleGui()
            }
            SureAction(width, height, remark) {
                ConfigName := Format("{}*{}", width, height)
                if (remark != "")
                    ConfigName := Format("{}*{}_{}", width, height, remark)
                if (ConfigName == this.Data.ConfigName)
                    return
                loop this.ConfigDLArr.Length {
                    if (this.ConfigDLArr[A_Index] == ConfigName) {
                        MsgBox(Format("{} 配置已存在，修改失败", ConfigName))
                        return
                    }
                }

                this.Data.ConfigName := ConfigName
                this.RefreshConfigDLArr()
                saveStr := JSON.stringify(this.Data, 0)
                IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
                MsgBox(GetLang("修改成功"))
            }
            this.WinRuleGui.SureAction := SureAction
            this.WinRuleGui.ShowGui()
        }
        else if (Str == GetLang("增加"))
            this.OnAddConfig()
        else if (Str == GetLang("删除"))
            this.OnRemoveConfig()
    }

    OnAddConfig() {
        if (!ObjHasOwnProp(this, "WinRuleGui")) {
            this.WinRuleGui := WinRuleGui()
        }
        SureAction(width, height, remark) {
            ConfigName := Format("{}*{}", width, height)
            if (remark != "")
                ConfigName := Format("{}*{}_{}", width, height, remark)
            loop this.ConfigDLArr.Length {
                if (this.ConfigDLArr[A_Index] == ConfigName) {
                    MsgBox(Format("{} 配置已存在，无法重复添加", ConfigName))
                    return
                }
            }

            LastConfig := Object()
            LastConfig.ConfigName := this.Data.ConfigName
            LastConfig.PosVarX := GetLangKey(this.PosVarXCon.Text)
            LastConfig.PosVarY := GetLangKey(this.PosVarYCon.Text)
            LastConfig.ActionType := this.ActionTypeCon.Value
            LastConfig.MouseMoveMode := this.MouseMoveModeCon.Value - 1
            LastConfig.Speed := this.SpeedCon.Value
            LastConfig.Count := this.CountCon.Value
            LastConfig.Interval := this.IntervalCon.Value
            this.Data.ConfigArr.Push(LastConfig)

            this.Data.ConfigName := ConfigName
            this.RefreshConfigDLArr()
            saveStr := JSON.stringify(this.Data, 0)
            IniWrite(saveStr, MMPROFile, IniSection, this.Data.SerialStr)
            MsgBox(Format("{} 配置添加成功", ConfigName))
        }
        this.WinRuleGui.SureAction := SureAction
        this.WinRuleGui.ShowGui()
    }

    OnRemoveConfig() {
        if (this.ConfigDLArr.Length <= 1) {
            MsgBox("最后选项不可删除！！！")
            return
        }

        result := MsgBox(Format(GetLang("是否删除 {} 配置"), this.ConfigDLCon.Text), GetLang("提示"), 1)
        if (result == "Cancel")
            return

        ConfigData := this.Data.ConfigArr[1]
        this.Data.ConfigArr.RemoveAt(1)
        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.PosVarX := ConfigData.PosVarX
        this.Data.PosVarY := ConfigData.PosVarY
        this.Data.ActionType := ConfigData.ActionType
        this.Data.MouseMoveMode := ObjHasOwnProp(ConfigData, "MouseMoveMode") ? ConfigData.MouseMoveMode : ToolCheckInfo.RecordMouseMoveMode
        this.Data.Speed := ConfigData.Speed
        this.Data.Count := ConfigData.Count
        this.Data.Interval := ConfigData.Interval
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, MMPROFile, IniSection, this.Data.SerialStr)

        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    OnChangeConfig() {
        LastConfig := Object()
        LastConfig.ConfigName := this.Data.ConfigName
        LastConfig.PosVarX := GetLangKey(this.PosVarXCon.Text)
        LastConfig.PosVarY := GetLangKey(this.PosVarYCon.Text)
        LastConfig.ActionType := this.ActionTypeCon.Value
        LastConfig.MouseMoveMode := this.MouseMoveModeCon.Value - 1
        LastConfig.Speed := this.SpeedCon.Value
        LastConfig.Count := this.CountCon.Value
        LastConfig.Interval := this.IntervalCon.Value
        this.Data.ConfigArr.Push(LastConfig)

        ConfigData := ""
        loop this.ConfigDLArr.Length {
            if (this.ConfigDLCon.Text == this.Data.ConfigArr[A_Index].ConfigName) {
                ConfigData := this.Data.ConfigArr.RemoveAt(A_Index)
                break
            }
        }

        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.PosVarX := ConfigData.PosVarX
        this.Data.PosVarY := ConfigData.PosVarY
        this.Data.ActionType := ConfigData.ActionType
        this.Data.MouseMoveMode := ObjHasOwnProp(ConfigData, "MouseMoveMode") ? ConfigData.MouseMoveMode : ToolCheckInfo.RecordMouseMoveMode
        this.Data.Speed := ConfigData.Speed
        this.Data.Count := ConfigData.Count
        this.Data.Interval := ConfigData.Interval
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, MMPROFile, IniSection, this.Data.SerialStr)
        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    CheckIfValid() {
        return true
    }

    RefreshMousePos() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.MousePosCon.Value := Format("{}{},{}", GetLang("当前鼠标位置:"), mouseX, mouseY)
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.SureMMPro(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.SureMMPro(), "Off")
        }
    }

    OnTypeChange() {
        MoveMode := this.MouseMoveModeCon.Value - 1
        isGameView := MoveMode == 2

        if (isGameView) {
            this.ActionTypeCon.Value := 1
            this.SpeedCon.Value := 100
            this.ActionTypeCon.Enabled := false
            this.SpeedCon.Enabled := false

            if (this.HumanMouseTogCon.Value == 1) {
                this.HumanMouseTogCon.Value := 0
            }
            this.HumanMouseTogCon.Enabled := false
        }
        else {
            this.ActionTypeCon.Enabled := true
            this.SpeedCon.Enabled := true
            this.HumanMouseTogCon.Enabled := true
        }

        this.CountTipCon.Visible := isGameView
        this.CountCon.Visible := isGameView
        this.IntervalTipCon.Visible := isGameView
        this.IntervalCon.Visible := isGameView
    }

    OnSureTarget(PosX, PosY, Color) {
        this.PosVarXCon.Text := PosX
        this.PosVarYCon.Text := PosY
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}", GetLang("1.左键拖拽改变位置"), GetLang("2.上下左右方向键微调位置"), GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"
        ))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return

        this.SaveMMProData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.ToggleFunc(false)

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    SureMMPro() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.PosVarXCon.Text := mouseX
        this.PosVarYCon.Text := mouseY
    }

    OnHumanMouseTogClick(*) {
        isEnabled := this.HumanMouseTogCon.Value == 1

        if (isEnabled) {
            if (this.MouseMoveModeCon.Value - 1 == 2) {
                this.MouseMoveModeCon.Value := 1
                this.OnTypeChange()
            }

            if (this.ActionTypeCon.Value != 1) {
                this.ActionTypeCon.Value := 1
            }
            this.ActionTypeCon.Enabled := false
            this.MouseMoveModeCon.Enabled := false
        }
        else {
            this.ActionTypeCon.Enabled := true
            this.MouseMoveModeCon.Enabled := true
        }
    }

    SaveMMProData() {
        this.Data.PosVarX := GetLangKey(this.PosVarXCon.Text)
        this.Data.PosVarY := GetLangKey(this.PosVarYCon.Text)
        this.Data.ActionType := this.ActionTypeCon.Value
        this.Data.MouseMoveMode := this.MouseMoveModeCon.Value - 1
        this.Data.Speed := this.SpeedCon.Value
        this.Data.Count := this.CountCon.Value
        this.Data.Interval := this.IntervalCon.Value
        this.Data.IsHumanMouse := this.HumanMouseTogCon.Value
        SaveMacroCMDData(this.Data)
    }
}
