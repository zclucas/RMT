#Requires AutoHotkey v2.0

; =====================================================================
; YOLO 检测指令编辑器。
;
; 独立实现，不继承任何窗口类：开窗、模态、关闭这些窗口生命周期在本类里各写一份，
; 只与其它指令编辑器共用 CmdEditorForm 的行 / 控件工厂。
;
; 任务由模型决定，参数与输出也跟着任务走：所有行先建好，再按任务把用不上的行
; 收起来（Visibility），而不是给每个任务各写一套编辑器。这样保存时是一次
; 全字段读取，切换模型也不会丢已经填好的值。
; =====================================================================

class YoloGui {
    CmdKey := "YOLO检测"
    _pickAction := ""      ; 框选进行中的回调，用于 Esc 取消
    _task := ""            ; 当前模型的任务码
    _rows := Map()         ; 字段名 → 行控件（用于按任务显隐）
    _offsetVisible := false ; 点击偏移行当前是否展开（首帧落点要用）

    __new() {
        this.ParentTile := ""
        this.ui := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this._closed := true
        this._batch := []
        this._batching := false
        this.SerialStr := ""
        this.Data := ""
        this._title := ""
        ; 编辑器在宏编辑器和节点编辑器里各有一个实例，这几个容器必须一人一份。
        this._rows := Map()
        this._task := ""
        this._offsetVisible := false
        this._pickAction := ""
    }

    ; 打开编辑器。Init 里的多次控件更新先攒着，一次性批投递，避免几十次 IPC。
    ShowGui(cmd) {
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
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ; batching 中入队，_flushBatch 一次性 BatchUpdate（合并 Init 的多次 Update 为一次 IPC）
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

    ; 任务 → 需要显示的行。模型读不出来时用 Fallback，保证还能填常用的几项。
    static Layout := Map(
        "detect", ["ConfLevel", "Iou", "MaxDet", "Classes", "TargetMode", "ActionType", "CountVar"],
        "segment", ["ConfLevel", "Iou", "MaxDet", "MinMaskRatio", "Classes", "TargetMode",
            "ActionType", "CountVar"],
        "pose", ["ConfLevel", "Iou", "MaxDet", "KeypointConf", "AnchorKpt", "Classes",
            "TargetMode", "ActionType", "CountVar"],
        "obb", ["ConfLevel", "Iou", "MaxDet", "Classes", "TargetMode", "ActionType", "CountVar"],
        "classify", ["ConfLevel", "TopK", "ClassVar", "ConfVar"],
        "semantic", ["MinRatio", "Classes", "ActionType", "ClassVar", "RatioVar"],
        "depth", ["SamplePoint", "DepthVar"])

    static Fallback := ["ConfLevel", "Classes", "TargetMode", "ActionType", "CountVar",
        "ClassVar", "ConfVar", "RatioVar", "DepthVar", "TopK", "MinRatio", "SamplePoint"]

    ; 只有带坐标的任务才有“找到后点击”。
    static Clickable := ["detect", "segment", "pose", "obb", "semantic"]

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang(this.CmdKey)
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")
        this._Field(body, "备注：", "Remark")
        this._BuildFields(body)
        this._BuildResultFields(body)
        CmdEditorForm.Footer(body)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            'Title="' this._EscapeXml(title) '" Width="640" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("BtnPick", "Click", (*) => SetTimer(this._Pick.Bind(this, this.ui), -1))
        this.ui.OnEvent("BtnBrowse", "Click", XamlWin.BindCurrent(this, "OnBrowseModel"))
        this.ui.OnEvent("ModelName", "SelectionChanged", XamlWin.BindCurrent(this, "OnModelChanged"))
        this.ui.OnEvent("ActionType", "SelectionChanged", XamlWin.BindCurrent(this, "OnActionChanged"))
        BindCmdEditorChrome(this.ui, "#指令手册/" this.CmdKey)
        ; 插件文件缺失时先补齐再让用户填参数；延后一拍，让窗口先画出来再弹询问。
        SetTimer(ObjBindMethod(this, "_EnsurePluginFiles"), -50)
    }

