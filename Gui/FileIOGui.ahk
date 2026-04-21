#Requires AutoHotkey v2.0

class FileIOGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""

        this.OperModeMap := Map(
            GetLang("读取Excel"),
            GetLangArr(["单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"]),
            GetLang("写入Excel"),
            GetLangArr(["单元格", "行号自增", "列号自增", "指定区域-行", "指定区域-列"]),
            GetLang("读取文本文件"),
            GetLangArr(["读取全部内容", "逐行读取", "指定行"]),
            GetLang("写入文本文件"),
            GetLangArr(["覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"])
        )
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        this.Init(cmd)
        this.RefreshConVisable()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("文件读写编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80, 20), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 120
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosX := 20
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("操作类型:"))
        PosX += 80
        TypeArr := GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"])
        this.OperTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 150), TypeArr)
        this.OperTypeCon.OnEvent("Change", this.OnRefreshType.Bind(this))

        PosX := 280
        this.EncodingConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("文件编码:"))
        this.EncodingConArr.Push(con)
        PosX += 80
        TypeArr := GetLangArr(MySoftData.FileEncodingArr)
        this.EncodingCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 150), TypeArr)
        this.EncodingConArr.Push(this.EncodingCon)

        PosX := 20
        PosY += 35
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("文件路径:"))
        PosX += 80
        this.FilePathCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 320, 30))
        PosX += 330
        con := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("选择文件"))
        con.OnEvent("Click", (*) => this.OnSelectPathBtnClick())

        PosX := 20
        PosY += 40
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("操作模式:"))
        PosX += 80
        this.OperModeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 150), GetLangArr([]))
        this.OperModeCon.OnEvent("Change", this.OnRefreshOperMode.Bind(this))

        PosX := 280
        this.TextRowConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("行号:"))
        this.TextRowConArr.Push(con)
        PosX += 80
        this.TextRowVarCon := MyGui.Add("ComboBox", Format("x{} y{} w{} h{}", PosX, PosY, 150, 30), [])
        this.TextRowConArr.Push(this.TextRowVarCon)

        PosX := 280
        this.ExcelConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("表名或序号:"))
        this.ExcelConArr.Push(con)
        PosX += 80
        this.NameOrSerialCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY, 150), [])
        this.ExcelConArr.Push(this.NameOrSerialCon)

        PosX := 20
        PosY += 35
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("表格行号:"))
        this.ExcelConArr.Push(con)
        PosX += 80
        this.RowCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY, 150), [])
        this.ExcelConArr.Push(this.RowCon)

        PosX := 280
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("表格列号:"))
        this.ExcelConArr.Push(con)
        PosX += 80
        this.ColCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY, 150, 30), [])
        this.ExcelConArr.Push(this.ColCon)

        PosX := 20
        PosY += 35
        this.RegionConArr := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("终止行号:"))
        this.RegionConArr.Push(con)
        PosX += 80
        this.RowEndCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY, 150), [])
        this.RegionConArr.Push(this.RowEndCon)

        PosX := 280
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY + 5, 80), GetLang("终止列号:"))
        this.RegionConArr.Push(con)
        PosX += 80
        this.ColEndCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY, 150, 30), [])
        this.RegionConArr.Push(this.ColEndCon)

        PosY += 35
        FlagY := PosY

        ;读取保存
        {
            PosX := 10
            PosY := FlagY
            this.ResultConArr := []
            Con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 510, 70), GetLang("结果保存"))
            this.ResultConArr.Push(Con)

            PosX := 20
            PosY += 30
            Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("结果："))
            this.ResultConArr.Push(Con)

            PosX += 50
            this.SaveTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLangArr(["变量",
                "数组"]))
            this.SaveTypeCon.Enabled := false
            this.ResultConArr.Push(this.SaveTypeCon)

            PosX += 105
            this.SaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 150), [])
            this.ResultConArr.Push(this.SaveNameCon)

        }

        ;写入内容
        {
            PosX := 20
            PosY := FlagY
            this.WriteConArr := []
            this.TextTipCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 20), GetLang("输出内容："))
            this.WriteConArr.Push(this.TextTipCon)
            PosX += 80
            this.ContentCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 370, 50))
            this.WriteConArr.Push(this.ContentCon)

            PosX := 20
            PosY += 55
            Con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 350, 20), GetLang("变量数组："))
            this.WriteConArr.Push(Con)
            PosX += 80
            this.WriteVarTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY, 85), GetLangArr(["变量",
                "数组"]))
            this.WriteVarTypeCon.Value := 1

            this.WriteVarTypeCon.OnEvent("Change", this.OnRefreshContentVarType.Bind(this))
            this.WriteConArr.Push(this.WriteVarTypeCon)
            PosX += 90
            this.WriteVarCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R10", PosX, PosY, 130), [])
            this.WriteConArr.Push(this.WriteVarCon)
            this.VarNameBtn := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 135, PosY - 1, 70, 29), GetLang(
                "追加名"))
            this.WriteConArr.Push(this.VarNameBtn)
            this.VarNameBtn.OnEvent("Click", (*) => this.OnClickAddVarNameBtn())
            this.VarValueBtn := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 210, PosY - 1, 70, 29), GetLang(
                "追加值"))
            this.WriteConArr.Push(this.VarValueBtn)
            this.VarValueBtn.OnEvent("Click", (*) => this.OnClickAddVarValueBtn())
        }

        ;指令写入的数组
        {
            PosX := 20
            PosY := FlagY
            this.WriteArrConArr := []
            this.WriteArrayTipCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 80, 20), GetLang("写入数组："))
            this.WriteArrConArr.Push(this.WriteArrayTipCon)
            PosX += 80
            this.WriteArrCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R10", PosX, PosY, 130), GetGuiArrNameArr())
            this.WriteArrConArr.Push(this.WriteArrCon)
        }

        PosY := FlagY + 110
        PosX := 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{} Center", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.Gui.Hide())
        MyGui.Show(Format("w{} h{}", 535, 400))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("文件读写")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLAllVarArr := GetGuiVarArr(1)
        this.DLVarArr := GetGuiVarArr(2)
        this.DLArrayArr := GetGuiArrNameArr()

        this.OperTypeCon.Text := GetLang(this.Data.OperType)
        this.EncodingCon.Text := GetShowEncoding(this.Data.Encoding)
        this.FilePathCon.Text := this.Data.FilePath
        this.ContentCon.Text := GetLangStr(this.Data.Content, 1)
        this.SaveTypeCon.Text := GetLang(this.Data.SaveType)
        this.SaveNameCon.Text := this.Data.SaveName

        ModeArr := this.OperModeMap[GetLang(this.Data.OperType)]
        SetDLConValue(this.OperModeCon, ModeArr, GetLang(this.Data.OperMode))
        SetDLConValue(this.TextRowVarCon, this.DLVarArr, this.Data.TextRowVar)
        SetDLConValue(this.NameOrSerialCon, this.DLVarArr, this.Data.NameOrSerial)
        SetDLConValue(this.RowCon, this.DLVarArr, this.Data.RowVar)
        SetDLConValue(this.ColCon, this.DLVarArr, this.Data.ColVar)
        SetDLConValue(this.RowEndCon, this.DLVarArr, this.Data.RowEndVar)
        SetDLConValue(this.ColEndCon, this.DLVarArr, this.Data.ColEndVar)
        SetDLConValue(this.WriteVarCon, this.DLAllVarArr, "")
        SetDLConValue(this.WriteArrCon, this.DLArrayArr, this.Data.ArrName)
    }

    OnRefreshType(*) {
        ModeArr := this.OperModeMap[this.OperTypeCon.Text]
        SetDLConValue(this.OperModeCon, ModeArr, this.OperModeCon.Text)
        this.RefreshConVisable()
    }

    OnRefreshOperMode(*) {
        this.RefreshConVisable()
    }

    RefreshConVisable() {
        CurType := this.OperTypeCon.Text
        CurMode := this.OperModeCon.Text
        IsRead := CurType == GetLang("读取Excel") || CurType == GetLang("读取文本文件")
        IsWrite := !IsRead
        IsExcel := CurType == GetLang("读取Excel") || CurType == GetLang("写入Excel")
        IsText := CurType == GetLang("读取文本文件") || CurType == GetLang("写入文本文件")

        IsExcelRange := IsExcel && (CurMode == GetLang("指定行") || CurMode == GetLang("指定列") || CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        IsTextRange := IsText && CurMode == GetLang("逐行读取")
        IsExcelResOnlyVar := IsRead && IsExcel && CurMode == GetLang("单元格")
        IsTextResOnlyVar := IsRead && IsText && (CurMode == GetLang("读取全部内容") || CurMode == GetLang("指定行"))
        IsResOnlyVar := IsExcelResOnlyVar || IsTextResOnlyVar

        HasEncoding := IsText
        HasTextRow := IsText && (CurMode == GetLang("指定行") || CurMode == GetLang("逐行读取") || CurMode == GetLang("行号自增"))
        HasExcel := IsExcel
        HasExcelRegion := IsRead && (CurMode == GetLang("指定区域-行") || CurMode == GetLang("指定区域-列"))
        HasRes := IsRead
        HasWriteArr := IsWrite && IsExcelRange
        HasWriteContent := IsWrite && !HasWriteArr

        this.SetConArrVisible(this.EncodingConArr, HasEncoding)
        this.SetConArrVisible(this.TextRowConArr, HasTextRow)
        this.SetConArrVisible(this.ExcelConArr, HasExcel)
        this.SetConArrVisible(this.RegionConArr, HasExcelRegion)
        this.SetConArrVisible(this.ResultConArr, HasRes)
        this.SetConArrVisible(this.WriteConArr, HasWriteContent)
        this.SetConArrVisible(this.WriteArrConArr, HasWriteArr)

        this.SaveTypeCon.Text := IsResOnlyVar ? GetLang("变量") : GetLang("数组")
        ResArr := IsResOnlyVar ? GetGuiVarArr() : this.DLArrayArr
        SetDLConValue(this.SaveNameCon, ResArr, this.SaveNameCon.Text)
    }

    SetConArrVisible(ConArr, Visible) {
        loop ConArr.Length {
            ConArr[A_Index].Visible := Visible
        }
    }

    OnSelectPathBtnClick() {
        CurType := this.OperTypeCon.Text
        IsExcel := CurType == GetLang("读取Excel") || CurType == GetLang("写入Excel")
        IsText := CurType == GetLang("读取文本文件") || CurType == GetLang("写入文本文件")
        SymbolStr := IsExcel ? "Excel Files(*.xlsx)" : ""
        SymbolStr := IsText ? "Text Files(*.txt)" : SymbolStr
    
        path := FileSelect(1, , GetLang("选择输入的源文件"), SymbolStr)
        this.FilePathCon.Value := path
    }

    OnRefreshContentVarType(*) {
        IsResVar := this.WriteVarTypeCon.Text == GetLang("变量")
        DLArr := IsResVar ? GetGuiVarArr(1) : GetGuiArrNameArr()
        SetDLConValue(this.WriteVarCon, DLArr, this.WriteVarCon.Text)
    }

    OnClickAddVarNameBtn() {
        this.ContentCon.Value .= this.WriteVarCon.Text
    }

    OnClickAddVarValueBtn() {
        ArraySymbol := this.WriteVarTypeCon.Text == GetLang("变量") ? "" : "ε"
        this.ContentCon.Value .= "{" ArraySymbol this.WriteVarCon.Text "}"
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this.Gui.Hide()
    }

    CheckIfValid() {
        if (this.FilePathCon.Text == "") {
            MsgBox("文件路径不能为空")
            return false
        }

        if (!CheckVarNameIfValid(this.SaveNameCon.Text))
            return false

        return true
    }

    TriggerMacro() {
        this.SaveData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)

        CurType := this.OperTypeCon.Text
        IsRead := CurType == GetLang("读取Excel") || CurType == GetLang("读取文本文件")
        if (IsRead) {
            Res := ""
            if (this.Data.SaveType == "变量" && MySoftData.VariableMap.Has(this.Data.SaveName))
                Res := MySoftData.VariableMap[this.Data.SaveName]
            if (this.Data.SaveType == "数组" && MySoftData.ArrayMap.Has(this.Data.SaveName))
                Res := GetArrayStr(MySoftData.ArrayMap[this.Data.SaveName])

            if (Res != "") {
                tip1 := Format(GetLang("变量：{}"), this.Data.SaveName)
                tip2 := Format(GetLang("值：{}"), Res)
                MsgBox(tip1 "`n" tip2)
            }
        }
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.RemarkCon.Value
        if (Remark == "") {
            Remark := this.OperTypeCon.Text
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveData() {
        this.Data.OperType := GetLangKey(this.OperTypeCon.Text)
        this.Data.Encoding := GetSoftEncoding(this.EncodingCon.Text)
        this.Data.FilePath := this.FilePathCon.Text
        this.Data.OperMode := GetLangKey(this.OperModeCon.Text)
        this.Data.TextRowVar := GetLangKey(this.TextRowVarCon.Text)
        this.Data.NameOrSerial := GetLangKey(this.NameOrSerialCon.Text)
        this.Data.RowVar := GetLangKey(this.RowCon.Text)
        this.Data.ColVar := GetLangKey(this.ColCon.Text)
        this.Data.RowEndVar := GetLangKey(this.RowEndCon.Text)
        this.Data.ColEndVar := GetLangKey(this.ColEndCon.Text)

        this.Data.Content := GetLangStr(this.ContentCon.Text, 2)
        this.Data.ArrName := this.WriteArrCon.Text

        this.Data.SaveType := GetLangKey(this.SaveTypeCon.Text)
        this.Data.SaveName := GetVarName(this.SaveNameCon.Text)

        if (this.SaveNameCon.Visible) {
            if (this.Data.SaveType == "变量")
                MySoftData.GlobalVariMap[this.Data.SaveName] := true
            if (this.Data.SaveType == "数组")
                MySoftData.GlobalArrMap[this.Data.SaveName] := true
        }
        SaveMacroCMDData(this.Data)
    }
}
