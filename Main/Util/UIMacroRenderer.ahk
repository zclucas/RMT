#Requires AutoHotkey v2.0

; ===========================================================================
; 界面宏 · 自定义面板渲染器（v0.2 · 绝对定位）
;
; 把 UIMacroSchema 渲染成一堆绝对定位的控件。设计器画布和浮窗运行时共用，
; 保证「画布上摆成什么样，浮窗就是什么样」。
;
; 定位方式：Grid 单元格内用 Margin(x, y, 0, 0) + 左上对齐 + 显式宽高。
;   （不用 Canvas.Left，避免依赖生成器对附加属性的支持差异）
; 宽度写 0 表示撑满到面板右边缘。
; ===========================================================================
class UIMacroRenderer {
    static Prefix := "UIC_"
    static CustomFontTag := "UIMacroCustomFont"
    static EdgePad := 6      ; 撑满时右侧留白

    static BtnStyle := '<Style TargetType="Button"><Setter Property="BorderThickness" Value="1"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Arrow"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="1,0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource UIPanelTitleBg}"/><Setter TargetName="Bd" Property="BorderThickness" Value="1"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource UIPanelTitleBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

    static NameOf(id) {
        return UIMacroRenderer.Prefix . String(id)
    }

    static HitNameOf(id) {
        return UIMacroRenderer.Prefix . "Hit_" . String(id)
    }

    ; 由 schema 推算某控件实际宽度（0 = 撑满）
    static ActualWidth(ctrl, panelW) {
        w := Integer(ctrl.w)
        if (w > 0)
            return w
        return Max(20, Integer(panelW) - Integer(ctrl.x) - UIMacroRenderer.EdgePad)
    }

