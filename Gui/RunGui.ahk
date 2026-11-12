#Requires AutoHotkey v2.0

; =====================================================================
; 运行编辑器 —— 简化版（备注 + 目标）
; 公开接口保持：ShowGui(cmd) / SureBtnAction / OwnerHwnd / ParentTile
; 完整模式/输入输出请用 RunProGui
; =====================================================================

class RunGui {
    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.Data := ""
        this.SerialStr := ""
    }

    ShowGui(cmd) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this._batching := true
        try this.Init(cmd)
        finally {
            this._flushBatch()
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        this.ToggleFunc(true)
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    static PresetGroups := [
        ["常用应用", [
            ["打开默认浏览器", "https://www.bing.com/"],
            ["打开文件资源管理器", "explorer.exe"],
            ["打开记事本", "notepad.exe"],
            ["打开计算器", "calc.exe"],
            ["打开命令提示符", "cmd.exe"],
            ["打开 PowerShell", "powershell.exe"],
            ["打开任务管理器", "taskmgr.exe"],
            ["打开截图工具", "ms-screenclip:"]
        ]],
        ["系统设置", [
            ["显示设置", "ms-settings:display"],
            ["声音设置", "ms-settings:sound"],
            ["蓝牙设置", "ms-settings:bluetooth"],
            ["Wi-Fi 设置", "ms-settings:network-wifi"],
            ["打印机和扫描仪", "ms-settings:printers"],
            ["Windows 更新", "ms-settings:windowsupdate"]
        ]],
        ["系统工具", [
            ["打开控制面板", "control.exe"],
            ["打开设备管理器", "devmgmt.msc"],
            ["打开服务管理器", "services.msc"],
            ["打开事件查看器", "eventvwr.msc"],
            ["打开资源监视器", "resmon.exe"]
        ]],
        ["网络诊断", [
            ["查看 IP 配置", "cmd.exe /d /k ipconfig /all"],
            ["测试网络连通性", "cmd.exe /d /k ping 1.1.1.1"],
            ["查询 DNS", "cmd.exe /d /k nslookup www.bing.com"],
            ["查看网络连接", "cmd.exe /d /k netstat -ano"]
        ]],
        ["电源", [
            ["30 秒后关机（强制关闭应用）", "shutdown.exe /s /t 30"],
            ["30 秒后重启（强制关闭应用）", "shutdown.exe /r /t 30"],
            ["取消定时关机或重启", "shutdown.exe /a"],
            ["休眠（需启用休眠）", "shutdown.exe /h"]
        ]]
    ]

    _ComboPush(comboName, propertyName, value) {
        if (this._batching)
            this._batch.Push({ControlName: comboName, PropertyName: propertyName, Value: value})
        else
            this.ui.Update(comboName, propertyName, value)
    }

    _flushBatch() {
        this._batching := false
        if (IsObject(this.ui) && this._batch.Length > 0) {
            this.ui.BatchUpdate(this._batch)
            this._batch := []
        }
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("运行编辑器")
        this._title := title
        titleHeight := XAMLHost.CmdTitleBarHeight()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("16,10,16,12")
        body.Rows("34", "34", "34", "22", "40")
        body.Cols("72", "*", "8", "88")

        body.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text(GetLang("备注：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(0).Grid_Column(1).Grid_ColumnSpan(3).Name("RemarkCon").Height(26).MinHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        body.Add("TextBlock").Grid_Row(1).Grid_Column(0).Text(GetLang("目标：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        body.Add("TextBox").Grid_Row(1).Grid_Column(1).Name("PathTextCon").Height(26).MinHeight(26).VerticalAlignment("Center")
            .VerticalContentAlignment("Center").FontSize("11").Padding("2,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        body.Add("Button").Grid_Row(1).Grid_Column(3).Name("BtnSelectFile").Content(GetLang("选择文件")).Height(26).MinHeight(26).VerticalAlignment("Center").HorizontalAlignment("Stretch").Cursor("Hand")

        body.Add("TextBlock").Grid_Row(2).Grid_Column(0).Text(GetLang("常用命令：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        presets := body.Add("ComboBox").Grid_Row(2).Grid_Column(1).Grid_ColumnSpan(3).Name("RunPresetCombo")
            .Height(26).MinHeight(26).VerticalAlignment("Center").MaxDropDownHeight(320).SelectedIndex(0)
        presets.Add("ComboBoxItem").Content(GetLang("选择命令填入目标"))
        this._presetTargets := []
        for group in RunGui.PresetGroups {
            for preset in group[2] {
                presets.Add("ComboBoxItem").Content(GetLang(group[1]) " · " GetLang(preset[1]))
                this._presetTargets.Push(preset[2])
            }
        }

        body.Add("TextBlock").Grid_Row(3).Grid_ColumnSpan(4).Text(GetLang("支持启动程序（如.exe、.bat）、打开文件（如.txt、.mp4）或网址等等"))
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize("11")

        btnRow := body.Add("StackPanel").Grid_Row(4).Grid_ColumnSpan(4).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        AddCmdOkBtn(btnRow)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="420" Height="224"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        BindCmdEditorChrome(this.ui, "#指令手册/16-运行", ObjBindMethod(this, "TriggerMacro"), "!l")
        this.ui.OnEvent("BtnSelectFile", "Click", ObjBindMethod(this, "OnClickFileSelectBtn"))
        this.ui.OnEvent("RunPresetCombo", "SelectionChanged", XamlWin.BindCurrent(this, "OnPresetSelected"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("运行")
        this.ui.Update("RemarkCon", "Text", cmdArr.Length >= 2 ? cmdArr[2] : "")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.ui.Update("PathTextCon", "Text", UnescapeVarText(this.Data.Target))
    }

    GetCommandStr() {
        textOnly := RTrim(this.Data.SerialStr, "0123456789")
        numbersOnly := SubStr(this.Data.SerialStr, StrLen(textOnly) + 1)
        commandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        commandStr := CorrectRemark(commandStr, this.ui.Query("RemarkCon"))
        return commandStr
    }

    ToggleFunc(state) {
        try Hotkey("!l", (*) => this.TriggerMacro(), state ? "On" : "Off")
    }

    OnPresetSelected(*) {
        index := this.ui.Query("RunPresetCombo>SelectedIndex")
        if (!IsInteger(index) || index < 1 || index > this._presetTargets.Length)
            return
        this.ui.BatchUpdate([
            {ControlName: "PathTextCon", PropertyName: "Text", Value: this._presetTargets[Integer(index)]},
            {ControlName: "RunPresetCombo", PropertyName: "SelectedIndex", Value: "0"}
        ])
    }

    OnClickFileSelectBtn(state := "", ctrl := "", event := "") {
        fileString := FileSelect("S1", "", GetLang("选择要运行的文件"))
        if (fileString == "")
            return
        this.ui.Update("PathTextCon", "Text", '"' fileString '"')
    }

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveRunData()
        this.ToggleFunc(false)
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this._CloseWindow()
    }

    CheckIfValid() {
        if (this.ui.Query("PathTextCon") == "") {
            RmtDialog.Info(GetLang("目标不能为空！"))
            return false
        }
        return true
    }

    TriggerMacro(state := "", ctrl := "", event := "") {
        this.SaveRunData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    SaveRunData() {
        this.Data.Target := SmartEscapeVarText(GetLangStr(this.ui.Query("PathTextCon"), 2))
        this.Data.Mode := 1
        this.Data.Option := 1
        if (ObjHasOwnProp(this.Data, "StdIn"))
            this.Data.DeleteProp("StdIn")
        if (ObjHasOwnProp(this.Data, "SaveNameArr"))
            this.Data.DeleteProp("SaveNameArr")
        if (ObjHasOwnProp(this.Data, "Encoding"))
            this.Data.DeleteProp("Encoding")
        SaveMacroCMDData(this.Data)
    }
}
