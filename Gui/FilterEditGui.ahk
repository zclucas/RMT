#Requires AutoHotkey v2.0
; RMT (若梦兔) - 图片处理 / AGPL-3.0
;
; 从「搜索Pro编辑器」点【图片处理】打开：
;   - 固定 300x300 的 1:1 取景框：100% 时一图像像素对一屏幕像素，图按原尺寸居中
;   - 滚轮以光标为中心缩放（1x~16x），拖动平移
;   - 点【取色】后才能在图里点选颜色；点【裁剪】后才能拖框选区
;   - 左原图 / 右"保留后"并排对比，放大到 6 倍以上自动显示像素格

class FilterEditGui {
    __new() {
        this.Gui := ""
        this.OwnerHwnd := ""
        this.SureAction := ""        ; (colorList, tolerance) => ...
        this.CropAction := ""        ; (newPath) => ...
        this.TemplatePath := ""
        this.Colors := ""
        this.Tolerance := 8

        ; 布局
        this.PicLeft := 16
        this.PicTop := 88
        this.PreviewMaxW := 340
        this.PreviewMaxH := 300
        this.CanvasSize := 340              ; 正方形预览区边长（物理像素）
        this.Gap := 40

        ; 运行时几何（每帧实测，不缓存）
        this.PicW := 0
        this.PicH := 0
        this.OffX := 0
        this.OffY := 0

        ; 控件（AddGui 里创建，这里先占位，避免未建窗时访问报错）
        this.NameCon := ""
        this.NameExtCon := ""
        this.NameExt := ".png"
        this.ColorCon := ""

        ; 视图
        this.Zoom := 1.0
        this.PanX := 0.0
        this.PanY := 0.0
        this.ViewX := 0
        this.ViewY := 0
        this.ViewW := 0
        this.ViewH := 0
        this.OrigW := 0
        this.OrigH := 0
        this.BoxW := 0
        this.BoxH := 0

        ; 交互状态
        this.PickMode := false
        this.CropMode := false
        this.SelX := 0
        this.SelY := 0
        this.SelW := 0
        this.SelH := 0
        this.dragActive := false
        this.AnchorX := 0
        this.AnchorY := 0
        this.wasDown := false
        this.pressIn := false
        this.pressX := 0
        this.pressY := 0
        this.moved := false
        this.lastPanTick := 0
        this.lastPickTick := 0

        this.tickFn := this.InputTick.Bind(this)
        this.wheelUpFn := this.OnWheelUp.Bind(this)
        this.wheelDownFn := this.OnWheelDown.Bind(this)
        this.clickFn := this.OnHotkeyClick.Bind(this)
    }

