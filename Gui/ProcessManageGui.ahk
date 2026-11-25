#Requires AutoHotkey v2.0

class ProcessManageGui extends CommentGui {
    ; 配置兼容旧键，界面与输出指令通过 GetLang 显示为“进程”。
    static CmdKey := "进程管理"
    _autoRemark := ""
    static Outputs := ["ResultVar", "NameVar", "PidVar", "PathVar", "ResultArray", "ExistVar", ProcessInfo.Metrics*]
    static OutputDefaults := Map("ResultVar", "Res", "NameVar", "Name", "PidVar", "PID", "PathVar", "Path",
        "ResultArray", "Procs", "ExistVar", "Exists", "StatusVar", "Status", "StartTimeVar", "Start",
        "UptimeVar", "Time", "CpuVar", "CPU", "GpuVar", "GPU")
    static MetricRows := [
        [["NameVar", "进程名：", "匹配进程的可执行文件名。"], ["StatusVar", "状态：", "正常、无响应、阻塞、加载或挂起。"]],
        [["StartTimeVar", "启动时间：", "本地时间，格式为 yyyy-MM-dd HH:mm:ss。"], ["UptimeVar", "运行时长：", "从进程启动到查询时的秒数。"]],
        [["CpuVar", "CPU 占用：", "短时采样，占全部逻辑处理器的百分比。"], ["GpuVar", "GPU 占用：", "进程最忙的 GPU 引擎占用率（%）。"]]]
    WindowBindingContext := ""
    _playHotkeys := []
    _pickKeys := []
    _picking := false
    _targetIconPaths := []

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
        row := this._Pair(body).Name("ProcessResultVariableRow")
        this._Output(row, "ResultVar", "结果变量：", false, tip)
        this._ShowFor(row, [0])

