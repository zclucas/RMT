#Requires AutoHotkey v2.0
#SingleInstance Force
#Include JoyMacro.ahk
#Include RecordJoyUtil.ahk
#Include RecordUtil.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_Host.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_Generator.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_GUI.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_Components.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_Adv_Components.ahk
#Include ..\Plugins\AHK-XAML\lib\XAML_Dialog.ahk
#Include ..\Plugins\AHK-XAML\lib\AXML.ahk
#Include RMTUtil.ahk
#Include WorkPool.ahk
#Include UIUtil.ahk
#Include TimingUtil.ahk
#Include WindowHotkeyManager.ahk
#Include BindUtil.ahk
#Include VariableUtil.ahk
#Include TriggerKeyData.ahk
#Include FolderPackager.ahk
#Include Util\MacroClipboardUtil.ahk
#Include Util\ErrorHandler.ahk
#Include ..\Plugins\ViGEm\AHK-ViGEm-Bus-v2.ahk

#Include ..\Gui\TriggerKeyGui.ahk
#Include ..\Gui\TriggerStrGui.ahk
#Include ..\Gui\TimingGui.ahk
#Include ..\Gui\MacroSettingGui.ahk
#Include ..\Gui\VerticalSlider.ahk
#Include ..\Gui\SettingMgrGui.ahk
#Include ..\Gui\EditHotkeyGui.ahk
#Include ..\Gui\FreePasteGui.ahk
#Include ..\Gui\MacroEditGui.ahk
#Include ..\Gui\MenuWheelGlobalSettingGui.ahk
#Include ..\Gui\MacroGraph\MacroGraphGui.ahk
#Include ..\Gui\MenuWheelGui.ahk
#Include ..\Gui\MenuMacroSettingGui.ahk
#Include ..\Gui\UIMacroGui.ahk
#Include ..\Gui\UIMacroSettingGui.ahk
#Include ..\Gui\UIMacroPanelSettingGui.ahk
#Include ..\Gui\ReplaceKeyGui.ahk
#Include ..\Gui\UseExplainGui.ahk
#Include ..\Gui\TargetGui.ahk
#Include ..\Gui\ColorPanelGui.ahk
#Include ..\Gui\ToolRecordSettingGui.ahk
#Include ..\Gui\VarListenGui.ahk
#Include ..\Gui\CMDTipGui.ahk
#Include ..\Gui\FrontInfoGui.ahk
#Include ..\Gui\CMDTipSettingGui.ahk
#Include ..\Gui\CustomMsgBoxGui.ahk
#Include ..\Gui\ErrorMsgBoxGui.ahk
#Include ..\Gui\CustomInputGui.ahk
#Include ..\Gui\InputBtnGui.ahk
#Include ..\Gui\ConfigMergeGui.ahk
#Include ..\Gui\ThankUIUtil.ahk
#Include ..\Gui\TabItemUIUtil.ahk


SetWorkingDir A_ScriptDir
DetectHiddenWindows true
Persistent
A_MaxHotkeysPerInterval := 400


OnError(ErrHandler)             ;注册全局错误处理器
UnblockZoneIdentifier()         ;异步移除文件的Zone.Identifier标记 防止文件被锁定
global MySoftData := SoftData()
global MainSoftData := MainConfig()
global IniFile := A_WorkingDir "\Setting\MainSettings.ini"
global LangDir := A_WorkingDir "\Lang"
LoadMainSetting()               ;加载通用设置

global MyJoyMacro := JoyMacro()
global MyMouseInfo := MouseWinData()
global MyTriggerKeyGui := TriggerKeyGui()
global MyTriggerStrGui := TriggerStrGui()
global MyEditHotkeyGui := EditHotkeyGui()
global MyMacroSettingGui := MacroSettingGui()
global MyVarListenGui := VarListenGui()
global MyMacroGui := MacroEditGui()
global MyMacroGraphGui := MacroGraphGui()
global MyMenuWheel := MenuWheelGui()
global MyMenuMacroSettingGui := MenuMacroSettingGui()
global MyUIMacroGui := UIMacroGui()
global MyUIMacroSettingGui := UIMacroSettingGui()
global MyReplaceKeyGui := ReplaceKeyGui()
global MyFreePasteGui := FreePasteGui()
global MySettingMgrGui := SettingMgrGui()
global MyFrontInfoGui := FrontInfoGui()
global MyCMDTipGui := CMDTipGui()
global MyTimingGui := TimingGui()
global MySlider := VerticalSlider()
global MyTargetGui := TargetGui()
global MyColorPanel := ColorPanelGui()
global MyMsgboxGui := CustomMsgBoxGui()
global MyErrorMsgBoxGui := ErrorMsgBoxGui()
global MyInputGui := CustomInputGui()
global MyInputBtnGui := InputBtnGui()
global MyCMDTipSettingGui := CMDTipSettingGui()
global MyToolRecordSettingGui := ToolRecordSettingGui()
global MyUseExplainGui := UseExplainGui()
global MyConfigMergeGui := ConfigMergeGui()
global MyStopMacro := StopMacro
global SelectAreaHo := HighlightOutlineSelectArea("Red", 150)
global SelectAreaState := {breakFlag: false, winPos: "", firstPos: false, sx: 0, sy: 0}
global MyTriggerSubMacro := TriggerMacroHandler
global MySubmitGraphBranches := SubmitGraphBranchesHandler
global MySetGlobalVariable := SetGlobalVariable
global MyDelGlobalVariable := DelGlobalVariable
global MyCMDReportAciton := CMDReport
global MyExcuteRMTCMDAction := ExcuteRMTCMDAction
global MySetTableItemState := SetTableItemState
global MySetItemPauseState := SetItemPauseState
global MyMsgBoxContent := MsgBoxContent
global MyToolTipContent := ToolTipContent
global MyMacroCount := MacroCount
global MyViGJoySetState := ViGJoySetState
;宏运行状态颜色（0默认 1运行中 2暂停 3停止）
global MacroStateColors := Map(1, "#FF4CAF50", 2, "#FFFFC107", 3, "#FFF44336")
;数组相关
global MySetGlobalArray := SetGlobalArray
global MyCloneGlobalArray := CloneGlobalArray
global MyDeleteGlobalArray := DeleteGlobalArray
global MyModifyGlobalArray := ModifyGlobalArray
global MyInsertGlobalArray := InsertGlobalArray
global MyRemoveAtGlobalArray := RemoveAtGlobalArray