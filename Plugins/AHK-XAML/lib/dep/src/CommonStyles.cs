// Shared WPF control styles. Configuration is data only; never loads executable XAML.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Markup;
using System.Windows.Input;
using System.Windows.Shapes;
using System.Windows.Documents;
using System.Windows.Threading;
using System.Xml;

internal static class RmtCommonStyles
{
    internal sealed class Entry
    {
        public WeakReference Element;
        public string Key, Location;
        public Dictionary<string, object> Original = new Dictionary<string, object>();
        public HashSet<string> Unset = new HashSet<string>();
        public HashSet<string> Applied = new HashSet<string>();
        public HashSet<string> Frozen = new HashSet<string>();
        public Dictionary<string, object> ResourceKeys = new Dictionary<string, object>();
        public Dictionary<string, string> LastApplied = new Dictionary<string, string>();
    }
    internal sealed class StyleBranch
    {
        public string Key, Type, Path;
        public Dictionary<string, string> Properties = new Dictionary<string, string>();
        public List<StyleBranch> Children = new List<StyleBranch>();
    }
    internal static readonly string[] Properties = {
        "Background", "HoverBackground", "PressedBackground", "Foreground", "BorderBrush", "CornerRadius", "BorderThickness",
        "Margin", "Padding", "MaxDropDownHeight", "HorizontalAlignment", "VerticalAlignment",
        "TextAlignment", "TextWrapping", "TextTrimming", "IsReadOnly", "AcceptsReturn", "MaxLength",
        "Orientation", "ChildAlignment", "Stretch", "StretchDirection", "VerticalScrollBarVisibility", "HorizontalScrollBarVisibility",
        "Width", "Height", "MinWidth", "MinHeight", "MaxWidth", "MaxHeight",
        "FontWeight", "RelativeFontSize", "Opacity", "HorizontalContentAlignment", "VerticalContentAlignment", "Spacing", "SizeMode"
    };
    internal static readonly string[] WindowExtraProperties = { "ShowMinimize", "ShowMaximize", "ShowPin", "ShowClose" };
    // Mirrors AppThemeUtil.ColorDefs order. These are the only colours GM-UI may assign.
    internal static readonly string[] ThemePaletteResources = {
        "ActionBg", "ActionHoverBg", "EditHoverBg", "TitleBarColor", "TitleBarForeground", "BgColor", "InputBg",
        "InputStroke", "GroupStroke", "TextMain", "InputText", "GraphLine", "GraphConn", "ActionText"
    };
    private static readonly ConditionalWeakTable<FrameworkElement, Entry> entries = new ConditionalWeakTable<FrameworkElement, Entry>();
    private static readonly List<WeakReference> elements = new List<WeakReference>();
    internal static readonly Dictionary<string, Dictionary<string, string>> Values = new Dictionary<string, Dictionary<string, string>>();
    internal static readonly Dictionary<string, Dictionary<string, string>> Layouts = new Dictionary<string, Dictionary<string, string>>();
    internal static readonly Dictionary<string, Dictionary<string, string>> InstanceStyles = new Dictionary<string, Dictionary<string, string>>();
    internal static readonly Dictionary<string, string> StyleBindings = new Dictionary<string, string>();
    internal static readonly Dictionary<string, StyleBranch> Composites = new Dictionary<string, StyleBranch>();
    internal static readonly Dictionary<string, string> CloneBases = new Dictionary<string, string>();
    internal static readonly Dictionary<string, string> DisplayNames = new Dictionary<string, string>();
    internal static readonly HashSet<string> HiddenStyles = new HashSet<string>();
    internal const string InstancePrefix = "实例/";
    private static readonly string[] PositionProperties = {
        "Margin", "AnchorObject", "AnchorType", "PositionX", "PositionY", "Left", "Top", "CanvasLeft", "CanvasTop", "SizeMode"
    };
    private static string path;
    private static bool initialized, development;
    private static RmtStyleEditor editor;
    private static readonly HashSet<Window> watched = new HashSet<Window>();
    private static bool refreshPending;
    private sealed class Corners { public CornerRadius Value; }
    private static readonly ConditionalWeakTable<Border, Corners> corners = new ConditionalWeakTable<Border, Corners>();
    private static readonly DependencyProperty ControlCornerRadius = DependencyProperty.RegisterAttached(
        "CommonCornerRadius", typeof(CornerRadius), typeof(RmtCommonStyles), new PropertyMetadata(new CornerRadius(0),
            (obj, args) => ApplyCorners(obj as Control)));
    // Background has no common hover DP.  Keep it as an attached property so it can be
    // configured just like the other GM-UI properties without changing every template.
    private sealed class HoverState { internal Brush Base, BorderBase; internal Border Border; internal bool Hooked, Hovering; }
    private static readonly ConditionalWeakTable<Control, HoverState> hovers = new ConditionalWeakTable<Control, HoverState>();
    private static readonly DependencyProperty ControlHoverBackground = DependencyProperty.RegisterAttached(
        "CommonHoverBackground", typeof(Brush), typeof(RmtCommonStyles), new PropertyMetadata(null,
            (obj, args) => ApplyHoverBackground(obj as Control)));
    private sealed class PressState { internal Brush Base, BorderBase; internal Border Border; internal bool Hooked, Pressed; }
    private static readonly ConditionalWeakTable<Control, PressState> presses = new ConditionalWeakTable<Control, PressState>();
    private static readonly DependencyProperty ControlPressedBackground = DependencyProperty.RegisterAttached(
        "CommonPressedBackground", typeof(Brush), typeof(RmtCommonStyles), new PropertyMetadata(null,
            (obj, args) => ApplyPressedBackground(obj as Control)));
    private sealed class StackSpacingState
    {
        internal readonly Dictionary<FrameworkElement, Thickness> Original = new Dictionary<FrameworkElement, Thickness>();
        internal readonly Dictionary<FrameworkElement, Thickness> Applied = new Dictionary<FrameworkElement, Thickness>();
        internal bool Hooked, Applying;
    }
    private static readonly ConditionalWeakTable<StackPanel, StackSpacingState> stackSpacings = new ConditionalWeakTable<StackPanel, StackSpacingState>();
    private static readonly DependencyProperty StackPanelSpacing = DependencyProperty.RegisterAttached(
        "CommonStackPanelSpacing", typeof(double), typeof(RmtCommonStyles), new PropertyMetadata(0.0,
            (obj, args) => ApplyStackPanelSpacing(obj as StackPanel)));
    private sealed class StackAlignState
    {
        internal readonly Dictionary<FrameworkElement, HorizontalAlignment> Original = new Dictionary<FrameworkElement, HorizontalAlignment>();
        internal readonly Dictionary<FrameworkElement, VerticalAlignment> OriginalVertical = new Dictionary<FrameworkElement, VerticalAlignment>();
        internal HorizontalAlignment PanelOriginal = HorizontalAlignment.Stretch;
        internal bool Hooked, Applying, CapturedPanel;
    }
    private static readonly ConditionalWeakTable<StackPanel, StackAlignState> stackAligns = new ConditionalWeakTable<StackPanel, StackAlignState>();
    private static readonly DependencyProperty StackPanelChildAlignment = DependencyProperty.RegisterAttached(
        "CommonStackPanelChildAlignment", typeof(HorizontalAlignment), typeof(RmtCommonStyles), new PropertyMetadata(HorizontalAlignment.Left,
            (obj, args) => ApplyStackPanelChildAlignment(obj as StackPanel)));
    internal static string LoadError = "";

