#Requires AutoHotkey v2.0

class MacroGraphFormalMixin {
    _FormalNodeTypes() {
        types := []
        for key in this._FormalIniCmdKeys()
            types.Push(GetLang(key))
        types.Push(GetLang("RMT指令"))
        return types
    }

    _IsFormalNodeType(typeStr) {
        for t in this._FormalNodeTypes() {
            if (t == typeStr)
                return true
        }
        return false
    }

    _FormalIniData(id) {
        if (!this.cmdNodes.Has(id))
            return ""
        arr := SplitCommand(this.cmdNodes[id].CurCMD)
        serial := arr.Length >= 1 ? arr[1] : this.cmdNodes[id].CurCMD
        try {
            data := GetMacroCMDData(serial)
            return IsObject(data) ? data : ""
        }
        return ""
    }

    _FormalEditorMap() {
        return Map(
            GetLang("宏操作"), this.SubMacroGui,
            GetLang("变量"), this.VariableGui,
            GetLang("变量提取"), this.ExVariableGui,
            GetLang("运算"), this.OperationGui,
            GetLang("运行"), this.RunGui,
            GetLang("文件读写"), this.FileIOGui,
            GetLang("文本处理"), this.TextOpsGui,
            GetLang("数组"), this.ArrayGui,
            GetLang("RMT指令"), this.RMTCMDGui,
            GetLang("后台鼠标"), this.BGMouseGui,
            GetLang("后台按键"), this.BGKeyGui,
            GetLang("窗口管理"), this.WindowManageGui,
            GetLang("按键检测"), this.KeyCheckGui,
            GetLang("抓图"), this.ScreenShotGui,
            GetLang("注释"), this.CommentGui,
            GetLang("循环"), this.LoopGui,
            GetLang("如果"), this.CompareGui,
            GetLang("如果Pro"), this.CompareProGui
        )
    }

    _RmtOpList() {
        return GetLangArr(["截图", "截图提取文本", "自由贴", "启用鼠标", "启用键盘", "启用键鼠",
            "禁用鼠标", "禁用键盘", "禁用键鼠", "显示菜单", "关闭菜单",
            "暂停所有宏", "恢复所有宏", "终止所有宏", "开启变量监视", "关闭变量监视", "开启指令显示",
            "关闭指令显示", "关闭软件", "休眠", "重载"])
    }

    _RmtOpIndex(opText) {
        ops := this._RmtOpList()
        loop ops.Length {
            if (ops[A_Index] == opText)
                return A_Index - 1
        }
        return 0
    }

    _FormalNodeWidth(type) {
        ; 变量提取参数较多：与搜索Pro同宽(380)，内部两列布局
        if (type == GetLang("变量提取"))
            return 380
        ; 如果Pro：标准 Formal 下拉(80/96) + 情况分区，略宽于普通 Formal 节点
        if (type == GetLang("如果Pro"))
            return 240
        return 200
    }

    _FormalLW() {
        return "80"
    }

    _FormalCW() {
        return "96"
    }

    ; 检查数组是否包含指定值
    _ArrayContains(arr, val) {
        for item in arr {
            if (item == val)
                return true
        }
        return false
    }

    _FormalContentW() {
        return "188"
    }

    _FormalVarSlotOn(v) {
        return v == 1 || v == "1" || v == true || v == "True"
    }

    _FormalVarOpTypes() {
        return GetLangArr(["数值", "随机数值", "字符", "系统", "删除"])
    }

    _FormalMacroIndexItems(macroType) {
        items := []
        mt := GetLangKey(macroType)
        if (mt == "当前宏")
            return items
        tableIndex := GetTableIndex(mt)
        if (tableIndex == 0)
            return items
        try {
            for index, remark in MySoftData.TableInfo[tableIndex].RemarkArr
                items.Push(index ". " remark)
        }
        return items
    }

    _FormalMenuIndexItems() {
        items := []
        try {
            foldInfo := MySoftData.TableInfo[3].FoldInfo
            loop foldInfo.RemarkArr.Length
                items.Push(A_Index ". " foldInfo.RemarkArr[A_Index])
        }
        return items
    }

    _FormalFileIOOperModes(operType) {
        m := Map(
            GetLang("读取Excel"), GetLangArr(["单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"]),
            GetLang("写入Excel"), GetLangArr(["单元格", "行号自增", "列号自增", "指定区域-行", "指定区域-列"]),
            GetLang("读取文本文件"), GetLangArr(["读取全部内容", "逐行读取", "指定行"]),
            GetLang("写入文本文件"), GetLangArr(["覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"])
        )
        ot := GetLang(operType)
        return m.Has(ot) ? m[ot] : GetLangArr(["单元格"])
    }

    _FormalTextOpsArgsTypes(typeName) {
        m := Map(
            "文本分割", GetLangArr(["内容分割", "定长分割", "正则匹配"]),
            "文本提取", GetLangArr(["数字提取", "字母提取", "中文提取", "正则匹配"]),
            "文本替换", GetLangArr(["普通文本", "正则匹配"]),
            "去除空格", GetLangArr(["去除前空白字符", "去除后空白字符", "去除前后空白字符", "去除所有空白字符"]),
            "大小写转换", GetLangArr(["全部大写", "全部小写", "首字母大写"]),
            "文本统计", GetLangArr(["字符数", "单词数", "行数"]),
            "文本拼接", GetLangArr(["拼接文本"])
        )
        ; typeName 已经是中文，直接用 Map 的 key 匹配
        return m.Has(typeName) ? m[typeName] : []
    }

    ; 类型顺序需与 TextOpsGui.ahk 保持一致
    _FormalTextOpsTypeNames() {
        return GetLangArr(["文本分割", "文本提取", "文本替换", "去除空格", "大小写转换", "文本统计", "文本拼接"])
    }

    _FormalTextOpsTypeIdx(typeName) {
        idx := this._IndexInLangArr(this._FormalTextOpsTypeNames(), typeName)
        return idx >= 0 ? idx + 1 : 1
    }

    ; 是否显示「参数值」行（与 TextOpsGui 一致：文本提取仅正则匹配时显示）
    _FormalTextOpsShowArgsName(tt, at) {
        return tt == "文本分割" || tt == "文本拼接" || (tt == "文本提取" && at == "正则匹配")
    }

    ; 每种处理类型预置独立参数类型下拉，切换类型时只改显隐，避免 ClearItems 闪烁
    _AddTextOpsArgsTypeRow(body, id, tt, at, visible, lw, cw) {
        row := body.Add("StackPanel").Name("TxtArgsTypeRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        if (!visible)
            row.Visibility("Collapsed")
        row.Add("TextBlock").Text(GetLang("参数类型：")).Foreground("{DynamicResource TextMain}").FontSize(this._MGFontSize(12)).Width(lw).VerticalAlignment("Center")
        slot := row.Add("StackPanel").Name("TxtArgsTypeSlot_" id)
        activeTi := this._FormalTextOpsTypeIdx(tt)
        for tidx, tn in this._FormalTextOpsTypeNames() {
            items := this._FormalTextOpsArgsTypes(tn)
            sel := (tidx == activeTi) ? this._IndexInLangArr(items, at) : 0
            if (sel < 0)
                sel := 0
            cmb := slot.Add("ComboBox").Name("TxtArgsTypeCmb_" tidx "_" id).Width(cw).Height("22").MinHeight("0").FontSize(this._MGFontSize(12)).Padding("4,0,22,0").MaxDropDownHeight("200")
                .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            cmb.Visibility(tidx == activeTi ? "Visible" : "Collapsed")
            for it in items
                cmb.Add("ComboBoxItem").Content(it)
            cmb.SelectedIndex(sel)
        }
        return row
    }

    ; 注意：控件命名统一为 "<prefix>_<id>"，故此处必须用 name "_" id（缺下划线会绑定到不存在的控件，导致内联事件永不触发）。
    ; SelectionChanged 偶发 state 文本为空；DropDownClosed 补一次，配合 handler 内 SelectedIndex 优先读值。
    _FormalTrackCombo(id, name, handler, runtime) {
        this._TrackCtrl(name "_" id, runtime)
        this._BindCtrl(name "_" id, "SelectionChanged", handler, runtime)
        this._BindCtrl(name "_" id, "DropDownClosed", handler, runtime)
    }

    _FormalTrackField(id, name, handler, runtime) {
        this._TrackCtrl(name "_" id, runtime)
        this._BindCtrl(name "_" id, "LostFocus", handler, runtime)
    }

    _FormalTrackEditCombo(id, name, handler, runtime) {
        this._TrackCtrl(name "_" id, runtime)
        this._BindCtrl(name "_" id, "LostFocus", handler, runtime)
        this._BindCtrl(name "_" id, "SelectionChanged", handler, runtime)
        ; 可编辑 ComboBox 从下拉里选变量时，SelectionChanged 偶发不提交（编辑态文本滞后），
        ; 补绑 DropDownClosed：下拉关闭时 SelectedItem/Text 已确定，确保选择能落库（否则只能手输）。
        this._BindCtrl(name "_" id, "DropDownClosed", handler, runtime)
    }

    _FormalTrackCheck(id, name, handler, runtime) {
        this._TrackCtrl(name "_" id, runtime)
        this._BindCtrl(name "_" id, "Click", handler, runtime)
    }

    _FormalInitArrText(initArr) {
        if (!IsObject(initArr) || initArr.Length == 0)
            return "1,2,3,4,5"
        result := ""
        for index, v in initArr {
            if (index > 1)
                result .= ","
            result .= String(v)
        }
        return result
    }

    _FillFormalNodeBody(id, d, body) {
        if (d.type == GetLang("宏操作"))
            this._FillSubMacroBody(id, d, body)
        else if (d.type == GetLang("变量"))
            this._FillVariableBody(id, d, body)
        else if (d.type == GetLang("变量提取"))
            this._FillExVariableBody(id, d, body)
        else if (d.type == GetLang("运算"))
            this._FillOperationBody(id, d, body)
        else if (d.type == GetLang("运行"))
            this._FillRunBody(id, d, body)
        else if (d.type == GetLang("文件读写"))
            this._FillFileIOBody(id, d, body)
        else if (d.type == GetLang("文本处理"))
            this._FillTextOpsBody(id, d, body)
        else if (d.type == GetLang("数组"))
            this._FillArrayBody(id, d, body)
        else if (d.type == GetLang("RMT指令"))
            this._FillRmtBody(id, d, body)
        else if (d.type == GetLang("后台鼠标"))
            this._FillBGMouseBody(id, d, body)
        else if (d.type == GetLang("后台按键"))
            this._FillBGKeyBody(id, d, body)
        else if (d.type == GetLang("窗口管理"))
            this._FillWindowManageBody(id, d, body)
        else if (d.type == GetLang("按键检测"))
            this._FillKeyCheckBody(id, d, body)
        else if (d.type == GetLang("抓图"))
            this._FillScreenShotBody(id, d, body)
        else if (d.type == GetLang("注释"))
            this._FillCommentBody(id, d, body)
        else if (d.type == GetLang("循环"))
            this._FillLoopBody(id, d, body)
        else if (d.type == GetLang("如果"))
            this._FillIfBody(id, d, body)
        else if (d.type == GetLang("如果Pro"))
            this._FillIfProBody(id, d, body)
    }

    ; 配置行高度（标签行 Margin5 + 控件高22）；注释正文 2~5 行配置高度
    _FormalConfigRowH() {
        return 27
    }

    ; 按文本估算注释框高度（介于 2~5 行配置高度）
    _CommentTextHeight(text) {
        rowH := this._FormalConfigRowH()
        minH := rowH * 2
        maxH := rowH * 5
        lineH := 18
        pad := 8
        lines := 0
        for part in StrSplit(text, "`n") {
            chars := StrLen(part)
            ; 宽约 188、字号 12：约 16 字换行
            lines += Max(1, Integer((chars + 15) / 16))
        }
        if (lines < 1)
            lines := 1
        return Min(maxH, Max(minH, lines * lineH + pad))
    }

    ; 注释正文宽度：节点宽 200，body 左右各 10 → 可用 180；再减 2 避免右边框被裁切
    _CommentContentW() {
        return "178"
    }

    ; 注释节点：标题仅「注释」；正文显示注释内容（即备注），高度 2~5 行配置，超出滚动
    _FillCommentBody(id, d, body) {
        content := d.HasOwnProp("commentContent") ? d.commentContent : GetLang("请输入注释内容")
        h := this._CommentTextHeight(content)
        maxH := this._FormalConfigRowH() * 5
        block := body.Add("StackPanel").Name("CommentBlock_" id).Margin("0,5,0,0")
        tb := block.Add("TextBox").Name("CommentText_" id).Text(content)
            .Width(this._CommentContentW()).Height(String(h)).MinHeight(String(this._FormalConfigRowH() * 2))
            .MaxHeight(String(maxH)).FontSize(this._MGFontSize(12)).Padding("4,4").Margin("0,0,0,0")
            .HorizontalAlignment("Left")
            .Foreground("{DynamicResource InputText}").CaretBrush("{DynamicResource InputText}")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        tb.SetProp("TextWrapping", "Wrap")
        tb.SetProp("AcceptsReturn", "True")
        tb.SetProp("VerticalScrollBarVisibility", "Auto")
        tb.SetProp("VerticalContentAlignment", "Top")
        tb.SetProp("HorizontalContentAlignment", "Left")
        tb.SetProp("TextAlignment", "Left")
        ; 禁用裁剪，避免右边框/滚动条被父级裁掉
        tb.SetProp("ClipToBounds", "False")
        block.SetProp("ClipToBounds", "False")
    }

    _FillSubMacroBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"])
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        mt := d.HasOwnProp("macroType") ? d.macroType : "按键宏"
        ct := d.HasOwnProp("callType") ? d.callType : "触发"
        idx := d.HasOwnProp("index") ? d.index : 1
        ins := d.HasOwnProp("insertCount") ? d.insertCount : "1"
        idxItems := this._FormalMacroIndexItems(mt)
        showIdx := (GetLangKey(mt) != "当前宏") && idxItems.Length > 0
        showIns := this._FormalSubCallIsInsert(id, ct)
        this._AddComboRow(body, "SubTypeRow_" id, GetLang("宏类型："), "SubTypeCmb_" id, macroTypes, this._IndexInLangArr(macroTypes, GetLang(mt)), true, true, lw, cw)
        this._AddComboRow(body, "SubCallRow_" id, GetLang("操作类型："), "SubCallCmb_" id, callTypes, this._IndexInLangArr(callTypes, GetLang(ct)), true, true, lw, cw)
        ; 插入次数置于宏序号上方（出现时紧跟操作类型）
        this._AddEditableComboRow(body, "SubInsRow_" id, GetLang("插入次数："), "SubIns_" id, GetGuiVarArr(), ins, showIns, lw, cw)
        this._AddComboRow(body, "SubIdxRow_" id, GetLang("宏序号："), "SubIdxCmb_" id, idxItems, Max(0, idx - 1), showIdx, showIdx, lw, cw)
    }

