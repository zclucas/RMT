#Requires AutoHotkey v2.0
#Include "DataClass.ahk"
#Include Util\TableLocator.ahk
#Include Util\ExcelUtil.ahk
#Include Util\SerialUtil.ahk
#Include Util\JsonUtil.ahk
#Include Util\LangUtil.ahk
#Include Util\Gdip_All.ahk
#Include Util\CompatDataUtil.ahk
#Include Util\CompareUtil.ahk
#Include Util\PresssKeyUtil.ahk
#Include Util\TextOpsUtil.ahk
#Include Util\ArrayUtil.ahk
#Include Util\ExpressUtil.ahk
#Include Util\InputUtil.ahk
#Include Util\SearchUtil.ahk
#Include Util\FileIOUtil.ahk
#Include Util\HumanMouse.ahk
#Include Util\MacroUtil.ahk
#Include Util\GraphMacroUtil.ahk
#Include Util\PluginUtil.ahk
#Include Util\ThemeUtil.ahk

#Include ..\Plugins\CLR.ahk
#Include "..\Plugins\RapidOcr\RapidOcr.ahk"
#Include "..\Plugins\AhiDriver\AhiDriver.ahk"
#Include "..\Plugins\IbInputSimulator.ahk"
#Include "..\Plugins\MouseControl.ahk"
#Include Util\MouseMoveUtil.ahk

global WM_COPYDATA := 0x4a ;传递字符串，系统信息

global WM_LOAD_WORK := 0x500  ;资源加载完成事件
global WM_CLEAR_WORK := 0x502  ;资源释放事件
global WM_TR_MACRO := 0x503 ;触发宏事件
global WM_STOP_MACRO := 0x504 ;停止宏事件
global WM_MASTER_TO_WORKER := 0x509  ; 主进程→Worker：分发任务/广播通知
global WM_WORKER_TO_MASTER := 0x50A  ; Worker→主进程：任务完成/事件上报

; 功能函数
GetFloatTime(oriTime, floatValue) {
    hasAdd := InStr(floatValue, "+")
    hasReduce := InStr(floatValue, "-")
    if (!hasAdd && !hasReduce) {
        hasAdd := true
        hasReduce := true
    }

    oriTime := Integer(oriTime)
    floatValue := Integer(floatValue)
    value := Abs(oriTime * (floatValue * 0.01))
    maxValue := hasAdd ? oriTime + value : oriTime
    minValue := hasReduce ? oriTime - value : oriTime
    result := Max(0, Random(minValue, maxValue))
    return result
}

GetFloatValue(oriValue, floatValue) {
    hasAdd := InStr(floatValue, "+")
    hasReduce := InStr(floatValue, "-")
    if (!hasAdd && !hasReduce) {
        hasAdd := true
        hasReduce := true
    }

    oriValue := Integer(oriValue)
    value := Abs(floatValue)
    maxValue := hasAdd ? oriValue + value : oriValue
    minValue := hasReduce ? oriValue - value : oriValue
    return Random(minValue, maxValue)
}

GetCurMSec() {
    return A_Hour * 3600 * 1000 + A_Min * 60 * 1000 + A_Sec * 1000 + A_mSec
}

GetHwndList(infoStr) {
    HwndList := []
    if (infoStr == "")
        return HwndList

    if (InStr(infoStr, "❖")) {
        infoStr := StrReplace(infoStr, "❖")
        hwndIdStrList := StrSplit(infoStr, "|")
        for index, hwndIdStr in hwndIdStrList {
            if (SubStr(hwndIdStr, 1, 1) = "{" && SubStr(hwndIdStr, -1) = "}")
                hwndIdStr := SubStr(hwndIdStr, 2, -1)

            hasValue := TryGetVarValue(&hwnd, hwndIdStr)
            if (hasValue)
                HwndList.Push(hwnd)
        }
        return HwndList
    }

    paramStr := GetParamsWinInfoStr(infoStr)
    if (paramStr == "")
        return HwndList

    HwndList := WinGetList(paramStr)

    loop HwndList.Length {
        index := HwndList.Length - A_Index + 1
        if (HwndList[index] == 0)
            HwndList.RemoveAt(index)
    }

    return HwndList
}

GetParamsWinInfoStr(infoStr) {
    if (infoStr == "")
        return ""

    if (InStr(infoStr, "❖")) {
        infoStr := StrReplace(infoStr, "❖")
        groupName := "UIGroup_" infoStr
        static groupCache := Map()
        if (!groupCache.Has(groupName)) {
            hwndList := StrSplit(infoStr, "|")
            for index, hwnd in hwndList {
                GroupAdd(groupName, "ahk_id " hwnd)
            }
            groupCache[groupName] := true
        }
        ResStr := "ahk_group " groupName
        return ResStr
    }

    infoArr := StrSplit(infoStr, "⎖")
    if (infoArr.Length != 3)
        return ""

    title := infoArr[1]
    className := infoArr[2]
    process := infoArr[3]

    ; 构建条件字符串
    condition := ""

    ; 添加标题（如果非空）
    if (title != "")
        condition .= title

    ; 添加窗口类（如果非空）
    if (className != "") {
        if (condition != "")
            condition .= " "
        condition .= "ahk_class " className
    }

    ; 添加进程名（如果非空）
    if (process != "") {
        if (condition != "")
            condition .= " "
        condition .= "ahk_exe " process
    }

    return condition
}

GetProcessName() {
    MouseGetPos &mouseX, &mouseY, &winId
    name := ""
    try {
        WinPID := WinGetPID("ahk_id " winId)
        name := ProcessGetName(WinPID)
    }
    catch {
        name := ""
    }
    return name
}

SaveClipToBitmap(filePath) {
    ; 保存位图到文件; 检查剪切板中是否有位图
    if !DllCall("IsClipboardFormatAvailable", "uint", 2)  ; 2 是 CF_BITMAP
    {
        RMTErrorShow(GetLang("剪切板中没有位图"), RMT_LV_WARN, "宏")
    }

    ; 打开剪切板
    if !DllCall("OpenClipboard", "ptr", 0) {
        RMTErrorShow(GetLang("无法打开剪切板"), RMT_LV_WARN, "宏")
        return
    }

    ; 获取剪切板中的位图句柄
    hBitmap := DllCall("GetClipboardData", "uint", 2, "ptr")  ; 2 是 CF_BITMAP
    if !hBitmap {
        RMTErrorShow(GetLang("无法获取位图句柄"), RMT_LV_WARN, "宏")
        DllCall("CloseClipboard")
        return
    }

    ; 关闭剪切板
    DllCall("CloseClipboard")

    ; 创建 GDI+ 位图对象
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
    if !pBitmap {
        RMTErrorShow(GetLang("无法创建 GDI+ 位图对象"), RMT_LV_WARN, "宏")
        return
    }

    ; 保存位图到文件
    Gdip_SaveBitmapToFile(pBitmap, filePath)

    ; 释放 GDI+ 位图对象
    Gdip_DisposeImage(pBitmap)
}

GetImageSize(imageFile) {
    pBm := Gdip_CreateBitmapFromFile(imageFile)
    width := Gdip_GetImageWidth(pBm)
    height := Gdip_GetImageHeight(pBm)

    Gdip_DisposeImage(pBm)
    return [width, height]
}

GetNextImageSerial(baseDir := "") {
    if (baseDir == "")
        baseDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot"

    maxSerial := 0
    loop files, baseDir "\*.png" {
        if (RegExMatch(A_LoopFileName, "^(\d+)\.png$", &match)) {
            serial := Integer(match[1])
            if (serial > maxSerial)
                maxSerial := serial
        }
    }

    nextSerial := maxSerial + 1
    return Format("{:03d}", nextSerial)
}

SplitMacro(macroStr) {
    cmdArr := StrSplit(macroStr, [",", "，", "`n", "⫶"])
    resultArr := []

    for value in cmdArr {
        curCmd := Trim(value)
        if (curCmd != "")
            resultArr.Push(curCmd)
    }
    return resultArr
}

SplitCommand(macro) {
    realKey := ""
    newMacro := macro

    ; 直接遍历全部20个特殊键做 InStr 包含检测。
    ; 原本的前4字符前缀优化是取 macro 开头的字符，但当特殊键不在指令开头时
    ; （例如 "按键_Launch_App2_点击_100"，前4字符为 "按键_L" 而非 "Laun"），
    ; 会导致所有长键名（Launch_App2 等）全部被漏检。
    ; SpecialKeyMap 只有 20 个键，直接遍历性能完全足够。
    for key in MySoftData.SpecialKeyMap {
        replaced := StrReplace(macro, key, "flagSymbol")
        if (replaced != macro) {
            realKey := key
            newMacro := replaced
            break
        }
    }

    result := StrSplit(realKey != "" ? newMacro : macro, "_")
    loop result.Length {
        if (InStr(result[A_Index], "flagSymbol")) {
            result[A_Index] := StrReplace(result[A_Index], "flagSymbol", realKey)
            break
        }
    }

    return result
}

GetCmdByParams(paramArr) {
    result := ""
    for index, value in paramArr {
        if (value != "") {
            result .= value "_"
        }
    }
    result := Trim(result, "_")
    return result
}

GetMacroStrByCmdArr(cmdArr) {
    ; 使用循环拼接（兼容所有数组类型，避免.Join()方法不存在的问题）
    result := ""
    for index, value in cmdArr {
        if (index > 1)
            result .= ","
        result .= value
    }
    return result
}

GetPressKeyArr(KeyArrStr) {
    if (InStr(KeyArrStr, "⎖")) {
        return StrSplit(KeyArrStr, "⎖")
    }
    return GetComboKeyArr(KeyArrStr)    ;兼容旧版本
}

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

EditListen() {
    OnMessage(0x020A, WM_MOUSEWHEEL)  ; 0x020A 是 WM_MOUSEWHEEL
}

WM_MOUSEWHEEL(wParam, lParam, msg, hwnd) {
    try {
        ctrl := GuiCtrlFromHwnd(hwnd)
        if (ctrl.Type == "DDL" || ctrl.Type == "ComboBox") {
            ; 检查下拉列表是否展开（通过发送 CB_GETDROPPEDSTATE 消息）
            isDropped := CheckIfDrop(0x0157, 0, 0, hwnd)  ; 0x0157 是 CB_GETDROPPEDSTATE
            if (!isDropped || !ctrl.Focused) {
                return 0  ; 阻止处理未展开状态下的滚轮事件
            }
        }
    }
    ; 其他控件允许正常处理
    return
}

