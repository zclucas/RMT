#Requires AutoHotkey v2.0

; ===========================================================================
; 界面宏 · 自定义面板 Schema（v0.2 · 画布式）
;
; v0.2 相比 v0.1 的变化：
;   - 控件改为绝对定位（x/y/w/h），对应「画布上自由摆放」
;   - window 增加 height，面板尺寸即画布尺寸
;   - 宽度写 0 表示「撑满到面板右边缘」
;
; schema 结构：
; {
;   "schemaVersion": 2,
;   "window": { "title": "", "width": 320, "height": 240 },
;   "controls": [
;     { "id": "c1", "type": "Button", "text": "开始",
;       "x": 12, "y": 12, "w": 0, "h": 30,
;       "action": { "cmd": "RunMacro", "macroId": "12" } }
;   ]
; }
;
; macroId 一律存字符串：宏排序会变，索引不可靠，只能靠 ID。
; ===========================================================================
class UIMacroSchema {
    static Version := 2
    static MaxControls := 30

    static MinWinWidth := 120
    static MaxWinWidth := 900
    static MinWinHeight := 80
    static MaxWinHeight := 900
    static MinCtrlHeight := 18
    static MaxCtrlHeight := 300
    static DefaultTextFontSize := 12
    static MinTextFontSize := 8
    static MaxTextFontSize := 48
    static MaxTextLen := 120

    static Types() {
        ; 后四个是纯装饰图形：无绑定、无动作，只画
        return ["Button", "CheckBox", "Edit", "TextBlock", "ComboBox", "Rect", "Ellipse", "LineH", "LineV"]
    }

    ; 交互控件（类型下拉前半段）
    static ControlTypes() {
        return ["Button", "CheckBox", "Edit", "TextBlock", "ComboBox"]
    }

    ; 装饰图形（类型下拉后半段，与控件分组显示）
    static ShapeTypes() {
        return ["Rect", "Ellipse", "LineH", "LineV"]
    }

    ; 装饰图形：不参与绑定/动作，尺寸下限也用图形的（2px），不受控件 18px 限制
    static IsShapeType(type) {
        switch String(type) {
            case "Rect", "Ellipse", "LineH", "LineV":
                return true
        }
        return false
    }

    static TypeLabel(type) {
        switch type {
            case "Button":    return "按钮"
            case "CheckBox":  return "勾选框"
            case "Edit":      return "输入框"
            case "TextBlock": return "文本"
            case "ComboBox":  return "下拉框"
            case "Rect":      return "线框"
            case "Ellipse":   return "椭圆"
            case "LineH":     return "横线"
            case "LineV":     return "竖线"
        }
        return type
    }

    static MinTextHeight(fontSize) {
        return Ceil(Integer(fontSize) * 1.6)
    }

    static NormalizeTextColor(color) {
        value := StrUpper(Trim(String(color)))
        return RegExMatch(value, "^#(?:[0-9A-F]{6}|[0-9A-F]{8})$") ? value : ""
    }

    ; 能否与「宏」建立关联。按钮/勾选框是「点了跑宏」；输入框/下拉框是「读写该宏里某一步的参数」。
    ; 两者的 action.macroId 都要能保存下来，否则编辑框的宏关联在存盘后会被丢弃。
    static CanBind(type) {
        return (type == "Button" || type == "CheckBox" || type == "Edit" || type == "ComboBox" || type == "TextBlock")
    }

    ; 该类型的字段绑定是「只读显示」（TextBlock 没有输入能力，只用来显示某个值）
    static IsDisplayOnly(type) {
        return (type == "TextBlock")
    }

    ; ------------------------------------------------------------------
    ; 构造
    ; ------------------------------------------------------------------
    static New() {
        return {
            schemaVersion: UIMacroSchema.Version,
            window: { title: "", width: 300, height: 220, pages: 1 },
            controls: []
        }
    }

