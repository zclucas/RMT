#Requires AutoHotkey v2.0

; ===========================================================================
; 界面宏 · 自定义面板 ↔ 宏行参数绑定（v0.3 · 方案 A）
;
; 旧模型（已废弃）绑的是「指令数据配置里的序列键」（如 间隔1）。但全仓没有任何
; UI 能创建这种序列——IntervalGui.GetCmdStr() 永远返回内联文本 `间隔_500`，
; IntervalFile.toml 根本不会被创建，绑定下拉永远是空的。
;
; 新模型直接把面板控件绑到「某条宏里的某一段的某个参数」：
;   { macroId: "UI.Module2.Macro1", step: 3, param: 2 }
;     macroId : 宏条目 ID（item.ID，稳定身份）
;     step    : item.Macro 按执行器规则拆分后的第几步（1 起）
;     param   : 该步按 "_" 拆分后的第几个参数（1 起；特殊键名中的 "_" 不拆分）
;
; 运行时不再需要「临时值层」：改控件 = 直接改内存里的 item.Macro（天然对所有
; 指令类型生效），点「写入宏」才落盘。面板销毁时用快照还原。
;
; 这里全是纯字符串手术，最要紧的要求是「只改目标字节，其余一个字节都不动」。
; ===========================================================================
class UIMacroStepBinding {
    ; 绑定下拉的候选上限（超出时截断，由设计器提示）
    static MaxEntries := 2000
    ; 文本参数长度上限
    static MaxTextLen := 500
    ; 宏参数分隔符
    static ParamSep := "_"
    ; 与 SplitMacro 一致的步骤分隔符
    static StepSeparators := [",", "，", "`n", "⫶"]

    ; ------------------------------------------------------------------
    ; 宏文本拆分与范围定位
    ; ------------------------------------------------------------------

    ; 使用执行器的步骤拆分规则，保证绑定序号与实际执行一致。
    static MacroSteps(macroText) {
        return SplitMacro(String(macroText))
    }

    ; 返回非空步骤在原文中的范围，供写回时保留其他格式。
    static _StepRanges(macroText) {
        s := String(macroText)
        ranges := []
        len := StrLen(s)
        start := 1
        pos := 1
        while (pos <= len + 1) {
            ch := (pos <= len) ? SubStr(s, pos, 1) : ""
            isStepSep := false
            if (pos <= len) {
                for sep in UIMacroStepBinding.StepSeparators {
                    if (ch == sep) {
                        isStepSep := true
                        break
                    }
                }
            }
            if (pos > len || isStepSep) {
                raw := SubStr(s, start, pos - start)
                trimmed := Trim(raw)
                if (trimmed != "") {
                    leading := StrLen(raw) - StrLen(LTrim(raw))
                    ranges.Push({ start: start + leading, length: StrLen(trimmed) })
                }
                start := pos + 1
            }
            pos += 1
        }
        return ranges
    }

    ; 返回参数范围；特殊键名中的下划线不作为参数分隔符。
    static _ParamRanges(stepText) {
        s := String(stepText)
        ranges := []
        if (s == "")
            return ranges

        specialKey := ""
        try {
            for key in MySoftData.SpecialKeyMap {
                key := String(key)
                if (InStr(s, key)) {
                    specialKey := key
                    break
                }
            }
        }

        protected := []
        if (specialKey != "") {
            searchFrom := 1
            keyLen := StrLen(specialKey)
            while (pos := InStr(s, specialKey, false, searchFrom)) {
                protected.Push({ start: pos, end: pos + keyLen - 1 })
                searchFrom := pos + keyLen
            }
        }

        start := 1
        pos := 1
        len := StrLen(s)
        while (pos <= len + 1) {
            isSeparator := (pos <= len && SubStr(s, pos, 1) == UIMacroStepBinding.ParamSep)
            insideKey := false
            if (isSeparator) {
                for span in protected {
                    if (pos >= span.start && pos <= span.end) {
                        insideKey := true
                        break
                    }
                }
            }
            if (pos > len || (isSeparator && !insideKey)) {
                ranges.Push({ start: start, length: pos - start })
                start := pos + 1
            }
            pos += 1
        }
        return ranges
    }

    ; 单步转参数数组，特殊键名处理与 SplitCommand 一致。
    static SplitStep(segText) {
        s := String(segText)
        if (s == "")
            return []
        out := []
        for span in UIMacroStepBinding._ParamRanges(s)
            out.Push(SubStr(s, span.start, span.length))
        return out
    }

    ; 取第 step 段的原文；越界返回 ""
    static GetStep(macroText, step) {
        parts := UIMacroStepBinding.MacroSteps(macroText)
        st := UIMacroStepBinding._ToInt(step, 0)
        if (st < 1 || st > parts.Length)
            return ""
        return String(parts[st])
    }

    ; 读第 step 段第 param 个参数原文；越界返回 ""
    static ReadParam(macroText, step, param) {
        seg := UIMacroStepBinding.GetStep(macroText, step)
        if (seg == "")
            return ""
        segs := UIMacroStepBinding.SplitStep(seg)
        pm := UIMacroStepBinding._ToInt(param, 0)
        if (pm < 1 || pm > segs.Length)
            return ""
        return String(segs[pm])
    }

    ; 写第 step 段第 param 个参数；越界/空宏 → 原样返回，绝不抛异常。
    ; 只重写目标参数，其余字符（空格、备注、多余的 _）一个字节都不动。
    static SetParam(macroText, step, param, value) {
        return UIMacroStepBinding.SetParamEx(macroText, step, param, value).text
    }

    ; 同上，但回传「有没有真的改」→ { ok, changed, text, msg }
    ; ok=false：本次写入无效（空宏/下标越界/值含步骤分隔符或非法参数分隔符）。
    static SetParamEx(macroText, step, param, value) {
        s := String(macroText)
        if (s == "")
            return { ok: false, changed: false, text: s, msg: "宏内容为空" }
        st := UIMacroStepBinding._ToInt(step, 0)
        pm := UIMacroStepBinding._ToInt(param, 0)
        if (st < 1 || pm < 1)
            return { ok: false, changed: false, text: s, msg: "步骤/参数下标非法" }

        stepRanges := UIMacroStepBinding._StepRanges(s)
        if (st > stepRanges.Length)
            return { ok: false, changed: false, text: s, msg: Format("宏只有 {} 步，第 {} 步不存在", stepRanges.Length, st) }
        stepRange := stepRanges[st]
        stepText := SubStr(s, stepRange.start, stepRange.length)
        paramRanges := UIMacroStepBinding._ParamRanges(stepText)
        if (pm > paramRanges.Length)
            return { ok: false, changed: false, text: s, msg: Format("该步只有 {} 个参数，第 {} 个不存在", paramRanges.Length, pm) }

        newVal := String(value)
        for sep in UIMacroStepBinding.StepSeparators {
            if (InStr(newVal, sep))
                return { ok: false, changed: false, text: s, msg: "值里不能包含宏步骤分隔符" }
        }

        paramRange := paramRanges[pm]
        oldVal := SubStr(stepText, paramRange.start, paramRange.length)
        if (oldVal == newVal)
            return { ok: true, changed: false, text: s, msg: "" }

        if (InStr(newVal, UIMacroStepBinding.ParamSep)) {
            segs := UIMacroStepBinding.SplitStep(stepText)
            cmd := segs.Length ? GetCmdStr(String(segs[1])) : ""
            if (pm != 2 || cmd != "按键" || !UIMacroStepBinding._IsSpecialKey(newVal))
                return { ok: false, changed: false, text: s, msg: "值里不能包含「_」（会破坏宏参数结构）" }
        }

        valueStart := stepRange.start + paramRange.start - 1
        newText := SubStr(s, 1, valueStart - 1) newVal SubStr(s, valueStart + paramRange.length)
        return { ok: true, changed: true, text: newText, msg: "" }
    }