    ; 变量槽（对齐「变量编辑器」：开关 + 变量名 + 变量类型 + 选择/输入 / 最小 / 最大）。
    ; 变量类型：1数值 2随机数值 3字符 4系统 5删除。
    ;   - 数值/字符：显示「选择/输入」行（CopyRow）
    ;   - 系统：显示系统变量下拉（SysRow）
    ;   - 随机数值：显示「最小/最大」两行
    ;   - 删除：仅变量名
    _FillVariableSlot(body, id, slot, d, visible := true) {
        ; 与间隔节点一致：标准 Formal 宽(80/96)；用分隔线代替组框
        lw := this._FormalLW(), cw := this._FormalCW()
        p := "VarS" slot
        toggled := d.HasOwnProp("toggle" slot) ? d["toggle" slot] : (slot == 1 ? 1 : 0)
        on := this._FormalVarSlotOn(toggled)
        ot := d.HasOwnProp("operaType" slot) ? d["operaType" slot] : 1
        vn := d.HasOwnProp("variable" slot) ? d["variable" slot] : "Var" slot
        cv := d.HasOwnProp("copyVar" slot) ? d["copyVar" slot] : "0"
        minv := d.HasOwnProp("minVar" slot) ? d["minVar" slot] : "0"
        maxv := d.HasOwnProp("maxVar" slot) ? d["maxVar" slot] : "10"
        opTypes := this._FormalVarOpTypes()
        showNum := on && ot == 1
        showChar := on && ot == 3
        showSys := on && ot == 4
        showMinMax := on && ot == 2
        ; 逐级展开：仅勾选上一变量后才显示本槽；分割线分隔，不挤占左右区域
        block := body.Add("StackPanel").Name(p "Card_" id).Margin("0,2,0,0")
        if (!visible)
            block.Visibility("Collapsed")
        block.Add("Border").Height("1").Margin("0,6,0,4").BorderThickness("0").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        this._AddCheckRow(block, p "TogRow_" id, p "Tog_" id, GetLang("变量") slot, on, true)
        this._AddEditableComboRow(block, p "NameRow_" id, GetLang("变量名："), p "Name_" id, GetGuiVarArr(), vn, on, lw, cw)
        this._AddComboRow(block, p "OpRow_" id, GetLang("类型："), p "OpCmb_" id, opTypes, ot - 1, on, true, lw, cw)
        ; 数值：可下拉选变量或手输数字；字符：纯文本输入框（无下拉）。两行各自固定标签、按类型显隐切换。
        this._AddEditableComboRow(block, p "CopyRow_" id, GetLang("数值："), p "Copy_" id, GetGuiVarArr(), cv, showNum, lw, cw)
        this._AddFieldRow(block, p "CharRow_" id, GetLang("字符："), p "CopyTxt_" id, cv, showChar, true, "", "", "", lw, cw)
        sysItems := GetSystemVarArr()
        sysIdx := this._IndexInLangArr(sysItems, GetLang(cv))
        this._AddComboRow(block, p "SysRow_" id, GetLang("系统："), p "SysCmb_" id, sysItems, sysIdx, showSys, true, lw, cw)
        this._AddEditableComboRow(block, p "MinRow_" id, GetLang("最小值："), p "Min_" id, GetGuiVarArr(), minv, showMinMax, lw, cw)
        this._AddEditableComboRow(block, p "MaxRow_" id, GetLang("最大值："), p "Max_" id, GetGuiVarArr(), maxv, showMinMax, lw, cw)
    }

    _FillVariableBody(id, d, body) {
        ; 同时构建「摘要」与「完整」两套容器，靠显隐切换，避免折叠时整窗重建导致闪烁
        folded := this._NodeFolded(id)
        ; 「如果变量存在则不改变数值」选项：折叠/展开都显示，可随时切换
        ign := d.HasOwnProp("isIgnoreExist") ? d.isIgnoreExist : 0
        this._AddCheckRow(body, "VarIgnRow_" id, "VarIgn_" id, GetLang("如果变量存在则不改变数值"), ign == 1 || ign == "1", true)

        sumBox := body.Add("StackPanel").Name("VarSumBox_" id)
        if (!folded)
            sumBox.Visibility("Collapsed")
        this._FillVariableSummary(id, d, sumBox)

        fullBox := body.Add("StackPanel").Name("VarFullBox_" id)
        if (folded)
            fullBox.Visibility("Collapsed")
        prevOn := true
        loop 4 {
            slot := A_Index
            vis := (slot == 1) ? true : prevOn
            this._FillVariableSlot(fullBox, id, slot, d, vis)
            toggled := d.HasOwnProp("toggle" slot) ? d["toggle" slot] : (slot == 1 ? 1 : 0)
            prevOn := vis && this._FormalVarSlotOn(toggled)
        }
    }

    ; 收起态摘要：4 个固定命名行（按启用与否显隐），逐个显示「变量名 = 值/描述」（颜色跟主题）
    _FillVariableSummary(id, d, box) {
        anyOn := false
        fg := "{DynamicResource TextMain}"
        loop 4 {
            slot := A_Index
            info := this._VarSummaryRowInfo(d, slot)
            if (info.on)
                anyOn := true
            row := box.Add("StackPanel").Name("VarSumRow_" slot "_" id).Orientation("Horizontal").Margin("0,5,0,0")
            if (!info.on)
                row.Visibility("Collapsed")
            row.Add("Ellipse").Width("7").Height("7").Fill("{DynamicResource GraphConnSel}").Margin("0,0,6,0").VerticalAlignment("Center")
            row.Add("TextBlock").Name("VarSumTxt_" slot "_" id).Text(info.text).Foreground(fg).FontSize(this._MGFontSize(12)).VerticalAlignment("Center").TextTrimming("CharacterEllipsis")
        }
        emptyTb := box.Add("TextBlock").Name("VarSumEmpty_" id).Text(GetLang("未启用任何变量")).Foreground(fg).FontSize(this._MGFontSize(11)).Margin("0,5,0,0")
        if (anyOn)
            emptyTb.Visibility("Collapsed")
    }

    ; 单个变量的摘要信息（开关 + 「变量名 = 值/描述」文本）
    _VarSummaryRowInfo(d, slot) {
        toggled := d.HasOwnProp("toggle" slot) ? d["toggle" slot] : (slot == 1 ? 1 : 0)
        on := this._FormalVarSlotOn(toggled)
        ot := d.HasOwnProp("operaType" slot) ? d["operaType" slot] : 1
        vn := d.HasOwnProp("variable" slot) ? d["variable" slot] : "Var" slot
        cv := d.HasOwnProp("copyVar" slot) ? d["copyVar" slot] : "0"
        minv := d.HasOwnProp("minVar" slot) ? d["minVar" slot] : "0"
        maxv := d.HasOwnProp("maxVar" slot) ? d["maxVar" slot] : "10"
        return { on: on, text: vn " = " this._VarSlotSummaryValue(ot, cv, minv, maxv) }
    }

    ; 变量摘要值描述：1数值 2随机 3字符 4系统 5删除
    _VarSlotSummaryValue(ot, cv, minv, maxv) {
        if (ot == 2)
            return GetLang("随机") "[" minv "~" maxv "]"
        if (ot == 3)
            return '"' cv '"'
        if (ot == 4)
            return GetLang("系统") "：" GetLang(cv)
        if (ot == 5)
            return GetLang("删除")
        return cv
    }

