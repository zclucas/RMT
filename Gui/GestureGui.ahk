OnItemEditGesture(tableItem, index, source, *) {
    item := GetItemByIndex(tableItem, index)
    if (item)
        SetTimer(ShowGestureEditor.Bind(tableItem.ID, item.ID, source), -1)
}

OnFoldEditGesture(tableItem, index, source, *) {
    if (tableItem.Folds.Has(index))
        SetTimer(ShowGestureEditor.Bind(tableItem.ID, tableItem.Folds[index].ID, source, true), -1)
}

ShowGestureEditor(tableID, targetID, source, isFold := false) {
    if (GestureTriggers.ShuttingDown)
        return
    if (GestureTriggers.Editing) {
        hwnd := GestureTriggers.Editing.Hwnd()
        if (hwnd)
            WinActivate("ahk_id " hwnd)
        return
    }
    if (isFold) {
        tableItem := GetTableByID(tableID)
        fold := tableItem ? tableItem.GetFold(targetID) : ""
        if (fold) {
            MyMainWin.ReadTabValues(tableItem)
            GestureGui(tableID, targetID, source, fold.GestureTK, fold.Remark, true)
        }
    } else if (resolved := ResolveMacroItem(tableID, targetID)) {
        MyMainWin.ReadTabValues(resolved.Table)
        GestureGui(tableID, targetID, source, resolved.Item.TK, resolved.Item.Remark)
    }
}

class GestureGui {
    static PreviewSize := 154

    __New(tableID, targetID, source, value, remark, isFold := false) {
        this.TableID := tableID
        this.TargetID := targetID
        this.IsFold := isFold
        this.Source := source
        this.MouseKeys := ["LButton", "MButton", "RButton", "XButton1", "XButton2", "WheelLeft", "WheelRight"]
        this.ShapeIDs := []
        this.Custom := ""
        this.CustomPreview := []
        this.ClearPending := false
        this.Recording := false
        this.SampleCallback := this.Sample.Bind(this)
        this.Owner := MainSoftData.MyGui.Hwnd
        this.RestoreOwner := false

        binding := GestureBinding(value, source)
        current := GestureRead(binding)
        mouse := source == "Mouse"
        body := XAML_Generator("DockPanel").Margin("16,12").LastChildFill("True")
        buttons := body.Add("DockPanel").DockPanel_Dock("Bottom").LastChildFill("False").Margin("0,10,0,0")
        AddCmdOkBtn(buttons, "ClearGesture", "", GetLang("清除")).DockPanel_Dock("Left").Width(96)
        AddCmdOkBtn(buttons, "SaveGesture", "8,0,0,0", GetLang("确定")).DockPanel_Dock("Right").IsDefault("True")
        AddCmdOkBtn(buttons, "CancelGesture", "", GetLang("取消")).DockPanel_Dock("Right")
        panel := body.Add("StackPanel")
        if (mouse)
            this.BuildMouse(panel, current, binding)
        else
            this.BuildTouch(panel, current)
        panel.Add("TextBlock").Name("GestureHint").TextWrapping("Wrap").Margin("0,8,0,0")
            .Text(mouse ? this.MouseHint() : GetLang("使用 Windows 精确式触控板，松开手指时触发宏。"))

        title := GetLang(mouse ? "鼠标手势" : "触控板手势") (remark == "" ? "" : " · " remark)
        this.UI := XamlWin.Create(title, body, 460, mouse ? 370 : 275)
        this.UI.OnEvent("Window", "Closing", this.Close.Bind(this, false))
        this.UI.OnEvent("Window", "KeyDown:Escape", this.Close.Bind(this, true))
        this.UI.OnEvent("CancelGesture", "Click", this.Close.Bind(this, true))
        this.UI.OnEvent("ClearGesture", "Click", this.Clear.Bind(this))
        this.UI.OnEvent("SaveGesture", "Click", this.Save.Bind(this))
        if (mouse) {
            InstallMouseHook()
            this.UI.OnEvent("MouseKey", "SelectionChanged", this.OnMouseKey.Bind(this))
            this.UI.OnEvent("Shape", "SelectionChanged", this.OnShape.Bind(this))
            this.UI.OnEvent("GesturePad", "MouseLeftButtonDown", this.StartRecording.Bind(this))
        } else {
            for name in ["FingerCount", "TouchAction"]
                this.UI.Track(name)
            for index, key in GestureModifierKeys()
                this.UI.OnEvent("TouchModifier" index, "Click", this.UpdateModifierHint.Bind(this))
        }

        GestureTriggers.Editing := this
        try {
            if (!XamlWin.Open(this.UI, , this.Owner)) {
                this.Close(true)
                return
            }
            if (GestureTriggers.Editing != this)
                return
            this.RestoreOwner := DllCall("IsWindowEnabled", "Ptr", this.Owner)
            if (this.RestoreOwner)
                DllCall("EnableWindow", "Ptr", this.Owner, "Int", false)
        } catch as err {
            this.Close(true)
            throw err
        }
    }

