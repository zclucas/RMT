GetComboKeyArr(ComboKey) {
    KeyArr := []
    ModifyKeyMap := Map("LAlt", "<!", "RAlt", ">!", "Alt", "!", "LWin", "<#", "RWin", ">#", "Win", "#",
        "LCtrl", "<^", "RCtrl", ">^", "Ctrl", "^", "LShift", "<+", "RShift", ">+", "Shift", "+")

    loop {
        hasModifyKey := false
        for key, value in ModifyKeyMap {
            length := StrLen(value)
            subComboKey := SubStr(ComboKey, 1, length)
            if (subComboKey == value) {
                KeyArr.Push(key)
                ComboKey := SubStr(ComboKey, length + 1)
                hasModifyKey := true
                break
            }
        }

        if (!hasModifyKey)
            break
    }

    if (ComboKey != "")
        KeyArr.Push(ComboKey)
    return KeyArr
}

RegisterNativeComboWheelGuard() {
    OnMessage(0x020A, OnNativeComboMouseWheel)  ; WM_MOUSEWHEEL
}

; 只有已展开且持有焦点的原生下拉框可以用滚轮选项。
OnNativeComboMouseWheel(wParam, lParam, msg, hwnd) {
    try {
        ctrl := GuiCtrlFromHwnd(hwnd)
        if (ctrl.Type == "DDL" || ctrl.Type == "ComboBox") {
            ; 检查下拉列表是否展开（通过发送 CB_GETDROPPEDSTATE 消息）
            isDropped := SendNativeControlMessage(0x0157, 0, 0, hwnd)  ; 0x0157 是 CB_GETDROPPEDSTATE
            if (!isDropped || !ctrl.Focused) {
                return 0
            }
        }
    }
    ; 其他控件允许正常处理
    return
}

