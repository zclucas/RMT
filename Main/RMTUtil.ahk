#Requires AutoHotkey v2.0

;资源保存
OnSaveSetting(*) {
    global MySoftData, MyWorkPool
    isValid := CheckAllValueSettingValid()
    if (!isValid)
        return

    if (IsSet(MyWorkPool) && ObjHasOwnProp(MyWorkPool, "Clear"))
        MyWorkPool.Clear()

    loop MySoftData.TabNameArr.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        RecycleTabItem(tableItem)
        SaveTableItemInfo(A_Index)
    }

    IniWrite(MySoftData.HoldFloatCtrl.Value, IniFile, IniSection, "HoldFloat")
    IniWrite(MySoftData.PreIntervalFloatCtrl.Value, IniFile, IniSection, "PreIntervalFloat")
    IniWrite(MySoftData.IntervalFloatCtrl.Value, IniFile, IniSection, "IntervalFloat")
    IniWrite(MySoftData.CoordXFloatCon.Value, IniFile, IniSection, "CoordXFloat")
    IniWrite(MySoftData.CoordYFloatCon.Value, IniFile, IniSection, "CoordYFloat")
    IniWrite(MySoftData.SuspendHotkeyCtrl.Value, IniFile, IniSection, "SuspendHotkey")
    IniWrite(MySoftData.PauseHotkeyCtrl.Value, IniFile, IniSection, "PauseHotkey")
    IniWrite(MySoftData.KillMacroHotkeyCtrl.Value, IniFile, IniSection, "KillMacroHotkey")
    IniWrite(MySoftData.BootStartCtrl.Value, IniFile, IniSection, "IsBootStart")
    IniWrite(MySoftData.SplitLineCtrl.Value, IniFile, IniSection, "ShowSplitLine")
    IniWrite(MySoftData.ModalSubGuiCtrl.Value, IniFile, IniSection, "IsModalSubGui")
    IniWrite(MySoftData.MutiThreadNumCtrl.Value, IniFile, IniSection, "MutiThreadNum")
    IniWrite(MySoftData.SoftBGColorCon.Value, IniFile, IniSection, "SoftBGColor")
    IniWrite(MySoftData.NoVariableTipCtrl.Value, IniFile, IniSection, "NoVariableTip")
    IniWrite(MySoftData.AdminStartCtrl.Value, IniFile, IniSection, "IsAdminStart")
    IniWrite(MySoftData.CMDTipCtrl.Value, IniFile, IniSection, "CMDTip")
    IniWrite(MySoftData.ScreenShotTypeCtrl.Value, IniFile, IniSection, "ScreenShotType")
    IniWrite(MySoftData.KeyDownDownCon.Value, IniFile, IniSection, "KeyDownDown")
    IniWrite(ToolCheckInfo.ToolCheckHotKeyCtrl.Value, IniFile, IniSection, "ToolCheckHotKey")
    IniWrite(ToolCheckInfo.ToolRecordMacroHotKeyCtrl.Value, IniFile, IniSection, "RecordMacroHotKey")
    IniWrite(ToolCheckInfo.ToolTextFilterHotKeyCtrl.Value, IniFile, IniSection, "ToolTextFilterHotKey")
    IniWrite(ToolCheckInfo.ScreenShotHotKeyCtrl.Value, IniFile, IniSection, "ScreenShotHotKey")
    IniWrite(ToolCheckInfo.FreePasteHotKeyCtrl.Value, IniFile, IniSection, "FreePasteHotKey")
    IniWrite(ToolCheckInfo.RecordKeyboard, IniFile, IniSection, "RecordKeyboard")
    IniWrite(ToolCheckInfo.RecordMouse, IniFile, IniSection, "RecordMouse")
    IniWrite(ToolCheckInfo.RecordJoy, IniFile, IniSection, "RecordJoy")
    IniWrite(ToolCheckInfo.RecordMouseTrail, IniFile, IniSection, "RecordMouseTrail")
    IniWrite(ToolCheckInfo.RecordMouseTrailSpeed, IniFile, IniSection, "RecordMouseTrailSpeed")
    IniWrite(ToolCheckInfo.RecordHoldMuti, IniFile, IniSection, "RecordHoldMuti")
    IniWrite(ToolCheckInfo.RecordAutoLoosen, IniFile, IniSection, "RecordAutoLoosen")
    IniWrite(ToolCheckInfo.RecordJoyInterval, IniFile, IniSection, "RecordJoyInterval")
    IniWrite(ToolCheckInfo.RecordShowBorder, IniFile, IniSection, "RecordShowBorder")
    IniWrite(ToolCheckInfo.OCRTypeCtrl.Value, IniFile, IniSection, "OCRType")
    IniWrite(MySoftData.TabCtrl.Value, IniFile, IniSection, "TableIndex")
    IniWrite(MySoftData.LangCtrl.Text, IniFile, IniSection, "Lang")
    IniWrite(MySoftData.FontTypeCtrl.Text, IniFile, IniSection, "FontType")
    IniWrite(MySoftData.MacroTotalCount, IniFile, IniSection, "MacroTotalCount")
    IniWrite(MySoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    IniWrite(true, IniFile, IniSection, "HasSaved")
    IniWrite(true, IniFile, IniSection, "IsReload")
    SaveCurWinPos()

    IniWrite(MySoftData.CMDPosX, IniFile, IniSection, "CMDPosX")
    IniWrite(MySoftData.CMDPosY, IniFile, IniSection, "CMDPosY")
    IniWrite(MySoftData.CMDWidth, IniFile, IniSection, "CMDWidth")
    IniWrite(MySoftData.CMDHeight, IniFile, IniSection, "CMDHeight")
    IniWrite(MySoftData.CMDBGColor, IniFile, IniSection, "CMDBGColor")
    IniWrite(MySoftData.CMDRunBGColor, IniFile, IniSection, "CMDRunBGColor")
    IniWrite(MySoftData.CMDTransparency, IniFile, IniSection, "CMDTransparency")
    IniWrite(MySoftData.CMDFontColor, IniFile, IniSection, "CMDFontColor")
    IniWrite(MySoftData.CMDFontSize, IniFile, IniSection, "CMDFontSize")
    Reload()
}

