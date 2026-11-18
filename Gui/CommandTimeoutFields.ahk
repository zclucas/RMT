#Requires AutoHotkey v2.0

class CommandTimeoutFields {
    static Add(parent, allowUnlimited := false) {
        panel := parent.Add("Grid").Name("CommandTimeoutRow")
        panel.Rows("Auto", "Auto")
        panel.Cols("*", 16, "*")
        time := CmdEditorForm.Row(panel, "超时(ms)：", , , , , GetLang("本次操作最多等待的毫秒数。"))
        status := CmdEditorForm.Row(panel, "超时状态：", "", "CommandRightLabel", "Center", "TimeoutStatusLabel").Grid_Column(2)
        action := CmdEditorForm.Row(panel, "超时处理：").Grid_Row(1)
        times := ["1000", "3000", "5000", "10000", "30000", "60000"]
        if (allowUnlimited)
            times.Push("不限时")
        this.Combo(time, "TimeoutMs", times, true)
        this.Combo(action, "TimeoutAction", TimeoutPolicy.Actions)
        this.Combo(status, "TimeoutStatusVar", [TimeoutPolicy.DefaultStatusVar], true)
        return panel
    }

    static Combo(row, name, items, editable := false) {
        box := CmdEditorForm.Combo(row, name, editable).Grid_Column(1)
        for value in items
            box.Add("ComboBoxItem").Content(GetLang(value))
        return box
    }

    static Init(ui, ms, action, statusVar) {
        batch := [{ControlName: "TimeoutStatusLabel", PropertyName: "ToolTip", Value: GetLang("超时：1，不超时：0")}]
        for name in GetGuiVarArr()
            if (name != "" && name != TimeoutPolicy.DefaultStatusVar)
                batch.Push({ControlName: "TimeoutStatusVar", PropertyName: "AddItem", Value: name})
        batch.Push(
            {ControlName: "TimeoutMs", PropertyName: "Text", Value: ms == 0 ? GetLang("不限时") : String(ms)},
            {ControlName: "TimeoutAction", PropertyName: "SelectedIndex",
                Value: action == "" ? -1 : CmdEnumIndex(action, TimeoutPolicy.Actions)},
            {ControlName: "TimeoutStatusVar", PropertyName: "Text", Value: GetLang(statusVar)})
        if (action == "")
            batch.Push({ControlName: "TimeoutAction", PropertyName: "ToolTip", Value: GetLang("留空时沿用旧版超时处理。")})
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
