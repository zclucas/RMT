#Requires AutoHotkey v2.0

; ===========================================================================
; 界面宏 · 字段挑选器
;
; 设计器点「挑选器」弹出。树形列出「宏 → 步骤 → 可绑字段」，支持嵌套宏
; （如果Pro 真假分支 / 循环体）递归展开（深度上限 = UIMacroStepBinding.MaxHops，
; 循环引用由 NormalizeHops 的规格化兜底——超深/成环的路径直接丢弃）。
;
; 重新绑定时定位当前目标；创建模式下可选字段并生成新控件。
;
; 用 ListBox + 缩进而非 TreeView： ListBox 子项是运行期字符串（ClearItems/
; AddItem），缩进可控、选中索引可直接 Query，事件面最小。
; ===========================================================================
class UIMacroFieldPicker {
    static instance := ""

    _closed := false
    _tableItem := ""
    _designer := ""
    _macroTypeTables := []
    _macroTypeIdx := -1
    _macroIds := []
    _rows := []          ; 与 FieldList 行一一对应：{ selectable, node }
    _macroId := ""       ; 当前展示的宏
    _treeNodes := []     ; 当前宏的绑定树（展开收起时复用，不重算）
    _nodeState := Map()  ; 节点展开状态（键=节点对象）
    _choiceNode := ""    ; 控件类型下拉当前对应的叶子
    _macroIdx := 0       ; 宏下拉默认选中下标（ui 创建后补设）
    _mode := "rebind"    ; rebind / create
    _currentBinding := ""
    _actionMacroId := ""
    _pendingNode := ""
    _locateTip := ""
    _loading := false

    ; ---- 入口 ----
    ; tableItem: UI 表对象；ctrl: 重新绑定目标控件；designer: 调用方实例
    static Show(tableItem, macroId, ctrl, designer, mode := "rebind") {
        if (IsObject(UIMacroFieldPicker.instance) && !UIMacroFieldPicker.instance._closed) {
            picker := UIMacroFieldPicker.instance
            picker._SetContext(tableItem, macroId, ctrl, designer, true, mode)
            hwnd := (IsObject(picker.ui) && picker.ui.HasProp("wpfHwnd")) ? picker.ui.wpfHwnd : 0
            if (hwnd)
                try WinActivate("ahk_id " hwnd)
            return
        }
        inst := UIMacroFieldPicker()
        inst._SetContext(tableItem, macroId, ctrl, designer, false, mode)
        inst._Build()
        UIMacroFieldPicker.instance := inst
    }

    _SetContext(tableItem, macroId, ctrl, designer, refresh := true, mode := "rebind") {
        this._tableItem := tableItem
        this._designer := designer
        this._mode := mode == "create" ? "create" : "rebind"
        this._currentBinding := (IsObject(ctrl) && ctrl.HasProp("binding")
            && IsObject(ctrl.binding)) ? ctrl.binding : ""
        this._actionMacroId := (IsObject(ctrl) && ctrl.HasProp("action") && IsObject(ctrl.action)
            && ctrl.action.HasProp("macroId")) ? String(ctrl.action.macroId) : ""
        this._macroId := (IsObject(this._currentBinding) && this._currentBinding.HasProp("macroId"))
            ? String(this._currentBinding.macroId)
            : (this._actionMacroId != "" ? this._actionMacroId : String(macroId))
        if (this._macroId != "") {
            sourceTable := ""
            try sourceTable := GetItemTableGlobal(this._macroId)
            if (IsObject(sourceTable))
                this._tableItem := sourceTable
        }
        this._nodeState := Map()
        this._choiceNode := ""
        this._pendingNode := ""
        this._locateTip := ""
        if (refresh && IsObject(this.ui)) {
            try this.ui.Update("BtnApply", "Content", this._ApplyButtonText())
            wasLoading := this._loading
            this._loading := true
            try {
                typeIdx := this._MacroTypeComboIndex(this._tableItem)
                this._macroTypeIdx := typeIdx
                this.ui.Update("MacroTypeCon", "SelectedIndex", String(typeIdx))
                this._ReloadMacroCombo(this._macroId)
            } catch {
            } finally {
                this._loading := wasLoading
            }
            this._ReloadFieldList()
        }
    }

