#Requires AutoHotkey v2.0

; One instruction produces an actual nested array for the existing array/loop commands.
SearchAllExecute(tableItem, Data, index) {
    MySetGlobalArray(Data.AllSaveName, [])
    attempts := Data.SearchCount == -1 ? 1 : Max(1, Integer(Data.SearchCount))
    loop attempts {
        WaitIfPaused(tableItem, index)
        if (tableItem.Items[index].Killed)
            return ""
        coordinates := SearchAllOnce(tableItem, Data, index)
        if (tableItem.Items[index].Killed)
            return ""
        MySetGlobalArray(Data.AllSaveName, coordinates)
        if (coordinates.Length) {
            WaitIfPaused(tableItem, index)
            if (tableItem.Items[index].Killed)
                return ""
            if (Data.ResultToggle)
                MySetGlobalVariable([Data.ResultSaveName], [Data.TrueValue], false)
            ; 兼容旧配置中的单点坐标变量。
            if (Data.CoordToogle) {
                last := coordinates[coordinates.Length]
                MySetGlobalVariable([Data.CoordXName], [last[1]], false)
                MySetGlobalVariable([Data.CoordYName], [last[2]], false)
            }
            if (Data.TrueMacro != "" && !TryInterceptDebugBranch("Search", "TrueMacro", "", -1))
                RunMacroBodyOnce(tableItem, Data.TrueMacro, index)
            return true
        }
        if (A_Index < attempts || Data.SearchCount == -1)
            InterruptibleSleep(tableItem, index, RandomizeDurationByPercent(Data.SearchInterval, MainSoftData.PreIntervalFloat))
    }
    if (Data.SearchCount == -1)
        return false
    if (Data.ResultToggle)
        MySetGlobalVariable([Data.ResultSaveName], [Data.FalseValue], false)
    if (Data.FalseMacro != "" && !TryInterceptDebugBranch("Search", "FalseMacro", "", -1))
        RunMacroBodyOnce(tableItem, Data.FalseMacro, index)
    return ""
}

SearchAllOnce(tableItem, Data, index) {
    if (!TryGetTabVarValue(&x1, tableItem, index, Data.StartPosX)
        || !TryGetTabVarValue(&y1, tableItem, index, Data.StartPosY)
        || !TryGetTabVarValue(&x2, tableItem, index, Data.EndPosX)
        || !TryGetTabVarValue(&y2, tableItem, index, Data.EndPosY))
        throw Error("搜索All：无法解析搜索范围")
    if (x2 <= x1 || y2 <= y1)
        throw Error("搜索All：搜索范围必须大于零")
    kind := CmdEnumSearch(Data.SearchType)
    isWin := InStr(kind, "窗口") == 1
    hwnds := isWin ? GetHwndList(ResolveBindWindow(tableItem, index, Data.WinInfo)) : [0]
    allPoints := []
    for hwnd in hwnds {
        WaitIfPaused(tableItem, index)
        if (tableItem.Items[index].Killed)
            return []
        points := SearchAllInRegion(tableItem, Data, index, x1, y1, x2, y2, kind, hwnd)
        for point in points
            allPoints.Push(point)
    }
    return SearchAllSort(allPoints, Data.AllSort)
}

