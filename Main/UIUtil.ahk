;窗口&UI刷新
InitUI() {
    global MySoftData
    MyGui := Gui()
    MyGui.Title := "RMTv1.1F1"
    MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)
    isValidCollor := RegExMatch(MySoftData.SoftBGColor, "^([0-9A-Fa-f]{6})$")
    BGColor := isValidCollor ? MySoftData.SoftBGColor : "f0f0f0"
    if (BGColor != "f0f0f0")
        MyGui.BackColor := BGColor

    MySoftData.MyGui := MyGui
    AddUI()
    CustomTrayMenu()
    OnOpen()

}

OnOpen() {
    global MySoftData
    if (!MySoftData.AgreeAgreement) {
        Agreement1 := GetLang('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。')
        Agreement2 := GetLang("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。")
        Agreement3 := GetLang("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。")
        Agreement4 := GetLang("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。")
        Agreement5 := GetLang("若不同意上述条款，请立即停止使用本软件。")
        AgreeAgreementStr := Format("{}`n{}`n{}`n{}`n{}", Agreement1, Agreement2, Agreement3, Agreement4, Agreement5)
        result := MsgBox(AgreeAgreementStr, GetLang("免责声明"), "4")
        if (result == "No")
            ExitApp()
        IniWrite(true, IniFile, IniSection, "AgreeAgreement")
    }

    if (IsSet(IsMinStart) && IsMinStart)
        return

    uptimeMs := DllCall("GetTickCount64", "Int64")
    if (uptimeMs <= 120 * 1000 && IsBootStart() && !MySoftData.IsReload)
        return

    RefreshGui()
}

RefreshGui() {
    LastWinPosStr := IniRead(IniFile, IniSection, "LastWinPos", "")
    WinPosArr := StrSplit(LastWinPosStr, "π")
    IniWrite(false, IniFile, IniSection, "IsReload")

    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MySoftData.MyGui.Show(Format("x{} y{} w{} h{}", WinPosArr[1], WinPosArr[2], 1070, 590))
            RefreshListenVarGui()
            return
        }
    }

    if (MySoftData.LastShowMonth != A_Mon) {
        MySoftData.TabCtrl.Value := 9
        MySoftData.LastShowMonth := A_Mon
        IniWrite(MySoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    }

    MySoftData.MyGui.Show(Format("w{} h{}", 1070, 590))
    RefreshListenVarGui()
}

RefreshListenVarGui(isForce := false) {
    IsOenListVar := IniRead(IniFile, IniSection, "IsOpenListenVar", false)
    if (!isForce && !IsOenListVar)
        return

    LastPosStr := IniRead(IniFile, IniSection, "ListenVarPos", "")
    WinPosArr := StrSplit(LastPosStr, "π")
    if (WinPosArr.Length == 2 && IsNumber(WinPosArr[1]) && IsNumber(WinPosArr[2])) {
        VirtualWidth := SysGet(78)
        VirtualHeight := SysGet(79)
        isXValid := WinPosArr[1] > 0 && WinPosArr[1] < VirtualWidth
        isYValid := WinPosArr[2] > 0 && WinPosArr[2] < VirtualHeight
        if (isXValid && isYValid) {
            MyVarListenGui.ShowGui()
            MyVarListenGui.Gui.Show(Format("x{} y{}", WinPosArr[1], WinPosArr[2]))
            return
        }
    }

    MyVarListenGui.ShowGui()
}

RefreshToolUI() {
    global ToolCheckInfo

    ToolCheckInfo.ToolMousePosCtrl.Value := ToolCheckInfo.PosStr
    ToolCheckInfo.ToolProcessNameCtrl.Value := ToolCheckInfo.ProcessName
    ToolCheckInfo.ToolProcessTileCtrl.Value := ToolCheckInfo.ProcessTile
    ToolCheckInfo.ToolProcessPidCtrl.Value := ToolCheckInfo.ProcessPid
    ToolCheckInfo.ToolProcessClassCtrl.Value := ToolCheckInfo.ProcessClass
    ToolCheckInfo.ToolProcessIdCtrl.Value := ToolCheckInfo.ProcessId
    ToolCheckInfo.ToolColorCtrl.Value := ToolCheckInfo.Color
    ToolCheckInfo.ToolMouseWinPosCtrl.Value := ToolCheckInfo.WinPosStr
}