CheckIfDrop(Msg, wParam, lParam, hWnd) {
    ; 辅助函数：发送 Windows 消息
    static WM_USER := 0x400
    if (Msg >= WM_USER) {
        return DllCall("SendMessage", "Ptr", hWnd, "UInt", Msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    return DllCall("User32.dll\SendMessage", "Ptr", hWnd, "UInt", Msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

;初始化数据
InitData() {
    InitTableItemState()
    MySoftData.DataFileMap := Map("搜索", SearchFile, "搜索Pro", SearchProFile, "移动Pro", MMProFile,
        "输出", OutputFile, "运行", RunFile, "循环", LoopFile, "宏操作", SubMacroFile, "变量", VariableFile,
        "变量提取", ExVariableFile, "如果", CompareFile, "如果Pro", CompareProFile, "运算", OperationFile,
        "后台鼠标", BGMouseFile, "后台按键", BGKeyFile, "文本处理", TextOpsFile, "Timing", TimingFile, "数组", ArrayFile,
        "输入", InputFile, "文件读写", FileIOFile, "窗口管理", WindowManageFile, "按键检测", KeyCheckFile,
        "注释", CommentFile, "抓图", ScreenShotFile, "图形节点", GraphNodeFile, "图形开始节点", GraphStartNodeFile,
        "间隔", IntervalFile, "按键", KeyDataFile, "移动", MoveDataFile, "RMT指令", RMTCMDFile)
    MySoftData.DataClassMap := Map("搜索", SearchData, "搜索Pro", SearchData, "移动Pro", MMProData,
        "输出", OutputData, "运行", RunData, "循环", LoopData, "宏操作", SubMacroData, "变量", VariableData,
        "变量提取", ExVariableData, "如果", CompareData, "如果Pro", CompareProData, "运算", OperationData,
        "后台鼠标", BGMouseData, "后台按键", BGKeyData, "文本处理", TextOpsData, "Timing", TimingData, "数组", ArrayData,
        "输入", InputData, "文件读写", FileIOData, "窗口管理", WindowManageData, "按键检测", KeyCheckData,
        "注释", CommentData, "抓图", ScreenShotData, "图形节点", MacroGraphNode, "图形开始节点", MacroGraphStartNode,
        "间隔", IntervalData, "按键", KeyDataConfig, "移动", MoveDataConfig, "RMT指令", RMTCMDData)
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

LoadMainSetting() {
    global MainSoftData, MySoftData
    global IniSection := "UserSettings"
    MySoftData.CurSettingName := IniRead(IniFile, IniSection, "CurSettingName", "RMT默认配置")
    MainSoftData.SettingArrStr := IniRead(IniFile, IniSection, "SettingArrStr", "RMT默认配置")
    MainSoftData.HasSaved := IniRead(IniFile, IniSection, "HasSaved", false)
    MainSoftData.IsReload := IniRead(IniFile, IniSection, "IsReload", false)
    MySoftData.NormalPeriod := IniRead(IniFile, IniSection, "NormalPeriod", 50)
    MainSoftData.HoldFloat := IniRead(IniFile, IniSection, "HoldFloat", 0)
    MainSoftData.PreIntervalFloat := IniRead(IniFile, IniSection, "PreIntervalFloat", 0)
    MainSoftData.IntervalFloat := IniRead(IniFile, IniSection, "IntervalFloat", 0)
    MainSoftData.CoordXFloat := IniRead(IniFile, IniSection, "CoordXFloat", 0)
    MainSoftData.CoordYFloat := IniRead(IniFile, IniSection, "CoordYFloat", 0)
    MainSoftData.SuspendHotkey := IniRead(IniFile, IniSection, "SuspendHotkey", "!p")
    MainSoftData.PauseHotkey := IniRead(IniFile, IniSection, "PauseHotkey", "!i")
    MainSoftData.KillMacroHotkey := IniRead(IniFile, IniSection, "KillMacroHotkey", "!k")
    MainSoftData.IsToolCheck := IniRead(IniFile, IniSection, "IsToolCheck", false)
    MainSoftData.ToolCheckHotKey := IniRead(IniFile, IniSection, "ToolCheckHotKey", "!o")
    MainSoftData.ToolRecordMacroHotKey := IniRead(IniFile, IniSection, "RecordMacroHotKey", "!r")
    MainSoftData.ToolTextFilterHotKey := IniRead(IniFile, IniSection, "ToolTextFilterHotKey", "!u")
    MainSoftData.ScreenShotHotKey := IniRead(IniFile, IniSection, "ScreenShotHotKey", "!y")
    MainSoftData.FreePasteHotKey := IniRead(IniFile, IniSection, "FreePasteHotKey", "!t")
    MainSoftData.RecordKeyboard := IniRead(IniFile, IniSection, "RecordKeyboard", true)
    MainSoftData.RecordMouse := IniRead(IniFile, IniSection, "RecordMouse", true)
    MainSoftData.RecordJoy := IniRead(IniFile, IniSection, "RecordJoy", false)
    MainSoftData.RecordMouseTrail := IniRead(IniFile, IniSection, "RecordMouseTrail", 1)
    MainSoftData.RecordMouseTrailSpeed := IniRead(IniFile, IniSection, "RecordMouseTrailSpeed", 95)
    MainSoftData.RecordHoldMuti := IniRead(IniFile, IniSection, "RecordHoldMuti", false)
    MainSoftData.RecordAutoLoosen := IniRead(IniFile, IniSection, "RecordAutoLoosen", true)
    MainSoftData.RecordJoyInterval := IniRead(IniFile, IniSection, "RecordJoyInterval", 50)
    MainSoftData.RecordShowBorder := IniRead(IniFile, IniSection, "RecordShowBorder", true)
    MainSoftData.OCRTypeValue := IniRead(IniFile, IniSection, "OCRType", 1)
    MainSoftData.IsBootStart := IniRead(IniFile, IniSection, "IsBootStart", false)
    if (MainSoftData.IsBootStart == 1 || MainSoftData.IsBootStart == 2)
        MainSoftData.IsBootStart := true
    else if (MainSoftData.IsBootStart == "false" || MainSoftData.IsBootStart == 0)
        MainSoftData.IsBootStart := false
    else
        MainSoftData.IsBootStart := !!MainSoftData.IsBootStart
    MainSoftData.IsAdminStart := IniRead(IniFile, IniSection, "IsAdminStart", false)
    if (MainSoftData.IsAdminStart == 1 || MainSoftData.IsAdminStart == "true")
        MainSoftData.IsAdminStart := true
    else if (MainSoftData.IsAdminStart == "false" || MainSoftData.IsAdminStart == 0)
        MainSoftData.IsAdminStart := false
    else
        MainSoftData.IsAdminStart := !!MainSoftData.IsAdminStart
    MainSoftData.ShowSplitLine := IniRead(IniFile, IniSection, "ShowSplitLine", false)
    MainSoftData.FixedMenuWheel := IniRead(IniFile, IniSection, "FixedMenuWheel", false)
    MainSoftData.MenuWheelSelectMode := IniRead(IniFile, IniSection, "MenuWheelSelectMode", 2)
    MainSoftData.MenuWheelShowTooltip := IniRead(IniFile, IniSection, "MenuWheelShowTooltip", false)
    MainSoftData.MenuWheelScale := IniRead(IniFile, IniSection, "MenuWheelScale", 100)
    MainSoftData.Theme := IniRead(IniFile, IniSection, "Theme", "RMT_Light")
    ; 主题字体：大小与 FontType 一样落在用户设置；旧版 themes.ini 仅作迁移回退
    global XAML_FontSizeDelta, XAML_FontSizeBase, XAML_FontSizeDefault, XAML_FontWeight, XAML_TextClarity
    defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
    fs := IniRead(IniFile, IniSection, "FontSize", "")
    if (fs == "" || !IsNumber(fs)) {
        themeIni := GetThemesIniPath()
        fs := IniRead(themeIni, MainSoftData.Theme, "FontSize", defFs)
    }
    ApplyUserFontSize(fs, false)
    if (IniRead(IniFile, IniSection, "FontSize", "") == "")
        try IniWrite(MainSoftData.FontSize, IniFile, IniSection, "FontSize")
    try {
        themeIni := GetThemesIniPath()
        MainSoftData.FontWeight := FontWeightToNum(IniRead(themeIni, MainSoftData.Theme, "FontWeight", "400"))
        XAML_FontWeight := MainSoftData.FontWeight
        MainSoftData.FontClarity := "1"   ; 文字清晰度固定 1（标准平滑）
        XAML_TextClarity := 1
    }
    ; 界面浮窗配置（非颜色）
    MainSoftData.UIPanelShowOnActive := IniRead(IniFile, IniSection, "UIPanelShowOnActive", true)
    MainSoftData.UIPanelDefaultPos := Integer(IniRead(IniFile, IniSection, "UIPanelDefaultPos", 1))
    ; 旧版本「鼠标位置」=8 已移除；无效值统一归一化为左上角(1)
    if (MainSoftData.UIPanelDefaultPos == 8 || MainSoftData.UIPanelDefaultPos < 1 || MainSoftData.UIPanelDefaultPos > 10)
        MainSoftData.UIPanelDefaultPos := 1
    MainSoftData.UIPanelOffsetX := IniRead(IniFile, IniSection, "UIPanelOffsetX", 100)
    MainSoftData.UIPanelOffsetY := IniRead(IniFile, IniSection, "UIPanelOffsetY", 100)
    MainSoftData.UIPanelBtnHeight := IniRead(IniFile, IniSection, "UIPanelBtnHeight", 34)
    MainSoftData.UIPanelFontSize := IniRead(IniFile, IniSection, "UIPanelFontSize", 12)
    MainSoftData.UIPanelBtnWidth := IniRead(IniFile, IniSection, "UIPanelBtnWidth", 80)
    MainSoftData.UIPanelCols := IniRead(IniFile, IniSection, "UIPanelCols", 3)
    EnsureXAMLThemesIni()
    ; 统一主题颜色（轮盘/浮窗/指令显示），不兼容旧分散颜色配置
    AppThemeUtil.LoadFromIni()
    MainSoftData.IsModalSubGui := IniRead(IniFile, IniSection, "IsModalSubGui", true)
    MainSoftData.MutiThreadNum := IniRead(IniFile, IniSection, "MutiThreadNum", -1)
    MainSoftData.DynamicCorePoolSize := IniRead(IniFile, IniSection, "DynamicCorePoolSize", 2)
    MainSoftData.ElasticTimeout := IniRead(IniFile, IniSection, "ElasticTimeout", 30)
    MainSoftData.MacroStopType := Integer(IniRead(IniFile, IniSection, "MacroStopType", 1))
    if (MainSoftData.MacroStopType != 1 && MainSoftData.MacroStopType != 2)
        MainSoftData.MacroStopType := 1
    MainSoftData.SoftBGColor := IniRead(IniFile, IniSection, "SoftBGColor", "f0f0f0")
    MainSoftData.NoVariableTip := IniRead(IniFile, IniSection, "NoVariableTip", true)
    ; 业务日志开关（统一日志 C 项阶段3）：默认关，开启后 Worker 写 Business.log 流水
    global RMTLogBusinessEnabled
    MainSoftData.BusinessLog := IniRead(IniFile, IniSection, "BusinessLog", false)
    RMTLogBusinessEnabled := MainSoftData.BusinessLog
    ; 日志与错误（C 项阶段5）
    global RMTLogSysMinLevel
    MainSoftData.SysLogMinLevel := IniRead(IniFile, IniSection, "SysLogMinLevel", "info")
    RMTLogSysMinLevel := MainSoftData.SysLogMinLevel
    MainSoftData.LogWarnBubble := IniRead(IniFile, IniSection, "LogWarnBubble", true)
    MainSoftData.LogErrorBadge := IniRead(IniFile, IniSection, "LogErrorBadge", true)
    MySoftData.CMDTip := IniRead(IniFile, IniSection, "CMDTip", false)
    MainSoftData.CheckForeground := IniRead(IniFile, IniSection, "CheckForeground", false)
    MainSoftData.ScreenShotType := IniRead(IniFile, IniSection, "ScreenShotType", 3)
    MainSoftData.KeyDownDownType := IniRead(IniFile, IniSection, "KeyDownDown", 1)
    MainSoftData.AutoLoosenModifier := !!IniRead(IniFile, IniSection, "AutoLoosenModifier", true)
    MainSoftData.ContinuousTrigger := !!IniRead(IniFile, IniSection, "ContinuousTrigger", true)
    MainSoftData.AgreeAgreement := IniRead(IniFile, IniSection, "AgreeAgreement", false)
    MySoftData.WinPosX := IniRead(IniFile, IniSection, "WinPosX", 0)
    MySoftData.WinPosY := IniRead(IniFile, IniSection, "WinPosY", 0)
    MainSoftData.TableIndex := IniRead(IniFile, IniSection, "TableIndex", 1)
    MainSoftData.CurTableID := IsNumber(MainSoftData.TableIndex) ? "" : MainSoftData.TableIndex
    MainSoftData.Lang := IniRead(IniFile, IniSection, "Lang", "无语言")
    MainSoftData.FontType := IniRead(IniFile, IniSection, "FontType", "微软雅黑")
    MainSoftData.JoyType := IniRead(IniFile, IniSection, "JoyType", "Xbox")
    if (MainSoftData.JoyType == "PS5")
        MainSoftData.JoyType := "DS4"   ; 兼容旧配置：ViGEm 仅有 DS4（DualShock 4），无 PS5 类型
    MainSoftData.TriggerJoyType := IniRead(IniFile, IniSection, "TriggerJoyType", "Xbox")
    MainSoftData.PreferredMacroEditor := Integer(IniRead(IniFile, IniSection, "PreferredMacroEditor", 1))
    MainSoftData.SharedCopy := !!IniRead(IniFile, IniSection, "SharedCopy", false)
    MainSoftData.GeneralContextMenu := IniRead(IniFile, IniSection, "GeneralContextMenu", "")
    MainSoftData.BranchContextMenu  := IniRead(IniFile, IniSection, "BranchContextMenu",  "")
    if (MainSoftData.PreferredMacroEditor != 1 && MainSoftData.PreferredMacroEditor != 2)
        MainSoftData.PreferredMacroEditor := 1
    MainSoftData.RemarkAutoType := Integer(IniRead(IniFile, IniSection, "RemarkAutoType", 2))
    if (MainSoftData.RemarkAutoType != 1 && MainSoftData.RemarkAutoType != 2 && MainSoftData.RemarkAutoType != 3)
        MainSoftData.RemarkAutoType := 2
    ; CMD 默认：宽按 DPI 缩放，高 300，X = 屏幕宽 - 显示宽（物理像素 / -DPIScale）
    defCMDWidth := GetDefaultCMDTipWidth()
    MainSoftData.CMDWidth := IniRead(IniFile, IniSection, "CMDWidth", defCMDWidth)
    MainSoftData.CMDHeight := IniRead(IniFile, IniSection, "CMDHeight", 300)
    MainSoftData.CMDPosX := IniRead(IniFile, IniSection, "CMDPosX", A_ScreenWidth - Integer(MainSoftData.CMDWidth))
    MainSoftData.CMDPosY := IniRead(IniFile, IniSection, "CMDPosY", 0)
    MainSoftData.CMDTransparency := IniRead(IniFile, IniSection, "CMDTransparency", 50)
    MainSoftData.CMDFontSize := IniRead(IniFile, IniSection, "CMDFontSize", 12)
    MainSoftData.CMDLogToFile := IniRead(IniFile, IniSection, "CMDLogToFile", false)
    MainSoftData.CMDLogFilePath := IniRead(IniFile, IniSection, "CMDLogFilePath", "")
    MainSoftData.CMDLogAutoClear := IniRead(IniFile, IniSection, "CMDLogAutoClear", 0)
    MainSoftData.VarListenTop := IniRead(IniFile, IniSection, "VarListenTop", 1)
    MainSoftData.VarListenWidth := IniRead(IniFile, IniSection, "VarListenWidth", 400)
    MainSoftData.VarListenHeight := IniRead(IniFile, IniSection, "VarListenHeight", 420)
    MySoftData.MacroTotalCount := IniRead(IniFile, IniSection, "MacroTotalCount", 0)
    MainSoftData.LastShowMonth := IniRead(IniFile, IniSection, "LastShowMonth", A_Mon)

    MySoftData.TableInfo := CreateTableItemArr()
    SetFontList()
    LangInitSetting()
    LangKeysInit()
}

GetThemesIniPath() {
    if (IsSet(ThemesIniPath) && ThemesIniPath != "")
        return ThemesIniPath
    return A_WorkingDir "\Setting\themes.ini"
}

; persistIni=true 时写入 MainSettings（权威）并同步 themes.ini
ApplyUserFontSize(fs, persistIni := true) {
    global XAML_FontSizeDelta, XAML_FontSizeBase, XAML_FontSizeDefault
    baseFs := IsSet(XAML_FontSizeBase) ? XAML_FontSizeBase : 15
    defFs := IsSet(XAML_FontSizeDefault) ? XAML_FontSizeDefault : 15
    if (!IsNumber(fs))
        fs := defFs
    fs := Integer(fs)
    if (fs < 0)
        fs := 0
    if (fs > 40)
        fs := 40
    MainSoftData.FontSize := fs
    XAML_FontSizeDelta := fs - baseFs
    if (persistIni) {
        try IniWrite(fs, IniFile, IniSection, "FontSize")
        try IniWrite(fs, GetThemesIniPath(), MainSoftData.Theme, "FontSize")
    }
    return fs
}

EnsureXAMLThemesIni() {
    static done := false
    if (done)
        return
    iniPath := GetThemesIniPath()
    if (FileExist(iniPath)) {
        done := true
        return
    }
    if (!DirExist(A_ScriptDir "\Setting"))
        DirCreate(A_ScriptDir "\Setting")
    IniWrite("2,0", iniPath, "RMT_Light", "Window_DWM")
    IniWrite("15", iniPath, "RMT_Light", "FontSize")   ; 主题字体大小（软件默认 15）
    IniWrite("400", iniPath, "RMT_Light", "FontWeight")
    IniWrite("1", iniPath, "RMT_Light", "FontClarity")
    IniWrite("CornerRadius:8", iniPath, "RMT_Light", "Resource_WindowRadius")
    IniWrite("#FFF0F0F0", iniPath, "RMT_Light", "Resource_BgColor")
    IniWrite("#FFEBEBEB", iniPath, "RMT_Light", "Resource_TitleBarColor")
    IniWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_TitleBarForeground")
    IniWrite("#20E0E0E0", iniPath, "RMT_Light", "Resource_SidebarColor")
    IniWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_TextMain")
    IniWrite("#FF666666", iniPath, "RMT_Light", "Resource_TextSub")
    IniWrite("#FFF0F0F0", iniPath, "RMT_Light", "Resource_ControlBg")
    IniWrite("#FF999999", iniPath, "RMT_Light", "Resource_ControlBorder")
    IniWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_InputBg")
    IniWrite("#FFCCCCCC", iniPath, "RMT_Light", "Resource_InputStroke")
    IniWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_InputText")
    IniWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_EditBg")
    IniWrite("#FFCCCCCC", iniPath, "RMT_Light", "Resource_EditStroke")
    IniWrite("#FF1A1A1A", iniPath, "RMT_Light", "Resource_EditText")
    IniWrite("#FFE3F2FD", iniPath, "RMT_Light", "Resource_EditHoverBg")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_EditHoverStroke")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ActionBg")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ActionStroke")
    IniWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_ActionText")
    IniWrite("#FF106EBE", iniPath, "RMT_Light", "Resource_ActionHoverBg")
    IniWrite("#FF106EBE", iniPath, "RMT_Light", "Resource_ActionHoverStroke")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ProgressBar")
    IniWrite("#FFFFFFFF", iniPath, "RMT_Light", "Resource_DropdownBg")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_Accent")
    IniWrite("Double:8", iniPath, "RMT_Light", "Resource_ScrollBarWidth")
    IniWrite("CornerRadius:3", iniPath, "RMT_Light", "Resource_ScrollBarRadius")
    IniWrite("#FF0078D7", iniPath, "RMT_Light", "Resource_ScrollBarHover")

    IniWrite("2,1", iniPath, "RMT_Dark", "Window_DWM")
    IniWrite("15", iniPath, "RMT_Dark", "FontSize")   ; 主题字体大小（软件默认 15）
    IniWrite("400", iniPath, "RMT_Dark", "FontWeight")
    IniWrite("1", iniPath, "RMT_Dark", "FontClarity")
    IniWrite("CornerRadius:8", iniPath, "RMT_Dark", "Resource_WindowRadius")
    IniWrite("#FF1E1E1E", iniPath, "RMT_Dark", "Resource_BgColor")
    IniWrite("#20000000", iniPath, "RMT_Dark", "Resource_SidebarColor")
    IniWrite("#FFFFFFFF", iniPath, "RMT_Dark", "Resource_TextMain")
    IniWrite("#FFAAAAAA", iniPath, "RMT_Dark", "Resource_TextSub")
    IniWrite("#15252525", iniPath, "RMT_Dark", "Resource_ControlBg")
    IniWrite("#20333333", iniPath, "RMT_Dark", "Resource_ControlBorder")
    IniWrite("#FF252525", iniPath, "RMT_Dark", "Resource_DropdownBg")
    IniWrite("#FF0A84FF", iniPath, "RMT_Dark", "Resource_Accent")
    IniWrite("Double:8", iniPath, "RMT_Dark", "Resource_ScrollBarWidth")
    IniWrite("CornerRadius:3", iniPath, "RMT_Dark", "Resource_ScrollBarRadius")
    IniWrite("#FF0A84FF", iniPath, "RMT_Dark", "Resource_ScrollBarHover")
    done := true
}

; 字体粗细名称 → 数值（100-900），兼容旧配置里的 Normal/Bold 等名称
FontWeightToNum(w) {
    switch w {
        case "Thin", "100":
            return "100"
        case "ExtraLight", "200":
            return "200"
        case "Light", "300":
            return "300"
        case "Normal", "Regular", "400", "":
            return "400"
        case "Medium", "500":
            return "500"
        case "SemiBold", "600":
            return "600"
        case "Bold", "700":
            return "700"
        case "ExtraBold", "800":
            return "800"
        case "Black", "Heavy", "900":
            return "900"
    }
    if (IsNumber(w) && w >= 100 && w <= 900)
        return w
    return "400"
}

; XAML 设置窗诊断日志（排查：打不开 / 打开了但看不见）
; 输出：A_WorkingDir\Log\XamlUiDiag.log
XamlUiDiag(msg, tag := "diag") {
    try {
        logDir := A_WorkingDir "\Log"
        if !DirExist(logDir)
            DirCreate(logDir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " [" tag "] " msg "`n"
            , logDir "\XamlUiDiag.log", "UTF-8")
    }
}

; 手柄按键输出诊断日志（排查：宏内 Joy 按键不生效）
; 归口统一日志（C 项）：debug 级（默认不写，设置页开启 Debug 后生效）
JoyDebugLog(msg, tag := "joy") {
    who := (IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker) ? "Worker" : "Master"
    RMTLogSys(RMT_LV_DEBUG, who, "[" tag "] " msg)
}

; 抓图指令诊断日志（排查：抓图后 Images\TempShot 下没有生成 Shot.png）
; 输出：主进程 A_WorkingDir\Log\ShotDebug.log；Worker 写到 A_ScriptDir\..\Log\ShotDebug.log
ShotDebugLog(msg, tag := "shot") {
    try {
        isWorker := IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker
        logDir := isWorker ? (A_ScriptDir "\..\Log") : (A_WorkingDir "\Log")
        if !DirExist(logDir)
            DirCreate(logDir)
        who := isWorker ? "Worker" : "Master"
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " [" who "/" tag "] " msg "`n"
            , logDir "\ShotDebug.log", "UTF-8")
    }
}

; 搜索指令诊断日志（排查：搜索无结果、真/假分支都不执行）
; 输出：主进程 A_WorkingDir\Log\SearchDebug.log；Worker 写到 A_ScriptDir\..\Log\SearchDebug.log
SearchDebugLog(msg, tag := "search") {
    try {
        isWorker := IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker
        logDir := isWorker ? (A_ScriptDir "\..\Log") : (A_WorkingDir "\Log")
        if !DirExist(logDir)
            DirCreate(logDir)
        who := isWorker ? "Worker" : "Master"
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " +" A_TickCount " [" who "/" tag "] " msg "`n"
            , logDir "\SearchDebug.log", "UTF-8")
    }
}

XamlUiDiagDaemon(tag := "daemon") {
    ; Worker 未加载 AHK-XAML：用动态名解析，避免裸写 XAMLHost 触发 #Warn / 编译失败
    try {
        hostName := "XAMLHost"
        if (!IsSet(%hostName%)) {
            XamlUiDiag("XAMLHost not loaded", tag)
            return
        }
        host := %hostName%
        hwnd := host.daemonHwnd
        alive := host.IsDaemonAlive()
        resp := alive ? host.IsDaemonResponsive(300) : false
        XamlUiDiag(Format("daemonHwnd={} alive={} responsive={}", hwnd, alive, resp), tag)
    } catch as e {
        XamlUiDiag("daemon status err: " e.Message, tag)
    }
}

; 记录窗口位置/可见性；若疑似透明或跑出屏幕则强制可见并居中
XamlUiDiagWindow(hwnd, tag := "win", fixIfHidden := false) {
    if (!hwnd) {
        XamlUiDiag("hwnd=0 (no window)", tag)
        return false
    }
    exists := DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
    visible := DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int")
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        XamlUiDiag(Format("hwnd={} exists={} visible={} pos=({},{}) size={}x{} title=[{}] screen={}x{}"
            , hwnd, exists, visible, x, y, w, h, title, A_ScreenWidth, A_ScreenHeight), tag)
        odd := (w < 40 || h < 40 || x < -3000 || y < -3000
            || x > A_ScreenWidth + 200 || y > A_ScreenHeight + 200 || !visible)
        if (fixIfHidden && odd) {
            nw := (w > 40) ? w : 540
            nh := (h > 40) ? h : 640
            cx := Max(0, (A_ScreenWidth - nw) // 2)
            cy := Max(0, (A_ScreenHeight - nh) // 2)
            XamlUiDiag(Format("FIX offscreen/hidden -> Move({},{}) size={}x{}", cx, cy, nw, nh), tag)
            try WinMove(cx, cy, nw, nh, "ahk_id " hwnd)
            try WinShow("ahk_id " hwnd)
            try WinActivate("ahk_id " hwnd)
            WinGetPos(&x2, &y2, &w2, &h2, "ahk_id " hwnd)
            XamlUiDiag(Format("after FIX pos=({},{}) size={}x{} visible={}"
                , x2, y2, w2, h2, DllCall("user32\IsWindowVisible", "Ptr", hwnd, "Int")), tag)
        }
        return true
    } catch as e {
        XamlUiDiag(Format("hwnd={} exists={} visible={} WinGetPos err={}", hwnd, exists, visible, e.Message), tag)
        return false
    }
}

; useAppWinTheme：是否用 AppTheme「通用窗口」色覆盖 XAML Resource（设置窗默认 true）
ApplyXamlTheme(ui, themeName, iniPath := "", useAppWinTheme := true) {
    if (iniPath == "")
        iniPath := A_WorkingDir "\Setting\themes.ini"
    if FileExist(iniPath) {
        themeData := ""
        try themeData := IniRead(iniPath, themeName)
        if (themeData != "") {
            ; 合并为一次 BatchUpdate：theme 资源 ~30 条，逐条 Update 是 30 次同步 IPC 往返（拖慢开窗）
            batch := []
            Loop Parse, themeData, "`n", "`r" {
                parts := StrSplit(A_LoopField, "=", " `t", 2)
                if (parts.Length == 2) {
                    key := Trim(parts[1])
                    val := Trim(parts[2])
                    if (key == "Window_DWM") {
                        ; 不透明窗口铺实色 BgColor，Mica 不可见且首帧闪紫：backdrop 置 0，保留 dark 模式
                        if (ui.HasProp("xaml") && InStr(ui.xaml, 'AllowsTransparency="True"'))
                            batch.Push({ControlName: "Window", PropertyName: "DWM", Value: val})
                        else {
                            dwmParts := StrSplit(val, ",", " `t")
                            dwmDark := dwmParts.Length > 1 ? dwmParts[2] : "0"
                            batch.Push({ControlName: "Window", PropertyName: "DWM", Value: "0," dwmDark})
                        }
                    }
                    else if (InStr(key, "Resource_") == 1)
                        batch.Push({ControlName: "Resource", PropertyName: SubStr(key, 10), Value: val})
                }
            }
            if (batch.Length > 0 && ui.HasMethod("BatchUpdate"))
                ui.BatchUpdate(batch)
        }
    }
    if (useAppWinTheme)
        AppThemeUtil.ApplyWinThemeToXaml(ui)
}

SetFontList() {
    MainSoftData.FontList := []
    callback := CallbackCreate(EnumFontFamilies)
    DllCall("gdi32\EnumFontFamilies", "uint", DllCall("GetDC", "uint", 0), "uint", 0, "uint", callback, "ptr", 0)
    CallbackFree(callback)

    ; Font enumeration callback
    EnumFontFamilies(lpelf, lpntm, FontType, lP) {
        if (SubStr(StrGet(lpelf + 28), 1, 1) != "@")
            MainSoftData.FontList.push(StrGet(lpelf + 28))
        return 1
    }

    if (MainSoftData.FontList.Length == 0)
        return

    DefaultFontMap := Map("微软雅黑", 0, "Arial", 0, "Consolas", 0, "SimHei", 0, "Dotum", 0, "Meiryo", 0)
    if (DefaultFontMap.Has(MainSoftData.FontType)) {
        for index, value in MainSoftData.FontList {
            if (DefaultFontMap.Has(value))
                DefaultFontMap[value] := index
        }
    }
    if (DefaultFontMap.Has(MainSoftData.FontType)) {
        if (DefaultFontMap[MainSoftData.FontType] != 0)
            return

        for key, value in DefaultFontMap {
            if (value != 0) {
                MainSoftData.FontType := key
                return
            }
        }

        MainSoftData.FontType := MainSoftData.FontList[1]
    }
}

; ============================================================
; 加载当前配置方案的所有表（动态表集合）
; 新格式：[Tables] 段 List=TableID|Symbol|Name|Order 用 π 分隔
; 旧格式：无 [Tables] 段 → 使用默认 13 表定义（每条目按旧格式迁移）
; ============================================================
LoadCurMacroSetting() {
    global MySoftData
    tableListStr := IniRead(MacroFile, "Tables", "List", "")
    migrated := false
    if (tableListStr != "") {
        ; 新格式：解析动态表集合（JSON 数组 [[ID, Symbol, Name, Order], ...]）
        ; 表身份固定 = Symbol（entry[2]）；entry[1] 若是旧动态 t_xxx 段名则记入 PersistSeg 供迁移读取
        MySoftData.TableInfo := []
        try {
            tableArr := JSON.parse(tableListStr, , false)
            if (IsObject(tableArr)) {
                for entry in tableArr {
                    if (!IsObject(entry) || entry.Length < 4)
                        continue
                    t := TableItem()
                    t.Symbol := entry[2]
                    t.ID := t.Symbol
                    t.Name := entry[3]
                    t.Order := Integer(entry[4])
                    ; 仅旧式动态段名（t_ 前缀）视为迁移源（PersistSeg）；新固定 Symbol 或 Symbol_N 多实例不做迁移
                    t.PersistSeg := (SubStr(entry[1], 1, 2) == "t_") ? entry[1] : ""
                    MySoftData.TableInfo.Push(t)
                }
            }
        } catch as e {
            ; JSON 解析失败（异常损坏）→ 回退默认表集合
            CreateTableItemArr()
        }
        if (MySoftData.TableInfo.Length == 0)
            CreateTableItemArr()
        RebuildTableLocator()
    } else {
        ; 旧格式：默认 13 表骨架（条目数据按旧格式逐表迁移）
        CreateTableItemArr()
        migrated := true
    }
    for tableItem in MySoftData.TableInfo {
        if (ReadTableItemInfo(tableItem))
            migrated := true
        EnsureTableHasFold(tableItem)
    }
    ; 仅当发生过迁移（旧格式→新格式）才落盘表集合，避免 Worker 并发写
    if (migrated)
        SaveTableCollection()
    RebuildTableLocator()
    ; 持久化的当前 tab 是 TableID（身份）：解析为显示顺序下标；无效则回落 1
    if (MainSoftData.CurTableID != "") {
        idx := GetTableIndexByID(MainSoftData.CurTableID)
        MainSoftData.TableIndex := idx > 0 ? idx : 1
    } else if (MainSoftData.TableIndex < 1 || MainSoftData.TableIndex > MySoftData.TableInfo.Length) {
        MainSoftData.TableIndex := 1
    }
}

; ============================================================
; 读取单个表的数据（tableItem 为表对象）
; 读三级段结构：[表ID]/[表ID.ModuleN]/[表ID.ModuleN.MacroM]，无三级数据则按全新表生成默认
; 返回 true 表示发生了初始化（需要落盘表集合），false 表示纯三级格式读取
; ============================================================
ReadTableItemInfo(tableItem) {
    global MySoftData
    symbol := tableItem.Symbol

    ; 非配置表（Tool/Setting/Help/Reward/Thank 等静态页）：不参与宏配置，
    ; 一律不读新/旧格式、不迁移，内存结构清空（Items/Folds 恒为空），磁盘由 SaveTableItemInfo 清空。
    if (IsStaticTable(tableItem)) {
        tableItem.Items := []
        tableItem.ItemMap := Map()
        tableItem.Folds := []
        tableItem.FoldMap := Map()
        return false
    }

    segID := tableItem.PersistSeg   ; 迁移源段名（旧 t_xxx；新格式为空）

    ; ---- 新格式检测：表段有 ModuleOrder 键，或存在 [tableID.*] 三级子段 ----
    if (HasThreeLevelData(tableItem.ID)) {
        ReadTableItemInfoNew(tableItem, tableItem.ID)
        return false
    }

    ; ---- 旧 t_xxx 迁移段检测：回退 PersistSeg ----
    if (segID != "" && HasThreeLevelData(segID)) {
        ; 旧 t_xxx 段数据仍在：按旧段名读取，并落盘迁移到固定 Symbol 段
        ReadTableItemInfoNew(tableItem, segID)
        SaveTableItemInfo(tableItem)   ; 迁移：写固定 Symbol 段
        tableItem.PersistSeg := ""     ; 迁移完成，清除迁移标记
        return true
    }

    ; ---- 全新表：初始化默认条目并落盘为三级格式 ----
    InitTableItemDefault(tableItem)
    SaveTableItemInfo(tableItem)
    return true
}

; 判断某表是否存在三级段结构数据（ModuleOrder 键或 [表ID.*] 子段）
HasThreeLevelData(tableID) {
    if (IniRead(MacroFile, tableID, "ModuleOrder", "") != "")
        return true
    return EnumerateDottedSubSegments(tableID).Length > 0
}

; 全新表：按表类型生成默认条目
InitTableItemDefault(tableItem) {
    symbol := tableItem.Symbol
    defs := GetTableItemDefaultInfo(tableItem)
    ; 非宏表（Tool/Setting/Help/Reward/Thank）无默认条目配置（ModeArr 为空串 → 0 条）
    if (defs[3] == "") {
        EnsureTableHasFold(tableItem)
        tableItem.RebuildIndex()
        return
    }
    ; 先确保有默认模块（路径身份 Normal.Module{max+1}），宏路径依赖父模块路径
    EnsureTableHasFold(tableItem)
    defaultFold := tableItem.Folds.Length > 0 ? tableItem.Folds[1] : ""
    itemCount := StrSplit(defs[3], "π").Length      ; ModeArr 决定条目数
    loop itemCount {
        item := MacroItem()
        item.ID := NewMacroPath(tableItem, defaultFold.ID)     ; 路径身份 foldSeg.Macro{max+1}
        item.FoldID := defaultFold.ID
        tableItem.Items.Push(item)
    }
    ApplyLegacyArraysToItems(tableItem, defs, [])
    ; 首次启动（从未保存过配置）：给首个条目填默认宏模板，
    ; 与旧格式迁移路径 ReadTableItemInfoLegacy 保持一致，避免首次创建 Macro_* 落盘为空
    if (!MainSoftData.HasSaved && itemCount >= 1)
        tableItem.Items[1].Macro := GetGetTableItemDefaultMacro(symbol)
    tableItem.RebuildIndex()
}

; 确保表有 ≥1 个折叠框：缺失时创建默认折叠框并把全部条目归入
; 非宏/非条目表（Tool/Setting/Help/Reward/Thank 等静态页）不参与折叠渲染，一律不加默认折叠框
EnsureTableHasFold(tableItem) {
    if (IsStaticTable(tableItem))
        return
    if (tableItem.Folds.Length > 0)
        return
    fold := MacroFold()
    fold.ID := NewModulePath(tableItem)   ; 路径身份 Normal.Module{max+1}
    fold.Remark := GetLang("RMT默认初始化配置")
    tableItem.Folds.Push(fold)
    for item in tableItem.Items
        item.FoldID := fold.ID
    tableItem.RebuildIndex()
}

; ============================================================
; 路径身份分配（纯自增不复用）：模块 = tableID.Module{max+1}；宏 = foldSeg.Macro{max+1}
; 序号自增不复用：取现有同层最大序号 + 1，基于内存现有对象扫描（首次生成时磁盘无数据，不能枚举磁盘）。
; ============================================================
NewModulePath(tableItem) {
    max := 0
    for fold in tableItem.Folds {
        n := SegTailNum(fold.ID, "Module")
        if (n > max)
            max := n
    }
    return tableItem.ID "." "Module" (max + 1)
}

NewMacroPath(tableItem, foldSeg) {
    max := 0
    for item in tableItem.Items {
        if (item.FoldID != foldSeg)
            continue
        n := SegTailNum(item.ID, "Macro")
        if (n > max)
            max := n
    }
    return foldSeg "." "Macro" (max + 1)
}

; 解析段名尾节的序号（Normal.Module3 → 3），前缀不匹配或非纯数字返回 0
SegTailNum(seg, prefix) {
    if (seg == "")
        return 0
    tail := GetSegTail(seg)
    if (SubStr(tail, 1, StrLen(prefix)) != prefix)
        return 0
    numStr := SubStr(tail, StrLen(prefix) + 1)
    return (RegExMatch(numStr, "^\d+$")) ? Integer(numStr) : 0
}

; ============================================================
; 新格式读取（三级段结构）：[TableID] / [TableID.ModuleN] / [TableID.ModuleN.MacroM]
;   [TableID]                表段：ModuleOrder=ModuleNπ...（模块显示顺序，重排不改段名）
;   [TableID.ModuleN]        模块段：MacroOrder=MacroNπ...（宏显示顺序）+ 模块字段；段名即模块身份
;   [TableID.ModuleN.MacroM] 宏段：宏字段 + Macro 实义；段名即宏身份（表内唯一路径）
;   段名序号 = 稳定身份（纯自增不复用、移动改路径），顺序由父段 Order 列表单独控制。
; ============================================================
ReadTableItemInfoNew(tableItem, segID := "") {
    tableID := (segID == "") ? tableItem.ID : segID
    tableItem.Items := []
    tableItem.ItemMap := Map()
    tableItem.Folds := []
    tableItem.FoldMap := Map()

    ; ---- 模块级：按表段 ModuleOrder 列表顺序加载 [tableID.ModuleN] 段 ----
    foldSegmentOrder := StrSplit(IniRead(MacroFile, tableID, "ModuleOrder", ""), "π")
    foldSegs := EnumerateDottedSubSegments(tableID)   ; 合法子段集合（去重确认存在）
    for foldRef in foldSegmentOrder {
        foldRef := Trim(foldRef, "`r`n ")
        if (foldRef == "")
            continue
        foldSeg := tableID "." foldRef     ; 例 Normal.Module1
        if (!HasSegment(foldSeg, foldSegs))
            continue   ; 段不存在则跳过（避免读残留）
        fold := MacroFold()
        fold.ID := foldSeg                 ; 段名即模块身份（全局唯一路径）
        fold.Remark := IniRead(MacroFile, foldSeg, "Remark", "")
        fold.FrontInfo := IniRead(MacroFile, foldSeg, "FrontInfo", "")
        fold.ForbidState := !!Integer(IniRead(MacroFile, foldSeg, "ForbidState", "0"))
        fold.FoldState := !!Integer(IniRead(MacroFile, foldSeg, "FoldState", "0"))
        fold.TKType := Integer(IniRead(MacroFile, foldSeg, "TKType", "4"))
        fold.TK := IniRead(MacroFile, foldSeg, "TK", "")
        fold.HoldTime := IniRead(MacroFile, foldSeg, "HoldTime", "500")
        fold.UnorderedTrigger := !!Integer(IniRead(MacroFile, foldSeg, "UnorderedTrigger", "0"))
        tableItem.Folds.Push(fold)
        tableItem.FoldMap[foldSeg] := fold

        ; ---- 宏级：按模块段 MacroOrder 列表顺序加载 [foldSeg.MacroM] 段 ----
        macroSegs := EnumerateDottedSubSegments(foldSeg)
        macroOrder := StrSplit(IniRead(MacroFile, foldSeg, "MacroOrder", ""), "π")
        for macroRef in macroOrder {
            macroRef := Trim(macroRef, "`r`n ")
            if (macroRef == "")
                continue
            macroSeg := foldSeg "." macroRef   ; 例 Normal.Module1.Macro1
            if (!HasSegment(macroSeg, macroSegs))
                continue
            item := MacroItem()
            item.ID := macroSeg                ; 段名即宏身份（表内唯一路径）
            item.TK := IniRead(MacroFile, macroSeg, "TK", "")
            item.HoldTime := IniRead(MacroFile, macroSeg, "HoldTime", "500")
            item.UnorderedTrigger := !!Integer(IniRead(MacroFile, macroSeg, "UnorderedTrigger", "0"))
            item.Forbid := ParseBoolInt(IniRead(MacroFile, macroSeg, "Forbid", "0"))
            item.LoopCount := IniRead(MacroFile, macroSeg, "LoopCount", "1")
            item.Remark := IniRead(MacroFile, macroSeg, "Remark", "")
            item.TriggerType := IniRead(MacroFile, macroSeg, "TriggerType", "1")
            item.TimingSerial := IniRead(MacroFile, macroSeg, "TimingSerial", "")
            item.Mode := IniRead(MacroFile, macroSeg, "Mode", "1")
            item.StartTipSound := IniRead(MacroFile, macroSeg, "StartTipSound", "1")
            item.EndTipSound := IniRead(MacroFile, macroSeg, "EndTipSound", "1")
            item.IcoPath := IniRead(MacroFile, macroSeg, "IcoPath", "")
            item.VoiceKeywords := IniRead(MacroFile, macroSeg, "VoiceKeywords", "")
            item.Macro := IniRead(MacroFile, macroSeg, "Macro", "")
            item.FoldID := foldSeg             ; 父模块路径身份
            tableItem.Items.Push(item)
            tableItem.ItemMap[macroSeg] := item
        }
    }
}

; 判断 seg 是否在 segList（已枚举的子段名数组）中
HasSegment(seg, segList) {
    for s in segList {
        if (s == seg)
            return true
    }
    return false
}

; 归一化 Forbid 布尔（兼容旧格式字符串 "0"/"1" / 布尔 / 数字）
ParseBoolInt(x) {
    return (x == true || x == "1" || x == 1) ? 1 : 0
}

; ============================================================
; 枚举某个段名前缀下的全部直接子段（不含更深的孙段），按段名最后一节的数字自然排序。
; 例：prefix="Normal" → ["Normal.Module1","Normal.Module2"]
;     prefix="Normal.Module1" → ["Normal.Module1.Macro1", ...]
; 仅返回比 prefix 多一节（不含更深层级）的段。
; ============================================================
EnumerateDottedSubSegments(prefix) {
    segs := []
    orderMap := Map()   ; 段名 -> 末节数字
    try {
        allSegs := IniRead(MacroFile)   ; 全部段名，换行分隔
        for rawLine in StrSplit(allSegs, "`n") {
            seg := Trim(rawLine, "`r`n ")
            if (seg == "" || seg == prefix)
                continue
            ; 只接受 prefix + "." + 单节（tail 不含点 = 直接子段；含点 = 更深孙段跳过）
            prefixDot := prefix "."
            if (SubStr(seg, 1, StrLen(prefixDot)) != prefixDot)
                continue
            tail := SubStr(seg, StrLen(prefixDot) + 1)
            if (InStr(tail, "."))
                continue   ; 更深层级孙段
            ; 提取末节序号（ModuleN / MacroN 的 N）
            num := 0
            if (RegExMatch(tail, "(\d+)$", &m))
                num := Integer(m[1])
            segs.Push(seg)
            orderMap[seg] := num
        }
    } catch as e {
        RMTLogSys(RMT_LV_ERROR, "EnumerateDottedSubSegments", Format("枚举 {1} 子段失败: {2}", prefix, e.Message))
    }
    ; 按末节数字自然升序
    BuildSortIndex(segs, orderMap)
    return segs
}

; 按 orderMap 提供的末节数字对 segs 做稳定升序（冒泡，量小）
BuildSortIndex(segs, orderMap) {
    n := segs.Length
    loop n - 1 {
        swapped := false
        inn := n - (A_Index - 1)
        j := 1
        while j < inn {
            if (orderMap[segs[j + 1]] < orderMap[segs[j]]) {
                tmp := segs[j]
                segs[j] := segs[j + 1]
                segs[j + 1] := tmp
                swapped := true
            }
            j++
        }
        if (!swapped)
            break
    }
}

; ============================================================
; 旧格式读取：symbol 前缀 π 拼接 + MacroArr N + FoldInfo JSON
; 解析后迁移为新格式对象结构
; ============================================================
ReadTableItemInfoLegacy(tableItem) {
    global MySoftData
    symbol := tableItem.Symbol
    defaultInfo := GetTableItemDefaultInfo(tableItem)
    savedTKArrStr := IniRead(MacroFile, IniSection, symbol "TKArr", "")
    savedModeArrStr := IniRead(MacroFile, IniSection, symbol "ModeArr", "")
    savedForbidArrStr := IniRead(MacroFile, IniSection, symbol "ForbidArr", "")
    savedRemarkArrStr := IniRead(MacroFile, IniSection, symbol "RemarkArr", "")
    savedLoopCountStr := IniRead(MacroFile, IniSection, symbol "LoopCountArr", "")
    savedHoldTimeArrStr := IniRead(MacroFile, IniSection, symbol "HoldTimeArr", "")
    savedTriggerTypeArrStr := IniRead(MacroFile, IniSection, symbol "TriggerTypeArr", "")
    savedSerialStr := IniRead(MacroFile, IniSection, symbol "SerialArr", "")
    savedTimingSerialStr := IniRead(MacroFile, IniSection, symbol "TimingSerialArr", "")
    savedStartTipSoundStr := IniRead(MacroFile, IniSection, symbol "StartTipSoundArr", "")
    savedEndTipSoundStr := IniRead(MacroFile, IniSection, symbol "EndTipSoundArr", "")
    savedIcoPathArrStr := IniRead(MacroFile, IniSection, symbol "IcoPathArr", "")
    savedUnorderedTriggerArrStr := IniRead(MacroFile, IniSection, symbol "UnorderedTriggerArr", "")
    savedVoiceKeywordsArrStr := IniRead(MacroFile, IniSection, symbol "VoiceKeywordsArr", "")
    savedFoldInfoStr := IniRead(MacroFile, IniSection, symbol "FoldInfo", "")

    ; 不存在折叠筐就初始化，并读取默认配置
    if (savedFoldInfoStr == "") {
        savedTKArrStr := defaultInfo[1]
        savedHoldTimeArrStr := defaultInfo[2]
        savedModeArrStr := defaultInfo[3]
        savedForbidArrStr := defaultInfo[4]
        savedRemarkArrStr := defaultInfo[5]
        savedLoopCountStr := defaultInfo[6]
        savedTriggerTypeArrStr := defaultInfo[7]
        savedSerialStr := defaultInfo[8]
        savedTimingSerialStr := defaultInfo[9]
        savedStartTipSoundStr := defaultInfo[10]
        savedEndTipSoundStr := defaultInfo[11]
        savedIcoPathArrStr := defaultInfo[12]
        savedUnorderedTriggerArrStr := defaultInfo[13]
        savedVoiceKeywordsArrStr := defaultInfo[14]

        defaultFoldInfo := ItemFoldInfo()
        defaultFoldInfo.RemarkArr := [GetLang("RMT默认初始化配置")]
        defaultFoldInfo.FrontInfoArr := [""]
        if (savedModeArrStr == "")
            IndexSpanValue := "无-无"
        else
            IndexSpanValue := "1-" StrSplit(savedModeArrStr, "π").Length
        defaultFoldInfo.IndexSpanArr := [IndexSpanValue]
        defaultFoldInfo.FoldStateArr := [false]
        defaultFoldInfo.ForbidStateArr := [false]

        defaultFoldInfo.TKTypeArr := [4]
        defaultFoldInfo.TKArr := [""]
        defaultFoldInfo.HoldTimeArr := [500]
        defaultFoldInfo.UnorderedTriggerArr := [false]
        savedFoldInfoStr := JSON.stringify(defaultFoldInfo, 0)
    }

    ; 解析旧数组 → 条目对象
    ; 非宏表（Tool/Setting/Help/Reward/Thank）无条目配置：ModeArr 空 → 0 条
    if (savedModeArrStr == "") {
        tableItem.Folds := []
        tableItem.FoldMap := Map()
        tableItem.Items := []
        tableItem.ItemMap := Map()
        return
    }
    itemCount := StrSplit(savedModeArrStr, "π").Length
    if (itemCount == 0)
        itemCount := 1

    oldTKArr := StrSplit(savedTKArrStr, "π")
    oldHoldTimeArr := StrSplit(savedHoldTimeArrStr, "π")
    oldModeArr := StrSplit(savedModeArrStr, "π")
    oldForbidArr := StrSplit(savedForbidArrStr, "π")
    oldRemarkArr := StrSplit(savedRemarkArrStr, "π")
    oldLoopCountArr := StrSplit(savedLoopCountStr, "π")
    oldTriggerTypeArr := StrSplit(savedTriggerTypeArrStr, "π")
    oldSerialArr := StrSplit(savedSerialStr, "π")
    oldTimingSerialArr := StrSplit(savedTimingSerialStr, "π")
    oldStartTipSoundArr := StrSplit(savedStartTipSoundStr, "π")
    oldEndTipSoundArr := StrSplit(savedEndTipSoundStr, "π")
    oldIcoPathArr := StrSplit(savedIcoPathArrStr, "π")
    oldUnorderedTriggerArr := StrSplit(savedUnorderedTriggerArrStr, "π")
    oldVoiceKeywordsArr := StrSplit(savedVoiceKeywordsArrStr, "π")

    ; 迁移折叠框：IndexSpanArr → FoldID
    oldFoldInfo := JSON.parse(savedFoldInfoStr, , false)
    Compat1_0_8F4FlodInfo(oldFoldInfo)
    mig := MigrateIndexSpanToFoldID(oldFoldInfo, itemCount)
    foldsArr := mig[1]
    itemFoldIDArr := mig[2]

    tableItem.Folds := foldsArr
    tableItem.FoldMap := Map()
    for fold in foldsArr
        tableItem.FoldMap[fold.ID] := fold

    tableItem.Items := []
    tableItem.ItemMap := Map()
    loop itemCount {
        item := MacroItem()
        item.ID := (oldSerialArr.Has(A_Index) && oldSerialArr[A_Index] != "") ? oldSerialArr[A_Index] : GetCMDSerialStr("Item")
        item.TK := oldTKArr.Has(A_Index) ? oldTKArr[A_Index] : ""
        item.HoldTime := oldHoldTimeArr.Has(A_Index) && oldHoldTimeArr[A_Index] != "" ? oldHoldTimeArr[A_Index] : 500
        item.Mode := oldModeArr.Has(A_Index) && oldModeArr[A_Index] != "" ? oldModeArr[A_Index] : 1
        item.Forbid := oldForbidArr.Has(A_Index) && oldForbidArr[A_Index] != "" ? oldForbidArr[A_Index] : 0
        item.Remark := oldRemarkArr.Has(A_Index) ? oldRemarkArr[A_Index] : ""
        item.LoopCount := oldLoopCountArr.Has(A_Index) && oldLoopCountArr[A_Index] != "" ? oldLoopCountArr[A_Index] : "1"
        item.TriggerType := oldTriggerTypeArr.Has(A_Index) && oldTriggerTypeArr[A_Index] != "" ? oldTriggerTypeArr[A_Index] : 1
        item.TimingSerial := oldTimingSerialArr.Has(A_Index) ? oldTimingSerialArr[A_Index] : ""
        item.StartTipSound := oldStartTipSoundArr.Has(A_Index) && oldStartTipSoundArr[A_Index] != "" ? oldStartTipSoundArr[A_Index] : 1
        item.EndTipSound := oldEndTipSoundArr.Has(A_Index) && oldEndTipSoundArr[A_Index] != "" ? oldEndTipSoundArr[A_Index] : 1
        item.IcoPath := oldIcoPathArr.Has(A_Index) ? oldIcoPathArr[A_Index] : ""
        item.UnorderedTrigger := oldUnorderedTriggerArr.Has(A_Index) ? (oldUnorderedTriggerArr[A_Index] == "1" || oldUnorderedTriggerArr[A_Index] == "true") : false
        item.VoiceKeywords := oldVoiceKeywordsArr.Has(A_Index) ? oldVoiceKeywordsArr[A_Index] : ""
        item.FoldID := itemFoldIDArr.Has(A_Index) ? itemFoldIDArr[A_Index] : ""
        tableItem.Items.Push(item)
        tableItem.ItemMap[item.ID] := item
    }

    ; 宏内容单独 key（旧格式：symbol"MacroArr" N）
    loop itemCount {
        str := IniRead(MacroFile, IniSection, symbol "MacroArr" A_Index, "")
        if (str == "" && !MainSoftData.HasSaved && A_Index == 1)
            str := GetGetTableItemDefaultMacro(symbol)
        else {
            str := StrReplace(str, "⫶", "`n")
        }
        tableItem.Items[A_Index].Macro := str
    }

    ; 登记条目 ID / TimingSerial 到全局序列号（防重复生成）
    for item in tableItem.Items {
        if (item.ID != "")
            SetSerialByArr([item.ID])
        if (item.TimingSerial != "")
            SetSerialByArr([item.TimingSerial])
    }
    CompatEnsureArrLength(tableItem)
}

; 把旧默认信息数组应用为条目（供全新表初始化）
ApplyLegacyArraysToItems(tableItem, defs, macroArr) {
    itemCount := StrSplit(defs[3], "π").Length
    loop itemCount {
        item := tableItem.Items[A_Index]
        item.TK := (StrSplit(defs[1], "π").Has(A_Index)) ? StrSplit(defs[1], "π")[A_Index] : ""
        item.HoldTime := (StrSplit(defs[2], "π").Has(A_Index)) ? StrSplit(defs[2], "π")[A_Index] : 500
        item.Mode := (StrSplit(defs[3], "π").Has(A_Index)) ? StrSplit(defs[3], "π")[A_Index] : 1
        item.Forbid := (StrSplit(defs[4], "π").Has(A_Index)) ? StrSplit(defs[4], "π")[A_Index] : 0
        item.Remark := (StrSplit(defs[5], "π").Has(A_Index)) ? StrSplit(defs[5], "π")[A_Index] : ""
        item.LoopCount := (StrSplit(defs[6], "π").Has(A_Index)) ? StrSplit(defs[6], "π")[A_Index] : "1"
        item.TriggerType := (StrSplit(defs[7], "π").Has(A_Index)) ? StrSplit(defs[7], "π")[A_Index] : 1
        item.TimingSerial := (StrSplit(defs[8], "π").Has(A_Index)) ? StrSplit(defs[8], "π")[A_Index] : ""
        item.StartTipSound := (StrSplit(defs[10], "π").Has(A_Index)) ? StrSplit(defs[10], "π")[A_Index] : 1
        item.EndTipSound := (StrSplit(defs[11], "π").Has(A_Index)) ? StrSplit(defs[11], "π")[A_Index] : 1
        item.IcoPath := (StrSplit(defs[12], "π").Has(A_Index)) ? StrSplit(defs[12], "π")[A_Index] : ""
        item.UnorderedTrigger := (StrSplit(defs[13], "π").Has(A_Index)) ? (StrSplit(defs[13], "π")[A_Index] == "1") : false
        item.VoiceKeywords := (StrSplit(defs[14], "π").Has(A_Index)) ? StrSplit(defs[14], "π")[A_Index] : ""
    }
}

GetGetTableItemDefaultMacro(symbol) {
    if (symbol == "Normal") {
        return "按键_a_点击_100_10_200,间隔_3000"
    }
    else if (symbol == "String")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Timing")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "SubMacro")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Replace")
        return "Left,a"
    else if (symbol == "UI")
        return "按键_a_点击_100_10_200,间隔_3000"
    else if (symbol == "Voice")
        return "按键_a_点击_100_10_200,间隔_3000"   ; 语音宏默认指令模板
    return ""
}

GetTableItemDefaultInfo(tableItem) {
    symbol := tableItem.Symbol
    savedTKArrStr := ""
    savedModeArrStr := ""
    savedForbidArrStr := ""
    savedRemarkArrStr := ""
    savedLoopCountStr := ""
    savedHoldTimeArrStr := ""
    savedTriggerTypeStr := ""
    savedSerialeArrStr := ""
    savedTimingSerialStr := ""
    savedStartTipSoundStr := ""
    savedEndTipSoundStr := ""
    savedIcoPathArrStr := ""
    savedUnorderedTriggerArrStr := ""
    savedVoiceKeywordsArrStr := ""

    if (symbol == "Normal") {
        savedTKArrStr := "k"
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("取消禁用配置才能生效")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "1"
        savedTimingSerialStr := "Timing1"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "0π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "String") {
        savedTKArrStr := ":?*:AA"
        savedHoldTimeArrStr := "0"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("按两次a触发")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "2"
        savedTimingSerialStr := "Timing2"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "Menu") {
        savedTKArrStr := "πππ"
        savedHoldTimeArrStr := "500π500π500π500"
        savedModeArrStr := "1π1π1π1"
        savedForbidArrStr := "0π0π0π0"
        savedRemarkArrStr := GetLang("快捷启动") "π" GetLang("音量调节") "π" GetLang("窗口管理") "π" GetLang("自定义")
        savedLoopCountStr := "1π1π1π1"
        savedTriggerTypeStr := "4π4π4π4"
        savedSerialeArrStr := "3π4π5π6"
        savedTimingSerialStr := "Timing3πTiming4πTiming5πTiming6"
        savedStartTipSoundStr := "1π1π1π1"
        savedEndTipSoundStr := "1π1π1π1"
        savedIcoPathArrStr := "0π0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0π0"
    }
    else if (symbol == "UI") {
        savedTKArrStr := "ππ"
        savedHoldTimeArrStr := "500π500π500"
        savedModeArrStr := "1π1π1"
        savedForbidArrStr := "1π1π1"
        savedRemarkArrStr := GetLang("界面按钮") "π" GetLang("游戏辅助") "π" GetLang("快捷入口")
        savedLoopCountStr := "1π1π1"
        savedTriggerTypeStr := "1π1π1"
        savedSerialeArrStr := "14π15π16"
        savedTimingSerialStr := "Timing14πTiming15πTiming16"
        savedStartTipSoundStr := "1π1π1"
        savedEndTipSoundStr := "1π1π1"
        savedIcoPathArrStr := "0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0"
    }
    else if (symbol == "Voice") {
        savedTKArrStr := "πππ"
        savedHoldTimeArrStr := "0π0π0"
        savedModeArrStr := "1π1π1"
        savedForbidArrStr := "1π1π1"
        savedRemarkArrStr := GetLang("语音宏示例1") "π" GetLang("语音宏示例2") "π" GetLang("语音宏示例3")
        savedLoopCountStr := "1π1π1"
        savedTriggerTypeStr := "1π1π1"
        savedSerialeArrStr := "17π18π19"
        savedTimingSerialStr := "Timing17πTiming18πTiming19"
        savedStartTipSoundStr := "1π1π1"
        savedEndTipSoundStr := "1π1π1"
        savedIcoPathArrStr := "0π0π0"
        savedUnorderedTriggerArrStr := "0π0π0"
        savedVoiceKeywordsArrStr := "你好π开始π停止"   ; 默认唤醒词
    }
    else if (symbol == "Timing") {
        savedTKArrStr := ""
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("通过定时或宏操作调用")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "9"
        savedTimingSerialStr := "Timing9"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "SubMacro") {
        savedTKArrStr := ""
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArr := GetLang("只能通过宏操作调用")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "10"
        savedTimingSerialStr := "Timing10"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    else if (symbol == "Replace") {
        savedTKArrStr := "k"
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("将k按键替换成其他按键")
        savedTriggerTypeStr := "1"
        savedLoopCountStr := "1"
        savedSerialeArrStr := "11"
        savedTimingSerialStr := "Timing11"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
        savedIcoPathArrStr := "00π"
        savedUnorderedTriggerArrStr := "0"
    }
    return [savedTKArrStr, savedHoldTimeArrStr, savedModeArrStr, savedForbidArrStr, savedRemarkArrStr,
        savedLoopCountStr, savedTriggerTypeStr, savedSerialeArrStr, savedTimingSerialStr, savedStartTipSoundStr,
        savedEndTipSoundStr, savedIcoPathArrStr, savedUnorderedTriggerArrStr, savedVoiceKeywordsArrStr]
}

; ============================================================
; 保存单个表（三级段结构）：[TableID] / [TableID.ModuleN] / [TableID.ModuleN.MacroM]
;   [TableID]                表段：ModuleOrder=ModuleNπ...（冗余调试键，顺序以枚举子段为准）
;   [TableID.ModuleN]        模块段：ID=<真实全局 f_xxx> + 模块字段
;   [TableID.ModuleN.MacroM] 宏段：ID=<真实全局 ItemN> + 宏字段 + Macro 实义
;   段名序号 ModuleN/MacroN 为层级内易读序号，真实对象 ID 存段内 ID= 键恢复全局唯一引用。
; ============================================================
; 枚举删除 INI 某段内的全部键（保留段头）。用于非配置表（静态页）在保存时清空整段，保证零配置、零残留。
WipeIniSectionKeys(filename, section) {
    allKeys := IniRead(filename, section)
    for key in StrSplit(allKeys, "`n") {
        if (key != "")
            IniDelete(filename, section, key)
    }
}

; 删除某表名前缀下的全部带点子段（[tableID.*]），供非配置表清空与孤儿清理。
WipeDottedSubSections(filename, tableID) {
    allSegs := IniRead(filename)   ; 全部段名，换行分隔
    prefixDot := tableID "."
    for rawLine in StrSplit(allSegs, "`n") {
        seg := Trim(rawLine, "`r`n ")
        if (seg == "")
            continue
        if (SubStr(seg, 1, StrLen(prefixDot)) == prefixDot)
            IniDelete(filename, seg)
    }
}

SaveTableItemInfo(tableItem) {
    tableID := tableItem.ID
    symbol := tableItem.Symbol

    ; 非配置表（Tool/Setting/Help/Reward/Thank 等静态页）：不参与宏配置，
    ; 清空本段全部键 + 全部 [tableID.*] 带点子段，保证磁盘零配置、零残留。
    if (IsStaticTable(tableItem)) {
        try {
            WipeIniSectionKeys(MacroFile, tableID)
            WipeDottedSubSections(MacroFile, tableID)
        } catch as e {
            RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", Format("清空静态表段 {1} 失败: {2}", tableID, e.Message))
        }
        return
    }

    ; ---- 模块级 + 宏级三级落盘（路径身份） ----
    ; 段名即对象身份（fold.ID = tableID.ModuleN，item.ID = foldSeg.MacroM），无独立 ID= 键。
    ; 顺序由父段 Order 列表单独控制：表段 ModuleOrder、模块段 MacroOrder（存各直属尾节）。
    ; 孤儿宏（FoldID 无匹配模块）先归入首模块，保证不丢失。
    fallbackFold := tableItem.Folds.Length > 0 ? tableItem.Folds[1] : ""
    for item in tableItem.Items {
        if ((item.FoldID == "" || !FoldIDBelongs(item.FoldID, tableItem)) && fallbackFold != "")
            item.FoldID := fallbackFold.ID
    }

    currentSegs := Map()   ; 本次写入的段名集合，用于孤儿清理
    moduleOrder := []      ; 表段 ModuleOrder：模块段尾节（ModuleN）
    for fold in tableItem.Folds {
        foldSeg := fold.ID
        if (foldSeg == "") {
            RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", "模块缺少路径身份(ID)，无法确定段名，跳过")
            continue
        }
        currentSegs[foldSeg] := true
        ; 收集模块尾节（如 Normal.Module1 → Module1）
        moduleOrder.Push(GetSegTail(foldSeg))
        IniWrite(fold.Remark,       MacroFile, foldSeg, "Remark")
        IniWrite(fold.FrontInfo,    MacroFile, foldSeg, "FrontInfo")
        IniWrite(fold.ForbidState ? 1 : 0, MacroFile, foldSeg, "ForbidState")
        IniWrite(fold.FoldState ? 1 : 0,   MacroFile, foldSeg, "FoldState")
        IniWrite(fold.TKType,       MacroFile, foldSeg, "TKType")
        IniWrite(fold.TK,           MacroFile, foldSeg, "TK")
        IniWrite(fold.HoldTime,     MacroFile, foldSeg, "HoldTime")
        IniWrite(fold.UnorderedTrigger ? 1 : 0, MacroFile, foldSeg, "UnorderedTrigger")

        macroOrder := []   ; 模块段 MacroOrder：宏段尾节（MacroN）
        for item in tableItem.Items {
            if (item.FoldID != foldSeg)
                continue   ; 宏归属按 FoldID（父路径）归入对应模块段
            macroSeg := item.ID
            if (macroSeg == "") {
                RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", Format("模块{1}内宏缺少路径身份(ID)，跳过", foldSeg))
                continue
            }
            currentSegs[macroSeg] := true
            macroOrder.Push(GetSegTail(macroSeg))
            IniWrite(item.TK,            MacroFile, macroSeg, "TK")
            IniWrite(item.HoldTime,      MacroFile, macroSeg, "HoldTime")
            IniWrite(item.Mode,          MacroFile, macroSeg, "Mode")
            IniWrite(item.Forbid ? 1 : 0, MacroFile, macroSeg, "Forbid")
            IniWrite(item.Remark,        MacroFile, macroSeg, "Remark")
            IniWrite(item.LoopCount,     MacroFile, macroSeg, "LoopCount")
            IniWrite(item.TriggerType,   MacroFile, macroSeg, "TriggerType")
            IniWrite(item.TimingSerial,  MacroFile, macroSeg, "TimingSerial")
            IniWrite(item.StartTipSound, MacroFile, macroSeg, "StartTipSound")
            IniWrite(item.EndTipSound,   MacroFile, macroSeg, "EndTipSound")
            IniWrite(item.IcoPath,       MacroFile, macroSeg, "IcoPath")
            IniWrite(item.UnorderedTrigger ? 1 : 0, MacroFile, macroSeg, "UnorderedTrigger")
            IniWrite(item.VoiceKeywords, MacroFile, macroSeg, "VoiceKeywords")
            ; 宏内容：直接存（换行用 ⫶ 编码，避免 INI 值含换行）
            MacroStr := Trim(item.Macro)
            MacroStr := Trim(MacroStr, "`n")
            MacroStr := Trim(MacroStr, ",")
            MacroStr := StrReplace(MacroStr, "`n", "⫶")
            IniWrite(MacroStr, MacroFile, macroSeg, "Macro")
        }
        IniWrite(JoinPi(macroOrder), MacroFile, foldSeg, "MacroOrder")
    }
    IniWrite(JoinPi(moduleOrder), MacroFile, tableID, "ModuleOrder")

    ; 清理孤儿 [tableID.*] 子段：删除不在当前写入集合中的段，防累积。
    try {
        allSegs := IniRead(MacroFile)
        prefixDot := tableID "."
        for rawLine in StrSplit(allSegs, "`n") {
            seg := Trim(rawLine, "`r`n ")
            if (seg == "" || SubStr(seg, 1, StrLen(prefixDot)) != prefixDot)
                continue
            if (!currentSegs.Has(seg))
                IniDelete(MacroFile, seg)
        }
    } catch as e {
        RMTLogSys(RMT_LV_ERROR, "SaveTableItemInfo", Format("清理孤儿子段失败: {1}", e.Message))
    }

    ; 清除旧格式残留 key（symbol 前缀，避免双格式并存误判）
    IniDelete(MacroFile, IniSection, symbol "TKArr")
    IniDelete(MacroFile, IniSection, symbol "ModeArr")
    IniDelete(MacroFile, IniSection, symbol "ForbidArr")
    IniDelete(MacroFile, IniSection, symbol "RemarkArr")
    IniDelete(MacroFile, IniSection, symbol "LoopCountArr")
    IniDelete(MacroFile, IniSection, symbol "HoldTimeArr")
    IniDelete(MacroFile, IniSection, symbol "TriggerTypeArr")
    IniDelete(MacroFile, IniSection, symbol "SerialArr")
    IniDelete(MacroFile, IniSection, symbol "TimingSerialArr")
    IniDelete(MacroFile, IniSection, symbol "StartTipSoundArr")
    IniDelete(MacroFile, IniSection, symbol "EndTipSoundArr")
    IniDelete(MacroFile, IniSection, symbol "IcoPathArr")
    IniDelete(MacroFile, IniSection, symbol "UnorderedTriggerArr")
    IniDelete(MacroFile, IniSection, symbol "VoiceTriggerArr")
    IniDelete(MacroFile, IniSection, symbol "VoiceKeywordsArr")
    IniDelete(MacroFile, IniSection, symbol "FoldInfo")
}

; 判断某 FoldID 是否属于本表现有模块集合
FoldIDBelongs(foldID, tableItem) {
    for fold in tableItem.Folds {
        if (fold.ID == foldID)
            return true
    }
    return false
}

; 取段名最后一节（Normal.Module1 → Module1）
GetSegTail(seg) {
    pos := InStr(seg, ".", , , -1)
    return (pos > 0) ? SubStr(seg, pos + 1) : seg
}

; 数组 π 拼接
JoinPi(arr) {
    out := ""
    for v in arr {
        if (out != "")
            out .= "π"
        out .= v
    }
    return out
}

; 保存整个表集合（[Tables] 段，动态表定义）
; 用 JSON 数组序列化，避免表名含 | / π 等分隔符导致解析错位
SaveTableCollection() {
    tableArr := []
    for tableItem in MySoftData.TableInfo {
        tableArr.Push([tableItem.ID, tableItem.Symbol, tableItem.Name, tableItem.Order])
    }
    IniWrite(JSON.stringify(tableArr, 0), MacroFile, "Tables", "List")
}

; ============================================================
; 旧格式 π 拼接序列化已废弃（新格式见 SaveTableItemInfo/ReadTableItemInfoNew）
; ============================================================

;Table信息相关
; 默认表定义（新体系：动态表集合的初始骨架）
; 每项 [Symbol, 显示名(语言键), 顺序]
CreateDefaultTableDefs() {
    return [
        ["Normal", "按键宏", 1],
        ["String", "字串宏", 2],
        ["Menu", "菜单宏", 3],
        ["UI", "界面宏", 4],
        ["Voice", "语音宏", 5],
        ["Timing", "定时宏", 6],
        ["SubMacro", "宏", 7],
        ["Replace", "按键替换", 8],
        ["Tool", "工具", 9],
        ["Setting", "设置", 10],
        ["Help", "帮助", 11],
        ["Reward", "打赏作者", 12],
        ["Thank", "特别感谢", 13]
    ]
}

CreateTableItemArr() {
    global MySoftData
    Arr := []
    defs := CreateDefaultTableDefs()
    for def in defs {
        t := TableItem()
        t.ID := def[1]      ; 表身份固定 = 表类型 Symbol（Normal/String/...），不用动态 t_xxx → 重启不漂移，段名固定
        t.Symbol := def[1]
        t.Name := def[2]
        t.Order := def[3]
        Arr.Push(t)
    }
    MySoftData.TableInfo := Arr
    RebuildTableLocator()
    return Arr
}

InitTableItemState() {
    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        InitSingleTableState(tableItem)
    }

    tableItem := MySoftData.SpecialTableItem
    if (tableItem.Items.Length == 0) {
        item := MacroItem()
        item.ID := GetCMDSerialStr("Item")
        tableItem.Items.Push(item)
        tableItem.RebuildIndex()
    }
    InitSingleTableState(tableItem)
}

; 运行时状态随条目对象初始化（每条目一个状态，增删条目不破坏其它条目）
InitSingleTableState(tableItem) {
    ; 内置控制键统一默认值（缺失才补，兼容已有运行态映射）
    static CtlKeys := Map(
        "宏循环次数", 0,
        "循环-跳过本轮", false,
        "循环-跳出", false,
        "分支-跳出", false
    )
    for item in tableItem.Items {
        if (!item.HoldKey)
            item.HoldKey := Map()
        ; 注意：空 Map() 也是真值，不能只用 !item.VariableMap 判断缺失键
        if (!ObjHasOwnProp(item, "VariableMap"))   ;属性未创建
            item.VariableMap := Map()
        for key, def in CtlKeys {
            if (!item.VariableMap.Has(key))
                item.VariableMap[key] := def
        }
    }
}

KillSingleTableMacro(tableItem) {
    for index, item in tableItem.Items {
        KillTableItemMacro(tableItem, index)
    }
}

; 松开宏项仍按住的按键（不修改 Killed）
ReleaseTableItemHoldKeys(tableItem, index) {
    item := tableItem.Items[index]
    if (!item || !item.HoldKey || item.HoldKey.Count == 0)
        return
    HoldKeyMap := item.HoldKey.Clone()
    GraphPoolLog("ReleaseHoldKeys", Format("tab={1} item={2} count={3} keys=[{4}]"
        , tableItem.ID, item.ID, HoldKeyMap.Count, HoldKeyMap.Count ? "..." : ""))
    for key, value in HoldKeyMap {
        if (value == "Game") {
            SendGameModeKey(key, 0, tableItem, index)
        }
        else if (value == "Normal") {
            SendNormalKey(key, 0, tableItem, index)
        }
        else if (value == "Logic") {
            SendLogicKey(key, 0, tableItem, index)
        }
        else if (value == "AHI") {
            SendAHIKey(key, 0, tableItem, index)
        }
        else if (value == "Joy") {
            SendJoyBtnKey(key, 0, tableItem, index)
        }
        else if (value == "JoyAxis") {
            SendJoyAxisKey(key, 0, tableItem, index)
        }
        else if (value == "JoyDpad") {
            SendJoyDpadKey(key, 0, tableItem, index)
        }
        else if (value == "GameMouse") {
            SendGameMouseKey(key, 0, tableItem, index)
        }
    }
    item.HoldKey := Map()
}

; Worker 同步过来的按键按住状态（供主进程强杀后松开）
; Worker 同步按键按住状态（供主进程强杀后松开）：tableID/itemID 字符串
SyncWorkerHoldKey(tableID, itemID, key, state, source := "") {
    tableItem := GetTableByID(String(tableID))
    if (!tableItem)
        return
    itemIndex := GetItemIndexInTable(tableItem, String(itemID))
    item := tableItem.Items[itemIndex]
    if (!item || !item.HoldKey)
        return
    bucket := item.HoldKey
    if (Integer(state)) {
        if (source != "")
            bucket[key] := source
    } else if (bucket.Has(key)) {
        bucket.Delete(key)
    }
}

KillTableItemMacro(tableItem, index) {
    item := tableItem.Items[index]
    if (!item)
        return
    GraphPoolLog("KillTableItemMacro", Format("tab={1} item={2} trig={3}", tableItem.ID, item.ID
        , item.TriggerType))
    item.Killed := true
    ReleaseTableItemHoldKeys(tableItem, index)

    ; 如果是开关型按键宏，重置其开关状态
    if (item.TriggerType == 4) {
        item.ToggleState := false
    }
}

GetTabHeight() {
    maxY := 0
    loop MySoftData.TableInfo.Length {
        posY := MySoftData.TableInfo[A_Index].UnderPosY
        if (posY > maxY)
            maxY := posY
    }

    height := maxY - MainSoftData.TabPosY
    return height
    ; return Max(height, 500)
}

UpdateUnderPosY(tableIndex, value) {
    table := MySoftData.TableInfo[tableIndex]
    table.UnderPosY += value
}

GetTableSymbol(index) {
    global MySoftData
    t := MySoftData.TableInfo[index]
    return t ? t.Symbol : ""
}

; 按表 Symbol 返回第一个匹配表的显示顺序下标（1 基；找不到返回 0）
GetTimingTableIndex() {
    global MySoftData
    for i, t in MySoftData.TableInfo {
        if (t.Symbol == "Timing")
            return i
    }
    return ""
}

; 按 Symbol 或表名返回显示顺序下标（1 基；找不到返回 0）
GetTableIndex(SymbolOrName) {
    global MySoftData
    for i, t in MySoftData.TableInfo {
        if (SymbolOrName == t.Name || SymbolOrName == t.Symbol)
            return i
    }
    return 0
}

; 判断某个 Symbol 是否为参与宏的条目类型（与 CheckIsItemTable(index) 同集合，但直接按 Symbol 判定，
; 不依赖 tableItem.Index 走 GetTableIndexByID 的定位，避免在表集合尚未完全构建／表索引错位时误判）。
IsItemSymbol(symbol) {
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "Replace")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    return false
}

; 是否静态/非配置表（Tool/Setting/Help/Reward/Thank 等 非 CheckIsItemSymbol）：不参与宏配置。
; 用于 ReadTableItemInfo / SaveTableItemInfo / EnsureTableHasFold 在读写入口统一短路。
IsStaticTable(tableItem) {
    if (!IsObject(tableItem) || !tableItem.HasProp("Symbol"))
        return true
    return !IsItemSymbol(tableItem.Symbol)
}

CheckIsNormalTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    return false
}

CheckIsItemTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "Replace")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    return false
}

CheckIsMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Normal")
        return true
    if (symbol == "String")
        return true
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    return false
}

CheckIsStringMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "String")
        return true
    return false
}

CheckIsTimingMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Timing")
        return true
    return false
}

CheckIsMenuMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "Menu")
        return true
    return false
}

InitArray(tableItem, arrName) {
    if (!tableItem.HasProp(arrName)) {
        tableItem.%arrName% := []
    }
}

CheckIsNoTriggerKey(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
        return true
    if (symbol == "UI")
        return true
    if (symbol == "Voice")
        return true
    return false
}

CheckIsSubMacroTable(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "SubMacro")
        return true
    return false
}

CheckIsNormalHotKey(key) {
    if (SubStr(key, 1, 1) == ":")
        return false

    if (InStr(key, "Joy"))
        return false

    if (InStr(key, "XButton"))
        return false

    if (InStr(key, "Wheel"))
        return false

    if (InStr(key, "Button"))
        return false

    if (MySoftData.SpecialKeyMap.Has(key))
        return false

    return true
}

GetHotKeyCtrlType(key) {
    isHotKey := CheckIsNormalHotKey(key)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    return CtrlType
}

; AHK 热键符号转可读显示：!p → Alt+P，^+a → Ctrl+Shift+A
FormatHotkeyDisplay(key) {
    key := Trim(String(key))
    if (key == "")
        return ""
    ; 字串触发等非标准热键原样显示
    if (SubStr(key, 1, 1) == ":")
        return key
    if (InStr(key, " & ")) {
        parts := StrSplit(key, " & ")
        out := ""
        for idx, part in parts {
            if (idx > 1)
                out .= " + "
            out .= FormatHotkeyDisplay(Trim(part))
        }
        return out
    }

    rest := key
    mods := []
    ; 左右修饰键需优先于单字符前缀匹配
    prefixes := [
        {p: "<^", n: "LCtrl"}, {p: ">^", n: "RCtrl"}, {p: "^", n: "Ctrl"},
        {p: "<!", n: "LAlt"}, {p: ">!", n: "RAlt"}, {p: "!", n: "Alt"},
        {p: "<+", n: "LShift"}, {p: ">+", n: "RShift"}, {p: "+", n: "Shift"},
        {p: "<#", n: "LWin"}, {p: ">#", n: "RWin"}, {p: "#", n: "Win"}
    ]
    loop {
        matched := false
        for item in prefixes {
            plen := StrLen(item.p)
            if (SubStr(rest, 1, plen) == item.p) {
                mods.Push(item.n)
                rest := SubStr(rest, plen + 1)
                matched := true
                break
            }
        }
        if (!matched)
            break
    }

    if (SubStr(rest, 1, 1) == "~")
        rest := SubStr(rest, 2)
    if (SubStr(rest, 1, 1) == "*")
        rest := SubStr(rest, 2)

    mainKey := rest
    if (StrLen(mainKey) == 1)
        mainKey := StrUpper(mainKey)

    result := ""
    for modName in mods {
        if (result != "")
            result .= "+"
        result .= modName
    }
    if (mainKey != "") {
        if (result != "")
            result .= "+"
        result .= mainKey
    }
    return result
}