    Hwnd() => this.UI.HasProp("wpfHwnd") ? this.UI.wpfHwnd : 0

    AddCombo(panel, name, label, selected) {
        row := panel.Add("Grid").Margin("0,0,0,8").Cols("110", "*")
        row.Add("TextBlock").Text(GetLang(label) ":").HorizontalAlignment("Right")
            .VerticalAlignment("Center").Margin("0,0,8,0")
        return row.Add("ComboBox").Grid_Column(1).Name(name).MinHeight(28).SelectedIndex(selected - 1)
    }

    BuildTouch(panel, current) {
        fingers := this.AddCombo(panel, "FingerCount", "手指数量", current ? current.Fingers : 1)
        for index, label in GestureFingerNames()
            fingers.Add("ComboBoxItem").Tag(index).Content(GetLang(label))
        actions := this.AddCombo(panel, "TouchAction", "动作", current ? current.Action : 1)
        for index, label in GestureTouchActions()
            actions.Add("ComboBoxItem").Tag(index).Content(GetLang(label))
        modifiers := current ? current.Modifiers : 0
        if (modifiers == 128)
            modifiers := 0x0A ; 旧 Ctrl+Alt 配置在编辑时提供左侧按键作为初始选项。
        row := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
            .InjectResources(XamlTabOptionStyle())
        keys := GestureModifierKeys()
        for index, key in keys {
            row.Add("ToggleButton").Name("TouchModifier" index).Content(key[1]).Width(54)
                .Margin(index == keys.Length ? "0,4,0,4" : "0,4,5,4")
                .Style("{StaticResource SetTabButton}").IsChecked(modifiers & (1 << (index - 1)) ? "True" : "False")
        }
        panel.Add("TextBlock").Name("TouchModifierHint").Text(this.ModifierHint(modifiers)).TextWrapping("Wrap")
            .Visibility(modifiers ? "Visible" : "Collapsed")
    }

    SelectedModifiers(state) {
        mask := 0
        for index, key in GestureModifierKeys() {
            if (state.Get("TouchModifier" index, "") == "True")
                mask |= 1 << (index - 1)
        }
        return mask
    }

    ModifierHint(mask) => mask ? Format(GetLang("仅在按住 {1} 时触发"), GestureModifierLabel(mask)) : ""

    UpdateModifierHint(state, *) {
        if (GestureTriggers.Editing != this)
            return
        mask := this.SelectedModifiers(state)
        this.UI.BatchUpdate([
            {ControlName: "TouchModifierHint", PropertyName: "Text", Value: this.ModifierHint(mask)},
            {ControlName: "TouchModifierHint", PropertyName: "Visibility", Value: mask ? "Visible" : "Collapsed"}
        ])
    }

