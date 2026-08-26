#Requires AutoHotkey v2.0

; ========== OpenCV DLL 加载与诊断 ==========
; RMT_OpenCV.dll 依赖 opencv_world481.dll，后者又依赖 Microsoft Visual C++ 2015-2022 运行库
; （MSVCP140.dll / VCRUNTIME140.dll / VCRUNTIME140_1.dll / CONCRT140.dll）。
; 若目标机器未安装该运行库，LoadLibrary 会失败，抓图、搜图等 OpenCV 功能将全部不可用。

OpenCvDllDir() {
    isWorker := IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker
    archDir := (A_PtrSize = 4) ? "x86" : "x64"
    if (isWorker)
        return A_ScriptDir "\..\Plugins\OpenCV\" archDir
    return A_ScriptDir "\Plugins\OpenCV\" archDir
}

IsOpenCvLoaded() {
    return DllCall("GetModuleHandle", "Str", "RMT_OpenCV.dll", "Ptr") != 0
}

; 检测 VC++ 2015-2022 运行库 DLL 是否缺失，返回缺失的 DLL 名（逗号分隔），无缺失返回 ""
GetMissingVcRuntime() {
    names := ["VCRUNTIME140.dll", "VCRUNTIME140_1.dll", "MSVCP140.dll", "CONCRT140.dll"]
    missing := []
    for n in names {
        if (DllCall("GetModuleHandle", "Str", n, "Ptr"))
            continue
        h := DllCall("LoadLibrary", "Str", n, "Ptr")
        if (h)
            DllCall("FreeLibrary", "Ptr", h)
        else
            missing.Push(n)
    }
    if (missing.Length == 0)
        return ""
    str := ""
    for i, n in missing
        str .= (i > 1 ? ", " : "") . n
    return str
}

; 确保 OpenCV DLL 可用。返回 "" 表示可用；否则返回失败原因（会话内只诊断/加载一次，避免刷日志）。
OpenCvEnsure() {
    static cached := false
    static cachedReason := ""

    if (IsOpenCvLoaded())
        return ""

    if (cached)
        return cachedReason

    reason := ""
    dllDir := OpenCvDllDir()
    rmtDll := dllDir "\RMT_OpenCV.dll"
    worldDll := dllDir "\opencv_world481.dll"

    if (!FileExist(rmtDll) || !FileExist(worldDll)) {
        reason := Format("OpenCV 插件文件缺失：`n{}`n{}", rmtDll, worldDll)
    } else {
        ; 将 OpenCV 目录加入 DLL 搜索路径，保证 opencv_world481.dll 能被找到
        DllCall("SetDllDirectory", "Str", dllDir)

        ; 先加载依赖库，失败时能精确区分“缺运行库”与“缺依赖”
        hWorld := DllCall("LoadLibrary", "Str", worldDll, "Ptr")
        if (!hWorld) {
            worldErr := A_LastError
            vc := GetMissingVcRuntime()
            if (vc != "")
                reason := Format("缺少 Microsoft Visual C++ 运行库（{}），请安装 vc_redist.{}.exe 后重启软件", vc, (A_PtrSize = 4 ? "x86" : "x64"))
            else
                reason := Format("opencv_world481.dll 加载失败（错误码 {}）", worldErr)
        } else {
            hRmt := DllCall("LoadLibrary", "Str", rmtDll, "Ptr")
            if (!hRmt)
                reason := Format("RMT_OpenCV.dll 加载失败（错误码 {}）", A_LastError)
        }
    }

    cached := true
    cachedReason := reason
    if (reason != "")
        SearchDebugLog(Format("OpenCV 不可用：{}", reason), "opencv")
    return reason
}

; 在主进程弹出一次“OpenCV 不可用”提示（Worker 无界面，不能弹窗，仅写日志）
ShowOpenCvInstallPrompt(reason) {
    static warned := false
    if (warned)
        return
    warned := true

    isWorker := IsSet(MySoftData) && ObjHasOwnProp(MySoftData, "isWorker") && MySoftData.isWorker
    if (isWorker)
        return

    try {
        MsgBox(Format("OpenCV 插件不可用，抓图/搜图等功能将无法使用：`n`n{}", reason), "RMT 提示", 48)
    }
}

