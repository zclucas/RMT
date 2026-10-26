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
            pos := GetMatchCoord(value, X1, Y1, text)
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

    ; 调用 ocr_from_bitmapdata 方法
    ocr := mode == 1 ? GetChineseOcr() : GetEnglishOcr()
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
            ; GetMatchCoord 已加上截图区域起点 X1/Y1，返回窗口客户区坐标（与 FindWinColor/FindWinImage 一致），无需再加
            pos := GetMatchCoord(value, X1, Y1, text)
            ResX := pos[1]
            ResY := pos[2]
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
    ocr := mode == 1 ? GetChineseOcr() : GetEnglishOcr()

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

; OpenCV屏幕图片识别（支持颜色筛选）  返回目标左上角屏幕坐标
; filterColors: "FF00FF,00FF00"（RRGGBB），空串表示不做颜色筛选
; filterMode:   0=排除这些颜色   1=只保留这些颜色（默认，其余像素不参与匹配）
; 返回码: 1找到 / 0未找到 / -1模板读取失败 / -2模板大于搜索区 / -3OpenCV异常 / -4有效像素不足 / -5截图失败 / -6参数非法
FindScreenImageFilter(ResXPtr, ResYPtr, targetPath, X1, Y1, X2, Y2, matchThreshold, filterColors, tolerance, filterMode := 1) {
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return -6
    if (OpenCvEnsure() != "")
        return -5

    return DllCall("RMT_OpenCV.dll\FindScreenImageFilter", "Str", targetPath, "Int", X1,
        "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1, "Int", matchThreshold,
        "Str", filterColors, "Int", tolerance, "Int", filterMode,
        "Int*", ResXPtr, "Int*", ResYPtr, "Cdecl Int")
}

; 渲染一次预览到指定文件；返回 {ret, ow, oh, pw, ph}
RenderFilterPreviewTo(templatePath, filterColors, tolerance, filterMode, size, zoom, outPath) {
    valid := 0, total := 0, pw := 0, ph := 0, ow := 0, oh := 0
    bx := 0, by := 0, bw := 0, bh := 0
    ret := DllCall("RMT_OpenCV.dll\RenderFilterPreview"
        , "Str", templatePath, "Str", filterColors, "Int", tolerance, "Int", filterMode
        , "Int", size, "Int", size
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0          ; view：0 = 整图
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0          ; 无选区框
        , "Int", 0                                       ; 不画像素格
        , "Int", zoom
        , "Str", outPath, "Str", outPath
        , "Int*", &valid, "Int*", &total, "Int*", &pw, "Int*", &ph
        , "Int*", &ow, "Int*", &oh, "Int*", &bx, "Int*", &by, "Int*", &bw, "Int*", &bh
        , "CDecl Int")
    return { ret: ret, ow: ow, oh: oh, pw: pw, ph: ph }
}

; 生成"保留后"缩略图，用于搜索Pro 里的预览框。成功返回图片路径，失败返回 ""
SaveFilteredPreview(templatePath, filterColors, tolerance, outPath, size := 100, filterMode := 1) {
    if (OpenCvEnsure() != "")
        return ""

    ; 先按 100% 渲一次拿原图尺寸（这次输出会被裁，只是探尺寸）
    probe := A_Temp "\RMT_thumb_probe.png"
    info := RenderFilterPreviewTo(templatePath, filterColors, tolerance, filterMode, size, 100, probe)
    if (info.ret != 1 || info.ow <= 0 || info.oh <= 0)
        return ""

    ; 再按"适应尺寸"渲一次
    zoom := Max(1, Floor(Min(size / info.ow, size / info.oh) * 100))
    info := RenderFilterPreviewTo(templatePath, filterColors, tolerance, filterMode, size, zoom, outPath)
    return (info.ret = 1) ? outPath : ""
}

; 取滤色找图最近一次的错误描述（没找到时会带"本区域最高 xx%"）
GetFilterLastErrorText() {
    if (OpenCvEnsure() != "")
        return ""
    try {
        pBuf := DllCall("RMT_OpenCV.dll\GetFilterLastError", "CDecl Ptr")
        return pBuf ? StrGet(pBuf, "UTF-16") : ""
    } catch {
        return ""
    }
}

; OpenCV窗口图片识别（保留色）  返回窗口客户区坐标
; 与 FindScreenImageFilter 同一套掩码逻辑，只是截图换成按窗口句柄取
FindWinImageFilter(ResXPtr, ResYPtr, targetPath, hwnd, X1, Y1, X2, Y2, matchThreshold, filterColors, tolerance, filterMode := 1) {
    if (A_PtrSize != 8) ;非64位不可用，直接退出
        return -6
    if (OpenCvEnsure() != "")
        return -5

    return DllCall("RMT_OpenCV.dll\FindWinImageFilter", "Str", targetPath, "Int", hwnd, "Int", X1,
        "Int", Y1, "Int", X2 - X1, "Int", Y2 - Y1, "Int", matchThreshold,
        "Str", filterColors, "Int", tolerance, "Int", filterMode,
        "Int*", ResXPtr, "Int*", ResYPtr, "Cdecl Int")
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
