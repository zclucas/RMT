#Requires AutoHotkey v2.0
#Include ..\..\Main\Util\JsonUtil.ahk

GetLang(text) {
    return text
}

GetLangArr(values) {
    translated := []
    for _, value in values {
        translated.Push(GetLang(value))
    }
    return translated
}

#Include ..\..\Main\UIUtil.ahk

GetTableSymbol(index) {
    global MySoftData
    return MySoftData.TabSymbolArr[index]
}

CheckIsItemTable(index) {
    return index >= 1 && index <= 6
}

CheckIsMacroTable(index) {
    return index == 1
}

CheckIsStringMacroTable(index) {
    return index == 2
}

CheckIsMenuMacroTable(index) {
    return index == 3
}

CheckIsTimingMacroTable(index) {
    return index == 4
}

Assert(condition, message) {
    if (!condition)
        throw Error(message)
}

WriteLine(message) {
    FileAppend(message "`n", "*", "UTF-8")
}

RunFixture(name, callback) {
    try {
        callback()
        WriteLine("ok " name)
    } catch as err {
        FileAppend("fail " name ": " err.Message "`n", "**", "UTF-8")
        ExitApp(1)
    }
}

CreateControl(value := "", text := unset) {
    return IsSet(text) ? RmtWebValueControl(value, text) : RmtWebValueControl(value)
}

CreateFoldInfo(spans := unset) {
    foldInfo := {}
    foldInfo.IndexSpanArr := IsSet(spans) ? spans : ["1-2"]
    foldInfo.RemarkArr := ["Default module"]
    foldInfo.FrontInfoArr := ["Window title / process rule"]
    foldInfo.ForbidStateArr := [false]
    foldInfo.FoldStateArr := [false]
    foldInfo.TKTypeArr := [1]
    foldInfo.TKArr := [""]
    foldInfo.HoldTimeArr := [500]
    return foldInfo
}

CreateTable(index) {
    table := {}
    table.Index := index
    table.FoldInfo := CreateFoldInfo()
    table.SerialArr := ["item-1", "item-2"]
    table.ColorStateArr := [0, 0]
    table.TKArr := ["F1", "F2"]
    table.TriggerTypeArr := [1, 1]
    table.MacroArr := ["Macro_1", "Macro_2"]
    table.ModeArr := [1, 1]
    table.ForbidArr := [false, true]
    table.RemarkArr := ["First macro", "Disabled macro"]
    table.LoopCountArr := ["1", "2"]
    table.HoldTimeArr := [500, 700]
    table.TimingSerialArr := ["timing-1", "timing-2"]
    table.StartTipSoundArr := [1, 1]
    table.EndTipSoundArr := [1, 1]
    table.PauseArr := [false, false]
    return table
}

