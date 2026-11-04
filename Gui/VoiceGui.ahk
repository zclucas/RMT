#Requires AutoHotkey v2.0

; =================================================================
; 语音触发配置窗口（VoiceGui）
; 为单条宏配置「语音唤醒关键词」（VoiceKeywordsArr[index]）。
; 启用/禁用由主界面的「禁用」开关控制（ForbidArr），此处不再提供开关。
; 识别与触发由 Main\Util\VoiceUtil.ahk 交给可替换的底层引擎（默认 sherpa-onnx KWS）。
; =================================================================

#Include ..\Main\Util\JsonUtil.ahk

class VoiceGui {
    __New() {
        this.Gui := ""
        this.ui := ""
        this.hasGui := false      ; 窗口是否存活（Gui 对象 Destroy 后仍非空，需独立标志）
        this.tableItem := ""
        this.index := 0
        this.SureBtnAction := ""
        this.keywords := []
        this._nextChipId := 0
        this._rec := false
        this._sttTick := ObjBindMethod(this, "_PollStt")
    }

    ; ShowGui(tableItem, index)
    ShowGui(tableItem, index, isUpdate := false) {
        if (!CheckIsItemTable(GetTableIndexByID(tableItem.ID)))
            return
        this.tableItem := tableItem
        this.index := index

        curKeywords := ""
        item := tableItem.Items[index]
        if (item)
            curKeywords := item.VoiceKeywords

        if (this.hasGui && IsObject(this.Gui)) {
            if (!this._CanReuseWindow()) {
                this._OnClosed()
            } else {
                this._LoadToFields(curKeywords)
                return
            }
        }

        try {
            mainGui := IsObject(MainSoftData.MyGui) ? MainSoftData.MyGui.Hwnd : ""
            this.keywords := this._ParseKeywords(curKeywords)
            panel := this._BuildPanel()
            this.ui := XamlWin.Create(GetLang("语音关键词"), panel, 460, 304)
            this.ui.OnEvent("BtnSure", "Click", (*) => this.OnSureClick())
            this.ui.OnEvent("BtnKwAdd", "Click", (*) => this._OnAddClick())
            this.ui.OnEvent("BtnKwMic", "Click", (*) => this._OnMicClick())
            this.ui.OnEvent("EdKeywords", "KeyDown:Return", (*) => this._OnAddClick())
            this.ui.OnEvent("EdKeywords", "TextChanged", (*) => this._SyncPlaceholder())
            this.ui.OnEvent("Window", "Closing", (*) => this._OnClosed())
            this.ui.OnEvent("Window", "Closed", (*) => this._OnClosed())
            this.hasGui := true
            opened := XamlWin.Open(this.ui, (*) => this._RenderChips(), mainGui)
            if (opened) {
                this.Gui := {Hwnd: this.ui.wpfHwnd}
                this._BindChipClicks()
                this._SyncPlaceholder()
            } else
                this.Cancel()
        } catch as err {
            try RmtDialog._Trace("VoiceGui ShowGui failed: " err.Message)
            this._OnClosed()
        }
    }

