#Requires AutoHotkey v2.0
#Include "DataClass.ahk"
#Include Util\ExcelUtil.ahk
#Include Util\SerialUtil.ahk
#Include Util\JsonUtil.ahk
#Include Util\LangUtil.ahk
#Include Util\Gdip_All.ahk
#Include Util\FixCompatUtil.ahk
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
#Include Util\PluginUtil.ahk
global WM_COPYDATA := 0x4a ;传递字符串，系统信息

global WM_LOAD_WORK := 0x500  ;资源加载完成事件
global WM_RELEASE_WORK := 0x501  ;资源释放事件
global WM_CLEAR_WORK := 0x502  ;资源释放事件
global WM_TR_MACRO := 0x503 ;触发宏事件
global WM_STOP_MACRO := 0x504 ;停止宏事件
global WM_SET_VARI := 0x505    ;设置变量
global WM_DEL_VARI := 0x506    ;删除变量
global WM_RECEIVE_INFO := 0x507    ;主进程接受到子进程信息，防止信息丢失

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

GetParamsWinInfoStr(infoStr, symbolStr := "default") {
    if (infoStr == "")
        return ""

    if (InStr(infoStr, "❖")) {
        infoStr := StrReplace(infoStr, "❖")
        hwndList := StrSplit(infoStr, "|")
        for index, hwnd in hwndList {
            GroupAdd(symbolStr, "ahk_id " hwnd)
        }
        ResStr := "ahk_group " symbolStr
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
        MsgBox(GetLang("剪切板中没有位图"))
    }

    ; 打开剪切板
    if !DllCall("OpenClipboard", "ptr", 0) {
        MsgBox(GetLang("无法打开剪切板"))
        return
    }

    ; 获取剪切板中的位图句柄
    hBitmap := DllCall("GetClipboardData", "uint", 2, "ptr")  ; 2 是 CF_BITMAP
    if !hBitmap {
        MsgBox(GetLang("无法获取位图句柄"))
        DllCall("CloseClipboard")
        return
    }

    ; 关闭剪切板
    DllCall("CloseClipboard")

    ; 创建 GDI+ 位图对象
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
    if !pBitmap {
        MsgBox(GetLang("无法创建 GDI+ 位图对象"))
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
    for key, value in MySoftData.SpecialKeyMap {
        newMacro := StrReplace(macro, key, "flagSymbol")
        if (newMacro != macro) {
            realKey := key
            break
        }
    }

    result := StrSplit(newMacro, "_")
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
    macroStr := ""
    loop cmdArr.Length {
        macroStr .= cmdArr[A_Index] ","
    }
    macroStr := Trim(macroStr, ",")
    return macroStr
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
        "输入", InputFile, "文件读写", FileIOFile, "窗口管理", WindowManageFile)
    MySoftData.DataClassMap := Map("搜索", SearchData, "搜索Pro", SearchData, "移动Pro", MMProData,
        "输出", OutputData, "运行", RunData, "循环", LoopData, "宏操作", SubMacroData, "变量", VariableData,
        "变量提取", ExVariableData, "如果", CompareData, "如果Pro", CompareProData, "运算", OperationData,
        "后台鼠标", BGMouseData, "后台按键", BGKeyData, "文本处理", TextOpsData, "Timing", TimingData, "数组", ArrayData,
        "输入", InputData, "文件读写", FileIOData, "窗口管理", WindowManageData)
}

InitLogitechGHubNew() {
    if (MySoftData.IsLogitechInit)
        return true

    res := IbSendInit("LogitechGHubNew", 0)
    if (res == false)
        return false

    MySoftData.IsLogitechInit := true
    return true
}

