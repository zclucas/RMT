// =============================================================================
// Document reader support: FlowDocumentReader styling & pagination
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
    private static void HideReaderToolbar(FlowDocumentReader reader)
    {
        if (reader == null) return;
        try
        {
            reader.ApplyTemplate();
            DependencyObject contentHost = BridgeUtil.FindVisualChildByName(reader, "PART_ContentHost");
            if (contentHost != null)
            {
                DependencyObject current = contentHost;
                DependencyObject childOfReader = null;
                while (current != null && current != reader)
                {
                    childOfReader = current;
                    current = VisualTreeHelper.GetParent(current);
                }

                int childCount = VisualTreeHelper.GetChildrenCount(reader);
                for (int i = 0; i < childCount; i++)
                {
                    var child = VisualTreeHelper.GetChild(reader, i) as FrameworkElement;
                    if (child != null && child != childOfReader)
                    {
                        child.Visibility = Visibility.Collapsed;
                    }
                }

                if (childOfReader != null)
                {
                    current = contentHost;
                    DependencyObject childOfRoot = null;
                    while (current != null && current != childOfReader)
                    {
                        childOfRoot = current;
                        current = VisualTreeHelper.GetParent(current);
                    }

                    int rootChildCount = VisualTreeHelper.GetChildrenCount(childOfReader);
                    for (int i = 0; i < rootChildCount; i++)
                    {
                        var child = VisualTreeHelper.GetChild(childOfReader, i) as FrameworkElement;
                        if (child != null && child != childOfRoot)
                        {
                            child.Visibility = Visibility.Collapsed;
                        }
                    }
                }
            }
            else
            {
                HideAllToolBarsRecursive(reader);
            }
        }
        catch (Exception ex)
        {
            System.IO.File.AppendAllText(System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log"), 
                "HideReaderToolbar Exception: " + ex.ToString() + "\n");
        }
    }

    private static void HideAllToolBarsRecursive(DependencyObject obj)
    {
        if (obj == null) return;
        if (obj is System.Windows.Controls.ToolBar)
        {
            var tb = (System.Windows.Controls.ToolBar)obj;
            tb.Visibility = Visibility.Collapsed;
        }
        int count = VisualTreeHelper.GetChildrenCount(obj);
        for (int i = 0; i < count; i++)
        {
            HideAllToolBarsRecursive(VisualTreeHelper.GetChild(obj, i));
        }
    }

    private static void UpdatePageStatus(FlowDocumentReader reader, Window win)
    {
        try {
            string rtbName = reader.Name.Replace("_PageReader", "");
            var pageTxt = win.FindName(rtbName + "_PageNumberText") as TextBlock;
            var btnPrev = win.FindName(rtbName + "_BtnPrevPage") as Button;
            var btnNext = win.FindName(rtbName + "_BtnNextPage") as Button;
            
            if (pageTxt != null)
            {
                pageTxt.Text = "Page " + reader.PageNumber + " of " + reader.PageCount;
            }
            if (btnPrev != null)
            {
                btnPrev.IsEnabled = reader.CanGoToPreviousPage;
            }
            if (btnNext != null)
            {
                btnNext.IsEnabled = reader.CanGoToNextPage;
            }
        } catch {}
    }

    private static void StyleReaderVisuals(FlowDocumentReader reader, string theme, Window win)
    {
        if (reader == null) return;

        // 1. Generate and inject XAML resource styles
        try {
            string xaml = GetReaderStylesXaml(theme, win);
            var resDict = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(xaml);
            
            // Merge or replace reader's resources
            reader.Resources.MergedDictionaries.Clear();
            reader.Resources.MergedDictionaries.Add(resDict);
        }
        catch (Exception ex) {
            System.IO.File.AppendAllText(System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log"), 
                "StyleReaderVisuals XAML Parse Exception: " + ex.ToString() + "\n");
        }

        // 2. Explicitly walk the visual tree and force property overrides for maximum robustness
        try {
            reader.ApplyTemplate();
            StyleVisualTreeRecursive(reader, theme, win);
        }
        catch (Exception ex) {
            System.IO.File.AppendAllText(System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log"), 
                "StyleReaderVisuals VisualTree Walk Exception: " + ex.ToString() + "\n");
        }
    }

    private static string GetReaderStylesXaml(string theme, Window win)
    {
        string tbBg = "Transparent";
        string borderBrush = "Transparent";
        string textMain = "Black";
        string controlBg = "White";
        string accent = "#005CBA";
        string hoverBg = "#15000000";
        string activeBg = "#25000000";

        if (theme == "Dark")
        {
            tbBg = "#252526";
            borderBrush = "#3F3F46";
            textMain = "#E0E0E0";
            controlBg = "#2D2D2D";
            accent = "#007ACC";
            hoverBg = "#15FFFFFF";
            activeBg = "#25FFFFFF";
        }
        else if (theme == "Theme")
        {
            tbBg = "{DynamicResource SidebarColor}";
            borderBrush = "{DynamicResource ControlBorder}";
            textMain = "{DynamicResource TextMain}";
            controlBg = "{DynamicResource ControlBg}";
            accent = "{DynamicResource Accent}";
            
            bool isDark = true;
            try {
                var textBrush = win.TryFindResource("TextMain") as SolidColorBrush;
                if (textBrush != null)
                {
                    var c = textBrush.Color;
                    double brightness = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) / 255.0;
                    isDark = brightness > 0.5;
                }
            } catch {}
            hoverBg = isDark ? "#15FFFFFF" : "#15000000";
            activeBg = isDark ? "#25FFFFFF" : "#25000000";
        }
        else // Normal
        {
            tbBg = "#F3F3F3";
            borderBrush = "#E0E0E0";
            textMain = "#333333";
            controlBg = "#FFFFFF";
            accent = "#005CBA";
            hoverBg = "#15000000";
            activeBg = "#25000000";
        }

        string xaml = @"
