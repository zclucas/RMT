#Requires AutoHotkey v2.0
#Include "XAML_Host.ahk"
#Include "XAML_Generator.ahk"

class XDialog {
    static Preload() {
        XAMLHost.Prewarm()
    }

    static Show(options) {
        ; --- CONFIGURATION ---
        title := options.HasProp("Title") ? options.Title : "Dialog"
        msg := options.HasProp("Message") ? options.Message : ""
        iconChar := options.HasProp("Icon") ? options.Icon : ""
        iconColor := options.HasProp("IconColor") ? options.IconColor : "{DynamicResource TextMain}"
        detail := options.HasProp("DetailText") ? options.DetailText : ""
        detailRows := options.HasProp("DetailRows") ? options.DetailRows : 4
        inputText := options.HasProp("InputText") ? options.InputText : ""
        hasProgress := options.HasProp("Progress") ? options.Progress : false
        buttons := options.HasProp("Buttons") ? options.Buttons : ["OK"]
        width := options.HasProp("Width") ? options.Width : 450
        height := options.HasProp("Height") ? options.Height : "Auto"
        resizable := options.HasProp("Resizable") ? options.Resizable : false
        modal := options.HasProp("Modal") ? options.Modal : false
        owner := options.HasProp("Owner") ? options.Owner : 0
        alwaysOnTop := options.HasProp("AlwaysOnTop") ? options.AlwaysOnTop : false
        waitForResponse := options.HasProp("WaitForResponse") ? options.WaitForResponse : true
        themeName := options.HasProp("Theme") ? options.Theme : "Dark Mica (Win 11)"
        iniPath := options.HasProp("IniPath") ? options.IniPath : (FileExist("themes.ini") ? "themes.ini" : "../themes.ini")
        soundFx := options.HasProp("Sound") ? options.Sound : ""
        disableAltF4 := options.HasProp("DisableAltF4") ? options.DisableAltF4 : false
        movable := options.HasProp("Movable") ? options.Movable : true
        showCloseBtn := options.HasProp("ShowCloseBtn") ? options.ShowCloseBtn : true
        darkenOwner := options.HasProp("DarkenOwner") ? options.DarkenOwner : false

        bgRes := "DropdownBg"
        if FileExist(iniPath) {
            try {
                themeData := IniRead(iniPath, themeName)
                Loop Parse, themeData, "`n", "`r" {
                    parts := StrSplit(A_LoopField, "=", " `t", 2)
                    if (parts.Length == 2 && parts[1] == "Window_DWM") {
                        if (SubStr(parts[2], 1, 1) == "2" || SubStr(parts[2], 1, 1) == "3")
                            bgRes := "BgColor"
                        break
                    }
                }
            }
        }

        ; --- BUILD LAYOUT ---
        main := XAML_Generator("Grid").Background("{DynamicResource " bgRes "}")
        main.Rows("40", "*", "Auto")

        ; Titlebar (draggable)
        tb := main.Add("Grid").Grid_Row(0).Background("Transparent")
        if (movable) {
            tb.Name("DragArea")
        }
        tb.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontSize(12).VerticalAlignment("Center").Margin("15,0,0,0")

        if (showCloseBtn) {
            CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
            closeBtn := tb.Add("Button").Name("BtnClose").WindowChrome_IsHitTestVisibleInChrome("True").Width(45).HorizontalAlignment("Right").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0)
            closeBtn.InjectResources(CloseBtnTemplate)
            closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        }

        ; Content Body
        body := main.Add("StackPanel").Grid_Row(1).Margin("20,10,20,20")

        ; Message & Icon row
        msgRow := body.Add("Grid").Margin("0,0,0,15")
        if (iconChar != "") {
            msgRow.Cols("40", "*")
            msgRow.Add("TextBlock").Text(iconChar).Foreground(iconColor).FontSize(18).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").VerticalAlignment("Top").Margin("0,2,0,0").Grid_Column(0)
            msgRow.Add("TextBlock").Text(msg).Foreground("{DynamicResource TextMain}").TextWrapping("Wrap").VerticalAlignment("Top").Grid_Column(1)
        } else {
            msgRow.Add("TextBlock").Text(msg).Foreground("{DynamicResource TextMain}").TextWrapping("Wrap").VerticalAlignment("Top")
        }

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
        footer := main.Add("Border").Grid_Row(2).Background("{DynamicResource ControlBg}").Padding("15").CornerRadius("0,0,8,8")
        btnSp := footer.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")