;资源读取
LoadMainSetting() {
    global ToolCheckInfo, MySoftData
    global IniSection := "UserSettings"
    MySoftData.CurSettingName := IniRead(IniFile, IniSection, "CurSettingName", "RMT默认配置")
    MySoftData.SettingArrStr := IniRead(IniFile, IniSection, "SettingArrStr", "RMT默认配置")
    MySoftData.HasSaved := IniRead(IniFile, IniSection, "HasSaved", false)
    MySoftData.IsReload := IniRead(IniFile, IniSection, "IsReload", false)
    MySoftData.NormalPeriod := IniRead(IniFile, IniSection, "NormalPeriod", 50)
    MySoftData.HoldFloat := IniRead(IniFile, IniSection, "HoldFloat", 0)
    MySoftData.PreIntervalFloat := IniRead(IniFile, IniSection, "PreIntervalFloat", 0)
    MySoftData.IntervalFloat := IniRead(IniFile, IniSection, "IntervalFloat", 0)
    MySoftData.CoordXFloat := IniRead(IniFile, IniSection, "CoordXFloat", 0)
    MySoftData.CoordYFloat := IniRead(IniFile, IniSection, "CoordYFloat", 0)
    MySoftData.SuspendHotkey := IniRead(IniFile, IniSection, "SuspendHotkey", "!p")
    MySoftData.PauseHotkey := IniRead(IniFile, IniSection, "PauseHotkey", "!i")
    MySoftData.KillMacroHotkey := IniRead(IniFile, IniSection, "KillMacroHotkey", "!k")
    ToolCheckInfo.IsToolCheck := IniRead(IniFile, IniSection, "IsToolCheck", false)
    ToolCheckInfo.ToolCheckHotKey := IniRead(IniFile, IniSection, "ToolCheckHotKey", "!o")
    ToolCheckInfo.ToolRecordMacroHotKey := IniRead(IniFile, IniSection, "RecordMacroHotKey", "!r")
    ToolCheckInfo.ToolTextFilterHotKey := IniRead(IniFile, IniSection, "ToolTextFilterHotKey", "!u")
    ToolCheckInfo.ScreenShotHotKey := IniRead(IniFile, IniSection, "ScreenShotHotKey", "!F1")
    ToolCheckInfo.FreePasteHotKey := IniRead(IniFile, IniSection, "FreePasteHotKey", "!F2")
    ToolCheckInfo.RecordKeyboard := IniRead(IniFile, IniSection, "RecordKeyboard", true)
    ToolCheckInfo.RecordMouse := IniRead(IniFile, IniSection, "RecordMouse", true)
    ToolCheckInfo.RecordJoy := IniRead(IniFile, IniSection, "RecordJoy", false)
    ToolCheckInfo.RecordMouseKeyPoint := IniRead(IniFile, IniSection, "RecordMouseKeyPoint", true)
    ToolCheckInfo.RecordMouseRelative := IniRead(IniFile, IniSection, "RecordMouseRelative", false)
    ToolCheckInfo.RecordMouseTrail := IniRead(IniFile, IniSection, "RecordMouseTrail", false)
    ToolCheckInfo.RecordMouseTrailLen := IniRead(IniFile, IniSection, "RecordMouseTrailLen", 100)
    ToolCheckInfo.RecordMouseTrailSpeed := IniRead(IniFile, IniSection, "RecordMouseTrailSpeed", 95)
    ToolCheckInfo.RecordHoldMuti := IniRead(IniFile, IniSection, "RecordHoldMuti", false)
    ToolCheckInfo.RecordAutoLoosen := IniRead(IniFile, IniSection, "RecordAutoLoosen", true)
    ToolCheckInfo.RecordMouseTrailInterval := IniRead(IniFile, IniSection, "MouseTrailInterval", 300)
    ToolCheckInfo.RecordJoyInterval := IniRead(IniFile, IniSection, "RecordJoyInterval", 50)
    ToolCheckInfo.OCRTypeValue := IniRead(IniFile, IniSection, "OCRType", 1)
    MySoftData.IsBootStart := IniRead(IniFile, IniSection, "IsBootStart", false)
    MySoftData.ShowSplitLine := IniRead(IniFile, IniSection, "ShowSplitLine", false)
    hiddenTopButtonText := IniRead(IniFile, IniSection, "HiddenTopButtonIndexes", "")
    if (hiddenTopButtonText == "" && StrLower(IniRead(IniFile, IniSection, "ShowTopButtons", "true")) == "false")
        hiddenTopButtonText := RmtIndexListToString(RmtCreateIndexList(MySoftData.TabNameArr.Length))
    MySoftData.HiddenTopButtonIndexes := RmtParseIndexList(hiddenTopButtonText, MySoftData.TabNameArr.Length)
    MySoftData.ColorPresetId := IniRead(IniFile, IniSection, "ColorPresetId", "rmt-green")
    MySoftData.FixedMenuWheel := IniRead(IniFile, IniSection, "FixedMenuWheel", false)
    MySoftData.IsModalSubGui := IniRead(IniFile, IniSection, "IsModalSubGui", true)
    MySoftData.MutiThreadNum := IniRead(IniFile, IniSection, "MutiThreadNum", -1)
    MySoftData.DynamicCorePoolSize := IniRead(IniFile, IniSection, "DynamicCorePoolSize", 2)
    MySoftData.ElasticTimeout := IniRead(IniFile, IniSection, "ElasticTimeout", 30)
    MySoftData.SoftBGColor := IniRead(IniFile, IniSection, "SoftBGColor", "f0f0f0")
    MySoftData.NoVariableTip := IniRead(IniFile, IniSection, "NoVariableTip", true)
    MySoftData.CMDTip := IniRead(IniFile, IniSection, "CMDTip", false)
    MySoftData.ScreenShotType := IniRead(IniFile, IniSection, "ScreenShotType", 3)
    MySoftData.KeyDownDownType := IniRead(IniFile, IniSection, "KeyDownDown", 1)
    MySoftData.AgreeAgreement := IniRead(IniFile, IniSection, "AgreeAgreement", false)
    MySoftData.WinPosX := IniRead(IniFile, IniSection, "WinPosX", 0)
    MySoftData.WinPosY := IniRead(IniFile, IniSection, "WinPosY", 0)
    MySoftData.TableIndex := IniRead(IniFile, IniSection, "TableIndex", 1)
    MySoftData.Lang := IniRead(IniFile, IniSection, "Lang", "无语言")
    MySoftData.FontType := IniRead(IniFile, IniSection, "FontType", "微软雅黑")
    MySoftData.CMDPosX := IniRead(IniFile, IniSection, "CMDPosX", A_ScreenWidth - 225 - 55)
    MySoftData.CMDPosY := IniRead(IniFile, IniSection, "CMDPosY", 0)
    MySoftData.CMDWidth := IniRead(IniFile, IniSection, "CMDWidth", 225)
    MySoftData.CMDHeight := IniRead(IniFile, IniSection, "CMDHeight", 200)
    MySoftData.CMDBGColor := IniRead(IniFile, IniSection, "CMDBGColor", "FFFFFF")
    MySoftData.CMDRunBGColor := IniRead(IniFile, IniSection, "CMDRunBGColor", "12fc0a")
    MySoftData.CMDTransparency := IniRead(IniFile, IniSection, "CMDTransparency", 50)
    MySoftData.CMDFontColor := IniRead(IniFile, IniSection, "CMDFontColor", "000000")
    MySoftData.CMDFontSize := IniRead(IniFile, IniSection, "CMDFontSize", 12)
    MySoftData.VarListenTop := IniRead(IniFile, IniSection, "VarListenTop", 0)
    MySoftData.VarListenWidth := IniRead(IniFile, IniSection, "VarListenWidth", 400)
    MySoftData.VarListenHeight := IniRead(IniFile, IniSection, "VarListenHeight", 420)
    MySoftData.MacroTotalCount := IniRead(IniFile, IniSection, "MacroTotalCount", 0)
    MySoftData.LastShowMonth := IniRead(IniFile, IniSection, "LastShowMonth", A_Mon)

    MySoftData.TableInfo := CreateTableItemArr()
    SetFontList()
    LangInitSetting()
    LangKeysInit()
}

