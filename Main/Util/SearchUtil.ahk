#Requires AutoHotkey v2.0

SearchOnTrigger(tableItem, cmdStr, index) {
    paramArr := StrSplit(cmdStr, "_")
    IsSearchPro := InStr(paramArr[1], "搜索Pro")
    dataFile := IsSearchPro ? SearchProFile : SearchFile
    Data := GetMacroCMDData(paramArr[1])
    SearchDebugLog(Format("搜索命令触发 cmd={} type={} count={}", cmdStr, Data.SearchType, Data.SearchCount))
    return SearchExecute(tableItem, Data, index)
}

; 搜索图片路径解析：存在同名用户变量 → 用变量值；否则把配置文本当作路径
ResolveSearchImagePath(tableItem, index, pathText) {
    pathText := Trim(String(pathText))
    if (pathText == "")
        return ""

    resolved := ""
    if (TryGetUserDefinedVarValue(&resolved, tableItem, index, pathText))
        return Trim(String(resolved))
    return pathText
}

; 仅查用户定义变量（局部/全局），不含数字、内置变量等特殊解析
TryGetUserDefinedVarValue(&Value, tableItem, index, varName) {
    varName := Trim(String(varName))
    if (varName == "")
        return false
    if (IsObject(tableItem) && tableItem.Items.Has(index)) {
        item := tableItem.Items[index]
        if (item && item.VariableMap.Has(varName)) {
            Value := item.VariableMap[varName]
            return true
        }
    }
    if (MySoftData.VariableMap.Has(varName)) {
        Value := MySoftData.VariableMap[varName]
        return true
    }
    return false
}

; §15.1 兼容取目标数组：旧配置无 SearchTargetArr（或为空）时，由顶层单目标字段构造
GetSearchTargetArr(Data) {
    if (ObjHasOwnProp(Data, "SearchTargetArr") && IsObject(Data.SearchTargetArr) && Data.SearchTargetArr.Length > 0)
        return Data.SearchTargetArr
    t := {
        SearchType:   ObjHasOwnProp(Data, "SearchType") ? Data.SearchType : 1,
        WinInfo:      ObjHasOwnProp(Data, "WinInfo") ? Data.WinInfo : "",
        SearchColor:  ObjHasOwnProp(Data, "SearchColor") ? Data.SearchColor : "FFFFFF",
        SearchText:   ObjHasOwnProp(Data, "SearchText") ? Data.SearchText : "",
        SearchImagePath: ObjHasOwnProp(Data, "SearchImagePath") ? Data.SearchImagePath : "",
        Similar:      ObjHasOwnProp(Data, "Similar") ? Data.Similar : 90,
        OCRType:      ObjHasOwnProp(Data, "OCRType") ? Data.OCRType : 1,
        SearchImageType: ObjHasOwnProp(Data, "SearchImageType") ? Data.SearchImageType : 1,
        StartPosX:    ObjHasOwnProp(Data, "StartPosX") ? Data.StartPosX : 0,
        StartPosY:    ObjHasOwnProp(Data, "StartPosY") ? Data.StartPosY : 0,
        EndPosX:      ObjHasOwnProp(Data, "EndPosX") ? Data.EndPosX : A_ScreenWidth,
        EndPosY:      ObjHasOwnProp(Data, "EndPosY") ? Data.EndPosY : A_ScreenHeight
    }
    return [t]
}

; 满足个数归一：-1/非法 → 所有目标
GetSatisfyCount(Data, targets) {
    n := ObjHasOwnProp(Data, "SatisfyCount") ? Data.SatisfyCount : -1
    if (!IsNumber(n) || Integer(n) < 1)
        return targets.Length
    return Min(Integer(n), targets.Length)
}

