#Requires AutoHotkey v2.0

; =============================================================================
; HelpDocWin —— 内嵌 WebView2 的帮助文档窗（自绘标题栏，非模态）
;
; 相比 msedge/chrome --app：窗口属于软件自身，标题栏、尺寸、位置、激活行为全可控；
; 不并入用户已开的浏览器进程，不受插件与「恢复上次会话」影响，任务栏不多留图标。
;
; 前提：系统装有 WebView2 运行时（Win10 1803+ 一般自带）。调用方先问
; HasWebView2Runtime()，不可用时退回 UIUtil.OpenHelpInAppWindow()。
;
; 用法：
;   HelpDocWin.Open()                        ; 首页
;   HelpDocWin.Open("#/docs/commands/key")   ; 直达某页（docOpen 用）
; =============================================================================

class HelpDocWin {
    ; 在线文档站根地址 —— 换域名只改这一处
    static OnlineBase := "https://yunkuangao.github.io/RMT-Docs/"

    static wvName := "HelpDocWebView"
    static ui := ""
    static isOpen := false
    static winW := 560
    static winH := 780
    static curHash := ""
    ; 关窗回调（可选）：Open 时传入，窗口关闭后调用，便于调用方清理状态
    static onClosed := ""

    ; 打开帮助窗；已开着则直接切到目标页，不重复开窗。
    ; pageHash 形如 "#/docs/commands/key"，留空打开首页。成功返回 true。
    static Open(pageHash := "", onClosed := "") {
        docPath := GetHelpDocPath()
        if (!FileExist(docPath))
            return false
        base := FileToFileUri(docPath)
        if (base = "")
            return false

        ; 已开着 → 直接导航过去，顺手激活
        if (HelpDocWin.isOpen && IsObject(HelpDocWin.ui)) {
            try {
                HelpDocWin.ui.Update(HelpDocWin.wvName, "Navigate", base pageHash)
                HelpDocWin.curHash := pageHash
                try WinActivate("ahk_id " HelpDocWin.ui.wpfHwnd)
                return true
            } catch {
                HelpDocWin.isOpen := false
            }
        }

        if (!HelpDocWin._Build(base pageHash))
            return false
        HelpDocWin.curHash := pageHash
        if (onClosed != "")
            HelpDocWin.onClosed := onClosed

        if (!XamlWin.Open(HelpDocWin.ui, "", HelpDocWin._OwnerHwnd())) {
            HelpDocWin.ui := ""
            HelpDocWin.isOpen := false
            return false
        }
        HelpDocWin.isOpen := true
        HelpDocWin._Place()
        return true
    }

    ; 当前页对应的在线地址（离线是 hash 路由 #/docs/x，在线是普通路径 docs/x）
    static OnlineUrl() {
        return HelpDocWin.OnlineBase RegExReplace(HelpDocWin.curHash, "^#/?", "")
    }

    static _OwnerHwnd() {
        try {
            if (IsSet(MainSoftData) && IsObject(MainSoftData) && MainSoftData.HasProp("MyGui")
                && IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.Hwnd)
                return MainSoftData.MyGui.Hwnd
        } catch {
        }
        return ""
    }

    static _Build(initUrl) {
        try {
            content := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
                .TextElement_FontSize(XAMLHost.FontSize())
            content.Rows("*", "38")

            ; --- 正文：内嵌 WebView2（初始页直接写在 Source 上，避免 Show 后再导航闪一下） ---
            host := content.Add("Grid").Grid_Row(0)
            host.SetProp("xmlns:wv2", "clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf")
            host.Add("wv2:WebView2").Name(HelpDocWin.wvName).SetProp("Source", initUrl)

            ; --- 页脚：离线说明 + 转在线文档 ---
            bar := content.Add("Border").Grid_Row(1)
                .Background("{DynamicResource TitleBarColor}")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,1,0,0")
            row := bar.Add("StackPanel").Orientation("Horizontal").Margin("12,0").VerticalAlignment("Center")
            row.Add("TextBlock").Text(GetLang("随软件发布的离线文档")).Foreground("{DynamicResource TextSub}")
                .VerticalAlignment("Center")
            row.Add("Button").Name("BtnOnlineDoc").Content(GetLang("打开在线文档"))
                .Margin("12,0,0,0").Height("26").MinHeight("26").Padding("12,0").Cursor("Hand")

            HelpDocWin.ui := XamlWin.Create(GetLang("帮助文档"), content, HelpDocWin.winW, HelpDocWin.winH)
            HelpDocWin.ui.OnEvent("BtnOnlineDoc", "Click", (*) => Run(HelpDocWin.OnlineUrl()))
            HelpDocWin.ui.OnEvent("Window", "Closing", HelpDocWin._OnClosing)
            return true
        } catch {
            ; 引擎没编进 WebView2 支持、或 WebView2 组件不可用时走到这里
            HelpDocWin.ui := ""
            return false
        }
    }

    static _OnClosing(*) {
        HelpDocWin.isOpen := false
        HelpDocWin.ui := ""
        if (HelpDocWin.onClosed != "") {
            cb := HelpDocWin.onClosed
            HelpDocWin.onClosed := ""
            try cb.Call()
        }
    }

    ; 贴主窗口右侧、与主窗口顶部对齐
    ; 只挪位置不改尺寸 —— 改尺寸会让 Viewbox 缩放内容，而 WebView2 是 HWND 宿主控件，
    ; 不跟随 WPF 变换，缩放后会错位
    static _Place() {
        ui := HelpDocWin.ui
        if (!IsObject(ui) || !ui.HasProp("wpfHwnd") || !ui.wpfHwnd)
            return
        hwnd := "ahk_id " ui.wpfHwnd
        owner := HelpDocWin._OwnerHwnd()
        if (owner = "")
            return

        mx := 0, my := 0, mw := 0, mh := 0
        try WinGetPos(&mx, &my, &mw, &mh, "ahk_id " owner)
        if (mw < 300 || mh < 300)
            return

        wx := 0, wy := 0, ww := 0, wh := 0
        try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        if (ww < 100 || wh < 100)
            return

        x := mx + mw + 8
        if (x + ww > A_ScreenWidth)
            x := (mx - ww - 8 >= 0) ? mx - ww - 8 : A_ScreenWidth - ww - 8
        if (x < 0)
            x := 0

        y := my
        if (y + wh > A_ScreenHeight)
            y := A_ScreenHeight - wh - 8
        if (y < 0)
            y := 0

        try WinMove(x, y, , , hwnd)
    }
}
