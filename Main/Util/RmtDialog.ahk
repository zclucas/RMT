#Requires AutoHotkey v2.0

; =============================================================================
; RMT 通用提示/确认弹窗
; 窗口骨架与主题配置、快捷键编辑一致：XAML_TEMPLATE + 标题栏 + BgColor 内容区。
; =============================================================================
class RmtDialog {
    ; 单按钮提示（确定）
    static Info(msg, title := "", owner := 0) {
        RmtDialog._Trace("Info enter msg=" RmtDialog._Clip(msg))
        try {
            RmtDialog._Show(String(msg), title != "" ? title : GetLang("提示"), [GetLang("确定")], Chr(0xE946), "{DynamicResource Accent}", owner)
        } catch as e {
            RmtDialog._Log("Info", e)
        }
    }

    ; 确定/取消，返回是否点了确定
    static Confirm(msg, title := "", owner := 0) {
        RmtDialog._Trace("Confirm enter msg=" RmtDialog._Clip(msg))
        try {
            btn := RmtDialog._Show(String(msg), title != "" ? title : GetLang("提示"), [GetLang("确定"), GetLang("取消")], Chr(0xE9CE), "{DynamicResource Accent}", owner)
            ok := (btn == GetLang("确定"))
            RmtDialog._Trace("Confirm result ok=" ok " btn=" btn)
            return ok
        } catch as e {
            RmtDialog._Log("Confirm", e)
            return false
        }
    }

    ; 多按钮选择（XAML 版 CustomMsgBox）。返回按钮序号（1 起）；点关闭/按 Esc → 0。
    ; 返回值语义与旧 CustomMsgBox 一致，方便调用处 1:1 替换。
    static Choose(msg, title := "", buttons := [], owner := 0) {
        RmtDialog._Trace("Choose enter msg=" RmtDialog._Clip(msg) " n=" buttons.Length)
        try {
            btn := RmtDialog._Show(String(msg), title != "" ? title : GetLang("提示"), buttons, Chr(0xE9CE), "{DynamicResource Accent}", owner)
            if (btn == "" || btn == "Closed")
                return 0
            loop buttons.Length {
                if (buttons[A_Index] == btn)
                    return A_Index
            }
            return 0
        } catch as e {
            RmtDialog._Log("Choose", e)
            return 0
        }
    }

