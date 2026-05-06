#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Plugins\RapidOcr\RapidOcr.ahk
#Include Plugins\CLR.ahk
#Include Plugins\IbInputSimulator.ahk
#Include Plugins\ViGEm\AHK-ViGEm-Bus-v2.ahk
#Include Main\JoyMacro.ahk
#Include Main\RecordJoyUtil.ahk
#Include Main\LineOverlay.ahk
#Include Main\AssetUtil.ahk
#Include Main\RMTUtil.ahk
#Include Main\WorkPool.ahk
#Include Main\UIUtil.ahk
#Include Main\TimingUtil.ahk
#Include Main\BindUtil.ahk
#Include Main\VariableUtil.ahk
#Include Main\TriggerKeyData.ahk
#Include Main\FolderPackager.ahk
#Include Main\GlobalUtil.ahk

try {
    InitFilePath()
    LoadCurMacroSetting()
    HandleOpenArg()
    EditListen()
    InitData()
    InitUI()
    SetEditData()

    PluginInit()
    TimingCheck()
    BindKey()
}
catch as e {
    RmtShowStartupError(e)
    ExitApp()
}

RmtShowStartupError(e) {
    message := "RMT startup failed.`n`n"
    message .= "Message: " e.Message "`n"
    if (e.File)
        message .= "File: " e.File "`n"
    if (e.Line)
        message .= "Line: " e.Line "`n"
    if (e.Extra)
        message .= "Extra: " e.Extra "`n"
    MsgBox(message, "RMT Error", "Iconx")
}