    ; 变量提取节点（380 宽，双列布局）：提取类型/忽略、模板(带编辑按钮)、窗口信息、
    ; OCR类型/次数、起止坐标、间隔，最后 6 个提取变量两两并排。
    _FillExVariableBody(id, d, body) {
        LW := "70", CW := "96"   ; 与搜索Pro一致：两列(标签70+控件96)并排恰好放进 380 宽节点
        varList := GetGuiVarArr()
        extTypes := GetLangArr(["屏幕", "剪切板", "窗口"])
        ocrTypes := GetLangArr(["中文", "英文"])
        et := d.HasOwnProp("extractType") ? d.extractType : 1
        es := d.HasOwnProp("extractStr") ? d.extractStr : ""
        wi := d.HasOwnProp("winInfo") ? d.winInfo : ""
        ocr := d.HasOwnProp("ocrType") ? d.ocrType : 1
        isOcr := et == 1 || et == 3
        isWin := et == 3
        ign := d.HasOwnProp("isIgnoreExist") ? d.isIgnoreExist : 0

        ; 提取类型 | 忽略已存在
        r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
        this._ProCellCombo(r, "ExTypeRow_" id, GetLang("提取类型："), "ExTypeCmb_" id, extTypes, et - 1, true, LW, CW, false)
        this._ProCellCheck(r, "ExIgnRow_" id, "ExIgn_" id, GetLang("忽略已存在"), ign == 1 || ign == "1", true, true)

        ; 模板（屏幕/剪切板/窗口 都需要），含「编辑」按钮打开提取模板编辑器
        exStrRow := body.Add("StackPanel").Name("ExStrRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        exStrRow.Add("TextBlock").Text(GetLang("模板：")).Foreground("{DynamicResource TextMain}").FontSize(this._MGFontSize(12)).Width(LW).VerticalAlignment("Center")
        this._MakeTextBox(exStrRow, "ExStr_" id, es, "188")
        exStrRow.Add("Button").Name("ExStrEdit_" id).Content(GetLang("编辑")).FontSize(this._MGFontSize(11)).Height("20").Margin("4,0,0,0").Padding("8,0").Cursor("Hand")

        ; 窗口信息（窗口类型才显示）
        this._AddFieldRow(body, "ExWinRow_" id, GetLang("窗口信息："), "ExWin_" id, wi, isWin, true, "", "", "", LW, "226")

        ; OCR类型（单独一行）
        r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
        this._ProCellCombo(r, "ExOcrRow_" id, GetLang("OCR类型："), "ExOcrCmb_" id, ocrTypes, ocr - 1, isOcr, LW, CW, false)

        ; 起始X | 起始Y
        r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
        this._ProCellEdit(r, "ExSXRow_" id, GetLang("起始X："), "ExSX_" id, varList, "" (d.HasOwnProp("startPosX") ? d.startPosX : 0), isOcr, LW, CW, false)
        this._ProCellEdit(r, "ExSYRow_" id, GetLang("起始Y："), "ExSY_" id, varList, "" (d.HasOwnProp("startPosY") ? d.startPosY : 0), isOcr, LW, CW, true)

        ; 终止X | 终止Y
        r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
        this._ProCellEdit(r, "ExEXRow_" id, GetLang("终止X："), "ExEX_" id, varList, "" (d.HasOwnProp("endPosX") ? d.endPosX : A_ScreenWidth), isOcr, LW, CW, false)
        this._ProCellEdit(r, "ExEYRow_" id, GetLang("终止Y："), "ExEY_" id, varList, "" (d.HasOwnProp("endPosY") ? d.endPosY : A_ScreenHeight), isOcr, LW, CW, true)

        ; 次数 | 间隔（次数在前）
        sc := d.HasOwnProp("searchCount") ? d.searchCount : 1
        scText := (sc == -1 || sc == "-1" || sc == GetLang("无限")) ? GetLang("无限") : String(sc)
        r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
        this._ProCellEdit(r, "ExCntRow_" id, GetLang("次数："), "ExCnt_" id, [GetLang("无限")], scText, isOcr, LW, CW, false)
        this._ProCellField(r, "ExIntRow_" id, GetLang("间隔："), "ExInt_" id, d.HasOwnProp("searchInterval") ? d.searchInterval : 1000, isOcr, "", LW, CW, true)

        ; 提取变量：6 个，复选框+名称为一格，两格一行（左列对齐次数、右列对齐间隔）
        loop 3 {
            r := body.Add("StackPanel").Orientation("Horizontal").Margin("0,5,0,0")
            this._FillExVarSlotCell(r, id, A_Index * 2 - 1, d, varList, false)
            this._FillExVarSlotCell(r, id, A_Index * 2, d, varList, true)
        }
    }

    _FillOperationSlot(body, id, slot, d, visible := true) {
        lw := this._FormalLW(), cw := this._FormalCW()
        p := "OpS" slot
        toggled := d.HasOwnProp("opToggle" slot) ? d["opToggle" slot] : (slot == 1 ? 1 : 0)
        on := toggled == 1 || toggled == "1"
        un := d.HasOwnProp("updateName" slot) ? d["updateName" slot] : "Var" slot
        ex := d.HasOwnProp("expression" slot) ? d["expression" slot] : ""
        ; 逐级展开：仅勾选上一个运算后才显示下一个（visible 控制整组行显隐，降低展开高度）
        this._AddCheckRow(body, p "TogRow_" id, p "Tog_" id, GetLang("运算") slot, on, visible)
        ; 表达式行：文本框 + 编辑按钮（输入框宽度140px）
        ; 注意：表达式中可能包含 { } 变量语法，需要 XAML 转义
        exprRow := body.Add("StackPanel").Name(p "ExprRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        if (!(visible && on))
            exprRow.Visibility("Collapsed")
        exprRow.Add("TextBox").Name(p "Expr_" id).Text(ex).Width("140").Height("20").MinHeight("0").FontSize("11").Padding("4,0").VerticalContentAlignment("Center").TextAlignment("Center").CaretBrush("{DynamicResource InputText}")
        editBtn := exprRow.Add("Button").Name(p "ExprEdit_" id).Content(GetLang("编辑")).Width("32").Height("20").FontSize(this._MGFontSize(10)).Padding("0").Margin("4,0,0,0").VerticalAlignment("Center").Cursor("Hand").Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").BorderThickness("1").BorderBrush("{DynamicResource ActionStroke}")
        this._ApplyActionBtnStyle(editBtn)
        ; 结果变量下拉
        this._AddEditableComboRow(body, p "TargetRow_" id, GetLang("结果变量："), p "Target_" id, GetGuiVarArr(), un, visible && on, lw, cw)
    }

    ; 运算表达式编辑按钮：打开表达式编辑器，确定后回写表达式
    _OnOperationExprEdit(id, slot, *) {
        ; 先从 UI 输入框获取当前表达式（这是最新的值）
        ex := ""
        if (this.ui != "") {
            try {
                ex := this.ui.Get("OpS" slot "Expr_" id, "Text")
            }
        }
        ; 如果 UI 没有，尝试从数据对象获取
        if (ex == "") {
            data := this._FormalIniData(id)
            if (data != "") {
                ; 优先从 ExpressionArr 数组获取（Data 类实例）
                if (data.HasOwnProp("ExpressionArr") && data.ExpressionArr.Length >= slot) {
                    ex := data.ExpressionArr[slot]
                }
                ; 其次从 expression1/expression2... 获取（动态对象）
                else if (data.HasOwnProp("expression" slot)) {
                    ex := data["expression" slot]
                }
            }
        }
        ; 确保 OperationSubGui 已初始化并创建 GUI
        opGui := this.OperationGui
        if (opGui.OperationSubGui == "") {
            opGui.OperationSubGui := OperationSubGui()
        }
        exGui := opGui.OperationSubGui
        exGui.ParentTile := ""
        exGui.OwnerHwnd := ""
        ; 确保 GUI 已创建
        if (exGui.Gui == "") {
            exGui.AddGui()
        }
        ; OperationSubGui.OnClickSureBtn 调用 action(this.Index, expression)
        exGui.SureBtnAction := (idx, expr) => this._OnOperationExprEditSure(id, slot, idx, expr)
        ; 显示编辑器
        exGui.ShowGui(slot, ex)
    }

    ; 表达式编辑器确定回调
    _OnOperationExprEditSure(id, slot, idx, expr, *) {
        ; 直接更新输入框文本
        if (this.ui != "") {
            this.ui.Update("OpS" slot "Expr_" id, "Text", expr)
        }
        ; 同时保存数据
        data := this._FormalIniData(id)
        if (data != "") {
            data.ExpressionArr[slot] := expr
            SaveMacroCMDData(data)
        }
        ; 折叠态刷新摘要
        if (this._NodeFolded(id))
            this._RefreshOperationSummary(id)
        this._Apply()
    }

    _FillOperationBody(id, d, body) {
        ; 同时构建「摘要」与「完整」两套容器，靠显隐切换，避免折叠时整窗重建导致闪烁
        folded := this._NodeFolded(id)

        sumBox := body.Add("StackPanel").Name("OpSumBox_" id)
        if (!folded)
            sumBox.Visibility("Collapsed")
        this._FillOperationSummary(id, d, sumBox)

        fullBox := body.Add("StackPanel").Name("OpFullBox_" id)
        if (folded)
            fullBox.Visibility("Collapsed")
        prevOn := true
        loop 4 {
            slot := A_Index
            vis := (slot == 1) ? true : prevOn
            this._FillOperationSlot(fullBox, id, slot, d, vis)
            toggled := d.HasOwnProp("opToggle" slot) ? d["opToggle" slot] : (slot == 1 ? 1 : 0)
            prevOn := vis && (toggled == 1 || toggled == "1")
        }
    }

    ; 收起态摘要：4 个固定命名行（按启用与否显隐），逐个显示「目标 = 表达式」（颜色跟主题）
    _FillOperationSummary(id, d, box) {
        anyOn := false
        fg := "{DynamicResource TextMain}"
        loop 4 {
            slot := A_Index
            info := this._OpSummaryRowInfo(d, slot)
            if (info.on)
                anyOn := true
            row := box.Add("StackPanel").Name("OpSumRow_" slot "_" id).Orientation("Horizontal").Margin("0,5,0,0")
            if (!info.on)
                row.Visibility("Collapsed")
            row.Add("Ellipse").Width("7").Height("7").Fill("{DynamicResource GraphConnSel}").Margin("0,0,6,0").VerticalAlignment("Center")
            row.Add("TextBlock").Name("OpSumTxt_" slot "_" id).Text(info.text).Foreground(fg).FontSize(this._MGFontSize(12)).VerticalAlignment("Center").TextTrimming("CharacterEllipsis")
        }
        emptyTb := box.Add("TextBlock").Name("OpSumEmpty_" id).Text(GetLang("未启用任何运算")).Foreground(fg).FontSize(this._MGFontSize(11)).Margin("0,5,0,0")
        if (anyOn)
            emptyTb.Visibility("Collapsed")
    }

    ; 单个运算槽的摘要信息
    _OpSummaryRowInfo(d, slot) {
        toggled := d.HasOwnProp("opToggle" slot) ? d["opToggle" slot] : (slot == 1 ? 1 : 0)
        on := toggled == 1 || toggled == "1" || toggled == true || toggled == "True"
        un := d.HasOwnProp("updateName" slot) ? d["updateName" slot] : "Var" slot
        ex := d.HasOwnProp("expression" slot) ? d["expression" slot] : ""
        return { on: on, text: un " = " (ex != "" ? ex : "...") }
    }

    ; 就地刷新运算节点摘要（收起态显示）
    _RefreshOperationSummary(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        anyOn := false
        loop 4 {
            slot := A_Index
            info := this._OpSummaryRowInfo(d, slot)
            if (info.on)
                anyOn := true
            this.ui.Update("OpSumRow_" slot "_" id, "Visibility", info.on ? "Visible" : "Collapsed")
            this.ui.Update("OpSumTxt_" slot "_" id, "Text", info.text)
        }
        this.ui.Update("OpSumEmpty_" id, "Visibility", anyOn ? "Collapsed" : "Visible")
    }

    ; 与运行编辑器一致：1不等待 2等待+返回值 3不等待+输入 4等待+输入输出
    _FormalRunModeArr() {
        return GetLangArr(["不等待", "等待+返回值", "不等待+输入", "等待+输入输出"])
    }

    _FillRunBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        modes := this._FormalRunModeArr()
        saveLabels := [GetLang("返回值"), GetLang("输出"), GetLang("错误")]
        rm := d.HasOwnProp("runMode") ? d.runMode : 1
        if (rm == "" || !IsNumber(rm))
            rm := 1
        rm := Integer(rm)
        if (rm < 1 || rm > 4)
            rm := 1
        rp := d.HasOwnProp("runTarget") ? d.runTarget : ""
        optionVal := d.HasOwnProp("option") ? d.option : 1
        if (optionVal == "" || !IsNumber(optionVal))
            optionVal := 1
        optionVal := Integer(optionVal)
        stdinVal := d.HasOwnProp("stdin") ? d.stdin : ""
        ; 显隐：与 RunGui.OnModeChange 对齐
        showStdIn := (rm == 3 || rm == 4)
        showEncIn := showStdIn
        showEncOut := (rm == 4)
        showSave1 := (rm == 2 || rm == 4)
        showSave23 := (rm == 4)
        ; 路径行：输入框 + 文件按钮（无标签，输入框宽度+30px）
        RunTargetRow := body.Add("StackPanel").Name("RunTargetRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        RunTargetRow.Add("TextBox").Name("RunTarget_" id).Text(rp).Width(cw + 25).Height("22").MinHeight("0").FontSize("12").Padding("4,0").VerticalContentAlignment("Center")
        this._ApplyActionBtnStyle(RunTargetRow.Add("Button").Name("RunTargetBrowse_" id).Content(GetLang("文件")).Width("50").Height("22").FontSize(this._MGFontSize(10)).Padding("0").Margin("4,0,0,0").VerticalAlignment("Center").Cursor("Hand").Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").BorderThickness("1").BorderBrush("{DynamicResource ActionStroke}"))
        this._AddComboRow(body, "RunModeRow_" id, GetLang("模式："), "RunModeCmb_" id, modes, rm - 1, true, true, lw, cw)

        options := GetLangArr(["后台", "默认", "最小化", "最大化"])
        this._AddComboRow(body, "RunHideRow_" id, GetLang("窗口："), "RunOptionCmb_" id, options, optionVal, true, true, lw, cw)

        encArr := GetLangArr(["UTF-8", "UTF-16", "CP0"])
        encInVal  := d.HasOwnProp("encIn")  ? d.encIn  : "UTF-8"
        encOutVal := d.HasOwnProp("encOut") ? d.encOut : "UTF-8"
        encErrVal := d.HasOwnProp("encErr") ? d.encErr : "UTF-8"
        this._AddComboRow(body, "RunEncInRow_" id,  GetLang("输入编码："), "RunEncInCmb_"  id, encArr, this._IndexInLangArr(encArr, encInVal),  showEncIn, true, lw, cw)
        this._AddComboRow(body, "RunEncOutRow_" id, GetLang("输出编码："), "RunEncOutCmb_" id, encArr, this._IndexInLangArr(encArr, encOutVal), showEncOut, true, lw, cw)
        this._AddComboRow(body, "RunEncErrRow_" id, GetLang("错误编码："), "RunEncErrCmb_" id, encArr, this._IndexInLangArr(encArr, encErrVal), showEncOut, true, lw, cw)

        stdinRow := body.Add("StackPanel").Name("RunStdInRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        if (!showStdIn)
            stdinRow.Visibility("Collapsed")
        stdinRow.Add("Label").Content(GetLang("输入：")).Width(lw).Height("22").FontSize("11").Foreground("{DynamicResource InputText}").VerticalContentAlignment("Center").Padding("0")
        stdinRow.Add("TextBox").Name("RunStdIn_" id).Text(stdinVal).Width(cw).Height("22").MinHeight("0").FontSize("11").Padding("4,0").VerticalContentAlignment("Center")

        loop 3 {
            i := A_Index
            sn := d.HasOwnProp("runSave" i) ? d["runSave" i] : (i == 1 ? "ExitCode" : (i == 2 ? "StdOut" : "StdErr"))
            showSave := (i == 1) ? showSave1 : showSave23
            this._AddEditableComboRow(body, "RunSave" i "Row_" id, saveLabels[i] "：", "RunSave" i "_" id, GetGuiVarArr(), sn, showSave, lw, cw)
        }
    }

    ; 选择文件按钮：打开文件选择对话框，选择后填入路径输入框
    _OnRunTargetBrowse(id, *) {
        try {
            ; 尝试获取当前路径作为初始目录
            curPath := ""
            if (this.ui != "") {
                try {
                    curPath := this.ui.Get("RunTarget_" id, "Text")
                }
            }
            ; 打开文件选择对话框（支持所有文件类型）
            selectedPath := FileSelect(1, curPath, GetLang("选择运行程序"), "All files (*.*)")
            if (selectedPath != "") {
                if (this.ui != "") {
                    this.ui.Update("RunTarget_" id, "Text", selectedPath)
                }
            }
        }
    }

    ; 文件路径选择按钮：打开文件选择对话框
    _OnFIOPathBrowse(id, *) {
        try {
            curPath := ""
            if (this.ui != "") {
                try {
                    curPath := this.ui.Get("FIOPath_" id, "Text")
                }
            }
            ; 根据文件类型显示不同的文件选择对话框
            selectedPath := FileSelect(1, curPath, GetLang("选择文件"), "All files (*.*)")
            if (selectedPath != "") {
                if (this.ui != "") {
                    this.ui.Update("FIOPath_" id, "Text", selectedPath)
                }
            }
        }
    }

    _FillFileIOBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        operTypes := GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"])
        encodings := GetLangArr(["UTF-8", "UTF-16", "GBK", "ANSI"])
        saveTypes := GetLangArr(["变量", "数组"])
        ot := d.HasOwnProp("operType") ? d.operType : "读取Excel"
        om := d.HasOwnProp("operMode") ? d.operMode : "单元格"
        modeItems := this._FormalFileIOOperModes(ot)
        fp := d.HasOwnProp("filePath") ? d.filePath : ""
        enc := d.HasOwnProp("encoding") ? d.encoding : "UTF-8"
        st := d.HasOwnProp("saveType") ? d.saveType : "变量"
        sn := d.HasOwnProp("saveName") ? d.saveName : "Data"
        IsRead := ot == "读取Excel" || ot == "读取文本文件"
        IsWrite := !IsRead
        IsExcel := ot == "读取Excel" || ot == "写入Excel"
        IsText := ot == "读取文本文件" || ot == "写入文本文件"
        IsExcelRange := IsExcel && (om == "指定行" || om == "指定列" || om == "指定区域-行" || om == "指定区域-列")
        HasTextRow := IsText && (om == "指定行" || om == "逐行读取" || om == "行号自增")
        HasRegion := IsRead && (om == "指定区域-行" || om == "指定区域-列")
        HasWriteContent := IsWrite && !IsExcelRange
        HasWriteArr := IsWrite && IsExcelRange
        this._AddComboRow(body, "FIOTypeRow_" id, GetLang("类型："), "FIOTypeCmb_" id, operTypes, this._IndexInLangArr(operTypes, GetLang(ot)), true, true, lw, cw)
        this._AddComboRow(body, "FIOModeRow_" id, GetLang("模式："), "FIOModeCmb_" id, modeItems, this._IndexInLangArr(modeItems, GetLang(om)), true, true, lw, cw)
        ; 路径行：输入框 + 文件按钮（无标签，与运行节点一致）
        fioPathRow := body.Add("StackPanel").Name("FIOPathRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        fioPathRow.Add("TextBox").Name("FIOPath_" id).Text(fp).Width(cw + 25).Height("22").MinHeight("0").FontSize("12").Padding("4,0").VerticalContentAlignment("Center")
        this._ApplyActionBtnStyle(fioPathRow.Add("Button").Name("FIOPathBrowse_" id).Content(GetLang("文件")).Width("50").Height("22").FontSize(this._MGFontSize(10)).Padding("0").Margin("4,0,0,0").VerticalAlignment("Center").Cursor("Hand").Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").BorderThickness("1").BorderBrush("{DynamicResource ActionStroke}"))
        ; 表名/序号（仅Excel时显示，默认值1）
        nameOrSerial := d.HasOwnProp("NameOrSerial") ? d.NameOrSerial : 1
        this._AddFieldRow(body, "FIOSheetRow_" id, GetLang("表名："), "FIOSheet_" id, nameOrSerial, IsExcel, true, "", "", "", lw, cw)
        this._AddComboRow(body, "FIOEncRow_" id, GetLang("编码："), "FIOEncCmb_" id, encodings, this._IndexInLangArr(encodings, GetLang(enc)), IsText, true, lw, cw)
        this._AddEditableComboRow(body, "FIORowRow_" id, GetLang("行号："), "FIORow_" id, GetGuiVarArr(), d.HasOwnProp("rowVar") ? d.rowVar : 1, IsExcel, lw, cw)
        this._AddEditableComboRow(body, "FIOColRow_" id, GetLang("列号："), "FIOCol_" id, GetGuiVarArr(), d.HasOwnProp("colVar") ? d.colVar : 1, IsExcel, lw, cw)
        this._AddEditableComboRow(body, "FIORowEndRow_" id, GetLang("终止行："), "FIORowEnd_" id, GetGuiVarArr(), d.HasOwnProp("rowEndVar") ? d.rowEndVar : 1, HasRegion, lw, cw)
        this._AddEditableComboRow(body, "FIOColEndRow_" id, GetLang("终止列："), "FIOColEnd_" id, GetGuiVarArr(), d.HasOwnProp("colEndVar") ? d.colEndVar : 1, HasRegion, lw, cw)
        this._AddEditableComboRow(body, "FIOTxtRowRow_" id, GetLang("文本行："), "FIOTxtRow_" id, GetGuiVarArr(), d.HasOwnProp("textRowVar") ? d.textRowVar : 1, HasTextRow, lw, cw)
        this._AddMultilineFieldBlock(body, "FIOContentBlock_" id, GetLang("写入内容："), "FIOContent_" id, d.HasOwnProp("content") ? d.content : GetLang("写入的内容"), HasWriteContent, this._FormalContentW())
        this._AddEditableComboRow(body, "FIOArrRow_" id, GetLang("数组名："), "FIOArr_" id, GetGuiArrNameArr(), d.HasOwnProp("arrName") ? d.arrName : "Arr", HasWriteArr, lw, cw)
        ; 保存类型：根据模式和操作类型自动固定（结果保存仅读取时出现，与编辑器一致）
        ; 读取Excel+单元格 → 变量；读取Excel+其他模式 → 数组；读取文本+全部/指定行 → 变量；其他 → 数组
        showSave := IsRead
        IsResOnlyVar := (ot == "读取Excel" && om == "单元格") || (ot == "读取文本文件" && (om == "读取全部内容" || om == "指定行"))
        autoSaveType := IsResOnlyVar ? GetLang("变量") : GetLang("数组")
        this._AddFieldRow(body, "FIOSaveTypeRow_" id, GetLang("保存类型："), "FIOSaveType_" id, autoSaveType, showSave, false)
        ; 保存类型是变量时用变量列表，是数组时用数组列表
        saveNameList := IsResOnlyVar ? GetGuiVarArr() : GetGuiArrNameArr()
        this._AddEditableComboRow(body, "FIOSaveRow_" id, GetLang("保存名："), "FIOSave_" id, saveNameList, sn, showSave, lw, cw)
    }

    _FillTextOpsBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        typeNames := this._FormalTextOpsTypeNames()
        tt := d.HasOwnProp("textOpsType") ? d.textOpsType : "文本分割"
        tn := d.HasOwnProp("textName") ? d.textName : "TextVar"
        at := d.HasOwnProp("argsType") ? d.argsType : ","
        an := d.HasOwnProp("argsName") ? d.argsName : ","
        sr := d.HasOwnProp("search") ? d.search : ""
        rp := d.HasOwnProp("replace") ? d.replace : ""
        sn := d.HasOwnProp("saveName") ? d.saveName : "Data"
        IsReplace := tt == "文本替换"
        IsSplit := tt == "文本分割"
        IsGetEx := tt == "文本提取"
        IsConcat := tt == "文本拼接"
        ShowArgsType := IsSplit || IsGetEx || tt == "大小写转换" || tt == "去除空格" || tt == "文本统计" || IsConcat || IsReplace
        ShowArgsName := this._FormalTextOpsShowArgsName(tt, at)
        fixedSt := (IsSplit || IsGetEx) ? "数组" : "变量"
        this._AddComboRow(body, "TxtTypeRow_" id, GetLang("类型："), "TxtTypeCmb_" id, typeNames, this._IndexInLangArr(typeNames, tt), true, true, lw, cw)
        this._AddEditableComboRow(body, "TxtNameRow_" id, GetLang("文本变量："), "TxtName_" id, GetGuiVarArr(), tn, true, lw, cw)
        this._AddTextOpsArgsTypeRow(body, id, tt, at, ShowArgsType && this._FormalTextOpsArgsTypes(tt).Length > 0, lw, cw)
        this._AddEditableComboRow(body, "TxtArgsNameRow_" id, GetLang("参数值："), "TxtArgsName_" id, GetGuiVarArr(2), an, ShowArgsName, lw, cw)
        this._AddFieldRow(body, "TxtSearchRow_" id, GetLang("查找："), "TxtSearch_" id, sr, IsReplace, true, "", "", "", lw, cw)
        this._AddFieldRow(body, "TxtReplaceRow_" id, GetLang("替换："), "TxtReplace_" id, rp, IsReplace, true, "", "", "", lw, cw)
        ; 保存类型固定为文本框（参考文件读写节点），避免切换类型时闪烁
        this._AddFieldRow(body, "TxtSaveTypeRow_" id, GetLang("保存类型："), "TxtSaveTypeTxt_" id, fixedSt, true, false, "", "", "", lw, cw)
        this._AddEditableComboRow(body, "TxtSaveRow_" id, GetLang("保存名："), "TxtSave_" id, GetGuiVarArr(), sn, true, lw, cw)
    }

    _FillArrayBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        typeNames := GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
        saveTypes := GetLangArr(["变量", "数组"])
        argsTypes := GetLangArr(["变量或值", "数组"])
        at := d.HasOwnProp("arrayType") ? d.arrayType : "创建"
        an := d.HasOwnProp("arrayName") ? d.arrayName : "Arr"
        ign := d.HasOwnProp("isIgnoreExist") ? d.isIgnoreExist : 0
        initTxt := d.HasOwnProp("initArr") ? this._FormalInitArrText(d.initArr) : "1,2,3,4,5"
        mi := d.HasOwnProp("mainIndex") ? d.mainIndex : 0
        ai := d.HasOwnProp("argsIndex") ? d.argsIndex : 1
        agt := d.HasOwnProp("argsType") ? d.argsType : "变量或值"
        agn := d.HasOwnProp("argsName") ? d.argsName : "Var1"
        st := d.HasOwnProp("saveType") ? d.saveType : "变量"
        sn := d.HasOwnProp("saveName") ? d.saveName : "Data"
        f := this._ArrFlags(at)
        fixedSt := this._ArrFixedSaveType(at)
        effSt := fixedSt != "" ? fixedSt : st
        showIdx := f.IsShowArgs && !f.OnlyArgsData
        showData := f.IsShowArgs && !f.OnlyArgsIndex
        argsNameList := (agt == "数组") ? GetGuiArrNameArr() : GetGuiVarArr()
        saveNameList := (effSt == "数组") ? GetGuiArrNameArr() : GetGuiVarArr()
        this._AddComboRow(body, "ArrTypeRow_" id, GetLang("操作："), "ArrTypeCmb_" id, typeNames, this._IndexInLangArr(typeNames, GetLang(at)), true, true, lw, cw)
        this._AddEditableComboRow(body, "ArrNameRow_" id, GetLang("数组："), "ArrName_" id, GetGuiArrNameArr(), an, true, lw, cw)
        this._AddCheckRow(body, "ArrIgnRow_" id, "ArrIgn_" id, GetLang("如果数组存在则不改变数据"), (ign == 1 || ign == "1") && f.ShowIgn, f.ShowIgn)
        this._AddFieldRow(body, "ArrInitRow_" id, GetLang("初始值："), "ArrInit_" id, initTxt, f.IsCreate, true, "", "", "", lw, cw)
        this._AddEditableComboRow(body, "ArrMainRow_" id, GetLang("子索引："), "ArrMain_" id, GetGuiVarArr(), mi, f.IsShowMainIndex, lw, cw)
        this._AddEditableComboRow(body, "ArrArgsIdxRow_" id, GetLang("索引："), "ArrArgsIdx_" id, GetGuiVarArr(), ai, showIdx, lw, cw)
        this._AddComboRow(body, "ArrArgsTypeRow_" id, GetLang("参数类型："), "ArrArgsTypeCmb_" id, argsTypes, this._IndexInLangArr(argsTypes, GetLang(agt)), showData, true, lw, cw)
        this._AddEditableComboRow(body, "ArrArgsNameRow_" id, GetLang("参数值："), "ArrArgsName_" id, argsNameList, agn, showData, lw, cw)
        this._AddComboRow(body, "ArrSaveTypeRow_" id, GetLang("保存类型："), "ArrSaveTypeCmb_" id, saveTypes, this._IndexInLangArr(saveTypes, GetLang(effSt)), f.IsShowResult, fixedSt == "", lw, cw)
        this._AddEditableComboRow(body, "ArrSaveRow_" id, GetLang("保存名："), "ArrSave_" id, saveNameList, sn, f.IsShowResult, lw, cw)
    }

    _FillRmtBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        categories := this._RmtCategories()
        ; 获取当前指令和类别
        currentOp := d.HasOwnProp("rmtOp") ? d.rmtOp : GetLang("截图")
        currentCategory := d.HasOwnProp("rmtCategory") ? d.rmtCategory : GetLang("全部")
        ; 根据类别获取指令列表，如果当前指令不在列表中则使用全部
        ops := this._RmtCategoryOps(currentCategory)
        if (!this._ArrayContains(ops, currentOp)) {
            ops := this._RmtCategoryOps(GetLang("全部"))
            currentCategory := GetLang("全部")
        }
        ; 安全获取菜单索引（确保是有效数字）
        menuIdx := 1
        if (d.HasOwnProp("rmtMenuIdx") && d.rmtMenuIdx != "" && IsNumber(d.rmtMenuIdx)) {
            parsed := Integer(d.rmtMenuIdx)
            if (parsed > 0)
                menuIdx := parsed
        }
        menuItems := this._FormalMenuIndexItems()
        showMenu := currentOp == GetLang("显示菜单")
        ; 类别下拉框
        this._AddComboRow(body, "RmtCatRow_" id, GetLang("类别："), "RmtCatCmb_" id, categories, this._IndexInLangArr(categories, currentCategory), true, true, lw, cw)
        ; 指令下拉框
        this._AddComboRow(body, "RmtOpRow_" id, GetLang("指令："), "RmtOpCmb_" id, ops, this._IndexInLangArr(ops, currentOp), true, true, lw, cw)
        ; 菜单序号（仅显示菜单时显示）
        this._AddComboRow(body, "RmtMenuRow_" id, GetLang("菜单序号："), "RmtMenuCmb_" id, menuItems, Max(0, menuIdx - 1), showMenu && menuItems.Length > 0, showMenu, lw, cw)
    }

    _FillBGMouseBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        varList := GetGuiVarArr()
        opTypes := GetLangArr(["点击", "双击", "按下", "松开"])
        mouseTypes := GetLangArr(["左键", "中键", "右键", "滚轮"])
        ot := d.HasOwnProp("bgOperateType") ? d.bgOperateType : 1
        mt := d.HasOwnProp("bgMouseType") ? d.bgMouseType : 1
        isScroll := mt == 4
        showClickTime := !isScroll && (ot == 1 || ot == 2)   ; 点击/双击
        tt := d.HasOwnProp("targetTitle") ? d.targetTitle : ""
        px := d.HasOwnProp("bgPosVarX") ? d.bgPosVarX : 100
        py := d.HasOwnProp("bgPosVarY") ? d.bgPosVarY : 100
        ctm := d.HasOwnProp("clickTime") ? d.clickTime : 50
        sv := d.HasOwnProp("scrollV") ? d.scrollV : 1
        sh := d.HasOwnProp("scrollH") ? d.scrollH : 0
        titleRow := body.Add("StackPanel").Name("BgmTitleRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        this._MakeTextBox(titleRow, "BgmTitle_" id, tt, "130")
        titleRow.Add("Button").Name("BgmTitleEdit_" id).Content(GetLang("编辑")).FontSize(this._MGFontSize(11)).Height("20").Margin("4,0,0,0").Padding("8,0").Cursor("Hand")
        this._AddComboRow(body, "BgmMouseRow_" id, GetLang("按键："), "BgmMouseCmb_" id, mouseTypes, mt - 1, true, true, lw, cw)
        this._AddComboRow(body, "BgmOpRow_" id, GetLang("动作："), "BgmOpCmb_" id, opTypes, ot - 1, !isScroll, !isScroll, lw, cw)
        this._AddFieldRow(body, "BgmTimeRow_" id, GetLang("点击时间:"), "BgmTime_" id, ctm, showClickTime, true, "", "", "", lw, cw)
        this._AddEditableComboRow(body, "BgmXRow_" id, GetLang("坐标X："), "BgmX_" id, varList, px, true, lw, cw)
        this._AddEditableComboRow(body, "BgmYRow_" id, GetLang("坐标Y："), "BgmY_" id, varList, py, true, lw, cw)
        this._AddFieldRow(body, "BgmSVRow_" id, GetLang("垂直滚动："), "BgmSV_" id, sv, isScroll, true, "", "", "", lw, cw)
        this._AddFieldRow(body, "BgmSHRow_" id, GetLang("水平滚动："), "BgmSH_" id, sh, isScroll, true, "", "", "", lw, cw)
    }

    _FillBGKeyBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        typeNames := GetLangArr(["按下", "松开", "点击"])
        tt := d.HasOwnProp("bgKeyType") ? d.bgKeyType : 1
        fs := d.HasOwnProp("frontStr") ? d.frontStr : ""
        keyStr := d.HasOwnProp("bgKeyStr") ? d.bgKeyStr : ""
        ctm := d.HasOwnProp("clickTime") ? d.clickTime : 100
        cc := d.HasOwnProp("clickCount") ? d.clickCount : 1
        ci := d.HasOwnProp("clickInterval") ? d.clickInterval : 100
        isClick := tt == 3
        body.Add("TextBlock").Name("BgkKeys_" id).Text(keyStr).Foreground("{DynamicResource EditText}").FontWeight("Bold").FontSize(this._MGFontSize(13)).TextWrapping("Wrap")
        frontRow := body.Add("StackPanel").Name("BgkFrontRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        this._MakeTextBox(frontRow, "BgkFront_" id, fs, "130")
        frontRow.Add("Button").Name("BgkFrontEdit_" id).Content(GetLang("编辑")).FontSize(this._MGFontSize(11)).Height("20").Margin("4,0,0,0").Padding("8,0").Cursor("Hand")
        this._AddComboRow(body, "BgkTypeRow_" id, GetLang("类型："), "BgkTypeCmb_" id, typeNames, tt - 1, true, true, lw, cw)
        this._AddFieldRow(body, "BgkTimeRow_" id, GetLang("点击时长："), "BgkTime_" id, ctm, isClick, true, "", "", "", lw, cw)
        this._AddFieldRow(body, "BgkCountRow_" id, GetLang("点击次数："), "BgkCount_" id, cc, isClick, true, "", "", "", lw, cw)
        this._AddFieldRow(body, "BgkInterRow_" id, GetLang("每次间隔："), "BgkInter_" id, ci, isClick, true, "", "", "", lw, cw)
    }

    ; 与 WindowManageGui.ActionTypeArr 一致
    _FormalWindowManageActions() {
        return GetLangArr(["激活窗口", "最大化窗口", "最小化窗口", "还原窗口", "关闭窗口", "移动窗口",
            "调整大小", "置顶窗口", "取消置顶", "修改标题", "修改透明度", "开启鼠标穿透", "关闭鼠标穿透"])
    }

    _FillWindowManageBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        varList := GetGuiVarArr()
        actions := this._FormalWindowManageActions()
        at := d.HasOwnProp("wmActionType") ? d.wmActionType : "激活窗口"
        sv := d.HasOwnProp("wmSearchValue") ? d.wmSearchValue : ""
        atKey := GetLangKey(at)
        isMove := atKey == "移动窗口"
        isSize := atKey == "调整大小"
        isTitle := atKey == "修改标题"
        isTrans := atKey == "修改透明度"
        this._AddComboRow(body, "WmActRow_" id, GetLang("操作："), "WmActCmb_" id, actions, this._IndexInLangArr(actions, GetLang(at)), true, true, lw, cw)
        winRow := body.Add("StackPanel").Name("WmWinRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        this._MakeTextBox(winRow, "WmWin_" id, sv, "130")
        this._ApplyActionBtnStyle(winRow.Add("Button").Name("WmWinEdit_" id).Content(GetLang("编辑")).Width("40").Height("20").FontSize(this._MGFontSize(11)).Padding("0").Margin("4,0,0,0").VerticalAlignment("Center").Cursor("Hand").Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}").BorderThickness("1").BorderBrush("{DynamicResource ActionStroke}"))
        this._AddEditableComboRow(body, "WmXRow_" id, GetLang("坐标X："), "WmX_" id, varList, d.HasOwnProp("wmPosX") ? d.wmPosX : 0, isMove, lw, cw)
        this._AddEditableComboRow(body, "WmYRow_" id, GetLang("坐标Y："), "WmY_" id, varList, d.HasOwnProp("wmPosY") ? d.wmPosY : 0, isMove, lw, cw)
        this._AddEditableComboRow(body, "WmWRow_" id, GetLang("宽度："), "WmW_" id, varList, d.HasOwnProp("wmWidth") ? d.wmWidth : 0, isSize, lw, cw)
        this._AddEditableComboRow(body, "WmHRow_" id, GetLang("高度："), "WmH_" id, varList, d.HasOwnProp("wmHeight") ? d.wmHeight : 0, isSize, lw, cw)
        this._AddEditableComboRow(body, "WmTitleRow_" id, GetLang("新标题："), "WmTitle_" id, varList, d.HasOwnProp("wmNewTitle") ? d.wmNewTitle : "", isTitle, lw, cw)
        this._AddEditableComboRow(body, "WmTransRow_" id, GetLang("透明度："), "WmTrans_" id, varList, d.HasOwnProp("wmTransparency") ? d.wmTransparency : "80", isTrans, lw, cw)
    }

    _FillKeyCheckBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        checkTypes := GetLangArr(["同时按下", "有一个按下"])
        stateTypes := GetLangArr(["物理状态", "逻辑状态"])
        ct := d.HasOwnProp("kcCheckType") ? d.kcCheckType : 1
        st := d.HasOwnProp("kcStateType") ? d.kcStateType : 1
        vn := d.HasOwnProp("kcVarName") ? d.kcVarName : ""
        keyStr := d.HasOwnProp("kcKeyStr") ? d.kcKeyStr : ""
        body.Add("TextBlock").Name("KcKeys_" id).Text(keyStr).Foreground("{DynamicResource EditText}").FontWeight("Bold").FontSize(this._MGFontSize(13)).TextWrapping("Wrap")
        this._AddComboRow(body, "KcCheckRow_" id, GetLang("检测："), "KcCheckCmb_" id, checkTypes, ct - 1, true, true, lw, cw)
        this._AddComboRow(body, "KcStateRow_" id, GetLang("状态类型："), "KcStateCmb_" id, stateTypes, st - 1, true, true, lw, cw)
        this._AddEditableComboRow(body, "KcVarRow_" id, GetLang("变量："), "KcVar_" id, GetGuiVarArr(), vn, true, lw, cw)
    }

    _FillScreenShotBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        varList := GetGuiVarArr()
        typeNames := GetLangArr(["屏幕抓图", "窗口抓图"])
        st := d.HasOwnProp("ssType") ? d.ssType : 1
        isWin := st == 2
        nt := d.HasOwnProp("ssNameType") ? d.ssNameType : 1
        showFixed := nt == 1 || nt == "1"
        fixed := d.HasOwnProp("ssFixedName") ? d.ssFixedName : "Shot"
        wi := d.HasOwnProp("ssWinInfo") ? d.ssWinInfo : ""
        toggle := d.HasOwnProp("ssResultToggle") ? d.ssResultToggle : 0
        on := toggle == 1 || toggle == "1"
        rn := d.HasOwnProp("ssResultSaveName") ? d.ssResultSaveName : GetLang("图片路径")
        this._AddComboRow(body, "SsTypeRow_" id, GetLang("类型："), "SsTypeCmb_" id, typeNames, st - 1, true, true, lw, cw)
        winRow := body.Add("StackPanel").Name("SsWinRow_" id).Orientation("Horizontal").Margin("0,5,0,0")
        if (!isWin)
            winRow.Visibility("Collapsed")
        this._MakeTextBox(winRow, "SsWin_" id, wi, "130")
        winRow.Add("Button").Name("SsWinEdit_" id).Content(GetLang("编辑")).FontSize(this._MGFontSize(11)).Height("20").Margin("4,0,0,0").Padding("8,0").Cursor("Hand")
        this._AddEditableComboRow(body, "SsSXRow_" id, GetLang("起始X："), "SsSX_" id, varList, d.HasOwnProp("ssStartX") ? d.ssStartX : 0, true, lw, cw)
        this._AddEditableComboRow(body, "SsSYRow_" id, GetLang("起始Y："), "SsSY_" id, varList, d.HasOwnProp("ssStartY") ? d.ssStartY : 0, true, lw, cw)
        this._AddEditableComboRow(body, "SsEXRow_" id, GetLang("终止X："), "SsEX_" id, varList, d.HasOwnProp("ssEndX") ? d.ssEndX : A_ScreenWidth, true, lw, cw)
        this._AddEditableComboRow(body, "SsEYRow_" id, GetLang("终止Y："), "SsEY_" id, varList, d.HasOwnProp("ssEndY") ? d.ssEndY : A_ScreenHeight, true, lw, cw)
        this._AddCheckRow(body, "SsNameTogRow_" id, "SsNameTog_" id, GetLang("固定名称："), showFixed, true)
        this._AddFieldRow(body, "SsFixedRow_" id, GetLang("名称："), "SsFixed_" id, fixed, showFixed, true, "", "", "", lw, cw)
        this._AddCheckRow(body, "SsResTogRow_" id, "SsResTog_" id, GetLang("保存到变量"), on, true)
        this._AddEditableComboRow(body, "SsResNameRow_" id, GetLang("变量名："), "SsResName_" id, varList, rn, on, lw, cw)
    }