CheckValueSettingValid(Name, Value) {
    if (!IsInteger(Value)) {
        MsgBox(Format("{}{}", Name, GetLang("只能是整数")))
        return false
    }
    return true
}

CheckAllValueSettingValid() {
    if (!CheckValueSettingValid(GetLang("点击时间浮动"), MySoftData.HoldFloatCtrl.Value))
        return false

    if (!CheckValueSettingValid(GetLang("每次间隔浮动"), MySoftData.PreIntervalFloatCtrl.Value))
        return false

    if (!CheckValueSettingValid(GetLang("间隔指令浮动"), MySoftData.IntervalFloatCtrl.Value))
        return false

    if (!CheckValueSettingValid(GetLang("坐标X浮动"), MySoftData.CoordXFloatCon.Value))
        return false

    if (!CheckValueSettingValid(GetLang("坐标Y浮动"), MySoftData.CoordYFloatCon.Value))
        return false

    if (!CheckValueSettingValid(GetLang("多线程数"), MySoftData.MutiThreadNumCtrl.Value))
        return false

    return true
}

SaveCurWinPos() {
    MyGui := MySoftData.MyGui
    MyGui.GetPos(&x, &y, &w, &h)
    IniWrite(Format("{}π{}", x, y), IniFile, IniSection, "LastWinPos")

    ListenGui := MyVarListenGui.Gui
    if (MyVarListenGui.Gui != "") {
        ListenGui.GetPos(&x, &y, &w, &h)
        IniWrite(Format("{}π{}", x, y), IniFile, IniSection, "ListenVarPos")
    }
}

OnEditCMDTipGui() {
    MyCMDTipSettingGui.ShowGui()
}

OnTabValueChanged(*) {
    tableItem := MySoftData.TableInfo[MySoftData.TabCtrl.Value]
    MySlider.SwitchTab(tableItem)
}

SwapTableContent(tableItem, indexA, indexB) {
    SwapArrValue(tableItem.SerialArr, indexA, indexB)
    SwapArrValue(tableItem.RemarkArr, indexA, indexB)
    SwapArrValue(tableItem.TKArr, indexA, indexB)
    SwapArrValue(tableItem.TriggerTypeArr, indexA, indexB)
    SwapArrValue(tableItem.HoldTimeArr, indexA, indexB)
    SwapArrValue(tableItem.MacroArr, indexA, indexB)
    SwapArrValue(tableItem.LoopCountArr, indexA, indexB)
    SwapArrValue(tableItem.ForbidArr, indexA, indexB)
    SwapArrValue(tableItem.GifPathArr, indexA, indexB)
}

SwapArrValue(Arr, indexA, indexB, valueType := 1) {
    if (valueType == 3) {
        temp := Arr[indexA].Text
        Arr[indexA].Text := Arr[indexB].Text
        Arr[indexB].Text := temp
    }
    else if (valueType == 2) {
        temp := Arr[indexA].Value
        Arr[indexA].Value := Arr[indexB].Value
        Arr[indexB].Value := temp
    }
    else {
        temp := Arr[indexA]
        Arr[indexA] := Arr[indexB]
        Arr[indexB] := temp
    }
}

PluginInit() {
    global MyWorkPool := WorkPool()
    global MyChineseOcr := 0  ; 懒加载：首次使用时才初始化
    global MyEnglishOcr := 0   ; 懒加载：首次使用时才初始化
    global MyPToken := Gdip_Startup()

    if (MySoftData.HasJoyMacro)
        global ViGJoy := ViGEmXb360()

    ; 构建包含 DLL 文件的目录路径（根据进程位数自动选择 x86 或 x64）
    archDir := (A_PtrSize = 4) ? "x86" : "x64"
    dllDir := A_ScriptDir "\Plugins\OpenCV\" archDir
    ; 使用 SetDllDirectory 将 dllDir 添加到 DLL 搜索路径中
    DllCall("SetDllDirectory", "Str", dllDir)

    OpenCvPath := dllDir "\RMT_OpenCV.dll"
    IBPath := A_ScriptDir "\Plugins\IbInputSimulator.dll"
    DllCall('LoadLibrary', 'str', OpenCvPath, "Ptr")
    DllCall("LoadLibrary", "Str", IBPath)

    RMTPath := A_ScriptDir "\Plugins\RMT\RMT.dll"
    RMT_ASM := CLR_LoadLibrary(RMTPath)   ;加载RMT程序集
    global RMT_Http := RMT_ASM.CreateInstance("RMT.Http")     ; 创建对象实例

    SetTimer(CheckOcrIdle, 60000)   ;60秒后，释放Ocr资源

    XAMLHost.Prewarm()
}

OnToolAlwaysOnTop(*) {
    global MySoftData, ToolCheckInfo
    state := ToolCheckInfo.AlwaysOnTopCtrl.Value
    if (state) {
        MySoftData.MyGui.Opt("+AlwaysOnTop")
    }
    else {
        MySoftData.MyGui.Opt("-AlwaysOnTop")
    }
}

