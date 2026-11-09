#Requires AutoHotkey v2.0

; =====================================================================
; RMT.dll 自编译：Plugins\RMT\*.cs → RMT.dll（csc，对齐 AHK-XAML BridgeUtil）
; =====================================================================

global RMT_Ai := ""          ; RMT.AiAssist CLR 实例
global RMT_ASM := ""         ; 已加载程序集（可选复用）

; 若源码比 DLL 新（或 DLL 缺失），用 csc 重编。打包 exe 不现场编译。
EnsureRmtDll(force := false) {
    rmtDir := AppRootDir "\Plugins\RMT"
    dllPath := rmtDir "\RMT.dll"
    if (A_IsCompiled) {
        if (!FileExist(dllPath))
            throw Error("缺少 Plugins\RMT\RMT.dll")
        return dllPath
    }
    need := force || !FileExist(dllPath)
    if (!need) {
        dllTime := FileGetTime(dllPath, "M")
        loop files rmtDir "\*.cs" {
            if (FileGetTime(A_LoopFilePath, "M") > dllTime) {
                need := true
                break
            }
        }
    }
    if (!need)
        return dllPath
    if (!BuildRmtDll(rmtDir, dllPath))
        throw Error("RMT.dll 编译失败，详见 %TEMP%\RMT-dll-build.log")
    return dllPath
}

BuildRmtDll(rmtDir := "", dllPath := "") {
    if (rmtDir == "")
        rmtDir := AppRootDir "\Plugins\RMT"
    if (dllPath == "")
        dllPath := rmtDir "\RMT.dll"
    csc := FindRmtCsc()
    if (csc == "")
        return false
    fwLib := A_WinDir "\Microsoft.NET\Framework64\v4.0.30319"
    if (!DirExist(fwLib))
        fwLib := A_WinDir "\Microsoft.NET\Framework\v4.0.30319"

    srcArgs := ""
    srcCount := 0
    loop files rmtDir "\*.cs" {
        srcArgs .= ' "' A_LoopFilePath '"'
        srcCount++
    }
    if (srcCount < 1)
        return false

    try FileDelete(dllPath)
    catch {
        ; 仍被占用则失败
        if (FileExist(dllPath))
            return false
    }

    refs := ""
    for name in ["System.dll", "System.Core.dll", "System.Net.Http.dll", "System.Management.dll", "System.Runtime.Serialization.dll"] {
        p := fwLib "\" name
        if (FileExist(p))
            refs .= ' /reference:"' p '"'
    }

    errLog := A_Temp "\RMT-dll-build.log"
    try FileDelete(errLog)
    cmd := Format('"{}" /nologo /target:library /optimize+ /out:"{}" /lib:"{}"{}{}'
        , csc, dllPath, fwLib, refs, srcArgs)
    RunWait(A_ComSpec ' /c "' cmd ' > "' errLog '" 2>&1"', , "Hide")
    return FileExist(dllPath)
}

FindRmtCsc() {
    roots := []
    try roots.Push(EnvGet("ProgramFiles"))
    try roots.Push(EnvGet("ProgramFiles(x86)"))
    years := ["2022", "2019", "2017"]
    editions := ["Enterprise", "Professional", "Community", "BuildTools"]
    for root in roots {
        if (root == "")
            continue
        for y in years {
            for e in editions {
                p := root "\Microsoft Visual Studio\" y "\" e "\MSBuild\Current\Bin\Roslyn\csc.exe"
                if (FileExist(p))
                    return p
            }
        }
    }
    p64 := A_WinDir "\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (FileExist(p64))
        return p64
    p32 := A_WinDir "\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    if (FileExist(p32))
        return p32
    return ""
}