    static Defaults(type) {
        switch type {
            case "Button":
                return {
                    type: "Button", text: "按钮", x: 12, y: 12, w: 90, h: 30,
                    action: "", page: 1, fontSize: UIMacroSchema.DefaultTextFontSize
                }
            case "CheckBox":
                return {
                    type: "CheckBox", text: "选项", x: 12, y: 12, w: 120, h: 24,
                    action: "", page: 1, fontSize: UIMacroSchema.DefaultTextFontSize
                }
            case "Edit":
                return {
                    type: "Edit", text: "", x: 12, y: 12, w: 140, h: 26,
                    action: "", page: 1, fontSize: UIMacroSchema.DefaultTextFontSize
                }
            case "TextBlock":
                return {
                    type: "TextBlock", text: "文本", x: 12, y: 12, w: 120, h: 20,
                    action: "", page: 1, fontSize: UIMacroSchema.DefaultTextFontSize
                }
            case "ComboBox":
                ; 子项由绑定字段决定（构建期生成，运行期不可增删）
                return {
                    type: "ComboBox", text: "", x: 12, y: 12, w: 140, h: 26,
                    action: "", page: 1, fontSize: UIMacroSchema.DefaultTextFontSize
                }
            case "Rect":
                return { type: "Rect", text: "", x: 12, y: 12, w: 200, h: 120, action: "", page: 1, color: "" }
            case "Ellipse":
                return { type: "Ellipse", text: "", x: 12, y: 12, w: 120, h: 80, action: "", page: 1, color: "" }
            case "LineH":
                return { type: "LineH", text: "", x: 12, y: 12, w: 200, h: 2, action: "", page: 1, color: "" }
            case "LineV":
                return { type: "LineV", text: "", x: 12, y: 12, w: 2, h: 120, action: "", page: 1, color: "" }
        }
        return ""
    }

    ; ------------------------------------------------------------------
    ; 序列化
    ; ------------------------------------------------------------------
    static Parse(str) {
        if (!IsObject(str) && Trim(String(str)) == "")
            return ""
        try {
            obj := IsObject(str) ? str : JSON.parse(String(str), , false)
        } catch {
            return ""
        }
        if (!IsObject(obj) || !ObjHasOwnProp(obj, "controls"))
            return ""
        ; Normalize 是「不可信 JSON → schema」的边界，任何意外都不该抛给调用方：
        ; 读不出配置的后果只能是「降级回自动模式」，不能是浮窗/设计器崩掉。
        try {
            return UIMacroSchema.Normalize(obj)
        } catch {
            return ""
        }
    }

    ; 安全取整：不可信输入转不成整数时返回 def，绝不抛异常
    ;   IsNumber("") / IsNumber("abc") / IsNumber("500abc") 都是 false → 走 def
    ;   IsNumber(500) / IsNumber("500") 都是 true
    ;   实测（AHK v2.0）：Integer() 对数字型字符串是「截断转换」而不是报错，
    ;   "12.5"→12、"3.7"→3、"1e3"→1000、"0x10"→16；只有真正非数字才抛。
    ;   另：IsNumber(1e300) 为真但 Integer(1e300) 会静默返回 INT64_MIN，
    ;   所以这里再加一道 32 位区间检查，超范围一律退回 def（饱和处理）。
    static _Int(v, def) {
        if (IsNumber(v))
            try {
                n := Integer(v)
                if (n >= -2147483648 && n <= 2147483647)
                    return n
            }
        return def
    }

    static ToString(schema) {
        try {
            return JSON.stringify(schema, 0)
        } catch {
            return ""
        }
    }

