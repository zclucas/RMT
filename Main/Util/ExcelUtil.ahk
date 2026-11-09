#Requires AutoHotkey v2.0

; 同一工作簿的读、写及关闭在不同 Worker 间串行执行。
class ExcelWorkbookLock {
    handle := 0

    __New(path, item := "") {
        this.path := ExcelWorkbookPath(path, &name)
        handle := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0, "Str", name, "Ptr")
        if (!handle)
            throw OSError()
        this.previousCritical := A_IsCritical
        deadline := A_TickCount + 20000
        try {
            while (!item || !item.Killed) {
                Critical("On")
                wait := DllCall("Kernel32\WaitForSingleObject", "Ptr", handle, "UInt", 0, "UInt")
                if (wait == 0 || wait == 0x80) { ; WAIT_OBJECT_0 / WAIT_ABANDONED
                    this.handle := handle
                    return
                }
                if (wait != 0x102 || A_TickCount >= deadline) ; WAIT_TIMEOUT
                    throw Error(GetLang("无法锁定工作簿"))
                Critical(this.previousCritical)
                Sleep(25)
            }
        } finally {
            if (!this.handle) {
                DllCall("Kernel32\CloseHandle", "Ptr", handle)
                Critical(this.previousCritical)
            }
        }
    }

    Close() {
        if (!this.handle)
            return
        DllCall("Kernel32\ReleaseMutex", "Ptr", this.handle)
        DllCall("Kernel32\CloseHandle", "Ptr", this.handle)
        this.handle := 0
        Critical(this.previousCritical)
    }
}

ExcelWorkbookPath(path, &mutexName) {
    fullPath := Buffer(32768 * 2)
    length := DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", 32768, "Ptr", fullPath, "Ptr", 0, "UInt")
    if (!length || length >= 32768)
        throw Error(GetLang("工作簿路径无效"))
    path := StrGet(fullPath, length, "UTF-16")
    normalized := StrLower(path)
    bytes := Buffer(StrPut(normalized, "UTF-16"))
    StrPut(normalized, bytes, "UTF-16")
    hash := Buffer(16)
    if (DllCall("Shlwapi\HashData", "Ptr", bytes, "UInt", bytes.Size, "Ptr", hash, "UInt", hash.Size, "Int") != 0)
        throw Error(GetLang("无法锁定工作簿"))
    mutexName := Format("Local\RMT.Excel.{:016X}{:016X}", NumGet(hash, 0, "Int64"), NumGet(hash, 8, "Int64"))
    return path
}

ExcelDllRead(path, sheet, mode, row, col, endRow, endCol, &result, item) {
    if (!ExcelDllRun(path, sheet, mode, false, row, col, endRow, endCol, "", &values, item))
        return false
    if (mode == "Cell") {
        result := values[0]
        return true
    }
    result := []
    if (endRow != row && endCol != col) {
        width := mode == "RowRange" ? endCol - col + 1 : endRow - row + 1
        for value in values {
            if (!result.Length || result[-1].Length == width)
                result.Push([])
            result[-1].Push(value)
        }
    } else {
        for value in values
            result.Push(value)
    }
    return true
}

ExcelDllWrite(path, sheet, mode, row, col, values, item) {
    return ExcelDllRun(path, sheet, mode, true, row, col, row, col, values, &unused, item)
}

; 将写入内容转为 [行偏移, 列偏移, 值]，保留锯齿数组和原有排列方式。
ExcelDllWriteCells(mode, values) {
    if (mode != "RowRange" && mode != "ColumnRange") {
        cells := ComObjArray(12, 3)
        cells[0] := 0, cells[1] := 0, cells[2] := values
        return cells
    }
    nested := values.Length && IsObject(values[1])
    byRow := mode == "RowRange"
    count := values.Length
    if (nested) {
        count := 0
        for line in values
            count += line.Length
    }
    cells := ComObjArray(12, count * 3)
    index := 0
    for i, value in values {
        if (nested) {
            for j, cell in value {
                cells[index++] := byRow ? i - 1 : j - 1
                cells[index++] := byRow ? j - 1 : i - 1
                cells[index++] := cell
            }
        } else {
            cells[index++] := byRow ? 0 : i - 1
            cells[index++] := byRow ? i - 1 : 0
            cells[index++] := IsObject(value) ? GetArrayStr(value) : value
        }
    }
    return cells
}

