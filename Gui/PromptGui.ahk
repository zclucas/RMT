#Requires AutoHotkey v2.0

class PromptGui {
    __New() {
        this.ParentTile := ""
        this.OwnerHwnd := ""
        this.SureBtnAction := ""
        this.ui := ""
        this._closed := true
    }

    ShowGui(cmd) {
        if (IsObject(this.ui))
            this.Close()
        parts := cmd == "" ? [] : StrSplit(cmd, "_", , 2)
        serial := parts.Length ? parts[1] : ""
        this.data := serial == "" ? PromptData() : GetMacroCMDData(serial).Clone()
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
        XAMLHost.AddCmdTitleBar(main, title, titleHeight)
        body := main.Add("ScrollViewer").Grid_Row(1).MaxHeight(400).VerticalScrollBarVisibility("Auto")
            .Add("StackPanel").Margin("16,14,16,0")
        this.AddPair(body, &left, &right)
        this.AddField(left, "Type", "提示类型", PromptTypes())
        this.AddField(right, "Remark", "备注")

        this.AddPair(body, &left, &right)
        this.AddField(left, "AudioMode", "音频类型", ["系统提示音", "系统语音", "自定义音频"])
        this.AddField(left, "TipMode", "内容类型", ["文本", "图片"])
        this.AddField(left, "PasteMode", "操作", ["文本", "图片", "关闭", "关闭所有"])
        this.AddField(left, "FlashMode", "显示屏", ["主屏", "副屏", "主副屏", "自定义"])
        this.AddField(left, "CountDownMode", "操作", ["显示", "关闭", "关闭所有"])
        this.AddField(right, "Beep", "系统提示音", PromptBeepModes())
        this.AddField(right, "AudioWait", "播放时", ["不等待", "等待结束"])
        this.AddField(right, "TextSource", "内容来源", ["直接填写", "剪贴板"])
        this.AddField(right, "PasteTextSource", "内容来源", ["直接填写", "剪贴板", "剪贴板图文"])
        this.AddField(right, "ImageSource", "内容来源", ["文件", "剪贴板"])
        this.AddField(right, "Monitors", "屏幕编号").ToolTip(GetLang("多个屏幕编号用逗号分隔"))
        this.AddField(right, "Param2", "计时方式", ["时长", "时刻", "时间戳"])

        this.AddPair(body, &left, &right)
        this.AddField(left, "PasteName", "贴片名称").ToolTip(GetLang("同名贴片会替换，关闭时留空则关闭最后一张"))
        this.AddField(left, "Duration", "显示时长（毫秒）")
        this.AddField(left, "Hour", "小时")
        this.AddField(right, "Min", "分钟")

        this.AddPair(body, &left, &right)
        this.AddField(left, "Sec", "秒数")
        this.AddField(left, "Param1", "目标时间").ToolTip("HH:mm:ss / YYYYMMDDHHmmss / Unix")
        this.AddField(right, "WaitEnd", "显示后", ["不等待", "等待结束"])

        this.AddPair(body, &left, &right)
        this.AddField(left, "PosX", "屏幕 X")
        this.AddField(right, "PosY", "屏幕 Y")

        this.AddPair(body, &left, &right)
        this.AddField(left, "Width", "区域宽度（像素）")
        this.AddField(right, "Height", "区域高度（像素）")

        this.AddPair(body, &left, &right)
        position := this.AddField(left, "PickPosition", "屏幕坐标", , "tools")
        position.Add("Button").Name("PickPosition").MinHeight(28).Content(GetLang("取鼠标位置（2 秒后）"))
        region := this.AddField(right, "PickRegion", "区域高亮", , "tools")
        region.Add("Button").Name("PickRegion").MinHeight(28).Content(GetLang("框选区域"))

        this.AddPair(body, &left, &right)
        this.AddField(left, "Color", "颜色（RRGGBB）")
        this.AddField(right, "Thickness", "边框粗细（像素）")

        this.AddPair(body, &left, &right)
        this.AddField(left, "FlashDuration", "单次闪光（毫秒）")
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
        for name in GetGuiVarArr(1) {
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
            'Title="' EscapeXamlXml(title) '" Width="560" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "LoadedHwnd", this.OnLoaded.Bind(this, this.ui))
        this.ui.OnEvent("Window", "Closing", this.OnClosing.Bind(this, this.ui))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "Close"))
        BindCmdEditorChrome(this.ui, "#指令手册/30-提示", this.Preview.Bind(this))
        this.ui.Update("BtnCmdPlay", "ToolTip", GetLang("执行"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "Save"))
        this.ui.OnEvent("PickPosition", "Click", this.PickPosition.Bind(this))
        this.ui.OnEvent("PickRegion", "Click", this.PickRegion.Bind(this))
        this.ui.OnEvent("InsertKind", "SelectionChanged", this.RefreshInsertNames.Bind(this))
        this.ui.OnEvent("AddName", "Click", this.AppendSelection.Bind(this, false))
        this.ui.OnEvent("AddValue", "Click", this.AppendSelection.Bind(this, true))
        this.ui.OnEvent("BrowseImagePath", "Click", this.Browse.Bind(this, "ImagePath", "Images (*.png; *.jpg; *.jpeg; *.bmp; *.gif; *.ico)"))
        this.ui.OnEvent("BrowseAudioPath", "Click", this.Browse.Bind(this, "AudioPath", "Audio (*.wav; *.mp3; *.wma; *.mid)"))
        for name, field in this.fields {
            if (field.kind == "tools")
                continue
            this.ui.Track(name)
            if (field.options.Length) {
                if (name != "Beep" && name != "WaitEnd" && name != "AudioWait")
                    this.ui.OnEvent(name, "SelectionChanged", this.Refresh.Bind(this))
            } else
                this.ui.Update(name, "Text", name == "Remark" ? this.remark
                    : name == "Text" ? GetLangStr(this.data.Text, 1) : String(this.data.%name%))
        }
    }

    AddPair(body, &left, &right) {
        row := body.Add("Grid").Cols("*", "14", "*")
        left := row.Add("StackPanel")
        right := row.Add("StackPanel").Grid_Column(2)
    }

    AddField(body, name, label, options := [], kind := "") {
        this.fields[name] := {label: label, options: options, kind: kind}
        row := body.Add("Grid").Name("Row" name).Margin("0,0,0,8")
        row.Visibility(this.FieldVisible(name, this.data) ? "Visible" : "Collapsed")
        caption := row.Add("TextBlock").Text(GetLang(label))
        if (kind == "multiline") {
            row.Rows("Auto", "Auto")
            caption.Margin("0,0,0,4")
            target := row.Add("Grid").Grid_Row(1)
        } else {
            row.Cols("Auto", "*")
            caption.MaxWidth(132).TextWrapping("Wrap").VerticalAlignment("Center").Margin("0,0,8,0")
            target := row.Add("Grid").Grid_Column(1)
        }
        if (kind == "tools")
            return target
        if (options.Length) {
            index := 0
            for i, value in options {
                if (this.data.%name% == value)
                    index := i - 1
            }
            combo := target.Add("ComboBox").Name(name).MinHeight(28).SelectedIndex(index)
            for value in options
                combo.Add("ComboBoxItem").Content(GetLang(value))
            return combo
        }
        if (kind == "file") {
            target.Cols("*", 80)
            target.Add("Button").Grid_Column(1).Name("Browse" name).Margin("6,0,0,0").Content(GetLang("浏览"))
        }
        box := target.Add("TextBox").Name(name).MinHeight(28).Padding("6,2").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}")
        if (kind == "multiline")
            box.Height(112).Padding("6,4").VerticalContentAlignment("Top").AcceptsReturn("True").TextWrapping("Wrap").ScrollViewer_VerticalScrollBarVisibility("Auto")
        return box
    }

    FieldVisible(name, data) {
        type := data.Type
        tip := type == "临时提示"
        paste := type == "自由贴"
        region := type == "区域高亮"
        flash := type == "屏幕边缘闪光"
        audio := type == "音频"
        countdown := type == "倒计时"
        showTimer := countdown && data.CountDownMode == "显示"
        tipText := tip && data.TipMode == "文本"
        pasteText := paste && data.PasteMode == "文本"
        image := tip && data.TipMode == "图片" || paste && data.PasteMode == "图片"
        text := type == "软件弹窗" || audio && data.AudioMode == "系统语音" || region
            || tipText && data.TextSource == "直接填写" || pasteText && data.PasteTextSource == "直接填写"
        switch name {
            case "AudioMode": return audio
            case "TipMode": return tip
            case "PasteMode": return paste
            case "FlashMode": return flash
            case "CountDownMode": return countdown
            case "TextSource": return tipText
            case "PasteTextSource": return pasteText
            case "ImageSource": return image
            case "Text", "Vars": return text
            case "ImagePath": return image && data.ImageSource == "文件"
            case "AudioPath", "AudioWait": return audio && data.AudioMode == "自定义音频"
            case "Beep": return audio && data.AudioMode == "系统提示音"
            case "PasteName": return paste && data.PasteMode != "关闭所有"
            case "PosX", "PosY", "PickPosition": return region || countdown && data.CountDownMode != "关闭所有"
            case "Width", "Height", "PickRegion": return region
            case "Color", "Thickness": return region || flash
            case "Duration": return tip || region
            case "FlashDuration", "FlashCount": return flash
            case "Monitors": return flash && data.FlashMode == "自定义"
            case "Param2", "WaitEnd": return showTimer
            case "Hour", "Min", "Sec": return showTimer && data.Param2 == "时长"
            case "Param1": return showTimer && data.Param2 != "时长"
            default: return true
        }
    }

    ReadChoices(data, state) {
        for name, field in this.fields {
            if (field.options.Length) {
                value := state.Get(name, "")
                for option in field.options {
                    if (GetLang(option) == value) {
                        data.%name% := option
                        break
                    }
                }
            }
        }
    }

    Refresh(*) {
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        data := this.data.Clone()
        this.ReadChoices(data, this.ui.Query("*"))
        changes := []
        for name in this.fields
            changes.Push({ControlName: "Row" name, PropertyName: "Visibility", Value: this.FieldVisible(name, data) ? "Visible" : "Collapsed"})
        this.ui.BatchUpdate(changes)
    }

    Browse(field, filter, *) {
        path := FileSelect(1, this.ui.Query(field), GetLang("选择文件"), filter)
        if (path != "" && IsObject(this.ui))
            this.ui.Update(field, "Text", path)
    }

    RefreshInsertNames(*) {
        if (!IsObject(this.ui) || !this.ui.wpfHwnd)
            return
        names := this.ui.Query("InsertKind") == GetLang("数组") ? GetGuiArrNameArr() : GetGuiVarArr(1)
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

    PickPosition(*) {
        ui := this.ui
        ui.Update("PickPosition", "IsEnabled", "False")
        SetTimer(this.ApplyPosition.Bind(this, ui), -2000)
    }

    ApplyPosition(ui) {
        if (this.ui != ui)
            return
        point := Buffer(8)
        if (DllCall("user32\GetCursorPos", "Ptr", point, "Int")) {
            ui.Update("PosX", "Text", String(NumGet(point, 0, "Int")))
            ui.Update("PosY", "Text", String(NumGet(point, 4, "Int")))
        }
        ui.Update("PickPosition", "IsEnabled", "True")
    }

    PickRegion(*) {
        if (MainSoftData.SelectAreaAction == "")
            TogSelectArea(true, this.ApplyRegion.Bind(this, this.ui), false)
    }

    ApplyRegion(ui, x1, y1, x2, y2) {
        if (this.ui != ui || x2 <= x1 || y2 <= y1)
            return
        ui.BatchUpdate([
            {ControlName: "PosX", PropertyName: "Text", Value: String(x1)},
            {ControlName: "PosY", PropertyName: "Text", Value: String(y1)},
            {ControlName: "Width", PropertyName: "Text", Value: String(x2 - x1)},
            {ControlName: "Height", PropertyName: "Text", Value: String(y2 - y1)}])
    }

    ReadData() {
        data := this.data.Clone()
        state := this.ui.Query("*")
        this.ReadChoices(data, state)
        for name, field in this.fields {
            if (name == "Remark" || field.options.Length || field.kind == "tools" || !this.FieldVisible(name, data))
                continue
            value := state.Get(name, "")
            data.%name% := name == "Text" ? GetLangStr(value, 2) : Trim(value)
            if (name != "Text" && name != "PasteName" && data.%name% == "")
                throw ValueError(GetLang("提示参数不能为空") ": " GetLang(field.label))
        }
        if (this.FieldVisible("Text", data) && data.Type != "区域高亮" && Trim(data.Text) == "")
            throw ValueError(GetLang("提示内容不能为空"))
        if (this.FieldVisible("Hour", data)) {
            if (IsNumber(data.Hour) && IsNumber(data.Min) && IsNumber(data.Sec) && data.Hour * 3600 + data.Min * 60 + data.Sec <= 0)
                throw ValueError(GetLang("倒计时时长必须大于零"))
            data.Seconds := 0
        }
        for name, range in Map("PosX", [-32768, 32767], "PosY", [-32768, 32767], "Width", [1, 32767], "Height", [1, 32767],
            "Duration", [1, 600000], "Thickness", [1, 100], "FlashDuration", [50, 5000], "FlashCount", [1, 20],
            "Hour", [0, 8760], "Min", [0, 525600], "Sec", [0, 31536000]) {
            if (this.FieldVisible(name, data) && IsNumber(data.%name%))
                PromptInt(data.%name%, range[1], range[2])
        }
        if (this.FieldVisible("Color", data) && !InStr(data.Color, "{") && !RegExMatch(data.Color, "i)^#?[0-9a-f]{6}$"))
            throw ValueError(GetLang("颜色使用六位十六进制 RGB"))
        if (this.FieldVisible("Monitors", data) && !InStr(data.Monitors, "{"))
            PromptMonitorNumbers(data.Monitors)
        return data
    }

    GetCommand(data, preview := false) {
        if (preview) {
            if (this.previewSerial == "")
                this.previewSerial := GetCMDSerialStr("提示")
            data.SerialStr := this.previewSerial
        } else if (data.SerialStr == "")
            data.SerialStr := GetCMDSerialStr("提示")
        SaveMacroCMDData(data)
        SplitSerialTextAndNumbers(data.SerialStr, &key, &number)
        return CorrectRemark(GetLang("提示") number, this.ui.Query("Remark"))
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
        if (this.ui == ui)
            XamlWin.OnLoadTheme(ui)
    }

    OnClosing(ui, *) {
        if (this.ui != ui)
            return
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
