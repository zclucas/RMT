#Requires AutoHotkey v2.0
#Include IntervalGui.ahk
#Include KeyGui.ahk
#Include MouseMoveGui.ahk
#Include SearchGui.ahk
#Include SearchProGui.ahk
#Include ScreenShotGui.ahk
#Include RunGui.ahk
#Include CompareGui.ahk
#Include MMProGui.ahk
#Include OutputGui.ahk
#Include VariableGui.ahk
#Include SubMacroGui.ahk
#Include OperationGui.ahk
#Include BGMouseGui.ahk
#Include ExVariableGui.ahk
#Include RMTCMDGui.ahk
#Include BGKeyGui.ahk
#Include LoopGui.ahk
#Include CompareProGui.ahk
#Include CompareProEditItemGui.ahk
#Include TextOpsGui.ahk
#Include ArrayGui.ahk
#Include InputGui.ahk
#Include FileIOGui.ahk
#Include WindowManageGui.ahk
#include KeyCheckGui.ahk
#Include CommentGui.ahk
#Include MacroEditModel.ahk

class MacroEditGui {
    static Hotkeys := ["f5", "f6", "delete"]

    __new() {
        this.ParentTile := ""
        this.ui := ""                     ; XAMLHost 实例
        this._closed := true
        this._dragEnabled := false        ; 原生 OnMessage 拖拽保持禁用（WPF 手动拖拽独立实现）
        this._dragCandidate := ""         ; P6 手动拖拽候选 {fromLeft, gui, name, source, sx, sy}
        this._dragActive := false
        this._dragSource := ""
        this._dragTarget := ""
        this._dragSlot := ""
        this._lastDragTip := ""            ; 拖拽提示缓存，防 ToolTip 每帧重建闪烁
        this._treeClickCoord := ""
        this._rightClickCoord := ""
        this._hkIds := []
        this._topOn := false
        this._title := ""
        this._suppressModeChange := false      ; 构建/初始化时忽略编辑模式 SelectionChanged，避免空树先刷再重载闪烁
        this._revealed := false                ; 已 Opacity=1，防重复 reveal
        this.Gui := ""                         ; 打开时置为 facade（兼容外部 .Gui.Hwnd / .Title / .Hide），关闭时复位为空
        this.GuiMenu := ""
        this.DebugItemID := 0
        this.CurrentItemID := 0
        this.ShowSaveBtn := false
        this.SureFocusCon := ""
        this.isContextEdit := false
        this.RecordToggleCon := ""
        this.EditModeCon := ""
        this.SubMacroEditGui := ""
        this.SubMacroGraphGui := ""
        this.CompareProEditItemGui := ""
        this.OwnerHwnd := ""

        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SaveBtnCtrl := {}
        this.SubGuiMap := map()
        this.MacroTreeViewCon := ""
        this.MacroEditTextCon := ""
        this.CmdEditType := 1  ;1添加指令 2修改当前指令 3向上插入指令 4 向下插入指令
        this.CurItemID := ""  ;当前操作itemID
        this.LastItemID := "" ;最后的itemID
        this.ContextMenu := ""
        this.BranchContextMenu := ""
        this._lastGenCfg := Chr(0)      ; 右键菜单配置缓存（变化时废弃重建）
        this._lastBranchCfg := Chr(0)   ; 分支菜单配置缓存（变化时废弃重建）
        this.OpenedSubGuis := []        ; 多开时额外创建的子指令编辑器实例
        this.RecordMacroCon := ""
        this.DefaultFocusCon := ""
        this.SubMacroLastIndex := 0
        this.DragSourceMap := Map()
        this._dragCancelled := false
        ; 多選複製：使用 TreeView Check 狀態作為多選標記
        this.MultiSelectItems := Map()
        this.MultiSelectAnchor := 0
        this._lbtnHandler := ObjBindMethod(this, "_OnLButtonDown")
        this._notifyHandler := ObjBindMethod(this, "_OnNotify")

        this.InitCommandConfigs()
        this.InitSubGuiConfigs()
        this.InitSubGui()
    }

    InitCommandConfigs() {
        this.CMDStrArr := GetLangArr(["间隔", "按键", "搜索", "搜索Pro", "移动", "移动Pro", "输入", "输出", "循环", "宏操作", "变量", "变量提取",
            "如果", "如果Pro", "运算", "运行", "文件读写", "文本处理", "数组", "RMT指令", "后台鼠标", "后台按键", "窗口管理", "按键检测", "注释", "抓图"])

        this.CMDIconFileArr := ["Images\Soft\Interval.png", "Images\Soft\Key.png",
            "Images\Soft\Search.png", "Images\Soft\SearchPro.png",
            "Images\Soft\Move.png", "Images\Soft\MovePro.png",
            "Images\Soft\Input.png", "Images\Soft\Output.png",
            "Images\Soft\Loop.png", "Images\Soft\Sub.png",
            "Images\Soft\Var.png", "Images\Soft\Extract.png",
            "Images\Soft\If.png", "Images\Soft\IfPro.png",
            "Images\Soft\Operation.png", "Images\Soft\Run.png",
            "Images\Soft\FileIO.png", "Images\Soft\TextOps.png",
            "Images\Soft\Arr.png", "Images\Soft\rabit.png",
            "Images\Soft\Mouse.png", "Images\Soft\Key.png",
            "Images\Soft\WindowManage.png", "Images\Soft\KeyCheck.png",
            "Images\Soft\ScreenShot.png", "Images\Soft\Comment.png"]

        this.IconMap := Map(GetLang("间隔"), "Icon1", GetLang("按键"), "Icon2", GetLang("搜索"), "Icon3",
        GetLang("搜索Pro"), "Icon4", GetLang("移动"), "Icon5", GetLang("移动Pro"), "Icon6", GetLang("输出"), "Icon7",
        GetLang("运行"), "Icon8", GetLang("循环"), "Icon9", GetLang("宏操作"), "Icon10", GetLang("变量"), "Icon11",
        GetLang("变量提取"), "Icon12", GetLang("如果"), "Icon13", GetLang("如果Pro"), "Icon14", GetLang("运算"), "Icon15",
        GetLang("RMT指令"), "Icon16", GetLang("后台鼠标"), "Icon17", GetLang("后台按键"), "Icon18", GetLang("真"), "Icon19",
        GetLang("假"), "Icon20", GetLang("循环次数"), "Icon21", GetLang("条件"), "Icon22", GetLang("循环体"), "Icon23",
        GetLang("文本处理"), "Icon24", GetLang("数组"), "Icon25", GetLang("输入"), "Icon26", GetLang("文件读写"), "Icon27",
        GetLang("流程控制"), "Icon28", GetLang("窗口管理"), "Icon29", GetLang("按键检测"), "Icon30", GetLang("注释"), "Icon31",
        GetLang("抓图"), "Icon32")

        ; IconN → 图标文件（顺序与原 IL_Add 一致）
        this.IconFileByNumber := Map(
            "Icon1", "Images\Soft\Interval.png", "Icon2", "Images\Soft\Key.png",
            "Icon3", "Images\Soft\Search.png", "Icon4", "Images\Soft\SearchPro.png",
            "Icon5", "Images\Soft\Move.png", "Icon6", "Images\Soft\MovePro.png",
            "Icon7", "Images\Soft\Output.png", "Icon8", "Images\Soft\Run.png",
            "Icon9", "Images\Soft\Loop.png", "Icon10", "Images\Soft\Sub.png",
            "Icon11", "Images\Soft\Var.png", "Icon12", "Images\Soft\Extract.png",
            "Icon13", "Images\Soft\If.png", "Icon14", "Images\Soft\IfPro.png",
            "Icon15", "Images\Soft\Operation.png", "Icon16", "Images\Soft\rabit.png",
            "Icon17", "Images\Soft\Mouse.png", "Icon18", "Images\Soft\Key.png",
            "Icon19", "Images\Soft\True.png", "Icon20", "Images\Soft\False.png",
            "Icon21", "Images\Soft\LoopCount.png", "Icon22", "Images\Soft\Condition.png",
            "Icon23", "Images\Soft\LoopBody.png", "Icon24", "Images\Soft\TextOps.png",
            "Icon25", "Images\Soft\Arr.png", "Icon26", "Images\Soft\Input.png",
            "Icon27", "Images\Soft\FileIO.png", "Icon28", "Images\Soft\Control.png",
            "Icon29", "Images\Soft\WindowManage.png", "Icon30", "Images\Soft\KeyCheck.png",
            "Icon31", "Images\Soft\Comment.png", "Icon32", "Images\Soft\ScreenShot.png")

        ; 指令名 → 图标文件（XAML 树节点 Image.Source 用）
        this.CmdIconFileMap := Map()
        for name, iconN in this.IconMap
            this.CmdIconFileMap[name] := this.IconFileByNumber.Get(iconN, "")
    }

    InitSubGuiConfigs() {
        this.SubGuiConfig := [
            {class: IntervalGui, name: "间隔", icon: "Images\Soft\Interval.png", propName: "IntervalGui"},
            {class: KeyGui, name: "按键", icon: "Images\Soft\Key.png", propName: "KeyGui"},
            {class: SearchGui, name: "搜索", icon: "Images\Soft\Search.png", propName: "SearchGui"},
            {class: SearchProGui, name: "搜索Pro", icon: "Images\Soft\SearchPro.png", propName: "SearchProGui"},
            {class: MouseMoveGui, name: "移动", icon: "Images\Soft\Move.png", propName: "MouseMoveGui"},
            {class: MMProGui, name: "移动Pro", icon: "Images\Soft\MovePro.png", propName: "MMProGui"},
            {class: InputGui, name: "输入", icon: "Images\Soft\Input.png", propName: "InputGui"},
            {class: OutputGui, name: "输出", icon: "Images\Soft\Output.png", propName: "OutputGui"},
            {class: LoopGui, name: "循环", icon: "Images\Soft\Loop.png", propName: "LoopGui"},
            {class: SubMacroGui, name: "宏操作", icon: "Images\Soft\Sub.png", propName: "SubMacroGui"},
            {class: VariableGui, name: "变量", icon: "Images\Soft\Var.png", propName: "VariableGui"},
            {class: ExVariableGui, name: "变量提取", icon: "Images\Soft\Extract.png", propName: "ExVariableGui"},
            {class: CompareGui, name: "如果", icon: "Images\Soft\If.png", propName: "CompareGui"},
            {class: CompareProGui, name: "如果Pro", icon: "Images\Soft\IfPro.png", propName: "CompareProGui"},
            {class: OperationGui, name: "运算", icon: "Images\Soft\Operation.png", propName: "OperationGui"},
            {class: RunGui, name: "运行", icon: "Images\Soft\Run.png", propName: "RunGui"},
            {class: FileIOGui, name: "文件读写", icon: "Images\Soft\FileIO.png", propName: "FileIOGui"},
            {class: TextOpsGui, name: "文本处理", icon: "Images\Soft\TextOps.png", propName: "TextOpsGui"},
            {class: ArrayGui, name: "数组", icon: "Images\Soft\Arr.png", propName: "ArrayGui"},
            {class: RMTCMDGui, name: "RMT指令", icon: "Images\Soft\rabit.png", propName: "RMTCMDGui"},
            {class: BGMouseGui, name: "后台鼠标", icon: "Images\Soft\Mouse.png", propName: "BGMouseGui"},
            {class: BGKeyGui, name: "后台按键", icon: "Images\Soft\Key.png", propName: "BGKeyGui"},
            {class: WindowManageGui, name: "窗口管理", icon: "Images\Soft\WindowManage.png", propName: "WindowManageGui"},
            {class: KeyCheckGui, name: "按键检测", icon: "Images\Soft\KeyCheck.png", propName: "KeyCheckGui"},
            {class: CommentGui, name: "注释", icon: "Images\Soft\Comment.png", propName: "CommentGui"},
            {class: ScreenShotGui, name: "抓图", icon: "Images\Soft\ScreenShot.png", propName: "ScreenShotGui"}
        ]
    }

    InitSubGui() {
        for config in this.SubGuiConfig {
            guiClass := config.class
            guiInstance := guiClass()
            guiInstance.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
            this.SubGuiMap.Set(GetLang(config.name), guiInstance)
            this.%config.propName% := guiInstance
        }
    }

    ShowGui(CommandStr, ShowSaveBtn) {
        global MySoftData
        this._revealed := false
        ; XAML 窗口不支持隐藏复用：已打开的实例先关掉再重建
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        ; 主题/快捷键同款：内容在 _BuildAndShow 里 Show 前填充（入队），LoadedHwnd 时一次刷入
        this._BuildAndShow(CommandStr, ShowSaveBtn)

        ; 注册快捷键热键（仅编辑器前台时拦截，失焦时按键透传给其他程序；关闭时注销）
        this._hkIds := WinHotkey.Register(["F5", "F6", "Delete", "$^c", "$^v"], ObjBindMethod(this, "_OnHotkey"), this.Hwnd())

        ; 注册拖拽消息监听（先注销再注册，避免重复打开时叠多个处理器）
        OnMessage(0x0201, this._lbtnHandler, 0)
        OnMessage(0x0201, this._lbtnHandler)
        OnMessage(0x004E, this._notifyHandler)  ; WM_NOTIFY：TreeView 多選高亮

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        UIControls.RecordToggle := this.RecordMacroCon
        MainSoftData.MacroEditGui := this
        this.InitGuiMenu()
        ; 兜底：万一揭盖失败（LoadedHwnd 丢失等）强制显示
        SetTimer(ObjBindMethod(this, "_RevealFallback"), -800)
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        return s
    }

