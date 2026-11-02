#Requires AutoHotkey v2.0

; 界面宏模块浮窗位置。
; 相对坐标：浮窗锚点与目标区域的对应点重合，再加偏移。无目标窗口时目标区域是屏幕。
; 绝对坐标：浮窗左上角的屏幕坐标。
class UIMacroPosSettingGui {
    static instances := Map()
    static Anchors := ["左上", "左中", "左下", "中上", "中心", "中下", "右上", "右中", "右下"]

    __new() {
        this.ui := ""
        this.closed := true
        this.tableItem := ""
        this.foldIndex := 0
        this.OwnerHwnd := ""
    }

    static ShowGui(tableItem, foldIndex) {
        key := "pos"
        if (UIMacroPosSettingGui.instances.Has(key)) {
            old := UIMacroPosSettingGui.instances[key]
            try {
                if (!old.closed && IsObject(old.ui))
                    old.Close()
            }
            UIMacroPosSettingGui.instances.Delete(key)
        }
        inst := UIMacroPosSettingGui()
        inst.tableItem := tableItem
        inst.foldIndex := foldIndex
        if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.HasProp("wpfHwnd"))
            inst.OwnerHwnd := MyMainWin.ui.wpfHwnd
        UIMacroPosSettingGui.instances[key] := inst
        inst._BuildAndShow()
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("浮窗位置")
        titleHeight := "30"
        okStyle := FrontInfoGui._OkBtnHoverStyle()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")
        XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("StackPanel").Grid_Row(1).Margin("16,12,16,14")
        labelW := 96

        modeRow := body.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center")
        modeRow.Add("TextBlock").Text(GetLang("位置模式") "：").Width(labelW).TextAlignment("Right")
            .VerticalAlignment("Center").Margin("0,0,8,0")
        mode := modeRow.Add("ComboBox").Name("PosModeCon").Width(108).Height(26).MinHeight(26)
        mode.Add("ComboBoxItem").Content(GetLang("相对坐标"))
        mode.Add("ComboBoxItem").Content(GetLang("绝对坐标"))

        anchorBox := modeRow.Add("StackPanel").Name("AnchorBox").Orientation("Horizontal").VerticalAlignment("Center")
        anchorBox.Add("TextBlock").Text(GetLang("锚点") "：").Margin("16,0,8,0").VerticalAlignment("Center")
        anchor := anchorBox.Add("ComboBox").Name("AnchorCon").Width(88).Height(26).MinHeight(26)
        for label in UIMacroPosSettingGui.Anchors
            anchor.Add("ComboBoxItem").Content(GetLang(label))

        this._AddCoordRow(body, "OffsetRow", GetLang("偏移值") "：", "OffXCon", "OffYCon", labelW)
        this._AddCoordRow(body, "AbsRow", GetLang("目标点") "：", "PosXCon", "PosYCon", labelW)

        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,12,0,0")
        okBtn := btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(76).Height(28).MinHeight(28).Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
        okBtn.InjectResources(okStyle)

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="420" Height="172" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("PosModeCon", "SelectionChanged", ObjBindMethod(this, "OnModeChanged"))
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

        this._LoadFold()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _AddCoordRow(body, rowName, rowLabel, xName, yName, labelW) {
        row := body.Add("StackPanel").Name(rowName).Orientation("Horizontal").Margin("0,10,0,0").VerticalAlignment("Center")
        row.Add("TextBlock").Text(rowLabel).Width(labelW).TextAlignment("Right")
            .VerticalAlignment("Center").Margin("0,0,8,0")
        this._AddNumBox(row, xName)
        this._AddNumBox(row, yName, "8,0,0,0")
    }

    _AddNumBox(parent, name, margin := "0") {
        parent.Add("TextBox").Name(name).Width(64).Height(26).MinHeight(26).Margin(margin)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
    }

