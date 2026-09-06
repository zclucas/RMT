#Requires AutoHotkey v2.0
#Include ..\Main\Util\JsonUtil.ahk

; §17/§18 热重载广播封装：调用方须已更新内存模型；总线空闲时统一派发各订阅者
; （触发键重绑 / Worker CF / 语音重建 / 定时重建 / UI宏刷新），与折叠头 FoldTK 同生效链路
; §18 宏表即时持久化：宏表（非静态表）编辑 → 立即落盘（SaveTableItemInfo 整文件读-改-原子写），
; 不再依赖「应用并保存」；「应用并保存」只处理全局非热重载数据
HotReloadPublish(tableIndex, itemIndex := 0) {
    global MyHotReloadBus, MySoftData
    if (tableIndex >= 1 && IsObject(MySoftData) && MySoftData.HasProp("TableInfo")
        && tableIndex <= MySoftData.TableInfo.Length) {
        tableItem := MySoftData.TableInfo[tableIndex]
        if (IsObject(tableItem) && !IsStaticTable(tableItem)) {
            try {
                SaveTableItemInfo(tableItem)
            } catch as e {
                RMTLogSys(RMT_LV_ERROR, "HotReloadPublish", Format("宏表落盘失败: tab={1} err={2}", tableIndex, e.Message))
            }
        }
    }
    if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
        MyHotReloadBus.Publish(tableIndex, itemIndex)
}

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
    item.FoldID := (foldIndex >= 1 && foldIndex <= tableItem.Folds.Length) ? tableItem.Folds[foldIndex].ID : ""
    ; 路径身份：新宏 = foldSeg.Macro{max+1}（父模块路径）
    item.ID := (item.FoldID != "") ? NewMacroPath(tableItem, item.FoldID) : GetCMDSerialStr("Item")
    item.TimingSerial := GetCMDSerialStr("Timing")
    tableItem.Items.InsertAt(AddIndex, item)

    tableItem.RebuildIndex()
    RebuildTableLocator()
    MyMainWin.RenderTab(tableItem)
    ; §17 热重载：新增宏 live 广播（触发键重绑/语音/定时订阅者空闲重建）
    HotReloadPublish(tableItem.Index, 0)
}

;删除宏配置
OnItemDelMacroBtnClick(tableItem, DelIndex, *) {
    try RmtDialog._Trace("Del click idx=" DelIndex)
    if (!RmtDialog.Confirm(GetLang("是否删除当前宏"), GetLang("提示")))
        return

    MyMainWin.ReadTabValues(tableItem)
    OnItemDelMacro(tableItem, DelIndex)
    MyMainWin.RenderTab(tableItem)
    ; §17 热重载：删除宏 live 广播 → 立即解除旧热键（防索引错位误触发错误宏）
    HotReloadPublish(tableItem.Index, 0)
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
    fold.ID := NewModulePath(tableItem)   ; 路径身份 Normal.Module{max+1}
    tableItem.Folds.InsertAt(foldIndex + 1, fold)

    if (isMenu)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 4)
    else if (isUI)
        OnItemAddMenuItem(tableItem, foldIndex + 1, 3)

    tableItem.RebuildIndex()
    MyMainWin.RenderTab(tableItem)
    ; §17 热重载：新增模块 live 广播（模块开关热键 BindFoldSwitchHotkey 即时重绑）
    HotReloadPublish(tableItem.Index, 0)
}

; 菜单宏/界面宏新增模块时批量预置配置项（菜单默认 4、界面默认 3）
OnItemAddMenuItem(tableItem, foldIndex, count := 4) {
    fold := tableItem.Folds[foldIndex]
    loop count {
        AddIndex := GetFoldAddItemIndex(tableItem, foldIndex)
        item := MacroItem()
        item.FoldID := fold.ID
        ; 路径身份：新宏 = foldSeg.Macro{max+1}（父模块路径）
        item.ID := NewMacroPath(tableItem, fold.ID)
        item.TimingSerial := GetCMDSerialStr("Timing")
        tableItem.Items.InsertAt(AddIndex, item)
    }
    tableItem.RebuildIndex()
    RebuildTableLocator()
}

