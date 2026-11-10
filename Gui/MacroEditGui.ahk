#Requires AutoHotkey v2.0
#Include IntervalGui.ahk
#Include KeyGui.ahk
#Include JoyPickerHook.ahk
#Include JoyGui.ahk
#Include MouseMoveGui.ahk
#Include SearchGui.ahk
#Include SearchProGui.ahk
#Include SearchAllGui.ahk
#Include SearchComboGui.ahk
#Include ScreenShotGui.ahk
#Include RunGui.ahk
#Include RunProGui.ahk
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
#Include JoyCheckGui.ahk
#Include CommentGui.ahk
#Include HttpRequestGui.ahk
#Include FlowJumpGui.ahk
#Include MacroEditModel.ahk

class MacroEditGui {
    ; MacroEditor 下的类内 #Include 共用编辑器实例及树状态。
    static Hotkeys := ["f5", "f6", "delete"]
#Include MacroEditor\DebugShortcuts.ahk

    __new(reuseShared := false) {
        this.ParentTile := ""
        this.ui := ""                     ; XAMLHost 实例
        this._debugToolbar := ""
        this._closed := true
        this._dragEnabled := false        ; 原生 OnMessage 拖拽保持禁用（拖拽由引擎内实现）
        ; 命中测试/坐标换算都要查引擎，而鼠标事件回调本身运行在「引擎发给 AHK 的 send 消息」里，
        ; 在里面同步发 MQUERY 拿不到应答。所以凡是需要查引擎的动作都转伪线程（-1 / -20）。
        this._dblState := ""              ; 双击落下的 state
        this._dblTick := ObjBindMethod(this, "_ApplyTreeDoubleClick")
        this._treeClickCoord := ""
        this._treeDownHit := ""           ; 按下时引擎随事件带回的命中行 Tag
        this._extDragGui := ""            ; 左侧指令拖进树：被拖的 gui 实例
        this._rightClickCoord := ""
        this._rightDownHit := ""          ; 右键按下时引擎带回的命中行 Tag
        this._hkIds := []
        this._topOn := false
        this._title := ""
        this._suppressModeChange := false      ; 构建/初始化时忽略编辑模式 SelectionChanged，避免空树先刷再重载闪烁
        this._revealed := false                ; 已 Opacity=1，防重复 reveal
        this.Gui := ""                         ; 打开时置为 facade（兼容外部 .Gui.Hwnd / .Title / .Hide），关闭时复位为空
        this.GuiMenu := ""
        this.DebugItemID := 0
        this.CurrentItemID := 0
        this.DebugStack := []                  ; 调试步入调用栈（纯瞬态，不落盘、不入快照）
        this._bpStr := ""                      ; 当前断点串缓存（InitTreeView 重建后按此重放标记）
        this.OnBpChanged := ""                 ; 断点写回回调（宿主设置；无持久化宿主时为空）
        ; F3：断点菜单门控。默认 false = 隐藏「断点」右键项（fail-safe，宁可无入口也不要静默丢失）。
        ; 仅当宿主已接线持久化落盘时才置 true：主编辑器（OpenItemMacroTreeEditor）设置；
        ; 侧栏逻辑树的断点菜单独立建在 MainWindowXaml，不受此开关影响。
        this._bpAllowed := false
        this.ShowSaveBtn := false
        this.SureFocusCon := ""
        this.isContextEdit := false
        this.RecordToggleCon := ""
        this.EditModeCon := ""
        this.SubMacroEditGui := ""
        this.SubMacroGraphGui := ""
        this.CompareProEditItemGui := ""
        this.OwnerHwnd := ""
        this.WindowBindingContext := ""
        ; 侧栏宿主：控件名可覆盖；_sideMode 时不建独立窗口，变更经 OnMacroChanged 写回
        this.treeName := "MacroTree"
        this.insertLineName := "DragInsertLine"
        this.dragGhostName := "DragGhost"
        this.dragGhostTxtName := "DragGhostTxt"
        this.ctxMenuName := "TreeCtxMenu"
        this.branchCtxMenuName := "BranchCtxMenu"
        this.blankCtxMenuName := "TreeBlankCtxMenu"
        this.menuEditName := "MenuEditCmd"
        this.menuSkipName := "MenuSkipCmd"
        this.menuDebugName := "MenuDebugCmd"
        this.menuBpName := "MenuBpCmd"
        this.menuCopyName := "MenuCopyCmd"
        this.menuPasteName := "MenuPasteCmd"
        this.menuDeleteName := "MenuDeleteCmd"
        this.menuBranchDeleteName := "MenuBranchDelete"
        this.menuBlankPasteName := "MenuBlankPasteCmd"
        this.menuInsertPrePrefix := "MenuInsertPre_"
        this.menuInsertNextPrefix := "MenuInsertNext_"
        this.menuBlankInsertPrefix := "MenuBlankInsert_"
        this.menuInsertPrefix := "MenuInsert_"  ; 兼容旧绑定
        this.menuBranchAddPrefix := "MenuBranchAdd_"
        this._sideMode := false
        this._sideBound := false
        this.OnMacroChanged := ""
        this._sideActive := true           ; 侧栏实例：当前页签是否前台（热键门控）
        this._pendingSideNotify := false

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
        ; §1 撤销/重做：快照栈（根宏串 + 树上全部命令 Data 深快照）
        this._undoStack := []
        this._redoStack := []
        this._undoBatch := 0             ; >0 时 _PushUndo 静默（内部批量组合操作只记一次）
        ; §13 左侧指令面板：按类型分类 + 收藏星标 + 分类展开状态（持久化到 INI）
        this.CmdCategory := [
            {name: "键鼠/手柄", icon: Chr(0xE765), cmds: ["按键", "手柄", "移动", "移动Pro", "增量移动", "后台按键", "后台鼠标", "按键检测", "手柄检测"]},
            {name: "搜索/识图", icon: Chr(0xE721), cmds: ["搜索", "搜索Pro", "搜索All", "搜索Combo"]},
            {name: "输入/输出", icon: Chr(0xE8A1), cmds: ["输入", "输出"]},
            {name: "变量/数据", icon: Chr(0xE8EF), cmds: ["变量", "变量提取", "运算", "数组", "文本处理"]},
            {name: "文件", icon: Chr(0xE8A5), cmds: ["文件读写", "Excel", "网络请求"]},
            {name: "流程", icon: Chr(0xE8FD), cmds: ["间隔", "等待", "循环", "跳转", "如果", "如果Pro", "倒计时"]},
            {name: "调控", icon: Chr(0xE713), cmds: ["运行", "运行Pro", "宏操作", "窗口信息", "调整窗口", "RMT指令"]},
            {name: "其他", icon: Chr(0xE712), cmds: ["抓图", "注释"]}
        ]
        this._favSet := Map()            ; 收藏指令名（中文）→ true
        this._catExpand := Map()         ; 分类名（中文）→ true（展开）
        this._favOpen := true            ; 收藏分组展开
        this._allExpanded := true        ; 工具栏「缩放」：全部展开 / 全部折叠
        this._ctxFavProp := ""           ; 指令行右键收藏的当前 propName
        this.SubMacroLastIndex := 0
        this.DragSourceMap := Map()
        this._dragCancelledAt := 0     ; 拖拽结束时刻：用它吞掉随后补发的那次 Click
        ; 多選複製：使用 TreeView Check 狀態作為多選標記
        this.MultiSelectItems := Map()
        this.MultiSelectAnchor := 0
        this._lbtnHandler := ObjBindMethod(this, "_OnLButtonDown")
        this._notifyHandler := ObjBindMethod(this, "_OnNotify")

        this.InitCommandConfigs()
        this.InitSubGuiConfigs()
        if (reuseShared && IsSet(MyMacroGui) && IsObject(MyMacroGui) && MyMacroGui != this) {
            this.SubGuiMap := MyMacroGui.SubGuiMap
            for config in this.SubGuiConfig {
                if (ObjHasOwnProp(MyMacroGui, config.propName))
                    this.%config.propName% := MyMacroGui.%config.propName%
            }
        } else
            this.InitSubGui()
        this.SubGuiMap.Set(GetLang("流程跳转"), this.FlowJumpGui)
    }
#Include MacroEditor\CommandCatalog.ahk

