// Compile with CommonStyles.cs and WPF references. Run in a separate STA process.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Data;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;

class CommonStylesTest
{
    static void Check(bool value, string message) { if (!value) throw new Exception(message); Console.WriteLine("PASS " + message); }
    static void Pump() { var frame = new DispatcherFrame(); var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) }; timer.Tick += delegate { timer.Stop(); frame.Continue = false; }; timer.Start(); Dispatcher.PushFrame(frame); }
    static void CheckRestoredWindowLayout()
    {
        const string key = "Window:Restored voice keywords";
        var savedLayout = new Dictionary<string, string> {
            { "AnchorObject", "窗口" }, { "AnchorType", "左上" },
            { "PositionX", "20" }, { "PositionY", "30" },
            { "Width", "701.33" }, { "Height", "526" }
        };
        try
        {
            for (int i = 0; i < 2; i++)
            {
                var input = new TextBox { Text = "开始,暂停", FontSize = 15 };
                var root = new Grid { Width = 480, Height = 300 };
                root.Children.Add(input);
                var hostBox = new Viewbox { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.Both, Child = root };
                // Start above the 480x300 design size to model the main window's Viewbox scale.
                var dialog = new Window { Title = "Restored voice keywords", Width = 720, Height = 450,
                    ShowInTaskbar = false, Opacity = 0, Content = hostBox };
                try
                {
                    RmtCommonStyles.Layouts.Remove(key);
                    dialog.Show(); Pump();
                    double initialVisualScale = RmtCommonStyles.WindowContentVisualScale(dialog);
                    Check(initialVisualScale > 1.1, "test dialog starts with a main-window-like visual font scale");
                    RmtCommonStyles.Layouts[key] = new Dictionary<string, string>(savedLayout);
                    RmtCommonStyles.ApplyLayout(dialog); Pump();
                    Check(ReferenceEquals(dialog.Content, hostBox) && ReferenceEquals(hostBox.Child, root),
                        "restored window keeps the Viewbox host so fonts stay scaled");
                    Check(Math.Abs(dialog.Width - 701.33) < .01 && dialog.Height == 526,
                        "restored window keeps the saved dimensions");
                    Check(input.FontSize == 15 && input.Text == "开始,暂停",
                        "restored window keeps editable content and declared font size");
                    double restoredRatio = root.Width / root.Height;
                    double viewportRatio = hostBox.ActualWidth / hostBox.ActualHeight;
                    Check(root.Width > 0 && root.Height > 0 && hostBox.ActualWidth > 0 && hostBox.ActualHeight > 0
                        && Math.Abs(restoredRatio - viewportRatio) < .02,
                        "restored window retargets design size to fill the new viewport");
                    Check(Math.Abs(RmtCommonStyles.WindowContentVisualScale(dialog) - initialVisualScale) < .02,
                        "restored window keeps its pre-resize visual font scale");
                    RmtCommonStyles.ApplyLayout(dialog); Pump();
                    Check(ReferenceEquals(dialog.Content, hostBox) && ReferenceEquals(hostBox.Child, root),
                        "restoring the same window layout twice keeps the Viewbox host");
                }
                finally { dialog.Close(); }
            }
        }
        finally { RmtCommonStyles.Layouts.Remove(key); }
    }
    static IEnumerable<TreeViewItem> FlattenTree(TreeViewItem item)
    {
        yield return item;
        foreach (TreeViewItem child in item.Items.OfType<TreeViewItem>())
            foreach (var nested in FlattenTree(child)) yield return nested;
    }
    static bool SameValues(Dictionary<string, string> left, Dictionary<string, string> right)
    {
        if (left == null || right == null || left.Count != right.Count) return false;
        foreach (var pair in left)
            if (!right.ContainsKey(pair.Key) || right[pair.Key] != pair.Value) return false;
        return true;
    }
    static IEnumerable<DependencyObject> WalkLogical(DependencyObject root)
    {
        yield return root;
        foreach (object child in LogicalTreeHelper.GetChildren(root))
        {
            var node = child as DependencyObject;
            if (node == null) continue;
            foreach (var nested in WalkLogical(node)) yield return nested;
        }
    }
    static string DisplayedValue(FrameworkElement element)
    {
        var box = element as TextBox;
        if (box != null) return box.Text;
        var combo = element as ComboBox;
        if (combo != null)
        {
            var item = combo.SelectedItem as ComboBoxItem;
            return item == null ? combo.Text : Convert.ToString(item.Content);
        }
        return "";
    }
    static IEnumerable<UIElement> FlattenFields(Panel panel)
    {
        foreach (UIElement child in panel.Children)
        {
            yield return child;
            var expander = child as Expander;
            var inner = expander == null ? null : expander.Content as Panel;
            if (inner == null) continue;
            foreach (UIElement nested in inner.Children) yield return nested;
        }
    }
    static string FieldHeading(UIElement child)
    {
        var heading = child as TextBlock;
        if (heading != null) return heading.Text ?? "";
        var expander = child as Expander;
        return expander == null ? null : expander.Header as string;
    }
    static Dictionary<string, string> SectionValues(StackPanel panel, string start, string end)
    {
        var result = new Dictionary<string, string>();
        bool active = false;
        foreach (UIElement child in FlattenFields(panel))
        {
            string heading = FieldHeading(child);
            if (heading != null)
            {
                if (heading.StartsWith(start)) { active = true; continue; }
                if (active && heading.StartsWith(end)) break;
            }
            var row = active ? child as Grid : null;
            if (row == null) continue;
            foreach (TextBlock label in row.Children.OfType<TextBlock>())
            {
                int column = Grid.GetColumn(label);
                var input = row.Children.OfType<FrameworkElement>().FirstOrDefault(x => !(x is TextBlock) && Grid.GetColumn(x) == column + 1);
                if (input != null) result[label.Text] = DisplayedValue(input);
            }
        }
        return result;
    }
    static bool SectionInputsDimmed(StackPanel panel, string start, string end)
    {
        bool active = false, found = false;
        foreach (UIElement child in FlattenFields(panel))
        {
            string heading = FieldHeading(child);
            if (heading != null)
            {
                if (heading.StartsWith(start)) { active = true; continue; }
                if (active && heading.StartsWith(end)) break;
            }
            var row = active ? child as Grid : null;
            if (row == null) continue;
            foreach (FrameworkElement input in row.Children.OfType<FrameworkElement>().Where(x => !(x is TextBlock) && Grid.GetColumn(x) % 2 == 1))
            {
                found = true;
                if (input.Opacity >= 1 || input.IsHitTestVisible || input.Focusable) return false;
            }
        }
        return found;
    }
    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            foreach (string file in Directory.GetFiles(Path.Combine(Path.GetTempPath(), "RmtGMUI-check"), "dialog-*.xaml"))
            {
                var dialog = (Window)XamlReader.Parse(File.ReadAllText(file));
                Check(dialog.Content != null, "migrated dialog XAML parses: " + Path.GetFileName(file));
                dialog.Close();
            }
            string path = Path.Combine(Path.GetTempPath(), "RmtGMUI-test-" + Guid.NewGuid().ToString("N") + ".xml");
            var window = (Window)XamlReader.Parse(@"<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' Title='Test' Width='600' Height='450' ShowInTaskbar='False' Opacity='0.01'>
              <Window.Resources><SolidColorBrush x:Key='ActionBg' Color='Red'/><SolidColorBrush x:Key='ActionHoverBg' Color='Orange'/><SolidColorBrush x:Key='ActionPressBg' Color='DarkRed'/><Style x:Key='RmtItemEditBtn' TargetType='Button'><Setter Property='Width' Value='64'/></Style></Window.Resources>
              <StackPanel><Button Name='First' Style='{StaticResource RmtItemEditBtn}' Background='{DynamicResource ActionBg}' Content='A'/><Button Name='Second' Uid='gm:Main.Config' Content='C'/><Button Name='Special' Uid='gm-exception:test' Width='31'/><Button Name='BtnMaximize' Visibility='Collapsed' Content='max'/><Button Name='BtnClose' Content='x'/><TextBox Name='Input' Text='hello'/><ItemsControl Name='Virtual'><ItemsControl.ItemTemplate><DataTemplate><Button Style='{StaticResource RmtItemEditBtn}' Content='{Binding}'/></DataTemplate></ItemsControl.ItemTemplate></ItemsControl></StackPanel></Window>");
            bool release = args.Length > 0 && args[0] == "release";
            RmtCommonStyles.Configure(window, path + (release ? "|0" : "|1"));
            window.Show(); Pump();
            CheckRestoredWindowLayout();
            var mainSizeBefore = window.RenderSize;
            var mainContentBefore = ((StackPanel)window.Content).RenderSize;
            var mainSecondBefore = (Button)window.FindName("Second");
            var mainSecondSizeBefore = mainSecondBefore.RenderSize;
            var mainSecondMarginBefore = mainSecondBefore.Margin;
            RmtCommonStyles.Open(window); Pump();
            if (release)
            {
                Check(!app.Windows.Cast<Window>().Any(w => w is RmtStyleEditor), "release editor blocked"); window.Close(); return 0;
            }
            var editor = app.Windows.Cast<Window>().OfType<RmtStyleEditor>().Single(); editor.Opacity = 0;
            Check(window.RenderSize == mainSizeBefore && ((StackPanel)window.Content).RenderSize == mainContentBefore && mainSecondBefore.RenderSize == mainSecondSizeBefore && mainSecondBefore.Margin == mainSecondMarginBefore, "opening GM-UI preserves main window layout");
            Check(editor.Owner == null && !editor.ShowInTaskbar, "GM-UI does not own the main window so other dialogs stay on top");
            Check(editor.WindowStartupLocation == WindowStartupLocation.Manual, "GM-UI places itself relative to the source window");
            Check(!editor.Resources.MergedDictionaries.Contains(window.Resources), "GM-UI uses an isolated resource snapshot");
            var initialDrafts = (Dictionary<string, Dictionary<string, string>>)typeof(RmtStyleEditor).GetField("drafts", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(initialDrafts.Count == 0, "opening GM-UI does not stage draft overrides");
            var editorRoot = (Border)editor.Content;
            var closeGlyph = (TextBlock)editorRoot.FindName("CloseGlyph");
            var pinGlyph = (TextBlock)editorRoot.FindName("PinGlyph");
            var mainTabs = (TabControl)editorRoot.FindName("MainTabs");
            Check(mainTabs != null && mainTabs.Items.Count == 3 && mainTabs.SelectedIndex == 0 && ((TabItem)mainTabs.Items[0]).Header as string == "控件调整" && ((TabItem)mainTabs.Items[1]).Header as string == "模版列表" && ((TabItem)mainTabs.Items[2]).Header as string == "窗口层级", "GM-UI tabs default to control adjustment");
            Check(mainTabs.Margin.Top == 2 && ((DockPanel)editorRoot.FindName("StylesContent")).Margin.Top == 2 && ((DockPanel)editorRoot.FindName("TemplatesContent")).Margin.Top == 2 && ((DockPanel)editorRoot.FindName("ReflectContent")).Margin.Top == 5, "tab and content vertical offsets");
            Check(!WalkLogical((DependencyObject)editorRoot.FindName("StylesContent")).OfType<TextBlock>().Any(t => t.Text == "属性名 / 属性值（每行三组）"), "property section caption removed");
            var previewBox = (Border)editorRoot.FindName("PreviewHost");
            Check(previewBox != null && previewBox.Height == 200 && previewBox.BorderThickness.Left == 1.5 && previewBox.BorderThickness.Top == 1.5, "target style preview uses a 200px 1.5px wrap border");
            Check(mainTabs.Style != null && ((TabItem)mainTabs.Items[0]).Style != null && ((TabItem)mainTabs.Items[0]).Tag as string == "first" && ((TabItem)mainTabs.Items[2]).Tag as string == "last", "GM-UI tabs use main-window-like tab chrome");
            var tabTemplate = (ControlTemplate)((Setter)((TabItem)mainTabs.Items[0]).Style.Setters.OfType<Setter>().First(s => s.Property == Control.TemplateProperty)).Value;
            string expectedFont = Math.Max(12, RmtCommonStyles.ThemeFontSize(window) + 2).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
            Check(XamlWriter.Save(tabTemplate).IndexOf("FontSize=\"" + expectedFont + "\"", StringComparison.Ordinal) >= 0, "tab header font size is theme plus two");
            Check(editorRoot.FindName("CmdReflect") == null && editorRoot.FindName("CmdReset") == null && editorRoot.FindName("CmdSave") == null && editorRoot.FindName("Status") == null, "top reset/apply/status controls removed");
            Check(editorRoot.FindName("BtnWinPin") is Button, "editor pin button exists");
            Check(editorRoot.FindName("BtnWinMin") is Button && editorRoot.FindName("BtnWinMax") is Button, "editor minimize and maximize buttons exist");
            Check(((TextBlock)editorRoot.FindName("MinGlyph")).Text == "\uE921" && ((TextBlock)editorRoot.FindName("MaxGlyph")).Text == "\uE922", "minimize and maximize glyphs match window chrome");
            Check(closeGlyph.Text == "\uE8BB" && closeGlyph.FontFamily.Source == "Segoe Fluent Icons, Segoe MDL2 Assets" && closeGlyph.FontSize >= Math.Max(15, window.FontSize) && closeGlyph.FontWeight == FontWeights.Bold, "close glyph matches scaled bold main window chrome");
            Check(pinGlyph.FontSize == closeGlyph.FontSize && pinGlyph.FontWeight == closeGlyph.FontWeight, "pin glyph uses the same scaled bold chrome style");
            Check(editorRoot.FindName("CmdLocateControl") is Button && ((Button)editorRoot.FindName("CmdLocateControl")).Content as string == "控件定位" && editorRoot.FindName("CmdItemReset") is Button && editorRoot.FindName("CmdItemRefresh") == null && editorRoot.FindName("CmdItemApply") == null && editorRoot.FindName("CmdFindTemplate") is Button && editorRoot.FindName("CmdApplyTemplate") == null && editorRoot.FindName("CmdAddTemplate") is Button, "item action bar uses automatic application");
            Check(((Button)editorRoot.FindName("CmdAddTemplate")).Content as string == "新增模版", "add template button renamed");
            var buttonOneField = typeof(RmtStyleEditor).GetField("selected", BindingFlags.Instance | BindingFlags.NonPublic);
            var renderButtonOne = typeof(RmtStyleEditor).GetMethod("Render", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly);
            string previousSelection = (string)buttonOneField.GetValue(editor);
            buttonOneField.SetValue(editor, "样式/RmtItemEditBtn"); renderButtonOne.Invoke(editor, null); Pump();
            var buttonOneColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(buttonOneColors["HoverBackground"].SelectedItem != null && buttonOneColors["PressedBackground"].SelectedItem != null, "named button hover and pressed backgrounds have concrete theme values");
            buttonOneField.SetValue(editor, previousSelection); renderButtonOne.Invoke(editor, null); Pump();
            var fontCombo = new ComboBox { Name = "FontChoice", MaxDropDownHeight = 220 };
            fontCombo.Template = (ControlTemplate)XamlReader.Parse(@"<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='ComboBox'><Grid><ToggleButton><ToggleButton.Template><ControlTemplate TargetType='ToggleButton'><Border Background='White' BorderBrush='Gray' BorderThickness='1' CornerRadius='4'/></ControlTemplate></ToggleButton.Template></ToggleButton><Popup><Border MaxHeight='350' CornerRadius='4'/></Popup></Grid></ControlTemplate>");
            fontCombo.Items.Add("宋体"); fontCombo.Items.Add("黑体"); fontCombo.SelectedIndex = 0;
            ((StackPanel)window.Content).Children.Add(fontCombo); Pump();
            mainTabs.SelectedIndex = 2; Pump();
            var hierarchyTree = (TreeView)editorRoot.FindName("HierarchyTree");
            Check(hierarchyTree != null && hierarchyTree.Items.Count > 0, "control reflector tab shows window hierarchy");
            var hierarchyRoot = (TreeViewItem)hierarchyTree.Items[0];
            Check(hierarchyRoot.ContextMenu != null && hierarchyRoot.ContextMenu.Items.Count == 2, "hierarchy nodes provide expand and collapse menu");
            Check((hierarchyRoot.Header as string ?? "").IndexOf("（" + window.Title + "）", StringComparison.Ordinal) >= 0, "window hierarchy node includes title");
            if (hierarchyRoot.Items.Count > 0)
            {
                var child = (TreeViewItem)hierarchyRoot.Items[0];
                child.IsExpanded = true;
                mainTabs.SelectedIndex = 0; Pump();
                mainTabs.SelectedIndex = 2; Pump();
                Check(ReferenceEquals(hierarchyTree.Items[0], hierarchyRoot) && child.IsExpanded, "switching tabs preserves hierarchy expansion");
            }
            var comboNode = hierarchyRoot.Items.OfType<TreeViewItem>().SelectMany(FlattenTree).FirstOrDefault(x => (x.Header as string ?? "").StartsWith("ComboBox"));
            Check(comboNode != null && comboNode.Items.Count == 0, "combo box hierarchy stops at ComboBox without option items");
            mainTabs.SelectedIndex = 0; Pump();
            var selection = (string)typeof(RmtStyleEditor).GetField("selected", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(selection == "通用/Button", "button template is selected by default");
            var selectedField = typeof(RmtStyleEditor).GetField("selected", BindingFlags.Instance | BindingFlags.NonPublic);
            var renderMethod = typeof(RmtStyleEditor).GetMethod("Render", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly);
            selectedField.SetValue(editor, "Theme.Confirm"); renderMethod.Invoke(editor, null);
            var themeSample = (Button)typeof(RmtStyleEditor).GetField("sample", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var themeBorder = themeSample.Template.LoadContent() as Border;
            Check(themeSample.Width == 80 && themeSample.Height == 32 && themeBorder != null && themeBorder.CornerRadius.TopLeft == 3, "theme confirm preview keeps real button template");
            selectedField.SetValue(editor, selection); renderMethod.Invoke(editor, null); Pump();
            var buttonSample = (Button)typeof(RmtStyleEditor).GetField("sample", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var previewPanel = (StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var previewButton = previewPanel.Children.OfType<Border>().Select(host => host.Child).OfType<Button>().FirstOrDefault();
            var actionBg = editor.TryFindResource("ActionBg") as SolidColorBrush;
            var previewBg = previewButton == null ? null : previewButton.Background as SolidColorBrush;
            Check(buttonSample != null && buttonSample.Template != null && previewButton != null && previewButton.Template != null && actionBg != null && previewBg != null && previewBg.Color == actionBg.Color, "button template preview uses ActionBg chrome matching override colors");
            var buttonColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(buttonColors.ContainsKey("PressedBackground") && buttonColors["PressedBackground"].SelectedItem != null, "button template pressed background has a concrete theme value");
            var foregroundPicker = buttonColors["Foreground"];
            var originalForeground = (foregroundPicker.SelectedItem as ComboBoxItem).Tag as string;
            var changedForeground = foregroundPicker.Items.Cast<ComboBoxItem>().First(item =>
            {
                string candidate = item.Tag as string;
                if (candidate == originalForeground) return false;
                var brush = editor.TryFindResource(RmtCommonStyles.ThemeColorKey(candidate)) as SolidColorBrush;
                var live = buttonSample.Foreground as SolidColorBrush;
                return brush != null && live != null && brush.Color != live.Color;
            });
            string expectedForeground = changedForeground.Tag as string;
            foregroundPicker.SelectedItem = changedForeground; Pump();
            typeof(RmtStyleEditor).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            selectedField.SetValue(editor, "Theme.Confirm"); renderMethod.Invoke(editor, null); Pump();
            selectedField.SetValue(editor, selection); renderMethod.Invoke(editor, null); Pump();
            buttonColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(RmtCommonStyles.Values[selection]["Foreground"] == expectedForeground
                && ((buttonColors["Foreground"].SelectedItem as ComboBoxItem).Tag as string) == expectedForeground,
                "button template foreground remains saved after switching templates");
            selectedField.SetValue(editor, "Main.Config"); renderMethod.Invoke(editor, null); Pump();
            var configSample = (Button)typeof(RmtStyleEditor).GetField("sample", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var configPreview = ((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).Children.OfType<Border>().Select(host => host.Child).OfType<Button>().FirstOrDefault();
            var configPresets = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("presetInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(configSample != null && configPreview != null && Math.Abs(configSample.Height - configPreview.Height) < .1 && Math.Abs(configSample.Padding.Left - configPreview.Padding.Left) < .1, "named button preview height and padding match sample");
            Check(configPresets.ContainsKey("Padding") && configPreview.Padding.Left == configSample.Padding.Left, "button 3 padding field matches preview chrome");
            selectedField.SetValue(editor, "通用/Window"); renderMethod.Invoke(editor, null); Pump();
            var windowPreview = ((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).Children.OfType<Border>().FirstOrDefault();
            var windowBody = windowPreview == null ? null : ((Grid)windowPreview.Child).Children.OfType<Border>().FirstOrDefault(x => Grid.GetRow(x) == 1);
            Check(windowBody != null && windowBody.Child is Border && ((Border)windowBody.Child).Background != null, "window template preview fills content with background to reveal padding");
            var windowFields = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var windowLabels = windowFields.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).Select(t => t.Text).ToList();
            Check(windowFields.Children.OfType<TextBlock>().Any(t => t.Text == "重载属性") && windowLabels.Contains("圆角") && windowLabels.Contains("背景颜色") && !windowLabels.Contains("宽高类型") && !windowLabels.Contains("宽度") && !windowLabels.Contains("高度"), "window template reload keeps chrome surface fields without size mode");
            var windowPresets = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("presetInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var windowColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(windowPresets.ContainsKey("Padding") && windowPresets.ContainsKey("CornerRadius") && windowPresets["Padding"].IsEditable && windowColors.ContainsKey("Background") && windowColors["Background"].Items.Count == 14, "window padding radius and background use the same pickers as button templates");
            selectedField.SetValue(editor, selection); renderMethod.Invoke(editor, null);
            var catalog = (TreeView)typeof(RmtStyleEditor).GetField("catalog", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var adjustCatalog = (TreeView)typeof(RmtStyleEditor).GetField("adjustCatalog", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var windowGroup = catalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "窗口" || (g.Tag as string) == "#group:窗口");
            var buttonGroupMenu = catalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "按钮" || (g.Tag as string) == "#group:按钮");
            Check(windowGroup.ContextMenu != null && windowGroup.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除")
                && windowGroup.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "重命名")
                && buttonGroupMenu.ContextMenu != null && buttonGroupMenu.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除"), "template categories provide rename and delete commands");
            var defaultLeaf = catalog.Items.OfType<TreeViewItem>().SelectMany(x => x.Items.OfType<TreeViewItem>()).First(x => (x.Tag as string) == "通用/Button");
            var defaultHeader = defaultLeaf.Header as Grid;
            Check(defaultLeaf.IsSelected && defaultHeader != null && defaultHeader.Children.OfType<System.Windows.Shapes.Ellipse>().Any(e => e.Visibility == Visibility.Visible) && defaultLeaf.FontWeight == FontWeights.Normal, "default button template has selection background and corner dot");
            foreach (TreeViewItem group in catalog.Items)
                foreach (TreeViewItem item in group.Items) item.IsSelected = true;
            Check(true, "all catalog previews render");
            var a = (Button)window.FindName("First"); var b = (Button)window.FindName("Second");
            editor.AcceptHierarchyTarget(b); Pump();
            var reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "反射控件");
            var reflectLeaf = reflectGroup.Items.OfType<TreeViewItem>().First();
            Check(reflectLeaf.IsSelected && ReferenceEquals(adjustCatalog.SelectedItem, reflectLeaf), "locate selects reflected control not its template");
            var positionX = (TextBox)typeof(RmtStyleEditor).GetField("positionX", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var positionY = (TextBox)typeof(RmtStyleEditor).GetField("positionY", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var templateBeforeReset = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(templateBeforeReset.Count > 0 && SectionInputsDimmed(fieldsPanel, "模版属性", "重载属性"), "reflected template properties are visibly read-only");
            var reflectedColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(reflectedColors["Background"].Items.Cast<ComboBoxItem>().All(x => Convert.ToString(x.Content).IndexOf("继承当前颜色", StringComparison.Ordinal) < 0), "reflected inherited colors show their concrete value");
            Check(reflectedColors["Background"].Items.Count == 14 && reflectedColors["Background"].Items.Cast<ComboBoxItem>().All(x => (x.Tag as string ?? "").StartsWith("$Theme:")), "color properties contain only colors 1 through 14");
            var reloadList = fieldsPanel.Children.OfType<DockPanel>().SelectMany(p => p.Children.OfType<StackPanel>()).SelectMany(p => p.Children.OfType<ComboBox>()).FirstOrDefault(c => c.Name == "ReloadList");
            Check(reloadList != null && reloadList.Items.Cast<ComboBoxItem>().Any(x => (x.Tag as string) == "通用/Button") && reloadList.Items.Cast<ComboBoxItem>().Any(x => (x.Tag as string) == "样式/RmtItemEditBtn"), "located button shows button templates in the reload list");
            var reloadActions = fieldsPanel.Children.OfType<DockPanel>().SelectMany(p => p.Children.OfType<StackPanel>()).FirstOrDefault(p => p.Children.OfType<ComboBox>().Any(c => c.Name == "ReloadList"));
            Check(reloadActions != null && reloadActions.Margin.Right >= 200, "reload list sits left of the editor edge");
            var reloadRow = fieldsPanel.Children.OfType<DockPanel>().FirstOrDefault(p => p.Children.OfType<StackPanel>().Any(s => s.Children.OfType<ComboBox>().Any(c => c.Name == "ReloadList")));
            Check(reloadRow != null && reloadRow.Margin.Top == 0, "reload properties sit closer to template properties");
            var inspectPreview = (StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(WalkLogical(inspectPreview).OfType<TextBlock>().Any(t => t.Text == "控件样式") && WalkLogical(inspectPreview).OfType<TextBlock>().Any(t => t.Text == "重载样式"), "located button preview splits control and reload styles");
            Check(!WalkLogical(inspectPreview).OfType<Viewbox>().Any(), "control style preview stays 1:1 without Viewbox shrink");
            Check(WalkLogical(inspectPreview).OfType<Border>().Any(frame => Math.Abs(frame.Width - 1.5) < 0.01 && frame.VerticalAlignment == VerticalAlignment.Stretch), "reload style column is separated by a 1.5px divider");
            var reloadPreviewCol = WalkLogical(inspectPreview).OfType<DockPanel>().FirstOrDefault(p => p.Children.OfType<TextBlock>().Any(t => t.Text == "重载样式"));
            var reloadPreviewBtn = reloadPreviewCol == null ? null : WalkLogical(reloadPreviewCol).OfType<Button>().FirstOrDefault();
            Check(reloadPreviewBtn != null && reloadPreviewBtn.HorizontalAlignment == HorizontalAlignment.Center && reloadPreviewBtn.VerticalAlignment == VerticalAlignment.Center, "reload style preview stays centered at its natural size");
            Check(WalkLogical(inspectPreview).OfType<Border>().Count(frame => Math.Abs(frame.BorderThickness.Left - 1.5) < 0.01 && frame.Child is DockPanel) == 2, "control and reload style columns use 1.5px wrap borders");
            var templateExpander = fieldsPanel.Children.OfType<Expander>().FirstOrDefault(e => (e.Header as string ?? "").StartsWith("模版属性"));
            Check(templateExpander != null && templateExpander.IsExpanded == false, "template properties start collapsed");
            typeof(RmtStyleEditor).GetField("interactionReady", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            var reloadBeforeSwitch = SectionValues(fieldsPanel, "重载属性", "不会出现的结束标记");
            double locatedWidthBeforeSwitch = b.Width;
            reloadList.SelectedItem = reloadList.Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "样式/RmtItemEditBtn"); Pump();
            Check(SameValues(reloadBeforeSwitch, SectionValues(fieldsPanel, "重载属性", "不会出现的结束标记")) && ((double.IsNaN(locatedWidthBeforeSwitch) && double.IsNaN(b.Width)) || b.Width == locatedWidthBeforeSwitch), "changing reload list does not refresh reload properties or the live control");
            reloadList.SelectedItem = reloadList.Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "通用/Button"); Pump();
            mainTabs.SelectedIndex = 1; Pump();
            var namedTemplateLeaf = catalog.Items.OfType<TreeViewItem>().SelectMany(g => g.Items.OfType<TreeViewItem>()).First(x => (x.Tag as string) == "样式/RmtItemEditBtn");
            namedTemplateLeaf.IsSelected = true; Pump();
            Check(!WalkLogical((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).OfType<TextBlock>().Any(t => t.Text == "控件样式"), "template list selection shows the catalog sample instead of the located preview");
            mainTabs.SelectedIndex = 0; Pump();
            Check(WalkLogical((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).OfType<TextBlock>().Any(t => t.Text == "控件样式"), "returning to control adjustment restores the located style preview");
            var restoredInspect = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(restoredInspect != null && ReferenceEquals(restoredInspect.Target, b), "returning to control adjustment keeps the located control");
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            positionX = (TextBox)typeof(RmtStyleEditor).GetField("positionX", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            positionY = (TextBox)typeof(RmtStyleEditor).GetField("positionY", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            typeof(RmtStyleEditor).GetField("interactionReady", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            var positionLabel = fieldsPanel.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).First(t => t.Text == "位置X");
            Check(positionLabel.Cursor == System.Windows.Input.Cursors.SizeWE, "position labels support drag adjustment");
            int positionHeadingAt = -1, styleTemplateAt = -1;
            for (int i = 0; i < fieldsPanel.Children.Count; i++)
            {
                var heading = fieldsPanel.Children[i] as TextBlock;
                if (heading != null && heading.Text == "位置") positionHeadingAt = i;
                var expander = fieldsPanel.Children[i] as Expander;
                if (expander != null && (expander.Header as string ?? "").StartsWith("样式模板")) styleTemplateAt = i;
            }
            Check(positionHeadingAt >= 0 && (styleTemplateAt < 0 || positionHeadingAt < styleTemplateAt), "position sits above the style template source");
            var beforePosition = b.TranslatePoint(new Point(0, 0), (UIElement)b.Parent);
            Check(Math.Abs(double.Parse(positionX.Text) - beforePosition.X) < .1 && Math.Abs(double.Parse(positionY.Text) - beforePosition.Y) < .1, "reflected position reads rendered coordinates");
            Check(typeof(RmtStyleEditor).GetField("anchorType", BindingFlags.Instance | BindingFlags.NonPublic) == null && typeof(RmtStyleEditor).GetField("anchorObject", BindingFlags.Instance | BindingFlags.NonPublic) == null, "reflector position UI no longer exposes anchors");
            positionX.Text = (double.Parse(positionX.Text) + 10).ToString(); Pump();
            var movedPosition = b.TranslatePoint(new Point(0, 0), (UIElement)b.Parent);
            Check(Math.Abs(movedPosition.X - beforePosition.X - 10) < .5, "position edit automatically updates reflected control");
            ((Button)editorRoot.FindName("CmdItemReset")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            var restoredPosition = b.TranslatePoint(new Point(0, 0), (UIElement)b.Parent);
            Check(Math.Abs(restoredPosition.X - beforePosition.X) < .5, "one reset restores the pre-edit position");
            var templateAfterReset = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(templateBeforeReset.OrderBy(x => x.Key).SequenceEqual(templateAfterReset.OrderBy(x => x.Key)), "reset does not change reflected template properties");
            var selectCatalog = typeof(RmtStyleEditor).GetMethod("SelectCatalog", BindingFlags.Instance | BindingFlags.NonPublic);
            Check(!(bool)selectCatalog.Invoke(editor, new object[] { "通用/TextBox", true, true, false }), "controls without a template cannot resolve to the reflected node");
            typeof(RmtStyleEditor).GetMethod("FindTemplate", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            var templateLeaf = (TreeViewItem)catalog.SelectedItem;
            var templateHeader = templateLeaf == null ? null : templateLeaf.Header as Grid;
            Check(templateLeaf != null && (templateLeaf.Tag as string) == "通用/Button" && templateHeader != null && templateHeader.Children.OfType<System.Windows.Shapes.Ellipse>().Any(e => e.Visibility == Visibility.Visible) && mainTabs.SelectedIndex == 1, "find template frames selected template");
            var inspectAfterFind = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(inspectAfterFind != null && ReferenceEquals(inspectAfterFind.Target, b), "find template keeps reflected control reference");
            Check(adjustCatalog.Items.OfType<TreeViewItem>().Any(g => (g.Header as string) == "反射控件"), "reflected control catalog group remains after find template");
            typeof(RmtStyleEditor).GetMethod("ApplyReloadToTemplate", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            Check(RmtCommonStyles.Values.ContainsKey("通用/Button"), "apply reload properties to template");
            var defaultMenu = defaultLeaf.ContextMenu;
            Check(defaultMenu != null && defaultMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除") && defaultMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "新增模版"), "button template provides delete command");
            var buttonGroup = catalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "按钮");
            var buttonOne = buttonGroup.Items.OfType<TreeViewItem>().FirstOrDefault(x => (x.Tag as string) == "样式/RmtItemEditBtn");
            var buttonTwo = buttonGroup.Items.OfType<TreeViewItem>().FirstOrDefault(x => (x.Tag as string) == "样式/RmtItemPrimaryBtn");
            var buttonMain = buttonGroup.Items.OfType<TreeViewItem>().FirstOrDefault(x => (x.Tag as string) == "Main.Config");
            Check(buttonOne != null && buttonOne.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除")
                && buttonTwo != null && buttonTwo.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除")
                && buttonMain != null && buttonMain.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除"), "named button styles provide delete command");
            var box = new StackPanel { Name = "Box" };
            var childA = new Button { Name = "ChildA", Content = "A", Width = 40 };
            var childB = new Button { Name = "ChildB", Content = "B", Width = 40 };
            box.Children.Add(childA); box.Children.Add(childB);
            ((StackPanel)window.Content).Children.Add(box); Pump();
            editor.AcceptHierarchyTarget(box); Pump();
            reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "反射控件");
            reflectLeaf = reflectGroup.Items.OfType<TreeViewItem>().First();
            Check(reflectLeaf.Items.Count == 2, "locating a parent syncs child hierarchy into style management");
            Check(fieldsPanel.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).Any(t => t.Text == "示例内容"), "hierarchy target shows sample content field");
            var hierarchyPreview = WalkLogical((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).OfType<StackPanel>().FirstOrDefault(s => s.Children.OfType<Button>().Count() == 2);
            Check(hierarchyPreview != null && hierarchyPreview.Children.OfType<Button>().Count() == 2, "hierarchy preview clones the full subtree not a single control");
            var boxOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var boxColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var boxInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(boxOptions.ContainsKey("Orientation") && boxOptions.ContainsKey("HorizontalAlignment") && boxOptions.ContainsKey("ChildAlignment"), "panel exposes orientation and alignment");
            Check(boxInputs.ContainsKey("Spacing"), "stack panel exposes child spacing");
            Check(boxInputs["Spacing"].Padding.Left == 2 && boxInputs["Spacing"].Padding.Top == 0
                && boxInputs["Spacing"].Height == 28 && boxInputs["Spacing"].VerticalContentAlignment == VerticalAlignment.Center,
                "stack panel spacing input matches compact numeric field chrome");
            Check(!boxOptions.ContainsKey("TextAlignment") && !boxOptions.ContainsKey("Stretch"), "panel hides text and image-only properties");
            Check(!boxColors.ContainsKey("HoverBackground") && !boxColors.ContainsKey("PressedBackground"), "panel hides button chrome properties");
            var boxTemplate = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(boxTemplate.ContainsKey("排列方向") && boxTemplate.ContainsKey("控件水平对齐") && boxTemplate.ContainsKey("子项间距") && boxTemplate.ContainsKey("内容对齐") && !boxTemplate.ContainsKey("文本对齐"), "panel template lists layout properties");
            boxInputs["Spacing"].Text = "6"; Pump();
            Check(Math.Abs(childB.Margin.Top - 6) < .1, "stack panel spacing applies between vertical children");
            typeof(RmtStyleEditor).GetField("interactionReady", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            var alignPick = boxOptions["ChildAlignment"].Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "Center");
            boxOptions["ChildAlignment"].SelectedItem = alignPick; Pump();
            Check(childA.HorizontalAlignment == HorizontalAlignment.Center && childB.HorizontalAlignment == HorizontalAlignment.Center, "stack panel child alignment centers children");
            var voiceActions = new StackPanel { Name = "VoiceKeywordActions", Uid = "ahk:Voice.Keywords.Actions", Orientation = Orientation.Horizontal };
            var voiceSure = new Button { Content = "确定", Width = 90, Margin = new Thickness(0, 0, 10, 0) };
            var voiceCancel = new Button { Content = "取消", Width = 90 };
            voiceActions.Children.Add(voiceSure); voiceActions.Children.Add(voiceCancel);
            ((StackPanel)window.Content).Children.Add(voiceActions); Pump();
            editor.AcceptHierarchyTarget(voiceActions); Pump();
            var voiceInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var voiceOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            voiceInputs["Spacing"].Text = "150"; Pump();
            voiceOptions["ChildAlignment"].SelectedItem = voiceOptions["ChildAlignment"].Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "Center"); Pump();
            Check(voiceActions.HorizontalAlignment == HorizontalAlignment.Center && !RmtCommonStyles.Layouts.ContainsKey(RmtCommonStyles.LayoutId(voiceActions)), "voice action style alignment is not pinned by an automatic position layout");
            var voicePreview = (StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(WalkLogical(voicePreview).OfType<ScrollViewer>().Any() && WalkLogical(voicePreview).OfType<Button>().Count() >= 2, "oversized action panel preview keeps its buttons in a scrollable area");
            typeof(RmtStyleEditor).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            string voiceActionsId = RmtCommonStyles.LayoutId(voiceActions);
            Check(voiceActionsId == "ahk:Voice.Keywords.Actions" && RmtCommonStyles.StyleBindings.ContainsKey(voiceActionsId) && RmtCommonStyles.InstanceStyles.ContainsKey(voiceActionsId), "voice action panel adjustments persist under a stable instance id");
            RmtCommonStyles.Save();
            RmtCommonStyles.InstanceStyles.Remove(voiceActionsId);
            typeof(RmtCommonStyles).GetMethod("Load", BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, null);
            ((StackPanel)window.Content).Children.Remove(voiceActions);
            var reopenedVoiceActions = new StackPanel { Name = "VoiceKeywordActions", Uid = voiceActionsId, Orientation = Orientation.Horizontal };
            var reopenedSure = new Button { Content = "确定", Width = 90, Margin = new Thickness(0, 0, 10, 0) };
            var reopenedCancel = new Button { Content = "取消", Width = 90 };
            reopenedVoiceActions.Children.Add(reopenedSure); reopenedVoiceActions.Children.Add(reopenedCancel);
            ((StackPanel)window.Content).Children.Add(reopenedVoiceActions); RmtCommonStyles.EnsureRegistered(reopenedVoiceActions); Pump();
            Check(reopenedVoiceActions.HorizontalAlignment == HorizontalAlignment.Center
                && reopenedSure.HorizontalAlignment == HorizontalAlignment.Center && reopenedCancel.HorizontalAlignment == HorizontalAlignment.Center
                && Math.Abs(reopenedCancel.Margin.Left - 150) < .1,
                "voice action panel alignment and spacing restore after configuration reload");
            var bareLabel = new TextBlock { Name = "BareLabel", Text = "颜色14：" };
            ((StackPanel)window.Content).Children.Add(bareLabel); Pump();
            editor.AcceptHierarchyTarget(bareLabel); Pump();
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(fieldsPanel.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).Any(t => t.Text == "示例内容"), "text target shows sample content field");
            var labelColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(labelColors["Background"].SelectedItem == null, "unpainted label background stays unselected instead of color 1");
            var labelPreview = WalkLogical((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).OfType<TextBlock>().FirstOrDefault(t => t.Text == "颜色14：");
            var labelBg = labelPreview == null ? null : labelPreview.Background as SolidColorBrush;
            Check(labelPreview != null && (labelPreview.Background == null || (labelBg != null && labelBg.Color.A == 0)), "unpainted label preview has no background");
            var labelOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(labelOptions.ContainsKey("TextAlignment") && labelOptions.ContainsKey("TextWrapping") && labelOptions.ContainsKey("TextTrimming") && labelOptions.ContainsKey("HorizontalAlignment"), "text block exposes text and alignment properties");
            Check(!labelColors.ContainsKey("HoverBackground") && !labelColors.ContainsKey("PressedBackground"), "text block hides button chrome properties");
            Check(!labelOptions.ContainsKey("IsReadOnly") && !labelOptions.ContainsKey("Orientation"), "text block hides text-box and panel-only properties");
            var labelTemplate = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(labelTemplate.ContainsKey("文本对齐") && labelTemplate.ContainsKey("文本换行") && labelTemplate.ContainsKey("文本裁剪") && !labelTemplate.ContainsKey("悬停背景"), "text block template lists text properties");
            Check(!fieldsPanel.Children.OfType<DockPanel>().SelectMany(p => p.Children.OfType<StackPanel>()).SelectMany(p => p.Children.OfType<ComboBox>()).Any(c => c.Name == "ReloadList"), "text block hides reload list when no matching template exists");
            var labelPreviewHost = (StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(WalkLogical(labelPreviewHost).OfType<TextBlock>().Any(t => t.Text == "控件样式") && !WalkLogical(labelPreviewHost).OfType<TextBlock>().Any(t => t.Text == "重载样式"), "text block preview keeps the control column and hides reload style");
            var inputBox = (TextBox)window.FindName("Input");
            editor.AcceptHierarchyTarget(inputBox); Pump();
            var inputColors = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("colorInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var inputOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var inputBoxes = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(inputOptions.ContainsKey("IsReadOnly") && inputOptions.ContainsKey("AcceptsReturn") && inputOptions.ContainsKey("TextWrapping") && inputOptions.ContainsKey("VerticalScrollBarVisibility"), "text box exposes edit and wrap properties");
            Check(inputBoxes.ContainsKey("MaxLength"), "text box exposes max length");
            Check(!inputColors.ContainsKey("HoverBackground") && !inputOptions.ContainsKey("TextTrimming") && !inputOptions.ContainsKey("Orientation"), "text box hides button, trim, and panel-only properties");
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var inputTemplate = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(inputTemplate.ContainsKey("只读") && inputTemplate.ContainsKey("允许换行") && inputTemplate.ContainsKey("最大长度") && !inputTemplate.ContainsKey("悬停背景"), "text box template lists edit properties");
            RmtCommonStyles.Values.Remove("通用/TextBox");
            var siblingInput = new TextBox { Name = "SiblingInput", Text = "unchanged" };
            ((StackPanel)window.Content).Children.Add(siblingInput); RmtCommonStyles.EnsureRegistered(siblingInput); Pump();
            double siblingFontBefore = siblingInput.FontSize;
            var inputSliders = (Dictionary<string, Slider>)typeof(RmtStyleEditor).GetField("sliderInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            inputSliders["RelativeFontSize"].Value = 2; Pump();
            Check(Math.Abs(inputBox.FontSize - (RmtCommonStyles.ThemeFontSize(inputBox) + 2)) < .01
                && Math.Abs(siblingInput.FontSize - siblingFontBefore) < .01,
                "reflected font preview changes only the located text box");
            typeof(RmtStyleEditor).GetMethod("ApplyReloadToTemplate", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            Check(!RmtCommonStyles.Values.ContainsKey("通用/TextBox"), "apply-to-template does not create a shared TextBox style from a reflected control");
            var applyStatus = (TextBlock)typeof(RmtStyleEditor).GetField("status", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(applyStatus.Text.IndexOf("没有独立模版", StringComparison.Ordinal) >= 0, "apply-to-template explains that reflected text boxes need an explicit template");
            typeof(RmtStyleEditor).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null); Pump();
            string inputLayoutId = RmtCommonStyles.LayoutId(inputBox);
            Check(!string.IsNullOrEmpty(inputLayoutId) && RmtCommonStyles.InstanceStyles.ContainsKey(inputLayoutId), "apply persists reflected text box edits as instance styles");
            Check(!RmtCommonStyles.Values.ContainsKey("通用/TextBox"), "apply does not paint shared TextBox styles onto the main window");
            string relativeFont;
            Check(RmtCommonStyles.InstanceStyles[inputLayoutId].TryGetValue("RelativeFontSize", out relativeFont)
                && Math.Abs(double.Parse(relativeFont, CultureInfo.InvariantCulture) - 2) < .01,
                "applied reflected font size is stored on the located instance");
            var inputParent = (StackPanel)inputBox.Parent;
            int inputIndex = inputParent.Children.IndexOf(inputBox);
            inputParent.Children.Remove(inputBox);
            var reopenedInput = new TextBox { Name = "Input", Text = "reopened" };
            inputParent.Children.Insert(inputIndex, reopenedInput); RmtCommonStyles.EnsureRegistered(reopenedInput); RmtCommonStyles.Refresh(); Pump();
            Check(RmtCommonStyles.LayoutId(reopenedInput) == inputLayoutId
                && Math.Abs(reopenedInput.FontSize - (RmtCommonStyles.ThemeFontSize(reopenedInput) + 2)) < .01,
                "recreated located control restores its instance font adjustment");
            inputParent.Children.Remove(siblingInput);
            var picture = new Image { Name = "Picture", Stretch = Stretch.Uniform, Width = 32, Height = 32 };
            ((StackPanel)window.Content).Children.Add(picture); Pump();
            editor.AcceptHierarchyTarget(picture); Pump();
            var imageOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(imageOptions.ContainsKey("Stretch") && imageOptions.ContainsKey("StretchDirection") && imageOptions.ContainsKey("HorizontalAlignment"), "image exposes stretch properties");
            Check(!imageOptions.ContainsKey("TextAlignment") && !imageOptions.ContainsKey("Orientation"), "image hides text and panel-only properties");
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var imageTemplate = SectionValues(fieldsPanel, "模版属性", "重载属性");
            Check(imageTemplate.ContainsKey("拉伸方式") && imageTemplate.ContainsKey("拉伸方向") && !imageTemplate.ContainsKey("文本对齐"), "image template lists stretch properties");
            window.Height = 900; Pump();
            var wrap = new Border { Name = "WrapBorder", Width = 160, Height = 56, Background = Brushes.Gray };
            var wrapped = new Button { Name = "WrappedBtn", Width = 160, Height = 56, Content = "in" };
            wrap.Child = wrapped;
            ((StackPanel)window.Content).Children.Insert(0, wrap); Pump();
            wrap.BringIntoView(); Pump();
            double innerX = wrapped.ActualWidth / 2;
            double innerY = wrapped.ActualHeight / 2;
            double rimX = Math.Max(1, wrapped.ActualWidth * 0.04);
            double rimY = Math.Max(1, wrapped.ActualHeight * 0.04);
            Check(RmtStyleEditor.IsInnerPickBand(wrapped, new Point(innerX, innerY)) && !RmtStyleEditor.IsInnerPickBand(wrapped, new Point(rimX, innerY)) && !RmtStyleEditor.IsInnerPickBand(wrapped, new Point(innerX, rimY)), "button inner 80 percent is the pick band and the rim is the edge");
            Check(ReferenceEquals(RmtStyleEditor.ResolveEdgeAwarePick(wrapped, new Point(innerX, innerY)), wrapped), "wrapped button center stays on the button");
            Check(ReferenceEquals(RmtStyleEditor.ResolveEdgeAwarePick(wrapped, new Point(rimX, innerY)), wrap), "wrapped button edge promotes to the border");
            Check(ReferenceEquals(RmtStyleEditor.ResolveEdgeAwarePick(wrapped, new Point(innerX, rimY)), wrap), "wrapped button top edge promotes to the border");
            var hitCenter = editor.HitPickableAt(window, wrapped.TranslatePoint(new Point(innerX, innerY), window));
            var hitEdge = editor.HitPickableAt(window, wrapped.TranslatePoint(new Point(rimX, innerY), window));
            Check(ReferenceEquals(hitCenter, wrapped), "hovering the inner 80 percent of a wrapped button picks the button");
            Check(ReferenceEquals(hitEdge, wrap), "hovering the button edge picks the wrapping border");
            typeof(RmtStyleEditor).GetMethod("ShowHighlight", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, new object[] { wrapped }); Pump();
            var hitAfterGlow = editor.HitPickableAt(window, wrapped.TranslatePoint(new Point(innerX, innerY), window));
            Check(ReferenceEquals(hitAfterGlow, wrapped), "highlight adorner does not steal the inner pick");
            var hitAfterGlow2 = editor.HitPickableAt(window, wrapped.TranslatePoint(new Point(innerX, innerY), window));
            Check(ReferenceEquals(hitAfterGlow, hitAfterGlow2) && ReferenceEquals(hitAfterGlow2, wrapped), "repeated hover over the highlighted button stays on the button");
            editor.AcceptHierarchyTarget(window); Pump();
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(fieldsPanel.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).Any(t => t.Text == "示例内容"), "window target shows sample content field");
            var windowClone = WalkLogical((StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor)).OfType<Border>().FirstOrDefault(frame => frame.Child is Grid && ((Grid)frame.Child).RowDefinitions.Count >= 2);
            var windowContentClone = windowClone == null ? null : ((Grid)windowClone.Child).Children.OfType<FrameworkElement>().FirstOrDefault(x => Grid.GetRow(x) == 1) as StackPanel;
            Check(windowClone != null && windowContentClone != null && windowContentClone.Children.OfType<Button>().Any(), "window hierarchy preview clones the full window content");
            Check(!windowContentClone.Children.OfType<Button>().Any(x => x.Name == "BtnMaximize" || x.Name == "BtnClose"), "window preview omits title-bar chrome controls that are cloned separately");
            var previewBar = windowClone == null ? null : ((Grid)windowClone.Child).Children.OfType<Grid>().FirstOrDefault(x => Grid.GetRow(x) == 0);
            var previewChrome = previewBar == null ? null : previewBar.Children.OfType<StackPanel>().FirstOrDefault();
            Check(previewChrome != null && previewChrome.Children.Count == 1, "window preview only shows visible title-bar buttons");
            var inspectLabels = fieldsPanel.Children.OfType<Grid>().SelectMany(g => g.Children.OfType<TextBlock>()).Select(t => t.Text).ToList();
            Check(!inspectLabels.Contains("悬停背景") && !inspectLabels.Contains("按住背景") && !inspectLabels.Contains("文字颜色"), "window template properties stay within the reload property set");
            var inspectHeadings = fieldsPanel.Children.Cast<UIElement>().Select(FieldHeading).Where(t => !string.IsNullOrEmpty(t)).ToList();
            int templateAt = inspectHeadings.FindIndex(t => (t ?? "").StartsWith("模版属性"));
            int reloadAt = inspectHeadings.FindIndex(t => (t ?? "").StartsWith("重载属性"));
            Check(templateAt >= 0 && reloadAt > templateAt, "window reload properties stay below template properties");
            var windowOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(windowOptions.ContainsKey("SizeMode"), "window inspect can reload size mode");
            var windowInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(windowInputs.ContainsKey("Width") && windowInputs.ContainsKey("Height"), "window reload exposes width and height");
            Check(typeof(RmtStyleEditor).GetField("positionWidth", BindingFlags.Instance | BindingFlags.NonPublic) == null
                && typeof(RmtStyleEditor).GetField("positionHeight", BindingFlags.Instance | BindingFlags.NonPublic) == null,
                "window position section does not duplicate width and height");
            double windowWidthBeforeLocate = window.Width, windowHeightBeforeLocate = window.Height;
            windowInputs["Width"].Text = (windowWidthBeforeLocate + 40).ToString(System.Globalization.CultureInfo.InvariantCulture);
            windowInputs["Height"].Text = (windowHeightBeforeLocate + 30).ToString(System.Globalization.CultureInfo.InvariantCulture); Pump();
            Check(Math.Abs(window.Width - windowWidthBeforeLocate - 40) < .5 && Math.Abs(window.Height - windowHeightBeforeLocate - 30) < .5, "window locate edits dimensions without scaling through content");
            ((Button)editorRoot.FindName("CmdItemReset")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            Check(Math.Abs(window.Width - windowWidthBeforeLocate) < .5 && Math.Abs(window.Height - windowHeightBeforeLocate) < .5, "window locate reset restores dimensions");
            var firstButton = (Button)window.FindName("First");
            typeof(RmtStyleEditor).GetField("picking", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            typeof(RmtStyleEditor).GetField("pickHover", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, firstButton);
            var clickArgs = new MouseButtonEventArgs(Mouse.PrimaryDevice, 0, MouseButton.Left) { RoutedEvent = UIElement.PreviewMouseLeftButtonDownEvent, Source = editor };
            typeof(RmtStyleEditor).GetMethod("PickMouseDown", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, new object[] { editor, clickArgs });
            Pump();
            var firstRoot = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRootRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "反射控件" || (g.Tag as string) == "#group:反射控件");
            reflectLeaf = reflectGroup.Items.OfType<TreeViewItem>().First();
            var pickedHierarchy = (TreeView)editorRoot.FindName("HierarchyTree");
            Check(clickArgs.Handled && firstRoot != null && ReferenceEquals(firstRoot.Target, firstButton), "left click confirms the hovered locate target");
            Check(reflectGroup.Items.Count == 1 && reflectLeaf.Items.Count == 0, "reflect catalog shows only the picked button subtree");
            Check(pickedHierarchy.Items.Count == 1 && !(((pickedHierarchy.Items[0] as TreeViewItem).Header as string) ?? "").StartsWith("Window"), "reflector tab shows only the picked control hierarchy");
            Check(((TreeViewItem)pickedHierarchy.Items[0]).ContextMenu != null && ((TreeViewItem)pickedHierarchy.Items[0]).ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "显示父级"), "reflector tab root can show parent");
            Check(reflectLeaf.ContextMenu != null && reflectLeaf.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "显示父级"), "reflect root offers show parent");
            editor.ShowInspectParent(); Pump();
            var parentRoot = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRootRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "反射控件" || (g.Tag as string) == "#group:反射控件");
            reflectLeaf = reflectGroup.Items.OfType<TreeViewItem>().First();
            Check(parentRoot != null && parentRoot.Target is Panel && ((Panel)parentRoot.Target).Children.Contains(firstButton), "show parent promotes the reflect root to the container");
            Check(FlattenTree(reflectLeaf).Any(x => { var weak = x.DataContext as WeakReference; return weak != null && ReferenceEquals(weak.Target, firstButton); }), "parent hierarchy still contains the original button");
            Check(!reflectLeaf.Items.OfType<TreeViewItem>().SelectMany(x => (x.ContextMenu == null ? new MenuItem[0] : x.ContextMenu.Items.OfType<MenuItem>())).Any(x => (x.Header as string) == "显示父级"), "only the reflect root offers show parent");
            var unnamedSibling = new Button { Width = 30, Content = "sibling" };
            ((Panel)parentRoot.Target).Children.Add(unnamedSibling); Pump();
            editor.AcceptHierarchyTarget(firstButton); Pump();
            editor.ShowInspectParent(); Pump();
            reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Tag as string) == "#group:反射控件");
            var siblingLeaf = FlattenTree(reflectGroup).First(x => { var weak = x.DataContext as WeakReference; return weak != null && ReferenceEquals(weak.Target, unnamedSibling); });
            siblingLeaf.IsSelected = true; Pump();
            Check(ReferenceEquals(typeof(RmtStyleEditor).GetMethod("Inspected", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, null), unnamedSibling), "sibling selection targets the sibling instance");
            typeof(RmtStyleEditor).GetMethod("StoreEdits", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, new object[] { new Dictionary<string, string> { { "Width", "54" } }, true }); Pump();
            Check(Math.Abs(unnamedSibling.Width - 54) < .1 && RmtCommonStyles.LayoutId(unnamedSibling) != "", "unnamed sibling selected after showing parent applies edits immediately: width=" + unnamedSibling.Width + " id=" + RmtCommonStyles.LayoutId(unnamedSibling));
            ((Button)editorRoot.FindName("CmdItemReset")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            ((Panel)parentRoot.Target).Children.Remove(unnamedSibling); Pump();
            editor.AcceptHierarchyTarget(fontCombo); Pump();
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var comboOrder = new List<string>();
            foreach (UIElement child in FlattenFields(fieldsPanel))
            {
                string heading = FieldHeading(child);
                if (!string.IsNullOrEmpty(heading)) { comboOrder.Add(heading); continue; }
                var grid = child as Grid;
                if (grid == null) continue;
                foreach (var label in grid.Children.OfType<TextBlock>())
                    if (label.Text == "示例内容" || label.Text == "选项内容" || label.Text == "展开高度" || label.Text == "圆角")
                        comboOrder.Add(label.Text);
            }
            Check(comboOrder.IndexOf("示例内容") >= 0 && comboOrder.IndexOf("选项内容") > comboOrder.IndexOf("示例内容") && comboOrder.FindIndex(t => (t ?? "").StartsWith("模版属性")) > comboOrder.IndexOf("选项内容"), "combo sample and options stay above template properties");
            Check(comboOrder.Contains("展开高度") && comboOrder.LastIndexOf("展开高度") > comboOrder.FindIndex(t => (t ?? "").StartsWith("重载属性")), "combo template and reload expose dropdown height");
            var comboOptions = (TextBox)typeof(RmtStyleEditor).GetField("previewOptions", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(comboOptions != null && comboOptions.Text.IndexOf("宋体", StringComparison.Ordinal) >= 0 && comboOptions.Text.IndexOf("黑体", StringComparison.Ordinal) >= 0, "combo option content lists live items");
            var comboPresets = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("presetInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var comboInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(comboPresets.ContainsKey("CornerRadius") && comboPresets["CornerRadius"].IsEnabled && (comboPresets["CornerRadius"].Text ?? "").IndexOf("4", StringComparison.Ordinal) >= 0, "combo corner radius shows the chrome value and can be reloaded");
            Check(comboInputs.ContainsKey("MaxDropDownHeight") && comboInputs["MaxDropDownHeight"].IsReadOnly == false, "combo dropdown height can be reloaded");
            typeof(RmtStyleEditor).GetField("interactionReady", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            comboPresets["CornerRadius"].Text = "6,6,6,6";
            typeof(RmtStyleEditor).GetMethod("Commit", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, new object[] { false });
            Pump();
            var comboChrome = RmtCommonStyles.FindControlBorder(fontCombo);
            Check(comboChrome != null && comboChrome.CornerRadius.TopLeft == 6, "combo corner radius reload updates the visible chrome");
            comboInputs["MaxDropDownHeight"].Text = "180";
            typeof(RmtStyleEditor).GetMethod("Commit", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(editor, new object[] { false });
            Pump();
            var comboDrop = RmtCommonStyles.FindComboDropDownBorder(fontCombo);
            Check(comboDrop != null && Math.Abs(comboDrop.MaxHeight - 180) < .1, "combo dropdown height reload updates the popup");
            editor.AcceptPickedControl(box); Pump();
            var pickedRoot = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRootRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var pickedRef = (WeakReference)typeof(RmtStyleEditor).GetField("inspectRef", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(pickedRoot != null && ReferenceEquals(pickedRoot.Target, box) && pickedRef != null && ReferenceEquals(pickedRef.Target, box), "control pick shows the selected control not its parent");
            reflectGroup = adjustCatalog.Items.OfType<TreeViewItem>().First(g => (g.Header as string) == "反射控件" || (g.Tag as string) == "#group:反射控件");
            reflectLeaf = reflectGroup.Items.OfType<TreeViewItem>().First();
            Check(reflectLeaf.Items.Count == 2, "control pick lists the selected control and its children");
            editor.AcceptHierarchyTarget(box); Pump();
            editor.AddTemplateFromCurrent("面板"); Pump();
            Check(RmtCommonStyles.Composites.Count >= 1, "hierarchical locate creates a composite template");
            var comboGroup = catalog.Items.OfType<TreeViewItem>().FirstOrDefault(g => (g.Header as string) == "组合模版");
            Check(comboGroup != null && comboGroup.Items.Count > 0 && comboGroup.Items.OfType<TreeViewItem>().First().Items.Count == 2, "style catalog shows hierarchical combination templates");
            var comboRoot = (TreeViewItem)comboGroup.Items[0];
            Check(comboRoot.ContextMenu != null && comboRoot.ContextMenu.Items.OfType<MenuItem>().Any(x => (x.Header as string) == "删除"), "composite template provides delete command");
            var kept = new Button { Name = "KeptStyle", Uid = "gm:ButtonTemplate1", Width = 40 };
            ((StackPanel)window.Content).Children.Add(kept); Pump();
            RmtCommonStyles.Values["ButtonTemplate1"] = new Dictionary<string, string> { { "Width", "77" } };
            RmtCommonStyles.CloneBases["ButtonTemplate1"] = "通用/Button";
            RmtCommonStyles.DisplayNames["ButtonTemplate1"] = "测试删除模版";
            RmtCommonStyles.Refresh();
            Check(Math.Abs(kept.Width - 40) < .1, "saving a named template does not alter a matching live control");
            RmtCommonStyles.InstanceStyles[RmtCommonStyles.LayoutId(kept)] = new Dictionary<string, string>(RmtCommonStyles.Values["ButtonTemplate1"]);
            RmtCommonStyles.Refresh();
            Check(Math.Abs(kept.Width - 77) < .1, "explicitly applying a template changes only the selected instance");
            editor.DeleteCatalogStyle("ButtonTemplate1"); Pump();
            Check(!RmtCommonStyles.Values.ContainsKey("ButtonTemplate1"), "deleted template is removed from the catalog store");
            var afterDelete = catalog.SelectedItem as TreeViewItem;
            var afterDeleteGroup = afterDelete == null ? null : ItemsControl.ItemsControlFromItemContainer(afterDelete) as TreeViewItem;
            Check(afterDelete != null && (afterDeleteGroup == null || (afterDeleteGroup.Tag as string) != "#group:反射控件" && (afterDeleteGroup.Header as string) != "反射控件"), "deleting a template keeps the previous catalog target selected");
            Check(Math.Abs(kept.Width - 77) < .1, "deleting a template does not change controls already using it");
            var special = (Button)window.FindName("Special");
            var input = (TextBox)window.FindName("Input"); input.SetBinding(TextBox.FontSizeProperty, new Binding("Tag") { Source = input }); input.Tag = 19.0;
            var other = new Window { Content = new Button { Content = "other" }, Width = 300, Height = 200, Opacity = 0.01, ShowInTaskbar = false };
            RmtCommonStyles.Configure(other, path + "|1"); other.Show(); Pump();
            var fontProbe = new Button { Name = "FontProbe", Content = "确定" };
            ((StackPanel)window.Content).Children.Add(fontProbe); Pump();
            Dictionary<string, string> savedButtonTemplate;
            if (RmtCommonStyles.Values.TryGetValue("通用/Button", out savedButtonTemplate))
                savedButtonTemplate = new Dictionary<string, string>(savedButtonTemplate);
            else savedButtonTemplate = null;
            RmtCommonStyles.Values.Remove("通用/Button");
            editor.AcceptHierarchyTarget(fontProbe); Pump();
            editor.ApplyReloadFromTemplate("通用/Button"); Pump();
            var probeSliders = (Dictionary<string, Slider>)typeof(RmtStyleEditor).GetField("sliderInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(probeSliders.ContainsKey("RelativeFontSize") && Math.Abs(probeSliders["RelativeFontSize"].Value) < .01, "applying the button template keeps relative font size at 0");
            if (savedButtonTemplate != null) RmtCommonStyles.Values["通用/Button"] = savedButtonTemplate;
            RmtCommonStyles.Values["通用/Button"] = new Dictionary<string, string> { { "Width", "123" }, { "Padding", "4,5,6,7" } };
            RmtCommonStyles.Values["样式/RmtItemEditBtn"] = new Dictionary<string, string> { { "Width", "88" } };
            RmtCommonStyles.Values["通用/TextBox"] = new Dictionary<string, string> { { "RelativeFontSize", "2" } };
            RmtCommonStyles.Refresh();
            Check(double.IsNaN(b.Width) && a.Width == 64, "button template definitions do not repaint existing controls");
            Check(special.Width == 31, "explicit exception retained");
            Check(input.FontSize == 19 && BindingOperations.IsDataBound(input, TextBox.FontSizeProperty), "data binding retained");
            var dynamic = new Button(); ((StackPanel)window.Content).Children.Add(dynamic); Pump();
            Check(double.IsNaN(dynamic.Width), "button templates do not affect newly created controls");
            editor.AcceptHierarchyTarget(b); Pump();
            fieldsPanel = (StackPanel)typeof(RmtStyleEditor).GetField("fields", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            reloadList = fieldsPanel.Children.OfType<DockPanel>().SelectMany(p => p.Children.OfType<StackPanel>()).SelectMany(p => p.Children.OfType<ComboBox>()).FirstOrDefault(c => c.Name == "ReloadList");
            typeof(RmtStyleEditor).GetField("interactionReady", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, true);
            var reloadBeforeApply = SectionValues(fieldsPanel, "重载属性", "不会出现的结束标记");
            reloadList.SelectedItem = reloadList.Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "样式/RmtItemEditBtn"); Pump();
            Check(SameValues(reloadBeforeApply, SectionValues(fieldsPanel, "重载属性", "不会出现的结束标记")) && double.IsNaN(b.Width), "switching to another template only updates the reload style preview");
            reloadList.SelectedItem = reloadList.Items.Cast<ComboBoxItem>().First(x => (x.Tag as string) == "通用/Button"); Pump();
            var applyReload = fieldsPanel.Children.OfType<DockPanel>().SelectMany(p => p.Children.OfType<StackPanel>()).SelectMany(p => p.Children.OfType<Button>()).First(x => x.Name == "CmdApplyReloadList");
            applyReload.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            Check(b.Width == 123 && a.Width == 64 && double.IsNaN(dynamic.Width), "applying reload list updates the located control immediately");
            var previewHost = (StackPanel)typeof(RmtStyleEditor).GetField("preview", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var previewApplied = WalkLogical(previewHost).OfType<Button>().FirstOrDefault(x => !double.IsNaN(x.Width) && Math.Abs(x.Width - 123) < .1);
            Check(previewApplied != null, "applying reload list refreshes the target style preview");
            var appliedInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            Check(appliedInputs.ContainsKey("Width") && appliedInputs["Width"].Text == "123", "applying reload list refreshes reload properties");
            // Located controls are saved when the reload list action runs.
            Check(b.Width == 123 && a.Width == 64 && double.IsNaN(dynamic.Width), "applying the common button template changes only the selected control");
            Check(RmtCommonStyles.BoundStyleKey(RmtCommonStyles.LayoutId(b)) == "通用/Button", "applying a template binds the control to that shared style");
            RmtCommonStyles.Values["通用/Button"]["Width"] = "124"; RmtCommonStyles.Refresh();
            Check(b.Width == 124 && a.Width == 64 && double.IsNaN(dynamic.Width), "shared template edits update every bound control");
            RmtCommonStyles.Values["通用/Button"]["Width"] = "123"; RmtCommonStyles.Refresh();
            var forked = new Dictionary<string, string>(RmtCommonStyles.Values["通用/Button"]);
            forked["Width"] = "150";
            string forkedKey = RmtCommonStyles.AssignControlStyle(b, forked);
            RmtCommonStyles.Refresh();
            Check(b.Width == 150 && RmtCommonStyles.IsInstanceStyle(forkedKey) && RmtCommonStyles.StyleRefCount("通用/Button") == 0, "editing one shared control forks an instance style");
            string merged = RmtCommonStyles.AssignControlStyle(b, RmtCommonStyles.Values["通用/Button"]);
            RmtCommonStyles.Refresh();
            Check(merged == "通用/Button" && !RmtCommonStyles.Values.ContainsKey(forkedKey), "identical styles merge and unused instance styles are deleted");
            editor.AcceptHierarchyTarget(a); Pump();
            editor.ApplyReloadFromTemplate("样式/RmtItemEditBtn"); Pump();
            // Applying a named template is immediate for the located control.
            Check(a.Width == 88 && b.Width == 123 && double.IsNaN(dynamic.Width), "applying a named template remains isolated to its selected control");
            Check(RmtCommonStyles.BoundStyleKey(RmtCommonStyles.LayoutId(a)) == "样式/RmtItemEditBtn" && RmtCommonStyles.BoundStyleKey(RmtCommonStyles.LayoutId(b)) == "通用/Button", "two controls keep independent shared style references");
            ((ItemsControl)window.FindName("Virtual")).Items.Add("row"); Pump();
            Check(RmtCommonStyles.Live().Count(x => x.Key == "样式/RmtItemEditBtn") >= 2, "DataTemplate row registered");
            var styled = (Button)XamlReader.Parse("<Button xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'><Button.Style><Style TargetType='Button'><Setter Property='Background' Value='#00000000'/><Setter Property='BorderBrush' Value='#FF223344'/><Setter Property='BorderThickness' Value='1'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Border x:Name='StyledBd' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' CornerRadius='3'><Grid><Rectangle Width='8' Height='8' Fill='Orange'/></Grid></Border></ControlTemplate></Setter.Value></Setter></Style></Button.Style></Button>");
            ((StackPanel)window.Content).Children.Add(styled); Pump();
            var rounded = (Button)XamlReader.Parse("<Button xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'><Button.Template><ControlTemplate TargetType='Button'><Border x:Name='BD' CornerRadius='3'/></ControlTemplate></Button.Template></Button>");
            ((StackPanel)window.Content).Children.Add(rounded); Pump();
            RmtCommonStyles.Values["样式/RmtItemEditBtn"]["CornerRadius"] = "9"; RmtCommonStyles.Refresh();
            var bd = (Border)rounded.Template.FindName("BD", rounded);
            Check(bd.CornerRadius.TopLeft == 3, "button template remains isolated from formal instances");
            RmtCommonStyles.Values["样式/RmtItemEditBtn"].Remove("CornerRadius"); RmtCommonStyles.Refresh();
            Check(bd.CornerRadius.TopLeft == 3, "button corner radius restored");
            RmtCommonStyles.Values["通用/Button"]["CornerRadius"] = "7";
            RmtCommonStyles.Values["通用/Button"]["HoverBackground"] = "#FF345678";
            RmtCommonStyles.Values["通用/Button"]["PressedBackground"] = "#FF234567";
            RmtCommonStyles.Refresh();
            Check(styled.Template.FindName("StyledBd", styled) is Border, "button overrides keep styled button template");
            RmtCommonStyles.Values["通用/Button"].Remove("CornerRadius");
            RmtCommonStyles.Values["通用/Button"].Remove("HoverBackground");
            RmtCommonStyles.Values["通用/Button"].Remove("PressedBackground");
            RmtCommonStyles.Refresh();
            var aOverride = new Dictionary<string, string>(RmtCommonStyles.Values["样式/RmtItemEditBtn"]);
            aOverride["Background"] = "#FF123456";
            RmtCommonStyles.AssignControlStyle(a, aOverride); RmtCommonStyles.Refresh();
            Check(((SolidColorBrush)a.Background).Color == Color.FromRgb(18,52,86), "local resource override applied");
            window.Resources["ActionBg"] = Brushes.Blue; RmtCommonStyles.ThemeChanged(window, "ActionBg"); Pump();
            RmtCommonStyles.Values.Remove("样式/RmtItemEditBtn"); RmtCommonStyles.Values.Remove("通用/Button"); RmtCommonStyles.Refresh();
            RmtCommonStyles.StyleBindings.Remove(RmtCommonStyles.LayoutId(a));
            RmtCommonStyles.StyleBindings.Remove(RmtCommonStyles.LayoutId(b));
            RmtCommonStyles.InstanceStyles.Remove(RmtCommonStyles.LayoutId(a));
            RmtCommonStyles.InstanceStyles.Remove(RmtCommonStyles.LayoutId(b));
            RmtCommonStyles.CollectUnusedInstances();
            RmtCommonStyles.Refresh();
            Check(a.Width == 64 && double.IsNaN(b.Width), "restore style and unset local values");
            Check(((SolidColorBrush)a.Background).Color == Colors.Blue, "reset resolves latest dynamic resource");
            window.Resources["ActionBg"] = Brushes.Blue; Pump();
            Check(((SolidColorBrush)a.Background).Color == Colors.Blue, "dynamic resource survives override reset");
            RmtCommonStyles.Values["颜色/ActionBg"] = new Dictionary<string, string> { { "Color", "#FF00FF00" } }; RmtCommonStyles.Refresh();
            Check(((SolidColorBrush)a.Background).Color == Colors.Lime, "shared color updates real control");
            window.Resources["ActionBg"] = Brushes.Purple; RmtCommonStyles.ThemeChanged(window, "ActionBg"); Pump();
            Check(((SolidColorBrush)a.Background).Color == Colors.Lime, "theme change preserves override");
            RmtCommonStyles.Values.Remove("颜色/ActionBg"); RmtCommonStyles.Refresh();
            Check(((SolidColorBrush)a.Background).Color == Colors.Purple, "color reset uses latest theme");
            RmtCommonStyles.Values["Main.Config"] = new Dictionary<string, string> { { "RelativeFontSize", "2" } }; RmtCommonStyles.Refresh();
            b.FontSize = 18; RmtCommonStyles.Refresh();
            RmtCommonStyles.Values.Remove("Main.Config"); RmtCommonStyles.Refresh();
            Check(b.FontSize == 18, "font reset uses latest application value");
            RmtCommonStyles.Values["Main.Config"] = new Dictionary<string, string> { { "RelativeFontSize", "1" } }; RmtCommonStyles.Save();
            Check(File.ReadAllText(path).Contains("Main.Config"), "configuration saved");
            RmtCommonStyles.Save(); Check(File.Exists(path + ".bak"), "atomic save backup");
            RmtCommonStyles.Values.Clear();
            typeof(RmtCommonStyles).GetMethod("Load", BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, null);
            Check(RmtCommonStyles.Values["Main.Config"]["RelativeFontSize"] == "1", "saved configuration reloads");
            editor.Close();
            RmtCommonStyles.Refresh();
            RmtCommonStyles.Open(window); Pump(); editor = app.Windows.Cast<Window>().OfType<RmtStyleEditor>().Single();
            typeof(RmtStyleEditor).GetField("selected", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(editor, "Main.Config");
            typeof(RmtStyleEditor).GetMethod("Render", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly).Invoke(editor, null);
            Pump();
            var sliders = (Dictionary<string, Slider>)typeof(RmtStyleEditor).GetField("sliderInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var editorInputs = (Dictionary<string, TextBox>)typeof(RmtStyleEditor).GetField("inputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var editorOptions = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("optionInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var editorPresets = (Dictionary<string, ComboBox>)typeof(RmtStyleEditor).GetField("presetInputs", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(editor);
            var apply = typeof(RmtStyleEditor).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic);
            Check(!editorInputs.ContainsKey("Cursor") && !editorOptions.ContainsKey("IsEnabled") && !editorOptions.ContainsKey("Visibility"), "reload properties remain on the compact template property set");
            Check(editorPresets.ContainsKey("Padding") && sliders.ContainsKey("RelativeFontSize"), "compact reload properties keep the original editable controls");
            double templateEditFontBefore = b.FontSize;
            Thickness templateEditPaddingBefore = b.Padding;
            editorPresets["Padding"].Text = "7,7,7,7";
            editorPresets["Padding"].RaiseEvent(new TextChangedEventArgs(TextBox.TextChangedEvent, UndoAction.None));
            Check(b.Padding == templateEditPaddingBefore, "editing a template padding does not refresh a matching control");
            sliders["RelativeFontSize"].Value = 3;
            Check(b.FontSize == templateEditFontBefore, "editing a template font does not refresh a matching control");
            var later = new Button { Uid = "gm:Main.Config", Content = "later" }; ((StackPanel)window.Content).Children.Add(later); Pump();
            Check(later.FontSize != window.FontSize + 3 && later.Padding.Left != 7, "automatic draft refresh does not affect later controls");
            Check((bool)apply.Invoke(editor, null) && b.FontSize == templateEditFontBefore && b.Padding == templateEditPaddingBefore,
                "saving a template keeps all matching controls unchanged");
            editor.Close(); Check(b.FontSize > 0, "closing restores a valid saved style state");
            other.Close(); window.Close();
            File.Delete(path); File.Delete(path + ".bak");
            Console.WriteLine("ALL PASS"); return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex); return 1; }
    }
}