    static _IsSpecialKey(value) {
        try {
            for key in MySoftData.SpecialKeyMap {
                if (String(key) == String(value))
                    return true
            }
        }
        return false
    }

    ; ------------------------------------------------------------------
    ; 宏条目 / 步骤查询
    ; ------------------------------------------------------------------

    static FindMacroItem(tableItem, macroId) {
        mid := String(macroId)
        if (mid == "")
            return ""

        globalTable := ""
        try globalTable := GetItemTableGlobal(mid)
        if (IsObject(globalTable) && globalTable.HasProp("Items")) {
            for item in globalTable.Items {
                if (String(item.ID) == mid)
                    return item
            }
        }

        if (!IsObject(tableItem) || !tableItem.HasProp("Items"))
            return ""
        for item in tableItem.Items {
            if (String(item.ID) == mid)
                return item
        }
        return ""
    }

    ; → [{ step, text, cmd, segs }]（step 递增）
    static StepsOf(tableItem, macroId) {
        out := []
        item := UIMacroStepBinding.FindMacroItem(tableItem, macroId)
        if (!IsObject(item))
            return out
        parts := UIMacroStepBinding.MacroSteps(item.Macro)
        idx := 0
        for text in parts {
            idx += 1
            segs := UIMacroStepBinding.SplitStep(text)
            cmd := segs.Length ? GetCmdStr(String(segs[1])) : ""
            out.Push({ step: idx, text: String(text), cmd: cmd, segs: segs })
        }
        return out
    }

    ; ------------------------------------------------------------------
    ; 参数规格（白名单）
    ;
    ; 宏是内联文本，格式由各指令的 GetCmdStr() 决定，实际布局（已核对）：
    ;   间隔 : 间隔_{时长}                （随机：间隔_{时长}~{上限}）
    ;          或 间隔_{时长}_/_{时长}~{上限}_{备注}   ← 末段是备注，不是上限
    ;   按键 : 按键_{键名}_{动作}[_{时长}][_{次数}][_{间隔}]
    ;          后三个是「按需追加」的可选段，不存在就没有该参数
    ;   其它 : 全部按文本开放
    ;
    ; 只暴露「这一段实际存在的参数」，不做补段/删段（补段会往指令里塞它不认识的
    ; 参数，删段会丢数据）。数值型参数仅当当前值确实是纯整数时才按 int 校验，
    ; 否则按 text——这些位置允许写变量表达式（如 {Var}），不能硬判成脏数据。
    ; ------------------------------------------------------------------
    static ParamSpecs(cmd, segs) {
        out := []
        if (!IsObject(segs))
            return out
        c := GetCmdStr(String(cmd))
        n := segs.Length
        i := 2
        while (i <= n) {
            cur := String(segs[i])
            ; 备注/动作不需要绑定：间隔的第3段是备注，按键的第3段是动作（枚举更适合在
            ; 指令编辑器里改），都不列入候选。
            if ((c == "间隔" || c == "按键") && i == 3) {
                i += 1
                continue
            }
            spec := { param: i, label: "第" i "段", type: "text", store: "str" }
            if (c == "间隔") {
                if (i == 2) {
                    spec.label := InStr(cur, "~") ? "时长~上限" : "时长"
                    if (!InStr(cur, "~"))
                        spec := UIMacroStepBinding._NumericIfInt(spec, cur, 0, 3600000)
                } else {
                    spec.label := "备注"
                }
            } else if (c == "按键") {
                switch i {
                    case 2:
                        spec.label := "键名"
                        spec.allowSpecialKey := true
                    case 3:
                        ; 动作只有三种取值（KeyGui._KeyTypeText 就是按下/松开/点击），天生适合下拉。
                        ; 旧配置里若出现过别的写法，保留成额外选项，免得下拉显示成空。
                        spec.label := "动作"
                        opts := [["点击", "点击"], ["按下", "按下"], ["松开", "松开"]]
                        known := false
                        for pair in opts {
                            if (String(pair[1]) == cur) {
                                known := true
                                break
                            }
                        }
                        if (cur != "" && !known)
                            opts.Push([cur, cur])
                        spec := { param: i, label: "动作", type: "enum", store: "str", options: opts }
                    case 4:
                        spec.label := "点击时长"
                        spec := UIMacroStepBinding._NumericIfInt(spec, cur, 0, 60000)
                    case 5:
                        spec.label := "点击次数"
                        spec := UIMacroStepBinding._NumericIfInt(spec, cur, 1, 9999)
                    case 6:
                        spec.label := "每次间隔"
                        spec := UIMacroStepBinding._NumericIfInt(spec, cur, 0, 60000)
                }
            }
            out.Push(spec)
            i += 1
        }
        return out
    }

    ; 纯整数 → 收紧成 int + 值域；否则保持 text
    static _NumericIfInt(spec, cur, minV, maxV) {
        if (RegExMatch(String(cur), "^-?\d+$")) {
            spec.type := "int"
            spec.min := minV
            spec.max := maxV
        }
        return spec
    }