    _BuildPanel() {
        lineH := 36
        padL := 10
        radius := 3
        sendW := 24
        addW := 26
        fs := XAMLHost.FontSize()
        panel := XAML_Generator("Grid").Margin("16,6,16,12")
        panel.Rows("Auto", "Auto", "Auto", "Auto")
        panel.InjectResources(this._InputStyles(lineH, radius, sendW, addW, fs))
        panel.Add("TextBlock").Name("LblKeywords").Uid("ahk:Voice.Keywords.Label")
            .Grid_Row(0).Text(GetLang("关键词：")).Foreground("{DynamicResource TextMain}")
            .Margin("0,0,0,6").TextWrapping("Wrap")
        chipBox := panel.Add("Border").Name("KwChipHost").Grid_Row(1)
            .Height(124).MinHeight(124).MaxHeight(124).Padding("4,2,4,2")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").CornerRadius(String(radius))
            .SnapsToDevicePixels("True").UseLayoutRounding("False")
        chipScroll := chipBox.Add("ScrollViewer").VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled").Background("Transparent").BorderThickness("0")
        chipScroll.Add("WrapPanel").Name("KwChipPanel").Uid("ahk:Voice.Keywords.Chips")
            .Orientation("Horizontal").HorizontalAlignment("Left")
        chrome := panel.Add("Border").Name("KwInputHost").Grid_Row(2).Margin("0,10,0,0")
            .Height(lineH).MinHeight(lineH).Padding(padL ",0,8,0")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").CornerRadius(String(radius))
            .SnapsToDevicePixels("True").UseLayoutRounding("False")
        inner := chrome.Add("Grid")
        inner.Add("TextBox").Name("EdKeywords").Style("{StaticResource KwChatBox}")
            .HorizontalAlignment("Stretch").VerticalAlignment("Center")
            .MinHeight(22)
            .AcceptsReturn("False").TextWrapping("NoWrap")
            .VerticalScrollBarVisibility("Hidden").HorizontalScrollBarVisibility("Disabled")
            .VerticalContentAlignment("Center").Padding("0,2,62,2")
            .FontSize(fs).Foreground("{DynamicResource InputText}")
            .Background("Transparent").BorderThickness("0")
        inner.Add("TextBlock").Name("EdKeywordsPh").Text(GetLang("请输入宏触发关键词"))
            .IsHitTestVisible("False").VerticalAlignment("Center").HorizontalAlignment("Left")
            .Margin("0,0,62,0").Padding("0,2,0,2").TextTrimming("CharacterEllipsis")
            .Foreground("{DynamicResource TextSub}").Opacity("0.55").FontSize(fs)
        btns := inner.Add("StackPanel").Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center")
            .SetProp("Panel.ZIndex", "2")
        btns.Add("Button").Name("BtnKwMic").Width(sendW).Height(sendW).MinHeight(sendW)
            .Style("{StaticResource KwIconBtn}").Margin("0,0,4,0")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
            .Foreground("{DynamicResource TextSub}").ToolTip(GetLang("语音输入"))
        btns.Add("Button").Name("BtnKwAdd").Width(addW).Height(addW).MinHeight(addW)
            .Style("{StaticResource KwAddBtn}").Margin("0")
            .Content("+").FontSize(16).FontWeight("Bold")
            .Foreground("{DynamicResource TextMain}").ToolTip(GetLang("添加"))
        btnSure := panel.Add("Button").Name("BtnSure").Uid("ahk:Voice.Keywords.Sure")
            .Grid_Row(3).Content(GetLang("确定")).Width(90).MinWidth(90).MinHeight(32)
            .HorizontalAlignment("Center").Margin("0,10,0,0")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
            .SnapsToDevicePixels("True").UseLayoutRounding("False").IsDefault("True")
        btnSure.InjectResources(this._FieldStrokeStyle("Button"))
        return panel
    }

