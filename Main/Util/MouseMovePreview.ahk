#Requires AutoHotkey v2.0

; Preview reads unsaved editor values and draws only; it never saves or sends input.
BindMouseMovePreview(ui, kind) {
    ; 预览按钮同时承担路径预览与双点编辑，保留一个入口避免两个按钮状态分裂。
    ui.Update("BtnCmdPointEdit", "Visibility", "Collapsed")
    ui.Update("BtnCmdPreview", "Visibility", "Visible")
    ui.Update("BtnCmdPreview", "ToolTip", GetLang("预览移动路径"))
    ; 标题栏按钮在 XAML 窗口真正加载后再补一次可见性，避免预加载 BatchUpdate 被模板初值覆盖。
    SetTimer(() => ShowMousePreviewButton(ui), -1)
    ui.OnEvent("BtnCmdPreview", "Click", (*) => PreviewMouseMovement(ui, kind))
}

ShowMousePreviewButton(ui) {
    if (!IsObject(ui))
        return
    try ui.Update("BtnCmdPointEdit", "Visibility", "Collapsed")
    try ui.Update("BtnCmdPreview", "Visibility", "Visible")
    try ui.Update("BtnCmdPreview", "ToolTip", GetLang("预览移动路径"))
}

PreviewMouseMovement(ui, kind) => MouseMovePreview.Toggle(ui, kind)
PreviewMousePath(ui, kind) => MouseMovePreview.TogglePath(ui, kind)

; Read all editor values in one IPC request. Timer refreshes do not show modal errors
; while the user is in the middle of typing a coordinate.
ReadMousePreview(ui, kind, cx, cy, notify := false) {
    fields := kind == "delta" ? ["DeltaXCon", "DeltaYCon", "CountCon"]
        : (kind == "pro" ? ["MouseMoveModeCombo>SelectedIndex", "ActionTypeCombo>SelectedIndex", "PosVarX", "PosVarY", "EndPosVarX", "EndPosVarY", "RefCombo>SelectedIndex", "WinInfoCon", "HumanMouseTog", "SpeedCon"]
        : ["MouseMoveModeCombo>SelectedIndex", "PosXCon", "PosYCon"])
    state := ui.Query(fields*)
    mode := 1, action := 1, endX := 0, endY := 0, count := 1, wx := 0, wy := 0
    if (kind == "delta") {
        x := state.Get("DeltaXCon", ""), y := state.Get("DeltaYCon", ""), count := state.Get("CountCon", "")
    } else {
        mode := state.Get("MouseMoveModeCombo>SelectedIndex", 0)
        if (kind == "pro") {
            x := state.Get("PosVarX", ""), y := state.Get("PosVarY", "")
            actionIdx := state.Get("ActionTypeCombo>SelectedIndex", 0)
            action := (mode == 0 && actionIdx == 3) ? 5 : ((mode == 0 && actionIdx == 4) ? 4 : actionIdx + 1)
            if (action == 4 && mode == 0)
                endX := state.Get("EndPosVarX", ""), endY := state.Get("EndPosVarY", "")
            if (mode == 0 && state.Get("RefCombo>SelectedIndex", 0) == 1) {
                hwnds := GetHwndList(GetLangKey(state.Get("WinInfoCon", "")))
                if (!IsObject(hwnds) || hwnds.Length == 0) {
                    if (notify)
                        RmtDialog.Info(GetLang("预览未找到目标窗口。"))
                    return ""
                }
                try WinGetPos(&wx, &wy, , , "ahk_id " hwnds[1])
                catch {
                    if (notify)
                        RmtDialog.Info(GetLang("预览未找到目标窗口。"))
                    return ""
                }
            }
        } else {
            x := state.Get("PosXCon", ""), y := state.Get("PosYCon", "")
        }
    }
    for value in [x, y, endX, endY, count] {
        if (!IsNumber(value)) {
            if (notify)
                RmtDialog.Info(GetLang("预览需要数值坐标和次数，请先将变量替换为数值。"))
            return ""
        }
    }
    points := MousePreviewPoints(kind, x, y, cx, cy, mode, action, endX, endY, count, wx, wy)
    points.Human := kind == "pro" && state.Get("HumanMouseTog", "False") == "True"
    speed := state.Get("SpeedCon", 90)
    points.Speed := IsNumber(speed) ? Max(0, Min(100, Integer(speed))) : 90
    return points
}