    ; ------------------------------------------------------------------
    ; 渲染
    ;   parent : XAML_Generator 的 Grid（画布本体）
    ;   opt    : { btnColor, btnTextColor, textColor, inputBg, inputStroke, panelWidth, tableItem, selectionOverlay }
    ;            tableItem 可选：下拉框要按宏文本现算参数规格（不传则自己取 UI 表）
    ; 返回   : Map(id -> { name, type, hitName? })
    ; ------------------------------------------------------------------
    static Render(parent, schema, opt) {
        ctrlMap := Map()
        if (!IsObject(schema) || !ObjHasOwnProp(schema, "controls"))
            return ctrlMap

        ; 下拉框的子项要读宏文本 → 需要表对象；渲染器也可能在没有表的环境里被调用
        tableItem := ""
        if (opt.HasProp("tableItem"))
            tableItem := opt.tableItem
        else
            try tableItem := GetTableBySymbol("UI")

        panelW := opt.HasProp("panelWidth") ? Integer(opt.panelWidth) : Integer(schema.window.width)
        btnColor := opt.HasProp("btnColor") ? opt.btnColor : "{DynamicResource UIPanelBtnColor}"
        btnTextColor := opt.HasProp("btnTextColor") ? opt.btnTextColor : "{DynamicResource UIPanelBtnText}"
        textColor := opt.HasProp("textColor") ? opt.textColor : "{DynamicResource UIPanelBtnText}"
        inputBg := opt.HasProp("inputBg") ? opt.inputBg : "{DynamicResource InputBg}"
        inputStroke := opt.HasProp("inputStroke") ? opt.inputStroke : "{DynamicResource InputStroke}"
        ; 输入框前景色单独一个键：UIPanelBtnText 是「按钮标签色」（配彩色按钮底用），
        ; 当输入框 Foreground 用会和 InputBg 撞色，字看不见。
        inputTextColor := opt.HasProp("inputTextColor") ? opt.inputTextColor : "{DynamicResource InputText}"
        ; 文本控件是「显示在面板底色上的字」，不能用按钮标签色（那是配彩色按钮底的），
        ; 否则跟面板底色撞上就看不见。默认走主题的正文色。
        textDisplayColor := opt.HasProp("textDisplayColor") ? opt.textDisplayColor : "{DynamicResource TextMain}"
        ; 图形是否参与命中测试：设计器要能点选，浮窗运行时必须让点击穿透到下面的控件
        shapeHit := opt.HasProp("shapeHitTest") && opt.shapeHitTest

        ; 两遍渲染：图形先入画，控件后入画。WPF 里后加的在上面，
        ; 这样线框永远在控件之下——不必依赖用户手动「置底」，也不会挡点击。
        ordered := []
        for ctrl in schema.controls {
            if (UIMacroRenderer.IsShapeCtrl(ctrl))
                ordered.Push(ctrl)
        }
        for ctrl in schema.controls {
            if (!UIMacroRenderer.IsShapeCtrl(ctrl))
                ordered.Push(ctrl)
        }

        for ctrl in ordered {
            ; 只画指定页（设计器切页用）：整页跳过，不生成元素
            if (opt.HasProp("onlyPage") && integer(opt.onlyPage) > 0) {
                pg := (ctrl.HasProp("page") ? Integer(ctrl.page) : 1)
                if (pg != integer(opt.onlyPage))
                    continue
            }
            name := UIMacroRenderer.NameOf(ctrl.id)
            bindingTable := tableItem
            if (ctrl.HasProp("binding") && IsObject(ctrl.binding)
                && ctrl.binding.HasProp("macroId")) {
                resolvedTable := ""
                try resolvedTable := GetItemTableGlobal(String(ctrl.binding.macroId))
                if (IsObject(resolvedTable))
                    bindingTable := resolvedTable
            }
            x := Integer(ctrl.x)
            y := Integer(ctrl.y)
            w := UIMacroRenderer.ActualWidth(ctrl, panelW)
            h := Integer(ctrl.h)
            hasCustomFont := !UIMacroSchema.IsShapeType(ctrl.type)
            ctrlFontSize := (ctrl.HasProp("fontSize") && Integer(ctrl.fontSize) > 0)
                ? Integer(ctrl.fontSize) : UIMacroSchema.DefaultTextFontSize
            customTextColor := (ctrl.HasProp("textColor") && String(ctrl.textColor) != "")
                ? String(ctrl.textColor) : ""
            margin := Format("{},{},0,0", x, y)

            switch ctrl.type {
                case "Button":
                    btn := parent.Add("Button").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .FontSize(ctrlFontSize).Padding("0").Cursor("Hand")
                    if (hasCustomFont)
                        btn.Tag(UIMacroRenderer.CustomFontTag)
                    btn.Background(btnColor).Foreground(customTextColor != "" ? customTextColor : btnTextColor)
                    btn.InjectResources(UIMacroRenderer.BtnStyle)
                    btn.Add("TextBlock").Text(String(ctrl.text))
                        .HorizontalAlignment("Center").VerticalAlignment("Center")
                        .TextTrimming("CharacterEllipsis")

                case "CheckBox":
                    cb := parent.Add("CheckBox").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Content(String(ctrl.text))
                        .Foreground(customTextColor != "" ? customTextColor : textColor).FontSize(ctrlFontSize)
                        .VerticalContentAlignment("Center")
                    if (hasCustomFont)
                        cb.Tag(UIMacroRenderer.CustomFontTag)

                case "Edit":
                    edit := parent.Add("TextBox").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Text("").FontSize(ctrlFontSize).Padding("4,0")
                        .VerticalContentAlignment("Center")
                        .Background(inputBg).Foreground(customTextColor != "" ? customTextColor : inputTextColor)
                        .BorderBrush(inputStroke).BorderThickness("1")
                    if (hasCustomFont)
                        edit.Tag(UIMacroRenderer.CustomFontTag)

                case "TextBlock":
                    textBlock := parent.Add("TextBlock").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Text(String(ctrl.text))
                        .Foreground(customTextColor != "" ? customTextColor : textDisplayColor).FontSize(ctrlFontSize)
                        .TextTrimming("CharacterEllipsis")
                    if (hasCustomFont)
                        textBlock.Tag(UIMacroRenderer.CustomFontTag)

                case "ComboBox":
                    ; 子项由绑定参数的 options 决定（XAML 不支持运行期增删子项）。
                    ; 未绑定或参数不是 enum → 渲染成空下拉框，不报错。
                    ; 外观对齐 Edit 分支：不设前景/背景/边框的话 WPF 会用系统白模板，不跟主题。
                    cb := parent.Add("ComboBox").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .FontSize(ctrlFontSize).Padding("4,0")
                        .VerticalContentAlignment("Center")
                        .Background(inputBg).Foreground(customTextColor != "" ? customTextColor : inputTextColor)
                        .BorderBrush(inputStroke).BorderThickness("1")
                    if (hasCustomFont)
                        cb.Tag(UIMacroRenderer.CustomFontTag)
                    options := UIMacroRenderer.OptionsOf(ctrl, "", bindingTable)
                    if (IsObject(options)) {
                        for pair in options
                            cb.Add("ComboBoxItem").Content(String(pair[2]))
                    }

                case "Rect":
                    ; 装饰线框：透明填充 + 边框，用来给控件分组。
                    ; Background 必须显式给 Transparent：null 背景不参与命中测试，设计器里就选不中。
                    parent.Add("Border").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Background("Transparent")
                        .BorderBrush(UIMacroRenderer.ShapeBrush(ctrl)).BorderThickness("1")
                        .IsHitTestVisible(shapeHit ? "True" : "False")

                case "Ellipse":
                    parent.Add("Ellipse").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Fill("Transparent")
                        .Stroke(UIMacroRenderer.ShapeBrush(ctrl)).StrokeThickness("1")
                        .IsHitTestVisible(shapeHit ? "True" : "False")

                case "LineH", "LineV":
                    ; 线段：实心细条。粗细由 h（横线）/ w（竖线）决定
                    parent.Add("Border").Name(name).Width(w).Height(h).Margin(margin)
                        .HorizontalAlignment("Left").VerticalAlignment("Top")
                        .Background(UIMacroRenderer.ShapeBrush(ctrl)).BorderThickness("0")
                        .IsHitTestVisible(shapeHit ? "True" : "False")
            }

            ctrlMap[String(ctrl.id)] := { name: name, type: ctrl.type }
        }

        ; 设计器用透明命中层接管点击，避免触发控件本身的交互行为。
        if (opt.HasProp("selectionOverlay") && opt.selectionOverlay) {
            for ctrl in ordered {
                id := String(ctrl.id)
                if (UIMacroRenderer.IsShapeCtrl(ctrl) || !ctrlMap.Has(id))
                    continue
                w := UIMacroRenderer.ActualWidth(ctrl, panelW)
                hitName := UIMacroRenderer.HitNameOf(id)
                parent.Add("Border").Name(hitName).Width(w).Height(Integer(ctrl.h))
                    .Margin(Format("{},{},0,0", Integer(ctrl.x), Integer(ctrl.y)))
                    .HorizontalAlignment("Left").VerticalAlignment("Top")
                    .Background("Transparent").Cursor("Arrow")
                info := ctrlMap[id]
                info.hitName := hitName
            }
        }
        return ctrlMap
    }