CheckContainText(source, text) {
    ; 返回布尔值：true 表示包含，false 表示不包含
    return RegExMatch(source, text)
}

GetMatchCoord(screenTextObj, x1, y1) {
    value := screenTextObj
    pointX := value.boxPoint[1].x + value.boxPoint[2].x + value.boxPoint[3].x + value.boxPoint[4].x
    pointY := value.boxPoint[1].y + value.boxPoint[2].y + value.boxPoint[3].y + value.boxPoint[4].y
    OutputVarX := x1 + pointX / 4
    OutputVarY := y1 + pointY / 4
    return [OutputVarX, OutputVarY]
}

IsClipboardText() {
    ; 检查是否存在文本格式
    if DllCall("IsClipboardFormatAvailable", "UInt", 1)  ; CF_TEXT = 1
        return true
    if DllCall("IsClipboardFormatAvailable", "UInt", 13) ; CF_UNICODETEXT = 13
        return true
    return false
}

;没必要删除
ClearUselessSetting(deleteMacro) {
    if (deleteMacro == "")
        return
    RegExMatch(deleteMacro, "(Compare\d+)", &match)
    match := match != "" ? match : []
    for id, value in match {
        if (value == "")
            continue
        IniDelete(CompareFile, IniSection, value)
    }

    RegExMatch(deleteMacro, "(Coord\d+)", &match)
    match := match != "" ? match : []
    for id, value in match {
        if (value == "")
            continue
        IniDelete(MMPROFile, IniSection, value)
    }
}

