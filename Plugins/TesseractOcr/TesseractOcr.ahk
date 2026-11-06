#Requires AutoHotkey v2.0

; Tesseract C API；返回与 RapidOcr 相同的行文本及四角坐标。
class TesseractOcr {
    ptr := 0
    tessModule := 0
    leptModule := 0

    __New(root) {
        dir := root "\Plugins\TesseractOcr"
        bin := dir (A_PtrSize == 8 ? "\x64" : "\x86")
        for lang in ["chi_sim", "eng"]
            if !FileExist(dir "\tessdata\" lang ".traineddata")
                throw Error("Tesseract OCR 缺少语言模型：" lang ".traineddata")
        try {
            this.leptModule := DllCall("LoadLibraryEx", "str", bin "\leptonica-1.82.0.dll", "ptr", 0, "uint", 8, "ptr")
            this.tessModule := DllCall("LoadLibraryEx", "str", bin "\tesseract50.dll", "ptr", 0, "uint", 8, "ptr")
            if (!this.leptModule || !this.tessModule)
                throw Error("Tesseract OCR 插件加载失败，请检查插件与 VC++ 运行库。")
            this.ptr := DllCall(this.Tess("TessBaseAPICreate"), "cdecl ptr")
            if !this.ptr
                throw Error("Tesseract OCR 创建失败。")
            path := this.NativePath(dir "\tessdata")
            if DllCall(this.Tess("TessBaseAPIInit2"), "ptr", this.ptr, "astr", path, "astr", "chi_sim+eng", "int", 1, "cdecl int")
                throw Error("Tesseract OCR 模型初始化失败。")
            ; 屏幕中分散的文本，无需方向检测模型。
            DllCall(this.Tess("TessBaseAPISetPageSegMode"), "ptr", this.ptr, "int", 11, "cdecl")
        } catch as e {
            this.Destroy()
            throw e
        }
    }

    Tess(name) => DllCall("GetProcAddress", "ptr", this.tessModule, "astr", name, "ptr")
    Lept(name) => DllCall("GetProcAddress", "ptr", this.leptModule, "astr", name, "ptr")
    NativePath(path) {
        ; 此 Windows 构建以 ANSI 打开模型/Mat 文件；优先短路径，再验证本机编码。
        shortPath := Buffer(32768 * 2)
        if DllCall("GetShortPathName", "str", path, "ptr", shortPath, "uint", 32768)
            path := StrGet(shortPath)
        encoded := Buffer(StrPut(path, "CP0"))
        StrPut(path, encoded, "CP0")
        if StrGet(encoded, "CP0") != path
            throw Error("Tesseract OCR 无法访问该路径，请将软件放到英文路径。")
        return path
    }

    Destroy() {
        if this.ptr {
            DllCall(this.Tess("TessBaseAPIDelete"), "ptr", this.ptr, "cdecl")
            this.ptr := 0
        }
        if this.tessModule
            DllCall("FreeLibrary", "ptr", this.tessModule)
        if this.leptModule
            DllCall("FreeLibrary", "ptr", this.leptModule)
        this.tessModule := this.leptModule := 0
    }
    __Delete() => this.Destroy()

    ocr_from_file(path, param := 0, allresult := false) {
        data := FileRead(path, "RAW")
        return this.ocr_from_binary(data, data.Size, param, allresult)
    }

    ocr_from_binary(data, size, param := 0, allresult := false) {
        pix := DllCall(this.Lept("pixReadMem"), "ptr", data, "uptr", size, "cdecl ptr")
        if !pix
            throw Error("Tesseract OCR 无法读取图像。")
        try {
            DllCall(this.Tess("TessBaseAPISetImage2"), "ptr", this.ptr, "ptr", pix, "cdecl")
            DllCall(this.Tess("TessBaseAPISetSourceResolution"), "ptr", this.ptr, "int", 96, "cdecl")
            if DllCall(this.Tess("TessBaseAPIRecognize"), "ptr", this.ptr, "ptr", 0, "cdecl int")
                throw Error("Tesseract OCR 识别失败。")
            result := this.ReadResult()
            return allresult ? result : result.text
        } finally {
            DllCall(this.Tess("TessBaseAPIClear"), "ptr", this.ptr, "cdecl")
            DllCall(this.Lept("pixDestroy"), "ptr*", &pix, "cdecl")
        }
    }

    ocr_from_bitmapdata(data, param := 0, allresult := false) {
        bits := NumGet(data, 0, "ptr")
        stride := NumGet(data, A_PtrSize, "int")
        width := NumGet(data, A_PtrSize + 4, "int")
        height := NumGet(data, A_PtrSize + 8, "int")
        if (!bits || width <= 0 || height <= 0 || NumGet(data, A_PtrSize + 12, "int") != 4)
            throw Error("Tesseract OCR 位图数据无效。")
        ; BMP 保留 BGRA 通道，逐行处理正/负步长，避免颜色或上下方向颠倒。
        rowBytes := width * 4
        bmp := Buffer(54 + rowBytes * height, 0)
        NumPut("ushort", 0x4D42, "uint", bmp.Size, bmp, 0)
        NumPut("uint", 54, "uint", 40, "int", width, "int", height, "ushort", 1, "ushort", 32, bmp, 10)
        loop height
            DllCall("RtlMoveMemory", "ptr", bmp.Ptr + 54 + (height - A_Index) * rowBytes,
                "ptr", bits + (A_Index - 1) * stride, "uptr", rowBytes)
        return this.ocr_from_binary(bmp, bmp.Size, param, allresult)
    }

    ocr_from_mat(mat, param := 0, allresult := false) {
        if !mat
            throw Error("Tesseract OCR 窗口截图失败。")
        ; 复用 OpenCV 的导出接口，不依赖 cv::Mat 的内部布局。
        name := Buffer(520, 0)
        if !DllCall("GetTempFileName", "str", A_Temp, "str", "rmt", "uint", 0, "ptr", name)
            throw OSError()
        temp := StrGet(name)
        path := temp ".bmp"
        try {
            ; OpenCV 此接口使用 ANSI 路径；短路径保证中文用户目录可用。
            SplitPath(path, &fileName)
            path := this.NativePath(A_Temp) "\" fileName
            if !DllCall("RMT_OpenCV.dll\SaveMatToFile", "ptr", mat, "astr", path, "cdecl int")
                throw Error("Tesseract OCR 无法转换窗口截图。")
            return this.ocr_from_file(path, param, allresult)
        } finally {
            try FileDelete(path)
            try FileDelete(temp)
        }
    }

    ReadResult() {
        result := []
        result.text := ""
        iter := DllCall(this.Tess("TessBaseAPIGetIterator"), "ptr", this.ptr, "cdecl ptr")
        if !iter
            return result
        try {
            page := DllCall(this.Tess("TessResultIteratorGetPageIterator"), "ptr", iter, "cdecl ptr")
            loop {
                ptext := DllCall(this.Tess("TessResultIteratorGetUTF8Text"), "ptr", iter, "int", 2, "cdecl ptr")
                if ptext {
                    try text := Trim(StrGet(ptext, "UTF-8"), "`r`n")
                    finally DllCall(this.Tess("TessDeleteText"), "ptr", ptext, "cdecl")
                    left := top := right := bottom := 0
                    if (text != "" && DllCall(this.Tess("TessPageIteratorBoundingBox"), "ptr", page, "int", 2,
                        "int*", &left, "int*", &top, "int*", &right, "int*", &bottom, "cdecl int")) {
                        score := DllCall(this.Tess("TessResultIteratorConfidence"), "ptr", iter, "int", 2, "cdecl float") / 100
                        result.Push({text: text, boxPoint: [{x: left, y: top}, {x: right, y: top},
                            {x: right, y: bottom}, {x: left, y: bottom}], boxScore: score, charScores: []})
                        result.text .= (result.text == "" ? "" : "`n") text
                    }
                }
                if !DllCall(this.Tess("TessResultIteratorNext"), "ptr", iter, "int", 2, "cdecl int")
                    break
            }
        } finally DllCall(this.Tess("TessResultIteratorDelete"), "ptr", iter, "cdecl")
        return result
    }
}