RmtCreateIndexList(count) {
    indexes := []
    loop Integer(count) {
        if (A_Index == 8)
            continue
        indexes.Push(A_Index)
    }
    return indexes
}

RmtParseIndexList(value, maxIndex := 0) {
    indexes := []
    seen := Map()
    for _, part in StrSplit(String(value), ",") {
        part := Trim(part)
        if (!IsInteger(part))
            continue
        index := Integer(part)
        if (index < 1 || index == 8 || (maxIndex > 0 && index > maxIndex) || seen.Has(index))
            continue
        seen[index] := true
        indexes.Push(index)
    }
    return indexes
}

RmtIndexListToString(indexes) {
    parts := []
    if (indexes is Array) {
        for _, index in indexes
            parts.Push(String(index))
    }
    return StrJoin(parts, ",")
}

StrJoin(values, separator) {
    result := ""
    for index, value in values {
        if (index > 1)
            result .= separator
        result .= value
    }
    return result
}

SetFontList() {
    MySoftData.FontList := []
    callback := CallbackCreate(EnumFontFamilies)
    DllCall("gdi32\EnumFontFamilies", "uint", DllCall("GetDC", "uint", 0), "uint", 0, "uint", callback, "ptr", 0)
    CallbackFree(callback)

    ; Font enumeration callback
    EnumFontFamilies(lpelf, lpntm, FontType, lP) {
        if (SubStr(StrGet(lpelf + 28), 1, 1) != "@")
            MySoftData.FontList.push(StrGet(lpelf + 28))
        return 1
    }

    if (MySoftData.FontList.Length == 0)
        return

    DefaultFontMap := Map("微软雅黑", 0, "Arial", 0, "Consolas", 0, "SimHei", 0, "Dotum", 0, "Meiryo", 0)
    if (DefaultFontMap.Has(MySoftData.FontType)) {
        for index, value in MySoftData.FontList {
            if (DefaultFontMap.Has(value))
                DefaultFontMap[value] := index
        }
    }
    if (DefaultFontMap.Has(MySoftData.FontType)) {
        if (DefaultFontMap[MySoftData.FontType] != 0)
            return

        for key, value in DefaultFontMap {
            if (value != 0) {
                MySoftData.FontType := key
                return
            }
        }

        MySoftData.FontType := MySoftData.FontList[1]
    }
}

