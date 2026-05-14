;窗口&UI刷新
InitUI() {
    global MySoftData
    MyGui := Gui()
    MyGui.Title := "RMTv2.0"
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

    if (MySoftData.IsMinStart) {
        MySoftData.IsMinStart := false
        MySoftData.MyGui.Hide()
        return
    }

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

; 添加控件到表格中，自动记录位置信息
AddTableControl(Type, Options, Text, tableItem, FoldIndex := 1) {
    global MySoftData
    con := MySoftData.MyGui.Add(Type, Options, Text)
    conInfo := ItemConInfo(con, tableItem, FoldIndex)
    tableItem.AllConArr.Push(conInfo)
    return con
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
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 110), GetLang("当前配置"))

    ; 当前配置
    posY += 25
    con := MyGui.Add("Text", Format("x{} y{} w{} h{} Center", 15, posY, 100, 45), MySoftData.CurSettingName)
    posY += 45
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("配置管理"))
    con.OnEvent("Click", (*) => MySettingMgrGui.ShowGui())

    posY += 45
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{} center", 10, posY, 110, 455), GetLang("全局操作"))

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

    posY := 505
    btnHelp := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("RMT文档"))
    btnHelp.OnEvent("Click", (*) => Run(A_WorkingDir "\index.html"))

    posY := 540
    MySoftData.BtnSave := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("应用并保存"))
    MySoftData.BtnSave.OnEvent("Click", OnSaveSetting)

    MyTriggerKeyGui.SureFocusCon := MySoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MySoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MySoftData.BtnSave
    MyUIMacroSettingGui.SureFocusCon := MySoftData.BtnSave
}