; 窗口颜色识别 x，y 窗口坐标
FindWinColor(ResXPtr, ResYPtr, colorStr, hwnd, X1, Y1, X2, Y2, matchThreshold) {
    if (A_PtrSize != 8) ;非64位不可用
        return false
    if (OpenCvEnsure() != "")
        return false

    colorStr := Format("{:06X}", ("0x" colorStr) + 0)
    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    return DllCall("RMT_OpenCV.dll\FindWinColor", "AStr", colorStr, "Int", hwnd, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}

ReleaseAllCaches() {
    ; OpenCV DLL 未加载时直接 DllCall 会抛 "Failed to load DLL"（例如本宏只用颜色/文本/本地识图搜索，从未用到 OpenCV）
    if (!DllCall("GetModuleHandle", "Str", "RMT_OpenCV.dll", "Ptr"))
        return
    DllCall("RMT_OpenCV.dll\ReleaseAllCaches", "Cdecl")
}

FindScreenText(&ResX, &ResY, X1, Y1, X2, Y2, text, mode) {
    result := GetScreenTextObjArr(X1, Y1, X2, Y2, mode)
    if (result == "" || !result)
        return false
    for index, value in result {
        isContain := CheckContainText(value.text, text)
        if (isContain) {
            pos := GetMatchCoord(value, X1, Y1)
            ResX := pos[1]
            ResY := pos[2]
            break
        }
    }
    return isContain
}

;RapidOcr文本识别 result里面都是窗口坐标
GetScreenTextObjArr(X1, Y1, X2, Y2, mode) {
    global MyChineseOcr, MyEnglishOcr
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)

    ; 获取位图的宽度和高度
    Width := Gdip_GetImageWidth(pBitmap)
    Height := Gdip_GetImageHeight(pBitmap)

    ; 锁定位图以获取位图数据
    Gdip_LockBits(pBitmap, 0, 0, Width, Height, &Stride, &Scan0, &BitmapData)

    if (A_PtrSize == 8) {
        ; 64位系统结构
        BITMAP_DATA := Buffer(24)  ; 64位下结构总大小为24字节
        NumPut("ptr", Scan0, BITMAP_DATA, 0)   ; bits (8字节)
        NumPut("uint", Stride, BITMAP_DATA, 8)  ; pitch (4字节)
        NumPut("int", Width, BITMAP_DATA, 12)   ; width (4字节)
        NumPut("int", Height, BITMAP_DATA, 16)  ; height (4字节)
        NumPut("int", 4, BITMAP_DATA, 20)      ; bytespixel (4字节)
    } else {
        ; 32位系统结构
        BITMAP_DATA := Buffer(20)  ; 32位下结构总大小为20字节
        NumPut("ptr", Scan0, BITMAP_DATA, 0)   ; bits (4字节)
        NumPut("uint", Stride, BITMAP_DATA, 4)  ; pitch (4字节)
        NumPut("int", Width, BITMAP_DATA, 8)    ; width (4字节)
        NumPut("int", Height, BITMAP_DATA, 12)  ; height (4字节)
        NumPut("int", 4, BITMAP_DATA, 16)       ; bytespixel (4字节)
    }

    ; 调用 ocr_from_bitmapdata 方法（mode 参数保留兼容，v6 统一多语言模型不再区分）
    ocr := GetChineseOcr()
    result := ocr.ocr_from_bitmapdata(BITMAP_DATA, , true)

    ; 解锁位图
    Gdip_UnlockBits(pBitmap, &BitmapData)
    ; 释放位图
    Gdip_DisposeImage(pBitmap)
    return result
}

FindWinText(&ResX, &ResY, hwnd, X1, Y1, X2, Y2, text, mode) {
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return false

    result := GetWinTextObjArr(hwnd, X1, Y1, X2, Y2, mode)
    if (result == "" || !result)
        return false
    for index, value in result {
        isContain := CheckContainText(value.text, text)
        if (isContain) {
            pos := GetMatchCoord(value, X1, Y1)
            ResX := pos[1] + X1
            ResY := pos[2] + Y1
            break
        }
    }
    return isContain
}

; 窗口文本识别
; C++ 后台截图 -> OpenCv 转 Mat -> RapidOcr 识别 Mat
GetWinTextObjArr(hwnd, X1, Y1, X2, Y2, mode) {
    if (OpenCvEnsure() != "")
        return ""

    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    matPtr := DllCall("RMT_OpenCV.dll\CaptureWinMat", "Int", hwnd, "Int", searchX, "Int", searchY,
        "Int", searchW, "Int", searchH, "Cdecl Ptr")
    ; v6 统一多语言模型，不再区分语言
    ocr := GetChineseOcr()

    res := ocr.ocr_from_mat(matPtr, , true)
    DllCall("RMT_OpenCV.dll\ReleaseMat", "ptr", matPtr, "cdecl")    ;释放mat，防止内存泄露

    return res
}

; OpenCV屏幕图片识别
FindScreenImage(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold) {
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return false
    if (OpenCvEnsure() != "")
        return false

    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    return DllCall("RMT_OpenCV.dll\FindScreenImage", "AStr", targetPath, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}

; OpenCV窗口图片识别    返回窗口的坐标
FindWinImage(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold) {
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return false
    if (OpenCvEnsure() != "")
        return false

    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    return DllCall("RMT_OpenCV.dll\FindWinImage", "AStr", targetPath, "Int", hwnd, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}
