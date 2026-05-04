#Requires AutoHotkey v2.0

ExcelCellToWrite(wbPath, sheetIdentifier, row, col, value) {
    try {
        xlWorkbook := ComObjGet(wbPath)
        xlApp := xlWorkbook.Application
        if (!xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
            xlApp := ComObject("Excel.Application")
            xlWorkbook := xlApp.Workbooks.Open(wbPath, 0, false)  ; 非只读模式打开
        }
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        MsgBox GetLang("写入失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close()
            xlApp.Quit()
        }
    }
}

ExcelRowToWrite(wbPath, sheetIdentifier, row, col, value) {
    try {
        xlWorkbook := ComObjGet(wbPath)
        xlApp := xlWorkbook.Application
        if (!xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
            xlApp := ComObject("Excel.Application")
            xlWorkbook := xlApp.Workbooks.Open(wbPath, 0, false)  ; 非只读模式打开
        }
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        loop {
            CurRow := row + A_Index - 1
            if (sheet.Cells(CurRow, col).Text == "") {
                row := CurRow
                break
            }
        }
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        MsgBox GetLang("写入失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close()
            xlApp.Quit()
        }
    }
}

ExcelColToWrite(wbPath, sheetIdentifier, row, col,  value) {
    try {
        xlWorkbook := ComObjGet(wbPath)
        xlApp := xlWorkbook.Application
        if (!xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
            xlApp := ComObject("Excel.Application")
            xlWorkbook := xlApp.Workbooks.Open(wbPath, 0, false)  ; 非只读模式打开
        }
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        loop {
            CurCol := col + A_Index - 1
            if (sheet.Cells(row, CurCol).Text == "") {
                col := CurCol
                break
            }
        }
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        MsgBox GetLang("写入失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close()
            xlApp.Quit()
        }
    }
}

ExcelRangeRowToWrite(xlPath, SheetIdentifier, Row, Col, Arr) {
    try {
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        if (!xlApp.Visible) {
             xlWorkbook.Close(false)
            xlApp.Quit()
            xlApp := ComObject("Excel.Application")
            xlWorkbook := xlApp.Workbooks.Open(xlPath, 0, false)  ; 非只读模式打开
        }
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)

        IsDoubleArr := Arr.Length >= 1 && IsObject(Arr[1])
        if (!IsDoubleArr) {
            loop Arr.Length {
                CurCol := Col + A_Index - 1
                Value := IsObject(Arr[A_Index]) ? GetArrayStr(Arr[A_Index]) : Arr[A_Index]
                sheet.Cells(Row, CurCol).Value := Value
            }
        }
        else {
            loop Arr.Length {
                CurRow := Row + A_Index - 1
                SubArr := Arr[A_Index]
                loop SubArr.Length {
                    CurCol := Col + A_Index - 1
                    sheet.Cells(CurRow, CurCol).Value := SubArr[A_Index]
                }
            }
        }

        xlWorkbook.Save()
        return true
    }
    catch as e {
        MsgBox GetLang("写入失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close()
            xlApp.Quit()
        }
    }
}

ExcelRangeColToWrite(xlPath, SheetIdentifier, Row, Col, Arr) {
    try {
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        if (!xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
            xlApp := ComObject("Excel.Application")
            xlWorkbook := xlApp.Workbooks.Open(xlPath, 0, false)  ; 非只读模式打开
        }
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)

        IsDoubleArr := Arr.Length >= 1 && IsObject(Arr[1])
        if (!IsDoubleArr) {
            loop Arr.Length {
                CurRow := Row + A_Index - 1
                Value := IsObject(Arr[A_Index]) ? GetArrayStr(Arr[A_Index]) : Arr[A_Index]
                sheet.Cells(CurRow, Col).Value := Value
            }
        }
        else {
            loop Arr.Length {
                CurCol := Col + A_Index - 1
                SubArr := Arr[A_Index]
                loop SubArr.Length {
                    CurRow := Row + A_Index - 1
                    sheet.Cells(CurRow, CurCol).Value := SubArr[A_Index]
                }
            }
        }

        xlWorkbook.Save()
        return true
    }
    catch as e {
        MsgBox GetLang("写入失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close()
            xlApp.Quit()
        }
    }
}