    _LoopCondiTypes() {
        return GetLangArr(["无", "继续条件", "退出条件"])
    }

    _LoopLogicTypes() {
        return GetLangArr(["且", "或"])
    }

    _LoopCmpTypes() {
        return GetLangArr(["大于", "大于等于", "等于", "小于等于", "小于", "字符包含", "变量存在", "正则匹配"])
    }

    _IfLogicTypes() {
        return this._LoopLogicTypes()
    }

    _IfCmpTypes() {
        return this._LoopCmpTypes()
    }

    ; 如果节点：逻辑关系 + 条件1~4（分割线分隔、标准宽）+ 结果保存；收起态为条件摘要 + 内嵌真/假分支
    _FillIfCondiCard(body, id, slot, d, showCard) {
        lw := this._FormalLW(), cw := this._FormalCW()
        p := "IfC" slot
        on := (slot == 1) ? true : (d.HasOwnProp("ifTog" slot) && (d["ifTog" slot] == 1 || d["ifTog" slot] == "1"))
        if (slot == 1 && d.HasOwnProp("ifTog1"))
            on := d["ifTog1"] == 1 || d["ifTog1"] == "1"
        nm := d.HasOwnProp("ifName" slot) ? d["ifName" slot] : "Var" slot
        cmp := d.HasOwnProp("ifCmp" slot) ? d["ifCmp" slot] : 1
        vr := d.HasOwnProp("ifVar" slot) ? d["ifVar" slot] : "Var" slot
        cmpTypes := this._IfCmpTypes()
        showRow := showCard && on
        showVal := showRow && cmp != 7
        block := body.Add("StackPanel").Name(p "TogRow_" id).Margin("0,2,0,0")
        if (!showCard)
            block.Visibility("Collapsed")
        block.Add("Border").Name(p "Sep_" id).Height("1").Margin("0,6,0,4").BorderThickness("0").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        this._AddCheckRow(block, p "TogChkRow_" id, p "Tog_" id, GetLang("条件") slot, on, true)
        this._AddEditableComboRow(block, p "NameRow_" id, GetLang("变量："), p "Name_" id, GetGuiVarArr(), GetLang(nm), showRow, lw, cw)
        this._AddComboRow(block, p "CmpRow_" id, GetLang("比较："), p "Cmp_" id, cmpTypes, cmp - 1, showRow, true, lw, cw)
        this._AddEditableComboRow(block, p "VarRow_" id, GetLang("值："), p "Var_" id, GetGuiVarArr(), GetLang(vr), showVal, lw, cw)
    }