SetupState() {
    global MySoftData, ToolCheckInfo
    MySoftData := {}
    ToolCheckInfo := {}

    MySoftData.CurSettingName := "legacy-fixture"
    MySoftData.TableIndex := 1
    MySoftData.IsSuspend := false
    MySoftData.IsPause := false
    MySoftData.IsMacroWorking := false
    MySoftData.MacroRunningCount := 0
    MySoftData.MacroTotalCount := 12
    MySoftData.TabCtrl := RmtWebTabControl(1)
    MySoftData.TabNameArr := ["Key macros", "String macros", "Menu macros", "Timed macros", "Multi macros", "Key replace", "Tools", "Settings", "Help", "Reward", "Thanks"]
    MySoftData.TabSymbolArr := ["Normal", "String", "Menu", "Timing", "Multi", "Replace", "Tool", "Setting", "Help", "Reward", "Thank"]
    MySoftData.TableInfo := []
    loop 6 {
        MySoftData.TableInfo.Push(CreateTable(A_Index))
    }

    MySoftData.HoldFloat := 0
    MySoftData.PreIntervalFloat := 0
    MySoftData.IntervalFloat := 0
    MySoftData.CoordXFloat := 0
    MySoftData.CoordYFloat := 0
    MySoftData.SuspendHotkey := "!p"
    MySoftData.PauseHotkey := "!i"
    MySoftData.KillMacroHotkey := "!k"
    MySoftData.IsBootStart := false
    MySoftData.ShowSplitLine := false
    MySoftData.FixedMenuWheel := false
    MySoftData.MutiThreadNum := "3"
    MySoftData.SoftBGColor := "f0f0f0"
    MySoftData.NoVariableTip := true
    MySoftData.CMDTip := false
    MySoftData.ScreenShotType := 3
    MySoftData.KeyDownDownType := 1
    MySoftData.Lang := "Chinese"
    MySoftData.FontType := "Microsoft YaHei"
    MySoftData.LangArr := ["Chinese", "English"]
    MySoftData.FontList := ["Microsoft YaHei", "Arial", "Consolas"]

    MySoftData.HoldFloatCtrl := CreateControl(MySoftData.HoldFloat)
    MySoftData.PreIntervalFloatCtrl := CreateControl(MySoftData.PreIntervalFloat)
    MySoftData.IntervalFloatCtrl := CreateControl(MySoftData.IntervalFloat)
    MySoftData.CoordXFloatCon := CreateControl(MySoftData.CoordXFloat)
    MySoftData.CoordYFloatCon := CreateControl(MySoftData.CoordYFloat)
    MySoftData.SuspendHotkeyCtrl := CreateControl(MySoftData.SuspendHotkey)
    MySoftData.PauseHotkeyCtrl := CreateControl(MySoftData.PauseHotkey)
    MySoftData.KillMacroHotkeyCtrl := CreateControl(MySoftData.KillMacroHotkey)
    MySoftData.BootStartCtrl := CreateControl(MySoftData.IsBootStart)
    MySoftData.SplitLineCtrl := CreateControl(MySoftData.ShowSplitLine)
    MySoftData.FixedMenuWheelCtrl := CreateControl(MySoftData.FixedMenuWheel)
    MySoftData.MutiThreadNumCtrl := CreateControl(MySoftData.MutiThreadNum)
    MySoftData.SoftBGColorCon := CreateControl(MySoftData.SoftBGColor)
    MySoftData.NoVariableTipCtrl := CreateControl(MySoftData.NoVariableTip)
    MySoftData.CMDTipCtrl := CreateControl(MySoftData.CMDTip)
    MySoftData.ScreenShotTypeCtrl := CreateControl(MySoftData.ScreenShotType)
    MySoftData.KeyDownDownCon := CreateControl(MySoftData.KeyDownDownType)
    MySoftData.LangCtrl := CreateControl(MySoftData.Lang, MySoftData.Lang)
    MySoftData.FontTypeCtrl := CreateControl(MySoftData.FontType, MySoftData.FontType)

    ToolCheckInfo.IsToolCheck := false
    ToolCheckInfo.IsToolRecord := false
    ToolCheckInfo.ToolCheckHotKey := "!o"
    ToolCheckInfo.ToolRecordMacroHotKey := "!r"
    ToolCheckInfo.ToolTextFilterHotKey := "!u"
    ToolCheckInfo.ScreenShotHotKey := "!F1"
    ToolCheckInfo.FreePasteHotKey := "!F2"
    ToolCheckInfo.OCRTypeValue := 1
    ToolCheckInfo.PosStr := ""
    ToolCheckInfo.WinPosStr := ""
    ToolCheckInfo.ProcessTile := ""
    ToolCheckInfo.ProcessName := ""
    ToolCheckInfo.ProcessClass := ""
    ToolCheckInfo.ProcessPid := ""
    ToolCheckInfo.ProcessId := ""
    ToolCheckInfo.Color := ""
    ToolCheckInfo.ToolCheckHotKeyCtrl := CreateControl(ToolCheckInfo.ToolCheckHotKey)
    ToolCheckInfo.ToolRecordMacroHotKeyCtrl := CreateControl(ToolCheckInfo.ToolRecordMacroHotKey)
    ToolCheckInfo.ToolTextFilterHotKeyCtrl := CreateControl(ToolCheckInfo.ToolTextFilterHotKey)
    ToolCheckInfo.ScreenShotHotKeyCtrl := CreateControl(ToolCheckInfo.ScreenShotHotKey)
    ToolCheckInfo.FreePasteHotKeyCtrl := CreateControl(ToolCheckInfo.FreePasteHotKey)
    ToolCheckInfo.ToolCheckRecordMacroCtrl := CreateControl(ToolCheckInfo.IsToolRecord)
    ToolCheckInfo.AlwaysOnTopCtrl := CreateControl(false)
    ToolCheckInfo.OCRTypeCtrl := CreateControl(ToolCheckInfo.OCRTypeValue)
    ToolCheckInfo.ToolMousePosCtrl := CreateControl(ToolCheckInfo.PosStr)
    ToolCheckInfo.ToolMouseWinPosCtrl := CreateControl(ToolCheckInfo.WinPosStr)
    ToolCheckInfo.ToolProcessTileCtrl := CreateControl(ToolCheckInfo.ProcessTile)
    ToolCheckInfo.ToolProcessNameCtrl := CreateControl(ToolCheckInfo.ProcessName)
    ToolCheckInfo.ToolProcessClassCtrl := CreateControl(ToolCheckInfo.ProcessClass)
    ToolCheckInfo.ToolProcessPidCtrl := CreateControl(ToolCheckInfo.ProcessPid)
    ToolCheckInfo.ToolProcessIdCtrl := CreateControl(ToolCheckInfo.ProcessId)
    ToolCheckInfo.ToolColorCtrl := CreateControl(ToolCheckInfo.Color)
    ToolCheckInfo.ToolTextCtrl := CreateControl("")
}

