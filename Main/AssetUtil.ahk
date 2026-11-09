#Requires AutoHotkey v2.0
#Include "DataClass.ahk"
#Include "VariableUtil.ahk"
#Include Util\TableLocator.ahk
#Include Util\ExcelUtil.ahk
#Include Util\RmtDllUtil.ahk
#Include Util\SerialUtil.ahk
#Include Util\JsonUtil.ahk
#Include Util\LangUtil.ahk
#Include Util\CmdEnumUtil.ahk
#Include Util\Gdip_All.ahk
#Include Util\CompatDataUtil.ahk
#Include Util\CompareUtil.ahk
#Include Util\PresssKeyUtil.ahk
#Include Util\TextOpsUtil.ahk
#Include Util\ArrayUtil.ahk
#Include Util\JoyNameUtil.ahk
#Include Util\ExpressUtil.ahk
#Include Util\InputUtil.ahk
#Include Util\SearchUtil.ahk
#Include Util\SearchImageAssetUtil.ahk
#Include Util\FileIOUtil.ahk
#Include Util\HttpRequestUtil.ahk
#Include Util\HumanMouse.ahk
#Include Util\MacroUtil.ahk
#Include Util\WaitUtil.ahk
#Include Util\TimeUtil.ahk
#Include Util\CountDownUtil.ahk
#Include Util\GraphMacroUtil.ahk
#Include Util\PluginUtil.ahk
#Include Util\ThemeUtil.ahk

#Include ..\Plugins\CLR.ahk
#Include "..\Plugins\RapidOcr\RapidOcr.ahk"
#Include "..\Plugins\TesseractOcr\TesseractOcr.ahk"

; 旧配置目录的整目录迁移（Compat_UpgradeDir）不在这里：它只在主进程需要，
; 由 InitFilePath 在加载配置之前统一处理；Worker 只读配置，不参与迁移。
#Include "..\Plugins\AhiDriver\AhiDriver.ahk"
#Include "..\Plugins\IbInputSimulator.ahk"
#Include "..\Plugins\VIIPER\VIIPER.ahk"
#Include "..\Plugins\MouseControl.ahk"
#Include Util\MouseMoveUtil.ahk
#Include Util\MouseMovePreview.ahk
#Include Util\TomlUtil.ahk
#Include Util\ConfigUtil.ahk

global WM_COPYDATA := 0x4a ;传递字符串，系统信息

global WM_LOAD_WORK := 0x500  ;资源加载完成事件
global WM_CLEAR_WORK := 0x502  ;资源释放事件
global WM_TR_MACRO := 0x503 ;触发宏事件
global WM_STOP_MACRO := 0x504 ;停止宏事件
global WM_MASTER_TO_WORKER := 0x509  ; 主进程→Worker：分发任务/广播通知
global WM_WORKER_TO_MASTER := 0x50A  ; Worker→主进程：任务完成/事件上报

; 主程序与 Worker 共用的配置、指令和运行时模块。
#Include Shared\RuntimeValues.ahk
#Include Shared\WindowBinding.ahk
#Include Shared\SearchAssets.ahk
#Include Shared\CommandData.ahk
#Include Shared\Hotkeys.ahk
#Include Shared\RuntimeStartup.ahk
#Include Shared\MainSettings.ahk
#Include Shared\ThemeSettings.ahk
#Include Shared\Diagnostics.ahk
#Include Shared\MacroTableStorage.ahk
#Include Shared\MacroTableRuntime.ahk
#Include Shared\CommandPaths.ahk
#Include Shared\VariableResolution.ahk
#Include Shared\MacroRuntimeHelpers.ahk