    ShowGui(templatePath, colorList, tolerance) {
        this.TemplatePath := templatePath
        this.Colors := colorList
        this.Tolerance := tolerance

        if (this.Gui != "") {
            if (this.OwnerHwnd != "") {
                this.Gui.Opt("+Owner" this.OwnerHwnd)
            }
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init()
        this.EnableInput()
    }

    EnableInput() {
        SetTimer(this.tickFn, 25)
        ; 热键 + 轮询双通道：主程序繁忙时钩子可能丢事件，轮询兜底（合成输入对轮询不可见）
        try Hotkey("~LButton", this.clickFn, "On")
        try {
            HotIfWinActive("ahk_id " this.Gui.Hwnd)
            Hotkey("WheelUp", this.wheelUpFn, "On")
            Hotkey("WheelDown", this.wheelDownFn, "On")
            HotIf()
        }
    }

    DisableInput() {
        SetTimer(this.tickFn, 0)
        try Hotkey("~LButton", this.clickFn, "Off")
        try {
            HotIfWinActive("ahk_id " this.Gui.Hwnd)
            Hotkey("WheelUp", this.wheelUpFn, "Off")
            Hotkey("WheelDown", this.wheelDownFn, "Off")
            HotIf()
        }
    }

    AddGui() {
        MyGui := Gui(, GetLang("图片处理"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MainSoftData.FontType)

        RightLeft := this.PicLeft + this.PreviewMaxW + this.Gap

        ; ---- 工具栏：取色/裁剪 一组，全选/复位 一组 ----
        this.PickBtn := MyGui.Add("Button", "x16 y14 w80 h30", GetLang("取色"))
        this.PickBtn.OnEvent("Click", (*) => this.TogglePick())
        this.PickBtn.ToolTip := GetLang("按下后，在图上点击即可取色（可连续取）")

        this.CropBtn := MyGui.Add("Button", "x104 y14 w80 h30", GetLang("裁剪"))
        this.CropBtn.OnEvent("Click", (*) => this.ToggleCrop())
        this.CropBtn.ToolTip := GetLang("按下后，在图上拖动框选要保留的部分")

        this.CropApplyBtn := MyGui.Add("Button", "x192 y14 w96 h30", GetLang("应用裁剪"))
        this.CropApplyBtn.OnEvent("Click", (*) => this.OnApplyCrop())
        this.CropApplyBtn.ToolTip := GetLang("把选中的区域另存为新模板并应用到当前命令")

        this.SelAllBtn := MyGui.Add("Button", "x304 y14 w68 h30", GetLang("全选"))
        this.SelAllBtn.OnEvent("Click", (*) => this.OnSelectAll())

        this.ResetBtn := MyGui.Add("Button", "x380 y14 w68 h30", GetLang("复位"))
        this.ResetBtn.OnEvent("Click", (*) => this.OnResetView())
        this.ResetBtn.ToolTip := GetLang("适应窗口：整张图缩放到可见")

        con := MyGui.Add("Text", "x520 y20 w224 h20 Right", GetLang("滚轮缩放 · 拖动平移"))
        con.SetFont("S9 W400", MainSoftData.FontType)

        MyGui.Add("Text", "x16 y56 w728 h1 BackgroundD0D0D0", "")

        ; ---- 标题 + 两张固定画布 ----
        this.LeftTitle := MyGui.Add("Text", Format("x{} y64 w{} Center", this.PicLeft, this.PreviewMaxW), GetLang("原图"))
        this.LeftTitle.SetFont("S10 W700", MainSoftData.FontType)
        this.RightTitle := MyGui.Add("Text", Format("x{} y64 w{} Center", RightLeft, this.PreviewMaxW), GetLang("保留后"))
        this.RightTitle.SetFont("S10 W700", MainSoftData.FontType)

        k := this.DpiK()
        lw := Max(1, Round(this.CanvasSize / k))   ; 逻辑尺寸
        lh := Max(1, Round(this.CanvasSize / k))
        off := (this.PreviewMaxW - lw) // 2        ; 用逻辑尺寸居中，不能用物理值

        this.PicLeftCon := MyGui.Add("Picture", Format("x{} y{} w{} h{}", this.PicLeft + off, this.PicTop, lw, lh), "")
        this.PicRightCon := MyGui.Add("Picture", Format("x{} y{} w{} h{}", RightLeft + off, this.PicTop, lw, lh), "")

        PosY := this.PicTop + lh + 10
        con := MyGui.Add("Text", Format("x16 y{} w728 h20", PosY), GetLang("点【取色】后在图里点选颜色；点【裁剪】后拖动框选，松手可拖四角微调；不按按钮时拖动为平移"))
        con.SetFont("S9 W400", MainSoftData.FontType)

        PosY += 28
        MyGui.Add("Text", Format("x16 y{} w728 h1 BackgroundD0D0D0", PosY), "")

        ; ---- 三段参数：标签统一 68 宽，输入框统一从 92 起，右侧按钮统一 660 起 ----
        PosY += 14
        MyGui.Add("Text", Format("x16 y{} w68 h24", PosY + 4), GetLang("文件名："))
        this.NameCon := MyGui.Add("Edit", Format("x92 y{} w520 h26", PosY), "")
        this.NameExtCon := MyGui.Add("Text", Format("x618 y{} w38 h24", PosY + 4), ".png")
        btnCon := MyGui.Add("Button", Format("x660 y{} w84 h26", PosY), GetLang("重命名"))
        btnCon.OnEvent("Click", (*) => this.OnRenameFile())
        btnCon.ToolTip := GetLang("只改文件名，扩展名固定，不会被误删")

        PosY += 38
        MyGui.Add("Text", Format("x16 y{} w68 h24", PosY + 4), GetLang("保留色："))
        this.ColorCon := MyGui.Add("Edit", Format("x92 y{} w560 h26", PosY), "")
        this.ColorCon.OnEvent("Change", (*) => this.OnColorsChanged())
        this.ClearBtn := MyGui.Add("Button", Format("x660 y{} w84 h26", PosY), GetLang("清空"))
        this.ClearBtn.OnEvent("Click", (*) => this.OnClearColors())

        PosY += 38
        MyGui.Add("Text", Format("x16 y{} w68 h24", PosY + 4), GetLang("容差："))
        this.TolCon := MyGui.Add("Edit", Format("x92 y{} w60 h26 Center", PosY), "")
        this.TolCon.OnEvent("Change", (*) => this.OnTolEditChanged())
        this.TolSlider := MyGui.Add("Slider", Format("x164 y{} w220 h26 Range0-255 ToolTip", PosY), 8)
        this.TolSlider.OnEvent("Change", (*) => this.OnTolSliderChanged())
        con := MyGui.Add("Text", Format("x392 y{} w120 h22", PosY + 4), GetLang("（0 ~ 255）"))
        con.SetFont("S9 W400", MainSoftData.FontType)

        ; ---- 状态行 ----
        PosY += 38
        this.StatCon := MyGui.Add("Text", Format("x16 y{} w728 h22", PosY), "")
        this.StatCon.SetFont("S9 W400", MainSoftData.FontType)

        ; ---- 底部按钮 ----
        PosY += 30
        MyGui.Add("Text", Format("x16 y{} w728 h1 BackgroundD0D0D0", PosY), "")
        PosY += 16
        btnCon := MyGui.Add("Button", Format("x556 y{} w90 h32", PosY), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnSureBtnClick())
        btnCon := MyGui.Add("Button", Format("x658 y{} w90 h32", PosY), GetLang("取消"))
        btnCon.OnEvent("Click", (*) => this.OnCancelBtnClick())

        MyGui.OnEvent("Close", (*) => this.OnClose())
        MyGui.OnEvent("Escape", (*) => this.OnCancelBtnClick())

        Height := PosY + 56
        pos := GetCenterPosOnActiveMonitor(760, Height)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 760, Height))
    }