    _LoadFold() {
        fold := this._Fold()
        mode := 0
        anchor := 6
        offX := -50
        offY := 50
        posX := 0
        posY := 0
        if (fold) {
            mode := fold.HasProp("PosMode") && Integer(fold.PosMode) == 1 ? 1 : 0
            anchor := fold.HasProp("Anchor") ? Integer(fold.Anchor) : 6
            if (anchor < 0 || anchor > 8)
                anchor := 6
            offX := fold.HasProp("OffsetX") ? Integer(fold.OffsetX) : -50
            offY := fold.HasProp("OffsetY") ? Integer(fold.OffsetY) : 50
            posX := fold.HasProp("PosX") ? Integer(fold.PosX) : 0
            posY := fold.HasProp("PosY") ? Integer(fold.PosY) : 0
        }
        this.ui.Update("PosModeCon", "SelectedIndex", String(mode))
        this.ui.Update("AnchorCon", "SelectedIndex", String(anchor))
        this.ui.Update("OffXCon", "Text", String(offX))
        this.ui.Update("OffYCon", "Text", String(offY))
        this.ui.Update("PosXCon", "Text", String(posX))
        this.ui.Update("PosYCon", "Text", String(posY))
        this._SyncModeUi(mode)
    }

    _Fold() {
        if (!IsObject(this.tableItem) || this.foldIndex < 1 || this.foldIndex > this.tableItem.Folds.Length)
            return ""
        return this.tableItem.Folds[this.foldIndex]
    }

    _SelIndex(name) {
        v := IsObject(this.ui) ? this.ui.Query(name ">SelectedIndex") : ""
        return IsNumber(v) ? Integer(v) : 0
    }

    OnModeChanged(*) {
        this._SyncModeUi(this._SelIndex("PosModeCon"))
    }

    _SyncModeUi(mode) {
        if (!IsObject(this.ui))
            return
        relative := mode == 1 ? "Collapsed" : "Visible"
        absolute := mode == 1 ? "Visible" : "Collapsed"
        this.ui.Update("AnchorBox", "Visibility", relative)
        this.ui.Update("OffsetRow", "Visibility", relative)
        this.ui.Update("AbsRow", "Visibility", absolute)
    }

    _ReadInt(name, &out) {
        v := Trim(this.ui.Query(name))
        if (v == "") {
            out := 0
            return true
        }
        if (!RegExMatch(v, "^-?\d+$"))
            return false
        out := Integer(v)
        return true
    }

    OnSureBtnClick(*) {
        fold := this._Fold()
        if (!fold) {
            this.Close()
            return
        }
        offX := 0, offY := 0, posX := 0, posY := 0
        if (!this._ReadInt("OffXCon", &offX) || !this._ReadInt("OffYCon", &offY)
            || !this._ReadInt("PosXCon", &posX) || !this._ReadInt("PosYCon", &posY)) {
            RmtDialog.Info(GetLang("请输入整数"), GetLang("浮窗位置"), "Owner" this.Hwnd())
            return
        }
        anchor := this._SelIndex("AnchorCon")
        if (anchor < 0 || anchor > 8)
            anchor := 6
        fold.PosMode := this._SelIndex("PosModeCon") == 1 ? 1 : 0
        fold.Anchor := anchor
        fold.OffsetX := offX
        fold.OffsetY := offY
        fold.PosX := posX
        fold.PosY := posY
        try SaveTableItemInfo(this.tableItem)
        if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.ApplyFoldPosition(this.foldIndex)
        this.Close()
    }

    OnWindowLoad(*) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(*) {
        this._ReleaseOwner()
        this.closed := true
        this.ui := ""
        if (UIMacroPosSettingGui.instances.Has("pos") && UIMacroPosSettingGui.instances["pos"] == this)
            UIMacroPosSettingGui.instances.Delete("pos")
    }

    OnCancelClick(*) {
        this.Close()
    }

    Close() {
        this._ReleaseOwner()
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this.closed := true
        if (UIMacroPosSettingGui.instances.Has("pos") && UIMacroPosSettingGui.instances["pos"] == this)
            UIMacroPosSettingGui.instances.Delete("pos")
    }

    _ReleaseOwner() {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            this.OwnerHwnd := ""
        }
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }
}

OnFoldPosSetting(tableItem, foldIndex, *) {
    if (!IsObject(tableItem) || foldIndex < 1 || foldIndex > tableItem.Folds.Length)
        return
    UIMacroPosSettingGui.ShowGui(tableItem, foldIndex)
}