SearchExecute(tableItem, Data, index) {
    targets := GetSearchTargetArr(Data)
    satisfyCount := GetSatisfyCount(Data, targets)

    if (Data.SearchCount == -1) {
        WaitIfPaused(tableItem, index)
        item := tableItem.Items[index]
        if (item && item.Killed)
            return
        isLoopFound := SearchRoundOnce(tableItem, Data, index, targets, satisfyCount)
        if (item && item.Killed)
            return
        if (!isLoopFound) {
            FloatInterval := GetFloatTime(Data.SearchInterval, MainSoftData.PreIntervalFloat)
            InterruptibleSleep(tableItem, index, FloatInterval)
        }
        return isLoopFound
    }
    else {
        loop Data.SearchCount {
            WaitIfPaused(tableItem, index)

            item := tableItem.Items[index]
            if (item && item.Killed)
                return

            isFound := SearchRoundOnce(tableItem, Data, index, targets, satisfyCount)
            if (isFound)
                return

            if (Data.SearchCount > A_Index) {
                FloatInterval := GetFloatTime(Data.SearchInterval, MainSoftData.PreIntervalFloat)
                InterruptibleSleep(tableItem, index, FloatInterval)
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

; §15.1 一轮搜索：遍历所有目标，统计满足个数；满足时执行动作（含 TrueMacro 一次）并返回 true
SearchRoundOnce(tableItem, Data, index, targets, satisfyCount) {
    foundCount := 0
    allResX := [], allResY := [], allResHwnd := [], allImagePath := [], allIsWin := []
    for ti, target in targets {
        ResXList := [], ResYList := [], ResHwndList := []
        found := SearchOnceTarget(tableItem, Data, target, index, &ResXList, &ResYList, &ResHwndList)
        if (found) {
            foundCount++
            isWin := target.SearchType == 4 || target.SearchType == 5 || target.SearchType == 6
            imgPath := target.SearchType == 1 ? target.SearchImagePath : ""
            for j, rx in ResXList {
                allResX.Push(rx)
                allResY.Push(ResYList[j])
                allResHwnd.Push(ResHwndList.Length >= j ? ResHwndList[j] : 0)
                allImagePath.Push(imgPath)
                allIsWin.Push(isWin)
            }
        }
        if (foundCount >= satisfyCount)
            break
    }

    if (foundCount < satisfyCount) {
        SearchDebugLog(Format("搜索轮次未满足 found={} need={} targets={}", foundCount, satisfyCount, targets.Length))
        return false
    }

    SearchDebugLog(Format("搜索轮次满足 found={} need={} positions={}", foundCount, satisfyCount, allResX.Length))
    ApplySearchActions(tableItem, Data, index, allResX, allResY, allResHwnd, allImagePath, allIsWin)
    return true
}

; 单目标搜索（§15.1 拆分：只搜索收集，不执行动作/TrueMacro）
SearchOnceTarget(tableItem, Data, target, index, &ResXList, &ResYList, &ResHwndList) {
    ; 获取坐标变量（目标各自独立）
    HasX1 := TryGetTabVarValue(&X1, tableItem, index, target.StartPosX)
    HasY1 := TryGetTabVarValue(&Y1, tableItem, index, target.StartPosY)
    HasX2 := TryGetTabVarValue(&X2, tableItem, index, target.EndPosX)
    HasY2 := TryGetTabVarValue(&Y2, tableItem, index, target.EndPosY)
    if (!HasX1 || !HasX2 || !HasY1 || !HasY2) {
        SearchDebugLog(Format("搜索坐标解析失败 startX={} startY={} endX={} endY={}"
            , target.StartPosX, target.StartPosY, target.EndPosX, target.EndPosY))
        return
    }

    ; 处理搜索文本变量
    Text := target.SearchText
    TryGetTabVarValue(&Text, tableItem, index, target.SearchText, false)

    ; 图片路径：若存在同名用户变量则用变量值，否则按文本路径使用（不做 {var} 优先替换，也不强制 FileExist）
    ImagePath := ResolveSearchImagePath(tableItem, index, target.SearchImagePath)
    SearchDebugLog(Format("搜索单次 type={} 范围=({},{})-({},{}) 图片={} 文本={}"
        , target.SearchType, X1, Y1, X2, Y2, ImagePath, Text))

    ResX := 0, ResY := 0
    ResXList := [], ResYList := [], ResHwndList := []
    try {
        found := DoSearch(target, X1, Y1, X2, Y2, Text, ImagePath, &ResX, &ResY, &ResXList, &ResYList, &ResHwndList, tableItem, index)
    } catch as e {
        SearchDebugLog(Format("搜索异常 Message={} Extra={} What={} File={} Line={}"
            , e.Message, e.Extra, e.What, e.File, e.Line))
        return false
    }

    SearchDebugLog(Format("搜索单次结果 found={} positions={}", found, ResXList.Length))
    return found
}

DoSearch(Data, X1, Y1, X2, Y2, Text, ImagePath, &ResX, &ResY, &ResXList, &ResYList, &ResHwndList, tableItem := "", index := 0) {
    CoordMode("Pixel", "Screen")
    ResX := 0, ResY := 0, found := false
    ResXList := [], ResYList := [], ResHwndList := []
    isWin := Data.SearchType == 4 || Data.SearchType == 5 || Data.SearchType == 6

    if (isWin) {
        hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.WinInfo))   ; §22 绑定窗口替换
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
        ocvReason := OpenCvEnsure()
        if (ocvReason != "") {
            ShowOpenCvInstallPrompt(ocvReason)
            return false
        }
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

; §15.1 整体满足后的动作：对所有找到位置执行鼠标动作 + 结果/坐标变量，TrueMacro 只执行一次
ApplySearchActions(tableItem, Data, index, ResXList, ResYList, ResHwndList, ImagePathList, IsWinList) {
    CoordMode("Mouse", "Screen")
    SendMode("Event")
    ; 界面速度 0~100（越大越快），由 MouseMoveUtil 按按键类型换算
    Speed := Data.Speed

    loop ResXList.Length {
        ResX := ResXList[A_Index]
        ResY := ResYList[A_Index]
        Pos := [ResX, ResY]
        hwnd := ResHwndList.Length >= A_Index ? ResHwndList[A_Index] : 0
        isWin := IsWinList.Length >= A_Index ? IsWinList[A_Index] : false

        ; 计算图片中心点（屏幕图片搜索）
        if (ImagePathList.Length >= A_Index && ImagePathList[A_Index] != "") {
            imageSize := GetImageSize(ImagePathList[A_Index])
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
        Pos[1] := GetFloatValue(Pos[1], MainSoftData.CoordXFloat)
        Pos[2] := GetFloatValue(Pos[2], MainSoftData.CoordYFloat)

        ; 执行鼠标动作
        DoMouseAction(tableItem, Data, index, Pos, hwnd, Speed, isWin)
    }

    ; 执行成功宏
    if (Data.TrueMacro == "")
        return true

    OnTriggerMacroOnce(tableItem, Data.TrueMacro, index)
    return true
}

DoMouseAction(tableItem, Data, index, Pos, hwnd, Speed, isWin) {
    keyMode := GetMacroKeyMode(tableItem, index)

    if (!isWin && (Data.MouseActionType == 2 || Data.MouseActionType == 3 || Data.MouseActionType == 4)) {
        SearchMouseActionByStrategy(keyMode, Data.MouseActionType, Pos[1], Pos[2], Speed, Data.ClickCount)
        return
    }

    if (isWin && Data.MouseActionType == 3) {
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