;删除模块
OnItemDelFoldBtnClick(tableItem, foldIndex, *) {
    try RmtDialog._Trace("FoldDel click idx=" foldIndex)
    if (!RmtDialog.Confirm(GetLang("是否删除当前模块以及模块中所有的宏配置"), GetLang("提示")))
        return

    if (tableItem.Folds.Length == 1) {
        RmtDialog.Info(GetLang("最后一个模块，不可删除！！！"), GetLang("提示"))
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
    ; §17 热重载：删除模块 live 广播 → 立即解除旧模块开关热键（防 foldIndex 错位切换错误模块）
    HotReloadPublish(tableItem.Index, 0)
}

;编辑字串宏触发键
OnItemEditTriggerStr(tableItem, index, *) {
    MyMainWin.ReadTabValues(tableItem)
    item := tableItem.Items[index]
    triggerStr := item.TK

    SureAction(sureTriggerKey) {
        item.TK := sureTriggerKey
        MyMainWin.RenderTab(tableItem)
        ; §17 热重载：字串宏触发键 live 广播 → 立即重绑热键/热串（与折叠头 FoldTK 同链路，不必等保存）
        HotReloadPublish(tableItem.Index, index)
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
    ; §17 热重载：自定义触发串 live 广播 → 立即重绑热键/热串
    HotReloadPublish(tableItem.Index, index)
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
        ; §17 热重载：按键宏触发键 live 广播 → 立即重绑热键（含顺序/反向组合键）
        HotReloadPublish(tableItem.Index, index)
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
        ; §18 宏内容即时持久化 + Worker 热重载：确定即写盘 + 广播 → CF → Worker 重载，不必等保存选「否」
        HotReloadPublish(tableItem.Index, 0)
        MyMainWin.RefreshItemRow(tableItem.Index, index)
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
        ; §18 替换宏内容即时持久化 + Worker 热重载
        HotReloadPublish(tableItem.Index, 0)
        MyMainWin.RefreshItemRow(tableItem.Index, index)
    }

    MyReplaceKeyGui.SureBtnAction := SureAction
    MyReplaceKeyGui.ShowGui(replaceKey)
}

OnItemForbidToggle(tableItem, index, *) {
    item := tableItem.Items[index]
    if (!item)
        return
    MyMainWin.ReadTabValues(tableItem)
    item.Forbid := !item.Forbid
    if (MyMainWin._useVirtual.Has(tableItem.Index))
        MyMainWin._vl.RefreshRow(tableItem.Index, index)
    else
        MyMainWin.RefreshItemRow(tableItem.Index, index)
    HotReloadPublish(tableItem.Index, 0)
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
    ; §17 热重载：上移改变索引 → 重绑触发键（防热键闭包数字索引错位）
    HotReloadPublish(tableItem.Index, 0)
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
    ; §17 热重载：下移改变索引 → 重绑触发键（防热键闭包数字索引错位）
    HotReloadPublish(tableItem.Index, 0)
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
        try {
            if (MyMainWin._useVirtual.Has(tableItem.Index))
                MyMainWin._vl.Init(tableItem.Index, tableItem)
            else
                MyMainWin.ui.Update("FoldFront_" tableItem.Index "_" foldIndex, "Text", newInfo)
        }
        ; §17 热重载：窗口条件（FrontInfo）live 广播 → 重绑热键（HotIfWinActive 新条件即时生效）
        HotReloadPublish(tableItem.Index, 0)
    }
    MyFrontInfoGui.SureAction := SureAction
    MyFrontInfoGui.ShowGui(frontCtrl, true)
}

