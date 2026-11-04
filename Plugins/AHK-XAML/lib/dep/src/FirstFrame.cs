// Keep the native window out of composition until AHK initialization and WPF rendering finish.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

internal sealed class RmtFirstFrame
{
    static readonly HashSet<Window> Pending = new HashSet<Window>();
    readonly Window window;
    readonly IntPtr hwnd;
    readonly bool startHidden;
    bool initialized, rendered, queued, finished, cloaked, layered, opacityFallback;
    int originalExStyle;
    double originalOpacity;

    public static bool IsPending(Window window) { return Pending.Contains(window); }

    public RmtFirstFrame(Window window, bool waitForInitialization, bool startHidden)
    {
        this.window = window;
        this.startHidden = startHidden;
        initialized = !waitForInitialization;
        // EnsureHandle creates HWND without showing it. Taskbar styles must also be set now.
        hwnd = new WindowInteropHelper(window).EnsureHandle();
        Pending.Add(window);
        window.ContentRendered += OnContentRendered;
        window.Closed += OnClosed;
        var source = HwndSource.FromHwnd(hwnd);
        var background = window.Background as SolidColorBrush;
        if (!window.AllowsTransparency && source != null && source.CompositionTarget != null && background != null)
            source.CompositionTarget.BackgroundColor = background.Color;
        try
        {
            int cloak = 1; // DWMWA_CLOAK: continue rendering, but do not present the unfinished HWND.
            cloaked = AhkWpfEngine.DwmSetWindowAttribute(hwnd, 13, ref cloak, 4) == 0;
        }
        catch { }
        if (!cloaked)
        {
            // Windows 7 has no DWMWA_CLOAK. Keep opaque HWNDs transparent at the native layer.
            if (!window.AllowsTransparency)
            {
                originalExStyle = AhkWpfEngine.GetWindowLong(hwnd, -20);
                AhkWpfEngine.SetWindowLong(hwnd, -20, new IntPtr(originalExStyle | 0x80000));
                layered = AhkWpfEngine.SetLayeredWindowAttributes(hwnd, 0, 0, 2);
                if (!layered)
                    AhkWpfEngine.SetWindowLong(hwnd, -20, new IntPtr(originalExStyle));
            }
            if (!layered)
            {
                originalOpacity = window.Opacity;
                window.Opacity = 0;
                opacityFallback = true;
            }
        }
    }

    public void CompleteInitialization()
    {
        initialized = true;
        QueueReveal();
    }

    void OnContentRendered(object sender, EventArgs args)
    {
        rendered = true;
        QueueReveal();
    }

    void QueueReveal()
    {
        if (finished || queued || !initialized || !rendered) return;
        queued = true;
        if (opacityFallback) window.Opacity = originalOpacity;
        // Initialization may invalidate layout after ContentRendered. Wait for that render too.
        CompositionTarget.Rendering += OnRendering;
        window.InvalidateVisual();
    }

    void OnRendering(object sender, EventArgs args)
    {
        CompositionTarget.Rendering -= OnRendering;
        window.Dispatcher.BeginInvoke(new Action(Reveal), DispatcherPriority.ContextIdle);
    }

    void Reveal()
    {
        if (finished) return;
        // For -min, hide the HWND before lifting the cover; WPF Visibility stays Visible.
        if (startHidden) AhkWpfEngine.ShowWindow(hwnd, 0);
        if (cloaked)
        {
            int cloak = 0;
            AhkWpfEngine.DwmSetWindowAttribute(hwnd, 13, ref cloak, 4);
        }
        if (layered)
        {
            AhkWpfEngine.SetLayeredWindowAttributes(hwnd, 0, 255, 2);
            // Preserve taskbar/owner styles installed after EnsureHandle.
            if ((originalExStyle & 0x80000) == 0)
            {
                int ex = AhkWpfEngine.GetWindowLong(hwnd, -20);
                AhkWpfEngine.SetWindowLong(hwnd, -20, new IntPtr(ex & ~0x80000));
            }
        }
        Finish();
        RmtWindowFrame.Sync(window);
    }

    void OnClosed(object sender, EventArgs args) { Finish(); }

    void Finish()
    {
        finished = true;
        Pending.Remove(window);
        CompositionTarget.Rendering -= OnRendering;
        window.ContentRendered -= OnContentRendered;
        window.Closed -= OnClosed;
    }
}
