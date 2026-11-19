// =============================================================================
// Document layout: fonts, pagination, view modes (ENABLE_DOCUMENT)
// =============================================================================
#if ENABLE_DOCUMENT

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

#if ENABLE_DOCUMENT
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
#endif
public partial class AhkWpfEngine
{
    // === Font Resolution ===
    // Static cache of installed system fonts for fast lookup
    private static System.Collections.Generic.HashSet<string> _installedFonts;
    private static string _userFontsUriStr;

    private static readonly System.Collections.Generic.Dictionary<string, string[]> _fontAliases = new System.Collections.Generic.Dictionary<string, string[]>(System.StringComparer.OrdinalIgnoreCase) {
        { "SimSun", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "宋体", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "Songti", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "NSimSun", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "新宋体", new[] { "SimSun", "宋体", "Songti", "NSimSun", "新宋体" } },
        { "Microsoft YaHei", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "微软雅黑", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "YaHei", new[] { "Microsoft YaHei", "微软雅黑", "YaHei", "Microsoft YaHei UI", "微软雅黑 UI" } },
        { "KaiTi", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "楷体", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "楷体_GB2312", new[] { "KaiTi", "楷体", "Kaiti", "KaiTi_GB2312", "楷体_GB2312" } },
        { "FangSong", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "仿宋", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "仿宋_GB2312", new[] { "FangSong", "仿宋", "Fangsong", "FangSong_GB2312", "仿宋_GB2312" } },
        { "SimHei", new[] { "SimHei", "黑体", "Heiti" } },
        { "黑体", new[] { "SimHei", "黑体", "Heiti" } },
        { "LiSu", new[] { "LiSu", "隶书", "Lishu" } },
        { "隶书", new[] { "LiSu", "隶书", "Lishu" } },
        { "YouYuan", new[] { "YouYuan", "幼圆", "Youyuan" } },
        { "幼圆", new[] { "YouYuan", "幼圆", "Youyuan" } },
        { "Times", new[] { "Times New Roman", "Georgia", "Times" } },
        { "Courier", new[] { "Courier New", "Consolas" } },
        { "Helvetica", new[] { "Arial", "Segoe UI" } },
        { "Calibri", new[] { "Calibri", "Segoe UI", "Arial" } }
    };

    private static bool IsFontInstalledWithAlias(string fontName, System.Collections.Generic.HashSet<string> installed) {
        if (string.IsNullOrEmpty(fontName)) return false;
        if (installed.Contains(fontName)) return true;
        if (_fontAliases.ContainsKey(fontName)) {
            foreach (var alias in _fontAliases[fontName]) {
                if (installed.Contains(alias)) return true;
            }
        }
        return false;
    }
    
    private static bool IsSerifFont(string fontName) {
        if (string.IsNullOrEmpty(fontName)) return false;
        string name = fontName.ToLower();
        if (name.Contains("serif") || name.Contains("roman") || name.Contains("georgia") || 
            name.Contains("times") || name.Contains("garamond") || name.Contains("bookman") || 
            name.Contains("palatino") || name.Contains("century")) {
            return true;
        }
        if (name.Contains("song") || name.Contains("ming") || name.Contains("kai") ||
            name.Contains("宋") || name.Contains("明") || name.Contains("楷") ||
            name.Contains("新細明") || name.Contains("細明") || name.Contains("报宋")) {
            return true;
        }
        return false;
    }

