#Requires AutoHotkey v2.0

; =====================================================================
; 输入按钮条 —— XAML 迁移版（复用主进程共享 daemon，与 CustomInputGui 同构）
; Type: 1 真/假  2 继续  3 继续&取消  4 继续/终止/暂停  5 选择  6 多选
; =====================================================================

class InputBtnXamlGui {
    __new() {
        this.ui := ""
        this.Gui := ""
        this._closed := true
        this.Type := 0
        this.Prompt := ""
        this.Options := ""
        this.DefaultValue := ""
        this.OptionArr := []
        this.TrueAction := ""
        this.FalseAction := ""
        this.ContinueAction := ""
        this.CancelAction := ""
        this.HideAction := ""
        this.PauseAction := ""
        this.TerminateAction := ""
        this.SelectAction := ""
        this.CheckHotKeyAction := this.CheckHotKey.Bind(this)
    }

    ShowGui(Type, prompt := "", options := "", defaultValue := "") {
        this.Type := Integer(Type)
        this.Prompt := prompt
        this.Options := options
        this.DefaultValue := defaultValue
        this.OptionArr := InputOptionArr(options)
        if (this.Type >= 5 && this.OptionArr.Length == 0)
            this.OptionArr := InputOptionArr(InputDefaultOptions())
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this._ApplyDefaults()
        SetTimer(this.CheckHotKeyAction, 30)
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _WinSize() {
        switch this.Type {
            case 1:
                return "Width=`"365`" Height=`"200`""
            case 4:
                return "Width=`"370`" Height=`"170`""
            case 5:
                return "Width=`"365`" Height=`"220`""
            case 6:
                return "Width=`"365`" Height=`"280`""
            default:
                return "Width=`"315`" Height=`"170`""
        }
    }

    _DialogTitle() {
        switch this.Type {
            case 1:
                return GetLang("输入-状态")
            case 5:
                return GetLang("输入-选择")
            case 6:
                return GetLang("输入-多选")
            case 2, 3, 4:
                return GetLang("等待确定")
            default:
                return GetLang("输入按钮")
        }
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this._DialogTitle()
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Grid").Grid_Row(1).Margin("10,8")
        body.Rows("Auto", "*")
        body.Add("TextBlock").Grid_Row(0).Name("PromptCon").Text(this.Prompt).TextWrapping("Wrap").Margin("0,0,0,8")
            .Visibility(this.Prompt != "" ? "Visible" : "Collapsed")

        content := body.Add("Grid").Grid_Row(1)
        switch this.Type {
            case 1:
                btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
                AddCmdOkBtn(btnRow, "BtnTrue", "0,0,50,0", GetLang("真值（1）")).Width(108)
                AddCmdOkBtn(btnRow, "BtnFalse", "", GetLang("假值（0）")).Width(108)
            case 2:
                btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
                AddCmdOkBtn(btnRow, "BtnContinue", "", GetLang("继续"))
            case 3:
                btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
                AddCmdOkBtn(btnRow, "BtnContinue", "0,0,50,0", GetLang("继续"))
                AddCmdOkBtn(btnRow, "BtnCancel", "", GetLang("取消"))
            case 4:
                btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
                AddCmdOkBtn(btnRow, "BtnContinue", "0,0,50,0", GetLang("继续"))
                AddCmdOkBtn(btnRow, "BtnTerminate", "0,0,50,0", GetLang("终止"))
                AddCmdOkBtn(btnRow, "BtnPause", "", GetLang("暂停"))
            case 5:
                col := content.Add("StackPanel").VerticalAlignment("Center").HorizontalAlignment("Center")
                col.Add("ComboBox").Name("ChoiceCombo").Width(180).Height(26).MinHeight(26).Margin("0,0,0,12").HorizontalAlignment("Center")
                okRow := col.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
                AddCmdOkBtn(okRow, "BtnSelect")
            case 6:
                col := content.Add("Grid")
                col.Rows("*", "48")
                sv := col.Add("ScrollViewer").Grid_Row(0).VerticalScrollBarVisibility("Auto")
                list := sv.Add("StackPanel").Name("MultiList").Margin("8,0")
                for i, opt in this.OptionArr
                    list.Add("CheckBox").Name("Opt" i).Content(opt).Margin("0,2")
                okRow := col.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
                AddCmdOkBtn(okRow, "BtnSelect")
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" ' this._WinSize() '')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        switch this.Type {
            case 1:
                this.ui.OnEvent("BtnTrue", "Click", ObjBindMethod(this, "OnTrueBtnClick"))
                this.ui.OnEvent("BtnFalse", "Click", ObjBindMethod(this, "OnFalseBtnClick"))
            case 2:
                this.ui.OnEvent("BtnContinue", "Click", ObjBindMethod(this, "OnContinueBtnClick"))
            case 3:
                this.ui.OnEvent("BtnContinue", "Click", ObjBindMethod(this, "OnContinueBtnClick"))
                this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelBtnClick"))
            case 4:
                this.ui.OnEvent("BtnContinue", "Click", ObjBindMethod(this, "OnContinueBtnClick"))
                this.ui.OnEvent("BtnTerminate", "Click", ObjBindMethod(this, "OnTerminateBtnClick"))
                this.ui.OnEvent("BtnPause", "Click", ObjBindMethod(this, "OnPauseBtnClick"))
            case 5, 6:
                this.ui.OnEvent("BtnSelect", "Click", ObjBindMethod(this, "OnSelectBtnClick"))
        }

        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _ApplyDefaults() {
        if (!IsObject(this.ui))
            return
        if (this.Type == 5) {
            this.ui.Update("ChoiceCombo", "ClearItems", "")
            sel := 0
            for i, opt in this.OptionArr {
                this.ui.Update("ChoiceCombo", "AddItem", opt)
                if (this.DefaultValue != "" && opt == this.DefaultValue)
                    sel := i - 1
            }
            this.ui.Update("ChoiceCombo", "SelectedIndex", String(sel))
        }
        else if (this.Type == 6 && this.DefaultValue != "") {
            picked := InputOptionArr(this.DefaultValue)
            for i, opt in this.OptionArr {
                on := false
                for p in picked {
                    if (p == opt) {
                        on := true
                        break
                    }
                }
                this.ui.Update("Opt" i, "IsChecked", on ? "True" : "False")
            }
        }
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.OnCancel()
        this.ui := ""
        this._closed := true
        SetTimer(this.CheckHotKeyAction, 0)
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
        SetTimer(this.CheckHotKeyAction, 0)
    }

    CheckHotKey() {
        if (GetKeyState("Enter", "P")) {
            switch this.Type {
                case 1: this.OnTrueBtnClick()
                case 2, 3, 4: this.OnContinueBtnClick()
                case 5, 6: this.OnSelectBtnClick()
            }
        }
        if (GetKeyState("Esc", "P"))
            this.OnCancelBtnClick()
    }

    OnTrueBtnClick(*) {
        this.OnTrue()
        this.OnHide()
        this._CloseWindow()
    }

    OnFalseBtnClick(*) {
        this.OnFalse()
        this.OnHide()
        this._CloseWindow()
    }

    OnContinueBtnClick(*) {
        this.OnContinue()
        this.OnHide()
        this._CloseWindow()
    }

    OnCancelBtnClick(*) {
        this.OnCancel()
        this.OnHide()
        this._CloseWindow()
    }

    OnTerminateBtnClick(*) {
        this._Fire("TerminateAction")
        this.OnHide()
        this._CloseWindow()
    }

    OnPauseBtnClick(*) {
        this._Fire("PauseAction")
        this.OnHide()
        this._CloseWindow()
    }

    OnSelectBtnClick(*) {
        val := ""
        if (this.Type == 5) {
            val := IsObject(this.ui) ? this.ui.Query("ChoiceCombo") : ""
        }
        else if (this.Type == 6) {
            picked := []
            for i, opt in this.OptionArr {
                if (IsObject(this.ui) && this.ui.Query("Opt" i) == "True")
                    picked.Push(opt)
            }
            val := ""
            for p in picked
                val .= (val != "" ? "," : "") p
        }
        if (this.SelectAction != "") {
            Action := this.SelectAction
            Action("sel:" val)
            this.SelectAction := ""
        }
        this.OnHide()
        this._CloseWindow()
    }

    OnCancelClick(state, ctrl, event) {
        this.OnCancel()
        this._CloseWindow()
    }

    _Fire(prop) {
        if (this.%prop% != "") {
            Action := this.%prop%
            Action()
            this.%prop% := ""
        }
    }

    OnTrue() {
        this._Fire("TrueAction")
    }

    OnFalse() {
        this._Fire("FalseAction")
    }

    OnContinue() {
        this._Fire("ContinueAction")
    }

    OnCancel() {
        this._Fire("CancelAction")
    }

    OnHide() {
        if (this.HideAction != "") {
            Action := this.HideAction
            Action()
            this.HideAction := ""
        }
        SetTimer(this.CheckHotKeyAction, 0)
    }
}
