#Requires AutoHotkey v2.0

BindKey() {
    BindSuspendHotkey()
    BindShortcut(MainSoftData.PauseHotkey, OnPauseHotKey)
    BindShortcut(MainSoftData.KillMacroHotkey, OnKillAllMacro)
    BindShortcut(MainSoftData.ToolCheckHotKey, OnToolCheckHotkey)
    BindShortcut(MainSoftData.ToolTextFilterHotKey, OnToolTextFilterScreenShot)
    BindShortcut(MainSoftData.ScreenShotHotKey, OnToolScreenShot)
    BindShortcut(MainSoftData.FreePasteHotKey, OnToolFreePaste)
    BindShortcut(MainSoftData.ToolRecordMacroHotKey, OnHotToolRecordMacro)
    InitTriggerKeyMap()
    BindMenuHotKey()
    BindUIPanelHotKey()
    BindTabHotKey()
    BindFoldSwitchHotkey()
    ; §2：保存后热重载（§17 选「否」）订阅触发键重绑，使模块/条目禁用、触发键改动运行时立即生效
    if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
        MyHotReloadBus.Subscribe(OnHotReloadRebindKeys)
    OnExit(OnExitSoft)
}

; §2 模块独立开关快捷键重绑总入口：fold 级禁用切换 / RMT指令「禁用模块」/ 保存热重载共用
RebindAllTriggerKeys() {
    InitTriggerKeyMap()
    BindMenuHotKey()
    BindUIPanelHotKey()
    BindTabHotKey()
    BindFoldSwitchHotkey()
}

; 保存后热重载订阅者：任何表配置变更都重绑触发键（fold 禁用状态/条目禁用/触发键改动实时生效）
OnHotReloadRebindKeys(tableIndex, itemIndex) {
    RebindAllTriggerKeys()
}

; ============================================================
; §2 模块独立快捷键开关：遍历全部表的折叠框，注册「启用/禁用模块」切换热键
; 按下 → OnFoldSwitchHotkey 切换 fold.ForbidState → 重绑触发键 + HotReloadBus 广播
; ============================================================
BindFoldSwitchHotkey() {
    for tableItem in MySoftData.TableInfo {
        for index, fold in tableItem.Folds {
            if (fold.ForbidHotkey == "")
                continue
            oriKey := fold.ForbidHotkey
            isCombo := IsComboKey(oriKey)
            key := isCombo ? oriKey : ("$*" oriKey)
            isJoyKey := RegExMatch(oriKey, "Joy")
            if (isJoyKey) {
                ; 手柄键：走 JoyMacro 映射（action 为函数对象，切换模块启用状态）
                try MyJoyMacro.AddMacro(oriKey, OnFoldSwitchHotkey.Bind(tableItem.Index, index), "", "")
            } else {
                try {
                    Hotkey(key, OnFoldSwitchHotkey.Bind(tableItem.Index, index))
                } catch as e {
                }
            }
        }
    }
}

; §2 模块开关动作：切换 fold 启用状态，实时重绑触发键 + 总线广播
OnFoldSwitchHotkey(tableIndex, foldIndex, *) {
    global MySoftData, MyMainWin, MyHotReloadBus
    tableItem := MySoftData.TableInfo[tableIndex]
    if (!tableItem)
        return
    fold := tableItem.Folds[foldIndex]
    if (!fold)
        return
    fold.ForbidState := !fold.ForbidState
    RebindAllTriggerKeys()
    ; §18 模块开关：即时落盘 + 广播（与 _ApplyChange FoldForbid 同链路）
    HotReloadPublish(tableIndex, 0)
    tip := (fold.ForbidState ? GetLang("模块已禁用：") : GetLang("模块已启用：")) (fold.Remark == "" ? fold.ID : fold.Remark)
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tip)
    ; 同步主界面折叠行「禁用」按钮态
    try {
        if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui)) {
            if (MyMainWin._useVirtual.Has(tableIndex))
                MyMainWin._vl.UpdateFoldForbid(tableIndex, foldIndex, fold.ForbidState)
            else
                MyMainWin.SyncFoldForbidBtnUI(tableIndex, foldIndex, fold.ForbidState)
        }
    } catch as e {
    }
}

BindShortcut(triggerInfo, action) {
    if (triggerInfo == "")
        return

    isString := SubStr(triggerInfo, 1, 1) == ":"

    if (isString) {
        Hotstring(triggerInfo, action)
    }
    else {
        isCombo := IsComboKey(triggerInfo)
        mapKey := StrLower(Trim(triggerInfo, "~"))
        if (isCombo) {
            key := triggerInfo
        }
        else {
            key := "$*~" triggerInfo
        }
        try {
            Hotkey(key, action)
        }
        catch as e {
        }
    }
}

