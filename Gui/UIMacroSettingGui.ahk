#Requires AutoHotkey v2.0

; 界面宏图标配置：XAML，颜色跟随通用主题
class UIMacroSettingGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.closed := true
        this._instanceKey := ""
        this.SureFocusCon := ""
        this.CurrentMacroIndex := 0
        this.TableItem := ""
        this.OriginalIconPath := ""
        this.StoredIconPath := ""
        this._pathText := ""
        this._editBtnStyle := ""
    }

    ; 表身份 = TableItem 对象
    ShowGui(tableItem, macroIndex) {
        this.TableItem := tableItem
        this.CurrentMacroIndex := macroIndex
        this.StoredIconPath := this.GetFullIconPath(tableItem.Items[macroIndex].IcoPath)
        this.OriginalIconPath := this.StoredIconPath
        this._pathText := this.StoredIconPath

        key := "uiIco"
        if (UIMacroSettingGui.instances.Has(key)) {
            oldInst := UIMacroSettingGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            if (!oldInst.closed && XAMLHost.CanReuseWindow(hwnd)) {
                oldInst.TableItem := tableItem
                oldInst.CurrentMacroIndex := macroIndex
                oldInst.StoredIconPath := this.StoredIconPath
                oldInst.OriginalIconPath := this.OriginalIconPath
                oldInst._pathText := this._pathText
                oldInst._ApplyValuesToUI()
                try WinActivate("ahk_id " hwnd)
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            UIMacroSettingGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (UIMacroSettingGui._opening)
            return
        UIMacroSettingGui._opening := true
        try {
            this._instanceKey := key
            this._BuildAndShow()
            UIMacroSettingGui.instances[key] := this
        } finally {
            UIMacroSettingGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("界面宏配置 - 图标") " " this.CurrentMacroIndex
        titleHeight := "30"
        winW := 420
        winH := 200
        this._editBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight, "BtnClosePanel", "TitleText")

        ; 预览紧贴内容区右上角（无底色/边框/边距）；表单整体下沉 30px
        body := main.Add("Grid").Grid_Row(1)
        body.Add("Image").Name("IcoPreview").Width("64").Height("64")
            .HorizontalAlignment("Right").VerticalAlignment("Top")
            .Margin("0").SetProp("Stretch", "Uniform")

        content := body.Add("StackPanel").Margin("18,44,18,14")
        content.Add("TextBlock").Text(GetLang("图标文件：")).Foreground("{DynamicResource TextMain}").FontSize(13).Margin("0,0,0,8")

        pathRow := content.Add("Grid").Margin("0,0,0,18").Height(28)
        pathRow.Cols("*", "Auto")
        pathRow.Add("TextBox").Name("IcoPathCon").Text("").Height(28).MinHeight(28)
            .FontSize(12).FontFamily(MainSoftData.FontType)
            .VerticalAlignment("Center").VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Padding("6,0")
            .Grid_Column(0)
        browseBtn := pathRow.Add("Button").Name("BtnBrowse").Content(GetLang("选择"))
            .Width(72).Height(28).MinHeight(28).Margin("8,0,0,0").FontSize(12).Cursor("Hand")
            .VerticalAlignment("Center")
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .Grid_Column(1)
        browseBtn.InjectResources(this._editBtnStyle)

        btnRow := content.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
        okBtn := btnRow.Add("Button").Name("BtnConfirm").Content(GetLang("确定"))
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(80).Height(28).Margin("0,0,100,0")
        okBtn.InjectResources(this._editBtnStyle)
        cancelBtn := btnRow.Add("Button").Name("BtnCancel").Content(GetLang("取消"))
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(13).Cursor("Hand").Width(80).Height(28)
        cancelBtn.InjectResources(this._editBtnStyle)

        pos := GetCenterPosOnActiveMonitor(winW, winH)
        dipX := PhysToDip(pos.x)
        dipY := PhysToDip(pos.y)
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"',
            Format('Title="{}" ShowInTaskbar="False" Width="{}" Height="{}" Left="{}" Top="{}" Opacity="0"',
                title, winW, winH, dipX, dipY))
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnConfirm", "Click", ObjBindMethod(this, "OnSureClick"))
        this.ui.OnEvent("BtnBrowse", "Click", ObjBindMethod(this, "OnBrowseClick"))
        this.ui.Track("IcoPathCon")
        this.ui.OnEvent("IcoPathCon", "LostFocus", ObjBindMethod(this, "OnPathChanged"))
        this.ui.OnEvent("IcoPathCon", "KeyDown:Return", ObjBindMethod(this, "OnPathChanged"))

        this._ApplyValuesToUI()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        UIMacroSettingGui._opening := false
        if (this._instanceKey != "" && UIMacroSettingGui.instances.Has(this._instanceKey))
            UIMacroSettingGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    _ApplyValuesToUI() {
        if (!IsObject(this.ui) || this.closed)
            return
        title := GetLang("界面宏配置 - 图标") " " this.CurrentMacroIndex
        try this.ui.Update("TitleText", "Text", title)
        try this.ui.Update("Window", "Title", title)
        try this.ui.Update("IcoPathCon", "Text", this._pathText)
        this._RefreshPreview(this._pathText)
    }

    _RefreshPreview(path) {
        if (!IsObject(this.ui) || this.closed)
            return
        if (path != "" && FileExist(path)) {
            src := StrReplace(path, "\", "/")
            try this.ui.Update("IcoPreview", "Source", src)
            try this.ui.Update("IcoPreview", "Visibility", "Visible")
        } else {
            try this.ui.Update("IcoPreview", "Visibility", "Collapsed")
        }
    }

    OnPathChanged(state := unset, ctrl := unset, event := unset) {
        path := this._pathText
        if (IsSet(state) && IsObject(state) && state.Has("IcoPathCon"))
            path := state["IcoPathCon"]
        else if (IsObject(this.ui))
            path := this.ui.Query("IcoPathCon")
        this._pathText := path
        this.OriginalIconPath := path
        this._RefreshPreview(path)
    }

    OnBrowseClick(state := unset, ctrl := unset, event := unset) {
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon\"
        file := FileSelect(1, fullPath, GetLang("选择图标"), "Image Files (*.gif; *.png; *.jpg; *.jpeg)")
        if (file == "")
            return

        SplitPath file, &name, &dir, &ext, &name_no_ext, &drive
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        newPath := destDir "\" name
        if (file != newPath) {
            if (!FileExist(destDir))
                DirCreate(destDir)
            if (FileExist(newPath)) {
                fileName := this.GetUniqueFileName(file)
                newPath := destDir "\" fileName
            }
            FileCopy(file, newPath, 1)
            file := newPath
        }
        this.OriginalIconPath := file
        this._pathText := file
        try this.ui.Update("IcoPathCon", "Text", file)
        this._RefreshPreview(file)
    }

    GetFullIconPath(path) {
        if (path == "")
            return ""
        if (FileExist(path))
            return path
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon\" path
        if (FileExist(fullPath))
            return fullPath
        return ""
    }

    OnSureClick(state := unset, ctrl := unset, event := unset) {
        this.OnPathChanged(IsSet(state) ? state : unset)
        tableItem := this.TableItem
        idx := this.CurrentMacroIndex
        finalPath := ""
        if (this.OriginalIconPath != "" && FileExist(this.OriginalIconPath))
            finalPath := this.CopyIconToImagesFolder(this.OriginalIconPath)
        tableItem.Items[idx].IcoPath := finalPath
        this.Close()
        ; §18 UI宏图标即时持久化 + 广播（面板渲染订阅者重建）
        HotReloadPublish(tableItem.Index, idx)
    }

    CopyIconToImagesFolder(sourcePath) {
        iconsDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        if (!FileExist(iconsDir))
            DirCreate(iconsDir)
        SplitPath sourcePath, &name, &dir, &ext, &name_no_ext, &drive
        destPath := iconsDir "\" name
        if (sourcePath == destPath)
            return sourcePath
        if (FileExist(destPath)) {
            name := this.GetUniqueFileName(sourcePath)
            destPath := iconsDir "\" name
        }
        try FileCopy(sourcePath, destPath, 1)
        return destPath
    }

    GetUniqueFileName(sourcePath) {
        SplitPath sourcePath, , , &ext, &nameNoExt
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        if (!FileExist(destDir "\" nameNoExt "." ext))
            return nameNoExt "." ext
        counter := 1
        while (true) {
            newName := nameNoExt "_" counter "." ext
            if (!FileExist(destDir "\" newName))
                return newName
            counter++
        }
    }

    OnCancelClick(state := unset, ctrl := unset, event := unset) {
        this.Close()
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }
}
