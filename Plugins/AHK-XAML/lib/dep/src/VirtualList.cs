// =============================================================================
// Virtual list: VL_* host & data model
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
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Markup;
using Color = System.Windows.Media.Color;


// ---- Epic5 虚拟列表（VL_* 命令，只加不改既有桥接契约）----
// 载体：ListBox + ObservableCollection + DataTemplate + VirtualizingStackPanel(Recycling)。
// 行 ID 约定 R<t>_<i>，折叠头 F<t>_<f>；字段分隔 \x1F(US)、行分隔 \x1E(RS)。
// 事件回传：EVENT|<winId>|<listName>|VL_CLICK|LengthPrefix("id\x1Faction")
//           EVENT|<winId>|<listName>|VL_CHANGE|LengthPrefix("id\x1Ffield\x1Fvalue")
//           EVENT|<winId>|<listName>|VL_COMMIT_ALL|首行空，后续 k=LengthPrefix("id\x1Ffield\x1Fvalue")
// 批量结构变更集合：ResetTo 只发一次 Reset 通知。逐条 RemoveAt/Insert 触发容器回收抖动
// （ComboBox 重绑复位→伪 SelectionChanged→重入布局），折叠 250ms 即此根源。
public class VListCollection : System.Collections.ObjectModel.ObservableCollection<object>
{
    public void ResetTo(System.Collections.Generic.IList<object> newItems)
    {
        this.Items.Clear();
        for (int i = 0; i < newItems.Count; i++)
            this.Items.Add(newItems[i]);
        this.OnCollectionChanged(new System.Collections.Specialized.NotifyCollectionChangedEventArgs(
            System.Collections.Specialized.NotifyCollectionChangedAction.Reset));
    }
}

public class VirtualListHost
{
    private static readonly System.Collections.Generic.Dictionary<string, VirtualListHost> _hosts =
        new System.Collections.Generic.Dictionary<string, VirtualListHost>();

    private System.Windows.Window _win;
    private string _winId, _listName;
    private Action<string> _send;
    private ListBox _lb;
    private VListCollection _items = new VListCollection();
    private System.Collections.Generic.Dictionary<string, object> _byId =
        new System.Collections.Generic.Dictionary<string, object>();
    private bool _hooked;
    private bool _compact;
    private string _anchorId;
    private bool _suppressCommit;
    private bool _suppressChange; // 结构操作布局期：压制容器回收产生的伪 SelectionChanged/LostFocus
    private string _rowSelId = "";
    // §11 VL 拖拽：按下起点 + 是否已武装（交互控件上不启动）
    private Point _dragStartPoint;
    private bool _dragArmed;
    private Popup _ghostPopup;
    private TextBlock _ghostText;
    private Popup _insertPopup;
    private Border _insertBar;
    private ListBoxItem _insertTarget;
    private bool _insertBefore;
    // 表类型 enabled 标志（VL_INIT 首行 T<t>_0 注入，per host 恒定）；默认 true 兼容不带标志的调用
    private bool _tkBtnEn = true;
    private bool _tkTypeEn = true;
    private bool _loopEn = true;
    private bool _foldTKTypeEn = true;
    // 吸顶折叠头：overlay 容器 + 当前钉住的 fold + 惰性 ScrollViewer
    private System.Windows.Controls.ContentControl _sticky;
    private VListFold _stickyFold;
    private System.Windows.Controls.ScrollViewer _sv;

    public static void Dispatch(System.Windows.Window win, string winId, ListBox lb, string cmd, string val, Action<string> send)
    {
        string key = winId + "|" + lb.Name;
        VirtualListHost host;
        if (!_hosts.TryGetValue(key, out host))
        {
            host = new VirtualListHost(win, winId, lb.Name, send);
            _hosts[key] = host;
        }
        host.Link(lb);
        switch (cmd)
        {
            case "VL_INIT": host.Rebuild(val); break;
            case "VL_ROW": host.SetRow(val); break;
            case "VL_FOLD": host.SetFold(val); break;
            case "VL_FF": host.SetFoldForbid(val); break;
            case "VL_MOVE": host.Move(val); break;
            case "VL_RELAYOUT": host.Relayout(); break;
            case "VL_COMMIT_ALL": host.CommitAll(); break;
            case "VL_COMPACT": host.SetCompact(val); break;
            case "VL_SEL": host.SetRowSel(val); break;
        }
    }

    private VirtualListHost(System.Windows.Window win, string winId, string listName, Action<string> send)
    {
        _win = win; _winId = winId; _listName = listName; _send = send;
    }