InitFilePath() {
    if (!DirExist(A_WorkingDir "\Setting")) {
        DirCreate(A_WorkingDir "\Setting")
    }
    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName)) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName)
    }

    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UseExplain")) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UseExplain")
    }

    if (!DirExist(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot")) {
        DirCreate(A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot")
    }

    filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\使用说明&署名.txt"
    if (!FileExist(filePath)) {
        str1 := GetLang("协议：CC BY - NC - SA 4.0")
        str2 := GetLang("原始来源：RMT(若梦兔) 软件导出")
        str3 := GetLang("说明：仅限非商业用途，转载请注明来源并保持相同协议")
        Str := Format("{}`n{}`n{}", str1, str2, str3)
        FileAppend(Str, filePath, "UTF-16")
    }

    if (!DirExist(A_WorkingDir "\Images")) {
        DirCreate(A_WorkingDir "\Images")
    }
    if (!DirExist(A_WorkingDir "\Images\Soft")) {
        DirCreate(A_WorkingDir "\Images\Soft")
    }

    if (!DirExist(A_WorkingDir "\Images\ScreenShot")) {
        DirCreate(A_WorkingDir "\Images\ScreenShot")
    }

    if (!DirExist(A_WorkingDir "\Images\FreePaste")) {
        DirCreate(A_WorkingDir "\Images\FreePaste")
    }

    FileInstall("Images\Soft\WeiXin.png", "Images\Soft\WeiXin.png", 1)
    FileInstall("Images\Soft\ZhiFuBao.png", "Images\Soft\ZhiFuBao.png", 1)
    FileInstall("Images\Soft\rabit.ico", "Images\Soft\rabit.ico", 1)
    FileInstall("Images\Soft\IcoPause.ico", "Images\Soft\IcoPause.ico", 1)
    FileInstall("Images\Soft\GreenColor.png", "Images\Soft\GreenColor.png", 1)
    FileInstall("Images\Soft\RedColor.png", "Images\Soft\RedColor.png", 1)
    FileInstall("Images\Soft\YellowColor.png", "Images\Soft\YellowColor.png", 1)
    FileInstall("Images\Soft\Target.png", "Images\Soft\Target.png", 1)

    ;图标
    FileInstall("Images\Soft\Key.png", "Images\Soft\Key.png", 1)
    FileInstall("Images\Soft\Interval.png", "Images\Soft\Interval.png", 1)
    FileInstall("Images\Soft\Search.png", "Images\Soft\Search.png", 1)
    FileInstall("Images\Soft\SearchPro.png", "Images\Soft\SearchPro.png", 1)
    FileInstall("Images\Soft\Move.png", "Images\Soft\Move.png", 1)
    FileInstall("Images\Soft\MovePro.png", "Images\Soft\MovePro.png", 1)
    FileInstall("Images\Soft\Output.png", "Images\Soft\Output.png", 1)
    FileInstall("Images\Soft\Run.png", "Images\Soft\Run.png", 1)
    FileInstall("Images\Soft\Var.png", "Images\Soft\Var.png", 1)
    FileInstall("Images\Soft\Extract.png", "Images\Soft\Extract.png", 1)
    FileInstall("Images\Soft\Operation.png", "Images\Soft\Operation.png", 1)
    FileInstall("Images\Soft\If.png", "Images\Soft\If.png", 1)
    FileInstall("Images\Soft\rabit.png", "Images\Soft\rabit.png", 1)
    FileInstall("Images\Soft\Sub.png", "Images\Soft\Sub.png", 1)
    FileInstall("Images\Soft\Mouse.png", "Images\Soft\Mouse.png", 1)
    FileInstall("Images\Soft\True.png", "Images\Soft\True.png", 1)
    FileInstall("Images\Soft\False.png", "Images\Soft\False.png", 1)
    FileInstall("Images\Soft\Loop.png", "Images\Soft\Loop.png", 1)
    FileInstall("Images\Soft\LoopBody.png", "Images\Soft\LoopBody.png", 1)
    FileInstall("Images\Soft\LoopCount.png", "Images\Soft\LoopCount.png", 1)
    FileInstall("Images\Soft\Condition.png", "Images\Soft\Condition.png", 1)
    FileInstall("Images\Soft\IfPro.png", "Images\Soft\IfPro.png", 1)
    FileInstall("Images\Soft\Arr.png", "Images\Soft\Arr.png", 1)
    FileInstall("Images\Soft\Input.png", "Images\Soft\Input.png", 1)
    FileInstall("Images\Soft\TextOps.png", "Images\Soft\TextOps.png", 1)
    FileInstall("Images\Soft\FileIO.png", "Images\Soft\FileIO.png", 1)
    FileInstall("Images\Soft\Control.png", "Images\Soft\Control.png", 1)
    FileInstall("Images\Soft\WindowManage.png", "Images\Soft\WindowManage.png", 1)
    FileInstall("Images\Soft\KeyCheck.png", "Images\Soft\KeyCheck.png", 1)

    global VBSPath := A_WorkingDir "\MinTool\PlayAudio.vbs"
    global StartTipAudio := A_WorkingDir "\Audio\Start.wav"
    global EndTipAudio := A_WorkingDir "\Audio\End.wav"
    global ViGEmDllPath := A_WorkingDir "\Plugins\ViGEm\ViGEmWrapper.dll"
    global ArrayFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\ArrayFile.ini"
    global MacroFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MacroFile.ini"
    global SearchFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SearchFile.ini"
    global SearchProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SearchProFile.ini"
    global CompareFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\CompareFile.ini"
    global CompareProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\CompareProFile.ini"
    global MMProFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MMProFile.ini"
    global BGKeyFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\BGKeyFile.ini"
    global TimingFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\TimingFile.ini"
    global RunFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\RunFile.ini"
    global OutputFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\OutputFile.ini"
    global VariableFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\VariableFile.ini"
    global ExVariableFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\ExVariableFile.ini"
    global TextOpsFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\TextOpsFile.ini"
    global SubMacroFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\SubMacroFile.ini"
    global LoopFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\LoopFile.ini"
    global OperationFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\OperationFile.ini"
    global BGMouseFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\BGMouseFile.ini"
    global InputFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\InputFile.ini"
    global FileIOFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\FileIOFile.ini"
    global WindowManageFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\WindowManageFile.ini"
    global KeyCheckFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\KeyCheckFile.ini"
}

SubMacroStopAction(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    WorkerIndex := tableItem.IsWorkIndexArr[itemIndex]
    if (WorkerIndex != 0) {
        MyWorkPool.BroadcastStop(tableIndex, itemIndex)
        tableItem.IsWorkIndexArr[itemIndex] := 0
    }
    else
        KillTableItemMacro(tableItem, itemIndex)
}

SetGlobalArray(Name, Value) {
    MySoftData.ArrayMap[Name] := Value
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("SetArray", Name, GetArrayStr(Value))
}

CloneGlobalArray(SourceArr, NewArrName) {
    MySoftData.ArrayMap[NewArrName] := SourceArr.Clone()
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("CloneArray", GetArrayStr(SourceArr), NewArrName)
}

DeleteGlobalArray(ArrName) {
    MySoftData.ArrayMap.Delete(ArrName)
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("DeleteArray", ArrName)
}

ModifyGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
    ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
    SourceArr[Index] := Value
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("ModifyArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
}

InsertGlobalArray(ArrName, MainIndex, Index, IsArrayValue, Value) {
    ValueStr := IsArrayValue ? GetArrayStr(Value) : Value
    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
    SourceArr.InsertAt(Index, Value)
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("InsertArray", ArrName, MainIndex, Index, IsArrayValue, ValueStr)
}

RemoveAtGlobalArray(ArrName, MainIndex, Index) {
    SourceArr := MainIndex == 0 ? MySoftData.ArrayMap[ArrName] : MySoftData.ArrayMap[ArrName][MainIndex]
    SourceArr.RemoveAt(Index)
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("RemoveAtArray", ArrName, MainIndex, Index)
}

SetGlobalVariable(NameArr, ValueArr, ignoreExist) {
    RealNameArr := NameArr.Clone()
    RealValueArr := ValueArr.Clone()
    if (ignoreExist) {
        RealNameArr := []
        RealValueArr := []
        loop NameArr.Length {
            if (!MySoftData.VariableMap.Has(NameArr[A_Index])) {
                RealNameArr.Push(NameArr[A_Index])
                RealValueArr.Push(ValueArr[A_Index])
            }
        }
    }
    if (RealNameArr.Length == 0)
        return

    loop RealNameArr.Length {
        MySoftData.VariableMap[RealNameArr[A_Index]] := ValueArr[A_Index]
    }
    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("SetVari", RealNameArr, RealValueArr)
}

DelGlobalVariable(NameArr) {
    RealNameArr := []
    loop NameArr.Length {
        if (MySoftData.VariableMap.Has(NameArr[A_Index])) {
            MySoftData.VariableMap.Delete(NameArr[A_Index])
            RealNameArr.Push(NameArr[A_Index])
        }
    }

    if (RealNameArr.Length == 0)
        return

    MyVarListenGui.Refresh()
    MyWorkPool.Broadcast("DelVari", RealNameArr)
}

SetCMDTipValue(value) {
    MyWorkPool.Broadcast("CMDTip", value)
}

CMDReport(CMDStr) {
    MyCMDTipGui.ShowGui(CMDStr)
}

;0默认状态 1运行 2暂停 3终止
SetTableItemState(tableIndex, itemIndex, State) {
    tableItem := MySoftData.TableInfo[tableIndex]
    LastState := tableItem.ColorStateArr[itemIndex]

    if (LastState == 0 && (State == 2 || State == 3))
        return

    if (State == 2 && LastState != 1)
        return
    if (State == 3 && LastState == 3)
        return

    if (State == 3) {
        StopCancelTableItemTimer(tableIndex, itemIndex)
        timerFunc := CancelTableItemStopState.Bind(tableIndex, itemIndex)
        timerKey := tableIndex "|" itemIndex
        CancelTableItemTimerMap[timerKey] := timerFunc
        SetTimer(timerFunc, -5000)
    }
    else if (LastState == 3)
        StopCancelTableItemTimer(tableIndex, itemIndex)

    UpdateMacroRunningCount(LastState, State)
    tableItem.ColorStateArr[itemIndex] := State
    RefreshItemColorUI(tableIndex, itemIndex)
}

RefreshItemColorUI(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    State := tableItem.ColorStateArr[itemIndex]
    isVisible := State != 0

    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    if (ItemUsePool.Has(itemIndex)) {
        ItemConObj := ItemUsePool[itemIndex]
        ItemConObj.ColorCon.Value := GetItemColorValue(State)
        ItemConObj.ColorCon.Visible := isVisible
    }
}

CancelTableItemStopState(tableIndex, itemIndex) {
    tableItem := MySoftData.TableInfo[tableIndex]
    if (tableItem.ColorStateArr[itemIndex] == 3) {
        if (tableItem.IsWorkIndexArr.Length >= itemIndex && tableItem.IsWorkIndexArr[itemIndex] != 0)
            return

        tableItem.ColorStateArr[itemIndex] := 0
        ; 同步清除 KilledArr，確保狀態完全恢復可再次觸發
        if (tableItem.KilledArr.Length >= itemIndex)
            tableItem.KilledArr[itemIndex] := false
        UpdateMacroRunningCount(3, 0)
        RefreshItemColorUI(tableIndex, itemIndex)
    }
}

global CancelTableItemTimerMap := Map()

StopCancelTableItemTimer(tableIndex, itemIndex) {
    timerKey := tableIndex "|" itemIndex
    if (CancelTableItemTimerMap.Has(timerKey)) {
        SetTimer(CancelTableItemTimerMap[timerKey], 0)
        CancelTableItemTimerMap.Delete(timerKey)
    }
}

SetItemPauseState(tableIndex, itemIndex, state) {
    tableItem := MySoftData.TableInfo[tableIndex]
    tableItem.PauseArr[itemIndex] := state

    LastColorState := tableItem.ColorStateArr[itemIndex]
    if (LastColorState == 1 && state == 1)
        SetTableItemState(tableIndex, itemIndex, 2)
    else if (LastColorState == 2 && state == 0)
        SetTableItemState(tableIndex, itemIndex, 1)

    MyWorkPool.Broadcast("PauseState", tableIndex, itemIndex, state)
}

;恢复意外退出残留的脏状态，后面要换成热重载就会要
RecoverAllDirtyStates() {
    loop MySoftData.TableInfo.Length {
        tableItem := MySoftData.TableInfo[A_Index]
        if (!tableItem.ColorStateArr.Length)
            continue
        loop tableItem.ColorStateArr.Length {
            if (tableItem.ColorStateArr[A_Index] != 0) {
                tableItem.ColorStateArr[A_Index] := 0
                if (tableItem.IsWorkIndexArr.Length >= A_Index)
                    tableItem.IsWorkIndexArr[A_Index] := 0
                RefreshItemColorUI(tableItem.Index, A_Index)
            }
        }
    }

    tableItem := MySoftData.SpecialTableItem
    if (tableItem.ColorStateArr.Length >= 1 && tableItem.ColorStateArr[1] != 0) {
        tableItem.ColorStateArr[1] := 0
        RefreshItemColorUI(tableItem.Index, 1)
    }

    if (MySoftData.MacroRunningCount != 0) {
        MySoftData.MacroRunningCount := 0
        MySoftData.IsMacroWorking := false
        MyCMDTipGui.OnToggleMacroWorkState()
    }
}

CleanupAllMacroStates() {
    RecoverAllDirtyStates()
}

MsgBoxContent(content) {
    MySoftData.MyGui.Flash()
    SoundPlay "*-1"
    MyMsgboxGui.ShowGui(content)
}

MacroCount(content) {
    if (content == "Add") {
        MySoftData.MacroTotalCount += 1
    }
}

ViGJoySetState(JoyType, Key, Value) {
    if (!IsSet(ViGJoy))
        global ViGJoy := ViGEmXb360()

    if (ViGJoy.Instance == "")
        return

    if (JoyType == "Btn")
        ViGJoy.Buttons[Key].SetState(Value)
    else if (JoyType == "Axis")
        ViGJoy.Axes[Key].SetState(Value)
    else if (JoyType == "Dpad")
        ViGJoy.Dpad.SetState(Key)
}

ToolTipContent(content) {
    MySoftData.ToolTipText := content
    MySoftData.ToolTipEndTime := A_TickCount + 5000  ; 设置5秒后结束的时间戳
    SetTimer(ToolTipTimer, 100)  ; 启动/重置定时器，每100ms执行一次
}

ToolTipTimer() {
    if (A_TickCount >= MySoftData.ToolTipEndTime) {
        ; 超过显示时间，隐藏ToolTip并停止定时器
        ToolTip
        SetTimer(ToolTipTimer, 0)
    } else {
        ; 仍在显示时间内，更新ToolTip
        ToolTip(MySoftData.ToolTipText)
    }
}

ExcuteRMTCMDAction(Cmd) {
    paramArr := StrSplit(Cmd, "⫶")
    switch paramArr[2] {
        case "截图":
            OnToolScreenShot()
        case "截图提取文本":
            OnToolTextFilterScreenShot()
        case "自由贴":
            OnToolFreePaste()
        case "开启指令显示":
            MySoftData.CMDTipCtrl.Value := true
            MySoftData.CMDTip := true
            SetCMDTipValue(true)
            MyCMDTipGui.ShowGui("开启指令显示")
        case "关闭指令显示":
            MySoftData.CMDTipCtrl.Value := false
            MySoftData.CMDTip := false
            SetCMDTipValue(false)
            if (!IsObject(MyCMDTipGui.Gui))
                return

            try {
                style := WinGetStyle(MyCMDTipGui.Gui.Hwnd)
                isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                if (isVisible)
                    MyCMDTipGui.Gui.Hide()
            }
        case "开启变量监视":
            RefreshListenVarGui(true)
        case "关闭变量监视":
            if (!IsObject(MyVarListenGui.Gui))
                return

            try {
                style := WinGetStyle(MyVarListenGui.Gui.Hwnd)
                isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                if (isVisible) {
                    MyVarListenGui.Gui.Hide()
                    IniWrite(false, IniFile, IniSection, "IsOpenListenVar")
                }
            }
        case "显示菜单":
            OpenMenuWheel(paramArr[3], false)
        case "关闭菜单":
            CloseMenuWheel()
        case "启用键鼠":
            BlockInput false
        case "禁用键鼠":
            BlockInput true
        case "置顶或取消":
            WinSetAlwaysOnTop -1, "A"
        case "透明度":
            WinSetTransparent Round(255 * (100 - paramArr[3]) / 100), "A"
        case "休眠":
            OnSuspendHotkey()
        case "暂停所有宏":
            SetPauseState(true)
        case "恢复所有宏":
            SetPauseState(false)
        case "终止所有宏":
            OnKillAllMacro()
        case "重载":
            MenuReload()
        case "关闭软件":
            ExitApp()
    }
}

ScreenShot(X1, Y1, X2, Y2, FileName) {
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)
    Gdip_SaveBitmapToFile(pBitmap, FileName)
    ; 释放位图资源
    Gdip_DisposeImage(pBitmap)
}

