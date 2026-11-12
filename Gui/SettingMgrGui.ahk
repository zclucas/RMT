#Requires AutoHotkey v2.0

class SettingMgrGui {
    static instances := Map()
    static _opening := false

    __new() {
        this.ui := 0
        this.closed := false
        this._instanceKey := ""
        this.SettingList := []
        this._selectedSetting := ""
        this._applyingUI := false
        this._btnStyle := ""
        this._revealed := false
    }

    ; 兼容旧入口 MySettingMgrGui.ShowGui()
    ShowGui() {
        SettingMgrGui.ShowGui()
    }

    static ShowGui() {
        key := "global"
        if (SettingMgrGui.instances.Has(key)) {
            oldInst := SettingMgrGui.instances[key]
            hwnd := (IsObject(oldInst.ui) && oldInst.ui.HasProp("wpfHwnd")) ? oldInst.ui.wpfHwnd : 0
            reuse := !oldInst.closed && XAMLHost.CanReuseWindow(hwnd)
            if (reuse) {
                try WinActivate("ahk_id " hwnd)
                oldInst.Refresh()
                return
            }
            try {
                if (!oldInst.closed && IsObject(oldInst.ui))
                    oldInst.Close()
            }
            SettingMgrGui.instances.Delete(key)
        }

        XAMLHost.EnsureDaemonHealthy()
        if (SettingMgrGui._opening)
            return
        SettingMgrGui._opening := true
        try {
            inst := SettingMgrGui()
            inst._instanceKey := key
            inst._BuildAndShow()
            SettingMgrGui.instances[key] := inst
        } catch {
        } finally {
            SettingMgrGui._opening := false
        }
    }