    ShowGui(CommandStr, ShowSaveBtn, windowBindingContext := "") {
        global MySoftData
        this._revealed := false
        ; XAML 窗口不支持隐藏复用：已打开的实例先关掉再重建
        if (IsObject(this.ui) && !this._closed)
            this._CloseWindow()
        this.WindowBindingContext := windowBindingContext
        ; 主题/快捷键同款：内容在 _BuildAndShow 里 Show 前填充（入队），LoadedHwnd 时一次刷入
        this._BuildAndShow(CommandStr, ShowSaveBtn)

        ; 注册快捷键热键（仅编辑器前台时拦截，失焦时按键透传给其他程序；关闭时注销）
        this._hkIds := WinHotkey.Register([this._GetContinueHotkey(), this._GetStepOverHotkey(), this._GetStepIntoHotkey(), this._GetStepOutHotkey(), this._GetRunToCursorHotkey(), "$" this._GetToggleSkipHotkey(), this._GetRunAllHotkey(), "Delete", "$^c", "$^v", "$^z", "$^y"], ObjBindMethod(this, "_OnHotkey"), this.Hwnd())

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
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }
#Include MacroEditor\SidePanel.ahk
#Include MacroEditor\CommandMenus.ahk
#Include MacroEditor\CommandPalette.ahk
#Include MacroEditor\WindowLayout.ahk