    ; ------------------------------------------------------------------
    ; 值校验（语义沿用旧 Coerce：int 校验范围、text 限长 500）
    ; 返回 { ok, value, msg }，value 一律是字符串（要写进宏文本）
    ; ------------------------------------------------------------------
    static Coerce(spec, raw) {
        if (!IsObject(spec))
            return { ok: false, value: "", msg: "该参数不允许绑定" }

        s := Trim(String(raw))

        switch String(spec.type) {
            case "int":
                if (s == "")
                    return { ok: false, value: "", msg: "不能为空，需要整数" }
                if (!RegExMatch(s, "^-?\d+$"))
                    return { ok: false, value: "", msg: Format("需要整数，当前是「{}」", s) }
                n := UIMacroStepBinding._ToInt(s, 0)
                minV := spec.HasProp("min") ? UIMacroStepBinding._ToInt(spec.min, -2147483647) : -2147483647
                maxV := spec.HasProp("max") ? UIMacroStepBinding._ToInt(spec.max, 2147483647) : 2147483647
                if (n < minV || n > maxV) {
                    msgRange := Format("需在 {} ~ {} 之间，当前是 {}", minV, maxV, n)
                    return { ok: false, value: "", msg: msgRange }
                }
                return { ok: true, value: String(n), msg: "" }

            case "enum":
                if (!spec.HasProp("options") || !IsObject(spec.options) || spec.options.Length = 0)
                    return { ok: false, value: "", msg: "可选项为空" }
                for pair in spec.options {
                    if (String(pair[1]) == s || String(pair[2]) == s)
                        return { ok: true, value: (spec.HasProp("store") && spec.store == "int") ? Integer(pair[1]) : String(pair[1]), msg: "" }
                }
                return { ok: false, value: "", msg: Format("不是合法选项：{}", s) }

            case "bool":
                low := StrLower(s)
                if (low == "1" || low == "true" || low == "yes" || low == "是")
                    return { ok: true, value: "1", msg: "" }
                if (low == "0" || low == "false" || low == "no" || low == "否" || low == "")
                    return { ok: true, value: "0", msg: "" }
                return { ok: false, value: "", msg: Format("只能是 1 或 0，当前是「{}」", s) }

            case "text":
                if (!(spec.HasProp("allowSep") && spec.allowSep)) {
                    hasStepSep := false
                    for sep in UIMacroStepBinding.StepSeparators {
                        if (InStr(s, sep)) {
                            hasStepSep := true
                            break
                        }
                    }
                    allowSpecialKey := spec.HasProp("allowSpecialKey")
                        && spec.allowSpecialKey && UIMacroStepBinding._IsSpecialKey(s)
                    if (hasStepSep || (InStr(s, UIMacroStepBinding.ParamSep) && !allowSpecialKey))
                        return { ok: false, value: "", msg: "值包含宏分隔符，无法安全写回" }
                }
                if (StrLen(s) > UIMacroStepBinding.MaxTextLen)
                    return { ok: false, value: "", msg: Format("文本过长（上限 {} 字）", UIMacroStepBinding.MaxTextLen) }
                return { ok: true, value: s, msg: "" }
        }
        return { ok: false, value: "", msg: "未知的值类型：" String(spec.type) }
    }

    ; 绑定控件的类型迁移：把「旧规格生成的输入框」升级到字段的标准控件
    ; （枚举→下拉框、布尔→勾选框）。只读文本不迁移。
    ; 调用点：_GetCustomSchema（所有消费方的唯一咽喉）。
    static MigrateBindingTypes(schema, tableItem) {
        if (!IsObject(schema) || !schema.HasProp("controls"))
            return schema
        for ctrl in schema.controls {
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            b := ctrl.binding
            spec := ""
            try {
                if (b.HasProp("mode") && String(b.mode) == "skip")
                    spec := UIMacroStepBinding.SkipSpec()
                else if (String(b.mode) == "data")
                    spec := UIMacroStepBinding.SpecOfData(b.kind, b.field)
                else
                    spec := UIMacroStepBinding.SpecOfBindingDeep(tableItem, b)
            } catch {
            }
            if (!IsObject(spec))
                continue
            cano := UIMacroStepBinding.CtrlTypeFor(spec)
            if (cano != "" && ctrl.HasProp("type") && ctrl.type != cano && ctrl.type != "TextBlock")
                ctrl.type := cano
        }
        return schema
    }

    ; RMT 指令可选项：与 RMTCMDGui.CategoriesMap 完全一致（扁平化，27 项）。
    ; 之前误用 LangCmdKeyArr（全量宏指令表，190+ 项），混入了大量
    ; 与 RMT 指令无关的宏编写指令（间隔/按键/搜索/循环/图形…）。
    ; 经 GetLang 取名，与编辑器下拉的语言环境一致。
    static _RmtCmdOptions() {
        keys := ["截图", "截图提取文本", "自由贴",
            "启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠",
            "启用鼠标加速", "禁用鼠标加速",
            "显示菜单", "关闭菜单", "打开界面窗口", "关闭界面窗口",
            "禁用模块", "取消禁用模块", "暂停所有宏", "恢复所有宏", "终止所有宏",
            "开启变量监视", "关闭变量监视", "开启指令显示", "关闭指令显示",
            "关闭软件", "休眠", "重载"]
        opts := []
        for k in keys {
            nm := k
            try nm := GetLang(k)
            catch {
            }
            nm := String(nm)
            if (nm == "")
                nm := k
            opts.Push([nm, nm])
        }
        return opts
    }

    ; 控件类型能否表达该参数
    static CtrlTypeFor(spec) {
        if (!IsObject(spec))
            return ""
        switch String(spec.type) {
            case "enum": return "ComboBox"
            case "bool": return "CheckBox"
            case "int", "text": return "Edit"
        }
        return ""
    }

    static CtrlTypeHint(spec) {
        switch UIMacroStepBinding.CtrlTypeFor(spec) {
            case "ComboBox": return "下拉框"
            case "CheckBox": return "勾选框"
            case "Edit":     return "输入框"
        }
        return ""
    }

    static CanBindField(ctrlType, spec) {
        if (!IsObject(spec))
            return false
        ; 文本控件是「只读显示」，不管字段是什么类型都能显示
        if (String(ctrlType) == "TextBlock")
            return true
        need := UIMacroStepBinding.CtrlTypeFor(spec)
        if (need == "")
            return false
        return (String(ctrlType) == need)
    }

    ; ------------------------------------------------------------------
    ; 绑定键 & 候选列表
    ; ------------------------------------------------------------------
    static BindingKey(binding) {
        if (!IsObject(binding))
            return ""
        mid := String(binding.macroId)
        mode := binding.HasProp("mode") ? String(binding.mode) : "step"
        if (mode == "data")
            return UIMacroStepBinding.DataBindingKeyOf(mid, binding.kind, binding.serial, binding.field)
                . UIMacroStepBinding.HopsKey(binding)
        if (mode == "skip")
            return mid "|skip|" String(binding.step) . UIMacroStepBinding.HopsKey(binding)
        key := mid "|step|" String(binding.step) "|" String(binding.param)
        ; 嵌套路径参与键：同一条宏里「顶层第3步」和「真分支里第3步」是两个不同绑定
        key .= UIMacroStepBinding.HopsKey(binding)
        return key
    }

    ; hops → 可进键的后缀（无 hops 返回空串）
    static HopsKey(binding) {
        if (!IsObject(binding) || !binding.HasProp("hops") || !IsObject(binding.hops))
            return ""
        s := ""
        for h in binding.hops {
            if (!IsObject(h))
                return "|hops:invalid"
            s .= "|h" h.step ":" h.serial ":" h.field ":" h.index
        }
        return s
    }

    static BindingKeyOf(macroId, step, param) {
        return String(macroId) "|step|" String(step) "|" String(param)
    }

    static DataBindingKeyOf(macroId, kind, serial, field) {
        return String(macroId) "|data|" String(kind) "|" String(serial) "|" String(field)
    }

    ; 字段是否适用于该数据对象当前状态（如搜索类型决定相似度/检索文本谁有效）。
    ; 无 onlyTypes 的字段恒适用；数据对象缺 SearchType 时按适用处理（宁多勿缺）。
    static _FieldApplies(spec, obj) {
        if (!IsObject(spec) || !spec.HasProp("onlyTypes") || !IsObject(spec.onlyTypes))
            return true
        if (!IsObject(obj) || !obj.HasProp("SearchType"))
            return true
        st := UIMacroStepBinding._ToInt(obj.SearchType, 0)
        for v in spec.onlyTypes {
            if (UIMacroStepBinding._ToInt(v, -999999) == st)
                return true
        }
        return false
    }