<ResourceDictionary xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                    xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml"">
    <Style TargetType=""ToolBar"">
        <Setter Property=""Background"" Value=""" + tbBg + @""" />
        <Setter Property=""BorderBrush"" Value=""" + borderBrush + @""" />
        <Setter Property=""BorderThickness"" Value=""0,1,0,0"" />
    </Style>
    
    <Style TargetType=""TextBlock"">
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""FontFamily"" Value=""Segoe UI"" />
        <Setter Property=""FontSize"" Value=""12"" />
    </Style>

    <Style TargetType=""TextBox"">
        <Setter Property=""Background"" Value=""" + controlBg + @""" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderBrush"" Value=""" + borderBrush + @""" />
        <Setter Property=""BorderThickness"" Value=""1"" />
        <Setter Property=""Padding"" Value=""4,2"" />
        <Setter Property=""SelectionBrush"" Value=""" + accent + @""" />
    </Style>

    <Style TargetType=""Button"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""Button"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType=""ToggleButton"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""ToggleButton"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsChecked"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + activeBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    
    <Style TargetType=""RepeatButton"">
        <Setter Property=""Background"" Value=""Transparent"" />
        <Setter Property=""Foreground"" Value=""" + textMain + @""" />
        <Setter Property=""BorderThickness"" Value=""0"" />
        <Setter Property=""Padding"" Value=""6,4"" />
        <Setter Property=""Margin"" Value=""2,0"" />
        <Setter Property=""Cursor"" Value=""Hand"" />
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""RepeatButton"">
                    <Border x:Name=""bg"" Background=""{TemplateBinding Background}"" CornerRadius=""4"" BorderThickness=""0"" Padding=""{TemplateBinding Padding}"">
                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsMouseOver"" Value=""True"">
                            <Setter TargetName=""bg"" Property=""Background"" Value=""" + hoverBg + @""" />
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Opacity"" Value=""0.4"" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>";

        return xaml;
    }

    private static void StyleVisualTreeRecursive(DependencyObject obj, string theme, Window win)
    {
        if (obj == null) return;

        // Skip children of PART_ContentHost (the document pages)
        FrameworkElement fe = obj as FrameworkElement;
        if (fe != null && fe.Name == "PART_ContentHost")
        {
            return;
        }

        // Explicitly apply themes to elements
        System.Windows.Controls.Border border = obj as System.Windows.Controls.Border;
        if (border != null)
        {
            if (border.TemplatedParent == null || border.TemplatedParent is FlowDocumentReader)
            {
                if (theme == "Dark")
                {
                    border.Background = new SolidColorBrush(Color.FromRgb(37, 37, 38));
                    border.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                }
                else if (theme == "Theme")
                {
                    border.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "SidebarColor");
                    border.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "ControlBorder");
                }
                else
                {
                    border.Background = new SolidColorBrush(Color.FromRgb(243, 243, 243));
                    border.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                }
            }
        }
        else {
            System.Windows.Controls.ToolBar toolbar = obj as System.Windows.Controls.ToolBar;
            if (toolbar != null)
            {
                if (theme == "Dark")
                {
                    toolbar.Background = new SolidColorBrush(Color.FromRgb(37, 37, 38));
                    toolbar.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                }
                else if (theme == "Theme")
                {
                    toolbar.SetResourceReference(System.Windows.Controls.ToolBar.BackgroundProperty, "SidebarColor");
                    toolbar.SetResourceReference(System.Windows.Controls.ToolBar.BorderBrushProperty, "ControlBorder");
                }
                else
                {
                    toolbar.Background = new SolidColorBrush(Color.FromRgb(243, 243, 243));
                    toolbar.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                }
            }
            else {
                System.Windows.Controls.Button btn = obj as System.Windows.Controls.Button;
                if (btn != null)
                {
                    if (theme == "Dark")
                    {
                        btn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                    }
                    else if (theme == "Theme")
                    {
                        btn.SetResourceReference(System.Windows.Controls.Button.ForegroundProperty, "TextMain");
                    }
                    else
                    {
                        btn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                    }
                }
                else {
                    System.Windows.Controls.Primitives.ToggleButton toggleBtn = obj as System.Windows.Controls.Primitives.ToggleButton;
                    if (toggleBtn != null)
                    {
                        if (theme == "Dark")
                        {
                            toggleBtn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                        }
                        else if (theme == "Theme")
                        {
                            toggleBtn.SetResourceReference(System.Windows.Controls.Primitives.ToggleButton.ForegroundProperty, "TextMain");
                        }
                        else
                        {
                            toggleBtn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                        }
                    }
                    else {
                        System.Windows.Controls.Primitives.RepeatButton repeatBtn = obj as System.Windows.Controls.Primitives.RepeatButton;
                        if (repeatBtn != null)
                        {
                            if (theme == "Dark")
                            {
                                repeatBtn.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                            }
                            else if (theme == "Theme")
                            {
                                repeatBtn.SetResourceReference(System.Windows.Controls.Primitives.RepeatButton.ForegroundProperty, "TextMain");
                            }
                            else
                            {
                                repeatBtn.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                            }
                        }
                        else {
                            System.Windows.Controls.TextBlock textBlock = obj as System.Windows.Controls.TextBlock;
                            if (textBlock != null)
                            {
                                if (theme == "Dark")
                                {
                                    textBlock.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                }
                                else if (theme == "Theme")
                                {
                                    textBlock.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty, "TextMain");
                                }
                                else
                               {
                                    textBlock.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                                }
                            }
                            else {
                                System.Windows.Controls.TextBox textBox = obj as System.Windows.Controls.TextBox;
                                if (textBox != null)
                                {
                                    if (theme == "Dark")
                                    {
                                        textBox.Background = new SolidColorBrush(Color.FromRgb(45, 45, 45));
                                        textBox.Foreground = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                        textBox.BorderBrush = new SolidColorBrush(Color.FromRgb(63, 63, 70));
                                    }
                                    else if (theme == "Theme")
                                    {
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.BackgroundProperty, "ControlBg");
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.ForegroundProperty, "TextMain");
                                        textBox.SetResourceReference(System.Windows.Controls.TextBox.BorderBrushProperty, "ControlBorder");
                                    }
                                    else
                                    {
                                        textBox.Background = new SolidColorBrush(Color.FromRgb(255, 255, 255));
                                        textBox.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
                                        textBox.BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Traverse children
        int count = VisualTreeHelper.GetChildrenCount(obj);
        for (int i = 0; i < count; i++)
        {
            StyleVisualTreeRecursive(VisualTreeHelper.GetChild(obj, i), theme, win);
        }
    }

}
