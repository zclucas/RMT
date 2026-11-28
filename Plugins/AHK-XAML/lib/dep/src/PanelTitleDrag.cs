using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

public partial class AhkWpfEngine
{
    [DllImport("user32.dll", EntryPoint = "SetThreadDpiAwarenessContext")]
    private static extern IntPtr SetPanelThreadDpi(IntPtr context);

    private sealed class PanelDpiScope : IDisposable
    {
        private IntPtr previous;
        public PanelDpiScope()
        {
            try
            {
                previous = SetPanelThreadDpi(new IntPtr(-4));
                if (previous == IntPtr.Zero) previous = SetPanelThreadDpi(new IntPtr(-3));
            }
            catch (EntryPointNotFoundException) { }
        }
        public void Dispose()
        {
            if (previous != IntPtr.Zero) SetPanelThreadDpi(previous);
        }
    }

    // WPF Left/Top are DIPs. A panel's saved screen point is physical, so do
    // native placement after EnsureHandle, before Show, in the target monitor.
    private void PlacePanelScreenPosition()
    {
        if (!win.Resources.Contains("RmtPanelScreenPosition")) return;
        var point = (Point)win.Resources["RmtPanelScreenPosition"];
        using (new PanelDpiScope())
            SetWindowPos(new WindowInteropHelper(win).Handle, IntPtr.Zero,
                (int)point.X, (int)point.Y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }

    private FrameworkElement _panelTitleDrag;
    private string _panelTitleDragName;
    private POINT _panelTitleMouse;
    private RECT _panelTitleWindow;
    private bool _panelTitleMoved;
    private bool _panelTitleMoving;
    private int _panelTitleBeat;
    private bool _panelTitlePending;
    private POINT _panelTitleLanding;
    private int _panelTitlePendingAt;

    [StructLayout(LayoutKind.Sequential)]
    private struct PanelWindowPos
    {
        public IntPtr hwnd, insertAfter;
        public int x, y, cx, cy;
        public uint flags;
    }

    // Keep follow updates from moving the window between mouse-down and the
    // asynchronous AHK notification. Only this UI thread owns its position then.
    private void GuardPanelTitlePosition(IntPtr lParam)
    {
        if (_panelTitleMoving || lParam == IntPtr.Zero)
            return;
        var pos = (PanelWindowPos)Marshal.PtrToStructure(lParam, typeof(PanelWindowPos));
        if (_panelTitleDrag == null)
        {
            if (!_panelTitlePending || (pos.flags & 0x0002) != 0) return;
            // AHK acknowledges the FIFO end event by applying its physical
            // landing. Reject old follow/activation positions until that point.
            if ((pos.x == _panelTitleLanding.x && pos.y == _panelTitleLanding.y)
                || unchecked(Environment.TickCount - _panelTitlePendingAt) > 3000)
            {
                _panelTitlePending = false;
                return;
            }
        }
        pos.flags |= 0x0002; // SWP_NOMOVE
        Marshal.StructureToPtr(pos, lParam, false);
    }

    private void BindPanelTitleDrag(string name, FrameworkElement title)
    {
        title.PreviewMouseLeftButtonDown += (s, e) =>
        {
            // Test actual interactive descendants, not a guessed strip width.
            DependencyObject node = e.OriginalSource as DependencyObject;
            while (node != null && node != title)
            {
                if (node is ButtonBase) return;
                node = node is Visual || node is System.Windows.Media.Media3D.Visual3D
                    ? VisualTreeHelper.GetParent(node) : LogicalTreeHelper.GetParent(node);
            }
            if (_panelTitleDrag != null) return;
            if (e.ClickCount >= 2)
            {
                SendPanelTitleGesture(name, "doubleclick");
                e.Handled = true;
                return;
            }
            IntPtr hwnd = new WindowInteropHelper(win).Handle;
            using (new PanelDpiScope())
                if (!GetCursorPos(out _panelTitleMouse) || !GetWindowRect(hwnd, out _panelTitleWindow))
                    return;
            if (!title.CaptureMouse()) return;
            _panelTitlePending = false;
            _panelTitleDrag = title;
            _panelTitleDragName = name;
            _panelTitleMoved = false;
            _panelTitleBeat = Environment.TickCount;
            SendPanelTitleGesture(name, "down");
            e.Handled = true;
        };
        win.PreviewMouseMove += (s, e) =>
        {
            if (_panelTitleDrag != title) return;
            if (e.LeftButton != MouseButtonState.Pressed)
            {
                FinishPanelTitleDrag();
                return;
            }
            MovePanelTitle();
            int now = Environment.TickCount;
            if (unchecked(now - _panelTitleBeat) >= 60)
            {
                _panelTitleBeat = now;
                SendPanelTitleGesture(name, "drag");
            }
            e.Handled = true;
        };
        win.PreviewMouseLeftButtonUp += (s, e) =>
        {
            if (_panelTitleDrag != title) return;
            MovePanelTitle();
            FinishPanelTitleDrag();
            e.Handled = true;
        };
        title.LostMouseCapture += (s, e) =>
        {
            if (_panelTitleDrag == title) FinishPanelTitleDrag();
        };
        win.Deactivated += (s, e) => FinishPanelTitleDrag();
        win.Closed += (s, e) => FinishPanelTitleDrag();
    }

    private void MovePanelTitle()
    {
        using (new PanelDpiScope())
        {
            POINT mouse;
            if (_panelTitleDrag == null || !GetCursorPos(out mouse)) return;
            int dx = mouse.x - _panelTitleMouse.x, dy = mouse.y - _panelTitleMouse.y;
            var source = PresentationSource.FromVisual(_panelTitleDrag);
            var scale = source != null && source.CompositionTarget != null
                ? source.CompositionTarget.TransformToDevice : Matrix.Identity;
            if (!_panelTitleMoved
                && Math.Abs(dx) <= SystemParameters.MinimumHorizontalDragDistance * scale.M11
                && Math.Abs(dy) <= SystemParameters.MinimumVerticalDragDistance * scale.M22)
                return;
            _panelTitleMoved = true;
            _panelTitleMoving = true;
            try
            {
                // Signed physical screen coordinates also cover monitors left/above
                // the primary display, without using the primary display's DPI.
                SetWindowPos(new WindowInteropHelper(win).Handle, IntPtr.Zero,
                    _panelTitleWindow.left + dx, _panelTitleWindow.top + dy,
                    0, 0, 0x0001 | 0x0004 | 0x0010);
            }
            finally { _panelTitleMoving = false; }
        }
    }

    private void FinishPanelTitleDrag()
    {
        var title = _panelTitleDrag;
        if (title == null) return;
        string name = _panelTitleDragName;
        RECT rect = new RECT();
        bool moved;
        using (new PanelDpiScope())
            moved = _panelTitleMoved && GetWindowRect(new WindowInteropHelper(win).Handle, out rect);
        string gesture = moved ? "move|" + rect.left + "," + rect.top : "up";
        if (moved)
        {
            _panelTitlePending = true;
            _panelTitleLanding = new POINT { x = rect.left, y = rect.top };
            _panelTitlePendingAt = Environment.TickCount;
        }
        // Clear before releasing capture: LostMouseCapture is synchronous.
        _panelTitleDrag = null;
        _panelTitleDragName = null;
        _panelTitleMoved = false;
        if (title.IsMouseCaptured) title.ReleaseMouseCapture();
        SendPanelTitleGesture(name, gesture);
    }

    private void SendPanelTitleGesture(string name, string gesture)
    {
        SendToAhkAsync("EVENT|" + winId + "|" + name + "|PanelTitleDrag|"
            + BridgeUtil.LengthPrefix(gesture) + "\n");
    }
}