OnToolTextFilterGetArea(x1, y1, x2, y2) {
    filePath := A_WorkingDir "\Images\ScreenShot\TextFilter.png"
    ScreenShot(x1, y1, x2, y2, filePath)
    ocr := ToolCheckInfo.OCRTypeCtrl.Value == 1 ? GetChineseOcr() : GetEnglishOcr()
    result := ocr.ocr_from_file(filePath)
    ToolCheckInfo.ToolTextCtrl.Value := result
    SetClipboard(result)
}

OnToolTextCheckScreenShot() {
    ; 如果剪贴板中有图像
    if DllCall("IsClipboardFormatAvailable", "uint", 8)  ; 8 是 CF_BITMAP 格式
    {
        filePath := A_WorkingDir "\Images\ScreenShot\TextFilter.png"
        SaveClipToBitmap(filePath)
        ocr := ToolCheckInfo.OCRTypeCtrl.Value == 1 ? GetChineseOcr() : GetEnglishOcr()
        result := ocr.ocr_from_file(filePath)
        ToolCheckInfo.ToolTextCtrl.Value := result
        SetClipboard(result)
        ; 停止监听
        SetTimer(, 0)
    }
}

TogGetSelectArea(isEnable, action := "") {
    if (isEnable && action != "") {
        MySoftData.GetAreaAction := action
    }
    else {
        MySoftData.GetAreaAction := ""
    }
}