    ; 如果条件收起态简要：{on, text}
    _IfCondiSummaryRow(data, slot) {
        res := {on: false, text: ""}
        if (data == "")
            return res
        tog := data.ToggleArr[slot]
        if (!tog)
            return res
        res.on := true
        cmpArr := this._IfCmpTypes()
        ct := data.CompareTypeArr[slot]
        cmpStr := (ct >= 1 && ct <= cmpArr.Length) ? cmpArr[ct] : cmpArr[1]
        nm := GetLang(data.NameArr[slot])
        res.text := (ct != 7) ? nm " " cmpStr " " GetLang(data.VariableArr[slot]) : nm " " cmpStr
        return res
    }

    _FillIfCondiSummary(id, box) {
        fg := "{DynamicResource TextMain}"
        data := this._SearchData(id)
        anyOn := false
        loop 4 {
            slot := A_Index
            ci := this._IfCondiSummaryRow(data, slot)
            if (ci.on)
                anyOn := true
            row := box.Add("StackPanel").Name("IfSumCondiRow_" slot "_" id).Orientation("Horizontal").Margin("0,3,0,0")
            if (!ci.on)
                row.Visibility("Collapsed")
            row.Add("Ellipse").Width("7").Height("7").Fill("{DynamicResource GraphConnSel}").Margin("0,0,6,0").VerticalAlignment("Center")
            row.Add("TextBlock").Name("IfSumCondiTxt_" slot "_" id).Text(ci.text).Foreground(fg).FontSize(this._MGFontSize(11)).VerticalAlignment("Center").TextTrimming("CharacterEllipsis")
        }
        emptyTb := box.Add("TextBlock").Name("IfSumEmpty_" id).Text(GetLang("未启用任何条件")).Foreground(fg).FontSize(this._MGFontSize(11)).Margin("0,3,0,0")
        if (anyOn)
            emptyTb.Visibility("Collapsed")
    }