BindSuspendHotkey() {
    global MySoftData
    if (MainSoftData.SuspendHotkey != "") {
        isCombo := IsComboKey(MainSoftData.SuspendHotkey)
        if (isCombo) {
            key := MainSoftData.SuspendHotkey
        }
        else {
            key := "$*~" MainSoftData.SuspendHotkey
        }
        try {
            Hotkey(key, OnSuspendHotkey, "S")
        }
        catch as e {
        }
    }
}

OnSuspendHotkey(*) {
    global MySoftData
    MainSoftData.IsSuspend := !MainSoftData.IsSuspend
    UIControls.SuspendToggle.Value := MainSoftData.IsSuspend
    if (MainSoftData.IsSuspend) {
        OnKillAllMacro()
        MyTimingScheduler.Stop()
        if (IsSet(MyVoiceEngine) && IsObject(MyVoiceEngine))
            MyVoiceEngine.Suspend()
        A_TrayMenu.Check(GetLang("休眠"))
        TraySetIcon("Images\Soft\IcoPause.ico", , true)
    }
    else {
        MyTimingScheduler.Start()
        if (IsSet(MyVoiceEngine) && IsObject(MyVoiceEngine))
            MyVoiceEngine.Resume()
        A_TrayMenu.Uncheck(GetLang("休眠"))
        TraySetIcon("Images\Soft\rabit.ico", , true)
    }

    tipStr := MainSoftData.IsSuspend ? GetLang("软件休眠") : GetLang("取消软件休眠")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    Suspend(MainSoftData.IsSuspend)
}

OnPauseHotKey(*) {
    MainSoftData.IsPause := !MainSoftData.IsPause
    UIControls.PauseToggle.Value := MainSoftData.IsPause

    for tableItem in MySoftData.TableInfo {
        for index, item in tableItem.Items {
            SetItemPauseState(tableItem, index, MainSoftData.IsPause)
        }
    }

    if (MainSoftData.IsPause) {
        MyTimingScheduler.Suspend()
        if (IsSet(MyVoiceEngine) && IsObject(MyVoiceEngine))
            MyVoiceEngine.Suspend()
    }
    else {
        MyTimingScheduler.Resume()
        if (IsSet(MyVoiceEngine) && IsObject(MyVoiceEngine))
            MyVoiceEngine.Resume()
    }

    tipStr := MainSoftData.IsPause ? GetLang("暂停所有宏") : GetLang("取消所有暂停")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)

    if (MySoftData.SpecialTableItem.Items.Length >= 1)
        MySoftData.SpecialTableItem.Items[1].Pause := MainSoftData.IsPause
}

SetPauseState(state) {
    UIControls.PauseToggle.Value := state
    MainSoftData.IsPause := state

    for tableItem in MySoftData.TableInfo {
        for index, item in tableItem.Items {
            SetItemPauseState(tableItem, index, state)
        }
    }

    if (MySoftData.SpecialTableItem.Items.Length >= 1)
        MySoftData.SpecialTableItem.Items[1].Pause := state
}

OnKillAllMacro(*) {
    global MySoftData, MyWorkPool
    ; 只停正在跑的宏，不要取消 AI 对话；取消走输入框暂停按钮

    CloseMenuWheel()

    MySoftData.MacroRunningCount := 0
    UpdateMacroRunningCount(0, 0)

    for tableItem in MySoftData.TableInfo {
        for index, item in tableItem.Items {
            if (item.ColorState == 1 || item.ColorState == 2) {
                MyStopMacro(tableItem, index)
            }
        }
    }

    KillSingleTableMacro(MySoftData.SpecialTableItem)

    tipStr := GetLang("终止所有宏")
    if (MySoftData.CMDTip)
        MyCMDReportAciton(tipStr)
}

OnToolCheckHotkey(*) {
    global MainSoftData
    MainSoftData.IsToolCheck := !MainSoftData.IsToolCheck
    UIControls.ToolCheck.Value := MainSoftData.IsToolCheck

    if (MainSoftData.IsToolCheck) {
        SetTimer SetToolCheckInfo, 100
    }
    else
        SetTimer SetToolCheckInfo, 0
}

SetToolCheckInfo() {
    global MainSoftData
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY, &winId
    try {
        MainSoftData.PosStr := mouseX . "," . mouseY
        try {
            WinPID := WinGetPID("ahk_id " winId)
            MainSoftData.ProcessName := ProcessGetName(WinPID)
        }
        catch {
            MainSoftData.ProcessName := ""
        }
        MainSoftData.ProcessTile := WinGetTitle(winId)
        MainSoftData.ProcessPid := WinGetPID(winId)
        MainSoftData.ProcessClass := WinGetClass(winId)
        MainSoftData.ProcessId := winId
        MainSoftData.Color := StrReplace(PixelGetColor(mouseX, mouseY, "Slow"), "0x", "")

        WinPosArr := GetCurWinPos()
        MainSoftData.WinPosStr := WinPosArr[1] . "," . WinPosArr[2]
        RefreshToolUI()
    }
}