    ; 控件绑定参数的 spec（未绑定 / 取不到 → ""）
    static SpecOfCtrl(ctrl, tableItem := "") {
        if (!IsObject(ctrl) || !ctrl.HasProp("binding") || !IsObject(ctrl.binding))
            return ""
        if (!IsObject(tableItem))
            return ""
        return UIMacroStepBinding.SpecOfBinding(tableItem, ctrl.binding)
    }

    ; enum 参数的可选项数组（[[值, 显示名], …]）；不是 enum → ""
    ; 是否装饰图形（线框/线）：渲染时统一压在控件之下
    static IsShapeCtrl(ctrl) {
        if (!IsObject(ctrl) || !ctrl.HasProp("type"))
            return false
        switch String(ctrl.type) {
            case "Rect", "Ellipse", "LineH", "LineV":
                return true
        }
        return false
    }

    ; 图形颜色 → 主题刷子（默认跟随主题边框色）
    static ShapeBrush(ctrl) {
        col := (IsObject(ctrl) && ctrl.HasProp("color")) ? String(ctrl.color) : ""
        switch col {
            case "accent": return "{DynamicResource ActionBg}"
            case "sub":    return "{DynamicResource TextSub}"
        }
        return "{DynamicResource ControlBorder}"
    }

    static OptionsOf(ctrl, spec, tableItem := "") {
        s := IsObject(spec) ? spec : UIMacroRenderer.SpecOfCtrl(ctrl, tableItem)
        if (!IsObject(s) || String(s.type) != "enum")
            return ""
        if (!s.HasProp("options") || !IsObject(s.options))
            return ""
        return s.options
    }