LoadCurMacroSetting() {
    loop MySoftData.TabNameArr.Length {
        ReadTableItemInfo(A_Index)
    }
}

ReadTableItemInfo(index) {
    global MySoftData
    symbol := GetTableSymbol(index)
    defaultInfo := GetTableItemDefaultInfo(index)
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
    savedFoldInfoStr := IniRead(MacroFile, IniSection, symbol "FoldInfo", "")

    ;不存在折叠筐就初始化，并读取默认配置
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

        defaultFoldInfo := ItemFoldInfo()
        defaultFoldInfo.RemarkArr := [GetLang("RMT默认初始化配置")]
        defaultFoldInfo.FrontInfoArr := [""]
        IndexSpanValue := savedModeArrStr == "" ? "无-无" : savedModeArrStr == "1" ? "1-1" : "1-8"
        defaultFoldInfo.IndexSpanArr := [IndexSpanValue]
        defaultFoldInfo.FoldStateArr := [false]
        defaultFoldInfo.ForbidStateArr := [false]

        defaultFoldInfo.TKTypeArr := [1]
        defaultFoldInfo.TKArr := [""]
        defaultFoldInfo.HoldTimeArr := [500]
        savedFoldInfoStr := JSON.stringify(defaultFoldInfo, 0)
    }

    tableItem := MySoftData.TableInfo[index]
    SetArr(savedTKArrStr, "π", tableItem.TKArr)
    SetArr(savedModeArrStr, "π", tableItem.ModeArr)
    SetArr(savedForbidArrStr, "π", tableItem.ForbidArr)
    SetArr(savedRemarkArrStr, "π", tableItem.RemarkArr)
    SetIntArr(savedLoopCountStr, "π", tableItem.LoopCountArr)
    SetArr(savedHoldTimeArrStr, "π", tableItem.HoldTimeArr)
    SetArr(savedTriggerTypeArrStr, "π", tableItem.TriggerTypeArr)
    SetArr(savedSerialStr, "π", tableItem.SerialArr)
    SetArr(savedTimingSerialStr, "π", tableItem.TimingSerialArr)
    SetArr(savedStartTipSoundStr, "π", tableItem.StartTipSoundArr)
    SetArr(savedEndTipSoundStr, "π", tableItem.EndTipSoundArr)
    tableItem.FoldInfo := JSON.parse(savedFoldInfoStr, , false)
    SetSerialByArr(tableItem.SerialArr)
    SetSerialByArr(tableItem.TimingSerialArr)
    Compat1_0_8F4FlodInfo(tableItem.FoldInfo)
    Compat1_0_9F1TipSound(tableItem)

    if (tableItem.ModeArr.Length == 1) {
        if (tableItem.TKArr.Length == 0)
            tableItem.TKArr := [""]

        if (tableItem.RemarkArr.Length == 0)
            tableItem.RemarkArr := [""]
    }

    loop tableItem.ModeArr.length {
        str := IniRead(MacroFile, IniSection, symbol "MacroArr" A_Index, "")
        if (str == "" && !MySoftData.HasSaved && A_Index == 1)
            str := GetGetTableItemDefaultMacro(index)
        else {
            str := StrReplace(str, "⫶", "`n")
        }
        tableItem.MacroArr.Push(str)
    }
}

SetArr(str, symbol, Arr) {
    for index, value in StrSplit(str, symbol) {
        if (Arr.Length < index) {
            Arr.Push(value)
        }
        else {
            Arr[index] = value
        }
    }
}

SetIntArr(str, symbol, Arr) {
    for index, value in StrSplit(str, symbol) {
        curValue := value
        if (value == "")
            curValue := 1
        if (Arr.Length < index) {
            Arr.Push(Integer(curValue))
        }
        else {
            Arr[index] = Integer(curValue)
        }
    }
}

GetGetTableItemDefaultMacro(index) {
    symbol := GetTableSymbol(index)
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
    return ""
}

