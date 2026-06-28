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

;窗口&UI刷新
InitUI() {
    global MySoftData
    MyGui := Gui()
    MyGui.Title := "RMTv" RMT_VERSION
    MyGui.SetFont("S10 W550 Q2", MainSoftData.FontType)
    isValidCollor := RegExMatch(MainSoftData.SoftBGColor, "^([0-9A-Fa-f]{6})$")
    BGColor := isValidCollor ? MainSoftData.SoftBGColor : "f0f0f0"
    if (BGColor != "f0f0f0")
        MyGui.BackColor := BGColor

    MainSoftData.MyGui := MyGui
    MyGui.OnEvent("Close", OnGuiClose)
    AddUI()
    CustomTrayMenu()
    OnOpen()

}

OnOpen() {
    global MySoftData
    if (!MainSoftData.AgreeAgreement) {
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

    if (MainSoftData.IsMinStart) {
        MainSoftData.IsMinStart := false
        MainSoftData.MyGui.Hide()
        return
    }

    RefreshGui()
}

; 主窗口关闭时清理所有鼠标热键订阅
OnGuiClose(*) {
    WinHotkey.UnsubscribeAllMouse()
    ; 重置各组件的订阅状态，以便窗口重新显示时能重新订阅
    MySlider._wheelCb := ""
    MyCMDTipGui._wheelCb := ""
    MyFreePasteGui._wheelCb := ""
    MyTargetGui._lbuttonCb := ""
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
            MainSoftData.MyGui.Show(Format("x{} y{} w{} h{}", WinPosArr[1], WinPosArr[2], 1070, 590))
            RefreshListenVarGui()
            ; 恢复滑块滚轮热键订阅（窗口重新打开后需要重新订阅）
            if (MySlider.tableItem != "" && MySlider.ShowSlider)
                MySlider.SwitchTab(MySlider.tableItem)
            return
        }
    }

    if (MainSoftData.LastShowMonth != A_Mon) {
        MainSoftData.TabCtrl.Value := 9
        MainSoftData.LastShowMonth := A_Mon
        IniWrite(MainSoftData.LastShowMonth, IniFile, IniSection, "LastShowMonth")
    }

    MainSoftData.MyGui.Show(Format("w{} h{}", 1070, 590))
    RefreshListenVarGui()
    ; 恢复滑块滚轮热键订阅（窗口重新打开后需要重新订阅）
    if (MySlider.tableItem != "" && MySlider.ShowSlider)
        MySlider.SwitchTab(MySlider.tableItem)
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
    global MainSoftData

    MainSoftData.ToolMousePosCtrl.Value := MainSoftData.PosStr
    MainSoftData.ToolProcessNameCtrl.Value := MainSoftData.ProcessName
    MainSoftData.ToolProcessTileCtrl.Value := MainSoftData.ProcessTile
    MainSoftData.ToolProcessPidCtrl.Value := MainSoftData.ProcessPid
    MainSoftData.ToolProcessClassCtrl.Value := MainSoftData.ProcessClass
    MainSoftData.ToolProcessIdCtrl.Value := MainSoftData.ProcessId
    MainSoftData.ToolColorCtrl.Value := MainSoftData.Color
    MainSoftData.ToolMouseWinPosCtrl.Value := MainSoftData.WinPosStr
}

; 添加控件到表格中，自动记录位置信息
AddTableControl(Type, Options, Text, tableItem, FoldIndex := 1) {
    global MySoftData
    con := MainSoftData.MyGui.Add(Type, Options, Text)
    conInfo := ItemConInfo(con, tableItem, FoldIndex)
    tableItem.AllConArr.Push(conInfo)
    return con
}

;UI元素相关函数
AddUI() {
    global MySoftData
    MyGui := MainSoftData.MyGui
    AddOperBtnUI()
    MainSoftData.TabPosY := 10
    MainSoftData.TabPosX := 130
    MainSoftData.TabCtrl := MyGui.Add("Tab3", Format("x{} y{} w{} Choose{}", MainSoftData.TabPosX, MainSoftData.TabPosY, 910,
        MainSoftData.TableIndex), GetLangArr(MainSoftData.TabNameArr))

    loop MainSoftData.TabNameArr.Length {
        MainSoftData.TabCtrl.UseTab(A_Index)
        func := GetUIAddFunc(A_Index)
        func(A_Index)
    }
    MainSoftData.TabCtrl.UseTab()
    MainSoftData.TabCtrl.Move(MainSoftData.TabPosX, MainSoftData.TabPosY, 920, 570)
    MainSoftData.TabCtrl.OnEvent("Change", OnTabValueChanged)
    AddSliderUI()
}

