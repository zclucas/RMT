#Requires AutoHotkey v2.0
; 窗口颜色识别 x，y 窗口坐标
FindWinColor(ResXPtr, ResYPtr, colorStr, hwnd, X1, Y1, X2, Y2, matchThreshold) {
    if (A_PtrSize != 8) ;非64位不可用
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
    if (A_PtrSize != 8) ;非64位不可用，直接退出
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
    
    searchX := X1
    searchY := Y1
    searchW := X2 - X1
    searchH := Y2 - Y1
    return DllCall("RMT_OpenCV.dll\FindWinImage", "AStr", targetPath, "Int", hwnd, "Int", searchX,
        "Int", searchY, "Int", searchW, "Int", searchH, "Int", matchThreshold, "Int*", ResXPtr, "Int*", ResYPtr,
        "Cdecl Int")
}
