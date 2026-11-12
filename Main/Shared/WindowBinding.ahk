; 窗口绑定引用在运行时沿 指令 → 宏设置 → 所属模块 解析，不复制父级值。
; 「{绑定窗口}」保留为旧版宏设置引用的别名。
ResolveBindWindow(tableItem, index, winInfoStr) {
    isMacro := winInfoStr == "{宏设置窗口绑定}" || winInfoStr == "{绑定窗口}" || winInfoStr == GetLang("{绑定窗口}")
    if (!isMacro && winInfoStr != "{模块窗口绑定}")
        return winInfoStr
    if (IsObject(tableItem) && tableItem.HasOwnProp("EditorWindowBindingContext"))
        return ResolveEditorBindWindow(tableItem.EditorWindowBindingContext, winInfoStr)
    if (!IsObject(tableItem) || !tableItem.Items.Has(index))
        return ""
    item := tableItem.Items[index]
    if (isMacro) {
        winInfoStr := item.HasOwnProp("BindWindow") ? item.BindWindow : ""
        if (winInfoStr == "" || winInfoStr == "{所有窗口}")
            return ""
        if (winInfoStr != "{模块窗口绑定}") {
            ; 禁止自身引用；旧占位符仍兼容，但不作为窗口标题匹配。
            if (winInfoStr == "{宏设置窗口绑定}" || winInfoStr == "{绑定窗口}" || winInfoStr == GetLang("{绑定窗口}"))
                return ""
            return winInfoStr
        }
    }
    return GetItemModuleWindowBinding(tableItem, index)
}

ResolveEditorBindWindow(context, winInfo) {
    macro := IsObject(context) ? ResolveMacroItem(context.TableID, context.ItemID) : ""
    return ResolveBindWindow(macro ? macro.Table : "", macro ? macro.Index : 0, winInfo)
}

IsMouseWindowBinding(infoStr) {
    return infoStr == "❖{句柄ID}" || infoStr == "❖{" GetLang("句柄ID") "}"
}

WindowBindingMouseActive(*) {
    MouseGetPos , , &hwnd
    return hwnd != 0 && WinActive("ahk_id " hwnd)
}

GetHwndList(infoStr) {
    HwndList := []
    if (infoStr == "")
        return HwndList

    if (IsMouseWindowBinding(infoStr)) {
        MouseGetPos , , &hwnd
        if (hwnd)
            HwndList.Push(hwnd)
        return HwndList
    }

    if (InStr(infoStr, "❖")) {
        infoStr := StrReplace(infoStr, "❖")
        hwndIdStrList := StrSplit(infoStr, "|")
        for index, hwndIdStr in hwndIdStrList {
            if (SubStr(hwndIdStr, 1, 1) = "{" && SubStr(hwndIdStr, -1) = "}")
                hwndIdStr := SubStr(hwndIdStr, 2, -1)

            hasValue := TryGetVarValue(&hwnd, hwndIdStr)
            if (hasValue)
                HwndList.Push(hwnd)
        }
        return HwndList
    }

    paramStr := GetParamsWinInfoStr(infoStr)
    if (paramStr == "")
        return HwndList

    HwndList := WinGetList(paramStr)

    loop HwndList.Length {
        index := HwndList.Length - A_Index + 1
        if (HwndList[index] == 0)
            HwndList.RemoveAt(index)
    }

    return HwndList
}

GetParamsWinInfoStr(infoStr) {
    if (infoStr == "")
        return ""

    if (InStr(infoStr, "❖")) {
        infoStr := StrReplace(infoStr, "❖")
        if (infoStr == "")
            return ""
        static groupCache := Map()
        if (!groupCache.Has(infoStr)) {
            ; 窗口组名称只允许字母、数字和下划线，不能直接包含句柄分隔符 |。
            groupName := "UIGroup_" (groupCache.Count + 1)
            hwndList := StrSplit(infoStr, "|")
            for hwnd in hwndList {
                if (!RegExMatch(Trim(hwnd), "i)^(?:0x[0-9a-f]+|[0-9]+)$") || Integer(Trim(hwnd)) == 0)
                    return ""
            }
            for index, hwnd in hwndList {
                GroupAdd(groupName, "ahk_id " Trim(hwnd))
            }
            groupCache[infoStr] := groupName
        }
        ResStr := "ahk_group " groupCache[infoStr]
        return ResStr
    }

    infoArr := StrSplit(infoStr, "⎖")
    if (infoArr.Length != 3)
        return ""

    title := infoArr[1]
    className := infoArr[2]
    process := infoArr[3]

    ; 构建条件字符串
    condition := ""

    ; 添加标题（如果非空）
    if (title != "")
        condition .= title

    ; 添加窗口类（如果非空）
    if (className != "") {
        if (condition != "")
            condition .= " "
        condition .= "ahk_class " className
    }

    ; 添加进程名（如果非空）
    if (process != "") {
        if (condition != "")
            condition .= " "
        condition .= "ahk_exe " process
    }

    return condition
}

GetProcessName() {
    MouseGetPos &mouseX, &mouseY, &winId
    name := ""
    try {
        WinPID := WinGetPID("ahk_id " winId)
        name := ProcessGetName(WinPID)
    }
    catch {
        name := ""
    }
    return name
}

; 获取窗口在活动显示器上居中的坐标
GetCenterPosOnActiveMonitor(winWidth, winHeight) {
    MouseGetPos(&mouseX, &mouseY)
    monCount := MonitorGetCount()
    Loop monCount {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (mouseX >= mL && mouseX < mR && mouseY >= mT && mouseY < mB) {
            MonitorGetWorkArea(A_Index, &waL, &waT, &waR, &waB)
            x := Floor((waL + waR - winWidth) / 2)
            y := Floor((waT + waB - winHeight) / 2)
            return {x: x, y: y}
        }
    }
    ; 默认主显示器
    MonitorGetWorkArea(1, &waL, &waT, &waR, &waB)
    x := Floor((waL + waR - winWidth) / 2)
    y := Floor((waT + waB - winHeight) / 2)
    return {x: x, y: y}
}
