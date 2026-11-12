#Requires AutoHotkey v2.0

class UIMacroGui {
    static STATE_DEFAULT := 0    ; 默认/空闲（隐藏色块）
    static STATE_RUNNING := 1    ; 运行中（绿色）
    static STATE_PAUSED := 2     ; 暂停中（黄色）
    static STATE_STOPPED := 3    ; 停止/终止（红色，5秒后自动恢复）
    static DEFAULT_PANEL_ANCHOR := 1
    static DEFAULT_PANEL_OFFSET_X := 100
    static DEFAULT_PANEL_OFFSET_Y := 100

    static AdditionalTables := Map()

    static ForTable(tableItem, create := false) {
        if (tableItem == GetTableBySymbol("UI"))
            return MyUIMacroGui
        if (create && !this.AdditionalTables.Has(tableItem.ID))
            this.AdditionalTables[tableItem.ID] := UIMacroGui(tableItem.ID)
        return this.AdditionalTables.Get(tableItem.ID, "")
    }

    GetTable() => this.TableID == "" ? GetTableBySymbol("UI") : GetTableByID(this.TableID)

    __new(tableID := "") {
        this.TableID := tableID
        this.PanelMap := Map()       ; panelKey -> panelInfo
        this.PanelTimers := Map()     ; panelKey -> FuncObj（SetTimer回调引用）
        this._pendingBallHome := Map()  ; panelKey -> {x, y}：刚收起时面板所在的中央，建球时一次性使用
        this._pendingPanelPos := Map()  ; foldIndex -> {offX, offY}：球展开成面板时的初始偏移，建窗一次性使用
        this.IsCreating := false
        this._panelGen := 0             ; 建窗轮询世代号：重建同一 panelKey 时旧轮询失效
        this.MonitorTimer := ""
        this._lastActiveHwnd := 0       ; 上次检测的前台窗口 hwnd
        this._TipTimers := Map()        ; panelKey -> 内联提示定时器
        this._waitFns := Map()          ; panelKey -> 建窗就绪轮询定时器（每个 key 只准有一个）
        this._schemaCache := Map()      ; foldKey -> {text, schema}：面板定义解析结果缓存
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
        if (this.TableID == "") {
            for _, panel in UIMacroGui.AdditionalTables
                panel.StopMonitor()
        }
    }

    ; ========== 面板管理（严格对齐 floating_panel.ahk） ==========

    ; 获取界面宏表 + 折叠框 + 折叠框内条目（统一入口，避免各处重复 TableInfo[4]/IndexSpan）
    _GetFoldContext(foldIndex) {
        tableItem := this.GetTable()
        if (!tableItem)
            return ""
        if (!tableItem.Folds.Has(foldIndex))
            return ""
        fold := tableItem.Folds[foldIndex]
        if (!fold || fold.ForbidState)
            return ""
        return { tableItem: tableItem, fold: fold, items: GetFoldItems(tableItem, fold) }
    }

    ; 折叠框 → 面板按钮列表（手动面板、自动面板、球展开回面板三处共用同一份构造）。
    ; 以前这段在 CreatePanel / CreateAutoPanel 里各写一遍，球展开时拿不到列表，
    ; 按钮面板收成球之后就展不回来（只会建出一块空面板）。
    _CollectBtnItems(foldIndex) {
        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return []
        tableItem := ctx.tableItem
        items := []
        for i, item in ctx.items {
            if (ParseBoolInt(item.Forbid))
                continue

            remarkValue := item.Remark
            iconValue := item.IcoPath
            btnText := remarkValue == "" ? GetLang("操作") i : remarkValue
            displayIcon := iconValue == "" ? "" : iconValue

            macroIndex := GetItemIndexInTable(tableItem, item.ID)
            items.Push({
                name: "Btn_" macroIndex,
                text: btnText,
                icon: displayIcon,
                state: item.ColorState,
                macroIndex: macroIndex,
                macroId: String(item.ID)
            })
        }
        return items
    }

