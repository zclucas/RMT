#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色）
    static STATE_PAUSED := 2     ; 暂停中（黄色）
    static STATE_STOPPED := 3    ; 停止/终止（红色，5秒后自动恢复）
    static DEFAULT_PANEL_ANCHOR := 1
    static DEFAULT_PANEL_OFFSET_X := 100
    static DEFAULT_PANEL_OFFSET_Y := 100

    __new() {
        this.PanelMap := Map()       ; panelKey -> panelInfo
        this.PanelTimers := Map()     ; panelKey -> FuncObj（SetTimer回调引用）
        this.IsCreating := false
        this.MonitorTimer := ""
        this.RunningMap := Map()
        this.RecoverTimers := Map()
        this._lastActiveHwnd := 0       ; 上次检测的前台窗口 hwnd
        this._TipTimers := Map()        ; panelKey -> 内联提示定时器
        ; 用户主动关闭（右键关闭/Alt+F4/热键隐藏）后禁止「激活时默认显示」重建，直到热键再开
        this.UserClosedKeys := Map()
        this.UserClosedFolds := Map()   ; fold 级「用户已关闭」：监控不再自动建回来
        ; 定时器回调懒创建。v2 读取尚未赋值的属性会直接抛错，不能写 IsObject(this._dragArmFn)
        this._dragArmFn := ""
        this._PosTickFn := ""
        ; §17 热重载订阅：任意配置变更广播 → 清空面板缓存（下次触发按新配置重建）
        global MyHotReloadBus
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "OnHotReloadConfigChanged"), (t) => this._IsMacroTable(t))
        this.StartMonitor()
    }

    ; 是否包含可运行宏的表（按表类型索引判断）
    _IsMacroTable(t) {
        global MySoftData
        if (!IsObject(MySoftData) || !MySoftData.HasProp("TableInfo"))
            return false
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return false
        return CheckIsMacroTable(t)
    }

    ; §17 热重载回调：清空面板缓存，下次触发（热键/RMT指令/激活跟随）按新配置重建
    OnHotReloadConfigChanged(tableIndex, itemIndex) {
        ; 自定义面板：宏内容变了只需要重填值。走 RefreshPanels（关掉所有浮窗）
        ; 既闪一下，又会把「写入宏」的内联提示连窗口一起销毁。
        customHandled := false
        for foldIndex, panelInfo in this.PanelMap.Clone() {
            if (!panelInfo.HasProp("_isCustom") || !panelInfo._isCustom)
                continue
            ; 以当前值为准：清掉未保存快照，否则关面板时会被回退到旧值
            if (panelInfo.HasProp("_macroSnapshot") && IsObject(panelInfo._macroSnapshot))
                panelInfo._macroSnapshot := Map()
            if (panelInfo.HasProp("_dataSnapshot") && IsObject(panelInfo._dataSnapshot))
                panelInfo._dataSnapshot := Map()
            this._FillBindings(panelInfo.panelKey)
            customHandled := true
        }
        if (!customHandled)
            this.RefreshPanels()
    }

    MarkUserClosed(panelKey) {
        this.UserClosedKeys[panelKey] := true
    }

    ClearUserClosed(panelKey) {
        if (this.UserClosedKeys.Has(panelKey))
            this.UserClosedKeys.Delete(panelKey)
    }

    IsUserClosed(panelKey) {
        return this.UserClosedKeys.Has(panelKey) && this.UserClosedKeys[panelKey]
    }

    StartMonitor() {
        if (this.MonitorTimer != "")
            return
        this.MonitorTimer := this.CheckAllPanels.Bind(this)
        SetTimer this.MonitorTimer, 200
    }

    StopMonitor() {
        if (this.MonitorTimer != "") {
            SetTimer this.MonitorTimer, 0
            this.MonitorTimer := ""
        }
        for foldIndex in this.PanelTimers.Clone() {
            this.StopFollowTimer(foldIndex)
        }
        this.HideAllPanels()
        for macroIndex in this.RunningMap {
            this.StopMacro(macroIndex)
        }
        for macroIndex in this.RecoverTimers {
            this.CancelRecoverTimer(macroIndex)
        }
    }

    ; ========== 面板管理（严格对齐 floating_panel.ahk） ==========

    ; 获取界面宏表 + 折叠框 + 折叠框内条目（统一入口，避免各处重复 TableInfo[4]/IndexSpan）
    _GetFoldContext(foldIndex) {
        tableItem := GetTableBySymbol("UI")
        if (!tableItem)
            return ""
        if (!tableItem.Folds.Has(foldIndex))
            return ""
        fold := tableItem.Folds[foldIndex]
        if (!fold || fold.ForbidState)
            return ""
        return { tableItem: tableItem, fold: fold, items: GetFoldItems(tableItem, fold) }
    }

    ; 创建面板入口（对齐 CreateFloatingPanel L182-265）
    CreatePanel(foldIndex) {
        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return
        tableItem := ctx.tableItem
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        btnItems := []
        for i, item in ctx.items {
            if (ParseBoolInt(item.Forbid))
                continue

            remarkValue := item.Remark
            iconValue := item.IcoPath
            btnText := remarkValue == "" ? GetLang("操作") i : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            macroIndex := GetItemIndexInTable(tableItem, item.ID)
            btnItems.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                macroIndex: macroIndex,
                macroId: String(item.ID)
            })
        }

        if (btnItems.Length == 0)
            return

        ; 解析目标窗口（对齐 floating_panel 的 targetB_Hwnd）
        frontInfo := fold.FrontInfo
        targetHwnd := 0
        isScreenMode := true

        if (frontInfo != "") {
            targetHwnd := this.ResolveTargetHwnd(frontInfo)
            if (targetHwnd)
                isScreenMode := false
        }

        if (!isScreenMode && targetHwnd) {
            if (!DllCall("user32\IsWindow", "Ptr", targetHwnd))
                return
            ; 前台激活检查：目标窗口必须在前台才允许创建面板
            activeHwnd := WinGetID("A")
            if (activeHwnd != targetHwnd)
                return
        }

        ; 构建面板（对齐 CreateFloatingPanel）
        ; 创建期间置位 IsCreating：BuildXAMLPanel/WaitForPanelReady 内的 Sleep 会泵消息，
        ; 导致 CheckAllPanels 重入；此时 PanelMap 尚未写入，自动显示会再建一个重复面板。
        this.IsCreating := true
        try {
            panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode, false, foldIndex)
            if (!panelInfo)
                return

            this.PanelMap.Set(foldIndex, panelInfo)

            ; 等待窗口就绪+初始化（对齐 WaitForHwnd + OnPanelReady）
            this.WaitForPanelReady(foldIndex)
        } finally {
            this.IsCreating := false
        }
    }

    ; 为指定 hwnd 创建自动面板（界面激活时默认显示），键为 foldIndex|hwnd；targetHwnd=0 时创建屏幕模式面板
    CreateAutoPanel(foldIndex, panelKey, targetHwnd) {
        if (this.PanelMap.Has(panelKey))
            return
        ; 用户曾主动关闭：不要因点击主界面/切换前台而自动重建
        if (this.IsUserClosed(panelKey))
            return

        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return
        tableItem := ctx.tableItem
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        btnItems := []
        for i, item in ctx.items {
            if (ParseBoolInt(item.Forbid))
                continue

            remarkValue := item.Remark
            iconValue := item.IcoPath
            btnText := remarkValue == "" ? GetLang("操作") i : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            macroIndex := GetItemIndexInTable(tableItem, item.ID)
            btnItems.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                macroIndex: macroIndex,
                macroId: String(item.ID)
            })
        }

        if (btnItems.Length == 0)
            return

        ; 自动面板：有目标窗口则窗口跟随模式，否则屏幕模式
        isScreenMode := (targetHwnd == 0)
        ; 创建期间置位 IsCreating，防止 Sleep 泵消息时 CheckAllPanels 重入造成重复面板
        this.IsCreating := true
        try {
            panelInfo := this.BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode, true, panelKey)
            if (!panelInfo)
                return

            panelInfo.autoShow := true  ; 标记为自动面板
            this.PanelMap.Set(panelKey, panelInfo)
            this.WaitForPanelReady(panelKey)
        } finally {
            this.IsCreating := false
        }

        ; 确保面板在目标窗口之上（不抢焦点）
        if (IsObject(panelInfo) && panelInfo.wpfHwnd) {
            DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0  ; HWND_TOP
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0001 | 0x0002 | 0x0010)  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
        }
    }

    ; 显示自动面板（不抢焦点，不激活）
    ShowAutoPanel(panelKey) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!panelInfo || !panelInfo.wpfHwnd)
            return

        ; 如果已被使用者手動關閉，則不進行自動顯示
        if (this.IsUserClosed(panelKey) || (panelInfo.HasProp("userClosed") && panelInfo.userClosed))
            return

        ; 配置变化检测：按钮尺寸/列数/颜色变化 → 销毁重建
        if (panelInfo._cfg_BtnHeight != MainSoftData.UIPanelBtnHeight
            || panelInfo._cfg_BtnWidth != MainSoftData.UIPanelBtnWidth
            || panelInfo._cfg_Cols != MainSoftData.UIPanelCols
            || panelInfo._cfg_FontSize != MainSoftData.UIPanelFontSize
            || panelInfo._cfg_BtnColor != MainSoftData.UIPanelBtnColor
            || panelInfo._cfg_BtnText != MainSoftData.UIPanelBtnText
            || panelInfo._cfg_BgColor != MainSoftData.UIPanelBgColor
            || panelInfo._cfg_TitleBg != MainSoftData.UIPanelTitleBg
            || panelInfo._cfg_TitleText != MainSoftData.UIPanelTitleText) {
            parts := StrSplit(panelKey, "|")
            foldIndex := Integer(parts[1])
            targetHwnd := (parts.Length >= 2) ? Integer(parts[2]) : 0
            this.DestroyPanel(panelKey)
            this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            return
        }

        try {
            DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 8)  ; SW_SHOWNA
            ; 重新显示 → 允许跟随定时器再置顶一次（配合 _topmostDone 的「只设一次」）
            panelInfo._topmostDone := false
            ; 不调用 ApplyPanelPosition——保持用户拖拽后的位置，跟随定时器会处理定位
            ; 提升到目标窗口之上（不抢焦点）
            DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0  ; HWND_TOP
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0001 | 0x0002 | 0x0010)  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
            panelInfo.visible := true
        }
    }

    ; 构建XAML面板（对齐 CreateFloatingPanel L182-264）
    BuildXAMLPanel(btnItems, foldIndex, targetHwnd, isScreenMode, skipActivate := false, panelKey := "") {
        if (panelKey == "")
            panelKey := foldIndex
        ; 自定义界面优先：该面板在配置里存在合法 schema 时，走独立渲染分支
        customSchema := this._GetCustomSchema(foldIndex)
        if (IsObject(customSchema))
            return this._BuildCustomPanel(customSchema, foldIndex, targetHwnd, isScreenMode, skipActivate, panelKey)

        titleBarH := 30
        btnItemH := MainSoftData.UIPanelBtnHeight
        btnItemW := MainSoftData.UIPanelBtnWidth
        btnGap := 2
        bodyMarginV := 6
        cols := MainSoftData.UIPanelCols
        wpfBorderPad := 2
        ; 面板宽度 = 列数 * 按钮宽度 + 按钮左右边距(各2px) + 主体左右边距(各4px)
        pw := cols * (btnItemW + 4) + 8

        btnColor := MainSoftData.UIPanelBtnColor
        btnTextColor := MainSoftData.UIPanelBtnText
        bgColor := MainSoftData.UIPanelBgColor
        titleBg := MainSoftData.UIPanelTitleBg
        titleText := MainSoftData.UIPanelTitleText
        fontSize := Integer(MainSoftData.UIPanelFontSize)

        tableItem := GetTableBySymbol("UI")
        fold := tableItem ? tableItem.Folds[foldIndex] : ""
        foldRemark := fold ? fold.Remark : ""

        rows := Ceil(btnItems.Length / cols)
        contentH := rows * btnItemH + (rows - 1) * btnGap + bodyMarginV
        ph := titleBarH + contentH + wpfBorderPad

        ; 默认位置来自模块设置。用户拖动后的记忆位置优先。
        ; 屏幕模式的 Left/Top 用 DIP，窗口跟随保持物理像素，与 SetWindowPos 一致。
        mode := 0, anchor := 6, offX := -50, offY := 50
        this._PlaceByFold(fold, foldIndex, targetHwnd, isScreenMode, pw, ph, &initX, &initY, &mode, &anchor, &offX, &offY)
        offsetX := offX
        offsetY := offY

        ; 构建XAML（与 floating_panel L213-233 完全一致的结构）
        main := XAML_Generator("Grid")
        main.Background("{DynamicResource UIPanelBgColor}")
        main.Rows(titleBarH, "*")

        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("{DynamicResource UIPanelTitleBg}")
            .WindowChrome_IsHitTestVisibleInChrome("True")
        titleBar.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("{DynamicResource UIPanelTitleText}").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")

        body := main.Add("Grid").Grid_Row(1).Name("BodyPanel").Margin("2,1,2,2")
        textMaxW := Max(btnItemW - 8, 24)

        ; 按钮样式挂在控件本地，避免无 x:Key 的 Style 进 Window.Resources 后被同步到
        ; Application.Current，关闭浮窗后污染其它 XAML 窗口
        panelBtnStyle := '<Style TargetType="Button"><Setter Property="BorderThickness" Value="1"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Arrow"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="1,0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource UIPanelTitleBg}"/><Setter TargetName="Bd" Property="BorderThickness" Value="1"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource UIPanelTitleBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        ; 列定义：根据按钮宽度显式设置
        colDefs := body.Add("Grid.ColumnDefinitions")
        loop cols
            colDefs.Add("ColumnDefinition").Width(btnItemW)

        ; 行定义：每行固定高度
        rowDefs := body.Add("Grid.RowDefinitions")
        loop rows
            rowDefs.Add("RowDefinition").Height(btnItemH)

        for i, item in btnItems {
            row := Floor((i - 1) / cols)
            col := Mod(i - 1, cols)
            isLastRow := (row = rows - 1)
            marginBottom := isLastRow ? "0" : btnGap
            marginStr := "1,0,1," marginBottom

            btn := body.Add("Button").Name(item.name).Height(btnItemH)
                .Grid_Row(row).Grid_Column(col)
                .Margin(marginStr)
            btn.Background("{DynamicResource UIPanelBtnColor}").Foreground("{DynamicResource UIPanelBtnText}").FontSize(fontSize)
            btn.HorizontalAlignment("Stretch")
            btn.Padding("0")
            btn.InjectResources(panelBtnStyle)

            sp := btn.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center")
                .VerticalAlignment("Center")

            ; 运行状态色点（默认隐藏）
            sp.Add("Ellipse").Name(item.name "_State")
                .Width(8).Height(8).VerticalAlignment("Center").Margin("0,0,2,0")
                .Visibility("Collapsed").IsHitTestVisible("False")

            if (item.icon != "") {
                fullIconPath := this.GetFullIconPath(item.icon)
                if (fullIconPath != "" && FileExist(fullIconPath)) {
                    sp.Add("Image").Name(item.name "_Img")
                        .Source(fullIconPath).Width(14).Height(14).VerticalAlignment("Center").Margin("0,0,2,0")
                }
            }

            sp.Add("TextBlock").Text(item.text).VerticalAlignment("Center").Foreground("{DynamicResource UIPanelBtnText}").FontSize(fontSize)
                .TextTrimming("CharacterEllipsis").MaxWidth(String(textMaxW))
        }

        ; XAML字符串处理（对齐 floating_panel L235-244）
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" ShowInTaskbar="False" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ; 矩形浮窗保持不透明。AllowsTransparency 与 WindowChrome 不能共存，
        ; 同时打开时内容不会绘制，窗口只剩一块黑底。
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="' bgColor '"')

        ; XAML_TEMPLATE 已内置 CloseBtnRadius；此处重复注入同名资源会让 WPF 解析器崩溃。
        panelResources := '<SolidColorBrush x:Key="UIPanelBtnColor" Color="' btnColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelBtnText" Color="' btnTextColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelBgColor" Color="' bgColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleBg" Color="' titleBg '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleText" Color="' titleText '"/>'
        ui.xaml := StrReplace(ui.xaml, '%resources%', panelResources)
        ui.xaml := StrReplace(ui.xaml, '%components%', '')

        ; 绑定事件（对齐 floating_panel L246-249）
        for i, item in btnItems {
            ui.OnEvent(item.name, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnBtnClick", item.macroId, panelKey))
        }
        try ui.OnEvent("TitleBar", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTitleGrab", panelKey))
        try ui.OnEvent("Window", "StateChanged", ObjBindMethod(this, "_OnPanelStateChanged", panelKey))

        ; 显示窗口（对齐 floating_panel L254）
        ui.Show()

        ; 等待wpfHwnd就绪（对齐 floating_panel L256-262）
        loop 20 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                if !skipActivate
                    WinActivate("ahk_id " ui.wpfHwnd)
                break
            }
            Sleep(50)
        }

        ; 返回面板信息（对齐 floating_panel 全局变量初始化 L207-L211, L251-L252）
        return {
            ui: ui,
            wpfHwnd: ui.wpfHwnd ? ui.wpfHwnd : 0,
            panelKey: panelKey,
            foldIndex: foldIndex,
            foldID: fold ? fold.ID : "",
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            frontInfo: fold ? fold.FrontInfo : "",
            visible: true,
            btnItems: btnItems,
            posMode: mode,
            anchor: anchor,
            offsetX: offsetX,
            offsetY: offsetY,
            lastSetX: "",
            lastSetY: "",
            panelReady: false,
            ; 配置快照：用于检测面板显示时配置是否变化
            _cfg_BtnHeight: btnItemH,
            _cfg_BtnWidth: btnItemW,
            _cfg_Cols: cols,
            _cfg_FontSize: fontSize,
            _cfg_BtnColor: btnColor,
            _cfg_BtnText: btnTextColor,
            _cfg_BgColor: bgColor,
            _cfg_TitleBg: titleBg,
            _cfg_TitleText: titleText
        }
    }

    ; ------------------------------------------------------------------
    ; 字段绑定：读初值 / 写入宏
    ; ------------------------------------------------------------------
    _PosTickFn := ""       ; 面板位置记录定时器
    _PosWatchHwnd := 0
    _PosWatchPanelKey := ""
    _PosWatchFold := 0
    _PosWatchTargetHwnd := 0
    _PosWatchStartX := 0
    _PosWatchStartY := 0

    _FindPanelInfo(panelKey) {
        return this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
    }

    ; ------------------------------------------------------------------
    ; 宏行参数绑定（方案 A）
    ;
    ; 不再有「临时值层」：改控件 = 直接改内存里的 item.Macro。
    ; 好处：所有指令类型都天然生效（旧方案只有间隔生效），执行宏时读到的就是新值。
    ; 「写入宏」才落盘；面板销毁/隐藏时用首次改动前的快照还原内存，保证
    ; 「不点写入宏，重开就回原值」。
    ; ------------------------------------------------------------------

    ; binding → { tableItem, item }；解析不到返回 ""
    _ResolveBinding(binding) {
        if (!IsObject(binding) || !binding.HasProp("macroId"))
            return ""
        tableItem := ""
        try tableItem := GetItemTableGlobal(String(binding.macroId))
        if (!IsObject(tableItem))
            return ""
        item := UIMacroStepBinding.FindMacroItem(tableItem, binding.macroId)
        if (!IsObject(item))
            return ""
        return { tableItem: tableItem, item: item }
    }

    ; 把值写进内存里的宏文本（首次改动前先快照原始宏）
    ; 把值写进内存（首次改动前先快照）
    ;   step 模式：改 item.Macro 文本
    ;   data 模式：改指令数据缓存对象（不落盘）
    ; 返回 { ok, changed, msg }
    _ApplyBoundValue(info, binding, value) {
        if (!IsObject(info) || !IsObject(binding))
            return { ok: false, changed: false, msg: "绑定无效" }

        mode := String(binding.mode)
        if (mode == "data") {
            spec := UIMacroStepBinding.SpecOfData(binding.kind, binding.field)
        } else if (mode == "skip") {
            spec := UIMacroStepBinding.SkipSpec()
        } else {
            spec := UIMacroStepBinding.SpecOfBindingDeep(this._TableForBinding(binding), binding)
        }
        coerced := UIMacroStepBinding.Coerce(spec, value)
        if (!coerced.ok)
            return { ok: false, changed: false, msg: coerced.msg }
        value := coerced.value

        ; ---------- 序列型：指令数据字段 ----------
        if (mode == "data") {
            if (!info.HasProp("_dataSnapshot") || !IsObject(info._dataSnapshot))
                info._dataSnapshot := Map()
            k := UIMacroStepBinding.BindingKey(binding)
            cur := UIMacroStepBinding.ReadData(binding.serial, binding.field)
            if (!cur.ok)
                return { ok: false, changed: false, msg: cur.msg }
            res := UIMacroStepBinding.SetData(binding.serial, binding.field, value)
            if (!res.ok)
                return res
            ; 快照同样记 orig/last：只有内存里仍是 last 才回退，避免覆盖别处的编辑
            if (!info._dataSnapshot.Has(k))
                info._dataSnapshot[k] := { serial: binding.serial, field: binding.field, orig: cur.value, last: String(value) }
            else
                info._dataSnapshot[k].last := String(value)
            return res
        }

        ; ---------- 步骤跳过开关（勾选=执行，取消=跳过 🚫） ----------
        if (mode == "skip") {
            tableItem := this._TableForBinding(binding)
            hopsS := (binding.HasProp("hops") && IsObject(binding.hops)) ? binding.hops : ""
            r0s := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hopsS)
            if (!r0s.ok)
                return { ok: false, changed: false, msg: r0s.msg }
            if (!info.HasProp("_macroSnapshot") || !IsObject(info._macroSnapshot))
                info._macroSnapshot := Map()
            ks := String(binding.macroId) "|skip|" String(binding.step) UIMacroStepBinding.HopsKey(binding)
            skipped := (String(value) == "0")
            res := UIMacroStepBinding.SetSkipDeep(tableItem, binding, skipped)
            if (!res.ok)
                return res
            if (!res.changed)
                return { ok: true, changed: false, msg: "" }
            if (!info._macroSnapshot.Has(ks))
                info._macroSnapshot[ks] := { orig: r0s.text, last: res.text, macroId: String(binding.macroId), hops: hopsS }
            else
                info._macroSnapshot[ks].last := res.text
            return { ok: true, changed: true, msg: "" }
        }

        ; ---------- 内联型：宏文本（hops 缺省 = 顶层宏，有 hops = 嵌套容器） ----------
        tableItem := this._TableForBinding(binding)
        hops := (binding.HasProp("hops") && IsObject(binding.hops)) ? binding.hops : ""
        ; 快照的 orig 要取「动手前」的容器原文，先解析一次
        r0 := UIMacroStepBinding.ResolveContainer(tableItem, binding.macroId, hops)
        if (!r0.ok)
            return { ok: false, changed: false, msg: r0.msg }
        if (!info.HasProp("_macroSnapshot") || !IsObject(info._macroSnapshot))
            info._macroSnapshot := Map()
        ; 键必须含 hops：同一条宏的「顶层第3步」和「真分支里第3步」是两个不同容器
        k := String(binding.macroId) UIMacroStepBinding.HopsKey(binding)
        res := UIMacroStepBinding.SetParamDeep(tableItem, binding, value)
        if (!res.ok)
            return res
        if (!res.changed)
            return { ok: true, changed: false, msg: "" }
        ; 快照记两份：orig = 面板动手前的容器原文，last = 我们最近一次写进去的文本。
        ; 还原时只有「容器仍是 last」才回退，避免把用户在别处的编辑覆盖掉。
        if (!info._macroSnapshot.Has(k))
            info._macroSnapshot[k] := { orig: r0.text, last: res.text, macroId: String(binding.macroId), hops: hops }
        else
            info._macroSnapshot[k].last := res.text
        return { ok: true, changed: true, msg: "" }
    }

    ; 还原快照（面板销毁/隐藏时调用；点过「写入宏」的不再还原）
    _RestoreMacroSnapshot(info) {
        if (!IsObject(info))
            return
        if (info.HasProp("_macroSnapshot") && IsObject(info._macroSnapshot)) {
            for snapKey, snap in info._macroSnapshot {
                if (!IsObject(snap) || !snap.HasProp("orig") || !snap.HasProp("last") || !snap.HasProp("macroId"))
                    continue
                ; hops 存在快照里：还原时按原路径解析容器
                tableItem := ""
                try tableItem := GetItemTableGlobal(String(snap.macroId))
                r := UIMacroStepBinding.ResolveContainer(tableItem, snap.macroId,
                    snap.HasProp("hops") && IsObject(snap.hops) ? snap.hops : "")
                if (!r.ok)
                    continue
                ; 只有容器仍是「我们上次写进去的文本」才回退。
                ; 若期间用户在宏编辑器里改过这一条并保存，文本已变，绝不能拿旧快照覆盖。
                if (r.text == snap.last)
                    UIMacroStepBinding._WriteContainerBack(r.owner, snap.orig)
            }
            info._macroSnapshot := Map()
        }
        if (info.HasProp("_dataSnapshot") && IsObject(info._dataSnapshot)) {
            for snapKey, snap in info._dataSnapshot {
                if (!IsObject(snap) || !snap.HasProp("orig"))
                    continue
                cur := UIMacroStepBinding.ReadData(snap.serial, snap.field)
                if (!cur.ok)
                    continue
                ; 同上：只有当前值仍是我们写的那个才回退
                if (String(cur.value) == String(snap.last))
                    UIMacroStepBinding.SetData(snap.serial, snap.field, snap.orig)
            }
            info._dataSnapshot := Map()
        }
    }

    ; 面板就绪后把宏里的当前值填进控件（只读一次，之后以面板值为准）
    _FillBindings(panelKey) {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema) || !IsObject(info) || !IsObject(info.ui))
            return
        for ctrl in schema.controls {
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            val := ""
            spec := ""
            if (String(ctrl.binding.mode) == "data") {
                got := UIMacroStepBinding.ReadData(ctrl.binding.serial, ctrl.binding.field)
                if (!got.ok)
                    continue
                val := got.value
                spec := UIMacroStepBinding.SpecOfData(ctrl.binding.kind, ctrl.binding.field)
            } else if (String(ctrl.binding.mode) == "skip") {
                tableItem := this._TableForBinding(ctrl.binding)
                got := UIMacroStepBinding.ReadSkipDeep(tableItem, ctrl.binding)
                if (!got.ok)
                    continue
                ; 勾选 = 执行（未跳过）
                val := got.skipped ? "0" : "1"
                spec := UIMacroStepBinding.SkipSpec()
            } else {
                tableItem := this._TableForBinding(ctrl.binding)
                got := UIMacroStepBinding.ReadParamDeep(tableItem, ctrl.binding)
                if (!got.ok)
                    continue
                val := got.value
                spec := UIMacroStepBinding.SpecOfBindingDeep(tableItem, ctrl.binding)
            }
            ; Edit / CheckBox / ComboBox 三种回填统一走 SetValue
            UIMacroRenderer.SetValue(info.ui, ctrl.id, ctrl.type, val, spec)
        }
    }

    ; 「写入宏」：把内存里的宏改动落盘（复用宏行编辑那条既有保存路径）
    _OnWriteBack(panelKey, *) {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema) || !IsObject(info) || !IsObject(info.ui))
            return

        written := 0             ; 真的写了（内存值确实变了）
        unchanged := 0           ; 值本来就和面板一致，不需要写
        failed := 0
        firstMsg := ""
        touchedMacros := Map()   ; macroId → tableItem（同一条宏只落盘一次）
        touchedData := Map()     ; serial → true（同一序列只落盘一次）

        for ctrl in schema.controls {
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue

            b := ctrl.binding
            ; TextBlock 只显示、不接收输入，没有「面板值」可写回
            if (UIMacroSchema.IsDisplayOnly(ctrl.type))
                continue
            isData := (String(b.mode) == "data")
            isSkip := (String(b.mode) == "skip")
            spec := isData
                ? UIMacroStepBinding.SpecOfData(b.kind, b.field)
                : (isSkip ? UIMacroStepBinding.SkipSpec()
                    : UIMacroStepBinding.SpecOfBindingDeep(this._TableForBinding(b), b))

            val := UIMacroRenderer.ReadValue(info.ui, ctrl.id, ctrl.type, spec)
            cres := UIMacroStepBinding.Coerce(spec, val)
            if (!cres.ok) {
                failed += 1
                if (firstMsg == "") {
                    ctrlLabel := Trim(String(ctrl.text))
                    if (ctrlLabel == "")
                        ctrlLabel := UIMacroSchema.TypeLabel(ctrl.type)
                    firstMsg := Format("「{}」{}", ctrlLabel, cres.msg)
                }
                continue
            }

            if (isData) {
                cur := UIMacroStepBinding.ReadData(b.serial, b.field)
                if (!cur.ok) {
                    failed += 1
                    if (firstMsg == "")
                        firstMsg := cur.msg
                    continue
                }
                ; 面板上的改动是「即时写进内存」的（改一下控件就见效），所以
                ; 「内存值 == 面板值」不能拿来判定「没改动」——那会导致永远不落盘。
                ; 真正的判据是：内存值是否仍等于本次编辑开始前快照下来的原始值。
                snapKey := UIMacroStepBinding.BindingKey(b)
                snap := (info.HasProp("_dataSnapshot") && IsObject(info._dataSnapshot) && info._dataSnapshot.Has(snapKey))
                    ? info._dataSnapshot[snapKey] : ""
                dirty := IsObject(snap)
                    ? (String(snap.orig) != String(cur.value))
                    : (String(cur.value) != String(cres.value))
                wres := UIMacroStepBinding.SetData(b.serial, b.field, cres.value)
                if (!wres.ok) {
                    failed += 1
                    if (firstMsg == "")
                        firstMsg := wres.msg
                    continue
                }
                ; 只要这个绑定通过了校验，就把它的容器记为「需要落盘」。
                ; 不去赌 dirty 判断——面板改动是即时写进内存的，任何一次判空都会
                ; 变成「执行生效但没存盘」。落盘未改动的容器只是重写同样内容，无害。
                touchedData[String(b.serial)] := true
                if (dirty)
                    written += 1
                else
                    unchanged += 1
                continue
            }

            ; ---- 跳过开关：勾选=执行，取消=跳过（写 🚫 前缀） ----
            if (isSkip) {
                tableItem := this._TableForBinding(b)
                wres := UIMacroStepBinding.SetSkipDeep(tableItem, b, String(cres.value) == "0")
                if (!wres.ok) {
                    failed += 1
                    if (firstMsg == "")
                        firstMsg := wres.msg
                    continue
                }
                snapKey := String(b.macroId) "|skip|" String(b.step) UIMacroStepBinding.HopsKey(b)
                snap := (info.HasProp("_macroSnapshot") && IsObject(info._macroSnapshot) && info._macroSnapshot.Has(snapKey))
                    ? info._macroSnapshot[snapKey] : ""
                dirty := IsObject(snap) ? (String(snap.orig) != String(wres.text)) : wres.changed
                touchedMacros[snapKey] := { owner: wres.owner }
                if (dirty)
                    written += 1
                else
                    unchanged += 1
                continue
            }

            tableItem := this._TableForBinding(b)
            wres := UIMacroStepBinding.SetParamDeep(tableItem, b, cres.value)
            if (!wres.ok) {
                failed += 1
                if (firstMsg == "")
                    firstMsg := wres.msg
                continue
            }
            ; 即时生效意味着内存里早就是新值了，只能拿快照原文比
            snapKey := String(b.macroId) UIMacroStepBinding.HopsKey(b)
            snap := (info.HasProp("_macroSnapshot") && IsObject(info._macroSnapshot) && info._macroSnapshot.Has(snapKey))
                ? info._macroSnapshot[snapKey] : ""
            dirty := IsObject(snap)
                ? (String(snap.orig) != String(wres.text))
                : wres.changed
            ; 不论 dirty 与否都记为「需要落盘」，否则会出现
            ; 「执行已生效、写盘被跳过」。未改动的容器重写同样内容是安全的。
            touchedMacros[snapKey] := { owner: wres.owner }
            if (dirty)
                written += 1
            else
                unchanged += 1
        }

        ; 落盘 1：内联型。只写盘，**不广播**热重载。
        ; 广播会触发 RefreshPanels → HideAllPanels（关掉所有浮窗、清 PanelMap），
        ; 表现就是点一下「写入宏」面板闪一下，而且提示框刚设置就被连窗口一起销毁了。
        repaintTables := Map()
        for snapKey, ent in touchedMacros {
            try {
                if (!UIMacroStepBinding.SaveContainer(ent.owner))
                    throw Error("容器保存失败")
                ; 顶层宏落盘后才需要重绘主界面；嵌套容器在数据文件里，主列表不显示它
                if (IsObject(ent.owner) && ent.owner.type == "item")
                    repaintTables[String(ent.owner.tableItem.ID)] := true
                if (info.HasProp("_macroSnapshot") && IsObject(info._macroSnapshot))
                    info._macroSnapshot.Delete(snapKey)
            } catch {
                failed += 1
                if (firstMsg == "")
                    firstMsg := "落盘失败：宏表保存出错"
            }
        }
        ; 仅顶层宏会显示在主界面列表中；嵌套容器只需保存数据文件。
        for tableID, _ in repaintTables
            this._RepaintMainWindowTable(tableID)
        ; 落盘 2：序列型 → SaveMacroCMDData（既有接口）
        savedData := Map()
        for serial, flag in touchedData {
            if (UIMacroStepBinding.SaveData(serial)) {
                savedData[String(serial)] := true
            } else {
                failed += 1
                if (firstMsg == "")
                    firstMsg := "落盘失败：指令数据保存出错"
            }
        }
        ; 保存成功后才清理快照；失败时关闭面板仍可还原内存值。
        if (info.HasProp("_dataSnapshot") && IsObject(info._dataSnapshot)) {
            dropKeys := []
            for snapKey, snap in info._dataSnapshot {
                if (IsObject(snap) && snap.HasProp("serial") && savedData.Has(String(snap.serial)))
                    dropKeys.Push(snapKey)
            }
            for snapKey in dropKeys
                info._dataSnapshot.Delete(snapKey)
        }

        ; 成功走面板内联提示（不弹窗）；有失败才弹一次，把原因说清楚
        if (failed > 0) {
            msg := Format("已保存：{} 项有改动", written)
            if (unchanged > 0)
                msg .= Format("，{} 项无变化", unchanged)
            msg .= Format("，{} 项失败", failed)
            if (firstMsg != "")
                msg .= "`n`n首个原因：" firstMsg
            this._ShowWriteBackTip(panelKey, Format("{} 项失败", failed))
            MsgBox(msg, "写入宏", "Icon!")
            return
        }
        tip := Format("已保存 {} 项", written)
        if (unchanged > 0)
            tip .= Format("（{} 项无变化）", unchanged)
        this._ShowWriteBackTip(panelKey, tip)
    }

    ; 面板内的轻量提示：显示在「写入宏」旁边，3 秒后自动消失（替代弹窗）
    _ShowWriteBackTip(panelKey, text) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        try info.ui.Update("WriteBackTip", "Text", text)
        try info.ui.Update("WriteBackTip", "Visibility", "Visible")
        if (this._TipTimers.Has(panelKey))
            SetTimer(this._TipTimers[panelKey], 0)
        timer := ObjBindMethod(this, "_HideWriteBackTip", panelKey)
        this._TipTimers[panelKey] := timer
        SetTimer(timer, -3000)
    }

    _HideWriteBackTip(panelKey) {
        if (this._TipTimers.Has(panelKey))
            this._TipTimers.Delete(panelKey)
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        try info.ui.Update("WriteBackTip", "Visibility", "Collapsed")
    }

    ; 绑定用的表对象（data 模式不需要，step 模式要它算 spec）
    _TableForBinding(binding) {
        if (!IsObject(binding) || !binding.HasProp("macroId"))
            return ""
        resolved := this._ResolveBinding(binding)
        return IsObject(resolved) ? resolved.tableItem : ""
    }

    ; 让主界面把某张表的每一行重新画一遍（虚拟列表不会感知 TableInfo 被整体替换）
    _RepaintMainWindowTable(tableID) {
        if (!IsSet(MyMainWin) || !IsObject(MyMainWin))
            return
        t := GetTableIndexByID(tableID)
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        tbl := MySoftData.TableInfo[t]
        if (!IsObject(tbl))
            return
        loop tbl.Items.Length
            try MyMainWin.RefreshItemRow(t, A_Index)
    }

    _OnBoundEdit(panelKey, ctrlId, binding, *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        val := ""
        try val := info.ui.Query(UIMacroRenderer.NameOf(ctrlId))
        this._ApplyBoundValue(info, binding, val)
        this._RefreshDisplayBindings(panelKey)
    }

    ; 刷新「只显示」的绑定（TextBlock）：它没有输入，只能跟着别的控件的改动走。
    ; 只碰 TextBlock，避免把用户正在输入的 Edit 内容覆盖掉。
    _RefreshDisplayBindings(panelKey) {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema) || !IsObject(info) || !IsObject(info.ui))
            return
        for ctrl in schema.controls {
            if (ctrl.type != "TextBlock")
                continue
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            b := ctrl.binding
            val := ""
            spec := ""
            if (String(b.mode) == "data") {
                spec := UIMacroStepBinding.SpecOfData(b.kind, b.field)
                cur := UIMacroStepBinding.ReadData(b.serial, b.field)
                val := cur.ok ? cur.value : ""
            } else {
                tableItem := this._TableForBinding(b)
                got := UIMacroStepBinding.ReadParamDeep(tableItem, b)
                if (got.ok) {
                    val := got.value
                    spec := UIMacroStepBinding.SpecOfBindingDeep(tableItem, b)
                }
            }
            UIMacroRenderer.SetValue(info.ui, ctrl.id, "TextBlock", val, spec)
        }
    }

    ; 下拉框改动：SelectedIndex → options 里的「值」→ 写进宏文本
    _OnBoundCombo(panelKey, ctrlId, binding, spec := "", *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        idx := -1
        try idx := Integer(info.ui.Query(UIMacroRenderer.NameOf(ctrlId) ">SelectedIndex"))
        if (idx < 0) {
            this._ApplyBoundValue(info, binding, "")
            return
        }
        if (!IsObject(spec) || !spec.HasProp("options") || !IsObject(spec.options))
            return
        i := 0
        for pair in spec.options {
            if (i == idx) {
                this._ApplyBoundValue(info, binding, String(pair[1]))
                this._RefreshDisplayBindings(panelKey)
                return
            }
            i += 1
        }
    }

    _OnBoundCheck(panelKey, ctrlId, binding, checked, *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info))
            return
        this._ApplyBoundValue(info, binding, checked ? "1" : "0")
        this._RefreshDisplayBindings(panelKey)
    }

    ; ------------------------------------------------------------------
    ; 自定义界面（v0.1）
    ; ------------------------------------------------------------------

    ; 读取该 fold 的自定义定义；没有配置或校验不通过 → 返回 ""（自动降级回自动模式）
    ;
    ; 存储键 = 折叠框 ID（稳定唯一）；旧版本用数组下标做键，第一次读到时
    ; 顺手迁移成新键（MigrateLegacy 只做一次，失败静默）。
    _GetCustomSchema(foldIndex) {
        foldKey := ""
        try {
            tableItem := GetTableBySymbol("UI")
            fold := (tableItem && tableItem.Folds.Length >= foldIndex) ? tableItem.Folds[foldIndex] : ""
            foldKey := UIMacroSchema.FoldKey(fold)
        }
        if (foldKey == "") {
            foldKey := String(foldIndex)
        } else {
            UIMacroSchema.MigrateLegacy(foldIndex, foldKey)
        }

        raw := UIMacroSchema.ReadStoreByKey(foldKey)
        if (Trim(String(raw)) == "")
            raw := UIMacroSchema.DecodeStore(MainSoftData.UIPanelCustom)
        if (Trim(String(raw)) == "")
            return ""
        ; 单面板文件里直接就是 schema；旧格式可能包了一层 {foldIndex: schema}
        ; 两条路径统一：Parse 之后必须过 Validate，否则 0 控件 / 越界的损坏文件
        ; 会被直接拿去渲染（渲染出一堆错位控件，比降级回自动模式更难排查）。
        parsed := UIMacroSchema.Parse(raw)
        if (IsObject(parsed)) {
            pv := UIMacroSchema.Validate(parsed)
            if (!pv.ok)
                return ""
            ; 绑定控件类型迁移：枚举字段的旧输入框 → 下拉框等。
            ; 这是所有消费方的唯一咽喉，迁这里才能保证渲染出来就不是输入框。
            return UIMacroStepBinding.MigrateBindingTypes(parsed, tableItem)
        }
        try obj := JSON.parse(String(raw), , false)
        catch
            return ""
        oldKey := String(foldIndex)
        if (!IsObject(obj) || !ObjHasOwnProp(obj, oldKey))
            return ""
        try schema := UIMacroSchema.Normalize(obj.%oldKey%)
        catch
            return ""
        v := UIMacroSchema.Validate(schema)
        if (!v.ok)
            return ""
        return UIMacroStepBinding.MigrateBindingTypes(schema, tableItem)
    }

    ; 用 schema 构建浮窗。外壳（位置/透明/标题栏/拖拽）与原逻辑保持一致，
    ; 只有内容区换成 UIMacroRenderer 渲染，保证和设计器预览同源。
    ; ================= 悬浮球（收起态） =================
    ; 折叠状态记在配置里（逗号分隔的 fold 键），跨重启保留。
    _BallKey(foldIndex) {
        ctx := this._GetFoldContext(foldIndex)
        if (IsObject(ctx) && IsObject(ctx.fold) && String(ctx.fold.ID) != "")
            return String(ctx.fold.ID)
        return String(foldIndex)
    }

    _BallGet(foldIndex) {
        k := this._BallKey(foldIndex)
        for part in StrSplit(String(MainSoftData.UIPanelBall), ",") {
            if (Trim(part) == k)
                return true
        }
        return false
    }

    _BallSet(foldIndex, on) {
        k := this._BallKey(foldIndex)
        out := []
        for part in StrSplit(String(MainSoftData.UIPanelBall), ",") {
            p := Trim(part)
            if (p == "" || p == k)
                continue
            out.Push(p)
        }
        if (on)
            out.Push(k)
        str := ""
        for p in out
            str .= (str == "" ? "" : ",") p
        MainSoftData.UIPanelBall := str
        ; 不在这里直接写盘：UIPanelBall 已加入设置脏检查列表，
        ; 用户保存设置时统一落盘，避免依赖 SettingSection 的全局可见性。
    }

    ; 球 ↔ 面板切换：先标记「保留未保存改动」，再销毁重建
    _ToggleBall(panelKey, on) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info))
            return
        foldIndex := info.foldIndex
        targetHwnd := 0
        isScreen := true
        info._keepEdits := true
        targetHwnd := info.targetHwnd
        isScreen := info.isScreenMode
        ; 收起前把面板当前真实位置记进「面板」存储，展开回来仍停在原处。
        if (info.wpfHwnd && !info.HasProp("_isBall")) {
            px := 0, py := 0
            try WinGetPos(&px, &py, , , "ahk_id " info.wpfHwnd)
            if (px != 0 || py != 0)
                this._PosSave("UIPanelPos", foldIndex, px, py, targetHwnd)
        }
        this._BallSet(foldIndex, on)
        this.DestroyPanel(panelKey)
        ; 不能走 CreatePanel：它要求「目标窗口必须在前台」，而切换瞬间前台是面板自己，
        ; 会被直接拦掉，表现为「点了最小化但屏幕上什么都没有」。
        this.IsCreating := true
        try {
            pi := this.BuildXAMLPanel([], foldIndex, targetHwnd, isScreen, true, panelKey)
            if (IsObject(pi)) {
                this.PanelMap.Set(panelKey, pi)
                ; 球不需要等待就绪；展开成面板时才走完整就绪流程
                if (!on)
                    this.WaitForPanelReady(panelKey)
            }
        } finally {
            this.IsCreating := false
        }
    }

    ; ================= 位置记忆（面板 / 悬浮球 两套独立） =================
    ; 新记录按折叠框 ID 存储；窗口实例可额外按 hwnd 独立保存。
    ; 读取时兼容旧的 foldIndex 记录，并迁移到当前稳定键。
    _PositionKey(foldIndex, targetHwnd := 0) {
        ctx := this._GetFoldContext(foldIndex)
        foldKey := IsObject(ctx) ? UIMacroSchema.FoldKey(ctx.fold) : ""
        key := foldKey != "" ? foldKey : String(foldIndex)
        return targetHwnd ? key "|" String(targetHwnd) : key
    }

    _ReadPosition(raw, key) {
        for part in StrSplit(String(raw), ";") {
            p := Trim(part)
            if (p == "")
                continue
            eq := InStr(p, "=")
            if (!eq || SubStr(p, 1, eq - 1) != key)
                continue
            xy := StrSplit(SubStr(p, eq + 1), ",")
            if (xy.Length >= 2 && IsInteger(Trim(xy[1])) && IsInteger(Trim(xy[2])))
                return { x: Integer(xy[1]), y: Integer(xy[2]) }
        }
        return ""
    }

    _PosGet(store, foldIndex, targetHwnd := 0) {
        raw := (store == "UIPanelPos") ? MainSoftData.UIPanelPos : MainSoftData.UIPanelBallPos
        keys := [this._PositionKey(foldIndex, targetHwnd)]
        foldKey := this._PositionKey(foldIndex)
        legacyKey := String(foldIndex)
        if (foldKey != keys[1])
            keys.Push(foldKey)
        if (legacyKey != keys[1] && legacyKey != foldKey)
            keys.Push(legacyKey)

        for i, key in keys {
            pos := this._ReadPosition(raw, key)
            if (!IsObject(pos))
                continue
            if (i > 1)
                this._PosSave(store, foldIndex, pos.x, pos.y, targetHwnd)
            return pos
        }
        return ""
    }

    _PosSave(store, foldIndex, x, y, targetHwnd := 0) {
        global SettingSection
        key := this._PositionKey(foldIndex, targetHwnd)
        raw := (store == "UIPanelPos") ? MainSoftData.UIPanelPos : MainSoftData.UIPanelBallPos
        out := []
        for part in StrSplit(String(raw), ";") {
            p := Trim(part)
            if (p == "")
                continue
            eq := InStr(p, "=")
            if (eq && SubStr(p, 1, eq - 1) == key)
                continue
            out.Push(p)
        }
        out.Push(key "=" x "," y)
        str := ""
        for p in out
            str .= (str == "" ? "" : ";") p
        if (store == "UIPanelPos") {
            MainSoftData.UIPanelPos := str
            try CfgWrite(str, SettingFile, SettingSection, "UIPanelPos")
        } else {
            MainSoftData.UIPanelBallPos := str
            try CfgWrite(str, SettingFile, SettingSection, "UIPanelBallPos")
        }
    }

    ; 用户改了模块位置后，丢掉该模块的拖动记忆，否则新锚点会被旧坐标盖住。
    _PosForget(store, foldIndex) {
        global SettingSection
        base := this._PositionKey(foldIndex)
        legacy := String(foldIndex)
        raw := (store == "UIPanelPos") ? MainSoftData.UIPanelPos : MainSoftData.UIPanelBallPos
        out := []
        for part in StrSplit(String(raw), ";") {
            p := Trim(part)
            if (p == "")
                continue
            eq := InStr(p, "=")
            if (!eq) {
                out.Push(p)
                continue
            }
            k := SubStr(p, 1, eq - 1)
            if (k == base || k == legacy || InStr(k, base "|") == 1 || InStr(k, legacy "|") == 1)
                continue
            out.Push(p)
        }
        str := ""
        for p in out
            str .= (str == "" ? "" : ";") p
        if (store == "UIPanelPos") {
            MainSoftData.UIPanelPos := str
            try CfgWrite(str, SettingFile, SettingSection, "UIPanelPos")
        } else {
            MainSoftData.UIPanelBallPos := str
            try CfgWrite(str, SettingFile, SettingSection, "UIPanelBallPos")
        }
    }

    ; 球态窗口：短按展开，拖动后保存位置。
    _BuildCustomBall(foldIndex, targetHwnd, isScreenMode, skipActivate, panelKey := "") {
        if (panelKey == "")
            panelKey := foldIndex
        size := 56
        main := XAML_Generator("Grid").Background("Transparent")
        ball := main.Add("Border").Name("BallView").Width(size).Height(size)
            .CornerRadius(String(size // 2))
            .Background("{DynamicResource UIPanelTitleBg}")
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .Cursor("Hand")
        iconPath := A_ScriptDir "\Images\Soft\rabit.ico"
        if (FileExist(iconPath)) {
            ball.Add("Image").Name("BallIcon").Source(iconPath)
                .Width(32).Height(32).HorizontalAlignment("Center").VerticalAlignment("Center")
        } else {
            ball.Add("TextBlock").Name("BallText").Text("RMT").FontSize("13")
                .Foreground("{DynamicResource UIPanelTitleText}")
                .HorizontalAlignment("Center").VerticalAlignment("Center")
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "0")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        ; 注意不要设 Opacity="0"：面板那套流程会再改回 1，球这边没有这段流程，
        ; 设了就会「窗口存在但完全透明」，表现为点了最小化什么都没出现。
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="RMT" ShowInTaskbar="False" Width="' size '" Height="' size '"')
        ; 圆球需要真透明窗口；而 WindowChrome 与 AllowsTransparency 不能共存，
        ; 两者同时存在会导致窗口不渲染——所以把 chrome 整段去掉。
        this.ui.xaml := RegExReplace(this.ui.xaml, "s)<WindowChrome\.WindowChrome>.*?</WindowChrome\.WindowChrome>", "")
        ; 球是固定尺寸，禁掉可调整边框
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="%ResizeMode%"', 'ResizeMode="NoResize"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'AllowsTransparency="False"', 'AllowsTransparency="True"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%", "")
        this.ui.xaml := StrReplace(this.ui.xaml, "%components%", "")

        this.ui.OnEvent("BallView", "BallDrag", ObjBindMethod(this, "_OnBallGesture", panelKey))

        ; 建窗前就定好位置：否则窗口会先按 CenterScreen 出现在屏幕中间，
        ; 再被 SetWindowPos 搬走 —— 表现为「球闪一下再跳过去」。
        ballPos := this._PosGet("UIPanelBallPos", foldIndex, targetHwnd)
        if (!IsObject(ballPos))
            ballPos := this._PosGet("UIPanelPos", foldIndex, targetHwnd)
        if (IsObject(ballPos)) {
            scaleB := A_ScreenDPI / 96
            lx := Round(ballPos.x / scaleB)
            ly := Round(ballPos.y / scaleB)
            this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"'
                , 'Left="' lx '" Top="' ly '" WindowStartupLocation="Manual"')
        }

        try this.ui.Show()
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                if !skipActivate
                    WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }
        ; 再用物理坐标精确对齐一次（DIP 换算有取整误差，这一步不会造成可见跳动）
        if (IsObject(ballPos) && this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
            try DllCall("user32\SetWindowPos", "Ptr", this.ui.wpfHwnd, "Ptr", 0
                , "Int", ballPos.x, "Int", ballPos.y, "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0004)
        }

        return {
            ui: this.ui,
            wpfHwnd: this.ui.wpfHwnd ? this.ui.wpfHwnd : 0,
            panelKey: panelKey,
            foldIndex: foldIndex,
            foldID: "",
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            frontInfo: "",
            visible: true,
            btnItems: [],
            _isCustom: true,
            _isBall: true,
            ; 配置快照：与自动面板同口径，避免「配置变化检测」读到缺字段
            _cfg_BtnHeight: MainSoftData.UIPanelBtnHeight,
            _cfg_BtnWidth: MainSoftData.UIPanelBtnWidth,
            _cfg_Cols: MainSoftData.UIPanelCols,
            _cfg_FontSize: MainSoftData.UIPanelFontSize,
            _cfg_BtnColor: MainSoftData.UIPanelBtnColor,
            _cfg_BtnText: MainSoftData.UIPanelBtnText,
            _cfg_BgColor: MainSoftData.UIPanelBgColor,
            _cfg_TitleBg: MainSoftData.UIPanelTitleBg,
            _cfg_TitleText: MainSoftData.UIPanelTitleText,
            ; 球态不跟随目标窗口：跟随会把它不停拽回原位，用户拖不走
            anchorPos: 0,
            offsetX: 0,
            offsetY: 0,
            lastSetX: "",
            lastSetY: "",
            panelReady: true
        }
    }

    ; 引擎在 WPF UI 线程内完成拖动；AHK 只处理点击和最终位置。
    _OnBallGesture(panelKey, state, *) {
        if (!IsObject(state) || !state.Has("BallDrag"))
            return
        gesture := String(state["BallDrag"])
        if (gesture == "click") {
            this._BallToPanel(panelKey)
            return
        }

        parts := StrSplit(gesture, "|", , 2)
        if (parts.Length != 2 || parts[1] != "move")
            return
        coords := StrSplit(parts[2], ",", , 2)
        if (coords.Length != 2 || !IsNumber(coords[1]) || !IsNumber(coords[2]))
            return

        info := this._FindPanelInfo(panelKey)
        if (IsObject(info))
            this._PosSave("UIPanelBallPos", info.foldIndex
                , Integer(coords[1]), Integer(coords[2]), info.targetHwnd)
    }

    _BallToPanel(panelKey) {
        this._ToggleBall(panelKey, false)
    }

    ; 标题栏可命中，双击走这里关闭，不再被系统当成标题栏双击而最大化。
    ; 单击仍交给系统拖动。
    _OnTitleGrab(panelKey, state, *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !info.wpfHwnd)
            return
        onBtn := this._TitleClickOnButton(info, state)
        if (!onBtn && IsObject(state) && state.Has("ClickCount") && Integer(state["ClickCount"]) >= 2) {
            this._StopTitleDragArm()
            if (IsObject(this._PosTickFn))
                SetTimer(this._PosTickFn, 0)
            this._PosWatchHwnd := 0
            info._manualPos := false
            this._OnPanelCloseClick(panelKey)
            return
        }
        if (!onBtn)
            this._ArmTitleDrag(info)
        this._PosWatchHwnd := info.wpfHwnd
        this._PosWatchPanelKey := panelKey
        this._PosWatchFold := info.foldIndex
        this._PosWatchTargetHwnd := info.targetHwnd
        ; 记下按下时的位置：松手后若没移动过，就不写记忆（避免点一下就被当成手动位置）
        this._PosWatchStartX := 0
        this._PosWatchStartY := 0
        sx := 0, sy := 0
        try WinGetPos(&sx, &sy, , , "ahk_id " info.wpfHwnd)
        this._PosWatchStartX := sx
        this._PosWatchStartY := sy
        if (!IsObject(this._PosTickFn))
            this._PosTickFn := ObjBindMethod(this, "_PanelPosWatch")
        SetTimer(this._PosTickFn, 100)
    }

    _PanelPosWatch() {
        if (GetKeyState("LButton", "P"))
            return
        if (IsObject(this._PosTickFn))
            SetTimer(this._PosTickFn, 0)
        hwnd := this._PosWatchHwnd
        this._PosWatchHwnd := 0
        if (!hwnd)
            return
        ; 点「—」/「✕」也会先触发标题栏按下 → 定时器醒来时窗口可能已经没了。
        ; 必须先判存活，且变量要先初始化，否则 WinGetPos 失败会报「变量未赋值」。
        px := 0, py := 0
        try {
            if (DllCall("user32\IsWindow", "Ptr", hwnd))
                WinGetPos(&px, &py, , , "ahk_id " hwnd)
        } catch {
        }
        if (px == 0 && py == 0)
            return
        ; 没移动过 → 不写（点标题栏/按钮不算“手动摆位置”）
        if (px == this._PosWatchStartX && py == this._PosWatchStartY)
            return
        this._PosSave("UIPanelPos", this._PosWatchFold, px, py, this._PosWatchTargetHwnd)
        info := this._FindPanelInfo(this._PosWatchPanelKey)
        if (IsObject(info))
            info._manualPos := true
    }

    ; 事件字符串会被当成 Base64 解码，不能拿来判断 Maximized。看窗口真实状态。
    _OnPanelStateChanged(panelKey, *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !info.wpfHwnd)
            return
        if (WinGetMinMax("ahk_id " info.wpfHwnd) != 1)
            return
        this._StopTitleDragArm()
        if (IsObject(this._PosTickFn))
            SetTimer(this._PosTickFn, 0)
        this._PosWatchHwnd := 0
        info._manualPos := false
        this._PosForget("UIPanelPos", info.foldIndex)
        this._OnPanelCloseClick(panelKey)
    }

    ; 按住不动先不拖，避免把双击吃掉。鼠标移开再交给系统拖动。
    _ArmTitleDrag(info) {
        MouseGetPos(&mx, &my)
        this._dragArmHwnd := info.wpfHwnd
        this._dragArmX := mx
        this._dragArmY := my
        if (!IsObject(this._dragArmFn))
            this._dragArmFn := ObjBindMethod(this, "_PollTitleDrag")
        SetTimer(this._dragArmFn, 15)
    }

    _StopTitleDragArm() {
        if (IsObject(this._dragArmFn))
            SetTimer(this._dragArmFn, 0)
        this._dragArmHwnd := 0
    }

    _PollTitleDrag() {
        hwnd := this.HasProp("_dragArmHwnd") ? this._dragArmHwnd : 0
        if (!hwnd || !GetKeyState("LButton", "P")) {
            this._StopTitleDragArm()
            return
        }
        MouseGetPos(&mx, &my)
        if (Abs(mx - this._dragArmX) <= 4 && Abs(my - this._dragArmY) <= 4)
            return
        this._StopTitleDragArm()
        if (DllCall("user32\IsWindow", "Ptr", hwnd))
            PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
    }

    ; 点在标题栏右侧按钮或左侧页码上时，不启动拖动。
    _TitleClickOnButton(info, state) {
        if (!IsObject(state) || !state.Has("TitleBar"))
            return false
        parts := StrSplit(state["TitleBar"], ",")
        if (parts.Length < 1 || !IsNumber(Trim(parts[1])))
            return false
        x := Integer(Trim(parts[1]))
        w := 0
        try WinGetPos(, , &w, , "ahk_id " info.wpfHwnd)
        if (w > 0)
            w := w * 96 // A_ScreenDPI
        if (w > 60 && x >= w - 60)
            return true
        pages := (info.HasProp("_pages") && Integer(info._pages) > 1) ? Integer(info._pages) : 0
        return pages > 0 && x <= 6 + pages * 18
    }

    ; 标题栏「—」：收起成悬浮球
    _OnPanelBallClick(panelKey, *) {
        this._ToggleBall(panelKey, true)
    }

    ; ---------- 分页 ----------
    _panelPage := Map()   ; panelKey → 当前页

    ; 点页码：切到该页（只改可见性，不重建窗口）
    _OnPageClick(panelKey, page, *) {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema))
            return
        pages := (schema.window.HasProp("pages") ? Integer(schema.window.pages) : 1)
        cur := Max(1, Min(pages, Integer(page)))
        this._panelPage[panelKey] := cur
        this._ApplyPanelPage(panelKey, schema, pages, cur)
    }

    _ApplyPanelPage(panelKey, schema, pages, cur) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        for ctrl in schema.controls {
            pg := (ctrl.HasProp("page") ? Integer(ctrl.page) : 1)
            try info.ui.Update(UIMacroRenderer.NameOf(ctrl.id), "Visibility", pg = cur ? "Visible" : "Collapsed")
        }
        ; 当前页码：反白（底色=标题文字色、文字=标题底色），一眼能看出在哪页
        loop pages {
            on := (A_Index == cur)
            try info.ui.Update("BtnPage" A_Index, "Background", on ? "{DynamicResource UIPanelTitleText}" : "Transparent")
            try info.ui.Update("PageNum" A_Index, "Foreground", on ? "{DynamicResource UIPanelTitleBg}" : "{DynamicResource UIPanelTitleText}")
            try info.ui.Update("PageNum" A_Index, "FontWeight", on ? "Bold" : "Normal")
        }
    }

    ; 标题栏「✕」：关闭这个浮窗（记为「用户主动关闭」，避免监控立刻重建）
    _OnPanelCloseClick(panelKey, *) {
        info := this._FindPanelInfo(panelKey)
        if (IsObject(info)) {
            ; 只有用户拖动过才记住屏幕坐标。没拖过就继续按模块锚点跟随。
            if (info.wpfHwnd && !info.HasProp("_isBall") && info.HasProp("_manualPos") && info._manualPos) {
                cx := 0, cy := 0
                try WinGetPos(&cx, &cy, , , "ahk_id " info.wpfHwnd)
                if (cx != 0 || cy != 0)
                    this._PosSave("UIPanelPos", info.foldIndex, cx, cy, info.targetHwnd)
            }
            this.MarkUserClosed(panelKey)
            ; 只记 key 不够：监控对不同目标窗口用的是 foldIndex|hwnd，换一个窗口就会重建。
            ; 这里再记一个 fold 级标记，本会话内彻底不再自动弹出。
            this.UserClosedFolds[info.foldIndex] := true
        }
        this.DestroyPanel(panelKey)
    }

    _BuildCustomPanel(schema, foldIndex, targetHwnd, isScreenMode, skipActivate := false, panelKey := "") {
        if (panelKey == "")
            panelKey := foldIndex
        ; 收起态（悬浮球）优先：短按展开，拖动调整位置
        if (this._BallGet(foldIndex))
            return this._BuildCustomBall(foldIndex, targetHwnd, isScreenMode, skipActivate, panelKey)

        titleBarH := 30
        wpfBorderPad := 2
        bodyPad := 4
        pw := Integer(schema.window.width)
        contentH := Integer(schema.window.height) + bodyPad * 2
        ph := titleBarH + contentH + wpfBorderPad

        btnColor := MainSoftData.UIPanelBtnColor
        btnTextColor := MainSoftData.UIPanelBtnText
        bgColor := MainSoftData.UIPanelBgColor
        titleBg := MainSoftData.UIPanelTitleBg
        titleText := MainSoftData.UIPanelTitleText
        fontSize := Integer(MainSoftData.UIPanelFontSize)

        tableItem := GetTableBySymbol("UI")
        fold := (tableItem && tableItem.Folds.Length >= foldIndex) ? tableItem.Folds[foldIndex] : ""
        foldRemark := ""
        if (fold)
            foldRemark := fold.Remark
        if (foldRemark == "" && ObjHasOwnProp(schema.window, "title"))
            foldRemark := schema.window.title
        ; 最后一级回落：都没有就用「面板 N」，避免标题栏只剩两个按钮的空白
        if (Trim(String(foldRemark)) == "")
            foldRemark := GetLang("面板") " " foldIndex

        ; 默认位置来自模块设置。用户拖动后的记忆位置优先。
        mode := 0, anchor := 6, offX := -50, offY := 50
        this._PlaceByFold(fold, foldIndex, targetHwnd, isScreenMode, pw, ph, &initX, &initY, &mode, &anchor, &offX, &offY)
        offsetX := offX
        offsetY := offY


        main := XAML_Generator("Grid")
        main.Background("{DynamicResource UIPanelBgColor}")
        main.Rows(titleBarH, "*")

        ; 标题栏：只有一行居中的标题文字，不加任何按钮
        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("{DynamicResource UIPanelTitleBg}")
            .WindowChrome_IsHitTestVisibleInChrome("True")
        tbGrid := titleBar.Add("Grid")
        tbGrid.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("{DynamicResource UIPanelTitleText}").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")
        ; 右上角：收起成球 / 关闭浮窗。图标字形必须指定图标字体，
        ; 否则继承了正文字体，Chr(0xE921) 会渲染成空白。
        ; 分页：页数来自 schema.window.pages；窗口尺寸由 window 统一，各页天然一致。
        ; 页码直接列成小数字按钮（1 2 3 …），点哪个去哪页，比上一页/下一页直观。
        pages := (schema.window.HasProp("pages") ? Integer(schema.window.pages) : 1)
        if (pages > 1) {
            pgBar := tbGrid.Add("StackPanel").Orientation("Horizontal")
                .HorizontalAlignment("Left").VerticalAlignment("Center").Margin("4,0,0,0")
            loop pages {
                n := A_Index
                pgBtn := pgBar.Add("Button").Name("BtnPage" n)
                    .WindowChrome_IsHitTestVisibleInChrome("True")
                    .Width(16).Height(18).MinHeight(18).Margin("1,0,0,0").Padding("0").Cursor("Hand")
                    .Background("Transparent").BorderThickness("0")
                try pgBtn.InjectResources(UIMacroRenderer.BtnStyle)
                pgBtn.Add("TextBlock").Name("PageNum" n).Text(String(n))
                    .FontSize("9").Foreground("{DynamicResource UIPanelTitleText}")
                    .HorizontalAlignment("Center").VerticalAlignment("Center")
            }
        }

        tbBtns := tbGrid.Add("StackPanel").Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center").Margin("0,0,4,0")
        for pair in [["BtnPanelBall", Chr(0xE921)], ["BtnPanelClose", Chr(0xE8BB)]] {
            b := tbBtns.Add("Button").Name(pair[1])
                ; 标题栏属于 WindowChrome 的 caption 区：不声明可命中就点不动
                .WindowChrome_IsHitTestVisibleInChrome("True")
                .Width(22).Height(20).MinHeight(20).Margin("2,0,0,0")
                .Padding("0").Cursor("Hand")
                .Background("Transparent").BorderThickness("0")
            try b.InjectResources(UIMacroRenderer.BtnStyle)
            if (pair[1] == "BtnPanelBall") {
                ; 收起 = 悬浮球：直接画一个小圆点，比图标字形的「一横」更表意
                b.Add("Border").Width(8).Height(8).CornerRadius("4")
                    .Background("{DynamicResource UIPanelTitleText}")
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
            } else {
                b.Add("TextBlock").Name(pair[1] "Glyph").Text(pair[2])
                    .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
                    .FontSize("9").Foreground("{DynamicResource UIPanelTitleText}")
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
            }
        }

        body := main.Add("Grid").Grid_Row(1).Name("BodyPanel").Margin("4,4,4,4")
        ctrlMap := UIMacroRenderer.Render(body, schema, {
            fontSize: fontSize,
            btnColor: "{DynamicResource UIPanelBtnColor}",
            btnTextColor: "{DynamicResource UIPanelBtnText}",
            textColor: "{DynamicResource UIPanelBtnText}",
            inputBg: "{DynamicResource InputBg}",
            inputStroke: "{DynamicResource InputStroke}",
            inputTextColor: "{DynamicResource InputText}",
            panelWidth: pw,
            tableItem: tableItem
        })

        ; ---- 字段绑定：底部「刷新 / 写入宏」 ----
        for ctrl in schema.controls {
            if (ctrl.HasProp("binding") && IsObject(ctrl.binding)) {
                ph := titleBarH + contentH + wpfBorderPad + 34
                ; 底部一行：左边是结果提示（从左下角起），右边是按钮
                bottomRow := body.Add("Grid").VerticalAlignment("Top")
                    .HorizontalAlignment("Stretch")
                    .Margin(Format("0,{},0,0", Integer(schema.window.height) + 2))
                bottomRow.Cols("*", "Auto")
                bottomRow.Add("TextBlock").Name("WriteBackTip").Text("")
                    .Grid_Column(0)
                    .Visibility("Collapsed").FontSize(10)
                    .TextAlignment("Left").VerticalAlignment("Center")
                    .HorizontalAlignment("Left").Margin("2,0,8,0")
                    .Foreground("{DynamicResource TextMain}")
                    .TextTrimming("CharacterEllipsis")
                bottomBar := bottomRow.Add("StackPanel").Grid_Column(1)
                    .Orientation("Horizontal")
                    .HorizontalAlignment("Right").VerticalAlignment("Top")
                wb := bottomBar.Add("Button").Name("BtnWriteBack").Content("写入宏")
                    .Width(76).Height(26).MinHeight(26)
                    .FontSize(11).Padding("0").Cursor("Hand")
                    .Foreground("{DynamicResource UIPanelBtnText}")
                    .Background("{DynamicResource UIPanelBtnColor}")
                    .BorderThickness("0")
                wb.InjectResources(UIMacroRenderer.BtnStyle)
                break
            }
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleBarH)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", "")

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" ShowInTaskbar="False" Width="' pw '" Height="' ph '"')
        ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'Left="' initX '" Top="' initY '" WindowStartupLocation="Manual"')
        ; 同自动浮窗：不透明，避免和 WindowChrome 叠在一起后整窗变黑。
        ui.xaml := StrReplace(ui.xaml, 'Background="Transparent"', 'Background="' bgColor '"')

        panelResources := '<SolidColorBrush x:Key="UIPanelBtnColor" Color="' btnColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelBtnText" Color="' btnTextColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelBgColor" Color="' bgColor '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleBg" Color="' titleBg '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleText" Color="' titleText '"/>'
        ui.xaml := StrReplace(ui.xaml, '%resources%', panelResources)
        ui.xaml := StrReplace(ui.xaml, '%components%', '')

        ; 事件：按全局宏 ID 定位所属表，不依赖固定 UI 表或行号。
        for id, info in ctrlMap {
            ctrl := UIMacroSchema.FindById(schema, id)
            if (!IsObject(ctrl) || !IsObject(ctrl.action))
                continue
            if (!ObjHasOwnProp(ctrl.action, "cmd") || ctrl.action.cmd != "RunMacro")
                continue
            ; 只有按钮/勾选框是「点了跑宏」。输入框/下拉框身上带 macroId 只是为了让设计器
            ; 知道「字段候选来自哪个宏」，绝不能在这里挂点击触发，否则点输入框就执行宏。
            if (ctrl.type != "Button" && ctrl.type != "CheckBox")
                continue
            macroId := String(ctrl.action.macroId)
            targetTable := ""
            try targetTable := GetItemTableGlobal(macroId)
            targetIndex := targetTable ? GetItemIndexInTable(targetTable, macroId) : 0
            if (!targetTable || !targetIndex)
                continue
            if (ctrl.type == "CheckBox") {
                ui.OnEvent(info.name, "Checked", ObjBindMethod(this, "_OnBtnClick", macroId, panelKey))
                ui.OnEvent(info.name, "Unchecked", ObjBindMethod(this, "_OnBtnClick", macroId, panelKey))
            } else {
                ui.OnEvent(info.name, "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnBtnClick", macroId, panelKey))
            }
        }
        try ui.OnEvent("BtnWriteBack", "Click", ObjBindMethod(this, "_OnWriteBack", panelKey))
        ; 用户拖标题栏移动面板：松手后记住位置
        try ui.OnEvent("TitleBar", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTitleGrab", panelKey))
        if (pages > 1) {
            loop pages
                try ui.OnEvent("BtnPage" A_Index, "Click", ObjBindMethod(this, "_OnPageClick", panelKey, A_Index))
        }
        ; 标题栏右上角两个按钮：收起成球 / 关闭浮窗
        try ui.OnEvent("BtnPanelBall", "Click", ObjBindMethod(this, "_OnPanelBallClick", panelKey))
        try ui.OnEvent("BtnPanelClose", "Click", ObjBindMethod(this, "_OnPanelCloseClick", panelKey))
        ; 双击标题：系统会先把它最大化，这里收到状态变化后关闭浮窗
        try ui.OnEvent("Window", "StateChanged", ObjBindMethod(this, "_OnPanelStateChanged", panelKey))

        ; 绑定控件的改动会即时更新内存，关闭面板时由快照决定是否还原。
        for ctrl in schema.controls {
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            name := UIMacroRenderer.NameOf(ctrl.id)
            bindCopy := ctrl.binding
            if (ctrl.type == "Edit") {
                try ui.OnEvent(name, "TextChanged", ObjBindMethod(this, "_OnBoundEdit", panelKey, ctrl.id, bindCopy))
            } else if (ctrl.type == "CheckBox") {
                try ui.OnEvent(name, "Checked", ObjBindMethod(this, "_OnBoundCheck", panelKey, ctrl.id, bindCopy, 1))
                try ui.OnEvent(name, "Unchecked", ObjBindMethod(this, "_OnBoundCheck", panelKey, ctrl.id, bindCopy, 0))
            } else if (ctrl.type == "ComboBox") {
                bindingTable := this._TableForBinding(ctrl.binding)
                spec := UIMacroStepBinding.SpecOfBinding(bindingTable, ctrl.binding)
                if (IsObject(spec) && String(spec.type) == "enum")
                    try ui.OnEvent(name, "SelectionChanged", ObjBindMethod(this, "_OnBoundCombo", panelKey, ctrl.id, bindCopy, spec))
            }
        }

        ; 面板只自带了 5 个 UIPanel* 刷子，但渲染器还引用了 {DynamicResource InputBg}
        ; / {DynamicResource InputStroke} 等——这些刷子在面板窗口作用域里不存在时
        ; WPF 会回退成系统白底（表现为输入框/下拉框是白块）。通用颜色由统一入口提供，
        ; UIPanel* 保留当前浮窗自定义值，不被通用主题颜色覆盖。
        ui._preserveUIPanelColors := true
        try AppThemeUtil.ApplyWinThemeToXaml(ui)
        ui.Show()

        loop 20 {
            if (ui.HasProp("wpfHwnd") && ui.wpfHwnd) {
                if !skipActivate
                    WinActivate("ahk_id " ui.wpfHwnd)
                break
            }
            Sleep(50)
        }

        ; 分页：初始只显示第 1 页（其余页的元素先隐藏，切页时再显示）
        if (pages > 1) {
            this._panelPage[panelKey] := 1
            for ctrl in schema.controls {
                pg := (ctrl.HasProp("page") ? Integer(ctrl.page) : 1)
                if (pg != 1)
                    try ui.Update(UIMacroRenderer.NameOf(ctrl.id), "Visibility", "Collapsed")
            }
            try ui.Update("BtnPage1", "Background", "{DynamicResource UIPanelTitleText}")
            try ui.Update("PageNum1", "Foreground", "{DynamicResource UIPanelTitleBg}")
            try ui.Update("PageNum1", "FontWeight", "Bold")
        }

        return {
            ui: ui,
            wpfHwnd: ui.wpfHwnd ? ui.wpfHwnd : 0,
            panelKey: panelKey,
            foldIndex: foldIndex,
            foldID: fold ? fold.ID : "",
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            frontInfo: fold ? fold.FrontInfo : "",
            visible: true,
            btnItems: [],
            _isCustom: true,
            _pages: pages,
            posMode: mode,
            anchor: anchor,
            offsetX: offsetX,
            offsetY: offsetY,
            lastSetX: "",
            lastSetY: "",
            panelReady: false,
            _cfg_BtnHeight: MainSoftData.UIPanelBtnHeight,
            _cfg_BtnWidth: MainSoftData.UIPanelBtnWidth,
            _cfg_Cols: MainSoftData.UIPanelCols,
            _cfg_FontSize: fontSize,
            _cfg_BtnColor: btnColor,
            _cfg_BtnText: btnTextColor,
            _cfg_BgColor: bgColor,
            _cfg_TitleBg: titleBg,
            _cfg_TitleText: titleText
        }
    }

    ; 等待窗口就绪并执行初始化（= floating_panel WaitForHwnd L352-361 + OnPanelReady L363-389）
    WaitForPanelReady(panelKey) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!panelInfo)
            return

        ; 对齐 WaitForHwnd L352-361：循环等待wpfHwnd
        loop 50 {
            if (panelInfo.ui && panelInfo.ui.HasProp("wpfHwnd") && panelInfo.ui.wpfHwnd) {
                ; 对齐 L355: g_panelReady := true
                panelInfo.panelReady := true
                ; 对齐 L356: OnPanelReady()
                this.OnPanelReady(panelKey)
                return
            }
            Sleep(50)
        }
    }

    ; 面板就绪后的初始化（严格对齐 floating_panel OnPanelReady L363-389）
    OnPanelReady(panelKey) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!panelInfo)
            return

        ; L364-L366: 设置 NativeOwner
        if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
            try panelInfo.ui.Update("Window", "NativeOwner", String(panelInfo.targetHwnd))
        }

        ; L373-L375: 设置窗口扩展样式 + 精简系统菜单（保留关闭，供标题栏右键）
        hwnd := panelInfo.wpfHwnd
        if (hwnd) {
            exStyle := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
            DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int"
                , exStyle | 0x80)
            ; 精简系统菜单项，保留 SC_CLOSE / SC_MOVE；置顶时菜单层级由引擎 SysMenu 事件配合处理
            hSysMenu := DllCall("user32\GetSystemMenu", "Ptr", hwnd, "Int", 0, "Ptr")
            if (hSysMenu) {
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF020, "UInt", 0)  ; SC_MINIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF000, "UInt", 0)  ; SC_SIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF030, "UInt", 0)  ; SC_MAXIMIZE
                DllCall("user32\DeleteMenu", "Ptr", hSysMenu, "UInt", 0xF120, "UInt", 0)  ; SC_RESTORE
            }
            ; 系统菜单打开期间暂停 AHK 侧反复 WinSetAlwaysOnTop，避免把菜单重新压到下面
            try panelInfo.ui.OnEvent("Window", "SysMenu", ObjBindMethod(this, "OnPanelSysMenu", panelKey))
        }

        ; L377-L384: 模式分支初始化
        if (panelInfo.isScreenMode) {
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            ; 记下「已经置顶过」：紧随其后的 FollowSinglePanel 就不会再调一次
            panelInfo._topmostDone := true
        } else {
            DllCall("user32\SetWindowPos"
                , "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0002 | 0x0001 | 0x0004 | 0x0010 | 0x0020)
        }

        ; L387: 立即执行一次跟随
        this.FollowSinglePanel(panelKey)

        ; L388: 启动定时器
        this.StartFollowTimer(panelKey)

        ; 绑定字段：面板就绪后把宏值填进控件
        this._FillBindings(panelKey)
    }

    ; ------------------------------------------------------------------
    ; 屏幕模式置顶：只做一次 + 系统菜单期间暂停 + 事件丢失自愈
    ;
    ; 为什么不能每 tick 无条件 WinSetAlwaysOnTop：
    ;   引擎收到标题栏菜单的 WM_ENTERMENULOOP 会先把窗口 HWND_NOTOPMOST，再**异步**
    ;   post SysMenu|Open 给 AHK；这中间的空档里定时器若又把面板置顶，菜单就被压到
    ;   面板下方而立刻关闭（用户看到「闪一下」）。所以用 _topmostDone 记状态、只设一次。
    ;
    ; 为什么要超时自愈：
    ;   _suspendTopmost 只有 OnPanelSysMenu 一处写。若 SysMenu|Close 事件丢失
    ;   （菜单期间异常退出等），它会永久为 true、_topmostDone 也是 true →
    ;   面板此后再也不置顶且没有任何恢复路径。超过 3 秒视为事件丢失，强制复位。
    ; ------------------------------------------------------------------
    _EnsureTopmost(panelInfo, hwnd) {
        if (!IsObject(panelInfo) || !hwnd)
            return
        topmostDone := (panelInfo.HasProp("_topmostDone") && panelInfo._topmostDone)
        suspended := (panelInfo.HasProp("_suspendTopmost") && panelInfo._suspendTopmost)
        if (suspended && panelInfo.HasProp("_suspendAt") && panelInfo._suspendAt != ""
            && (A_TickCount - panelInfo._suspendAt) > 3000) {
            panelInfo._suspendTopmost := false
            panelInfo._suspendAt := ""
            panelInfo._topmostDone := false
            suspended := false
            topmostDone := false
        }
        if (!suspended && !topmostDone) {
            try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            panelInfo._topmostDone := true
        }
    }

    ; 跟随逻辑（严格逐行对齐 floating_panel FollowTarget L391-440 + MovePanel L171-179）
    FollowSinglePanel(panelKey) {
        if (!this.PanelMap.Has(panelKey))
            return
        panelInfo := this.PanelMap[panelKey]
        ; 用户手动摆过位置 → 不再跟随目标窗口（否则每个 tick 都会被拽回锚点）
        if (IsObject(this._PosGet("UIPanelPos", panelInfo.foldIndex, panelInfo.targetHwnd)))
            return

        ; L392: if (!g_panelReady) return
        if (!panelInfo.panelReady)
            return

        ; L394-L396: 获取hwnd并验证
        hwnd := panelInfo.wpfHwnd
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
            return

        ; L398-L409: 屏幕模式分支
        if (panelInfo.isScreenMode) {
            this._EnsureTopmost(panelInfo, hwnd)
            return
        }

        ; L411-L416: 目标窗口检查
        if (!panelInfo.targetHwnd)
            return
        if (!DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
            this.DestroyPanel(panelKey)
            return
        }

        ; ====== 目标窗口矩形 + 面板尺寸 ======
        rect := this.GetWindowRectCoords(panelInfo.targetHwnd)
        winW := rect["right"] - rect["left"]
        winH := rect["bottom"] - rect["top"]
        panelRect := this.GetWindowRectCoords(hwnd)
        pw := panelRect["right"] - panelRect["left"]
        ph := panelRect["bottom"] - panelRect["top"]
        if (winW <= 0)
            winW := A_ScreenWidth
        if (winH <= 0)
            winH := A_ScreenHeight
        if (pw <= 0)
            pw := 250
        if (ph <= 0)
            ph := 200

        ; 绝对坐标固定在屏幕上。相对坐标跟随目标窗口，锚点随窗口尺寸变化。
        mode := panelInfo.HasProp("posMode") ? panelInfo.posMode : 0
        if (mode == 1) {
            if (panelInfo.lastSetX != "" && panelInfo.lastSetY != "") {
                devX := Abs(panelRect["left"] - panelInfo.lastSetX)
                devY := Abs(panelRect["top"] - panelInfo.lastSetY)
                if (devX > 3 || devY > 3) {
                    panelInfo.offsetX := panelRect["left"]
                    panelInfo.offsetY := panelRect["top"]
                }
            }
            newX := panelInfo.offsetX
            newY := panelInfo.offsetY
        } else {
            anchorX := 0, anchorY := 0
            anchor := panelInfo.HasProp("anchor") ? panelInfo.anchor : 6
            this._AnchorBase(anchor, pw, ph, winW, winH, &anchorX, &anchorY)
            if (panelInfo.lastSetX != "" && panelInfo.lastSetY != "") {
                devX := Abs(panelRect["left"] - panelInfo.lastSetX)
                devY := Abs(panelRect["top"] - panelInfo.lastSetY)
                if (devX > 3 || devY > 3) {
                    panelInfo.offsetX := panelRect["left"] - rect["left"] - anchorX
                    panelInfo.offsetY := panelRect["top"] - rect["top"] - anchorY
                }
            }
            newX := rect["left"] + anchorX + panelInfo.offsetX
            newY := rect["top"] + anchorY + panelInfo.offsetY
        }
        ownerHwnd := panelInfo.targetHwnd
        DllCall("user32\SetWindowPos"
            , "Ptr", hwnd
            , "Ptr", ownerHwnd
            , "Int", newX, "Int", newY
            , "Int", 0, "Int", 0
            , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
        ; 记录本次设置的目标位置，供下次回调对比
        panelInfo.lastSetX := newX
        panelInfo.lastSetY := newY
    }

    ; 切换可见性（严格对齐 floating_panel TogglePanelVisibility L490-513）
    TogglePanel(foldIndex) {
        ; 用户主动打开 → 解除「已关闭」，恢复自动显示
        if (this.UserClosedFolds.Has(foldIndex))
            this.UserClosedFolds.Delete(foldIndex)
        ; 创建进行中：忽略本次触发，避免在 PanelMap 写入前重入创建出重复面板
        if (this.IsCreating)
            return

        tableItem := GetTableBySymbol("UI")
        ; 每次触发实时读取，避免编辑前台后仍用旧判断
        frontInfo := ""
        if (tableItem) {
            fold := tableItem.Folds[foldIndex]
            if (fold)
                frontInfo := fold.FrontInfo
        }

        targetHwnd := 0
        panelKey := foldIndex

        ; ====== 前置守卫：有前台信息时，以鼠标所在窗口为准（不用焦点窗口） ======
        ; 与按键宏 TriggerKeyData / TimingUtil 一致，走 MyMouseInfo.CheckIfMatch
        if (frontInfo != "") {
            if (MyMouseInfo.CheckIfMatch(frontInfo, true)) {
                ; 鼠标在对应前台窗口上 → 允许开关该实例
                targetHwnd := Integer(MyMouseInfo.WinId)
                panelKey := foldIndex "|" targetHwnd
            } else {
                ; 鼠标在本模块浮窗上：仅当该浮窗绑定的目标仍匹配当前前台信息时允许
                ; （方便在按钮上按触发键隐藏；目标已不符则视为非对应前台，无效）
                mouseHwnd := MyMouseInfo.HasError ? 0 : Integer(MyMouseInfo.WinId)
                matched := false
                if (mouseHwnd) {
                    for key, panelInfo in this.PanelMap {
                        if (panelInfo.foldIndex != foldIndex || panelInfo.wpfHwnd != mouseHwnd)
                            continue
                        if (panelInfo.targetHwnd && this.IsHwndMatchFrontInfo(panelInfo.targetHwnd, frontInfo)) {
                            targetHwnd := panelInfo.targetHwnd
                            panelKey := key
                            matched := true
                        }
                        break
                    }
                }
                if (!matched)
                    return
            }
        }

        if (!this.PanelMap.Has(panelKey)) {
            this.ClearUserClosed(panelKey)  ; 热键主动打开：清除「用户关闭」标记
            if (targetHwnd)
                this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            else
                this.CreatePanel(foldIndex)
            return
        }

        panelInfo := this.PanelMap[panelKey]
        if (!panelInfo.ui || !panelInfo.wpfHwnd)
            return

        ; 配置变化检测：按钮尺寸/列数/颜色变化时销毁重建
        if (panelInfo.visible == false  ; 只在从隐藏→显示时检查
            && (panelInfo._cfg_BtnHeight != MainSoftData.UIPanelBtnHeight
                || panelInfo._cfg_BtnWidth != MainSoftData.UIPanelBtnWidth
                || panelInfo._cfg_Cols != MainSoftData.UIPanelCols
                || panelInfo._cfg_FontSize != MainSoftData.UIPanelFontSize
                || panelInfo._cfg_BtnColor != MainSoftData.UIPanelBtnColor
                || panelInfo._cfg_BtnText != MainSoftData.UIPanelBtnText
                || panelInfo._cfg_BgColor != MainSoftData.UIPanelBgColor
                || panelInfo._cfg_TitleBg != MainSoftData.UIPanelTitleBg
                || panelInfo._cfg_TitleText != MainSoftData.UIPanelTitleText)) {
            this.ClearUserClosed(panelKey)
            this.DestroyPanel(panelKey)
            if (targetHwnd)
                this.CreateAutoPanel(foldIndex, panelKey, targetHwnd)
            else
                this.CreatePanel(foldIndex)
            return
        }

        ; 切换可见性
        panelInfo.visible := !panelInfo.visible
        hwnd := panelInfo.wpfHwnd
        if (!hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd))
            return

        if (panelInfo.visible) {
            panelInfo.userClosed := false
            this.ClearUserClosed(panelKey)
            ; 重新显示后要让跟随定时器再置顶一次（配合 _topmostDone 的「只设一次」）
            panelInfo._topmostDone := false
            ; SW_SHOWNA：显示但不抢焦点，保持鼠标下仍是目标窗，下次触发判断更稳定
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 8)
            ; 没拖动过：按模块位置重新摆放并继续跟随。拖动过：Apply 会优先用记忆坐标。
            this._ResetPosFromFold(panelInfo)
            panelInfo.lastSetX := ""
            panelInfo.lastSetY := ""
            this.ApplyPanelPosition(panelInfo)
        } else {
            ; 拖动过才记下屏幕坐标，避免一次隐藏就把相对跟随钉死。
            if (panelInfo.wpfHwnd && !panelInfo.HasProp("_isBall") && panelInfo.HasProp("_manualPos") && panelInfo._manualPos) {
                px := 0, py := 0
                try WinGetPos(&px, &py, , , "ahk_id " panelInfo.wpfHwnd)
                if (px != 0 || py != 0)
                    this._PosSave("UIPanelPos", foldIndex, px, py, panelInfo.targetHwnd)
            }
            panelInfo.userClosed := true
            this.MarkUserClosed(panelKey)
            ; 隐藏 = 用户不再看这个面板：没点写入宏的改动要还原
            this._RestoreMacroSnapshot(panelInfo)
            DllCall("user32\ShowWindow", "Ptr", hwnd, "Int", 0)
        }
    }

    ; 引擎通知：标题栏系统菜单打开/关闭（暂停/恢复 AlwaysOnTop 重刷）
    ; 回调参数：(stateMap, "Window", "SysMenu")，Open/Close 在 stateMap["SysMenu"]
    OnPanelSysMenu(panelKey, state := unset, ctrl := unset, event := unset) {
        if (!this.PanelMap.Has(panelKey))
            return
        panelInfo := this.PanelMap[panelKey]
        isOpen := false
        if (IsSet(state) && IsObject(state) && state.Has("SysMenu"))
            isOpen := (state["SysMenu"] = "Open")
        ; 关键：打开菜单时只置 _suspendTopmost，**不要**动 _topmostDone。
        ; 若在这里把 _topmostDone 复位，等于放开定时器重新置顶，竞态立刻回来。
        panelInfo._suspendTopmost := isOpen
        if (isOpen) {
            ; 记时间戳，供 _EnsureTopmost 在 Close 事件丢失时超时自愈
            panelInfo._suspendAt := A_TickCount
            return
        }
        panelInfo._suspendAt := ""
        if (panelInfo.isScreenMode && panelInfo.visible && panelInfo.wpfHwnd) {
            ; 置顶成功才写标记：写在外面等于「失败也宣称成功」，之后不会再补
            try {
                WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
                panelInfo._topmostDone := true
            }
        }
    }

    ; 销毁指定模块的全部面板（前台信息变更时清理旧目标实例）
    DestroyFoldPanels(foldIndex) {
        keys := []
        for key, panelInfo in this.PanelMap {
            if (panelInfo.foldIndex == foldIndex)
                keys.Push(key)
        }
        for key in keys
            this.DestroyPanel(key)
    }

    ; 销毁面板（严格对齐 floating_panel ClosePanel L515-523）
    DestroyPanel(panelKey) {
        if (!this.PanelMap.Has(panelKey))
            return

        ; L517: 停止定时器（对齐 SetTimer(FollowTarget, 0)）
        this.StopFollowTimer(panelKey)

        panelInfo := this.PanelMap[panelKey]
        ; 面板要没了：把「只改了内存、没点写入宏」的宏文本还原回去。
        ; 折叠成球时例外：改动仍在内存里，展开后应原样还在。
        if (!(panelInfo.HasProp("_keepEdits") && panelInfo._keepEdits))
            this._RestoreMacroSnapshot(panelInfo)
        ; L518-L520: 关闭窗口
        if (panelInfo.ui) {
            try panelInfo.ui.Update("Window", "Close", "")
        }
        if (this._panelPage.Has(panelKey))
            this._panelPage.Delete(panelKey)
        if (this._TipTimers.Has(panelKey)) {
            SetTimer(this._TipTimers[panelKey], 0)
            this._TipTimers.Delete(panelKey)
        }
        ; L521-L522: 清理
        if (this.PanelMap.Has(panelKey))
            this.PanelMap.Delete(panelKey)
    }

    ; 屏幕模式面板的定期检查（对齐 FollowTarget 中 L398-L409 的screenMode分支）
    CheckAllPanels() {
        deadFolds := []
        for panelKey, panelInfo in this.PanelMap {
            ; 非屏幕模式面板：目标窗口已关闭则自动销毁
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd
                && !DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
                deadFolds.Push(panelKey)
                continue
            }
            ; 面板窗口已失效（被关闭）：视为用户主动关闭，禁止随后点主界面自动重建
            if (!panelInfo.ui || !panelInfo.wpfHwnd || !WinExist("ahk_id " panelInfo.wpfHwnd)) {
                this.MarkUserClosed(panelKey)
                deadFolds.Push(panelKey)
                continue
            }

            ; 處理目標視窗隱藏/退到後台時，浮窗隱藏；重新顯現時浮窗也重新顯現
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                ; 檢查目標視窗是否最小化 (WinGetMinMax 傳回 -1 代表最小化) 或不可見
                try {
                    isMin := WinGetMinMax("ahk_id " panelInfo.targetHwnd) == -1
                    targetVisible := !isMin && DllCall("user32\IsWindowVisible", "Ptr", panelInfo.targetHwnd)
                } catch {
                    targetVisible := false
                }
                
                if (!targetVisible && panelInfo.visible) {
                    panelInfo.visible := false
                    panelInfo.targetWasHidden := true
                    DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 0) ; SW_HIDE
                } else if (targetVisible && !panelInfo.visible && (panelInfo.HasProp("targetWasHidden") && panelInfo.targetWasHidden)) {
                    panelInfo.visible := true
                    panelInfo.targetWasHidden := false
                    DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 8) ; SW_SHOWNA
                    this.ApplyPanelPosition(panelInfo)
                }
            }

            if (!panelInfo.isScreenMode)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd
            ; 与 FollowSinglePanel 共用同一套闸门（只设一次 + 菜单期间暂停 + 超时自愈）
            this._EnsureTopmost(panelInfo, hwnd)
        }
        ; 清理已关闭的面板残留条目（DestroyPanel 会关闭窗口 + 停止定时器）
        for panelKey in deadFolds {
            this.DestroyPanel(panelKey)
        }

        ; 用户主动关闭浮窗（右键关闭 / Alt+F4）会引起焦点切换，若不处理，下面的"激活时默认显示"
        ; 会把这次焦点变化当成窗口切换而立即重建面板。这里把 _lastActiveHwnd 同步为关闭后的
        ; 当前前台窗口，使其不立即重建，等到下次真正切换窗口时再显示 —— 与快捷键隐藏的行为一致。
        if (deadFolds.Length > 0) {
            try this._lastActiveHwnd := WinGetID("A")
        }

        ; ====== 界面激活时默认显示（同时支持有前台和无前台模块） ======
        try {
            ; 正在创建面板时跳过：避免创建过程中（BuildXAMLPanel 的 Sleep 泵消息）重入建出重复面板
            if (!this.IsCreating && MainSoftData.UIPanelShowOnActive) {
                activeHwnd := WinGetID("A")
                if (activeHwnd != this._lastActiveHwnd) {
                    this._lastActiveHwnd := activeHwnd

                    tableItem := GetTableBySymbol("UI")
                    if (tableItem) {
                        for foldIndex, fold in tableItem.Folds {
                            ; 用户点过 ✕ → 这次会话内不再自动弹回来（快捷键/点按钮仍可打开）
                            if (this.UserClosedFolds.Has(foldIndex))
                                continue
                            if (fold.ForbidState)
                                continue

                            frontInfo := fold.FrontInfo
                            if (frontInfo == "") {
                                ; 无前台模块（屏幕模式）：仅当 RMT 主界面被激活时才创建/显示，
                                ; 避免点击任务栏或切到其它任意窗口也把已关闭的浮窗重新弹出。
                                mainHwnd := (IsObject(MainSoftData.MyGui) && MainSoftData.MyGui.HasProp("Hwnd")) ? MainSoftData.MyGui.Hwnd : 0
                                if (!mainHwnd || activeHwnd != mainHwnd)
                                    continue
                                panelKey := foldIndex
                                if (this.IsUserClosed(panelKey))
                                    continue
                                if (!this.PanelMap.Has(panelKey))
                                    this.CreateAutoPanel(foldIndex, panelKey, 0)
                                else
                                    this.ShowAutoPanel(panelKey)
                            } else if (activeHwnd && this.IsHwndMatchFrontInfo(activeHwnd, frontInfo)) {
                                ; 有前台模块：面板键为 foldIndex|hwnd（每个窗口实例独立面板）
                                panelKey := foldIndex "|" activeHwnd
                                if (this.IsUserClosed(panelKey))
                                    continue
                                if (!this.PanelMap.Has(panelKey))
                                    this.CreateAutoPanel(foldIndex, panelKey, activeHwnd)
                                else
                                    this.ShowAutoPanel(panelKey)
                            }
                        }
                    }
                }
            }
        } catch {
        }
    }

    ; 启动跟随定时器（对齐 floating_panel L388: SetTimer(FollowTarget, 50)）
    StartFollowTimer(panelKey) {
        if (this.PanelTimers.Has(panelKey)) {
            oldCb := this.PanelTimers[panelKey]
            if (oldCb)
                SetTimer(oldCb, 0)
        }
        cb := this.FollowSinglePanel.Bind(this, panelKey)
        this.PanelTimers[panelKey] := cb
        SetTimer(cb, 50)
    }

    ; 停止跟随定时器（对齐 floating_panel L517: SetTimer(FollowTarget, 0)）
    StopFollowTimer(panelKey) {
        if (!this.PanelTimers.Has(panelKey))
            return
        cb := this.PanelTimers[panelKey]
        if (cb)
            SetTimer(cb, 0)
        this.PanelTimers.Delete(panelKey)
    }

    ; ========== 宏执行逻辑 ==========

    ; ObjBindMethod 转发器（ObjBindMethod 固定参数值，避免闭包捕获循环变量的引用问题）
    _OnBtnClick(macroId, panelKey, *) {
        this.OnButtonClick(macroId, panelKey)
    }

    OnButtonClick(macroId, panelKey, *) {
        try {
            tableItem := GetItemTableGlobal(String(macroId))
            if (!tableItem)
                return
            macroIndex := GetItemIndexInTable(tableItem, String(macroId))
            item := macroIndex ? tableItem.Items[macroIndex] : ""
            if (!item || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, macroIndex))
                return

            if (!item.Macro)
                return

            if (tableItem.Symbol == "UI") {
                if (this.IsMacroRunning(macroIndex))
                    this.StopMacro(macroIndex)
                else
                    this.StartMacro(macroIndex)
            } else {
                if (item.ColorState > 0)
                    MyStopMacro(tableItem, item.ID)
                else
                    TriggerMacroHandler(tableItem, item)
            }

            ; 点击后面板抢走了焦点 → 立即将焦点还给目标窗口
            this.RestoreTargetFocus(panelKey)
        }
        catch as e {
        }
    }

    ; 点击实例的面板按钮后恢复该实例的目标窗口焦点。
    RestoreTargetFocus(panelKey) {
        if (!this.PanelMap.Has(panelKey))
            return
        panelInfo := this.PanelMap[panelKey]
        if (panelInfo.targetHwnd && DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd))
            WinActivate("ahk_id " panelInfo.targetHwnd)
    }

    IsMacroRunning(macroIndex) {
        return (this.RunningMap.Has(macroIndex)
            && this.RunningMap[macroIndex].IsRunning)
    }

    StartMacro(macroIndex) {
        if (this.IsMacroRunning(macroIndex))
            return

        tableItem := GetTableBySymbol("UI")
        item := tableItem ? tableItem.Items[macroIndex] : ""
        if (!item)
            return
        macroStr := item.Macro

        this.CancelRecoverTimer(macroIndex)

        actionObj := this
        action := (*) => (
            RunMacroTrigger(tableItem, macroStr, macroIndex),
            SetTimer(() => actionObj.OnMacroComplete(macroIndex), -10)
        )

        this.RunningMap[macroIndex] := {IsRunning: true, TimerAction: action}
        SetTimer(action, -1)
        MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_RUNNING)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_RUNNING)
    }

    StopMacro(macroIndex) {
        tableItem := GetTableBySymbol("UI")

        this.CancelRecoverTimer(macroIndex)

        if (tableItem && tableItem.Items.Has(macroIndex)) {
            item := tableItem.Items[macroIndex]
            item.Killed := true
            item.Pause := false
        }

        if (this.RunningMap.Has(macroIndex))
            this.RunningMap.Delete(macroIndex)

        MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_STOPPED)
        this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_STOPPED)
    }

    OnMacroComplete(macroIndex) {
        if (this.IsMacroRunning(macroIndex)) {
            this.RunningMap.Delete(macroIndex)
            this.CancelRecoverTimer(macroIndex)
            tableItem := GetTableBySymbol("UI")
            if (tableItem)
                MySetTableItemState(tableItem, macroIndex, UIMacroGui.STATE_DEFAULT)
            this.UpdateButtonStatus(macroIndex, UIMacroGui.STATE_DEFAULT)
        }
    }

    ; 更新按钮状态色点
    UpdateButtonStatus(macroIndex, state) {
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.ui || !panelInfo.btnItems)
                continue
            for item in panelInfo.btnItems {
                if (item.macroIndex == macroIndex) {
                    stateName := item.name "_State"
                    try {
                        if (state == UIMacroGui.STATE_DEFAULT) {
                            panelInfo.ui.Update(stateName, "Visibility", "Collapsed")
                        } else if (MacroStateColors.Has(state)) {
                            color := MacroStateColors[state]
                            panelInfo.ui.Update(stateName, "Visibility", "Visible")
                            panelInfo.ui.Update(stateName, "Fill", color)
                        }
                    }
                    ; ui.Update() 后恢复位置（对齐 MovePanel L171-179）
                    if (!panelInfo.isScreenMode && panelInfo.panelReady && panelInfo.visible
                        && panelInfo.wpfHwnd && panelInfo.targetHwnd
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.wpfHwnd)
                        && DllCall("user32\IsWindow", "Ptr", panelInfo.targetHwnd)) {
                        targetRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                        winW := targetRect["right"] - targetRect["left"]
                        winH := targetRect["bottom"] - targetRect["top"]
                        pr := this.GetWindowRectCoords(panelInfo.wpfHwnd)
                        pw := pr["right"] - pr["left"]
                        ph := pr["bottom"] - pr["top"]
                        restoreX := 0, restoreY := 0
                        this._PanelScreenPos(panelInfo, targetRect["left"], targetRect["top"], winW, winH, pw, ph, &restoreX, &restoreY)
                        DllCall("user32\SetWindowPos"
                            , "Ptr", panelInfo.wpfHwnd, "Ptr", panelInfo.targetHwnd
                            , "Int", restoreX, "Int", restoreY
                            , "Int", 0, "Int", 0
                            , "UInt", 0x0001 | 0x0004 | 0x0010 | 0x4000)
                    }
                    break
                }
            }
        }
    }

    UpdateButtonsState(macroIndex, state) {
        this.UpdateButtonStatus(macroIndex, state)
    }

    CancelRecoverTimer(macroIndex) {
        if (this.RecoverTimers.Has(macroIndex)) {
            oldTimer := this.RecoverTimers[macroIndex]
            if (oldTimer)
                SetTimer(oldTimer, 0)
            this.RecoverTimers.Delete(macroIndex)
        }
    }

    HideAllPanels() {
        for foldIndex in this.PanelTimers.Clone() {
            this.StopFollowTimer(foldIndex)
        }
        for foldIndex, panelInfo in this.PanelMap.Clone() {
            try {
                if (panelInfo.ui)
                    panelInfo.ui.Update("Window", "Close", "")
            }
        }
        this.PanelMap.Clear()
    }

    ; §15.5 RMT指令「打开界面窗口」：为界面宏表全部可用折叠框创建并显示面板；
    ; 没有可用的界面窗口时无操作（调用方据此判断「指令无效」）
    ShowAllPanels() {
        tableItem := GetTableBySymbol("UI")
        if (!tableItem)
            return
        loop tableItem.Folds.Length {
            foldIndex := A_Index
            fold := tableItem.Folds[foldIndex]
            if (!fold || fold.ForbidState)
                continue
            ctx := this._GetFoldContext(foldIndex)
            if (ctx && ctx.items.Length > 0)
                this.ShowPanel(foldIndex)
        }
    }

    RefreshPanels() {
        ; 配置/宏数据热重载仍需清空面板缓存，下次显示时重建按钮布局。
        this.HideAllPanels()
    }

    ApplyThemeColors() {
        for , panelInfo in this.PanelMap {
            if (!panelInfo || !IsObject(panelInfo.ui))
                continue
            updates := [
                {ControlName: "Resource", PropertyName: "UIPanelBtnColor", Value: MainSoftData.UIPanelBtnColor},
                {ControlName: "Resource", PropertyName: "UIPanelBtnText", Value: MainSoftData.UIPanelBtnText},
                {ControlName: "Resource", PropertyName: "UIPanelBgColor", Value: MainSoftData.UIPanelBgColor},
                {ControlName: "Resource", PropertyName: "UIPanelTitleBg", Value: MainSoftData.UIPanelTitleBg},
                {ControlName: "Resource", PropertyName: "UIPanelTitleText", Value: MainSoftData.UIPanelTitleText}
            ]
            try panelInfo.ui.BatchUpdate(updates)
            panelInfo._cfg_BtnColor := MainSoftData.UIPanelBtnColor
            panelInfo._cfg_BtnText := MainSoftData.UIPanelBtnText
            panelInfo._cfg_BgColor := MainSoftData.UIPanelBgColor
            panelInfo._cfg_TitleBg := MainSoftData.UIPanelTitleBg
            panelInfo._cfg_TitleText := MainSoftData.UIPanelTitleText
        }
    }

    ShowPanel(foldIndex) {
        this.ClearUserClosed(foldIndex)
        if (!this.PanelMap.Has(foldIndex))
            this.CreatePanel(foldIndex)

        panelInfo := this.PanelMap.Has(foldIndex) ? this.PanelMap[foldIndex] : ""
        if (!panelInfo || !panelInfo.wpfHwnd)
            return

        try {
            panelInfo.userClosed := false
            DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", 9)
            if (panelInfo.isScreenMode) {
                WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
            }

            ; Show 之后重新应用默认位置（WPF Show 会恢复上次位置）
            this.ApplyPanelPosition(panelInfo)

            WinActivate("ahk_id " panelInfo.wpfHwnd)
            panelInfo.visible := true
        }
    }

    GetFullIconPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon\" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    ; 根据内部默认锚点计算面板相对容器（屏幕或目标窗口）的坐标
    ; pos: 1=左上,2=中上,3=右上,4=中左,5=中心,6=中右,7=左下,9=中下,10=右下
    ; sw/sh 为锚定容器尺寸（屏幕模式=屏幕，窗口跟随模式=目标窗口矩形），缺省取主屏
    CalcDefaultPosition(pos, &x, &y, pw, ph, sw := 0, sh := 0) {
        if (sw <= 0)
            sw := A_ScreenWidth
        if (sh <= 0)
            sh := A_ScreenHeight
        switch pos {
            case 1: x := 20, y := 20                          ; 左上
            case 2: x := (sw - pw) // 2, y := 20             ; 中上
            case 3: x := sw - pw - 20, y := 20               ; 右上
            case 4: x := 20, y := (sh - ph) // 2            ; 中左
            case 5: x := (sw - pw) // 2, y := (sh - ph) // 2 ; 中心
            case 6: x := sw - pw - 20, y := (sh - ph) // 2  ; 中右
            case 7: x := 20, y := sh - ph - 20               ; 左下
            case 9: x := (sw - pw) // 2, y := sh - ph - 20  ; 中下
            case 10: x := sw - pw - 20, y := sh - ph - 20   ; 右下
        }
    }

    ; 把已打开的该模块浮窗立刻挪到当前保存的位置。
    ApplyFoldPosition(foldIndex) {
        tableItem := GetTableBySymbol("UI")
        if (!tableItem || foldIndex < 1 || foldIndex > tableItem.Folds.Length)
            return
        fold := tableItem.Folds[foldIndex]
        this._PosForget("UIPanelPos", foldIndex)
        for key, panelInfo in this.PanelMap {
            if (!IsObject(panelInfo))
                continue
            if (panelInfo.foldIndex != foldIndex && panelInfo.foldIndex != fold.ID)
                continue
            this._ResetPosFromFold(panelInfo, fold)
            panelInfo.lastSetX := ""
            panelInfo.lastSetY := ""
            panelInfo._manualPos := false
            if (!panelInfo.visible || !panelInfo.wpfHwnd)
                continue
            if (!panelInfo.isScreenMode && panelInfo.panelReady)
                this.FollowSinglePanel(key)
            else
                this.ApplyPanelPosition(panelInfo)
        }
    }

    _FoldOf(panelInfo) {
        tableItem := GetTableBySymbol("UI")
        if (!tableItem || !IsObject(panelInfo) || !panelInfo.HasProp("foldIndex"))
            return ""
        idx := panelInfo.foldIndex
        if (IsInteger(idx) && idx >= 1 && idx <= tableItem.Folds.Length)
            return tableItem.Folds[idx]
        if (tableItem.FoldMap.Has(idx))
            return tableItem.FoldMap[idx]
        return ""
    }

    _Num(v, def) {
        if (IsInteger(v))
            return v
        if (IsNumber(v))
            return Integer(v)
        return def
    }

    ; offX/offY：相对模式是偏移，绝对模式是屏幕坐标。
    _ReadFoldPos(fold, &mode, &anchor, &offX, &offY) {
        mode := 0
        anchor := 6
        offX := -50
        offY := 50
        if (!IsObject(fold))
            return
        mode := fold.HasProp("PosMode") && this._Num(fold.PosMode, 0) == 1 ? 1 : 0
        anchor := fold.HasProp("Anchor") ? this._Num(fold.Anchor, 6) : 6
        if (anchor < 0 || anchor > 8)
            anchor := 6
        if (mode == 1) {
            offX := fold.HasProp("PosX") ? this._Num(fold.PosX, 0) : 0
            offY := fold.HasProp("PosY") ? this._Num(fold.PosY, 0) : 0
        } else {
            offX := fold.HasProp("OffsetX") ? this._Num(fold.OffsetX, -50) : -50
            offY := fold.HasProp("OffsetY") ? this._Num(fold.OffsetY, 50) : 50
        }
    }

    _ResetPosFromFold(panelInfo, fold := "") {
        if (!IsObject(fold))
            fold := this._FoldOf(panelInfo)
        mode := 0, anchor := 6, offX := -50, offY := 50
        this._ReadFoldPos(fold, &mode, &anchor, &offX, &offY)
        panelInfo.posMode := mode
        panelInfo.anchor := anchor
        panelInfo.offsetX := offX
        panelInfo.offsetY := offY
    }

    ; 0左上 1左中 2左下 3中上 4中心 5中下 6右上 7右中 8右下。点相对矩形左上角。
    _AnchorPoint(anchor, w, h, &x, &y) {
        col := 2, row := 0
        switch this._Num(anchor, 6) {
            case 0: col := 0, row := 0
            case 1: col := 0, row := 1
            case 2: col := 0, row := 2
            case 3: col := 1, row := 0
            case 4: col := 1, row := 1
            case 5: col := 1, row := 2
            case 6: col := 2, row := 0
            case 7: col := 2, row := 1
            case 8: col := 2, row := 2
        }
        x := col == 0 ? 0 : (col == 1 ? w // 2 : w)
        y := row == 0 ? 0 : (row == 1 ? h // 2 : h)
    }

    ; 偏移为 0 时浮窗左上角相对容器左上角的位置。右下、偏移 0,0 时浮窗右下角与容器右下角重合。
    _AnchorBase(anchor, pw, ph, contW, contH, &x, &y) {
        tx := 0, ty := 0, fx := 0, fy := 0
        this._AnchorPoint(anchor, contW, contH, &tx, &ty)
        this._AnchorPoint(anchor, pw, ph, &fx, &fy)
        x := tx - fx
        y := ty - fy
    }

    _PanelScreenPos(info, baseLeft, baseTop, contW, contH, pw, ph, &x, &y) {
        if (info.HasProp("posMode") && info.posMode == 1) {
            x := info.offsetX
            y := info.offsetY
            return
        }
        ax := 0, ay := 0
        anchor := info.HasProp("anchor") ? info.anchor : 6
        this._AnchorBase(anchor, pw, ph, contW, contH, &ax, &ay)
        x := baseLeft + ax + info.offsetX
        y := baseTop + ay + info.offsetY
    }

    ; 建窗时的初始坐标。没有拖动记忆时用模块位置设置；有记忆则用记忆。
    ; 屏幕模式的 Left/Top 用 DIP，窗口跟随保持物理像素。
    _PlaceByFold(fold, foldIndex, targetHwnd, isScreenMode, pw, ph, &initX, &initY, &mode, &anchor, &offX, &offY) {
        mode := 0, anchor := 6, offX := -50, offY := 50
        this._ReadFoldPos(fold, &mode, &anchor, &offX, &offY)
        dpi := A_ScreenDPI < 96 ? 96 : A_ScreenDPI
        physPw := pw * dpi // 96
        physPh := ph * dpi // 96
        baseLeft := 0, baseTop := 0, contW := A_ScreenWidth, contH := A_ScreenHeight
        if (!isScreenMode && targetHwnd && mode != 1) {
            try {
                rect := this.GetWindowRectCoords(targetHwnd)
                w := rect["right"] - rect["left"]
                h := rect["bottom"] - rect["top"]
                if (w > 0 && h > 0) {
                    contW := w
                    contH := h
                    baseLeft := rect["left"]
                    baseTop := rect["top"]
                }
            }
        }
        physX := 0, physY := 0
        posStub := { posMode: mode, anchor: anchor, offsetX: offX, offsetY: offY }
        this._PanelScreenPos(posStub, baseLeft, baseTop, contW, contH, physPw, physPh, &physX, &physY)
        if (isScreenMode) {
            initX := physX * 96 // dpi
            initY := physY * 96 // dpi
        } else {
            initX := physX
            initY := physY
        }
        savedPos := this._PosGet("UIPanelPos", foldIndex, targetHwnd)
        if (IsObject(savedPos)) {
            if (isScreenMode) {
                scale := A_ScreenDPI / 96
                initX := Round(savedPos.x / scale)
                initY := Round(savedPos.y / scale)
            } else {
                initX := savedPos.x
                initY := savedPos.y
            }
        }
    }

    ; 有拖动记忆时优先恢复；否则按模块位置设置放置。
    ApplyPanelPosition(panelInfo) {
        if (panelInfo.HasProp("foldIndex")) {
            saved := this._PosGet("UIPanelPos", panelInfo.foldIndex, panelInfo.targetHwnd)
            if (IsObject(saved) && panelInfo.wpfHwnd) {
                try DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0
                    , "Int", saved.x, "Int", saved.y, "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0004)
                panelInfo.lastSetX := saved.x
                panelInfo.lastSetY := saved.y
                panelInfo._manualPos := true
                return
            }
        }
        try {
            rect := this.GetWindowRectCoords(panelInfo.wpfHwnd)
            pw := rect["right"] - rect["left"]
            ph := rect["bottom"] - rect["top"]
        } catch {
            pw := 250, ph := 200
        }
        if (pw <= 0)
            pw := 250
        if (ph <= 0)
            ph := 200

        baseLeft := 0, baseTop := 0, contW := A_ScreenWidth, contH := A_ScreenHeight
        mode := panelInfo.HasProp("posMode") ? panelInfo.posMode : 0
        if (mode != 1 && !panelInfo.isScreenMode && panelInfo.targetHwnd) {
            try {
                wRect := this.GetWindowRectCoords(panelInfo.targetHwnd)
                w := wRect["right"] - wRect["left"]
                h := wRect["bottom"] - wRect["top"]
                if (w > 0 && h > 0) {
                    contW := w
                    contH := h
                    baseLeft := wRect["left"]
                    baseTop := wRect["top"]
                }
            }
        }
        initX := 0, initY := 0
        this._PanelScreenPos(panelInfo, baseLeft, baseTop, contW, contH, pw, ph, &initX, &initY)
        DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0
            , "Int", initX, "Int", initY, "Int", 0, "Int", 0, "UInt", 0x0001)
        panelInfo.lastSetX := initX
        panelInfo.lastSetY := initY
    }

    GetWindowRectCoords(hwnd) {
        rect := Buffer(16, 0)
        DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")
        return Map("left", left, "top", top, "right", right, "bottom", bottom)
    }

    ; 直接用 hwnd 匹配 FrontInfo 条件（用于自动显示检测）
    IsHwndMatchFrontInfo(hwnd, frontInfo) {
        if (frontInfo == "" || !hwnd)
            return false

        ; ❖ 句柄列表模式：检查 hwnd 是否在列表中
        if (InStr(frontInfo, "❖")) {
            idStr := StrReplace(frontInfo, "❖")
            for _, id in StrSplit(idStr, "|") {
                if (id != "" && Integer(id) == hwnd)
                    return true
            }
            return false
        }

        ; title⎖class⎖process 模式
        infoArr := StrSplit(frontInfo, "⎖")
        if (infoArr.Length != 3)
            return false

        try {
            if (infoArr[1] != "" && !InStr(WinGetTitle("ahk_id " hwnd), infoArr[1]))
                return false
            if (infoArr[2] != "" && WinGetClass("ahk_id " hwnd) != infoArr[2])
                return false
            if (infoArr[3] != "" && WinGetProcessName("ahk_id " hwnd) != infoArr[3])
                return false
            return true
        }
        return false
    }

    ResolveTargetHwnd(frontInfo) {
        if (frontInfo == "")
            return 0

        if (InStr(frontInfo, "❖")) {
            idStr := StrReplace(frontInfo, "❖")
            hwndList := StrSplit(idStr, "|")
            for index, hwnd in hwndList {
                if (hwnd == "")
                    continue
                try {
                    hwndVal := Integer(hwnd)
                    if (DllCall("user32\IsWindow", "Ptr", hwndVal))
                        return hwndVal
                }
            }
            return 0
        }

        infoArr := StrSplit(frontInfo, "⎖")
        if (infoArr.Length != 3)
            return 0

        title := infoArr[1]
        className := infoArr[2]
        process := infoArr[3]

        winTitle := ""
        if (title != "")
            winTitle .= title
        if (className != "")
            winTitle .= " ahk_class " className
        if (process != "")
            winTitle .= " ahk_exe " process

        if (winTitle == "")
            return 0

        try {
            hwnd := WinExist(winTitle)
            return hwnd ? hwnd : 0
        }
        return 0
    }

    __Delete() {
        this.StopMonitor()
    }
}
