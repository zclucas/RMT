#Requires AutoHotkey v2.0

; =====================================================================
; MacroEditGui 的 XAML 迁移基础：节点模型 + 原生 TreeView 兼容适配器
;
; 思路：MacroEditGui 约 1800 行逻辑直接调用原生 AHK TreeView API
; （Add/Delete/Modify/GetText/GetParent/GetChild/GetNext/GetPrev），
; 用 MacroTreeAdapter 把这些调用翻译到内存节点树（MacroEditNode），
; 视图用 WPF TreeView 全量重建 + SelectByTag 恢复选中，从而让现有
; 逻辑层基本原样保留。
;
; ponytail: 全量重建（宏体量千条内无感），后续若超大宏卡顿再改增量。
; =====================================================================

class MacroEditNode {
    __New(id, text, icon, parent := "") {
        this.id := id
        this.text := text          ; 显示文本（含 ⭐/🚫/→/⎖ 前缀）
        this.icon := icon          ; 图标文件绝对路径（/ 分隔）
        this.parent := parent
        this.children := []
        this.checked := false      ; 多选标记
        this.expanded := true      ; 展开状态
    }
}

class MacroTreeAdapter {
    __New(ui, treeName) {
        this.ui := ui
        this.treeName := treeName
        this.nodes := Map()        ; id → MacroEditNode
        this.roots := []           ; 根节点数组
        this._seq := 0
        this._redrawSuspended := false
        this._visible := false
        this._iconMap := Map()     ; "IconN" → 文件路径（兼容旧调用）
        this._events := Map()      ; 事件名 → 回调（右键/双击，P5 接线）
        this._renderCause := ""    ; 临时诊断
        this._suppressRender := false  ; 拖拽期间禁止全量重建
    }

