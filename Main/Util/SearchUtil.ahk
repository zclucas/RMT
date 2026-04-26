#Requires AutoHotkey v2.0

SearchOnTrigger(tableItem, cmdStr, index) {
    paramArr := StrSplit(cmdStr, "_")
    IsSearchPro := InStr(paramArr[1], "搜索Pro")
    dataFile := IsSearchPro ? SearchProFile : SearchFile
    Data := GetMacroCMDData(paramArr[1])
    return SearchExecute(tableItem, Data, index)
}

SearchExecute(tableItem, Data, index) {
    if (Data.SearchCount == -1) {
        isLoopFound := SearchOnce(tableItem, Data, index)
        if (!isLoopFound) {
            FloatInterval := GetFloatTime(Data.SearchInterval, MySoftData.PreIntervalFloat)
            Sleep(FloatInterval)
        }
        return isLoopFound
    }
    else {
        loop Data.SearchCount {
            WaitIfPaused(tableItem, index)

            if (tableItem.KilledArr[index])
                return

            isFound := SearchOnce(tableItem, Data, index)
            if (isFound)
                return

            if (Data.SearchCount > A_Index) {
                FloatInterval := GetFloatTime(Data.SearchInterval, MySoftData.PreIntervalFloat)
                Sleep(FloatInterval)
            }
        }

        if (Data.ResultToggle) {
            MySetGlobalVariable([Data.ResultSaveName], [Data.FalseValue], false)
        }

        if (Data.FalseMacro == "")
            return
        OnTriggerMacroOnce(tableItem, Data.FalseMacro, index)
    }
}

SearchOnce(tableItem, Data, index) {
    ; 获取坐标变量
    HasX1 := TryGetTabVarValue(&X1, tableItem, index, Data.StartPosX)
    HasY1 := TryGetTabVarValue(&Y1, tableItem, index, Data.StartPosY)
    HasX2 := TryGetTabVarValue(&X2, tableItem, index, Data.EndPosX)
    HasY2 := TryGetTabVarValue(&Y2, tableItem, index, Data.EndPosY)
    if (!HasX1 || !HasX2 || !HasY1 || !HasY2)
        return

    ; 处理搜索文本变量
    Text := Data.SearchText
    TryGetTabVarValue(&Text, tableItem, index, Data.SearchText, false)

    ; 执行搜索
    ImagePath := GetReplaceVarText(tableItem, index, Data.SearchImagePath)
    if (!ValidateCmdPath(&Data, "SearchImagePath", GetLang("选择搜索图片"), "PNG Files (*.png)", tableItem, index))
        return false
    ImagePath := Data.SearchImagePath
    ResXList := [], ResYList := [], ResHwndList := []
    found := DoSearch(Data, X1, Y1, X2, Y2, Text, ImagePath, &ResX, &ResY, &ResXList, &ResYList, &ResHwndList)

    ; 处理搜索结果
    if (found) {
        return HandleSearchResult(tableItem, Data, index, ImagePath, ResXList, ResYList, ResHwndList)
    }

    return false
}

DoSearch(Data, X1, Y1, X2, Y2, Text, ImagePath, &ResX, &ResY, &ResXList, &ResYList, &ResHwndList) {
    CoordMode("Pixel", "Screen")
    ResX := 0, ResY := 0, found := false
    ResXList := [], ResYList := [], ResHwndList := []
    isWin := Data.SearchType == 4 || Data.SearchType == 5 || Data.SearchType == 6

    if (isWin) {
        hwndList := GetHwndList(Data.WinInfo)
    }

    if (Data.SearchType == 1) {     ;屏幕图片
        found := SearchImage(Data, X1, Y1, X2, Y2, ImagePath, &ResX, &ResY)
    }
    else if (Data.SearchType == 2) {    ;屏幕颜色
        found := SearchColor(Data, X1, Y1, X2, Y2, &ResX, &ResY)
    }
    else if (Data.SearchType == 3) {    ;屏幕文本
        found := SearchText(Data, X1, Y1, X2, Y2, &ResX, &ResY, Text)
    }
    else if (Data.SearchType == 4) {    ;窗口图片
        found := SearchWinImage(Data, hwndList, X1, Y1, X2, Y2, ImagePath, &ResXList, &ResYList, &ResHwndList)
    }
    else if (Data.SearchType == 5) {    ;窗口颜色
        found := SearchWinColor(Data, hwndList, X1, Y1, X2, Y2, &ResXList, &ResYList, &ResHwndList)
    }
    else if (Data.SearchType == 6) {    ;窗口文本
        found := SearchWinText(Data, hwndList, X1, Y1, X2, Y2, Text, &ResXList, &ResYList, &ResHwndList)
    }

    if (!isWin) {
        ResXList := [ResX]
        ResYList := [ResY]
    }

    return found
}

SearchImage(Data, X1, Y1, X2, Y2, ImagePath, &ResX, &ResY) {
    if (Data.SearchImageType == 1) {
        return FindScreenImage(&ResX, &ResY, ImagePath, X1, Y1, X2, Y2, Data.Similar)
    }
    else {
        Similar := Integer(-2.55 * Data.Similar + 255)
        SearchInfo := Format("*{} *w0 *h0 {}", Similar, ImagePath)
        return ImageSearch(&ResX, &ResY, X1, Y1, X2, Y2, SearchInfo)
    }
}

