#Requires AutoHotkey v2.0

; =============================================================================
; VC++ 2015-2022 运行库：检测（主进程 / Worker 共用）
;
; 只回答一个问题：这台机器的「系统基础环境」装了没有。
; 判据是系统层面的证据——注册表 Installed 标志 + 系统目录文件存在性，
; 不是「进程里现在能不能找到这个模块」。
;
; 为什么不用 LoadLibrary/GetModuleHandle 探测：
;   插件目录曾自带一份同名运行库（Plugins\Voice\{arch}，现已移除），
;   语音预热会在启动 2 秒时把它加载进进程。此时 GetModuleHandle 会命中
;   插件自带的那一份，把「插件自带」误判成「系统已装」，检测结论就废了。
;   文件与注册表不会因为别人的加载而改变，所以只能看它们。
;
; 本文件只做检测：不 Load 任何 DLL、不弹窗、不下载、不安装、不依赖界面。
; 修复编排（下载官方 vc_redist 并静默安装）在主进程的 SelfCheck.ahk
; （VcRuntimeEnsureInstalled），因为只有主进程才有 RmtDialog/RmtProgress。
;
; 设计取舍：不做 app-local。官方 vc_redist 自己知道该装什么，
; 不需要我们维护一份"完整依赖清单"，也就不存在「清单漏一项、干净机器起不来」。
; 代价是安装要管理员授权；用户拒绝后，依赖它的功能（OpenCV/OCR）不可用。
; =============================================================================

; 该架构下必须具备的运行库文件。
;   · vcruntime140_1 只在 x64 存在（x64 的 C++ 异常处理运行时，x86 没有）
;   · msvcp140_1 / msvcp140_2 被 onnxruntime、RapidOcr 用到
;   · concrt140 被 opencv_world481.dll 用到，最容易漏
VcRuntimeRequiredFiles() {
    files := ["vcruntime140.dll", "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "concrt140.dll"]
    if (A_PtrSize == 8)
        files.Push("vcruntime140_1.dll")
    return files
}

VcRuntimeArchDir() {
    return (A_PtrSize == 8) ? "x64" : "x86"
}

; 系统目录。32 位进程在 64 位系统上访问 System32 会被自动重定向到 SysWOW64，
; 所以统一写 System32，拿到的就是本进程真正会用的那一份，不用手工区分位数。
VcRuntimeSystemDir() {
    return A_WinDir "\System32"
}

; 官方安装器写、卸载器清的标志。这是「系统基础环境装没装」的权威判据。
; 64 位系统上 32 位程序写的键在 WOW6432Node；两处都试，任一命中即算已装。
VcRuntimeIsRegistered() {
    arch := VcRuntimeArchDir()
    for key in ["HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\" arch
        , "HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\" arch] {
        try installed := RegRead(key, "Installed")
        catch
            continue
        if (installed = 1)
            return true
    }
    return false
}

; 该文件在系统目录里是否就位。就位返回 ""，否则返回文件名本身。
; 只判断存在性，不加载，避免被进程内其它来源的同名模块干扰。
VcRuntimeResolveOne(fileName) {
    if (FileExist(VcRuntimeSystemDir() "\" fileName))
        return ""
    return fileName
}

; 缺失的运行库文件名数组（空数组 = 文件齐）
VcRuntimeMissingList() {
    missing := []
    for fileName in VcRuntimeRequiredFiles() {
        if (VcRuntimeResolveOne(fileName) != "")
            missing.Push(fileName)
    }
    return missing
}

; 系统基础环境是否就绪：注册表认账 且 关键文件都在。
; 两者缺一都算没装好——注册表在而文件被删，装一遍就能修回来。
VcRuntimeIsReady() {
    return VcRuntimeIsRegistered() && VcRuntimeMissingList().Length == 0
}

; 缺失项逗号串，供日志与提示文案使用
VcRuntimeMissingText() {
    text := ""
    for index, fileName in VcRuntimeMissingList()
        text .= (index > 1 ? ", " : "") fileName
    return text
}

; 人话版状态，给日志中心/自检面板用
VcRuntimeStatusText() {
    arch := VcRuntimeArchDir()
    missing := VcRuntimeMissingList()
    if (!VcRuntimeIsRegistered())
        return "未安装 VC++ 运行库（" arch "）"
    if (missing.Length)
        return Format("VC++ 运行库已注册但文件缺失（{}）：{}", arch, VcRuntimeMissingText())
    return "VC++ 运行库已安装（" arch "）"
}