    ; 收起态：内嵌真/假分支指令列表 + 流程控制（简化文字）
    _FillIfInlineBranches(parent, id, folded) {
        fg := "{DynamicResource TextMain}"
        box := parent.Add("StackPanel").Name("IfInlineBranch_" id).Margin("0,2,0,0")
        box.Visibility(folded ? "Visible" : "Collapsed")
        for isTrue in [true, false] {
            tag := isTrue ? "T" : "F"
            box.Add("Border").Height("1").Margin("0,6,0,4").BorderThickness("0").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
            head := box.Add("StackPanel").Orientation("Horizontal")
            head.Add("Ellipse").Width("8").Height("8").Fill(isTrue ? "#4CAF50" : "#E53935").Margin("0,0,6,0").VerticalAlignment("Center")
            head.Add("TextBlock").Text(this._BranchTitleFor(id, isTrue)).Foreground(fg).FontSize(this._MGFontSize(12)).FontWeight("Bold")
            cmds := this._BranchGraphCmds(this._BranchStartSerial(id, isTrue))
            this._FillLoopChips(box, "IfInline" tag "Chips_" id, "IfInline" tag "Expand_" id, "IfInline" tag "_" id, cmds)
            data := this._BranchParentData(id)
            ct := "无"
            if (data != "") {
                raw := isTrue ? (data.HasOwnProp("TrueControlType") ? data.TrueControlType : "无") : (data.HasOwnProp("FalseControlType") ? data.FalseControlType : "无")
                ct := GetLang(raw)
            }
            box.Add("TextBlock").Name("IfInline" tag "Flow_" id).Text(GetLang("流程控制") "：" ct).Foreground(fg).FontSize(this._MGFontSize(11)).Margin("0,2,0,0")
        }
    }

