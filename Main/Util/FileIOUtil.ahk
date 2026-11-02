#Requires AutoHotkey v2.0

FileIONormType(t) {
    t := GetLangKey(t)
    if (t == "读取文本文件")
        return "读取文件"
    if (t == "写入文本文件")
        return "写入文件"
    return t
}

FileIOIsExcelType(t) {
    t := FileIONormType(t)
    return t == "读取Excel" || t == "写入Excel"
}

FileIOIsTextType(t) {
    t := FileIONormType(t)
    return t == "读取文件" || t == "写入文件"
}

FileIOIsReadType(t) {
    t := FileIONormType(t)
    return t == "读取Excel" || t == "读取文件"
}

FileIOTypeInList(t, arr) {
    t := FileIONormType(t)
    for x in arr {
        if (FileIONormType(x) == t)
            return true
    }
    return false
}

FileIOOperTypes(kind, extraType := "") {
    types := kind == "excel" ? ["读取Excel", "写入Excel"] : ["读取文件", "写入文件"]
    extra := FileIONormType(extraType)
    if (extra != "" && !FileIOTypeInList(extra, types))
        types := ["读取Excel", "写入Excel", "读取文件", "写入文件"]
    return GetLangArr(types)
}

FileIODefaultMode(operType) {
    switch FileIONormType(operType) {
        case "读取Excel", "写入Excel":
            return "单元格"
        case "读取文件":
            return "读取全部内容"
        case "写入文件":
            return "覆盖写入"
        default:
            return "单元格"
    }
}

CompatEnsureFileIOData(Data) {
    if (Data == "" || !IsObject(Data) || !ObjHasOwnProp(Data, "OperType"))
        return false
    old := Data.OperType
    Data.OperType := FileIONormType(old)
    return Data.OperType != old
}

SetFileIOGlobalData(Data) {
    CurType := FileIONormType(Data.OperType)
    CurMode := Data.OperMode
    IsRead := FileIOIsReadType(CurType)
    IsExcelRange := CurMode == "指定区域-行" || CurMode == "指定区域-列"
    IsVar := IsRead && !IsExcelRange
    IsArr := IsRead && IsExcelRange

    if (IsVar && Data.SaveName != "")
        MySoftData.GlobalVariMap[Data.SaveName] := true

    if (IsArr && Data.SaveName != "")
        MySoftData.GlobalArrMap[Data.SaveName] := true
}

