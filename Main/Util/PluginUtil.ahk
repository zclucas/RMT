#Requires AutoHotkey v2.0

; ========== OpenCV DLL 加载与诊断 ==========
; RMT_OpenCV.dll 依赖 opencv_world481.dll，后者又依赖 Microsoft Visual C++ 2015-2022 运行库
; （MSVCP140.dll / MSVCP140_1.dll / MSVCP140_2.dll / VCRUNTIME140.dll /
;  VCRUNTIME140_1.dll / CONCRT140.dll）。
; 目标机器没装该运行库时 LoadLibrary 会失败，抓图、搜图、文字识别会全部不可用。
;
; 处理分两层，互不干扰：
;   1. 本文件只负责「尝试加载 + 给出失败原因」，不预加载任何随包 DLL。
;      一旦提前把运行库塞进进程，「缺运行库」这个事实就被掩盖了，检测形同虚设。
;   2. 检测与自动安装在主进程 SelfCheck.ahk（VcRuntimeEnsureInstalled），
;      由调用方拿到失败原因后触发；Worker 没有界面层，只把原因上报。

; OpenCvEnsure 的会话级缓存。运行库补齐后需要重新尝试加载，
; 所以状态放全局，不能用函数内 static（外部无法清除）。
global OpenCvEnsureTried := false
global OpenCvEnsureReason := ""

OpenCvDllDir() {
    ; 目录由路径表统一给出（ProjectRootDir），主进程和 Worker 是同一个值，
    ; 不需要再按「我是谁」分支。
    archDir := (A_PtrSize = 4) ? "x86" : "x64"
    return ProjectRootDir "\Plugins\OpenCV\" archDir
}

IsOpenCvLoaded() {
    return DllCall("GetModuleHandle", "Str", "RMT_OpenCV.dll", "Ptr") != 0
}

; 检测 VC++ 2015-2022 运行库 DLL 是否缺失，返回缺失的 DLL 名（逗号分隔），无缺失返回 ""
; 实现已迁到 VcRuntimeUtil.ahk（注册表 + 系统目录文件，判据只有一处），这里只保留原签名。
GetMissingVcRuntime() {
    return VcRuntimeMissingText()
}

; 运行库补齐后调用，让下一次 OpenCvEnsure() 重新尝试加载
OpenCvResetEnsureCache() {
    global OpenCvEnsureTried, OpenCvEnsureReason
    OpenCvEnsureTried := false
    OpenCvEnsureReason := ""
}

; 确保 OpenCV DLL 可用。返回 "" 表示可用；否则返回失败原因（会话内只诊断/加载一次，避免刷日志）。
OpenCvEnsure() {
    global OpenCvEnsureTried, OpenCvEnsureReason

    if (IsOpenCvLoaded())
        return ""

    if (OpenCvEnsureTried)
        return OpenCvEnsureReason

    reason := ""
    dllDir := OpenCvDllDir()
    rmtDll := dllDir "\RMT_OpenCV.dll"
    worldDll := dllDir "\opencv_world481.dll"

    if (!FileExist(rmtDll) || !FileExist(worldDll)) {
        reason := Format("OpenCV 插件文件缺失：`n{}`n{}", rmtDll, worldDll)
    } else {
        ; 按插件目录解析依赖，避免更改进程全局 DLL 搜索路径。
        ; 先加载依赖库，失败时能精确区分“缺运行库”与“缺依赖”
        hWorld := DllCall("LoadLibraryEx", "Str", worldDll, "Ptr", 0, "UInt", 8, "Ptr")
        if (!hWorld) {
            worldErr := A_LastError
            vc := GetMissingVcRuntime()
            if (vc != "")
                reason := Format("缺少 Microsoft Visual C++ 运行库（{}）", vc)
            else
                reason := Format("opencv_world481.dll 加载失败（错误码 {}）", worldErr)
        } else {
            hRmt := DllCall("LoadLibraryEx", "Str", rmtDll, "Ptr", 0, "UInt", 8, "Ptr")
            if (!hRmt) {
                reason := Format("RMT_OpenCV.dll 加载失败（错误码 {}）", A_LastError)
                DllCall("FreeLibrary", "Ptr", hWorld)
            }
        }
    }

    OpenCvEnsureTried := true
    OpenCvEnsureReason := reason
    if (reason != "")
        SearchDebugLog(Format("OpenCV 不可用：{}", reason), "opencv")
    return reason
}

SearchColorHex(value) {
    return RegExReplace(Trim(String(value)), "^(#|0[xX])")
}

; 窗口颜色识别 x，y 窗口客户区坐标
FindWinColor(ResXPtr, ResYPtr, colorStr, hwnd, X1, Y1, X2, Y2, matchThreshold) {
    colorStr := SearchColorHex(colorStr)
    if (!RegExMatch(colorStr, "i)^[0-9a-f]{1,6}$"))
        return false
    if (OpenCvEnsure() != "")
        return false

    colorStr := Format("{:06X}", Integer("0x" colorStr))
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
    points := SearchAllSort(SearchAllTextPoints(result, text, X1, Y1), "左右优先")
    if (!points.Length)
        return false
    ResX := points[1][1]
    ResY := points[1][2]
    return true
}