    ; 候选条目 → 绑定键（设计器比较「当前下拉」与「已绑定」时用）
    static TargetKey(target) {
        if (!IsObject(target))
            return ""
        if (target.HasProp("mode") && String(target.mode) == "data")
            return UIMacroStepBinding.DataBindingKeyOf(target.macroId, target.kind, target.serial, target.field)
            . UIMacroStepBinding.HopsKey(target)
        if (target.HasProp("mode") && String(target.mode) == "skip")
            return String(target.macroId) "|skip|" String(target.step) . UIMacroStepBinding.HopsKey(target)
        return UIMacroStepBinding.BindingKeyOf(target.macroId, target.step, target.param)
            . UIMacroStepBinding.HopsKey(target)
    }

    ; → { items: [...], truncated }
    ; 条目（两种模式统一字段，designer 只按 mode 取需要的）：
    ;   step: { mode:"step", macroId, step, param, cmd, spec, fieldLabel, macroLabel, label }
    ;   data: { mode:"data", macroId, kind, serial, field, hops?, spec, fieldLabel, macroLabel, label }
    ; 顺序：宏（Items 数组顺序）→ 步 → 参数
    static CollectTargets(tableItem, maxEntries := 0) {
        out := []
        if (!IsObject(tableItem) || !tableItem.HasProp("Items"))
            return { items: out, truncated: false }
        for item in tableItem.Items
            UIMacroStepBinding._CollectForItem(item, out)
        return UIMacroStepBinding._Truncate(out, maxEntries)
    }

    ; 只取某一条宏的候选（设计器：控件先绑宏，再在该宏内选步骤）
    static CollectTargetsForMacro(tableItem, macroId, maxEntries := 0) {
        out := []
        item := UIMacroStepBinding.FindMacroItem(tableItem, macroId)
        if (!IsObject(item))
            return { items: out, truncated: false }
        UIMacroStepBinding._CollectForItem(item, out)
        return UIMacroStepBinding._Truncate(out, maxEntries)
    }

    static _Truncate(out, maxEntries) {
        if (maxEntries <= 0)
            maxEntries := UIMacroStepBinding.MaxEntries
        truncated := false
        if (out.Length > maxEntries) {
            truncated := true
            while (out.Length > maxEntries)
                out.Pop()
        }
        return { items: out, truncated: truncated }
    }

    ; 一条宏 → 逐步展开；序列型步骤产出 data 型条目，内联步骤产出 step 型条目
    static _CollectForItem(item, out) {
        ; 候选与挑选器共用同一棵树（含嵌套 hops 叶），保证两边的绑定键能对上
        nodes := UIMacroStepBinding.BuildTree(item)
        UIMacroStepBinding._FlattenTree(nodes, "", out)
    }

    ; 树 → 扁平候选。prefix 累积容器/步骤上下文（如「■ 真分支 · 第1步 间隔_900 ·」）
    static _FlattenTree(nodes, prefix, out) {
        for n in nodes {
            if (n.type != "leaf") {
                childPrefix := prefix
                if (n.HasProp("label") && n.label != "")
                    childPrefix .= (prefix == "" ? "" : " · ") n.label
                UIMacroStepBinding._FlattenTree(n.children, childPrefix, out)
                continue
            }
            t := n.target
            entry := {
                mode: t.mode,
                macroId: t.macroId,
                spec: t.spec,
                fieldLabel: t.fieldLabel,
                macroLabel: "",
                label: prefix n.label
            }
            if (String(t.mode) == "data") {
                entry.kind := t.kind
                entry.serial := t.serial
                entry.field := t.field
                if (t.HasProp("hops") && IsObject(t.hops) && t.hops.Length > 0)
                    entry.hops := t.hops
            } else {
                entry.step := t.step
                entry.param := t.param
                entry.cmd := t.HasProp("cmd") ? t.cmd : ""
                if (t.HasProp("hops") && IsObject(t.hops) && t.hops.Length > 0)
                    entry.hops := t.hops
            }
            out.Push(entry)
        }
    }

    ; 绑定 → 当前 spec（取不到返回 ""）
    ; spec 是按「当前宏文本」现算的，所以每次渲染/回填都要重新取一次
    static SpecOfBinding(tableItem, binding) {
        if (!IsObject(binding))
            return ""
        if (binding.HasProp("mode") && String(binding.mode) == "data")
            return UIMacroStepBinding.SpecOfData(binding.kind, binding.field)
        if (binding.HasProp("hops") && IsObject(binding.hops) && binding.hops.Length > 0)
            return UIMacroStepBinding.SpecOfBindingDeep(tableItem, binding)
        item := UIMacroStepBinding.FindMacroItem(tableItem, binding.macroId)
        if (!IsObject(item))
            return ""
        seg := UIMacroStepBinding.GetStep(item.Macro, binding.step)
        if (seg == "")
            return ""
        segs := UIMacroStepBinding.SplitStep(seg)
        cmd := segs.Length ? GetCmdStr(String(segs[1])) : ""
        pm := UIMacroStepBinding._ToInt(binding.param, 0)
        for spec in UIMacroStepBinding.ParamSpecs(cmd, segs) {
            if (spec.param == pm)
                return spec
        }
        return ""
    }