OnClickToolRecordSettingBtn(*) {
    XamlUiDiag("=== click 指令录制按钮 ===", "UIUtil")
    ToolRecordSettingGui.ShowGui()
}

OnClickThemeSettingBtn(*) {
    XamlUiDiag("=== click 主题按钮 ===", "UIUtil")
    ThemeSettingGui.ShowGui()
}

OnClickHotkeySettingBtn(*) {
    XamlUiDiag("=== click 快捷键按钮 ===", "UIUtil")
    HotkeySettingGui.ShowGui()
}

OnClickMenuWheelSettingBtn(*) {
    XamlUiDiag("=== click 轮盘按钮 ===", "UIUtil")
    MenuWheelGlobalSettingGui.ShowGui()
}

OnClickUIMacroPanelSettingBtn(*) {
    XamlUiDiag("=== click 界面浮窗按钮 ===", "UIUtil")
    UIMacroPanelSettingGui.ShowGui()
}

OnClickCMDTipToggle(*) {
    global MyMainWin
    v := MyMainWin.ui.Query("ChkCMDTip") == "True"
    MySoftData.CMDTip := v
    SetCMDTipValue(v)
}

OnToolTextFilterScreenShot(*) {
    if (MainSoftData.ScreenShotType == 1) {
        SetClipboard("")
        Run("ms-screenclip:")
        SetTimer(OnToolTextCheckScreenShot, 500)
    }
    else if (MainSoftData.ScreenShotType == 3) {
        RunScreenCapture(OnToolTextCheckScreenShot)
    }
    else {
        TogSelectArea(true, OnToolTextFilterGetArea)
    }
}

OnToolScreenShot(*) {
    if (MainSoftData.ScreenShotType == 1) {
        Run("ms-screenclip:")
    }
    else if (MainSoftData.ScreenShotType == 3) {
        scPath := A_WorkingDir "\Plugins\ScreenCapture\ScreenCapture.exe"
        if !FileExist(scPath)
            return
        SetClipboard("")
        Run('"' scPath '" --tool:"rect,ellipse,arrow,number,line,text,mosaic,eraser,|,undo,redo,|,pin,clipboard,save,close"'
        )
    }
    else {
        TogSelectArea(true, OnToolScreenShotGetArea)
    }
}

OnToolScreenShotGetArea(x1, y1, x2, y2) {
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)
    Gdip_SetBitmapToClipboard(pBitmap)
    Gdip_DisposeImage(pBitmap)
}

RunScreenCapture(callback := "") {
    scPath := A_WorkingDir "\Plugins\ScreenCapture\ScreenCapture.exe"
    if !FileExist(scPath)
        return
    SetClipboard("")
    if (callback != "") {
        SetTimer(callback, 500)
    }
    Run('"' scPath '" --tool:"clipboard,close"')
}

OnToolFreePaste(*) {
    MyFreePasteGui.ShowGui()
}