    ; 展开/收起如果节点内嵌分支指令列表
    _OnIfInlineChipsToggle(id, isTrue, *) {
        if (this.ui == "")
            return
        tag := isTrue ? "T" : "F"
        key := "IfInline" tag "_" id
        panelName := "IfInline" tag "Chips_" id
        btnName := "IfInline" tag "Expand_" id
        nv := !(this._loopChipsExpanded.Has(key) && this._loopChipsExpanded[key])
        this._loopChipsExpanded[key] := nv
        cmds := this._BranchGraphCmds(this._BranchStartSerial(id, isTrue))
        this._RebuildLoopChips(panelName, cmds, nv)
        this.ui.Update(btnName, "Content", nv ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")"))
    }

    ; 运行时刷新如果节点收起态条件摘要
    _RefreshIfSummary(id) {
        if (this.ui == "")
            return
        data := this._SearchData(id)
        anyOn := false
        loop 4 {
            slot := A_Index
            ci := this._IfCondiSummaryRow(data, slot)
            if (ci.on)
                anyOn := true
            this.ui.Update("IfSumCondiRow_" slot "_" id, "Visibility", ci.on ? "Visible" : "Collapsed")
            this.ui.Update("IfSumCondiTxt_" slot "_" id, "Text", ci.text)
        }
        this.ui.Update("IfSumEmpty_" id, "Visibility", anyOn ? "Collapsed" : "Visible")
    }

    ; 运行时刷新如果节点收起态内嵌真/假分支
    _RefreshIfInlineBranches(id) {
        if (this.ui == "")
            return
        for isTrue in [true, false] {
            tag := isTrue ? "T" : "F"
            key := "IfInline" tag "_" id
            cmds := this._BranchGraphCmds(this._BranchStartSerial(id, isTrue))
            expanded := this._loopChipsExpanded.Has(key) && this._loopChipsExpanded[key]
            this._RebuildLoopChips("IfInline" tag "Chips_" id, cmds, expanded)
            this.ui.Update("IfInline" tag "Expand_" id, "Visibility", cmds.Length > this._LoopPreviewCount() ? "Visible" : "Collapsed")
            this.ui.Update("IfInline" tag "Expand_" id, "Content", expanded ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")"))
            data := this._BranchParentData(id)
            ct := "无"
            if (data != "") {
                raw := isTrue ? (data.HasOwnProp("TrueControlType") ? data.TrueControlType : "无") : (data.HasOwnProp("FalseControlType") ? data.FalseControlType : "无")
                ct := GetLang(raw)
            }
            this.ui.Update("IfInline" tag "Flow_" id, "Text", GetLang("流程控制") "：" ct)
        }
    }

    _FillIfBody(id, d, body) {
        lw := this._FormalLW(), cw := this._FormalCW()
        folded := this._NodeFolded(id)
        logicTypes := this._IfLogicTypes()
        logicType := d.HasOwnProp("logicType") ? d.logicType : 1
        saveOn := d.HasOwnProp("saveToggle") && (d.saveToggle == 1 || d.saveToggle == "1")
        saveName := d.HasOwnProp("saveName") ? d.saveName : GetLang("结果")
        trueVal := d.HasOwnProp("trueValue") ? d.trueValue : 1
        falseVal := d.HasOwnProp("falseValue") ? d.falseValue : 0
        ; 逻辑关系始终可编辑（与循环次数类似）
        this._AddComboRow(body, "IfLogicRow_" id, GetLang("逻辑关系："), "IfLogicCmb_" id, logicTypes, Max(0, logicType - 1), true, true, lw, cw)

        ; ---- 展开：完整条件 + 结果保存 ----
        fullBox := body.Add("StackPanel").Name("IfFullBox_" id)
        fullBox.Visibility(folded ? "Collapsed" : "Visible")
        prevOn := true
        loop 4 {
            slot := A_Index
            chainVis := (slot == 1) ? true : prevOn
            this._FillIfCondiCard(fullBox, id, slot, d, chainVis)
            on := (slot == 1) ? true : (d.HasOwnProp("ifTog" slot) && (d["ifTog" slot] == 1 || d["ifTog" slot] == "1"))
            if (slot == 1 && d.HasOwnProp("ifTog1"))
                on := d["ifTog1"] == 1 || d["ifTog1"] == "1"
            prevOn := chainVis && on
        }
        this._AddCheckRow(fullBox, "IfSaveTogRow_" id, "IfSaveTog_" id, GetLang("结果保存"), saveOn, true)
        this._AddEditableComboRow(fullBox, "IfSaveNameRow_" id, GetLang("变量名："), "IfSaveName_" id, GetGuiVarArr(), GetLang(saveName), saveOn, lw, cw)
        this._AddFieldRow(fullBox, "IfTrueValRow_" id, GetLang("真值："), "IfTrueVal_" id, trueVal, saveOn, true, "", "", "", lw, cw)
        this._AddFieldRow(fullBox, "IfFalseValRow_" id, GetLang("假值："), "IfFalseVal_" id, falseVal, saveOn, true, "", "", "", lw, cw)

        ; ---- 收起：条件圆点摘要 ----
        sumBox := body.Add("StackPanel").Name("IfSumBox_" id)
        sumBox.Visibility(folded ? "Visible" : "Collapsed")
        this._FillIfCondiSummary(id, sumBox)

        ; ---- 收起：内嵌真/假分支 ----
        this._FillIfInlineBranches(body, id, folded)
    }

    ; 循环体命令显示串数组（用于内联小卡片展示）。
    ; 循环体可能保存两种形式：①图形开始节点序列码（嵌套图，复用 _BranchGraphCmds 遍历）②线性宏串。
    _LoopBodyCmds(d) {
        body := d.HasOwnProp("loopBody") ? d.loopBody : ""
        if (body == "")
            return []
        SplitSerialTextAndNumbers(body, &t, &n)
        if (t == GetLangKey("图形开始节点") && n != "")
            return this._BranchGraphCmds(body)
        result := []
        for cmd in SplitMacro(GetLangMacro(body, 1)) {
            if (cmd != "")
                result.Push(cmd)
        }
        return result
    }

    ; 循环体卡片预览的最大条数（超出则提供展开/收起按钮，与搜索分支节点一致）。
    _LoopPreviewCount() {
        return 5
    }

    ; 循环体指令行 XAML（与分支共用斑马纹样式）。
    _LoopChipXaml(text, idx := 1) {
        return this._CmdChipXaml(text, idx)
    }

    ; 构建循环体指令列表 + 展开/收起按钮（内联体与外置体共用；样式与分支统一）。
    ;   parent：承载容器；panelName：列表命名；btnName：按钮命名；key：展开态键；cmds：指令串数组。
    ;   panelMargin：默认 -10 抵消节点 body 左边距；组框内嵌时传 "0" 以免顶破左右内边距。
    _FillLoopChips(parent, panelName, btnName, key, cmds, panelMargin := "-10,0,0,0") {
        expanded := this._loopChipsExpanded.Has(key) && this._loopChipsExpanded[key]
        panel := parent.Add("StackPanel").Name(panelName).Margin(panelMargin)
        if (cmds.Length == 0) {
            emptyMg := (panelMargin = "-10,0,0,0") ? "10,0,0,0" : "0"
            panel.Add("TextBlock").Text("（" GetLang("空") "）").Foreground("{DynamicResource TextMain}").FontSize(this._MGFontSize(11)).Margin(emptyMg)
        } else {
            shown := expanded ? cmds.Length : Min(cmds.Length, this._LoopPreviewCount())
            Loop shown
                this._AddCmdChip(panel, "· " cmds[A_Index], A_Index)
        }
        btn := parent.Add("Button").Name(btnName).Content(expanded ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")")).FontSize(this._MGFontSize(10)).Height("20").Margin("0,4,0,0").Padding("6,0").HorizontalAlignment("Left")
        if (cmds.Length <= this._LoopPreviewCount())
            btn.Visibility("Collapsed")
    }

    ; 运行时按展开态重建循环体指令列表（清空后重注入）。
    _RebuildLoopChips(panelName, cmds, expanded) {
        this.ui.Update(panelName, "ClearItems", "")
        if (cmds.Length == 0) {
            this.ui.Update(panelName, "AddXamlItem", this._CmdChipEmptyXaml())
            return
        }
        shown := expanded ? cmds.Length : Min(cmds.Length, this._LoopPreviewCount())
        Loop shown
            this.ui.Update(panelName, "AddXamlItem", this._CmdChipXaml("· " cmds[A_Index], A_Index))
    }

    ; 展开/收起循环体指令卡片（内联体与外置体共用按钮回调）。loopId 用于取最新循环体指令。
    _OnLoopChipsToggle(key, panelName, btnName, loopId, *) {
        if (this.ui == "")
            return
        nv := !(this._loopChipsExpanded.Has(key) && this._loopChipsExpanded[key])
        this._loopChipsExpanded[key] := nv
        cmds := this._LoopBodyCmds(this._FormalDFromId(loopId))
        this._RebuildLoopChips(panelName, cmds, nv)
        this.ui.Update(btnName, "Content", nv ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")"))
    }

    ; 运行时刷新内联循环体卡片 + 展开按钮 + 计数徽标。
    _RefreshLoopChips(id) {
        if (this.ui == "")
            return
        cmds := this._LoopBodyCmds(this._FormalDFromId(id))
        expanded := this._loopChipsExpanded.Has(id) && this._loopChipsExpanded[id]
        this._RebuildLoopChips("LoopChipsPanel_" id, cmds, expanded)
        this.ui.Update("LoopChipsExpand_" id, "Visibility", cmds.Length > this._LoopPreviewCount() ? "Visible" : "Collapsed")
        this.ui.Update("LoopChipsExpand_" id, "Content", expanded ? GetLang("收起") : (GetLang("展开") " (" cmds.Length ")"))
        this.ui.Update("LoopBodyCount_" id, "Text", this._LoopBodyBadge(cmds.Length))
    }

    ; 循环体徽标文本（数量已由下方展开按钮提示，此处不再显示计数）。
    _LoopBodyBadge(count) {
        return GetLang("循环体")
    }

    ; 循环次数行文本（无限时友好显示）。
    _LoopCountText(d) {
        lc := d.HasOwnProp("loopCount") ? d.loopCount : 10
        return (lc == -1 || lc == "-1") ? GetLang("无限") : lc
    }

    ; 单个条件行卡片：开关 + 变量名 + 比较类型 + 比较值（变量存在时隐藏值）。
    _FillLoopCondiCard(body, id, slot, d, showCard) {
        ; 条件内下拉与间隔/循环主行一致：标准 Formal 宽(80/96)；用分隔线代替组框，不挤占左右区域
        lw := this._FormalLW(), cw := this._FormalCW()
        p := "LoopC" slot
        on := d.HasOwnProp("loopTog" slot) && (d["loopTog" slot] == 1 || d["loopTog" slot] == "1")
        nm := d.HasOwnProp("loopName" slot) ? d["loopName" slot] : "Var" slot
        cmp := d.HasOwnProp("loopCmp" slot) ? d["loopCmp" slot] : 1
        vr := d.HasOwnProp("loopVar" slot) ? d["loopVar" slot] : "Var" slot
        cmpTypes := this._LoopCmpTypes()
        showRow := showCard && on
        showVal := showRow && cmp != 7
        block := body.Add("StackPanel").Name(p "TogRow_" id).Margin("0,2,0,0")
        if (!showCard)
            block.Visibility("Collapsed")
        ; 顶部分隔线：与上方字段 / 上一条件分割
        block.Add("Border").Name(p "Sep_" id).Height("1").Margin("0,6,0,4").BorderThickness("0").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        this._AddCheckRow(block, p "TogChkRow_" id, p "Tog_" id, GetLang("条件") slot, on, true)
        this._AddEditableComboRow(block, p "NameRow_" id, GetLang("变量："), p "Name_" id, GetGuiVarArr(), GetLang(nm), showRow, lw, cw)
        this._AddComboRow(block, p "CmpRow_" id, GetLang("比较："), p "Cmp_" id, cmpTypes, cmp - 1, showRow, true, lw, cw)
        this._AddEditableComboRow(block, p "VarRow_" id, GetLang("值："), p "Var_" id, GetGuiVarArr(), GetLang(vr), showVal, lw, cw)
    }

    ; 循环节点收起态摘要信息：循环次数 / 循环条件类型 / 逻辑关系。
    _LoopSummaryInfo(id) {
        info := {count: "", condiName: "", logicName: "", showLogic: false}
        data := this._SearchData(id)
        if (data == "")
            return info
        info.count := (data.LoopCount == -1 || data.LoopCount == "-1") ? GetLang("无限") : data.LoopCount
        condiTypes := this._LoopCondiTypes()
        ct := data.CondiType
        info.condiName := (ct >= 1 && ct <= condiTypes.Length) ? condiTypes[ct] : condiTypes[1]
        if (ct != 1) {
            n := 0
            loop 4
                if (data.ToggleArr[A_Index])
                    n++
            logicTypes := this._LoopLogicTypes()
            info.logicName := (data.LogicType >= 1 && data.LogicType <= logicTypes.Length) ? logicTypes[data.LogicType] : logicTypes[1]
            info.showLogic := n >= 2
        }
        return info
    }

    ; 单个条件的收起态简要：{on, text}。on=条件类型非「无」且该条件已启用。
    _LoopCondiSummaryRow(data, slot) {
        res := {on: false, text: ""}
        if (data == "" || data.CondiType == 1 || !data.ToggleArr[slot])
            return res
        res.on := true
        cmpArr := this._LoopCmpTypes()
        ct := data.CompareTypeArr[slot]
        cmpStr := (ct >= 1 && ct <= cmpArr.Length) ? cmpArr[ct] : cmpArr[1]
        nm := GetLang(data.NameArr[slot])
        res.text := (ct != 7) ? nm " " cmpStr " " GetLang(data.VariableArr[slot]) : nm " " cmpStr
        return res
    }

    ; 收起态条件摘要：逻辑关系(多条件时) + 条件1~4 圆点行（次数/循环条件下拉仍保留在上方）。
    _FillLoopCondiSumRows(id, box) {
        info := this._LoopSummaryInfo(id)
        fg := "{DynamicResource TextMain}", fs := this._MGFontSize(12)
        lRow := box.Add("TextBlock").Name("LoopSumLogic_" id).Text(GetLang("逻辑关系") "：" info.logicName).Foreground(fg).FontSize(fs).Margin("0,3,0,0").TextWrapping("Wrap")
        if (!info.showLogic)
            lRow.Visibility("Collapsed")
        data := this._SearchData(id)
        loop 4 {
            slot := A_Index
            ci := this._LoopCondiSummaryRow(data, slot)
            row := box.Add("StackPanel").Name("LoopSumCondiRow_" slot "_" id).Orientation("Horizontal").Margin("0,3,0,0")
            if (!ci.on)
                row.Visibility("Collapsed")
            row.Add("Ellipse").Width("7").Height("7").Fill("{DynamicResource GraphConnSel}").Margin("0,0,6,0").VerticalAlignment("Center")
            row.Add("TextBlock").Name("LoopSumCondiTxt_" slot "_" id).Text(ci.text).Foreground(fg).FontSize(this._MGFontSize(11)).VerticalAlignment("Center").TextTrimming("CharacterEllipsis")
        }
    }

    ; 循环节点主体：
    ;   展开：次数/条件/逻辑/条件卡 + 外置循环体；
    ;   收起：次数/条件下拉保留，条件简化为圆点摘要 + 内置循环体列表。
    _FillLoopBody(id, d, body) {
        ; 与间隔节点一致：标准 Formal 标签/下拉宽(80/96)
        lw := this._FormalLW(), cw := this._FormalCW()
        folded := this._NodeFolded(id)          ; 收起态
        condiTypes := this._LoopCondiTypes()
        logicTypes := this._LoopLogicTypes()
        condiType := d.HasOwnProp("condiType") ? d.condiType : 1
        logicType := d.HasOwnProp("logicType") ? d.logicType : 1
        showCondi := condiType != 1
        cmds := this._LoopBodyCmds(d)

        countItems := GetGuiVarArr()
        countItems.Push(GetLang("无限"))
        this._AddEditableComboRow(body, "LoopCountRow_" id, GetLang("循环次数："), "LoopCount_" id, countItems, this._LoopCountText(d), true, lw, cw)
        this._AddComboRow(body, "LoopCondiRow_" id, GetLang("循环条件："), "LoopCondiCmb_" id, condiTypes, Max(0, condiType - 1), true, true, lw, cw)
        ; 展开态完整条件；收起时隐藏，改用下方摘要
        this._AddComboRow(body, "LoopLogicRow_" id, GetLang("逻辑关系："), "LoopLogicCmb_" id, logicTypes, Max(0, logicType - 1), showCondi && !folded, true, lw, cw)
        prevOn := true
        loop 4 {
            slot := A_Index
            chainVis := (slot == 1) ? true : prevOn
            this._FillLoopCondiCard(body, id, slot, d, showCondi && !folded && chainVis)
            on := d.HasOwnProp("loopTog" slot) && (d["loopTog" slot] == 1 || d["loopTog" slot] == "1")
            prevOn := chainVis && on
        }
        ; ---- 收起态：条件圆点摘要 ----
        sumBox := body.Add("StackPanel").Name("LoopCondiSumBox_" id).Margin("0,2,0,0")
        sumBox.Visibility((folded && showCondi) ? "Visible" : "Collapsed")
        this._FillLoopCondiSumRows(id, sumBox)
        ; ---- 收起态：内置循环体（分割线分隔）----
        inlineBox := body.Add("StackPanel").Name("LoopInlineBody_" id).Margin("0,2,0,0")
        inlineBox.Visibility(folded ? "Visible" : "Collapsed")
        inlineBox.Add("Border").Height("1").Margin("0,6,0,6").BorderThickness("0").Background("{DynamicResource ControlBorder}").IsHitTestVisible("False")
        head := inlineBox.Add("StackPanel").Orientation("Horizontal")
        head.Add("TextBlock").Text("↻ ").Foreground("{DynamicResource TextMain}").FontSize(this._MGFontSize(14))
        head.Add("TextBlock").Name("LoopBodyCount_" id).Text(this._LoopBodyBadge(cmds.Length)).Foreground("{DynamicResource TextMain}").FontSize(this._MGFontSize(12))
        this._FillLoopChips(inlineBox, "LoopChipsPanel_" id, "LoopChipsExpand_" id, id, cmds)
        ; 垫高：回环下端口(Y=146)落在节点内；始终创建以便条件切换时显隐
        pad := body.Add("Border").Name("LoopPortPad_" id).Height("48").BorderThickness("0").Background("Transparent").IsHitTestVisible("False")
        if (showCondi || folded)
            pad.Visibility("Collapsed")
    }

    _IndexInLangArr(arr, target) {
        loop arr.Length {
            if (arr[A_Index] == target)
                return A_Index - 1
        }
        return 0
    }

    _RegisterFormalNodeEvents(id, d, runtime := false) {
        t := d.type
        if (t == GetLang("宏操作")) {
            h := this._OnFormalSubMacro.Bind(this, id)
            this._FormalTrackCombo(id, "SubTypeCmb", h, runtime)
            this._FormalTrackCombo(id, "SubCallCmb", h, runtime)
            this._FormalTrackCombo(id, "SubIdxCmb", h, runtime)
            this._FormalTrackEditCombo(id, "SubIns", h, runtime)
        } else if (t == GetLang("变量")) {
            h := this._OnFormalVariable.Bind(this, id)
            this._FormalTrackCheck(id, "VarIgn", h, runtime)
            loop 4 {
                p := "VarS" A_Index
                this._FormalTrackCheck(id, p "Tog", h, runtime)
                this._FormalTrackCombo(id, p "OpCmb", h, runtime)
                this._FormalTrackEditCombo(id, p "Name", h, runtime)
                this._FormalTrackEditCombo(id, p "Copy", h, runtime)
                this._FormalTrackField(id, p "CopyTxt", h, runtime)
                this._FormalTrackCombo(id, p "SysCmb", h, runtime)
                this._FormalTrackEditCombo(id, p "Min", h, runtime)
                this._FormalTrackEditCombo(id, p "Max", h, runtime)
            }
        } else if (t == GetLang("变量提取")) {
            h := this._OnFormalExVariable.Bind(this, id)
            this._FormalTrackCheck(id, "ExIgn", h, runtime)
            this._FormalTrackCombo(id, "ExTypeCmb", h, runtime)
            this._FormalTrackField(id, "ExStr", h, runtime)
            this._BindCtrl("ExStrEdit_" id, "Click", this._OnFormalExTemplateEdit.Bind(this, id), runtime)
            this._FormalTrackField(id, "ExWin", h, runtime)
            this._FormalTrackCombo(id, "ExOcrCmb", h, runtime)
            for nm in ["ExSX", "ExSY", "ExEX", "ExEY", "ExCnt"]
                this._FormalTrackEditCombo(id, nm, h, runtime)
            this._FormalTrackField(id, "ExInt", h, runtime)
            loop 6 {
                p := "ExV" A_Index
                this._FormalTrackCheck(id, p "Tog", h, runtime)
                this._FormalTrackEditCombo(id, p "Name", h, runtime)
            }
        } else if (t == GetLang("运算")) {
            h := this._OnFormalOperation.Bind(this, id)
            loop 4 {
                p := "OpS" A_Index
                this._FormalTrackCheck(id, p "Tog", h, runtime)
                this._FormalTrackEditCombo(id, p "Target", h, runtime)
                this._FormalTrackField(id, p "Expr", h, runtime)
                this._BindCtrl(p "ExprEdit_" id, "Click", this._OnOperationExprEdit.Bind(this, id, A_Index), runtime)
            }
        } else if (t == GetLang("运行")) {
            h := this._OnFormalRun.Bind(this, id)
            this._FormalTrackField(id, "runTarget", h, runtime)
            this._BindCtrl("RunTargetBrowse_" id, "Click", this._OnRunTargetBrowse.Bind(this, id), runtime)
            this._FormalTrackCombo(id, "RunModeCmb", h, runtime)
            this._FormalTrackCombo(id, "RunOptionCmb", h, runtime)
            this._FormalTrackField(id, "RunStdIn", h, runtime)
            this._FormalTrackCombo(id, "RunEncInCmb", h, runtime)
            this._FormalTrackCombo(id, "RunEncOutCmb", h, runtime)
            this._FormalTrackCombo(id, "RunEncErrCmb", h, runtime)
            loop 3
                this._FormalTrackEditCombo(id, "RunSave" A_Index, h, runtime)
        } else if (t == GetLang("文件读写")) {
            ; 类型/模式各自独立处理（含派生选项刷新），普通字段统一走 _OnFIOField，互不干扰
            hType := this._OnFIOType.Bind(this, id)
            hMode := this._OnFIOMode.Bind(this, id)
            hField := this._OnFIOField.Bind(this, id)
            this._FormalTrackCombo(id, "FIOTypeCmb", hType, runtime)
            this._FormalTrackCombo(id, "FIOModeCmb", hMode, runtime)
            this._BindCtrl("FIOPathBrowse_" id, "Click", this._OnFIOPathBrowse.Bind(this, id), runtime)
            this._FormalTrackField(id, "FIOPath", hField, runtime)
            this._FormalTrackField(id, "FIOSheet", hField, runtime)
            this._FormalTrackCombo(id, "FIOEncCmb", hField, runtime)
            for nm in ["FIORow", "FIOCol", "FIORowEnd", "FIOColEnd", "FIOTxtRow", "FIOArr", "FIOSave"]
                this._FormalTrackEditCombo(id, nm, hField, runtime)
            this._FormalTrackField(id, "FIOContent", hField, runtime)
        } else if (t == GetLang("文本处理")) {
            h := this._OnFormalTextOps.Bind(this, id)
            this._FormalTrackCombo(id, "TxtTypeCmb", h, runtime)
            this._FormalTrackEditCombo(id, "TxtName", h, runtime)
            loop this._FormalTextOpsTypeNames().Length
                this._FormalTrackCombo(id, "TxtArgsTypeCmb_" A_Index, h, runtime)
            this._FormalTrackEditCombo(id, "TxtArgsName", h, runtime)
            this._FormalTrackField(id, "TxtSearch", h, runtime)
            this._FormalTrackField(id, "TxtReplace", h, runtime)
            ; 保存类型是固定的文本框，不需要追踪
            this._FormalTrackEditCombo(id, "TxtSave", h, runtime)
        } else if (t == GetLang("数组")) {
            hType := this._OnFormalArray.Bind(this, id)
            hField := this._OnArrField.Bind(this, id)
            this._FormalTrackCombo(id, "ArrTypeCmb", hType, runtime)
            this._FormalTrackCombo(id, "ArrArgsTypeCmb", hType, runtime)
            this._FormalTrackCombo(id, "ArrSaveTypeCmb", hType, runtime)
            this._FormalTrackEditCombo(id, "ArrName", hField, runtime)
            this._FormalTrackCheck(id, "ArrIgn", hField, runtime)
            this._FormalTrackField(id, "ArrInit", hField, runtime)
            this._FormalTrackEditCombo(id, "ArrMain", hField, runtime)
            this._FormalTrackEditCombo(id, "ArrArgsIdx", hField, runtime)
            this._FormalTrackEditCombo(id, "ArrArgsName", hField, runtime)
            this._FormalTrackEditCombo(id, "ArrSave", hField, runtime)
        } else if (t == GetLang("RMT指令")) {
            hCat := this._OnRmtCategory.Bind(this, id)
            hOp := this._OnRmtOp.Bind(this, id)
            hField := this._OnRmtField.Bind(this, id)
            this._FormalTrackCombo(id, "RmtCatCmb", hCat, runtime)
            this._FormalTrackCombo(id, "RmtOpCmb", hOp, runtime)
            this._FormalTrackCombo(id, "RmtMenuCmb", hField, runtime)
        } else if (t == GetLang("后台鼠标")) {
            h := this._OnFormalBGMouse.Bind(this, id)
            this._FormalTrackField(id, "BgmTitle", h, runtime)
            this._BindCtrl("BgmTitleEdit_" id, "Click", this._OnFormalBGMouseTitleEdit.Bind(this, id), runtime)
            this._FormalTrackCombo(id, "BgmOpCmb", h, runtime)
            this._FormalTrackCombo(id, "BgmMouseCmb", h, runtime)
            this._FormalTrackField(id, "BgmTime", h, runtime)
            this._FormalTrackEditCombo(id, "BgmX", h, runtime)
            this._FormalTrackEditCombo(id, "BgmY", h, runtime)
            this._FormalTrackField(id, "BgmSV", h, runtime)
            this._FormalTrackField(id, "BgmSH", h, runtime)
        } else if (t == GetLang("后台按键")) {
            h := this._OnFormalBGKey.Bind(this, id)
            this._FormalTrackField(id, "BgkFront", h, runtime)
            this._BindCtrl("BgkFrontEdit_" id, "Click", this._OnFormalBGKeyFrontEdit.Bind(this, id), runtime)
            this._FormalTrackCombo(id, "BgkTypeCmb", h, runtime)
            this._FormalTrackField(id, "BgkTime", h, runtime)
            this._FormalTrackField(id, "BgkCount", h, runtime)
            this._FormalTrackField(id, "BgkInter", h, runtime)
        } else if (t == GetLang("窗口管理")) {
            h := this._OnFormalWindowManage.Bind(this, id)
            this._FormalTrackCombo(id, "WmActCmb", h, runtime)
            this._FormalTrackField(id, "WmWin", h, runtime)
            this._BindCtrl("WmWinEdit_" id, "Click", this._OnFormalWmWinEdit.Bind(this, id), runtime)
            for nm in ["WmX", "WmY", "WmW", "WmH", "WmTitle", "WmTrans"]
                this._FormalTrackEditCombo(id, nm, h, runtime)
        } else if (t == GetLang("按键检测")) {
            h := this._OnFormalKeyCheck.Bind(this, id)
            this._FormalTrackCombo(id, "KcCheckCmb", h, runtime)
            this._FormalTrackCombo(id, "KcStateCmb", h, runtime)
            this._FormalTrackEditCombo(id, "KcVar", h, runtime)
        } else if (t == GetLang("抓图")) {
            h := this._OnFormalScreenShot.Bind(this, id)
            this._FormalTrackCombo(id, "SsTypeCmb", h, runtime)
            this._FormalTrackField(id, "SsWin", h, runtime)
            this._BindCtrl("SsWinEdit_" id, "Click", this._OnFormalSsWinEdit.Bind(this, id), runtime)
            for nm in ["SsSX", "SsSY", "SsEX", "SsEY"]
                this._FormalTrackEditCombo(id, nm, h, runtime)
            this._FormalTrackCheck(id, "SsNameTog", h, runtime)
            this._FormalTrackField(id, "SsFixed", h, runtime)
            this._FormalTrackCheck(id, "SsResTog", h, runtime)
            this._FormalTrackEditCombo(id, "SsResName", h, runtime)
        } else if (t == GetLang("注释")) {
            h := this._OnFormalComment.Bind(this, id)
            this._FormalTrackField(id, "CommentText", h, runtime)
        } else if (t == GetLang("循环")) {
            h := this._OnFormalLoop.Bind(this, id)
            this._FormalTrackEditCombo(id, "LoopCount", h, runtime)
            this._FormalTrackCombo(id, "LoopCondiCmb", h, runtime)
            this._FormalTrackCombo(id, "LoopLogicCmb", h, runtime)
            loop 4 {
                p := "LoopC" A_Index
                this._FormalTrackCheck(id, p "Tog", h, runtime)
                this._FormalTrackEditCombo(id, p "Name", h, runtime)
                this._FormalTrackCombo(id, p "Cmp", h, runtime)
                this._FormalTrackEditCombo(id, p "Var", h, runtime)
            }
            this._BindCtrl("LoopChipsExpand_" id, "Click", this._OnLoopChipsToggle.Bind(this, id, "LoopChipsPanel_" id, "LoopChipsExpand_" id, id), runtime)
            this._BindCtrl("SFold_" id, "Click", this._OnToggleLoopFold.Bind(this, id), runtime)
        } else if (t == GetLang("如果")) {
            h := this._OnFormalIf.Bind(this, id)
            this._FormalTrackCombo(id, "IfLogicCmb", h, runtime)
            loop 4 {
                p := "IfC" A_Index
                this._FormalTrackCheck(id, p "Tog", h, runtime)
                this._FormalTrackEditCombo(id, p "Name", h, runtime)
                this._FormalTrackCombo(id, p "Cmp", h, runtime)
                this._FormalTrackEditCombo(id, p "Var", h, runtime)
            }
            this._FormalTrackCheck(id, "IfSaveTog", h, runtime)
            this._FormalTrackEditCombo(id, "IfSaveName", h, runtime)
            this._FormalTrackField(id, "IfTrueVal", h, runtime)
            this._FormalTrackField(id, "IfFalseVal", h, runtime)
            this._BindCtrl("IfInlineTExpand_" id, "Click", this._OnIfInlineChipsToggle.Bind(this, id, true), runtime)
            this._BindCtrl("IfInlineFExpand_" id, "Click", this._OnIfInlineChipsToggle.Bind(this, id, false), runtime)
            ; 折叠真/假分支（与搜索共用 _OnToggleFold，会记忆展开/收起后继相对位置）
            this._BindCtrl("SFold_" id, "Click", this._OnToggleFold.Bind(this, id), runtime)
        } else if (t == GetLang("如果Pro")) {
            h := this._OnFormalIfPro.Bind(this, id)
            data := this._IfProData(id)
            if (data != "") {
                cc := this._IfProCaseCountFromData(data)
                loop cc {
                    ci := A_Index
                    p := "IfProC" ci
                    this._FormalTrackCombo(id, p "LogicCmb", h, runtime)
                    loop 4 {
                        slot := A_Index
                        ps := p "S" slot
                        this._FormalTrackCheck(id, ps "Tog", h, runtime)
                        this._FormalTrackEditCombo(id, ps "Name", h, runtime)
                        this._FormalTrackCombo(id, ps "Cmp", h, runtime)
                        this._FormalTrackEditCombo(id, ps "Var", h, runtime)
                    }
                }
                count := this._IfProBranchCountFromData(data)
                loop count {
                    idx := A_Index - 1
                    this._BindCtrl("IfProInline" idx "Expand_" id, "Click", this._OnIfProInlineChipsToggle.Bind(this, id, idx), runtime)
                }
            }
            this._BindCtrl("SFold_" id, "Click", this._OnToggleIfProFold.Bind(this, id), runtime)
        }
    }
}

_GraftMacroGraphMixin(MacroGraphFormalMixin)