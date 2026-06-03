#Requires AutoHotkey v2.0
#Include VarModifyGui.ahk

class VarListenGui {
    __new() {
        this.Gui := ""
        this.ModifyGui := VarModifyGui()
        this.TopCon := ""
        this.LVCon := ""
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        
        this.TopCon.Value := MySoftData.VarListenTop
        this.OnTogTop()
        IniWrite(true, IniFile, IniSection, "IsOpenListenVar")
        this.Refresh()
        this.LVCon.Focus()  ; 🔥 强制获得焦点，解决第一次双击无效问题
    }

    Refresh() {
        if (!IsObject(this.Gui))
            return

        style := WinGetStyle(this.Gui)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        this.LVCon.Opt("-Redraw")
        count := this.LVCon.GetCount()
        LVKeys := Map()
        loop count {
            row := count - A_Index + 1
            key := LTrim(this.LVCon.GetText(row, 1), "ε")
            value := this.LVCon.GetText(row, 3)
            if (!MySoftData.VariableMap.Has(key) && !MySoftData.ArrayMap.Has(key))
                this.LVCon.Delete(row)
            else if (MySoftData.VariableMap.Has(key) && String(MySoftData.VariableMap[key]) != value)
                this.LVCon.Delete(row)
            else if (MySoftData.ArrayMap.Has(key) && GetArrayStr(MySoftData.ArrayMap[key]) != value)
                this.LVCon.Delete(row)
            else
                LVKeys[key] := True
        }

        ; 3) 添加 Map 中有但 LV 没有的项
        for key, value in MySoftData.VariableMap {
            if !LVKeys.Has(key) {
                this.LVCon.Add(, key, GetLang("值"), value)
            }
        }

        ;key前面加一个空格，确保排在后面
        for key, value in MySoftData.ArrayMap {
            if !LVKeys.Has(key) {
                this.LVCon.Add(, "ε" key, GetLang("数组"), GetArrayStr(value))
            }
        }
        this.LVCon.Opt("+Redraw")
    }

    AddGui() {
        MyGui := Gui(, GetLang("变量监视器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        MyGui.Opt("+Resize")

        PosX := 10
        PosY := 10
        this.TopCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口置顶"))
        this.TopCon.OnEvent("Click", this.OnTogTop.Bind(this))

        PosX := 10
        PosY += 30
        this.LVCon := MyGui.Add("ListView", Format("x{} y{} w380 h370 -LV0x10 NoSort Sort", PosX, PosY), GetLangArr([
            "变量名", "类型", "值"]))
        ; 设置列宽（单位：px）
        this.LVCon.ModifyCol(1, 100) ; 第一列宽度
        this.LVCon.ModifyCol(2, 50) ; 第一列宽度
        this.LVCon.ModifyCol(3, 205) ; 自动填充剩余宽度
        this.LVCon.OnEvent("DoubleClick", this.OnDoubleClick.Bind(this))

        MyGui.OnEvent("Close", this.OnClose.Bind(this))
        MyGui.OnEvent("Size", this.OnResize.Bind(this))
        pos := GetCenterPosOnActiveMonitor(MySoftData.VarListenWidth, MySoftData.VarListenHeight)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, MySoftData.VarListenWidth, MySoftData.VarListenHeight))
        MyGui.Opt("+MinSize400x420")
    }

    OnClose(*) {
        if (MySoftData.MacroEditGui != "" && MySoftData.MacroEditGui.Gui != "") {
            style := WinGetStyle(MySoftData.MacroEditGui.Gui)
            isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
            if (isVisible) {
                MySoftData.MacroEditGui.ToolMenu.Uncheck(GetLang("变量监视"))
            }
        }
        IniWrite(false, IniFile, IniSection, "IsOpenListenVar")
    }

    OnResize(guiObj, MinMax, Width, Height) {
        ; 留一点边距
        margin := 10
        ; ListView 自适应
        this.LVCon.Move(
            margin,
            40,
            Width - margin * 2,
            Height - 50
        )

        IniWrite(Width, IniFile, IniSection, "VarListenWidth")
        IniWrite(Height, IniFile, IniSection, "VarListenHeight")
    }

    OnTogTop(*) {
        state := this.topCon.Value
        if (state) {
            this.Gui.Opt("+AlwaysOnTop")
        }
        else {
            this.Gui.Opt("-AlwaysOnTop")
        }
        IniWrite(state, IniFile, IniSection, "VarListenTop")
    }

    OnDoubleClick(LV, RowNumber, *) {
        isArray := SubStr(this.LVCon.GetText(RowNumber, 1), 1, 1) == "ε"
        varName := LTrim(this.LVCon.GetText(RowNumber, 1), "ε")
        curValue := this.LVCon.GetText(RowNumber, 3)
        SureAction := this.OnModifySureAction.Bind(this, isArray)
        this.ModifyGui.ParentHwnd := this.Gui.Hwnd
        this.ModifyGui.SureAction := SureAction
        this.ModifyGui.ShowGui(varName, curValue)
    }

    OnModifySureAction(isArray, Name, Value) {
        if (isArray) {
            if (Value == "")
                DeleteGlobalArray(Name)
            else
                SetGlobalArray(Name, GetArray(Value))
        }
        else {
            if (Value == "")
                DelGlobalVariable([Name])
            else
                SetGlobalVariable([Name], [Value], false)
        }
    }
}