    _InputStyles(lineH, radius, sendW, addW, fs) {
        chatBox := '<Style x:Key="KwChatBox" TargetType="TextBox">'
            . '<Setter Property="FontSize" Value="' fs '"/>'
            . '<Setter Property="MinHeight" Value="22"/>'
            . '<Setter Property="Padding" Value="0,2,62,2"/>'
            . '<Setter Property="TextWrapping" Value="NoWrap"/>'
            . '<Setter Property="VerticalContentAlignment" Value="Center"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource InputText}"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="VerticalScrollBarVisibility" Value="Hidden"/>'
            . '<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">'
            . '<Border Background="{TemplateBinding Background}" BorderThickness="0">'
            . '<ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden"/>'
            . '</Border></ControlTemplate></Setter.Value></Setter></Style>'
        iconBtn := '<Style x:Key="KwIconBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="' sendW '"/><Setter Property="Height" Value="' sendW '"/><Setter Property="MinHeight" Value="' sendW '"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderBrush" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextSub}"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="3" Width="' sendW '" Height="' sendW '">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        addBtn := '<Style x:Key="KwAddBtn" TargetType="Button">'
            . '<Setter Property="Width" Value="' addW '"/><Setter Property="Height" Value="' addW '"/><Setter Property="MinHeight" Value="' addW '"/>'
            . '<Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/>'
            . '<Setter Property="Cursor" Value="Hand"/>'
            . '<Setter Property="Background" Value="{DynamicResource ControlBg}"/>'
            . '<Setter Property="BorderBrush" Value="{DynamicResource InputStroke}"/>'
            . '<Setter Property="BorderThickness" Value="1"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            . '<Setter Property="FontWeight" Value="Bold"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Width="' addW '" Height="' addW '">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource EditHoverBg}"/>'
            . '<Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource ActionStroke}"/>'
            . '<Setter Property="Foreground" Value="{DynamicResource ActionBg}"/>'
            . '</Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
        return chatBox iconBtn addBtn
    }

    _CanReuseWindow() {
        if (!this.hasGui || !IsObject(this.ui) || !this.ui.HasProp("wpfHwnd"))
            return false
        hwnd := this.ui.wpfHwnd
        return hwnd && DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
    }

    _FieldStrokeStyle(typeName) {
        return '<Style TargetType="' typeName '"><Setter Property="Template"><Setter.Value>'
            . '<ControlTemplate TargetType="' typeName '">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"'
            . ' Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/>'
            . '<Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
            . '</Trigger></ControlTemplate.Triggers>'
            . '</ControlTemplate></Setter.Value></Setter></Style>'
    }

    _ParseKeywords(keywords) {
        keywords := Trim(keywords, "，, `t")
        keywords := StrReplace(keywords, "，", ",")
        parts := []
        seen := Map()
        for p in StrSplit(keywords, ",") {
            p := Trim(p)
            if (p == "" || seen.Has(p))
                continue
            seen[p] := true
            this._nextChipId += 1
            parts.Push({Id: this._nextChipId, Text: p})
        }
        return parts
    }

    _LoadToFields(keywords) {
        this.keywords := this._ParseKeywords(keywords)
        try this.ui.Update("EdKeywords", "Text", "")
        this._RenderChips()
        this._BindChipClicks()
        this._SyncPlaceholder()
        try WinActivate("ahk_id " this.ui.wpfHwnd)
    }

    _RenderChips() {
        if (!IsObject(this.ui))
            return
        this.ui.Update("KwChipPanel", "ClearItems", "")
        for item in this.keywords
            this.ui.Update("KwChipPanel", "AddXamlItem", this._ChipXaml(item))
    }

    _ChipXaml(item) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        del := "KwChipDel_" item.Id
        return '<Grid ' ns ' Name="KwChip_' item.Id '" Margin="6,4,6,4" MaxWidth="408" HorizontalAlignment="Left">'
            . '<Border Padding="10,6,10,6"'
            . ' Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" CornerRadius="3" MaxWidth="408" HorizontalAlignment="Left"'
            . ' SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<TextBlock Name="KwChipText_' item.Id '" Text="' this._XmlEsc(item.Text) '"'
            . ' TextWrapping="Wrap" Foreground="{DynamicResource TextMain}"'
            . ' VerticalAlignment="Center"/>'
            . '</Border>'
            . '<Button Name="' del '" Width="16" Height="16" Padding="0"'
            . ' HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-4,-8,0" Panel.ZIndex="1"'
            . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" Cursor="Hand" Focusable="False"'
            . ' ToolTip="' this._XmlEsc(GetLang("删除")) '">'
            . '<Button.Template><ControlTemplate TargetType="Button">'
            . '<Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Width="16" Height="16">'
            . '<TextBlock Text="' Chr(0xE711) '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"'
            . ' FontSize="8" Foreground="{DynamicResource TextSub}"'
            . ' HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Border>'
            . '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
            . '<Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBorder}"/>'
            . '</Trigger></ControlTemplate.Triggers>'
            . '</ControlTemplate></Button.Template></Button>'
            . '</Grid>'
    }

    _BindChipClicks() {
        if (!IsObject(this.ui) || !this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd)
            return
        for item in this.keywords {
            name := "KwChipDel_" item.Id
            this.ui.OnEvent(name, "Click", this._OnChipDel.Bind(this, item.Id))
            try this.ui.BindEventBatched(name, "Click")
        }
    }

    _OnChipDel(id, *) {
        next := []
        for item in this.keywords {
            if (item.Id != id)
                next.Push(item)
        }
        this.keywords := next
        this._RenderChips()
        this._BindChipClicks()
    }

    _OnAddClick(*) {
        text := ""
        try text := Trim(this.ui.Query("EdKeywords"))
        text := Trim(StrReplace(text, "，", ","))
        if (InStr(text, ",")) {
            for p in StrSplit(text, ",")
                this._AddKeyword(Trim(p))
        } else
            this._AddKeyword(text)
        try this.ui.Update("EdKeywords", "Text", "")
        this._SyncPlaceholder()
    }

    _AddKeyword(text) {
        text := Trim(text)
        if (text == "")
            return false
        for item in this.keywords {
            if (item.Text == text)
                return false
        }
        this._nextChipId += 1
        this.keywords.Push({Id: this._nextChipId, Text: text})
        this._RenderChips()
        this._BindChipClicks()
        return true
    }

    _SyncPlaceholder() {
        if (!IsObject(this.ui))
            return
        text := ""
        try text := Trim(this.ui.Query("EdKeywords"))
        hasLive := this._rec && this._recLive != ""
        try this.ui.Update("EdKeywordsPh", "Visibility", (text == "" && !hasLive) ? "Visible" : "Collapsed")
    }

    _OnMicClick(*) {
        if (this._rec) {
            this._StopRec()
            return
        }
        if (!IsSet(InitSttEngine))
            return
        engine := InitSttEngine()
        if (IsObject(engine) && !engine.IsDllReady())
            engine._TryLoadDll()
        if (!IsObject(engine) || !engine.IsDllReady()) {
            try Toast.Warning(GetLang("语音引擎未就绪"))
            return
        }
        if (!engine.IsStreamReady()) {
            SttGui.RequestModelDownload()
            return
        }
        baseText := ""
        try baseText := Trim(this.ui.Query("EdKeywords"))
        initializing := !engine.streamLoaded
        if (initializing && baseText == "") {
            try this.ui.Update("EdKeywordsPh", "Text", GetLang("模型正在加载…"))
            try this.ui.Update("EdKeywordsPh", "Visibility", "Visible")
            Sleep(50)
        }
        if (!engine.StreamBegin()) {
            this._SyncPlaceholder()
            try Toast.Error(GetLang("开始录音失败：") engine._ErrText(engine.StreamGetLastError()))
            return
        }
        this._rec := true
        this._recBase := baseText
        this._recLive := ""
        try this.ui.Update("EdKeywords", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("BtnKwMic", "Foreground", "{DynamicResource Accent}")
        try this.ui.Update("BtnKwMic", "ToolTip", GetLang("停止录音"))
        try this.ui.Update("EdKeywordsPh", "Text", GetLang("正在聆听…"))
        try this.ui.Update("EdKeywordsPh", "Visibility", this._recBase == "" ? "Visible" : "Collapsed")
        SetTimer(this._sttTick, 150)
    }

    _PollStt() {
        if (!this._rec) {
            SetTimer(this._sttTick, 0)
            return
        }
        if (!IsSet(InitSttEngine))
            return
        engine := InitSttEngine()
        live := ""
        try live := engine.StreamPoll()
        if (Trim(live) != "" && live != this._recLive) {
            this._recLive := live
            base := this._recBase
            sep := (base != "" && !RegExMatch(base, "\s$")) ? " " : ""
            try this.ui.Update("EdKeywords", "Text", base sep live)
            try this.ui.Update("EdKeywordsPh", "Text", GetLang("请输入宏触发关键词"))
            try this.ui.Update("EdKeywordsPh", "Visibility", "Collapsed")
        }
    }

    _StopRec() {
        this._rec := false
        SetTimer(this._sttTick, 0)
        try this.ui.Update("BtnKwMic", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("BtnKwMic", "ToolTip", GetLang("语音输入"))
        try this.ui.Update("EdKeywordsPh", "Text", GetLang("请输入宏触发关键词"))
        if (!IsSet(InitSttEngine)) {
            try this.ui.Update("EdKeywords", "Foreground", "{DynamicResource InputText}")
            this._SyncPlaceholder()
            return
        }
        engine := InitSttEngine()
        if (!IsObject(engine)) {
            try this.ui.Update("EdKeywords", "Foreground", "{DynamicResource InputText}")
            this._SyncPlaceholder()
            return
        }
        if (!engine.StreamEnd(0)) {
            try this.ui.Update("EdKeywords", "Foreground", "{DynamicResource InputText}")
            this._SyncPlaceholder()
            return
        }
        loop 40 {
            st := engine.StreamGetState()
            if (st == 3 || st == 4)
                break
            Sleep(50)
        }
        result := Trim(engine.StreamGetResult())
        if (result != "")
            this.ui.Update("EdKeywords", "Text", this._recBase (this._recBase != "" ? " " : "") result)
        else
            this.ui.Update("EdKeywords", "Text", this._recBase)
        try this.ui.Update("EdKeywords", "Foreground", "{DynamicResource InputText}")
        this._SyncPlaceholder()
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _ReadFields() {
        pending := ""
        try pending := Trim(this.ui.Query("EdKeywords"))
        pending := Trim(StrReplace(pending, "，", ","))
        texts := []
        seen := Map()
        for item in this.keywords {
            if (item.Text == "" || seen.Has(item.Text))
                continue
            seen[item.Text] := true
            texts.Push(item.Text)
        }
        if (pending != "") {
            for p in StrSplit(pending, ",") {
                p := Trim(p)
                if (p == "" || seen.Has(p))
                    continue
                seen[p] := true
                texts.Push(p)
            }
        }
        clean := ""
        for i, p in texts {
            if (i > 1)
                clean .= ","
            clean .= p
        }
        return clean
    }

    _ApplyToModel(keywords) {
        global MyVoiceEngine, MyHotReloadBus
        tableItem := this.tableItem
        index := this.index
        item := tableItem.Items[index]
        if (!item)
            return
        item.VoiceKeywords := keywords
        HotReloadPublish(GetTableIndexByID(tableItem.ID), index)
    }

    OnSureClick(*) {
        this._DoSure()
    }

    _DoSure() {
        keywords := this._ReadFields()
        this._ApplyToModel(keywords)
        if (IsSet(MyMainWin) && IsObject(MyMainWin))
            MyMainWin.RenderTab(this.tableItem)
        this.Cancel()
        if (IsObject(this.SureBtnAction))
            this.SureBtnAction.Call()
    }

    Cancel(*) {
        if (this._rec)
            this._StopRec()
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
        this._OnClosed()
    }

    _OnClosed() {
        if (this._rec)
            this._StopRec()
        this.hasGui := false
        this.Gui := ""
        this.ui := ""
        this.keywords := []
    }
}
