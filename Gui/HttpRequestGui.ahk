#Requires AutoHotkey v2.0

; 复用标准指令窗口的生命周期、主题和模态关闭处理。
class HttpRequestGui extends CommentGui {
    static Fields := ["Url", "Headers", "Body", "TimeoutMs", "Retries", "StatusVar", "ResponseVar", "ErrorVar"]

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("网络请求编辑器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "*")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,10")
        this._Field(body, "备注：", "Remark", false)
        this._Choice(body, "方法：", "Method", ["GET", "POST", "PUT", "DELETE"])
        this._Field(body, "URL：", "Url", false)
        this._Field(body, "Header：", "Headers", true, 78)
        this._Choice(body, "Body 类型：", "BodyType", ["JSON", "表单", "原始文本"])
        this._Field(body, "Body：", "Body", true, 110)
        body.Add("TextBlock").Text(GetLang("URL、Header 值和 Body 支持 {变量名}；GET 不发送 Body。"))
            .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap").Margin("0,4,0,2")
        body.Add("TextBlock").Text(GetLang("Header 每行 名称: 值；表单每行 名称=值（自动编码）。"))
            .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap").Margin("0,0,0,6")
        this._Field(body, "超时（毫秒）：", "TimeoutMs", false)
        this._Field(body, "失败重试次数：", "Retries", false)
        this._Field(body, "状态码变量：", "StatusVar", false)
        this._Field(body, "响应体变量：", "ResponseVar", false)
        this._Field(body, "错误信息变量：", "ErrorVar", false)
        body.Add("TextBlock").Text(GetLang("网络失败状态码为 0；重试可能重复提交，默认不重试。"))
            .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap").Margin("0,6")
        buttons := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,8,0,0")
        AddCmdOkBtn(buttons)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnClickSureBtn"))
        BindCmdEditorChrome(this.ui, "#指令手册/网络请求")
    }

    _Row(body, label) {
        row := body.Add("Grid").Margin("0,3")
        row.Cols("110", "*")
        row.Add("TextBlock").Text(GetLang(label)).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        return row
    }

    _Field(body, label, name, multiline, height := 28) {
        box := this._Row(body, label).Add("TextBox").Name(name).Grid_Column(1).Height(height).MinHeight(height)
            .Padding("4,2").Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (multiline)
            box.AcceptsReturn("True").TextWrapping("Wrap").VerticalContentAlignment("Top").ScrollViewer_VerticalScrollBarVisibility("Auto")
        else
            box.VerticalContentAlignment("Center")
    }

    _Choice(body, label, name, values) {
        box := this._Row(body, label).Add("ComboBox").Name(name).Grid_Column(1).Height(28).MinHeight(28)
        for value in values
            box.Add("ComboBoxItem").Content(GetLang(value))
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : GetCMDSerialStr("网络请求")
        this.Data := GetMacroCMDData(this.SerialStr)
        this.ui.Update("Remark", "Text", parts.Length >= 2 ? parts[2] : "")
        for name in HttpRequestGui.Fields
            this.ui.Update(name, "Text", this.Data.%name%)
        for name, values in Map("Method", ["GET", "POST", "PUT", "DELETE"], "BodyType", ["JSON", "表单", "原始文本"]) {
            for i, value in values {
                if (value == this.Data.%name%)
                    this.ui.Update(name, "SelectedIndex", i - 1)
            }
        }
    }

    _ReadData() {
        data := HttpRequestData()
        data.SerialStr := this.Data.SerialStr
        for name in HttpRequestGui.Fields
            data.%name% := this.ui.Query(name)
        data.Method := this.ui.Query("Method")
        data.BodyType := GetLangKey(this.ui.Query("BodyType"))
        for name in ["StatusVar", "ResponseVar", "ErrorVar"]
            data.%name% := GetVarName(Trim(data.%name%))
        return data
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
        return true
    }

    SaveData() {
        this.Data := this._ReadData()
        this.Data.TimeoutMs := Integer(this.Data.TimeoutMs)
        this.Data.Retries := Integer(this.Data.Retries)
        HttpRequestRegisterResults(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("网络请求") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }
}