GetRmtExcelEditor() {
    global RMT_ASM
    if (!IsObject(RMT_ASM))
        RMT_ASM := CLR_LoadLibrary(EnsureRmtDll())
    editor := RMT_ASM.CreateInstance("RMT.ExcelEditor")
    if (!IsObject(editor))
        throw Error(GetLang("无法加载 Excel DLL"))
    return editor
}

ExcelDllRun(path, sheet, mode, write, row, col, endRow, endCol, values, &result, item) {
    try {
        if (item && item.Killed)
            return false
        path := ExcelWorkbookPath(path, &mutexName)
        job := GetRmtExcelEditor()
        cells := write ? ExcelDllWriteCells(mode, values) : ComObjArray(12, 0)
        if (IsInteger(sheet))
            sheet := Integer(sheet)
        if (!job.Begin(path, mutexName, sheet, mode, write, row, col, endRow, endCol, cells))
            throw Error(GetLang("当前进程已有 Excel 操作在运行"))
        deadline := DllCall("GetTickCount64", "UInt64") + 60000
        waitingForElevation := false
        while (state := job.GetState()) == 1 {
            if (item && item.Killed)
                return false
            now := DllCall("GetTickCount64", "UInt64")
            waiting := job.IsWaitingForElevation()
            if (waiting != waitingForElevation) {
                waitingForElevation := waiting
                deadline := now + (waiting ? 120000 : 60000)
            }
            if (now >= deadline) {
                message := waiting ? "等待 Excel 管理员授权超时" : "Excel 操作超时。若已开始写入，请检查工作簿。"
                throw Error(GetLang(message))
            }
            Sleep(25)
        }
        if (item && item.Killed)
            return false
        if (state != 2) {
            message := ""
            for i, line in StrSplit(job.GetError(), "`n", "`r")
                message .= (i > 1 ? "`n" : "") GetLang(line)
            throw Error(message)
        }
        if (!write)
            result := job.GetResult()
        return true
    } catch as e {
        failure := e.Message
    } finally {
        if (IsSet(job) && IsObject(job))
            try job.Cancel()
    }
    RmtDialog.Info(GetLang(write ? "写入失败：" : "读取失败：") failure)
    return false
}

class ExcelElevationRequired extends Error {
}

; 优先从现有窗口获取工作簿，找不到时走原有 COM 文件绑定。
ExcelOpenWorkbook(path, writable, &app, &closeBackground, &workbook) {
    workbook := ""
    try {
        editor := GetRmtExcelEditor()
        workbook := editor.FindOpenWorkbook(path)
    }
    attached := IsObject(workbook) && ComObjValue(workbook)
    if (!attached) {
        needsElevation := false
        if (IsSet(editor))
            try needsElevation := editor.NeedsElevationForLockedWorkbook(path)
        if (needsElevation)
            throw ExcelElevationRequired()
        try workbook := ComObjGet(path)
        catch as e {
            accessError := ""
            if (writable && IsSet(editor))
                try accessError := editor.GetOpenWorkbookError()
            if (accessError != "")
                throw Error(e.Message "`n" GetLang(accessError))
            throw e
        }
    }
    app := workbook.Application
    closeBackground := !attached && !app.Visible
    if (writable && workbook.ReadOnly) {
        needsElevation := false
        if (IsSet(editor))
            try needsElevation := editor.NeedsElevationForLockedWorkbook(path)
        if (needsElevation)
            throw ExcelElevationRequired()
        if (!attached && IsSet(editor)) {
            accessError := ""
            try accessError := editor.GetOpenWorkbookError()
            if (accessError != "")
                throw Error(GetLang(accessError))
        }
        if (closeBackground)
            workbook.ChangeFileAccess(2, , false) ; xlReadWrite
        if (workbook.ReadOnly)
            throw Error(GetLang("工作簿为只读"))
    }
}

ExcelCloseBackgroundWorkbook(workbook, app) {
    try {
        if (app.Visible)
            return
        if (IsObject(workbook))
            workbook.Close(false)
        if (app.Workbooks.Count == 0 && app.ProtectedViewWindows.Count == 0)
            app.Quit()
    }
}