; Numeric geometry follows the executor: relative moves truncate, absolute moves round.
MousePreviewPoints(kind, x, y, cx, cy, mode := 0, action := 1, endX := 0, endY := 0, count := 1, wx := 0, wy := 0) {
    if (kind == "delta") {
        steps := Max(1, Integer(count)), dx := Integer(x), dy := Integer(y)
        ; 增量值表示本次总偏移，次数只决定分成多少个等量步骤。
        stepX := dx / steps, stepY := dy / steps
        return {X1: cx, Y1: cy, X2: cx + dx, Y2: cy + dy, StepX: stepX, StepY: stepY, Steps: steps}
    }
    if (mode == 1)
        return {X1: cx, Y1: cy, X2: cx + Integer(x), Y2: cy + Integer(y)}
    if (kind == "pro" && action == 4)
        return {X1: Round(wx + x), Y1: Round(wy + y), X2: Round(wx + endX), Y2: Round(wy + endY)}
    if (kind == "pro" && action == 5)
        return {X1: cx, Y1: cy, X2: Round(wx + x), Y2: Round(wy + y)}
    return {X1: cx, Y1: cy, X2: Round(wx + x), Y2: Round(wy + y)}
}

class MouseMovePreview {
    static Overlay := ""
    static Editor := ""
    static Kind := ""
    static OriginX := 0
    static OriginY := 0
    static LastFrame := ""
    static Revision := 0
    static LastPathKey := ""
    static LastPath := []
    static LastEditFrame := ""
    static RefreshTimer := ObjBindMethod(MouseMovePreview, "Refresh")
    static EditHandles := []
    static EditTimer := ObjBindMethod(MouseMovePreview, "RefreshEditHandles")
    static EditMode := false
    static DragIndex := 0
    static DragOffsetX := 0
    static DragOffsetY := 0

    static Toggle(ui, kind) {
        ; 相对位移与 A 到 B 拖拽进入双点编辑：再次点击同一按钮提交点位。
        if (this.Editor == ui && this.EditMode) {
            this.CommitEdit()
            return
        }
        if (this.Editor == ui) {
            this.Clear()
            return
        }
        this.Clear()
        this.Editor := ui, this.Kind := kind
        CoordMode("Mouse", "Screen")
        MouseGetPos(&cx, &cy)
        this.OriginX := cx, this.OriginY := cy
        ; 三种移动编辑器都支持双点编辑：绝对移动/普通拖拽以当前点到目标点显示，
        ; 相对位移和 A 到 B 拖拽则把两点结果写回对应字段。
        if (this.StartEdit(ui, kind))
            return
        if (!this.Refresh(true)) {
            this.Clear()
            return
        }
        SetTimer(this.RefreshTimer, 300)
    }

    static Clear(ui := "") {
        ; A different editor closing must not dismiss the current editor's preview.
        if (IsObject(ui) && this.Editor != ui)
            return
        SetTimer(this.RefreshTimer, 0)
        SetTimer(this.EditTimer, 0)
        this.DestroyEditHandles()
        this.EditMode := false
        this.DragIndex := 0
        this.LastEditFrame := ""
        this.Revision += 1
        if (IsObject(this.Editor))
            this.SetButton(false)
        this.Editor := "", this.Kind := "", this.LastFrame := ""
        this.LastPathKey := "", this.LastPath := []
        this.HideOverlay()
    }

