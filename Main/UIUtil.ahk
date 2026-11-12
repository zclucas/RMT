; 全局 UI 控件容器（存放需要外部程序化更新的 GUI 控件对象）
; 这些控件不在 MainSoftData/SoftData 中存储，仅在 UI 层访问
global UIControls := {
    SuspendToggle: "",
    PauseToggle: "",
    CMDTip: "",
    RecordToggle: "",
    ToolCheck: "",
    ToolCheckRecord: "",
    AlwaysOnTop: "",
    ToolText: "",
    OCRType: ""
}

; 设置工具页文本显示内容（Master 有 GUI，Worker 无操作）
SetToolTextDisplay(text) {
    if (UIControls.ToolText)
        UIControls.ToolText.Value := text
}

; 编译包显示架构后缀；.ahk 调试运行不带 x64/x86
global RMT_VERSION_DISPLAY := A_IsCompiled
    ? (RMT_VERSION "_" (A_PtrSize = 8 ? "x64" : "x86"))
    : RMT_VERSION

; 主窗句柄就绪等待：回调队列 + 截止时间 + 定时器开关（见 WaitMainWinReady）
global RmtWinReadyCbs := []
global RmtWinReadyDeadline := 0
global RmtWinReadyTimerOn := false

; 主窗句柄由引擎异步回传（Window.LoadedHwnd），这里用定时器轮询等它，主线程不阻塞。
; 多个回调按注册顺序在同一轮触发，先注册的 UI 收尾一定排在后面的启动命令之前。
; 超时仍未拿到句柄时照样回调，避免引擎异常导致启动链永久挂起（与旧行为一致）。
WaitMainWinReady(cb, timeoutMs := 30000) {
    global RmtWinReadyCbs, RmtWinReadyDeadline, RmtWinReadyTimerOn
    if (MainWinHwndReady()) {
        cb()
        return
    }
    RmtWinReadyCbs.Push(cb)
    if (RmtWinReadyTimerOn)
        return
    RmtWinReadyTimerOn := true
    RmtWinReadyDeadline := A_TickCount + timeoutMs
    SetTimer(MainWinReadyTick, 25)
}

MainWinHwndReady() {
    global MyMainWin
    ; 与项目其它处一致用真值判断：句柄未回传时是 0，不是空串
    return IsObject(MyMainWin) && IsObject(MyMainWin.ui)
        && MyMainWin.ui.HasProp("wpfHwnd") && MyMainWin.ui.wpfHwnd
}

MainWinReadyTick() {
    global RmtWinReadyCbs, RmtWinReadyDeadline, RmtWinReadyTimerOn, MyMainWin
    ready := MainWinHwndReady()
    if (!ready && A_TickCount <= RmtWinReadyDeadline)
        return
    SetTimer(MainWinReadyTick, 0)
    RmtWinReadyTimerOn := false
    msg := ready ? ("MainWin hwnd=" MyMainWin.ui.wpfHwnd) : "MainWin hwnd timeout，仍继续 UI 收尾"
    try XamlUiDiag(msg, "MainWin")
    ; 揭盖走引擎的 LoadedHwnd 回调 + InitialUpdateComplete。句柄已到说明该回调已入队，
    ; 先让出一轮消息处理把它放行，再做适配器/OnOpen 这些长任务，否则窗口要多等它们跑完才可见。
    Sleep(-1)
    cbs := RmtWinReadyCbs
    RmtWinReadyCbs := []
    for fn in cbs
        try fn()
}

;窗口&UI刷新
InitUI() {
    global MySoftData
    ; 首次启动：先同意免责声明，再显示主界面
    if (!MainSoftData.AgreeAgreement) {
        if (!AgreementGui.ShowAndWait())
            ExitApp()
        MainSoftData.AgreeAgreement := true
        CfgWrite(true, SettingFile, SettingSection, "AgreeAgreement")
    }

    ; 建窗走引擎异步通道，Show() 立即返回、这里不再 Sleep 轮询句柄。
    ; 适配器/托盘菜单/首屏刷新都依赖句柄，交给 WaitMainWinReady 在句柄回传后执行；
    ; 主线程先回落到启动链，把 PluginInit、热键绑定这类不依赖界面的活并进引擎建窗期间。
    MyMainWin.BuildAndShow()
    WaitMainWinReady(InitUIFinishUI)
}

; 主窗句柄就绪后的 UI 收尾。必须跑在句柄回传之后，
; 否则适配器按名字取控件会全部落空，随后的保存/切页都会失效。
InitUIFinishUI() {
    MainSoftData.MyGui := GuiAdapter(MyMainWin.ui)
    MainSoftData.MyGui.Title := "RMTv" RMT_VERSION_DISPLAY
    MainSoftData.TabCtrl := TabAdapter(MyMainWin.ui, MyMainWin)
    MainSoftData.TabCtrl._value := MainSoftData.TableIndex
    MainSoftData.BtnSave := CtrlAdapter("BtnSave", MyMainWin.ui, "Text")

    MyTriggerKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MainSoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyUIMacroSettingGui.SureFocusCon := MainSoftData.BtnSave

    CustomTrayMenu()
    OnOpen()
}

