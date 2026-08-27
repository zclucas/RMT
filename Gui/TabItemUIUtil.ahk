#Requires AutoHotkey v2.0
#Include ..\Main\Util\JsonUtil.ahk

; 宏列表数据操作层（XAML 版）
; 渲染由 MainWin.RenderTab 完成；本文件只做数据变更 + 触发重渲染。
; 编辑值回读统一走 MyMainWin.ReadTabValues（对应原生 RecycleTabItem）。

RecycleTabItem(tableItem) {
    MyMainWin.ReadTabValues(tableItem)
}

;增加宏配置
OnItemAddMacroBtnClick(tableItem, foldIndex, *) {
    foldInfo := tableItem.FoldInfo
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    if (isMenu) {
        IndexSpan := StrSplit(foldInfo.IndexSpanArr[foldIndex], "-")
        if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
            Count := IndexSpan[2] - IndexSpan[1] + 1
            if (Count >= 8) {
                MsgBox(GetLang("轮盘最多只能添加8个"), GetLang("提示"))
                return
            }
        }
    }
    MyMainWin.ReadTabValues(tableItem)
    AddIndex := GetFoldAddItemIndex(foldInfo, foldIndex)
    if (foldInfo.FoldStateArr[foldIndex])  ;没开打的话，自动打开
        foldInfo.FoldStateArr[foldIndex] := false

    UpdateFoldIndexInfo(foldInfo, AddIndex, foldIndex, true)
    tableItem.ColorStateArr.InsertAt(AddIndex, 0)
    tableItem.TKArr.InsertAt(AddIndex, "")
    tableItem.TriggerTypeArr.InsertAt(AddIndex, 1)
    tableItem.MacroArr.InsertAt(AddIndex, "")
    tableItem.ModeArr.InsertAt(AddIndex, 1)
    tableItem.ForbidArr.InsertAt(AddIndex, 0)
    tableItem.RemarkArr.InsertAt(AddIndex, "")
    tableItem.LoopCountArr.InsertAt(AddIndex, "1")
    tableItem.HoldTimeArr.InsertAt(AddIndex, 500)
    tableItem.UnorderedTriggerArr.InsertAt(AddIndex, false)
    tableItem.SerialArr.InsertAt(AddIndex, GetCMDSerialStr("Item"))
    tableItem.TimingSerialArr.InsertAt(AddIndex, GetCMDSerialStr("Timing"))
    tableItem.StartTipSoundArr.InsertAt(AddIndex, 1)
    tableItem.EndTipSoundArr.InsertAt(AddIndex, 1)
    tableItem.VoiceTriggerArr.InsertAt(AddIndex, 0)
    tableItem.VoiceKeywordsArr.InsertAt(AddIndex, "")
    tableItem.IsWorkIndexArr.InsertAt(AddIndex, 0)
    tableItem.GraphBranchCountArr.InsertAt(AddIndex, 0)
    tableItem.IcoPathArr.InsertAt(AddIndex, "")
    tableItem.KilledArr.InsertAt(AddIndex, false)
    tableItem.PauseArr.InsertAt(AddIndex, false)
    tableItem.ActionCount.InsertAt(AddIndex, 0)
    tableItem.HoldKeyArr.InsertAt(AddIndex, Map())
    tableItem.ToggleStateArr.InsertAt(AddIndex, false)
    tableItem.ToggleActionArr.InsertAt(AddIndex, "")
    VariableMap := Map()
    VariableMap["宏循环次数"] := 0
    VariableMap["循环-跳过本轮"] := false
    VariableMap["循环-跳出"] := false
    VariableMap["分支-跳出"] := false
    tableItem.VariableMapArr.InsertAt(AddIndex, VariableMap)

    MyMainWin.RenderTab(tableItem)
}