        ; Inject beautiful Win11 rounded button styles directly into the dialog resources
        main.InjectResources('<Style x:Key="DialogBtn" TargetType="Button"><Setter Property="Background" Value="#10FFFFFF"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#20FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style><Style x:Key="DialogPrimaryBtn" TargetType="Button"><Setter Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="15,6"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        for index, btnText in buttons {
            isPrimary := (btnText == "OK" || btnText == "Confirm" || btnText == "Allow Execution" || btnText == "Yes" || btnText == "Save" || btnText == "Awesome")
            isCancel := (btnText == "Cancel" || btnText == "Close" || btnText == "Abort")

            btnEl := btnSp.Add("Button").Name("Btn" index).Content(btnText).Width(120).Margin("5,0").Cursor("Hand")

            if (isPrimary) {
                btnEl.Style("{StaticResource DialogPrimaryBtn}")
                btnEl.IsDefault("True")
            } else {
                btnEl.Style("{StaticResource DialogBtn}")
                if (isCancel) {
                    btnEl.IsCancel("True")
                }
            }
        }

        ; --- INIT LOGIC ---
        exePath := ""
        if (IsSet(XAML_FORCE_DYNAMIC_COMPILE) && !XAML_FORCE_DYNAMIC_COMPILE && options.HasProp("Id")) {
            exePath := options.Id "_dialog.dll"
        }

        ui := ""
        ; Modal logic
        overlayGui := ""
        if (modal && owner) {
            WinSetEnabled(0, "ahk_id " owner)

            if (darkenOwner) {
                try {
                    WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " owner)
                    overlayGui := Gui("-Caption +ToolWindow +Owner" owner)
                    overlayGui.BackColor := "Black"
                    WinSetTransparent(150, overlayGui.Hwnd)
                    overlayGui.Show("x" ox " y" oy " w" ow " h" oh " NoActivate")
                }
            }
        }

        actualOwner := overlayGui != "" ? overlayGui.Hwnd : owner

        if (exePath != "" && FileExist(exePath)) {
            ui := XAMLHost("", exePath, actualOwner)
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
                        TextElement.Foreground="{DynamicResource TextMain}" FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif">
                    
                    <WindowChrome.WindowChrome>
                        <WindowChrome GlassFrameThickness="-1" CaptionHeight="%captionH%" CornerRadius="{DynamicResource WindowRadius}" />
                    </WindowChrome.WindowChrome>
                
                    %app%
                </Window>
            )'
            dialogTemplate := StrReplace(dialogTemplate, "%startupLoc%", startupLoc)
            dialogTemplate := StrReplace(dialogTemplate, "%captionH%", captionH)
            ui := XAMLHost(StrReplace(dialogTemplate, "%app%", main.ToString()), exePath, actualOwner)
        }

        ; Replace some default xaml.ahk window stuff to match the dialog needs
        heightAttr := (height == "Auto") ? 'SizeToContent="Height"' : 'Height="' height '"'
        resizeAttr := resizable ? 'ResizeMode="CanResize"' : 'ResizeMode="NoResize"'

        ; Auto Focus Logic
        focusAttr := inputText != "" ? 'FocusManager.FocusedElement="{Binding ElementName=DialogInput}"' : 'FocusManager.FocusedElement="{Binding ElementName=Btn1}"'

        ; Clean title and fetch default icon for the OS Window frame
        safeTitle := StrReplace(title, "&", "&amp;")
        safeTitle := StrReplace(safeTitle, "<", "&lt;")
        safeTitle := StrReplace(safeTitle, ">", "&gt;")
        safeTitle := StrReplace(safeTitle, '"', "&quot;")

        hIcon := ""
        try hIcon := LoadPicture("shell32.dll", "Icon26", &ImageType := 1)

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" Width="' width '" ' heightAttr ' ' resizeAttr ' ' focusAttr (alwaysOnTop ? ' Topmost="True"' : ''))

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

        if (inputText != "") {
            ui.Track("DialogInput")
        }

        ui.Show()

        if (waitForResponse) {
            ; Wait for dialog to close
            while (resultObj.Button == "" && ProcessExist(ui.pid)) {
                Sleep(50)
            }
            if (resultObj.Button == "") {
                resultObj.Button := "Closed"
            }
            if (modal && owner) {
                WinSetEnabled(1, "ahk_id " owner)
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
        if (owner) {
            ui.Update("Window", "NativeOwner", owner)
        }
        if (hIcon != "") {
            ui.Update("Window", "Icon", "HICON:" hIcon)
        }
        XDialog.ApplyTheme(ui, themeName, iniPath)
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