    ; SpecOfBinding 的嵌套版：spec 相对「最终容器文本」而言（hops 缺省 = 顶层宏）
    static SpecOfBindingDeep(tableItem, binding) {
        if (!IsObject(binding))
            return ""
        hops := binding.HasProp("hops") ? binding.hops : ""
        r := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r.ok)
            return ""
        seg := UIMacroStepBinding.GetStep(r.text, binding.step)
        if (seg == "")
            return ""
        segs := UIMacroStepBinding.SplitStep(seg)
        cmd := segs.Length ? GetCmdStr(String(segs[1])) : ""
        pm := UIMacroStepBinding._ToInt(binding.param, 0)
        for spec in UIMacroStepBinding.ParamSpecs(cmd, segs) {
            if (spec.param == pm)
                return spec
        }
        return ""
    }

    ; ------------------------------------------------------------------
    ; 序列型（data 模式）：参数在指令数据文件里，不在宏文本里
    ;
    ; 判定看步骤原文：SplitSerialTextAndNumbers 拆出「文本 + 尾部数字」，
    ; 若尾部数字非空且 DataFileMap 认得这个文本，就是序列引用（如 变量2）。
    ;
    ; field 里的 ".N" 表示数组下标（1 起）：VariableArr.1 → data.VariableArr[1]。
    ; 没有 .N 就直接当属性名。写之前校验数组长度，越界拒绝，绝不擅自扩数组。
    ; 只开放下表这 7 个字段，其余 kind 一律不出现在候选里。
    ; ------------------------------------------------------------------

    ; 步骤原文 → { mode, kind, serial }（无法判定时 mode 为 "step" 内联）
    ;
    ; 序列步骤在宏文本里有两种形态：
    ;   指令N          （无备注）
    ;   指令N_备注     （带备注 —— 备注**不是**内联参数！）
    ; 之前只认第一种：带备注的序列步骤（如 RMT指令1_终止所有宏、变量2_22）
    ; 会被误判成内联，整棵树退化成「第2段 输入框」，数据字段全部消失。
    ;
    ; 判定顺序：
    ;   1) 整段「文本+尾部数字」且 DataFileMap 认得 → 序列（无备注形态）
    ;   2) 第一个下划线前的部分能拆出「文本+数字」且认得 → 序列带备注
    ;      （间隔/按键 除外——它们的编辑器写的就是内联参数，下划线后是真参数）
    ;   3) 其余 → 内联
    static StepModeOf(stepText) {
        s := GetCmdStr(Trim(String(stepText)))
        isObj := (IsObject(MySoftData) && MySoftData.HasProp("DataFileMap") && IsObject(MySoftData.DataFileMap))
        try {
            ; 1) 无备注形态
            textOnly := "", numbersOnly := ""
            SplitSerialTextAndNumbers(s, &textOnly, &numbersOnly)
            if (numbersOnly != "" && isObj && MySoftData.DataFileMap.Has(textOnly))
                return { mode: "data", kind: textOnly, serial: textOnly numbersOnly }
            ; 2) 带备注形态：取第一个下划线前的「指令+数字」
            if (InStr(s, "_")) {
                head := SubStr(s, 1, InStr(s, "_") - 1)
                textOnly := "", numbersOnly := ""
                SplitSerialTextAndNumbers(head, &textOnly, &numbersOnly)
                if (numbersOnly != "" && isObj && MySoftData.DataFileMap.Has(textOnly)
                    && textOnly != "间隔" && textOnly != "按键")
                    return { mode: "data", kind: textOnly, serial: textOnly numbersOnly }
            }
        } catch {
        }
        return { mode: "step", kind: "", serial: "" }
    }

    static DataFieldList(kind) {
        switch String(kind) {
            case "变量": return ["VariableArr.1", "MinVariableArr.1", "MaxVariableArr.1"]
            case "循环": return ["LoopCount"]
            case "运行": return ["Target"]
            case "等待": return ["Interval", "Param1"]
            ; 搜索家族共用 SearchData、共用 SearchOnTrigger（MacroUtil:164）：
            ; 只留常用 4 项；搜索颜色/OCR类型/搜索类型 按需求不开放。
            case "搜索", "搜索Pro", "搜索All", "搜索Combo", "组合搜索", "搜索Multi":
                return ["Similar", "SearchText", "SearchCount", "SearchInterval"]
            ; 以下均为执行路径已核实消费的标量字段（MacroUtil / CountDownUtil）
            case "输出": return ["Text"]
            case "鼠标移动", "移动": return ["PosX", "PosY", "Speed"]
            case "增量移动": return ["DeltaX", "DeltaY", "Count", "Interval"]
            case "倒计时": return ["Seconds"]
            ; RMT 指令：指令名是固定集合（下拉框），菜单序号只在「显示菜单」时用
            case "RMT指令": return ["CmdStr", "MenuIndex"]
        }
        return []
    }

    static _DataSpecOfOne(kind, field) {
        switch String(kind) {
            case "变量":
                switch String(field) {
                    case "VariableArr.1":    return { label: "赋值内容", type: "text", store: "str" }
                    case "MinVariableArr.1": return { label: "随机下限", type: "int", min: 0, max: 999999999, store: "int" }
                    case "MaxVariableArr.1": return { label: "随机上限", type: "int", min: 0, max: 999999999, store: "int" }
                }
            case "循环":
                if (String(field) == "LoopCount")
                    return { label: "循环次数", type: "int", min: -1, max: 999999, store: "int" }
            case "运行":
                if (String(field) == "Target")
                    return { label: "目标", type: "text", store: "str" }
            case "等待":
                switch String(field) {
                    case "Interval": return { label: "检测间隔", type: "int", min: 0, max: 60000, store: "int" }
                    case "Param1":   return { label: "主参数", type: "text", store: "str" }
                }
            case "输出":
                ; 正文：数据文件存储，允许逗号/下划线（allowSep）
                if (String(field) == "Text")
                    return { label: "输出内容", type: "text", store: "str", allowSep: true }
            case "鼠标移动", "移动":
                switch String(field) {
                    case "PosX":  return { label: "目标 X", type: "int", min: 0, max: 65535, store: "int" }
                    case "PosY":  return { label: "目标 Y", type: "int", min: 0, max: 65535, store: "int" }
                    case "Speed": return { label: "移动速度", type: "int", min: 0, max: 100, store: "int" }
                }
            case "增量移动":
                ; 这四项在执行侧支持 {变量}，所以按文本开放（allowSep：允许下划线）
                switch String(field) {
                    case "DeltaX":   return { label: "横向位移", type: "text", store: "str", allowSep: true }
                    case "DeltaY":   return { label: "纵向位移", type: "text", store: "str", allowSep: true }
                    case "Count":    return { label: "偏移次数", type: "text", store: "str", allowSep: true }
                    case "Interval": return { label: "每次间隔", type: "text", store: "str", allowSep: true }
                }
            case "倒计时":
                if (String(field) == "Seconds")
                    return { label: "秒数", type: "int", min: 1, max: 86400, store: "int" }
            case "RMT指令":
                switch String(field) {
                    case "CmdStr":    return { label: "指令", type: "enum", store: "str", options: UIMacroStepBinding._RmtCmdOptions() }
                    case "MenuIndex": return { label: "菜单序号", type: "int", min: 1, max: 99, store: "int" }
                }
            case "搜索", "搜索Pro", "搜索All", "搜索Combo", "组合搜索", "搜索Multi":
                switch String(field) {
                    ; onlyTypes：仅当搜索类型匹配时该字段才有意义（挑选器据此过滤）
                    case "Similar":        return { label: "相似度", type: "int", min: 50, max: 100, store: "int", onlyTypes: [1, 4], typeNote: "图片搜索" }
                    case "SearchText":     return { label: "检索文本", type: "text", store: "str", allowSep: true, onlyTypes: [3, 6], typeNote: "文本搜索" }
                    case "SearchCount":    return { label: "搜索次数", type: "int", min: -1, max: 9999, store: "int" }
                    case "SearchInterval": return { label: "搜索间隔", type: "int", min: 0, max: 60000, store: "int" }
                }
        }
        return ""
    }

    static SpecOfData(kind, field) {
        return UIMacroStepBinding._DataSpecOfOne(kind, field)
    }

    static DataFieldsOf(kind) {
        fields := Map()
        for f in UIMacroStepBinding.DataFieldList(kind) {
            spec := UIMacroStepBinding._DataSpecOfOne(kind, f)
            if (IsObject(spec))
                fields[f] := spec.label
        }
        return fields
    }

    ; field 拆成「属性名 + 数组下标」（无下标时 index = 0）
    static _SplitField(field, &propName, &index) {
        s := String(field)
        pos := InStr(s, ".")
        if (pos > 0) {
            propName := SubStr(s, 1, pos - 1)
            index := UIMacroStepBinding._ToInt(SubStr(s, pos + 1), 0)
        } else {
            propName := s
            index := 0
        }
    }

    ; 取数据对象（带缓存）；取不到返回 ""
    static GetDataObj(serial) {
        try {
            obj := GetMacroCMDData(String(serial))
            return IsObject(obj) ? obj : ""
        } catch {
            return ""
        }
    }

    ; 读序列字段 → { ok, value, msg }
    static ReadData(serial, field) {
        obj := UIMacroStepBinding.GetDataObj(serial)
        if (!IsObject(obj))
            return { ok: false, value: "", msg: "指令数据不存在（可能已被删除）" }
        propName := ""
        index := 0
        UIMacroStepBinding._SplitField(field, &propName, &index)
        if (!obj.HasProp(propName))
            return { ok: false, value: "", msg: "字段不存在：" propName }
        val := obj.%propName%
        if (index > 0) {
            if (!IsObject(val))
                return { ok: false, value: "", msg: "字段不是数组：" propName }
            if (index > val.Length)
                return { ok: false, value: "", msg: Format("数组越界：{} 只有 {} 项", propName, val.Length) }
            return { ok: true, value: String(val[index]), msg: "" }
        }
        return { ok: true, value: String(val), msg: "" }
    }

    ; 写序列字段（只改内存缓存，不落盘）→ { ok, changed, msg }
    static SetData(serial, field, value) {
        obj := UIMacroStepBinding.GetDataObj(serial)
        if (!IsObject(obj))
            return { ok: false, changed: false, msg: "指令数据不存在（可能已被删除）" }
        propName := ""
        index := 0
        UIMacroStepBinding._SplitField(field, &propName, &index)
        if (!obj.HasProp(propName))
            return { ok: false, changed: false, msg: "字段不存在：" propName }

        if (index > 0) {
            arr := obj.%propName%
            if (!IsObject(arr))
                return { ok: false, changed: false, msg: "字段不是数组：" propName }
            if (index > arr.Length)
                return { ok: false, changed: false, msg: Format("数组越界：{} 只有 {} 项", propName, arr.Length) }
            if (String(arr[index]) == String(value))
                return { ok: true, changed: false, msg: "" }
            arr[index] := value
            obj.%propName% := arr
            return { ok: true, changed: true, msg: "" }
        }

        if (String(obj.%propName%) == String(value))
            return { ok: true, changed: false, msg: "" }
        obj.%propName% := value
        return { ok: true, changed: true, msg: "" }
    }

    ; 落盘（点「写入宏」时才调）
    static SaveData(serial) {
        obj := UIMacroStepBinding.GetDataObj(serial)
        if (!IsObject(obj))
            return false
        try {
            SaveMacroCMDData(obj)
            return true
        } catch {
            return false
        }
    }

    ; ------------------------------------------------------------------
    ; 占用索引：一个宏参数只被一个面板绑（避免两个面板互相覆盖）
    ;
    ; 扫描 UIPanelCustom_*.json，按「活着的折叠框」过滤孤儿文件（不删文件）。
    ; 取不到表时退化为全部计入。
    ; ------------------------------------------------------------------
    static OccupiedMap(exceptKey := "", exceptIndex := "") {
        occupied := Map()
        dir := ""
        p := UIMacroSchema.StorePathByKey("0")
        SplitPath(p, , &dir)
        if (dir == "" || !DirExist(dir))
            return occupied

        skipKey := String(exceptKey)
        skipIndex := String(exceptIndex)
        liveInfo := UIMacroStepBinding._LiveFoldIds()

        loop files, dir "\UIPanelCustom_*.json" {
            fileName := A_LoopFileName
            storeKey := RegExReplace(fileName, "^UIPanelCustom_(.*)\.json$", "$1")
            if (storeKey == "" || storeKey == fileName)
                continue
            if (skipKey != "" && storeKey == skipKey)
                continue
            if (skipIndex != "" && storeKey == skipIndex)
                continue
            if (!UIMacroStepBinding._IsLiveStoreKey(storeKey, liveInfo))
                continue

            schema := UIMacroSchema.Parse(UIMacroSchema.ReadStoreByKey(storeKey))
            if (!IsObject(schema))
                continue
            for ctrl in schema.controls {
                if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                    continue
                bindKey := UIMacroStepBinding.BindingKey(ctrl.binding)
                occupied[bindKey] := { key: storeKey, text: ctrl.text }
            }
        }
        return occupied
    }

    ; 按「已算好的绑定键」判占用（设计器用，兼容 step/data 两种模式）
    static IsOccupiedByKey(bindKey, exceptKey := "", exceptIndex := "") {
        k := String(bindKey)
        if (k == "")
            return false
        return UIMacroStepBinding.OccupiedMap(exceptKey, exceptIndex).Has(k)
    }

    static IsOccupied(macroId, step, param, exceptKey := "", exceptIndex := "") {
        return UIMacroStepBinding.OccupiedMap(exceptKey, exceptIndex)
            .Has(UIMacroStepBinding.BindingKeyOf(macroId, step, param))
    }

    static _LiveFoldIds() {
        ids := Map()
        try {
            tableItem := GetTableBySymbol("UI")
            if (!IsObject(tableItem) || !tableItem.HasProp("Folds"))
                return { ok: false, ids: ids, count: 0 }
            for fold in tableItem.Folds {
                id := UIMacroSchema.FoldKey(fold)
                if (id != "")
                    ids[id] := true
            }
            return { ok: true, ids: ids, count: tableItem.Folds.Length }
        } catch {
            return { ok: false, ids: ids, count: 0 }
        }
    }

    static _IsLiveStoreKey(storeKey, liveInfo) {
        if (!IsObject(liveInfo) || !liveInfo.ok)
            return true
        if (liveInfo.ids.Has(storeKey))
            return true
        if (RegExMatch(storeKey, "^\d+$")) {
            idx := UIMacroStepBinding._ToInt(storeKey, 0)
            if (idx >= 1 && liveInfo.count >= idx)
                return true
        }
        return false
    }

    ; ------------------------------------------------------------------
    ; 内部工具
    ; ------------------------------------------------------------------
    static _ToInt(v, def) {
        if (IsNumber(v))
            try {
                n := Integer(v)
                if (n >= -2147483648 && n <= 2147483647)
                    return n
            }
        return def
    }

    ; ==================================================================
    ; 嵌套容器（hops）：支持绑定「如果Pro 真假分支 / 循环体」等嵌套宏里的指令
    ;
    ; 绑定结构（step 模式的可选扩展）：
    ;   { macroId, mode:"step", step, param, hops:[hop, ...] }
    ; hop := { step, kind, serial, field, index }
    ;   含义：在「当前容器文本」的第 step 步有一个序列指令 serial（类型 kind），
    ;   沿它的 field（数组字段取第 index 个，index=0 表示标量）走进下一层宏文本。
    ;   最后一跳之后，step/param 相对「最终容器文本」而言。
    ; 无 hops = 现状（容器就是顶层 item.Macro），老配置零迁移。
    ; ==================================================================
    static MaxHops := 5

    ; hops 规格化：合法 → 规范化数组；非法 → ""（调用方应丢弃整个绑定）
    static NormalizeHops(hopsRaw) {
        if (!IsObject(hopsRaw))
            return ""
        out := []
        for h in hopsRaw {
            if (!IsObject(h))
                return ""
            st := UIMacroStepBinding._ToInt(h.HasProp("step") ? h.step : 0, 0)
            kind := h.HasProp("kind") ? String(h.kind) : ""
            serial := h.HasProp("serial") ? String(h.serial) : ""
            field := h.HasProp("field") ? String(h.field) : ""
            idx := UIMacroStepBinding._ToInt(h.HasProp("index") ? h.index : 0, 0)
            if (st < 1 || kind == "" || serial == "" || field == "" || idx < 0)
                return ""
            out.Push({ step: st, kind: kind, serial: serial, field: field, index: idx })
        }
        if (out.Length < 1 || out.Length > UIMacroStepBinding.MaxHops)
            return ""
        return out
    }

    ; 某序列型指令里可作为「嵌套宏文本容器」的字段。
    ; obj 为该指令的数据对象（用于枚举数组容器，如如果Pro 的分支列表）。
    ; 返回 [{field, index, label}]；不在白名单 → []（树上不可展开）
    static HopContainers(kind, obj) {
        switch String(kind) {
            case "如果":
                return [{ field: "TrueMacro", index: 0, label: "真分支" },
                    { field: "FalseMacro", index: 0, label: "假分支" }]
            case "如果Pro":
                out := []
                if (IsObject(obj) && obj.HasProp("MacroArr") && IsObject(obj.MacroArr)) {
                    loop obj.MacroArr.Length
                        out.Push({ field: "MacroArr", index: A_Index, label: "分支" A_Index })
                }
                if (IsObject(obj) && obj.HasProp("DefaultMacro"))
                    out.Push({ field: "DefaultMacro", index: 0, label: "默认分支" })
                return out
            case "循环":
                return [{ field: "LoopBody", index: 0, label: "循环体" }]
            ; 搜索家族自带真假分支宏，SearchUtil:125 经 RunMacroBodyOnce 执行
            case "搜索", "搜索Pro", "搜索All", "搜索Combo", "组合搜索", "搜索Multi":
                return [{ field: "TrueMacro", index: 0, label: "真分支" },
                    { field: "FalseMacro", index: 0, label: "假分支" }]
        }
        return []
    }

    ; 单跳读：数据对象里的宏文本字段（数组字段取第 index 个）
    static _ReadHopText(obj, field, index) {
        if (!IsObject(obj) || !obj.HasProp(field))
            return ""
        if (index >= 1) {
            arr := obj.%field%
            if (!IsObject(arr) || index > arr.Length)
                return ""
            return String(arr[index])
        }
        return String(obj.%field%)
    }

    ; 单跳写回
    static _WriteHopText(obj, field, index, text) {
        if (!IsObject(obj) || !obj.HasProp(field))
            return false
        if (index >= 1) {
            arr := obj.%field%
            if (!IsObject(arr) || index > arr.Length)
                return false
            arr[index] := text
            obj.%field% := arr
            return true
        }
        obj.%field% := text
        return true
    }

    ; 沿 hops 解析最终宏文本。
    ; 返回 { ok, text, msg, owner }：
    ;   owner = { type:"item", item, tableItem }               （无 hops）
    ;         = { type:"hop", serial, kind, field, index, obj }（有 hops，最后一级）
    static ResolveContainer(tableItem, macroId, hops) {
        item := UIMacroStepBinding.FindMacroItem(tableItem, macroId)
        if (!IsObject(item))
            return { ok: false, msg: "宏不存在（可能已被删除）" }
        actualTable := ""
        try actualTable := GetItemTableGlobal(macroId)
        if (IsObject(actualTable) && actualTable.HasProp("Items"))
            tableItem := actualTable
        text := String(item.Macro)
        owner := { type: "item", item: item, tableItem: tableItem }
        if (IsObject(hops)) {
            for hop in hops {
                if (!IsObject(hop))
                    return { ok: false, msg: "绑定路径无效" }
                ; 校验这一跳：当前文本的第 step 步必须就是 hop 记录的那条序列指令
                stepText := UIMacroStepBinding.GetStep(text, hop.step)
                sm := UIMacroStepBinding.StepModeOf(stepText)
                if (String(sm.mode) != "data" || String(sm.serial) != String(hop.serial)
                    || String(sm.kind) != String(hop.kind))
                    return { ok: false, msg: "绑定路径已失效（嵌套宏可能已被修改）" }
                obj := UIMacroStepBinding.GetDataObj(hop.serial)
                if (!IsObject(obj))
                    return { ok: false, msg: "嵌套指令数据不存在：" hop.serial }
                text := UIMacroStepBinding._ReadHopText(obj, hop.field, hop.index)
                owner := { type: "hop", serial: String(hop.serial), kind: String(hop.kind),
                    field: String(hop.field), index: Integer(hop.index), obj: obj }
            }
        }
        return { ok: true, text: text, owner: owner, msg: "" }
    }

    ; 把最终容器文本写回它的归属（item.Macro 或数据对象字段）
    static _WriteContainerBack(owner, text) {
        if (!IsObject(owner))
            return false
        if (owner.type == "item") {
            if (!IsObject(owner.item))
                return false
            owner.item.Macro := text
            return true
        }
        if (owner.type == "hop")
            return UIMacroStepBinding._WriteHopText(owner.obj, owner.field, owner.index, text)
        return false
    }

    ; 按容器类型落盘
    static SaveContainer(owner) {
        if (!IsObject(owner))
            return false
        if (owner.type == "item") {
            try {
                SaveTableItemInfo(owner.tableItem)
                return true
            } catch {
                return false
            }
        }
        if (owner.type == "hop")
            return UIMacroStepBinding.SaveData(owner.serial)
        return false
    }

    ; 绑定值读取（step 模式，含 hops）→ { ok, value, msg }
    static ReadParamDeep(tableItem, binding) {
        hops := (IsObject(binding) && binding.HasProp("hops")) ? binding.hops : ""
        r := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r.ok)
            return { ok: false, msg: r.msg }
        return { ok: true, value: UIMacroStepBinding.ReadParam(r.text, binding.step, binding.param) }
    }

    ; 绑定值写入（step 模式，含 hops）。只改内存，落盘由调用方按 owner 调 SaveContainer。
    ; 返回 { ok, changed, text(最终容器新文本), owner, msg }
    static SetParamDeep(tableItem, binding, value) {
        hops := (IsObject(binding) && binding.HasProp("hops")) ? binding.hops : ""
        r := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r.ok)
            return { ok: false, changed: false, msg: r.msg }
        w := UIMacroStepBinding.SetParamEx(r.text, binding.step, binding.param, value)
        if (!w.ok)
            return { ok: false, changed: false, msg: w.msg }
        if (w.changed) {
            if (!UIMacroStepBinding._WriteContainerBack(r.owner, w.text))
                return { ok: false, changed: false, msg: "嵌套容器写回失败" }
        }
        return { ok: true, changed: w.changed, text: w.text, owner: r.owner, msg: "" }
    }

    ; ---- 步骤跳过开关（复用系统既有的 🚫 前缀机制） ----
    ; 勾选 = 执行（无前缀），取消 = 跳过（加前缀）。MacroUtil:212 就是靠这个前缀跳步。
    static ReadSkipDeep(tableItem, binding) {
        hops := (IsObject(binding) && binding.HasProp("hops")) ? binding.hops : ""
        r := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r.ok)
            return { ok: false, msg: r.msg }
        stepText := UIMacroStepBinding.GetStep(r.text, binding.step)
        if (stepText == "")
            return { ok: false, msg: "该步骤不存在" }
        return { ok: true, skipped: (SubStr(stepText, 1, 2) == "🚫") }
    }

    ; skip=true 表示跳过。只改内存，落盘由调用方按 owner 处理。
    static SetSkipDeep(tableItem, binding, skip) {
        hops := (IsObject(binding) && binding.HasProp("hops")) ? binding.hops : ""
        r := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r.ok)
            return { ok: false, changed: false, msg: r.msg }
        stepText := UIMacroStepBinding.GetStep(r.text, binding.step)
        if (stepText == "")
            return { ok: false, changed: false, msg: "该步骤不存在" }
        curSkip := (SubStr(stepText, 1, 2) == "🚫")
        wantSkip := !!skip
        if (curSkip == wantSkip)
            return { ok: true, changed: false, text: r.text, owner: r.owner, msg: "" }
        newStep := wantSkip ? ("🚫" stepText) : Trim(SubStr(stepText, 3), " ")
        if (newStep == "")
            return { ok: false, changed: false, msg: "步骤内容为空" }
        newText := UIMacroStepBinding.SetStepText(r.text, binding.step, newStep)
        if (!UIMacroStepBinding._WriteContainerBack(r.owner, newText))
            return { ok: false, changed: false, msg: "写回失败" }
        return { ok: true, changed: true, text: newText, owner: r.owner, msg: "" }
    }

    ; 替换宏文本里第 step 步（其余步骤原样保留）
    static SetStepText(macroText, step, newStep) {
        s := String(macroText)
        st := UIMacroStepBinding._ToInt(step, 0)
        ranges := UIMacroStepBinding._StepRanges(s)
        if (st < 1 || st > ranges.Length)
            return macroText
        range := ranges[st]
        return SubStr(s, 1, range.start - 1) String(newStep) SubStr(s, range.start + range.length)
    }

    ; 跳过开关的字段规格（勾选框）
    static SkipSpec() {
        return { label: "是否执行", type: "bool", store: "bool" }
    }

    ; ==================================================================
    ; 绑定树（挑选器数据源）：递归展开「宏 → 步骤 → 字段 / 嵌套容器」
    ;
    ; 节点：{ type:"leaf", label, spec, target }
    ;       { type:"step"|"container", label, children }
    ; target 是可直接转成 binding 的候选对象（含 hops 累积）。
    ; 循环引用 / 超深由 _HopsPlus → NormalizeHops 兜底（返回 "" 即剪枝）。
    ; ==================================================================
    static BuildTree(item) {
        if (!IsObject(item))
            return []
        return UIMacroStepBinding._TreeOfText(String(item.Macro), [], 0, String(item.ID))
    }

    static _TreeOfText(macroText, hopsSoFar, depth, macroId) {
        nodes := []
        parts := UIMacroStepBinding.MacroSteps(macroText)
        st := 0
        for text in parts {
            st += 1
            if (Trim(text) == "")
                continue
            sm := UIMacroStepBinding.StepModeOf(text)
            stepLabel := "第" st "步  " text
            if (String(sm.mode) == "data") {
                children := []
                ; 数据字段按 serial/field 读写；hops 仍需保留，用于区分嵌套上下文。
                for field in UIMacroStepBinding.DataFieldList(sm.kind) {
                    spec := UIMacroStepBinding._DataSpecOfOne(sm.kind, field)
                    if (!IsObject(spec))
                        continue
                    children.Push({ type: "leaf", label: spec.label, spec: spec,
                        target: { mode: "data", macroId: macroId, kind: sm.kind, serial: sm.serial,
                            field: field, spec: spec, fieldLabel: spec.label, hops: hopsSoFar } })
                }
                ; 嵌套容器：如果Pro 分支 / 循环体 …
                obj := UIMacroStepBinding.GetDataObj(sm.serial)
                for c in UIMacroStepBinding.HopContainers(sm.kind, obj) {
                    hop := { step: st, kind: sm.kind, serial: sm.serial, field: c.field, index: c.index }
                    hops2 := UIMacroStepBinding._HopsPlus(hopsSoFar, hop)
                    if (hops2 == "")
                        continue    ; 超深 / 成环 → 剪枝
                    inner := UIMacroStepBinding._TreeOfText(
                        UIMacroStepBinding._ReadHopText(obj, c.field, c.index), hops2, depth + 1, macroId)
                    children.Push({ type: "container", label: "■ " c.label, children: inner })
                }
                if (children.Length == 0)
                    continue
                ; 步骤级开关：勾选=执行，取消=跳过（🚫）
                children.InsertAt(1, { type: "leaf", label: "是否执行（勾选=执行）", spec: UIMacroStepBinding.SkipSpec()
                    , target: { mode: "skip", macroId: macroId, step: st, hops: hopsSoFar } })
                nodes.Push({ type: "step", label: stepLabel, children: children })
                continue
            }
            ; 内联：每个实际存在的段是一个叶
            segs := UIMacroStepBinding.SplitStep(text)
            cmd := segs.Length ? GetCmdStr(String(segs[1])) : ""
            leafs := []
            for spec in UIMacroStepBinding.ParamSpecs(cmd, segs) {
                leafs.Push({ type: "leaf", label: spec.label, spec: spec,
                    target: { mode: "step", macroId: macroId, step: st, param: spec.param,
                        hops: hopsSoFar, spec: spec, fieldLabel: spec.label } })
            }
            ; 内联步骤同样带「是否执行」开关
            leafs.InsertAt(1, { type: "leaf", label: "是否执行（勾选=执行）", spec: UIMacroStepBinding.SkipSpec()
                , target: { mode: "skip", macroId: macroId, step: st, hops: hopsSoFar } })
            if (leafs.Length == 0)
                continue
            nodes.Push({ type: "step", label: stepLabel, children: leafs })
        }
        return nodes
    }

    ; hops 追加一跳后规格化（深度上限 / 环保护都在 NormalizeHops 里）
    static _HopsPlus(hopsSoFar, hop) {
        out := []
        if (IsObject(hopsSoFar))
            for h in hopsSoFar
                out.Push(h)
        out.Push(hop)
        return UIMacroStepBinding.NormalizeHops(out)
    }
}