    _BuildAndShow() {
        this.closed := false
        title := GetLang("配置管理")
        titleHeight := "30"
        this._btnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
        scrollViewer := body.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        panel := scrollViewer.Add("StackPanel").Margin("16, 8, 16, 12")

        ; 顶部入口与当前配置操作按钮的宽度
        renameW := 28
        repairW := 28
        topBtnGap := 8
        replaceW := 168

        ; 组内操作行：与「配置选项 + 下拉」同宽，左右按钮分别贴齐两端
        optLabelW := 78
        comboW := 200
        comboMargin := 8
        operRowW := optLabelW + comboMargin + comboW
        operBtnW := 100

        ; 共享仓库和旧版配置升级并排显示
        rowTop := panel.Add("Grid").Margin("0,2,0,0")
        rowTop.Cols("*", "Auto")
        this._AddBtn(rowTop, "BtnOpenRepo", GetLang("共享仓库"), replaceW)
            .Grid_Column(0).HorizontalAlignment("Left")
            .ToolTip(GetLang("下载其他用户分享的配置，上传本地配置"))
        this._AddBtn(rowTop, "BtnReplace", GetLang("升级旧版配置"), replaceW)
            .Grid_Column(1).HorizontalAlignment("Right")
            .ToolTip(GetLang("迁移本地旧版配置，使其适配当前版本"))

        ; 当前配置 + 重命名 / 校准
        rowCur := panel.Add("Grid").Margin("0,10,0,0")
        rowCur.Cols("*", "Auto")
        curLeft := rowCur.Add("Grid").Grid_Column(0).VerticalAlignment("Center")
        curLeft.Cols("Auto", "*")
        curLeft.Add("TextBlock").Text(GetLang("当前配置："))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Grid_Column(0)
        ; 当前配置名：剩余宽度内 Viewbox 仅缩小不放大；颜色跟随主题主文字
        curNameBox := curLeft.Add("Viewbox").Grid_Column(1).Margin("4,0,8,0")
            .Stretch("Uniform").StretchDirection("DownOnly")
            .HorizontalAlignment("Left").VerticalAlignment("Center")
        curNameBox.Add("TextBlock").Name("CurSettingCon").Text("")
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").TextAlignment("Left").TextWrapping("NoWrap")
        curRight := rowCur.Add("StackPanel").Orientation("Horizontal").Grid_Column(1)
            .HorizontalAlignment("Right").VerticalAlignment("Center").Width(renameW + topBtnGap + repairW)
        this._AddBtn(curRight, "BtnRename", GetLang("重命名"), renameW).Margin("0,0," topBtnGap ",0")
        this._AddBtn(curRight, "BtnRepair", GetLang("配置校准"), repairW)

        ; 新增与导入
        addGroup := panel.Add("Border").Margin("0,12,0,0")
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("1.5").CornerRadius("4")
            .Background("Transparent")
        addInner := addGroup.Add("StackPanel").Orientation("Horizontal").Margin("12, 10, 12, 10").HorizontalAlignment("Center")
        this._AddBtn(addInner, "BtnAdd", GetLang("新增配置"), 100).Margin("0,0,10,0")
        this._AddBtn(addInner, "BtnUnpack", GetLang("导入配置"), 100).Margin("0,0,10,0")
        this._AddBtn(addInner, "BtnMerge", GetLang("合并导入"), 100)

        ; 配置操作
        operGroup := panel.Add("Border").Margin("0,10,0,0")
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("1.5").CornerRadius("4")
            .Background("Transparent")
        operInner := operGroup.Add("StackPanel").Margin("12, 8, 12, 10")

        rowOpt := operInner.Add("StackPanel").Orientation("Horizontal").Margin("0,2,0,0")
            .HorizontalAlignment("Center").Width(operRowW)
        rowOpt.Add("TextBlock").Text(GetLang("配置选项："))
            .Foreground("{DynamicResource TextMain}").FontSize(13)
            .VerticalAlignment("Center").Width(optLabelW)
        rowOpt.Add("ComboBox").Name("OperSettingCon").Width(comboW).Height(26).MinHeight(26)
            .Margin(comboMargin ",0,0,0")

        this._AddPairBtnRow(operInner, "BtnLoad", GetLang("加载配置"), "BtnPack", GetLang("导出配置"),
            operRowW, operBtnW, "0,12,0,0")
        this._AddPairBtnRow(operInner, "BtnCourse", GetLang("使用说明"), "BtnDel", GetLang("删除配置"),
            operRowW, operBtnW, "0,10,0,0")

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' title '" ShowInTaskbar="True" Width="440" Height="340"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.Track("OperSettingCon")
        this.ui.OnEvent("OperSettingCon", "SelectionChanged", ObjBindMethod(this, "OnOperSettingChanged"))

        this.ui.OnEvent("BtnReplace", "Click", ObjBindMethod(this, "OnReplaceBtnClick"))
        this.ui.OnEvent("BtnRename", "Click", ObjBindMethod(this, "OnReNameBtnClick"))
        this.ui.OnEvent("BtnRepair", "Click", ObjBindMethod(this, "OnRepairBtnClick"))
        this.ui.OnEvent("BtnAdd", "Click", ObjBindMethod(this, "OnAddBtnClick"))
        this.ui.OnEvent("BtnUnpack", "Click", ObjBindMethod(this, "OnUnpackBtnClick"))
        this.ui.OnEvent("BtnMerge", "Click", ObjBindMethod(this, "OnMergeBtnClick"))
        this.ui.OnEvent("BtnLoad", "Click", ObjBindMethod(this, "OnLoadBtnClick"))
        this.ui.OnEvent("BtnDel", "Click", ObjBindMethod(this, "OnDelBtnClick"))
        this.ui.OnEvent("BtnCourse", "Click", ObjBindMethod(this, "OnCourseBtnClick"))
        this.ui.OnEvent("BtnPack", "Click", ObjBindMethod(this, "OnPackBtnClick"))
        this.ui.OnEvent("BtnOpenRepo", "Click", ObjBindMethod(this, "OnOpenRMTSettingBtnClick"))

        this._revealed := false
        ; Show 前入队配置：LoadedHwnd 时引擎先 flush _updateQueue 再调 OnWindowLoad，首帧已有文案
        this.Refresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this.closed := true
    }