    internal static void Configure(Window window, string options)
    {
        var parts = options.Split(new[] { '|' }, 2);
        if (!initialized)
        {
            path = parts[0];
            development = parts.Length == 2 && parts[1] == "1";
            Load();
            EventManager.RegisterClassHandler(typeof(FrameworkElement), FrameworkElement.LoadedEvent,
                new RoutedEventHandler(OnLoaded), true);
            initialized = true;
        }
        Walk(window, new HashSet<DependencyObject>());
        ApplyResources(window);
        if (watched.Add(window))
        {
            bool pending = false, closed = false;
            // WPF does not broadcast Loaded to nodes without an instance/style Loaded handler.
            // Coalesce layout discovery so virtualized and dynamically inserted nodes are included.
            EventHandler layout = delegate
            {
                if (pending || closed) return;
                pending = true;
                window.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Background, new Action(delegate
                {
                    pending = false;
                    if (!closed) Walk(window, new HashSet<DependencyObject>());
                }));
            };
            window.LayoutUpdated += layout;
            window.Closed += delegate { closed = true; window.LayoutUpdated -= layout; watched.Remove(window); };
        }
    }

    private static void OnLoaded(object sender, RoutedEventArgs args)
    {
        var fe = sender as FrameworkElement;
        if (fe != null) Register(fe);
    }

    private static void Walk(DependencyObject root, HashSet<DependencyObject> visited)
    {
        if (root == null || !visited.Add(root)) return;
        var fe = root as FrameworkElement;
        if (fe != null) Register(fe);
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>().ToArray()) Walk(child, visited);
        if (root is Visual)
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) Walk(VisualTreeHelper.GetChild(root, i), visited);
    }

    private static bool Eligible(FrameworkElement fe)
    {
        // DataTemplate controls (including virtual rows) are application controls too.
        if (fe.TemplatedParent is Control && !(fe.TemplatedParent is ContentPresenter)) return false;
        if (IsEditorWindow(fe as Window ?? Window.GetWindow(fe))) return false;
        if (fe is Window)
            return Application.Current == null || !ReferenceEquals(fe, Application.Current.MainWindow);
        return fe is Control || fe is Border || fe is TextBlock || fe is Panel;
    }

    private static string StyleKey(FrameworkElement fe)
    {
        // A copied GM-UI style is attached declaratively with Uid="gm:Button1" (or TextBox1, ComboBox1...).
        if (!string.IsNullOrEmpty(fe.Uid) && fe.Uid.StartsWith("gm:") && !fe.Uid.StartsWith("gm:auto.")) return fe.Uid.Substring(3);
        if (!string.IsNullOrEmpty(fe.Uid) && fe.Uid.StartsWith("gm-exception:")) return "特殊/" + fe.Uid.Substring(13);
        if (fe.Name == "BtnMinimize" || fe.Name == "BtnMaximize" || fe.Name == "BtnPin" || fe.Name == "BtnWinClose" || fe.Name == "BtnClosePanel")
            return "特殊/窗口标题栏/" + fe.Name;
        var style = fe.Style;
        for (FrameworkElement parent = fe; parent != null; parent = (LogicalTreeHelper.GetParent(parent) ?? VisualParent(parent)) as FrameworkElement)
        {
            string key = FindKey(parent.Resources, style);
            if (key != null) return "样式/" + key;
        }
        return "通用/" + fe.GetType().Name;
    }

    internal static string StyleKeyPublic(FrameworkElement fe)
    {
        return StyleKey(fe);
    }

    internal static bool IsPickable(FrameworkElement fe)
    {
        if (fe == null || fe is RmtStyleEditor) return false;
        if (IsEditorWindow(Window.GetWindow(fe))) return false;
        if (fe.TemplatedParent != null) return false;
        if (fe is ContentPresenter) return false;
        return fe is Control || fe is Panel || fe is Border || fe is TextBlock || fe is Image || fe is Viewbox;
    }

    internal static bool IsEditorWindow(Window window)
    {
        return window is RmtStyleEditor || window is RmtControlTreeWindow || (window != null && window.Owner is RmtStyleEditor);
    }

    internal static void EnsureRegistered(FrameworkElement fe)
    {
        Register(fe);
    }

    internal static bool TryGetEntry(FrameworkElement fe, out Entry entry)
    {
        entry = null;
        return fe != null && entries.TryGetValue(fe, out entry);
    }

    private static DependencyObject VisualParent(DependencyObject value)
    {
        return value is Visual ? VisualTreeHelper.GetParent(value) : null;
    }

    private static string FindKey(ResourceDictionary resources, Style style)
    {
        if (style == null) return null;
        foreach (object key in resources.Keys)
            if (key is string && ReferenceEquals(resources[key], style)) return (string)key;
        foreach (ResourceDictionary child in resources.MergedDictionaries)
        {
            string key = FindKey(child, style);
            if (key != null) return key;
        }
        return null;
    }

    private static void Register(FrameworkElement fe)
    {
        if (!Eligible(fe)) return;
        Entry existing;
        if (entries.TryGetValue(fe, out existing)) return;
        var window = Window.GetWindow(fe);
        var entry = new Entry { Element = new WeakReference(fe), Key = StyleKey(fe),
            Location = (window == null ? "" : window.Title) + " / " + fe.GetType().Name + " / " + fe.Name + " / " + fe.Uid };
        entries.Add(fe, entry);
        elements.Add(new WeakReference(fe));
        if (elements.Count % 512 == 0) elements.RemoveAll(x => !x.IsAlive);
        foreach (string property in Properties)
        {
            var dp = Property(fe, property);
            if (dp == null) continue;
            entry.Original[property] = fe.GetValue(dp);
            if (fe.ReadLocalValue(dp) == DependencyProperty.UnsetValue) entry.Unset.Add(property);
        }
        Apply(entry);
        ApplyLayout(fe);
    }

    internal static string LayoutId(FrameworkElement fe)
    {
        if (fe == null) return "";
        if (!string.IsNullOrEmpty(fe.Uid) && (fe.Uid.StartsWith("gm:") || fe.Uid.StartsWith("ahk:"))) return fe.Uid;
        var window = fe as Window ?? Window.GetWindow(fe);
        string title = window == null ? "" : (window.Title ?? "");
        if (!string.IsNullOrEmpty(fe.Name)) return title + "/" + fe.Name;
        if (fe is Window && !string.IsNullOrEmpty(title)) return "Window:" + title;
        return "";
    }

    internal static string EnsureLayoutId(FrameworkElement fe)
    {
        string id = LayoutId(fe);
        if (id != "" || fe == null) return id;
        string uid;
        do { uid = "gm:auto." + fe.GetType().Name + "." + Guid.NewGuid().ToString("N"); }
        while (StyleBindings.ContainsKey(uid) || InstanceStyles.ContainsKey(uid));
        fe.Uid = uid;
        return uid;
    }

    internal static bool IsInstanceStyle(string key)
    {
        return !string.IsNullOrEmpty(key) && key.StartsWith(InstancePrefix, StringComparison.Ordinal);
    }

    internal static bool IsCatalogTemplate(string key)
    {
        if (string.IsNullOrEmpty(key) || IsInstanceStyle(key) || key.StartsWith("颜色/", StringComparison.Ordinal)) return false;
        if (key.StartsWith("#group:", StringComparison.Ordinal) || HiddenStyles.Contains(key)) return false;
        return Values.ContainsKey(key) || CloneBases.ContainsKey(key) || Composites.ContainsKey(key)
            || key.StartsWith("通用/", StringComparison.Ordinal) || key.StartsWith("样式/", StringComparison.Ordinal);
    }

    internal static Dictionary<string, string> SanitizeStyle(Dictionary<string, string> values)
    {
        var result = new Dictionary<string, string>();
        if (values == null) return result;
        foreach (var pair in values)
        {
            if (string.IsNullOrEmpty(pair.Key) || Array.IndexOf(PositionProperties, pair.Key) >= 0) continue;
            if ((pair.Key == "Width" || pair.Key == "Height") && pair.Value != null && pair.Value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) continue;
            result[pair.Key] = pair.Value ?? "";
        }
        return result;
    }

    internal static bool StyleEquals(Dictionary<string, string> left, Dictionary<string, string> right)
    {
        var a = SanitizeStyle(left);
        var b = SanitizeStyle(right);
        if (a.Count != b.Count) return false;
        foreach (var pair in a)
        {
            string value;
            if (!b.TryGetValue(pair.Key, out value) || value != pair.Value) return false;
        }
        return true;
    }

    internal static int StyleRefCount(string styleKey)
    {
        if (string.IsNullOrEmpty(styleKey)) return 0;
        int count = 0;
        foreach (string bound in StyleBindings.Values)
            if (bound == styleKey) count++;
        return count;
    }

    internal static string BoundStyleKey(string layoutId)
    {
        string key;
        return !string.IsNullOrEmpty(layoutId) && StyleBindings.TryGetValue(layoutId, out key) ? key : "";
    }

    internal static bool TryBoundProperties(string layoutId, out Dictionary<string, string> values)
    {
        values = null;
        string key = BoundStyleKey(layoutId);
        return key != "" && Values.TryGetValue(key, out values);
    }

    private static bool StyleTypeMatches(string key, string typeName)
    {
        if (string.IsNullOrEmpty(typeName) || string.IsNullOrEmpty(key)) return true;
        if (key == "通用/" + typeName) return true;
        if (IsInstanceStyle(key) && key.StartsWith(InstancePrefix + typeName, StringComparison.Ordinal)) return true;
        string clone;
        if (CloneBases.TryGetValue(key, out clone) && clone == "通用/" + typeName) return true;
        if (typeName == "Button" && (key.IndexOf("Button", StringComparison.OrdinalIgnoreCase) >= 0
            || key.IndexOf("Btn", StringComparison.OrdinalIgnoreCase) >= 0
            || key.StartsWith("Main.", StringComparison.Ordinal) || key.StartsWith("Theme.", StringComparison.Ordinal)))
            return true;
        if (typeName == "Window" && IsWindowKey(key)) return true;
        return false;
    }

    internal static string FindEqualStyle(Dictionary<string, string> values, string typeName, string excludeKey)
    {
        var wanted = SanitizeStyle(values);
        foreach (var pair in Values)
        {
            if (pair.Key == excludeKey || HiddenStyles.Contains(pair.Key)) continue;
            if (pair.Key.StartsWith("颜色/", StringComparison.Ordinal) || IsCompositeChild(pair.Key)) continue;
            if (!StyleTypeMatches(pair.Key, typeName)) continue;
            if (StyleEquals(pair.Value, wanted)) return pair.Key;
        }
        return null;
    }

    internal static string NewInstanceKey(string typeName)
    {
        if (string.IsNullOrEmpty(typeName)) typeName = "Control";
        int number = 1;
        string key;
        do { key = InstancePrefix + typeName + number++; }
        while (Values.ContainsKey(key) || CloneBases.ContainsKey(key) || Composites.ContainsKey(key));
        return key;
    }

    internal static string AssignControlStyle(FrameworkElement element, Dictionary<string, string> values)
    {
        if (element == null) return "";
        var props = SanitizeStyle(values);
        if (element is Window)
        {
            foreach (string extra in new[] { "Width", "Height", "MinWidth", "MinHeight", "MaxWidth", "MaxHeight", "SizeMode", "Padding" })
                props.Remove(extra);
            foreach (string chrome in WindowExtraProperties) props.Remove(chrome);
        }
        string layoutId = EnsureLayoutId(element);
        if (layoutId == "") return "";
        string current;
        StyleBindings.TryGetValue(layoutId, out current);
        bool exclusive = IsInstanceStyle(current) && StyleRefCount(current) <= 1;
        string typeName = element.GetType().Name;
        string match = FindEqualStyle(props, typeName, exclusive ? current : null);
        if (match != null)
        {
            StyleBindings[layoutId] = match;
            if (exclusive && current != match) RemoveInstanceStyle(current);
            CollectUnusedInstances();
            SyncBoundInstance(layoutId);
            return match;
        }
        string target = exclusive ? current : NewInstanceKey(typeName);
        Values[target] = new Dictionary<string, string>(props);
        StyleBindings[layoutId] = target;
        CollectUnusedInstances();
        SyncBoundInstance(layoutId);
        return target;
    }

    internal static void CollectUnusedInstances()
    {
        foreach (string key in Values.Keys.ToArray())
        {
            if (!IsInstanceStyle(key) || StyleRefCount(key) > 0) continue;
            RemoveInstanceStyle(key);
        }
    }

    private static void RemoveInstanceStyle(string key)
    {
        if (!IsInstanceStyle(key)) return;
        Values.Remove(key);
        CloneBases.Remove(key);
        DisplayNames.Remove(key);
        Composites.Remove(key);
        foreach (var pair in StyleBindings.ToArray())
            if (pair.Value == key) StyleBindings.Remove(pair.Key);
        foreach (var pair in InstanceStyles.ToArray())
        {
            string bound = BoundStyleKey(pair.Key);
            if (bound == "" || bound == key) InstanceStyles.Remove(pair.Key);
        }
    }

    private static void SyncBoundInstance(string layoutId)
    {
        Dictionary<string, string> props;
        if (TryBoundProperties(layoutId, out props))
            InstanceStyles[layoutId] = new Dictionary<string, string>(props);
        else
            InstanceStyles.Remove(layoutId);
    }

    private static void RebindUsersToInstance(string styleKey)
    {
        if (string.IsNullOrEmpty(styleKey)) return;
        var users = new List<string>();
        foreach (var pair in StyleBindings)
            if (pair.Value == styleKey) users.Add(pair.Key);
        if (users.Count == 0) return;
        Dictionary<string, string> props;
        if (!Values.TryGetValue(styleKey, out props) || props == null) props = new Dictionary<string, string>();
        string leftover = NewInstanceKey(InstanceTypeName(styleKey));
        Values[leftover] = SanitizeStyle(props);
        foreach (string user in users)
        {
            StyleBindings[user] = leftover;
            SyncBoundInstance(user);
        }
    }

    private static string InstanceTypeName(string styleKey)
    {
        if (IsInstanceStyle(styleKey)) return styleKey.Substring(InstancePrefix.Length).TrimEnd('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        if (!string.IsNullOrEmpty(styleKey) && styleKey.StartsWith("通用/", StringComparison.Ordinal)) return styleKey.Substring(3);
        string clone;
        if (CloneBases.TryGetValue(styleKey, out clone) && clone.StartsWith("通用/", StringComparison.Ordinal)) return clone.Substring(3);
        return "Control";
    }

    private static void ImportLegacyInstance(string layoutId, Dictionary<string, string> values)
    {
        if (string.IsNullOrEmpty(layoutId)) return;
        var props = SanitizeStyle(values);
        string match = FindEqualStyle(props, null, null);
        string key = match;
        if (key == null)
        {
            key = NewInstanceKey(InstanceTypeName(layoutId));
            Values[key] = props;
        }
        StyleBindings[layoutId] = key;
        SyncBoundInstance(layoutId);
    }

    internal static void ApplyLayout(FrameworkElement fe)
    {
        string id = LayoutId(fe);
        Dictionary<string, string> layout;
        if (id == "" || !Layouts.TryGetValue(id, out layout)) return;
        string value;
        if (layout.ContainsKey("AnchorObject") && layout.ContainsKey("AnchorType") && layout.ContainsKey("PositionX") && layout.ContainsKey("PositionY"))
        {
            ApplyAnchorLayout(fe, layout);
            return;
        }
        if (layout.TryGetValue("Margin", out value))
        {
            try { fe.Margin = (Thickness)ConvertValue(typeof(Thickness), value); } catch { }
        }
        if (layout.TryGetValue("CanvasLeft", out value))
        {
            try { Canvas.SetLeft(fe, (double)ConvertValue(typeof(double), value)); } catch { }
        }
        if (layout.TryGetValue("CanvasTop", out value))
        {
            try { Canvas.SetTop(fe, (double)ConvertValue(typeof(double), value)); } catch { }
        }
        var window = fe as Window;
        if (window != null)
        {
            ApplyWindowLayoutSize(window, layout);
            if (layout.TryGetValue("Left", out value))
            {
                try { window.Left = (double)ConvertValue(typeof(double), value); } catch { }
            }
            if (layout.TryGetValue("Top", out value))
            {
                try { window.Top = (double)ConvertValue(typeof(double), value); } catch { }
            }
        }
    }

    internal static void ApplyAnchorLayout(FrameworkElement target, Dictionary<string, string> layout)
    {
        if (target == null || layout == null) return;
        string anchorName, anchorKind, xText, yText;
        if (!layout.TryGetValue("AnchorObject", out anchorName)
            || !layout.TryGetValue("AnchorType", out anchorKind)
            || !layout.TryGetValue("PositionX", out xText)
            || !layout.TryGetValue("PositionY", out yText)) return;
        double x, y;
        if (!double.TryParse(xText, NumberStyles.Float, CultureInfo.InvariantCulture, out x)
            || !double.TryParse(yText, NumberStyles.Float, CultureInfo.InvariantCulture, out y)) return;
        double ax, ay;
        AnchorFactors(anchorKind, out ax, out ay);
        var window = target as Window;
        if (window != null)
        {
            ApplyWindowLayoutSize(window, layout);
            window.UpdateLayout();
            Rect area = SystemParameters.WorkArea;
            double width = double.IsNaN(window.ActualWidth) || window.ActualWidth <= 0 ? window.Width : window.ActualWidth;
            double height = double.IsNaN(window.ActualHeight) || window.ActualHeight <= 0 ? window.Height : window.ActualHeight;
            window.Left = area.Left + area.Width * ax + x - width * ax;
            window.Top = area.Top + area.Height * ay + y - height * ay;
            window.UpdateLayout();
            return;
        }
        var parent = (LogicalTreeHelper.GetParent(target) ?? VisualParent(target)) as FrameworkElement;
        if (parent == null) return;
        FrameworkElement anchor = anchorName == "窗口" ? Window.GetWindow(target) : parent;
        if (anchor == null) anchor = parent;
        Point origin = new Point(0, 0);
        if (!ReferenceEquals(anchor, parent))
        {
            try { origin = anchor.TranslatePoint(new Point(0, 0), parent); }
            catch { origin = new Point(0, 0); }
        }
        Point current;
        try { current = target.TranslatePoint(new Point(0, 0), parent); }
        catch { current = new Point(target.Margin.Left, target.Margin.Top); }
        double left = origin.X + anchor.ActualWidth * ax + x - target.ActualWidth * ax;
        double top = origin.Y + anchor.ActualHeight * ay + y - target.ActualHeight * ay;
        double dx = left - current.X;
        double dy = top - current.Y;
        if (parent is Canvas)
        {
            double canvasLeft = Canvas.GetLeft(target), canvasTop = Canvas.GetTop(target);
            Canvas.SetLeft(target, (double.IsNaN(canvasLeft) ? current.X : canvasLeft) + dx);
            Canvas.SetTop(target, (double.IsNaN(canvasTop) ? current.Y : canvasTop) + dy);
        }
        else
        {
            Thickness margin = target.Margin;
            double ml = margin.Left, mt = margin.Top, mr = margin.Right, mb = margin.Bottom;
            if (target.HorizontalAlignment == HorizontalAlignment.Left) ml += dx;
            else if (target.HorizontalAlignment == HorizontalAlignment.Right) mr -= dx;
            else { ml += dx; mr -= dx; }
            if (target.VerticalAlignment == VerticalAlignment.Top) mt += dy;
            else if (target.VerticalAlignment == VerticalAlignment.Bottom) mb -= dy;
            else { mt += dy; mb -= dy; }
            target.Margin = new Thickness(ml, mt, mr, mb);
        }
        parent.UpdateLayout();
    }

    private static void ApplyWindowLayoutSize(Window window, Dictionary<string, string> layout)
    {
        if (window == null || layout == null) return;
        double visualScale = WindowContentVisualScale(window);
        string value;
        double size;
        bool resized = false;
        if (layout.TryGetValue("Width", out value))
        {
            if (value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) { window.Width = double.NaN; resized = true; }
            else if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out size) && size > 0) { window.Width = size; resized = true; }
        }
        if (layout.TryGetValue("Height", out value))
        {
            if (value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) { window.Height = double.NaN; resized = true; }
            else if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out size) && size > 0) { window.Height = size; resized = true; }
        }
        if (resized)
        {
            NormalizeWindowContentForResize(window, visualScale);
            if (!window.IsLoaded)
            {
                // Before Show(), WPF still reports the Viewbox's old viewport size. Retarget
                // once more during Loaded so a saved GM-UI window size fills the real viewport
                // before LoadedHwnd lets the AHK host reveal the window.
                RoutedEventHandler loaded = null;
                loaded = delegate
                {
                    window.Loaded -= loaded;
                    NormalizeWindowContentForResize(window, visualScale);
                };
                window.Loaded += loaded;
            }
        }
    }

    internal static double WindowContentVisualScale(Window window)
    {
        if (window == null) return double.NaN;
        window.UpdateLayout();
        var hostBox = window.Content as Viewbox;
        var child = hostBox == null ? null : hostBox.Child as FrameworkElement;
        if (hostBox == null || child == null) return double.NaN;
        double hostW = hostBox.ActualWidth > 1 ? hostBox.ActualWidth : window.Width;
        double hostH = hostBox.ActualHeight > 1 ? hostBox.ActualHeight : window.Height;
        double designW = child.ActualWidth > 1 ? child.ActualWidth : child.Width;
        double designH = child.ActualHeight > 1 ? child.ActualHeight : child.Height;
        double scale = double.NaN;
        if (hostW > 1 && designW > 1) scale = hostW / designW;
        if (hostH > 1 && designH > 1)
        {
            double heightScale = hostH / designH;
            scale = double.IsNaN(scale) ? heightScale : Math.Min(scale, heightScale);
        }
        if (double.IsNaN(scale)) return scale;
        return Math.Max(0.2, Math.Min(4, scale));
    }

    internal static void NormalizeWindowContentForResize(Window window, double visualScale = double.NaN)
    {
        if (window == null) return;
        window.UpdateLayout();
        var root = window.Content as FrameworkElement;
        if (root == null) return;
        // EngineHost wraps dialog roots in a uniform Viewbox so open-time fonts match the main
        // UI. Keep that host when GM-UI changes the viewport: retarget the design surface to
        // the new window aspect at the current visual density so the title/content fill the
        // window without letterboxing and without dropping back to unscaled DIP fonts.
        var hostBox = root as Viewbox;
        if (hostBox != null && hostBox.Stretch == Stretch.Uniform
            && hostBox.StretchDirection == StretchDirection.Both
            && hostBox.Child is FrameworkElement)
        {
            RetargetViewboxDesignSize(window, hostBox, (FrameworkElement)hostBox.Child, visualScale);
            return;
        }
        root.SetCurrentValue(FrameworkElement.WidthProperty, double.NaN);
        root.SetCurrentValue(FrameworkElement.HeightProperty, double.NaN);
        root.HorizontalAlignment = HorizontalAlignment.Stretch;
        root.VerticalAlignment = VerticalAlignment.Stretch;
    }

    private static void RetargetViewboxDesignSize(Window window, Viewbox hostBox, FrameworkElement child, double visualScale)
    {
        if (window == null || hostBox == null || child == null) return;
        // Width/Height already contain the restored GM-UI target while the pre-show Viewbox
        // can still report its original design viewport. Prefer the explicit target so the
        // first visible frame cannot be letterboxed and then relaid out.
        double viewportW = !window.IsLoaded && !double.IsNaN(window.Width) && window.Width > 1 ? window.Width
            : (hostBox.ActualWidth > 1 ? hostBox.ActualWidth : (window.ActualWidth > 1 ? window.ActualWidth : window.Width));
        double viewportH = !window.IsLoaded && !double.IsNaN(window.Height) && window.Height > 1 ? window.Height
            : (hostBox.ActualHeight > 1 ? hostBox.ActualHeight : (window.ActualHeight > 1 ? window.ActualHeight : window.Height));
        if (double.IsNaN(viewportW) || viewportW <= 1 || double.IsNaN(viewportH) || viewportH <= 1) return;
        double designW = child.ActualWidth > 1 ? child.ActualWidth : child.Width;
        double designH = child.ActualHeight > 1 ? child.ActualHeight : child.Height;
        double scale = visualScale;
        if (double.IsNaN(scale) || scale <= 0)
        {
            scale = 1;
            if (designW > 1 && designH > 1 && hostBox.ActualWidth > 1 && hostBox.ActualHeight > 1)
                scale = Math.Min(hostBox.ActualWidth / designW, hostBox.ActualHeight / designH);
            else if (designW > 1)
                scale = viewportW / designW;
        }
        if (scale < 0.2) scale = 0.2;
        if (scale > 4) scale = 4;
        child.SetCurrentValue(FrameworkElement.WidthProperty, viewportW / scale);
        child.SetCurrentValue(FrameworkElement.HeightProperty, viewportH / scale);
        child.HorizontalAlignment = HorizontalAlignment.Stretch;
        child.VerticalAlignment = VerticalAlignment.Stretch;
        hostBox.UpdateLayout();
    }

    internal static Point ReadAnchorPosition(FrameworkElement target, string anchorName, string anchorKind)
    {
        if (target == null) return new Point(0, 0);
        double ax, ay;
        AnchorFactors(anchorKind, out ax, out ay);
        var window = target as Window;
        if (window != null)
        {
            Rect area = SystemParameters.WorkArea;
            return new Point(window.Left + window.ActualWidth * ax - (area.Left + area.Width * ax), window.Top + window.ActualHeight * ay - (area.Top + area.Height * ay));
        }
        var parent = (LogicalTreeHelper.GetParent(target) ?? VisualParent(target)) as FrameworkElement;
        if (parent == null) return new Point(target.Margin.Left, target.Margin.Top);
        FrameworkElement anchor = anchorName == "窗口" ? Window.GetWindow(target) : parent;
        if (anchor == null) anchor = parent;
        Point targetOrigin, anchorOrigin = new Point(0, 0);
        try { targetOrigin = target.TranslatePoint(new Point(0, 0), parent); }
        catch { targetOrigin = new Point(target.Margin.Left, target.Margin.Top); }
        if (!ReferenceEquals(anchor, parent))
        {
            try { anchorOrigin = anchor.TranslatePoint(new Point(0, 0), parent); }
            catch { anchorOrigin = new Point(0, 0); }
        }
        return new Point(
            targetOrigin.X + target.ActualWidth * ax - (anchorOrigin.X + anchor.ActualWidth * ax),
            targetOrigin.Y + target.ActualHeight * ay - (anchorOrigin.Y + anchor.ActualHeight * ay));
    }

    private static void AnchorFactors(string anchorKind, out double ax, out double ay)
    {
        ax = anchorKind != null && anchorKind.StartsWith("中") ? .5 : anchorKind != null && anchorKind.StartsWith("右") ? 1 : 0;
        ay = anchorKind != null && (anchorKind.EndsWith("中") || anchorKind == "中心") ? .5 : anchorKind != null && anchorKind.EndsWith("下") ? 1 : 0;
    }

    internal static DependencyProperty Property(FrameworkElement fe, string name)
    {
        if (name == "CornerRadius" && fe is Control) return ControlCornerRadius;
        if (name == "HoverBackground" && fe is Control) return ControlHoverBackground;
        if (name == "PressedBackground" && fe is Control) return ControlPressedBackground;
        if (name == "Spacing" && fe is StackPanel) return StackPanelSpacing;
        if (name == "ChildAlignment" && fe is StackPanel) return StackPanelChildAlignment;
        if (name == "RelativeFontSize") return System.Windows.Documents.TextElement.FontSizeProperty;
        var descriptor = DependencyPropertyDescriptor.FromName(name, fe.GetType(), fe.GetType());
        return descriptor == null || descriptor.IsReadOnly ? null : descriptor.DependencyProperty;
    }

    private static void ApplyStackPanelSpacing(StackPanel panel)
    {
        if (panel == null) return;
        StackSpacingState state = stackSpacings.GetValue(panel, p => new StackSpacingState());
        if (!state.Hooked)
        {
            state.Hooked = true;
            panel.LayoutUpdated += delegate { ApplyStackPanelSpacing(panel); };
        }
        if (state.Applying) return;
        state.Applying = true;
        try
        {
            double spacing = 0;
            object value = panel.GetValue(StackPanelSpacing);
            if (value is double && !double.IsNaN((double)value) && !double.IsInfinity((double)value)) spacing = Math.Max(0, (double)value);
            var live = new HashSet<FrameworkElement>();
            int index = 0;
            foreach (UIElement element in panel.Children)
            {
                var child = element as FrameworkElement;
                if (child == null) { index++; continue; }
                live.Add(child);
                Thickness original;
                if (!state.Original.TryGetValue(child, out original))
                {
                    original = child.Margin;
                    state.Original[child] = original;
                }
                else
                {
                    Thickness applied;
                    if (state.Applied.TryGetValue(child, out applied) && child.Margin != applied)
                    {
                        original = child.Margin;
                        state.Original[child] = original;
                        state.Applied.Remove(child);
                    }
                }
                if (spacing <= 0)
                {
                    if (child.Margin != original) child.SetCurrentValue(FrameworkElement.MarginProperty, original);
                }
                else
                {
                    double add = index == 0 ? 0 : spacing;
                    Thickness desired = panel.Orientation == Orientation.Horizontal
                        ? new Thickness(original.Left + add, original.Top, original.Right, original.Bottom)
                        : new Thickness(original.Left, original.Top + add, original.Right, original.Bottom);
                    if (child.Margin != desired) child.SetCurrentValue(FrameworkElement.MarginProperty, desired);
                    state.Applied[child] = desired;
                }
                index++;
            }
            foreach (var child in state.Original.Keys.Where(x => !live.Contains(x)).ToArray())
            {
                state.Original.Remove(child);
                state.Applied.Remove(child);
            }
            if (spacing <= 0) state.Applied.Clear();
        }
        finally { state.Applying = false; }
    }

    private static void ApplyStackPanelChildAlignment(StackPanel panel)
    {
        if (panel == null) return;
        StackAlignState state = stackAligns.GetValue(panel, p => new StackAlignState());
        if (!state.Hooked)
        {
            state.Hooked = true;
            panel.LayoutUpdated += delegate { ApplyStackPanelChildAlignment(panel); };
        }
        if (state.Applying) return;
        state.Applying = true;
        try
        {
            var align = (HorizontalAlignment)panel.GetValue(StackPanelChildAlignment);
            if (align != HorizontalAlignment.Left && align != HorizontalAlignment.Center && align != HorizontalAlignment.Right)
                align = HorizontalAlignment.Left;
            if (!state.CapturedPanel)
            {
                state.PanelOriginal = panel.HorizontalAlignment;
                state.CapturedPanel = true;
            }
            // ChildAlignment positions the group on the axis that can move it in
            // its parent. A horizontal StackPanel uses HorizontalAlignment;
            // a vertical StackPanel uses child HorizontalAlignment.
            if (panel.Orientation == Orientation.Horizontal)
            {
                if (panel.HorizontalAlignment != align)
                    panel.SetCurrentValue(FrameworkElement.HorizontalAlignmentProperty, align);
                if (state.CapturedPanel && panel.VerticalAlignment != VerticalAlignment.Top
                    && panel.VerticalAlignment != VerticalAlignment.Center
                    && panel.VerticalAlignment != VerticalAlignment.Bottom
                    && panel.VerticalAlignment != VerticalAlignment.Stretch)
                    panel.SetCurrentValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Stretch);
            }
            else if (state.CapturedPanel && panel.HorizontalAlignment != state.PanelOriginal)
                panel.SetCurrentValue(FrameworkElement.HorizontalAlignmentProperty, state.PanelOriginal);
            var live = new HashSet<FrameworkElement>();
            foreach (UIElement element in panel.Children)
            {
                var child = element as FrameworkElement;
                if (child == null) continue;
                live.Add(child);
                if (!state.Original.ContainsKey(child)) state.Original[child] = child.HorizontalAlignment;
                if (!state.OriginalVertical.ContainsKey(child)) state.OriginalVertical[child] = child.VerticalAlignment;
                if (panel.Orientation == Orientation.Horizontal)
                {
                    if (child.HorizontalAlignment != align)
                        child.SetCurrentValue(FrameworkElement.HorizontalAlignmentProperty, align);
                    if (child.VerticalAlignment != VerticalAlignment.Center)
                        child.SetCurrentValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
                }
                else if (child.HorizontalAlignment != align)
                    child.SetCurrentValue(FrameworkElement.HorizontalAlignmentProperty, align);
            }
            foreach (var child in state.Original.Keys.Where(x => !live.Contains(x)).ToArray())
            {
                state.Original.Remove(child);
                state.OriginalVertical.Remove(child);
            }
        }
        finally { state.Applying = false; }
    }

    internal static List<Entry> Live()
    {
        elements.RemoveAll(x => !x.IsAlive);
        var result = new List<Entry>();
        foreach (var weak in elements)
        {
            var fe = weak.Target as FrameworkElement;
            Entry entry;
            if (fe != null && entries.TryGetValue(fe, out entry) && Window.GetWindow(fe) != null) result.Add(entry);
        }
        return result;
    }

    internal static string Text(object value)
    {
        if (value == null) return "";
        var converter = TypeDescriptor.GetConverter(value.GetType());
        return converter.CanConvertTo(typeof(string)) ? converter.ConvertToInvariantString(value) : value.ToString();
    }

    internal static object ConvertValue(Type type, string value)
    {
        if (type == typeof(double) && value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) return double.NaN;
        object result = TypeDescriptor.GetConverter(type).ConvertFromInvariantString(value);
        var brush = result as Freezable;
        if (brush != null && brush.CanFreeze) brush.Freeze();
        return result;
    }

    internal static bool IsThemeColor(string value)
    {
        return !string.IsNullOrEmpty(value) && value.StartsWith("$Theme:", StringComparison.Ordinal);
    }
    internal static string ThemeColorKey(string value)
    {
        return IsThemeColor(value) ? value.Substring("$Theme:".Length) : "";
    }
    internal static bool IsColorProperty(string name)
    {
        return name == "Color" || name == "Background" || name == "HoverBackground" || name == "PressedBackground" || name == "Foreground" || name == "BorderBrush";
    }

    private static void Apply(Entry entry)
    {
        Apply(entry, null);
    }

    private static void Apply(Entry entry, Dictionary<string, string> overlay)
    {
        var fe = entry.Element.Target as FrameworkElement;
        if (fe == null) return;
        // A theme/font change may replace a local value while an override is active.
        // Keep that new base value for reset instead of restoring a stale startup value.
        foreach (string name in entry.Applied)
        {
            var dp = Property(fe, name);
            if (entry.LastApplied.ContainsKey(name) && Text(fe.GetValue(dp)) != entry.LastApplied[name])
            {
                entry.Original[name] = fe.GetValue(dp);
                if (fe.ReadLocalValue(dp) == DependencyProperty.UnsetValue) entry.Unset.Add(name);
                else entry.Unset.Remove(name);
            }
        }
        var desired = new Dictionary<string, string>();
        var instanceKeys = new HashSet<string>();
        Dictionary<string, string> instance;
        string layoutId = LayoutId(fe);
        string boundKey = BoundStyleKey(layoutId);
        if (boundKey != "" && Values.TryGetValue(boundKey, out instance))
            foreach (var pair in instance) { desired[pair.Key] = pair.Value; instanceKeys.Add(pair.Key); }
        else if (layoutId != "" && InstanceStyles.TryGetValue(layoutId, out instance))
            foreach (var pair in instance) { desired[pair.Key] = pair.Value; instanceKeys.Add(pair.Key); }
        if (overlay != null)
            foreach (var pair in overlay) { desired[pair.Key] = pair.Value; instanceKeys.Add(pair.Key); }
        foreach (string name in entry.Applied.ToArray())
        {
            if (desired.ContainsKey(name)) continue;
            if (entry.Frozen.Contains(name)) continue;
            var dp = Property(fe, name);
            if (entry.ResourceKeys.ContainsKey(name)) fe.SetResourceReference(dp, entry.ResourceKeys[name]);
            else if (entry.Unset.Contains(name)) fe.ClearValue(dp);
            else fe.SetCurrentValue(dp, entry.Original[name]);
            entry.Applied.Remove(name);
        }
        foreach (var pair in desired)
        {
            // Window dimensions are instance layout, not a shared style.  Keeping them out of
            // the common Window override prevents resizing one auxiliary window from changing
            // every other window (including the main surface).
            if (fe is Window && (pair.Key == "Padding" || IsWindowExtra(pair.Key)
                || pair.Key == "Width" || pair.Key == "Height" || pair.Key == "MinWidth" || pair.Key == "MinHeight"
                || pair.Key == "MaxWidth" || pair.Key == "MaxHeight" || pair.Key == "SizeMode")) continue;
            if (entry.Frozen.Contains(pair.Key) && !instanceKeys.Contains(pair.Key)) continue;
            var dp = Property(fe, pair.Key);
            if (dp == null || BindingOperations.IsDataBound(fe, dp)) continue;
            try
            {
                if (!entry.Applied.Contains(pair.Key))
                {
                    // Capture at first edit, after startup theme/font updates have completed.
                    entry.Original[pair.Key] = fe.GetValue(dp);
                    var local = fe.ReadLocalValue(dp);
                    if (local != null && local.GetType().Name == "ResourceReferenceExpression")
                    {
                        var key = local.GetType().GetProperty("ResourceKey", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic);
                        if (key != null) entry.ResourceKeys[pair.Key] = key.GetValue(local, null);
                    }
                    if (fe.ReadLocalValue(dp) == DependencyProperty.UnsetValue) entry.Unset.Add(pair.Key);
                    else entry.Unset.Remove(pair.Key);
                }
                if (IsColorProperty(pair.Key) && IsThemeColor(pair.Value))
                    fe.SetResourceReference(dp, ThemeColorKey(pair.Value));
                else if (pair.Key == "RelativeFontSize")
                    fe.SetCurrentValue(dp, ThemeFontSize(fe) + (double)ConvertValue(typeof(double), pair.Value));
                else
                    fe.SetCurrentValue(dp, ConvertValue(dp.PropertyType, pair.Value));
                entry.Applied.Add(pair.Key);
                entry.LastApplied[pair.Key] = Text(fe.GetValue(dp));
                if (pair.Key == "CornerRadius") ApplyCorners(fe as Control);
            }
            catch (Exception ex) { LoadError = entry.Key + "/" + pair.Key + ": " + ex.Message; }
        }
        ApplyButtonChrome(fe as Button, entry, desired);
        if (fe is Control) ApplyCorners((Control)fe);
        if (fe is ComboBox) ApplyComboDropDown((ComboBox)fe);
        if (fe is Window) ApplyWindowChrome((Window)fe, entry, desired);
    }

    internal static List<FrameworkElement> StyleChildren(DependencyObject parent)
    {
        var result = new List<FrameworkElement>();
        if (parent == null) return result;
        var children = LogicalTreeHelper.GetChildren(parent).OfType<DependencyObject>().ToList();
        if (children.Count == 0 && parent is Visual)
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++) children.Add(VisualTreeHelper.GetChild(parent, i));
        foreach (DependencyObject child in children)
        {
            var element = child as FrameworkElement;
            if (element == null)
            {
                result.AddRange(StyleChildren(child));
                continue;
            }
            if (element.TemplatedParent is Control && !(element.TemplatedParent is ContentPresenter)) continue;
            if (element is ComboBoxItem || element is ListBoxItem || element is MenuItem) continue;
            result.Add(element);
        }
        return result;
    }

    internal static bool IsCompositeRoot(string key)
    {
        return !string.IsNullOrEmpty(key) && Composites.ContainsKey(key);
    }

    internal static bool IsCompositeChild(string key)
    {
        if (string.IsNullOrEmpty(key) || IsCompositeRoot(key)) return false;
        foreach (string root in Composites.Keys)
            if (key.StartsWith(root + "/", StringComparison.Ordinal)) return true;
        return false;
    }

    internal static StyleBranch CloneBranch(StyleBranch source)
    {
        if (source == null) return null;
        var copy = new StyleBranch
        {
            Key = source.Key, Type = source.Type, Path = source.Path,
            Properties = new Dictionary<string, string>(source.Properties)
        };
        foreach (var child in source.Children) copy.Children.Add(CloneBranch(child));
        return copy;
    }

    internal static bool IsWindowExtra(string name)
    {
        return Array.IndexOf(WindowExtraProperties, name) >= 0;
    }

    internal static bool IsWindowKey(string key)
    {
        if (string.IsNullOrEmpty(key)) return false;
        if (key == "通用/Window" || key.StartsWith("Window.")) return true;
        if (key.StartsWith("Window") && key.Length > 6)
        {
            int n;
            return int.TryParse(key.Substring(6), out n);
        }
        string cloneBase;
        return CloneBases.TryGetValue(key, out cloneBase) && (cloneBase == "通用/Window" || cloneBase.StartsWith("Window."));
    }

    internal static FrameworkElement WindowBody(Window window)
    {
        if (window == null) return null;
        var named = window.FindName("WindowBody") as FrameworkElement;
        if (named != null) return named;
        FrameworkElement root = window.Content as FrameworkElement;
        var box = root as Viewbox;
        if (box != null) root = box.Child as FrameworkElement;
        var grid = root as Grid;
        if (grid == null) return root;
        foreach (UIElement child in grid.Children)
        {
            var fe = child as FrameworkElement;
            if (fe != null && Grid.GetRow(fe) > 0) return fe;
        }
        return null;
    }

    private static readonly string[][] ChromeButtons = {
        new[] { "ShowMinimize", "BtnMinimize" },
        new[] { "ShowMaximize", "BtnMaximize" },
        new[] { "ShowPin", "BtnPin" },
        new[] { "ShowClose", "BtnClosePanel" },
        new[] { "ShowClose", "BtnWinClose" },
        new[] { "ShowClose", "BtnClose" }
    };

    private static void ApplyWindowChrome(Window window, Entry entry, Dictionary<string, string> desired)
    {
        foreach (string prop in WindowExtraProperties)
        {
            string value;
            bool has = desired.TryGetValue(prop, out value);
            foreach (var map in ChromeButtons)
            {
                if (map[0] != prop) continue;
                var btn = window.FindName(map[1]) as UIElement;
                if (btn == null) continue;
                if (!entry.Original.ContainsKey(prop + "." + map[1]))
                    entry.Original[prop + "." + map[1]] = btn.Visibility;
                if (has)
                    btn.Visibility = value.Equals("True", StringComparison.OrdinalIgnoreCase) ? Visibility.Visible : Visibility.Collapsed;
                else if (entry.Applied.Contains(prop))
                {
                    object original;
                    if (entry.Original.TryGetValue(prop + "." + map[1], out original) && original is Visibility)
                        btn.Visibility = (Visibility)original;
                }
            }
            if (has) entry.Applied.Add(prop);
            else entry.Applied.Remove(prop);
        }
        var body = WindowBody(window);
        if (body != null)
        {
            if (!entry.Original.ContainsKey("Padding"))
                entry.Original["Padding"] = body.Margin;
            string pad;
            if (desired.TryGetValue("Padding", out pad))
            {
                try
                {
                    body.Margin = (Thickness)ConvertValue(typeof(Thickness), pad);
                    entry.Applied.Add("Padding");
                    entry.LastApplied["Padding"] = pad;
                }
                catch (Exception ex) { LoadError = entry.Key + "/Padding: " + ex.Message; }
            }
            else if (entry.Applied.Contains("Padding"))
            {
                object original;
                if (entry.Original.TryGetValue("Padding", out original) && original is Thickness)
                    body.Margin = (Thickness)original;
                entry.Applied.Remove("Padding");
            }
        }
        string radiusText;
        if (desired.TryGetValue("CornerRadius", out radiusText))
        {
            try
            {
                var radius = (CornerRadius)ConvertValue(typeof(CornerRadius), radiusText);
                window.Resources["WindowRadius"] = radius;
                var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(window);
                if (chrome != null) chrome.CornerRadius = radius;
                var overlay = window.FindName("WindowBorderOverlay") as Border;
                if (overlay != null) overlay.CornerRadius = radius;
                var rootBorder = window.Content as Border;
                if (rootBorder != null) rootBorder.CornerRadius = radius;
                ApplyCorners(window);
                entry.Applied.Add("CornerRadius");
                entry.LastApplied["CornerRadius"] = radiusText;
            }
            catch (Exception ex) { LoadError = entry.Key + "/CornerRadius: " + ex.Message; }
        }
        string background;
        if (desired.TryGetValue("Background", out background))
        {
            var rootBorder = window.Content as Border;
            if (rootBorder != null)
            {
                if (!entry.Original.ContainsKey("SurfaceBackground"))
                    entry.Original["SurfaceBackground"] = rootBorder.Background;
                if (IsThemeColor(background)) rootBorder.SetResourceReference(Border.BackgroundProperty, ThemeColorKey(background));
                else
                {
                    try { rootBorder.Background = (Brush)ConvertValue(typeof(Brush), background); }
                    catch (Exception ex) { LoadError = entry.Key + "/Background: " + ex.Message; }
                }
            }
        }
    }

    private static readonly Dictionary<Window, Dictionary<string, object>> resourceOriginals = new Dictionary<Window, Dictionary<string, object>>();
    internal static void ApplyResources(Window window)
    {
        if (IsEditorWindow(window)) return;
        Dictionary<string, object> originals;
        if (!resourceOriginals.TryGetValue(window, out originals))
        {
            originals = new Dictionary<string, object>();
            resourceOriginals[window] = originals;
            window.Closed += delegate { resourceOriginals.Remove(window); };
        }
        foreach (var item in originals.ToArray())
            if (!Values.ContainsKey("颜色/" + item.Key)) { window.Resources[item.Key] = item.Value; originals.Remove(item.Key); }
        foreach (var item in Values.Where(x => x.Key.StartsWith("颜色/")))
        {
            string name = item.Key.Substring(3);
            var old = window.TryFindResource(name) as SolidColorBrush;
            if (old == null || !item.Value.ContainsKey("Color")) continue;
            if (!originals.ContainsKey(name)) originals[name] = old;
            try
            {
                string value = item.Value["Color"];
                window.Resources[name] = IsThemeColor(value) ? window.TryFindResource(ThemeColorKey(value)) : ConvertValue(typeof(Brush), value);
            }
            catch (Exception ex) { LoadError = name + ": " + ex.Message; }
        }
    }

    internal static Dictionary<string, string> Colors(Window window)
    {
        var result = new Dictionary<string, string>();
        if (Application.Current != null) CollectColors(Application.Current.Resources, result);
        CollectColors(window.Resources, result);
        return result;
    }
    private static void CollectColors(ResourceDictionary dictionary, Dictionary<string, string> result)
    {
        foreach (var child in dictionary.MergedDictionaries) CollectColors(child, result);
        foreach (object key in dictionary.Keys)
            if (key is string && dictionary[key] is SolidColorBrush) result[(string)key] = Text(dictionary[key]);
    }

    internal static void Refresh()
    {
        foreach (var entry in Live())
        {
            Apply(entry);
            var fe = entry.Element.Target as FrameworkElement;
            if (fe != null) ApplyLayout(fe);
        }
        foreach (Window window in Application.Current.Windows.Cast<Window>().ToArray()) ApplyResources(window);
    }

    internal static void PreviewInstance(FrameworkElement element, Dictionary<string, string> values)
    {
        EnsureRegistered(element);
        Entry entry;
        if (!entries.TryGetValue(element, out entry)) return;
        string id = LayoutId(element);
        Dictionary<string, string> saved;
        bool hadSaved = InstanceStyles.TryGetValue(id, out saved);
        InstanceStyles.Remove(id);
        try { Apply(entry, values); }
        finally { if (hadSaved) InstanceStyles[id] = saved; }
    }

    internal static void ApplyCorners(Control control)
    {
        if (control == null) return;
        var list = FindControlBorders(control);
        for (int i = 0; i < list.Count; i++) ApplyCornerToBorder(control, list[i]);
    }

    private static void ApplyCornerToBorder(Control control, Border border)
    {
        if (border == null) return;
        if (control.ReadLocalValue(ControlCornerRadius) == DependencyProperty.UnsetValue)
        {
            Corners old;
            if (corners.TryGetValue(border, out old)) { border.SetCurrentValue(Border.CornerRadiusProperty, old.Value); corners.Remove(border); }
        }
        else
        {
            corners.GetValue(border, b => new Corners { Value = b.CornerRadius });
            border.SetValue(Border.CornerRadiusProperty, control.GetValue(ControlCornerRadius));
        }
    }

    internal static void ApplyComboDropDown(ComboBox combo)
    {
        if (combo == null) return;
        var drop = FindComboDropDownBorder(combo);
        if (drop != null) drop.MaxHeight = combo.MaxDropDownHeight;
    }

    private static void ApplyButtonChrome(Button button, Entry entry, Dictionary<string, string> desired)
    {
        if (button == null || entry == null) return;
        // Keep the original button template intact. Replacing it with a generic shell
        // breaks business-specific buttons such as fold/setting/edit controls by
        // removing their custom layout, spacing and visual states.
        // CornerRadius is applied by `ApplyCorners`, while hover/pressed colors are
        // handled through attached-property event hooks that update Background.
    }

    internal static double ThemeFontSize(FrameworkElement element)
    {
        var window = Window.GetWindow(element);
        if (window != null && window.FontSize > 0) return window.FontSize;
        return Application.Current != null && Application.Current.MainWindow != null ? Application.Current.MainWindow.FontSize : 15;
    }

    private static void ApplyHoverBackground(Control control)
    {
        if (control == null) return;
        var state = hovers.GetValue(control, c => new HoverState());
        if (!state.Hooked)
        {
            state.Hooked = true;
            control.MouseEnter += delegate
            {
                var hover = control.GetValue(ControlHoverBackground) as Brush;
                if (hover == null) return;
                state.Hovering = true;
                ApplyTransientBackground(control, hover, ref state.Base, ref state.BorderBase, ref state.Border);
            };
            control.MouseLeave += delegate
            {
                if (!state.Hovering) return;
                state.Hovering = false;
                RestoreTransientBackground(control, state.Base, state.BorderBase, state.Border);
                state.Border = null;
            };
        }
        if (!state.Hovering) state.Base = control.Background;
    }

    private static void ApplyPressedBackground(Control control)
    {
        if (control == null) return;
        var state = presses.GetValue(control, c => new PressState());
        if (!state.Hooked)
        {
            state.Hooked = true;
            control.PreviewMouseLeftButtonDown += delegate
            {
                var pressed = control.GetValue(ControlPressedBackground) as Brush;
                if (pressed == null) return;
                state.Pressed = true;
                ApplyTransientBackground(control, pressed, ref state.Base, ref state.BorderBase, ref state.Border);
            };
            MouseButtonEventHandler restore = delegate
            {
                if (!state.Pressed) return;
                state.Pressed = false;
                RestoreTransientBackground(control, state.Base, state.BorderBase, state.Border);
                state.Border = null;
            };
            control.PreviewMouseLeftButtonUp += restore;
            control.LostMouseCapture += delegate { restore(control, null); };
            control.MouseLeave += delegate
            {
                if (!state.Pressed || control.IsMouseCaptured) return;
                state.Pressed = false;
                RestoreTransientBackground(control, state.Base, state.BorderBase, state.Border);
                state.Border = null;
            };
        }
        if (!state.Pressed) state.Base = control.Background;
    }

    private static void ApplyTransientBackground(Control control, Brush brush, ref Brush baseBrush, ref Brush borderBase, ref Border border)
    {
        baseBrush = control.Background;
        border = FindControlBorder(control);
        borderBase = null;
        if (border != null)
            border.SetValue(Border.BackgroundProperty, brush);
        control.SetValue(Control.BackgroundProperty, brush);
    }

    private static void RestoreTransientBackground(Control control, Brush baseBrush, Brush borderBase, Border border)
    {
        // Always clear the template border override so TemplateBinding Background can resume.
        // Capturing border.Background during MouseEnter is unsafe when a template Trigger
        // already painted the hover color onto the same Border.
        if (border != null)
            border.ClearValue(Border.BackgroundProperty);
        if (baseBrush != null) control.SetValue(Control.BackgroundProperty, baseBrush);
        else control.ClearValue(Control.BackgroundProperty);
    }

    internal static object DisplayValue(FrameworkElement element, string name, DependencyProperty dp)
    {
        if (name == "CornerRadius" && element is Window)
        {
            if (element.Resources.Contains("WindowRadius")) return element.Resources["WindowRadius"];
            var resource = element.TryFindResource("WindowRadius");
            if (resource is CornerRadius) return resource;
        }
        if (name == "CornerRadius" && element is Control && element.ReadLocalValue(dp) == DependencyProperty.UnsetValue)
        {
            var border = FindControlBorder((Control)element);
            if (border != null) return border.CornerRadius;
        }
        if (name == "MaxDropDownHeight" && element is ComboBox && element.ReadLocalValue(dp) == DependencyProperty.UnsetValue)
        {
            var drop = FindComboDropDownBorder((ComboBox)element);
            if (drop != null) return drop.MaxHeight;
        }
        if (name == "HoverBackground" || name == "PressedBackground")
        {
            var brush = element.GetValue(dp) as Brush;
            if (IsVisibleBrush(brush)) return brush;
            return FallbackButtonChrome(element, name);
        }
        return element.GetValue(dp);
    }

    internal static bool IsVisibleBrush(Brush brush)
    {
        if (brush == null || brush == Brushes.Transparent) return false;
        var solid = brush as SolidColorBrush;
        return solid == null || solid.Color.A > 0;
    }

    internal static Brush FallbackButtonChrome(FrameworkElement element, string name)
    {
        return FallbackButtonChrome(name, element);
    }

    internal static Brush FallbackButtonChrome(string name, params FrameworkElement[] roots)
    {
        string[] keys = name == "HoverBackground"
            ? new[] { "ActionHoverBg", "ControlBorder" }
            : new[] { "ActionPressBg", "BtnPressBg", "ActionHoverBg", "ActionBg" };
        foreach (string key in keys)
        {
            if (roots == null) continue;
            for (int i = 0; i < roots.Length; i++)
            {
                if (roots[i] == null) continue;
                var brush = roots[i].TryFindResource(key) as Brush;
                if (IsVisibleBrush(brush)) return brush;
            }
        }
        return null;
    }

    internal static Border FindControlBorder(Control control)
    {
        var list = FindControlBorders(control);
        return list.Count > 0 ? list[0] : null;
    }

    internal static Border FindComboDropDownBorder(ComboBox combo)
    {
        return combo == null ? null : FindPopupBorder(combo);
    }

    internal static List<Border> FindControlBorders(Control control)
    {
        var result = new List<Border>();
        if (control == null) return result;
        control.ApplyTemplate();
        Border own = null, chrome = null, drop = null;
        var queue = new Queue<DependencyObject>();
        queue.Enqueue(control);
        while (queue.Count > 0)
        {
            var node = queue.Dequeue();
            var nested = node as Control;
            if (nested != null && !ReferenceEquals(nested, control)) nested.ApplyTemplate();
            var popup = node as Popup;
            if (popup != null)
            {
                if (drop == null) drop = FirstBorder(popup.Child ?? popup);
                continue;
            }
            var border = node as Border;
            if (border != null)
            {
                if (own == null && ReferenceEquals(border.TemplatedParent, control)) own = border;
                else if (chrome == null && control is ComboBox && border.TemplatedParent is ToggleButton) chrome = border;
            }
            if (node is Visual)
            {
                int count = VisualTreeHelper.GetChildrenCount(node);
                for (int i = 0; i < count; i++) queue.Enqueue(VisualTreeHelper.GetChild(node, i));
            }
        }
        if (own != null) result.Add(own);
        if (chrome != null && !result.Contains(chrome)) result.Add(chrome);
        if (drop != null && !result.Contains(drop)) result.Add(drop);
        return result;
    }

    private static Border FindPopupBorder(DependencyObject root)
    {
        if (root == null) return null;
        var queue = new Queue<DependencyObject>();
        queue.Enqueue(root);
        while (queue.Count > 0)
        {
            var node = queue.Dequeue();
            var popup = node as Popup;
            if (popup != null) return FirstBorder(popup.Child ?? popup);
            if (!(node is Visual)) continue;
            int count = VisualTreeHelper.GetChildrenCount(node);
            for (int i = 0; i < count; i++) queue.Enqueue(VisualTreeHelper.GetChild(node, i));
        }
        return null;
    }

    private static Border FirstBorder(DependencyObject root)
    {
        if (root == null) return null;
        var border = root as Border;
        if (border != null) return border;
        if (!(root is Visual)) return null;
        int count = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var found = FirstBorder(VisualTreeHelper.GetChild(root, i));
            if (found != null) return found;
        }
        return null;
    }

    internal static void ThemeChanged(Window window, string name)
    {
        if (!initialized) return;
        Dictionary<string, object> originals;
        if (resourceOriginals.TryGetValue(window, out originals) && originals.ContainsKey(name)) originals[name] = window.TryFindResource(name);
        if (refreshPending) return;
        refreshPending = true;
        window.Dispatcher.BeginInvoke(new Action(delegate { refreshPending = false; Refresh(); }));
    }

    internal static void Open(Window owner)
    {
        if (!development) return;
        if (editor != null) { editor.Activate(); return; }
        WindowState ownerState = owner.WindowState;
        SizeToContent ownerSizing = owner.SizeToContent;
        double ownerLeft = owner.Left, ownerTop = owner.Top;
        double ownerWidth = owner.Width, ownerHeight = owner.Height;
        editor = new RmtStyleEditor(owner);
        editor.Closed += delegate { editor = null; };
        editor.Show();
        Action restoreOwnerLayout = delegate
        {
            if (owner == null || !owner.IsLoaded) return;
            if (owner.WindowState != ownerState) owner.WindowState = ownerState;
            if (ownerState == WindowState.Normal && ownerSizing == SizeToContent.Manual)
            {
                if (!double.IsNaN(ownerWidth) && ownerWidth > 0) owner.Width = ownerWidth;
                if (!double.IsNaN(ownerHeight) && ownerHeight > 0) owner.Height = ownerHeight;
                if (!double.IsNaN(ownerLeft)) owner.Left = ownerLeft;
                if (!double.IsNaN(ownerTop)) owner.Top = ownerTop;
            }
            owner.UpdateLayout();
        };
        restoreOwnerLayout();
        owner.Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, restoreOwnerLayout);
    }

    private static void Load()
    {
        if (!File.Exists(path)) return;
        try
        {
            Values.Clear();
            Layouts.Clear();
            CloneBases.Clear();
            DisplayNames.Clear();
            Composites.Clear();
            InstanceStyles.Clear();
            StyleBindings.Clear();
            HiddenStyles.Clear();
            var doc = new XmlDocument { XmlResolver = null };
            using (var reader = XmlReader.Create(path, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null })) doc.Load(reader);
            foreach (XmlElement style in doc.SelectNodes("/CommonStyles/Style"))
            {
                var properties = ReadStyleProperties(style);
                string styleKey = style.GetAttribute("key");
                Values[styleKey] = properties;
                if (style.HasAttribute("base")) CloneBases[styleKey] = style.GetAttribute("base");
                if (style.HasAttribute("display")) DisplayNames[styleKey] = style.GetAttribute("display");
                if (style.GetAttribute("composite") == "1" || style.SelectNodes("Child").Count > 0)
                {
                    var branch = ReadStyleBranch(style, styleKey, style.GetAttribute("type"), "");
                    branch.Properties = properties;
                    Composites[styleKey] = branch;
                }
            }
            foreach (XmlElement layout in doc.SelectNodes("/CommonStyles/Layout"))
            {
                var properties = new Dictionary<string, string>();
                foreach (XmlElement prop in layout.SelectNodes("Property"))
                    properties[prop.GetAttribute("name")] = prop.GetAttribute("value");
                string layoutKey = layout.GetAttribute("key");
                if (!string.IsNullOrEmpty(layoutKey)) Layouts[layoutKey] = properties;
            }
            foreach (XmlElement binding in doc.SelectNodes("/CommonStyles/Binding"))
            {
                string controlKey = binding.GetAttribute("control");
                string styleKey = binding.GetAttribute("style");
                if (!string.IsNullOrEmpty(controlKey) && !string.IsNullOrEmpty(styleKey))
                {
                    StyleBindings[controlKey] = styleKey;
                    SyncBoundInstance(controlKey);
                }
            }
            foreach (XmlElement instance in doc.SelectNodes("/CommonStyles/Instance"))
            {
                var properties = new Dictionary<string, string>();
                foreach (XmlElement prop in instance.SelectNodes("Property"))
                    properties[prop.GetAttribute("name")] = prop.GetAttribute("value");
                string instanceKey = instance.GetAttribute("key");
                if (!string.IsNullOrEmpty(instanceKey) && !StyleBindings.ContainsKey(instanceKey))
                    ImportLegacyInstance(instanceKey, properties);
            }
            foreach (XmlElement hidden in doc.SelectNodes("/CommonStyles/Hidden"))
            {
                string hiddenKey = hidden.GetAttribute("key");
                if (!string.IsNullOrEmpty(hiddenKey)) HiddenStyles.Add(hiddenKey);
            }
            foreach (XmlElement group in doc.SelectNodes("/CommonStyles/Group"))
            {
                string groupKey = group.GetAttribute("key");
                string groupName = group.GetAttribute("display");
                if (!string.IsNullOrEmpty(groupKey) && !string.IsNullOrEmpty(groupName)) DisplayNames[groupKey] = groupName;
            }
        }
        catch (Exception ex) { LoadError = "样式配置读取失败：" + ex.Message; }
    }

    private static Dictionary<string, string> ReadStyleProperties(XmlElement owner)
    {
        var properties = new Dictionary<string, string>();
        foreach (XmlElement prop in owner.SelectNodes("Property"))
            if (Properties.Contains(prop.GetAttribute("name")) || IsWindowExtra(prop.GetAttribute("name")) || prop.GetAttribute("name") == "Color")
            {
                string name = prop.GetAttribute("name"), value = prop.GetAttribute("value");
                try
                {
                    if (name == "SizeMode" || IsWindowExtra(name)) { properties[name] = value; continue; }
                    if (IsColorProperty(name) && IsThemeColor(value)) { properties[name] = value; continue; }
                    var probe = (name == "Spacing" || name == "ChildAlignment") ? (FrameworkElement)new StackPanel() : new Button();
                    var dp = name == "Color" ? null : Property(probe, name);
                    object converted = ConvertValue(dp == null ? typeof(Brush) : dp.PropertyType, value);
                    if (dp != null && !dp.IsValidValue(converted)) throw new ArgumentException(name + " 值无效");
                    properties[name] = value;
                }
                catch (Exception ex) { LoadError = "已忽略无效配置 " + name + ": " + ex.Message; }
            }
        return properties;
    }

    private static StyleBranch ReadStyleBranch(XmlElement owner, string key, string type, string path)
    {
        var branch = new StyleBranch { Key = key, Type = type, Path = path, Properties = ReadStyleProperties(owner) };
        Values[key] = new Dictionary<string, string>(branch.Properties);
        foreach (XmlElement child in owner.SelectNodes("Child"))
        {
            string childPath = child.GetAttribute("path");
            string childKey = child.GetAttribute("key");
            if (string.IsNullOrEmpty(childKey)) childKey = string.IsNullOrEmpty(childPath) ? key : key.Split('/')[0] + "/" + childPath;
            branch.Children.Add(ReadStyleBranch(child, childKey, child.GetAttribute("type"), childPath));
        }
        return branch;
    }

    internal static void Save()
    {
        CollectUnusedInstances();
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
        var settings = new XmlWriterSettings { Indent = true, Encoding = new System.Text.UTF8Encoding(false) };
        string temp = path + ".tmp";
        using (var writer = XmlWriter.Create(temp, settings))
        {
            writer.WriteStartElement("CommonStyles"); writer.WriteAttributeString("version", "2");
            foreach (var style in Values.OrderBy(x => x.Key))
            {
                if (IsCompositeChild(style.Key)) continue;
                writer.WriteStartElement("Style"); writer.WriteAttributeString("key", style.Key);
                if (IsInstanceStyle(style.Key)) writer.WriteAttributeString("instance", "1");
                string cloneBase;
                if (CloneBases.TryGetValue(style.Key, out cloneBase)) writer.WriteAttributeString("base", cloneBase);
                string displayName;
                if (DisplayNames.TryGetValue(style.Key, out displayName)) writer.WriteAttributeString("display", displayName);
                StyleBranch composite;
                if (Composites.TryGetValue(style.Key, out composite))
                {
                    writer.WriteAttributeString("composite", "1");
                    if (!string.IsNullOrEmpty(composite.Type)) writer.WriteAttributeString("type", composite.Type);
                    WriteStyleProperties(writer, composite.Properties.Count > 0 ? composite.Properties : style.Value);
                    WriteStyleChildren(writer, composite);
                }
                else
                    WriteStyleProperties(writer, style.Value);
                writer.WriteEndElement();
            }
            foreach (var layout in Layouts.OrderBy(x => x.Key))
            {
                writer.WriteStartElement("Layout"); writer.WriteAttributeString("key", layout.Key);
                WriteStyleProperties(writer, layout.Value);
                writer.WriteEndElement();
            }
            foreach (var binding in StyleBindings.OrderBy(x => x.Key))
            {
                if (string.IsNullOrEmpty(binding.Value) || HiddenStyles.Contains(binding.Value)) continue;
                writer.WriteStartElement("Binding");
                writer.WriteAttributeString("control", binding.Key);
                writer.WriteAttributeString("style", binding.Value);
                writer.WriteEndElement();
            }
            foreach (string hidden in HiddenStyles.OrderBy(x => x))
            {
                writer.WriteStartElement("Hidden"); writer.WriteAttributeString("key", hidden); writer.WriteEndElement();
            }
            foreach (var group in DisplayNames.Where(x => x.Key.StartsWith("#group:", StringComparison.Ordinal)).OrderBy(x => x.Key))
            {
                writer.WriteStartElement("Group"); writer.WriteAttributeString("key", group.Key);
                writer.WriteAttributeString("display", group.Value); writer.WriteEndElement();
            }
            writer.WriteEndElement();
        }
        if (File.Exists(path)) File.Replace(temp, path, path + ".bak"); else File.Move(temp, path);
    }

    private static void WriteStyleProperties(XmlWriter writer, Dictionary<string, string> properties)
    {
        if (properties == null) return;
        foreach (var prop in properties.OrderBy(x => x.Key))
        {
            writer.WriteStartElement("Property"); writer.WriteAttributeString("name", prop.Key);
            writer.WriteAttributeString("value", prop.Value); writer.WriteEndElement();
        }
    }

    private static void WriteStyleChildren(XmlWriter writer, StyleBranch branch)
    {
        if (branch == null) return;
        foreach (var child in branch.Children)
        {
            writer.WriteStartElement("Child");
            writer.WriteAttributeString("key", child.Key);
            if (!string.IsNullOrEmpty(child.Path)) writer.WriteAttributeString("path", child.Path);
            if (!string.IsNullOrEmpty(child.Type)) writer.WriteAttributeString("type", child.Type);
            WriteStyleProperties(writer, child.Properties);
            WriteStyleChildren(writer, child);
            writer.WriteEndElement();
        }
    }

    internal static IEnumerable<string> StyleTreeKeys(string key)
    {
        yield return key;
        StyleBranch branch;
        if (!Composites.TryGetValue(key, out branch))
        {
            foreach (var composite in Composites.Values)
            {
                var found = FindBranch(composite, key);
                if (found != null) { branch = found; break; }
            }
        }
        if (branch == null) yield break;
        foreach (string childKey in BranchKeys(branch))
            if (childKey != key) yield return childKey;
    }

    private static IEnumerable<string> BranchKeys(StyleBranch branch)
    {
        if (branch == null) yield break;
        yield return branch.Key;
        foreach (var child in branch.Children)
            foreach (string key in BranchKeys(child)) yield return key;
    }

    internal static StyleBranch FindBranch(StyleBranch branch, string key)
    {
        if (branch == null) return null;
        if (branch.Key == key) return branch;
        foreach (var child in branch.Children)
        {
            var found = FindBranch(child, key);
            if (found != null) return found;
        }
        return null;
    }

    internal static void RemoveStyleTree(string key)
    {
        foreach (string item in StyleTreeKeys(key).ToArray())
            RebindUsersToInstance(item);
        foreach (string item in StyleTreeKeys(key).ToArray())
        {
            Values.Remove(item);
            CloneBases.Remove(item);
            DisplayNames.Remove(item);
        }
        StyleBranch root;
        if (Composites.TryGetValue(key, out root)) Composites.Remove(key);
        else
        {
            foreach (var pair in Composites.ToArray())
            {
                if (RemoveChildBranch(pair.Value, key))
                {
                    Values.Remove(key);
                    break;
                }
            }
        }
        CollectUnusedInstances();
    }

    private static bool RemoveChildBranch(StyleBranch parent, string key)
    {
        if (parent == null) return false;
        for (int i = 0; i < parent.Children.Count; i++)
        {
            if (parent.Children[i].Key == key)
            {
                parent.Children.RemoveAt(i);
                return true;
            }
            if (RemoveChildBranch(parent.Children[i], key)) return true;
        }
        return false;
    }
}

