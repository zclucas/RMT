#Requires AutoHotkey v2.0

; =====================================================================
; 触发键编辑器 —— XAML 迁移版（独立实现，照 KeyGui 模式）
; 公开接口保持：ShowGui(triggerKey, HoldTime, IsToolEdit) / SureBtnAction / SaveBtnAction / SureFocusCon / UnorderedTrigger
; 与 KeyGui 差异：触发键解析（修饰键符号 !^+#、& 组合）；右下面板操作选项；跳过悬停高亮
; =====================================================================

class TriggerKeyGui {
    __new() {
        this.Gui := ""
        this.ui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SureFocusCon := ""
        this._closed := true

        this.CheckedArr := []
        this.ConMap := Map()          ; key → 按键按钮控件名
        this._btnKeyMap := Map()      ; 控件名 → key
        this._btnTxtMap := Map()      ; key → 按钮内文字控件名
        this._keySeq := 0
        this.ShowSaveBtn := false
        this.IsToolEdit := ""
        this.HoldTime := 0
        this.UnorderedTrigger := false
        this.ModifyKeyMap := Map("LAlt", "<!", "RAlt", ">!", "Alt", "!", "LWin", "<#", "RWin", ">#", "Win", "#",
            "LCtrl", "<^", "RCtrl", ">^", "Ctrl", "^", "LShift", "<+", "RShift", ">+", "Shift", "+")

        this.SelectColor := "#19C930"
        this.UnSelectColor := "{DynamicResource InputBg}"
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

    OnSureHotkey(state, ctrl, event) {
        triggerKey := this.ui.Query("HotkeyCon")
        symbol := this.ui.Query("EnableTriggerKeyCon") == "True" ? "~" : ""
        triggerKey := symbol triggerKey
        this.Init(triggerKey)
        this.Refresh()
    }

    ;选项相关
    OnCheckedKey(key, *) {
        isSelected := false
        arrayIndex := 0
        isModifyKey := false
        isNormalIndex := 0
        con := this.ConMap.Get(key)

        for modifyKey, modifyValue in this.ModifyKeyMap {
            if (modifyKey == key) {
                isModifyKey := true
                break
            }
        }

        for index, value in this.CheckedArr {
            if (!this.ModifyKeyMap.Has(value) && isNormalIndex == 0) {
                isNormalIndex := index
            }

            if (value == key) {
                isSelected := true
                arrayIndex := index
                break
            }
        }

        if (isSelected) {
            this.ui.Update(con, "Background", this.UnSelectColor)
            this.CheckedArr.RemoveAt(arrayIndex)
        }
        else {
            this.ui.Update(con, "Background", this.SelectColor)
            if (isModifyKey) {
                this.CheckedArr.InsertAt(isNormalIndex, key)
            }
            else {
                this.CheckedArr.Push(key)
            }
        }

        this.Refresh()
    }

    ClearCheckedArr() {
        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.UnSelectColor)
        }
        this.CheckedArr := []
        this.Refresh()
    }

    CheckConfigValid() {
        normalKeyNum := 0
        joyKeyNum := 0
        mouseKeyNum := 0
        hasModifyKey := false
        for index, value in this.CheckedArr {
            isSpecialKey := false

            subValue := SubStr(value, 1, 3)
            if (subValue == "Joy") {
                joyKeyNum += 1
                isSpecialKey := true
            }

            if (value == "LButton" || value == "RButton" || value == "MButton" || value == "XButton1" || value == "XButton2") {
                mouseKeyNum += 1
                isSpecialKey := true
            }

            for modifyKey, modifyValue in this.ModifyKeyMap {
                if (value == modifyKey) {
                    hasModifyKey := true
                    isSpecialKey := true
                    break
                }
            }

            if (!isSpecialKey)
                normalKeyNum += 1
        }

        if (joyKeyNum > 2)
            return false

        if (joyKeyNum >= 1 && (hasModifyKey || normalKeyNum > 0 || mouseKeyNum > 0))
            return false

        if (mouseKeyNum > 2)
            return false

        if (hasModifyKey && (normalKeyNum + mouseKeyNum) > 1)
            return false

        if ((normalKeyNum + mouseKeyNum) > 2)
            return false

        return true
    }

    ; 统计已勾选的非特殊按键数量（特殊按键=修饰键 Shift/Alt/Ctrl/Win 及其左右变体）
    CountNonSpecialKeys() {
        count := 0
        for index, value in this.CheckedArr {
            if (!this.ModifyKeyMap.Has(value))
                count += 1
        }
        return count
    }

    Init(triggerKey) {
        this.CheckedArr := []
        loopCount := 0
        this.ui.Update("EnableTriggerKeyCon", "IsChecked", RegExMatch(triggerKey, "~") ? "True" : "False")
        triggerKey := RegExReplace(triggerKey, "~", "")
        loop {
            hasModifyKey := false
            for key, value in this.ModifyKeyMap {
                length := StrLen(value)
                subTriggerKey := SubStr(triggerKey, 1, length)
                if (subTriggerKey == value) {
                    this.CheckedArr.Push(key)
                    triggerKey := SubStr(triggerKey, length + 1)
                    triggerKey := LTrim(triggerKey)
                    hasModifyKey := true
                    break
                }
            }

            if (!hasModifyKey)
                break

            loopCount += 1
            if (loopCount > 10)
                break
        }

        if (InStr(triggerKey, " & ")) {
            keyParts := StrSplit(triggerKey, " & ")
            for index, keyPart in keyParts {
                keyPart := Trim(keyPart)
                for key, value in this.ConMap {
                    if (StrCompare(key, keyPart, false) == 0) {
                        this.CheckedArr.Push(key)
                        break
                    }
                }
            }
            for key, name in this.ConMap
                this.ui.Update(name, "Background", this.UnSelectColor)
        }
        else {
            for key, name in this.ConMap {
                if (StrCompare(key, Trim(triggerKey), false) == 0)
                    this.CheckedArr.Push(key)
                this.ui.Update(name, "Background", this.UnSelectColor)
            }
        }

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this.ui.Update(this.ConMap[value], "Background", this.SelectColor)
        }

        this.ShowSaveBtn := !this.IsToolEdit
        vis := !this.IsToolEdit ? "Visible" : "Collapsed"
        this.ui.Update("HoldTimeCon", "Visibility", vis)
        this.ui.Update("HoldTimeLabelCon", "Visibility", vis)
        this.ui.Update("UnorderedTriggerCon", "Visibility", vis)
        if (!this.IsToolEdit) {
            this.ui.Update("HoldTimeCon", "Text", this.HoldTime)
            this.ui.Update("UnorderedTriggerCon", "IsChecked", this.UnorderedTrigger ? "True" : "False")
        }
        else {
            this.ui.Update("EnableTriggerKeyCon", "IsChecked", "False")
            this.ui.Update("EnableTriggerKeyCon", "IsEnabled", "False")
            this.ui.Update("UnorderedTriggerCon", "IsChecked", "False")
            this.ui.Update("UnorderedTriggerCon", "IsEnabled", "False")
        }
    }

    GetTriggerKey() {
        triggerKey := ""
        hasJoy := false
        modifyKeyArr := []
        normalKeyArr := []
        mouseKeyArr := []
        joyKeyArr := []

        for index, value in this.CheckedArr {
            if (RegExMatch(value, "Joy")) {
                hasJoy := true
                joyKeyArr.Push(value)
            }

            if (this.ModifyKeyMap.Has(value)) {
                modifyKeyArr.Push(value)
            }
            else if (value == "LButton" || value == "RButton" || value == "MButton" || value == "XButton1" || value == "XButton2") {
                mouseKeyArr.Push(value)
            }
            else {
                normalKeyArr.Push(value)
            }
        }

        keepOriginal := !hasJoy && this.ui.Query("EnableTriggerKeyCon") == "True"

        allNormalKeys := normalKeyArr.Clone()
        for index, value in mouseKeyArr {
            allNormalKeys.Push(value)
        }

        ; 当只有修饰键没有其他按键时，将修饰键作为普通按键处理
        if (modifyKeyArr.Length > 0 && allNormalKeys.Length == 0 && !hasJoy) {
            allNormalKeys := modifyKeyArr.Clone()
            modifyKeyArr := []
        }

        ; 修饰键前缀（! ^ + #）
        modifierPrefix := ""
        for index, value in modifyKeyArr {
            modifierPrefix .= this.ModifyKeyMap.Get(value)
        }

        ; 按键部分
        keyPart := ""
        if (hasJoy) {
            if (joyKeyArr.Length == 2) {
                keyPart .= joyKeyArr[1] " & " joyKeyArr[2]
            }
            else if (joyKeyArr.Length == 1) {
                keyPart .= joyKeyArr[1]
            }
        }
        else {
            if (allNormalKeys.Length == 2) {
                keyPart .= allNormalKeys[1] " & " allNormalKeys[2]
            }
            else if (allNormalKeys.Length == 1) {
                keyPart .= allNormalKeys[1]
            }
        }

        ; 保留触发键原本功能：~ 必须在最前面
        if (keepOriginal)
            triggerKey .= "~"
        triggerKey .= modifierPrefix keyPart

        return triggerKey
    }

    ;按钮点击回调
    OnSureBtnClick(state, ctrl, event) {
        isValid := this.CheckConfigValid()
        if (!isValid) {
            MsgBox(GetLang("当前配置无效,请浏览勾选规则后，检查配置,有异议请联系UP: 浮生若梦的兔子。"))
            return
        }
        triggerKey := this.GetTriggerKey()
        holdTime := this.ui.Query("HoldTimeCon")
        unorderedTrigger := this.ui.Query("UnorderedTriggerCon") == "True"
        action := this.SureBtnAction
        action(triggerKey, holdTime, unorderedTrigger)
        this._CloseWindow()
        if (this.SureFocusCon != "")
            try this.SureFocusCon.Focus()
    }

    OnSaveBtnClick(state, ctrl, event) {
        isValid := this.CheckConfigValid()
        if (!isValid) {
            MsgBox(GetLang("当前配置无效,请浏览勾选规则后，检查配置,有异议请联系UP: 浮生若梦的兔子。"))
            return
        }

        triggerKey := this.GetTriggerKey()
        holdTime := this.ui.Query("HoldTimeCon")
        unorderedTrigger := this.ui.Query("UnorderedTriggerCon") == "True"
        action := this.SureBtnAction
        action(triggerKey, holdTime, unorderedTrigger)

        action := this.SaveBtnAction
        action()
        this._CloseWindow()
        if (this.SureFocusCon != "")
            try this.SureFocusCon.Focus()
    }

    ;UI相关
    ShowGui(triggerKey, HoldTime, IsToolEdit) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this.HoldTime := HoldTime
        this.IsToolEdit := IsToolEdit
        this.Init(triggerKey)
        this.Refresh()
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        ; 实例复用：重建前清空按键映射，避免 _btnKeyMap/_keySeq 累积导致事件重复绑定
        this.ConMap := Map()
        this._btnKeyMap := Map()
        this._btnTxtMap := Map()
        this._keySeq := 0
        title := GetLang("触发键编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 按键网格（主界面同款 1.5px Outline 外框；顶部居中：键盘触发键检测）===
        editorBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        toolBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="False">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        keyGroup := main.Add("Border").Grid_Row(1).Margin("8,4,8,19").Padding("4,2,4,4")
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("1.5").CornerRadius("4")
            .Background("Transparent").ClipToBounds("False")
        keyGroup.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "False"})
        keyInner := keyGroup.Add("Grid").ClipToBounds("False")
        ; 单层叠放：检测行置顶居中；按键区铺满
        keyInner.Rows("*")

        detectRow := keyInner.Add("StackPanel").Grid_Row(0).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Top").Margin("-20,2,0,0").Panel_ZIndex(2)
        detectRow.Add("TextBlock").Text(GetLang("键盘触发键检测：")).VerticalAlignment("Center")
        detectRow.Add("TextBox").Name("HotkeyCon").Width(180).Height(26).MinHeight(26).Margin("4,0,0,0")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").VerticalContentAlignment("Center").Padding("4,0")
        detectBtn := detectRow.Add("Button").Name("BtnDetect").Content(GetLang("确定")).Width(56).Height(26).MinHeight(26).Padding("12,0").Margin("6,0,0,0").Cursor("Hand")
            .Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        detectBtn.InjectResources(toolBtnStyle)

        sv := keyInner.Add("ScrollViewer").Grid_Row(0).Panel_ZIndex(1)
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled").ClipToBounds("False")
        this._keyGrid := sv.Add("Canvas").Width("1240").Height("395").Margin("-10,0,0,0")

        ; === 底部：选项+说明+清空/确定，整体上移 15px（不改包裹框内按键）===
        bottom := main.Add("Grid").Grid_Row(2).Margin("0,-15,0,4").ClipToBounds("False")
        bottom.Rows("Auto", "44")

        opt := bottom.Add("Grid").Grid_Row(0).Margin("10,4").ClipToBounds("False")
        opt.Rows("28", "30", "26")

        r0 := opt.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").HorizontalAlignment("Left").Margin("100,0,0,0")
        r0.Add("CheckBox").Name("EnableTriggerKeyCon").Content(GetLang("保留触发键原本功能")).VerticalAlignment("Center")
        r0.Add("CheckBox").Name("UnorderedTriggerCon").Content(GetLang("顺序触发")).VerticalAlignment("Center").Margin("24,0,0,0")
            .ToolTip(GetLang("普通触发键多选生效"))

        r1 := opt.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Left").Margin("100,0,0,0")
        r1.Add("TextBlock").Name("HoldTimeLabelCon").Text(GetLang("长按时间/双击时间：")).VerticalAlignment("Center")
        r1.Add("TextBox").Name("HoldTimeCon").Width(100).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ToolTip(GetLang("此设置只在触发模式是【长按】/【双击】时有效"))

        r2 := opt.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment("Left").Margin("100,0,0,0")
        r2.Add("TextBlock").Name("CheckedInfoCon").Text(GetLang("当前配置的触发键：无")).VerticalAlignment("Center")
        r2.Add("TextBlock").Name("CheckedInvalidTipCon").Text(GetLang("当前配置无效,请浏览勾选规则后，检查配置")).Foreground("#FF0000").VerticalAlignment("Center").Margin("20,0,0,0").Visibility("Collapsed")

        helpStack := opt.Add("StackPanel").Grid_Row(0).Grid_RowSpan(3).Orientation("Vertical")
            .HorizontalAlignment("Left").VerticalAlignment("Center").Margin("620,0,10,0").Width(630)
            .IsHitTestVisible("False")
        helpStack.Add("TextBlock").Name("HelpTip1").Text(GetLang("特殊按键：Shift, Alt, Ctrl, Win, LShift, RShift, LAlt, RAlt, LCtrl, RCtrl, LWin, RWin")).Opacity("0.6").TextWrapping("Wrap")
        helpStack.Add("TextBlock").Name("HelpTip2").Text(GetLang("普通按键：除特殊按键的其他按键")).Opacity("0.6").Margin("0,4,0,0")
        helpStack.Add("TextBlock").Name("HelpTip3").Text(GetLang("勾选规则1：特殊按键中可以 同时勾选多个按键 或 不选，普通按键中只能 勾选一/二个按键 或 不选")).Opacity("0.6").Margin("0,4,0,0").TextWrapping("Wrap")
        helpStack.Add("TextBlock").Name("HelpTip4").Text(GetLang("勾选规则2：手柄按钮、摇杆可选1-2个按键组合")).Opacity("0.6").Margin("0,4,0,0")

        btnRow := bottom.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
        clearBtn := btnRow.Add("Button").Name("BtnClear").Content(GetLang("清空")).Width(100).Height(32).MinHeight(32).Margin("0").Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontWeight("Bold")
        clearBtn.InjectResources(editorBtnStyle)
        okBtn := btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("400,0,0,0").Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontWeight("Bold")
        okBtn.InjectResources(editorBtnStyle)

        ; === 生成按键网格 ===
        this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="1280" Height="635" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件 ===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnDetect", "Click", ObjBindMethod(this, "OnSureHotkey"))
        this.ui.OnEvent("EnableTriggerKeyCon", "Click", ObjBindMethod(this, "OnChangeEnableTriggerKey"))
        this.ui.OnEvent("UnorderedTriggerCon", "Click", ObjBindMethod(this, "OnChangeUnorderedTrigger"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))

    }

    ; ---------------- 按键网格 ----------------

    _PlaceLabel(text, x, y) {
        this._keyGrid.Add("TextBlock").Text(text).FontWeight("SemiBold").FontSize(12)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
    }

    _PlaceKey(value, display, x, y, width) {
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        txtName := name "_Txt"
        btn := this._keyGrid.Add("Button").Name(name).Width(width).Height(25)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .Cursor("Hand").Padding("2,1")
            .HorizontalContentAlignment("Stretch").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        ; Viewbox DownOnly：字号上限为当前 11，超出按钮宽度时自适应缩小
        vb := btn.Add("Viewbox").Stretch("Uniform").StretchDirection("DownOnly")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
        vb.Add("TextBlock").Name(txtName).Text(display).FontSize(11)
            .Foreground("{DynamicResource TextMain}")
            .TextAlignment("Center").TextWrapping("NoWrap")
        this.ConMap.Set(value, name)
        this._btnKeyMap.Set(name, value)
        this._btnTxtMap.Set(value, txtName)
    }

    _AddKeyRow(keys, y) {
        for item in keys {
            this._PlaceKey(item[1], item[2], item[3], y, item[4])
        }
    }

    _BuildKeyGrid() {
        global MySoftData
        ; 「键盘」在 Esc 上方（同「鼠标」相对左键）；整体上移由 ScrollViewer/Canvas Margin 完成，勿再 +30 抵消
        this._PlaceLabel(GetLang("键盘"), 20, 0)
        this._AddKeyRow([
            ["Esc","Esc",20,40],["F1","F1",120,35],["F2","F2",170,35],["F3","F3",220,35],["F4","F4",270,35],
            ["F5","F5",345,35],["F6","F6",395,35],["F7","F7",445,35],["F8","F8",495,35],
            ["F9","F9",570,35],["F10","F10",620,35],["F11","F11",670,35],["F12","F12",720,35],
            ["PrintScreen","PrtScr",795,45],["ScrollLock","Scroll",870,45],["Pause","Pause",945,45]], 20)
        this._AddKeyRow([
            ["``","~",20,35],["1","1",70,35],["2","2",120,35],["3","3",170,35],["4","4",220,35],
            ["5","5",270,35],["6","6",320,35],["7","7",370,35],["8","8",420,35],["9","9",470,35],
            ["0","0",520,35],["-","-",570,35],["=","=",620,35],["BS","Backspace",670,85],
            ["Ins","Ins",795,45],["Home","Home",870,45],["PgUp","PgUp",945,45],
            ["NumLock","Num",1045,35],["NumpadDiv","/",1095,35],["NumpadMult","*",1145,35],["NumpadSub","-",1195,35]], 50)
        this._AddKeyRow([
            ["Tab","Tab",20,60],["q","Q",100,35],["w","W",150,35],["e","E",200,35],["r","R",250,35],
            ["t","T",300,35],["y","Y",350,35],["u","U",400,35],["i","I",450,35],["o","O",500,35],
            ["p","P",550,35],["[","[",600,35],["]","]",650,35],["\","\",705,50],
            ["Del","Del",795,45],["End","End",870,45],["PgDn","PgDn",945,45],
            ["Numpad7","7",1045,35],["Numpad8","8",1095,35],["Numpad9","9",1145,35],["NumpadAdd","+",1195,35]], 80)
        this._AddKeyRow([
            ["CapsLock","CapsLock",20,75],["a","A",120,35],["s","S",170,35],["d","D",220,35],["f","F",270,35],
            ["g","G",320,35],["h","H",370,35],["j","J",420,35],["k","K",470,35],["l","L",520,35],
            [";",";",570,35],["'","'",620,35],["Enter","Enter",680,75],
            ["Numpad4","4",1045,35],["Numpad5","5",1095,35],["Numpad6","6",1145,35]], 110)
        this._AddKeyRow([
            ["LShift","LShift",20,85],["z","Z",130,35],["x","X",180,35],["c","C",230,35],["v","V",280,35],
            ["b","B",330,35],["n","N",380,35],["m","M",430,35],["逗号",",",480,35],[".",".",530,35],
            ["/","/",580,35],["RShift","RShift",670,85],["Up","↑",870,45],
            ["Numpad1","1",1045,35],["Numpad2","2",1095,35],["Numpad3","3",1145,35],["NumpadEnter","Enter",1195,35]], 140)
        this._AddKeyRow([
            ["LCtrl","LCtrl",20,60],["LWin","LWin",95,60],["LAlt","LAlt",170,60],["Space","Space",245,210],
            ["RAlt","RAlt",470,60],["RWin","RWin",545,60],["AppsKey","AppsKey",620,60],["RCtrl","RCtrl",695,60],
            ["Left","←",795,45],["Down","↓",870,45],["Right","→",945,45],["Numpad0","0",1045,35],["NumpadDot","Del",1145,35]], 170)
        this._AddKeyRow([
            ["Ctrl","Ctrl",20,60],["Shift","Shift",95,60],["Alt","Alt",170,60],
            ["Browser_Back",GetLang("后退"),245,60],["Browser_Forward",GetLang("前进"),320,60],
            ["Browser_Refresh",GetLang("刷新"),395,60],["Browser_Stop",GetLang("停止"),470,60],
            ["Browser_Search",GetLang("搜索"),545,60],["Browser_Favorites",GetLang("收藏夹"),620,60],
            ["Browser_Home",GetLang("主页"),695,60],["Volume_Mute",GetLang("静音"),790,60],
            ["Volume_Down",GetLang("音量-"),865,60],["Volume_Up",GetLang("音量+"),940,60],
            ["Bright_Down",GetLang("亮度-"),1045,60],["Bright_Up",GetLang("亮度+"),1120,60]], 200)
        this._AddKeyRow([
            ["Launch_App1",GetLang("此电脑"),20,60],["Launch_App2",GetLang("计算器"),95,60],
            ["Media_Next",GetLang("下一首"),170,60],["Media_Prev",GetLang("上一首"),245,60],
            ["Media_Stop",GetLang("停止"),320,60],["Media_Play_Pause",GetLang("播放/暂停"),395,80]], 230)

        this._PlaceLabel(GetLang("鼠标"), 20, 260)
        this._AddKeyRow([
            ["LButton",GetLang("左键"),20,60],["MButton",GetLang("中键"),95,60],["RButton",GetLang("右键"),170,60],
            ["WheelDown",GetLang("下滚轮"),245,60],["WheelUp",GetLang("上滚轮"),320,60],
            ["WheelLeft",GetLang("滚轮左键"),395,60],["WheelRight",GetLang("滚轮右键"),470,60],
            ["XButton1",GetLang("侧键1"),545,60],["XButton2",GetLang("侧键2"),620,60]], 280)

        this._PlaceLabel(GetLang("手柄-按键"), 20, 310)
        this._AddKeyRow([
            ["JoyA",MySoftData.GetJoyDisplayName("JoyA"),20,60],["JoyB",MySoftData.GetJoyDisplayName("JoyB"),95,60],
            ["JoyX",MySoftData.GetJoyDisplayName("JoyX"),170,60],["JoyY",MySoftData.GetJoyDisplayName("JoyY"),245,60],
            ["JoyLB",MySoftData.GetJoyDisplayName("JoyLB"),320,60],["JoyRB",MySoftData.GetJoyDisplayName("JoyRB"),395,60],
            ["JoyLT",MySoftData.GetJoyDisplayName("JoyLT"),470,60],["JoyRT",MySoftData.GetJoyDisplayName("JoyRT"),545,60],
            ["JoyLS",MySoftData.GetJoyDisplayName("JoyLS"),620,60],["JoyRS",MySoftData.GetJoyDisplayName("JoyRS"),695,60],
            ["JoyBack",MySoftData.GetJoyDisplayName("JoyBack"),770,60],["JoyStart",MySoftData.GetJoyDisplayName("JoyStart"),845,60],
            ["JoyHome",MySoftData.GetJoyDisplayName("JoyHome"),920,60],["JoyPad",MySoftData.GetJoyDisplayName("JoyPad"),995,60]], 330)

        this._PlaceLabel(GetLang("手柄-方向键、摇杆"), 20, 360)
        this._AddKeyRow([
            ["JoyDpadUp",GetLang("上"),20,60],["JoyDpadDown",GetLang("下"),95,60],
            ["JoyDpadLeft",GetLang("左"),170,60],["JoyDpadRight",GetLang("右"),245,60],
            ["JoyDpadNone",GetLang("无方向"),320,60],["JoyAxisLXMin","LXMin",395,60],["JoyAxisLXMax","LXMax",470,60],
            ["JoyAxisLYMin","LYMin",545,60],["JoyAxisLYMax","LYMax",620,60],["JoyAxisRXMin","RXMin",695,60],
            ["JoyAxisRXMax","RXMax",770,60],["JoyAxisRYMin","RYMin",845,60],["JoyAxisRYMax","RYMax",920,60]], 380)
    }

    _RegisterKeyEvents() {
        for name, value in this._btnKeyMap
            this.ui.OnEvent(name, "Click", ObjBindMethod(this, "OnCheckedKey").Bind(value))
    }

    Refresh() {
        lable := GetLang("当前配置的触发键：")
        infoStr := ""
        hasJoy := false
        for index, value in this.CheckedArr {
            isMatch := RegExMatch(value, "Joy")
            if (isMatch) {
                hasJoy := true
            }
            infoStr .= value
            if (index < this.CheckedArr.Length) {
                infoStr .= "  +  "
            }
        }

        if (this.CheckedArr.Length == 0)
            infoStr := GetLang("无")
        else {
            if (!hasJoy && this.ui.Query("EnableTriggerKeyCon") == "True") {
                infoStr := "~" infoStr
            }
        }

        if (hasJoy || this.IsToolEdit) {
            this.ui.Update("EnableTriggerKeyCon", "IsChecked", "False")
            this.ui.Update("EnableTriggerKeyCon", "IsEnabled", "False")
        }
        else {
            this.ui.Update("EnableTriggerKeyCon", "IsEnabled", "True")
        }

        isValid := this.CheckConfigValid()
        this.ui.Update("CheckedInvalidTipCon", "Visibility", isValid ? "Collapsed" : "Visible")
        this.ui.Update("CheckedInfoCon", "Text", lable infoStr)
        this.UpdateJoyBtnDisplay()

        ; 顺序触发：仅当非特殊按键多选时可用，否则禁用并灰显
        nonSpecialKeyNum := this.CountNonSpecialKeys()
        if (!this.IsToolEdit && nonSpecialKeyNum >= 2) {
            this.ui.Update("UnorderedTriggerCon", "IsEnabled", "True")
        }
        else {
            this.ui.Update("UnorderedTriggerCon", "IsEnabled", "False")
            this.ui.Update("UnorderedTriggerCon", "IsChecked", "False")
        }
    }

    UpdateJoyBtnDisplay() {
        global MySoftData
        joyBtnKeys := ["JoyA", "JoyB", "JoyX", "JoyY", "JoyLB", "JoyRB", "JoyLT", "JoyRT",
            "JoyLS", "JoyRS", "JoyBack", "JoyStart", "JoyPad", "JoyHome",
            "JoyDpadUp", "JoyDpadDown", "JoyDpadLeft", "JoyDpadRight"]
        for key in joyBtnKeys {
            if (this._btnTxtMap.Has(key))
                this.ui.Update(this._btnTxtMap[key], "Text", MySoftData.GetJoyDisplayName(key))
        }
    }

    OnChangeEnableTriggerKey(state, ctrl, event) {
        this.Refresh()
    }

    OnChangeUnorderedTrigger(state, ctrl, event) {
        this.Refresh()
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
        ; ScaleFontSize 有主题下限，声明 FontSize(9) 会被抬回主题字号；用 Relative 写入才真正 -2
        helpFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSizeRelative(XAMLHost.GetDesignFontSize() - 2))
        prevSkip := this.ui.HasProp("skipFontScale") ? this.ui.skipFontScale : false
        this.ui.skipFontScale := true
        loop 4 {
            try this.ui.Update("HelpTip" A_Index, "FontSize", String(helpFs))
        }
        this.ui.skipFontScale := prevSkip
    }

    OnWindowClosing(state, ctrl, event) {
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this._closed := true
    }

    OnGuiClose() {
        this._CloseWindow()
    }
}