    Init() {
        this.RefreshName()
        this.ColorCon.Value := this.Colors
        this.TolCon.Value := this.Tolerance
        this.TolSlider.Value := this.Tolerance
        this.UpdateButtons()
        this.RenderPreview()
    }

    UpdateButtons() {
        this.PickBtn.Text := this.PickMode ? GetLang("取色中…") : GetLang("取色")
        this.CropBtn.Text := this.CropMode ? GetLang("裁剪中…") : GetLang("裁剪")
        this.CropApplyBtn.Enabled := (this.SelW > 1 && this.SelH > 1)
    }

    TogglePick() {
        this.PickMode := !this.PickMode
        if (this.PickMode)
            this.CropMode := false
        this.UpdateButtons()
    }

    ToggleCrop() {
        this.CropMode := !this.CropMode
        if (this.CropMode)
            this.PickMode := false
        if (!this.CropMode) {
            this.SelW := 0
            this.SelH := 0
            this.RenderPreview()
        }
        this.UpdateButtons()
    }

    Hide() {
        this.DisableInput()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
            catch {
            }
        }
        if (this.Gui != "")
            this.Gui.Hide()
    }

    OnClose(*) {
        this.SureAction := ""
        this.Hide()
    }

    OnCancelBtnClick(*) {
        this.SureAction := ""
        this.Hide()
    }

    OnSureBtnClick(*) {
        action := this.SureAction
        this.SureAction := ""
        if (action != "")
            action(this.NormalizeColors(), this.GetTolerance())
        this.Hide()
    }

    OnColorsChanged() {
        this.Colors := this.ColorCon.Value
        this.RenderPreview()
    }

    OnClearColors() {
        this.Colors := ""
        this.ColorCon.Value := ""
        this.RenderPreview()
    }

    OnTolEditChanged() {
        tol := this.GetTolerance()
        this.TolSlider.Value := tol
        this.RenderPreview()
    }

    OnTolSliderChanged() {
        tol := this.TolSlider.Value
        this.TolCon.Value := tol
        this.RenderPreview()
    }

    OnSelectAll() {
        this.CropMode := true
        this.PickMode := false
        this.SelX := 0
        this.SelY := 0
        this.SelW := this.OrigW
        this.SelH := this.OrigH
        this.UpdateButtons()
        this.RenderPreview()
    }

    OnResetView() {
        this.FitToWindow()
    }

    GetTolerance() {
        tol := this.Tolerance
        if IsNumber(this.TolCon.Value)
            tol := Integer(this.TolCon.Value)
        if (tol < 0)
            tol := 0
        else if (tol > 255)
            tol := 255
        return tol
    }

    NormalizeColors() {
        arr := []
        for part in StrSplit(this.Colors, ",") {
            v := StrUpper(Trim(part))
            if (v == "")
                continue
            exists := false
            for c in arr {
                if (c == v) {
                    exists := true
                    break
                }
            }
            if (!exists)
                arr.Push(v)
        }
        out := ""
        for c in arr
            out .= (out = "" ? "" : ",") c
        return out
    }

    ; ---------------- 坐标换算 ----------------
    DpiK() {
        static k := 0
        if (k = 0) {
            k := A_ScreenDPI / 96.0
            if (k <= 0)
                k := 1.0
        }
        return k
    }

    ; 控件客户区在屏幕上的物理像素矩形（每帧实测，不缓存）
    CtrlRectPhysical(ctrl, &ox, &oy, &cw, &ch) {
        ox := 0, oy := 0, cw := 0, ch := 0
        if (ctrl == "")
            return false
        hwnd := ctrl.Hwnd
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        cw := NumGet(rc, 8, "Int")
        ch := NumGet(rc, 12, "Int")
        pt := Buffer(8, 0)
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt)
        ox := NumGet(pt, 0, "Int")
        oy := NumGet(pt, 4, "Int")
        return (cw > 0 && ch > 0)
    }

    CursorToImage() {
        pt := Buffer(8, 0)
        if (!DllCall("GetCursorPos", "Ptr", pt))
            return { in: false }
        sx := NumGet(pt, 0, "Int")
        sy := NumGet(pt, 4, "Int")

        for ctrl in [this.PicLeftCon, this.PicRightCon] {
            if (ctrl == "")
                continue
            if (!this.CtrlRectPhysical(ctrl, &ox, &oy, &cw, &ch))
                continue
            if (sx < ox || sx >= ox + cw || sy < oy || sy >= oy + ch)
                continue

            px := sx - ox - this.OffX
            py := sy - oy - this.OffY
            if (px < 0 || py < 0 || px >= this.PicW || py >= this.PicH)
                continue
            ix := Floor(this.ViewX + px * this.ViewW / this.PicW)
            iy := Floor(this.ViewY + py * this.ViewH / this.PicH)
            return { in: true, px: px, py: py, ix: ix, iy: iy }
        }
        return { in: false }
    }

    ; 热键触发取色（只在取色模式下生效）
    OnHotkeyClick(*) {
        if (this.Gui == "" || this.PicW <= 0 || !this.PickMode)
            return
        if (!DllCall("IsWindowVisible", "Ptr", this.Gui.Hwnd))
            return
        pos := this.CursorToImage()
        if (!pos.in)
            return
        this.lastPickTick := A_TickCount
        this.PickAt(pos.ix, pos.iy)
    }

    ; ---------------- 输入 ----------------
    InputTick() {
        if (this.Gui == "" || this.PicW <= 0)
            return
        if (!DllCall("IsWindowVisible", "Ptr", this.Gui.Hwnd))
            return

        down := GetKeyState("LButton", "P")
        pos := this.CursorToImage()

        ; 按下起点
        if (down && !this.wasDown) {
            this.pressIn := pos.in
            this.pressX := pos.in ? pos.px : 0
            this.pressY := pos.in ? pos.py : 0
            this.moved := false
            this.lastPanX := pos.in ? pos.px : 0
            this.lastPanY := pos.in ? pos.py : 0
        }

        ; 位移判定（区分点击与拖动）
        if (down && pos.in && this.pressIn) {
            if (Abs(pos.px - this.pressX) + Abs(pos.py - this.pressY) > 4)
                this.moved := true
        }

        if (this.CropMode) {
            if (down && pos.in) {
                if (!this.dragActive) {
                    this.dragActive := true
                    ; 先看是不是抓住了某个角手柄；抓住就以上面那个对角为锚点缩放
                    if (!this.TryStartResize(pos)) {
                        this.AnchorX := pos.ix
                        this.AnchorY := pos.iy
                    }
                    this.UpdateSelection(pos.ix, pos.iy)
                }
                this.UpdateSelection(pos.ix, pos.iy)
                this.RenderPreview()
            }
            else if (!down && this.dragActive) {
                this.dragActive := false
                this.UpdateButtons()
                this.RenderPreview()
            }
        }
        else if (this.PickMode) {
            if (!down && this.wasDown && pos.in && !this.moved && (A_TickCount - this.lastPickTick > 200)) {
                this.lastPickTick := A_TickCount
                this.PickAt(pos.ix, pos.iy)
            }
        }
        else {
            ; 平移：拖动时移动视口
            if (down && pos.in && this.lastPanTick !== "" && (A_TickCount - this.lastPanTick > 35)) {
                dx := pos.px - this.lastPanX
                dy := pos.py - this.lastPanY
                if (dx != 0 || dy != 0) {
                    this.PanX -= dx * this.ViewW / this.PicW
                    this.PanY -= dy * this.ViewH / this.PicH
                    this.ClampPan()
                    this.lastPanX := pos.px
                    this.lastPanY := pos.py
                    this.lastPanTick := A_TickCount
                    this.RenderPreview()
                }
            }
            if (down && pos.in) {
                this.lastPanX := pos.px
                this.lastPanY := pos.py
            }
        }

        this.wasDown := down
    }

    ; 命中四角手柄？命中则把锚点设为对角，返回 true
    TryStartResize(pos) {
        if (this.SelW < 2 || this.SelH < 2)
            return false
        if (this.ViewW <= 0 || this.ViewH <= 0)
            return false

        sx := this.PicW / this.ViewW
        sy := this.PicH / this.ViewH
        x1 := (this.SelX - this.ViewX) * sx
        y1 := (this.SelY - this.ViewY) * sy
        x2 := (this.SelX + this.SelW - this.ViewX) * sx
        y2 := (this.SelY + this.SelH - this.ViewY) * sy

        ; 容差自适应：小选区里 10px 会盖住几乎整个框，按短边 1/3 收缩
        tol := Min(10, Max(3, Floor(Min(this.SelW * sx, this.SelH * sy) / 3)))

        ; 左上角 -> 锚点取右下角
        if (Abs(pos.px - x1) <= tol && Abs(pos.py - y1) <= tol) {
            this.AnchorX := this.SelX + this.SelW - 1
            this.AnchorY := this.SelY + this.SelH - 1
            return true
        }
        ; 右下角 -> 锚点取左上角
        if (Abs(pos.px - x2) <= tol && Abs(pos.py - y2) <= tol) {
            this.AnchorX := this.SelX
            this.AnchorY := this.SelY
            return true
        }
        ; 右上角 -> 锚点取左下角
        if (Abs(pos.px - x2) <= tol && Abs(pos.py - y1) <= tol) {
            this.AnchorX := this.SelX
            this.AnchorY := this.SelY + this.SelH - 1
            return true
        }
        ; 左下角 -> 锚点取右上角
        if (Abs(pos.px - x1) <= tol && Abs(pos.py - y2) <= tol) {
            this.AnchorX := this.SelX + this.SelW - 1
            this.AnchorY := this.SelY
            return true
        }
        return false
    }

    ; 由"锚点 + 当前点"算矩形：支持任意方向拖动；右/下边界包含最后一列一行
    UpdateSelection(cx, cy) {
        maxX := this.ViewX + this.ViewW - 1
        maxY := this.ViewY + this.ViewH - 1
        if (cx < this.ViewX)
            cx := this.ViewX
        if (cx > maxX)
            cx := maxX
        if (cy < this.ViewY)
            cy := this.ViewY
        if (cy > maxY)
            cy := maxY

        x1 := Min(this.AnchorX, cx)
        y1 := Min(this.AnchorY, cy)
        x2 := Max(this.AnchorX, cx)
        y2 := Max(this.AnchorY, cy)

        this.SelX := x1
        this.SelY := y1
        this.SelW := x2 - x1 + 1          ; +1：包含终点那一列/行
        this.SelH := y2 - y1 + 1
    }

    PickAt(ix, iy) {
        r := 0, g := 0, b := 0
        ret := DllCall("RMT_OpenCV.dll\GetImagePixelAt", "Str", this.TemplatePath
            , "Int", ix, "Int", iy, "Int*", &r, "Int*", &g, "Int*", &b, "CDecl Int")
        if (ret != 1)
            return
        this.AddColor(Format("{:02X}{:02X}{:02X}", r, g, b))
    }

    AddColor(hex) {
        hex := StrUpper(hex)
        for c in StrSplit(this.NormalizeColors(), ",") {
            if (c == hex)
                return
        }
        cur := this.NormalizeColors()
        this.Colors := (cur = "" ? hex : cur "," hex)
        this.ColorCon.Value := this.Colors
        this.RenderPreview()
    }

    ; ---------------- 滚轮缩放 ----------------
    OnWheelUp(*) {
        this.ZoomAt(1.25)
    }

    OnWheelDown(*) {
        this.ZoomAt(1 / 1.25)
    }

    ZoomAt(factor) {
        if (this.OrigW <= 0)
            return
        pos := this.CursorToImage()
        if (!pos.in)
            return

        newZoom := this.Zoom * factor
        if (newZoom < 0.1)
            newZoom := 0.1
        if (newZoom > 16.0)
            newZoom := 16.0
        if (Abs(newZoom - this.Zoom) < 0.001)
            return

        ixF := this.ViewX + pos.px * this.ViewW / this.PicW
        iyF := this.ViewY + pos.py * this.ViewH / this.PicH
        fracX := pos.px / this.PicW
        fracY := pos.py / this.PicH

        this.Zoom := newZoom
        this.UpdateViewSize()

        this.PanX := ixF - fracX * this.ViewW
        this.PanY := iyF - fracY * this.ViewH
        this.ClampPan()
        this.RenderPreview()
    }

    ; 适应窗口：整个图片刚好放进 300x300 取景框（小图不放大，保持 1:1）
    FitToWindow() {
        if (this.OrigW <= 0 || this.OrigH <= 0)
            return
        ; 取景框填满：小图放大、大图缩小，不再设 1.0 上限
        ; （18x18 这种小图原来只显示 18 像素大，就是被 1.0 卡住的）
        z := Min(this.CanvasSize / this.OrigW, this.CanvasSize / this.OrigH, 16.0)
        ; 传给 DLL 的是整数百分比，这里向下取整对齐，
        ; 否则 0.375 会被当成 38% 渲染，边缘被裁掉几个像素
        z := Floor(z * 100) / 100
        if (z < 0.1)
            z := 0.1
        this.Zoom := z
        this.UpdateViewSize()
        this.PanX := Max(0.0, (this.OrigW - this.ViewW) / 2.0)
        this.PanY := Max(0.0, (this.OrigH - this.ViewH) / 2.0)
        this.ClampPan()
        this.RenderPreview()
    }

    UpdateViewSize() {
        ; 1:1 取景框：视口 = 画布边长 / 缩放（正方形 → 像素格必为正方形）
        if (this.OrigW <= 0)
            return
        side := this.CanvasSize
        vw := Max(1, Floor(side / this.Zoom))
        vh := Max(1, Floor(side / this.Zoom))
        if (vw > this.OrigW)
            vw := this.OrigW
        if (vh > this.OrigH)
            vh := this.OrigH
        this.ViewW := vw
        this.ViewH := vh
        this.ClampPan()
    }

    ClampPan() {
        maxX := this.OrigW - this.ViewW
        maxY := this.OrigH - this.ViewH
        if (maxX < 0)
            maxX := 0
        if (maxY < 0)
            maxY := 0
        if (this.PanX < 0)
            this.PanX := 0
        if (this.PanY < 0)
            this.PanY := 0
        if (this.PanX > maxX)
            this.PanX := maxX
        if (this.PanY > maxY)
            this.PanY := maxY
        this.ViewX := Round(this.PanX)
        this.ViewY := Round(this.PanY)
    }

    ; 取统一带点的后缀（AHK 的 SplitPath 返回的 Ext 不带点，容易拼错）
    FileExt(path) {
        SplitPath(path, , , &ext)
        ext := Trim(ext)
        if (ext = "")
            return ".png"
        return (SubStr(ext, 1, 1) = ".") ? ext : "." ext
    }

    ; ---------------- 文件名 ----------------
    RefreshName() {
        if (this.NameCon == "")
            return
        SplitPath(this.TemplatePath, , , , &nameNoExt)
        ext := this.FileExt(this.TemplatePath)
        this.NameExt := ext
        this.NameCon.Value := nameNoExt          ; 框里只放主名，扩展名固定在外面
        this.NameExtCon.Text := ext
    }

    OnRenameFile() {
        if (this.TemplatePath == "")
            return
        name := Trim(this.NameCon.Value)
        if (name == "")
            return

        SplitPath(this.TemplatePath, , &dir)
        ext := this.FileExt(this.TemplatePath)

        ; 用户可能手滑把后缀也打进去了，统一剥掉，后缀一律用固定的
        name := RegExReplace(name, "\.\w{1,5}$", "")
        ; 去掉 Windows 非法字符
        for bad in ["\", "/", ":", "*", "?", Chr(34), "<", ">", "|"]
            name := StrReplace(name, bad, "_")
        if (Trim(name) == "")
            return

        newPath := dir "\" name ext
        if (newPath == this.TemplatePath)
            return
        if FileExist(newPath) {
            MsgBox(GetLang("同名文件已存在：") newPath)
            return
        }

        try {
            FileMove(this.TemplatePath, newPath)
        } catch as e {
            MsgBox(GetLang("重命名失败：") e.Message)
            return
        }

        this.TemplatePath := newPath
        this.RefreshName()
        this.StatCon.Text := GetLang("已重命名为：") name ext

        action := this.CropAction
        if (action != "")
            action(newPath)
    }

    ; ---------------- 裁剪 ----------------
    OnApplyCrop() {
        if (this.SelW < 2 || this.SelH < 2) {
            MsgBox(GetLang("请先点【裁剪】并在图上拖拽框选一块区域"))
            return
        }

        src := this.TemplatePath
        SplitPath(src, &nameNoExt, &dir, &ext)
        if (ext = "")
            ext := ".png"

        ; 先裁到临时文件，成功后再覆盖原图 —— 裁失败也不会把原图弄坏
        tmp := A_Temp "\RMT_crop_tmp.png"
        if FileExist(tmp)
            FileDelete(tmp)

        ret := DllCall("RMT_OpenCV.dll\CropImageFile", "Str", src
            , "Int", this.SelX, "Int", this.SelY, "Int", this.SelW, "Int", this.SelH
            , "Str", tmp, "CDecl Int")
        if (ret != 1) {
            MsgBox(GetLang("裁剪失败：") this.GetErrText())
            return
        }

        ; 模板是 bmp 之类时，DLL 只能编 PNG，就顺势换成同名 png
        target := src
        if (StrLower(ext) != ".png") {
            target := dir "\" nameNoExt ".png"
            try FileDelete(src)
        }
        if (!FileMove(tmp, target, true)) {
            MsgBox(GetLang("覆盖原图失败：") target)
            return
        }

        this.TemplatePath := target
        this.Zoom := 0            ; 置 0 触发下一帧重新适应窗口
        this.SelW := 0
        this.SelH := 0
        this.OrigW := 0
        this.OrigH := 0
        this.PanX := 0.0
        this.PanY := 0.0
        this.ViewW := 0
        this.ViewH := 0

        action := this.CropAction
        if (action != "")
            action(target)

        this.CropMode := false
        this.RefreshName()
        this.UpdateButtons()
        this.RenderPreview()
        this.StatCon.Text := GetLang("已裁剪并覆盖原图：") target
    }

    GetErrText() {
        try {
            pBuf := DllCall("RMT_OpenCV.dll\GetFilterLastError", "CDecl Ptr")
            return pBuf ? StrGet(pBuf, "UTF-16") : ""
        } catch {
            return ""
        }
    }

    ; ---------------- 渲染 ----------------
    RenderPreview() {
        if (this.TemplatePath == "" || !FileExist(this.TemplatePath)) {
            this.StatCon.Text := GetLang("未设置搜索图片")
            return
        }

        reason := OpenCvEnsure()
        if (reason != "") {
            this.StatCon.Text := GetLang("OpenCV 插件不可用")
            return
        }

        if (this.OrigW <= 0) {
            this.Zoom := 1.0
            this.PanX := 0.0
            this.PanY := 0.0
            this.ViewX := 0
            this.ViewY := 0
        }

        origFile := A_Temp "\RMT_KeepOrig.png"
        effectFile := A_Temp "\RMT_KeepEffect.png"

        if (!this.CtrlRectPhysical(this.PicLeftCon, &ox0, &oy0, &cw, &ch)) {
            cw := this.CanvasSize
            ch := this.CanvasSize
        }

        this.ViewX := Round(this.PanX)
        this.ViewY := Round(this.PanY)

        valid := 0, total := 0, pw := 0, ph := 0, ow := 0, oh := 0
        bx := 0, by := 0, bw := 0, bh := 0

        ret := DllCall("RMT_OpenCV.dll\RenderFilterPreview"
            , "Str", this.TemplatePath
            , "Str", this.NormalizeColors()
            , "Int", this.GetTolerance()
            , "Int", 1
            , "Int", cw
            , "Int", ch
            , "Int", this.ViewX, "Int", this.ViewY
            , "Int", this.ViewW, "Int", this.ViewH
            , "Int", this.SelX, "Int", this.SelY, "Int", this.SelW, "Int", this.SelH
            , "Int", 1
            , "Int", Round(this.Zoom * 100)
            , "Str", origFile
            , "Str", effectFile
            , "Int*", &valid, "Int*", &total
            , "Int*", &pw, "Int*", &ph
            , "Int*", &ow, "Int*", &oh
            , "Int*", &bx, "Int*", &by, "Int*", &bw, "Int*", &bh
            , "CDecl Int")

        if (ret != 1) {
            errPtr := DllCall("RMT_OpenCV.dll\GetFilterLastError", "CDecl Ptr")
            errText := errPtr ? StrGet(errPtr, "UTF-16") : ""
            this.StatCon.Text := errText
            return
        }

        this.OrigW := ow
        this.OrigH := oh
        this.BoxW := bw
        this.BoxH := bh
        this.PicW := pw
        this.PicH := ph

        if (this.ViewW <= 0 || this.ViewH <= 0) {
            ; 首次打开 / 换图后：默认适应窗口，先让人看到整张图
            this.FitToWindow()
            return
        }

        this.OffX := (cw - pw) // 2
        this.OffY := (ch - ph) // 2

        try this.PicLeftCon.Value := origFile
        try this.PicRightCon.Value := effectFile

        pct := total > 0 ? Round(valid * 100 / total, 1) : 0
        msg := Format(GetLang("保留 {}/{} 像素（占整图 {}%）"), valid, total, pct)
        if (bw > 0 && bh > 0) {
            msg .= Format(GetLang("　·　匹配区 {}x{}"), bw, bh)
            boxPct := Round(valid * 100 / (bw * bh), 1)
            msg .= Format(GetLang("　·　占匹配区 {}%"), boxPct)
        }
        msg .= Format(GetLang("　·　缩放 {}x"), Round(this.Zoom, 2))
        if (this.SelW > 1 && this.SelH > 1)
            msg .= Format(GetLang("　·　选区 {}x{} @ ({},{})"), this.SelW, this.SelH, this.SelX, this.SelY)
        this.StatCon.Text := msg
    }
}