    ; 只更新核心文件、手删过插件目录，都会落到这里：打开编辑器就查缺，
    ; 缺了直接给下载，而不是等执行时报「插件文件缺失」。
    _EnsurePluginFiles() {
        missing := Yolo.MissingFiles()
        if (!missing.Length)
            return
        list := ""
        for path in missing
            list .= "`n  · " path
        prompt := Format(GetLang("YOLO 插件缺少 {} 个文件：{}`n`n是否立即下载补齐？"), missing.Length, list)
        if (!RmtDialog.Confirm(prompt, GetLang(this.CmdKey), this.Hwnd()))
            return

        entries := []
        for path in missing {
            SplitPath(path, &name)
            entries.Push({fullPath: path, entry: name})
        }
        progress := RmtProgress(GetLang("下载 YOLO 插件"), GetLang("准备下载"),
            XamlWin.ActiveOwner(), GetLang("取消下载"))
        progress.Show()
        result := ""
        try {
            progress.Report("Yolo.zip")
            result := DownloadRmtAssetBundle(RmtAssetsBaseUrl(RmtAssetsReleaseTag()) "Yolo.zip", entries, progress)
        } finally progress.Close()

        if (result == "ok") {
            Yolo.ResetDll()
            Toast.Success(GetLang("YOLO 插件已就绪"))
        } else if (result != "cancel") {
            Toast.Error(GetLang("YOLO 插件下载失败，请稍后重试"))
        }
    }

    _Row(body, label, name, labelAlignment := "Center", labelGroup := "CommandLabel", labelTip := "") {
        return CmdEditorForm.Row(body, label, name "Row", labelGroup, labelAlignment, name "Label", labelTip)
    }

    _Field(body, label, name, height := 26) {
        return CmdEditorForm.TextBox(this._Row(body, label, name), name, height).Grid_Column(1)
    }

    ; 参数行：建好并登记，之后按任务决定显隐。
    _Param(body, label, name, tip := "") {
        row := this._Row(body, label, name, "Center", "CommandLabel", tip)
        CmdEditorForm.TextBox(row, name).Grid_Column(1)
        this._rows[name] := row
        return row
    }

    ; 下拉型参数：选项在 Init 里填充。
    _ChoiceParam(body, label, name, tip := "") {
        row := this._Row(body, label, name, "Center", "CommandLabel", tip)
        CmdEditorForm.Combo(row, name).Grid_Column(1)
        this._rows[name] := row
        return row
    }

    ; perTask 为真时登记到 _rows，由任务布局控制显隐；结果/错误变量与任务无关，始终显示。
    _Variable(body, label, name, perTask := true) {
        row := this._Row(body, label, name, "Center", "CommandLabel")
        CmdEditorForm.Combo(row, name, true).Grid_Column(1)
        if (perTask)
            this._rows[name] := row
        return row
    }

