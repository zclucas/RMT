// =============================================================================
// 流式行布局：容器按自身宽度自动分行，每行居中。
// 用于赞助商 logo 这类「固定槽位、按宽度决定每行几个」的排列。
// 以前由 AHK 监听 SizeChanged、回读 ActualWidth 再逐行重发 XAML，每次窗口尺寸
// 变化都要一次跨进程往返 + 整段重建；现在宽度变化时引擎内部直接重排。
// =============================================================================
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;

public partial class AhkWpfEngine
{
    private sealed class FlowState
    {
        public readonly List<UIElement> Items = new List<UIElement>();
        public double Slot = 124;
        public int Cap = -1;
        public bool Busy;
    }

    private const string FlowRowTag = "RmtFlowRow";

    // 用弱表挂状态，面板销毁时自动回收，不需要额外的清理点
    private static readonly ConditionalWeakTable<Panel, FlowState> _flowStates =
        new ConditionalWeakTable<Panel, FlowState>();

    // 命令入口：ctrl|FlowLayout|<槽位像素>
    private static void ApplyFlowLayout(Panel panel, double slot)
    {
        if (panel == null)
            return;
        if (slot < 20)
            slot = 124;

        FlowState st;
        if (!_flowStates.TryGetValue(panel, out st))
        {
            st = new FlowState();
            _flowStates.Add(panel, st);
            panel.SizeChanged += FlowPanel_SizeChanged;
        }
        else if (!IsFlowRowLayout(panel))
        {
            // 内容被外部重置过（ClearItems 或重新 AddXamlItem），重新取快照
            st.Items.Clear();
        }

        if (st.Items.Count == 0)
        {
            CollectFlowItems(panel, st.Items);
            panel.Children.Clear();
        }

        st.Slot = slot;
        st.Cap = -1;
        RelayoutFlow(panel);
    }

    private static void FlowPanel_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        Panel panel = sender as Panel;
        if (panel != null)
            RelayoutFlow(panel);
    }

    // 当前 Children 是否全是上次排出来的行（用 Tag 标记），用来判断快照还能不能用
    private static bool IsFlowRowLayout(Panel panel)
    {
        if (panel.Children.Count == 0)
            return true;
        foreach (UIElement child in panel.Children)
        {
            FrameworkElement fe = child as FrameworkElement;
            if (fe == null)
                return false;
            string tag = fe.Tag as string;
            if (tag != FlowRowTag)
                return false;
        }
        return true;
    }

    // 取回原始条目。已经排过行的容器要展开行，否则重新收集会把行当成条目塞进去。
    private static void CollectFlowItems(Panel panel, List<UIElement> into)
    {
        foreach (UIElement child in panel.Children)
        {
            FrameworkElement fe = child as FrameworkElement;
            string tag = (fe != null) ? fe.Tag as string : null;
            Panel rowPanel = child as Panel;
            if (tag == FlowRowTag && rowPanel != null)
            {
                List<UIElement> nested = new List<UIElement>();
                foreach (UIElement g in rowPanel.Children)
                    nested.Add(g);
                foreach (UIElement g in nested)
                    into.Add(g);
                continue;
            }
            into.Add(child);
        }
    }

    private static void RelayoutFlow(Panel panel)
    {
        FlowState st;
        if (!_flowStates.TryGetValue(panel, out st))
            return;
        if (st.Busy || st.Items.Count == 0)
            return;

        double avail = panel.ActualWidth;
        if (double.IsNaN(avail) || avail <= 0)
            return;

        int cap = (int)Math.Floor(avail / st.Slot);
        if (cap < 1)
            cap = 1;

        int n = st.Items.Count;
        if (cap > n)
            cap = n;
        if (cap == st.Cap)
            return;

        st.Busy = true;
        try
        {
            st.Cap = cap;
            int rows = (int)Math.Ceiling((double)n / cap);
            panel.Children.Clear();

            int idx = 0;
            for (int r = 0; r < rows; r++)
            {
                // 多出来的名额放在上面几行，和原算法一致
                int take = n / rows + (r < (n % rows) ? 1 : 0);
                StackPanel row = new StackPanel();
                row.Orientation = Orientation.Horizontal;
                row.HorizontalAlignment = HorizontalAlignment.Center;
                row.Tag = FlowRowTag;
                for (int i = 0; i < take && idx < n; i++)
                {
                    row.Children.Add(st.Items[idx]);
                    idx++;
                }
                panel.Children.Add(row);
            }
        }
        finally
        {
            st.Busy = false;
        }
    }
}
