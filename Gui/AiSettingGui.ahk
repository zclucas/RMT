#Requires AutoHotkey v2.0

; =====================================================================
; AI 助手设置：模型商 / API URL / API Key / 模型 / 写入权限 / 指令审批
; 入口：侧栏 AI 工具栏「设置」；确定后即时 IniWrite
;
; 布局约定：
; - 内容内边距统一 ContentPadL=6（与全局 TextBox/对话输入一致）
; - ComboBox 显式 Padding，覆盖主题默认
; - 每行 Grid(Auto|*)，字段列 Stretch，避免固定 fieldW 造成右侧留白
; =====================================================================

class AiSettingGui {
    static instances := Map()
    static _opening := false
    ; 统一内容左缘（与「写入权限」下拉一致）；下拉右侧留箭头
    static ContentPadL := 6
    static ComboPad := "6,0,18,0"
    static CtrlH := 28

    __New() {
        this.ui := ""
        this.closed := true
        this._refreshing := false
        this._providerGuard := false
        this._revealed := false
        this._applying := false
    }

    static ShowGui() {
        key := "main"
        if (AiSettingGui.instances.Has(key)) {
            oldInst := AiSettingGui.instances[key]
            try {
                if (!oldInst.closed && IsObject(oldInst.ui)) {
                    try WinActivate("ahk_id " oldInst.ui.wpfHwnd)
                    return
                }
            }
            AiSettingGui.instances.Delete(key)
        }

        try XAMLHost.EnsureDaemonHealthy()
        if (AiSettingGui._opening)
            return
        AiSettingGui._opening := true
        try {
            inst := AiSettingGui()
            inst._BuildAndShow()
            AiSettingGui.instances[key] := inst
        } finally {
            AiSettingGui._opening := false
        }
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _StyleCombo(ctrl) {
        h := AiSettingGui.CtrlH
        ctrl.Height(h).MinHeight(h).MaxHeight(h).Padding(AiSettingGui.ComboPad)
            .VerticalContentAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        return ctrl
    }

    ; TextBox 主题模板对 Padding 表现与 Combo 不一致：外层 Border 承担边框+内边距，内层 TextBox 无边框
    ; 父级须为 Grid 且字段在 Column 1（*），本控件 Stretch 填满，不再写死 Width。
    _AddFieldTextBox(parent, name, gap) {
        h := AiSettingGui.CtrlH
        padL := AiSettingGui.ContentPadL
        host := parent.Add("Border").Name(name "_Host").Grid_Column(1)
            .Height(h).MinHeight(h).MaxHeight(h)
            .Margin(gap ",0,0,0").Padding(padL ",0," padL ",0").CornerRadius("3")
            .HorizontalAlignment("Stretch")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        tb := host.Add("TextBox").Name(name)
            .Height(h - 2).MinHeight(h - 2).VerticalContentAlignment("Center")
            .Padding("0").Margin("0").BorderThickness("0")
            .Foreground("{DynamicResource InputText}").Background("Transparent")
            .VerticalScrollBarVisibility("Disabled").HorizontalScrollBarVisibility("Disabled")
        return tb
    }

    _StyleActionBtn(ctrl) {
        h := AiSettingGui.CtrlH
        ctrl.Height(h).MinHeight(h).MaxHeight(h).Padding("8,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .SnapsToDevicePixels("True")
        return ctrl
    }

    _BuildAndShow() {
        AiAssist.EnsureDefaults()
        this.closed := false
        title := GetLang("AI 设置")
        titleHeight := "30"
        h := AiSettingGui.CtrlH

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; 右缘留白根因：StackPanel+固定 fieldW 不拉伸；内容宽≈386，窗宽460→右侧空约 30px。
        ; 改为每行 Grid(Auto|*)，字段列 HorizontalAlignment=Stretch 吃满 body。
        body := main.Add("Grid").Grid_Row(1).Margin("16,14,17,14")
        body.Rows("36", "36", "36", "36", "36", "44", "*")
        labelW := 64
        gap := 2
        midGap := 20    ; 写入权限下拉 与「指令审批」标签间距

        ; 行0：模型商
        row0 := body.Add("Grid").Grid_Row(0).VerticalAlignment("Center")
        row0.Cols(String(labelW), "*")
        row0.Add("TextBlock").Text(GetLang("模型商：")).Grid_Column(0).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        cmbProv := this._StyleCombo(row0.Add("ComboBox").Name("CmbAiProvider").Grid_Column(1).Margin(gap ",0,0,0").HorizontalAlignment("Stretch"))
        for p in AiAssist.Providers
            cmbProv.Add("ComboBoxItem").Content(GetLang(p["name"]))

        ; 行1：API URL
        row1 := body.Add("Grid").Grid_Row(1).VerticalAlignment("Center")
        row1.Cols(String(labelW), "*")
        row1.Add("TextBlock").Text(GetLang("API URL：")).Grid_Column(0).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddFieldTextBox(row1, "TxtAiBaseUrl", gap)
            .ToolTip(GetLang("OpenAI 兼容接口，例如 https://api.openai.com/v1"))

        ; 行2：API Key
        row2 := body.Add("Grid").Grid_Row(2).VerticalAlignment("Center")
        row2.Cols(String(labelW), "*")
        row2.Add("TextBlock").Text(GetLang("API Key：")).Grid_Column(0).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddFieldTextBox(row2, "TxtAiApiKey", gap)

        ; 行3：模型列表 + 刷新
        row3 := body.Add("Grid").Grid_Row(3).VerticalAlignment("Center")
        row3.Cols(String(labelW), "*")
        row3.Add("TextBlock").Text(GetLang("模型列表：")).Grid_Column(0).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        modelHost := row3.Add("Grid").Grid_Column(1).Height(h).Margin(gap ",0,0,0").HorizontalAlignment("Stretch")
        modelHost.Cols("*", "Auto")
        this._StyleCombo(modelHost.Add("ComboBox").Name("CmbAiModel").Grid_Column(0).Margin("0,0," gap ",0").HorizontalAlignment("Stretch").IsEditable("True"))
        this._StyleActionBtn(modelHost.Add("Button").Name("BtnRefreshModels").Grid_Column(1).Content(GetLang("刷新")))

        ; 行4：写入权限 + 指令审批（两侧 * 等宽）
        row4 := body.Add("Grid").Grid_Row(4).VerticalAlignment("Center")
        row4.Cols(String(labelW), "*")
        row4.Add("TextBlock").Text(GetLang("写入权限：")).Grid_Column(0).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        permHost := row4.Add("Grid").Grid_Column(1).Height(h).Margin(gap ",0,0,0").HorizontalAlignment("Stretch")
        permHost.Cols("*", "Auto", "*")
        cmbAccess := this._StyleCombo(permHost.Add("ComboBox").Name("CmbAiAccess").Grid_Column(0)
            .Margin("0,0,10,0").HorizontalAlignment("Stretch")
            .ToolTip(GetLang("只读：只能读取任意文件内容") "`n" GetLang("工作区：可以读取任意文件，写入仅限软件目录") "`n" GetLang("完全访问：没有任何读写限制")))
        for lab in AiAssist.AccessLabels
            cmbAccess.Add("ComboBoxItem").Content(GetLang(lab))
        permHost.Add("TextBlock").Grid_Column(1).Text(GetLang("指令审批："))
            .VerticalAlignment("Center").HorizontalAlignment("Center")
            .Margin(midGap ",0," midGap ",0")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        cmbAppr := this._StyleCombo(permHost.Add("ComboBox").Name("CmbAiApproval").Grid_Column(2)
            .Margin("10,0,0,0").HorizontalAlignment("Stretch"))
        for lab in AiAssist.ApprovalLabels
            cmbAppr.Add("ComboBoxItem").Content(GetLang(lab))

        btnRow := body.Add("StackPanel").Grid_Row(5).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Height(28).MinHeight(28).Padding("18,0")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="460" SizeToContent="Height" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("CmbAiProvider", "SelectionChanged", ObjBindMethod(this, "OnProviderChanged"))
        this.ui.OnEvent("BtnRefreshModels", "Click", ObjBindMethod(this, "OnRefreshClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnOkClick"))

        ; 主题界面同款：Show 前入队主题+表单值，LoadedHwnd 一次刷入再揭盖，避免空壳/多次刷新闪烁
        this._applying := true
        this._revealed := false
        XamlWin.OnLoadTheme(this.ui)
        this._ApplyCurrent()

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
        SetTimer(ObjBindMethod(this, "_ReleaseApplyingGuard"), -200)
    }

    _TryReveal() {
        if (this._revealed || this.closed || !IsObject(this.ui))
            return
        if (!this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd)
            return
        this._revealed := true
        try this.ui.Update("Window", "Opacity", "1")
    }

    _ReleaseApplyingGuard(*) {
        this._applying := false
        this._providerGuard := false
    }

    _ApplyCurrent() {
        AiAssist.EnsureDefaults()
        this._providerGuard := true
        try {
            pIdx := AiAssist.ProviderIndex(MainSoftData.AiProvider) - 1
            this.ui.Update("CmbAiProvider", "SelectedIndex", String(pIdx))
            this.ui.Update("TxtAiBaseUrl", "Text", MainSoftData.AiApiBaseUrl)
            this._ApplyUrlEditable(this._IsUrlEditable(MainSoftData.AiProvider))
            this.ui.Update("TxtAiApiKey", "Text", MainSoftData.AiApiKey)
            this._FillModelCombo(AiAssist.ModelListArr(), MainSoftData.AiModel)
            this.ui.Update("CmbAiAccess", "SelectedIndex", String(MainSoftData.AiAccessMode - 1))
            this.ui.Update("CmbAiApproval", "SelectedIndex", String(MainSoftData.AiApprovalMode - 1))
        } catch {
        }
        ; 打开流程：守卫延后到 _ReleaseApplyingGuard，避免 LoadedHwnd 刷入时 SelectionChanged 误改 URL
        if (!this._applying)
            this._providerGuard := false
    }

    _ApplyUrlEditable(editable) {
        ; 外层 Host 一并禁用，避免只读态边框与内层不一致
        try this.ui.Update("TxtAiBaseUrl_Host", "IsEnabled", editable ? "True" : "False")
        try this.ui.Update("TxtAiBaseUrl", "IsEnabled", editable ? "True" : "False")
        try this.ui.Update("TxtAiBaseUrl", "IsReadOnly", editable ? "False" : "True")
    }

    _IsUrlEditable(providerId) {
        for p in AiAssist.Providers {
            if (p["id"] = providerId)
                return (p["id"] = "custom" || Trim(p["url"]) == "")
        }
        return true
    }

    _FillModelCombo(ids, selected := "") {
        if (!IsObject(this.ui))
            return
        this.ui.Update("CmbAiModel", "ClearItems", "")
        for id in ids {
            if (Trim(id) == "")
                continue
            this.ui.Update("CmbAiModel", "AddItem", id)
        }
        if (selected != "")
            this.ui.Update("CmbAiModel", "Text", selected)
        else if (ids.Length >= 1)
            this.ui.Update("CmbAiModel", "SelectedIndex", "0")
    }

    _ReadForm(&apiKey, &baseUrl, &model, &accessMode, &approvalMode, &providerId) {
        apiKey := Trim(this.ui.Query("TxtAiApiKey"))
        baseUrl := Trim(this.ui.Query("TxtAiBaseUrl"))
        model := Trim(this.ui.Query("CmbAiModel"))
        pIdx := this.ui.Query("CmbAiProvider>SelectedIndex")
        prov := AiAssist.ProviderByIndex(IsNumber(pIdx) ? Integer(pIdx) + 1 : AiAssist.Providers.Length)
        providerId := prov["id"]
        aIdx := this.ui.Query("CmbAiAccess>SelectedIndex")
        apIdx := this.ui.Query("CmbAiApproval>SelectedIndex")
        accessMode := IsNumber(aIdx) ? Integer(aIdx) + 1 : 2
        approvalMode := IsNumber(apIdx) ? Integer(apIdx) + 1 : 2
        if (accessMode < 1 || accessMode > 3)
            accessMode := 2
        if (approvalMode < 1 || approvalMode > 3)
            approvalMode := 2
    }

    _CollectModelListText(curModel) {
        list := []
        seen := Map()
        if (Trim(curModel) != "") {
            list.Push(curModel)
            seen[curModel] := true
        }
        for id in AiAssist.ModelListArr() {
            if (seen.Has(id))
                continue
            seen[id] := true
            list.Push(id)
        }
        out := ""
        for id in list
            out .= (out == "" ? "" : ",") id
        return out
    }

    OnProviderChanged(state, ctrl, event) {
        if (this._providerGuard || !IsObject(this.ui))
            return
        pIdx := this.ui.Query("CmbAiProvider>SelectedIndex")
        if (!IsNumber(pIdx))
            return
        prov := AiAssist.ProviderByIndex(Integer(pIdx) + 1)
        this._ApplyUrlEditable(this._IsUrlEditable(prov["id"]))
        if (prov["id"] = "custom" || Trim(prov["url"]) == "")
            this.ui.Update("TxtAiBaseUrl", "Text", Trim(prov["url"]))
        else
            this.ui.Update("TxtAiBaseUrl", "Text", prov["url"])
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this._revealed := true
        this.ui := ""
        this.closed := true
        if (AiSettingGui.instances.Has("main"))
            AiSettingGui.instances.Delete("main")
    }

    OnCloseClick(state, ctrl, event) {
        try this.ui.Update("Window", "Close", "")
    }

    OnRefreshClick(state, ctrl, event) {
        if (this._refreshing || !IsObject(this.ui))
            return
        apiKey := "", baseUrl := "", model := "", accessMode := 2, approvalMode := 2, providerId := "custom"
        this._ReadForm(&apiKey, &baseUrl, &model, &accessMode, &approvalMode, &providerId)
        if (apiKey == "" || baseUrl == "") {
            Toast.Warning(GetLang("请先填写 API Key 与 API URL"))
            return
        }
        this._refreshing := true
        try this.ui.Update("BtnRefreshModels", "IsEnabled", "False")
        try this.ui.Update("BtnRefreshModels", "Content", GetLang("刷新中…"))
        try {
            ids := AiAssist.FetchModels(baseUrl, apiKey)
            MainSoftData.AiModelList := ""
            for id in ids
                MainSoftData.AiModelList .= (MainSoftData.AiModelList == "" ? "" : ",") id
            keep := model
            if (keep == "" && ids.Length >= 1)
                keep := ids[1]
            this._FillModelCombo(ids, keep)
            Toast.Success(GetLang("已刷新模型列表"))
        } catch as e {
            Toast.Error(e.Message)
        } finally {
            this._refreshing := false
            try this.ui.Update("BtnRefreshModels", "IsEnabled", "True")
            try this.ui.Update("BtnRefreshModels", "Content", GetLang("刷新"))
        }
    }

    OnOkClick(state, ctrl, event) {
        apiKey := "", baseUrl := "", model := "", accessMode := 2, approvalMode := 2, providerId := "custom"
        this._ReadForm(&apiKey, &baseUrl, &model, &accessMode, &approvalMode, &providerId)
        if (apiKey == "" || baseUrl == "") {
            Toast.Warning(GetLang("请填写 API Key 与 API URL"))
            return
        }
        if (model == "") {
            Toast.Warning(GetLang("请选择或填写模型"))
            return
        }
        MainSoftData.AiProvider := providerId
        MainSoftData.AiApiKey := apiKey
        MainSoftData.AiApiBaseUrl := AiAssist.NormalizeBaseUrl(baseUrl)
        MainSoftData.AiModel := model
        MainSoftData.AiModelList := this._CollectModelListText(model)
        MainSoftData.AiAccessMode := accessMode
        MainSoftData.AiApprovalMode := approvalMode
        AiAssist.SaveToIni()
        Toast.Success(GetLang("AI 设置已保存"))
        try this.ui.Update("Window", "Close", "")
    }
}
