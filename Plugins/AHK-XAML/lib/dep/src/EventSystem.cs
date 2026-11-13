// =============================================================================
// Event system: binding, throttling, AHK event reporting
// =============================================================================
using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Markup;
using Color = System.Windows.Media.Color;

#if ENABLE_WEBVIEW
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;
#endif
public partial class AhkWpfEngine
{
    // WM_COPYDATA callbacks must stay asynchronous to avoid re-entrant WPF/AHK deadlocks,
    // but a separate ThreadPool work item per event can reorder Down/Move/Up.  A single
    // FIFO worker preserves UI event order while retaining the asynchronous boundary.
    private readonly object _asyncSendLock = new object();
    private readonly System.Collections.Generic.Queue<string> _asyncSendQueue =
        new System.Collections.Generic.Queue<string>();
    private bool _asyncSendWorkerRunning;
    private FrameworkElement _ballDragControl;
    private IntPtr _ballDragWindowHwnd;
    private int _ballDragStartMouseX;
    private int _ballDragStartMouseY;
    private int _ballDragStartWindowX;
    private int _ballDragStartWindowY;
    private bool _ballDragMoved;
    private string _ballDragControlName;   // 拖动心跳要回发到哪个控件的事件名
    private int _ballDragBeatAt;           // 上次心跳的 TickCount（限频用）
    // Window 级焦点上报只挂一次（RebindEvents 重复下发也只算一次）
    private bool _focusEditableBound;
    // 窗口级 MouseMove/PreviewMouseMove 是否回传。默认 true 保持既有行为；
    // 主窗绑它只为拖 AI 分割条时取 DragCoords，开窗后由 AHK 关掉，按下分割条时再临时打开。
    // 控件级 MouseMove（画布、摇杆、树节点拖拽）不受此开关影响。
    internal bool ReportWindowMouseMove = true;