    ; ------------------------------------------------------------------
    ; 读控件当前值
    ;   Edit      → 文本
    ;   CheckBox  → 0/1
    ;   ComboBox  → 选中项的「值」（options[idx+1][1]）的字符串形式；未选 → ""
    ;   spec      : 可选，ComboBox 需要它拿 options（由调用方传入）
    ; ------------------------------------------------------------------
    static ReadValue(ui, id, type, spec := "") {
        if (!IsObject(ui))
            return ""
        name := UIMacroRenderer.NameOf(id)
        try {
            switch type {
                case "CheckBox":
                    return (ui.Query(name) = "True") ? 1 : 0
                case "Edit":
                    return ui.Query(name)
                case "ComboBox":
                    idx := Integer(ui.Query(name ">SelectedIndex"))
                    if (idx < 0)
                        return ""
                    if (!IsObject(spec) || String(spec.type) != "enum")
                        return ""
                    if (!spec.HasProp("options") || !IsObject(spec.options))
                        return ""
                    options := spec.options
                    if (idx >= options.Length)
                        return ""
                    return String(options[idx + 1][1])
            }
        } catch {
            return ""
        }
        return ""
    }

    ; ------------------------------------------------------------------
    ; 把值写进控件（运行期回填初值用）
    ;   Edit      → Text
    ;   CheckBox  → IsChecked
    ;   ComboBox  → 按值在 options 里找下标后设 SelectedIndex
    ; 返回 true 表示已写入
    ; ------------------------------------------------------------------
    static SetValue(ui, id, type, value, spec := "") {
        if (!IsObject(ui))
            return false
        name := UIMacroRenderer.NameOf(id)
        v := String(value)
        try {
            switch type {
                case "Edit":
                    ui.Update(name, "Text", v)
                    return true

                case "TextBlock":
                    ; 只显示、不接收输入：回填/刷新都走这里
                    ui.Update(name, "Text", v)
                    return true

                case "CheckBox":
                    low := StrLower(Trim(v))
                    on := (low == "1" || low == "true" || low == "yes" || low == "是")
                    ui.Update(name, "IsChecked", on ? "True" : "False")
                    return true

                case "ComboBox":
                    if (!IsObject(spec) || String(spec.type) != "enum")
                        return false
                    if (!spec.HasProp("options") || !IsObject(spec.options))
                        return false
                    options := spec.options
                    idx := -1
                    i := 0
                    for pair in options {
                        if (String(pair[1]) == v) {
                            idx := i
                            break
                        }
                        i += 1
                    }
                    if (idx < 0 && v == "") {
                        ; 值本身就是空 → 取消选中
                        ui.Update(name, "SelectedIndex", "-1")
                        return true
                    }
                    if (idx < 0)
                        return false
                    ui.Update(name, "SelectedIndex", String(idx))
                    return true
            }
        } catch {
            return false
        }
        return false
    }
}
