#Requires AutoHotkey v2.0

class FolderPackager {
    ; ── 解包安全限制（解包来源不可信的包时生效，P0）──
    static MAX_FILE_COUNT := 10000                       ; 条目数上限
    static MAX_FILE_SIZE := 200 * 1024 * 1024            ; 单文件上限 200MB
    static MAX_TOTAL_SIZE := 1024 * 1024 * 1024          ; 解压总大小上限 1GB（条目数 × 单文件上限可达 TB 级，必须有总量帽子）
    static ALLOWED_EXT := "ini,toml,json,txt,md,png,jpg,jpeg,gif,bmp,webp,ico,wav,mp3,onnx"

    ; 打包文件夹为二进制文件
    static PackFolder(folderPath, outputFile) {
        if !DirExist(folderPath)
            throw Error(GetLang("文件夹不存在:") folderPath)

        ; 获取所有文件列表
        files := this._GetAllFiles(folderPath)
        totalFiles := files.Length

        ; 预计算总大小
        totalSize := 16 ; 头部大小
        for filePath in files {
            relativePath := StrReplace(filePath, folderPath "\")
            fileNameLen := StrPut(relativePath, "utf-8")
            fileSize := FileGetSize(filePath)
            totalSize += 4 + fileNameLen + 8 + fileSize ; 文件名长度 + 文件名 + 文件大小 + 文件数据
        }

        ; 创建主缓冲区
        mainBuffer := Buffer(totalSize)
        pos := 0

        ; 写入文件头
        header := this._CreateHeader()
        DllCall("RtlMoveMemory", "ptr", mainBuffer.ptr + pos, "ptr", header.ptr, "uint", header.Size)
        pos += header.Size

        ; 遍历文件夹并添加文件
        processedFiles := 0
        for filePath in files {
            relativePath := StrReplace(filePath, folderPath "\")
            fileChunk := this._AddFile(relativePath, filePath)

            ; 将文件块复制到主缓冲区
            DllCall("RtlMoveMemory", "ptr", mainBuffer.ptr + pos, "ptr", fileChunk.ptr, "uint", fileChunk.Size)
            pos += fileChunk.Size

            processedFiles++
        }

        ; 保存到文件
        FileEncoding("CP0")
        FileOpen(outputFile, "w").RawWrite(mainBuffer)
        return true
    }

    ; 解包二进制文件为文件夹
    static UnpackFile(packedFile, outputFolder, callback := "") {
        if !FileExist(packedFile)
            throw Error(GetLang("打包文件不存在:") packedFile)

        if callback
            callback(GetLang("开始解包文件:") packedFile)

        ; 读取二进制数据 - 修正这里
        FileEncoding("CP0")
        file := FileOpen(packedFile, "r")
        fileSize := FileGetSize(packedFile)  ; 使用 FileGetSize 获取文件大小
        data := Buffer(fileSize)
        bytesRead := file.RawRead(data, fileSize)  ; 读取指定字节数
        file.Close()

        if bytesRead != fileSize
            throw Error(GetLang("文件读取不完整，期望") fileSize GetLang("字节，实际读取") bytesRead GetLang("字节"))

        ; 解析文件头
        headerInfo := this._ParseHeader(data)
        if !headerInfo
            throw Error(GetLang("无效的打包文件格式"))

        pos := headerInfo.endPos
        totalSize := data.Size
        processedSize := pos

        ; 创建输出文件夹
        DirCreate(outputFolder)

        ; 解析并提取文件
        fileCount := 0
        extractedSize := 0
        while pos < data.Size {
            fileInfo := this._ParseFile(data, pos)
            if !fileInfo
                break

            ; ── 安全校验：包可能来自不可信来源 ──
            if (++fileCount > this.MAX_FILE_COUNT)
                throw Error(GetLang("打包文件条目数超过上限，已中止解包"))

            this._ValidateEntry(fileInfo.path)

            ; 累计写出量上限：单文件有帽子，但条目数没约束时总量能到 TB 级
            extractedSize += fileInfo.data.Size
            if (extractedSize > this.MAX_TOTAL_SIZE)
                throw Error(GetLang("打包文件解压后总大小超过上限，已中止解包"))

            ; 创建子目录（如果需要）
            fileDir := outputFolder "\" fileInfo.dir
            if fileDir != outputFolder "\"
                DirCreate(fileDir)

            ; 写入文件
            outputPath := outputFolder "\" fileInfo.path
            FileOpen(outputPath, "w").RawWrite(fileInfo.data)

            pos := fileInfo.nextPos
            processedSize := pos

            if callback {
                progress := Round((processedSize / totalSize) * 100)
                callback("解包进度: " progress "% - " fileInfo.path, progress)
            }
        }

        if callback
            callback("解包完成: " outputFolder " (共 " fileCount " 个文件)", 100)

        return true
    }

    static UploadFile(selectedFile) {
        tempPath := outputFolder := A_WorkingDir "\Temp"
        FolderPackager.UnpackFile(selectedFile, tempPath)

        MyUseExplainGui.Mode := 2
        MyUseExplainGui.ModeAction := FolderPackager.VerifyOperation.Bind(FolderPackager, selectedFile)
        MyUseExplainGui.ShowGui(tempPath)
    }

    ;1确定   0关闭验证
    static VerifyOperation(selectedFile, isSure, isChange) {
        tempPath := outputFolder := A_WorkingDir "\Temp"
        if (isSure) {
            if (isChange) {
                FolderPackager.PackFolder(tempPath, selectedFile)
            }

            result := MsgBox(GetLang("共享上传文件：") selectedFile, GetLang("提示"), "4")
            if (result == "No")
                return

            global RMT_Http, RMT_HasDotNet
            if (!RMT_HasDotNet || RMT_Http == "") {
                MsgBox(GetLang("缺少.NET环境，无法使用共享上传功能"))
                return
            }

            result := RMT_Http.UploadFile(selectedFile)
            MsgBox(result)
        }
        if (DirExist(tempPath))
            DirDelete(tempPath, true)
    }

    ; 私有方法
    static _CreateHeader() {
        header := Buffer(16)
        ; 文件标识符 (4字节)
        StrPut("RMPK", header, 4, "cp0")
        ; 时间戳 (8字节)
        NumPut("uint64", A_TickCount, header, 4)
        ; 版本号 (4字节)
        NumPut("uint", 1, header, 12)
        return header
    }

    static _ParseHeader(data) {
        ; 检查文件标识符
        if data.Size < 4 || StrGet(data, 4, "cp0") != "RMPK"
            return false

        ; 校验版本号
        if data.Size < 16 || NumGet(data, 12, "uint") != 1
            return false

        return { endPos: 16 } ; 头部总长度
    }

    ; 校验条目路径与扩展名（防路径穿越 / 危险文件，P0）
    static _ValidateEntry(name) {
        static RESERVED := "CON,PRN,AUX,NUL,COM1,COM2,COM3,COM4,COM5,COM6,COM7,COM8,COM9,LPT1,LPT2,LPT3,LPT4,LPT5,LPT6,LPT7,LPT8,LPT9"

        if (name = "")
            throw Error(GetLang("打包文件包含空路径，已中止解包"))
        ; 拒绝 ..、盘符、正斜杠、反斜杠开头（只允许包内相对路径）
        if InStr(name, "..") || InStr(name, ":") || InStr(name, "/") || SubStr(name, 1, 1) = "\"
            throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        ; 拒绝控制字符
        loop parse name
            if (Ord(A_LoopField) < 32)
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        ; 拒绝 Windows 保留设备名
        for seg in StrSplit(name, "\") {
            base := seg
            dot := InStr(base, ".", , 1)
            if dot
                base := SubStr(base, 1, dot - 1)
            if InStr("," RESERVED ",", "," base ",")
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        }
        ; 扩展名白名单
        dot := InStr(name, ".", , -1)
        if !dot || !InStr("," this.ALLOWED_EXT ",", "," SubStr(name, dot + 1) ",")
            throw Error(GetLang("打包文件包含不允许的文件类型，已中止解包:") " " name)
    }

    static _GetAllFiles(folderPath) {
        files := []
        loop files folderPath "\*", "R" {
            if !InStr(FileExist(A_LoopFileFullPath), "D")
                files.Push(A_LoopFileFullPath)
        }
        return files
    }

    static _AddFile(relativePath, filePath) {
        ; 文件头格式: [文件名长度(4字节)][文件名][文件大小(8字节)][文件数据]
        fileNameLen := StrPut(relativePath, "utf-8")
        nameBuffer := Buffer(fileNameLen)
        StrPut(relativePath, nameBuffer, "utf-8")

        fileData := FileRead(filePath, "RAW")

        chunk := Buffer(4 + fileNameLen + 8 + fileData.Size)
        NumPut("uint", fileNameLen, chunk, 0)           ; 文件名长度
        DllCall("RtlMoveMemory", "ptr", chunk.ptr + 4, "ptr", nameBuffer.ptr, "uint", fileNameLen) ; 文件名
        NumPut("uint64", fileData.Size, chunk, 4 + fileNameLen) ; 文件大小
        DllCall("RtlMoveMemory", "ptr", chunk.ptr + 4 + fileNameLen + 8, "ptr", fileData.ptr, "uint", fileData.Size) ; 文件数据

        return chunk
    }

    static _ParseFile(data, startPos) {
        if startPos + 12 > data.Size ; 至少需要文件名长度(4) + 文件大小(8)
            return false

        ; 读取文件名长度
        nameLen := NumGet(data, startPos, "uint")
        if startPos + 4 + nameLen + 8 > data.Size
            return false

        ; 读取文件名
        fileNameBuf := Buffer(nameLen)
        DllCall("RtlMoveMemory", "ptr", fileNameBuf.ptr, "ptr", data.ptr + startPos + 4, "uint", nameLen)
        fileName := StrGet(fileNameBuf, "utf-8")

        ; 读取文件大小
        fileSize := NumGet(data, startPos + 4 + nameLen, "uint64")

        ; 单文件大小上限（防止异常大文件直接分配内存）
        if fileSize > this.MAX_FILE_SIZE
            throw Error(GetLang("打包文件包含超过大小上限的条目，已中止解包"))

        ; 计算数据位置
        dataStart := startPos + 4 + nameLen + 8
        dataEnd := dataStart + fileSize

        if dataEnd > data.Size
            return false

        ; 提取文件数据
        fileData := Buffer(fileSize)
        DllCall("RtlMoveMemory", "ptr", fileData.ptr, "ptr", data.ptr + dataStart, "uint", fileSize)

        ; 分离目录和文件名
        splitPos := InStr(fileName, "\", , -1)
        if splitPos {
            fileDir := SubStr(fileName, 1, splitPos - 1)
            fileNameOnly := SubStr(fileName, splitPos + 1)
        } else {
            fileDir := ""
            fileNameOnly := fileName
        }

        return {
            path: fileName,
            dir: fileDir,
            name: fileNameOnly,
            data: fileData,
            nextPos: dataEnd
        }
    }
}