GetUIAddFunc(index) {
    UIAddFuncArr := [LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold,
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
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("变量监视器："), tableItem)
    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 120, posY - 3, 130), GetLang("打开监视器"), tableItem)
    con.OnEvent("Click", (*) => MyVarListenGui.ShowGui())

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("鼠标信息："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolCheckHotkey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolCheckHotkey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    ToolCheckInfo.ToolCheckCtrl := con
    ToolCheckInfo.ToolCheckCtrl.Value := ToolCheckInfo.IsToolCheck
    ToolCheckInfo.ToolCheckCtrl.OnEvent("Click", OnToolCheckHotkey)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 400, posY, 60), GetLang("窗口置顶"), tableItem)
    ToolCheckInfo.AlwaysOnTopCtrl := con
    ToolCheckInfo.AlwaysOnTopCtrl.Value := false
    ToolCheckInfo.AlwaysOnTopCtrl.OnEvent("Click", OnToolAlwaysOnTop)

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("屏幕坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.PosStr, tableItem)
    ToolCheckInfo.ToolMousePosCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("窗口坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.WinPosStr, tableItem)
    ToolCheckInfo.ToolMouseWinPosCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口标题："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessTile, tableItem)
    ToolCheckInfo.ToolProcessTileCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程名："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessName, tableItem)
    ToolCheckInfo.ToolProcessNameCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口类："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessClass, tableItem)
    ToolCheckInfo.ToolProcessClassCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程PID:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.ProcessPid, tableItem)
    ToolCheckInfo.ToolProcessPidCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("句柄Id:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), ToolCheckInfo.ProcessId, tableItem)
    ToolCheckInfo.ToolProcessIdCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("位置颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), ToolCheckInfo.Color, tableItem)
    ToolCheckInfo.ToolColorCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("指令录制："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolRecordMacroHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    ToolCheckInfo.ToolCheckRecordMacroCtrl := con
    ToolCheckInfo.ToolCheckRecordMacroCtrl.Value := ToolCheckInfo.IsToolRecord
    ToolCheckInfo.ToolCheckRecordMacroCtrl.OnEvent("Click", OnHotToolRecordMacro.Bind(false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("图片文本提取："), tableItem)

    isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolTextFilterHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem).Enabled := false

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 260, posY - 5, 100), GetLang("截图提取文本"), tableItem)
    con.OnEvent("Click", OnToolTextFilterScreenShot)

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 400, posY - 5, 120), GetLang("从图片提取文本"), tableItem)
    con.OnEvent("Click", OnToolTextFilterSelectImage)

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("相关选项："), tableItem)

    AddTableControl("Text", Format("x{} y{} w{}", PosX + 120, PosY, 110), GetLang("文本识别模型："), tableItem)

    con := AddTableControl("DropDownList", Format("x{} y{} w{}", PosX + 260, PosY - 5, 100), GetLangArr(["中文", "英文"]),
    tableItem)
    ToolCheckInfo.OCRTypeCtrl := con
    ToolCheckInfo.OCRTypeCtrl.Value := ToolCheckInfo.OCRTypeValue

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("录制的指令或提取的文本内容："), tableItem)

    con := AddTableControl("Button", Format("x{} y{} w{} h{}", posX + 260, posY - 5, 80, 25), GetLang("清空内容"),
    tableItem)
    con.OnEvent("Click", OnClearToolText)

    posY += 25
    con := ToolCheckInfo.ToolTextCtrl := AddTableControl("Edit", Format("x{} y{} w{} h{}", posX + 20, posY, 800, 140),
    "", tableItem)

    posY += 100
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
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("快捷键修改"), tableItem)
    tableItem.AllGroup.Push(con)

    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件休眠："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.SuspendHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MySoftData.SuspendHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), MySoftData.SuspendHotkey, tableItem)
    MySoftData.SuspendHotkeyCtrl := con
    MySoftData.SuspendHotkeyCtrl.Visible := false

    con := AddTableControl("Button", Format("x{} y{} w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.SuspendHotkeyCtrl, true))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("暂停宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.PauseHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MySoftData.PauseHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), MySoftData.PauseHotkey, tableItem)
    MySoftData.PauseHotkeyCtrl := con
    MySoftData.PauseHotkeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.PauseHotkeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("终止宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MySoftData.KillMacroHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), MySoftData.KillMacroHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), MySoftData.KillMacroHotkey, tableItem)
    MySoftData.KillMacroHotkeyCtrl := con
    MySoftData.KillMacroHotkeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, MySoftData.KillMacroHotkeyCtrl, false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("指令录制："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolRecordMacroHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.ToolRecordMacroHotKey,
    tableItem)
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl := con
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolRecordMacroHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("文本提取："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolTextFilterHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolTextFilterHotKey,
    tableItem)
    ToolCheckInfo.ToolTextFilterHotKeyCtrl := con
    ToolCheckInfo.ToolTextFilterHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolTextFilterHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("屏幕截图："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ScreenShotHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), ToolCheckInfo.ScreenShotHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), ToolCheckInfo.ScreenShotHotKey, tableItem)
    ToolCheckInfo.ScreenShotHotKeyCtrl := con
    ToolCheckInfo.ScreenShotHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ScreenShotHotKeyCtrl, false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("自由贴："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.FreePasteHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), ToolCheckInfo.FreePasteHotKey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), ToolCheckInfo.FreePasteHotKey, tableItem)
    ToolCheckInfo.FreePasteHotKeyCtrl := con
    ToolCheckInfo.FreePasteHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.FreePasteHotKeyCtrl, false))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("鼠标信息："), tableItem)
    CtrlType := GetHotKeyCtrlType(ToolCheckInfo.ToolCheckHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), ToolCheckInfo.ToolCheckHotkey,
    tableItem)
    showCon.Enabled := false
    con := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), ToolCheckInfo.ToolCheckHotkey, tableItem)
    ToolCheckInfo.ToolCheckHotKeyCtrl := con
    ToolCheckInfo.ToolCheckHotKeyCtrl.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnOpenEditHotkeyGui.Bind(showCon, ToolCheckInfo.ToolCheckHotKeyCtrl, false))

    posY += 40
    posX := MySoftData.TabPosX
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("数值选项"), tableItem)
    tableItem.AllGroup.Push(con)
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("点击时间浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.HoldFloat, tableItem
    )
    MySoftData.HoldFloatCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("每次间隔浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.PreIntervalFloat,
    tableItem)
    MySoftData.PreIntervalFloatCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("间隔指令浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.IntervalFloat,
    tableItem)
    MySoftData.IntervalFloatCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("坐标X浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.CoordXFloat,
    tableItem)
    MySoftData.CoordXFloatCon := con

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("坐标Y浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MySoftData.CoordYFloat,
    tableItem)
    MySoftData.CoordYFloatCon := con

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("多线程数(-1~10)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.MutiThreadNum, tableItem)
    MySoftData.MutiThreadNumCtrl := con

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("核心池大小(1~10)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.DynamicCorePoolSize, tableItem)
    ; MySoftData.DynamicCorePoolSizeCtrl := con

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("弹性超时(秒)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MySoftData.ElasticTimeout, tableItem)
    ; MySoftData.ElasticTimeoutCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件背景颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MySoftData.SoftBGColor,
    tableItem)
    MySoftData.SoftBGColorCon := con

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h140", posX + 10, posY), GetLang("开关选项"), tableItem)
    tableItem.AllGroup.Push(con)
    posY += 30

    con := AddTableControl("CheckBox", Format("x{} y{} -Wrap w15", posX + 25, posY), "", tableItem)
    MySoftData.CMDTipCtrl := con
    MySoftData.CMDTipCtrl.Value := MySoftData.CMDTip
    con := AddTableControl("Button", Format("x{} y{}", posX + 25 + 15, posY - 5), GetLang("指令显示"), tableItem)
    con.OnEvent("Click", (*) => OnEditCMDTipGui())

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 315, posY - 5, 100), GetLang("录制选项"), tableItem)
    con.OnEvent("Click", OnClickToolRecordSettingBtn)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("无变量提醒"), tableItem)
    MySoftData.NoVariableTipCtrl := con
    MySoftData.NoVariableTipCtrl.Value := MySoftData.NoVariableTip

    posY += 40

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("菜单轮位置固定"), tableItem)
    MySoftData.FixedMenuWheelCtrl := con
    MySoftData.FixedMenuWheelCtrl.Value := MySoftData.FixedMenuWheel
    MySoftData.FixedMenuWheelCtrl.OnEvent("Click", OnMenuWheelPosChanged)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 315, posY), GetLang("分割线"), tableItem)
    MySoftData.SplitLineCtrl := con
    MySoftData.SplitLineCtrl.Value := MySoftData.ShowSplitLine

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("模态子窗口"), tableItem)
    MySoftData.ModalSubGuiCtrl := con
    MySoftData.ModalSubGuiCtrl.Value := MySoftData.IsModalSubGui

    posY += 40
    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("管理员启动"), tableItem)
    MySoftData.AdminStartCtrl := con
    MySoftData.AdminStartCtrl.Value := MySoftData.IsAdminStart
    MySoftData.AdminStartCtrl.OnEvent("Click", OnAdminStartChanged)

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w870 h100", posX + 10, posY), GetLang("下拉框选项"), tableItem)
    tableItem.AllGroup.Push(con)

    ;语言/Lang： 如果外国人打开中文的话，或者中国人打开英语，方便都能找到调整的选项
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), "语言/Lang：", tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), [], tableItem)
    MySoftData.LangCtrl := con
    MySoftData.LangCtrl.Delete()
    MySoftData.LangCtrl.Add(MySoftData.LangArr)
    MySoftData.LangCtrl.Text := MySoftData.Lang

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("软件字体："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w180", posX + 390, posY - 4), [], tableItem)
    MySoftData.FontTypeCtrl := con
    MySoftData.FontTypeCtrl.Delete()
    MySoftData.FontTypeCtrl.Add(MySoftData.FontList)
    MySoftData.FontTypeCtrl.Text := MySoftData.FontType

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("截图方式："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 710, posY - 4), GetLangArr(["微软截图",
        "RMT截图", "SC截图"]), tableItem)
    MySoftData.ScreenShotTypeCtrl := con
    MySoftData.ScreenShotTypeCtrl.Value := MySoftData.ScreenShotType

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("按下时按下："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), GetLangArr(["自动松开", "忽略重复按下",
        "允许重复按下"]), tableItem)
    MySoftData.KeyDownDownCon := con
    MySoftData.KeyDownDownCon.Value := MySoftData.KeyDownDownType
    Con := AddTableControl("Button", Format("x{} y{} h27", posX + 231, posY - 4), "?", tableItem)
    Con.OnEvent("Click", OnClickKeyDownDownHelpBtn)

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("开机自启："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 390, posY - 4), GetLangArr(["否", "是", "管理员"]), tableItem)
    MySoftData.BootStartCtrl := con
    MySoftData.BootStartCtrl.Value := MySoftData.IsBootStart + 1

    posY += 30
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
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 25), GetLang("免责声明"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 14, 600, 2)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 35), GetLang(
        "本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 10, 600, 0)))

    posY += 40
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        '1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 50), GetLang(
        "4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MySoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 800, 35), GetLang(
        "若不同意上述条款，请立即停止使用本软件。"), tableItem)
    con.SetFont((Format("cRed  S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("更新视频合集："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://www.bilibili.com/video/BV1oWVRzaEzk">{}</a>', GetLang("版本更新视频，直播交流问答")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    LinkStr := A_WorkingDir "\index.html"
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("操作说明文档："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format('<a href="{}">{}</a>', LinkStr,
        GetLang("快速上手，指令手册、常见问题、常见报错、更新日志等")), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("配置共享仓库："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://zclucas.github.io/RMT-Setting/">{}</a>', GetLang("案例学习、获取他人分享的宏配置（支持下载导入）")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国内开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://gitee.com/fateman/RMT">https://gitee.com/fateman/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国外开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://github.com/zclucas/RMT">https://github.com/zclucas/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件检查更新："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本"),
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件交流渠道："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30),
    '<a href="https://qm.qq.com/q/DgpDumEPzq">QQ群（837661891）</a>、<a href="https://pd.qq.com/s/5wyjvj7zw">QQ频道</a>、<a href="https://github.com/zclucas/RMT/discussions">GitHub 论坛</a>、<a href="https://discord.gg/m8ewvgtzat">Discord</a>',
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件反馈表格："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    str1 := Format('<a href="https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj">{}</a>', GetLang("bug文档"))
    str2 := Format('<a href="https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo">{}</a>', GetLang("需求文档"))
    str3 := Format('<a href="https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2">{}</a>', GetLang("使用备注"))
    str4 := GetLang("（仅交流群成员有编辑权限）")
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30), Format("{}、{}、{}{}", str1, str2, str3,
        str4), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MySoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件开源协议："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), "AGPL-3.0", tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    ; posY += 35
    tableItem.underPosY := posY
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
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 80), str, tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 100
    posX := MySoftData.TabPosX + 100
    AddTableControl("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\WeiXin.png",
    tableItem)
    AddTableControl("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("微信打赏"), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    posX += 450
    AddTableControl("Picture", Format("x{} y{} w{} h{} center", posX, posY, 220, 220), "Images\Soft\ZhiFuBao.png",
    tableItem)
    AddTableControl("Text", Format("x{} y{} w{} h{} center", posX, posY + 230, 220, 50), GetLang("支付宝打赏"), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 300
    posX := MySoftData.TabPosX + 15
    str := Format("{}`n{}", GetLang("当然，如果你暂时不方便，分享给朋友也是很棒的支持~"), GetLang("开发不易，感谢你的每一份温暖！"))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 860, 80), str, tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 35
    tableItem.underPosY := posY
}

; 系统托盘优化
CustomTrayMenu() {
    loop 30 {
        if (WinExist("ahk_class Shell_TrayWnd")) {
            break
        }
        Sleep(1000)
    }
    tipStr := MySoftData.MyGui.Title
    if (A_IsAdmin)
        tipStr .= "`n" GetLang("管理员权限")
    
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    A_IconTip := tipStr  ; 鼠标悬停时显示此内容
    A_IconHidden := 0   ;0(可见) 和 1(隐藏)
    TraySetIcon("Images\Soft\rabit.ico")
}