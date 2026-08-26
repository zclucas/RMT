#Requires AutoHotkey v2.0

; ============================================================================
; 主窗口 XAML 迁移
; 用 XAMLHost + XAML_Generator 替代原生 Gui() 应用壳。
; 适配器让消费文件对原生控件的 .Value/.Text/.Hwnd/.Focus()/.GetPos()/.Opt()
; 等引用继续工作：
;   GuiAdapter  -> MainSoftData.MyGui
;   TabAdapter  -> MainSoftData.TabCtrl
;   CtrlAdapter -> UIControls.* / MainSoftData.Tool*Ctrl / MainSoftData.BtnSave
; ============================================================================

class CtrlAdapter {
    __New(name, ui, prop := "Text") {
        this._name := name
        this._ui := ui
        this._prop := prop        ; "Text" | "IsChecked" | "SelectedIndex"
    }
    Value {
        get {
            v := this._ui.Query(this._name)
            if (this._prop == "IsChecked")
                return (v == "True")
            return v
        }
        set {
            if (this._prop == "IsChecked")
                this._ui.Update(this._name, "IsChecked", value ? "True" : "False")
            else if (this._prop == "SelectedIndex")
                this._ui.Update(this._name, "SelectedIndex", String(value - 1))
            else
                this._ui.Update(this._name, this._prop, String(value))
        }
    }
    Text {
        get => this._ui.Query(this._name)
        set => this._ui.Update(this._name, "Text", String(value))
    }
    Focus() {
        this._ui.Update(this._name, "Focus", "True")
    }
    Enabled {
        set => this._ui.Update(this._name, "IsEnabled", value ? "True" : "False")
    }
}

class TabAdapter {
    __New(ui) {
        this.ui := ui
        this._value := 1
    }
    Value {
        get => this._value
        set {
            this._value := value
            this.ui.Update("TabControl", "SelectedIndex", String(value - 1))
        }
    }
    UseTab(i := "") {
        if (i != "")
            this.Value := i
    }
    Move(*) {
    }
    OnEvent(evt, cb) {
        if (evt == "Change")
            this.ui.OnEvent("TabControl", "SelectionChanged", cb)
    }
}

class GuiAdapter {
    __New(ui) {
        this.ui := ui
        this._title := ""
    }
    Hwnd {
        get => this.ui.wpfHwnd
    }
    Title {
        get => this._title
        set {
            this._title := value
            this.ui.Update("Window", "Title", value)
        }
    }
    Show(opts := "") {
        hwnd := this.ui.wpfHwnd
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return
        if (opts != "") {
            if (RegExMatch(opts, "i)x(\d+)", &mx) && RegExMatch(opts, "i)y(\d+)", &my)) {
                w := RegExMatch(opts, "i)w(\d+)", &mw) ? Integer(mw[1]) : 1070
                h := RegExMatch(opts, "i)h(\d+)", &mh) ? Integer(mh[1]) : 590
                WinMove(Integer(mx[1]), Integer(my[1]), w, h, hwnd)
            }
        }
        WinShow(hwnd)
        ; 与原生 Gui.Show 语义一致：显示即激活（托盘「显示窗口」/最小化启动恢复都走这里）
        try WinActivate(hwnd)
    }
    Hide() {
        WinHide(this.ui.wpfHwnd)
    }
    Opt(opt) {
        if (InStr(opt, "AlwaysOnTop"))
            this.ui.Update("Window", "Topmost", SubStr(opt, 1, 1) == "+" ? "True" : "False")
    }
    GetPos(&x, &y, &w, &h) {
        WinGetPos(&x, &y, &w, &h, this.ui.wpfHwnd)
    }
    Flash() {
        DllCall("FlashWindow", "Ptr", this.ui.wpfHwnd, "Int", 1)
    }
    Submit() {
        return ""   ; 值已由事件/回读同步到 MainSoftData，此处 no-op
    }
}

; ============================================================================
; MainWin — 主窗口壳 + 静态页 + 宏列表渲染
; ============================================================================
class MainWin {
    __New() {
        this.ui := ""
        this.closed := false
        this._linkCounter := 0
        this._linkQueue := []
        ; 每页已渲染的宏条目索引（供 RefreshItemColorUI 判断是否需更新色点）
        this.RenderedItems := Map()
        ; Epic5 虚拟列表：宏/模块显示区（tab1-7）全走 _vl 渲染（模板已支持全部表类型：
        ; Normal/String/Menu/UI/Timing/SubMacro/Replace 的标志行 + IsEnabled 绑定），
        ; 结构操作（增删/折叠/上下移）只发 VL_INIT/VL_FOLD/VL_MOVE 增量命令，不再整表重建，
        ; 消除旧路径新增宏/折叠的界面闪烁与千条级卡顿；tab8-12 非宏页走 Panel_ 不受影响
        this._vl := ""
        this._useVirtual := Map()
        loop 7 {
            this._useVirtual[A_Index] := true
        }
    }