    static Normalize(obj) {
        schema := UIMacroSchema.New()

        if (ObjHasOwnProp(obj, "window") && IsObject(obj.window)) {
            win := obj.window
            if (ObjHasOwnProp(win, "title"))
                schema.window.title := String(win.title)
            ; 读入宽、写出严：读边界只做「修正到合法区间」，让加载永远成功；
            ; 真正拦用户的是校验边界 Validate（设计器点保存时才走）。
            if (ObjHasOwnProp(win, "width"))
                schema.window.width := Max(UIMacroSchema.MinWinWidth
                    , Min(UIMacroSchema.MaxWinWidth, UIMacroSchema._Int(win.width, schema.window.width)))
            if (ObjHasOwnProp(win, "height"))
                schema.window.height := Max(UIMacroSchema.MinWinHeight
                    , Min(UIMacroSchema.MaxWinHeight, UIMacroSchema._Int(win.height, schema.window.height)))
            ; 页数：1~20。窗口尺寸由 window 统一，所有页共用，天然一致。
            if (ObjHasOwnProp(win, "pages"))
                schema.window.pages := Max(1, Min(20, UIMacroSchema._Int(win.pages, 1)))
        }

        if (!ObjHasOwnProp(obj, "controls") || !IsObject(obj.controls))
            return schema

        idx := 0
        for ctrl in obj.controls {
            idx += 1
            if (idx > UIMacroSchema.MaxControls)
                break
            if (!IsObject(ctrl))
                continue
            type := ObjHasOwnProp(ctrl, "type") ? String(ctrl.type) : ""
            if (type == "" || !UIMacroSchema.IsKnownType(type))
                continue

            item := UIMacroSchema.Defaults(type)
            item.id := (ObjHasOwnProp(ctrl, "id") && String(ctrl.id) != "") ? String(ctrl.id) : "c" idx
            ; 控件所属页：夹到 [1, pages]
            if (ObjHasOwnProp(ctrl, "page"))
                item.page := Max(1, Min(Integer(schema.window.pages), UIMacroSchema._Int(ctrl.page, 1)))
            if (ObjHasOwnProp(ctrl, "text"))
                item.text := String(ctrl.text)
            if (!UIMacroSchema.IsShapeType(type)) {
                if (ObjHasOwnProp(ctrl, "fontSize")) {
                    fontSize := UIMacroSchema._Int(ctrl.fontSize, 0)
                    if (fontSize >= UIMacroSchema.MinTextFontSize && fontSize <= UIMacroSchema.MaxTextFontSize)
                        item.fontSize := fontSize
                }
                if (ObjHasOwnProp(ctrl, "textColor")) {
                    textColor := UIMacroSchema.NormalizeTextColor(ctrl.textColor)
                    if (textColor != "")
                        item.textColor := textColor
                }
            }
            ; 坐标/尺寸来自不可信配置：转不成整数就用默认值，且不因此丢掉整个控件
            ; x / y / w 负数按 0 处理（与设计器 _OnPosChanged / _OnSizeChanged 一致；
            ; w=0 的语义是「撑满到右边缘」，不能当非法值）；
            ; h 夹到 MinCtrlHeight~MaxCtrlHeight，保证加载后一定合法（Validate 仍严格校验）。
            if (ObjHasOwnProp(ctrl, "x"))
                item.x := Max(0, UIMacroSchema._Int(ctrl.x, item.x))
            else if (!ObjHasOwnProp(ctrl, "y"))
                ; v0.1 的配置没有坐标：按顺序竖排，避免全部叠在左上角
                item.x := 6
            if (ObjHasOwnProp(ctrl, "y"))
                item.y := Max(0, UIMacroSchema._Int(ctrl.y, item.y))
            else if (!ObjHasOwnProp(ctrl, "x"))
                item.y := 8 + (idx - 1) * 36
            if (ObjHasOwnProp(ctrl, "w"))
                item.w := Max(0, UIMacroSchema._Int(ctrl.w, item.w))
            if (ObjHasOwnProp(ctrl, "h")) {
                ; 图形（线）可以只有 2px：下限按类型取，不能硬套控件 18px
                minH := UIMacroSchema.IsShapeType(type) ? 2 : UIMacroSchema.MinCtrlHeight
                item.h := Max(minH
                    , Min(UIMacroSchema.MaxCtrlHeight, UIMacroSchema._Int(ctrl.h, item.h)))
            }
            ; 旧布局可能允许控件越界；载入时收回画布内，避免运行时整套自定义面板降级。
            if (item.w == 0)
                item.x := Min(item.x, schema.window.width - 20)
            else {
                item.w := Min(item.w, schema.window.width)
                item.x := Min(item.x, schema.window.width - item.w)
            }
            item.h := Min(item.h, schema.window.height)
            if (item.HasProp("fontSize"))
                item.h := Min(schema.window.height
                    , Max(item.h, UIMacroSchema.MinTextHeight(item.fontSize)))
            item.y := Min(item.y, schema.window.height - item.h)

            ; 图形颜色（预设三档）；非图形忽略，未知取值按主题色
            if (UIMacroSchema.IsShapeType(type) && ObjHasOwnProp(ctrl, "color")) {
                col := String(ctrl.color)
                if (col == "accent" || col == "sub")
                    item.color := col
            }
            if (UIMacroSchema.CanBind(type) && ObjHasOwnProp(ctrl, "action") && IsObject(ctrl.action)) {
                act := ctrl.action
                if (ObjHasOwnProp(act, "macroId"))
                    item.action := { cmd: "RunMacro", macroId: String(act.macroId) }
            }
            ; 控件 ↔ 宏行参数的绑定（v0.4 混合模型）
            ;   step 型：{ macroId, mode:"step", step, param }         内联指令（间隔_500）
            ;   data 型：{ macroId, mode:"data", kind, serial, field, hops? } 序列指令字段
            ; 兼容：
            ;   有 macroId 但没 mode 且有 step/param → 视为 step 型（v0.3 结构）
            ;   旧 {kind, serial, field} 无 macroId   → 丢弃（当未绑定）
            ;   其它                                  → 未绑定
            if (ObjHasOwnProp(ctrl, "binding") && IsObject(ctrl.binding)) {
                b := ctrl.binding
                bMacro := ObjHasOwnProp(b, "macroId") ? String(b.macroId) : ""
                bMode := ObjHasOwnProp(b, "mode") ? String(b.mode) : ""
                if (bMacro != "" && bMode == "" && ObjHasOwnProp(b, "step") && ObjHasOwnProp(b, "param"))
                    bMode := "step"
                if (bMacro != "" && bMode == "step") {
                    stepN := UIMacroSchema._Int(ObjHasOwnProp(b, "step") ? b.step : 0, 0)
                    paramN := UIMacroSchema._Int(ObjHasOwnProp(b, "param") ? b.param : 0, 0)
                    if (stepN >= 1 && paramN >= 1) {
                        nb := {
                            macroId: bMacro,
                            mode: "step",
                            step: stepN,
                            param: paramN
                        }
                        ; 嵌套路径（可选）。hops 存在但非法 → 整个绑定丢弃：
                        ; 掉了 hops 语义就变了（会绑到顶层去），宁可不绑。
                        if (ObjHasOwnProp(b, "hops")) {
                            n := UIMacroStepBinding.NormalizeHops(b.hops)
                            if (IsObject(n))
                                nb.hops := n
                            else
                                nb := ""
                        }
                        if (IsObject(nb))
                            item.binding := nb
                    }
                } else if (bMacro != "" && bMode == "skip") {
                    ; 步骤跳过开关：勾选=执行，取消=跳过（宏文本前加 🚫）
                    stepN := UIMacroSchema._Int(ObjHasOwnProp(b, "step") ? b.step : 0, 0)
                    if (stepN >= 1) {
                        nb := { macroId: bMacro, mode: "skip", step: stepN }
                        if (ObjHasOwnProp(b, "hops")) {
                            n2 := UIMacroStepBinding.NormalizeHops(b.hops)
                            if (IsObject(n2))
                                nb.hops := n2
                            else
                                nb := ""
                        }
                        if (IsObject(nb))
                            item.binding := nb
                    }
                } else if (bMacro != "" && bMode == "data") {
                    if (ObjHasOwnProp(b, "kind") && ObjHasOwnProp(b, "serial") && ObjHasOwnProp(b, "field")
                        && String(b.kind) != "" && String(b.serial) != "" && String(b.field) != "") {
                        nb := {
                            macroId: bMacro,
                            mode: "data",
                            kind: String(b.kind),
                            serial: String(b.serial),
                            field: String(b.field)
                        }
                        if (ObjHasOwnProp(b, "hops")) {
                            n3 := UIMacroStepBinding.NormalizeHops(b.hops)
                            if (IsObject(n3))
                                nb.hops := n3
                            else
                                nb := ""
                        }
                        if (IsObject(nb))
                            item.binding := nb
                    }
                }
            }
            schema.controls.Push(item)
        }
        return schema
    }