internal sealed class RmtStyleEditor : Window
{
    private readonly Window source;
    private readonly TreeView catalog = new TreeView();
    private TreeView adjustCatalog;
    private readonly StackPanel fields = new StackPanel();
    private readonly StackPanel preview = new StackPanel();
    private readonly TextBlock status = new TextBlock { TextWrapping = TextWrapping.Wrap };
    private readonly TextBox search = new TextBox();
    private TextBox adjustSearch;
    private DockPanel editorHost;
    private Border adjustEditorSlot;
    private Border templateEditorSlot;
    private readonly Dictionary<string, TextBox> inputs = new Dictionary<string, TextBox>();
    private readonly Dictionary<string, ComboBox> colorInputs = new Dictionary<string, ComboBox>();
    private readonly Dictionary<string, ComboBox> optionInputs = new Dictionary<string, ComboBox>();
    private readonly Dictionary<string, Slider> sliderInputs = new Dictionary<string, Slider>();
    private readonly Dictionary<string, ComboBox> dimensionInputs = new Dictionary<string, ComboBox>();
    private readonly Dictionary<string, ComboBox> presetInputs = new Dictionary<string, ComboBox>();
    private readonly Dictionary<string, Dictionary<string, string>> drafts = new Dictionary<string, Dictionary<string, string>>();
    private readonly Dictionary<FrameworkElement, Dictionary<string, string>> instanceDrafts = new Dictionary<FrameworkElement, Dictionary<string, string>>();
    private bool inspectingSelection;
    private sealed class PositionOriginal { internal bool IsWindow, IsCanvas; internal double X, Y, Width, Height; internal Thickness Margin; }
    private readonly Dictionary<FrameworkElement, PositionOriginal> positionOriginals = new Dictionary<FrameworkElement, PositionOriginal>();
    private readonly Dictionary<string, CheckBox> chromeChecks = new Dictionary<string, CheckBox>();
    private TextBox previewContent;
    private TextBox previewOptions;
    private readonly HashSet<string> colorTouched = new HashSet<string>();
    private readonly HashSet<string> sliderTouched = new HashSet<string>();
    private readonly HashSet<string> dimensionTouched = new HashSet<string>();
    private readonly HashSet<string> presetTouched = new HashSet<string>();
    private readonly HashSet<string> optionTouched = new HashSet<string>();
    private Grid propertyRow;
    private int propertyPair;
    private Panel templateRows;
    private TreeViewItem catalogHighlight;
    private bool rendering, applying;
    private bool interactionReady;
    private int renderTicket;
    private readonly Dictionary<string, string> labels = new Dictionary<string, string> {
        {"样式/RmtItemEditBtn", "按钮 1 · 宏配置—操作按钮"}, {"样式/RmtItemPrimaryBtn", "按钮 2 · 宏配置—设置按钮"},
        {"Main.Config", "按钮 3 · 主界面—配置管理"}, {"Main.Save", "按钮 4 · 主界面—应用保存"},
        {"Theme.Confirm", "按钮 5 · 设置—主题选项确定"},
        {"Window.TriggerKey", "窗口 1 · 触发键编辑窗口"}, {"Window.Theme", "窗口 2 · 设置—主题"}
    };
    private static readonly Dictionary<string, string> notices = new Dictionary<string, string> {
        {"特殊说明/系统菜单与系统弹窗", "系统 Menu、MsgBox、InputBox 由 Windows 绘制，不属于 WPF 控件树。此项仅登记来源，不能通过通用 WPF 属性编辑。应用内使用 XAMLHost 的对话框仍自动接入。"},
        {"特殊说明/屏幕搜索范围标记", "Gui/SearchProGui.ahk：四个原生无标题置顶窗口用于描绘屏幕范围，带鼠标穿透。属于自绘标记，未接入通用控件尺寸与边距覆盖。"},
        {"特殊说明/旧输入按钮条", "Gui/InputBtnGui.ahk：旧原生透明按钮条，透明键色 EEAA99，字体 s11 w550，按钮宽 80。新版 Gui/InputBtnXamlGui.ahk 已经通过 XAMLHost 自动接入。"},
        {"特殊说明/运行浮层与轮盘业务颜色", "Main/Util/ThemeUtil.ahk 的 AppThemeUtil.ColorDefs 维护 Wheel_*、Panel_*、CMD_* 业务配色；在设置→主题选项中配置。它们属于独立业务绘制，不等同于通用窗口按钮颜色。"}
    };
    private static readonly Dictionary<string, string> propertyLabels = new Dictionary<string, string> {
        {"Background", "背景颜色"}, {"HoverBackground", "悬停背景"}, {"PressedBackground", "按住背景"}, {"Foreground", "文字颜色"}, {"BorderBrush", "边框颜色"}, {"BorderThickness", "边框宽度"}, {"CornerRadius", "圆角"},
        {"Margin", "外边距"}, {"Padding", "内边距"}, {"Width", "宽度"}, {"Height", "高度"}, {"MinWidth", "最小宽度"}, {"MinHeight", "最小高度"},
        {"MaxWidth", "最大宽度"}, {"MaxHeight", "最大高度"}, {"MaxDropDownHeight", "展开高度"}, {"RelativeFontSize", "相对字号"}, {"FontWeight", "字体粗细"},
        {"FontFamily", "字体"}, {"FontStyle", "字体样式"}, {"FontStretch", "字体伸缩"}, {"Opacity", "不透明度"},
        {"HorizontalAlignment", "控件水平对齐"}, {"VerticalAlignment", "控件垂直对齐"},
        {"HorizontalContentAlignment", "水平对齐"}, {"VerticalContentAlignment", "垂直对齐"},
        {"FlowDirection", "文字方向"}, {"Visibility", "可见性"}, {"IsEnabled", "是否启用"}, {"IsHitTestVisible", "鼠标命中"},
        {"Focusable", "允许聚焦"}, {"Cursor", "鼠标指针"}, {"UseLayoutRounding", "布局取整"}, {"SnapsToDevicePixels", "像素对齐"},
        {"TextAlignment", "文本对齐"}, {"TextWrapping", "文本换行"}, {"TextTrimming", "文本裁剪"},
        {"IsReadOnly", "只读"}, {"AcceptsReturn", "允许换行"}, {"AcceptsTab", "允许Tab"}, {"MaxLength", "最大长度"},
        {"IsEditable", "允许编辑"}, {"SelectedIndex", "选中序号"}, {"Orientation", "排列方向"}, {"ChildAlignment", "内容对齐"},
        {"Stretch", "拉伸方式"}, {"StretchDirection", "拉伸方向"},
        {"VerticalScrollBarVisibility", "纵向滚动条"}, {"HorizontalScrollBarVisibility", "横向滚动条"},
        {"Spacing", "子项间距"}, {"SizeMode", "宽高类型"}, {"Color", "颜色"},
        {"ShowMinimize", "最小化"}, {"ShowMaximize", "最大化"}, {"ShowPin", "置顶"}, {"ShowClose", "关闭"}
    };
    private string selected;
    private string reloadListKey;
    private FrameworkElement sample;
    private WeakReference inspectRef;
    private WeakReference inspectRootRef;
    private bool dirty;
    private Button cmdPin, cmdMin, cmdMax, cmdLocate;
    private TextBlock maxGlyph;
    private TabControl mainTabs;
    private TreeView hierarchyTree;
    private double previewHintWidth;
    private const double PropertyColumnGap = 44; // was 14; +30 between property columns
    private const double PickInnerBand = 0.80;
    private TextBox positionX, positionY;
    private bool positionUpdating;
    private bool positionEdited;
    private double chromeButtonWidth = 46, chromeButtonHeight = 30, chromeGlyphSize = 15;
    private FontWeight chromeGlyphWeight = FontWeights.Bold;
    private FrameworkElement highlightTarget;
    private FrameworkElement pickHover;
    private bool picking;
    private readonly List<Window> pickHooked = new List<Window>();
    private Dictionary<string, Dictionary<string, string>> snapshot;
    private Dictionary<string, Dictionary<string, string>> layoutSnapshot;
    private Dictionary<string, Dictionary<string, string>> instanceSnapshot;
    private Dictionary<string, string> bindingSnapshot;
    private Dictionary<string, RmtCommonStyles.StyleBranch> compositeSnapshot;
    private Dictionary<string, string> cloneSnapshot;
    private Dictionary<string, string> displaySnapshot;
    private HashSet<string> hiddenSnapshot;

