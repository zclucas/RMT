GetRandomStr(length) {
    result := Random(1, 9)
    loop length {
        if (A_Index + 1 > length)
            break

        result .= Random(0, 9)
    }
    return result
}

WaitIfPaused(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    while (item.Pause) {
        if (item.Killed)
            break

        Sleep(200)
    }
}

; 可中断休眠：间隔内定期检查暂停/终止
InterruptibleSleep(tableItem, index, duration, waitWhilePaused := true) {
    if (duration <= 0)
        return
    item := tableItem.Items[index]
    curTime := 0
    clip := Min(100, duration)
    while (curTime < duration) {
        if (waitWhilePaused)
            WaitIfPaused(tableItem, index)
        if (item && item.Killed)
            break
        Sleep(clip)
        curTime += clip
        clip := Min(waitWhilePaused ? 500 : 100, duration - curTime)
    }
}

; ============================================================
; 折叠归属辅助（对象化）：条目通过 item.FoldID 归属折叠框
; ============================================================
; 条目所属折叠框下标（1 基；无归属或找不到返回 0）
GetItemFoldIndex(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item || item.FoldID == "")
        return 0
    return GetFoldIndexInTable(tableItem, item.FoldID)
}

; 统一获取某项的所有Fold信息（对象化：条目 FoldID → 折叠框）
GetItemFoldData(tableItem, itemIndex) {
    item := tableItem.Items[itemIndex]
    if (!item || item.FoldID == "")
        return { foldIndex: 0, forbidState: false, frontInfo: "", offset: 1 }

    for Index, fold in tableItem.Folds {
        if (fold.ID == item.FoldID) {
            return {
                foldIndex: Index,
                forbidState: fold.ForbidState,
                frontInfo: fold.FrontInfo,
                offset: 1
            }
        }
    }
    return { foldIndex: 0, forbidState: false, frontInfo: "", offset: 1 }
}

GetItemFoldForbidState(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).forbidState
}

; 按条目的 FoldID 取所属模块绑定。宏条目自己的窗口绑定由 ResolveBindWindow 处理。
GetItemModuleWindowBinding(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).frontInfo
}

GetItemOffsetOfFold(tableItem, itemIndex) {
    return GetItemFoldData(tableItem, itemIndex).offset
}

CustomMsgBox(Text := "", Title := "", Buttons := "") {
    ; 兼容旧调用：统一使用 XAML 对话框，返回按钮序号（关闭返回 0）。
    return RmtDialog.Choose(Text, Title, StrSplit(Buttons, "|"))
}

IncrementText(strArr, str) {
    str := IncrementTextNumber(str)
    for curStr in strArr {
        if (str == curStr)
            return IncrementText(strArr, str)
    }
    return str
}

IncrementTextNumber(str) {
    ; 使用正则表达式匹配文本+数字的模式
    if (RegExMatch(str, "^(.*?)(\d+)$", &match)) {
        ; 如果匹配成功，提取文本部分和数字部分
        textPart := match[1]
        numberPart := match[2]

        ; 将数字部分转换为整数并加1
        newNumber := Integer(numberPart) + 1

        ; 返回文本+新数字
        return textPart . newNumber
    }
    else {
        ; 如果没有数字部分，直接在后面添加"1"
        return str . "1"
    }
}

; macroState 为 1 时判断本轮开始提示，为 2 时判断本轮结束提示。
; 播放策略 3 只在宏的首轮开始或末轮结束播放。
PlayMacroIterationCue(tableItem, itemIndex, macroState, isFirst, isLast) {
    item := tableItem.Items[itemIndex]
    if (!item)
        return
    if (macroState == 1) {
        if (item.StartTipSound == 1)
            return

        if (item.StartTipSound == 2) {
            PlayTipSound(1)
            return
        }

        if (item.StartTipSound == 3 && isFirst) {
            PlayTipSound(1)
            return
        }
    }

    if (macroState == 2) {
        if (item.EndTipSound == 1)
            return

        if (item.EndTipSound == 2) {
            PlayTipSound(2)
            return
        }

        if (item.EndTipSound == 3 && isLast) {
            PlayTipSound(2)
            return
        }
    }
}

; type 为 1 开始、2 结束、3 终止。未配置独立终止音时沿用结束音。
PlayTipSound(type) {
    startPath := (IsSet(MainSoftData) && MainSoftData.StartTipAudio != "" && FileExist(MainSoftData.StartTipAudio)) ? MainSoftData.StartTipAudio : StartTipAudio
    endPath := (IsSet(MainSoftData) && MainSoftData.EndTipAudio != "" && FileExist(MainSoftData.EndTipAudio)) ? MainSoftData.EndTipAudio : EndTipAudio
    stopPath := (IsSet(MainSoftData) && MainSoftData.StopTipAudio != "" && FileExist(MainSoftData.StopTipAudio)) ? MainSoftData.StopTipAudio : endPath
    audioPathMap := Map(1, startPath, 2, endPath, 3, stopPath)
    if (audioPathMap.Has(type) && FileExist(audioPathMap[type])) {
        SoundPlay(audioPathMap[type])
    }
}

; 仅裁掉尾部未启用的行。中间的禁用行保留位置，与变量和值的下标对齐。
GetLastEnabledExtractRow(Arr) {
    Length := Arr.Length
    loop Arr.Length {
        index := Arr.Length - A_Index + 1
        if (Arr[index] == 0 || Arr[index] == false) {
            Length--
            continue
        }
        break
    }
    return Length
}