    _BuildFields(body) {
        model := this._Row(body, "模型：", "ModelName", , ,
            GetLang("从全局模型库选择；点右侧按钮可挑选新的 ONNX 文件并登记")).Add("Grid").Grid_Column(1)
        model.Cols("*", 6, "Auto")
        CmdEditorForm.Combo(model, "ModelName", true)
        CmdEditorForm.IconButton(model, "BtnBrowse", 0xE8E5, "选择 ONNX 模型文件").Grid_Column(2)

        ; 任务不是选项，是模型自带的：只做展示，让用户知道接下来会看到哪套参数。
        taskRow := this._Row(body, "任务：", "TaskInfo", "Center", "CommandLabel",
            GetLang("任务由模型元数据决定，参数和输出都跟着任务走"))
        taskRow.Add("TextBlock").Name("TaskInfo").Grid_Column(1)
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")

        deviceRow := this._Row(body, "设备：", "Device")
        CmdEditorForm.Combo(deviceRow, "Device").Grid_Column(1)

        this._Param(body, "置信度：", "ConfLevel", GetLang("0~1 之间，也可填百分数如 50。"))
        this._Param(body, "IoU：", "Iou", GetLang("NMS 的合并阈值，0~1。目标挤在一起时调小，重叠目标被误合并时调大。"))
        this._Param(body, "最大目标：", "MaxDet", GetLang("最多保留多少个目标，默认 300。"))
        this._Param(body, "类别过滤：", "Classes", GetLang("填类别名或序号，逗号分隔，例如 person,0；留空表示全部类别"))
        this._Param(body, "掩膜下限：", "MinMaskRatio", GetLang("掩膜面积占画面的比例下限，0~1；太小的碎块直接丢掉"))
        this._Param(body, "关键点阈值：", "KeypointConf", GetLang("关键点可信度下限，0~1；低于它的点不参与定位"))
        this._Param(body, "点击锚点：", "AnchorKpt", GetLang("用第几个关键点当点击位置，-1 表示用框中心（COCO：0 鼻子、5 左肩、6 右肩…）"))
        this._Param(body, "Top-K：", "TopK", GetLang("分类结果保留前多少个候选，1~20"))
        this._Param(body, "覆盖率下限：", "MinRatio", GetLang("类别像素占比下限，0~1；低于它的类别不输出"))
        this._BuildSampleRow(body)
        this._PickerField(body, "检测区域：", "Region", "框选检测区域，留空表示主屏全屏")
        this._ChoiceParam(body, "目标选择：", "TargetMode", GetLang("命中多个目标时取第一个的规则"))
        this._ChoiceParam(body, "找到后：", "ActionType")
        this._BuildOffsetRow(body)
    }

