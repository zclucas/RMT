// =============================================================================
// IPC command dispatch: WndProc/ProcessMessage/ProcessSingleMessage
// =============================================================================
using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Markup;
using Color = System.Windows.Media.Color;

#if ENABLE_AVALONEDIT
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.CodeCompletion;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Editing;
using ICSharpCode.AvalonEdit.Folding;
using ICSharpCode.AvalonEdit.Rendering;
using ICSharpCode.AvalonEdit.Search;
#endif
#if ENABLE_DOCUMENT
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
#endif
public partial class AhkWpfEngine
{
    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x004A)
        {
            try
            {
                var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
                byte[] bytes = new byte[cds.cbData];
                Marshal.Copy(cds.lpData, bytes, 0, cds.cbData);
                ProcessMessage(hwnd, Encoding.UTF8.GetString(bytes).TrimEnd('\0'));
            }
            catch { }
            handled = true;
        }
        else if (msg == 0x0084) // WM_NCHITTEST
        {
            try
            {
                // 只允许四角缩放：点落在窗口四边（非四角）时返回 HTBORDER，禁止单边调整大小
                try
                {
                    short px = (short)(lParam.ToInt64() & 0xFFFF);
                    short py = (short)((lParam.ToInt64() >> 16) & 0xFFFF);
                    RECT wr;
                    if (GetWindowRect(hwnd, out wr))
                    {
                        int band = 10; // 边缘带宽度（物理像素）
                        bool onLeft = px >= wr.left && px <= wr.left + band;
                        bool onRight = px >= wr.right - band && px <= wr.right;
                        bool onTop = py >= wr.top && py <= wr.top + band;
                        bool onBottom = py >= wr.bottom - band && py <= wr.bottom;
                        bool corner = (onLeft || onRight) && (onTop || onBottom);
                        if ((onLeft || onRight || onTop || onBottom) && !corner)
                        {
                            handled = true;
                            return new IntPtr(18); // HTBORDER：无缩放边框，拖拽无效
                        }
                    }
                }
                catch { }
                var btn = win.FindName("BtnMaximize") as System.Windows.Controls.Button;
                if (btn != null && btn.IsVisible)
                {
                    short screenX = (short)(lParam.ToInt64() & 0xFFFF);
                    short screenY = (short)((lParam.ToInt64() >> 16) & 0xFFFF);

                    Point topLeft = btn.PointToScreen(new Point(0, 0));
                    Point bottomRight = btn.PointToScreen(new Point(btn.ActualWidth, btn.ActualHeight));

                    if (screenX >= topLeft.X && screenX <= bottomRight.X &&
                        screenY >= topLeft.Y && screenY <= bottomRight.Y)
                    {
                        // Apply custom hover highlight (same as #20FFFFFF style trigger)
                        btn.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(0x20, 0xFF, 0xFF, 0xFF));

                        handled = true;
                        return new IntPtr(9); // HTMAXBUTTON
                    }
                    else
                    {
                        // Reset background if cursor moved off the button
                        if (btn.Background != System.Windows.Media.Brushes.Transparent)
                        {
                            btn.Background = System.Windows.Media.Brushes.Transparent;
                        }
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x0020) // WM_SETCURSOR
        {
            try
            {
                // 四边（HTLEFT=10 HTRIGHT=11 HTTOP=12 HTBOTTOM=15）：普通箭头光标，不提示缩放
                int htW = wParam.ToInt32() & 0xFFFF;
                if (htW == 10 || htW == 11 || htW == 12 || htW == 15)
                {
                    IntPtr hArrow = LoadCursor(IntPtr.Zero, 32512); // IDC_ARROW
                    if (hArrow != IntPtr.Zero)
                    {
                        SetCursor(hArrow);
                        handled = true;
                        return new IntPtr(1); // True
                    }
                }
                int hitTest = (int)(lParam.ToInt64() & 0xFFFF);
                if (hitTest == 9) // HTMAXBUTTON
                {
                    IntPtr hCursor = LoadCursor(IntPtr.Zero, 32649); // IDC_HAND
                    if (hCursor != IntPtr.Zero)
                    {
                        SetCursor(hCursor);
                        handled = true;
                        return new IntPtr(1); // True
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x02A2 || msg == 0x02A3) // WM_NCMOUSELEAVE or WM_MOUSELEAVE
        {
            try
            {
                var btn = win.FindName("BtnMaximize") as System.Windows.Controls.Button;
                if (btn != null && btn.Background != System.Windows.Media.Brushes.Transparent)
                {
                    btn.Background = System.Windows.Media.Brushes.Transparent;
                }
            }
            catch { }
        }
        else if (msg == 0x00A1) // WM_NCLBUTTONDOWN
        {
            if (wParam.ToInt32() == 9) // HTMAXBUTTON
            {
                win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                handled = true;
                return IntPtr.Zero;
            }
        }
        else if (msg == 0x0211) // WM_ENTERMENULOOP：系统菜单/弹出菜单打开
        {
            try
            {
                // Topmost / Win32 TOPMOST 窗的系统菜单会被压在窗口下方；菜单期间临时取消置顶
                _restoreTopmostAfterMenu = (win != null && win.Topmost);
                if (win != null)
                {
                    if (win.Topmost)
                        win.Topmost = false;
                    IntPtr h = new WindowInteropHelper(win).Handle;
                    if (h != IntPtr.Zero)
                        SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); // HWND_NOTOPMOST
                }
                SendToAhkAsync("EVENT|" + winId + "|Window|SysMenu|Open\n");
            }
            catch { }
        }
        else if (msg == 0x0212) // WM_EXITMENULOOP
        {
            try
            {
                if (win != null && _restoreTopmostAfterMenu)
                {
                    win.Topmost = true;
                    IntPtr h = new WindowInteropHelper(win).Handle;
                    if (h != IntPtr.Zero)
                        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); // HWND_TOPMOST
                }
                _restoreTopmostAfterMenu = false;
                SendToAhkAsync("EVENT|" + winId + "|Window|SysMenu|Close\n");
            }
            catch { }
        }
        else if (msg == 0x0024)
        { // WM_GETMINMAXINFO
            try
            {
                MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(lParam, typeof(MINMAXINFO));
                IntPtr monitor = MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
                if (monitor != IntPtr.Zero)
                {
                    MONITORINFO monitorInfo = new MONITORINFO();
                    monitorInfo.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                    GetMonitorInfo(monitor, ref monitorInfo);
                    RECT rcWorkArea = monitorInfo.rcWork;
                    RECT rcMonitorArea = monitorInfo.rcMonitor;
                    mmi.ptMaxPosition.x = Math.Abs(rcWorkArea.left - rcMonitorArea.left);
                    mmi.ptMaxPosition.y = Math.Abs(rcWorkArea.top - rcMonitorArea.top);
                    mmi.ptMaxSize.x = Math.Abs(rcWorkArea.right - rcWorkArea.left);
                    mmi.ptMaxSize.y = Math.Abs(rcWorkArea.bottom - rcWorkArea.top);
                }
                Marshal.StructureToPtr(mmi, lParam, true);
            }
            catch { }
        }
        else if (msg == 0x0214)
        { // WM_SIZING：仅四角等比缩放；四边（左/右/上/下）不允许单边调整宽高
            try
            {
                int edge = wParam.ToInt32();
                // 纯边拖拽（1=left 2=right 3=top 6=bottom）：恢复当前矩形，缩放无效
                if (edge == 1 || edge == 2 || edge == 3 || edge == 6)
                {
                    RECT cur;
                    if (GetWindowRect(hwnd, out cur))
                    {
                        Marshal.StructureToPtr(cur, lParam, false);
                        handled = true;
                        return IntPtr.Zero;
                    }
                }
                if (win != null && !double.IsNaN(win.Width) && !double.IsNaN(win.Height)
                    && win.Width > 0 && win.Height > 0)
                {
                    RECT rc = (RECT)Marshal.PtrToStructure(lParam, typeof(RECT));
                    double ratio = win.Width / win.Height;
                    int w = rc.right - rc.left;
                    int h = rc.bottom - rc.top;
                    if (w > 0 && h > 0)
                    {
                        // 4=left-top 5=right-top 7=left-bottom 8=right-bottom（四角）
                        bool hasLeft = (edge == 4 || edge == 7);
                        bool hasRight = (edge == 5 || edge == 8);
                        bool hasTop = (edge == 4 || edge == 5);
                        bool hasBottom = (edge == 7 || edge == 8);
                        // 有水平拖拽边时以宽定高，否则以高定宽，保证宽高比恒定
                        int newW, newH;
                        if (hasLeft || hasRight)
                        {
                            newW = w;
                            newH = (int)Math.Round(w / ratio);
                        }
                        else
                        {
                            newH = h;
                            newW = (int)Math.Round(h * ratio);
                        }
                        // 最小尺寸：设计尺寸的 45%（与比例一致），避免缩得过小
                        double minW = Math.Max(280, win.Width * 0.45);
                        double minH = minW / ratio;
                        if (newW < minW)
                        {
                            newW = (int)Math.Round(minW);
                            newH = (int)Math.Round(minW / ratio);
                        }
                        if (newH < minH)
                        {
                            newH = (int)Math.Round(minH);
                            newW = (int)Math.Round(minH * ratio);
                        }
                        if (hasRight) rc.right = rc.left + newW;
                        else if (hasLeft) rc.left = rc.right - newW;
                        if (hasBottom) rc.bottom = rc.top + newH;
                        else if (hasTop) rc.top = rc.bottom - newH;
                        Marshal.StructureToPtr(rc, lParam, false);
                        handled = true;
                        return IntPtr.Zero;
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x020A)
        { // WM_MOUSEWHEEL
            if (win != null && !win.IsEnabled) { handled = true; return IntPtr.Zero; }
            try
            {
                int delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
                DependencyObject target = System.Windows.Input.Mouse.DirectlyOver as DependencyObject;

                while (target != null)
                {
                    ScrollViewer sv = target as ScrollViewer;
                    if (sv != null && sv.VerticalScrollBarVisibility == ScrollBarVisibility.Disabled && sv.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled)
                    {
                        bool canScroll = (delta > 0 && sv.HorizontalOffset > 1.0) || (delta < 0 && (sv.ScrollableWidth - sv.HorizontalOffset) > 1.0);
                        if (canScroll)
                        {
                            sv.ScrollToHorizontalOffset(sv.HorizontalOffset - delta);
                            handled = true;
                            break;
                        }
                    }

                    if (target is System.Windows.Media.Visual || target is System.Windows.Media.Media3D.Visual3D)
                    {
                        target = System.Windows.Media.VisualTreeHelper.GetParent(target);
                    }
                    else
                    {
                        target = LogicalTreeHelper.GetParent(target);
                    }
                }
            }
            catch { }
        }
        else if (msg == 0x020E)
        { // WM_MOUSEHWHEEL
            if (win != null && !win.IsEnabled) { handled = true; return IntPtr.Zero; }
            try
            {
                int delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
                DependencyObject target = System.Windows.Input.Mouse.DirectlyOver as DependencyObject;
                while (target != null)
                {
                    ScrollViewer sv = target as ScrollViewer;
                    if (sv != null && sv.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled)
                    {
                        bool canScroll = (delta < 0 && sv.HorizontalOffset > 1.0) || (delta > 0 && (sv.ScrollableWidth - sv.HorizontalOffset) > 1.0);
                        if (canScroll)
                        {
                            sv.ScrollToHorizontalOffset(sv.HorizontalOffset + delta);
                            handled = true;
                            break;
                        }
                    }
                    if (target is System.Windows.Media.Visual || target is System.Windows.Media.Media3D.Visual3D)
                    {
                        target = System.Windows.Media.VisualTreeHelper.GetParent(target);
                    }
                    else
                    {
                        target = LogicalTreeHelper.GetParent(target);
                    }
                }
            }
            catch { }
        }
        return IntPtr.Zero;
    }

    private void ProcessMessage(IntPtr hwnd, string text)
    {
        foreach (string line in text.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                ProcessSingleMessage(hwnd, line);
            }
            catch (Exception ex)
            {
                if (EnableLogging)
                {
                    try { System.IO.File.AppendAllText(GetLogPath("AhkWpfDebug.log"), "ProcessMessage line failed: " + line + " => " + ex.Message + "\n"); } catch { }
                }
            }
        }
    }

    private void ProcessSingleMessage(IntPtr hwnd, string text)
    {
        string[] parts = text.Split(new[] { '|' }, 3);
        if (parts.Length < 2) return;
        if (parts.Length > 2)
        {
            parts[2] = parts[2].Replace("&#x0A;", "\n").Replace("&#x0D;", "\r");
        }

        // MQUERY: batched targeted query — returns values for specific controls in one IPC call
        // Format: MQUERY|ctrl1,ctrl2,ctrl3  or  MQUERY|*  (all tracked)
        if (parts[0] == "MQUERY" && parts.Length >= 2)
        {
            string query = parts.Length >= 3 ? parts[1] + "|" + parts[2] : parts[1];
            string stateData;
            if (query.Trim() == "*")
            {
                stateData = CollectState();
            }
            else
            {
                string[] names = query.Split(',');
                stateData = CollectStateFor(names);
            }
            int count = stateData.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;
            SendToAhk("MRESPONSE|" + winId + "|" + count + "\n" + stateData);
            return;
        }

        // CONFIG: runtime configuration changes
        // Format: CONFIG|Key|Value
        if (parts[0] == "CONFIG" && parts.Length >= 3)
        {
            if (parts[1] == "LightweightEvents")
            {
                LightweightEvents = parts[2] == "1" || parts[2].ToLower() == "true";
            }
            return;
        }

        // DEVTOOLS: Chrome-like developer tools hooks
        // Format: DEVTOOLS|Command|Arg
        if (parts[0] == "DEVTOOLS")
        {
            if (parts[1] == "GetTree")
            {
                string treeData = SerializeVisualTree(win);
                SendToAhk("EVENT|" + winId + "|Engine|DevToolsTree|" + BridgeUtil.LengthPrefix(treeData) + "\n");
            }
            else if (parts[1] == "Highlight" && parts.Length >= 3)
            {
                string elementName = parts[2];
                FrameworkElement element = null;
                if (elementName == "Window")
                {
                    element = win;
                }
                else if (!string.IsNullOrEmpty(elementName))
                {
                    element = FindElementByHash(win, elementName);
                    if (element == null)
                    {
                        element = win.FindName(elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        element = FindLogicalNodeDeep(win, elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        WalkVisualTree(win, (DependencyObject d) =>
                        {
                            if (element != null) return;
                            var fe = d as FrameworkElement;
                            if (fe != null && fe.Name == elementName)
                            {
                                element = fe;
                            }
                        });
                    }
                }

                SetHighlight(element, element != null);
            }
            else if (parts[1] == "GetProps" && parts.Length >= 3)
            {
                string elementName = parts[2];
                FrameworkElement element = null;
                if (elementName == "Window")
                {
                    element = win;
                }
                else if (!string.IsNullOrEmpty(elementName))
                {
                    element = FindElementByHash(win, elementName);
                    if (element == null)
                    {
                        element = win.FindName(elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        element = FindLogicalNodeDeep(win, elementName) as FrameworkElement;
                    }
                    if (element == null)
                    {
                        WalkVisualTree(win, (DependencyObject d) =>
                        {
                            if (element != null) return;
                            var fe = d as FrameworkElement;
                            if (fe != null && fe.Name == elementName)
                            {
                                element = fe;
                            }
                        });
                    }
                }

                if (element != null)
                {
                    string propsData = InspectElementProperties(element);
                    SendToAhk("EVENT|" + winId + "|Engine|DevToolsProps|" + BridgeUtil.LengthPrefix(elementName + "\n" + propsData) + "\n");
                }
            }
            return;
        }

        if (parts[0] == "AppWindow" && parts[1] == "InspectMode" && parts.Length >= 3)
        {
            _isInspectMode = parts[2] == "1" || parts[2].ToLower() == "true";
            if (_isInspectMode)
            {
                _lastHighlightedElement = null;
                win.PreviewMouseMove -= Win_InspectMouseMove;
                win.PreviewMouseDown -= Win_InspectMouseDown;
                win.PreviewMouseMove += Win_InspectMouseMove;
                win.PreviewMouseDown += Win_InspectMouseDown;
                win.Cursor = System.Windows.Input.Cursors.Cross;
            }
            else
            {
                win.PreviewMouseMove -= Win_InspectMouseMove;
                win.PreviewMouseDown -= Win_InspectMouseDown;
                win.Cursor = System.Windows.Input.Cursors.Arrow;
                SetHighlight(win, false);
            }
            return;
        }

        if (parts.Length < 3) return;
        if (parts[0] == "Window" && parts[1] == "DWM")
        {
            string[] p = parts[2].Split(',');
            int backdrop = int.Parse(p[0]), dark = int.Parse(p[1]);
            win.Resources["DWM_Backdrop"] = backdrop;
            win.Resources["DWM_Dark"] = dark;
            if (win.AllowsTransparency) return; // Do not apply DWM backdrop / colors that clobber transparency!

            DwmSetWindowAttribute(hwnd, 20, ref dark, 4);
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
            int borderColor = -2; // DWMWA_COLOR_NONE (0xFFFFFFFE)
            DwmSetWindowAttribute(hwnd, 34, ref borderColor, 4);

            // Re-apply shadow policy if glass frame thickness was set to prevent theme change override
            if (win.Resources.Contains("GlassFrameThicknessVal"))
            {
                double val = (double)win.Resources["GlassFrameThicknessVal"];
                int policy = (val == 0) ? 1 : 2;
                DwmSetWindowAttribute(hwnd, 2, ref policy, 4);

                MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                DwmExtendFrameIntoClientArea(hwnd, ref margins);
                SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0037);
            }
        }
        else if (parts[0] == "Window" && parts[1] == "ResizeMode")
        {
            try
            {
                if (parts[2].ToLower() == "noresize" || parts[2] == "0")
                {
                    win.ResizeMode = System.Windows.ResizeMode.NoResize;
                    var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                    if (chrome != null)
                    {
                        chrome.ResizeBorderThickness = new Thickness(0);
                    }
                }
                else
                {
                    win.ResizeMode = System.Windows.ResizeMode.CanResize;
                    var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                    if (chrome != null)
                    {
                        double val = 0;
                        if (win.Resources.Contains("GlassFrameThicknessVal"))
                        {
                            val = (double)win.Resources["GlassFrameThicknessVal"];
                        }
                        if (val == 0)
                        {
                            chrome.ResizeBorderThickness = win.AllowsTransparency ? new Thickness(0) : new Thickness(6);
                        }
                        else
                        {
                            chrome.ResizeBorderThickness = new Thickness(0);
                        }
                    }
                }
            }
            catch { }
        }
        else if (parts[0] == "Window" && parts[1] == "NativeOwner")
        {
            try
            {
                IntPtr ownerHwnd = new IntPtr(long.Parse(parts[2]));
                if (ownerHwnd != IntPtr.Zero)
                {
                    win.Resources["OriginalNativeOwner"] = ownerHwnd;
                }
                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    SetWindowLong(hwndVal, -8, ownerHwnd);
                }
                InheritWindowIconAndTitle(win, parts[2]);
            }
            catch { }
        }
        else if (parts[0] == "Window" && parts[1] == "GlassFrameThickness")
        {
            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
            if (chrome != null)
            {
                double val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                win.Resources["GlassFrameThicknessVal"] = val;
                chrome.GlassFrameThickness = new Thickness(val);
                if (val == 0)
                {
                    chrome.ResizeBorderThickness = win.AllowsTransparency ? new Thickness(0) : new Thickness(6);
                }
                else
                {
                    chrome.ResizeBorderThickness = new Thickness(0);
                }
                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    if (!win.AllowsTransparency)
                    {
                        int policy = (val == 0) ? 1 : 2; // 1 = DWMNCRP_DISABLED (No Shadow), 2 = DWMNCRP_ENABLED (Shadow)
                        DwmSetWindowAttribute(hwndVal, 2, ref policy, 4); // DWMWA_NCRENDERING_POLICY = 2

                        MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                        DwmExtendFrameIntoClientArea(hwndVal, ref margins);

                        SetWindowPos(hwndVal, IntPtr.Zero, 0, 0, 0, 0, 0x0037); // SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER

                        if (win.Resources.Contains("DWM_Backdrop") && win.Resources.Contains("DWM_Dark"))
                        {
                            int backdrop = (int)win.Resources["DWM_Backdrop"];
                            int dark = (int)win.Resources["DWM_Dark"];
                            DwmSetWindowAttribute(hwndVal, 20, ref dark, 4);
                            DwmSetWindowAttribute(hwndVal, 38, ref backdrop, 4);
                            int borderColor = -2; // DWMWA_COLOR_NONE
                            DwmSetWindowAttribute(hwndVal, 34, ref borderColor, 4);
                        }
                    }
                    UpdateSnapState(win);
                }
            }
        }
        else if (parts[0] == "Window" && parts[1] == "ApplyVisibilityStyles")
        {
            try
            {
                string[] sub = parts[2].Split(',');
                bool showInAltTab = sub[0] == "1";
                bool showInTaskbar = sub[1] == "1";

                IntPtr hwndVal = new WindowInteropHelper(win).Handle;
                if (hwndVal != IntPtr.Zero)
                {
                    bool wasVisible = IsWindowVisible(hwndVal);
                    if (wasVisible)
                    {
                        ShowWindow(hwndVal, 0); // SW_HIDE = 0
                    }

                    IntPtr originalOwner = IntPtr.Zero;
                    if (win.Resources.Contains("OriginalNativeOwner"))
                    {
                        originalOwner = (IntPtr)win.Resources["OriginalNativeOwner"];
                    }

                    if (showInAltTab)
                    {
                        SetWindowLong(hwndVal, -8, IntPtr.Zero);
                    }
                    else
                    {
                        SetWindowLong(hwndVal, -8, originalOwner);
                    }

                    int exStyle = GetWindowLong(hwndVal, -20); // GWL_EXSTYLE = -20
                    if (showInAltTab && showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle |= 0x40000; // Add WS_EX_APPWINDOW
                    }
                    else if (showInAltTab && !showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                    }
                    else if (!showInAltTab && showInTaskbar)
                    {
                        exStyle &= ~0x80; // Remove WS_EX_TOOLWINDOW
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                    }
                    else
                    { // !showInAltTab && !showInTaskbar
                        exStyle &= ~0x40000; // Remove WS_EX_APPWINDOW
                        exStyle |= 0x80; // Add WS_EX_TOOLWINDOW
                    }

                    SetWindowLong(hwndVal, -20, new IntPtr(exStyle));

                    SetTaskbarPresence(hwndVal, showInTaskbar);

                    SetWindowPos(hwndVal, IntPtr.Zero, 0, 0, 0, 0, 0x0037); // SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER

                    if (wasVisible)
                    {
                        ShowWindow(hwndVal, 8); // SW_SHOWNA = 8
                    }

                    // Re-apply DWM attributes after recreate
                    if (!win.AllowsTransparency && win.Resources.Contains("DWM_Backdrop") && win.Resources.Contains("DWM_Dark"))
                    {
                        int backdrop = (int)win.Resources["DWM_Backdrop"];
                        int dark = (int)win.Resources["DWM_Dark"];
                        DwmSetWindowAttribute(hwndVal, 20, ref dark, 4);
                        DwmSetWindowAttribute(hwndVal, 38, ref backdrop, 4);
                        int borderColor = -2; // DWMWA_COLOR_NONE
                        DwmSetWindowAttribute(hwndVal, 34, ref borderColor, 4);
                    }

                    if (!win.AllowsTransparency && win.Resources.Contains("GlassFrameThicknessVal"))
                    {
                        double val = (double)win.Resources["GlassFrameThicknessVal"];
                        int policy = (val == 0) ? 1 : 2;
                        DwmSetWindowAttribute(hwndVal, 2, ref policy, 4);
                        MARGINS margins = (val == 0) ? new MARGINS(0, 0, 0, 0) : new MARGINS(-1, -1, -1, -1);
                        DwmExtendFrameIntoClientArea(hwndVal, ref margins);
                    }

                    UpdateSnapState(win);
                }
            }
            catch { }
        }
        else if (parts[0] == "Window" && parts[1] == "ApplyFonts")
        {
            // 主题字体运行时应用（改主题字体后立即生效，无需重开窗口）：
            //   Window|ApplyFonts|字体|字号增量|字重数值(100-900)|清晰度(1=标准 2=锐利 3=极锐利)
            // 字体/字重/清晰度按绝对值设置（窗口根，未显式设置的元素继承）；
            // 字号按「增量」逐元素平移（覆盖生成期硬编码字号）。
            try
            {
                string[] seg = parts[2].Split('|');
                string family = seg.Length > 0 ? seg[0] : "";
                double delta = 0;
                double dd;
                if (seg.Length > 1 && double.TryParse(seg[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out dd))
                    delta = dd;
                bool hasWeight = seg.Length > 2 && !string.IsNullOrEmpty(seg[2]);
                FontWeight weight = FontWeights.Normal;
                if (hasWeight)
                {
                    try { weight = (FontWeight)new FontWeightConverter().ConvertFromString(seg[2]); } catch { }
                }
                int clarity = 2;
                int cc;
                if (seg.Length > 3 && int.TryParse(seg[3], out cc))
                    clarity = cc;
                if (!string.IsNullOrEmpty(family))
                    win.SetValue(TextElement.FontFamilyProperty, new System.Windows.Media.FontFamily(family));
                if (hasWeight)
                    win.SetValue(TextElement.FontWeightProperty, weight);
                // 清晰度：1=标准(Ideal) 2=锐利(Display) 3=极锐利(Display+Aliased)
                if (clarity == 1)
                    win.SetValue(TextOptions.TextFormattingModeProperty, TextFormattingMode.Ideal);
                else
                    win.SetValue(TextOptions.TextFormattingModeProperty, TextFormattingMode.Display);
                if (clarity == 3)
                    win.SetValue(TextOptions.TextRenderingModeProperty, TextRenderingMode.Aliased);
                else
                    win.SetValue(TextOptions.TextRenderingModeProperty, TextRenderingMode.ClearType);
                if (delta != 0)
                {
                    WalkVisualTree(win, (System.Windows.DependencyObject node) =>
                    {
                        if (node is System.Windows.Controls.TextBlock
                            || node is System.Windows.Controls.TextBox
                            || node is System.Windows.Controls.Control)
                        {
                            try
                            {
                                object v = node.GetValue(TextElement.FontSizeProperty);
                                if (v is double && !double.IsNaN((double)v))
                                    node.SetValue(TextElement.FontSizeProperty, Math.Max(6, (double)v + delta));
                            }
                            catch { }
                        }
                    });
                }
            }
            catch { }
        }
        else if (parts[0] == "Resource")
        {
            string[] rParts = parts[2].Split(new[] { ':' }, 2);
            if (rParts.Length == 2 && (rParts[0] == "Brush" || rParts[0] == "Thickness" || rParts[0] == "CornerRadius" || rParts[0] == "Double"))
            {
                string type = rParts[0];
                string val = rParts[1];
                if (type == "Brush") win.Resources[parts[1]] = new System.Windows.Media.BrushConverter().ConvertFromString(val);
                else if (type == "Thickness") win.Resources[parts[1]] = new System.Windows.ThicknessConverter().ConvertFromString(val);
                else if (type == "CornerRadius")
                {
                    if (parts[1] == "WindowRadius")
                    {
                        win.Resources["BaseWindowRadius"] = new System.Windows.CornerRadiusConverter().ConvertFromString(val);
                        if (Application.Current != null && !win.Title.StartsWith("Developer Tools - ")) Application.Current.Resources["BaseWindowRadius"] = win.Resources["BaseWindowRadius"];
                        UpdateSnapState(win);
                    }
                    else
                    {
                        win.Resources[parts[1]] = new System.Windows.CornerRadiusConverter().ConvertFromString(val);
                        if (parts[1] == "PanelRadius")
                        {
                            var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(win);
                            if (chrome != null)
                            {
                                chrome.CornerRadius = (CornerRadius)win.Resources["PanelRadius"];
                            }
                            UpdateSnapState(win);
                        }
                    }
                }
                else if (type == "Double") win.Resources[parts[1]] = double.Parse(val, System.Globalization.CultureInfo.InvariantCulture);
            }
            else
            {
                try
                {
                    win.Resources[parts[1]] = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                }
                catch
                {
                    try
                    {
                        win.Resources[parts[1]] = new System.Windows.CornerRadiusConverter().ConvertFromString(parts[2]);
                    }
                    catch
                    {
                        try
                        {
                            win.Resources[parts[1]] = new System.Windows.ThicknessConverter().ConvertFromString(parts[2]);
                        }
                        catch
                        {
                            try
                            {
                                win.Resources[parts[1]] = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                            }
                            catch { }
                        }
                    }
                }
            }
            if (Application.Current != null && !win.Title.StartsWith("Developer Tools - ")
                && win.Resources.Contains(parts[1]))
            {
                object synced = win.Resources[parts[1]];
                if (!(synced is System.Windows.Style) && !(synced is FrameworkTemplate))
                    Application.Current.Resources[parts[1]] = synced;
            }
            // Force-apply ScrollBarWidth to all ScrollBar elements in the visual tree
            if (parts[1] == "ScrollBarWidth" && win.Resources[parts[1]] is double)
            {
                double sz = (double)win.Resources[parts[1]];
                WalkVisualTree(win, (obj) =>
                {
                    if (obj is ScrollBar)
                    {
                        ScrollBar sb = (ScrollBar)obj;
                        if (sb.Orientation == System.Windows.Controls.Orientation.Vertical) sb.Width = sz;
                        else sb.Height = sz;
                    }
                });
            }
        }
        else
        {
            // 不依赖控件查找：AHK 可用任意控件名（推荐画布 id / Window）收起临时拖线
            if (parts.Length >= 2 && parts[1] == "HideTempConnection")
            {
                CancelConnectionDrag(connectionDragCanvas, true);
                return;
            }
            // AHK 准备重开指令菜单：短暂抑制 Closed 清线
            if (parts.Length >= 2 && parts[1] == "SuppressTempClear")
            {
                suppressTempClearOnMenuClosed = (parts.Length < 3 || parts[2] != "0");
                return;
            }
            object ctrl = parts[0] == "Window" ? win : FindControlByPath(parts[0]);
            if (ctrl == null && parts[0] != "Window")
            {
                if (EnableLogging)
                {
                    try { System.IO.File.AppendAllText(GetLogPath("AhkWpfDebug.log"), "Control not found: " + parts[0] + "\n"); } catch { }
                }
            }
            if (ctrl != null)
            {
                if (parts[1] == "AddItem")
                {
                    _controlCache.Clear();
                    if (ctrl is ListBox)
                    {
                        ListBox lb = (ListBox)ctrl;
                        int prevIdx = lb.SelectedIndex;
                        lb.Items.Add(parts[2]);
                        if (prevIdx != -1)
                        {
                            lb.SelectedIndex = prevIdx;
                        }
                        else
                        {
                            lb.SelectedIndex = lb.Items.Count - 1;
                            lb.ScrollIntoView(lb.SelectedItem);
                        }
                    }
                    else if (ctrl is TreeView)
                    {
                        TreeViewItem newItem = new TreeViewItem { Header = parts[2] };
                        int openParen = parts[2].LastIndexOf('(');
                        int closeParen = parts[2].LastIndexOf(')');
                        if (openParen >= 0 && closeParen > openParen)
                        {
                            string itemName = parts[2].Substring(openParen + 1, closeParen - openParen - 1);
                            newItem.Name = itemName;
                            try { win.UnregisterName(itemName); } catch { }
                            try { win.RegisterName(itemName, newItem); } catch { }
                        }
                        ((TreeView)ctrl).Items.Add(newItem);
                    }
                    else if (ctrl is TreeViewItem)
                    {
                        TreeViewItem newItem = new TreeViewItem { Header = parts[2] };
                        int openParen = parts[2].LastIndexOf('(');
                        int closeParen = parts[2].LastIndexOf(')');
                        if (openParen >= 0 && closeParen > openParen)
                        {
                            string itemName = parts[2].Substring(openParen + 1, closeParen - openParen - 1);
                            newItem.Name = itemName;
                            try { win.UnregisterName(itemName); } catch { }
                            try { win.RegisterName(itemName, newItem); } catch { }
                        }
                        ((TreeViewItem)ctrl).Items.Add(newItem);
                    }
                    else if (ctrl is ItemsControl)
                    {
                        ((ItemsControl)ctrl).Items.Add(parts[2]);
                    }
                }
                else if (parts[1] == "AddXamlItem")
                {
                    _controlCache.Clear();
                    try
                    {
                        object element = XamlReader.Parse(parts[2]);

                        var visited = new System.Collections.Generic.HashSet<object>();
                        Action<object> registerNames = null;
                        registerNames = new Action<object>((object obj) =>
                        {
                            if (obj == null || !visited.Add(obj)) return;
                            var fe = obj as FrameworkElement;
                            if (fe != null)
                            {
                                if (!string.IsNullOrEmpty(fe.Name))
                                {
                                    try {
                                        var ns = NameScope.GetNameScope(win);
                                        try {
                                            System.IO.File.AppendAllText(
                                                GetLogPath("AhkWpfDebug.log"),
                                                string.Format("AddXamlItem RegisterName: fe.Name={0}, ns is null={1}\n", fe.Name, ns == null)
                                            );
                                        } catch { }
                                        if (ns != null) {
                                            try { ns.UnregisterName(fe.Name); } catch { }
                                            ns.RegisterName(fe.Name, fe);
                                        } else {
                                            try { win.UnregisterName(fe.Name); } catch { }
                                            win.RegisterName(fe.Name, fe);
                                        }
                                    } catch (Exception ex) {
                                        try {
                                            System.IO.File.AppendAllText(
                                                GetLogPath("AhkWpfDebug.log"),
                                                "RegisterName Error for " + fe.Name + ": " + ex.ToString() + "\n"
                                            );
                                        } catch { }
                                    }
                                }
                                else
                                {
                                    try {
                                        System.IO.File.AppendAllText(
                                            GetLogPath("AhkWpfDebug.log"),
                                            "RegisterName Warning: Element " + fe.GetType().Name + " has empty Name\n"
                                        );
                                    } catch { }
                                }
                            }
                            var dobj = obj as DependencyObject;
                            if (dobj != null)
                            {
                                foreach (object child in System.Windows.LogicalTreeHelper.GetChildren(dobj))
                                {
                                    registerNames(child);
                                }
                                var cc = dobj as System.Windows.Controls.ContentControl;
                                if (cc != null && cc.Content != null) registerNames(cc.Content);
                                var dec = dobj as System.Windows.Controls.Decorator;
                                if (dec != null && dec.Child != null) registerNames(dec.Child);
                                var panel = dobj as System.Windows.Controls.Panel;
                                if (panel != null)
                                {
                                    foreach (UIElement c in panel.Children) registerNames(c);
                                }
                                var ic = dobj as ItemsControl;
                                if (ic != null)
                                {
                                    foreach (object item in ic.Items) registerNames(item);
                                }
                            }
                        });
                        registerNames(element);

                        if (ctrl is ItemsControl)
                        {
                            ((ItemsControl)ctrl).Items.Add(element);
                        }
                        else if (ctrl is System.Windows.Controls.Panel)
                        {
                            ((System.Windows.Controls.Panel)ctrl).Children.Add((UIElement)element);
                        }
                        else if (ctrl is System.Windows.Controls.Border)
                        {
                            ((System.Windows.Controls.Border)ctrl).Child = (UIElement)element;
                        }
                        else if (ctrl is ContentControl)
                        {
                            ((ContentControl)ctrl).Content = element;
                        }
                    }
                    catch (Exception ex)
                    {
                        try
                        {
                            System.IO.File.AppendAllText(
                                GetLogPath("AhkWpfDebug.log"),
                                "XamlParse Error in AddXamlItem:\n" + ex.ToString() + "\n\n"
                            );
                        }
                        catch { }
                        Console.WriteLine("XamlParse Error: " + ex.Message);
                    }
                }
                else if (parts[1] == "InsertXamlItem" && ctrl is ItemsControl)
                {
                    // 在指定索引插入卡片 XAML（value = "<index>|<xaml>"），用于逻辑树增量增删
                    _controlCache.Clear();
                    try
                    {
                        string[] idxXaml = parts[2].Split(new[] { '|' }, 2);
                        int insertIdx;
                        if (idxXaml.Length == 2 && int.TryParse(idxXaml[0], out insertIdx))
                        {
                            object element = XamlReader.Parse(idxXaml[1]);
                            var visited = new System.Collections.Generic.HashSet<object>();
                            Action<object> regNames = null;
                            regNames = new Action<object>((object obj) =>
                            {
                                if (obj == null || !visited.Add(obj)) return;
                                var fe = obj as FrameworkElement;
                                if (fe != null && !string.IsNullOrEmpty(fe.Name))
                                {
                                    try
                                    {
                                        var ns = NameScope.GetNameScope(win);
                                        if (ns != null) { try { ns.UnregisterName(fe.Name); } catch { } ns.RegisterName(fe.Name, fe); }
                                        else { try { win.UnregisterName(fe.Name); } catch { } win.RegisterName(fe.Name, fe); }
                                    }
                                    catch { }
                                }
                                var dobj = obj as DependencyObject;
                                if (dobj != null)
                                {
                                    foreach (object child in System.Windows.LogicalTreeHelper.GetChildren(dobj)) regNames(child);
                                    var cc = dobj as System.Windows.Controls.ContentControl;
                                    if (cc != null && cc.Content != null) regNames(cc.Content);
                                    var dec = dobj as System.Windows.Controls.Decorator;
                                    if (dec != null && dec.Child != null) regNames(dec.Child);
                                    var panel = dobj as System.Windows.Controls.Panel;
                                    if (panel != null) { foreach (UIElement c in panel.Children) regNames(c); }
                                    var ic = dobj as ItemsControl;
                                    if (ic != null) { foreach (object item in ic.Items) regNames(item); }
                                }
                            });
                            regNames(element);
                            if (insertIdx < 0) insertIdx = 0;
                            if (insertIdx > ((ItemsControl)ctrl).Items.Count) insertIdx = ((ItemsControl)ctrl).Items.Count;
                            ((ItemsControl)ctrl).Items.Insert(insertIdx, element);
                        }
                    }
                    catch (Exception ex)
                    {
                        try { System.IO.File.AppendAllText(GetLogPath("AhkWpfDebug.log"), "XamlParse Error in InsertXamlItem:\n" + ex.ToString() + "\n\n"); } catch { }
                        Console.WriteLine("XamlParse Error: " + ex.Message);
                    }
                }
                else if (parts[1] == "SelectByTag" && ctrl is TreeView)
                {
                    string tagHash = parts[2];
                    Func<ItemsControl, TreeViewItem> findAndExpand = null;
                    findAndExpand = (parent) =>
                    {
                        foreach (object item in parent.Items)
                        {
                            TreeViewItem tvi = item as TreeViewItem;
                            if (tvi != null)
                            {
                                if (tvi.Tag != null && tvi.Tag.ToString() == tagHash)
                                {
                                    return tvi;
                                }
                                TreeViewItem found = findAndExpand(tvi);
                                if (found != null)
                                {
                                    tvi.IsExpanded = true;
                                    return found;
                                }
                            }
                        }
                        return null;
                    };

                    TreeViewItem result = findAndExpand((TreeView)ctrl);
                    if (result != null)
                    {
                        result.IsSelected = true;
                        result.BringIntoView();
                    }
                }
                else if (parts[1] == "SelectByTag" && ctrl is ListBox)
                {
                    // 逻辑树卡片：按 Tag 找到卡片并滚到可见（不设 SelectedItem，选中视觉由勾选标记承担）
                    string tagHash = parts[2];
                    foreach (object item in ((ListBox)ctrl).Items)
                    {
                        var lbi = item as ListBoxItem;
                        if (lbi != null && lbi.Tag != null && lbi.Tag.ToString() == tagHash)
                        {
                            ((ListBox)ctrl).ScrollIntoView(lbi);
                            break;
                        }
                    }
                }
                else if (parts[1] == "Document" && ctrl is RichTextBox)
                {
                    try
                    {
                        FlowDocument doc = (FlowDocument)XamlReader.Parse(parts[2]);
                        ((RichTextBox)ctrl).Document = doc;
                    }
                    catch (Exception ex)
                    {
                        if (EnableLogging)
                        {
                            try { System.IO.File.AppendAllText("xaml_parse_error.log", "Parse Error: " + ex.Message + "\n" + (ex.InnerException != null ? ex.InnerException.Message : "") + "\nString: " + parts[2] + "\n\n"); } catch { }
                        }
                    }
                }
                else if (parts[1] == "Background")
                {
                    if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Border)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Border)ctrl).SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Border)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Panel)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Panel)ctrl).SetResourceReference(System.Windows.Controls.Panel.BackgroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Panel)ctrl).Background = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "Foreground")
                {
                    if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is TextBlock)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((TextBlock)ctrl).SetResourceReference(TextBlock.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((TextBlock)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is TextElement)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((TextElement)ctrl).SetResourceReference(TextElement.ForegroundProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((TextElement)ctrl).Foreground = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "BorderBrush")
                {
                    if (ctrl is System.Windows.Controls.Border)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Border)ctrl).SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Border)ctrl).BorderBrush = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                    else if (ctrl is System.Windows.Controls.Control)
                    {
                        if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Controls.Control)ctrl).SetResourceReference(System.Windows.Controls.Control.BorderBrushProperty, parts[2].Substring(17, parts[2].Length - 18));
                        else ((System.Windows.Controls.Control)ctrl).BorderBrush = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                    }
                }
                else if (parts[1] == "Stroke" && ctrl is System.Windows.Shapes.Shape)
                {
                    if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Shapes.Shape)ctrl).SetResourceReference(System.Windows.Shapes.Shape.StrokeProperty, parts[2].Substring(17, parts[2].Length - 18));
                    else ((System.Windows.Shapes.Shape)ctrl).Stroke = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                }
                else if (parts[1] == "Fill" && ctrl is System.Windows.Shapes.Shape)
                {
                    if (parts[2].StartsWith("{DynamicResource ") && parts[2].EndsWith("}")) ((System.Windows.Shapes.Shape)ctrl).SetResourceReference(System.Windows.Shapes.Shape.FillProperty, parts[2].Substring(17, parts[2].Length - 18));
                    else ((System.Windows.Shapes.Shape)ctrl).Fill = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]) as System.Windows.Media.Brush;
                }
                else if (parts[1] == "StrokeThickness" && ctrl is System.Windows.Shapes.Shape)
                {
                    ((System.Windows.Shapes.Shape)ctrl).StrokeThickness = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                }
                else if (parts[1] == "RemoveItem" && ctrl is ItemsControl)
                {
                    _controlCache.Clear();
                    var itemsControl = (ItemsControl)ctrl;
                    object toRemove = null;
                    foreach (var item in itemsControl.Items)
                    {
                        bool match = item.ToString() == parts[2];
                        if (!match && item is System.Windows.Controls.ListBoxItem)
                        {
                            var lbi = (System.Windows.Controls.ListBoxItem)item;
                            match = (lbi.Content != null && lbi.Content.ToString() == parts[2]);
                        }
                        if (!match && item is FrameworkElement)
                        {
                            var fe = (FrameworkElement)item;
                            match = (fe.Tag != null && fe.Tag.ToString() == parts[2]);
                        }
                        if (match)
                        {
                            toRemove = item;
                            break;
                        }
                    }
                    if (toRemove != null)
                    {
                        if (toRemove is DependencyObject)
                        {
                            try { UnregisterNamesRecursive((DependencyObject)toRemove); } catch { }
                        }
                        try { itemsControl.Items.Remove(toRemove); } catch { }
                    }
                }
                else if (parts[1] == "ClearItems")
                {
                    _controlCache.Clear();
                    if (ctrl is ItemsControl)
                    {
                        var ic = (ItemsControl)ctrl;
                        var itemsList = new System.Collections.Generic.List<object>();
                        try
                        {
                            foreach (var item in ic.Items) itemsList.Add(item);
                        }
                        catch { }
                        foreach (var item in itemsList)
                        {
                            if (item is DependencyObject)
                            {
                                try { UnregisterNamesRecursive((DependencyObject)item); } catch { }
                            }
                        }
                        try { ic.Items.Clear(); } catch { }
                    }
                    else if (ctrl is System.Windows.Controls.Panel)
                    {
                        var panel = (System.Windows.Controls.Panel)ctrl;
                        var childrenList = new System.Collections.Generic.List<UIElement>();
                        try
                        {
                            foreach (UIElement child in panel.Children) childrenList.Add(child);
                        }
                        catch { }
                        foreach (var child in childrenList)
                        {
                            if (child is DependencyObject)
                            {
                                try { UnregisterNamesRecursive((DependencyObject)child); } catch { }
                            }
                        }
                        try { panel.Children.Clear(); } catch { }
                    }
                    else if (ctrl is System.Windows.Controls.Border)
                    {
                        var border = (System.Windows.Controls.Border)ctrl;
                        if (border.Child != null)
                        {
                            try { UnregisterNamesRecursive(border.Child); } catch { }
                        }
                        try { border.Child = null; } catch { }
                    }
                    else if (ctrl is ContentControl)
                    {
                        var cc = (ContentControl)ctrl;
                        if (cc.Content is DependencyObject)
                        {
                            try { UnregisterNamesRecursive((DependencyObject)cc.Content); } catch { }
                        }
                        try { cc.Content = null; } catch { }
                    }
                }
                else if (parts[1] == "Play" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Play();
                }
                else if (parts[1] == "Pause" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Pause();
                }
                else if (parts[1] == "Stop" && ctrl is MediaElement)
                {
                    ((MediaElement)ctrl).Stop();
                }
                else if (parts[1] == "Seek" && ctrl is MediaElement)
                {
                    double secs;
                    if (double.TryParse(parts[2], out secs))
                    {
                        ((MediaElement)ctrl).Position = TimeSpan.FromSeconds(secs);
                    }
                }
                else if (parts[1] == "NavigateToString" && ctrl is System.Windows.Controls.WebBrowser)
                {
                    try
                    {
                        byte[] htmlBytes = Convert.FromBase64String(parts[2]);
                        string html = Encoding.UTF8.GetString(htmlBytes);
                        ((System.Windows.Controls.WebBrowser)ctrl).NavigateToString(html);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("NavigateToString error: " + ex.Message);
                    }
                }
                else if (parts[1] == "BindEvent")
                {
                    BindEvent(parts[0], parts[2]);
                }
                // Epic5 虚拟列表命令（只加不改既有契约；ListBox 守卫，实现见文件尾 VirtualListHost 类）
                else if (parts[1].StartsWith("VL_") && ctrl is ListBox)
                {
                    VirtualListHost.Dispatch(win, winId, (ListBox)ctrl, parts[1], parts[2], t => SendToAhk(t));
                }
                // 取色器（Picker）：预览渲染在 daemon 进程内本地驱动，零 IPC（确认时 AHK 本地读坐标+颜色）
                // parts[2] = "GridN|CellSize"（DIP），缺省 9|12
                else if (parts[1] == "PickerStart" && ctrl is Window)
                {
                    StartPicker(winId, (Window)ctrl, parts.Length >= 3 ? parts[2] : "");
                }
                else if (parts[1] == "PickerStop" && ctrl is Window)
                {
                    StopPicker(winId);
                }