    internal RmtStyleEditor(Window owner)
    {
        source = owner; Title = "GM-UI · 通用样式管理";
        Width = 1300; Height = 850; MinWidth = 1040; MinHeight = 640;
        FontFamily = owner.FontFamily; FontSize = owner.FontSize;
        snapshot = CopyValues();
        layoutSnapshot = CopyLayouts();
        instanceSnapshot = CopyInstances();
        bindingSnapshot = CopyBindings();
        compositeSnapshot = CopyComposites();
        cloneSnapshot = new Dictionary<string, string>(RmtCommonStyles.CloneBases);
        displaySnapshot = new Dictionary<string, string>(RmtCommonStyles.DisplayNames);
        hiddenSnapshot = new HashSet<string>(RmtCommonStyles.HiddenStyles);
        selected = "通用/Button";
        const string editorXaml = @"<Border xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' Margin='10' Background='{DynamicResource BgColor}' BorderBrush='{DynamicResource ControlBorder}' BorderThickness='1' CornerRadius='{DynamicResource WindowRadius}' TextElement.Foreground='{DynamicResource TextMain}'>
  <Border.Effect><DropShadowEffect BlurRadius='15' ShadowDepth='2' Opacity='.30'/></Border.Effect>
  <Grid><Grid.RowDefinitions><RowDefinition Height='30'/><RowDefinition Height='*'/></Grid.RowDefinitions>
    <Grid Background='{DynamicResource TitleBarColor}'>
      <Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='Auto'/></Grid.ColumnDefinitions>
      <Border x:Name='DragArea' Grid.Column='0' Background='{DynamicResource TitleBarColor}'>
        <TextBlock Text='GM-UI · 控件样式管理' Foreground='{DynamicResource TitleBarForeground}' FontWeight='Bold' FontSize='17' VerticalAlignment='Center' Margin='15,0,0,0'/>
      </Border>
      <StackPanel Grid.Column='1' Orientation='Horizontal' VerticalAlignment='Stretch'>
        <Button x:Name='BtnWinPin' Width='46' Height='30' MinWidth='46' MinHeight='30' Padding='0' Margin='0' VerticalAlignment='Stretch' Background='Transparent' Foreground='{DynamicResource TitleBarForeground}' BorderThickness='0' ToolTip='置顶'>
          <TextBlock x:Name='PinGlyph' Text='&#xE840;' FontFamily='Segoe Fluent Icons, Segoe MDL2 Assets' FontSize='15' VerticalAlignment='Center' HorizontalAlignment='Center' Margin='0' Foreground='{DynamicResource TitleBarForeground}'/>
        </Button>
        <Button x:Name='BtnWinMin' Width='46' Height='30' MinWidth='46' MinHeight='30' Padding='0' Margin='0' VerticalAlignment='Stretch' Background='Transparent' Foreground='{DynamicResource TitleBarForeground}' BorderThickness='0' ToolTip='最小化'>
          <TextBlock x:Name='MinGlyph' Text='&#xE921;' FontFamily='Segoe Fluent Icons, Segoe MDL2 Assets' FontSize='15' VerticalAlignment='Center' HorizontalAlignment='Center' Margin='0' Foreground='{DynamicResource TitleBarForeground}'/>
        </Button>
        <Button x:Name='BtnWinMax' Width='46' Height='30' MinWidth='46' MinHeight='30' Padding='0' Margin='0' VerticalAlignment='Stretch' Background='Transparent' Foreground='{DynamicResource TitleBarForeground}' BorderThickness='0' ToolTip='最大化'>
          <TextBlock x:Name='MaxGlyph' Text='&#xE922;' FontFamily='Segoe Fluent Icons, Segoe MDL2 Assets' FontSize='15' VerticalAlignment='Center' HorizontalAlignment='Center' Margin='0' Foreground='{DynamicResource TitleBarForeground}'/>
        </Button>
        <Button x:Name='BtnWinClose' Width='46' Height='30' MinWidth='46' MinHeight='30' Padding='0' Margin='0' VerticalAlignment='Stretch' Background='Transparent' Foreground='{DynamicResource TitleBarForeground}' BorderThickness='0'>
          <TextBlock x:Name='CloseGlyph' Text='&#xE8BB;' FontFamily='Segoe Fluent Icons, Segoe MDL2 Assets' FontSize='15' VerticalAlignment='Center' HorizontalAlignment='Center' Margin='0' Foreground='{DynamicResource TitleBarForeground}'/>
        </Button>
      </StackPanel>
    </Grid>
    <TabControl x:Name='MainTabs' Grid.Row='1' Margin='18,2,18,18' Background='Transparent' BorderThickness='0' Padding='0'>
      <TabItem x:Name='TabStyles' Header='控件调整' Tag='first'>
        <DockPanel x:Name='StylesContent' Margin='0,2,0,0'>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width='300'/><ColumnDefinition Width='16'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>
            <Border Grid.Column='0' BorderBrush='{DynamicResource Win_GroupStroke}' BorderThickness='1' CornerRadius='5' Padding='10'><DockPanel><TextBox x:Name='AdjustSearch' DockPanel.Dock='Top' MinHeight='30' Margin='0,0,0,8' ToolTip='搜索已定位控件'/><TreeView x:Name='AdjustCatalog'/></DockPanel></Border>
            <Border x:Name='AdjustEditorSlot' Grid.Column='2'>
              <DockPanel x:Name='EditorHost'>
                <Border x:Name='PreviewHost' DockPanel.Dock='Top' Height='200' MinHeight='200' MaxHeight='200' Margin='0,0,0,10' Padding='8' BorderBrush='{DynamicResource Win_GroupStroke}' BorderThickness='1.5' CornerRadius='5'><StackPanel x:Name='Preview'/></Border>
                <StackPanel DockPanel.Dock='Bottom' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,10,0,0'>
                  <Button x:Name='CmdLocateControl' Content='控件定位' Padding='10,5' Margin='0,0,8,0'/>
                  <Button x:Name='CmdItemReset' Content='重置' Padding='10,5' Margin='0,0,8,0'/>
                  <Button x:Name='CmdFindTemplate' Content='查找模版' Padding='10,5' Margin='0,0,8,0'/>
                  <Button x:Name='CmdAddTemplate' Content='新增模版' Padding='10,5'/>
                </StackPanel>
                <ScrollViewer VerticalScrollBarVisibility='Auto'><StackPanel x:Name='Fields'/></ScrollViewer>
              </DockPanel>
            </Border>
          </Grid>
        </DockPanel>
      </TabItem>
      <TabItem x:Name='TabTemplates' Header='模版列表'>
        <DockPanel x:Name='TemplatesContent' Margin='0,2,0,0'>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width='300'/><ColumnDefinition Width='16'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>
            <Border Grid.Column='0' BorderBrush='{DynamicResource Win_GroupStroke}' BorderThickness='1' CornerRadius='5' Padding='10'><DockPanel><TextBox x:Name='Search' DockPanel.Dock='Top' MinHeight='30' Margin='0,0,0,8' ToolTip='搜索按钮或窗口样式'/><TreeView x:Name='Catalog'/></DockPanel></Border>
            <Border x:Name='TemplateEditorSlot' Grid.Column='2'/>
          </Grid>
        </DockPanel>
      </TabItem>
      <TabItem x:Name='TabReflect' Header='窗口层级' Tag='last'>
        <DockPanel x:Name='ReflectContent' Margin='0,5,0,0'>
          <StackPanel DockPanel.Dock='Bottom' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,10,0,0'>
            <Button x:Name='CmdHierarchyRefresh' Content='刷新层级' Padding='10,5' Margin='0,0,8,0'/>
            <Button x:Name='CmdHierarchyLocate' Content='定位并调整' Padding='10,5'/>
          </StackPanel>
          <TreeView x:Name='HierarchyTree'/>
        </DockPanel>
      </TabItem>
    </TabControl>
  </Grid>
</Border>";
        var root = (Border)XamlReader.Parse(editorXaml); Content = root;
        // Do not set Owner: activating an owned window also brings the owner forward and can cover other dialogs.
        Owner = null;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent; ShowInTaskbar = false; WindowStartupLocation = WindowStartupLocation.Manual;
        var chrome = new System.Windows.Shell.WindowChrome { CaptionHeight = 30, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(0), CornerRadius = new CornerRadius(0) };
        System.Windows.Shell.WindowChrome.SetWindowChrome(this, chrome);
        CopyResourceSnapshot(Resources, source.Resources);
        Loaded += delegate
        {
            if (source == null || !source.IsLoaded) return;
            UpdateLayout();
            double width = ActualWidth > 0 ? ActualWidth : Width;
            double height = ActualHeight > 0 ? ActualHeight : Height;
            if (double.IsNaN(width) || width <= 0) width = 980;
            if (double.IsNaN(height) || height <= 0) height = 720;
            Left = source.Left + Math.Max(0, (source.ActualWidth - width) / 2);
            Top = source.Top + Math.Max(0, (source.ActualHeight - height) / 2);
        };
        search = (TextBox)root.FindName("Search");
        adjustSearch = (TextBox)root.FindName("AdjustSearch");
        catalog = (TreeView)root.FindName("Catalog");
        adjustCatalog = (TreeView)root.FindName("AdjustCatalog");
        editorHost = (DockPanel)root.FindName("EditorHost");
        adjustEditorSlot = (Border)root.FindName("AdjustEditorSlot");
        templateEditorSlot = (Border)root.FindName("TemplateEditorSlot");
        var catalogItemStyle = new Style(typeof(TreeViewItem));
        catalogItemStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0)));
        catalogItemStyle.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0)));
        catalogItemStyle.Setters.Add(new Setter(Control.BackgroundProperty, Brushes.Transparent));
        catalogItemStyle.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
        catalog.ItemContainerStyle = catalogItemStyle;
        if (adjustCatalog != null) adjustCatalog.ItemContainerStyle = catalogItemStyle;
        fields = (StackPanel)root.FindName("Fields");
        preview = (StackPanel)root.FindName("Preview");
        mainTabs = (TabControl)root.FindName("MainTabs");
        ApplyEditorTabStyles();
        hierarchyTree = (TreeView)root.FindName("HierarchyTree");
        hierarchyTree.FontSize = Math.Max(10, FontSize - 3);
        var drag = (Border)root.FindName("DragArea"); drag.MouseLeftButtonDown += delegate { try { DragMove(); } catch { } };
        var close = (Button)root.FindName("BtnWinClose");
        var sourceClose = source.FindName("BtnWinClose") as Button ?? source.FindName("BtnClosePanel") as Button ?? source.FindName("BtnClose") as Button;
        double chromeWidth = sourceClose != null && sourceClose.ActualWidth > 0 ? sourceClose.ActualWidth : 46;
        double chromeHeight = sourceClose != null && sourceClose.ActualHeight > 0 ? sourceClose.ActualHeight : 30;
        chromeWidth = Math.Max(46, chromeWidth);
        chromeHeight = Math.Max(30, chromeHeight);
        chromeButtonWidth = chromeWidth;
        chromeButtonHeight = chromeHeight;
        var editorGrid = root.Child as Grid;
        if (editorGrid != null && editorGrid.RowDefinitions.Count > 0) editorGrid.RowDefinitions[0].Height = new GridLength(chromeHeight);
        chrome.CaptionHeight = chromeHeight;
        close.Style = TryFindResource("TitleBarCloseButton") as Style ?? Application.Current.TryFindResource("TitleBarCloseButton") as Style;
        close.Width = chromeWidth; close.Height = chromeHeight; close.MinWidth = chromeWidth; close.MinHeight = chromeHeight;
        close.Padding = new Thickness(0); close.Margin = new Thickness(0);
        close.VerticalAlignment = VerticalAlignment.Stretch;
        close.Background = Brushes.Transparent; close.BorderThickness = new Thickness(0);
        var glyph = close.Content as TextBlock;
        if (glyph == null)
        {
            glyph = new TextBlock();
            close.Content = glyph;
        }
        glyph.Text = "\uE8BB";
        glyph.FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");
        var sourceCloseGlyph = sourceClose == null ? null : sourceClose.Content as TextBlock;
        glyph.FontSize = Math.Max(15, Math.Max(sourceCloseGlyph == null ? 0 : sourceCloseGlyph.FontSize, RmtCommonStyles.ThemeFontSize(source)));
        glyph.FontWeight = sourceCloseGlyph != null && sourceCloseGlyph.FontWeight != FontWeights.Normal ? sourceCloseGlyph.FontWeight : FontWeights.Bold;
        chromeGlyphSize = glyph.FontSize;
        chromeGlyphWeight = glyph.FontWeight;
        glyph.Margin = new Thickness(0);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        glyph.Foreground = close.Foreground;
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(close, true); close.Click += delegate { Close(); };
        cmdPin = (Button)root.FindName("BtnWinPin");
        cmdMin = (Button)root.FindName("BtnWinMin");
        cmdMax = (Button)root.FindName("BtnWinMax");
        Style chromeStyle = TryFindResource("TitleBarChromeButton") as Style ?? Application.Current.TryFindResource("TitleBarChromeButton") as Style;
        foreach (Button chromeBtn in new[] { cmdPin, cmdMin, cmdMax })
        {
            if (chromeBtn == null) continue;
            chromeBtn.Style = chromeStyle;
            chromeBtn.Width = chromeWidth; chromeBtn.Height = chromeHeight; chromeBtn.MinWidth = chromeWidth; chromeBtn.MinHeight = chromeHeight;
            chromeBtn.Padding = new Thickness(0); chromeBtn.Margin = new Thickness(0); chromeBtn.VerticalAlignment = VerticalAlignment.Stretch;
            var chromeGlyph = chromeBtn.Content as TextBlock;
            if (chromeGlyph != null) { chromeGlyph.FontSize = glyph.FontSize; chromeGlyph.FontWeight = glyph.FontWeight; }
            System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(chromeBtn, true);
        }
        maxGlyph = cmdMax == null ? null : cmdMax.Content as TextBlock;
        cmdPin.Click += delegate { Topmost = !Topmost; UpdatePinVisual(); };
        cmdMin.Click += delegate { WindowState = WindowState.Minimized; };
        cmdMax.Click += delegate { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };
        StateChanged += delegate { UpdateMaxVisual(); };
        UpdateMaxVisual();
        cmdLocate = (Button)root.FindName("CmdLocateControl");
        cmdLocate.Click += delegate { ToggleControlPick(); };
        ((Button)root.FindName("CmdItemReset")).Click += delegate { ResetCurrent(); };
        ((Button)root.FindName("CmdFindTemplate")).Click += delegate { FindTemplate(); };
        ((Button)root.FindName("CmdAddTemplate")).Click += delegate { AddToTemplate(); };
        ((Button)root.FindName("CmdHierarchyRefresh")).Click += delegate { RefreshHierarchyTree(); };
        ((Button)root.FindName("CmdHierarchyLocate")).Click += delegate { AcceptHierarchySelected(); };
        hierarchyTree.SelectedItemChanged += delegate { PreviewHierarchyTarget(HierarchySelectedElement()); };
        hierarchyTree.MouseDoubleClick += delegate(object sender, MouseButtonEventArgs args)
        {
            if (HierarchySelectedElement() != null) { AcceptHierarchySelected(); args.Handled = true; }
        };
        mainTabs.SelectionChanged += delegate(object sender, SelectionChangedEventArgs args)
        {
            if (!ReferenceEquals(args.Source, mainTabs)) return;
            if (mainTabs.SelectedIndex == 0)
            {
                MoveEditorTo(adjustEditorSlot);
                RestoreInspectedEditor();
            }
            else if (mainTabs.SelectedIndex == 1) MoveEditorTo(templateEditorSlot);
            // Keep expansion state across tab switches; only build the tree on first visit.
            if (mainTabs.SelectedIndex == 2 && hierarchyTree != null && hierarchyTree.Items.Count == 0)
                RefreshHierarchyTree();
        };
        catalog.PreviewMouseRightButtonDown += CatalogRightButtonDown;
        catalog.SelectedItemChanged += delegate { OnCatalogItemSelected(catalog.SelectedItem as TreeViewItem); };
        if (adjustCatalog != null)
        {
            adjustCatalog.PreviewMouseRightButtonDown += CatalogRightButtonDown;
            adjustCatalog.SelectedItemChanged += delegate { OnCatalogItemSelected(adjustCatalog.SelectedItem as TreeViewItem); };
        }
        search.TextChanged += delegate { Populate(); };
        if (adjustSearch != null) adjustSearch.TextChanged += delegate { Populate(); };
        PreviewKeyDown += EditorKeyDown;
        Closing += delegate(object sender, CancelEventArgs args) { CancelControlPick(); ClearHighlight(); if (dirty) Restore(); };
        Populate();
        SelectCatalog("通用/Button", true);
        status.Text = RmtCommonStyles.LoadError;
    }

    private void OnCatalogItemSelected(TreeViewItem item)
    {
        if (item == null || !(item.Tag is string)) return;
        string key = (string)item.Tag;
        if (key.StartsWith("#group:", StringComparison.Ordinal)) return;
        var weak = item.DataContext as WeakReference;
        var inspect = weak == null ? null : weak.Target as FrameworkElement;
        bool inspectMode = inspect != null;
        if (key == selected && inspectingSelection == inspectMode && ((inspect == null && Inspected() == null) || ReferenceEquals(inspect, Inspected())))
        {
            HighlightCatalogItem(item);
            return;
        }
        selected = key;
        inspectingSelection = inspectMode;
        positionEdited = false;
        if (inspect != null)
        {
            inspectRef = weak;
            // Sibling nodes selected after "显示父级" do not pass through
            // AcceptHierarchyTarget. Give them the same persistent identity.
            RmtCommonStyles.EnsureLayoutId(inspect);
            RmtCommonStyles.EnsureRegistered(inspect);
        }
        HighlightCatalogItem(item);
        Render();
    }

    private void RestoreInspectedEditor()
    {
        var item = adjustCatalog == null ? null : adjustCatalog.SelectedItem as TreeViewItem;
        if (item != null && item.Tag is string && !((string)item.Tag).StartsWith("#group:", StringComparison.Ordinal))
        {
            OnCatalogItemSelected(item);
            return;
        }
        var inspected = Inspected();
        if (inspected == null) return;
        inspectingSelection = true;
        selected = RmtCommonStyles.StyleKeyPublic(inspected);
        Render();
    }

    private void MoveEditorTo(Border slot)
    {
        if (editorHost == null || slot == null || ReferenceEquals(editorHost.Parent, slot)) return;
        var oldBorder = editorHost.Parent as Border;
        if (oldBorder != null) oldBorder.Child = null;
        else
        {
            var panel = editorHost.Parent as Panel;
            if (panel != null) panel.Children.Remove(editorHost);
        }
        slot.Child = editorHost;
    }

    internal static void CopyResourceSnapshot(ResourceDictionary destination, ResourceDictionary sourceDictionary)
    {
        if (destination == null || sourceDictionary == null) return;
        try
        {
            var detached = XamlReader.Parse(XamlWriter.Save(sourceDictionary)) as ResourceDictionary;
            if (detached != null)
            {
                destination.MergedDictionaries.Add(detached);
                return;
            }
        }
        catch { }
        // The fallback deliberately skips objects that cannot be cloned. Sharing a Style,
        // ControlTemplate or DataTemplate with the main window can change its resource owner.
        foreach (ResourceDictionary merged in sourceDictionary.MergedDictionaries)
            CopyResourceSnapshot(destination, merged);
        foreach (object key in sourceDictionary.Keys)
        {
            object value = sourceDictionary[key], detached = null;
            var freezable = value as Freezable;
            if (freezable != null) detached = freezable.CloneCurrentValue();
            else if (value == null || value is string || value.GetType().IsValueType) detached = value;
            else
            {
                try { detached = XamlReader.Parse(XamlWriter.Save(value)); }
                catch { continue; }
            }
            destination[key] = detached;
        }
    }

    private void UpdatePinVisual()
    {
        if (cmdPin == null) return;
        cmdPin.ToolTip = Topmost ? "取消置顶" : "置顶";
        if (Topmost)
            cmdPin.Background = TryFindResource("ActionHoverBg") as Brush
                ?? TryFindResource("ControlBorder") as Brush
                ?? Brushes.SlateGray;
        else
            cmdPin.ClearValue(Control.BackgroundProperty);
    }

    private void UpdateMaxVisual()
    {
        if (cmdMax == null) return;
        bool maximized = WindowState == WindowState.Maximized;
        cmdMax.ToolTip = maximized ? "还原" : "最大化";
        if (maxGlyph != null) maxGlyph.Text = maximized ? "\uE923" : "\uE922";
    }

    private void ApplyEditorTabStyles()
    {
        if (mainTabs == null) return;
        // Match MainWindowXaml RmtMainTabCtrl + TabItem chrome. Header font is theme size + 2
        // (main hardcodes 14 in the template, so TabControl.FontSize alone never reaches the header).
        double tabFont = Math.Max(12, RmtCommonStyles.ThemeFontSize(source) + 2);
        Style tabCtrl = source.TryFindResource("RmtMainTabCtrl") as Style
            ?? TryFindResource("RmtMainTabCtrl") as Style;
        if (tabCtrl == null)
        {
            tabCtrl = (Style)XamlReader.Parse(@"<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='TabControl'>
              <Setter Property='Background' Value='Transparent'/>
              <Setter Property='BorderThickness' Value='0'/>
              <Setter Property='Padding' Value='0'/>
              <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TabControl'><Grid>
                <Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='*'/></Grid.RowDefinitions>
                <Border Grid.Row='0' Margin='4,0,2,0' CornerRadius='4' BorderThickness='1.5' BorderBrush='{DynamicResource OutlineStroke}' Padding='0' SnapsToDevicePixels='True'><WrapPanel IsItemsHost='True'/></Border>
                <Border Grid.Row='1' Background='Transparent'><ContentPresenter ContentSource='SelectedContent'/></Border>
              </Grid></ControlTemplate></Setter.Value></Setter>
            </Style>");
        }
        mainTabs.Style = tabCtrl;
        string itemXaml = @"<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='TabItem'>
          <Setter Property='Width' Value='108'/>
          <Setter Property='Height' Value='28'/>
          <Setter Property='MinHeight' Value='28'/>
          <Setter Property='MaxHeight' Value='28'/>
          <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TabItem'>
            <Grid Height='28' ClipToBounds='True'>
              <Border x:Name='Bd' Background='Transparent' BorderThickness='0' BorderBrush='Transparent' Padding='5,4,5,4' Cursor='Hand' CornerRadius='0'>
                <Grid>
                  <ContentPresenter ContentSource='Header' TextElement.Foreground='{DynamicResource TextMain}' TextElement.FontSize='" + tabFont.ToString("0.##", CultureInfo.InvariantCulture) + @"' TextElement.FontWeight='SemiBold' HorizontalAlignment='Center' VerticalAlignment='Center'/>
                  <Ellipse x:Name='SelDot' Width='6' Height='6' Fill='{DynamicResource Accent}' HorizontalAlignment='Right' VerticalAlignment='Top' Margin='0,-3,-1,-3' Visibility='Collapsed' IsHitTestVisible='False'/>
                </Grid>
              </Border>
              <Rectangle x:Name='Divider' Width='2' Fill='{DynamicResource ControlBorder}' HorizontalAlignment='Right' VerticalAlignment='Stretch' Margin='0,3,0,3' IsHitTestVisible='False' SnapsToDevicePixels='True' RenderOptions.EdgeMode='Aliased'/>
            </Grid>
            <ControlTemplate.Triggers>
              <MultiTrigger><MultiTrigger.Conditions>
                <Condition Property='IsMouseOver' Value='True'/>
                <Condition Property='IsSelected' Value='False'/>
              </MultiTrigger.Conditions>
                <Setter TargetName='Bd' Property='Background' Value='{DynamicResource ControlBorder}'/>
                <Setter TargetName='Bd' Property='BorderBrush' Value='{DynamicResource Accent}'/>
              </MultiTrigger>
              <Trigger Property='IsSelected' Value='True'>
                <Setter TargetName='Bd' Property='Background' Value='{DynamicResource TabSelBg}'/>
                <Setter TargetName='SelDot' Property='Visibility' Value='Visible'/>
              </Trigger>
              <MultiTrigger><MultiTrigger.Conditions>
                <Condition Property='IsMouseOver' Value='True'/>
                <Condition Property='IsSelected' Value='True'/>
              </MultiTrigger.Conditions>
                <Setter TargetName='Bd' Property='Background' Value='{DynamicResource TabSelBg}'/>
                <Setter TargetName='Bd' Property='BorderBrush' Value='{DynamicResource Accent}'/>
              </MultiTrigger>
              <Trigger Property='Tag' Value='first'>
                <Setter TargetName='Bd' Property='CornerRadius' Value='4,0,0,4'/>
              </Trigger>
              <Trigger Property='Tag' Value='last'>
                <Setter TargetName='Bd' Property='CornerRadius' Value='0,4,4,0'/>
                <Setter TargetName='Divider' Property='Visibility' Value='Collapsed'/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Setter.Value></Setter>
        </Style>";
        Style tabItemStyle = (Style)XamlReader.Parse(itemXaml);
        foreach (TabItem item in mainTabs.Items)
            item.Style = tabItemStyle;
    }

    private static Dictionary<string, Dictionary<string, string>> CopyValues()
    {
        return RmtCommonStyles.Values.ToDictionary(x => x.Key, x => new Dictionary<string, string>(x.Value));
    }
    private static Dictionary<string, Dictionary<string, string>> CopyLayouts()
    {
        return RmtCommonStyles.Layouts.ToDictionary(x => x.Key, x => new Dictionary<string, string>(x.Value));
    }
    private static Dictionary<string, Dictionary<string, string>> CopyInstances()
    {
        return RmtCommonStyles.InstanceStyles.ToDictionary(x => x.Key, x => new Dictionary<string, string>(x.Value));
    }
    private static Dictionary<string, string> CopyBindings()
    {
        return new Dictionary<string, string>(RmtCommonStyles.StyleBindings);
    }
    private static Dictionary<string, RmtCommonStyles.StyleBranch> CopyComposites()
    {
        return RmtCommonStyles.Composites.ToDictionary(x => x.Key, x => RmtCommonStyles.CloneBranch(x.Value));
    }
    private void Restore()
    {
        drafts.Clear();
        instanceDrafts.Clear();
        RestoreAllPositions();
        RmtCommonStyles.Values.Clear(); foreach (var item in snapshot) RmtCommonStyles.Values[item.Key] = new Dictionary<string, string>(item.Value);
        RmtCommonStyles.Layouts.Clear(); foreach (var item in layoutSnapshot) RmtCommonStyles.Layouts[item.Key] = new Dictionary<string, string>(item.Value);
        RmtCommonStyles.InstanceStyles.Clear(); foreach (var item in instanceSnapshot) RmtCommonStyles.InstanceStyles[item.Key] = new Dictionary<string, string>(item.Value);
        RmtCommonStyles.StyleBindings.Clear(); foreach (var item in bindingSnapshot) RmtCommonStyles.StyleBindings[item.Key] = item.Value;
        RmtCommonStyles.Composites.Clear(); foreach (var item in compositeSnapshot) RmtCommonStyles.Composites[item.Key] = RmtCommonStyles.CloneBranch(item.Value);
        RmtCommonStyles.CloneBases.Clear(); foreach (var item in cloneSnapshot) RmtCommonStyles.CloneBases[item.Key] = item.Value;
        RmtCommonStyles.DisplayNames.Clear(); foreach (var item in displaySnapshot) RmtCommonStyles.DisplayNames[item.Key] = item.Value;
        RmtCommonStyles.HiddenStyles.Clear(); foreach (string item in hiddenSnapshot) RmtCommonStyles.HiddenStyles.Add(item);
        RmtCommonStyles.Refresh(); dirty = false; status.Text = "已撤销未保存预览。";
    }

    private void ResetCurrent()
    {
        if (string.IsNullOrEmpty(selected)) return;
        var target = LiveInspecting() ? Inspected() : null;
        if (target != null) instanceDrafts.Remove(target);
        else
        {
            drafts.Remove(selected);
            Dictionary<string, string> original;
            if (snapshot.TryGetValue(selected, out original)) RmtCommonStyles.Values[selected] = new Dictionary<string, string>(original);
            else RmtCommonStyles.Values.Remove(selected);
            string clone;
            if (cloneSnapshot.TryGetValue(selected, out clone)) RmtCommonStyles.CloneBases[selected] = clone;
            else RmtCommonStyles.CloneBases.Remove(selected);
            string display;
            if (displaySnapshot.TryGetValue(selected, out display)) RmtCommonStyles.DisplayNames[selected] = display;
            else RmtCommonStyles.DisplayNames.Remove(selected);
        }
        if (target != null)
        {
            string id = RmtCommonStyles.LayoutId(target);
            Dictionary<string, string> layout;
            if (layoutSnapshot.TryGetValue(id, out layout)) RmtCommonStyles.Layouts[id] = new Dictionary<string, string>(layout);
            else RmtCommonStyles.Layouts.Remove(id);
            Dictionary<string, string> instance;
            if (instanceSnapshot.TryGetValue(id, out instance)) RmtCommonStyles.InstanceStyles[id] = new Dictionary<string, string>(instance);
            else RmtCommonStyles.InstanceStyles.Remove(id);
            string bound;
            if (bindingSnapshot.TryGetValue(id, out bound)) RmtCommonStyles.StyleBindings[id] = bound;
            else RmtCommonStyles.StyleBindings.Remove(id);
            RmtCommonStyles.CollectUnusedInstances();
        }
        RmtCommonStyles.Refresh();
        // Restore the preview position after style/layout refresh so one click cannot be
        // overwritten by a pending layout pass from the old preview value.
        if (target != null)
        {
            RestorePosition(target);
            string id = RmtCommonStyles.LayoutId(target);
            Dictionary<string, string> layout;
            if (layoutSnapshot.TryGetValue(id, out layout)) RmtCommonStyles.ApplyAnchorLayout(target, layout);
            target.UpdateLayout();
            try { RmtCommonStyles.Save(); }
            catch (Exception ex) { status.Text = ex.Message; return; }
        }
        positionEdited = false;
        Render();
        dirty = drafts.Count > 0 || instanceDrafts.Count > 0;
        status.Text = "当前控件的重载属性已恢复到调整前。";
    }

    private void ApplyCurrent()
    {
        if (!Commit(true)) return;
        try
        {
            RmtCommonStyles.Save();
            snapshot = CopyValues();
            layoutSnapshot = CopyLayouts();
            instanceSnapshot = CopyInstances();
            bindingSnapshot = CopyBindings();
            compositeSnapshot = CopyComposites();
            cloneSnapshot = new Dictionary<string, string>(RmtCommonStyles.CloneBases);
            displaySnapshot = new Dictionary<string, string>(RmtCommonStyles.DisplayNames);
            hiddenSnapshot = new HashSet<string>(RmtCommonStyles.HiddenStyles);
            var target = Inspected();
            if (target != null) positionOriginals.Remove(target);
            dirty = drafts.Count > 0 || instanceDrafts.Count > 0;
            status.Text = "当前样式已永久应用。";
        }
        catch (Exception ex) { status.Text = ex.Message; }
    }

    private string TemplateKey()
    {
        if (string.IsNullOrEmpty(selected)) return "";
        string template;
        if (RmtCommonStyles.CloneBases.TryGetValue(selected, out template)) return template;
        if (selected.StartsWith("通用/")) return selected;
        var target = Inspected() ?? sample;
        return target == null ? "" : "通用/" + target.GetType().Name;
    }

    private bool TryConfiguredValues(string key, out Dictionary<string, string> values)
    {
        if (drafts.TryGetValue(key, out values)) return true;
        return RmtCommonStyles.Values.TryGetValue(key, out values);
    }

    private bool TryEditingValues(out Dictionary<string, string> values)
    {
        if (!LiveInspecting()) return TryConfiguredValues(selected, out values);
        var target = Inspected();
        if (instanceDrafts.TryGetValue(target, out values)) return true;
        string layoutId = RmtCommonStyles.LayoutId(target);
        if (RmtCommonStyles.TryBoundProperties(layoutId, out values)) return true;
        return RmtCommonStyles.InstanceStyles.TryGetValue(layoutId, out values);
    }

    private bool StoreEdits(Dictionary<string, string> next, bool persist)
    {
        if (LiveInspecting())
        {
            var target = Inspected();
            // Located controls apply every valid change immediately. Keep the opening
            // snapshot intact so ResetCurrent can restore the pre-edit values.
            if ((positionEdited || target is Window) && !ApplyInspectedPosition(true)) return false;
            // Older edits saved an anchor even when only a style field changed. Such an
            // anchor pins a horizontal StackPanel at its old X and defeats alignment.
            if (!positionEdited && target is StackPanel && next.ContainsKey("ChildAlignment"))
            {
                string id = RmtCommonStyles.LayoutId(target);
                PositionOriginal original;
                if (positionOriginals.TryGetValue(target, out original)) target.Margin = original.Margin;
                RmtCommonStyles.Layouts.Remove(id);
            }
            RmtCommonStyles.AssignControlStyle(target, next);
            instanceDrafts.Remove(target);
            RmtCommonStyles.Refresh();
            RmtCommonStyles.Save();
            dirty = drafts.Count > 0 || instanceDrafts.Count > 0;
        }
        else
        {
            if (persist)
            {
                RmtCommonStyles.Values[selected] = RmtCommonStyles.SanitizeStyle(next);
                drafts.Remove(selected);
                RmtCommonStyles.Refresh();
            }
            else drafts[selected] = next;
            SyncBranchProperties(selected, next);
        }
        if (!LiveInspecting()) dirty = true;
        return true;
    }

    private void FindTemplate()
    {
        string template = TemplateKey();
        if (string.IsNullOrEmpty(template))
        {
            MessageBox.Show(this, "当前控件还没有模版收纳。", "GM-UI", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        selected = template;
        Populate();
        if (!SelectCatalog(template, true, true))
        {
            MessageBox.Show(this, "当前控件还没有模版收纳。", "GM-UI", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (mainTabs != null) mainTabs.SelectedIndex = 1;
        Render();
        status.Text = "已跳转到对应模版。";
    }

    private void ApplyReloadToTemplate()
    {
        if (string.IsNullOrEmpty(selected) || sample == null) return;
        if (!Commit(false)) return;
        string template = TemplateKey();
        if (string.IsNullOrEmpty(template))
        {
            MessageBox.Show(this, "当前控件还没有可应用的模版。", "GM-UI", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        // Implicit 通用/{Type} keys other than Button/Window are not catalog templates.
        // Writing them would repaint every live control of that type (e.g. main-window fold fields).
        if (LiveInspecting() && IsImplicitSharedTypeTemplate(template) && template != "通用/Button" && template != "通用/Window")
        {
            status.Text = "当前反射控件没有独立模版。请点「应用」只保存到该控件，或先「添加新模版」再应用到模版。";
            return;
        }
        Dictionary<string, string> current;
        TryEditingValues(out current);
        RmtCommonStyles.Values[template] = current == null ? new Dictionary<string, string>() : new Dictionary<string, string>(current);
        SyncBranchProperties(template, RmtCommonStyles.Values[template]);
        drafts.Remove(template);
        dirty = true;
        status.Text = "已将重载属性应用到模版：" + DisplayName(template) + "。";
    }

    private static bool IsImplicitSharedTypeTemplate(string key)
    {
        return !string.IsNullOrEmpty(key) && key.StartsWith("通用/", StringComparison.Ordinal)
            && !RmtCommonStyles.CloneBases.ContainsKey(key);
    }

    private void AddToTemplate()
    {
        AddTemplateFromCurrent(PromptCategory());
    }

    internal void AddTemplateFromCurrent(string category)
    {
        if (string.IsNullOrEmpty(selected) || sample == null) return;
        if (string.IsNullOrWhiteSpace(category)) return;
        if (!Commit(false)) return;
        category = category.Trim();
        string baseKey = TemplateKey();
        if (string.IsNullOrEmpty(baseKey)) baseKey = sample is Window ? "通用/Window" : "通用/" + sample.GetType().Name;
        string title = category + "模版";
        int number = 1;
        var names = new HashSet<string>(RmtCommonStyles.DisplayNames.Values);
        names.Add("按钮模版");
        names.Add("窗口模版");
        foreach (string catalogKey in labels.Keys) names.Add(ButtonTitle(catalogKey));
        if (names.Contains(title))
        {
            do { title = category + number++; } while (names.Contains(title));
        }
        var root = Inspected() ?? sample;
        string prefix = root is Window ? "WindowTemplate" : root.GetType().Name + "Template";
        int keyNo = 1;
        string key;
        do { key = prefix + keyNo++; } while (RmtCommonStyles.Values.ContainsKey(key) || RmtCommonStyles.CloneBases.ContainsKey(key) || RmtCommonStyles.Composites.ContainsKey(key));
        var children = root == null ? new List<FrameworkElement>() : RmtCommonStyles.StyleChildren(root);
        if (root != null && children.Count > 0)
        {
            var branch = CaptureBranch(root, "", key);
            branch.Properties = CurrentValues();
            RmtCommonStyles.Values[key] = new Dictionary<string, string>(branch.Properties);
            RmtCommonStyles.Composites[key] = branch;
        }
        else
            RmtCommonStyles.Values[key] = CurrentValues();
        RmtCommonStyles.CloneBases[key] = baseKey;
        RmtCommonStyles.DisplayNames[key] = title;
        selected = key;
        dirty = true;
        Populate();
        SelectCatalog(key, true);
        Render();
        status.Text = children.Count > 0 ? "已添加层级组合模版：" + title + "。" : "已添加新模版：" + title + "。";
    }

    private Dictionary<string, string> CurrentValues()
    {
        Dictionary<string, string> current;
        TryConfiguredValues(selected, out current);
        return current == null ? new Dictionary<string, string>() : new Dictionary<string, string>(current);
    }

    private RmtCommonStyles.StyleBranch CaptureBranch(FrameworkElement element, string path, string rootKey)
    {
        string key = path == "" ? rootKey : rootKey + "/" + path;
        Dictionary<string, string> configured;
        TryConfiguredValues(RmtCommonStyles.StyleKeyPublic(element), out configured);
        var branch = new RmtCommonStyles.StyleBranch
        {
            Key = key,
            Type = element.GetType().Name,
            Path = path,
            Properties = configured == null ? new Dictionary<string, string>() : new Dictionary<string, string>(configured)
        };
        if (path != "") RmtCommonStyles.Values[key] = new Dictionary<string, string>(branch.Properties);
        var children = RmtCommonStyles.StyleChildren(element);
        if (element is ComboBox || element is ListBox) children = new List<FrameworkElement>();
        for (int i = 0; i < children.Count; i++)
        {
            string childPath = path == "" ? i.ToString(CultureInfo.InvariantCulture) : path + "/" + i.ToString(CultureInfo.InvariantCulture);
            branch.Children.Add(CaptureBranch(children[i], childPath, rootKey));
        }
        return branch;
    }

    internal static bool CanDeleteStyle(string key)
    {
        if (string.IsNullOrEmpty(key) || key.StartsWith("特殊/", StringComparison.Ordinal)) return false;
        return true;
    }

    internal void DeleteCatalogStyle(string key)
    {
        if (!CanDeleteStyle(key))
        {
            status.Text = "内置模版不能删除。";
            return;
        }
        foreach (string item in RmtCommonStyles.StyleTreeKeys(key).ToArray()) drafts.Remove(item);
        string neighbor = NeighborCatalogKey(key);
        RmtCommonStyles.RemoveStyleTree(key);
        RmtCommonStyles.HiddenStyles.Add(key);
        if (selected == key || selected != null && selected.StartsWith(key + "/", StringComparison.Ordinal))
            selected = neighbor;
        dirty = true;
        Populate();
        if (!SelectCatalog(selected, true, true))
        {
            if (LiveInspecting()) SelectCatalog(selected, false, false, true);
            else SelectCatalog(selected, true);
        }
        if (catalog.SelectedItem == null) SelectCatalog("通用/Button", true, true);
        Render();
        status.Text = "已删除模版；已单独应用到控件的实例样式不受影响。";
    }

    private RmtCommonStyles.StyleBranch FindSelectedBranch()
    {
        if (string.IsNullOrEmpty(selected)) return null;
        foreach (var composite in RmtCommonStyles.Composites.Values)
        {
            var found = RmtCommonStyles.FindBranch(composite, selected);
            if (found != null) return found;
        }
        return null;
    }

    private static void SyncBranchProperties(string key, Dictionary<string, string> values)
    {
        if (string.IsNullOrEmpty(key) || values == null) return;
        foreach (var composite in RmtCommonStyles.Composites.Values)
        {
            var found = RmtCommonStyles.FindBranch(composite, key);
            if (found != null)
            {
                found.Properties = new Dictionary<string, string>(values);
                return;
            }
        }
    }

    private string PromptCategory()
    {
        var dialog = new Window { Title = "添加新模版", Width = 380, Height = 155, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, FontFamily = FontFamily, FontSize = FontSize };
        CopyResourceSnapshot(dialog.Resources, Resources);
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = "类别", Margin = new Thickness(0, 0, 0, 6) });
        var input = new TextBox { MinHeight = 30, Padding = new Thickness(5) };
        panel.Children.Add(input);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var cancel = new Button { Content = "取消", MinWidth = 70, Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(0, 0, 8, 0) };
        var ok = new Button { Content = "确定", MinWidth = 70, Padding = new Thickness(10, 5, 10, 5), IsDefault = true };
        cancel.Click += delegate { dialog.DialogResult = false; };
        ok.Click += delegate { dialog.DialogResult = true; };
        buttons.Children.Add(cancel); buttons.Children.Add(ok); panel.Children.Add(buttons); dialog.Content = panel;
        dialog.Loaded += delegate { input.Focus(); };
        return dialog.ShowDialog() == true ? input.Text : "";
    }

    private FrameworkElement Inspected()
    {
        return inspectRef == null ? null : inspectRef.Target as FrameworkElement;
    }

    private FrameworkElement InspectedRoot()
    {
        return inspectRootRef == null ? null : inspectRootRef.Target as FrameworkElement;
    }

    private bool LiveInspecting()
    {
        var target = Inspected();
        return inspectingSelection && target != null && selected == RmtCommonStyles.StyleKeyPublic(target);
    }

    private bool LocatingSelectedWindow()
    {
        return Inspected() is Window && LiveInspecting();
    }

    internal void PreviewHierarchyTarget(FrameworkElement target)
    {
        ShowHighlight(target);
    }

    internal void AcceptHierarchyTarget(FrameworkElement target)
    {
        if (target == null) return;
        positionEdited = false;
        inspectRootRef = new WeakReference(target);
        inspectRef = new WeakReference(target);
        inspectingSelection = true;
        selected = RmtCommonStyles.StyleKeyPublic(target);
        RmtCommonStyles.EnsureLayoutId(target);
        RmtCommonStyles.EnsureRegistered(target);
        foreach (var child in CollectDescendants(target))
            RmtCommonStyles.EnsureRegistered(child);
        ClearHighlight();
        if (mainTabs != null) mainTabs.SelectedIndex = 0;
        Populate();
        SelectCatalog(selected, false, false, true);
        ShowPickedHierarchy(target);
        Render();
        status.Text = "已定位 " + target.GetType().Name + (string.IsNullOrEmpty(target.Name) ? "" : " / " + target.Name) + "。";
        Activate();
    }

    internal void AcceptPickedControl(FrameworkElement target)
    {
        AcceptHierarchyTarget(ResolvePickedControl(target) ?? target);
    }

    private static FrameworkElement ResolvePickedControl(FrameworkElement hit)
    {
        if (hit == null) return null;
        if (hit is Window) return hit;
        if (IsWindowChromeElement(hit))
        {
            var window = Window.GetWindow(hit);
            return window != null && !RmtCommonStyles.IsEditorWindow(window) ? window : hit;
        }
        FrameworkElement current = hit;
        while (current != null && !(current is Window))
        {
            if (IsConcretePick(current)) return current;
            current = (LogicalTreeHelper.GetParent(current) ?? VisualTreeHelper.GetParent(current)) as FrameworkElement;
        }
        return hit;
    }

    private static bool IsConcretePick(FrameworkElement element)
    {
        if (element == null || element is Window || element is Panel || element is Viewbox) return false;
        if (element.TemplatedParent != null) return false;
        return element is Control || element is TextBlock || element is Image;
    }

    private void ToggleControlPick()
    {
        if (picking) CancelControlPick();
        else StartControlPick();
    }

    private void StartControlPick()
    {
        picking = true;
        pickHover = null;
        Mouse.OverrideCursor = Cursors.Cross;
        if (cmdLocate != null) cmdLocate.Content = "取消定位";
        status.Text = "悬停定位：控件中心 80% 选中自身，边缘选中父级。按 Esc 或左键确认，点「取消定位」放弃。";
        HookPickWindows();
    }

    private void CancelControlPick()
    {
        StopControlPick();
        status.Text = "已取消控件定位。";
    }

    internal void FinishControlPick()
    {
        var target = pickHover;
        StopControlPick();
        if (target != null) AcceptPickedControl(target);
        else status.Text = "已退出控件定位。";
    }

    private void StopControlPick()
    {
        picking = false;
        pickHover = null;
        Mouse.OverrideCursor = null;
        if (cmdLocate != null) cmdLocate.Content = "控件定位";
        UnhookPickWindows();
        ClearHighlight();
    }

    private void HookPickWindows()
    {
        UnhookPickWindows();
        var windows = new List<Window>();
        if (Application.Current != null)
            foreach (Window window in Application.Current.Windows) windows.Add(window);
        if (source != null && !windows.Contains(source)) windows.Add(source);
        foreach (Window window in windows)
        {
            if (window == null || window == this || window is RmtControlTreeWindow) continue;
            window.PreviewMouseMove += PickMouseMove;
            window.PreviewMouseLeftButtonDown += PickMouseDown;
            window.PreviewKeyDown += PickKeyDown;
            pickHooked.Add(window);
        }
    }

    private void UnhookPickWindows()
    {
        foreach (Window window in pickHooked)
        {
            if (window == null) continue;
            window.PreviewMouseMove -= PickMouseMove;
            window.PreviewMouseLeftButtonDown -= PickMouseDown;
            window.PreviewKeyDown -= PickKeyDown;
        }
        pickHooked.Clear();
    }

    private void PickMouseMove(object sender, MouseEventArgs args)
    {
        if (!picking) return;
        var hit = HitPickable(sender as Window, args);
        if (hit == null) return;
        pickHover = hit;
        ShowHighlight(hit);
    }

    private void PickMouseDown(object sender, MouseButtonEventArgs args)
    {
        if (!picking) return;
        args.Handled = true;
        var host = sender as Window;
        var hit = HitPickable(host, args);
        if (hit != null) pickHover = hit;
        if (host != null) host.PreviewMouseLeftButtonUp += SwallowPickClick;
        FinishControlPick();
    }

    private void SwallowPickClick(object sender, MouseButtonEventArgs args)
    {
        args.Handled = true;
        var host = sender as Window;
        if (host != null) host.PreviewMouseLeftButtonUp -= SwallowPickClick;
    }

    private void PickKeyDown(object sender, KeyEventArgs args)
    {
        if (!picking || args.Key != Key.Escape) return;
        args.Handled = true;
        FinishControlPick();
    }

    private FrameworkElement HitPickable(Window window, MouseEventArgs args)
    {
        if (window == null || args == null) return null;
        return HitPickableAt(window, args.GetPosition(window));
    }

    internal FrameworkElement HitPickableAt(Window window, Point windowPoint)
    {
        if (window == null || window == this || RmtCommonStyles.IsEditorWindow(window)) return null;
        DependencyObject current = HitVisibleVisual(window, windowPoint);
        if (current == null) return null;
        FrameworkElement innermost = null;
        while (current != null)
        {
            var element = current as FrameworkElement;
            if (element != null && RmtCommonStyles.IsPickable(element))
            {
                if (innermost == null) innermost = element;
                if (IsWindowChromeElement(element))
                    return ResolvePickedControl(element);
            }
            current = NextHitParent(current);
        }
        if (innermost == null) return null;
        var leaf = ResolvePickedControl(innermost) ?? innermost;
        Point local;
        try { local = window.TranslatePoint(windowPoint, leaf); }
        catch { local = new Point(leaf.ActualWidth / 2, leaf.ActualHeight / 2); }
        return ResolveEdgeAwarePick(leaf, local);
    }

    private static DependencyObject HitVisibleVisual(Visual reference, Point point)
    {
        DependencyObject found = null;
        VisualTreeHelper.HitTest(reference,
            delegate(DependencyObject potential)
            {
                if (potential is Adorner || potential is AdornerLayer)
                    return HitTestFilterBehavior.ContinueSkipSelfAndChildren;
                var ui = potential as UIElement;
                if (ui != null && !ui.IsHitTestVisible)
                    return HitTestFilterBehavior.ContinueSkipSelfAndChildren;
                return HitTestFilterBehavior.Continue;
            },
            delegate(HitTestResult result)
            {
                found = result.VisualHit;
                return HitTestResultBehavior.Stop;
            },
            new PointHitTestParameters(point));
        return found;
    }

    private static DependencyObject NextHitParent(DependencyObject current)
    {
        var adorner = current as Adorner;
        if (adorner != null && adorner.AdornedElement != null) return adorner.AdornedElement;
        return VisualTreeHelper.GetParent(current);
    }

    internal static FrameworkElement ResolveEdgeAwarePick(FrameworkElement leaf, Point local)
    {
        if (leaf == null) return null;
        if (leaf is Window || IsWindowChromeElement(leaf)) return leaf;
        if (IsInnerPickBand(leaf, local)) return leaf;
        return PickableAncestor(leaf) ?? leaf;
    }

    internal static bool IsInnerPickBand(FrameworkElement element, Point local)
    {
        if (element == null) return false;
        double width = element.ActualWidth;
        double height = element.ActualHeight;
        if (width <= 0 || height <= 0) return true;
        double marginX = width * (1 - PickInnerBand) / 2;
        double marginY = height * (1 - PickInnerBand) / 2;
        return local.X >= marginX && local.X <= width - marginX
            && local.Y >= marginY && local.Y <= height - marginY;
    }

    private static FrameworkElement PickableAncestor(FrameworkElement element)
    {
        if (element == null) return null;
        DependencyObject current = LogicalTreeHelper.GetParent(element) ?? VisualTreeHelper.GetParent(element);
        while (current != null)
        {
            var parent = current as FrameworkElement;
            if (parent is Window) return null;
            if (parent != null && RmtCommonStyles.IsPickable(parent)) return parent;
            current = LogicalTreeHelper.GetParent(current) ?? VisualTreeHelper.GetParent(current);
        }
        return null;
    }

    private FrameworkElement HierarchySelectedElement()
    {
        var item = hierarchyTree == null ? null : hierarchyTree.SelectedItem as TreeViewItem;
        var weak = item == null ? null : item.Tag as WeakReference;
        return weak == null ? null : weak.Target as FrameworkElement;
    }

    private void AcceptHierarchySelected()
    {
        var element = HierarchySelectedElement();
        if (element != null) AcceptHierarchyTarget(element);
    }

    private void RefreshHierarchyTree()
    {
        if (hierarchyTree == null) return;
        hierarchyTree.Items.Clear();
        if (Application.Current == null) return;
        foreach (Window window in Application.Current.Windows.Cast<Window>().ToArray())
        {
            if (window == null || window is RmtStyleEditor || window is RmtControlTreeWindow) continue;
            var root = MakeHierarchyNode(window);
            root.IsExpanded = true;
            AddHierarchyChildren(root, window, new HashSet<DependencyObject>());
            hierarchyTree.Items.Add(root);
        }
    }

    private void ShowPickedHierarchy(FrameworkElement root)
    {
        if (hierarchyTree == null || root == null) return;
        hierarchyTree.Items.Clear();
        var node = MakeHierarchyNode(root);
        node.IsExpanded = true;
        AttachShowParentMenu(node);
        AddHierarchyChildren(node, root, new HashSet<DependencyObject>());
        hierarchyTree.Items.Add(node);
    }

    private static List<FrameworkElement> CollectDescendants(FrameworkElement root)
    {
        var result = new List<FrameworkElement>();
        if (root == null) return result;
        var queue = new Queue<FrameworkElement>();
        queue.Enqueue(root);
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (current is ComboBox || current is ListBox) continue;
            foreach (var child in RmtCommonStyles.StyleChildren(current))
            {
                result.Add(child);
                queue.Enqueue(child);
            }
        }
        return result;
    }

    private static void AddHierarchyChildren(TreeViewItem parentItem, DependencyObject parent, HashSet<DependencyObject> visited)
    {
        if (parent == null || !visited.Add(parent)) return;
        foreach (var element in RmtCommonStyles.StyleChildren(parent))
        {
            var item = MakeHierarchyNode(element);
            parentItem.Items.Add(item);
            if (element is ComboBox || element is ListBox) continue;
            AddHierarchyChildren(item, element, visited);
        }
    }

    private static TreeViewItem MakeHierarchyNode(FrameworkElement element)
    {
        var item = new TreeViewItem { Header = HierarchyElementLabel(element), Tag = new WeakReference(element) };
        var menu = new ContextMenu();
        var expand = new MenuItem { Header = "展开全部" };
        var collapse = new MenuItem { Header = "收缩全部" };
        expand.Click += delegate { SetHierarchyExpanded(item, true); };
        collapse.Click += delegate { SetHierarchyExpanded(item, false); };
        menu.Items.Add(expand);
        menu.Items.Add(collapse);
        item.ContextMenu = menu;
        return item;
    }

    private static void SetHierarchyExpanded(TreeViewItem item, bool expanded)
    {
        if (item == null) return;
        item.IsExpanded = expanded;
        foreach (TreeViewItem child in item.Items.OfType<TreeViewItem>()) SetHierarchyExpanded(child, expanded);
    }

    private static string HierarchyElementLabel(FrameworkElement element)
    {
        string label = element.GetType().Name;
        var window = element as Window;
        if (window != null && !string.IsNullOrEmpty(window.Title))
            label += "（" + window.Title + "）";
        if (!string.IsNullOrEmpty(element.Name)) label += " / " + element.Name;
        var content = element as ContentControl;
        var text = content == null || window != null ? null : content.Content as string;
        if (!string.IsNullOrEmpty(text)) label += " · " + text;
        return label;
    }

    private void EditorKeyDown(object sender, KeyEventArgs args)
    {
        if (args.Key == Key.Escape)
        {
            if (picking) FinishControlPick();
            else ClearHighlight();
            args.Handled = true;
        }
    }

    private RmtHighlightAdorner highlightAdorner;

    private void ShowHighlight(FrameworkElement element)
    {
        if (highlightTarget == element) return;
        ClearHighlight();
        if (element == null) return;
        var layer = AdornerLayer.GetAdornerLayer(element);
        if (layer == null) return;
        highlightAdorner = new RmtHighlightAdorner(element, ContrastHighlightColor(element));
        layer.Add(highlightAdorner);
        highlightTarget = element;
    }

    private static Color ContrastHighlightColor(FrameworkElement element)
    {
        Color background = SampleElementBackground(element);
        // Prefer colors that stay visible against ActionBg orange and common dark/light panels.
        Color[] candidates = {
            Color.FromRgb(0, 190, 255),
            Color.FromRgb(40, 220, 120),
            Color.FromRgb(200, 60, 255),
            Color.FromRgb(255, 50, 140),
            Color.FromRgb(255, 230, 0),
            Color.FromRgb(30, 90, 255),
            Color.FromRgb(255, 140, 0)
        };
        Color best = candidates[0];
        double bestScore = -1;
        foreach (Color candidate in candidates)
        {
            double score = ColorDistance(candidate, background);
            if (score > bestScore) { bestScore = score; best = candidate; }
        }
        return best;
    }

    private static Color SampleElementBackground(FrameworkElement element)
    {
        Brush brush = null;
        var control = element as Control;
        if (control != null) brush = control.Background;
        if (brush == null)
        {
            var border = element as Border;
            if (border != null) brush = border.Background;
        }
        if (brush == null)
        {
            var panel = element as Panel;
            if (panel != null) brush = panel.Background;
        }
        if ((brush == null || brush == Brushes.Transparent) && control != null)
        {
            control.ApplyTemplate();
            var templateBorder = RmtCommonStyles.FindControlBorder(control);
            if (templateBorder != null) brush = templateBorder.Background;
        }
        var solid = brush as SolidColorBrush;
        if (solid != null) return solid.Color;
        return Color.FromRgb(128, 128, 128);
    }

    private static double ColorDistance(Color a, Color b)
    {
        double dr = a.R - b.R, dg = a.G - b.G, db = a.B - b.B;
        // Weight green slightly less so orange-vs-yellow still loses to cyan/magenta.
        return dr * dr + 0.7 * dg * dg + db * db;
    }

    private void ClearHighlight()
    {
        if (highlightAdorner != null)
        {
            var layer = AdornerLayer.GetAdornerLayer(highlightAdorner.AdornedElement);
            if (layer != null) layer.Remove(highlightAdorner);
            highlightAdorner = null;
        }
        highlightTarget = null;
    }

    private bool SelectCatalog(string key, bool highlight = false, bool templateOnly = false, bool preferReflect = false)
    {
        if (preferReflect && SelectInTree(adjustCatalog, key)) return true;
        if (SelectInTree(catalog, key)) return true;
        if (!templateOnly) return SelectInTree(adjustCatalog, key);
        return false;
    }

    private bool SelectInTree(TreeView tree, string key)
    {
        if (tree == null) return false;
        foreach (TreeViewItem group in tree.Items)
            if (SelectCatalogLeaf(group, key)) return true;
        return false;
    }

    private bool SelectCatalogLeaf(TreeViewItem parent, string key)
    {
        foreach (TreeViewItem leaf in parent.Items.OfType<TreeViewItem>())
        {
            if ((leaf.Tag as string) == key)
            {
                leaf.IsSelected = true;
                leaf.BringIntoView();
                HighlightCatalogItem(leaf);
                return true;
            }
            if (SelectCatalogLeaf(leaf, key)) return true;
        }
        return false;
    }

    private void CatalogRightButtonDown(object sender, MouseButtonEventArgs args)
    {
        var item = TreeItemFrom(args.OriginalSource as DependencyObject);
        if (item == null || item.ContextMenu == null) return;
        item.ContextMenu.PlacementTarget = item;
        item.ContextMenu.IsOpen = true;
        args.Handled = true;
    }

    private static TreeViewItem TreeItemFrom(DependencyObject source)
    {
        while (source != null)
        {
            var item = source as TreeViewItem;
            if (item != null) return item;
            source = VisualTreeHelper.GetParent(source);
        }
        return null;
    }

    private string NeighborCatalogKey(string key)
    {
        var keys = new List<string>();
        CollectCatalogKeys(catalog, keys, true);
        int index = keys.IndexOf(key);
        if (index > 0) return keys[index - 1];
        if (index >= 0 && index + 1 < keys.Count) return keys[index + 1];
        foreach (string fallback in keys)
            if (fallback != key && !fallback.StartsWith("#group:", StringComparison.Ordinal)) return fallback;
        return RmtCommonStyles.HiddenStyles.Contains("通用/Button") ? null : "通用/Button";
    }

    private static void CollectCatalogKeys(ItemsControl parent, List<string> keys, bool skipReflect)
    {
        foreach (TreeViewItem item in parent.Items.OfType<TreeViewItem>())
        {
            string tag = item.Tag as string;
            if (tag == "#group:反射控件")
            {
                if (!skipReflect) CollectCatalogKeys(item, keys, false);
                continue;
            }
            if (!string.IsNullOrEmpty(tag) && !tag.StartsWith("#group:", StringComparison.Ordinal)) keys.Add(tag);
            CollectCatalogKeys(item, keys, skipReflect);
        }
    }

    private void HighlightCatalogItem(TreeViewItem leaf)
    {
        if (leaf == null) return;
        if (catalogHighlight != null && !ReferenceEquals(catalogHighlight, leaf))
            SetLeafSelectedVisual(catalogHighlight, false);
        catalogHighlight = leaf;
        SetLeafSelectedVisual(leaf, true);
    }

    private FrameworkElement MakeLeafHeader(string text, bool selected)
    {
        var root = new Grid { MinHeight = 26 };
        var bg = new Border
        {
            Background = selected
                ? (TryFindResource("TabSelBg") as Brush
                    ?? TryFindResource("ActionHoverBg") as Brush
                    ?? new SolidColorBrush(Color.FromArgb(48, 255, 140, 0)))
                : Brushes.Transparent,
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(6, 3, 16, 3),
            Child = new TextBlock
            {
                Text = text,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = TryFindResource("TextMain") as Brush ?? Foreground
            }
        };
        root.Children.Add(bg);
        root.Children.Add(new Ellipse
        {
            Width = 6,
            Height = 6,
            Fill = TryFindResource("Accent") as Brush ?? Brushes.Orange,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 2, 2, 0),
            Visibility = selected ? Visibility.Visible : Visibility.Collapsed,
            IsHitTestVisible = false
        });
        return root;
    }

    private static string LeafText(TreeViewItem leaf)
    {
        if (leaf == null) return "";
        var grid = leaf.Header as Grid;
        if (grid != null)
        {
            var border = grid.Children.OfType<Border>().FirstOrDefault();
            var block = border == null ? null : border.Child as TextBlock;
            if (block != null) return block.Text ?? "";
        }
        return leaf.Header as string ?? "";
    }

    private void SetLeafSelectedVisual(TreeViewItem leaf, bool selected)
    {
        if (leaf == null) return;
        var grid = leaf.Header as Grid;
        if (grid != null)
        {
            var bg = grid.Children.OfType<Border>().FirstOrDefault();
            var dot = grid.Children.OfType<Ellipse>().FirstOrDefault();
            if (bg != null)
                bg.Background = selected
                    ? (TryFindResource("TabSelBg") as Brush
                        ?? TryFindResource("ActionHoverBg") as Brush
                        ?? new SolidColorBrush(Color.FromArgb(48, 255, 140, 0)))
                    : Brushes.Transparent;
            if (dot != null) dot.Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
        }
        else
            leaf.Header = MakeLeafHeader(LeafText(leaf), selected);
        leaf.BorderThickness = new Thickness(0);
        leaf.Padding = new Thickness(0);
        leaf.Background = Brushes.Transparent;
    }

    private void AddPositionFields(FrameworkElement target)
    {
        fields.Children.Add(new TextBlock { Text = "位置", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 2, 0, 4) });
        var row = ThreePairGrid();
        Point initial = RmtCommonStyles.ReadAnchorPosition(target, target is Window ? "窗口" : "父级", "左上");
        positionX = PositionBox("PositionX", initial.X);
        positionY = PositionBox("PositionY", initial.Y);
        var xLabel = AddPair(row, 0, "位置X", positionX);
        var yLabel = AddPair(row, 1, "位置Y", positionY);
        EnableNumberDrag(xLabel, positionX);
        EnableNumberDrag(yLabel, positionY);
        positionX.TextChanged += delegate { PreviewPosition(); };
        positionY.TextChanged += delegate { PreviewPosition(); };
        fields.Children.Add(row);
    }

    private static Grid ThreePairGrid()
    {
        var row = new Grid { Margin = new Thickness(0, 3, 0, 3) };
        for (int i = 0; i < 3; i++)
        {
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        return row;
    }

    private static TextBlock AddPair(Grid row, int pair, string title, FrameworkElement input)
    {
        int column = pair * 2;
        var label = new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0) };
        Grid.SetColumn(label, column); row.Children.Add(label);
        Grid.SetColumn(input, column + 1); row.Children.Add(input);
        return label;
    }

    private static TextBox PositionBox(string name, double value)
    {
        return new TextBox { Name = name, Text = value.ToString("0.##", CultureInfo.InvariantCulture), Height = 28, MinHeight = 28, Padding = new Thickness(2, 0, 2, 0), VerticalContentAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, PropertyColumnGap, 0) };
    }

    private static double WindowDimension(Window window, bool width)
    {
        if (window == null) return 0;
        double value = width ? window.Width : window.Height;
        if (double.IsNaN(value) || value <= 0) value = width ? window.ActualWidth : window.ActualHeight;
        if (double.IsNaN(value) || value <= 0) value = width ? window.RenderSize.Width : window.RenderSize.Height;
        return value > 0 ? value : (width ? 1 : 1);
    }

    private static string WindowLayoutDimension(Window window, bool width)
    {
        if (window == null) return "Auto";
        double value = width ? window.Width : window.Height;
        if (double.IsNaN(value)) return "Auto";
        return WindowDimension(window, width).ToString(CultureInfo.InvariantCulture);
    }

    private static void ApplyWindowDimension(Window window, string value, bool width)
    {
        if (window == null || string.IsNullOrWhiteSpace(value)) return;
        double visualScale = RmtCommonStyles.WindowContentVisualScale(window);
        if (value.Equals("Auto", StringComparison.OrdinalIgnoreCase))
        {
            if (width) window.Width = double.NaN; else window.Height = double.NaN;
            RmtCommonStyles.NormalizeWindowContentForResize(window, visualScale);
            return;
        }
        double number;
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) || number <= 0) return;
        if (width) window.Width = number; else window.Height = number;
        RmtCommonStyles.NormalizeWindowContentForResize(window, visualScale);
    }

    private void RefreshPositionValues()
    {
        var target = Inspected();
        if (target == null || positionX == null || positionY == null) return;
        Point point = RmtCommonStyles.ReadAnchorPosition(target, target is Window ? "窗口" : "父级", "左上");
        positionUpdating = true;
        positionX.Text = point.X.ToString("0.##", CultureInfo.InvariantCulture);
        positionY.Text = point.Y.ToString("0.##", CultureInfo.InvariantCulture);
        positionUpdating = false;
    }

    private void PreviewPosition()
    {
        if (rendering || positionUpdating) return;
        if (!ApplyInspectedPosition(true)) return;
        positionEdited = true;
        try { RmtCommonStyles.Save(); }
        catch (Exception ex) { status.Text = ex.Message; }
    }

    private void EnableNumberDrag(TextBlock label, TextBox box)
    {
        EnableNumberDrag(label, () => box.Text, value => { box.Text = value; });
    }

    private void EnableNumberDrag(TextBlock label, Func<string> getText, Action<string> setText)
    {
        bool dragging = false;
        Point start = new Point();
        double initial = 0;
        label.Cursor = Cursors.SizeWE;
        label.ToolTip = "按住并左右拖拽可调整数值";
        label.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs args)
        {
            string text = (getText() ?? "").Trim();
            if (text == "无限" || text.Equals("Auto", StringComparison.OrdinalIgnoreCase) || text == "Infinity" || text == "∞"
                || !double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out initial))
                initial = 0;
            dragging = true;
            start = Mouse.GetPosition(this);
            label.CaptureMouse();
            args.Handled = true;
        };
        label.MouseMove += delegate(object sender, MouseEventArgs args)
        {
            if (!dragging || args.LeftButton != MouseButtonState.Pressed) return;
            double value = Math.Max(0, initial + Mouse.GetPosition(this).X - start.X);
            setText(value.ToString("0.##", CultureInfo.InvariantCulture));
        };
        label.MouseLeftButtonUp += delegate(object sender, MouseButtonEventArgs args)
        {
            if (!dragging) return;
            dragging = false;
            label.ReleaseMouseCapture();
            args.Handled = true;
        };
    }

    private bool ApplyInspectedPosition(bool persist)
    {
        if (!LiveInspecting()) return true;
        var target = Inspected();
        if (target == null || positionX == null || positionY == null) return true;
        double left, top;
        if (!double.TryParse(positionX.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out left)
            || !double.TryParse(positionY.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out top))
        { status.Text = "位置X、位置Y请输入数字。"; return false; }
        var window = target as Window;
        string id = RmtCommonStyles.LayoutId(target);
        if (persist && id == "") { status.Text = "该控件没有稳定名称，位置无法永久保存。请先给控件命名。"; return false; }
        var layout = new Dictionary<string, string> {
            { "AnchorObject", target is Window ? "窗口" : "父级" },
            { "AnchorType", "左上" },
            { "PositionX", left.ToString(CultureInfo.InvariantCulture) },
            { "PositionY", top.ToString(CultureInfo.InvariantCulture) }
        };
        if (window != null)
        {
            layout["Width"] = WindowLayoutDimension(window, true);
            layout["Height"] = WindowLayoutDimension(window, false);
        }
        CapturePosition(target);
        RmtCommonStyles.ApplyAnchorLayout(target, layout);
        if (persist)
        {
            RmtCommonStyles.Layouts[id] = layout;
        }
        else dirty = true;
        return true;
    }

    private void CapturePosition(FrameworkElement target)
    {
        if (target == null || positionOriginals.ContainsKey(target)) return;
        var original = new PositionOriginal { Margin = target.Margin };
        var window = target as Window;
        if (window != null)
        {
            original.IsWindow = true; original.X = window.Left; original.Y = window.Top;
            original.Width = window.Width; original.Height = window.Height;
        }
        else if ((LogicalTreeHelper.GetParent(target) ?? VisualTreeHelper.GetParent(target)) is Canvas)
        {
            original.IsCanvas = true; original.X = Canvas.GetLeft(target); original.Y = Canvas.GetTop(target);
        }
        positionOriginals[target] = original;
    }

    private void RestorePosition(FrameworkElement target)
    {
        PositionOriginal original;
        if (target == null || !positionOriginals.TryGetValue(target, out original)) return;
        if (original.IsWindow)
        {
            var window = (Window)target;
            window.Left = original.X; window.Top = original.Y;
            window.Width = original.Width; window.Height = original.Height;
        }
        else if (original.IsCanvas) { Canvas.SetLeft(target, original.X); Canvas.SetTop(target, original.Y); }
        else target.Margin = original.Margin;
        positionOriginals.Remove(target);
    }

    private void RestoreAllPositions()
    {
        foreach (var target in positionOriginals.Keys.ToArray()) RestorePosition(target);
    }
    private static void AddButton(Panel parent, string title, Func<bool> callback)
    {
        var button = new Button { Content = title, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 8) };
        button.Click += delegate { callback(); }; parent.Children.Add(button);
    }
    private void Populate()
    {
        string old = selected, query = search == null ? "" : (search.Text ?? "");
        string adjustQuery = adjustSearch == null ? "" : (adjustSearch.Text ?? "");
        catalogHighlight = null;
        if (adjustCatalog != null) adjustCatalog.Items.Clear();
        catalog.Items.Clear();
        var all = new HashSet<string>(labels.Keys);
        all.UnionWith(new[] { "通用/Button", "通用/Window", "Window.TriggerKey", "Window.Theme" });
        all.UnionWith(RmtCommonStyles.Live().Select(x => x.Key));
        all.UnionWith(RmtCommonStyles.Values.Keys);
        all.UnionWith(RmtCommonStyles.CloneBases.Keys);
        var inspected = Inspected();
        var inspectRoot = InspectedRoot() ?? inspected;
        if (inspected != null) all.Add(RmtCommonStyles.StyleKeyPublic(inspected));
        if (inspectRoot != null) all.Add(RmtCommonStyles.StyleKeyPublic(inspectRoot));
        bool preferInspect = inspected != null && RmtCommonStyles.StyleKeyPublic(inspected) == old;
        TreeViewItem firstLeaf = null;
        TreeViewItem reflectLeaf = null;
        if (inspectRoot != null && adjustCatalog != null)
        {
            var inspectGroup = new TreeViewItem { Header = GroupTitle("反射控件"), Tag = "#group:反射控件", IsExpanded = true, FontWeight = FontWeights.SemiBold };
            var rootLeaf = AddInspectLeaf(inspectGroup, inspectRoot, adjustQuery, old, preferInspect ? inspected : null);
            if (rootLeaf != null)
            {
                adjustCatalog.Items.Add(inspectGroup);
                if (preferInspect) reflectLeaf = rootLeaf;
            }
        }
        var compositeGroup = MakeStyleGroup("组合模版");
        foreach (string key in all.Where(RmtCommonStyles.IsCompositeRoot).OrderBy(x => ButtonTitle(x)))
        {
            if (RmtCommonStyles.HiddenStyles.Contains(key)) continue;
            var branch = RmtCommonStyles.Composites[key];
            if (!BranchMatchesQuery(branch, query)) continue;
            var leaf = MakeCompositeLeaf(branch, old, ref firstLeaf, reflectLeaf == null);
            compositeGroup.Items.Add(leaf);
        }
        if (compositeGroup.Items.Count > 0 && !RmtCommonStyles.HiddenStyles.Contains("#group:组合模版")) catalog.Items.Add(compositeGroup);
        var buttonGroup = MakeStyleGroup("按钮");
        int buttonNo = 0;
        foreach (string key in all.Where(IsButtonKey).OrderBy(ButtonOrder))
        {
            if (RmtCommonStyles.HiddenStyles.Contains(key) || RmtCommonStyles.IsInstanceStyle(key)) continue;
            if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) continue;
            string text = key == "通用/Button" ? "按钮模版" : "按钮" + (++buttonNo) + " - " + ButtonTitle(key);
            if ((text + key).IndexOf(query, StringComparison.OrdinalIgnoreCase) < 0) continue;
            var leaf = MakeLeaf(text, key);
            buttonGroup.Items.Add(leaf);
            if (firstLeaf == null) firstLeaf = leaf;
            // Prefer the live reflected node when the style key also matches a template/named entry.
            if (key == old && reflectLeaf == null) leaf.IsSelected = true;
        }
        if (buttonGroup.Items.Count > 0 && !RmtCommonStyles.HiddenStyles.Contains("#group:按钮")) catalog.Items.Add(buttonGroup);
        var windowGroup = MakeStyleGroup("窗口");
        int windowNo = 0;
        foreach (string key in all.Where(RmtCommonStyles.IsWindowKey).OrderBy(WindowOrder))
        {
            if (RmtCommonStyles.HiddenStyles.Contains(key) || RmtCommonStyles.IsInstanceStyle(key)) continue;
            if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) continue;
            string text = key == "通用/Window" ? "窗口模版" : "窗口" + (++windowNo) + " - " + ButtonTitle(key);
            if ((text + key).IndexOf(query, StringComparison.OrdinalIgnoreCase) < 0) continue;
            var leaf = MakeLeaf(text, key);
            windowGroup.Items.Add(leaf);
            if (firstLeaf == null) firstLeaf = leaf;
            if (key == old && reflectLeaf == null) leaf.IsSelected = true;
        }
        if (windowGroup.Items.Count > 0 && !RmtCommonStyles.HiddenStyles.Contains("#group:窗口")) catalog.Items.Add(windowGroup);
        if (reflectLeaf == null && catalog.SelectedItem == null && firstLeaf != null) firstLeaf.IsSelected = true;
        var current = (reflectLeaf ?? catalog.SelectedItem) as TreeViewItem;
        if (current != null) HighlightCatalogItem(current);
    }

    private TreeViewItem AddInspectLeaf(TreeViewItem parent, FrameworkElement element, string query, string old, FrameworkElement selectedElement)
    {
        if (element == null) return null;
        string key = RmtCommonStyles.StyleKeyPublic(element);
        string text = element.GetType().Name + (string.IsNullOrEmpty(element.Name) ? "" : " / " + element.Name);
        var leaf = MakeLeaf(text, key, false);
        leaf.DataContext = new WeakReference(element);
        leaf.IsExpanded = true;
        bool visible = (text + key).IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0;
        TreeViewItem first = visible ? leaf : null;
        if (!(element is ComboBox || element is ListBox))
        {
            foreach (var child in RmtCommonStyles.StyleChildren(element))
            {
                var childLeaf = AddInspectLeaf(leaf, child, query, old, selectedElement);
                if (childLeaf != null) { visible = true; if (first == null) first = childLeaf; }
            }
        }
        if (!visible) return null;
        if (ReferenceEquals(element, selectedElement) || (selectedElement == null && key == old && parent.Header as string == "反射控件"))
            leaf.IsSelected = true;
        if (IsReflectGroup(parent)) AttachShowParentMenu(leaf);
        parent.Items.Add(leaf);
        return first ?? leaf;
    }

    private static bool IsReflectGroup(TreeViewItem item)
    {
        return item != null && ((item.Tag as string) == "#group:反射控件" || (item.Header as string) == "反射控件");
    }

    private void AttachShowParentMenu(TreeViewItem leaf)
    {
        if (leaf == null) return;
        if (leaf.ContextMenu == null) leaf.ContextMenu = new ContextMenu();
        foreach (MenuItem existing in leaf.ContextMenu.Items.OfType<MenuItem>())
            if ((existing.Header as string) == "显示父级") return;
        var showParent = new MenuItem { Header = "显示父级" };
        showParent.Click += delegate { ShowInspectParent(); };
        leaf.ContextMenu.Items.Insert(0, showParent);
    }

    internal void ShowInspectParent()
    {
        var parent = InspectParent(InspectedRoot() ?? Inspected());
        if (parent == null)
        {
            status.Text = "当前已是最顶层，没有可显示的父级。";
            return;
        }
        AcceptHierarchyTarget(parent);
    }

    private static FrameworkElement InspectParent(FrameworkElement element)
    {
        if (element == null || element is Window) return null;
        DependencyObject current = LogicalTreeHelper.GetParent(element);
        if (current == null && element is Visual) current = VisualTreeHelper.GetParent(element);
        while (current != null)
        {
            var fe = current as FrameworkElement;
            if (fe != null && RmtCommonStyles.IsPickable(fe) && !RmtCommonStyles.IsEditorWindow(Window.GetWindow(fe)))
                return fe;
            DependencyObject next = LogicalTreeHelper.GetParent(current);
            if (next == null && current is Visual) next = VisualTreeHelper.GetParent(current);
            current = next;
        }
        return null;
    }

    private bool BranchMatchesQuery(RmtCommonStyles.StyleBranch branch, string query)
    {
        if (branch == null) return false;
        if ((ButtonTitle(branch.Key) + branch.Key + (branch.Type ?? "")).IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0) return true;
        foreach (var child in branch.Children)
            if (BranchMatchesQuery(child, query)) return true;
        return false;
    }

    private TreeViewItem MakeCompositeLeaf(RmtCommonStyles.StyleBranch branch, string old, ref TreeViewItem firstLeaf, bool canSelect)
    {
        string text = string.IsNullOrEmpty(branch.Path)
            ? ButtonTitle(branch.Key)
            : ((string.IsNullOrEmpty(branch.Type) ? "控件" : branch.Type) + (string.IsNullOrEmpty(branch.Path) ? "" : " · " + branch.Path));
        var leaf = MakeLeaf(text, branch.Key);
        leaf.IsExpanded = true;
        if (firstLeaf == null) firstLeaf = leaf;
        if (canSelect && branch.Key == old) leaf.IsSelected = true;
        foreach (var child in branch.Children)
            leaf.Items.Add(MakeCompositeLeaf(child, old, ref firstLeaf, canSelect));
        return leaf;
    }

    private TreeViewItem MakeStyleGroup(string name)
    {
        var group = new TreeViewItem
        {
            Header = GroupTitle(name),
            Tag = "#group:" + name,
            IsExpanded = true,
            FontWeight = FontWeights.SemiBold
        };
        var menu = new ContextMenu();
        var rename = new MenuItem { Header = "重命名" };
        rename.Click += delegate { BeginGroupRename(group, name); };
        menu.Items.Add(rename);
        var delete = new MenuItem { Header = "删除" };
        delete.Click += delegate { DeleteCatalogGroup(name); };
        menu.Items.Add(delete);
        group.ContextMenu = menu;
        return group;
    }

    private string GroupTitle(string name)
    {
        string custom;
        return RmtCommonStyles.DisplayNames.TryGetValue("#group:" + name, out custom) && !string.IsNullOrWhiteSpace(custom) ? custom : name;
    }

    private void BeginGroupRename(TreeViewItem group, string name)
    {
        var edit = new TextBox { Text = GroupTitle(name), MinWidth = 120, Padding = new Thickness(3) };
        bool done = false;
        Action<bool> finish = accept =>
        {
            if (done) return; done = true;
            string title = edit.Text.Trim();
            if (accept && !string.IsNullOrEmpty(title))
            {
                RmtCommonStyles.DisplayNames["#group:" + name] = title;
                dirty = true;
            }
            Populate();
        };
        edit.KeyDown += delegate(object sender, System.Windows.Input.KeyEventArgs args)
        {
            if (args.Key == System.Windows.Input.Key.Enter) { finish(true); args.Handled = true; }
            else if (args.Key == System.Windows.Input.Key.Escape) { finish(false); args.Handled = true; }
        };
        edit.LostKeyboardFocus += delegate { finish(true); };
        group.Header = edit;
        Dispatcher.BeginInvoke(new Action(delegate { edit.Focus(); edit.SelectAll(); }));
    }

    private void DeleteCatalogGroup(string name)
    {
        var keys = new List<string>();
        CollectCatalogKeys(catalog, keys, true);
        var group = catalog.Items.OfType<TreeViewItem>().FirstOrDefault(x => (x.Tag as string) == "#group:" + name);
        if (group != null)
        {
            keys.Clear();
            CollectCatalogKeys(group, keys, false);
        }
        string neighbor = null;
        foreach (string key in keys)
        {
            if (neighbor == null) neighbor = NeighborCatalogKey(key);
            DeleteCatalogStyleSilent(key);
        }
        RmtCommonStyles.HiddenStyles.Add("#group:" + name);
        selected = neighbor;
        dirty = true;
        Populate();
        if (!SelectCatalog(selected, true, true)) SelectCatalog(selected, true);
        Render();
        status.Text = "已删除模版类别「" + GroupTitle(name) + "」。";
    }

    private void DeleteCatalogStyleSilent(string key)
    {
        if (!CanDeleteStyle(key)) return;
        foreach (string item in RmtCommonStyles.StyleTreeKeys(key).ToArray()) drafts.Remove(item);
        RmtCommonStyles.RemoveStyleTree(key);
        RmtCommonStyles.HiddenStyles.Add(key);
    }

    private TreeViewItem MakeLeaf(string text, string key)
    {
        return MakeLeaf(text, key, true);
    }

    private TreeViewItem MakeLeaf(string text, string key, bool allowDelete)
    {
        var leaf = new TreeViewItem {
            Header = MakeLeafHeader(text, false), Tag = key, ToolTip = key, Padding = new Thickness(0),
            FontWeight = FontWeights.Normal,
            BorderThickness = new Thickness(0),
            Foreground = TryFindResource("TextMain") as Brush ?? Foreground
        };
        var menu = new ContextMenu();
        if (key != "通用/Button" && key != "通用/Window")
        {
            var rename = new MenuItem { Header = "重命名" };
            rename.Click += delegate { BeginRename(leaf, key); };
            menu.Items.Add(rename);
        }
        var copy = new MenuItem { Header = "新增模版" };
        copy.Click += delegate { CopyStyle(key); };
        menu.Items.Add(copy);
        if (allowDelete && CanDeleteStyle(key))
        {
            var delete = new MenuItem { Header = "删除" };
            delete.Click += delegate { DeleteCatalogStyle(key); };
            menu.Items.Add(delete);
        }
        leaf.ContextMenu = menu;
        return leaf;
    }

    private void BeginRename(TreeViewItem leaf, string key)
    {
        var edit = new TextBox { Text = ButtonTitle(key), MinWidth = 170, Padding = new Thickness(3) };
        string original = LeafText(leaf);
        bool done = false;
        Action<bool> finish = accept =>
        {
            if (done) return; done = true;
            string name = edit.Text.Trim();
            if (accept && !string.IsNullOrEmpty(name)) { RmtCommonStyles.DisplayNames[key] = name; dirty = true; }
            leaf.Header = MakeLeafHeader(original, ReferenceEquals(leaf, catalogHighlight)); Populate();
        };
        edit.KeyDown += delegate(object sender, System.Windows.Input.KeyEventArgs args)
        {
            if (args.Key == System.Windows.Input.Key.Enter) { finish(true); args.Handled = true; }
            else if (args.Key == System.Windows.Input.Key.Escape) { finish(false); args.Handled = true; }
        };
        edit.LostKeyboardFocus += delegate { finish(true); };
        leaf.Header = edit;
        Dispatcher.BeginInvoke(new Action(delegate { edit.Focus(); edit.SelectAll(); }));
    }

    private static bool IsButtonKey(string key)
    {
        if (string.IsNullOrEmpty(key) || key.StartsWith("特殊/", StringComparison.Ordinal)) return false;
        if (RmtCommonStyles.IsWindowKey(key)) return false;
        if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) return false;
        if (key.StartsWith("样式/", StringComparison.Ordinal)
            && (key.IndexOf("Btn", StringComparison.OrdinalIgnoreCase) >= 0
                || key.IndexOf("Button", StringComparison.OrdinalIgnoreCase) >= 0))
            return true;
        return ControlType(key) == "按钮";
    }
    private static int ButtonOrder(string key)
    {
        if (key == "通用/Button") return 0;
        if (key == "样式/RmtItemEditBtn") return 1;
        if (key == "样式/RmtItemPrimaryBtn") return 2;
        if (key == "Main.Config") return 3;
        if (key == "Main.Save") return 4;
        if (key == "Theme.Confirm") return 5;
        return 1000;
    }
    private static int WindowOrder(string key)
    {
        if (key == "通用/Window") return 0;
        if (key == "Window.TriggerKey") return 1;
        if (key == "Window.Theme") return 2;
        return 1000;
    }
    private string ButtonTitle(string key)
    {
        string value;
        if (RmtCommonStyles.DisplayNames.TryGetValue(key, out value) && !string.IsNullOrWhiteSpace(value)) return value;
        if (labels.TryGetValue(key, out value))
        {
            int mark = value.IndexOf('·');
            return mark >= 0 ? value.Substring(mark + 1).Trim() : value;
        }
        return "未命名样式";
    }

    private static string ControlType(string key)
    {
        string raw = key.StartsWith("通用/") ? key.Substring(3) : key;
        if (RmtCommonStyles.IsWindowKey(key) || raw == "Window") return "窗口";
        if (raw.IndexOf("Button", StringComparison.OrdinalIgnoreCase) >= 0
            || raw.IndexOf("Btn", StringComparison.OrdinalIgnoreCase) >= 0
            || raw.StartsWith("Main.") || raw.StartsWith("Theme.")) return "按钮";
        return "其它控件";
    }
    private string DisplayName(string key)
    {
        string value;
        if (labels.TryGetValue(key, out value)) return value;
        if (key == "通用/Button") return "按钮模版";
        if (key == "通用/Window") return "窗口模版";
        if (key.StartsWith("样式/Button")) return key.Substring(3).Replace("Button", "按钮 ");
        return key.StartsWith("通用/") ? "通用 " + key.Substring(3) : key;
    }

    private void CopyStyle(string sourceName)
    {
        if (string.IsNullOrEmpty(sourceName) || (!IsButtonKey(sourceName) && !RmtCommonStyles.IsWindowKey(sourceName) && !RmtCommonStyles.IsCompositeRoot(sourceName)))
        {
            status.Text = "请选择一个控件样式后再复制。"; return;
        }
        string family = RmtCommonStyles.IsWindowKey(sourceName) ? "Window" : (RmtCommonStyles.IsCompositeRoot(sourceName) ? (RmtCommonStyles.Composites[sourceName].Type ?? "Panel") + "Group" : "Button");
        int number = 1; string next;
        do { next = family + number++; } while (RmtCommonStyles.Values.ContainsKey(next) || RmtCommonStyles.CloneBases.ContainsKey(next) || RmtCommonStyles.Composites.ContainsKey(next));
        Dictionary<string, string> original;
        RmtCommonStyles.Values.TryGetValue(sourceName, out original);
        RmtCommonStyles.Values[next] = original == null ? new Dictionary<string, string>() : new Dictionary<string, string>(original);
        RmtCommonStyles.CloneBases[next] = sourceName;
        RmtCommonStyles.StyleBranch composite;
        if (RmtCommonStyles.Composites.TryGetValue(sourceName, out composite))
            RmtCommonStyles.Composites[next] = CopyCompositeWithKey(composite, sourceName, next);
        if (IsButtonKey(next) || RmtCommonStyles.IsWindowKey(next) || RmtCommonStyles.IsCompositeRoot(next)) RmtCommonStyles.DisplayNames[next] = ButtonTitle(sourceName) + "（副本）";
        dirty = true; selected = next; Populate(); Render();
        status.Text = DisplayName(next) + " 已由「" + DisplayName(sourceName) + "」复制；可在右侧继续调整。";
    }

    private static RmtCommonStyles.StyleBranch CopyCompositeWithKey(RmtCommonStyles.StyleBranch source, string fromKey, string toKey)
    {
        var copy = RmtCommonStyles.CloneBranch(source);
        RelocateBranchKeys(copy, fromKey, toKey);
        return copy;
    }

    private static void RelocateBranchKeys(RmtCommonStyles.StyleBranch branch, string fromKey, string toKey)
    {
        if (branch == null) return;
        if (branch.Key == fromKey) branch.Key = toKey;
        else if (branch.Key != null && branch.Key.StartsWith(fromKey + "/", StringComparison.Ordinal))
            branch.Key = toKey + branch.Key.Substring(fromKey.Length);
        RmtCommonStyles.Values[branch.Key] = new Dictionary<string, string>(branch.Properties);
        foreach (var child in branch.Children) RelocateBranchKeys(child, fromKey, toKey);
    }

    private void Render()
    {
        rendering = true;
        interactionReady = false;
        int ticket = ++renderTicket;
        fields.Children.Clear(); preview.Children.Clear(); inputs.Clear(); colorInputs.Clear(); optionInputs.Clear(); sliderInputs.Clear(); dimensionInputs.Clear(); presetInputs.Clear(); chromeChecks.Clear(); colorTouched.Clear(); sliderTouched.Clear(); dimensionTouched.Clear(); presetTouched.Clear(); optionTouched.Clear(); propertyRow = null; propertyPair = 0; templateRows = null; sample = null;
        if (selected == null) { rendering = false; ArmInteraction(ticket); return; }
        var inspected = Inspected();
        bool inspectMode = LiveInspecting();
        if (RmtCommonStyles.IsWindowKey(selected))
        {
            PrepareWindowSample();
            if (inspectMode) AddTemplateSection(inspected);
            AddPreviewOptions();
            AddReloadHeading(inspectMode, inspected);
            AddWindowReloadFields();
            if (inspectMode) AddPositionFields(inspected);
            if (inspectMode) ShowHierarchyPreview(inspected);
            else ShowWindowPreview();
            rendering = false;
            ArmInteraction(ticket);
            return;
        }
        Dictionary<string, string> values; TryEditingValues(out values);
        var compositeBranch = FindSelectedBranch();
        if ((values == null || values.Count == 0) && compositeBranch != null) values = compositeBranch.Properties;
        string previewBase;
        RmtCommonStyles.CloneBases.TryGetValue(selected, out previewBase);
        string targetKey = previewBase ?? selected;
        bool fromTemplateClone = previewBase == "通用/Button" && selected != "通用/Button";
        bool isTemplate = selected == "通用/Button" || fromTemplateClone;
        var matches = fromTemplateClone ? new List<RmtCommonStyles.Entry>() : RmtCommonStyles.Live().Where(x => x.Key == targetKey || (targetKey.StartsWith("通用/") && ((FrameworkElement)x.Element.Target).GetType().Name == targetKey.Substring(3))).ToList();
        var entry = matches.FirstOrDefault();
        bool namedPreview = IsNamedButtonKey(targetKey);
        // Named styles must be previewed from a real registered target. A generic replacement is misleading for icon buttons and fixed layouts.
        if (!inspectMode && entry == null && !targetKey.StartsWith("通用/") && !namedPreview && compositeBranch == null)
        {
            preview.Children.Add(new TextBlock { Text = "对应目标控件尚未打开；打开它并点击“刷新实例”后，预览会直接复制目标样式、内容和尺寸。", TextWrapping = TextWrapping.Wrap });
            fields.Children.Add(new TextBlock { Text = "为避免错误预览，此命名样式在没有真实实例时不显示替代控件。", TextWrapping = TextWrapping.Wrap });
            rendering = false;
            ArmInteraction(ticket);
            return;
        }
        previewHintWidth = 0;
        if (inspectMode) sample = inspected;
        else if (isTemplate) { sample = CreateSample("通用/Button"); ConfigureButtonTemplate(sample as Button); }
        else if (namedPreview) sample = CreateNamedPreviewSample(targetKey, entry);
        else if (compositeBranch != null && (entry == null || RmtCommonStyles.IsCompositeRoot(selected) || RmtCommonStyles.IsCompositeChild(selected)))
            sample = CreateSample("通用/" + (compositeBranch.Type ?? "Button")) ?? new Button();
        else if (entry == null) sample = CreateSample(targetKey);
        else sample = entry.Element.Target as FrameworkElement;
        if (!inspectMode && entry == null && sample != null && targetKey.StartsWith("样式/"))
            sample.Style = TryFindResource(targetKey.Substring(3)) as Style;
        if (!inspectMode && entry == null && !isTemplate && !namedPreview && sample is Button && IsButtonKey(selected))
            BindButtonChrome((Button)sample, "ActionHoverBg", "ActionPressBg");
        if (sample == null) { fields.Children.Add(new TextBlock { Text = "请先打开使用此样式的界面，再刷新目录。" }); rendering = false; ArmInteraction(ticket); return; }
        if (!inspectMode && entry != null && !namedPreview && !isTemplate)
            previewHintWidth = ((FrameworkElement)entry.Element.Target).ActualWidth;
        if (!inspectMode && entry == null && !selected.StartsWith("通用/") && !namedPreview && sample.Style == null)
            fields.Children.Add(new TextBlock { Text = "此界面尚未加载，当前为类型示例；打开对应界面并刷新后可查看实际样式。", TextWrapping = TextWrapping.Wrap });
        AddPreviewOptions();
        if (inspectMode) AddTemplateSection(inspected);
        AddReloadHeading(inspectMode, inspected);
        propertyRow = null; propertyPair = 0;
        foreach (string property in RmtCommonStyles.Properties)
        {
            if (property == "Width" || property == "Height" || property == "MinWidth" || property == "MinHeight" || property == "MaxWidth" || property == "MaxHeight") continue;
            if (!ShouldShowProperty(sample, property)) continue;
            var dp = RmtCommonStyles.Property(sample, property); if (dp == null) continue;
            bool bound = BindingOperations.IsDataBound(sample, dp);
            object displayed = property == "RelativeFontSize" ? (object)0 : ResolveDisplayedValue(sample, property, dp);
            string current = property == "RelativeFontSize" ? "0" : RmtCommonStyles.Text(displayed);
            Field(property, values != null && values.ContainsKey(property) ? values[property] : "", current, bound);
        }
        string sizeMode = SizeMode(values, sample);
        Field("SizeMode", sizeMode, sizeMode, false);
        if (sizeMode == "固定宽高" || sizeMode == "自适应高度")
            AddSizeField("Width", values);
        if (sizeMode == "固定宽高" || sizeMode == "自适应宽度")
            AddSizeField("Height", values);
        if (sizeMode == "自适应宽度") { AddSizeField("MinWidth", values); AddSizeField("MaxWidth", values); }
        if (sizeMode == "自适应高度") { AddSizeField("MinHeight", values); AddSizeField("MaxHeight", values); }
        if (sizeMode == "自适应宽高")
        {
            AddSizeField("MinWidth", values); AddSizeField("MinHeight", values);
            AddSizeField("MaxWidth", values); AddSizeField("MaxHeight", values);
        }
        if (inspectMode) AddPositionFields(inspected);
        if (sample.Style != null)
        {
            try { fields.Children.Add(new Expander { Header = "样式模板 / 交互状态（只读来源）", Margin = new Thickness(0, 8, 0, 0), Content = new TextBox { Text = System.Windows.Markup.XamlWriter.Save(sample.Style), IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 240, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } }); }
            catch { }
        }
        if (inspectMode) ShowHierarchyPreview(inspected);
        else ShowPreview(sample);
        rendering = false;
        ArmInteraction(ticket);
    }

    private void ArmInteraction(int ticket)
    {
        Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(delegate
        {
            if (renderTicket == ticket) interactionReady = true;
        }));
    }

    private void AddTemplateSection(FrameworkElement target)
    {
        string templateKey = "通用/" + target.GetType().Name;
        string cloneBase;
        if (RmtCommonStyles.CloneBases.TryGetValue(selected, out cloneBase) && !string.IsNullOrEmpty(cloneBase))
            templateKey = cloneBase;
        Dictionary<string, string> template;
        TryConfiguredValues(templateKey, out template);
        var templateBody = new StackPanel();
        fields.Children.Add(new Expander
        {
            Header = "模版属性（" + templateKey + "，只读）",
            IsExpanded = false,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 8, 0, 6),
            Content = templateBody
        });
        templateRows = templateBody;
        FrameworkElement templateSample = CreateSample(templateKey);
        if (templateSample == null)
        {
            try { templateSample = Activator.CreateInstance(target.GetType()) as FrameworkElement; }
            catch { templateSample = target; }
        }
        if (templateKey == "通用/Button") ConfigureButtonTemplate(templateSample as Button);
        bool windowTarget = target is Window || RmtCommonStyles.IsWindowKey(selected);
        Grid row = null;
        int pairIndex = 0;
        foreach (string property in RmtCommonStyles.Properties)
        {
            if (property == "SizeMode" || property == "Width" || property == "Height" || property == "MinWidth" || property == "MinHeight" || property == "MaxWidth" || property == "MaxHeight") continue;
            if (windowTarget && !IsWindowReloadProperty(property)) continue;
            if (!ShouldShowProperty(templateSample, property)) continue;
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, property);
        }
        string sizeMode = SizeMode(template, templateSample);
        AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "SizeMode", sizeMode);
        if (sizeMode == "固定宽高" || sizeMode == "自适应高度")
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "Width");
        if (sizeMode == "固定宽高" || sizeMode == "自适应宽度")
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "Height");
        if (sizeMode == "自适应宽度")
        {
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MinWidth");
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MaxWidth");
        }
        if (sizeMode == "自适应高度")
        {
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MinHeight");
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MaxHeight");
        }
        if (sizeMode == "自适应宽高")
        {
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MinWidth");
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MinHeight");
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MaxWidth");
            AddTemplateProperty(ref row, ref pairIndex, templateSample, template, "MaxHeight");
        }
        if (windowTarget)
        {
            foreach (string chrome in RmtCommonStyles.WindowExtraProperties)
            {
                string shown = DefaultChrome(templateKey, chrome) ? "True" : "False";
                if (template != null && template.ContainsKey(chrome)) shown = template[chrome];
                AddTemplateProperty(ref row, ref pairIndex, templateSample, template, chrome, shown);
            }
        }
        templateRows = null;
    }

    private void AddReloadHeading(bool inspectMode, FrameworkElement target)
    {
        string title = inspectMode ? "重载属性（修改后立即作用到选中控件）" : "重载属性";
        var templates = inspectMode ? ListReloadTemplates(target) : new List<string>();
        if (templates.Count == 0)
        {
            fields.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 6) });
            return;
        }
        fields.Children.Add(new TextBlock { Text = title, Height = 0, Margin = new Thickness(0), Visibility = Visibility.Collapsed });
        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 6), LastChildFill = true };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 200, 0) };
        DockPanel.SetDock(actions, Dock.Right);
        actions.Children.Add(new TextBlock { Text = "重载列表", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var combo = new ComboBox { Name = "ReloadList", MinWidth = 180, MinHeight = 28, VerticalAlignment = VerticalAlignment.Center };
        int selectedIndex = 0;
        for (int i = 0; i < templates.Count; i++)
        {
            string key = templates[i];
            combo.Items.Add(new ComboBoxItem { Content = key == "通用/Button" ? "按钮模版" : (key == "通用/Window" ? "窗口模版" : DisplayName(key)), Tag = key });
            if (key == reloadListKey) selectedIndex = i;
        }
        if (combo.Items.Count > 0)
        {
            combo.SelectedIndex = selectedIndex;
            var current = combo.SelectedItem as ComboBoxItem;
            if (current != null) reloadListKey = current.Tag as string;
        }
        combo.SelectionChanged += delegate
        {
            if (rendering || !interactionReady) return;
            var selectedItem = combo.SelectedItem as ComboBoxItem;
            reloadListKey = selectedItem == null ? null : selectedItem.Tag as string;
            if (LiveInspecting()) ShowHierarchyPreview(Inspected());
        };
        var apply = new Button { Name = "CmdApplyReloadList", Content = "应用", Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        apply.Click += delegate
        {
            if (rendering) return;
            var item = combo.SelectedItem as ComboBoxItem;
            ApplyReloadFromTemplate(item == null ? null : item.Tag as string);
        };
        actions.Children.Add(combo);
        actions.Children.Add(apply);
        row.Children.Add(actions);
        row.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        fields.Children.Add(row);
    }

    private List<string> ListReloadTemplates(FrameworkElement target)
    {
        var result = new List<string>();
        if (target == null) return result;
        var all = new HashSet<string>(labels.Keys);
        all.UnionWith(new[] { "通用/Button", "通用/Window" });
        all.UnionWith(RmtCommonStyles.Values.Keys);
        all.UnionWith(RmtCommonStyles.CloneBases.Keys);
        if (target is Button)
        {
            foreach (string key in all.Where(IsButtonKey).OrderBy(ButtonOrder))
            {
                if (RmtCommonStyles.HiddenStyles.Contains(key) || RmtCommonStyles.IsInstanceStyle(key)) continue;
                if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) continue;
                result.Add(key);
            }
        }
        else if (target is Window)
        {
            foreach (string key in all.Where(RmtCommonStyles.IsWindowKey).OrderBy(WindowOrder))
            {
                if (RmtCommonStyles.HiddenStyles.Contains(key) || RmtCommonStyles.IsInstanceStyle(key)) continue;
                if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) continue;
                result.Add(key);
            }
        }
        else
        {
            string typeName = target.GetType().Name;
            string typeKey = "通用/" + typeName;
            foreach (var pair in RmtCommonStyles.Composites)
            {
                if (RmtCommonStyles.HiddenStyles.Contains(pair.Key)) continue;
                if (string.Equals(pair.Value.Type, typeName, StringComparison.Ordinal)) result.Add(pair.Key);
            }
            foreach (string key in all)
            {
                if (RmtCommonStyles.HiddenStyles.Contains(key) || RmtCommonStyles.IsInstanceStyle(key)) continue;
                if (RmtCommonStyles.IsCompositeRoot(key) || RmtCommonStyles.IsCompositeChild(key)) continue;
                string clone;
                if (RmtCommonStyles.CloneBases.TryGetValue(key, out clone) && clone == typeKey && !result.Contains(key))
                    result.Add(key);
            }
        }
        return result;
    }

    internal void ApplyReloadFromTemplate(string templateKey)
    {
        var target = Inspected();
        if (string.IsNullOrEmpty(templateKey) || target == null) return;
        inspectingSelection = true;
        selected = RmtCommonStyles.StyleKeyPublic(target);
        reloadListKey = templateKey;
        Dictionary<string, string> source = CaptureTemplateReloadValues(templateKey);
        if (!StoreEdits(new Dictionary<string, string>(source), true)) return;
        target.UpdateLayout();
        Render();
        status.Text = "已应用「" + DisplayName(templateKey) + "」的重载属性。";
    }

    private Dictionary<string, string> CaptureTemplateReloadValues(string templateKey)
    {
        var result = new Dictionary<string, string>();
        if (string.IsNullOrEmpty(templateKey)) return result;
        string clone;
        if (RmtCommonStyles.CloneBases.TryGetValue(templateKey, out clone) && !string.IsNullOrEmpty(clone) && clone != templateKey)
            MergeConfiguredValues(result, clone);
        MergeConfiguredValues(result, templateKey);
        RmtCommonStyles.StyleBranch branch;
        if (RmtCommonStyles.Composites.TryGetValue(templateKey, out branch) && branch != null && branch.Properties != null)
            foreach (var pair in branch.Properties) result[pair.Key] = pair.Value;
        if (result.Count == 0)
            CollectLocalStyleProperties(CreateRawTemplateSample(templateKey), result);
        NormalizeRelativeFontSize(result);
        return RmtCommonStyles.SanitizeStyle(result);
    }

    private FrameworkElement CreateRawTemplateSample(string templateKey)
    {
        var sample = CreateSample(templateKey);
        if (sample == null) return null;
        if (templateKey == "通用/Button") ConfigureButtonTemplate(sample as Button);
        else if (IsNamedButtonKey(templateKey)) ConfigureNamedButtonSample(sample as Button, templateKey);
        return sample;
    }

    private void CollectLocalStyleProperties(FrameworkElement sample, Dictionary<string, string> result)
    {
        if (sample == null || result == null) return;
        foreach (string name in RmtCommonStyles.Properties)
        {
            if (name == "SizeMode" || name == "Margin") continue;
            var dp = RmtCommonStyles.Property(sample, name);
            if (dp == null || sample.ReadLocalValue(dp) == DependencyProperty.UnsetValue) continue;
            if (name == "RelativeFontSize")
            {
                double actual = (double)sample.GetValue(dp);
                double offset = actual - RmtCommonStyles.ThemeFontSize(source);
                if (Math.Abs(offset) < 0.01) continue;
                result[name] = offset.ToString("0.##", CultureInfo.InvariantCulture);
                continue;
            }
            result[name] = RmtCommonStyles.Text(sample.GetValue(dp));
        }
    }

    private void NormalizeRelativeFontSize(Dictionary<string, string> result)
    {
        string text;
        if (result == null || !result.TryGetValue("RelativeFontSize", out text)) return;
        double number;
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number)) return;
        if (number > 8 || number < -8)
            number = number - RmtCommonStyles.ThemeFontSize(source);
        if (Math.Abs(number) < 0.01) result.Remove("RelativeFontSize");
        else result["RelativeFontSize"] = number.ToString("0.##", CultureInfo.InvariantCulture);
    }

    private void MergeConfiguredValues(Dictionary<string, string> result, string key)
    {
        Dictionary<string, string> values;
        if (result == null || string.IsNullOrEmpty(key) || !TryConfiguredValues(key, out values) || values == null) return;
        foreach (var pair in values) result[pair.Key] = pair.Value;
    }

    private static bool ShouldShowProperty(FrameworkElement sample, string name)
    {
        if (sample == null || string.IsNullOrEmpty(name)) return false;
        if (name == "Spacing" || name == "ChildAlignment") return sample is StackPanel;
        if (name == "HoverBackground" || name == "PressedBackground") return sample is Button;
        if (name == "MaxDropDownHeight") return sample is ComboBox;
        return true;
    }

    private static bool IsWindowReloadProperty(string name)
    {
        return name == "Background" || name == "CornerRadius" || name == "Padding" || name == "SizeMode"
            || name == "Width" || name == "Height" || name == "MinWidth" || name == "MinHeight"
            || name == "MaxWidth" || name == "MaxHeight" || RmtCommonStyles.IsWindowExtra(name);
    }

    private void AddTemplateProperty(ref Grid row, ref int pairIndex, FrameworkElement templateSample, Dictionary<string, string> template, string property, string explicitCurrent = null)
    {
        string current = explicitCurrent;
        if (property != "SizeMode" && !RmtCommonStyles.IsWindowExtra(property))
        {
            var dp = RmtCommonStyles.Property(templateSample, property);
            if (dp == null) return;
            if (property == "RelativeFontSize")
            {
                double baseSize = RmtCommonStyles.ThemeFontSize(source);
                double actual = (double)RmtCommonStyles.DisplayValue(templateSample, property, dp);
                current = (actual - baseSize).ToString("0.##", CultureInfo.InvariantCulture);
            }
            else
            {
                current = RmtCommonStyles.Text(ResolveDisplayedValue(templateSample, property, dp));
                if ((property == "Width" || property == "Height") && (current == "NaN" || string.IsNullOrEmpty(current))) current = "Auto";
                if ((property == "MaxWidth" || property == "MaxHeight") && (current == "Infinity" || current == "∞")) current = "无限";
            }
        }
        if (row == null || pairIndex == 3)
        {
            row = ThreePairGrid();
            (templateRows ?? (Panel)fields).Children.Add(row);
            pairIndex = 0;
        }
        string configured = template != null && template.ContainsKey(property) ? template[property] : "";
        AddTemplateDisplayField(row, pairIndex++, property, configured, current);
    }

    private void AddTemplateDisplayField(Grid row, int pair, string name, string value, string current)
    {
        FrameworkElement input;
        if (RmtCommonStyles.IsColorProperty(name))
            input = new TextBox { Text = ConcreteColor(value, current), IsReadOnly = true, Height = 28, MinHeight = 28, Padding = new Thickness(2, 0, 2, 0), VerticalContentAlignment = VerticalAlignment.Center, ToolTip = name };
        else if (IsPresetProperty(name))
        {
            string shown = NormalizeThickness(string.IsNullOrEmpty(value) ? current : value);
            input = new TextBox { Text = shown, IsReadOnly = true, Height = 28, MinHeight = 28, Padding = new Thickness(2, 0, 2, 0), VerticalContentAlignment = VerticalAlignment.Center, ToolTip = name };
        }
        else
        {
            string shown = string.IsNullOrEmpty(value) ? current : value;
            input = new TextBox { Text = shown, IsReadOnly = true, Height = 28, MinHeight = 28, Padding = new Thickness(2, 0, 2, 0), VerticalContentAlignment = VerticalAlignment.Center, ToolTip = name };
        }
        input.Margin = new Thickness(0, 0, PropertyColumnGap, 0);
        input.Opacity = .58;
        input.IsHitTestVisible = false;
        input.Focusable = false;
        var label = AddPair(row, pair, propertyLabels.ContainsKey(name) ? propertyLabels[name] : name, input);
        label.Opacity = .58;
    }

    private string ConcreteColor(string value, string current)
    {
        if (RmtCommonStyles.IsThemeColor(value))
        {
            var brush = TryFindResource(RmtCommonStyles.ThemeColorKey(value)) as Brush;
            if (brush != null) return RmtCommonStyles.Text(brush);
        }
        return string.IsNullOrEmpty(value) ? current : value;
    }

    private void PrepareWindowSample()
    {
        string previewBase;
        RmtCommonStyles.CloneBases.TryGetValue(selected, out previewBase);
        string targetKey = previewBase ?? selected;
        var matches = RmtCommonStyles.Live().Where(x => x.Element.Target is Window && (x.Key == targetKey || (targetKey == "通用/Window" && x.Key == "通用/Window"))).ToList();
        var inspectedWindow = Inspected();
        sample = (inspectedWindow is Window && selected == RmtCommonStyles.StyleKeyPublic(inspectedWindow))
            ? inspectedWindow
            : (matches.Count > 0 ? matches[0].Element.Target as FrameworkElement : new Window());
    }

    private void AddWindowReloadFields()
    {
        Dictionary<string, string> values;
        TryEditingValues(out values);
        bool locatedWindow = LocatingSelectedWindow();
        Dictionary<string, string> displayValues = values;
        if (locatedWindow)
        {
            // A located window displays its live instance dimensions.  Older configurations
            // may still contain Width/Height under the shared Window key; do not surface those
            // stale values or accidentally reapply them when another reload field is edited.
            displayValues = values == null ? new Dictionary<string, string>() : new Dictionary<string, string>(values);
            displayValues.Remove("Width"); displayValues.Remove("Height");
            displayValues.Remove("MinWidth"); displayValues.Remove("MinHeight");
            displayValues.Remove("MaxWidth"); displayValues.Remove("MaxHeight");
            displayValues.Remove("SizeMode");
        }
        string previewBase;
        RmtCommonStyles.CloneBases.TryGetValue(selected, out previewBase);
        string targetKey = previewBase ?? selected;
        fields.Children.Add(new TextBlock { Text = "右上角交互按钮", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 4, 0, 6) });
        var chromeRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
        AddChromeCheck(chromeRow, "ShowMinimize", "最小化", values, DefaultChrome(targetKey, "ShowMinimize"));
        AddChromeCheck(chromeRow, "ShowMaximize", "最大化", values, DefaultChrome(targetKey, "ShowMaximize"));
        AddChromeCheck(chromeRow, "ShowPin", "置顶", values, DefaultChrome(targetKey, "ShowPin"));
        AddChromeCheck(chromeRow, "ShowClose", "关闭", values, DefaultChrome(targetKey, "ShowClose"));
        fields.Children.Add(chromeRow);
        propertyRow = null; propertyPair = 0;
        string pad = values != null && values.ContainsKey("Padding") ? values["Padding"] : CurrentWindowPadding();
        Field("Padding", values != null && values.ContainsKey("Padding") ? values["Padding"] : "", pad, false);
        string radius = values != null && values.ContainsKey("CornerRadius") ? values["CornerRadius"] : CurrentWindowCornerRadius();
        Field("CornerRadius", values != null && values.ContainsKey("CornerRadius") ? values["CornerRadius"] : "", radius, false);
        var bgDp = RmtCommonStyles.Property(sample, "Background");
        string bgCurrent = bgDp == null ? "" : RmtCommonStyles.Text(RmtCommonStyles.DisplayValue(sample, "Background", bgDp));
        Field("Background", values != null && values.ContainsKey("Background") ? values["Background"] : "", bgCurrent, bgDp != null && BindingOperations.IsDataBound(sample, bgDp));
        if (locatedWindow)
        {
            // Keep the legacy size-mode controls available for existing GM-UI users.  When
            // this is a concrete window, CommitWindow routes the resulting dimensions into
            // that window's Layout entry instead of the shared Window style.
            string sizeMode = SizeMode(displayValues, sample);
            Field("SizeMode", sizeMode, sizeMode, false);
            if (sizeMode == "固定宽高" || sizeMode == "自适应高度") AddSizeField("Width", displayValues);
            if (sizeMode == "固定宽高" || sizeMode == "自适应宽度") AddSizeField("Height", displayValues);
            if (sizeMode == "自适应宽度") { AddSizeField("MinWidth", displayValues); AddSizeField("MaxWidth", displayValues); }
            if (sizeMode == "自适应高度") { AddSizeField("MinHeight", displayValues); AddSizeField("MaxHeight", displayValues); }
            if (sizeMode == "自适应宽高")
            {
                AddSizeField("MinWidth", displayValues); AddSizeField("MinHeight", displayValues);
                AddSizeField("MaxWidth", displayValues); AddSizeField("MaxHeight", displayValues);
            }
        }
    }

    private string CurrentWindowCornerRadius()
    {
        var window = sample as Window;
        if (window != null && window.Resources.Contains("WindowRadius"))
            return RmtCommonStyles.Text(window.Resources["WindowRadius"]);
        var resource = window == null ? null : window.TryFindResource("WindowRadius");
        if (resource != null) return RmtCommonStyles.Text(resource);
        return "0";
    }

    private static bool DefaultChrome(string key, string prop)
    {
        if (prop == "ShowClose") return true;
        return false;
    }

    private string CurrentWindowPadding()
    {
        var window = sample as Window;
        var body = window == null ? null : RmtCommonStyles.WindowBody(window);
        if (body != null) return RmtCommonStyles.Text(body.Margin);
        return "0";
    }

    private void AddChromeCheck(Panel parent, string name, string title, Dictionary<string, string> values, bool fallback)
    {
        bool on = fallback;
        string stored;
        if (values != null && values.TryGetValue(name, out stored))
            on = stored.Equals("True", StringComparison.OrdinalIgnoreCase);
        else
        {
            var window = sample as Window;
            string btnName = name == "ShowMinimize" ? "BtnMinimize" : name == "ShowMaximize" ? "BtnMaximize" : name == "ShowPin" ? "BtnPin" : "BtnClosePanel";
            var btn = window == null ? null : window.FindName(btnName) as UIElement;
            if (btn == null && name == "ShowClose" && window != null)
                btn = (window.FindName("BtnWinClose") as UIElement) ?? (window.FindName("BtnClose") as UIElement);
            if (btn != null) on = btn.Visibility == Visibility.Visible;
        }
        var box = new CheckBox { Content = title, IsChecked = on, Margin = new Thickness(0, 0, 18, 0), VerticalAlignment = VerticalAlignment.Center };
        box.Click += delegate { if (!interactionReady) return; Commit(false); };
        parent.Children.Add(box);
        chromeChecks[name] = box;
    }

    private void ShowWindowPreview()
    {
        preview.Children.Clear();
        bool min = ChromeOn("ShowMinimize"), max = ChromeOn("ShowMaximize"), pin = ChromeOn("ShowPin"), close = ChromeOn("ShowClose");
        string pad = ComboTextOrDefault("Padding", CurrentWindowPadding());
        CornerRadius previewRadius = SafeCornerRadius(ComboTextOrDefault("CornerRadius", CurrentWindowCornerRadius()));
        Brush previewBg = PreviewWindowBackground();
        var frame = new Border
        {
            BorderBrush = TryFindResource("ControlBorder") as Brush ?? Brushes.Gray,
            BorderThickness = new Thickness(1),
            CornerRadius = previewRadius,
            Background = previewBg,
            Width = 360,
            Height = 150,
            SnapsToDevicePixels = true
        };
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(chromeButtonHeight) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var bar = new Grid { Background = TryFindResource("TitleBarColor") as Brush ?? Brushes.LightGray };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.Children.Add(new TextBlock
        {
            Text = selected == "通用/Window" ? "窗口模版" : ButtonTitle(selected),
            Foreground = TryFindResource("TitleBarForeground") as Brush ?? Brushes.Black,
            FontWeight = FontWeights.Bold,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(12, 0, 0, 0)
        });
        var btns = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        Grid.SetColumn(btns, 1);
        if (min) btns.Children.Add(PreviewChromeGlyph("\uE921"));
        if (max) btns.Children.Add(PreviewChromeGlyph("\uE922"));
        if (pin) btns.Children.Add(PreviewChromeGlyph("\uE840"));
        if (close) btns.Children.Add(PreviewChromeGlyph("\uE8BB"));
        bar.Children.Add(btns);
        var body = new Border
        {
            Background = TryFindResource("InputBg") as Brush
                ?? TryFindResource("ControlBorder") as Brush
                ?? Brushes.LightGray,
            Padding = SafeThickness(pad),
            Child = new Border
            {
                Background = TryFindResource("BgColor") as Brush ?? Brushes.White,
                Child = new TextBlock
                {
                    Text = "示例内容",
                    VerticalAlignment = VerticalAlignment.Center,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Opacity = 0.55
                }
            }
        };
        Grid.SetRow(body, 1);
        grid.Children.Add(bar);
        grid.Children.Add(body);
        frame.Child = grid;
        double scale = SourceContentScale();
        if (Math.Abs(scale - 1) > 0.01)
            frame.LayoutTransform = new ScaleTransform(scale, scale);
        preview.Children.Add(frame);
    }

    private Border PreviewChromeGlyph(string glyph)
    {
        return new Border
        {
            Width = chromeButtonWidth,
            Height = chromeButtonHeight,
            Child = new TextBlock
            {
                Text = glyph,
                FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
                FontSize = chromeGlyphSize,
                FontWeight = chromeGlyphWeight,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
    }

    private bool ChromeOn(string name)
    {
        CheckBox box;
        if (chromeChecks.TryGetValue(name, out box) && box.IsChecked == true) return true;
        return false;
    }

    private static Thickness SafeThickness(string value)
    {
        try { return (Thickness)RmtCommonStyles.ConvertValue(typeof(Thickness), value); }
        catch { return new Thickness(0); }
    }

    private static CornerRadius SafeCornerRadius(string value)
    {
        try { return (CornerRadius)RmtCommonStyles.ConvertValue(typeof(CornerRadius), value); }
        catch { return new CornerRadius(6); }
    }

    private Brush PreviewWindowBackground()
    {
        ComboBox color;
        if (colorInputs.TryGetValue("Background", out color))
        {
            var item = color.SelectedItem as ComboBoxItem;
            string value = item == null ? "" : (item.Tag as string ?? "");
            if (RmtCommonStyles.IsThemeColor(value))
            {
                var theme = TryFindResource(RmtCommonStyles.ThemeColorKey(value)) as Brush;
                if (theme != null) return theme;
            }
        }
        var control = sample as Control;
        if (control != null && control.Background != null) return control.Background;
        return TryFindResource("BgColor") as Brush ?? Brushes.White;
    }

    private static string SizeMode(Dictionary<string, string> values, FrameworkElement element)
    {
        string value;
        if (values != null && values.TryGetValue("SizeMode", out value) && (value == "固定宽高" || value == "自适应宽度" || value == "自适应高度" || value == "自适应宽高")) return value;
        bool autoW = (values != null && values.TryGetValue("Width", out value) && value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) || (element != null && double.IsNaN(element.Width));
        bool autoH = (values != null && values.TryGetValue("Height", out value) && value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) || (element != null && double.IsNaN(element.Height));
        if (autoW && autoH) return "自适应宽高";
        if (autoW) return "自适应宽度";
        if (autoH) return "自适应高度";
        return "固定宽高";
    }

    private void AddSizeField(string name, Dictionary<string, string> values)
    {
        var dp = RmtCommonStyles.Property(sample, name);
        if (dp == null) return;
        string current = RmtCommonStyles.Text(RmtCommonStyles.DisplayValue(sample, name, dp));
        if ((name == "Width" || name == "Height") && (current == "NaN" || string.IsNullOrEmpty(current))) current = "Auto";
        if ((name == "MaxWidth" || name == "MaxHeight") && (current == "Infinity" || current == "∞")) current = "无限";
        Field(name, values != null && values.ContainsKey(name) ? values[name] : "", current, BindingOperations.IsDataBound(sample, dp));
    }

    private static FrameworkElement CreateSample(string key)
    {
        if (key == "Theme.Confirm" || key == "Main.Config" || key == "Main.Save" || key.Contains("Btn")) return new Button();
        if (!key.StartsWith("通用/")) return null;
        Type type = typeof(Button).Assembly.GetType("System.Windows.Controls." + key.Substring(3));
        return type == null ? null : Activator.CreateInstance(type) as FrameworkElement;
    }

    private void ConfigureButtonTemplate(Button button)
    {
        if (button == null) return;
        // The template is a representative action button, not WPF's bare default Button.
        // Its inherited values therefore match the properties shown at right.
        button.SetResourceReference(Control.BackgroundProperty, "ActionBg");
        button.SetResourceReference(Control.ForegroundProperty, "ActionText");
        button.SetResourceReference(Control.BorderBrushProperty, "ActionBg");
        BindButtonChrome(button, "ActionHoverBg", "ActionPressBg");
        button.BorderThickness = new Thickness(1);
        button.Padding = new Thickness(10, 4, 10, 4);
        button.Height = 32;
        button.MinHeight = 32;
        button.FontSize = RmtCommonStyles.ThemeFontSize(source);
        button.SetValue(RmtCommonStyles.Property(button, "CornerRadius"), new CornerRadius(3));
        button.HorizontalContentAlignment = HorizontalAlignment.Center;
        button.VerticalContentAlignment = VerticalAlignment.Center;
        button.Template = ThemeConfirmTemplate();
    }

    private string PressedResourceKey(string preferred)
    {
        if (!string.IsNullOrEmpty(preferred) && TryFindResource(preferred) != null) return preferred;
        if (TryFindResource("ActionPressBg") != null) return "ActionPressBg";
        if (TryFindResource("BtnPressBg") != null) return "BtnPressBg";
        return "ActionHoverBg";
    }

    private void BindButtonChrome(Button button, string hoverKey, string pressPreferred)
    {
        if (button == null) return;
        var hoverDp = RmtCommonStyles.Property(button, "HoverBackground");
        var pressDp = RmtCommonStyles.Property(button, "PressedBackground");
        string pressKey = PressedResourceKey(pressPreferred);
        if (hoverDp != null)
        {
            var hover = TryFindResource(hoverKey) as Brush ?? RmtCommonStyles.FallbackButtonChrome("HoverBackground", this, source);
            if (hover != null) button.SetValue(hoverDp, hover);
            else if (!string.IsNullOrEmpty(hoverKey)) button.SetResourceReference(hoverDp, hoverKey);
        }
        if (pressDp != null)
        {
            var press = TryFindResource(pressKey) as Brush ?? RmtCommonStyles.FallbackButtonChrome("PressedBackground", this, source);
            if (press != null) button.SetValue(pressDp, press);
            else if (!string.IsNullOrEmpty(pressKey)) button.SetResourceReference(pressDp, pressKey);
        }
    }

    private object ResolveDisplayedValue(FrameworkElement element, string name, DependencyProperty dp)
    {
        object displayed = RmtCommonStyles.DisplayValue(element, name, dp);
        if (name != "HoverBackground" && name != "PressedBackground") return displayed;
        if (RmtCommonStyles.IsVisibleBrush(displayed as Brush)) return displayed;
        return RmtCommonStyles.FallbackButtonChrome(name, element, this, source);
    }

    private static bool IsNamedButtonKey(string key)
    {
        return key == "Theme.Confirm" || key == "Main.Config" || key == "Main.Save";
    }

    private FrameworkElement CreateNamedPreviewSample(string key, RmtCommonStyles.Entry entry)
    {
        var button = CreateSample(key) as Button;
        ConfigureNamedButtonSample(button, key);
        var live = entry == null ? null : entry.Element.Target as FrameworkElement;
        if (live != null)
        {
            previewHintWidth = live.ActualWidth;
            var liveButton = live as Button;
            if (liveButton != null && liveButton.Template != null) button.Template = liveButton.Template;
            foreach (string name in RmtCommonStyles.Properties)
            {
                var dp = RmtCommonStyles.Property(live, name);
                if (dp == null || live.ReadLocalValue(dp) == DependencyProperty.UnsetValue) continue;
                CopyPreviewProperty(button, live, name);
            }
        }
        Dictionary<string, string> configured;
        if (TryConfiguredValues(key, out configured))
            foreach (var pair in configured)
                ApplyPreviewValue(button, pair.Key, pair.Value);
        return button;
    }

    private void ConfigureNamedButtonSample(Button button, string key)
    {
        if (button == null) return;
        if (key == "Theme.Confirm")
        {
            button.SetResourceReference(Control.BackgroundProperty, "ActionBg");
            button.SetResourceReference(Control.ForegroundProperty, "ActionText");
            button.SetResourceReference(Control.BorderBrushProperty, "ActionStroke");
            BindButtonChrome(button, "ActionHoverBg", "ActionPressBg");
            button.BorderThickness = new Thickness(1);
            button.FontWeight = FontWeights.Bold;
            button.FontSize = RmtCommonStyles.ThemeFontSize(source);
            button.Width = 80;
            button.Height = 32;
            button.Padding = new Thickness(0);
            button.Content = "确定";
            button.Cursor = Cursors.Hand;
            button.HorizontalContentAlignment = HorizontalAlignment.Center;
            button.VerticalContentAlignment = VerticalAlignment.Center;
            button.Template = ThemeConfirmTemplate();
            return;
        }
        // Match MainWindowXaml defaultBtnStyle / RmtSidebarBtn so preview size and padding match override fields.
        button.SetResourceReference(Control.BackgroundProperty, "ControlBg");
        button.SetResourceReference(Control.ForegroundProperty, "TextMain");
        button.SetResourceReference(Control.BorderBrushProperty, "OutlineStroke");
        BindButtonChrome(button, "ControlBorder", "BtnPressBg");
        button.BorderThickness = new Thickness(1.5);
        button.Padding = new Thickness(10, 0, 10, 0);
        button.Cursor = Cursors.Hand;
        button.HorizontalContentAlignment = HorizontalAlignment.Center;
        button.VerticalContentAlignment = VerticalAlignment.Center;
        button.Template = MainButtonChromeTemplate();
        if (key == "Main.Config")
        {
            button.Height = 33;
            button.MinHeight = 33;
            button.Content = "配置管理";
            return;
        }
        if (key == "Main.Save")
        {
            button.FontWeight = FontWeights.Bold;
            button.Height = 36;
            button.MinHeight = 36;
            button.Content = "应用并保存";
        }
    }

    private static ControlTemplate ThemeConfirmTemplate()
    {
        // Hover/press colors are applied by CommonHoverBackground / CommonPressedBackground hooks.
        // Do not also set IsMouseOver triggers here: they paint the template Border first, then the
        // hook captures that hover brush as "base" and fails to restore the normal background.
        return (ControlTemplate)XamlReader.Parse(@"<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='Button'>
          <Border x:Name='bd' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' CornerRadius='3' Padding='{TemplateBinding Padding}'>
            <ContentPresenter HorizontalAlignment='{TemplateBinding HorizontalContentAlignment}' VerticalAlignment='{TemplateBinding VerticalContentAlignment}'/>
          </Border>
        </ControlTemplate>");
    }

    private static ControlTemplate MainButtonChromeTemplate()
    {
        return (ControlTemplate)XamlReader.Parse(@"<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='Button'>
          <Border x:Name='Bd' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' CornerRadius='3' Padding='{TemplateBinding Padding}'>
            <ContentPresenter HorizontalAlignment='{TemplateBinding HorizontalContentAlignment}' VerticalAlignment='{TemplateBinding VerticalContentAlignment}' Margin='0'/>
          </Border>
        </ControlTemplate>");
    }

    private string DefaultPreviewText()
    {
        var inspected = Inspected();
        if (inspected != null && selected == RmtCommonStyles.StyleKeyPublic(inspected))
        {
            string live = LivePreviewText(inspected);
            if (!string.IsNullOrEmpty(live)) return live;
        }
        var content = sample as ContentControl;
        string actual = content == null ? null : content.Content as string;
        if (!string.IsNullOrEmpty(actual)) return actual;
        var block = sample as TextBlock;
        if (block != null && !string.IsNullOrEmpty(block.Text)) return block.Text;
        var box = sample as TextBox;
        if (box != null && !string.IsNullOrEmpty(box.Text)) return box.Text;
        var combo = sample as ComboBox;
        if (combo != null)
        {
            if (!string.IsNullOrEmpty(combo.Text)) return combo.Text;
            string selectedText = ComboItemText(combo.SelectedItem);
            if (!string.IsNullOrEmpty(selectedText)) return selectedText;
        }
        if (selected == "Theme.Confirm") return "确定";
        if (selected == "Main.Config") return "配置管理";
        if (selected == "Main.Save") return "应用并保存";
        return sample is Button ? "按钮" : "文本内容";
    }

    private static string ComboItemText(object item)
    {
        if (item == null) return "";
        var box = item as ComboBoxItem;
        if (box != null)
        {
            string content = box.Content as string;
            return content ?? (box.Content == null ? "" : box.Content.ToString());
        }
        return item.ToString();
    }

    private static string ComboOptionsText(ComboBox combo)
    {
        if (combo == null) return "";
        var parts = new List<string>();
        foreach (object item in combo.Items)
        {
            string text = ComboItemText(item);
            if (!string.IsNullOrEmpty(text)) parts.Add(text);
        }
        return string.Join(",", parts.ToArray());
    }

    private static string[] SplitComboOptions(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return new string[0];
        var parts = new List<string>();
        foreach (string part in text.Split(new[] { ',', '，' }))
        {
            string item = part.Trim();
            if (item.Length > 0) parts.Add(item);
        }
        return parts.ToArray();
    }

    private void ApplyComboPreview(ComboBox combo, ComboBox original)
    {
        if (combo == null) return;
        string[] options = previewOptions != null ? SplitComboOptions(previewOptions.Text) : new string[0];
        if (options.Length == 0 && original != null) options = SplitComboOptions(ComboOptionsText(original));
        if (options.Length == 0) options = new[] { "选项一", "选项二" };
        combo.Items.Clear();
        foreach (string option in options) combo.Items.Add(option);
        string selectedText = previewContent != null ? previewContent.Text : "";
        if (!string.IsNullOrEmpty(selectedText))
        {
            combo.Items.Remove(selectedText);
            combo.Items.Insert(0, selectedText);
            combo.SelectedIndex = 0;
            if (combo.IsEditable) combo.Text = selectedText;
        }
        else if (combo.Items.Count > 0) combo.SelectedIndex = 0;
        if (original != null) combo.MaxDropDownHeight = original.MaxDropDownHeight;
        RmtCommonStyles.ApplyComboDropDown(combo);
        RmtCommonStyles.ApplyCorners(combo);
    }

    private static string LivePreviewText(FrameworkElement element)
    {
        if (element == null) return "";
        var block = element as TextBlock;
        if (block != null && !string.IsNullOrEmpty(block.Text)) return block.Text;
        var box = element as TextBox;
        if (box != null && !string.IsNullOrEmpty(box.Text)) return box.Text;
        var content = element as ContentControl;
        string text = content == null || content is Window ? null : content.Content as string;
        if (!string.IsNullOrEmpty(text)) return text;
        foreach (var child in RmtCommonStyles.StyleChildren(element))
        {
            string nested = LivePreviewText(child);
            if (!string.IsNullOrEmpty(nested)) return nested;
        }
        return "";
    }

    private void AddPreviewOptions()
    {
        previewContent = null;
        previewOptions = null;
        bool inspectMode = Inspected() != null && selected == RmtCommonStyles.StyleKeyPublic(Inspected());
        if (!inspectMode && sample == null) return;
        var row = new Grid { Margin = new Thickness(0, 0, 0, 9) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(new TextBlock { Text = "示例内容", VerticalAlignment = VerticalAlignment.Center, ToolTip = "仅影响右侧预览；可输入普通文本或符号。" });
        previewContent = new TextBox { Text = DefaultPreviewText(), Height = 42, Padding = new Thickness(5), ToolTip = "例如：保存、✓、⚙" };
        previewContent.TextChanged += delegate { RefreshPreviewFromOptions(); };
        Grid.SetColumn(previewContent, 1); row.Children.Add(previewContent); fields.Children.Add(row);
        if (sample is ComboBox || Inspected() is ComboBox)
        {
            var optionRow = new Grid { Margin = new Thickness(0, 0, 0, 9) };
            optionRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
            optionRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            optionRow.Children.Add(new TextBlock { Text = "选项内容", VerticalAlignment = VerticalAlignment.Center, ToolTip = "用逗号分隔下拉选项，仅影响右侧预览。" });
            previewOptions = new TextBox { Text = ComboOptionsText((sample as ComboBox) ?? (Inspected() as ComboBox)), Height = 42, Padding = new Thickness(5), ToolTip = "例如：选项一,选项二,选项三" };
            previewOptions.TextChanged += delegate { RefreshPreviewFromOptions(); };
            Grid.SetColumn(previewOptions, 1); optionRow.Children.Add(previewOptions); fields.Children.Add(optionRow);
        }
    }

    private void RefreshPreviewFromOptions()
    {
        if (rendering) return;
        preview.Children.Clear();
        if (LiveInspecting()) ShowHierarchyPreview(Inspected());
        else if (sample != null) ShowPreview(sample);
    }
    private void ShowPreview(FrameworkElement original)
    {
        FrameworkElement element;
        try { element = Activator.CreateInstance(original.GetType()) as FrameworkElement; } catch { return; }
        if (element == null) return;
        // The preview inherits the editor's detached resource snapshot from its visual parent.
        element.Style = original.Style;
        var elementButton = element as Button;
        var originalButton = original as Button;
        if (elementButton != null && originalButton != null && originalButton.Template != null)
            elementButton.Template = originalButton.Template;
        var elementCombo = element as ComboBox;
        var originalCombo = original as ComboBox;
        if (elementCombo != null && originalCombo != null && originalCombo.Template != null)
            elementCombo.Template = originalCombo.Template;
        foreach (string name in RmtCommonStyles.Properties)
        {
            if (RmtCommonStyles.IsColorProperty(name) && !HasPaintedBrush(original, name)) continue;
            CopyPreviewProperty(element, original, name);
        }
        Dictionary<string, string> configured;
        TryEditingValues(out configured);
        if (configured != null)
            foreach (var pair in configured)
                ApplyPreviewValue(element, pair.Key, pair.Value);
        foreach (var input in colorInputs)
        {
            if (!colorTouched.Contains(input.Key) && (configured == null || !configured.ContainsKey(input.Key))) continue;
            var item = input.Value.SelectedItem as ComboBoxItem;
            string value = item == null ? "" : (item.Tag as string ?? "");
            if (!string.IsNullOrEmpty(value)) ApplyPreviewValue(element, input.Key, value);
        }
        foreach (var input in presetInputs)
        {
            if (!presetTouched.Contains(input.Key) && (configured == null || !configured.ContainsKey(input.Key))) continue;
            string value = ComboText(input.Value);
            if (!string.IsNullOrEmpty(value)) ApplyPreviewValue(element, input.Key, value);
        }
        var content = element as ContentControl;
        if (content != null)
        {
            var originalContent = original as ContentControl;
            string actual = originalContent == null ? null : originalContent.Content as string;
            content.Content = previewContent != null && !string.IsNullOrEmpty(previewContent.Text) ? previewContent.Text : (!string.IsNullOrEmpty(actual) ? actual : PreviewTextFor(element));
        }
        var text = element as TextBox;
        if (text != null) text.Text = PreviewOverrideText(original as TextBox != null ? ((TextBox)original).Text : "输入内容");
        var block = element as TextBlock;
        if (block != null) block.Text = PreviewOverrideText(original as TextBlock != null ? ((TextBlock)original).Text : "文本内容");
        var combo = element as ComboBox;
        if (combo != null) ApplyComboPreview(combo, original as ComboBox);
        var list = element as ListBox; if (list != null) { list.Items.Add("内容一"); list.Items.Add("内容二"); }
        var border = element as Border; if (border != null) border.Child = new TextBlock { Text = "内容框" };
        // Prefer the live control's rendered width so stretch sidebar buttons keep matching padding/size.
        if (double.IsNaN(element.Width))
        {
            double hint = original.ActualWidth > 1 ? original.ActualWidth : previewHintWidth;
            if (hint > 1) element.Width = Math.Min(440, hint);
            else if (element.HorizontalAlignment == HorizontalAlignment.Stretch)
                element.HorizontalAlignment = HorizontalAlignment.Left;
        }
        var host = new Border { Child = element, HorizontalAlignment = HorizontalAlignment.Left, MaxWidth = 440, Padding = new Thickness(0) };
        double scale = SourceContentScale();
        if (Math.Abs(scale - 1) > 0.01)
            host.LayoutTransform = new ScaleTransform(scale, scale);
        preview.Children.Add(host);
        element.ApplyTemplate();
        RmtCommonStyles.ApplyCorners(element as Control);
    }

    private string PreviewOverrideText(string fallback)
    {
        return previewContent != null && !string.IsNullOrEmpty(previewContent.Text) ? previewContent.Text : (fallback ?? "");
    }

    private static bool HasPaintedBrush(FrameworkElement element, string name)
    {
        var dp = RmtCommonStyles.Property(element, name);
        if (element == null || dp == null) return false;
        if (element.ReadLocalValue(dp) != DependencyProperty.UnsetValue) return true;
        var brush = element.GetValue(dp) as SolidColorBrush;
        return brush != null && brush.Color.A > 0 && !brush.Color.Equals(Colors.Transparent);
    }

    private void ShowHierarchyPreview(FrameworkElement original)
    {
        if (original == null) return;
        preview.Children.Clear();
        var templates = ListReloadTemplates(original);
        bool showReload = templates.Count > 0;
        var grid = new Grid
        {
            Height = 160,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var left = PreviewColumn("控件样式", BuildControlStylePreview(original));
        grid.Children.Add(left);
        if (showReload)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var split = new Border
            {
                Width = 1.5,
                Margin = new Thickness(8, 0, 8, 0),
                Background = TryFindResource("Win_GroupStroke") as Brush
                    ?? TryFindResource("OutlineStroke") as Brush
                    ?? TryFindResource("ControlBorder") as Brush
                    ?? Brushes.Gray,
                VerticalAlignment = VerticalAlignment.Stretch,
                SnapsToDevicePixels = true
            };
            Grid.SetColumn(split, 1);
            grid.Children.Add(split);
            string key = reloadListKey;
            if (string.IsNullOrEmpty(key)) key = templates[0];
            var right = PreviewColumn("重载样式", BuildReloadStylePreview(key, original));
            Grid.SetColumn(right, 2);
            grid.Children.Add(right);
        }
        preview.Children.Add(grid);
    }

    private UIElement PreviewColumn(string title, FrameworkElement content)
    {
        var panel = new DockPanel { LastChildFill = true };
        var header = new TextBlock
        {
            Text = title,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 6)
        };
        DockPanel.SetDock(header, Dock.Top);
        panel.Children.Add(header);
        panel.Children.Add(HostPreview(content));
        return new Border
        {
            BorderBrush = TryFindResource("Win_GroupStroke") as Brush
                ?? TryFindResource("OutlineStroke") as Brush
                ?? TryFindResource("ControlBorder") as Brush
                ?? Brushes.Gray,
            BorderThickness = new Thickness(1.5),
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(8),
            SnapsToDevicePixels = true,
            Child = panel
        };
    }

    private UIElement HostPreview(FrameworkElement element)
    {
        if (element == null || element is Window)
            return new TextBlock { Text = "无预览", Opacity = 0.5, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        bool panelPreview = element is Panel;
        element.HorizontalAlignment = panelPreview ? HorizontalAlignment.Left : HorizontalAlignment.Center;
        element.VerticalAlignment = panelPreview ? VerticalAlignment.Top : VerticalAlignment.Center;
        var host = new Border
        {
            Child = element,
            HorizontalAlignment = panelPreview ? HorizontalAlignment.Left : HorizontalAlignment.Center,
            VerticalAlignment = panelPreview ? VerticalAlignment.Top : VerticalAlignment.Center,
            Background = Brushes.Transparent
        };
        double scale = SourceContentScale();
        if (Math.Abs(scale - 1) > 0.01)
            host.LayoutTransform = new ScaleTransform(scale, scale);
        if (panelPreview)
            return new ScrollViewer { Content = host, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var stage = new Grid { ClipToBounds = true };
        stage.Children.Add(host);
        return stage;
    }

    private FrameworkElement BuildControlStylePreview(FrameworkElement original)
    {
        FrameworkElement clone = ClonePreviewElement(original, 0);
        if (clone == null) return null;
        Dictionary<string, string> configured;
        if (TryEditingValues(out configured) && configured != null)
            foreach (var pair in configured)
                ApplyPreviewValue(clone, pair.Key, pair.Value);
        ApplyPreviewTextOverride(clone, original);
        MatchLivePreviewSize(clone, original);
        return clone;
    }

    private FrameworkElement BuildReloadStylePreview(string templateKey, FrameworkElement located)
    {
        if (string.IsNullOrEmpty(templateKey)) return null;
        if (located is Window || RmtCommonStyles.IsWindowKey(templateKey))
        {
            var liveWindow = located as Window;
            return liveWindow == null ? null : CloneWindowPreview(liveWindow, 0);
        }
        FrameworkElement element;
        if (IsNamedButtonKey(templateKey) || templateKey.IndexOf("Btn", StringComparison.Ordinal) >= 0)
            element = CreateNamedPreviewSample(templateKey, null);
        else
            element = CreateRawTemplateSample(templateKey);
        if (element == null && located != null && !(located is Window))
        {
            try { element = Activator.CreateInstance(located.GetType()) as FrameworkElement; }
            catch { element = null; }
            if (element is Button && templateKey == "通用/Button") ConfigureButtonTemplate(element as Button);
        }
        if (element == null || element is Window) return null;
        Dictionary<string, string> props = CaptureTemplateReloadValues(templateKey);
        foreach (var pair in props)
            ApplyPreviewValue(element, pair.Key, pair.Value);
        var content = element as ContentControl;
        if (content != null && content.Content == null)
        {
            var originalContent = located as ContentControl;
            string actual = originalContent == null ? null : originalContent.Content as string;
            content.Content = previewContent != null && !string.IsNullOrEmpty(previewContent.Text)
                ? previewContent.Text
                : (!string.IsNullOrEmpty(actual) ? actual : PreviewTextFor(element));
        }
        var text = element as TextBox;
        if (text != null && string.IsNullOrEmpty(text.Text))
            text.Text = PreviewOverrideText(located as TextBox != null ? ((TextBox)located).Text : "输入内容");
        var block = element as TextBlock;
        if (block != null && string.IsNullOrEmpty(block.Text))
            block.Text = PreviewOverrideText(located as TextBlock != null ? ((TextBlock)located).Text : "文本内容");
        var combo = element as ComboBox;
        if (combo != null) ApplyComboPreview(combo, located as ComboBox);
        element.HorizontalAlignment = HorizontalAlignment.Center;
        element.VerticalAlignment = VerticalAlignment.Center;
        return element;
    }

    private static void MatchLivePreviewSize(FrameworkElement clone, FrameworkElement original)
    {
        if (clone == null || original == null) return;
        clone.Margin = new Thickness(0);
        clone.HorizontalAlignment = HorizontalAlignment.Left;
        clone.VerticalAlignment = VerticalAlignment.Top;
        if (double.IsNaN(clone.Width) && original.ActualWidth > 1) clone.Width = original.ActualWidth;
        if (double.IsNaN(clone.Height) && original.ActualHeight > 1) clone.Height = original.ActualHeight;
    }

    private void ApplyPreviewTextOverride(FrameworkElement clone, FrameworkElement original)
    {
        if (clone is ComboBox)
        {
            ApplyComboPreview((ComboBox)clone, original as ComboBox);
            return;
        }
        if (clone == null || original == null || previewContent == null || string.IsNullOrEmpty(previewContent.Text)) return;
        var block = clone as TextBlock;
        if (block != null) { block.Text = previewContent.Text; return; }
        var box = clone as TextBox;
        if (box != null) { box.Text = previewContent.Text; return; }
        var content = clone as ContentControl;
        if (content != null && !(clone is Window) && ((original as ContentControl) != null) && ((ContentControl)original).Content is string)
        {
            content.Content = previewContent.Text;
            return;
        }
        var cloneKids = RmtCommonStyles.StyleChildren(clone);
        var originalKids = RmtCommonStyles.StyleChildren(original);
        int count = Math.Min(cloneKids.Count, originalKids.Count);
        for (int i = 0; i < count; i++)
            ApplyPreviewTextOverride(cloneKids[i], originalKids[i]);
    }

    private FrameworkElement ClonePreviewElement(FrameworkElement src, int depth)
    {
        if (src == null || depth > 16 || src.Visibility == Visibility.Collapsed || IsWindowChromeElement(src)) return null;
        var window = src as Window;
        if (window != null) return CloneWindowPreview(window, depth);
        FrameworkElement dest;
        try { dest = Activator.CreateInstance(src.GetType()) as FrameworkElement; }
        catch { dest = new Border(); }
        if (dest == null) return null;
        dest.Style = src.Style;
        var srcButton = src as Button;
        var destButton = dest as Button;
        if (srcButton != null && destButton != null && srcButton.Template != null)
            destButton.Template = srcButton.Template;
        var srcCombo = src as ComboBox;
        var destCombo = dest as ComboBox;
        if (srcCombo != null && destCombo != null && srcCombo.Template != null)
            destCombo.Template = srcCombo.Template;
        dest.Margin = src.Margin;
        dest.HorizontalAlignment = src.HorizontalAlignment;
        dest.VerticalAlignment = src.VerticalAlignment;
        dest.Opacity = src.Opacity;
        dest.Visibility = src.Visibility;
        dest.MinWidth = src.MinWidth;
        dest.MinHeight = src.MinHeight;
        if (!double.IsNaN(src.Width)) dest.Width = src.Width;
        if (!double.IsNaN(src.Height)) dest.Height = src.Height;
        foreach (string name in RmtCommonStyles.Properties)
        {
            if (RmtCommonStyles.IsColorProperty(name) && !HasPaintedBrush(src, name)) continue;
            CopyPreviewProperty(dest, src, name);
        }
        dest.SnapsToDevicePixels = src.SnapsToDevicePixels;
        var srcGrid = src as Grid;
        var destGrid = dest as Grid;
        if (srcGrid != null && destGrid != null)
        {
            foreach (ColumnDefinition column in srcGrid.ColumnDefinitions)
                destGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = column.Width, MinWidth = column.MinWidth, MaxWidth = column.MaxWidth });
            foreach (RowDefinition row in srcGrid.RowDefinitions)
                destGrid.RowDefinitions.Add(new RowDefinition { Height = row.Height, MinHeight = row.MinHeight, MaxHeight = row.MaxHeight });
        }
        var srcText = src as TextBlock;
        var destText = dest as TextBlock;
        if (srcText != null && destText != null)
        {
            destText.Text = srcText.Text;
            destText.TextWrapping = srcText.TextWrapping;
            destText.TextAlignment = srcText.TextAlignment;
            destText.FontSize = srcText.FontSize;
            destText.FontWeight = srcText.FontWeight;
            destText.Foreground = srcText.Foreground;
        }
        var srcBox = src as TextBox;
        var destBox = dest as TextBox;
        if (srcBox != null && destBox != null) destBox.Text = srcBox.Text;
        var srcImage = src as Image;
        var destImage = dest as Image;
        if (srcImage != null && destImage != null) destImage.Source = srcImage.Source;
        var srcContent = src as ContentControl;
        var destContent = dest as ContentControl;
        if (srcContent != null && destContent != null && !(src is ComboBox) && !(src is ListBox) && !(src is Window))
        {
            var nested = srcContent.Content as FrameworkElement;
            if (nested != null) destContent.Content = ClonePreviewElement(nested, depth + 1);
            else if (srcContent.Content is string) destContent.Content = srcContent.Content;
        }
        if (src is ComboBox || src is ListBox) return dest;
        var srcBorder = src as Border;
        var destBorder = dest as Border;
        if (srcBorder != null && destBorder != null)
        {
            destBorder.CornerRadius = srcBorder.CornerRadius;
            destBorder.Padding = srcBorder.Padding;
            destBorder.BorderThickness = srcBorder.BorderThickness;
            if (HasPaintedBrush(srcBorder, "Background")) destBorder.Background = srcBorder.Background;
            destBorder.BorderBrush = srcBorder.BorderBrush;
            var child = srcBorder.Child as FrameworkElement;
            if (child != null) destBorder.Child = ClonePreviewElement(child, depth + 1);
            return dest;
        }
        var srcView = src as Viewbox;
        var destView = dest as Viewbox;
        if (srcView != null && destView != null)
        {
            destView.Stretch = srcView.Stretch;
            destView.StretchDirection = srcView.StretchDirection;
            var child = srcView.Child as FrameworkElement;
            if (child != null) destView.Child = ClonePreviewElement(child, depth + 1);
            return dest;
        }
        var srcPanel = src as Panel;
        var destPanel = dest as Panel;
        if (srcPanel != null && destPanel != null)
        {
            if (HasPaintedBrush(srcPanel, "Background")) destPanel.Background = srcPanel.Background;
            foreach (UIElement child in srcPanel.Children)
            {
                var fe = child as FrameworkElement;
                if (fe == null) continue;
                var cloned = ClonePreviewElement(fe, depth + 1);
                if (cloned == null) continue;
                destPanel.Children.Add(cloned);
                CopyAttachedLayout(cloned, fe);
            }
        }
        return dest;
    }

    private FrameworkElement CloneWindowPreview(Window src, int depth)
    {
        var frame = new Border
        {
            BorderBrush = TryFindResource("ControlBorder") as Brush ?? Brushes.Gray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            SnapsToDevicePixels = true,
            Background = src.Background
        };
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(chromeButtonHeight) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var bar = new Grid { Background = TryFindResource("TitleBarColor") as Brush ?? Brushes.LightGray };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.Children.Add(new TextBlock
        {
            Text = src.Title ?? "",
            Foreground = TryFindResource("TitleBarForeground") as Brush ?? Brushes.Black,
            FontWeight = FontWeights.Bold,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(12, 0, 0, 0)
        });
        var btns = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        Grid.SetColumn(btns, 1);
        if (FindVisibleNamed(src, "BtnMinimize") != null) btns.Children.Add(PreviewChromeGlyph("\uE921"));
        if (FindVisibleNamed(src, "BtnMaximize") != null) btns.Children.Add(PreviewChromeGlyph("\uE922"));
        if (FindVisibleNamed(src, "BtnPin") != null) btns.Children.Add(PreviewChromeGlyph("\uE840"));
        if (FindVisibleNamed(src, "BtnWinClose") != null || FindVisibleNamed(src, "BtnClosePanel") != null || FindVisibleNamed(src, "BtnClose") != null)
            btns.Children.Add(PreviewChromeGlyph("\uE8BB"));
        bar.Children.Add(btns);
        var content = RmtCommonStyles.WindowBody(src) ?? (src.Content as FrameworkElement);
        var cloned = ClonePreviewElement(content, depth + 1);
        if (cloned == null) cloned = new Border { Background = TryFindResource("BgColor") as Brush ?? Brushes.White };
        Grid.SetRow(cloned, 1);
        grid.Children.Add(bar);
        grid.Children.Add(cloned);
        frame.Child = grid;
        double width = src.ActualWidth > 80 ? src.ActualWidth : (double.IsNaN(src.Width) ? 360 : src.Width);
        double height = src.ActualHeight > 80 ? src.ActualHeight : (double.IsNaN(src.Height) ? 220 : src.Height);
        frame.Width = width;
        frame.Height = height;
        return frame;
    }

    private static FrameworkElement FindNamed(Window window, string name)
    {
        return window == null ? null : window.FindName(name) as FrameworkElement;
    }

    private static FrameworkElement FindVisibleNamed(Window window, string name)
    {
        var element = FindNamed(window, name);
        return element != null && element.Visibility == Visibility.Visible ? element : null;
    }

    private static bool IsWindowChromeElement(FrameworkElement element)
    {
        if (element == null || string.IsNullOrEmpty(element.Name)) return false;
        string name = element.Name;
        return name == "BtnMinimize" || name == "BtnMaximize" || name == "BtnPin"
            || name == "BtnWinClose" || name == "BtnClosePanel" || name == "BtnClose"
            || name == "BtnWinMin" || name == "BtnWinMax" || name == "BtnWinPin"
            || name == "BtnMaximizeTxt" || name == "DragArea";
    }

    private static void CopyAttachedLayout(FrameworkElement dest, FrameworkElement src)
    {
        Grid.SetRow(dest, Grid.GetRow(src));
        Grid.SetColumn(dest, Grid.GetColumn(src));
        Grid.SetRowSpan(dest, Grid.GetRowSpan(src));
        Grid.SetColumnSpan(dest, Grid.GetColumnSpan(src));
        DockPanel.SetDock(dest, DockPanel.GetDock(src));
        if (!double.IsNaN(Canvas.GetLeft(src))) Canvas.SetLeft(dest, Canvas.GetLeft(src));
        if (!double.IsNaN(Canvas.GetTop(src))) Canvas.SetTop(dest, Canvas.GetTop(src));
    }

    private double SourceContentScale()
    {
        var vb = source == null ? null : source.Content as Viewbox;
        if (vb == null) return 1;
        var child = vb.Child as FrameworkElement;
        if (child == null) return 1;
        double design = child.ActualWidth > 1 ? child.ActualWidth : (double.IsNaN(child.Width) ? 0 : child.Width);
        if (design <= 1 || vb.ActualWidth <= 1) return 1;
        return vb.ActualWidth / design;
    }

    private void ApplyPreviewValue(FrameworkElement element, string name, string value)
    {
        var dp = RmtCommonStyles.Property(element, name);
        if (dp == null || string.IsNullOrEmpty(value)) return;
        if (RmtCommonStyles.IsColorProperty(name) && RmtCommonStyles.IsThemeColor(value))
            element.SetResourceReference(dp, RmtCommonStyles.ThemeColorKey(value));
        else if (name == "RelativeFontSize")
            element.SetValue(dp, RmtCommonStyles.ThemeFontSize(source) + (double)RmtCommonStyles.ConvertValue(typeof(double), value));
        else if (value.Equals("Auto", StringComparison.OrdinalIgnoreCase) && (name == "Width" || name == "Height"))
            element.SetValue(dp, double.NaN);
        else if ((name == "MaxWidth" || name == "MaxHeight") && value == "无限")
            element.SetValue(dp, double.PositiveInfinity);
        else
            element.SetValue(dp, RmtCommonStyles.ConvertValue(dp.PropertyType, value));
        if (name == "CornerRadius") RmtCommonStyles.ApplyCorners(element as Control);
        if (name == "MaxDropDownHeight") RmtCommonStyles.ApplyComboDropDown(element as ComboBox);
    }

    private static void CopyPreviewProperty(FrameworkElement dest, FrameworkElement src, string name)
    {
        var dp = RmtCommonStyles.Property(dest, name);
        if (dp == null) return;
        if (name == "CornerRadius" && src is Control && src.ReadLocalValue(dp) == DependencyProperty.UnsetValue)
            return;
        object local = src.ReadLocalValue(dp);
        if (local != null && local.GetType().Name == "ResourceReferenceExpression")
        {
            var key = local.GetType().GetProperty("ResourceKey", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic);
            if (key != null)
            {
                dest.SetResourceReference(dp, key.GetValue(local, null));
                return;
            }
        }
        dest.SetValue(dp, src.GetValue(dp));
    }

    private static string PreviewTextFor(FrameworkElement element)
    {
        if (element is CheckBox) return "启用选项";
        if (element is RadioButton) return "单选项";
        if (element is Button) return "按钮";
        if (element is GroupBox) return "分组标题";
        return "控件内容";
    }
    private void Field(string name, string value, string current, bool bound)
    {
        if (propertyRow == null || propertyPair == 3)
        {
            propertyRow = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            for (int i = 0; i < 3; i++)
            {
                propertyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
                propertyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            }
            fields.Children.Add(propertyRow); propertyPair = 0;
        }
        int column = propertyPair++ * 2;
        var label = new TextBlock { Text = propertyLabels.ContainsKey(name) ? propertyLabels[name] : name, ToolTip = name, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0) };
        Grid.SetColumn(label, column); propertyRow.Children.Add(label);
        if (RmtCommonStyles.IsColorProperty(name))
        {
            Brush liveBrush = null;
            if (sample != null)
            {
                var liveDp = RmtCommonStyles.Property(sample, name);
                if (liveDp != null)
                    liveBrush = ResolveDisplayedValue(sample, name, liveDp) as Brush;
                if (!HasPaintedBrush(sample, name) && name != "HoverBackground" && name != "PressedBackground")
                    liveBrush = null;
            }
            string preferredKey = name == "HoverBackground" ? "ActionHoverBg" : name == "PressedBackground" ? PressedResourceKey("ActionPressBg") : "";
            var combo = ThemeColorPicker(value, current, bound, liveBrush, preferredKey); combo.Margin = new Thickness(0, 0, PropertyColumnGap, 0);
            combo.SelectionChanged += delegate { if (rendering || !interactionReady) return; colorTouched.Add(name); Commit(false); };
            Grid.SetColumn(combo, column + 1); propertyRow.Children.Add(combo); colorInputs[name] = combo;
        }
        else if (IsOptionProperty(name))
        {
            var combo = OptionPicker(name, value, current, bound); combo.Margin = new Thickness(0, 0, PropertyColumnGap, 0);
            combo.SelectionChanged += delegate { if (rendering || !interactionReady) return; optionTouched.Add(name); Commit(false); if (name == "SizeMode") Render(); };
            Grid.SetColumn(combo, column + 1); propertyRow.Children.Add(combo); optionInputs[name] = combo;
        }
        else if (name == "Opacity" || name == "RelativeFontSize")
        {
            double number;
            if (!double.TryParse(string.IsNullOrEmpty(value) ? current : value, NumberStyles.Float, CultureInfo.InvariantCulture, out number)) number = name == "Opacity" ? 1 : 0;
            var panel = new Grid { MinHeight = 28, Margin = new Thickness(0, 0, PropertyColumnGap, 0) };
            panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            var slider = new Slider { Minimum = name == "Opacity" ? 0 : -8, Maximum = name == "Opacity" ? 1 : 8, Value = number, IsEnabled = !bound, VerticalAlignment = VerticalAlignment.Center, Tag = name };
            var display = new TextBlock { Text = name == "Opacity" ? number.ToString("0.00", CultureInfo.InvariantCulture) : (number >= 0 ? "+" : "") + number.ToString("0", CultureInfo.InvariantCulture), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            slider.ValueChanged += delegate { display.Text = name == "Opacity" ? slider.Value.ToString("0.00", CultureInfo.InvariantCulture) : (slider.Value >= 0 ? "+" : "") + slider.Value.ToString("0", CultureInfo.InvariantCulture); if (rendering || !interactionReady) return; sliderTouched.Add(name); Commit(false); };
            panel.Children.Add(slider); Grid.SetColumn(display, 1); panel.Children.Add(display);
            Grid.SetColumn(panel, column + 1); propertyRow.Children.Add(panel); sliderInputs[name] = slider;
        }
        else if (IsPresetProperty(name))
        {
            var combo = PresetPicker(name, string.IsNullOrEmpty(value) ? current : value, bound);
            combo.Tag = string.IsNullOrEmpty(value) ? "inherit" : "override";
            combo.Margin = new Thickness(0, 0, PropertyColumnGap, 0);
            combo.SelectionChanged += delegate { if (rendering || !interactionReady) return; presetTouched.Add(name); combo.Tag = "override"; if (!combo.IsDropDownOpen) Commit(false); };
            combo.AddHandler(TextBox.TextChangedEvent, new TextChangedEventHandler(delegate { if (rendering || !interactionReady) return; presetTouched.Add(name); combo.Tag = "override"; Commit(false); }));
            combo.DropDownClosed += delegate { if (rendering || !interactionReady) return; Commit(false); };
            combo.LostKeyboardFocus += delegate { if (rendering || !interactionReady) return; if (!combo.IsDropDownOpen) Commit(false); };
            Grid.SetColumn(combo, column + 1); propertyRow.Children.Add(combo); presetInputs[name] = combo;
        }
        else if (name == "MaxWidth" || name == "MaxHeight")
        {
            string shown = string.IsNullOrEmpty(value) ? current : value;
            if (shown == "Infinity" || shown == "∞") shown = "无限";
            var combo = new ComboBox { IsEditable = true, IsReadOnly = bound, MinHeight = 28, Margin = new Thickness(0, 0, PropertyColumnGap, 0), Text = shown, ToolTip = "可直接输入数值；最大宽高可选择“无限”。" };
            combo.Items.Add("无限");
            combo.SelectionChanged += delegate { if (rendering || !interactionReady) return; dimensionTouched.Add(name); if ((combo.SelectedItem as string) == "无限") combo.Text = "无限"; Commit(false); };
            combo.AddHandler(TextBox.TextChangedEvent, new TextChangedEventHandler(delegate { if (rendering || !interactionReady) return; dimensionTouched.Add(name); Commit(false); }));
            combo.LostKeyboardFocus += delegate { if (rendering || !interactionReady) return; Commit(false); };
            Grid.SetColumn(combo, column + 1); propertyRow.Children.Add(combo); dimensionInputs[name] = combo;
            if (!bound) EnableNumberDrag(label, () => combo.Text, text => { combo.Text = text; dimensionTouched.Add(name); });
        }
        else
        {
            bool inherited = string.IsNullOrEmpty(value);
            bool compactPad = name == "CornerRadius" || name == "BorderThickness" || name == "Margin" || name == "Padding"
                || name == "Width" || name == "Height" || name == "MinWidth" || name == "MinHeight"
                || name == "MaxDropDownHeight" || name == "MaxLength" || name == "Spacing";
            var box = new TextBox { Text = inherited ? current : value, IsReadOnly = bound, Padding = compactPad ? new Thickness(2, 0, 2, 0) : new Thickness(5), Height = 28, MinHeight = 28, VerticalContentAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, PropertyColumnGap, 0), ToolTip = inherited ? "显示当前继承值；修改后立即覆盖并应用。" : "当前覆盖值", Tag = inherited ? "inherit" : "override" };
            if (inherited) box.Foreground = Brushes.SlateGray;
            box.TextChanged += delegate { if (rendering || !interactionReady) return; if (!box.IsReadOnly) { box.Tag = "override"; box.Foreground = Brushes.Black; Commit(false); } };
            Grid.SetColumn(box, column + 1); propertyRow.Children.Add(box); inputs[name] = box;
            if (!bound && (name == "Width" || name == "Height" || name == "MinWidth" || name == "MinHeight" || name == "MaxDropDownHeight" || name == "MaxLength" || name == "Spacing"))
                EnableNumberDrag(label, box);
        }
    }

    private static bool IsPresetProperty(string name)
    {
        return name == "CornerRadius" || name == "BorderThickness" || name == "Margin" || name == "Padding";
    }

    private ComboBox PresetPicker(string name, string current, bool bound)
    {
        var options = name == "Padding"
            ? new[] { "0,0,0,0", "1,0,1,0", "2,0,2,0", "3,0,3,0", "4,0,4,0" }
            : name == "BorderThickness"
            ? new[] { "0,0,0,0", "1,1,1,1", "1.5,1.5,1.5,1.5", "2,2,2,2", "2.5,2.5,2.5,2.5", "3,3,3,3", "4,4,4,4" }
            : new[] { "0,0,0,0", "1,1,1,1", "2,2,2,2", "3,3,3,3", "4,4,4,4" };
        string shown = string.IsNullOrEmpty(current) ? options[0] : NormalizeThickness(current);
        var combo = new ComboBox { IsEditable = true, IsEnabled = !bound, MinHeight = 28, MaxDropDownHeight = 240, ToolTip = "选择常用值，也可直接输入。" };
        foreach (string option in options) combo.Items.Add(option);
        if (!combo.Items.Contains(shown)) combo.Items.Insert(0, shown);
        combo.SelectedItem = shown;
        combo.Text = shown;
        return combo;
    }

    private static string NormalizeThickness(string value)
    {
        if (string.IsNullOrEmpty(value)) return "0,0,0,0";
        try
        {
            var t = (Thickness)RmtCommonStyles.ConvertValue(typeof(Thickness), value);
            return t.Left.ToString(CultureInfo.InvariantCulture) + "," + t.Top.ToString(CultureInfo.InvariantCulture) + "," + t.Right.ToString(CultureInfo.InvariantCulture) + "," + t.Bottom.ToString(CultureInfo.InvariantCulture);
        }
        catch { return value.Replace(" ", ""); }
    }

    private static string ComboText(ComboBox combo)
    {
        if (combo == null) return "";
        if (combo.IsEditable && !string.IsNullOrWhiteSpace(combo.Text)) return combo.Text.Trim();
        if (combo.SelectedItem is string) return (string)combo.SelectedItem;
        var item = combo.SelectedItem as ComboBoxItem;
        if (item != null && item.Tag is string) return (string)item.Tag;
        return (combo.Text ?? "").Trim();
    }

    private string ComboTextOrDefault(string name, string fallback)
    {
        ComboBox preset;
        if (presetInputs.TryGetValue(name, out preset))
        {
            string text = ComboText(preset);
            if (!string.IsNullOrWhiteSpace(text)) return text;
        }
        TextBox box;
        if (inputs.TryGetValue(name, out box) && !string.IsNullOrWhiteSpace(box.Text)) return box.Text.Trim();
        return fallback ?? "";
    }

    private static bool IsOptionProperty(string name)
    {
        return name == "FontWeight" || name == "FontStyle" || name == "FontStretch"
            || name == "HorizontalAlignment" || name == "VerticalAlignment"
            || name == "HorizontalContentAlignment" || name == "VerticalContentAlignment"
            || name == "FlowDirection" || name == "Visibility" || name == "TextAlignment"
            || name == "TextWrapping" || name == "TextTrimming" || name == "Orientation"
            || name == "IsEnabled" || name == "IsHitTestVisible" || name == "Focusable"
            || name == "UseLayoutRounding" || name == "SnapsToDevicePixels" || name == "IsReadOnly"
            || name == "AcceptsReturn" || name == "AcceptsTab" || name == "IsEditable" || name == "SizeMode"
            || name == "Stretch" || name == "StretchDirection"
            || name == "VerticalScrollBarVisibility" || name == "HorizontalScrollBarVisibility"
            || name == "ChildAlignment";
    }

    private ComboBox OptionPicker(string name, string value, string current, bool bound)
    {
        var combo = new ComboBox { IsEnabled = !bound, MinHeight = 28, Padding = new Thickness(4), ToolTip = "选择后会立即应用。" };
        string[] options;
        if (name == "FontWeight") options = new[] { "Thin", "ExtraLight", "Light", "Normal", "Medium", "SemiBold", "Bold", "ExtraBold", "Black" };
        else if (name == "FontStyle") options = new[] { "Normal", "Italic", "Oblique" };
        else if (name == "FontStretch") options = new[] { "UltraCondensed", "ExtraCondensed", "Condensed", "SemiCondensed", "Normal", "SemiExpanded", "Expanded", "ExtraExpanded", "UltraExpanded" };
        else if (name == "VerticalAlignment" || name == "VerticalContentAlignment") options = new[] { "Top", "Center", "Bottom", "Stretch" };
        else if (name == "FlowDirection") options = new[] { "LeftToRight", "RightToLeft" };
        else if (name == "Visibility") options = new[] { "Visible", "Hidden", "Collapsed" };
        else if (name == "TextAlignment") options = new[] { "Left", "Center", "Right", "Justify" };
        else if (name == "TextWrapping") options = new[] { "NoWrap", "Wrap", "WrapWithOverflow" };
        else if (name == "TextTrimming") options = new[] { "None", "CharacterEllipsis", "WordEllipsis" };
        else if (name == "Orientation") options = new[] { "Horizontal", "Vertical" };
        else if (name == "ChildAlignment") options = new[] { "Left", "Center", "Right" };
        else if (name == "Stretch") options = new[] { "None", "Fill", "Uniform", "UniformToFill" };
        else if (name == "StretchDirection") options = new[] { "UpOnly", "DownOnly", "Both" };
        else if (name == "VerticalScrollBarVisibility" || name == "HorizontalScrollBarVisibility") options = new[] { "Disabled", "Auto", "Hidden", "Visible" };
        else if (name.StartsWith("Is") || name == "Focusable" || name == "UseLayoutRounding" || name == "SnapsToDevicePixels" || name == "AcceptsReturn" || name == "AcceptsTab") options = new[] { "True", "False" };
        else if (name == "SizeMode") options = new[] { "固定宽高", "自适应宽度", "自适应高度", "自适应宽高" };
        else options = new[] { "Left", "Center", "Right", "Stretch" };
        bool concreteOption = name == "SizeMode" || name == "FontWeight"
            || name == "HorizontalContentAlignment" || name == "VerticalContentAlignment"
            || name == "HorizontalAlignment" || name == "VerticalAlignment"
            || name == "TextAlignment" || name == "TextWrapping" || name == "TextTrimming"
            || name == "Orientation" || name == "ChildAlignment" || name == "Stretch" || name == "StretchDirection"
            || name == "IsReadOnly" || name == "AcceptsReturn"
            || name == "VerticalScrollBarVisibility" || name == "HorizontalScrollBarVisibility";
        bool inherited = string.IsNullOrEmpty(value) && !concreteOption;
        if (inherited)
        {
            var inherit = new ComboBoxItem { Content = "继承当前值（" + current + "）", Tag = "" };
            combo.Items.Add(inherit);
            combo.SelectedItem = inherit;
        }
        string pick = string.IsNullOrEmpty(value) ? current : value;
        foreach (string option in options)
        {
            string display = option;
            if (name == "ChildAlignment")
            {
                if (option == "Left") display = "左对齐";
                else if (option == "Center") display = "居中";
                else if (option == "Right") display = "右对齐";
            }
            var item = new ComboBoxItem { Content = display, Tag = option };
            combo.Items.Add(item);
            if (!inherited && string.Equals(option, pick, StringComparison.OrdinalIgnoreCase)) combo.SelectedItem = item;
        }
        if (combo.SelectedIndex < 0) combo.SelectedIndex = 0;
        return combo;
    }

    private ComboBox ThemeColorPicker(string value, string current, bool bound, Brush liveBrush, string preferredKey)
    {
        var combo = new ComboBox { IsEnabled = !bound, MinHeight = 28, Padding = new Thickness(4), ToolTip = "只能选择主题颜色序列；切换主题时会自动同步。" };
        string wanted = RmtCommonStyles.IsThemeColor(value) ? RmtCommonStyles.ThemeColorKey(value) : "";
        bool hasConfiguredTheme = !string.IsNullOrEmpty(wanted);
        var liveSolid = liveBrush as SolidColorBrush;
        if (liveSolid == null || liveSolid.Color.A == 0)
            liveSolid = ParseSolid(string.IsNullOrEmpty(value) ? current : value);
        for (int i = 0; i < RmtCommonStyles.ThemePaletteResources.Length; i++)
        {
            string key = RmtCommonStyles.ThemePaletteResources[i];
            var brush = TryFindResource(key) as Brush ?? Brushes.Transparent;
            string hex = RmtCommonStyles.Text(brush);
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new Border { Width = 18, Height = 18, Background = brush, BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 7, 0) });
            row.Children.Add(new TextBlock { Text = "颜色" + (i + 1) + "   " + hex, VerticalAlignment = VerticalAlignment.Center });
            var item = new ComboBoxItem { Content = row, Tag = "$Theme:" + key };
            combo.Items.Add(item);
            // Existing literal values are migrated to their matching theme resource on the next save.
            string displayed = string.IsNullOrEmpty(value) ? current : value;
            var themeSolid = brush as SolidColorBrush;
            bool sameLive = liveSolid != null && themeSolid != null && liveSolid.Color == themeSolid.Color && liveSolid.Color.A > 0;
            // A persisted theme resource is authoritative. The live brush can still reflect
            // the previous template while the editor is switching selections, so allowing it
            // to match as well can overwrite the saved selection later in this loop.
            if (key == wanted || (!hasConfiguredTheme && (sameLive || (liveSolid != null && ColorTextEquals(hex, displayed)))))
                combo.SelectedItem = item;
        }
        if (combo.SelectedIndex < 0 && liveSolid != null && liveSolid.Color.A > 0)
            combo.SelectedIndex = ClosestPaletteIndex(liveSolid.Color);
        if (combo.SelectedIndex < 0 && !string.IsNullOrEmpty(preferredKey))
        {
            for (int i = 0; i < combo.Items.Count; i++)
            {
                var item = combo.Items[i] as ComboBoxItem;
                if (item != null && RmtCommonStyles.ThemeColorKey(item.Tag as string ?? "") == preferredKey)
                {
                    combo.SelectedIndex = i;
                    break;
                }
            }
            if (combo.SelectedIndex < 0)
            {
                var preferred = TryFindResource(preferredKey) as SolidColorBrush;
                if (preferred != null && preferred.Color.A > 0)
                    combo.SelectedIndex = ClosestPaletteIndex(preferred.Color);
            }
        }
        if (combo.SelectedIndex < 0 && !string.IsNullOrEmpty(value)) combo.SelectedIndex = 0;
        return combo;
    }

    private int ClosestPaletteIndex(Color color)
    {
        int best = -1;
        double bestScore = double.MaxValue;
        for (int i = 0; i < RmtCommonStyles.ThemePaletteResources.Length; i++)
        {
            var themeSolid = TryFindResource(RmtCommonStyles.ThemePaletteResources[i]) as SolidColorBrush;
            if (themeSolid == null) continue;
            double score = ColorDistance(color, themeSolid.Color);
            if (score < bestScore) { bestScore = score; best = i; }
        }
        return best;
    }

    private static SolidColorBrush ParseSolid(string value)
    {
        if (string.IsNullOrEmpty(value)) return null;
        try { return RmtCommonStyles.ConvertValue(typeof(Brush), value) as SolidColorBrush; }
        catch { return null; }
    }

    private static bool ColorTextEquals(string left, string right)
    {
        if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right)) return false;
        if (string.Equals(left, right, StringComparison.OrdinalIgnoreCase)) return true;
        try
        {
            var a = RmtCommonStyles.ConvertValue(typeof(Brush), left) as SolidColorBrush;
            var b = RmtCommonStyles.ConvertValue(typeof(Brush), right) as SolidColorBrush;
            return a != null && b != null && a.Color == b.Color && a.Color.A > 0;
        }
        catch { return false; }
    }

    private bool CommitWindow(bool rerender)
    {
        if (applying) return false;
        applying = true;
        Dictionary<string, string> saved;
        TryEditingValues(out saved);
        var next = saved == null ? new Dictionary<string, string>() : new Dictionary<string, string>(saved);
        bool locatedWindow = LocatingSelectedWindow();
        if (locatedWindow)
        {
            // Dimensions for a reflected Window are instance layout values.  Start from the
            // live window instead of any legacy shared Width/Height entries, then add only the
            // fields the user actually changed below.
            next.Remove("Width"); next.Remove("Height"); next.Remove("MinWidth"); next.Remove("MinHeight");
            next.Remove("MaxWidth"); next.Remove("MaxHeight"); next.Remove("SizeMode");
        }
        try
        {
            foreach (var check in chromeChecks)
                next[check.Key] = check.Value.IsChecked == true ? "True" : "False";
            foreach (var input in inputs)
            {
                if (input.Value.IsReadOnly) continue;
                if ((input.Value.Tag as string) == "inherit" || string.IsNullOrWhiteSpace(input.Value.Text)) { next.Remove(input.Key); continue; }
                string value = input.Value.Text.Trim();
                Type type = input.Key == "CornerRadius" ? typeof(CornerRadius) : input.Key == "Padding" || input.Key == "Margin" ? typeof(Thickness) : typeof(double);
                if (input.Key == "CornerRadius" || input.Key == "Padding" || input.Key == "Margin")
                    RmtCommonStyles.ConvertValue(type, value);
                else if (input.Key == "Width" || input.Key == "Height" || input.Key == "MinWidth" || input.Key == "MinHeight")
                {
                    if (value.Equals("Auto", StringComparison.OrdinalIgnoreCase)) { next[input.Key] = "Auto"; continue; }
                    double number;
                    if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) || number < 0)
                        throw new ArgumentException(input.Key + " 请输入非负数。");
                }
                next[input.Key] = value;
            }
            foreach (var input in dimensionInputs)
            {
                if (!dimensionTouched.Contains(input.Key)) continue;
                string value = input.Value.Text.Trim();
                if (string.IsNullOrEmpty(value)) { next.Remove(input.Key); continue; }
                if (value == "无限") value = "Infinity";
                next[input.Key] = value;
            }
            foreach (var input in presetInputs)
            {
                if (!input.Value.IsEnabled || (input.Value.Tag as string) == "inherit" && !presetTouched.Contains(input.Key)) continue;
                if (!presetTouched.Contains(input.Key) && (input.Value.Tag as string) == "inherit") { next.Remove(input.Key); continue; }
                string value = ComboText(input.Value);
                if (string.IsNullOrWhiteSpace(value) || (input.Value.Tag as string) == "inherit") { next.Remove(input.Key); continue; }
                if (input.Key == "CornerRadius") RmtCommonStyles.ConvertValue(typeof(CornerRadius), value);
                else RmtCommonStyles.ConvertValue(typeof(Thickness), value);
                next[input.Key] = value;
            }
            foreach (var input in colorInputs)
            {
                if (!input.Value.IsEnabled || !colorTouched.Contains(input.Key)) continue;
                var item = input.Value.SelectedItem as ComboBoxItem;
                string value = item == null ? "" : (item.Tag as string ?? "");
                if (string.IsNullOrEmpty(value)) next.Remove(input.Key); else next[input.Key] = value;
            }
            ComboBox modeInput;
            if (optionInputs.TryGetValue("SizeMode", out modeInput) && modeInput.SelectedItem is ComboBoxItem)
            {
                string mode = ((ComboBoxItem)modeInput.SelectedItem).Tag as string ?? "固定宽高";
                next["SizeMode"] = mode;
                if (mode == "自适应宽高") { next["Width"] = "Auto"; next["Height"] = "Auto"; }
                else if (mode == "自适应宽度") { next["Width"] = "Auto"; next.Remove("MinHeight"); next.Remove("MaxHeight"); }
                else if (mode == "自适应高度") { next["Height"] = "Auto"; next.Remove("MinWidth"); next.Remove("MaxWidth"); }
                else
                {
                    string size;
                    if (next.TryGetValue("Width", out size) && size == "Auto") next.Remove("Width");
                    if (next.TryGetValue("Height", out size) && size == "Auto") next.Remove("Height");
                    next.Remove("MinWidth"); next.Remove("MinHeight"); next.Remove("MaxWidth"); next.Remove("MaxHeight");
                }
            }
            if (locatedWindow)
            {
                // Width/Height are edited in the reload-property section only.  Apply those
                // values to the concrete Window before capturing its anchor layout, then strip
                // all size keys from the shared Window style so another window cannot inherit
                // this instance-specific resize.
                var concreteWindow = Inspected() as Window;
                string widthText, heightText;
                if (concreteWindow != null)
                {
                    // Capture before applying the reload dimensions so Reset can restore the
                    // exact pre-edit window size as well as its position.
                    CapturePosition(concreteWindow);
                    if (next.TryGetValue("Width", out widthText)) ApplyWindowDimension(concreteWindow, widthText, true);
                    if (next.TryGetValue("Height", out heightText)) ApplyWindowDimension(concreteWindow, heightText, false);
                    concreteWindow.UpdateLayout();
                }
                if (!ApplyInspectedPosition(false)) return false;
                // A concrete window's dimensions belong to its Layout entry.  Never write
                // them back to the shared Window style while editing through control locate.
                next.Remove("Width"); next.Remove("Height"); next.Remove("MinWidth"); next.Remove("MinHeight");
                next.Remove("MaxWidth"); next.Remove("MaxHeight"); next.Remove("SizeMode");
            }
            if (!StoreEdits(next, rerender)) return false;
            preview.Children.Clear();
            if (LiveInspecting()) ShowHierarchyPreview(Inspected());
            else ShowWindowPreview();
            status.Text = rerender ? "已应用到正式界面。" : "";
            return true;
        }
        catch (Exception ex) { status.Text = "未应用：" + ex.Message; return false; }
        finally { applying = false; }
    }

    // Retained for the test hook and explicit final application path.
    private bool Apply() { return Commit(true); }

    private bool Commit(bool rerender)
    {
        if (rendering || applying || selected == null || sample == null) return false;
        if (notices.ContainsKey(selected)) { status.Text = "此项为特殊界面的来源登记，未接入通用 WPF 属性编辑。"; return false; }
        if (RmtCommonStyles.IsWindowKey(selected)) return CommitWindow(rerender);
        applying = true;
        Dictionary<string, string> saved;
        TryEditingValues(out saved);
        var next = saved == null ? new Dictionary<string, string>() : new Dictionary<string, string>(saved);
        try
        {
            foreach (var input in inputs)
            {
                if (input.Value.IsReadOnly) continue;
                if ((input.Value.Tag as string) == "inherit" || string.IsNullOrWhiteSpace(input.Value.Text)) { next.Remove(input.Key); continue; }
                string value = input.Value.Text.Trim();
                Type type = input.Key == "Color" ? typeof(Brush) : RmtCommonStyles.Property(sample, input.Key).PropertyType;
                var converted = RmtCommonStyles.ConvertValue(type, value);
                if (input.Key == "Color" && !(converted is SolidColorBrush)) throw new ArgumentException("颜色须为纯色。");
                if (sample != null && input.Key != "Color")
                {
                    var dp = RmtCommonStyles.Property(sample, input.Key);
                    if (!dp.IsValidValue(converted)) throw new ArgumentException(input.Key + " 的值超出允许范围。");
                }
                next[input.Key] = value;
            }
            foreach (var input in sliderInputs)
                if (sliderTouched.Contains(input.Key)) next[input.Key] = input.Key == "Opacity" ? input.Value.Value.ToString("0.00", CultureInfo.InvariantCulture) : input.Value.Value.ToString("0", CultureInfo.InvariantCulture);
            foreach (var input in dimensionInputs)
            {
                if (!dimensionTouched.Contains(input.Key)) continue;
                string value = input.Value.Text.Trim();
                if (string.IsNullOrEmpty(value)) { next.Remove(input.Key); continue; }
                if (value == "无限") value = "Infinity";
                double number;
                if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) || number < 0)
                    throw new ArgumentException(input.Key + " 请输入非负数或选择无限。");
                next[input.Key] = value;
            }
            foreach (var input in optionInputs)
            {
                if (input.Key == "SizeMode") continue;
                if (!optionTouched.Contains(input.Key)) continue;
                var item = input.Value.SelectedItem as ComboBoxItem;
                string value = item == null ? "" : (item.Tag as string ?? "");
                if (string.IsNullOrEmpty(value)) next.Remove(input.Key); else next[input.Key] = value;
            }
            foreach (var input in presetInputs)
            {
                if (!input.Value.IsEnabled || !presetTouched.Contains(input.Key)) continue;
                string value = ComboText(input.Value);
                if (string.IsNullOrWhiteSpace(value)) { next.Remove(input.Key); continue; }
                var dp = RmtCommonStyles.Property(sample, input.Key);
                if (dp != null) RmtCommonStyles.ConvertValue(dp.PropertyType, value);
                next[input.Key] = value;
            }
            foreach (var input in colorInputs)
            {
                if (!input.Value.IsEnabled || !colorTouched.Contains(input.Key)) continue;
                var item = input.Value.SelectedItem as ComboBoxItem;
                string value = item == null ? "" : (item.Tag as string ?? "");
                if (string.IsNullOrEmpty(value)) next.Remove(input.Key); else next[input.Key] = value;
            }
            string mode = "固定宽高";
            ComboBox modeInput;
            if (optionInputs.TryGetValue("SizeMode", out modeInput) && modeInput.SelectedItem is ComboBoxItem)
                mode = ((ComboBoxItem)modeInput.SelectedItem).Tag as string ?? mode;
            next["SizeMode"] = mode;
            if (mode == "自适应宽高")
            {
                next["Width"] = "Auto"; next["Height"] = "Auto";
            }
            else if (mode == "自适应宽度")
            {
                next["Width"] = "Auto"; next.Remove("MinHeight"); next.Remove("MaxHeight");
            }
            else if (mode == "自适应高度")
            {
                next["Height"] = "Auto"; next.Remove("MinWidth"); next.Remove("MaxWidth");
            }
            else
            {
                string size;
                if (next.TryGetValue("Width", out size) && size == "Auto") next.Remove("Width");
                if (next.TryGetValue("Height", out size) && size == "Auto") next.Remove("Height");
                next.Remove("MinWidth"); next.Remove("MinHeight"); next.Remove("MaxWidth"); next.Remove("MaxHeight");
            }
            if (!StoreEdits(next, rerender)) return false;
            preview.Children.Clear();
            if (LiveInspecting()) ShowHierarchyPreview(Inspected());
            else ShowPreview(sample);
            status.Text = rerender ? "已应用到正式界面。" : ""; return true;
        }
        catch (Exception ex) { status.Text = "未应用：" + ex.Message; return false; }
        finally { applying = false; }
    }
}