SendNativeControlMessage(Msg, wParam, lParam, hWnd) {
    static WM_USER := 0x400
    if (Msg >= WM_USER) {
        return DllCall("SendMessage", "Ptr", hWnd, "UInt", Msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    return DllCall("User32.dll\SendMessage", "Ptr", hWnd, "UInt", Msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

;初始化数据
InitData() {
    InitTableItemState()
    MySoftData.DataFileMap := Map("搜索", SearchFile, "搜索Pro", SearchProFile, "搜索All", SearchAllFile, "搜索Combo", SearchComboFile, "组合搜索", SearchComboFile, "搜索Multi", SearchComboFile, "移动Pro", MMProFile,
        "输出", OutputFile, "运行", RunFile, "运行Pro", RunFile, "循环", LoopFile, "宏操作", SubMacroFile, "变量", VariableFile,
        "变量提取", ExVariableFile, "如果", CompareFile, "如果Pro", CompareProFile, "运算", OperationFile,
        "后台鼠标", BGMouseFile, "后台按键", BGKeyFile, "文本处理", TextOpsFile, "Timing", TimingFile, "数组", ArrayFile,
        "输入", InputFile, "网络请求", HttpRequestFile, "文件读写", FileIOFile, "Excel", FileIOFile, "窗口信息", WindowManageFile, "调整窗口", WindowManageFile, "窗口管理", WindowManageFile, "按键检测", KeyCheckFile, "手柄检测", JoyCheckFile,
        "注释", CommentFile, "抓图", ScreenShotFile, "图形节点", GraphNodeFile, "图形开始节点", GraphStartNodeFile,
        "间隔", IntervalFile, "按键", KeyDataFile, "移动", MoveDataFile, "RMT指令", RMTCMDFile,
        "等待", WaitFile, "等待确定", WaitConfirmFile, "时间", TimeDataFile, "倒计时", CountDownFile,
        ; §20 指令改名：新名「鼠标移动/鼠标移动Pro/增量移动」与旧名「移动/移动Pro」双键并存（旧配置序列码与宏内容零迁移兼容）
        "鼠标移动", MoveDataFile, "鼠标移动Pro", MMProFile, "增量移动", DeltaMoveFile)
    MySoftData.DataClassMap := Map("搜索", SearchData, "搜索Pro", SearchData, "搜索All", SearchAllData, "搜索Combo", SearchData, "组合搜索", SearchData, "搜索Multi", SearchData, "移动Pro", MMProData,
        "输出", OutputData, "运行", RunData, "运行Pro", RunData, "循环", LoopData, "宏操作", SubMacroData, "变量", VariableData,
        "变量提取", ExVariableData, "如果", CompareData, "如果Pro", CompareProData, "运算", OperationData,
        "后台鼠标", BGMouseData, "后台按键", BGKeyData, "文本处理", TextOpsData, "Timing", TimingData, "数组", ArrayData,
        "输入", InputData, "网络请求", HttpRequestData, "文件读写", FileIOData, "Excel", FileIOData, "窗口信息", WindowInfoData, "调整窗口", WindowManageData, "窗口管理", WindowManageData, "按键检测", KeyCheckData, "手柄检测", KeyCheckData,
        "注释", CommentData, "抓图", ScreenShotData, "图形节点", MacroGraphNode, "图形开始节点", MacroGraphStartNode,
        "间隔", IntervalData, "按键", KeyDataConfig, "移动", MoveDataConfig, "RMT指令", RMTCMDData,
        "等待", WaitData, "等待确定", WaitConfirmData, "时间", TimeData, "倒计时", CountDownData,
        "鼠标移动", MoveDataConfig, "鼠标移动Pro", MMProData, "增量移动", DeltaMoveData)
}

; 是否正在运行罗技软件（G HUB / LGS）
; IbSendInit 只判断虚拟设备能否打开，进程未启动时仍可能返回成功，但按键实际无效
IsLogitechSoftwareRunning() {
    for name in ["lghub.exe", "lghub_agent.exe", "LCore.exe"] {
        if ProcessExist(name)
            return true
    }
    return false
}

InitLogitechGHubNew() {
    if (MySoftData.IsLogitechInit)
        return true

    static hasTipNoGHUB := false

    ; G HUB 2021 / LGS：鼠标报告 5 字节，须用 "Logitech"
    ; 较新 G HUB：鼠标报告 8 字节，须用 "LogitechGHubNew"
    ; 类型选错时键盘往往仍可用，但鼠标/滚轮会无效
    res := IbSendInit("Logitech", 0)
    if (res == false) {
        try IbSendDestroy()
        res := IbSendInit("LogitechGHubNew", 0)
    }
    if (res == false) {
        if (!hasTipNoGHUB) {
            hasTipNoGHUB := true
            ShowLogitechGHubTip(false)
        }
        return false
    }


    ; 设备可打开 ≠ 软件在运行；未运行时提醒并允许下次重试
    if (!IsLogitechSoftwareRunning()) {
        try IbSendDestroy()
        if (!hasTipNoGHUB) {
            hasTipNoGHUB := true
            ShowLogitechGHubTip(true)
        }
        return false
    }

    MySoftData.IsLogitechInit := true
    return true
}

; 初始化 MouseControl.dll（用于 Logi 模式下的鼠标移动）
InitMouseControl() {
    if (MySoftData.IsMouseControlInit)
        return true

    res := MC_Init()
    if (!res)
        return false

    MySoftData.IsMouseControlInit := true
    return true
}

;资源读取
; 指令显示默认宽度：基准 225，按屏幕 DPI 缩放（100%→225，150%→338）
GetDefaultCMDTipWidth() {
    return Round(225 * A_ScreenDPI / 96)
}

; AHK / Win32 屏幕坐标、宽高为物理像素；WPF Window.Left/Top/Width/Height 为 DIP
PhysToDip(v) {
    return Integer(Round(Integer(v) * 96 / A_ScreenDPI))
}

DipToPhys(v) {
    return Integer(Round(Integer(v) * A_ScreenDPI / 96))
}

CheckOcrIdle() {
    global MyChineseOcr, MyEnglishOcr, LastChineseOcrUseTime, LastEnglishOcrUseTime, OCR_IDLE_TIMEOUT

    currentTime := A_TickCount

    if (MyChineseOcr && (currentTime - LastChineseOcrUseTime > OCR_IDLE_TIMEOUT)) {
        UnloadChineseOcr()
    }

    if (MyEnglishOcr && (currentTime - LastEnglishOcrUseTime > OCR_IDLE_TIMEOUT)) {
        UnloadEnglishOcr()
    }
}

SafeReload() {
    ; 重载是同一次使用里的重启，不算再次打开软件，跳过下一次 getstatus
    try CfgWrite(true, SettingFile, SettingSection, "SkipDataReport")
    if (A_IsAdmin) {
        Run('"' A_ScriptFullPath '" -elevated')
        ExitApp()
    } else {
        Reload()
    }
}

WorkPoolEnabled() {
    global MyWorkPool
    return MyWorkPool != "" && IsObject(MyWorkPool) && (MyWorkPool.isDynamic || MyWorkPool.maxSize >= 1)
}
