#Requires AutoHotkey v2.0

; ========== OpenCV DLL 加载与诊断 ==========
; RMT_OpenCV.dll 依赖 opencv_world481.dll，后者又依赖 Microsoft Visual C++ 2015-2022 运行库
; （MSVCP140.dll / VCRUNTIME140.dll / VCRUNTIME140_1.dll / CONCRT140.dll）。
; 若目标机器未安装该运行库，LoadLibrary 会失败，抓图、搜图等 OpenCV 功能将全部不可用。

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
    if (A_PtrSize != 8)
        return false
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
    ; v6 统一多语言模型，不再区分语言
    ocr := GetChineseOcr()

    res := ocr.ocr_from_mat(matPtr, , true)
    DllCall("RMT_OpenCV.dll\ReleaseMat", "ptr", matPtr, "cdecl")    ;释放mat，防止内存泄露

    return res
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
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return false
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
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return false
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
    if (A_PtrSize != 8)
        return false
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

AutoSelectPointsApiReady() {
    if (A_PtrSize != 8)
        return false
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

MultiPointSuperApiReady() {
    if (A_PtrSize != 8)
        return false
    if (OpenCvEnsure() != "")
        return false
    try {
        return DllCall("RMT_OpenCV.dll\GetApiVersion", "CDecl Int") >= 11
    } catch {
        return false
    }
}

FindScreenImageMultiPoint(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold, points, tolerance := 8) {
    if (A_PtrSize != 8)
        return -6
    if (OpenCvEnsure() != "")
        return -5
    return DllCall("RMT_OpenCV.dll\FindScreenImageMultiPoint", "Str", targetPath
        , "Int", X1, "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1
        , "Int", matchThreshold, "Str", points, "Int", tolerance
        , "Int*", ResXPtr, "Int*", ResYPtr, "CDecl Int")
}

FindWinImageMultiPoint(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold, points, tolerance := 8) {
    if (A_PtrSize != 8)
        return -6
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
