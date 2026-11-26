#Requires AutoHotkey v2.0

; =====================================================================
; 翻译指令编辑器。
;
; 独立实现，不继承任何窗口类：开窗、模态、关闭这些窗口生命周期在本类里各写一份，
; 只与其它指令编辑器共用 CmdEditorForm 的行 / 控件工厂。
;
; 标题栏执行钮 / Alt+L 试译：按当前界面配置跑一次翻译，译文与耗时弹独立窗口。
; 来源为变量时没有宏上下文可解析，编辑器里不试译。
; 设备（自动 / GPU / CPU）只对本地引擎有效，切换后下一次翻译会重新 Load 模型。
; =====================================================================

class TranslateGui {
    static TextFields := ["Text", "ResultVar", "ErrorVar", "TargetCustom"]
    static Choices := Map(
        "Source", TranslateCommand.Sources,
        "Target", TranslateCommand.Targets,
        "Engine", TranslateCommand.Engines,
        "Device", TranslateCommand.Devices)

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
        this._glossary := []   ; 结构化术语和未迁移旧条目
        this._legacyGlossary := ""
        this._legacyGlossaryLines := []
        this._glossSeq := 0
        this._glossBound := Map()  ; 已登记过 Click 回调的标签按钮 id（OnEvent 是 Push 会叠）
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
        if (!this._closed)
            this.ToggleFunc(true)
        ; 延迟查缺组件与模型：建窗消息里不能弹对话框，SetTimer(-50) 等窗口稳了再问
        SetTimer(ObjBindMethod(this, "_EnsureReady"), -50)
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