    static StartEdit(ui, kind) {
        points := ReadMousePreview(ui, kind, this.OriginX, this.OriginY, true)
        if (!IsObject(points))
            return false
        this.Editor := ui, this.Kind := kind, this.EditMode := true
        this.LastFrame := ""
        this.EditPoints := [{x: points.X1, y: points.Y1}, {x: points.X2, y: points.Y2}]
        this.CreateEditHandles()
        this.Show(points, this.Palette())
        this.SetButton(true)
        this.Editor.Update("BtnCmdPreview", "ToolTip", GetLang("再次点击确定点位"))
        SetTimer(this.EditTimer, 60)
        return true
    }

    static TogglePath(ui, kind) {
        if (this.Editor == ui && this.EditMode)
            return
        if (this.Editor == ui) {
            this.Clear()
            return
        }
        this.Clear()
        this.Editor := ui, this.Kind := kind
        CoordMode("Mouse", "Screen")
        MouseGetPos(&cx, &cy)
        this.OriginX := cx, this.OriginY := cy
        if (!this.Refresh(true)) {
            this.Clear()
            return
        }
        SetTimer(this.RefreshTimer, 300)
    }

    static CreateEditHandles() {
        this.DestroyEditHandles()
        handleSize := 44
        halfSize := handleSize // 2
        for point in this.EditPoints {
            h := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
            ; 使用透明的大点击区域；可见圆点由下方主题色预览层绘制，确保箭头连接圆心。
            h.BackColor := "FFFFFF"
            t := h.AddText("x0 y0 w" handleSize " h" handleSize " Center", " ")
            t.OnEvent("Click", ObjBindMethod(this, "OnEditHandleClick"))
            h.Show("NA x" (point.x - halfSize) " y" (point.y - halfSize) " w" handleSize " h" handleSize)
            ; 使用低透明度窗口而不是颜色键透明：颜色键会让鼠标穿透到桌面，拖拽时触发系统框选。
            try WinSetTransparent(1, h.Hwnd)
            this.EditHandles.Push(h)
        }
    }

    static DestroyEditHandles() {
        for h in this.EditHandles
            try h.Destroy()
        this.EditHandles := []
    }

    static OnEditHandleClick(ctrl, info := "", *) {
        ; 句柄窗口是无标题透明窗口，直接发送 HTCAPTION 在部分系统/缩放下不会开始拖动。
        ; 实际拖动由 RefreshEditHandles 按鼠标按下状态接管，Click 事件只负责兼容点击。
        return
    }

