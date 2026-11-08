
; ============================================================================
; 主窗口 XAML 迁移
; 用 XAMLHost + XAML_Generator 替代原生 Gui() 应用壳。
; 适配器让消费文件对原生控件的 .Value/.Text/.Hwnd/.Focus()/.GetPos()/.Opt()
; 等引用继续工作：
;   GuiAdapter  -> MainSoftData.MyGui
;   TabAdapter  -> MainSoftData.TabCtrl
;   CtrlAdapter -> UIControls.* / MainSoftData.Tool*Ctrl / MainSoftData.BtnSave
; ============================================================================

class CtrlAdapter {
    __New(name, ui, prop := "Text") {
        this._name := name
        this._ui := ui
        this._prop := prop        ; "Text" | "IsChecked" | "SelectedIndex"
    }
    Value {
        get {
            v := this._ui.Query(this._name)
            if (this._prop == "IsChecked")
                return (v == "True")
            return v
        }
        set {
            if (this._prop == "IsChecked")
                this._ui.Update(this._name, "IsChecked", value ? "True" : "False")
            else if (this._prop == "SelectedIndex")
                this._ui.Update(this._name, "SelectedIndex", String(value - 1))
            else
                this._ui.Update(this._name, this._prop, String(value))
        }
    }
    Text {
        get => this._ui.Query(this._name)
        set => this._ui.Update(this._name, "Text", String(value))
    }
    Focus() {
        this._ui.Update(this._name, "Focus", "True")
    }
    Enabled {
        set => this._ui.Update(this._name, "IsEnabled", value ? "True" : "False")
    }

    ; 批量写：pairs = [[adapter, 新值], ...]，合并成一条 IPC。
    ; 定时刷新整块显示的控件（如工具页 8 个信息框）逐条复制会变成每秒几十次跨进程往返，
    ; 这里一次发完，WPF 侧也只结算一次布局。
    static RefreshAll(pairs) {
        ui := ""
        batch := []
        for pair in pairs {
            a := pair[1]
            if (!IsObject(a))
                continue
            ui := a._ui
            v := pair[2]
            if (a._prop == "IsChecked")
                batch.Push({ ControlName: a._name, PropertyName: "IsChecked", Value: v ? "True" : "False" })
            else if (a._prop == "SelectedIndex")
                batch.Push({ ControlName: a._name, PropertyName: "SelectedIndex", Value: String(v - 1) })
            else
                batch.Push({ ControlName: a._name, PropertyName: a._prop, Value: String(v) })
        }
        if (ui && batch.Length)
            try ui.BatchUpdate(batch)
    }
}

class TabAdapter {
    __New(ui, owner := "") {
        this.ui := ui
        this._owner := owner
        this._value := 1
    }
    ; §10 可见页签映射表（TableInfo 下标数组，主窗口构建时按 TabVisibleMap 过滤生成）
    _TabOrder() {
        o := (IsObject(this._owner) && this._owner.HasOwnProp("_tabOrder") && IsObject(this._owner._tabOrder)) ? this._owner._tabOrder : ""
        return (o && o.Length > 0) ? o : ""
    }
    Value {
        get {
            o := this._TabOrder()
            if (!o)
                return this._value
            v := this.ui.Query("TabControl>SelectedIndex")
            if (v == "")
                return this._value
            sel := Integer(v) + 1
            if (sel >= 1 && sel <= o.Length)
                return o[sel]
            return this._value
        }
        set {
            this._value := value
            o := this._TabOrder()
            if (!o) {
                this.ui.Update("TabControl", "SelectedIndex", String(value - 1))
                return
            }
            for i, t in o {
                if (t == value) {
                    this.ui.Update("TabControl", "SelectedIndex", String(i - 1))
                    return
                }
            }
            ; 目标表被隐藏：切到第一个可见页签
            this.ui.Update("TabControl", "SelectedIndex", "0")
        }
    }
    UseTab(i := "") {
        if (i != "")
            this.Value := i
    }
    Move(*) {
    }
    OnEvent(evt, cb) {
        if (evt == "Change")
            this.ui.OnEvent("TabControl", "SelectionChanged", cb)
    }
}

class GuiAdapter {
    __New(ui) {
        this.ui := ui
        this._title := ""
    }
    Hwnd {
        get => this.ui.wpfHwnd
    }
    Title {
        get => this._title
        set {
            this._title := value
            this.ui.Update("Window", "Title", value)
        }
    }
    Show(opts := "") {
        hwnd := this.ui.wpfHwnd
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return
        if (opts != "") {
            if (RegExMatch(opts, "i)x(\d+)", &mx) && RegExMatch(opts, "i)y(\d+)", &my)) {
                w := RegExMatch(opts, "i)w(\d+)", &mw) ? Integer(mw[1]) : 1070
                h := RegExMatch(opts, "i)h(\d+)", &mh) ? Integer(mh[1]) : 590
                WinMove(Integer(mx[1]), Integer(my[1]), w, h, hwnd)
            }
        }
        WinShow(hwnd)
        ; 与原生 Gui.Show 语义一致：显示即激活（托盘「显示窗口」/最小化启动恢复都走这里）
        try WinActivate(hwnd)
    }
    Hide() {
        if (IsSet(MyMainWin) && IsObject(MyMainWin) && MyMainWin.ui == this.ui)
            MyMainWin.HideSideDebugTools()
        WinHide(this.ui.wpfHwnd)
    }
    Opt(opt) {
        if (InStr(opt, "AlwaysOnTop"))
            this.ui.Update("Window", "Topmost", SubStr(opt, 1, 1) == "+" ? "True" : "False")
    }
    GetPos(&x, &y, &w, &h) {
        WinGetPos(&x, &y, &w, &h, this.ui.wpfHwnd)
    }
    Flash() {
        DllCall("FlashWindow", "Ptr", this.ui.wpfHwnd, "Int", 1)
    }
    Submit() {
        return ""   ; 值已由事件/回读同步到 MainSoftData，此处 no-op
    }
}

; 休眠/暂停 状态按钮适配器：激活时显示「蓝色背景+右上角红点」按钮，否则显示普通按钮
; BindUtil 通过 UIControls.SuspendToggle/PauseToggle.Value 写入状态，与本类对接
class StateBtnAdapter {
    __New(normalName, activeName, ui) {
        this._normal := normalName
        this._active := activeName
        this._ui := ui
    }
    Value {
        get => ""
        set {
            this._ui.Update(this._normal, "Visibility", value ? "Collapsed" : "Visible")
            this._ui.Update(this._active, "Visibility", value ? "Visible" : "Collapsed")
        }
    }
}
