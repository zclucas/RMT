#Requires AutoHotkey v2.0

; =============================================================================
; DirectX XInput 组件：检测（主进程 / Worker 共用）
;
; 只回答一个问题：本机能不能用 XInput 读 Xbox 手柄。
; 判据是系统目录里 xinput1_3.dll 是否存在，与 VcRuntimeUtil 同一套思路——
; 不 Load、不查注册表、不弹窗、不依赖界面，因此不会受进程内其它同名模块干扰。
;
; 为什么只认 xinput1_3：
;   · xinput9_1_0 是 Vista 时代的兼容层，Win7 精简系统里可能剩它而没有 1_3，
;     它能读摇杆和按键，但扳机 LT/RT 会合并成一根轴、Guide 键读不到。
;   · xinput1_3 由 DirectX End-User Runtime（Jun2010）提供，是我们静默安装的目标，
;     装完 1_3 和 9_1_0 都会有。
;   所以「1_3 在」= 完整可用；「只有 9_1_0」= 兼容模式，仍然提示补齐。
;
; 安装编排（下载官方 DirectX 运行库并静默安装）在主进程 SelfCheck.ahk
; （DirectXEnsureInstalled），只有主进程才有 RmtDialog / RmtProgress。
; =============================================================================

; 完整可用所需的文件
DirectXRequiredFiles() {
    return ["xinput1_3.dll"]
}

; 系统目录。32 位进程在 64 位系统上访问 System32 会被重定向到 SysWOW64，
; 拿到的正是本进程实际会加载的那一份，不用手工分位数。
DirectXSystemDir() {
    return A_WinDir "\System32"
}

; 缺失的文件名数组（空数组 = 齐）
DirectXMissingList() {
    missing := []
    for fileName in DirectXRequiredFiles() {
        if (!FileExist(DirectXSystemDir() "\" fileName))
            missing.Push(fileName)
    }
    return missing
}

DirectXIsReady() {
    return DirectXMissingList().Length == 0
}

DirectXMissingText() {
    text := ""
    for index, fileName in DirectXMissingList()
        text .= (index > 1 ? ", " : "") fileName
    return text
}

; 兼容层是否在（仅用于提示文案，不参与就绪判定）
DirectXCompatLayerExists() {
    return FileExist(DirectXSystemDir() "\xinput9_1_0.dll") != ""
}

; 人话版状态，给日志与自检面板用
DirectXStatusText() {
    if (DirectXIsReady())
        return "XInput 组件已就绪（xinput1_3.dll）"
    if (DirectXCompatLayerExists())
        return "XInput 仅兼容模式（缺 " DirectXMissingText() "，扳机键与 Guide 键不可用）"
    return "未安装 XInput 组件（缺 " DirectXMissingText() "）"
}
