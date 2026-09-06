#Requires AutoHotkey v2.0
#Include "XAML_Host.ahk"
#Include "XAML_Generator.ahk"

class XDialog {
    static Preload() {
        XAMLHost.Prewarm()
    }

    ; AHK v2：对象上的 HasOwnProp/HasProp 对缺失字段会误报，读字段才抛错。只以 try 读取为准。
    static Opt(options, name, default := "") {
        try return options.%name%
        catch
            return default
    }

    static Has(options, name) {
        try {
            dummy := options.%name%
            return true
        } catch {
            return false
        }
    }

    static Show(options) {
        ; --- CONFIGURATION ---
        title := XDialog.Opt(options, "Title", "Dialog")
        msg := XDialog.Opt(options, "Message", "")
        iconChar := XDialog.Opt(options, "Icon", "")
        iconColor := XDialog.Opt(options, "IconColor", "{DynamicResource TextMain}")
        iconFontSize := XDialog.Opt(options, "IconFontSize", 18)
        iconColW := XDialog.Opt(options, "IconColWidth", 40)
        detail := XDialog.Opt(options, "DetailText", "")
        detailRows := XDialog.Opt(options, "DetailRows", 4)
        inputText := XDialog.Opt(options, "InputText", "")
        hasProgress := XDialog.Opt(options, "Progress", false)
        buttons := XDialog.Opt(options, "Buttons", ["OK"])
        width := XDialog.Opt(options, "Width", 450)
        height := XDialog.Opt(options, "Height", "Auto")
        resizable := XDialog.Opt(options, "Resizable", false)
        modal := XDialog.Opt(options, "Modal", false)
        owner := XDialog.Opt(options, "Owner", 0)
        alwaysOnTop := XDialog.Opt(options, "AlwaysOnTop", false)
        waitForResponse := XDialog.Opt(options, "WaitForResponse", true)
        themeName := XDialog.Opt(options, "Theme", XAMLHost.LastTheme)
        iniPath := XDialog.Opt(options, "IniPath", (XAMLHost.LastThemeIni != "" ? XAMLHost.LastThemeIni : (FileExist("themes.ini") ? "themes.ini" : "../themes.ini")))
        soundFx := XDialog.Opt(options, "Sound", "")
        disableAltF4 := XDialog.Opt(options, "DisableAltF4", false)
        movable := XDialog.Opt(options, "Movable", true)
        showCloseBtn := XDialog.Opt(options, "ShowCloseBtn", true)
        darkenOwner := XDialog.Opt(options, "DarkenOwner", false)

        bgRes := "DropdownBg"

        ; --- BUILD LAYOUT ---
        main := XAML_Generator("Grid")
        dialogResources := ""
        if (XDialog.Has(options, "CustomBackground")) {
            fn := options.CustomBackground
            fn(main)
        } else {
            main.Background("Transparent")
        }
        if (XDialog.Has(options, "Resources")) {
            dialogResources .= "`n" options.Resources
        }
        main.Rows("30", "*", "Auto")
        if (XDialog.Has(options, "ContentFontSize"))
            main.TextElement_FontSize(options.ContentFontSize)
        else
            main.TextElement_FontSize(XAMLHost.FontSize())

        ; Titlebar (draggable)
        tb := main.Add("Grid").Grid_Row(0).Background("Transparent")
        if (movable) {
            tb.Name("DragArea")
        }
        
        titleTb := tb.Add("TextBlock").Text(title).FontSize(XDialog.Opt(options, "TitleFontSize", 12)).FontWeight("Bold").VerticalAlignment("Center").Margin("15,0,0,0")
        titleTb.Foreground(XDialog.Opt(options, "TitleForeground", "{DynamicResource TextMain}"))
        if (XDialog.Has(options, "TitleFontFamily")) {
            titleTb.FontFamily(options.TitleFontFamily)
        }
        if (XDialog.Has(options, "TitleFontWeight")) {
            titleTb.FontWeight(options.TitleFontWeight)
        }
        if (XDialog.Has(options, "TitleFontSize")) {
            titleTb.FontSize(options.TitleFontSize)
        }
        if (XDialog.Has(options, "TitleMargin")) {
            titleTb.Margin(options.TitleMargin)
        }

        if (showCloseBtn) {
            closeBtnName := XDialog.Opt(options, "CloseBtnName", "BtnClose")
            closeBtn := tb.Add("Button").Name(closeBtnName).WindowChrome_IsHitTestVisibleInChrome("True").HorizontalAlignment("Right").Background("Transparent").BorderThickness(0).Width(46).Height(30).MinHeight(30).Padding("0").Cursor("Hand").Foreground("{DynamicResource TitleBarForeground}")
            try closeBtn._Props["Width"] := options.CloseBtnWidth
            try closeBtn._Props["Height"] := options.CloseBtnHeight
            try closeBtn._Props["Margin"] := options.CloseBtnMargin
            try closeBtn._Props["VerticalAlignment"] := options.CloseBtnVerticalAlignment
            closeStyle := XDialog.Opt(options, "CloseBtnStyle", "")
            if (closeStyle != "")
                closeBtn.Style(closeStyle)
            else if (closeBtnName == "BtnDlgClose")
                closeBtn.Style("{StaticResource DlgCloseBtn}")
            else
                closeBtn.Style("{StaticResource TitleBarCloseButton}")
            closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        }

        ; Content Body
        body := main.Add("StackPanel").Grid_Row(1).Margin("20,10,20,20")

        ; Message & Icon row
        shortMsg := (detail == "" && inputText == "" && !hasProgress && StrLen(msg) <= 40 && !InStr(msg, "`n"))
        msgAlign := shortMsg ? "Center" : "Top"
        msgRow := body.Add("Grid").Margin("0,0,0,15")
        msgTb := msgRow.Add("TextBlock").Text(msg).TextWrapping("Wrap").VerticalAlignment(msgAlign).TextAlignment(shortMsg ? "Center" : "Left")
        if (iconChar != "") {
            msgRow.Cols(String(iconColW), "*")
            msgRow.Add("TextBlock").Text(iconChar).Foreground(iconColor).FontSize(iconFontSize).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").VerticalAlignment(msgAlign).HorizontalAlignment("Center").Margin(shortMsg ? "0" : "0,2,0,0").Grid_Column(0)
            msgTb.Grid_Column(1).VerticalAlignment(msgAlign)
            if (shortMsg)
                msgTb.HorizontalAlignment("Center")
        } else if (shortMsg) {
            msgTb.HorizontalAlignment("Center")
        }
        msgTb.Foreground(XDialog.Opt(options, "MessageForeground", "{DynamicResource TextMain}"))
        msgFont := XDialog.Opt(options, "MessageFontFamily", "")
        if (msgFont == "")
            msgFont := XDialog.Opt(options, "FontFamily", "")
        if (msgFont != "")
            msgTb.FontFamily(msgFont)
        titleFont := XDialog.Opt(options, "TitleFontFamily", "")
        if (titleFont == "")
            titleFont := XDialog.Opt(options, "FontFamily", "")
        if (titleFont != "")
            titleTb.FontFamily(titleFont)
        msgSize := XDialog.Opt(options, "MessageFontSize", "")
        if (msgSize != "")
            msgTb.FontSize(msgSize)

        ; Detail Textbox
        if (detail != "") {
            body.Add("TextBox").Name("DialogDetail").Text(detail).IsReadOnly("True").Foreground("{DynamicResource TextSub}").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).Padding("10").Margin("0,0,0,15").Height(detailRows * 20).TextWrapping("Wrap").VerticalScrollBarVisibility("Auto")
        }