    _BuildAndShow() {
        this._closed := false
        title := this.ParentTile GetLang("翻译编辑器")
        this._title := title
        height := XAMLHost.CmdTitleBarHeight()
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(height, "Auto")
        XAMLHost.AddCmdTitleBar(main, title, height)
        body := main.Add("StackPanel").Grid_Row(1).Margin("16,8,16,12").Grid_IsSharedSizeScope("True")

        this._Field(body, "备注：", "Remark")
        head := body.Add("Grid").Margin("0,4").Cols("*", 16, "*")
        this._Choice(this._Row(head, "来源：", "Source"), "Source", TranslateGui.Choices["Source"])
        this._Choice(this._Row(head, "目标语言：", "Target").Grid_Column(2), "Target", TranslateGui.Choices["Target"])

        ; 目标语言选「自定义」时展开，填任意语言名（模型支持 150 种语言）
        tcRow := this._Row(body, "自定义语言：", "TargetCustom", GetLang("填语言名称，模型支持 150 种语言。"))
        tcRow.Visibility("Collapsed")
        this._TextBox(tcRow, "TargetCustom").Grid_Column(1)

        this._Choice(this._Row(body, "模型：", "Engine", GetLang("本地模型在进程内推理，不联网。")), "Engine", TranslateGui.Choices["Engine"])

        device := this._Row(body, "设备：", "Device", GetLang("只对本地模型有效：自动/GPU 走显卡，CPU 不占显存。切换后首次翻译会重新加载模型。"))
        this._Choice(device, "Device", TranslateGui.Choices["Device"])

        ; 内容随来源切换：变量=选变量下拉，固定文本=填文本框，剪切板=两行都藏
        this._Field(body, "内容：", "Text", GetLang("来源选「固定文本」时填原文。"), 64)
        tvRow := this._Row(body, "内容：", "TextVar", GetLang("来源选「变量」时取该变量的值。"))
        tvRow.Visibility("Collapsed")
        tvRow.Add("ComboBox").Name("TextVar").Height(28).MinHeight(28).IsEditable("True").Padding("5,0,21,0")
            .Grid_Column(1)
        ; 术语表：存量渲染成标签流（WrapPanel，标签尾部带 ✕ 删除），增删用
        ; AddXamlItem 整片重建；添加区固定在标签流最下面，一框原文一框译文点 + 添加，
        ; 用户不用考虑 原文:译文 格式。
        glRow := this._Row(body, "术语表：", "Glossary", GetLang("固定译法对照。下方一框原文一框译文，点 + 添加；标签尾部 ✕ 删除。"))
        glStack := glRow.Add("StackPanel").Grid_Column(1)
        glStack.Add("WrapPanel").Name("GlossaryTags").Margin("0,0,0,4")
        glAdd := glStack.Add("Grid").Margin("0,2,0,0").Cols("*", 8, "*", "Auto")
        this._TextBox(glAdd, "GlossarySrc").Grid_Column(0)
        this._TextBox(glAdd, "GlossaryDst").Grid_Column(2)
        CmdEditorForm.IconButton(glAdd, "BtnGlossAdd", 0xE710, "添加术语对照").Grid_Column(3)

        results := body.Add("Grid").Margin("0,4").Cols("*", 16, "*")
        this._Variable(results, "结果变量：", "ResultVar", 0, GetLang("译文写入该变量。"))
        this._Variable(results, "错误变量：", "ErrorVar", 2, GetLang("友好错误会提示并继续；技术错误仍会中断。填入后也会把错误信息写入该变量。"))

        CmdEditorForm.Footer(body)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", height)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="620" SizeToContent="Height"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.OnEvent("Window", "Closing", XamlWin.BindCurrent(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", XamlWin.BindCurrent(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", XamlWin.BindCurrent(this, "OnClickSureBtn"))
        this.ui.OnEvent("Engine", "SelectionChanged", XamlWin.BindCurrent(this, "OnEngineChanged"))
        this.ui.OnEvent("Target", "SelectionChanged", XamlWin.BindCurrent(this, "OnTargetChanged"))
        this.ui.OnEvent("Source", "SelectionChanged", XamlWin.BindCurrent(this, "OnSourceChanged"))
        this.ui.OnEvent("BtnGlossAdd", "Click", XamlWin.BindCurrent(this, "OnGlossAdd"))
        BindCmdEditorChrome(this.ui, "#指令手册/翻译", ObjBindMethod(this, "RunTest"))
    }

    _Row(body, label, name := "", tip := "") {
        rowName := name != "" ? name "Row" : ""
        labelName := name != "" ? name "Label" : ""
        return CmdEditorForm.Row(body, label, rowName, "CommandLabel", "Center", labelName, tip)
    }

    _Field(body, label, name, tip := "", height := 28) {
        row := this._Row(body, label, name, tip)
        return this._TextBox(row, name, height).Grid_Column(1)
    }

    _TextBox(parent, name, height := 28) {
        box := parent.Add("TextBox").Name(name).Height(height).MinHeight(height)
            .Padding("2,2").Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        if (height > 30) {
            box.AcceptsReturn("True").TextWrapping("Wrap").VerticalContentAlignment("Top")
                .ScrollViewer_VerticalScrollBarVisibility("Auto")
                .Style("{StaticResource RmtMultiLineTextBox}")
        } else {
            box.VerticalContentAlignment("Center").Style("{StaticResource RmtSingleLineTextBox}")
        }
        return box
    }

    _Choice(parent, name, values) {
        box := parent.Add("ComboBox").Name(name).Height(28).MinHeight(28).Padding("7,0,23,0").SelectedIndex(0)
        for value in values
            box.Add("ComboBoxItem").Content(GetLang(value)).Tag(value)
        return box.Grid_Column(1)
    }

    _Variable(grid, label, name, column := 0, tip := "") {
        row := this._Row(grid, label, name, tip).Grid_Column(column)
        combo := row.Add("ComboBox").Name(name).Height(28).MinHeight(28).IsEditable("True").Padding("5,0,21,0")
        return combo.Grid_Column(1)
    }

    Init(cmd) {
        parts := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := parts.Length ? parts[1] : AllocateCommandSerial("翻译")
        this.Data := GetMacroCMDData(this.SerialStr)
        this._ComboPush("Remark", "Text", parts.Length >= 2 ? parts[2] : "")

        for varName in GetGuiVarArr() {
            if (varName == "")
                continue
            for name in ["ResultVar", "ErrorVar", "TextVar"]
                this._ComboPush(name, "AddItem", varName)
        }
        for name in TranslateGui.TextFields
            this._ComboPush(name, "Text", String(this.Data.HasOwnProp(name) ? this.Data.%name% : ""))
        ; 旧格式原文保留到用户明确删除；新条目从结构化字段读取。
        this._glossary := []
        this._glossSeq := 0
        this._glossBound := Map()
        this._legacyGlossary := String(this.Data.HasOwnProp("Glossary") ? this.Data.Glossary : "")
        this._legacyGlossaryLines := []
        if (this._legacyGlossary != "") {
            for line in StrSplit(this._legacyGlossary, "`n") {
                line := RTrim(line, "`r")
                if (line == "")
                    continue
                this._legacyGlossaryLines.Push(line)
                this._glossSeq++
                this._glossary.Push({id: this._glossSeq, legacy: true, legacyIndex: this._legacyGlossaryLines.Length, text: line})
            }
        }
        if (this.Data.HasOwnProp("GlossaryItems") && this.Data.GlossaryItems is Array) {
            for item in this.Data.GlossaryItems {
                if (!IsObject(item) || !item.HasOwnProp("source") || !item.HasOwnProp("target"))
                    continue
                this._glossSeq++
                this._glossary.Push({id: this._glossSeq, legacy: false, source: String(item.source), target: String(item.target)})
            }
        }
        for name, values in TranslateGui.Choices {
            value := CmdEnumZh(this.Data.%name%, values)
            this._ComboPush(name, "SelectedIndex", CmdEnumIndex(value, values))
        }
        ; Init 阶段批量更新尚未提交，Query 取不到刚设的下拉值，按存储值直接算初始显隐
        source := CmdEnumZh(this.Data.Source, TranslateCommand.Sources)
        this._ComboPush("TargetCustomRow", "Visibility",
            CmdEnumZh(this.Data.Target, TranslateCommand.Targets) == "自定义" ? "Visible" : "Collapsed")
        this._ComboPush("TextRow", "Visibility", source == "固定文本" ? "Visible" : "Collapsed")
        this._ComboPush("TextVarRow", "Visibility", source == "变量" ? "Visible" : "Collapsed")
    }

    _ReadData() {
        data := TranslateData()
        data.SerialStr := this.Data.SerialStr
        for name in TranslateGui.TextFields
            data.%name% := this.ui.Query(name)
        for name in ["Source", "Target", "Engine", "Device"]
            data.%name% := TranslateGui._ChoiceValue(this.ui.Query(name), TranslateGui.Choices[name])
        ; 来源=变量 时内容取变量下拉；剪切板 时内容无用，清空避免残留旧值
        if (data.Source == "变量")
            data.Text := Trim(this.ui.Query("TextVar"))
        else if (data.Source == "剪切板")
            data.Text := ""
        data.Glossary := this._legacyGlossary
        data.GlossaryItems := []
        for item in this._glossary
            if (!item.legacy)
                data.GlossaryItems.Push({source: item.source, target: item.target})
        data.ResultVar := GetVarName(Trim(data.ResultVar))
        data.ErrorVar := GetVarName(Trim(data.ErrorVar))
        return data
    }

    static _ChoiceValue(text, values) {
        for value in values
            if (GetLang(value) == text)
                return value
        return values[1]
    }

    CheckIfValid() {
        data := this._ReadData()
        if (data.Target == "自定义" && Trim(data.TargetCustom) == "") {
            RmtDialog.Info(GetLang("自定义目标语言不能为空"), GetLang("翻译"), this.Hwnd())
            return false
        }
        if (data.ResultVar != "" && data.ResultVar = data.ErrorVar) {
            RmtDialog.Info(GetLang("结果变量和错误变量不能相同。"), GetLang("翻译"), this.Hwnd())
            return false
        }
        for name in [data.ResultVar, data.ErrorVar]
            if (name != "" && !CheckVarNameIfValid(name))
                return false
        return true
    }

    SaveData() {
        this.Data := this._ReadData()
        RegisterTranslateVars(this.Data)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        return CorrectRemark(GetLang("翻译") RegExReplace(this.Data.SerialStr, "\D+"), this.ui.Query("Remark"))
    }

    ; ---------- 执行：按当前配置试译一次 ----------

    ; 标题栏执行钮 / Alt+L 同一动作。本地引擎同步推理约一秒，AI 通道走一次同步请求。
    RunTest() {
        if (!IsObject(this.ui) || this._closed)
            return
        if (!this.CheckIfValid())
            return
        data := this._ReadData()
        switch data.Source {
            case "剪切板": text := A_Clipboard
            case "固定文本": text := Trim(data.Text)
            default:
                RmtDialog.Info(GetLang("来源为变量时无法试译，请改用固定文本或剪切板。"), GetLang("翻译"), this.Hwnd())
                return
        }
        text := Trim(text)
        if (text == "") {
            RmtDialog.Info(GetLang("翻译内容为空"), GetLang("翻译"), this.Hwnd())
            return
        }
        timedOut := false
        elapsedMs := 0
        try {
            target := TranslateCommand.ResolveTarget(data)
            promptTarget := TranslateCommand.TargetPrompt.Has(target) ? TranslateCommand.TargetPrompt[target] : target
            if (TranslateCommand.IsLocal(data.Engine))
                result := TranslateCommand.ExecuteLocal(text, promptTarget, data.Glossary, data.GlossaryItems, data, () => false, &timedOut, &elapsedMs)
            else
                result := TranslateCommand.ExecuteRemote(text, promptTarget, data.Glossary, data.GlossaryItems, data, () => false, &timedOut, &elapsedMs)
        } catch as e {
            message := e.Message
            if (SubStr(message, 1, StrLen(TranslateCommand.MissingModelPrefix)) == TranslateCommand.MissingModelPrefix) {
                modelName := SubStr(message, StrLen(TranslateCommand.MissingModelPrefix) + 1)
                TranslateGui._PromptModelDownload(modelName)
                return
            }
            if (SubStr(message, 1, StrLen(TranslateCommand.FriendlyErrorPrefix)) == TranslateCommand.FriendlyErrorPrefix)
                message := SubStr(message, StrLen(TranslateCommand.FriendlyErrorPrefix) + 1)
            RmtDialog.Info(message, GetLang("翻译"), this.Hwnd())
            return
        }
        ; 结果独立弹窗：耗时一行 + 译文（长文本走 RmtDialog 的只读框，可复制）
        hint := timedOut ? GetLang("结果可能不完整") "`n`n" : ""
        RmtDialog.Info(Format(GetLang("试译耗时 {} 毫秒"), elapsedMs) "`n`n" hint result, GetLang("试译结果"), this.Hwnd())
    }

    ; Alt+L 与标题栏执行钮同一动作；关窗必须摘掉，否则编辑器关了热键还在。
    ; 重开时必须显式传 "On"：Hotkey(k, "Off") 只留禁用变体，不传 "On" 会挂在禁用变体上。
    ToggleFunc(state) {
        if (state)
            Hotkey("!l", XamlWin.BindCurrent(this, "RunTest"), "On")
        else
            try Hotkey("!l", "Off")
    }

    ; 目标语言切到/切离「自定义」时显隐自定义语言行
    OnTargetChanged(state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        value := TranslateGui._ChoiceValue(this.ui.Query("Target"), TranslateGui.Choices["Target"])
        this.ui.Update("TargetCustomRow", "Visibility", value == "自定义" ? "Visible" : "Collapsed")
    }

    ; 来源切换时显隐对应的内容行：变量=下拉，固定文本=文本框，剪切板=都藏
    OnSourceChanged(state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        source := TranslateGui._ChoiceValue(this.ui.Query("Source"), TranslateGui.Choices["Source"])
        this.ui.BatchUpdate([
            {ControlName: "TextRow", PropertyName: "Visibility", Value: source == "固定文本" ? "Visible" : "Collapsed"},
            {ControlName: "TextVarRow", PropertyName: "Visibility", Value: source == "变量" ? "Visible" : "Collapsed"}
        ])
    }

    ; ---------- 术语表标签流（非标准控件：AddXamlItem 动态标签，尾部 ✕ 删除） ----------
    ;
    ; WrapPanel 不支持按条删除（RemoveItem 只认 ItemsControl），所以增删一律
    ; ClearItems + 逐条 AddXamlItem 整片重建；重建后的按钮是新实例，必须
    ; BindEventBatched 重新挂一次（引擎按实例去重）。回调登记走 host.OnEvent，
    ; 它是 Push 会叠回调——每个 id 只登记一次（_glossBound 去重），id 不复用。

    _GlossChipXaml(id, text) {
        esc := this._EscapeXml(text)
        return '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
            . ' Tag="' esc '" CornerRadius="6" Background="{DynamicResource InputBg}"'
            . ' BorderBrush="{DynamicResource InputStroke}" BorderThickness="1" Margin="0,2,6,2" Padding="8,2">'
            . '<StackPanel Orientation="Horizontal">'
            . '<TextBlock Text="' esc '" Foreground="{DynamicResource InputText}" VerticalAlignment="Center" Margin="0,0,4,0"/>'
            . '<Button Name="BtnGlossDel_' id '" Content="✕" FontSize="10" Padding="3,1" Margin="0,-2,-3,0"'
            . ' Background="Transparent" BorderThickness="0" Foreground="{DynamicResource InputText}"'
            . ' VerticalAlignment="Center" Cursor="Hand"/>'
            . '</StackPanel></Border>'
    }

    _RebuildGlossaryChips() {
        if (!IsObject(this.ui))
            return
        updates := [{ControlName: "GlossaryTags", PropertyName: "ClearItems", Value: ""}]
        for item in this._glossary {
            text := item.legacy ? item.text : item.source " → " item.target
            updates.Push({ControlName: "GlossaryTags", PropertyName: "AddXamlItem", Value: this._GlossChipXaml(item.id, text)})
        }
        this.ui.BatchUpdate(updates)
        for item in this._glossary {
            if (!this._glossBound.Has(item.id)) {
                this._glossBound[item.id] := true
                this.ui.OnEvent("BtnGlossDel_" item.id, "Click", this._GlossDelHandler(item.id))
            }
            ; 重建后是新实例，强制引擎重挂一次（OnEvent 已登记过回调，不再 Push）
            this.ui.BindEventBatched("BtnGlossDel_" item.id, "Click")
        }
    }

    ; 每个条目一个独立闭包，id 是本次调用的局部量，不受后续循环影响
    _GlossDelHandler(id) {
        return (state, ctrl, event) => this.OnGlossDelId(id)
    }

    OnGlossAdd(state, ctrl, event) {
        if (!IsObject(this.ui))
            return
        src := this.ui.Query("GlossarySrc")
        dst := this.ui.Query("GlossaryDst")
        if (Trim(src) == "" || Trim(dst) == "") {
            RmtDialog.Info(GetLang("原文和译文都要填，才能添加一条术语对照。"), GetLang("翻译"), this.Hwnd())
            return
        }
        for item in this._glossary {
            if (!item.legacy && item.source == src && item.target == dst) {
                RmtDialog.Info(GetLang("这条术语对照已经在列表里。"), GetLang("翻译"), this.Hwnd())
                return
            }
            if (!item.legacy && item.source == src) {
                RmtDialog.Info(GetLang("原文已存在，请先删除旧术语对照。"), GetLang("翻译"), this.Hwnd())
                return
            }
        }
        this._glossSeq++
        this._glossary.Push({id: this._glossSeq, legacy: false, source: src, target: dst})
        this._RebuildGlossaryChips()
        this.ui.BatchUpdate([
            {ControlName: "GlossarySrc", PropertyName: "Text", Value: ""},
            {ControlName: "GlossaryDst", PropertyName: "Text", Value: ""}
        ])
    }

    OnGlossDelId(id) {
        if (!IsObject(this.ui))
            return
        for idx, item in this._glossary {
            if (item.id == id) {
                if (item.legacy) {
                    this._legacyGlossaryLines.RemoveAt(item.legacyIndex)
                    this._legacyGlossary := ""
                    for lineIndex, line in this._legacyGlossaryLines
                        this._legacyGlossary .= (lineIndex == 1 ? "" : "`n") line
                    for other in this._glossary
                        if (other.legacy && other.legacyIndex > item.legacyIndex)
                            other.legacyIndex -= 1
                }
                this._glossary.RemoveAt(idx)
                break
            }
        }
        this._RebuildGlossaryChips()
    }

    ; ---------- 组件与模型按需下载 ----------

    ; Translate.zip 覆盖的全部运行库文件；与 SelfCheck.ahk 的翻译 optionalFiles
    ; 同一份清单，增删要两处同步。模型 GGUF 不在包里，走下面的模型下载。
    static MissingRuntimeFiles() {
        if (A_PtrSize == 4)
            return []
        dir := A_WorkingDir "\Plugins\Translate\x64\"
        files := ["TranslateDll.dll", "llama.dll", "ggml.dll", "ggml-base.dll", "ggml-vulkan.dll"
            , "ggml-cpu-x64.dll", "ggml-cpu-sse42.dll", "ggml-cpu-sandybridge.dll", "ggml-cpu-haswell.dll"
            , "ggml-cpu-skylakex.dll", "ggml-cpu-cannonlake.dll", "ggml-cpu-cascadelake.dll"
            , "ggml-cpu-icelake.dll", "ggml-cpu-alderlake.dll"]
        missing := []
        for file in files
            if (RmtAssetMissing(dir file))
                missing.Push({fullPath: dir file, entry: file})
        return missing
    }

    ; 默认模型使用 GitCode LFS，备用地址直连 GitHub 原文件。
    static _ModelUrls(modelName) {
        if (modelName == TranslateEngine.DefaultModel) {
            primary := RmtLargeAssetUrl(modelName)
            return [primary, RmtDownloadDirectUrl(primary)]
        }
        repo := InStr(modelName, "-9B") ? "IndexTeam/Index-Translate-9B-GGUF" : "IndexTeam/Index-Translate-2B-GGUF"
        return ["https://modelscope.cn/models/" repo "/resolve/master/" modelName,
                "https://huggingface.co/" repo "/resolve/main/" modelName]
    }

    ; 模型下载由通用下载管理器执行；翻译模块只提供来源、目标和完成提示。
    static BeginModelDownload(modelName) {
        if (TranslateEngine.HasModel(modelName))
            return
        savePath := A_WorkingDir "\Plugins\Translate\models\" modelName
        minBytes := InStr(modelName, "-9B") ? 5000 * 1024 * 1024 : 1200 * 1024 * 1024
        try {
            RmtDownloadManager.Enqueue(Format(GetLang("翻译模型：{}"), modelName),
                TranslateGui._ModelUrls(modelName), savePath, minBytes, 7200,
                (job) => TranslateGui._OnModelDownloadComplete(job))
            Toast.Info(GetLang("已加入后台下载，可在设置中查看进度。"))
        } catch as error {
            RMTErrorShow("翻译模型下载任务创建失败：" error.Message, RMT_LV_ERROR, "TranslateGui")
            Toast.Error(GetLang("翻译模型下载失败，请在下载管理中重试。"))
        }
    }

    static _OnModelDownloadComplete(job) {
        if (job.status == "completed")
            Toast.Success(GetLang("翻译模型已就绪"))
        else if (job.status == "failed")
            Toast.Error(GetLang("翻译模型下载失败，请在下载管理中重试。"))
    }

    static _PromptModelDownload(modelName) {
        if (TranslateEngine.HasModel(modelName))
            return
        sizeHint := InStr(modelName, "-9B") ? "5.9 GB" : "1.3 GB"
        prompt := Format(GetLang("本地翻译模型未下载（{}，约 {}），是否加入后台下载？"), modelName, sizeHint)
        if (RmtDialog.Confirm(prompt, GetLang("翻译")))
            TranslateGui.BeginModelDownload(modelName)
    }

    static RequestInternalDownload(assetId) {
        prefix := "translate-model:"
        if (SubStr(assetId, 1, StrLen(prefix)) != prefix)
            return
        modelName := SubStr(assetId, StrLen(prefix) + 1)
        validModel := false
        for _, name in TranslateCommand.EngineModels
            if (name == modelName) {
                validModel := true
                break
            }
        if (!validModel)
            return
        SetTimer((*) => TranslateGui._PromptModelDownload(modelName), -10)
    }

    static _DownloadRuntimeFiles() {
        missing := TranslateGui.MissingRuntimeFiles()
        if (!missing.Length)
            return
        target := RmtCacheDir() "\Downloads\" RmtAssetsReleaseTag() "\Translate.zip"
        url := RmtAssetsBaseUrl(RmtAssetsReleaseTag()) "Translate.zip"
        try {
            RmtDownloadManager.Enqueue(GetLang("翻译组件"), [url], target, 10 * 1024 * 1024, 120,
                (job) => TranslateGui._OnRuntimeDownloadComplete(job, missing))
            Toast.Info(GetLang("翻译组件已加入后台下载，可在设置中查看进度。"))
        } catch as error {
            RMTErrorShow("翻译组件下载任务创建失败：" error.Message, RMT_LV_ERROR, "TranslateGui")
            Toast.Error(GetLang("翻译组件下载失败，请在下载管理中重试。"))
        }
    }

    static _OnRuntimeDownloadComplete(job, files) {
        if (job.status != "completed") {
            if (job.status == "failed")
                Toast.Error(GetLang("翻译组件下载失败，请在下载管理中重试。"))
            return
        }
        SetTimer((*) => TranslateGui._ExtractRuntimeBundle(job.targetPath, files), -10)
    }

    static _ExtractRuntimeBundle(zipPath, files) {
        progress := RmtProgress(GetLang("安装翻译组件"), GetLang("正在解压"),
            XamlWin.ActiveOwner())
        result := ""
        try {
            progress.Show()
            result := RmtExtractAssetBundle(zipPath, files, progress)
        } finally progress.Close()
        if (result == "ok")
            Toast.Success(GetLang("翻译组件已就绪"))
        else
            Toast.Error(GetLang("翻译组件下载完成，但解压失败。"))
    }

    _EnsureReady() {
        if (this._closed || !IsObject(this.ui))
            return
        ; 组件查缺优先：模型下载依赖 DLL 就位，别让两件事一起弹
        missing := TranslateGui.MissingRuntimeFiles()
        if (missing.Length) {
            list := ""
            for file in missing
                list .= "`n  · " file.entry
            prompt := Format(GetLang("翻译组件缺少 {} 个文件：{}`n`n是否立即下载补齐？"), missing.Length, list)
            if (RmtDialog.Confirm(prompt, GetLang("翻译"), this.Hwnd()))
                TranslateGui._DownloadRuntimeFiles()
            return
        }
        engine := TranslateGui._ChoiceValue(this.ui.Query("Engine"), TranslateGui.Choices["Engine"])
        if (!TranslateCommand.IsLocal(engine))
            return
        modelName := TranslateCommand.EngineModels[engine]
        if (TranslateEngine.HasModel(modelName))
            return
        TranslateGui._PromptModelDownload(modelName)
    }

    OnEngineChanged(state, ctrl, event) {
        SetTimer(ObjBindMethod(this, "_EnsureReady"), -10)
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
        this._RebuildGlossaryChips()
    }

    OnWindowClosing(state, ctrl, event) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this._closed := true
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
}

RmtRequestInternalDownload(assetId) => TranslateGui.RequestInternalDownload(assetId)