    ; 创建面板入口（对齐 CreateFloatingPanel L182-265）
    CreatePanel(foldIndex) {
        ctx := this._GetFoldContext(foldIndex)
        if (!ctx || ctx.items.Length == 0)
            return
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        ; 按钮列表统一由 _CollectBtnItems 生成：球展开回面板时也用它，两处口径必须一致
        btnItems := this._CollectBtnItems(foldIndex)

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
        fold := ctx.fold

        if (this.PanelMap.Has(foldIndex))
            this.DestroyPanel(foldIndex)

        ; 按钮列表统一由 _CollectBtnItems 生成：球展开回面板时也用它，两处口径必须一致
        btnItems := this._CollectBtnItems(foldIndex)

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
        ; 球与按钮配置无关：跳过，否则改个按钮颜色就会把球重建成面板
        if (!(panelInfo.HasProp("_isBall") && panelInfo._isBall)
            && (panelInfo._cfg_BtnHeight != MainSoftData.UIPanelBtnHeight
            || panelInfo._cfg_BtnWidth != MainSoftData.UIPanelBtnWidth
            || panelInfo._cfg_Cols != MainSoftData.UIPanelCols
            || panelInfo._cfg_FontSize != MainSoftData.UIPanelFontSize
            || panelInfo._cfg_BtnColor != MainSoftData.UIPanelBtnColor
            || panelInfo._cfg_BtnText != MainSoftData.UIPanelBtnText
            || panelInfo._cfg_BgColor != MainSoftData.UIPanelBgColor
            || panelInfo._cfg_TitleBg != MainSoftData.UIPanelTitleBg
            || panelInfo._cfg_TitleText != MainSoftData.UIPanelTitleText)) {
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
        ; 收起态（悬浮球）优先：按钮面板和自定义面板都能收成球，这里是两种面板共用的入口。
        ; 以前只有 _BuildCustomPanel 有这道判断，按钮面板点了圆点仍会照空按钮列表建窗，
        ; 表现就是「点了圆点但什么都没变」。
        if (this._BallGet(foldIndex))
            return this._BuildCustomBall(foldIndex, targetHwnd, isScreenMode, panelKey)
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

        tableItem := this.GetTable()
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

        ; 标题栏：标题居中，右上角「收起成球 / 关闭」两个按钮。
        ; 以前这里是一整条只放标题文字的 Border，于是没有自定义界面的默认面板右上角
        ; 什么都没有，收球、关闭只能靠热键。现在两种面板共用同一套标题栏。
        titleBar := main.Add("Border").Grid_Row(0).Name("TitleBar").Background("{DynamicResource UIPanelTitleBg}")
            .WindowChrome_IsHitTestVisibleInChrome("True")
        tbGrid := titleBar.Add("Grid")
        tbGrid.Add("TextBlock").Name("TitleText").Text(foldRemark)
            .Foreground("{DynamicResource UIPanelTitleText}").FontSize(11).FontWeight("SemiBold")
            .VerticalAlignment("Center").HorizontalAlignment("Center").Margin("6,0,6,0")
        ; 两个按钮画成「实色圆点 / 字符 ×」，不走 DynamicResource、也不用图标字体：
        ; 图标字体回退失败时 E8BB 会渲染成空白，DynamicResource 缺定义时解析成空画刷，
        ; 两种都会让按钮「明明在、却看不见」。颜色直接取面板标题文字色。
        tbBtns := tbGrid.Add("StackPanel").Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center").Margin("0,0,4,0")
        for btnName in ["BtnPanelBall", "BtnPanelClose"] {
            b := tbBtns.Add("Button").Name(btnName)
                ; 标题栏属于 WindowChrome 的 caption 区：不声明可命中就点不动
                .WindowChrome_IsHitTestVisibleInChrome("True")
                .Width(22).Height(20).MinHeight(20).Margin("2,0,0,0")
                .Padding("0").Cursor("Hand")
                .Background("Transparent").BorderThickness("0")
            try b.InjectResources(UIMacroRenderer.BtnStyle)
            if (btnName == "BtnPanelBall") {
                ; 收起 = 悬浮球：直接画一个小圆点
                b.Add("Border").Width(8).Height(8).CornerRadius("4")
                    .Background(titleText)
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
            } else {
                b.Add("TextBlock").Name(btnName "Glyph").Text("×")
                    .FontSize("13").FontWeight("SemiBold").Foreground(titleText)
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
                    .Margin("0,0,0,1")
            }
        }

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

            stateDot := sp.Add("Ellipse").Name(item.name "_State")
                .Width(8).Height(8).VerticalAlignment("Center").Margin("0,0,2,0")
                .IsHitTestVisible("False")
            if (MacroStateColors.Has(item.state))
                stateDot.Fill(MacroStateColors[item.state])
            else
                stateDot.Visibility("Collapsed")

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

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="RMT Panel" ShowInTaskbar="False" ShowActivated="False" Width="' pw '" Height="' ph '"')
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
        ; 标题栏右上角：收起成球 / 关闭浮窗（与自定义面板同一套回调）
        try ui.OnEvent("BtnPanelBall", "Click", ObjBindMethod(this, "_OnPanelBallClick", panelKey))
        try ui.OnEvent("BtnPanelClose", "Click", ObjBindMethod(this, "_OnPanelCloseClick", panelKey))
        try ui.OnEvent("Window", "StateChanged", ObjBindMethod(this, "_OnPanelStateChanged", panelKey))

        ; 显示窗口（对齐 floating_panel L254）
        ; 建窗走异步通道：Show 只把 CREATE 投进共享内存 + PostMessage，立刻返回。
        ; 同步 Show 要等 daemon 真正建出窗口（实测 200~700ms，最坏 2s），这段时间
        ; 主线程完全阻塞，热键、跟随定时器、其它浮窗的刷新一起停。
        ; 句柄回传前 wpfHwnd 为 0，激活与就绪初始化延到 _WaitPanelHwnd 里做。
        ui.asyncCreate := true
        ; 更新同样异步：跟随/回填/状态色都在主线程上，同步等引擎执行完等于
        ; 把这份等待加到每一次刷新上。入队即返回，引擎按帧回执。
        ui.asyncUpdate := true
        ui.Show()

        ; 返回面板信息（对齐 floating_panel 全局变量初始化 L207-L211, L251-L252）
        return {
            ui: ui,
            wpfHwnd: ui.HasProp("wpfHwnd") ? ui.wpfHwnd : 0,
            _creating: true,          ; 句柄未回传：CheckAllPanels 不能当「窗口已失效」销毁
            _skipActivate: skipActivate,
            panelKey: panelKey,
            foldIndex: foldIndex,
            foldID: fold ? fold.ID : "",
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            noActivate: true,
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
    ; 逐控件 Update 都是一次同步跨进程往返，这里收进收集缓冲，末尾一条 payload 发完，
    ; 引擎侧对这批失效只结算一次布局。
    _FillBindings(panelKey) {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema) || !IsObject(info) || !IsObject(info.ui))
            return
        ui := info.ui
        cmds := ""
        ui.BeginCollect()
        try {
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
                UIMacroRenderer.SetValue(ui, ctrl.id, ctrl.type, val, spec)
            }
        } finally {
            ; 必须收口：BeginCollect 之后漏掉 EndCollect，后续所有 Update 都会被截留在缓冲里
            cmds := ui.EndCollect()
        }
        if (cmds != "")
            try ui.SendRaw(cmds)
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

        ; 一次批量取回全部控件的显示值：原来每个绑定控件各发一次同步 Query（还要忙等
        ; 回执），控件多的面板点一下「写入宏」要排几十趟跨进程往返，界面会顿一下。
        ; 取不到的控件在下面退回逐控件读取，行为与原来一致。
        stateAll := Map()
        try stateAll := info.ui.Query("*")
        if (!IsObject(stateAll))
            stateAll := Map()

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

            pv := UIMacroGui._PanelValueOf(stateAll, ctrl, spec)
            val := pv.ok ? pv.val : UIMacroRenderer.ReadValue(info.ui, ctrl.id, ctrl.type, spec)
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
        ; 只记「真正改过的宏」所在行：整表重绘等于把没动过的行也逐行下发一遍，
        ; 行多时点一次「写入宏」就顿一下，而实际需要刷新的通常只有一两行。
        repaintRows := Map()   ; tableID → Map(itemID → true)
        for snapKey, ent in touchedMacros {
            try {
                if (!UIMacroStepBinding.SaveContainer(ent.owner))
                    throw Error("容器保存失败")
                ; 顶层宏落盘后才需要重绘主界面；嵌套容器在数据文件里，主列表不显示它
                if (IsObject(ent.owner) && ent.owner.type == "item" && IsObject(ent.owner.item)) {
                    tID := String(ent.owner.tableItem.ID)
                    if (!repaintRows.Has(tID))
                        repaintRows[tID] := Map()
                    repaintRows[tID][String(ent.owner.item.ID)] := true
                }
                if (info.HasProp("_macroSnapshot") && IsObject(info._macroSnapshot))
                    info._macroSnapshot.Delete(snapKey)
            } catch {
                failed += 1
                if (firstMsg == "")
                    firstMsg := "落盘失败：宏表保存出错"
            }
        }
        ; 仅顶层宏会显示在主界面列表中；嵌套容器只需保存数据文件。
        for tableID, idSet in repaintRows
            this._RepaintMainWindowTable(tableID, idSet)
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
        ; 文本与可见性合成一条：两次同步往返 = 引擎两轮布局结算，点一下能感到顿
        try info.ui.BatchUpdate([
            { ControlName: "WriteBackTip", PropertyName: "Text", Value: text },
            { ControlName: "WriteBackTip", PropertyName: "Visibility", Value: "Visible" }
        ])
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

    ; 让主界面把某张表的行重新画一遍（虚拟列表不会感知 TableInfo 被整体替换）
    ; idSet 给出「本次真正改动过的宏 ID」时只刷这些行 —— 每行在非虚拟模式下是十余条
    ; 同步 IPC，虚拟模式下也各要一条，整表遍历几百行就是一次肉眼可见的停顿。
    _RepaintMainWindowTable(tableID, idSet := "") {
        if (!IsSet(MyMainWin) || !IsObject(MyMainWin))
            return
        t := GetTableIndexByID(tableID)
        if (t < 1 || t > MySoftData.TableInfo.Length)
            return
        tbl := MySoftData.TableInfo[t]
        if (!IsObject(tbl))
            return
        if (IsObject(idSet)) {
            if (!idSet.Count)
                return
            loop tbl.Items.Length {
                it := tbl.Items[A_Index]
                if (IsObject(it) && idSet.Has(String(it.ID)))
                    try MyMainWin.RefreshItemRow(t, A_Index)
            }
            return
        }
        loop tbl.Items.Length
            try MyMainWin.RefreshItemRow(t, A_Index)
    }

    ; TextChanged 回调：值优先取事件包里的 stateMap —— 引擎 Full 模式已把全部跟踪控件的值
    ; 随事件一并带回，逐字再补一次同步 Query（还要忙等回执）纯属白付一趟往返。
    _OnBoundEdit(panelKey, ctrlId, binding, stateMap := "", ctrlName := "", eventName := "") {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info) || !IsObject(info.ui))
            return
        ctrlFullName := UIMacroRenderer.NameOf(ctrlId)
        val := ""
        if (IsObject(stateMap) && stateMap.Has(ctrlFullName))
            val := stateMap[ctrlFullName]
        else
            try val := info.ui.Query(ctrlFullName)
        res := this._ApplyBoundValue(info, binding, val)
        ; 值没变（光标移动、程序化回填）就不刷显示，省掉一轮无意义下发
        if (IsObject(res) && res.HasProp("changed") && !res.changed)
            return
        this._RefreshDisplayBindings(panelKey, binding)
    }

    ; 刷新「只显示」的绑定（TextBlock）：它没有输入，只能跟着别的控件的改动走。
    ; 只碰 TextBlock，避免把用户正在输入的 Edit 内容覆盖掉。
    ; srcBinding 非空时只刷同一容器位置的显示控件；结果合并成一条 BatchUpdate，
    ; 不再逐条同步往返。
    _RefreshDisplayBindings(panelKey, srcBinding := "") {
        info := this._FindPanelInfo(panelKey)
        schema := IsObject(info) ? this._GetCustomSchema(info.foldIndex) : ""
        if (!IsObject(schema) || !IsObject(info) || !IsObject(info.ui))
            return
        targets := []
        for ctrl in schema.controls {
            if (ctrl.type != "TextBlock")
                continue
            if (!ctrl.HasProp("binding") || !IsObject(ctrl.binding))
                continue
            targets.Push(ctrl)
        }
        if (IsObject(srcBinding) && targets.Length) {
            filtered := []
            for ctrl in targets {
                if (UIMacroGui._TouchSameTarget(srcBinding, ctrl.binding))
                    filtered.Push(ctrl)
            }
            ; 过滤后一个都没命中（绑定形态没覆盖到）→ 退回全刷，宁可多发也不漏刷
            if (filtered.Length)
                targets := filtered
        }
        updates := []
        for ctrl in targets {
            b := ctrl.binding
            val := ""
            if (String(b.mode) == "data") {
                cur := UIMacroStepBinding.ReadData(b.serial, b.field)
                val := cur.ok ? cur.value : ""
            } else {
                tableItem := this._TableForBinding(b)
                got := UIMacroStepBinding.ReadParamDeep(tableItem, b)
                if (got.ok)
                    val := got.value
            }
            updates.Push({ ControlName: UIMacroRenderer.NameOf(ctrl.id), PropertyName: "Text", Value: String(val) })
        }
        if (updates.Length)
            try info.ui.BatchUpdate(updates)
    }

    ; 把批量查询（Query("*")）里某个控件的显示值，换算成「ReadValue 口径」的值。
    ; ok=false 表示这批数据里没有它、或无法可靠反查（下拉框显示名重复），调用方退回逐控件读。
    static _PanelValueOf(stateAll, ctrl, spec) {
        name := UIMacroRenderer.NameOf(ctrl.id)
        if (!IsObject(stateAll) || !stateAll.Has(name))
            return { ok: false, val: "" }
        raw := String(stateAll[name])
        t := String(ctrl.HasProp("type") ? ctrl.type : "")
        if (t == "CheckBox")
            return { ok: true, val: (raw == "True" || raw == "1") ? 1 : 0 }
        if (t == "ComboBox") {
            ; 引擎回报的是选中项的显示文本（ComboBoxItem.Content 即 options[?][2]）
            if (!IsObject(spec) || String(spec.type) != "enum"
                || !spec.HasProp("options") || !IsObject(spec.options))
                return { ok: false, val: "" }
            if (raw == "")
                return { ok: true, val: "" }
            hitIdx := -1, dup := false, i := 0
            for pair in spec.options {
                if (String(pair[2]) == raw) {
                    if (hitIdx >= 0) {
                        dup := true
                        break
                    }
                    hitIdx := i
                }
                i += 1
            }
            if (hitIdx < 0 || dup)
                return { ok: false, val: "" }
            opts := spec.options
            return { ok: true, val: String(opts[hitIdx + 1][1]) }
        }
        return { ok: true, val: raw }
    }

    ; 两个绑定是否指向同一容器位置：同一序列的字段，或同一宏的同一步（含嵌套分支路径）
    static _TouchSameTarget(a, b) {
        if (!IsObject(a) || !IsObject(b))
            return false
        am := a.HasProp("mode") ? String(a.mode) : ""
        bm := b.HasProp("mode") ? String(b.mode) : ""
        if (am == "data" || bm == "data") {
            if (am != "data" || bm != "data")
                return false
            return String(a.HasProp("serial") ? a.serial : "") == String(b.HasProp("serial") ? b.serial : "")
        }
        if (String(a.HasProp("macroId") ? a.macroId : "") != String(b.HasProp("macroId") ? b.macroId : ""))
            return false
        if (String(a.HasProp("step") ? a.step : "") != String(b.HasProp("step") ? b.step : ""))
            return false
        return UIMacroStepBinding.HopsKey(a) == UIMacroStepBinding.HopsKey(b)
    }

    ; 下拉框改动：选中项 → options 里的「值」→ 写进宏文本
    ; 事件包默认 Full 模式已带回控件的当前值（不可编辑 ComboBox 即选中项文本），
    ; 能对上就直接用；对不上（空选中、可编辑下拉被手输）才回退一次同步 Query。
    _OnBoundCombo(panelKey, ctrlId, binding, spec := "", stateMap := "", ctrlName := "", *) {
        info := this._FindPanelInfo(panelKey)
        if (!IsObject(info))
            return
        if (!IsObject(spec) || !spec.HasProp("options") || !IsObject(spec.options))
            return
        name := UIMacroRenderer.NameOf(ctrlId)
        if (IsObject(stateMap) && stateMap.Has(name)) {
            selText := String(stateMap[name])
            ; 显示文本唯一才敢按文本反查值（options 允许两条不同值共用一个显示名）
            hitIdx := -1, dup := false, i := 0
            for pair in spec.options {
                if (String(pair[2]) == selText) {
                    if (hitIdx >= 0) {
                        dup := true
                        break
                    }
                    hitIdx := i
                }
                i += 1
            }
            if (hitIdx >= 0 && !dup) {
                opts := spec.options
                this._ApplyBoundValue(info, binding, String(opts[hitIdx + 1][1]))
                this._RefreshDisplayBindings(panelKey, binding)
                return
            }
        }
        if (!IsObject(info.ui))
            return
        idx := -1
        try idx := Integer(info.ui.Query(name ">SelectedIndex"))
        if (idx < 0) {
            this._ApplyBoundValue(info, binding, "")
            return
        }
        i := 0
        for pair in spec.options {
            if (i == idx) {
                this._ApplyBoundValue(info, binding, String(pair[1]))
                this._RefreshDisplayBindings(panelKey, binding)
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
        this._RefreshDisplayBindings(panelKey, binding)
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
            tableItem := this.GetTable()
            fold := (tableItem && tableItem.Folds.Length >= foldIndex) ? tableItem.Folds[foldIndex] : ""
            foldKey := UIMacroSchema.FoldKey(fold)
        }
        if (foldKey == "") {
            foldKey := String(foldIndex)
        } else if (this.TableID == "") {
            UIMacroSchema.MigrateLegacy(foldIndex, foldKey)
        }

        raw := UIMacroSchema.ReadStoreByKey(foldKey)
        if (Trim(String(raw)) == "" && this.TableID == "")
            raw := UIMacroSchema.DecodeStore(MainSoftData.UIPanelCustom)
        if (Trim(String(raw)) == "")
            return ""
        ; 解析结果按「foldKey + 原文」缓存：文本没变就不重复 Parse/Validate/Migrate。
        ; 读文本这一层已由 UIMacroSchema 的内存缓存接住，这里是第二层（JSON 解析 + 校验 +
        ; 绑定类型迁移）。按键回填、切页、就绪全部走这里，一次不回填就是十几次解析。
        ; schema 在调用方只读（渲染 / 取值 / 写入宏），可以放心共享同一份对象。
        if (IsObject(this._schemaCache) && this._schemaCache.Has(foldKey)) {
            hit := this._schemaCache[foldKey]
            if (IsObject(hit) && IsObject(hit.schema) && hit.text == raw)
                return hit.schema
        }
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
            result := UIMacroStepBinding.MigrateBindingTypes(parsed, tableItem)
            if (IsObject(result) && IsObject(this._schemaCache))
                this._schemaCache[foldKey] := { text: raw, schema: result }
            return result
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
        ; 清掉上一次没被建窗消费掉的残留偏移，避免「这次打开突然出现在上次球的位置」
        if (this._pendingPanelPos.Has(foldIndex))
            this._pendingPanelPos.Delete(foldIndex)
        targetHwnd := 0
        isScreen := true
        info._keepEdits := true
        targetHwnd := info.targetHwnd
        isScreen := info.isScreenMode
        ; 面板 → 球：球出现在面板当前位置的中央。两种状态占同一处，视觉上就是「缩小」。
        ; 这个位置只在建球时用一次、不落盘：建球时会被折算成跟随偏移，之后照常跟窗口走。
        if (on && info.wpfHwnd && !info.HasProp("_isBall")) {
            home := this._CenteredBallPos(info.wpfHwnd)
            if (IsObject(home))
                this._pendingBallHome[panelKey] := home
        }
        ; 收起前只记「用户真拖过」的位置（与 × 关闭、热键隐藏同口径）。
        ; 跟随模式下绝不能记：UIPanelPos 一旦有记录，FollowSinglePanel 会认定用户
        ; 手动摆过而永久停止跟随 —— 收成球再展开，面板就再也不跟目标窗口了。
        ; 没拖过却残留了记录（旧版本在这里无条件写过）时顺手清掉，让跟随恢复。
        if (info.wpfHwnd && !info.HasProp("_isBall")) {
            if (info.HasProp("_manualPos") && info._manualPos) {
                px := 0, py := 0
                try WinGetPos(&px, &py, , , "ahk_id " info.wpfHwnd)
                if (px != 0 || py != 0)
                    this._PosSave("UIPanelPos", foldIndex, px, py, targetHwnd)
            } else if ((info.HasProp("posMode") ? info.posMode : 0) != 1) {
                ; 跟随模式下这条记忆本来就不参与定位，清掉以免下次又被误当成手动位置
                try this._PosForget("UIPanelPos", foldIndex)
            }
        }
        ; 展开成面板前确认内容还在：自定义面板要有 schema，按钮面板要有按钮。
        ; 两者都拿不到时保持球态 —— 否则建出来的是一块空面板，球没了、面板也是空的，
        ; 看起来就是「点了球之后什么都打不开」。这种情况别把唯一的入口换掉。
        if (!on && !IsObject(this._GetCustomSchema(foldIndex)) && this._CollectBtnItems(foldIndex).Length == 0) {
            this._BallSet(foldIndex, true)
            return
        }
        this._BallSet(foldIndex, on)
        this.DestroyPanel(panelKey)
        ; 球 → 面板：把球当前位置折算成面板偏移，紧接着的建窗会用它（就地放大）
        if (!on)
            this._QueuePanelPosFromBall(foldIndex, info)
        ; 不能走 CreatePanel：它要求「目标窗口必须在前台」，而切换瞬间前台是面板自己，
        ; 会被直接拦掉，表现为「点了最小化但屏幕上什么都没有」。
        this.IsCreating := true
        try {
            ; 按钮列表在这里重新收集：自定义面板走 schema 分支会忽略它，按钮面板靠它建格子
            pi := this.BuildXAMLPanel(this._CollectBtnItems(foldIndex), foldIndex, targetHwnd, isScreen, true, panelKey)
            if (IsObject(pi)) {
                this.PanelMap.Set(panelKey, pi)
                ; 建窗一律异步，两种形态都要轮询句柄：球只补一次精确对齐后返回，
                ; 展开成面板才走完整就绪流程（定位、跟随、回填）
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
        if (this.TableID == "" && legacyKey != keys[1] && legacyKey != foldKey)
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
        legacy := this.TableID == "" ? String(foldIndex) : base
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
    _BuildCustomBall(foldIndex, targetHwnd, isScreenMode, panelKey := "") {
        if (panelKey == "")
            panelKey := foldIndex
        size := 56
        ; 颜色写成实色而不是 DynamicResource：球的窗口不注入主题资源时，Border 的
        ; Background 会解析成空。空 Background 的 Border 不参与命中测试 —— 鼠标事件
        ; 落到外层 Grid 上，BallView 的点击/拖动回调一次都不会触发（表现为球点不动、
        ; 拖不动，但窗口本身还看得见）。
        ballBg := MainSoftData.UIPanelTitleBg
        ballFg := MainSoftData.UIPanelTitleText
        main := XAML_Generator("Grid").Background("Transparent")
        ball := main.Add("Border").Name("BallView").Width(size).Height(size)
            .CornerRadius(String(size // 2))
            .Background(ballBg)
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .Cursor("Hand")
        iconPath := A_ScriptDir "\Images\Soft\rabit.ico"
        if (FileExist(iconPath)) {
            ball.Add("Image").Name("BallIcon").Source(iconPath)
                .Width(32).Height(32).HorizontalAlignment("Center").VerticalAlignment("Center")
        } else {
            ball.Add("TextBlock").Name("BallText").Text("RMT").FontSize("13")
                .Foreground(ballFg)
                .HorizontalAlignment("Center").VerticalAlignment("Center")
        }

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", "0")
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", 0)
        ; 注意不要设 Opacity="0"：面板那套流程会再改回 1，球这边没有这段流程，
        ; 设了就会「窗口存在但完全透明」，表现为点了最小化什么都没出现。
        ; Tag="BallNoActivate"：引擎在 EnsureHandle 之后、Show 之前按这个标记直接打上
        ; WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW（见 FirstFrame.cs）。只在 AHK 侧事后补样式
        ; 是不够的 —— 句柄回传要几十到几百毫秒，而收球后用户第一件事往往就是去点它，
        ; 这个空档里窗口还是「可激活」的，一点就把当前正在输入的窗口顶掉。
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"'
            , 'Title="RMT" ShowInTaskbar="False" Tag="BallNoActivate" Width="' size '" Height="' size '"')
        ; 圆球需要真透明窗口；而 WindowChrome 与 AllowsTransparency 不能共存，
        ; 两者同时存在会导致窗口不渲染——所以把 chrome 整段去掉。
        this.ui.xaml := RegExReplace(this.ui.xaml, "s)<WindowChrome\.WindowChrome>.*?</WindowChrome\.WindowChrome>", "")
        ; 球是固定尺寸，禁掉可调整边框
        this.ui.xaml := StrReplace(this.ui.xaml, 'ResizeMode="%ResizeMode%"', 'ResizeMode="NoResize"')
        ; ShowActivated="False"：建窗不上前台，否则球一出现就把用户正在输入的窗口顶掉。
        ; 真正的「不激活」靠根上的 Tag="BallNoActivate"（引擎建句柄时打 WS_EX_NOACTIVATE），
        ; 这里只是让首帧 Show 本身也不上前台；句柄回传后 _ApplyBallWindowStyle 再补一次兜底。
        this.ui.xaml := StrReplace(this.ui.xaml, 'AllowsTransparency="False"'
            , 'AllowsTransparency="True" ShowActivated="False" Focusable="False"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"'
            , 'FontFamily="' MainSoftData.FontType '"')
        ; 和面板同口径注入面板配色：球的 Border 用实色，但 _ApplyBallWindowStyle、
        ; 主题刷新等路径仍会下发 UIPanel* 资源名，缺定义时 DynamicResource 会解析成空。
        this.ui.xaml := StrReplace(this.ui.xaml, "%resources%"
            , '<SolidColorBrush x:Key="UIPanelTitleBg" Color="' ballBg '"/>'
            . '<SolidColorBrush x:Key="UIPanelTitleText" Color="' ballFg '"/>')
        this.ui.xaml := StrReplace(this.ui.xaml, "%components%", "")

        this.ui.OnEvent("BallView", "BallDrag", ObjBindMethod(this, "_OnBallGesture", panelKey))

        ; 建窗前就定好位置：否则窗口会先按 CenterScreen 出现在屏幕中间，
        ; 再被 SetWindowPos 搬走 —— 表现为「球闪一下再跳过去」。
        ; 位置模型和面板完全一样（模块位置设置 + 锚点/偏移），只是把尺寸换成球径：
        ; 这样球也能跟着目标窗口走，拖动后从新偏移继续跟，和面板行为一致。
        ctxFold := this._GetFoldContext(foldIndex)
        fold := IsObject(ctxFold) ? ctxFold.fold : ""
        mode := 0, anchor := 6, offX := -50, offY := 50
        this._ReadFoldPos(fold, &mode, &anchor, &offX, &offY)
        baseLeft := 0, baseTop := 0, contW := A_ScreenWidth, contH := A_ScreenHeight
        if (!isScreenMode && targetHwnd && mode != 1) {
            try {
                trect := this.GetWindowRectCoords(targetHwnd)
                tw := trect["right"] - trect["left"]
                th := trect["bottom"] - trect["top"]
                if (tw > 0 && th > 0) {
                    contW := tw
                    contH := th
                    baseLeft := trect["left"]
                    baseTop := trect["top"]
                }
            }
        }
        bsp := Round(size * (A_ScreenDPI / 96))
        ax := 0, ay := 0
        this._AnchorBase(anchor, bsp, bsp, contW, contH, &ax, &ay)
        ; 刚收起时用「面板中央」当初始偏移：就地缩小，不跳；之后偏移保持不变继续跟随。
        pend := this._TakePendingBallHome(panelKey)
        if (IsObject(pend) && mode != 1) {
            offX := pend.x - baseLeft - ax
            offY := pend.y - baseTop - ay
        }
        wantX := (mode == 1) ? offX : baseLeft + ax + offX
        wantY := (mode == 1) ? offY : baseTop + ay + offY
        ballPos := this._ClampBallPos(wantX, wantY, size)
        ; 夹回屏幕内之后重新折算偏移，保证「偏移 → 位置」永远自洽（否则下一帧会被跟随拉走）
        if (mode == 1) {
            offX := ballPos.x
            offY := ballPos.y
        } else {
            offX := ballPos.x - baseLeft - ax
            offY := ballPos.y - baseTop - ay
        }
        scaleB := A_ScreenDPI / 96
        lx := Round(ballPos.x / scaleB)
        ly := Round(ballPos.y / scaleB)
        this.ui.xaml := StrReplace(this.ui.xaml, 'WindowStartupLocation="CenterScreen"'
            , 'Left="' lx '" Top="' ly '" WindowStartupLocation="Manual"')

        ; 建窗异步：同步 Show 要等 daemon 建出窗口（实测 200~700ms，最坏 2s），这期间
        ; 主线程完全停住，而「最小化成球」是用户会连着点的操作。球的位置上面已写进
        ; XAML 的 Left/Top（DIP），误差不到 1 像素，物理像素精确对齐挪到句柄回传后做。
        this.ui.asyncCreate := true
        this.ui.asyncUpdate := true
        try this.ui.Show()
        ; 诊断留痕：一行写完（跨行隐式拼接在 v2 里要靠续行规则，写死一行更稳）
        traceExtra := "fold=" foldIndex " mode=" mode " anchor=" anchor " off=" offX "," offY " pos=" ballPos.x "," ballPos.y " scr=" (isScreenMode ? 1 : 0) " tgt=" targetHwnd
        this._BallTrace("ball-build", panelKey, "", traceExtra)

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
            noActivate: true,
            ; 句柄回传前 wpfHwnd 是 0：让 200ms 一次的巡检跳过，别当成「用户关窗」销毁
            _creating: true,
            ; 精确对齐用的物理坐标（DIP 换算有取整误差），就绪后由 _WaitPanelHwnd 补做
            _ballPos: ballPos,
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
            ; 与面板同一套位置模型：跟随定时器据此逐帧摆位（mode = 1 的绝对坐标不跟随）
            posMode: mode,
            anchor: anchor,
            offsetX: offX,
            offsetY: offY,
            lastSetX: "",
            lastSetY: "",
            ; 句柄回传后才置 true：跟随定时器据此跳过还没建出来的窗口
            panelReady: false
        }
    }

    ; 引擎在 WPF UI 线程内完成拖动；AHK 只处理点击和最终落点。
    _OnBallGesture(panelKey, state, *) {
        if (!IsObject(state) || !state.Has("BallDrag"))
            return
        gesture := String(state["BallDrag"])
        info := this._FindPanelInfo(panelKey)
        ; 按下：从现在起到松手，窗口位置由引擎逐帧接管，跟随定时器必须让开，
        ; 否则每 50ms 会把球拽回上一次的位置（慢速拖动时尤其明显，像有黏性）。
        if (gesture == "down") {
            if (IsObject(info)) {
                info._ballDragging := true
                ; 记时间戳：引擎的 move/up 一旦丢失，靠它超时解锁跟随（见 FollowSinglePanel）
                info._ballDragAt := A_TickCount
            }
            this._BallTrace("gesture", panelKey, info, "down")
            return
        }
        ; 拖动心跳（引擎每 60ms 一条）：窗口位置由引擎逐帧接管，这里只刷新「还在拖」的时间戳。
        ; 必须放在清 _ballDragging 之前 —— 心跳和结束事件走同一条通道，只是语义不同。
        if (SubStr(gesture, 1, 5) == "drag|") {
            if (IsObject(info)) {
                info._ballDragging := true
                info._ballDragAt := A_TickCount
            }
            return
        }
        if (IsObject(info))
            info._ballDragging := false
        this._BallTrace("gesture", panelKey, info, gesture)
        if (gesture == "click") {
            this._BallToPanel(panelKey)
            return
        }
        ; 异常收尾（捕获丢失）：以当前窗口矩形为落点，别让球弹回原位
        if (gesture == "up") {
            if (IsObject(info) && info.wpfHwnd) {
                px := 0, py := 0
                try WinGetPos(&px, &py, , , "ahk_id " info.wpfHwnd)
                if (px != 0 || py != 0)
                    this._BallAdoptPos(info, px, py)
            }
            return
        }
        ; 拖动松手：引擎已经把窗口拖到落点。和面板拖动同一套处理 —— 把落点换算成
        ; 「相对目标窗口的偏移」，之后跟随定时器就从这个新偏移继续跟，球停在落点。
        if (SubStr(gesture, 1, 5) != "move|")
            return
        if (!IsObject(info))
            return
        coords := StrSplit(SubStr(gesture, 6), ",", , 2)
        if (coords.Length != 2)
            return
        x := Trim(coords[1]), y := Trim(coords[2])
        if (!IsInteger(x) || !IsInteger(y))
            return
        this._BallAdoptPos(info, Integer(x), Integer(y))
    }

    ; 把球摆到 (x, y)（物理像素），并把该位置折算成跟随用的偏移。
    ; 拖动松手、以及绝对坐标模式下的显式定位都走这里。
    _BallAdoptPos(info, x, y, size := 56) {
        if (!IsObject(info))
            return
        pos := this._ClampBallPos(x, y, size)
        mode := info.HasProp("posMode") ? info.posMode : 0
        if (mode == 1) {
            info.offsetX := pos.x
            info.offsetY := pos.y
        } else {
            baseLeft := 0, baseTop := 0, contW := A_ScreenWidth, contH := A_ScreenHeight
            if (!info.isScreenMode && info.targetHwnd) {
                try {
                    rect := this.GetWindowRectCoords(info.targetHwnd)
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
            bsp := Round(size * (A_ScreenDPI / 96))
            ax := 0, ay := 0
            anchor := info.HasProp("anchor") ? info.anchor : 6
            this._AnchorBase(anchor, bsp, bsp, contW, contH, &ax, &ay)
            info.offsetX := pos.x - baseLeft - ax
            info.offsetY := pos.y - baseTop - ay
        }
        info.lastSetX := pos.x
        info.lastSetY := pos.y
        info._manualPos := true
        info._ballPos := pos
        ; SWP_NOACTIVATE：拖动结束后对齐也不能把焦点抢回去
        if (info.wpfHwnd)
            try DllCall("user32\SetWindowPos", "Ptr", info.wpfHwnd, "Ptr", 0
                , "Int", pos.x, "Int", pos.y, "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0004 | 0x0010)
    }

    ; 悬浮球跟随诊断：只在「同一个 key + tag 的状态内容变了」时写一行，
    ; 50ms 的跟随定时器不会刷爆日志。只记球（传面板时直接跳过）。
    ; 文件：Log\UIMacroBall.log，累计 400 行后停写。
    _BallTrace(tag, panelKey, info := "", extra := "") {
        static last := Map()
        static count := 0
        if (IsObject(info) && !(info.HasProp("_isBall") && info._isBall))
            return
        line := ""
        if (IsObject(info)) {
            line := "ball=1"
                . " mode=" (info.HasProp("posMode") ? info.posMode : "?")
                . " anchor=" (info.HasProp("anchor") ? info.anchor : "?")
                . " off=" (info.HasProp("offsetX") ? info.offsetX : "?") "," (info.HasProp("offsetY") ? info.offsetY : "?")
                . " drag=" (info.HasProp("_ballDragging") && info._ballDragging ? 1 : 0)
                . " ready=" (info.HasProp("panelReady") && info.panelReady ? 1 : 0)
                . " scr=" (info.HasProp("isScreenMode") && info.isScreenMode ? 1 : 0)
                . " tgt=" (info.HasProp("targetHwnd") ? info.targetHwnd : 0)
                . " hwnd=" (info.HasProp("wpfHwnd") ? info.wpfHwnd : 0)
        }
        if (extra != "")
            line .= " " extra
        ; 焦点诊断：球一旦成为前台窗口，说明「不激活」没生效（样式没打上，或引擎还是旧 dll
        ; 没重编）。只在真抢到时追加标记，正常情况下这行永远不出现。
        if (IsObject(info) && info.HasProp("wpfHwnd") && info.wpfHwnd
            && DllCall("user32\GetForegroundWindow", "Ptr") == info.wpfHwnd)
            line .= " FOREGROUND"
        key := String(panelKey) "|" tag
        if (last.Has(key) && last[key] == line)
            return
        last[key] := line
        if (count >= 2000)
            return
        count += 1
        try FileAppend(FormatTime(A_Now, "HH:mm:ss") " [" tag "] " key " " line "`n"
            , A_ScriptDir "\Log\UIMacroBall.log")
    }

    _BallToPanel(panelKey) {
        this._ToggleBall(panelKey, false)
    }

    ; 球 → 面板：把球当前位置折算成面板的「跟随偏移」，交给紧接着的这次建窗
    ; （_PlaceByFold 用它算初始 Left/Top），视觉上就是「就地放大」，不会先闪到默认锚点。
    _QueuePanelPosFromBall(foldIndex, ballInfo) {
        if (!IsObject(ballInfo))
            return
        if (!(ballInfo.HasProp("_ballPos") && IsObject(ballInfo._ballPos)))
            return
        ; 面板尺寸与 _BuildCustomPanel 同口径：宽 = 设计宽 + 10；高 = 标题 30 + 设计高 + 8 + 2
        pw := 250, ph := 200
        schema := this._GetCustomSchema(foldIndex)
        if (IsObject(schema) && schema.HasProp("window") && IsObject(schema.window)) {
            w := Integer(schema.window.width)
            h := Integer(schema.window.height)
            if (w > 0 && h > 0) {
                pw := w + 10
                ph := 30 + h + 8 + 2
            }
        } else {
            ; 按钮面板没有 schema：尺寸按按钮网格算（与 BuildXAMLPanel 同口径），
            ; 否则「从球就地放大」时面板中心会从球心偏出去。
            n := this._CollectBtnItems(foldIndex).Length
            if (n > 0) {
                iw := MainSoftData.UIPanelBtnWidth
                ih := MainSoftData.UIPanelBtnHeight
                c := Max(1, Integer(MainSoftData.UIPanelCols))
                r := Ceil(n / c)
                pw := c * (iw + 4) + 8
                ph := 30 + r * ih + (r - 1) * 2 + 6 + 2
            }
        }
        scale := A_ScreenDPI / 96
        pw := Round(pw * scale)
        ph := Round(ph * scale)
        bsp := Round(56 * scale)
        baseLeft := 0, baseTop := 0, contW := A_ScreenWidth, contH := A_ScreenHeight
        if (!ballInfo.isScreenMode && ballInfo.targetHwnd) {
            try {
                rect := this.GetWindowRectCoords(ballInfo.targetHwnd)
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
        ax := 0, ay := 0
        anchor := ballInfo.HasProp("anchor") ? ballInfo.anchor : 6
        this._AnchorBase(anchor, pw, ph, contW, contH, &ax, &ay)
        ; 面板中心对上球心
        cx := ballInfo._ballPos.x + bsp // 2
        cy := ballInfo._ballPos.y + bsp // 2
        this._pendingPanelPos[foldIndex] := {
            offX: cx - pw // 2 - baseLeft - ax
            , offY: cy - ph // 2 - baseTop - ay
        }
    }

    ; 取某个窗口的矩形，算「球占它正中央」时的物理坐标
    _CenteredBallPos(hwnd) {
        try {
            r := this.GetWindowRectCoords(hwnd)
            w := r["right"] - r["left"]
            h := r["bottom"] - r["top"]
            if (w > 0 && h > 0) {
                bsp := Round(56 * A_ScreenDPI / 96)
                return this._ClampBallPos(r["left"] + (w - bsp) // 2
                    , r["top"] + (h - bsp) // 2)
            }
        }
        return ""
    }

    ; 球不许跑到屏幕外：桌面上找不到入口，比位置差几像素糟得多。
    ; 用整个虚拟屏幕（多显示器）兜底，而不是只看主屏。
    _ClampBallPos(x, y, size := 56) {
        bsp := Round(size * A_ScreenDPI / 96)
        vx := DllCall("user32\GetSystemMetrics", "Int", 78, "Int")   ; SM_XVIRTUALSCREEN
        vy := DllCall("user32\GetSystemMetrics", "Int", 79, "Int")   ; SM_YVIRTUALSCREEN
        vw := DllCall("user32\GetSystemMetrics", "Int", 76, "Int")   ; SM_CXVIRTUALSCREEN
        vh := DllCall("user32\GetSystemMetrics", "Int", 77, "Int")   ; SM_CYVIRTUALSCREEN
        if (vw <= 0 || vh <= 0) {
            vx := 0, vy := 0, vw := A_ScreenWidth, vh := A_ScreenHeight
        }
        return { x: Max(vx, Min(vx + Max(0, vw - bsp), x))
            , y: Max(vy, Min(vy + Max(0, vh - bsp), y)) }
    }

    _TakePendingBallHome(panelKey) {
        if (!this._pendingBallHome.Has(panelKey))
            return ""
        home := this._pendingBallHome[panelKey]
        this._pendingBallHome.Delete(panelKey)
        return home
    }

    ; 球的窗口样式：不进任务栏 / Alt+Tab、点击不激活。z 序交给属主（与面板同款）。
    ;
    ; 以前球是不带属主的独立 Topmost 窗口，为的是「始终浮在目标窗口上」。代价是它同时
    ; 浮在了所有窗口之上：目标窗口被遮挡它还在，最小化后它还留在桌面上。现在改成
    ; 属主 = 目标窗口（见 _WaitPanelHwnd），z 序由系统按「紧贴在属主之上」维护，
    ; 显隐也跟着属主走 —— 面板怎么表现，球就怎么表现。
    ; 只有屏幕模式（没有目标窗口、也就没有属主）的球才需要自己 Topmost。
    ;
    ; 不抢焦点这件事的主战场在引擎侧：XAML 根上带 Tag="BallNoActivate"，FirstFrame 在
    ; EnsureHandle 之后、Show 之前就打上 WS_EX_NOACTIVATE（那时系统刚注册完窗口样式，
    ; 中间没有任何「可激活」的空档）。这里只做兜底 —— 句柄万一被重建、或引擎侧那段
    ; 异常被吞掉，样式还能补回来。
    _ApplyBallWindowStyle(info) {
        if (!IsObject(info) || !info.wpfHwnd || !DllCall("user32\IsWindow", "Ptr", info.wpfHwnd))
            return
        hwnd := info.wpfHwnd
        ex := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
        want := ex | 0x80 | 0x08000000        ; WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
        if (want != ex)
            try DllCall("user32\SetWindowLongW", "Ptr", hwnd, "Int", -20, "Int", want)
        owned := (!info.isScreenMode && info.targetHwnd)
        if (!owned)
            try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        info._topmostDone := true
        ; 样式是否真的落上了：引擎是旧 dll（Tag 那段没重编）时这里会是 noact=0
        exNow := DllCall("user32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "Int")
        this._BallTrace("style", "", info
            , "noact=" ((exNow & 0x08000000) ? 1 : 0) " tool=" ((exNow & 0x80) ? 1 : 0))
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
        ; 逐条 Update 是逐次同步往返：控件多的面板切一页就要几十趟。合并成一条批量下发。
        updates := []
        for ctrl in schema.controls {
            pg := (ctrl.HasProp("page") ? Integer(ctrl.page) : 1)
            updates.Push({ ControlName: UIMacroRenderer.NameOf(ctrl.id)
                , PropertyName: "Visibility", Value: pg = cur ? "Visible" : "Collapsed" })
        }
        ; 当前页码：反白（底色=标题文字色、文字=标题底色），一眼能看出在哪页
        loop pages {
            on := (A_Index == cur)
            updates.Push({ ControlName: "BtnPage" A_Index
                , PropertyName: "Background", Value: on ? "{DynamicResource UIPanelTitleText}" : "Transparent" })
            updates.Push({ ControlName: "PageNum" A_Index
                , PropertyName: "Foreground", Value: on ? "{DynamicResource UIPanelTitleBg}" : "{DynamicResource UIPanelTitleText}" })
            updates.Push({ ControlName: "PageNum" A_Index
                , PropertyName: "FontWeight", Value: on ? "Bold" : "Normal" })
        }
        try info.ui.BatchUpdate(updates)
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
            return this._BuildCustomBall(foldIndex, targetHwnd, isScreenMode, panelKey)

        ; 输入框和下拉框需要键盘焦点，纯按钮面板保留当前前台窗口。
        noActivate := true
        for ctrl in schema.controls {
            if (ctrl.type == "Edit" || ctrl.type == "ComboBox") {
                noActivate := false
                break
            }
        }

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

        tableItem := this.GetTable()
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
        ; 两个按钮画成「实色圆点 / 字符 ×」，不走 DynamicResource、也不用图标字体：
        ; 图标字体在部分机器上回退失败时 E8BB 会渲染成方框或空白，看起来就是「标题栏
        ; 上没有圆点和 ×」；DynamicResource 在窗口作用域里缺定义时同样会解析成空画刷。
        ; 颜色直接取面板标题文字色（和标题同一来源），保证任何主题下都看得见。
        for name in ["BtnPanelBall", "BtnPanelClose"] {
            b := tbBtns.Add("Button").Name(name)
                ; 标题栏属于 WindowChrome 的 caption 区：不声明可命中就点不动
                .WindowChrome_IsHitTestVisibleInChrome("True")
                .Width(22).Height(20).MinHeight(20).Margin("2,0,0,0")
                .Padding("0").Cursor("Hand")
                .Background("Transparent").BorderThickness("0")
            try b.InjectResources(UIMacroRenderer.BtnStyle)
            if (name == "BtnPanelBall") {
                ; 收起 = 悬浮球：直接画一个小圆点，比图标字形的「一横」更表意
                b.Add("Border").Width(8).Height(8).CornerRadius("4")
                    .Background(titleText)
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
            } else {
                b.Add("TextBlock").Name(name "Glyph").Text("×")
                    .FontSize("13").FontWeight("SemiBold").Foreground(titleText)
                    .VerticalAlignment("Center").HorizontalAlignment("Center")
                    .Margin("0,0,0,1")
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
        if (noActivate || skipActivate)
            ui.xaml := StrReplace(ui.xaml, 'ShowInTaskbar="False"', 'ShowInTaskbar="False" ShowActivated="False"')
        ; 建窗异步：Show 只投递不阻塞（同步等 daemon 建窗要 200~700ms，最坏 2s）。
        ; 分页初值不在这里下发：放到 _WaitPanelHwnd 的就绪分支，和主题刷新错开，
        ; 也避免首帧先把所有页的控件都画一遍再隐藏。
        ui.asyncCreate := true
        ; 自定义面板的刷新全在按键/切页/状态色上，同步 IPC 会直接压在输入手感上
        ui.asyncUpdate := true
        ui.Show()

        return {
            ui: ui,
            wpfHwnd: ui.HasProp("wpfHwnd") ? ui.wpfHwnd : 0,
            _creating: true,          ; 句柄未回传：CheckAllPanels 不能当「窗口已失效」销毁
            _skipActivate: skipActivate,
            panelKey: panelKey,
            foldIndex: foldIndex,
            foldID: fold ? fold.ID : "",
            targetHwnd: targetHwnd,
            isScreenMode: isScreenMode,
            frontInfo: fold ? fold.FrontInfo : "",
            visible: true,
            btnItems: [],
            _isCustom: true,
            noActivate: noActivate,
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
    ; 建窗已改异步（见各 Build* 里的 asyncCreate）：这里不再 Sleep 阻塞等句柄，
    ; 句柄未回传就挂 20ms 轮询，就绪后再补做激活/分页初值/定位/回填。
    WaitForPanelReady(panelKey) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!panelInfo || !IsObject(panelInfo.ui))
            return
        ; 世代号：同一 panelKey 被销毁重建时，上一轮轮询自动失效
        this._panelGen += 1
        gen := this._panelGen
        panelInfo._buildGen := gen
        panelInfo._buildTick := A_TickCount
        this._WaitPanelHwnd(panelKey, gen)
    }

    ; 轮询句柄是否回传，就绪后执行原本在 WaitForPanelReady 里同步做完的初始化。
    _WaitPanelHwnd(panelKey, gen) {
        panelInfo := this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : ""
        if (!IsObject(panelInfo) || !IsObject(panelInfo.ui)) {
            this._StopWaitTimer(panelKey)
            return
        }
        if (panelInfo.HasProp("_buildGen") && panelInfo._buildGen != gen) {
            this._StopWaitTimer(panelKey)
            return
        }
        hwnd := panelInfo.ui.HasProp("wpfHwnd") ? panelInfo.ui.wpfHwnd : 0
        if (!hwnd) {
            ; 5 秒还没建出来就别把面板永远挂在 _creating 上，交回 CheckAllPanels 处理
            if (A_TickCount - panelInfo._buildTick > 5000) {
                panelInfo._creating := false
                this._StopWaitTimer(panelKey)
                return
            }
            ; 必须「先停旧的，再起新的」：SetTimer(ObjBindMethod(...)) 每次调用都是一个新的
            ; 函数对象 = 一个新的定时器，旧的不会自己消失。这里以前是每 20ms 顺手再起一个，
            ; 句柄回传后那批定时器仍按 20ms 一直跑到进程结束。
            ; 面板那条分支靠「panelReady 就返回」挡住了，球那条分支没有这道闸 ——
            ; 于是每个残留回调都会把球搬回建窗时的坐标、重设一次属主与扩展样式，
            ; 画面就在「旧位置 / 新位置」之间来回闪，而且定时器越攒越多、越闪越快。
            this._RestartWaitTimer(panelKey, gen)
            return
        }
        this._StopWaitTimer(panelKey)

        panelInfo.wpfHwnd := hwnd
        panelInfo._creating := false
        ; 就绪只做一次：与面板分支同口径。球的初始化里有 SetWindowPos(_ballPos) 与
        ; 属主/样式设置，重复执行就是把球拽回建窗位置。
        if (panelInfo.HasProp("panelReady") && panelInfo.panelReady)
            return
        ; 悬浮球：位置在建窗前已写进 XAML，这里先补一次物理像素精确对齐，再走跟随。
        if (panelInfo.HasProp("_isBall") && panelInfo._isBall) {
            ; 属主 = 目标窗口：和面板完全同一套「压在目标窗口上」的机制。
            ; 不只是 z 序 —— 目标窗口最小化 / 被隐藏时系统会把属主窗口一起收起来，
            ; 被别的窗口盖住时也随目标窗口一起被盖住。球以前用独立 Topmost 顶在所有人上面，
            ; 于是最小化后还留在桌面上、被遮挡时也还露着。
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd)
                try panelInfo.ui.Update("Window", "NativeOwner", String(panelInfo.targetHwnd))
            if (IsObject(panelInfo._ballPos))
                try DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                    , "Int", panelInfo._ballPos.x, "Int", panelInfo._ballPos.y, "Int", 0, "Int", 0
                    , "UInt", 0x0001 | 0x0004 | 0x0010)   ; + SWP_NOACTIVATE：定位不抢焦点
            ; 球不占任务栏 / 不进 Alt+Tab、点击不激活
            this._ApplyBallWindowStyle(panelInfo)
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd)
                ; 属主刚设上，抬到属主窗口正上方（不移动、不改大小、不抢焦点）
                try DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
                    , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                    , "UInt", 0x0001 | 0x0002 | 0x0010)
            panelInfo.panelReady := true
            this._BallTrace("ball-ready", panelKey, panelInfo)
            ; 和面板一样跟随目标窗口：同一条 50ms 跟随定时器，只是尺寸换成球径
            this.FollowSinglePanel(panelKey)
            this.StartFollowTimer(panelKey)
            return
        }
        ; 已经就绪过就别重跑（重复调 WaitForPanelReady 会重启跟随定时器、重填绑定）
        if (panelInfo.HasProp("panelReady") && panelInfo.panelReady)
            return
        if (!panelInfo.noActivate && !panelInfo._skipActivate) {
            ; 建窗改异步后，这段激活比原来晚了一两百毫秒：期间用户可能已经切走。
            ; 目标窗口不再是前台就别抢焦点，否则会把人正在操作的窗口顶掉。
            activate := true
            if (!panelInfo.isScreenMode && panelInfo.targetHwnd) {
                try activate := (WinGetID("A") == panelInfo.targetHwnd)
            }
            if (activate)
                try WinActivate("ahk_id " hwnd)
        }

        ; 自定义面板的分页初值：等窗口建出来再下发，一条批量解决；建窗函数里做会撞上
        ; 主题刷新的首帧，先按「全部页可见」画一遍再隐藏，出现一下抖动。
        if (panelInfo.HasProp("_pages") && panelInfo._pages > 1) {
            this._panelPage[panelKey] := 1
            schema := this._GetCustomSchema(panelInfo.foldIndex)
            if (IsObject(schema))
                this._ApplyPanelPage(panelKey, schema, panelInfo._pages, 1)
        }

        ; 对齐 L355: g_panelReady := true
        panelInfo.panelReady := true
        ; 对齐 L356: OnPanelReady()
        this.OnPanelReady(panelKey)
    }

    ; 建窗就绪轮询：同一个 panelKey 始终只保留一个定时器。
    ; 旧写法 SetTimer(ObjBindMethod(...), 20) 在每次回调里重新绑定，AHK 会当成新定时器，
    ; 旧的继续按 20ms 触发 —— 这是「球来回闪、越闪越快」的根因。
    _RestartWaitTimer(panelKey, gen) {
        this._StopWaitTimer(panelKey)
        cb := ObjBindMethod(this, "_WaitPanelHwnd", panelKey, gen)
        this._waitFns[panelKey] := cb
        SetTimer(cb, 20)
    }

    _StopWaitTimer(panelKey) {
        if (this._waitFns.Has(panelKey)) {
            try SetTimer(this._waitFns[panelKey], 0)
            this._waitFns.Delete(panelKey)
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
                , exStyle | 0x80 | (panelInfo.noActivate ? 0x08000000 : 0)) ; WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
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

        ; L387: 立即定位一次。绝对坐标模式按位置记忆摆，其余按锚点摆；
        ; 之后交给跟随定时器（mode = 1 的闸门会让它保持不动）。
        this.ApplyPanelPosition(panelInfo)
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
        isBall := (panelInfo.HasProp("_isBall") && panelInfo._isBall)
        ; 球被按住拖动时，窗口位置由引擎在 WPF 侧逐帧接管；这里插一脚只会把它拽回去。
        ;
        ; 判据只看「心跳新鲜度」：引擎每次移动都会发一条 drag|x,y（限频 60ms），收到就刷新
        ; _ballDragAt。这里曾经补过一条 GetKeyState("LButton","P")，实测每次都把正在进行的
        ; 拖动判成「已松手」（日志里 down 与 drag-release 同一秒），于是跟随定时器 50ms 一次
        ; 把球拽回起点、引擎下一帧又拖走 —— 表现为新旧两点之间来回闪。
        ; 心跳停了 3 秒 = 松手事件丢了或引擎异常，按「已结束」处理，避免永久停摆。
        if (panelInfo.HasProp("_ballDragging") && panelInfo._ballDragging) {
            at := panelInfo.HasProp("_ballDragAt") ? panelInfo._ballDragAt : 0
            if (at && A_TickCount - at < 3000) {
                this._BallTrace("follow-hold", panelKey, panelInfo)
                return
            }
            ; 解除前以窗口当前矩形为落点折算偏移，否则跟随一恢复就把球弹回拖动前的位置
            px := 0, py := 0
            try {
                if (panelInfo.wpfHwnd && DllCall("user32\IsWindow", "Ptr", panelInfo.wpfHwnd))
                    WinGetPos(&px, &py, , , "ahk_id " panelInfo.wpfHwnd)
            } catch {
            }
            panelInfo._ballDragging := false
            ; 只有球才需要把落点折算回偏移（球的位置就等于偏移 + 窗口矩形）；
            ; 面板有 lastSetX 那套自纠，这里多插一脚反而会改掉它的偏移。
            if (isBall && (px != 0 || py != 0))
                this._BallAdoptPos(panelInfo, px, py)
            this._BallTrace("drag-release", panelKey, panelInfo, "pos=" px "," py)
        }
        ; 只有绝对坐标模式（posMode = 1）才用位置记忆锁定，不再跟随。
        ; 相对锚点模式必须始终跟随：拖动面板产生的偏差，会被下面的 lastSetX 对比
        ; 吸收进 offsetX（拖动 → 相对偏移改变 → 继续跟随），不需要这道闸门。
        ; 早先这里对两种模式都判「有记忆就不跟随」，于是收起成球/隐藏时顺手记下的
        ; 一次位置，就会让面板此后永久停在旧坐标、再也不跟目标窗口。
        if ((panelInfo.HasProp("posMode") ? panelInfo.posMode : 0) == 1
            && IsObject(this._PosGet("UIPanelPos", panelInfo.foldIndex, panelInfo.targetHwnd))) {
            this._BallTrace("skip-abs", panelKey, panelInfo)
            return
        }
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
        ; 目标窗口最小化时 GetWindowRect 给出 -32000 这类哨兵值，照算会把浮窗甩到屏幕外
        ; （巡检 200ms 之后才隐藏，肉眼能看到它闪一下）。位置保持不动即可。
        if (DllCall("user32\IsIconic", "Ptr", panelInfo.targetHwnd))
            return

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
            pw := isBall ? Round(56 * A_ScreenDPI / 96) : 250
        if (ph <= 0)
            ph := isBall ? Round(56 * A_ScreenDPI / 96) : 200

        ; 绝对坐标固定在屏幕上。相对坐标跟随目标窗口，锚点随窗口尺寸变化。
        ;
        ; 「窗口实际矩形 ≠ 我上次设的坐标」= 有人搬过这个窗口 → 把偏差吸收进偏移。
        ; 面板和球共用这一条，它也是「拖动」的全部机制：系统拖窗 / 引擎逐帧搬窗时
        ; AHK 都没有回调，只能事后从矩形反推新偏移。
        ; 少了它，跟随定时器每 50ms 会按旧偏移把窗口写回去、拖动方下一帧再搬走 ——
        ; 画面就是「起点和当前点来回闪」。
        ;
        ; 但要扣掉「目标窗口自己动了」这一种：那一刻浮窗还没跟上属于正常，若也吸收，
        ; 一旦某次 SetWindowPos 没落地，偏移就会被改成与旧位置自洽的值，此后每帧都
        ; 算回同一个坐标 —— 早先的「球永远不跟窗口」正是这么来的。
        mode := panelInfo.HasProp("posMode") ? panelInfo.posMode : 0
        anchorX := 0, anchorY := 0
        anchor := panelInfo.HasProp("anchor") ? panelInfo.anchor : 6
        this._AnchorBase(anchor, pw, ph, winW, winH, &anchorX, &anchorY)
        lastWinX := panelInfo.HasProp("lastWinX") ? panelInfo.lastWinX : ""
        lastWinY := panelInfo.HasProp("lastWinY") ? panelInfo.lastWinY : ""
        winMoved := (lastWinX != "" && (rect["left"] != lastWinX || rect["top"] != lastWinY))
        hasLast := (panelInfo.lastSetX != "" && panelInfo.lastSetY != "")
        if (hasLast && (mode == 1 || !winMoved)
            && (Abs(panelRect["left"] - panelInfo.lastSetX) > 3
                || Abs(panelRect["top"] - panelInfo.lastSetY) > 3)) {
            if (mode == 1) {
                panelInfo.offsetX := panelRect["left"]
                panelInfo.offsetY := panelRect["top"]
            } else {
                panelInfo.offsetX := panelRect["left"] - rect["left"] - anchorX
                panelInfo.offsetY := panelRect["top"] - rect["top"] - anchorY
            }
        }
        if (mode == 1) {
            newX := panelInfo.offsetX
            newY := panelInfo.offsetY
        } else {
            newX := rect["left"] + anchorX + panelInfo.offsetX
            newY := rect["top"] + anchorY + panelInfo.offsetY
        }
        insertAfter := panelInfo.targetHwnd
        flags := 0x0001 | 0x0004 | 0x0010 | 0x4000   ; + SWP_ASYNCWINDOWPOS
        if (isBall) {
            ; 球几十像素，同步移动的代价可以忽略；跨线程投递（ASYNCWINDOWPOS）在 daemon
            ; 忙于渲染时会把移动延后落地，看着就是「球跟不上窗口」。同步 + 不传
            ; hwndInsertAfter（SWP_NOZORDER 本来也不看它，z 序交给属主）。
            insertAfter := 0
            flags := 0x0001 | 0x0004 | 0x0010
        }
        DllCall("user32\SetWindowPos"
            , "Ptr", hwnd
            , "Ptr", insertAfter
            , "Int", newX, "Int", newY
            , "Int", 0, "Int", 0
            , "UInt", flags)
        ; 记录本次设置的目标位置，供下次回调对比
        panelInfo.lastSetX := newX
        panelInfo.lastSetY := newY
        ; 同时记下这一帧用的目标窗口矩形：下次判断「偏差是不是因为目标窗口自己移动」用
        panelInfo.lastWinX := rect["left"]
        panelInfo.lastWinY := rect["top"]
        ; 球的每帧落位留痕（内容不变不写）：SetWindowPos 没落地时能在这里一眼看出来
        if (isBall && A_TickCount - (panelInfo.HasProp("_traceAt") ? panelInfo._traceAt : 0) > 500) {
            panelInfo._traceAt := A_TickCount
            act := this.GetWindowRectCoords(hwnd)
            this._BallTrace("follow-move", panelKey, panelInfo
                , "want=" newX "," newY " got=" act["left"] "," act["top"] " win=" rect["left"] "," rect["top"])
        }
    }

    ; 切换可见性（严格对齐 floating_panel TogglePanelVisibility L490-513）
    TogglePanel(foldIndex) {
        ; 用户主动打开 → 解除「已关闭」，恢复自动显示
        if (this.UserClosedFolds.Has(foldIndex))
            this.UserClosedFolds.Delete(foldIndex)
        ; 创建进行中：忽略本次触发，避免在 PanelMap 写入前重入创建出重复面板
        if (this.IsCreating)
            return

        tableItem := this.GetTable()
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

        ; 球和面板是同一个浮窗的两种显示状态：热键只负责打开 / 关闭。
        ; 球态下关闭就是球消失，再按一次球原样回来，不会被换成面板；
        ; 形态切换只由标题栏小圆点 / 短按球触发，热键不参与。
        isBall := (panelInfo.HasProp("_isBall") && panelInfo._isBall)

        ; 配置变化检测：按钮尺寸/列数/颜色变化时销毁重建（球不受按钮配置影响）
        if (!isBall && panelInfo.visible == false  ; 只在从隐藏→显示时检查
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
            ; 球拖动后是「相对目标窗口的偏移」记在 offsetX/offsetY 上，重算回模块默认值
            ; 会让它跳回原位，所以球被拖过就保留偏移。
            if (!(isBall && panelInfo.HasProp("_manualPos") && panelInfo._manualPos)) {
                this._ResetPosFromFold(panelInfo)
                panelInfo.lastSetX := ""
                panelInfo.lastSetY := ""
            }
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
        this._StopWaitTimer(panelKey)

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
            ; 建窗是异步的：句柄回传前 wpfHwnd 还是 0，这不是「窗口已失效」，
            ; 不跳过的话 200ms 一次的巡检会把刚建的面板当成用户关闭直接销毁。
            if (panelInfo.HasProp("_creating") && panelInfo._creating)
                continue
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

            ; 處理目標視窗隱藏/退到後台時，浮窗隱藏；重新顯現時浮窗也重新顯現。
            ; 球和面板是同一浮窗的两种状态，这里一视同仁：目标窗口最小化时球跟着收起，
            ; 恢复时再出来 —— 这正是「跟随窗口」的一半（另一半是位置跟随）。
            isBallNow := (panelInfo.HasProp("_isBall") && panelInfo._isBall)
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

            ; 球的 z 序交给属主维护（系统保证紧贴在目标窗口之上），这里不再重复置顶 ——
            ; 再 Topmost 一次就等于把「被遮挡时跟着一起被挡住」这个行为又破坏掉。
            ; 只有屏幕模式的球没有属主，才需要常驻最上层，被别的置顶窗挤下去后由这里补回来。
            if (isBallNow) {
                if (panelInfo.visible && panelInfo.isScreenMode)
                    this._EnsureTopmost(panelInfo, panelInfo.wpfHwnd)
                continue
            }

            if (!panelInfo.isScreenMode)
                continue
            if (!panelInfo.visible)
                continue

            hwnd := panelInfo.wpfHwnd
            ; 与 FollowSinglePanel 共用同一套闸门（只设一次 + 菜单期间暂停 + 超时自愈）
            this._EnsureTopmost(panelInfo, hwnd)
        }
        ; 跟随定时器自愈：定时器是按 panelKey 存放的，收球 / 展开 / 重建时只要有一次
        ; StartFollowTimer 没跑到（旧窗口的 Closed 事件把新定时器停掉、回调中途异常、
        ; 建窗回调还没执行到尾部），对应浮窗就永久停在原地且没有任何恢复路径。
        ; 巡检每 200ms 补一次，缺了就立刻补上；正常情况下只是几次 Map 查询。
        for panelKey, panelInfo in this.PanelMap {
            if (!panelInfo.visible || panelInfo.isScreenMode)
                continue
            if (!(panelInfo.HasProp("panelReady") && panelInfo.panelReady))
                continue
            ; 判据用浮窗自身的 _followOn（不是 PanelTimers 的键）：两套 Map 万一键类型
            ; 不一致，「没有定时器」会永远成立，就成了每 200ms 造一个 50ms 定时器。
            if (panelInfo.HasProp("_followOn") && panelInfo._followOn)
                continue
            this._BallTrace("timer-revive", panelKey, panelInfo)
            this.StartFollowTimer(panelKey)
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

                    tableItem := this.GetTable()
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
        if (this.PanelMap.Has(panelKey))
            this.PanelMap[panelKey]._followOn := true
        this._BallTrace("timer-start", panelKey, this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : "")
    }

    ; 停止跟随定时器（对齐 floating_panel L517: SetTimer(FollowTarget, 0)）
    StopFollowTimer(panelKey) {
        if (!this.PanelTimers.Has(panelKey))
            return
        cb := this.PanelTimers[panelKey]
        if (cb)
            SetTimer(cb, 0)
        this.PanelTimers.Delete(panelKey)
        if (this.PanelMap.Has(panelKey))
            this.PanelMap[panelKey]._followOn := false
        this._BallTrace("timer-stop", panelKey, this.PanelMap.Has(panelKey) ? this.PanelMap[panelKey] : "")
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

            ; 恢复目标焦点后再分派，避免本地执行时阻塞焦点恢复。
            this.RestoreTargetFocus(panelKey)
            if (item.ColorState == 1 || item.ColorState == 2
                || (WorkPoolEnabled() && MyWorkPool.HasItemWork(tableItem.ID, item.ID))) {
                MyStopMacro(tableItem, item.ID)
            } else {
                SetTimer(TriggerMacroHandler.Bind(tableItem.ID, item.ID), -1)
            }
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

    ; 更新按钮状态色点
    UpdateButtonStatus(macroIndex, state) {
        for foldIndex, panelInfo in this.PanelMap {
            if (!panelInfo.ui || !panelInfo.btnItems)
                continue
            for item in panelInfo.btnItems {
                if (item.macroIndex == macroIndex) {
                    stateName := item.name "_State"
                    updates := []
                    if (state == UIMacroGui.STATE_DEFAULT)
                        updates.Push({ ControlName: stateName, PropertyName: "Visibility", Value: "Collapsed" })
                    else if (MacroStateColors.Has(state)) {
                        updates.Push({ ControlName: stateName, PropertyName: "Visibility", Value: "Visible" })
                        updates.Push({ ControlName: stateName, PropertyName: "Fill", Value: MacroStateColors[state] })
                    }
                    ; 两条属性合并成一次 BatchUpdate：少一趟同步往返，引擎侧只结算一次布局
                    if (updates.Length)
                        try panelInfo.ui.BatchUpdate(updates)
                    ; 这里不再补 SetWindowPos：改的是控件属性，窗口矩形没有变；
                    ; 跟随定时器（50ms）下一帧就会按当前偏移摆正，多搬一次反而是
                    ; 一次白跑的跨线程窗口移动（宏快速循环时按步频触发）。
                    break
                }
            }
        }
    }

    UpdateButtonsState(macroIndex, state) {
        this.UpdateButtonStatus(macroIndex, state)
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
        tableItem := this.GetTable()
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
        if (this.TableID == "") {
            for _, panel in UIMacroGui.AdditionalTables
                panel.ApplyThemeColors()
        }
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
            DllCall("user32\ShowWindow", "Ptr", panelInfo.wpfHwnd, "Int", panelInfo.noActivate ? 8 : 9)
            if (panelInfo.isScreenMode) {
                WinSetAlwaysOnTop(1, "ahk_id " panelInfo.wpfHwnd)
            }

            ; Show 之后重新应用默认位置（WPF Show 会恢复上次位置）
            this.ApplyPanelPosition(panelInfo)

            if (!panelInfo.noActivate)
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
        tableItem := this.GetTable()
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
        tableItem := this.GetTable()
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
        ; 「球 → 面板」展开：用球的位置折算出的偏移当初始位置，视觉上就地放大，
        ; 不会先出现在默认锚点再跳过去。一次性，用完即删。
        if (this._pendingPanelPos.Has(foldIndex)) {
            pend := this._pendingPanelPos[foldIndex]
            this._pendingPanelPos.Delete(foldIndex)
            if (mode != 1 && IsObject(pend)) {
                offX := pend.offX
                offY := pend.offY
            }
        }
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
        ; 只有绝对坐标模式才用位置记忆当初始位置。跟随模式若用记忆，窗口会先出现在
        ; 上次的旧坐标（可能是屏幕外）再被跟随逻辑拉回锚点，看着就是「闪一下再跳」。
        if (mode == 1) {
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
    }

    ; 有拖动记忆时优先恢复；否则按模块位置设置放置。球走同一套：它的 offsetX/offsetY
    ; 就是「拖动后相对目标窗口的偏移」，由 _BallAdoptPos 维护。
    ApplyPanelPosition(panelInfo) {
        isBall := (panelInfo.HasProp("_isBall") && panelInfo._isBall)
        ; 球的坐标只由跟随定时器维护（目标矩形 + 偏移，逐帧算）。这里摆一次是用面板尺寸
        ; 算锚点的，会把球摆到错的位置，下一帧又被「偏差吸收」记成新偏移 —— 越摆越歪。
        if (isBall)
            return
        ; 先算出锚点位置：绝对坐标模式（posMode = 1）若有位置记忆就用记忆，
        ; 否则一律按锚点摆放。跟随类面板不读记忆——记忆是「上次待的位置」，
        ; 与「跟着目标窗口走」冲突，读了只会让面板停在旧坐标不动。
        ; 球不读面板那套记忆：它自己有偏移量，读面板记忆会把球拽到面板待过的地方。
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

        if (mode == 1 && !isBall && panelInfo.HasProp("foldIndex")) {
            saved := this._PosGet("UIPanelPos", panelInfo.foldIndex, panelInfo.targetHwnd)
            if (IsObject(saved) && panelInfo.wpfHwnd) {
                try DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0
                    , "Int", saved.x, "Int", saved.y, "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0004 | 0x0010)
                panelInfo.lastSetX := saved.x
                panelInfo.lastSetY := saved.y
                panelInfo._manualPos := true
                return
            }
        }

        DllCall("user32\SetWindowPos", "Ptr", panelInfo.wpfHwnd, "Ptr", 0
            , "Int", initX, "Int", initY, "Int", 0, "Int", 0, "UInt", 0x0001 | 0x0010)
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
