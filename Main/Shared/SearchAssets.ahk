SaveClipToBitmap(filePath) {
    ; 保存位图到文件; 检查剪切板中是否有位图
    if !DllCall("IsClipboardFormatAvailable", "uint", 2)  ; 2 是 CF_BITMAP
    {
        RMTErrorShow(GetLang("剪切板中没有位图"), RMT_LV_WARN, "宏")
    }

    ; 打开剪切板
    if !DllCall("OpenClipboard", "ptr", 0) {
        RMTErrorShow(GetLang("无法打开剪切板"), RMT_LV_WARN, "宏")
        return
    }

    ; 获取剪切板中的位图句柄
    hBitmap := DllCall("GetClipboardData", "uint", 2, "ptr")  ; 2 是 CF_BITMAP
    if !hBitmap {
        RMTErrorShow(GetLang("无法获取位图句柄"), RMT_LV_WARN, "宏")
        DllCall("CloseClipboard")
        return
    }

    ; 关闭剪切板
    DllCall("CloseClipboard")

    ; 创建 GDI+ 位图对象
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
    if !pBitmap {
        RMTErrorShow(GetLang("无法创建 GDI+ 位图对象"), RMT_LV_WARN, "宏")
        return
    }

    ; 保存位图到文件
    Gdip_SaveBitmapToFile(pBitmap, filePath)

    ; 释放 GDI+ 位图对象
    Gdip_DisposeImage(pBitmap)
}

GetImageSize(imageFile) {
    pBm := Gdip_CreateBitmapFromFile(imageFile)
    width := Gdip_GetImageWidth(pBm)
    height := Gdip_GetImageHeight(pBm)

    Gdip_DisposeImage(pBm)
    return [width, height]
}

GetNextImageSerial(baseDir := "") {
    if (baseDir == "")
        baseDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot"

    maxSerial := 0
    loop files, baseDir "\*.png" {
        if (RegExMatch(A_LoopFileName, "^(\d+)\.png$", &match)) {
            serial := Integer(match[1])
            if (serial > maxSerial)
                maxSerial := serial
        }
    }

    nextSerial := maxSerial + 1
    return Format("{:03d}", nextSerial)
}

; 返回第一个正则匹配的 1 基位置，未命中时返回 0。
FindRegexMatchPosition(source, pattern) {
    return RegExMatch(source, pattern)
}

; 计算命中文本在识别框中的坐标：按命中文本在识别文本中的位置比例定位到框内水平位置，
; 不再简单取整个识别框的中心（否则长段落/长行里鼠标会落在段落中间而不是目标文本上）。
; searchText 与 FindRegexMatchPosition 使用同一正则匹配规则。
GetOcrMatchScreenPosition(screenTextObj, x1, y1, searchText := "") {
    value := screenTextObj
    p1 := value.boxPoint[1]
    p2 := value.boxPoint[2]
    p3 := value.boxPoint[3]
    p4 := value.boxPoint[4]

    ; 文本框中心（垂直方向始终取中心；水平方向无命中文本时也退回中心）
    centerX := (p1.x + p2.x + p3.x + p4.x) / 4
    centerY := (p1.y + p2.y + p3.y + p4.y) / 4
    posX := centerX

    if (searchText != "") {
        textLen := StrLen(value.text)
        if (textLen > 0 && RegExMatch(value.text, searchText, &m)) {
            ; 命中文本中心在识别文本中的比例（0~1），按该比例在文本框左右边界间定位
            frac := (m.Pos - 1 + m.Len / 2) / textLen
            frac := Max(0, Min(1, frac))
            xs := [p1.x, p2.x, p3.x, p4.x]
            posX := Min(xs*) + frac * (Max(xs*) - Min(xs*))
        }
    }

    return [x1 + posX, y1 + centerY]
}
global LastChineseOcrUseTime := 0
global LastEnglishOcrUseTime := 0
global OCR_IDLE_TIMEOUT := 300000

GetChineseOcr() {
    global MyChineseOcr, LastChineseOcrUseTime, MainSoftData
    engineType := MainSoftData.OCRTypeValue == 2 ? 2 : 1
    if (MyChineseOcr && ((MyChineseOcr is TesseractOcr) != (engineType == 2))) {
        UnloadChineseOcr()
        UnloadEnglishOcr()
    }
    if (!MyChineseOcr)
        MyChineseOcr := engineType == 2 ? TesseractOcr(GetProjectRoot()) : RapidOcr(GetProjectRoot())
    LastChineseOcrUseTime := A_TickCount
    return MyChineseOcr
}

; 已弃用：PP-OCRv6 为统一多语言模型，GetChineseOcr/GetEnglishOcr 返回同一模型实例，保留仅为兼容旧调用
GetEnglishOcr() {
    return GetChineseOcr()
}

UnloadChineseOcr() {
    global MyChineseOcr
    if (MyChineseOcr) {
        MyChineseOcr.Destroy()
        MyChineseOcr := ""
    }
}

UnloadEnglishOcr() {
    global MyEnglishOcr
    if (MyEnglishOcr) {
        MyEnglishOcr.Destroy()
        MyEnglishOcr := ""
    }
}