internal sealed class RmtControlTreeWindow : Window
{
    private readonly RmtStyleEditor editor;
    private readonly TreeView tree = new TreeView();

    internal RmtControlTreeWindow(RmtStyleEditor owner)
    {
        editor = owner;
        Owner = owner;
        Title = "GM-UI · 控件层级";
        Width = 720;
        Height = 780;
        MinWidth = 380;
        MinHeight = 360;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        FontFamily = owner.FontFamily;
        FontSize = owner.FontSize;
        RmtStyleEditor.CopyResourceSnapshot(Resources, owner.Resources);
        var root = new DockPanel { Margin = new Thickness(12) };
        var header = new TextBlock { Text = "界面控件层级", FontWeight = FontWeights.Bold, FontSize = owner.FontSize + 1, Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        var refresh = new Button { Content = "刷新层级", Padding = new Thickness(12, 6, 12, 6), Margin = new Thickness(0, 0, 8, 0) };
        var locate = new Button { Content = "定位并调整", Padding = new Thickness(12, 6, 12, 6), IsDefault = true };
        refresh.Click += delegate { RefreshTree(); };
        locate.Click += delegate { AcceptSelected(); };
        actions.Children.Add(refresh);
        actions.Children.Add(locate);
        DockPanel.SetDock(actions, Dock.Bottom);
        root.Children.Add(actions);
        tree.SelectedItemChanged += delegate
        {
            var element = SelectedElement();
            editor.PreviewHierarchyTarget(element);
        };
        tree.MouseDoubleClick += delegate(object sender, MouseButtonEventArgs args)
        {
            if (SelectedElement() != null) { AcceptSelected(); args.Handled = true; }
        };
        root.Children.Add(tree);
        Content = root;
        Loaded += delegate { RefreshTree(); };
        KeyDown += delegate(object sender, KeyEventArgs args) { if (args.Key == Key.Escape) Close(); };
    }

    private FrameworkElement SelectedElement()
    {
        var item = tree.SelectedItem as TreeViewItem;
        var weak = item == null ? null : item.Tag as WeakReference;
        return weak == null ? null : weak.Target as FrameworkElement;
    }

    private void AcceptSelected()
    {
        var element = SelectedElement();
        if (element != null) editor.AcceptHierarchyTarget(element);
    }

    private void RefreshTree()
    {
        tree.Items.Clear();
        if (Application.Current == null) return;
        foreach (Window window in Application.Current.Windows.Cast<Window>().ToArray())
        {
            if (window == null || window is RmtStyleEditor || window is RmtControlTreeWindow) continue;
            var root = MakeNode(window);
            root.IsExpanded = true;
            AddChildren(root, window, new HashSet<DependencyObject>());
            tree.Items.Add(root);
        }
    }

    private static void AddChildren(TreeViewItem parentItem, DependencyObject parent, HashSet<DependencyObject> visited)
    {
        if (parent == null || !visited.Add(parent)) return;
        var children = LogicalTreeHelper.GetChildren(parent).OfType<DependencyObject>().ToList();
        if (children.Count == 0 && parent is Visual)
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++) children.Add(VisualTreeHelper.GetChild(parent, i));
        foreach (DependencyObject child in children)
        {
            var element = child as FrameworkElement;
            if (element == null) { AddChildren(parentItem, child, visited); continue; }
            if (element.TemplatedParent is Control && !(element.TemplatedParent is ContentPresenter)) continue;
            if (element is ComboBoxItem || element is ListBoxItem || element is MenuItem) continue;
            var item = MakeNode(element);
            parentItem.Items.Add(item);
            if (element is ComboBox || element is ListBox) continue;
            AddChildren(item, child, visited);
        }
    }