    OnWindowLoad(state, ctrl, event) {
        try {
            try {
                hIcon := LoadPicture("Images\Soft\rabit.ico", "Icon1", &ImageType := 1)
                if (hIcon)
                    this.ui.Update("Window", "Icon", "HICON:" hIcon)
            }
            XamlWin.OnLoadTheme(this.ui)
            this._SyncModeSeg(IsObject(this.EditModeCon) ? this.EditModeCon.Value : 1)
            this._SyncToolToggleDots()
        } catch {
        }
        this._TryReveal("theme")
    }

    ; §8 帮助按钮：打开指令手册（后续可精确跳转到对应指令章节）
    OnCmdHelpClick(state, ctrl, event) {
        OnOpenRmtDoc("#指令手册")
    }

    ; §8 视频按钮：占位（指令详细介绍视频制作中）
    OnCmdVideoClick(state, ctrl, event) {
        MyMsgBoxContent(GetLang("指令介绍视频制作中，敬请期待。"))
    }

    ; 拿一次焦点（防重复）：窗口创建时就是最终样子，这里只负责切到前台
    _TryReveal(from := "") {
        if (this._revealed || this._closed)
            return
        if (!IsObject(this.ui) || !this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd)
            return
        this._revealed := true
        try WinActivate("ahk_id " this.ui.wpfHwnd)
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
        this._DragEndReset()
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
        ToolTip()
        if (IsObject(this._debugToolbar))
            this._debugToolbar.Hide()
        this._debugToolbar := ""
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
        if (IsObject(this._debugToolbar))
            this._debugToolbar.Hide()
        this._DragEndReset()
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
        if (IsObject(this.MacroTreeViewCon))
            this.MacroTreeViewCon._suppressRender := false
        ; V4：调试进行中关窗 = 终止调试。只清 hook.active 不够——ContinueRun/StepOut 的
        ; 同步循环仍在逐条真实执行指令（键鼠仍在动）。Kill 停真实执行 + 复位全部调试态。
        KillSingleTableMacro(MySoftData.SpecialTableItem)
        this.ResetDebugState()
        ; 关窗时清全局调试钩子 active 标志：DebugHook 是全局对象、不随窗口销毁清零；
        ; 若在 DoDebugStep 激活(active:=true) 与复位之间进程被杀/异常退出，会残留 active=true →
        ; 之后真实触发宏时 TryInterceptDebugBranch 误拦截、静默跳过分支体。_CloseDebugHook 仅清标志，安全。
        this._CloseDebugHook()
        ToolTip()
        this._debugToolbar := ""
        this.ui := ""
        this.Gui := ""
    }

