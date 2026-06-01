#Requires AutoHotkey v2.0
#Include ..\Main\Util\JsonUtil.ahk
ItemFreeConPoolMap := Map()
ItemUseConPoolMap := Map()

LoadItemFold(index) {
    tableItem := MySoftData.TableInfo[index]
    FoldInfo := tableItem.FoldInfo
    MyGui := MySoftData.MyGui
    tableItem.UnderPosY := MySoftData.TabPosY
    tableItem.FoldOffsetArr := []
    tableItem.FoldBtnArr := []
    ItemFreeConPoolMap.Set(tableItem.Index, [])
    ItemUseConPoolMap.Set(tableItem.Index, Map())
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    titleHeight := isMenu ? 85 : 55
    UpdateUnderPosY(index, 25)
    for foldIndex, IndexSpanStr in FoldInfo.IndexSpanArr {
        tableItem.FoldOffsetArr.Push(0)
        LoadItemFoldTitle(tableItem, foldIndex, tableItem.UnderPosY)
        UpdateUnderPosY(index, titleHeight)
        IndexSpan := StrSplit(IndexSpanStr, "-")
        if (!IsInteger(IndexSpan[1]) || !IsInteger(IndexSpan[2]))
            continue

        LoadItemFoldTip(tableItem, foldIndex, tableItem.UnderPosY)

        ;行高40 titleTip 25 group间隔5
        AllItemHeight := FoldInfo.FoldStateArr[foldIndex] ? 0 : (IndexSpan[2] - IndexSpan[1] + 1) * 40 + 25
        UpdateUnderPosY(index, AllItemHeight)
        UpdateUnderPosY(index, 5)
    }
    UpdateItemConPos(tableItem, true)
}

LoadItemFoldTitle(tableItem, foldIndex, PosY) {
    FoldInfo := tableItem.FoldInfo
    MyGui := MySoftData.MyGui
    isMenu := CheckIsMenuMacroTable(tableItem.Index)

    GroupHeight := GetFoldGroupHeight(FoldInfo, foldIndex, isMenu)
    con := MyGui.Add("GroupBox", Format("x{} y{} w900 h{}", MySoftData.TabPosX + 10, posY + 2,
        GroupHeight))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.InsertAt(foldIndex, con)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)
    PosY += 20

    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 20, posY + 2), GetLang("备注："))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)

    con := MyGui.Add("Edit", Format("x{} y{} w150 h27", MySoftData.TabPosX + 60, posY), FoldInfo.RemarkArr[
        foldIndex])
    con.OnEvent("Change", OnFoldRemarkChange.Bind(tableItem))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 230, posY + 2), GetLang("前台:"))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)

    FrontCon := MyGui.Add("Edit", Format("x{} y{} w150 h27", MySoftData.TabPosX + 270, posY), FoldInfo.FrontInfoArr[
        foldIndex])
    FrontCon.OnEvent("Change", OnFoldFrontInfoChange.Bind(tableItem))
    conInfo := ItemConInfo(FrontCon, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[FrontCon] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("Button", Format("x{} y{} h29", MySoftData.TabPosX + 422, posY - 1), GetLang("编辑"))
    con.OnEvent("Click", OnFoldFrontInfoEdit.Bind(tableItem, FrontCon))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    ;界面宏时禁用前台信息控件
    isUI := GetTableSymbol(tableItem.Index) == "UI"
    if (isUI) {
        FrontCon.Enabled := false
        con.Enabled := false
    }

    con := MyGui.Add("Button", Format("x{} y{} h29", MySoftData.TabPosX + 490, posY - 1), GetLang("新增宏"))
    con.OnEvent("Click", OnItemAddMacroBtnClick.Bind(tableItem))
    con.Visible := !isMenu
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("Button", Format("x{} y{} h29", MySoftData.TabPosX + 560, posY - 1), GetLang("粘贴宏"))
    con.OnEvent("Click", OnItemPasteMacroBtnClick.bind(tableItem))
    con.Visible := !isMenu
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("Button", Format("x{} y{} h29", MySoftData.TabPosX + 630, posY - 1), GetLang("新增模块"))
    con.OnEvent("Click", OnItemAddFoldBtnClick.Bind(tableItem))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("Button", Format("x{} y{} h29", MySoftData.TabPosX + 715, posY - 1), GetLang("删除模块"))
    con.OnEvent("Click", OnItemDelFoldBtnClick.Bind(tableItem))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    con := MyGui.Add("CheckBox", Format("x{} y{}", MySoftData.TabPosX + 750 + 40, posY + 2), GetLang("禁用"))
    con.Value := FoldInfo.ForbidStateArr[foldIndex]
    con.OnEvent("Click", OnFoldForbidChange.Bind(tableItem))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)

    btnStr := FoldInfo.FoldStateArr[foldIndex] ? "🞃" : "❯"
    con := MyGui.Add("Button", Format("x{} y{} w{} +BackgroundTrans", MySoftData.TabPosX + 840, posY - 2, 30),
    btnStr)
    con.OnEvent("Click", OnFoldBtnClick.Bind(tableItem))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[con] := MacroItemInfo(-10000, conInfo)
    tableItem.FoldBtnArr.InsertAt(foldIndex, con)

    if (isMenu)
        LoadItemFoldTK(tableItem, foldIndex, PosY + 35)
}