OnFoldBtnClick(tableItem, foldIndex, *) {
    fold := tableItem.Folds[foldIndex]
    MyMainWin.ReadTabValues(tableItem)
    fold.FoldState := !fold.FoldState
    ; §18 折叠状态即时持久化（UI 状态，不影响触发/执行，只写盘不广播）
    if (!IsStaticTable(tableItem)) {
        try SaveTableItemInfo(tableItem)
        catch as e
            RMTLogSys(RMT_LV_ERROR, "OnFoldBtnClick", Format("折叠状态落盘失败: {1}", e.Message))
    }
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
        ; §18 折叠头触发键即时持久化 + 重绑（与 _ApplyChange FoldTK 同链路）
        HotReloadPublish(tableItem.Index, 0)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := fold.UnorderedTrigger
    MyTriggerKeyGui.ShowGui(fold.TK, fold.HoldTime, false)
}

; §2 模块禁用切换：按钮态（非勾选框）；复用开关热键同链路
OnFoldForbidToggleClick(tableItem, foldIndex, *) {
    MyMainWin.ReadTabValues(tableItem)
    OnFoldSwitchHotkey(tableItem.Index, foldIndex)
}

; §2 模块启用/禁用开关快捷键：弹触发键编辑窗，仅取按键值（切换模块启用状态用，无需长按/顺序语义）
OnFoldForbidHKEditClick(tableItem, foldIndex, *) {
    fold := tableItem.Folds[foldIndex]
    MyMainWin.ReadTabValues(tableItem)
    SureAction(sureTriggerKey, timeValue, unorderedTrigger) {
        fold.ForbidHotkey := sureTriggerKey
        MyMainWin.RenderTab(tableItem)
        ; §18 模块开关热键即时持久化 + 重绑（BindFoldSwitchHotkey 生效）
        HotReloadPublish(tableItem.Index, 0)
    }

    MyTriggerKeyGui.SaveBtnAction := OnSaveSetting
    MyTriggerKeyGui.SureBtnAction := SureAction
    MyTriggerKeyGui.UnorderedTrigger := false
    MyTriggerKeyGui.ShowGui(fold.ForbidHotkey, 500, false)
}