    BuildAndShow() {
        this.closed := false
        title := "RMTv" RMT_VERSION
        titleHeight := "36"

        ; 根内容固定按 1400×787 设计渲染：引擎 Viewbox 会保留显式尺寸，
        ; 再按窗口实际尺寸（随屏幕等比缩放，见下方 wh 计算）等比例缩放——
        ; 任何分辨率下内容布局完全一致（高分屏只是整体放大）。
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        main.Width(1400).Height(787)
        main.Rows(titleHeight, "*")
        main.Cols("130", "*")

        ; ---- 标题栏 ----
        tb := main.Add("Border").Grid_Row(0).Grid_ColumnSpan(2).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(XAMLHost.GetThemeFontSize() + 2).FontWeight("Bold").VerticalAlignment("Center").Margin("15,0,0,0").Padding("0")
        btnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right").VerticalAlignment("Stretch").Height(36)
        minBtn := btnGroup.Add("Button").Name("BtnMinimize").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(36).Padding("0").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        minBtn.Add("TextBlock").Text(Chr(0xE921)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        maxBtn := btnGroup.Add("Button").Name("BtnMaximize").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(36).Padding("0").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        maxBtn.Add("TextBlock").Text(Chr(0xE922)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        closeBtn := btnGroup.Add("Button").Name("BtnClosePanel").Style("{StaticResource TitleBarCloseButton}").WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(36).Padding("0").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; ---- 左操作栏 ----
        left := main.Add("Grid").Grid_Row(1).Grid_Column(0).Margin("6,6,4,6")
        left.Rows("*", "Auto")
        leftTop := left.Add("StackPanel").Grid_Row(0)
        leftTop.Add("TextBlock").Text(GetLang("当前配置")).FontWeight("Bold").FontSize(11).Opacity("0.7").Margin("4,0,0,2")
        leftTop.Add("TextBlock").Name("TxtCurSetting").Text(MySoftData.CurSettingName).FontWeight("SemiBold").Margin("4,0,0,2").TextTrimming("CharacterEllipsis")
        leftTop.Add("Button").Name("BtnConfig").Content(GetLang("配置管理")).Height(28).MinHeight(28).Margin("0,2,0,2")
        leftTop.Add("Rectangle").Height(1).Margin("2,8,2,6").Fill("{DynamicResource ControlBorder}").Stretch("Fill")
        leftTop.Add("TextBlock").Text(GetLang("全局操作")).FontWeight("Bold").FontSize(11).Opacity("0.7").Margin("4,0,0,4")
        leftTop.Add("CheckBox").Name("ChkSuspend").Content(GetLang("休眠")).Margin("2,0,0,0")
        leftTop.Add("TextBlock").Name("TxtSuspendKey").Text(FormatHotkeyDisplay(MainSoftData.SuspendHotkey)).Opacity("0.6").FontSize(11).Margin("6,0,0,0")
        leftTop.Add("CheckBox").Name("ChkPause").Content(GetLang("暂停")).Margin("2,8,0,0")
        leftTop.Add("TextBlock").Name("TxtPauseKey").Text(FormatHotkeyDisplay(MainSoftData.PauseHotkey)).Opacity("0.6").FontSize(11).Margin("6,0,0,0")
        leftTop.Add("Button").Name("BtnKill").Content(GetLang("终止所有宏")).Height(28).MinHeight(28).Margin("0,8,0,0")
        leftTop.Add("TextBlock").Name("TxtKillKey").Text(FormatHotkeyDisplay(MainSoftData.KillMacroHotkey)).Opacity("0.6").FontSize(11).Margin("6,0,0,0")
        leftTop.Add("Button").Name("BtnReload").Content(GetLang("重载")).Height(28).MinHeight(28).Margin("0,8,0,0")
        leftBottom := left.Add("StackPanel").Grid_Row(1).VerticalAlignment("Bottom")
        leftBottom.Add("Button").Name("BtnHelp").Content(GetLang("RMT文档")).Height(28).MinHeight(28).Margin("0,2,0,2")
        leftBottom.Add("Button").Name("BtnSave").Content(GetLang("应用并保存")).Height(30).MinHeight(30).Margin("0,2,0,2").FontWeight("Bold")

        ; ---- 右侧 TabControl ----
        right := main.Add("Grid").Grid_Row(1).Grid_Column(1).Margin("0,4,8,4")
        tab := right.Add("TabControl").Name("TabControl").Style("{StaticResource RmtMainTabCtrl}").Background("{DynamicResource BgColor}").SelectedIndex(String(MainSoftData.TableIndex - 1))
        loop MainSoftData.TabNameArr.Length {
            idx := A_Index
            tabItem := tab.Add("TabItem").Header(GetLang(MainSoftData.TabNameArr[idx]))
            if (idx <= 7) {
                ; 宏/模块显示区：自适应剩余空间，外层边框包裹
                bd := tabItem.Add("Border").BorderThickness("1").BorderBrush("{DynamicResource InputStroke}").CornerRadius("4").Margin("4,2,4,4").Padding("2,2")
                if (this._useVirtual.Has(idx)) {
                    ; Epic5 虚拟列表：ListBox + DataTemplate + VirtualizingStackPanel(Recycling)，
                    ; 行模板注入 Window.Resources，由 _vl.Init 一次 VL_INIT 填充
                    vg := bd.Add("Grid")
                    vg.Add("ListBox").Name("FoldList_" idx).SelectionMode("Single").BorderThickness("0").Background("Transparent")
                        .Margin("4,2,4,2")
                        .VirtualizingPanel_IsVirtualizing("True").VirtualizingPanel_VirtualizationMode("Recycling")
                        .VirtualizingPanel_CacheLength("2,2").VirtualizingPanel_CacheLengthUnit("Page")
                    ; 吸顶折叠头 overlay（sticky header）：滚动时当前模块头钉在列表顶部
                    vg.Add("ContentControl").Name("VLSticky_" idx).VerticalAlignment("Top").HorizontalAlignment("Stretch").Visibility("Collapsed").Margin("4,2,4,2")
                } else {
                    sv := bd.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Auto")
                    sv.Add("StackPanel").Name("FoldList_" idx).Margin("4,2,4,2")
                }
            } else {
                sv := tabItem.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
                sv.Add("StackPanel").Name("Panel_" idx).Margin("8,6,8,10")
            }
        }

        ; ---- 组装窗口 ----
        ; 主界面 TabControl 用 WrapPanel 做 items host：多行排列严格按添加顺序，点击任意行不会重组
        tabStyle := '<Style x:Key="RmtMainTabCtrl" TargetType="TabControl">'
            . '<Setter Property="Background" Value="Transparent"/>'
            . '<Setter Property="BorderThickness" Value="0"/>'
            . '<Setter Property="Padding" Value="0"/>'
            . '<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabControl"><Grid>'
            . '<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>'
            . '<Border Grid.Row="0" Margin="4,10,4,0" CornerRadius="4" BorderThickness="1" BorderBrush="{DynamicResource InputStroke}" Padding="6,2"><WrapPanel IsItemsHost="True"/></Border>'
            . '<Border Grid.Row="1" Background="Transparent"><ContentPresenter ContentSource="SelectedContent"/></Border>'
            . '</Grid></ControlTemplate></Setter.Value></Setter>'
            . '</Style>'
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        tmp := StrReplace(tmp, "%resources%", tabStyle . this._BuildVListTemplates())
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        ; 首帧即定死保存位置：模板 CenterScreen 会让 WPF 强制居中并覆盖后续 WinMove → 先默认位置闪一帧。
        ; 改 Manual + 注入 Left/Top/Width/Height（AHK 逻辑坐标 = WPF DIP，125% DPI 下物理 132,126 已实测吻合，无单位错位）。
        ; LastWinPos 无效时保持 CenterScreen 1070×590 居中默认。
        pos := GetLastWinPos()
        startLoc := 'WindowStartupLocation="CenterScreen"'
        ; 主界面默认尺寸按屏幕等比缩放：1920×1080 参考 1400×787。
        ; 更宽的屏幕（横向富余）按高度缩放、更高的屏幕（纵向富余）按宽度缩放，
        ; 即缩放系数 = min(屏幕宽/1920, 屏幕高/1080)；用 DIP 屏幕尺寸计算，物理像素随 DPI 正确。
        dpiScale := DllCall("GetDpiForSystem", "UInt") / 96.0
        dipSW := A_ScreenWidth / dpiScale
        dipSH := A_ScreenHeight / dpiScale
        fs := Min(dipSW / 1920, dipSH / 1080)
        wh := 'Width="' Round(1400 * fs) '" Height="' Round(787 * fs) '"'
        if (pos.Length) {
            ; AHK 进程 DPI aware，WinGetPos/LastWinPos 是物理像素；XAML 注入按 DIP 解释，须换算（实测 125% 屏偏右下 26px）
            ; ponytail: 用 GetDpiForSystem 单值；跨屏不同 DPI 时可能偏差，待真机多屏再按 per-monitor 换算
            scale := DllCall("GetDpiForSystem", "UInt") / 96.0
            x := Round(pos[1] / scale), y := Round(pos[2] / scale), w := Round(pos[3] / scale), h := Round(pos[4] / scale)
            startLoc := 'WindowStartupLocation="Manual" Left="' x '" Top="' y '"'
            wh := 'Width="' w '" Height="' h '"'
        }
        ; 先填内容再显示：Opacity=0 走引擎离屏揭盖，避免空壳→主题/列表刷入时抖动
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ' wh ' Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', startLoc)

        ; ---- 壳级事件（初始 XAML 内，经 eventBindings 绑定） ----
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("Window", "Revealed", ObjBindMethod(this, "OnWindowRevealed"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCloseClick"))
        this.ui.OnEvent("BtnMinimize", "Click", ObjBindMethod(this, "OnMinimizeClick"))
        this.ui.OnEvent("BtnMaximize", "Click", ObjBindMethod(this, "OnMaximizeClick"))
        this.ui.OnEvent("TabControl", "SelectionChanged", ObjBindMethod(this, "OnTabChanged"))
        this.ui.OnEvent("BtnConfig", "Click", (*) => SettingMgrGui.ShowGui())
        this.ui.OnEvent("ChkSuspend", "Click", OnSuspendHotkey)
        this.ui.OnEvent("ChkPause", "Click", OnPauseHotKey)
        this.ui.OnEvent("BtnKill", "Click", OnKillAllMacro)
        this.ui.OnEvent("BtnReload", "Click", MenuReload)
        this.ui.OnEvent("BtnHelp", "Click", (*) => Run(A_WorkingDir "\index.html"))
        this.ui.OnEvent("BtnSave", "Click", OnSaveSetting)

        this._vl := VirtualListHost(this.ui)
        this.LoadLeftBarValues()
        this._startHidden := MainSoftData.HasProp("IsMinStart") && MainSoftData.IsMinStart
        this.ui._skipAutoReveal := this._startHidden
        ; ===== 先填充内容（Show 前入队，LoadedHwnd 时一次刷入），填充完再显示，避免空壳闪烁 =====
        try {
            this.PopulateAll()
        } catch {
        }
        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.wpfHwnd) {
                gotHwnd := true
                XamlUiDiag("MainWin hwnd=" this.ui.wpfHwnd, "MainWin")
                break
            }
            Sleep(50)
        }
    }

    PopulateAll() {
        this.BuildToolTab()
        this.BuildSettingTab()
        this.BuildHelpTab()
        this.BuildRewardTab()
        this.BuildThankTab()
        ; 惰性渲染：只渲染当前 tab（旧路径全量渲染 7 tab 是启动 1.3s 的主因），切 tab 时由 OnTabChanged 补渲染
        this._renderedTabs := Map()
        cur := MainSoftData.TableIndex
        this._renderedTabs[cur] := true
        this.RenderTab(MySoftData.TableInfo[cur])
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            ; 任务栏/Alt-Tab 图标：托盘已用 rabit.ico，窗口本身也要显式设置（脚本运行时默认是 AHK 图标）
            try {
                hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1", &ImageType := 1)
                if (hIcon)
                    this.ui.Update("Window", "Icon", "HICON:" hIcon)
            }
            ApplyXamlTheme(this.ui, MainSoftData.Theme)
            this.LoadLeftBarValues()
        } catch as e {
            XamlUiDiag("MainWin OnWindowLoad err: " e.Message, "MainWin")
        }
        ; 最小化启动：保持隐藏，不揭盖
        if (this.HasOwnProp("_startHidden") && this._startHidden)
            return
        try this.ui.Update("Window", "Opacity", "1")
    }

    OnWindowRevealed(state, ctrl, event) {
        try WinActivate("ahk_id " this.ui.wpfHwnd)
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        OnGuiClose()
        this.ui := ""
    }

    OnCloseClick(state, ctrl, event) {
        ; 主窗口关闭 = 隐藏（应用继续托盘运行），不真正销毁窗口，托盘可恢复
        OnGuiClose()
        try WinHide(this.ui.wpfHwnd)
    }

    OnMinimizeClick(state, ctrl, event) {
        try this.ui.Update("Window", "WindowState", "Minimized")
    }

    OnMaximizeClick(state, ctrl, event) {
        hwnd := (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
        if (!hwnd)
            return
        maxState := WinGetMinMax("ahk_id " hwnd)
        this.ui.Update("Window", "WindowState", maxState == 1 ? "Normal" : "Maximized")
    }

    OnTabChanged(state, ctrl, event) {
        v := this.ui.Query("TabControl>SelectedIndex")
        if (v == "")
            return
        idx := Integer(v) + 1
        MainSoftData.TableIndex := idx
        try MainSoftData.TabCtrl._value := idx
        OnTabValueChanged()
        ; 惰性渲染：该 tab 尚未构建过则首次切换时渲染（启动只渲染当前 tab）
        if (!this._renderedTabs.Has(idx)) {
            this._renderedTabs[idx] := true
            this.RenderTab(MySoftData.TableInfo[idx])
        }
    }

    LoadLeftBarValues() {
        this.ui.Update("TxtCurSetting", "Text", MySoftData.CurSettingName)
        this.ui.Update("ChkSuspend", "IsChecked", MainSoftData.IsSuspend ? "True" : "False")
        this.ui.Update("ChkPause", "IsChecked", MainSoftData.IsPause ? "True" : "False")
        ; BindUtil 读写侧栏开关状态，须挂 CtrlAdapter 否则 SuspendToggle/PauseToggle 是空串
        UIControls.SuspendToggle := CtrlAdapter("ChkSuspend", this.ui, "IsChecked")
        UIControls.PauseToggle := CtrlAdapter("ChkPause", this.ui, "IsChecked")
    }

    ; ============ 宏列表渲染 ============
    ReadTabValues(tableItem) {
        t := tableItem.Index
        if (this._useVirtual.Has(t))
            return  ; Epic5：VL_CHANGE 已逐字段写回模型，此处 no-op
        fi := tableItem.FoldInfo
        ; 收集所有需读取的控件名，单次批量 Query（一次 daemon 往返），替代逐项轮询
        names := []
        for f, spanStr in fi.IndexSpanArr {
            span := StrSplit(spanStr, "-")
            if (IsInteger(span[1]) && IsInteger(span[2])) {
                loop span[2] - span[1] + 1 {
                    i := span[1] + A_Index - 1
                    if (!this._IsRendered(t, i))
                        continue
                    names.Push("Remark_" t "_" i)
                    names.Push("TKType_" t "_" i ">SelectedIndex")
                    names.Push("Forbid_" t "_" i)
                    names.Push("Loop_" t "_" i)
                }
            }
            names.Push("FoldRemark_" t "_" f)
            names.Push("FoldFront_" t "_" f)
            names.Push("FoldForbid_" t "_" f)
            names.Push("FoldTKType_" t "_" f ">SelectedIndex")
            names.Push("FoldTK_" t "_" f)
        }
        if (names.Length == 0)
            return
        state := this.ui.Query(names*)

        for f, spanStr in fi.IndexSpanArr {
            span := StrSplit(spanStr, "-")
            if (IsInteger(span[1]) && IsInteger(span[2])) {
                loop span[2] - span[1] + 1 {
                    i := span[1] + A_Index - 1
                    if (!this._IsRendered(t, i))
                        continue
                    if (state.Has("Remark_" t "_" i))
                        try tableItem.RemarkArr[i] := state["Remark_" t "_" i]
                    if (state.Has("TKType_" t "_" i ">SelectedIndex"))
                        try tableItem.TriggerTypeArr[i] := Integer(state["TKType_" t "_" i ">SelectedIndex"]) + 1
                    if (state.Has("Forbid_" t "_" i))
                        try tableItem.ForbidArr[i] := state["Forbid_" t "_" i] == "True"
                    if (state.Has("Loop_" t "_" i))
                        try tableItem.LoopCountArr[i] := (state["Loop_" t "_" i] == GetLang("无限")) ? "-1" : state["Loop_" t "_" i]
                }
            }
            if (state.Has("FoldRemark_" t "_" f))
                try fi.RemarkArr[f] := state["FoldRemark_" t "_" f]
            if (state.Has("FoldFront_" t "_" f))
                try fi.FrontInfoArr[f] := state["FoldFront_" t "_" f]
            if (state.Has("FoldForbid_" t "_" f))
                try fi.ForbidStateArr[f] := state["FoldForbid_" t "_" f] == "True"
            if (state.Has("FoldTKType_" t "_" f ">SelectedIndex"))
                try fi.TKTypeArr[f] := Integer(state["FoldTKType_" t "_" f ">SelectedIndex"]) + 1
            if (state.Has("FoldTK_" t "_" f))
                try fi.TKArr[f] := state["FoldTK_" t "_" f]
        }
    }

    _IsRendered(t, i) {
        return this.RenderedItems.Has(t) && this.RenderedItems[t].Has(i)
    }

    RenderTab(tableItem) {
        t := tableItem.Index
        if (this._useVirtual.Has(t)) {
            ; Epic5：1 次 VL_INIT 填充虚拟列表（模型已由 VL_CHANGE 保持，视图全量重建成本 O(1) IPC）
            this._vl.Init(t, tableItem)
            return
        }
        this.RenderedItems[t] := Map()
        listName := "FoldList_" t
        this.ui.Update(listName, "ClearItems", "")
        fi := tableItem.FoldInfo
        ; B: 每模块 1 次 AddXamlItem 批量渲染（整组一个根 StackPanel），不再逐行 N 次桥接往返。
        ;    注意不能增量逐批加子项：StackPanel 每加一个子项就全量重测量（增量 = O(n²)），整组一次加 = O(n)。
        ; A: 折叠行也全渲染进 FoldItems_<t>_<f> 子容器，折叠切换只切容器 Visibility 不重建（千条级折叠/展开瞬间，滚动位置保留）
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        for f, spanStr in fi.IndexSpanArr {
            vis := fi.FoldStateArr[f] ? ' Visibility="Collapsed"' : ""
            xaml := '<StackPanel ' ns '>'
                . this._BuildFoldTitleRow(t, f)
                . '<StackPanel Name="FoldItems_' t '_' f '"' vis '>'
            span := StrSplit(spanStr, "-")
            if (IsInteger(span[1]) && IsInteger(span[2])) {
                loop span[2] - span[1] + 1 {
                    i := span[1] + A_Index - 1
                    xaml .= this._BuildItemRow(t, i)
                    this.RenderedItems[t][i] := true
                }
            }
            xaml .= '</StackPanel></StackPanel>'
            this.ui.Update(listName, "AddXamlItem", xaml)
        }
        ; 绑定须在 AddXamlItem 之后（控件已存在）
        ; 折叠态行隐藏且事件不可达：跳过 BindEvent（千条级折叠组省 ~9×N 次桥接往返），
        ; 展开折叠时由 OnFoldBtnClick 补绑（_Bind 清旧再挂，幂等）
        for f, spanStr in fi.IndexSpanArr {
            span := StrSplit(spanStr, "-")
            if (!IsInteger(span[1]) || !IsInteger(span[2]))
                continue
            if (fi.FoldStateArr[f])
                continue
            loop span[2] - span[1] + 1 {
                i := span[1] + A_Index - 1
                this._BindItemRow(t, i)
            }
        }
        this._BindFoldRows(t)
    }

    _BuildFoldTitleRow(t, f) {
        fi := MySoftData.TableInfo[t].FoldInfo
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        foldGlyph := fi.FoldStateArr[f] ? "&#xE76C;" : "&#xE70D;"
        xaml := '<Border ' ns ' CornerRadius="4" BorderThickness="1" BorderBrush="{DynamicResource InputStroke}" Background="{DynamicResource DropdownBg}" Margin="0,2,0,4" Padding="6,4">'
            . '<StackPanel>'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Name="FoldBtn_' t '_' f '" Width="24" Height="26" MinHeight="26" Cursor="Hand" Margin="0,0,6,0" Padding="0" Background="Transparent" BorderThickness="0">'
            . '<TextBlock Name="FoldGlyph_' t '_' f '" Text="' foldGlyph '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource TextMain}" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            . '</Button>'
            . '<TextBlock Text="' GetLang("备注：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Name="FoldRemark_' t '_' f '" Text="' this._XmlEsc(fi.RemarkArr[f]) '" Width="120" Height="26" MinHeight="26" Padding="4,0" Margin="2,0,8,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<TextBlock Text="' GetLang("前台:") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Name="FoldFront_' t '_' f '" Text="' this._XmlEsc(fi.FrontInfoArr[f]) '" Width="120" Height="26" MinHeight="26" Padding="4,0" Margin="2,0,8,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Name="FoldFrontBtn_' t '_' f '" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Name="FoldAddBtn_' t '_' f '" Content="' GetLang("新增宏") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Name="FoldPasteBtn_' t '_' f '" Content="' GetLang("粘贴宏") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Name="FoldAddModBtn_' t '_' f '" Content="' GetLang("新增模块") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Name="FoldDelModBtn_' t '_' f '" Content="' GetLang("删除模块") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<CheckBox Name="FoldForbid_' t '_' f '" Content="' GetLang("禁用") '" IsChecked="' (fi.ForbidStateArr[f] ? "True" : "False") '" VerticalAlignment="Center">'
            . '<CheckBox.Template><ControlTemplate TargetType="CheckBox">'
            . '<BulletDecorator Background="Transparent" Cursor="Hand">'
            . '<BulletDecorator.Bullet><Border x:Name="Border" Width="18" Height="18" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3"><Path x:Name="CheckMark" Visibility="Collapsed" Data="M 4 9 L 7 12 L 13 5" Stroke="{DynamicResource Accent}" StrokeThickness="2" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round"/></Border></BulletDecorator.Bullet>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" RecognizesAccessKey="True"/>'
            . '</BulletDecorator>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></CheckBox.Template></CheckBox>'
            . '</StackPanel>'
        if (isMenu || isUI) {
            xaml .= '<StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,0,0">'
                . '<TextBlock Text="' (isUI ? GetLang("面板触发键：") : GetLang("菜单触发键：")) '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
                . '<ComboBox Name="FoldTKType_' t '_' f '" Width="70" Height="26" MinHeight="26" Margin="2,0,10,0" SelectedIndex="' (fi.TKTypeArr[f] - 1) '" IsEnabled="' (isUI ? "False" : "True") '">'
                . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
                . '</ComboBox>'
                . '<TextBox Name="FoldTK_' t '_' f '" Text="' this._XmlEsc(fi.TKArr[f]) '" Width="100" Height="26" VerticalContentAlignment="Center" TextAlignment="Center"/>'
                . '<Button Name="FoldTKEdit_' t '_' f '" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Padding="8,0" Margin="6,0,0,0"/>'
                . '</StackPanel>'
        }
        xaml .= '</StackPanel></Border>'
        return xaml
    }

    _BuildItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        isMacro := CheckIsMacroTable(t)
        isNormal := CheckIsNormalTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isSubMacro := CheckIsSubMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"

        tkStr := isTiming ? GetLang("定时") : FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(tableItem.TKArr[i]))
        tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        loopStr := tableItem.LoopCountArr[i] == "-1" ? GetLang("无限") : tableItem.LoopCountArr[i]
        colorState := tableItem.ColorStateArr[i]
        colorHex := colorState == 1 ? "#2E7D32" : colorState == 2 ? "#F9A825" : colorState == 3 ? "#C62828" : "Transparent"
        tkTypeIdx := tableItem.TriggerTypeArr[i] - 1
        if (isUI)
            tkTypeIdx := 3

        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        xaml := '<Grid ' ns ' Margin="0,1,0,1">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="20"/><ColumnDefinition Width="26"/><ColumnDefinition Width="150"/>'
            . '<ColumnDefinition Width="100"/><ColumnDefinition Width="72"/><ColumnDefinition Width="82"/>'
            . '<ColumnDefinition Width="58"/><ColumnDefinition Width="58"/>'
            . '<ColumnDefinition Width="22"/><ColumnDefinition Width="22"/><ColumnDefinition Width="60"/>'
            . '<ColumnDefinition Width="48"/><ColumnDefinition Width="48"/>'
            . '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Name="Color_' t '_' i '" Width="12" Height="12" CornerRadius="6" Background="' colorHex '" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . '<TextBlock Grid.Column="1" Text="' i '." VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Grid.Column="2" Name="Remark_' t '_' i '" Text="' this._XmlEsc(tableItem.RemarkArr[i]) '" Height="26" MinHeight="26" Padding="4,0" Margin="0,0,6,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="3" Name="TKBtn_' t '_' i '" Content="' this._XmlEsc(tkStr) '" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="4,0" IsEnabled="' (isSubMacro ? "False" : "True") '"/>'
            . '<ComboBox Grid.Column="4" Name="TKType_' t '_' i '" Height="26" MinHeight="26" Margin="0,0,4,0" SelectedIndex="' tkTypeIdx '" IsEnabled="' (isNormal ? "True" : "False") '">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . '<ComboBox Grid.Column="5" Name="Loop_' t '_' i '" Height="26" MinHeight="26" Margin="0,0,4,0" IsEditable="True" IsEnabled="' (isMacro ? "True" : "False") '">'
            . '<ComboBoxItem Content="' GetLang("无限") '"/>'
            . '</ComboBox>'
            . '<Button Grid.Column="6" Name="Setting_' t '_' i '" Content="' GetLang("设置") '" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="6,0"/>'
            . '<Button Grid.Column="7" Name="Edit_' t '_' i '" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="6,0"/>'
            . '<Button Grid.Column="8" Name="Pre_' t '_' i '" Content="&#x2191;" Height="26" MinHeight="26" Width="20" Padding="0" Cursor="Hand" FontSize="14" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>'
            . '<Button Grid.Column="9" Name="Next_' t '_' i '" Content="&#x2193;" Height="26" MinHeight="26" Width="20" Padding="0" Cursor="Hand" FontSize="14" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>'
            . '<CheckBox Grid.Column="10" Name="Forbid_' t '_' i '" Content="' GetLang("禁用") '" IsChecked="' (tableItem.ForbidArr[i] ? "True" : "False") '" HorizontalAlignment="Left" Margin="2,0,0,0" VerticalAlignment="Center">'
            . '<CheckBox.Template><ControlTemplate TargetType="CheckBox">'
            . '<BulletDecorator Background="Transparent" Cursor="Hand">'
            . '<BulletDecorator.Bullet><Border x:Name="Border" Width="18" Height="18" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3"><Path x:Name="CheckMark" Visibility="Collapsed" Data="M 4 9 L 7 12 L 13 5" Stroke="{DynamicResource Accent}" StrokeThickness="2" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round"/></Border></BulletDecorator.Bullet>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" RecognizesAccessKey="True"/>'
            . '</BulletDecorator>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></CheckBox.Template></CheckBox>'
            . '<Button Grid.Column="11" Name="Copy_' t '_' i '" Content="' GetLang("复制") '" Height="26" MinHeight="26" Cursor="Hand" Padding="4,0"/>'
            . '<Button Grid.Column="12" Name="Del_' t '_' i '" Content="' GetLang("删除") '" Height="26" MinHeight="26" Cursor="Hand" Padding="4,0"/>'
            . '</Grid>'
        return xaml
    }

    _BindItemRow(t, i) {
        tableItem := MySoftData.TableInfo[t]
        isMacro := CheckIsMacroTable(t)
        isTriggerStr := CheckIsStringMacroTable(t)
        isTiming := CheckIsTimingMacroTable(t)
        isMenu := CheckIsMenuMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"

        editTK := isTriggerStr ? OnItemEditTriggerStr : OnItemEditTriggerKey
        editTK := isTiming ? OnItemEditTiming : editTK
        editTK := isMenu ? OnItemMenuMacroSettingClick : editTK
        editMacro := isMacro ? OnItemEditMacro : OnItemEditReplaceKey
        if (isUI)
            editTK := OnUIMacroSettingClick

        loopStr := tableItem.LoopCountArr[i] == "-1" ? GetLang("无限") : tableItem.LoopCountArr[i]
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)

        this._Bind("TKBtn_" t "_" i, "Click", editTK.Bind(tableItem, i))
        this._Bind("TKBtn_" t "_" i, "MouseRightButtonUp", OnItemCustomEditTriggerStr.Bind(tableItem, i))
        this._Bind("Setting_" t "_" i, "Click", OnItemEditMacroSetting.Bind(tableItem, i))
        this._Bind("Edit_" t "_" i, "Click", editMacro.Bind(tableItem, i))
        this._Bind("Pre_" t "_" i, "Click", OnItemMoveUp.Bind(tableItem, i))
        this._Bind("Next_" t "_" i, "Click", OnItemMoveDown.Bind(tableItem, i))
        this._Bind("Copy_" t "_" i, "Click", OnItemCopyMacroBtnClick.Bind(tableItem, i))
        this._Bind("Del_" t "_" i, "Click", OnItemDelMacroBtnClick.Bind(tableItem, i))
    }

