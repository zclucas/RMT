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
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    if (isMenu) {
        fold := tableItem.Folds[foldIndex]
        if (fold) {
            Count := GetFoldItemCount(tableItem, fold)
            if (Count >= 8) {
                MsgBox(GetLang("轮盘最多只能添加8个"), GetLang("提示"))
                return
            }
        }
    }
    MyMainWin.ReadTabValues(tableItem)
    AddIndex := GetFoldAddItemIndex(tableItem, foldIndex)
    if (foldIndex >= 1 && foldIndex <= tableItem.Folds.Length)
        tableItem.Folds[foldIndex].FoldState := false  ;没开打的话，自动打开

    item := MacroItem()
    item.ID := GetCMDSerialStr("Item")
    item.TimingSerial := GetCMDSerialStr("Timing")
    item.FoldID := (foldIndex >= 1 && foldIndex <= tableItem.Folds.Length) ? tableItem.Folds[foldIndex].ID : ""
    tableItem.Items.InsertAt(AddIndex, item)

    tableItem.RebuildIndex()
    RebuildTableLocator()
    MyMainWin.RenderTab(tableItem)
}

;删除宏配置
OnItemDelMacroBtnClick(tableItem, DelIndex, *) {
    result := MsgBox(GetLang("是否删除当前宏"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    MyMainWin.ReadTabValues(tableItem)
    OnItemDelMacro(tableItem, DelIndex)
    MyMainWin.RenderTab(tableItem)
}

OnItemDelMacro(tableItem, itemIndex) {
    tableItem.Items.RemoveAt(itemIndex)
    tableItem.RebuildIndex()
    RebuildTableLocator()
}

;增加宏模块
OnItemAddFoldBtnClick(tableItem, foldIndex, *) {
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    isUI := GetTableSymbol(tableItem.Index) == "UI"
    MyMainWin.ReadTabValues(tableItem)

    fold := MacroFold()
    fold.ID := GetFoldSerialStr()
    tableItem.Folds.InsertAt(foldIndex + 1, fold)

    if (isMenu)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 4)
    else if (isUI)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 3)

    tableItem.RebuildIndex()
    MyMainWin.RenderTab(tableItem)
}

; 菜单宏/界面宏新增模块时批量预置配置项（菜单默认 4、界面默认 3）
OnItemAddMenuItem(tableItem, foldIndex, count := 4) {
    fold := tableItem.Folds[foldIndex]
    loop count {
        AddIndex := GetFoldAddItemIndex(tableItem, foldIndex)
        item := MacroItem()
        item.ID := GetCMDSerialStr("Item")
        item.TimingSerial := GetCMDSerialStr("Timing")
        item.FoldID := fold.ID
        tableItem.Items.InsertAt(AddIndex, item)
    }
    tableItem.RebuildIndex()
    RebuildTableLocator()
}