    BuildMouse(panel, current, binding) {
        this.KeyIndex := 3
        if (current) {
            for index, key in this.MouseKeys {
                if (key == current.Key)
                    this.KeyIndex := index
            }
            if (current.Shape == "Custom")
                this.Custom := StrSplit(binding, "|")[3]
        }
        keyCombo := this.AddCombo(panel, "MouseKey", "鼠标按键", this.KeyIndex)
        for index, key in this.MouseKeys
            keyCombo.Add("ComboBoxItem").Tag(index).Content(GetLang(GestureMouseKeys()[key]))

        ; Tilt 保留在列表末尾，仅横向滚轮可选。改变按键时轨迹项的序号保持不变。
        this.ShapeIDs := ["Custom"]
        for preset in GesturePath.Presets()
            this.ShapeIDs.Push(preset[1])
        this.ShapeIDs.Push("Tilt")
        this.ShapeIndex := 1
        for index, id in this.ShapeIDs {
            if (id == (current ? current.Shape : "Custom"))
                this.ShapeIndex := index
        }
        shapes := this.AddCombo(panel, "Shape", "手势轨迹", this.ShapeIndex).MaxDropDownHeight(340)
        chevrons := Map("Caret", 0xE96D, "V", 0xE96E, "CaretLeft", 0xE96F, "CaretRight", 0xE970)
        for index, id in this.ShapeIDs {
            item := shapes.Add("ComboBoxItem").Tag(index).MinHeight(24).VerticalContentAlignment("Center")
            label := GetLang(GesturePath.Labels()[id])
            if (id == "Tilt") {
                item.Name("TiltShape").Content(label).Visibility(this.IsWheel() ? "Visible" : "Collapsed")
            } else if (chevrons.Has(id)) {
                item.AutomationProperties_Name(label).HorizontalContentAlignment("Left")
                item.Add("TextBlock").Text(Chr(chevrons[id])).Width(16).TextAlignment("Center")
                    .HorizontalAlignment("Left").FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            } else if (SubStr(id, 1, 1) == "L" && id != "Left") {
                this.BuildElbowLabel(item, GesturePath.Labels()[id])
            } else {
                item.Content(GetLang(GesturePath.Labels()[id]))
            }
        }

        size := GestureGui.PreviewSize
        pad := panel.Add("Border").Name("GesturePad").Height(size).CornerRadius(5).ClipToBounds("True")
            .BorderThickness(1).BorderBrush("{DynamicResource OutlineStroke}").Background("{DynamicResource ControlBg}")
        canvas := pad.Add("Canvas").Name("GesturePreview").Width(size).Height(size).HorizontalAlignment("Center")
            .VerticalAlignment("Center").IsHitTestVisible("False")
        canvas.Add("Border").Name("GesturePreviewEnd").Canvas_Left(size).Canvas_Top(size).Width(1).Height(1).Opacity(0)
        geometry := this.Geometry(this.PreviewPoints())
        canvas.Add("Path").Name("GestureLine").Stroke("{DynamicResource Accent}").StrokeThickness(3)
            .StrokeStartLineCap("Round").StrokeEndLineCap("Round").StrokeLineJoin("Round").Data(geometry[1])
        canvas.Add("Path").Name("GestureStart").Fill("{DynamicResource Accent}").Data(geometry[2])
    }

    BuildElbowLabel(item, label) {
        symbols := StrSplit(label, " ")
        corner := symbols[1], arrow := symbols[2]
        row := item.AutomationProperties_Name(label).Add("StackPanel").Orientation("Horizontal")
            .HorizontalAlignment("Left").VerticalAlignment("Center")
        ; 方框符号只占字格上半或下半，按字形实际位置对齐箭头。
        row.Add("TextBlock").Text(corner).FontFamily("Segoe UI Symbol").FontSize(16)
            .Add("TextBlock.RenderTransform").Add("TranslateTransform").Y(corner == "┌" || corner == "┐" ? -6 : 1)
        row.Add("TextBlock").Text(arrow).FontFamily("Segoe UI Symbol").FontSize(16).Margin("2,0,0,0")
            .Add("TextBlock.RenderTransform").Add("TranslateTransform").Y(arrow == "↑" || arrow == "↓" ? -1.3 : -2)
    }

    IsWheel() => GestureIsWheel(this.MouseKeys[this.KeyIndex])

    OnMouseKey(state, *) {
        index := Integer(state.Get("MouseKey", "") != "" ? state["MouseKey"] : 0)
        if (GestureTriggers.Editing != this || !this.MouseKeys.Has(index))
            return
        this.KeyIndex := index
        this.UI.Update("TiltShape", "Visibility", this.IsWheel() ? "Visible" : "Collapsed")
        if (!this.IsWheel() && this.ShapeIDs[this.ShapeIndex] == "Tilt") {
            this.ShapeIndex := 1
            this.UI.Update("Shape", "SelectedIndex", "0")
        }
        this.UpdatePreview()
    }

    OnShape(state, *) {
        index := Integer(state.Get("Shape", "") != "" ? state["Shape"] : 0)
        if (GestureTriggers.Editing != this || !this.ShapeIDs.Has(index))
            return
        this.ShapeIndex := index
        if (this.ShapeIDs[index] != "Custom")
            this.ClearPending := false
        this.StopRecording()
        this.UpdatePreview()
    }

    PreviewPoints() {
        shape := this.ShapeIDs[this.ShapeIndex]
        if (shape == "Custom")
            return this.Custom == "" ? [] : GestureRead("Mouse|LButton|" this.Custom).Path[1]
        if (shape == "Tilt")
            return []
        return GesturePath.PreviewPoints(shape, GesturePath.Shapes()[shape][1])
    }

    Geometry(points, useCanvasCoords := false) {
        origin := useCanvasCoords ? 0 : GestureGui.PreviewSize / 2
        scale := useCanvasCoords ? 1 : 118
        ; 自定义轨迹沿尾段回看，避免单个抖动采样点决定箭头。
        tailDistance := this.ShapeIDs[this.ShapeIndex] == "Custom" ? 20 : 0
        return GesturePath.PreviewGeometry(points, origin, origin, scale, 4, 10, tailDistance)
    }

