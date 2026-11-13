#Requires AutoHotkey v2.0

; =====================================================================
; 输入弹窗 —— XAML 迁移版（独立实现）
; 公开接口保持：ShowGui(Label, Content) / SureAction / HideAction / CloseAction
;
; 本文件只管窗口：布局、主题、确定/取消、Enter 确认与 Shift+Enter 换行，
; 以及把语音识别出的文字贴进输入框、把录音状态反映到麦克风图标上。
; 语音本身由 Main\Util\SttUtil.ahk 里的 class VoiceInput 提供接口，
; 窗口不碰模型、不碰解码、不碰轮询节奏。
; =====================================================================

class CustomInputGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this._submitting := false ; 确定已按下：吃掉连点与重复的 Enter
        this._voice := ""
        this._recBase := ""      ; 开录时框内的原文（识别的追加起点）
        this._recText := ""      ; 本轮已写入框内的完整文本（本地副本，免去反复查询）
        this._pttAt := 0         ; 上次按住说话键按下的时刻（吃掉热键连发）
        this._pttIds := []       ; 窗口级热键的注册令牌，关窗时注销
        this.HideAction := ""
        this.SureAction := ""
        this.CloseAction := ""
    }

    ShowGui(Label, Content) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        if (IsObject(this.ui)) {
            this.ui.Update("LabelCon", "Text", Label)
            this.ui.Update("ContentCon", "Text", Content)
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
        else
            this._BindPttHotkey()
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        this._submitting := false
        this._voice := ""
        this._recBase := ""
        this._recText := ""
        this._pttAt := 0
        this._pttIds := []
        title := GetLang("输入-弹窗")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,12")
        body.Rows("28", "*", "48")
        ; 麦克风按钮放标签行右侧：不占输入区、也不压到文本上（输入区叠按钮会被裁切）
        promptRow := body.Add("DockPanel").Grid_Row(0)
        promptRow.Add("Button").Name("BtnMic").DockPanel_Dock("Right").Width(26).Height(26)
            .VerticalAlignment("Center").Padding("0").Margin("6,0,0,0")
            .Background("Transparent").BorderThickness("0").Cursor("Hand")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            .Foreground("{DynamicResource TextSub}").ToolTip(this._VoiceToolTip())
        promptRow.Add("TextBlock").Name("LabelCon").Text("").VerticalAlignment("Center")

        body.Add("TextBox").Grid_Row(1).Name("ContentCon").AcceptsReturn("True").TextWrapping("Wrap")
            .VerticalContentAlignment("Top").Padding("6,8,6,8").Margin("0,8,0,8")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")

        btnRow := body.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        okBtn := AddCmdOkBtn(btnRow).IsDefault("True")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="365" Height="252"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        ; Enter 确认、Shift+Enter 换行：引擎对 PreviewKeyDown:Return 已置 Handled，不会插入原生换行
        this.ui.OnEvent("Window", "PreviewKeyDown:Return", XamlWin.BindCurrent(this, "OnEnter"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        this._SetupVoice()
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        try this.ui.Update("ContentCon", "Focus", "True")
        ; 录音时每 40ms 要刷新一次文本，而默认的 Update 是同步 SendMessage，会把主线程
        ; 按在引擎的渲染节奏上。必须走伪线程——建槽要发同步 AsyncAttach，
        ; 在引擎事件回调栈里发会互等死锁。
        SetTimer(ObjBindMethod(this, "_EnableAsyncUpdate"), -1)
        ; 模型首次加载要 1~3 秒（读 onnx + 建 session），交给 DLL 后台线程，界面全程不卡
        SetTimer(ObjBindMethod(this, "_WarmupVoice"), -60)
    }

    ; 开窗后把本窗口的更新切到共享内存异步通道（等价主窗口的 asyncUpdate）。
    ; 旧版引擎不支持时会自动回退同步，行为不退化。
    _EnableAsyncUpdate() {
        if (!IsObject(this.ui) || this._closed || !this.Hwnd())
            return
        try this.ui.asyncUpdate := true
        try this.ui._EnsureAsyncUpdSlot()
    }

    _WarmupVoice() {
        if (this._closed || !IsObject(this._voice))
            return
        this._voice.Warmup()
    }

    ; 输入框里的回车：Enter 提交，Shift+Enter 在光标处换行（多行粘贴保留换行）
    OnEnter(state, ctrl, event) {
        if (this._closed || this._submitting)
            return
        mods := state.Has("KeyModifiers") ? state["KeyModifiers"] : ""
        if (mods == "Shift") {
            if (state.Has("KeyFromEditable")) {
                start := this.ui.Query("ContentCon>SelectionStart")
                if (!IsInteger(start))
                    return
                this.ui.Update("ContentCon", "SelectedText", "`r`n")
                this.ui.Update("ContentCon", "CaretIndex", start + 2)
            }
        } else if (mods == "") {
            this.OnSureBtnClick(state, ctrl, event)
        }
    }

    OnWindowClosing(state, ctrl, event) {
        this._TeardownVoice()
        this.OnClose()
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._TeardownVoice()
        this.OnClose()
        this._CloseWindow()
    }

    _CloseWindow() {
        this._TeardownVoice()
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnSureBtnClick(state, ctrl, event) {
        if (this._closed || this._submitting)
            return
        this._submitting := true
        ; 停录并拿最终识别文本（DLL 在 End 里会把尾音收干净再返回），避免丢最后一句。
        ; 收尾结果会经 OnVoiceText 回来，这里不用再手动上屏。
        if (IsObject(this._voice))
            this._voice.Commit()
        this.OnSure()
        this.OnHide()
        this._CloseWindow()
    }

    OnCloseBtnClick(state, ctrl, event) {
        this._TeardownVoice()
        this.OnClose()
        this.OnHide()
        this._CloseWindow()
    }

    OnSure() {
        if (this.SureAction != "") {
            Action := this.SureAction
            Action(this.ui.Query("ContentCon"))
            this.SureAction := ""
        }
    }

    OnClose() {
        if (this.CloseAction != "") {
            Action := this.CloseAction
            Action()
            this.CloseAction := ""
        }
    }

    OnHide() {
        if (this.HideAction != "") {
            Action := this.HideAction
            Action()
            this.HideAction := ""
        }
    }

    ; =================================================================
    ; 语音输入：只做“把接口事件翻译成界面动作”
    ; =================================================================

    ; 绑定麦克风按钮与按住说话。引擎侧事件必须在 XamlWin.Open 之前绑：
    ; 在引擎事件回调里（如 LoadedHwnd）再发同步的注册消息会和引擎互等。
    ; 按住说话键是 AHK 窗口级热键（要窗口句柄），另在 Open 之后由 _BindPttHotkey 绑。
    _SetupVoice() {
        this._voice := VoiceInput()
        this._voice.OnText := ObjBindMethod(this, "OnVoiceText")
        this._voice.OnState := ObjBindMethod(this, "OnVoiceState")
        this._voice.OnNotify := ObjBindMethod(this, "OnVoiceNotify")
        this._voice.HoldCheck := ObjBindMethod(this, "IsPttHeld")
        this.ui.OnEvent("BtnMic", "Click", ObjBindMethod(this, "OnMicClick"))
        ; 失活兜底：Alt+Tab 之后收不到按键松开，麦克风会一直开着
        this.ui.OnEvent("Window", "Deactivated", ObjBindMethod(this, "OnWindowDeactivated"))
    }

    ; 按住说话键：走 WinHotkey 的窗口级热键（和调试快捷键一套），
    ; HotIfWinActive 限定在本窗口，键名原样交给 AHK，不需要翻译成引擎的 WPF Key 名。
    ; 配置里是什么键就绑什么键，代码不规定能用哪些键。
    _BindPttHotkey() {
        key := this._PttHotkey()
        hwnd := this.Hwnd()
        if (key == "" || !hwnd)
            return
        ; ~ 前缀：按键照常透传，不吞键。否则窗口内按住 Alt 会把 Alt+Tab 之类的组合截住。
        try this._pttIds := WinHotkey.Register(["~" key], ObjBindMethod(this, "_OnPttPress"), hwnd)
    }

    ; 配置里的按住说话键（「设置 → 快捷键 → 语音输入」，默认左 Alt）。
    ; 只接受单个物理键：松手是靠轮询这个键的物理状态判定的，组合键没有单一的松开时刻。
    ; 键名交给 GetKeyVK 校验，系统不认识的一律按未配置处理（只能点麦克风按钮）。
    _PttHotkey() {
        global MainSoftData
        if (!MainSoftData.HasProp("VoiceInputHotkey"))
            return ""
        ; 去掉通配 / 穿透 / 左右限定前缀，剩下的必须是一个键名
        key := RegExReplace(Trim(String(MainSoftData.VoiceInputHotkey)), "^[~$*<>]+")
        if (key == "" || RegExMatch(key, "[!^+#&]"))
            return ""
        return GetKeyVK(key) ? key : ""
    }

    ; 麦克风按钮提示：键名怎么显示交给 FormatHotkeyDisplay，这里不做按键特判
    _VoiceToolTip() {
        key := this._PttHotkey()
        return key == "" ? GetLang("语音输入") : GetLang("语音输入") " · " FormatHotkeyDisplay(key)
    }

    ; 停掉语音、注销热键，避免窗口销毁后回调还在跑
    _TeardownVoice() {
        if (this._pttIds.Length > 0) {
            try WinHotkey.UnregisterAll(this._pttIds)
            this._pttIds := []
        }
        if (!IsObject(this._voice))
            return
        try this._voice.Close()
        this._voice := ""
    }

    ; 松手判定：配置的键还按着就不收尾（VoiceInput 每 40ms 来问，收不到 KeyUp 也能停）
    IsPttHeld() {
        key := this._PttHotkey()
        if (key == "")
            return false
        try return GetKeyState(key, "P")
        catch
            return false
    }

    OnMicClick(state := "", ctrl := "", info := "") {
        this._ToggleVoice(false)
    }

    ; 按住说话键按下（窗口级热键回调，key 是实际触发的热键名）
    _OnPttPress(key := "") {
        if (this._closed || !IsObject(this._voice))
            return
        ; 已经在录（点按钮起的）或在等模型：按住说话键不抢占，也不重复开录
        if (this._voice.IsRecording() || this._voice.IsWaiting())
            return
        ; 长按时系统会连发热键，一次按住只处理第一次
        if (this._pttAt != 0 && A_TickCount - this._pttAt < 200)
            return
        this._pttAt := A_TickCount
        this._ToggleVoice(true)
    }

    ; 窗口失活（Alt+Tab 等）：收不到按键松开事件了，直接停录提交，避免麦克风一直开着
    OnWindowDeactivated(state, ctrl, info) {
        if (!IsObject(this._voice))
            return
        ; 等模型加载的排队在切窗后已无意义，直接作废
        if (this._voice.IsWaiting()) {
            this._voice.CancelWait()
            return
        }
        if (this._voice.IsRecording())
            this._voice.Stop(true)
    }

    ; 开始 / 停止 / 取消等待，三态判断与缺模型引导都在 VoiceInput.Toggle 里
    _ToggleVoice(byHold) {
        if (this._closed || !IsObject(this._voice))
            return
        this._voice.Toggle(byHold)
    }

    ; 实时识别文本按「追加」处理（论坛反馈#503）：以开录时框内原文为基准整段刷新。
    ; 绝大多数情况只是末尾接字，把增量追加进去就行——整段 Text 赋值会重建 TextBox
    ; 全文、光标归位到 0、滚动条跳回顶部，长文本时既费时又看不到最新的字。
    OnVoiceText(text) {
        if (!IsObject(this.ui) || this._closed)
            return
        pre := this._recBase
        sep := (pre != "" && !RegExMatch(pre, "\s$")) ? " " : ""
        full := pre sep text
        if (full == this._recText)
            return
        prev := this._recText
        this._recText := full
        n := StrLen(prev)
        if (n > 0 && StrLen(full) > n && SubStr(full, 1, n) == prev)
            this.ui.Update("ContentCon", "AppendText", SubStr(full, n + 1))
        else
            this.ui.Update("ContentCon", "Text", full)
    }

    ; 录音状态变化 → 图标与文字颜色
    OnVoiceState(state) {
        if (!IsObject(this.ui) || this._closed)
            return
        if (state == "recording") {
            ; 记下框内原文作为本轮追加起点，之后整轮不再查询输入框
            cur := ""
            try cur := this.ui.Query("ContentCon")
            this._recBase := cur
            this._recText := cur
            try this.ui.Update("ContentCon", "Foreground", "{DynamicResource TextSub}")
            try this.ui.Update("BtnMic", "Foreground", "{DynamicResource Accent}")
            try this.ui.Update("BtnMic", "ToolTip", GetLang("停止录音"))
            return
        }
        ; idle
        try this.ui.Update("ContentCon", "Foreground", "{DynamicResource InputText}")
        try this.ui.Update("BtnMic", "Foreground", "{DynamicResource TextSub}")
        try this.ui.Update("BtnMic", "ToolTip", this._VoiceToolTip())
    }

    ; 需要告诉用户的事。文案与提示方式都归窗口管，语音层只给 key。
    OnVoiceNotify(key, detail := "") {
        ; 注意：try 后面必须跟大括号，不能让 try 直接做 if 的单条语句体，
        ; 否则 AHK 解析到下一个 else 会报 Unexpected "Else"。
        if (key == "loading") {
            try Toast.Info(GetLang("语音模型加载中…加载完自动开始"))
        } else if (key == "loadFailed") {
            try Toast.Error(GetLang("语音模型加载失败，请重试"))
        } else if (key == "readyRetry") {
            ; 有配键就带上键名，没配就只说就绪
            k := this._PttHotkey()
            if (k == "") {
                try Toast.Info(GetLang("语音模型已就绪"))
            } else {
                try Toast.Info(GetLang("语音模型已就绪，按住") " " FormatHotkeyDisplay(k) " " GetLang("再说一次"))
            }
        } else if (key == "startFailed") {
            try Toast.Error(GetLang("开始录音失败：") (detail != "" ? detail : GetLang("未知错误")))
        }
    }
}