    _BindFoldRows(t) {
        tableItem := MySoftData.TableInfo[t]
        fi := tableItem.FoldInfo
        for f, spanStr in fi.IndexSpanArr {
            this._Bind("FoldFrontBtn_" t "_" f, "Click", OnFoldFrontInfoEdit.Bind(tableItem, f))
            this._Bind("FoldAddBtn_" t "_" f, "Click", OnItemAddMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldPasteBtn_" t "_" f, "Click", OnItemPasteMacroBtnClick.Bind(tableItem, f))
            this._Bind("FoldAddModBtn_" t "_" f, "Click", OnItemAddFoldBtnClick.Bind(tableItem, f))
            this._Bind("FoldDelModBtn_" t "_" f, "Click", OnItemDelFoldBtnClick.Bind(tableItem, f))
            this._Bind("FoldBtn_" t "_" f, "Click", OnFoldBtnClick.Bind(tableItem, f))
            this._Bind("FoldTKEdit_" t "_" f, "Click", OnFlodTKEditClick.Bind(tableItem, f))
        }
    }

    ; 本地登记回调 + 让引擎挂上真实 WPF 事件（动态注入控件必须在 AddXamlItem 之后调用）
    ; 重建前先清同名旧回调，避免重复触发（同 ConfigMergeGui.PopulateListView 做法）
    _Bind(name, evt, cb) {
        if (this.ui.events.Has(name) && this.ui.events[name].Has(evt))
            this.ui.events[name][evt] := []
        this.ui.OnEvent(name, evt, cb)
        this.ui.Update(name, "BindEvent", evt)
    }

    UpdateItemColor(t, i) {
        if (this._useVirtual.Has(t)) {
            this._vl.UpdateColor(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        state := MySoftData.TableInfo[t].ColorStateArr[i]
        colorHex := state == 1 ? "#2E7D32" : state == 2 ? "#F9A825" : state == 3 ? "#C62828" : "Transparent"
        this.ui.Update("Color_" t "_" i, "Background", colorHex)
    }

    ; 增量刷新单行显示值：结构操作（上/下移）后只刷被交换两行，不整列表重建（滚动位置自然保留）。
    ; 槽位不变、事件绑 (tableItem, index) 闭包不重建，故仅更新各控件值即可。
    RefreshItemRow(t, i) {
        if (this._useVirtual.Has(t)) {
            this._vl.RefreshRow(t, i)
            return
        }
        if (!this._IsRendered(t, i))
            return
        tableItem := MySoftData.TableInfo[t]
        isTiming := CheckIsTimingMacroTable(t)
        isUI := GetTableSymbol(t) == "UI"
        tkStr := isTiming ? GetLang("定时") : FormatHotkeyDisplay(MySoftData.FormatJoyTriggerKey(tableItem.TKArr[i]))
        tkStr := tkStr == "" ? GetLang("编辑") : tkStr
        loopStr := tableItem.LoopCountArr[i] == "-1" ? GetLang("无限") : tableItem.LoopCountArr[i]
        tkTypeIdx := tableItem.TriggerTypeArr[i] - 1
        if (isUI)
            tkTypeIdx := 3
        this.ui.Update("Remark_" t "_" i, "Text", tableItem.RemarkArr[i])
        this.ui.Update("TKBtn_" t "_" i, "Content", tkStr)
        this.ui.Update("TKType_" t "_" i, "SelectedIndex", String(tkTypeIdx))
        this.ui.Update("Loop_" t "_" i, "Text", loopStr)
        this.ui.Update("Forbid_" t "_" i, "IsChecked", tableItem.ForbidArr[i] ? "True" : "False")
        this.UpdateItemColor(t, i)
    }

    _XmlEsc(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        s := StrReplace(s, "`r`n", "&#10;")
        s := StrReplace(s, "`n", "&#10;")
        s := StrReplace(s, "`r", "&#10;")
        return s
    }

    ; ============ Epic5 虚拟列表模板（注入 Window.Resources，VLTemplateSelector 按行类型取用） ============
    ; 复刻 _BuildItemRow / _BuildFoldTitleRow 列结构，字面值换 {Binding}，控件加 Tag 供容器级事件路由。
    ; 折叠头 TK 行文案固定「菜单触发键：」（模板共享，UI 表同文案，阶段C 如需区分再拆模板）。
    _BuildVListTemplates() {
        row := '<DataTemplate x:Key="RmtMacroRow">'
            . '<Grid Margin="0,1,0,1">'
            . '<Grid.ColumnDefinitions>'
            . '<ColumnDefinition Width="20"/><ColumnDefinition Width="26"/><ColumnDefinition Width="150"/>'
            . '<ColumnDefinition Width="100"/><ColumnDefinition Width="72"/><ColumnDefinition Width="82"/>'
            . '<ColumnDefinition Width="58"/><ColumnDefinition Width="58"/>'
            . '<ColumnDefinition Width="22"/><ColumnDefinition Width="22"/><ColumnDefinition Width="60"/>'
            . '<ColumnDefinition Width="48"/><ColumnDefinition Width="48"/>'
            . '</Grid.ColumnDefinitions>'
            . '<Border Grid.Column="0" Width="12" Height="12" CornerRadius="6" Background="{Binding ColorHex}" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
            . '<TextBlock Grid.Column="1" Text="{Binding SeqNo}" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Grid.Column="2" Tag="Remark" Text="{Binding Remark}" Height="26" MinHeight="26" Padding="4,0" Margin="0,0,6,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Grid.Column="3" Tag="TKBtn" Content="{Binding TKStr}" IsEnabled="{Binding TKBtnEnabled}" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="4,0"/>'
            . '<ComboBox Grid.Column="4" Tag="TKType" SelectedIndex="{Binding TKType}" IsEnabled="{Binding TKTypeEnabled}" Height="26" MinHeight="26" Margin="0,0,4,0">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . '<ComboBox Grid.Column="5" Tag="Loop" Text="{Binding LoopText}" IsEditable="True" IsEnabled="{Binding LoopEnabled}" Height="26" MinHeight="26" Margin="0,0,4,0">'
            . '<ComboBoxItem Content="' GetLang("无限") '"/>'
            . '</ComboBox>'
            . '<Button Grid.Column="6" Tag="Setting" Content="' GetLang("设置") '" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="6,0"/>'
            . '<Button Grid.Column="7" Tag="Edit" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Margin="0,0,4,0" Cursor="Hand" Padding="6,0"/>'
            . '<Button Grid.Column="8" Tag="Pre" Content="&#x2191;" Height="26" MinHeight="26" Width="20" Padding="0" Cursor="Hand" FontSize="14"/>'
            . '<Button Grid.Column="9" Tag="Next" Content="&#x2193;" Height="26" MinHeight="26" Width="20" Padding="0" Cursor="Hand" FontSize="14"/>'
            . this._VlCheckBox("Forbid", "10")
            . '<Button Grid.Column="11" Tag="Copy" Content="' GetLang("复制") '" Height="26" MinHeight="26" Cursor="Hand" Padding="4,0"/>'
            . '<Button Grid.Column="12" Tag="Del" Content="' GetLang("删除") '" Height="26" MinHeight="26" Cursor="Hand" Padding="4,0"/>'
            . '</Grid></DataTemplate>'
        fold := '<DataTemplate x:Key="RmtFoldHeader">'
            . '<Border BorderThickness="0,0,0,1" BorderBrush="{DynamicResource ControlBorder}" Background="{DynamicResource DropdownBg}" Margin="0,2,0,4" Padding="6,4">'
            . '<StackPanel>'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
            . '<Button Tag="FoldBtn" Width="24" Height="26" MinHeight="26" Cursor="Hand" Margin="0,0,6,0" Padding="0" Background="Transparent" BorderThickness="0" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource TextMain}">'
            . '<Button.Style><Style TargetType="Button">'
            . '<Setter Property="Content" Value="&#xE70D;"/>'
            . '<Style.Triggers><DataTrigger Binding="{Binding Folded}" Value="True"><Setter Property="Content" Value="&#xE76C;"/></DataTrigger></Style.Triggers>'
            . '</Style></Button.Style>'
            . '</Button>'
            . '<TextBlock Text="' GetLang("备注：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Tag="FoldRemark" Text="{Binding FoldRemark}" Width="120" Height="26" MinHeight="26" Padding="4,0" Margin="2,0,8,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<TextBlock Text="' GetLang("前台:") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<TextBox Tag="FoldFront" Text="{Binding FoldFront}" Width="120" Height="26" MinHeight="26" Padding="4,0" Margin="2,0,8,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<Button Tag="FoldFrontBtn" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Tag="FoldAdd" Content="' GetLang("新增宏") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Tag="FoldPaste" Content="' GetLang("粘贴宏") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Tag="FoldAddMod" Content="' GetLang("新增模块") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . '<Button Tag="FoldDelMod" Content="' GetLang("删除模块") '" Height="26" MinHeight="26" Padding="6,0" Margin="0,0,4,0"/>'
            . this._VlCheckBox("FoldForbid", "")
            . '</StackPanel>'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,0,0" Visibility="{Binding ShowTKRowVisibility}">'
            . '<TextBlock Text="' GetLang("菜单触发键：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}"/>'
            . '<ComboBox Tag="FoldTKType" SelectedIndex="{Binding FoldTKType}" IsEnabled="{Binding FoldTKTypeEnabled}" Width="70" Height="26" MinHeight="26" Margin="2,0,10,0">'
            . '<ComboBoxItem Content="' GetLang("按下") '"/><ComboBoxItem Content="' GetLang("松开") '"/><ComboBoxItem Content="' GetLang("松止") '"/><ComboBoxItem Content="' GetLang("开关") '"/><ComboBoxItem Content="' GetLang("长按") '"/><ComboBoxItem Content="' GetLang("双击") '"/>'
            . '</ComboBox>'
            . '<TextBox Tag="FoldTK" Text="{Binding FoldTK}" Width="100" Height="26" VerticalContentAlignment="Center" TextAlignment="Center"/>'
            . '<Button Tag="FoldTKEdit" Content="' GetLang("编辑") '" Height="26" MinHeight="26" Padding="8,0" Margin="6,0,0,0"/>'
            . '</StackPanel>'
            . '</StackPanel></Border></DataTemplate>'
        return row . fold
    }

    ; 行/折叠头共用 CheckBox（自定义勾选模板，Tag 兼作绑定路径）
    _VlCheckBox(tag, col) {
        colAttr := col == "" ? "" : ' Grid.Column="' col '"'
        return '<CheckBox' colAttr ' Tag="' tag '" Content="' GetLang("禁用") '" IsChecked="{Binding ' tag '}" HorizontalAlignment="Left" Margin="2,0,0,0" VerticalAlignment="Center">'
            . '<CheckBox.Template><ControlTemplate TargetType="CheckBox">'
            . '<BulletDecorator Background="Transparent" Cursor="Hand">'
            . '<BulletDecorator.Bullet><Border x:Name="Border" Width="18" Height="18" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3"><Path x:Name="CheckMark" Visibility="Collapsed" Data="M 4 9 L 7 12 L 13 5" Stroke="{DynamicResource Accent}" StrokeThickness="2" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round"/></Border></BulletDecorator.Bullet>'
            . '<ContentPresenter Margin="4,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" RecognizesAccessKey="True"/>'
            . '</BulletDecorator>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="Border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger>'
            . '</ControlTemplate.Triggers>'
            . '</ControlTemplate></CheckBox.Template></CheckBox>'
    }

    ; ============ 工具页 ============
    BuildToolTab() {
        p := "Panel_8"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)

        Add(this._LabelRow("变量监视器：", '<StackPanel Orientation="Horizontal"><Button Name="BtnOpenVarListen" Content="' GetLang("打开监视器") '" Height="26" MinHeight="26" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnFileCheck" Content="' GetLang("文件校验") '" Height="26" MinHeight="26" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnFileCheckHelp" Content="?" Height="26" MinHeight="26" Width="30" Padding="0" Cursor="Hand" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/></StackPanel>'))
        Add(this._LabelRow("鼠标信息：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtToolCheckKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolCheckHotkey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><CheckBox Name="ChkToolCheck" Content="' GetLang("开关") '" VerticalAlignment="Center" Margin="0,0,16,0"/><CheckBox Name="ChkAlwaysOnTop" Content="' GetLang("窗口置顶") '" VerticalAlignment="Center"/></StackPanel>'))
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add(this._TwoColRow(ns, "屏幕坐标：", "TxtMousePos", MainSoftData.PosStr, "窗口坐标：", "TxtWinPos", MainSoftData.WinPosStr))
        Add(this._TwoColRow(ns, "进程窗口标题：", "TxtProcessTile", MainSoftData.ProcessTile, "进程名：", "TxtProcessName", MainSoftData.ProcessName))
        Add(this._TwoColRow(ns, "进程窗口类：", "TxtProcessClass", MainSoftData.ProcessClass, "进程PID:", "TxtProcessPid", MainSoftData.ProcessPid))
        Add(this._TwoColRow(ns, "句柄Id:", "TxtProcessId", MainSoftData.ProcessId, "位置颜色：", "TxtColor", MainSoftData.Color))
        Add(this._LabelRow("指令录制：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtRecordKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><CheckBox Name="ChkToolCheckRecord" Content="' GetLang("开关") '" VerticalAlignment="Center"/></StackPanel>'))
        Add(this._LabelRow("图片文本提取：", '<StackPanel Orientation="Horizontal"><TextBlock Name="TxtTextFilterKey" Text="' FormatHotkeyDisplay(MainSoftData.ToolTextFilterHotKey) '" VerticalAlignment="Center" Opacity="0.6" Margin="0,0,8,0"/><Button Name="BtnTextShot" Content="' GetLang("截图提取文本") '" Height="26" MinHeight="26" Padding="10,0" Margin="0,0,8,0"/><Button Name="BtnTextImage" Content="' GetLang("从图片提取文本") '" Height="26" MinHeight="26" Padding="10,0"/></StackPanel>'))
        Add('<StackPanel ' ns ' Orientation="Horizontal" Margin="0,6,0,0"><TextBlock Text="' GetLang("录制的指令或提取的文本内容：") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/><Button Name="BtnClearToolText" Content="' GetLang("清空内容") '" Height="26" MinHeight="26" Padding="10,0" Margin="12,0,0,0"/></StackPanel>')
        Add('<TextBox ' ns ' Name="TxtToolText" Text="" Height="140" AcceptsReturn="True" VerticalContentAlignment="Top" TextWrapping="Wrap" Padding="6,4" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>')

        this._Bind("BtnOpenVarListen", "Click", (*) => MyVarListenGui.ShowGui())
        this._Bind("BtnFileCheck", "Click", (*) => SelfCheckMissingFiles())
        this._Bind("BtnFileCheckHelp", "Click", OnClickFileCheckHelpBtn)
        this._Bind("ChkToolCheck", "Click", OnToolCheckHotkey)
        this._Bind("ChkAlwaysOnTop", "Click", OnToolAlwaysOnTop)
        this._Bind("ChkToolCheckRecord", "Click", OnHotToolRecordMacro.Bind(false))
        this._Bind("BtnTextShot", "Click", OnToolTextFilterScreenShot)
        this._Bind("BtnTextImage", "Click", OnToolTextFilterSelectImage)
        this._Bind("BtnClearToolText", "Click", OnClearToolText)

        UIControls.ToolCheck := CtrlAdapter("ChkToolCheck", this.ui, "IsChecked")
        UIControls.AlwaysOnTop := CtrlAdapter("ChkAlwaysOnTop", this.ui, "IsChecked")
        UIControls.ToolCheckRecord := CtrlAdapter("ChkToolCheckRecord", this.ui, "IsChecked")
        UIControls.ToolText := CtrlAdapter("TxtToolText", this.ui, "Text")
        MainSoftData.ToolMousePosCtrl := CtrlAdapter("TxtMousePos", this.ui, "Text")
        MainSoftData.ToolMouseWinPosCtrl := CtrlAdapter("TxtWinPos", this.ui, "Text")
        MainSoftData.ToolProcessTileCtrl := CtrlAdapter("TxtProcessTile", this.ui, "Text")
        MainSoftData.ToolProcessNameCtrl := CtrlAdapter("TxtProcessName", this.ui, "Text")
        MainSoftData.ToolProcessClassCtrl := CtrlAdapter("TxtProcessClass", this.ui, "Text")
        MainSoftData.ToolProcessPidCtrl := CtrlAdapter("TxtProcessPid", this.ui, "Text")
        MainSoftData.ToolProcessIdCtrl := CtrlAdapter("TxtProcessId", this.ui, "Text")
        MainSoftData.ToolColorCtrl := CtrlAdapter("TxtColor", this.ui, "Text")

        this.ui.Update("ChkToolCheck", "IsChecked", MainSoftData.IsToolCheck ? "True" : "False")
        this.ui.Update("ChkToolCheckRecord", "IsChecked", MainSoftData.IsToolRecord ? "True" : "False")
        this.ui.Update("ChkAlwaysOnTop", "IsChecked", "False")
    }

    _LabelRow(label, controlXaml) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        if (label == "")
            return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">' controlXaml '</StackPanel>'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Margin="0,0,6,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . controlXaml
            . '</StackPanel>'
    }

    ; 两列行：label1+TextBox1 | label2+TextBox2，复刻旧布局「一行两列」
    _TwoColRow(ns, label1, name1, val1, label2, name2, val2) {
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,0,4">'
            . '<TextBlock Text="' this._XmlEsc(label1) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name1 '" Text="' this._XmlEsc(val1) '" Width="220" Height="26" MinHeight="26" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '<TextBlock Text="' this._XmlEsc(label2) '" Width="120" Margin="16,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name2 '" Text="' this._XmlEsc(val2) '" Width="220" Height="26" MinHeight="26" Padding="4,0" VerticalContentAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    ; ============ 设置页 ============
    BuildSettingTab() {
        p := "Panel_9"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

        Add('<TextBlock ' ns ' Text="' GetLang("数值选项") '" FontWeight="Bold" Margin="0,6,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._IntRow("点击时间浮动(%)：", "EditHoldFloat", MainSoftData.HoldFloat)
            . this._IntRow("每次间隔浮动(%)：", "EditPreIntervalFloat", MainSoftData.PreIntervalFloat)
            . this._IntRow("间隔指令浮动(%)：", "EditIntervalFloat", MainSoftData.IntervalFloat)
            . this._IntRow("坐标X浮动(px)：", "EditCoordXFloat", MainSoftData.CoordXFloat)
            . this._IntRow("坐标Y浮动(px)：", "EditCoordYFloat", MainSoftData.CoordYFloat)
            . this._IntRow("多线程数(-1~10)：", "EditMutiThreadNum", MainSoftData.MutiThreadNum
                , GetLang("设置若梦兔最大线程数量") "`n" GetLang("-1：动态多线程，线程闲置时回收（30秒），不足时创建新的线程")
                . "`n" GetLang("0：单线程") "`n" GetLang("n：固定线程为指定n（推荐3~5）")
                . "`n" GetLang("提示：动态多线程采用固定线程3+动态多线程池最大16"))
            . '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"><TextBlock Text="' GetLang("软件背景颜色：") '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/><TextBox Name="EditSoftBGColor" Text="' MainSoftData.SoftBGColor '" Width="100" Height="26" MinHeight="26" Padding="4,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/></StackPanel>'
            . '</WrapPanel>')

        Add('<TextBlock ' ns ' Text="' GetLang("开关选项") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._CheckRow("开机自启", "ChkBootStart", MainSoftData.IsBootStart)
            . this._CheckRow("管理员启动", "ChkAdminStart", MainSoftData.IsAdminStart
                , GetLang("开启后：软件会以管理员身份启动。部分功能（如后台键鼠、部分游戏按键模拟等）需要管理员权限才能生效。")
                . "`n" GetLang("若同时开启开机自启，自启时也会以管理员身份启动。")
                . "`n" GetLang("重要：请不要自行通过「右键若梦兔 → 属性 → 兼容性 → 以管理员身份运行此程序」绑定管理员权限，这样会导致「开机自启」选项失效。如需管理员权限，请使用本选项。"))
            . this._CheckRow("仅前台运行宏", "ChkForeground", MainSoftData.CheckForeground
                , GetLang("开启后：宏运行时会检查该项配置的前台窗口；若当前前台窗口不匹配，则终止该宏。")
                . "`n" GetLang("关闭后：不校验前台窗口，宏按原逻辑继续执行。")
                . "`n" GetLang("提示：需在对应宏项中配置「前台」信息后才会生效；未配置前台信息的宏不受此选项影响。"))
            . this._CheckRow("自动松开修饰键", "ChkAutoLoosen", MainSoftData.AutoLoosenModifier
                , GetLang("开启后：当触发键为「修饰键 + 普通键」（如 Ctrl + A）时，触发宏前会先松开修饰键，再执行宏逻辑。")
                . "`n" GetLang("这样可避免修饰键仍被按住，导致宏里发送的按键变成组合键（例如本意发 A，实际变成 Ctrl+A）。")
                . "`n" GetLang("关闭后：不自动松开修饰键，保持物理按键原样。")
                . "`n" GetLang("提示：触发键以 ~ 开头（穿透）时，不会自动松开修饰键。"))
            . this._CheckRow("连续触发", "ChkContinuous", MainSoftData.ContinuousTrigger
                , GetLang("开启后：按下、开关、长按类型在按住触发键期间可以连续触发。")
                . "`n" GetLang("关闭后：按下、开关、长按类型必须先松开触发键，才能再次触发。")
                . "`n" GetLang("提示：松开、松止、双击类型不受此选项影响。"))
            . this._CheckRow("无变量提醒", "ChkNoVariable", MainSoftData.NoVariableTip)
            . this._CheckRow("业务日志", "ChkBusinessLog", MainSoftData.BusinessLog
                , GetLang("开启后：记录宏运行流水到 Log\\Business.log（宏触发/每指令/宏结束）。")
                . "`n" GetLang("关闭后：不记录业务流水（默认）。")
                . "`n" GetLang("提示：业务日志可能产生大量内容，建议排查问题时开启。"))
            . this._CheckRow("模态子窗口", "ChkModalSubGui", MainSoftData.IsModalSubGui
                , GetLang("开启后：打开指令编辑等子窗口时，会禁用主窗口，必须先关闭子窗口才能继续操作主窗口。")
                . "`n" GetLang("关闭后：子窗口与主窗口可同时操作，方便对照主界面内容进行编辑。")
                . "`n" GetLang("提示：默认开启，一般建议保持开启，避免误操作主窗口导致编辑内容丢失。"))
            . this._CheckRow("分割线", "ChkSplitLine", MainSoftData.ShowSplitLine)
            . '</WrapPanel>')

        Add('<TextBlock ' ns ' Text="' GetLang("下拉框选项") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . this._ComboRow("语言/Lang：", "CmbLang", MainSoftData.LangArr, MainSoftData.Lang)
            . this._ComboRow(GetLang("首选编辑器："), "CmbPreferredEditor", GetLangArr(["逻辑树", "图形节点"]), MainSoftData.PreferredMacroEditor)
            . this._ComboRow(GetLang("截图方式："), "CmbScreenShot", GetLangArr(["微软截图", "RMT截图", "SC截图"]), MainSoftData.ScreenShotType)
            . this._ComboRow(GetLang("手柄映射："), "CmbTriggerJoyType", ["Xbox", "PS5"], MainSoftData.TriggerJoyType
                , GetLang("手柄映射说明"))
            . this._ComboRow(GetLang("宏手柄类型："), "CmbJoyType", ["Xbox", "PS5"], MainSoftData.JoyType
                , GetLang("宏手柄类型说明"))
            . this._ComboRow(GetLang("按下时按下："), "CmbKeyDownDown", GetLangArr(["自动松开", "忽略重复按下", "允许重复按下"]), MainSoftData.KeyDownDownType
                , GetLang("当宏按键已经处于按下状态，再次触发按下指令时特别处理")
                . "`n" GetLang("自动松开：再次按下前，先松开该按键（确保指令正常执行）")
                . "`n" GetLang("忽略重复按下：保持按键之前的状态，忽略后续的按下指令")
                . "`n" GetLang("允许重复按下：再次按下宏按键（罗技按键可能卡死）")
                . "`n" GetLang("Tip1：按下时再次按下，真实键盘无法触发这个行为，这个行为通常是无效的")
                . "`n" GetLang("Tip2：按下时再次按下，按键检测网站可能无法检测，但记事本中可以有效输出"))
            . this._ComboRow(GetLang("指令备注") "：", "CmbRemarkAuto", GetLangArr(["不生成", "自动生成", "覆盖生成"]), MainSoftData.RemarkAutoType)
            . this._ComboRow(GetLang("宏终止方式："), "CmbMacroStop", GetLangArr(["智能终止", "强制终止"]), MainSoftData.MacroStopType
                , GetLang("智能终止：优先以协作方式让宏自行退出，设 150ms 期限，逾期未退出则强制结束。")
                . "`n" GetLang("强制终止：直接结束线程并创建新线程，不等待宏自行退出。")
                . "`n" GetLang("提示：强制终止响应更快，但频繁结束、创建线程会消耗较多资源，建议保持智能终止。"))
            . '</WrapPanel>')

        Add('<TextBlock ' ns ' Text="' GetLang("功能选项") '" FontWeight="Bold" Margin="0,10,0,4"/>')
        Add('<WrapPanel ' ns ' Orientation="Horizontal">'
            . '<Button Name="BtnTheme" Content="' GetLang("主题") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnHotkey" Content="' GetLang("快捷键") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnToolRecord" Content="' GetLang("指令录制") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnLogCenter" Content="' GetLang("日志中心") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnLogSetting" Content="' GetLang("日志与错误") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnRightClickMenu" Content="' GetLang("右键菜单设置") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnMenuWheel" Content="' GetLang("轮盘") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<Button Name="BtnUIPanel" Content="' GetLang("界面浮窗") '" Height="28" MinHeight="28" Padding="14,0" Margin="0,4,12,4"/>'
            . '<CheckBox Name="ChkCMDTip" Content="' GetLang("指令显示") '" VerticalAlignment="Center" Margin="4,4,6,4"/>'
            . '<Button Name="BtnCMDTipSetting" Content="' GetLang("设置") '" Height="28" MinHeight="28" Padding="10,0" Margin="0,4,0,4"/>'
            . '</WrapPanel>')

        ; ---- 事件 ----
        this._Bind("EditHoldFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "HoldFloat"))
        this._Bind("EditPreIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "PreIntervalFloat"))
        this._Bind("EditIntervalFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "IntervalFloat"))
        this._Bind("EditCoordXFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordXFloat"))
        this._Bind("EditCoordYFloat", "LostFocus", ObjBindMethod(this, "OnIntEdit", "CoordYFloat"))
        this._Bind("EditMutiThreadNum", "LostFocus", ObjBindMethod(this, "OnIntEdit", "MutiThreadNum"))
        this._Bind("EditSoftBGColor", "LostFocus", ObjBindMethod(this, "OnTextEdit", "SoftBGColor"))
        this._Bind("ChkBootStart", "Click", OnBootStartChanged)
        this._Bind("ChkAdminStart", "Click", OnAdminStartChanged)
        this._Bind("ChkForeground", "Click", ObjBindMethod(this, "OnCheckEdit", "CheckForeground"))
        this._Bind("ChkAutoLoosen", "Click", ObjBindMethod(this, "OnCheckEdit", "AutoLoosenModifier"))
        this._Bind("ChkContinuous", "Click", ObjBindMethod(this, "OnCheckEdit", "ContinuousTrigger"))
        this._Bind("ChkNoVariable", "Click", ObjBindMethod(this, "OnCheckEdit", "NoVariableTip"))
        this._Bind("ChkBusinessLog", "Click", ObjBindMethod(this, "OnBusinessLogToggle"))
        this._Bind("ChkModalSubGui", "Click", ObjBindMethod(this, "OnCheckEdit", "IsModalSubGui"))
        this._Bind("ChkSplitLine", "Click", ObjBindMethod(this, "OnCheckEdit", "ShowSplitLine"))
        this._Bind("CmbLang", "SelectionChanged", ObjBindMethod(this, "OnComboText", "Lang"))
        this._Bind("CmbPreferredEditor", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "PreferredMacroEditor"))
        this._Bind("CmbScreenShot", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "ScreenShotType"))
        this._Bind("CmbTriggerJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "TriggerJoyType"))
        this._Bind("CmbJoyType", "SelectionChanged", ObjBindMethod(this, "OnComboText", "JoyType"))
        this._Bind("CmbKeyDownDown", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "KeyDownDownType"))
        this._Bind("CmbRemarkAuto", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "RemarkAutoType"))
        this._Bind("CmbMacroStop", "SelectionChanged", ObjBindMethod(this, "OnComboIndex", "MacroStopType"))
        this._Bind("BtnTheme", "Click", OnClickThemeSettingBtn)
        this._Bind("BtnHotkey", "Click", OnClickHotkeySettingBtn)
        this._Bind("BtnToolRecord", "Click", OnClickToolRecordSettingBtn)
        this._Bind("BtnLogCenter", "Click", (*) => LogCenterGui.ShowGui())
        this._Bind("BtnLogSetting", "Click", (*) => LogSettingGui.ShowGui())
        this._Bind("BtnRightClickMenu", "Click", (*) => RightClickMenuSettingGui().ShowGui())
        this._Bind("BtnMenuWheel", "Click", OnClickMenuWheelSettingBtn)
        this._Bind("BtnUIPanel", "Click", OnClickUIMacroPanelSettingBtn)
        this._Bind("ChkCMDTip", "Click", OnClickCMDTipToggle)
        this._Bind("BtnCMDTipSetting", "Click", (*) => CMDTipSettingGui.ShowGui())

        UIControls.CMDTip := CtrlAdapter("ChkCMDTip", this.ui, "IsChecked")
        this.ui.Update("ChkCMDTip", "IsChecked", MySoftData.CMDTip ? "True" : "False")
    }

    OnIntEdit(fieldName, state, ctrl, event) {
        v := Trim(this.ui.Query(ctrl))
        if (v != "" && IsInteger(v))
            MainSoftData.%fieldName% := Integer(v)
    }

    OnTextEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
    }

    OnCheckEdit(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl) == "True"
    }

    ; 业务日志开关：写 MainSoftData + 同步 LogUtil global + 持久化
    OnBusinessLogToggle(state, ctrl, event) {
        global RMTLogBusinessEnabled
        MainSoftData.BusinessLog := this.ui.Query(ctrl) == "True"
        RMTLogBusinessEnabled := MainSoftData.BusinessLog
        IniWrite(MainSoftData.BusinessLog, IniFile, IniSection, "BusinessLog")
    }

    OnComboText(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := this.ui.Query(ctrl)
    }

    OnComboIndex(fieldName, state, ctrl, event) {
        MainSoftData.%fieldName% := Integer(this.ui.Query(ctrl ">SelectedIndex")) + 1
    }

    _IntRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="120" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBox Name="' name '" Text="' val '" Width="100" Height="26" MinHeight="26" Padding="4,0" VerticalContentAlignment="Center" TextAlignment="Center" FontSize="11" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"/>'
            . '</StackPanel>'
    }

    _CheckRow(label, name, val, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<CheckBox Name="' name '" Content="' this._XmlEsc(label) '" IsChecked="' (val ? "True" : "False") '" VerticalAlignment="Center"/>'
            . '</StackPanel>'
    }

    _ComboRow(label, name, items, sel, tip := "") {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        selIdx := ""
        itemsXaml := ""
        for k, it in items {
            ; INI 读出的数值可能是字符串（如 "1"），需按整数匹配
            isSel := IsInteger(sel) ? (k == Integer(sel)) : (it == sel)
            if (isSel)
                selIdx := k - 1
            itemsXaml .= '<ComboBoxItem Content="' this._XmlEsc(it) '"/>'
        }
        selAttr := (selIdx == "") ? "" : ' SelectedIndex="' selIdx '"'
        tipAttr := tip == "" ? "" : ' ToolTip="' this._XmlEsc(tip) '"'
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,4,16,4"' tipAttr '>'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="80" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<ComboBox Name="' name '" Width="130" Height="26" MinHeight="26" VerticalContentAlignment="Center" FontSize="12" Foreground="{DynamicResource InputText}" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}" BorderThickness="1"' selAttr '>' itemsXaml '</ComboBox>'
            . '</StackPanel>'
    }

    ; ============ 帮助页 ============
    BuildHelpTab() {
        p := "Panel_10"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' GetLang("免责声明") '" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,8,0,4"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力") '" FontSize="10" HorizontalAlignment="Center" Opacity="0.7" Margin="0,0,0,8"/>')
        Add(this._Para('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'))
        Add(this._Para("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"))
        Add(this._Para("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"))
        Add(this._Para("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"))
        Add('<TextBlock ' ns ' Text="' GetLang("若不同意上述条款，请立即停止使用本软件。") '" Foreground="Red" HorizontalAlignment="Center" Margin="0,10,0,0"/>')

        Add(this._LinkRow(GetLang("更新视频合集："), "https://www.bilibili.com/video/BV1yR8x6xEBW", GetLang("版本更新视频，直播交流问答")))
        Add(this._LinkRow(GetLang("操作说明文档："), A_WorkingDir "\index.html", GetLang("快速上手，指令手册、常见问题、常见报错、更新日志等")))
        Add(this._LinkRow(GetLang("配置共享仓库："), "https://zclucas.github.io/RMT-Setting/", GetLang("案例学习、获取他人分享的宏配置（支持下载导入）")))
        Add(this._LinkRow(GetLang("国内开源网址："), "https://gitee.com/fateman/RMT", "https://gitee.com/fateman/RMT"))
        Add(this._LinkRow(GetLang("国外开源网址："), "https://github.com/zclucas/RMT", "https://github.com/zclucas/RMT"))
        Add(this._LabelRow(GetLang("软件检查更新："), '<TextBlock Text="' GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本") '" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        Add(this._LinkRow(GetLang("软件交流渠道："), "https://qm.qq.com/q/DgpDumEPzq", "QQ群（837661891）、QQ频道、GitHub 论坛、Discord"))
        Add(this._LabelRow(GetLang("软件反馈表格："), '<TextBlock Text="' GetLang("bug文档") '、' GetLang("需求文档") '、' GetLang("使用备注") '（仅交流群成员有编辑权限）" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        Add(this._LabelRow(GetLang("软件开源协议："), '<TextBlock Text="AGPL-3.0" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}"/>'))
        this._FlushLinks()
    }

    _Para(text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
        return '<TextBlock ' ns ' Text="' this._XmlEsc(GetLang(text)) '" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,3"/>'
    }

    _LinkRow(label, url, text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        this._linkCounter := this._linkCounter + 1
        name := "Link_" this._linkCounter
        this._linkQueue.Push({ name: name, url: url })
        return '<StackPanel ' ns ' Orientation="Horizontal" Margin="0,3,0,3">'
            . '<TextBlock Text="' this._XmlEsc(label) '" Width="130" VerticalAlignment="Center" Foreground="{DynamicResource TextMain}" FontSize="12"/>'
            . '<TextBlock Name="' name '" Text="' this._XmlEsc(text) '" TextDecorations="Underline" Foreground="#2D6CDF" Cursor="Hand" FontSize="12" TextWrapping="Wrap"/>'
            . '</StackPanel>'
    }

    OnLinkClick(url, state, ctrl, event) {
        Run(url)
    }

    ; ============ 打赏页 ============
    BuildRewardTab() {
        p := "Panel_11"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
        str := Format(GetLang("若梦兔（RMT）—— 这款完全免费的开源软件，始终陪在你身边。")) "`n"
            . Format(GetLang("至今已为您执行 {:} 次宏指令。"), countStr) "`n"
            . GetLang("诚邀本月打赏成为若梦兔的 “守护者”，一起让若梦兔走得更远。")
        weiXinImg := StrReplace(A_WorkingDir "\Images\Soft\WeiXin.png", "\", "/")
        zhiFuBaoImg := StrReplace(A_WorkingDir "\Images\Soft\ZhiFuBao.png", "\", "/")
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' this._XmlEsc(str) '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,4"/>')
        Add('<StackPanel ' ns ' Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">'
            . '<StackPanel Margin="0,0,40,0"><Image Source="' weiXinImg '" Width="180" Height="180"/><TextBlock Text="' GetLang("微信打赏") '" HorizontalAlignment="Center" Margin="0,6,0,0"/></StackPanel>'
            . '<StackPanel><Image Source="' zhiFuBaoImg '" Width="180" Height="180"/><TextBlock Text="' GetLang("支付宝打赏") '" HorizontalAlignment="Center" Margin="0,6,0,0"/></StackPanel>'
            . '</StackPanel>')
        Add('<TextBlock ' ns ' Text="' this._XmlEsc(GetLang("当然，如果你暂时不方便，分享给朋友也是很棒的支持~")) '`n' this._XmlEsc(GetLang("开发不易，感谢你的每一份温暖！")) '" FontSize="12" TextWrapping="Wrap" Margin="0,16,0,0"/>')
    }

    ; ============ 特别感谢页 ============
    BuildThankTab() {
        p := "Panel_12"
        Add := (x) => this.ui.Update(p, "AddXamlItem", x)
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        Add('<TextBlock ' ns ' Text="' GetLang("感谢以下开发者为项目付出的智慧与汗水（排名不分先后）：") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,8,0,4"/>')
        Add(this._ThankLinks(["https://github.com/GushuLily", "https://gitee.com/bogezzb", "https://github.com/yunkuangao", "https://github.com/boxstudy", "https://github.com/sovaedv776", "https://github.com/T8numen"], ["GushuLily", "张正波", "yun", "boxstudy", "sovaedv776", "T8numen"]))
        Add('<TextBlock ' ns ' Text="' GetLang("软件的开发离不开众多优秀开源项目的支持，特别感谢：") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,14,0,4"/>')
        Add(this._ThankLinks(["https://github.com/opencv/opencv", "https://github.com/thqby/ahk2_lib", "https://github.com/RapidAI/RapidOCR", "https://github.com/evilC/AHK-CvJoyInterface", "https://github.com/Chaoses-Ib/IbInputSimulator", "https://github.com/evilC/AHK-ViGEm-Bus", "https://github.com/CesarHlp1/AHK-ViGEm-Bus-v2.ahk", "https://github.com/xland/ScreenCapture", "https://github.com/owhs/ahk-xaml"], ["OpenCV", "ahk2_lib", "RapidOCR", "AHK-CvJoyInterface", "IbInputSimulator", "AHK-ViGEm-Bus", "AHK-ViGEm-Bus-v2", "ScreenCapture", "ahk-xaml"]))
        Add('<TextBlock ' ns ' Text="' GetLang("感谢以下群友在社区中的活跃参与和宝贵建议：（QQ昵称）") '" FontWeight="Bold" TextWrapping="Wrap" Margin="0,14,0,4"/>')
        Add('<TextBlock ' ns ' Text="AYu    万年置伞    别说*不下啦    仰望    话听    yun" FontSize="12" Margin="0,4,0,4"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("感谢所有打赏支持若梦兔的守护者，以及参与完善 Bug 和需求文档的朋友。") '" FontSize="12" TextWrapping="Wrap" Margin="0,14,0,0"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("感谢每一位陪伴我们走过这段旅程的粉丝和群友们！是你们的支持与信任，让这个软件从一个小小的想法，一步步成长为今天的样子。每一次的鼓励、每一条的建议，都是我们前进的动力。") '`n' GetLang("感谢你们不离不弃，与我们共同见证每一次的迭代与成长。") '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>')
        Add('<TextBlock ' ns ' Text="' GetLang("再次感谢所有关心、支持、帮助过这个项目的每一个人！") '`n' GetLang("因为有你，这个项目才变得更有意义。") '" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>')
        Add('<TextBlock ' ns ' Text="—— 若梦兔' GetLang("敬上") '" FontSize="12" HorizontalAlignment="Right" Margin="0,8,0,0"/>')
        this._FlushLinks()
    }

    _ThankLinks(urls, names) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        row := '<WrapPanel ' ns ' Margin="0,3,0,3">'
        for k, url in urls {
            this._linkCounter := this._linkCounter + 1
            name := "ThankLink_" this._linkCounter
            this._linkQueue.Push({ name: name, url: url })
            row .= '<TextBlock Name="' name '" Text="' this._XmlEsc(names[k]) '" TextDecorations="Underline" Foreground="#2D6CDF" Cursor="Hand" FontSize="12" Margin="0,0,18,0"/>'
        }
        row .= '</WrapPanel>'
        return row
    }

    _FlushLinks() {
        for item in this._linkQueue
            this._Bind(item.name, "MouseLeftButtonUp", ObjBindMethod(this, "OnLinkClick", item.url))
        this._linkQueue := []
    }
}

global MyMainWin := MainWin()
