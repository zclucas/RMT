// =============================================================================
// 逻辑树拖拽（引擎内实现）：命中测试、插入线、跟手幽灵全部在 WPF 线程跑，
// 松手时才回报 AHK 一次（TreeDrop）。做法与 BallDrag / CanvasViewport 一致。
// AHK 侧不再在事件回调里逐帧同步查询引擎——那条路会因嵌套消息拿不到应答而失效。
// =============================================================================
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

public partial class AhkWpfEngine
{
    private FrameworkElement _tdLb;        // 目标树（ListBox，行 Tag = 节点 id）
    private FrameworkElement _tdLine;      // 插入线 Border
    private Popup _tdGhost;                // 跟手幽灵 Popup
    private TextBlock _tdGhostTxt;         // 幽灵文本
    private FrameworkElement _tdSrcItem;   // 起拖的源行（取幽灵文本）
    private bool _tdArmed;                 // 已按下，未超过拖动阈值
    private bool _tdActive;                // 已进入拖拽
    private bool _tdExternal;              // 外部拖入（左侧指令面板 → 树）
    private int _tdStartX, _tdStartY;
    private string _tdSource = "";
    private string _tdTarget = "";
    private string _tdSlot = "";
    private string _tdGhostText = "";      // 外部拖入的幽灵文本，真正起拖时才填

    private string TdName()
    {
        var fe = _tdLb;
        return fe != null && !string.IsNullOrEmpty(fe.Name) ? fe.Name : "Window";
    }

    // 树内拖拽：把 ListBox 与它的插入线/幽灵接起来。spec = "插入线名|幽灵名|幽灵文本名"
    internal void AttachTreeDrag(object ctrl, string spec)
    {
        var lb = ctrl as FrameworkElement;
        if (lb == null)
            return;
        ResolveTreeDragParts(spec);
        _tdLb = lb;
        lb.PreviewMouseLeftButtonDown -= OnTreeDragDown;
        lb.PreviewMouseLeftButtonDown += OnTreeDragDown;
        lb.PreviewMouseMove -= OnTreeDragMove;
        lb.PreviewMouseMove += OnTreeDragMove;
        lb.PreviewMouseLeftButtonUp -= OnTreeDragUp;
        lb.PreviewMouseLeftButtonUp += OnTreeDragUp;
        lb.LostMouseCapture -= OnTreeDragLostCapture;
        lb.LostMouseCapture += OnTreeDragLostCapture;
    }

    private void ResolveTreeDragParts(string spec)
    {
        string lineName = "", ghostName = "", txtName = "";
        string[] sp = (spec ?? "").Split('|');
        if (sp.Length >= 1) lineName = sp[0].Trim();
        if (sp.Length >= 2) ghostName = sp[1].Trim();
        if (sp.Length >= 3) txtName = sp[2].Trim();
        _tdLine = string.IsNullOrEmpty(lineName) ? null : FindControlByPath(lineName) as FrameworkElement;
        _tdGhost = string.IsNullOrEmpty(ghostName) ? null : FindControlByPath(ghostName) as Popup;
        _tdGhostTxt = string.IsNullOrEmpty(txtName) ? null : FindControlByPath(txtName) as TextBlock;
    }

    // 外部拖入：左侧指令面板按下后调用。treeName 为落点树，text 为幽灵显示文本。
    // spec 同上；为空时沿用 treeName 上次 AttachTreeDrag 接好的那套控件。
    internal void BeginExternalTreeDrag(string treeName, string text, string spec)
    {
        var lb = FindControlByPath(treeName) as FrameworkElement;
        if (lb == null)
            return;
        if (!string.IsNullOrEmpty(spec))
            ResolveTreeDragParts(spec);
        _tdLb = lb;
        _tdExternal = true;
        _tdArmed = true;
        // 先不进入拖拽态。左侧按钮多数只是「点击新增」，按下就弹幽灵会让点击也像拖拽；
        // 而且一旦 Up 派发不到（点击直接开了子窗就会这样），幽灵和拖拽态会一直挂着，
        // 之后树点不动、窗口也关不掉。
        _tdActive = false;
        _tdSource = "";
        _tdTarget = "";
        _tdSlot = "";
        _tdSrcItem = null;
        _tdGhostText = text ?? "";

        POINT p;
        if (GetCursorPos(out p))
        {
            _tdStartX = p.x;
            _tdStartY = p.y;
        }

        if (_tdGhost != null)
            _tdGhost.IsOpen = false;

        win.PreviewMouseMove -= OnTreeDragMoveExternal;
        win.PreviewMouseMove += OnTreeDragMoveExternal;
        win.PreviewMouseLeftButtonUp -= OnTreeDragUpExternal;
        win.PreviewMouseLeftButtonUp += OnTreeDragUpExternal;
        // 点击可能直接开出子窗，之后 Up 就收不到了：窗口一失活就收尾
        win.Deactivated -= OnWindowDeactivatedCancelDrag;
        win.Deactivated += OnWindowDeactivatedCancelDrag;
    }

