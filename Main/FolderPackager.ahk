#Requires AutoHotkey v2.0

class FolderPackager {
    ; ── 解包安全限制（解包来源不可信的包时生效，P0）──
    static MAX_FILE_COUNT := 10000                       ; 条目数上限
    static MAX_FILE_SIZE := 200 * 1024 * 1024            ; 单文件上限 200MB
    static MAX_TOTAL_SIZE := 1024 * 1024 * 1024          ; 解压总大小上限 1GB（条目数 × 单文件上限可达 TB 级，必须有总量帽子）
    static ALLOWED_EXT := "ini,toml,json,txt,md,png,jpg,jpeg,gif,bmp,webp,ico,wav,mp3,onnx"

    ; 打包文件夹为二进制文件
    ; password 非空 → 整体加密，输出带 "RMTC" 头的密文包（导入时凭密码解开）
    static PackFolder(folderPath, outputFile, password := "") {
        if !DirExist(folderPath)
            throw Error(GetLang("文件夹不存在:") folderPath)

        ; 导出前先升级真实内容，再写入版本，不能把旧包仅改标签冒充新版。
        Compat_UpgradeDir(folderPath)
        CfgWrite(RMT_VERSION, Compat_VersionFile(folderPath), "RMT", "AppVersion")

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
        ; 加密作用于整个包：连文件名、图片内容都看不到，比逐个文件加密更干净
        buf := (password == "") ? mainBuffer : RMTC_SealBuffer(mainBuffer, password)
        FileEncoding("CP0")
        FileOpen(outputFile, "w").RawWrite(buf)
        return true
    }