    _AddBtn(parent, name, content, width) {
        icons := Map("BtnOpenRepo", 0xE753, "BtnReplace", 0xE898,
            "BtnRename", 0xE8AC, "BtnRepair", 0xE90F,
            "BtnAdd", 0xE710, "BtnUnpack", 0xE74B, "BtnMerge", 0xE8EA,
            "BtnLoad", 0xE8E5, "BtnPack", 0xE8B6,
            "BtnCourse", 0xE8A5, "BtnDel", 0xE74D)
        btn := parent.Add("Button").Name(name)
            .Background("{DynamicResource EditBg}").Foreground("{DynamicResource EditText}")
            .BorderBrush("{DynamicResource EditStroke}").BorderThickness("1")
            .FontSize(12).Cursor("Hand").Width(width).Height(28)
        btnStyle := this._btnStyle
        if (name == "BtnDel") {
            btn.Background("#C42B1C").Foreground("#FFFFFF").BorderBrush("#C42B1C")
            btnStyle := StrReplace(btnStyle, "{DynamicResource EditHoverBg}", "#A4262C")
            btnStyle := StrReplace(btnStyle, "{DynamicResource EditHoverStroke}", "#A4262C")
        }
        btn.InjectResources(btnStyle)
        iconOnly := (name == "BtnRename" || name == "BtnRepair")
        if (iconOnly)
            btn.ToolTip(content).SetProp("AutomationProperties.Name", content)
        contentPanel := btn.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center")
        contentPanel.Add("TextBlock").Text(Chr(icons[name]))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .Margin(iconOnly ? "0" : "0,0,6,0").VerticalAlignment("Center")
        if (!iconOnly)
            contentPanel.Add("TextBlock").Text(content).VerticalAlignment("Center")
        return btn
    }

    ; 左右两端贴齐：左按钮对齐行起点，右按钮对齐行终点（与配置选项行同宽）
    _AddPairBtnRow(parent, leftName, leftText, rightName, rightText, rowW, btnW, margin) {
        row := parent.Add("Grid").Margin(margin).HorizontalAlignment("Center").Width(rowW)
        row.Cols("*", "*")
        this._AddBtn(row, leftName, leftText, btnW)
            .Grid_Column(0).HorizontalAlignment("Left")
        this._AddBtn(row, rightName, rightText, btnW)
            .Grid_Column(1).HorizontalAlignment("Right")
        return row
    }