GetTableItemDefaultInfo(index) {
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
    symbol := GetTableSymbol(index)

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
    }
    else if (symbol == "Menu") {
        savedTKArrStr := "πππππππ"
        savedHoldTimeArrStr := "500π500π500π500π500π500π500π500"
        savedModeArrStr := "1π1π1π1π1π1π1π1"
        savedForbidArrStr := "0π0π0π0π0π0π0π0"
        savedRemarkArrStr := "πππππππ"
        savedLoopCountStr := "1π1π1π1π1π1π1π1"
        savedTriggerTypeStr := "1π1π1π1π1π1π1π1"
        savedSerialeArrStr := "3π4π5π6π7π8π12π13"
        savedTimingSerialStr :=
            "Timing3πTiming4πTiming5πTiming6πTiming7πTiming8πTiming12πTiming13"
        savedStartTipSoundStr := "1π1π1π1π1π1π1π1"
        savedEndTipSoundStr := "1π1π1π1π1π1π1π1"
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
    }
    else if (symbol == "SubMacro") {
        savedTKArrStr := ""
        savedHoldTimeArrStr := "500"
        savedModeArrStr := "1"
        savedForbidArrStr := "1"
        savedRemarkArrStr := GetLang("只能通过宏操作调用")
        savedLoopCountStr := "1"
        savedTriggerTypeStr := "1"
        savedSerialeArrStr := "10"
        savedTimingSerialStr := "Timing10"
        savedStartTipSoundStr := "1"
        savedEndTipSoundStr := "1"
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
    }
    return [savedTKArrStr, savedHoldTimeArrStr, savedModeArrStr, savedForbidArrStr, savedRemarkArrStr,
        savedLoopCountStr, savedTriggerTypeStr, savedSerialeArrStr, savedTimingSerialStr, savedStartTipSoundStr,
        savedEndTipSoundStr]
}

SaveTableItemInfo(index) {
    SavedInfo := GetSavedTableItemInfo(index)
    symbol := GetTableSymbol(index)
    tableItem := MySoftData.TableInfo[index]
    IniWrite(SavedInfo[1], MacroFile, IniSection, symbol "TKArr")
    IniWrite(SavedInfo[2], MacroFile, IniSection, symbol "ModeArr")
    IniWrite(SavedInfo[3], MacroFile, IniSection, symbol "HoldTimeArr")
    IniWrite(SavedInfo[4], MacroFile, IniSection, symbol "ForbidArr")
    IniWrite(SavedInfo[5], MacroFile, IniSection, symbol "RemarkArr")
    IniWrite(SavedInfo[6], MacroFile, IniSection, symbol "LoopCountArr")
    IniWrite(SavedInfo[7], MacroFile, IniSection, symbol "TriggerTypeArr")
    IniWrite(SavedInfo[8], MacroFile, IniSection, symbol "SerialArr")
    IniWrite(SavedInfo[9], MacroFile, IniSection, symbol "TimingSerialArr")
    IniWrite(SavedInfo[10], MacroFile, IniSection, symbol "StartTipSoundArr")
    IniWrite(SavedInfo[11], MacroFile, IniSection, symbol "EndTipSoundArr")

    FoldInfoStr := JSON.stringify(tableItem.FoldInfo, 0)
    IniWrite(FoldInfoStr, MacroFile, IniSection, symbol "FoldInfo")

    SaveTableItemMacro(index)
}

SaveTableItemMacro(index) {
    tableItem := MySoftData.TableInfo[index]
    symbol := GetTableSymbol(index)
    loop tableItem.ModeArr.Length {
        MacroStr := tableItem.MacroArr.Has(A_Index) ? tableItem.MacroArr[A_Index] : ""
        MacroStr := Trim(MacroStr)
        MacroStr := Trim(MacroStr, "`n")
        MacroStr := Trim(MacroStr, ",")
        MacroStr := StrReplace(MacroStr, "`n", "⫶")
        IniWrite(MacroStr, MacroFile, IniSection, symbol "MacroArr" A_Index)
    }
}

