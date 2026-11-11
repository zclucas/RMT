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

        this.SelectColor := "{DynamicResource ActionBg}"
        this.UnSelectColor := "{DynamicResource InputBg}"
        this._joyBtnDefBg := Map()
        this._joyBtnDefBd := Map()
        this._joyAxisCenters := Map()
        this._joyDrag := ""
        this._joyDragMoved := false
        this._joyDragStartX := 0
        this._joyDragStartY := 0
        this._joyDragLastX := 0
        this._joyDragLastY := 0
        this._joyScreenOriginX := 0
        this._joyScreenOriginY := 0
        this._joyDragTick := ObjBindMethod(this, "OnJoyDragTick")
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _UiAlive() {
        return IsObject(this.ui) && !(this.HasProp("_closed") && this._closed)
    }

    _EscapeXml(s) => EscapeXamlXml(s)

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
            this._SetKeyBtnState(con, key, false)
            this.CheckedArr.RemoveAt(arrayIndex)
        }
        else {
            this._SetKeyBtnState(con, key, true)
            if (isModifyKey) {
                this.CheckedArr.InsertAt(isNormalIndex ? isNormalIndex : this.CheckedArr.Length + 1, key)
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
                this._SetKeyBtnState(this.ConMap[value], value, false)
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
        ; 兼容旧配置/外部调用：手柄编辑器中的短名 A/B/... 必须规范化为
        ; JoyA/JoyB/...，否则重绑时会被当成键盘热键。
        if (this.EditorMode == "joy" && !InStr(triggerKey, "Joy")) {
            hadPassthrough := InStr(triggerKey, "~")
            rawJoy := Trim(RegExReplace(triggerKey, "^~", ""))
            if (InStr(rawJoy, " & ")) {
                normalizedParts := []
                for part in StrSplit(rawJoy, " & ") {
                    converted := this._ToTriggerJoyKey(Trim(part))
                    normalizedParts.Push(converted != "" ? converted : Trim(part))
                }
                triggerKey := (hadPassthrough ? "~" : "") normalizedParts[1] " & " normalizedParts[2]
            }
            else {
                normalizedJoy := this._ToTriggerJoyKey(rawJoy)
                if (normalizedJoy != "")
                    triggerKey := (hadPassthrough ? "~" : "") normalizedJoy
            }
        }
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
                this._SetKeyBtnState(name, key, false)
        }
        else {
            for key, name in this.ConMap {
                if (StrCompare(key, Trim(triggerKey), false) == 0)
                    this.CheckedArr.Push(key)
                this._SetKeyBtnState(name, key, false)
            }
        }

        for index, value in this.CheckedArr {
            if (this.ConMap.Has(value))
                this._SetKeyBtnState(this.ConMap[value], value, true)
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

        ; 键盘使用 AHK 的 ~ 前缀；手柄由 JoyMacro 转发到虚拟手柄。
        ; 手柄触发不使用键盘热键的 ~ 前缀；~ 仅属于键盘穿透语义。
        keepOriginal := !hasJoy && this.ui.Query("EnableTriggerKeyCon") == "True"

        allNormalKeys := normalKeyArr.Clone()
        for index, value in mouseKeyArr {
            allNormalKeys.Push(value)
        }

        ; 手柄编辑模式下，兜底把短名 A/B/... 规范化为 JoyA/JoyB/...。
        ; 即使旧窗口事件把按钮暂时写进普通按键数组，最终保存值也不会
        ; 被 BindTabHotKey 当成键盘热键。
        if (this.EditorMode == "joy" && !hasJoy) {
            normalizedJoy := []
            for index, value in allNormalKeys {
                try converted := JoyShortToInternal(value)
                catch
                    converted := ""
                if (converted != "")
                    normalizedJoy.Push(converted)
            }
            if (normalizedJoy.Length > 0) {
                hasJoy := true
                joyKeyArr := normalizedJoy
                allNormalKeys := []
            }
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
        if (keepOriginal && keyPart != "")
            triggerKey .= "~"
        triggerKey .= modifierPrefix keyPart

        return triggerKey
    }

    ;按钮点击回调
    OnSureBtnClick(state, ctrl, event) {
        isValid := this.CheckConfigValid()
        if (!isValid) {
            RmtDialog.Info(GetLang("当前配置无效,请浏览勾选规则后，检查配置,有异议请联系UP: 浮生若梦的兔子。"))
            return
        }
        triggerKey := this.GetTriggerKey()
        holdTime := this.ui.Query("HoldTimeCon")
        unorderedTrigger := this.EditorMode != "joy" && this.ui.Query("UnorderedTriggerCon") == "True"
        action := this.SureBtnAction
        action(triggerKey, holdTime, unorderedTrigger)
        this._CloseWindow()
        if (this.SureFocusCon != "")
            try this.SureFocusCon.Focus()
    }

    OnSaveBtnClick(state, ctrl, event) {
        isValid := this.CheckConfigValid()
        if (!isValid) {
            RmtDialog.Info(GetLang("当前配置无效,请浏览勾选规则后，检查配置,有异议请联系UP: 浮生若梦的兔子。"))
            return
        }

        triggerKey := this.GetTriggerKey()
        holdTime := this.ui.Query("HoldTimeCon")
        unorderedTrigger := this.EditorMode != "joy" && this.ui.Query("UnorderedTriggerCon") == "True"
        action := this.SureBtnAction
        action(triggerKey, holdTime, unorderedTrigger)

        action := this.SaveBtnAction
        action()
        this._CloseWindow()
        if (this.SureFocusCon != "")
            try this.SureFocusCon.Focus()
    }

    ;UI相关
    ShowGui(triggerKey, HoldTime, IsToolEdit, mode := "") {
        this.EditorMode := mode != "" ? mode : (InStr(triggerKey, "Joy") ? "joy" : "keyboard")
        this._drafts := Map("keyboard", "", "joy", "")
        this._drafts[this.EditorMode] := triggerKey
        this._draftOrder := Map("keyboard", false, "joy", false)
        this._draftOrder[this.EditorMode] := this.UnorderedTrigger
        this._OpenEditor(triggerKey, HoldTime, IsToolEdit)
    }

    _SwitchEditor(*) {
        this._drafts[this.EditorMode] := this.GetTriggerKey()
        holdTime := this.ui.Query("HoldTimeCon")
        this._draftOrder[this.EditorMode] := this.ui.Query("UnorderedTriggerCon") == "True"
        this.EditorMode := this.EditorMode == "joy" ? "keyboard" : "joy"
        this.UnorderedTrigger := this._draftOrder[this.EditorMode]
        this._OpenEditor(this._drafts[this.EditorMode], holdTime, this.IsToolEdit)
    }

    _OpenEditor(triggerKey, HoldTime, IsToolEdit) {
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this._BuildAndShow()
        this.HoldTime := HoldTime
        this.IsToolEdit := IsToolEdit
        this.Init(triggerKey)
        this.Refresh()
        opened := XamlWin.Open(this.ui, "", XamlWin.Owner(this))
        if (!opened)
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
        ; 每个窗口实例带独立令牌，旧窗口的 Closing/Loaded 回调不能清理新窗口。
        token := Object()
        this._uiToken := token
        isJoy := this.EditorMode == "joy"
        title := GetLang(isJoy ? "手柄触发键" : "按键触发键")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*", "Auto")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBarChrome(main, title)
        ; 编辑器切换放在标题栏右侧，保持与其它编辑器的窗口操作一致。
        switchTitle := XAMLHost.AddTitleChromeBtn(chrome.Btns, "BtnSwitch", titleHeight,
            Chr(isJoy ? 0xE92E : 0xE7FC), "Visible", "{StaticResource TitleBarChromeButton}", "42", "14")
        switchTitle.ToolTip(GetLang(isJoy ? "切换到按键触发键" : "切换到手柄触发键"))
        chrome.Close := XAMLHost.AddTitleCloseBtn(chrome.Btns, "BtnClosePanel", titleHeight)

        ; === 按键网格（主界面同款 1.5px Outline 外框；顶部居中：键盘触发键检测）===
        editorBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        toolBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True" UseLayoutRounding="True">'
            . '<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ControlBorder}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '<Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource BtnPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        joyGroupBg := isJoy ? "{DynamicResource ControlBg}" : "Transparent"
        joyGroupBorder := isJoy ? "{DynamicResource ControlBorder}" : "{DynamicResource OutlineStroke}"
        joyGroupRadius := isJoy ? "10" : "4"
        joyGroupPadding := isJoy ? "12" : "4,2,4,4"
        keyGroup := main.Add("Border").Name("WindowBody").Grid_Row(1).Margin("8,4,8,19").Padding(joyGroupPadding)
            .BorderBrush(joyGroupBorder).BorderThickness("1.5").CornerRadius(joyGroupRadius)
            .Background(joyGroupBg).ClipToBounds("False")
        keyGroup.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "False"})
        keyInner := keyGroup.Add("Grid").ClipToBounds("False")
        ; 单层叠放：检测行置顶居中；按键区铺满
        keyInner.Rows("*")

        detectRow := keyInner.Add("StackPanel").Grid_Row(0).Orientation("Horizontal")
            .HorizontalAlignment("Center").VerticalAlignment("Top").Margin("-20,2,0,0").Panel_ZIndex(2)
        detectRow.Visibility(isJoy ? "Collapsed" : "Visible")
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
        this._keyGrid := sv.Add("Canvas").Name("TriggerPadCanvas").Width(isJoy ? "640" : "1240").Height(isJoy ? "390" : "315").Margin("-10,0,0,0")

        ; === 底部：选项+说明+清空/确定，整体上移 15px（不改包裹框内按键）===
        bottom := main.Add("Grid").Grid_Row(2).Margin("0,-15,0,4").ClipToBounds("False")
        bottom.Rows("Auto", "44")

        opt := bottom.Add("Grid").Grid_Row(0).Margin("10,4").ClipToBounds("False")
        opt.Rows("28", "30", "26")

        r0 := opt.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").HorizontalAlignment(isJoy ? "Center" : "Left").Margin(isJoy ? "0" : "100,0,0,0")
        r0.Add("CheckBox").Name("EnableTriggerKeyCon").Content(GetLang("保留触发键原本功能")).VerticalAlignment("Center")
        unorderedCon := r0.Add("CheckBox").Name("UnorderedTriggerCon").Content(GetLang("顺序触发")).VerticalAlignment("Center").Margin("24,0,0,0")
            .ToolTip(GetLang("普通触发键多选生效"))
        if (isJoy)
            unorderedCon.Visibility("Collapsed")

        r1 := opt.Add("StackPanel").Grid_Row(1).Orientation("Horizontal").HorizontalAlignment(isJoy ? "Center" : "Left").Margin(isJoy ? "0" : "100,0,0,0")
        r1.Add("TextBlock").Name("HoldTimeLabelCon").Text(GetLang("长按时间/双击时间：")).VerticalAlignment("Center")
        r1.Add("TextBox").Name("HoldTimeCon").Width(100).Height(24).MinHeight(24)
            .VerticalContentAlignment("Center").Padding("4,0").TextAlignment("Center").FontSize(11).Margin("4,0,0,0")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ToolTip(GetLang("此设置只在触发模式是【长按】/【双击】时有效"))

        r2 := opt.Add("StackPanel").Grid_Row(2).Orientation("Horizontal").HorizontalAlignment(isJoy ? "Center" : "Left").Margin(isJoy ? "0" : "100,0,0,0")
        r2.Add("TextBlock").Name("CheckedInfoCon").Text(GetLang("当前配置的触发键：无")).VerticalAlignment("Center")
        r2.Add("TextBlock").Name("CheckedInvalidTipCon").Text(GetLang("当前配置无效,请浏览勾选规则后，检查配置")).Foreground("#FF0000").VerticalAlignment("Center").Margin("20,0,0,0").Visibility("Collapsed")

        helpStack := opt.Add("StackPanel").Grid_Row(0).Grid_RowSpan(3).Orientation("Vertical")
            .HorizontalAlignment("Left").VerticalAlignment("Center").Margin("620,0,10,0").Width(630)
            .IsHitTestVisible("False")
        helpStack.Add("TextBlock").Name("HelpTip1").Text(GetLang("特殊按键：Shift, Alt, Ctrl, Win, LShift, RShift, LAlt, RAlt, LCtrl, RCtrl, LWin, RWin")).Opacity("0.6").TextWrapping("Wrap")
        helpStack.Add("TextBlock").Name("HelpTip2").Text(GetLang("普通按键：除特殊按键的其他按键")).Opacity("0.6").Margin("0,4,0,0")
        helpStack.Add("TextBlock").Name("HelpTip3").Text(GetLang("勾选规则1：特殊按键中可以 同时勾选多个按键 或 不选，普通按键中只能 勾选一/二个按键 或 不选")).Opacity("0.6").Margin("0,4,0,0").TextWrapping("Wrap")
        helpStack.Visibility(isJoy ? "Collapsed" : "Visible")
        helpStack.Add("TextBlock").Name("HelpTip4").Text("").Opacity("0.6").Margin("0,4,0,0")

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
        if (isJoy)
            this._BuildJoyGrid()
        else
            this._BuildKeyGrid()

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")
        winW := isJoy ? "720" : "1280"
        winH := isJoy ? "620" : "555"
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Uid="gm:Window.TriggerKey" Title="' this._EscapeXml(title) '" Width="' winW '" Height="' winH '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 注册按键事件 ===
        this._RegisterKeyEvents()

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing", token))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad", token))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("BtnSwitch", "Click", ObjBindMethod(this, "_SwitchEditor"))
        this.ui.OnEvent("BtnDetect", "Click", ObjBindMethod(this, "OnSureHotkey"))
        this.ui.OnEvent("EnableTriggerKeyCon", "Click", ObjBindMethod(this, "OnChangeEnableTriggerKey"))
        this.ui.OnEvent("UnorderedTriggerCon", "Click", ObjBindMethod(this, "OnChangeUnorderedTrigger"))
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearCheckedArr())
        this.ui.OnEvent("BtnOk", "Click", ObjBindMethod(this, "OnSureBtnClick"))
        if (isJoy) {
            this.ui.OnEvent("TriggerPadCanvas", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "OnJoyPadMouseDown"))
            this.ui.OnEvent("TriggerPadCanvas", "PreviewMouseMove", ObjBindMethod(this, "OnJoyPadMouseMove"))
            this.ui.OnEvent("TriggerPadCanvas", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "OnJoyPadMouseUp"))
        }

    }

    ; ---------------- 按键网格 ----------------

    _KeyLabelBox(parent) {
        ; 键帽文字可能同时受窗口缩放和 Viewbox 缩放。使用连续字形度量，
        ; 避免在不同坐标系中先按像素取整、再缩放时裁掉字形边缘。
        return parent.Add("Viewbox").Stretch("Uniform").StretchDirection("DownOnly")
            .UseLayoutRounding("False").SnapsToDevicePixels("False")
            .SetProp("TextOptions.TextFormattingMode", "Ideal")
    }

    _PlaceLabel(text, x, y) {
        ; 标题和下一行按键之间只有 20 DIP，大号主题文字也要放进这段高度。
        label := this._KeyLabelBox(this._keyGrid).Height(20)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
        label.Add("TextBlock").Text(text).FontWeight("SemiBold").FontSize(12)
    }

    _SetKeyBtnState(con, key, selected) {
        defaultBg := this._joyBtnDefBg.Has(con) ? this._joyBtnDefBg[con] : this.UnSelectColor
        defaultBd := this._joyBtnDefBd.Has(con) ? this._joyBtnDefBd[con] : "{DynamicResource InputStroke}"
        this.ui.Update(con, "Background", selected ? this.SelectColor : defaultBg)
        this.ui.Update(con, "BorderBrush", selected ? "{DynamicResource ActionStroke}" : defaultBd)
        this.ui.Update(con, "Tag", selected ? "1" : "0")
        if (this._btnTxtMap.Has(key))
            this.ui.Update(this._btnTxtMap[key], "Foreground", selected ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
    }

    ; 摇杆本体没有可见的按钮控件（事件由画布统一处理），因此不能只更新
    ; 隐藏映射按钮。同步更新摇杆圆盘和字母的视觉状态，让点击与普通按键
    ; 一样有明确的背景反馈。
    _RefreshJoyStickHighlight() {
        if (!IsObject(this.ui) || !this.HasProp("_joyAxisCenters"))
            return
        for prefix, key in Map("AxisLS", "JoyLS", "AxisRS", "JoyRS") {
            selected := false
            for value in this.CheckedArr {
                if (value == key || InStr(value, prefix == "AxisLS" ? "JoyAxisL" : "JoyAxisR") == 1) {
                    selected := true
                    break
                }
            }
            try this.ui.Update("Pad_" prefix "KnobFill", "Fill", selected ? "{DynamicResource ActionBg}" : "{DynamicResource ControlBg}")
            try this.ui.Update("Pad_" prefix "KnobFill", "Stroke", selected ? "{DynamicResource ActionStroke}" : "{DynamicResource ControlBorder}")
            try this.ui.Update("Pad_" prefix "Tag", "Foreground", selected ? "{DynamicResource ActionText}" : "{DynamicResource TextMain}")
        }
    }

    _PlaceKey(value, display, x, y, width, height := 25) {
        global MySoftData
        this._keySeq += 1
        name := "KeyBtn_" this._keySeq
        txtName := name "_Txt"
        btn := this._keyGrid.Add("Button").Name(name).Width(width).Height(height)
            .SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
            .Cursor("Hand").Tag("0")
            .HorizontalContentAlignment("Stretch").VerticalContentAlignment("Stretch")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        btn.InjectResources(this.EditorMode == "joy" ? StrReplace(FrontInfoGui._KeyPickBtnStyle(), 'CornerRadius="3"', 'CornerRadius="12"') : FrontInfoGui._KeyPickBtnStyle())
        ; 按钮模板不读取 Padding，直接为文字留出内边距。
        vb := this._KeyLabelBox(btn).Margin("2,1").HorizontalAlignment("Center").VerticalAlignment("Center")
        tb := vb.Add("TextBlock").Name(txtName).Text(display).FontSize(11)
            .Foreground("{DynamicResource TextMain}")
            .TextAlignment("Center").TextWrapping("NoWrap")
        ff := MySoftData.GetJoyBtnFontFamily(value)
        if (ff != "")
            tb.FontFamily(ff)
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

    }

    ; 手柄触发键直接复用 JoyGui 的真实绘制代码，避免两套手柄视觉漂移。
    _BuildJoyGrid() {
        builder := JoyGui()
        builder._pad := this._keyGrid
        builder._btnKeyMap := Map()
        builder._btnDefBg := Map()
        builder._btnDefBd := Map()
        builder._padBtnLayout := Map()
        builder._stickLayout := Map()
        builder._axisGroup := ""
        builder._BuildPad()
        this._joyVisualBuilder := builder
        this._joyBtnDefBg := builder._btnDefBg
        this._joyBtnDefBd := builder._btnDefBd
        this._joyAxisCenters := Map()

        ; JoyGui 保存短键名，触发键编辑器统一保存 Joy 前缀内部键名。
        for name, shortKey in builder._btnKeyMap {
            joyKey := this._ToTriggerJoyKey(shortKey)
            if (joyKey == "")
                continue
            this._btnKeyMap.Set(name, joyKey)
            this.ConMap.Set(joyKey, name)
        }

        ; JoyGui 的摇杆是拖拽控件；触发键编辑需要可点击的 L/R、四方向区域。
        isPs5 := (IsSet(MainSoftData) && MainSoftData.TriggerJoyType == "PS5")
        this._AddJoyAxisPickers("AxisL", isPs5 ? 238 : 198, isPs5 ? 238 : 142)
        this._AddJoyAxisPickers("AxisR", 402, 238)
    }

    _AddJoyAxisPickers(prefix, cx, cy) {
        this._joyAxisCenters[prefix] := {x: cx, y: cy}
        ; 用透明按钮承接鼠标捕获。直接拖动圆形图形时，WPF 在鼠标离开
        ; 摇杆控件后可能停止向画布派发 MouseMove；透明按钮会在按下后
        ; 自动捕获鼠标，同时不改变宏指令-手柄的视觉。
        overlayName := "Trigger_" prefix "_Overlay"
        overlay := this._keyGrid.Add("Button").Name(overlayName).Width("86").Height("86")
            .SetProp("Canvas.Left", String(cx - 43)).SetProp("Canvas.Top", String(cy - 43))
            .SetProp("Panel.ZIndex", "20").Background("#00FFFFFF").BorderBrush("#00FFFFFF")
            .BorderThickness("0").Padding("0").Cursor("SizeAll")
        overlay.InjectResources('<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="Transparent" BorderThickness="0"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>')
        ; 隐藏控件仅用于保留 JoyLS/JoyRS 的配置映射；可见交互由上面的透明捕获层和画布处理。
        centerName := "Trigger_" prefix "_Center"
        this._keyGrid.Add("Button").Name(centerName).Width("1").Height("1").Visibility("Collapsed")
        this._joyBtnDefBg.Set(centerName, "Transparent")
        this._joyBtnDefBd.Set(centerName, "Transparent")
        this.ConMap.Set(prefix == "AxisL" ? "JoyLS" : "JoyRS", centerName)

        axisKeys := prefix == "AxisL"
            ? ["JoyAxisLYMin", "JoyAxisLYMax", "JoyAxisLXMin", "JoyAxisLXMax"]
            : ["JoyAxisRYMin", "JoyAxisRYMax", "JoyAxisRXMin", "JoyAxisRXMax"]
        ; 保留不可见控件作为状态映射，触发键配置仍可回显，但界面不再显示四个浮动按钮。
        for i, key in axisKeys {
            name := "Trigger_" prefix "_Axis" i
            this._keyGrid.Add("Button").Name(name).Visibility("Collapsed")
            this._btnKeyMap.Set(name, key)
            this._joyBtnDefBg.Set(name, "{DynamicResource ControlBg}")
            this._joyBtnDefBd.Set(name, "{DynamicResource ControlBorder}")
            this.ConMap.Set(key, name)
        }
        ; 方向按钮不再覆盖摇杆。拖拽结束后由 _SelectJoyAxisDirections 按终点方向自动选值。
    }

    _JoyEventXY(state) {
        raw := ""
        if (IsObject(state)) {
            if (state.Has("TriggerPadCanvas"))
                raw := state["TriggerPadCanvas"]
            else if (state.Has("PreviewMouseLeftButtonDown"))
                raw := state["PreviewMouseLeftButtonDown"]
            else if (state.Has("PreviewMouseMove"))
                raw := state["PreviewMouseMove"]
            else if (state.Has("PreviewMouseLeftButtonUp"))
                raw := state["PreviewMouseLeftButtonUp"]
        }
        if (!InStr(raw, ","))
            return {x: -1, y: -1}
        p := StrSplit(raw, ",")
        try return {x: Integer(p[1]), y: Integer(p[2])}
        return {x: -1, y: -1}
    }

    _HitJoyAxisDirection(px, py) {
        if (px < 0)
            return ""
        for prefix, center in this._joyAxisCenters {
            dirs := [
                {key: "up", x: center.x - 16, y: center.y - 52},
                {key: "down", x: center.x - 16, y: center.y + 20},
                {key: "left", x: center.x - 52, y: center.y - 16},
                {key: "right", x: center.x + 20, y: center.y - 16}
            ]
            for d in dirs
                if (px >= d.x && px <= d.x + 32 && py >= d.y && py <= d.y + 32)
                    return prefix
        }
        return ""
    }

    _HitJoyAxis(px, py) {
        if (px < 0)
            return ""
        for prefix, center in this._joyAxisCenters {
            dx := px - center.x, dy := py - center.y
            if (dx * dx + dy * dy <= 43 * 43)
                return prefix
        }
        return ""
    }

    OnJoyPadMouseDown(state, *) {
        xy := this._JoyEventXY(state)
        id := this._HitJoyAxis(xy.x, xy.y)
        if (id == "")
            return
        this._joyDrag := id
        this._joyDragMoved := false
        this._joyDragStartX := xy.x, this._joyDragStartY := xy.y
        this._joyDragLastX := xy.x, this._joyDragLastY := xy.y
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        this._joyScreenOriginX := sx - xy.x, this._joyScreenOriginY := sy - xy.y
        SetTimer(this._joyDragTick, 16)
        this._UpdateTriggerStickKnob(id, xy.x, xy.y)
    }

    OnJoyPadMouseMove(state, *) {
        if (this._joyDrag == "")
            return
        xy := this._JoyEventXY(state)
        if (xy.x < 0)
            return
        this._joyDragLastX := xy.x, this._joyDragLastY := xy.y
        dx := xy.x - this._joyDragStartX, dy := xy.y - this._joyDragStartY
        if (!this._joyDragMoved && dx * dx + dy * dy < 36)
            return
        this._joyDragMoved := true
        this._UpdateTriggerStickKnob(this._joyDrag, xy.x, xy.y)
    }

    OnJoyPadMouseUp(state, *) {
        if (this._joyDrag == "")
            return
        id := this._joyDrag
        moved := this._joyDragMoved
        xy := this._JoyEventXY(state)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        screenXY := {x: sx - this._joyScreenOriginX, y: sy - this._joyScreenOriginY}
        ; 某些 WPF/自动化拖拽只产生按下和抬起事件，没有中间 MouseMove。
        ; 以抬起时的屏幕坐标补判移动，否则会被误判成一次点击。
        eventMoved := (xy.x >= 0 && (xy.x != this._joyDragStartX || xy.y != this._joyDragStartY))
        screenMoved := (screenXY.x != this._joyDragStartX || screenXY.y != this._joyDragStartY)
        if (eventMoved || screenMoved)
            moved := true
        if (xy.x < 0 || screenMoved)
            xy := screenXY
        this._joyDrag := ""
        this._joyDragMoved := false
        SetTimer(this._joyDragTick, 0)
        this._UpdateTriggerStickKnob(id, xy.x, xy.y)
        if (!moved) {
            this.OnCheckedKey(id == "AxisL" ? "JoyLS" : "JoyRS")
            return
        }
        center := this._joyAxisCenters[id]
        this._SelectJoyAxisDirections(id, xy.x - center.x, xy.y - center.y)
    }

    _SelectJoyAxisDirections(prefix, dx, dy) {
        axisKeys := prefix == "AxisL"
            ? ["JoyAxisLYMin", "JoyAxisLYMax", "JoyAxisLXMin", "JoyAxisLXMax"]
            : ["JoyAxisRYMin", "JoyAxisRYMax", "JoyAxisRXMin", "JoyAxisRXMax"]
        stickKey := prefix == "AxisL" ? "JoyLS" : "JoyRS"
        ; 清除同一摇杆旧的方向及按下状态，再写入拖动终点对应的方向。
        for key in axisKeys {
            for i, value in this.CheckedArr {
                if (value == key) {
                    this.CheckedArr.RemoveAt(i)
                    break
                }
            }
            if (this.ConMap.Has(key))
                this._SetKeyBtnState(this.ConMap[key], key, false)
        }
        for i, value in this.CheckedArr {
            if (value == stickKey) {
                this.CheckedArr.RemoveAt(i)
                break
            }
        }
        wanted := []
        visualDx := 0
        visualDy := 0
        ; 斜向拖动按主方向取值，例如右上优先选“右”，避免一次生成两个方向。
        ax := Abs(dx), ay := Abs(dy)
        if (Max(ax, ay) >= 12) {
            if (ax >= ay) {
                wanted.Push(dx < 0 ? axisKeys[3] : axisKeys[4])
                visualDx := dx < 0 ? -22 : 22
            }
            else {
                wanted.Push(dy < 0 ? axisKeys[2] : axisKeys[1])
                visualDy := dy < 0 ? -22 : 22
            }
        }
        for key in wanted {
            this.CheckedArr.Push(key)
            if (this.ConMap.Has(key))
                this._SetKeyBtnState(this.ConMap[key], key, true)
        }
        center := this._joyAxisCenters[prefix]
        this._UpdateTriggerStickKnob(prefix, center.x + visualDx, center.y + visualDy)
        this.Refresh()
    }

    OnJoyDragTick(*) {
        if (this._joyDrag == "")
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        px := sx - this._joyScreenOriginX, py := sy - this._joyScreenOriginY
        center := this._joyAxisCenters[this._joyDrag]
        dx := px - center.x, dy := py - center.y
        if (!this._joyDragMoved && dx * dx + dy * dy < 36)
            return
        this._joyDragMoved := true
        this._joyDragLastX := px, this._joyDragLastY := py
        this._UpdateTriggerStickKnob(this._joyDrag, px, py)
    }

    _UpdateTriggerStickKnob(id, px, py) {
        if (!IsObject(this.ui) || !this._joyAxisCenters.Has(id))
            return
        center := this._joyAxisCenters[id]
        dx := px - center.x, dy := py - center.y
        maxR := 22
        len := Sqrt(dx * dx + dy * dy)
        if (len > maxR && len > 0) {
            dx := dx * maxR / len
            dy := dy * maxR / len
        }
        ; 与 JoyGui._CenterStickKnob 使用同一套圆形范围和坐标换算。
        ; JoyGui._PlaceStick 使用 9px 安全边距和 17px 旋钮井半径。
        ; 这里保持同一坐标系，确保拖到边缘时旋钮完整显示。
        kx := 26 + dx
        ky := 26 + dy
        visualId := id == "AxisL" ? "AxisLS" : "AxisRS"
        try this.ui.Update("Pad_" visualId "Knob", "Margin", Round(kx) "," Round(ky) ",0,0")
    }

    _ToTriggerJoyKey(shortKey) {
        static direct := Map(
            "A", "JoyA", "B", "JoyB", "X", "JoyX", "Y", "JoyY",
            "LB", "JoyLB", "RB", "JoyRB", "LT", "JoyLT", "RT", "JoyRT",
            "LS", "JoyLS", "RS", "JoyRS", "Home", "JoyHome", "Back", "JoyBack",
            "Pad", "JoyPad", "Start", "JoyStart",
            "DpadUp", "JoyDpadUp", "DpadDown", "JoyDpadDown",
            "DpadLeft", "JoyDpadLeft", "DpadRight", "JoyDpadRight", "DpadNone", "JoyDpadNone",
            "上", "JoyDpadUp", "下", "JoyDpadDown", "左", "JoyDpadLeft", "右", "JoyDpadRight", "无方向", "JoyDpadNone",
            "AxisLS", "JoyLS", "AxisRS", "JoyRS", "AxisLT", "JoyLT", "AxisRT", "JoyRT")
        return direct.Get(shortKey, "")
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
            infoStr .= InStr(value, "Joy") ? MySoftData.GetJoyDisplayName(value) : value
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

        if (this.EditorMode == "joy" || hasJoy || this.IsToolEdit) {
            this.ui.Update("EnableTriggerKeyCon", "IsEnabled", this.IsToolEdit ? "False" : "True")
        }
        else {
            this.ui.Update("EnableTriggerKeyCon", "IsEnabled", "True")
        }

        isValid := this.CheckConfigValid()
        this.ui.Update("CheckedInvalidTipCon", "Visibility", isValid ? "Collapsed" : "Visible")
        this.ui.Update("CheckedInfoCon", "Text", lable infoStr)
        this.UpdateJoyBtnDisplay()
        this._RefreshJoyStickHighlight()

        ; 顺序触发：仅当非特殊按键多选时可用，否则禁用并灰显
        nonSpecialKeyNum := this.CountNonSpecialKeys()
        if (this.EditorMode != "joy" && !this.IsToolEdit && nonSpecialKeyNum >= 2) {
            this.ui.Update("UnorderedTriggerCon", "IsEnabled", "True")
        }
        else {
            this.ui.Update("UnorderedTriggerCon", "IsEnabled", "False")
            this.ui.Update("UnorderedTriggerCon", "IsChecked", "False")
            if (this.EditorMode == "joy")
                this.ui.Update("UnorderedTriggerCon", "Visibility", "Collapsed")
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

    ; 触发键编辑器中的 LT/RT 是数字触发键（JoyLT/JoyRT），没有宏指令编辑器
    ; 的连续轴值模式，因此让 JoyPickerHook 按按钮边沿处理。
    _LtRtAsButton() {
        return true
    }

    _OnLiveButton(short) {
        if (!this._UiAlive())
            return
        if (this.HasProp("_joyUserOff") && IsObject(this._joyUserOff) && this._joyUserOff.Has(short))
            return
        key := this._ToTriggerJoyKey(short)
        if (key == "" || !this.ConMap.Has(key))
            return
        this._joyLiveClick := true
        try this.OnCheckedKey(key)
        finally this._joyLiveClick := false
    }

    ; 触发键只需要选择摇杆方向，不需要把每一帧的模拟量写入配置。
    ; 仅在方向桶发生变化时更新，避免微小漂移导致按钮反复闪烁。
    _ApplyLiveStick(id, a1, a2, x, y) {
        if (!this._UiAlive())
            return
        if (!this.HasProp("_joyAxisSeen") || !IsObject(this._joyAxisSeen))
            this._joyAxisSeen := Map()
        if (Sqrt(x * x + y * y) < 20) {
            this._joyAxisSeen[id] := ""
            return
        }
        prefix := id == "AxisLS" ? "AxisL" : "AxisR"
        ; XInput 的 LY/RY 正方向与屏幕坐标相反：手柄向上为正值，
        ; 界面坐标向下才是正值。自动选择前先翻转 Y，避免上下轴倒置。
        screenY := -y
        ax := Abs(x), ay := Abs(screenY)
        bucket := ax >= ay ? (x < 0 ? "L" : "R") : (screenY < 0 ? "U" : "D")
        if (this._joyAxisSeen.Get(id, "") == bucket)
            return
        this._joyAxisSeen[id] := bucket
        this._joyLiveClick := true
        try this._SelectJoyAxisDirections(prefix, x, screenY)
        finally this._joyLiveClick := false
    }

    _ApplyLiveTriggersExclusive(lt, rt) {
        ; 当前编辑器将 LT/RT 作为按钮处理，保留空实现以满足 JoyPickerHook 接口。
    }

    OnWindowLoad(token, state, ctrl, event) {
        if (!IsObject(this._uiToken) || this._uiToken != token)
            return
        ; 窗口切换时旧窗口的 LoadedHwnd 可能晚到，不能再访问已被清空的 ui。
        ui := this.ui
        if (!IsObject(ui))
            return
        XamlWin.OnLoadTheme(ui)
        if (this.EditorMode == "joy")
            try JoyPickerHook.Attach(this)
        ; ScaleFontSize 有主题下限，声明 FontSize(9) 会被抬回主题字号；用 Relative 写入才真正 -2
        helpFs := XAMLHost.FormatFontSize(XAMLHost.ScaleFontSizeRelative(XAMLHost.GetDesignFontSize() - 2))
        prevSkip := ui.HasProp("skipFontScale") ? ui.skipFontScale : false
        ui.skipFontScale := true
        loop 4 {
            try ui.Update("HelpTip" A_Index, "FontSize", String(helpFs))
        }
        if (IsObject(this.ui) && this.ui == ui)
            this.ui.skipFontScale := prevSkip
    }

    OnWindowClosing(token, state, ctrl, event) {
        if (!IsObject(this._uiToken) || this._uiToken != token)
            return
        try JoyPickerHook.Detach(this)
        SetTimer(this._joyDragTick, 0)
        this._joyDrag := ""
        this.ui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        try JoyPickerHook.Detach(this)
        SetTimer(this._joyDragTick, 0)
        this._joyDrag := ""
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