    static IsKnownType(type) {
        for t in UIMacroSchema.Types() {
            if (t == type)
                return true
        }
        return false
    }

    ; ------------------------------------------------------------------
    ; 从宏列表物化：竖向排一列，作为「切到自定义」的起点
    ; ------------------------------------------------------------------
    static FromItems(items, panelW := 300) {
        schema := UIMacroSchema.New()
        schema.window.width := panelW
        idx := 0
        gap := 4
        y := 8
        for item in items {
            if (idx >= UIMacroSchema.MaxControls)
                break
            idx += 1
            text := ""
            if (ObjHasOwnProp(item, "Remark"))
                text := Trim(String(item.Remark))
            if (text == "")
                text := "操作" idx
            if (StrLen(text) > UIMacroSchema.MaxTextLen)
                text := SubStr(text, 1, UIMacroSchema.MaxTextLen)

            schema.controls.Push({
                id: "c" idx,
                type: "Button",
                text: text,
                x: 6,
                y: y,
                w: 0,
                h: 30,
                fontSize: UIMacroSchema.DefaultTextFontSize,
                action: { cmd: "RunMacro", macroId: String(item.ID) }
            })
            y += 30 + gap
        }
        schema.window.height := Max(120, y + 4)
        return schema
    }

    ; ------------------------------------------------------------------
    ; 增删查
    ; ------------------------------------------------------------------
    static IndexOf(schema, id) {
        for i, ctrl in schema.controls {
            if (String(ctrl.id) == String(id))
                return i
        }
        return 0
    }