RunFixture("default state shape", (*) => (
    SetupState(),
    state := RmtBuildState(),
    Assert(state["version"] == RMT_WEBVIEW_VERSION, "version mismatch"),
    Assert(state["tabs"].Length == 11, "tab count mismatch"),
    Assert(state["tabs"][1]["kind"] == "macro", "first tab should be macro"),
    Assert(state["tabs"][7]["kind"] == "tool", "tool tab kind mismatch"),
    Assert(state["tabs"][8]["kind"] == "settings", "settings tab kind mismatch"),
    Assert(state["settings"]["screenShotType"] == 3, "screenshot type should preserve default"),
    Assert(state["tools"]["ocrType"] == 1, "tool OCR type should preserve default")
))

RunFixture("old item arrays receive defaults", (*) => (
    SetupState(),
    table := MySoftData.TableInfo[1],
    table.StartTipSoundArr := [],
    table.EndTipSoundArr := [],
    table.PauseArr := [],
    state := RmtBuildState(),
    item := state["tabs"][1]["table"]["folds"][1]["items"][1],
    Assert(item["startTipSound"] == 1, "missing StartTipSoundArr should default to 1"),
    Assert(item["endTipSound"] == 1, "missing EndTipSoundArr should default to 1"),
    Assert(!RmtBool(item["pause"]), "missing PauseArr should default to false")
))

RunFixture("multiple folds preserve disabled and collapsed state", (*) => (
    SetupState(),
    table := MySoftData.TableInfo[1],
    table.FoldInfo.IndexSpanArr := ["1-1", "2-2"]
    table.FoldInfo.RemarkArr := ["Enabled module", "Legacy disabled module"]
    table.FoldInfo.FrontInfoArr := ["Window A", "Window B"]
    table.FoldInfo.ForbidStateArr := [false, true]
    table.FoldInfo.FoldStateArr := [false, true]
    table.FoldInfo.TKTypeArr := [1, 1]
    table.FoldInfo.TKArr := ["", ""]
    table.FoldInfo.HoldTimeArr := [500, 500]
    state := RmtBuildState(),
    folds := state["tabs"][1]["table"]["folds"],
    Assert(folds.Length == 2, "fold count mismatch"),
    Assert(!RmtBool(folds[1]["forbid"]), "first fold should stay enabled"),
    Assert(RmtBool(folds[2]["forbid"]), "second fold should stay disabled"),
    Assert(RmtBool(folds[2]["collapsed"]), "second fold should stay collapsed"),
    Assert(folds[2]["items"].Length == 1, "second fold should expose its item")
))

WriteLine("RmtBuildState fixture compatibility checks passed.")
