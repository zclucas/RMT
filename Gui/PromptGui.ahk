#Requires AutoHotkey v2.0

class PromptGui {
    _autoRemark := ""
    _playHotkeys := []
    static WindowWidth := 560
    static BodyInset := 16
    static PairGap := 14
    static TimePartWidth := 136
    static TimePartGap := 16

    __New() {
        this.ParentTile := ""
        this.OwnerHwnd := ""
        this.SureBtnAction := ""
        this.ui := ""
        this._closed := true
        this._pickAction := ""
        this._pickHotkeys := []
        this._pickMode := ""
        this._areaPreview := ScreenAreaPreview()
        this._previewShowing := false
    }

    ShowGui(cmd) {
        if (IsObject(this.ui))
            this.Close()
        parts := cmd == "" ? [] : StrSplit(cmd, "_", , 2)
        serial := parts.Length ? parts[1] : ""
        this.data := serial == "" ? PromptData() : GetMacroCMDData(serial).Clone()
        if (serial == "") {
            this.data.PasteName := "自由贴"
            this.data.RegionName := "框选范围"
            this.data.CountDownName := "倒计时"
        }
        if (this.data.FlashMode == "主副屏")
            this.data.FlashMode := "所有屏"
        if (!this.data.HasProp("AudioPlayback"))
            this.data.AudioPlayback := "后台播放"
        if (!this.data.HasProp("PastePosition"))
            this.data.PastePosition := "鼠标位置"
        if (!this.data.HasProp("RegionMode"))
            this.data.RegionMode := "显示"
        if (!this.data.HasProp("RegionName"))
            this.data.RegionName := ""
        if (!this.data.HasProp("CountDownName"))
            this.data.CountDownName := ""
        this._autoRemark := ReadCommandAutoRemark(this.data, GenerateCommandAutoRemark)
        this.remark := parts.Length > 1 ? parts[2] : ""
        if (serial != "" && !RegExMatch(serial, "\d+$"))
            this.remark := ""
        this.previewSerial := ""
        this.fields := Map()
        this.Build()
        this._closed := false
        if (this.OwnerHwnd && MainSoftData.IsModalSubGui) {
            this.disabledOwner := this.OwnerHwnd
            try SafeGuiFromHwnd(this.disabledOwner).Opt("+Disabled")
        }
        try {
            if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
                this.Close()
        } catch {
            this.Close()
            throw
        }
    }