    Hwnd {
        get => (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.treeName, "Visibility", value ? "Visible" : "Collapsed")
        }
    }

    SetImageList(id) {
        ; 图标嵌入节点 Header，图片列表无用
    }

    SetIconMap(iconMap) {
        this._iconMap := iconMap
    }

    Opt(options) {
        if (InStr(options, "-Redraw"))
            this._redrawSuspended := true
        else if (InStr(options, "+Redraw")) {
            this._redrawSuspended := false
            this._renderCause := "Opt+Redraw"
            this.Render()
        }
    }

    Focus() {
        if (IsObject(this.ui))
            this.ui.Update(this.treeName, "Focus", "True")
    }

    OnEvent(event, callback) {
        this._events[event] := callback
    }

    ; ---------------- 遍历（id 为节点 id 字符串；0 表示根） ----------------

    GetParent(id) {
        if (id == 0)
            return 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return (node && node.parent) ? node.parent.id : 0
    }

    GetChild(id) {
        if (id == 0)
            return this.roots.Length ? this.roots[1].id : 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return (node && node.children.Length) ? node.children[1].id : 0
    }

    GetNext(id) {
        if (id == 0)
            return this.roots.Length ? this.roots[1].id : 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        if (!node)
            return 0
        siblings := node.parent ? node.parent.children : this.roots
        i := this._IndexOf(siblings, node.id)
        return (i > 0 && i < siblings.Length) ? siblings[i + 1].id : 0
    }

    GetPrev(id) {
        if (id == 0)
            return 0
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        if (!node)
            return 0
        siblings := node.parent ? node.parent.children : this.roots
        i := this._IndexOf(siblings, node.id)
        return i > 1 ? siblings[i - 1].id : 0
    }

    GetText(id) {
        if (id == 0)
            return ""
        node := this.nodes.Has(id) ? this.nodes[id] : ""
        return node ? node.text : ""
    }

    GetCount() {
        count := 0
        for node in this.roots
            count += this._CountChildren(node)
        return count
    }

    IsExpanded(id) {
        if (id == 0 || !this.nodes.Has(id))
            return false
        return this.nodes[id].expanded
    }

    ; ---------------- 修改 ----------------

    Modify(id, options := "", newText := "") {
        if (id == 0 || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        needsRender := false
        if (newText != "" && node.text != newText) {
            node.text := newText
            ; 增量更新文本块，不整树重建
            if (IsObject(this.ui))
                this.ui.Update("Txt_" id, "Text", newText)
        }
        ; 勾选只更新 ✓ 标记，不触发全量重渲染（避免点击闪烁/覆盖折叠）
        if (InStr(options, "Check") && !node.checked) {
            node.checked := true
            this._UpdateCheckMark(id)
        } else if (InStr(options, "-Check") && node.checked) {
            node.checked := false
            this._UpdateCheckMark(id)
        }
        if (InStr(options, "Expand") && !node.expanded) {
            node.expanded := true
            needsRender := true
        } else if (InStr(options, "Collapse") && node.expanded) {
            node.expanded := false
            needsRender := true
        }
        if (InStr(options, "Select"))
            this._Select(id)
        if (needsRender && !this._redrawSuspended) {
            this._renderCause := "Modify:" options
            this.Render()
        }
    }

    ; 更新单个节点的勾选标记（不重渲染，两种图标同尺寸占位）
    _UpdateCheckMark(id) {
        if (!IsObject(this.ui) || !this.nodes.Has(id))
            return
        checked := this.nodes[id].checked
        this.ui.Update("ChkMark_" id, "Background", checked ? "#2D6CDF" : "Transparent")
        this.ui.Update("ChkMark_" id, "BorderBrush", checked ? "#2D6CDF" : "#999999")
        this.ui.Update("ChkMark_" id "_Txt", "Text", checked ? Chr(0x2713) : "")
    }

    _Select(id) {
        if (IsObject(this.ui))
            this.ui.Update(this.treeName, "SelectByTag", id)
    }

    ; ---------------- 添加 ----------------

    Add(text, parentID := 0, options := "") {
        opts := StrSplit(Trim(options), A_Space)
        insertBefore := false
        insertAfterId := ""
        icon := ""
        for token in opts {
            if (token == "First")
                insertBefore := true
            else if (token != "" && this.nodes.Has(token))
                insertAfterId := token
            else if (token != "")
                icon := this._ResolveIcon(token)
        }
        this._seq += 1
        id := "n" this._seq
        node := MacroEditNode(id, text, icon)
        this.nodes[id] := node
        ; 父节点由叶变父（0→1 子）需补展开箭头，整树重建一次；其余增量插入
        parentWasLeaf := (parentID != 0 && this.nodes.Has(parentID) && this.nodes[parentID].children.Length == 0)
        if (parentID != 0 && this.nodes.Has(parentID)) {
            node.parent := this.nodes[parentID]
            this._InsertInto(node.parent.children, node, insertBefore, insertAfterId)
        } else {
            this._InsertInto(this.roots, node, insertBefore, insertAfterId)
        }
        if (!this._redrawSuspended) {
            if (parentWasLeaf)
                this._UpdateArrow(parentID)
            if (this._IsVisible(node)) {
                idx := this._FlatIndexOf(id)
                if (idx >= 0)
                    this.ui.Update(this.treeName, "InsertXamlItem", idx "|" this._BuildCardXml(node, this._Depth(node), idx))
                else
                    this.Render()
            }
        }
        return id
    }

    _InsertInto(arr, node, insertBefore, insertAfterId) {
        if (insertBefore) {
            arr.InsertAt(1, node)
            return
        }
        if (insertAfterId != "") {
            for i, n in arr
                if (n.id == insertAfterId) {
                    arr.InsertAt(i + 1, node)
                    return
                }
        }
        arr.Push(node)
    }

    _ResolveIcon(token) {
        return this._iconMap.Has(token) ? this._iconMap[token] : token
    }

    ; ---------------- 删除 ----------------

    Delete(id := "") {
        ; 原生 Delete() 无参 = 清空整棵
        if (id == "") {
            this.nodes := Map()
            this.roots := []
            if (!this._redrawSuspended) {
                this._renderCause := "Delete-all"
                this.Render()
            }
            return
        }
        if (!this.nodes.Has(id))
            return
        node := this.nodes[id]
        ; 先收集可见卡片 id（改模型前），删单个节点时增量移除，避免整树重建
        visibleIds := []
        if (this._IsVisible(node))
            this._CollectVisibleIds(node, &visibleIds)
        ; 父节点由父变叶（1→0 子）需去箭头，整树重建一次
        parentBecomesLeaf := (node.parent && node.parent.children.Length == 1)
        if (node.parent) {
            arr := node.parent.children
            for i, n in arr
                if (n.id == id) {
                    arr.RemoveAt(i)
                    break
                }
        } else {
            for i, n in this.roots
                if (n.id == id) {
                    this.roots.RemoveAt(i)
                    break
                }
        }
        this._RemoveRecursive(node)
        if (!this._redrawSuspended) {
            if (parentBecomesLeaf && node.parent)
                this._UpdateArrow(node.parent.id)
            for vid in visibleIds
                this.ui.Update(this.treeName, "RemoveItem", vid)
        }
    }

    _RemoveRecursive(node) {
        for child in node.children
            this._RemoveRecursive(child)
        this.nodes.Delete(node.id)
    }

    ; ---------------- 渲染 ----------------

    Render() {
        if (!IsObject(this.ui) || this._redrawSuspended || this._suppressRender)
            return
        this._renderCause := ""
        this.ui.Update(this.treeName, "ClearItems", "")
        ; 展平为可见节点（仅展开分支），深度=缩进
        cards := []
        for root in this.roots
            this._AppendVisibleCards(root, 0, &cards)
        ; 批量推送卡片：逐条 Update 是 N 次同步 IPC 往返（千条级宏打开/刷新卡顿元凶），
        ; 合并为少量 BatchUpdate 分块（WM_COPYDATA 单消息体量限制，按字节分块），一次往返处理多条。
        this._BatchPushCards(cards)
    }

    ; 分块批量推送 AddXamlItem：单块控制在 ~36KB 以内（含 UTF-8 中文 3 字节/字），
    ; 单次 WM_COPYDATA 安全上限 64KB，留足余量避免大宏超限丢消息。
    _BatchPushCards(cards) {
        if (cards.Length == 0)
            return
        chunk := []
        chunkBytes := 0
        maxBytes := 36000
        for xml in cards {
            if (xml == "")
                continue
            chunk.Push({ControlName: this.treeName, PropertyName: "AddXamlItem", Value: xml})
            chunkBytes += StrPut(xml, "UTF-8") - 1
            if (chunkBytes >= maxBytes) {
                if (chunk.Length > 0)
                    this.ui.BatchUpdate(chunk)
                chunk := []
                chunkBytes := 0
            }
        }
        if (chunk.Length > 0)
            this.ui.BatchUpdate(chunk)
    }

    ; 递归收集可见节点卡片（塌陷分支不进入）
    _AppendVisibleCards(node, depth, &cards) {
        cards.Push(this._BuildCardXml(node, depth, cards.Length))
        if (!node.expanded)
            return
        for child in node.children
            this._AppendVisibleCards(child, depth + 1, &cards)
    }

    _BuildCardXml(node, depth, flatIdx := 0) {
        text := this._EscapeXml(node.text)
        hasChild := node.children.Length > 0
        left := depth * 16
        ; 展开箭头：恒占位（叶子空字），命名 Arrow_<id> 供命中测试；叶↔父转换只改文字，不重建
        glyph := hasChild ? (node.expanded ? Chr(0x25BC) : Chr(0x25B6)) : ""
        arrow := '<Border Name="Arrow_' node.id '" Width="14" Height="14" Margin="0,0,2,0" Background="Transparent">'
            . '<TextBlock Name="Arrow_' node.id '_Txt" Text="' glyph '" FontSize="8" Foreground="{DynamicResource TextSub}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
        ; 卡片：圆角 + 描边 + 底，左缩进=深度；缩进放内层 Border 的 Margin（ListBoxItem 不设 Margin，保证整行命中无死区）
        ; §14.1 交替背景：按可见扁平索引奇偶在两色间交替，便于区分相邻节点（ListAltBg 为主题随动斑马纹）
        ; AHK v2 无 mod 运算符（v1 才有），必须用 Mod() 函数；
        ; 裸写 `flatIdx mod 2` 会被解析成拼接，mod 求值为 Mod 函数对象 → 报 "Expected a String but got a Func"
        cardBg := (Mod(flatIdx, 2) == 0) ? "{DynamicResource DropdownBg}" : "{DynamicResource ListAltBg}"
        xml := '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
            . ' Tag="' node.id '" Background="Transparent" BorderThickness="0" Padding="0" HorizontalContentAlignment="Stretch">'
            . '<Border CornerRadius="6" BorderThickness="1" BorderBrush="{DynamicResource InputStroke}" Background="' cardBg '" Margin="' left ',3,8,3" Padding="6,5,8,5">'
            . '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
        xml .= arrow
        ; 勾选标记：选中=蓝底白✓，未选中=灰色空心框。两种图标同尺寸始终占位，避免行内容移位
        xml .= '<Border Name="ChkMark_' node.id '" Width="14" Height="14" CornerRadius="2" Margin="0,0,4,0"'
            . ' BorderBrush="' (node.checked ? "#2D6CDF" : "#999999") '" BorderThickness="1"'
            . ' Background="' (node.checked ? "#2D6CDF" : "Transparent") '">'
            . '<TextBlock Name="ChkMark_' node.id '_Txt" Text="' (node.checked ? Chr(0x2713) : "") '" Foreground="White" FontSize="9" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>'
        if (node.icon != "")
            xml .= '<Image Source="' this._EscapeXml(node.icon) '" Width="16" Height="16" Margin="0,0,4,0"/>'
        xml .= '<TextBlock Name="Txt_' node.id '" Text="' text '" VerticalAlignment="Center"/>'
        xml .= '</StackPanel>'
        xml .= '</Border>'
        xml .= '</ListBoxItem>'
        return xml
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    _IndexOf(arr, id) {
        for i, n in arr
            if (n.id == id)
                return i
        return 0
    }

    _CountChildren(node) {
        c := 1
        for child in node.children
            c += this._CountChildren(child)
        return c
    }

    ; ---------------- 增量渲染辅助 ----------------

    ; 节点是否可见（所有祖先均展开；根节点恒可见）
    _IsVisible(node) {
        p := node.parent
        while (p) {
            if (!p.expanded)
                return false
            p := p.parent
        }
        return true
    }

    ; 节点深度（根=0），决定卡片左缩进
    _Depth(node) {
        d := 0
        p := node.parent
        while (p) {
            d += 1
            p := p.parent
        }
        return d
    }

    ; 节点在扁平可见列表中的索引（与 Render 展平顺序一致），不可见/不存在返回 -1
    _FlatIndexOf(id) {
        idx := 0
        found := -1
        for node in this.roots
            this._WalkFlatIndex(node, &idx, id, &found)
        return found
    }

    _WalkFlatIndex(node, &idx, targetId, &found) {
        if (found >= 0)
            return
        if (node.id == targetId) {
            found := idx
            return
        }
        idx += 1
        if (node.expanded)
            for child in node.children
                this._WalkFlatIndex(child, &idx, targetId, &found)
    }

    ; 收集节点及其可见后代的 id（展平顺序，用于增量移除）
    _CollectVisibleIds(node, &arr) {
        arr.Push(node.id)
        if (node.expanded)
            for child in node.children
                this._CollectVisibleIds(child, &arr)
    }

    ; 更新节点展开箭头文字（叶↔父转换时增量改，不重建）
    _UpdateArrow(id) {
        if (!IsObject(this.ui) || !this.nodes.Has(id))
            return
        node := this.nodes[id]
        hasChild := node.children.Length > 0
        glyph := hasChild ? (node.expanded ? Chr(0x25BC) : Chr(0x25B6)) : ""
        this.ui.Update("Arrow_" id "_Txt", "Text", glyph)
    }
}

; ---------------- 其它控件兼容适配器 ----------------

class MacroTextBox {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._visible := false
    }

    Hwnd {
        get => (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Visibility", value ? "Visible" : "Collapsed")
        }
    }

    Value {
        get => IsObject(this.ui) ? this.ui.Query(this.name) : ""
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Text", value)
        }
    }

    ScrollToEnd() {
        if (IsObject(this.ui))
            this.ui.Update(this.name, "ScrollToEnd", "")
    }
}