    ; 只读正文右键：只换菜单外观（与 AI 助手同色/同结构），不改弹窗正文字号
    static _AttachReadonlyCtxMenu(el) {
        if (!IsObject(el))
            return
        ff := (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑"
        cm := el.Add("FrameworkElement.ContextMenu").Add("ContextMenu")
            .MinWidth("140").Placement("MousePoint").FontFamily(ff)
            .Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        cm.Add("MenuItem").Header(GetLang("复制")).SetMarkup("Command", "Copy")
        cm.Add("Separator")
        cm.Add("MenuItem").Header(GetLang("全选")).SetMarkup("Command", "SelectAll")
    }

    static _LinePx(line, fs) {
        px := 0.0
        loop parse line {
            if (Ord(A_LoopField) <= 127)
                px += fs * 0.55
            else
                px += fs
        }
        return px
    }

    ; 多行说明段落之间补空行，避免挤成一团；已有空行的保持原样
    static _LoosenLines(msg) {
        msg := String(msg)
        if (!InStr(msg, "`n") || InStr(msg, "`n`n"))
            return msg
        return StrReplace(msg, "`n", "`n`n")
    }

    ; 短句按最长行收窗宽，避免左右大块留白；超过 2 行走宽窗 + 可滚动文本框。
    ; 下限 360：单行提示也保持正常弹窗尺寸，不至于缩成一个小方块。
    static _MsgLayout(msg, fs := 15) {
        nl := 1
        longest := 0.0
        if (InStr(msg, "`n")) {
            nl := 0
            loop parse msg, "`n" {
                nl++
                w := RmtDialog._LinePx(A_LoopField, fs)
                if (w > longest)
                    longest := w
            }
        } else {
            longest := RmtDialog._LinePx(msg, fs)
        }
        ; 行数多或单行太长都走「宽窗 + 可滚动只读框」，避免窗口被撑得又长又窄
        tall := nl > 2 || longest > 480
        w := tall ? 520 : Min(420, Max(360, Round(longest + 56)))
        return { Tall: tall, WinW: w, Lines: nl }
    }

    static _Show(msg, title, buttons, iconChar, iconColor, owner := 0) {
        if (!owner)
            owner := XamlWin.ActiveOwner()
        try XAMLHost.EnsureDaemonHealthy()

        titleHeight := "30"
        fs := XAMLHost.FontSize()
        msg := RmtDialog._LoosenLines(msg)
        lay := RmtDialog._MsgLayout(msg, fs)
        winW := lay.WinW
        fontFamily := ""
        try {
            if (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
                fontFamily := MainSoftData.FontType
        }

        ; 按钮统一宽度（取最长按钮文字），按钮行总宽并入窗宽，
        ; 否则「覆盖导入 / 自增导入 / 取消导入」这种三按钮会被窗边裁掉两侧。
        btnW := 88
        loop buttons.Length
            btnW := Max(btnW, Round(RmtDialog._LinePx(buttons[A_Index], fs) + 36))
        gapX := (buttons.Length > 2) ? 18 : 52
        ; +56 = 内容区左右各 22 的边距 + 余量，保证按钮行不被窗口边缘裁切
        winW := Min(640, Max(winW, btnW * buttons.Length + gapX * Max(0, buttons.Length - 1) + 56))

        main := XAML_Generator("Grid").Name("RmtDialogRoot").Background("{DynamicResource BgColor}")
        if (fontFamily != "")
            main.TextElement_FontFamily(fontFamily)
        main.TextElement_FontSize(fs)
        main.Rows(titleHeight, "Auto")

        XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClosePanel", "DialogTitle", iconChar, iconColor)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        ; 正文区给一个下限高度，单行提示也不会扁成一条
        if (!lay.Tall)
            body.MinHeight("96")
        panel := body.Add("StackPanel").Margin(lay.Tall ? "14,14,14,14" : "22,20,22,18")

        if (!lay.Tall) {
            ; 短文案：整段居中，窗宽按最长行收紧
            msgTb := panel.Add("TextBlock").Text(msg).Foreground("{DynamicResource TextMain}").FontSize(fs)
                .HorizontalAlignment("Center").VerticalAlignment("Center")
                .TextAlignment("Center").TextWrapping("Wrap")
                .MaxWidth(winW - 44).Margin("0,4,0,0")
        } else {
            ; 长文案：边框包住只读文本，可框选复制、不可编辑
            roStyle := '<Style TargetType="TextBox"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Background="Transparent" Padding="0"/></ControlTemplate></Setter.Value></Setter></Style>'
            box := panel.Add("Border")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1.5").CornerRadius("4")
                .Background("{DynamicResource InputBg}").Padding("10,8,10,10")
            msgTb := box.Add("TextBox").Name("DlgMsgText").Text(msg).Foreground("{DynamicResource TextMain}").FontSize(fs)
                .Background("Transparent").BorderThickness("0").Padding("0")
                .IsReadOnly("True").IsReadOnlyCaretVisible("True").AcceptsReturn("True")
                .TextWrapping("Wrap").MaxHeight(440)
                .HorizontalScrollBarVisibility("Disabled").VerticalScrollBarVisibility("Auto")
                .CaretBrush("{DynamicResource TextMain}")
            msgTb.InjectResources(roStyle)
            RmtDialog._AttachReadonlyCtxMenu(msgTb)
        }
        if (fontFamily != "")
            msgTb.FontFamily(fontFamily)

        PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,18,0,2")
        okText := GetLang("确定")
        cancelText := GetLang("取消")
        loop buttons.Length {
            idx := A_Index
            btnText := buttons[idx]
            isLast := (idx == buttons.Length)
            ; 三个及以上按钮时，最后一个（通常是「取消…」）用次级配色，避免整排都是主色块
            isSecondary := (buttons.Length > 2) && isLast
            gap := isLast ? "0" : ("0,0," gapX ",0")
            btnEl := btnRow.Add("Button").Name("Btn" idx).Content(btnText)
                .Background(isSecondary ? "{DynamicResource ControlBg}" : "{DynamicResource ActionBg}")
                .Foreground(isSecondary ? "{DynamicResource TextMain}" : "{DynamicResource ActionText}")
                .FontWeight("Bold")
                .BorderBrush(isSecondary ? "{DynamicResource ControlBorder}" : "{DynamicResource ActionStroke}")
                .BorderThickness("1")
                .FontSize(fs).Cursor("Hand").Width(btnW).Height(34).Margin(gap)
            if (btnText == okText)
                btnEl.IsDefault("True")
            if (isSecondary || btnText == cancelText)
                btnEl.IsCancel("True")
            btnEl.InjectResources(PrimaryBtnStyle)
        }

        ; 落点写进 XAML：引擎揭盖时直接用 Left/Top，不再按「高 600」估，开窗就在正确位置。
        ; 尺寸仍由 SizeToContent 决定，estH 只参与算落点，估偏几像素不影响显示。
        lineH := Round(fs * 1.5)
        if (!lay.Tall)
            estH := 30 + 38 + 4 + lay.Lines * lineH + 20 + 34
        else
            estH := 30 + 28 + Min(lay.Lines * lineH, 440) + 21 + 20 + 34
        posAttr := XamlWin.PosAttr(winW, estH, owner)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
        ; 走与设置/编辑窗完全一致的管线（字号按 delta 缩放、标题栏补丁统一标题字号与关闭钮、视觉缩放），
        ; 因此不设 skipFontScale：正文声明基准字号→缩放到主题字号，标题由补丁强制为主题字号+2。
        safeTitle := RmtDialog._XmlEsc(title)
        ; 与其它小弹窗（XamlWin.Create）统一：不置顶，属主已保证压在主窗口上方；
        ; 高度随内容（SizeToContent=Height），宽度按正文/按钮行算好。
        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False"' posAttr ' Width="' winW '" SizeToContent="Height" Opacity="0"')
        ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        ; 窗口自身底色从 Transparent 换成标题栏色：Viewbox 等比缩放留边时不会露出白条
        winEnd := InStr(ui.xaml, ">")
        if (winEnd) {
            head := SubStr(ui.xaml, 1, winEnd)
            head := StrReplace(head, 'Background="Transparent"', 'Background="{DynamicResource TitleBarColor}"')
            ui.xaml := head SubStr(ui.xaml, winEnd + 1)
        }
        if (fontFamily != "")
            ui.xaml := StrReplace(ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' fontFamily '"')
        ui.xaml := StrReplace(ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        ui.xaml := StrReplace(ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        resultObj := { Button: "", Instance: ui }
        ownerDisabled := false

        ui.OnEvent("Window", "Closing", (state, ctrl, event) => RmtDialog._OnClosing(resultObj, owner))
        ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => RmtDialog._OnLoad(ui, owner))
        ui.OnEvent("BtnClosePanel", "Click", (state, ctrl, event) => RmtDialog._OnPick(ui, resultObj, "Closed", owner))
        loop buttons.Length {
            idx := A_Index
            btnText := buttons[idx]
            ui.OnEvent("Btn" idx, "Click", ObjBindMethod(RmtDialog, "_OnPick", ui, resultObj, btnText, owner))
        }

        RmtDialog._Trace("Show start owner=" owner " w=" winW " fs=" fs)
        if (!XamlWin.Open(ui, "", owner)) {
            try {
                dir := A_ScriptDir "\Log"
                if !DirExist(dir)
                    DirCreate(dir)
                FileAppend(ui.xaml, dir "\RmtDialog.last.xaml", "UTF-8")
            }
            throw Error("Dialog window failed to open")
        }
        ; 落点已在 XAML 里给好，揭盖即到位；这里只做一次兜底校验（偏差 >40px 才纠正，
        ; 正常情况不动，不会有可见的重新定位）
        XamlWin.NudgeIfOff(ui, owner)

        while (resultObj.Button == "" && WinExist("ahk_id " ui.wpfHwnd)) {
            if (ui.wpfHwnd && owner && !ownerDisabled) {
                try WinSetEnabled(0, "ahk_id " owner)
                ownerDisabled := true
            }
            Sleep(50)
        }
        if (resultObj.Button == "")
            resultObj.Button := "Closed"
        if (owner) {
            try WinSetEnabled(1, "ahk_id " owner)
            try WinActivate("ahk_id " owner)
        }
        RmtDialog._Trace("Show done btn=" resultObj.Button)
        return resultObj.Button
    }

    static _OnLoad(ui, owner, state := "", ctrl := "", event := "") {
        ; 落点已写进 XAML，这里不再挪窗口（挪了就是可见的跳动）
        XamlWin.OnLoadTheme(ui)
    }

    static _OnClosing(resultObj, owner, state := "", ctrl := "", event := "") {
        if (resultObj.Button == "")
            resultObj.Button := "Closed"
        if (owner) {
            try WinSetEnabled(1, "ahk_id " owner)
            try WinActivate("ahk_id " owner)
        }
    }

    static _OnPick(ui, resultObj, btnText, owner, state := "", ctrl := "", event := "") {
        resultObj.Button := btnText
        if (owner) {
            try WinSetEnabled(1, "ahk_id " owner)
            try WinActivate("ahk_id " owner)
        }
        try ui.Update("Window", "Close", "")
    }

    static _XmlEsc(s) {
        s := StrReplace(String(s), "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    static _LogPath() {
        dir := A_ScriptDir "\Log"
        if !DirExist(dir)
            DirCreate(dir)
        return dir "\RmtDialog.log"
    }

    static _Trace(msg) {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "." SubStr(A_TickCount, -2) " " msg "`n", RmtDialog._LogPath(), "UTF-8")
    }

    static _Clip(s, n := 80) {
        s := StrReplace(String(s), "`n", " ")
        return StrLen(s) > n ? SubStr(s, 1, n) "..." : s
    }

    static _Log(where, e) {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" where "] " e.Message "`n" e.Stack "`n`n", RmtDialog._LogPath(), "UTF-8")
    }
}