    _ApplyButtonText() {
        return this._mode == "create" ? "生成控件" : "重新绑定"
    }

    _Build() {
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows("30", "78", "*", "50")

        XAMLHost.AddTitleBar(main, "挑选器", "30")

        ; ---- 宏来源 ----
        source := main.Add("Border").Grid_Row(1).Margin("12,6,12,6")
            .Padding("8,4").CornerRadius("4")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        sourceGrid := source.Add("Grid").Rows("20", "34").Cols("140", "220", "*")
        sourceGrid.Add("TextBlock").Grid_Row(0).Grid_Column(0).Text("宏类型").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        sourceGrid.Add("TextBlock").Grid_Row(0).Grid_Column(1).Text("宏").FontSize("11")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextSub}")
        mtc := sourceGrid.Add("ComboBox").Name("MacroTypeCon").Grid_Row(1).Grid_Column(0)
            .Width(132).Height(28).MinHeight(28).Margin("0,6,0,0")
            .HorizontalAlignment("Left")
            .VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        this._FillMacroTypeCombo(mtc)
        mc := sourceGrid.Add("ComboBox").Name("MacroCon").Grid_Row(1)
            .Grid_Column(1)
            .Width(210).Height(28).MinHeight(28).Margin("0,6,0,0")
            .HorizontalAlignment("Left")
            .VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        initialTable := this._MacroTypeTableAt(this._macroTypeIdx)
        this._FillMacroCombo(mc, initialTable, this._macroId)

        ; ---- 字段树 ----
        listArea := main.Add("Grid").Grid_Row(2).Margin("12,6,12,6")
        listArea.Rows("20", "*")
        listArea.Add("TextBlock").Grid_Row(0).Text("可绑定项").FontSize("11")
            .VerticalAlignment("Center")
            .Foreground("{DynamicResource TextSub}")
        listArea.Add("ListBox").Name("FieldList").Grid_Row(1)
            .Margin("0,6,0,0").Padding("4,2")
            .FontSize("12")
            .Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

        ; ---- 底部控件类型与操作 ----
        bottom := main.Add("Grid").Grid_Row(3).Margin("12,6,12,12")
        bottom.Rows("32")
        bottom.Cols("Auto", "*", "Auto")
        typeRow := bottom.Add("StackPanel").Grid_Column(0).Orientation("Horizontal")
            .VerticalAlignment("Center")
        typeRow.Add("TextBlock").Text("控件类型")
            .FontSize("11").VerticalAlignment("Center").Margin("0,0,8,0")
            .Foreground("{DynamicResource TextSub}")
        typeRow.Add("ComboBox").Name("CtrlTypeCon").Width(128)
            .Height(28).MinHeight(28).VerticalContentAlignment("Center")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        bottom.Add("TextBlock").Name("TipText").Grid_Column(1)
            .Text("").VerticalAlignment("Center").FontSize("10")
            .Foreground("{DynamicResource TextSub}").TextTrimming("CharacterEllipsis")
        btnBar := bottom.Add("StackPanel").Grid_Column(2)
            .Orientation("Horizontal").HorizontalAlignment("Right")
            .VerticalAlignment("Center")
        br := btnBar.Add("Button").Name("BtnApply").Content(this._ApplyButtonText())
            .Width(92).Height(30).MinHeight(30).Margin("0,0,8,0")
            .FontSize("12").Padding("10,0").Cursor("Hand")
            .Foreground("{DynamicResource ActionText}")
            .Background("{DynamicResource ActionBg}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        bc := btnBar.Add("Button").Name("BtnCancel").Content("取消")
            .Width(68).Height(30).MinHeight(30)
            .FontSize("12").Padding("10,0").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}")
            .Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        try br.InjectResources(UIMacroRenderer.BtnStyle)

        main.Add("Border").Grid_Row(0).Grid_RowSpan(4)
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .CornerRadius("4").IsHitTestVisible("False").SetProp("Panel.ZIndex", "1000")

