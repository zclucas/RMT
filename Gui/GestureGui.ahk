OnItemEditGesture(tableItem, index, *) {
    item := GetItemByIndex(tableItem, index)
    if (item)
        SetTimer(ShowGestureEditor.Bind(tableItem.ID, item.ID), -1)
}

ShowGestureEditor(tableID, itemID) {
    if (GestureTriggers.Editing) {
        WinActivate("ahk_id " GestureTriggers.Editing.Window.Hwnd)
        return
    }
    resolved := ResolveMacroItem(tableID, itemID)
    if (resolved) {
        MyMainWin.ReadTabValues(resolved.Table)
        GestureGui(tableID, itemID, resolved.Item.TK, resolved.Item.Remark)
    }
}

class GestureGui {
    __New(tableID, itemID, value, remark := "") {
        this.TableID := tableID
        this.ItemID := itemID
        this.MouseKeys := ["LButton", "MButton", "RButton", "XButton1", "XButton2", "WheelLeft", "WheelRight"]
        this.ShapeIDs := []
        this.Custom := ""
        this.Points := []
        this.WasDown := false
        this.Recording := false
        this.SampleCallback := ObjBindMethod(this, "Sample")
        this.Owner := MainSoftData.MyGui.Hwnd
        this.RestoreOwner := false

        title := GetLang("编辑手势") (remark == "" ? "" : " · " remark)
        this.Window := Gui("+Owner" this.Owner, title)
        win := this.Window
        win.MarginX := 16
        win.MarginY := 14
        win.SetFont("s10", "Segoe UI")
        win.AddText("xm ym+3 w105", GetLang("手势来源"))
        this.Source := win.AddDropDownList("x+8 yp-3 w333 Choose1", GetLangArr(["鼠标手势", "触控板手势"]))
        this.MouseLabel := win.AddText("xm y52 w105", GetLang("鼠标按键"))
        mouseLabels := []
        for key in this.MouseKeys
            mouseLabels.Push(GetLang(GestureMouseKeys()[key]))
        this.MouseKey := win.AddDropDownList("x+8 yp-3 w333 Choose3", mouseLabels)
        this.TouchLabel := win.AddText("xm y52 w105", GetLang("触控板手势"))
        this.Touch := win.AddDropDownList("x+8 yp-3 w333 Choose1", GetLangArr(GestureTouchNames()))
        this.ShapeLabel := win.AddText("xm y88 w105", GetLang("手势轨迹"))
        this.Shape := win.AddDropDownList("x+8 yp-3 w333", [])
        this.ShortcutLabel := win.AddText("xm y88 w105", GetLang("映射快捷键"))
        this.Shortcut := win.AddHotkey("x+8 yp-3 w229")
        this.ResetShortcut := win.AddButton("x+8 yp-1 w96 h26", GetLang("恢复默认"))
        this.ResetShortcut.OnEvent("Click", ObjBindMethod(this, "DefaultShortcut"))
        this.Pad := win.AddPicture("xm y122 w446 h112 +Border +0x200")
        this.TouchHelp := win.AddText("xm y122 w446 h50", GetLang("在 Windows 触控板的高级手势中，为所选动作录入这里的快捷键。"))
        this.OpenSettings := win.AddButton("xm y182 w215 h30", GetLang("打开 Windows 触控板设置"))
        this.OpenSettings.OnEvent("Click", ObjBindMethod(this, "OpenTouchSettings"))
        this.Hint := win.AddText("xm y244 w446 h50", "")
        this.ClearButton := win.AddButton("xm y304 w104 h32", GetLang("清除绑定"))
        this.ClearButton.Enabled := value != ""
        this.ClearButton.OnEvent("Click", ObjBindMethod(this, "Save", true))
        win.AddButton("x+166 yp w82 h32", GetLang("取消")).OnEvent("Click", ObjBindMethod(this, "Close"))
        win.AddButton("x+12 yp w82 h32 Default", GetLang("保存")).OnEvent("Click", ObjBindMethod(this, "Save", false))

        current := GestureRead(value)
        this.LastSlot := 1
        this.DefaultShortcut()
        if (current && current.Source == "Touch") {
            this.Source.Choose(2)
            this.Touch.Choose(current.Slot)
            this.LastSlot := current.Slot
            this.Shortcut.Value := GestureHotkeyText(current.Chord)
        } else if (current) {
            for i, key in this.MouseKeys {
                if (key == current.Key)
                    this.MouseKey.Choose(i)
            }
            if (current.Shape == "Custom")
                this.Custom := StrSplit(value, "|")[3]
        }
        this.RebuildShapes(current && current.Source == "Mouse" ? current.Shape : "")
        this.Source.OnEvent("Change", ObjBindMethod(this, "Update"))
        this.MouseKey.OnEvent("Change", ObjBindMethod(this, "OnMouseKey"))
        this.Shape.OnEvent("Change", ObjBindMethod(this, "Update"))
        this.Touch.OnEvent("Change", ObjBindMethod(this, "OnTouch"))
        this.Shortcut.OnEvent("Change", ObjBindMethod(this, "Update"))
        win.OnEvent("Close", ObjBindMethod(this, "Close"))
        win.OnEvent("Escape", ObjBindMethod(this, "Close"))

        GestureTriggers.Editing := this
        this.RestoreOwner := DllCall("IsWindowEnabled", "Ptr", this.Owner)
        if (this.RestoreOwner)
            DllCall("EnableWindow", "Ptr", this.Owner, "Int", false)
        try {
            win.Show("AutoSize")
            this.Update()
        } catch as err {
            this.Close()
            throw err
        }
    }