;UI元素相关函数
AddUI() {
    global MySoftData
    MyGui := MySoftData.MyGui
    AddOperBtnUI()
    MySoftData.TabPosY := 10
    MySoftData.TabPosX := 130
    MySoftData.TabCtrl := MyGui.Add("Tab3", Format("x{} y{} w{} Choose{}", MySoftData.TabPosX, MySoftData.TabPosY, 910,
        MySoftData.TableIndex), GetLangArr(MySoftData.TabNameArr))

    loop MySoftData.TabNameArr.Length {
        MySoftData.TabCtrl.UseTab(A_Index)
        func := GetUIAddFunc(A_Index)
        func(A_Index)
    }
    MySoftData.TabCtrl.UseTab()
    MySoftData.TabCtrl.Move(MySoftData.TabPosX, MySoftData.TabPosY, 920, 570)
    MySoftData.TabCtrl.OnEvent("Change", OnTabValueChanged)
    AddSliderUI()
}

AddSliderUI() {
    MyGui := MySoftData.MyGui
    areaCon := MyGui.Add("Pic", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 541, "d1d1d1"), "")
    barCon := MyGui.Add("Text", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 250, "9f9f9f"), "")
    tableItem := MySoftData.TableInfo[MySoftData.TableIndex]
    MySlider.SetSliderCon(areaCon, barCon)
    MySlider.SetStyleParams(2, 2)
    MySlider.SwitchTab(tableItem)
}

AddOperBtnUI() {
    MyGui := MySoftData.MyGui
    posY := 10
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 95), GetLang("当前配置"))

    ; 当前配置
    posY += 25
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", 15, posY, 100, 40), MySoftData.CurSettingName)
    posY += 30
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("配置管理"))
    con.OnEvent("Click", (*) => MySettingMgrGui.ShowGui())

    posY += 50
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 465), GetLang("全局操作"))

    posY += 25
    ; 休眠
    MySoftData.SuspendToggleCtrl := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("休眠"))
    MySoftData.SuspendToggleCtrl.Value := MySoftData.IsSuspend
    MySoftData.SuspendToggleCtrl.OnEvent("Click", OnSuspendHotkey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MySoftData.SuspendHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.SuspendHotkey)
    con.Enabled := false
    posY += 40

    ; 暂停
    MySoftData.PauseToggleCtrl := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("暂停"))
    MySoftData.PauseToggleCtrl.Value := MySoftData.IsPause
    MySoftData.PauseToggleCtrl.OnEvent("Click", OnPauseHotKey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MySoftData.PauseHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.PauseHotkey)
    con.Enabled := false
    posY += 40

    ;终止模块
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("终止所有宏"))
    con.OnEvent("Click", OnKillAllMacro)
    posY += 31
    CtrlType := GetHotKeyCtrlType(MySoftData.KillMacroHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MySoftData.KillMacroHotkey)
    con.Enabled := false
    posY += 40

    ReloadBtnCtrl := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("重载"))
    ReloadBtnCtrl.OnEvent("Click", MenuReload)
    posY += 40

    posY := 540
    MySoftData.BtnSave := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("应用并保存"))
    MySoftData.BtnSave.OnEvent("Click", OnSaveSetting)

    MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MySoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MySoftData.BtnSave
}

GetUIAddFunc(index) {
    UIAddFuncArr := [LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold,
        AddToolUI, AddSettingUI, AddHelpUI, AddRewardUI, AddThankUI]
    return UIAddFuncArr[index]
}