    Build() {
        title := this.ParentTile GetLang("提示编辑器")
        titleHeight := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", 56)
        chrome := XAMLHost.AddCmdTitleBar(main, title, titleHeight)
        chrome.F1.Style("{StaticResource PromptPickButton}").Tag("0")
        main.InjectResources('<Style x:Key="PromptPickButton" TargetType="Button" BasedOn="{StaticResource TitleBarChromeButton}">'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="surface" Background="{TemplateBinding Background}">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="surface" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '<Trigger Property="Tag" Value="1"><Setter TargetName="surface" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')
        body := main.Add("ScrollViewer").Grid_Row(1).MaxHeight(400).VerticalScrollBarVisibility("Auto")
            .Add("StackPanel").Margin(PromptGui.BodyInset ",14," PromptGui.BodyInset ",0")
        this.AddPair(body, &left, &right)
        this.AddField(left, "Type", "提示类型", PromptTypes())
        this.AddField(right, "Remark", "备注")

        this.AddPair(body, &left, &right)
        this.AddField(left, "AudioMode", "音频类型", ["系统提示音", "系统语音", "自定义音频"])
        this.AddField(left, "TipMode", "内容类型", ["文本", "图片"])
        this.AddField(left, "PasteMode", "操作", ["文本", "图片", "关闭", "关闭所有"])
        this.AddField(left, "RegionMode", "操作", ["显示", "关闭"])
        this.AddField(left, "FlashMode", "显示屏", ["主屏", "副屏", "所有屏", "自定义"])
        this.AddField(left, "CountDownMode", "操作", ["显示", "关闭", "关闭所有"])
        this.AddField(right, "Beep", "提示音", PromptBeepModes())
        this.AddField(right, "AudioPlayback", "播放方式", ["后台播放", "使用播放器"])
        this.AddField(right, "TextSource", "内容来源", ["直接填写", "剪贴板"])
        clipboardSource := this.data.PasteTextSource == "剪贴板图文" ? "剪贴板图文" : "剪贴板"
        this.AddField(right, "PasteTextSource", "内容来源", ["直接填写", clipboardSource])
        this.AddField(right, "ImageSource", "内容来源", ["文件", "剪贴板"])
        this.AddField(right, "Monitors", "屏幕编号", , , GetLang("多个屏幕编号用逗号分隔"))
        this.AddField(right, "Param2", "计时方式", ["时长", "时刻", "时间戳"])
        this.AddField(right, "RegionName", "名称", , "name", GetLang("同名框选会替换，关闭时留空则关闭最后一个"))

        this.AddPair(body, &left, &right)
        this.AddField(left, "AudioWait", "播放时", ["不等待", "等待结束"])
        this.AddField(left, "PasteName", "名称", , "name", GetLang("同名贴片会替换，关闭时留空则关闭最后一张"))
        this.AddField(left, "CountDownName", "名称", , "name")
        this.AddField(right, "PastePosition", "位置模式", ["鼠标位置", "固定位置"])
        this.AddField(left, "Duration", "显示时长", , , GetLang("内容在屏幕上停留的毫秒数。"))
        this.AddField(right, "WaitEnd", "显示后", ["不等待", "等待结束"])

        this.AddPair(body, &left, &right)
        this.AddField(left, "Param1", "时间戳", , "timestamp", GetLang("填写毫秒时间戳或选择时间变量。"))
        this.AddCountDownTime(body)

        this.AddPair(body, &left, &right)
        this.AddField(left, "PosX", "屏幕 X")
        this.AddField(right, "PosY", "屏幕 Y")

        this.AddRegionFields(body)

        this.AddPair(body, &left, &right)
        this.AddField(left, "Color", "颜色")

        this.AddPair(body, &left, &right)
        this.AddField(left, "FlashDuration", "单次闪光", , , GetLang("每次闪光持续的毫秒数。"))
        this.AddField(right, "FlashCount", "闪光次数")

        this.AddField(body, "ImagePath", "图片路径", , "file")
        this.AddField(body, "AudioPath", "音频路径", , "file")
        this.AddField(body, "Text", "提示内容", , "multiline")
        vars := this.AddField(body, "Vars", "变量数组：", , "tools")
        vars.Cols("90", "*", "Auto", "Auto")
        kind := vars.Add("ComboBox").Name("InsertKind").SelectedIndex(0).MinHeight(28)
        for label in ["变量", "数组"]
            kind.Add("ComboBoxItem").Content(GetLang(label))
        names := vars.Add("ComboBox").Grid_Column(1).Name("InsertValue").SelectedIndex(0).MinHeight(28).Margin("8,0,0,0")
        for name in GetGuiVarArr("all") {
            if (name != "")
                names.Add("ComboBoxItem").Content(name)
        }
        vars.Add("Button").Grid_Column(2).Name("AddName").MinWidth(70).Margin("8,0,0,0").Content(GetLang("追加名"))
        vars.Add("Button").Grid_Column(3).Name("AddValue").MinWidth(70).Margin("8,0,0,0").Content(GetLang("追加值"))

        buttons := main.Add("StackPanel").Grid_Row(2).VerticalAlignment("Center").HorizontalAlignment("Center")
        AddCmdOkBtn(buttons)
        template := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(template, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' EscapeXamlXml(title) '" Width="' this.LayoutWidth() '" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "LoadedHwnd", this.OnLoaded.Bind(this, this.ui))
        this.ui.OnEvent("Window", "Closing", this.OnClosing.Bind(this, this.ui))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "Close"))
        BindCmdEditorChrome(this.ui, "#指令手册/30-提示", this.Preview.Bind(this), "!l", this.PickFlashColor.Bind(this), this.PickScreen.Bind(this))
        this.ui.Update("BtnCmdTargeter", "Visibility", this.FieldVisible("Color", this.data) ? "Visible" : "Collapsed")
        this.ui.BatchUpdate(CmdEditorF1Updates(this.PickMode(this.data)))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "Save"))
        this.ui.OnEvent("BtnPreviewArea", "Click", this.ToggleAreaPreview.Bind(this))
        for name, value in Map("RegionStartX", this.data.PosX, "RegionStartY", this.data.PosY
            , "RegionEndX", this.RegionEnd(this.data, "X", "Width"), "RegionEndY", this.RegionEnd(this.data, "Y", "Height")) {
            this.ui.Track(name)
            this.ui.Update(name, "Text", String(value))
            this.ui.OnEvent(name, "LostFocus", this.RefreshAreaPreview.Bind(this))
        }
        this.ui.OnEvent("InsertKind", "SelectionChanged", this.RefreshInsertNames.Bind(this))
        this.ui.OnEvent("AddName", "Click", this.AppendSelection.Bind(this, false))
        this.ui.OnEvent("AddValue", "Click", this.AppendSelection.Bind(this, true))
        this.ui.OnEvent("BrowseImagePath", "Click", this.Browse.Bind(this, "ImagePath", "Images (*.png; *.jpg; *.jpeg; *.bmp; *.gif; *.ico)"))
        this.ui.OnEvent("BrowseAudioPath", "Click", this.Browse.Bind(this, "AudioPath", "Audio (*.wav; *.mp3; *.wma; *.mid; *.midi)"))
        this.ui.OnEvent("CountDownName", "TextChanged", this.Refresh.Bind(this))
        this.ui.OnEvent("CountDownName", "SelectionChanged", this.Refresh.Bind(this))
        for name, field in this.fields {
            if (field.kind == "tools")
                continue
            this.ui.Track(name)
            if (field.options.Length) {
                if (name != "Beep" && name != "WaitEnd" && name != "AudioWait")
                    this.ui.OnEvent(name, "SelectionChanged", this.Refresh.Bind(this))
            } else
                this.ui.Update(name, "Text", name == "Remark" ? this.remark
                    : name == "Text" ? GetLangStr(this.data.Text, 1)
                    : field.kind == "name" ? TranslateBuiltinVarReferences(this.data.%name%, true)
                    : name == "Param1" ? (this.data.Param2 == "时间戳" ? GetLang(this.data.Param1) : "")
                    : String(this.data.%name%))
        }
        for prefix in ["CountDownDuration", "CountDownClock"]
            for part in ["Hour", "Min", "Sec"]
                this.ui.Track(prefix part)
    }

    AddPair(body, &left, &right) {
        row := body.Add("Grid").Cols("*", PromptGui.PairGap, "*")
        left := row.Add("StackPanel")
        right := row.Add("StackPanel").Grid_Column(2)
    }

    LabelColumnWidth() => Ceil(XAMLHost.GetThemeFontSize() * 5.5) + 6

    LayoutWidth() {
        timeWidth := 3 * PromptGui.TimePartWidth + 2 * PromptGui.TimePartGap
        return Max(PromptGui.WindowWidth, 2 * PromptGui.BodyInset + this.LabelColumnWidth() + timeWidth + 16)
    }

    PairedInputWidth() => (this.LayoutWidth() - 2 * PromptGui.BodyInset - PromptGui.PairGap) / 2 - this.LabelColumnWidth()

    AddRegionFields(body) {
        area := body.Add("Grid").Name("RegionFields").Margin("0,0,0,8")
            .HorizontalAlignment("Left").Visibility(this.PickMode(this.data) == "area" ? "Visible" : "Collapsed")
        inputWidth := this.PairedInputWidth()
        area.Rows("32", "32").Cols("Auto", 6, inputWidth, PromptGui.PairGap, inputWidth)
        button := area.Add("Button").Name("BtnPreviewArea").Grid_RowSpan(2).Tag("0")
            .Focusable("False").Cursor("Hand").ToolTip(GetLang("框选范围预览"))
            .HorizontalContentAlignment("Stretch").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
        button.InjectResources(ScreenAreaPreview.ButtonStyle())
        labels := button.Add("Grid").Rows("*", "*")
        labels.Add("TextBlock").Name("RegionStartLabel").Text(GetLang("起始坐标：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").IsHitTestVisible("False")
        labels.Add("TextBlock").Name("RegionEndLabel").Grid_Row(1).Text(GetLang("终止坐标：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").IsHitTestVisible("False")
        for field in [["RegionStartX", 0, 2, "起始X："], ["RegionStartY", 0, 4, "起始Y："]
            , ["RegionEndX", 1, 2, "终止X："], ["RegionEndY", 1, 4, "终止Y："]] {
            area.Add("TextBox").Name(field[1]).Grid_Row(field[2]).Grid_Column(field[3])
                .Margin("0,2").Padding("1.5,2")
                .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
                .BorderBrush("{DynamicResource InputStroke}")
        }
    }

    RegionEnd(data, axis, size) {
        end := "EndPos" axis
        if (data.HasProp(end) && data.%end% != "")
            return data.%end%
        start := "Pos" axis
        return IsInteger(data.%start%) && IsInteger(data.%size%) ? data.%start% + data.%size% : ""
    }

    AddField(body, name, label, options := [], kind := "", labelTip := "") {
        this.fields[name] := {label: label, options: options, kind: kind}
        row := body.Add("Grid").Name("Row" name).Margin("0,0,0,8")
        row.Visibility(this.FieldVisible(name, this.data) ? "Visible" : "Collapsed")
        caption := row.Add("TextBlock").Name("Label" name).Text(this.FieldCaption(name, this.data))
        if (labelTip != "")
            caption.ToolTip(labelTip)
        if (kind == "multiline") {
            row.Rows("Auto", "Auto")
            caption.Margin("0,0,0,4")
            target := row.Add("Grid").Grid_Row(1)
        } else {
            row.Cols(this.LabelColumnWidth(), "*")
            caption.TextWrapping("Wrap").VerticalAlignment("Center").Margin("0,0,6,0")
            target := row.Add("Grid").Grid_Column(1)
        }
        if (kind == "tools")
            return target
        if (kind == "timestamp")
            return this.AddEditableCombo(target, name, GetGuiVarArr("timeVars", "timestamp"))
        if (kind == "name")
            return this.AddEditableCombo(target, name, GetGuiVarReferences("text")).IsTextSearchEnabled("False")
        if (options.Length) {
            index := 0
            for i, value in options {
                if (this.data.%name% == value)
                    index := i - 1
            }
            combo := target.Add("ComboBox").Name(name).MinHeight(28).SelectedIndex(index)
            for value in options
                combo.Add("ComboBoxItem").Content(this.OptionCaption(name, value))
            return combo
        }
        if (kind == "file") {
            target.Cols("*", 80)
            target.Add("Button").Grid_Column(1).Name("Browse" name).Margin("6,0,0,0").Content(GetLang("浏览"))
        }
        ; The TextBox template applies padding twice, so 1.5 aligns the text with the ComboBox content.
        box := target.Add("TextBox").Name(name).MinHeight(28).Padding("1.5,2").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}")
        if (kind == "multiline")
            box.Height(112).Padding("1.5,1,1.5,4").VerticalContentAlignment("Top").AcceptsReturn("True").TextWrapping("Wrap").ScrollViewer_VerticalScrollBarVisibility("Auto")
        if (name == "Duration" || name == "FlashDuration") {
            unitPadding := Ceil(XAMLHost.GetThemeFontSize()) + 3
            target.Width(this.PairedInputWidth()).HorizontalAlignment("Left")
            box.Padding("1.5,2," unitPadding ",2")
            target.Add("TextBlock").Name(name "Unit").Text("ms").IsHitTestVisible("False")
                .HorizontalAlignment("Right").VerticalAlignment("Bottom").Margin("0,0,6,2")
                .Foreground("{DynamicResource TextSub}")
        }
        return box
    }

    AddEditableCombo(parent, name, items) {
        combo := parent.Add("ComboBox").Name(name).MinHeight(28).IsEditable("True").MaxDropDownHeight(260)
        for item in items
            CmdEditorForm.ComboItem(combo, item)
        return combo
    }

    AddCountDownTime(body) {
        data := this.data
        clock := ["14", "30", "00"]
        this.legacyClock := ""
        if (data.Param2 == "时刻") {
            clock := [data.Hour, data.Min, data.Sec]
            if (data.Param1 != "") {
                raw := Trim(data.Param1)
                parts := StrSplit(raw, ":", " `t")
                if (parts.Length >= 2 && parts.Length <= 3 && !RegExMatch(raw, "^\d{4}[-/.]"))
                    clock := [parts[1], parts[2], parts.Length == 3 ? parts[3] : "00"]
                else {
                    ; 旧配置也允许整段时刻变量或完整日期时间。
                    this.legacyClock := raw
                    clock := [raw, "00", "00"]
                }
            }
        }
        this.AddCountDownParts(body, "CountDownDuration", "时长", [data.Hour, data.Min, data.Sec], 59)
        this.AddCountDownParts(body, "CountDownClock", "目标时间", clock, 23)
    }

    AddCountDownParts(body, prefix, label, values, maxHour) {
        partWidth := PromptGui.TimePartWidth, gap := PromptGui.TimePartGap
        row := this.AddField(body, prefix, label, , "tools", prefix == "CountDownClock"
            ? GetLang("按时、分、秒填写一天中的时刻。") : GetLang("按时、分、秒填写持续时间。")).Cols(partWidth, gap, partWidth, gap, partWidth)
        for i, part in ["Hour", "Min", "Sec"] {
            col := (i - 1) * 2
            if (i > 1)
                row.Add("TextBlock").Grid_Column(col - 1).Text(":").HorizontalAlignment("Center")
                    .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
            items := []
            Loop (i == 1 ? maxHour + 1 : 60)
                items.Push(Format("{:02}", A_Index - 1))
            for variable in GetGuiVarArr(["hour", "minute", "second"][i])
                items.Push(variable)
            value := values[i]
            if (IsInteger(value) && !(prefix == "CountDownClock" && i == 1 && this.legacyClock != ""))
                value := Format("{:02}", Integer(value))
            this.AddEditableCombo(row, prefix part, items).Grid_Column(col).SetProp("Text", GetLang(value))
                .ToolTip(GetLang(["时", "分", "秒"][i]))
        }
    }

    FieldCaption(name, data) {
        label := this.fields[name].label
        if (name == "Text" && data.Type == "音频" && data.AudioMode == "系统语音")
            label := "语音文本"
        if (data.Type == "自由贴") {
            if (name == "PosX")
                label := "中心 X"
            else if (name == "PosY")
                label := "中心 Y"
        }
        text := GetLang(label)
        return RTrim(text, " `t:：") ":"
    }

    OptionCaption(name, value) {
        if (name == "PasteTextSource" && value == "剪贴板图文")
            return GetLang("剪贴板")
        return name == "Type" && value == "区域高亮" ? GetLang("框选范围") : GetLang(value)
    }

    FieldVisible(name, data) {
        type := data.Type
        tip := type == "临时提示"
        paste := type == "自由贴"
        region := type == "区域高亮"
        showRegion := region && data.RegionMode == "显示"
        flash := type == "屏幕边缘闪光"
        audio := type == "音频"
        countdown := type == "倒计时"
        showTimer := countdown && data.CountDownMode == "显示"
        tipText := tip && data.TipMode == "文本"
        pasteText := paste && data.PasteMode == "文本"
        pasteShown := paste && (data.PasteMode == "文本" || data.PasteMode == "图片")
        image := tip && data.TipMode == "图片" || paste && data.PasteMode == "图片"
        text := type == "软件弹窗" || audio && data.AudioMode == "系统语音" || showRegion
            || tipText && data.TextSource == "直接填写" || pasteText && data.PasteTextSource == "直接填写"
        switch name {
            case "AudioMode": return audio
            case "TipMode": return tip
            case "PasteMode": return paste
            case "RegionMode", "RegionName": return region
            case "FlashMode": return flash
            case "CountDownMode": return countdown
            case "CountDownName": return countdown && data.CountDownMode != "关闭所有"
            case "TextSource": return tipText
            case "PasteTextSource": return pasteText
            case "ImageSource": return image
            case "Text", "Vars": return text
            case "ImagePath": return image && data.ImageSource == "文件"
            case "AudioPath", "AudioPlayback": return audio && data.AudioMode == "自定义音频"
            case "AudioWait": return audio && data.AudioMode == "自定义音频" && data.AudioPlayback == "后台播放"
            case "Beep": return audio && data.AudioMode == "系统提示音"
            case "PasteName": return paste && data.PasteMode != "关闭所有"
            case "PastePosition": return pasteShown
            case "PosX", "PosY":
                return showTimer || countdown && data.CountDownMode == "关闭" && data.CountDownName == ""
                    || pasteShown && data.PastePosition == "固定位置"
            case "Color": return flash
            case "Duration": return tip || showRegion
            case "FlashDuration", "FlashCount": return flash
            case "Monitors": return flash && data.FlashMode == "自定义"
            case "Param2", "WaitEnd": return showTimer
            case "CountDownDuration": return showTimer && data.Param2 == "时长"
            case "CountDownClock": return showTimer && data.Param2 == "时刻"
            case "Param1": return showTimer && data.Param2 == "时间戳"
            default: return true
        }
    }

    ReadChoices(data, state) {
        for name, field in this.fields {
            if (field.options.Length) {
                value := state.Get(name, "")
                for option in field.options {
                    if (this.OptionCaption(name, option) == value) {
                        data.%name% := option
                        break
                    }
                }
            }
        }
        data.CountDownName := Trim(state.Get("CountDownName", ""))
    }

    Refresh(*) {
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        data := this.data.Clone()
        this.ReadChoices(data, this.ui.Query("*"))
        changes := []
        for name in this.fields
            changes.Push({ControlName: "Row" name, PropertyName: "Visibility", Value: this.FieldVisible(name, data) ? "Visible" : "Collapsed"})
        for name in ["Text", "PosX", "PosY"]
            changes.Push({ControlName: "Label" name, PropertyName: "Text", Value: this.FieldCaption(name, data)})
        changes.Push({ControlName: "BtnCmdTargeter", PropertyName: "Visibility", Value: this.FieldVisible("Color", data) ? "Visible" : "Collapsed"})
        mode := this.PickMode(data)
        if (mode != this._pickMode) {
            this.CancelPick()
            if (mode != "area" && this._previewShowing)
                this.SetAreaPreview(false)
            this.BindPickHotkey(mode)
            changes.Push(CmdEditorF1Updates(mode)*)
        }
        changes.Push({ControlName: "RegionFields", PropertyName: "Visibility", Value: mode == "area" ? "Visible" : "Collapsed"})
        this.ui.BatchUpdate(changes)
    }

    PickFlashColor(*) {
        if (IsObject(this.ui) && this.ui.Query("Type") == GetLang("屏幕边缘闪光"))
            MyTargetGui.ShowGui(XamlWin.BindCurrent(this, "ApplyFlashColor"))
    }

    ApplyFlashColor(x, y, color) {
        if (this.ui.Query("Type") == GetLang("屏幕边缘闪光"))
            this.ui.Update("Color", "Text", SearchColorHex(color))
    }

    Browse(field, filter, *) {
        path := FileSelect(1, this.ui.Query(field), GetLang("选择文件"), filter)
        if (path != "" && IsObject(this.ui))
            this.ui.Update(field, "Text", path)
    }

    RefreshInsertNames(*) {
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        names := this.ui.Query("InsertKind") == GetLang("数组") ? GetGuiArrNameArr() : GetGuiVarArr("all")
        changes := [{ControlName: "InsertValue", PropertyName: "ClearItems", Value: ""}]
        for name in names {
            if (name != "")
                changes.Push({ControlName: "InsertValue", PropertyName: "AddItem", Value: name})
        }
        if (changes.Length > 1)
            changes.Push({ControlName: "InsertValue", PropertyName: "SelectedIndex", Value: "0"})
        this.ui.BatchUpdate(changes)
    }

    AppendSelection(asValue, *) {
        name := this.ui.Query("InsertValue")
        if (name == "")
            return
        if (asValue) {
            prefix := this.ui.Query("InsertKind") == GetLang("数组") ? "ε" : ""
            name := "{" prefix name "}"
        }
        this.ui.Update("Text", "Text", this.ui.Query("Text") name)
    }

    PickMode(data) {
        if (data.Type == "区域高亮" && data.RegionMode == "显示")
            return "area"
        return this.FieldVisible("PosX", data) ? "point" : ""
    }

    BindPickHotkey(mode) {
        if (mode == "" && this._pickHotkeys.Length) {
            WinHotkey.UnregisterAll(this._pickHotkeys)
            this._pickHotkeys := []
        } else if (mode != "" && !this._pickHotkeys.Length) {
            this._pickHotkeys := WinHotkey.Register(["F1"], this.OnF1.Bind(this), this.ui.wpfHwnd)
        }
        this._pickMode := mode
    }

    OnF1(*) {
        if (this._pickMode == "area") {
            this.PickScreen()
        } else if (this._pickMode == "point" && IsObject(this.ui)) {
            this.CancelPick()
            point := Buffer(8)
            if (DllCall("user32\GetCursorPos", "Ptr", point, "Int"))
                this.ApplyPick(this.ui, "point", NumGet(point, 0, "Int"), NumGet(point, 4, "Int"), 0, 0)
        }
    }

    PickScreen(*) {
        ui := this.ui
        mode := this._pickMode
        if (!IsObject(ui) || mode == "" || this._pickAction != "")
            return
        while (GetKeyState("LButton", "P") && this.ui == ui && this._pickMode == mode)
            Sleep(15)
        if (this.ui != ui || this._pickMode != mode || this._pickAction != ""
            || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        action := this.ApplyPick.Bind(this, ui, mode)
        this._pickAction := action
        cancelKeys := WinHotkey.Register(["Escape"], this.CancelPick.Bind(this), ui.wpfHwnd)
        try {
            ui.Update("BtnCmdF1", "Tag", "1")
            if (mode == "area")
                this._areaPreview.Hide()
            TogSelectArea(true, action, true, mode == "point")
        } finally {
            WinHotkey.UnregisterAll(cancelKeys)
            if (this._pickAction == action)
                this._pickAction := ""
            if (this.ui == ui) {
                ui.Update("BtnCmdF1", "Tag", "0")
                this.RefreshAreaPreview()
            }
        }
    }

    CancelPick(*) {
        if (this._pickAction != "" && MainSoftData.SelectAreaAction == this._pickAction)
            SelectAreaCancel()
    }

    ApplyPick(ui, mode, x1, y1, x2, y2) {
        if (this.ui != ui || this._pickMode != mode)
            return
        if (mode == "area") {
            this.ApplyRegion(ui, x1, y1, x2, y2)
        } else {
            ui.BatchUpdate([
                {ControlName: "PosX", PropertyName: "Text", Value: String(x1)},
                {ControlName: "PosY", PropertyName: "Text", Value: String(y1)}])
        }
    }

    ApplyRegion(ui, x1, y1, x2, y2) {
        if (this.ui != ui || this._pickMode != "area" || x2 <= x1 || y2 <= y1)
            return
        ui.BatchUpdate([
            {ControlName: "RegionStartX", PropertyName: "Text", Value: String(x1)},
            {ControlName: "RegionStartY", PropertyName: "Text", Value: String(y1)},
            {ControlName: "RegionEndX", PropertyName: "Text", Value: String(x2)},
            {ControlName: "RegionEndY", PropertyName: "Text", Value: String(y2)}])
        this.RefreshAreaPreview()
    }

    ToggleAreaPreview(*) {
        if (this._pickMode == "area" && this._pickAction == "")
            this.SetAreaPreview(!this._previewShowing)
    }

    SetAreaPreview(showing) {
        this._previewShowing := showing
        this.ui.Update("BtnPreviewArea", "Tag", showing ? "1" : "0")
        this.RefreshAreaPreview()
    }

    RefreshAreaPreview(*) {
        if (!this._previewShowing || this._pickAction != "" || this._pickMode != "area") {
            this._areaPreview.Hide()
            return
        }
        ui := this.ui
        state := ui.Query("RegionStartX", "RegionStartY", "RegionEndX", "RegionEndY")
        x1 := state.Get("RegionStartX", ""), y1 := state.Get("RegionStartY", "")
        x2 := state.Get("RegionEndX", ""), y2 := state.Get("RegionEndY", "")
        resolve := (value) => value
        try {
            x := PromptRangeAxis(x1, x2, "", resolve)
            y := PromptRangeAxis(y1, y2, "", resolve)
        } catch ValueError {
            this._areaPreview.Hide()
            return
        }
        this._areaPreview.Show(x[1], y[1], x[2], y[2], this.ApplyRegion.Bind(this, ui))
    }

    ReadRegion(data, state) {
        for axis, size in Map("X", "Width", "Y", "Height") {
            start := Trim(state.Get("RegionStart" axis, ""))
            end := Trim(state.Get("RegionEnd" axis, ""))
            if (start == "" || (end == "" && this.RegionEnd(this.data, axis, size) != ""))
                throw ValueError(GetLang("提示参数不能为空") ": " GetLang("框选范围"))
            if (IsNumber(start) && (end == "" ? IsNumber(data.%size%) : IsNumber(end)))
                PromptRangeAxis(start, end, data.%size%, (value) => value)
            startField := "Pos" axis, endField := "EndPos" axis
            data.%startField% := start
            data.%endField% := end
        }
    }

    ReadData() {
        data := this.data.Clone()
        state := this.ui.Query("*")
        this.ReadChoices(data, state)
        for name, field in this.fields {
            if (name == "Remark" || field.options.Length || field.kind == "tools" || !this.FieldVisible(name, data))
                continue
            value := state.Get(name, "")
            data.%name% := name == "Text" ? GetLangStr(value, 2)
                : field.kind == "name" ? TranslateBuiltinVarReferences(Trim(value)) : Trim(value)
            if (name != "Text" && field.kind != "name" && data.%name% == "")
                throw ValueError(GetLang("提示参数不能为空") ": " GetLang(field.label))
        }
        if (this.FieldVisible("Text", data) && data.Type != "区域高亮" && Trim(data.Text) == "") {
            if (data.Type == "音频")
                throw ValueError(GetLang("提示参数不能为空") ": " GetLang("语音文本"))
            throw ValueError(GetLang("提示内容不能为空"))
        }
        if (this.PickMode(data) == "area")
            this.ReadRegion(data, state)
        if (data.Type == "倒计时" && data.CountDownMode == "显示")
            this.ReadCountDownTime(data, state)
        for name, range in Map("PosX", [-32768, 32767], "PosY", [-32768, 32767],
            "Duration", [1, 600000], "FlashDuration", [50, 5000], "FlashCount", [1, 20]) {
            if (this.FieldVisible(name, data) && IsNumber(data.%name%))
                PromptInt(data.%name%, range[1], range[2])
        }
        if (this.FieldVisible("Color", data) && !InStr(data.Color, "{") && !RegExMatch(data.Color, "i)^#?[0-9a-f]{6}$"))
            throw ValueError(GetLang("颜色使用六位十六进制 RGB"))
        if (this.FieldVisible("Monitors", data) && !InStr(data.Monitors, "{"))
            PromptMonitorNumbers(data.Monitors)
        return data
    }

    ReadCountDownTime(data, state) {
        if (data.Param2 == "时间戳") {
            data.Param1 := GetVarName(data.Param1)
            return
        }
        duration := data.Param2 == "时长"
        prefix := duration ? "CountDownDuration" : "CountDownClock"
        parts := []
        for part in ["Hour", "Min", "Sec"]
            parts.Push(GetVarName(Trim(state.Get(prefix part, ""))))
        if (!duration && this.legacyClock != "" && parts[1] == GetVarName(this.legacyClock)
            && parts[2] == "00" && parts[3] == "00") {
            data.Param1 := this.legacyClock
            return
        }
        limits := duration ? [8760, 525600, 31536000] : [23, 59, 59]
        for i, value in parts {
            if (value == "")
                throw ValueError(GetLang("提示参数不能为空") ": " GetLang(["小时", "分钟", "秒数"][i]))
            if (IsNumber(value))
                PromptInt(value, 0, limits[i])
        }
        if (!duration) {
            data.Param1 := parts[1] ":" parts[2] ":" parts[3]
            return
        }
        data.Hour := parts[1], data.Min := parts[2], data.Sec := parts[3]
        if (IsNumber(data.Hour) && IsNumber(data.Min) && IsNumber(data.Sec) && data.Hour * 3600 + data.Min * 60 + data.Sec <= 0)
            throw ValueError(GetLang("倒计时时长必须大于零"))
        data.Seconds := 0
    }

    GetCommand(data, preview := false) {
        if (preview) {
            if (this.previewSerial == "")
                this.previewSerial := GetCMDSerialStr("提示")
            data.SerialStr := this.previewSerial
        } else if (data.SerialStr == "")
            data.SerialStr := GetCMDSerialStr("提示")
        command := FormatCommandAutoRemark(data, this.ui.Query("Remark"), this._autoRemark, GenerateCommandAutoRemark, !preview)
        SaveMacroCMDData(data)
        return command
    }

    Save(*) {
        try command := this.GetCommand(this.ReadData())
        catch as err {
            RmtDialog.Info(err.Message, "", "Owner" this.ui.wpfHwnd)
            return
        }
        action := this.SureBtnAction
        this.Close()
        action(command)
    }

    Preview(*) {
        try command := this.GetCommand(this.ReadData(), true)
        catch as err {
            RmtDialog.Info(err.Message, "", "Owner" this.ui.wpfHwnd)
            return
        }
        try OnTriggerSepcialItemMacro(command)
        finally {
            CfgDelete(PromptFile, SettingSection, this.previewSerial)
            if (MySoftData.DataCacheMap.Has(this.previewSerial))
                MySoftData.DataCacheMap.Delete(this.previewSerial)
        }
    }

    OnLoaded(ui, *) {
        if (this.ui == ui) {
            XamlWin.OnLoadTheme(ui)
            this._playHotkeys := WinHotkey.Register(["!l"], (*) => this.Preview(), ui.wpfHwnd)
            this.Refresh()
        }
    }

    OnClosing(ui, *) {
        if (this.ui != ui)
            return
        WinHotkey.UnregisterAll(this._playHotkeys)
        this._playHotkeys := []
        this.CancelPick()
        this.BindPickHotkey("")
        this._previewShowing := false
        this._areaPreview.Hide()
        if (this.HasOwnProp("disabledOwner")) {
            try SafeGuiFromHwnd(this.disabledOwner).Opt("-Disabled")
            this.DeleteProp("disabledOwner")
        }
        this.ui := ""
        this._closed := true
    }

    Close(*) {
        ui := this.ui
        this.OnClosing(ui)
        if (IsObject(ui))
            try ui.Update("Window", "Close", "")
    }
}