class MacroCombo {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._value := 1
    }

    Value {
        get => this._value
        set {
            this._value := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "SelectedIndex", String(value - 1))
        }
    }
}

class MacroCheckBox {
    __New(ui, name) {
        this.ui := ui
        this.name := name
    }

    Value {
        get => (IsObject(this.ui) && this.ui.Query(this.name) == "True")
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.name, "IsChecked", value ? "True" : "False")
        }
    }
}

class MacroButton {
    __New(ui, name) {
        this.ui := ui
        this.name := name
        this._visible := true
    }

    Visible {
        get => this._visible
        set {
            this._visible := value
            if (IsObject(this.ui))
                this.ui.Update(this.name, "Visibility", value ? "Visible" : "Collapsed")
        }
    }
}

; 菜单适配：MenuHandler 仍调用 ToolMenu.Check/Uncheck/ToggleCheck，
; 映射到 WPF MenuItem.IsChecked。IsChecked 状态在 AHK 侧维护，避免回调内 Query。
class MacroMenuAdapter {
    __New(ui) {
        this.ui := ui
        this._checked := Map()
        this._nameMap := Map(
            GetLang("变量监视"), "MenuVarListen",
            GetLang("指令显示"), "MenuCmdTip",
            GetLang("窗口置顶"), "MenuTopMost"
        )
    }