    private static TreeViewItem MakeNode(FrameworkElement element)
    {
        var item = new TreeViewItem { Header = ElementLabel(element), Tag = new WeakReference(element) };
        var menu = new ContextMenu();
        var expand = new MenuItem { Header = "展开全部" };
        var collapse = new MenuItem { Header = "收缩全部" };
        expand.Click += delegate { SetExpanded(item, true); };
        collapse.Click += delegate { SetExpanded(item, false); };
        menu.Items.Add(expand);
        menu.Items.Add(collapse);
        item.ContextMenu = menu;
        return item;
    }

    private static void SetExpanded(TreeViewItem item, bool expanded)
    {
        if (item == null) return;
        item.IsExpanded = expanded;
        foreach (TreeViewItem child in item.Items.OfType<TreeViewItem>()) SetExpanded(child, expanded);
    }

    private static string ElementLabel(FrameworkElement element)
    {
        string label = element.GetType().Name;
        var window = element as Window;
        if (window != null && !string.IsNullOrEmpty(window.Title))
            label += "（" + window.Title + "）";
        if (!string.IsNullOrEmpty(element.Name)) label += "  #" + element.Name;
        if (!string.IsNullOrEmpty(element.Uid)) label += "  [" + element.Uid + "]";
        var content = element as ContentControl;
        string text = content == null || window != null ? null : content.Content as string;
        if (!string.IsNullOrWhiteSpace(text)) label += "  “" + (text.Length > 28 ? text.Substring(0, 28) + "…" : text) + "”";
        return label;
    }
}

internal sealed class RmtHighlightAdorner : Adorner
{
    private readonly Pen borderPen;
    private readonly Brush fillBrush;

    public RmtHighlightAdorner(UIElement adornedElement, Color accent) : base(adornedElement)
    {
        IsHitTestVisible = false;
        fillBrush = new SolidColorBrush(Color.FromArgb(48, accent.R, accent.G, accent.B));
        fillBrush.Freeze();
        borderPen = new Pen(new SolidColorBrush(accent), 2.5);
        borderPen.Freeze();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        drawingContext.DrawRectangle(fillBrush, borderPen, new Rect(AdornedElement.RenderSize));
    }
}
