// =============================================================================
// Control state collection & queries: CollectState/MQUERY etc.
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

public partial class AhkWpfEngine
{


    // Reusable helper: extract the current value of a named control.
    // Used by both CollectState() and MQUERY handler.
    // Extract visible text from a TextBlock with Run elements (from emoji auto-detection)
    private string GetTextFromInlines(TextBlock tb)
    {
        var sb = new StringBuilder();
        foreach (var inline in tb.Inlines)
        {
            if (inline is System.Windows.Documents.Run)
            {
                sb.Append(((System.Windows.Documents.Run)inline).Text);
            }
        }
        return sb.ToString();
    }

    // 遍历 TreeView 可视树，收集所有已实现（可见）的 TreeViewItem
    private void CollectTreeViewItems(DependencyObject parent, System.Collections.Generic.List<System.Windows.Controls.TreeViewItem> result)
    {
        if (parent is System.Windows.Controls.TreeViewItem)
            result.Add((System.Windows.Controls.TreeViewItem)parent);
        int n = System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < n; i++)
            CollectTreeViewItems(System.Windows.Media.VisualTreeHelper.GetChild(parent, i), result);
    }

    // 收集 ListBox 里所有已实现（可见）的 ListBoxItem（逻辑树卡片，Items 里直接是 ListBoxItem）
    private void CollectListBoxItems(System.Windows.Controls.ListBox lb, System.Collections.Generic.List<System.Windows.Controls.ListBoxItem> result)
    {
        foreach (object item in lb.Items)
        {
            var lbi = item as System.Windows.Controls.ListBoxItem;
            if (lbi != null)
                result.Add(lbi);
        }
    }

    // tag|slot|expander|originY|height|originX|width|splitBtn
    private string FormatListHit(FrameworkElement tagFe, FrameworkElement yFe, FrameworkElement xFe, double hy, bool expander, string splitBtn, Visual rootVisual, FrameworkElement rowFe)
    {
        if (tagFe == null || yFe == null)
            return "";
        if (xFe == null)
            xFe = yFe;
        var yOrigin = yFe.TransformToAncestor(rootVisual).Transform(new System.Windows.Point(0, 0));
        var xOrigin = xFe.TransformToAncestor(rootVisual).Transform(new System.Windows.Point(0, 0));
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        string slot = (hy < yOrigin.Y + yFe.ActualHeight / 2.0) ? "top" : "bottom";
        // 最后一段是整行宽度：分栏行里 xFe 只是其中一栏，算左右分栏占用要的是行宽
        string rowW = "";
        if (rowFe != null)
        {
            try { rowW = rowFe.ActualWidth.ToString(inv); } catch { }
        }
        return tagFe.Tag.ToString() + "|" + slot + "|" + (expander ? "1" : "0")
            + "|" + yOrigin.Y.ToString(inv) + "|" + yFe.ActualHeight.ToString(inv)
            + "|" + xOrigin.X.ToString(inv) + "|" + xFe.ActualWidth.ToString(inv)
            + "|" + (splitBtn ?? "") + "|" + rowW;
    }

    private string GetControlValue(string trackName)
    {
        if (trackName == "Window>FocusEditable")
            return IsEditableFocus(System.Windows.Input.Keyboard.FocusedElement) ? "1" : "0";

        string cName = trackName;
        string suffix = null;

        // New: '>' delimiter for rich queries (e.g. "MyList>Count", "MyGrid>SelectedRow")
        int gtIdx = cName.IndexOf('>');
        if (gtIdx > 0)
        {
            suffix = cName.Substring(gtIdx + 1);
            cName = cName.Substring(0, gtIdx);
        }
        // Legacy: _CaretIndex backward compat
        else if (cName.EndsWith("_CaretIndex"))
        {
            cName = cName.Substring(0, cName.Length - 11);
            suffix = "CaretIndex";
        }

        // FindControlByPath：含 NameScope 回退与可视树查找，避免仅 win.FindName 漏掉画布内节点控件
        var c = FindControlByPath(cName);
        if (c == null) return null;

        string val = "";

        // --- Suffix queries (rich component data) ---
        if (suffix != null)
        {
            // TextLines —— 文本框在当前宽度下实际占几行，以及实际行高（"行数,行高"）。
            // 替代主程序里按字符宽度估算换行的做法：估算用固定系数近似 ASCII 宽度，
            // 中英混排、字体回退时都会偏，输入框高度会跳行。
            if (suffix.StartsWith("TextLines"))
            {
                var tbx = c as System.Windows.Controls.TextBox;
                if (tbx == null)
                    return "1";
                return MeasureTextBoxMetrics(tbx);
            }

            // MaxPanelWidth:listMinW —— AI 侧栏在「左侧列表不窄于 listMinW」前提下能取到的最大宽度。
            // 面板和列表是同一容器里的两半，它们的实际宽度只有引擎知道；以前由主程序
            // 回读 FoldList 的 ActualWidth 自己算，还得猜哪个页签当前可见。
            if (suffix.StartsWith("MaxPanelWidth"))
            {
                double mpMinW = 0;
                if (suffix.Length > 14)
                    double.TryParse(suffix.Substring(14), System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out mpMinW);
                return QueryMaxPanelWidth(mpMinW);
            }

            // HitTest:x;y —— 在指定控件上命中测试（坐标相对该控件），向上找 TreeViewItem，
            // 返回 "Tag|top/bottom"（top=光标在上半，bottom=下半；供插入上/下判定）
            if (suffix.StartsWith("HitTest:"))
            {
                string[] hxy = suffix.Substring("HitTest:".Length).Split(';');
                double hx, hy;
                if (hxy.Length == 2
                    && double.TryParse(hxy[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out hx)
                    && double.TryParse(hxy[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out hy))
                {
                    var rootVisual = c as System.Windows.Media.Visual;
                    if (rootVisual != null)
                    {
                        var hitRes = System.Windows.Media.VisualTreeHelper.HitTest(rootVisual, new System.Windows.Point(hx, hy));
                        DependencyObject dep = hitRes != null ? hitRes.VisualHit as DependencyObject : null;
                        // ListBox 卡片命中：找 ListBoxItem，isExpander=命中 Arrow_* 命名元素（展开箭头）
                        // 返回 tag|slot|expander|originY|height|originX|width|splitBtn
                        if (c is System.Windows.Controls.ListBox)
                        {
                            bool isCardExpander = false;
                            string splitBtn = "";
                            FrameworkElement nodeFe = null;
                            FrameworkElement colFe = null;
                            DependencyObject walk = dep;
                            while (walk != null && !(walk is System.Windows.Controls.ListBoxItem) && !(walk is System.Windows.Controls.ListBox))
                            {
                                var fe = walk as System.Windows.FrameworkElement;
                                if (fe != null)
                                {
                                    if (fe.Name != null)
                                    {
                                        if (fe.Name.StartsWith("Arrow_"))
                                            isCardExpander = true;
                                        else if (fe.Name.StartsWith("SplitViewT_"))
                                            splitBtn = "T:" + fe.Name.Substring("SplitViewT_".Length);
                                        else if (fe.Name.StartsWith("SplitViewF_"))
                                            splitBtn = "F:" + fe.Name.Substring("SplitViewF_".Length);
                                        else if (colFe == null && fe.Name.StartsWith("SplitCol_"))
                                            colFe = fe;
                                    }
                                    if (nodeFe == null && fe.Tag != null)
                                    {
                                        string tg = fe.Tag.ToString();
                                        if (tg.StartsWith("n") && tg.IndexOf('+') < 0)
                                            nodeFe = fe;
                                    }
                                }
                                walk = System.Windows.Media.VisualTreeHelper.GetParent(walk);
                            }
                            dep = walk;
                            var lbi = dep as System.Windows.Controls.ListBoxItem;
                            FrameworkElement tagFe = nodeFe != null ? nodeFe : (colFe != null ? colFe : lbi);
                            FrameworkElement yFe = nodeFe != null ? nodeFe : (colFe != null ? colFe : lbi);
                            FrameworkElement xFe = colFe != null ? colFe : lbi;
                            if (tagFe != null && tagFe.Tag != null)
                            {
                                try
                                {
                                    val = FormatListHit(tagFe, yFe, xFe, hy, isCardExpander, splitBtn, rootVisual, lbi);
                                }
                                catch
                                {
                                    val = tagFe.Tag.ToString() + "|" + (isCardExpander ? "1" : "0") + "|0|0";
                                }
                            }
                            else if (dep is System.Windows.Controls.ListBox)
                            {
                                // 卡片间空隙/空白区：按 Y 找包含该点的卡片
                                var items = new System.Collections.Generic.List<System.Windows.Controls.ListBoxItem>();
                                CollectListBoxItems((System.Windows.Controls.ListBox)dep, items);
                                foreach (var it in items)
                                {
                                    try
                                    {
                                        var itOrigin = it.TransformToAncestor(rootVisual).Transform(new System.Windows.Point(0, 0));
                                        if (hy >= itOrigin.Y && hy < itOrigin.Y + it.ActualHeight)
                                        {
                                            val = FormatListHit(it, it, it, hy, false, "", rootVisual, it);
                                            break;
                                        }
                                    }
                                    catch { }
                                }
                            }
                            return val;
                        }
                        // 命中 ToggleButton = 展开箭头（需与条目内容区分：点箭头只折叠，不选择/不双击）
                        bool isExpander = false;
                        // 停在 TreeViewItem（命中条目）或 TreeView（命中树但不在条目上，行间/空白区）
                        while (dep != null && !(dep is System.Windows.Controls.TreeViewItem) && !(dep is System.Windows.Controls.TreeView))
                        {
                            if (dep is System.Windows.Controls.Primitives.ToggleButton)
                                isExpander = true;
                            dep = System.Windows.Media.VisualTreeHelper.GetParent(dep);
                        }
                        var tvi = dep as System.Windows.Controls.TreeViewItem;
                        if (tvi != null && tvi.Tag != null)
                        {
                            try
                            {
                                // 相对被命中的控件（win 或 tree）换算纵向位置，与 hy 同坐标系
                                var origin = tvi.TransformToAncestor(rootVisual).Transform(new System.Windows.Point(0, 0));
                                var inv = System.Globalization.CultureInfo.InvariantCulture;
                                val = tvi.Tag.ToString() + "|" + (hy < origin.Y + tvi.ActualHeight / 2.0 ? "top" : "bottom") + "|" + (isExpander ? "1" : "0")
                                    + "|" + origin.Y.ToString(inv) + "|" + tvi.ActualHeight.ToString(inv);
                            }
                            catch
                            {
                                val = tvi.Tag.ToString() + "|" + (isExpander ? "1" : "0") + "|0|0";
                            }
                        }
                        else if (dep is System.Windows.Controls.TreeView)
                        {
                            // 行间/条目行空白区（文字右侧）：按 Y 找包含该点的条目（相邻行无间隙，总能命中一行）
                            var items = new System.Collections.Generic.List<System.Windows.Controls.TreeViewItem>();
                            CollectTreeViewItems((System.Windows.Controls.TreeView)dep, items);
                            foreach (var it in items)
                            {
                                try
                                {
                                    var itOrigin = it.TransformToAncestor(rootVisual).Transform(new System.Windows.Point(0, 0));
                                    if (hy >= itOrigin.Y && hy < itOrigin.Y + it.ActualHeight)
                                    {
                                        var inv = System.Globalization.CultureInfo.InvariantCulture;
                                        val = it.Tag.ToString() + "|" + (hy < itOrigin.Y + it.ActualHeight / 2.0 ? "top" : "bottom") + "|0"
                                            + "|" + itOrigin.Y.ToString(inv) + "|" + it.ActualHeight.ToString(inv);
                                        break;
                                    }
                                }
                                catch { }
                            }
                        }
                    }
                }
                return val;
            }
            // MouseLocal —— 当前光标相对该控件的本地坐标（穿透 Viewbox，供拖拽命中）
            if (suffix == "MouseLocal")
            {
                var ie = c as System.Windows.IInputElement;
                if (ie != null)
                {
                    try
                    {
                        var pos = System.Windows.Input.Mouse.GetPosition(ie);
                        var inv = System.Globalization.CultureInfo.InvariantCulture;
                        val = pos.X.ToString(inv) + ";" + pos.Y.ToString(inv);
                    }
                    catch { }
                }
                return val;
            }
            // CursorDip —— 屏幕光标的 WPF DIP（Popup Placement=Absolute 跟手，与 VL 一致）
            if (suffix == "CursorDip")
            {
                var visual = c as System.Windows.Media.Visual;
                if (visual == null && c is DependencyObject)
                    visual = Window.GetWindow((DependencyObject)c) as System.Windows.Media.Visual;
                if (visual != null)
                {
                    try
                    {
                        POINT cpt;
                        if (GetCursorPos(out cpt))
                        {
                            var device = new System.Windows.Point(cpt.x, cpt.y);
                            var src = System.Windows.PresentationSource.FromVisual(visual);
                            if (src != null && src.CompositionTarget != null)
                                device = src.CompositionTarget.TransformFromDevice.Transform(device);
                            var inv = System.Globalization.CultureInfo.InvariantCulture;
                            val = device.X.ToString(inv) + "," + device.Y.ToString(inv);
                        }
                    }
                    catch { }
                }
                return val;
            }
            // IsOverTree:x;y —— 命中测试点是否落在 TreeView 内（空白树区也算），用于拖放"出树即取消"
            if (suffix.StartsWith("IsOverTree:"))
            {
                string[] hxy = suffix.Substring("IsOverTree:".Length).Split(';');
                double hx, hy;
                if (hxy.Length == 2
                    && double.TryParse(hxy[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out hx)
                    && double.TryParse(hxy[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out hy))
                {
                    var rootVisual = c as System.Windows.Media.Visual;
                    if (rootVisual != null)
                    {
                        var hitRes = System.Windows.Media.VisualTreeHelper.HitTest(rootVisual, new System.Windows.Point(hx, hy));
                        DependencyObject dep = hitRes != null ? hitRes.VisualHit as DependencyObject : null;
                        while (dep != null && !(dep is System.Windows.Controls.TreeView) && !(dep is System.Windows.Controls.ListBox))
                            dep = System.Windows.Media.VisualTreeHelper.GetParent(dep);
                        val = (dep is System.Windows.Controls.TreeView || dep is System.Windows.Controls.ListBox) ? "1" : "";
                    }
                }
                return val;
            }
            switch (suffix)
            {
                case "CaretIndex":
                    if (c is TextBox) val = ((TextBox)c).CaretIndex.ToString();
                    break;
                case "FirstVisibleLine":
                    if (c is TextBox) val = ((TextBox)c).GetFirstVisibleLineIndex().ToString();
                    break;
                case "Count":
                    if (c is ItemsControl) val = ((ItemsControl)c).Items.Count.ToString();
                    break;
                case "SelectedIndex":
                    if (c is System.Windows.Controls.Primitives.Selector)
                        val = ((System.Windows.Controls.Primitives.Selector)c).SelectedIndex.ToString();
                    else if (c is TabControl)
                        val = ((TabControl)c).SelectedIndex.ToString();
                    break;
                case "SelectedHeader":
                    if (c is TabControl)
                    {
                        TabControl _tc = (TabControl)c;
                        if (_tc.SelectedItem is TabItem)
                        {
                            TabItem _ti = (TabItem)_tc.SelectedItem;
                            val = _ti.Header != null ? _ti.Header.ToString() : "";
                        }
                    }
                    break;
                case "Items":
                    if (c is ItemsControl)
                    {
                        ItemsControl _ic = (ItemsControl)c;
                        var items = new System.Collections.Generic.List<string>();
                        foreach (var item in _ic.Items)
                        {
                            if (item is ContentControl)
                            {
                                ContentControl _cc = (ContentControl)item;
                                object _tag = _cc.Tag;
                                object _content = _cc.Content;
                                if (_tag != null && _tag.ToString() != "")
                                {
                                    items.Add(_tag.ToString());
                                }
                                else if (_content is TextBlock)
                                {
                                    // Handle emoji auto-detection: Content is a TextBlock with Runs
                                    TextBlock _tb = (TextBlock)_content;
                                    items.Add(_tb.Text != null && _tb.Text.Length > 0 ? _tb.Text : GetTextFromInlines(_tb));
                                }
                                else if (_content is string)
                                {
                                    items.Add((string)_content);
                                }
                                else if (_content != null)
                                {
                                    items.Add(_content.ToString());
                                }
                                else
                                {
                                    items.Add("");
                                }
                            }
                            else
                            {
                                items.Add(item != null ? item.ToString() : "");
                            }
                        }
                        val = string.Join("|", items);
                    }
                    break;
                case "SelectedRow":
                    // DataGrid: return pipe-delimited cell values of selected row
                    if (c is DataGrid && ((DataGrid)c).SelectedItem != null)
                    {
                        DataGrid _dg = (DataGrid)c;
                        var props = _dg.SelectedItem.GetType().GetProperties();
                        var cells = new System.Collections.Generic.List<string>();
                        foreach (var p in props)
                        {
                            try
                            {
                                object pv = p.GetValue(_dg.SelectedItem);
                                cells.Add(pv != null ? pv.ToString() : "");
                            }
                            catch { }
                        }
                        val = string.Join("|", cells);
                    }
                    break;
                case "FilteredCount":
                    // DataGrid: count of visible rows in the current view
                    if (c is DataGrid)
                    {
                        DataGrid _dg2 = (DataGrid)c;
                        var view = System.Windows.Data.CollectionViewSource.GetDefaultView(_dg2.ItemsSource != null ? _dg2.ItemsSource : _dg2.Items);
                        if (view != null)
                        {
                            int count = 0;
                            foreach (var item in view) count++;
                            val = count.ToString();
                        }
                        else
                        {
                            val = _dg2.Items.Count.ToString();
                        }
                    }
                    break;
                case "Nodes":
                    // Canvas-based node editor: serialize node positions and data
                    if (c is Canvas)
                    {
                        Canvas _canvas = (Canvas)c;
                        var nodes = new System.Collections.Generic.List<string>();
                        foreach (UIElement child in _canvas.Children)
                        {
                            if (child is FrameworkElement)
                            {
                                FrameworkElement _fe = (FrameworkElement)child;
                                if (_fe.Name != null && _fe.Name != "")
                                {
                                    double x = Canvas.GetLeft(_fe); if (double.IsNaN(x)) x = 0;
                                    double y = Canvas.GetTop(_fe); if (double.IsNaN(y)) y = 0;
                                    string nodeTag = _fe.Tag as string;
                                    if (nodeTag == null) nodeTag = "";
                                    nodes.Add(_fe.Name + ":" + x + "," + y + (nodeTag != "" ? ":" + nodeTag : ""));
                                }
                            }
                        }
                        val = string.Join("|", nodes);
                    }
                    break;
                case "Connections":
                    // Canvas: find Path elements that represent connections (by Tag convention)
                    if (c is Canvas)
                    {
                        Canvas _canvas2 = (Canvas)c;
                        var conns = new System.Collections.Generic.List<string>();
                        foreach (UIElement child in _canvas2.Children)
                        {
                            if (child is System.Windows.Shapes.Path)
                            {
                                System.Windows.Shapes.Path _path = (System.Windows.Shapes.Path)child;
                                string connTag = _path.Tag as string;
                                if (connTag != null && connTag.StartsWith("conn:"))
                                {
                                    conns.Add(connTag.Substring(5));
                                }
                            }
                        }
                        val = string.Join("|", conns);
                    }
                    break;
                case "SelectedNode":
                    // Canvas: find the focused/selected node element
                    if (c is Canvas)
                    {
                        Canvas _canvas3 = (Canvas)c;
                        foreach (UIElement child in _canvas3.Children)
                        {
                            if (child is FrameworkElement)
                            {
                                FrameworkElement _fe2 = (FrameworkElement)child;
                                string _feTag = _fe2.Tag as string;
                                if (_feTag != null && _feTag.Contains("selected"))
                                {
                                    val = _fe2.Name != null ? _fe2.Name : "";
                                    break;
                                }
                            }
                        }
                    }
                    break;
                case "ActualWidth":
                    if (c is FrameworkElement)
                    {
                        var invW = System.Globalization.CultureInfo.InvariantCulture;
                        val = ((FrameworkElement)c).ActualWidth.ToString(invW);
                    }
                    break;
                case "ScreenOrigin":
                    if (c is FrameworkElement)
                    {
                        var element = (FrameworkElement)c;
                        if (element.IsVisible && PresentationSource.FromVisual(element) != null)
                        {
                            var point = element.PointToScreen(new Point(0, 0));
                            var inv = System.Globalization.CultureInfo.InvariantCulture;
                            val = point.X.ToString("F0", inv) + "," + point.Y.ToString("F0", inv);
                        }
                    }
                    break;
                case "Position":
                    if (c is System.Windows.Media.Visual)
                    {
                        try
                        {
                            var visual = (System.Windows.Media.Visual)c;
                            var parentWindow = Window.GetWindow(visual);
                            if (parentWindow != null)
                            {
                                var pos = visual.TransformToAncestor(parentWindow).Transform(new System.Windows.Point(0, 0));
                                val = pos.X + "," + pos.Y;
                            }
                        }
                        catch { }
                    }
                    break;
                case "CanvasMouseLive":
                case "CanvasMouse":
                    // 画布本地坐标下的当前光标位置（含 RenderTransform），供 Ctrl+V 粘贴锚点等使用
                    if (c is Canvas)
                    {
                        try
                        {
                            var canvas = (Canvas)c;
                            Point pos;
                            try { pos = System.Windows.Input.Mouse.GetPosition(canvas); }
                            catch { pos = new Point(double.NaN, double.NaN); }
                            if (double.IsNaN(pos.X) || double.IsNaN(pos.Y))
                            {
                                if (canvas.Name != null && canvasMouseCache.ContainsKey(canvas.Name))
                                    pos = canvasMouseCache[canvas.Name];
                            }
                            else if (canvas.Name != null)
                                canvasMouseCache[canvas.Name] = pos;
                            if (!double.IsNaN(pos.X) && !double.IsNaN(pos.Y))
                            {
                                val = pos.X.ToString(System.Globalization.CultureInfo.InvariantCulture) + ","
                                    + pos.Y.ToString(System.Globalization.CultureInfo.InvariantCulture);
                            }
                        }
                        catch { }
                    }
                    break;
                case "Handle":
                    val = new System.Windows.Interop.WindowInteropHelper(win).Handle.ToString();
                    break;
                default:
                    // Generic: try to read an arbitrary dependency property by name
                    if (c is FrameworkElement)
                    {
                        try
                        {
                            var pi = c.GetType().GetProperty(suffix);
                            if (pi != null)
                            {
                                object pVal = pi.GetValue(c);
                                val = pVal != null ? pVal.ToString() : "";
                            }
                        }
                        catch { }
                    }
                    break;
            }
            return val;
        }

        // --- Default value extraction (no suffix) ---
        if (c is TextBox) val = ((TextBox)c).Text;
        else if (c is PasswordBox) val = ((PasswordBox)c).Password;
        else if (c is ToggleButton) { bool? isChecked = ((ToggleButton)c).IsChecked; val = isChecked.HasValue ? isChecked.Value.ToString() : "False"; }
        else if (c is RangeBase) val = ((RangeBase)c).Value.ToString();
        else if (c is ComboBox)
        {
            ComboBox cb = (ComboBox)c;
            // 可编辑下拉：显示文本即真值。标签拖拽只改 Text，SelectedItem 可能仍指向旧项。
            if (cb.IsEditable)
            {
                try
                {
                    var editBox = cb.Template != null
                        ? cb.Template.FindName("PART_EditableTextBox", cb) as System.Windows.Controls.TextBox
                        : null;
                    if (editBox != null)
                        val = editBox.Text ?? "";
                    else
                        val = cb.Text ?? "";
                }
                catch { val = cb.Text ?? ""; }
            }
            else if (cb.SelectedItem is ComboBoxItem)
            {
                object tag = ((ComboBoxItem)cb.SelectedItem).Tag;
                object content = ((ComboBoxItem)cb.SelectedItem).Content;
                if (tag != null && tag.ToString() != "") val = tag.ToString();
                else if (content is TextBlock)
                {
                    TextBlock tb = (TextBlock)content;
                    val = GetTextFromInlines(tb);
                    if (string.IsNullOrEmpty(val) && tb.Text != null) val = tb.Text;
                }
                else if (content != null) val = content.ToString();
                else val = "";
            }
            else val = cb.Text;
        }
        else if (c is TreeView)
        {
            TreeView tv = (TreeView)c;
            if (tv.SelectedItem is TreeViewItem)
            {
                object tag = ((TreeViewItem)tv.SelectedItem).Tag;
                val = tag != null && tag.ToString() != "" ? tag.ToString() : "";
                if (string.IsNullOrEmpty(val))
                {
                    object header = ((TreeViewItem)tv.SelectedItem).Header;
                    val = header != null ? header.ToString() : "";
                }
            }
        }
        else if (c is ListBox)
        {
            ListBox lb = (ListBox)c;
            if (lb.SelectedItem is ListBoxItem)
            {
                object tag = ((ListBoxItem)lb.SelectedItem).Tag;
                object content = ((ListBoxItem)lb.SelectedItem).Content;
                if (tag != null && tag.ToString() != "") val = tag.ToString();
                else if (content is TextBlock) val = GetTextFromInlines((TextBlock)content);
                else if (content != null) val = content.ToString();
                else val = "";
            }
            else if (lb.SelectedItem != null) val = lb.SelectedItem.ToString();
        }
        // New: TextBlock, TabControl, DataGrid, Image — previously unsupported
        else if (c is TextBlock) val = ((TextBlock)c).Text;
        else if (c is System.Windows.Controls.Image)
        {
            var imgSrc = ((System.Windows.Controls.Image)c).Source;
            val = imgSrc != null ? imgSrc.ToString() : "";
        }
        else if (c is TabControl) val = ((TabControl)c).SelectedIndex.ToString();
        else if (c is DataGrid) val = ((DataGrid)c).SelectedIndex.ToString();

        if (val == null) val = "";
        return val;
    }

    public string CollectState()
    {
        var sb = new StringBuilder();
        foreach (var t in tracked)
        {
            string val = GetControlValue(t);
            if (val != null)
            {
                sb.Append(t + "=" + BridgeUtil.LengthPrefix(val) + "\n");
            }
        }
        return sb.ToString();
    }

    // 找当前可见的 AI 侧栏，用「列表宽 + 面板宽 - 列表最小宽」算出面板还能到多宽。
    // 只认 Visibility 为 Visible 且已经有实际宽度的那个，隐藏页签的 ActualWidth 为 0，不能用。
    private string QueryMaxPanelWidth(double listMinW)
    {
        if (win == null)
            return "";
        double best = 0;
        WalkVisualTree(win, (System.Windows.DependencyObject d) =>
        {
            var fe = d as System.Windows.FrameworkElement;
            if (fe == null || string.IsNullOrEmpty(fe.Name))
                return;
            if (!fe.Name.StartsWith("AiWrap_"))
                return;
            if (fe.Visibility != System.Windows.Visibility.Visible || fe.ActualWidth <= 0)
                return;
            string tab = fe.Name.Substring("AiWrap_".Length);
            var list = FindControlByPath("FoldList_" + tab) as System.Windows.FrameworkElement;
            if (list == null || list.ActualWidth <= 0)
                return;
            double avail = list.ActualWidth + fe.ActualWidth - listMinW;
            if (avail > best)
                best = avail;
        });
        if (best <= 0)
            return "";
        return ((int)System.Math.Round(best)).ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    // 文本框在当前宽度下占几行，以及实际行高（"行数,行高"）。
    // 直接按文本排版测量，不看控件的 DesiredSize：模板自带的固定内边距和「单行外框高」
    // 对不齐，用 DesiredSize 反推会整体偏一行。
    // 行高也一并返回：主程序那边用的是固定值，字号被主题放大后每行会矮一截，多行时会裁字。
    private static string MeasureTextBoxMetrics(System.Windows.Controls.TextBox tb)
    {
        if (tb == null)
            return "1";

        string text = tb.Text;
        if (string.IsNullOrEmpty(text))
            text = " ";   // 空文本也要量出行高，主程序拿它算「最多显示几行」的上限

        var inv = System.Globalization.CultureInfo.InvariantCulture;
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');

        double avail = tb.ActualWidth - tb.Padding.Left - tb.Padding.Right;
        if (double.IsNaN(avail) || avail <= 0)
            avail = tb.Width;
        if (double.IsNaN(avail) || avail <= 0)
            return "1";
        if (avail < 8)
            avail = 8;

        try
        {
            var tf = new System.Windows.Media.Typeface(
                tb.FontFamily, tb.FontStyle, tb.FontWeight, tb.FontStretch);
            var ci = System.Globalization.CultureInfo.CurrentUICulture;

            // 单行基准：中英各取一个字符，同时触发字体回退，行高更接近实际排版
            var probe = new System.Windows.Media.FormattedText(
                "国Ag", ci, tb.FlowDirection, tf, tb.FontSize,
                System.Windows.Media.Brushes.Black);
            probe.MaxTextWidth = 100000;
            double lineUnit = probe.Height;
            if (lineUnit <= 0)
                return "1";

            var ft = new System.Windows.Media.FormattedText(
                text, ci, tb.FlowDirection, tf, tb.FontSize,
                System.Windows.Media.Brushes.Black);
            ft.MaxTextWidth = avail;
            ft.MaxTextHeight = 1000000;

            // 加 0.5 后取下整，避开 Math.Round 的银行家舍入（0.5 会舍成 0，导致少一行）
            int lines = (int)Math.Floor(ft.Height / lineUnit + 0.5);
            if (lines < 1)
                lines = 1;
            if (lines > 64)
                lines = 64;
            return lines.ToString(inv) + "," + lineUnit.ToString("0.##", inv);
        }
        catch
        {
            return "1";
        }
    }

    // Collect state for specific control names only (used by MQUERY)
    public string CollectStateFor(string[] names)
    {
        var sb = new StringBuilder();
        foreach (var name in names)
        {
            string trimmed = name.Trim();
            if (trimmed.Length == 0) continue;
            string val = GetControlValue(trimmed);
            if (val != null)
            {
                sb.Append(trimmed + "=" + BridgeUtil.LengthPrefix(val) + "\n");
            }
        }
        return sb.ToString();
    }

    private DateTime lastSendMouseMove = DateTime.MinValue;

    private void AppendCanvasMouseLiveToState(StringBuilder sb)
    {
        if (sb == null) return;
        // 先刷新所有已跟踪画布的实时光标，再写入状态（Ctrl+V 粘贴锚点用）
        var names = new System.Collections.Generic.List<string>(canvasMouseCache.Keys);
        // 始终尝试 RMT 画布（即使尚未移过鼠标、缓存为空）
        if (!names.Contains("RMTGraph") && FindControlByPath("RMTGraph") is Canvas)
            names.Insert(0, "RMTGraph");
        if (names.Count == 0 && win != null)
        {
            WalkVisualTree(win, (DependencyObject d) =>
            {
                var cv = d as Canvas;
                if (cv != null && cv.Tag != null && cv.Tag.ToString() == "ZoomPanEnabled" && !string.IsNullOrEmpty(cv.Name))
                    names.Add(cv.Name);
            });
        }
        foreach (string canvasName in names)
        {
            if (string.IsNullOrEmpty(canvasName)) continue;
            Point pos;
            var canvas = FindControlByPath(canvasName) as Canvas;
            if (canvas != null)
            {
                try { pos = System.Windows.Input.Mouse.GetPosition(canvas); }
                catch
                {
                    if (!canvasMouseCache.TryGetValue(canvasName, out pos)) continue;
                }
                canvasMouseCache[canvasName] = pos;
            }
            else if (!canvasMouseCache.TryGetValue(canvasName, out pos))
                continue;
            string coords = pos.X.ToString(System.Globalization.CultureInfo.InvariantCulture) + ","
                + pos.Y.ToString(System.Globalization.CultureInfo.InvariantCulture);
            sb.Append(canvasName + ">CanvasMouseLive=" + BridgeUtil.LengthPrefix(coords) + "\n");
            sb.Append("CanvasMouseLive=" + BridgeUtil.LengthPrefix(coords) + "\n");
        }
    }

    private Canvas FindZoomPanCanvas()
    {
        // 优先 RMT 图形画布
        var rmt = FindControlByPath("RMTGraph") as Canvas;
        if (rmt != null) return rmt;
        foreach (var kv in canvasMouseCache)
        {
            var cv = FindControlByPath(kv.Key) as Canvas;
            if (cv != null) return cv;
        }
        Canvas found = null;
        if (win != null)
        {
            WalkVisualTree(win, (DependencyObject d) =>
            {
                if (found != null) return;
                var cv = d as Canvas;
                if (cv == null || string.IsNullOrEmpty(cv.Name)) return;
                if (cv.Tag != null && cv.Tag.ToString() == "ZoomPanEnabled")
                    found = cv;
                else if (found == null && cv.Name == "RMTGraph")
                    found = cv;
            });
        }
        return found;
    }

    private void SendPasteAtFromCanvas(Canvas canvas, Point? screenPoint = null)
    {
        if (canvas == null) return;
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        Point pos;
        if (screenPoint.HasValue)
        {
            // AHK MouseGetPos(Screen) → PointFromScreen（含 RenderTransform）
            try { pos = canvas.PointFromScreen(screenPoint.Value); }
            catch { pos = System.Windows.Input.Mouse.GetPosition(canvas); }
        }
        else
        {
            // 与 MoveConnectionDrag 同源；异常时用屏幕光标兜底
            pos = System.Windows.Input.Mouse.GetPosition(canvas);
            if (double.IsNaN(pos.X) || double.IsNaN(pos.Y) || (pos.X == 0 && pos.Y == 0 && !canvas.IsMouseOver))
            {
                try
                {
                    POINT sp;
                    if (GetCursorPos(out sp))
                        pos = canvas.PointFromScreen(new System.Windows.Point((double)sp.x, (double)sp.y));
                }
                catch { }
            }
        }
        if (!string.IsNullOrEmpty(canvas.Name))
            canvasMouseCache[canvas.Name] = pos;
        string coords = pos.X.ToString(inv) + "," + pos.Y.ToString(inv);
        string name = !string.IsNullOrEmpty(canvas.Name) ? canvas.Name : "Canvas";
        // 必须异步：AHK 经 Update 同步进来时，若再同步 SendMessage 回 AHK 会死锁
        SendToAhkAsync("EVENT|" + winId + "|" + name + "|PasteAt|" + BridgeUtil.LengthPrefix(coords) + "\n");
    }

}