CheckIfHasModifyKey(keyCombo) {
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    for prefix in modPrefixes {
        if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
            return true
        }
    }
    return false
}

IsComboKey(keyCombo) {
    return InStr(keyCombo, " & ")
}

; 是否为修饰键名（含左右侧）
IsModifierKeyName(keyName) {
    static ModMap := Map(
        "Ctrl", 1, "LCtrl", 1, "RCtrl", 1, "Control", 1, "LControl", 1, "RControl", 1,
        "Alt", 1, "LAlt", 1, "RAlt", 1,
        "Shift", 1, "LShift", 1, "RShift", 1,
        "Win", 1, "LWin", 1, "RWin", 1)
    return ModMap.Has(keyName)
}

; 模拟松开指定按键
ReleaseKeyByName(key) {
    if (key == "" || key == "None")
        return
    ; 泛化 Ctrl/Alt/Shift/Win：映射到左右键，但只松开实际按下的一侧
    ; 注意：不可对未按下的 RAlt 发 KEYUP——RAlt(AltGr) 在许多布局下等价于 Ctrl+Alt，会冒出幽灵 Ctrl
    keys := []
    switch key {
        case "Ctrl", "Control":
            keys := ["LCtrl", "RCtrl"]
        case "LControl":
            keys := ["LCtrl"]
        case "RControl":
            keys := ["RCtrl"]
        case "Alt":
            keys := ["LAlt", "RAlt"]
        case "Shift":
            keys := ["LShift", "RShift"]
        case "Win":
            keys := ["LWin", "RWin"]
        default:
            keys := [key]
    }
    for k in keys {
        if (!GetKeyState(k, "P"))
            continue
        try {
            VK := GetKeyVK(k)
            SC := GetKeySC(k)
            flags := 0x2  ; KEYEVENTF_KEYUP
            if (k == "RAlt" || k == "RCtrl")
                flags |= 0x1  ; KEYEVENTF_EXTENDEDKEY
            DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", flags, "UPtr", 0)
        }
    }
}