GetSavedTableItemInfo(index) {
    Saved := MySoftData.MyGui.Submit()
    TKArrStr := ""
    ModeArrStr := ""
    HoldTimeArrStr := ""
    ForbidArrStr := ""
    RemarkArrStr := ""
    LoopCountArrStr := ""
    TriggerTypeArrStr := ""
    SerialArrStr := ""
    TimingSerialArrStr := ""
    StartTipSoundArrStr := ""
    EndTipSoundArrStr := ""

    tableItem := MySoftData.TableInfo[index]
    symbol := GetTableSymbol(index)

    loop tableItem.ModeArr.Length {
        TKArrStr .= tableItem.TKArr[A_Index]
        ModeArrStr .= tableItem.ModeArr[A_Index]
        ForbidArrStr .= tableItem.ForbidArr[A_Index]
        HoldTimeArrStr .= tableItem.HoldTimeArr[A_Index]
        RemarkArrStr .= tableItem.RemarkArr[A_Index]
        TriggerTypeArrStr .= tableItem.TriggerTypeArr[A_Index]
        LoopCountArrStr .= tableItem.LoopCountArr[A_Index]
        SerialArrStr .= tableItem.SerialArr[A_Index]
        TimingSerialArrStr .= tableItem.TimingSerialArr[A_Index]
        StartTipSoundArrStr .= tableItem.StartTipSoundArr[A_Index]
        EndTipSoundArrStr .= tableItem.EndTipSoundArr[A_Index]
        if (tableItem.ModeArr.Length > A_Index) {
            TKArrStr .= "π"
            ModeArrStr .= "π"
            HoldTimeArrStr .= "π"
            ForbidArrStr .= "π"
            RemarkArrStr .= "π"
            LoopCountArrStr .= "π"
            TriggerTypeArrStr .= "π"
            SerialArrStr .= "π"
            TimingSerialArrStr .= "π"
            StartTipSoundArrStr .= "π"
            EndTipSoundArrStr .= "π"
        }
    }

    return [TKArrStr, ModeArrStr, HoldTimeArrStr, ForbidArrStr, RemarkArrStr,
        LoopCountArrStr, TriggerTypeArrStr, SerialArrStr, TimingSerialArrStr, StartTipSoundArrStr, EndTipSoundArrStr]
}

;Table信息相关
CreateTableItemArr() {
    Arr := []
    loop MySoftData.TabNameArr.Length {
        newTableItem := TableItem()
        newTableItem.Index := A_Index
        if (Arr.Length < A_Index) {
            Arr.Push(newTableItem)
        }
        else {
            Arr[A_Index] := newTableItem
        }
    }
    return Arr
}

InitTableItemState() {
    loop MySoftData.TabNameArr.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        InitSingleTableState(tableItem)
    }

    tableItem := MySoftData.SpecialTableItem
    tableItem.ModeArr := [1]
    InitSingleTableState(tableItem)
}

InitSingleTableState(tableItem) {
    tableItem.KilledArr := []
    tableItem.ActionCount := []
    tableItem.HoldKeyArr := []
    tableItem.ToggleStateArr := []
    tableItem.ToggleActionArr := []
    tableItem.VariableMapArr := []
    tableItem.IsWorkIndexArr := []
    tableItem.PauseArr := []
    tableItem.ColorStateArr := []
    for index, value in tableItem.ModeArr {
        tableItem.KilledArr.Push(false)
        tableItem.PauseArr.Push(false)
        tableItem.ActionCount.Push(0)
        tableItem.HoldKeyArr.Push(Map())
        tableItem.ToggleStateArr.Push(false)
        tableItem.ToggleActionArr.Push("")
        tableItem.IsWorkIndexArr.Push(false)
        tableItem.ColorStateArr.Push(0)

        VariableMap := Map()
        VariableMap["宏循环次数"] := 0
        VariableMap["循环-跳过本轮"] := false
        VariableMap["循环-跳出"] := false
        VariableMap["分支-跳出"] := false
        tableItem.VariableMapArr.Push(VariableMap)
    }
}

KillSingleTableMacro(tableItem) {
    for index, value in tableItem.ModeArr {
        KillTableItemMacro(tableItem, index)
    }
}

KillTableItemMacro(tableItem, index) {
    if (tableItem.KilledArr.Length < index)
        return
    tableItem.KilledArr[index] := true
    HoldKeyMap := tableItem.HoldKeyArr[index].Clone()
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

    ; 如果是开关型按键宏，重置其开关状态
    if (tableItem.TriggerTypeArr.Length >= index && tableItem.TriggerTypeArr[index] == 4) {
        if (tableItem.ToggleStateArr.Length >= index)
            tableItem.ToggleStateArr[index] := false
    }
}

GetTabHeight() {
    maxY := 0
    loop MySoftData.TabNameArr.Length {
        posY := MySoftData.TableInfo[A_Index].UnderPosY
        if (posY > maxY)
            maxY := posY
    }

    height := maxY - MySoftData.TabPosY
    return height
    ; return Max(height, 500)
}

UpdateUnderPosY(tableIndex, value) {
    table := MySoftData.TableInfo[tableIndex]
    table.UnderPosY += value
}

