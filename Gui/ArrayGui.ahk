#Requires AutoHotkey v2.0

class ArrayGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
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
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("数组编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosX += 200
        this.IsIgnoreExistCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY - 5, 180), GetLang(
            "如果变量存在则不改变数据"))

        PosX := 20
        PosY += 40
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("类型："))

        PosX += 50
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLangArr(["创建", "克隆",
            "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"]))
        this.TypeCon.Value := 1
        this.TypeCon.OnEvent("Change", this.OnRefresh.Bind(this))

        PosX += 125
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("数组名："))
        PosX += 65
        this.NameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 100), [])

        PosX += 120
        this.MainIndexConArr := []
        Con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("子索引："))
        this.MainIndexConArr.Push(Con)
        PosX += 65
        this.MainIndexCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 90), ["0"])
        this.MainIndexConArr.Push(this.MainIndexCon)
        PosX += 95
        Con := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 7, 25), "?")
        Con.OnEvent("Click", this.OnClickIndexHelpBtn.Bind(this))
        this.MainIndexConArr.Push(Con)

        PosY += 35
        SplitPosY := PosY

        ;创建参数
        {
            PosX := 10
            PosY := SplitPosY
            this.CreateConArr := []
            Con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 550, 70), GetLang("创建参数"))
            this.CreateConArr.Push(Con)

            PosX := 20
            PosY += 30
            Con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("初始数据："))
            this.CreateConArr.Push(Con)
            PosX += 75
            this.InitArrCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 400), "1, 2, 3")
            this.CreateConArr.Push(this.InitArrCon)
            PosX += 405
            Con := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 7, 25), "?")
            Con.OnEvent("Click", this.OnClickInitHelpBtn.Bind(this))
            this.CreateConArr.Push(Con)
        }

        ;类型参数
        {
            PosX := 10
            PosY := SplitPosY
            this.ArgsConArr := []
            this.ArgsIndexConArr := []
            this.ArgsDataConArr := []
            Con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 550, 70), GetLang("类型参数"))
            this.ArgsConArr.Push(Con)

            PosX := 20
            PosY += 30
            Con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("索引："))
            this.ArgsConArr.Push(Con)
            this.ArgsIndexConArr.Push(Con)
            PosX += 50
            this.ArgsIndexCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 100), [0])
            this.ArgsConArr.Push(this.ArgsIndexCon)
            this.ArgsIndexConArr.Push(this.ArgsIndexCon)

            PosX += 125
            Con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 70, 20), GetLang("数据："))
            Con.GetPos(&x)
            Con.OriPosX := x
            this.ArgsConArr.Push(Con)
            this.ArgsDataConArr.Push(Con)
            PosX += 50
            this.ArgsTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLangArr([
                "变量或值",
                "数组"]))
            this.ArgsTypeCon.GetPos(&x)
            this.ArgsTypeCon.OriPosX := x
            this.ArgsTypeCon.OnEvent("Change", this.OnRefreshDataType.Bind(this))
            this.ArgsConArr.Push(this.ArgsTypeCon)
            this.ArgsDataConArr.Push(this.ArgsTypeCon)

            PosX += 105
            this.ArgsNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 100), [])
            this.ArgsNameCon.GetPos(&x)
            this.ArgsNameCon.OriPosX := x
            this.ArgsConArr.Push(this.ArgsNameCon)
            this.ArgsDataConArr.Push(this.ArgsNameCon)
        }

        ;结果
        {
            PosX := 20
            PosY := 170
            this.ResultConArr := []
            Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("结果："))
            this.ResultConArr.Push(Con)

            PosX += 50
            this.SaveTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLangArr(["变量",
                "数组"]))
            this.SaveTypeCon.OnEvent("Change", this.OnRefreshDataType.Bind(this))
            this.ResultConArr.Push(this.SaveTypeCon)

            PosX += 105
            this.SaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 130), [])
            this.ResultConArr.Push(this.SaveNameCon)
        }

        PosY := 200
        PosX := 240
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 580, 250))
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
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("数组")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        this.DLArrayArr := GetGuiArrNameArr()

        this.TypeCon.Text := GetLang(this.Data.Type)
        this.IsIgnoreExistCon.Value := this.Data.IsIgnoreExist
        SetDLConValue(this.NameCon, this.DLArrayArr, this.Data.Name)
        SetDLConValue(this.MainIndexCon, GetGuiVarArr(2), this.Data.MainIndex)
        this.InitArrCon.Text := GetArrayStr(this.Data.InitArr)

        SetDLConValue(this.ArgsIndexCon, GetGuiVarArr(2), this.Data.ArgsIndex)
        this.ArgsTypeCon.Text := GetLang(this.Data.ArgsType)
        this.ArgsNameCon.Text := this.Data.ArgsName

        this.SaveTypeCon.Text := GetLang(this.Data.SaveType)
        this.SaveNameCon.Text := this.Data.SaveName
    }

    OnRefresh(*) {
        IsCreate := this.TypeCon.Text == GetLang("创建")
        IsClone := this.TypeCon.Text == GetLang("克隆")
        IsDelete := this.TypeCon.Text == GetLang("删除")
        IsContain := this.TypeCon.Text == GetLang("包含")
        IsGet := this.TypeCon.Text == GetLang("取值")
        IsSetValue := this.TypeCon.Text == GetLang("赋值")
        IsInsert := this.TypeCon.Text == GetLang("插入")
        IsAdd := this.TypeCon.Text == GetLang("追加")
        IsRemove := this.TypeCon.Text == GetLang("移除")
        IsRemoveLast := this.TypeCon.Text == GetLang("移除最后")
        IsReverse := this.TypeCon.Text == GetLang("反转")
        IsLength := this.TypeCon.Text == GetLang("长度")
        OnlyResVar := IsLength || IsContain
        OnlyResArr := IsClone || IsReverse
        OnlyArgsIndex := IsGet || IsRemove
        OnlyArgsData := IsAdd || IsContain
        IsShowRusult := IsGet || IsLength || IsClone || IsRemove || IsRemoveLast || IsContain || IsReverse
        IsShowMainIndex := !IsCreate && !IsDelete
        IsShowArgs := IsGet || IsSetValue || IsInsert || IsAdd || IsRemove || IsContain

        this.IsIgnoreExistCon.Visible := IsCreate || IsClone || IsGet || IsLength || IsRemove || IsRemoveLast ||
            IsContain
        this.SetConArrVisible(this.MainIndexConArr, IsShowMainIndex)
        this.SetConArrVisible(this.ResultConArr, IsShowRusult)
        this.SetConArrVisible(this.CreateConArr, IsCreate)
        this.OnRefreshArgs(IsShowArgs, OnlyArgsIndex, OnlyArgsData)

        if (OnlyResVar || OnlyResArr) {
            this.SaveTypeCon.Value := OnlyResVar ? 1 : 2
            this.SaveTypeCon.Enabled := false
        }
        else {
            this.SaveTypeCon.Enabled := true
        }
        this.OnRefreshDataType()
    }

    SetConArrVisible(ConArr, isVisible) {
        loop ConArr.Length {
            ConArr[A_Index].Visible := isVisible
        }
    }

    OnRefreshArgs(IsShow, OnlyIndex, OnlyData) {
        this.SetConArrVisible(this.ArgsConArr, IsShow)
        if (!IsShow)
            return
        if (OnlyIndex) {
            this.SetConArrVisible(this.ArgsIndexConArr, true)
            this.SetConArrVisible(this.ArgsDataConArr, false)
        }
        else if (OnlyData) {
            this.SetConArrVisible(this.ArgsIndexConArr, false)
            this.SetConArrVisible(this.ArgsDataConArr, true)
            loop this.ArgsDataConArr.Length {
                Con := this.ArgsDataConArr[A_Index]
                Con.Move(Con.OriPosX - 175)
            }
        }
        else {
            this.SetConArrVisible(this.ArgsIndexConArr, true)
            this.SetConArrVisible(this.ArgsDataConArr, true)
            loop this.ArgsDataConArr.Length {
                Con := this.ArgsDataConArr[A_Index]
                Con.Move(Con.OriPosX)
            }
        }
    }

    OnRefreshDataType(*) {
        IsArgsVar := this.ArgsTypeCon.Text == GetLang("变量或值")
        IsResVar := this.SaveTypeCon.Text == GetLang("变量")
        ArgsArr := IsArgsVar ? this.DLVariableArr : this.DLArrayArr
        ResArr := IsResVar ? GetGuiVarArr(0) : this.DLArrayArr
        SetDLConValue(this.ArgsNameCon, ArgsArr, this.ArgsNameCon.Text)
        SetDLConValue(this.SaveNameCon, ResArr, this.SaveNameCon.Text)
    }

    OnClickIndexHelpBtn(*) {
        str1 := GetLang("数组支持二维，该参数可控制数组或子数组进行调度")
        str2 := GetLang("一维数组时，保持默认值0即可")
        str3 := GetLang("0. 数组本身")
        str4 := GetLang("N. 对应索引的子数组")
        MsgBox(Format("{}`n{}`n{}`n{}", str1, str2, str3, str4))
    }

    OnClickInitHelpBtn(*) {
        str1 := GetLang("1. 逗号分割数据")
        str2 := GetLang("案例数据：1,2,文本,4")
        str3 := GetLang('数组-1→1、数组-2→2、数组-3→"文本"、数组-4→4')
        str4 := GetLang("2. 中括号表示数组数据")
        str5 := GetLang('案例数据：1,"文本",[2, 5, 7],8')
        str6 := GetLang('数组-1→1、数组-2→"文本"、数组-3→2, 5, 7、数组-4→8')
        str7 := GetLang("3. 数据中使用\符号，表示原本的功能")
        str8 := GetLang("案例数据1,我的\,世界,\[若梦兔\],4")
        str9 := GetLang('数组-1→1、数组-2→"我的,世界"、数组-3→"[若梦兔]"、数组-4→4')
        MsgBox(Format("{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6, str7, str8, str9))
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSubMacroData()
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
        if (!CheckVarNameIfValid(this.SaveNameCon.Text))
            return false
        return true
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        Remark := this.RemarkCon.Value
        if (Remark == "") {
            switch this.Data.Type {
                case "创建":
                    Remark := Format(GetLang("创建{}"), this.Data.Name)
                case "克隆":
                    Remark := Format(GetLang("克隆{}到{}"), this.Data.Name, this.Data.SaveName)
                case "删除":
                    Remark := Format(GetLang("删除{}"), this.Data.Name)
                case "包含":
                    tip1 := Format(GetLang("{}包含数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}包含数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "取值":
                    tip1 := Format(GetLang("取值{}-{}到{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.SaveName)
                    tip2 := Format(GetLang("取值{}-{}-{}到{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex,
                    this.Data
                    .SaveName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "赋值":
                    tip1 := Format(GetLang("{}-{}赋值为{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}赋值为{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex,
                    this.Data
                    .ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "插入":
                    tip1 := Format(GetLang("{}-{}插入数据{}"), this.Data.Name, this.Data.ArgsIndex, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}-{}插入数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex,
                    this.Data
                    .ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "追加":
                    tip1 := Format(GetLang("{}追加数据{}"), this.Data.Name, this.Data.ArgsName)
                    tip2 := Format(GetLang("{}-{}追加数据{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsName)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除":
                    tip1 := Format(GetLang("移除{}-{}"), this.Data.Name, this.Data.ArgsIndex)
                    tip2 := Format(GetLang("移除{}-{}-{}"), this.Data.Name, this.Data.MainIndex, this.Data.ArgsIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "移除最后":
                    tip1 := Format(GetLang("移除{}-最后数据"), this.Data.Name)
                    tip2 := Format(GetLang("移除{}-{}最后数据"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
                case "长度":
                    tip1 := Format(GetLang("{}长度"), this.Data.Name)
                    tip2 := Format(GetLang("{}-{}长度"), this.Data.Name, this.Data.MainIndex)
                    Remark := this.Data.MainIndex == 0 ? tip1 : tip2
            }
        }
        CommandStr := CorrectRemark(CommandStr, Remark)
        return CommandStr
    }

    SaveSubMacroData() {
        this.Data.IsIgnoreExist := this.IsIgnoreExistCon.Value
        this.Data.Type := GetLangKey(this.TypeCon.Text)
        this.Data.Name := this.NameCon.Text
        this.Data.InitArr := GetArray(this.InitArrCon.Text)
        this.Data.MainIndex := GetLangKey(this.MainIndexCon.Text)
        this.Data.ArgsIndex := GetLangKey(this.ArgsIndexCon.Text)
        this.Data.ArgsType := GetLangKey(this.ArgsTypeCon.Text)
        this.Data.ArgsName := GetLangKey(this.ArgsNameCon.Text)
        this.Data.SaveType := GetLangKey(this.SaveTypeCon.Text)
        this.Data.SaveName := GetVarName(this.SaveNameCon.Text)
        SetArrayDataNewArr(this.Data)
        SetArrayDataNewVar(this.Data)
        SaveMacroCMDData(this.Data)
    }
}
