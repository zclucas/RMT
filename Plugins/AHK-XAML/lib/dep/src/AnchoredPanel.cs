using System;
using System.Windows;

// 窗口内锚定浮层：把一个面板贴到某个控件的上沿，随窗口一起移动/缩放。
// 用窗口内子元素而不是 Popup / ToolTip：Popup 是独立 HWND，切换到别的窗口会自己关掉，
// 也不会跟着窗口移动。位置在引擎里算，AHK 侧只管开关与内容。
public partial class AhkWpfEngine
{
    private FrameworkElement anchoredPanel;
    private FrameworkElement anchoredLayer;
    private FrameworkElement anchoredTarget;
    private bool anchoredHooked;

    // ctrl 为面板自身，targetName 为目标控件名（按名字解析，见 FindControlByPath）。
    internal void AttachAnchoredPanel(FrameworkElement panel, string targetName)
    {
        if (panel == null || string.IsNullOrEmpty(targetName))
            return;

        var target = FindControlByPath(targetName) as FrameworkElement;
        if (target == null)
            return;

        anchoredPanel = panel;
        anchoredLayer = panel.Parent as FrameworkElement;
        anchoredTarget = target;

        // 布局一变就重新贴：窗口缩放、目标因文字变宽而位移都能跟上。
        // 只挂一次；Margin 相同就不再写，避免每帧触发无谓的再次布局。
        if (!anchoredHooked && anchoredLayer != null)
        {
            anchoredLayer.LayoutUpdated += RepositionAnchoredPanel;
            anchoredHooked = true;
        }

        RepositionAnchoredPanel(null, EventArgs.Empty);
    }

    private void RepositionAnchoredPanel(object sender, EventArgs e)
    {
        var panel = anchoredPanel;
        var layer = anchoredLayer;
        var target = anchoredTarget;
        if (panel == null || layer == null || target == null)
            return;
        if (panel.Visibility != Visibility.Visible)
            return;
        if (layer.ActualWidth < 1 || layer.ActualHeight < 1)
            return;

        try
        {
            // 浮层与目标互为兄弟（都在整窗那一层里），不能拿浮层当祖先，要换算到两者共同的父级
            FrameworkElement parent = layer.Parent as FrameworkElement;
            if (parent == null)
                return;

            Point targetOrigin = target.TransformToAncestor(parent).Transform(new Point(0, 0));
            Point layerOrigin = layer.TransformToAncestor(parent).Transform(new Point(0, 0));
            double originX = targetOrigin.X - layerOrigin.X;
            double originY = targetOrigin.Y - layerOrigin.Y;

            const double gap = 6;
            double x = originX;
            double width = panel.ActualWidth;
            if (width > 0)
            {
                double maxX = layer.ActualWidth - width - 8;
                if (x > maxX)
                    x = Math.Max(0, maxX);
            }

            // 面板底边贴在目标上沿往上 gap 处：底对齐 + 从图层底部量起的下边距
            double bottom = layer.ActualHeight - (originY - gap);
            if (bottom < 0)
                bottom = 0;

            Thickness margin = new Thickness(x, 0, 0, bottom);
            if (panel.Margin != margin)
                panel.Margin = margin;
        }
        catch (Exception)
        {
            // 目标被移出可视树时 TransformToAncestor 会抛，忽略即可
        }
    }
}
