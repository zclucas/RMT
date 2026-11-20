#Requires AutoHotkey v2.0

class ProcessManageGui extends CommentGui {
    static CmdKey := "进程管理"
    static Outputs := ["ResultVar", "NameVar", "PidVar", "PathVar", "ResultArray", "ExistVar", ProcessInfo.Metrics*]
    static OutputDefaults := Map("ResultVar", "Res", "NameVar", "Name", "PidVar", "PID", "PathVar", "Path")
    static MetricRows := [
        [["ExistVar", "是否存在：", "存在：1，不存在：0。"], ["StatusVar", "状态：", "正常、无响应、阻塞、加载或挂起。"]],
        [["StartTimeVar", "启动时间：", "本地时间，格式为 yyyy-MM-dd HH:mm:ss。"], ["UptimeVar", "运行时长：", "从进程启动到查询时的秒数。"]],
        [["CpuVar", "CPU 占用：", "短时采样，占全部逻辑处理器的百分比。"], ["GpuVar", "GPU 占用：", "进程最忙的 GPU 引擎占用率（%）。"]],
        [["IntegrityVar", "权限级别：", "Windows 访问令牌的完整性级别。"]]]
    WindowBindingContext := ""
    _pickKeys := []
    _picking := false

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(ProcessManageGui.CmdKey)
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        chrome := XAMLHost.AddCmdTitleBar(main, title, height)
        chrome.F1.ToolTip(StrReplace(GetLang("F1:确定信息"), "F1:", "F1："))
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12")
        row := this._Pair(body)
        this._Choice(row, "操作：", "Action", ProcessManage.Actions)
        this._TextField(row, "备注：", "Remark", true)

        row := this._Pair(body)
        this._Choice(row, "匹配方式：", "MatchBy", ProcessManage.MatchModes)
        this._TargetField(row)

        tip := GetLang("成功：1、失败：0")
        row := this._Pair(body)
        this._Output(row, "ResultVar", "结果变量：", false, tip)
        this._ShowFor(row, [0, 3])

        row := body.Add("Grid").Margin("0,4")
        row.Add("CheckBox").Name("EndAll").Content(GetLang("结束全部匹配项")).VerticalAlignment("Center")
        this._ShowFor(row, [3], [0, 1, 3])

        row := this._Pair(body)
        pick := this._Choice(row, "选取方式：", "PickMatch", ProcessManage.MatchPicks)
        pick.Name("ProcessPickRow")
        this._Output(row, "NameVar", "进程名：", true)
        this._ShowFor(row, [1])
        row := this._Pair(body)
        this._Output(row, "PidVar", "PID：")
        this._Output(row, "PathVar", "程序路径：", true)
        this._ShowFor(row, [1])
        for fields in ProcessManageGui.MetricRows {
            row := this._Pair(body)
            for i, field in fields
                this._Output(row, field[1], field[2], i == 2, GetLang(field[3]))
            this._ShowFor(row, [1])
        }
        row := this._Output(body, "ResultArray", "数组名：", false, GetLang("数组每项为 [进程名, PID, 程序路径]。"))
        this._ShowFor(row, [2])
        CmdEditorForm.Footer(body)

        template := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(template, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' this._EscapeXml(title) '" Width="680" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"',
            'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnCmdF1", "Click", XamlWin.BindCurrent(this, "_ToggleWindowPick"))
        this.ui.OnEvent("BtnEditProcessWindow", "Click", XamlWin.BindCurrent(this, "_EditWindowBinding"))
        this.ui.OnEvent("MatchBy", "SelectionChanged", XamlWin.BindCurrent(this, "_OnMatchByChanged"))
        BindCmdEditorChrome(this.ui, "#指令手册/41-进程", XamlWin.BindCurrent(this, "Preview"), "")
    }

    _Pair(body) => body.Add("Grid").Cols("*", "16", "*")

    _FieldRow(body, label, right, tip := "") {
        labelWidth := 6 * XAMLHost.ScaleFontSize(XAMLHost.FontSize())
        row := body.Add("Grid").Grid_Column(right ? 2 : 0).Margin("0,4").Cols(labelWidth, "*")
        caption := CmdEditorForm.Label(row, label).Margin("0").TextTrimming("CharacterEllipsis")
        if (tip != "")
            caption.ToolTip(tip)
        return row
    }

    _TextField(body, label, name, right := false, tip := "") {
        row := this._FieldRow(body, label, right, tip)
        row.Add("TextBox").Name(name).Grid_Column(1).Height(26).MinHeight(26)
            .Style("{StaticResource RmtSingleLineTextBox}")
            .Background("{DynamicResource InputBg}")
        return row
    }

