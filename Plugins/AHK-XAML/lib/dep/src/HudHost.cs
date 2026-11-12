// =============================================================================
// HUD：「输出 → 悬浮显示」的窗口侧实现
//
// 职责划分
//   AHK 侧提供数据（文本）与配置（位置模式/锚点/坐标/最大宽度）；
//   布局、尺寸、定位、跟随目标窗口与拖动由本文件实现。
//
// 布局置于引擎侧的原因
//   XAMLHost.Update 为 SendMessage 同步调用，AHK 侧获取尺寸/位置须等待 WPF 布局
//   完成，多悬浮窗时串行累加。此处文本更新经 BeginInvoke 合并后 WndProc 立即返回；
//   尺寸由 SizeToContent 计算，锚点在 SizeChanged 中重算，AHK 不参与布局。
//
// 指令（AHK → 引擎，复用 XAMLHost.Update 的 IPC）
//   HUD|Bind|mode;anchor;x;y;targetHwnd;maxWidth;shmName    创建或更新配置
//        mode 0 固定于 x,y（DIP）  1 整屏锚点  2 跟随 targetHwnd
//   HUD|Text|<文本>                                         异步合并更新文本
//
// 事件（引擎 → AHK）
//   EVENT|<winId>|Window|HudMoved|<x>,<y>                   拖动结束，坐标单位 DIP
// =============================================================================
using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

public partial class AhkWpfEngine
{
    private sealed class HudInfo
    {
        public TextBlock Text;
        public FrameworkElement Area;
        public int Mode;                       // 0 固定坐标  1 整屏  2 跟随窗口
        public int Anchor = 6;                 // 0 左上 … 8 右下
        public double X, Y;                    // Mode=0 时的绝对坐标（DIP）
        public double OffX, OffY;              // Mode=1/2 时的锚点偏移（DIP）
        public IntPtr Target = IntPtr.Zero;
        public double MaxWidth = 420;
        public bool UserMoved;                 // 用户已拖动：不再自动定位
        public bool TextQueued;
        public string PendingText;
        public bool ReposQueued;
        public bool Positioned;                // 已成功定位过；首帧前允许回退到整屏
        public bool SizeMode;                  // 已切换为宽度固定、高度自适应
        public double LastLeft, LastTop;       // 最近一次由引擎设定的位置
        public IntPtr SharedPtr;               // 文本槽视图：AHK 写入，此处读取
    }

    private HudInfo _hud;
    private IntPtr _hudHook;
    private HudHookProc _hudHookProc;

    private delegate void HudHookProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        HudHookProc lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    private static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll", EntryPoint = "IsIconic")]
    private static extern bool HudIsIconic(IntPtr hWnd);

