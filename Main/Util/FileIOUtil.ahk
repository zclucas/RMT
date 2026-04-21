#Requires AutoHotkey v2.0

SetFileIOGlobalData(Data) {
    CurType := Data.OperType
    CurMode := Data.OperMode
    IsRead := CurType == "读取Excel" || CurType == "读取文本文件"
    IsExcelRange := CurMode == "指定区域-行" || CurMode == "指定区域-列"
    IsVar := IsRead && !IsExcelRange
    IsArr := IsRead && IsExcelRange

    if (IsVar && Data.SaveName != "")
        MySoftData.GlobalVariMap[Data.SaveName] := true

    if (IsArr && Data.SaveName != "")
        MySoftData.GlobalArrMap[Data.SaveName] := true
}

ReadExcel(Data, tableItem, index) {
    HasRow := TryGetTabVarValue(&Row, tableItem, index, Data.RowVar, true)
    HasCol := TryGetTabVarValue(&Col, tableItem, index, Data.ColVar, true)
    if (!HasRow || !HasCol)
        return

    switch Data.OperMode {
        case "单元格":
            IsOk := ExcelCellToRead(Data.FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalVariable([Data.SaveName], [ResArr], false)
        case "指定行":
            IsOk := ExcelRowToRead(Data.FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定列":
            IsOk := ExcelColToRead(Data.FilePath, Data.NameOrSerial, Row, Col, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定区域-行":
            HasRowEnd := TryGetTabVarValue(&RowEnd, tableItem, index, Data.RowEndVar, true)
            HasColEnd := TryGetTabVarValue(&ColEnd, tableItem, index, Data.ColEndVar, true)
            if (!HasRowEnd || !HasColEnd)
                return
            IsOk := ExcelRangeRowToRead(Data.FilePath, Data.NameOrSerial, Row, Col, RowEnd, ColEnd, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
        case "指定区域-列":
            HasRowEnd := TryGetTabVarValue(&RowEnd, tableItem, index, Data.RowEndVar, true)
            HasColEnd := TryGetTabVarValue(&ColEnd, tableItem, index, Data.ColEndVar, true)
            if (!HasRowEnd || !HasColEnd)
                return
            IsOk := ExcelRangeColToRead(Data.FilePath, Data.NameOrSerial, Row, Col, RowEnd, ColEnd, &ResArr)
            if (IsOk)
                MySetGlobalArray(Data.SaveName, ResArr)
    }
}

WriteExcel(Data, tableItem, index) {
    Content := GetReplaceVarText(tableItem, index, Data.Content)
    hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.RowVar)
    hasColValue := TryGetTabVarValue(&ColValue, tableItem, index, Data.ColVar)
    if (!hasRowValue || !hasColValue)
        return

    switch Data.OperMode {
        case "单元格":
            ExcelCellToWrite(Data.FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "行号自增":
            ExcelRowToWrite(Data.FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "列号自增":
            ExcelColToWrite(Data.FilePath, Data.NameOrSerial, RowValue, ColValue, Content)
        case "指定区域-行":
            hasArray := TryGetArrValue(&Arr, Data.ArrName)
            if (hasArray) {
                ExcelRangeRowToWrite(Data.FilePath, Data.NameOrSerial, RowValue, ColValue, Arr)
            }
        case "指定区域-列":
            hasArray := TryGetArrValue(&Arr, Data.ArrName)
            if (hasArray) {
                ExcelRangeColToWrite(Data.FilePath, Data.NameOrSerial, RowValue, ColValue, Arr)
            }
    }
}

ReadTextFile(Data, tableItem, index) {
    switch Data.OperMode {
        case "读取全部内容":
            Content := FileRead(Data.FilePath, Data.Encoding)
            MySetGlobalVariable([Data.SaveName], [Content], false)
        case "逐行读取":
            ResArr := []
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                FileEncoding(Data.Encoding)
                loop read, Data.FilePath {
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
                loop read, Data.FilePath {
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
    Content := GetReplaceVarText(tableItem, index, Data.Content)

    switch Data.OperMode {
        case "覆盖写入":
            FileObj := FileOpen(Data.FilePath, "w", Data.Encoding)
            if !FileObj
                MsgBox("文件打开失败: " Data.FilePath)

            FileObj.Write(Content)
            FileObj.Close()
        case "追加写入":
            FileObj := FileOpen(Data.FilePath, "a", Data.Encoding)
            FileObj.Write(Content)
            FileObj.Close()
        case "追加写入-行":
            FileObj := FileOpen(Data.FilePath, "a", Data.Encoding)
            FileObj.WriteLine("")
            FileObj.Write(Content)
            FileObj.Close()
        case "指定行":
            hasRowValue := TryGetTabVarValue(&RowValue, tableItem, index, Data.TextRowVar)
            if (hasRowValue) {
                RowValue := Integer(RowValue)
                text := FileRead(Data.FilePath, Data.Encoding)
                ; 分割成行（兼容 CRLF）
                lines := StrSplit(text, "`n", "`r")

                ; 不够行就自动补
                while (lines.Length < RowValue)
                    lines.Push("")

                lines[RowValue] := Content

                ; 重新写回文件（覆盖写）
                FileObj := FileOpen(Data.FilePath, "w", Data.Encoding)
                ; 写回所有行
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
                text := FileRead(Data.FilePath, Data.Encoding)
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
                FileObj := FileOpen(Data.FilePath, "w", Data.Encoding)
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
