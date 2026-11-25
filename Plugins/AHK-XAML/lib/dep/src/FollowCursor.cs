// =============================================================================
// 引擎内跟随光标：把 Line 的第二端点交给引擎逐帧按光标位置更新。
// 替代原 AHK 每 16ms 两条同步 WM_COPYDATA 的做法，AHK 侧不再被逐帧调用切碎。
// =============================================================================
using System;
using System.Windows;
using System.Windows.Shapes;
using System.Windows.Threading;

public partial class AhkWpfEngine
{
    private DispatcherTimer _followCursorTimer;
    private Line _followCursorLine;
    private bool _followCursorClosedHooked;

    // value 非 "0" 即开启；重复调用等价于重设目标（先停旧表再起新表）
    private void SetFollowCursor(Line line, string value)
    {
        StopFollowCursor();
        if (line == null || value == "0")
            return;
        _followCursorLine = line;
        if (!_followCursorClosedHooked && win != null)
        {
            _followCursorClosedHooked = true;
            // 定时器持有窗口引用：窗口关掉必须停表，否则会继续按已卸载的可视树取坐标
            win.Closed += (s, e) => StopFollowCursor();
        }
        DispatcherTimer timer = new DispatcherTimer(DispatcherPriority.Render);
        timer.Interval = TimeSpan.FromMilliseconds(16);
        timer.Tick += (s, e) => FollowCursorTick();
        _followCursorTimer = timer;
        // 首帧就把端点对准真实光标；不要等待用户首次移动或下一次计时器触发。
        // 建窗初期视觉树可能尚未就绪；此时仍需启动计时器供后续帧重试。
        FollowCursorTick();
        if (_followCursorTimer == timer)
            timer.Start();
    }

    private void StopFollowCursor()
    {
        if (_followCursorTimer != null)
        {
            try { _followCursorTimer.Stop(); } catch { }
            _followCursorTimer = null;
        }
        _followCursorLine = null;
    }

    private void FollowCursorTick()
    {
        Line line = _followCursorLine;
        if (line == null || win == null || !win.IsVisible)
        {
            StopFollowCursor();
            return;
        }
        FrameworkElement host = line.Parent as FrameworkElement;
        // 控件还没挂进可视树（首帧之前）先不动，等它挂上再开始跟
        if (host == null || !line.IsLoaded)
            return;
        // 从系统屏幕坐标换算到轮盘 Canvas：Mouse.GetPosition 在其他进程的窗口
        // （尤其不同 DPI 感知模式）中触发时，首帧可能沿用鼠标事件的旧坐标。
        // GetCursorPos 总是当前设备像素坐标，PointFromScreen 按 WPF 所在监视器换算为 DIP。
        POINT cursor;
        if (!GetCursorPos(out cursor))
            return;
        Point p;
        try { p = host.PointFromScreen(new Point(cursor.x, cursor.y)); }
        catch { return; }
        // 没移动就不赋值：每次赋值都会让分层窗整窗重绘一次（软件渲染）
        if (Math.Abs(p.X - line.X2) < 0.5 && Math.Abs(p.Y - line.Y2) < 0.5)
            return;
        line.X2 = p.X;
        line.Y2 = p.Y;
    }
}