GetTableSymbol(index) {
    return MySoftData.TabSymbolArr[index]
}

GetTimingTableIndex() {
    loop MySoftData.TabNameArr.Length {
        symbol := GetTableSymbol(A_Index)
        if (symbol == "Timing")
            return A_Index
    }
    return ""
}

GetTableIndex(SymbolOrName) {
    loop MySoftData.TabNameArr.Length {
        if (SymbolOrName == MySoftData.TabNameArr[A_Index])
            return A_Index

        if (SymbolOrName == MySoftData.TabSymbolArr[A_Index])
            return A_Index
    }
    return 0
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

CheckIsNoTriggerKey(index) {
    symbol := GetTableSymbol(index)
    if (symbol == "SubMacro")
        return true
    if (symbol == "Timing")
        return true
    if (symbol == "Menu")
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

LoosenModifyKey(keyCombo) {
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]

    ; 检查是否以修饰键开头
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

    ; 检查所有修饰键是否按下
    for mod in modifiers {
        key := ""
        switch mod {
            case "^":
                key := "Ctrl"
            case "<^":
                key := "LCtrl"
            case ">^":
                key := "RCtrl"
            case "!":
                key := "Alt"
            case "<!":
                key := "LAlt"
            case ">!":
                key := "RAlt"
            case "+":
                key := "Shift"
            case "<+":
                key := "LShift"
            case ">+":
                key := "RShift"
            case "#":
                key := "Win"
            case "<#":
                key := "LWin"
            case ">#":
                key := "RWin"
        }
        if (key != "") {
            VK := GetKeyVK(key)
            SC := GetKeySC(key)
            DllCall("keybd_event", "UChar", VK, "UChar", SC, "UInt", 0x2, "UPtr", 0)
        }
    }

}

AreKeysPressed(keyCombo) {
    ; 初始化存储修饰键的数组
    modifiers := []
    modPrefixes := ["^", "<^", ">^", "!", "<!", ">!", "+", "<+", ">+", "#", "<#", ">#"]

    ; 检查是否以修饰键开头
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

    ; 剩余部分是主键
    mainKey := keyCombo

    ; 检查所有修饰键是否按下
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

            default: return false  ; 未知修饰键
        }
    }

    isJoyKey := RegExMatch(mainKey, "Joy")
    if (mainKey == "") {
        return true
    }
    if (isJoyKey) {
        isJoyAxis := RegExMatch(mainKey, "Min") || RegExMatch(mainKey, "Max")
        joyName := isJoyAxis ? SubStr(mainKey, 1, 4) : mainKey

        loop 4 {
            state := GetKeyState(A_Index joyName)
            if (state)
                return true
        }
    }
    else if (GetKeyState(mainKey, "P")) {  ; 检查主键（如果有）
        return true
    }

    return false
}

GetRecordTriggerKeyMap() {
    triggerKey := ToolCheckInfo.ToolRecordMacroHotKey
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
        resultMap.Set(triggerKey, true)

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

GetMacroCMDData(serialStr) {
    if (MySoftData.DataCacheMap.Has(serialStr)) {
        return MySoftData.DataCacheMap[serialStr]
    }

    textOnly := RegExReplace(serialStr, "\d+")
    numbersOnly := RegExReplace(serialStr, "\D+")
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
    MySoftData.DataCacheMap.Set(normalizedSerialStr, Data)

    ; Also cache the original key if they differ, so next time we hit the fast path at the top
    if (normalizedSerialStr != serialStr) {
        MySoftData.DataCacheMap.Set(serialStr, Data)
    }

    return Data
}

SaveMacroCMDData(Data) {
    cmd := RegExReplace(Data.SerialStr, "\d+")
    DataFile := MySoftData.DataFileMap[cmd]

    saveStr := JSON.stringify(Data, 0)
    IniWrite(saveStr, DataFile, IniSection, Data.SerialStr)
    if (MySoftData.DataCacheMap.Has(Data.SerialStr)) {
        MySoftData.DataCacheMap.Delete(Data.SerialStr)
    }
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
    TableVariableMap := tableItem.VariableMapArr[index]
    return TryGetVarValue(&Value, varName, variTip, TableVariableMap)
}

ShowNoVariableTip(VarName) {
    if (MySoftData.NoVariableTip) {
        str1 := GetLang("当前环境不存在变量") VarName
        str2 := Format(GetLang("tip1:请确保有创建变量-{}的相关指令"), VarName)
        str3 := Format(GetLang("tip2:请确保上述指令运行过"))
        MsgBox(Format("{}`n{}`n{}", str1, str2, str3))
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
    while (tableItem.PauseArr[itemIndex]) {
        if (tableItem.KilledArr[itemIndex])
            break

        Sleep(200)
    }
}

GetItemFoldIndex(tableItem, itemIndex) {
    FoldInfo := tableItem.FoldInfo
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        IndexSpan := StrSplit(IndexSpanStr, "-")
        if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
            if (IndexSpan[1] <= itemIndex && IndexSpan[2] >= itemIndex)
                return Index
        }
    }
    return 0
}