SearchColor(Data, X1, Y1, X2, Y2, &ResX, &ResY) {
    HasValue := TryGetVarValue(&Value, Data.SearchColor, false)
    color := HasValue ? "0X" Value : "0X" Data.SearchColor
    Similar := Integer(-2.55 * Data.Similar + 255)
    return PixelSearch(&ResX, &ResY, X1, Y1, X2, Y2, color, Similar)
}

SearchText(Data, X1, Y1, X2, Y2, &ResX, &ResY, Text) {
    return FindScreenText(&ResX, &ResY, X1, Y1, X2, Y2, Text, Data.OCRType)
}

SearchWinImage(Data, hwndList, X1, Y1, X2, Y2, ImagePath, &ResXList, &ResYList, &ResHwndList) {
    found := false
    ResXList := [], ResYList := [], ResHwndList := []
    for i, hwnd in hwndList {
        ResX := 0, ResY := 0
        isFound := FindWinImage(&ResX, &ResY, ImagePath, hwnd, X1, Y1, X2, Y2, Data.Similar)
        if (isFound) {
            found := true
            ResHwndList.Push(hwnd)
            ResXList.Push(ResX)
            ResYList.Push(ResY)
        }
    }
    return found
}

SearchWinColor(Data, hwndList, X1, Y1, X2, Y2, &ResXList, &ResYList, &ResHwndList) {
    found := false
    HasValue := TryGetVarValue(&Value, Data.SearchColor, false)
    ColorStr := HasValue ? Value : Data.SearchColor
    ResXList := [], ResYList := [], ResHwndList := []
    for i, hwnd in hwndList {
        ResX := 0, ResY := 0
        isFound := FindWinColor(&ResX, &ResY, ColorStr, hwnd, X1, Y1, X2, Y2, Data.Similar)
        if (isFound) {
            found := true
            ResHwndList.Push(hwnd)
            ResXList.Push(ResX)
            ResYList.Push(ResY)
        }
    }
    return found
}

SearchWinText(Data, hwndList, X1, Y1, X2, Y2, searchText, &ResXList, &ResYList, &ResHwndList) {
    found := false
    ResXList := [], ResYList := [], ResHwndList := []
    for i, hwnd in hwndList {
        ResX := 0, ResY := 0
        isFound := FindWinText(&ResX, &ResY, hwnd, X1, Y1, X2, Y2, searchText, Data.OCRType)
        if (isFound) {
            found := true
            ResHwndList.Push(hwnd)
            ResXList.Push(ResX)
            ResYList.Push(ResY)
        }
    }
    return found
}

HandleSearchResult(tableItem, Data, index, ImagePath, ResXList, ResYList, ResHwndList) {
    CoordMode("Mouse", "Screen")
    SendMode("Event")
    Speed := 100 - Data.Speed

    isWin := Data.SearchType == 4 || Data.SearchType == 5 || Data.SearchType == 6

    loop ResXList.Length {
        ResX := ResXList[A_Index]
        ResY := ResYList[A_Index]
        Pos := [ResX, ResY]
        hwnd := ResHwndList.Length >= A_Index ? ResHwndList[A_Index] : 0

        ; 计算图片中心点
        if (Data.SearchType == 1) {
            imageSize := GetImageSize(ImagePath)
            Pos := [ResX + imageSize[1] / 2, ResY + imageSize[2] / 2]
        }

        ; 保存结果变量
        if (Data.ResultToggle) {
            MySetGlobalVariable([Data.ResultSaveName], [Data.TrueValue], false)
        }

        ; 保存坐标变量
        if (Data.CoordToogle) {
            MySetGlobalVariable([Data.CoordXName], [Pos[1]], false)
            MySetGlobalVariable([Data.CoordYName], [Pos[2]], false)
        }

        ; 坐标浮点处理
        Pos[1] := GetFloatValue(Pos[1], MySoftData.CoordXFloat)
        Pos[2] := GetFloatValue(Pos[2], MySoftData.CoordYFloat)

        ; 执行鼠标动作
        DoMouseAction(Data, Pos, hwnd, Speed, isWin)
    }

    ; 执行成功宏
    if (Data.TrueMacro == "")
        return true

    OnTriggerMacroOnce(tableItem, Data.TrueMacro, index)
    return true
}

DoMouseAction(Data, Pos, hwnd, Speed, isWin) {
    if (Data.MouseActionType == 4) {
        SetDefaultMouseSpeed(Speed)
        Click(Format("{} {} {}"), Pos[1], Pos[2], 2)
    }
    else if (!isWin && Data.MouseActionType == 3) {
        SetDefaultMouseSpeed(Speed)
        Click(Format("{} {} {}"), Pos[1], Pos[2], Data.ClickCount)
    }
    else if (!isWin && Data.MouseActionType == 2) {
        MouseMove(Pos[1], Pos[2], Speed)
    }
    else if (isWin && Data.MouseActionType == 3) {
        lParam := (Pos[2] << 16) | (Pos[1] & 0xFFFF)
        PostMessage 0x203, 1, lParam, , "ahk_id " hwnd
        Sleep 50
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
    }
    else if (isWin && Data.MouseActionType == 2) {
        lParam := (Pos[2] << 16) | (Pos[1] & 0xFFFF)
        PostMessage 0x201, 1, lParam, , "ahk_id " hwnd
        Sleep 50
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
    }
}