LoadItemFoldTK(tableItem, foldIndex, PosY) {
    FoldInfo := tableItem.FoldInfo
    MyGui := MySoftData.MyGui

    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 20, posY + 2), GetLang("菜单触发键："))
    conInfo := ItemConInfo(con, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)

    TriggerTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", MySoftData.TabPosX + 100, posY - 3, 70),
    GetLangArr(["按下", "松开", "松止", "开关", "长按", "双击"]))
    TriggerTypeCon.Value := FoldInfo.TKTypeArr[foldIndex]
    TriggerTypeCon.OnEvent("Change", OnFlodTKTypeChange.Bind(tableItem))
    conInfo := ItemConInfo(TriggerTypeCon, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[TriggerTypeCon] := MacroItemInfo(-10000, conInfo)

    TkCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", MySoftData.TabPosX + 175, posY - 3, 100,),
    "")
    TkCon.Value := FoldInfo.TKArr[foldIndex]
    TkCon.OnEvent("Change", OnFlodTKChange.Bind(tableItem))
    conInfo := ItemConInfo(TkCon, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[TkCon] := MacroItemInfo(-10000, conInfo)

    btnStr := GetLang("编辑")
    TKBtnCon := MyGui.Add("Button", Format("x{} y{} w60 h29", MySoftData.TabPosX + 280, posY - 4), btnStr)
    TKBtnCon.OnEvent("Click", OnFlodTKEditClick.Bind(TkCon, tableItem))
    conInfo := ItemConInfo(TKBtnCon, tableItem, foldIndex)
    conInfo.IsTitle := true
    tableItem.AllConArr.Push(conInfo)
    tableItem.ConIndexMap[TKBtnCon] := MacroItemInfo(-10000, conInfo)
}

LoadItemFoldTip(tableItem, foldIndex, PosY) {
    MyGui := MySoftData.MyGui

    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 70, posY), GetLang("宏名称"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))

    ;所有宏类型使用相同的列布局
    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 265, posY), GetLang("触发编辑器"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))
    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 360, posY), GetLang("触发类型"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))
    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 440, posY), GetLang("循环次数"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))
    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 518, posY), GetLang("宏设置"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))
    con := MyGui.Add("Text", Format("x{} y{}", MySoftData.TabPosX + 580, posY), GetLang("宏编辑器"))
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, foldIndex))
}

;按钮事件
;增加宏配置
OnItemAddMacroBtnClick(tableItem, btn, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[btn].itemConInfo.FoldIndex
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    titleHeight := isMenu ? 85 : 55
    AddIndex := GetFoldAddItemIndex(foldInfo, foldIndex)
    if (foldInfo.FoldStateArr[foldIndex])  ;没开打的话，自动打开
        OnFoldBtnClick(tableItem, btn)

    isFirst := foldInfo.IndexSpanArr[foldIndex] == "无-无"
    UpdateFoldIndexInfo(foldInfo, AddIndex, foldIndex, true)
    RecycleTabItem(tableItem)
    tableItem.ColorStateArr.InsertAt(AddIndex, 0)
    tableItem.TKArr.InsertAt(AddIndex, "")
    tableItem.TriggerTypeArr.InsertAt(AddIndex, 1)
    tableItem.MacroArr.InsertAt(AddIndex, "")
    tableItem.ModeArr.InsertAt(AddIndex, 1)
    tableItem.ForbidArr.InsertAt(AddIndex, 0)
    tableItem.RemarkArr.InsertAt(AddIndex, "")
    tableItem.LoopCountArr.InsertAt(AddIndex, "1")
    tableItem.HoldTimeArr.InsertAt(AddIndex, 500)
    tableItem.SerialArr.InsertAt(AddIndex, GetCMDSerialStr("Item"))
    tableItem.TimingSerialArr.InsertAt(AddIndex, GetCMDSerialStr("Timing"))
    tableItem.StartTipSoundArr.InsertAt(AddIndex, 1)
    tableItem.EndTipSoundArr.InsertAt(AddIndex, 1)
    tableItem.IsWorkIndexArr.InsertAt(AddIndex, 0)
    tableItem.GifPathArr.InsertAt(AddIndex, "")
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

    PosY := 1000000
    for index, value in tableItem.AllConArr {
        if (foldIndex == value.FoldIndex && PosY > value.OriPosY)
            PosY := value.OriPosY
    }

    PosY += titleHeight
    if (isFirst) {
        MySoftData.TabCtrl.UseTab(tableItem.Index)
        LoadItemFoldTip(tableItem, foldIndex, PosY)
        MySoftData.TabCtrl.UseTab()
    }

    afterHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    tableItem.AllGroup[foldIndex].Move(, , , afterHei)

    addHei := isFirst ? 75 : 40
    tableItem.FoldOffsetArr[foldIndex] += addHei
    MySlider.RefreshTab()
}

