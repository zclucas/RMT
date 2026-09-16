// =============================================================================
// Native interop: P/Invoke, structs, taskbar COM
// =============================================================================
using System;
using System.Collections.Generic;
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

public partial class AhkWpfEngine
{
    [StructLayout(LayoutKind.Sequential)]
    public struct COPYDATASTRUCT
    {
        public IntPtr dwData; public int cbData; public IntPtr lpData;
    }
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, ref COPYDATASTRUCT lParam);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);
    [DllImport("user32.dll")]
    public static extern IntPtr SetCursor(IntPtr hCursor);
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [DllImport("user32.dll")]
    public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS
    {
        public int leftWidth;
        public int rightWidth;
        public int topHeight;
        public int bottomHeight;
        public MARGINS(int left, int right, int top, int bottom)
        {
            leftWidth = left; rightWidth = right; topHeight = top; bottomHeight = bottom;
        }
    }
    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    public static int GetWindowLong(IntPtr hWnd, int nIndex)
    {
        if (IntPtr.Size == 4) return GetWindowLong32(hWnd, nIndex);
        return (int)(long)GetWindowLongPtr64(hWnd, nIndex);
    }
    public static IntPtr SetWindowLong(IntPtr hWnd, int nIndex, IntPtr dwNewLong)
    {
        if (IntPtr.Size == 4) return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
        return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
    }

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")]
    public static extern uint GetPixel(IntPtr hdc, int x, int y);
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);
    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(IntPtr hdcDest, int x, int y, int w, int h, IntPtr hdcSrc, int x1, int y1, uint rop);
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFO pbmi, uint usage, out IntPtr ppvBits, IntPtr hSection, uint offset);
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();


    private static ITaskbarList _taskbarList = null;
    public static void SetTaskbarPresence(IntPtr hwnd, bool show)
    {
        try
        {
            if (_taskbarList == null)
            {
                _taskbarList = (ITaskbarList)new TaskbarList();
                _taskbarList.HrInit();
            }
            if (show)
            {
                _taskbarList.AddTab(hwnd);
            }
            else
            {
                _taskbarList.DeleteTab(hwnd);
            }
        }
        catch { }
    }

    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    [StructLayout(LayoutKind.Sequential)]
    public struct MINMAXINFO { public POINT ptReserved; public POINT ptMaxSize; public POINT ptMaxPosition; public POINT ptMinTrackSize; public POINT ptMaxTrackSize; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth;
        public int biHeight;   // 负值 = 顶向下（(0,0) 左上）
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        public uint bmiColors;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int left, top, right, bottom; }
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr handle, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll", EntryPoint = "SendMessage", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "GetClassLong")]
    public static extern uint GetClassLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "GetClassLongPtr")]
    public static extern IntPtr GetClassLongPtr64(IntPtr hWnd, int nIndex);

    public static IntPtr GetClassLongPtr(IntPtr hWnd, int nIndex)
    {
        if (IntPtr.Size == 4) return new IntPtr(GetClassLong32(hWnd, nIndex));
        return GetClassLongPtr64(hWnd, nIndex);
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern uint ExtractIconEx(string szFileName, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")]
    private static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    public static void EnableDpiAwareness()
    {
        try
        {
            if (SetProcessDpiAwarenessContext(new IntPtr(-4)))
                return;
        }
        catch { }
        try
        {
            SetProcessDpiAwareness(2);
            return;
        }
        catch { }
        try
        {
            SetProcessDPIAware();
        }
        catch { }
    }

}

[ComImport]
[Guid("56FDF342-FD6D-11d0-958A-006097C9A090")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITaskbarList
{
    void HrInit();
    void AddTab(IntPtr hwnd);
    void DeleteTab(IntPtr hwnd);
    void ActivateTab(IntPtr hwnd);
    void SetActiveAlt(IntPtr hwnd);
}

[ComImport]
[Guid("56FDF344-FD6D-11d0-958A-006097C9A090")]
public class TaskbarList
{
}

[ComImport]
[Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITaskbarList3
{
    void HrInit();
    void AddTab(IntPtr hwnd);
    void DeleteTab(IntPtr hwnd);
    void ActivateTab(IntPtr hwnd);
    void SetActiveAlt(IntPtr hwnd);
    void MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fullscreen);
    void SetProgressValue(IntPtr hwnd, ulong completed, ulong total);
    void SetProgressState(IntPtr hwnd, int flags);
    void RegisterTab(IntPtr hwndTab, IntPtr hwndMdi);
    void UnregisterTab(IntPtr hwndTab);
    void SetTabOrder(IntPtr hwndTab, IntPtr hwndInsertBefore);
    void SetTabActive(IntPtr hwndTab, IntPtr hwndMdi, uint reserved);
    void ThumbBarAddButtons(IntPtr hwnd, uint count, IntPtr buttons);
    void ThumbBarUpdateButtons(IntPtr hwnd, uint count, IntPtr buttons);
    void ThumbBarSetImageList(IntPtr hwnd, IntPtr imageList);
    void SetOverlayIcon(IntPtr hwnd, IntPtr icon, [MarshalAs(UnmanagedType.LPWStr)] string description);
    void SetThumbnailTooltip(IntPtr hwnd, [MarshalAs(UnmanagedType.LPWStr)] string tip);
    void SetThumbnailClip(IntPtr hwnd, IntPtr clip);
}

internal static class RmtTaskbarGroup
{
    // 总开关：禁用“对话框折叠成主窗口标签页”的行为。
    // 折叠会导致子窗口没有自己的任务栏按钮、Alt+Tab 不列出（RMT 主程序要求独立窗口）。
    // 恢复原行为改回 false 即可。
    private static readonly bool disabled = true;

    private static ITaskbarList3 list;
    private static bool hooked;
    private static IntPtr hubHwnd;
    private static readonly Dictionary<IntPtr, Window> tabs = new Dictionary<IntPtr, Window>();

    public static void EnsureHooked()
    {
        if (disabled) return;
        if (hooked) return;
        hooked = true;
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent, new RoutedEventHandler(OnWindowLoaded), true);
    }

    public static void Refresh()
    {
        if (disabled) return;
        try { RefreshCore(); }
        catch { }
    }

    private static ITaskbarList3 List()
    {
        if (list == null)
        {
            list = (ITaskbarList3)new TaskbarList();
            list.HrInit();
        }
        return list;
    }

    private static void OnWindowLoaded(object sender, RoutedEventArgs args)
    {
        var window = sender as Window;
        if (window == null) return;
        window.Activated -= OnWindowActivated;
        window.Activated += OnWindowActivated;
        window.Closed -= OnWindowClosed;
        window.Closed += OnWindowClosed;
        window.IsVisibleChanged -= OnWindowVisibleChanged;
        window.IsVisibleChanged += OnWindowVisibleChanged;
        Refresh();
    }

    private static void OnWindowActivated(object sender, EventArgs args)
    {
        var window = sender as Window;
        if (window == null || hubHwnd == IntPtr.Zero) return;
        IntPtr hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero || hwnd == hubHwnd || !tabs.ContainsKey(hwnd)) return;
        try { List().SetTabActive(hwnd, hubHwnd, 0); }
        catch { }
    }

    private static void OnWindowClosed(object sender, EventArgs args)
    {
        Refresh();
    }

    private static void OnWindowVisibleChanged(object sender, DependencyPropertyChangedEventArgs args)
    {
        Refresh();
    }

    private static void RefreshCore()
    {
        if (Application.Current == null) return;
        Window[] windows = Application.Current.Windows.Cast<Window>().ToArray();
        Window hub = FindHub(windows);
        if (hub == null) return;
        IntPtr nextHub = new WindowInteropHelper(hub).Handle;
        if (nextHub == IntPtr.Zero) return;
        if (nextHub != hubHwnd && hubHwnd != IntPtr.Zero)
        {
            foreach (IntPtr old in tabs.Keys.ToArray()) Unregister(old);
            tabs.Clear();
        }
        hubHwnd = nextHub;

        var wanted = new HashSet<IntPtr>();
        foreach (Window window in windows)
        {
            if (window == null || ReferenceEquals(window, hub) || !IsGroupWindow(window)) continue;
            IntPtr hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) continue;
            wanted.Add(hwnd);
            if (!tabs.ContainsKey(hwnd)) Register(hwnd, window);
            else UpdateTooltip(hwnd, window);
        }
        foreach (IntPtr old in tabs.Keys.ToArray())
        {
            if (wanted.Contains(old)) continue;
            Unregister(old);
            tabs.Remove(old);
        }
    }

    private static Window FindHub(Window[] windows)
    {
        foreach (Window window in windows)
        {
            if (window != null && window.ShowInTaskbar && IsGroupWindow(window)) return window;
        }
        Window main = Application.Current != null ? Application.Current.MainWindow : null;
        if (main != null && IsGroupWindow(main)) return main;
        return null;
    }

    internal static bool IsGroupWindow(Window window)
    {
        if (window == null || !window.IsVisible) return false;
        if (window.Resources.Contains("_NativeAlphaPending")) return false;
        double width = window.ActualWidth > 1 ? window.ActualWidth : window.Width;
        double height = window.ActualHeight > 1 ? window.ActualHeight : window.Height;
        if (width > 0 && width < 180) return false;
        if (height > 0 && height < 140) return false;
        string title = window.Title ?? "";
        if (title == "CMDTip" || title == "RMT-Target" || title.StartsWith("Developer Tools")) return false;
        if (window.WindowStyle == WindowStyle.None && window.AllowsTransparency && width < 8) return false;
        return true;
    }

    private static void Register(IntPtr hwnd, Window window)
    {
        ITaskbarList3 bar = List();
        bar.DeleteTab(hwnd);
        int ex = AhkWpfEngine.GetWindowLong(hwnd, -20);
        if ((ex & 0x80) != 0)
            AhkWpfEngine.SetWindowLong(hwnd, -20, new IntPtr(ex & ~0x80));
        bar.RegisterTab(hwnd, hubHwnd);
        bar.SetTabOrder(hwnd, IntPtr.Zero);
        UpdateTooltip(hwnd, window);
        tabs[hwnd] = window;
    }

    private static void Unregister(IntPtr hwnd)
    {
        try { List().UnregisterTab(hwnd); }
        catch { }
    }

    private static void UpdateTooltip(IntPtr hwnd, Window window)
    {
        string tip = window == null || string.IsNullOrEmpty(window.Title) ? "若梦兔" : window.Title;
        try { List().SetThumbnailTooltip(hwnd, tip); }
        catch { }
    }
}