;工具
AddToolUI(index) {
    global ToolCheckInfo

    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX
    ; 配置规则说明
    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("变量监视器："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 120, posY - 3, 130), GetLang("打开监视器"))
    con.OnEvent("Click", (*) => MyVarListenGui.ShowGui())
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("鼠标信息："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolCheckHotkey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolCheckHotkey)
    con.Enabled := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"))
    ToolCheckInfo.ToolCheckCtrl := con
    ToolCheckInfo.ToolCheckCtrl.Value := ToolCheckInfo.IsToolCheck
    ToolCheckInfo.ToolCheckCtrl.OnEvent("Click", OnToolCheckHotkey)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 400, posY, 60), GetLang("窗口置顶"))
    ToolCheckInfo.AlwaysOnTopCtrl := con
    ToolCheckInfo.AlwaysOnTopCtrl.Value := false
    ToolCheckInfo.AlwaysOnTopCtrl.OnEvent("Click", OnToolAlwaysOnTop)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("屏幕坐标："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.PosStr)
    ToolCheckInfo.ToolMousePosCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 400, posY), GetLang("窗口坐标："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.WinPosStr)
    ToolCheckInfo.ToolMouseWinPosCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口标题："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessTile)
    ToolCheckInfo.ToolProcessTileCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程名："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessName)
    ToolCheckInfo.ToolProcessNameCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口类："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessClass)
    ToolCheckInfo.ToolProcessClassCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程PID:"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessPid)
    ToolCheckInfo.ToolProcessPidCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("句柄Id:"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessId)
    ToolCheckInfo.ToolProcessIdCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 400, posY), GetLang("位置颜色："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.Color)
    ToolCheckInfo.ToolColorCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("截图和自由贴："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ScreenShotHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ScreenShotHotKey
    )
    con.Enabled := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 260, posY - 5, 100), GetLang("截图"))
    con.OnEvent("Click", OnToolScreenShot)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.FreePasteHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX + 400, posY - 3, 130), ToolCheckInfo.FreePasteHotKey
    )
    con.Enabled := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 540, posY - 5, 100), GetLang("自由贴"))
    con.OnEvent("Click", OnToolFreePaste)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("指令录制："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolRecordMacroHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolRecordMacroHotKey
    )
    con.Enabled := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"))
    ToolCheckInfo.ToolCheckRecordMacroCtrl := con
    ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := ToolCheckInfo.IsToolRecord
    ToolCheckInfo.ToolCheckRecordMacroCtrl.OnEvent("Click", OnHotToolRecordMacro.Bind(false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("图片文本提取："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolTextFilterHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolTextFilterHotKey
    )
    con.Enabled := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 260, posY - 5, 100), GetLang("截图提取文本"))
    con.OnEvent("Click", OnToolTextFilterScreenShot)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 400, posY - 5, 120), GetLang("从图片提取文本"))
    con.OnEvent("Click", OnToolTextFilterSelectImage)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("相关选项："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{} w{}", PosX + 120, PosY, 110), GetLang("文本识别模型："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX + 260, PosY - 5, 100), GetLangArr(["中文", "英文"]))
    ToolCheckInfo.OCRTypeCtrl := con
    ToolCheckInfo.OCRTypeCtrl.Value := ToolCheckInfo.OCRTypeValue
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 20, posY), GetLang("录制的指令或提取的文本内容："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{} h{}", posX + 260, posY - 5, 80, 25), GetLang("清空内容"))
    con.OnEvent("Click", OnClearToolText)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    con := ToolCheckInfo.ToolTextCtrl := MyGui.Add("Edit", Format("x{} y{} w{} h{}", posX + 20, posY, 800, 100), "")
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 20
    MySoftData.TableInfo[index].underPosY := posY
}

