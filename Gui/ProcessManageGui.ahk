#Requires AutoHotkey v2.0

class ProcessManageGui extends CommentGui {
    static CmdKey := "进程管理"
    static Outputs := [
        ["ResultVar", "保存结果变量："], ["CountVar", "匹配数量变量："],
        ["NameVar", "进程名变量："], ["PidVar", "PID 变量："], ["PathVar", "程序路径变量："],
        ["ResultArray", "数组名："], ["ErrorVar", "错误信息变量："]]

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(ProcessManageGui.CmdKey)
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._TextField(body, "备注：", "Remark")
        this._Choice(body, "操作：", "Action", ProcessManage.Actions)
        this._Choice(body, "匹配方式：", "MatchBy", ProcessManage.MatchModes)
        this._TextField(body, "目标：", "Target").ToolTip(GetLang("输入进程名或 PID，支持 {变量}。列出进程时可留空。"))

        row := CmdEditorForm.Row(body, "")
        row.Add("CheckBox").Name("EndAll").Grid_Column(1).Content(GetLang("结束全部匹配项")).VerticalAlignment("Center")
        this._ShowFor(row, [3], true)
        for output in ProcessManageGui.Outputs {
            field := output[1]
            row := CmdEditorForm.Row(body, output[2])
            combo := CmdEditorForm.Combo(row, field, true).Grid_Column(1)
            switch field {
                case "ResultVar":
                    combo.ToolTip(GetLang("检测返回 1 或 0，结束返回成功提交的结束请求数。"))
                    this._ShowFor(row, [0, 3])
                case "ResultArray":
                    combo.ToolTip(GetLang("数组每项为 [进程名, PID, 程序路径]。"))
                    this._ShowFor(row, [2])
                case "ErrorVar":
                    combo.ToolTip(GetLang("无错误时为空。留空则按宏的错误处理方式报告错误。"))
                default:
                    this._ShowFor(row, [1])
            }
        }
        CmdEditorForm.Footer(body)

        template := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(template, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' this._EscapeXml(title) '" Width="560" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"',
            'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        BindCmdEditorChrome(this.ui, "#指令手册/41-进程")
    }

    _TextField(body, label, name) {
        row := CmdEditorForm.Row(body, label)
        return row.Add("TextBox").Name(name).Grid_Column(1).Height(26).MinHeight(26)
            .Style("{StaticResource RmtSingleLineTextBox}")
    }

    _Choice(body, label, name, choices) {
        combo := CmdEditorForm.Combo(CmdEditorForm.Row(body, label), name).Grid_Column(1)
        for choice in choices
            combo.Add("ComboBoxItem").Content(GetLang(choice))
    }

    _ShowFor(row, indices, byName := false) {
        style := row.Add("Grid.Style").Add("Style").TargetType("Grid")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        triggers := style.Add("Style.Triggers")
        for index in indices {
            trigger := triggers.Add("MultiDataTrigger")
            conditions := trigger.Add("MultiDataTrigger.Conditions")
            conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=Action}").Value(index)
            if (byName)
                conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=MatchBy}").Value(0)
            trigger.Add("Setter").Property("Visibility").Value("Visible")
        }
    }

    Init(cmd) {
        parts := cmd == "" ? [] : SplitCommand(cmd)
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr(ProcessManageGui.CmdKey)
        this.Data := GetMacroCMDData(this.SerialStr)
        this.SerialStr := this.Data.SerialStr
        this._ComboPush("Action", "SelectedIndex", CmdEnumIndex(this.Data.Action, ProcessManage.Actions))
        this._ComboPush("MatchBy", "SelectedIndex", CmdEnumIndex(this.Data.MatchBy, ProcessManage.MatchModes))
        this._ComboPush("Target", "Text", this.Data.Target)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        this._ComboPush("EndAll", "IsChecked", this.Data.EndAll ? "True" : "False")
        vars := GetGuiVarArr()
        arrays := GetGuiArrNameArr()
        for output in ProcessManageGui.Outputs {
            field := output[1]
            for name in (field == "ResultArray" ? arrays : vars)
                this._ComboPush(field, "AddItem", name)
            this._ComboPush(field, "Text", this.Data.%field%)
        }
    }

    CheckIfValid() {
        try {
            state := this.ui.Query("Action", "MatchBy", "Target", "Remark", "EndAll",
                "ResultVar", "CountVar", "NameVar", "PidVar", "PathVar", "ResultArray", "ErrorVar")
            data := ProcessManageData()
            data.SerialStr := this.SerialStr
            data.Action := CmdEnumZh(state["Action"], ProcessManage.Actions)
            data.MatchBy := CmdEnumZh(state["MatchBy"], ProcessManage.MatchModes)
            data.Target := Trim(state["Target"])
            checked := state["EndAll"]
            data.EndAll := data.Action == "结束进程" && data.MatchBy == "进程名" && (checked = "True" || checked = "1")
            ProcessManage.ValidateTarget(data, data.Target, true)

            fields := ProcessManage.OutputFields(data.Action)
            if (data.Action == "列出进程")
                fields.Push("ResultArray")
            saved := Map()
            for field in fields {
                name := Trim(state[field])
                if (name != "" && !this._AddOutput(data, field, name, saved))
                    return false
            }
            if (!saved.Count && data.ResultArray == "" && data.Action != "结束进程")
                throw ValueError(GetLang("请填写至少一个结果保存名称。"))
            errorVar := Trim(state["ErrorVar"])
            if (errorVar != "" && !this._AddOutput(data, "ErrorVar", errorVar, saved))
                return false
            this.Data := data
            this._remark := state["Remark"]
            return true
        } catch as e {
            RmtDialog.Info(e.Message, GetLang(ProcessManageGui.CmdKey), this.Hwnd())
            return false
        }
    }

    _AddOutput(data, field, name, saved) {
        if (field != "ResultArray")
            name := GetVarName(name)
        if (!CheckVarNameIfValid(name))
            return false
        if (field != "ResultArray") {
            if (saved.Has(name))
                throw ValueError(GetLang("结果变量名不能重复。"))
            saved[name] := true
        }
        data.%field% := name
        return true
    }

    SaveData() {
        ProcessManage.RegisterOutputs(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang(ProcessManageGui.CmdKey) RegExReplace(this.SerialStr, "\D+"), this._remark)
    }
}