        ; Input field
        if (inputText != "") {
            body.Add("TextBox").Name("DialogInput").Text("").Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource Accent}").BorderThickness(1).Padding("10").Margin("0,0,0,15").Tag(inputText)
        }

        ; Progress bars
        if (hasProgress) {
            body.Add("TextBlock").Name("DialogProgText1").Text("Processing...").Foreground("{DynamicResource TextMain}").Margin("0,0,0,5")
            body.Add("TextBlock").Name("DialogProgSub1").Text("Please wait...").Foreground("{DynamicResource TextSub}").FontSize(11).Margin("0,0,0,5")
            body.Add("ProgressBar").Name("DialogProg1").Value(0).Maximum(100).Height(6).Margin("0,0,0,20").Foreground("{DynamicResource Accent}").Background("{DynamicResource ControlBorder}").BorderThickness(0)

            body.Add("TextBlock").Name("DialogProgText2").Text("Overall Task").Foreground("{DynamicResource TextMain}").Margin("0,0,0,5")
            body.Add("TextBlock").Name("DialogProgSub2").Text("Step 1").Foreground("{DynamicResource TextSub}").FontSize(11).Margin("0,0,0,5")
            body.Add("ProgressBar").Name("DialogProg2").Value(0).Maximum(100).Height(6).Margin("0,0,0,15").Foreground("{DynamicResource TextSub}").Background("{DynamicResource ControlBorder}").BorderThickness(0)
        }

        ; Buttons Footer
        footerBg := XDialog.Opt(options, "FooterBackground", "{DynamicResource ControlBg}")
        footer := main.Add("Border").Grid_Row(2).Background(footerBg).Padding("15").CornerRadius("0,0,10,10")
        btnSp := footer.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")

        ; Inject default button styles if not already provided in resources
        if (!InStr(dialogResources, 'x:Key="DialogBtn"')) {
            dialogResources .= '<Style x:Key="DialogBtn" TargetType="Button"><Setter Property="Background" Value="#10FFFFFF"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#20FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style><Style x:Key="DialogPrimaryBtn" TargetType="Button"><Setter Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        }

        for index, btnText in buttons {
            isPrimary := (btnText == "OK" || btnText == "Confirm" || btnText == "Allow Execution" || btnText == "Yes" || btnText == "Save" || btnText == "Awesome" || btnText == "确定" || btnText == "是" || btnText == "确认")
            isCancel := (btnText == "Cancel" || btnText == "Close" || btnText == "Abort" || btnText == "取消" || btnText == "关闭")

            btnEl := btnSp.Add("Button").Name("Btn" index).Content(btnText).Width(XDialog.Opt(options, "ButtonWidth", 100)).Margin("6,0").Cursor("Hand")
            btnH := XDialog.Opt(options, "ButtonHeight", "")
            if (btnH != "") {
                btnEl.Height(btnH).MinHeight(btnH)
            } else {
                btnEl.Height(26).MinHeight(26)
            }

            uniformBtns := XDialog.Opt(options, "UniformButtons", false)
            if (uniformBtns || isPrimary) {
                if (uniformBtns)
                    btnEl.Style("{StaticResource DialogBtn}")
                else
                    btnEl.Style("{StaticResource DialogPrimaryBtn}")
                if (isPrimary)
                    btnEl.IsDefault("True")
                if (isCancel)
                    btnEl.IsCancel("True")
            } else {
                btnEl.Style("{StaticResource DialogBtn}")
                if (isCancel) {
                    btnEl.IsCancel("True")
                }
            }
        }

        try RmtDialog._Trace("XDialog.Show start wait=" waitForResponse " modal=" modal " owner=" owner " w=" width)
        exePath := ""
        if (IsSet(XAML_FORCE_DYNAMIC_COMPILE) && !XAML_FORCE_DYNAMIC_COMPILE && XDialog.Has(options, "Id")) {
            exePath := options.Id "_dialog.dll"
        }

        ui := ""
        overlayGui := ""
        ownerDisabled := false

        actualOwner := owner

        if (exePath != "" && FileExist(exePath)) {
            ui := XAMLHost("", exePath, actualOwner)
            ui.skipFontScale := XDialog.Opt(options, "SkipFontScale", false)
        } else {
            ; Use a lightweight template without the 75KB component library for speed
            captionH := movable ? "30" : "0"
            startupLoc := owner ? "CenterOwner" : "CenterScreen"
            dialogTemplate := '
            (
                <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                        Width="940" Height="700"
                        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
                        ShowInTaskbar="False"
                        WindowStartupLocation="%startupLoc%"
                        TextElement.Foreground="{DynamicResource TextMain}">
                    <Window.Resources>
                        <CornerRadius x:Key="WindowRadius">12</CornerRadius>
                        <CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>
                        %dialogRes%
                    </Window.Resources>
                    <WindowChrome.WindowChrome>
                        <WindowChrome GlassFrameThickness="0" ResizeBorderThickness="6" CaptionHeight="%captionH%" CornerRadius="{DynamicResource WindowRadius}" />
                    </WindowChrome.WindowChrome>
                
                    <Border Margin="15" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="{DynamicResource WindowRadius}" Background="{DynamicResource %bgRes%}" SnapsToDevicePixels="True">
                        <Border.Effect>
                            <DropShadowEffect BlurRadius="15" Direction="270" RenderingBias="Performance" ShadowDepth="2" Opacity="0.3" Color="Black" />
                        </Border.Effect>
                        %app%
                    </Border>
                </Window>
            )'
            dialogTemplate := StrReplace(dialogTemplate, "%startupLoc%", startupLoc)
            dialogTemplate := StrReplace(dialogTemplate, "%captionH%", captionH)
            dialogTemplate := StrReplace(dialogTemplate, "%bgRes%", bgRes)
            dialogTemplate := StrReplace(dialogTemplate, "%dialogRes%", dialogResources)
            ui := XAMLHost(StrReplace(dialogTemplate, "%app%", main.ToString()), exePath, actualOwner)
            ui.skipFontScale := XDialog.Opt(options, "SkipFontScale", false)
        }

        ; Replace some default xaml.ahk window stuff to match the dialog needs
        heightAttr := (height == "Auto") ? 'SizeToContent="Height"' : 'Height="' height '"'
        resizeAttr := resizable ? 'ResizeMode="CanResize"' : 'ResizeMode="NoResize"'

        ; Clean title and fetch default icon for the OS Window frame
        safeTitle := StrReplace(title, "&", "&amp;")
        safeTitle := StrReplace(safeTitle, "<", "&lt;")
        safeTitle := StrReplace(safeTitle, ">", "&gt;")
        safeTitle := StrReplace(safeTitle, '"', "&quot;")

        hIcon := ""
        try hIcon := LoadPicture("shell32.dll", "Icon26", &ImageType := 1)

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" Width="' (width + 30) '" ' heightAttr ' ' resizeAttr (alwaysOnTop ? ' Topmost="True"' : ''))
        dlgFont := XDialog.Opt(options, "FontFamily", "")
        if (dlgFont != "") {
            ui.xaml := StrReplace(ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' dlgFont '"')
        }

        resultObj := { Button: "", Input: "", Instance: ui }

        ; Sound
        if (soundFx != "") {
            SoundPlay(soundFx)
        }

        ; Callbacks
        ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => XDialog.OnDialogLoad(ui, actualOwner, modal, themeName, iniPath, buttons, resultObj, hIcon), 255)
        ui.OnEvent("Window", "Closing", (state, ctrl, event) => XDialog.OnDialogClose(ui, resultObj, owner, modal, overlayGui), 255)

        for index, btnText in buttons {
            ui.OnEvent("Btn" index, "Click", ObjBindMethod(XDialog, "OnButtonClick", ui, resultObj, btnText, owner, modal), 255)
        }
        if (showCloseBtn && XDialog.Opt(options, "CloseBtnName", "BtnClose") != "BtnClose") {
            ui.OnEvent(options.CloseBtnName, "Click", (state, ctrl, event) => ui.Update("Window", "Close", ""), 255)
        }

        if (inputText != "") {
            ui.Track("DialogInput")
        }

        if (IsSet(XamlWin))
            XamlWin.Open(ui, "", actualOwner)
        else
            ui.Show()
        try RmtDialog._Trace("XDialog.Show after ui.Show hwnd=" ui.wpfHwnd " id=" ui.id " daemon=" XAMLHost.daemonHwnd)

        if (waitForResponse) {
            waitStart := A_TickCount
            lastBeat := 0
            while (resultObj.Button == "" && (ui.wpfHwnd == 0 || WinExist("ahk_id " ui.wpfHwnd))) {
                if (ui.wpfHwnd && modal && owner && !ownerDisabled) {
                    try WinSetEnabled(0, "ahk_id " owner)
                    ownerDisabled := true
                    try RmtDialog._Trace("XDialog owner disabled hwnd=" ui.wpfHwnd)
                }
                elapsed := A_TickCount - waitStart
                if (elapsed - lastBeat >= 1000) {
                    lastBeat := elapsed
                    wx := 0, wy := 0, ww := 0, wh := 0
                    try {
                        if (ui.wpfHwnd)
                            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " ui.wpfHwnd)
                    }
                    try RmtDialog._Trace("XDialog wait elapsed=" elapsed " hwnd=" ui.wpfHwnd " exist=" (ui.wpfHwnd && WinExist("ahk_id " ui.wpfHwnd) ? 1 : 0) " pos=" wx "," wy " size=" ww "x" wh)
                }
                if (ui.wpfHwnd == 0 && A_TickCount - waitStart > 5000) {
                    try {
                        dir := A_ScriptDir "\Log"
                        if !DirExist(dir)
                            DirCreate(dir)
                        FileAppend(ui.xaml, dir "\XDialog.last.xaml", "UTF-8")
                    }
                    try RmtDialog._Trace("XDialog timeout hwnd=0 dumped XDialog.last.xaml len=" StrLen(ui.xaml))
                    throw Error("Dialog window failed to open")
                }
                Sleep(50)
            }
            if (resultObj.Button == "") {
                resultObj.Button := "Closed"
            }
            if (modal && owner) {
                try WinSetEnabled(1, "ahk_id " owner)
            }
            return resultObj
        } else {
            return resultObj
        }
    }

    static ApplyTheme(ui, themeName, iniPath) {
        if !FileExist(iniPath)
            return
        themeData := ""
        try themeData := IniRead(iniPath, themeName)
        Loop Parse, themeData, "`n", "`r" {
            parts := StrSplit(A_LoopField, "=", " `t", 2)
            if (parts.Length == 2) {
                key := parts[1]
                val := parts[2]
                if (key == "Window_DWM")
                    ui.Update("Window", "DWM", val)
                else if (InStr(key, "Resource_") == 1)
                    ui.Update("Resource", SubStr(key, 10), val)
            }
        }
    }

    static OnDialogLoad(ui, owner, modal, themeName, iniPath, buttons, resultObj, hIcon := "", state := "", ctrl := "", event := "") {
        try RmtDialog._Trace("OnDialogLoad hwnd=" ui.wpfHwnd " owner=" owner " theme=" themeName)
        if (owner) {
            ui.Update("Window", "NativeOwner", owner)
        }
        if (hIcon != "") {
            ui.Update("Window", "Icon", "HICON:" hIcon)
        }
        try {
            XDialog.ApplyTheme(ui, themeName, iniPath)
        } catch as e {
            try RmtDialog._Trace("ApplyTheme err=" e.Message)
        }
        if (IsSet(XamlWin))
            XamlWin.OnLoadTheme(ui)
        else {
            try ApplyXamlTheme(ui, themeName)
            catch as e {
                try RmtDialog._Trace("ApplyXamlTheme err=" e.Message)
            }
        }
    }

    static OnDialogClose(ui, resultObj, owner, modal, overlayGui, state := "", ctrl := "", event := "") {
        if (resultObj.Button == "") {
            resultObj.Button := "Closed"
        }

        if (overlayGui != "") {
            try overlayGui.Destroy()
        }

        if (owner) {
            if (modal) {
                WinSetEnabled(1, "ahk_id " owner)
            }
        }
    }

    static OnButtonClick(ui, resultObj, btnText, owner, modal, state, ctrl, event) {
        resultObj.Button := btnText
        if state.Has("DialogInput") {
            resultObj.Input := state["DialogInput"]
        }

        if (owner) {
            if (modal) {
                WinSetEnabled(1, "ahk_id " owner)
            }
        }

        ; Close the window
        ui.Update("Window", "Close", "")
    }
}