GetItemFoldForbidState(tableItem, itemIndex) {
    FoldInfo := tableItem.FoldInfo
    FoldIndex := GetItemFoldIndex(tableItem, itemIndex)
    return FoldInfo.ForbidStateArr[FoldIndex]
}

GetItemFrontInfo(tableItem, itemIndex) {
    FoldInfo := tableItem.FoldInfo
    FoldIndex := GetItemFoldIndex(tableItem, itemIndex)
    return FoldInfo.FrontInfoArr[FoldIndex]
}

GetItemOffsetOfFold(tableItem, itemIndex) {
    FoldInfo := tableItem.FoldInfo
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        IndexSpan := StrSplit(IndexSpanStr, "-")
        if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
            if (IndexSpan[1] <= itemIndex && IndexSpan[2] >= itemIndex) {
                return itemIndex - IndexSpan[1] + 1
            }
        }
    }

    return 1
}

CustomMsgBox(Text := "", Title := "", Buttons := "") {
    Result := -1

    ; 解析按钮字符串
    ButtonArray := StrSplit(Buttons, "|")
    ButtonCount := ButtonArray.Length

    ; 创建 GUI
    MyGui := Gui()
    MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)
    MyGui.Title := Title
    MyGui.OnEvent("Close", GuiClose)
    MyGui.OnEvent("Escape", GuiClose)

    ; 添加提示文本
    MyGui.Add("Text", "w300 Center", Text)

    ; 动态创建按钮 - 统一 Y 坐标
    ButtonWidth := 80
    ButtonHeight := 30
    ButtonSpacing := 10
    ButtonY := 40  ; 统一的 Y 坐标位置

    TotalWidth := (ButtonWidth * ButtonCount) + (ButtonSpacing * (ButtonCount - 1))
    StartX := (300 - TotalWidth) // 2  ; 居中显示

    loop ButtonCount {
        CurrentX := StartX + (ButtonWidth + ButtonSpacing) * (A_Index - 1)
        Btn := MyGui.Add("Button", "w" ButtonWidth " h" ButtonHeight " x" CurrentX " y" ButtonY, ButtonArray[A_Index])
        Btn.OnEvent("Click", ButtonClicked.Bind(A_Index))
    }

    ; 显示 GUI 并等待
    MyGui.Show()

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
    if (macroState == 1) {
        if (tableItem.StartTipSoundArr[itmeIndex] == 1)
            return

        if (tableItem.StartTipSoundArr[itmeIndex] == 2) {
            PlayTipSound(1)
            return
        }

        if (tableItem.StartTipSoundArr[itmeIndex] == 3 && isFirst) {
            PlayTipSound(1)
            return
        }
    }

    if (macroState == 2) {
        if (tableItem.EndTipSoundArr[itmeIndex] == 1)
            return

        if (tableItem.EndTipSoundArr[itmeIndex] == 2) {
            PlayTipSound(2)
            return
        }

        if (tableItem.EndTipSoundArr[itmeIndex] == 3 && isLast) {
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
    IsSkip := RegExMatch(cmd, "🚫")
    IsDebug := RegExMatch(cmd, "⭐")
    SkipStr := IsSkip ? "🚫" : ""
    DebugStr := IsDebug ? "⭐" : ""
    Symbol := Format("{}{}", SkipStr, DebugStr)
    return Symbol
}

GetCmdOnlyText(param) {
    param := GetCmdStr(param)
    textOnly := RegExReplace(param, "\d+")
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
    GetLang("当前鼠标坐标Y"), GetLang("当前日期"), GetLang("当前时间"), GetLang("当前时间(秒)"), GetLang("当前秒")]
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
    switch (ControlType) {
        case "循环-跳过本轮":
            tableItem.VariableMapArr[index]["循环-跳过本轮"] := true
        case "循环-跳出":
            tableItem.VariableMapArr[index]["循环-跳出"] := true
        case "分支-跳出":
            tableItem.VariableMapArr[index]["分支-跳出"] := true
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