    private void Link(ListBox lb)
    {
        if (_lb == lb) return;
        _lb = lb;
        if (_lb != null && !_hooked)
        {
            _hooked = true;
            _lb.AddHandler(ButtonBase.ClickEvent, new RoutedEventHandler(OnClick));
            _lb.AddHandler(Selector.SelectionChangedEvent, new SelectionChangedEventHandler(OnSelectionChanged));
            _lb.AddHandler(System.Windows.UIElement.LostKeyboardFocusEvent, new System.Windows.Input.KeyboardFocusChangedEventHandler(OnLostFocus));
            _lb.AddHandler(System.Windows.UIElement.MouseRightButtonUpEvent, new System.Windows.Input.MouseButtonEventHandler(OnRightUp), true);
            // 点击折叠按钮时 WPF 会 BringIntoView，把上面的模块顶走；展开/折叠禁止自动滚入视口
            _lb.RequestBringIntoView += (s, e) => { e.Handled = true; };
            // §11 VL 拖拽排序：行/折叠头按住拖动 → VL_DROP 回传（srcId\x1FtgtId\x1F0前|1后）
            _lb.AllowDrop = true;
            _dragArmed = false;
            _lb.PreviewMouseLeftButtonDown += (s, e) =>
            {
                _dragArmed = false;
                FrameworkElement fe = e.OriginalSource as FrameworkElement;
                DependencyObject d = fe;
                bool fromHandle = false;
                bool interactive = false;
                while (d != null)
                {
                    FrameworkElement el = d as FrameworkElement;
                    if (el != null && (el.Tag as string) == "DragHandle")
                    {
                        fromHandle = true;
                        break;
                    }
                    if (d is ButtonBase || d is TextBox || d is ComboBox || d is CheckBox || d is ScrollBar)
                    {
                        interactive = true;
                        break;
                    }
                    d = System.Windows.Media.VisualTreeHelper.GetParent(d);
                }
                ListBoxItem under = GetItemUnderMouse(_lb, e.GetPosition(_lb));
                VLItem underVi = under != null ? under.DataContext as VLItem : null;
                if (underVi is VListRow && !interactive)
                    SendClick(underVi.Id, "Select");
                else if (underVi is VListRow && (d is TextBox || d is ComboBox))
                    SendClick(underVi.Id, "Field");
                if (interactive && !fromHandle)
                    return;
                if (!fromHandle && !(underVi is VListFold))
                    return;
                _dragStartPoint = e.GetPosition(null);
                _dragArmed = true;
            };
            _lb.PreviewMouseMove += (s, e) =>
            {
                if (!_dragArmed || e.LeftButton != System.Windows.Input.MouseButtonState.Pressed)
                    return;
                Point pos = e.GetPosition(null);
                if (Math.Abs(pos.X - _dragStartPoint.X) < SystemParameters.MinimumHorizontalDragDistance &&
                    Math.Abs(pos.Y - _dragStartPoint.Y) < SystemParameters.MinimumVerticalDragDistance)
                    return;
                _dragArmed = false;
                ListBoxItem item = GetItemUnderMouse(_lb, e.GetPosition(_lb));
                if (item == null) return;
                VLItem vi = item.DataContext as VLItem;
                if (vi == null || vi is VListAddFold) return;
                EnsureDragUi();
                _ghostText.Text = GhostLabel(vi);
                try
                {
                    DataObject dobj = new DataObject("VLRowId", vi.Id);
                    DragDrop.DoDragDrop(_lb, dobj, DragDropEffects.Move);
                }
                catch { }
                HideDragUi();
            };
            _lb.GiveFeedback += (s, e) =>
            {
                e.UseDefaultCursors = false;
                try { Mouse.SetCursor(Cursors.Arrow); } catch { }
                EnsureDragUi();
                Point dip = CursorDip(_lb);
                if (_ghostPopup.IsOpen
                    && Math.Abs(dip.X + 18 - _ghostPopup.HorizontalOffset) < 2
                    && Math.Abs(dip.Y + 14 - _ghostPopup.VerticalOffset) < 2)
                {
                    e.Handled = true;
                    return;
                }
                _ghostPopup.HorizontalOffset = dip.X + 18;
                _ghostPopup.VerticalOffset = dip.Y + 14;
                _ghostPopup.IsOpen = true;
                e.Handled = true;
            };
            _lb.DragOver += (s, e) =>
            {
                if (!e.Data.GetDataPresent("VLRowId")) return;
                e.Effects = DragDropEffects.Move;
                ListBoxItem target = GetItemUnderMouse(_lb, e.GetPosition(_lb));
                if (target == null || target.DataContext is VListAddFold)
                {
                    e.Handled = true;
                    return;
                }
                ShowInsertMarker(target, InsertBefore(target, e.GetPosition(target).Y));
                e.Handled = true;
            };
            _lb.DragLeave += (s, e) =>
            {
                Point p = e.GetPosition(_lb);
                if (p.X < 0 || p.Y < 0 || p.X >= _lb.ActualWidth || p.Y >= _lb.ActualHeight)
                    HideInsertMarker();
            };
            _lb.Drop += (s, e) =>
            {
                if (!e.Data.GetDataPresent("VLRowId"))
                {
                    HideDragUi();
                    return;
                }
                string srcId = (string)e.Data.GetData("VLRowId");
                ListBoxItem target = GetItemUnderMouse(_lb, e.GetPosition(_lb));
                ListBoxItem markerTarget = _insertTarget;
                bool markerBefore = _insertBefore;
                bool before = ReferenceEquals(target, markerTarget)
                    ? markerBefore
                    : (target != null && InsertBefore(target, e.GetPosition(target).Y));
                HideDragUi();
                if (target == null && markerTarget != null)
                {
                    target = markerTarget;
                    before = markerBefore;
                }
                if (target == null) return;
                VLItem tvi = target.DataContext as VLItem;
                if (tvi == null) return;
                if (tvi.Id == srcId)
                {
                    object srcObj;
                    if (!_byId.TryGetValue(srcId, out srcObj)) return;
                    int si = _items.IndexOf(srcObj);
                    if (si < 0) return;
                    int ni = before ? si - 1 : si + 1;
                    if (ni < 0 || ni >= _items.Count) return;
                    VLItem nb = _items[ni] as VLItem;
                    if (nb == null || nb is VListAddFold) return;
                    tvi = nb;
                    before = !before;
                }
                if (tvi is VListAddFold)
                    before = false;
                SendDrop(srcId, tvi.Id, before);
                e.Handled = true;
            };
            _lb.ItemTemplateSelector = new VLTemplateSelector(_win, this);
            // 容器模板剥成裸 ContentPresenter：SelectionMode=Single 仅为合法值，实际无选中高亮/键盘焦点
            var lbiStyle = new System.Windows.Style(typeof(System.Windows.Controls.ListBoxItem));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.FocusableProperty, false));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.MarginProperty, new Thickness(0)));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.PaddingProperty, new Thickness(0)));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.UIElement.ClipToBoundsProperty, false));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.FrameworkElement.UseLayoutRoundingProperty, false));
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
            var lbiFactory = new System.Windows.FrameworkElementFactory(typeof(System.Windows.Controls.ContentPresenter));
            lbiFactory.SetValue(System.Windows.Controls.ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Stretch);
            var lbiTemplate = new System.Windows.Controls.ControlTemplate(typeof(System.Windows.Controls.ListBoxItem))
            { VisualTree = lbiFactory };
            lbiStyle.Setters.Add(new System.Windows.Setter(System.Windows.Controls.ListBoxItem.TemplateProperty, lbiTemplate));
            _lb.ItemContainerStyle = lbiStyle;
            // 吸顶折叠头 overlay（VLSticky_<t>）：惰性查找 + 复用 RmtFoldHeader 模板 + 同一套事件回传
            EnsureSticky();
        }
    }

    // 惰性查找 overlay：视觉树未加载时找不到，窗口 Loaded 后重试；滚动/结构操作也触发
    private void EnsureSticky()
    {
        if (_sticky != null || _win == null) return;
        string sn = _listName.Replace("FoldList_", "VLSticky_"); // FoldList_1 → VLSticky_1
        _sticky = FindControlByName(_win, sn) as System.Windows.Controls.ContentControl;
        if (_sticky == null)
            _sticky = _win.FindName(sn) as System.Windows.Controls.ContentControl;
        if (_sticky == null && !_win.IsLoaded)
        {
            // 窗口未加载完：VL_INIT 可能早于视觉树就绪，Loaded 后重试一次并立即算吸顶
            _win.Loaded += (s, e) => { EnsureSticky(); UpdateSticky(); };
            return;
        }
        if (_sticky != null)
        {
            _sticky.ContentTemplate = FoldHeaderTemplate();
            _sticky.AddHandler(ButtonBase.ClickEvent, new RoutedEventHandler(OnClick));
            _sticky.AddHandler(System.Windows.UIElement.LostKeyboardFocusEvent, new System.Windows.Input.KeyboardFocusChangedEventHandler(OnLostFocus));
            _sticky.AddHandler(System.Windows.UIElement.MouseRightButtonUpEvent, new System.Windows.Input.MouseButtonEventHandler(OnRightUp), true);
            _sticky.AddHandler(Selector.SelectionChangedEvent, new SelectionChangedEventHandler(OnSelectionChanged));
        }
    }

    private System.Windows.DataTemplate FoldHeaderTemplate()
    {
        string key = _compact ? "RmtFoldHeaderC" : "RmtFoldHeader";
        object r = _win.FindResource(key);
        return r as System.Windows.DataTemplate;
    }

    public bool IsCompact { get { return _compact; } }

    private void SetCompact(string val)
    {
        bool on = val == "1";
        if (_compact == on)
            return;
        _compact = on;
        if (_sticky != null)
            _sticky.ContentTemplate = FoldHeaderTemplate();
        if (_lb != null && _items.Count > 0)
            Relayout();
    }

    // ---- 结构命令 ----

    private void Rebuild(string val)
    {
        double keepOff = CaptureScroll();
        _anchorId = FirstVisibleId();
        _byId.Clear();
        var newItems = new System.Collections.Generic.List<object>();
        VListFold inFold = null;
        string[] lines = val.Split('\x1E');
        foreach (string line in lines)
        {
            if (line.Length == 0) continue;
            string[] f = line.Split('\x1F');
            if (f.Length == 0 || f[0].Length == 0) continue;
            if (f[0][0] == 'T')
            {
                // 表类型标志行：T<t>_0\x1FtkBtnEn\x1FtkTypeEn\x1FloopEn\x1FfoldTKTypeEn
                _tkBtnEn = f.Length > 1 && f[1] == "1";
                _tkTypeEn = f.Length > 2 && f[2] == "1";
                _loopEn = f.Length > 3 && f[3] == "1";
                _foldTKTypeEn = f.Length > 4 && f[4] == "1";
                continue;
            }
            if (f[0][0] == 'A')
            {
                VListAddFold add = new VListAddFold();
                add.Id = f[0];
                _byId[add.Id] = add;
                newItems.Add(add);
                continue;
            }
            if (f[0][0] == 'F')
            {
                VListFold fo = new VListFold();
                fo.Id = f[0];
                fo.FoldRemark = f.Length > 1 ? f[1] : "";
                fo.FoldFront = f.Length > 2 ? f[2] : "";
                fo.FoldForbid = f.Length > 3 && f[3] == "1";
                fo.FoldTKType = f.Length > 4 ? ParseInt(f[4]) : 0;
                fo.FoldTK = f.Length > 5 ? f[5] : "";
                fo.Folded = f.Length > 6 && f[6] == "1";
                fo.ShowTKRow = f.Length > 7 && f[7] == "1";
                fo.FoldTKTypeEnabled = _foldTKTypeEn;
                _byId[fo.Id] = fo;
                newItems.Add(fo);
                inFold = fo.Folded ? fo : null; // 折叠态 fold 吸收入后续行
            }
            else if (inFold != null)
            {
                VListRow r = ParseRow(f);
                r.TKBtnEnabled = _tkBtnEn; r.TKTypeEnabled = _tkTypeEn; r.LoopEnabled = _loopEn;
                _byId[r.Id] = r;
                inFold.ChildRows.Add(r);
            }
            else
            {
                VListRow r = ParseRow(f);
                r.TKBtnEnabled = _tkBtnEn; r.TKTypeEnabled = _tkTypeEn; r.LoopEnabled = _loopEn;
                _byId[r.Id] = r;
                newItems.Add(r);
            }
        }
        MarkFoldRowFlags(newItems);
        if (_lb == null)
            return;
        // 结构未变（同模块内拖拽换位）：就地写回已有 VM，不 Reset、不重建容器，避免抖动和首帧底边丢失
        if (_items.Count > 0 && SameShape(_items, newItems))
        {
            AdoptItems(_items, newItems);
            ApplyRowSel();
            return;
        }
        ApplyReset(newItems, keepOff);
        ApplyRowSel();
        _stickyFold = null;
        // 视口已落定则不再二次 Reset（ContextIdle 会在首帧之后重排，切页签时偶发抖动）
        if (_lb.ActualHeight < 8)
            _lb.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new System.Action(() => Relayout()));
    }

    // 与折叠同一条显示路径：对现有对象再发一次 Reset，逼容器按已落定视口重测
    private void Relayout()
    {
        if (_lb == null || _items.Count == 0)
            return;
        double keepOff = CaptureScroll();
        var snap = new System.Collections.Generic.List<object>(_items);
        MarkFoldRowFlags(snap);
        ApplyReset(snap, keepOff);
    }

    private void ApplyReset(System.Collections.Generic.IList<object> newItems, double keepOff)
    {
        _suppressChange = true;
        _items.ResetTo(newItems);
        if (_lb == null)
        {
            _suppressChange = false;
            return;
        }
        if (_lb.ItemsSource != _items)
            _lb.ItemsSource = _items;
        RestoreScroll(keepOff);
        _lb.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new System.Action(() =>
        {
            _suppressChange = false;
            RestoreScroll(keepOff);
            UpdateSticky();
        }));
    }

    private static bool SameShape(System.Collections.Generic.IList<object> a, System.Collections.Generic.IList<object> b)
    {
        if (a.Count != b.Count)
            return false;
        for (int i = 0; i < a.Count; i++)
        {
            if (a[i].GetType() != b[i].GetType())
                return false;
        }
        return true;
    }

    private void AdoptItems(VListCollection dst, System.Collections.Generic.List<object> src)
    {
        _byId.Clear();
        for (int i = 0; i < dst.Count; i++)
        {
            AdoptOne(dst[i], src[i]);
            VLItem vi = dst[i] as VLItem;
            if (vi != null && !string.IsNullOrEmpty(vi.Id))
                _byId[vi.Id] = dst[i];
            VListFold fo = dst[i] as VListFold;
            if (fo != null)
            {
                for (int c = 0; c < fo.ChildRows.Count; c++)
                {
                    if (!string.IsNullOrEmpty(fo.ChildRows[c].Id))
                        _byId[fo.ChildRows[c].Id] = fo.ChildRows[c];
                }
            }
        }
    }

    private static void AdoptOne(object dst, object src)
    {
        VListRow dr = dst as VListRow, sr = src as VListRow;
        if (dr != null && sr != null)
        {
            dr.Id = sr.Id;
            dr.Remark = sr.Remark;
            dr.TKStr = sr.TKStr;
            dr.TKType = sr.TKType;
            dr.LoopText = sr.LoopText;
            dr.Forbid = sr.Forbid;
            dr.ColorHex = sr.ColorHex;
            dr.SeqNo = sr.SeqNo;
            dr.TKBtnEnabled = sr.TKBtnEnabled;
            dr.TKTypeEnabled = sr.TKTypeEnabled;
            dr.LoopEnabled = sr.LoopEnabled;
            dr.IsAltRow = sr.IsAltRow;
            dr.IsAltFold = sr.IsAltFold;
            dr.IsLastInFold = sr.IsLastInFold;
            dr.IsLastModule = sr.IsLastModule;
            dr.EditKind = sr.EditKind;
            dr.FoldForbid = sr.FoldForbid;
            FillSelMark(dr);
            return;
        }
        VListFold df = dst as VListFold, sf = src as VListFold;
        if (df != null && sf != null)
        {
            df.Id = sf.Id;
            df.FoldRemark = sf.FoldRemark;
            df.FoldFront = sf.FoldFront;
            df.FoldForbid = sf.FoldForbid;
            df.FoldTKType = sf.FoldTKType;
            df.FoldTK = sf.FoldTK;
            df.Folded = sf.Folded;
            df.HasBody = sf.HasBody;
            df.IsFirstFold = sf.IsFirstFold;
            df.IsLastFold = sf.IsLastFold;
            df.IsAltFold = sf.IsAltFold;
            df.ShowTKRow = sf.ShowTKRow;
            df.FoldTKTypeEnabled = sf.FoldTKTypeEnabled;
            df.ChildRows = sf.ChildRows;
            return;
        }
        VListAddFold da = dst as VListAddFold, sa = src as VListAddFold;
        if (da != null && sa != null)
            da.Id = sa.Id;
    }

    private void SetRow(string val)
    {
        string[] f = val.Split('\x1F');
        if (f.Length < 2) return;
        object o;
        if (!_byId.TryGetValue(f[0], out o)) return;
        VListRow r = o as VListRow;
        if (r == null) return;
        if (f.Length > 1) r.Remark = f[1];
        if (f.Length > 2) r.TKStr = f[2];
        if (f.Length > 3) r.TKType = ParseInt(f[3]);
        if (f.Length > 4) r.LoopText = f[4];
        if (f.Length > 5) r.Forbid = f[5] == "1";
        if (f.Length > 6) r.ColorHex = f[6];
        if (f.Length > 7) r.SeqNo = f[7];
        if (f.Length > 8) r.EditKind = f[8];
        // §23 网络宏扩展位（与 ParseRow 同布局：f[9]=网络表标志）
        if (f.Length > 9)
        {
            bool isNetRow = f[9] == "1";
            r.NetHelpVis = isNetRow ? "Visible" : "Collapsed";
            r.NetTypeVis = isNetRow ? "Collapsed" : "Visible";
        }
    }

    private void SetFold(string val)
    {
        string[] f = val.Split('\x1F');
        if (f.Length < 2) return;
        object o;
        if (!_byId.TryGetValue(f[0], out o)) return;
        VListFold fo = o as VListFold;
        if (fo == null) return;
        _anchorId = FirstVisibleId();
        bool fold = f[1] == "1";
        var newItems = new System.Collections.Generic.List<object>(_items.Count);
        if (fold && !fo.Folded)
        {
            fo.ChildRows.Clear();
            bool absorbing = false;
            foreach (object it in _items)
            {
                if (ReferenceEquals(it, fo)) { newItems.Add(fo); absorbing = true; }
                else if (absorbing && it is VListRow)
                {
                    VListRow r = (VListRow)it;
                    fo.ChildRows.Add(r);
                    _byId.Remove(r.Id);
                }
                else
                {
                    if (absorbing && !(it is VListRow)) absorbing = false; // 遇下一折叠头停止吸收
                    newItems.Add(it);
                }
            }
            fo.Folded = true;
        }
        else if (!fold && fo.Folded)
        {
            foreach (object it in _items)
            {
                newItems.Add(it);
                if (ReferenceEquals(it, fo))
                {
                    foreach (VListRow r in fo.ChildRows)
                    {
                        newItems.Add(r);
                        _byId[r.Id] = r;
                    }
                }
            }
            fo.ChildRows.Clear();
            fo.Folded = false;
        }
        else
        {
            return; // 已是目标态
        }
        MarkFoldRowFlags(newItems);
        double keepOff = CaptureScroll();
        ApplyReset(newItems, keepOff);
        ApplyRowSel();
    }

    private void SetRowSel(string id)
    {
        _rowSelId = id ?? "";
        ApplyRowSel();
        if (string.IsNullOrEmpty(id) || _lb == null) return;
        object o;
        if (!_byId.TryGetValue(id, out o)) return;
        int idx = _items.IndexOf(o);
        if (idx < 0) return;
        System.Windows.Controls.ScrollViewer sv = BridgeUtil.FindVisualChild<System.Windows.Controls.ScrollViewer>(_lb);
        if (sv == null) return;
        // 尽量把选中行滚入视口（折叠头 RequestBringIntoView 被拦，这里直接改偏移）
        double view = sv.ViewportHeight;
        double off = sv.VerticalOffset;
        if (idx < off)
            sv.ScrollToVerticalOffset(idx);
        else if (idx >= off + view - 0.5)
            sv.ScrollToVerticalOffset(Math.Max(0, idx - Math.Max(0, view - 1)));
    }

    private void ApplyRowSel()
    {
        string id = _rowSelId ?? "";
        foreach (var kv in _byId)
        {
            VListRow r = kv.Value as VListRow;
            if (r != null)
                r.RowSel = (id.Length > 0 && r.Id == id);
            VListFold fo = kv.Value as VListFold;
            if (fo != null)
            {
                foreach (VListRow cr in fo.ChildRows)
                    cr.RowSel = (id.Length > 0 && cr.Id == id);
            }
        }
    }

    // 模块禁用态增量刷新（避免 VL_INIT 全量重建导致虚拟行字号未再经 ApplyFonts 缩小）
    private void SetFoldForbid(string val)
    {
        string[] f = val.Split('\x1F');
        if (f.Length < 2) return;
        object o;
        if (!_byId.TryGetValue(f[0], out o)) return;
        VListFold fo = o as VListFold;
        if (fo == null) return;
        fo.FoldForbid = f[1] == "1";
        ApplyFoldForbidToRows(fo);
    }

    private void ApplyFoldForbidToRows(VListFold fo)
    {
        bool on = fo.FoldForbid;
        foreach (VListRow r in fo.ChildRows)
            r.FoldForbid = on;
        bool after = false;
        foreach (object it in _items)
        {
            if (ReferenceEquals(it, fo))
            {
                after = true;
                continue;
            }
            if (!after)
                continue;
            VListRow r = it as VListRow;
            if (r == null)
                break;
            r.FoldForbid = on;
        }
    }

    private void Move(string val)
    {
        string[] f = val.Split('\x1F');
        if (f.Length < 2) return;
        object a, b;
        if (!_byId.TryGetValue(f[0], out a) || !_byId.TryGetValue(f[1], out b)) return;
        _anchorId = FirstVisibleId();
        int ia = _items.IndexOf(a), ib = _items.IndexOf(b);
        if (ia < 0 || ib < 0) return;
        object tmp = _items[ia];
        _items[ia] = _items[ib];
        _items[ib] = tmp;
        // 槽位交换后对象跟随新位置：Id/SeqNo 必须同步交换，否则后续 VL_ROW 按 Id
        // 命中旧位置对象、把内容写回原槽位（现象：序号动了、内容没动），且 _byId 失配。
        string tmpId = ((VLItem)a).Id;
        ((VLItem)a).Id = ((VLItem)b).Id;
        ((VLItem)b).Id = tmpId;
        _byId.Remove(f[0]); _byId.Remove(f[1]);
        _byId[((VLItem)a).Id] = a;
        _byId[((VLItem)b).Id] = b;
        VListRow ra = a as VListRow, rb = b as VListRow;
        if (ra != null && rb != null)
        {
            string tmpSeq = ra.SeqNo;
            ra.SeqNo = rb.SeqNo;
            rb.SeqNo = tmpSeq;
        }
        MarkFoldRowFlags(_items);
        ApplyRowSel();
    }

    // ---- 容器级事件路由 ----

    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (_suppressCommit) return;
        FrameworkElement fe = FindTagged(e.OriginalSource as FrameworkElement);
        if (fe == null) return;
        string tag = (string)fe.Tag;
        VLItem item = fe.DataContext as VLItem;
        if (item == null) return;
        if (tag == "Forbid" || tag == "FoldForbid")
        {
            CheckBox cb = fe as CheckBox;
            if (cb != null)
            {
                SendChange(item.Id, tag, cb.IsChecked == true ? "1" : "0");
                return;
            }
        }
        SendClick(item.Id, tag);
    }

    private void OnRightUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        FrameworkElement fe = FindTagged(e.OriginalSource as FrameworkElement);
        if (fe == null) return;
        string tag = (string)fe.Tag;
        if (tag != "TKBtn" && tag != "FoldFront") return; // 仅触发键按钮支持右键自定义
        VLItem item = fe.DataContext as VLItem;
        if (item == null) return;
        SendClick(item.Id, tag + "R");
    }

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressCommit || _suppressChange) return;
        ComboBox cb = e.OriginalSource as ComboBox;
        if (cb == null) return;
        string tag = cb.Tag as string;
        if (tag != "TKType" && tag != "FoldTKType") return;
        VLItem item = cb.DataContext as VLItem;
        if (item == null) return;
        SendChange(item.Id, tag, cb.SelectedIndex.ToString());
    }

    private void OnLostFocus(object sender, System.Windows.Input.KeyboardFocusChangedEventArgs e)
    {
        if (_suppressCommit || _suppressChange) return;
        TextBox tb = e.OriginalSource as TextBox;
        ComboBox cb = e.OriginalSource as ComboBox;
        if (tb == null && cb == null) return;
        FrameworkElement fe = FindTagged(e.OriginalSource as FrameworkElement);
        if (fe == null) return;
        string tag = (string)fe.Tag;
        if (tag != "Remark" && tag != "Loop" && tag != "FoldRemark" && tag != "FoldFront" && tag != "FoldTK") return;
        VLItem item = fe.DataContext as VLItem;
        if (item == null) return;
        SendChange(item.Id, tag, tb != null ? tb.Text : cb.Text);
    }

    // e.OriginalSource 可能是控件内部元素（TextBlock/ContentPresenter），向上找最近带 Tag 的祖先
    private static FrameworkElement FindTagged(FrameworkElement fe)
    {
        DependencyObject d = fe;
        while (d != null)
        {
            FrameworkElement el = d as FrameworkElement;
            if (el != null && el.Tag is string && ((string)el.Tag).Length > 0)
                return el;
            d = System.Windows.Media.VisualTreeHelper.GetParent(d);
        }
        return null;
    }

    // ---- 回传与兜底提交 ----

    private void SendClick(string id, string action)
    {
        _send("EVENT|" + _winId + "|" + _listName + "|VL_CLICK|" + BridgeUtil.LengthPrefix(id + "\x1F" + action));
    }

    private void SendChange(string id, string field, string value)
    {
        _send("EVENT|" + _winId + "|" + _listName + "|VL_CHANGE|" + BridgeUtil.LengthPrefix(id + "\x1F" + field + "\x1F" + value));
    }

    // §11 拖拽落点回传：VL_DROP|srcId\x1FtgtId\x1F0(前)/1(后)
    private void SendDrop(string srcId, string tgtId, bool before)
    {
        _send("EVENT|" + _winId + "|" + _listName + "|VL_DROP|" + BridgeUtil.LengthPrefix(srcId + "\x1F" + tgtId + "\x1F" + (before ? "0" : "1")));
    }

    private void CommitAll()
    {
        if (_lb == null) return;
        _suppressCommit = true;
        try
        {
            var sb = new System.Text.StringBuilder();
            int n = 0;
            foreach (object o in _items)
            {
                if (o is VListRow)
                {
                    VListRow r = (VListRow)o;
                    AppendCommit(sb, ref n, r, "Remark", r.Remark);
                    AppendCommit(sb, ref n, r, "TKType", r.TKType.ToString());
                    AppendCommit(sb, ref n, r, "Loop", r.LoopText);
                    AppendCommit(sb, ref n, r, "Forbid", r.Forbid ? "1" : "0");
                }
                else
                {
                    VListFold fo = (VListFold)o;
                    AppendCommit(sb, ref n, fo, "FoldRemark", fo.FoldRemark);
                    AppendCommit(sb, ref n, fo, "FoldFront", fo.FoldFront);
                    AppendCommit(sb, ref n, fo, "FoldTK", fo.FoldTK);
                    AppendCommit(sb, ref n, fo, "FoldForbid", fo.FoldForbid ? "1" : "0");
                }
            }
            if (n == 0) return;
            _send("EVENT|" + _winId + "|" + _listName + "|VL_COMMIT_ALL|\n" + sb.ToString());
        }
        finally { _suppressCommit = false; }
    }

    private void AppendCommit(System.Text.StringBuilder sb, ref int n, VLItem item, string field, string value)
    {
        if (sb.Length > 0) sb.Append('\n');
        sb.Append(n).Append('=').Append(BridgeUtil.LengthPrefix(item.Id + "\x1F" + field + "\x1F" + value));
        n++;
    }

    // ---- 视口锚定 ----

    private string FirstVisibleId()
    {
        if (_lb == null) return null;
        var gen = _lb.ItemContainerGenerator;
        for (int i = 0; i < _items.Count; i++)
        {
            ListBoxItem c = gen.ContainerFromIndex(i) as ListBoxItem;
            if (c != null && c.IsVisible)
            {
                VLItem it = _items[i] as VLItem;
                if (it != null) return it.Id;
            }
        }
        return null;
    }

    private void RestoreAnchor()
    {
        if (_anchorId == null) return;
        object o;
        if (!_byId.TryGetValue(_anchorId, out o)) return;
        int idx = _items.IndexOf(o);
        if (idx < 0) return;
        // 直接按项索引设偏移：ScrollIntoView 的 EnsureVisible 会强制布局（折叠实测 ~65ms），
        // ScrollToVerticalOffset 仅设偏移，由后续布局一次性实现视口。
        System.Windows.Controls.ScrollViewer sv = BridgeUtil.FindVisualChild<System.Windows.Controls.ScrollViewer>(_lb);
        if (sv == null) return;
        sv.ScrollToVerticalOffset(idx);
    }

    private double CaptureScroll()
    {
        if (_lb == null) return 0;
        System.Windows.Controls.ScrollViewer sv = BridgeUtil.FindVisualChild<System.Windows.Controls.ScrollViewer>(_lb);
        return sv != null ? sv.VerticalOffset : 0;
    }

    private void RestoreScroll(double off)
    {
        if (_lb == null) return;
        System.Windows.Controls.ScrollViewer sv = BridgeUtil.FindVisualChild<System.Windows.Controls.ScrollViewer>(_lb);
        if (sv != null)
            sv.ScrollToVerticalOffset(off);
    }

    // ---- 吸顶折叠头（sticky fold header） ----
    // 模块头随滚动滑出视口时，overlay 把它钉在列表顶部；模块头仍完整可见时取消钉。
    private void UpdateSticky()
    {
        if (_lb == null) return;
        EnsureSticky();
        if (_sticky == null) return;
        try
        {
            if (_sv == null)
            {
                _sv = BridgeUtil.FindVisualChild<System.Windows.Controls.ScrollViewer>(_lb);
                if (_sv != null)
                    _sv.ScrollChanged += (s, e) => UpdateSticky();
            }
            // 判定统一用逻辑单位：CanContentScroll=True 时 VerticalOffset 是项索引（非像素），
            // 而 fold 在 _items 的下标同为项单位，两者可比。头已滚过视口顶（off>idx）→ 钉住该头。
            double off = _sv.VerticalOffset;
            VListFold pin = null;
            for (int i = 0; i < _items.Count; i++)
            {
                VListFold fo = _items[i] as VListFold;
                if (fo == null) continue;
                if (off > i) pin = fo;
                else break; // 第一个还完整的头，之后不再扫
            }
            SetStickyFold(pin);
        }
        catch { }
    }

    private void SetStickyFold(VListFold fo)
    {
        if (ReferenceEquals(fo, _stickyFold)) return;
        _stickyFold = fo;
        if (fo == null)
        {
            _sticky.Content = null;
            _sticky.Visibility = System.Windows.Visibility.Collapsed;
        }
        else
        {
            _sticky.Content = fo;
            _sticky.Visibility = System.Windows.Visibility.Visible;
        }
    }

    // 深搜按 Name 找控件（VLSticky overlay 不在命名作用域，FindName 取不到）
    private static System.Windows.FrameworkElement FindControlByName(DependencyObject parent, string name)
    {
        System.Windows.FrameworkElement fe = parent as System.Windows.FrameworkElement;
        if (fe != null && fe.Name == name) return fe;
        int n = System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < n; i++)
        {
            System.Windows.FrameworkElement r = FindControlByName(System.Windows.Media.VisualTreeHelper.GetChild(parent, i), name);
            if (r != null) return r;
        }
        return null;
    }

    // §11 拖拽目标行命中：光标下最近的 ListBoxItem；行间隙未命中时取最近项，避免插入线闪烁
    private ListBoxItem GetItemUnderMouse(ListBox lb, Point p)
    {
        System.Windows.Media.HitTestResult hit = System.Windows.Media.VisualTreeHelper.HitTest(lb, p);
        if (hit != null)
        {
            DependencyObject depObj = hit.VisualHit;
            while (depObj != null && !(depObj is ListBoxItem))
                depObj = System.Windows.Media.VisualTreeHelper.GetParent(depObj);
            ListBoxItem direct = depObj as ListBoxItem;
            if (direct != null) return direct;
        }
        var gen = lb.ItemContainerGenerator;
        ListBoxItem best = null;
        double bestDist = double.MaxValue;
        int n = _items != null ? _items.Count : 0;
        for (int i = 0; i < n; i++)
        {
            ListBoxItem c = gen.ContainerFromIndex(i) as ListBoxItem;
            if (c == null || !c.IsVisible) continue;
            Point tl = c.TranslatePoint(new Point(0, 0), lb);
            double top = tl.Y, bottom = tl.Y + c.ActualHeight;
            if (p.Y >= top && p.Y <= bottom)
                return c;
            double dist = p.Y < top ? top - p.Y : p.Y - bottom;
            if (dist < bestDist)
            {
                bestDist = dist;
                best = c;
            }
        }
        return bestDist < 16 ? best : null;
    }

    private bool InsertBefore(ListBoxItem target, double y)
    {
        double h = Math.Max(1, target.ActualHeight);
        if (ReferenceEquals(target, _insertTarget) && _insertPopup != null && _insertPopup.IsOpen)
        {
            if (y < h * 0.35) return true;
            if (y > h * 0.65) return false;
            return _insertBefore;
        }
        return y < h * 0.5;
    }

    private void MarkFoldRowFlags(System.Collections.Generic.IEnumerable<object> items)
    {
        VListFold fold = null;
        VListRow lastRow = null;
        int i = 0;
        int foldIndex = 0;
        foreach (object it in items)
        {
            VListFold nextFold = it as VListFold;
            if (nextFold != null)
            {
                if (fold != null)
                    fold.IsLastFold = false;
                CloseFoldFlags(fold, lastRow);
                nextFold.IsFirstFold = (fold == null);
                nextFold.IsLastFold = true;
                nextFold.IsAltFold = (foldIndex % 2) == 1;
                foldIndex++;
                fold = nextFold;
                lastRow = null;
                i = 0;
                continue;
            }
            VListRow row = it as VListRow;
            if (row != null)
            {
                row.IsAltRow = (i % 2) == 0;
                row.IsAltFold = fold != null && fold.IsAltFold;
                row.FoldForbid = fold != null && fold.FoldForbid;
                row.IsLastInFold = false;
                row.IsLastModule = false;
                lastRow = row;
                i++;
                continue;
            }
            CloseFoldFlags(fold, lastRow);
            fold = null;
            lastRow = null;
            i = 0;
        }
        CloseFoldFlags(fold, lastRow);
    }

    private static void CloseFoldFlags(VListFold fold, VListRow lastRow)
    {
        if (fold != null)
        {
            fold.HasBody = lastRow != null;
            foreach (VListRow r in fold.ChildRows)
                r.FoldForbid = fold.FoldForbid;
        }
        if (lastRow != null)
        {
            lastRow.IsLastInFold = true;
            lastRow.IsLastModule = fold != null && fold.IsLastFold;
        }
    }

    private void EnsureDragUi()
    {
        if (_ghostPopup != null) return;
        _ghostText = new TextBlock
        {
            FontSize = 12,
            Padding = new Thickness(10, 5, 10, 5),
            MaxWidth = 280,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        _ghostText.SetResourceReference(TextBlock.ForegroundProperty, "TextMain");
        Border ghostBd = new Border
        {
            CornerRadius = new CornerRadius(3),
            BorderThickness = new Thickness(1),
            Child = _ghostText,
            Opacity = 0.94
        };
        ghostBd.SetResourceReference(Border.BackgroundProperty, "ControlBg");
        ghostBd.SetResourceReference(Border.BorderBrushProperty, "Accent");
        _ghostPopup = new Popup
        {
            AllowsTransparency = true,
            IsHitTestVisible = false,
            Placement = PlacementMode.Absolute,
            Child = ghostBd
        };
        _insertBar = new Border
        {
            Height = 4,
            MinWidth = 160,
            CornerRadius = new CornerRadius(2),
            IsHitTestVisible = false
        };
        _insertBar.SetResourceReference(Border.BackgroundProperty, "Accent");
        _insertPopup = new Popup
        {
            AllowsTransparency = true,
            IsHitTestVisible = false,
            Placement = PlacementMode.Absolute,
            Child = _insertBar
        };
    }

    private static string GhostLabel(VLItem vi)
    {
        VListRow row = vi as VListRow;
        if (row != null)
        {
            string tk = string.IsNullOrEmpty(row.TKStr) ? "" : "  " + row.TKStr;
            return (row.SeqNo ?? "") + " " + (row.Remark ?? "") + tk;
        }
        VListFold fold = vi as VListFold;
        if (fold != null)
            return fold.FoldRemark ?? "";
        return "";
    }

    private void ShowInsertMarker(ListBoxItem target, bool before)
    {
        EnsureDragUi();
        if (ReferenceEquals(_insertTarget, target) && _insertBefore == before && _insertPopup.IsOpen)
            return;
        _insertTarget = target;
        _insertBefore = before;
        Point screen = target.PointToScreen(new Point(0, before ? -2 : target.ActualHeight - 2));
        Point dip = DeviceToDip(target, screen);
        _insertBar.Width = Math.Max(160, target.ActualWidth);
        _insertPopup.HorizontalOffset = dip.X;
        _insertPopup.VerticalOffset = dip.Y;
        _insertPopup.IsOpen = true;
    }

    private void HideInsertMarker()
    {
        _insertTarget = null;
        if (_insertPopup != null)
            _insertPopup.IsOpen = false;
    }

    private void HideDragUi()
    {
        HideInsertMarker();
        if (_ghostPopup != null)
            _ghostPopup.IsOpen = false;
    }

    private static Point CursorDip(Visual v)
    {
        POINT pt;
        GetCursorPos(out pt);
        return DeviceToDip(v, new Point(pt.X, pt.Y));
    }

    private static Point DeviceToDip(Visual v, Point device)
    {
        PresentationSource src = PresentationSource.FromVisual(v);
        if (src != null && src.CompositionTarget != null)
            return src.CompositionTarget.TransformFromDevice.Transform(device);
        return device;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    // ---- 解析工具 ----

    private static VListRow ParseRow(string[] f)
    {
        VListRow r = new VListRow();
        r.Id = f[0];
        r.Remark = f.Length > 1 ? f[1] : "";
        r.TKStr = f.Length > 2 ? f[2] : "";
        r.TKType = f.Length > 3 ? ParseInt(f[3]) : 0;
        r.LoopText = f.Length > 4 ? f[4] : "";
        r.Forbid = f.Length > 5 && f[5] == "1";
        r.ColorHex = f.Length > 6 ? f[6] : "";
        r.SeqNo = f.Length > 7 ? f[7] : "";
        r.EditKind = f.Length > 8 ? f[8] : "0";
        // §23 网络宏扩展位：f[9]="1" 表示网络表行（显示说明按钮、隐藏触发类型下拉）
        bool isNetRow = f.Length > 9 && f[9] == "1";
        r.NetHelpVis = isNetRow ? "Visible" : "Collapsed";
        r.NetTypeVis = isNetRow ? "Collapsed" : "Visible";
        FillSelMark(r);
        return r;
    }

    private static void FillSelMark(VListRow r)
    {
        r.SelMark = ((char)0xE72A).ToString();
        r.SelMarkNo = "";
        r.SelMarkTip = "";
    }

    private static int ParseInt(string s)
    {
        int v;
        return int.TryParse(s, out v) ? v : 0;
    }

}

// 数据模板选择：按 item 类型选 RmtMacroRow / RmtFoldHeader（模板由 AHK 注入 Window.Resources）
public class VLTemplateSelector : System.Windows.Controls.DataTemplateSelector
{
    private System.Windows.Window _win;
    private VirtualListHost _host;
    public VLTemplateSelector(System.Windows.Window win, VirtualListHost host) { _win = win; _host = host; }
    public override System.Windows.DataTemplate SelectTemplate(object item, DependencyObject container)
    {
        string suf = (_host != null && _host.IsCompact) ? "C" : "";
        if (item is VListFold)
        {
            object r = _win.FindResource("RmtFoldHeader" + suf);
            if (r is System.Windows.DataTemplate) return (System.Windows.DataTemplate)r;
        }
        else if (item is VListAddFold)
        {
            object r = _win.FindResource("RmtAddFold");
            if (r is System.Windows.DataTemplate) return (System.Windows.DataTemplate)r;
        }
        else if (item is VListRow)
        {
            object r = _win.FindResource("RmtMacroRow" + suf);
            if (r is System.Windows.DataTemplate) return (System.Windows.DataTemplate)r;
        }
        return null;
    }
}

public abstract class VLItem : System.ComponentModel.INotifyPropertyChanged
{
    public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
    public string Id;
    protected void Set<T>(ref T field, T value, string name)
    {
        field = value;
        if (PropertyChanged != null)
            PropertyChanged(this, new System.ComponentModel.PropertyChangedEventArgs(name));
    }
}

public class VListAddFold : VLItem { }

public class VListRow : VLItem
{
    public string Remark { get { return _Remark; } set { Set(ref _Remark, value, "Remark"); } } private string _Remark;
    public string TKStr { get { return _TKStr; } set { Set(ref _TKStr, value, "TKStr"); } } private string _TKStr;
    public int TKType { get { return _TKType; } set { Set(ref _TKType, value, "TKType"); } } private int _TKType;
    public string LoopText { get { return _LoopText; } set { Set(ref _LoopText, value, "LoopText"); } } private string _LoopText;
    public bool Forbid { get { return _Forbid; } set { Set(ref _Forbid, value, "Forbid"); } } private bool _Forbid;
    public string ColorHex { get { return _ColorHex; } set { Set(ref _ColorHex, value, "ColorHex"); } } private string _ColorHex;
    public string SeqNo { get { return _SeqNo; } set { Set(ref _SeqNo, value, "SeqNo"); } } private string _SeqNo;
    public bool TKBtnEnabled { get; set; }
    public bool TKTypeEnabled { get; set; }
    public bool LoopEnabled { get; set; }
    public bool IsAltRow { get { return _IsAltRow; } set { Set(ref _IsAltRow, value, "IsAltRow"); } } private bool _IsAltRow;
    public bool IsAltFold { get { return _IsAltFold; } set { Set(ref _IsAltFold, value, "IsAltFold"); } } private bool _IsAltFold;
    public bool IsLastInFold { get { return _IsLastInFold; } set { Set(ref _IsLastInFold, value, "IsLastInFold"); } } private bool _IsLastInFold;
    public bool IsLastModule { get { return _IsLastModule; } set { Set(ref _IsLastModule, value, "IsLastModule"); } } private bool _IsLastModule;
    public string EditKind { get { return _EditKind; } set { Set(ref _EditKind, value, "EditKind"); } } private string _EditKind;
    public bool FoldForbid { get { return _FoldForbid; } set { Set(ref _FoldForbid, value, "FoldForbid"); } } private bool _FoldForbid;
    public bool RowSel { get { return _RowSel; } set { Set(ref _RowSel, value, "RowSel"); } } private bool _RowSel;
    public string SelMark { get { return _SelMark; } set { Set(ref _SelMark, value, "SelMark"); } } private string _SelMark;
    public string SelMarkNo { get { return _SelMarkNo; } set { Set(ref _SelMarkNo, value, "SelMarkNo"); } } private string _SelMarkNo;
    public string SelMarkTip { get { return _SelMarkTip; } set { Set(ref _SelMarkTip, value, "SelMarkTip"); } } private string _SelMarkTip;
    // §23 网络宏行标志：NetHelpVis=说明按钮可见性、NetTypeVis=触发类型下拉可见性（互斥，由同一记录位驱动）
    public string NetHelpVis { get; set; }
    public string NetTypeVis { get; set; }
}

public class VListFold : VLItem
{
    public string FoldRemark { get { return _FoldRemark; } set { Set(ref _FoldRemark, value, "FoldRemark"); } } private string _FoldRemark;
    public string FoldFront { get { return _FoldFront; } set { Set(ref _FoldFront, value, "FoldFront"); } } private string _FoldFront;
    public bool FoldForbid { get { return _FoldForbid; } set { Set(ref _FoldForbid, value, "FoldForbid"); } } private bool _FoldForbid;
    public int FoldTKType { get { return _FoldTKType; } set { Set(ref _FoldTKType, value, "FoldTKType"); } } private int _FoldTKType;
    public string FoldTK { get { return _FoldTK; } set { Set(ref _FoldTK, value, "FoldTK"); } } private string _FoldTK;
    public bool Folded { get { return _Folded; } set { Set(ref _Folded, value, "Folded"); } } private bool _Folded;
    public bool HasBody { get { return _HasBody; } set { Set(ref _HasBody, value, "HasBody"); } } private bool _HasBody;
    public bool IsFirstFold { get { return _IsFirstFold; } set { Set(ref _IsFirstFold, value, "IsFirstFold"); } } private bool _IsFirstFold;
    public bool IsLastFold { get { return _IsLastFold; } set { Set(ref _IsLastFold, value, "IsLastFold"); } } private bool _IsLastFold;
    public bool IsAltFold { get { return _IsAltFold; } set { Set(ref _IsAltFold, value, "IsAltFold"); } } private bool _IsAltFold;
    public bool ShowTKRow { get; set; }
    public bool FoldTKTypeEnabled { get; set; }
    public string ShowTKRowVisibility { get { return ShowTKRow ? "Visible" : "Collapsed"; } }
    public System.Collections.Generic.List<VListRow> ChildRows = new System.Collections.Generic.List<VListRow>();
}