    private static System.Collections.Generic.HashSet<string> GetInstalledFonts() {
        if (_installedFonts == null) {
            _installedFonts = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
            
            // 1. Scan default system font families and all their localized names
            foreach (var family in System.Windows.Media.Fonts.SystemFontFamilies) {
                _installedFonts.Add(family.Source);
                try {
                    foreach (var name in family.FamilyNames.Values) {
                        _installedFonts.Add(name);
                    }
                } catch { }
            }
            
            // 2. Scan user local AppData fonts folder if it exists
            try {
                string localAppData = System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData);
                string userFontsDir = System.IO.Path.Combine(localAppData, @"Microsoft\Windows\Fonts");
                if (System.IO.Directory.Exists(userFontsDir)) {
                    _userFontsUriStr = "file:///" + userFontsDir.Replace('\\', '/').TrimEnd('/') + "/";
                    foreach (var family in System.Windows.Media.Fonts.GetFontFamilies(new Uri(_userFontsUriStr))) {
                        _installedFonts.Add(family.Source);
                        try {
                            foreach (var name in family.FamilyNames.Values) {
                                _installedFonts.Add(name);
                            }
                        } catch { }
                    }
                }
            } catch { }

            // 3. Scan system and user registry fonts to match AHK side
            foreach (var hive in new[] { Microsoft.Win32.Registry.LocalMachine, Microsoft.Win32.Registry.CurrentUser }) {
                try {
                    using (var key = hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")) {
                        if (key != null) {
                            foreach (var valName in key.GetValueNames()) {
                                string name = valName;
                                name = System.Text.RegularExpressions.Regex.Replace(name, @"\s*\((TrueType|OpenType|PostScript|Type 1|Vector|Stroke)\)$", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                                name = System.Text.RegularExpressions.Regex.Replace(name, @"\s+(Bold|Italic|Regular|Semibold|Semi-Bold|Light|Extra\s*Light|Medium|Black|Condensed|Oblique|Bold\s+Italic|Italic\s+Bold|Demibold|Heavy|Nord)\b", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                                name = name.Trim();
                                if (!string.IsNullOrEmpty(name)) {
                                    if (name.Contains("&")) {
                                        foreach (var sName in name.Split('&')) {
                                            string trimmedSub = sName.Trim();
                                            if (!string.IsNullOrEmpty(trimmedSub)) _installedFonts.Add(trimmedSub);
                                        }
                                    } else {
                                        _installedFonts.Add(name);
                                    }
                                }
                            }
                        }
                    }
                } catch { }
            }
        }
        return _installedFonts;
    }

    private System.Windows.Media.FontFamily ResolveFontFamily(string requestedFont) {
        if (string.IsNullOrEmpty(requestedFont)) return new System.Windows.Media.FontFamily("Segoe UI");
        
        var installed = GetInstalledFonts();
        var parts = requestedFont.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
        var resolvedFonts = new System.Collections.Generic.List<string>();
        
        foreach (var p in parts) {
            string fontName = p.Trim();
            if (string.IsNullOrEmpty(fontName)) continue;
            
            string resolvedName = null;
            if (installed.Contains(fontName)) {
                resolvedName = fontName;
            } else {
                if (_fontAliases.ContainsKey(fontName)) {
                    foreach (var alias in _fontAliases[fontName]) {
                        if (installed.Contains(alias)) {
                            resolvedName = alias;
                            break;
                        }
                    }
                }
            }
            
            if (resolvedName != null) {
                bool isUserFont = false;
                if (!string.IsNullOrEmpty(_userFontsUriStr)) {
                    try {
                        foreach (var family in System.Windows.Media.Fonts.GetFontFamilies(new Uri(_userFontsUriStr))) {
                            bool matched = string.Equals(family.Source, resolvedName, StringComparison.OrdinalIgnoreCase);
                            if (!matched) {
                                foreach (var name in family.FamilyNames.Values) {
                                    if (string.Equals(name, resolvedName, StringComparison.OrdinalIgnoreCase)) {
                                        matched = true;
                                        break;
                                    }
                                }
                            }
                            if (matched) {
                                resolvedFonts.Add(_userFontsUriStr + "#" + resolvedName);
                                isUserFont = true;
                                break;
                            }
                        }
                    } catch { }
                }
                if (!isUserFont) {
                    resolvedFonts.Add(resolvedName);
                }
            } else {
                resolvedFonts.Add(fontName); // Add anyway as fallback
            }
        }
        
        // Add default fallbacks based on whether the primary font is Serif
        string primaryFont = parts.Length > 0 ? parts[0].Trim() : "";
        if (IsSerifFont(primaryFont)) {
            resolvedFonts.AddRange(new[] { "Times New Roman", "SimSun", "Georgia", "PMingLiU", "KaiTi", "Segoe UI", "Segoe UI Emoji", "Segoe UI Symbol", "Arial", "Microsoft YaHei" });
        } else {
            resolvedFonts.AddRange(new[] { "Segoe UI", "Segoe UI Emoji", "Segoe UI Symbol", "Arial", "Microsoft YaHei", "SimSun", "Malgun Gothic", "Yu Gothic", "Times New Roman" });
        }
        
        // Remove duplicates while keeping order
        var uniqueFonts = new System.Collections.Generic.List<string>();
        foreach (var f in resolvedFonts) {
            if (!uniqueFonts.Contains(f)) {
                uniqueFonts.Add(f);
            }
        }
        
        string joined = string.Join(", ", uniqueFonts);
        return new System.Windows.Media.FontFamily(joined);
    }

    // === Page Break Spacer Management ===
    private static T FindParent<T>(DependencyObject child) where T : DependencyObject {
        DependencyObject parentObject = child;
        while (parentObject != null) {
            if (parentObject is T) return (T)parentObject;
            DependencyObject parentVisual = null;
            if (parentObject is Visual || parentObject is System.Windows.Media.Media3D.Visual3D) {
                parentVisual = VisualTreeHelper.GetParent(parentObject);
            }
            parentObject = parentVisual ?? LogicalTreeHelper.GetParent(parentObject);
        }
        return null;
    }

    private void LogEditorState(string context, RichTextBox rtb) {
        try {
            string debugPath = System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log");
            var sb = new StringBuilder();
            sb.AppendLine(string.Format("--- Editor State: {0} ({1:HH:mm:ss.fff}) ---", context, DateTime.Now));
            if (rtb == null) {
                sb.AppendLine("RTB is NULL");
            } else {
                sb.AppendLine(string.Format("RTB Name: {0}", rtb.Name));
                sb.AppendLine(string.Format("RTB Visibility: {0}", rtb.Visibility));
                sb.AppendLine(string.Format("RTB IsEnabled: {0}", rtb.IsEnabled));
                sb.AppendLine(string.Format("RTB IsReadOnly: {0}", rtb.IsReadOnly));
                sb.AppendLine(string.Format("RTB IsDocumentEnabled: {0}", rtb.IsDocumentEnabled));
                sb.AppendLine(string.Format("RTB Focusable: {0}", rtb.Focusable));
                sb.AppendLine(string.Format("RTB IsFocused: {0}", rtb.IsFocused));
                sb.AppendLine(string.Format("RTB IsKeyboardFocusWithin: {0}", rtb.IsKeyboardFocusWithin));
                sb.AppendLine(string.Format("RTB IsHitTestVisible: {0}", rtb.IsHitTestVisible));
                int blocksCount = -1;
                if (rtb.Document != null && rtb.Document.Blocks != null) {
                    blocksCount = rtb.Document.Blocks.Count;
                }
                sb.AppendLine(string.Format("RTB Document Blocks Count: {0}", blocksCount));
                
                DependencyObject parent = rtb;
                while (parent != null) {
                    DependencyObject parentVisual = null;
                    if (parent is Visual || parent is System.Windows.Media.Media3D.Visual3D) {
                        parentVisual = VisualTreeHelper.GetParent(parent);
                    }
                    parent = parentVisual ?? LogicalTreeHelper.GetParent(parent);
                    if (parent != null) {
                        var fe = parent as FrameworkElement;
                        sb.AppendLine(string.Format("Parent Type: {0}, Name: {1}, Visibility: {2}, IsEnabled: {3}, IsHitTestVisible: {4}", 
                            parent.GetType().Name, 
                            fe != null ? fe.Name : "N/A", 
                            fe != null ? fe.Visibility.ToString() : "N/A", 
                            fe != null ? fe.IsEnabled.ToString() : "N/A",
                            fe != null ? fe.IsHitTestVisible.ToString() : "N/A"));
                    }
                }
            }
            sb.AppendLine();
            System.IO.File.AppendAllText(debugPath, sb.ToString());
        } catch { }
    }

    private System.Collections.Generic.List<BlockUIContainer> _pageBreakSpacers
        = new System.Collections.Generic.List<BlockUIContainer>();
    private bool _isUpdatingSpacers = false;

    private void _GetLayoutBlocks(System.Windows.Documents.BlockCollection blocks, System.Collections.Generic.List<Block> flatList) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Section) {
                _GetLayoutBlocks(((System.Windows.Documents.Section)block).Blocks, flatList);
            } else {
                flatList.Add(block);
            }
        }
    }

    private double _GetActualBlockHeight(RichTextBox rtb, Block block, double availableWidth) {
        try {
            var rectStart = block.ContentStart.GetCharacterRect(LogicalDirection.Forward);
            var rectEnd = block.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
            double height = rectEnd.Bottom - rectStart.Top;
            if (height > 0 && height < 5000) {
                return height;
            }
        } catch { }
        return _EstimateBlockHeight(block, availableWidth);
    }

    private void ApplyViewMode(RichTextBox rtb, string viewMode, string currentTheme, Window win)
    {
        string rtbName = rtb.Name;
        string readerName = rtbName + "_PageReader";
        string pageBorderName = rtbName + "_PageBorder";
        string editorWrapperName = rtbName + "_EditorWrapper";

        // Use FindName for robust lookup — visual tree walking fails when parents are Collapsed
        var pageBorder = win.FindName(pageBorderName) as System.Windows.Controls.Border;
        if (pageBorder == null) pageBorder = rtb.Parent as System.Windows.Controls.Border;
        Grid editorWrapper = win.FindName(editorWrapperName) as Grid;
        
        // Find editorCanvas and editorSv by walking from pageBorder upwards via logical tree
        // (logical tree is always available even when elements are Collapsed)
        FrameworkElement editorCanvas = null;
        ScrollViewer editorSv = null;
        if (pageBorder != null) {
            // pageBorder → Grid(editorCenter) → ScrollViewer(editorSv) → Border(editorCanvas)
            var editorCenter = LogicalTreeHelper.GetParent(pageBorder) as FrameworkElement;
            editorSv = editorCenter != null ? LogicalTreeHelper.GetParent(editorCenter) as ScrollViewer : null;
            editorCanvas = editorSv != null ? LogicalTreeHelper.GetParent(editorSv) as FrameworkElement : null;
        }
        // Fallback: try visual tree if logical tree didn't work
        if (editorSv == null) {
            editorSv = FindParent<ScrollViewer>(rtb);
        }
        if (editorCanvas == null && editorSv != null) {
            editorCanvas = LogicalTreeHelper.GetParent(editorSv) as FrameworkElement;
            if (editorCanvas == null) {
                try { editorCanvas = VisualTreeHelper.GetParent(editorSv) as FrameworkElement; } catch { }
            }
        }
        if (editorWrapper == null && editorCanvas != null) {
            editorWrapper = LogicalTreeHelper.GetParent(editorCanvas) as Grid;
            if (editorWrapper == null) {
                try { editorWrapper = VisualTreeHelper.GetParent(editorCanvas) as Grid; } catch { }
            }
        }

        FlowDocumentReader reader = null;
        if (editorWrapper != null) {
            foreach (var child in editorWrapper.Children) {
                if (child is FlowDocumentReader) {
                    reader = (FlowDocumentReader)child;
                    break;
                }
            }
        }
        // Also try FindName for the reader
        if (reader == null) {
            reader = win.FindName(readerName) as FlowDocumentReader;
        }

        // Save view mode
        _docViewModes[rtbName] = viewMode;

        // If transitioning away from twoup, restore the editor's visual chain first so the RTB is fully visible and connected when Document is assigned
        if (viewMode != "twoup") {
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
        }

        // STEP 1: ALWAYS consolidate doc back to RTB first
        if (reader != null && reader.Document != null) {
            var transferDoc = reader.Document;
            reader.Document = null;
            transferDoc.ClearValue(FlowDocument.PageWidthProperty);
            transferDoc.ClearValue(FlowDocument.PageHeightProperty);
            transferDoc.PagePadding = new Thickness(60, 50, 60, 50);
            transferDoc.ClearValue(FlowDocument.BackgroundProperty);
            transferDoc.ClearValue(FlowDocument.ForegroundProperty);
            rtb.Document = transferDoc;
        }

        // If the mode is NOT twoup, remove reader from visual tree
        if (viewMode != "twoup") {
            if (editorWrapper != null) {
                var toRemove = new System.Collections.Generic.List<UIElement>();
                foreach (var child in editorWrapper.Children) {
                    if (child is FlowDocumentReader) {
                        toRemove.Add((UIElement)child);
                    }
                }
                foreach (var r in toRemove) {
                    editorWrapper.Children.Remove(r);
                    try { win.UnregisterName(((FrameworkElement)r).Name); } catch {}
                }
            }
            // Also try to unregister by name if it still exists
            try {
                var staleReader = win.FindName(readerName) as FlowDocumentReader;
                if (staleReader != null) {
                    var parentPanel = LogicalTreeHelper.GetParent(staleReader) as System.Windows.Controls.Panel;
                    if (parentPanel != null) parentPanel.Children.Remove(staleReader);
                    try { win.UnregisterName(readerName); } catch { }
                }
            } catch { }
            reader = null;
        }

        // STEP 2: Apply the requested view mode
        if (viewMode == "paper") {
            // Hide custom page nav in status bar
            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Collapsed;

            // Robustly restore the entire editor visual chain
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);

            var settings = rtb.Document.Tag as DocLayoutSettings;
            double pgW = 816;
            double pgH = 1056;
            Thickness pgPad = new Thickness(96, 72, 96, 72);
            if (settings != null) {
                pgW = settings.PageWidth;
                pgH = settings.PageHeight;
                pgPad = settings.PagePadding;
            }
            if (pageBorder != null) {
                pageBorder.Width = pgW;
                pageBorder.MinHeight = pgH;
                pageBorder.ClearValue(FrameworkElement.HeightProperty);
                pageBorder.Effect = new System.Windows.Media.Effects.DropShadowEffect {
                    BlurRadius = 15,
                    ShadowDepth = 3,
                    Opacity = 0.15,
                    Color = System.Windows.Media.Colors.Black
                };
            }

            rtb.Document.ClearValue(FlowDocument.PageWidthProperty);
            rtb.Document.ClearValue(FlowDocument.PageHeightProperty);
            rtb.Document.PagePadding = pgPad;
            rtb.Document.ClearValue(FlowDocument.BackgroundProperty);
            rtb.Document.ClearValue(FlowDocument.ForegroundProperty);

            // Insert spacers
            _InsertPageBreakSpacers(rtb, currentTheme);

            // Deferred focus and scroll restore — use multiple passes at different priorities
            rtb.Dispatcher.BeginInvoke(new Action(() => {
                _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
                if (rtb.Document != null) {
                    rtb.Document.IsEnabled = true;
                    rtb.CaretPosition = rtb.Document.ContentStart;
                }
                rtb.Focus();
                System.Windows.Input.Keyboard.Focus(rtb);
                rtb.Dispatcher.BeginInvoke(new Action(() => {
                    rtb.IsReadOnly = false;
                    rtb.Focusable = true;
                    rtb.IsEnabled = false;
                    rtb.IsEnabled = true;
                    rtb.Focus();
                    System.Windows.Input.Keyboard.Focus(rtb);
                }), System.Windows.Threading.DispatcherPriority.Input);
            }), System.Windows.Threading.DispatcherPriority.Loaded);

        } else if (viewMode == "twoup") {
            _RemovePageBreakSpacers(rtb);

            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Visible;

            if (reader == null && editorWrapper != null) {
                reader = new FlowDocumentReader();
                reader.Name = readerName;
                try { win.RegisterName(readerName, reader); } catch { }
                reader.BorderThickness = new Thickness(0);
                reader.IsFindEnabled = false;
                reader.Visibility = Visibility.Collapsed;
                // Set text rendering quality for two-page mode
                TextOptions.SetTextFormattingMode(reader, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(reader, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(reader, TextHintingMode.Fixed);
                RenderOptions.SetClearTypeHint(reader, ClearTypeHint.Enabled);
                reader.UseLayoutRounding = true;
                Grid.SetColumn(reader, 1);
                Grid.SetRow(reader, 0);

                reader.Loaded += (s, ev) => {
                    var container = win.FindName(rtbName + "_Container") as FrameworkElement;
                    string theme = (container != null && container.Tag is string) ? (string)container.Tag : "Normal";
                    StyleReaderVisuals(reader, theme, win);
                    HideReaderToolbar(reader);

                    var btnPrev = win.FindName(rtbName + "_BtnPrevPage") as Button;
                    var btnNext = win.FindName(rtbName + "_BtnNextPage") as Button;
                    if (btnPrev != null) {
                        btnPrev.Click += (s2, ev2) => System.Windows.Input.NavigationCommands.PreviousPage.Execute(null, reader);
                    }
                    if (btnNext != null) {
                        btnNext.Click += (s2, ev2) => System.Windows.Input.NavigationCommands.NextPage.Execute(null, reader);
                    }

                    var dpPageNum = System.ComponentModel.DependencyPropertyDescriptor.FromProperty(FlowDocumentReader.PageNumberProperty, typeof(FlowDocumentReader));
                    if (dpPageNum != null) {
                        dpPageNum.AddValueChanged(reader, (s2, ev2) => UpdatePageStatus(reader, win));
                    }
                    var dpPageCount = System.ComponentModel.DependencyPropertyDescriptor.FromProperty(FlowDocumentReader.PageCountProperty, typeof(FlowDocumentReader));
                    if (dpPageCount != null) {
                        dpPageCount.AddValueChanged(reader, (s2, ev2) => UpdatePageStatus(reader, win));
                    }

                    UpdatePageStatus(reader, win);
                };

                editorWrapper.Children.Add(reader);
            }

            if (reader != null) {
                var doc = rtb.Document;
                rtb.Document = new FlowDocument();
                reader.Document = doc;

                double pgW = 816;
                double pgH = 1056;
                Thickness pgPad = new Thickness(96, 72, 96, 72);
                var settings = doc.Tag as DocLayoutSettings;
                if (settings != null) {
                    pgW = settings.PageWidth;
                    pgH = settings.PageHeight;
                    pgPad = settings.PagePadding;
                }
                doc.PageWidth = pgW;
                doc.PageHeight = pgH;
                doc.PagePadding = pgPad;
                doc.ColumnWidth = double.MaxValue;
                
                // Set text rendering quality on the document itself
                TextOptions.SetTextFormattingMode(doc, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(doc, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(doc, TextHintingMode.Fixed);
                // Also ensure the reader has these settings
                TextOptions.SetTextFormattingMode(reader, TextFormattingMode.Ideal);
                TextOptions.SetTextRenderingMode(reader, TextRenderingMode.ClearType);
                TextOptions.SetTextHintingMode(reader, TextHintingMode.Fixed);
                RenderOptions.SetClearTypeHint(reader, ClearTypeHint.Enabled);
                reader.UseLayoutRounding = true;

                if (currentTheme == "Dark") {
                    reader.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 30));
                    doc.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(38, 38, 38));
                    doc.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
                } else if (currentTheme == "Theme") {
                    reader.SetResourceReference(FlowDocumentReader.BackgroundProperty, "DropdownBg");
                    doc.SetResourceReference(FlowDocument.BackgroundProperty, "ControlBg");
                    doc.SetResourceReference(FlowDocument.ForegroundProperty, "TextMain");
                } else {
                    reader.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(230, 230, 230));
                    doc.Background = System.Windows.Media.Brushes.White;
                    doc.Foreground = System.Windows.Media.Brushes.Black;
                }

                if (editorCanvas != null) editorCanvas.Visibility = Visibility.Collapsed;
                reader.Visibility = Visibility.Visible;
                reader.ViewingMode = FlowDocumentReaderViewingMode.TwoPage;

                StyleReaderVisuals(reader, currentTheme, win);
                HideReaderToolbar(reader);
                UpdatePageStatus(reader, win);
            }

        } else {
            // Feed View
            var statusPageNav = win.FindName(rtbName + "_StatusPageNav") as FrameworkElement;
            if (statusPageNav != null) statusPageNav.Visibility = Visibility.Collapsed;

            // Robustly restore the entire editor visual chain
            _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);

            if (pageBorder != null) {
                var settings = rtb.Document.Tag as DocLayoutSettings;
                double pgW = 816;
                double pgH = 1056;
                Thickness pgPad = new Thickness(96, 72, 96, 72);
                if (settings != null) {
                    pgW = settings.PageWidth;
                    pgH = settings.PageHeight;
                    pgPad = settings.PagePadding;
                }
                pageBorder.Width = pgW;
                pageBorder.MinHeight = pgH;
                pageBorder.Effect = null;
            }

            _RemovePageBreakSpacers(rtb);

            rtb.Document.ClearValue(FlowDocument.PageWidthProperty);
            rtb.Document.ClearValue(FlowDocument.PageHeightProperty);
            rtb.Document.PagePadding = new Thickness(60, 50, 60, 50);
            rtb.Document.ClearValue(FlowDocument.BackgroundProperty);
            rtb.Document.ClearValue(FlowDocument.ForegroundProperty);

            // Deferred focus and scroll restore — use multiple passes at different priorities
            rtb.Dispatcher.BeginInvoke(new Action(() => {
                _RestoreEditorChain(rtb, pageBorder, editorSv, editorCanvas);
                if (rtb.Document != null) {
                    rtb.Document.IsEnabled = true;
                    rtb.CaretPosition = rtb.Document.ContentStart;
                }
                rtb.Focus();
                System.Windows.Input.Keyboard.Focus(rtb);
                rtb.Dispatcher.BeginInvoke(new Action(() => {
                    rtb.IsReadOnly = false;
                    rtb.Focusable = true;
                    rtb.IsEnabled = false;
                    rtb.IsEnabled = true;
                    rtb.Focus();
                    System.Windows.Input.Keyboard.Focus(rtb);
                }), System.Windows.Threading.DispatcherPriority.Input);
            }), System.Windows.Threading.DispatcherPriority.Loaded);
        }
    }

    // Robustly restore the entire editor visual chain from RTB up through all ancestors
    private static void _RestoreEditorChain(RichTextBox rtb, System.Windows.Controls.Border pageBorder, ScrollViewer editorSv, FrameworkElement editorCanvas) {
        // Force every element in the chain to Visible + Enabled + HitTestVisible
        // Walk from the innermost (RTB) outward
        _ForceElementVisible(rtb);
        rtb.IsReadOnly = false;
        rtb.IsDocumentEnabled = false;
        rtb.Focusable = true;
        rtb.AllowDrop = true;
        // Clear any stale UIElement properties
        rtb.ClearValue(UIElement.IsHitTestVisibleProperty);
        rtb.ClearValue(UIElement.FocusableProperty);
        rtb.ClearValue(UIElement.IsEnabledProperty);
        
        if (pageBorder != null) _ForceElementVisible(pageBorder);
        
        // editorCenter (the Grid between pageBorder and ScrollViewer)
        if (pageBorder != null) {
            var editorCenter = LogicalTreeHelper.GetParent(pageBorder) as FrameworkElement;
            if (editorCenter != null) _ForceElementVisible(editorCenter);
        }
        
        if (editorSv != null) {
            _ForceElementVisible(editorSv);
            // Explicitly restore scroll bar visibility in case it was altered
            editorSv.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            editorSv.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            editorSv.CanContentScroll = true;
            editorSv.ClearValue(UIElement.IsHitTestVisibleProperty);
            // Force ScrollViewer to recalculate scroll extents
            editorSv.InvalidateScrollInfo();
            editorSv.InvalidateMeasure();
            editorSv.InvalidateArrange();
        }
        
        if (editorCanvas != null) {
            _ForceElementVisible(editorCanvas);
            // Force layout recalculation
            editorCanvas.InvalidateMeasure();
            editorCanvas.InvalidateArrange();
        }
        
        // Walk up the entire visual tree from RTB and force everything visible + enabled
        DependencyObject current = rtb;
        int maxDepth = 20;
        while (current != null && maxDepth-- > 0) {
            if (current is FrameworkElement) {
                var fe = (FrameworkElement)current;
                fe.Visibility = Visibility.Visible;
                fe.IsEnabled = true;
                fe.IsHitTestVisible = true;
            }
            try { current = VisualTreeHelper.GetParent(current); } catch { break; }
        }
    }
    
    private static void _ForceElementVisible(FrameworkElement el) {
        if (el == null) return;
        el.Visibility = Visibility.Visible;
        el.IsEnabled = true;
        el.IsHitTestVisible = true;
        el.ClearValue(UIElement.IsEnabledProperty);
    }

    // Walk the logical tree from the caret to find the enclosing TableCell
    private static System.Windows.Documents.TableCell FindTableCellAtCaret(RichTextBox rtb) {
        try {
            var pos = rtb.CaretPosition;
            if (pos == null) return null;
            DependencyObject parent = pos.Parent;
            int maxDepth = 20;
            while (parent != null && maxDepth-- > 0) {
                if (parent is System.Windows.Documents.TableCell)
                    return (System.Windows.Documents.TableCell)parent;
                parent = LogicalTreeHelper.GetParent(parent);
            }
        } catch { }
        return null;
    }

    // WPF-native color picker dialog — shows a grid of preset colors + custom RGB sliders
    private static System.Windows.Media.Color? ShowColorPickerDialog(Window owner) {
        System.Windows.Media.Color? result = null;
        var dlg = new Window();
        dlg.Title = "Choose Color";
        dlg.Width = 380;
        dlg.Height = 400;
        dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        dlg.Owner = owner;
        dlg.ResizeMode = ResizeMode.NoResize;
        dlg.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 30));

        var mainPanel = new StackPanel { Margin = new Thickness(12) };

        // Title
        var title = new TextBlock { Text = "Select a Color", FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = System.Windows.Media.Brushes.White, Margin = new Thickness(0, 0, 0, 8) };
        mainPanel.Children.Add(title);

        // Preset colors grid
        string[] presets = { "#000000", "#333333", "#555555", "#888888", "#AAAAAA", "#CCCCCC", "#EEEEEE", "#FFFFFF",
                             "#FF0000", "#FF4500", "#FF8C00", "#FFD700", "#FFFF00", "#9ACD32", "#32CD32", "#008000",
                             "#00CED1", "#4169E1", "#0000FF", "#8A2BE2", "#9932CC", "#FF1493", "#FF69B4", "#FFC0CB",
                             "#800000", "#A0522D", "#DAA520", "#808000", "#006400", "#008080", "#000080", "#4B0082",
                             "#F0E68C", "#FAEBD7", "#FFE4C4", "#FFDEAD", "#DEB887", "#D2B48C", "#BC8F8F", "#CD853F" };

        var grid = new System.Windows.Controls.WrapPanel { Margin = new Thickness(0, 4, 0, 8) };
        var preview = new System.Windows.Controls.Border {
            Width = double.NaN, Height = 36, Margin = new Thickness(0, 8, 0, 4),
            CornerRadius = new CornerRadius(4),
            Background = System.Windows.Media.Brushes.White,
            BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(80, 80, 80)),
            BorderThickness = new Thickness(1)
        };

        byte rVal = 0, gVal = 0, bVal = 0;

        // RGB Sliders
        var sliderPanel = new StackPanel { Margin = new Thickness(0, 4, 0, 0) };
        var rSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var gSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var bSlider = new Slider { Minimum = 0, Maximum = 255, Value = 0, Margin = new Thickness(0, 2, 0, 2) };
        var rLabel = new TextBlock { Text = "R: 0", Foreground = System.Windows.Media.Brushes.LightCoral, FontSize = 11 };
        var gLabel = new TextBlock { Text = "G: 0", Foreground = System.Windows.Media.Brushes.LightGreen, FontSize = 11 };
        var bLabel = new TextBlock { Text = "B: 0", Foreground = System.Windows.Media.Brushes.LightBlue, FontSize = 11 };

        Action updatePreview = () => {
            rVal = (byte)rSlider.Value; gVal = (byte)gSlider.Value; bVal = (byte)bSlider.Value;
            preview.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(rVal, gVal, bVal));
            rLabel.Text = "R: " + rVal; gLabel.Text = "G: " + gVal; bLabel.Text = "B: " + bVal;
        };
        rSlider.ValueChanged += (s, e) => updatePreview();
        gSlider.ValueChanged += (s, e) => updatePreview();
        bSlider.ValueChanged += (s, e) => updatePreview();

        foreach (string hex in presets) {
            var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex);
            var swatch = new System.Windows.Controls.Border {
                Width = 28, Height = 28, Margin = new Thickness(2),
                Background = new System.Windows.Media.SolidColorBrush(color),
                BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(60, 60, 60)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(3),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            var capturedColor = color;
            swatch.MouseLeftButtonDown += (s, e) => {
                rSlider.Value = capturedColor.R;
                gSlider.Value = capturedColor.G;
                bSlider.Value = capturedColor.B;
            };
            grid.Children.Add(swatch);
        }
        mainPanel.Children.Add(grid);
        mainPanel.Children.Add(preview);

        sliderPanel.Children.Add(rLabel); sliderPanel.Children.Add(rSlider);
        sliderPanel.Children.Add(gLabel); sliderPanel.Children.Add(gSlider);
        sliderPanel.Children.Add(bLabel); sliderPanel.Children.Add(bSlider);
        mainPanel.Children.Add(sliderPanel);

        // OK / Cancel buttons
        var btnPanel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var okBtn = new System.Windows.Controls.Button { Content = "OK", Width = 80, Height = 30, Margin = new Thickness(4, 0, 0, 0) };
        var cancelBtn = new System.Windows.Controls.Button { Content = "Cancel", Width = 80, Height = 30, Margin = new Thickness(4, 0, 0, 0) };
        okBtn.Click += (s, e) => { result = System.Windows.Media.Color.FromRgb(rVal, gVal, bVal); dlg.DialogResult = true; };
        cancelBtn.Click += (s, e) => { dlg.DialogResult = false; };
        btnPanel.Children.Add(cancelBtn);
        btnPanel.Children.Add(okBtn);
        mainPanel.Children.Add(btnPanel);

        dlg.Content = mainPanel;
        dlg.ShowDialog();
        return result;
    }

    // Sends the spell check state, active language, and custom dictionaries back to AHK via event routing
    private void SendSpellCheckInfo(RichTextBox rtb, string winId, string ctrlName) {
        try {
            bool isEnabled = rtb.SpellCheck.IsEnabled;
            string configLang = "en-US";
            if (_spellCheckLangs.ContainsKey(rtb.Name)) {
                configLang = _spellCheckLangs[rtb.Name];
            } else if (rtb.Language != null) {
                configLang = rtb.Language.ToString();
            }

            string currentLang = "Unknown";
            try {
                var scLang = rtb.Language;
                if (scLang != null) {
                    try {
                        var ci = new System.Globalization.CultureInfo(scLang.ToString());
                        currentLang = ci.DisplayName + " (" + ci.Name + ")";
                    } catch {
                        currentLang = scLang.ToString();
                    }
                    if (_spellCheckLangs.ContainsKey(rtb.Name) && _spellCheckLangs[rtb.Name] == "auto") {
                        currentLang += " (Autodetected)";
                    }
                }
            } catch { }

            string spellingDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Spelling");
            var dicts = new System.Collections.Generic.List<string>();
            try {
                if (System.IO.Directory.Exists(spellingDir)) {
                    foreach (var dir in System.IO.Directory.GetDirectories(spellingDir)) {
                        string langName = System.IO.Path.GetFileName(dir);
                        foreach (var f in System.IO.Directory.GetFiles(dir, "*.dic")) {
                            dicts.Add("📘 " + langName + " - " + System.IO.Path.GetFileName(f));
                        }
                        foreach (var f in System.IO.Directory.GetFiles(dir, "*.lex")) {
                            dicts.Add("📗 " + langName + " - " + System.IO.Path.GetFileName(f));
                        }
                    }
                }
            } catch { }
            try {
                foreach (var uriObj in rtb.SpellCheck.CustomDictionaries) {
                    var uri = uriObj as Uri;
                    dicts.Add("📙 Custom: " + (uri != null ? uri.LocalPath : uriObj.ToString()));
                }
            } catch { }

            string dictsJson = string.Join("|", dicts);
            string payload = isEnabled.ToString().ToLower() + "," + configLang + "," + currentLang + "," + dictsJson;
            SendToAhk("EVENT|" + winId + "|" + ctrlName + "|SpellCheckInfo|" + BridgeUtil.LengthPrefix(payload) + "\n");
        } catch { }
    }

    private FlowDocument GetActiveDocument(RichTextBox rtb) {
        try {
            var pageReader = win.FindName(rtb.Name + "_PageReader") as FlowDocumentReader;
            if (pageReader != null && pageReader.Document != null && pageReader.Visibility == Visibility.Visible) {
                return pageReader.Document;
            }
        } catch { }
        return rtb.Document;
    }

    private string DetectLanguage(RichTextBox rtb) {
        try {
            FlowDocument activeDoc = GetActiveDocument(rtb);
            TextRange range = new TextRange(activeDoc.ContentStart, activeDoc.ContentEnd);
            string text = range.Text;
            if (string.IsNullOrWhiteSpace(text)) return "en-US";
            
            // Check for Chinese characters first (CJK Unified Ideographs: 4E00-9FFF)
            int cjkCount = 0;
            int totalCheck = Math.Min(text.Length, 2000);
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if (c >= 0x4E00 && c <= 0x9FFF) {
                    cjkCount++;
                }
            }
            if (cjkCount > totalCheck * 0.05) {
                return "zh-CN";
            }
            
            // Check for Cyrillic (Russian) (0400-04FF)
            int cyrillicCount = 0;
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if (c >= 0x0400 && c <= 0x04FF) {
                    cyrillicCount++;
                }
            }
            if (cyrillicCount > totalCheck * 0.1) {
                return "ru-RU";
            }
            
            // Check for Japanese (Hiragana/Katakana: 3040-309F / 30A0-30FF)
            int jpCount = 0;
            for (int i = 0; i < totalCheck; i++) {
                char c = text[i];
                if ((c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF)) {
                    jpCount++;
                }
            }
            if (jpCount > totalCheck * 0.05) {
                return "ja-JP";
            }
            
            // European languages stopwords frequency check
            string[] words = text.ToLower().Split(new[] { ' ', '\r', '\n', '\t', '.', ',', ';', '!', '?' }, StringSplitOptions.RemoveEmptyEntries);
            int enCount = 0;
            int frCount = 0;
            int deCount = 0;
            int esCount = 0;
            
            int wordLimit = Math.Min(words.Length, 200);
            for (int i = 0; i < wordLimit; i++) {
                string w = words[i];
                if (w == "the" || w == "and" || w == "of" || w == "to" || w == "is" || w == "that" || w == "in") enCount++;
                else if (w == "le" || w == "la" || w == "les" || w == "et" || w == "un" || w == "une" || w == "dans") frCount++;
                else if (w == "der" || w == "die" || w == "das" || w == "und" || w == "ist" || w == "in" || w == "zu") deCount++;
                else if (w == "el" || w == "la" || w == "los" || w == "y" || w == "en" || w == "un" || w == "una") esCount++;
            }
            
            if (frCount > enCount && frCount > deCount && frCount > esCount) return "fr-FR";
            if (deCount > enCount && deCount > frCount && deCount > esCount) return "de-DE";
            if (esCount > enCount && esCount > frCount && esCount > deCount) return "es-ES";
            
            return "en-US";
        } catch {
            return "en-US";
        }
    }

    private void _InsertPageBreakSpacers(RichTextBox rtb, string theme) {
        if (_isUpdatingSpacers) return;
        _isUpdatingSpacers = true;
        
        TextPointer caretPtr = null;
        try { caretPtr = rtb.CaretPosition; } catch { }
        
        rtb.BeginChange();
        try {
            _RemovePageBreakSpacers(rtb);
            _UnsplitParagraphs(rtb); // Rejoin any previously split paragraphs
            
            // Force visual layout pass to make character bounds queryable
            rtb.UpdateLayout();
            
            var doc = rtb.Document;
            var settings = doc.Tag as DocLayoutSettings;
            double pgW = 816;
            double pgH = 1056;
            Thickness pgPad = new Thickness(96, 72, 96, 72);
            if (settings != null) {
                pgW = settings.PageWidth;
                pgH = settings.PageHeight;
                pgPad = settings.PagePadding;
            }
            double pageContentHeight = pgH - (pgPad.Top + pgPad.Bottom);
            double availableWidth = pgW - (pgPad.Left + pgPad.Right);

            // Get document's first content Y position as origin
            double docOriginY = 0;
            try {
                var docStartRect = doc.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                if (!docStartRect.IsEmpty && !double.IsInfinity(docStartRect.Top)) {
                    docOriginY = docStartRect.Top;
                }
            } catch { }

            // Gap visuals between pages
            double gapHeight = 40;
            double gapMargin = 10;
            double totalGapSize = gapHeight + gapMargin * 2; // 60px total

            // We need to iterate and potentially modify blocks, so we do multiple passes
            // Each pass: find the FIRST block that overflows, split/break it, insert spacer, re-layout
            int maxPasses = 100; // Safety limit
            int passCount = 0;
            double nextPageBreakY = docOriginY + pageContentHeight;
            int pageNumber = 1;

            while (passCount < maxPasses) {
                passCount++;
                var flatList = new System.Collections.Generic.List<Block>();
                _GetLayoutBlocks(doc.Blocks, flatList);

                Block overflowBlock = null;
                double overflowBlockTop = 0;
                double overflowBlockBottom = 0;
                double prevBottom = docOriginY;

                int startIndex = 0;
                if (_pageBreakSpacers.Count > 0) {
                    var lastSpacer = _pageBreakSpacers[_pageBreakSpacers.Count - 1];
                    int foundIdx = flatList.IndexOf(lastSpacer);
                    if (foundIdx != -1) {
                        startIndex = foundIdx + 1;
                    }
                }

                for (int idx = startIndex; idx < flatList.Count; idx++) {
                    var block = flatList[idx];
                    if (block is BlockUIContainer && (((BlockUIContainer)block).Tag as string) == "__PageBreakSpacer__") {
                        // Skip spacers — they are already positioned
                        continue;
                    }

                    double blockTop = 0;
                    double blockBottom = 0;
                    bool gotBounds = false;
                    try {
                        var rectStart = block.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                        var rectEnd = block.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
                        if (!rectStart.IsEmpty && !rectEnd.IsEmpty &&
                            !double.IsInfinity(rectStart.Top) && !double.IsInfinity(rectEnd.Bottom)) {
                            blockTop = rectStart.Top;
                            blockBottom = rectEnd.Bottom;
                            try {
                                blockTop -= block.Margin.Top;
                                blockBottom += block.Margin.Bottom;
                            } catch { }
                            gotBounds = true;
                        }
                    } catch { }

                    if (!gotBounds) {
                        double est = _EstimateBlockHeight(block, availableWidth);
                        blockTop = prevBottom;
                        blockBottom = blockTop + est;
                    }

                    // Case 1: Block SPANS the page boundary (starts before, ends after)
                    if (blockBottom > nextPageBreakY && blockTop < nextPageBreakY) {
                        overflowBlock = block;
                        overflowBlockTop = blockTop;
                        overflowBlockBottom = blockBottom;
                        break;
                    }
                    // Case 2: Block starts AFTER the page boundary entirely
                    // (the gap between previous content and this block crosses the boundary)
                    if (blockTop >= nextPageBreakY) {
                        overflowBlock = block;
                        overflowBlockTop = blockTop;
                        overflowBlockBottom = blockBottom;
                        break;
                    }
                    prevBottom = blockBottom;
                }

                if (overflowBlock == null) break; // No more overflows — done

                // We found a block that crosses the page boundary.
                // Try to split it at the line level if it's a Paragraph.
                pageNumber++;
                bool didSplit = false;

                if (overflowBlock is System.Windows.Documents.Paragraph) {
                    var para = (System.Windows.Documents.Paragraph)overflowBlock;
                    // Walk lines to find the split point
                    TextPointer splitPoint = _FindLineSplitPoint(para, nextPageBreakY);

                    if (splitPoint != null) {
                        // Split the paragraph at this line boundary
                        var secondHalf = _SplitParagraphAtPointer(para, splitPoint);
                        if (secondHalf != null) {
                            // Calculate remaining space on current page
                            double remainingSpace = 0;
                            try {
                                var newEndRect = para.ContentEnd.GetCharacterRect(LogicalDirection.Backward);
                                if (!newEndRect.IsEmpty && !double.IsInfinity(newEndRect.Bottom)) {
                                    remainingSpace = Math.Max(0, nextPageBreakY - newEndRect.Bottom);
                                }
                            } catch { }

                            // Insert spacer after the first half, then the second half after the spacer
                            var spacer = _CreatePageBreakSpacer(theme, pageNumber, remainingSpace);
                            try {
                                var siblings = para.SiblingBlocks;
                                if (siblings != null) {
                                    siblings.InsertAfter(para, spacer);
                                    siblings.InsertAfter(spacer, secondHalf);
                                    _pageBreakSpacers.Add(spacer);
                                    _splitParagraphs.Add(secondHalf); // Track for unsplitting later
                                    didSplit = true;
                                }
                            } catch { }
                        }
                    }
                }

                if (!didSplit) {
                    // Could not split (not a Paragraph, or split failed)
                    // Fall back: insert spacer BEFORE the block
                    double remainingSpace = Math.Max(0, nextPageBreakY - prevBottom);
                    var spacer = _CreatePageBreakSpacer(theme, pageNumber, remainingSpace);
                    try {
                        var siblings = overflowBlock.SiblingBlocks;
                        if (siblings != null) {
                            siblings.InsertBefore(overflowBlock, spacer);
                            _pageBreakSpacers.Add(spacer);
                        }
                    } catch { }
                }

                // Re-layout and recalculate next page break
                // One UpdateLayout call ensures the newly inserted spacer and split paragraphs
                // have valid layout information for GetCharacterRect queries
                rtb.UpdateLayout();
                // Find the actual Y position of the next page's start by locating
                // the first content block after the last spacer we inserted
                bool foundNextStart = false;
                var lastInsertedSpacer = _pageBreakSpacers[_pageBreakSpacers.Count - 1];
                Block nextContentBlock = lastInsertedSpacer.NextBlock;
                // Skip any spacer blocks
                while (nextContentBlock != null && nextContentBlock is BlockUIContainer &&
                       (((BlockUIContainer)nextContentBlock).Tag as string) == "__PageBreakSpacer__") {
                    nextContentBlock = nextContentBlock.NextBlock;
                }
                if (nextContentBlock != null) {
                    try {
                        var ncRect = nextContentBlock.ContentStart.GetCharacterRect(LogicalDirection.Forward);
                        if (!ncRect.IsEmpty && !double.IsInfinity(ncRect.Top)) {
                            // Account for top margin
                            double pageStartY = ncRect.Top;
                            try { pageStartY -= nextContentBlock.Margin.Top; } catch { }
                            nextPageBreakY = pageStartY + pageContentHeight;
                            foundNextStart = true;
                        }
                    } catch { }
                }
                if (!foundNextStart) {
                    // Fallback: just advance by one page from current boundary
                    nextPageBreakY += pageContentHeight + totalGapSize;
                }
            }
        } catch (Exception ex) {
            string debugPath = System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log");
            System.IO.File.AppendAllText(debugPath, string.Format("InsertSpacers ERROR: {0}\n", ex.ToString()));
        } finally {
            rtb.EndChange();
            _isUpdatingSpacers = false;
            if (caretPtr != null) {
                try { rtb.CaretPosition = caretPtr; } catch { }
            }
        }
    }

    // Find the TextPointer at the start of the first line that overflows the page boundary
    private TextPointer _FindLineSplitPoint(System.Windows.Documents.Paragraph para, double pageBreakY) {
        try {
            TextPointer lineStart = para.ContentStart.GetLineStartPosition(0);
            if (lineStart == null) lineStart = para.ContentStart;
            TextPointer lastGoodLine = null;

            int safetyLimit = 500;
            int lineCount = 0;
            while (lineStart != null && lineStart.CompareTo(para.ContentEnd) < 0 && lineCount < safetyLimit) {
                lineCount++;
                var lineRect = lineStart.GetCharacterRect(LogicalDirection.Forward);
                if (!lineRect.IsEmpty && !double.IsInfinity(lineRect.Top)) {
                    if (lineRect.Top >= pageBreakY) {
                        // This line starts at or past the page boundary — split here
                        return lineStart;
                    }
                    lastGoodLine = lineStart;
                }
                var nextLine = lineStart.GetLineStartPosition(1);
                if (nextLine == null || nextLine.CompareTo(lineStart) == 0) break;
                lineStart = nextLine;
            }
        } catch { }
        return null;
    }

    // Split a paragraph at a given TextPointer, returning the second half as a new Paragraph
    private System.Windows.Documents.Paragraph _SplitParagraphAtPointer(System.Windows.Documents.Paragraph para, TextPointer splitPoint) {
        try {
            // Verify split point is within the paragraph
            if (splitPoint.CompareTo(para.ContentStart) <= 0 || splitPoint.CompareTo(para.ContentEnd) >= 0)
                return null;

            var newPara = new System.Windows.Documents.Paragraph();
            // Copy paragraph-level formatting
            try { newPara.Margin = para.Margin; } catch { }
            try { newPara.LineHeight = para.LineHeight; } catch { }
            try { newPara.LineStackingStrategy = para.LineStackingStrategy; } catch { }
            try { newPara.TextAlignment = para.TextAlignment; } catch { }
            try { newPara.FontFamily = para.FontFamily; } catch { }
            try { newPara.FontSize = para.FontSize; } catch { }
            try { newPara.FontWeight = para.FontWeight; } catch { }
            try { newPara.FontStyle = para.FontStyle; } catch { }
            try { newPara.Foreground = para.Foreground; } catch { }
            try { newPara.Background = para.Background; } catch { }
            try { newPara.FlowDirection = para.FlowDirection; } catch { }
            try { newPara.TextIndent = para.TextIndent; } catch { }
            // Don't copy margin top for the second half (it's a continuation)
            newPara.Margin = new Thickness(para.Margin.Left, 0, para.Margin.Right, para.Margin.Bottom);
            // First half loses bottom margin
            para.Margin = new Thickness(para.Margin.Left, para.Margin.Top, para.Margin.Right, 0);

            // Snapshot the inlines list
            var allInlines = new System.Collections.Generic.List<Inline>();
            foreach (var il in para.Inlines) {
                allInlines.Add(il);
            }

            bool foundSplit = false;
            var inlinesToMove = new System.Collections.Generic.List<Inline>();

            for (int i = 0; i < allInlines.Count; i++) {
                var inline = allInlines[i];

                if (!foundSplit) {
                    // Check if split point is within or before this inline
                    if (splitPoint.CompareTo(inline.ElementEnd) <= 0) {
                        foundSplit = true;

                        if (inline is System.Windows.Documents.Run && splitPoint.CompareTo(inline.ContentStart) > 0) {
                            // Split point is INSIDE this Run
                            var run = (System.Windows.Documents.Run)inline;
                            string textBefore = new TextRange(run.ContentStart, splitPoint).Text;
                            string fullText = run.Text;
                            string textAfter = "";
                            if (textBefore.Length < fullText.Length) {
                                textAfter = fullText.Substring(textBefore.Length);
                            }

                            if (textAfter.Length > 0) {
                                run.Text = textBefore;
                                var newRun = new System.Windows.Documents.Run(textAfter);
                                _CopyRunFormatting(run, newRun);
                                newPara.Inlines.Add(newRun);
                            }
                        } else {
                            // Split point is at or before this inline — move entire inline
                            inlinesToMove.Add(inline);
                        }
                    }
                    // else: this inline is entirely before the split point — keep it
                } else {
                    // This inline is after the split — move it
                    inlinesToMove.Add(inline);
                }
            }

            // Move inlines to new paragraph
            foreach (var il in inlinesToMove) {
                try {
                    para.Inlines.Remove(il);
                    newPara.Inlines.Add(il);
                } catch { }
            }

            if (newPara.Inlines.Count == 0 && new TextRange(newPara.ContentStart, newPara.ContentEnd).Text.Length == 0) {
                return null; // Nothing to split
            }

            return newPara;
        } catch {
            return null;
        }
    }

    private void _CopyRunFormatting(System.Windows.Documents.Run source, System.Windows.Documents.Run target) {
        try { target.FontFamily = source.FontFamily; } catch { }
        try { target.FontSize = source.FontSize; } catch { }
        try { target.FontWeight = source.FontWeight; } catch { }
        try { target.FontStyle = source.FontStyle; } catch { }
        try { target.Foreground = source.Foreground; } catch { }
        try { target.Background = source.Background; } catch { }
        try { target.TextDecorations = source.TextDecorations; } catch { }
        try { target.FlowDirection = source.FlowDirection; } catch { }
    }

    // Track split paragraphs for unsplitting when re-paginating
    private System.Collections.Generic.List<Block> _splitParagraphs = new System.Collections.Generic.List<Block>();

    private void _UnsplitParagraphs(RichTextBox rtb) {
        // Re-join previously split paragraphs: merge second half back into first half
        foreach (var block in _splitParagraphs) {
            try {
                if (block is System.Windows.Documents.Paragraph) {
                    var secondHalf = (System.Windows.Documents.Paragraph)block;
                    // Find the paragraph before the spacer before this one
                    var prevBlock = secondHalf.PreviousBlock;
                    if (prevBlock != null && prevBlock is BlockUIContainer && 
                        (((BlockUIContainer)prevBlock).Tag as string) == "__PageBreakSpacer__") {
                        var spacer = prevBlock;
                        var firstHalf = spacer.PreviousBlock as System.Windows.Documents.Paragraph;
                        if (firstHalf != null) {
                            // Move all inlines from secondHalf back to firstHalf
                            var inlines = new System.Collections.Generic.List<Inline>();
                            foreach (var il in secondHalf.Inlines) {
                                inlines.Add(il);
                            }
                            foreach (var il in inlines) {
                                try {
                                    secondHalf.Inlines.Remove(il);
                                    firstHalf.Inlines.Add(il);
                                } catch { }
                            }
                            // Restore margins
                            firstHalf.Margin = new Thickness(firstHalf.Margin.Left, firstHalf.Margin.Top, firstHalf.Margin.Right, secondHalf.Margin.Bottom);
                            // Remove the empty second half
                            try {
                                if (secondHalf.SiblingBlocks != null) secondHalf.SiblingBlocks.Remove(secondHalf);
                                else rtb.Document.Blocks.Remove(secondHalf);
                            } catch { }
                        }
                    }
                }
            } catch { }
        }
        _splitParagraphs.Clear();
    }

    private void _RemovePageBreakSpacers(RichTextBox rtb) {
        var doc = rtb.Document;
        foreach (var spacer in _pageBreakSpacers) {
            try {
                if (spacer.SiblingBlocks != null) {
                    spacer.SiblingBlocks.Remove(spacer);
                } else {
                    doc.Blocks.Remove(spacer);
                }
            } catch { }
        }
        _pageBreakSpacers.Clear();
        
        var toRemove = new System.Collections.Generic.List<Block>();
        _FindOrphanedSpacers(doc.Blocks, toRemove);
        foreach (var block in toRemove) {
            try {
                if (block.SiblingBlocks != null) {
                    block.SiblingBlocks.Remove(block);
                } else {
                    doc.Blocks.Remove(block);
                }
            } catch { }
        }
    }

    private void _FindOrphanedSpacers(System.Windows.Documents.BlockCollection blocks, System.Collections.Generic.List<Block> toRemove) {
        foreach (var block in blocks) {
            if (block is System.Windows.Documents.Section) {
                _FindOrphanedSpacers(((System.Windows.Documents.Section)block).Blocks, toRemove);
            } else if (block is BlockUIContainer && (((BlockUIContainer)block).Tag as string) == "__PageBreakSpacer__") {
                toRemove.Add(block);
            }
        }
    }

    private BlockUIContainer _CreatePageBreakSpacer(string theme, int pageNum, double fillHeight = 0) {
        bool isDark = (theme == "Dark");
        
        var spacerPanel = new StackPanel();
        spacerPanel.Orientation = Orientation.Vertical;
        spacerPanel.Margin = new Thickness(-150, 0, -150, 0);
        spacerPanel.Focusable = false;
        spacerPanel.IsHitTestVisible = false;

        // Part 1: Fill remaining page space (transparent — looks like part of the page)
        if (fillHeight > 2) {
            var fillArea = new System.Windows.Controls.Border();
            fillArea.Height = fillHeight;
            fillArea.Background = System.Windows.Media.Brushes.Transparent;
            fillArea.IsHitTestVisible = false;
            spacerPanel.Children.Add(fillArea);
        }

        // Part 2: Visual gap between pages
        var spacerGrid = new Grid();
        spacerGrid.Height = 40;
        spacerGrid.Margin = new Thickness(0, 10, 0, 10);
        spacerGrid.Focusable = false;
        spacerGrid.IsHitTestVisible = false;

        // Background container representing the gap (matches surrounding canvas theme)
        var bgBorder = new System.Windows.Controls.Border();
        bgBorder.BorderThickness = new Thickness(0, 1, 0, 1);
        bgBorder.IsHitTestVisible = false;
        
        if (theme == "Dark") {
            bgBorder.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(18, 18, 18));
            bgBorder.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(51, 51, 51));
        } else if (theme == "Theme") {
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "DropdownBg");
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "ControlBorder");
        } else {
            bgBorder.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "DropdownBg");
            bgBorder.BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224));
        }

        spacerGrid.Children.Add(bgBorder);

        spacerPanel.Children.Add(spacerGrid);

        var container = new BlockUIContainer(spacerPanel);
        container.Tag = "__PageBreakSpacer__";
        container.Focusable = false;
        container.Margin = new Thickness(0);
        container.Padding = new Thickness(0);
        return container;
    }

    private double _EstimateBlockHeight(Block block, double availableWidth) {
        if (block is System.Windows.Documents.Paragraph) {
            var p = (System.Windows.Documents.Paragraph)block;
            string text = "";
            try {
                text = new TextRange(p.ContentStart, p.ContentEnd).Text;
            } catch { }
            
            double fontSize = 14;
            try {
                double rawFs = p.FontSize;
                if (!double.IsNaN(rawFs) && rawFs > 0) {
                    fontSize = rawFs;
                }
            } catch { }

            double lineHeight = fontSize * 1.5;
            double charsPerLine = Math.Max(1, availableWidth / (fontSize * 0.55));
            int lines = 1;
            if (text != null && text.Length > 0 && charsPerLine > 0) {
                try {
                    lines = Math.Max(1, (int)Math.Ceiling(text.Length / charsPerLine));
                } catch { }
            }

            double top = 0;
            double bottom = 0;
            try {
                double rawTop = p.Margin.Top;
                if (!double.IsNaN(rawTop)) top = rawTop;
            } catch { }
            try {
                double rawBottom = p.Margin.Bottom;
                if (!double.IsNaN(rawBottom)) bottom = rawBottom;
            } catch { }

            double est = lines * lineHeight + top + bottom + 4;
            
            try {
                string debugPath = System.IO.Path.Combine(GetLogDir(), "ahk_editor_debug.log");
                System.IO.File.AppendAllText(debugPath, string.Format("EstimateBlockHeight: textLen={0}, fontSize={1}, lineHeight={2}, charsPerLine={3}, lines={4}, margin.top={5}, margin.bottom={6}, est={7}\n",
                    text != null ? text.Length : 0, fontSize, lineHeight, charsPerLine, lines, top, bottom, est));
            } catch { }

            return double.IsNaN(est) ? 24 : est;
        }
        if (block is System.Windows.Documents.Table) {
            var tbl = (System.Windows.Documents.Table)block;
            int rowCount = 0;
            foreach (var rg in tbl.RowGroups) rowCount += rg.Rows.Count;
            return rowCount * 32 + 20;
        }
        if (block is System.Windows.Documents.List) {
            return ((System.Windows.Documents.List)block).ListItems.Count * 26 + 10;
        }
        if (block is BlockUIContainer) return 40;
        return 24;
    }

}
#endif