    ; 打包并询问密码（勾选「不加密」= 明文）。返回 true 表示已写出文件，false 表示用户取消
    static PackFolderWithPassword(folderPath, outputFile, owner := 0) {
        r := RMTC_AskExportPassword(owner)
        if (!r.Ok)
            return false
        this.PackFolder(folderPath, outputFile, r.Pwd)
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
        fileSize := file.Length
        if (fileSize > this.MAX_TOTAL_SIZE + 16 * 1024 * 1024) {
            file.Close()
            throw Error(GetLang("打包文件解压后总大小超过上限，已中止解包"))
        }
        data := Buffer(fileSize)
        bytesRead := file.RawRead(data, fileSize)  ; 读取指定字节数
        file.Close()

        if bytesRead != fileSize
            throw Error(GetLang("文件读取不完整，期望") fileSize GetLang("字节，实际读取") bytesRead GetLang("字节"))

        ; 加密分享包：问一次密码，解出原始 RMPK 字节，后续解析流程完全不变
        if (data.Size >= 4 && StrGet(data, 4, "cp0") == "RMTC")
            data := this._DecryptData(data, packedFile)

        ; 解析文件头
        headerInfo := this._ParseHeader(data)
        if !headerInfo
            throw Error(GetLang("无效的打包文件格式"))

        pos := headerInfo.endPos
        totalSize := data.Size
        ; 整包校验通过前不创建目录、不删除版本标记、不覆盖原文件。
        entries := []
        fileNames := Map()
        fileNames.CaseSense := false
        extractedSize := 0
        this._RejectReparsePoint(outputFolder)
        while pos < totalSize {
            if (entries.Length >= this.MAX_FILE_COUNT)
                throw Error(GetLang("打包文件条目数超过上限，已中止解包"))
            entry := this._ParseFile(data, pos)
            if !entry
                throw Error(GetLang("无效的打包文件格式"))
            this._ValidateEntry(entry.path)
            if fileNames.Has(entry.path)
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " entry.path)
            fileNames[entry.path] := true
            extractedSize += entry.size
            if (extractedSize > this.MAX_TOTAL_SIZE)
                throw Error(GetLang("打包文件解压后总大小超过上限，已中止解包"))
            entries.Push(entry)
            pos := entry.nextPos
        }
        if !entries.Length
            throw Error(GetLang("无效的打包文件格式"))
        for entry in entries {
            path := outputFolder
            relative := ""
            parts := StrSplit(entry.path, "\")
            for i, segment in parts {
                path .= "\" segment
                relative .= (relative = "" ? "" : "\") segment
                this._RejectReparsePoint(path)
                attr := FileExist(path)
                isFolder := i < parts.Length
                if ((isFolder && fileNames.Has(relative)) || (attr && !!InStr(attr, "D") != isFolder))
                    throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " entry.path)
            }
        }

        ; 创建输出文件夹
        DirCreate(outputFolder)
        ; 覆盖解包无版本旧包时，不继承目标目录残留的新版本标记。
        versionPath := Compat_VersionFile(outputFolder)
        this._RejectReparsePoint(versionPath)
        if (FileExist(versionPath))
            FileDelete(versionPath)
        CfgInvalidate(versionPath)


        for fileInfo in entries {
            ; 创建子目录（如果需要）
            fileDir := outputFolder "\" fileInfo.dir
            if fileDir != outputFolder "\"
                DirCreate(fileDir)

            ; 写入文件
            outputPath := outputFolder "\" fileInfo.path
            out := FileOpen(outputPath, "w")
            try {
                if (fileInfo.size && out.RawWrite(data.Ptr + fileInfo.offset, fileInfo.size) != fileInfo.size)
                    throw Error(GetLang("文件写入失败:") " " fileInfo.path)
            } finally out.Close()

            if callback {
                progress := Round((fileInfo.nextPos / totalSize) * 100)
                callback("解包进度: " progress "% - " fileInfo.path, progress)
            }
        }

        if callback
            callback("解包完成: " outputFolder " (共 " entries.Length " 个文件)", 100)

        return true
    }

    static _RejectReparsePoint(path) {
        attrs := DllCall("GetFileAttributesW", "str", path, "uint")
        if (attrs != 0xFFFFFFFF && attrs & 0x400)
            throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " path)
    }

    ; 加密包 → 明文包字节。最多问 3 次密码，取消或连续输错就中止导入
    static _DecryptData(data, packedFile) {
        SplitPath packedFile, &name
        wrong := false
        loop 3 {
            r := RMTC_AskImportPassword(name, wrong)
            if (!r.Ok)
                throw Error(GetLang("已取消，未导入加密分享包"))
            try {
                return RMTC_OpenBuffer(data, r.Pwd)
            } catch as e {
                wrong := true
            }
        }
        throw Error(GetLang("密码错误次数过多，已取消导入"))
    }

    ; 私有方法
    static _CreateHeader() {
        header := Buffer(16)
        ; 文件标识符 (4字节)
        StrPut("RMPK", header, 4, "cp0")
        ; 时间戳 (8字节)
        NumPut("uint64", A_TickCount, header, 4)
        ; 容器格式版本 (4字节)，配置版本存放在包内 RmtVersion.toml
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
        if RegExMatch(name, '[<>:"/|?*]')
            throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        ; 拒绝控制字符
        loop parse name
            if (Ord(A_LoopField) < 32)
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        ; 拒绝 Windows 保留设备名
        for seg in StrSplit(name, "\") {
            if (!StrLen(seg) || RegExMatch(seg, "[ .]$"))
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
            base := seg
            dot := InStr(base, ".", , 1)
            if dot
                base := SubStr(base, 1, dot - 1)
            if (InStr("," RESERVED ",", "," RTrim(base) ",") || RegExMatch(base, "i)^(COM|LPT)[¹²³]$"))
                throw Error(GetLang("打包文件包含非法路径，已中止解包:") " " name)
        }
        ; 扩展名白名单
        ; 旧版导出会打包手动停用的定时文件，按原文件名保留备份。
        if (name = "TimingFile.bak")
            return
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
        if (nameLen < 2 || nameLen > 131072 || startPos + 4 + nameLen + 8 > data.Size)
            return false

        nameOffset := startPos + 4
        if NumGet(data, nameOffset + nameLen - 1, "uchar") != 0
            return false
        fileName := StrGet(data.Ptr + nameOffset, nameLen - 1, "UTF-8")
        if StrPut(fileName, "UTF-8") != nameLen
            return false

        ; 读取文件大小
        fileSize := NumGet(data, startPos + 4 + nameLen, "int64")

        ; 单文件大小上限（防止异常大文件直接分配内存）
        if (fileSize < 0 || fileSize > this.MAX_FILE_SIZE)
            throw Error(GetLang("打包文件包含超过大小上限的条目，已中止解包"))

        ; 计算数据位置
        dataStart := startPos + 4 + nameLen + 8
        dataEnd := dataStart + fileSize

        if dataEnd > data.Size
            return false

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
            offset: dataStart,
            size: fileSize,
            nextPos: dataEnd
        }
    }
}