;删除宏配置
OnItemDelMacroBtnClick(tableItem, DelIndex, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := GetItemFoldIndex(tableItem, DelIndex)
    result := MsgBox(GetLang("是否删除当前宏"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    RecycleTabItem(tableItem)
    OnItemDelMacro(tableItem, DelIndex, foldInfo, foldIndex)
    MySlider.RefreshTab()
}

OnItemDelMacro(tableItem, itemIndex, foldInfo, foldIndex) {
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    beforeHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    UpdateFoldIndexInfo(foldInfo, itemIndex, foldIndex, false)
    HandleItemTopLabel(foldInfo, tableItem, foldIndex)
    afterHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    tableItem.FoldOffsetArr[foldIndex] += afterHei - beforeHei
    tableItem.AllGroup[foldIndex].Move(, , , afterHei)

    tableItem.ColorStateArr.RemoveAt(itemIndex)
    tableItem.SerialArr.RemoveAt(itemIndex)
    tableItem.TKArr.RemoveAt(itemIndex)
    tableItem.MacroArr.RemoveAt(itemIndex)
    tableItem.LoopCountArr.RemoveAt(itemIndex)
    tableItem.TriggerTypeArr.RemoveAt(itemIndex)
    tableItem.ModeArr.RemoveAt(itemIndex)
    tableItem.ForbidArr.RemoveAt(itemIndex)
    tableItem.HoldTimeArr.RemoveAt(itemIndex)
    tableItem.RemarkArr.RemoveAt(itemIndex)
    tableItem.TimingSerialArr.RemoveAt(itemIndex)
    tableItem.StartTipSoundArr.RemoveAt(itemIndex)
    tableItem.EndTipSoundArr.RemoveAt(itemIndex)
    tableItem.IsWorkIndexArr.RemoveAt(itemIndex)
    if (tableItem.HasProp("GifPathArr") && tableItem.GifPathArr.Length >= itemIndex) {
        tableItem.GifPathArr.RemoveAt(itemIndex)
    }
    tableItem.KilledArr.RemoveAt(itemIndex)
    tableItem.PauseArr.RemoveAt(itemIndex)
    tableItem.ActionCount.RemoveAt(itemIndex)
    tableItem.HoldKeyArr.RemoveAt(itemIndex)
    tableItem.ToggleStateArr.RemoveAt(itemIndex)
    tableItem.ToggleActionArr.RemoveAt(itemIndex)
    tableItem.VariableMapArr.RemoveAt(itemIndex)
}

;增加宏模块
OnItemAddFoldBtnClick(tableItem, btn, *) {
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    titleHeidht := isMenu ? 85 : 55
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[btn].itemConInfo.FoldIndex
    foldInfo.RemarkArr.InsertAt(foldIndex + 1, "")
    foldInfo.FrontInfoArr.InsertAt(foldIndex + 1, "")
    foldInfo.IndexSpanArr.InsertAt(foldIndex + 1, "无-无")
    foldInfo.ForbidStateArr.InsertAt(foldIndex + 1, false)
    foldInfo.FoldStateArr.InsertAt(foldIndex + 1, false)
    foldInfo.TKTypeArr.InsertAt(foldIndex + 1, 1)
    foldInfo.TKArr.InsertAt(foldIndex + 1, "")
    foldInfo.HoldTimeArr.InsertAt(foldIndex + 1, 500)
    tableItem.FoldOffsetArr.InsertAt(foldIndex + 1, titleHeidht)

    UpdateConFoldIndex(tableItem, foldIndex, true)
    LastGroupCon := tableItem.AllGroup[foldIndex]
    LastGroupCon.GetPos(&x, &y, &w, &h)
    LastItemConInfo := tableItem.ConIndexMap[LastGroupCon].itemConInfo
    LastOriPosY := LastItemConInfo.OriPosY + LastItemConInfo.SelfOffsetY
    PosY := LastOriPosY + h - tableItem.FoldOffsetArr[foldIndex]
    MySoftData.TabCtrl.UseTab(tableItem.Index)
    LoadItemFoldTitle(tableItem, foldIndex + 1, PosY)
    MySoftData.TabCtrl.UseTab()

    if (isMenu)
        OnItemAddMenuItem(tableItem, foldIndex + 1)

    MySlider.RefreshTab()
}

OnItemAddMenuItem(tableItem, foldIndex) {
    RecycleTabItem(tableItem)
    loop 8 {
        foldInfo := tableItem.FoldInfo
        isMenu := CheckIsMenuMacroTable(tableItem.Index)
        titleHeight := isMenu ? 85 : 55
        AddIndex := GetFoldAddItemIndex(foldInfo, foldIndex)

        isFirst := foldInfo.IndexSpanArr[foldIndex] == "无-无"
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
        tableItem.SerialArr.InsertAt(AddIndex, GetCMDSerialStr("Item"))
        tableItem.TimingSerialArr.InsertAt(AddIndex, GetCMDSerialStr("Timing"))
        tableItem.StartTipSoundArr.InsertAt(AddIndex, 0)
        tableItem.EndTipSoundArr.InsertAt(AddIndex, 0)
        tableItem.IsWorkIndexArr.InsertAt(AddIndex, 0)
        tableItem.GifPathArr.InsertAt(AddIndex, "")
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

        PosY := 1000000
        for index, value in tableItem.AllConArr {
            if (foldIndex == value.FoldIndex && PosY > value.OriPosY)
                PosY := value.OriPosY
        }

        PosY += titleHeight
        if (isFirst) {
            MySoftData.TabCtrl.UseTab(tableItem.Index)
            LoadItemFoldTip(tableItem, foldIndex, PosY)
            MySoftData.TabCtrl.UseTab()
        }

        afterHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
        tableItem.AllGroup[foldIndex].Move(, , , afterHei)

        addHei := isFirst ? 75 : 40
        tableItem.FoldOffsetArr[foldIndex] += addHei
    }
}

;删除模块
OnItemDelFoldBtnClick(tableItem, btn, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[btn].itemConInfo.FoldIndex

    result := MsgBox(GetLang("是否删除当前模块以及模块中所有的宏配置"), GetLang("提示"), 1)
    if (result == "Cancel")
        return

    if (foldInfo.IndexSpanArr.Length == 1) {
        MsgBox(GetLang("最后一个模块，不可删除！！！"))
        return
    }

    RecycleTabItem(tableItem)
    hasSetting := foldInfo.IndexSpanArr[foldIndex] != "无-无"
    if (hasSetting) {
        IndexSpan := StrSplit(foldInfo.IndexSpanArr[foldIndex], "-")
        loop IndexSpan[2] - IndexSpan[1] + 1 {
            itemIndex := IndexSpan[2] - A_Index + 1
            OnItemDelMacro(tableItem, itemIndex, foldInfo, foldIndex)
        }
    }

    UpdateConFoldIndex(tableItem, foldIndex, false)
    foldInfo.RemarkArr.RemoveAt(foldIndex)
    foldInfo.FrontInfoArr.RemoveAt(foldIndex)
    foldInfo.IndexSpanArr.RemoveAt(foldIndex)
    foldInfo.ForbidStateArr.RemoveAt(foldIndex)
    foldInfo.FoldStateArr.RemoveAt(foldIndex)
    foldInfo.TKTypeArr.RemoveAt(foldIndex)
    foldInfo.TKArr.RemoveAt(foldIndex)
    foldInfo.HoldTimeArr.RemoveAt(foldIndex)
    tableItem.FoldOffsetArr.RemoveAt(foldIndex)
    tableItem.AllGroup.RemoveAt(foldIndex)
    MySlider.RefreshTab()
}

;编辑字串宏触发键
OnItemEditTriggerStr(tableItem, index, *) {
    triggerStr := tableItem.TKArr[index]

    SureAction(sureTriggerKey) {
        tableItem.TKArr[index] := sureTriggerKey
        ItemUsePool := ItemUseConPoolMap[tableItem.Index]
        if (ItemUsePool.Has(index)) {
            ItemConObj := ItemUsePool[index]
            ItemConObj.TKBtnCon.Text := sureTriggerKey == "" ? GetLang("编辑") : sureTriggerKey
        }
    }

    MyTriggerStrGui.SaveBtnAction := OnSaveSetting
    MyTriggerStrGui.SureBtnAction := SureAction
    MyTriggerStrGui.ShowGui(triggerStr, 0, false)
}

;自定义编辑触发按键
OnItemCustomEditTriggerStr(tableItem, index, *) {
    isNormal := CheckIsNormalTable(tableItem.Index)
    if (!isNormal)
        return

    CustomTK := InputBox(GetLang("请输入自定义触发按键："), "修改", "w300 h100", tableItem.TKArr[index])

    ; 检查用户是否取消输入
    if CustomTK.Result = "Cancel"
        return
    tableItem.TKArr[index] := CustomTK.Value
    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    if (ItemUsePool.Has(index)) {
        ItemConObj := ItemUsePool[index]
        ItemConObj.TKBtnCon.Text := CustomTK.Value == "" ? GetLang("编辑") : CustomTK.Value
    }
}

;编辑按键宏触发键
OnItemEditTriggerKey(tableItem, index, *) {
    triggerKey := tableItem.TKArr[index]

    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        tableItem.TKArr[index] := sureTriggerKey
        tableItem.HoldTimeArr[index] := timeValue
        tableItem.UnorderedTriggerArr[index] := unorderedTrigger
        ItemUsePool := ItemUseConPoolMap[tableItem.Index]
        if (ItemUsePool.Has(index)) {
            ItemConObj := ItemUsePool[index]
            ItemConObj.TKBtnCon.Text := sureTriggerKey == "" ? GetLang("编辑") : sureTriggerKey
        }
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := tableItem.UnorderedTriggerArr.Has(index) ? tableItem.UnorderedTriggerArr[index] : false
    MyTriggerKeyGui.ShowGui(triggerKey, tableItem.HoldTimeArr[index], false)
}

;编辑定时器
OnItemEditTiming(tableItem, index, *) {
    SerialStr := tableItem.TimingSerialArr[index]
    MyTimingGui.ShowGui(SerialStr)
}

OnItemEditMacroSetting(tableItem, index, *) {
    MyMacroSettingGui.OwnerHwnd := MySoftData.MyGui.Hwnd
    MyMacroSettingGui.ShowGui(tableItem.Index, index)
}

OnItemMenuMacroSettingClick(tableItem, index, *) {
    MyMenuMacroSettingGui.ShowGui(tableItem.Index, index)
}

OnItemEditMacro(tableItem, index, *) {
    macro := tableItem.MacroArr[index]

    SureAction(sureMacro) {
        tableItem.MacroArr[index] := sureMacro
    }

    MySoftData.SpecialTableItem.ModeArr[1] := tableItem.ModeArr[index]
    if (MyMacroGui.Gui != "") {
        style := WinGetStyle(MyMacroGui.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (isVisible) {    ;存在并且显示的话，就打开第二个编辑界面
            MacroGui := MacroEditGui()
            MacroGui.SureFocusCon := MySoftData.BtnSave
            MacroGui.SureBtnAction := SureAction
            MacroGui.SaveBtnAction := OnSaveSetting
            MacroGui.ShowGui(macro, true)
            return
        }
    }
    MyMacroGui.SureFocusCon := MySoftData.BtnSave
    MyMacroGui.SureBtnAction := SureAction
    MyMacroGui.SaveBtnAction := OnSaveSetting
    MyMacroGui.ShowGui(macro, true)
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
    RecycleTabItem(tableItem)
    SwapTableContent(tableItem, index, index - 1)
    UpdateItemConPos(tableItem, true)
}

OnItemMoveDown(tableItem, index, *) {
    lastIndex := tableItem.ModeArr.length
    if (lastIndex == index) {
        MsgBox(GetLang("下面没有元素，无法下移！！！"))
        return
    }
    RecycleTabItem(tableItem)
    SwapTableContent(tableItem, index, index + 1)
    UpdateItemConPos(tableItem, true)
}

OnFoldRemarkChange(tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    foldInfo.RemarkArr[foldIndex] := con.text
}

OnFoldFrontInfoChange(tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    foldInfo.FrontInfoArr[foldIndex] := con.text
}

OnFoldFrontInfoEdit(tableItem, FrontCon, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    MyFrontInfoGui.SureAction := () => foldInfo.FrontInfoArr[foldIndex] := FrontCon.text
    MyFrontInfoGui.ShowGui(FrontCon, true)
}

OnFoldForbidChange(tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    foldInfo.ForbidStateArr[foldIndex] := con.Value
}

OnFoldBtnClick(tableItem, btn, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[btn].itemConInfo.FoldIndex
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    beforeHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    state := !foldInfo.FoldStateArr[foldIndex]
    foldInfo.FoldStateArr[foldIndex] := state
    afterHei := GetFoldGroupHeight(foldInfo, foldIndex, isMenu)
    tableItem.FoldOffsetArr[foldIndex] += afterHei - beforeHei

    btnStr := FoldInfo.FoldStateArr[foldIndex] ? "🞃" : "❯"
    tableItem.FoldBtnArr[foldIndex].Text := btnStr

    tableItem.AllGroup[foldIndex].Move(, , , afterHei)
    MySlider.RefreshTab()
}

OnFlodTKTypeChange(tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    foldInfo.TKTypeArr[foldIndex] := con.Value
}

OnFlodTKChange(tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    foldInfo.TKArr[foldIndex] := con.Value
}

OnFlodTKEditClick(TKEditCon, tableItem, con, *) {
    foldInfo := tableItem.FoldInfo
    foldIndex := tableItem.ConIndexMap[con].itemConInfo.FoldIndex
    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        TKEditCon.Value := sureTriggerKey
        foldInfo.TKArr[foldIndex] := sureTriggerKey
        foldInfo.HoldTimeArr[foldIndex] := timeValue
        foldInfo.UnorderedTriggerArr[foldIndex] := unorderedTrigger
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := foldInfo.UnorderedTriggerArr.Has(foldIndex) ? foldInfo.UnorderedTriggerArr[foldIndex] : false
    MyTriggerKeyGui.ShowGui(TKEditCon.Value, foldInfo.HoldTimeArr[foldIndex], false)
}

;刷新函数
UpdateItemConPos(tableItem, isDown) {
    hwnd := MySoftData.MyGui.Hwnd
    DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)

    loop tableItem.AllConArr.Length {
        Index := isDown ? A_Index : tableItem.AllConArr.Length - A_Index + 1
        ConInfo := tableItem.AllConArr[Index]
        ConInfo.UpdatePos(tableItem.OffSetPosY)
    }

    for index, value in tableItem.AllGroup {
        RefreshTabItem(tableItem)
        RefreshGroupItem(tableItem, Index)
        value.Redraw()
    }

    DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "UInt", 0)
}

HandleItemTopLabel(foldInfo, tableItem, foldIndex) {
    isNull := foldInfo.IndexSpanArr[foldIndex] == "无-无"
    if (!isNull)
        return

    for index, value in tableItem.AllConArr {
        if (value.FoldIndex != foldIndex)
            continue
        if (value.IsTitle)
            continue

        value.Hide()
    }
}

UpdateConFoldIndex(tableItem, FoldIndex, IsAdd) {
    tableItem.AllGroup[FoldIndex].GetPos(&x, &y, &w, &h)
    DelOffsetY := h - tableItem.FoldOffsetArr[FoldIndex]

    for index, value in tableItem.AllConArr {
        if (isAdd) {
            if (value.FoldIndex <= FoldIndex)
                continue

            value.FoldIndex += 1
        }
        else {
            if (value.FoldIndex < FoldIndex)
                continue

            if (value.FoldIndex == FoldIndex)
                value.Hide()

            if (value.FoldIndex > FoldIndex) {
                value.FoldIndex -= 1
                value.DelAfterOffset(DelOffsetY)
            }
        }
    }
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
                ;已经存在后面数字加1
                if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
                    IndexSpan[2] := IndexSpan[2] + 1
                }
                else {  ;不存在直接初始化
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

;封装方法
GetFoldGroupHeight(FoldInfo, index, isMenu) {
    height := isMenu ? 85 : 55
    if (FoldInfo.FoldStateArr[index])
        return height
    IndexSpan := StrSplit(FoldInfo.IndexSpanArr[index], "-")
    if (!IsInteger(IndexSpan[1]) || !IsInteger(IndexSpan[2]))
        return height

    height := height + 25
    height := height + (IndexSpan[2] - IndexSpan[1] + 1) * 40
    return height
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

;无尽列表调整方法
LoadTabSingleItem(tableItem, ItemConObj) {
    MyGui := MySoftData.MyGui
    TabPosX := MySoftData.TabPosX
    tableIndex := tableItem.Index
    isMacro := CheckIsMacroTable(tableIndex)
    isNormal := CheckIsNormalTable(tableIndex)
    isTriggerStr := CheckIsStringMacroTable(tableIndex)
    isTiming := CheckIsTimingMacroTable(tableIndex)
    isMenu := CheckIsMenuMacroTable(tableIndex)
    isSubMacro := CheckIsSubMacroTable(tableIndex)
    isNoTriggerKey := CheckIsNoTriggerKey(tableIndex)
    isUI := GetTableSymbol(tableIndex) == "UI"

    MySoftData.TabCtrl.UseTab(tableItem.Index)
    ;颜色
    ColorCon := MyGui.Add("Pic", Format("x{} y{} w{} h27", TabPosX + 20, -1000, 29),
    "Images\Soft\GreenColor.png")
    ColorCon.Visible := false
    ColorCon.OriPosX := TabPosX + 20

    ;序号
    IndexCon := MyGui.Add("Text", Format("x{} y{} w{} +BackgroundTrans", TabPosX + 20, -1000, 30), 0 ".")
    IndexCon.OffsetY := 5
    IndexCon.OriPosX := TabPosX + 20

    ;备注
    RemarkCon := MyGui.Add("Edit", Format("x{} y{} w180", TabPosX + 60, -1000), "")
    RemarkCon.OriPosX := TabPosX + 60

    ;触发按键
    btnStr := isTiming ? GetLang("定时") : GetLang("编辑")
    TKBtnCon := MyGui.Add("Button", Format("x{} y{} w100 h29", TabPosX + 250, -1000), btnStr)
    TKBtnCon.Enabled := !isSubMacro
    TKBtnCon.OffsetY := -1
    TKBtnCon.OriPosX := TabPosX + 250

    ;触发类型
    TKTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", TabPosX + 360, -1000, 70),
    GetLangArr(["按下", "松开", "松止", "开关", "长按", "双击"]))
    TKTypeCon.Enabled := isNormal
    TKTypeCon.OriPosX := TabPosX + 360

    ;循环次数
    LoopCon := MyGui.Add("ComboBox", Format("x{} y{} w60 R5 center", TabPosX + 440, -1000), GetLangArr(["无限"]))
    LoopCon.Text := GetLang("无限")
    LoopCon.Enabled := isMacro
    LoopCon.OriPosX := TabPosX + 440

    SettingCon := MyGui.Add("Button", Format("x{} y{} w60 h29", TabPosX + 510, -1000), GetLang("设置"))
    SettingCon.OffsetY := -1
    SettingCon.OriPosX := TabPosX + 510

    ;编辑
    EditCon := MyGui.Add("Button", Format("x{} y{} w60 h29", TabPosX + 575, -1000 - 1), GetLang("编辑"))
    EditCon.OffsetY := -1
    EditCon.OriPosX := TabPosX + 575

    ;上
    PreCon := MyGui.Add("Button", Format("x{} y{} w20 h28", TabPosX + 700, -1000), "↑")
    PreCon.OriPosX := TabPosX + 650

    ;下
    NextCon := MyGui.Add("Button", Format("x{} y{} w20 h28", TabPosX + 725, -1000), "↓")
    NextCon.OriPosX := TabPosX + 675

    ;禁用
    ForbidCon := MyGui.Add("Checkbox", Format("x{} y{}", TabPosX + 735, -1000), GetLang("禁用"))
    ForbidCon.OffsetY := 4
    ForbidCon.OriPosX := TabPosX + 705

    ;复制
    CopyCon := MyGui.Add("Button", Format("x{} y{} w50 h29", TabPosX + 785, -1000), GetLang("复制"))
    CopyCon.OffsetY := -1
    CopyCon.OriPosX := TabPosX + 765

    ;删除
    DelCon := MyGui.Add("Button", Format("x{} y{} w50 h29", TabPosX + 810, -1000), GetLang("删除"))
    DelCon.Enabled := !isMenu
    DelCon.OffsetY := -1
    DelCon.OriPosX := TabPosX + 820

    ;分割线
    LineCon := ""
    if (MySoftData.ShowSplitLine) {
        LineCon := MyGui.Add("Text", Format("x{} y{} w870 h1 0x10", TabPosX + 20, -1000), "") ; SS_ETCHEDHORZ
        LineCon.OffsetY := 32
        LineCon.OriPosX := TabPosX + 20
    }

    ItemConObj.ColorCon := ColorCon
    ItemConObj.IndexCon := IndexCon
    ItemConObj.RemarkCon := RemarkCon
    ItemConObj.TKBtnCon := TKBtnCon
    ItemConObj.TKTypeCon := TKTypeCon
    ItemConObj.LoopCon := LoopCon
    ItemConObj.SettingCon := SettingCon
    ItemConObj.EditCon := EditCon
    ItemConObj.PreCon := PreCon
    ItemConObj.NextCon := NextCon
    ItemConObj.ForbidCon := ForbidCon
    ItemConObj.CopyCon := CopyCon
    ItemConObj.DelCon := DelCon
    ItemConObj.LineCon := LineCon

    ;所有宏类型使用相同的控件数组
    ItemConObj.ConArr := [ColorCon, IndexCon, RemarkCon, TKBtnCon, TKTypeCon, LoopCon, SettingCon,
        EditCon, PreCon, NextCon, ForbidCon, CopyCon, DelCon, LineCon]

    MySoftData.TabCtrl.UseTab()
}

RefreshTabItem(tableItem) {
    isItem := CheckIsItemTable(tableItem.Index)
    if (!isItem)
        return

    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    FoldInfo := tableItem.FoldInfo
    ;因为遍历里面涉及对ItemUsePool的Delete操作，会影响遍历操作
    UsePool := ItemUsePool.Clone()
    for index, ItemConObj in UsePool {
        foldIndex := GetItemFoldIndex(tableItem, index)
        isFold := foldIndex == 0 ? true : FoldInfo.FoldStateArr[foldIndex]
        if (isFold) {
            RecycleTabSingleItem(tableItem, index)
            continue
        }

        FoldCon := tableItem.AllGroup[foldIndex]
        FoldCon.GetPos(&FoldX, &FoldY, &w, &h)
        IndexSpanStr := FoldInfo.IndexSpanArr[foldIndex]
        IndexSpan := StrSplit(IndexSpanStr, "-")
        isMenu := CheckIsMenuMacroTable(tableItem.Index)
        titleHeight := isMenu ? 105 : 75
        OffsetNum := index - IndexSpan[1]
        PosY := OffsetNum * 40 + titleHeight + FoldY
        isOverScreen := PosY < -50 || PosY > 600
        if (isOverScreen || isFold) {
            RecycleTabSingleItem(tableItem, index)
            continue
        }

        for Index, Con in ItemConObj.ConArr {
            if (Con == "")
                continue

            SelfOffsetY := ObjHasOwnProp(Con, "OffsetY") ? Con.OffsetY : 0
            Con.Move(Con.OriPosX, PosY + SelfOffsetY)
        }
    }
}

RefreshGroupItem(tableItem, foldIndex) {
    isItem := CheckIsItemTable(tableItem.Index)
    if (!isItem)
        return

    FoldInfo := tableItem.FoldInfo
    isFold := FoldInfo.FoldStateArr[foldIndex]
    if (isFold)
        return

    FoldCon := tableItem.AllGroup[foldIndex]
    FoldCon.GetPos(&FoldX, &FoldY, &w, &h)
    if (FoldY + h < -50 || FoldY > 600)
        return

    IndexSpanStr := FoldInfo.IndexSpanArr[foldIndex]
    IndexSpan := StrSplit(IndexSpanStr, "-")
    if (!IsInteger(IndexSpan[1]) || !IsInteger(IndexSpan[2]))
        return

    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    titleHeight := isMenu ? 105 : 75
    loop IndexSpan[2] - IndexSpan[1] + 1 {
        itemIndex := IndexSpan[1] + A_Index - 1
        PosY := (A_Index - 1) * 40 + titleHeight + FoldY
        if (PosY < -50 || PosY > 600)
            continue

        ItemConObj := GetItemConObj(tableItem, itemIndex)
        for Index, Con in ItemConObj.ConArr {
            if (Con == "")
                continue

            SelfOffsetY := ObjHasOwnProp(Con, "OffsetY") ? Con.OffsetY : 0
            Con.Move(Con.OriPosX, PosY + SelfOffsetY)
        }
    }
}

GetItemConObj(tableItem, itemIndex) {
    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    if (ItemUsePool.Has(itemIndex))
        return ItemUsePool[itemIndex]

    ItemFreeArr := ItemFreeConPoolMap[tableItem.Index]
    if (ItemFreeArr.Length == 0) {
        ItemConObj := Object()
        LoadTabSingleItem(tableItem, ItemConObj)
        ItemFreeArr.Push(ItemConObj)
    }
    ItemConObj := ItemFreeArr.Pop()
    ItemUsePool.Set(itemIndex, ItemConObj)

    isTiming := CheckIsTimingMacroTable(tableItem.Index)
    isMacro := CheckIsMacroTable(tableItem.Index)
    isTriggerStr := CheckIsStringMacroTable(tableItem.Index)
    isUI := GetTableSymbol(tableItem.Index) == "UI"
    isMenu := CheckIsMenuMacroTable(tableItem.Index)
    TKBtnStr := isTiming ? GetLang("定时") : tableItem.TKArr[ItemIndex]
    TKBtnStr := TKBtnStr == "" ? GetLang("编辑") : TKBtnStr
    LoopStr := tableItem.LoopCountArr[ItemIndex] == "-1" ? GetLang("无限") : tableItem.LoopCountArr[ItemIndex]
    EditTKAction := isTriggerStr ? OnItemEditTriggerStr : OnItemEditTriggerKey
    EditTKAction := isTiming ? OnItemEditTiming : EditTKAction
    EditTKAction := isMenu ? OnItemMenuMacroSettingClick : EditTKAction
    EditMacroAction := isMacro ? OnItemEditMacro : OnItemEditReplaceKey

    ItemConObj.ColorCon.Value := GetItemColorValue(tableItem.ColorStateArr[itemIndex])
    ItemConObj.ColorCon.Visible := tableItem.ColorStateArr[itemIndex] != 0
    ItemConObj.IndexCon.Value := itemIndex "."
    ItemConObj.RemarkCon.Value := tableItem.RemarkArr[ItemIndex]
    ItemConObj.TKBtnCon.Text := TKBtnStr
    ItemConObj.TKTypeCon.Value := tableItem.TriggerTypeArr[ItemIndex]
    ItemConObj.LoopCon.Text := LoopStr
    ItemConObj.ForbidCon.Value := tableItem.ForbidArr[ItemIndex]

    if (isUI) {
        ;UI宏：触发类型固定为"开关"（索引4）
        tableItem.TriggerTypeArr[itemIndex] := 4
        ItemConObj.TKTypeCon.Value := 4
        ItemConObj.TKTypeCon.Enabled := false

        ;UI宏：触发编辑器打开界面宏按钮配置（参考定时宏的处理方式）
        EditTKAction := OnUIMacroSettingClick.bind(tableItem, itemIndex)
    }

    TabItemOnEvent(ItemConObj.TKBtnCon, "Click", EditTKAction.bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.TKBtnCon, "ContextMenu", OnItemCustomEditTriggerStr.bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.SettingCon, "Click", OnItemEditMacroSetting.Bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.EditCon, "Click", EditMacroAction.bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.PreCon, "Click", OnItemMoveUp.Bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.NextCon, "Click", OnItemMoveDown.Bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.CopyCon, "Click", OnItemCopyMacroBtnClick.bind(tableItem, itemIndex))
    TabItemOnEvent(ItemConObj.DelCon, "Click", OnItemDelMacroBtnClick.bind(tableItem, itemIndex))
    return ItemConObj
}

TabItemOnEvent(Con, EventName, Callback) {
    ;先删除之前绑定的事件
    EventAtr := EventName "Action"
    if (ObjHasOwnProp(Con, EventAtr)) {
        if (EventName == "Click")
            Con.OnEvent(EventName, Con.ClickAction, 0)
        if (EventName == "ContextMenu")
            Con.OnEvent(EventName, Con.ContextMenuAction, 0)
    }

    if (EventName == "Click")
        Con.ClickAction := Callback
    if (EventName == "ContextMenu")
        Con.ContextMenuAction := Callback

    Con.OnEvent(EventName, Callback)
}

RecycleTabItem(tableItem) {
    if (!ItemUseConPoolMap.Has(tableItem.Index))
        return

    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    FoldInfo := tableItem.FoldInfo
    ;因为遍历里面涉及对ItemUsePool的Delete操作，会影响遍历操作
    UsePool := ItemUsePool.Clone()
    for itemIndex, ItemConObj in UsePool {
        RecycleTabSingleItem(tableItem, itemIndex)
    }
}

RecycleTabSingleItem(tableItem, itemIndex) {
    ItemUsePool := ItemUseConPoolMap[tableItem.Index]
    if (!ItemUsePool.Has(itemIndex))
        return

    ItemFreeArr := ItemFreeConPoolMap[tableItem.Index]
    ItemConObj := ItemUsePool[itemIndex]
    ItemUsePool.Delete(itemIndex)
    ItemFreeArr.Push(ItemConObj)

    ColorState := GetItemColorState(ItemConObj.ColorCon.Value)
    ColorState := ItemConObj.ColorCon.Visible ? ColorState : 0
    BtnStr := ItemConObj.TKBtnCon.Text == GetLang("编辑") ? "" : ItemConObj.TKBtnCon.Text
    LoopValue := ItemConObj.LoopCon.Text == GetLang("无限") ? -1 : ItemConObj.LoopCon.Text

    ;记录可能修改的值
    tableItem.ColorStateArr[itemIndex] := ColorState
    tableItem.TKArr[itemIndex] := BtnStr
    tableItem.TriggerTypeArr[itemIndex] := ItemConObj.TKTypeCon.Value
    tableItem.ForbidArr[itemIndex] := ItemConObj.ForbidCon.Value
    tableItem.RemarkArr[itemIndex] := ItemConObj.RemarkCon.Value
    tableItem.LoopCountArr[itemIndex] := LoopValue

    for Index, Con in ItemConObj.ConArr {
        if (Con == "")
            continue
        Con.Move(Con.OriPosX, -1000)
    }
}

OnUIMacroSettingClick(tableItem, macroIndex, *) {
    MyUIMacroSettingGui.SaveBtnAction := OnSaveSetting
    MyUIMacroSettingGui.ShowGui(tableItem, macroIndex)
}