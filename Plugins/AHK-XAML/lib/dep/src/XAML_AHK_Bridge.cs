// =============================================================================
// Engine entry: shared usings, assembly info, logging
// =============================================================================
using System;
using System.Linq;
using System.Windows;
using System.Windows.Markup;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
#if ENABLE_WEBVIEW
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;
#endif
#if ENABLE_AVALONEDIT
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.CodeCompletion;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Editing;
using ICSharpCode.AvalonEdit.Folding;
using ICSharpCode.AvalonEdit.Rendering;
using ICSharpCode.AvalonEdit.Search;
#endif
#if ENABLE_DOCUMENT
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
#endif
using Color = System.Windows.Media.Color;


[assembly: AssemblyTitle("ahk-xaml Engine")]
[assembly: AssemblyDescription("WPF Rendering Engine for AutoHotkey")]
[assembly: AssemblyCompany("owhs")]
[assembly: AssemblyProduct("ahk-xaml Shared Engine")]
[assembly: AssemblyCopyright("Copyright © 2026")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDispatch)]
public partial class AhkWpfEngine
{
    public static bool EnableLogging = true;
    private static string _logDir = null;

    private static string GetLogDir()
    {
        if (_logDir == null)
        {
            _logDir = System.Environment.GetEnvironmentVariable("RMT_LOG_DIR");
            if (string.IsNullOrEmpty(_logDir))
            {
                _logDir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AhkWpf");
            }
        }
        if (!System.IO.Directory.Exists(_logDir))
            System.IO.Directory.CreateDirectory(_logDir);
        return _logDir;
    }

    private static string GetLogPath(string filename)
    {
        return System.IO.Path.Combine(GetLogDir(), filename);
    }

    private static void LogDebug(string msg)
    {
        try
        {
            System.IO.File.AppendAllText(GetLogPath("AhkWpfDebug.log"),
                System.DateTime.Now.ToString("HH:mm:ss.fff") + " " + msg + "\n");
        }
        catch { }
    }

    // 绑定不到的控件（动态生成的控件）以前每条都追加一行日志，主窗口一次就有上千行、
    // 每次开窗都重写一遍（文件曾涨到 4.7MB）。默认关掉，需要排查时设环境变量 RMT_XAML_VERBOSE=1。
    internal static readonly bool VerboseBindLog =
        System.Environment.GetEnvironmentVariable("RMT_XAML_VERBOSE") == "1";

    /// <summary>
    /// 写应用级资源字典，值没变就不写。
    /// 应用级 Resources 每写一个键，所有已打开窗口都要重算一遍 DynamicResource；
    /// 主题色每次开窗都是同一批同一值，无条件写＝每开一个窗白烧一两百毫秒。
    /// </summary>
    internal static void SetAppResource(object key, object val)
    {
        if (key == null || Application.Current == null)
            return;
        try
        {
            ResourceDictionary res = Application.Current.Resources;
            if (res.Contains(key) && SameResourceValue(res[key], val))
                return;
            res[key] = val;
        }
        catch { }
    }

    internal static bool SameResourceValue(object a, object b)
    {
        if (a == null || b == null)
            return ReferenceEquals(a, b);
        if (ReferenceEquals(a, b))
            return true;
        if (a.GetType() != b.GetType())
            return false;
        if (a is Brush)
            return a.ToString() == b.ToString();   // Brush.ToString() 就是颜色串
        if (a is double)
            return (double)a == (double)b;
        if (a is string)
            return string.Equals((string)a, (string)b, StringComparison.Ordinal);
        return a.Equals(b);                        // Thickness / CornerRadius 等值类型
    }

    /// <summary>
    /// 把 "Brush:#FFF" / "Double:12" / "#FFF" 这类资源串解析成对象；解不出返回 null。
    /// 与 CommandDispatcher 里 Resource 分支的解析顺序一致。
    /// </summary>
    internal static object ParseResourceValue(string raw)
    {
        if (string.IsNullOrEmpty(raw))
            return null;
        int c = raw.IndexOf(':');
        if (c > 0)
        {
            string t = raw.Substring(0, c);
            string v = raw.Substring(c + 1);
            try
            {
                if (t == "Brush") return new System.Windows.Media.BrushConverter().ConvertFromString(v);
                if (t == "Thickness") return new System.Windows.ThicknessConverter().ConvertFromString(v);
                if (t == "CornerRadius") return new System.Windows.CornerRadiusConverter().ConvertFromString(v);
                if (t == "Double") return double.Parse(v, System.Globalization.CultureInfo.InvariantCulture);
            }
            catch { return null; }
        }
        try { return new System.Windows.Media.BrushConverter().ConvertFromString(raw); }
        catch { }
        try { return new System.Windows.CornerRadiusConverter().ConvertFromString(raw); }
        catch { }
        try { return new System.Windows.ThicknessConverter().ConvertFromString(raw); }
        catch { }
        try { return double.Parse(raw, System.Globalization.CultureInfo.InvariantCulture); }
        catch { }
        return null;
    }

    /// <summary>
    /// 窗口级资源值没变就不重写。写 window.Resources 会让该窗口整棵树重新求值 DynamicResource，
    /// 主题色每次开窗都是同一批同一值，白写一遍等于白烧几十毫秒。
    /// </summary>
    internal static bool WindowResourceUnchanged(Window w, string key, string raw)
    {
        try
        {
            if (w == null || key == null || !w.Resources.Contains(key))
                return false;
            object cur = w.Resources[key];
            if (cur == null)
                return false;
            object nv = ParseResourceValue(raw);
            return nv != null && SameResourceValue(cur, nv);
        }
        catch { return false; }
    }
}
