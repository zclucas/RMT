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
        // Mouse.GetPosition 返回的就是 DIP 相对坐标（光标在窗外也有效），无需再按 dpiScale 换算
        Point p;
        try { p = System.Windows.Input.Mouse.GetPosition(host); }
        catch { return; }
        // 没移动就不赋值：每次赋值都会让分层窗整窗重绘一次（软件渲染）
        if (Math.Abs(p.X - line.X2) < 0.5 && Math.Abs(p.Y - line.Y2) < 0.5)
            return;
        line.X2 = p.X;
        line.Y2 = p.Y;
    }
}
