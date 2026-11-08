#Requires AutoHotkey v2.0
#Include SearchAllUtil.ahk

SearchOnTrigger(tableItem, cmdStr, index) {
    cmdName := StrSplit(cmdStr, "_")[1]
    Data := GetMacroCMDData(cmdName)
    SearchDebugLog(Format("搜索命令触发 cmd={} type={} count={}", cmdStr, Data.SearchType, Data.SearchCount))
    res := SearchExecute(tableItem, Data, index)
    return (res == false && res != "") ? [cmdStr] : ""
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
        SearchType:   ObjHasOwnProp(Data, "SearchType") ? CmdEnumSearch(Data.SearchType) : "屏幕图片",
        WinInfo:      ObjHasOwnProp(Data, "WinInfo") ? Data.WinInfo : "",
        SearchColor:  ObjHasOwnProp(Data, "SearchColor") ? Data.SearchColor : "FFFFFF",
        SearchText:   ObjHasOwnProp(Data, "SearchText") ? Data.SearchText : "",
        SearchImagePath: ObjHasOwnProp(Data, "SearchImagePath") ? Data.SearchImagePath : "",
        Similar:      ObjHasOwnProp(Data, "Similar") ? Data.Similar : 90,
        MultiPointData: ObjHasOwnProp(Data, "MultiPointData") && IsObject(Data.MultiPointData) ? Data.MultiPointData : [],
        MultiPointSeedData: ObjHasOwnProp(Data, "MultiPointSeedData") && IsObject(Data.MultiPointSeedData) ? Data.MultiPointSeedData : [],
        SuperMultiPointSeedData: ObjHasOwnProp(Data, "SuperMultiPointSeedData") && IsObject(Data.SuperMultiPointSeedData) ? Data.SuperMultiPointSeedData : [],
        SuperMultiPointIgnoreData: SearchSuperMultiPointIgnoreData(Data),
        MultiPointTolerance: ObjHasOwnProp(Data, "MultiPointTolerance") ? Data.MultiPointTolerance : 8,
        SuperMultiPointTolerance: ObjHasOwnProp(Data, "SuperMultiPointTolerance") ? Data.SuperMultiPointTolerance : 8,
        MultiPointMode: ObjHasOwnProp(Data, "MultiPointMode") ? Data.MultiPointMode : "",
        OCRType:      ObjHasOwnProp(Data, "OCRType") ? Data.OCRType : 1,
        SearchImageType: ObjHasOwnProp(Data, "SearchImageType") ? Data.SearchImageType : SearchImageDefaultType(),
        ColorMatch:   SearchColorMatchOn(Data) ? 1 : 0,
        Adaptive:     ObjHasOwnProp(Data, "Adaptive") ? Data.Adaptive : 0,
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
    if (Type(Data) == "SearchAllData" || GetLangKey(RegExReplace(Data.SerialStr, "\d+$", "")) == "搜索All")
        return SearchAllExecute(tableItem, Data, index)
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
        if (isLoopFound)
            SearchTimingMarkSucceeded(tableItem, Data)
        if (!isLoopFound) {
            FloatInterval := RandomizeDurationByPercent(Data.SearchInterval, MainSoftData.PreIntervalFloat)
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
            if (isFound) {
                SearchTimingMarkSucceeded(tableItem, Data)
                return
            }

            if (Data.SearchCount > A_Index) {
                FloatInterval := RandomizeDurationByPercent(Data.SearchInterval, MainSoftData.PreIntervalFloat)
                InterruptibleSleep(tableItem, index, FloatInterval)
            }
        }

        if (Data.ResultToggle) {
            MySetGlobalVariable([Data.ResultSaveName], [Data.FalseValue], false)
        }

        if (Data.FalseMacro == "")
            return
        ; 调试步入拦截：假分支（非空）仅判定不执行体；返回 "" 阻断 Search(-1) 重插
        if (TryInterceptDebugBranch("Search", "FalseMacro", "", -1))
            return ""
        RunMacroBodyOnce(tableItem, Data.FalseMacro, index)
    }
}