; 触发宏前松开组合键中的修饰键（支持 ^a 与 Ctrl & A 两种格式）
LoosenModifyKey(keyCombo) {
    keyCombo := Trim(String(keyCombo))
    keyCombo := LTrim(keyCombo, "~")
    if (keyCombo == "")
        return

    ; 新格式：Ctrl & A / LShift & F1
    if (InStr(keyCombo, " & ")) {
        for part in StrSplit(keyCombo, " & ") {
            name := LTrim(Trim(part), "~")
            if (IsModifierKeyName(name))
                ReleaseKeyByName(name)
        }
        return
    }

    ; 旧格式：^a / <+!b
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                keyCombo := SubStr(keyCombo, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    for mod in modifiers {
        key := ""
        switch mod {
            case "^": key := "Ctrl"
            case "<^": key := "LCtrl"
            case ">^": key := "RCtrl"
            case "!": key := "Alt"
            case "<!": key := "LAlt"
            case ">!": key := "RAlt"
            case "+": key := "Shift"
            case "<+": key := "LShift"
            case ">+": key := "RShift"
            case "#": key := "Win"
            case "<#": key := "LWin"
            case ">#": key := "RWin"
        }
        if (key != "")
            ReleaseKeyByName(key)
    }
}

; 检查单个物理键是否按下（含手柄键）
IsPhysicalKeyPressed(mainKey) {
    mainKey := LTrim(Trim(mainKey), "~")
    if (mainKey == "")
        return true

    isJoyKey := RegExMatch(mainKey, "Joy")
    if (isJoyKey) {
        isJoyAxis := RegExMatch(mainKey, "Min") || RegExMatch(mainKey, "Max")
        joyName := isJoyAxis ? SubStr(mainKey, 1, 4) : mainKey
        loop 4 {
            if (GetKeyState(A_Index joyName))
                return true
        }
        return false
    }
    return !!GetKeyState(mainKey, "P")
}

AreKeysPressed(keyCombo) {
    keyCombo := LTrim(Trim(String(keyCombo)), "~")
    if (keyCombo == "")
        return false

    ; 新格式：Ctrl & A
    if (InStr(keyCombo, " & ")) {
        for part in StrSplit(keyCombo, " & ") {
            if (!IsPhysicalKeyPressed(part))
                return false
        }
        return true
    }

    ; 旧格式：^a / <+!b
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(keyCombo, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                keyCombo := SubStr(keyCombo, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    mainKey := keyCombo
    for mod in modifiers {
        switch mod {
            case "^": if (!GetKeyState("Ctrl"))
                return false
            case "<^": if !GetKeyState("LCtrl")
                return false
            case ">^": if !GetKeyState("RCtrl")
                return false
            case "!": if !(GetKeyState("Alt"))
                return false
            case "<!": if !GetKeyState("LAlt")
                return false
            case ">!": if !GetKeyState("RAlt")
                return false
            case "+": if !(GetKeyState("Shift"))
                return false
            case "<+": if !GetKeyState("LShift")
                return false
            case ">+": if !GetKeyState("RShift")
                return false
            case "#": if (!GetKeyState("LWin") && !GetKeyState("RWin"))
                return false
            case "<#": if !GetKeyState("LWin")
                return false
            case ">#": if !GetKeyState("RWin")
                return false
            default: return false
        }
    }

    if (mainKey == "")
        return true
    return IsPhysicalKeyPressed(mainKey)
}

GetRecordTriggerKeyMap() {
    triggerKey := MainSoftData.ToolRecordMacroHotKey
    ; 初始化存储修饰键的数组
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]

    ; 检查是否以修饰键开头
    loop {
        hasAdd := false
        for prefix in modPrefixes {
            if (SubStr(triggerKey, 1, StrLen(prefix)) == prefix) {
                modifiers.Push(prefix)
                triggerKey := SubStr(triggerKey, StrLen(prefix) + 1)
                hasAdd := true
                break
            }
        }
        if (!hasAdd)
            break
    }

    ; 剩余部分是主键
    resultMap := Map()
    if (triggerKey != "")
        resultMap.Set(triggerKey, 0)

    for index, value in modifiers {
        if (value == "^" || value == "<^" || value == ">^") {
            resultMap.Set("Ctrl", 0)
            resultMap.Set("LCtrl", 0)
            resultMap.Set("RCtrl", 0)
        }

        if (value == "!" || value == "<!" || value == ">!") {
            resultMap.Set("Alt", 0)
            resultMap.Set("LAlt", 0)
            resultMap.Set("RAlt", 0)
        }

        if (value == "+" || value == "<+" || value == ">+") {
            resultMap.Set("Shift", 0)
            resultMap.Set("LShift", 0)
            resultMap.Set("RShift", 0)
        }

        if (value == "#" || value == "<#" || value == ">#") {
            resultMap.Set("Win", 0)
            resultMap.Set("LWin", 0)
            resultMap.Set("RWin", 0)
        }
    }

    return resultMap
}

StrToHex(str) {
    hex := ""
    loop parse str {
        hex .= Format("{:02X}", Ord(A_LoopField))
    }
    return hex
}

GetWinPos(ScreenX, ScreenY, hwnd := 0) {
    WinX := 0
    WinY := 0
    DllCall("SetProcessDPIAware")
    if (hwnd == 0) {
        hwnd := DllCall("User32\WindowFromPoint", "int64", (ScreenY << 32) | (ScreenX & 0xFFFFFFFF), "ptr")
    }
    try {

        ; 获取该窗口的主窗口（避免偏移）
        GA_ROOT := 2
        rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", GA_ROOT, "ptr")

        ; 创建结构体 POINT
        pt := Buffer(8, 0)
        NumPut("int", ScreenX, pt, 0)  ; X
        NumPut("int", ScreenY, pt, 4)  ; Y

        ; 屏幕坐标转客户区
        DllCall("User32\ScreenToClient", "ptr", rootHwnd, "ptr", pt)

        WinX := NumGet(pt, 0, "int")
        WinY := NumGet(pt, 4, "int")
    }
    return [WinX, WinY]
}

GetCurWinPos() {
    CoordMode("Mouse", "Screen")
    MouseGetPos &mouseX, &mouseY
    return GetWinPos(mouseX, mouseY)
}

; 高效的序列号拆分函数：一次遍历同时提取文本和数字部分（避免2次RegExReplace）
SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly) {
    textOnly := ""
    numbersOnly := ""
    loop parse serialStr {
        ch := A_LoopField
        if (IsInteger(ch))
            numbersOnly .= ch
        else
            textOnly .= ch
    }
}

GetMacroCMDData(serialStr) {
    if (MySoftData.DataCacheMap.Has(serialStr)) {
        return MySoftData.DataCacheMap[serialStr]
    }

    ; 优化：使用单次遍历拆分（替代2次RegExReplace）
    SplitSerialTextAndNumbers(serialStr, &textOnly, &numbersOnly)
    cmd := GetLangKey(textOnly)

    ; Normalize key if needed (though the cache check above might already cover common cases if they were stored with original key)
    ; But here we reconstruct it using 'cmd' which might be different if 'GetLangKey' changes it.
    ; NOTE: The original code reconstructed 'serialStr' using the translated 'cmd' + numbers.
    ; This implies the cache key used is the TRANSLATED one.

    normalizedSerialStr := Format("{}{}", cmd, numbersOnly)

    ; Check cache again with normalized key if different
    if (normalizedSerialStr != serialStr && MySoftData.DataCacheMap.Has(normalizedSerialStr)) {
        return MySoftData.DataCacheMap[normalizedSerialStr]
    }

    DataFile := MySoftData.DataFileMap[cmd]
    DataClass := MySoftData.DataClassMap[cmd]
    saveStr := IniRead(DataFile, IniSection, normalizedSerialStr, "")
    if (saveStr == "") {
        Data := DataClass()
        Data.SerialStr := SerialStr
    }
    else {
        Data := JSON.parse(saveStr, , false)
    }
    ; 旧配置「运行」可能缺 Mode 等字段，读入时补齐
    if (cmd == "运行")
        CompatEnsureRunData(Data)
    MySoftData.DataCacheMap.Set(normalizedSerialStr, Data)

    ; Also cache the original key if they differ, so next time we hit the fast path at the top
    if (normalizedSerialStr != serialStr) {
        MySoftData.DataCacheMap.Set(serialStr, Data)
    }

    return Data
}

SaveMacroCMDData(Data) {
    ; 优化：使用单次遍历拆分（替代RegExReplace）
    dummyNumbers := ""
    SplitSerialTextAndNumbers(Data.SerialStr, &cmd, &dummyNumbers)
    cmdKey := GetLangKey(cmd)
    if (!MySoftData.DataFileMap.Has(cmdKey))
        cmdKey := cmd
    DataFile := MySoftData.DataFileMap[cmdKey]

    saveStr := JSON.stringify(Data, 0)
    IniWrite(saveStr, DataFile, IniSection, Data.SerialStr)
    ; 清掉原串与规范化键，避免中英文序列码双缓存导致读到旧对象（勾选未回显）
    if (MySoftData.DataCacheMap.Has(Data.SerialStr))
        MySoftData.DataCacheMap.Delete(Data.SerialStr)
    normalizedSerialStr := Format("{}{}", cmdKey, dummyNumbers)
    if (normalizedSerialStr != Data.SerialStr && MySoftData.DataCacheMap.Has(normalizedSerialStr))
        MySoftData.DataCacheMap.Delete(normalizedSerialStr)
}

GetReplaceVarText(tableItem, tableIndex, text) {
    matches := []      ; 存储变量名（不含花括号）
    arrayMatches := [] ; 存储数组名（不含花括号和ε）
    pos := 1

    ; 匹配 {xxx} 或 {εxxx}
    while (pos := RegExMatch(text, "\{([^{}]*?)\}", &match, pos)) {
        content := match[1]
        if (RegExMatch(content, "^ε(.+)$", &arrMatch)) {     ; 以ε开头 -> 数组
            arrayMatches.Push(arrMatch[1])
        } else {        ; 普通变量
            matches.Push(content)
        }
        pos += match.Len
    }

    ResText := text
    ; 替换普通变量
    for index, value in matches {
        hasValue := TryGetTabVarValue(&variValue, tableItem, tableIndex, value, true)
        if (hasValue)
            ResText := StrReplace(ResText, "{" value "}", variValue)
    }

    ; 替换数组变量（去掉花括号和ε）
    for index, arrName in arrayMatches {
        if (MySoftData.ArrayMap.Has(arrName)) {
            arrValue := GetArrayStr(MySoftData.ArrayMap[arrName])
            ResText := StrReplace(ResText, "{ε" arrName "}", arrValue)
        }
    }

    return ResText
}

; ──────────────────────────────────────────────────────────────────────
; 解析變量並執行實際替換（作用於「存儲格式」文字）
;
;   1. {var} -> var值
;   2. /{    -> {
;   3. /}    -> }
; ──────────────────────────────────────────────────────────────────────
GetSmartReplaceVarText(tableItem, index, &text) {
    static ESC_L := Chr(0xE001)
    static ESC_R := Chr(0xE002)

    ; 先保護字面量花括號
    text := StrReplace(text, "/{", ESC_L)
    text := StrReplace(text, "/}", ESC_R)

    result := ""
    pos := 1
    len := StrLen(text)

    while (pos <= len) {
        openPos := InStr(text, "{", false, pos)

        if (!openPos) {
            result .= SubStr(text, pos)
            break
        }

        ; 加入 { 前面的文字
        if (openPos > pos)
            result .= SubStr(text, pos, openPos - pos)

        ; 找對應的 }
        closePos := InStr(text, "}", false, openPos + 1)

        if (!closePos) {
            ; 沒有完整的 {xxx}，原樣保留後面內容
            result .= SubStr(text, openPos)
            break
        }

        varName := SubStr(text, openPos + 1, closePos - openPos - 1)
        varValue := ""

        ; 直接使用 TryGetTabVarValue
        if (TryGetTabVarValue(&varValue, tableItem, index, varName, true)) {
            result .= varValue
        } else {
            ; 非變量，原樣保留
            result .= SubStr(text, openPos, closePos - openPos + 1)
        }

        pos := closePos + 1
    }

    ; 還原一般花括號
    result := StrReplace(result, ESC_L, "{")
    result := StrReplace(result, ESC_R, "}")

    text := result
}

TryGetVarValue(&Value, varName, variTip := true, tableVarMap := Map()) {

    if (RegExMatch(varName, "^[0-9A-Fa-f]{6}$")) {
        Value := varName
        return true
    }

    if (IsNumber(varName)) {
        Value := Number(varName)
        return true
    }

    switch varName {
        case "当前鼠标坐标X", "当前鼠标坐标Y":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            Value := varName == "当前鼠标坐标X" ? mouseX : mouseY
            return true
        case "当前日期":
            Value := FormatTime(A_Now, "yyyy-MM-dd")
            return true
        case "当前时间":
            Value := FormatTime(A_Now, "HH:mm")
            return true
        case "当前时间(秒)":
            Value := FormatTime(A_Now, "HH:mm:ss")
            return true
        case "当前秒":
            Value := A_Sec
            return true
        case "当前星期几":
            Value := A_WDay == 1 ? 7 : A_WDay - 1
            return true
        case "当前鼠标颜色":
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            Value := StrReplace(Color, "0x", "")
            return true
        case "句柄ID":
            winId := 0
            try {
                CoordMode("Mouse", "Screen")
                MouseGetPos &mouseX, &mouseY, &winId
            }
            Value := winId
            return true
    }

    if (tableVarMap.Has(varName)) {
        Value := tableVarMap[varName]
        return true
    }

    GlobalVariableMap := MySoftData.VariableMap
    if (GlobalVariableMap.Has(varName)) {
        Value := GlobalVariableMap[varName]
        return true
    }

    if (variTip)
        ShowNoVariableTip(varName)
    return false
}

TryGetTabVarValue(&Value, tableItem, index, varName, variTip := true) {
    item := tableItem.Items[index]
    if (!item)
        return false
    return TryGetVarValue(&Value, varName, variTip, item.VariableMap)
}

ShowNoVariableTip(VarName) {
    if (MainSoftData.NoVariableTip) {
        str1 := GetLang("当前环境不存在变量") VarName
        str2 := Format(GetLang("tip1:请确保有创建变量-{}的相关指令"), VarName)
        str3 := Format(GetLang("tip2:请确保上述指令运行过"))
        RMTErrorShow(Format("{}`n{}`n{}", str1, str2, str3), RMT_LV_WARN, "宏")
    }
}

GetRandomStr(length) {
    result := Random(1, 9)
    loop length {
        if (A_Index + 1 > length)
            break

        result .= Random(0, 9)
    }
    return result
}

WaitIfPaused(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    while (item.Pause) {
        if (item.Killed)
            break

        Sleep(200)
    }
}

; 可中断休眠：间隔内定期检查暂停/终止
InterruptibleSleep(tableItem, index, duration) {
    if (duration <= 0)
        return
    item := tableItem.Items[index]
    curTime := 0
    clip := Min(100, duration)
    while (curTime < duration) {
        WaitIfPaused(tableItem, index)
        if (item && item.Killed)
            break
        Sleep(clip)
        curTime += clip
        clip := Min(500, duration - curTime)
    }
}

; ============================================================
; 折叠归属辅助（对象化）：条目通过 item.FoldID 归属折叠框
; ============================================================
; 条目所属折叠框下标（1 基；无归属或找不到返回 0）
GetItemFoldIndex(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item || item.FoldID == "")
        return 0
    return GetFoldIndexInTable(tableItem, item.FoldID)
}