;删除宏配置
OnItemDelMacroBtnClick(tableItem, DelIndex, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := GetItemFoldIndex(tableItem, DelIndex)
    result := MsgBox(GetLang("是否删除当前宏"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    MyMainWin.ReadTabValues(tableItem)
    OnItemDelMacro(tableItem, DelIndex, foldInfo, foldIndex)
    MyMainWin.RenderTab(tableItem)
}

OnItemDelMacro(tableItem, itemIndex, foldInfo, foldIndex) {
    UpdateFoldIndexInfo(foldInfo, itemIndex, foldIndex, false)

    SafeRemoveAt(tableItem.ColorStateArr, itemIndex)
    SafeRemoveAt(tableItem.SerialArr, itemIndex)
    SafeRemoveAt(tableItem.TKArr, itemIndex)
    SafeRemoveAt(tableItem.MacroArr, itemIndex)
    SafeRemoveAt(tableItem.LoopCountArr, itemIndex)
    SafeRemoveAt(tableItem.TriggerTypeArr, itemIndex)
    SafeRemoveAt(tableItem.ModeArr, itemIndex)
    SafeRemoveAt(tableItem.ForbidArr, itemIndex)
    SafeRemoveAt(tableItem.HoldTimeArr, itemIndex)
    SafeRemoveAt(tableItem.UnorderedTriggerArr, itemIndex)
    SafeRemoveAt(tableItem.RemarkArr, itemIndex)
    SafeRemoveAt(tableItem.TimingSerialArr, itemIndex)
    SafeRemoveAt(tableItem.StartTipSoundArr, itemIndex)
    SafeRemoveAt(tableItem.EndTipSoundArr, itemIndex)
    SafeRemoveAt(tableItem.VoiceTriggerArr, itemIndex)
    SafeRemoveAt(tableItem.VoiceKeywordsArr, itemIndex)
    SafeRemoveAt(tableItem.IsWorkIndexArr, itemIndex)
    SafeRemoveAt(tableItem.GraphBranchCountArr, itemIndex)
    SafeRemoveAt(tableItem.IcoPathArr, itemIndex)
    SafeRemoveAt(tableItem.KilledArr, itemIndex)
    SafeRemoveAt(tableItem.PauseArr, itemIndex)
    SafeRemoveAt(tableItem.ActionCount, itemIndex)
    SafeRemoveAt(tableItem.HoldKeyArr, itemIndex)
    SafeRemoveAt(tableItem.ToggleStateArr, itemIndex)
    SafeRemoveAt(tableItem.ToggleActionArr, itemIndex)
    SafeRemoveAt(tableItem.VariableMapArr, itemIndex)
}

SafeRemoveAt(arr, index) {
    if (index > 0 && index <= arr.Length)
        arr.RemoveAt(index)
}

;增加宏模块
OnItemAddFoldBtnClick(tableItem, foldIndex, *) {
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    isUI := GetTableSymbol(tableItem.Index) == "UI"
    foldInfo := tableItem.FoldInfo
    MyMainWin.ReadTabValues(tableItem)

    foldInfo.RemarkArr.InsertAt(foldIndex + 1, "")
    foldInfo.FrontInfoArr.InsertAt(foldIndex + 1, "")
    foldInfo.IndexSpanArr.InsertAt(foldIndex + 1, "无-无")
    foldInfo.ForbidStateArr.InsertAt(foldIndex + 1, false)
    foldInfo.FoldStateArr.InsertAt(foldIndex + 1, false)
    foldInfo.TKTypeArr.InsertAt(foldIndex + 1, 1)
    foldInfo.TKArr.InsertAt(foldIndex + 1, "")
    foldInfo.HoldTimeArr.InsertAt(foldIndex + 1, 500)
    while (foldInfo.UnorderedTriggerArr.Length < foldIndex)
        foldInfo.UnorderedTriggerArr.Push(false)
    foldInfo.UnorderedTriggerArr.InsertAt(foldIndex + 1, false)

    if (isMenu)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 4)
    else if (isUI)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 3)

    MyMainWin.RenderTab(tableItem)
}

