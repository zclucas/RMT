#Requires AutoHotkey v2.0

; ===========================================================================
; 当前页控件列表
;
; 像 PS 图层那样列出当前页的控件：上层在上、下层在下。
;   · 点行       → 设计器选中该控件（画布选中框 + 属性同步）
;   · 按住拖到另一行 → 换序（画布立刻重画）
;   · 设计器里选中别的控件 → 本列表高亮实时跟随
;
; 为什么不用 ListBox：
;   1) 引擎没有「坐标 → 行号」的命中测试，ListBox 无法实现拖放落点判定；
;   2) StackPanel 的子项无法动态清空（ClearItems 只支持 ItemsControl）。
;   所以预建 MaxControls 个行（每行 Height 固定），刷新时只改文本/可见性，
;   每行各自绑鼠标按下/抬起事件——和设计器画布拖控件的做法一致。
; ===========================================================================
class UIMacroLayerGui {
    static instance := ""

    _closed := false
    _designer := ""
    _loading := false
    _ids := []          ; 可见行号 → 当前页控件 id
    _dragFrom := 0      ; 按下时的行号（0 = 没在拖）
    _hoverRow := 0      ; 拖动中鼠标所在行（画插入指示线用）
    _timerFn := ""      ; 存活检查定时器
    _openedAt := 0      ; 打开时刻（存活检查宽限期用）

    static Show(designer) {
        if (!IsObject(designer))
            return
        if (IsObject(UIMacroLayerGui.instance) && !UIMacroLayerGui.instance._closed) {
            hwnd := (IsObject(UIMacroLayerGui.instance.ui)
                && UIMacroLayerGui.instance.ui.HasProp("wpfHwnd")) ? UIMacroLayerGui.instance.ui.wpfHwnd : 0
            if (hwnd)
                try WinActivate("ahk_id " hwnd)
            UIMacroLayerGui.instance._designer := designer
            UIMacroLayerGui.instance._Refresh()
            return
        }
        inst := UIMacroLayerGui()
        inst._designer := designer
        inst._Build()
        UIMacroLayerGui.instance := inst
        inst._Refresh()
    }

    ; 设计器重建/增删后调用：列表内容变了
    static NotifyIfOpen() {
        if (IsObject(UIMacroLayerGui.instance) && !UIMacroLayerGui.instance._closed)
            UIMacroLayerGui.instance._Refresh()
    }

    ; 设计器关闭时一并关掉本面板（否则会留下一个指向已销毁设计器的浮窗）
    static CloseIfOpen() {
        if (IsObject(UIMacroLayerGui.instance) && !UIMacroLayerGui.instance._closed)
            UIMacroLayerGui.instance._OnClose()
    }

    ; 设计器选中项变化：只移动高亮，不重排列表
    static NotifySelection() {
        if (!IsObject(UIMacroLayerGui.instance) || UIMacroLayerGui.instance._closed)
            return
        UIMacroLayerGui.instance._SyncSelection()
    }