    static FindById(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        return i ? schema.controls[i] : ""
    }

    static NextId(schema) {
        loop 9999 {
            id := "c" A_Index
            if (!UIMacroSchema.IndexOf(schema, id))
                return id
        }
        return "c0"
    }

    static Add(schema, type, x := -1, y := -1) {
        if (schema.controls.Length >= UIMacroSchema.MaxControls)
            return ""
        item := UIMacroSchema.Defaults(type)
        if (item == "")
            return ""
        item.id := UIMacroSchema.NextId(schema)
        if (x >= 0)
            item.x := x
        if (y >= 0)
            item.y := y
        schema.controls.Push(item)
        return item.id
    }

    static Remove(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        if (!i)
            return false
        schema.controls.RemoveAt(i)
        return true
    }

    ; 提到最上层（画布上控件重叠时用）
    ; 移动到数组指定位置（1-based；数组尾 = 最上层）。拖动排序用。
    static MoveToIndex(schema, id, target) {
        i := UIMacroSchema.IndexOf(schema, id)
        n := schema.controls.Length
        if (!i || target < 1 || target > n || i = target)
            return false
        item := schema.controls.RemoveAt(i)
        ; 「最终落到 target 位置」语义：移除后 target 之后的下标整体前移，
        ; 所以直接插到 target 即可（InsertAt 允许 len+1 即追加到末尾）
        schema.controls.InsertAt(target, item)
        return true
    }

    ; 上移一层（数组尾 = 最上层）
    static MoveUp(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        if (!i || i >= schema.controls.Length)
            return false
        item := schema.controls[i]
        schema.controls[i] := schema.controls[i + 1]
        schema.controls[i + 1] := item
        return true
    }

    ; 下移一层
    static MoveDown(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        if (!i || i <= 1)
            return false
        item := schema.controls[i]
        schema.controls[i] := schema.controls[i - 1]
        schema.controls[i - 1] := item
        return true
    }

    ; 置底：方框/线常用来分组，必须能压到控件下面，否则会挡住点击
    static SendToBack(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        if (!i || i = 1)
            return false
        item := schema.controls.RemoveAt(i)
        schema.controls.InsertAt(1, item)
        return true
    }

    static BringToFront(schema, id) {
        i := UIMacroSchema.IndexOf(schema, id)
        if (!i || i = schema.controls.Length)
            return false
        item := schema.controls[i]
        schema.controls.RemoveAt(i)
        schema.controls.Push(item)
        return true
    }