;设置
AddSettingUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 30
    posX := MySoftData.TabPosX
    con := MyGui.Add("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("快捷键修改"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)

    posY += 30
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件休眠："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(MySoftData.SuspendHotkey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MySoftData.SuspendHotkey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 100, posY), MySoftData.SuspendHotkey)
    MySoftData.SuspendHotkeyCtrl := con
    MySoftData.SuspendHotkeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w50", posX + 235, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.SuspendHotkeyCtrl, true))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("暂停宏："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(MySoftData.PauseHotkey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MySoftData.PauseHotkey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 385, posY), MySoftData.PauseHotkey)
    MySoftData.PauseHotkeyCtrl := con
    MySoftData.PauseHotkeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.PauseHotkeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 605, posY), GetLang("终止宏："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(MySoftData.KillMacroHotkey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), MySoftData.KillMacroHotkey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 680, posY), MySoftData.KillMacroHotkey)
    MySoftData.KillMacroHotkeyCtrl := con
    MySoftData.KillMacroHotkeyCtrl.Visible := false
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.KillMacroHotkeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("指令录制："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolRecordMacroHotKey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4),
    ToolCheckInfo.ToolRecordMacroHotKey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.ToolRecordMacroHotKey)
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl := con
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolRecordMacroHotKeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("文本提取："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolTextFilterHotKey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4),
    ToolCheckInfo.ToolTextFilterHotKey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolTextFilterHotKey)
    ToolCheckInfo.ToolTextFilterHotKeyCtrl := con
    ToolCheckInfo.ToolTextFilterHotKeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolTextFilterHotKeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 605, posY), GetLang("屏幕截图："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ScreenShotHotKey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4),
    ToolCheckInfo.ScreenShotHotKey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 680, posY), ToolCheckInfo.ScreenShotHotKey)
    ToolCheckInfo.ScreenShotHotKeyCtrl := con
    ToolCheckInfo.ScreenShotHotKeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ScreenShotHotKeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("自由贴："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.FreePasteHotKey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4),
    ToolCheckInfo.FreePasteHotKey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.FreePasteHotKey)
    ToolCheckInfo.FreePasteHotKeyCtrl := con
    ToolCheckInfo.FreePasteHotKeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.FreePasteHotKeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("鼠标信息："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolCheckHotkey)
    showCon := MyGui.Add(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4),
    ToolCheckInfo.ToolCheckHotkey)
    showCon.Enabled := false
    conInfo := ItemConInfo(showCon, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolCheckHotkey)
    ToolCheckInfo.ToolCheckHotKeyCtrl := con
    ToolCheckInfo.ToolCheckHotKeyCtrl.Visible := false
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"))
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolCheckHotKeyCtrl, false))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    posX := MySoftData.TabPosX
    con := MyGui.Add("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("数值选项"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)
    posY += 30
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("按住时间浮动(%)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.HoldFloat)
    MySoftData.HoldFloatCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("每次间隔浮动(%)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.PreIntervalFloat)
    MySoftData.PreIntervalFloatCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 635, posY), GetLang("间隔指令浮动(%)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.IntervalFloat)
    MySoftData.IntervalFloatCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("坐标X浮动(px)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.CoordXFloat)
    MySoftData.CoordXFloatCon := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("坐标Y浮动(px)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.CoordYFloat)
    MySoftData.CoordYFloatCon := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 635, posY), GetLang("多线程数(0~10)："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.MutiThreadNum)
    MySoftData.MutiThreadNumCtrl := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件背景颜色："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.SoftBGColor)
    MySoftData.SoftBGColorCon := con
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("GroupBox", Format("x{} y{} w870 h100", posX + 10, posY), GetLang("开关选项"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)
    posY += 30

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("开机自启"))
    MySoftData.BootStartCtrl := con
    MySoftData.BootStartCtrl.Value := MySoftData.IsBootStart
    MySoftData.BootStartCtrl.OnEvent("Click", OnBootStartChanged)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{} -Wrap w15", posX + 315, posY), "")
    MySoftData.CMDTipCtrl := con
    MySoftData.CMDTipCtrl.Value := MySoftData.CMDTip
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Button", Format("x{} y{}", posX + 315 + 15, posY - 5), GetLang("指令显示"))
    con.OnEvent("Click", (*) => OnEditCMDTipGui())
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Button", Format("x{} y{} w{}", posX + 635, posY - 5, 100), GetLang("录制选项"))
    con.OnEvent("Click", OnClickToolRecordSettingBtn)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("无变量提醒"))
    MySoftData.NoVariableTipCtrl := con
    MySoftData.NoVariableTipCtrl.Value := MySoftData.NoVariableTip
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 315, posY), GetLang("菜单轮位置固定"))
    MySoftData.FixedMenuWheelCtrl := con
    MySoftData.FixedMenuWheelCtrl.Value := MySoftData.FixedMenuWheel
    MySoftData.FixedMenuWheelCtrl.OnEvent("Click", OnMenuWheelPosChanged)
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("分割线"))
    MySoftData.SplitLineCtrl := con
    MySoftData.SplitLineCtrl.Value := MySoftData.ShowSplitLine
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    con := MyGui.Add("GroupBox", Format("x{} y{} w870 h100", posX + 10, posY), GetLang("下拉框选项"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)

    ;语言/Lang： 如果外国人打开中文的话，或者中国人打开英语，方便都能找到调整的选项
    posY += 30
    con := MyGui.Add("Text", Format("x{} y{}", posX + 25, posY), "语言/Lang：")
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("DropDownList", Format("x{} y{} w100", posX + 100, posY - 5), [])
    MySoftData.LangCtrl := con
    MySoftData.LangCtrl.Delete()
    MySoftData.LangCtrl.Add(MySoftData.LangArr)
    MySoftData.LangCtrl.Text := MySoftData.Lang
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 315, posY), GetLang("软件字体："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("DropDownList", Format("x{} y{} w180", posX + 390, posY - 5), [])
    MySoftData.FontTypeCtrl := con
    MySoftData.FontTypeCtrl.Delete()
    MySoftData.FontTypeCtrl.Add(MySoftData.FontList)
    MySoftData.FontTypeCtrl.Text := MySoftData.FontType
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", posX + 635, posY), GetLang("截图方式："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("DropDownList", Format("x{} y{} w100", posX + 710, posY - 5), GetLangArr(["微软截图",
        "RMT截图"]))
    MySoftData.ScreenShotTypeCtrl := con
    MySoftData.ScreenShotTypeCtrl.Value := MySoftData.ScreenShotType
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 70
    tableItem := MySoftData.TableInfo[index]
    tableItem.UnderPosY := posY
}

