// User edits across static and dynamically inserted forms. Only control identity is sent;
// text, selected values and clipboard contents never enter the diagnostic event.
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

public partial class AhkWpfEngine
{
    private bool _userValueEventsBound;
    private FrameworkElement _userValueInput;
    private FrameworkElement _userValueSession;
    private int _userValueInputTick;
    private string _userValueCommand;

    private FrameworkElement UserValueControl(object source)
    {
        DependencyObject current = source as DependencyObject;
        FrameworkElement candidate = null;
        while (current != null && current != win)
        {
            var element = current as FrameworkElement;
            if (element != null && !String.IsNullOrEmpty(element.Name)
                && !element.Name.StartsWith("PART_", StringComparison.Ordinal))
            {
                if (element is ComboBox) return element;
                if (candidate == null && (element is TextBoxBase || element is RangeBase || element is ToggleButton))
                    candidate = element;
            }
            current = current is Visual ? VisualTreeHelper.GetParent(current) : LogicalTreeHelper.GetParent(current);
        }
        return candidate;
    }

    private void ArmUserValue(object source, bool mouse)
    {
        _userValueCommand = null;
        _userValueInput = UserValueControl(source);
        _userValueInputTick = Environment.TickCount;
        // A text editing session lasts until focus leaves. Sliders and selection controls
        // start a new interaction on each mouse press / navigation key.
        var combo = _userValueInput as ComboBox;
        if (mouse || !(_userValueInput is TextBoxBase) && !(combo != null && combo.IsEditable))
            _userValueSession = null;
    }

    private void ReportUserValue(object source, string kind)
    {
        var element = UserValueControl(source);
        if (element == null || !element.IsVisible || !element.IsEnabled) return;
        var text = element as TextBoxBase;
        if (text != null && text.IsReadOnly) return;
        var combo = element as ComboBox;
        // Template toggle buttons / scroll bars change while merely opening or
        // scrolling a selector. Only the public value control is an edit.
        if (kind == "toggle" && !(element is ToggleButton)) return;
        if (kind == "selection" && combo == null) return;
        if (kind == "range" && (!(element is RangeBase) || element is ScrollBar)) return;
        bool input = Object.ReferenceEquals(element, _userValueInput)
            && unchecked(Environment.TickCount - _userValueInputTick) >= 0
            && unchecked(Environment.TickCount - _userValueInputTick) < 2000;
        if (!input && !(kind == "selection" && combo != null && combo.IsDropDownOpen && combo.IsKeyboardFocusWithin)) return;
        if (kind == "text" && _userValueCommand != null)
        {
            kind = _userValueCommand;
            _userValueCommand = null;
        }
        if (Object.ReferenceEquals(element, _userValueSession)) return;
        _userValueSession = element;
        SendToAhk("EVENT|" + winId + "|Window|UserValueChanged|"
            + BridgeUtil.LengthPrefix(kind + "|" + element.Name) + "\n");
    }

    private void BindUserValueEvents()
    {
        if (_userValueEventsBound) return;
        _userValueEventsBound = true;
        win.AddHandler(UIElement.PreviewKeyDownEvent, new KeyEventHandler((s, e) => ArmUserValue(Keyboard.FocusedElement, false)), true);
        win.AddHandler(TextCompositionManager.PreviewTextInputEvent, new TextCompositionEventHandler((s, e) => ArmUserValue(Keyboard.FocusedElement, false)), true);
        win.AddHandler(UIElement.PreviewMouseDownEvent, new MouseButtonEventHandler((s, e) => ArmUserValue(e.OriginalSource, true)), true);
        win.AddHandler(UIElement.PreviewMouseWheelEvent, new MouseWheelEventHandler((s, e) => ArmUserValue(e.OriginalSource, true)), true);
        win.AddHandler(UIElement.PreviewDropEvent, new DragEventHandler((s, e) => ArmUserValue(e.OriginalSource, true)), true);
        CommandManager.AddPreviewExecutedHandler(win, (s, e) => {
            if (e.Command == ApplicationCommands.Copy || e.Command == ApplicationCommands.Paste || e.Command == ApplicationCommands.Cut
                || e.Command == ApplicationCommands.Undo || e.Command == ApplicationCommands.Redo)
            {
                ArmUserValue(Keyboard.FocusedElement, false);
                _userValueSession = null;
                if (e.Command == ApplicationCommands.Copy)
                    ReportUserValue(Keyboard.FocusedElement, "copy");
                else
                    _userValueCommand = e.Command == ApplicationCommands.Paste ? "paste"
                        : e.Command == ApplicationCommands.Cut ? "cut" : e.Command == ApplicationCommands.Undo ? "undo" : "redo";
            }
        });
        win.AddHandler(Keyboard.GotKeyboardFocusEvent, new KeyboardFocusChangedEventHandler((s, e) => {
            if (!Object.ReferenceEquals(UserValueControl(e.NewFocus), _userValueSession))
                _userValueSession = null;
        }), true);
        win.AddHandler(TextBoxBase.TextChangedEvent, new TextChangedEventHandler((s, e) => ReportUserValue(e.OriginalSource, "text")), true);
        win.AddHandler(Selector.SelectionChangedEvent, new SelectionChangedEventHandler((s, e) => ReportUserValue(e.OriginalSource, "selection")), true);
        win.AddHandler(ToggleButton.CheckedEvent, new RoutedEventHandler((s, e) => ReportUserValue(e.OriginalSource, "toggle")), true);
        win.AddHandler(ToggleButton.UncheckedEvent, new RoutedEventHandler((s, e) => ReportUserValue(e.OriginalSource, "toggle")), true);
        win.AddHandler(RangeBase.ValueChangedEvent, new RoutedPropertyChangedEventHandler<double>((s, e) => ReportUserValue(e.OriginalSource, "range")), true);
    }
}
