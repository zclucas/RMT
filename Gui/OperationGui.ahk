#Requires AutoHotkey v2.0
#Include OperationSubGui.ahk

class OperationGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.Data := ""
        this.OperationSubGui := ""

        this.ToggleConArr := []
        this.ExprConArr := []
        this.UpdateNameConArr := []
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
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("运算编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 50, 30), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosX := 10
        PosY += 35
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 50
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("运算表达式"))
        PosX += 350
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("结果保存变量"))
        PosY -= 10

        loop 4 {
            PosY += 35
            PosX := 15
            con := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
            this.ToggleConArr.Push(con)

            PosX += 35
            con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 300), "")
            con.Enabled := false
            this.ExprConArr.Push(con)

            PosX += 305
            con := MyGui.Add("Button", Format("x{} y{} w{} Center", PosX, PosY - 4, 50), GetLang("编辑"))
            con.OnEvent("Click", this.OnEditVariableBtnClick.Bind(this, A_Index))

            PosX += 55
            con := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 3, 120), [])
            this.UpdateNameConArr.Push(con)
        }

        PosY += 40
        PosX := 225
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(550, 270)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 550, 270))
    }

    OnGuiClose() {
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运算")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()

        loop this.Data.ToggleArr.Length {
            this.ToggleConArr[A_Index].Value := this.Data.ToggleArr[A_Index]
            this.ExprConArr[A_Index].Value := GetLangStr(this.Data.ExpressionArr[A_Index], 1)
            this.UpdateNameConArr[A_Index].Delete()
            this.UpdateNameConArr[A_Index].Add(this.DLVariableArr)
            this.UpdateNameConArr[A_Index].Text := GetLang(this.Data.UpdateNameArr[A_Index])
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.RemarkCon.Value
        if (Remark == "") {
            Remark := GetLang("更新")
            loop 4 {
                if (this.ToggleConArr[A_Index].Value) {
                    Remark .= this.UpdateNameConArr[A_Index].Text "&"
                }
            }
            Remark := RTrim(Remark, "&")
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    OnEditVariableBtnClick(Index, *) {
        if (this.OperationSubGui == "") {
            this.OperationSubGui := OperationSubGui()
        }

        ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
        this.OperationSubGui.ParentTile := ParentTile "-"

        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.OperationSubGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.OperationSubGui.OwnerHwnd := ""
        }

        this.OperationSubGui.SureBtnAction := (Index, ExpressStr) => this.OnSureOperationBtnClick(
            Index, ExpressStr)

        ; 将表达式作为参数传递给ShowGui，Name为空表示没有预先选择的变量
        this.OperationSubGui.ShowGui(Index, this.ExprConArr[Index].Value)
    }

    OnSureOperationBtnClick(Index, ExpressStr) {
        this.ExprConArr[Index].Text := ExpressStr
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveOperationData()
        action := this.SureBtnAction
        action(this.GetCommandStr())

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    CheckIfValid() {
        loop 4 {
            IsOn := this.ToggleConArr[A_Index].Value
            if (IsOn && !CheckVarNameIfValid(this.UpdateNameConArr[A_Index].Text)) {
                return false
            }
        }

        return true
    }

    SaveOperationData() {
        loop this.Data.ToggleArr.Length {
            this.Data.ToggleArr[A_Index] := this.ToggleConArr[A_Index].Value
            this.Data.ExpressionArr[A_Index] := GetLangStr(this.ExprConArr[A_Index].Value, 2)
            this.Data.UpdateNameArr[A_Index] := GetVarName(this.UpdateNameConArr[A_Index].Text)
        }

        ; 添加全局变量，方便下拉选取
        loop this.Data.ToggleArr.Length {
            if (this.Data.ToggleArr[A_Index])
                MySoftData.GlobalVariMap[this.Data.UpdateNameArr[A_Index]] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