;RapidOcr文本识别 result里面都是窗口坐标
GetScreenTextObjArr(X1, Y1, X2, Y2, mode) {
    global MyChineseOcr, MyEnglishOcr
    width := X2 - X1
    height := Y2 - Y1
    pBitmap := Gdip_BitmapFromScreen(X1 "|" Y1 "|" width "|" height)

    if !pBitmap
        throw Error("OCR 屏幕截图失败。")
    locked := false
    try {
        ; 获取位图的宽度和高度
        Width := Gdip_GetImageWidth(pBitmap)
        Height := Gdip_GetImageHeight(pBitmap)

        ; 锁定位图以获取位图数据
        if Gdip_LockBits(pBitmap, 0, 0, Width, Height, &Stride, &Scan0, &BitmapData)
            throw Error("OCR 无法锁定截图位图。")
        locked := true

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
    } finally {
        if locked
            Gdip_UnlockBits(pBitmap, &BitmapData)
        Gdip_DisposeImage(pBitmap)
    }
    return result
}

FindWinText(&ResX, &ResY, hwnd, X1, Y1, X2, Y2, text, mode) {
    result := GetWinTextObjArr(hwnd, X1, Y1, X2, Y2, mode)
    points := SearchAllSort(SearchAllTextPoints(result, text, X1, Y1), "左右优先")
    if (!points.Length)
        return false
    ResX := points[1][1]
    ResY := points[1][2]
    return true
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
    if !matPtr
        throw Error("OCR 窗口截图失败。")
    try {
        ocr := GetChineseOcr()
        return ocr.ocr_from_mat(matPtr, , true)
    } finally {
        DllCall("RMT_OpenCV.dll\ReleaseMat", "ptr", matPtr, "cdecl")
    }
}

; 当前 RMT_OpenCV.dll 是否带自适应匹配（老 dll 没有该导出 → 返回 false，自动走旧接口）
OpenCvAdaptiveReady() {
    static cached := -1
    if (cached != -1)
        return cached
    cached := 0
    try {
        if (DllCall("RMT_OpenCV.dll\GetApiVersion", "Cdecl Int") >= 2)
            cached := 1
    } catch {
    }
    return cached
}

; OpenCV屏幕图片识别
; API 12 将颜色匹配与相似度分离，旧 DLL 不能静默按 95% 切换算法。
OpenCvExplicitImageReady() {
    if (DllCall("RMT_OpenCV.dll\GetApiVersion", "Cdecl Int") < 12)
        throw Error("OpenCV 图片识别插件版本过旧，请更新 RMT_OpenCV.dll（需要 API 12）。")
}

FindScreenImage(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold, Adaptive := false, ColorMatch := false) {
    if (OpenCvEnsure() != "")
        return false

    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    OpenCvExplicitImageReady()
    return DllCall("RMT_OpenCV.dll\FindScreenImageEx", "AStr", targetPath, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int", ColorMatch ? 1 : 0, "Int", Adaptive ? 1 : 0, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}

; OpenCV窗口图片识别    返回窗口的坐标
FindWinImage(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold, Adaptive := false, ColorMatch := false) {
    if (OpenCvEnsure() != "")
        return false

    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    OpenCvExplicitImageReady()
    return DllCall("RMT_OpenCV.dll\FindWinImageEx", "AStr", targetPath, "Int", hwnd, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int", ColorMatch ? 1 : 0, "Int", Adaptive ? 1 : 0, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}

; 多点找图 API
MultiPointApiReady() {
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

AutoSelectPointsApiReady() {
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

MultiPointSuperApiReady() {
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

FindScreenImageMultiPoint(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold, points, tolerance := 8) {
    if (OpenCvEnsure() != "")
        return -5
    return DllCall("RMT_OpenCV.dll\FindScreenImageMultiPoint", "Str", targetPath
        , "Int", X1, "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1
        , "Int", matchThreshold, "Str", points, "Int", tolerance
        , "Int*", ResXPtr, "Int*", ResYPtr, "CDecl Int")
}

FindWinImageMultiPoint(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold, points, tolerance := 8) {
    if (OpenCvEnsure() != "")
        return -5
    return DllCall("RMT_OpenCV.dll\FindWinImageMultiPoint", "Str", targetPath, "Int", hwnd
        , "Int", X1, "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1
        , "Int", matchThreshold, "Str", points, "Int", tolerance
        , "Int*", ResXPtr, "Int*", ResYPtr, "CDecl Int")
}

FindScreenImageMultiPointSuper(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold, seedPoints, tolerance := 8, ignoreData := "") {
    if (!MultiPointSuperApiReady())
        return -5
    return DllCall("RMT_OpenCV.dll\FindScreenImageMultiPointSuper", "Str", targetPath
        , "Int", X1, "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1
        , "Int", matchThreshold, "Str", seedPoints, "Int", tolerance, "Str", ignoreData
        , "Int*", ResXPtr, "Int*", ResYPtr, "CDecl Int")
}

FindWinImageMultiPointSuper(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold, seedPoints, tolerance := 8, ignoreData := "") {
    if (!MultiPointSuperApiReady())
        return -5
    return DllCall("RMT_OpenCV.dll\FindWinImageMultiPointSuper", "Str", targetPath, "Int", hwnd
        , "Int", X1, "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1
        , "Int", matchThreshold, "Str", seedPoints, "Int", tolerance, "Str", ignoreData
        , "Int*", ResXPtr, "Int*", ResYPtr, "CDecl Int")
}

; 最近一次 OpenCV 图片处理错误。
GetImageLastErrorText() {
    if (OpenCvEnsure() != "")
        return ""
    try {
        pBuf := DllCall("RMT_OpenCV.dll\GetImageLastError", "CDecl Ptr")
        return pBuf ? StrGet(pBuf, "UTF-16") : ""
    } catch {
        return ""
    }
}
