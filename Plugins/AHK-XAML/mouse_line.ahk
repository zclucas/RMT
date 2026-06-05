#Requires AutoHotkey v2.0
#SingleInstance Force

; ====== XAML 鼠标划线测试 ======
;
; 技术架构：
;   渲染层：WPF 原生 Line 元素（X1/Y1 固定起点，X2/Y2 动态终点）
;            参考: https://learn.microsoft.com/zh-cn/dotnet/desktop/wpf/graphics-multimedia/how-to-create-a-line-using-a-linegeometry
;   数据源：AHK 定时器轮询鼠标坐标（因 AHK-XAML 桥接层的 MouseMove 事件不传递位置参数）
;   更新通道：ui.Update() → WM_COPYDATA → WPF 属性变更 → 自动重绘

#Include lib/XAML_Host.ahk
#Include lib/XAML_Generator.ahk

class MouseLineDemo {
    __New() {
        this.ui := ""
        this.winW := 600
        this.winH := 500
        this.cx := 300          ; 固定点 X（Canvas 内中心）
        this.cy := 232          ; 固定点 Y（Canvas 内中心 = (500-36)/2）
        this.timerFn := ""
        this.isRunning := false
    }

    Show() {
        ; ---- 构建 XAML 窗口 ----
        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        win.Width(this.winW).Height(this.winH)
        win.WindowStyle("None").AllowsTransparency("True")
        win.Background("#FF1E1E2E")
        win.ShowInTaskbar("False").Topmost("True")
        win.ResizeMode("NoResize").WindowStartupLocation("CenterScreen")

        ; 根容器：Window 只能有一个子元素（Content），用 Grid 包裹所有内容
        rootGrid := win.Add("Grid").Name("RootGrid")
        rootGrid.Rows("36", "*")

        ; ---- 第1行：标题栏 ----
        titleBar := rootGrid.Add("Grid").Name("TitleBar").Grid_Row(0)
            .Background("#FF2D2D44")
        titleSp := titleBar.Add("StackPanel")
            .Orientation("Horizontal").VerticalAlignment("Center").Margin("12,0,0,0")
        titleSp.Add("TextBlock").Text("XAML 鼠标划线演示")
            .Foreground("#FFCCCCCC").FontSize(13).FontWeight("SemiBold")
            .VerticalAlignment("Center")

        closeBtn := titleBar.Add("Button").Name("BtnClose")
            .Content("✕").Width(32).Height(28)
            .Background("Transparent").BorderThickness(0)
            .Foreground("#FFAAAAAA").FontSize(12)
            .HorizontalAlignment("Right").Margin("0,0,4,0")
            .Cursor("Hand").VerticalAlignment("Center")

        ; ---- 第2行：主画布（Canvas）----
        canvasH := this.winH - 36
        canvas := rootGrid.Add("Canvas").Name("RootCanvas").Grid_Row(1)
        canvas.Width(this.winW).Height(canvasH)

        ; === WPF Line 元素：线的起点固定在 Canvas 中心 ===
        ; Line 由 (X1,Y1) 和 (X2,Y2) 两个端点定义
        ; 起点(X1,Y1)不变，终点(X2,Y2)随鼠标实时更新
        line := canvas.Add("Line").Name("SwipeLine")
        line.X1(this.cx).Y1(this.cy)         ; 起点：固定中心点
        line.X2(this.cx).Y2(this.cy)           ; 终点：初始与起点重合
        line.Stroke("#FF4FC3F7").StrokeThickness(2.5)
        line.IsHitTestVisible("False")         ; 不拦截鼠标事件

        ; 固定中心点标记（红色圆圈 = 线的起点）
        centerDot := canvas.Add("Ellipse").Name("CenterDot")
        centerDot.Width(12).Height(12)
        centerDot.Canvas_Left(this.cx - 6).Canvas_Top(this.cy - 6)
        centerDot.Fill("#FFFF5555").Stroke("#FFFFFFFF").StrokeThickness(2)

        ; 鼠标跟随点标记（蓝色圆圈 = 线的终点）
        mouseDot := canvas.Add("Ellipse").Name("MouseDot")
        mouseDot.Width(10).Height(10)
        mouseDot.Fill("#FF55AAFF").Stroke("#FFFFFFFF").StrokeThickness(1.5)
        mouseDot.IsHitTestVisible("False")

        ; 信息面板
        infoBg := canvas.Add("Border").Name("InfoPanel")
        infoBg.Background("#33FFFFFF").CornerRadius(6).Padding("10,6")
        infoBg.Canvas_Left(10).Canvas_Top(10)

        infoSp := infoBg.Add("StackPanel").Orientation("Horizontal")
        infoSp.Add("TextBlock").Name("TxtCoords").Text("鼠标: (--, --)")
            .Foreground("#FFCCCCCC").FontSize(11).FontFamily("Cascadia Code, Consolas")
        infoSp.Add("TextBlock").Text("  |  ").Foreground("#FF666666").FontSize(11)
        infoSp.Add("TextBlock").Name("TxtDist").Text("距离: 0 px")
            .Foreground("#FF4FC3F7").FontSize(11).FontFamily("Cascadia Code, Consolas")
        infoSp.Add("TextBlock").Text("  |  ").Foreground("#FF666666").FontSize(11)
        infoSp.Add("TextBlock").Name("TxtAngle").Text("角度: 0°")
            .Foreground("#FFAA88FF").FontSize(11).FontFamily("Cascadia Code, Consolas")

        ; 托管到 WPF 引擎
        this.ui := XAMLHost(win.ToString(), "", 0)

        ; 绑定关闭按钮和标题栏拖拽事件
        this.ui.OnEvent("BtnClose", "Click", (*) => this.Close())
        this.ui.OnEvent("TitleBar", "PreviewMouseLeftButtonDown", (*) => this._OnTitleDown())
        this.ui.OnEvent("TitleBar", "PreviewMouseMove", (*) => this._OnTitleMove())
        this.ui.OnEvent("TitleBar", "PreviewMouseLeftButtonUp", (*) => this._OnTitleUp())

        ; 显示窗口
        this.ui.Show()

        ; 等待 WPF 窗口就绪
        startTime := A_TickCount
        while (!this.ui.wpfHwnd && A_TickCount - startTime < 5000)
            Sleep(20)

        if (!this.ui.wpfHwnd) {
            MsgBox("WPF 窗口创建失败！")
            return
        }

        ; 启动定时器：获取鼠标坐标并更新 WPF Line 的终点
        ; （注：AHK-XAML 桥接的 MouseMove 事件不传递鼠标位置参数，
        ;   因此需要通过 AHK 侧定时器获取坐标后通过 ui.Update 推送到 WPF）
        this.isRunning := true
        this.timerFn := ObjBindMethod(this, "_OnTick")
        SetTimer(this.timerFn, 16)    ; ~60fps
    }