    _Name(name) => this._nameMap.Has(name) ? this._nameMap[name] : ""

    Check(name) {
        this._checked[name] := true
        if (IsObject(this.ui) && this._Name(name) != "")
            this.ui.Update(this._Name(name), "IsChecked", "True")
    }

    Uncheck(name) {
        this._checked[name] := false
        if (IsObject(this.ui) && this._Name(name) != "")
            this.ui.Update(this._Name(name), "IsChecked", "False")
    }

    ToggleCheck(name) {
        cur := this._checked.Has(name) ? this._checked[name] : false
        cur ? this.Uncheck(name) : this.Check(name)
    }
}

; 值桥接：把 XAML 控件包装成带 .Value 读写的对象，供原生 GUI（如 FrontInfoGui）读写
class XamlValueBridge {
    __New(ui, ctrlName) {
        this.ui := ui
        this.ctrlName := ctrlName
    }

    Value {
        get => IsObject(this.ui) ? this.ui.Query(this.ctrlName) : ""
        set {
            if (IsObject(this.ui))
                this.ui.Update(this.ctrlName, "Text", value)
        }
    }
}

; 兼容外部对 .Gui.Hwnd / .Gui.Title / .Gui.Hide 的调用
class MacroEditGuiFacade {
    __New(owner) {
        this._owner := owner
    }

    Hwnd {
        get => (IsObject(this._owner.ui) && this._owner.ui.HasProp("wpfHwnd")) ? this._owner.ui.wpfHwnd : 0
    }

    Title {
        get => this._owner._title
    }

    Hide() {
        this._owner._HideWindow()
    }
}
