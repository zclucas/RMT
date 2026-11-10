#Requires AutoHotkey v2.0

; =====================================================================
; 自由粘贴面板 —— XAML 迁移版
; 公开接口保持：ShowGui() / DestroyGui / _wheelCb（UIUtil.ahk:64 外部清零）
; 面板为无边框置顶小窗：显示剪贴板图片/文本，滚轮缩放（文本字号5~20，图片×1.15/0.85），
; 左键拖拽移动，双击关闭；支持多面板并存（GuiMap 以窗口句柄为键）。
; 尺寸自适应：窗口 SizeToContent="WidthAndHeight"，内容 FontSize/Width/Height 变化即自动跟随。
; =====================================================================

class FreePasteGui {
    __new() {
        this.GuiMap := Map()
        this._wheelCb := ""
        this.ui := ""
        this.curGui := ""
        this.sequence := 0
    }

    ShowGui() {
        this.AddGui()
    }

    ShowPrompt(isImage, value, name := "", temporary := false) {
        if (name != "")
            this.ClosePrompt(false, name)
        try {
            if (!this._BuildAndShow(isImage, value, name, temporary) && temporary)
                PromptReleaseImage(value)
        } catch {
            if (temporary)
                PromptReleaseImage(value)
            throw
        }
    }

    ClosePrompt(all, name := "") {
        matches := []
        latest := ""
        for _, data in this.GuiMap {
            if (all || (name != "" && data.Name == name))
                matches.Push(data.ui)
            else if (name == "" && (!IsObject(latest) || data.Sequence > latest.Sequence))
                latest := data
        }
        if (IsObject(latest))
            matches.Push(latest.ui)
        for ui in matches
            this.DestroyGui(ui)
    }

    _WatchWheel() {
        ; 订阅滚轮热键（粘贴窗口活动期间有效）
        if (!this._wheelCb) {
            this._wheelCb := ObjBindMethod(this, "_OnWheel")
            WinHotkey.SubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.SubscribeMouse("WheelDown", this._wheelCb)
        }
    }

    DestroyGui(ui) {
        this._RemoveUi(ui)
        if (IsObject(ui)) {
            try ui.Update("Window", "Close", "")
        }
    }

    ; 从 GuiMap 移除面板；全部面板销毁后取消订阅滚轮热键（幂等，双路径共用）
    _RemoveUi(ui) {
        hwnd := (IsObject(ui) && ui.HasProp("wpfHwnd")) ? ui.wpfHwnd : 0
        if (hwnd != 0 && this.GuiMap.Has(hwnd)) {
            data := this.GuiMap.Delete(hwnd)
            PromptReleaseImage(data.TemporaryPath)
        }
        if (this.GuiMap.Count == 0 && this._wheelCb) {
            WinHotkey.UnsubscribeMouse("WheelUp", this._wheelCb)
            WinHotkey.UnsubscribeMouse("WheelDown", this._wheelCb)
            this._wheelCb := ""
        }
    }

    AddGui() {
        ; 检测剪贴板格式
        isImage := DllCall("IsClipboardFormatAvailable", "UInt", 8)  ; CF_DIB = 8
        isText := IsClipboardText()

        if (isImage) {
            CurrentDateTime := FormatTime(, "MM月dd日HH-mm-ss")
            filePath := A_WorkingDir "\Images\FreePaste\" CurrentDateTime ".png"
            SaveClipToBitmap(filePath)
            this.ShowPrompt(true, filePath)
        } else if (isText)
            this.ShowPrompt(false, A_Clipboard)
    }

    _BuildAndShow(isImage, value, name, temporary) {
        global MySoftData
        title := "RMT-FreePaste"
        this._title := title

        main := XAML_Generator("Grid").Name("OverlayCon").Background("White")

        if (isImage) {
            size := GetImageSize(value)
            if (size[1] <= 0 || size[2] <= 0)
                throw ValueError(GetLang("无法读取图片") ": " value)
            main.Add("Image").Name("ImageCon").Width(size[1]).Height(size[2]).Stretch("Uniform")
                .Source(StrReplace(value, "\", "/"))
        }
        else {
            main.Add("TextBlock").Name("TextCon").Text(value).FontSize(13).FontWeight("SemiBold")
                .Margin("10").Foreground("#FF000000")
        }

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "0")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="RMT-FreePaste" Width="300" Height="200" SizeToContent="WidthAndHeight"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="CenterScreen" Topmost="True" ShowInTaskbar="False"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件（闭包捕获本面板 ui，支持多面板并存；事件回调为异步 SetTimer，勿做阻塞操作）===
        localUi := this.ui
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing").Bind(localUi))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("OverlayCon", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnOverlayMouseDown").Bind(localUi))