    private void OnWindowDeactivatedCancelDrag(object sender, EventArgs e)
    {
        if (_tdExternal)
            CancelExternalTreeDrag();
    }

    private void OnTreeDragDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.ChangedButton != System.Windows.Input.MouseButton.Left || _tdExternal)
            return;
        POINT p;
        if (!GetCursorPos(out p))
            return;
        _tdStartX = p.x;
        _tdStartY = p.y;
        _tdArmed = true;
        _tdActive = false;
        _tdSource = "";
        _tdTarget = "";
        _tdSlot = "";
        _tdSrcItem = null;
        // 不设 Handled：ListBoxItem 的选中照常由 WPF 处理
    }

    private void OnTreeDragMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_tdExternal || !_tdArmed || _tdLb == null)
            return;
        // 捕获期间若左键已经松开（松开发生在窗口外、Up 没派发过来），立刻收尾并释放捕获。
        // 捕获是 UI 线程级的：一旦泄漏，同一引擎里所有窗口都点不动。
        if (_tdActive && System.Windows.Input.Mouse.LeftButton != System.Windows.Input.MouseButtonState.Pressed)
        {
            string treeName = TdName();
            ResetTreeDrag();
            SendToAhkAsync("EVENT|" + winId + "|" + treeName + "|TreeDragCancel|\n");
            return;
        }
        POINT p;
        if (!GetCursorPos(out p))
            return;

        if (!_tdActive)
        {
            // 位移阈值：和原 AHK 侧一致，避免点一下就起拖
            if (Math.Abs(p.x - _tdStartX) <= 8 && Math.Abs(p.y - _tdStartY) <= 8)
                return;
            ListBoxItem srcItem;
            string srcTag, srcSlot;
            if (!HitTreeItem(_tdLb, e.GetPosition(_tdLb), out srcItem, out srcTag, out srcSlot)
                || string.IsNullOrEmpty(srcTag))
            {
                _tdArmed = false;
                return;
            }
            _tdSource = srcTag;
            _tdSrcItem = srcItem;
            _tdActive = true;
            try { _tdLb.CaptureMouse(); } catch { }
            if (_tdGhostTxt != null)
                _tdGhostTxt.Text = ItemText(srcItem);
            // 通知 AHK 进入拖拽态（它要暂停树的整棵重建，否则拖到一半列表被重建会丢源）
            SendToAhkAsync("EVENT|" + winId + "|" + TdName() + "|TreeDragStart|\n");
        }
        UpdateTreeDragVisual(e.GetPosition(_tdLb));
    }

    private void OnTreeDragUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (_tdExternal || !_tdArmed)
            return;
        bool wasActive = _tdActive;
        string src = _tdSource, tgt = _tdTarget, slot = _tdSlot;
        string treeName = TdName();
        ResetTreeDrag();
        if (!wasActive || string.IsNullOrEmpty(src))
            return;
        EmitTreeDrop("TreeDrop", src, tgt, slot, treeName);
    }

    private void OnTreeDragLostCapture(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_tdExternal || !_tdActive)
        {
            _tdArmed = false;
            return;
        }
        string treeName = TdName();
        ResetTreeDrag();
        SendToAhkAsync("EVENT|" + winId + "|" + treeName + "|TreeDragCancel|\n");
    }

    // --- 外部拖入 ---------------------------------------------------------

    private void OnTreeDragMoveExternal(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_tdExternal || _tdLb == null)
            return;
        if (!System.Windows.Input.Mouse.LeftButton.Equals(System.Windows.Input.MouseButtonState.Pressed))
        {
            CancelExternalTreeDrag();
            return;
        }
        if (!_tdActive)
        {
            POINT p;
            if (!GetCursorPos(out p))
                return;
            // 阈值没到就还当点击处理，不弹幽灵
            if (Math.Abs(p.x - _tdStartX) <= 8 && Math.Abs(p.y - _tdStartY) <= 8)
                return;
            _tdActive = true;
            if (_tdGhostTxt != null)
                _tdGhostTxt.Text = _tdGhostText ?? "";
            if (_tdGhost != null)
                _tdGhost.IsOpen = true;
        }
        UpdateTreeDragVisual(e.GetPosition(_tdLb));
    }

    private void OnTreeDragUpExternal(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!_tdExternal)
            return;
        bool wasActive = _tdActive;
        string tgt = _tdTarget, slot = _tdSlot, treeName = TdName();
        CancelExternalTreeDrag();
        // 只是点击（没超过拖动阈值）：交给按钮自己的 Click，不要当成「拖到树外」再开一次窗
        if (!wasActive)
            return;
        if (string.IsNullOrEmpty(tgt))
        {
            SendToAhkAsync("EVENT|" + winId + "|" + treeName + "|TreeDropExternal|\n");
            return;
        }
        EmitTreeDrop("TreeDropExternal", "", tgt, slot, treeName);
    }

    private void CancelExternalTreeDrag()
    {
        _tdExternal = false;
        _tdArmed = false;
        _tdActive = false;
        _tdTarget = "";
        _tdSlot = "";
        _tdGhostText = "";
        if (_tdLine != null)
            _tdLine.Visibility = Visibility.Collapsed;
        if (_tdGhost != null)
            _tdGhost.IsOpen = false;
        win.PreviewMouseMove -= OnTreeDragMoveExternal;
        win.PreviewMouseLeftButtonUp -= OnTreeDragUpExternal;
        win.Deactivated -= OnWindowDeactivatedCancelDrag;
    }

    // --- 公共 -------------------------------------------------------------

    private void EmitTreeDrop(string kind, string src, string tgt, string slot, string treeName)
    {
        string payload = (src ?? "") + "|" + (tgt ?? "") + "|" + (slot ?? "");
        SendToAhkAsync("EVENT|" + winId + "|" + treeName + "|" + kind + "|"
            + BridgeUtil.LengthPrefix(payload) + "\n");
    }

    private void ResetTreeDrag()
    {
        _tdArmed = false;
        _tdActive = false;
        _tdSource = "";
        _tdTarget = "";
        _tdSlot = "";
        _tdSrcItem = null;
        if (_tdLine != null)
            _tdLine.Visibility = Visibility.Collapsed;
        if (_tdGhost != null)
            _tdGhost.IsOpen = false;
        if (_tdLb != null && _tdLb.IsMouseCaptured)
        {
            try { _tdLb.ReleaseMouseCapture(); } catch { }
        }
    }

    // 插入线定位 + 幽灵跟手。pos 为树本地坐标（相对 ListBox）。
    private void UpdateTreeDragVisual(System.Windows.Point pos)
    {
        if (_tdLb == null)
            return;
        ListBoxItem item;
        string tag, slot;
        bool ok = HitTreeItem(_tdLb, pos, out item, out tag, out slot);
        _tdTarget = ok ? tag : "";
        _tdSlot = ok ? slot : "";

        if (_tdLine != null)
        {
            bool placed = false;
            // 引擎用 .NET Framework 的 csc 编译（默认 C# 5），不要写 `is T x` 模式匹配
            var host = _tdLine.Parent as FrameworkElement;
            if (ok && item != null && host != null)
            {
                try
                {
                    System.Windows.Point o = item.TranslatePoint(new System.Windows.Point(0, 0), host);
                    double y = o.Y + (slot == "top" ? 0 : item.ActualHeight) - 1;
                    _tdLine.Margin = new Thickness(0, Math.Max(0, y), 0, 0);
                    _tdLine.HorizontalAlignment = HorizontalAlignment.Stretch;
                    _tdLine.Visibility = Visibility.Visible;
                    placed = true;
                }
                catch { }
            }
            if (!placed)
                _tdLine.Visibility = Visibility.Collapsed;
        }

        if (_tdGhost != null)
        {
            POINT p;
            if (GetCursorPos(out p))
            {
                System.Windows.Point dip = new System.Windows.Point(p.x, p.y);
                var src = PresentationSource.FromVisual(_tdLb);
                if (src != null && src.CompositionTarget != null)
                    dip = src.CompositionTarget.TransformFromDevice.Transform(dip);
                _tdGhost.HorizontalOffset = dip.X + 18;
                _tdGhost.VerticalOffset = dip.Y + 14;
                _tdGhost.IsOpen = true;
            }
        }
    }

    // 命中：返回该点压着的行；行间空白按 Y 落到覆盖它的那一行。
    private bool HitTreeItem(FrameworkElement lb, System.Windows.Point pos,
        out ListBoxItem item, out string tag, out string slot)
    {
        item = null;
        tag = "";
        slot = "";
        var hit = VisualTreeHelper.HitTest(lb, pos);
        if (hit != null)
        {
            DependencyObject d = hit.VisualHit;
            while (d != null && !(d is ListBoxItem) && !(d is ListBox))
                d = VisualTreeHelper.GetParent(d);
            item = d as ListBoxItem;
        }
        if (item == null)
        {
            var listBox = lb as ListBox;
            if (listBox != null)
            {
                foreach (object obj in listBox.Items)
                {
                    var li = listBox.ItemContainerGenerator.ContainerFromItem(obj) as ListBoxItem;
                    if (li == null)
                        continue;
                    try
                    {
                        System.Windows.Point o = li.TranslatePoint(new System.Windows.Point(0, 0), lb);
                        if (pos.Y >= o.Y && pos.Y < o.Y + li.ActualHeight)
                        {
                            item = li;
                            break;
                        }
                    }
                    catch { }
                }
            }
        }
        if (item == null || item.Tag == null)
            return false;
        tag = item.Tag.ToString();
        if (string.IsNullOrEmpty(tag))
            return false;
        try
        {
            System.Windows.Point o = item.TranslatePoint(new System.Windows.Point(0, 0), lb);
            slot = (pos.Y < o.Y + item.ActualHeight / 2.0) ? "top" : "bottom";
        }
        catch { }
        return true;
    }

    private string ItemText(DependencyObject root)
    {
        var tb = BridgeUtil.FindVisualChild<TextBlock>(root);
        return tb != null && tb.Text != null ? tb.Text : "";
    }
}