SearchAllInRegion(tableItem, Data, index, x1, y1, x2, y2, kind, hwnd) {
    if (kind == "屏幕文本" || kind == "窗口文本") {
        text := Data.SearchText
        TryGetTabVarValue(&text, tableItem, index, Data.SearchText, false)
        if (text == "")
            throw Error("搜索All：搜索文本不能为空")
        result := hwnd ? GetWinTextObjArr(hwnd, x1, y1, x2, y2, Data.OCRType) : GetScreenTextObjArr(x1, y1, x2, y2, Data.OCRType)
        points := SearchAllTextPoints(result, text, x1, y1)
    } else if (kind == "屏幕图片" || kind == "屏幕颜色" || kind == "窗口图片" || kind == "窗口颜色") {
        if (OpenCvEnsure() != "")
            throw Error("搜索All：OpenCV 插件不可用")
        if (DllCall("RMT_OpenCV.dll\GetApiVersion", "Cdecl Int") < 13)
            throw Error("搜索All：请更新 OpenCV 插件并重启软件")
        isColor := InStr(kind, "颜色") != 0
        path := !isColor ? ResolveSearchImagePath(tableItem, index, Data.SearchImagePath) : ""
        color := 0
        if (isColor) {
            value := ResolveSearchColorHex(Data.SearchColor, tableItem, index)
            if (!RegExMatch(value, "i)^[0-9a-f]{6}$"))
                throw Error("搜索All：颜色应为六位十六进制值")
            color := Integer("0x" value)
        }
        handle := DllCall("RMT_OpenCV.dll\SearchAllCapture", "Str", path, "Int", x1, "Int", y1,
            "Int", x2 - x1, "Int", y2 - y1, "Int", Data.Similar,
            "Int", SearchColorMatchOn(Data), "Int", SearchAdaptiveOn(Data),
            "Int", isColor, "UInt", color, "Int", hwnd, "Cdecl Ptr")
        if (!handle)
            throw Error("搜索All：截图或图片匹配失败，请检查图片及搜索范围")
        points := []
        try {
            count := DllCall("RMT_OpenCV.dll\SearchAllCount", "Ptr", handle, "Cdecl Int")
            buffer := DllCall("RMT_OpenCV.dll\SearchAllPoints", "Ptr", handle, "Cdecl Ptr")
            loop count {
                if (Mod(A_Index, 4096) == 0) {
                    WaitIfPaused(tableItem, index)
                    if (tableItem.Items[index].Killed)
                        return []
                }
                points.Push([NumGet(buffer, (A_Index - 1) * 8, "Int"), NumGet(buffer, (A_Index - 1) * 8 + 4, "Int")])
            }
        } finally DllCall("RMT_OpenCV.dll\SearchAllRelease", "Ptr", handle, "Cdecl")
    } else
        throw Error("搜索All：不支持的搜索类型")
    return points
}

SearchAllTextPoints(result, pattern, x1, y1) {
    points := []
    if (!IsObject(result))
        return points
    ; OCR can put several occurrences in one line; enumerate matches inside each box.
    for value in result {
        start := 1
        while (start <= StrLen(value.text) + 1 && RegExMatch(value.text, pattern, &match, start)) {
            if (match.Len > 0) {
                xs := [], ys := []
                for p in value.boxPoint {
                    xs.Push(p.x)
                    ys.Push(p.y)
                }
                fraction := (match.Pos - 1 + match.Len / 2) / StrLen(value.text)
                points.Push([Round(x1 + Min(xs*) + fraction * (Max(xs*) - Min(xs*))), Round(y1 + (Min(ys*) + Max(ys*)) / 2)])
            }
            start := match.Pos + Max(1, match.Len)
        }
    }
    return points
}

; Bottom-up merge sort avoids quadratic work for large color result sets.
SearchAllSort(points, order) {
    if (points.Length < 2 || order == "不排序")
        return points
    axis := order == "上下优先" || order == "从左到右" ? 1 : 2
    other := 3 - axis
    primaryDirection := order == "下上左右" || order == "下上右左" ? -1 : 1
    secondaryDirection := order == "上下右左" || order == "下上右左" ? -1 : 1
    width := 1
    while (width < points.Length) {
        merged := [], start := 1
        while (start <= points.Length) {
            left := start, mid := Min(start + width, points.Length + 1)
            right := mid, finish := Min(start + width * 2, points.Length + 1)
            while (left < mid || right < finish) {
                takeLeft := right >= finish
                if (!takeLeft && left < mid) {
                    primary := points[left][axis] - points[right][axis]
                    secondary := points[left][other] - points[right][other]
                    takeLeft := primary * primaryDirection < 0 || (primary == 0 && secondary * secondaryDirection <= 0)
                }
                merged.Push(points[takeLeft ? left++ : right++])
            }
            start := finish
        }
        points := merged, width *= 2
    }
    return points
}