AddSliderUI() {
    MyGui := MainSoftData.MyGui
    areaCon := MyGui.Add("Pic", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 541, "d1d1d1"), "")
    barCon := MyGui.Add("Text", Format("x{} y{} w{} h{} +Background0x{}", 1045, 37, 15, 250, "9f9f9f"), "")
    tableItem := MySoftData.TableInfo[MainSoftData.TableIndex]
    MySlider.SetSliderCon(areaCon, barCon)
    MySlider.SetStyleParams(2, 2)
    MySlider.SwitchTab(tableItem)
}

AddOperBtnUI() {
    MyGui := MainSoftData.MyGui
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
    UIControls.SuspendToggle := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("休眠"))
    UIControls.SuspendToggle.Value := MainSoftData.IsSuspend
    UIControls.SuspendToggle.OnEvent("Click", OnSuspendHotkey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MainSoftData.SuspendHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MainSoftData.SuspendHotkey)
    con.Enabled := false
    posY += 40

    ; 暂停
    UIControls.PauseToggle := MyGui.Add("CheckBox", Format("x{} y{} w{} h{}", 15, posY, 100, 20), GetLang("暂停"))
    UIControls.PauseToggle.Value := MainSoftData.IsPause
    UIControls.PauseToggle.OnEvent("Click", OnPauseHotKey)
    posY += 20
    CtrlType := GetHotKeyCtrlType(MainSoftData.PauseHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MainSoftData.PauseHotkey)
    con.Enabled := false
    posY += 40

    ;终止模块
    con := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("终止所有宏"))
    con.OnEvent("Click", OnKillAllMacro)
    posY += 31
    CtrlType := GetHotKeyCtrlType(MainSoftData.KillMacroHotkey)
    con := MyGui.Add(CtrlType, Format("x{} y{} w{}", 15, posY, 100), MainSoftData.KillMacroHotkey)
    con.Enabled := false
    posY += 40

    ReloadBtnCtrl := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("重载"))
    ReloadBtnCtrl.OnEvent("Click", MenuReload)
    posY += 40

    posY := 505
    btnHelp := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("RMT文档"))
    btnHelp.OnEvent("Click", (*) => Run(A_WorkingDir "\index.html"))

    posY := 540
    MainSoftData.BtnSave := MyGui.Add("Button", Format("x{} y{} w{} h{} center", 15, posY, 100, 30), GetLang("应用并保存"))
    MainSoftData.BtnSave.OnEvent("Click", OnSaveSetting)

    MyTriggerKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyTriggerStrGui.SureFocusCon := MainSoftData.BtnSave
    MyReplaceKeyGui.SureFocusCon := MainSoftData.BtnSave
    MyUIMacroSettingGui.SureFocusCon := MainSoftData.BtnSave
}

GetUIAddFunc(index) {
    UIAddFuncArr := [LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold, LoadItemFold,
        AddToolUI, AddSettingUI, AddHelpUI, AddRewardUI, AddThankUI]
    return UIAddFuncArr[index]
}