    RebuildShapes(selected := "") {
        this.ShapeIDs := []
        labels := []
        wheel := GestureIsWheel(this.MouseKeys[this.MouseKey.Value])
        ids := ["Right", "DownRight", "Down", "DownLeft", "Left", "UpLeft", "Up", "UpRight",
            "L", "V", "Caret", "Z", "S", "N", "W", "M", "Circle", "Triangle", "Square", "Diamond", "Custom"]
        if (wheel)
            ids.InsertAt(1, "Tilt")
        if (selected == "" || (selected == "Tilt" && !wheel))
            selected := ids[1]
        choice := 1
        for i, id in ids {
            this.ShapeIDs.Push(id)
            labels.Push(GetLang(GesturePath.Labels()[id]))
            if (id == selected)
                choice := i
        }
        this.Shape.Delete()
        this.Shape.Add(labels)
        this.Shape.Choose(choice)
    }

    OnMouseKey(*) {
        this.RebuildShapes(this.ShapeIDs[this.Shape.Value])
        this.Update()
    }

    OnTouch(*) {
        previous := GestureDefaultChord(this.LastSlot)
        this.LastSlot := this.Touch.Value
        if (GestureParseHotkey(this.Shortcut.Value) == previous)
            this.DefaultShortcut()
        this.Update()
    }

    DefaultShortcut(*) {
        this.Shortcut.Value := GestureHotkeyText(GestureDefaultChord(this.Touch.Value))
        if (GestureTriggers.Editing == this)
            this.Update()
    }

    OpenTouchSettings(*) {
        chord := GestureParseHotkey(this.Shortcut.Value)
        status := this.TouchStatus(chord)
        if (status != "") {
            this.Hint.Text := status
            return
        }
        GestureTriggers.SetSetupChord(chord)
        try Run("ms-settings:devices-touchpad")
        catch {
            GestureTriggers.SetSetupChord()
            this.Hint.Text := GetLang("请从 Windows 设置手动打开触控板。")
        }
    }

    Update(*) {
        touch := this.Source.Value == 2
        shape := this.ShapeIDs[this.Shape.Value]
        custom := !touch && shape == "Custom"
        this.MouseLabel.Visible := this.MouseKey.Visible := this.ShapeLabel.Visible := this.Shape.Visible := !touch
        this.TouchLabel.Visible := this.Touch.Visible := this.ShortcutLabel.Visible := this.Shortcut.Visible := touch
        this.ResetShortcut.Visible := this.TouchHelp.Visible := this.OpenSettings.Visible := touch
        this.Pad.Visible := !touch && shape != "Tilt"
        if (!custom)
            this.Recording := false
        if (custom) {
            InstallMouseHook()
            this.WasDown := GetKeyState("LButton", "P")
        }
        SetTimer(this.SampleCallback, custom ? 15 : 0)

        if (touch) {
            chord := GestureParseHotkey(this.Shortcut.Value)
            this.Hint.Text := this.TouchStatus(chord)
        } else if (custom) {
            path := this.Custom == "" ? [] : GestureRead("Mouse|LButton|" this.Custom).Path[1]
            this.DrawPreview(path)
            this.Hint.Text := GetLang("在此区域按住左键绘制自定义轨迹")
        } else if (shape == "Tilt") {
            this.Hint.Text := GetLang("倾斜滚轮即可触发。同方向也绑定了轨迹时，停住鼠标后区分。")
        } else {
            this.DrawPreview(GesturePath.Shapes()[shape][1])
            this.Hint.Text := GestureIsWheel(this.MouseKeys[this.MouseKey.Value])
                ? GetLang("向左或右倾斜滚轮一次。选择轨迹时，随后移动鼠标并停住。")
                : GetLang("按住所选鼠标键绘制轨迹，松开时识别。按键也会传给当前应用。")
        }
    }

    TouchStatus(chord) {
        if (!chord)
            return GetLang("请设置含 Ctrl、Alt 或 Shift 的组合键。")
        if (!GestureTriggers.ShortcutAvailable(chord))
            return GetLang("这个快捷键无法注册，请换一个组合键。")
        for tableItem in MySoftData.TableInfo {
            if (tableItem.Symbol != "Gesture")
                continue
            for item in tableItem.Items {
                if (tableItem.ID == this.TableID && item.ID == this.ItemID)
                    continue
                if (SubStr(item.TK, 1, 6) != "Touch|")
                    continue
                gesture := GestureRead(item.TK)
                if (gesture && gesture.Source == "Touch" && gesture.Chord == chord && gesture.Slot != this.Touch.Value)
                    return GetLang("这个快捷键已分配给另一种触控板动作。")
            }
        }
        return ""
    }