OnGetSelectAreaDown(kye, *) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY)
    MySoftData.StartAreaPosX := startX
    MySoftData.StartAreaPosY := startY
}

OnGetSelectAreaUp(key, *) {
    action := MySoftData.GetAreaAction
    TogGetSelectArea(false)
    CoordMode("Mouse", "Screen")
    MouseGetPos(&endX, &endY)

    x1 := Min(MySoftData.StartAreaPosX, endX)
    y1 := Min(MySoftData.StartAreaPosY, endY)
    x2 := Max(MySoftData.StartAreaPosX, endX)
    y2 := Max(MySoftData.StartAreaPosY, endY)
    action(x1, y1, x2, y2)
}

TogSelectArea(isEnable, action := "") {
    if (isEnable && action != "") {
        MySoftData.SelectAreaAction := action
        ToolTipContent(GetLang("请框选截图范围"))
        actionDown := OnBindKeyDown.Bind("LButton")
        Hotkey("LButton", actionDown)
    }
    else {
        MySoftData.ToolTipEndTime := 0
        MySoftData.SelectAreaAction := ""
    }
}

SelectArea() {
    action := MySoftData.SelectAreaAction
    TogSelectArea(false)
    actionDown := OnBindKeyDown.Bind("LButton")
    Hotkey("~LButton", actionDown, "On")
    ; 获取起始点坐标
    startX := startY := endX := endY := 0
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY)

    ; 创建 GUI 用于绘制矩形框
    MyGui := Gui("+ToolWindow -Caption +AlwaysOnTop -DPIScale")
    MyGui.BackColor := "Red"
    WinSetTransColor(" 150", MyGui)
    MyGui.Opt("+LastFound")
    GuiHwnd := WinExist()

    ; 显示初始 GUI
    MyGui.Show("NA x" startX " y" startY " w1 h1")

    ; 跟踪鼠标移动
    while GetKeyState("LButton", "P") {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&endX, &endY)
        width := Abs(endX - startX)
        height := Abs(endY - startY)
        x := Min(startX, endX)
        y := Min(startY, endY)

        MyGui.Show("NA x" x " y" y " w" width " h" height)
    }
    ; 销毁 GUI
    MyGui.Destroy()
    ; 返回坐标

    x1 := Min(startX, endX)
    y1 := Min(startY, endY)
    x2 := Max(startX, endX)
    y2 := Max(startY, endY)
    action(x1, y1, x2, y2)
}