OnOpen() {
    global MySoftData
    if (MainSoftData.IsMinStart) {
        MainSoftData.IsMinStart := false
        MainSoftData.MyGui.Hide()
        return
    }

    CfgWrite(false, SettingFile, SettingSection, "IsReload")
    if (MainSoftData.LastShowMonth != A_Mon) {
        MainSoftData.TabCtrl.Value := 9
        MainSoftData.LastShowMonth := A_Mon
        CfgWrite(MainSoftData.LastShowMonth, SettingFile, SettingSection, "LastShowMonth")
    }
    ; 首次打开不 WinMove/WinShow：主窗口 Opacity=0，内容填完再揭盖；再 Move 会抖一下
    RefreshListenVarGui()
}

; 主窗口关闭时清理所有鼠标热键订阅
OnGuiClose(*) {
    WinHotkey.UnsubscribeAllMouse()
    MyCMDTipGui._wheelCb := ""
    MyFreePasteGui._wheelCb := ""
    MyTargetGui._lbuttonCb := ""
}

; 统一主窗口默认尺寸（物理像素），与 1400×787 设计比例一致。
GetMainWindowDefaultSize() {
    scale := Min(A_ScreenWidth / 1920, A_ScreenHeight / 1080)
    return [Round(1400 * scale), Round(787 * scale)]
}

; 读取保存的主窗口位置尺寸；旧格式只有坐标，使用新版默认居中尺寸。
; BuildAndShow 可见前置位 + RefreshGui 都复用，避免两处解析漂移
GetLastWinPos() {
    LastWinPosStr := CfgRead(SettingFile, SettingSection, "LastWinPos", "")
    WinPosArr := StrSplit(LastWinPosStr, "π")
    if (WinPosArr.Length != 4)
        return []
    if (WinPosArr.Length >= 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        if (WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth && WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight) {
            ; 新格式 xπyπSπ缩放系数：尺寸 = 1400×787 基准 × 当前屏幕 fs × 系数（物理像素）
            ; 跨分辨率（4K→1080p 等）时窗口比例不变，不会因保存的绝对尺寸而巨大化
            if (WinPosArr.Length >= 4 && WinPosArr[3] == "S" && IsNumber(WinPosArr[4])) {
                dpi := DllCall("GetDpiForSystem", "UInt") / 96.0
                dipSW := A_ScreenWidth / dpi
                dipSH := A_ScreenHeight / dpi
                fs := Min(dipSW / 1920, dipSH / 1080)
                scale := Float(WinPosArr[4])
                if (scale <= 0 || scale > 3)
                    return []
                w := Min(Round(1400 * fs * scale * dpi), VirtualWidth)
                h := Min(Round(787 * fs * scale * dpi), VirtualHeight)
                if (w < 400 || h < 300)
                    return []
                return [WinPosArr[1], WinPosArr[2], w, h]
            }
            ; 旧四段绝对尺寸只在宽高都有效时恢复，不能混用旧尺寸与新默认值。
            if (!IsNumber(WinPosArr[3]) || !IsNumber(WinPosArr[4]) || WinPosArr[3] < 400 || WinPosArr[4] < 300)
                return []
            w := Min(WinPosArr[3], VirtualWidth)
            h := Min(WinPosArr[4], VirtualHeight)
            return [WinPosArr[1], WinPosArr[2], w, h]
        }
    }
    return []
}

RefreshGui() {
    CfgWrite(false, SettingFile, SettingSection, "IsReload")

    pos := GetLastWinPos()
    if (pos.Length) {
        MainSoftData.MyGui.Show(Format("x{} y{} w{} h{}", pos[1], pos[2], pos[3], pos[4]))
        RefreshListenVarGui()
        return
    }

    if (MainSoftData.LastShowMonth != A_Mon) {
        MainSoftData.TabCtrl.Value := 9
        MainSoftData.LastShowMonth := A_Mon
        CfgWrite(MainSoftData.LastShowMonth, SettingFile, SettingSection, "LastShowMonth")
    }

    size := GetMainWindowDefaultSize()
    MainSoftData.MyGui.Show(Format("w{} h{}", size[1], size[2]))
    RefreshListenVarGui()
}

RefreshListenVarGui(isForce := false) {
    IsOenListVar := CfgRead(SettingFile, SettingSection, "IsOpenListenVar", false)
    if (!isForce && !IsOenListVar)
        return

    LastPosStr := CfgRead(SettingFile, SettingSection, "ListenVarPos", "")
    WinPosArr := StrSplit(LastPosStr, "π")
    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MyVarListenGui.ShowGui(WinPosArr[1], WinPosArr[2])
            return
        }
    }

    MyVarListenGui.ShowGui()
}