    private void BindEvent(string ctrlName, string eventName, int fpsLimit = 0, bool queueLimited = false)
    {
        string eventKey = ctrlName + ":" + eventName;
        object ctrl = ctrlName == "Window" ? (object)win : FindControlByPath(ctrlName);
        if (ctrl == null)
        {
            _boundEvents.Remove(eventKey);
            if (_boundEventCtrls != null)
                _boundEventCtrls.Remove(eventKey);
            if (AhkWpfEngine.VerboseBindLog)
            {
                try
                {
                    System.IO.File.AppendAllText(
                        GetLogPath("AhkWpfDebug.log"),
                        string.Format("BindEvent info: Control '{0}' not found for event '{1}' (may be dynamic)\n", ctrlName, eventName)
                    );
                } catch { }
            }
            return;
        }
        if (_boundEventCtrls == null)
            _boundEventCtrls = new System.Collections.Generic.Dictionary<string, object>();
        object oldCtrl;
        if (_boundEventCtrls.TryGetValue(eventKey, out oldCtrl) && object.ReferenceEquals(oldCtrl, ctrl))
            return;
        _boundEventCtrls[eventKey] = ctrl;
        _boundEvents.Add(eventKey);
        try
        {
            // 可编辑 ComboBox：TextChanged 是内嵌 TextBox（PART_EditableTextBox）的 CLR 事件，
            // ComboBox 自身没有该事件，下方反射 GetEvent 会失败导致绑定静默丢失
            // （如 SearchProGui 坐标框 TextChanged→预览刷新不生效、TextOpsGui ArgsNameCon 同理）。
            // 显式挂内嵌 TextBox 的 TextChanged，事件名仍以 ComboBox 名上报，AHK 侧绑定不变。
            if (eventName == "TextChanged" && ctrl is System.Windows.Controls.ComboBox)
            {
                var combo = (System.Windows.Controls.ComboBox)ctrl;
                if (combo.IsEditable)
                {
                    System.Windows.Controls.TextBox hookedTb = null;
                    combo.Loaded += (s, e) =>
                    {
                        try
                        {
                            combo.ApplyTemplate();
                            var tb = combo.Template != null
                                ? combo.Template.FindName("PART_EditableTextBox", combo) as System.Windows.Controls.TextBox
                                : null;
                            if (tb != null && hookedTb == null)
                            {
                                hookedTb = tb;
                                tb.TextChanged += (s2, e2) => DumpState(ctrlName, eventName);
                            }
                        }
                        catch { }
                    };
                }
                return;
            }

            if (eventName == "IsVisibleChanged")
            {
                if (ctrl is UIElement)
                {
                    ((UIElement)ctrl).IsVisibleChanged += (s, e) =>
                    {
                        string val = BridgeUtil.LengthPrefix(e.NewValue.ToString());
                        SendToAhk("EVENT|" + winId + "|" + ctrlName + "|IsVisibleChanged|" + val + "\n");
                    };
                }
                return;
            }

            // 焦点是否落在可输入控件上（Window 级，一次挂载全窗生效）。
            // 控件状态归引擎：焦点换到 TextBox/可编辑下拉时推 1，换走或落空推 0。
            // 主程序只读这个结果，不用再逐控件挂 GotFocus 去自己维护焦点状态。
            if (eventName == "FocusEditable")
            {
                if (ctrl is UIElement && !_focusEditableBound)
                {
                    _focusEditableBound = true;
                    System.Windows.Input.KeyboardFocusChangedEventHandler onFocus =
                        (s, e) => ReportFocusEditable(e.NewFocus);
                    ((UIElement)ctrl).AddHandler(UIElement.GotKeyboardFocusEvent, onFocus, true);
                    ((UIElement)ctrl).AddHandler(UIElement.LostKeyboardFocusEvent, onFocus, true);
                    try
                    {
                        System.IO.File.AppendAllText(GetLogPath("AhkWpfDebug.log"),
                            "BindEvent: Window:FocusEditable installed (" + ctrlName + ")\n");
                    }
                    catch { }
                }
                return;
            }

            // KeyDown:Return / KeyUp:Alt / PreviewKeyDown:Delete 等：绑底层键盘事件，仅在目标键时上报
            if (eventName.StartsWith("KeyDown:") || eventName.StartsWith("PreviewKeyDown:") || eventName.StartsWith("KeyUp:"))
            {
                int colon = eventName.IndexOf(':');
                string baseEvt = eventName.Substring(0, colon);
                string keyFilter = eventName.Substring(colon + 1);
                if (ctrl is UIElement)
                {
                    UIElement ue = (UIElement)ctrl;
                    if (baseEvt == "PreviewKeyDown")
                    {
                        ue.PreviewKeyDown += (s, e) =>
                        {
                            if (KeyMatchesFilter(e, keyFilter))
                            {
                                DumpStateWithArgs(ctrlName, baseEvt, e);
                                // Enter：交给 AHK（发送 / Shift+换行），阻止 TextBox 再插入换行
                                // Tab：交给 AHK 处理，阻止默认焦点移动（绑了 Tab 的窗口才会走到）
                                if (keyFilter == "Return" || keyFilter == "Tab")
                                    e.Handled = true;
                            }
                        };
                    }
                    else if (baseEvt == "KeyUp")
                    {
                        ue.KeyUp += (s, e) =>
                        {
                            if (KeyMatchesFilter(e, keyFilter))
                                DumpStateWithArgs(ctrlName, baseEvt, e);
                        };
                    }
                    else
                    {
                        ue.KeyDown += (s, e) =>
                        {
                            if (KeyMatchesFilter(e, keyFilter))
                                DumpStateWithArgs(ctrlName, baseEvt, e);
                        };
                    }
                }
                return;
            }

            // KeyCapture：通用按键捕获（Hotkey 控件用）。控件聚焦时按下任意键，映射成 AHK 键名发回。
            if (eventName == "KeyCapture")
            {
                if (ctrl is UIElement)
                {
                    UIElement ue = (UIElement)ctrl;
                    ue.PreviewKeyDown += (s, e) =>
                    {
                        string ahkKey = KeyToAhkName(e);
                        if (ahkKey != "")
                        {
                            e.Handled = true;
                            SendToAhkAsync("EVENT|" + winId + "|" + ctrlName + "|KeyCapture|" + BridgeUtil.LengthPrefix(ahkKey) + "\n");
                        }
                    };
                }
                return;
            }

            // 悬浮球在 WPF UI 线程内捕获鼠标并移动窗口，避免逐帧跨进程回调造成拖动滞后。
            // 移动/抬起同时挂到窗口上：球是 WS_EX_NOACTIVATE 的透明窗，捕获偶发失败时
            // 只挂元素的话会完全收不到 MouseMove，表现为「拖不动」。
            if (eventName == "BallDrag")
            {
                var ball = ctrl as FrameworkElement;
                if (ball != null)
                {
                    ball.PreviewMouseLeftButtonDown += (s, e) => BeginBallDrag(ctrlName, ball, e);
                    ball.PreviewMouseMove += (s, e) => UpdateBallDrag(ball, e);
                    ball.PreviewMouseLeftButtonUp += (s, e) => EndBallDrag(ctrlName, ball, e);
                    ball.LostMouseCapture += (s, e) => CancelBallDrag(ctrlName, ball);
                    if (win != null)
                    {
                        win.PreviewMouseMove += (s, e) => UpdateBallDrag(ball, e);
                        win.PreviewMouseLeftButtonUp += (s, e) => EndBallDrag(ctrlName, ball, e);
                    }
                }
                return;
            }

            // PreviewMouseLeftButtonDown：双击树条目时置 Handled，阻止 TreeViewItem 默认展开/折叠切换
            if (eventName == "PreviewMouseLeftButtonDown")
            {
                if (ctrl is UIElement)
                {
                    ((UIElement)ctrl).PreviewMouseLeftButtonDown += (s, e) =>
                    {
                        if (ctrlName.StartsWith("AiSplit_", StringComparison.Ordinal))
                        {
                            try { ((UIElement)ctrl).CaptureMouse(); } catch { }
                        }
                        if (e.ClickCount >= 2)
                        {
                            DependencyObject orig = e.OriginalSource as DependencyObject;
                            bool onExpander = false;
                            while (orig != null && !(orig is System.Windows.Controls.TreeViewItem) && !(orig is System.Windows.Controls.TreeView))
                            {
                                if (orig is System.Windows.Controls.Primitives.ToggleButton)
                                    onExpander = true;   // 点在展开箭头上
                                orig = System.Windows.Media.VisualTreeHelper.GetParent(orig);
                            }
                            // 双击条目内容才阻止展开切换；双击箭头让它正常每次切换
                            if (orig is System.Windows.Controls.TreeViewItem && !onExpander)
                                e.Handled = true;
                        }
                        DumpStateWithArgs(ctrlName, eventName, e);
                    };
                }
                return;
            }

            // 扩展面板分割线在按下时捕获鼠标；按钮抬起后必须显式释放，
            // 否则移出 6px 热区时会丢 MouseMove，后续点击也可能仍投递给旧分割线。
            if (eventName == "PreviewMouseLeftButtonUp" && ctrl is UIElement)
            {
                ((UIElement)ctrl).PreviewMouseLeftButtonUp += (s, e) =>
                {
                    DumpStateWithArgs(ctrlName, eventName, e);
                    var captured = System.Windows.Input.Mouse.Captured as FrameworkElement;
                    if (captured != null && captured.Name.StartsWith("AiSplit_", StringComparison.Ordinal))
                    {
                        try { captured.ReleaseMouseCapture(); } catch { }
                    }
                };
                return;
            }

            var evt = ctrl.GetType().GetEvent(eventName);
            if (evt == null)
            {
                _boundEvents.Remove(eventKey);
                return;
            }

            var parameters = evt.EventHandlerType.GetMethod("Invoke").GetParameters();

            if (eventName == "Drop")
            {
                if (ctrl is UIElement)
                {
                    ((UIElement)ctrl).AllowDrop = true;
                    ((UIElement)ctrl).Drop += (s, e) =>
                    {
                        if (e.Data.GetDataPresent(DataFormats.FileDrop))
                        {
                            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                            string fileList = BridgeUtil.LengthPrefix(string.Join("|", files));
                            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|Drop|" + fileList + "\n");
                        }
                    };
                }
                return;
            }

            var pExprs = parameters.Select(p => System.Linq.Expressions.Expression.Parameter(p.ParameterType, p.Name)).ToArray();
            System.Linq.Expressions.MethodCallExpression call;

            if (fpsLimit > 0)
            {
                var throttler = new EventThrottler(fpsLimit, queueLimited, this, ctrlName, eventName);
                var throttlerConst = System.Linq.Expressions.Expression.Constant(throttler);

                if (pExprs.Length >= 2)
                {
                    var method = typeof(EventThrottler).GetMethod("InvokeWithArgs");
                    var objCast = System.Linq.Expressions.Expression.Convert(pExprs[1], typeof(object));
                    call = System.Linq.Expressions.Expression.Call(throttlerConst, method, objCast);
                }
                else
                {
                    var method = typeof(EventThrottler).GetMethod("Invoke");
                    call = System.Linq.Expressions.Expression.Call(throttlerConst, method);
                }
            }
            else
            {
                if (pExprs.Length >= 2)
                {
                    var dumpStateWithArgsMethod = this.GetType().GetMethod("DumpStateWithArgs", BindingFlags.NonPublic | BindingFlags.Instance);
                    var objCast = System.Linq.Expressions.Expression.Convert(pExprs[1], typeof(object));
                    call = System.Linq.Expressions.Expression.Call(System.Linq.Expressions.Expression.Constant(this), dumpStateWithArgsMethod, System.Linq.Expressions.Expression.Constant(ctrlName), System.Linq.Expressions.Expression.Constant(eventName), objCast);
                }
                else
                {
                    var dumpStateMethod = this.GetType().GetMethod("DumpState", BindingFlags.NonPublic | BindingFlags.Instance);
                    call = System.Linq.Expressions.Expression.Call(System.Linq.Expressions.Expression.Constant(this), dumpStateMethod, System.Linq.Expressions.Expression.Constant(ctrlName), System.Linq.Expressions.Expression.Constant(eventName));
                }
            }

            var lambda = System.Linq.Expressions.Expression.Lambda(evt.EventHandlerType, call, pExprs);
            // Compile(true) = 解释执行而不是生成 IL+JIT。
            // 每个事件生成一次 IL 要 20~50ms，一个弹窗绑 3~5 个事件就是 130~150ms，
            // 全花在窗口 Show 之前（实测 pre-show 段）。解释执行编译开销 <1ms，
            // 只在事件触发时慢几微秒，UI 事件完全无感。
            evt.AddEventHandler(ctrl, lambda.Compile(true));
        }
        catch (Exception ex)
        {
            _boundEvents.Remove(eventKey);
            if (_boundEventCtrls != null)
                _boundEventCtrls.Remove(eventKey);
            try {
                System.IO.File.AppendAllText(
                    GetLogPath("AhkWpfDebug.log"),
                    string.Format("BindEvent exception: Control '{0}', Event '{1}' - {2}\n", ctrlName, eventName, ex.ToString())
                );
            } catch { }
        }
    }