    OnWindowClosing(state, ctrl, event) {
        this.closed := true
        this._revealed := true   ; 关闭中不再 fallback reveal
        SettingMgrGui._opening := false
        if (this._instanceKey != "" && SettingMgrGui.instances.Has(this._instanceKey))
            SettingMgrGui.instances.Delete(this._instanceKey)
        this.ui := ""
        try {
            if (!XAMLHost.IsDaemonAlive())
                XAMLHost.ResetDaemon()
        }
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnCancelClick(state, ctrl, event) {
        this.ui.Update("Window", "Close", "")
    }

    Close() {
        this.closed := true
        if IsObject(this.ui) {
            try this.ui.Update("Window", "Close", "")
            this.ui := ""
        }
    }

    Refresh() {
        this.SettingList := StrSplit(MainSoftData.SettingArrStr, "π")
        this._selectedSetting := MySoftData.CurSettingName
        if (!IsObject(this.ui))
            return

        this._applyingUI := true
        try {
            this.ui.Update("CurSettingCon", "Text", MySoftData.CurSettingName)
            this.ui.Update("OperSettingCon", "ClearItems", "")
            selIdx := 0
            ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
            for i, name in this.SettingList {
                this.ui.Update("OperSettingCon", "AddXamlItem",
                    '<ComboBoxItem ' ns ' Content="' this._XmlEsc(name) '"/>')
                if (name == MySoftData.CurSettingName)
                    selIdx := i - 1
            }
            if (this.SettingList.Length > 0)
                this.ui.Update("OperSettingCon", "SelectedIndex", String(selIdx))
        } finally {
            this._applyingUI := false
        }
    }

    _XmlEsc(s) => EscapeXamlXml(s)

    OnOperSettingChanged(state, ctrl, event) {
        if (this._applyingUI)
            return
        this._selectedSetting := this._GetSelectedSetting(state)
    }

    _GetSelectedSetting(state := unset) {
        name := this._selectedSetting != "" ? this._selectedSetting : MySoftData.CurSettingName
        if (IsSet(state) && IsObject(state) && state.Has("OperSettingCon"))
            name := state["OperSettingCon"]
        if (Compat_IsSettingName(name)) {
            for item in this.SettingList {
                if (item = name)
                    return item
            }
        }
        return ""
    }

    _RequireSelectedSetting(state) {
        name := this._GetSelectedSetting(state)
        if (name == "")
            RmtDialog.Info(GetLang("请从列表中选择已有配置"), GetLang("提示"), this.ui.wpfHwnd)
        return name
    }

    OnMergeBtnClick(state, ctrl, event) {
        ConfigMergeGui.ShowGui()
    }

    OnReNameBtnClick(state, ctrl, event) {
        newFileName := RmtDialog.Input(GetLang("请输入新的配置名："), GetLang("重命名"), "")
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild)
            return false

        NewSettingArrStr := ""
        for index, settingName in this.SettingList {
            value := MySoftData.CurSettingName == settingName ? newFileName.Value : settingName
            NewSettingArrStr .= value "π"
        }

        try {
            RmtProgress.Run(GetLang("重命名"), GetLang("正在复制配置文件")
                , (*) => Compat_RenameProfile(A_WorkingDir, MySoftData.CurSettingName, newFileName.Value
                    , ObjBindMethod(this, "_SelectProfileForReload", newFileName.Value, RTrim(NewSettingArrStr, "π")))
                , this.ui.wpfHwnd)
        } catch as e {
            RmtDialog.Info(e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        RmtDialog.Info(GetLang("重命名成功"), GetLang("提示"), this.ui.wpfHwnd)
        SafeReload()
    }

    OnReplaceBtnClick(state, ctrl, event) {
        tipStr := Format("{}`n{}", GetLang("将清空当前软件的所有配置，并把所选文件中的配置迁移导入本软件。"), GetLang(
            "为了避免数据丢失，自动备份当前所有配置保存到软件下SettingOld中。"))
        RmtDialog.Info(tipStr, GetLang("提示"), this.ui.wpfHwnd)
        SelectedFolder := DirSelect(, 0, GetLang("请选择若梦兔软件下Setting配置文件。"))
        if SelectedFolder == ""
            return
        SplitPath SelectedFolder, &name, &dir, &ext, &name_no_ext, &drive
        if (!InStr(name, "Setting") || name == "SettingOld") {
            RmtDialog.Info(GetLang("需要选择若梦兔软件下的Setting文件"), GetLang("提示"), this.ui.wpfHwnd)
            return
        }
        try {
            imported := RmtProgress.Run(GetLang("配置迁移"), GetLang("正在检查配置文件")
                , (progress) => Compat_ImportSettingsTree(SelectedFolder, A_WorkingDir "\Setting"
                    , A_WorkingDir "\SettingOld", MySoftData.CurSettingName, ObjBindMethod(progress, "Report")
                    , MySoftData.MacroTotalCount)
                , this.ui.wpfHwnd)
        } catch as e {
            RmtDialog.Info(GetLang("迁移失败: ") e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        MainSoftData.SettingArrStr := imported.Names
        MySoftData.CurSettingName := imported.Selected
        ; 重载退出会保存内存中的次数，先同步为已安装的迁移值。
        MySoftData.MacroTotalCount := imported.MacroTotalCount
        RMTLogSysInfo("配置导入", Format("配置列表已重建：{1}", imported.Names))
        RmtDialog.Info(GetLang("配置迁移成功"), GetLang("提示"), this.ui.wpfHwnd)
        SafeReload()
    }

    OnRepairBtnClick(state, ctrl, event) {
        SettingDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        hasWork := RmtProgress.Run(GetLang("正在检查配置文件"), MySoftData.CurSettingName
            , (*) => this.OnRepairSetting(SettingDir), this.ui.wpfHwnd)
        if (hasWork) {
            RmtDialog.Info("已校对")
            CfgWrite(true, SettingFile, SettingSection, "IsReload")
            SafeReload()
        }
        else {
            tipStr := (
                Format("{}`n{}`n{}`n{}", GetLang("未发现需要修复的内容"), GetLang("重要须知："), GetLang("- 针对覆盖配置文件后，搜索图片的配置路径矫正"),
                GetLang("- 低版本配置到高版本时，进行兼容适配升级"))
            )
            RmtDialog.Info(tipStr)
        }
    }

    OnOpenRMTSettingBtnClick(state, ctrl, event) {
        Run("https://forum.ruomengtu.com/c/shared-repository")
    }

    OnPackBtnClick(state, ctrl, event) {
        settingName := this._RequireSelectedSetting(state)
        if (settingName == "")
            return
        folderPath := A_WorkingDir "\Setting\" settingName
        outputFile := A_Desktop "\" settingName ".rmt"
        ; 询问包密码（弹窗挂在配置管理窗口上，取消 = 不导出）
        if (!FolderPackager.PackFolderWithPassword(folderPath, outputFile, this.ui.wpfHwnd))
            return
        RmtDialog.Info(GetLang("打包完成:") outputFile, GetLang("提示"), this.ui.wpfHwnd)
    }

    OnUnpackBtnClick(state, ctrl, event) {
        selectedFile := FileSelect(1, , GetLang("选择要导入的 RMT 文件"), "RMT Files (*.rmt)")
        if selectedFile == ""
            return

        SplitPath selectedFile, &fileName, , &fileExt, &fileNameNoExt
        if fileExt != "rmt" {
            RmtDialog.Info(GetLang("请选择 .rmt 文件！"), GetLang("错误"), this.ui.wpfHwnd)
            return
        }

        isVaild := this.IsValidFolderName(fileNameNoExt)
        if (!isVaild) {
            RmtDialog.Info(GetLang("配置名不符合文件目录命名规则，请修改"), GetLang("提示"), this.ui.wpfHwnd)
            return false
        }

        LoadType := 1
        for settingName in this.SettingList {
            if (fileNameNoExt = settingName) {
                fileNameNoExt := settingName
                importBtns := [GetLang("覆盖导入"), GetLang("自增导入"), GetLang("取消导入")]
                SelectType := RmtDialog.Choose(GetLang("配置已存在，请选择导入方式："), GetLang("配置导入选项"), importBtns, this.ui.wpfHwnd)
                if (SelectType == 0 || SelectType == 3)
                    return

                LoadType := SelectType + 1
                break
            }
        }

        if (LoadType == 3)
            fileNameNoExt := IncrementText(this.SettingList, fileNameNoExt)

        try {
            list := MainSoftData.SettingArrStr
            if (LoadType != 2)
                list .= "π" fileNameNoExt
            RmtProgress.Run(GetLang("导入配置"), GetLang("正在检查配置文件")
                , (progress) => Compat_ImportProfilePackage(selectedFile, A_WorkingDir "\Setting", A_WorkingDir "\SettingOld", fileNameNoExt
                    , ObjBindMethod(this, "_SelectProfileForReload", fileNameNoExt, list), ObjBindMethod(progress, "Report"))
                , this.ui.wpfHwnd)
        } catch as e {
            RmtDialog.Info(GetLang("解包失败: ") e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        SafeReload()
    }

    OnLoadBtnClick(state, ctrl, event) {
        settingName := this._RequireSelectedSetting(state)
        if (settingName == "")
            return
        try {
            RmtProgress.Run(GetLang("切换配置"), settingName
                , (*) => this._SelectProfileForReload(settingName), this.ui.wpfHwnd)
        } catch as e {
            RmtDialog.Info(e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        SafeReload()
    }

    _SelectProfileForReload(name, list := unset, rebase := unset) {
        ; 一次提交列表和当前项，避免其中一项写入后重载到不完整的配置状态。
        if (!IsSet(list))
            list := MainSoftData.SettingArrStr
        root := Cfg_Load(SettingFile).Clone()
        settings := Cfg_Seg(root, SettingSection).Clone()
        if (IsSet(rebase)) {
            for key, value in settings {
                if (Type(value) == "String")
                    settings[key] := rebase.Call(value)
            }
        }
        settings["SettingArrStr"] := list
        settings["CurSettingName"] := name
        settings["IsReload"] := "1"
        root[SettingSection] := settings
        Cfg_WriteRoot(root, SettingFile)
        MainSoftData.SettingArrStr := list
        MySoftData.CurSettingName := name
    }

    OnCourseBtnClick(state, ctrl, event) {
        settingName := this._RequireSelectedSetting(state)
        if (settingName == "")
            return
        folderPath := A_WorkingDir "\Setting\" settingName
        MyUseExplainGui.ShowGui(folderPath)
    }

    OnDelBtnClick(state, ctrl, event) {
        settingName := this._RequireSelectedSetting(state)
        if (settingName == "")
            return
        if (settingName == MySoftData.CurSettingName) {
            RmtDialog.Info(GetLang("不可删除当前配置"))
            return
        }

        result := RmtDialog.Confirm(Format(GetLang("是否删除{}配置"), settingName), GetLang("提示"))
        if (!result)
            return

        settingPath := A_WorkingDir "\Setting\" settingName
        try {
            FolderPackager._RejectReparsePoint(A_WorkingDir "\Setting")
            FolderPackager._RejectReparsePoint(settingPath)
            if (DirExist(settingPath)) {
                Compat_CheckPlainTree(settingPath)
                DirDelete(settingPath, true)
            }
        } catch as e {
            RmtDialog.Info(e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }

        SettingArrStr := ""
        for name in this.SettingList {
            if (settingName == name)
                continue
            SettingArrStr .= name "π"
        }
        SettingArrStr := RTrim(SettingArrStr, "π")
        MainSoftData.SettingArrStr := SettingArrStr
        CfgWrite(MainSoftData.SettingArrStr, SettingFile, SettingSection, "SettingArrStr")
        RmtDialog.Info(GetLang("删除配置: ") settingName)
        this.Refresh()
    }

    OnAddBtnClick(state, ctrl, event) {
        newFileName := RmtDialog.Input(GetLang("请输入新的配置名："), GetLang("新增配置"), "")
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild)
            return false

        if (FileExist(A_WorkingDir "\Setting\" newFileName.Value)) {
            RmtDialog.Info(GetLang("配置名已存在"), GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        try this._SelectProfileForReload(newFileName.Value, MainSoftData.SettingArrStr "π" newFileName.Value)
        catch as e {
            RmtDialog.Info(e.Message, GetLang("错误"), this.ui.wpfHwnd)
            return
        }
        SafeReload()
    }

    OnCopyBtnClick(state := unset, ctrl := unset, event := unset) {
        newFileName := RmtDialog.Input(GetLang("请输入新的配置名："), GetLang("复制配置"), "")
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild)
            return false

        MainSoftData.SettingArrStr .= "π" newFileName.Value
        CfgWrite(MainSoftData.SettingArrStr, SettingFile, SettingSection, "SettingArrStr")
        SourcePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        DestPath := A_WorkingDir "\Setting\" newFileName.Value
        DirCopy(SourcePath, DestPath, 1)
        this.OnRepairSetting(DestPath)
        RmtDialog.Info(Format(GetLang("成功复制<{}>配置到<{}>中"), MySoftData.CurSettingName, newFileName.Value))

        ; 只落盘：源（当前）配置未被触碰，不切换 CurSettingName、不写 IsReload、不重启，仅刷新配置列表
        this.Refresh()
    }

    OnRepairSetting(SettringDir, strict := false) {
        try {
            return Compat_UpgradeDir(SettringDir)
        } catch as e {
            RMTLogSys(RMT_LV_ERROR, "配置导入", SettringDir ": " e.Message)
            if (strict)
                throw e
            return false
        }
    }

    CheckIfExistAndValid(FileName) {
        isVaild := this.IsValidFolderName(FileName)
        if (!isVaild) {
            RmtDialog.Info(GetLang("配置名不符合文件目录命名规则，请修改"))
            return false
        }

        for settingName in this.SettingList {
            if (FileName = settingName) {
                RmtDialog.Info(GetLang("配置名已存在"))
                return false
            }
        }
        return true
    }

    IsValidFolderName(folderName) {
        return Compat_IsSettingName(folderName)
    }
}