    _Choice(body, label, name, choices, right := false) {
        row := this._FieldRow(body, label, right)
        combo := CmdEditorForm.Combo(row, name).Grid_Column(1)
        for choice in choices
            combo.Add("ComboBoxItem").Content(GetLang(choice))
        return row
    }

    _TargetField(body) {
        row := this._FieldRow(body, "目标：", true, GetLang("按匹配方式输入进程名、PID 或正则，支持 {变量}。"))
            .Name("ProcessTargetRow")
        CmdEditorForm.Combo(row, "Target", true).Grid_Column(1)
        hint := row.Add("TextBlock").Name("TargetPidHint").Grid_Column(1).Text(GetLang("请输入进程PID"))
            .Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("8,0,24,0")
            .TextTrimming("CharacterEllipsis").IsHitTestVisible("False")
        style := hint.Add("TextBlock.Style").Add("Style").TargetType("TextBlock")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        trigger := style.Add("Style.Triggers").Add("MultiDataTrigger")
        conditions := trigger.Add("MultiDataTrigger.Conditions")
        conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=MatchBy}").Value(CmdEnumIndex("PID", ProcessManage.MatchModes))
        conditions.Add("Condition").Binding("{Binding Text, ElementName=Target}").Value("")
        trigger.Add("Setter").Property("Visibility").Value("Visible")