    ; ------------------------------------------------------------------
    ; 校验
    ; ------------------------------------------------------------------
    static Validate(schema) {
        if (!IsObject(schema) || !ObjHasOwnProp(schema, "controls"))
            return { ok: false, msg: "数据结构无效" }

        n := schema.controls.Length
        if (n <= 0)
            return { ok: false, msg: "至少需要一个控件" }
        if (n > UIMacroSchema.MaxControls)
            return { ok: false, msg: "控件数量超过上限（" UIMacroSchema.MaxControls "）" }

        ; 只应收到 Normalize 过的 schema，但这里也不假设入参可信：
        ; 取不出数字就按 0 处理，让范围校验自己返回 ok:false，而不是抛异常。
        w := UIMacroSchema._Int(schema.window.width, 0)
        h := UIMacroSchema._Int(schema.window.height, 0)
        if (w < UIMacroSchema.MinWinWidth || w > UIMacroSchema.MaxWinWidth)
            return { ok: false, msg: Format("面板宽度需在 {}~{} 之间", UIMacroSchema.MinWinWidth, UIMacroSchema.MaxWinWidth) }
        if (h < UIMacroSchema.MinWinHeight || h > UIMacroSchema.MaxWinHeight)
            return { ok: false, msg: Format("面板高度需在 {}~{} 之间", UIMacroSchema.MinWinHeight, UIMacroSchema.MaxWinHeight) }

        seen := Map()
        for ctrl in schema.controls {
            id := String(ctrl.id)
            if (seen.Has(id))
                return { ok: false, msg: "控件 ID 重复：" id }
            seen[id] := true

            if (!UIMacroSchema.IsKnownType(ctrl.type))
                return { ok: false, msg: "未知控件类型：" ctrl.type }

            if (!UIMacroSchema.IsShapeType(ctrl.type)) {
                fontSize := ctrl.HasProp("fontSize") ? UIMacroSchema._Int(ctrl.fontSize, 0) : 0
                if (fontSize != 0 && (fontSize < UIMacroSchema.MinTextFontSize
                    || fontSize > UIMacroSchema.MaxTextFontSize))
                    return { ok: false, msg: Format("「{}」字号需在 {}~{} 之间"
                        , UIMacroSchema.TypeLabel(ctrl.type), UIMacroSchema.MinTextFontSize, UIMacroSchema.MaxTextFontSize) }
                textColor := ctrl.HasProp("textColor") ? UIMacroSchema.NormalizeTextColor(ctrl.textColor) : ""
                if (ctrl.HasProp("textColor") && String(ctrl.textColor) != "" && textColor == "")
                    return { ok: false, msg: "文字颜色格式无效：" String(ctrl.textColor) }
            }

            if (UIMacroSchema.IsShapeType(ctrl.type)) {
                col := ctrl.HasProp("color") ? String(ctrl.color) : ""
                if (col != "" && col != "accent" && col != "sub")
                    return { ok: false, msg: "图形颜色取值无效：" col }
            }

            ch := UIMacroSchema._Int(ctrl.h, 0)
            minH := UIMacroSchema.IsShapeType(ctrl.type) ? 2 : UIMacroSchema.MinCtrlHeight
            if (ch < minH || ch > UIMacroSchema.MaxCtrlHeight)
                return { ok: false, msg: Format("「{}」高度需在 {}~{} 之间", UIMacroSchema.TypeLabel(ctrl.type), minH, UIMacroSchema.MaxCtrlHeight) }
            if (!UIMacroSchema.IsShapeType(ctrl.type) && fontSize > 0
                && ch < UIMacroSchema.MinTextHeight(fontSize))
                return { ok: false, msg: Format("「{}」高度不足以容纳当前字号，请增大控件高度"
                    , UIMacroSchema.TypeLabel(ctrl.type)) }

            cx := UIMacroSchema._Int(ctrl.x, -1)
            cy := UIMacroSchema._Int(ctrl.y, -1)
            cw := UIMacroSchema._Int(ctrl.w, -1)
            if (cx < 0 || cy < 0 || cw < 0)
                return { ok: false, msg: Format("「{}」的位置或宽度无效", UIMacroSchema.TypeLabel(ctrl.type)) }
            if (cw == 0) {
                if (cx > w - 20)
                    return { ok: false, msg: Format("「{}」超出窗体右边界", UIMacroSchema.TypeLabel(ctrl.type)) }
            } else if (cx + cw > w) {
                return { ok: false, msg: Format("「{}」超出窗体右边界", UIMacroSchema.TypeLabel(ctrl.type)) }
            }
            if (cy + ch > h)
                return { ok: false, msg: Format("「{}」超出窗体下边界", UIMacroSchema.TypeLabel(ctrl.type)) }

            if (StrLen(String(ctrl.text)) > UIMacroSchema.MaxTextLen)
                return { ok: false, msg: Format("「{}…」文本过长", SubStr(String(ctrl.text), 1, 10)) }
        }
        return { ok: true, msg: "" }
    }

    static Summary(schema) {
        if (!IsObject(schema))
            return "（空）"
        return Format("{}×{} / {} 个控件", schema.window.width, schema.window.height, schema.controls.Length)
    }

    ; ------------------------------------------------------------------
    ; 落盘编码
    ;
    ; 配置是 TOML，值用双引号包裹；JSON 正文里全是双引号，直接塞会把文件写坏
    ; （读回来变成空串，表现就是「保存没用」）。所以统一 Base64 后再存。
    ; 内存里 MainSoftData.UIPanelCustom 始终保存 Base64，读写两侧都走这两个函数。
    ; ------------------------------------------------------------------
    static EncodeStore(plainJson) {
        if (plainJson == "")
            return ""
        return UIMacroSchema._B64Enc(plainJson)
    }

    static DecodeStore(raw) {
        s := Trim(String(raw))
        if (s == "")
            return ""
        ; 兼容早期直接存 JSON 的配置
        if (SubStr(s, 1, 1) == "{")
            return s
        try
            return UIMacroSchema._B64Dec(s)
        catch
            return ""
    }