; 菜单宏/界面宏新增模块时批量预置配置项（菜单默认 4、界面默认 3）
OnItemAddMenuItem(tableItem, foldIndex, count := 4) {
    loop count {
        foldInfo := tableItem.FoldInfo
        AddIndex := GetFoldAddItemIndex(foldInfo, foldIndex)
        UpdateFoldIndexInfo(foldInfo, AddIndex, foldIndex, true)
        tableItem.ColorStateArr.InsertAt(AddIndex, 0)
        tableItem.TKArr.InsertAt(AddIndex, "")
        tableItem.TriggerTypeArr.InsertAt(AddIndex, 1)
        tableItem.MacroArr.InsertAt(AddIndex, "")
        tableItem.ModeArr.InsertAt(AddIndex, 1)
        tableItem.ForbidArr.InsertAt(AddIndex, 0)
        tableItem.RemarkArr.InsertAt(AddIndex, "")
        tableItem.LoopCountArr.InsertAt(AddIndex, "1")
        tableItem.HoldTimeArr.InsertAt(AddIndex, 500)
        tableItem.UnorderedTriggerArr.InsertAt(AddIndex, false)
        tableItem.SerialArr.InsertAt(AddIndex, GetCMDSerialStr("Item"))
        tableItem.TimingSerialArr.InsertAt(AddIndex, GetCMDSerialStr("Timing"))
        tableItem.StartTipSoundArr.InsertAt(AddIndex, 0)
        tableItem.EndTipSoundArr.InsertAt(AddIndex, 0)
        tableItem.VoiceTriggerArr.InsertAt(AddIndex, 0)
        tableItem.VoiceKeywordsArr.InsertAt(AddIndex, "")
        tableItem.IsWorkIndexArr.InsertAt(AddIndex, 0)
        tableItem.GraphBranchCountArr.InsertAt(AddIndex, 0)
        tableItem.IcoPathArr.InsertAt(AddIndex, "")
        tableItem.KilledArr.InsertAt(AddIndex, false)
        tableItem.PauseArr.InsertAt(AddIndex, false)
        tableItem.ActionCount.InsertAt(AddIndex, 0)
        tableItem.HoldKeyArr.InsertAt(AddIndex, Map())
        tableItem.ToggleStateArr.InsertAt(AddIndex, false)
        tableItem.ToggleActionArr.InsertAt(AddIndex, "")
        VariableMap := Map()
        VariableMap["宏循环次数"] := 0
        VariableMap["循环-跳过本轮"] := false
        VariableMap["循环-跳出"] := false
        VariableMap["分支-跳出"] := false
        tableItem.VariableMapArr.InsertAt(AddIndex, VariableMap)
    }
}