        if (!XamlWin.Open(localUi)) {
            this.DestroyGui(localUi)
            return false
        }

        ; 登记 GuiMap（以窗口句柄为键，滚轮回调/双击/关闭共用）
        guiData := FreePasteData(localUi)
        guiData.Name := name
        guiData.Sequence := ++this.sequence
        guiData.TemporaryPath := temporary ? value : ""
        if (isImage)
            guiData.InitImage("ImageCon", size[1], size[2])
        else
            guiData.InitText("TextCon")
        guiData.InitOverlay("OverlayCon")
        this.GuiMap.Set(localUi.wpfHwnd, guiData)
        this.curGui := localUi
        this._WatchWheel()
        return true
    }

    ; 左键单击拖拽窗口，双击销毁面板（与原生 Click/DoubleClick 语义一致）
    OnOverlayMouseDown(ui, state, ctrl, event) {
        clickCount := (IsObject(state) && state.Has("ClickCount")) ? state["ClickCount"] : "1"
        if (clickCount == "2" || clickCount == 2) {
            this.DestroyGui(ui)
        }
        else {
            hwnd := (IsObject(ui) && ui.HasProp("wpfHwnd")) ? ui.wpfHwnd : 0
            if (hwnd != 0)
                PostMessage(0xA1, 2, , , "ahk_id " hwnd)  ; WM_NCLBUTTONDOWN, HTCAPTION：拖拽移动
        }
    }

    OnWindowClosing(ui, state, ctrl, event) {
        this._RemoveUi(ui)
        if (this.curGui == ui)
            this.curGui := ""
        if (this.ui == ui)
            this.ui := ""
    }

    OnWindowLoad(state, ctrl, event) {
        ; 粘贴面板固定白底黑字，不套主题，保持与原生 BackColor=FFFFFF 一致
    }

    ; 拖动函数（原生 PostMessage 语义，仅目标窗口句柄改为 wpfHwnd）
    GuiDrag(hwnd, *) {
        PostMessage(0xA1, 2, , , "ahk_id " hwnd)
    }

    ; 双击关闭（保留原方法名，参数语义从原生 Gui 对象改为面板 ui）
    DoubleClick(ui, *) {
        this.DestroyGui(ui)
    }

    _OnWheel(key) {
        this.OnScrollWheel(key)
    }

    OnScrollWheel(key) {
        MouseGetPos(&x, &y, &windId)
        if (!this.GuiMap.Has(windId))
            return

        isDown := InStr(key, "Down", "Off") ? true : false
        valueSymbol := isDown ? -1 : 1
        valueScale := isDown ? 0.85 : 1.15
        guiData := this.GuiMap[windId]
        if (guiData.Type == 1) {
            guiData.FontSize += valueSymbol
            guiData.FontSize := Min(guiData.FontSize, 20)
            guiData.FontSize := Max(guiData.FontSize, 5)
            ; SizeToContent 下窗口自动跟随字号缩放
            guiData.ui.Update("TextCon", "FontSize", String(guiData.FontSize))
        }

        if (guiData.Type == 2) {
            guiData.ImageWidth *= valueScale
            guiData.ImageHeight *= valueScale
            ; SizeToContent 下窗口自动跟随图片尺寸缩放
            guiData.ui.Update("ImageCon", "Width", String(Round(guiData.ImageWidth)))
            guiData.ui.Update("ImageCon", "Height", String(Round(guiData.ImageHeight)))
        }
    }
}

class FreePasteData {
    __New(ui) {
        this.ui := ui
        this.Gui := ui          ; 兼容原字段名（原为原生 Gui 对象）
        this.Type := 0
        this.FontSize := 13
        this.ImageWidth := 0
        this.ImageHeight := 0
        this.TextCon := ""
        this.ImageCon := ""
        this.OverlayCon := ""
    }

    InitText(textConName) {
        this.Type := 1
        this.TextCon := textConName
        this.FontSize := 13
    }

    InitImage(imageConName, width, height) {
        this.Type := 2
        this.ImageCon := imageConName
        this.ImageWidth := width
        this.ImageHeight := height
    }

    InitOverlay(overlayConName) {
        this.OverlayCon := overlayConName
    }
}