    ; ---- 定时器回调：获取鼠标坐标 → 更新 WPF Line 终点 ----
    _OnTick() {
        if (!this.isRunning || !this.ui || !this.ui.wpfHwnd)
            return

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)

        ; 将屏幕坐标转换为窗口内坐标
        WinGetPos(&wx, &wy, , , "ahk_id " this.ui.wpfHwnd)
        relX := mx - wx
        relY := my - wy - 36       ; 减去标题栏高度（Canvas 在 Row 1）

        ; --- 通过 ui.Update 推送新坐标到 WPF Line 元素 ---
        ; WPF 收到属性变更后自动重绘线条，无需手动 GDI 操作
        this.ui.Update("SwipeLine", "X2", String(relX))
        this.ui.Update("SwipeLine", "Y2", String(relY))

        ; 更新鼠标跟随圆点
        this.ui.Update("MouseDot", "Canvas.Left", String(relX - 5))
        this.ui.Update("MouseDot", "Canvas.Top", String(relY - 5))

        ; 计算距离和角度
        dx := relX - this.cx
        dy := relY - this.cy
        dist := Round(Sqrt(dx * dx + dy * dy), 1)
        angle := Round(this._Atan2(dy, dx), 1)

        this.ui.Update("TxtCoords", "Text", "鼠标: (" Round(relX) ", " Round(relY) ")")
        this.ui.Update("TxtDist", "Text", "距离: " dist " px")
        this.ui.Update("TxtAngle", "Text", "角度: " angle "°")
    }

    ; ---- 标题栏拖拽 ----
    _isDragging := false
    _dragOffsetX := 0
    _dragOffsetY := 0

    _OnTitleDown() {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinGetPos(&wx, &wy, , , "ahk_id " this.ui.wpfHwnd)
        this._dragOffsetX := mx - wx
        this._dragOffsetY := my - wy
        this._isDragging := true
    }

    _OnTitleMove() {
        if (!this._isDragging || !this.ui.wpfHwnd)
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinMove(mx - this._dragOffsetX, my - this._dragOffsetY, , , "ahk_id " this.ui.wpfHwnd)
    }

    _OnTitleUp() {
        this._isDragging := false
    }

    ; 用 AHK 内置 ATan 实现 Atan2（AHK v2 没有 ATan2 函数）
    _Atan2(y, x) {
        if (x > 0)
            return ATan(y / x)
        else if (x < 0 && y >= 0)
            return ATan(y / x) + 180
        else if (x < 0 && y < 0)
            return ATan(y / x) - 180
        else if (x == 0 && y > 0)
            return 90
        else if (x == 0 && y < 0)
            return -90
        return 0
    }

    Close() {
        this.isRunning := false
        if (this.timerFn) {
            SetTimer(this.timerFn, 0)
            this.timerFn := ""
        }
        if (IsObject(this.ui)) {
            try {
                this.ui.Update("Window", "Close", "")
                this.ui.Dispose()
            }
        }
        this.ui := ""
        ExitApp()
    }
}

; ---- 启动测试 ----
demo := MouseLineDemo()
demo.Show()

; 按 Esc 关闭
HotKey("Esc", (*) => demo.Close())
Persistent()
