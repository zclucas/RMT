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

    private void BindEvent(string ctrlName, string eventName, int fpsLimit = 0, bool queueLimited = false)
    {
        string eventKey = ctrlName + ":" + eventName;
        object ctrl = ctrlName == "Window" ? (object)win : FindControlByPath(ctrlName);
        if (ctrl == null)
        {
            _boundEvents.Remove(eventKey);
            if (_boundEventCtrls != null)
                _boundEventCtrls.Remove(eventKey);
            try
            {
                System.IO.File.AppendAllText(
                    GetLogPath("AhkWpfDebug.log"),
                    string.Format("BindEvent info: Control '{0}' not found for event '{1}' (may be dynamic)\n", ctrlName, eventName)
                );
            } catch { }
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

            // KeyDown:Return / PreviewKeyDown:Delete 等：绑底层键盘事件，仅在目标键时上报
            if (eventName.StartsWith("KeyDown:") || eventName.StartsWith("PreviewKeyDown:"))
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
                            if (e.Key.ToString() == keyFilter || (keyFilter == "Return" && e.Key == System.Windows.Input.Key.Enter))
                            {
                                DumpStateWithArgs(ctrlName, baseEvt, e);
                                // Enter：交给 AHK（发送 / Shift+换行），阻止 TextBox 再插入换行
                                if (keyFilter == "Return")
                                    e.Handled = true;
                            }
                        };
                    }
                    else
                    {
                        ue.KeyDown += (s, e) =>
                        {
                            if (e.Key.ToString() == keyFilter || (keyFilter == "Return" && e.Key == System.Windows.Input.Key.Enter))
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
            evt.AddEventHandler(ctrl, lambda.Compile());
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
                    sb.Append("ClickCount=" + BridgeUtil.LengthPrefix(((System.Windows.Input.MouseButtonEventArgs)e).ClickCount.ToString()) + "\n");
                SendToAhkAsync(sb.ToString());
                return;
            }
        }
        DumpState(cName, eName);
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
            try { SendToAhk(text); }
            catch { }
        }
    }

    private void SendToAhk(string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        var cds = new COPYDATASTRUCT { cbData = bytes.Length + 1, lpData = Marshal.AllocHGlobal(bytes.Length + 1) };
        Marshal.Copy(bytes, 0, cds.lpData, bytes.Length);
        Marshal.WriteByte(cds.lpData, bytes.Length, 0);
        SendMessage(ahkHwnd, 0x004A, IntPtr.Zero, ref cds);
        Marshal.FreeHGlobal(cds.lpData);
    }

}