    private void BeginBallDrag(string ctrlName, FrameworkElement ball,
        System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.ChangedButton != System.Windows.Input.MouseButton.Left || _ballDragControl != null)
            return;

        POINT mouse;
        RECT window;
        IntPtr hwnd = new WindowInteropHelper(win).Handle;
        if (hwnd == IntPtr.Zero || !GetCursorPos(out mouse) || !GetWindowRect(hwnd, out window))
            return;

        _ballDragControl = ball;
        _ballDragControlName = ctrlName;
        _ballDragBeatAt = 0;
        _ballDragWindowHwnd = hwnd;
        _ballDragStartMouseX = mouse.x;
        _ballDragStartMouseY = mouse.y;
        _ballDragStartWindowX = window.left;
        _ballDragStartWindowY = window.top;
        _ballDragMoved = false;
        // 捕获失败不放弃拖动：窗口一直跟着鼠标走，球本身始终在光标下方，
        // 窗口级的 MouseMove/MouseLeftButtonUp 仍能收到事件（见 BallDrag 绑定处）。
        try { ball.CaptureMouse(); } catch { }
        // 通知 AHK「开始拖了」：拖动期间窗口位置由这里逐帧接管，AHK 侧跟随定时器
        // 必须让开，否则慢速拖动时每 50ms 会被拽回上一次的位置（球看着发黏）。
        SendToAhkAsync("EVENT|" + winId + "|" + ctrlName + "|BallDrag|"
            + BridgeUtil.LengthPrefix("down") + "\n");
        e.Handled = true;
    }

    private void UpdateBallDrag(FrameworkElement ball, System.Windows.Input.MouseEventArgs e)
    {
        // 不能要求 IsMouseCaptured：NOACTIVATE 透明窗的捕获不可靠，一旦没捕获成功
        // 这里就会静默返回，整只球拖不动。以「是否是当前拖动对象」为准即可。
        if (!object.ReferenceEquals(_ballDragControl, ball))
            return;

        POINT mouse;
        if (!GetCursorPos(out mouse))
            return;

        int dx = mouse.x - _ballDragStartMouseX;
        int dy = mouse.y - _ballDragStartMouseY;

        // 拖动心跳：窗口位置完全由这里接管，AHK 只需要知道「还在拖，别插手」。
        // 以前是 AHK 自己用 GetKeyState("LButton") 推断，实测靠不住 —— 拖到一半就被判成
        // 松手，跟随定时器 50ms 一次把窗口拽回起点，画面就在新旧两点之间来回闪。
        // 放在拖动阈值判断之前：手指轻动但还没到拖动距离时也要报「我还按着」，
        // 否则 AHK 那边超时解锁，真开始拖的头一帧会被拽回原位。
        // 按 60ms 限频，一次拖动十几条短消息，开销可以忽略。
        if (!string.IsNullOrEmpty(_ballDragControlName))
        {
            int now = Environment.TickCount;
            if (now - _ballDragBeatAt >= 60)
            {
                _ballDragBeatAt = now;
                SendToAhkAsync("EVENT|" + winId + "|" + _ballDragControlName + "|BallDrag|"
                    + BridgeUtil.LengthPrefix("drag|" + (_ballDragStartWindowX + dx) + ","
                        + (_ballDragStartWindowY + dy)) + "\n");
            }
        }

        if (!_ballDragMoved)
        {
            double scaleX = 1;
            double scaleY = 1;
            try
            {
                PresentationSource source = PresentationSource.FromVisual(ball);
                if (source != null && source.CompositionTarget != null)
                {
                    scaleX = source.CompositionTarget.TransformToDevice.M11;
                    scaleY = source.CompositionTarget.TransformToDevice.M22;
                }
            }
            catch { }

            int thresholdX = Math.Max(1, (int)Math.Ceiling(SystemParameters.MinimumHorizontalDragDistance * scaleX));
            int thresholdY = Math.Max(1, (int)Math.Ceiling(SystemParameters.MinimumVerticalDragDistance * scaleY));
            if (Math.Abs(dx) <= thresholdX && Math.Abs(dy) <= thresholdY)
                return;
            _ballDragMoved = true;
        }

        SetWindowPos(_ballDragWindowHwnd, IntPtr.Zero,
            _ballDragStartWindowX + dx, _ballDragStartWindowY + dy, 0, 0,
            0x0001 | 0x0004 | 0x0010);
        e.Handled = true;
    }

    private void EndBallDrag(string ctrlName, FrameworkElement ball,
        System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!object.ReferenceEquals(_ballDragControl, ball)
            || e.ChangedButton != System.Windows.Input.MouseButton.Left)
            return;

        UpdateBallDrag(ball, e);
        bool moved = _ballDragMoved;
        IntPtr hwnd = _ballDragWindowHwnd;
        int x = _ballDragStartWindowX;
        int y = _ballDragStartWindowY;
        if (moved)
        {
            RECT window;
            if (GetWindowRect(hwnd, out window))
            {
                x = window.left;
                y = window.top;
            }
        }

        _ballDragControl = null;
        _ballDragControlName = null;
        _ballDragWindowHwnd = IntPtr.Zero;
        _ballDragMoved = false;
        if (ball.IsMouseCaptured)
            ball.ReleaseMouseCapture();

        string gesture = moved ? "move|" + x + "," + y : "click";
        SendToAhkAsync("EVENT|" + winId + "|" + ctrlName + "|BallDrag|"
            + BridgeUtil.LengthPrefix(gesture) + "\n");
        e.Handled = true;
    }

    // 捕获丢失等异常收尾：告诉 AHK「拖结束了」（位置以当前窗口矩形为准），
    // 否则拖动标记会一直挂着，跟随定时器永久让开、球就不再跟窗口了。
    private void CancelBallDrag(string ctrlName, FrameworkElement ball)
    {
        if (!object.ReferenceEquals(_ballDragControl, ball))
            return;
        IntPtr hwnd = _ballDragWindowHwnd;
        RECT window;
        bool haveRect = GetWindowRect(hwnd, out window);
        bool moved = _ballDragMoved && haveRect;
        _ballDragControl = null;
        _ballDragControlName = null;
        _ballDragWindowHwnd = IntPtr.Zero;
        _ballDragMoved = false;
        string gesture = moved ? "move|" + window.left + "," + window.top : "up";
        SendToAhkAsync("EVENT|" + winId + "|" + ctrlName + "|BallDrag|"
            + BridgeUtil.LengthPrefix(gesture) + "\n");
    }

    public class EventThrottler
    {
        private int _delayMs;
        private bool _queueLimited;
        private object _bridge;
        private string _ctrlName;
        private string _eventName;
        private DateTime _lastFire = DateTime.MinValue;
        private bool _timerRunning = false;
        private object _lastArgs = null;
        private bool _hasPending = false;
        private object _sync = new object();
        private System.Collections.Generic.Queue<object> _queue = new System.Collections.Generic.Queue<object>();

        public EventThrottler(int fpsLimit, bool queueLimited, object bridge, string ctrlName, string eventName)
        {
            _delayMs = 1000 / fpsLimit;
            _queueLimited = queueLimited;
            _bridge = bridge;
            _ctrlName = ctrlName;
            _eventName = eventName;
        }

        public void Invoke() { InvokeWithArgs(null); }

        public void InvokeWithArgs(object args)
        {
            lock (_sync)
            {
                var now = DateTime.UtcNow;
                if (_queueLimited)
                {
                    _queue.Enqueue(args);
                    if (!_timerRunning)
                    {
                        _timerRunning = true;
                        ProcessQueueAsync();
                    }
                }
                else
                {
                    if (now - _lastFire >= TimeSpan.FromMilliseconds(_delayMs))
                    {
                        _lastFire = now;
                        FireEvent(args);
                    }
                    else
                    {
                        _lastArgs = args;
                        _hasPending = true;
                        if (!_timerRunning)
                        {
                            _timerRunning = true;
                            int waitMs = (int)(_delayMs - (now - _lastFire).TotalMilliseconds);
                            if (waitMs <= 0) waitMs = 1;
                            System.Threading.Tasks.Task.Delay(waitMs).ContinueWith(t =>
                            {
                                lock (_sync)
                                {
                                    _timerRunning = false;
                                    if (_hasPending)
                                    {
                                        _hasPending = false;
                                        _lastFire = DateTime.UtcNow;
                                        FireEvent(_lastArgs);
                                        _lastArgs = null;
                                    }
                                }
                            });
                        }
                    }
                }
            }
        }

        private async void ProcessQueueAsync()
        {
            while (true)
            {
                object args = null;
                lock (_sync)
                {
                    if (_queue.Count > 0) args = _queue.Dequeue();
                    else { _timerRunning = false; return; }
                }
                FireEvent(args);
                await System.Threading.Tasks.Task.Delay(_delayMs);
            }
        }

        private void FireEvent(object args)
        {
            var bridgeType = _bridge.GetType();
            Action action = () =>
            {
                try
                {
                    if (args != null)
                    {
                        bridgeType.GetMethod("DumpStateWithArgs", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(_bridge, new object[] { _ctrlName, _eventName, args });
                    }
                    else
                    {
                        bridgeType.GetMethod("DumpState", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(_bridge, new object[] { _ctrlName, _eventName });
                    }
                }
                catch { }
            };

            if (Application.Current != null && !Application.Current.Dispatcher.CheckAccess())
            {
                Application.Current.Dispatcher.BeginInvoke(action);
            }
            else
            {
                action();
            }
        }
    }
    // 键名匹配：Enter→Return 别名；Alt/Ctrl 等修饰键在 WPF 里是 Key.System，真实键在 SystemKey。
    // 修饰键支持聚合名：Alt 同时匹配 LeftAlt/RightAlt（Win 同理），AHK 侧只绑一个即可。
    private static bool KeyMatchesFilter(System.Windows.Input.KeyEventArgs e, string keyFilter)
    {
        if (e.Key.ToString() == keyFilter)
            return true;
        if (keyFilter == "Return" && e.Key == System.Windows.Input.Key.Enter)
            return true;
        if (e.Key == System.Windows.Input.Key.System && e.SystemKey != System.Windows.Input.Key.None)
        {
            string sk = e.SystemKey.ToString();
            if (sk == keyFilter)
                return true;
            if (keyFilter == "Alt" && (e.SystemKey == System.Windows.Input.Key.LeftAlt || e.SystemKey == System.Windows.Input.Key.RightAlt))
                return true;
            if (keyFilter == "Win" && (e.SystemKey == System.Windows.Input.Key.LWin || e.SystemKey == System.Windows.Input.Key.RWin))
                return true;
        }
        return false;
    }

    private void DumpStateWithArgs(string cName, string eName, object e)
    {
        if (e is System.Windows.Input.KeyEventArgs)
        {
            var ke = (System.Windows.Input.KeyEventArgs)e;
            // Ctrl 组合时 Key 偶发为 System，改读 SystemKey
            var key = (ke.Key == System.Windows.Input.Key.System) ? ke.SystemKey : ke.Key;
            eName += ":" + key.ToString();

            var mods = System.Windows.Input.Keyboard.Modifiers;
            bool ctrlOnly = (mods & System.Windows.Input.ModifierKeys.Control) != 0
                && (mods & System.Windows.Input.ModifierKeys.Shift) == 0
                && (mods & System.Windows.Input.ModifierKeys.Alt) == 0;

            // Ctrl+V：事件主载荷直接带画布坐标，不塞进 CollectState 长报文
            string eventPayload = "";
            if (key == System.Windows.Input.Key.V && ctrlOnly)
            {
                Canvas pasteCanvas = FindZoomPanCanvas();
                if (pasteCanvas != null)
                {
                    var inv = System.Globalization.CultureInfo.InvariantCulture;
                    Point pos = System.Windows.Input.Mouse.GetPosition(pasteCanvas);
                    try
                    {
                        POINT sp;
                        if (GetCursorPos(out sp))
                            pos = pasteCanvas.PointFromScreen(new System.Windows.Point((double)sp.x, (double)sp.y));
                    }
                    catch { }
                    if (!string.IsNullOrEmpty(pasteCanvas.Name))
                        canvasMouseCache[pasteCanvas.Name] = pos;
                    eventPayload = BridgeUtil.LengthPrefix(
                        pos.X.ToString(inv) + "," + pos.Y.ToString(inv));
                }
            }

            var sbKey = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName);
            if (eventPayload != "")
                sbKey.Append("|").Append(eventPayload);
            sbKey.Append("\n");

            // 修饰键写入 state，避免 AHK SetTimer 延迟后 GetKeyState 已松开
            string modStr = "";
            if ((mods & System.Windows.Input.ModifierKeys.Control) != 0) modStr += "Ctrl,";
            if ((mods & System.Windows.Input.ModifierKeys.Shift) != 0) modStr += "Shift,";
            if ((mods & System.Windows.Input.ModifierKeys.Alt) != 0) modStr += "Alt,";
            if (modStr.Length > 0)
                sbKey.Append("KeyModifiers=" + BridgeUtil.LengthPrefix(modStr.TrimEnd(',')) + "\n");
            if (IsEditableFocus(System.Windows.Input.Keyboard.FocusedElement))
                sbKey.Append("KeyFromEditable=" + BridgeUtil.LengthPrefix("1") + "\n");

            if (key == System.Windows.Input.Key.V && ctrlOnly)
            {
                // 粘贴只需短报文 + 坐标；再写一份 CanvasMouseLive 作兼容
                AppendCanvasMouseLiveToState(sbKey);
                if (eventPayload != "")
                    sbKey.Append("PasteAt=" + eventPayload + "\n");
            }
            else if (LightweightEvents)
            {
                string triggerVal = GetControlValue(cName);
                if (triggerVal != null)
                    sbKey.Append(cName + "=" + BridgeUtil.LengthPrefix(triggerVal) + "\n");
            }
            else
            {
                AppendCanvasMouseLiveToState(sbKey);
                sbKey.Append(CollectState());
            }
            SendToAhkAsync(sbKey.ToString());
            return;
        }
#if ENABLE_WEBVIEW
        else if (e is Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs) {
            var we = (Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs)e;
            var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "|" + BridgeUtil.LengthPrefix(we.WebMessageAsJson) + "\n");
            SendToAhk(sb.ToString());
            return;
        }
#endif
        else if (e is System.Windows.Input.MouseEventArgs)
        {
            if (eName == "MouseMove" || eName == "PreviewMouseMove")
            {
                // 窗口级鼠标移动默认不回传：主窗绑它是为了拖侧栏时取 DragCoords，
                // 平时鼠标划过整个窗口就是每秒六十来条全量状态报文＋跨进程往返。
                // AHK 在按下分割条时开、松开时关（CONFIG/MouseMoveReport）；控件级 MouseMove
                // （画布、摇杆、轮盘）不受影响。
                if (cName == "Window" && !ReportWindowMouseMove) return;
                if ((DateTime.Now - lastSendMouseMove).TotalMilliseconds < 16) return;
                lastSendMouseMove = DateTime.Now;
            }
            var me = (System.Windows.Input.MouseEventArgs)e;
            var ctrl = FindControlByPath(cName) as System.Windows.IInputElement;
            if (ctrl != null)
            {
                var pos = me.GetPosition(ctrl);
                string coords = ((int)pos.X) + "," + ((int)pos.Y);
                var dragPos = me.GetPosition(win);
                string dragCoords = ((int)dragPos.X) + "," + ((int)dragPos.Y);
                var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "|" + BridgeUtil.LengthPrefix(coords) + "\n");
                sb.Append(cName + "=" + BridgeUtil.LengthPrefix(coords) + "\n");
                sb.Append("DragCoords=" + BridgeUtil.LengthPrefix(dragCoords) + "\n");
                if (e is System.Windows.Input.MouseButtonEventArgs)
                {
                    sb.Append("ClickCount=" + BridgeUtil.LengthPrefix(((System.Windows.Input.MouseButtonEventArgs)e).ClickCount.ToString()) + "\n");
                    // 列表/树按下时顺带回报命中行的 Tag：主程序拿它直接定位点了哪一行，
                    // 不用再补一条同步 HitTest 查询（那是点一下等一次跨进程往返）。
                    if (eName == "PreviewMouseLeftButtonDown" || eName == "MouseLeftButtonDown"
                        || eName == "PreviewMouseRightButtonDown" || eName == "MouseRightButtonDown")
                    {
                        string hitTag = HitItemTagAt(ctrl, pos);
                        if (hitTag != "")
                            sb.Append("HitTag=" + BridgeUtil.LengthPrefix(hitTag) + "\n");
                    }
                }
                SendToAhkAsync(sb.ToString());
                return;
            }
        }
        DumpState(cName, eName);
    }

    // 文本框（非只读）、密码框、可编辑或已展开的下拉框接收编辑按键。
    private static bool IsEditableFocus(IInputElement focus)
    {
        TextBoxBase tb = focus as TextBoxBase;
        if (tb != null)
            return !tb.IsReadOnly;
        if (focus is PasswordBox)
            return true;
        ComboBox cb = focus as ComboBox;
        return cb != null && (cb.IsEditable || cb.IsDropDownOpen);
    }

    private void ReportFocusEditable(IInputElement focus)
    {
        try
        {
            // 必须走 LengthPrefix：AHK 侧 DecodeValue 只认「长度:值」，裸 "1" 会被当 base64 解成空串，
            // 主程序那边就只能读到空值，焦点状态永远停在 0。
            SendToAhkAsync("EVENT|" + winId + "|Window|FocusEditable|"
                + BridgeUtil.LengthPrefix(IsEditableFocus(focus) ? "1" : "0") + "\n");
        }
        catch { }
    }

    // ===================== 输入限制 =====================
    // XAML 上用 Tag 声明，拦截在引擎里做。多个规则用 | 叠加，全部满足才放行：
    //   Tag="NumOnly"                      只收半角数字
    //   Tag="NumOnly|MaxLen:5"             数字，最长 5 位
    //   Tag="AsciiAlnum|NoSpace|NoIME"     只收英文数字、不许空格、关掉输入法
    // 规则表写在代码里，加一种规则就是在表里加一行。
    private static readonly Dictionary<string, string> MaskRules = new Dictionary<string, string>
    {
        { "NumOnly",    @"^\d*$" },                 // 半角数字
        { "AsciiAlnum", @"^[A-Za-z0-9]*$" },        // 英文 + 数字
        { "NoSpace",    @"^\S*$" },                 // 不许空白（全角空格也算）
        { "Int",        @"^-?\d*$" },               // 可负整数
        { "Decimal",    @"^-?\d*(\.\d{0,%})?$" },   // 小数，% 换成小数位数
        { "MaxLen",     @"^[\s\S]{0,%}$" },         // 最长 % 个字符
    };

    private static readonly DependencyProperty MaskAppliedProperty =
        DependencyProperty.RegisterAttached("MaskApplied", typeof(bool), typeof(AhkWpfEngine),
            new PropertyMetadata(false));

    // 窗口 Loaded 后整棵视觉树扫一遍。虚拟列表那种延迟生成的控件不在此时存在，
    // 需要时在生成后再调用一次。
    private void AttachInputMasks(DependencyObject root)
    {
        if (root == null)
            return;
        TextBox tb = root as TextBox;
        if (tb != null)
            AttachMask(tb, tb.Tag as string);
        // 可编辑下拉：Tag 写在 ComboBox 上，实际输入的是模板里的 PART_EditableTextBox
        ComboBox cb = root as ComboBox;
        if (cb != null && cb.IsEditable)
        {
            string cbTag = cb.Tag as string;
            if (!string.IsNullOrEmpty(cbTag))
            {
                try { cb.ApplyTemplate(); }
                catch { }
                TextBox inner = cb.Template == null ? null
                    : cb.Template.FindName("PART_EditableTextBox", cb) as TextBox;
                if (inner != null)
                    AttachMask(inner, cbTag);
            }
        }
        int count = 0;
        try { count = VisualTreeHelper.GetChildrenCount(root); }
        catch { return; }
        for (int i = 0; i < count; i++)
            AttachInputMasks(VisualTreeHelper.GetChild(root, i));
    }

    private void AttachMask(TextBox tb, string tag)
    {
        if (string.IsNullOrEmpty(tag))
            return;
        if ((bool)tb.GetValue(MaskAppliedProperty))
            return;

        bool noIme = false;
        List<Regex> rules = new List<Regex>();
        string[] tokens = tag.Split('|');
        for (int i = 0; i < tokens.Length; i++)
        {
            string tok = tokens[i].Trim();
            if (tok.Length == 0)
                continue;
            string name = tok;
            string argv = "";
            int colon = tok.IndexOf(':');
            if (colon > 0)
            {
                name = tok.Substring(0, colon).Trim();
                argv = tok.Substring(colon + 1).Trim();
            }
            if (name == "NoIME")
            {
                noIme = true;          // 不是正则规则：关掉这个框的输入法
                continue;
            }
            string pattern;
            if (!MaskRules.TryGetValue(name, out pattern))
                continue;
            if (pattern.IndexOf('%') >= 0)
            {
                if (argv.Length == 0)
                    continue;               // 带 % 的规则必须给参数，缺了就当没写
                pattern = pattern.Replace("%", argv);
            }
            try { rules.Add(new Regex(pattern, RegexOptions.CultureInvariant)); }
            catch { }
        }
        if (rules.Count == 0 && !noIme)
            return;
        tb.SetValue(MaskAppliedProperty, true);

        if (noIme)
            System.Windows.Input.InputMethod.SetIsInputMethodEnabled(tb, false);

        Regex[] set = rules.ToArray();

        // 逐字符拦截：拿「插入后的候选串」判定，不能只看新字符，否则长度类规则形同虚设。
        // 只挂 Preview（隧道），冒泡的 TextInput 到达时 TextBox 已经插完字，会把候选串算重。
        System.Windows.Input.TextCompositionEventHandler filter = (s, e) =>
        {
            if (string.IsNullOrEmpty(e.Text))
                return;
            if (!MaskAcceptsInput(tb, set, e.Text))
                e.Handled = true;
        };
        tb.PreviewTextInput += filter;

        // 粘贴：整段参与判定，不合法就整段丢掉。正则只判不修，没法做到「只留数字」。
        DataObject.AddPastingHandler(tb, (s, e) => MaskOnPaste(tb, set, e));

        // 兜底：输入法上屏、拖放、外部注入这些绕开 PreviewTextInput 的路径，
        // 退回上一个合法值。同一个 Dispatcher 周期内完成，中间态不会被绘制，不会闪。
        string lastValid = tb.Text == null ? "" : tb.Text;
        bool fixing = false;
        tb.TextChanged += (s, e) =>
        {
            if (fixing)
                return;
            string cur = tb.Text == null ? "" : tb.Text;
            if (MaskAcceptsText(set, cur))
            {
                lastValid = cur;
                return;
            }
            int caret = tb.CaretIndex;
            fixing = true;
            try
            {
                tb.Text = lastValid;
                tb.CaretIndex = Math.Min(caret, lastValid.Length);
            }
            finally
            {
                fixing = false;
            }
        };
    }

    private static bool MaskAcceptsText(Regex[] rules, string text)
    {
        for (int i = 0; i < rules.Length; i++)
        {
            if (!rules[i].IsMatch(text))
                return false;
        }
        return true;
    }

    // 模拟一次插入后的整串，判断是否仍满足全部规则
    private static bool MaskAcceptsInput(TextBox tb, Regex[] rules, string input)
    {
        string cur = tb.Text == null ? "" : tb.Text;
        int start = tb.SelectionStart;
        int len = tb.SelectionLength;
        if (start < 0) start = 0;
        if (start > cur.Length) start = cur.Length;
        if (len < 0) len = 0;
        if (start + len > cur.Length) len = cur.Length - start;
        string candidate = cur.Substring(0, start) + input + cur.Substring(start + len);
        return MaskAcceptsText(rules, candidate);
    }

    private static void MaskOnPaste(TextBox tb, Regex[] rules, DataObjectPastingEventArgs e)
    {
        string raw = null;
        try
        {
            if (e.DataObject.GetDataPresent(DataFormats.UnicodeText))
                raw = e.DataObject.GetData(DataFormats.UnicodeText) as string;
            else if (e.DataObject.GetDataPresent(DataFormats.Text))
                raw = e.DataObject.GetData(DataFormats.Text) as string;
        }
        catch { }
        if (raw == null || !MaskAcceptsInput(tb, rules, raw))
            e.CancelCommand();
    }

    // 在指定控件内按该控件的本地坐标做一次命中测试，向上找列表项/树项的 Tag。
    // 只用于把「点了哪一行」随鼠标事件一起回传，省掉主程序那条同步 HitTest 查询。
    private static string HitItemTagAt(object root, System.Windows.Point p)
    {
        var vis = root as System.Windows.Media.Visual;
        if (vis == null)
            return "";
        try
        {
            var res = System.Windows.Media.VisualTreeHelper.HitTest(vis, p);
            System.Windows.DependencyObject d = (res != null) ? res.VisualHit as System.Windows.DependencyObject : null;
            while (d != null)
            {
                if (d is System.Windows.Controls.ListBoxItem || d is System.Windows.Controls.TreeViewItem)
                {
                    var fe = d as System.Windows.FrameworkElement;
                    if (fe != null && fe.Tag != null)
                        return fe.Tag.ToString();
                    return "";
                }
                d = System.Windows.Media.VisualTreeHelper.GetParent(d);
            }
        }
        catch { }
        return "";
    }

    // 把 WPF Key 映射成 AHK 键名（与 KeyGui 按键网格 value 一致）
    private static string KeyToAhkName(System.Windows.Input.KeyEventArgs e)
    {
        var key = (e.Key == System.Windows.Input.Key.System) ? e.SystemKey : e.Key;
        if (key >= System.Windows.Input.Key.A && key <= System.Windows.Input.Key.Z)
            return key.ToString().ToLowerInvariant();
        if (key >= System.Windows.Input.Key.D0 && key <= System.Windows.Input.Key.D9)
            return key.ToString().Substring(1); // "D1" -> "1"
        switch (key)
        {
            case System.Windows.Input.Key.Escape: return "Esc";
            case System.Windows.Input.Key.F1: case System.Windows.Input.Key.F2: case System.Windows.Input.Key.F3:
            case System.Windows.Input.Key.F4: case System.Windows.Input.Key.F5: case System.Windows.Input.Key.F6:
            case System.Windows.Input.Key.F7: case System.Windows.Input.Key.F8: case System.Windows.Input.Key.F9:
            case System.Windows.Input.Key.F10: case System.Windows.Input.Key.F11: case System.Windows.Input.Key.F12:
            case System.Windows.Input.Key.F13: case System.Windows.Input.Key.F14: case System.Windows.Input.Key.F15:
            case System.Windows.Input.Key.F16: case System.Windows.Input.Key.F17: case System.Windows.Input.Key.F18:
            case System.Windows.Input.Key.F19: case System.Windows.Input.Key.F20: case System.Windows.Input.Key.F21:
            case System.Windows.Input.Key.F22: case System.Windows.Input.Key.F23: case System.Windows.Input.Key.F24:
                return key.ToString();
            case System.Windows.Input.Key.Space: return "Space";
            case System.Windows.Input.Key.Enter: return "Enter";
            case System.Windows.Input.Key.Back: return "BS";
            case System.Windows.Input.Key.Tab: return "Tab";
            case System.Windows.Input.Key.Oem3: return "`";
            case System.Windows.Input.Key.OemMinus: return "-";
            case System.Windows.Input.Key.OemPlus: return "=";
            case System.Windows.Input.Key.OemOpenBrackets: return "[";
            case System.Windows.Input.Key.OemCloseBrackets: return "]";
            case System.Windows.Input.Key.OemBackslash: return "\\";
            case System.Windows.Input.Key.OemSemicolon: return ";";
            case System.Windows.Input.Key.OemQuotes: return "'";
            case System.Windows.Input.Key.OemComma: return ",";
            case System.Windows.Input.Key.OemPeriod: return ".";
            case System.Windows.Input.Key.OemQuestion: return "/";
            case System.Windows.Input.Key.Left: return "Left";
            case System.Windows.Input.Key.Right: return "Right";
            case System.Windows.Input.Key.Up: return "Up";
            case System.Windows.Input.Key.Down: return "Down";
            case System.Windows.Input.Key.Insert: return "Ins";
            case System.Windows.Input.Key.Delete: return "Del";
            case System.Windows.Input.Key.Home: return "Home";
            case System.Windows.Input.Key.End: return "End";
            case System.Windows.Input.Key.PageUp: return "PgUp";
            case System.Windows.Input.Key.PageDown: return "PgDn";
            case System.Windows.Input.Key.NumLock: return "NumLock";
            case System.Windows.Input.Key.NumPad0: return "Numpad0";
            case System.Windows.Input.Key.NumPad1: return "Numpad1";
            case System.Windows.Input.Key.NumPad2: return "Numpad2";
            case System.Windows.Input.Key.NumPad3: return "Numpad3";
            case System.Windows.Input.Key.NumPad4: return "Numpad4";
            case System.Windows.Input.Key.NumPad5: return "Numpad5";
            case System.Windows.Input.Key.NumPad6: return "Numpad6";
            case System.Windows.Input.Key.NumPad7: return "Numpad7";
            case System.Windows.Input.Key.NumPad8: return "Numpad8";
            case System.Windows.Input.Key.NumPad9: return "Numpad9";
            case System.Windows.Input.Key.Divide: return "NumpadDiv";
            case System.Windows.Input.Key.Multiply: return "NumpadMult";
            case System.Windows.Input.Key.Subtract: return "NumpadSub";
            case System.Windows.Input.Key.Add: return "NumpadAdd";
            case System.Windows.Input.Key.Decimal: return "NumpadDot";
            case System.Windows.Input.Key.LeftShift: return "LShift";
            case System.Windows.Input.Key.RightShift: return "RShift";
            case System.Windows.Input.Key.LeftCtrl: return "LCtrl";
            case System.Windows.Input.Key.RightCtrl: return "RCtrl";
            case System.Windows.Input.Key.LeftAlt: return "LAlt";
            case System.Windows.Input.Key.RightAlt: return "RAlt";
            case System.Windows.Input.Key.LWin: return "LWin";
            case System.Windows.Input.Key.RWin: return "RWin";
            case System.Windows.Input.Key.Apps: return "AppsKey";
            case System.Windows.Input.Key.CapsLock: return "CapsLock";
            case System.Windows.Input.Key.PrintScreen: return "PrintScreen";
            case System.Windows.Input.Key.Scroll: return "ScrollLock";
            case System.Windows.Input.Key.Pause: return "Pause";
        }
        return "";
    }

    private System.Collections.Generic.Dictionary<string, DateTime> lastEventSendTimes = new System.Collections.Generic.Dictionary<string, DateTime>();

    private void DumpState(string cName, string eName)
    {
        var ctrl = FindControlByPath(cName) as FrameworkElement;
        if (ctrl != null)
        {
            string tag = ctrl.Tag as string ?? "";

            if (eName == "TextChanged" && !ctrl.IsKeyboardFocusWithin && !tag.Contains("AllowPassive")) return;
            if (eName == "ValueChanged" && !ctrl.IsMouseOver && !ctrl.IsKeyboardFocusWithin && !ctrl.IsMouseCaptured && !tag.Contains("AllowPassive")) return;

            if (tag.Contains("Throttle"))
            {
                int delay = 50;
                var match = System.Text.RegularExpressions.Regex.Match(tag, @"Throttle:(\d+)");
                if (match.Success) delay = int.Parse(match.Groups[1].Value);

                string key = cName + "|" + eName;
                if (lastEventSendTimes.ContainsKey(key))
                {
                    if ((DateTime.Now - lastEventSendTimes[key]).TotalMilliseconds < delay)
                    {
                        return;
                    }
                }
                lastEventSendTimes[key] = DateTime.Now;
            }
        }

        if (eName == "MouseMove" || eName == "PreviewMouseMove")
        {
            if ((DateTime.Now - lastSendMouseMove).TotalMilliseconds < 16) return;
            lastSendMouseMove = DateTime.Now;
        }
        var sb = new StringBuilder("EVENT|" + winId + "|" + cName + "|" + eName + "\n");
        if (LightweightEvents)
        {
            // Lightweight mode: only send the triggering control's value.
            // Callbacks should use ui.Query() for additional values.
            string triggerVal = GetControlValue(cName);
            if (triggerVal != null)
            {
                sb.Append(cName + "=" + BridgeUtil.LengthPrefix(triggerVal) + "\n");
            }
        }
        else
        {
            // Full mode (default): send all tracked controls' values.
            // Backwards compatible — callbacks can read any tracked control from state map.
            sb.Append(CollectState());
        }
        SendToAhkAsync(sb.ToString());
    }

    private void SendToAhkAsync(string text)
    {
        lock (_asyncSendLock)
        {
            _asyncSendQueue.Enqueue(text);
            if (_asyncSendWorkerRunning)
                return;
            _asyncSendWorkerRunning = true;
        }

        System.Threading.ThreadPool.QueueUserWorkItem(_ => DrainAsyncSendQueue());
    }

    private void DrainAsyncSendQueue()
    {
        int consecutiveFail = 0;
        while (true)
        {
            string text;
            lock (_asyncSendLock)
            {
                if (_asyncSendQueue.Count == 0)
                {
                    _asyncSendWorkerRunning = false;
                    return;
                }
                text = _asyncSendQueue.Dequeue();
            }
            bool ok = false;
            try { ok = SendToAhk(text); }
            catch { }
            if (ok)
            {
                consecutiveFail = 0;
                continue;
            }
            // AHK 连续不取消息：队列里再堆着的也是过期事件，丢掉比让它越积越晚更好。
            // 下次 Enqueue 会重新拉起 worker。
            if (++consecutiveFail >= 3)
            {
                lock (_asyncSendLock)
                {
                    _asyncSendQueue.Clear();
                    _asyncSendWorkerRunning = false;
                }
                return;
            }
        }
    }

    private bool SendToAhk(string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        int size = bytes.Length + 1;
        IntPtr buf = Marshal.AllocHGlobal(size);
        Marshal.Copy(bytes, 0, buf, bytes.Length);
        Marshal.WriteByte(buf, bytes.Length, 0);
        var cds = new COPYDATASTRUCT { cbData = size, lpData = buf };
        IntPtr result;
        // 500ms 超时：原来是无超时 SendMessage，AHK 主线程在处理长任务时会把手
        // 唯一的发送 worker 永久挂住，之后所有 UI 事件都堵在队列里、界面看着像卡死。
        // 这里超时就放弃这一条，worker 继续处理后面的。
        IntPtr ok = SendMessageTimeout(ahkHwnd, 0x004A, IntPtr.Zero, ref cds, 0x0000, 500, out result);
        if (ok != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(buf);
            return true;
        }
        // 超时不能释放：消息可能仍排在 AHK 队列里等处理，回收会变成读已释放内存。
        // 只在对方长时间不响应时发生，单条几十字节，随进程退出回收。
        return false;
    }

}
