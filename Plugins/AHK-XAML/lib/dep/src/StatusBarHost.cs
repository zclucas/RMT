using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

// =============================================================================
// 状态栏：采样、读数、资源明细、悬停与钉住，全在引擎进程内完成
// =============================================================================
// 不放 AHK 的原因：AHK 没有线程，WMI/PDH 这类阻塞查询只能再起一个进程、再配一套
// 共享内存与序号协议；引擎本身是常驻 .NET 进程，采样丢线程池即可。
// AHK 只推两样（都不涉及持久化）：启动、下载/通知计数与运行中的宏标签。
// 文案直接写中文：底栏这几个词不参与多语言（GetLang 里也没有「内存」这个键）。
//
// 采样口径与旧的 AHK 版一致，改之前先对一遍：
//   CPU  —— GetSystemTimes 的 delta 作分母；RMT 取内部进程 kernel+user 之和的占比，
//           单个进程也是占整机的百分比（100% 表示所有核心跑满）。
//   GPU  —— PDH 的 \GPU Engine(*)\Utilization Percentage。单个进程取它最忙的那个引擎；
//           整机 / RMT 的总量按引擎求和后取最大值（不把 3D、Copy、Decode 叠一起）。
//   内存 —— GlobalMemoryStatusEx 取整机，psapi 逐进程取工作集。
//   网速 —— PDH 的 \Network Interface(*)\Bytes Received|Sent/sec，全实例求和。
public partial class AhkWpfEngine
{
    private const uint StatusTh32CsSnapshotProcess = 0x00000002;
    private const uint StatusProcessQueryLimited = 0x1000;
    private const uint StatusProcessVmRead = 0x0010;
    private const uint StatusPdhFmtDouble = 0x00000200;
    private const uint StatusPdhMoreData = 0x800007D2;
    private const int StatusSampleIntervalMs = 1000;
    private const int StatusHoverDelayMs = 350;
    private const int StatusSystemTopLimit = 3;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref StatusMemoryStatus buffer);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32FirstW(IntPtr snapshot, ref StatusProcessEntry entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32NextW(IntPtr snapshot, ref StatusProcessEntry entry);

    // CloseHandle 的声明在 HudHost.cs（同一个 partial class），这里直接用，不重复声明

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit,
        out long kernel, out long user);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentProcessId();

    [DllImport("psapi.dll", SetLastError = true)]
    private static extern bool GetProcessMemoryInfo(IntPtr process, ref StatusProcessMemory counters, uint size);

    [DllImport("pdh.dll", EntryPoint = "PdhOpenQueryW", CharSet = CharSet.Unicode)]
    private static extern uint PdhOpenQuery(string dataSource, IntPtr userData, out IntPtr query);

    // 一律用 English 计数器：计数器路径在非英文系统上会本地化，只有这个入口稳定
    [DllImport("pdh.dll", EntryPoint = "PdhAddEnglishCounterW", CharSet = CharSet.Unicode)]
    private static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr userData, out IntPtr counter);

    [DllImport("pdh.dll")]
    private static extern uint PdhCollectQueryData(IntPtr query);

    [DllImport("pdh.dll", EntryPoint = "PdhGetFormattedCounterArrayW", CharSet = CharSet.Unicode)]
    private static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint bufferSize,
        out uint itemCount, IntPtr buffer);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StatusProcessEntry
    {
        public uint Size;
        public uint Usage;
        public uint Pid;
        public IntPtr DefaultHeapId;
        public uint ModuleId;
        public uint Threads;
        public uint ParentPid;
        public int PriClassBase;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string ExeFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StatusMemoryStatus
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StatusProcessMemory
    {
        public uint Size;
        public uint PageFaultCount;
        public IntPtr PeakWorkingSet;
        public IntPtr WorkingSet;
        public IntPtr QuotaPeakPagedPool;
        public IntPtr QuotaPagedPool;
        public IntPtr QuotaPeakNonPagedPool;
        public IntPtr QuotaNonPagedPool;
        public IntPtr Pagefile;
        public IntPtr PeakPagefile;
    }

    // PDH_FMT_COUNTERVALUE 是 { DWORD CStatus; union {...} }，union 按 double 取 8 字节
    [StructLayout(LayoutKind.Sequential)]
    private struct StatusPdhValue
    {
        public uint Status;
        public double DoubleValue;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StatusPdhItem
    {
        public IntPtr Name;
        public StatusPdhValue Value;
    }

    private sealed class StatusProcTime
    {
        public long Creation;
        public long Kernel;
        public long User;
    }

    private sealed class StatusRow
    {
        public int Pid;
        public string Name;
        public bool Internal;
        public double Cpu = double.NaN;
        public double Memory = double.NaN;
        public double Gpu = double.NaN;
    }

    private sealed class StatusSnapshot
    {
        public string CpuText = "";
        public string GpuText = "";
        public string MemoryText = "";
        public string NetworkText = "";
        public List<StatusRow> Rows = new List<StatusRow>();
        public double SystemGpu = double.NaN;
        public double RmtGpu = double.NaN;
        public bool GpuReady;
        public bool InternalComplete = true;
    }

    private sealed class StatusMetricControls
    {
        public string BoxName;
        public FrameworkElement Selected;
        public FrameworkElement PinOn;
        public FrameworkElement PinOff;
    }

    private System.Threading.Timer statusSampler;
    private volatile bool statusRunning;
    private volatile bool statusWindowIdle;
    private int statusSampling;

    private TextBlock statusCpuBlock;
    private TextBlock statusGpuBlock;
    private TextBlock statusMemoryBlock;
    private TextBlock statusNetworkBlock;
    private Button statusDownloadsButton;
    private Button statusNotificationsButton;
    private FrameworkElement statusDetailPanel;
    private TextBlock statusDetailText;
    private string statusDetailMetric;

    private readonly Dictionary<FrameworkElement, string> statusMetricOfBox = new Dictionary<FrameworkElement, string>();
    private readonly Dictionary<string, StatusMetricControls> statusMetricControls = new Dictionary<string, StatusMetricControls>();
    private readonly Dictionary<int, string> statusMacroLabels = new Dictionary<int, string>();
    private readonly object statusMacroLock = new object();

    private DispatcherTimer statusHoverTimer;
    private string statusHoveredMetric;
    private string statusPinnedMetric;

    private StatusSnapshot statusSnapshot;
    private Dictionary<int, StatusProcTime> statusPrevTimes = new Dictionary<int, StatusProcTime>();
    private long statusPrevIdle;
    private long statusPrevTotal;

    private IntPtr statusPdhQuery = IntPtr.Zero;
    private IntPtr statusPdhGpu = IntPtr.Zero;
    private IntPtr statusPdhNetIn = IntPtr.Zero;
    private IntPtr statusPdhNetOut = IntPtr.Zero;
    private bool statusPdhLogged;
    private bool statusPdhCollectOk;

    // -------------------------------------------------------------------------
    // 入口：AHK 侧只有启停、计数、宏标签三条指令
    // -------------------------------------------------------------------------

    internal void StartStatusBar()
    {
        if (statusRunning)
            return;
        try
        {
            statusDetailPanel = FindControlByPath("StatusDetail") as FrameworkElement;
            statusDetailText = FindControlByPath("StatusDetailText") as TextBlock;
            statusCpuBlock = FindControlByPath("StatusCpu") as TextBlock;
            statusGpuBlock = FindControlByPath("StatusGpu") as TextBlock;
            statusMemoryBlock = FindControlByPath("StatusMemory") as TextBlock;
            statusNetworkBlock = FindControlByPath("StatusNetwork") as TextBlock;
            statusDownloadsButton = FindControlByPath("StatusDownloads") as Button;
            statusNotificationsButton = FindControlByPath("StatusNotifications") as Button;

            statusDetailMetric = null;
            statusHoveredMetric = null;
            statusPinnedMetric = null;

            HookStatusMetric("StatusCpu", "cpu");
            HookStatusMetric("StatusGpu", "gpu");
            HookStatusMetric("StatusMemory", "memory");

            if (statusHoverTimer == null)
            {
                statusHoverTimer = new DispatcherTimer();
                statusHoverTimer.Interval = TimeSpan.FromMilliseconds(StatusHoverDelayMs);
                statusHoverTimer.Tick += StatusHoverTick;
            }

            statusRunning = true;
            // 窗口关掉就地收摊：AHK 的 OnWindowClosing 是从引擎 Closing 回调里进来的，
            // 那一刻再同步投递指令会和引擎互相等待，收尾放在这里最省事
            Window window = win;
            if (window != null)
            {
                window.Closed += StatusWindowClosed;
                window.StateChanged += delegate { UpdateStatusWindowIdle(); };
                window.IsVisibleChanged += delegate { UpdateStatusWindowIdle(); };
            }
            UpdateStatusWindowIdle();

            // 首帧先给一次读数，别让底栏挂着建窗时的占位串
            ThreadPool.QueueUserWorkItem(StatusSampleOnce);
            statusSampler = new System.Threading.Timer(StatusSampleOnce, null,
                StatusSampleIntervalMs, StatusSampleIntervalMs);
        }
        catch (Exception ex)
        {
            statusRunning = false;
            LogDebug("StatusBar start failed: " + ex.Message);
        }
    }

    internal void StopStatusBar()
    {
        statusRunning = false;
        try
        {
            if (statusSampler != null)
            {
                statusSampler.Dispose();
                statusSampler = null;
            }
            if (statusHoverTimer != null)
                statusHoverTimer.Stop();
            statusHoveredMetric = null;
            statusPinnedMetric = null;
            statusDetailMetric = null;
            statusMetricOfBox.Clear();
            statusMetricControls.Clear();
            statusSnapshot = null;
            // 清掉上一轮的时间基线，否则窗口重开后第一帧会把整段空档算进 delta
            statusPrevTimes = new Dictionary<int, StatusProcTime>();
            statusPrevIdle = 0;
            statusPrevTotal = 0;
        }
        catch (Exception ex)
        {
            LogDebug("StatusBar stop failed: " + ex.Message);
        }
    }

    private void StatusWindowClosed(object sender, EventArgs e)
    {
        StopStatusBar();
    }

    // 下载/通知计数是 RMT 侧状态，没有变更通知，AHK 只在变化时推一条。
    // 不依赖 Start 先到：控件按需查找，先到就先写。
    internal void SetStatusBarCounts(string payload)
    {
        if (win == null || string.IsNullOrEmpty(payload))
            return;
        string[] parts = payload.Split('|');
        int downloads;
        int notifications;
        if (parts.Length < 2 || !int.TryParse(parts[0], out downloads) || !int.TryParse(parts[1], out notifications))
            return;
        if (statusDownloadsButton == null)
            statusDownloadsButton = FindControlByPath("StatusDownloads") as Button;
        if (statusNotificationsButton == null)
            statusNotificationsButton = FindControlByPath("StatusNotifications") as Button;
        SetButtonText(statusDownloadsButton, "下载 " + downloads.ToString(CultureInfo.InvariantCulture));
        SetButtonText(statusNotificationsButton, "通知 " + notifications.ToString(CultureInfo.InvariantCulture));
    }

    // pid=标签|pid=标签：宏类型-模块名-宏名，只有 AHK 的表结构知道
    internal void SetStatusBarLabels(string payload)
    {
        lock (statusMacroLock)
        {
            statusMacroLabels.Clear();
            if (string.IsNullOrEmpty(payload))
                return;
            foreach (string item in payload.Split('|'))
            {
                if (item.Length == 0)
                    continue;
                int split = item.IndexOf('=');
                if (split <= 0)
                    continue;
                int pid;
                if (!int.TryParse(item.Substring(0, split), out pid))
                    continue;
                statusMacroLabels[pid] = item.Substring(split + 1);
            }
        }
        // 明细正显示着就跟着刷新，标签是随宏启停变的
        if (statusDetailMetric != null)
            ApplyStatusDetail();
    }

    private void HookStatusMetric(string boxName, string metric)
    {
        FrameworkElement box = FindControlByPath(boxName + "Box") as FrameworkElement;
        if (box == null)
            return;
        statusMetricOfBox[box] = metric;
        box.MouseEnter += StatusMetricMouseEnter;
        box.MouseLeave += StatusMetricMouseLeave;
        box.MouseLeftButtonDown += StatusMetricMouseDown;

        var controls = new StatusMetricControls();
        controls.BoxName = boxName + "Box";
        controls.Selected = FindControlByPath(boxName + "Sel") as FrameworkElement;
        controls.PinOn = FindControlByPath(boxName + "PinOn") as FrameworkElement;
        controls.PinOff = FindControlByPath(boxName + "PinOff") as FrameworkElement;
        statusMetricControls[metric] = controls;
    }

    // -------------------------------------------------------------------------
    // 交互：悬停 350ms 出明细，移出即收；钉住常驻且同一时刻只钉一项
    // 全部在 UI 线程上，事件直接来自 WPF，不再绕 AHK 一圈
    // -------------------------------------------------------------------------

    private void StatusMetricMouseEnter(object sender, MouseEventArgs e)
    {
        var box = sender as FrameworkElement;
        if (box == null || !statusRunning)
            return;
        string metric;
        if (!statusMetricOfBox.TryGetValue(box, out metric))
            return;
        statusHoveredMetric = metric;
        if (statusHoverTimer != null)
        {
            statusHoverTimer.Stop();
            statusHoverTimer.Start();
        }
    }

    private void StatusMetricMouseLeave(object sender, MouseEventArgs e)
    {
        var box = sender as FrameworkElement;
        if (box == null)
            return;
        string metric;
        if (!statusMetricOfBox.TryGetValue(box, out metric))
            return;
        if (statusHoveredMetric == metric)
            statusHoveredMetric = null;
        if (statusHoverTimer != null)
            statusHoverTimer.Stop();
        // 钉住的那一项不跟着鼠标收
        if (statusPinnedMetric != null)
            return;
        if (statusDetailMetric == metric)
            HideStatusDetail();
    }

    private void StatusHoverTick(object sender, EventArgs e)
    {
        if (statusHoverTimer != null)
            statusHoverTimer.Stop();
        if (!statusRunning || statusHoveredMetric == null || statusPinnedMetric != null)
            return;
        ShowStatusDetail(statusHoveredMetric);
    }

    private void StatusMetricMouseDown(object sender, MouseButtonEventArgs e)
    {
        var box = sender as FrameworkElement;
        if (box == null || !statusRunning)
            return;
        string metric;
        if (!statusMetricOfBox.TryGetValue(box, out metric))
            return;
        e.Handled = true;
        ToggleStatusPin(metric);
    }

    private void ToggleStatusPin(string metric)
    {
        bool pin = statusPinnedMetric != metric;
        if (pin)
        {
            if (statusPinnedMetric != null)
                SetStatusPinVisual(statusPinnedMetric, false);
            statusPinnedMetric = metric;
            SetStatusPinVisual(metric, true);
            ShowStatusDetail(metric);
            return;
        }
        statusPinnedMetric = null;
        SetStatusPinVisual(metric, false);
        // 取消钉住时鼠标还停在这一项上就继续显示，等移出再收
        if (statusHoveredMetric != metric)
            HideStatusDetail();
    }

    private void SetStatusPinVisual(string metric, bool pinned)
    {
        StatusMetricControls controls;
        if (!statusMetricControls.TryGetValue(metric, out controls))
            return;
        if (controls.Selected != null)
            controls.Selected.Visibility = pinned ? Visibility.Visible : Visibility.Collapsed;
        if (controls.PinOn != null)
            controls.PinOn.Visibility = pinned ? Visibility.Visible : Visibility.Collapsed;
        if (controls.PinOff != null)
            controls.PinOff.Visibility = pinned ? Visibility.Collapsed : Visibility.Visible;
    }

    private void ShowStatusDetail(string metric)
    {
        StatusMetricControls controls;
        if (statusDetailPanel == null || statusDetailText == null)
            return;
        if (!statusMetricControls.TryGetValue(metric, out controls))
            return;
        statusDetailMetric = metric;
        statusDetailText.Text = ComposeStatusDetail(metric);
        statusDetailPanel.Visibility = Visibility.Visible;
        // 定位仍在 AnchoredPanel：目标换成被悬停的那一项，之后跟着布局自己重贴
        AttachAnchoredPanel(statusDetailPanel, controls.BoxName);
    }

    private void HideStatusDetail()
    {
        statusDetailMetric = null;
        if (statusDetailPanel != null)
            statusDetailPanel.Visibility = Visibility.Collapsed;
    }

    // -------------------------------------------------------------------------
    // 采样：线程池里跑，结果整份投到 UI 线程
    // -------------------------------------------------------------------------

    private void StatusSampleOnce(object state)
    {
        if (!statusRunning)
            return;
        // 上一轮还没跑完就跳过这一轮：WMI/PDH 偶发卡住时不要堆线程
        if (Interlocked.Exchange(ref statusSampling, 1) == 1)
            return;
        try
        {
            if (statusWindowIdle)
                return;
            StatusSnapshot snapshot = CollectStatus();
            Window window = win;
            if (window == null)
                return;
            window.Dispatcher.BeginInvoke(new Action(delegate()
            {
                ApplyStatusSnapshot(snapshot);
            }));
        }
        catch (Exception ex)
        {
            LogDebug("StatusBar sample failed: " + ex.Message);
        }
        finally
        {
            Interlocked.Exchange(ref statusSampling, 0);
        }
    }

    // 最小化/隐藏时不采样：这段时间的 delta 会被拉长成一段平均值，没有意义。
    // 状态由 UI 线程的事件维护，采样线程只读这一位 —— WPF 对象不能跨线程碰。
    private void UpdateStatusWindowIdle()
    {
        Window window = win;
        statusWindowIdle = window == null || !window.IsVisible || window.WindowState == WindowState.Minimized;
    }

    private void ApplyStatusSnapshot(StatusSnapshot snapshot)
    {
        if (!statusRunning || snapshot == null)
            return;
        try
        {
            statusSnapshot = snapshot;
            SetText(statusCpuBlock, snapshot.CpuText);
            SetText(statusGpuBlock, snapshot.GpuText);
            SetText(statusMemoryBlock, snapshot.MemoryText);
            SetText(statusNetworkBlock, snapshot.NetworkText);
            // 明细正显示着就跟一次：钉住时数字与进程列表要能自己更新
            if (statusDetailMetric != null)
                ApplyStatusDetail();
        }
        catch (Exception ex)
        {
            LogDebug("StatusBar apply failed: " + ex.Message);
        }
    }

    private void ApplyStatusDetail()
    {
        if (statusDetailText == null || statusDetailMetric == null)
            return;
        statusDetailText.Text = ComposeStatusDetail(statusDetailMetric);
    }

    private StatusSnapshot CollectStatus()
    {
        var snapshot = new StatusSnapshot();

        Dictionary<int, StatusProcessEntry> processes = SnapshotStatusProcesses();
        HashSet<int> internalPids;
        bool internalComplete;
        ResolveStatusInternalPids(processes, out internalPids, out internalComplete);
        snapshot.InternalComplete = internalComplete;

        long idle;
        long kernel;
        long user;
        long totalDelta = 0;
        long idleDelta = 0;
        bool haveSystem = statusPrevTotal > 0;
        if (GetSystemTimes(out idle, out kernel, out user))
        {
            long total = kernel + user;
            if (haveSystem)
            {
                totalDelta = total - statusPrevTotal;
                idleDelta = idle - statusPrevIdle;
            }
            statusPrevIdle = idle;
            statusPrevTotal = total;
        }
        else
        {
            haveSystem = false;
        }

        double systemCpu = double.NaN;
        if (haveSystem && totalDelta > 0)
            systemCpu = ClampPercent(100.0 * (totalDelta - idleDelta) / totalDelta);

        // 一次遍历同时拿 CPU 时间与工作集：逐进程开句柄已经是这份代码最贵的部分
        var nextTimes = new Dictionary<int, StatusProcTime>(processes.Count);
        double rmtCpuDelta = 0;
        double rmtWorkingSet = 0;
        bool rmtCpuKnown = totalDelta > 0;
        bool rmtMemoryKnown = true;
        int internalCount = 0;

        foreach (KeyValuePair<int, StatusProcessEntry> pair in processes)
        {
            int pid = pair.Key;
            bool internalProc = internalPids.Contains(pid);
            // 工作集对全部进程都要：明细的「系统」段按内存排序取前三，没有全量就没有排序依据
            bool wantsMemory = true;
            IntPtr handle = OpenProcess(StatusProcessQueryLimited | StatusProcessVmRead, false, pid);
            if (handle == IntPtr.Zero)
            {
                // 受保护进程不给 VM_READ，退一步只取 CPU 时间
                handle = OpenProcess(StatusProcessQueryLimited, false, pid);
                wantsMemory = false;
                if (internalProc)
                    rmtMemoryKnown = false;
            }
            if (handle == IntPtr.Zero)
            {
                if (internalProc)
                {
                    rmtCpuKnown = false;
                    rmtMemoryKnown = false;
                }
                continue;
            }
            try
            {
                long creation;
                long exit;
                long procKernel;
                long procUser;
                if (!GetProcessTimes(handle, out creation, out exit, out procKernel, out procUser))
                {
                    if (internalPids.Contains(pid))
                    {
                        rmtCpuKnown = false;
                        rmtMemoryKnown = false;
                    }
                    continue;
                }
                var times = new StatusProcTime();
                times.Creation = creation;
                times.Kernel = procKernel;
                times.User = procUser;
                nextTimes[pid] = times;

                var row = new StatusRow();
                row.Pid = pid;
                row.Name = pair.Value.ExeFile;
                row.Internal = internalPids.Contains(pid);

                StatusProcTime previous;
                if (totalDelta > 0 && statusPrevTimes.TryGetValue(pid, out previous)
                    && previous.Creation == creation)
                {
                    long delta = (procKernel + procUser) - (previous.Kernel + previous.User);
                    if (delta < 0)
                        delta = 0;
                    row.Cpu = ClampPercent(100.0 * delta / totalDelta);
                    if (row.Internal)
                        rmtCpuDelta += delta;
                }
                else if (row.Internal)
                {
                    rmtCpuKnown = false;
                }

                if (wantsMemory)
                {
                    var counters = new StatusProcessMemory();
                    counters.Size = (uint)Marshal.SizeOf(typeof(StatusProcessMemory));
                    if (GetProcessMemoryInfo(handle, ref counters, counters.Size))
                    {
                        double workingSet = counters.WorkingSet.ToInt64();
                        row.Memory = workingSet;
                        if (internalProc)
                        {
                            rmtWorkingSet += workingSet;
                            internalCount++;
                        }
                    }
                    else if (internalProc)
                    {
                        rmtMemoryKnown = false;
                    }
                }
                snapshot.Rows.Add(row);
            }
            finally
            {
                CloseHandle(handle);
            }
        }
        statusPrevTimes = nextTimes;

        var memoryStatus = new StatusMemoryStatus();
        memoryStatus.Length = (uint)Marshal.SizeOf(typeof(StatusMemoryStatus));
        double usedMemory = double.NaN;
        double totalMemory = double.NaN;
        if (GlobalMemoryStatusEx(ref memoryStatus))
        {
            totalMemory = memoryStatus.TotalPhys;
            usedMemory = memoryStatus.TotalPhys - memoryStatus.AvailPhys;
        }

        double rmtCpu = rmtCpuKnown ? ClampPercent(100.0 * rmtCpuDelta / totalDelta) : double.NaN;
        double rmtMemory = (rmtMemoryKnown && internalCount > 0) ? rmtWorkingSet : double.NaN;

        CollectStatusPdh();
        CollectStatusGpu(snapshot, internalPids);
        double netIn;
        double netOut;
        CollectStatusNetwork(out netIn, out netOut);

        // 底栏统一「RMT / 系统」在前
        snapshot.CpuText = "CPU " + FormatStatusPercent(rmtCpu) + " / " + FormatStatusPercent(systemCpu);
        snapshot.GpuText = "GPU " + FormatStatusPercent(snapshot.RmtGpu) + " / " + FormatStatusPercent(snapshot.SystemGpu);
        snapshot.MemoryText = "内存 " + FormatStatusMemory(rmtMemory) + " / "
            + FormatStatusMemory(usedMemory) + " / " + FormatStatusMemory(totalMemory);
        snapshot.NetworkText = "↓ " + FormatStatusRate(netIn) + "  ↑ " + FormatStatusRate(netOut);
        return snapshot;
    }

    private static Dictionary<int, StatusProcessEntry> SnapshotStatusProcesses()
    {
        var processes = new Dictionary<int, StatusProcessEntry>();
        IntPtr snapshot = CreateToolhelp32Snapshot(StatusTh32CsSnapshotProcess, 0);
        if (snapshot == IntPtr.Zero || snapshot == new IntPtr(-1))
            return processes;
        try
        {
            var entry = new StatusProcessEntry();
            entry.Size = (uint)Marshal.SizeOf(typeof(StatusProcessEntry));
            if (!Process32FirstW(snapshot, ref entry))
                return processes;
            do
            {
                processes[(int)entry.Pid] = entry;
                entry.Size = (uint)Marshal.SizeOf(typeof(StatusProcessEntry));
            }
            while (Process32NextW(snapshot, ref entry));
        }
        finally
        {
            CloseHandle(snapshot);
        }
        return processes;
    }

    // 内部进程 = 主程序与 daemon 的全部后代（Worker、更新器、WebView2 都在里面）。
    // 不靠 AHK 上报 pid：那需要在 Worker 启停处挂钩子，而父子关系本来就在快照里。
    private void ResolveStatusInternalPids(Dictionary<int, StatusProcessEntry> processes,
        out HashSet<int> internalPids, out bool complete)
    {
        internalPids = new HashSet<int>();
        complete = true;
        int self = (int)GetCurrentProcessId();
        int parent = 0;
        StatusProcessEntry selfEntry;
        if (processes.TryGetValue(self, out selfEntry))
            parent = (int)selfEntry.ParentPid;
        if (parent == 0 || !processes.ContainsKey(parent))
            complete = false;

        var children = new Dictionary<int, List<int>>();
        foreach (KeyValuePair<int, StatusProcessEntry> pair in processes)
        {
            int childParent = (int)pair.Value.ParentPid;
            if (childParent == 0)
                continue;
            List<int> list;
            if (!children.TryGetValue(childParent, out list))
            {
                list = new List<int>();
                children[childParent] = list;
            }
            list.Add(pair.Key);
        }

        var queue = new Queue<int>();
        internalPids.Add(self);
        queue.Enqueue(self);
        if (parent != 0)
        {
            internalPids.Add(parent);
            queue.Enqueue(parent);
        }
        while (queue.Count > 0)
        {
            List<int> kids;
            if (!children.TryGetValue(queue.Dequeue(), out kids))
                continue;
            for (int i = 0; i < kids.Count; i++)
            {
                if (internalPids.Add(kids[i]))
                    queue.Enqueue(kids[i]);
            }
        }
    }

    // GPU：\GPU Engine(*)\Utilization Percentage，实例名形如
    // pid_1234_luid_0x00000000_0x0000C3B4_phys_0_eng_0_engtype_3D
    private void CollectStatusGpu(StatusSnapshot snapshot, HashSet<int> internalPids)
    {
        snapshot.GpuReady = false;
        if (!statusPdhCollectOk || statusPdhGpu == IntPtr.Zero)
            return;

        List<KeyValuePair<string, double>> values = ReadStatusCounter(statusPdhGpu);
        if (values.Count == 0)
            return;

        // 同一个进程会在多个引擎上各占一份（3D、Copy、VideoDecode…），分进程相加会超过 100，
        // 所以「单个进程」只取最忙的那个引擎；而整机 / RMT 的总量必须按引擎求和后取最大值，
        // 否则多进程同时吃 GPU 时总量会被低估（任务管理器就是这个口径）。
        var perPidEngine = new Dictionary<string, double>();
        var engineTotal = new Dictionary<string, double>();
        var engineInternal = new Dictionary<string, double>();
        for (int i = 0; i < values.Count; i++)
        {
            Match match = Regex.Match(values[i].Key, "^pid_(\\d+)_(.+)$");
            if (!match.Success)
                continue;
            int pid;
            if (!int.TryParse(match.Groups[1].Value, out pid))
                continue;
            double value = values[i].Value;
            if (double.IsNaN(value) || value < 0)
                continue;
            string engine = match.Groups[2].Value;

            string key = pid.ToString(CultureInfo.InvariantCulture) + "\u0000" + engine;
            perPidEngine[key] = (perPidEngine.ContainsKey(key) ? perPidEngine[key] : 0) + value;
            engineTotal[engine] = (engineTotal.ContainsKey(engine) ? engineTotal[engine] : 0) + value;
            if (internalPids.Contains(pid))
                engineInternal[engine] = (engineInternal.ContainsKey(engine) ? engineInternal[engine] : 0) + value;
        }

        var perPidPeak = new Dictionary<int, double>();
        foreach (KeyValuePair<string, double> pair in perPidEngine)
        {
            int split = pair.Key.IndexOf('\u0000');
            if (split <= 0)
                continue;
            int pid;
            if (!int.TryParse(pair.Key.Substring(0, split), out pid))
                continue;
            double peak;
            perPidPeak.TryGetValue(pid, out peak);
            perPidPeak[pid] = Math.Max(peak, pair.Value);
        }

        for (int i = 0; i < snapshot.Rows.Count; i++)
        {
            StatusRow row = snapshot.Rows[i];
            double peak;
            if (perPidPeak.TryGetValue(row.Pid, out peak))
                row.Gpu = ClampPercent(peak);
        }

        double total = 0;
        foreach (KeyValuePair<string, double> pair in engineTotal)
            total = Math.Max(total, pair.Value);
        double ours = 0;
        foreach (KeyValuePair<string, double> pair in engineInternal)
            ours = Math.Max(ours, pair.Value);

        // 一个可用实例都没有时不算「有数据」，否则底栏会显示 0% 而不是不可用
        if (engineTotal.Count == 0)
            return;

        snapshot.SystemGpu = ClampPercent(total);
        // 有 GPU 数据但内部进程一点没占：那是 0，不是「不可用」
        snapshot.RmtGpu = ClampPercent(ours);
        snapshot.GpuReady = true;
    }

    private void CollectStatusNetwork(out double received, out double sent)
    {
        received = double.NaN;
        sent = double.NaN;
        if (!statusPdhCollectOk)
            return;
        if (statusPdhNetIn != IntPtr.Zero)
        {
            List<KeyValuePair<string, double>> values = ReadStatusCounter(statusPdhNetIn);
            if (values.Count > 0)
            {
                double sum = 0;
                for (int i = 0; i < values.Count; i++)
                    if (!double.IsNaN(values[i].Value) && values[i].Value > 0)
                        sum += values[i].Value;
                received = sum;
            }
        }
        if (statusPdhNetOut != IntPtr.Zero)
        {
            List<KeyValuePair<string, double>> values = ReadStatusCounter(statusPdhNetOut);
            if (values.Count > 0)
            {
                double sum = 0;
                for (int i = 0; i < values.Count; i++)
                    if (!double.IsNaN(values[i].Value) && values[i].Value > 0)
                        sum += values[i].Value;
                sent = sum;
            }
        }
    }

    // 每个周期只采集一次：GPU 与网速都在同一个查询里，重复采集会让速率窗口错位。
    // 首个周期速率型计数器还没有基线，采出来是无效值，底栏那一秒显示不可用。
    private void CollectStatusPdh()
    {
        EnsureStatusPdhQuery();
        statusPdhCollectOk = statusPdhQuery != IntPtr.Zero && PdhCollectQueryData(statusPdhQuery) == 0;
    }

    private void EnsureStatusPdhQuery()
    {
        if (statusPdhQuery != IntPtr.Zero)
            return;
        IntPtr query;
        if (PdhOpenQuery(null, IntPtr.Zero, out query) != 0)
        {
            // 失败会每秒重试一次，日志只留一条就够
            if (!statusPdhLogged)
            {
                statusPdhLogged = true;
                LogDebug("StatusBar PDH query open failed");
            }
            return;
        }
        statusPdhQuery = query;
        statusPdhGpu = AddStatusPdHCounter(query, @"\GPU Engine(*)\Utilization Percentage");
        statusPdhNetIn = AddStatusPdHCounter(query, @"\Network Interface(*)\Bytes Received/sec");
        statusPdhNetOut = AddStatusPdHCounter(query, @"\Network Interface(*)\Bytes Sent/sec");
        // 这里不垫采集：速率型计数器要两个有间隔的样本，紧接着再采一次只会拿到无效值
    }

    private IntPtr AddStatusPdHCounter(IntPtr query, string path)
    {
        IntPtr counter;
        uint status = PdhAddEnglishCounter(query, path, IntPtr.Zero, out counter);
        if (status != 0)
        {
            LogDebug("StatusBar PDH counter failed (" + status.ToString(CultureInfo.InvariantCulture) + "): " + path);
            return IntPtr.Zero;
        }
        return counter;
    }

    private List<KeyValuePair<string, double>> ReadStatusCounter(IntPtr counter)
    {
        var values = new List<KeyValuePair<string, double>>();
        if (counter == IntPtr.Zero)
            return values;

        uint size = 0;
        uint count = 0;
        uint status = PdhGetFormattedCounterArray(counter, StatusPdhFmtDouble, ref size, out count, IntPtr.Zero);
        if (status != StatusPdhMoreData || size == 0 || count == 0)
            return values;

        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            status = PdhGetFormattedCounterArray(counter, StatusPdhFmtDouble, ref size, out count, buffer);
            if (status != 0 || count == 0)
                return values;
            // 缓冲区由 PDH 按它自己的结构体大小分配；能用 size/count 反推就更稳
            int stride = (size % count == 0) ? (int)(size / count) : Marshal.SizeOf(typeof(StatusPdhItem));
            for (uint i = 0; i < count; i++)
            {
                IntPtr address = new IntPtr(buffer.ToInt64() + (long)i * stride);
                var item = (StatusPdhItem)Marshal.PtrToStructure(address, typeof(StatusPdhItem));
                if (item.Value.Status != 0)
                    continue;
                string name = Marshal.PtrToStringUni(item.Name);
                if (string.IsNullOrEmpty(name))
                    continue;
                values.Add(new KeyValuePair<string, double>(name, item.Value.DoubleValue));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        return values;
    }

    // -------------------------------------------------------------------------
    // 明细文本
    // -------------------------------------------------------------------------

    private string ComposeStatusDetail(string metric)
    {
        string title = metric == "gpu" ? "GPU" : (metric == "cpu" ? "CPU" : "内存");
        StatusSnapshot snapshot = statusSnapshot;
        if (snapshot == null || snapshot.Rows.Count == 0)
            return title + "\n不可用";
        if (metric == "gpu" && !snapshot.GpuReady)
            return title + "\n不可用";

        var mine = new List<StatusRow>();
        var others = new List<StatusRow>();
        for (int i = 0; i < snapshot.Rows.Count; i++)
        {
            StatusRow row = snapshot.Rows[i];
            if (row.Internal)
                mine.Add(row);
            else
                others.Add(row);
        }

        Dictionary<int, string> labels;
        lock (statusMacroLock)
            labels = new Dictionary<int, string>(statusMacroLabels);

        var text = new System.Text.StringBuilder();
        text.Append(title);
        // 分组顺序跟底栏读数一致：RMT 在前，系统在后
        AppendStatusDetailSection(text, "RMT", mine, metric, labels, 0);
        AppendStatusDetailSection(text, "系统", others, metric, labels, StatusSystemTopLimit);
        if (!snapshot.InternalComplete)
            text.Append("\n\n部分内部进程未计入");
        return text.ToString();
    }

    private void AppendStatusDetailSection(System.Text.StringBuilder text, string header, List<StatusRow> rows,
        string metric, Dictionary<int, string> labels, int limit)
    {
        text.Append("\n\n").Append(header);
        var sorted = new List<StatusRow>(rows);
        sorted.Sort(delegate(StatusRow left, StatusRow right)
        {
            return StatusRowValue(right, metric).CompareTo(StatusRowValue(left, metric));
        });
        // 没有可用值的排最后：NaN 比任何数都小，降序时自然落到末尾
        int shown = 0;
        for (int i = 0; i < sorted.Count; i++)
        {
            StatusRow row = sorted[i];
            double value = StatusRowValue(row, metric);
            if (double.IsNaN(value) && !row.Internal)
                continue;
            if (limit > 0 && shown >= limit)
                break;
            shown++;
            string label;
            string line = row.Name + " (" + row.Pid.ToString(CultureInfo.InvariantCulture) + ")";
            if (row.Internal && labels.TryGetValue(row.Pid, out label) && !string.IsNullOrEmpty(label))
                line += " [" + label + "]";
            line += "  ";
            line += metric == "memory" ? FormatStatusMemory(value) : FormatStatusPercent(value);
            text.Append("\n").Append(line);
        }
        if (shown == 0)
            text.Append("\n无数据");
    }

    private static double StatusRowValue(StatusRow row, string metric)
    {
        if (metric == "gpu")
            return row.Gpu;
        if (metric == "memory")
            return row.Memory;
        return row.Cpu;
    }

    // -------------------------------------------------------------------------
    // 格式化：数字一律用不变文化，别让系统区域设置把小数点变成逗号
    // -------------------------------------------------------------------------

    private static void SetText(TextBlock block, string value)
    {
        if (block == null || value == null || block.Text == value)
            return;
        block.Text = value;
    }

    private static void SetButtonText(Button button, string value)
    {
        if (button == null)
            return;
        string current = button.Content as string;
        if (current == value)
            return;
        button.Content = value;
    }

    private static double ClampPercent(double value)
    {
        if (double.IsNaN(value))
            return double.NaN;
        if (value < 0)
            return 0;
        if (value > 100)
            return 100;
        return value;
    }

    private static string FormatStatusPercent(double value)
    {
        if (double.IsNaN(value))
            return "不可用";
        return ClampPercent(value).ToString("0.0", CultureInfo.InvariantCulture) + "%";
    }

    private static string FormatStatusMemory(double bytes)
    {
        if (double.IsNaN(bytes) || bytes < 0)
            return "不可用";
        if (bytes >= 1073741824)
            return (bytes / 1073741824).ToString("0.0", CultureInfo.InvariantCulture) + " GB";
        return (bytes / 1048576).ToString("0.0", CultureInfo.InvariantCulture) + " MB";
    }

    private static string FormatStatusRate(double bytesPerSecond)
    {
        if (double.IsNaN(bytesPerSecond) || bytesPerSecond < 0)
            return "不可用";
        if (bytesPerSecond >= 1048576)
            return (bytesPerSecond / 1048576).ToString("0.0", CultureInfo.InvariantCulture) + " MB/s";
        return (bytesPerSecond / 1024).ToString("0.0", CultureInfo.InvariantCulture) + " KB/s";
    }
}