SimpleRecordMacroStr(MacroStr) {
    CmdArr := SplitMacro(MacroStr)
    SimpleCmdArr := []
    loop CmdArr.Length {
        paramArr := SplitCommand(CmdArr[A_Index])
        isPressKey := paramArr[1] == GetLang("按键") && paramArr[3] == GetLang("按下")
        if (isPressKey && A_Index + 1 < CmdArr.Length) {
            next1ParamArr := SplitCommand(CmdArr[A_Index + 1])
            next2ParamArr := SplitCommand(CmdArr[A_Index + 2])
            isMatchFormat := next1ParamArr[1] == GetLang("间隔") && next2ParamArr[1] == GetLang("按键")
            if (isMatchFormat && paramArr[2] == next2ParamArr[2] && next2ParamArr[3] == "松开") {
                SimpleCmdStr := Format("{}_{}_{}_{}", GetLang("按键"), paramArr[2], GetLang("点击"), next1ParamArr[2])
                SimpleCmdArr.Push(SimpleCmdStr)
                A_Index := A_Index + 2
                continue
            }
        }
        SimpleCmdArr.Push(CmdArr[A_Index])
    }

    return GetMacroStrByCmdArr(SimpleCmdArr)
}

DiscardRecordTriggerKey(MacroStr, isFront) {
    triggerMap := GetRecordTriggerKeyMap()
    CmdArr := SplitMacro(MacroStr)
    SimpleCmdArr := []
    hasDiscard := false
    loop CmdArr.Length {
        cmd := isFront ? CmdArr[A_Index] : CmdArr[CmdArr.Length - A_Index + 1]

        if (!hasDiscard) {
            if (isFront && MySoftData.IsTogStartRecord) {
                hasDiscard := true
            }
            else if (!isFront && MySoftData.IsTogEndRecord) {
                hasDiscard := true
            }
            else {
                if (InStr(cmd, GetLang("间隔")))
                    continue

                if (!isFront) {
                    moveArr := SplitCommand(cmd)
                    if (moveArr.Length >= 4 && moveArr[moveArr.Length] == "2")
                        continue
                }

                if (CheckIfDiscardCMD(triggerMap, cmd))
                    continue

                hasDiscard := true
            }
        }

        if (isFront)
            SimpleCmdArr.Push(cmd)
        else
            SimpleCmdArr.InsertAt(1, cmd)
    }

    return GetMacroStrByCmdArr(SimpleCmdArr)
}

