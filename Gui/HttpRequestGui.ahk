#Requires AutoHotkey v2.0

; 复用标准指令窗口的生命周期、主题和模态关闭处理。
class HttpRequestGui extends CommentGui {
    static Fields := ["Url", "Headers", "Body", "StatusVar", "ResponseVar", "ErrorVar"]
    static Methods := ["GET", "POST", "PUT", "DELETE"]
    static BodyTypes := ["JSON", "表单", "原始文本"]
    static ResultFields := ["StatusVar", "ResponseVar", "ErrorVar"]
    _textEditor := ""

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("网络请求编辑器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,10").Grid_IsSharedSizeScope("True")
        request := body.Add("Grid").Cols("*", 16, "*")
        method := this._Row(request, "类型：").Add("Grid").Grid_Column(1).Cols("*", "Auto")
        this._Choice(method, "Method", HttpRequestGui.Methods)
        method.Add("Button").Grid_Column(1).Name("BtnMethodHelp").Content("?").ToolTip(GetLang("请求类型说明"))
            .Width(28).Height(28).MinHeight(28).Margin("6,0,0,0").Padding("0").Cursor("Hand")
        remark := this._Row(request, "备注：").Grid_Column(2)
        this._TextBox(remark, "Remark").Grid_Column(1)
        this._Field(body, "URL：", "Url", false)
        this._Field(body, "Header：", "Headers", true, 78)
        payload := body.Add("StackPanel").Name("BodySettings")
        style := payload.Add("StackPanel.Style").Add("Style").TargetType("StackPanel")
        style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding SelectedIndex, ElementName=Method}").Value("0")
            .Add("Setter").Property("Visibility").Value("Collapsed")
        this._Choice(this._Row(payload, "Body 类型："), "BodyType", HttpRequestGui.BodyTypes).Grid_Column(1)
        this._Field(payload, "Body：", "Body", true, 110)

        options := body.Add("Grid")
        options.Rows("Auto", "Auto")
        options.Cols("*", 16, "*")
        this._Option(options, 0, 0, "状态码变量：", "StatusVar", "保存 HTTP 状态码，未收到响应时为 0。")
        this._Option(options, 0, 2, "响应体变量：", "ResponseVar", "保存服务器返回的响应体，包括 HTTP 错误响应的正文。")
        this._Option(options, 1, 0, "错误体变量：", "ErrorVar", "保存 HTTP 错误状态或请求失败信息，无错误时为空。")
        CommandTimeoutFields.Add(body, false, "HttpRequestLabel", "HttpRequestLabel")
        buttons := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
        AddCmdOkBtn(buttons)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnMethodHelp", "Click", (*) => SetTimer(ObjBindMethod(this, "_ShowMethodHelp", this.ui), -1))
        for name in ["Headers", "Body"]
            this.ui.OnEvent("BtnEdit" name, "Click", ObjBindMethod(this, "_QueueTextEditor", name))
        BindCmdEditorChrome(this.ui, "#指令手册/网络请求")
    }

    _Row(body, label, tip := "") {
        if (label == "Header：")
            tip := GetLang("Header 每行 名称: 值；")
        return CmdEditorForm.Row(body, label, , "HttpRequestLabel", , , tip).Margin("0,3")
    }

    _Field(body, label, name, multiline, height := 28) {
        row := this._Row(body, label)
        if (!multiline) {
            this._TextBox(row, name, height).Grid_Column(1)
            return
        }
        host := row.Add("Grid").Grid_Column(1)
        this._TextBox(host, name, height).AcceptsReturn("True").TextWrapping("Wrap").Padding("2,3,15,3")
            .VerticalContentAlignment("Top").ScrollViewer_VerticalScrollBarVisibility("Auto")
        host.Add("Button").Name("BtnEdit" name).Width(22).Height(22).MinHeight(22).Padding("0")
            .HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,4,4,0").Cursor("Hand")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12).Content(Chr(0xE70F))
            .ToolTip(GetLang("编辑")).Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1)
    }

    _TextBox(parent, name, height := 28) {
        return parent.Add("TextBox").Name(name).Height(height).MinHeight(height).VerticalContentAlignment("Center")
            .Padding("2,2").Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
    }

    _Choice(parent, name, values) {
        box := parent.Add("ComboBox").Name(name).Height(28).MinHeight(28).Padding("7,0,23,0").SelectedIndex(0)
        for value in values
            box.Add("ComboBoxItem").Content(GetLang(value)).Tag(value)
        return box
    }

    _Option(grid, row, column, label, name, tip) {
        tip := GetLang(tip)
        field := this._Row(grid, label, tip).Grid_Row(row).Grid_Column(column)
        ; 可编辑下拉内部的 TextBox 自带 2 DIP 文本留白。
        field.Add("ComboBox").Name(name).Height(28).MinHeight(28).IsEditable("True").Padding("5,0,21,0").Grid_Column(1)
    }

    _ShowMethodHelp(ui) {
        if (this.ui != ui)
            return
        info := GetLang("GET 获取数据，POST 提交数据")
            . "`n" GetLang("PUT 更新资源，DELETE 删除资源")
            . "`n`n" GetLang("Header 每行 名称: 值；")
            . "`n" Format(GetLang("表单每行 名称{1}值（自动编码）。"), "=")
            . "`n" GetLang("网络失败状态码为 0；")
        RmtDialog.Info(info, GetLang("请求类型说明"), "Owner" this.Hwnd())
    }

    _QueueTextEditor(name, *) {
        SetTimer(ObjBindMethod(this, "_OpenTextEditor", this.ui, name), -1)
    }

    _OpenTextEditor(ui, name) {
        if (this.ui != ui)
            return
        if (!IsObject(this._textEditor))
            this._textEditor := CharVarEditGui()
        this._textEditor.OwnerHwnd := this.Hwnd()
        this._textEditor.ParentTile := this.ParentTile
        this._textEditor.SureBtnAction := (text) => this.ui == ui ? ui.Update(name, "Text", text) : ""
        this._textEditor.ShowGui(ui.Query(name))
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr("网络请求")
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        action := TimeoutPolicy.Get(this.Data)
        if (action == "")
            action := TimeoutPolicy.LegacyRetryAction(this.Data.Retries)
        CommandTimeoutFields.Init(this.ui, this.Data.TimeoutMs, action,
            InputField(this.Data, "TimeoutStatusVar", TimeoutPolicy.DefaultStatusVar))
        for varName in GetGuiVarArr() {
            if (varName == "")
                continue
            for name in HttpRequestGui.ResultFields
                this._ComboPush(name, "AddItem", varName)
        }
        for name in HttpRequestGui.Fields
            this._ComboPush(name, "Text", this._TranslateReferences(name, this.Data.%name%, 1))
        for name, values in Map("Method", HttpRequestGui.Methods, "BodyType", HttpRequestGui.BodyTypes) {
            for i, value in values {
                if (value == this.Data.%name%) {
                    this._ComboPush(name, "SelectedIndex", i - 1)
                    break
                }
            }
        }
    }

    _ReadData() {
        data := HttpRequestData()
        data.SerialStr := this.Data.SerialStr
        for name in HttpRequestGui.Fields
            data.%name% := this._TranslateReferences(name, this.ui.Query(name), 2)
        data.Method := this.ui.Query("Method")
        data.BodyType := this.ui.Query("BodyType")
        CommandTimeoutFields.Read(this.ui, data)
        if (data.TimeoutAction == "")
            data.Retries := this.Data.Retries
        for name in HttpRequestGui.ResultFields
            data.%name% := GetVarName(Trim(data.%name%))
        return data
    }

    _TranslateReferences(field, text, mode) {
        if (!InStr(text, "{")
            || (field != "Url" && field != "Headers" && field != "Body"))
            return text
        for displayName in GetSpecialVarArr() {
            key := GetLangKey(displayName)
            if (key != displayName) {
                from := mode == 1 ? key : displayName
                to := mode == 1 ? displayName : key
                text := StrReplace(text, "{" from "}", "{" to "}", true)
            }
        }
        return text
    }

    CheckIfValid() {
        data := this._ReadData()
        try HttpRequestValidate(data)
        catch as e {
            RmtDialog.Info(GetLang(e.Message))
            return false
        }
        for name in [data.StatusVar, data.ResponseVar, data.ErrorVar] {
            if (!CheckVarNameIfValid(name))
                return false
        }
        if (data.StatusVar == data.ResponseVar || data.StatusVar == data.ErrorVar || data.ResponseVar == data.ErrorVar) {
            RmtDialog.Info(GetLang("三个结果变量名不能相同。"))
            return false
        }
        return CommandTimeoutFields.ValidateStatus(data, data.StatusVar, data.ResponseVar, data.ErrorVar)
    }

    SaveData() {
        this.Data := this._ReadData()
        if (IsInteger(this.Data.Retries))
            this.Data.Retries := Integer(this.Data.Retries)
        HttpRequestRegisterResults(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("网络请求") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }
}