    _HideWindow() {
        if (IsObject(this._debugToolbar))
            this._debugToolbar.Hide()
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
        this._SyncToolToggleDots()
    }

    Init(MacroStr, ShowSaveBtn) {
        MacroStr := GetLangMacro(MacroStr, 1)
        this.ShowSaveBtn := ShowSaveBtn
        this.SubMacroLastIndex := 0
        ; 打开新宏：清空上一份宏的撤销/重做栈
        this._undoStack := []
        this._redoStack := []
        this._undoBatch := 0
        this.SaveBtnCtrl.Visible := false
        this.InitTreeView(MacroStr)
        this.InitMacroText(MacroStr)

        this.ClearMultiSelection()
        this.CurItemID := 0
        this.MacroTreeViewCon.Focus()
        if (IsObject(this.MacroTreeViewCon) && this.MacroTreeViewCon.HasMethod("Unselect"))
            this.MacroTreeViewCon.Unselect()
    }

    _LastRootItem() {
        last := 0
        if (!IsObject(this.MacroTreeViewCon))
            return 0
        cur := this.MacroTreeViewCon.GetNext(0)
        while (cur) {
            last := cur
            cur := this.MacroTreeViewCon.GetNext(cur)
        }
        return last
    }

    Backspace() {
        if (this.EditModeCon.Value == 1) {
            last := this._LastRootItem()
            if (!last)
                return
            this._PushUndo()
            this.ResetDebugState()
            this.CurItemID := last
            this._DeleteSingleCmd(last)
            this.LastItemID := this._LastRootItem()
            this.ClearMultiSelection()
            this._NotifyMacroChanged()
            return
        }
        this._PushUndo()
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

    ClearStr() {
        this._PushUndo()
        this.MacroTreeViewCon.Delete()
        this.MacroEditTextCon.Value := ""
        ; T4：清空全部命令后树上已无任何标记 → 重采集(得 "") 剪掉所有残留断点签名
        if (this._bpAllowed)
            this._NotifyBpChanged()
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
            if (IsObject(this._debugToolbar))
                this._debugToolbar.Hide()
            this.ResetDebugState()                  ; V6：树已隐藏，悬挂的调试态会继续驱动不可见树 → 切换即终止调试
            this.InitMacroText(MacroStr)
        }
        this.ui.Update("BtnDebugToolbar", "IsEnabled", this.EditModeCon.Value == 1 ? "True" : "False")
        this._SyncModeSeg(this.EditModeCon.Value)
    }

    OnClickRecordTog(*) {
        UIControls.RecordToggle := this.RecordMacroCon
        MainSoftData.MacroEditGui := this
        OnClickToolRecordMacro(true)
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
        MyMacroGraphGui.ShowGui(macroStr, this.WindowBindingContext)
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
        ; SureFocusCon 可能是原生控件 / XAML facade / 轻量对象，也可能是 ""
        ; （宿主未提供，如 CompareProGui 传空）→ 必须先判对象，否则 "".Focus() 直接抛错
        if (IsObject(this.SureFocusCon))
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
        ; SureFocusCon 可能是原生控件 / XAML facade / 轻量对象，也可能是 ""
        ; （宿主未提供，如 CompareProGui 传空）→ 必须先判对象，否则 "".Focus() 直接抛错
        if (IsObject(this.SureFocusCon))
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
#Include MacroEditor\UndoHistory.ahk
#Include MacroEditor\TreeEvents.ahk
#Include MacroEditor\TreeMenuActions.ahk
#Include MacroEditor\Debugger.ahk
#Include MacroEditor\TreeRendering.ahk
#Include MacroEditor\CommandDialogs.ahk
#Include MacroEditor\TreeEditing.ahk
#Include MacroEditor\TreeSelection.ahk
#Include MacroEditor\CommandStorage.ahk
#Include MacroEditor\TreeDrag.ahk
}
#Include MacroEditor\DebugToolbar.ahk
#Include MacroEditor\SidePanelAdapters.ahk
