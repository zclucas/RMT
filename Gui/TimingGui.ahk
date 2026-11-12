#Requires AutoHotkey v2.0

; 定时宏编辑器：XAML，颜色跟随通用主题
class TimingGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.closed := true
        this._instanceKey := ""
        this.Data := ""
        this.SerialStr := ""
        this.tableItem := ""
        this.itemIndex := 0
        this._typeIndex := 1
        this._unitIndex := 2
        this._startText := ""
        this._endText := ""
        this._endEnabled := false
        this._intervalText := "10"
        this._durationModeIndex := 1
        this._durationText := "10"
        this._durationUnitIndex := 2
        this._btnStyle := ""
        this._editBtnStyle := ""
        this._pickerGui := ""
    }

    ShowGui(SerialStr, tableItem := "", index := 0) {
        if (SerialStr == "" || !RegExMatch(SerialStr, "^Timing\d+$"))
            SerialStr := GetCMDSerialStr("Timing")
        this.SerialStr := SerialStr
        this.Data := this.GetTimingData(this.SerialStr)
        this.tableItem := tableItem
        this.itemIndex := index
        this._LoadDataToFields()

        key := "timing"
        if (TimingGui.instances.Has(key)) {
            oldInst := TimingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                oldInst.SerialStr := this.SerialStr
                oldInst.Data := this.Data
                oldInst.tableItem := tableItem
                oldInst.itemIndex := index
                oldInst._LoadDataToFields()
                oldInst._ApplyValuesToUI()
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            TimingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (TimingGui._opening)
            return
        TimingGui._opening := true
        try {
            this._instanceKey := key
            this._BuildAndShow()
            TimingGui.instances[key] := this
        } finally {
            TimingGui._opening := false
        }
    }

    _LoadDataToFields() {
        this._startText := this._FormatStamp(this.Data.StartStamp)
        this._endEnabled := this.Data.HasOwnProp("EndStamp") && this.Data.EndStamp
        this._endText := this._endEnabled
            ? this._FormatStamp(this.Data.EndStamp)
            : this._DefaultEndText()

        this._typeIndex := CmdEnumIndex(CmdEnumTimingType(this.Data.Type), CmdEnumTimingTypeNames()) + 1

        this._intervalText := String(this.Data.HasOwnProp("CustomInterval") ? this.Data.CustomInterval : "10")

        this._unitIndex := CmdEnumIndex(this.Data.HasOwnProp("CustomUnit") ? this.Data.CustomUnit : "分钟", CmdEnumTimingUnitNames()) + 1

        durationMode := this.Data.HasOwnProp("DurationMode") ? this.Data.DurationMode : "无限制"
        this._durationModeIndex := CmdEnumIndex(durationMode, CmdEnumTimingDurationNames()) + 1
        this._durationText := String(this.Data.HasOwnProp("Duration") ? this.Data.Duration : "10")
        this._durationUnitIndex := CmdEnumIndex(this.Data.HasOwnProp("DurationUnit") ? this.Data.DurationUnit : "分钟", CmdEnumTimingUnitNames()) + 1
    }

    _DefaultEndText() {
        return FormatTime(DateAdd(A_Now, 2, "Hours"), "yyyy-MM-dd HH:mm:ss")
    }

    _FormatStamp(stamp) {
        if (!stamp)
            return FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        return FormatTime(StampToTimeStr(stamp), "yyyy-MM-dd HH:mm:ss")
    }

    _ParseTimeText(text) {
        t := RegExReplace(Trim(String(text)), "[^\d]", "")
        return (StrLen(t) == 14) ? t : ""
    }

    _NormalizeTimeInput(text, minVal, maxVal, fallback := "00") {
        t := RegExReplace(Trim(String(text)), "[^\d]", "")
        if (t = "")
            return fallback
        n := Integer(t)
        if (n < minVal)
            n := minVal
        else if (n > maxVal)
            n := maxVal
        return Format("{:02}", n)
    }

    _ResolveComboIndex(text, names, fallback := 1) {
        t := Trim(String(text))
        if (t = "")
            return fallback

        loop names.Length {
            if (t = names[A_Index])
                return A_Index
        }

        if RegExMatch(t, "^\d+$") {
            n := Integer(t)
            if (n >= 1 && n <= names.Length)
                return n
        }

        return fallback
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("定时编辑器")
        titleHeight := "30"
        winW := 740
        winH := 270
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        this._editBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,10,16,8")

        timeBoxW := "176"
        labelW := "78"
        sideLabelW := "78"
        modeW := "132"
        unitNames := GetLangArr(["秒", "分钟", "小时", "天", "周", "月"])
        rowGap := "0,0,0,10"

        ; 列2与开始时间的日期按钮同列，每次间隔、时长从这一列起排
        form := body.Add("Grid")
        form.Rows("Auto", "Auto", "Auto", "Auto")
        form.Cols(labelW, timeBoxW, "Auto", "Auto", "Auto", timeBoxW, "Auto", "Auto")

        this._AddFormLabel(form, "", GetLang("开始时间："), labelW, "0,0,4,10")
            .Grid_Row(0).Grid_Column(0)
        this._AddTextBox(form, "StartTimeCon", "", timeBoxW, true, true, "2,0")
            .Grid_Row(0).Grid_Column(1).Margin(rowGap)
        this._AddCalButton(form, "BtnStartCal", "")
            .Grid_Row(0).Grid_Column(2).Margin("6,0,0,10")
        form.Add("CheckBox").Name("EndEnableCon").Content("")
            .VerticalAlignment("Center").Margin("36,0,2,10")
            .Foreground("{DynamicResource TextMain}")
            .Grid_Row(0).Grid_Column(3)
        this._AddFormLabel(form, "EndLabelCon", GetLang("结束时间："), "", "0,0,4,10")
            .Grid_Row(0).Grid_Column(4)
        this._AddTextBox(form, "EndTimeCon", "", timeBoxW, true, true, "2,0")
            .Grid_Row(0).Grid_Column(5).Margin(rowGap)
        this._AddCalButton(form, "BtnEndCal", "BtnEndCalIcon")
            .Grid_Row(0).Grid_Column(6).Margin("6,0,0,10")
        helpBtn := form.Add("Button").Name("BtnEndHelp").Content("?")
            .Width(28).Height(26).MinHeight(26).Margin("6,0,0,10").Cursor("Hand").FontSize(13)
            .VerticalAlignment("Center")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .Grid_Row(0).Grid_Column(7)
        helpBtn.InjectResources(this._editBtnStyle)

        this._AddFormLabel(form, "", GetLang("触发类型："), labelW, "0,0,4,10")
            .Grid_Row(1).Grid_Column(0)
        this._AddCombo(form, "TypeCon", modeW, rowGap, GetLangArr(["单次", "软件启动时", "周期触发"]))
            .Grid_Row(1).Grid_Column(1).HorizontalAlignment("Left")
        intervalPanel := form.Add("StackPanel").Name("IntervalPanel").Orientation("Horizontal")
            .Visibility("Collapsed").VerticalAlignment("Center")
            .Grid_Row(1).Grid_Column(2).Grid_ColumnSpan(6).Margin(rowGap)
        this._AddFormLabel(intervalPanel, "IntervalLabel", GetLang("每次间隔："), sideLabelW, "6,0,4,0")
        this._AddTextBox(intervalPanel, "IntervalCon", "10", "70", false, false, "2,0")
        this._AddCombo(intervalPanel, "UnitCon", "82", "6,0,0,0", unitNames)

        this._AddFormLabel(form, "", GetLang("任务时长："), labelW, "0,0,4,10")
            .Grid_Row(2).Grid_Column(0)
        this._AddCombo(form, "DurationModeCon", modeW, rowGap, GetLangArr(["无限制", "固定时长"]))
            .Grid_Row(2).Grid_Column(1).HorizontalAlignment("Left")
        durationPanel := form.Add("StackPanel").Name("DurationPanel").Orientation("Horizontal")
            .Visibility("Collapsed").VerticalAlignment("Center")
            .Grid_Row(2).Grid_Column(2).Grid_ColumnSpan(6).Margin(rowGap)
        this._AddFormLabel(durationPanel, "", GetLang("时长："), sideLabelW, "6,0,4,0")
        this._AddTextBox(durationPanel, "DurationCon", "10", "70", false, false, "2,0")
        this._AddCombo(durationPanel, "DurationUnitCon", "82", "6,0,0,0", unitNames)

        form.Add("TextBlock").Name("NextTriggerTip").Text("")
            .Foreground("{DynamicResource TextSub}").FontSize(12).TextWrapping("Wrap")
            .Margin("0,2,0,0").Grid_Row(3).Grid_Column(0).Grid_ColumnSpan(8)

        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,16,0,0")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(90).Height(32)
        okBtn.InjectResources(this._btnStyle)

        pos := GetCenterPosOnActiveMonitor(winW, winH)
        dipX := PhysToDip(pos.x)
        dipY := PhysToDip(pos.y)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="{}" ShowInTaskbar="False" Width="{}" Height="{}" Left="{}" Top="{}"',
                title, winW, winH, dipX, dipY))
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        ; 输入框和下拉框统一使用 1 DIP 的像素对齐边框
        inputChrome := '<CornerRadius x:Key="PanelRadius">8</CornerRadius>'
        inputChrome .= '<Style TargetType="CheckBox"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><BulletDecorator Background="Transparent"><BulletDecorator.Bullet><Border Width="18" Height="18" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" CornerRadius="3" SnapsToDevicePixels="True"><Path x:Name="Tick" Data="M 3 8 L 7 12 L 14 4" Stroke="{DynamicResource TextMain}" StrokeThickness="2" Visibility="Collapsed"/></Border></BulletDecorator.Bullet><ContentPresenter Margin="2,0,0,0" VerticalAlignment="Center"/></BulletDecorator><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Tick" Property="Visibility" Value="Visible"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        inputChrome .= '<Style TargetType="TextBox"><Setter Property="UseLayoutRounding" Value="True"/><Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True"><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Stretch"/></Border></ControlTemplate></Setter.Value></Setter></Style>'
        inputChrome .= '<Style TargetType="ComboBox"><Setter Property="Padding" Value="6,0,18,0"/><Setter Property="UseLayoutRounding" Value="True"/><Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><ToggleButton x:Name="ToggleButton" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Focusable="false" IsChecked="{Binding Path=IsDropDownOpen,Mode=TwoWay,RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True"><Path Fill="{DynamicResource TextMain}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0" Data="M 0 0 L 4 4 L 8 0 Z"/></Border></ControlTemplate></ToggleButton.Template></ToggleButton><ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"/><TextBox x:Name="PART_EditableTextBox" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="{TemplateBinding Padding}" Focusable="True" Background="Transparent" Foreground="{TemplateBinding Foreground}" BorderThickness="0" Visibility="Hidden" IsReadOnly="{TemplateBinding IsReadOnly}"/><Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide"><Border x:Name="DropDownBorder" Background="{DynamicResource DropdownBg}" BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="3" Margin="0,4,0,0" Width="{Binding ActualWidth, ElementName=ToggleButton}" MaxHeight="350"><ScrollViewer Margin="0" SnapsToDevicePixels="True" Tag="ContainScroll"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid></ControlTemplate></Setter.Value></Setter></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', inputChrome)

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this.ui.OnEvent("BtnStartCal", "Click", ObjBindMethod(this, "OnStartCalClick"))
        this.ui.OnEvent("BtnEndCal", "Click", ObjBindMethod(this, "OnEndCalClick"))
        this.ui.OnEvent("BtnEndHelp", "Click", ObjBindMethod(this, "OnEndHelpClick"))
        this.ui.Track("StartTimeCon")
        this.ui.Track("EndTimeCon")
        this.ui.Track("EndEnableCon")
        this.ui.Track("TypeCon")
        this.ui.Track("IntervalCon")
        this.ui.Track("UnitCon")
        this.ui.Track("DurationModeCon")
        this.ui.Track("DurationCon")
        this.ui.Track("DurationUnitCon")
        this.ui.OnEvent("TypeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("TypeCon", "DropDownClosed", ObjBindMethod(this, "OnChangeType"))
        this.ui.OnEvent("DurationModeCon", "SelectionChanged", ObjBindMethod(this, "OnChangeDurationMode"))
        this.ui.OnEvent("DurationModeCon", "DropDownClosed", ObjBindMethod(this, "OnChangeDurationMode"))
        this.ui.OnEvent("IntervalCon", "TextChanged", ObjBindMethod(this, "OnTimingFieldChanged"))
        this.ui.OnEvent("UnitCon", "SelectionChanged", ObjBindMethod(this, "OnTimingFieldChanged"))
        this.ui.OnEvent("UnitCon", "DropDownClosed", ObjBindMethod(this, "OnTimingFieldChanged"))
        this.ui.OnEvent("EndEnableCon", "Checked", ObjBindMethod(this, "OnEndEnableChanged"))
        this.ui.OnEvent("EndEnableCon", "Unchecked", ObjBindMethod(this, "OnEndEnableChanged"))

        this._ApplyValuesToUI()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _AddTextBox(parent, name, text, width, readOnly := false, centerText := false, padding := "6,0") {
        tb := parent.Add("TextBox").Name(name).Text(text).Height(30).MinHeight(30)
            .FontSize(12).FontFamily(MainSoftData.FontType)
            .VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Padding(padding)
        if (width != "*")
            tb.Width(width)
        if (readOnly)
            tb.IsReadOnly("True")
        if (centerText)
            tb.TextAlignment("Center")
        return tb
    }

    _AddFormLabel(parent, name, text, width, margin) {
        tb := parent.Add("TextBlock").Text(text)
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Margin(margin)
        if (name != "")
            tb.Name(name)
        if (width != "")
            tb.Width(width)
        return tb
    }

    _AddCalButton(parent, name, iconName) {
        btn := parent.Add("Button").Name(name)
            .Width(28).Height(26).MinHeight(26).Margin("6,0,0,0").Cursor("Hand")
            .VerticalAlignment("Center")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
        btn.InjectResources(this._editBtnStyle)
        icon := btn.Add("TextBlock").Text(Chr(0xE787)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            .FontSize(12).HorizontalAlignment("Center").VerticalAlignment("Center")
        if (iconName != "")
            icon.Name(iconName)
        return btn
    }

    _AddCombo(parent, name, width, margin, names) {
        cmb := parent.Add("ComboBox").Name(name).Width(width).Height(30).MinHeight(30)
            .Margin(margin).VerticalAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .IsEditable("False")
        for n in names
            cmb.Add("ComboBoxItem").Content(n)
        return cmb
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this._ClosePicker()
        this.closed := true
        TimingGui._opening := false
        if (this._instanceKey != "" && TimingGui.instances.Has(this._instanceKey))
            TimingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnCloseClick(state := unset, ctrl := unset, event := unset) {
        this.Close()
    }

    Close() {
        this._ClosePicker()
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    _ClosePicker() {
        if (IsObject(this._pickerGui)) {
            try this._pickerGui.Update("Window", "Close", "")
            this._pickerGui := ""
        }
    }

    _ApplyValuesToUI() {
        if (!IsObject(this.ui) || this.closed)
            return

        typeNames := GetLangArr(["单次", "软件启动时", "周期触发"])
        unitNames := GetLangArr(["秒", "分钟", "小时", "天", "周", "月"])
        durationNames := GetLangArr(["无限制", "固定时长"])

        try this.ui.Update("StartTimeCon", "Text", this._startText)
        try this.ui.Update("EndTimeCon", "Text", this._endText)
        try this.ui.Update("EndEnableCon", "IsChecked", this._endEnabled ? "True" : "False")
        try this.ui.Update("IntervalCon", "Text", this._intervalText)
        try this.ui.Update("DurationCon", "Text", this._durationText)

        try this.ui.Update("TypeCon", "Text", typeNames[this._typeIndex])
        try this.ui.Update("TypeCon", "SelectedIndex", this._typeIndex - 1)
        try this.ui.Update("UnitCon", "Text", unitNames[this._unitIndex])
        try this.ui.Update("UnitCon", "SelectedIndex", this._unitIndex - 1)
        try this.ui.Update("DurationModeCon", "Text", durationNames[this._durationModeIndex])
        try this.ui.Update("DurationModeCon", "SelectedIndex", this._durationModeIndex - 1)
        try this.ui.Update("DurationUnitCon", "Text", unitNames[this._durationUnitIndex])
        try this.ui.Update("DurationUnitCon", "SelectedIndex", this._durationUnitIndex - 1)

        this._RefreshIntervalVisibility()
        this._RefreshDurationVisibility()
        this._RefreshEndEnabled()
        this._RefreshNextTriggerTip()
    }

    OnChangeType(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        this._RefreshIntervalVisibility()
        this._RefreshNextTriggerTip()
    }

    OnTimingFieldChanged(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        this._RefreshNextTriggerTip()
    }

    OnChangeDurationMode(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        this._RefreshDurationVisibility()
    }

    OnEndEnableChanged(state := unset, ctrl := unset, event := unset) {
        enabled := this._endEnabled
        if (IsSet(state) && IsObject(state) && state.Has("EndEnableCon"))
            enabled := (state["EndEnableCon"] = "True" || state["EndEnableCon"] = "true" || state["EndEnableCon"] = "1")
        else if (IsObject(this.ui)) {
            v := this.ui.Query("EndEnableCon")
            enabled := (v = "True" || v = "true" || v = "1")
        }
        this._endEnabled := enabled
        if (enabled && Trim(this._endText) == "") {
            this._endText := this._DefaultEndText()
            try this.ui.Update("EndTimeCon", "Text", this._endText)
        }
        this._RefreshEndEnabled()
        this._RefreshNextTriggerTip()
    }

    _RefreshIntervalVisibility() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("IntervalPanel", "Visibility", this._typeIndex == 3 ? "Visible" : "Collapsed")
    }

    _RefreshDurationVisibility() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("DurationPanel", "Visibility", this._durationModeIndex == 2 ? "Visible" : "Collapsed")
    }

    _RefreshNextTriggerTip() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("NextTriggerTip", "Text", this._DescribeNextTrigger())
    }

    _DescribeNextTrigger() {
        block := this._TriggerBlockReason()
        if (block != "")
            return GetLang("不会触发：") block

        typeName := CmdEnumFromIndex(this._typeIndex - 1, CmdEnumTimingTypeNames())
        if (typeName == "软件启动时")
            return this._WithFrontNote(GetLang("下次触发时间：") GetLang("软件启动时"))

        startRaw := this._ParseTimeText(this._startText)
        if (startRaw == "")
            return GetLang("不会触发：") GetLang("开始时间无效")

        Data := { StartStamp: TimeStrToStamp(startRaw), Type: typeName, CustomInterval: this._intervalText
            , CustomUnit: CmdEnumFromIndex(this._unitIndex - 1, CmdEnumTimingUnitNames()) }
        if (this._endEnabled) {
            endRaw := this._ParseTimeText(this._endText)
            if (endRaw == "")
                return GetLang("不会触发：") GetLang("结束时间无效")
            if (endRaw <= startRaw)
                return GetLang("不会触发：") GetLang("结束时间必须晚于开始时间")
            Data.EndStamp := TimeStrToStamp(endRaw)
        }

        if (typeName == "周期触发" && (!IsNumber(this._intervalText) || this._intervalText + 0 <= 0 || InStr(String(this._intervalText), ".")))
            return GetLang("不会触发：") GetLang("每次间隔需要是大于零的整数")

        now := UnixNow()
        next := 0
        try next := CalculateNextStamp(Data, now)
        if (next)
            return this._WithFrontNote(GetLang("下次触发时间：") this._FormatStamp(next))

        if (typeName == "单次")
            return GetLang("不会触发：") GetLang("开始时间已过，单次只会触发一次")
        return GetLang("不会触发：") GetLang("下一次触发不早于结束时间")
    }

    _TriggerBlockReason() {
        if (!IsObject(this.tableItem) || this.itemIndex < 1)
            return ""
        item := ""
        try item := this.tableItem.Items[this.itemIndex]
        if (!item)
            return ""
        if (item.Macro == "")
            return GetLang("宏内容为空")
        if (item.Forbid)
            return GetLang("该宏已禁用")
        if (GetItemFoldForbidState(this.tableItem, this.itemIndex))
            return GetLang("所属模块已禁用")
        return ""
    }

    _WithFrontNote(text) {
        if (!IsObject(this.tableItem) || this.itemIndex < 1)
            return text
        front := ""
        try front := GetItemModuleWindowBinding(this.tableItem, this.itemIndex)
        if (front == "")
            return text
        return text GetLang("（仅指定前台窗口匹配时触发）")
    }

    _RefreshEndEnabled() {
        if (!IsObject(this.ui))
            return
        ; 自定义模板无 IsEnabled 灰显样式，需同步 Opacity / Foreground；问号始终可点
        if (this._endEnabled) {
            try this.ui.Update("EndLabelCon", "Foreground", "{DynamicResource TextMain}")
            try this.ui.Update("EndLabelCon", "Opacity", "1")
            try this.ui.Update("EndTimeCon", "IsEnabled", "True")
            try this.ui.Update("EndTimeCon", "Opacity", "1")
            try this.ui.Update("EndTimeCon", "Foreground", "{DynamicResource InputText}")
            try this.ui.Update("BtnEndCal", "IsEnabled", "True")
            try this.ui.Update("BtnEndCal", "Opacity", "1")
            try this.ui.Update("BtnEndCalIcon", "Opacity", "1")
        } else {
            try this.ui.Update("EndLabelCon", "Foreground", "{DynamicResource TextSub}")
            try this.ui.Update("EndLabelCon", "Opacity", "0.55")
            try this.ui.Update("EndTimeCon", "IsEnabled", "False")
            try this.ui.Update("EndTimeCon", "Opacity", "0.45")
            try this.ui.Update("EndTimeCon", "Foreground", "{DynamicResource TextSub}")
            try this.ui.Update("BtnEndCal", "IsEnabled", "False")
            try this.ui.Update("BtnEndCal", "Opacity", "0.45")
            try this.ui.Update("BtnEndCalIcon", "Opacity", "0.45")
        }
        try this.ui.Update("BtnEndHelp", "IsEnabled", "True")
        try this.ui.Update("BtnEndHelp", "Opacity", "1")
    }

    OnStartCalClick(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        this._ShowDateTimePicker("start", this._startText)
    }

    OnEndCalClick(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        if (!this._endEnabled)
            return
        seed := this._endText != "" ? this._endText : this._DefaultEndText()
        this._ShowDateTimePicker("end", seed)
    }

    OnEndHelpClick(state := unset, ctrl := unset, event := unset) {
        ; 无 Icon，避免系统提示音；内容两行显示
        RmtDialog.Info(GetLang("勾选后，到达结束时间将不再触发此定时宏；") "`n" GetLang("若宏正在运行也会被停止。"), GetLang("结束时间："))
    }

    _ShowDateTimePicker(which, currentText) {
        this._ClosePicker()
        owner := 0
        if (IsObject(this.ui) && this.ui.HasProp("wpfHwnd"))
            owner := this.ui.wpfHwnd

        year := FormatTime(A_Now, "yyyy")
        month := FormatTime(A_Now, "MM")
        day := FormatTime(A_Now, "dd")
        hour := FormatTime(A_Now, "HH")
        minute := FormatTime(A_Now, "mm")
        second := FormatTime(A_Now, "ss")

        raw := this._ParseTimeText(currentText)
        if (raw != "" && StrLen(raw) == 14) {
            year := SubStr(raw, 1, 4)
            month := SubStr(raw, 5, 2)
            day := SubStr(raw, 7, 2)
            hour := SubStr(raw, 9, 2)
            minute := SubStr(raw, 11, 2)
            second := SubStr(raw, 13, 2)
        }

        dateStr := year "-" month "-" day

        title := GetLang("选择时间")
        titleHeight := "30"
        winW := 320
        winH := 400

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClosePicker")

        body := main.Add("StackPanel").Grid_Row(1).Margin("15,8,15,8")

        body.Add("Calendar").Name("CalendarCon").HorizontalAlignment("Center").BorderThickness(0).Background("Transparent").Margin("0,0,0,8")
        body.Add("TextBlock").Name("HiddenDateText").SetMarkup("Text", "{Binding SelectedDate, ElementName=CalendarCon, StringFormat='{}{0:yyyy-MM-dd}'}").Visibility("Collapsed")

        timeGrid := body.Add("Grid").Margin("0,8,0,8").HorizontalAlignment("Center")
        timeGrid.Cols("Auto", "5", "62", "3", "62", "3", "62")

        timeGrid.Add("TextBlock").Text(GetLang("时间：")).Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").Grid_Column(0)

        hourCmb := timeGrid.Add("ComboBox").Name("HourCon").Height(26).MinHeight(26).Grid_Column(2)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalAlignment("Center")
            .IsEditable("True")
        loop 24 {
            v := Format("{:02}", A_Index - 1)
            hourCmb.Add("ComboBoxItem").Content(v)
        }

        timeGrid.Add("TextBlock").Text(":").Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").HorizontalAlignment("Center").Grid_Column(3)

        minCmb := timeGrid.Add("ComboBox").Name("MinCon").Height(26).MinHeight(26).Grid_Column(4)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalAlignment("Center")
            .IsEditable("True")
        loop 60 {
            v := Format("{:02}", A_Index - 1)
            minCmb.Add("ComboBoxItem").Content(v)
        }

        timeGrid.Add("TextBlock").Text(":").Foreground("{DynamicResource TextMain}").FontSize(13).VerticalAlignment("Center").HorizontalAlignment("Center").Grid_Column(5)

        secCmb := timeGrid.Add("ComboBox").Name("SecCon").Height(26).MinHeight(26).Grid_Column(6)
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalAlignment("Center")
            .IsEditable("True")
        loop 60 {
            v := Format("{:02}", A_Index - 1)
            secCmb.Add("ComboBoxItem").Content(v)
        }

        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,12,0,0")

        okBtn := btnRow.Add("Button").Name("BtnPickerConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").FontWeight("Bold")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .FontSize(12).Cursor("Hand").Width(80).Height(28).Margin("0,0,10,0")
        okBtn.InjectResources(this._btnStyle)

        cancelBtn := btnRow.Add("Button").Name("BtnPickerCancel").Content(GetLang("取消"))
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(12).Cursor("Hand").Width(80).Height(28)
        cancelBtn.InjectResources(this._editBtnStyle)

        pos := GetCenterPosOnActiveMonitor(winW, winH)
        dipX := PhysToDip(pos.x)
        dipY := PhysToDip(pos.y)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)

        picker := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        picker.xaml := StrReplace(picker.xaml, 'Width="940" Height="700"',
            Format('Title="{}" ShowInTaskbar="False" Width="{}" Height="{}" Left="{}" Top="{}"',
                title, winW, winH, dipX, dipY))
        picker.xaml := StrReplace(picker.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        picker.xaml := StrReplace(picker.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        picker.xaml := StrReplace(picker.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        picker.xaml := StrReplace(picker.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        picker.OnEvent("Window", "Closing", ObjBindMethod(this, "_OnPickerClosing"))
        picker.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "_OnPickerLoad", dateStr, hour, minute, second))
        picker.OnEvent("BtnClosePicker", "Click", ObjBindMethod(this, "_OnPickerCancelClick"))
        picker.OnEvent("BtnPickerConfirm", "Click", ObjBindMethod(this, "_OnPickerConfirmClick", which))
        picker.OnEvent("BtnPickerCancel", "Click", ObjBindMethod(this, "_OnPickerCancelClick"))
        picker.Track("HiddenDateText")
        picker.Track("HourCon")
        picker.Track("MinCon")
        picker.Track("SecCon")

        this._pickerGui := picker
        XamlWin.Open(picker, ObjBindMethod(this, "_FillPicker", dateStr, hour, minute, second))
    }

    _OnPickerClosing(state := unset, ctrl := unset, event := unset) {
        this._pickerGui := ""
    }

    _FillPicker(dateStr, hour, minute, second) {
        if (!IsObject(this._pickerGui))
            return
        this._pickerGui.Update("CalendarCon", "SelectedDate", dateStr)
        this._pickerGui.Update("CalendarCon", "DisplayDate", dateStr)
        this._pickerGui.Update("HourCon", "Text", Format("{:02}", Integer(hour)))
        this._pickerGui.Update("MinCon", "Text", Format("{:02}", Integer(minute)))
        this._pickerGui.Update("SecCon", "Text", Format("{:02}", Integer(second)))
        this._pickerGui.Update("HourCon", "SelectedIndex", String(Integer(hour)))
        this._pickerGui.Update("MinCon", "SelectedIndex", String(Integer(minute)))
        this._pickerGui.Update("SecCon", "SelectedIndex", String(Integer(second)))
    }

    _OnPickerLoad(dateStr, hour, minute, second, state := unset, ctrl := unset, event := unset) {
        XamlWin.OnLoadTheme(this._pickerGui)
    }

    _OnPickerConfirmClick(which, state := unset, ctrl := unset, event := unset) {
        dateVal := this._pickerGui.Query("HiddenDateText")
        hText := this._pickerGui.Query("HourCon")
        mText := this._pickerGui.Query("MinCon")
        sText := this._pickerGui.Query("SecCon")

        if (dateVal == "")
            dateVal := FormatTime(A_Now, "yyyy-MM-dd")

        hStr := this._NormalizeTimeInput(hText, 0, 23, "00")
        mStr := this._NormalizeTimeInput(mText, 0, 59, "00")
        sStr := this._NormalizeTimeInput(sText, 0, 59, "00")

        text := dateVal " " hStr ":" mStr ":" sStr

        if (which == "start") {
            this._startText := text
            try this.ui.Update("StartTimeCon", "Text", text)
        } else {
            this._endText := text
            this._endEnabled := true
            try this.ui.Update("EndTimeCon", "Text", text)
            try this.ui.Update("EndEnableCon", "IsChecked", "True")
            this._RefreshEndEnabled()
        }
        this._RefreshNextTriggerTip()
        this._ClosePicker()
    }

    _OnPickerCancelClick(state := unset, ctrl := unset, event := unset) {
        this._ClosePicker()
    }

    _ReadUIState(state := unset) {
        if (IsSet(state) && IsObject(state)) {
            if (state.Has("StartTimeCon"))
                this._startText := state["StartTimeCon"]
            if (state.Has("EndTimeCon"))
                this._endText := state["EndTimeCon"]
            if (state.Has("IntervalCon"))
                this._intervalText := state["IntervalCon"]
            if (state.Has("DurationCon"))
                this._durationText := state["DurationCon"]
            if (state.Has("EndEnableCon"))
                this._endEnabled := (state["EndEnableCon"] = "True" || state["EndEnableCon"] = "true" || state["EndEnableCon"] = "1")
            if (state.Has("TypeCon") && state["TypeCon"] != "")
                this._typeIndex := this._MatchNameIndex(state["TypeCon"], GetLangArr(["单次", "软件启动时", "周期触发"]), this._typeIndex)
            if (state.Has("UnitCon") && state["UnitCon"] != "")
                this._unitIndex := this._MatchNameIndex(state["UnitCon"], GetLangArr(["秒", "分钟", "小时", "天", "周", "月"]), this._unitIndex)
            if (state.Has("DurationModeCon") && state["DurationModeCon"] != "")
                this._durationModeIndex := this._MatchNameIndex(state["DurationModeCon"], GetLangArr(["无限制", "固定时长"]), this._durationModeIndex)
            if (state.Has("DurationUnitCon") && state["DurationUnitCon"] != "")
                this._durationUnitIndex := this._MatchNameIndex(state["DurationUnitCon"], GetLangArr(["秒", "分钟", "小时", "天", "周", "月"]), this._durationUnitIndex)
        }
        if (IsObject(this.ui)) {
            v := this.ui.Query("StartTimeCon")
            if (v != "")
                this._startText := v
            v := this.ui.Query("EndTimeCon")
            this._endText := v
            v := this.ui.Query("IntervalCon")
            if (v != "")
                this._intervalText := v
            v := this.ui.Query("DurationCon")
            if (v != "")
                this._durationText := v
            v := this.ui.Query("EndEnableCon")
            if (v != "")
                this._endEnabled := (v = "True" || v = "true" || v = "1")
            this._typeIndex := this._QueryComboIndex("TypeCon", this._typeIndex)
            this._unitIndex := this._QueryComboIndex("UnitCon", this._unitIndex)
            this._durationModeIndex := this._QueryComboIndex("DurationModeCon", this._durationModeIndex)
            this._durationUnitIndex := this._QueryComboIndex("DurationUnitCon", this._durationUnitIndex)
        }
    }

    _MatchNameIndex(text, names, fallback) {
        loop names.Length {
            if (text == names[A_Index])
                return A_Index
        }
        return fallback
    }

    _QueryComboIndex(name, fallback) {
        idx := this.ui.Query(name ">SelectedIndex")
        if (idx != "" && IsNumber(idx))
            return Integer(idx) + 1
        return fallback
    }

    _CheckPositiveInt(text, emptyMsg, decimalMsg) {
        if (!IsNumber(text) || text + 0 <= 0) {
            RmtDialog.Info(GetLang(emptyMsg))
            return false
        }
        if (InStr(String(text), ".")) {
            RmtDialog.Info(GetLang(decimalMsg))
            return false
        }
        return true
    }

    CheckIfValid() {
        startRaw := this._ParseTimeText(this._startText)
        if (startRaw == "") {
            RmtDialog.Info(GetLang("请输入正确的开始时间（yyyy-MM-dd HH:mm:ss）"))
            return false
        }
        if (this._endEnabled) {
            endRaw := this._ParseTimeText(this._endText)
            if (endRaw == "") {
                RmtDialog.Info(GetLang("请输入正确的结束时间（yyyy-MM-dd HH:mm:ss）"))
                return false
            }
            if (endRaw <= startRaw) {
                RmtDialog.Info(GetLang("勾选结束时间后，结束时间必须大于开始时间！！！"))
                return false
            }
        }
        if (this._typeIndex == 3) {
            if (!this._CheckPositiveInt(this._intervalText, "每次间隔需要输入大于零的数字！！！", "每次间隔时间只能是整数！！"))
                return false
        }
        if (this._durationModeIndex == 2) {
            if (!this._CheckPositiveInt(this._durationText, "时长需要输入大于零的数字！！！", "时长只能是整数！！"))
                return false
        }
        return true
    }

    OnSureBtnClick(state := unset, ctrl := unset, event := unset) {
        this._ReadUIState(IsSet(state) ? state : unset)
        if (!this.CheckIfValid())
            return
        this.SaveTimingData()
        this._RefreshOwnerRow()
        this.Close()
    }

    _RefreshOwnerRow() {
        if (!IsObject(this.tableItem) || this.itemIndex < 1)
            return
        if (IsSet(MyMainWin) && IsObject(MyMainWin))
            MyMainWin.RefreshItemRow(this.tableItem.Index, this.itemIndex)
    }

    SaveTimingData() {
        Data := this.Data
        startRaw := this._ParseTimeText(this._startText)
        endRaw := ""
        if (this._endEnabled)
            endRaw := this._ParseTimeText(this._endText)
        Data.StartStamp := TimeStrToStamp(startRaw)
        Data.EndStamp := endRaw == "" ? 0 : TimeStrToStamp(endRaw)
        Data.Type := CmdEnumFromIndex(this._typeIndex - 1, CmdEnumTimingTypeNames())
        Data.CustomInterval := this._intervalText
        Data.CustomUnit := CmdEnumFromIndex(this._unitIndex - 1, CmdEnumTimingUnitNames())
        Data.DurationMode := CmdEnumFromIndex(this._durationModeIndex - 1, CmdEnumTimingDurationNames())
        Data.Duration := this._durationText
        Data.DurationUnit := CmdEnumFromIndex(this._durationUnitIndex - 1, CmdEnumTimingUnitNames())

        minimal := {}
        minimal.SerialStr := Data.SerialStr
        minimal.StartStamp := Data.StartStamp
        minimal.StampUnit := "ms"
        minimal.Type := Data.Type
        if (Data.EndStamp)
            minimal.EndStamp := Data.EndStamp
        if (Data.Type == "周期触发") {
            minimal.CustomInterval := Data.CustomInterval
            minimal.CustomUnit := Data.CustomUnit
        }
        minimal.DurationMode := Data.DurationMode
        minimal.Duration := Data.Duration
        minimal.DurationUnit := Data.DurationUnit

        saveStr := JSON.stringify(minimal, 0)
        CfgWrite(saveStr, TimingFile, SettingSection, Data.SerialStr)
        if (MySoftData.DataCacheMap.Has(Data.SerialStr))
            MySoftData.DataCacheMap.Delete(Data.SerialStr)
        ; §18 定时参数即时生效：广播 Timing 表整表变更 → TimingScheduler 订阅者空闲重建调度堆（不必等保存选「否」）
        t := GetTableBySymbol("Timing")
        if (t)
            HotReloadPublish(t.Index, 0)
    }

    GetTimingData(SerialStr) {
        saveStr := CfgRead(TimingFile, SettingSection, SerialStr, "")
        if (!saveStr) {
            data := TimingData()
            data.SerialStr := SerialStr
            return data
        }
        data := JSON.parse(saveStr, , false)
        data.SerialStr := SerialStr
        return data
    }
}