    static RefreshEditHandles(*) {
        if (!this.EditMode || !IsObject(this.Editor) || this.EditHandles.Length < 2)
            return
        editor := this.Editor, kind := this.Kind, revision := this.Revision
        ; 拖动时提高刷新频率，松开后恢复较低频率，减少 IPC 与重绘开销。
        SetTimer(this.EditTimer, GetKeyState("LButton", "P") ? 15 : 60)
        ; 轮询按键状态并直接移动句柄窗口，避免透明无标题窗口的系统拖动消息不可靠。
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        if (GetKeyState("LButton", "P")) {
            if (!this.DragIndex) {
                for i, point in this.EditPoints {
                    if (Abs(mx - point.x) <= 28 && Abs(my - point.y) <= 28) {
                        this.DragIndex := i
                        this.DragOffsetX := mx - point.x
                        this.DragOffsetY := my - point.y
                        break
                    }
                }
            }
            if (this.DragIndex) {
                dragHwnd := this.EditHandles[this.DragIndex].Hwnd
                try WinMove(mx - this.DragOffsetX - 22, my - this.DragOffsetY - 22, , , "ahk_id " dragHwnd)
            }
        } else {
            this.DragIndex := 0
        }
        for i, h in this.EditHandles {
            try WinGetPos(&x, &y, &w, &hgt, "ahk_id " h.Hwnd)
            catch
                continue
            this.EditPoints[i].x := x + 22, this.EditPoints[i].y := y + 22
        }
        p1 := this.EditPoints[1], p2 := this.EditPoints[2]
        editFrame := p1.x "," p1.y "," p2.x "," p2.y
        if (editFrame == this.LastEditFrame)
            return
        ; Query 会等待界面进程，期间按钮/关闭事件可能清空或切换预览。
        ; 保留本轮编辑器引用，返回后核对代次，过期回调不得继续写回或重绘。
        state := editor.Query("CountCon", "MouseMoveModeCombo>SelectedIndex", "ActionTypeCombo>SelectedIndex", "RefCombo>SelectedIndex", "WinInfoCon")
        if (!this.IsCurrentEdit(editor, revision))
            return
        updates := []
        preview := {X1: p1.x, Y1: p1.y, X2: p2.x, Y2: p2.y}
        if (kind == "delta") {
            updates.Push({ControlName: "DeltaXCon", PropertyName: "Text", Value: String(Round(p2.x - p1.x))}, {ControlName: "DeltaYCon", PropertyName: "Text", Value: String(Round(p2.y - p1.y))})
            count := state.Get("CountCon", 1)
            count := IsNumber(count) && Number(count) > 0 ? Max(1, Integer(count)) : 1
            preview.Steps := count
            preview.StepX := (p2.x - p1.x) / count
            preview.StepY := (p2.y - p1.y) / count
        } else {
            mode := state.Get("MouseMoveModeCombo>SelectedIndex", 0)
            if (kind == "move") {
                updates.Push({ControlName: "PosXCon", PropertyName: "Text", Value: String(Round(mode == 1 ? p2.x - p1.x : p2.x))},
                    {ControlName: "PosYCon", PropertyName: "Text", Value: String(Round(mode == 1 ? p2.y - p1.y : p2.y))})
            } else if (mode == 1) {
                updates.Push({ControlName: "PosVarX", PropertyName: "Text", Value: String(Round(p2.x - p1.x))}, {ControlName: "PosVarY", PropertyName: "Text", Value: String(Round(p2.y - p1.y))})
            } else {
                ox := 0, oy := 0
                if (state.Get("RefCombo>SelectedIndex", 0) == 1) {
                    try {
                        hwnds := GetHwndList(GetLangKey(state.Get("WinInfoCon", "")))
                        if (IsObject(hwnds) && hwnds.Length)
                            WinGetPos(&ox, &oy, , , "ahk_id " hwnds[1])
                    }
                }
                ; 普通绝对移动/拖拽只写目标点；A 到 B 拖拽同时写入起点。
                start := state.Get("ActionTypeCombo>SelectedIndex", 0) == 4 ? p1 : p2
                updates.Push({ControlName: "PosVarX", PropertyName: "Text", Value: String(Round(start.x - ox))}, {ControlName: "PosVarY", PropertyName: "Text", Value: String(Round(start.y - oy))},
                    {ControlName: "EndPosVarX", PropertyName: "Text", Value: String(Round(p2.x - ox))}, {ControlName: "EndPosVarY", PropertyName: "Text", Value: String(Round(p2.y - oy))})
            }
        }
        if (!this.IsCurrentEdit(editor, revision))
            return
        editor.BatchUpdate(updates)
        if (!this.IsCurrentEdit(editor, revision))
            return
        this.LastEditFrame := editFrame
        this.Show(preview, this.Palette())
    }

    static IsCurrentEdit(editor, revision) {
        return this.EditMode && this.Editor == editor && this.Revision == revision
    }

    static CommitEdit() {
        this.RefreshEditHandles()
        this.Clear(this.Editor)
    }

    static HideOverlay() {
        if (IsObject(this.Overlay))
            this.Overlay.Destroy()
        this.Overlay := ""
    }

    static SetButton(enabled) {
        try {
            this.Editor.Update("BtnCmdPreview", "Background", enabled ? "{DynamicResource ActionBg}" : "Transparent")
            this.Editor.Update("BtnCmdPreview", "Foreground", enabled ? "{DynamicResource ActionText}" : "{DynamicResource TitleBarForeground}")
            tipKey := enabled ? (this.EditMode ? "再次点击确定点位" : "关闭指令预览") : "预览移动路径"
            this.Editor.Update("BtnCmdPreview", "ToolTip", GetLang(tipKey))
        }
    }