ExcelCellToRead(wbPath, sheetIdentifier, row, col, &ResValue) {
    try {
        xlWorkbook := ComObjGet(wbPath)
        xlApp := xlWorkbook.Application
        xlApp.Calculate()
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)

        ; 获取单元格
        cell := sheet.Cells(row, col)
        if cell.MergeCells {
            ResValue := cell.MergeArea.Cells(1, 1).Text
        } else {
            ResValue := cell.Text
        }
        return true
    }
    catch as e {
        MsgBox GetLang("读取失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
        }
    }
}

ExcelRowToRead(xlPath, SheetIdentifier, Row, Col, &ResArr) {
    try {
        ResArr := []
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        xlApp.Calculate()       ;Calculate会导致文件内容修改，不保存会提示
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        Sheet := xlWorkbook.Sheets(SheetIdentifier)

        CurCol := Col
        IsNullCount := 0
        loop {
            Cell := Sheet.Cells(Row, CurCol)
            if Cell.MergeCells {
                Value := Cell.MergeArea.Cells(1, 1).Text
            } else {
                Value := Cell.Text
            }
            IsNullCount := Value == "" ? IsNullCount + 1 : 0
            if (IsNullCount == 5)
                break
            ResArr.Push(Value)
            CurCol++
        }
        ArrayTrimRightNull(ResArr)
        return true
    }
    catch as e {
        MsgBox GetLang("读取失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
        }
    }
}

ExcelColToRead(xlPath, SheetIdentifier, Row, Col, &ResArr) {
    try {
        ResArr := []
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        Sheet := xlWorkbook.Sheets(SheetIdentifier)

        CurRow := Row
        IsNullCount := 0
        loop {
            Cell := Sheet.Cells(CurRow, Col)
            if Cell.MergeCells {
                Value := Cell.MergeArea.Cells(1, 1).Text
            } else {
                Value := Cell.Text
            }
            IsNullCount := Value == "" ? IsNullCount + 1 : 0
            if (IsNullCount == 5)
                break
            ResArr.Push(Value)
            CurRow++
        }
        ArrayTrimRightNull(ResArr)
        return true
    }
    catch as e {
        MsgBox GetLang("读取失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
        }
    }
}

ExcelRangeRowToRead(xlPath, SheetIdentifier, Row, Col, EndRow, EndCol, &ResArr) {
    try {
        ResArr := []
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        sheet := xlWorkbook.Sheets(SheetIdentifier)

        loop EndRow - Row + 1 {
            CurRow := Row + A_Index - 1
            ResArr.Push([])
            loop EndCol - Col + 1 {
                CurCol := Col + A_Index - 1
                Cell := sheet.Cells(CurRow, CurCol)
                if Cell.MergeCells {
                    Value := Cell.MergeArea.Cells(1, 1).Text
                } else {
                    Value := Cell.Text
                }
                ResArr[ResArr.Length].Push(Value)
            }
        }
        return true
    }
    catch as e {
        MsgBox GetLang("读取失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
        }
    }
}

ExcelRangeColToRead(xlPath, SheetIdentifier, Row, Col, EndRow, EndCol, &ResArr) {
    try {
        ResArr := []
        xlWorkbook := ComObjGet(xlPath)
        xlApp := xlWorkbook.Application
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        sheet := xlWorkbook.Sheets(SheetIdentifier)

        loop EndCol - Col + 1 {
            CurCol := Col + A_Index - 1
            ResArr.Push([])
            loop EndRow - Row + 1 {
                CurRow := Row + A_Index - 1
                Cell := sheet.Cells(CurRow, curCol)
                if Cell.MergeCells {
                    Value := Cell.MergeArea.Cells(1, 1).Text
                } else {
                    Value := Cell.Text
                }
                ResArr[ResArr.Length].Push(Value)
            }
        }
        return true
    }
    catch as e {
        MsgBox GetLang("读取失败：") e.Message
        return false
    }
    finally {
        if (IsSet(xlApp) && !xlApp.Visible) {
            xlWorkbook.Close(false)
            xlApp.Quit()
        }
    }
}