    // 可见边框（不含 Win10/11 的隐形调整边）；失败时回退 GetWindowRect
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int HudDwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);

    private const uint HUD_EVENT_LOCATIONCHANGE = 0x800B;

    // ---- 共享内存文本通道 ----
    // AHK 写入映射区后以 PostMessage 唤醒本窗口；此处只读不阻塞，
    // AHK 侧无需等待 SendMessage 回执，多窗口时开销不线性累加。
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr OpenFileMappingW(uint dwDesiredAccess, bool bInheritHandle, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr MapViewOfFile(IntPtr hFileMappingObject, uint dwDesiredAccess,
        uint dwFileOffsetHigh, uint dwFileOffsetLow, UIntPtr dwNumberOfBytesToMap);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UnmapViewOfFile(IntPtr lpBaseAddress);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessageW(string lpString);

    private const uint HUD_FILE_MAP_READ = 0x0004;

    private static uint _wmHudText = 0;

    // 双方以同一注册名获取同一消息 ID
    private static uint WmHudText
    {
        get
        {
            if (_wmHudText == 0)
                _wmHudText = RegisterWindowMessageW("RMT_HUD_TEXT");
            return _wmHudText;
        }
    }

    // ---------------------------------------------------------------
    // 指令入口
    // ---------------------------------------------------------------
    private void HudProcess(string op, string value)
    {
        if (op == "Bind")
        {
            HudBind(value);
            return;
        }
        if (op == "Text")
        {
            HudSetText(value);
            return;
        }
        if (op == "Detach")
        {
            HudUnhook();
            _hud = null;
            return;
        }
    }

    // ---------------------------------------------------------------
    // 配置：mode;anchor;x;y;targetHwnd;maxWidth;shmName
    // ---------------------------------------------------------------
    private void HudBind(string value)
    {
        HudInfo info = HudEnsure();
        if (info == null)
            return;

        int mode = 2, anchor = 6;
        double x = 0, y = 0, maxw = 420;
        IntPtr target = IntPtr.Zero;
        string shmName = "";

        try
        {
            string[] p = (value == null ? "" : value).Split(';');
            if (p.Length > 0) int.TryParse(p[0], out mode);
            if (p.Length > 1) int.TryParse(p[1], out anchor);
            if (p.Length > 2) HudParseDouble(p[2], out x);
            if (p.Length > 3) HudParseDouble(p[3], out y);
            if (p.Length > 4 && p[4].Length > 0)
            {
                long h = 0;
                if (long.TryParse(p[4], NumberStyles.Integer, CultureInfo.InvariantCulture, out h))
                    target = new IntPtr(h);
            }
            if (p.Length > 5) HudParseDouble(p[5], out maxw);
            if (p.Length > 6) shmName = p[6];
        }
        catch { }

        HudAttachShared(info, shmName);

        if (mode < 0 || mode > 2) mode = 2;
        if (anchor < 0 || anchor > 8) anchor = 6;
        if (maxw < 80) maxw = 80;
        if (maxw > 2000) maxw = 2000;

        info.Mode = mode;
        info.Anchor = anchor;
        info.X = x;
        info.Y = y;
        info.OffX = (mode == 0) ? 0 : x;
        info.OffY = (mode == 0) ? 0 : y;
        info.Target = target;
        info.MaxWidth = maxw;
        info.UserMoved = false;
        info.Positioned = false;

        if (info.Text != null)
        {
            try { info.Text.MaxWidth = maxw; } catch { }
        }

        HudHook(info);

        if (mode == 0)
        {
            try
            {
                win.Left = x;
                win.Top = y;
                info.LastLeft = x;
                info.LastTop = y;
                info.Positioned = true;
            }
            catch { }
        }
        else
        {
            // 首次定位允许回退到整屏：宏启动时目标窗口可能尚不可枚举
            HudReposition(info, true);
        }
    }

    private static void HudParseDouble(string s, out double v)
    {
        v = 0;
        if (s == null)
            return;
        double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v);
    }

    // ---------------------------------------------------------------
    // 文本：异步合并，同一帧内多次调用仅最后一次生效
    // ---------------------------------------------------------------
    private void HudSetText(string text)
    {
        HudInfo info = HudEnsure();
        if (info == null || info.Text == null)
            return;

        info.PendingText = (text == null) ? "" : text;
        if (info.TextQueued)
            return;
        info.TextQueued = true;

        try
        {
            // 使用 Normal 而非 Background：Background 排在渲染之后，窗口繁忙时更新
            // 会被延后，表现为显示偶发跳变。Normal 在渲染前执行。
            win.Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(delegate()
            {
                info.TextQueued = false;
                if (info.Text == null)
                    return;
                string t = info.PendingText;
                if (t == null)
                    return;
                try
                {
                    if (!object.Equals(info.Text.Text, t))
                        info.Text.Text = t;
                    HudUpdateWidth(info, t);
                }
                catch { }
            }));
        }
        catch
        {
            info.TextQueued = false;
        }
    }

    // ---------------------------------------------------------------
    // 共享内存：挂接 / 读取 / 清理
    // 槽格式：+0 = 字节数(UInt32)，+4 = UTF-8 文本
    // ---------------------------------------------------------------
    private void HudAttachShared(HudInfo info, string name)
    {
        HudDetachShared(info);
        if (info == null || string.IsNullOrEmpty(name))
            return;
        try
        {
            IntPtr h = OpenFileMappingW(HUD_FILE_MAP_READ, false, name);
            if (h == IntPtr.Zero)
                return;
            IntPtr p = MapViewOfFile(h, HUD_FILE_MAP_READ, 0, 0, UIntPtr.Zero);
            CloseHandle(h);
            if (p != IntPtr.Zero)
                info.SharedPtr = p;
        }
        catch { }
    }

    private static void HudDetachShared(HudInfo info)
    {
        if (info == null || info.SharedPtr == IntPtr.Zero)
            return;
        try { UnmapViewOfFile(info.SharedPtr); } catch { }
        info.SharedPtr = IntPtr.Zero;
    }

    private string HudReadSharedText()
    {
        HudInfo info = _hud;
        if (info == null || info.SharedPtr == IntPtr.Zero)
            return null;
        try
        {
            int len = Marshal.ReadInt32(info.SharedPtr, 0);
            if (len <= 0 || len > 65000)
                return null;
            byte[] buf = new byte[len];
            Marshal.Copy(new IntPtr(info.SharedPtr.ToInt64() + 4), buf, 0, len);
            return Encoding.UTF8.GetString(buf);
        }
        catch { return null; }
    }

    // 唤醒消息处理：读取一帧，经 BeginInvoke 合并路径更新
    private void HudRefreshFromShared()
    {
        string t = HudReadSharedText();
        if (t != null)
            HudSetText(t);
    }

    // ---------------------------------------------------------------
    // 通用异步更新通道（非 HUD 窗口使用）
    //
    // 指令流水等每秒数十次的更新若走 SendMessage，每次均须等待本进程处理完成，
    // 引擎繁忙时该等待会阻塞调用方主线程，并影响其定时任务（如悬浮窗刷新）。
    // 改为：AHK 写共享内存 → PostMessage 唤醒 → 本进程读取。
    // ---------------------------------------------------------------
    private IntPtr _asyncShared;

    private void XamlAttachAsync(string name)
    {
        if (_asyncShared != IntPtr.Zero)
        {
            try { UnmapViewOfFile(_asyncShared); } catch { }
            _asyncShared = IntPtr.Zero;
        }
        if (string.IsNullOrEmpty(name))
            return;
        try
        {
            IntPtr h = OpenFileMappingW(HUD_FILE_MAP_READ, false, name);
            if (h == IntPtr.Zero)
                return;
            IntPtr p = MapViewOfFile(h, HUD_FILE_MAP_READ, 0, 0, UIntPtr.Zero);
            CloseHandle(h);
            if (p == IntPtr.Zero)
                return;
            _asyncShared = p;
            // 握手：告知 AHK「本版引擎支持带序号与回执的槽格式」。
            // 旧版引擎不会回这条，AHK 侧据此继续走同步发送 —— 否则新格式写进旧解析器
            // 会从 +4 开始读，把序号当成正文，收到半截乱码指令。
            SendToAhkAsync("EVENT|" + winId + "|Window|AsyncReady|2\n");
        }
        catch { }
    }

    // 异步帧的形态：+0 长度 / +4 序号 / +8 正文。
    // 序号由 AHK 侧递增，处理完原样回传；AHK 只有收到回执才发下一帧，
    // 单槽因此不会出现「第二条覆盖第一条、第一条丢失」。
    private void XamlAsyncRefresh(IntPtr hwnd)
    {
        if (_asyncShared == IntPtr.Zero)
            return;
        int seq = 0;
        try
        {
            int len = Marshal.ReadInt32(_asyncShared, 0);
            seq = Marshal.ReadInt32(_asyncShared, 4);
            // 上限放宽至 4MB：主窗口首次填充会将数百条属性合并为一条（数十至数百 KB），
            // 65000 的限制会整条丢弃该批次，导致窗口停留在空壳状态。槽实际大小由 AHK 侧决定。
            if (len > 0 && len <= 4 * 1024 * 1024)
            {
                byte[] buf = new byte[len];
                Marshal.Copy(new IntPtr(_asyncShared.ToInt64() + 8), buf, 0, len);
                string payload = Encoding.UTF8.GetString(buf);
                if (payload.Length > 0)
                    ProcessMessage(hwnd, payload);
            }
        }
        catch { }
        XamlAckAsync(seq);
    }

    private void XamlAckAsync(int seq)
    {
        if (seq <= 0)
            return;
        try { SendToAhkAsync("EVENT|" + winId + "|Window|AsyncAck|" + seq.ToString() + "\n"); }
        catch { }
    }

    private void XamlDetachAsync()
    {
        if (_asyncShared == IntPtr.Zero)
            return;
        try { UnmapViewOfFile(_asyncShared); } catch { }
        _asyncShared = IntPtr.Zero;
    }

    // ---------------------------------------------------------------
    // 宽度：按文本量计算一次，满足需求后不再调整。
    //
    // 不能每帧依赖 SizeToContent 自适应：数值位数变化会同时改变宽高，WPF 每次均须
    // SetWindowPos 重建分层窗口（AllowsTransparency 窗口代价更高）。多窗口并发时
    // 每秒数百次尺寸变更会占满引擎 UI 线程。
    //
    // 现策略：高度交由 SizeToContent(Height)，单行高度恒定；宽度只增不减，
    // 避免数值在 9 与 10 之间反复抖动。
    // ---------------------------------------------------------------
    private void HudUpdateWidth(HudInfo info, string text)
    {
        if (info == null || info.Text == null || win == null)
            return;
        double need = HudMeasureTextWidth(info, text);
        if (need <= 0)
            return;

        // 38 = Border 左右 Padding 14*2 + 边框 1*2 + 余量 8
        double target = Math.Ceiling(need) + 38;
        double cap = info.MaxWidth + 40;
        if (target > cap) target = cap;
        if (target < 80) target = 80;

        double cur = win.Width;
        bool grow = double.IsNaN(cur) || target > cur + 2;
        if (!grow && info.SizeMode)
            return;

        try
        {
            win.SizeToContent = SizeToContent.Height;
            win.Width = grow ? target : cur;
            info.SizeMode = true;
        }
        catch { }
    }

    private double HudMeasureTextWidth(HudInfo info, string text)
    {
        if (text == null || info == null || info.Text == null)
            return 0;
        try
        {
            Typeface tf = new Typeface(info.Text.FontFamily, info.Text.FontStyle,
                info.Text.FontWeight, info.Text.FontStretch);
            double fs = info.Text.FontSize;
            if (double.IsNaN(fs) || fs <= 0)
                fs = 14;

            double max = 0;
            string[] lines = text.Replace("\r", "").Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                if (lines[i].Length == 0)
                    continue;
                // 6 参构造自 .NET 4.6.2 起标记为过时（推荐 PixelsPerDip 重载），
                // 但本工程按 .NET 4.0 参考程序集编译，该重载不存在，故沿用 6 参版本；
                // 此处仅测量文本宽度，不使用 PixelsPerDip。
#pragma warning disable 618
                FormattedText ft = new FormattedText(lines[i], CultureInfo.CurrentCulture,
                    FlowDirection.LeftToRight, tf, fs, Brushes.Black);
#pragma warning restore 618
                if (ft.WidthIncludingTrailingWhitespace > max)
                    max = ft.WidthIncludingTrailingWhitespace;
            }
            return max;
        }
        catch { return 0; }
    }

    // ---------------------------------------------------------------
    // 挂接：尺寸交由 WPF（SizeToContent）计算，AHK 不设置宽高
    // ---------------------------------------------------------------
    private HudInfo HudEnsure()
    {
        if (_hud != null)
            return _hud;
        if (win == null)
            return null;

        HudInfo info = new HudInfo();
        info.Text = HudFindText();
        info.Area = win.FindName("DragArea") as FrameworkElement;

        if (info.Text != null)
        {
            try
            {
                info.Text.TextWrapping = TextWrapping.Wrap;
                info.Text.TextTrimming = TextTrimming.None;
                info.Text.TextAlignment = TextAlignment.Left;
                // 首帧即需宽度上限，否则 Wrap 与 SizeToContent 会在无限宽度下量出超宽窗口
                info.Text.MaxWidth = 420;
            }
            catch { }
        }

        try
        {
            // 宽高由内容决定：宽度受 MaxWidth 约束，高度按行数，均由 WPF 测量
            win.Width = double.NaN;
            win.Height = double.NaN;
            win.SizeToContent = SizeToContent.WidthAndHeight;
        }
        catch { }

        win.SizeChanged += delegate(object s, SizeChangedEventArgs e)
        {
            HudInfo cur = _hud;
            if (cur == null)
                return;
            // 尺寸变化后须按新尺寸重算锚点，否则右侧锚定的窗口会随文本变长向右溢出
            if (cur.ReposQueued)
                return;
            cur.ReposQueued = true;
            try
            {
                win.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate()
                {
                    cur.ReposQueued = false;
                    // 尚未定位（首帧布局刚完成）时允许回退到整屏，避免停在默认位置
                    HudReposition(cur, !cur.Positioned);
                }));
            }
            catch { cur.ReposQueued = false; }
        };

        win.Closed += delegate
        {
            _hudDragging = false;
            HudUnhook();
            HudDetachShared(_hud);
            _hud = null;
        };

        _hud = info;
        return info;
    }

    private TextBlock HudFindText()
    {
        try
        {
            TextBlock tb = win.FindName("HudText") as TextBlock;
            if (tb != null)
                return tb;
        }
        catch { }
        try { return BridgeUtil.FindVisualChild<TextBlock>(win); }
        catch { return null; }
    }

    // ---------------------------------------------------------------
    // 定位：锚点对齐 + 偏移，均使用 WPF Left/Top（DIP）
    // ---------------------------------------------------------------
    private void HudReposition(HudInfo info)
    {
        HudReposition(info, false);
    }

    // allowScreenFallback：首次定位时目标窗口可能尚未显示，此时按整屏锚点定位一次，
    // 避免停留在 WPF 默认的 (0,0)。后续跟随不允许回退，保持原位而非跳变。
    private void HudReposition(HudInfo info, bool allowScreenFallback)
    {
        if (info == null || win == null)
            return;
        if (info.Mode == 0 || info.UserMoved || _hudDragging)
            return;

        try
        {
            double aw = win.ActualWidth;
            double ah = win.ActualHeight;
            if (double.IsNaN(aw) || aw <= 0)
                aw = win.Width;
            if (double.IsNaN(ah) || ah <= 0)
                ah = win.Height;
            if (double.IsNaN(aw) || double.IsNaN(ah) || aw <= 0 || ah <= 0)
                return;

            double bx, by, bw, bh;
            if (!HudBaseRect(info, allowScreenFallback, out bx, out by, out bw, out bh))
                return;   // 目标窗口不可用（已关闭或最小化）：保持原位

            double ax, ay, fx, fy;
            HudAnchorPoint(info.Anchor, bw, bh, out ax, out ay);
            HudAnchorPoint(info.Anchor, aw, ah, out fx, out fy);

            double nx = Math.Round(bx + ax - fx + info.OffX);
            double ny = Math.Round(by + ay - fy + info.OffY);

            // 窗口未定位时 Left/Top 为 NaN，与任何值比较均为 false，须单独判断
            if (double.IsNaN(win.Left) || Math.Abs(nx - win.Left) > 0.4)
                win.Left = nx;
            if (double.IsNaN(win.Top) || Math.Abs(ny - win.Top) > 0.4)
                win.Top = ny;
            info.LastLeft = nx;
            info.LastTop = ny;
            info.Positioned = true;
        }
        catch { }
    }

    // 锚点基准区域：跟随窗口时取目标窗口可见边框，否则取整个虚拟桌面
    private bool HudBaseRect(HudInfo info, bool allowFallback, out double bx, out double by, out double bw, out double bh)
    {
        bx = SystemParameters.VirtualScreenLeft;
        by = SystemParameters.VirtualScreenTop;
        bw = SystemParameters.VirtualScreenWidth;
        bh = SystemParameters.VirtualScreenHeight;

        if (info.Mode != 2 || info.Target == IntPtr.Zero)
            return true;

        try
        {
            if (!HudWindowVisible(info.Target))
                return allowFallback;
            Matrix m = HudDeviceToDip();
            RECT r;
            if (!HudTryGetVisibleRect(info.Target, out r))
                return allowFallback;
            Point tl = m.Transform(new Point(r.left, r.top));
            Point br = m.Transform(new Point(r.right, r.bottom));
            double w = br.X - tl.X;
            double h = br.Y - tl.Y;
            if (w <= 0 || h <= 0)
                return allowFallback;
            bx = tl.X;
            by = tl.Y;
            bw = w;
            bh = h;
            return true;
        }
        catch { return allowFallback; }
    }

    private bool HudWindowVisible(IntPtr hwnd)
    {
        try
        {
            if (!IsWindow(hwnd) || !IsWindowVisible(hwnd) || HudIsIconic(hwnd))
                return false;
        }
        catch { return false; }
        return true;
    }

    private bool HudTryGetVisibleRect(IntPtr hwnd, out RECT rect)
    {
        rect = new RECT();
        try
        {
            RECT dwm;
            if (HudDwmGetWindowAttribute(hwnd, 9, out dwm, Marshal.SizeOf(typeof(RECT))) == 0)
            {
                if (dwm.right > dwm.left && dwm.bottom > dwm.top)
                {
                    rect = dwm;
                    return true;
                }
            }
        }
        catch { }
        try { return GetWindowRect(hwnd, out rect); }
        catch { return false; }
    }

    private Matrix HudDeviceToDip()
    {
        try
        {
            PresentationSource src = PresentationSource.FromVisual(win);
            if (src != null && src.CompositionTarget != null)
                return src.CompositionTarget.TransformFromDevice;
        }
        catch { }
        return Matrix.Identity;
    }

    private static void HudAnchorPoint(int anchor, double w, double h, out double x, out double y)
    {
        int col = 2, row = 0;
        switch (anchor)
        {
            case 0: col = 0; row = 0; break;
            case 1: col = 0; row = 1; break;
            case 2: col = 0; row = 2; break;
            case 3: col = 1; row = 0; break;
            case 4: col = 1; row = 1; break;
            case 5: col = 1; row = 2; break;
            case 6: col = 2; row = 0; break;
            case 7: col = 2; row = 1; break;
            default: col = 2; row = 2; break;
        }
        x = (col == 0) ? 0 : (col == 1 ? w / 2.0 : w);
        y = (row == 0) ? 0 : (row == 1 ? h / 2.0 : h);
    }

    // ---------------------------------------------------------------
    // 跟随目标窗口：监听 WinEvent 位置变化，事件驱动，不使用定时器
    // ---------------------------------------------------------------
    private void HudHook(HudInfo info)
    {
        HudUnhook();
        if (info == null || info.Mode != 2 || info.Target == IntPtr.Zero)
            return;
        try
        {
            _hudHookProc = new HudHookProc(HudOnWinEvent);
            // flags=0 即 WINEVENT_OUTOFCONTEXT：回调投递到安装线程的消息循环（UI 线程）
            _hudHook = SetWinEventHook(HUD_EVENT_LOCATIONCHANGE, HUD_EVENT_LOCATIONCHANGE,
                IntPtr.Zero, _hudHookProc, 0, 0, 0);
        }
        catch
        {
            _hudHook = IntPtr.Zero;
            _hudHookProc = null;
        }
    }

    private void HudUnhook()
    {
        try
        {
            if (_hudHook != IntPtr.Zero)
                UnhookWinEvent(_hudHook);
        }
        catch { }
        _hudHook = IntPtr.Zero;
        _hudHookProc = null;
    }

    private void HudOnWinEvent(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild,
        uint dwEventThread, uint dwmsEventTime)
    {
        HudInfo info = _hud;
        if (info == null || hwnd != info.Target)
            return;
        // 仅关注顶层窗口自身的位置变化，忽略子控件事件
        if (idObject != 0 || idChild != 0)
            return;
        if (info.ReposQueued)
            return;
        info.ReposQueued = true;
        try
        {
            win.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate()
            {
                info.ReposQueued = false;
                HudReposition(info);
            }));
        }
        catch { info.ReposQueued = false; }
    }

    // ---------------------------------------------------------------
    // 拖动：自行跟随鼠标，不使用 DragMove()
    //
    // DragMove 依赖 WM_NCLBUTTONDOWN/HTCAPTION 的系统拖动循环，对
    // WS_EX_NOACTIVATE 的透明无边框窗口不保证生效。此处采用鼠标捕获加屏幕坐标
    // 增量计算，事件驱动，不引入定时器。
    // ---------------------------------------------------------------
    private bool _hudDragging;
    private double _hudDragCursorX, _hudDragCursorY;
    private double _hudDragLeft, _hudDragTop;

    internal void HudBeginDrag(UIElement area)
    {
        if (_hud == null || win == null || area == null)
            return;
        double cx, cy;
        if (!HudCursorPos(out cx, out cy))
            return;
        try
        {
            _hudDragging = true;
            _hudDragCursorX = cx;
            _hudDragCursorY = cy;
            _hudDragLeft = double.IsNaN(win.Left) ? 0 : win.Left;
            _hudDragTop = double.IsNaN(win.Top) ? 0 : win.Top;
            area.CaptureMouse();
        }
        catch
        {
            _hudDragging = false;
        }
    }

    internal void HudDragTo()
    {
        if (!_hudDragging || _hud == null || win == null)
            return;
        double cx, cy;
        if (!HudCursorPos(out cx, out cy))
            return;
        try
        {
            win.Left = Math.Round(_hudDragLeft + (cx - _hudDragCursorX));
            win.Top = Math.Round(_hudDragTop + (cy - _hudDragCursorY));
        }
        catch { }
    }

    internal void HudEndDrag(UIElement area)
    {
        if (!_hudDragging)
            return;
        _hudDragging = false;
        try
        {
            if (area != null)
                area.ReleaseMouseCapture();
        }
        catch { }
        HudOnDragEnd();
    }

    // 鼠标屏幕坐标（DIP）：GetCursorPos 返回物理像素，按本窗口 DPI 换算
    private bool HudCursorPos(out double x, out double y)
    {
        x = 0;
        y = 0;
        try
        {
            POINT pt;
            if (!GetCursorPos(out pt))
                return false;
            Point p = HudDeviceToDip().Transform(new Point(pt.x, pt.y));
            x = p.X;
            y = p.Y;
            return true;
        }
        catch { return false; }
    }

    // ---------------------------------------------------------------
    // 拖动结束：将新坐标回传 AHK 持久化
    // ---------------------------------------------------------------
    private void HudOnDragEnd()
    {
        HudInfo info = _hud;
        if (info == null || win == null)
            return;
        try
        {
            double l = win.Left, t = win.Top;
            if (double.IsNaN(l) || double.IsNaN(t))
                return;
            // 未发生位移（仅点击）：保持自动定位
            if (Math.Abs(l - info.LastLeft) <= 1 && Math.Abs(t - info.LastTop) <= 1)
                return;
            info.UserMoved = true;
            info.LastLeft = l;
            info.LastTop = t;
            string payload = ((long)Math.Round(l)).ToString(CultureInfo.InvariantCulture)
                + "," + ((long)Math.Round(t)).ToString(CultureInfo.InvariantCulture);
            SendToAhkAsync("EVENT|" + winId + "|Window|HudMoved|" + BridgeUtil.LengthPrefix(payload) + "\n");
        }
        catch { }
    }
}