ReadExcel(Data, tableItem, index) {
    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    HasRow := TryGetTabVarValue(&Row, tableItem, index, Data.RowVar, true)
    HasCol := TryGetTabVarValue(&Col, tableItem, index, Data.ColVar, true)
    if (!HasRow || !HasCol)
        return
    Row := Integer(Row), Col := Integer(Col)

    switch Data.OperMode {
        case "单元格":
            IsOk := ExcelCellToRead(FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalVariable([Data.SaveName], [ResArr], false)
        case "指定行":
            IsOk := ExcelRowToRead(FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定列":
            IsOk := ExcelColToRead(FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定区域-行":
            HasRowEnd := TryGetTabVarValue(&RowEnd, tableItem, index, Data.RowEndVar, true)
            HasColEnd := TryGetTabVarValue(&ColEnd, tableItem, index, Data.ColEndVar, true)
            if (!HasRowEnd || !HasColEnd)
                return
            RowEnd := Integer(RowEnd), ColEnd := Integer(ColEnd)
            err := CheckExcelRegionBounds(Row, Col, RowEnd, ColEnd)
            if (err != "") {
                RMTErrorShow(err, RMT_LV_WARN, "宏")
                return
            }
            IsOk := ExcelRangeRowToRead(FilePath, Data.NameOrSerial, Row, Col, RowEnd, ColEnd, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定区域-列":
            HasRowEnd := TryGetTabVarValue(&RowEnd, tableItem, index, Data.RowEndVar, true)
            HasColEnd := TryGetTabVarValue(&ColEnd, tableItem, index, Data.ColEndVar, true)
            if (!HasRowEnd || !HasColEnd)
                return
            RowEnd := Integer(RowEnd), ColEnd := Integer(ColEnd)
            err := CheckExcelRegionBounds(Row, Col, RowEnd, ColEnd)
            if (err != "") {
                RMTErrorShow(err, RMT_LV_WARN, "宏")
                return
            }
            IsOk := ExcelRangeColToRead(FilePath, Data.NameOrSerial, Row, Col, RowEnd, ColEnd, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
    }
}

; 指定区域：终止行/列 >= 起始；且行或列至少有一侧终止 > 起始（禁止单单元格）
; 字面量才校验；变量名则跳过（运行时再判）
CheckExcelRegionBounds(rowStart, colStart, rowEnd, colEnd) {
    hasRow := IsInteger(rowStart) && IsInteger(rowEnd)
    hasCol := IsInteger(colStart) && IsInteger(colEnd)
    if (hasRow) {
        r1 := Integer(rowStart), r2 := Integer(rowEnd)
        if (r2 < r1)
            return GetLang("终止行号必须大于或等于起始行号")
    }
    if (hasCol) {
        c1 := Integer(colStart), c2 := Integer(colEnd)
        if (c2 < c1)
            return GetLang("终止列号必须大于或等于起始列号")
    }
    if (hasRow && hasCol) {
        r1 := Integer(rowStart), r2 := Integer(rowEnd)
        c1 := Integer(colStart), c2 := Integer(colEnd)
        if (r2 == r1 && c2 == c1)
            return GetLang("指定区域无效：终止行与终止列不能同时等于起始（至少一侧终止大于起始）")
    }
    return ""
}

WriteExcel(Data, tableItem, index) {
    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    Content := GetReplaceVarText(tableItem, index, Data.Content)
    hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.RowVar)
    hasColValue := TryGetTabVarValue(&ColValue, tableItem, index, Data.ColVar)
    if (!hasRowValue || !hasColValue)
        return
    RowValue := Integer(RowValue), ColValue := Integer(ColValue)

    switch Data.OperMode {
        case "单元格":
            ExcelCellToWrite(FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "行号自增":
            ExcelRowToWrite(FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "列号自增":
            ExcelColToWrite(FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "指定区域-行":
            hasArray := TryGetArrValue(&Arr, Data.ArrName)
            if (hasArray) {
                ExcelRangeRowToWrite(FilePath, Data.NameOrSerial, RowValue, ColValue, Arr)
            }
        case "指定区域-列":
            hasArray := TryGetArrValue(&Arr, Data.ArrName)
            if (hasArray) {
                ExcelRangeColToWrite(FilePath, Data.NameOrSerial, RowValue, ColValue, Arr)
            }
    }
}

ReadTextFile(Data, tableItem, index) {
    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    switch Data.OperMode {
        case "读取全部内容":
            Content := FileRead(FilePath, Data.Encoding)
            MySetGlobalVariable([Data.SaveName], [Content], false)
        case "逐行读取":
            ResArr := []
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                FileEncoding(Data.Encoding)
                loop read, FilePath {
                    if (A_Index < RowValue)
                        continue
                    ResArr.Push(A_LoopReadLine)
                }
                MySetGlobalArray(Data.SaveName, ResArr)
            }
        case "指定行":
            Content := ""
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                FileEncoding(Data.Encoding)
                loop read, FilePath {
                    if (A_Index = RowValue) {
                        Content := A_LoopReadLine
                        break
                    }
                }
                MySetGlobalVariable([Data.SaveName], [Content], false)
            }
    }
}

WriteTextFile(Data, tableItem, index) {
    FilePath := GetReplaceVarText(tableItem, index, Data.FilePath)
    Content := GetReplaceVarText(tableItem, index, Data.Content)

    switch Data.OperMode {
        case "覆盖写入":
            FileObj := FileOpen(FilePath, "w", Data.Encoding)
            if !FileObj
                RMTErrorShow("文件打开失败: " FilePath, RMT_LV_ERROR, "宏")

            FileObj.Write(Content)
            FileObj.Close()
        case "追加写入":
            FileObj := FileOpen(FilePath, "a", Data.Encoding)
            FileObj.Write(Content)
            FileObj.Close()
        case "追加写入-行":
            FileObj := FileOpen(FilePath, "a", Data.Encoding)
            FileObj.WriteLine("")
            FileObj.Write(Content)
            FileObj.Close()
        case "指定行":
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                RowValue := Integer(RowValue)
                text := FileRead(FilePath, Data.Encoding)
                lines := StrSplit(text, "`n", "`r")

                ; 不够行就自动补
                while (lines.Length < RowValue)
                    lines.Push("")

                lines[RowValue] := Content

                FileObj := FileOpen(FilePath, "w", Data.Encoding)
                for i, line in lines {
                    if (i < lines.Length)
                        FileObj.WriteLine(line)
                    else
                        FileObj.Write(line) ; 最后一行不强制换行
                }

                FileObj.Close()
            }
        case "行号自增":
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                RowValue := Integer(RowValue)
                text := FileRead(FilePath, Data.Encoding)
                ; 分割成行（兼容 CRLF）
                lines := StrSplit(text, "`n", "`r")
                HasWrite := false

                loop lines.Length {
                    CurRow := RowValue + A_Index - 1
                    if (CurRow > lines.Length)
                        break
                    if (lines[CurRow] == "") {
                        HasWrite := true
                        lines[CurRow] := Content
                        break
                    }
                }

                if (!HasWrite)
                    lines.Push(Content)

                ; 重新写回文件（覆盖写）
                FileObj := FileOpen(FilePath, "w", Data.Encoding)
                ; 写回所有行
                for i, line in lines {
                    if (i < lines.Length)
                        FileObj.WriteLine(line)
                    else
                        FileObj.Write(line) ; 最后一行不强制换行
                }

                FileObj.Close()

            }
    }
}