;工具
AddToolUI(index) {
    global MainSoftData

    MyGui := MainSoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MainSoftData.TabPosY
    posX := MainSoftData.TabPosX
    ; 配置规则说明
    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("变量监视器："), tableItem)
    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 120, posY - 3, 130), GetLang("打开监视器"), tableItem)
    con.OnEvent("Click", (*) => MyVarListenGui.ShowGui())

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("鼠标信息："), tableItem)

    isHotKey := CheckIsNormalHotKey(MainSoftData.ToolCheckHotkey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), MainSoftData.ToolCheckHotkey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    UIControls.ToolCheck := con
    UIControls.ToolCheck.Value := MainSoftData.IsToolCheck
    UIControls.ToolCheck.OnEvent("Click", OnToolCheckHotkey)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 400, posY, 60), GetLang("窗口置顶"), tableItem)
    UIControls.AlwaysOnTop := con
    UIControls.AlwaysOnTop.Value := false
    UIControls.AlwaysOnTop.OnEvent("Click", OnToolAlwaysOnTop)

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("屏幕坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), MainSoftData.PosStr, tableItem)
    MainSoftData.ToolMousePosCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("窗口坐标："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), MainSoftData.WinPosStr, tableItem)
    MainSoftData.ToolMouseWinPosCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口标题："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), MainSoftData.ProcessTile, tableItem)
    MainSoftData.ToolProcessTileCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程名："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), MainSoftData.ProcessName, tableItem)
    MainSoftData.ToolProcessNameCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("进程窗口类："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), MainSoftData.ProcessClass, tableItem)
    MainSoftData.ToolProcessClassCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("进程PID:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), MainSoftData.ProcessPid, tableItem)
    MainSoftData.ToolProcessPidCtrl := con

    posY += 35
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("句柄Id:"), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 120, posY - 5), MainSoftData.ProcessId, tableItem)
    MainSoftData.ToolProcessIdCtrl := con

    AddTableControl("Text", Format("x{} y{}", posX + 400, posY), GetLang("位置颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w240", posX + 480, posY - 5), MainSoftData.Color, tableItem)
    MainSoftData.ToolColorCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("指令录制："), tableItem)

    isHotKey := CheckIsNormalHotKey(MainSoftData.ToolRecordMacroHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), MainSoftData.ToolRecordMacroHotKey,
    tableItem).Enabled := false

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 260, posY, 60), GetLang("开关"), tableItem)
    UIControls.ToolCheckRecord := con
    UIControls.ToolCheckRecord.Value := MainSoftData.IsToolRecord
    UIControls.ToolCheckRecord.OnEvent("Click", OnHotToolRecordMacro.Bind(false))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("图片文本提取："), tableItem)

    isHotKey := CheckIsNormalHotKey(MainSoftData.ToolTextFilterHotKey)
    CtrlType := isHotKey ? "Hotkey" : "Text"
    AddTableControl(CtrlType, Format("x{} y{} w{}", posX + 120, posY - 3, 130), MainSoftData.ToolTextFilterHotKey,
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
    UIControls.OCRType := con
    UIControls.OCRType.Value := MainSoftData.OCRTypeValue

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 20, posY), GetLang("录制的指令或提取的文本内容："), tableItem)

    con := AddTableControl("Button", Format("x{} y{} w{} h{}", posX + 260, posY - 5, 80, 25), GetLang("清空内容"),
    tableItem)
    con.OnEvent("Click", OnClearToolText)

    posY += 25
    con := UIControls.ToolText := AddTableControl("Edit", Format("x{} y{} w{} h{}", posX + 20, posY, 800, 140),
    "", tableItem)

    posY += 100
    MySoftData.TableInfo[index].UnderPosY := posY
}

; 编辑快捷键后同步隐藏Text控件的值到 MainSoftData
OnEditHotkeyAndSync(showCon, keyCon, OnlyTriggerKey, fieldName, *) {
    OnOpenEditHotkeyGui(showCon, keyCon, OnlyTriggerKey)
    MainSoftData.%fieldName% := keyCon.Value
}