OnClickMutiThreadHelpBtn(*) {
    str1 := GetLang("设置若梦兔最大线程数量")
    str2 := GetLang("-1：动态多线程，线程闲置时回收（30秒），不足时创建新的线程")
    str3 := GetLang("0：单线程")
    str4 := GetLang("n：固定线程为指定n（推荐3~5）")
    str5 := GetLang("提示：动态多线程采用固定线程3+动态多线程池最大16")

    str := Format("{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5)
    MsgBox(str, GetLang("多线程说明"))
}

OnClickModalSubGuiHelpBtn(*) {
    str1 := GetLang("开启后：打开指令编辑等子窗口时，会禁用主窗口，必须先关闭子窗口才能继续操作主窗口。")
    str2 := GetLang("关闭后：子窗口与主窗口可同时操作，方便对照主界面内容进行编辑。")
    str3 := GetLang("提示：默认开启，一般建议保持开启，避免误操作主窗口导致编辑内容丢失。")

    str := Format("{}`n{}`n{}", str1, str2, str3)
    MsgBox(str, GetLang("模态子窗口说明"))
}

OnClickCheckForegroundHelpBtn(*) {
    str1 := GetLang("开启后：宏运行时会检查该项配置的前台窗口；若当前前台窗口不匹配，则终止该宏。")
    str2 := GetLang("关闭后：不校验前台窗口，宏按原逻辑继续执行。")
    str3 := GetLang("提示：需在对应宏项中配置「前台」信息后才会生效；未配置前台信息的宏不受此选项影响。")

    str := Format("{}`n{}`n{}", str1, str2, str3)
    MsgBox(str, GetLang("仅前台运行宏说明"))
}

OnClickAdminStartHelpBtn(*) {
    str1 := GetLang("开启后：软件会以管理员身份启动。部分功能（如后台键鼠、部分游戏按键模拟等）需要管理员权限才能生效。")
    str2 := GetLang("若同时开启开机自启，自启时也会以管理员身份启动。")
    str3 := GetLang("重要：请不要自行通过「右键若梦兔 → 属性 → 兼容性 → 以管理员身份运行此程序」绑定管理员权限，这样会导致「开机自启」选项失效。如需管理员权限，请使用本选项。")

    str := Format("{}`n{}`n{}", str1, str2, str3)
    MsgBox(str, GetLang("管理员启动说明"))
}

OnClickKeyDownDownHelpBtn(*) {
    str1 := GetLang("当宏按键已经处于按下状态，再次触发按下指令时特别处理")
    str2 := GetLang("自动松开：再次按下前，先松开该按键（确保指令正常执行）")
    str3 := GetLang("忽略重复按下：保持按键之前的状态，忽略后续的按下指令")
    str4 := GetLang("允许重复按下：再次按下宏按键（罗技按键可能卡死）")
    str5 := GetLang("Tip1：按下时再次按下，真实键盘无法触发这个行为，这个行为通常是无效的")
    str6 := GetLang("Tip2：按下时再次按下，按键检测网站可能无法检测，但记事本中可以有效输出")

    str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
    MsgBox(str, GetLang("按下时按下说明"))
}

OnClickMacroStopHelpBtn(*) {
    str1 := GetLang("智能终止：优先以协作方式让宏自行退出，设 150ms 期限，逾期未退出则强制结束。")
    str2 := GetLang("强制终止：直接结束线程并创建新线程，不等待宏自行退出。")
    str3 := GetLang("提示：强制终止响应更快，但频繁结束、创建线程会消耗较多资源，建议保持智能终止。")

    str := Format("{}`n`n{}`n`n{}", str1, str2, str3)
    MsgBox(str, GetLang("宏终止方式说明"))
}

OnClickAutoLoosenModifierHelpBtn(*) {
    str1 := GetLang("开启后：当触发键为「修饰键 + 普通键」（如 Ctrl + A）时，触发宏前会先松开修饰键，再执行宏逻辑。")
    str2 := GetLang("这样可避免修饰键仍被按住，导致宏里发送的按键变成组合键（例如本意发 A，实际变成 Ctrl+A）。")
    str3 := GetLang("关闭后：不自动松开修饰键，保持物理按键原样。")
    str4 := GetLang("提示：触发键以 ~ 开头（穿透）时，不会自动松开修饰键。")

    str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
    MsgBox(str, GetLang("自动松开修饰键说明"))
}

OnClickContinuousTriggerHelpBtn(*) {
    str1 := GetLang("开启后：按下、开关、长按类型在按住触发键期间可以连续触发。")
    str2 := GetLang("关闭后：按下、开关、长按类型必须先松开触发键，才能再次触发。")
    str3 := GetLang("提示：松开、松止、双击类型不受此选项影响。")

    str := Format("{}`n{}`n{}", str1, str2, str3)
    MsgBox(str, GetLang("连续触发说明"))
}

OnClickSharedCopyHelpBtn(*) {
    str1 := GetLang("开启后：逻辑树编辑器右键菜单会在「复制」下方新增「共享复制」条目。")
    str2 := GetLang("共享复制会原样复制指令文本（不重新分配内部序列号）")
    str3 := GetLang("指令修改，相同序列号的指令会同步修改内容")

    str := Format("{}`n{}`n{}", str1, str2, str3)
    MsgBox(str, GetLang("共享复制说明"))
}

OnClickFileCheckHelpBtn(*) {
    str1 := GetLang("文件校验：检查运行所需的插件、模型、图标、音频等资源文件是否齐全。")
    str2 := GetLang("若发现缺失，可一键从 GitHub 资源仓库自动下载补全（需联网）。")
    str3 := GetLang("适用场景：安装包不完整、杀毒误删、自行替换/删除插件文件后功能异常等。")
    str4 := GetLang("提示：此检查不会在启动时自动执行，需要时在「工具」页手动点击「文件校验」。")
    str5 := GetLang("注意：带 F 后缀的测试版本此功能不会生效（资源仓库仅对应正式版本 tag）。")

    str := Format("{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5)
    MsgBox(str, GetLang("文件校验说明"))
}

OnClickMacroJoyTypeHelpBtn(*) {
    str1 := GetLang("设置宏实际输出到的虚拟手柄类型（Xbox 360 / DS4），影响按键模拟输出。")
    str2 := GetLang("仅影响实际模拟输出，不影响界面按键名称的显示（显示请使用「手柄映射」）。")

    str := Format("{}`n{}", str1, str2)
    MsgBox(str, GetLang("宏手柄类型说明"))
}

OnClickTriggerJoyTypeHelpBtn(*) {
    str1 := GetLang("手柄映射：触发键、按键指令、按键检测等所有手柄按键名称的显示统一使用此映射。")

    MsgBox(str1, GetLang("手柄映射说明"))
}

OnExitSoft(*) {
    global MyPToken, MyChineseOcr, MyEnglishOcr, MyUIMacroGui, MyWorkPool, MyVoiceEngine
    global MainSoftData, MySoftData, IniFile, IniSection, MyMainWin

    try {
        if (IsSet(MyMainWin) && IsObject(MyMainWin))
            MyMainWin._AiPersistAllTabs()
    }

    ; ① 先隐藏主窗口：WPF 窗口属于 daemon 进程，进程清理期间仍留在屏幕上正是「窗口关得慢」的主因。
    ;    先隐藏后，用户感知窗口立即关闭，其余清理在后台进行。
    try {
        if (IsSet(MainSoftData) && IsObject(MainSoftData) && IsObject(MainSoftData.MyGui))
            MainSoftData.MyGui.Hide()
    }

    ; ② 语音引擎先停：VoiceDll 的采集/识别线程若在进程退出时仍在运行，
    ;    DLL 卸载与线程执行竞态是 0xc0000409 崩溃的头号嫌疑，退出前必须 join 停线程。
    try {
        if (IsSet(MyVoiceEngine) && IsObject(MyVoiceEngine))
            MyVoiceEngine.Stop()
    } catch as e {
        RMTLogSys(RMT_LV_WARN, "Exit", "语音引擎停止失败: " (e.HasProp("Message") ? e.Message : ""))
    }

    ; ③ 各项清理各自 try：任一失败（如 gdiplus 已卸载抛错）都不中断后续清理
    try Gdip_Shutdown(MyPToken)
    catch as e {
        RMTLogSys(RMT_LV_WARN, "Exit", "Gdip_Shutdown 失败: " (e.HasProp("Message") ? e.Message : ""))
    }
    try IbSendDestroy()
    catch as e {
        RMTLogSys(RMT_LV_WARN, "Exit", "IbSendDestroy 失败: " (e.HasProp("Message") ? e.Message : ""))
    }
    try {
        MyChineseOcr := ""
        MyEnglishOcr := ""
    } catch {
    }
    try CleanupAllMacroStates()
    catch as e {
        RMTLogSys(RMT_LV_WARN, "Exit", "CleanupAllMacroStates 失败: " (e.HasProp("Message") ? e.Message : ""))
    }

    if (MyWorkPool != "") {
        try MyWorkPool.Clear()
        catch as e {
            RMTLogSys(RMT_LV_WARN, "Exit", "WorkPool.Clear 失败: " (e.HasProp("Message") ? e.Message : ""))
        }
        MyWorkPool := ""
    }
    if (IsSet(MyUIMacroGui) && MyUIMacroGui != "") {
        try MyUIMacroGui.StopMonitor()
        catch as e {
            RMTLogSys(RMT_LV_WARN, "Exit", "UIMacro.StopMonitor 失败: " (e.HasProp("Message") ? e.Message : ""))
        }
    }
    try IniWrite(MySoftData.MacroTotalCount, IniFile, IniSection, "MacroTotalCount")
    catch {
    }
}

BindMenuHotKey() {
    tableItem := GetTableBySymbol("Menu")
    if (!tableItem)
        return
    for index, fold in tableItem.Folds {
        if (fold.ForbidState || fold.TK == "")
            continue

        oriKey := fold.TK
        isCombo := IsComboKey(oriKey)
        if (isCombo) {
            key := oriKey
        }
        else {
            key := "$*" oriKey
        }
        actionArr := GetBindMacroAction(oriKey)
        isJoyKey := RegExMatch(oriKey, "Joy")
        frontInfo := fold.FrontInfo
        realFrontStr := GetParamsWinInfoStr(frontInfo)

        if (realFrontStr != "") {
            HotIfWinActive(realFrontStr)
        }

        if (isJoyKey) {
            MyJoyMacro.AddMacro(oriKey, actionArr[1], frontInfo, actionArr[2])
        }
        else {
            try {
                if (actionArr[1] != "")
                    Hotkey(key, actionArr[1])

                if (actionArr[2] != "" && !isCombo)
                    Hotkey(key " up", actionArr[2])

                ; 顺序触发（默认无序）：注册反向组合键；勾选顺序时不注册
                if (isCombo && !fold.UnorderedTrigger) {
                    reversedKey := GetReversedComboKey(oriKey)
                    if (reversedKey != "") {
                        try {
                            Hotkey(reversedKey, actionArr[1])
                            if (actionArr[2] != "" && !isCombo)
                                Hotkey(reversedKey " up", actionArr[2])
                        }
                        catch as e {
                        }
                    }
                }
            }
            catch as e {
            }
        }

        if (realFrontStr != "") {
            HotIfWinActive
        }
    }
}

; 界面宏模块级触发键：走 TriggerKeyMap 统一分发（与菜单宏一致）
; 不可单独 Hotkey→TogglePanel：与按键宏共用同一键时会被 BindTabHotKey 覆盖，
; 且旧逻辑在 TriggerKeyInfo 里误把 macroType=3 当成菜单宏打开轮盘。
BindUIPanelHotKey() {
    tableItem := GetTableBySymbol("UI")
    if (!tableItem)
        return

    for index, fold in tableItem.Folds {
        if (fold.ForbidState || fold.TK == "")
            continue

        oriKey := fold.TK
        isCombo := IsComboKey(oriKey)
        key := isCombo ? oriKey : ("$*" oriKey)
        actionArr := GetBindMacroAction(oriKey)
        isJoyKey := RegExMatch(oriKey, "Joy")
        frontInfo := fold.FrontInfo
        realFrontStr := GetParamsWinInfoStr(frontInfo)

        if (realFrontStr != "")
            HotIfWinActive(realFrontStr)

        if (isJoyKey) {
            MyJoyMacro.AddMacro(oriKey, actionArr[1], frontInfo, actionArr[2])
        }
        else {
            try {
                if (actionArr[1] != "")
                    Hotkey(key, actionArr[1])
                if (actionArr[2] != "" && !isCombo)
                    Hotkey(key " up", actionArr[2])
            }
            catch as e {
            }
        }

        if (realFrontStr != "")
            HotIfWinActive
    }
}

BindTabHotKey() {
    tableIndex := 0
    MyJoyMacro.MacroMap := Map()
    MyJoyMacro.ComboMacroMap := Map()
    ; 同步清空边缘触发状态，避免旧宏残留 prev=1 导致重绑后首个按键边沿丢失
    MyJoyMacro.prevXboxState := Map()
    registerMsg := "=== Registered Hotkeys ===`n"

    ; 预计算缓存Map（避免重复的字符串处理和正则匹配）
    keyCache := Map()

    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        tableIndex := A_Index
        symbol := tableItem.Symbol
        canBind := symbol == "Normal" || symbol == "String" || symbol == "SubMacro"
        if (!canBind)
            continue

        for index, item in tableItem.Items {
            ; 优化：一次调用获取所有Fold信息（避免重复遍历Folds）
            foldData := GetItemFoldData(tableItem, index)
            if (foldData.forbidState)
                continue

            if (item.TK == "" || item.Forbid)
                continue

            if (item.Macro == "")
                continue

            rawKey := item.TK

            ; 使用缓存避免重复计算
            cacheKey := rawKey "|" tableIndex "|" index
            if (!keyCache.Has(cacheKey)) {
                cacheData := {
                    isCombo: IsComboKey(rawKey),
                    isJoy: !!RegExMatch(rawKey, "Joy"),
                    isHotstring: SubStr(rawKey, 1, 1) == ":",
                    firstChar: SubStr(rawKey, 1, 1),
                    keyPrefix: (SubStr(rawKey, 1, 1) == "~" || !IsComboKey(rawKey)) ? "$*" : "",
                    frontInfo: foldData.frontInfo,
                    realFrontStr: ""
                }

                if (cacheData.frontInfo != "")
                    cacheData.realFrontStr := GetParamsWinInfoStr(cacheData.frontInfo)

                keyCache.Set(cacheKey, cacheData)
            }
            cache := keyCache[cacheKey]

            key := cache.isCombo ? rawKey : cache.keyPrefix rawKey
            actionArr := GetMacroAction(tableIndex, index)

            registerMsg .= "rawKey: '" rawKey "' → key: '" key "' (isCombo=" cache.isCombo ")`n"

            if (cache.realFrontStr != "") {
                HotIfWinActive(cache.realFrontStr)
            }

            if (cache.isJoy) {
                MyJoyMacro.AddMacro(rawKey, actionArr[1], cache.frontInfo, actionArr[2])
            }
            else if (cache.isHotstring) {
                Hotstring(rawKey, actionArr[1])
            }
            else {
                try {
                    if (actionArr[1] != "") {
                        Hotkey(key, actionArr[1], "On")
                    }

                    if (actionArr[2] != "" && !cache.isCombo)
                        Hotkey(key " up", actionArr[2], "On")

                    ; 顺序触发（默认无序）：注册反向组合键；勾选顺序时不注册
                    if (cache.isCombo && !item.UnorderedTrigger) {
                        reversedKey := GetReversedComboKey(rawKey)
                        if (reversedKey != "") {
                            try {
                                Hotkey(reversedKey, actionArr[1], "On")
                                if (actionArr[2] != "" && !cache.isCombo)
                                    Hotkey(reversedKey " up", actionArr[2], "On")
                                registerMsg .= "  ↩ Reversed: '" reversedKey "'`n"
                            }
                            catch as e {
                                registerMsg .= "  ❌ Unordered Failed: " e.Message "`n"
                            }
                        }
                    }
                }
                catch as e {
                    registerMsg .= "❌ Failed: " e.Message "`n"
                }
            }

            if (cache.realFrontStr != "") {
                HotIfWinActive
            }
        }
    }
}

InitTriggerKeyMap() {
    MySoftData.TriggerKeyMap := Map()
    tableItem := GetTableBySymbol("Normal")
    if (tableItem) {
        for index, item in tableItem.Items {
            if (GetItemFoldForbidState(tableItem, index))
                continue

            if (item.TK == "" || item.Forbid)
                continue

            if (item.Macro == "")
                continue

            key := LTrim(item.TK, "~")
            key := StrLower(key)
            if (!MySoftData.TriggerKeyMap.Has(key)) {
                MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
            }
            info := TriggerKeyInfo()
            info.macroType := 1
            info.tableID := tableItem.ID
            info.itemID := item.ID
            MySoftData.TriggerKeyMap[key].AddData(info)

            ; 顺序触发（默认无序）：将反向组合键也加入映射；勾选顺序时不加
            if (!item.UnorderedTrigger) {
                reversedRaw := GetReversedComboKey(item.TK)
                if (reversedRaw != "") {
                    reversedKey := LTrim(reversedRaw, "~")
                    reversedKey := StrLower(reversedKey)
                    if (!MySoftData.TriggerKeyMap.Has(reversedKey)) {
                        MySoftData.TriggerKeyMap[reversedKey] := MySoftData.TriggerKeyMap[key]
                    }
                }
            }
        }
    }

    ; 菜单宏：模块级（折叠框）触发键
    tableItem := GetTableBySymbol("Menu")
    if (tableItem) {
        for index, fold in tableItem.Folds {
            if (fold.ForbidState || fold.TK == "")
                continue
            key := LTrim(fold.TK, "~")
            key := StrLower(key)
            if (!MySoftData.TriggerKeyMap.Has(key)) {
                MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
            }
            info := TriggerKeyInfo()
            info.tableID := tableItem.ID
            info.macroType := 2
            info.foldID := fold.ID
            MySoftData.TriggerKeyMap[key].AddData(info)

            ; 顺序触发（默认无序）：将反向组合键也加入映射；勾选顺序时不加
            if (!fold.UnorderedTrigger) {
                reversedRaw := GetReversedComboKey(fold.TK)
                if (reversedRaw != "") {
                    reversedKey := LTrim(reversedRaw, "~")
                    reversedKey := StrLower(reversedKey)
                    if (!MySoftData.TriggerKeyMap.Has(reversedKey)) {
                        MySoftData.TriggerKeyMap[reversedKey] := MySoftData.TriggerKeyMap[key]
                    }
                }
            }
        }
    }

    ; 界面宏的Fold触发键（悬浮面板切换）
    tableItem := GetTableBySymbol("UI")
    if (tableItem) {
        for index, fold in tableItem.Folds {
            if (fold.ForbidState || fold.TK == "")
                continue
            key := LTrim(fold.TK, "~")
            key := StrLower(key)
            if (!MySoftData.TriggerKeyMap.Has(key)) {
                MySoftData.TriggerKeyMap[key] := TriggerKeyData(key)
            }
            info := TriggerKeyInfo()
            info.tableID := tableItem.ID
            info.macroType := 3  ; 界面宏面板类型
            info.foldID := fold.ID
            MySoftData.TriggerKeyMap[key].AddData(info)
        }
    }
}

GetMacroAction(tableIndex, index) {
    tableItem := MySoftData.TableInfo[tableIndex]
    item := tableItem.Items[index]
    macro := item.Macro
    tableSymbol := tableItem.Symbol
    actionDown := ""
    actionUp := ""

    if (tableSymbol == "Normal") {
        actionDown := OnTriggerKeyDown.Bind(tableIndex, index)
        actionUp := OnTriggerKeyUp.Bind(tableIndex, index)
    }
    else if (tableSymbol == "String") {
        ; §17 表身份已 ID 化（670460e8 重构）：TriggerMacroHandler 首参须为表对象/ID，
        ; 绑定对象而非数字索引，否则 GetTableByID("3") 解析失败 → 字符串宏触发键/热串永不触发
        actionDown := TriggerMacroHandler.Bind(tableItem, index)
    }
    else if (tableSymbol == "Replace") {
        actionDown := OnReplaceDownKey.Bind(tableItem, macro, index)
        actionUp := OnReplaceUpKey.Bind(tableItem, macro, index)
    }
    return [actionDown, actionUp]
}

OnTriggerKeyDown(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    item := tableItem.Items[itemIndex]
    rawTK := item.TK
    key := LTrim(rawTK, "~")
    key := StrLower(key)

    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyDown()
}

OnTriggerKeyUp(tableIndex, itemIndex, *) {
    tableItem := MySoftData.TableInfo[tableIndex]
    item := tableItem.Items[itemIndex]
    key := LTrim(item.TK, "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyUp()
}

GetBindMacroAction(key) {
    actionDown := OnBindKeyDown.Bind(key)
    actionUp := OnBindKeyUp.Bind(key)
    return [actionDown, actionUp]
}

OnBindKeyDown(key, *) {
    key := LTrim(key, "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    if (MainSoftData.SelectAreaAction != "")
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyDown()
}

OnBindKeyUp(key, *) {
    key := LTrim(key, "~")
    key := StrLower(key)
    if (!MySoftData.TriggerKeyMap.Has(key))
        return

    Data := MySoftData.TriggerKeyMap[key]
    Data.OnTriggerKeyUp()
}

; 开关触发：表身份=TableItem 对象
OnToggleTriggerMacro(tableItem, itemIndex) {
    if (!IsObject(tableItem))
        tableItem := GetTableByID(String(tableItem))
    if (!tableItem)
        return
    if (IsObject(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
    }
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    macro := item.Macro
    tableID := tableItem.ID
    itemID := item.ID

    if (WorkPoolEnabled()) {
        SetTableItemState(tableItem, itemIndex, 1)
        MyWorkPool.PrepareItemRun(tableID, itemID)
        GraphPoolLog("宏触发", Format("tab={1} item={2} 来源=开关", tableID, itemID))
        cmd := EncodeBatch(EncodeCommand("TR", tableID, itemID))
        MyWorkPool.Submit(cmd, tableID, itemID)
        item.IsWorkIndex := true
        return
    }

    isTrigger := item.ToggleState
    if (!isTrigger) {
        item.ToggleState := true
        SetTableItemState(tableItem, itemIndex, 1)
        action := OnTriggerMacroKeyAndInit.Bind(tableItem, macro, itemIndex)
        item.ToggleAction := action
        SetTimer(action, -1)
    }
    else {
        action := item.ToggleAction
        if (action == "")
            return

        KillTableItemMacro(tableItem, itemIndex)
        SetTableItemState(tableItem, itemIndex, 3)
        SetTimer(action, 0)
    }
}

; 触发宏入口：表身份=TableItem 对象（位置不代表身份）
TriggerMacroHandler(tableItem, itemIndex, *) {
    if (!IsObject(tableItem))
        tableItem := GetTableByID(String(tableItem))
    if (!tableItem)
        return
    if (IsObject(itemIndex)) {
        itemIndex := GetItemIndexInTable(tableItem, itemIndex.ID)
    } else if (!IsNumber(itemIndex)) {
        ; 字符串 ItemID（跨模块 ID 引用）
        itemIndex := GetItemIndexInTable(tableItem, String(itemIndex))
    }
    if (itemIndex < 1)
        return
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    ; §17 统一禁用门控（条目禁用 Forbid / 所属模块禁用 fold.ForbidState → 任何触发来源均不执行）：
    ; 热重载（保存选「否」）后旧热键/定时器排程里的残留条目仍会到达此入口，
    ; 在这里统一拦截后禁用立即生效；覆盖 String 表直绑热键、定时宏、Worker 分支触发、子宏「触发」等路径
    ; Forbid 用 ParseBoolInt 归一（防旧配置遗留字符串 "0" 被当 truthy）
    if (ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, itemIndex))
        return
    macro := item.Macro
    tableID := tableItem.ID
    itemID := item.ID
    isWork := item.IsWorkIndex
    if (isWork && MyWorkPool != "" && IsObject(MyWorkPool) && MyWorkPool.HasItemWork(tableID, itemID))
        return

    SetTableItemState(tableItem, itemIndex, 1)
    if (WorkPoolEnabled()) {
        if (isWork)
            GraphPoolLog("宏触发恢复", Format("tab={1} item={2} 清理上次残留", tableID, itemID))
        MyWorkPool.PrepareItemRun(tableID, itemID)
        GraphPoolLog("宏触发", Format("tab={1} item={2}", tableID, itemID))
        cmd := EncodeBatch(EncodeCommand("TR", tableID, itemID))
        MyWorkPool.Submit(cmd, tableID, itemID)
        item.IsWorkIndex := true
        return
    }
    MySoftData.MacroTotalCount += 1
    OnTriggerMacroKeyAndInit(tableItem, macro, itemIndex)
}

GetReversedComboKey(comboKey) {
    if (!InStr(comboKey, " & "))
        return ""

    parts := StrSplit(comboKey, " & ")
    if (parts.Length != 2)
        return ""

    part1 := Trim(parts[1])
    part2 := Trim(parts[2])

    hasTilde1 := SubStr(part1, 1, 1) == "~"
    hasTilde2 := SubStr(part2, 1, 1) == "~"

    key1 := hasTilde1 ? SubStr(part1, 2) : part1
    key2 := hasTilde2 ? SubStr(part2, 2) : part2

    prefix1 := hasTilde2 ? "~" : ""
    prefix2 := hasTilde1 ? "~" : ""

    return prefix1 key2 " & " prefix2 key1
}