ExcelCellToWrite(wbPath, sheetIdentifier, row, col, value, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Cell", row, col, value, item)
    try {
        lock := ExcelWorkbookLock(wbPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, true, &xlApp, &closeBackground, &xlWorkbook)
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Cell", row, col, value, item)
    MsgBox GetLang("写入失败：") failure.Message
    return false
}

ExcelRowToWrite(wbPath, sheetIdentifier, row, col, value, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Row", row, col, value, item)
    try {
        lock := ExcelWorkbookLock(wbPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, true, &xlApp, &closeBackground, &xlWorkbook)
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        loop {
            CurRow := row + A_Index - 1
            if (sheet.Cells(CurRow, col).Value2 == "") {
                row := CurRow
                break
            }
        }
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Row", row, col, value, item)
    MsgBox GetLang("写入失败：") failure.Message
    return false
}

ExcelColToWrite(wbPath, sheetIdentifier, row, col,  value, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Column", row, col, value, item)
    try {
        lock := ExcelWorkbookLock(wbPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, true, &xlApp, &closeBackground, &xlWorkbook)
        if (IsInteger(sheetIdentifier))
            sheetIdentifier := Integer(sheetIdentifier)
        sheet := xlWorkbook.Sheets(sheetIdentifier)
        loop {
            CurCol := col + A_Index - 1
            if (sheet.Cells(row, CurCol).Value2 == "") {
                col := CurCol
                break
            }
        }
        sheet.Cells(row, col).Value := value
        xlWorkbook.Save()
        return true
    }
    catch as e {
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllWrite(wbPath, sheetIdentifier, "Column", row, col, value, item)
    MsgBox GetLang("写入失败：") failure.Message
    return false
}

ExcelRangeRowToWrite(xlPath, SheetIdentifier, Row, Col, Arr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllWrite(xlPath, SheetIdentifier, "RowRange", Row, Col, Arr, item)
    try {
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, true, &xlApp, &closeBackground, &xlWorkbook)
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
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllWrite(xlPath, SheetIdentifier, "RowRange", Row, Col, Arr, item)
    MsgBox GetLang("写入失败：") failure.Message
    return false
}

ExcelRangeColToWrite(xlPath, SheetIdentifier, Row, Col, Arr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllWrite(xlPath, SheetIdentifier, "ColumnRange", Row, Col, Arr, item)
    try {
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, true, &xlApp, &closeBackground, &xlWorkbook)
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
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllWrite(xlPath, SheetIdentifier, "ColumnRange", Row, Col, Arr, item)
    MsgBox GetLang("写入失败：") failure.Message
    return false
}

ExcelCellToRead(wbPath, sheetIdentifier, row, col, &ResValue, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllRead(wbPath, sheetIdentifier, "Cell", row, col, row, col, &ResValue, item)
    try {
        lock := ExcelWorkbookLock(wbPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, false, &xlApp, &closeBackground, &xlWorkbook)
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
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllRead(wbPath, sheetIdentifier, "Cell", row, col, row, col, &ResValue, item)
    MsgBox GetLang("读取失败：") failure.Message
    return false
}

ExcelRowToRead(xlPath, SheetIdentifier, Row, Col, &ResArr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllRead(xlPath, SheetIdentifier, "Row", Row, Col, Row, Col, &ResArr, item)
    try {
        ResArr := []
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, false, &xlApp, &closeBackground, &xlWorkbook)
        xlApp.Calculate()       ;Calculate会导致文件内容修改，不保存会提示
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        Sheet := xlWorkbook.Sheets(SheetIdentifier)

        CurCol := Col
        IsNullCount := 0
        loop Sheet.Columns.Count - CurCol + 1 {
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
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllRead(xlPath, SheetIdentifier, "Row", Row, Col, Row, Col, &ResArr, item)
    MsgBox GetLang("读取失败：") failure.Message
    return false
}

ExcelColToRead(xlPath, SheetIdentifier, Row, Col, &ResArr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllRead(xlPath, SheetIdentifier, "Column", Row, Col, Row, Col, &ResArr, item)
    try {
        ResArr := []
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, false, &xlApp, &closeBackground, &xlWorkbook)
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        Sheet := xlWorkbook.Sheets(SheetIdentifier)

        CurRow := Row
        IsNullCount := 0
        loop Sheet.Rows.Count - CurRow + 1 {
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
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllRead(xlPath, SheetIdentifier, "Column", Row, Col, Row, Col, &ResArr, item)
    MsgBox GetLang("读取失败：") failure.Message
    return false
}

; 仅当行、列都跨格时保持二维；单行或单列区域压成一维
FlattenExcelRangeIfStrip(&ResArr, Row, Col, EndRow, EndCol) {
    singleRow := EndRow == Row
    singleCol := EndCol == Col
    if (!singleRow && !singleCol)
        return
    flat := []
    for outer in ResArr {
        if (IsObject(outer)) {
            for v in outer
                flat.Push(v)
        } else
            flat.Push(outer)
    }
    ResArr := flat
}

ExcelRangeRowToRead(xlPath, SheetIdentifier, Row, Col, EndRow, EndCol, &ResArr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllRead(xlPath, SheetIdentifier, "RowRange", Row, Col, EndRow, EndCol, &ResArr, item)
    try {
        ResArr := []
        Row := Integer(Row), Col := Integer(Col), EndRow := Integer(EndRow), EndCol := Integer(EndCol)
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, false, &xlApp, &closeBackground, &xlWorkbook)
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        sheet := xlWorkbook.Sheets(SheetIdentifier)

        ; 外层按行；读完后单行/单列压成一维，行列都跨格才保留二维
        loop EndRow - Row + 1 {
            CurRow := Row + A_Index - 1
            rowArr := []
            loop EndCol - Col + 1 {
                CurCol := Col + A_Index - 1
                Cell := sheet.Cells(CurRow, CurCol)
                if Cell.MergeCells {
                    Value := Cell.MergeArea.Cells(1, 1).Text
                } else {
                    Value := Cell.Text
                }
                rowArr.Push(Value)
            }
            ResArr.Push(rowArr)
        }
        FlattenExcelRangeIfStrip(&ResArr, Row, Col, EndRow, EndCol)
        return true
    }
    catch as e {
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllRead(xlPath, SheetIdentifier, "RowRange", Row, Col, EndRow, EndCol, &ResArr, item)
    MsgBox GetLang("读取失败：") failure.Message
    return false
}

ExcelRangeColToRead(xlPath, SheetIdentifier, Row, Col, EndRow, EndCol, &ResArr, item := "") {
    if (MainSoftData.ExcelBackend != 2)
        return ExcelDllRead(xlPath, SheetIdentifier, "ColumnRange", Row, Col, EndRow, EndCol, &ResArr, item)
    try {
        ResArr := []
        Row := Integer(Row), Col := Integer(Col), EndRow := Integer(EndRow), EndCol := Integer(EndCol)
        lock := ExcelWorkbookLock(xlPath, item)
        if (!lock.handle)
            return false
        ExcelOpenWorkbook(lock.path, false, &xlApp, &closeBackground, &xlWorkbook)
        xlApp.Calculate()
        if (IsInteger(SheetIdentifier))
            SheetIdentifier := Integer(SheetIdentifier)
        sheet := xlWorkbook.Sheets(SheetIdentifier)

        ; 外层按列；读完后单行/单列压成一维，行列都跨格才保留二维
        loop EndCol - Col + 1 {
            CurCol := Col + A_Index - 1
            colArr := []
            loop EndRow - Row + 1 {
                CurRow := Row + A_Index - 1
                Cell := sheet.Cells(CurRow, CurCol)
                if Cell.MergeCells {
                    Value := Cell.MergeArea.Cells(1, 1).Text
                } else {
                    Value := Cell.Text
                }
                colArr.Push(Value)
            }
            ResArr.Push(colArr)
        }
        FlattenExcelRangeIfStrip(&ResArr, Row, Col, EndRow, EndCol)
        return true
    }
    catch as e {
        failure := e
    }
    finally {
        if (IsSet(closeBackground) && closeBackground)
            ExcelCloseBackgroundWorkbook(xlWorkbook ?? "", xlApp)
        if (IsSet(lock))
            lock.Close()
    }
    if (failure is ExcelElevationRequired)
        return ExcelDllRead(xlPath, SheetIdentifier, "ColumnRange", Row, Col, EndRow, EndCol, &ResArr, item)
    MsgBox GetLang("读取失败：") failure.Message
    return false
}
