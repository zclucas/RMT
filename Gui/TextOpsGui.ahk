#Requires AutoHotkey v2.0

class TextOpsGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.RemarkCon := ""
        this.ArgsNameOptions := []
        this.lastArgsNameConText := ""

        this.ArgsTypeMap := Map(
            GetLang("去除空格"), [
                GetLang("去除前空白字符"),
                GetLang("去除后空白字符"),
                GetLang("去除前后空白字符"),
                GetLang("去除所有空白字符")
            ],
            GetLang("大小写转换"), [
                GetLang("全部大写"),
                GetLang("全部小写"),
                GetLang("首字母大写"),
            ],
            GetLang("文本统计"), [
                GetLang("字符数"),
                GetLang("单词数"),
                GetLang("行数"),
            ],
            GetLang("文本提取"), [
                GetLang("数字提取"),
                GetLang("字母提取"),
                GetLang("中文提取"),
            ],
            GetLang("文本分割"), [
                GetLang("内容分割"),
                GetLang("定长分割"),
            ],
            GetLang("文本拼接"), [
                GetLang("拼接文本"),
            ])

        this.ArgsTipMap := Map(
            GetLang("内容分割"), GetLang("分割文本："),
            GetLang("定长分割"), GetLang("分割长度："),
            GetLang("拼接文本"), GetLang("拼接内容："))
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        this.Init(cmd)
        this.OnRefresh()
        this.lastArgsNameConText := ""
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("文本处理编辑器"))
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
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY - 3, 75), GetLang("处理类型:"))
        PosX += 75
        TypeArr := GetLangArr(["文本分割", "文本提取", "文本替换", "去除空格", "大小写转换", "文本统计", "文本拼接"])
        this.TypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 150), TypeArr)
        this.TypeCon.OnEvent("Change", this.OnRefresh.Bind(this))

        PosX := 275
        this.NameConTip := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY - 3, 75), GetLang("文本来源:"))
        PosX += 75
        this.NameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 150), [])

        PosY += 30
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 510, 100), GetLang("处理参数"))

        ; 第一行：类型选项   类型参数
        PosY += 30
        PosX := 20
        this.ArgsTypeConTip := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("类型选项:"))
        PosX += 75
        this.ArgsTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 150), [])
        this.ArgsTypeCon.OnEvent("Change", this.OnRefreshArgsType.Bind(this))

        PosX := 275
        this.ArgsNameConTip := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("类型参数:"))
        PosX += 75
        this.ArgsNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 150), [])
        this.ArgsNameCon.OnEvent("Change", this.OnArgsNameConChange.Bind(this))

        PosY += 35
        PosX := 20
        this.ReplaceConArr := []
        Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("查找文本:"))
        this.ReplaceConArr.Push(Con)
        PosX += 75
        this.SearchCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 150), [])
        this.ReplaceConArr.Push(this.SearchCon)

        PosX := 275
        Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("替换文本:"))
        this.ReplaceConArr.Push(Con)
        PosX += 75
        this.ReplaceCon := MyGui.Add("ComboBox", Format("x{} y{} w{}", PosX, PosY - 5, 150), [])
        this.ReplaceConArr.Push(this.ReplaceCon)

        ;结果
        {
            PosX := 10
            PosY += 45
            MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 510, 70), GetLang("结果保存"))

            PosX := 20
            PosY += 30
            this.ResultConArr := []
            Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("结果："))
            this.ResultConArr.Push(Con)

            PosX += 50
            this.SaveTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 5, 100), GetLangArr(["变量",
                "数组"]))
            this.SaveTypeCon.OnEvent("Change", this.OnRefreshDataType.Bind(this))
            this.SaveTypeCon.Enabled := false
            this.ResultConArr.Push(this.SaveTypeCon)

            PosX += 105
            this.SaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R8", PosX, PosY - 5, 130), [])
            this.ResultConArr.Push(this.SaveNameCon)
        }

        PosY += 50
        PosX := 210
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{} Center", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.Gui.Hide())
        MyGui.Show(Format("w{} h{}", 535, 320))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("文本处理")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLArrayArr := GetGuiArrNameArr()
        ArgsNameArr := GetGuiVarArr(2)
        ArgsNameArr.InsertAt(1, GetLang("制表符"))
        this.ArgsNameOptions := ArgsNameArr.Clone()

        this.TypeCon.Text := GetLang(this.Data.Type)
        SetDLConValue(this.NameCon, GetGuiVarArr(), this.Data.Name)
        SetDLConValue(this.ArgsNameCon, ArgsNameArr, this.Data.ArgsName)
        this.lastArgsNameConText := this.ArgsNameCon.Text

        SetDLConValue(this.SearchCon, GetGuiVarArr(2), this.Data.Search)
        SetDLConValue(this.ReplaceCon, GetGuiVarArr(2), this.Data.Replace)

        this.SaveTypeCon.Text := GetLang(this.Data.SaveType)
        this.SaveNameCon.Text := this.Data.SaveName
    }

    OnRefresh(*) {
        IsSplit := this.TypeCon.Text == GetLang("文本分割")
        IsReplace := this.TypeCon.Text == GetLang("文本替换")
        IsGetEx := this.TypeCon.Text == GetLang("文本提取")
        IsSpace := this.TypeCon.Text == GetLang("去除空格")
        IsUpLow := this.TypeCon.Text == GetLang("大小写转换")
        IsStatistics := this.TypeCon.Text == GetLang("文本统计")
        IsConcat := this.TypeCon.Text == GetLang("文本拼接")

        ArgsDLArr := []
        this.ArgsTypeCon.Delete()
        if (this.ArgsTypeMap.Has(this.TypeCon.Text)) {
            ArgsDLArr := this.ArgsTypeMap[this.TypeCon.Text]
            this.ArgsTypeCon.Add(ArgsDLArr)
            this.ArgsTypeCon.Value := 1

            loop ArgsDLArr.Length {
                if (ArgsDLArr[A_Index] == GetLang(this.Data.ArgsType)) {
                    this.ArgsTypeCon.Text := GetLang(this.Data.ArgsType)
                    break
                }
            }
        }

        ShowArgsType := IsSplit || IsGetEx || IsUpLow || IsSpace || IsStatistics || IsConcat
        ShowArgsName := IsSplit || IsConcat
        this.ArgsTypeConTip.Enabled := ShowArgsType
        this.ArgsTypeCon.Enabled := ShowArgsType
        this.ArgsNameConTip.Enabled := ShowArgsName
        this.ArgsNameCon.Enabled := ShowArgsName
        loop this.ReplaceConArr.Length {
            this.ReplaceConArr[A_Index].Enabled := IsReplace
        }

        this.NameConTip.Enabled := !IsConcat
        this.NameCon.Enabled := !IsConcat

        OnlyResVar := IsReplace || IsSpace || IsUpLow || IsStatistics || IsConcat
        OnlyResArr := IsSplit || IsGetEx
        this.SaveTypeCon.Value := OnlyResVar ? 1 : 2
        this.OnRefreshArgsType()
        this.OnRefreshDataType()
    }

    OnRefreshArgsType(*) {
        tipText := GetLang("类型参数:")
        if (this.ArgsTipMap.Has(this.ArgsTypeCon.Text))
            tipText := this.ArgsTipMap[this.ArgsTypeCon.Text]
        this.ArgsNameConTip.Text := tipText
        this.lastArgsNameConText := this.ArgsNameCon.Text
    }

    OnRefreshDataType(*) {
        IsResVar := this.SaveTypeCon.Text == GetLang("变量")
        ResArr := IsResVar ? GetGuiVarArr() : this.DLArrayArr
        SetDLConValue(this.SaveNameCon, ResArr, this.SaveNameCon.Text)
        this.lastArgsNameConText := this.ArgsNameCon.Text
    }

    OnArgsNameConChange(*) {
        IsConcat := this.TypeCon.Text == GetLang("文本拼接")
        if (!IsConcat) {
            this.lastArgsNameConText := this.ArgsNameCon.Text
            return
        }
        
        newText := this.ArgsNameCon.Text
        if (newText == "") {
            this.lastArgsNameConText := ""
            return
        }
        
        isFromDropdown := false
        if (this.ArgsNameOptions != "") {
            loop this.ArgsNameOptions.Length {
                if (this.ArgsNameOptions[A_Index] == newText) {
                    isFromDropdown := true
                    break
                }
            }
        }
        
        if (isFromDropdown && this.lastArgsNameConText != "" && newText != this.lastArgsNameConText) {
            this.ArgsNameCon.Text := this.lastArgsNameConText "{" newText "}"
        }
        else if (isFromDropdown && (this.lastArgsNameConText == "" || newText == this.lastArgsNameConText)) {
            this.ArgsNameCon.Text := "{" newText "}"
        }
        this.lastArgsNameConText := this.ArgsNameCon.Text
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveTextOpsData()
        CommandStr := this.GetCommandStr()
        action := this.SureBtnAction
        action(CommandStr)
        this.Gui.Hide()
    }

    CheckIfValid() {
        if (this.TypeCon.Text == GetLang("文本替换")) {
            if (this.SearchCon.Text == "" || this.ReplaceCon.Text == "") {
                MsgBox(GetLang("搜索文本和替换文本不能为空"))
                return false
            }
        }

        if (this.TypeCon.Text == GetLang("文本分割")) {
            if (this.ArgsNameCon.Text == "") {
                MsgBox(GetLang("类型参数不能为空"))
                return false
            }
        }

        if (!CheckVarNameIfValid(this.SaveNameCon.Text))
            return false

        return true
    }

    TriggerMacro() {
        this.SaveTextOpsData()
        CommandStr := this.GetCommandStr()
        OnTriggerSepcialItemMacro(CommandStr)

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

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    SaveTextOpsData() {
        ;edit没法直接输入制表符，增加一个特定的变量代表
        ArgsName := GetLangKey(this.ArgsNameCon.Text)
        ArgsName := ArgsName == "制表符" ? "`t" : ArgsName

        this.Data.Type := GetLangKey(this.TypeCon.Text)
        this.Data.Name := this.NameCon.Text
        this.Data.ArgsType := GetLangKey(this.ArgsTypeCon.Text)
        this.Data.ArgsName := ArgsName
        this.Data.Search := GetLangKey(this.SearchCon.Text)
        this.Data.Replace := GetLangKey(this.ReplaceCon.Text)
        this.Data.SaveType := GetLangKey(this.SaveTypeCon.Text)
        this.Data.SaveName := GetVarName(this.SaveNameCon.Text)

        if (this.Data.SaveType == "变量")
            MySoftData.GlobalVariMap[this.Data.SaveName] := true
        if (this.Data.SaveType == "数组")
            MySoftData.GlobalArrMap[this.Data.SaveName] := true
        SaveMacroCMDData(this.Data)
    }
}