    ; 支持子菜单的 MenuItem 模板（全局主题模板缺子菜单支持，与 MacroGraph 共用方案）
    _MenuItemSubmenuStyle() {
        return ''
            . '<Style TargetType="MenuItem">'
            .   '<Setter Property="Background" Value="Transparent"/>'
            .   '<Setter Property="Foreground" Value="{DynamicResource TextMain}"/>'
            .   '<Setter Property="Padding" Value="10,8"/>'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="MenuItem">'
            .       '<Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="3">'
            .         '<Grid>'
            .           '<Grid.ColumnDefinitions>'
            .             '<ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>'
            .           '</Grid.ColumnDefinitions>'
            .           '<ContentPresenter ContentSource="Icon" Margin="0,0,8,0" VerticalAlignment="Center"/>'
            .           '<ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>'
            .           '<TextBlock Grid.Column="2" Text="{TemplateBinding InputGestureText}" Foreground="{DynamicResource TextSub}" Margin="15,0,0,0" VerticalAlignment="Center"/>'
            .           '<Path Grid.Column="3" x:Name="ArrowPath" Data="M0,0 L4,4 L0,8 Z" Fill="{DynamicResource TextMain}" Margin="8,0,2,0" VerticalAlignment="Center" Visibility="Collapsed"/>'
            .           '<Popup x:Name="PART_Popup" AllowsTransparency="True" Placement="Right" HorizontalOffset="-3" PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Focusable="False">'
            .             '<Border FlowDirection="LeftToRight" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3" Padding="4,4,0,4" MinWidth="180">'
            .               '<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" MaxHeight="400" Margin="0" Padding="0"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" Margin="0,0,4,0"/></ScrollViewer>'
            .             '</Border>'
            .           '</Popup>'
            .         '</Grid>'
            .       '</Border>'
            .       '<ControlTemplate.Triggers>'
            .         '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/><Setter Property="Foreground" Value="White"/></Trigger>'
            .         '<Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource TextSub}"/></Trigger>'
            .         '<Trigger Property="HasItems" Value="True"><Setter TargetName="ArrowPath" Property="Visibility" Value="Visible"/></Trigger>'
            .         '<MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="HasItems" Value="True"/></MultiTrigger.Conditions><Setter Property="IsSubmenuOpen" Value="True"/></MultiTrigger>'
            .       '</ControlTemplate.Triggers>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    ; 支持滚轮滑动的 ContextMenu 模板
    _ContextMenuScrollStyle() {
        return ''
            . '<Style TargetType="ContextMenu">'
            .   '<Setter Property="Template"><Setter.Value>'
            .     '<ControlTemplate TargetType="ContextMenu">'
            .       '<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="4">'
            .         '<ScrollViewer VerticalScrollBarVisibility="Auto" CanContentScroll="False">'
            .           '<ItemsPresenter/>'
            .         '</ScrollViewer>'
            .       '</Border>'
            .     '</ControlTemplate>'
            .   '</Setter.Value></Setter>'
            . '</Style>'
    }

    _BuildAndShow(CommandStr, ShowSaveBtn) {
        global MySoftData
        this._closed := false
        this.Gui := MacroEditGuiFacade(this)
        title := this.ParentTile GetLang("宏指令编辑器")
        this._title := title
        titleHeight := "30"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.GetDesignFontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(title).Foreground("{DynamicResource TitleBarForeground}").FontSize(12).FontWeight("SemiBold").VerticalAlignment("Center").Margin("12,0,0,0")
        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")
        closeBtn := BtnGroup.Add("Button").Name("BtnClosePanel").WindowChrome_IsHitTestVisibleInChrome("True").Width(40).Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        ; === 主体 ===
        body := main.Add("Grid").Grid_Row(1)
        body.Rows("30", "*")

        ; 菜单栏：按钮 + ContextMenu（桥接有成熟先例 MG_CM，Menu 控件本桥接未验证过）
        menuBar := body.Add("StackPanel").Grid_Row(0).Orientation("Horizontal").Margin("2,2,0,0").Background("{DynamicResource BgColor}")
        dbgBtn := menuBar.Add("Button").Name("BtnMenuDebug").Content(GetLang("调试")).Cursor("Hand").Background("Transparent").BorderThickness("0").Padding("10,3")
        dbgHost := menuBar.Add("Border").Name("MenuDebugHost").Width("0").Height("0").Visibility("Collapsed")
        dbgCM := dbgHost.Add("Border.ContextMenu").Add("ContextMenu").Name("MenuDebugCM").MinWidth("160").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        dbgCM.Add("MenuItem").Name("MenuRunF5").Header(GetLang("运行(F5)"))
        dbgCM.Add("MenuItem").Name("MenuRunF6").Header(GetLang("单步运行(F6)"))
        dbgCM.Add("MenuItem").Name("MenuKill").Header(GetLang("终止"))
        toolBtn := menuBar.Add("Button").Name("BtnMenuTool").Content(GetLang("工具")).Cursor("Hand").Background("Transparent").BorderThickness("0").Padding("10,3").Margin("8,0,0,0")
        toolHost := menuBar.Add("Border").Name("MenuToolHost").Width("0").Height("0").Visibility("Collapsed")
        toolCM := toolHost.Add("Border.ContextMenu").Add("ContextMenu").Name("MenuToolCM").MinWidth("160").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        toolCM.Add("MenuItem").Name("MenuVarListen").Header(GetLang("变量监视")).IsCheckable("True")
        toolCM.Add("MenuItem").Name("MenuCmdTip").Header(GetLang("指令显示")).IsCheckable("True")
        toolCM.Add("MenuItem").Name("MenuTopMost").Header(GetLang("窗口置顶")).IsCheckable("True")

        ; 树右键菜单（普通指令 / 分支容器），挂在 0 尺寸隐藏 Border 上，Placement=MousePoint
        treeCtxHost := menuBar.Add("Border").Name("TreeCtxHost").Width("0").Height("0").Visibility("Collapsed")
        treeCtx := treeCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("TreeCtxMenu").MinWidth("180").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        treeCtx.Add("MenuItem").Name("MenuEditCmd").Header(GetLang("编辑"))
        treeCtx.Add("MenuItem").Name("MenuSkipCmd").Header(GetLang("跳过指令"))
        treeCtx.Add("MenuItem").Name("MenuDebugCmd").Header(GetLang("调试起点"))
        treeCtx.Add("Separator")
        miInsert := treeCtx.Add("MenuItem").Name("MenuInsertCmd").Header(GetLang("插入指令"))
        for index, value in this.CMDStrArr
            miInsert.Add("MenuItem").Name("MenuInsert_" index).Header(value)
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("MenuCopyCmd").Header(GetLang("复制"))
        treeCtx.Add("MenuItem").Name("MenuPasteCmd").Header(GetLang("粘贴"))
        treeCtx.Add("Separator")
        treeCtx.Add("MenuItem").Name("MenuDeleteCmd").Header(GetLang("删除"))

        branchCtxHost := menuBar.Add("Border").Name("BranchCtxHost").Width("0").Height("0").Visibility("Collapsed")
        branchCtx := branchCtxHost.Add("Border.ContextMenu").Add("ContextMenu").Name("BranchCtxMenu").MinWidth("180").Placement("MousePoint").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}").BorderThickness("1").Foreground("{DynamicResource TextMain}").InjectResources(this._ContextMenuScrollStyle()).InjectResources(this._MenuItemSubmenuStyle())
        miAdd := branchCtx.Add("MenuItem").Name("MenuBranchAddCmd").Header(GetLang("添加指令"))
        for index, value in this.CMDStrArr
            miAdd.Add("MenuItem").Name("MenuBranchAdd_" index).Header(value)
        branchCtx.Add("Separator")
        branchCtx.Add("MenuItem").Name("MenuBranchDelete").Header(GetLang("删除"))

        content := body.Add("Grid").Grid_Row(1)
        content.Cols("210", "*")
        content.Rows("42", "30", "*", "48")

        ; 左侧指令面板
        left := content.Add("GroupBox").Grid_Column(0).Grid_RowSpan(4).Header(GetLang("指令选项")).Margin("5,4,2,4")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Foreground("{DynamicResource TextMain}")
        leftGrid := left.Add("UniformGrid").Columns(2)
        for config in this.SubGuiConfig {
            btnName := "CmdBtn_" config.propName
            b := leftGrid.Add("Button").Name(btnName).Height(32).Margin("2").Background("Transparent").BorderThickness("0")
                .Cursor("Hand").HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
            sp := b.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
            sp.Add("Image").Source(StrReplace(A_WorkingDir "\" config.icon, "\", "/")).Width(16).Height(16).Margin("0,0,4,0")
            sp.Add("TextBlock").Text(GetLang(config.name)).FontSize(11)
        }

        ; 顶部工具条
        toolRow := content.Add("Grid").Grid_Column(1).Grid_Row(0).Margin("10,8,10,0")
        toolRow.Cols("*", "Auto")
        leftStack := toolRow.Add("StackPanel").Grid_Column(0).Orientation("Horizontal")
        leftStack.Add("TextBlock").Text(GetLang("编辑模式：")).VerticalAlignment("Center")
        combo := leftStack.Add("ComboBox").Name("EditModeCombo").Width(86).Height(26).MinHeight(26).SelectedIndex("0").Margin("4,0")
        combo.Add("ComboBoxItem").Content(GetLang("逻辑树")).Tag("1")
        combo.Add("ComboBoxItem").Content(GetLang("文本")).Tag("2")
        leftStack.Add("CheckBox").Name("RecordTog").Content(GetLang("指令录制")).VerticalAlignment("Center").Margin("12,0,0,0")
        leftStack.Add("TextBlock").Name("RecordHotkeyText").Text(FormatHotkeyDisplay(MainSoftData.ToolRecordMacroHotKey)).Opacity("0.6").VerticalAlignment("Center").Margin("6,0,0,0")
        toolRow.Add("Button").Grid_Column(1).Name("BtnGraphNode").Content(GetLang("图形节点")).Height(28).MinHeight(28).Padding("10,3").Margin("6,0,0,0")

        ; 当前宏指令行
        row1 := content.Add("StackPanel").Grid_Column(1).Grid_Row(1).Orientation("Horizontal").Margin("10,4,10,0")
        row1.Add("TextBlock").Text(GetLang("当前宏指令")).VerticalAlignment("Center")
        row1.Add("Button").Name("BtnExpand").Content(GetLang("全部展开")).Padding("8,3").Margin("10,0,0,0")
        row1.Add("Button").Name("BtnCollapse").Content(GetLang("全部折叠")).Padding("8,3").Margin("6,0,0,0")

        ; 树 / 文本视图
        view := content.Add("Grid").Grid_Column(1).Grid_Row(2).Margin("10,0,10,0")
        ; 关虚拟化（注入真实 ListBoxItem，虚拟化会导致插入后滚动条复位）+ 去 ListBoxItem 默认内边距/选中高亮
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" SnapsToDevicePixels="True"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>'
        view.Add("ListBox").Name("MacroTree").Background("{DynamicResource BgColor}").Foreground("{DynamicResource TextMain}")
            .BorderThickness("0")
            .VirtualizingPanel_IsVirtualizing("False")
            .ScrollViewer_HorizontalScrollBarVisibility("Auto").ScrollViewer_VerticalScrollBarVisibility("Auto")
            .InjectResources(lbStyle)
        ; 拖拽插入指示线（覆盖在树上，拖拽时定位，不重建树）
        view.Add("Border").Name("DragInsertLine").Height(2).HorizontalAlignment("Stretch").VerticalAlignment("Top")
            .Background("{DynamicResource Accent}").BorderThickness(0)
            .SetProp("Panel.ZIndex", "10").Visibility("Collapsed").IsHitTestVisible("False")
        view.Add("TextBox").Name("MacroText").AcceptsReturn("True").FontSize("12").Visibility("Collapsed")
            .VerticalContentAlignment("Top")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
            .ScrollViewer_HorizontalScrollBarVisibility("Auto").ScrollViewer_VerticalScrollBarVisibility("Auto")

        ; 底部按钮
        bottom := content.Add("StackPanel").Grid_Column(1).Grid_Row(3).Orientation("Horizontal").Margin("10,6,10,0").HorizontalAlignment("Center")
        bottom.Add("Button").Name("BtnBack").Content(GetLang("退格")).Width(100).Height(32).MinHeight(32).Margin("4,0")
        bottom.Add("Button").Name("BtnClear").Content(GetLang("清空指令")).Width(100).Height(32).MinHeight(32).Margin("4,0")
        bottom.Add("Button").Name("BtnOk").Content(GetLang("确定")).Width(100).Height(32).MinHeight(32).Margin("4,0")
        bottom.Add("Button").Name("SaveBtn").Content(GetLang("应用并保存")).Width(100).Height(32).MinHeight(32).Margin("4,0")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="945" Height="570" Opacity="0"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        groupBoxStyle := '<Style TargetType="GroupBox"><Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/></Style>'
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', groupBoxStyle)

        ; === 控件适配器 ===
        this.MacroTreeViewCon := MacroTreeAdapter(this.ui, "MacroTree")
        this.MacroTreeViewCon.SetIconMap(this.IconFileByNumber)
        this.MacroEditTextCon := MacroTextBox(this.ui, "MacroText")
        this.EditModeCon := MacroCombo(this.ui, "EditModeCombo")
        this.RecordMacroCon := MacroCheckBox(this.ui, "RecordTog")
        this.SaveBtnCtrl := MacroButton(this.ui, "SaveBtn")
        this.ToolMenu := MacroMenuAdapter(this.ui)

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        this.ui.OnEvent("EditModeCombo", "SelectionChanged", ObjBindMethod(this, "OnChangeEditMode"))
        this.ui.OnEvent("RecordTog", "Click", ObjBindMethod(this, "OnClickRecordTog"))
        this.ui.OnEvent("BtnBack", "Click", (*) => this.Backspace())
        this.ui.OnEvent("BtnClear", "Click", (*) => this.ClearStr())
        this.ui.OnEvent("BtnOk", "Click", (*) => this.OnSureBtnClick())
        this.ui.OnEvent("SaveBtn", "Click", (*) => this.OnSaveBtnClick())
        this.ui.OnEvent("BtnExpand", "Click", (*) => this.ExpandAll())
        this.ui.OnEvent("BtnCollapse", "Click", (*) => this.CollapseAll())
        this.ui.OnEvent("BtnGraphNode", "Click", ObjBindMethod(this, "OnSwitchToGraphEditor"))
        this.ui.OnEvent("BtnMenuDebug", "Click", (*) => this.ui.Update("MenuDebugCM", "IsOpen", "True"))
        this.ui.OnEvent("BtnMenuTool", "Click", (*) => this.ui.Update("MenuToolCM", "IsOpen", "True"))
        this.ui.OnEvent("MenuRunF5", "Click", (*) => this.MenuHandler(GetLang("运行(F5)")))
        this.ui.OnEvent("MenuRunF6", "Click", (*) => this.MenuHandler(GetLang("单步运行(F6)")))
        this.ui.OnEvent("MenuKill", "Click", (*) => this.MenuHandler(GetLang("终止")))
        this.ui.OnEvent("MenuVarListen", "Click", (*) => this.MenuHandler(GetLang("变量监视")))
        this.ui.OnEvent("MenuCmdTip", "Click", (*) => this.MenuHandler(GetLang("指令显示")))
        this.ui.OnEvent("MenuTopMost", "Click", (*) => this.MenuHandler(GetLang("窗口置顶")))

        ; 树右键菜单项
        this.ui.OnEvent("MenuEditCmd", "Click", (*) => this.ContentMenuHandler(GetLang("编辑")))
        this.ui.OnEvent("MenuSkipCmd", "Click", (*) => this.ContentMenuHandler("Skip"))
        this.ui.OnEvent("MenuDebugCmd", "Click", (*) => this.ContentMenuHandler("Debug"))
        this.ui.OnEvent("MenuCopyCmd", "Click", (*) => this.ContentMenuHandler(GetLang("复制")))
        this.ui.OnEvent("MenuPasteCmd", "Click", (*) => this.ContentMenuHandler(GetLang("粘贴")))
        this.ui.OnEvent("MenuDeleteCmd", "Click", (*) => this.ContentMenuHandler(GetLang("删除")))
        this.ui.OnEvent("MenuBranchDelete", "Click", (*) => this.ContentMenuHandler(GetLang("删除")))
        for index, value in this.CMDStrArr {
            this.ui.OnEvent("MenuInsert_" index, "Click", this.ContentMenuHandler.Bind(this, "Next_" value))
            this.ui.OnEvent("MenuBranchAdd_" index, "Click", this.ContentMenuHandler.Bind(this, "Add_" value))
        }

        ; 树左/右击（多选 + 右键菜单 + 拖拽 + 双击编辑；双击在 PreviewMouseLeftButtonDown 里按 ClickCount 判定）
        this.ui.OnEvent("MacroTree", "PreviewMouseLeftButtonDown", ObjBindMethod(this, "_OnTreePreviewLeftDown"))
        this.ui.OnEvent("MacroTree", "PreviewMouseRightButtonDown", ObjBindMethod(this, "_OnTreePreviewRightDown"))
        ; 拖拽移动/松开绑在窗口级：WPF 按钮按下会捕获鼠标，TreeView 收不到移动事件
        this.ui.OnEvent("Window", "PreviewMouseMove", ObjBindMethod(this, "_OnTreeDragMove"))
        this.ui.OnEvent("Window", "PreviewMouseLeftButtonUp", ObjBindMethod(this, "_OnTreeDragDrop"))

        for config in this.SubGuiConfig {
            guiInstance := this.%config.propName%
            btnName := "CmdBtn_" config.propName
            this.ui.OnEvent(btnName, "Click", CreateSubGuiClickHandler(this, guiInstance))
            this.ui.OnEvent(btnName, "PreviewMouseLeftButtonDown", this._OnPanelDragStart.Bind(this, guiInstance, GetLang(config.name)))
        }

        this.ui.Track("EditModeCombo")
        this.ui.Track("MacroText")
        this.ui.Track("MacroTree")

        ; WPF ComboBox 默认 SelectedIndex=-1（不自动选第一项），强制选中「逻辑树」
        ; 构建期抑制 SelectionChanged：否则会先 InitTreeView(空) 再被灌树刷第二次 → 闪一下
        this._suppressModeChange := true
        ; ===== 主题/快捷键同款：先填充内容（Show 前入队，LoadedHwnd 时一次刷入）=====
        try {
            this.Init(CommandStr, ShowSaveBtn)
        } catch {
        }
        this.ui.Update("EditModeCombo", "SelectedIndex", "0")
        try this.EditModeCon._value := 1

        this.ui.Show()

        gotHwnd := false
        loop 40 {
            if (this.ui.HasProp("wpfHwnd") && this.ui.wpfHwnd) {
                gotHwnd := true
                if (this.OwnerHwnd != "")
                    try this.ui.Update("Window", "NativeOwner", String(this.OwnerHwnd))
                ; 内容已入队并在 LoadedHwnd 刷入，立即揭盖（主题界面同款）
                try this.ui.Update("Window", "Opacity", "1")
                try WinActivate("ahk_id " this.ui.wpfHwnd)
                break
            }
            Sleep(50)
        }
        ; 等待循环已消费 LoadedHwnd 刷入触发的 SelectionChanged，此时解除抑制
        this._suppressModeChange := false
        if (!gotHwnd)
            this._closed := true
    }

    OnWindowLoad(state, ctrl, event) {
        try {
            try {
                hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1", &ImageType := 1)
                if (hIcon)
                    this.ui.Update("Window", "Icon", "HICON:" hIcon)
            }
            themeName := MainSoftData.HasProp("Theme") ? MainSoftData.Theme : "RMT_Light"
            ApplyXamlTheme(this.ui, themeName)
        } catch {
        }
        this._TryReveal("theme")
    }

    ; 揭盖一次（防重复）：引擎还原位置并显示，窗口从离屏直接变完整内容，无 Hide/Show
    _TryReveal(from := "") {
        if (this._revealed || this._closed)
            return
        if (!IsObject(this.ui) || !this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd)
            return
        this._revealed := true
        try this.ui.Update("Window", "Opacity", "1")
        try WinActivate("ahk_id " this.ui.wpfHwnd)
    }

    _RevealFallback(*) {
        this._TryReveal("fallback")
    }

    _FadeIn() {
        this._TryReveal("fadeIn")
    }

    OnWindowClosing(state, ctrl, event) {
        this._revealed := true   ; 关闭中不再 fallback reveal
        if (this._hkIds.Length > 0) {
            WinHotkey.UnregisterAll(this._hkIds)
            this._hkIds := []
        }
        OnMessage(0x0201, this._lbtnHandler, 0)
        OnMessage(0x004E, this._notifyHandler, 0)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this._dragActive := false
        this._dragCandidate := ""
        this._dragSource := ""
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
        ToolTip()
        this.ui := ""
        this.Gui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        this._revealed := true
        this._closed := true
        if (this._hkIds.Length > 0) {
            WinHotkey.UnregisterAll(this._hkIds)
            this._hkIds := []
        }
        OnMessage(0x0201, this._lbtnHandler, 0)
        OnMessage(0x004E, this._notifyHandler, 0)
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this._dragActive := false
        this._dragCandidate := ""
        this._dragSource := ""
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
        ToolTip()
        this.ui := ""
        this.Gui := ""
    }

    _HideWindow() {
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
    }

    InitGuiMenu() {
        ; 菜单已在 _BuildAndShow 中以 XAML 构建；这里只按窗口可见状态同步初始勾选
        if (this.ToolMenu == "")
            return
        try {
            if (MyVarListenGui.Gui != "" && MyVarListenGui.Gui.Hwnd) {
                style := WinGetStyle("ahk_id " MyVarListenGui.Gui.Hwnd)
                if (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    this.ToolMenu.Check(GetLang("变量监视"))
            }
        }
        try {
            if (MyCMDTipGui.Gui != "" && MyCMDTipGui.Gui.Hwnd) {
                style := WinGetStyle("ahk_id " MyCMDTipGui.Gui.Hwnd)
                if (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    this.ToolMenu.Check(GetLang("指令显示"))
            }
        }
        try {
            if (this.Hwnd()) {
                exStyle := DllCall("GetWindowLongPtr", "Ptr", this.Hwnd(), "Int", -20, "UInt") ; GWL_EXSTYLE = -20
                if (exStyle & 0x00000008) {
                    this._topOn := true
                    this.ToolMenu.Check(GetLang("窗口置顶"))
                }
            }
        }
    }

    Init(MacroStr, ShowSaveBtn) {
        MacroStr := GetLangMacro(MacroStr, 1)
        this.ShowSaveBtn := ShowSaveBtn
        this.SubMacroLastIndex := 0
        this.SaveBtnCtrl.Visible := this.ShowSaveBtn
        this.InitTreeView(MacroStr)
        this.InitMacroText(MacroStr)

        this.ClearMultiSelection()
        firstItem := this.MacroTreeViewCon.GetNext(0)
        this.MacroTreeViewCon.Focus()
        if (firstItem)
            this.SetMultiSelected(firstItem, true)
    }

    Backspace() {
        if (this.EditModeCon.Value == 1) {
            if (this.MacroTreeViewCon.GetCount() == 0)
                return
            preItemID := this.MacroTreeViewCon.GetPrev(this.LastItemID)
            this.MacroTreeViewCon.Delete(this.LastItemID)
            this.LastItemID := preItemID
        }
        else {
            MacroStr := this.GetMacroStr()
            cmdArr := SplitMacro(MacroStr)
            if (cmdArr.Length > 0)
                cmdArr.Pop()
            MacroStr := GetMacroStrByCmdArr(cmdArr)

            ; 保留滚动位置（#3）：改前抓首行，改后滚回
            firstVisible := IsObject(this.ui) ? this.ui.Query("MacroText>FirstVisibleLine") : ""
            this.InitMacroText(MacroStr)
            if (firstVisible != "" && IsObject(this.ui))
                this.ui.Update("MacroText", "ScrollToLine", firstVisible)
            else
                this.MacroEditTextCon.ScrollToEnd()
        }
    }

    ClearStr() {
        this.MacroTreeViewCon.Delete()
        this.MacroEditTextCon.Value := ""
    }

    OnChangeEditMode(state, ctrl, event) {
        ; 打开构建期：SelectedIndex 初值会触发本事件，此时树尚未 Init，跳过避免空刷新闪烁
        if (this._suppressModeChange)
            return
        ; ComboBoxItem 的 Tag 即模式值（"1"=逻辑树 "2"=文本）
        if (IsObject(state) && state.Has("EditModeCombo") && state["EditModeCombo"] != "")
            this.EditModeCon._value := Integer(state["EditModeCombo"])
        else
            this.EditModeCon._value := 1
        MacroStr := this.GetMacroStr()
        this.MacroTreeViewCon.Visible := this.EditModeCon.Value == 1
        this.MacroEditTextCon.Visible := this.EditModeCon.Value == 2

        if (this.EditModeCon.Value == 1) {
            this.InitTreeView(MacroStr)
        }
        else if (this.EditModeCon.Value == 2) {
            this.InitMacroText(MacroStr)
        }
    }

    OnClickRecordTog(*) {
        UIControls.RecordToggle := this.RecordMacroCon
        MainSoftData.MacroEditGui := this
        OnHotToolRecordMacro(true)
    }

    ; 切换到图形节点编辑器（先回写当前宏内容）
    OnSwitchToGraphEditor(*) {
        macroStr := this.GetMacroStr()
        macroStr := GetLangMacro(macroStr, 2)
        sureAction := this.SureBtnAction
        if (sureAction != "")
            sureAction(macroStr)
        this.SureBtnAction := ""
        this.OnGuiClose()

        MyMacroGraphGui.OwnerHwnd := ""
        MyMacroGraphGui.SureBtnAction := sureAction
        MyMacroGraphGui.ShowGui(macroStr)
    }

    OnSaveBtnClick() {
        macroStr := this.GetMacroStr()
        macroStr := GetLangMacro(macroStr, 2)
        action := this.SureBtnAction
        action(macroStr)

        this.SureBtnAction := ""

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }

        this._HideWindow()

        action := this.SaveBtnAction
        action()
        this.SureFocusCon.Focus()
    }

    OnSureBtnClick() {
        macroStr := this.GetMacroStr()
        macroStr := GetLangMacro(macroStr, 2)
        action := this.SureBtnAction
        action(macroStr)

        this.SureBtnAction := ""

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }

        this._HideWindow()
        this.SureFocusCon.Focus()
    }

    OnGuiClose() {
        this._CloseWindow()
    }

    GetMacroStr() {
        MacroStr := ""
        if (this.MacroTreeViewCon.Visible) {
            MacroStr := this.GetTreeMacroStr(0)
        }
        else if (this.MacroEditTextCon.Visible) {
            MacroStr := this.MacroEditTextCon.Value
        }
        return MacroStr
    }

    InitMacroText(MacroStr) {
        this.MacroEditTextCon.Visible := this.EditModeCon.Value == 2

        content := RegExReplace(MacroStr, "[,，⫶]", "`n")
        this.MacroEditTextCon.Value := content
    }

    ShowContextMenu(ctrl, item, isRightClick, x, y) {
        if (item == 0)
            return

        ; 检查配置是否变化，若变化则废弃缓存重建
        genCfg := MainSoftData.HasProp("GeneralContextMenu") ? MainSoftData.GeneralContextMenu : ""
        if (this._lastGenCfg != genCfg)
            this.ContextMenu := ""

        if (this.ContextMenu == "") {
            this._lastGenCfg := genCfg
            this.ContextMenu := Menu()
            this.ContextMenu.IsSkip := true
            this.ContextMenu.IsDebug := true

            ; 构建插入指令子菜单（固定）
            insertSubMenu := Menu()
            for index, value in this.CMDStrArr {
                insertSubMenu.Add(value, this.ContentMenuHandler.Bind(this, "Next_" value))
                insertSubMenu.SetIcon(value, this.CMDIconFileArr[index])
            }

            ; 从配置加载顺序，若无则使用默认顺序
            genKeys := (genCfg != "") ? StrSplit(genCfg, ",") : ["Edit", "Skip", "Debug", "Separator", "Insert", "Separator", "Copy", "SharedCopy", "Paste", "Separator", "Delete"]

            for k in genKeys {
                switch k {
                    case "Separator":
                        this.ContextMenu.Add()
                    case "Edit":
                        this.ContextMenu.Add(GetLang("编辑"), (*) => this.ContentMenuHandler(GetLang("编辑")))
                    case "Skip":
                        this.ContextMenu.Add(GetLang("跳过指令"), (*) => this.ContentMenuHandler("Skip"))
                    case "Debug":
                        this.ContextMenu.Add(GetLang("调试起点"), (*) => this.ContentMenuHandler("Debug"))
                    case "Insert":
                        this.ContextMenu.Add(GetLang("插入指令"), insertSubMenu)
                    case "Copy":
                        this.ContextMenu.Add(GetLang("复制"), (*) => this.ContentMenuHandler(GetLang("复制")))
                    case "SharedCopy":
                        this.ContextMenu.Add(GetLang("共享复制"), (*) => this.ContentMenuHandler("SharedCopy"))
                    case "Paste":
                        this.ContextMenu.Add(GetLang("粘贴"), (*) => this.ContentMenuHandler(GetLang("粘贴")))
                    case "Delete":
                        this.ContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
                }
            }
        }

        ; 检查分支菜单配置是否变化
        branchCfg := MainSoftData.HasProp("BranchContextMenu") ? MainSoftData.BranchContextMenu : ""
        if (this._lastBranchCfg != branchCfg)
            this.BranchContextMenu := ""

        if (this.BranchContextMenu == "") {
            this._lastBranchCfg := branchCfg
            this.BranchContextMenu := Menu()

            ; 构建添加指令子菜单（固定）
            addSubMenu := Menu()
            for index, value in this.CMDStrArr {
                addSubMenu.Add(value, this.ContentMenuHandler.Bind(this, "Add_" value))
                addSubMenu.SetIcon(value, this.CMDIconFileArr[index])
            }

            ; 从配置加载顺序
            branchKeys := (branchCfg != "") ? StrSplit(branchCfg, ",") : ["Add", "Separator", "BranchCopy", "BranchSharedCopy", "Paste", "Separator", "Delete"]

            for k in branchKeys {
                switch k {
                    case "Separator":
                        this.BranchContextMenu.Add()
                    case "Add":
                        this.BranchContextMenu.Add(GetLang("添加指令"), addSubMenu)
                    case "BranchCopy":
                        this.BranchContextMenu.Add(GetLang("复制"), (*) => this.ContentMenuHandler("BranchCopy"))
                    case "BranchSharedCopy":
                        this.BranchContextMenu.Add(GetLang("共享复制"), (*) => this.ContentMenuHandler("BranchSharedCopy"))
                    case "Paste":
                        this.BranchContextMenu.Add(GetLang("粘贴"), (*) => this.ContentMenuHandler(GetLang("粘贴")))
                    case "Delete":
                        this.BranchContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
                }
            }
        }

        ; 右鍵只設定「右鍵操作目標」，絕對不改變目前多選狀態。
        ; MultiSelectItems / TreeView Select 狀態都保持原樣。
        this.CurItemID := item
        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        cleanItemText := StrReplace(itemText, "→", "")
        isCondi := SubStr(cleanItemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        ; 清理→前缀用于菜单状态判断（→是运行时临时标记，不影响逻辑状态）
        if (cleanItemText == "" || SubStr(cleanItemText, 1, 1) == "⎖")
            return
        else if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体") || isCondi) {
            this.BranchContextMenu.Show(x, y)
        }
        else {
            CurSkipMenuText := this.ContextMenu.IsSkip ? GetLang("跳过指令") : GetLang("取消跳过")
            SkipMenuText := SubStr(cleanItemText, 1, 2) == "🚫" ? GetLang("取消跳过") : GetLang("跳过指令")
            if (CurSkipMenuText != SkipMenuText) {
                this.ContextMenu.Rename(CurSkipMenuText, SkipMenuText)
                this.ContextMenu.IsSkip := !this.ContextMenu.IsSkip
            }

            CurDebugMenuText := this.ContextMenu.IsDebug ? GetLang("调试起点") : GetLang("取消调试起点")
            DebugMenuText := SubStr(cleanItemText, 1, 1) == "⭐" ? GetLang("取消调试起点") : GetLang("调试起点")
            if (CurDebugMenuText != DebugMenuText) {
                this.ContextMenu.Rename(CurDebugMenuText, DebugMenuText)
                this.ContextMenu.IsDebug := !this.ContextMenu.IsDebug
            }

            this.ContextMenu.Show(x, y)
        }
    }

    _OnHotkey(key) {
        ; 去掉 ~ / $ 前缀后再比较（$ 用于防止 Send 再次触发自身热键）
        key := LTrim(key, "~$")
        if (key == "F5")
            this.MenuHandler(GetLang("运行(F5)"))
        else if (key == "F6")
            this.MenuHandler(GetLang("单步运行(F6)"))
        else if (key == "Delete") {
            this.OnDeleteCmd()
        }
        else if (key == "^c") {
            ; 逻辑树模式：复制选中指令；文本模式：交还编辑框原生复制
            ; 非透传（无 ~）会吞掉按键，避免树控件收到 Ctrl+C 后响铃
            if (!this.MacroTreeViewCon.Visible)
                Send("^c")
            else if (this.CurItemID)
                this.ContentMenuHandler(GetLang("复制"))
        }
        else if (key == "^v") {
            if (!this.MacroTreeViewCon.Visible)
                Send("^v")
            else
                ; 空树/无选中时也允许粘贴到根层
                this.ContentMenuHandler(GetLang("粘贴"))
        }
    }

    OnSoftKey(key, isDown) {
        if (!isDown)
            return

        if (key == "f5")
            this.MenuHandler(GetLang("运行(F5)"))
        if (key == "f6")
            this.MenuHandler(GetLang("单步运行(F6)"))
        if (key == "delete") {
            try {
                focusedHwnd := DllCall("GetFocus", "Ptr")
                if (focusedHwnd = this.MacroTreeViewCon.hwnd)
                    this.OnDeleteCmd()
            }
        }
    }

    ; 从事件 state 读 DragCoords（相对绑定控件的 DIP 坐标），返回 "x;y"；读不到返回 ""
    _EventCoord(state, ctrlName) {
        coord := ""
        if (IsObject(state) && state.Has("DragCoords"))
            coord := state["DragCoords"]
        else if (IsObject(state) && state.Has(ctrlName))
            coord := state[ctrlName]
        if (coord == "")
            return ""
        parts := StrSplit(coord, ",")
        if (parts.Length != 2)
            return ""
        return Trim(parts[1]) ";" Trim(parts[2])
    }

    ; 命中测试（坐标相对 ctrlName），返回 "tag|top/bottom" 或 ""
    _HitTest(ctrlName, coord) {
        if (!IsObject(this.ui) || coord == "")
            return ""
        return this.ui.Query(ctrlName ">HitTest:" coord)
    }

    ; WPF 树双击：命中测试定位节点打开编辑器；WPF 默认双击展开/折叠，定向还原到双击前状态（不整树重渲染）
    _OnTreeDoubleClick(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        coord := this._EventCoord(state, "MacroTree")
        if (coord == "")
            return
        tagSlot := this._HitTest("MacroTree", coord)
        if (tagSlot == "")
            return
        parts := StrSplit(tagSlot, "|")
        itemID := parts[1]
        ; 点在展开箭头上：只折叠，不打开编辑器；叶子无子节点则正常打开编辑器
        if (parts.Length > 2 && parts[3] == "1" && this.MacroTreeViewCon.GetChild(itemID) != 0)
            return
        this.OnDoubleClick(this.MacroTreeViewCon, itemID)
    }

    ; WPF 树左键按下：记录拖拽候选，延迟到选中完成后再处理多选（Ctrl/Shift/普通）
    _OnTreePreviewLeftDown(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        ; 双击：打开编辑器（C# 已对树条目双击置 Handled，阻止展开/折叠切换）
        clickCount := 1
        if (IsObject(state) && state.Has("ClickCount")) {
            cc := state["ClickCount"]
            if (IsNumber(cc))
                clickCount := Integer(cc)
        }
        if (clickCount >= 2) {
            this._OnTreeDoubleClick(state, ctrl, event)
            return
        }
        ; 新按下：清掉上次可能残留的拖拽激活态
        this._dragActive := false
        this._dragTarget := ""
        this._dragSlot := ""
        coord := this._EventCoord(state, "MacroTree")
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        source := ""
        if (coord != "") {
            tagSlot := this._HitTest("MacroTree", coord)
            if (tagSlot != "") {
                parts := StrSplit(tagSlot, "|")
                source := parts[1]
            }
        }
        this._dragCandidate := {fromLeft: false, gui: "", name: "", source: source, sx: sx, sy: sy}
        this._treeClickCoord := coord
        SetTimer(ObjBindMethod(this, "_ProcessTreeLeftClick"), -20)
    }

    ; 左面板按钮按下：拖拽候选（fromLeft）
    _OnPanelDragStart(guiInstance, displayName, state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        this._dragActive := false
        this._dragTarget := ""
        this._dragSlot := ""
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        this._dragCandidate := {fromLeft: true, gui: guiInstance, name: displayName, source: "", sx: sx, sy: sy}
    }

    ; 窗口级鼠标移动：检测拖拽启动；命中树得插入线位置（不重建树）
    _OnTreeDragMove(state, ctrl, event) {
        if (!IsObject(this._dragCandidate))
            return
        if (!GetKeyState("LButton", "P")) {
            this._DragEndReset()
            return
        }
        if (!this._dragActive) {
            cand := this._dragCandidate
            CoordMode("Mouse", "Screen")
            MouseGetPos(&cx, &cy)
            if (Abs(cx - cand.sx) > 8 || Abs(cy - cand.sy) > 8) {
                this._dragActive := true
                this.MacroTreeViewCon._suppressRender := true   ; 拖拽期间禁全量重建
            }
        }
        if (this._dragActive) {
            coord := this._EventCoord(state, "Window")
            this._dragTarget := ""
            this._dragSlot := ""
            lineY := -1
            if (coord != "") {
                treeCoord := this._TreeCoord(coord)
                if (treeCoord != "") {
                    tagSlot := this._HitTest("MacroTree", treeCoord)
                    if (tagSlot != "") {
                        parts := StrSplit(tagSlot, "|")
                        this._dragTarget := parts[1]
                        this._dragSlot := parts.Length > 1 ? parts[2] : ""
                        if (this._dragTarget != "" && parts.Length >= 4) {
                            originY := IsNumber(parts[4]) ? parts[4] : 0
                            h := IsNumber(parts[5]) ? parts[5] : 0
                            lineY := (this._dragSlot == "top") ? originY : originY + h
                        }
                    }
                }
            }
            if (lineY >= 0) {
                try this.ui.Update("DragInsertLine", "Margin", "1," Integer(lineY) ",1,0")
                try this.ui.Update("DragInsertLine", "Visibility", "Visible")
            } else
                try this.ui.Update("DragInsertLine", "Visibility", "Collapsed")
            name := this._dragCandidate.fromLeft ? this._dragCandidate.name : this.MacroTreeViewCon.GetText(this._dragCandidate.source)
            tip := GetLang("拖动插入: ") name
            if (this._dragTarget != "") {
                ttext := this.MacroTreeViewCon.GetText(this._dragTarget)
                if (this.IsContainerNode(ttext))
                    tip .= "`n" GetLang("目标: 插入到 ") ttext GetLang(" 内部")
                else if (SubStr(StrReplace(ttext, "→", ""), 1, 1) == "⎖")
                    tip .= "`n" GetLang("提示: 无法移动到此位置")
                else
                    tip .= "`n" GetLang("目标: 插入到 ") ttext GetLang(this._dragSlot == "top" ? " 上方" : " 下方")
            } else
                tip .= "`n" GetLang("目标: 追加到末尾")
            ; 提示文本变化才刷新，避免每帧重建 ToolTip 闪烁
            if (tip != this._lastDragTip) {
                this._lastDragTip := tip
                ToolTip(tip)
            }
        }
    }

    ; 窗口坐标 → 树坐标（用于命中树取插入线位置）
    _TreeCoord(winCoord) {
        if (!IsObject(this.ui))
            return ""
        pos := this.ui.Query("MacroTree>Position")
        if (pos == "")
            return ""
        pp := StrSplit(pos, ",")
        wc := StrSplit(winCoord, ";")
        if (pp.Length != 2 || wc.Length != 2)
            return ""
        return (wc[1] - pp[1]) ";" (wc[2] - pp[2])
    }

    ; 拖拽结束/取消统一复位：恢复渲染、隐藏插入线、清 ToolTip
    _DragEndReset() {
        this._dragActive := false
        this._dragCandidate := ""
        this._dragTarget := ""
        this._dragSlot := ""
        this._lastDragTip := ""
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
        if (IsObject(this.ui)) {
            try this.ui.Update("DragInsertLine", "Visibility", "Collapsed")
        }
        ToolTip()
    }

    ; 窗口级松开左键：执行拖放（释放点不在树上则取消）
    _OnTreeDragDrop(state, ctrl, event) {
        if (!this._dragActive || !IsObject(this._dragCandidate))
            return
        cand := this._dragCandidate
        coord := this._EventCoord(state, "Window")
        overTree := (coord != "" && IsObject(this.ui) && this.ui.Query("Window>IsOverTree:" coord) == "1")
        this._DragEndReset()
        this._dragCancelled := true
        SetTimer((*) => this._dragCancelled := false, -300)
        if (!overTree)
            return
        ; 用释放点重新命中测试，取最终目标（转树内坐标后命中列表，扁平列表无 TreeView 命中）
        target := ""
        slot := ""
        if (coord != "") {
            treeCoord := this._TreeCoord(coord)
            tagSlot := (treeCoord != "") ? this._HitTest("MacroTree", treeCoord) : ""
            if (tagSlot != "") {
                parts := StrSplit(tagSlot, "|")
                target := parts[1]
                slot := parts.Length > 1 ? parts[2] : ""
            }
        }
        if (cand.fromLeft) {
            this.CurItemID := target
            if (target == "") {
                this.OnOpenSubGui(cand.gui, 1)
                return
            }
            text := this.MacroTreeViewCon.GetText(target)
            if (SubStr(StrReplace(text, "→", ""), 1, 1) == "⎖")
                return
            if (this.IsContainerNode(text)) {
                this.OnOpenSubGui(cand.gui, 5)
            } else {
                this.OnOpenSubGui(cand.gui, slot == "top" ? 3 : 4)
            }
            return
        }
        ; 树内移动：源 = 按下时命中的节点，目标 = 拖放时命中的节点
        source := cand.source
        if (source == "")
            return
        if (target == "") {
            this.MoveTreeViewItem(source, 0, 0, 1)
            return
        }
        if (target == source)
            return
        if (this.IsDescendantOrSelf(this.MacroTreeViewCon, source, target))
            return
        text := this.MacroTreeViewCon.GetText(target)
        if (SubStr(StrReplace(text, "→", ""), 1, 1) == "⎖")
            return
        if (this.IsContainerNode(text)) {
            this.MoveTreeViewItem(source, target, target, 5)
        } else {
            destParent := this.MacroTreeViewCon.GetParent(target)
            this.MoveTreeViewItem(source, destParent, target, slot == "top" ? 3 : 4)
        }
    }

    _ProcessTreeLeftClick() {
        if (!IsObject(this.ui))
            return
        coord := this._treeClickCoord
        if (coord == "")
            return
        tagSlot := this._HitTest("MacroTree", coord)
        if (tagSlot == "")
            return
        parts := StrSplit(tagSlot, "|")
        itemID := parts[1]
        ; 点在展开箭头上：切换展开/折叠（扁平列表无 WPF 原生箭头）；叶子无子节点则落到下方正常选择
        if (parts.Length > 2 && parts[3] == "1") {
            if (this.MacroTreeViewCon.GetChild(itemID) != 0) {
                this.MacroTreeViewCon.Modify(itemID, this.MacroTreeViewCon.IsExpanded(itemID) ? "Collapse" : "Expand")
                return
            }
        }
        if (GetKeyState("Shift", "P"))
            this.SelectMultiRange(this.MultiSelectAnchor, itemID)
        else if (GetKeyState("Ctrl", "P"))
            this.ToggleMultiSelection(itemID)
        else
            this.SetSingleMultiSelection(itemID)
        this.CurItemID := itemID
        this.MacroTreeViewCon.Modify(itemID, "Select")
    }

    ; WPF 树右键按下：记录命中坐标，延迟弹右键菜单（命中不到节点不弹，不误改多选）
    _OnTreePreviewRightDown(state, ctrl, event) {
        if (this.EditModeCon.Value != 1 || !IsObject(this.ui))
            return
        this._rightClickCoord := this._EventCoord(state, "MacroTree")
        SetTimer(ObjBindMethod(this, "_ProcessTreeRightClick"), -20)
    }

    _ProcessTreeRightClick() {
        if (!IsObject(this.ui))
            return
        coord := this._rightClickCoord
        this._rightClickCoord := ""
        if (coord == "")
            return
        tagSlot := this._HitTest("MacroTree", coord)
        if (tagSlot == "")
            return
        itemID := StrSplit(tagSlot, "|")[1]
        this.CurItemID := itemID
        itemText := this.MacroTreeViewCon.GetText(itemID)
        cleanItemText := StrReplace(itemText, "→", "")
        if (cleanItemText == "" || SubStr(cleanItemText, 1, 1) == "⎖")
            return
        if (this.IsContainerNode(itemText)) {
            this.ui.Update("BranchCtxMenu", "IsOpen", "True")
            return
        }
        SkipMenuText := SubStr(cleanItemText, 1, 2) == "🚫" ? GetLang("取消跳过") : GetLang("跳过指令")
        DebugMenuText := SubStr(cleanItemText, 1, 1) == "⭐" ? GetLang("取消调试起点") : GetLang("调试起点")
        this.ui.Update("MenuSkipCmd", "Header", SkipMenuText)
        this.ui.Update("MenuDebugCmd", "Header", DebugMenuText)
        this.ui.Update("TreeCtxMenu", "IsOpen", "True")
    }

    OnDoubleClick(ctrl, item) {
        if (item == 0)
            return

        itemText := this.MacroTreeViewCon.GetText(item)
        if (itemText == "" || SubStr(itemText, 1, 1) == "⎖")
            return

        this.CurItemID := item
        if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体")) {
            if (this.SubMacroEditGui == "")
                this.SubMacroEditGui := MacroEditGui()

            macroStr := this.GetTreeMacroStr(this.CurItemID)
            this.SubMacroEditGui.SureBtnAction := this.OnSubNodeEdit.Bind(this, this.CurItemID)
            this.SubMacroEditGui.SureFocusCon := this.MacroTreeViewCon
            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.SubMacroEditGui.ParentTile := ParentTile "-"

            if (MainSoftData.IsModalSubGui && this.Gui != "") {
                this.SubMacroEditGui.OwnerHwnd := this.Gui.Hwnd
            }
            else {
                this.SubMacroEditGui.OwnerHwnd := ""
            }

            this.SubMacroEditGui.ShowGui(macroStr, false)
            return
        }
        else if (SubStr(itemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")) {
            if (this.CompareProEditItemGui == "")
                this.CompareProEditItemGui := CompareProEditItemGui()
            this.CompareProEditItemGui.IsSubMacroEdit := true
            this.CompareProEditItemGui.SureBtnAction := this.OnSubNodeEdit.Bind(this, this.CurItemID)

            if (MainSoftData.IsModalSubGui && this.Gui != "") {
                this.CompareProEditItemGui.OwnerHwnd := this.Gui.Hwnd
            }
            else {
                this.CompareProEditItemGui.OwnerHwnd := ""
            }

            ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
            CommndStr := this.MacroTreeViewCon.GetText(ParentID)
            ItemNumber := this.GetItemNumber(this.CurItemID)
            this.CompareProEditItemGui.MacroEditShowGui(CommndStr, ItemNumber)
            return
        }

        ; 清理→前缀（⭐/🚫 由 GetCmdOnlyText / GetCmdStr 处理）
        cleanText := StrReplace(itemText, "→", "")
        paramsArr := StrSplit(cleanText, "_")
        cmd := GetCmdOnlyText(paramsArr[1])
        ; 图形开始节点：用节点编辑器打开，不走普通指令 SubGui
        if (this._IsGraphStartCmd(cmd)) {
            this._OpenGraphNodeEditor(GetCmdStr(paramsArr[1]), GetCmdSymbol(paramsArr[1]))
            return
        }
        if (!this.SubGuiMap.Has(cmd))
            return
        subGui := this.SubGuiMap[cmd]
        this.OnOpenSubGui(subGui, 2)
    }

    ; 是否为「图形开始节点」序列码（逻辑树中的图入口指令）
    _IsGraphStartCmd(cmd) {
        key := GetLangKey(cmd)
        return key == "图形开始节点" || cmd == GetLang("图形开始节点")
    }

    ; 双击/编辑：打开嵌套节点编辑器，编辑该图形开始节点子图
    _OpenGraphNodeEditor(cmdStr, symbol := "") {
        itemId := this.CurItemID
        parentId := this.MacroTreeViewCon.GetParent(itemId)
        serial := GetLangMacro(cmdStr, 2)
        if (this.SubMacroGraphGui == "")
            this.SubMacroGraphGui := MacroGraphGui()
        this.SubMacroGraphGui.OwnerHwnd := (MainSoftData.IsModalSubGui && this.Gui != "") ? this.Gui.Hwnd : ""
        this.SubMacroGraphGui.ShowToTreeBtn := true
        this.SubMacroGraphGui.OnClosedAction := ""
        this.SubMacroGraphGui.SureBtnAction := (startSerial) => this._OnGraphNodeEditorSure(itemId, startSerial, symbol)
        ; 「逻辑树」：把该子图转成线性宏写回当前逻辑树（循环体等），不打开顶层编辑器
        this.SubMacroGraphGui.OnSwitchToTreeAction := (linear) => this._OnGraphNodeSwitchToTree(parentId, itemId, linear)
        this.SubMacroGraphGui.ShowGui(serial)
    }

    ; 嵌套节点编辑器点「逻辑树」：子图转线性后写回所属分支并刷新树
    _OnGraphNodeSwitchToTree(parentId, itemId, linear) {
        displayLinear := GetLangMacro(linear, 1)
        if (displayLinear == "")
            displayLinear := " "
        if (parentId != 0) {
            try this.MacroTreeViewCon.GetText(parentId)
            catch
                return
            this.OnSubNodeEdit(parentId, displayLinear)
            return
        }
        ; 根级图形开始节点：用线性宏替换该节点
        try this.MacroTreeViewCon.GetText(itemId)
        catch
            return
        this.CurItemID := itemId
        cmds := SplitMacro(displayLinear)
        if (cmds.Length == 0) {
            this.OnDeleteCmd()
            return
        }
        this.OnModifyCmd(cmds[1])
        loop cmds.Length - 1 {
            this.OnNextInsertCmd(cmds[A_Index + 1])
            ; OnNextInsertCmd 后 CurItemID 仍指向原节点；插在其后需推进选中
            nextId := this.MacroTreeViewCon.GetNext(this.CurItemID)
            if (nextId)
                this.CurItemID := nextId
        }
    }

    _OnGraphNodeEditorSure(itemId, startSerial, symbol := "") {
        ; 先清空回调，避免窗口 Closed 重复触发 _Apply 时二次改树
        if (this.SubMacroGraphGui != "")
            this.SubMacroGraphGui.SureBtnAction := ""
        if (itemId == "" || itemId == 0)
            return
        displayStr := symbol . GetLangMacro(startSerial, 1)
        ; 节点可能已被上次回写 RefreshTree 重建；失效则跳过
        try curText := this.MacroTreeViewCon.GetText(itemId)
        catch
            return
        ; 图内容已由 _SaveGraph 落盘；显示序列码未变则不必改树
        if (GetCmdStr(curText) == GetCmdStr(displayStr))
            return
        this.CurItemID := itemId
        ParentID := this.MacroTreeViewCon.GetParent(itemId)
        if (ParentID == 0) {
            this.OnModifyCmd(displayStr)
            return
        }
        ; 位于真/假/循环体/条件下：改子节点后按分支宏整体回写
        this.MacroTreeViewCon.Modify(itemId, , displayStr)
        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        if (RealItemID == 0)
            return
        try this.MacroTreeViewCon.GetText(RealItemID)
        catch
            return
        this.OnSubNodeEdit(ParentID, macroStr)
    }

    MenuHandler(cmdNextStr, *) {
        switch cmdNextStr {
            case GetLang("变量监视"):
            {
                if (MyVarListenGui.Gui != "" && MyVarListenGui.Gui.Hwnd) {
                    style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        this.ToolMenu.Uncheck(GetLang("变量监视"))
                        MyVarListenGui.Gui.Hide()
                        return
                    }
                }
                this.ToolMenu.Check(GetLang("变量监视"))
                MyVarListenGui.ShowGui()
            }
            case GetLang("指令显示"):
            {
                if (MyCMDTipGui.Gui != "" && MyCMDTipGui.Gui.Hwnd) {
                    style := WinGetStyle(MyCMDTipGui.Gui.Hwnd)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        MySoftData.CMDTip := false
                        SetCMDTipValue(false)
                        this.ToolMenu.Uncheck(GetLang("指令显示"))
                        MyCMDTipGui.Gui.Hide()
                        return
                    }
                }
                MySoftData.CMDTip := true
                SetCMDTipValue(true)
                MyCMDTipGui.ShowGui(GetLang("开启指令显示"))
                this.ToolMenu.Check(GetLang("指令显示"))
            }
            case GetLang("窗口置顶"):
            {
                this._topOn := !this._topOn
                if (IsObject(this.ui))
                    this.ui.Update("Window", "Topmost", this._topOn ? "True" : "False")
                this.ToolMenu.ToggleCheck(GetLang("窗口置顶"))
            }
            case GetLang("运行(F5)"):
            {
                this.ResetDebugState()
                MacroStr := this.GetMacroStr()
                MacroStr := GetLangMacro(macroStr, 2)
                ResArr := StrSplit(MacroStr, "⭐", 2)
                MacroStr := ResArr.Length > 1 ? ResArr[2] : MacroStr
                MyCMDTipGui.Hide()
                OnTriggerSepcialItemMacro(MacroStr)
                MsgBox(GetLang("调试运行结束"), "", "Owner" this.Gui.Hwnd)
            }
            case GetLang("单步运行(F6)"):
            {
                tableItem := MySoftData.SpecialTableItem
                if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState == 1) {
                    return
                }

                ; 阶段1: 定位（首次F6或终止后，查找⭐起点或第一项）
                if (this.DebugItemID == 0) {
                    MyCMDTipGui.Hide()
                    this.DebugItemID := this.FindDebugStartItem()
                    if (!this.DebugItemID) {
                        this.DebugItemID := this.MacroTreeViewCon.GetNext(0)
                    }
                }
                if (!this.DebugItemID)
                    return

                try {
                    CurCMD := this.MacroTreeViewCon.GetText(this.DebugItemID)
                } catch {
                    this.ResetDebugState()
                    return
                }

                ; 阶段2: 跳过不可执行项（🚫禁用和⎖容器配置），自动推进不消耗步数
                while (SubStr(CurCMD, 1, 2) == "🚫" || SubStr(CurCMD, 1, 1) == "⎖") {
                    this.AdvanceToNext()
                    if (!this.DebugItemID)
                        return
                    try {
                        CurCMD := this.MacroTreeViewCon.GetText(this.DebugItemID)
                    } catch {
                        this.ResetDebugState()
                        return
                    }
                }

                ; 阶段3: 标记当前位置 → 执行
                this.MarkCurrentPosition(this.DebugItemID)

                CleanCMD := StrReplace(StrReplace(CurCMD, "⭐", ""), "→", "")
                ; 还原格式化的手柄键名后执行
                CleanCMD := MySoftData.ParseCmdJoyDisplay(CleanCMD)
                CurLangCMD := GetLangMacro(CleanCMD, 2)
                OnTriggerSepcialItemMacro(CurLangCMD)

                ; 阶段4: 推进到下一项
                this.AdvanceToNext()
            }
            case GetLang("终止"):
            {
                KillSingleTableMacro(MySoftData.SpecialTableItem)
                this.ResetDebugState()
                MyCMDTipGui.ShowGui(GetLang("终止"))
            }
        }
    }

    ContentMenuHandler(cmdStr, *) {
        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        ; 清理→前缀用于状态判断
        cleanItemText := StrReplace(itemText, "→", "")
        paramsArr := StrSplit(cmdStr, "_")
        if (paramsArr.Length == 2) {
            modeType := paramsArr[1] == "Pre" ? 3 : paramsArr[1] == "Next" ? 4 : 5
            this.CmdEditType := modeType
            subGui := this.SubGuiMap[paramsArr[2]]
            this.OnOpenSubGui(subGui, modeType)
            return
        }

        switch cmdStr {
            case GetLang("编辑"):
            {
                paramsArr := StrSplit(cleanItemText, "_")
                cmd := GetCmdOnlyText(paramsArr[1])
                if (this._IsGraphStartCmd(cmd)) {
                    this._OpenGraphNodeEditor(GetCmdStr(paramsArr[1]), GetCmdSymbol(paramsArr[1]))
                    return
                }
                if (!this.SubGuiMap.Has(cmd))
                    return
                subGui := this.SubGuiMap[cmd]
                this.OnOpenSubGui(subGui, 2)
            }
            case "Skip":
            {
                if (SubStr(cleanItemText, 1, 1) == "⭐") {
                    MsgBox(GetLang("调试起点不能跳过"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                IsToSkip := SubStr(cleanItemText, 1, 2) != "🚫"
                CommandStr := IsToSkip ? "🚫" cleanItemText : SubStr(cleanItemText, 3)
                this.OnModifyCmd(CommandStr)
            }
            case "Debug":
                if (SubStr(cleanItemText, 1, 2) == "🚫") {
                    MsgBox(GetLang("跳过指令不可设置为调试起点"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                IsToDebug := SubStr(cleanItemText, 1, 1) != "⭐"
                CommandStr := IsToDebug ? "⭐" cleanItemText : SubStr(cleanItemText, 2)
                ; ⭐是持久标记，由F6单步时FindDebugStartItem查找，不直接设DebugItemID
                this.OnModifyCmd(CommandStr)
            case GetLang("复制"):
            {
                selectedItems := this.GetMultiSelectedItems()
                if (selectedItems.Length <= 1) {
                    newCmd := FullCopyCmd(cleanItemText)
                    SetClipboard(newCmd)
                    return
                }

                ; 多選複製：依 TreeView 中的原始順序輸出，以逗號組成可再次 SplitMacro() 的宏字串。
                copyStr := ""
                for itemID in selectedItems {
                    try {
                        text := this.MacroTreeViewCon.GetText(itemID)
                    } catch {
                        continue
                    }
                    text := StrReplace(text, "⭐", "")
                    text := StrReplace(text, "→", "")
                    if (text == "" || SubStr(text, 1, 1) == "⎖")
                        continue
                    cmd := FullCopyCmd(text)
                    if (cmd != "")
                        copyStr .= (copyStr == "" ? "" : ",") cmd
                }
                if (copyStr != "")
                    SetClipboard(copyStr)
            }
            case GetLang("粘贴"):
            {
                this.PasteClipboardCommands(A_Clipboard)
            }
            case "SharedCopy":
            {
                ; 共享复制：原样复制指令文本，不重新分配内部序列号，方便分享到其他宏/其他设备
                selectedItems := this.GetMultiSelectedItems()
                if (selectedItems.Length <= 1) {
                    SetClipboard(cleanItemText)
                    Toast.Show(GetLang("已复制"))
                    return
                }

                copyStr := ""
                for itemID in selectedItems {
                    try {
                        text := this.MacroTreeViewCon.GetText(itemID)
                    } catch {
                        continue
                    }
                    text := StrReplace(text, "⭐", "")
                    text := StrReplace(text, "→", "")
                    if (text == "" || SubStr(text, 1, 1) == "⎖")
                        continue
                    if (text != "")
                        copyStr .= (copyStr == "" ? "" : ",") text
                }
                if (copyStr != "")
                    SetClipboard(copyStr)
                Toast.Show(GetLang("已复制"))
            }
            case "BranchCopy":
            {
                ; 分支／循环体容器不是实际指令，复制时应复制其内部宏内容。
                if (!this.IsContainerNode(cleanItemText))
                    return

                branchMacroStr := this.GetTreeMacroStr(this.CurItemID)
                if (branchMacroStr == "") {
                    SetClipboard("")
                } else {
                    cmds := SplitMacro(branchMacroStr)
                    copyStr := ""
                    for _, text in cmds {
                        text := Trim(text, " `t`r`n")
                        if (text == "")
                            continue
                        text := StrReplace(text, "⭐", "")
                        text := StrReplace(text, "→", "")
                        cmd := FullCopyCmd(text)
                        if (cmd != "")
                            copyStr .= (copyStr == "" ? "" : ",") cmd
                    }
                    SetClipboard(copyStr)
                }
                Toast.Show(GetLang("已复制"))
            }
            case "BranchSharedCopy":
            {
                ; 共享复制保留分支內部的原始宏文字，不重新分配内部序列号。
                if (!this.IsContainerNode(cleanItemText))
                    return

                branchMacroStr := this.GetTreeMacroStr(this.CurItemID)
                SetClipboard(branchMacroStr)
                Toast.Show(GetLang("已复制"))
                return
            }
            case GetLang("删除"):
            {
                this.OnDeleteCmd()
            }
        }
    }

    ; 重置调试状态（清除位置和→标记）
    ResetDebugState() {
        this.DebugItemID := 0
        this.ClearCurrentPosition()
    }

    ; 在指定项上加→前缀，表示当前位置（同时清除旧位置）
    MarkCurrentPosition(itemID) {
        ; 先清除旧的→标记
        if (this.CurrentItemID && this.CurrentItemID != itemID) {
            try {
                oldText := this.MacroTreeViewCon.GetText(this.CurrentItemID)
                if (SubStr(oldText, 1, 1) == "→") {
                    this.MacroTreeViewCon.Modify(this.CurrentItemID, , SubStr(oldText, 2))
                }
            } catch {
                ; 旧项可能已失效，忽略
            }
        }
        ; 在新项上加→（保留⭐标记）
        try {
            text := this.MacroTreeViewCon.GetText(itemID)
            hasStar := SubStr(text, 1, 1) == "⭐"
            cleanText := StrReplace(text, "⭐", "")
            cleanText := StrReplace(cleanText, "→", "")
            if (SubStr(cleanText, 1, 2) != "🚫" && SubStr(cleanText, 1, 1) != "⎖") {
                newText := hasStar ? "→⭐" cleanText : "→" cleanText
                this.MacroTreeViewCon.Modify(itemID, , newText)
            }
        } catch {
            ; 忽略
        }
        this.CurrentItemID := itemID
    }

    ; 清除当前项的→标记
    ClearCurrentPosition() {
        if (!this.CurrentItemID)
            return
        try {
            text := this.MacroTreeViewCon.GetText(this.CurrentItemID)
            if (SubStr(text, 1, 1) == "→") {
                this.MacroTreeViewCon.Modify(this.CurrentItemID, , SubStr(text, 2))
            }
        } catch {
            ; 忽略
        }
        this.CurrentItemID := 0
    }

    ; 推进到下一个可执行项，到达末尾时直接结束
    AdvanceToNext() {
        safeCount := 0
        loop {
            if (safeCount++ > 1000) {
                this.ResetDebugState()
                return
            }
            try
                nextID := this.MacroTreeViewCon.GetNext(this.DebugItemID)
            catch {
                this.ResetDebugState()
                MsgBox(GetLang("单步运行结束"), "", "Owner" this.Gui.Hwnd)
                return
            }
            if (!nextID) {
                ; 到达当前层级末尾，直接结束
                this.ResetDebugState()
                MsgBox(GetLang("单步运行结束"), "", "Owner" this.Gui.Hwnd)
                return
            }
            this.DebugItemID := nextID

            try {
                cmdNextStr := this.MacroTreeViewCon.GetText(this.DebugItemID)
            } catch {
                this.ResetDebugState()
                MsgBox(GetLang("单步运行结束"), "", "Owner" this.Gui.Hwnd)
                return
            }

            ; 跳过禁用项和特殊容器配置项
            if (SubStr(cmdNextStr, 1, 2) == "🚫" || SubStr(cmdNextStr, 1, 1) == "⎖")
                continue

            break
        }
        ; 到达下一个可执行项，标记为当前位置
        this.MarkCurrentPosition(this.DebugItemID)
    }

    ; 递归遍历整个TreeView（含子分支），查找带⭐的调试起点项
    FindDebugStartItem(startID := 0) {
        itemID := this.MacroTreeViewCon.GetNext(startID)
        while (itemID) {
            try
                text := this.MacroTreeViewCon.GetText(itemID)
            catch {
                try
                    itemID := this.MacroTreeViewCon.GetNext(itemID)
                catch
                    break
                continue
            }
            ; 当前项就是⭐起点
            if (SubStr(text, 1, 1) == "⭐")
                return itemID
            ; 递归检查子分支（支持任意层级嵌套）
            found := this._FindStarInChildren(itemID)
            if (found)
                return found
            try
                itemID := this.MacroTreeViewCon.GetNext(itemID)
            catch
                break
        }
        return 0
    }

    ; 在指定节点的所有后代中递归查找⭐
    _FindStarInChildren(parentID) {
        try
            childID := this.MacroTreeViewCon.GetChild(parentID)
        catch
            return 0
        while (childID) {
            try
                childText := this.MacroTreeViewCon.GetText(childID)
            catch {
                try
                    childID := this.MacroTreeViewCon.GetNext(childID)
                catch
                    break
                continue
            }
            if (SubStr(childText, 1, 1) == "⭐")
                return childID
            ; 递归深入子节点的子节点
            deeper := this._FindStarInChildren(childID)
            if (deeper)
                return deeper
            try
                childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
        return 0
    }

    InitTreeView(MacroStr) {
        this.ResetDebugState()
        this.ClearMultiSelection()
        this.MacroTreeViewCon.Visible := this.EditModeCon.Value == 1
        cmdArr := SplitMacro(MacroStr)
        this.MacroTreeViewCon.Opt("-Redraw")
        this.MacroTreeViewCon.Delete()
        this.LastItemID := 0
        for cmdStr in cmdArr {
            iconStr := this.GetCmdIconStr(cmdStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(cmdStr)
            root := this.MacroTreeViewCon.Add(displayStr, 0, iconStr)
            this.LastItemID := root
            this.TreeAddBranch(root, cmdStr)
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    RefreshTree(itemID) {
        this.ClearMultiSelection()
        CommandStr := this.MacroTreeViewCon.GetText(itemID)
        paramsArr := StrSplit(CommandStr, "_")

        subItem := this.MacroTreeViewCon.GetChild(itemID)
        while (subItem) {
            this.MacroTreeViewCon.Delete(subItem)
            subItem := this.MacroTreeViewCon.GetChild(itemID)
        }
        this.TreeAddBranch(itemID, CommandStr)
        ; 不再 TreeExpand：新节点默认 expanded，增量增删已呈现完整分支，无需全量重建
    }

    TreeAddBranch(root, cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        IsSkip := SubStr(paramArr[1], 1, 2) == "🚫"
        IsSearchPro := InStr(paramArr[1], GetLang("搜索Pro"))
        IsSearch := InStr(paramArr[1], GetLang("搜索")) && !IsSearchPro
        IsIfPro := InStr(paramArr[1], GetLang("如果Pro"))
        IsIf := InStr(paramArr[1], GetLang("如果")) && !IsIfPro
        IsLoop := InStr(paramArr[1], GetLang("循环"))
        Cmd := GetCmdOnlyText(paramArr[1])
        SerialStr := GetCmdStr(paramArr[1])
        if (IsSkip)
            return
        if (!IsSearch && !IsSearchPro && !IsIf && !IsLoop && !IsIfPro)
            return

        ParentID := this.MacroTreeViewCon.GetParent(root)
        while (ParentID != 0) {
            itemText := this.MacroTreeViewCon.GetText(ParentID)
            itemParamArr := StrSplit(itemText, "_")
            ParentID := this.MacroTreeViewCon.GetParent(ParentID)
            if (itemParamArr[1] == paramArr[1])
                return
        }

        Data := GetMacroCMDData(SerialStr)
        if (IsIf || IsSearch || IsSearchPro) {
            TrueMacro := GetLangMacro(Data.TrueMacro, 1)
            FalseMacro := GetLangMacro(Data.FalseMacro, 1)

            iconStr := this.GetCmdIconStr(GetLang("真"))
            trueRoot := this.MacroTreeViewCon.Add(GetLang("真"), root, iconStr)
            ControlType := IsIf ? Data.TrueControlType : "无"
            this.TreeAddSubTree(trueRoot, TrueMacro)
            this.TreeAddControl(trueRoot, ControlType)

            iconStr := this.GetCmdIconStr(GetLang("假"))
            falseRoot := this.MacroTreeViewCon.Add(GetLang("假"), root, iconStr)
            ControlType := IsIf ? Data.FalseControlType : "无"
            this.TreeAddSubTree(falseRoot, FalseMacro)
            this.TreeAddControl(falseRoot, ControlType)
        }
        else if (IsLoop) {
            iconStr := this.GetCmdIconStr(GetLang("循环次数"))
            countStr := Data.LoopCount == -1 ? GetLang("无限") : Data.LoopCount
            CountRoot := this.MacroTreeViewCon.Add(Format("{}:{}", GetLang("⎖循环次数"), countStr), root, iconStr)

            if (Data.CondiType != 1) {
                iconStr := this.GetCmdIconStr(GetLang("条件"))
                CondiStr := Data.CondiType == 2 ? GetLang("⎖继续条件：") : GetLang("⎖退出条件：")
                ItemStr := CondiStr . LoopData.GetCondiStr(Data)
                CondiRoot := this.MacroTreeViewCon.Add(ItemStr, root, iconStr)
            }

            iconStr := this.GetCmdIconStr(GetLang("循环体"))
            BodyRoot := this.MacroTreeViewCon.Add(GetLang("循环体"), root, iconStr)
            LoopBody := GetLangMacro(Data.LoopBody, 1)
            this.TreeAddSubTree(BodyRoot, LoopBody)
        }
        else if (IsIfPro) {
            iconStr := this.GetCmdIconStr(GetLang("条件"))
            loop Data.VariNameArr.Length {
                CondiStr := GetLang("条件：") CompareProData.GetCondiStr(Data, A_Index)
                CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
                MacroStr := GetLangMacro(Data.MacroArr[A_Index], 1)
                this.TreeAddSubTree(CondiRoot, MacroStr)
                this.TreeAddControl(CondiRoot, Data.ControlTypeArr[A_Index])
            }

            CondiStr := GetLang("条件：以上都不是")
            CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
            DefaultMacro := GetLangMacro(Data.DefaultMacro, 1)
            this.TreeAddSubTree(CondiRoot, DefaultMacro)
            this.TreeAddControl(CondiRoot, Data.DefaultControlType)
        }
    }

    TreeAddControl(root, ControlType) {
        if (ControlType == "无")
            return

        iconStr := this.GetCmdIconStr(GetLang("流程控制"))
        ItemStr := GetLang("⎖流程控制：") . GetLang(ControlType)
        this.MacroTreeViewCon.Add(ItemStr, root, iconStr)
    }

    TreeAddSubTree(root, CommandStr) {
        if (CommandStr == "")
            return

        cmdArr := SplitMacro(CommandStr)
        for cmdStr in cmdArr {
            iconStr := this.GetCmdIconStr(cmdStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(cmdStr)
            subRoot := this.MacroTreeViewCon.Add(displayStr, root, iconStr)
            this.TreeAddBranch(subRoot, cmdStr)
        }
    }

    ;打开子指令编辑器 modeType 1:默认行尾追加 2:编辑修改 3:上方插入 4:下方插入 5:真假节点添加
    ; 子指令窗口是否正在显示（用于同类型多开判断）
    ; XAML 版用 _closed 生命周期标志判断（原生版用 WS_VISIBLE）
    IsSubGuiVisible(subGui) {
        return IsObject(subGui) && ObjHasOwnProp(subGui, "_closed") && !subGui._closed
    }

    ; 收集某共享子 GUI 同类型的全部实例（共享 + 多开额外实例）
    GetSubGuiInstances(sharedGui) {
        list := [sharedGui]
        for g in this.OpenedSubGuis {
            if (IsObject(g) && Type(g) == Type(sharedGui))
                list.Push(g)
        }
        return list
    }

    ; 同一编辑上下文（类型+mode+节点）已打开则复用并前置；不同节点可多开
    ResolveSubGuiInstance(sharedGui, modeType, itemId) {
        for g in this.GetSubGuiInstances(sharedGui) {
            if (!this.IsSubGuiVisible(g))
                continue
            openType := ObjHasOwnProp(g, "_OpenEditType") ? g._OpenEditType : ""
            openItem := ObjHasOwnProp(g, "_OpenItemId") ? g._OpenItemId : ""
            if (openType == modeType && openItem == itemId)
                return g
        }
        for g in this.GetSubGuiInstances(sharedGui) {
            if (!this.IsSubGuiVisible(g))
                return g
        }
        guiClass := ""
        for config in this.SubGuiConfig {
            if (this.SubGuiMap[GetLang(config.name)] == sharedGui) {
                guiClass := config.class
                break
            }
        }
        if (guiClass == "")
            return sharedGui
        newGui := guiClass()
        this.OpenedSubGuis.Push(newGui)
        return newGui
    }

    OnOpenSubGui(subGui, modeType := 1) {
        this.CmdEditType := modeType
        editType := modeType
        itemId := this.CurItemID

        ; 同节点再开：复用并覆盖前置；不同节点：多开新实例
        subGui := this.ResolveSubGuiInstance(subGui, modeType, itemId)
        subGui._OpenEditType := modeType
        subGui._OpenItemId := itemId

        if ObjHasOwnProp(subGui, "ParentTile") {
            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            subGui.ParentTile := ParentTile "-"
        }

        if (MainSoftData.IsModalSubGui && this.Gui != "") {
            subGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            subGui.OwnerHwnd := ""
        }

        ; 绑定打开时的编辑上下文，多开时互不干扰
        subGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr, editType, itemId)

        if (modeType == 2) {
            ItemText := this.MacroTreeViewCon.GetText(this.CurItemID)
            ; 清理→和⭐前缀
            ; 只清理位置标记→（前缀，不是方向箭头显示名）
            ItemText := StrReplace(ItemText, "⭐", "")
            if SubStr(ItemText, 1, 1) = "→"
                ItemText := SubStr(ItemText, 2)
            ; 还原显示名 + 转 BtnN → Joy* 后传给旧 GUI 编辑器
            ItemText := MySoftData.ParseCmdJoyDisplay(ItemText)
            ItemText := MySoftData.CmdJoyNToJoyFriendly(ItemText)
            CommandStr := GetCmdStr(ItemText)
            subGui.ShowGui(CommandStr)
            return
        }
        subGui.ShowGui("")
    }

    ;确定子指令编辑器（editType/itemId 为打开时捕获的上下文，多开时互不干扰）
    OnSubGuiSureBtnClick(CommandStr, editType := 1, itemId := 0) {
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        savedType := this.CmdEditType
        savedItem := this.CurItemID
        this.CmdEditType := editType
        if (itemId != 0)
            this.CurItemID := itemId

        if (editType == 1) {
            this.OnAddCmd(CommandStr)
        }
        else if (editType == 2) {
            this.OnModifyCmd(CommandStr)
        }
        else if (editType == 3) {
            this.OnPreInsertCmd(CommandStr)
        }
        else if (editType == 4) {
            this.OnNextInsertCmd(CommandStr)
        }
        else if (editType == 5) {
            this.OnSubNodeAddCmd(CommandStr)
        }

        this.CmdEditType := savedType
        this.CurItemID := savedItem
        UIControls.RecordToggle := this.RecordMacroCon
        MainSoftData.MacroEditGui := this
    }

    ;添加指令
    OnAddCmd(CommandStr) {
        this.ResetDebugState()
        if (this.EditModeCon.Value == 1) {
            iconStr := this.GetCmdIconStr(CommandStr)
            displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
            root := this.MacroTreeViewCon.Add(displayStr, 0, iconStr)
            this.TreeAddBranch(root, CommandStr)
            this.LastItemID := root
        }
        else {
            MacroStr := this.GetMacroStr()
            MacroStr .= "`n" CommandStr
            cmdArr := SplitMacro(MacroStr)
            MacroStr := GetMacroStrByCmdArr(cmdArr)

            ; 保留滚动位置（#3）
            firstVisible := IsObject(this.ui) ? this.ui.Query("MacroText>FirstVisibleLine") : ""
            this.InitMacroText(MacroStr)
            if (firstVisible != "" && IsObject(this.ui))
                this.ui.Update("MacroText", "ScrollToLine", firstVisible)
            else
                this.MacroEditTextCon.ScrollToEnd()
        }
    }

    ;修改指令
    OnModifyCmd(CommandStr) {
        this.ResetDebugState()
        this.MacroTreeViewCon.Modify(this.CurItemID, , MySoftData.FormatCmdJoyDisplay(CommandStr))
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        if (ParentID == 0) {
            ; 仅分支指令（有子节点）修改结构时重建；叶子修改无需
            if (this.MacroTreeViewCon.GetChild(this.CurItemID) != 0)
                this.RefreshTree(this.CurItemID)
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        if (this.MacroTreeViewCon.GetChild(this.CurItemID) != 0)
            this.RefreshTree(RealItemID)
    }

    OnPreMoveCmd() {
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        if (PreItemID == 0) {
            MsgBox(GetLang("已经是第一个指令了，无法上移"))
            return
        }
        PreText := this.MacroTreeViewCon.GetText(PreItemID)
        if (PreText == "" || SubStr(PreText, 1, 1) == "⎖") {
            MsgBox(GetLang("不可与特殊指令进行交换"))
            return
        }
        this.OnSwitchCmd(PreItemID, this.CurItemID)
    }

    OnNextMoveCmd() {
        NextItemID := this.MacroTreeViewCon.GetNext(this.CurItemID)
        if (NextItemID == 0) {
            MsgBox(GetLang("已经是最后的指令了，无法下移"))
            return
        }
        NextText := this.MacroTreeViewCon.GetText(NextItemID)
        if (NextText == "" || SubStr(NextText, 1, 1) == "⎖") {
            MsgBox(GetLang("不可与特殊指令进行交换"))
            return
        }
        this.OnSwitchCmd(this.CurItemID, NextItemID)
    }

    OnSwitchCmd(ItemAID, ItemBID) {
        this.ResetDebugState()
        LastItemID := this.MacroTreeViewCon.GetPrev(ItemAID)
        ParentID := this.MacroTreeViewCon.GetParent(ItemAID)
        NewACmdStr := this.MacroTreeViewCon.GetText(ItemBID)
        NewBCmdStr := this.MacroTreeViewCon.GetText(ItemAID)
        NewAIconStr := this.GetCmdIconStr(NewACmdStr)
        NewBIconStr := this.GetCmdIconStr(NewBCmdStr)

        this.MacroTreeViewCon.Delete(ItemAID)
        this.MacroTreeViewCon.Delete(ItemBID)
        SortArg := LastItemID == 0 ? "First" : LastItemID
        NewItemAID := this.MacroTreeViewCon.Add(NewACmdStr, ParentID, SortArg " " NewAIconStr)
        NewItemBID := this.MacroTreeViewCon.Add(NewBCmdStr, ParentID, NewItemAID " " NewBIconStr)
        this.TreeAddBranch(NewItemAID, NewACmdStr)
        this.TreeAddBranch(NewItemBID, NewBCmdStr)
        if (ParentID == 0) {
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
    }

    ; Delete 熱鍵與右鍵「刪除」共用這個入口。
    ; 真／假／循環體／條件可以參與多選；刪除時不能直接刪掉容器，
    ; 而是依照單選的語義清空對應分支資料，再統一 RefreshTree。
    OnDeleteCmd() {
        this.ResetDebugState()

        selectedItems := this.GetMultiSelectedItems()
        if (selectedItems.Length == 0 && this.CurItemID)
            selectedItems.Push(this.CurItemID)
        if (selectedItems.Length == 0)
            return

        ; 單選：使用完整的分支刪除邏輯。
        if (selectedItems.Length == 1) {
            this.CurItemID := selectedItems[1]
            this._DeleteSingleCmd(this.CurItemID)
            this.ClearMultiSelection()
            return
        }

        ; 多選項目必須位於同一層級。
        parentID := this.MacroTreeViewCon.GetParent(selectedItems[1])
        for itemID in selectedItems {
            if (this.MacroTreeViewCon.GetParent(itemID) != parentID) {
                ; 舊狀態若存在跨層多選，退回目前項目的單選刪除。
                this.SetSingleMultiSelection(this.CurItemID ? this.CurItemID : selectedItems[1])
                this.CurItemID := this.CurItemID ? this.CurItemID : selectedItems[1]
                this._DeleteSingleCmd(this.CurItemID)
                this.ClearMultiSelection()
                return
            }
        }

        ; 根層沒有「真／假／循環體／條件」容器，正常倒序刪除。
        if (parentID == 0) {
            loop selectedItems.Length {
                itemID := selectedItems[selectedItems.Length - A_Index + 1]
                try this.MacroTreeViewCon.Delete(itemID)
            }
            this.CurItemID := 0
            this.ClearMultiSelection()
            return
        }

        ; parentID 有兩種情況：
        ; 1. parentID 是「真／假／循環體／條件」容器：selectedItems 是其中的普通指令。
        ; 2. parentID 是根層的分支命令：selectedItems 是「真／假／循環體／條件」容器本身。
        parentText := this.MacroTreeViewCon.GetText(parentID)
        parentIsContainer := this.IsContainerNode(parentText)

        if (parentIsContainer) {
            realItemID := this.MacroTreeViewCon.GetParent(parentID)
            if (!realItemID) {
                this.CurItemID := 0
                this.ClearMultiSelection()
                return
            }
            realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        } else {
            ; 分支命令本身就是 SaveCommandData 的 RealCommandStr，刷新它即可。
            realItemID := parentID
            realCommandStr := parentText
        }

        ; 同一 Parent 下若有「條件」容器，刪除前先保存原始 ItemNumber。
        ; IfPro 刪除分支時會移除陣列元素，因此必須從後往前處理。
        containerItems := []
        normalItems := []
        for itemID in selectedItems {
            try itemText := this.MacroTreeViewCon.GetText(itemID)
            catch
                continue

            if (this.IsContainerNode(itemText))
                containerItems.Push(itemID)
            else
                normalItems.Push(itemID)
        }

        ; 容器按 TreeView 順序由後往前處理，避免 IfPro 分支編號因前面刪除而位移。
        loop containerItems.Length {
            bestIndex := 1
            bestNumber := this.GetItemNumber(containerItems[1])
            idx := 2
            while (idx <= containerItems.Length) {
                number := this.GetItemNumber(containerItems[idx])
                if (number > bestNumber) {
                    bestIndex := idx
                    bestNumber := number
                }
                idx += 1
            }

            itemID := containerItems.RemoveAt(bestIndex)
            this.SaveCommandData(realCommandStr, "", itemID)
        }

        ; 一般子指令才直接 Delete；從後往前刪，避免 TreeView handle 互相影響。
        loop normalItems.Length {
            itemID := normalItems[normalItems.Length - A_Index + 1]
            try this.MacroTreeViewCon.Delete(itemID)
        }

        ; 如果 selectedItems 是容器本身，前面的 SaveCommandData 已逐個清空對應分支。
        ; 如果 selectedItems 是容器內普通指令，則需要把剩餘宏重新寫回該容器。
        if (parentIsContainer) {
            macroStr := this.GetTreeMacroStr(parentID)
            isCondi := SubStr(StrReplace(parentText, "→", ""), 1, StrLen(GetLang("条件"))) == GetLang("条件")
            macroStr := macroStr == "" && isCondi ? "空条件" : macroStr
            this.SaveCommandData(realCommandStr, macroStr, parentID)
        }

        this.RefreshTree(realItemID)
        this.CurItemID := 0
        this.ClearMultiSelection()
    }

    ; 單一指令的刪除邏輯。容器節點不能直接 Delete，只能清空它所代表的分支。
    _DeleteSingleCmd(itemID) {
        if (!itemID)
            return

        itemText := this.MacroTreeViewCon.GetText(itemID)
        isContainer := this.IsContainerNode(itemText)
        ParentID := this.MacroTreeViewCon.GetParent(itemID)

        ; 理論上根層不會出現容器；即使狀態異常，也不要直接刪除容器。
        if (ParentID == 0) {
            if (!isContainer)
                this.MacroTreeViewCon.Delete(itemID)
            return
        }

        NodeItemID := itemID
        RealItemID := ParentID
        macroStr := ""

        ; 普通指令：直接刪除，再將同層剩餘內容寫回父容器。
        if (!isContainer) {
            this.MacroTreeViewCon.Delete(itemID)
            NodeItemID := ParentID
            RealItemID := this.MacroTreeViewCon.GetParent(NodeItemID)
            macroStr := this.GetTreeMacroStr(NodeItemID)

            NodeItemText := this.MacroTreeViewCon.GetText(NodeItemID)
            isCondi := SubStr(StrReplace(NodeItemText, "→", ""), 1, StrLen(GetLang("条件"))) == GetLang("条件")
            macroStr := macroStr == "" && isCondi ? "空条件" : macroStr
        }

        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, NodeItemID)
        ; 普通指令删除已增量完成；仅清空容器分支时才需重建
        if (isContainer)
            this.RefreshTree(RealItemID)
    }

    ;插入指令
    OnPreInsertCmd(CommandStr) {
        this.ResetDebugState()
        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        Seq := PreItemID == 0 ? "First" : PreItemID
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, ParentID, Seq " " iconStr)
        this.TreeAddBranch(newItemID, CommandStr)
        if (ParentID == 0)
            return

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
    }

    ; 插入一條指令；返回刷新後可繼續作為插入錨點的 TreeView ItemID。
    OnNextInsertCmd(CommandStr) {
        this.ResetDebugState()

        ; 防止多條指令誤傳進來，避免把「运行,输出,如果」當成一個 command key。
        cmds := SplitMacro(CommandStr)
        if (cmds.Length > 1) {
            this.PasteClipboardCommands(CommandStr)
            return 0
        }

        CommandStr := Trim(CommandStr, " `t`r`n")
        if (CommandStr == "")
            return 0

        anchorItemID := this.CurItemID
        ParentID := this.MacroTreeViewCon.GetParent(anchorItemID)

        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, ParentID, anchorItemID " " iconStr)
        if (anchorItemID == this.LastItemID)
            this.LastItemID := newItemID
        this.TreeAddBranch(newItemID, CommandStr)

        if (ParentID == 0) {
            this.CurItemID := newItemID
            this.MacroTreeViewCon.Modify(newItemID, "Select")
            return newItemID
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)

        ; 不再 RefreshTree：newItemID 保持有效，直接选中
        this.CurItemID := newItemID
        this.MacroTreeViewCon.Modify(newItemID, "Select")
        return newItemID
    }

    ; 粘貼到真/假/循環體/條件容器節點內部：把指令追加到該分支末尾並回寫。
    ; 容器節點不能像普通指令一樣在同層級插入，否則 GetParent 取到根後 GetText(0) 報錯。
    PasteIntoContainer(containerID, cmds) {
        realItemID := this.MacroTreeViewCon.GetParent(containerID)
        if (!realItemID)
            return

        realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        macroStr := this.GetTreeMacroStr(containerID)

        for _, cmdStr in cmds {
            cmdStr := Trim(cmdStr, " `t`r`n")
            if (cmdStr == "")
                continue
            macroStr := (macroStr == "" ? "" : macroStr ",") cmdStr
        }

        this.SaveCommandData(realCommandStr, macroStr, containerID)
        this.RefreshTree(realItemID)
        this.CurItemID := 0
    }

    ; 將剪貼簿中的單條或多條宏指令逐條貼上。
    PasteClipboardCommands(ClipboardStr) {
        ClipboardStr := Trim(ClipboardStr, " `t`r`n")
        if (ClipboardStr == "")
            return

        cmds := SplitMacro(ClipboardStr)
        if (cmds.Length == 0)
            return

        anchorID := this.CurItemID
        anchorText := ""
        if (anchorID) {
            try anchorText := this.MacroTreeViewCon.GetText(anchorID)
            catch
                anchorID := 0
        }
        anchorText := StrReplace(anchorText, "→", "")

        ; 無有效錨點（空樹或刪光後）：逐條追加到根層
        if (!anchorID) {
            firstInserted := 0
            for _, cmdStr in cmds {
                cmdStr := Trim(cmdStr, " `t`r`n")
                if (cmdStr == "")
                    continue
                this.OnAddCmd(cmdStr)
                if (!firstInserted && this.CurItemID)
                    firstInserted := this.CurItemID
            }
            if (firstInserted)
                this.MacroTreeViewCon.Modify(firstInserted, "Select")
            return
        }

        ; ⎖ 開頭的是資訊/控制顯示節點（循環次數、繼續/退出條件、流程控制），不允許粘貼。
        if (SubStr(anchorText, 1, 1) == "⎖")
            return

        ; 真/假/循環體/條件 容器節點：粘貼到容器內部（追加到該分支），而非與容器同層級。
        if (this.IsContainerNode(anchorText)) {
            this.PasteIntoContainer(anchorID, cmds)
            return
        }

        ; 單條直接走原本的插入流程。
        if (cmds.Length == 1) {
            this.OnNextInsertCmd(cmds[1])
            return
        }

        parentID := this.MacroTreeViewCon.GetParent(anchorID)

        ; 根層：逐條插入，OnNextInsertCmd 會把 CurItemID 推進到上一條新指令。
        if (parentID == 0) {
            firstInserted := 0
            for _, cmdStr in cmds {
                cmdStr := Trim(cmdStr, " `t`r`n")
                if (cmdStr == "")
                    continue

                insertedID := this.OnNextInsertCmd(cmdStr)
                if (!firstInserted && insertedID)
                    firstInserted := insertedID
            }
            if (firstInserted)
                this.MacroTreeViewCon.Modify(firstInserted, "Select")
            return
        }

        ; 分支內：一次重建該分支宏，避免 RefreshTree 後舊 ItemID 失效。
        branchIndex := this.GetItemNumber(parentID)
        anchorIndex := this.GetItemNumber(anchorID)

        macroStr := this.GetTreeMacroStr(parentID)
        existingCmds := SplitMacro(macroStr)
        if (anchorIndex > existingCmds.Length)
            anchorIndex := existingCmds.Length

        mergedCmds := []
        for i, cmdStr in existingCmds {
            if (i == anchorIndex + 1) {
                for _, pasteCmd in cmds {
                    pasteCmd := Trim(pasteCmd, " `t`r`n")
                    if (pasteCmd != "")
                        mergedCmds.Push(pasteCmd)
                }
            }
            mergedCmds.Push(cmdStr)
        }

        ; 原本錨點在分支末尾時，插入內容要放到最後。
        if (anchorIndex >= existingCmds.Length) {
            for _, pasteCmd in cmds {
                pasteCmd := Trim(pasteCmd, " `t`r`n")
                if (pasteCmd != "")
                    mergedCmds.Push(pasteCmd)
            }
        }

        newMacroStr := ""
        for _, cmdStr in mergedCmds
            newMacroStr .= (newMacroStr == "" ? "" : ",") cmdStr

        realItemID := this.MacroTreeViewCon.GetParent(parentID)
        if (!realItemID)
            return
        realCommandStr := this.MacroTreeViewCon.GetText(realItemID)
        this.SaveCommandData(realCommandStr, newMacroStr, parentID)
        this.RefreshTree(realItemID)

        ; RefreshTree 後重新找回原本的分支節點。
        newParentID := this.GetNthChildItem(realItemID, branchIndex)
        if (!newParentID)
            return

        ; 找到插入區段最後一條，讓後續操作仍停在貼上的內容附近。
        targetIndex := anchorIndex + cmds.Length
        targetID := this.GetNthCommandChild(newParentID, targetIndex)
        if (targetID) {
            this.CurItemID := targetID
            this.MultiSelectAnchor := targetID
            this.MacroTreeViewCon.Modify(targetID, "Select")
        }
    }

    ; 取得 parent 的第 N 個直接子節點（1-based）。
    GetNthChildItem(parentID, wantedIndex) {
        if (!parentID || wantedIndex < 1)
            return 0

        childID := this.MacroTreeViewCon.GetChild(parentID)
        index := 1
        while (childID) {
            if (index == wantedIndex)
                return childID
            index += 1
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        return 0
    }

    ; 取得 branch 下第 N 條真正宏指令，忽略 ⎖ 控制項。
    GetNthCommandChild(parentID, wantedIndex) {
        if (!parentID || wantedIndex < 1)
            return 0

        childID := this.MacroTreeViewCon.GetChild(parentID)
        index := 1
        while (childID) {
            text := this.MacroTreeViewCon.GetText(childID)
            if (text != "" && SubStr(text, 1, 1) != "⎖") {
                if (index == wantedIndex)
                    return childID
                index += 1
            }
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        return 0
    }

    OnSubNodeAddCmd(CommandStr) {
        displayStr := MySoftData.FormatCmdJoyDisplay(CommandStr)
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(displayStr, this.CurItemID, iconStr)
        this.TreeAddBranch(newItemID, CommandStr)
        macroStr := this.GetTreeMacroStr(this.CurItemID)

        RealItemID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, this.CurItemID)
    }

    OnSubNodeEdit(nodeItemID, macroStr) {
        RealItemID := this.MacroTreeViewCon.GetParent(nodeItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        macroStr := macroStr == "" ? " " : macroStr
        this.SaveCommandData(RealCommandStr, macroStr, nodeItemID)
        this.RefreshTree(RealItemID)
    }

    ExpandAll() {
        this.MacroTreeViewCon.Opt("-Redraw")
        rootItemID := this.MacroTreeViewCon.GetNext(0)
        while (rootItemID) {
            this.MacroTreeViewCon.Modify(rootItemID, "Expand")
            this.TreeExpandRecursive(rootItemID)
            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    TreeExpandRecursive(ItemID) {
        childID := this.MacroTreeViewCon.GetChild(ItemID)
        while (childID) {
            this.MacroTreeViewCon.Modify(childID, "Expand")
            this.TreeExpandRecursive(childID)
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
    }

    CollapseAll() {
        this.MacroTreeViewCon.Opt("-Redraw")
        itemID := this.MacroTreeViewCon.GetNext(0)
        while (itemID) {
            this.TreeCollapse(itemID)
            itemID := this.MacroTreeViewCon.GetNext(itemID)
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    TreeCollapse(ItemID) {
        childID := this.MacroTreeViewCon.GetChild(ItemID)
        while (childID) {
            this.TreeCollapse(childID)
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
        if (this.MacroTreeViewCon.GetChild(ItemID))
            this.MacroTreeViewCon.Modify(ItemID, "Collapse")
    }

    GetTreeMacroStr(ItemID) {
        macroStr := ""
        rootItemID := this.MacroTreeViewCon.GetChild(ItemID)
        while (rootItemID) {
            cmdStr := this.MacroTreeViewCon.GetText(rootItemID)
            if (cmdStr != "" && SubStr(cmdStr, 1, 1) != "⎖")
                macroStr .= MySoftData.ParseCmdJoyDisplay(cmdStr) ","

            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
        macroStr := Trim(macroStr, ",")
        return macroStr
    }

    ; ==================== 多選複製 ====================

    SetSingleMultiSelection(itemID) {
        this.ClearMultiSelection()
        if (!itemID)
            return
        this.SetMultiSelected(itemID, true)
        this.MultiSelectAnchor := itemID
    }

    SetMultiSelected(itemID, isSelected) {
        if (!itemID)
            return

        if (isSelected) {
            try this.MacroTreeViewCon.Modify(itemID, "Check")
            catch
                return
            this.MultiSelectItems[itemID] := true
        } else {
            try this.MacroTreeViewCon.Modify(itemID, "-Check")
            this.MultiSelectItems.Delete(itemID)
        }
    }

    ClearMultiSelection() {
        if (!IsObject(this.MultiSelectItems))
            this.MultiSelectItems := Map()
        if (this.MultiSelectItems.Count == 0) {
            this.MultiSelectAnchor := 0
            return
        }

        ; 逐项更新 ✓ 标记（不触发全量渲染）
        for itemID in this.MultiSelectItems {
            try this.MacroTreeViewCon.Modify(itemID, "-Check")
        }
        this.MultiSelectItems.Clear()
        this.MultiSelectAnchor := 0
    }

    ToggleMultiSelection(itemID) {
        if (!itemID)
            return

        ; 多選必須維持在同一層級。
        ; 不同 Parent 的 Ctrl+Click 直接改成單選，避免刪除時 RefreshTree 讓其他 ItemID 失效。
        if (!this.MultiSelectItems.Has(itemID)
            && this.MultiSelectAnchor
            && this.MacroTreeViewCon.GetParent(this.MultiSelectAnchor) != this.MacroTreeViewCon.GetParent(itemID)) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        if (this.MultiSelectItems.Has(itemID))
            this.SetMultiSelected(itemID, false)
        else
            this.SetMultiSelected(itemID, true)
        this.MultiSelectAnchor := itemID
    }

    SelectMultiRange(anchorID, itemID) {
        if (!anchorID || !itemID) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        if (this.MacroTreeViewCon.GetParent(anchorID) != this.MacroTreeViewCon.GetParent(itemID)) {
            this.SetSingleMultiSelection(itemID)
            return
        }

        this.ClearMultiSelection()
        cur := anchorID
        reached := false
        while (cur) {
            this.SetMultiSelected(cur, true)
            if (cur == itemID) {
                reached := true
                break
            }
            cur := this.MacroTreeViewCon.GetNext(cur)
        }

        if (!reached) {
            this.ClearMultiSelection()
            cur := anchorID
            while (cur) {
                this.SetMultiSelected(cur, true)
                if (cur == itemID)
                    break
                cur := this.MacroTreeViewCon.GetPrev(cur)
            }
        }
        this.MultiSelectAnchor := anchorID
    }

    GetMultiSelectedItems() {
        result := []
        this._CollectCheckedItems(0, &result)
        return result
    }

    _CollectCheckedItems(parentID, &result) {
        itemID := parentID == 0 ? this.MacroTreeViewCon.GetNext(0) : this.MacroTreeViewCon.GetChild(parentID)
        while (itemID) {
            if (this.MultiSelectItems.Has(itemID))
                result.Push(itemID)
            this._CollectCheckedItems(itemID, &result)
            itemID := this.MacroTreeViewCon.GetNext(itemID)
        }
    }

    GetCmdIconStr(cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        paramArr[1] := GetCmdStr(paramArr[1])

        textOnly := RegExReplace(paramArr[1], "\d+")
        if (this.CmdIconFileMap.Has(textOnly)) {
            rel := this.CmdIconFileMap[textOnly]
            full := A_WorkingDir "\" rel
            if (FileExist(full))
                return StrReplace(full, "\", "/")
        }
        return ""
    }

    SaveCommandData(RealCommandStr, macroStr, nodeItemID) {
        paramArr := StrSplit(RealCommandStr, "_")
        cmd := RegExReplace(paramArr[1], "\d+")

        ; 映射表：命令 → 文件名
        fileMap := Map(
            GetLang("搜索"), SearchFile,
            GetLang("搜索Pro"), SearchProFile,
            GetLang("抓图"), ScreenShotFile,
            GetLang("如果"), CompareFile,
            GetLang("如果Pro"), CompareProFile,
            GetLang("循环"), LoopFile
        )
        if (!fileMap.Has(cmd))
            return

        ItemNumber := this.GetItemNumber(nodeItemID)
        Data := GetMacroCMDData(paramArr[1])
        macroStr := GetLangMacro(macroStr, 2)
        if (cmd == GetLang("循环")) {
            Data.LoopBody := macroStr
        }
        else if (cmd == GetLang("如果Pro")) {
            if (ItemNumber > Data.VariNameArr.Length) {
                if (macroStr == "")
                    MsgBox("最后的分支不能删除，已清空分支指令")
                Data.DefaultMacro := Trim(macroStr)
            }
            else {
                if (macroStr == "空条件") {
                    Data.MacroArr[ItemNumber] := ""
                }
                else if (macroStr == "") {
                    Data.VariNameArr.RemoveAt(ItemNumber)
                    Data.CompareTypeArr.RemoveAt(ItemNumber)
                    Data.VariableArr.RemoveAt(ItemNumber)
                    Data.LogicTypeArr.RemoveAt(ItemNumber)
                    Data.MacroArr.RemoveAt(ItemNumber)
                }
                else {
                    Data.MacroArr[ItemNumber] := Trim(macroStr)
                }
            }
        }
        else {
            if (ItemNumber == 1)    ;真
                Data.TrueMacro := macroStr
            else
                Data.FalseMacro := macroStr
        }

        SaveMacroCMDData(Data)
    }

    GetItemNumber(nodeItemID) {
        ItemNumber := 1
        PreItemID := this.MacroTreeViewCon.GetPrev(nodeItemID)
        while (PreItemID != 0) {
            ItemNumber += 1
            PreItemID := this.MacroTreeViewCon.GetPrev(PreItemID)
        }
        return ItemNumber
    }

    _OnLButtonDown(wParam, lParam, msg, hwnd) {
        ; P6 才接入 XAML 拖拽；此前 WPF 窗口的 WM_LBUTTONDOWN 全部忽略
        if (!this._dragEnabled)
            return
        if (!this.Gui || !WinActive("ahk_id " this.Gui.Hwnd))
            return

        hwndTV := this.MacroTreeViewCon.Hwnd
        isFromLeft := this.DragSourceMap.Has(hwnd)
        isFromTV := (hwnd == hwndTV)

        if (!isFromLeft && !isFromTV)
            return

        dragInfo := ""
        sourceItem := 0
        CoordMode("Mouse", "Screen")
        MouseGetPos(&startX, &startY)

        if (isFromLeft) {
            dragInfo := this.DragSourceMap[hwnd]
        } else {
            hitFlags := 0
            sourceItem := this.TreeViewHitTest(this.MacroTreeViewCon, startX, startY, &hitFlags)
            if (sourceItem == 0)
                return
            ; 点到展开/折叠按钮：不拦截，交给 TreeView 正常处理
            if (hitFlags & 0x0010)  ; TVHT_ONITEMBUTTON
                return

            itemText := this.MacroTreeViewCon.GetText(sourceItem)
            cleanText := StrReplace(itemText, "→", "")

            ; ⎖ 開頭的是資訊/控制節點，不參與多選。
            ; 真／假／循環體／條件是可選取的容器節點。
            if (SubStr(cleanText, 1, 1) == "⎖")
                return 1

            ; Ctrl+Click / Shift+Click：進入多選模式，不啟動拖曳。
            ; 使用 Check 狀態作為可視化的多選標記。
            if (GetKeyState("Ctrl", "P") || GetKeyState("Shift", "P")) {
                if (GetKeyState("Shift", "P"))
                    this.SelectMultiRange(this.MultiSelectAnchor, sourceItem)
                else
                    this.ToggleMultiSelection(sourceItem)

                this.CurItemID := sourceItem
                this.MacroTreeViewCon.Modify(sourceItem, "Select")
                return 1
            }

            ; 一般單擊：清掉舊多選，只保留目前項目。
            this.SetSingleMultiSelection(sourceItem)
            this.CurItemID := sourceItem
            this.MacroTreeViewCon.Modify(sourceItem, "Select")

            ; 容器可以被選取，但不當成可拖曳的一般指令。
            if (this.IsContainerNode(itemText))
                return 1

            dragInfo := {name: itemText, gui: "", isMove: true, sourceItem: sourceItem}
        }

        dragStarted := false
        lastTargetItem := -1
        lastMode := 0
        plannedMode := 1
        plannedTarget := 0

        actionVerb := dragInfo.isMove ? GetLang("移动") : GetLang("拖动插入")

        while GetKeyState("LButton", "P") {
            MouseGetPos(&curX, &curY, &curWin, &curCtrlHwnd, 2)
            if (!dragStarted) {
                if (Abs(curX - startX) > 8 || Abs(curY - startY) > 8) {
                    dragStarted := true
                    ; 捕捉滑鼠到 TreeView，防止 WM_LBUTTONUP 流向編輯器造成焦點偷換
                    DllCall("SetCapture", "Ptr", hwndTV)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                }
            }
            if (dragStarted) {
                if (curCtrlHwnd == hwndTV) {
                    targetItem := this.TreeViewHitTest(this.MacroTreeViewCon, curX, curY)

                    mode := 1
                    after := 0

                    if (targetItem == 0) {
                        mode := 1
                    } else {
                        itemText := this.MacroTreeViewCon.GetText(targetItem)
                        cleanText := StrReplace(itemText, "→", "")

                        if (SubStr(cleanText, 1, 1) == "⎖" || (dragInfo.isMove && targetItem == dragInfo.sourceItem)) {
                            mode := -1
                        } else if (dragInfo.isMove && this.IsDescendantOrSelf(this.MacroTreeViewCon, dragInfo.sourceItem, targetItem)) {
                            mode := -1
                        } else if (this.IsContainerNode(itemText)) {
                            mode := 5
                        } else {
                            rect := this.GetItemRect(this.MacroTreeViewCon, targetItem)
                            if (rect) {
                                pt := Buffer(8)
                                NumPut("Int", curX, pt, 0)
                                NumPut("Int", curY, pt, 4)
                                DllCall("ScreenToClient", "Ptr", hwndTV, "Ptr", pt)
                                clientY := NumGet(pt, 4, "Int")

                                midY := rect.top + (rect.bottom - rect.top) / 2
                                if (clientY < midY) {
                                    mode := 3
                                    after := 0
                                } else {
                                    mode := 4
                                    after := 1
                                }
                            } else {
                                mode := 4
                                after := 1
                            }
                        }
                    }

                    if (targetItem != lastTargetItem || mode != lastMode) {
                        lastTargetItem := targetItem
                        lastMode := mode

                        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)

                        plannedMode := mode
                        plannedTarget := targetItem

                        if (mode == -1) {
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("提示: 无法移动到此位置"))
                        } else if (mode == 1) {
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 追加到末尾"))
                        } else if (mode == 5) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 内部"))
                        } else if (mode == 3) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 上方"))
                        } else if (mode == 4) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 1, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 下方"))
                        }
                    }
                } else if (curCtrlHwnd == this.MacroEditTextCon.Hwnd) {
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                    lastTargetItem := -1
                    lastMode := 0

                    ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 文本末尾"))
                    plannedMode := 1
                    plannedTarget := 0
                } else {
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                    lastTargetItem := -1
                    lastMode := 0

                    ToolTip(actionVerb ": " dragInfo.name)
                    plannedMode := -1
                }
            }
            Sleep(30)
        }

        ToolTip() ; Clear tooltip
        DllCall("ReleaseCapture")  ; 釋放滑鼠捕捉
        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)

        if (isFromLeft) {
            if (!dragStarted) {
                ; 沒有拖曳：模擬正常按鈕點擊，追加到末尾
                this.OnOpenSubGui(dragInfo.gui, 1)
            } else if (plannedMode != -1) {
                ; 拖曳並在 TreeView 或 Edit 中釋放
                MouseGetPos(&releaseX, &releaseY, &releaseWin, &releaseCtrlHwnd, 2)
                if (releaseCtrlHwnd == hwndTV || releaseCtrlHwnd == this.MacroEditTextCon.Hwnd) {
                    this.CurItemID := plannedTarget
                    if (this.CurItemID != 0) {
                        this.MacroTreeViewCon.Modify(this.CurItemID, "Select")
                    }
                    this.OnOpenSubGui(dragInfo.gui, plannedMode)
                }
                ; TreeView 外釋放：什麼都不做
            }
            ; 攔截原始 WM_LBUTTONDOWN，防止按鈕的 Click 事件重複觸發
            return 1
        } else {
            ; isFromTV：TreeView 內部指令移動；未拖动时已在按下时完成选中
            if (dragStarted && plannedMode != -1) {
                MouseGetPos(&releaseX, &releaseY, &releaseWin, &releaseCtrlHwnd, 2)
                if (releaseCtrlHwnd == hwndTV) {
                    destParent := 0
                    if (plannedMode == 5) {
                        destParent := plannedTarget
                    } else if (plannedMode == 3 || plannedMode == 4) {
                        destParent := this.MacroTreeViewCon.GetParent(plannedTarget)
                    }
                    this.MoveTreeViewItem(dragInfo.sourceItem, destParent, plannedTarget, plannedMode)
                }
            }
            ; 消费消息，避免过期的 WM_LBUTTONDOWN 再交给 TreeView 破坏选中
            return 1
        }
    }

    ; TreeView 多選視覺高亮：被選中的指令整行都會突出顯示。
    _OnNotify(wParam, lParam, msg, hwnd) {
        if (!this.Gui || !this.MacroTreeViewCon || !lParam)
            return

        treeHwnd := this.MacroTreeViewCon.Hwnd
        if (!treeHwnd)
            return

        ; WM_NOTIFY / NMCUSTOMDRAW / NMTVCUSTOMDRAW
        ; 32 位與 64 位結構的對齊方式不同，這裡使用固定的正確欄位偏移。
        if (A_PtrSize == 8) {
            hdrHwndOffset := 0
            codeOffset := 16
            drawStageOffset := 24
            itemSpecOffset := 56
            clrTextOffset := 80
            clrTextBkOffset := 84
        } else {
            hdrHwndOffset := 0
            codeOffset := 8
            drawStageOffset := 12
            itemSpecOffset := 36
            clrTextOffset := 48
            clrTextBkOffset := 52
        }

        hwndFrom := NumGet(lParam, hdrHwndOffset, "Ptr")
        if (hwndFrom != treeHwnd)
            return

        code := NumGet(lParam, codeOffset, "Int")
        if (code != -12) ; NM_CUSTOMDRAW
            return

        drawStage := NumGet(lParam, drawStageOffset, "UInt")

        ; CDDS_PREPAINT：要求下一階段的 ITEMPREPAINT 通知。
        if (drawStage == 0x00000001)
            return 0x00000020 ; CDRF_NOTIFYITEMDRAW

        ; CDDS_ITEMPREPAINT：針對每個 TreeView item 設定顏色。
        if (drawStage != 0x00010001)
            return

        itemID := NumGet(lParam, itemSpecOffset, "Ptr")
        if (!itemID || !this.MultiSelectItems.Has(itemID))
            return

        ; 多選項目：整行高亮，而不是只靠 CheckBox。
        ; 使用亮藍背景 + 白色文字，滑鼠移開後仍保持。
        NumPut("UInt", 0xFFFFFF, lParam, clrTextOffset)
        NumPut("UInt", 0x2D6CDF, lParam, clrTextBkOffset)

        return 0x00000002 ; CDRF_NEWFONT
    }

    TreeViewHitTest(TVCon, mouseX, mouseY, &flags := 0) {
        hwnd := TVCon.Hwnd
        pt := Buffer(8)
        NumPut("Int", mouseX, pt, 0)
        NumPut("Int", mouseY, pt, 4)
        DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt)
        clientX := NumGet(pt, 0, "Int")
        clientY := NumGet(pt, 4, "Int")

        structSize := A_PtrSize == 8 ? 24 : 16
        tvhti := Buffer(structSize, 0)
        NumPut("Int", clientX, tvhti, 0)
        NumPut("Int", clientY, tvhti, 4)

        hItem := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x1111, "Ptr", 0, "Ptr", tvhti, "Ptr")
        flags := NumGet(tvhti, 8, "UInt")
        return hItem
    }

    IsContainerNode(itemText) {
        cleanItemText := StrReplace(itemText, "→", "")
        isCondi := SubStr(cleanItemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        return (
            cleanItemText == GetLang("真")
            || cleanItemText == GetLang("假")
            || cleanItemText == GetLang("循环体")
            || isCondi
        )
    }

    GetItemRect(TVCon, hItem) {
        hwnd := TVCon.Hwnd
        rect := Buffer(16, 0)
        NumPut("UPtr", hItem, rect, 0)
        if DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x1104, "Ptr", 0, "Ptr", rect, "Ptr") {
            return {
                left: NumGet(rect, 0, "Int"),
                top: NumGet(rect, 4, "Int"),
                right: NumGet(rect, 8, "Int"),
                bottom: NumGet(rect, 12, "Int")
            }
        }
        return ""
    }

    MoveTreeViewItem(sourceItem, destParent, relativeToItem, mode) {
        this.ResetDebugState()
        this.ClearMultiSelection()

        sourceText := this.MacroTreeViewCon.GetText(sourceItem)
        sourceIcon := this.GetCmdIconStr(sourceText)
        sourceParent := this.MacroTreeViewCon.GetParent(sourceItem)

        if (mode == 3) {
            prev := this.MacroTreeViewCon.GetPrev(relativeToItem)
            seq := prev == 0 ? "First" : prev
        } else if (mode == 4) {
            seq := relativeToItem
        } else if (mode == 5) {
            seq := "First"
        } else {
            seq := ""
        }

        newItem := this.MacroTreeViewCon.Add(sourceText, destParent, seq " " sourceIcon)
        this.TreeAddBranch(newItem, sourceText)

        this.MacroTreeViewCon.Delete(sourceItem)

        if (sourceParent != 0) {
            macroStrSource := this.GetTreeMacroStr(sourceParent)
            RealSourceItemID := this.MacroTreeViewCon.GetParent(sourceParent)
            RealSourceCommandStr := this.MacroTreeViewCon.GetText(RealSourceItemID)
            this.SaveCommandData(RealSourceCommandStr, macroStrSource, sourceParent)
        }

        if (destParent != 0) {
            macroStrDest := this.GetTreeMacroStr(destParent)
            RealDestItemID := this.MacroTreeViewCon.GetParent(destParent)
            RealDestCommandStr := this.MacroTreeViewCon.GetText(RealDestItemID)
            this.SaveCommandData(RealDestCommandStr, macroStrDest, destParent)
        }

        ; 移动已由 Add + TreeAddBranch + Delete 增量完成，不再 RefreshTree
        if (destParent != 0) {
            child := this.MacroTreeViewCon.GetChild(destParent)
            while (child) {
                if (this.MacroTreeViewCon.GetText(child) == sourceText) {
                    this.MacroTreeViewCon.Modify(child, "Select")
                    break
                }
                child := this.MacroTreeViewCon.GetNext(child)
            }
        } else {
            this.MacroTreeViewCon.Modify(newItem, "Select")
        }

        return newItem
    }

    IsDescendantOrSelf(TVCon, item, potentialParent) {
        if (potentialParent == 0)
            return false
        if (potentialParent == item)
            return true
        parent := TVCon.GetParent(potentialParent)
        while (parent != 0) {
            if (parent == item)
                return true
            parent := TVCon.GetParent(parent)
        }
        return false
    }
}

CreateSubGuiClickHandler(self, guiInstance) {
    clickHandler(*) {
        if (self._dragCancelled) {
            self._dragCancelled := false
            return
        }
        self.OnOpenSubGui(guiInstance)
    }
    return clickHandler
}