    MouseHint() {
        switch this.ShapeIDs[this.ShapeIndex] {
            case "Custom": return GetLang("在此区域按住左键绘制自定义轨迹")
            case "Tilt": return GetLang("倾斜滚轮即可触发。同方向也绑定了轨迹时，停住鼠标后区分。")
            default:
                return this.IsWheel()
                    ? GetLang("向左或右倾斜滚轮一次。选择轨迹时，随后移动鼠标并停住。")
                    : GetLang("按住所选鼠标键绘制轨迹，松开时识别。前台应用仍会收到鼠标操作。")
        }
    }

    UpdatePreview(hint := "") {
        useCanvasCoords := this.ShapeIDs[this.ShapeIndex] == "Custom" && this.CustomPreview.Length
        this.DrawPreview(useCanvasCoords ? this.CustomPreview : this.PreviewPoints(), hint == "" ? this.MouseHint() : hint, useCanvasCoords)
    }

    DrawPreview(points, hint, useCanvasCoords := false) {
        geometry := this.Geometry(points, useCanvasCoords)
        this.UI.BatchUpdate([
            {ControlName: "GestureLine", PropertyName: "Data", Value: geometry[1]},
            {ControlName: "GestureStart", PropertyName: "Data", Value: geometry[2]},
            {ControlName: "GestureHint", PropertyName: "Text", Value: hint}
        ])
    }

    StartRecording(state, *) {
        if (GestureTriggers.Editing != this || this.ShapeIDs[this.ShapeIndex] != "Custom"
            || !GetKeyState("LButton", "P"))
            return
        bounds := this.UI.Query("GesturePad>ScreenOrigin", "GesturePreview>ScreenOrigin", "GesturePreviewEnd>ScreenOrigin")
        pad := StrSplit(bounds.Get("GesturePad>ScreenOrigin", ""), ",")
        origin := StrSplit(bounds.Get("GesturePreview>ScreenOrigin", ""), ",")
        end := StrSplit(bounds.Get("GesturePreviewEnd>ScreenOrigin", ""), ",")
        click := StrSplit(state.Get("GesturePad", ""), ",")
        if (pad.Length != 2 || origin.Length != 2 || end.Length != 2 || click.Length != 2
            || end[1] <= origin[1] || end[2] <= origin[2]
            || GestureTriggers.Editing != this || this.ShapeIDs[this.ShapeIndex] != "Custom")
            return
        ; WPF 的屏幕原点包含窗口 DPI 和界面缩放，录制期间使用同一套坐标。
        size := GestureGui.PreviewSize
        this.PreviewOrigin := origin
        this.PreviewScale := [(end[1] - origin[1]) / size, (end[2] - origin[2]) / size]
        start := [pad[1] + click[1] * this.PreviewScale[1], pad[2] + click[2] * this.PreviewScale[2]]
        this.Recording := true
        this.Points := [start]
        this.RecordingPreview := [this.LocalPoint(start)]
        this.DrawPreview(this.RecordingPreview, GetLang("正在录制轨迹…"), true)
        SetTimer(this.SampleCallback, 15)
    }

    LocalPoint(point) {
        return [(point[1] - this.PreviewOrigin[1]) / this.PreviewScale[1],
            (point[2] - this.PreviewOrigin[2]) / this.PreviewScale[2]]
    }

    Sample() {
        if (!this.Recording)
            return
        if (!WinActive("ahk_id " this.Hwnd())) {
            this.StopRecording()
            this.UpdatePreview()
            return
        }
        cursor := Buffer(8)
        if (!DllCall("GetPhysicalCursorPos", "Ptr", cursor))
            return
        point := [NumGet(cursor, 0, "Int"), NumGet(cursor, 4, "Int")]
        if (!GetKeyState("LButton", "P")) {
            this.StopRecording()
            if (GesturePath.Distance(point, this.Points[-1]) > 0) {
                this.Points.Push(point)
                this.RecordingPreview.Push(this.LocalPoint(point))
            }
            points := GesturePath.Normalize(this.Points, 25)
            if (points.Length) {
                this.Custom := GesturePath.Encode(points)
                this.CustomPreview := this.RecordingPreview
                this.ClearPending := false
            }
            hint := points.Length ? "轨迹已录制，可重新绘制"
                : (this.Custom == "" ? "轨迹太短，请重新绘制" : "轨迹太短，已保留上一次录制。")
            this.UpdatePreview(GetLang(hint))
        } else if (this.Points.Length < 1000 && GesturePath.Distance(point, this.Points[-1]) >= 2) {
            this.Points.Push(point)
            this.RecordingPreview.Push(this.LocalPoint(point))
            this.DrawPreview(this.RecordingPreview, GetLang("正在录制轨迹…"), true)
        }
    }