#if ENABLE_WEBVIEW
                else if (parts[1] == "Navigate" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.Navigate(parts[2]);
                    } catch { }
                } else if (parts[1] == "ExecuteScript" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.ExecuteScriptAsync(Encoding.UTF8.GetString(Convert.FromBase64String(parts[2])));
                    } catch { }
                } else if (parts[1] == "PostWebMessage" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try {
                        ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.PostWebMessageAsString(parts[2]);
                    } catch { }
                } else if (parts[1] == "GoBack" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).GoBack(); } catch { }
                } else if (parts[1] == "GoForward" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).GoForward(); } catch { }
                } else if (parts[1] == "Refresh" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).Reload(); } catch { }
                } else if (parts[1] == "OpenDevTools" && ctrl is Microsoft.Web.WebView2.Wpf.WebView2) {
                    try { ((Microsoft.Web.WebView2.Wpf.WebView2)ctrl).CoreWebView2.OpenDevToolsWindow(); } catch { }
                }
#endif
#if ENABLE_AVALONEDIT
                else if (ctrl is ContentControl && parts[1].StartsWith("AE_")) {
                    // AvalonEdit commands — the ContentControl hosts the TextEditor
                    var host = ctrl as ContentControl;
                    var editor = host != null ? host.Content as TextEditor : null;
                    if (editor == null) {
                        // First-time init: create AvalonEdit inside the ContentControl
                        if (parts[1] == "AE_Init") {
                            editor = new TextEditor();
                            editor.FontFamily = new System.Windows.Media.FontFamily("Consolas");
                            editor.FontSize = 14;
                            editor.ShowLineNumbers = true;
                            editor.WordWrap = false;
                            editor.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
                            editor.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
                            editor.Options.EnableHyperlinks = false;
                            editor.Options.EnableEmailHyperlinks = false;
                            editor.Options.ShowEndOfLine = false;
                            editor.Options.ShowSpaces = false;
                            editor.Options.ShowTabs = false;
                            editor.Options.HighlightCurrentLine = true;
                            editor.Options.AllowScrollBelowDocument = true;
                            editor.Options.ConvertTabsToSpaces = true;
                            editor.Options.IndentationSize = 4;
                            // Install search panel
                            SearchPanel.Install(editor);
                            // Wire events
                            string eName = ((FrameworkElement)host).Name;
                            editor.TextChanged += (s, e2) => {
                                SendToAhk("EVENT|" + winId + "|" + eName + "|TextChanged|" + BridgeUtil.LengthPrefix(editor.Document.LineCount.ToString()) + "\n");
                            };
                            editor.TextArea.Caret.PositionChanged += (s, e2) => {
                                int line = editor.TextArea.Caret.Line;
                                int col = editor.TextArea.Caret.Column;
                                int offset = editor.TextArea.Caret.Offset;
                                SendToAhk("EVENT|" + winId + "|" + eName + "|CaretChanged|" + BridgeUtil.LengthPrefix(line + "," + col + "," + offset) + "\n");
                            };
                            ((ContentControl)host).Content = editor;
                            // Apply initial theme from parts[2] if provided
                            if (parts.Length > 2 && !string.IsNullOrEmpty(parts[2])) {
                                ApplyAvalonEditTheme(editor, parts[2]);
                            }
                        }
                    }
                    if (editor != null) {
                        string aeCmd = parts[1].Substring(3); // strip "AE_"
                        string aeVal = parts.Length > 2 ? parts[2] : "";
                        switch (aeCmd) {
                            case "Init": break; // Already handled above
                            case "SetText":
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.Document.Text = decoded;
                                } catch {
                                    editor.Document.Text = aeVal;
                                }
                                break;
                            case "GetText": {
                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(editor.Document.Text));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)host).Name + "|TextContent|" + BridgeUtil.LengthPrefix(b64) + "\n");
                                break;
                            }
                            case "AppendText":
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.AppendText(decoded);
                                } catch {
                                    editor.AppendText(aeVal);
                                }
                                break;
                            case "SetLanguage":
                                try {
                                    var hlDef = HighlightingManager.Instance.GetDefinition(aeVal);
                                    if (hlDef == null) {
                                        // Try common aliases
                                        switch (aeVal.ToLower()) {
                                            case "ahk": case "autohotkey": hlDef = HighlightingManager.Instance.GetDefinition("Python"); break; // Closest built-in
                                            case "cs": case "csharp": hlDef = HighlightingManager.Instance.GetDefinition("C#"); break;
                                            case "js": case "javascript": hlDef = HighlightingManager.Instance.GetDefinition("JavaScript"); break;
                                            case "py": case "python": hlDef = HighlightingManager.Instance.GetDefinition("Python"); break;
                                            case "xml": case "xaml": hlDef = HighlightingManager.Instance.GetDefinition("XML"); break;
                                            case "html": hlDef = HighlightingManager.Instance.GetDefinition("HTML"); break;
                                            case "css": hlDef = HighlightingManager.Instance.GetDefinition("CSS"); break;
                                            case "json": hlDef = HighlightingManager.Instance.GetDefinition("JavaScript"); break;
                                            case "sql": hlDef = HighlightingManager.Instance.GetDefinition("TSQL"); break;
                                            case "md": case "markdown": hlDef = HighlightingManager.Instance.GetDefinition("MarkDown"); break;
                                            case "cpp": case "c++": case "c": hlDef = HighlightingManager.Instance.GetDefinition("C++"); break;
                                            case "java": hlDef = HighlightingManager.Instance.GetDefinition("Java"); break;
                                            case "ps": case "powershell": hlDef = HighlightingManager.Instance.GetDefinition("PowerShell"); break;
                                            case "bat": case "batch": case "cmd": hlDef = HighlightingManager.Instance.GetDefinition("BAT"); break;
                                            case "vb": case "vbnet": hlDef = HighlightingManager.Instance.GetDefinition("VB"); break;
                                            case "php": hlDef = HighlightingManager.Instance.GetDefinition("PHP"); break;
                                        }
                                    }
                                    editor.SyntaxHighlighting = hlDef;
                                } catch { }
                                break;
                            case "SetTheme":
                                ApplyAvalonEditTheme(editor, aeVal);
                                break;
                            case "ShowLineNumbers":
                                editor.ShowLineNumbers = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "WordWrap":
                                editor.WordWrap = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ReadOnly":
                                editor.IsReadOnly = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "FontSize":
                                double fs; if (double.TryParse(aeVal, out fs)) editor.FontSize = fs;
                                break;
                            case "FontFamily":
                                editor.FontFamily = new System.Windows.Media.FontFamily(aeVal);
                                break;
                            case "TabSize":
                                int ts; if (int.TryParse(aeVal, out ts)) editor.Options.IndentationSize = ts;
                                break;
                            case "GotoLine": {
                                int ln; if (int.TryParse(aeVal, out ln) && ln > 0 && ln <= editor.Document.LineCount) {
                                    editor.ScrollToLine(ln);
                                    editor.TextArea.Caret.Line = ln;
                                    editor.TextArea.Caret.Column = 1;
                                }
                                break;
                            }
                            case "GotoOffset": {
                                int off; if (int.TryParse(aeVal, out off)) {
                                    if (off >= 0 && off <= editor.Document.TextLength) {
                                        editor.CaretOffset = off;
                                        editor.ScrollTo(editor.TextArea.Caret.Line, editor.TextArea.Caret.Column);
                                    }
                                }
                                break;
                            }
                            case "Select": {
                                string[] sel = aeVal.Split(',');
                                if (sel.Length >= 2) {
                                    int start, len;
                                    if (int.TryParse(sel[0], out start) && int.TryParse(sel[1], out len)) {
                                        if (start >= 0 && start + len <= editor.Document.TextLength) {
                                            editor.Select(start, len);
                                            editor.ScrollTo(editor.TextArea.Caret.Line, editor.TextArea.Caret.Column);
                                        }
                                    }
                                }
                                break;
                            }
                            case "InsertText": {
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    editor.Document.Insert(editor.CaretOffset, decoded);
                                } catch {
                                    editor.Document.Insert(editor.CaretOffset, aeVal);
                                }
                                break;
                            }
                            case "Find": {
                                // Open built-in search panel with query
                                var sp = SearchPanel.Install(editor);
                                // The SearchPanel doesn't expose a programmatic "search for" method easily,
                                // so we use reflection or just open it
                                sp.Open();
                                if (!string.IsNullOrEmpty(aeVal)) {
                                    // Set search text via reflection
                                    try {
                                        var searchProp = sp.GetType().GetProperty("SearchPattern");
                                        if (searchProp != null) searchProp.SetValue(sp, aeVal);
                                    } catch { }
                                }
                                break;
                            }
                            case "ReplaceAll": {
                                string[] rp = aeVal.Split(new[] { "|||" }, StringSplitOptions.None);
                                if (rp.Length >= 2) {
                                    string findText = rp[0], replText = rp[1];
                                    editor.Document.Text = editor.Document.Text.Replace(findText, replText);
                                }
                                break;
                            }
                            case "HighlightLine": {
                                // Set current line highlight — AvalonEdit does this natively
                                // but we can also add a custom background marker
                                int hlLine;
                                if (int.TryParse(aeVal, out hlLine) && hlLine > 0 && hlLine <= editor.Document.LineCount) {
                                    editor.ScrollToLine(hlLine);
                                    var docLine = editor.Document.GetLineByNumber(hlLine);
                                    editor.Select(docLine.Offset, docLine.Length);
                                }
                                break;
                            }
                            case "FoldAll":
                                if (editor.Tag is FoldingManager) {
                                    var fm = (FoldingManager)editor.Tag;
                                    foreach (var fold in fm.AllFoldings) fold.IsFolded = true;
                                }
                                break;
                            case "UnfoldAll":
                                if (editor.Tag is FoldingManager) {
                                    var fm = (FoldingManager)editor.Tag;
                                    foreach (var fold in fm.AllFoldings) fold.IsFolded = false;
                                }
                                break;
                            case "SetFolding": {
                                // Initialize or update folding based on brace-matching
                                FoldingManager foldMgr = editor.Tag as FoldingManager;
                                if (foldMgr == null) {
                                    foldMgr = FoldingManager.Install(editor.TextArea);
                                    editor.Tag = foldMgr;
                                    
                                    // Replace standard boxy FoldingMargin with SexyFoldingMargin
                                    for (int i = 0; i < editor.TextArea.LeftMargins.Count; i++) {
                                        var margin = editor.TextArea.LeftMargins[i];
                                        if (margin.GetType().Name == "FoldingMargin") {
                                            editor.TextArea.LeftMargins[i] = new SexyFoldingMargin() { FoldingManager = foldMgr };
                                            break;
                                        }
                                    }
                                }
                                var strategy = new BraceFoldingStrategy();
                                strategy.UpdateFoldings(foldMgr, editor.Document);
                                
                                // Re-apply theme styling to the folding margin if current theme is stored
                                if (editor.Resources.Contains("CurrentTheme")) {
                                    ApplyAvalonEditTheme(editor, (string)editor.Resources["CurrentTheme"]);
                                }
                                break;
                            }
                            case "ShowCompletion": {
                                // Show a WPF-styled autocomplete popup with the provided items
                                try {
                                    string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(aeVal));
                                    string[] items = decoded.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                                    var completionWindow = new CompletionWindow(editor.TextArea);
                                    
                                    // Custom visual styling matching the host/editor theme
                                    try {
                                        completionWindow.Background = editor.Background;
                                        completionWindow.BorderBrush = editor.LineNumbersForeground ?? System.Windows.Media.Brushes.Gray;
                                        completionWindow.BorderThickness = new System.Windows.Thickness(1);
                                        completionWindow.Foreground = editor.Foreground;
                                        completionWindow.FontFamily = editor.FontFamily;
                                        completionWindow.FontSize = editor.FontSize;
                                        completionWindow.MinWidth = 240;
                                        completionWindow.WindowStyle = System.Windows.WindowStyle.None;
                                        completionWindow.ResizeMode = System.Windows.ResizeMode.NoResize;
                                        
                                        var listBox = completionWindow.CompletionList.ListBox;
                                        if (listBox != null) {
                                            listBox.Background = System.Windows.Media.Brushes.Transparent;
                                            listBox.BorderThickness = new System.Windows.Thickness(0);
                                            listBox.Foreground = editor.Foreground;
                                            listBox.FontFamily = editor.FontFamily;
                                            listBox.FontSize = editor.FontSize;
                                            listBox.Padding = new System.Windows.Thickness(4);
                                            
                                            // Styled ListBoxItem container for hover/selection visual parity
                                            var itemStyle = new System.Windows.Style(typeof(System.Windows.Controls.ListBoxItem));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, System.Windows.Media.Brushes.Transparent));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.ForegroundProperty, editor.Foreground));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.PaddingProperty, new System.Windows.Thickness(10, 5, 10, 5)));
                                            itemStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.MarginProperty, new System.Windows.Thickness(0, 1, 0, 1)));
                                            
                                            // Selection Highlight
                                            var triggerSelected = new System.Windows.Trigger { Property = System.Windows.Controls.ListBoxItem.IsSelectedProperty, Value = true };
                                            triggerSelected.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, editor.TextArea.SelectionBrush ?? System.Windows.Media.Brushes.DodgerBlue));
                                            triggerSelected.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.ForegroundProperty, editor.Foreground));
                                            
                                            // Hover Highlight
                                            var triggerHover = new System.Windows.Trigger { Property = System.Windows.Controls.ListBoxItem.IsMouseOverProperty, Value = true };
                                            System.Windows.Media.Brush hoverBrush = null;
                                            var selBrush = editor.TextArea.SelectionBrush as System.Windows.Media.SolidColorBrush;
                                            if (selBrush != null) {
                                                hoverBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(40, selBrush.Color.R, selBrush.Color.G, selBrush.Color.B));
                                            } else {
                                                hoverBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(20, 128, 128, 128));
                                            }
                                            triggerHover.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.BackgroundProperty, hoverBrush));
                                            
                                            itemStyle.Triggers.Add(triggerSelected);
                                            itemStyle.Triggers.Add(triggerHover);
                                            listBox.ItemContainerStyle = itemStyle;
                                        }
                                    } catch { }
                                    
                                    foreach (string item in items) {
                                        string[] itemParts = item.Split(new[] { '|' }, 2);
                                        string completionText = itemParts[0].Trim();
                                        string desc = itemParts.Length > 1 ? itemParts[1].Trim() : "";
                                        completionWindow.CompletionList.CompletionData.Add(
                                            new AhkCompletionData(completionText, desc));
                                    }
                                    completionWindow.Show();
                                    completionWindow.Closed += (s2, e2) => {
                                        // Notify AHK which item was selected
                                        SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)host).Name + "|CompletionClosed|\n");
                                    };
                                } catch { }
                                break;
                            }
                            case "AddMarker": {
                                // Format: line,type (error|warning|info|breakpoint)
                                // TODO: Add colored marker support with custom margin rendering
                                break;
                            }
                            case "ClearMarkers":
                                break;
                            case "HighlightCurrentLine":
                                editor.Options.HighlightCurrentLine = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowSpaces":
                                editor.Options.ShowSpaces = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowTabs":
                                editor.Options.ShowTabs = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                            case "ShowEndOfLine":
                                editor.Options.ShowEndOfLine = aeVal != "0" && aeVal.ToLower() != "false";
                                break;
                        }
                    }
                }