;删除模块
OnItemDelFoldBtnClick(tableItem, foldIndex, *) {
    foldInfo := tableItem.FoldInfo
    result := MsgBox(GetLang("是否删除当前模块以及模块中所有的宏配置"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    if (foldInfo.IndexSpanArr.Length == 1) {
        MsgBox(GetLang("最后一个模块，不可删除！！！"))
        return
    }

    MyMainWin.ReadTabValues(tableItem)
    hasSetting := foldInfo.IndexSpanArr[foldIndex] != "无-无"
    if (hasSetting) {
        IndexSpan := StrSplit(foldInfo.IndexSpanArr[foldIndex], "-")
        loop IndexSpan[2] - IndexSpan[1] + 1 {
            itemIndex := IndexSpan[2] - A_Index + 1
            OnItemDelMacro(tableItem, itemIndex, foldInfo, foldIndex)
        }
    }

    foldInfo.RemarkArr.RemoveAt(foldIndex)
    foldInfo.FrontInfoArr.RemoveAt(foldIndex)
    foldInfo.IndexSpanArr.RemoveAt(foldIndex)
    foldInfo.ForbidStateArr.RemoveAt(foldIndex)
    foldInfo.FoldStateArr.RemoveAt(foldIndex)
    foldInfo.TKTypeArr.RemoveAt(foldIndex)
    foldInfo.TKArr.RemoveAt(foldIndex)
    foldInfo.HoldTimeArr.RemoveAt(foldIndex)
    foldInfo.UnorderedTriggerArr.RemoveAt(foldIndex)
    MyMainWin.RenderTab(tableItem)
}

;编辑字串宏触发键
OnItemEditTriggerStr(tableItem, index, *) {
    MyMainWin.ReadTabValues(tableItem)
    triggerStr := tableItem.TKArr[index]

    SureAction(sureTriggerKey) {
        tableItem.TKArr[index] := sureTriggerKey
        MyMainWin.RenderTab(tableItem)
    }

    MyTriggerStrGui.SaveBtnAction := OnSaveSetting
    MyTriggerStrGui.SureBtnAction := SureAction
    MyTriggerStrGui.ShowGui(triggerStr, 0, false)
}

;自定义编辑触发按键（触发键按钮右键）
;现提供菜单：语音触发设置 / 自定义触发串
OnItemCustomEditTriggerStr(tableItem, index, *) {
    isNormal := CheckIsNormalTable(tableItem.Index)
    MyMainWin.ReadTabValues(tableItem)

    m := Menu()
    m.Add(GetLang("语音触发"), (*) => OnItemVoiceTriggerSetting(tableItem, index))
    if (isNormal)
        m.Add(GetLang("自定义触发串"), (*) => OnItemCustomEditTriggerStrInput(tableItem, index))
    handler := OnItemCustomEditTriggerStr.Bind(tableItem, index)
    m.Show()
}

; 原「自定义触发串」InputBox 逻辑（保留，走菜单项）
OnItemCustomEditTriggerStrInput(tableItem, index, *) {
    CustomTK := InputBox(GetLang("请输入自定义触发按键："), "修改", "w300 h100", tableItem.TKArr[index])
    if CustomTK.Result = "Cancel"
        return
    tableItem.TKArr[index] := CustomTK.Value
    MyMainWin.RenderTab(tableItem)
}

; 语音触发设置（语音关键词配置窗口入口）
OnItemVoiceTriggerSetting(tableItem, index, *) {
    MyVoiceGui.ShowGui(tableItem, index)
}

;编辑按键宏触发键
OnItemEditTriggerKey(tableItem, index, *) {
    MyMainWin.ReadTabValues(tableItem)
    triggerKey := tableItem.TKArr[index]

    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        tableItem.TKArr[index] := sureTriggerKey
        tableItem.HoldTimeArr[index] := timeValue
        while (tableItem.UnorderedTriggerArr.Length < index)
            tableItem.UnorderedTriggerArr.Push(false)
        tableItem.UnorderedTriggerArr[index] := unorderedTrigger
        MyMainWin.RenderTab(tableItem)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := tableItem.UnorderedTriggerArr[index]
    MyTriggerKeyGui.ShowGui(triggerKey, tableItem.HoldTimeArr[index], false)
}

;编辑定时器
OnItemEditTiming(tableItem, index, *) {
    SerialStr := tableItem.TimingSerialArr[index]
    if (!RegExMatch(SerialStr, "^Timing\d+$")) {
        SerialStr := GetCMDSerialStr("Timing")
        tableItem.TimingSerialArr[index] := SerialStr
    }
    MyTimingGui.ShowGui(SerialStr)
}

OnItemEditMacroSetting(tableItem, index, *) {
    MyMacroSettingGui.OwnerHwnd := MainSoftData.MyGui.Hwnd
    MyMacroSettingGui.ShowGui(tableItem.Index, index)
}

OnItemMenuMacroSettingClick(tableItem, index, *) {
    MyMenuMacroSettingGui.ShowGui(tableItem.Index, index)
}

; 打开逻辑树（宏指令）编辑器
OpenItemMacroTreeEditor(tableItem, index, macro, SureAction) {
    MySoftData.SpecialTableItem.ModeArr[1] := tableItem.ModeArr[index]
    if (MyMacroGui.Gui != "") {
        style := WinGetStyle(MyMacroGui.Gui.Hwnd)
        isVisible := (style & 0x10000000)
        if (isVisible) {
            MacroGui := MacroEditGui()
            MacroGui.SureFocusCon := MainSoftData.BtnSave
            MacroGui.SureBtnAction := SureAction
            MacroGui.SaveBtnAction := OnSaveSetting
            MacroGui.ShowGui(macro, true)
            return
        }
    }
    MyMacroGui.SureFocusCon := MainSoftData.BtnSave
    MyMacroGui.SureBtnAction := SureAction
    MyMacroGui.SaveBtnAction := OnSaveSetting
    MyMacroGui.ShowGui(macro, true)
}

; 打开图形节点编辑器
OpenItemMacroGraphEditor(macro, SureAction) {
    MyMacroGraphGui.OwnerHwnd := ""
    MyMacroGraphGui.SureBtnAction := SureAction
    MyMacroGraphGui.ShowGui(macro)
}

; 编辑按钮：空宏按「首选编辑器」；已有配置则看首条是否图形开始节点
OnItemEditMacro(tableItem, index, *) {
    macro := tableItem.MacroArr[index]

    SureAction(sureMacro) {
        tableItem.MacroArr[index] := sureMacro
    }

    useGraph := false
    if (IsEmptyMacroStr(macro))
        useGraph := (Integer(MainSoftData.PreferredMacroEditor) == 2)
    else
        useGraph := IsMacroFirstCmdGraphStart(macro)

    if (useGraph)
        OpenItemMacroGraphEditor(macro, SureAction)
    else
        OpenItemMacroTreeEditor(tableItem, index, macro, SureAction)
}

OnItemEditReplaceKey(tableItem, index, *) {
    replaceKey := tableItem.MacroArr[index]

    SureAction(sureMacro) {
        tableItem.MacroArr[index] := sureMacro
    }

    MyReplaceKeyGui.SureBtnAction := SureAction
    MyReplaceKeyGui.ShowGui(replaceKey)
}

OnItemMoveUp(tableItem, index, *) {
    if (index == 1) {
        MsgBox(GetLang("上面没有元素，无法上移！！！"))
        return
    }
    MyMainWin.ReadTabValues(tableItem)
    SwapTableContent(tableItem, index, index - 1)
    ; Epic5 虚拟化：先换集合顺序再刷两行（VM 槽位数据随模型更新）
    if (MyMainWin._useVirtual.Has(tableItem.Index))
        MyMainWin._vl.MoveRow(tableItem.Index, index, index - 1)
    ; 增量：只刷新被交换两行，不整列表重建（滚动位置不复位）
    MyMainWin.RefreshItemRow(tableItem.Index, index - 1)
    MyMainWin.RefreshItemRow(tableItem.Index, index)
}

OnItemMoveDown(tableItem, index, *) {
    lastIndex := tableItem.ModeArr.length
    if (lastIndex == index) {
        MsgBox(GetLang("下面没有元素，无法下移！！！"))
        return
    }
    MyMainWin.ReadTabValues(tableItem)
    SwapTableContent(tableItem, index, index + 1)
    if (MyMainWin._useVirtual.Has(tableItem.Index))
        MyMainWin._vl.MoveRow(tableItem.Index, index, index + 1)
    ; 增量：只刷新被交换两行，不整列表重建（滚动位置不复位）
    MyMainWin.RefreshItemRow(tableItem.Index, index + 1)
    MyMainWin.RefreshItemRow(tableItem.Index, index)
}

OnFoldFrontInfoEdit(tableItem, foldIndex, *) {
    foldInfo := tableItem.FoldInfo
    if (MyMainWin._useVirtual.Has(tableItem.Index)) {
        ; Epic5：fold 头 TextBox 在 DataTemplate 内无命名控件，读模型（点按钮前 LostFocus 已 VL_CHANGE 写回）
        frontCtrl := { Value: foldInfo.FrontInfoArr[foldIndex] }
    } else {
        frontCtrl := CtrlAdapter("FoldFront_" tableItem.Index "_" foldIndex, MyMainWin.ui, "Text")
    }
    SureAction() {
        newInfo := frontCtrl.Value
        oldInfo := foldInfo.FrontInfoArr[foldIndex]
        foldInfo.FrontInfoArr[foldIndex] := newInfo
        if (oldInfo != newInfo && IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.DestroyFoldPanels(foldIndex)
    }
    MyFrontInfoGui.SureAction := SureAction
    MyFrontInfoGui.ShowGui(frontCtrl, true)
}

OnFoldBtnClick(tableItem, foldIndex, *) {
    foldInfo := tableItem.FoldInfo
    MyMainWin.ReadTabValues(tableItem)
    foldInfo.FoldStateArr[foldIndex] := !foldInfo.FoldStateArr[foldIndex]
    t := tableItem.Index
    if (MyMainWin._useVirtual.Has(t)) {
        ; Epic5：折叠 = 集合移除行组 + 视口锚定（1 IPC），不重建整表
        MyMainWin._vl.FoldToggle(t, foldIndex, foldInfo.FoldStateArr[foldIndex])
        return
    }
    ; A: 折叠只切整组容器 Visibility + 图标文字，不重建整表（千条级展开/折叠瞬间完成，滚动位置保留）
    ;    Update 路径不解 XAML 实体（仅解 &#x0A;/&#x0D;），须传实际字符非实体串，否则图标变字面 &#xE76C;
    MyMainWin.ui.Update("FoldItems_" t "_" foldIndex, "Visibility", foldInfo.FoldStateArr[foldIndex] ? "Collapsed" : "Visible")
    MyMainWin.ui.Update("FoldGlyph_" t "_" foldIndex, "Text", foldInfo.FoldStateArr[foldIndex] ? Chr(0xE76C) : Chr(0xE70D))
    ; 展开折叠：补绑组内行事件（渲染时折叠态行跳过了 BindEvent，_Bind 清旧再挂幂等）
    if (!foldInfo.FoldStateArr[foldIndex]) {
        span := StrSplit(foldInfo.IndexSpanArr[foldIndex], "-")
        if (IsInteger(span[1]) && IsInteger(span[2])) {
            loop span[2] - span[1] + 1 {
                i := span[1] + A_Index - 1
                MyMainWin._BindItemRow(t, i)
            }
        }
    }
}

OnFlodTKEditClick(tableItem, foldIndex, *) {
    foldInfo := tableItem.FoldInfo
    MyMainWin.ReadTabValues(tableItem)
    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        foldInfo.TKArr[foldIndex] := sureTriggerKey
        foldInfo.HoldTimeArr[foldIndex] := timeValue
        while (foldInfo.UnorderedTriggerArr.Length < foldIndex)
            foldInfo.UnorderedTriggerArr.Push(false)
        foldInfo.UnorderedTriggerArr[foldIndex] := unorderedTrigger
        MyMainWin.RenderTab(tableItem)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := foldInfo.UnorderedTriggerArr.Has(foldIndex) ? foldInfo.UnorderedTriggerArr[foldIndex] : false
    MyTriggerKeyGui.ShowGui(foldInfo.TKArr[foldIndex], foldInfo.HoldTimeArr[foldIndex], false)
}

UpdateFoldIndexInfo(FoldInfo, OperIndex, FoldIndex, IsAdd) {
    curMaxItemIndex := 0
    for Index, IndexSpanStr in FoldInfo.IndexSpanArr {
        IndexSpan := StrSplit(IndexSpanStr, "-")
        if (Index < FoldIndex) {
            if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
                curMaxItemIndex := IndexSpan[2]
            }
            continue
        }
        if (Index == FoldIndex) {
            if (IsAdd) {
                if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
                    IndexSpan[2] := IndexSpan[2] + 1
                }
                else {
                    IndexSpan[1] := curMaxItemIndex + 1
                    IndexSpan[2] := curMaxItemIndex + 1
                }
            }
            else {
                IndexSpan[2] := IndexSpan[2] - 1
                if (IndexSpan[2] < IndexSpan[1]) {
                    IndexSpan[1] := "无"
                    IndexSpan[2] := "无"
                }
            }
        }
        if (Index > FoldIndex) {
            Value := IsAdd ? 1 : -1
            if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
                IndexSpan[1] := IndexSpan[1] + Value
                IndexSpan[2] := IndexSpan[2] + Value
            }
        }
        FoldInfo.IndexSpanArr[Index] := IndexSpan[1] "-" IndexSpan[2]
    }
}

GetFoldAddItemIndex(FoldInfo, FoldIndex) {
    IndexSpan := StrSplit(FoldInfo.IndexSpanArr[FoldIndex], "-")
    if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
        return IndexSpan[2] + 1
    }

    CurFoldLastIndex := 0
    for index, value in FoldInfo.IndexSpanArr {
        if (index > FoldIndex)
            break

        IndexSpan := StrSplit(value, "-")
        if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
            CurFoldLastIndex := IndexSpan[2]
        }
    }

    return CurFoldLastIndex + 1
}

OnUIMacroSettingClick(tableItem, macroIndex, *) {
    MyUIMacroSettingGui.ShowGui(tableItem.Index, macroIndex)
}
