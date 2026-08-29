#Requires AutoHotkey v2.0

; 功能选项「快捷键」：XAML 双列编辑全局快捷键（设置页原「快捷键修改」模块已移除）

class HotkeyValueHolder {
    __New(val := "") {
        this.Value := val
        this.Visible := true
        this.Enabled := true
    }
}

class HotkeySettingGui {
    static instances := Map()
    static _opening := false

    ; 与设置页「快捷键修改」同一批字段；OnlyTrigger=true 时不可用字串触发
    static HotkeyDefs := [
        {Field: "SuspendHotkey", Label: "软件休眠", OnlyTrigger: true, Default: "!p"},
        {Field: "PauseHotkey", Label: "暂停宏", OnlyTrigger: false, Default: "!i"},
        {Field: "KillMacroHotkey", Label: "终止宏", OnlyTrigger: false, Default: "!k"},
        {Field: "ToolRecordMacroHotKey", Label: "指令录制", OnlyTrigger: false, Default: "!r"},
        {Field: "ToolTextFilterHotKey", Label: "文本提取", OnlyTrigger: false, Default: "!u"},
        {Field: "ScreenShotHotKey", Label: "屏幕截图", OnlyTrigger: false, Default: "!y"},
        {Field: "FreePasteHotKey", Label: "自由贴", OnlyTrigger: false, Default: "!t"},
        {Field: "ToolCheckHotkey", Label: "鼠标信息", OnlyTrigger: false, Default: "!o"},
        {Field: "DebugRunHotkey", Label: "调试运行", OnlyTrigger: true, Default: "f5"},
        {Field: "DebugStepHotkey", Label: "调试单步", OnlyTrigger: true, Default: "f6"}
    ]

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this._values := Map()
        this._syncing := false
        this._ignoreConfirmUntil := 0  ; 编辑子窗确认后短时忽略「确定」，避免 Enter 误关本窗
    }

    static ShowGui() {
        key := "global"
        XamlUiDiag("ShowGui enter _opening=" HotkeySettingGui._opening " hasInst=" HotkeySettingGui.instances.Has(key), "Hotkey")
        XamlUiDiagDaemon("Hotkey.pre")
        if (HotkeySettingGui.instances.Has(key)) {
            oldInst := HotkeySettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            reuse := (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd))
            XamlUiDiag(Format("oldInst closed={} hwnd={} reuse={}", oldInst.closed, hwnd, reuse), "Hotkey")
            if (reuse) {
                try WinActivate("ahk_id " hwnd)
                XamlUiDiagWindow(hwnd, "Hotkey.reuse", true)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            HotkeySettingGui.instances.Delete(key)
            XamlUiDiag("deleted stale instance", "Hotkey")
        }

        t0 := A_TickCount
        XAMLHost.EnsureDaemonHealthy()
        XamlUiDiag("EnsureDaemonHealthy cost=" (A_TickCount - t0) "ms", "Hotkey")
        if (HotkeySettingGui._opening) {
            XamlUiDiag("ABORT: _opening=true", "Hotkey")
            return
        }
        HotkeySettingGui._opening := true
        try {
            inst := HotkeySettingGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            HotkeySettingGui.instances[key] := inst
            XamlUiDiag("ShowGui done hwnd=" (IsObject(inst.ui) && inst.ui.HasProp("wpfHwnd") ? inst.ui.wpfHwnd : 0), "Hotkey")
        } catch as e {
            XamlUiDiag("ShowGui EXCEPTION: " e.Message " @ " e.File ":" e.Line, "Hotkey")
        } finally {
            HotkeySettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("快捷键")
        titleHeight := "36"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Rows(titleHeight, "*")

        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("24, 14, 24, 10")

        ; 紧凑「编辑」按钮：主题编辑色，去掉默认 Padding
        this._editBtnStyle := '<Style TargetType="Button"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="0"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        defs := HotkeySettingGui.HotkeyDefs
        half := Integer((defs.Length + 1) // 2)
        loop half {
            i := A_Index
            row := panel.Add("StackPanel").Orientation("Horizontal").Margin(i == 1 ? "0,4,0,0" : "0,14,0,0")
            this._AddHotkeyItem(row, defs[i], 0)
            rightIdx := i + half
            if (rightIdx <= defs.Length)
                this._AddHotkeyItem(row, defs[rightIdx], 70)
        }

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,6")
        revertBtn := btnRow.Add("Button").Name("BtnRevert").Content(GetLang("恢复默认")).Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).Cursor("Hand").Width(90).Height(32).Margin("0,0,16,0").IsDefault("False").IsCancel("False")
        revertBtn.InjectResources(PrimaryBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定")).Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).Cursor("Hand").Width(80).Height(32).IsDefault("False").IsCancel("False")
        okBtn.InjectResources(PrimaryBtnStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="False" Width="630" Height="330" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnRevert", "Click", ObjBindMethod(this, "OnRevertClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnConfirmClick"))

        for def in defs {
            this.ui.OnEvent("BtnEdit_" def.Field, "Click", ObjBindMethod(this, "OnEditHotkey", def.Field, def.OnlyTrigger))
        }

        this.LoadInitValues()
        this.ApplyValuesToUI()
        XamlUiDiag("before ui.Show() hostId=" this.ui.id, "Hotkey")
        tShow := A_TickCount
        this.ui.Show()
        XamlUiDiag("ui.Show() returned cost=" (A_TickCount - tShow) "ms", "Hotkey")

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                hwnd := this.ui.wpfHwnd
                try this.ui.Update("Window", "Opacity", "1")
                try WinActivate("ahk_id " hwnd)
                XamlUiDiagWindow(hwnd, "Hotkey.afterShow", true)
                break
            }
            Sleep(50)
        }
        if (!gotHwnd) {
            XamlUiDiag("FAIL: no wpfHwnd after wait", "Hotkey")
            XamlUiDiagDaemon("Hotkey.noHwnd")
        }
    }

    _AddHotkeyItem(row, def, leftMargin) {
        item := row.Add("StackPanel").Orientation("Horizontal").Margin(leftMargin ",0,0,0").VerticalAlignment("Center")
        item.Add("TextBlock").Text(GetLang(def.Label) "：")
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Width(72)
        box := item.Add("Border").Width(120).Height(28).CornerRadius("3")
            .Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .VerticalAlignment("Center")
        box.Add("TextBlock").Name("Val_" def.Field)
            .Text("").FontSize(12)
            .Foreground("{DynamicResource InputText}")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        editBtn := item.Add("Button").Name("BtnEdit_" def.Field).Content(GetLang("编辑"))
            .Width(52).Height(28).Margin("8,0,0,0").Padding("0").FontSize(12).Cursor("Hand")
            .Background("{DynamicResource EditBg}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .Foreground("{DynamicResource EditText}")
            .VerticalAlignment("Center")
            .IsDefault("False").IsCancel("False")
        editBtn.InjectResources(this._editBtnStyle)
    }

    _DisplayVal(raw) {
        if (raw == "")
            return GetLang("无")
        return FormatHotkeyDisplay(raw)
    }

    LoadInitValues() {
        this._values := Map()
        for def in HotkeySettingGui.HotkeyDefs {
            field := def.Field
            this._values[field] := MainSoftData.HasProp(field) ? String(MainSoftData.%field%) : ""
        }
    }

    ApplyValuesToUI() {
        if (!IsObject(this.ui))
            return
        this._syncing := true
        try {
            for def in HotkeySettingGui.HotkeyDefs {
                val := this._values.Has(def.Field) ? this._values[def.Field] : ""
                this.ui.Update("Val_" def.Field, "Text", this._DisplayVal(val))
            }
        } finally {
            this._syncing := false
        }
    }

    OnEditHotkey(fieldName, onlyTrigger, state, ctrl, event) {
        if (this.closed || this._syncing)
            return
        cur := this._values.Has(fieldName) ? this._values[fieldName] : ""
        showCon := HotkeyValueHolder(cur)
        keyCon := HotkeyValueHolder(cur)

        AfterSure(*) {
            newVal := keyCon.Value
            this._values[fieldName] := newVal
            MainSoftData.%fieldName% := newVal
            try this.ui.Update("Val_" fieldName, "Text", this._DisplayVal(newVal))
            ; 子窗「确定」的 Enter 可能回传到本窗并触发默认按钮，短时忽略关闭
            this._ignoreConfirmUntil := A_TickCount + 500
            try WinActivate("ahk_id " this.ui.wpfHwnd)
        }

        MyEditHotkeyGui.AfterSureAction := AfterSure
        OnOpenEditHotkeyGui(showCon, keyCon, onlyTrigger)
    }

    OnRevertClick(state, ctrl, event) {
        if (this._ShouldIgnoreConfirm())
            return
        for def in HotkeySettingGui.HotkeyDefs {
            this._values[def.Field] := def.Default
            MainSoftData.%def.Field% := def.Default
        }
        this.ApplyValuesToUI()
    }

    OnConfirmClick(state, ctrl, event) {
        if (this._ShouldIgnoreConfirm())
            return
        for def in HotkeySettingGui.HotkeyDefs {
            if (this._values.Has(def.Field))
                MainSoftData.%def.Field% := this._values[def.Field]
        }
        this.ui.Update("Window", "Close", "")
    }

    _ShouldIgnoreConfirm() {
        return A_TickCount < this._ignoreConfirmUntil
    }

    OnCancelClick(state, ctrl, event) {
        this.ui.Update("Window", "Close", "")
    }

    OnWindowClosing(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        XamlUiDiag("OnWindowClosing hwnd=" hwnd, "Hotkey")
        this.closed := true
        HotkeySettingGui._opening := false
        MyEditHotkeyGui.AfterSureAction := ""
        if (this._instanceKey != "" && HotkeySettingGui.instances.Has(this._instanceKey))
            HotkeySettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
        XamlUiDiagDaemon("Hotkey.afterClose")
    }

    OnWindowLoad(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        XamlUiDiag("OnWindowLoad enter hwnd=" hwnd, "Hotkey")
        try {
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
            this.ApplyValuesToUI()
        } catch as e {
            XamlUiDiag("OnWindowLoad err: " e.Message, "Hotkey")
        } finally {
            try this.ui.Update("Window", "Opacity", "1")
            XamlUiDiagWindow(hwnd, "Hotkey.loaded", true)
        }
    }

    Close() {
        this.closed := true
        MyEditHotkeyGui.AfterSureAction := ""
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }
}