        row := this._FieldRow(body, "窗口绑定：", true, GetLang("指定这条指令要操作的窗口。")).Name("ProcessWindowRow")
        binding := row.Add("Grid").Grid_Column(1).Cols("*", 6, 28)
        CmdEditorForm.WindowBindingCombo(binding, "ProcessWindowBinding").MaxHeight(26)
        CmdEditorForm.IconButton(binding, "BtnEditProcessWindow", 0xE70F, "编辑").Grid_Column(2)
    }

    _Output(body, name, label, right := false, tip := "") {
        row := this._FieldRow(body, label, right, tip)
        combo := CmdEditorForm.Combo(row, name, true).Grid_Column(1)
        if (tip != "")
            combo.ToolTip(tip)
        return row
    }

    _ShowFor(row, indices, matchIndices := [""]) {
        style := row.Add("Grid.Style").Add("Style").TargetType("Grid")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        triggers := style.Add("Style.Triggers")
        for index in indices {
            for matchIndex in matchIndices {
                trigger := triggers.Add("MultiDataTrigger")
                conditions := trigger.Add("MultiDataTrigger.Conditions")
                conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=Action}").Value(index)
                if (matchIndex != "")
                    conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=MatchBy}").Value(matchIndex)
                trigger.Add("Setter").Property("Visibility").Value("Visible")
            }
        }
    }

    Init(cmd) {
        parts := cmd == "" ? [] : SplitCommand(cmd)
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr(ProcessManageGui.CmdKey)
        this.Data := GetMacroCMDData(this.SerialStr)
        this.SerialStr := this.Data.SerialStr
        this._matchMode := this.Data.MatchBy
        this._targets := Map(this._matchMode, parts.Length ? this.Data.Target : "notepad.exe")
        action := ProcessManage.ActionKey(this.Data.Action)
        this._ComboPush("Action", "SelectedIndex", CmdEnumIndex(action, ProcessManage.Actions))
        this._ComboPush("MatchBy", "SelectedIndex", CmdEnumIndex(this._matchMode, ProcessManage.MatchModes))
        this._ComboPush("PickMatch", "SelectedIndex", CmdEnumIndex(this.Data.HasProp("PickMatch") ? this.Data.PickMatch : "首个", ProcessManage.MatchPicks))
        this._FillTargets()
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        this._ComboPush("EndAll", "IsChecked", this.Data.EndAll ? "True" : "False")
        vars := GetGuiVarArr()
        arrays := GetGuiArrNameArr()
        for field in ProcessManageGui.Outputs {
            for name in (field == "ResultArray" ? arrays : vars)
                this._ComboPush(field, "AddItem", name)
            value := parts.Length && this.Data.HasProp(field) ? this.Data.%field% : ""
            if (!parts.Length || (action != "进程信息" && (field == "NameVar" || field == "PidVar" || field == "PathVar") && value == ""))
                value := ProcessManageGui.OutputDefaults.Get(field, "")
            this._ComboPush(field, "Text", value)
        }
    }

    _FillTargets() {
        isBinding := this._matchMode == "窗口绑定"
        this._ComboPush("ProcessTargetRow", "Visibility", isBinding ? "Collapsed" : "Visible")
        this._ComboPush("ProcessWindowRow", "Visibility", isBinding ? "Visible" : "Collapsed")
        this._ComboPush("ProcessPickRow", "Visibility", this._matchMode == "PID" ? "Collapsed" : "Visible")
        if (isBinding) {
            this._ComboPush("ProcessWindowBinding", "Text", this._targets.Get(this._matchMode, "❖{句柄ID}"))
            return
        }
        this._ComboPush("Target", "ClearItems", "")
        if (this._matchMode != "正则匹配") {
            names := Map()
            names.CaseSense := false
            try {
                for process in ProcessManage.Find("进程名", "") {
                    value := this._matchMode == "PID" ? String(process.Pid) : process.Name
                    names[value] := true
                }
            }
            items := ""
            for value in names
                items .= value "`n"
            for value in StrSplit(Sort(RTrim(items, "`n"), this._matchMode == "PID" ? "N" : ""), "`n") {
                if (value != "")
                    this._ComboPush("Target", "AddItem", value)
            }
        }
        for reference in GetGuiVarReferences()
            this._ComboPush("Target", "AddItem", reference)
        this._ComboPush("Target", "Text", this._targets.Get(this._matchMode, ""))
    }

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        this._RefreshWindowPick()
    }

    _OnMatchByChanged(*) {
        if (!this.Hwnd())
            return
        state := this.ui.Query("MatchBy", "Target", "ProcessWindowBinding")
        if (state["MatchBy"] == "")
            return
        mode := CmdEnumZh(state["MatchBy"], ProcessManage.MatchModes)
        if (mode == this._matchMode)
            return
        this._StopWindowPick()
        this._targets[this._matchMode] := state[this._matchMode == "窗口绑定" ? "ProcessWindowBinding" : "Target"]
        this._matchMode := mode
        this._batching := true
        try this._FillTargets()
        finally this._flushBatch()
        this._RefreshWindowPick()
    }

    _EditWindowBinding(*) {
        MyFrontInfoGui.OwnerHwnd := MainSoftData.IsModalSubGui ? this.Hwnd() : ""
        MyFrontInfoGui.ShowGui(XamlValueBridge(this.ui, "ProcessWindowBinding"))
    }

    _RefreshWindowPick() {
        enabled := this._matchMode == "进程名" || this._matchMode == "PID"
        this.ui.Update("BtnCmdF1", "Visibility", enabled ? "Visible" : "Collapsed")
        if (enabled && !this._pickKeys.Length && this.Hwnd())
            this._pickKeys := WinHotkey.Register(["F1"], this._PickHoveredWindow.Bind(this), this.Hwnd())
        else if (!enabled)
            this._ReleaseWindowPick()
    }

    _HoveredWindow() {
        MouseGetPos(, , &hwnd)
        return hwnd ? DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") : 0
    }

    _PickHoveredWindow(*) {
        if (!this.Hwnd() || !this._pickKeys.Length)
            return
        hwnd := this._HoveredWindow()
        this._StopWindowPick()
        if (!hwnd || hwnd == this.Hwnd())
            return
        try {
            value := this._matchMode == "PID" ? String(WinGetPID(hwnd)) : WinGetProcessName(hwnd)
            this.ui.Update("Target", "Text", value)
        } catch {
            Toast.Info(GetLang("未找到目标窗口。"))
        }
    }

    _ToggleWindowPick(*) {
        if (this._picking) {
            this._StopWindowPick()
            return
        }
        if (!this._pickKeys.Length || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        if (!this.HasOwnProp("_pickClickWhen")) {
            this._pickClickWhen := (*) => this._picking && this._HoveredWindow() != this.Hwnd()
            this._pickCancelWhen := (*) => this._picking
        }
        this._picking := true
        try {
            this._BindWindowPickClicks("On")
            this.ui.Update("BtnCmdF1", "Background", "{DynamicResource ActionBg}")
            ToolTip(GetLang("请点击目标窗口，右键或 Esc 取消"), , , 20)
        } catch {
            this._StopWindowPick()
        }
    }

    _BindWindowPickClicks(state) {
        try {
            HotIf(this._pickClickWhen)
            Hotkey("*LButton", this._PickHoveredWindow.Bind(this), state)
            HotIf(this._pickCancelWhen)
            Hotkey("*RButton", this._StopWindowPick.Bind(this), state)
            Hotkey("Escape", this._StopWindowPick.Bind(this), state)
        } finally HotIf()
    }

    _StopWindowPick(*) {
        if (!this._picking)
            return
        this._picking := false
        try this._BindWindowPickClicks("Off")
        ToolTip(, , , 20)
        if (IsObject(this.ui))
            try this.ui.Update("BtnCmdF1", "Background", "Transparent")
    }

    _ReleaseWindowPick() {
        this._StopWindowPick()
        WinHotkey.UnregisterAll(this._pickKeys)
        this._pickKeys := []
    }

    _CloseWindow() {
        this._ReleaseWindowPick()
        super._CloseWindow()
    }

    OnWindowClosing(state, ctrl, event) {
        this._ReleaseWindowPick()
        super.OnWindowClosing(state, ctrl, event)
    }

    CheckIfValid() {
        try {
            controls := ["Action", "MatchBy", "Target", "ProcessWindowBinding", "PickMatch", "Remark", "EndAll"]
            controls.Push(ProcessManageGui.Outputs*)
            state := this.ui.Query(controls*)
            data := this._ReadOperation(state)
            ProcessManage.ValidateTarget(data, data.Target, true)

            fields := ProcessManage.OutputFields(data.Action)
            if (data.Action == "列出进程")
                fields.Push("ResultArray")
            saved := Map()
            for field in fields {
                if (field == "CountVar") {
                    ; 已配置的匹配数量变量继续写入。
                    data.CountVar := this.Data.HasProp("CountVar") ? this.Data.CountVar : ""
                    continue
                }
                name := Trim(state[field])
                if (name != "" && !this._AddOutput(data, field, name, saved))
                    return false
            }
            if (!saved.Count && data.CountVar == "" && data.ResultArray == "" && data.Action != "结束进程")
                throw ValueError(GetLang("请填写至少一个结果保存名称。"))
            this.Data := data
            this._remark := state["Remark"]
            return true
        } catch as e {
            RmtDialog.Info(e.Message, GetLang(ProcessManageGui.CmdKey), this.Hwnd())
            return false
        }
    }

    _ReadOperation(state) {
        data := ProcessManageData()
        data.SerialStr := this.SerialStr
        data.Action := CmdEnumZh(state["Action"], ProcessManage.Actions)
        data.MatchBy := CmdEnumZh(state["MatchBy"], ProcessManage.MatchModes)
        data.Target := Trim(state[data.MatchBy == "窗口绑定" ? "ProcessWindowBinding" : "Target"])
        data.PickMatch := CmdEnumZh(state["PickMatch"], ProcessManage.MatchPicks)
        checked := state["EndAll"]
        data.EndAll := data.Action == "结束进程" && data.MatchBy != "PID" && (checked = "True" || checked = "1")
        return data
    }

    Preview(*) {
        owner := this.Hwnd()
        title := GetLang(ProcessManageGui.CmdKey)
        try {
            data := this._ReadOperation(this.ui.Query("Action", "MatchBy", "Target", "ProcessWindowBinding", "PickMatch", "EndAll"))
            title .= " · " GetLang(data.Action)
            resolve := (text) => GetReplaceVarText({Items: [{VariableMap: Map()}]}, 1, text, false)
            target := ProcessManage.ResolveTarget(data, resolve, (binding) => ResolveEditorBindWindow(this.WindowBindingContext, binding))
            if ((data.MatchBy == "进程名" || data.MatchBy == "PID") && RegExMatch(target, "\{([^{}]+)\}", &ref))
                throw ValueError(GetLang("当前环境不存在变量") " " ref[1])
            ProcessManage.ValidateTarget(data, target)
            if (data.Action == "结束进程") {
                action := GetLang(data.EndAll ? "结束全部匹配项" : "结束进程")
                if (RmtDialog.Choose(GetLang("目标：") " " target "`n" action, title,
                    [GetLang("结束进程"), GetLang("取消")], owner) != 1)
                    return
            }
            message := this._PreviewMessage(data.Action, ProcessManage.Execute(data, target, true))
        } catch as e {
            message := e.Message
        }
        RmtDialog.Info(message, title, owner)
    }

    _PreviewMessage(action, result) {
        switch action {
            case "检测进程", "结束进程":
                message := GetLang("结果变量：") " " result.ResultVar
                if (action == "结束进程")
                    message .= "`n" Format(GetLang("已提交 {} 个结束请求。"), result.EndedCount)
            case "进程信息":
                message := Format(GetLang("匹配进程数：{}"), result.CountVar)
                if (result.PidVar != "") {
                    message .= "`n" result.NameVar " · PID " result.PidVar "`n" result.PathVar
                    for fields in ProcessManageGui.MetricRows {
                        for field in fields {
                            value := result.%field[1]%
                            message .= "`n" GetLang(field[2]) " " (value == "" ? "—" : value)
                        }
                    }
                } else {
                    message .= "`n" GetLang("是否存在：") " " result.ExistVar
                }
            case "列出进程":
                message := Format(GetLang("匹配进程数：{}"), result.ResultArray.Length)
                for process in result.ResultArray
                    message .= "`n" process[1] " · PID " process[2] (process[3] == "" ? "" : " · " process[3])
        }
        if (result.ErrorVar != "")
            message .= "`n" Format(GetLang("错误信息：{}"), result.ErrorVar)
        return message
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