;帮助
AddHelpUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 40
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 25),
    GetLang("免责声明"))
    con.SetFont((Format("S{} W{} Q{}", 14, 600, 2)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 35),
    GetLang("本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力"))
    con.SetFont((Format("S{} W{} Q{}", 10, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 40
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25),
    GetLang('1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25),
    GetLang("2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25),
    GetLang("3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 50),
    GetLang("4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 50
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", posX, posY, 800, 35),
    GetLang("若不同意上述条款，请立即停止使用本软件。"))
    con.SetFont((Format("cRed  S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 50
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 35),
    GetLang("更新视频合集："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 35),
    Format('<a href="https://www.bilibili.com/video/BV1oWVRzaEzk">{}</a>', GetLang("版本更新视频，直播交流问答")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 35),
    GetLang("操作说明文档："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 35),
    Format('<a href="https://zclucas.github.io/RMT/">{}</a>', GetLang("帮助你快速上手，理解词条、指令，10分钟秒变大神")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("国内开源网址："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://gitee.com/fateman/RMT">https://gitee.com/fateman/RMT</a>')
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("国外开源网址："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://github.com/zclucas/RMT">https://github.com/zclucas/RMT</a>')
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("软件检查更新："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("软件交流渠道："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30),
    '<a href="https://qm.qq.com/q/DgpDumEPzq">[1群]837661891</a>、<a href="https://qm.qq.com/q/uZszuxabPW">[2群]1050141694</a>、<a href="https://pd.qq.com/s/5wyjvj7zw">QQ频道</a>、<a href="https://discord.gg/m8ewvgtzat">Discord</a>'
    )
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("软件反馈表格："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    str1 := Format('<a href="https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj">{}</a>', GetLang("bug文档"))
    str2 := Format('<a href="https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo">{}</a>', GetLang("需求文档"))
    str3 := Format('<a href="https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2">{}</a>', GetLang("使用备注"))
    con := MyGui.Add("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30),
    Format("{}、{}、{}", str1, str2, str3))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 30
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30),
    GetLang("软件开源协议："))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), "AGPL-3.0")
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    MySoftData.TableInfo[index].underPosY := posY
}

;打赏
AddRewardUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY
    posX := MySoftData.TabPosX

    posY += 40
    posX += 15
    countStr := FormatIntegerWithCommas(MySoftData.MacroTotalCount)
    str1 := GetLang("若梦兔（RMT）—— 这款完全免费的开源软件，始终陪在你身边。")
    str2 := Format(GetLang("至今已为您执行 {:} 次宏指令。"), countStr)
    str3 := GetLang("诚邀本月打赏成为若梦兔的 “守护者”，一起让若梦兔走得更远。")
    str := Format("{}`n{}`n{}", str1, str2, str3)
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 80), str)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 100
    posX := MySoftData.TabPosX + 100
    con := MyGui.Add("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\WeiXin.png")
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("微信打赏"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 450
    con := MyGui.Add("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\ZhiFuBao.png")
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("支付宝打赏"))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 300
    posX := MySoftData.TabPosX + 15
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 860, 80), Format("{}`n{}", GetLang(
        "当然，如果你暂时不方便，分享给朋友也是很棒的支持~"), GetLang("开发不易，感谢你的每一份温暖！")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 35
    MySoftData.TableInfo[index].underPosY := posY
}

; 系统托盘优化
CustomTrayMenu() {
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    TraySetIcon(, , true)
}