;设置
AddSettingUI(index) {
    MyGui := MainSoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MainSoftData.TabPosY
    posX := MainSoftData.TabPosX

    posY += 30
    posX := MainSoftData.TabPosX
    con := AddTableControl("GroupBox", Format("x{} y{} w890 h140", posX + 10, posY), GetLang("快捷键修改"), tableItem)
    tableItem.AllGroup.Push(con)

    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件休眠："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.SuspendHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MainSoftData.SuspendHotkey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), MainSoftData.SuspendHotkey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, true, "SuspendHotkey"))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("暂停宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.PauseHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MainSoftData.PauseHotkey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), MainSoftData.PauseHotkey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "PauseHotkey"))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("终止宏："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.KillMacroHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), MainSoftData.KillMacroHotkey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), MainSoftData.KillMacroHotkey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "KillMacroHotkey"))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("指令录制："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.ToolRecordMacroHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MainSoftData.ToolRecordMacroHotKey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), MainSoftData.ToolRecordMacroHotKey,
    tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "ToolRecordMacroHotKey"))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("文本提取："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.ToolTextFilterHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MainSoftData.ToolTextFilterHotKey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), MainSoftData.ToolTextFilterHotKey,
    tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "ToolTextFilterHotKey"))

    AddTableControl("Text", Format("x{} y{}", posX + 605, posY), GetLang("屏幕截图："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.ScreenShotHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 680, posY - 4), MainSoftData.ScreenShotHotKey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 680, posY), MainSoftData.ScreenShotHotKey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 815, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "ScreenShotHotKey"))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("自由贴："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.FreePasteHotKey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 100, posY - 4), MainSoftData.FreePasteHotKey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 100, posY), MainSoftData.FreePasteHotKey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 235, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "FreePasteHotKey"))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("鼠标信息："), tableItem)
    CtrlType := GetHotKeyCtrlType(MainSoftData.ToolCheckHotkey)
    showCon := AddTableControl(CtrlType, Format("x{} y{} w130", posX + 385, posY - 4), MainSoftData.ToolCheckHotkey,
    tableItem)
    showCon.Enabled := false
    keyCon := AddTableControl("Text", Format("x{} y{} w130", posX + 385, posY), MainSoftData.ToolCheckHotkey, tableItem)
    keyCon.Visible := false
    con := AddTableControl("Button", Format("x{} y{} center w50", posX + 520, posY - 5), GetLang("编辑"), tableItem)
    con.OnEvent("Click", OnEditHotkeyAndSync.Bind(showCon, keyCon, false, "ToolCheckHotkey"))

    posY += 40
    posX := MainSoftData.TabPosX
    con := AddTableControl("GroupBox", Format("x{} y{} w890 h140", posX + 10, posY), GetLang("数值选项"), tableItem)
    tableItem.AllGroup.Push(con)
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("点击时间浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MainSoftData.HoldFloat, tableItem
    )
    con.OnEvent("Change", (*) => MainSoftData.HoldFloat := Integer(con.Value))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("每次间隔浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MainSoftData.PreIntervalFloat,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.PreIntervalFloat := Integer(con.Value))

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("间隔指令浮动(%)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MainSoftData.IntervalFloat,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.IntervalFloat := Integer(con.Value))

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("坐标X浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MainSoftData.CoordXFloat,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.CoordXFloat := Integer(con.Value))

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("坐标Y浮动(px)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 440, posY - 4), MainSoftData.CoordYFloat,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.CoordYFloat := Integer(con.Value))

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("多线程数(-1~10)："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MainSoftData.MutiThreadNum,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.MutiThreadNum := Integer(con.Value))
    Con := AddTableControl("Button", Format("x{} y{} h27", posX + 865, posY - 4), "?", tableItem)
    Con.OnEvent("Click", OnClickMutiThreadHelpBtn)

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("核心池大小(1~10)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MainSoftData.DynamicCorePoolSize, tableItem)
    ; MainSoftData.DynamicCorePoolSizeCtrl := con

    ; posY += 40
    ; AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("弹性超时(秒)："), tableItem)
    ; con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 760, posY - 4), MainSoftData.ElasticTimeout, tableItem)
    ; MainSoftData.ElasticTimeoutCtrl := con

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("软件背景颜色："), tableItem)
    con := AddTableControl("Edit", Format("x{} y{} w100 center", posX + 145, posY - 4), MainSoftData.SoftBGColor,
    tableItem)
    con.OnEvent("Change", (*) => MainSoftData.SoftBGColor := con.Value)

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w890 h180", posX + 10, posY), GetLang("开关选项"), tableItem)
    tableItem.AllGroup.Push(con)

    posY += 30
    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("开机自启"), tableItem)
    con.Value := MainSoftData.IsBootStart
    con.OnEvent("Click", OnBootStartChanged)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 315, posY), GetLang("管理员启动"), tableItem)
    con.Value := MainSoftData.IsAdminStart
    con.OnEvent("Click", OnAdminStartChanged)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("仅前台运行宏"), tableItem)
    con.Value := MainSoftData.CheckForeground
    con.OnEvent("Click", (*) => MainSoftData.CheckForeground := con.Value)

    posY += 40
    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 25, posY), GetLang("无变量提醒"), tableItem)
    con.Value := MainSoftData.NoVariableTip
    con.OnEvent("Click", (*) => MainSoftData.NoVariableTip := con.Value)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 315, posY), GetLang("模态子窗口"), tableItem)
    con.Value := MainSoftData.IsModalSubGui
    con.OnEvent("Click", (*) => MainSoftData.IsModalSubGui := con.Value)

    con := AddTableControl("CheckBox", Format("x{} y{}", posX + 635, posY), GetLang("分割线"), tableItem)
    con.Value := MainSoftData.ShowSplitLine
    con.OnEvent("Click", (*) => MainSoftData.ShowSplitLine := con.Value)

    posY += 40
    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 25, posY - 5, 100), GetLang("录制选项"), tableItem)
    con.OnEvent("Click", OnClickToolRecordSettingBtn)

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 315, posY - 5, 100), GetLang("轮盘选项"), tableItem)
    con.OnEvent("Click", (*) => MenuWheelGlobalSettingGui.ShowGui())

    con := AddTableControl("Button", Format("x{} y{} w{}", posX + 635, posY - 5, 100), GetLang("界面浮窗"), tableItem)
    con.OnEvent("Click", (*) => UIMacroPanelSettingGui.ShowGui())

    posY += 40
    con := AddTableControl("CheckBox", Format("x{} y{} -Wrap w15", posX + 25, posY), "", tableItem)
    UIControls.CMDTip := con
    con.Value := MySoftData.CMDTip
    con.OnEvent("Click", (*) => MySoftData.CMDTip := con.Value)
    con := AddTableControl("Button", Format("x{} y{}", posX + 25 + 15, posY - 5), GetLang("指令显示"), tableItem)
    con.OnEvent("Click", (*) => OnEditCMDTipGui())

    posY += 40
    con := AddTableControl("GroupBox", Format("x{} y{} w890 h100", posX + 10, posY), GetLang("下拉框选项"), tableItem)
    tableItem.AllGroup.Push(con)

    ;语言/Lang： 如果外国人打开中文的话，或者中国人打开英语，方便都能找到调整的选项
    posY += 30
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), "语言/Lang：", tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), [], tableItem)
    con.Delete()
    con.Add(MainSoftData.LangArr)
    con.Text := MainSoftData.Lang
    con.OnEvent("Change", (*) => MainSoftData.Lang := con.Text)

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("软件字体："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w180", posX + 390, posY - 4), [], tableItem)
    con.Delete()
    con.Add(MainSoftData.FontList)
    con.Text := MainSoftData.FontType
    con.OnEvent("Change", (*) => MainSoftData.FontType := con.Text)

    AddTableControl("Text", Format("x{} y{}", posX + 635, posY), GetLang("截图方式："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 710, posY - 4), GetLangArr(["微软截图",
        "RMT截图", "SC截图"]), tableItem)
    con.Value := MainSoftData.ScreenShotType
    con.OnEvent("Change", (*) => MainSoftData.ScreenShotType := con.Value)

    posY += 40
    AddTableControl("Text", Format("x{} y{}", posX + 25, posY), GetLang("按下时按下："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 110, posY - 4), GetLangArr(["自动松开", "忽略重复按下",
        "允许重复按下"]), tableItem)
    con.Value := MainSoftData.KeyDownDownType
    con.OnEvent("Change", (*) => MainSoftData.KeyDownDownType := con.Value)
    Con := AddTableControl("Button", Format("x{} y{} h27", posX + 231, posY - 4), "?", tableItem)
    Con.OnEvent("Click", OnClickKeyDownDownHelpBtn)

    AddTableControl("Text", Format("x{} y{}", posX + 315, posY), GetLang("手柄类型："), tableItem)
    con := AddTableControl("DropDownList", Format("x{} y{} w120", posX + 390, posY - 4), ["Xbox", "PS5"], tableItem)
    con.Text := MainSoftData.JoyType
    con.OnEvent("Change", (*) => MainSoftData.JoyType := con.Text)

    posY += 30
    tableItem.UnderPosY := posY
}