CheckIfDiscardCMD(triggerMap, cmd) {
    if (!InStr(cmd, GetLang("按键")) || InStr(cmd, GetLang("按键检测")))
        return false

    paramArr := SplitCommand(cmd)
    if (triggerMap.Has(paramArr[2]) && triggerMap[paramArr[2]] < 2) {
        triggerMap[paramArr[2]] += 1
        return true
    }

    return false
}

FullCopyCmd(cmdStr, CopyedMap := Map()) {
    paramArr := SplitCommand(cmdStr)
    paramArr[1] := GetCmdStr(paramArr[1])
    if (paramArr[1] == GetLang("间隔"))
        return cmdStr
    if (paramArr[1] == GetLang("按键"))
        return cmdStr
    if (paramArr[1] == GetLang("移动"))
        return cmdStr
    if (paramArr[1] == GetLang("RMT指令"))
        return cmdStr

    if (CopyedMap.Has(paramArr[1])) {
        paramArr[1] := CopyedMap[paramArr[1]]
        return GetCmdByParams(paramArr)
    }

    textOnly := GetCmdOnlyText(paramArr[1])
    cmd := GetLangKey(textOnly)
    dataFile := MySoftData.DataFileMap[cmd]
    Data := GetMacroCMDData(paramArr[1]).Clone()
    Data.SerialStr := GetCMDSerialStr(cmd)
    numbersOnly := RegExReplace(Data.SerialStr, "\D+")
    CommandStr := Format("{}{}", textOnly, numbersOnly)
    CopyedMap.Set(paramArr[1], CommandStr)
    paramArr[1] := CommandStr

    ;如果， 搜索， 搜索Pro
    if (ObjHasOwnProp(Data, "TrueMacro")) {
        Data.TrueMacro := FullCopyMacro(Data.TrueMacro, CopyedMap)
    }

    if (ObjHasOwnProp(Data, "FalseMacro")) {
        Data.FalseMacro := FullCopyMacro(Data.FalseMacro, CopyedMap)
    }

    ;循环
    if (ObjHasOwnProp(Data, "LoopBody")) {
        Data.LoopBody := FullCopyMacro(Data.LoopBody, CopyedMap)
    }

    ;如果Pro
    if (ObjHasOwnProp(Data, "MacroArr") && ObjHasOwnProp(Data, "DefaultMacro")) {
        Data.DefaultMacro := FullCopyMacro(Data.DefaultMacro, CopyedMap)
        loop Data.MacroArr.Length {
            Data.MacroArr[A_Index] := FullCopyMacro(Data.MacroArr[A_Index], CopyedMap)
        }
    }

    SaveMacroCMDData(Data)
    res := GetCmdByParams(paramArr)
    return res
}

FullCopyMacro(MacroStr, CopyedMap) {
    if (MacroStr == "")
        return MacroStr
    cmdArr := SplitMacro(MacroStr)
    loop cmdArr.Length {
        cmdArr[A_Index] := FullCopyCmd(cmdArr[A_Index], CopyedMap)
    }

    result := ""
    for index, value in cmdArr {
        result .= value
        if (index != cmdArr.Length)
            result .= ","
    }
    return result
}

GetPixelColorMap(CentPosX, CentPosY, Row, Col) {
    width := Col
    height := Row
    PosX := Integer(CentPosX - (Col - 1) / 2)
    PosY := Integer(CentPosY - (Row - 1) / 2)
    pBitmap := Gdip_BitmapFromScreen(PosX "|" PosY "|" width "|" height)
    ResultMap := Map()
    loop Row {
        rowValue := A_Index
        loop Col {
            colValue := A_Index
            Value := Gdip_GetPixel(pBitmap, colValue - 1, rowValue - 1)
            Key := Format("{}-{}", colValue, rowValue)
            RGB_Value := Value & 0xFFFFFF  ; 移除Alpha通道，保留RGB
            hexStr := Format("0x{:X}", RGB_Value)
            ResultMap.Set(Key, hexStr)
        }
    }
    return ResultMap
}