    StopRecording() {
        this.Recording := false
        SetTimer(this.SampleCallback, 0)
    }

    Clear(*) {
        if (GestureTriggers.Editing != this)
            return
        this.ClearPending := true
        if (this.Source == "Touch") {
            updates := [
                {ControlName: "FingerCount", PropertyName: "SelectedIndex", Value: "-1"},
                {ControlName: "TouchAction", PropertyName: "SelectedIndex", Value: "-1"},
                {ControlName: "TouchModifierHint", PropertyName: "Visibility", Value: "Collapsed"}
            ]
            for index, key in GestureModifierKeys()
                updates.Push({ControlName: "TouchModifier" index, PropertyName: "IsChecked", Value: "False"})
            this.UI.BatchUpdate(updates)
        } else {
            this.StopRecording()
            this.Custom := ""
            this.CustomPreview := []
            this.ShapeIndex := 1
            this.UI.Update("Shape", "SelectedIndex", "0")
            this.UpdatePreview()
        }
    }

    Save(state, *) {
        if (GestureTriggers.Editing != this)
            return
        binding := ""
        if (this.Source == "Touch") {
            fingers := Integer(state.Get("FingerCount", "") != "" ? state["FingerCount"] : 0)
            action := Integer(state.Get("TouchAction", "") != "" ? state["TouchAction"] : 0)
            modifiers := this.SelectedModifiers(state)
            if (!this.ClearPending || fingers || action || modifiers) {
                if (!GestureFingerNames().Has(fingers) || !GestureTouchActions().Has(action)) {
                    this.UI.Update("GestureHint", "Text", GetLang("请选择手指数量和动作"))
                    return
                }
                binding := "Touchpad|" fingers "|" action "|" (modifiers ? "m" modifiers : "0")
            }
        } else if (!this.ClearPending) {
            shape := this.ShapeIDs[this.ShapeIndex]
            if (shape == "Custom") {
                if (this.Custom == "") {
                    this.UI.Update("GestureHint", "Text", GetLang("请先绘制自定义轨迹"))
                    return
                }
                shape := this.Custom
            }
            binding := "Mouse|" this.MouseKeys[this.KeyIndex] "|" shape
        }
        if (this.IsFold) {
            tableItem := GetTableByID(this.TableID)
            target := tableItem ? tableItem.GetFold(this.TargetID) : ""
            property := "GestureTK"
        } else {
            resolved := ResolveMacroItem(this.TableID, this.TargetID)
            tableItem := resolved ? resolved.Table : ""
            target := resolved ? resolved.Item : ""
            property := "TK"
        }
        if (!target) {
            this.Close(true)
            return
        }
        previous := target.%property%
        value := GestureWithBinding(previous, this.Source, binding)
        if (previous == value) {
            this.Close(true)
            return
        }
        previousCritical := A_IsCritical
        Critical()
        target.%property% := value
        try {
            if (!SaveTableItemInfo(tableItem))
                throw Error(GetLang("无法写入当前配置"))
        } catch as err {
            target.%property% := previous
            this.UI.Update("GestureHint", "Text", GetLang("手势保存失败，请检查配置文件后重试。"))
            try RMTLogSys(RMT_LV_ERROR, "Gesture", err.Message)
            return
        } finally {
            Critical(previousCritical)
        }
        HotReloadPublish(tableItem.Index, 0, false)
        this.Close(true)
        if (!this.IsFold)
            MyMainWin.RefreshItemRow(tableItem.Index, resolved.Index)
    }

    CloseForExit() {
        this.RestoreOwner := false
        hwnd := this.Hwnd()
        if (hwnd)
            DllCall("user32\ShowWindowAsync", "Ptr", hwnd, "Int", 0) ; SW_HIDE
        this.Close(true)
    }

    Close(closeWindow, *) {
        if (GestureTriggers.Editing != this)
            return
        this.StopRecording()
        this.SampleCallback := ""
        GestureTriggers.Editing := false
        if (this.RestoreOwner)
            DllCall("EnableWindow", "Ptr", this.Owner, "Int", true)
        if (closeWindow)
            this.UI.Update("Window", "Close", "")
    }
}
