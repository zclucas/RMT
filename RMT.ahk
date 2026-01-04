#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Joy\SuperCvJoyInterface.ahk
#Include Joy\JoyMacro.ahk
#Include Plugins\RapidOcr\RapidOcr.ahk
#Include Plugins\CLR.ahk
#Include Plugins\IbInputSimulator.ahk
#Include Gui\TriggerKeyGui.ahk
#Include Gui\TriggerStrGui.ahk
#Include Gui\TimingGui.ahk
#Include Gui\MacroSettingGui.ahk
#Include Gui\VerticalSlider.ahk
#Include Gui\SettingMgrGui.ahk
#Include Gui\EditHotkeyGui.ahk
#Include Gui\FreePasteGui.ahk
#Include Gui\MacroEditGui.ahk
#Include Gui\MenuWheelGui.ahk
#Include Gui\ReplaceKeyGui.ahk
#Include Gui\UseExplainGui.ahk
#Include Gui\LoopGui.ahk
#Include Gui\TargetGui.ahk
#Include Gui\ToolRecordSettingGui.ahk
#Include Gui\VariableListenGui.ahk
#Include Gui\CMDTipGui.ahk
#Include Gui\FrontInfoGui.ahk
#Include Gui\CMDTipSettingGui.ahk
#Include Gui\CustomMsgBoxGui.ahk
#Include Main\Gdip_All.ahk
#Include Main\LineDrawer.ahk
#Include Main\LineOverlay.ahk
#Include Main\DataClass.ahk
#Include Main\AssetUtil.ahk
#Include Main\RecordJoyUtil.ahk
#Include Main\ThankUIUtil.ahk
#Include Main\HotkeyUtil.ahk
#Include Main\RMTUtil.ahk
#Include Main\WorkPool.ahk
#Include Main\TabItemUIUtil.ahk
#Include Main\UIUtil.ahk
#Include Main\JsonUtil.ahk
#Include Main\CompareUtil.ahk
#Include Main\TimingUtil.ahk
#Include Main\BindUtil.ahk
#Include Main\TextProcessUtil.ahk
#Include Main\VariableUtil.ahk
#Include Main\FixCompatUtil.ahk
#Include Main\LangUtil.ahk
#Include Main\TriggerKeyData.ahk
#Include Main\FolderPackager.ahk
SetWorkingDir A_ScriptDir
DetectHiddenWindows true
Persistent
A_MaxHotkeysPerInterval := 400

global MyvJoy := SuperCvJoyInterface().GetMyvJoy()
global MyJoyMacro := JoyMacro()
global MyMouseInfo := MouseWinData()
global MySoftData := SoftData()
global ToolCheckInfo := ToolCheck()
global IniFile := A_WorkingDir "\Setting\MainSettings.ini"
global LangDir := A_WorkingDir "\Lang"
LoadMainSetting()       ;加载配置
global IsMinStart := false

if (A_Args.Length > 0) {
    loop A_Args.Length {
        arg := A_Args[A_Index]
        if ((arg = "/load" || arg = "-load") && A_Index < A_Args.Length) {
            targetConfigName := A_Args[A_Index + 1]
            targetPath := A_WorkingDir "\Setting\" targetConfigName
            if (DirExist(targetPath)) {
                MySoftData.CurSettingName := targetConfigName
            } else {
                MsgBox("启动参数错误：`n找不到名为 [" targetConfigName "] 的配置。`n`n软件将加载默认配置启动。", "RMT 启动提示", 48)
            }
        }
        if (arg = "/min" || arg = "-min") {
            IsMinStart := true
        }
    }
}

global MyTriggerKeyGui := TriggerKeyGui()
global MyTriggerStrGui := TriggerStrGui()
global MyEditHotkeyGui := EditHotkeyGui()
global MyMacroSettingGui := MacroSettingGui()
global MyVarListenGui := VariableListenGui()
global MyMacroGui := MacroEditGui()
global MyMenuWheel := MenuWheelGui()
global MyReplaceKeyGui := ReplaceKeyGui()
global MyFreePasteGui := FreePasteGui()
global MySettingMgrGui := SettingMgrGui()
global MyFrontInfoGui := FrontInfoGui()
global MyCMDTipGui := CMDTipGui()
global MyTimingGui := TimingGui()
global MySlider := VerticalSlider()
global MyTargetGui := TargetGui()
global MyMsgboxGui := CustomMsgBoxGui()
global MyCMDTipSettingGui := CMDTipSettingGui()
global MyToolRecordSettingGui := ToolRecordSettingGui()
global MyUseExplainGui := UseExplainGui()
global MySubMacroStopAction := SubMacroStopAction
global MyTriggerSubMacro := TriggerMacroHandler
global MySetGlobalVariable := SetGlobalVariable
global MyDelGlobalVariable := DelGlobalVariable
global MyCMDReportAciton := CMDReport
global MyExcuteRMTCMDAction := ExcuteRMTCMDAction
global MySetTableItemState := SetTableItemState
global MySetItemPauseState := SetItemPauseState
global MyMsgBoxContent := MsgBoxContent
global MyToolTipContent := ToolTipContent
global MyMacroCount := MacroCount

InitFilePath()          ;初始化文件路径
LoadCurMacroSetting()   ;加载当前配置宏
EditListen()        ;右键编辑数据监听
InitData()          ;初始化软件数据
InitUI()            ;初始化UI
SetGlobalVar()      ;缓存全局变量

;放后面初始化，因为这初始化时间比较长
PluginInit()
TimingCheck()       ;轮询检测触发
BindKey()           ;绑定快捷键