    _Build() {
        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
            .TextElement_FontSize(XAMLHost.FontSize())
        main.Rows("30", "32", "*")

        XAMLHost.AddTitleBar(main, "当前页控件列表", "30")

        main.Add("TextBlock").Name("LayerHint").Text("")
            .Grid_Row(1).Margin("14,0,12,0").VerticalAlignment("Center")
            .FontSize("11").Foreground("{DynamicResource TextSub}")

        sv := main.Add("ScrollViewer").Grid_Row(2).Margin("12,4,12,12")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        rows := sv.Add("StackPanel")

        ; 预建行：上限 = 控件数上限，行高固定，刷新时只换文本与可见性
        loop UIMacroSchema.MaxControls {
            r := rows.Add("Border").Name("LR" A_Index)
                .Height(30).Margin("0,1,0,1").CornerRadius("4")
                .Background("Transparent").BorderBrush("Transparent")
                .BorderThickness("1").Padding("6,0")
                .Visibility("Collapsed")
            rowGrid := r.Add("Grid").Cols("28", "*")
            rowGrid.Add("TextBlock").Name("LRN" A_Index).Text("")
                .Grid_Column(0).FontSize("10").VerticalAlignment("Center")
                .Foreground("{DynamicResource TextSub}").TextAlignment("Center")
            rowGrid.Add("TextBlock").Name("LRT" A_Index).Text("")
                .Grid_Column(1).FontSize("12").VerticalAlignment("Center")
                .Foreground("{DynamicResource TextMain}").TextTrimming("CharacterEllipsis")
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "30")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="当前页控件列表" Width="330" Height="500" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.xaml := StrReplace(this.ui.xaml, "%components%", "")

        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "_OnClose"))
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "_OnClose"))
        ; 每行各自绑按下/抬起：按下记录来源行，抬起按落点行换序
        loop UIMacroSchema.MaxControls {
            this.ui.OnEvent("LR" A_Index, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnRowDown", A_Index))
            this.ui.OnEvent("LR" A_Index, "PreviewMouseMove", ObjBindMethod(this, "_OnRowHover", A_Index))
            this.ui.OnEvent("LR" A_Index, "MouseLeftButtonUp", ObjBindMethod(this, "_OnRowUp", A_Index))
        }

        try AppThemeUtil.ApplyWinThemeToXaml(this.ui)
        try this.ui.Show()
        ; 设计器被关掉（含用户点 ✕）时自己也退出：定时检查比事件可靠——
        ; 设计器重建时旧窗口的 Closing 是异步的，事件里分不清「重建」与「关闭」。
        this._openedAt := A_TickCount
        this._timerFn := ObjBindMethod(this, "_Watch")
        SetTimer(this._timerFn, 400)
    }

    ; 设计器已关闭 → 自己关闭。
    ; 判据只认「明确关闭」：d.closed 为真，或实例已从注册表移除。
    ; 不检查 ui.wpfHwnd——重建期间它可能短暂为空，会把「重建」误判成「关闭」
    ; （症状：刚打开/刚操作就自动关掉）。
    _Watch() {
        if (this._closed) {
            this._StopWatch()
            return
        }
        ; 打开后 1.5 秒内不判死，避开开窗初期的窗口句柄空档
        if (A_TickCount - this._openedAt < 1500)
            return
        d := this._designer
        dead := false
        if (!IsObject(d) || d.closed)
            dead := true
        else if (d._instanceKey != "" && !UIMacroDesignerGui.instances.Has(d._instanceKey))
            dead := true
        else if (!IsObject(d.ui))
            dead := true
        if (dead) {
            this._StopWatch()
            this._OnClose()
        }
    }

    _StopWatch() {
        if (this.HasProp("_timerFn") && this._timerFn != "") {
            try SetTimer(this._timerFn, 0)
            this._timerFn := ""
        }
    }

    ; 重建行内容：数组尾 = 最上层，所以行号 1 = 顶层
    _Refresh() {
        if (this._closed || !IsObject(this._designer) || !IsObject(this._designer._schema))
            return
        controls := this._CurrentPageControls()
        n := controls.Length
        this._loading := true
        try {
            batch := []
            this._ids := []
            loop UIMacroSchema.MaxControls {
                row := A_Index
                if (row <= n) {
                    ctrl := controls[n - row + 1]
                    this._ids.Push(String(ctrl.id))
                    batch.Push({ ControlName: "LRN" row, PropertyName: "Text", Value: String(row) })
                    batch.Push({ ControlName: "LRT" row, PropertyName: "Text", Value: UIMacroLayerGui._RowText(ctrl) })
                    batch.Push({ ControlName: "LR" row, PropertyName: "Visibility", Value: "Visible" })
                } else {
                    batch.Push({ ControlName: "LRN" row, PropertyName: "Text", Value: "" })
                    batch.Push({ ControlName: "LRT" row, PropertyName: "Text", Value: "" })
                    batch.Push({ ControlName: "LR" row, PropertyName: "Visibility", Value: "Collapsed" })
                }
            }
            if (this.ui.HasMethod("BatchUpdate"))
                this.ui.BatchUpdate(batch)
            else {
                for e in batch
                    this.ui.Update(e.ControlName, e.PropertyName, e.Value)
            }
            try this.ui.Update("LayerHint", "Text", "第 " this._designer._page " 页    " n " 个控件")
        } catch {
        }
        this._loading := false
        this._SyncSelection()
    }

    _CurrentPageControls() {
        controls := []
        page := Integer(this._designer._page)
        for ctrl in this._designer._schema.controls {
            ctrlPage := ctrl.HasProp("page") ? Integer(ctrl.page) : 1
            if (ctrlPage == page)
                controls.Push(ctrl)
        }
        return controls
    }

    ; 高亮跟设计器选中项走（只改行的背景，不动列表顺序）
    _SyncSelection() {
        if (this._closed || this._loading || !IsObject(this._designer))
            return
        selId := String(this._designer._selId)
        batch := []
        loop UIMacroSchema.MaxControls {
            row := A_Index
            id := (row <= this._ids.Length) ? this._ids[row] : ""
            on := (id != "" && id == selId)
            batch.Push({ ControlName: "LR" row, PropertyName: "Background"
                , Value: on ? "{DynamicResource ActionBg}" : "Transparent" })
            batch.Push({ ControlName: "LR" row, PropertyName: "BorderBrush"
                , Value: on ? "{DynamicResource ActionStroke}" : "Transparent" })
        }
        try {
            if (this.ui.HasMethod("BatchUpdate"))
                this.ui.BatchUpdate(batch)
            else {
                for e in batch
                    this.ui.Update(e.ControlName, e.PropertyName, e.Value)
            }
        }
    }

    static _RowText(ctrl) {
        t := UIMacroSchema.TypeLabel(ctrl.type)
        s := t
        if (UIMacroSchema.IsShapeType(ctrl.type)) {
            col := ctrl.HasProp("color") ? String(ctrl.color) : ""
            if (col == "accent")
                s .= "（强调）"
            else if (col == "sub")
                s .= "（次要）"
        } else {
            txt := ctrl.HasProp("text") ? Trim(String(ctrl.text)) : ""
            if (txt != "")
                s .= " · " txt
        }
        ; 批量协议用 | 与换行做分隔，值里不能带
        s := StrReplace(s, "|", "｜")
        s := StrReplace(s, "`r", " ")
        s := StrReplace(s, "`n", " ")
        return s
    }

    ; 拖动中鼠标移入某行：画一条插入指示线（该行上边框）
    ; 只改一行的边框，不动列表顺序——重排要等松手，否则每移一格就要整表刷新
    _OnRowHover(row, *) {
        if (this._closed || this._loading)
            return
        if (this._dragFrom == 0)
            return
        ; 拖回来源行 = 取消落位：必须把上一行的指示清掉，否则线会停在别处
        if (row == this._dragFrom) {
            this._ClearHover()
            return
        }
        if (row == this._hoverRow)
            return
        ; 空白行不画线：松手不会落位，画了是误导
        id := (row <= this._ids.Length) ? this._ids[row] : ""
        if (id == "") {
            this._ClearHover()
            return
        }
        ; 先清掉上一行的指示
        if (this._hoverRow != 0) {
            try this.ui.Update("LR" this._hoverRow, "BorderThickness", "0")
            try this.ui.Update("LR" this._hoverRow, "BorderBrush", "Transparent")
        }
        this._hoverRow := row
        ; 方向决定指示线画在上边还是下边——落位语义是「控件占据该行」，
        ; 但原占用者的移动方向两个方向相反：
        ;   向上拖（来源行号 > 目标行号）→ 原占用者被挤向下 → 线在目标行顶部
        ;   向下拖（来源行号 < 目标行号）→ 原占用者被挤向上 → 线在目标行底部
        edge := (this._dragFrom > row) ? "0,2,0,0" : "0,0,0,2"
        try this.ui.Update("LR" row, "BorderBrush", "{DynamicResource ActionBg}")
        try this.ui.Update("LR" row, "BorderThickness", edge)
    }

    _ClearHover() {
        if (this._hoverRow != 0) {
            try this.ui.Update("LR" this._hoverRow, "BorderThickness", "0")
            try this.ui.Update("LR" this._hoverRow, "BorderBrush", "Transparent")
        }
        this._hoverRow := 0
    }

    ; 行按下：选中该控件，并记下拖动来源
    _OnRowDown(row, *) {
        if (this._closed || this._loading)
            return
        id := (row <= this._ids.Length) ? this._ids[row] : ""
        if (id == "")
            return
        this._ClearHover()
        this._dragFrom := row
        if (String(this._designer._selId) != id)
            this._designer.SelectControl(id)
    }

    ; 行抬起：若落点行与来源行不同 → 换序
    _OnRowUp(row, *) {
        if (this._closed || this._loading)
            return
        from := this._dragFrom
        this._dragFrom := 0
        this._ClearHover()
        if (from == 0 || from == row)
            return
        dstId := (row <= this._ids.Length) ? this._ids[row] : ""
        if (dstId == "")
            return
        srcId := (from <= this._ids.Length) ? this._ids[from] : ""
        if (srcId == "")
            return
        if (!this._MoveControlTo(srcId, dstId))
            return
        this._designer._selId := srcId
        this._designer._Rebuild()     ; 重建画布；收尾会回调 NotifyIfOpen 刷新本列表
    }

    _MoveControlTo(srcId, dstId) {
        if (srcId == "" || dstId == "" || srcId == dstId)
            return false
        targetIndex := UIMacroSchema.IndexOf(this._designer._schema, dstId)
        if (!targetIndex)
            return false
        return UIMacroSchema.MoveToIndex(this._designer._schema, srcId, targetIndex)
    }

    _OnClose(*) {
        if (this._closed)
            return
        this._closed := true
        this._StopWatch()
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        if (UIMacroLayerGui.instance == this)
            UIMacroLayerGui.instance := ""
    }
}
