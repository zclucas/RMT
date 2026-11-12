#Requires AutoHotkey v2.0

; XAML 准星：窗口中心即采样点，中心留空，避免将定位标记采进预览。
class TargetGui {
    __New() {
        this.Gui := ""
        this.ui := ""
        this._hkIds := []
        this._lbuttonCb := ""
        this.active := false
        this._tick := ObjBindMethod(this, "_Refresh")
    }

    Hwnd() => IsObject(this.ui) ? this.ui.wpfHwnd : 0

    ShowGui(sureAction, targetHwnd := 0) {
        if (this.active)
            return false
        ; XAML 事件中延后建窗，避免嵌套 CREATE_WINDOW。
        this.active := true
        SetTimer(ObjBindMethod(this, "_Open", sureAction, targetHwnd), -1)
        return true
    }

    _Open(sureAction, targetHwnd) {
        if (!this.active)
            return
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&startX, &startY)
            this.startX := startX, this.startY := startY
            ui := this.AddGui()
            if (this.ui != ui)
                return
            MyColorPanel.ShowGui(sureAction, targetHwnd)
            if (this.ui != ui)
                return
            this._hkIds := WinHotkey.Register(["Left", "Right", "Up", "Down", "Enter", "Escape"], ObjBindMethod(this, "_OnHotkey"))
            SetTimer(this._tick, 60)
        } catch as err {
            MyColorPanel.OnClose()
            RmtDialog.Info(err.Message, GetLang("定位取色器"))
        }
    }

    AddGui() {
        win := ColorPanelGui.Window("RMT-Target", 72)
        win.Height(72).Cursor("SizeAll")
        canvas := win.Add("ContentControl").Name("DragArea").Add("Canvas").Width(72).Height(72).Background("#01000000")
        ; 三层描边：黑白轮廓保证对比度，主题主色突出准星。1/255 的底层让空白区域也能拖动。
        for index, stroke in ["#FF111827", "#FFFFFFFF", "{DynamicResource ActionBg}"] {
            thick := index == 1 ? 9 : index == 2 ? 7 : 4
            canvas.Add("Ellipse").Width(40).Height(40).Canvas_Left(16).Canvas_Top(16).Stroke(stroke).StrokeThickness(thick)
            for p in [[36, 3, 36, 22], [36, 50, 36, 69], [3, 36, 22, 36], [50, 36, 69, 36]]
                canvas.Add("Line").X1(p[1]).Y1(p[2]).X2(p[3]).Y2(p[4]).Stroke(stroke).StrokeThickness(thick)
        }
        this.ui := XAMLHost(win.ToString(), "", WinExist("A"))
        this.ui.skipFontScale := true
        ui := this.ui
        this.ui.OnEvent("Window", "LoadedHwnd", XamlWin.BindCurrent(this, "_Loaded"))
        this.ui.OnEvent("Window", "Closing", (*) => this.ui == ui ? MyColorPanel.OnClose() : "")
        ; 准星整块就是 DragArea（窗口靠它拖动），这块客户端区域在 WM_NCHITTEST 里被当成标题栏，
        ; WPF 的 MouseDoubleClick 收不到。引擎把标题栏双击转成 NcDoubleClick 回传。
        this.ui.OnEvent("Window", "NcDoubleClick", XamlWin.BindCurrent(this, "GuiDoubleClick"))
        this.ui.OnEvent("DragArea", "MouseDoubleClick", XamlWin.BindCurrent(this, "GuiDoubleClick"))
        XamlWin.QueueTheme(this.ui)
        ; 不要给准星加「截屏排除」：那是 SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)，
        ; 效果是「只在本机显示器上显示，远程桌面里完全不出现」——远程使用者会看不到准星。
        ; 取色靠 BitBlt(SRCCOPY) 采样，本身不含分层窗口，准星不会污染采样结果。
        ui.Show()
        if (this.ui == ui)
            this.Gui := GuiAdapter(ui)
        return ui
    }

    _Loaded(*) {
        ui := this.ui
        if (!this.active || !IsObject(ui) || !ui.wpfHwnd)
            return
        hwnd := ui.wpfHwnd
        try {
            WinGetPos(, , &w, &h, hwnd)
            WinMove(this.startX - Round(w / 2), this.startY - Round(h / 2), , , hwnd)
            if (this.ui == ui)
                ui.Update("Window", "Opacity", "1")
        } catch TargetError {
            ; 窗口可能在 LoadedHwnd 回调执行期间已经关闭。
        }
    }

    GuiDrag(*) {
        if (this.active && this.Hwnd())
            PostMessage(0xA1, 2, , , this.Hwnd())
    }

    GetPoint(&x, &y) {
        WinGetPos(&left, &top, &w, &h, this.Hwnd())
        x := left + Round(w / 2)
        y := top + Round(h / 2)
    }

    _Refresh(*) {
        if (!this.active || !this.Hwnd() || !IsObject(MyColorPanel.ui) || !MyColorPanel.ui.wpfHwnd)
            return
        try {
            ; 面板仅首次定位，用户拖动后保持当前位置。
            MyColorPanel.RefreshCoord()
            MyColorPanel.RefreshMapImage()
        }
    }

    _OnHotkey(key) {
        if (!this.active)
            return
        if (key == "Escape") {
            MyColorPanel.OnClose()
            return
        }
        if (key == "Enter") {
            MyColorPanel.GuiDoubleClick()
            return
        }
        hwnd := this.Hwnd()
        if (!hwnd)
            return
        WinGetPos(&x, &y, &w, &h, hwnd)
        dx := key == "Left" ? -1 : key == "Right" ? 1 : 0
        dy := key == "Up" ? -1 : key == "Down" ? 1 : 0
        this.GetPoint(&px, &py)
        ; 物理像素微调，不受显示缩放影响，支持负坐标副屏。
        if (px + dx < SysGet(76) || px + dx >= SysGet(76) + SysGet(78)
            || py + dy < SysGet(77) || py + dy >= SysGet(77) + SysGet(79))
            return
        WinMove(x + dx, y + dy, , , hwnd)
        this._Refresh()
    }

    ResetPosition(*) {
        if (!this.active || !this.Hwnd())
            return
        ; 点击复位时以信息面板所在的显示器为准，包括负坐标副屏。
        WinGetPos(&px, &py, &pw, &ph, MyColorPanel.ui.wpfHwnd)
        cx := px + pw / 2, cy := py + ph / 2
        monitor := MonitorGetPrimary()
        loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            if (cx >= l && cx < r && cy >= t && cy < b) {
                monitor := A_Index
                break
            }
        }
        MonitorGet(monitor, &l, &t, &r, &b)
        WinGetPos(, , &w, &h, this.Hwnd())
        WinMove(Round((l + r) / 2) - Round(w / 2), Round((t + b) / 2) - Round(h / 2), , , this.Hwnd())
        this._Refresh()
    }
    HideGui() {
        this.active := false
        SetTimer(this._tick, 0)
        WinHotkey.UnregisterAll(this._hkIds)
        this._hkIds := []
        ui := this.ui
        this.ui := ""
        this.Gui := ""
        if IsObject(ui)
            try ui.Update("Window", "Close", "")
    }

    GuiDoubleClick(*) => MyColorPanel.GuiDoubleClick()
    OnArrowKeyDown(key) => this._OnHotkey(key)
}