;删除模块
OnItemDelFoldBtnClick(tableItem, foldIndex, *) {
    result := MsgBox(GetLang("是否删除当前模块以及模块中所有的宏配置"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    if (tableItem.Folds.Length == 1) {
        MsgBox(GetLang("最后一个模块，不可删除！！！"))
        return
    }

    MyMainWin.ReadTabValues(tableItem)
    fold := tableItem.Folds[foldIndex]
    if (fold) {
        ; 删除归属该折叠框的所有条目
        keep := []
        for item in tableItem.Items {
            if (item.FoldID != fold.ID)
                keep.Push(item)
        }
        tableItem.Items := keep
        tableItem.Folds.RemoveAt(foldIndex)
        tableItem.RebuildIndex()
        RebuildTableLocator()
    }
    MyMainWin.RenderTab(tableItem)
}

;编辑字串宏触发键
OnItemEditTriggerStr(tableItem, index, *) {
    MyMainWin.ReadTabValues(tableItem)
    item := tableItem.Items[index]
    triggerStr := item.TK

    SureAction(sureTriggerKey) {
        item.TK := sureTriggerKey
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
    item := tableItem.Items[index]
    CustomTK := InputBox(GetLang("请输入自定义触发按键："), "修改", "w300 h100", item.TK)
    if CustomTK.Result = "Cancel"
        return
    item.TK := CustomTK.Value
    MyMainWin.RenderTab(tableItem)
}

; 语音触发设置（语音关键词配置窗口入口）
OnItemVoiceTriggerSetting(tableItem, index, *) {
    MyVoiceGui.ShowGui(tableItem, index)
}

;编辑按键宏触发键
OnItemEditTriggerKey(tableItem, index, *) {
    MyMainWin.ReadTabValues(tableItem)
    item := tableItem.Items[index]
    triggerKey := item.TK

    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        item.TK := sureTriggerKey
        item.HoldTime := timeValue
        item.UnorderedTrigger := unorderedTrigger
        MyMainWin.RenderTab(tableItem)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := item.UnorderedTrigger
    MyTriggerKeyGui.ShowGui(triggerKey, item.HoldTime, false)
}

;编辑定时器
OnItemEditTiming(tableItem, index, *) {
    item := tableItem.Items[index]
    SerialStr := item.TimingSerial
    if (!RegExMatch(SerialStr, "^Timing\d+$")) {
        SerialStr := GetCMDSerialStr("Timing")
        item.TimingSerial := SerialStr
    }
    MyTimingGui.ShowGui(SerialStr)
}

OnItemEditMacroSetting(tableItem, index, *) {
    MyMacroSettingGui.OwnerHwnd := MainSoftData.MyGui.Hwnd
    MyMacroSettingGui.ShowGui(tableItem, index)
}

OnItemMenuMacroSettingClick(tableItem, index, *) {
    MyMenuMacroSettingGui.ShowGui(tableItem, index)
}

; 打开逻辑树（宏指令）编辑器
OpenItemMacroTreeEditor(tableItem, index, macro, SureAction) {
    item := tableItem.Items[index]
    MySoftData.SpecialTableItem.Items[1].Mode := item.Mode
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
    item := tableItem.Items[index]
    macro := item.Macro

    SureAction(sureMacro) {
        item.Macro := sureMacro
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
    item := tableItem.Items[index]
    replaceKey := item.Macro

    SureAction(sureMacro) {
        item.Macro := sureMacro
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
    lastIndex := tableItem.Items.Length
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
    fold := tableItem.Folds[foldIndex]
    if (MyMainWin._useVirtual.Has(tableItem.Index)) {
        ; Epic5：fold 头 TextBox 在 DataTemplate 内无命名控件，读模型（点按钮前 LostFocus 已 VL_CHANGE 写回）
        frontCtrl := { Value: fold.FrontInfo }
    } else {
        frontCtrl := CtrlAdapter("FoldFront_" tableItem.Index "_" foldIndex, MyMainWin.ui, "Text")
    }
    SureAction() {
        newInfo := frontCtrl.Value
        oldInfo := fold.FrontInfo
        fold.FrontInfo := newInfo
        if (oldInfo != newInfo && IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.DestroyFoldPanels(fold.ID)
    }
    MyFrontInfoGui.SureAction := SureAction
    MyFrontInfoGui.ShowGui(frontCtrl, true)
}

OnFoldBtnClick(tableItem, foldIndex, *) {
    fold := tableItem.Folds[foldIndex]
    MyMainWin.ReadTabValues(tableItem)
    fold.FoldState := !fold.FoldState
    t := tableItem.Index
    if (MyMainWin._useVirtual.Has(t)) {
        ; Epic5：折叠 = 集合移除行组 + 视口锚定（1 IPC），不重建整表
        MyMainWin._vl.FoldToggle(t, foldIndex, fold.FoldState)
        return
    }
    ; A: 折叠只切整组容器 Visibility + 图标文字，不重建整表（千条级展开/折叠瞬间完成，滚动位置保留）
    ;    Update 路径不解 XAML 实体（仅解 &#x0A;/&#x0D;），须传实际字符非实体串，否则图标变字面 &#xE76C;
    MyMainWin.ui.Update("FoldItems_" t "_" foldIndex, "Visibility", fold.FoldState ? "Collapsed" : "Visible")
    MyMainWin.ui.Update("FoldGlyph_" t "_" foldIndex, "Text", fold.FoldState ? Chr(0xE76C) : Chr(0xE70D))
    ; 展开折叠：补绑组内行事件（渲染时折叠态行跳过了 BindEvent，_Bind 清旧再挂幂等）
    if (!fold.FoldState) {
        for i, item in tableItem.Items {
            if (item.FoldID == fold.ID)
                MyMainWin._BindItemRow(t, i)
        }
    }
}

OnFlodTKEditClick(tableItem, foldIndex, *) {
    fold := tableItem.Folds[foldIndex]
    MyMainWin.ReadTabValues(tableItem)
    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        fold.TK := sureTriggerKey
        fold.HoldTime := timeValue
        fold.UnorderedTrigger := unorderedTrigger
        MyMainWin.RenderTab(tableItem)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := fold.UnorderedTrigger
    MyTriggerKeyGui.ShowGui(fold.TK, fold.HoldTime, false)
}

; 折叠框内条目数（用于菜单宏 8 上限校验）
GetFoldItemCount(tableItem, fold) {
    count := 0
    for item in tableItem.Items {
        if (item.FoldID == fold.ID)
            count++
    }
    return count
}

; 在折叠框内新增条目的插入下标（表内顺序）：
; 归属该折叠框的条目之后；无归属条目时取该折叠框之前的最后条目之后（保持折叠框区块顺序）
GetFoldAddItemIndex(tableItem, FoldIndex) {
    fold := tableItem.Folds[FoldIndex]
    if (!fold)
        return tableItem.Items.Length + 1
    lastIdx := 0
    for i, item in tableItem.Items {
        if (item.FoldID == fold.ID) {
            lastIdx := i
        } else if (lastIdx != 0) {
            break   ; 已越过本折叠的条目区
        }
    }
    if (lastIdx != 0)
        return lastIdx + 1

    ; 折叠框无条目：找前一个有序折叠框（FoldIndex-1 ... 1）的最后一个条目，插其后
    loop FoldIndex - 1 {
        f := FoldIndex - A_Index
        prevFold := tableItem.Folds[f]
        if (!prevFold)
            continue
        for i, item in tableItem.Items {
            if (item.FoldID == prevFold.ID)
                return i + 1
        }
    }
    return 1
}

OnUIMacroSettingClick(tableItem, macroIndex, *) {
    MyUIMacroSettingGui.ShowGui(tableItem, macroIndex)
}