SearchTimingMarkSucceeded(tableItem, Data) {
    if (!IsObject(tableItem) || !ObjHasOwnProp(tableItem, "ImageSearchTestTiming"))
        return
    timing := tableItem.ImageSearchTestTiming
    if (IsObject(timing) && timing.SerialStr == Data.SerialStr)
        timing.Succeeded := true
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
            isWin := CmdEnumSearch(target.SearchType) == "窗口图片" || CmdEnumSearch(target.SearchType) == "窗口颜色" || CmdEnumSearch(target.SearchType) == "窗口文本"
            imgPath := CmdEnumSearch(target.SearchType) == "屏幕图片" ? target.SearchImagePath : ""
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
    ; 只累计搜索Pro当前测试指令的搜索耗时，不包含间隔、鼠标动作及后续指令。
    timing := ObjHasOwnProp(tableItem, "ImageSearchTestTiming") ? tableItem.ImageSearchTestTiming : ""
    if (!IsObject(timing) || timing.SerialStr != Data.SerialStr)
        timing := ""
    if (IsObject(timing)) {
        started := 0
        DllCall("QueryPerformanceCounter", "Int64*", &started)
    }
    try {
        try {
            found := DoSearch(target, X1, Y1, X2, Y2, Text, ImagePath, &ResX, &ResY, &ResXList, &ResYList, &ResHwndList, tableItem, index)
        } finally {
            if (IsObject(timing)) {
                ended := 0
                DllCall("QueryPerformanceCounter", "Int64*", &ended)
                timing.Ticks += ended - started
                timing.Count += 1
            }
        }
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
    searchType := CmdEnumSearch(Data.SearchType)
    isWin := searchType == "窗口图片" || searchType == "窗口颜色" || searchType == "窗口文本"

    if (isWin) {
        hwndList := GetHwndList(ResolveBindWindow(tableItem, index, Data.WinInfo))   ; §22 绑定窗口替换
    }

    if (searchType == "屏幕图片") {
        found := SearchImage(Data, X1, Y1, X2, Y2, ImagePath, &ResX, &ResY)
    }
    else if (searchType == "屏幕颜色") {
        found := SearchColor(Data, X1, Y1, X2, Y2, &ResX, &ResY)
    }
    else if (searchType == "屏幕文本") {
        found := SearchText(Data, X1, Y1, X2, Y2, &ResX, &ResY, Text)
    }
    else if (searchType == "窗口图片") {
        found := SearchWinImage(Data, hwndList, X1, Y1, X2, Y2, ImagePath, &ResXList, &ResYList, &ResHwndList)
    }
    else if (searchType == "窗口颜色") {
        found := SearchWinColor(Data, hwndList, X1, Y1, X2, Y2, &ResXList, &ResYList, &ResHwndList)
    }
    else if (searchType == "窗口文本") {
        found := SearchWinText(Data, hwndList, X1, Y1, X2, Y2, Text, &ResXList, &ResYList, &ResHwndList)
    }

    if (!isWin) {
        ResXList := [ResX]
        ResYList := [ResY]
    }

    return found
}

; 设置中的全局图片识别自适应开关（跨分辨率找图）
SearchMultiPointOn(Data) {
    if (SearchMatchMode(Data) != "multi")
        return false
    return ObjHasOwnProp(Data, "MultiPointData") && IsObject(Data.MultiPointData)
        && Data.MultiPointData.Length >= 1
}

SearchSuperMultiPointSeedData(Data) {
    if (ObjHasOwnProp(Data, "SuperMultiPointSeedData") && IsObject(Data.SuperMultiPointSeedData))
        return Data.SuperMultiPointSeedData
    return []
}

SearchSuperMultiPointIgnoreData(Data) {
    return ObjHasOwnProp(Data, "SuperMultiPointIgnoreData")
        ? String(Data.SuperMultiPointIgnoreData) : ""
}

SearchMultiPointSuperOn(Data) {
    return SearchMatchMode(Data) == "super"
        && SearchSuperMultiPointSeedData(Data).Length >= 1
}

SearchMatchMode(Data) {
    points := ObjHasOwnProp(Data, "MultiPointData") && IsObject(Data.MultiPointData)
        ? Data.MultiPointData : []
    superSeeds := SearchSuperMultiPointSeedData(Data)
    mode := ObjHasOwnProp(Data, "MultiPointMode") ? Data.MultiPointMode : ""
    if (mode == "super")
        return superSeeds.Length > 0 ? "super" : ""
    if (mode == "multi")
        return points.Length > 0 ? "multi" : ""
    return ""
}

BuildMultiPointText(points) {
    if (!IsObject(points) || points.Length < 1)
        return ""
    text := ""
    for point in points {
        if (!IsObject(point) || !ObjHasOwnProp(point, "X") || !ObjHasOwnProp(point, "Y")
            || !ObjHasOwnProp(point, "Color"))
            return ""
        color := StrUpper(RegExReplace(String(point.Color), "^#|^0[xX]"))
        if (!RegExMatch(color, "^[0-9A-F]{6}$") || !IsNumber(point.X) || !IsNumber(point.Y))
            return ""
        text .= (text == "" ? "" : ";") Integer(point.X) "," Integer(point.Y) "," color
    }
    return text
}

BuildMultiPointSeedText(points) {
    if (!IsObject(points) || points.Length < 1)
        return ""
    text := ""
    for point in points {
        if (!IsObject(point) || !ObjHasOwnProp(point, "X") || !ObjHasOwnProp(point, "Y")
            || !ObjHasOwnProp(point, "Color"))
            return ""
        color := StrUpper(RegExReplace(String(point.Color), "^#|^0[xX]"))
        if (!RegExMatch(color, "^[0-9A-F]{6}$") || !IsNumber(point.X) || !IsNumber(point.Y))
            return ""
        text .= (text == "" ? "" : ";") Integer(point.X) "," Integer(point.Y) "," color
    }
    return text
}
SearchColorMatchOn(Data) {
    return ObjHasOwnProp(Data, "ColorMatch") && (Data.ColorMatch == 1 || Data.ColorMatch == "true")
}

SearchAdaptiveOn(Data) {
    ; 所有搜索目标统一使用全局设置，忽略旧指令中的 Adaptive 字段。
    if (!IsSet(MainSoftData) || !MainSoftData.HasProp("SearchImageAdaptive"))
        return false
    v := MainSoftData.SearchImageAdaptive
    if (IsNumber(v))
        return Integer(v) != 0
    return (v == true || v == "true" || v == 1)
}

SearchImage(Data, X1, Y1, X2, Y2, ImagePath, &ResX, &ResY) {
    if (SearchMultiPointSuperOn(Data)) {
        if (!MultiPointSuperApiReady()) {
            SearchDebugLog("超多点匹配不可用：OpenCV 插件不支持超多点接口")
            return false
        }
        seeds := BuildMultiPointSeedText(SearchSuperMultiPointSeedData(Data))
        tolerance := ObjHasOwnProp(Data, "SuperMultiPointTolerance")
            ? Data.SuperMultiPointTolerance : 8
        ignoreData := SearchSuperMultiPointIgnoreData(Data)
        ret := seeds != "" ? FindScreenImageMultiPointSuper(&ResX, &ResY, ImagePath, X1, Y1, X2, Y2
            , Data.Similar, seeds, tolerance, ignoreData) : -4
        if (ret != 1)
            SearchDebugLog(Format("超多点匹配未命中 区域=({},{})-({},{}) 基准点数={} 返回={} 详情={}"
                , X1, Y1, X2, Y2, SearchSuperMultiPointSeedData(Data).Length, ret, GetImageLastErrorText()))
        return ret == 1
    }
    if (SearchMultiPointOn(Data)) {
        if (!MultiPointApiReady()) {
            SearchDebugLog("多点找图不可用：OpenCV 插件不支持多点接口")
            return false
        }
        points := BuildMultiPointText(Data.MultiPointData)
        ret := points != "" ? FindScreenImageMultiPoint(&ResX, &ResY, ImagePath, X1, Y1, X2, Y2
            , Data.Similar, points, Data.MultiPointTolerance) : -4
        if (ret != 1)
            SearchDebugLog(Format("多点找图未命中 区域=({},{})-({},{}) 点数={} 返回={} 详情={}"
                , X1, Y1, X2, Y2, Data.MultiPointData.Length, ret, GetImageLastErrorText()))
        return ret == 1
    }

    if (SearchImageDefaultType() == 1) {
        ocvReason := OpenCvEnsure()
        if (ocvReason != "") {
            ; 失败原因已由 OpenCvEnsure 写进日志；启动时的界面提示在主进程 InitNativePlugins 里做
            SearchDebugLog(Format("找图失败：OpenCV 不可用（{}）", ocvReason), "opencv")
            return false
        }
        return FindScreenImage(&ResX, &ResY, ImagePath, X1, Y1, X2, Y2, Data.Similar, SearchAdaptiveOn(Data), SearchColorMatchOn(Data))
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
    useSuper := SearchMultiPointSuperOn(Data)
    useMultiPoint := useSuper || SearchMultiPointOn(Data)
    if (useSuper && !MultiPointSuperApiReady()) {
        SearchDebugLog("超多点匹配不可用：OpenCV 插件不支持超多点接口")
        return false
    }
    if (useMultiPoint && !useSuper && !MultiPointApiReady()) {
        SearchDebugLog("多点找图不可用：OpenCV 插件不支持多点接口")
        return false
    }
    superSeeds := useSuper ? SearchSuperMultiPointSeedData(Data) : []
    multiPointText := useSuper ? BuildMultiPointSeedText(superSeeds)
        : (useMultiPoint ? BuildMultiPointText(Data.MultiPointData) : "")
    superIgnoreData := useSuper ? SearchSuperMultiPointIgnoreData(Data) : ""

    found := false
    ResXList := [], ResYList := [], ResHwndList := []
    for i, hwnd in hwndList {
        ResX := 0, ResY := 0
        if (useSuper)
            isFound := multiPointText != "" ? FindWinImageMultiPointSuper(&ResX, &ResY, ImagePath, hwnd
                , X1, Y1, X2, Y2, Data.Similar, multiPointText
                , ObjHasOwnProp(Data, "SuperMultiPointTolerance") ? Data.SuperMultiPointTolerance : 8
                , superIgnoreData) : false
        else if (useMultiPoint)
            isFound := multiPointText != "" ? FindWinImageMultiPoint(&ResX, &ResY, ImagePath, hwnd
                , X1, Y1, X2, Y2, Data.Similar, multiPointText, Data.MultiPointTolerance) : false
        else
            isFound := FindWinImage(&ResX, &ResY, ImagePath, hwnd, X1, Y1, X2, Y2, Data.Similar, SearchAdaptiveOn(Data), SearchColorMatchOn(Data))
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
        WaitIfPaused(tableItem, index)
        if (tableItem.Items[index].Killed)
            return ""
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
        Pos[1] := RandomizeValueByOffset(Pos[1], MainSoftData.CoordXFloat)
        Pos[2] := RandomizeValueByOffset(Pos[2], MainSoftData.CoordYFloat)

        ; 执行鼠标动作
        DoMouseAction(tableItem, Data, index, Pos, hwnd, Speed, isWin)
    }

    ; 执行成功宏
    if (Data.TrueMacro == "")
        return true

    ; 调试步入拦截：真分支（非空）仅判定不执行体；返回 true 伪装「已找到」阻断 Search(-1) 重插
    if (TryInterceptDebugBranch("Search", "TrueMacro", "", -1))
        return true
    RunMacroBodyOnce(tableItem, Data.TrueMacro, index)
    return true
}

DoMouseAction(tableItem, Data, index, Pos, hwnd, Speed, isWin) {
    keyMode := GetMacroKeyMode(tableItem, index)

    mouseAct := CmdEnumMouseAct(Data.MouseActionType)
    if (!isWin && (mouseAct == "移动至目标" || mouseAct == "移动至目标点击1次" || mouseAct == "移动至目标点击2次")) {
        SearchMouseActionByStrategy(keyMode, mouseAct, Pos[1], Pos[2], Speed, Data.ClickCount)
        return
    }

    if (isWin && mouseAct == "移动至目标点击2次") {
        ; 窗口后台双击：down / up / dblclk / up，缺 WM_LBUTTONDBLCLK 只会被当成两次单击
        lParam := (Pos[2] << 16) | (Pos[1] & 0xFFFF)
        PostMessage 0x201, 1, lParam, , "ahk_id " hwnd
        Sleep 20
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
        Sleep 40
        PostMessage 0x203, 1, lParam, , "ahk_id " hwnd
        Sleep 20
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
    }
    else if (isWin && mouseAct == "移动至目标点击1次") {
        lParam := (Pos[2] << 16) | (Pos[1] & 0xFFFF)
        PostMessage 0x203, 1, lParam, , "ahk_id " hwnd
        Sleep 50
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
    }
    else if (isWin && mouseAct == "移动至目标") {
        lParam := (Pos[2] << 16) | (Pos[1] & 0xFFFF)
        PostMessage 0x201, 1, lParam, , "ahk_id " hwnd
        Sleep 50
        PostMessage 0x202, 0, lParam, , "ahk_id " hwnd
    }
}