    static Palette() {
        colors := MainSoftData.HasProp("ThemeColors") ? MainSoftData.ThemeColors : Map()
        return {Line: Integer("0x" SubStr(AppThemeUtil.ResolveColor(colors, "Theme_Color01"), 2)),
            Outline: Integer("0x" SubStr(AppThemeUtil.ResolveColor(colors, "Theme_Color14"), 2))}
    }

    static Refresh(notify := false) {
        if (!IsObject(this.Editor))
            return false
        revision := this.Revision
        points := ReadMousePreview(this.Editor, this.Kind, this.OriginX, this.OriginY, notify)
        if (revision != this.Revision)
            return false
        if (!IsObject(points)) {
            this.HideOverlay()
            this.LastFrame := ""
            return false
        }
        pathKey := points.X1 "," points.Y1 "," points.X2 "," points.Y2 "," points.Human "," points.Speed
        if (points.Human) {
            if (pathKey != this.LastPathKey) {
                this.LastPath := MousePreviewCurve(points)
                this.LastPathKey := pathKey
            }
            points.Path := this.LastPath
        } else {
            this.LastPathKey := "", this.LastPath := []
        }
        palette := this.Palette()
        frame := pathKey "," points.X1 "," points.Y1 "," points.X2 "," points.Y2 "," palette.Line "," palette.Outline
        if (points.HasOwnProp("Steps"))
            frame .= "," points.Steps "," points.StepX "," points.StepY
        if (frame != this.LastFrame) {
            this.Show(points, palette)
            this.LastFrame := frame
            ; 预览和双点编辑都属于按钮的开启状态，均保持选中背景。
            this.SetButton(true)
        }
        return true
    }