SavePixelImage(PosX, PosY, SavePath) {
    ; 创建位图
    RowNum := 9
    ColNum := 13
    width := 130, height := 90
    pBitmap := Gdip_CreateBitmap(width, height)
    G := Gdip_GraphicsFromImage(pBitmap)
    CoordMode("Pixel", "Screen")

    loop RowNum {
        RowValue := A_Index
        loop ColNum {
            ColValue := A_Index

            CurPosX := PosX - (ColNum - 1) / 2 + ColValue
            CurPosY := PosY - (RowNum - 1) / 2 + RowValue
            ColorValue := PixelGetColor(CurPosX, CurPosY)
            ColorValue := "0xFF" SubStr(ColorValue, 3)
            pBrush := Gdip_BrushCreateSolid(ColorValue)
            Gdip_FillRectangle(G, pBrush, (ColValue - 1) * 10, (RowValue - 1) * 10, 10, 10)
            Gdip_DeleteBrush(pBrush)
        }
    }

    ; 保存临时图片文件
    Gdip_SaveBitmapToFile(pBitmap, SavePath)

    ; 清理资源
    Gdip_DeleteGraphics(G)
    Gdip_DisposeImage(pBitmap)
}

FormatIntegerWithCommas(num) {
    return RegExReplace(num, "(\d)(?=(\d{3})+$)", "$1,")
}

CheckIfMenuBtnHotKey(key) {
    if (IsNumber(key)) {
        return Integer(key) >= 1 && Integer(key) <= 8
    }
    return false
}

OpenMenuWheel(MenuIndex, isTog) {
    if (IsObject(MyMenuWheel) && MyMenuWheel.isOpen && MySoftData.CurMenuWheelIndex == MenuIndex) {
        if (isTog)
            CloseMenuWheel()
        return
    }

    MySoftData.CurMenuWheelIndex := MenuIndex
    MyMenuWheel.ShowGui(MenuIndex)

    ;重新绑定一下，让菜单按钮快捷键不会被输入
    BindMenuHotKey()
    BindTabHotKey()
    BindSoftHotKey()
}

CloseMenuWheel() {
    MyMenuWheel.Close()
}

IsBootStart() {
    regPath := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        value := RegRead(regPath, "RMT")
        if (value != "")
            return true
    }

    return false
}

CorrectRemark(CommandStr, Remark) {
    charsToRemove := [",", "，", "`n", "⫶", "_"]
    ; 循环删除每个字符
    for char in charsToRemove {
        Remark := StrReplace(Remark, char)
    }
    if (Remark != "") {
        CommandStr .= "_" Remark
    }
    return CommandStr
}

OnTriggerSepcialItemMacro(MacroStr) {
    tableItem := MySoftData.SpecialTableItem
    tableItem.KilledArr[1] := false
    tableItem.PauseArr[1] := 0
    tableItem.ActionCount[1] := 0
    tableItem.index := 1
    tableItem.ColorStateArr[1] := 1
    UpdateMacroRunningCount(0, 1)
    RefreshItemColorUI(tableItem.Index, 1)
    OnTriggerMacroOnce(tableItem, MacroStr, 1)
    tableItem.ColorStateArr[1] := 0
    UpdateMacroRunningCount(1, 0)
    RefreshItemColorUI(tableItem.Index, 1)
}

HandleOpenArg() {
    if (A_Args.Length <= 0) {
        if (MySoftData.IsAdminStart && !A_IsAdmin)
            ElevateToAdmin()
        return
    }

    loop A_Args.Length {
        arg := A_Args[A_Index]
        if (arg == "-min") {
            MySoftData.IsMinStart := true
            continue
        }
        if (arg == "-admin") {
            if (!A_IsAdmin) {
                ElevateToAdmin()
            }
            continue
        }
    }
}

ElevateToAdmin() {
    args := ""
    loop A_Args.Length {
        arg := A_Args[A_Index]
        if (arg != "-admin")
            args .= ' "' arg '"'
    }
    try {
        Run('*RunAs "' A_ScriptFullPath '" ' args)
        ExitApp()
    }
}

SetEditData() {
    visitMap := Map()
    loop MySoftData.TabNameArr.Length {
        tableIndex := A_Index
        tableItem := MySoftData.TableInfo[tableIndex]
        isMacro := CheckIsMacroTable(tableIndex)
        if (!isMacro)
            continue

        for index, value in tableItem.ModeArr {
            if (tableItem.MacroArr.Length < index || tableItem.MacroArr[index] == "")
                continue

            macroStr := tableItem.MacroArr[index]
            SetGlobalData(macroStr, visitMap)
        }
    }
}

;0默认状态 1运行 2暂停 3终止
UpdateMacroRunningCount(LastState, State) {
    value := 0
    if ((LastState == 0 || LastState == 3) && State == 1) ;运行+1
        value := 1
    else if (LastState == 1 && State != 1)  ;结束 | 暂停 | 终止 -1
        value := -1
    else if (LastState == 2 && State == 1)  ;取消暂停+1
        value := 1

    MySoftData.MacroRunningCount += value
    if (MySoftData.MacroRunningCount < 0)
        MySoftData.MacroRunningCount := 0

    curState := MySoftData.MacroRunningCount > 0
    if (curState != MySoftData.IsMacroWorking) {
        MySoftData.IsMacroWorking := curState
        MyCMDTipGui.OnToggleMacroWorkState()
    }
}

;批量移除文件的“来自互联网”标记（Zone.Identifier）。 防止文件被锁定
UnblockZoneIdentifier() {
    markerFile := A_WorkingDir "\Setting\.unblocked"
    if (FileExist(markerFile)) {
        markerTime := FileGetTime(markerFile)
        exeTime := FileGetTime(A_ScriptFullPath)
        if (exeTime <= markerTime)
            return
    }

    try {
        fullCmd := 'powershell.exe -NoProfile -WindowStyle Hidden -Command "Get-ChildItem -Path "' A_ScriptDir '" -Recurse -File | ForEach-Object { try { Unblock-File -Path $_.FullName -ErrorAction Stop } catch {} }; if ($?) { New-Item -Path "' markerFile '" -ItemType File -Force | Out-Null }"'
        Run(fullCmd, , "Hide")
    }
}