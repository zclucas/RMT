#Requires AutoHotkey v2.0

class CommandTimeoutFields {
    static Add(parent, allowUnlimited := false, labelGroup := "CommandLabel", rightLabelGroup := "CommandRightLabel", labelWidth := 0) {
        panel := parent.Add("Grid").Name("CommandTimeoutRow")
        panel.Rows("Auto", "Auto")
        panel.Cols("*", 16, "*")
        time := this._Row(panel, "超时(ms)：", labelGroup, "", GetLang("本次操作最多等待的毫秒数。"), labelWidth)
        status := this._Row(panel, "超时状态：", rightLabelGroup, "TimeoutStatusLabel", "", labelWidth).Grid_Column(2)
        action := this._Row(panel, "超时处理：", labelGroup, "TimeoutActionLabel", "", labelWidth).Grid_Row(1)
        times := ["1000", "3000", "5000", "10000", "30000", "60000"]
        if (allowUnlimited)
            times.Push("不限时")
        this.Combo(time, "TimeoutMs", times, true)
        this.Combo(action, "TimeoutAction", TimeoutPolicy.Actions)
        statusBox := this.Combo(status, "TimeoutStatusVar", [TimeoutPolicy.DefaultStatusVar], true)
        this._StatusTip(status.Find("TimeoutStatusLabel"), "TextBlock")
        this._StatusTip(statusBox, "ComboBox")
        return panel
    }

    static _StatusTip(control, type) {
        style := control.Add(type ".Style").Add("Style").TargetType(type)
        if (type == "ComboBox")
            style.BasedOn("{StaticResource {x:Type ComboBox}}")
        style.Add("Setter").Property("ToolTip").Value(GetLang("超时：1，不超时：0"))
        trigger := style.Add("Style.Triggers").Add("DataTrigger")
            .Binding("{Binding SelectedIndex, ElementName=TimeoutAction}").Value(CmdEnumIndex("无限重试", TimeoutPolicy.Actions))
        trigger.Add("Setter").Property("ToolTip").Value(GetLang("无限重试不可能超时，值为0"))
    }

    static _Row(parent, label, group, labelName, tip, labelWidth) {
        if (!labelWidth)
            return CmdEditorForm.Row(parent, label, , group, , labelName, tip)
        row := parent.Add("Grid").Margin("0,4").Cols(labelWidth, "*")
        caption := CmdEditorForm.Label(row, label).Margin("0")
        if (labelName != "")
            caption.Name(labelName)
        if (tip != "")
            caption.ToolTip(tip)
        return row
    }

    static Combo(row, name, items, editable := false) {
        box := CmdEditorForm.Combo(row, name, editable).Grid_Column(1)
        for value in items
            box.Add("ComboBoxItem").Content(GetLang(value))
        return box
    }

    static Init(ui, ms, action, statusVar) {
        batch := []
        for name in GetGuiVarArr()
            if (name != "" && name != TimeoutPolicy.DefaultStatusVar)
                batch.Push({ControlName: "TimeoutStatusVar", PropertyName: "AddItem", Value: name})
        batch.Push(
            {ControlName: "TimeoutMs", PropertyName: "Text", Value: ms == 0 ? GetLang("不限时") : String(ms)},
            {ControlName: "TimeoutAction", PropertyName: "SelectedIndex",
                Value: action == "" ? -1 : CmdEnumIndex(action, TimeoutPolicy.Actions)},
            {ControlName: "TimeoutStatusVar", PropertyName: "Text", Value: GetLang(statusVar)})
        if (action == "")
            batch.Push({ControlName: "TimeoutActionLabel", PropertyName: "ToolTip", Value: GetLang("留空时沿用旧版超时处理。")})
        ui.BatchUpdate(batch)
    }

    static Read(ui, data, allowUnlimited := false) {
        state := ui.Query("TimeoutMs", "TimeoutAction", "TimeoutStatusVar")
        ms := Trim(state["TimeoutMs"])
        if (allowUnlimited && (ms == "" || ms == GetLang("不限时")))
            ms := 0
        data.TimeoutMs := IsInteger(ms) ? Integer(ms) : ms
        data.TimeoutAction := GetLangKey(state["TimeoutAction"])
        data.TimeoutStatusVar := GetVarName(Trim(state["TimeoutStatusVar"]))
    }

    static ValidateStatus(data, otherResults*) {
        name := TimeoutPolicy.StatusVar(data)
        if (name == "")
            return true
        if (!CheckVarNameIfValid(name))
            return false
        for other in otherResults {
            if (name = other) {
                RmtDialog.Info(GetLang("超时状态变量不能与其他结果变量同名。"))
                return false
            }
        }
        return true
    }
}