; §11 模块三横杠菜单（行内「新增宏/粘贴宏/新增模块/删除模块」按钮移入此菜单）
OnFoldMenuClick(tableItem, foldIndex, *) {
    MyMainWin.ReadTabValues(tableItem)
    m := Menu()
    m.Add(GetLang("新增宏"), (*) => OnItemAddMacroBtnClick(tableItem, foldIndex))
    m.Add(GetLang("粘贴宏"), (*) => OnItemPasteMacroBtnClick(tableItem, foldIndex))
    m.Add(GetLang("新增模块"), (*) => OnItemAddFoldBtnClick(tableItem, foldIndex))
    m.Add(GetLang("删除模块"), (*) => OnItemDelFoldBtnClick(tableItem, foldIndex))
    m.Show()
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

; ============================================================
; §23 网络触发：条目触发 URL 辅助 + 说明弹窗
; 触发码=条目 ID，动作由 path 决定：
;   开启 http://127.0.0.1:{端口}/macro/{ID}/on   （循环执行，幂等）
;   关闭 http://127.0.0.1:{端口}/macro/{ID}/off  （停止执行，幂等）
; 「按下/单次」对网络宏无意义，UI 不展示（服务端仍兼容 /{ID}）。
; ============================================================

NetworkGetPort() {
    global MainSoftData
    return MainSoftData.HasProp("NetworkPort") ? Integer(MainSoftData.NetworkPort) : 16888
}

; 拼接条目触发 URL（action: "on"/"off"；按当前设置端口，127.0.0.1 固定回环）
NetworkGetTriggerUrl(macroID, action := "on") {
    return "http://127.0.0.1:" NetworkGetPort() "/macro/" macroID "/" action
}

; 复制条目触发 URL 到剪贴板（action: "on"/"off"，成功经 Toast 反馈）
OnItemNetworkCopyUrl(tableItem, index, action := "on", *) {
    item := tableItem.Items[index]
    if (!item || item.ID == "")
        return
    url := NetworkGetTriggerUrl(item.ID, action)
    if (SetClipboard(url))
        Toast.Success(GetLang("已复制：") url)
}

; 网络宏条目触发键列点击/右键：不弹菜单，直接复制「开启」URL（「关闭」URL 在「?」说明弹窗里可复制）

; 网络触发说明弹窗（触发键左侧「?」按钮）：本条目的开/关 URL（可复制）+ 参数/响应/各种情况解释
OnItemNetworkHelp(tableItem, index, *) {
    item := tableItem.Items[index]
    if (!item || item.ID == "")
        return
    NetworkShowHelpDialog(item.ID)
}

; 网络触发说明弹窗。macroID 为空 = 通用模式（设置页入口，URL 用 {条目ID} 占位）；
; 传入条目 ID = 条目模式（网络表「?」按钮，URL 行为该条目的真实链接，可复制）
NetworkShowHelpDialog(macroID := "") {
    port := NetworkGetPort()
    isItem := (macroID != "")
    idPart := isItem ? macroID : "{" GetLang("条目ID") "}"
    urlBase := "http://127.0.0.1:" port "/macro/" idPart
    urlOn := isItem ? NetworkGetTriggerUrl(macroID, "on") : ""
    urlOff := isItem ? NetworkGetTriggerUrl(macroID, "off") : ""
    owner := 0
    try {
        if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.wpfHwnd)
            owner := MyMainWin.ui.wpfHwnd
    }
    try XAMLHost.EnsureDaemonHealthy()

    titleHeight := "36"
    fs := XAMLHost.FontSize()
    winW := 520
    fontFamily := ""
    try {
        if (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            fontFamily := MainSoftData.FontType
    }

    main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
    if (fontFamily != "")
        main.TextElement_FontFamily(fontFamily)
    main.TextElement_FontSize(fs)
    main.Rows(titleHeight, "Auto")

    ; 标题栏（与 RmtDialog 同壳：拖拽区 + 统一关闭钮）
    tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
    tbInner := tb.Add("Grid")
    tbInner.Add("TextBlock").Text(GetLang("网络触发说明")).Foreground("{DynamicResource TitleBarForeground}")
        .FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold").VerticalAlignment("Center").Margin("15,0,0,0").Padding("0")
    btnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right").VerticalAlignment("Stretch").Height(36)
    closeBtn := btnGroup.Add("Button").Name("BtnClosePanel").Style("{StaticResource TitleBarCloseButton}")
        .WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(36).MinHeight(36).Padding("0")
        .VerticalAlignment("Stretch").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
    closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10)
        .VerticalAlignment("Center").HorizontalAlignment("Center")

    body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
    panel := body.Add("StackPanel").Margin("16,12,16,12")

    ; —— 一行解释 ——
    panel.Add("TextBlock").Text(GetLang("用 HTTP 请求触发本宏，参数写入全局变量（文本，允许覆盖）；出错时 body 直接写明原因。"))
        .Foreground("{DynamicResource TextMain}").TextWrapping("Wrap")

    ; —— 本条目的触发 URL（条目模式各带复制按钮；通用模式跳过）——
    if (isItem) {
        for , rowDef in [{label: GetLang("开启（循环执行）"), url: urlOn, btn: "BtnCopyOn"}
                       , {label: GetLang("关闭（停止执行）"), url: urlOff, btn: "BtnCopyOff"}] {
            row := panel.Add("Grid").Margin("0,2,0,2")
            row.Cols("Auto", "*", "Auto")
            row.Add("TextBlock").Grid_Column(0).Text(rowDef.label "：").Foreground("{DynamicResource TextMain}")
                .VerticalAlignment("Center").Margin("0,0,6,0")
            row.Add("TextBlock").Grid_Column(1).Text(rowDef.url).Foreground("{DynamicResource Accent}")
                .VerticalAlignment("Center").TextWrapping("Wrap")
            row.Add("Button").Grid_Column(2).Name(rowDef.btn).Content(GetLang("复制"))
                .Width(56).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
        }
    }

    ; —— 示例（多行，每行可复制；通用模式用 {条目ID} 占位）——
    panel.Add("TextBlock").Text(GetLang("示例")).FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,10,0,2")
    exArr := [urlBase
            , urlBase "/on"
            , urlBase "/off"
            , urlBase "/on?" GetLang("窗口标题") "=文档1&" GetLang("次数") "=3"
            , 'curl -X POST -H "Content-Type: application/json" -d "{\"窗口标题\":\"文档1\"}" ' urlBase]
    exIdx := 0
    for , ex in exArr {
        exIdx++
        exRow := panel.Add("Grid").Margin("0,2,0,2")
        exRow.Cols("*", "Auto")
        exRow.Add("TextBlock").Grid_Column(0).Text(ex).Foreground("{DynamicResource TextMain}")
            .VerticalAlignment("Center").TextWrapping("Wrap")
        exRow.Add("Button").Grid_Column(1).Name("BtnEx" exIdx).Content(GetLang("复制"))
            .Width(56).Height(24).MinHeight(24).Margin("8,0,0,0").Cursor("Hand")
    }

    ; —— 底部确定按钮 ——
    btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,14,0,4")
    okBtn := btnRow.Add("Button").Name("BtnOk").Content(GetLang("确定"))
        .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
        .FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        .FontSize(fs).Cursor("Hand").Width(80).Height(32)
    PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    okBtn.InjectResources(PrimaryBtnStyle)

    tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
    ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
    safeTitle := RmtDialog._XmlEsc(GetLang("网络触发说明"))
    ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False" Width="' winW '" SizeToContent="Height" Opacity="0"')
    ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
    if (fontFamily != "")
        ui.xaml := StrReplace(ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' fontFamily '"')
    ui.xaml := StrReplace(ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
    ui.xaml := StrReplace(ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

    resultObj := { Button: "" }
    closeDlg := (btnText) => RmtDialog._OnPick(ui, resultObj, btnText, owner)
    ui.OnEvent("Window", "Closing", (state, ctrl, event) => RmtDialog._OnClosing(resultObj, owner))
    ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => RmtDialog._OnLoad(ui, owner))
    ui.OnEvent("BtnClosePanel", "Click", (state, ctrl, event) => closeDlg("Closed"))
    ui.OnEvent("BtnOk", "Click", (state, ctrl, event) => closeDlg(GetLang("确定")))
    if (isItem) {
        ui.OnEvent("BtnCopyOn", "Click", (*) => OnItemNetworkCopyClipboard(urlOn, GetLang("已复制开启 URL")))
        ui.OnEvent("BtnCopyOff", "Click", (*) => OnItemNetworkCopyClipboard(urlOff, GetLang("已复制关闭 URL")))
    }
    for n, ex in exArr
        ui.OnEvent("BtnEx" n, "Click", OnItemNetworkCopyClipboardEx.Bind(ex))

    if (!XamlWin.Open(ui, "", owner))
        throw Error("网络触发说明弹窗打开失败")
    ownerDisabled := false
    while (resultObj.Button == "" && WinExist("ahk_id " ui.wpfHwnd)) {
        if (ui.wpfHwnd && owner && !ownerDisabled) {
            try WinSetEnabled(0, "ahk_id " owner)
            ownerDisabled := true
        }
        Sleep(50)
    }
    if (owner)
        try WinSetEnabled(1, "ahk_id " owner)
}

OnItemNetworkCopyClipboard(text, tip) {
    if (SetClipboard(text))
        Toast.Success(tip)
}

; 弹窗示例行复制按钮用（OnEvent 会附带事件参数，须可变参接收）
OnItemNetworkCopyClipboardEx(text, *) {
    OnItemNetworkCopyClipboard(text, GetLang("已复制"))
}

; ============================================================
; §23 网络宏设置窗口（设置页底部按钮组「网络宏设置」）
; 仅承载网络宏相关参数：监听端口 / 监听地址 / 端口冲突红字
; ============================================================
NetworkShowSettingDialog() {
    global MainSoftData
    owner := 0
    try {
        if (IsSet(MyMainWin) && IsObject(MyMainWin) && IsObject(MyMainWin.ui) && MyMainWin.ui.wpfHwnd)
            owner := MyMainWin.ui.wpfHwnd
    }
    try XAMLHost.EnsureDaemonHealthy()

    titleHeight := "36"
    fs := XAMLHost.FontSize()
    winW := 400
    fontFamily := ""
    try {
        if (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            fontFamily := MainSoftData.FontType
    }

    main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
    if (fontFamily != "")
        main.TextElement_FontFamily(fontFamily)
    main.TextElement_FontSize(fs)
    main.Rows(titleHeight, "Auto")

    ; 标题栏（与说明弹窗同壳）
    tb := main.Add("Border").Grid_Row(0).Background("{DynamicResource TitleBarColor}").Name("DragArea")
    tbInner := tb.Add("Grid")
    tbInner.Add("TextBlock").Text(GetLang("网络宏设置")).Foreground("{DynamicResource TitleBarForeground}")
        .FontSize(XAMLHost.TitleFontSize()).FontWeight("Bold").VerticalAlignment("Center").Margin("15,0,0,0").Padding("0")
    btnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right").VerticalAlignment("Stretch").Height(36)
    closeBtn := btnGroup.Add("Button").Name("BtnClosePanel").Style("{StaticResource TitleBarCloseButton}")
        .WindowChrome_IsHitTestVisibleInChrome("True").Width(46).Height(36).MinHeight(36).Padding("0")
        .VerticalAlignment("Stretch").Background("Transparent").Foreground("{DynamicResource TitleBarForeground}").BorderThickness(0)
    closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10)
        .VerticalAlignment("Center").HorizontalAlignment("Center")

    body := main.Add("Border").Grid_Row(1).Background("{DynamicResource BgColor}")
    panel := body.Add("StackPanel").Margin("16,12,16,12")

    ; —— 监听端口 ——
    row1 := panel.Add("Grid").Margin("0,2,0,2")
    row1.Cols("Auto", "Auto")
    row1.Add("TextBlock").Grid_Column(0).Text(GetLang("监听端口：")).Foreground("{DynamicResource TextMain}")
        .VerticalAlignment("Center").Margin("0,0,6,0")
    row1.Add("TextBox").Grid_Column(1).Name("EditNetPort").Text(String(MainSoftData.NetworkPort))
        .Width(100).Height(26).MinHeight(26).Padding("4,0").VerticalContentAlignment("Center")
        .FontSize(12).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
        .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")

    ; —— 监听地址（只读）——
    row2 := panel.Add("Grid").Margin("0,6,0,2")
    row2.Cols("Auto", "Auto")
    row2.Add("TextBlock").Grid_Column(0).Text(GetLang("监听地址：")).Foreground("{DynamicResource TextMain}")
        .VerticalAlignment("Center").Margin("0,0,6,0")
    row2.Add("TextBox").Grid_Column(1).Text("127.0.0.1").IsReadOnly("True")
        .Width(100).Height(26).MinHeight(26).Padding("4,0").VerticalContentAlignment("Center")
        .FontSize(12).Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
        .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        .ToolTip(GetLang("默认仅监听本机回环地址，保证安全；外部设备无法访问"))

    ; —— 状态红字（端口冲突 / 校验错误，正常时隐藏）——
    panel.Add("TextBlock").Name("TxtNetBindError").Text("").Foreground("Red").FontSize(11)
        .Margin("0,8,0,0").Visibility("Collapsed").TextWrapping("Wrap")

    ; —— 底部按钮：保存 / 关闭 ——
    btnRow := panel.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,14,0,4")
    saveBtn := btnRow.Add("Button").Name("BtnNetSave").Content(GetLang("保存"))
        .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
        .FontWeight("Bold").BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1")
        .FontSize(fs).Cursor("Hand").Width(80).Height(32).Margin("0,0,12,0")
    closeBtn2 := btnRow.Add("Button").Name("BtnNetClose").Content(GetLang("关闭"))
        .FontSize(fs).Cursor("Hand").Width(80).Height(32)
    PrimaryBtnStyle := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionHoverBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource ActionPressBg}"/><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource ActionHoverStroke}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    saveBtn.InjectResources(PrimaryBtnStyle)

    tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
    ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", owner)
    safeTitle := RmtDialog._XmlEsc(GetLang("网络宏设置"))
    ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' safeTitle '" ShowInTaskbar="False" Width="' winW '" SizeToContent="Height" Opacity="0"')
    ui.xaml := StrReplace(ui.xaml, 'ResizeMode="CanResize"', 'ResizeMode="NoResize"')
    if (fontFamily != "")
        ui.xaml := StrReplace(ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' fontFamily '"')
    ui.xaml := StrReplace(ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
    ui.xaml := StrReplace(ui.xaml, '%resources%', '<CornerRadius x:Key="PanelRadius">8</CornerRadius>')

    resultObj := { Button: "" }
    closeDlg := (btnText) => RmtDialog._OnPick(ui, resultObj, btnText, owner)
    ui.OnEvent("Window", "Closing", (state, ctrl, event) => RmtDialog._OnClosing(resultObj, owner))
    ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => RmtDialog._OnLoad(ui, owner))
    ui.OnEvent("BtnClosePanel", "Click", (state, ctrl, event) => closeDlg("Closed"))
    ui.OnEvent("BtnNetClose", "Click", (state, ctrl, event) => closeDlg("Closed"))
    ui.OnEvent("BtnNetSave", "Click", (state, ctrl, event) => NetworkApplyNetSetting(ui, closeDlg))
    ; 打开即显示当前端口冲突状态（如有）
    NetworkSetNetDialogError(ui, NetworkGetBindError())

    if (!XamlWin.Open(ui, "", owner))
        throw Error("网络宏设置窗口打开失败")
    ownerDisabled := false
    while (resultObj.Button == "" && WinExist("ahk_id " ui.wpfHwnd)) {
        if (ui.wpfHwnd && owner && !ownerDisabled) {
            try WinSetEnabled(0, "ahk_id " owner)
            ownerDisabled := true
        }
        Sleep(50)
    }
    if (owner)
        try WinSetEnabled(1, "ahk_id " owner)
}

; 读取监听 bind 错误（无监听对象/无错误返回空串）
NetworkGetBindError() {
    global MyNetworkServer
    err := ""
    try {
        if (IsSet(MyNetworkServer) && IsObject(MyNetworkServer))
            err := MyNetworkServer.GetBindError()
    }
    return err
}

; 设置窗口状态红字（msg 为空隐藏）
NetworkSetNetDialogError(ui, msg) {
    try {
        ui.Update("TxtNetBindError", "Text", RmtDialog._XmlEsc(msg))
        ui.Update("TxtNetBindError", "Visibility", msg == "" ? "Collapsed" : "Visible")
    }
}

; 保存：校验端口 → 写 MainSoftData → OnSaveSetting 落盘 + 总线调和 → 反馈结果
; 成功返回 true（调用方关闭窗口）；失败在窗口内红字提示并保持打开
NetworkApplyNetSetting(ui, closeDlg) {
    global MainSoftData, MyNetworkServer
    v := ""
    try v := Trim(ui.Query("EditNetPort"))
    if (!NetworkIsValidPort(v)) {
        NetworkSetNetDialogError(ui, GetLang("端口需为 1-65535 的整数"))
        return
    }
    MainSoftData.NetworkPort := Integer(v)
    OnSaveSetting()   ; 全量脏检查落盘 + HotReloadPublish 广播（注意：总线是 SetTimer(-1) 异步 flush）
    ; 总线调和为空闲异步派发，此处需立即拿到 bind 结果决定红字/关窗：
    ; 同步做一次幂等调和（后续总线 flush 再调一次无副作用，running/wantPort 已判定）
    try MyNetworkServer.OnConfigChanged(0, 0)
    err := NetworkGetBindError()
    if (err != "") {
        NetworkSetNetDialogError(ui, err)   ; 绑定失败（如端口占用）：红字提示，窗口保持打开
        return
    }
    NetworkSetNetDialogError(ui, "")
    Toast.Success(GetLang("已保存，监听端口: ") MainSoftData.NetworkPort)
    closeDlg(GetLang("保存"))
}