    static Show(p, palette := "") {
        if (!IsObject(palette))
            palette := this.Palette()
        ; Physical virtual-desktop pixels, including monitors left/above the primary.
        left := SysGet(76), top := SysGet(77), width := SysGet(78), height := SysGet(79)
        token := Gdip_Startup()
        hbm := 0, hdc := 0, old := 0, g := 0, outline := 0, pen := 0, brush := 0
        try {
            hbm := CreateDIBSection(width, height)
            hdc := CreateCompatibleDC()
            old := SelectObject(hdc, hbm)
            g := Gdip_GraphicsFromHDC(hdc)
            Gdip_GraphicsClear(g, 0)
            Gdip_SetSmoothingMode(g, 4)
            outline := Gdip_CreatePen(palette.Outline, 7)
            pen := Gdip_CreatePen(palette.Line, 3)
            brush := Gdip_BrushCreateSolid(palette.Line)
            x1 := p.X1 - left, y1 := p.Y1 - top, x2 := p.X2 - left, y2 := p.Y2 - top
            curve := p.HasOwnProp("Path") && p.Path.Length > 1
            polyline := ""
            if (curve) {
                for point in p.Path
                    polyline .= (A_Index == 1 ? "" : "|") (point.X-left) "," (point.Y-top)
            }
            dx := x2-x1, dy := y2-y1
            if (curve) {
                ; Orient the arrowhead along the curve's final nonzero segment.
                loop p.Path.Length - 1 {
                    point := p.Path[p.Path.Length-A_Index]
                    dx := p.X2-point.X, dy := p.Y2-point.Y
                    if (dx*dx+dy*dy >= 1)
                        break
                }
            }
            ; 先绘制端点和增量中间点，再绘制线与箭头，保证箭头层级在圆点之上。
            Gdip_DrawEllipse(g, outline, x1-11, y1-11, 22, 22)
            Gdip_FillEllipse(g, brush, x1-11, y1-11, 22, 22)
            Gdip_DrawEllipse(g, outline, x2-11, y2-11, 22, 22)
            Gdip_FillEllipse(g, brush, x2-11, y2-11, 22, 22)
            if (p.HasOwnProp("Steps")) {
                range := MousePreviewVisibleSteps(p, left, top, width, height)
                loop Max(0, range.Last - range.First + 1) {
                    step := range.First + A_Index - 1
                    px := x1 + p.StepX * step, py := y1 + p.StepY * step
                    Gdip_DrawEllipse(g, outline, px-4, py-4, 8, 8)
                    Gdip_FillEllipse(g, brush, px-4, py-4, 8, 8)
                }
            }
            length := Sqrt(dx*dx + dy*dy)
            if (length > 0) {
                ux := dx/length, uy := dy/length
                ; The final eased segment can be subpixel; keep the arrowhead readable.
                arrow := Min(18, Sqrt((x2-x1)**2 + (y2-y1)**2)), wing := arrow * 0.5
                ax := x2 - ux*arrow - uy*wing, ay := y2 - uy*arrow + ux*wing
                bx := x2 - ux*arrow + uy*wing, by := y2 - uy*arrow - ux*wing
                for linePen in [outline, pen] {
                    if (curve)
                        Gdip_DrawLines(g, linePen, polyline)
                    else
                        Gdip_DrawLine(g, linePen, x1, y1, x2, y2)
                    Gdip_DrawLine(g, linePen, ax, ay, x2, y2)
                    Gdip_DrawLine(g, linePen, bx, by, x2, y2)
                }
            }
            if (!IsObject(this.Overlay))
                this.Overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale")
            this.Overlay.Show("NA x" left " y" top " w" width " h" height)
            UpdateLayeredWindow(this.Overlay.Hwnd, hdc, left, top, width, height)
        } finally {
            if (brush)
                Gdip_DeleteBrush(brush)
            if (pen)
                Gdip_DeletePen(pen)
            if (outline)
                Gdip_DeletePen(outline)
            if (g)
                Gdip_DeleteGraphics(g)
            if (old)
                SelectObject(hdc, old)
            if (hbm)
                DeleteObject(hbm)
            if (hdc)
                DeleteDC(hdc)
            Gdip_Shutdown(token)
        }
    }
}

; Skip only off-screen steps; retain every visible step even for very large counts.
MousePreviewVisibleSteps(p, left, top, width, height) {
    ; 终点单独绘制大圆，这里只返回真正的中间落点。
    first := 1, last := Max(0, p.Steps - 1)
    if (last < first)
        return {First: 1, Last: 0}
    for axis in [{Origin: p.X1, Delta: p.StepX, Low: left-7, High: left+width+7},
        {Origin: p.Y1, Delta: p.StepY, Low: top-7, High: top+height+7}] {
        if (axis.Delta == 0) {
            if (axis.Origin < axis.Low || axis.Origin > axis.High)
                return {First: 1, Last: 0}
            continue
        }
        a := (axis.Low-axis.Origin)/axis.Delta, b := (axis.High-axis.Origin)/axis.Delta
        first := Max(first, Ceil(Min(a, b)))
        last := Min(last, Floor(Max(a, b)))
    }
    if (p.StepX == 0 && p.StepY == 0)
        last := Min(last, 1) ; coincident points have identical pixels
    return {First: first, Last: last}
}

; Generate a sample with the execution algorithm, without moving the real pointer
; or changing the singleton's parameters. Cache it until geometry/speed changes.
MousePreviewCurve(p) {
    runtime := HumanMouse.GetInstance()
    generator := HumanMouse()
    for name, value in runtime.OwnProps()
        generator.%name% := value
    generator.Speed := p.Speed
    distance := Sqrt((p.X2-p.X1)**2 + (p.Y2-p.Y1)**2)
    generator.AutoCalculateParams(distance)
    return generator.GeneratePath(p.X1, p.Y1, p.X2, p.Y2)
}