RefreshToolUI() {
    global MainSoftData
    ; XAML 版：Tool*Ctrl 由异步 BuildToolTab 赋值（_PopulateAsync），窗口显示瞬间鼠标移动
    ; 可能先触发本函数（BindUtil 鼠标钩子），控件未赋值时直接跳过，避免对不存在属性赋值抛错
    if (!MainSoftData.HasProp("ToolMousePosCtrl") || !IsObject(MainSoftData.ToolMousePosCtrl))
        return
    ; 100ms 一次整块刷新，合并下发，避免逐条同步跨进程往返。
    CtrlAdapter.RefreshAll([
        [MainSoftData.ToolMousePosCtrl, MainSoftData.PosStr],
        [MainSoftData.ToolProcessNameCtrl, MainSoftData.ProcessName],
        [MainSoftData.ToolProcessTileCtrl, MainSoftData.ProcessTile],
        [MainSoftData.ToolProcessPidCtrl, MainSoftData.ProcessPid],
        [MainSoftData.ToolProcessClassCtrl, MainSoftData.ProcessClass],
        [MainSoftData.ToolProcessIdCtrl, MainSoftData.ProcessId],
        [MainSoftData.ToolWinOriginCtrl, MainSoftData.WinOriginStr],
        [MainSoftData.ToolWinSizeCtrl, MainSoftData.WinSizeStr],
        [MainSoftData.ToolColorCtrl, MainSoftData.Color],
        [MainSoftData.ToolMouseWinPosCtrl, MainSoftData.WinPosStr]
    ])
}

; 编辑快捷键：确认选择后再同步到 MainSoftData（以及显示控件）
OnEditHotkeyAndSync(showCon, keyCon, OnlyTriggerKey, fieldName, *) {
    SyncAfterSure(val) {
        MainSoftData.%fieldName% := val
        try showCon.Value := val
        try keyCon.Value := val
    }
    MyEditHotkeyGui.AfterSureAction := SyncAfterSure
    OnOpenEditHotkeyGui(showCon, keyCon, OnlyTriggerKey)
}

; 设置页数值编辑：输入过程中允许空/非法字符，仅在合法整数时写回
OnSettingIntEditChange(fieldName, ctrl, *) {
    v := Trim(ctrl.Value)
    if (v != "" && IsInteger(v))
        MainSoftData.%fieldName% := Integer(v)
}