#endif
#if ENABLE_DOCUMENT
                else if (parts[1].StartsWith("Doc_") && ctrl is RichTextBox) {
                    var rtb = (RichTextBox)ctrl;
                    if (rtb.Tag == null || rtb.Tag.ToString() != "wired") {
                        rtb.SelectionChanged += (s, e) => {
                            var r = rtb.Selection;
                            var fw = r.GetPropertyValue(TextElement.FontWeightProperty);
                            var fs = r.GetPropertyValue(TextElement.FontStyleProperty);
                            var td = r.GetPropertyValue(Inline.TextDecorationsProperty);
                            var sz = r.GetPropertyValue(TextElement.FontSizeProperty);
                            var ff = r.GetPropertyValue(TextElement.FontFamilyProperty);
                            
                            string b = (fw != DependencyProperty.UnsetValue && (FontWeight)fw >= FontWeights.SemiBold) ? "1" : "0";
                            string i = (fs != DependencyProperty.UnsetValue && (FontStyle)fs == FontStyles.Italic) ? "1" : "0";
                            string u = (td != DependencyProperty.UnsetValue && td == TextDecorations.Underline) ? "1" : "0";
                            string st = (td != DependencyProperty.UnsetValue && td == TextDecorations.Strikethrough) ? "1" : "0";
                            double sizeVal = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                            string size = sizeVal.ToString();
                            string font = "Segoe UI";
                            bool fontIsInstalled = true;
                            if (ff != DependencyProperty.UnsetValue) {
                                string rawFont = ff.ToString();
                                // Determine if the selected text contains CJK characters
                                bool selectionHasCJK = false;
                                try {
                                    string selText = r.Text;
                                    if (!string.IsNullOrEmpty(selText)) {
                                        foreach (char ch in selText) {
                                            if (ch > 127) { selectionHasCJK = true; break; }
                                        }
                                    }
                                    if (!selectionHasCJK) {
                                        // No text selected or no CJK in selection — check the Run at caret
                                        var caretPos = r.Start;
                                        if (caretPos != null) {
                                            // Walk the parent chain to find the enclosing Run
                                            DependencyObject parent = caretPos.Parent;
                                            while (parent != null && !(parent is System.Windows.Documents.Run)) {
                                                parent = LogicalTreeHelper.GetParent(parent);
                                            }
                                            if (parent is System.Windows.Documents.Run) {
                                                string runText = ((System.Windows.Documents.Run)parent).Text;
                                                if (!string.IsNullOrEmpty(runText)) {
                                                    foreach (char ch in runText) {
                                                        if (ch > 127) { selectionHasCJK = true; break; }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } catch { }

                                // Parse the comma-separated font chain
                                var fontParts = rawFont.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
                                string primaryFont = "";
                                if (selectionHasCJK && fontParts.Length > 0) {
                                    // For CJK text, find the first CJK-capable font in the chain
                                    string cjkFont = null;
                                    foreach (var fp in fontParts) {
                                        string candidate = fp.Trim();
                                        int hashIdx = candidate.IndexOf('#');
                                        if (hashIdx >= 0) candidate = candidate.Substring(hashIdx + 1);
                                        // Check if this looks like a CJK font
                                        bool isCJK = false;
                                        foreach (char ch in candidate) {
                                            if (ch > 127) { isCJK = true; break; }
                                        }
                                        if (!isCJK) {
                                            string lower = candidate.ToLower();
                                            if (lower.Contains("sim") || lower.Contains("song") || lower.Contains("hei") || 
                                                lower.Contains("kai") || lower.Contains("ming") || lower.Contains("yahei") ||
                                                lower.Contains("gothic") || lower.Contains("malgun") || lower.Contains("meiryo") ||
                                                lower.Contains("dotum") || lower.Contains("batang") || lower.Contains("gulim") ||
                                                lower.Contains("fang")) {
                                                isCJK = true;
                                            }
                                        }
                                        if (isCJK) { cjkFont = candidate; break; }
                                    }
                                    primaryFont = cjkFont ?? fontParts[0].Trim();
                                } else if (fontParts.Length > 0) {
                                    primaryFont = fontParts[0].Trim();
                                }
                                // If per-user font path, extract the actual font name after '#'
                                int hashIdx2 = primaryFont.IndexOf('#');
                                if (hashIdx2 >= 0) {
                                    primaryFont = primaryFont.Substring(hashIdx2 + 1);
                                }
                                // Check if primary font is actually installed via WPF or alias
                                fontIsInstalled = IsFontInstalledWithAlias(primaryFont, GetInstalledFonts());
                                // Prefix with ! if not installed so AHK can show the fallback indicator
                                font = fontIsInstalled ? primaryFont : ("!" + primaryFont);
                            }
                            
                            string style = "Body";
                            if (sz != DependencyProperty.UnsetValue) {
                                double dSz = (double)sz;
                                FontWeight w = (fw != DependencyProperty.UnsetValue) ? (FontWeight)fw : FontWeights.Normal;
                                if (dSz >= 24 && w >= FontWeights.Bold) style = "H1";
                                else if (dSz >= 20 && w >= FontWeights.SemiBold) style = "H2";
                                else if (dSz >= 16 && w >= FontWeights.SemiBold) style = "H3";
                                else if (dSz >= 14 && w >= FontWeights.SemiBold) style = "H4";
                                else if (dSz >= 12 && w >= FontWeights.SemiBold) style = "H5";
                                else if (dSz >= 11 && w >= FontWeights.SemiBold) style = "H6";
                            }
                            
                            string fmt = string.Format("B:{0},I:{1},U:{2},S:{3},Size:{4},Style:{5},Font:{6}", b, i, u, st, size, style, font);
                            SendToAhk(string.Format("EVENT|{0}|{1}|SelectionFormat|{2}\n", winId, ((FrameworkElement)ctrl).Name, BridgeUtil.LengthPrefix(fmt)));
                        };

                        // Debouncer for page break spacer updates
                        var spacerTimer = new System.Windows.Threading.DispatcherTimer();
                        spacerTimer.Interval = TimeSpan.FromMilliseconds(1500);
                        spacerTimer.Tick += (s2, e2) => {
                            spacerTimer.Stop();
                            string currentMode = "paper";
                            if (_docViewModes.ContainsKey(rtb.Name)) {
                                currentMode = _docViewModes[rtb.Name];
                            }
                            if (currentMode != "paper") return;

                            var pageB = win.FindName(rtb.Name + "_PageBorder") as System.Windows.Controls.Border;
                            if (pageB != null) {
                                var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                _InsertPageBreakSpacers(rtb, thm);
                            }
                        };

                        rtb.TextChanged += (s, e) => {
                            if (!_isUpdatingSpacers) {
                                spacerTimer.Stop();
                                spacerTimer.Start();
                            }
                        };

                        // Setup click listener on outer ScrollViewer to focus RTB
                        Action wireScrollViewer = () => {
                            FrameworkElement walkUp = rtb.Parent as FrameworkElement;
                            ScrollViewer editorSv = null;
                            while (walkUp != null) {
                                if (walkUp is ScrollViewer) { editorSv = (ScrollViewer)walkUp; break; }
                                walkUp = System.Windows.Media.VisualTreeHelper.GetParent(walkUp) as FrameworkElement;
                            }
                            if (editorSv != null && editorSv.Tag == null) {
                                editorSv.MouseLeftButtonDown += (s2, e2) => {
                                    if (e2.OriginalSource == editorSv || e2.OriginalSource is Grid || e2.OriginalSource is System.Windows.Controls.Border) {
                                        rtb.Focus();
                                        System.Windows.Input.Keyboard.Focus(rtb);
                                    }
                                };
                                editorSv.Tag = "wired";
                            }
                        };

                        if (rtb.IsLoaded) {
                            wireScrollViewer();
                        } else {
                            rtb.Loaded += (s, e) => wireScrollViewer();
                        }

                        rtb.Tag = "wired";
                    }
                    string docCmd = parts[1].Substring(4);
                    string docVal = parts.Length > 2 ? parts[2] : "";
                    switch (docCmd) {
                        case "Import": {
                            try {
                                string filePath = docVal;
                                if (System.IO.File.Exists(filePath)) {
                                    string ext = System.IO.Path.GetExtension(filePath).ToLower();
                                    FlowDocument doc = new FlowDocument();
                                    if (ext == ".docx") {
                                        doc = DocxToFlowDocument(filePath);
                                    } else if (ext == ".doc") {
                                        doc = DocToFlowDocument(filePath);
                                    } else if (ext == ".rtf") {
                                        var range = new TextRange(doc.ContentStart, doc.ContentEnd);
                                        using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Open)) {
                                            range.Load(fs, DataFormats.Rtf);
                                        }
                                    } else if (ext == ".txt") {
                                        doc.Blocks.Add(new System.Windows.Documents.Paragraph(
                                            new System.Windows.Documents.Run(System.IO.File.ReadAllText(filePath))));
                                    }
                                    if (doc.Tag == null) {
                                        doc.Tag = new DocLayoutSettings {
                                            PageWidth = 816,
                                            PageHeight = 1056,
                                            PagePadding = new Thickness(96, 72, 96, 72)
                                        };
                                    }
                                    rtb.Document = doc;
                                    
                                    string configLang = "en-US";
                                    if (_spellCheckLangs.ContainsKey(rtb.Name)) {
                                        configLang = _spellCheckLangs[rtb.Name];
                                    }
                                    
                                    string langToApply = configLang;
                                    if (configLang == "auto") {
                                        langToApply = DetectLanguage(rtb);
                                    }
                                    
                                    try {
                                        var xmlLang = System.Windows.Markup.XmlLanguage.GetLanguage(langToApply);
                                        rtb.Language = xmlLang;
                                        rtb.Document.Language = xmlLang;
                                        bool wasEnabled = rtb.SpellCheck.IsEnabled;
                                        rtb.SpellCheck.IsEnabled = false;
                                        rtb.SpellCheck.IsEnabled = wasEnabled;
                                    } catch { }

                                    string viewMode = "paper";
                                    if (_docViewModes.ContainsKey(rtb.Name)) {
                                        viewMode = _docViewModes[rtb.Name];
                                    } else {
                                        _docViewModes[rtb.Name] = viewMode;
                                    }
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    ApplyViewMode(rtb, viewMode, currentTheme, win);
                                    SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentLoaded|" + BridgeUtil.LengthPrefix(filePath) + "\n");
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "Export": {
                            try {
                                // Strip page break spacers before saving
                                bool hadSpacers = _pageBreakSpacers.Count > 0;
                                _RemovePageBreakSpacers(rtb);
                                
                                // Get the active document (might be in FlowDocumentReader if in Page/TwoUp view)
                                string rtbN = ((FrameworkElement)ctrl).Name;
                                var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                                FlowDocument exportDoc = rtb.Document;
                                if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                    exportDoc = pageReader.Document;
                                }
                                
                                string filePath = docVal;
                                string ext = System.IO.Path.GetExtension(filePath).ToLower();
                                if (ext == ".docx") {
                                    FlowDocumentToDocx(exportDoc, filePath);
                                } else if (ext == ".rtf") {
                                    var range = new TextRange(exportDoc.ContentStart, exportDoc.ContentEnd);
                                    using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Create)) {
                                        range.Save(fs, DataFormats.Rtf);
                                    }
                                } else {
                                    var range = new TextRange(exportDoc.ContentStart, exportDoc.ContentEnd);
                                    System.IO.File.WriteAllText(filePath, range.Text);
                                }
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentSaved|" + BridgeUtil.LengthPrefix(filePath) + "\n");
                                
                                // Re-insert spacers if we were in page view
                                if (hadSpacers) {
                                    var containerEl2 = win.FindName(((FrameworkElement)ctrl).Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl2 != null && containerEl2.Tag is string) ? (string)containerEl2.Tag : "Normal";
                                    _InsertPageBreakSpacers(rtb, thm);
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|DocumentError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "Format": {
                            ApplyDocFormat(rtb, docVal);
                            break;
                        }
                        case "FormatStyle": {
                            var r = rtb.Selection;
                            if (docVal == "H1") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 24.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Bold);
                            } else if (docVal == "H2") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 20.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H3") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 16.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H4") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H5") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 12.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else if (docVal == "H6") {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 11.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
                            } else {
                                r.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                r.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
                            }
                            break;
                        }
                        case "InsertTable": {
                            string[] dims = docVal.Split(',');
                            int rows = 3, cols = 3;
                            if (dims.Length >= 2) { int.TryParse(dims[0], out rows); int.TryParse(dims[1], out cols); }
                            var table = new System.Windows.Documents.Table();
                            table.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                            table.BorderThickness = new Thickness(1);
                            table.CellSpacing = 0;
                            table.Margin = new Thickness(0, 10, 0, 10);
                            for (int c = 0; c < cols; c++) {
                                table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                            }
                            var rg = new System.Windows.Documents.TableRowGroup();
                            for (int r = 0; r < rows; r++) {
                                var row = new System.Windows.Documents.TableRow();
                                for (int c = 0; c < cols; c++) {
                                    var cellPara = new System.Windows.Documents.Paragraph(new System.Windows.Documents.Run(r == 0 ? "Header" : ""));
                                    cellPara.Margin = new Thickness(0);
                                    if (r == 0) cellPara.TextAlignment = System.Windows.TextAlignment.Center;
                                    var cell = new System.Windows.Documents.TableCell(cellPara);
                                    cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                    cell.BorderThickness = new Thickness(0.5);
                                    cell.Padding = new Thickness(10, 8, 10, 8);
                                    if (r == 0) {
                                        cell.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(68, 114, 196));
                                        cell.Foreground = System.Windows.Media.Brushes.White;
                                        cellPara.FontWeight = FontWeights.Bold;
                                    }
                                    row.Cells.Add(cell);
                                }
                                rg.Rows.Add(row);
                            }
                            table.RowGroups.Add(rg);
                            
                            var currentPara = rtb.CaretPosition.Paragraph;
                            if (currentPara != null) {
                                rtb.Document.Blocks.InsertAfter(currentPara, table);
                            } else {
                                rtb.Document.Blocks.Add(table);
                            }
                            break;
                        }
                        case "GetOutline": {
                            string rtbN = ((FrameworkElement)ctrl).Name;
                            var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                            FlowDocument activeDoc = rtb.Document;
                            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                activeDoc = pageReader.Document;
                            }
                            //System.IO.File.WriteAllText(@"c:\projects\ahk\ahk-xaml\examples\clones\outline_debug.txt", "--- GET OUTLINE START ---\n");
                            System.Text.StringBuilder sb = new System.Text.StringBuilder();
                            int pIdx = 0;
                            System.Windows.Documents.TextPointer ptr = activeDoc.ContentStart;
                            while (ptr != null && ptr.CompareTo(rtb.Document.ContentEnd) < 0) {
                                if (ptr.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.ElementStart) {
                                    System.Windows.Documents.TextElement element = ptr.GetAdjacentElement(LogicalDirection.Forward) as System.Windows.Documents.TextElement;
                                    System.Windows.Documents.Paragraph p = element as System.Windows.Documents.Paragraph;
                                    if (p != null) {
                                        var range = new TextRange(p.ContentStart, p.ContentEnd);
                                        string headingText = range.Text.Trim();
                                        int nlIdx = headingText.IndexOf('\n');
                                        if (nlIdx > 0) headingText = headingText.Substring(0, nlIdx).Trim();
                                        
                                        if (!string.IsNullOrEmpty(headingText) && headingText.Length < 100) {
                                            bool isHeading = false;
                                            string level = "H2";
                                            
                                            double effSize = p.FontSize;
                                            FontWeight effWeight = p.FontWeight;
                                            
                                            double maxEffSize = p.FontSize;
                                            FontWeight maxEffWeight = p.FontWeight;

                                            System.Windows.Documents.TextPointer pointer = p.ContentStart;
                                            while (pointer != null && pointer.CompareTo(p.ContentEnd) < 0) {
                                                if (pointer.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                                                    string runText = pointer.GetTextInRun(LogicalDirection.Forward);
                                                    if (runText.Trim().Length > 0) {
                                                        System.Windows.Documents.TextElement textElement = pointer.Parent as System.Windows.Documents.TextElement;
                                                        if (textElement != null) {
                                                            if (textElement.FontSize > maxEffSize) {
                                                                maxEffSize = textElement.FontSize;
                                                                maxEffWeight = textElement.FontWeight;
                                                            } else if (textElement.FontSize == maxEffSize && textElement.FontWeight > maxEffWeight) {
                                                                maxEffWeight = textElement.FontWeight;
                                                            }
                                                        }
                                                    }
                                                }
                                                pointer = pointer.GetNextContextPosition(LogicalDirection.Forward);
                                            }
                                            
                                            effSize = maxEffSize;
                                            effWeight = maxEffWeight;

                                            bool isHeavy = (effWeight == FontWeights.Bold || effWeight == FontWeights.SemiBold || effWeight == FontWeights.Black || effWeight == FontWeights.ExtraBold);
                                            if (effSize >= 25.5) {
                                                isHeading = true;
                                                level = "H1";
                                            } else if (effSize >= 23.5) {
                                                isHeading = true;
                                                level = "H2";
                                            } else if (effSize >= 19.5) {
                                                isHeading = true;
                                                level = "H3";
                                            } else if (effSize >= 15.5) {
                                                isHeading = true;
                                                level = "H4";
                                            } else if (effSize >= 13.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H5";
                                            } else if (effSize >= 11.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H6";
                                            } else if (effSize >= 10.5 && isHeavy) {
                                                isHeading = true;
                                                level = "H6";
                                            } else if (isHeavy) {
                                                isHeading = true;
                                                level = "H3";
                                            }
                                            
                                            //System.IO.File.AppendAllText(@"c:\projects\ahk\ahk-xaml\examples\clones\outline_debug.txt", string.Format("[{0}] Text='{1}' Size={2} Weight={3} isHeading={4}\n", pIdx, headingText, effSize, effWeight, isHeading));
                                            
                                            if (isHeading) {
                                                sb.Append(pIdx + "," + level + "," + headingText + "\n");
                                            }
                                        }
                                        pIdx++;
                                    }
                                }
                                ptr = ptr.GetNextContextPosition(LogicalDirection.Forward);
                            }
                            string base64Outline = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(sb.ToString()));
                            SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|Outline|" + base64Outline + "\n");
                            break;
                        }
                        case "GoToBlock": {
                            try {
                                string type = "paragraph";
                                int targetIdx = 0;
                                if (docVal.Contains(":")) {
                                    string[] pts = docVal.Split(':');
                                    type = pts[0].ToLower();
                                    int.TryParse(pts[1], out targetIdx);
                                } else {
                                    int.TryParse(docVal, out targetIdx);
                                }
                                
                                int currentIdx = 0;
                                System.Windows.Documents.TextElement foundElement = null;

                                if (type == "paragraph") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Paragraph) {
                                            if (currentIdx == targetIdx) {
                                                foundElement = (System.Windows.Documents.Paragraph)block;
                                            }
                                            currentIdx++;
                                        }
                                    });
                                } else if (type == "table") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Table) {
                                            if (currentIdx == targetIdx) {
                                                foundElement = (System.Windows.Documents.Table)block;
                                            }
                                            currentIdx++;
                                        }
                                    });
                                } else if (type == "hyperlink") {
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (foundElement != null) return;
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (foundElement != null) return;
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    if (currentIdx == targetIdx) {
                                                        foundElement = (System.Windows.Documents.Hyperlink)inline;
                                                    }
                                                    currentIdx++;
                                                }
                                            });
                                        }
                                    });
                                }

                                if (foundElement != null) {
                                    rtb.CaretPosition = foundElement.ContentStart;
                                    rtb.Selection.Select(foundElement.ContentStart, foundElement.ContentEnd);
                                    rtb.Focus();
                                    try {
                                        var rect = rtb.CaretPosition.GetCharacterRect(System.Windows.Documents.LogicalDirection.Forward);
                                        if (rect.Top != 0 || rect.Bottom != 0) {
                                            double targetOffset = rtb.VerticalOffset + rect.Top - 30;
                                            if (targetOffset < 0) targetOffset = 0;
                                            rtb.ScrollToVerticalOffset(targetOffset);
                                        } else {
                                            foundElement.BringIntoView();
                                        }
                                    } catch {
                                        try { foundElement.BringIntoView(); } catch {}
                                    }
                                }
                            } catch {}
                            break;
                        }
                        case "InsertImage": {
                            try {
                                if (System.IO.File.Exists(docVal)) {
                                    var bi = new System.Windows.Media.Imaging.BitmapImage(new Uri(docVal));
                                    var img = new System.Windows.Controls.Image { Source = bi, MaxWidth = 600, Stretch = System.Windows.Media.Stretch.Uniform };
                                    img.Cursor = System.Windows.Input.Cursors.SizeNWSE;
                                    
                                    // Add right-click context menu
                                    var ctxMenu = new ContextMenu();
                                    var miSmall = new MenuItem { Header = "Resize: Small (200px)" };
                                    var miMedium = new MenuItem { Header = "Resize: Medium (400px)" };
                                    var miLarge = new MenuItem { Header = "Resize: Large (600px)" };
                                    var miOriginal = new MenuItem { Header = "Resize: Original" };
                                    var miDelete = new MenuItem { Header = "Delete Image" };
                                    var miCopy = new MenuItem { Header = "Copy Image" };
                                    
                                    miSmall.Click += (s, e) => { img.MaxWidth = 200; img.Width = 200; };
                                    miMedium.Click += (s, e) => { img.MaxWidth = 400; img.Width = 400; };
                                    miLarge.Click += (s, e) => { img.MaxWidth = 600; img.Width = 600; };
                                    miOriginal.Click += (s, e) => { img.ClearValue(FrameworkElement.MaxWidthProperty); img.ClearValue(FrameworkElement.WidthProperty); };
                                    miDelete.Click += (s, e) => {
                                        try {
                                            var parent = LogicalTreeHelper.GetParent(img) as InlineUIContainer;
                                            if (parent != null) {
                                                var para = parent.Parent as System.Windows.Documents.Paragraph;
                                                if (para != null) para.Inlines.Remove(parent);
                                            }
                                        } catch { }
                                    };
                                    miCopy.Click += (s, e) => {
                                        try {
                                            Clipboard.SetImage(bi);
                                        } catch { }
                                    };
                                    
                                    ctxMenu.Items.Add(miSmall);
                                    ctxMenu.Items.Add(miMedium);
                                    ctxMenu.Items.Add(miLarge);
                                    ctxMenu.Items.Add(miOriginal);
                                    ctxMenu.Items.Add(new Separator());
                                    ctxMenu.Items.Add(miCopy);
                                    ctxMenu.Items.Add(miDelete);
                                    img.ContextMenu = ctxMenu;
                                    
                                    // Mouse-drag resizing: drag the image to resize proportionally
                                    bool isResizing = false;
                                    double startX = 0, startW = 0;
                                    img.MouseLeftButtonDown += (s, e) => {
                                        if (System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Shift) {
                                            isResizing = true;
                                            startX = e.GetPosition(img).X;
                                            startW = img.ActualWidth > 0 ? img.ActualWidth : 300;
                                            img.CaptureMouse();
                                            e.Handled = true;
                                        }
                                    };
                                    img.MouseMove += (s, e) => {
                                        if (isResizing) {
                                            double dx = e.GetPosition(img).X - startX;
                                            double newW = Math.Max(50, startW + dx);
                                            img.Width = newW;
                                            img.MaxWidth = newW;
                                            e.Handled = true;
                                        }
                                    };
                                    img.MouseLeftButtonUp += (s, e) => {
                                        if (isResizing) {
                                            isResizing = false;
                                            img.ReleaseMouseCapture();
                                            e.Handled = true;
                                        }
                                    };
                                    
                                    var container = new InlineUIContainer(img, rtb.CaretPosition);
                                }
                            } catch { }
                            break;
                        }
                        case "InsertHR": {
                            var line = new System.Windows.Documents.Paragraph();
                            line.BorderBrush = System.Windows.Media.Brushes.Gray;
                            line.BorderThickness = new Thickness(0, 0, 0, 1);
                            line.Margin = new Thickness(0, 10, 0, 10);
                            rtb.Document.Blocks.Add(line);
                            break;
                        }
                        case "SetLineSpacing": {
                            double spacingMultiplier;
                            if (double.TryParse(docVal, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out spacingMultiplier)) {
                                // Resolve grid line height
                                var lsSettings = rtb.Document.Tag as DocLayoutSettings;
                                double gridLH = 0;
                                if (lsSettings != null && lsSettings.LinePitch > 0) {
                                    gridLH = (lsSettings.LinePitch / 20.0) * (96.0 / 72.0);
                                }
                                // Apply to all paragraphs recursively
                                _ApplyLineSpacingToBlocks(rtb.Document.Blocks, spacingMultiplier, gridLH);
                                // Store multiplier for future reference
                                if (lsSettings != null) {
                                    lsSettings.LineSpacingOverride = spacingMultiplier;
                                }
                                // Re-insert page break spacers if in paper mode
                                if (_docViewModes.ContainsKey(rtb.Name) && _docViewModes[rtb.Name] == "paper") {
                                    var containerEl2 = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm2 = (containerEl2 != null && containerEl2.Tag is string) ? (string)containerEl2.Tag : "Normal";
                                    rtb.Dispatcher.BeginInvoke(new Action(() => {
                                        _InsertPageBreakSpacers(rtb, thm2);
                                    }), System.Windows.Threading.DispatcherPriority.Background);
                                }
                            }
                            break;
                        }
                        case "InsertLink": {
                            try {
                                string linkUrl = docVal;
                                string displayText = "";
                                if (!rtb.Selection.IsEmpty) {
                                    displayText = rtb.Selection.Text;
                                }
                                if (string.IsNullOrEmpty(displayText)) {
                                    displayText = linkUrl;
                                }
                                var linkRun = new System.Windows.Documents.Run(displayText);
                                var hyperlink = new System.Windows.Documents.Hyperlink(linkRun, rtb.CaretPosition);
                                try { hyperlink.NavigateUri = new Uri(linkUrl, UriKind.RelativeOrAbsolute); } catch { }
                                hyperlink.Foreground = new System.Windows.Media.SolidColorBrush(
                                    System.Windows.Media.Color.FromRgb(17, 85, 204));
                                hyperlink.ToolTip = linkUrl;
                                hyperlink.Cursor = System.Windows.Input.Cursors.Hand;
                                hyperlink.RequestNavigate += (s, e) => {
                                    try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); } catch { }
                                    e.Handled = true;
                                };
                            } catch { }
                            break;
                        }
                        case "GetWordCount": {
                            string rtbN = ((FrameworkElement)ctrl).Name;
                            var pageReader = win.FindName(rtbN + "_PageReader") as FlowDocumentReader;
                            FlowDocument activeDoc = rtb.Document;
                            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                                activeDoc = pageReader.Document;
                            }
                            var range = new TextRange(activeDoc.ContentStart, activeDoc.ContentEnd);
                            string wcText = range.Text;
                            int words = wcText.Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries).Length;
                            int chars = wcText.Length;
                            SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|WordCount|" + BridgeUtil.LengthPrefix(words + "," + chars) + "\n");
                            break;
                        }
                        case "Zoom": {
                            double zoom;
                            if (double.TryParse(docVal, out zoom)) {
                                var parent = System.Windows.Media.VisualTreeHelper.GetParent(rtb) as FrameworkElement;
                                if (parent == null) parent = rtb;
                                var st = parent.LayoutTransform as System.Windows.Media.ScaleTransform;
                                if (st == null) {
                                    st = new System.Windows.Media.ScaleTransform(1, 1);
                                    parent.LayoutTransform = st;
                                }
                                st.ScaleX = zoom / 100.0;
                                st.ScaleY = zoom / 100.0;
                            }
                            break;
                        }
                        case "NewDocument": {
                            rtb.Document = new FlowDocument();
                            rtb.Document.FontFamily = new System.Windows.Media.FontFamily("Segoe UI, Segoe UI Emoji, Segoe UI Symbol");
                            rtb.Document.FontSize = 14;
                            
                            string viewMode = "paper";
                            if (_docViewModes.ContainsKey(rtb.Name)) {
                                viewMode = _docViewModes[rtb.Name];
                            } else {
                                _docViewModes[rtb.Name] = viewMode;
                            }
                            
                            var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                            string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                            
                            ApplyViewMode(rtb, viewMode, currentTheme, win);
                            break;
                        }
                        case "Undo":
                            rtb.Undo();
                            break;
                        case "Redo":
                            rtb.Redo();
                            break;
                        case "SelectAll": {
                            rtb.SelectAll();
                            break;
                        }
                        case "FindNext": {
                            string fnQuery = docVal; StringComparison fnCmp = StringComparison.OrdinalIgnoreCase;
                            int fnMc = docVal.IndexOf("|||MC:"); if (fnMc >= 0) { fnQuery = docVal.Substring(0, fnMc); fnCmp = docVal.Substring(fnMc + 6) == "1" ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase; }
                            if (!string.IsNullOrEmpty(fnQuery)) {
                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder();
                                foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();

                                TextPointer currentStart = rtb.Selection.IsEmpty ? rtb.Document.ContentStart : rtb.Selection.End;
                                int searchStartIdx = 0;
                                for (int i = 0; i < map.Count; i++) { if (map[i].Start.CompareTo(currentStart) >= 0) { searchStartIdx = i; break; } }

                                int idx = plainText.IndexOf(fnQuery, searchStartIdx, fnCmp);
                                if (idx < 0) idx = plainText.IndexOf(fnQuery, 0, fnCmp);

                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start;
                                    TextPointer end = map[idx + fnQuery.Length - 1].End;
                                    if (start != null && end != null) {
                                        if (_activeMatchRange != null) { try { _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _highlightBrush); } catch { } }
                                        _activeMatchRange = new TextRange(start, end);
                                        _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _activeMatchBrush);
                                        rtb.Focus();
                                        rtb.Selection.Select(start, end); 
                                        if (start.Paragraph != null) start.Paragraph.BringIntoView(); 
                                    }
                                }
                            }
                            break;
                        }
                        case "FindPrevious": {
                            string fpQuery = docVal; StringComparison fpCmp = StringComparison.OrdinalIgnoreCase;
                            int fpMc = docVal.IndexOf("|||MC:"); if (fpMc >= 0) { fpQuery = docVal.Substring(0, fpMc); fpCmp = docVal.Substring(fpMc + 6) == "1" ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase; }
                            if (!string.IsNullOrEmpty(fpQuery)) {
                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder();
                                foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();

                                TextPointer currentStart = rtb.Selection.IsEmpty ? rtb.Document.ContentEnd : rtb.Selection.Start;
                                int searchStartIdx = map.Count - 1;
                                for (int i = map.Count - 1; i >= 0; i--) { if (map[i].End.CompareTo(currentStart) <= 0) { searchStartIdx = i; break; } }

                                int idx = plainText.LastIndexOf(fpQuery, searchStartIdx, fpCmp);
                                if (idx < 0) idx = plainText.LastIndexOf(fpQuery, map.Count - 1, fpCmp);

                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start;
                                    TextPointer end = map[idx + fpQuery.Length - 1].End;
                                    if (start != null && end != null) {
                                        if (_activeMatchRange != null) { try { _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _highlightBrush); } catch { } }
                                        _activeMatchRange = new TextRange(start, end);
                                        _activeMatchRange.ApplyPropertyValue(TextElement.BackgroundProperty, _activeMatchBrush);
                                        rtb.Focus();
                                        rtb.Selection.Select(start, end); 
                                        if (start.Paragraph != null) start.Paragraph.BringIntoView(); 
                                    }
                                }
                            }
                            break;
                        }
                        case "ReplaceCurrent": {
                            string[] rp = docVal.Split(new[] { "|||" }, StringSplitOptions.None);
                            if (rp.Length >= 2) {
                                string find = rp[0]; string replace = rp[1];
                                StringComparison rcCmp = StringComparison.OrdinalIgnoreCase;
                                for (int pi = 2; pi < rp.Length; pi++) { if (rp[pi] == "MC:1") rcCmp = StringComparison.Ordinal; }
                                
                                if (!rtb.Selection.IsEmpty && rtb.Selection.Text.Equals(find, rcCmp)) rtb.Selection.Text = replace;

                                var map = BuildCharPositionMap(rtb.Document);
                                var sb = new StringBuilder(); foreach (var cp in map) sb.Append(cp.Character);
                                string plainText = sb.ToString();
                                TextPointer currentStart = rtb.Selection.End;
                                int searchStartIdx = 0;
                                for (int i = 0; i < map.Count; i++) { if (map[i].Start.CompareTo(currentStart) >= 0) { searchStartIdx = i; break; } }
                                int idx = plainText.IndexOf(find, searchStartIdx, rcCmp);
                                if (idx < 0) idx = plainText.IndexOf(find, 0, rcCmp);
                                if (idx >= 0) {
                                    TextPointer start = map[idx].Start; TextPointer end = map[idx + find.Length - 1].End;
                                    if (start != null && end != null) { rtb.Selection.Select(start, end); if (start.Paragraph != null) start.Paragraph.BringIntoView(); }
                                }
                            }
                            break;
                        }
                        case "ReplaceAll": {
                            string[] rp = docVal.Split(new[] { "|||" }, StringSplitOptions.None);
                            if (rp.Length >= 2) {
                                string find = rp[0]; string replace = rp[1];
                                bool isPreview = rp.Length > 2 && rp[2] == "1";
                                bool raMatchCase = false;
                                for (int pi = 2; pi < rp.Length; pi++) { if (rp[pi] == "MC:1") raMatchCase = true; }
                                
                                if (isPreview) {
                                    if (_isPreviewActive) rtb.Undo();
                                    rtb.BeginChange();
                                    ReplaceAllBackward(rtb, find, replace, raMatchCase);
                                    rtb.EndChange();
                                    _isPreviewActive = true;
                                } else {
                                    rtb.BeginChange();
                                    ReplaceAllBackward(rtb, find, replace, raMatchCase);
                                    rtb.EndChange();
                                }
                            }
                            break;
                        }
                        case "HighlightFinds": {
                            // Parse match-case flag: value may end with |||MC:0 or |||MC:1
                            string hlQuery = docVal ?? "";
                            bool hlMatchCase = false;
                            int hlMcIdx = hlQuery.IndexOf("|||MC:");
                            if (hlMcIdx >= 0) { hlMatchCase = hlQuery.Substring(hlMcIdx + 6) == "1"; hlQuery = hlQuery.Substring(0, hlMcIdx); }

                            _pendingHighlightQuery = hlQuery;
                            _pendingHighlightMatchCase = hlMatchCase;
                            _pendingHighlightRtb = rtb;
                            if (_highlightDebounce == null) {
                                _highlightDebounce = new System.Windows.Threading.DispatcherTimer {
                                    Interval = TimeSpan.FromMilliseconds(200)
                                };
                                _highlightDebounce.Tick += (ds, de) => {
                                    _highlightDebounce.Stop();
                                    ClearSearchHighlights(_pendingHighlightRtb);
                                    if (!string.IsNullOrEmpty(_pendingHighlightQuery) && _pendingHighlightQuery.Length >= 2) {
                                        HighlightAllMatches(_pendingHighlightRtb, _pendingHighlightQuery, _pendingHighlightMatchCase);
                                    }
                                };
                            }
                            _highlightDebounce.Stop();
                            if (string.IsNullOrEmpty(hlQuery)) { 
                                ClearSearchHighlights(rtb); 
                                var tb = win.FindName(rtb.Name + "_MatchCount") as System.Windows.Controls.TextBlock;
                                if (tb != null) tb.Text = "";
                            } else { 
                                _highlightDebounce.Start(); 
                            }
                            break;
                        }
                        case "ConfirmReplace": {
                            _isPreviewActive = false;
                            break;
                        }
                        case "CancelReplace": {
                            if (_isPreviewActive) {
                                rtb.Undo();
                                _isPreviewActive = false;
                            }
                            break;
                        }
                        case "ApplyDarkMode": {
                            ApplyDarkModeToDocument(rtb.Document);
                            break;
                        }
                        case "RestoreColors": {
                            RestoreDocumentColors(rtb.Document);
                            break;
                        }
                        case "SetupToolbarResponsive": {
                            // Setup responsive toolbar: hide/show named groups based on window width
                            // docVal = comma-separated list of group names in order of priority (first hidden first)
                            // Format can be "MainGrp" or "MainGrp|PopoverGrp"
                            if (!string.IsNullOrEmpty(docVal)) {
                                string[] groupNames = docVal.Split(',');
                                // Thresholds (in window pixels): each group gets hidden below this width
                                double[] thresholds = new double[] { 860, 760, 660, 560, 460 };
                                
                                Action<double> evaluateWidth = (w) => {
                                    for (int gi = 0; gi < groupNames.Length; gi++) {
                                        string[] pairs = groupNames[gi].Trim().Split('|');
                                        var mainGrp = win.FindName(pairs[0]) as FrameworkElement;
                                        var popGrp = pairs.Length > 1 ? win.FindName(pairs[1]) as FrameworkElement : null;
                                        
                                        if (mainGrp != null) {
                                            double threshold = gi < thresholds.Length ? thresholds[gi] : 400;
                                            bool isVisible = w > threshold;
                                            mainGrp.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;
                                            if (popGrp != null) {
                                                popGrp.Visibility = isVisible ? Visibility.Collapsed : Visibility.Visible;
                                            }
                                        }
                                    }
                                };

                                win.SizeChanged += (s, e) => {
                                    evaluateWidth(win.ActualWidth);
                                };
                                // Trigger initial evaluation
                                evaluateWidth(win.ActualWidth);
                            }
                            break;
                        }
                        case "QueryDOM": {
                            try {
                                string selector = docVal.ToLower();
                                StringBuilder sb = new StringBuilder();

                                if (selector == "headings") {
                                    int pIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string styleId = p.Tag as string ?? "";
                                            
                                            if (string.IsNullOrEmpty(styleId)) {
                                                if (p.FontWeight == FontWeights.Bold && p.FontSize > 14) {
                                                    styleId = "Heading1";
                                                }
                                            }
                                            
                                            string domText = new TextRange(p.ContentStart, p.ContentEnd).Text.Trim();
                                            bool isHeading = styleId.StartsWith("Heading", StringComparison.OrdinalIgnoreCase) || 
                                                             styleId.StartsWith("H", StringComparison.OrdinalIgnoreCase);
                                            
                                            if (!string.IsNullOrEmpty(domText) && isHeading) {
                                                sb.Append(pIdx + "|" + styleId + "|" + domText + "\n");
                                            }
                                            pIdx++;
                                        }
                                    });
                                } else if (selector == "hyperlinks") {
                                    int hlCount = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    string url = hl.NavigateUri != null ? hl.NavigateUri.ToString() : "";
                                                    string domText = new TextRange(hl.ContentStart, hl.ContentEnd).Text.Trim();
                                                    if (string.IsNullOrEmpty(domText)) domText = url;
                                                    
                                                    string relId = "memHl_" + hlCount;
                                                    if (!string.IsNullOrEmpty(url)) {
                                                        sb.Append(domText + "|" + url + "|" + relId + "\n");
                                                    }
                                                    hlCount++;
                                                }
                                            });
                                        }
                                    });
                                } else if (selector == "tables") {
                                    int tIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Table) {
                                            var t = (System.Windows.Documents.Table)block;
                                            int rows = 0;
                                            foreach (var rg in t.RowGroups) rows += rg.Rows.Count;
                                            
                                            int cols = 0;
                                            if (t.RowGroups.Count > 0 && t.RowGroups[0].Rows.Count > 0) {
                                                cols = t.RowGroups[0].Rows[0].Cells.Count;
                                            }
                                            
                                            string firstCellText = "";
                                            if (t.RowGroups.Count > 0 && t.RowGroups[0].Rows.Count > 0 && t.RowGroups[0].Rows[0].Cells.Count > 0) {
                                                var firstCell = t.RowGroups[0].Rows[0].Cells[0];
                                                firstCellText = new TextRange(firstCell.ContentStart, firstCell.ContentEnd).Text.Trim();
                                            }
                                            if (firstCellText.Length > 30) firstCellText = firstCellText.Substring(0, 27) + "...";
                                            
                                            sb.Append(tIdx + "|" + rows + "|" + cols + "|" + firstCellText + "\n");
                                            tIdx++;
                                        }
                                    });
                                } else if (selector == "paragraphs") {
                                    int pIdx = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string domText = new TextRange(p.ContentStart, p.ContentEnd).Text.Trim();
                                            string style = p.Tag as string ?? "Normal";
                                            if (!string.IsNullOrEmpty(domText)) {
                                                sb.Append(pIdx + "|" + style + "|" + domText + "\n");
                                            }
                                            pIdx++;
                                        }
                                    });
                                } else if (selector == "fonts") {
                                    var uniqueFonts = new System.Collections.Generic.HashSet<string>();
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            if (p.FontFamily != null) uniqueFonts.Add(p.FontFamily.Source);
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Run) {
                                                    var run = (System.Windows.Documents.Run)inline;
                                                    if (run.FontFamily != null) uniqueFonts.Add(run.FontFamily.Source);
                                                } else if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    if (hl.FontFamily != null) uniqueFonts.Add(hl.FontFamily.Source);
                                                }
                                            });
                                        }
                                    });
                                    foreach (var fName in uniqueFonts) {
                                        if (!string.IsNullOrEmpty(fName)) {
                                            sb.Append(fName + "\n");
                                        }
                                    }
                                }

                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(sb.ToString()));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerQueryDone|" + BridgeUtil.LengthPrefix(selector + "|" + b64) + "\n");
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "HighlightStyle": {
                            try {
                                string[] hp = docVal.Split('|');
                                if (hp.Length >= 2) {
                                    string styleId = hp[0];
                                    string colorName = hp[1];
                                    
                                    System.Windows.Media.Brush hlBrush = System.Windows.Media.Brushes.Yellow;
                                    try {
                                        hlBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFromString(colorName);
                                    } catch {}

                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            string pStyle = p.Tag as string ?? "";
                                            
                                            if (string.IsNullOrEmpty(pStyle)) {
                                                if (p.FontWeight == FontWeights.Bold && p.FontSize > 14) {
                                                    pStyle = "Heading1";
                                                }
                                            }

                                            if (string.Equals(pStyle, styleId, StringComparison.OrdinalIgnoreCase) || 
                                                (styleId == "Heading" && pStyle.StartsWith("Heading", StringComparison.OrdinalIgnoreCase))) {
                                                
                                                TraverseInlines(p.Inlines, (inline) => {
                                                    if (inline is System.Windows.Documents.Run) {
                                                        var run = (System.Windows.Documents.Run)inline;
                                                        run.Background = hlBrush;
                                                    }
                                                });
                                            }
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "AuditLinks": {
                            try {
                                StringBuilder sb = new StringBuilder();
                                int hlCount = 0;
                                
                                TraverseBlocks(rtb.Document.Blocks, (block) => {
                                    if (block is System.Windows.Documents.Paragraph) {
                                        var p = (System.Windows.Documents.Paragraph)block;
                                        TraverseInlines(p.Inlines, (inline) => {
                                            if (inline is System.Windows.Documents.Hyperlink) {
                                                var hl = (System.Windows.Documents.Hyperlink)inline;
                                                string url = hl.NavigateUri != null ? hl.NavigateUri.ToString() : "";
                                                string domText = new TextRange(hl.ContentStart, hl.ContentEnd).Text.Trim();
                                                if (string.IsNullOrEmpty(domText)) domText = url;
                                                
                                                string relId = "memHl_" + hlCount;
                                                if (!string.IsNullOrEmpty(url)) {
                                                    sb.Append(relId + "|" + url + "|" + domText + "\n");
                                                }
                                                hlCount++;
                                            }
                                        });
                                    }
                                });
                                
                                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(sb.ToString()));
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerAuditDone|" + BridgeUtil.LengthPrefix(b64) + "\n");
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "RewriteLinks": {
                            try {
                                string[] lines = docVal.Split('\n');
                                var replacements = new System.Collections.Generic.Dictionary<string, string>();
                                foreach (var line in lines) {
                                    if (string.IsNullOrEmpty(line)) continue;
                                    string[] parts2 = line.Split('|');
                                    if (parts2.Length >= 2) {
                                        replacements[parts2[0].Trim()] = parts2[1].Trim();
                                    }
                                }

                                if (replacements.Count > 0) {
                                    int hlCount = 0;
                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    string relId = "memHl_" + hlCount;
                                                    if (replacements.ContainsKey(relId)) {
                                                        string newUrl = replacements[relId];
                                                        try {
                                                            hl.NavigateUri = new Uri(newUrl, UriKind.RelativeOrAbsolute);
                                                            hl.ToolTip = newUrl;
                                                        } catch {}
                                                    }
                                                    hlCount++;
                                                }
                                            });
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "StandardizeFont": {
                            try {
                                string[] hp = docVal.Split('|');
                                if (hp.Length >= 2) {
                                    string fromFont = hp[0].Trim();
                                    string toFont = hp[1].Trim();
                                    var targetFamily = new System.Windows.Media.FontFamily(toFont);

                                    TraverseBlocks(rtb.Document.Blocks, (block) => {
                                        if (block is System.Windows.Documents.Paragraph) {
                                            var p = (System.Windows.Documents.Paragraph)block;
                                            if (p.FontFamily != null && string.Equals(p.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                p.FontFamily = targetFamily;
                                            }
                                            TraverseInlines(p.Inlines, (inline) => {
                                                if (inline is System.Windows.Documents.Run) {
                                                    var run = (System.Windows.Documents.Run)inline;
                                                    if (run.FontFamily != null && string.Equals(run.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                        run.FontFamily = targetFamily;
                                                    }
                                                } else if (inline is System.Windows.Documents.Hyperlink) {
                                                    var hl = (System.Windows.Documents.Hyperlink)inline;
                                                    if (hl.FontFamily != null && string.Equals(hl.FontFamily.Source, fromFont, StringComparison.OrdinalIgnoreCase)) {
                                                        hl.FontFamily = targetFamily;
                                                    }
                                                }
                                            });
                                        }
                                    });
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "CompileTemplate": {
                            try {
                                string[] lines = docVal.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                                if (lines.Length > 0) {
                                    System.Windows.Documents.Paragraph placeholder = null;
                                    System.Windows.Documents.BlockCollection parentCollection = null;
                                    int placeholderIdx = -1;

                                    Action<System.Windows.Documents.BlockCollection> searchCollection = null;
                                    searchCollection = (coll) => {
                                        if (placeholder != null) return;
                                        for (int i = 0; i < coll.Count; i++) {
                                            var b = coll.ElementAt(i);
                                            if (b is System.Windows.Documents.Paragraph) {
                                                var p = (System.Windows.Documents.Paragraph)b;
                                                string pText = new TextRange(p.ContentStart, p.ContentEnd).Text;
                                                if (pText.Contains("{{REPORT_TABLE}}")) {
                                                    placeholder = p;
                                                    parentCollection = coll;
                                                    placeholderIdx = i;
                                                    return;
                                                }
                                            } else if (b is System.Windows.Documents.Section) {
                                                searchCollection(((System.Windows.Documents.Section)b).Blocks);
                                            } else if (b is System.Windows.Documents.List) {
                                                foreach (var li in ((System.Windows.Documents.List)b).ListItems) {
                                                    searchCollection(li.Blocks);
                                                }
                                            } else if (b is System.Windows.Documents.Table) {
                                                foreach (var rg in ((System.Windows.Documents.Table)b).RowGroups) {
                                                    foreach (var row in rg.Rows) {
                                                        foreach (var cell in row.Cells) {
                                                            searchCollection(cell.Blocks);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    };

                                    searchCollection(rtb.Document.Blocks);

                                    if (placeholder != null && parentCollection != null) {
                                        var table = new System.Windows.Documents.Table();
                                        table.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                        table.BorderThickness = new Thickness(1);
                                        table.CellSpacing = 0;
                                        table.Margin = new Thickness(0, 8, 0, 8);
                                        
                                        string[] headers = lines[0].Split(',');
                                        int colCount = headers.Length;
                                        
                                        for (int i = 0; i < colCount; i++) {
                                            table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                                        }

                                        var rg = new System.Windows.Documents.TableRowGroup();

                                        var headerRow = new System.Windows.Documents.TableRow();
                                        foreach (string colText in headers) {
                                            var cell = new System.Windows.Documents.TableCell();
                                            cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                            cell.BorderThickness = new Thickness(0.5);
                                            cell.Padding = new Thickness(8, 6, 8, 6);
                                            cell.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(47, 85, 151));
                                            
                                            var p = new System.Windows.Documents.Paragraph();
                                            p.TextAlignment = System.Windows.TextAlignment.Center;
                                            var run = new System.Windows.Documents.Run(colText.Trim());
                                            run.FontWeight = FontWeights.Bold;
                                            run.Foreground = System.Windows.Media.Brushes.White;
                                            run.FontSize = 12;
                                            p.Inlines.Add(run);
                                            cell.Blocks.Add(p);
                                            headerRow.Cells.Add(cell);
                                        }
                                        rg.Rows.Add(headerRow);

                                        for (int rIdx = 1; rIdx < lines.Length; rIdx++) {
                                            string[] cells = lines[rIdx].Split(',');
                                            var row = new System.Windows.Documents.TableRow();
                                            System.Windows.Media.Color bgCol = (rIdx % 2 == 1) ? System.Windows.Media.Color.FromRgb(242, 245, 249) : System.Windows.Media.Color.FromRgb(255, 255, 255);
                                            var bgBrush = new System.Windows.Media.SolidColorBrush(bgCol);

                                            for (int cIdx = 0; cIdx < colCount; cIdx++) {
                                                string cellVal = cIdx < cells.Length ? cells[cIdx].Trim() : "";
                                                var cell = new System.Windows.Documents.TableCell();
                                                cell.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(180, 180, 180));
                                                cell.BorderThickness = new Thickness(0.5);
                                                cell.Padding = new Thickness(8, 6, 8, 6);
                                                cell.Background = bgBrush;

                                                var p = new System.Windows.Documents.Paragraph();
                                                p.TextAlignment = System.Windows.TextAlignment.Left;
                                                var run = new System.Windows.Documents.Run(cellVal);
                                                run.FontSize = 11;
                                                p.Inlines.Add(run);
                                                cell.Blocks.Add(p);
                                                row.Cells.Add(cell);
                                            }
                                            rg.Rows.Add(row);
                                        }

                                        table.RowGroups.Add(rg);

                                        parentCollection.InsertAfter(placeholder, table);
                                        parentCollection.Remove(placeholder);
                                    }
                                }
                            } catch (Exception ex) {
                                SendToAhk("EVENT|" + winId + "|" + ((FrameworkElement)ctrl).Name + "|PowerToolsError|" + BridgeUtil.LengthPrefix(ex.Message) + "\n");
                            }
                            break;
                        }
                        case "SetPageView": {
                            try {
                                string viewMode = (docVal ?? "").ToLower().Trim();
                                var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                string currentTheme = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                ApplyViewMode(rtb, viewMode, currentTheme, win);
                            } catch (Exception ex) {
                                string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_editor_debug.log");
                                System.IO.File.AppendAllText(debugPath, "SetPageView EXCEPTION: " + ex.ToString() + "\n");
                            }
                            break;
                        }
                        case "UpdateSpacers": {
                            try {
                                string currentMode = "paper";
                                if (_docViewModes.ContainsKey(rtb.Name)) {
                                    currentMode = _docViewModes[rtb.Name];
                                }
                                if (currentMode == "paper") {
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    _InsertPageBreakSpacers(rtb, thm);
                                }
                                
                                // Also update flow document reader if active
                                string readerName = rtb.Name + "_PageReader";
                                FlowDocumentReader reader = win.FindName(readerName) as FlowDocumentReader;
                                if (reader != null && reader.Visibility == Visibility.Visible) {
                                    var containerEl = win.FindName(rtb.Name + "_Container") as FrameworkElement;
                                    string thm = (containerEl != null && containerEl.Tag is string) ? (string)containerEl.Tag : "Normal";
                                    StyleReaderVisuals(reader, thm, win);
                                }
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // TABLE OPERATIONS
                        // ================================================================
                        case "InsertRowAbove":
                        case "InsertRowBelow": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    if (row != null && rg != null) {
                                        int colCount = row.Cells.Count;
                                        var newRow = new System.Windows.Documents.TableRow();
                                        for (int c = 0; c < colCount; c++) {
                                            var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                                            newCell.BorderBrush = cell.BorderBrush;
                                            newCell.BorderThickness = cell.BorderThickness;
                                            newCell.Padding = cell.Padding;
                                            newRow.Cells.Add(newCell);
                                        }
                                        int idx = rg.Rows.IndexOf(row);
                                        if (docCmd == "InsertRowAbove") {
                                            rg.Rows.Insert(idx, newRow);
                                        } else {
                                            rg.Rows.Insert(idx + 1, newRow);
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "InsertColumnLeft":
                        case "InsertColumnRight": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        int colIdx = row.Cells.IndexOf(cell);
                                        int insertIdx = docCmd == "InsertColumnLeft" ? colIdx : colIdx + 1;
                                        table.Columns.Add(new System.Windows.Documents.TableColumn { Width = new GridLength(1, GridUnitType.Star) });
                                        foreach (var trg in table.RowGroups) {
                                            foreach (var tr in trg.Rows) {
                                                var newCell = new System.Windows.Documents.TableCell(new System.Windows.Documents.Paragraph());
                                                newCell.BorderBrush = cell.BorderBrush;
                                                newCell.BorderThickness = cell.BorderThickness;
                                                newCell.Padding = cell.Padding;
                                                if (insertIdx <= tr.Cells.Count) {
                                                    tr.Cells.Insert(insertIdx, newCell);
                                                } else {
                                                    tr.Cells.Add(newCell);
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "DeleteRow": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    if (rg != null && rg.Rows.Count > 1) {
                                        rg.Rows.Remove(row);
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "DeleteColumn": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        int colIdx = row.Cells.IndexOf(cell);
                                        if (row.Cells.Count > 1) {
                                            foreach (var trg in table.RowGroups) {
                                                foreach (var tr in trg.Rows) {
                                                    if (colIdx < tr.Cells.Count) {
                                                        tr.Cells.RemoveAt(colIdx);
                                                    }
                                                }
                                            }
                                            if (table.Columns.Count > 0) {
                                                table.Columns.RemoveAt(table.Columns.Count - 1);
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "CellBackground": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var color = ShowColorPickerDialog(win);
                                    if (color.HasValue) {
                                        cell.Background = new System.Windows.Media.SolidColorBrush(color.Value);
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "TableBorders": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    var row = cell.Parent as System.Windows.Documents.TableRow;
                                    var rg = row.Parent as System.Windows.Documents.TableRowGroup;
                                    var table = rg.Parent as System.Windows.Documents.Table;
                                    if (table != null) {
                                        // Toggle between thick, thin, and no borders
                                        double currentThick = table.BorderThickness.Left;
                                        Thickness newBorder;
                                        if (currentThick >= 1.5) newBorder = new Thickness(0);
                                        else if (currentThick >= 0.5) newBorder = new Thickness(2);
                                        else newBorder = new Thickness(1);
                                        table.BorderThickness = newBorder;
                                        foreach (var trg in table.RowGroups) {
                                            foreach (var tr in trg.Rows) {
                                                foreach (var tc in tr.Cells) {
                                                    tc.BorderThickness = new Thickness(Math.Max(0.5, newBorder.Left * 0.5));
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch { }
                            break;
                        }
                        case "MergeCells": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null) {
                                    int current = cell.ColumnSpan;
                                    cell.ColumnSpan = current + 1;
                                }
                            } catch { }
                            break;
                        }
                        case "SplitCell": {
                            try {
                                var cell = FindTableCellAtCaret(rtb);
                                if (cell != null && cell.ColumnSpan > 1) {
                                    cell.ColumnSpan = cell.ColumnSpan - 1;
                                }
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // FORMATTING COMMANDS
                        // ================================================================
                        case "Superscript": {
                            try {
                                var sel = rtb.Selection;
                                if (!sel.IsEmpty) {
                                    var current = sel.GetPropertyValue(Inline.BaselineAlignmentProperty);
                                    if (current is BaselineAlignment && (BaselineAlignment)current == BaselineAlignment.Superscript)
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                                    else
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Superscript);
                                    sel.ApplyPropertyValue(TextElement.FontSizeProperty, 10.0);
                                }
                            } catch { }
                            break;
                        }
                        case "Subscript": {
                            try {
                                var sel = rtb.Selection;
                                if (!sel.IsEmpty) {
                                    var current = sel.GetPropertyValue(Inline.BaselineAlignmentProperty);
                                    if (current is BaselineAlignment && (BaselineAlignment)current == BaselineAlignment.Subscript)
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                                    else
                                        sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Subscript);
                                    sel.ApplyPropertyValue(TextElement.FontSizeProperty, 10.0);
                                }
                            } catch { }
                            break;
                        }
                        case "IncreaseFontSize": {
                            try {
                                var sel = rtb.Selection;
                                var sz = sel.GetPropertyValue(TextElement.FontSizeProperty);
                                double currentSize = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                                double[] sizes = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72 };
                                double newSize = 72;
                                for (int si = 0; si < sizes.Length; si++) {
                                    if (sizes[si] > currentSize) { newSize = sizes[si]; break; }
                                }
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, newSize);
                            } catch { }
                            break;
                        }
                        case "DecreaseFontSize": {
                            try {
                                var sel = rtb.Selection;
                                var sz = sel.GetPropertyValue(TextElement.FontSizeProperty);
                                double currentSize = (sz != DependencyProperty.UnsetValue) ? (double)sz : 14.0;
                                double[] sizes = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72 };
                                double newSize = 8;
                                for (int si = sizes.Length - 1; si >= 0; si--) {
                                    if (sizes[si] < currentSize) { newSize = sizes[si]; break; }
                                }
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, newSize);
                            } catch { }
                            break;
                        }
                        case "TextColor": {
                            try {
                                var color = ShowColorPickerDialog(win);
                                if (color.HasValue) {
                                    rtb.Selection.ApplyPropertyValue(TextElement.ForegroundProperty,
                                        new System.Windows.Media.SolidColorBrush(color.Value));
                                }
                            } catch { }
                            break;
                        }
                        case "Highlight": {
                            try {
                                var color = ShowColorPickerDialog(win);
                                if (color.HasValue) {
                                    rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty,
                                        new System.Windows.Media.SolidColorBrush(color.Value));
                                }
                            } catch { }
                            break;
                        }
                        case "ClearFormatting": {
                            try {
                                var sel = rtb.Selection;
                                sel.ApplyPropertyValue(TextElement.FontSizeProperty, 14.0);
                                sel.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
                                sel.ApplyPropertyValue(TextElement.FontStyleProperty, FontStyles.Normal);
                                sel.ApplyPropertyValue(Inline.TextDecorationsProperty, null);
                                sel.ApplyPropertyValue(TextElement.ForegroundProperty, System.Windows.Media.Brushes.Black);
                                sel.ApplyPropertyValue(TextElement.BackgroundProperty, System.Windows.Media.Brushes.Transparent);
                                sel.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Baseline);
                            } catch { }
                            break;
                        }
                        // ================================================================
                        // SPELL CHECK COMMANDS
                        // ================================================================
                        case "LoadDictionary": {
                            try {
                                var dlg = new Microsoft.Win32.OpenFileDialog();
                                dlg.Title = "Select Dictionary File (.dic / .lex)";
                                dlg.Filter = "Dictionary Files (*.dic;*.lex)|*.dic;*.lex|All Files|*.*";
                                if (dlg.ShowDialog(win) == true) {
                                    string dictPath = dlg.FileName;
                                    try {
                                        Uri dictUri = new Uri(dictPath);
                                        if (!rtb.SpellCheck.CustomDictionaries.Contains(dictUri)) {
                                            rtb.SpellCheck.CustomDictionaries.Add(dictUri);
                                        }
                                    } catch { }
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch { }
                            break;
                        }
                        case "AddDictionary": {
                            try {
                                string dictPath = docVal;
                                if (!string.IsNullOrEmpty(dictPath)) {
                                    Uri dictUri = new Uri(dictPath);
                                    if (!rtb.SpellCheck.CustomDictionaries.Contains(dictUri)) {
                                        rtb.SpellCheck.CustomDictionaries.Add(dictUri);
                                    }
                                    SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                                }
                            } catch { }
                            break;
                        }
                        case "SpellCheckOff": {
                            try {
                                rtb.SpellCheck.IsEnabled = false;
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                        case "SpellCheck": {
                            try {
                                string scAction = (docVal ?? "").ToLower().Trim();
                                if (scAction == "on") {
                                    rtb.SpellCheck.IsEnabled = true;
                                } else if (scAction == "off") {
                                    rtb.SpellCheck.IsEnabled = false;
                                } else if (scAction == "toggle") {
                                    rtb.SpellCheck.IsEnabled = !rtb.SpellCheck.IsEnabled;
                                } else if (scAction.StartsWith("setlang:")) {
                                    string langTag = scAction.Substring(8);
                                    _spellCheckLangs[rtb.Name] = langTag;
                                    string langToApply = langTag;
                                    if (langTag == "auto") {
                                        langToApply = DetectLanguage(rtb);
                                    }
                                    var xmlLang = System.Windows.Markup.XmlLanguage.GetLanguage(langToApply);
                                    rtb.Language = xmlLang;
                                    if (rtb.Document != null) {
                                        rtb.Document.Language = xmlLang;
                                    }
                                    bool wasEnabled = rtb.SpellCheck.IsEnabled;
                                    rtb.SpellCheck.IsEnabled = false;
                                    rtb.SpellCheck.IsEnabled = wasEnabled;
                                }
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                        case "QuerySpellCheck": {
                            try {
                                SendSpellCheckInfo(rtb, winId, ((FrameworkElement)ctrl).Name);
                            } catch { }
                            break;
                        }
                    }
                }
#endif
                else if (parts[1] == "StartPositionTimer" && ctrl is MediaElement)
                {
                    // Handle all position tracking and seeking in C# to avoid IPC feedback loops
                    var me = (MediaElement)ctrl;
                    string sliderName = parts.Length > 2 ? parts[2] : "";
                    if (!string.IsNullOrEmpty(sliderName))
                    {
                        var slider = win.FindName(sliderName) as Slider;
                        if (slider != null)
                        {
                            bool isSeeking = false;
                            bool isUpdating = false;

                            // Detect user drag start/end via Thumb routed events
                            slider.AddHandler(Thumb.DragStartedEvent, new DragStartedEventHandler((ds, de) =>
                            {
                                isSeeking = true;
                            }));
                            slider.AddHandler(Thumb.DragCompletedEvent, new DragCompletedEventHandler((dc, dce) =>
                            {
                                me.Position = TimeSpan.FromSeconds(slider.Value);
                                isSeeking = false;
                            }));

                            // Also handle click-on-track seeking
                            slider.PreviewMouseLeftButtonUp += (mu, mue) =>
                            {
                                if (!isSeeking)
                                {
                                    me.Position = TimeSpan.FromSeconds(slider.Value);
                                }
                            };

                            // Timer syncs slider position (only when user isn't seeking)
                            var posTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
                            posTimer.Tick += (s, e) =>
                            {
                                if (me.NaturalDuration.HasTimeSpan && !isSeeking)
                                {
                                    isUpdating = true;
                                    slider.Maximum = me.NaturalDuration.TimeSpan.TotalSeconds;
                                    slider.Value = me.Position.TotalSeconds;
                                    isUpdating = false;
                                }
                            };
                            posTimer.Start();
                        }
                    }
                }
                else if (parts[1] == "SetPosition" && ctrl is UIElement)
                {
                    var coords = parts[2].Split(',');
                    if (coords.Length >= 2)
                    {
                        Canvas.SetLeft((UIElement)ctrl, double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture));
                        Canvas.SetTop((UIElement)ctrl, double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture));
                    }
                }
                else if (parts[1] == "IsOpen" && ctrl is System.Windows.Controls.ContextMenu)
                {
                    // 用最稳的 IsOpen 打开 ContextMenu（Placement=MousePoint）。仅对 MG_CM 打诊断日志：
                    // 挂一次性 Opened 事件，记录菜单实际左上角屏幕坐标，与右键点对比出真实偏移。
                    var cmm = (System.Windows.Controls.ContextMenu)ctrl;
                    bool open = parts.Length >= 3 && (parts[2] == "True" || parts[2] == "true" || parts[2] == "1");
                    if (open)
                        FixMenuDropAlignment(); // 确保向右弹（系统偏好可能已把该字段重置回 true）
                    if (open && parts[0] == "MG_CM")
                    {
                        System.Windows.RoutedEventHandler[] oh = new System.Windows.RoutedEventHandler[1];
                        oh[0] = (os, oe) =>
                        {
                            try
                            {
                                cmm.Opened -= oh[0];
                                var mp = cmm.PointToScreen(new Point(0, 0)); // 菜单左上角(设备像素)
                                LogDebug("[CtxMenu] menuTopLeft(dev)=(" + mp.X.ToString("F1") + "," + mp.Y.ToString("F1")
                                    + ")  rightClick(dev)=(" + _ctxMenuClickDevX.ToString("F1") + "," + _ctxMenuClickDevY.ToString("F1")
                                    + ")  delta=(" + (mp.X - _ctxMenuClickDevX).ToString("F1") + "," + (mp.Y - _ctxMenuClickDevY).ToString("F1") + ")");
                            }
                            catch (Exception ex) { LogDebug("[CtxMenu] opened-log err: " + ex.Message); }
                        };
                        cmm.Opened += oh[0];
                    }
                    // 拖线指令菜单：关闭时清掉 Pending 临时连线（AHK 重开时可 SuppressTempClear）
                    if (parts[0] == "MG_DropCM")
                    {
                        if (open)
                        {
                            System.Windows.RoutedEventHandler[] ch = new System.Windows.RoutedEventHandler[1];
                            ch[0] = (cs, ce) =>
                            {
                                try { cmm.Closed -= ch[0]; } catch { }
                                if (suppressTempClearOnMenuClosed)
                                    return;
                                if (connectionDragPhase == ConnDragPendingMenu)
                                    CancelConnectionDrag(connectionDragCanvas, true);
                            };
                            try { cmm.Closed -= ch[0]; } catch { }
                            cmm.Closed += ch[0];
                            // 打开成功后解除抑制（若先关后开，Closed 已在抑制期跳过）
                            suppressTempClearOnMenuClosed = false;
                        }
                        else if (suppressTempClearOnMenuClosed)
                        {
                            // 仅关闭以重开：不挂清理
                        }
                    }
                    cmm.IsOpen = open;
                }
                else if (parts[1] == "SetCanvasMode" && ctrl is Canvas)
                {
                    canvasModes[parts[0]] = parts[2];
                }
                else if (parts[1] == "EnableZoomPan" && ctrl is Canvas)
                {
                    EnableCanvasZoomPan((Canvas)ctrl);
                }
                else if (parts[1] == "GetPasteMouse" && ctrl is Canvas)
                {
                    // AHK Ctrl+V 请求：与拖线同源 Mouse.GetPosition，回发 PasteAt
                    SendPasteAtFromCanvas((Canvas)ctrl);
                }
                else if (parts[1] == "ScreenToCanvas" && ctrl is Canvas && parts.Length >= 3)
                {
                    // AHK: MouseGetPos Screen → "sx,sy" → 画布坐标 → PasteAt
                    try
                    {
                        var sp = parts[2].Split(',');
                        if (sp.Length >= 2)
                        {
                            double sx = double.Parse(sp[0].Trim(), System.Globalization.CultureInfo.InvariantCulture);
                            double sy = double.Parse(sp[1].Trim(), System.Globalization.CultureInfo.InvariantCulture);
                            SendPasteAtFromCanvas((Canvas)ctrl, new Point(sx, sy));
                        }
                    }
                    catch { }
                }
                else if (parts[1] == "ZoomAll" && ctrl is Canvas)
                {
                    ZoomAllCanvas((Canvas)ctrl);
                }
                else if (parts[1] == "Zoom" && ctrl is Canvas)
                {
                    ZoomCanvas((Canvas)ctrl, double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture));
                }
                else if (parts[1] == "EnableDrag" && ctrl is FrameworkElement)
                {
                    EnableCanvasDrag((FrameworkElement)ctrl, parts[0], parts.Length > 2 ? parts[2] : "");
                }
                else if (parts[1] == "BeginStoryboard" && ctrl is FrameworkElement)
                {
                    var sb = ((FrameworkElement)ctrl).FindResource(parts[2]) as System.Windows.Media.Animation.Storyboard;
                    if (sb != null) sb.Begin((FrameworkElement)ctrl);
                }
                else if (parts[1] == "EnableListBoxDragDrop" && ctrl is ListBox)
                {
                    EnableListBoxDragDrop((ListBox)ctrl, parts[0]);
                }
                else if (parts[1] == "EnableListBoxDragSource" && ctrl is ListBox)
                {
                    string dragFormat = parts.Length > 2 ? parts[2] : "ListBoxItem";
                    EnableListBoxDragSource((ListBox)ctrl, parts[0], dragFormat);
                }
                else if (parts[1] == "EnableDragSource" && ctrl is UIElement)
                {
                    string dragFormat = parts.Length > 2 ? parts[2] : "DragItem";
                    EnableGenericDragSource((UIElement)ctrl, parts[0], dragFormat);
                }
                else if (parts[1] == "EnableDropTarget" && ctrl is UIElement)
                {
                    string dropFormat = parts.Length > 2 ? parts[2] : "DragItem";
                    EnableGenericDropTarget((UIElement)ctrl, parts[0], dropFormat);
                }
                else if (parts[1] == "Close" && ctrl is Window)
                {
                    var ownerHwnd = new System.Windows.Interop.WindowInteropHelper((Window)ctrl).Owner;
                    if (ownerHwnd != IntPtr.Zero)
                    {
                        SetForegroundWindow(ownerHwnd);
                    }
                    win.Dispatcher.BeginInvoke(new Action(() => ((Window)ctrl).Close()));
                }
                else if (parts[1] == "AppendText" && ctrl is System.Windows.Controls.TextBox)
                {
                    var tb = (System.Windows.Controls.TextBox)ctrl;
                    tb.AppendText(parts[2]);
                    tb.ScrollToEnd();
                }
                else if (parts[1] == "ScrollToEnd")
                {
                    if (ctrl is System.Windows.Controls.TextBox)
                        ((System.Windows.Controls.TextBox)ctrl).ScrollToEnd();
                    else if (ctrl is System.Windows.Controls.ScrollViewer)
                        ((System.Windows.Controls.ScrollViewer)ctrl).ScrollToEnd();
                }
                else if (parts[1] == "ScrollToLine" && ctrl is System.Windows.Controls.TextBox)
                {
                    int ln;
                    if (int.TryParse(parts[2], out ln))
                        ((System.Windows.Controls.TextBox)ctrl).ScrollToLine(ln);
                }
                else if (parts[1] == "LineUp")
                {
                    if (ctrl is System.Windows.Controls.TextBox)
                        ((System.Windows.Controls.TextBox)ctrl).LineUp();
                    else if (ctrl is System.Windows.Controls.ScrollViewer)
                        ((System.Windows.Controls.ScrollViewer)ctrl).LineUp();
                }
                else if (parts[1] == "LineDown")
                {
                    if (ctrl is System.Windows.Controls.TextBox)
                        ((System.Windows.Controls.TextBox)ctrl).LineDown();
                    else if (ctrl is System.Windows.Controls.ScrollViewer)
                        ((System.Windows.Controls.ScrollViewer)ctrl).LineDown();
                }
                else if (parts[1] == "InsertText" && ctrl is System.Windows.Controls.TextBox)
                {
                    var tb = (System.Windows.Controls.TextBox)ctrl;
                    int idx = tb.CaretIndex;
                    string pre = tb.Text.Substring(0, idx);
                    string post = tb.Text.Substring(idx);
                    tb.Text = pre + parts[2] + post;
                    tb.CaretIndex = idx + parts[2].Length;
                }
                else if (parts[1] == "NativeOwner" && ctrl is Window)
                {
                    new System.Windows.Interop.WindowInteropHelper((Window)ctrl).Owner = new IntPtr(long.Parse(parts[2]));
                    InheritWindowIconAndTitle((Window)ctrl, parts[2]);
                }
                else if (parts[1] == "Focus" && ctrl is UIElement)
                {
                    if (parts[2].ToLower() == "true" || parts[2] == "1") ((UIElement)ctrl).Focus();
                    else System.Windows.Input.Keyboard.ClearFocus();
                }
                else if (parts[1] == "BringIntoView" && ctrl is FrameworkElement)
                {
                    ((FrameworkElement)ctrl).BringIntoView();
                }
                else if (parts[1] == "Invoke" && ctrl is System.Windows.Controls.Primitives.ButtonBase)
                {
                    if (ctrl is System.Windows.Controls.Primitives.ToggleButton)
                    {
                        var tPeer = new System.Windows.Automation.Peers.ToggleButtonAutomationPeer((System.Windows.Controls.Primitives.ToggleButton)ctrl);
                        var toggleProv = tPeer.GetPattern(System.Windows.Automation.Peers.PatternInterface.Toggle) as System.Windows.Automation.Provider.IToggleProvider;
                        if (toggleProv != null) toggleProv.Toggle();
                    }
                    else if (ctrl is System.Windows.Controls.Button)
                    {
                        var peer = new System.Windows.Automation.Peers.ButtonAutomationPeer((System.Windows.Controls.Button)ctrl);
                        var invokeProv = peer.GetPattern(System.Windows.Automation.Peers.PatternInterface.Invoke) as System.Windows.Automation.Provider.IInvokeProvider;
                        if (invokeProv != null) invokeProv.Invoke();
                    }
                }
                else if (parts[1] == "TrapScroll" && ctrl is ScrollViewer)
                {
                    var sv = (ScrollViewer)ctrl;
                    System.Windows.Input.MouseWheelEventHandler handler = (s, e) =>
                    {
                        sv.ScrollToVerticalOffset(sv.VerticalOffset - e.Delta / 3.0);
                        e.Handled = true;
                    };
                    sv.PreviewMouseWheel -= handler;
                    sv.PreviewMouseWheel += handler;
                    sv.MouseWheel -= handler;
                    sv.MouseWheel += handler;
                }
                else if (parts[1].StartsWith("Effect.") && ctrl is UIElement)
                {
                    // Navigate through the Effect property to set sub-properties on ShaderEffect objects.
                    // e.g. "MyBorder|Effect.BlurRadius|0.5" => get MyBorder.Effect, then set .BlurRadius = 0.5
                    var effect = ((UIElement)ctrl).Effect;
                    string debugPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ahk_effect_debug.log");
                    try { System.IO.File.AppendAllText(debugPath, DateTime.Now.ToString("HH:mm:ss.fff") + " ctrl=" + parts[0] + " type=" + ctrl.GetType().Name + " effect=" + (effect != null ? effect.GetType().FullName : "NULL") + " prop=" + parts[1] + " val=" + parts[2] + "\n"); } catch { }
                    if (effect != null)
                    {
                        string subPropName = parts[1].Substring(7); // strip "Effect."
                        var subProp = effect.GetType().GetProperty(subPropName);
                        if (subProp != null)
                        {
                            object val = null;
                            string pt = subProp.PropertyType.Name;
                            if (pt == "Brush") val = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                            else if (pt == "Color") val = System.Windows.Media.ColorConverter.ConvertFromString(parts[2]);
                            else if (pt == "Point")
                            {
                                string[] coords = parts[2].Split(',');
                                if (coords.Length == 2)
                                    val = new Point(double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture), double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture));
                                else
                                    val = System.Windows.Point.Parse(parts[2]);
                            }
                            else if (subProp.PropertyType.IsEnum) val = Enum.Parse(subProp.PropertyType, parts[2], true);
                            else if (pt == "Double") val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                            else if (pt == "Boolean") val = Convert.ToBoolean(parts[2]);
                            else val = Convert.ChangeType(parts[2], subProp.PropertyType);
                            subProp.SetValue(effect, val, null);
                        }
                        else
                        {
                            try { System.IO.File.AppendAllText(debugPath, "  -> Property '" + subPropName + "' NOT FOUND on " + effect.GetType().Name + "\n"); } catch { }
                        }
                    }
                }
                else
                {
                    var prop = ctrl.GetType().GetProperty(parts[1]);
                    if (prop != null)
                    {
                        object val = null;
                        string pt = prop.PropertyType.Name;
                        if (pt == "Brush") val = new System.Windows.Media.BrushConverter().ConvertFromString(parts[2]);
                        else if (pt == "Color") val = System.Windows.Media.ColorConverter.ConvertFromString(parts[2]);
                        else if (pt == "Point")
                        {
                            string[] coords = parts[2].Split(',');
                            if (coords.Length == 2)
                            {
                                val = new Point(
                                    double.Parse(coords[0], System.Globalization.CultureInfo.InvariantCulture),
                                    double.Parse(coords[1], System.Globalization.CultureInfo.InvariantCulture)
                                );
                            }
                            else
                            {
                                val = System.Windows.Point.Parse(parts[2]);
                            }
                        }
                        else if (prop.PropertyType.IsEnum) val = Enum.Parse(prop.PropertyType, parts[2], true);
                        else if (pt == "Double") val = double.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
                        else if (pt == "Boolean" || pt == "Nullable`1") val = Convert.ToBoolean(parts[2]);
                        else if (pt == "Thickness") val = new System.Windows.ThicknessConverter().ConvertFromString(parts[2]);
                        else if (pt == "CornerRadius") val = new System.Windows.CornerRadiusConverter().ConvertFromString(parts[2]);
                        else if (pt == "ImageSource")
                        {
                            if (parts[2].StartsWith("HICON:"))
                            {
                                IntPtr hIcon = new IntPtr(long.Parse(parts[2].Substring(6)));
                                val = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(hIcon, System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                            }
                            else if (parts[2].StartsWith("HBITMAP:"))
                            {
                                IntPtr hBmp = new IntPtr(long.Parse(parts[2].Substring(8)));
                                val = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(hBmp, IntPtr.Zero, System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                            }
                            else
                            {
                                val = new System.Windows.Media.ImageSourceConverter().ConvertFromString(parts[2]);
                            }
                        }
                        else if (pt == "GridLength") val = new System.Windows.GridLengthConverter().ConvertFromString(parts[2]);
                        else if (pt == "Object" || pt == "String") val = parts[2];
                        else if (pt == "Uri") val = new Uri(parts[2], UriKind.RelativeOrAbsolute);
                        else if (pt == "Rect") val = System.Windows.Rect.Parse(parts[2]);
                        else if (pt == "Geometry") val = System.Windows.Media.Geometry.Parse(parts[2]);
                        else val = Convert.ChangeType(parts[2], prop.PropertyType);
                        prop.SetValue(ctrl, val, null);
                        // 离屏隐藏窗口揭盖：先移回屏内（SetWindowPos 同步移动，避免 WPF 异步移动重置 LWA 露黑帧），
                        // 等首帧 present 完成（80ms）再清 LWA，显示完整内容。
                        if (ctrl == win && parts[1] == "Opacity" && win.Resources.Contains("_NativeAlphaPending"))
                        {
                            try
                            {
                                win.Resources.Remove("_NativeAlphaPending");
                                IntPtr wHwnd = new System.Windows.Interop.WindowInteropHelper(win).Handle;
                                if (wHwnd != IntPtr.Zero)
                                {
                                    win.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ContextIdle, new Action(() =>
                                    {
                                        try
                                        {
                                            // 窗口已关闭则放弃
                                            if (!win.IsLoaded || new System.Windows.Interop.WindowInteropHelper(win).Handle != wHwnd)
                                                return;
                                            // 第一步：移到屏内（保持 LWA 透明）；SetWindowPos 不触发 WPF 重排
                                            if (win.Resources.Contains("_RevealPos"))
                                            {
                                                try
                                                {
                                                    System.Windows.Point pos = (System.Windows.Point)win.Resources["_RevealPos"];
                                                    double scale = 1.0;
                                                    try { scale = GetDpiForSystem() / 96.0; } catch { }
                                                    SetWindowPos(wHwnd, IntPtr.Zero, (int)(pos.X * scale), (int)(pos.Y * scale), 0, 0, 0x0001 | 0x0004 | 0x0010); // SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
                                                }
                                                catch { }
                                            }
                                            // 补 LWA 防重置
                                            try { ApplyNativeAlphaZero(win); } catch { }
                                            // 屏内合成中设 backdrop=0 才真正生效（未显示过的窗口上可能被忽略）
                                            if (!win.AllowsTransparency)
                                            {
                                                try
                                                {
                                                    int noBackdrop = 0;
                                                    int darkMode = 0;
                                                    DwmSetWindowAttribute(wHwnd, 20, ref darkMode, 4);
                                                    DwmSetWindowAttribute(wHwnd, 38, ref noBackdrop, 4);
                                                }
                                                catch { }
                                            }
                                            // 第二步：等首帧 present 完成再清 LWA
                                            var presentTimer = new System.Windows.Threading.DispatcherTimer();
                                            presentTimer.Interval = TimeSpan.FromMilliseconds(80);
                                            presentTimer.Tick += (s2, e2) =>
                                            {
                                                presentTimer.Stop();
                                                try
                                                {
                                                    if (!win.IsLoaded || new System.Windows.Interop.WindowInteropHelper(win).Handle != wHwnd)
                                                        return;
                                                    RevealNativeWindow(win, wHwnd);
                                                    // 揭盖完成通知 AHK 激活窗口
                                                    try { SendToAhkAsync("EVENT|" + winId + "|Window|Revealed\n"); } catch { }
                                                }
                                                catch { }
                                            };
                                            presentTimer.Start();
                                        }
                                        catch { }
                                    }));
                                }
                            }
                            catch { }
                        }
                        // AHK 收起临时拖线时同步复位拖线状态机
                        if (parts[1] == "Visibility" && ctrl == tempConnection && val is Visibility
                            && (Visibility)val == Visibility.Collapsed)
                        {
                            connectionSourcePort = null;
                            connectionDragCanvas = null;
                            connectionDragPhase = ConnDragIdle;
                        }
                    }
                }
            }
        }
    }

    // 揭盖：窗口创建时被移到屏外（见 PrepareDeferredReveal），AHK 置 Opacity=1 时还原位置并清 LWA 显示
    private static void RevealNativeWindow(Window win, IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero)
            return;
        // 清 LWA 前先关 DWM backdrop（Acrylic 会让首帧闪系统玻璃紫；此处窗口即将可见才生效）
        if (!win.AllowsTransparency)
        {
            try
            {
                int noBackdrop = 0; // DWMSBT_NONE
                int darkMode = 0;
                DwmSetWindowAttribute(hwnd, 20, ref darkMode, 4);
                DwmSetWindowAttribute(hwnd, 38, ref noBackdrop, 4);
            }
            catch { }
        }
        // 位置已在第一步由 SetWindowPos 设好，此处不用 win.Left/Top（透明状态下 WPF 移动会重置 LWA）
        SetLayeredWindowAttributes(hwnd, 0, 255, 0x2);      // LWA_ALPHA=255，兜底
        int ex = GetWindowLong(hwnd, -20);
        SetWindowLong(hwnd, -20, new IntPtr(ex & ~0x80000)); // 去掉 WS_EX_LAYERED，恢复正常窗口（保留阴影）
        ShowWindow(hwnd, 5);                                 // SW_SHOW，兜底
    }

}
