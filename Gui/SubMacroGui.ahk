#Requires AutoHotkey v2.0

class SubMacroGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
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
        this.OnRefresh()
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("宏操作编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
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

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("宏类型："))

        PosX += 70
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 110), GetLangArr(["当前宏", "按键宏",
            "字串宏",
            "菜单宏", "定时宏", "宏"]))
        this.TypeCon.Value := 1
        this.TypeCon.OnEvent("Change", (*) => this.OnRefresh())

        PosX += 140
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("宏序号："))

        PosX += 65
        this.DropDownIndexCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R8", PosX, PosY - 5, 185), [])

        PosX := 10
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("操作类型:"))

        PosX += 70
        this.CallTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 110), GetLangArr(["插入到当前宏",
            "触发", "暂停", "取消暂停", "终止"]))
        this.CallTypeCon.Value := 1
        this.CallTypeCon.OnEvent("Change", (*) => this.OnRefresh())

        PosX += 140
        this.InsertCountTipCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("插入次数："))

        PosX += 65
        this.InsertCountCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 5, 130), [])

        PosX := 10
        PosY += 25
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("插入到当前宏: 指定宏 按插入次数 插入到当前宏"))

        PosX := 10
        PosY += 25
        MyGui.Add("Text", Format("x{} y{} h{}", PosX, PosY, 20), GetLang("触发: 运行指定宏，指定宏和当前宏同时执行"))

        PosY += 30
        PosX := 200
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(500, 220)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 500, 220))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("宏操作")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(2)

        this.TypeCon.Text := GetLang(this.Data.MacroType)
        this.CallTypeCon.Text := GetLang(this.Data.CallType)
        this.InsertCountCon.Delete()
        this.InsertCountCon.Add(this.DLVariableArr)
        this.InsertCountCon.Text := GetLang(this.Data.InsertCount)

        tableIndex := GetTableIndex(this.Data.MacroType)
        this.DropDownIndexCon.Delete()
        if (this.Data.MacroType != "当前宏") {
            DropDownArr := []
            for index, Remark in MySoftData.TableInfo[tableIndex].RemarkArr {
                DropDownArr.Push(A_Index ". " Remark)
            }
            this.DropDownIndexCon.Delete()
            this.DropDownIndexCon.Add(DropDownArr)
            if (DropDownArr.Length >= this.Data.Index)
                this.DropDownIndexCon.Value := this.Data.Index
        }

        ;尝试修正序号
        if (this.Data.MacroType != "当前宏") {
            SerialArr := MySoftData.TableInfo[tableIndex].SerialArr
            if (SerialArr.Length < this.Data.Index || SerialArr[this.Data.Index] != this.Data.MacroSerial) {
                loop SerialArr.Length {
                    if (SerialArr[A_Index] == this.Data.MacroSerial) {
                        this.DropDownIndexCon.Value := A_Index
                        break
                    }
                }
            }
        }
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            Hotkey("!l", MacroAction, "On")
        }
        else {
            Hotkey("!l", MacroAction, "Off")
        }
    }

    OnRefresh() {
        EnableIndex := this.TypeCon.Text != GetLang("当前宏")  ;类型是1的时候，不能选择序号
        this.DropDownIndexCon.Enabled := EnableIndex
        if (EnableIndex) {
            lastIndex := Max(1, this.DropDownIndexCon.Value)
            tableIndex := GetTableIndex(GetLangKey(this.TypeCon.Text))
            DropDownArr := []
            for index, Remark in MySoftData.TableInfo[tableIndex].RemarkArr {
                DropDownArr.Push(A_Index ". " Remark)
            }
            this.DropDownIndexCon.Delete()
            this.DropDownIndexCon.Add(DropDownArr)

            if (DropDownArr.Length >= lastIndex)
                this.DropDownIndexCon.Value := lastIndex
            else if (DropDownArr.Length >= 1)
                this.DropDownIndexCon.Value := 1
        }
        else {
            this.DropDownIndexCon.Delete()
        }

        ShowInsert := this.CallTypeCon.Value == 1
        this.InsertCountTipCon.Visible := ShowInsert
        this.InsertCountCon.Visible := ShowInsert
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSubMacroData()
        this.ToggleFunc(false)
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    CheckIfValid() {
        tableIndex := GetTableIndex(GetLangKey(this.TypeCon.Text))
        SerialArr := this.TypeCon.Value == 1 ? "" : MySoftData.TableInfo[tableIndex].SerialArr

        if (SerialArr != "") {
            if (this.DropDownIndexCon.Value > SerialArr.Length || this.DropDownIndexCon.Value == 0) {
                MsgBox(GetLang("配置无效，序号不正确"))
                return false
            }
        }

        return true
    }

    TriggerMacro() {
        this.SaveSubMacroData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.RemarkCon.Value
        if (Remark == "") {
            OperTipArr := GetLangArr(["插入", "触发", "暂停", "取消暂停", "终止"])
            IntervarlStr := MySoftData.Lang == "中文" ? "" : " "
            MacroTypeArr := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"])
            OperStr := OperTipArr[this.CallTypeCon.Value]
            TypeStr := MacroTypeArr[this.TypeCon.Value]
            SerialStr := this.TypeCon.Value == 1 ? "" : this.DropDownIndexCon.value
            Remark := OperStr IntervarlStr TypeStr SerialStr
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        this.Data.MacroType := GetLangKey(this.TypeCon.Text)
        this.Data.Index := this.DropDownIndexCon.value
        this.Data.CallType := GetLangKey(this.CallTypeCon.Text)
        this.Data.InsertCount := GetLangKey(this.InsertCountCon.Text)

        tableIndex := GetTableIndex(this.Data.MacroType)
        SerialArr := this.TypeCon.Value == 1 ? "" : MySoftData.TableInfo[tableIndex].SerialArr
        this.Data.MacroSerial := SerialArr != "" ? SerialArr[this.Data.Index] : ""

        SaveMacroCMDData(this.Data)
    }
}