; 统一获取某项的所有Fold信息（对象化：条目 FoldID → 折叠框）
GetItemFoldData(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item || item.FoldID == "")
        return { foldIndex: 0, forbidState: false, frontInfo: "", offset: 1 }

    for Index, fold in tableItem.Folds {
        if (fold.ID == item.FoldID) {
            return {
                foldIndex: Index,
                forbidState: fold.ForbidState,
                frontInfo: fold.FrontInfo,
                offset: 1
            }
        }
    }
    return { foldIndex: 0, forbidState: false, frontInfo: "", offset: 1 }
}

GetItemFoldForbidState(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).forbidState
}

GetItemFrontInfo(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).frontInfo
}

GetItemOffsetOfFold(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).offset
}

CustomMsgBox(Text := "", Title := "", Buttons := "") {
    Result := -1

    ; 解析按钮字符串
    ButtonArray := StrSplit(Buttons, "|")
    ButtonCount := ButtonArray.Length

    ; 创建 GUI
    MyGui := Gui()
    MyGui.SetFont("S10 W550 Q2", MainSoftData.FontType)
    MyGui.Title := Title
    MyGui.OnEvent("Close", GuiClose)
    MyGui.OnEvent("Escape", GuiClose)

    ; 添加提示文本（支持多行）
    MyGui.Add("Text", "w360 Center", Text)

    ; 动态创建按钮 - 统一 Y 坐标；按文案略增宽，避免「强行切换」等被裁切
    ButtonWidth := 80
    for btnText in ButtonArray
        ButtonWidth := Max(ButtonWidth, StrLen(btnText) * 14 + 16)
    ButtonHeight := 30
    ButtonSpacing := 10
    ButtonY := 55

    TotalWidth := (ButtonWidth * ButtonCount) + (ButtonSpacing * (ButtonCount - 1))
    dialogW := Max(380, TotalWidth + 40)
    StartX := (dialogW - TotalWidth) // 2

    loop ButtonCount {
        CurrentX := StartX + (ButtonWidth + ButtonSpacing) * (A_Index - 1)
        Btn := MyGui.Add("Button", "w" ButtonWidth " h" ButtonHeight " x" CurrentX " y" ButtonY, ButtonArray[A_Index])
        Btn.OnEvent("Click", ButtonClicked.Bind(A_Index))
    }

    ; 显示 GUI 并等待
    MyGui.Show("w" dialogW)

    ; 等待用户选择
    while Result == -1
        Sleep(50)

    return Result

    ; 按钮点击事件
    ButtonClicked(Index, Ctrl, Info) {
        Result := Index
        MyGui.Destroy()
    }

    ; 关闭 GUI 事件
    GuiClose(*) {
        Result := 0
        MyGui.Destroy()
    }
}