        row := this._Pair(body)
        pick := this._Choice(row, "选取方式：", "PickMatch", ProcessManage.MatchPicks)
        pick.Name("ProcessPickRow")
        this._Output(row, "ExistVar", "是否存在：", true, GetLang("存在：1，不存在：0。"))
        this._ShowFor(row, [CmdEnumIndex("进程信息", ProcessManage.Actions)])
        row := this._Pair(body)
        this._Output(row, "PidVar", "PID：")
        this._Output(row, "PathVar", "程序路径：", true)
        this._ShowFor(row, [CmdEnumIndex("进程信息", ProcessManage.Actions)])
        for fields in ProcessManageGui.MetricRows {
            row := this._Pair(body)
            for i, field in fields
                this._Output(row, field[1], field[2], i == 2, GetLang(field[3]))
            this._ShowFor(row, [CmdEnumIndex("进程信息", ProcessManage.Actions)])
        }
        row := this._Pair(body)
        this._Output(row, "ResultArray", "结果数组：", false, GetLang("所有匹配的PID"))
        this._ShowFor(row, [CmdEnumIndex("列出进程", ProcessManage.Actions)])
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
        this.ui.OnEvent("Action", "SelectionChanged", XamlWin.BindCurrent(this, "_OnActionChanged"))
        BindCmdEditorChrome(this.ui, "#指令手册/41-进程", XamlWin.BindCurrent(this, "Preview"))
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
        for choice in choices {
            item := combo.Add("ComboBoxItem").Content(GetLang(choice))
            if (name == "MatchBy" && choice == "PID") {
                item.Name("ProcessPidMatchOption")
                style := item.Add("ComboBoxItem.Style").Add("Style").TargetType("ComboBoxItem")
                trigger := style.Add("Style.Triggers").Add("DataTrigger")
                    .Binding("{Binding SelectedIndex, ElementName=Action}").Value(CmdEnumIndex("列出进程", ProcessManage.Actions))
                trigger.Add("Setter").Property("Visibility").Value("Collapsed")
            }
        }
        return row
    }

    _TargetField(body) {
        row := this._FieldRow(body, "目标：", true, GetLang("输入进程名、程序完整路径、PID 或正则，支持 {变量}。完整路径忽略大小写；正则匹配进程名。"))
            .Name("ProcessTargetRow")
        CmdEditorForm.Combo(row, "Target", true).Grid_Column(1)
        hint := row.Add("TextBlock").Name("TargetHint").Grid_Column(1)
            .Foreground("{DynamicResource TextSub}").VerticalAlignment("Center").Margin("8,0,24,0")
            .TextTrimming("CharacterEllipsis").IsHitTestVisible("False")
        style := hint.Add("TextBlock.Style").Add("Style").TargetType("TextBlock")
        style.Add("Setter").Property("Visibility").Value("Collapsed")
        style.Add("Setter").Property("Text").Value(GetLang("请输入进程PID"))
        triggers := style.Add("Style.Triggers")
        trigger := triggers.Add("MultiDataTrigger")
        conditions := trigger.Add("MultiDataTrigger.Conditions")
        conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=MatchBy}").Value(CmdEnumIndex("PID", ProcessManage.MatchModes))
        conditions.Add("Condition").Binding("{Binding Text, ElementName=Target}").Value("")
        trigger.Add("Setter").Property("Visibility").Value("Visible")
        trigger := triggers.Add("MultiDataTrigger")
        conditions := trigger.Add("MultiDataTrigger.Conditions")
        conditions.Add("Condition").Binding("{Binding SelectedIndex, ElementName=MatchBy}").Value(CmdEnumIndex("完整路径匹配", ProcessManage.MatchModes))
        conditions.Add("Condition").Binding("{Binding Text, ElementName=Target}").Value("")
        trigger.Add("Setter").Property("Visibility").Value("Visible")
        trigger.Add("Setter").Property("Text").Value(GetLang("请输入程序完整路径"))

        row := this._FieldRow(body, "窗口绑定：", true, GetLang("指定这条指令要操作的窗口。")).Name("ProcessWindowRow")
        binding := row.Add("Grid").Grid_Column(1).Cols("*", 6, 28)
        CmdEditorForm.WindowBindingCombo(binding, "ProcessWindowBinding").MaxHeight(26)
        CmdEditorForm.IconButton(binding, "BtnEditProcessWindow", 0xE70F, "编辑").Grid_Column(2)
    }

    _Output(body, name, label, right := false, tip := "") {
        row := this._FieldRow(body, label, right, tip)
        combo := CmdEditorForm.Combo(row, name, true).Grid_Column(1)
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
        this._autoRemark := ReadCommandAutoRemark(this.Data, GenerateCommandAutoRemark)
        this.SerialStr := this.Data.SerialStr
        this._matchMode := this.Data.MatchBy
        this._targets := Map(this._matchMode, parts.Length ? this.Data.Target : "notepad.exe")
        action := ProcessManage.ActionKey(this.Data.Action)
        if (action == "列出进程" && this._matchMode == "PID") {
            this._matchMode := "进程名"
            this._targets[this._matchMode] := ""
        }
        this._ComboPush("Action", "SelectedIndex", CmdEnumIndex(action, ProcessManage.Actions))
        this._ComboPush("MatchBy", "SelectedIndex", CmdEnumIndex(this._matchMode, ProcessManage.MatchModes))
        this._ComboPush("PickMatch", "SelectedIndex", CmdEnumIndex(this.Data.HasProp("PickMatch") ? this.Data.PickMatch : "首个", ProcessManage.MatchPicks))
        this._FillTargets()
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        vars := GetGuiVarArr()
        arrays := GetGuiArrNameArr()
        for field in ProcessManageGui.Outputs {
            for name in (field == "ResultArray" ? arrays : vars)
                this._ComboPush(field, "AddItem", name)
            value := parts.Length && this.Data.HasProp(field) ? this.Data.%field% : ""
            if (value == "")
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
            this._ComboPush("ProcessWindowBinding", "Text", NormalizeWindowBinding(this._targets.Get(this._matchMode, "{运行时句柄ID}")))
            return
        }
        this._ComboPush("Target", "ClearItems", "")
        this._targetIconPaths := []
        if (this._matchMode == "进程名" || this._matchMode == "PID")
            this._AddProcessTargets(this._matchMode == "PID")
        for reference in GetGuiVarReferences()
            this._ComboPush("Target", "AddItem", reference)
        this._ComboPush("Target", "Text", this._targets.Get(this._matchMode, ""))
    }

    _AddProcessTargets(byPid) {
        try processes := ProcessManage.Find("进程名", "")
        catch
            return
        groups := Map()
        groups.CaseSense := false
        for process in processes {
            value := byPid ? String(process.Pid) : process.Name
            if (value == "")
                continue
            if (!groups.Has(value))
                groups[value] := {Name: process.Name, Pid: process.Pid, Count: 0, Paths: []}
            group := groups[value]
            group.Count += 1
            path := ProcessManage.Path(process.Pid)
            if (path != "") {
                found := false
                for existing in group.Paths {
                    if (existing = path) {
                        found := true
                        break
                    }
                }
                if (!found)
                    group.Paths.Push(path)
            }
        }
        values := ""
        for value in groups
            values .= value "`n"
        for value in StrSplit(Sort(RTrim(values, "`n"), byPid ? "N" : ""), "`n") {
            if (value == "")
                continue
            group := groups[value]
            detail := group.Count == 1 ? "PID " group.Pid : Format(GetLang("匹配进程数：{}"), group.Count)
            label := group.Name == "" ? detail : group.Name
            this._targetIconPaths.Push(group.Paths.Length ? group.Paths[1] : "")
            index := this._targetIconPaths.Length
            xaml := '<ComboBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
                . ' TextSearch.Text="{}' this._EscapeXml(value) '">'
                . '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                . '<Image Name="TargetProcessIcon' index '" Width="16" Height="16" HorizontalAlignment="Left"/>'
                . '<StackPanel Grid.Column="1"><TextBlock Text="{}' this._EscapeXml(label) '" TextTrimming="CharacterEllipsis"/>'
            if (group.Name != "")
                xaml .= '<TextBlock Text="{}' this._EscapeXml(detail) '" Opacity="0.75" TextTrimming="CharacterEllipsis"/>'
            this._ComboPush("Target", "AddXamlItem", xaml '</StackPanel></Grid></ComboBoxItem>')
        }
    }

    _SetTargetIcons() {
        if (!this._targetIconPaths.Length)
            return
        icons := Map()
        icons.CaseSense := false
        fallback := DllCall("user32\LoadIconW", "Ptr", 0, "Ptr", 32512, "Ptr")
        updates := []
        ; 等候窗口建好后同步传入 HICON，WPF 读取完即可释放提取的图标。
        try {
            for index, path in this._targetIconPaths {
                if (path != "" && !icons.Has(path)) {
                    icon := 0
                    DllCall("shell32\ExtractIconExW", "Str", path, "Int", 0, "Ptr", 0, "Ptr*", &icon, "UInt", 1, "UInt")
                    icons[path] := icon
                }
                icon := icons.Get(path, 0)
                if (!icon)
                    icon := fallback
                if (icon)
                    updates.Push({ControlName: "TargetProcessIcon" index, PropertyName: "Source", Value: "HICON:" icon})
            }
            this.ui.BatchUpdate(updates)
        } finally {
            for path, icon in icons
                if (icon)
                    DllCall("user32\DestroyIcon", "Ptr", icon)
        }
    }

    OnWindowLoad(state, ctrl, event) {
        super.OnWindowLoad(state, ctrl, event)
        this._playHotkeys := WinHotkey.Register(["!l"], XamlWin.BindCurrent(this, "Preview"), this.Hwnd())
        if (this._matchMode == "进程名" || this._matchMode == "PID")
            this._SetTargetIcons()
        this._RefreshWindowPick()
    }

    _OnActionChanged(*) {
        if (!this.Hwnd())
            return
        state := this.ui.Query("Action", "MatchBy")
        if (CmdEnumZh(state["Action"], ProcessManage.Actions) == "列出进程"
            && CmdEnumZh(state["MatchBy"], ProcessManage.MatchModes) == "PID") {
            this.ui.Update("MatchBy", "SelectedIndex", CmdEnumIndex("进程名", ProcessManage.MatchModes))
            this._OnMatchByChanged()
        }
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
        if (mode == "进程名" || mode == "PID")
            this._SetTargetIcons()
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
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        this._ReleaseWindowPick()
        super._CloseWindow()
    }

    OnWindowClosing(state, ctrl, event) {
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        this._ReleaseWindowPick()
        super.OnWindowClosing(state, ctrl, event)
    }

    CheckIfValid() {
        try {
            controls := ["Action", "MatchBy", "Target", "ProcessWindowBinding", "PickMatch", "Remark"]
            controls.Push(ProcessManageGui.Outputs*)
            state := this.ui.Query(controls*)
            data := this._ReadOperation(state)
            ProcessManage.ValidateTarget(data, data.Target, true)

            fields := data.Action == "结束进程" ? [] : ProcessManage.OutputFields(data.Action)
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
        return data
    }

    Preview(*) {
        owner := this.Hwnd()
        title := GetLang(ProcessManageGui.CmdKey)
        try {
            data := this._ReadOperation(this.ui.Query("Action", "MatchBy", "Target", "ProcessWindowBinding", "PickMatch"))
            title .= " · " GetLang(data.Action)
            resolve := (text) => GetReplaceVarText({Items: [{VariableMap: Map()}]}, 1, text, false)
            target := ProcessManage.ResolveTarget(data, resolve, (binding) => ResolveEditorBindWindow(this.WindowBindingContext, binding))
            if ((data.MatchBy == "进程名" || data.MatchBy == "PID") && RegExMatch(target, "\{([^{}]+)\}", &ref))
                throw ValueError(GetLang("当前环境不存在变量") " " ref[1])
            ProcessManage.ValidateTarget(data, target)
            if (data.Action == "结束进程") {
                action := GetLang("结束进程")
                if (RmtDialog.Choose(GetLang("目标：") " " target "`n" action, title,
                    [GetLang("结束进程"), GetLang("取消")], owner) != 1)
                    return
            }
            result := ProcessManage.Execute(data, target, true)
            if (data.Action == "进程信息") {
                RmtDialog.InfoFields(this._PreviewFields(result), title, owner)
                return
            }
            message := this._PreviewMessage(data.Action, result)
        } catch as e {
            message := e.Message
        }
        RmtDialog.Info(message, title, owner)
    }

    _PreviewFields(result) {
        shown(value) => value == "" ? "—" : String(value)
        percent(value) => value == "" ? "—" : Format("{:.2f}%", value)
        fields := [
            [GetLang("是否存在："), String(result.ExistVar), GetLang("（1存在，0不存在）")],
            [GetLang("进程名："), shown(result.NameVar)],
            [GetLang("PID："), shown(result.PidVar)],
            [GetLang("程序路径："), shown(result.PathVar)],
            [GetLang("状态："), shown(result.StatusVar), GetLang("正常、无响应、阻塞、加载、挂起")],
            [[GetLang("启动时间："), shown(result.StartTimeVar)],
                [GetLang("运行时长："), result.UptimeVar == "" ? "—" : ProcessInfo.FormatUptime(result.UptimeVar)]],
            [[GetLang("CPU 占用："), percent(result.CpuVar)], [GetLang("GPU 占用："), percent(result.GpuVar)]]]
        if (result.ErrorVar != "")
            fields.Push([GetLang("错误信息："), result.ErrorVar])
        return fields
    }

    _PreviewMessage(action, result) {
        switch action {
            case "检测进程":
                message := GetLang("结果变量：") " " result.ResultVar
            case "结束进程":
                message := Format(GetLang("已提交 {} 个结束请求。"), result.EndedCount)
            case "进程信息":
                message := ""
                for field in this._PreviewFields(result) {
                    line := field[1] is Array ? field[1][1] " " field[1][2] "    " field[2][1] " " field[2][2]
                        : field[1] " " field[2] (field.Length >= 3 ? "    " field[3] : "")
                    message .= (message == "" ? "" : "`n") line
                }
            case "列出进程":
                message := Format(GetLang("匹配进程数：{}"), result.ResultArray.Length)
                for pid in result.ResultArray
                    message .= "`nPID " pid
        }
        if (result.ErrorVar != "" && action != "进程信息")
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
        FormatCommandAutoRemark(this.Data, this._remark, this._autoRemark, GenerateCommandAutoRemark, true)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return FormatCommandAutoRemark(this.Data, this._remark, this._autoRemark, GenerateCommandAutoRemark, false)
    }
}