;帮助
AddHelpUI(index) {
    MyGui := MainSoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MainSoftData.TabPosY
    posX := MainSoftData.TabPosX

    posY += 40
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 25), GetLang("免责声明"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 14, 600, 2)))

    posY += 25
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 700, 35), GetLang(
        "本文件是对 GNU Affero General Public License v3.0 的补充说明，不影响原协议效力"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 10, 600, 0)))

    posY += 40
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        '1. 本软件按"原样"提供，开发者不承担因使用、修改或分发导致的任何法律责任。'), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "2. 严禁用于违法用途，包括但不限于：游戏作弊、未经授权的系统访问或数据篡改。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 25), GetLang(
        "3. 使用者需自行承担所有风险，开发者对因违反法律或第三方条款导致的后果概不负责。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 25
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 800, 50), GetLang(
        "4. 通过使用本软件，您确认：不会将其用于任何非法目的、已充分了解并接受所有潜在法律风险、同意免除开发者因滥用行为导致的一切追责权利。"), tableItem)
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MainSoftData.TabPosX + 15
    con := AddTableControl("Text", Format("x{} y{} w{} h{} Center", posX, posY, 800, 35), GetLang(
        "若不同意上述条款，请立即停止使用本软件。"), tableItem)
    con.SetFont((Format("cRed  S{} W{} Q{}", 12, 600, 0)))

    posY += 50
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("更新视频合集："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://www.bilibili.com/video/BV1oWVRzaEzk">{}</a>', GetLang("版本更新视频，直播交流问答")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    LinkStr := A_WorkingDir "\index.html"
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("操作说明文档："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format('<a href="{}">{}</a>', LinkStr,
        GetLang("快速上手，指令手册、常见问题、常见报错、更新日志等")), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("配置共享仓库："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), Format(
        '<a href="https://zclucas.github.io/RMT-Setting/">{}</a>', GetLang("案例学习、获取他人分享的宏配置（支持下载导入）")), tableItem).SetFont((
            Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国内开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://gitee.com/fateman/RMT">https://gitee.com/fateman/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("国外开源网址："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30),
    '<a href="https://github.com/zclucas/RMT">https://github.com/zclucas/RMT</a>', tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件检查更新："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), GetLang("浏览开源网址，查看右侧发行版处即可知道软件最新版本"),
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件交流渠道："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30),
    '<a href="https://qm.qq.com/q/DgpDumEPzq">QQ群（837661891）</a>、<a href="https://pd.qq.com/s/5wyjvj7zw">QQ频道</a>、<a href="https://github.com/zclucas/RMT/discussions">GitHub 论坛</a>、<a href="https://discord.gg/m8ewvgtzat">Discord</a>',
    tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件反馈表格："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    str1 := Format('<a href="https://docs.qq.com/sheet/DVWJIdEVMV1pHUVJj">{}</a>', GetLang("bug文档"))
    str2 := Format('<a href="https://docs.qq.com/sheet/DVWRQaXBFUVV5bERo">{}</a>', GetLang("需求文档"))
    str3 := Format('<a href="https://docs.qq.com/sheet/DVVNwWHJEd3NOWXhR?tab=BB08J2">{}</a>', GetLang("使用备注"))
    str4 := GetLang("（仅交流群成员有编辑权限）")
    AddTableControl("Link", Format("x{} y{} w{} h{}", posX + 130, posY, 700, 30), Format("{}、{}、{}{}", str1, str2, str3,
        str4), tableItem).SetFont((Format("S{} W{} Q{}", 12, 600, 0)))

    posY += 30
    posX := MainSoftData.TabPosX + 15
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 130, 30), GetLang("软件开源协议："), tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX + 130, posY, 500, 30), "AGPL-3.0", tableItem).SetFont((
        Format("S{} W{} Q{}", 12, 600, 0)))

    ; posY += 35
    tableItem.UnderPosY := posY
}

