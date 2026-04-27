#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

class CompareProEditItemGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.RemarkCon := ""
        this.FocusCon := ""
        this.MacroGui := ""

        this.IsSubMacroEdit := false
        this.Data := ""
        this.CondiNumber := 1

        this.EditType := 1  ;1正常分支 2兜底分支
        this.ToggleConArr := []
        this.NameConArr := []
        this.CompareTypeConArr := []
        this.VariableConArr := []
        this.LogicalTypeCon := ""
        this.MacroCon := ""
    }

    MacroEditShowGui(CommandStr, CondiNumber) {
        paramArr := StrSplit(CommandStr, "_")
        Data := GetMacroCMDData(paramArr[1])
        this.Data := Data
        this.CondiNumber := CondiNumber
        EditType := CondiNumber <= Data.VariNameArr.Length ? 1 : 2
        if (EditType == 2) {
            this.ShowGui(EditType, [[], [], []], GetLang("且"), Data.DefaultMacro, Data.DefaultControlType)
            return
        }

        DataArr := []
        DataArr.Push(Data.VariNameArr[CondiNumber])
        DataArr.Push(Data.CompareTypeArr[CondiNumber])
        DataArr.Push(Data.VariableArr[CondiNumber])
        logicStr := Data.LogicTypeArr[CondiNumber] == 1 ? GetLang("且") : GetLang("或")
        macro := Data.MacroArr[CondiNumber]
        controlType := Data.ControlTypeArr[CondiNumber]
        this.ShowGui(EditType, DataArr, logicStr, macro, controlType)
    }

    ShowGui(EditType, DataArr, logicStr, macro, controlType) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        this.Init(EditType, DataArr, logicStr, macro, controlType)
        this.OnRefresh()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("如果Pro分支编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 30), GetLang("逻辑关系："))
        this.LogicalTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 85, PosY - 3, 60), GetLangArr([
            "且", "或"]))

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 50
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("选择/输入"))
        PosX += 230
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("选择/输入"))

        PosY += 25
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 160, PosY - 3, 80), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 245, PosY - 3, 120), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 160, PosY - 3, 80), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 245, PosY - 3, 120), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 160, PosY - 3, 80), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 245, PosY - 3, 120), [])
        this.VariableConArr.Push(con)

        PosY += 35
        PosX := 15
        con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ToggleConArr.Push(con)
        con.Value := 1

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.NameConArr.Push(con)

        con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 160, PosY - 3, 80), GetLangArr(["大于", "大于等于",
            "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"]))
        con.Value := 1
        con.OnEvent("Change", (*) => this.OnRefresh())
        this.CompareTypeConArr.Push(con)

        con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 245, PosY - 3, 120), [])
        this.VariableConArr.Push(con)

        PosY += 40
        PosX := 10
        SplitPosY := PosY
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 160, 20), GetLang("分支指令:"))

        PosX += 80
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 60, 25), GetLang("编辑"))
        btnCon.OnEvent("Click", (*) => this.OnEditMacroBtnClick())

        PosY += 25
        PosX := 10
        this.MacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 370, 60), "")

        PosY += 65
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), GetLang("流程控制："))
        PosX += 80
        this.ControlTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 125), GetLangArr(["无",
            "循环-跳过本轮", "循环-跳出", "分支-跳出"]))
        this.ControlTypeCon.Value := 1

        PosY += 40
        PosX := 170
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.Show(Format("w{} h{}", 420, 400))
    }

    Init(EditType, DataArr, logicStr, macro, controlType) {
        this.EditType := EditType
        this.LogicalTypeCon.Text := logicStr == "" ? GetLang("且") : logicStr
        this.MacroCon.Value := macro
        this.ControlTypeCon.Text := GetLang(controlType)
        this.DLVariableArr := GetGuiVarArr(1)

        VariNameArr := DataArr[1]
        CompareTypeArr := DataArr[2]
        VariableArr := DataArr[3]
        loop 4 {
            this.ToggleConArr[A_Index].Value := VariNameArr.Length >= A_Index
            this.NameConArr[A_Index].Delete()
            this.NameConArr[A_Index].Add(this.DLVariableArr)
            this.NameConArr[A_Index].Text := VariNameArr.Length >= A_Index ? VariNameArr[A_Index] : "Var" A_Index
            this.CompareTypeConArr[A_Index].Value := CompareTypeArr.Length >= A_Index ? CompareTypeArr[A_Index] : 1
            this.VariableConArr[A_Index].Delete()
            this.VariableConArr[A_Index].Add(this.DLVariableArr)
            this.VariableConArr[A_Index].Text := VariableArr.Length >= A_Index ? VariableArr[A_Index] : "Var" A_Index
        }

        isEnabled := EditType == 1
        this.LogicalTypeCon.Enabled := isEnabled
        loop 4 {
            this.ToggleConArr[A_Index].Enabled := isEnabled
            this.NameConArr[A_Index].Enabled := isEnabled
            this.CompareTypeConArr[A_Index].Enabled := isEnabled
            this.VariableConArr[A_Index].Enabled := isEnabled
        }
    }

    OnRefresh() {
        loop 4 {
            OperaTypeValue := this.CompareTypeConArr[A_Index].Value
            EnableVari := OperaTypeValue != 7 && this.EditType == 1
            this.VariableConArr[A_Index].Enabled := EnableVari
        }
    }

    OnClickSureBtn() {
        action := this.SureBtnAction
        if (this.IsSubMacroEdit) {
            if (this.EditType == 2) {
                this.Data.DefaultMacro := GetLangStr(this.MacroCon.Value, 2)
                this.Data.DefaultControlType := GetLangKey(this.ControlTypeCon.Text)
            }
            else {
                VariNameArr := []
                CompareTypeArr := []
                VariableArr := []
                loop 4 {
                    if (this.ToggleConArr[A_Index].Value) {
                        VariNameArr.Push(this.NameConArr[A_Index].Text)
                        CompareTypeArr.Push(this.CompareTypeConArr[A_Index].Value)
                        VariableArr.Push(this.VariableConArr[A_Index].Text)
                    }
                }
                this.Data.VariNameArr[this.CondiNumber] := GetLangKeyArr(VariNameArr)
                this.Data.CompareTypeArr[this.CondiNumber] := GetLangKeyArr(CompareTypeArr)
                this.Data.VariableArr[this.CondiNumber] := GetLangKeyArr(VariableArr)
                this.Data.LogicTypeArr[this.CondiNumber] := this.LogicalTypeCon.Value
                this.Data.MacroArr[this.CondiNumber] := GetLangStr(this.MacroCon.Value, 2)
                this.Data.ControlTypeArr[this.CondiNumber] := GetLangKey(this.ControlTypeCon.Text)
            }
            saveStr := JSON.stringify(this.Data, 0)
            IniWrite(saveStr, CompareProFile, IniSection, this.Data.SerialStr)
            if (MySoftData.DataCacheMap.Has(this.Data.SerialStr)) {
                MySoftData.DataCacheMap.Delete(this.Data.SerialStr)
            }
            action(this.MacroCon.Value)
        }
        else if (this.EditType == 1) {
            condiStr := ""
            loop 4 {
                if (this.ToggleConArr[A_Index].Value) {
                    if (this.CompareTypeConArr[A_Index].Text != GetLang("变量存在")) {
                        condiStr .= this.NameConArr[A_Index].Text " " this.CompareTypeConArr[A_Index].Text " " this.VariableConArr[
                            A_Index].Text
                    }
                    else {
                        condiStr .= this.NameConArr[A_Index].Text " " this.CompareTypeConArr[A_Index].Text
                    }

                    condiStr .= "⎖"
                }
            }
            condiStr := Trim(condiStr, "⎖")
            logicStr := this.LogicalTypeCon.Text
            macro := this.MacroCon.Value
            controlType := GetLangKey(this.ControlTypeCon.Text)
            action(condiStr, logicStr, macro, controlType)
        }
        else {
            controlType := GetLangKey(this.ControlTypeCon.Text)
            action(GetLang("以上都不是"), "", this.MacroCon.Value, controlType)
        }

        this.SureBtnAction := ""
        this.Gui.Hide()
    }

    OnMacroBtnClick(CommandStr) {
        this.MacroCon.Value := GetLangMacro(CommandStr, 1)
    }

    OnEditMacroBtnClick() {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            this.MacroGui.SureFocusCon := this.LogicalTypeCon

            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.MacroGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnMacroBtnClick(command)
        this.MacroGui.ShowGui(this.MacroCon.Value, false)
    }
}