IncrementText(strArr, str) {
    str := IncrementTextNumber(str)
    for curStr in strArr {
        if (str == curStr)
            return IncrementText(strArr, str)
    }
    return str
}

IncrementTextNumber(str) {
    ; 使用正则表达式匹配文本+数字的模式
    if (RegExMatch(str, "^(.*?)(\d+)$", &match)) {
        ; 如果匹配成功，提取文本部分和数字部分
        textPart := match[1]
        numberPart := match[2]

        ; 将数字部分转换为整数并加1
        newNumber := Integer(numberPart) + 1

        ; 返回文本+新数字
        return textPart . newNumber
    }
    else {
        ; 如果没有数字部分，直接在后面添加"1"
        return str . "1"
    }
}

;macroState 1start 2end
HandTipSound(tableItem, itmeIndex, macroState, isFirst, isLast) {
    item := tableItem.Items[itmeIndex]
    if (!item)
        return
    if (macroState == 1) {
        if (item.StartTipSound == 1)
            return

        if (item.StartTipSound == 2) {
            PlayTipSound(1)
            return
        }

        if (item.StartTipSound == 3 && isFirst) {
            PlayTipSound(1)
            return
        }
    }

    if (macroState == 2) {
        if (item.EndTipSound == 1)
            return

        if (item.EndTipSound == 2) {
            PlayTipSound(2)
            return
        }

        if (item.EndTipSound == 3 && isLast) {
            PlayTipSound(2)
            return
        }
    }
}

;type 1 开始   2结束
PlayTipSound(type) {
    audioPathMap := Map(1, StartTipAudio, 2, EndTipAudio)
    if (audioPathMap.Has(type) && FileExist(audioPathMap[type])) {
        SoundPlay(audioPathMap[type])
    }
}

GetExVariableActiveLength(Arr) {
    Length := Arr.Length
    loop Arr.Length {
        index := Arr.Length - A_Index + 1
        if (Arr[index] == 0 || Arr[index] == false) {
            Length--
            continue
        }
        break
    }
    return Length
}

GetItemColorValue(state) {
    ColorMap := Map(0, "", 1, "Images\Soft\GreenColor.png", 2, "Images\Soft\YellowColor.png", 3,
        "Images\Soft\RedColor.png")

    if (ColorMap.Has(state))
        return ColorMap[state]

    return ""
}

GetItemColorState(ColorValue) {
    ColorMap := Map("", 0, "Images\Soft\GreenColor.png", 1, "Images\Soft\YellowColor.png", 2,
        "Images\Soft\RedColor.png", 3)

    if (ColorMap.Has(ColorValue))
        return ColorMap[ColorValue]

    return 0
}

GetCmdStr(param) {
    param := StrReplace(param, "🚫", "")
    param := StrReplace(param, "⭐", "")
    return param
}

GetCmdSymbol(cmd) {
    ; 优化：使用InStr替代RegExMatch（单字符匹配更快）
    IsSkip := InStr(cmd, "🚫")
    IsDebug := InStr(cmd, "⭐")
    SkipStr := IsSkip ? "🚫" : ""
    DebugStr := IsDebug ? "⭐" : ""
    Symbol := Format("{}{}", SkipStr, DebugStr)
    return Symbol
}

GetCmdOnlyText(param) {
    param := GetCmdStr(param)
    ; 优化：使用单次遍历拆分（替代RegExReplace）
    dummyNumbers := ""
    SplitSerialTextAndNumbers(param, &textOnly, &dummyNumbers)
    return textOnly
}

SetDLConValue(Con, Arr, Text) {
    Con.Delete()
    Con.Add(Arr)
    if (Con.Type == "ComboBox") {
        Con.Text := Text
        return
    }

    if (Con.Type == "DDL") {
        Con.Text := Arr.Length >= 1 ? Arr[1] : ""
        loop Arr.Length {
            if (Arr[A_Index] == Text) {
                Con.Text := Text
                break
            }
        }
    }

}

GetNameAndValueByParamArr(&NameArr, &ValueArr, ParamArr) {
    NameArr := []
    ValueArr := []
    i := 2
    while (i <= paramArr.Length) {
        NameArr.Push(paramArr[i])
        ValueArr.Push(paramArr[i + 1])
        i += 2
    }
}

GetShowEncoding(Encoding) {
    if (Encoding == "CP0")
        return "ANSI"
    if (Encoding == "CP936")
        return "GB2312"
    if (Encoding == "CP54936")
        return "GB18030"
    if (Encoding == "CP950")
        return "BIG5"
    return Encoding
}

GetSoftEncoding(Encoding) {
    if (Encoding == "ANSI")
        return "CP0"
    if (Encoding == "GB2312")
        return "CP936"
    if (Encoding == "GB18030")
        return "CP54936"
    if (Encoding == "BIG5")
        return "CP950"
    return Encoding
}

GetBrightness() {
    wmi := ComObjGet("winmgmts:\\.\root\WMI")
    itmes := wmi.ExecQuery("SELECT * FROM WmiMonitorBrightness")
    for item in itmes {
        return item.CurrentBrightness
    }
    return 20
}

GetSystemVarArr() {
    return [GetLang("循环次数"), GetLang("宏循环次数"), GetLang("句柄ID"), GetLang("当前鼠标颜色"), GetLang("当前鼠标坐标X"),
    GetLang("当前鼠标坐标Y"), GetLang("当前日期"), GetLang("当前时间"), GetLang("当前时间(秒)"), GetLang("当前秒"), GetLang("当前星期几")]
}

DoCompare(&currentComparison, tableItem, index, CompareType, Name, OtherValue) {
    if (CompareType == 7) {
        hasValue := TryGetTabVarValue(&Value, tableItem, index, Name, false)
        currentComparison := hasValue
        return true
    }

    hasValue := TryGetTabVarValue(&Value, tableItem, index, Name)
    if (!hasValue)
        return false

    if (CompareType == 3 || CompareType == 6 || CompareType == 8) {
        hasOtherValue := TryGetTabVarValue(&OtherVal, tableItem, index, OtherValue, false)
        OtherVal := hasOtherValue ? OtherVal : OtherValue
        hasOtherValue := true
    }
    else {
        hasOtherValue := TryGetTabVarValue(&OtherVal, tableItem, index, OtherValue)
    }

    if (!hasOtherValue)
        return false

    switch CompareType {
        case 1: currentComparison := Value > OtherVal
        case 2: currentComparison := Value >= OtherVal
        case 3: currentComparison := Value == OtherVal
        case 4: currentComparison := Value <= OtherVal
        case 5: currentComparison := Value < OtherVal
        case 6: currentComparison := CheckContainText(Value, OtherVal)
        case 8: currentComparison := RegExMatch(Value, OtherVal)
        default: currentComparison := false
    }
    return true
}

HandleControlType(tableItem, index, ControlType) {
    item := tableItem.Items[index]
    if (!item)
        return
    switch (ControlType) {
        case "循环-跳过本轮":
            item.VariableMap["循环-跳过本轮"] := true
        case "循环-跳出":
            item.VariableMap["循环-跳出"] := true
        case "分支-跳出":
            item.VariableMap["分支-跳出"] := true
    }
}

; 避免写入提示报错
SetClipboard(Content) {
    loop 5 {  ; 最多重试5次
        try {
            A_Clipboard := Content
            return true
        } catch as err {
            Sleep(100)  ; 等待50毫秒
            continue
        }
    }
    return false  ; 5次都失败
}

ValidateCmdPath(&Data, pathFieldName, selectTitle, filter, tableItem := "", index := 1, showSelect := true) {
    if (!ObjHasOwnProp(Data, pathFieldName))
        return true

    rawPath := Data.%pathFieldName%
    hasVariable := InStr(rawPath, "{") && InStr(rawPath, "}")

    if (!hasVariable) {
        if (rawPath == "" || FileExist(rawPath))
            return true

        if (!showSelect)
            return false

        tipStr := Format(GetLang("路径 '{}' 不存在，请重新选择"), rawPath)
        result := CustomMsgBox(tipStr, GetLang("路径缺失"), GetLang("选择文件|跳过本条指令"))

        if (result == 2)
            return false

        newPath := FileSelect(1, , GetLang(selectTitle), filter)
        if (newPath == "")
            return false

        Data.%pathFieldName% := newPath
        SaveMacroCMDData(Data)
        return true
    }

    actualPath := GetReplaceVarText(tableItem, index, rawPath)

    if (actualPath != "" && FileExist(actualPath))
        return true

    if (!showSelect)
        return false

    tipStr := Format("{}`n`n{}: {}`n{}: {}",
        GetLang("变量路径解析后文件不存在"),
        GetLang("原始配置"), rawPath,
        GetLang("解析为"), actualPath == "" ? GetLang("(空值)") : actualPath)

    result := CustomMsgBox(tipStr, GetLang("变量路径错误"), GetLang("覆盖变量|跳过本条指令"))

    if (result == 2)
        return false

    newPath := FileSelect(1, , GetLang(selectTitle), filter)
    if (newPath == "")
        return false

    Data.%pathFieldName% := newPath
    SaveMacroCMDData(Data)
    return true
}

; ===== 项目根目录 / OCR 懒加载/定时回收函数 =====

GetProjectRoot() {
    root := A_ScriptDir
    if !FileExist(root '\Plugins\RapidOcr') {
        root .= '\..'
        loop files, root {
            root := A_LoopFileFullPath
            break
        }
    }
    return root
}

global LastChineseOcrUseTime := 0
global LastEnglishOcrUseTime := 0
global OCR_IDLE_TIMEOUT := 300000

GetChineseOcr() {
    global MyChineseOcr, LastChineseOcrUseTime
    if (!MyChineseOcr) {
        MyChineseOcr := RapidOcr(GetProjectRoot())
    }
    LastChineseOcrUseTime := A_TickCount
    return MyChineseOcr
}

; 已弃用：PP-OCRv6 为统一多语言模型，GetChineseOcr/GetEnglishOcr 返回同一模型实例，保留仅为兼容旧调用
GetEnglishOcr() {
    global MyEnglishOcr, LastEnglishOcrUseTime
    if (!MyEnglishOcr) {
        MyEnglishOcr := RapidOcr(GetProjectRoot(), 2)
    }
    LastEnglishOcrUseTime := A_TickCount
    return MyEnglishOcr
}

UnloadChineseOcr() {
    global MyChineseOcr
    if (MyChineseOcr) {
        MyChineseOcr.Destroy()
        MyChineseOcr := ""
    }
}

UnloadEnglishOcr() {
    global MyEnglishOcr
    if (MyEnglishOcr) {
        MyEnglishOcr.Destroy()
        MyEnglishOcr := ""
    }
}

; 获取窗口在活动显示器上居中的坐标
GetCenterPosOnActiveMonitor(winWidth, winHeight) {
    MouseGetPos(&mouseX, &mouseY)
    monCount := MonitorGetCount()
    Loop monCount {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (mouseX >= mL && mouseX < mR && mouseY >= mT && mouseY < mB) {
            MonitorGetWorkArea(A_Index, &waL, &waT, &waR, &waB)
            x := Floor((waL + waR - winWidth) / 2)
            y := Floor((waT + waB - winHeight) / 2)
            return {x: x, y: y}
        }
    }
    ; 默认主显示器
    MonitorGetWorkArea(1, &waL, &waT, &waR, &waB)
    x := Floor((waL + waR - winWidth) / 2)
    y := Floor((waT + waB - winHeight) / 2)
    return {x: x, y: y}
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