;打赏
AddRewardUI(index) {
    MyGui := MainSoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MainSoftData.TabPosY
    posX := MainSoftData.TabPosX

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
    posX := MainSoftData.TabPosX + 100
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
    posX := MainSoftData.TabPosX + 15
    str := Format("{}`n{}", GetLang("当然，如果你暂时不方便，分享给朋友也是很棒的支持~"), GetLang("开发不易，感谢你的每一份温暖！"))
    AddTableControl("Text", Format("x{} y{} w{} h{}", posX, posY, 860, 80), str, tableItem).SetFont((Format(
        "S{} W{} Q{}", 12, 600, 0)))

    posY += 35
    tableItem.UnderPosY := posY
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
    if (A_IsAdmin)
        tipStr .= "`n" GetLang("管理员权限")

    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("显示窗口"), (*) => RefreshGui())
    A_TrayMenu.Insert("&Suspend Hotkeys", GetLang("休眠"), (*) => OnSuspendHotkey())
    A_TrayMenu.Insert(GetLang("休眠"), GetLang("开始录制"), (*) => OnTrayStartRecord())
    A_TrayMenu.Insert(GetLang("休眠"), GetLang("结束录制"), (*) => OnTrayEndRecord())
    A_TrayMenu.Delete("&Pause Script")
    A_TrayMenu.Delete("&Suspend Hotkeys")
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Default := GetLang("显示窗口")
    A_IconTip := tipStr  ; 鼠标悬停时显示此内容
    A_IconHidden := 0   ;0(可见) 和 1(隐藏)
    TraySetIcon("Images\Soft\rabit.ico")
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