        ; ---- 宿主 ----
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="挑选器" Width="560" Height="620"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"'
            , 'CornerRadius="4"')
        this.ui.xaml := StrReplace(this.ui.xaml, '<CornerRadius x:Key="CloseBtnRadius">0,8,0,0</CornerRadius>'
            , '<CornerRadius x:Key="CloseBtnRadius">0,4,0,0</CornerRadius>')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')
        this.ui.xaml := StrReplace(this.ui.xaml, '%components%', '')

        ; ---- 事件 ----
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "_OnCancel"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "_OnCancel"))
        this.ui.OnEvent("BtnCancel", "Click", ObjBindMethod(this, "_OnCancel"))
        this.ui.OnEvent("BtnApply", "Click", ObjBindMethod(this, "_OnApply"))
        this.ui.OnEvent("MacroTypeCon", "SelectionChanged", ObjBindMethod(this, "_OnMacroTypeChanged"))
        this.ui.OnEvent("MacroCon", "SelectionChanged", ObjBindMethod(this, "_OnMacroChanged"))
        this.ui.OnEvent("FieldList", "SelectionChanged", ObjBindMethod(this, "_OnListSel"))

        ; 初始化期间忽略窗口加载和设置默认选择产生的 SelectionChanged。
        wasLoading := this._loading
        this._loading := true
        try {
            try AppThemeUtil.ApplyWinThemeToXaml(this.ui)
            this.ui.Show()
            this.ui.Update("MacroTypeCon", "SelectedIndex", String(this._macroTypeIdx))
            this.ui.Update("MacroCon", "SelectedIndex", String(this._macroIdx))
        } catch {
        } finally {
            this._loading := wasLoading
        }
        ; 首次填充字段列表
        this._ReloadFieldList()
    }

    ; ---- 宏选择 ----
    _FillMacroTypeCombo(combo) {
        global MySoftData
        this._macroTypeTables := []
        if (!IsObject(MySoftData) || !MySoftData.HasProp("TableInfo"))
            return
        for tableItem in MySoftData.TableInfo {
            tableIndex := GetTableIndexByID(tableItem.ID)
            if (!tableIndex || !CheckIsMacroTable(tableIndex) || !tableItem.HasProp("Items"))
                continue
            this._macroTypeTables.Push(tableItem)
            combo.Add("ComboBoxItem").Content(UIMacroFieldPicker._MacroTypeLabel(tableItem))
        }
        this._macroTypeIdx := this._MacroTypeComboIndex(this._tableItem)
    }

    _MacroTypeComboIndex(tableItem) {
        if (IsObject(tableItem) && tableItem.HasProp("ID")) {
            for i, candidate in this._macroTypeTables {
                if (candidate.HasProp("ID") && String(candidate.ID) == String(tableItem.ID))
                    return i - 1
            }
        }
        return this._macroTypeTables.Length > 0 ? 0 : -1
    }

    _MacroTypeTableAt(index) {
        return (index >= 0 && index + 1 <= this._macroTypeTables.Length)
            ? this._macroTypeTables[index + 1] : ""
    }

    _MacroItems(tableItem) {
        items := []
        if (!IsObject(tableItem) || !tableItem.HasProp("Items"))
            return items
        itemIndex := 0
        for item in tableItem.Items {
            itemIndex += 1
            if (!item.HasProp("ID") || String(item.ID) == "")
                continue
            remark := item.HasProp("Remark") ? Trim(String(item.Remark)) : ""
            label := String(itemIndex)
            if (remark != "")
                label .= ". " remark
            items.Push({ id: String(item.ID), label: label })
        }
        return items
    }

    _FillMacroCombo(combo, tableItem, macroId) {
        combo.Add("ComboBoxItem").Content("（请选择宏）")
        this._macroIds := []
        for item in this._MacroItems(tableItem) {
            this._macroIds.Push(item.id)
            combo.Add("ComboBoxItem").Content(item.label)
        }
        this._macroIdx := this._MacroComboIndex(macroId)
    }

    _ReloadMacroCombo(macroId := "") {
        wasLoading := this._loading
        this._loading := true
        try {
            this.ui.Update("MacroCon", "ClearItems", "")
            this.ui.Update("MacroCon", "AddItem", "（请选择宏）")
            this._macroIds := []
            for item in this._MacroItems(this._tableItem) {
                this._macroIds.Push(item.id)
                this.ui.Update("MacroCon", "AddItem", item.label)
            }
            this._macroIdx := this._MacroComboIndex(macroId)
            this.ui.Update("MacroCon", "SelectedIndex", String(this._macroIdx))
        } catch {
        } finally {
            this._loading := wasLoading
        }
    }

    static _MacroTypeLabel(tableItem) {
        symbol := tableItem.HasProp("Symbol") ? String(tableItem.Symbol) : ""
        for def in CreateDefaultTableDefs() {
            if (String(def[1]) == symbol)
                return GetLang(String(def[2]))
        }
        name := tableItem.HasProp("Name") ? Trim(GetLang(String(tableItem.Name))) : ""
        return name != "" ? name : (symbol != "" ? symbol : "宏")
    }

    _MacroComboIndex(macroId) {
        if (macroId != "") {
            for i, id in this._macroIds {
                if (String(id) == String(macroId))
                    return i
            }
        }
        return 0
    }

    _OnMacroTypeChanged(*) {
        if (this._closed || this._loading)
            return
        idx := -1
        try idx := Integer(this.ui.Query("MacroTypeCon>SelectedIndex"))
        tableItem := this._MacroTypeTableAt(idx)
        if (IsObject(tableItem) && IsObject(this._tableItem)
            && tableItem.HasProp("ID") && this._tableItem.HasProp("ID")
            && String(tableItem.ID) == String(this._tableItem.ID))
            return
        this._macroTypeIdx := idx
        this._tableItem := tableItem
        this._macroId := ""
        this._currentBinding := ""
        this._actionMacroId := ""
        this._ReloadMacroCombo()
        this._ReloadFieldList()
    }

    _OnMacroChanged(*) {
        if (this._closed || this._loading)
            return
        idx := 0
        try idx := Integer(this.ui.Query("MacroCon>SelectedIndex"))
        selectedMacroId := (idx >= 1 && idx <= this._macroIds.Length)
            ? String(this._macroIds[idx]) : ""
        if (selectedMacroId == this._macroId)
            return
        this._macroId := selectedMacroId
        this._currentBinding := ""
        this._actionMacroId := ""
        this._ReloadFieldList()
    }

    ; ---- 字段列表（树 → 缩进行） ----
    _ReloadFieldList() {
        wasLoading := this._loading
        this._loading := true
        try {
            batch := [{ ControlName: "FieldList", PropertyName: "ClearItems", Value: "" }]
            this._rows := []
            this._treeNodes := []
            this._nodeState := Map()
            this._pendingNode := ""
            this._locateTip := ""
            if (this._macroId == "") {
                batch.Push({ ControlName: "FieldList", PropertyName: "AddItem", Value: "（请先在上方选择宏）" })
                this._PushRow(false, "")
            } else {
                item := UIMacroStepBinding.FindMacroItem(this._tableItem, this._macroId)
                if (!IsObject(item)) {
                    batch.Push({ ControlName: "FieldList", PropertyName: "AddItem", Value: "（宏不存在，请刷新）" })
                    this._PushRow(false, "")
                } else {
                    this._treeNodes := UIMacroStepBinding.BuildTree(item)
                    this._PrepareInitialSelection()
                    this._RenderAll(batch)
                }
            }
            selectedIndex := this._InitialRowIndex()
            batch.Push({ ControlName: "FieldList", PropertyName: "SelectedIndex"
                , Value: String(selectedIndex) })
            batch.Push({ ControlName: "CtrlTypeCon", PropertyName: "ClearItems", Value: "" })
            batch.Push({ ControlName: "TipText", PropertyName: "Text", Value: this._locateTip })
            this._FlushListBatch(batch)
            if (selectedIndex >= 0 && selectedIndex + 1 <= this._rows.Length)
                this._FillCtrlChoices(this._rows[selectedIndex + 1].node)
        } catch {
        } finally {
            this._loading := wasLoading
        }
    }

    _PrepareInitialSelection() {
        if (IsObject(this._currentBinding)) {
            hasPath := UIMacroFieldPicker._HasHops(this._currentBinding)
            matches := []
            this._CollectBindingMatches(this._treeNodes, this._currentBinding, hasPath, [], matches)
            if (matches.Length == 1) {
                match := matches[1]
                this._pendingNode := match.node
                for parent in match.parents
                    this._nodeState[parent] := true
            } else if (matches.Length > 1) {
                this._locateTip := "当前绑定对应多个嵌套字段，请手动选择。"
            } else {
                this._locateTip := "当前绑定字段未找到，请选择其他字段重新绑定。"
            }
        } else if (this._actionMacroId != "" && this._actionMacroId == this._macroId) {
            this._pendingNode := ""
        }
    }

    _CollectBindingMatches(nodes, binding, hasPath, parents, matches) {
        for node in nodes {
            if (node.type == "leaf") {
                target := node.target
                applies := true
                if (String(target.mode) == "data") {
                    obj := UIMacroStepBinding.GetDataObj(target.serial)
                    applies := UIMacroStepBinding._FieldApplies(target.spec, obj)
                }
                if (!applies)
                    continue
                if (hasPath)
                    same := UIMacroStepBinding.TargetKey(target) == UIMacroStepBinding.BindingKey(binding)
                else
                    same := UIMacroFieldPicker._TargetBaseKey(target)
                        == UIMacroFieldPicker._TargetBaseKey(binding)
                if (same)
                    matches.Push({ node: node, parents: parents.Clone() })
                continue
            }
            if (node.HasProp("children") && IsObject(node.children)) {
                nextParents := parents.Clone()
                nextParents.Push(node)
                this._CollectBindingMatches(node.children, binding, hasPath, nextParents, matches)
            }
        }
    }

    static _HasHops(binding) {
        return (IsObject(binding) && binding.HasProp("hops")
            && IsObject(binding.hops) && binding.hops.Length > 0)
    }

    static _TargetBaseKey(target) {
        if (!IsObject(target))
            return ""
        mode := target.HasProp("mode") ? String(target.mode) : "step"
        if (mode == "data")
            return UIMacroStepBinding.DataBindingKeyOf(
                target.macroId, target.kind, target.serial, target.field)
        if (mode == "skip")
            return String(target.macroId) "|skip|" String(target.step)
        if (mode == "action")
            return String(target.macroId) "|action"
        return UIMacroStepBinding.BindingKeyOf(target.macroId, target.step, target.param)
    }

    _InitialRowIndex() {
        for i, row in this._rows {
            if (!row.selectable || !IsObject(row.node) || !row.node.HasProp("target"))
                continue
            target := row.node.target
            if (IsObject(this._pendingNode) && row.node == this._pendingNode)
                return i - 1
            if (!IsObject(this._currentBinding) && this._actionMacroId != ""
                && String(target.mode) == "action"
                && String(target.macroId) == this._actionMacroId)
                return i - 1
        }
        return -1
    }

    _PushRow(selectable, node) {
        this._rows.Push({ selectable: selectable, node: node })
    }

    ; 展开收起后只重渲染列表行（不动宏下拉、不清已选类型）
    _ReloadListRows(anchorNode := "") {
        this._loading := true
        try {
            batch := [{ ControlName: "FieldList", PropertyName: "ClearItems", Value: "" }]
            this._rows := []
            this._RenderAll(batch, anchorNode)
            batch.Push({ ControlName: "FieldList", PropertyName: "SelectedIndex", Value: "-1" })
            this._FlushListBatch(batch)
        } catch {
        }
        this._loading := false
    }

    ; 攒进 batch 而不是逐行 ui.Update：每行 AddItem 都是一次同步 IPC 往返，
    ; 整列表逐个发就是「展开/收起卡一下」的根因（项目里 AssetUtil:1159 同款教训）。
    ; 列表渲染入口：先放触发宏，再渲染步骤树。
    _RenderAll(batch, anchorNode := "") {
        if (this._macroId != "") {
            actionNode := { type: "leaf", label: "触发宏"
                , spec: { type: "action", label: "运行此宏" }
                , target: { mode: "action", macroId: this._macroId } }
            batch.Push({ ControlName: "FieldList", PropertyName: "AddItem"
                , Value: UIMacroFieldPicker._BatchText("▶ 触发宏") })
            this._PushRow(true, actionNode)
        }
        if (IsObject(this._treeNodes))
            this._RenderNodes(this._treeNodes, 0, batch, anchorNode)
    }

    _RenderNodes(nodes, indent, batch, anchorNode := "") {
        pad := ""
        loop indent
            pad .= "    "
        for n in nodes {
            if (n.type == "leaf") {
                t := n.target
                ; 数据字段按数据对象当前状态过滤（如搜索类型决定相似度/检索文本谁出现）
                if (String(t.mode) == "data") {
                    obj := UIMacroStepBinding.GetDataObj(t.serial)
                    if (!UIMacroStepBinding._FieldApplies(t.spec, obj))
                        continue
                }
                lbl := n.label
                if (n.spec.HasProp("typeNote") && n.spec.typeNote != "")
                    lbl .= "（" n.spec.typeNote "）"
                mark := ""
                key := UIMacroStepBinding.TargetKey(t)
                if (key != "" && this._designer != ""
                    && UIMacroStepBinding.IsOccupiedByKey(key, this._designer._foldKey, this._designer._foldIndex))
                    mark := "（已占用）"
                batch.Push({ ControlName: "FieldList", PropertyName: "AddItem"
                    , Value: UIMacroFieldPicker._BatchText(pad "· " lbl "  [" UIMacroFieldPicker._DefaultCtrlLabel(n.spec) "]" mark) })
                this._PushRow(true, n)
            } else {
                ; 步骤/分支：默认收起，定位现有字段时按需展开。
                open := this._NodeOpen(n)
                suffix := (n.HasProp("children") && n.children.Length == 0) ? "（空）" : ""
                if (IsObject(anchorNode) && n == anchorNode)
                    batch.Push({ ControlName: "FieldList", PropertyName: "SelectedIndex", Value: "-1" })
                batch.Push({ ControlName: "FieldList", PropertyName: "AddItem"
                    , Value: UIMacroFieldPicker._BatchText(pad (open ? "− " : "+ ") n.label suffix) })
                this._PushRow(false, n)
                if (open && n.HasProp("children") && IsObject(n.children))
                    this._RenderNodes(n.children, indent + 1, batch, anchorNode)
            }
        }
    }

    ; 批量消息协议是「控件|属性|值」+ 换行分隔：值里出现 | 或换行会被切错，
    ; 而宏文本/备注完全可能带这些字符。列表文本只用于显示，替换成全角/空格即可。
    static _BatchText(s) {
        t := String(s)
        t := StrReplace(t, "|", "｜")
        t := StrReplace(t, "`r", " ")
        t := StrReplace(t, "`n", " ")
        return t
    }

    ; 一次 BatchUpdate 发完整个列表（ClearItems + N×AddItem + SelectedIndex）
    _FlushListBatch(batch) {
        if (!IsObject(batch) || batch.Length == 0)
            return
        if (this.ui.HasMethod("BatchUpdate"))
            this.ui.BatchUpdate(batch)
        else {
            for e in batch
                this.ui.Update(e.ControlName, e.PropertyName, e.Value)
        }
    }

    ; 节点默认收起；定位已有绑定时会展开其父路径。
    _NodeOpen(n) {
        if (!IsObject(this._nodeState))
            this._nodeState := Map()
        if (this._nodeState.Has(n))
            return this._nodeState[n]
        ; 默认全部收起：一屏能看到整条宏的骨架，需要时再点开
        return false
    }

    _NodeToggle(n) {
        if (!IsObject(this._nodeState))
            this._nodeState := Map()
        this._nodeState[n] := !this._NodeOpen(n)
    }

    ; spec.type → 默认控件名
    static _DefaultCtrlLabel(spec) {
        if (!IsObject(spec))
            return "输入框"
        switch String(spec.type) {
            case "enum": return "下拉框"
            case "bool": return "勾选框"
            case "action": return "按钮"
        }
        return "输入框"
    }

    ; 某字段允许的控件类型（type 值 + 界面名）
    static _CtrlChoices(spec) {
        if (!IsObject(spec))
            return [{ type: "Edit", label: "输入框" }]
        switch String(spec.type) {
            case "action": return [{ type: "Button", label: "按钮" }]
            case "enum": return [{ type: "ComboBox", label: "下拉框" }, { type: "TextBlock", label: "只读文本" }]
            case "bool": return [{ type: "CheckBox", label: "勾选框" }, { type: "TextBlock", label: "只读文本" }]
        }
        return [{ type: "Edit", label: "输入框" }, { type: "TextBlock", label: "只读文本" }]
    }

    _OnListSel(*) {
        if (this._closed || this._loading)
            return
        idx := -1
        try idx := Integer(this.ui.Query("FieldList>SelectedIndex"))
        row := (idx >= 0 && idx + 1 <= this._rows.Length) ? this._rows[idx + 1] : ""
        if (!IsObject(row) || !row.selectable) {
            ; 步骤/分支标题行：点击 = 切换展开收起
            if (IsObject(row) && IsObject(row.node) && row.node.HasProp("children")) {
                if (row.node.children.Length == 0)
                    return      ; 空分支没有可展开内容，不做无谓的整体重渲染
                this._NodeToggle(row.node)
                this._ReloadListRows(row.node)
            }
            return
        }
        node := row.node
        if (!node.HasProp("target") || !IsObject(node.target))
            return
        this._FillCtrlChoices(node)
    }

    ; 按叶子重填控件类型；应用时会兜底调用，避免依赖列表事件。
    _FillCtrlChoices(node) {
        this._choiceNode := node
        wasLoading := this._loading
        this._loading := true
        try {
            this.ui.Update("CtrlTypeCon", "ClearItems", "")
            for c in UIMacroFieldPicker._CtrlChoices(node.spec)
                this.ui.Update("CtrlTypeCon", "AddItem", c.label)
            this.ui.Update("CtrlTypeCon", "SelectedIndex", "0")
            this.ui.Update("TipText", "Text", "")
        } catch {
        } finally {
            this._loading := wasLoading
        }
    }

    _ChosenCtrlType(spec) {
        idx := -1
        try idx := Integer(this.ui.Query("CtrlTypeCon>SelectedIndex"))
        choices := UIMacroFieldPicker._CtrlChoices(spec)
        if (idx >= 0 && idx + 1 <= choices.Length)
            return choices[idx + 1].type
        return choices[1].type
    }

    _Tip(text) {
        try this.ui.Update("TipText", "Text", text)
    }

    ; 根据打开方式将所选目标绑定到当前控件，或生成新的绑定控件。
    _OnApply(*) {
        if (this._closed)
            return
        idx := -1
        try idx := Integer(this.ui.Query("FieldList>SelectedIndex"))
        if (idx < 0 || idx + 1 > this._rows.Length) {
            this._Tip("请选择触发宏或字段")
            return
        }
        row := this._rows[idx + 1]
        if (!IsObject(row) || !row.selectable) {
            this._Tip("请选择字段")
            return
        }
        node := row.node
        if (!node.HasProp("target") || !IsObject(node.target)) {
            this._Tip("该字段没有可用的绑定目标")
            return
        }
        if (!this.HasProp("_choiceNode") || this._choiceNode != node)
            this._FillCtrlChoices(node)
        ctrlType := this._ChosenCtrlType(node.spec)
        if (!IsObject(this._designer)) {
            this._Tip("设计器已关闭")
            return
        }
        if (this._mode == "rebind" && this._designer._selId == "") {
            this._Tip("请先在画布上选中一个控件")
            return
        }
        newId := this._mode == "create"
            ? this._designer.CreateBoundControl(node.target, ctrlType)
            : this._designer.RebindSelected(node.target, ctrlType)
        if (newId != "")
            this._OnCancel()
    }

    _OnCancel(*) {
        if (this._closed)
            return
        this._closed := true
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (UIMacroFieldPicker.instance == this)
            UIMacroFieldPicker.instance := ""
    }
}