    ; 采样点是两个数，放一行；用不到的任务整行收起。
    _BuildSampleRow(body) {
        row := this._Row(body, "采样点：", "SamplePoint", "Center", "CommandLabel",
            GetLang("屏幕坐标 X,Y；留空表示整块区域的平均距离"))
        inner := row.Add("StackPanel").Orientation("Horizontal").Grid_Column(1)
        inner.Add("TextBlock").Text("X").Margin("0,0,4,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        CmdEditorForm.TextBox(inner, "SampleX").Width(70)
        inner.Add("TextBlock").Text("Y").Margin("14,0,4,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        CmdEditorForm.TextBox(inner, "SampleY").Width(70)
        this._rows["SamplePoint"] := row
    }

    _BuildOffsetRow(body) {
        row := this._Row(body, "点击偏移：", "OffsetX", "Center", "CommandLabel",
            GetLang("在目标中心点基础上偏移的像素数。"))
        inner := row.Add("StackPanel").Orientation("Horizontal").Grid_Column(1)
        inner.Add("TextBlock").Text("X").Margin("0,0,4,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        CmdEditorForm.TextBox(inner, "OffsetX").Width(70)
        inner.Add("TextBlock").Text("Y").Margin("14,0,4,0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        CmdEditorForm.TextBox(inner, "OffsetY").Width(70)
        ; 偏移行不参与任务映射，单独由动作类型控制显隐。
    }

    _BuildResultFields(body) {
        first := body.Add("Grid").Margin("0,8,0,0")
        first.Cols("*", 16, "*")
        left := first.Add("StackPanel").Grid_Column(0)
        this._Variable(left, "数量变量：", "CountVar")
        this._Variable(left, "类别变量：", "ClassVar")
        this._Variable(left, "置信度变量：", "ConfVar")
        this._Variable(left, "覆盖率变量：", "RatioVar")
        this._Variable(left, "距离变量：", "DepthVar")
        right := first.Add("StackPanel").Grid_Column(2)
        this._Variable(right, "结果变量：", "ResultVar", false)
        this._Variable(right, "错误信息变量：", "ErrorVar", false)
    }

    _PickerField(body, label, name, tip) {
        row := this._Row(body, label, name)
        inner := row.Add("Grid").Grid_Column(1)
        inner.Cols("*", 6, "Auto")
        CmdEditorForm.TextBox(inner, name)
        CmdEditorForm.IconButton(inner, "BtnPick", 0xECAF, tip).Grid_Column(2)
    }

    Init(cmd) {
        parts := cmd == "" ? [] : StrSplit(cmd, "_")
        this.SerialStr := parts.Length ? parts[1] : AllocateCommandSerial(this.CmdKey)
        this.Data := Yolo.Normalize(GetMacroCMDData(this.SerialStr))
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")

        this.RefreshModels(this.Data.ModelName)
        this._FillChoice("Device", Yolo.Devices, this.Data.Device)
        this._FillChoice("TargetMode", Yolo.Targets, this.Data.TargetMode)
        this._FillChoice("ActionType", Yolo.Actions, this.Data.ActionType)

        for field in ["ConfLevel", "Iou", "MaxDet", "Classes", "MinMaskRatio", "KeypointConf",
            "AnchorKpt", "TopK", "MinRatio", "SampleX", "SampleY", "Region", "OffsetX", "OffsetY"]
            this._ComboPush(field, "Text", String(this.Data.%field%))

        varFields := ["CountVar", "ClassVar", "ConfVar", "RatioVar", "DepthVar", "ResultVar", "ErrorVar"]
        for varName in GetGuiVarArr() {
            for field in varFields
                this._ComboPush(field, "AddItem", varName)
        }
        for field in varFields
            this._ComboPush(field, "Text", String(this.Data.%field%))

        this._ApplyTask(Yolo.TaskOf(this.Data.ModelName),
            CmdEnumZh(this.Data.ActionType, Yolo.Actions), this.Data.ModelName)
        ; 首帧就按任务收好行，落点交给模板里的 CenterScreen 一次算准。
        this._HideRowsInXaml()
    }

    _FillChoice(name, names, current) {
        this._ComboPush(name, "ClearItems", "")
        for item in names
            this._ComboPush(name, "AddItem", GetLang(item))
        selected := CmdEnumZh(current, names)
        this._ComboPush(name, "Text", GetLang(selected))
    }

    ; 把界面上显示的译文还原成中文键，再落盘。
    _EnumValue(text, names) {
        for name in names {
            if (GetLang(name) == text || name == text)
                return name
        }
        return names[1]
    }

    ; ---------- 按任务显隐 ----------

    _ApplyTask(task, action, modelName := "") {
        this._task := task
        layout := YoloGui.Layout.Has(task) ? YoloGui.Layout[task] : YoloGui.Fallback
        for name, _ in this._rows {
            this._ComboPush(name "Row", "Visibility",
                this._Has(layout, name) ? "Visible" : "Collapsed")
        }
        this._ComboPush("TaskInfo", "Text", this._TaskText(task, modelName))
        this._UpdateAction(action)
    }

    _TaskText(task, modelName) {
        if (task == "") {
            if (Trim(modelName) == "")
                return GetLang("请选择模型。")
            return GetLang("未知：读不到模型信息，已按通用参数显示")
        }
        name := Yolo.Tasks.Has(task) ? GetLang(Yolo.Tasks[task]) : task
        return name "　" GetLang("（由模型决定，参数与输出随之变化）")
    }

    _UpdateAction(action) {
        clickable := this._task == "" || this._Has(YoloGui.Clickable, this._task)
        this._offsetVisible := clickable && action != "无动作"
        this._ComboPush("OffsetXRow", "Visibility", this._offsetVisible ? "Visible" : "Collapsed")
    }

    _Has(list, value) {
        for item in list
            if (item == value)
                return true
        return false
    }

    ; ---------- 首帧显隐：让开窗高度一次就是最终高度 ----------
    ; SizeToContent 窗口靠模板里的 CenterScreen 居中，而 WPF 只在首次 Show 时按当时的
    ; 尺寸算一次，之后尺寸变了不再重新定位。本编辑器是唯一「开窗后还要收行」的指令窗口：
    ; 行收起走 Init 的批次更新，要等 LoadedHwnd 才发到引擎，于是首帧按「全部行展开」
    ; 的高度居中，收完行窗变矮而 Top 不动，看着就不在屏幕中间（差 行数差×34/2）。
    ; 这里把用不上的行在 Show 之前直接写进 XAML，首帧高度即最终高度，其余与别的编辑器一致。
    _HideRowsInXaml() {
        if (!IsObject(this.ui))
            return
        layout := YoloGui.Layout.Has(this._task) ? YoloGui.Layout[this._task] : YoloGui.Fallback
        for name, _ in this._rows {
            if (this._Has(layout, name))
                continue
            this.ui.xaml := StrReplace(this.ui.xaml, 'Name="' name 'Row"',
                'Name="' name 'Row" Visibility="Collapsed"')
        }
        ; 偏移行不在任务映射里，单独按动作类型决定。
        if (!this._offsetVisible)
            this.ui.xaml := StrReplace(this.ui.xaml, 'Name="OffsetXRow"',
                'Name="OffsetXRow" Visibility="Collapsed"')
    }

    _ReadData() {
        fields := ["Remark", "ModelName", "Device", "ConfLevel", "Iou", "MaxDet", "Classes",
            "MinMaskRatio", "KeypointConf", "AnchorKpt", "TopK", "MinRatio", "SampleX", "SampleY",
            "Region", "TargetMode", "ActionType", "OffsetX", "OffsetY",
            "CountVar", "ClassVar", "ConfVar", "RatioVar", "DepthVar", "ResultVar", "ErrorVar"]
        state := this.ui.Query(fields*)

        data := this.Data.Clone()
        data.ModelName := Trim(state["ModelName"])
        data.Device := this._EnumValue(state["Device"], Yolo.Devices)
        data.TargetMode := this._EnumValue(state["TargetMode"], Yolo.Targets)
        data.ActionType := this._EnumValue(state["ActionType"], Yolo.Actions)
        for field in ["ConfLevel", "Iou", "MaxDet", "Classes", "MinMaskRatio", "KeypointConf",
            "AnchorKpt", "TopK", "MinRatio", "SampleX", "SampleY", "Region", "OffsetX", "OffsetY"]
            data.%field% := Trim(state[field])
        for field in ["CountVar", "ClassVar", "ConfVar", "RatioVar", "DepthVar", "ResultVar", "ErrorVar"]
            data.%field% := GetVarName(Trim(state[field]))
        return data
    }

    CheckIfValid() {
        try {
            data := this._ReadData()
            if (data.ModelName == "")
                throw Error(GetLang("请选择模型。"))
            if (YoloModelStore.ResolvePath(data.ModelName) == "")
                throw Error(Format(GetLang("模型「{}」不在模型库中，请重新选择。"), data.ModelName))

            task := Yolo.TaskOf(data.ModelName)
            region := Yolo.ParseRegion(data.Region)
            ; 参数校验直接复用运行时那一套，避免编辑器放行、执行时才报错。
            Yolo.BuildOptions(task == "" ? "detect" : task, data, (text) => text, region)

            if (task == "" || this._Has(YoloGui.Clickable, task)) {
                for field in ["OffsetX", "OffsetY"] {
                    value := Trim(data.%field%)
                    if (value != "" && !IsInteger(value))
                        throw Error(GetLang("偏移量须为整数。"))
                }
            }
            if (!this._HasOutput(data))
                throw Error(GetLang("请至少填写一个结果变量。"))
        } catch as e {
            RmtDialog.Info(e.Message, GetLang(this.CmdKey), this.Hwnd())
            return false
        }
        for name in [data.CountVar, data.ClassVar, data.ConfVar, data.RatioVar, data.DepthVar,
            data.ResultVar, data.ErrorVar]
            if (name != "" && !CheckVarNameIfValid(name))
                return false
        return true
    }

    _HasOutput(data) {
        for field in ["CountVar", "ClassVar", "ConfVar", "RatioVar", "DepthVar", "ResultVar", "ErrorVar"]
            if (data.%field% != "")
                return true
        return false
    }

    SaveData() {
        this.Data := this._ReadData()
        RegisterYoloVars(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang(this.CmdKey) RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }

    OnModelChanged(*) {
        name := this.ui.Query("ModelName")
        this._ApplyTask(Yolo.TaskOf(name),
            this._EnumValue(this.ui.Query("ActionType"), Yolo.Actions), name)
    }

    OnActionChanged(*) {
        this._UpdateAction(this._EnumValue(this.ui.Query("ActionType"), Yolo.Actions))
    }

    OnBrowseModel(*) {
        selected := FileSelect(3, ProjectRootDir "\Plugins\YOLO\models", GetLang("选择 ONNX 模型"), "ONNX (*.onnx)")
        if (selected == "")
            return
        SplitPath(selected, , , , &nameNoExt)
        if (nameNoExt == "") {
            RmtDialog.Info(GetLang("模型文件名无效。"), GetLang(this.CmdKey), this.Hwnd())
            return
        }
        YoloModelStore.Set(nameNoExt, selected)
        this.RefreshModels(nameNoExt)
        this._ComboPush("ModelName", "Text", nameNoExt)
        this._ApplyTask(Yolo.TaskOf(nameNoExt),
            this._EnumValue(this.ui.Query("ActionType"), Yolo.Actions), nameNoExt)
    }

    RefreshModels(selected) {
        this._ComboPush("ModelName", "ClearItems", "")
        for name in YoloModelStore.List()
            this._ComboPush("ModelName", "AddItem", name)
        this._ComboPush("ModelName", "Text", String(selected))
    }

    _Pick(ui) {
        if (this.ui != ui || this._pickAction != "" || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        while (GetKeyState("LButton", "P") && this.ui == ui)
            Sleep(15)
        if (this.ui != ui || MainSoftData.SelectAreaAction != "" || MainSoftData.GetAreaAction != "")
            return
        result := []
        action := (x1, y1, x2, y2) => result.Push(x1, y1, x2, y2)
        this._pickAction := action
        keys := WinHotkey.Register(["Escape"], this._CancelPick.Bind(this))
        title := "ahk_id " this.Hwnd()
        failure := ""
        try {
            WinHide(title)
            TogSelectArea(true, action)
            if (this.ui == ui && result.Length)
                this._ApplyPick(ui, result)
        } catch as e {
            failure := e.Message
        } finally {
            WinHotkey.UnregisterAll(keys)
            this._pickAction := ""
            if (this.ui == ui) {
                wasDetectingHidden := A_DetectHiddenWindows
                DetectHiddenWindows(true)
                try WinShow(title)
                finally DetectHiddenWindows(wasDetectingHidden)
                try WinActivate(title)
            }
        }
        if (this.ui == ui && failure != "")
            RmtDialog.Info(failure, GetLang(this.CmdKey), this.Hwnd())
    }

    _ApplyPick(ui, coords) {
        if (coords[1] != coords[3] && coords[2] != coords[4])
            ui.Update("Region", "Text", Format("{1},{2},{3},{4}", coords*))
    }

    _CancelPick(*) {
        if (this._pickAction != "" && MainSoftData.SelectAreaAction == this._pickAction)
            TogSelectArea(false)
    }

    ; ---------- 窗口生命周期 ----------

    OnClickSureBtn(state, ctrl, event) {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this._CloseWindow()
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this._CancelPick()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
    }

    _CloseWindow() {
        this._CancelPick()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }
}