; 系统托盘优化
CustomTrayMenu() {
    loop 30 {
        if (WinExist("ahk_class Shell_TrayWnd")) {
            break
        }
        Sleep(1000)
    }
    tipStr := MainSoftData.MyGui.Title
    if (IsProcessElevated())
        tipStr .= "`n" GetLang("管理员权限")

    ; 先整表清空：AHK 默认会加「打开 / 帮助 / Window Spy / 重新加载脚本 / 编辑脚本 / 退出」，
    ; 这些对用户没意义（编译版里名字还是英文），下面只放软件自己的项。
    try A_TrayMenu.Delete()
    A_TrayMenu.Add(GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Add(GetLang("日志中心"), (*) => LogCenterGui.ShowGui())
    A_TrayMenu.Add()
    A_TrayMenu.Add(GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Add(GetLang("开始录制"), (*) => OnTrayStartRecord())
    A_TrayMenu.Add(GetLang("结束录制"), (*) => OnTrayEndRecord())
    A_TrayMenu.Add()
    ; 退出走 ExitApp，OnExitSoft 里的保存与清理照常执行
    A_TrayMenu.Add(GetLang("退出"), (*) => ExitApp())
    if (MainSoftData.IsSuspend)
        try A_TrayMenu.Check(GetLang("休眠"))
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    A_IconTip := tipStr  ; 鼠标悬停时显示此内容
    A_IconHidden := 0   ;0(可见) 和 1(隐藏)
    UpdateMacroTrayIcon()
}

; 休眠优先；任一宏运行时显示运行图标，全部结束/暂停后恢复默认图标。
UpdateMacroTrayIcon() {
    icon := MainSoftData.IsSuspend ? "IcoPause.ico"
        : (MySoftData.IsMacroWorking ? "IcoRunning.ico" : "rabit.ico")
    TraySetIcon("Images\Soft\" icon, , true)
}

OnTrayStartRecord(*) {
    if (RI_isActive || (IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")))
        return
    UIControls.ToolCheckRecord.Value := true
    OnToolRecordMacro(false)
}

OnTrayEndRecord(*) {
    if (!RI_isActive && !(IsSet(CD_canceled) && !CD_canceled && (IsSet(RecordCountdownGui) && RecordCountdownGui != "")))
        return
    UIControls.ToolCheckRecord.Value := false
    OnForceEndRecord()
}

; 帮助文档：程序目录根下的 index.html（SingleHtml 打成的单文件）。旧版 Web\index.html 仅作兜底。
GetHelpDocPath() {
    p := A_WorkingDir "\index.html"
    if (FileExist(p))
        return p
    return A_WorkingDir "\Web\index.html"
}

; 标题栏执行钮提示：Alt + L：执行
CmdEditorPlayTip(hotkey := "!l") {
    disp := FormatHotkeyDisplay(hotkey)
    if (disp == "")
        disp := hotkey
    disp := StrReplace(disp, "+", " + ")
    act := GetLang("执行")
    if (act == "")
        act := "执行"
    return disp "：" act
}

; 指令编辑器标题栏：手册跳转对应章节，视频暂为占位提示
; playAction 非空时显示执行钮；targeterAction 显示定位取色器；f1Action 显示 F1 定位
; 标题栏动作不需要 XAML Click 传入的 state、控件名和事件名，统一无参调用。
BindCmdEditorChrome(ui, helpRoute := "", playAction := "", playHotkey := "!l", targeterAction := "", f1Action := "", f2Action := "", f3Action := "") {
    if (!IsObject(ui))
        return
    hash := "#指令手册"
    helpRoute := Trim(helpRoute)
    if (helpRoute != "")
        hash := (SubStr(helpRoute, 1, 1) == "#") ? helpRoute : "#" helpRoute
    ui.OnEvent("BtnCmdHelp", "Click", (*) => OnOpenRmtDoc(hash))
    ui.OnEvent("BtnCmdVideo", "Click", (*) => ShowCmdVideoNotice(ui))
    if (playAction != "") {
        try ui.Update("BtnCmdPlay", "Visibility", "Visible")
        disp := CmdEditorPlayTip(playHotkey)
        try ui.Update("BtnCmdPlay", "ToolTip", disp)
        ui.OnEvent("BtnCmdPlay", "Click", (*) => playAction())
    }
    if (targeterAction != "") {
        try ui.Update("BtnCmdTargeter", "Visibility", "Visible")
        try ui.Update("BtnCmdTargeter", "ToolTip", GetLang("定位取色器"))
        ui.OnEvent("BtnCmdTargeter", "Click", (*) => targeterAction())
    }
    if (f1Action != "") {
        try ui.Update("BtnCmdF1", "Visibility", "Visible")
        f1Tip := GetLang("F1:选取当前坐标")
        f1Tip := StrReplace(f1Tip, "F1:", "F1：")
        try ui.Update("BtnCmdF1", "ToolTip", f1Tip)
        ui.OnEvent("BtnCmdF1", "Click", (*) => f1Action())
    }
    if (f2Action != "") {
        try ui.Update("BtnCmdF2", "Visibility", "Visible")
        try ui.Update("BtnCmdF2", "ToolTip", GetLang("F2：截图"))
        ui.OnEvent("BtnCmdF2", "Click", (*) => f2Action())
    }
    if (f3Action != "") {
        try ui.Update("BtnCmdF3", "Visibility", "Visible")
        try ui.Update("BtnCmdF3", "ToolTip", GetLang("F3：选取当前颜色"))
        ui.OnEvent("BtnCmdF3", "Click", (*) => f3Action())
    }
}

ShowCmdVideoNotice(ui) {
    if (IsObject(ui) && ui.wpfHwnd)
        RmtDialog.Info(GetLang("指令介绍视频制作中，敬请期待。"), , ui.wpfHwnd)
}

; 标题去掉「编辑器」后缀：宏指令-移动编辑器 → 宏指令-移动
CmdEditorDisplayTitle(title) {
    s := String(title)
    try s := StrReplace(s, GetLang("编辑器"), "")
    s := StrReplace(s, "编辑器", "")
    return Trim(s)
}

; 按窗口标题匹配指令图标（优先用指令配置，长名字先命中）
CmdEditorTitleIcon(title) {
    t := String(title)
    if (InStr(t, "宏指令编辑器"))
        return ""
    best := "", bestLen := 0
    try {
        if (IsSet(MyMacroGui) && IsObject(MyMacroGui) && MyMacroGui.HasProp("SubGuiConfig")) {
            for config in MyMacroGui.SubGuiConfig {
                cand := [config.name]
                try cand.Push(GetLang(config.name))
                try cand.Push(GetLang(config.name "编辑器"))
                for k in cand {
                    if (k != "" && InStr(t, k) && StrLen(k) > bestLen) {
                        best := config.icon
                        bestLen := StrLen(k)
                    }
                }
            }
        }
    }
    if (best != "")
        return best
    static pairs := ""
    if (!IsObject(pairs)) {
        pairs := [
            ["移动Pro", "Images\Soft\MovePro.png"],
            ["搜索Pro", "Images\Soft\SearchPro.png"],
            ["搜索All", "Images\Soft\SearchAll.png"],
            ["搜索Combo", "Images\Soft\SearchCombo.png"],
            ["组合搜索", "Images\Soft\SearchCombo.png"],
            ["搜索Multi", "Images\Soft\SearchCombo.png"],
            ["如果Pro", "Images\Soft\IfPro.png"],
            ["变量提取", "Images\Soft\Extract.png"],
            ["提取文本", "Images\Soft\Extract.png"],
            ["文本处理", "Images\Soft\TextOps.png"],
            ["网络请求", "Images\Soft\HttpRequest.png"],
            ["文件读写", "Images\Soft\FileIO.png"],
            ["Excel", "Images\Soft\Excel.png"],
            ["窗口管理", "Images\Soft\WindowManage.png"],
            ["窗口信息", "Images\Soft\WindowManage.png"],
            ["调整窗口", "Images\Soft\WindowAdjustGear32.png"],
            ["按键检测", "Images\Soft\KeyListen.png"],
            ["手柄检测", "Images\Soft\JoyListen.png"],
            ["后台鼠标", "Images\Soft\Mouse.png"],
            ["后台按键", "Images\Soft\BGKey.png"],
            ["增量移动", "Images\Soft\DeltaMove.png"],
            ["移动", "Images\Soft\Move.png"],
            ["RMT指令", "Images\Soft\rabit.png"],
            ["跳转", "Images\Soft\FlowJump.png"],
            ["宏操作", "Images\Soft\MacroAction.png"],
            ["间隔", "Images\Soft\Time.png"],
            ["按键", "Images\Soft\Key.png"],
            ["手柄", "Images\Soft\Joy.png"],
            ["搜索", "Images\Soft\Search.png"],
            ["输入", "Images\Soft\Input.png"],
            ["输出", "Images\Soft\Output.png"],
            ["循环", "Images\Soft\Loop.png"],
            ["变量", "Images\Soft\Var.png"],
            ["如果", "Images\Soft\If.png"],
            ["运算", "Images\Soft\Operation.png"],
            ["运行Pro", "Images\Soft\RunPro.png"],
            ["运行", "Images\Soft\Run.png"],
            ["数组", "Images\Soft\Arr.png"],
            ["等待确定", "Images\Soft\WaitConfirm.png"],
            ["等待", "Images\Soft\Wait.png"],
            ["时间", "Images\Soft\Time.png"],
            ["倒计时", "Images\Soft\Time.png"],
            ["提示", "Images\Soft\Prompt.png"],
            ["注释", "Images\Soft\Comment.png"],
            ["抓图", "Images\Soft\ScreenShot.png"]
        ]
    }
    for p in pairs {
        if (InStr(t, p[1]))
            return p[2]
    }
    return ""
}

; 指令编辑器确定按钮：与间隔编辑器同款
AddCmdOkBtn(parent, name := "BtnOk", extraMargin := "", content := "") {
    btn := parent.Add("Button").Name(name).Content(content != "" ? content : GetLang("确定")).Width(88).Height(32).MinHeight(32).Cursor("Hand")
        .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
        .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
    if (extraMargin != "")
        btn.Margin(extraMargin)
    btn.InjectResources(FrontInfoGui._OkBtnHoverStyle())
    return btn
}

class ScreenAreaPreview {
    static ButtonStyle() {
        return '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">'
            . '<Border x:Name="surface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" SnapsToDevicePixels="True">'
            . '<Grid><Border x:Name="hoverTint" Background="{DynamicResource Accent}" Opacity="0.16" CornerRadius="2" Visibility="Collapsed" IsHitTestVisible="False"/>'
            . '<ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/></Grid></Border>'
            . '<ControlTemplate.Triggers>'
            . '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="surface" Property="Background" Value="{DynamicResource EditHoverBg}"/></Trigger>'
            . '<Trigger Property="Tag" Value="1"><Setter TargetName="surface" Property="Background" Value="{DynamicResource EditHoverBg}"/><Setter TargetName="surface" Property="BorderBrush" Value="{DynamicResource EditHoverStroke}"/></Trigger>'
            . '<MultiTrigger><MultiTrigger.Conditions><Condition Property="Tag" Value="1"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>'
            . '<Setter TargetName="hoverTint" Property="Visibility" Value="Visible"/></MultiTrigger>'
            . '</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }

    ; 顺序与 _Draw 中的上、下、左、右、左上、右上、左下、右下相同。
    static Grips := [[0, -1, 32645], [0, 1, 32645], [-1, 0, 32644], [1, 0, 32644],
        [-1, -1, 32642], [1, -1, 32643], [-1, 1, 32643], [1, 1, 32642]]

    __New(minSize := 1) {
        this.MinSize := minSize
        this.Windows := []
        this.GripByHwnd := Map()
        this.Rect := []
        this.Drag := ""
        this.Apply := ""
        this.TargetHwnd := 0
        this.MouseDown := ""
        this.SetCursor := ""
    }

    Show(x, y, w, h, apply, targetHwnd := 0, context := "") {
        wasCritical := A_IsCritical
        Critical("On")
        try {
            rect := [Round(x), Round(y), Max(Round(x) + 1, Round(x + w)), Max(Round(y) + 1, Round(y + h))]
            if (this.IsDragging()) {
                if (targetHwnd == this.TargetHwnd && context == this.Context && this._SameRect(rect, this.Drag.StartRect))
                    return
                this._StopDrag()
            }
            this.Apply := apply
            this.TargetHwnd := targetHwnd
            this.Context := context
            this._Draw(rect)
        } finally {
            Critical(wasCritical)
        }
    }

    Hide() {
        ; 创建边框时 Gui.Show 可以派发新事件，显隐过程不能相互打断。
        wasCritical := A_IsCritical
        Critical("On")
        try {
            this._StopDrag()
            if (IsObject(this.MouseDown))
                OnMessage(0x0201, this.MouseDown, 0) ; WM_LBUTTONDOWN
            if (IsObject(this.SetCursor))
                OnMessage(0x0020, this.SetCursor, 0) ; WM_SETCURSOR
            this.MouseDown := "", this.SetCursor := ""
            for g in this.Windows
                g.Destroy()
            this.Windows := []
            this.GripByHwnd.Clear()
            this.Rect := []
            this.Apply := ""
            this.TargetHwnd := 0
        } finally {
            Critical(wasCritical)
        }
    }

    IsDragging() {
        return IsObject(this.Drag)
    }

    FindTargetWindow(info) {
        matches := GetHwndList(info)
        if (!matches.Length)
            return 0
        hwnd := matches[1]
        ; 跟随鼠标所在窗口时，悬停在预览边框上仍使用原窗口。
        return this.GripByHwnd.Has(hwnd) ? this.TargetHwnd : hwnd
    }

    _SameRect(a, b) {
        return b.Length && a[1] == b[1] && a[2] == b[2] && a[3] == b[3] && a[4] == b[4]
    }

    _Draw(rect) {
        if (this._SameRect(rect, this.Rect))
            return
        this.Rect := rect
        left := rect[1], top := rect[2], right := rect[3], bottom := rect[4]
        width := right - left, height := bottom - top
        gripW := Max(2, Min(10, (width - 1) // 2)), gripH := Max(2, Min(10, (height - 1) // 2))
        ; 极小范围的角向外延伸，仍给每条边留下可拖动的区域。
        cornerLeft := Min(left, right - 2 * gripW - 1), cornerTop := Min(top, bottom - 2 * gripH - 1)
        cornerRight := right - gripW, cornerBottom := bottom - gripH
        midLeft := cornerLeft + gripW, midTop := cornerTop + gripH
        midW := cornerRight - midLeft, midH := cornerBottom - midTop
        edgeW := Min(gripW, 5), edgeH := Min(gripH, 5)
        parts := [[midLeft, cornerTop, midW, edgeH], [midLeft, bottom - edgeH, midW, edgeH],
            [cornerLeft, midTop, edgeW, midH], [right - edgeW, midTop, edgeW, midH],
            [cornerLeft, cornerTop, gripW, gripH], [cornerRight, cornerTop, gripW, gripH],
            [cornerLeft, cornerBottom, gripW, gripH], [cornerRight, cornerBottom, gripW, gripH]]
        for i, part in parts {
            if (i <= this.Windows.Length) {
                this.Windows[i].Move(part*)
                continue
            }
            g := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x08000000 -DPIScale")
            g.BackColor := "Red"
            this.Windows.Push(g)
            this.GripByHwnd[g.Hwnd] := ScreenAreaPreview.Grips[i]
            g.Show("NA x" part[1] " y" part[2] " w" part[3] " h" part[4])
        }
        if (this.MouseDown == "") {
            this.MouseDown := this._OnMouseDown.Bind(this)
            this.SetCursor := this._OnSetCursor.Bind(this)
            OnMessage(0x0201, this.MouseDown)
            OnMessage(0x0020, this.SetCursor)
        }
    }

    _OnSetCursor(wParam, lParam, msg, hwnd) {
        if (!this.GripByHwnd.Has(hwnd))
            return
        cursor := DllCall("LoadCursor", "ptr", 0, "ptr", this.GripByHwnd[hwnd][3], "ptr")
        DllCall("SetCursor", "ptr", cursor)
        return 1
    }

    _OnMouseDown(wParam, lParam, msg, hwnd) {
        if (!this.GripByHwnd.Has(hwnd) || this.IsDragging())
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.Drag := {StartRect: this.Rect, X: x, Y: y, Grip: this.GripByHwnd[hwnd], Timer: this._DragTick.Bind(this)}
        SetTimer(this.Drag.Timer, 15)
        return 0
    }

    _DragTick() {
        Critical()
        if (!this.IsDragging())
            return
        drag := this.Drag
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        dx := x - drag.X, dy := y - drag.Y
        rect := drag.StartRect.Clone()
        minWidth := Min(this.MinSize, rect[3] - rect[1]), minHeight := Min(this.MinSize, rect[4] - rect[2])
        if (drag.Grip[1] < 0)
            rect[1] := Min(rect[1] + dx, rect[3] - minWidth)
        else if (drag.Grip[1] > 0)
            rect[3] := Max(rect[3] + dx, rect[1] + minWidth)
        if (drag.Grip[2] < 0)
            rect[2] := Min(rect[2] + dy, rect[4] - minHeight)
        else if (drag.Grip[2] > 0)
            rect[4] := Max(rect[4] + dy, rect[2] + minHeight)
        this._Draw(rect)
        if (GetKeyState("LButton", "P"))
            return
        this._StopDrag()
        if (this._SameRect(rect, drag.StartRect))
            return

        apply := this.Apply
        hwnd := this.TargetHwnd
        if (hwnd) {
            if (!WinExist("ahk_id " hwnd)) {
                this.Hide()
                return
            }
            start := GetWinPos(rect[1], rect[2], hwnd), end := GetWinPos(rect[3], rect[4], hwnd)
            rect := [start[1], start[2], end[1], end[2]]
        }
        Critical("Off")
        apply.Call(rect*)
    }

    _StopDrag() {
        if (this.IsDragging()) {
            SetTimer(this.Drag.Timer, 0)
            this.Drag := ""
        }
    }
}

; 快捷键键帽（F1 等）
AddHotkeyBadge(parent, hotkey, tip := "") {
    cap := parent.Add("Border").CornerRadius("3").BorderThickness("1.25").Padding("8,0")
        .Height(28).MinHeight(28)
        .BorderBrush("{DynamicResource ControlBorder}").Background("{DynamicResource ControlBg}")
        .VerticalAlignment("Center").SnapsToDevicePixels("True").UseLayoutRounding("True")
    if (tip != "")
        cap.ToolTip(tip)
    disp := FormatHotkeyDisplay(hotkey)
    if (disp == "")
        disp := hotkey
    disp := StrReplace(disp, "+", " + ")
    cap.Add("TextBlock").Text(disp).FontSize(11).FontWeight("SemiBold")
        .VerticalAlignment("Center").HorizontalAlignment("Center").Foreground("{DynamicResource TextMain}")
    return cap
}

; 侧栏「RMT文档」/指令编辑器「手册」：打开程序目录 index.html 并定位章节
; pageHash 形如 "#指令手册/2-按键"，留空则打开文档首页
; 不能直接 Run(file:///...#hash)：Windows ShellExecute 会丢掉 fragment，浏览器只打开首页
OnOpenRmtDoc(pageHash := "") {
    p := A_WorkingDir "\index.html"
    if (!FileExist(p)) {
        RmtDialog.Info(GetLang("未找到帮助文档，请检查程序目录下的 index.html 是否完整。"), GetLang("提示"))
        return
    }
    hash := Trim(pageHash)
    if (hash != "" && SubStr(hash, 1, 1) != "#")
        hash := "#" hash
    route := Trim(hash, " `t#")
    uri := FileToFileUri(p)
    if (uri == "") {
        uri := StrReplace(p, "\", "/")
        if (RegExMatch(uri, "i)^[a-z]:"))
            uri := "file:///" uri
    }
    target := uri
    if (route != "") {
        enc := UriEncode(route)
        target := uri "?r=" enc "#" enc
    }
    exe := FindChromiumBrowser()
    if (exe != "") {
        try {
            Run('"' exe '" "' target '"')
            return
        }
    }
    jump := A_Temp "\RmtDocJump.html"
    js := StrReplace(StrReplace(target, "\", "\\"), "'", "\'")
    html := "<!DOCTYPE html><html><head><meta charset='utf-8'></head><body><script>location.replace('" js "');</script></body></html>"
    try FileDelete(jump)
    FileAppend(html, jump, "UTF-8")
    Run(jump)
}

; 打开帮助文档；文件不存在时给出提示而不是抛 Run 错误
; pageHash 形如 "#/docs/commands/key"，留空则打开首页
; 三层降级：内嵌 WebView2 窗（Win10/11，自绘标题栏）→ Chromium --app 小窗 → 系统默认浏览器
OnOpenHelpDoc(pageHash := "") {
    p := GetHelpDocPath()
    if (!FileExist(p)) {
        RmtDialog.Info(GetLang("未找到帮助文档，请检查程序目录下的 index.html 是否完整。"), GetLang("提示"))
        return
    }
    if (HasWebView2Runtime() && HelpDocWin.Open(pageHash))
        return
    if (OpenHelpInAppWindow(pageHash))
        return
    Run(p)   ; 没有可用的 Chromium 浏览器 → 交系统默认浏览器
}

; 探测系统是否装有 WebView2 运行时（Win10 1803+ 一般自带；Win7 没有）
; 检查 EdgeUpdate Clients 注册表里的 pv 值，三个视图都查
HasWebView2Runtime() {
    static keys := ["HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
                  , "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
                  , "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"]
    for k in keys {
        try {
            v := Trim(RegRead(k, "pv"))
            if (v != "")
                return true
        }
    }
    return false
}

; 用 Chromium 浏览器的 --app 模式打开帮助文档（无地址栏的独立小窗）
; pageHash 形如 "#/docs/commands/key"，留空则打开首页
; winW / winH：窗口宽高。winW 默认 560（窄栏，触发站点移动端布局）；winH 传 0 表示与主窗口等高
; 返回 true = 已用 app 模式打开；false = 没找到浏览器或启动失败
OpenHelpInAppWindow(pageHash := "", winW := 560, winH := 0) {
    docPath := GetHelpDocPath()
    if (!FileExist(docPath))
        return false
    exe := FindChromiumBrowser()
    if (exe = "")
        return false

    ; 独立 user-data-dir：不与用户已开的浏览器共进程，
    ; 既不会被「恢复上次会话」/插件干扰，用户关浏览器时也不会连带关掉帮助窗
    profileDir := A_Temp "\RMT_HelpBrowser"
    if (!DirExist(profileDir))
        DirCreate(profileDir)

    ; 位置与尺寸：贴当前前台窗口（点「帮助」时就是 RMT 主窗口）右侧并等高，
    ; 右边放不下就贴左侧；完全取不到主窗口就贴主屏右侧
    mx := 0
    my := 0
    mw := 0
    mh := 0
    try WinGetPos(&mx, &my, &mw, &mh, "A")
    w := winW
    if (winW > A_ScreenWidth)
        w := A_ScreenWidth - 40
    if (mw < 200 || mh < 200) {
        x := A_ScreenWidth - w - 12
        y := 60
        h := (winH > 0) ? winH : Round(A_ScreenHeight * 0.85)
    } else {
        x := mx + mw
        y := my
        h := (winH > 0) ? winH : mh
        if (x + w > A_ScreenWidth)
            x := (mx - w >= 0) ? mx - w : A_ScreenWidth - w
    }

    cmd := '"' exe '"'
        . ' --app="' FileToFileUri(docPath) pageHash '"'
        . ' --user-data-dir="' profileDir '"'
        . ' --no-first-run --no-default-browser-check'
        . ' --window-size=' w ',' h
        . ' --window-position=' x ',' y
    try
        Run(cmd)
    catch
        return false
    return true
}

; 本地路径 → file:/// URL（--app 只接受 URL，不接受裸路径）
FileToFileUri(path) {
    p := StrReplace(path, "\", "/")
    if (!RegExMatch(p, "^[A-Za-z]:"))
        return ""
    return "file:///" UriEncode(p)
}

; UTF-8 百分号编码，保留 URL 路径中安全的字符（含 / 和 :）
; 用途：用户名/安装目录含中文或空格时，file:// URL 仍然可用
UriEncode(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    StrPut(s, buf, "UTF-8")
    out := "", i := 0
    while (i < buf.Size - 1) {
        b := NumGet(buf, i, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2F || b = 0x3A || b = 0x2D || b = 0x5F || b = 0x2E || b = 0x7E)
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
        i++
    }
    return out
}

; 探测可用的 Chromium 浏览器 exe 路径，找不到返回 ""
FindChromiumBrowser() {
    ; 1) 注册表 App Paths（Chrome / Edge；32 位进程需另查 WOW6432Node）
    for name in ["chrome.exe", "msedge.exe"] {
        for key in ["HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\"
                  , "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\"
                  , "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\"] {
            try {
                p := Trim(RegRead(key name), '" ')
                if (p != "" && FileExist(p))
                    return p
            }
        }
    }
    ; 2) 常见安装路径兜底
    pf  := EnvGet("ProgramFiles")
    pfx := EnvGet("ProgramFiles(x86)")
    lad := EnvGet("LocalAppData")
    for p in [lad "\Google\Chrome\Application\chrome.exe"
            , pf  "\Google\Chrome\Application\chrome.exe"
            , pfx "\Google\Chrome\Application\chrome.exe"
            , pfx "\Microsoft\Edge\Application\msedge.exe"
            , pf  "\Microsoft\Edge\Application\msedge.exe"
            , lad "\Microsoft\Edge\Application\msedge.exe"]
        if (FileExist(p))
            return p
    return ""
}

; ---------------- 错误统一展示（宏内业务错误） ----------------
; 这是同名两套实现里的「主进程版」：写系统日志 + 按级别通知（warn 托盘气泡 / error 错误中心）。
; Worker 版在 Thread\WorkUtil.ahk，只做一条 IPC 上报。两边由包含链决定，函数里没有角色分支。
; 返回 true 表示已处理（调用方无需再弹窗）。
RMTErrorShow(msg, level := RMT_LV_ERROR, source := "") {
    if (source == "")
        source := "Master"

    RMTLogSys(level, source, msg)
    if (level == RMT_LV_WARN) {
        ; warn：托盘气泡（2s 自动消失）
        if (!(IsSet(MainSoftData) && ObjHasOwnProp(MainSoftData, "LogWarnBubble") && !MainSoftData.LogWarnBubble)) {
            try TrayTip(Format("[{1}] {2}", source, msg), GetLang("RMT 警告"), 1)
            try SetTimer(() => TrayTip(), -2000)
        }
    } else if (level == RMT_LV_ERROR) {
        ; error：错误中心聚合
        if (IsSet(MyErrorMsgBoxGui) && IsObject(MyErrorMsgBoxGui)
            && !(IsSet(MainSoftData) && ObjHasOwnProp(MainSoftData, "LogErrorBadge") && !MainSoftData.LogErrorBadge))
            MyErrorMsgBoxGui.ShowGui(Format("[{1}] {2}", source, msg))
    }
    return true
}

; 日志里的进程标记（同名两套实现之一）。身份由入口文件决定，这里不需要判断。
ProcessTag() {
    return "Master"
}

; ---------------- 主界面按钮回调（仅主进程） ----------------
; 这些回调都要碰界面（读 MyMainWin、写工具文本），只在这个进程里存在。

OnToolTextFilterSelectImage(*) {
    global MainSoftData
    path := FileSelect(, , GetLang("选择图片"))
    if (path == "")
        return
    ocr := GetChineseOcr() ; v6 统一多语言模型，不再区分语言
    result := ocr.ocr_from_file(path)
    SetToolTextDisplay(result)
    SetClipboard(result)
}

OnClearToolText(*) {
    SetToolTextDisplay("")
}

OnBootStartChanged(ctrl, *) {
    global MyMainWin
    MainSoftData.IsBootStart := MyMainWin.ui.Query("ChkBootStart") == "True"
    ok := ApplyBootStartRegistry(MainSoftData.IsBootStart)
    CfgWrite(MainSoftData.IsBootStart ? 1 : 0, SettingFile, SettingSection, "IsBootStart")
    if (!ok) {
        ; 注册表未能与选项对齐时回滚勾选，避免界面已关、实际仍自启
        MainSoftData.IsBootStart := !MainSoftData.IsBootStart
        try MyMainWin.ui.Update("ChkBootStart", "IsChecked", MainSoftData.IsBootStart ? "True" : "False")
        CfgWrite(MainSoftData.IsBootStart ? 1 : 0, SettingFile, SettingSection, "IsBootStart")
        RmtDialog.Info(GetLang("开机自启设置失败，请检查是否被安全软件拦截，或勿通过兼容性强制管理员运行。"), GetLang("提示"), 48)
    }
}

OnAdminStartChanged(ctrl, *) {
    global MyMainWin
    MainSoftData.IsAdminStart := MyMainWin.ui.Query("ChkAdminStart") == "True"
    CfgWrite(MainSoftData.IsAdminStart ? 1 : 0, SettingFile, SettingSection, "IsAdminStart")
    if (MainSoftData.IsBootStart)
        ApplyBootStartRegistry(true)
}