    static _B64Enc(str) {
        buf := Buffer(StrPut(str, "UTF-8"))
        StrPut(str, buf, "UTF-8")
        size := 0
        if (!DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x1, "Ptr", 0, "UInt*", &size))
            return ""
        out := Buffer(size * 2)
        if (!DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x1, "Ptr", out, "UInt*", &size))
            return ""
        return StrReplace(StrReplace(StrGet(out, "UTF-16"), "`r", ""), "`n", "")
    }

    static _B64Dec(b64) {
        size := 0
        if (!DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0))
            return ""
        buf := Buffer(size)
        if (!DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1, "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0))
            return ""
        return StrGet(buf, size, "UTF-8")
    }

    ; ------------------------------------------------------------------
    ; 存储：独立 JSON 文件
    ;
    ; 不再走 MainSettings.toml：TOML 用双引号包值，JSON 正文全是引号，
    ; 早期版本因此写出坏行、读回空串（表现为「保存没生效」）。
    ; 单独放一个 UTF-8 文件，读写都是原文，最不容易出错。
    ;
    ; 存储键（key）：早期用「折叠框数组下标」，折叠框一重排配置就串组，
    ; 而且串组后不报错（读到的 schema 仍合法，只是属于别的面板）。
    ; 现在键是折叠框 ID（稳定唯一），下标只保留兼容旧文件的读迁移。
    ; ------------------------------------------------------------------

    ; 折叠框 → 存储键。空折叠框 / 无 ID → ""
    static FoldKey(fold) {
        if (!IsObject(fold))
            return ""
        try {
            if (fold.HasProp("ID"))
                return String(fold.ID)
        }
        return ""
    }

    static StorePathByKey(key) {
        global MySoftData
        name := "default"
        try name := MySoftData.CurSettingName
        catch
            name := "default"
        return A_WorkingDir "\Setting\" name "\UIPanelCustom_" String(key) ".json"
    }

    ; 旧接口：按数组下标取路径（仅为兼容保留，内部转发到 StorePathByKey）
    static StorePath(foldIndex := 0) {
        return UIMacroSchema.StorePathByKey(String(foldIndex))
    }

    ; 旧下标文件 → 新 key 文件的一次性迁移。只做一次，任何失败都静默。
    static MigrateLegacy(foldIndex, key) {
        k := String(key)
        if (k == "" || k == String(foldIndex))
            return false
        oldPath := UIMacroSchema.StorePathByKey(String(foldIndex))
        newPath := UIMacroSchema.StorePathByKey(k)
        if (!FileExist(oldPath) || FileExist(newPath))
            return false
        content := ""
        try content := FileRead(oldPath, "UTF-8")
        catch
            return false
        try {
            FileAppend(content, newPath, "UTF-8")
            ; 保留旧文件为 .bak：迁移出问题时还能手工找回
            FileMove(oldPath, oldPath ".bak", 1)
            return true
        } catch {
            return false
        }
    }

    static ReadStoreByKey(key) {
        p := UIMacroSchema.StorePathByKey(key)
        if (!FileExist(p))
            return ""
        try
            return FileRead(p, "UTF-8")
        catch
            return ""
    }

    static WriteStoreByKey(key, json) {
        p := UIMacroSchema.StorePathByKey(key)
        tmp := p ".tmp"
        try {
            dir := ""
            SplitPath(p, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            f := FileOpen(tmp, "w", "UTF-8")
            f.Write(json)
            f.Close()
            FileMove(tmp, p, 1)
            return true
        } catch {
            try f.Close()
            try FileDelete(tmp)
            return false
        }
    }

    static DeleteStoreByKey(key) {
        p := UIMacroSchema.StorePathByKey(key)
        if (!FileExist(p))
            return false
        try {
            FileDelete(p)
            return true
        } catch {
            return false
        }
    }

    static ReadStore(foldIndex := 0) {
        return UIMacroSchema.ReadStoreByKey(String(foldIndex))
    }

    static _HopsJson(hops) {
        if (!IsObject(hops) || hops.Length == 0)
            return ""
        json := "["
        for i, hop in hops {
            if (i > 1)
                json .= ","
            json .= '{"step":' Integer(hop.step)
                . ',"kind":"' UIMacroSchema._Esc(hop.kind) '"'
                . ',"serial":"' UIMacroSchema._Esc(hop.serial) '"'
                . ',"field":"' UIMacroSchema._Esc(hop.field) '"'
                . ',"index":' Integer(hop.index) '}'
        }
        return json "]"
    }

    ; 手写序列化。此环境下 JSON.stringify 会返回空串，所以输出侧不依赖它。
    static Serialize(schema) {
        s := '{"schemaVersion":' UIMacroSchema.Version
        s .= ',"window":{"title":"' UIMacroSchema._Esc(schema.window.title) '","width":' Integer(schema.window.width) ',"height":' Integer(schema.window.height)
        if (schema.window.HasProp("pages") && Integer(schema.window.pages) > 1)
            s .= ',"pages":' Integer(schema.window.pages)
        s .= '}'
        s .= ',"controls":['
        first := true
        for ctrl in schema.controls {
            if (!first)
                s .= ','
            first := false
            s .= '{"id":"' UIMacroSchema._Esc(ctrl.id) '","type":"' UIMacroSchema._Esc(ctrl.type) '","text":"' UIMacroSchema._Esc(ctrl.text) '"'
            s .= ',"x":' Integer(ctrl.x) ',"y":' Integer(ctrl.y) ',"w":' Integer(ctrl.w) ',"h":' Integer(ctrl.h)
            if (!UIMacroSchema.IsShapeType(ctrl.type)) {
                if (ctrl.HasProp("fontSize") && Integer(ctrl.fontSize) > 0)
                    s .= ',"fontSize":' Integer(ctrl.fontSize)
                if (ctrl.HasProp("textColor") && String(ctrl.textColor) != "")
                    s .= ',"textColor":"' UIMacroSchema._Esc(ctrl.textColor) '"'
            }
            if (ctrl.HasProp("action") && IsObject(ctrl.action) && ObjHasOwnProp(ctrl.action, "macroId"))
                s .= ',"action":{"cmd":"RunMacro","macroId":"' UIMacroSchema._Esc(ctrl.action.macroId) '"}'
            else
                s .= ',"action":""'
            if (ctrl.HasProp("binding") && IsObject(ctrl.binding)) {
                b := ctrl.binding
                if (b.HasProp("mode") && String(b.mode) == "skip") {
                    s .= ',"binding":{"macroId":"' UIMacroSchema._Esc(b.macroId) '","mode":"skip"'
                        . ',"step":' Integer(b.step)
                    hopsJson := UIMacroSchema._HopsJson(b.HasProp("hops") ? b.hops : "")
                    if (hopsJson != "")
                        s .= ',"hops":' hopsJson
                    s .= '}'
                } else if (b.HasProp("mode") && String(b.mode) == "data") {
                    s .= ',"binding":{"macroId":"' UIMacroSchema._Esc(b.macroId) '","mode":"data"'
                        . ',"kind":"' UIMacroSchema._Esc(b.kind) '","serial":"' UIMacroSchema._Esc(b.serial) '","field":"' UIMacroSchema._Esc(b.field) '"'
                    hopsJson := UIMacroSchema._HopsJson(b.HasProp("hops") ? b.hops : "")
                    if (hopsJson != "")
                        s .= ',"hops":' hopsJson
                    s .= '}'
                } else {
                    s .= ',"binding":{"macroId":"' UIMacroSchema._Esc(b.macroId) '","mode":"step"'
                        . ',"step":' Integer(b.step) ',"param":' Integer(b.param)
                    hopsJson := UIMacroSchema._HopsJson(b.HasProp("hops") ? b.hops : "")
                    if (hopsJson != "")
                        s .= ',"hops":' hopsJson
                    s .= '}'
                }
            } else
                s .= ',"binding":""'
            ; 图形颜色（仅非默认时写出）
            if (ctrl.HasProp("page") && Integer(ctrl.page) > 1)
                s .= ',"page":' Integer(ctrl.page)
            if (UIMacroSchema.IsShapeType(ctrl.type) && ctrl.HasProp("color") && String(ctrl.color) != "")
                s .= ',"color":"' UIMacroSchema._Esc(ctrl.color) '"'
            s .= '}'
        }
        s .= ']}'
        return s
    }

    ; JSON 字符串转义。注意 `\r` 不能直接删掉：粘贴的多行文本会因此静默丢行。
    static _Esc(v) {
        s := String(v)
        s := StrReplace(s, '\', '\\')
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, Chr(13), '\r')
        s := StrReplace(s, Chr(10), '\n')
        s := StrReplace(s, Chr(9), '\t')
        s := StrReplace(s, Chr(8), '\b')
        s := StrReplace(s, Chr(12), '\f')
        return s
    }

    static WriteStore(json, foldIndex := 0) {
        return UIMacroSchema.WriteStoreByKey(String(foldIndex), json)
    }
}