    DrawPreview(points) {
        rect := Buffer(16)
        if (!DllCall("GetClientRect", "Ptr", this.Pad.Hwnd, "Ptr", rect))
            return
        width := NumGet(rect, 8, "Int")
        height := NumGet(rect, 12, "Int")
        if (width < 1 || height < 1)
            return
        bitmap := Gdip_CreateBitmap(width, height)
        if (!bitmap)
            return
        graphics := Gdip_GraphicsFromImage(bitmap)
        pen := Gdip_CreatePen(0xFF2563EB, 3)
        try {
            Gdip_GraphicsClear(graphics, 0xFFF4F7FC)
            if (points.Length >= 2) {
                Gdip_SetSmoothingMode(graphics, 4)
                scale := Min(width, height) - 22
                line := ""
                for point in points {
                    line .= (line == "" ? "" : "|") Round(width / 2 + point[1] * scale)
                        . "," Round(height / 2 + point[2] * scale)
                }
                Gdip_DrawLines(graphics, pen, line)
                start := points[1]
                brush := Gdip_BrushCreateSolid(0xFF2563EB)
                try Gdip_FillEllipse(graphics, brush, width / 2 + start[1] * scale - 4, height / 2 + start[2] * scale - 4, 8, 8)
                finally Gdip_DeleteBrush(brush)
            }
            image := Gdip_CreateHBITMAPFromBitmap(bitmap)
            if (image)
                this.Pad.Value := "HBITMAP:" image
        } finally {
            Gdip_DeletePen(pen)
            Gdip_DeleteGraphics(graphics)
            Gdip_DisposeImage(bitmap)
        }
    }

    Sample() {
        down := GetKeyState("LButton", "P")
        started := down && !this.WasDown
        this.WasDown := down
        if (!WinActive("ahk_id " this.Window.Hwnd)) {
            if (this.Recording) {
                this.Recording := false
                this.Update()
            }
            return
        }
        if (!started && !this.Recording)
            return
        point := GesturePath.Cursor()
        if (started) {
            rect := Buffer(16)
            if (!DllCall("GetWindowRect", "Ptr", this.Pad.Hwnd, "Ptr", rect))
                return
            if (point[1] < NumGet(rect, 0, "Int") || point[1] >= NumGet(rect, 8, "Int")
                || point[2] < NumGet(rect, 4, "Int") || point[2] >= NumGet(rect, 12, "Int"))
                return
            this.Recording := true
            this.Points := [point]
            this.Hint.Text := GetLang("正在录制轨迹…")
            this.DrawPreview([])
        } else if (!down) {
            this.Recording := false
            this.Points.Push(point)
            points := GesturePath.Normalize(this.Points, 25)
            if (points.Length) {
                this.Custom := GesturePath.Encode(points)
                this.DrawPreview(points)
                this.Hint.Text := GetLang("轨迹已录制，可重新绘制")
            } else {
                this.Update()
                this.Hint.Text := GetLang(this.Custom == "" ? "轨迹太短，请重新绘制" : "轨迹太短，已保留上一次录制。")
            }
        } else if (this.Points.Length < 1000 && GesturePath.Distance(point, this.Points[-1]) >= 2) {
            this.Points.Push(point)
            if (Mod(this.Points.Length, 4) == 0)
                this.DrawPreview(GesturePath.Normalize(this.Points))
        }
    }

    Save(clear, *) {
        value := ""
        if (!clear) {
            if (this.Source.Value == 2) {
                chord := GestureParseHotkey(this.Shortcut.Value)
                status := this.TouchStatus(chord)
                if (status != "") {
                    this.Hint.Text := status
                    return
                }
                slot := this.Touch.Value
                value := "Touch|" slot
                if (chord != GestureDefaultChord(slot))
                    value .= "|" (chord & 0xFFFF) "|" (chord >> 16)
            } else {
                key := this.MouseKeys[this.MouseKey.Value]
                shape := this.ShapeIDs[this.Shape.Value]
                if (shape == "Custom") {
                    if (this.Custom == "") {
                        this.Hint.Text := GetLang("请先绘制自定义轨迹")
                        return
                    }
                    shape := this.Custom
                }
                value := "Mouse|" key "|" shape
            }
        }
        resolved := ResolveMacroItem(this.TableID, this.ItemID)
        changed := resolved && resolved.Item.TK != value
        if (changed)
            resolved.Item.TK := value
        this.Close()
        if (!changed)
            return
        MyMainWin.RefreshItemRow(resolved.Table.Index, resolved.Index)
        HotReloadPublish(resolved.Table.Index, resolved.Index)
    }

    Close(*) {
        if (GestureTriggers.Editing != this)
            return
        SetTimer(this.SampleCallback, 0)
        GestureTriggers.Editing := false
        GestureTriggers.SetSetupChord()
        if (this.RestoreOwner)
            DllCall("EnableWindow", "Ptr", this.Owner, "Int", true)
        this.Window.Destroy()
        this.SampleCallback := ""
    }
}

