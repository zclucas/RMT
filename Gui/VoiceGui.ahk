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
        this.edKeywords := { Value: "" }
    }

    ; ShowGui(tableItem, index)
    ShowGui(tableItem, index, isUpdate := false) {
        if (!CheckIsItemTable(GetTableIndexByID(tableItem.ID)))
            return
        this.tableItem := tableItem
        this.index := index

        ; 读取当前关键词（对象字段，容错）
        curKeywords := ""
        item := tableItem.Items[index]
        if (item)
            curKeywords := item.VoiceKeywords

        ; 复用已存在窗口则刷新（单实例模式）。引擎窗口被关闭/重启后，旧的
        ; AHK 对象可能仍然存在；先校验 HWND，避免把 Update/Query 发到失效窗口。
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
            strokeWidth := "1"
            panel := XAML_Generator("Grid").Margin("16")
            panel.Rows("Auto", "Auto", "*", "Auto", "Auto")
            panel.Add("TextBlock").Grid_Row(0).Text(GetLang("说出以下关键词即可触发该宏。支持多个关键词，用英文逗号 , 分隔。")).TextWrapping("Wrap").Margin("0,0,0,10")
            panel.Add("TextBlock").Grid_Row(1).Text(GetLang("唤醒关键词：")).Margin("0,0,0,6")
            ; Match main fold-field stroke weight: 1.25 DIP, no Aliased edge mode
            ; (default TextBox/Button templates look hairline-thin at 125% DPI).
            ed := panel.Add("TextBox").Name("EdKeywords").Grid_Row(2).MinHeight(120).AcceptsReturn("True").TextWrapping("Wrap")
                .VerticalScrollBarVisibility("Auto").VerticalAlignment("Stretch")
                .BorderBrush("{DynamicResource InputStroke}").BorderThickness(strokeWidth)
                .SnapsToDevicePixels("True").UseLayoutRounding("False")
            ed.InjectResources(this._FieldStrokeStyle("TextBox"))
            panel.Add("TextBlock").Grid_Row(3).Text(GetLang("示例：开始攻击, 暂停, 保存进度（每个关键词之间用英文逗号分隔）")).TextWrapping("Wrap").Margin("0,8,0,12")
            ; A stable Uid is required for GM-UI instance properties to survive a restart.
            ; Automatic source-line Uids are disabled in production and must not be relied on.
            buttons := panel.Add("StackPanel").Name("VoiceKeywordActions").Uid("ahk:Voice.Keywords.Actions")
                .Grid_Row(4).Orientation("Horizontal").HorizontalAlignment("Right")
            btnSure := buttons.Add("Button").Name("BtnSure").Content(GetLang("确定")).Width(90).MinHeight(32)
                .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness(strokeWidth)
                .SnapsToDevicePixels("True").UseLayoutRounding("False")
                .IsDefault("True").Margin("0,0,10,0")
            btnSure.InjectResources(this._FieldStrokeStyle("Button"))
            btnCancel := buttons.Add("Button").Name("BtnCancel").Content(GetLang("取消")).Width(90).MinHeight(32)
                .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness(strokeWidth)
                .SnapsToDevicePixels("True").UseLayoutRounding("False")
                .IsCancel("True")
            btnCancel.InjectResources(this._FieldStrokeStyle("Button"))
            ; Use the same Viewbox/chrome scaling path as every other business dialog.
            ; The former fluid-only path made this title bar a different visual size and
            ; caused several visible relayouts while restoring the saved window geometry.
            this.ui := XamlWin.Create(GetLang("语音关键词"), panel, 480, 340)
            this.ui.OnEvent("BtnSure", "Click", (*) => this.OnSureClick())
            this.ui.OnEvent("BtnCancel", "Click", (*) => this.Cancel())
            this.ui.OnEvent("Window", "Closing", (*) => this._OnClosed())
            this.ui.OnEvent("Window", "Closed", (*) => this._OnClosed())
            this.ui.Update("EdKeywords", "Text", curKeywords)
            this.hasGui := true
            if (XamlWin.Open(this.ui, "", mainGui))
                this.Gui := {Hwnd: this.ui.wpfHwnd}
            else
                this.Cancel()
        } catch as err {
            ; 解析/XAML 引擎异常时释放可复用状态，下一次点击可重新创建窗口。
            try RmtDialog._Trace("VoiceGui ShowGui failed: " err.Message)
            this._OnClosed()
        }
    }

    _CanReuseWindow() {
        if (!this.hasGui || !IsObject(this.ui) || !this.ui.HasProp("wpfHwnd"))
            return false
        hwnd := this.ui.wpfHwnd
        return hwnd && DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
    }

    ; Same stroke recipe as main fold fields: template Border without Aliased EdgeMode
    ; so 1.5 DIP strokes stay visible at 125%/150% DPI.
    _FieldStrokeStyle(typeName) {
        return '<Style TargetType="' typeName '"><Setter Property="Template"><Setter.Value>'
            . '<ControlTemplate TargetType="' typeName '">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"'
            . ' BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"'
            . ' Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . (typeName = "TextBox"
                ? '<ScrollViewer x:Name="PART_ContentHost" Margin="0"/>'
                : '<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>')
            . '</Border>'
            . (typeName = "Button"
                ? '<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">'
                    . '<Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/>'
                    . '<Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/>'
                    . '</Trigger></ControlTemplate.Triggers>'
                : '')
            . '</ControlTemplate></Setter.Value></Setter></Style>'
    }

    _LoadToFields(keywords) {
        this.ui.Update("EdKeywords", "Text", keywords)
        try WinActivate("ahk_id " this.ui.wpfHwnd)
    }

    ; 收集界面值写回模型
    _ReadFields() {
        keywords := Trim(this.ui.Query("EdKeywords"))
        keywords := Trim(keywords, "，, ")
        ; 统一关键词内分隔符为英文逗号（兼容中文逗号输入）
        keywords := StrReplace(keywords, "，", ",")
        ; 清理空项与多余空格
        parts := []
        for p in StrSplit(keywords, ",") {
            p := Trim(p)
            if (p != "")
                parts.Push(p)
        }
        clean := ""
        for i, p in parts {
            if (i > 1)
                clean .= ","
            clean .= p
        }
        return clean
    }

    ; 写回表格模型（供语音引擎读取）
    _ApplyToModel(keywords) {
        global MyVoiceEngine, MyHotReloadBus
        tableItem := this.tableItem
        index := this.index
        item := tableItem.Items[index]
        if (!item)
            return
        item.VoiceKeywords := keywords
        ; 启用/禁用由主界面「禁用」开关（Forbid）控制；此处仅保证该行语音字段有效

        ; §18 热重载：广播「本行配置已变更」+ 即时落盘，VoiceEngine 订阅者空闲时重建关键词集（不阻塞 UI）
        HotReloadPublish(GetTableIndexByID(tableItem.ID), index)
    }

    OnSureClick(*) {
        this._DoSure()
    }

    _DoSure() {
        keywords := this._ReadFields()
        this._ApplyToModel(keywords)
        ; 刷新主界面表格，让关键词列立即显示新值
        if (IsSet(MyMainWin) && IsObject(MyMainWin))
            MyMainWin.RenderTab(this.tableItem)
        this.Cancel()
        if (IsObject(this.SureBtnAction))
            this.SureBtnAction.Call()
    }

    Cancel(*) {
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
        this._OnClosed()
    }

    _OnClosed() {
        this.hasGui := false
        this.Gui := ""
        this.ui := ""
    }
}
