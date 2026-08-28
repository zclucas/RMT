#Requires AutoHotkey v2.0

; 形式化节点：内联变更处理、显隐刷新、摘要（与 MacroGraphFormal.ahk 配套）

class MacroGraphFormalHandlersMixin {

    _FormalChecked(state, key) {
        return state.Has(key) && (state[key] == "True" || state[key] == true || state[key] == 1 || state[key] == "1")
    }

    ; CheckBox 事件 state 往往只有「刚点击的那一个」；读其它勾选前必须从界面补齐，否则会被当成未勾选写回。
    _FormalEnsureCheckInState(state, key) {
        if (!IsObject(state))
            return
        if (state.Has(key))
            return
        if (this.ui == "")
            return
        q := this.ui.Query(key)
        if (q != "")
            state[key] := q
    }

    ; 读勾选写回：补读 UI 后取 0/1；若仍无键则保留原值（避免轻量事件/Flush 空 Map 误清）
    _FormalReadToggle(state, key, current := 0) {
        this._FormalEnsureCheckInState(state, key)
        if (IsObject(state) && state.Has(key))
            return this._FormalChecked(state, key) ? 1 : 0
        return (current == 1 || current == "1" || current == true || current == "True") ? 1 : 0
    }

    _FormalSetVis(id, rowName, visible) {
        if (this.ui != "")
            this.ui.Update(rowName, "Visibility", visible ? "Visible" : "Collapsed")
    }

    _FormalSubCallIsInsert(id, ct, state := unset) {
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        val := this._ComboText("SubCallCmb_" id, IsSet(state) ? state : unset, callTypes)
        if (val != "") {
            idx := this._IndexInLangArr(callTypes, val)
            if (idx < 0)
                idx := this._IndexInLangArr(callTypes, GetLang(GetLangKey(val)))
            return idx == 0
        }
        return GetLangKey(ct) == "插入到当前宏"
    }

    _FormalLangKeyFromCombo(items, stateVal) {
        idx := this._IndexInLangArr(items, stateVal)
        return idx >= 0 ? GetLangKey(items[idx + 1]) : GetLangKey(stateVal)
    }

    _FormalParseListIndex(text) {
        if (RegExMatch(String(text), "^(\d+)", &m))
            return Integer(m[1])
        return 1
    }

    _FormalParseInitArr(text) {
        parts := StrSplit(text, ",")
        arr := []
        for p in parts {
            v := Trim(p)
            if (v != "")
                arr.Push(IsNumber(v) ? Number(v) : v)
        }
        return arr.Length ? arr : [1, 2, 3]
    }

    _FormalDFromId(id) {
        if (!this.cmdNodes.Has(id))
            return { type: "" }
        return this._Parse(this.cmdNodes[id].CurCMD)
    }

    ; ----------------------------------------------------------------- 内联变更处理

    _OnFormalSubMacro(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"])
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        this._EnsureComboInState(state, "SubTypeCmb_" id, macroTypes)
        this._EnsureComboInState(state, "SubCallCmb_" id, callTypes)
        sidx := this._ComboSelectedIndex("SubIdxCmb_" id)
        if (sidx >= 0)
            state["SubIdxCmb_" id] := String(sidx + 1)
        if (state.Has("SubTypeCmb_" id) && state["SubTypeCmb_" id] != "")
            data.MacroType := this._FormalLangKeyFromCombo(macroTypes, state["SubTypeCmb_" id])
        if (state.Has("SubCallCmb_" id) && state["SubCallCmb_" id] != "")
            data.CallType := this._FormalLangKeyFromCombo(callTypes, state["SubCallCmb_" id])
        if (state.Has("SubIdxCmb_" id) && state["SubIdxCmb_" id] != "") {
            data.Index := this._FormalParseListIndex(state["SubIdxCmb_" id])
            try {
                tableItem := GetTableBySymbol(data.MacroType)
                if (tableItem && tableItem.Items.Length >= data.Index)
                    data.MacroSerial := tableItem.Items[data.Index].ID
            }
        }
        if (state.Has("SubIns_" id) && state["SubIns_" id] != "")
            data.InsertCount := GetLangKey(state["SubIns_" id])
        else if (this.ui != "") {
            ins := this.ui.Query("SubIns_" id ">Text")
            if (ins == "")
                ins := this.ui.Query("SubIns_" id)
            if (ins != "")
                data.InsertCount := GetLangKey(ins)
        }
        SaveMacroCMDData(data)
        this._RefreshFormalSubMacroVisibility(id, state)
        this._Apply()
    }

    _FormalVarSlotState(id, slot, d, state := unset) {
        p := "VarS" slot
        opTypes := this._FormalVarOpTypes()
        ot := d.HasOwnProp("operaType" slot) ? d["operaType" slot] : 1
        ; 默认值须与内联构建(_FillVariableSlot)一致：缺省时变量1为开，其余为关，否则会出现勾选了却收起字段
        on := this._FormalVarSlotOn(d.HasOwnProp("toggle" slot) ? d["toggle" slot] : (slot == 1 ? 1 : 0))
        if (IsSet(state) && IsObject(state)) {
            if (state.Has(p "Tog_" id))
                on := this._FormalChecked(state, p "Tog_" id)
            this._EnsureComboInState(state, p "OpCmb_" id, opTypes)
            if (state.Has(p "OpCmb_" id) && state[p "OpCmb_" id] != "")
                ot := this._IndexInLangArr(opTypes, state[p "OpCmb_" id]) + 1
        } else {
            opTxt := this._ComboText(p "OpCmb_" id, unset, opTypes)
            if (opTxt != "")
                ot := this._IndexInLangArr(opTypes, opTxt) + 1
        }
        return { on: on, ot: ot }
    }

    _OnFormalVariable(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        opTypes := this._FormalVarOpTypes()
        data.IsIgnoreExist := this._FormalReadToggle(state, "VarIgn_" id, data.IsIgnoreExist)
        loop 4 {
            slot := A_Index
            p := "VarS" slot
            this._EnsureComboInState(state, p "OpCmb_" id, opTypes)
            data.ToggleArr[slot] := this._FormalReadToggle(state, p "Tog_" id, data.ToggleArr[slot])
            if (state.Has(p "OpCmb_" id) && state[p "OpCmb_" id] != "")
                data.OperaTypeArr[slot] := this._IndexInLangArr(opTypes, state[p "OpCmb_" id]) + 1
            ; 可编辑下拉：优先界面 Text（标签拖拽只改 Text，SelectedItem 可能仍是旧值）
            this._PullEditTextIntoState(state, p "Name_" id)
            this._PullEditTextIntoState(state, p "Copy_" id)
            this._PullEditTextIntoState(state, p "Min_" id)
            this._PullEditTextIntoState(state, p "Max_" id)
            this._PullEditTextIntoState(state, p "CopyTxt_" id)
            if (state.Has(p "Name_" id) && state[p "Name_" id] != "")
                data.VariableArr[slot] := GetVarName(state[p "Name_" id])
            ot := data.OperaTypeArr[slot]
            if (ot == 4) {
                sysItems := GetSystemVarArr()
                this._EnsureComboInState(state, p "SysCmb_" id, sysItems)
                if (state.Has(p "SysCmb_" id) && state[p "SysCmb_" id] != "")
                    data.CopyVariableArr[slot] := GetLangKey(state[p "SysCmb_" id])
            } else if (ot == 3) {
                ; 字符：取纯文本输入（按字面量保存，不做语言键转换，允许为空串）
                if (state.Has(p "CopyTxt_" id))
                    data.CopyVariableArr[slot] := state[p "CopyTxt_" id]
            } else if (state.Has(p "Copy_" id) && state[p "Copy_" id] != "")
                data.CopyVariableArr[slot] := GetLangKey(state[p "Copy_" id])
            if (state.Has(p "Min_" id) && state[p "Min_" id] != "")
                data.MinVariableArr[slot] := GetLangKey(state[p "Min_" id])
            if (state.Has(p "Max_" id) && state[p "Max_" id] != "")
                data.MaxVariableArr[slot] := GetLangKey(state[p "Max_" id])
        }
        SaveMacroCMDData(data)
        this._RefreshFormalVariableVisibility(id, state)
        this._RefreshVariableSummary(id)   ; 同步收起态摘要，保证启用/取值变化即时反映
        this._Apply()
    }

    _OnFormalExVariable(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        extTypes := GetLangArr(["屏幕", "剪切板", "窗口"])
        this._EnsureComboInState(state, "ExTypeCmb_" id, extTypes)
        data.IsIgnoreExist := this._FormalReadToggle(state, "ExIgn_" id, data.IsIgnoreExist)
        if (state.Has("ExTypeCmb_" id) && state["ExTypeCmb_" id] != "")
            data.ExtractType := this._IndexInLangArr(extTypes, state["ExTypeCmb_" id]) + 1
        if (state.Has("ExStr_" id))
            data.ExtractStr := state["ExStr_" id]
        if (state.Has("ExWin_" id))
            data.WinInfo := state["ExWin_" id]
        if (state.Has("ExSX_" id) && state["ExSX_" id] != "")
            data.StartPosX := state["ExSX_" id]
        if (state.Has("ExSY_" id) && state["ExSY_" id] != "")
            data.StartPosY := state["ExSY_" id]
        if (state.Has("ExEX_" id) && state["ExEX_" id] != "")
            data.EndPosX := state["ExEX_" id]
        if (state.Has("ExEY_" id) && state["ExEY_" id] != "")
            data.EndPosY := state["ExEY_" id]
        if (state.Has("ExCnt_" id) && state["ExCnt_" id] != "")
            data.SearchCount := state["ExCnt_" id] == GetLang("无限") ? -1 : state["ExCnt_" id]
        if (state.Has("ExInt_" id))
            data.SearchInterval := state["ExInt_" id]
        loop 6 {
            slot := A_Index
            p := "ExV" slot
            data.ToggleArr[slot] := this._FormalReadToggle(state, p "Tog_" id, data.ToggleArr[slot])
            if (state.Has(p "Name_" id) && state[p "Name_" id] != "")
                data.VariableArr[slot] := GetVarName(state[p "Name_" id])
        }
        SaveMacroCMDData(data)
        this._RefreshFormalExVariableVisibility(id)
        this._Apply()
    }

    ; 变量提取「模板」编辑按钮：复用提取模板编辑器(ExVariableEditGui)，确定后回写模板与变量勾选。
    _OnFormalExTemplateEdit(id, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        editor := this.ExVariableGui.MyEditGui
        editor.OwnerHwnd := ""
        editor.SureAction := this._OnFormalExTemplateSure.Bind(this, id)
        editor.ShowGui(data.HasOwnProp("ExtractStr") ? data.ExtractStr : "")
    }

    ; 模板编辑器确定回调：(ExtractStr, VariNum)。回写模板文本、按数量勾选前 VariNum 个变量并就地刷新内联。
    _OnFormalExTemplateSure(id, extractStr, variNum, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        data.ExtractStr := extractStr
        loop 6
            data.ToggleArr[A_Index] := (A_Index <= variNum) ? 1 : 0
        SaveMacroCMDData(data)
        if (this.ui != "") {
            this.ui.Update("ExStr_" id, "Text", extractStr)
            loop 6
                this.ui.Update("ExV" A_Index "Tog_" id, "IsChecked", (A_Index <= variNum) ? "True" : "False")
        }
        this._RefreshFormalExVariableVisibility(id)
        this._Apply()
    }

    _OnFormalOperation(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        loop 4 {
            slot := A_Index
            p := "OpS" slot
            ; 补读全部勾选：只点「运算2」时 state 常无「运算1」，勿把运算1误写成关
            data.ToggleArr[slot] := this._FormalReadToggle(state, p "Tog_" id, data.ToggleArr[slot])
            if (state.Has(p "Target_" id) && state[p "Target_" id] != "")
                data.UpdateNameArr[slot] := GetVarName(state[p "Target_" id])
            if (!state.Has(p "Expr_" id) && this.ui != "") {
                q := this.ui.Query(p "Expr_" id)
                if (q != "")
                    state[p "Expr_" id] := q
            }
            if (state.Has(p "Expr_" id))
                data.ExpressionArr[slot] := state[p "Expr_" id]
        }
        SaveMacroCMDData(data)
        this._RefreshFormalOperationVisibility(id)
        ; 折叠态：刷新摘要显示
        if (this._NodeFolded(id))
            this._RefreshOperationSummary(id)
        this._Apply()
    }

    _OnFormalRun(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        modes := this._FormalRunModeArr()
        options := GetLangArr(["后台", "默认", "最小化", "最大化"])
        encArr := GetLangArr(["UTF-8", "UTF-16", "CP0"])
        this._EnsureComboInState(state, "RunModeCmb_" id, modes)
        this._EnsureComboInState(state, "RunEncInCmb_" id, encArr)
        this._EnsureComboInState(state, "RunEncOutCmb_" id, encArr)
        this._EnsureComboInState(state, "RunEncErrCmb_" id, encArr)
        this._EnsureComboInState(state, "RunOptionCmb_" id, options)
        this._PullEditTextIntoState(state, "RunTarget_" id)
        this._PullEditTextIntoState(state, "RunStdIn_" id)
        ; 存索引 0~3（对应 Run/RunWait 的 Hide/默认/Min/Max）
        oidx := this._ComboSelectedIndex("RunOptionCmb_" id)
        if (oidx >= 0 && oidx <= 3)
            data.Option := oidx
        else if (state.Has("RunOptionCmb_" id) && state["RunOptionCmb_" id] != "")
            data.Option := this._IndexInLangArr(options, state["RunOptionCmb_" id])
        if (state.Has("RunTarget_" id))
            data.Target := state["RunTarget_" id]
        if (state.Has("RunModeCmb_" id) && state["RunModeCmb_" id] != "") {
            mi := this._IndexInLangArr(modes, state["RunModeCmb_" id]) + 1
            if (mi >= 1 && mi <= 4)
                data.Mode := mi
        }

        ; 与 RunGui.SaveRunData 一致：按模式裁剪字段
        if (data.Mode == 1) {
            if (ObjHasOwnProp(data, "StdIn"))
                data.DeleteProp("StdIn")
            if (ObjHasOwnProp(data, "SaveNameArr"))
                data.DeleteProp("SaveNameArr")
            if (ObjHasOwnProp(data, "Encoding"))
                data.DeleteProp("Encoding")
        } else if (data.Mode == 2) {
            if (ObjHasOwnProp(data, "StdIn"))
                data.DeleteProp("StdIn")
            if (ObjHasOwnProp(data, "Encoding"))
                data.DeleteProp("Encoding")
            saveVal := (state.Has("RunSave1_" id) && state["RunSave1_" id] != "") ? GetVarName(state["RunSave1_" id]) : "ExitCode"
            data.SaveNameArr := [saveVal]
        } else if (data.Mode == 3) {
            data.StdIn := state.Has("RunStdIn_" id) ? state["RunStdIn_" id] : ""
            if (ObjHasOwnProp(data, "SaveNameArr"))
                data.DeleteProp("SaveNameArr")
            enc := {}
            enc.In := (state.Has("RunEncInCmb_" id) && state["RunEncInCmb_" id] != "") ? state["RunEncInCmb_" id] : "UTF-8"
            data.Encoding := enc
        } else if (data.Mode == 4) {
            data.StdIn := state.Has("RunStdIn_" id) ? state["RunStdIn_" id] : ""
            arr := []
            loop 3 {
                def := (A_Index == 1 ? "ExitCode" : (A_Index == 2 ? "StdOut" : "StdErr"))
                val := (state.Has("RunSave" A_Index "_" id) && state["RunSave" A_Index "_" id] != "") ? GetVarName(state["RunSave" A_Index "_" id]) : def
                arr.Push(val)
            }
            data.SaveNameArr := arr
            enc := {}
            enc.In  := (state.Has("RunEncInCmb_"  id) && state["RunEncInCmb_"  id] != "") ? state["RunEncInCmb_"  id] : "UTF-8"
            enc.Out := (state.Has("RunEncOutCmb_" id) && state["RunEncOutCmb_" id] != "") ? state["RunEncOutCmb_" id] : "UTF-8"
            enc.Err := (state.Has("RunEncErrCmb_" id) && state["RunEncErrCmb_" id] != "") ? state["RunEncErrCmb_" id] : "UTF-8"
            data.Encoding := enc
        }
        SaveMacroCMDData(data)
        this._RefreshFormalRunVisibility(id)
        this._Apply()
    }

    ; 文件读写：结果是否仅能为「变量」（其余皆为「数组」），与编辑器 RefreshConVisable 一致。
    _FIOResOnlyVar(operType, operMode) {
        return (operType == "读取Excel" && operMode == "单元格")
            || (operType == "读取文本文件" && (operMode == "读取全部内容" || operMode == "指定行"))
    }

    ; 在模式列表中查找某模式键的索引（0 基），未找到返回 -1。
    _FIOModeIdx(modeItems, modeKey) {
        target := GetLang(modeKey)
        loop modeItems.Length {
            if (modeItems[A_Index] == target)
                return A_Index - 1
        }
        return -1
    }

    ; 实时读取文件读写节点当前界面上「类型/模式/保存名」的真实值（直接向 WPF 进程查询，不用事件快照、不读数据缓存）。
    _FIOReadLive(id) {
        operTypes := GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"])
        otTxt := this._ComboText("FIOTypeCmb_" id, unset, operTypes)
        ot := otTxt != "" ? GetLangKey(otTxt) : ""
        modeItems := ot != "" ? this._FormalFileIOOperModes(ot) : []
        omTxt := this._ComboText("FIOModeCmb_" id, unset, modeItems)
        om := omTxt != "" ? GetLangKey(omTxt) : ""
        sn := ""
        if (this.ui != "") {
            sn := this.ui.Query("FIOSave_" id ">Text")
            if (sn == "")
                sn := this.ui.Query("FIOSave_" id)
        }
        return { ot: ot, om: om, sn: sn }
    }

    ; 操作类型切换：重置下方所有选项——模式列表重建并定位到「第一个」模式，再按 (类型, 第一个模式) 实时刷新下方内容。
    ; 类型实时取自界面控件，模式固定为新类型的第一项，不依赖任何快照/缓存。
    _OnFIOType(id, state, ctrl, event) {
        live := this._FIOReadLive(id)
        ot := live.ot
        if (ot == "")
            return
        modeItems := this._FormalFileIOOperModes(ot)
        om := modeItems.Length > 0 ? GetLangKey(modeItems[1]) : "单元格"   ; 切类型 → 模式回到第一个
        if (this.ui != "") {
            this.ui.Update("FIOModeCmb_" id, "ClearItems", "")
            for it in modeItems
                this.ui.Update("FIOModeCmb_" id, "AddItem", it)
            this.ui.Update("FIOModeCmb_" id, "SelectedIndex", 0)
        }
        ; 按 (类型, 第一个模式) 实时刷新下方所有选项
        this._RefreshFileIOOptions(id, ot, om, live.sn)
        ; 持久化（仅存储，不参与上面的刷新判断）
        data := this._FormalIniData(id)
        if (data != "") {
            data.OperType := ot
            data.OperMode := om
            data.SaveType := this._FIOResOnlyVar(ot, om) ? "变量" : "数组"
            SaveMacroCMDData(data)
        }
        this._Apply()
    }

    ; 模式切换：类型与模式都【实时】取自界面控件，按 (类型, 模式) 一级一级刷新下方内容，不用快照、不读缓存。
    _OnFIOMode(id, state, ctrl, event) {
        live := this._FIOReadLive(id)
        ot := live.ot, om := live.om
        if (ot == "" || om == "")
            return
        ; 过滤不属于当前类型的模式（类型切换时清空/重建产生的瞬时回显）
        if (this._FIOModeIdx(this._FormalFileIOOperModes(ot), om) < 0)
            return
        ; 按 (类型, 模式) 实时刷新下方所有选项
        this._RefreshFileIOOptions(id, ot, om, live.sn)
        ; 持久化
        data := this._FormalIniData(id)
        if (data != "") {
            data.OperType := ot
            data.OperMode := om
            data.SaveType := this._FIOResOnlyVar(ot, om) ? "变量" : "数组"
            SaveMacroCMDData(data)
        }
        this._Apply()
    }

    ; 实时读取 RMT 指令节点当前界面上「类别/指令」的真实值（直接向 WPF 进程查询，不用事件快照、不读数据缓存）。
    _RmtReadLive(id) {
        categories := this._RmtCategories()
        catTxt := this._ComboText("RmtCatCmb_" id, unset, categories)
        cat := catTxt != "" ? GetLangKey(catTxt) : ""
        ops := this._RmtCategoryOps(catTxt != "" ? catTxt : GetLang("全部"))
        opTxt := this._ComboText("RmtOpCmb_" id, unset, ops)
        op := opTxt != "" ? GetLangKey(opTxt) : ""
        return { cat: cat, op: op }
    }

    ; RMT 指令类别
    _RmtCategories() {
        return GetLangArr(["全部", "图文", "输入控制", "宏控制", "调试", "软件自身"])
    }

    ; RMT 类别对应的指令列表（与 RMTCMDGui.CategoriesMap 保持一致）
    _RmtCategoryOps(category) {
        allOps := GetLangArr(["截图", "截图提取文本", "自由贴", "启用鼠标", "启用键盘", "启用键鼠",
            "禁用鼠标", "禁用键盘", "禁用键鼠", "启用鼠标加速", "禁用鼠标加速", "显示菜单", "关闭菜单",
            "暂停所有宏", "恢复所有宏", "终止所有宏", "开启变量监视", "关闭变量监视", "开启指令显示",
            "关闭指令显示", "关闭软件", "休眠", "重载"])
        if (category == GetLang("全部") || category == "")
            return allOps
        categoryOps := Map(
            GetLang("图文"), GetLangArr(["截图", "截图提取文本", "自由贴"]),
            GetLang("输入控制"), GetLangArr(["启用鼠标", "启用键盘", "启用键鼠", "禁用鼠标", "禁用键盘", "禁用键鼠", "启用鼠标加速", "禁用鼠标加速"]),
            GetLang("宏控制"), GetLangArr(["显示菜单", "关闭菜单", "暂停所有宏", "恢复所有宏", "终止所有宏"]),
            GetLang("调试"), GetLangArr(["开启变量监视", "关闭变量监视", "开启指令显示", "关闭指令显示"]),
            GetLang("软件自身"), GetLangArr(["关闭软件", "休眠", "重载"])
        )
        return categoryOps.Has(category) ? categoryOps[category] : allOps
    }

    ; 在指令列表中查找某指令键的索引（0 基），未找到返回 -1。
    _RmtOpIdx(ops, opKey) {
        target := GetLang(opKey)
        loop ops.Length {
            if (ops[A_Index] == target)
                return A_Index - 1
        }
        return -1
    }

    ; RMT 指令不走 INI 序列，内联/编辑器变更后须回写 CurCMD，保证节点与编辑器一致。
    _RmtSyncCurCMD(id, d) {
        if (!this.cmdNodes.Has(id) || d.type != GetLang("RMT指令"))
            return
        this.cmdNodes[id].CurCMD := this._BuildCmd(d)
    }

    ; 类别切换：重置下方所有选项——指令列表重建并定位到「第一个」指令，再按 (类别, 第一个指令) 实时刷新下方内容。
    _OnRmtCategory(id, state, ctrl, event) {
        live := this._RmtReadLive(id)
        cat := live.cat
        if (cat == "")
            return
        ops := this._RmtCategoryOps(cat)
        op := ops.Length > 0 ? GetLangKey(ops[1]) : GetLang("截图")   ; 切类别 → 指令回到第一个
        if (this.ui != "" && HasMethod(this.ui, "Update")) {
            this.ui.Update("RmtOpCmb_" id, "ClearItems", "")
            for it in ops
                this.ui.Update("RmtOpCmb_" id, "AddItem", it)
            this.ui.Update("RmtOpCmb_" id, "SelectedIndex", 0)
        }
        this._RefreshRmtOptions(id, cat, op)
        d := this._FormalDFromId(id)
        d.rmtCategory := cat
        d.rmtOp := op
        if (op != GetLang("显示菜单"))
            d.rmtMenuIdx := "1"
        this._RmtSyncCurCMD(id, d)
        this._Apply()
    }

    ; 指令切换：类别与指令都【实时】取自界面控件，按 (类别, 指令) 一级一级刷新下方内容
    _OnRmtOp(id, state, ctrl, event) {
        live := this._RmtReadLive(id)
        cat := live.cat, op := live.op
        if (cat == "" || op == "")
            return
        ops := this._RmtCategoryOps(cat)
        if (this._RmtOpIdx(ops, op) < 0)
            return
        this._RefreshRmtOptions(id, cat, op)
        d := this._FormalDFromId(id)
        d.rmtCategory := cat
        d.rmtOp := op
        if (op != GetLang("显示菜单"))
            d.rmtMenuIdx := "1"
        this._RmtSyncCurCMD(id, d)
        this._Apply()
    }

    ; 刷新 RMT 指令节点下方选项（菜单序号的显示/隐藏）
    _RefreshRmtOptions(id, cat, op) {
        showMenu := op == GetLang("显示菜单")
        if (this.ui == "")
            return
        ; 设置行可见性
        this._FormalSetVis(id, "RmtMenuRow_" id, showMenu)
        ; 菜单序号显示时，确保下拉框启用并有数据
        if (showMenu) {
            ; 启用下拉框（因为初始创建时可能被禁用）
            this.ui.Update("RmtMenuCmb_" id, "IsEnabled", "True")
            ; 加载菜单选项
            menuItems := this._FormalMenuIndexItems()
            if (menuItems.Length > 0) {
                this.ui.Update("RmtMenuCmb_" id, "ClearItems", "")
                for item in menuItems {
                    this.ui.Update("RmtMenuCmb_" id, "AddItem", item)
                }
                ; 设置默认选中第一个
                this.ui.Update("RmtMenuCmb_" id, "SelectedIndex", 0)
            }
        }
    }

    ; 普通字段变更（RMT 菜单序号）
    _OnRmtField(id, state, ctrl, event) {
        d := this._FormalDFromId(id)
        if (!IsObject(state))
            state := Map()
        midx := this._ComboSelectedIndex("RmtMenuCmb_" id)
        if (midx >= 0)
            d.rmtMenuIdx := midx + 1
        else if (state.Has("RmtMenuCmb_" id) && state["RmtMenuCmb_" id] != "")
            d.rmtMenuIdx := this._FormalParseListIndex(state["RmtMenuCmb_" id])
        live := this._RmtReadLive(id)
        if (live.cat != "")
            d.rmtCategory := live.cat
        if (live.op != "")
            d.rmtOp := live.op
        this._RmtSyncCurCMD(id, d)
        this._Apply()
    }

    ; 文件读写普通字段变更（RMT 菜单序号）
    ; 注：FIO 相关普通字段移到 _OnFIOField 处理
    _OnFIOField(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        encodings := GetLangArr(["UTF-8", "UTF-16", "GBK", "ANSI"])
        this._EnsureComboInState(state, "FIOEncCmb_" id, encodings)
        if (state.Has("FIOPath_" id))
            data.FilePath := state["FIOPath_" id]
        if (state.Has("FIOSheet_" id) && state["FIOSheet_" id] != "")
            data.NameOrSerial := state["FIOSheet_" id]
        if (state.Has("FIOEncCmb_" id) && state["FIOEncCmb_" id] != "")
            data.Encoding := GetLangKey(state["FIOEncCmb_" id])
        if (state.Has("FIORow_" id) && state["FIORow_" id] != "")
            data.RowVar := state["FIORow_" id]
        if (state.Has("FIOCol_" id) && state["FIOCol_" id] != "")
            data.ColVar := state["FIOCol_" id]
        if (state.Has("FIORowEnd_" id) && state["FIORowEnd_" id] != "")
            data.RowEndVar := state["FIORowEnd_" id]
        if (state.Has("FIOColEnd_" id))
            data.ColEndVar := state["FIOColEnd_" id]
        if (state.Has("FIOTxtRow_" id) && state["FIOTxtRow_" id] != "")
            data.TextRowVar := state["FIOTxtRow_" id]
        if (state.Has("FIOContent_" id))
            data.Content := state["FIOContent_" id]
        if (state.Has("FIOArr_" id) && state["FIOArr_" id] != "")
            data.ArrName := GetVarName(state["FIOArr_" id])
        if (state.Has("FIOSave_" id) && state["FIOSave_" id] != "")
            data.SaveName := GetVarName(state["FIOSave_" id])
        SaveMacroCMDData(data)
        this._Apply()
    }

    ; 下方所有选项的刷新：完全由 (类型, 模式) 决定，不读数据表。
    ; 一级一级判断：保存类型文本 → 保存名列表（变量/数组）→ 各字段行显隐。saveName 仅用于回填下拉文本。
    _RefreshFileIOOptions(id, ot, om, saveName := "") {
        if (this.ui == "")
            return
        isResOnlyVar := this._FIOResOnlyVar(ot, om)
        this.ui.Update("FIOSaveType_" id, "Text", GetLang(isResOnlyVar ? "变量" : "数组"))
        saveNameList := isResOnlyVar ? GetGuiVarArr() : GetGuiArrNameArr()
        this.ui.Update("FIOSave_" id, "ClearItems", "")
        for name in saveNameList
            this.ui.Update("FIOSave_" id, "AddItem", name)
        if (saveName != "")
            this.ui.Update("FIOSave_" id, "Text", saveName)
        this._RefreshFormalFileIOVisibility(id, ot, om)
    }

    ; 切换参数类型下拉显隐（各类型预置独立 ComboBox，不重建列表）
    _RefreshFormalTextOpsArgsTypeSlot(id, tt, at := "") {
        if (this.ui == "")
            return
        ti := this._FormalTextOpsTypeIdx(tt)
        loop this._FormalTextOpsTypeNames().Length
            this.ui.Update("TxtArgsTypeCmb_" A_Index "_" id, "Visibility", A_Index == ti ? "Visible" : "Collapsed")
        if (ti >= 1) {
            items := this._FormalTextOpsArgsTypes(tt)
            sel := (at != "" && items.Length) ? this._IndexInLangArr(items, at) : 0
            if (sel < 0)
                sel := 0
            this.ui.Update("TxtArgsTypeCmb_" ti "_" id, "SelectedIndex", sel)
        }
    }

    ; 文本处理节点下方选项刷新：完全由类型决定，不读数据表。
    ; 参数：tt=类型, at=参数类型(可选), saveName=保存名(可选)
    _RefreshTextOpsOptions(id, tt, at := "", saveName := "") {
        if (this.ui == "")
            return
        IsSplit := tt == "文本分割"
        IsGetEx := tt == "文本提取"
        autoSaveType := (IsSplit || IsGetEx) ? "数组" : "变量"
        this.ui.Update("TxtSaveTypeTxt_" id, "Text", autoSaveType)
        saveNameList := GetGuiVarArr()
        this.ui.Update("TxtSave_" id, "ClearItems", "")
        for name in saveNameList
            this.ui.Update("TxtSave_" id, "AddItem", name)
        if (saveName != "")
            this.ui.Update("TxtSave_" id, "Text", saveName)
        this._RefreshFormalTextOpsVisibility(id, tt, at)
        if (at == "" && this._FormalTextOpsArgsTypes(tt).Length > 0)
            at := this._FormalTextOpsArgsTypes(tt)[1]
        this._RefreshFormalTextOpsArgsTypeSlot(id, tt, at)
    }

    _OnFormalTextOps(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()

        ; 必须用 ctrl 区分触发源：state 快照含全部已追踪控件，不能靠 Has 判断
        if (ctrl == "TxtTypeCmb_" id) {
            typeNames := this._FormalTextOpsTypeNames()
            ttTxt := this._ComboText(ctrl, state, typeNames)
            if (ttTxt == "")
                return
            tt := GetLangKey(ttTxt)
            if (data.Type == tt)
                return
            data.Type := tt
            argsItems := this._FormalTextOpsArgsTypes(tt)
            if (argsItems.Length > 0)
                data.ArgsType := GetLangKey(argsItems[1])
            data.SaveType := (tt == "文本分割" || tt == "文本提取") ? "数组" : "变量"
            this._RefreshTextOpsOptions(id, tt, data.ArgsType, data.HasOwnProp("SaveName") ? data.SaveName : "")
            SaveMacroCMDData(data)
            this._Apply()
            return
        }

        if (RegExMatch(ctrl, "^TxtArgsTypeCmb_\d+_" id "$")) {
            tt := data.HasOwnProp("Type") ? data.Type : "文本分割"
            argsItems := this._FormalTextOpsArgsTypes(tt)
            atTxt := this._ComboText(ctrl, state, argsItems)
            if (atTxt == "")
                return
            data.ArgsType := GetLangKey(atTxt)
            this._RefreshFormalTextOpsVisibility(id, data.Type, data.ArgsType)
            SaveMacroCMDData(data)
            this._Apply()
            return
        }

        hasChange := false
        if (ctrl == "TxtName_" id && state.Has(ctrl) && state[ctrl] != "") {
            newName := GetVarName(state[ctrl])
            if (data.Name != newName) {
                data.Name := newName
                hasChange := true
            }
        }
        if (ctrl == "TxtArgsName_" id && state.Has(ctrl) && state[ctrl] != "") {
            if (data.ArgsName != state[ctrl]) {
                data.ArgsName := state[ctrl]
                hasChange := true
            }
        }
        if (ctrl == "TxtSearch_" id && state.Has(ctrl)) {
            if (data.Search != state[ctrl]) {
                data.Search := state[ctrl]
                hasChange := true
            }
        }
        if (ctrl == "TxtReplace_" id && state.Has(ctrl)) {
            if (data.Replace != state[ctrl]) {
                data.Replace := state[ctrl]
                hasChange := true
            }
        }
        if (ctrl == "TxtSave_" id && state.Has(ctrl) && state[ctrl] != "") {
            newSaveName := GetVarName(state[ctrl])
            if (data.SaveName != newSaveName) {
                data.SaveName := newSaveName
                hasChange := true
            }
        }

        if (hasChange) {
            SaveMacroCMDData(data)
            this._Apply()
        }
    }

    ; 数组：根据操作类型计算各类显隐/逻辑标志，节点与刷新共用，保证表现一致。
    _ArrFlags(at) {
        IsCreate := at == "创建"
        IsClone := at == "克隆"
        IsDelete := at == "删除"
        IsContain := at == "包含"
        IsGet := at == "取值"
        IsSetValue := at == "赋值"
        IsInsert := at == "插入"
        IsAdd := at == "追加"
        IsRemove := at == "移除"
        IsRemoveLast := at == "移除最后"
        IsReverse := at == "反转"
        IsLength := at == "长度"
        OnlyArgsIndex := IsGet || IsRemove                ; 取值/移除：只要 索引，不要 参数类型/参数值
        OnlyArgsData := IsAdd || IsContain                ; 追加/包含：只要 参数类型/参数值，不要 索引
        IsShowResult := IsGet || IsLength || IsClone || IsRemove || IsRemoveLast || IsContain || IsReverse
        IsShowMainIndex := !IsCreate && !IsDelete
        IsShowArgs := IsGet || IsSetValue || IsInsert || IsAdd || IsRemove || IsContain
        ShowIgn := IsCreate                               ; 仅 创建 显示「忽略已存在」
        return { IsCreate: IsCreate, IsClone: IsClone, IsDelete: IsDelete, IsContain: IsContain
            , IsGet: IsGet, IsSetValue: IsSetValue, IsInsert: IsInsert, IsAdd: IsAdd
            , IsRemove: IsRemove, IsRemoveLast: IsRemoveLast, IsReverse: IsReverse, IsLength: IsLength
            , OnlyArgsIndex: OnlyArgsIndex, OnlyArgsData: OnlyArgsData, IsShowResult: IsShowResult
            , IsShowMainIndex: IsShowMainIndex, IsShowArgs: IsShowArgs, ShowIgn: ShowIgn }
    }

    ; 数组：某些操作类型的「保存类型」固定，返回固定值（"变量"/"数组"），无固定返回 ""。
    _ArrFixedSaveType(at) {
        if (at == "长度" || at == "包含")
            return "变量"
        if (at == "克隆" || at == "反转")
            return "数组"
        return ""
    }

    ; 实时读取数组节点当前界面上「操作类型/参数类型/保存类型」的真实值（直接向 WPF 查询，不用快照/缓存）。
    _ArrReadLive(id) {
        typeNames := GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
        argsTypes := GetLangArr(["变量或值", "数组"])
        saveTypes := GetLangArr(["变量", "数组"])
        atTxt := this._ComboText("ArrTypeCmb_" id, unset, typeNames)
        agtTxt := this._ComboText("ArrArgsTypeCmb_" id, unset, argsTypes)
        stTxt := this._ComboText("ArrSaveTypeCmb_" id, unset, saveTypes)
        at := atTxt != "" ? GetLangKey(atTxt) : ""
        agt := agtTxt != "" ? GetLangKey(agtTxt) : ""
        st := stTxt != "" ? GetLangKey(stTxt) : ""
        return { at: at, agt: agt, st: st }
    }

    ; 操作类型/参数类型/保存类型 任一变更：三者都【实时】取自界面控件，按其值一级一级刷新下方内容，不用快照/缓存。
    _OnFormalArray(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        live := this._ArrReadLive(id)
        at := live.at != "" ? live.at : (data.HasOwnProp("Type") ? data.Type : "创建")
        agt := live.agt != "" ? live.agt : (data.HasOwnProp("ArgsType") ? data.ArgsType : "变量或值")
        fixedSt := this._ArrFixedSaveType(at)
        st := fixedSt != "" ? fixedSt : (live.st != "" ? live.st : (data.HasOwnProp("SaveType") ? data.SaveType : "变量"))
        ; 持久化布局相关字段
        data.Type := at
        data.ArgsType := agt
        data.SaveType := st
        f := this._ArrFlags(at)
        if (!f.ShowIgn)
            data.IsIgnoreExist := 0
        SaveMacroCMDData(data)
        ; 实时刷新下方所有选项（含保存类型固定、参数值/保存名列表、各行显隐）
        this._RefreshArrayOptions(id, at, agt, st
            , data.HasOwnProp("ArgsName") ? data.ArgsName : ""
            , data.HasOwnProp("SaveName") ? data.SaveName : "")
        this._Apply()
    }

    ; 普通字段变更：只写入对应字段，不触碰类型/派生显隐（这些字段不影响布局）。
    _OnArrField(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (state.Has("ArrName_" id) && state["ArrName_" id] != "")
            data.Name := GetVarName(state["ArrName_" id])
        if (state.Has("ArrInit_" id))
            data.InitArr := this._FormalParseInitArr(state["ArrInit_" id])
        if (state.Has("ArrMain_" id) && state["ArrMain_" id] != "")
            data.MainIndex := state["ArrMain_" id]
        if (state.Has("ArrArgsIdx_" id) && state["ArrArgsIdx_" id] != "")
            data.ArgsIndex := state["ArrArgsIdx_" id]
        if (state.Has("ArrArgsName_" id) && state["ArrArgsName_" id] != "")
            data.ArgsName := GetVarName(state["ArrArgsName_" id])
        if (state.Has("ArrSave_" id) && state["ArrSave_" id] != "")
            data.SaveName := GetVarName(state["ArrSave_" id])
        ; 忽略已存在：仅 创建 生效，其余强制 false
        ShowIgn := (data.Type == "创建")
        if (!IsObject(state))
            state := Map()
        data.IsIgnoreExist := (ShowIgn && this._FormalReadToggle(state, "ArrIgn_" id, data.IsIgnoreExist)) ? 1 : 0
        SaveMacroCMDData(data)
        this._Apply()
    }

    ; 下方所有选项的刷新：完全由 (操作类型, 参数类型, 保存类型) 决定。
    ; 一级一级：行显隐 → 保存类型固定/释放 → 参数值列表(变量/数组) → 保存名列表(变量/数组)。
    _RefreshArrayOptions(id, at, argsType, saveType, argsName := "", saveName := "") {
        if (this.ui == "")
            return
        f := this._ArrFlags(at)
        fixedSt := this._ArrFixedSaveType(at)
        effSt := fixedSt != "" ? fixedSt : saveType
        showIdx := f.IsShowArgs && !f.OnlyArgsData
        showData := f.IsShowArgs && !f.OnlyArgsIndex
        this._FormalSetVis(id, "ArrIgnRow_" id, f.ShowIgn)
        this._FormalSetVis(id, "ArrInitRow_" id, f.IsCreate)
        this._FormalSetVis(id, "ArrMainRow_" id, f.IsShowMainIndex)
        this._FormalSetVis(id, "ArrArgsIdxRow_" id, showIdx)
        this._FormalSetVis(id, "ArrArgsTypeRow_" id, showData)
        this._FormalSetVis(id, "ArrArgsNameRow_" id, showData)
        this._FormalSetVis(id, "ArrSaveTypeRow_" id, f.IsShowResult)
        this._FormalSetVis(id, "ArrSaveRow_" id, f.IsShowResult)
        ; 保存类型固定/释放
        saveTypes := GetLangArr(["变量", "数组"])
        this.ui.Update("ArrSaveTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(saveTypes, GetLang(effSt)))
        this.ui.Update("ArrSaveTypeCmb_" id, "IsEnabled", fixedSt != "" ? "False" : "True")
        ; 参数值列表（变量或值→变量列表；数组→数组列表）
        argsNameList := (argsType == "数组") ? GetGuiArrNameArr() : GetGuiVarArr()
        this.ui.Update("ArrArgsName_" id, "ClearItems", "")
        for n in argsNameList
            this.ui.Update("ArrArgsName_" id, "AddItem", n)
        if (argsName != "")
            this.ui.Update("ArrArgsName_" id, "Text", argsName)
        ; 保存名列表（变量→变量列表；数组→数组列表）
        saveNameList := (effSt == "数组") ? GetGuiArrNameArr() : GetGuiVarArr()
        this.ui.Update("ArrSave_" id, "ClearItems", "")
        for n in saveNameList
            this.ui.Update("ArrSave_" id, "AddItem", n)
        if (saveName != "")
            this.ui.Update("ArrSave_" id, "Text", saveName)
    }

    _OnFormalBGMouse(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        opTypes := GetLangArr(["点击", "双击", "按下", "松开"])
        mouseTypes := GetLangArr(["左键", "中键", "右键", "滚轮"])
        this._EnsureComboInState(state, "BgmOpCmb_" id, opTypes)
        this._EnsureComboInState(state, "BgmMouseCmb_" id, mouseTypes)
        if (state.Has("BgmTitle_" id))
            data.TargetTitle := state["BgmTitle_" id]
        if (state.Has("BgmOpCmb_" id) && state["BgmOpCmb_" id] != "")
            data.OperateType := this._IndexInLangArr(opTypes, state["BgmOpCmb_" id]) + 1
        if (state.Has("BgmMouseCmb_" id) && state["BgmMouseCmb_" id] != "")
            data.MouseType := this._IndexInLangArr(mouseTypes, state["BgmMouseCmb_" id]) + 1
        this._PullEditTextIntoState(state, "BgmTime_" id)
        if (state.Has("BgmTime_" id) && state["BgmTime_" id] != "")
            data.ClickTime := state["BgmTime_" id]
        if (state.Has("BgmX_" id) && state["BgmX_" id] != "")
            data.PosVarX := state["BgmX_" id]
        if (state.Has("BgmY_" id) && state["BgmY_" id] != "")
            data.PosVarY := state["BgmY_" id]
        if (state.Has("BgmSV_" id))
            data.ScrollV := state["BgmSV_" id]
        if (state.Has("BgmSH_" id))
            data.ScrollH := state["BgmSH_" id]
        SaveMacroCMDData(data)
        this._RefreshFormalBGMouseVisibility(id)
        this._Apply()
    }

    ; 后台鼠标「编辑」按钮：打开窗口信息编辑器，确定后回写目标窗口标题。
    _OnFormalBGMouseTitleEdit(id, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        adapter := { Value: data.TargetTitle }
        MyFrontInfoGui.OwnerHwnd := ""
        MyFrontInfoGui.HideAction := ""
        MyFrontInfoGui.SureAction := this._OnFormalBGMouseTitleEditSure.Bind(this, id, adapter)
        MyFrontInfoGui.ShowGui(adapter)
    }

    _OnFormalBGMouseTitleEditSure(id, adapter, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        data.TargetTitle := adapter.Value
        SaveMacroCMDData(data)
        if (this.ui != "")
            this.ui.Update("BgmTitle_" id, "Text", adapter.Value)
        this._Apply()
    }

    _OnFormalBGKey(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        types := GetLangArr(["按下", "松开", "点击"])
        this._EnsureComboInState(state, "BgkTypeCmb_" id, types)
        if (state.Has("BgkTypeCmb_" id) && state["BgkTypeCmb_" id] != "")
            data.Type := this._IndexInLangArr(types, state["BgkTypeCmb_" id]) + 1
        if (state.Has("BgkFront_" id))
            data.FrontStr := state["BgkFront_" id]
        if (state.Has("BgkTime_" id))
            data.ClickTime := state["BgkTime_" id]
        if (state.Has("BgkCount_" id))
            data.ClickCount := state["BgkCount_" id]
        if (state.Has("BgkInter_" id))
            data.ClickInterval := state["BgkInter_" id]
        SaveMacroCMDData(data)
        this._RefreshFormalBGKeyVisibility(id)
        this._Apply()
    }

    ; 后台按键「编辑」按钮：打开窗口信息编辑器，确定后回写前台信息。
    _OnFormalBGKeyFrontEdit(id, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        adapter := { Value: data.FrontStr }
        MyFrontInfoGui.OwnerHwnd := ""
        MyFrontInfoGui.HideAction := ""
        MyFrontInfoGui.SureAction := this._OnFormalBGKeyFrontEditSure.Bind(this, id, adapter)
        MyFrontInfoGui.ShowGui(adapter)
    }

    _OnFormalBGKeyFrontEditSure(id, adapter, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        data.FrontStr := adapter.Value
        SaveMacroCMDData(data)
        if (this.ui != "")
            this.ui.Update("BgkFront_" id, "Text", adapter.Value)
        this._Apply()
    }

    _OnFormalWindowManage(id, state, ctrl, event) {
        actions := this._FormalWindowManageActions()
        if (!IsObject(state))
            state := Map()
        if (ctrl == "WmActCmb_" id) {
            atTxt := this._ComboText(ctrl, state, actions)
            if (atTxt == "")
                return
            at := this._FormalLangKeyFromCombo(actions, atTxt)
            data := this._FormalIniData(id)
            if (data == "")
                return
            data.ActionType := at
            SaveMacroCMDData(data)
            this._RefreshFormalWindowManageVisibility(id, at)
            this._Apply()
            return
        }
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (state.Has("WmWin_" id))
            data.SearchValue := state["WmWin_" id]
        if (state.Has("WmX_" id) && state["WmX_" id] != "")
            data.PosX := state["WmX_" id]
        if (state.Has("WmY_" id) && state["WmY_" id] != "")
            data.PosY := state["WmY_" id]
        if (state.Has("WmW_" id) && state["WmW_" id] != "")
            data.Width := state["WmW_" id]
        if (state.Has("WmH_" id) && state["WmH_" id] != "")
            data.Height := state["WmH_" id]
        if (state.Has("WmTitle_" id) && state["WmTitle_" id] != "")
            data.NewTitle := state["WmTitle_" id]
        if (state.Has("WmTrans_" id) && state["WmTrans_" id] != "")
            data.Transparency := state["WmTrans_" id]
        SaveMacroCMDData(data)
        this._Apply()
    }

    _OnFormalWmWinEdit(id, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        adapter := { Value: data.SearchValue }
        MyFrontInfoGui.OwnerHwnd := ""
        MyFrontInfoGui.HideAction := ""
        MyFrontInfoGui.SureAction := this._OnFormalWmWinEditSure.Bind(this, id, adapter)
        MyFrontInfoGui.ShowGui(adapter)
    }

    _OnFormalWmWinEditSure(id, adapter, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        data.SearchValue := adapter.Value
        SaveMacroCMDData(data)
        if (this.ui != "")
            this.ui.Update("WmWin_" id, "Text", adapter.Value)
        this._Apply()
    }

    _WmReadLiveAction(id) {
        actions := this._FormalWindowManageActions()
        if (this.ui != "") {
            try {
                idx := this.ui.Get("WmActCmb_" id, "SelectedIndex")
                if (idx >= 0 && idx < actions.Length)
                    return GetLangKey(actions[idx + 1])
            }
        }
        d := this._FormalDFromId(id)
        return d.HasOwnProp("wmActionType") ? GetLangKey(d.wmActionType) : "激活窗口"
    }

    _OnFormalKeyCheck(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        checkTypes := GetLangArr(["同时按下", "有一个按下"])
        stateTypes := GetLangArr(["物理状态", "逻辑状态"])
        this._EnsureComboInState(state, "KcCheckCmb_" id, checkTypes)
        this._EnsureComboInState(state, "KcStateCmb_" id, stateTypes)
        if (state.Has("KcCheckCmb_" id) && state["KcCheckCmb_" id] != "")
            data.CheckType := this._IndexInLangArr(checkTypes, state["KcCheckCmb_" id]) + 1
        if (state.Has("KcStateCmb_" id) && state["KcStateCmb_" id] != "")
            data.StateType := this._IndexInLangArr(stateTypes, state["KcStateCmb_" id]) + 1
        if (state.Has("KcVar_" id) && state["KcVar_" id] != "")
            data.VarName := GetVarName(state["KcVar_" id])
        SaveMacroCMDData(data)
        this._Apply()
    }

    _OnFormalScreenShot(id, state, ctrl, event) {
        typeNames := GetLangArr(["屏幕抓图", "窗口抓图"])
        if (!IsObject(state))
            state := Map()
        if (ctrl == "SsTypeCmb_" id) {
            ttTxt := this._ComboText(ctrl, state, typeNames)
            if (ttTxt == "")
                return
            data := this._FormalIniData(id)
            if (data == "")
                return
            data.ScreenShotType := this._IndexInLangArr(typeNames, ttTxt) + 1
            SaveMacroCMDData(data)
            this._RefreshFormalScreenShotVisibility(id, data.ScreenShotType)
            this._Apply()
            return
        }
        if (ctrl == "SsNameTog_" id || ctrl == "SsResTog_" id) {
            data := this._FormalIniData(id)
            if (data == "")
                return
            if (!IsObject(state))
                state := Map()
            if (ctrl == "SsNameTog_" id)
                data.NameType := this._FormalReadToggle(state, "SsNameTog_" id, data.NameType)
            else
                data.ResultToggle := this._FormalReadToggle(state, "SsResTog_" id, data.ResultToggle)
            SaveMacroCMDData(data)
            nt := data.NameType
            resOn := data.ResultToggle == 1 || data.ResultToggle == "1"
            this._RefreshFormalScreenShotVisibility(id, unset, nt, resOn)
            this._Apply()
            return
        }
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (state.Has("SsWin_" id))
            data.WinInfo := state["SsWin_" id]
        if (state.Has("SsSX_" id) && state["SsSX_" id] != "")
            data.StartPosX := state["SsSX_" id]
        if (state.Has("SsSY_" id) && state["SsSY_" id] != "")
            data.StartPosY := state["SsSY_" id]
        if (state.Has("SsEX_" id) && state["SsEX_" id] != "")
            data.EndPosX := state["SsEX_" id]
        if (state.Has("SsEY_" id) && state["SsEY_" id] != "")
            data.EndPosY := state["SsEY_" id]
        if (state.Has("SsFixed_" id))
            data.FixedName := state["SsFixed_" id]
        if (state.Has("SsResName_" id) && state["SsResName_" id] != "")
            data.ResultSaveName := GetVarName(state["SsResName_" id])
        SaveMacroCMDData(data)
        this._Apply()
    }

    _OnFormalSsWinEdit(id, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        adapter := { Value: data.WinInfo }
        MyFrontInfoGui.OwnerHwnd := ""
        MyFrontInfoGui.HideAction := ""
        MyFrontInfoGui.SureAction := this._OnFormalSsWinEditSure.Bind(this, id, adapter)
        MyFrontInfoGui.ShowGui(adapter)
    }

    _OnFormalSsWinEditSure(id, adapter, *) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        data.WinInfo := adapter.Value
        SaveMacroCMDData(data)
        if (this.ui != "")
            this.ui.Update("SsWin_" id, "Text", adapter.Value)
        this._Apply()
    }

    ; ----------------------------------------------------------------- 显隐刷新

    _RefreshFormalSubMacroVisibility(id, state := unset) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        mt := d.HasOwnProp("macroType") ? d.macroType : "按键宏"
        ct := d.HasOwnProp("callType") ? d.callType : "触发"
        if (IsSet(state) && state.Has("SubTypeCmb_" id) && state["SubTypeCmb_" id] != "")
            mt := this._FormalLangKeyFromCombo(GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"]), state["SubTypeCmb_" id])
        if (IsSet(state) && state.Has("SubCallCmb_" id) && state["SubCallCmb_" id] != "")
            ct := this._FormalLangKeyFromCombo(GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"]), state["SubCallCmb_" id])
        idxItems := this._FormalMacroIndexItems(mt)
        showIdx := (GetLangKey(mt) != "当前宏") && idxItems.Length > 0
        showIns := IsSet(state) ? this._FormalSubCallIsInsert(id, ct, state) : this._FormalSubCallIsInsert(id, ct)
        this._FormalSetVis(id, "SubIdxRow_" id, showIdx)
        this._FormalSetVis(id, "SubInsRow_" id, showIns)
    }

    _RefreshFormalVariableVisibility(id, state := unset) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        prevOn := true
        loop 4 {
            slot := A_Index
            p := "VarS" slot
            st := IsSet(state) ? this._FormalVarSlotState(id, slot, d, state) : this._FormalVarSlotState(id, slot, d)
            on := st.on
            ot := st.ot
            slotVis := (slot == 1) ? true : prevOn   ; 逐级展开：仅上一个变量勾选后才显示本卡片
            showNum := on && ot == 1
            showChar := on && ot == 3
            showSys := on && ot == 4
            showMinMax := on && ot == 2
            this._FormalSetVis(id, p "Card_" id, slotVis)
            this._FormalSetVis(id, p "TogRow_" id, true)
            this._FormalSetVis(id, p "OpRow_" id, on)
            this._FormalSetVis(id, p "NameRow_" id, on)
            this._FormalSetVis(id, p "CopyRow_" id, showNum)
            this._FormalSetVis(id, p "CharRow_" id, showChar)
            this._FormalSetVis(id, p "SysRow_" id, showSys)
            this._FormalSetVis(id, p "MinRow_" id, showMinMax)
            this._FormalSetVis(id, p "MaxRow_" id, showMinMax)
            prevOn := slotVis && on
        }
    }

    _RefreshFormalExVariableVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        et := d.HasOwnProp("extractType") ? d.extractType : 1
        isOcr := et == 1 || et == 3
        isWin := et == 3
        this._FormalSetVis(id, "ExStrRow_" id, true)   ; 模板：屏幕/剪切板/窗口 都需要
        this._FormalSetVis(id, "ExWinRow_" id, isWin)
        for nm in ["ExSXRow_", "ExSYRow_", "ExEXRow_", "ExEYRow_", "ExCntRow_", "ExIntRow_"]
            this._FormalSetVis(id, nm id, isOcr)
        ; 提取变量格（复选框+名称）始终可见，启用与否由复选框表达，不再随类型/勾选隐藏名称
        loop 6 {
            p := "ExV" A_Index
            this._FormalSetVis(id, p "TogRow_" id, true)
        }
    }

    _RefreshFormalOperationVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        prevOn := true
        loop 4 {
            slot := A_Index
            p := "OpS" slot
            toggled := d.HasOwnProp("opToggle" slot) ? d["opToggle" slot] : (slot == 1 ? 1 : 0)
            on := toggled == 1 || toggled == "1"
            slotVis := (slot == 1) ? true : prevOn   ; 逐级展开：仅上一个运算勾选后才显示本组
            this._FormalSetVis(id, p "TogRow_" id, slotVis)
            this._FormalSetVis(id, p "TargetRow_" id, slotVis && on)
            this._FormalSetVis(id, p "ExprRow_" id, slotVis && on)
            prevOn := slotVis && on
        }
    }

    _RefreshFormalRunVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        ; 运行节点字段是 runMode；基类 Parse 自带空串 mode，不可拿来做数值比较
        rm := d.HasOwnProp("runMode") ? d.runMode : 1
        if (rm == "" || !IsNumber(rm))
            rm := 1
        rm := Integer(rm)
        if (rm < 1 || rm > 4)
            rm := 1
        ; 与 RunGui.OnModeChange / _FillRunBody 对齐
        showStdIn := (rm == 3 || rm == 4)
        showEncIn := showStdIn
        showEncOut := (rm == 4)
        showSave1 := (rm == 2 || rm == 4)
        showSave23 := (rm == 4)
        this._FormalSetVis(id, "RunStdInRow_" id, showStdIn)
        this._FormalSetVis(id, "RunEncInRow_" id, showEncIn)
        this._FormalSetVis(id, "RunEncOutRow_" id, showEncOut)
        this._FormalSetVis(id, "RunEncErrRow_" id, showEncOut)
        this._FormalSetVis(id, "RunSave1Row_" id, showSave1)
        this._FormalSetVis(id, "RunSave2Row_" id, showSave23)
        this._FormalSetVis(id, "RunSave3Row_" id, showSave23)
    }

    ; ot/om 可显式传入（来自权威 data，确定且无需反解）；省略时回退到反解 CurCMD。
    _RefreshFormalFileIOVisibility(id, ot := "", om := "") {
        if (this.ui == "")
            return
        if (ot == "" || om == "") {
            d := this._FormalDFromId(id)
            ot := d.HasOwnProp("operType") ? d.operType : "读取Excel"
            om := d.HasOwnProp("operMode") ? d.operMode : "单元格"
        }
        IsRead := ot == "读取Excel" || ot == "读取文本文件"
        IsWrite := !IsRead
        IsExcel := ot == "读取Excel" || ot == "写入Excel"
        IsText := ot == "读取文本文件" || ot == "写入文本文件"
        IsExcelRange := IsExcel && (om == "指定行" || om == "指定列" || om == "指定区域-行" || om == "指定区域-列")
        HasTextRow := IsText && (om == "指定行" || om == "逐行读取" || om == "行号自增")
        HasRegion := IsRead && (om == "指定区域-行" || om == "指定区域-列")
        HasWriteContent := IsWrite && !IsExcelRange
        HasWriteArr := IsWrite && IsExcelRange
        this._FormalSetVis(id, "FIOSheetRow_" id, IsExcel)
        this._FormalSetVis(id, "FIOEncRow_" id, IsText)
        this._FormalSetVis(id, "FIORowRow_" id, IsExcel)
        this._FormalSetVis(id, "FIOColRow_" id, IsExcel)
        this._FormalSetVis(id, "FIORowEndRow_" id, HasRegion)
        this._FormalSetVis(id, "FIOColEndRow_" id, HasRegion)
        this._FormalSetVis(id, "FIOTxtRowRow_" id, HasTextRow)
        this._FormalSetVis(id, "FIOContentBlock_" id, HasWriteContent)
        this._FormalSetVis(id, "FIOArrRow_" id, HasWriteArr)
        ; 结果保存（保存类型+保存名）仅读取时出现，与文件读写编辑器一致；
        ; 写入Excel-指定区域只需「数组名」作为写入源，不需要保存字段。
        this._FormalSetVis(id, "FIOSaveTypeRow_" id, IsRead)
        this._FormalSetVis(id, "FIOSaveRow_" id, IsRead)
    }

    _RefreshFormalTextOpsVisibility(id, tt := "", at := "") {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        if (tt == "")
            tt := d.HasOwnProp("textOpsType") ? d.textOpsType : "文本分割"
        if (at == "")
            at := d.HasOwnProp("argsType") ? d.argsType : ","
        IsReplace := tt == "文本替换"
        IsSplit := tt == "文本分割"
        IsGetEx := tt == "文本提取"
        IsConcat := tt == "文本拼接"
        ShowArgsType := IsSplit || IsGetEx || tt == "大小写转换" || tt == "去除空格" || tt == "文本统计" || IsConcat || IsReplace
        ShowArgsName := this._FormalTextOpsShowArgsName(tt, at)
        argsItems := this._FormalTextOpsArgsTypes(tt)
        this._FormalSetVis(id, "TxtArgsTypeRow_" id, ShowArgsType && argsItems.Length > 0)
        this._FormalSetVis(id, "TxtArgsNameRow_" id, ShowArgsName)
        this._FormalSetVis(id, "TxtSearchRow_" id, IsReplace)
        this._FormalSetVis(id, "TxtReplaceRow_" id, IsReplace)
    }

    ; 文本处理节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshTextOpsInline(id, d) {
        typeNames := this._FormalTextOpsTypeNames()
        tt := d.HasOwnProp("textOpsType") ? d.textOpsType : "文本分割"
        tn := d.HasOwnProp("textName") ? d.textName : "TextVar"
        at := d.HasOwnProp("argsType") ? d.argsType : ","
        an := d.HasOwnProp("argsName") ? d.argsName : ","
        sr := d.HasOwnProp("search") ? d.search : ""
        rp := d.HasOwnProp("replace") ? d.replace : ""
        sn := d.HasOwnProp("saveName") ? d.saveName : "Data"
        IsSplit := tt == "文本分割"
        IsGetEx := tt == "文本提取"
        fixedSt := (IsSplit || IsGetEx) ? "数组" : "变量"

        this.ui.Update("TxtTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(typeNames, tt))
        this.ui.Update("TxtName_" id, "Text", tn)
        this.ui.Update("TxtSearch_" id, "Text", sr)
        this.ui.Update("TxtReplace_" id, "Text", rp)
        this.ui.Update("TxtSave_" id, "Text", sn)
        this._RefreshFormalTextOpsArgsTypeSlot(id, tt, at)

        varList := GetGuiVarArr(2)
        this.ui.Update("TxtArgsName_" id, "ClearItems", "")
        for item in varList
            this.ui.Update("TxtArgsName_" id, "AddItem", item)
        this.ui.Update("TxtArgsName_" id, "Text", an)

        this.ui.Update("TxtSaveTypeTxt_" id, "Text", fixedSt)
        saveNameList := GetGuiVarArr()
        this.ui.Update("TxtSave_" id, "ClearItems", "")
        for item in saveNameList
            this.ui.Update("TxtSave_" id, "AddItem", item)

        this._RefreshFormalTextOpsVisibility(id, tt, at)
    }

    _RefreshFormalArrayVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        at := d.HasOwnProp("arrayType") ? d.arrayType : "创建"
        agt := d.HasOwnProp("argsType") ? d.argsType : "变量或值"
        st := d.HasOwnProp("saveType") ? d.saveType : "变量"
        agn := d.HasOwnProp("argsName") ? d.argsName : ""
        sn := d.HasOwnProp("saveName") ? d.saveName : ""
        this._RefreshArrayOptions(id, at, agt, st, agn, sn)
    }

    ; 如果Pro：各情况条件/逻辑关系 内联变更
    _OnFormalIfPro(id, state, ctrl, event) {
        data := this._IfProData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        logicTypes := this._IfProLogicTypes()
        cmpTypes := this._IfProCmpTypes()
        cc := this._IfProCaseCountFromData(data)
        loop cc {
            ci := A_Index
            p := "IfProC" ci
            this._EnsureComboInState(state, p "LogicCmb_" id, logicTypes)
            if (state.Has(p "LogicCmb_" id) && state[p "LogicCmb_" id] != "")
                data.LogicTypeArr[ci] := this._IndexInLangArr(logicTypes, state[p "LogicCmb_" id]) + 1
            names := []
            cmps := []
            vals := []
            loop 4 {
                slot := A_Index
                ps := p "S" slot
                this._EnsureComboInState(state, ps "Cmp_" id, cmpTypes)
                ; IfPro 以数组长度表达启用数：未勾选则跳过；读不到时按原条件数保留
                on := this._FormalReadToggle(state, ps "Tog_" id, slot <= data.VariNameArr[ci].Length ? 1 : 0)
                if (!on)
                    continue
                nm := state.Has(ps "Name_" id) ? GetLangKey(state[ps "Name_" id]) : ("Var" slot)
                cmp := 3
                if (state.Has(ps "Cmp_" id) && state[ps "Cmp_" id] != "")
                    cmp := this._IndexInLangArr(cmpTypes, state[ps "Cmp_" id]) + 1
                vr := state.Has(ps "Var_" id) ? GetLangKey(state[ps "Var_" id]) : ("Var" slot)
                names.Push(nm)
                cmps.Push(cmp)
                vals.Push(vr)
            }
            if (names.Length == 0) {
                names.Push("Var1")
                cmps.Push(3)
                vals.Push("Var1")
            }
            data.VariNameArr[ci] := names
            data.CompareTypeArr[ci] := cmps
            data.VariableArr[ci] := vals
        }
        SaveMacroCMDData(data)
        this._RefreshFormalIfProVisibility(id)
        this._RefreshIfProSummary(id)
        this._RefreshIfProPortPositions(id)
        this._Apply()
    }

    _RefreshFormalIfProVisibility(id) {
        if (this.ui == "")
            return
        data := this._IfProData(id)
        if (data == "")
            return
        cc := this._IfProCaseCountFromData(data)
        loop cc {
            ci := A_Index
            p := "IfProC" ci
            condiN := data.VariNameArr[ci].Length
            this._FormalSetVis(id, p "LogicRow_" id, condiN > 1)
            prevOn := true
            loop 4 {
                slot := A_Index
                ps := p "S" slot
                on := slot <= condiN
                chainVis := (slot == 1) ? true : prevOn
                cmp := (slot <= data.CompareTypeArr[ci].Length) ? data.CompareTypeArr[ci][slot] : 3
                this._FormalSetVis(id, ps "Row_" id, chainVis)
                this._FormalSetVis(id, ps "NameRow_" id, chainVis && on)
                this._FormalSetVis(id, ps "CmpRow_" id, chainVis && on)
                this._FormalSetVis(id, ps "VarRow_" id, chainVis && on && cmp != 7)
                prevOn := chainVis && on
            }
        }
    }

    _RefreshIfProInline(id, d) {
        data := this._IfProData(id)
        if (data == "" || this.ui == "")
            return false
        cc := this._IfProCaseCountFromData(data)
        oldCc := this._ifProUiCaseCount.Has(id) ? this._ifProUiCaseCount[id] : cc
        if (cc != oldCc)
            return false
        logicTypes := this._IfProLogicTypes()
        cmpTypes := this._IfProCmpTypes()
        loop cc {
            ci := A_Index
            p := "IfProC" ci
            lt := data.LogicTypeArr[ci]
            this.ui.Update(p "LogicCmb_" id, "SelectedIndex", Max(0, lt - 1))
            condiN := data.VariNameArr[ci].Length
            loop 4 {
                slot := A_Index
                ps := p "S" slot
                on := slot <= condiN
                nm := on ? data.VariNameArr[ci][slot] : ("Var" slot)
                cmp := on ? data.CompareTypeArr[ci][slot] : 3
                vr := on ? data.VariableArr[ci][slot] : ("Var" slot)
                this.ui.Update(ps "Tog_" id, "IsChecked", on ? "True" : "False")
                this.ui.Update(ps "Name_" id, "Text", GetLang(nm))
                this.ui.Update(ps "Cmp_" id, "SelectedIndex", cmp - 1)
                this.ui.Update(ps "Var_" id, "Text", GetLang(vr))
            }
        }
        this._RefreshIfProSummary(id)
        this._RefreshFormalIfProVisibility(id)
        this._RefreshIfProPortPositions(id)
        this._RebuildIfProBranches(id)
        return true
    }

    ; 如果节点：逻辑关系/条件行/结果保存 变更
    _OnFormalIf(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        logicTypes := this._IfLogicTypes()
        cmpTypes := this._IfCmpTypes()
        this._EnsureComboInState(state, "IfLogicCmb_" id, logicTypes)
        if (state.Has("IfLogicCmb_" id) && state["IfLogicCmb_" id] != "")
            data.LogicalType := this._IndexInLangArr(logicTypes, state["IfLogicCmb_" id]) + 1
        data.SaveToggle := this._FormalReadToggle(state, "IfSaveTog_" id, data.SaveToggle)
        if (state.Has("IfSaveName_" id) && state["IfSaveName_" id] != "")
            data.SaveName := GetVarName(state["IfSaveName_" id])
        if (state.Has("IfTrueVal_" id))
            data.TrueValue := state["IfTrueVal_" id]
        if (state.Has("IfFalseVal_" id))
            data.FalseValue := state["IfFalseVal_" id]
        loop 4 {
            slot := A_Index
            p := "IfC" slot
            this._EnsureComboInState(state, p "Cmp_" id, cmpTypes)
            data.ToggleArr[slot] := this._FormalReadToggle(state, p "Tog_" id, data.ToggleArr[slot])
            if (state.Has(p "Name_" id) && state[p "Name_" id] != "")
                data.NameArr[slot] := GetLangKey(state[p "Name_" id])
            if (state.Has(p "Cmp_" id) && state[p "Cmp_" id] != "")
                data.CompareTypeArr[slot] := this._IndexInLangArr(cmpTypes, state[p "Cmp_" id]) + 1
            if (state.Has(p "Var_" id) && state[p "Var_" id] != "")
                data.VariableArr[slot] := GetLangKey(state[p "Var_" id])
        }
        SaveMacroCMDData(data)
        this._RefreshFormalIfVisibility(id)
        if (this._NodeFolded(id))
            this._RefreshIfSummary(id)
        this._Apply()
    }

    _RefreshFormalIfVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        folded := this._NodeFolded(id)
        saveOn := d.HasOwnProp("saveToggle") && (d.saveToggle == 1 || d.saveToggle == "1")
        this._FormalSetVis(id, "IfSaveNameRow_" id, !folded && saveOn)
        this._FormalSetVis(id, "IfTrueValRow_" id, !folded && saveOn)
        this._FormalSetVis(id, "IfFalseValRow_" id, !folded && saveOn)
        prevOn := true
        loop 4 {
            slot := A_Index
            p := "IfC" slot
            tog := (slot == 1) ? true : (d.HasOwnProp("ifTog" slot) && (d["ifTog" slot] == 1 || d["ifTog" slot] == "1"))
            if (slot == 1 && d.HasOwnProp("ifTog1"))
                tog := d["ifTog1"] == 1 || d["ifTog1"] == "1"
            chainVis := (slot == 1) ? true : prevOn
            cmp := d.HasOwnProp("ifCmp" slot) ? d["ifCmp" slot] : 1
            cardVis := !folded && chainVis
            this._FormalSetVis(id, p "TogRow_" id, cardVis)
            this._FormalSetVis(id, p "NameRow_" id, cardVis && tog)
            this._FormalSetVis(id, p "CmpRow_" id, cardVis && tog)
            this._FormalSetVis(id, p "VarRow_" id, cardVis && tog && cmp != 7)
            prevOn := chainVis && tog
        }
    }

    ; 如果分支节点：流程控制下拉变更
    _OnBranchFlowControl(parentId, isTrue, state, ctrl, event) {
        data := this._FormalIniData(parentId)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        brId := this._BranchId(parentId, isTrue)
        key := "BrFlowCmb_" brId
        flowTypes := this._IfFlowTypes()
        this._EnsureComboInState(state, key, flowTypes)
        if (state.Has(key) && state[key] != "") {
            val := GetLangKey(state[key])
            if (isTrue)
                data.TrueControlType := val
            else
                data.FalseControlType := val
        }
        SaveMacroCMDData(data)
        if (this._IsIfNodeId(parentId) && this._NodeFolded(parentId))
            this._RefreshIfInlineBranches(parentId)
        this._Apply()
    }

    ; 循环节点：循环次数/条件类型/逻辑关系/条件行 变更。条件行不重建下拉，标准 mega-handler + reparse 显隐即可。
    _OnFormalLoop(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        condiTypes := this._LoopCondiTypes()
        logicTypes := this._LoopLogicTypes()
        cmpTypes := this._LoopCmpTypes()
        this._EnsureComboInState(state, "LoopCondiCmb_" id, condiTypes)
        this._EnsureComboInState(state, "LoopLogicCmb_" id, logicTypes)
        ; 循环次数：可编辑下拉，优先 Text
        if (this.ui != "") {
            cntTxt := this.ui.Query("LoopCount_" id ">Text")
            if (cntTxt == "")
                cntTxt := this.ui.Query("LoopCount_" id)
            if (cntTxt != "")
                state["LoopCount_" id] := cntTxt
        }
        if (state.Has("LoopCount_" id) && state["LoopCount_" id] != "")
            data.LoopCount := (state["LoopCount_" id] == GetLang("无限")) ? -1 : state["LoopCount_" id]
        if (state.Has("LoopCondiCmb_" id) && state["LoopCondiCmb_" id] != "")
            data.CondiType := this._IndexInLangArr(condiTypes, state["LoopCondiCmb_" id]) + 1
        if (state.Has("LoopLogicCmb_" id) && state["LoopLogicCmb_" id] != "")
            data.LogicType := this._IndexInLangArr(logicTypes, state["LoopLogicCmb_" id]) + 1
        loop 4 {
            slot := A_Index
            p := "LoopC" slot
            this._EnsureComboInState(state, p "Cmp_" id, cmpTypes)
            data.ToggleArr[slot] := this._FormalReadToggle(state, p "Tog_" id, data.ToggleArr[slot])
            if (state.Has(p "Name_" id) && state[p "Name_" id] != "")
                data.NameArr[slot] := GetLangKey(state[p "Name_" id])
            if (state.Has(p "Cmp_" id) && state[p "Cmp_" id] != "")
                data.CompareTypeArr[slot] := this._IndexInLangArr(cmpTypes, state[p "Cmp_" id]) + 1
            if (state.Has(p "Var_" id) && state[p "Var_" id] != "")
                data.VariableArr[slot] := GetLangKey(state[p "Var_" id])
        }
        SaveMacroCMDData(data)
        this._RefreshFormalLoopVisibility(id)
        this._RefreshLoopSummary(id)
        this._Apply()
    }

    _RefreshFormalLoopVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        condiType := d.HasOwnProp("condiType") ? d.condiType : 1
        showCondi := condiType != 1
        folded := this._NodeFolded(id)
        this._FormalSetVis(id, "LoopLogicRow_" id, showCondi && !folded)
        this._FormalSetVis(id, "LoopCondiSumBox_" id, showCondi && folded)
        ; 展开且无条件时垫高以容纳回环下端口；有条件/收起态不垫
        this._FormalSetVis(id, "LoopPortPad_" id, !showCondi && !folded)
        prevOn := true
        loop 4 {
            slot := A_Index
            p := "LoopC" slot
            tog := d.HasOwnProp("loopTog" slot) && (d["loopTog" slot] == 1 || d["loopTog" slot] == "1")
            chainVis := (slot == 1) ? true : prevOn   ; 逐级展开：仅勾选上一条件后才显示本条件块
            cardVis := showCondi && !folded && chainVis
            cmp := d.HasOwnProp("loopCmp" slot) ? d["loopCmp" slot] : 1
            this._FormalSetVis(id, p "TogRow_" id, cardVis)   ; 整块条件（含分隔线）随条件类型 + 逐级展开显隐
            this._FormalSetVis(id, p "NameRow_" id, cardVis && tog)
            this._FormalSetVis(id, p "CmpRow_" id, cardVis && tog)
            this._FormalSetVis(id, p "VarRow_" id, cardVis && tog && cmp != 7)
            prevOn := chainVis && tog
        }
    }

    ; 循环体「编辑」按钮：打开嵌套图形编辑器编辑循环体子图（与外置循环体节点双击一致），
    ; 确定后就地刷新内置/外置循环体卡片，不整窗重建。
    _OnFormalLoopBodyEdit(id, *) {
        this._OpenLoopBodyEditor(id)
    }

    _RefreshFormalRmtVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        op := d.HasOwnProp("rmtOp") ? d.rmtOp : GetLang("截图")
        menuItems := this._FormalMenuIndexItems()
        showMenu := op == GetLang("显示菜单") && menuItems.Length > 0
        this._FormalSetVis(id, "RmtMenuRow_" id, showMenu)
    }

    _RefreshFormalBGMouseVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        mt := d.HasOwnProp("bgMouseType") ? d.bgMouseType : 1
        ot := d.HasOwnProp("bgOperateType") ? d.bgOperateType : 1
        isScroll := mt == 4
        showClickTime := !isScroll && (ot == 1 || ot == 2)   ; 点击/双击
        this._FormalSetVis(id, "BgmOpRow_" id, !isScroll)
        this._FormalSetVis(id, "BgmTimeRow_" id, showClickTime)
        this._FormalSetVis(id, "BgmSVRow_" id, isScroll)
        this._FormalSetVis(id, "BgmSHRow_" id, isScroll)
    }

    ; 后台鼠标节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshBGMouseInline(id, d) {
        opTypes := GetLangArr(["点击", "双击", "按下", "松开"])
        mouseTypes := GetLangArr(["左键", "中键", "右键", "滚轮"])
        tt := d.HasOwnProp("targetTitle") ? d.targetTitle : ""
        ot := d.HasOwnProp("bgOperateType") ? d.bgOperateType : 1
        mt := d.HasOwnProp("bgMouseType") ? d.bgMouseType : 1
        px := d.HasOwnProp("bgPosVarX") ? d.bgPosVarX : 100
        py := d.HasOwnProp("bgPosVarY") ? d.bgPosVarY : 100
        ctm := d.HasOwnProp("clickTime") ? d.clickTime : 50
        sv := d.HasOwnProp("scrollV") ? d.scrollV : 1
        sh := d.HasOwnProp("scrollH") ? d.scrollH : 0
        varList := GetGuiVarArr()

        this.ui.Update("BgmTitle_" id, "Text", tt)
        this.ui.Update("BgmMouseCmb_" id, "SelectedIndex", Max(0, mt - 1))
        this.ui.Update("BgmOpCmb_" id, "SelectedIndex", Max(0, ot - 1))
        this.ui.Update("BgmTime_" id, "Text", ctm)
        this.ui.Update("BgmX_" id, "ClearItems", "")
        for item in varList
            this.ui.Update("BgmX_" id, "AddItem", item)
        this.ui.Update("BgmX_" id, "Text", GetLang(px))
        this.ui.Update("BgmY_" id, "ClearItems", "")
        for item in varList
            this.ui.Update("BgmY_" id, "AddItem", item)
        this.ui.Update("BgmY_" id, "Text", GetLang(py))
        this.ui.Update("BgmSV_" id, "Text", sv)
        this.ui.Update("BgmSH_" id, "Text", sh)
        this._RefreshFormalBGMouseVisibility(id)
    }

    _RefreshFormalBGKeyVisibility(id) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        tt := d.HasOwnProp("bgKeyType") ? d.bgKeyType : 1
        isClick := tt == 3
        this._FormalSetVis(id, "BgkTimeRow_" id, isClick)
        this._FormalSetVis(id, "BgkCountRow_" id, isClick)
        this._FormalSetVis(id, "BgkInterRow_" id, isClick)
    }

    ; 后台按键节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshBGKeyInline(id, d) {
        typeNames := GetLangArr(["按下", "松开", "点击"])
        tt := d.HasOwnProp("bgKeyType") ? d.bgKeyType : 1
        fs := d.HasOwnProp("frontStr") ? d.frontStr : ""
        keyStr := d.HasOwnProp("bgKeyStr") ? d.bgKeyStr : ""
        ctm := d.HasOwnProp("clickTime") ? d.clickTime : 100
        cc := d.HasOwnProp("clickCount") ? d.clickCount : 1
        ci := d.HasOwnProp("clickInterval") ? d.clickInterval : 100
        this.ui.Update("BgkKeys_" id, "Text", keyStr)
        this.ui.Update("BgkFront_" id, "Text", fs)
        this.ui.Update("BgkTypeCmb_" id, "SelectedIndex", Max(0, tt - 1))
        this.ui.Update("BgkTime_" id, "Text", ctm)
        this.ui.Update("BgkCount_" id, "Text", cc)
        this.ui.Update("BgkInter_" id, "Text", ci)
        this._RefreshFormalBGKeyVisibility(id)
    }

    _RefreshFormalWindowManageVisibility(id, at := "") {
        if (this.ui == "")
            return
        if (at == "")
            at := this._WmReadLiveAction(id)
        at := GetLangKey(at)
        this._FormalSetVis(id, "WmXRow_" id, at == "移动窗口")
        this._FormalSetVis(id, "WmYRow_" id, at == "移动窗口")
        this._FormalSetVis(id, "WmWRow_" id, at == "调整大小")
        this._FormalSetVis(id, "WmHRow_" id, at == "调整大小")
        this._FormalSetVis(id, "WmTitleRow_" id, at == "修改标题")
        this._FormalSetVis(id, "WmTransRow_" id, at == "修改透明度")
    }

    ; 窗口管理节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshWindowManageInline(id, d) {
        actions := this._FormalWindowManageActions()
        at := d.HasOwnProp("wmActionType") ? d.wmActionType : "激活窗口"
        sv := d.HasOwnProp("wmSearchValue") ? d.wmSearchValue : ""
        varList := GetGuiVarArr()
        actIdx := this._IndexInLangArr(actions, GetLang(at))
        if (actIdx < 0)
            actIdx := this._IndexInLangArr(actions, at)
        this.ui.Update("WmActCmb_" id, "SelectedIndex", Max(0, actIdx))
        this.ui.Update("WmWin_" id, "Text", sv)
        for nm, val in Map("WmX", d.HasOwnProp("wmPosX") ? d.wmPosX : 0, "WmY", d.HasOwnProp("wmPosY") ? d.wmPosY : 0,
            "WmW", d.HasOwnProp("wmWidth") ? d.wmWidth : 0, "WmH", d.HasOwnProp("wmHeight") ? d.wmHeight : 0,
            "WmTitle", d.HasOwnProp("wmNewTitle") ? d.wmNewTitle : "", "WmTrans", d.HasOwnProp("wmTransparency") ? d.wmTransparency : "80") {
            this.ui.Update(nm "_" id, "ClearItems", "")
            for item in varList
                this.ui.Update(nm "_" id, "AddItem", item)
            this.ui.Update(nm "_" id, "Text", GetLang(val))
        }
        this._RefreshFormalWindowManageVisibility(id, at)
    }

    ; 按键检测节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshKeyCheckInline(id, d) {
        ct := d.HasOwnProp("kcCheckType") ? d.kcCheckType : 1
        st := d.HasOwnProp("kcStateType") ? d.kcStateType : 1
        vn := d.HasOwnProp("kcVarName") ? d.kcVarName : ""
        keyStr := d.HasOwnProp("kcKeyStr") ? d.kcKeyStr : ""
        varList := GetGuiVarArr()
        this.ui.Update("KcKeys_" id, "Text", keyStr)
        this.ui.Update("KcCheckCmb_" id, "SelectedIndex", Max(0, ct - 1))
        this.ui.Update("KcStateCmb_" id, "SelectedIndex", Max(0, st - 1))
        this.ui.Update("KcVar_" id, "ClearItems", "")
        for item in varList
            this.ui.Update("KcVar_" id, "AddItem", item)
        this.ui.Update("KcVar_" id, "Text", GetLang(vn))
    }

    _RefreshFormalScreenShotVisibility(id, st := unset, nt := unset, resOn := unset) {
        if (this.ui == "" || !this.cmdNodes.Has(id))
            return
        d := this._FormalDFromId(id)
        if (!IsSet(st))
            st := d.HasOwnProp("ssType") ? d.ssType : 1
        if (!IsSet(nt))
            nt := d.HasOwnProp("ssNameType") ? d.ssNameType : 1
        if (!IsSet(resOn)) {
            rt := d.HasOwnProp("ssResultToggle") ? d.ssResultToggle : 0
            resOn := rt == 1 || rt == "1"
        }
        this._FormalSetVis(id, "SsWinRow_" id, st == 2)
        this._FormalSetVis(id, "SsFixedRow_" id, nt == 1 || nt == "1")
        this._FormalSetVis(id, "SsResNameRow_" id, resOn)
    }

    ; 抓图节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshScreenShotInline(id, d) {
        varList := GetGuiVarArr()
        st := d.HasOwnProp("ssType") ? d.ssType : 1
        nt := d.HasOwnProp("ssNameType") ? d.ssNameType : 1
        showFixed := nt == 1 || nt == "1"
        wi := d.HasOwnProp("ssWinInfo") ? d.ssWinInfo : ""
        fixed := d.HasOwnProp("ssFixedName") ? d.ssFixedName : "Shot"
        on := d.HasOwnProp("ssResultToggle") && (d.ssResultToggle == 1 || d.ssResultToggle == "1")
        rn := d.HasOwnProp("ssResultSaveName") ? d.ssResultSaveName : GetLang("图片路径")
        this.ui.Update("SsTypeCmb_" id, "SelectedIndex", Max(0, st - 1))
        this.ui.Update("SsWin_" id, "Text", wi)
        this.ui.Update("SsNameTog_" id, "IsChecked", showFixed ? "True" : "False")
        this.ui.Update("SsFixed_" id, "Text", fixed)
        for nm, val in Map("SsSX", d.HasOwnProp("ssStartX") ? d.ssStartX : 0, "SsSY", d.HasOwnProp("ssStartY") ? d.ssStartY : 0,
            "SsEX", d.HasOwnProp("ssEndX") ? d.ssEndX : A_ScreenWidth, "SsEY", d.HasOwnProp("ssEndY") ? d.ssEndY : A_ScreenHeight) {
            this.ui.Update(nm "_" id, "ClearItems", "")
            for item in varList
                this.ui.Update(nm "_" id, "AddItem", item)
            this.ui.Update(nm "_" id, "Text", GetLang(val))
        }
        this.ui.Update("SsResTog_" id, "IsChecked", on ? "True" : "False")
        this.ui.Update("SsResName_" id, "ClearItems", "")
        for item in varList
            this.ui.Update("SsResName_" id, "AddItem", item)
        this.ui.Update("SsResName_" id, "Text", GetLang(rn))
        this._RefreshFormalScreenShotVisibility(id, st, nt, on)
    }

    ; 仅用于初始注册/显隐刷新：更新标题与各类型显隐。
    ; 内联控件取值同步统一走整体重建（_Render，见 OnEditorSure），不在此逐控件打补丁。
    _RefreshFormalNode(id, d) {
        if (this.ui == "")
            return
        d := this._FormalDFromId(id)
        this.ui.Update("Title_" id, "Text", this._NodeTitleText(d))
        if (d.type == GetLang("宏操作"))
            this._RefreshFormalSubMacroVisibility(id)
        else if (d.type == GetLang("变量"))
            this._RefreshFormalVariableVisibility(id)
        else if (d.type == GetLang("变量提取"))
            this._RefreshFormalExVariableVisibility(id)
        else if (d.type == GetLang("运算"))
            this._RefreshFormalOperationVisibility(id)
        else if (d.type == GetLang("运行"))
            this._RefreshFormalRunVisibility(id)
        else if (d.type == GetLang("文件读写"))
            this._RefreshFormalFileIOVisibility(id)
        else if (d.type == GetLang("文本处理"))
            this._RefreshFormalTextOpsVisibility(id)
        else if (d.type == GetLang("数组"))
            this._RefreshFormalArrayVisibility(id)
        else if (d.type == GetLang("循环"))
            this._RefreshFormalLoopVisibility(id)
        else if (d.type == GetLang("如果"))
            this._RefreshFormalIfVisibility(id)
        else if (d.type == GetLang("如果Pro"))
            this._RefreshFormalIfProVisibility(id)
        else if (d.type == GetLang("RMT指令"))
            this._RefreshFormalRmtVisibility(id)
        else if (d.type == GetLang("后台鼠标"))
            this._RefreshFormalBGMouseVisibility(id)
        else if (d.type == GetLang("后台按键"))
            this._RefreshFormalBGKeyVisibility(id)
        else if (d.type == GetLang("窗口管理"))
            this._RefreshFormalWindowManageVisibility(id)
        else if (d.type == GetLang("抓图"))
            this._RefreshFormalScreenShotVisibility(id)
        else if (d.type == GetLang("注释"))
            this._RefreshCommentInline(id, d)
    }

    ; 编辑器确定后：就地把数据写回内联控件值（不整窗 _Render，避免闪烁）。
    ; 已支持的类型返回 true；未覆盖的类型返回 false，由调用方回退到 _Render。
    ; 只设置已有控件的值（SelectedIndex/Text/IsChecked）+ 显隐刷新，不重建命名元素，
    ; 因此不会触发 NameScope 名称冲突或选中漂移。
    _RefreshFormalInline(id, d) {
        if (this.ui == "")
            return false
        if (d.type == GetLang("宏操作")) {
            this._RefreshSubMacroInline(id, d)
            return true
        }
        if (d.type == GetLang("变量")) {
            this._RefreshVariableInline(id, d)
            return true
        }
        if (d.type == GetLang("文件读写")) {
            this._RefreshFileIOInline(id, d)
            return true
        }
        if (d.type == GetLang("数组")) {
            this._RefreshArrayInline(id, d)
            return true
        }
        if (d.type == GetLang("文本处理")) {
            this._RefreshTextOpsInline(id, d)
            return true
        }
        if (d.type == GetLang("循环")) {
            this._RefreshLoopInline(id, d)
            return true
        }
        if (d.type == GetLang("如果")) {
            this._RefreshIfInline(id, d)
            return true
        }
        if (d.type == GetLang("如果Pro")) {
            this._RefreshIfProInline(id, d)
            return true
        }
        if (d.type == GetLang("RMT指令")) {
            this._RefreshRmtInline(id, d)
            return true
        }
        if (d.type == GetLang("后台鼠标")) {
            this._RefreshBGMouseInline(id, d)
            return true
        }
        if (d.type == GetLang("后台按键")) {
            this._RefreshBGKeyInline(id, d)
            return true
        }
        if (d.type == GetLang("窗口管理")) {
            this._RefreshWindowManageInline(id, d)
            return true
        }
        if (d.type == GetLang("按键检测")) {
            this._RefreshKeyCheckInline(id, d)
            return true
        }
        if (d.type == GetLang("抓图")) {
            this._RefreshScreenShotInline(id, d)
            return true
        }
        if (d.type == GetLang("注释")) {
            this._RefreshCommentInline(id, d)
            return true
        }
        return false
    }

    ; 注释节点：正文写回 Content，并同步 CurCMD 备注后缀（与 CommentGui.GetCommandStr 一致）
    _OnFormalComment(id, state, ctrl, event) {
        data := this._FormalIniData(id)
        if (data == "")
            return
        if (!IsObject(state))
            state := Map()
        key := "CommentText_" id
        if (!state.Has(key) && this.ui != "")
            state[key] := this.ui.Query(key)
        if (!state.Has(key))
            return
        content := Trim(state[key])
        if (content == "")
            content := GetLang("请输入注释内容")
        data.Content := content
        SaveMacroCMDData(data)
        this.cmdNodes[id].CurCMD := this._CommentCmdFromData(data)
        if (this.ui != "") {
            h := this._CommentTextHeight(content)
            this.ui.Update(key, "Text", content)
            this.ui.Update(key, "Height", String(h))
            this.ui.Update("Title_" id, "Text", GetLang("注释"))
        }
        this._Apply()
    }

    ; 由 CommentData 生成带备注后缀的 CurCMD（备注取内容前 20 字）
    _CommentCmdFromData(data) {
        SplitSerialTextAndNumbers(data.SerialStr, &textOnly, &numbersOnly)
        cmd := Format("{}{}", GetLang(textOnly), numbersOnly)
        remark := data.Content
        if (StrLen(remark) > 20)
            remark := SubStr(remark, 1, 20) "..."
        return CorrectRemark(cmd, remark)
    }

    _RefreshCommentInline(id, d) {
        if (this.ui == "")
            return
        content := d.HasOwnProp("commentContent") ? d.commentContent : GetLang("请输入注释内容")
        h := this._CommentTextHeight(content)
        this.ui.Update("CommentText_" id, "Text", content)
        this.ui.Update("CommentText_" id, "Height", String(h))
        this.ui.Update("Title_" id, "Text", GetLang("注释"))
    }

    ; RMT指令节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshRmtInline(id, d) {
        categories := this._RmtCategories()
        currentCategory := d.HasOwnProp("rmtCategory") ? d.rmtCategory : GetLang("全部")
        currentOp := d.HasOwnProp("rmtOp") ? d.rmtOp : GetLang("截图")
        ops := this._RmtCategoryOps(currentCategory)
        if (!this._ArrayContains(ops, GetLang(currentOp)) && !this._ArrayContains(ops, currentOp)) {
            currentCategory := GetLang("全部")
            ops := this._RmtCategoryOps(currentCategory)
        }
        catIdx := this._IndexInLangArr(categories, GetLang(currentCategory))
        if (catIdx < 0)
            catIdx := this._IndexInLangArr(categories, currentCategory)
        this.ui.Update("RmtCatCmb_" id, "SelectedIndex", Max(0, catIdx))
        this.ui.Update("RmtOpCmb_" id, "ClearItems", "")
        for op in ops
            this.ui.Update("RmtOpCmb_" id, "AddItem", op)
        opIdx := this._RmtOpIdx(ops, currentOp)
        if (opIdx < 0)
            opIdx := this._RmtOpIdx(ops, GetLang(currentOp))
        this.ui.Update("RmtOpCmb_" id, "SelectedIndex", Max(0, opIdx))
        showMenu := (currentOp == GetLang("显示菜单") || GetLang(currentOp) == GetLang("显示菜单"))
        this._FormalSetVis(id, "RmtMenuRow_" id, showMenu)
        if (showMenu) {
            this.ui.Update("RmtMenuCmb_" id, "IsEnabled", "True")
            menuItems := this._FormalMenuIndexItems()
            if (menuItems.Length > 0) {
                this.ui.Update("RmtMenuCmb_" id, "ClearItems", "")
                for item in menuItems
                    this.ui.Update("RmtMenuCmb_" id, "AddItem", item)
                menuIdx := (d.HasOwnProp("rmtMenuIdx") && IsNumber(d.rmtMenuIdx)) ? Integer(d.rmtMenuIdx) - 1 : 0
                this.ui.Update("RmtMenuCmb_" id, "SelectedIndex", Max(0, menuIdx))
            }
        }
    }

    ; 循环节点：编辑器确定后就地刷新内联控件值与循环体卡片（避免整窗 _Render 闪烁）。
    _RefreshLoopInline(id, d) {
        condiTypes := this._LoopCondiTypes()
        logicTypes := this._LoopLogicTypes()
        cmpTypes := this._LoopCmpTypes()
        condiType := d.HasOwnProp("condiType") ? d.condiType : 1
        logicType := d.HasOwnProp("logicType") ? d.logicType : 1
        this.ui.Update("LoopCount_" id, "Text", this._LoopCountText(d))
        this.ui.Update("LoopCondiCmb_" id, "SelectedIndex", Max(0, condiType - 1))
        this.ui.Update("LoopLogicCmb_" id, "SelectedIndex", Max(0, logicType - 1))
        loop 4 {
            slot := A_Index
            p := "LoopC" slot
            on := d.HasOwnProp("loopTog" slot) && (d["loopTog" slot] == 1 || d["loopTog" slot] == "1")
            nm := d.HasOwnProp("loopName" slot) ? d["loopName" slot] : "Var" slot
            cmp := d.HasOwnProp("loopCmp" slot) ? d["loopCmp" slot] : 1
            vr := d.HasOwnProp("loopVar" slot) ? d["loopVar" slot] : "Var" slot
            this.ui.Update(p "Tog_" id, "IsChecked", on ? "True" : "False")
            this.ui.Update(p "Name_" id, "Text", GetLang(nm))
            this.ui.Update(p "Cmp_" id, "SelectedIndex", cmp - 1)
            this.ui.Update(p "Var_" id, "Text", GetLang(vr))
        }
        this._RefreshLoopChips(id)
        this._RefreshLoopSummary(id)
        this._RefreshLoopBodyNode(id)
        this._RefreshFormalLoopVisibility(id)
    }

    ; 如果节点：编辑器确定后就地刷新内联控件值与分支节点内容（避免整窗 _Render 闪烁）。
    _RefreshIfInline(id, d) {
        logicTypes := this._IfLogicTypes()
        cmpTypes := this._IfCmpTypes()
        logicType := d.HasOwnProp("logicType") ? d.logicType : 1
        saveOn := d.HasOwnProp("saveToggle") && (d.saveToggle == 1 || d.saveToggle == "1")
        saveName := d.HasOwnProp("saveName") ? d.saveName : GetLang("结果")
        trueVal := d.HasOwnProp("trueValue") ? d.trueValue : 1
        falseVal := d.HasOwnProp("falseValue") ? d.falseValue : 0
        this.ui.Update("IfLogicCmb_" id, "SelectedIndex", Max(0, logicType - 1))
        loop 4 {
            slot := A_Index
            p := "IfC" slot
            on := (slot == 1) ? true : (d.HasOwnProp("ifTog" slot) && (d["ifTog" slot] == 1 || d["ifTog" slot] == "1"))
            if (slot == 1 && d.HasOwnProp("ifTog1"))
                on := d["ifTog1"] == 1 || d["ifTog1"] == "1"
            nm := d.HasOwnProp("ifName" slot) ? d["ifName" slot] : "Var" slot
            cmp := d.HasOwnProp("ifCmp" slot) ? d["ifCmp" slot] : 1
            vr := d.HasOwnProp("ifVar" slot) ? d["ifVar" slot] : "Var" slot
            this.ui.Update(p "Tog_" id, "IsChecked", on ? "True" : "False")
            this.ui.Update(p "Name_" id, "Text", GetLang(nm))
            this.ui.Update(p "Cmp_" id, "SelectedIndex", cmp - 1)
            this.ui.Update(p "Var_" id, "Text", GetLang(vr))
        }
        this.ui.Update("IfSaveTog_" id, "IsChecked", saveOn ? "True" : "False")
        this.ui.Update("IfSaveName_" id, "Text", GetLang(saveName))
        this.ui.Update("IfTrueVal_" id, "Text", trueVal)
        this.ui.Update("IfFalseVal_" id, "Text", falseVal)
        this._RefreshFormalIfVisibility(id)
        if (this._branchInjected.Has(id)) {
            this._RefreshBranchBody(id, true)
            this._RefreshBranchBody(id, false)
        }
    }

    ; 数组节点：编辑器确定后就地刷新内联控件值（避免整窗 _Render 闪烁）。
    _RefreshArrayInline(id, d) {
        typeNames := GetLangArr(["创建", "克隆", "删除", "包含", "取值", "赋值", "插入", "追加", "移除", "移除最后", "反转", "长度"])
        argsTypes := GetLangArr(["变量或值", "数组"])
        at := d.HasOwnProp("arrayType") ? d.arrayType : "创建"
        an := d.HasOwnProp("arrayName") ? d.arrayName : "Arr"
        ign := d.HasOwnProp("isIgnoreExist") ? d.isIgnoreExist : 0
        initTxt := d.HasOwnProp("initArr") ? this._FormalInitArrText(d.initArr) : "1,2,3,4,5"
        mi := d.HasOwnProp("mainIndex") ? d.mainIndex : 0
        ai := d.HasOwnProp("argsIndex") ? d.argsIndex : 1
        agt := d.HasOwnProp("argsType") ? d.argsType : "变量或值"
        agn := d.HasOwnProp("argsName") ? d.argsName : "Var1"
        st := d.HasOwnProp("saveType") ? d.saveType : "变量"
        sn := d.HasOwnProp("saveName") ? d.saveName : "Data"
        f := this._ArrFlags(at)
        this.ui.Update("ArrTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(typeNames, GetLang(at)))
        this.ui.Update("ArrName_" id, "Text", an)
        this.ui.Update("ArrIgn_" id, "IsChecked", ((ign == 1 || ign == "1") && f.ShowIgn) ? "True" : "False")
        this.ui.Update("ArrInit_" id, "Text", initTxt)
        this.ui.Update("ArrMain_" id, "Text", GetLang(mi))
        this.ui.Update("ArrArgsIdx_" id, "Text", GetLang(ai))
        this.ui.Update("ArrArgsTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(argsTypes, GetLang(agt)))
        ; 余下（保存类型固定/释放、参数值/保存名列表回填、各行显隐）统一交给 options 刷新
        this._RefreshArrayOptions(id, at, agt, st, agn, sn)
    }

    _RefreshFileIOInline(id, d) {
        encodings := GetLangArr(["UTF-8", "UTF-16", "GBK", "ANSI"])
        operTypes := GetLangArr(["读取Excel", "写入Excel", "读取文本文件", "写入文本文件"])
        enc := d.HasOwnProp("encoding") ? d.encoding : "UTF-8"
        ot := d.HasOwnProp("operType") ? d.operType : "读取Excel"
        om := d.HasOwnProp("operMode") ? d.operMode : "单元格"
        modeItems := this._FormalFileIOOperModes(ot)
        ; 更新控件值
        this.ui.Update("FIOTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(operTypes, GetLang(ot)))
        this.ui.Update("FIOModeCmb_" id, "ClearItems", "")
        for it in modeItems
            this.ui.Update("FIOModeCmb_" id, "AddItem", it)
        this.ui.Update("FIOModeCmb_" id, "SelectedIndex", this._IndexInLangArr(modeItems, GetLang(om)))
        this.ui.Update("FIOPath_" id, "Text", d.HasOwnProp("filePath") ? d.filePath : "")
        this.ui.Update("FIOSheet_" id, "Text", d.HasOwnProp("NameOrSerial") ? d.NameOrSerial : 1)
        this.ui.Update("FIOEncCmb_" id, "SelectedIndex", this._IndexInLangArr(encodings, GetLang(enc)))
        ; 保存类型自动固定：读取Excel+单元格/读取文本+全部/指定行 → 变量；其他 → 数组
        IsResOnlyVar := (ot == "读取Excel" && om == "单元格") || (ot == "读取文本文件" && (om == "读取全部内容" || om == "指定行"))
        autoSaveType := IsResOnlyVar ? GetLang("变量") : GetLang("数组")
        this.ui.Update("FIOSaveType_" id, "Text", autoSaveType)
        ; 更新保存名选项列表
        saveNameList := IsResOnlyVar ? GetGuiVarArr() : GetGuiArrNameArr()
        this.ui.Update("FIOSave_" id, "ClearItems", "")
        for name in saveNameList
            this.ui.Update("FIOSave_" id, "AddItem", name)
        this.ui.Update("FIOSave_" id, "Text", d.HasOwnProp("saveName") ? d.saveName : "Data")
        ; 刷新显隐
        this._RefreshFormalFileIOVisibility(id)
    }

    _RefreshSubMacroInline(id, d) {
        macroTypes := GetLangArr(["当前宏", "按键宏", "字串宏", "菜单宏", "定时宏", "宏"])
        callTypes := GetLangArr(["插入到当前宏", "触发", "暂停", "取消暂停", "终止"])
        mt := d.HasOwnProp("macroType") ? d.macroType : "按键宏"
        ct := d.HasOwnProp("callType") ? d.callType : "触发"
        idx := d.HasOwnProp("index") ? d.index : 1
        ins := d.HasOwnProp("insertCount") ? d.insertCount : "1"
        this.ui.Update("SubTypeCmb_" id, "SelectedIndex", this._IndexInLangArr(macroTypes, GetLang(mt)))
        this.ui.Update("SubCallCmb_" id, "SelectedIndex", this._IndexInLangArr(callTypes, GetLang(ct)))
        this.ui.Update("SubIns_" id, "Text", GetLang(ins))
        ; 宏序号下拉项随宏类型变化：在同一控件上清空重填（无新命名元素，安全）
        idxItems := this._FormalMacroIndexItems(mt)
        this.ui.Update("SubIdxCmb_" id, "ClearItems", "")
        for it in idxItems
            this.ui.Update("SubIdxCmb_" id, "AddItem", it)
        if (idxItems.Length > 0)
            this.ui.Update("SubIdxCmb_" id, "SelectedIndex", Max(0, idx - 1))
        this._RefreshFormalSubMacroVisibility(id)
    }

    _RefreshVariableInline(id, d) {
        ign := d.HasOwnProp("isIgnoreExist") ? d.isIgnoreExist : 0
        this.ui.Update("VarIgn_" id, "IsChecked", (ign == 1 || ign == "1") ? "True" : "False")
        sysItems := GetSystemVarArr()
        loop 4 {
            slot := A_Index
            p := "VarS" slot
            toggled := d.HasOwnProp("toggle" slot) ? d["toggle" slot] : (slot == 1 ? 1 : 0)
            on := this._FormalVarSlotOn(toggled)
            ot := d.HasOwnProp("operaType" slot) ? d["operaType" slot] : 1
            vn := d.HasOwnProp("variable" slot) ? d["variable" slot] : "Var" slot
            cv := d.HasOwnProp("copyVar" slot) ? d["copyVar" slot] : "0"
            minv := d.HasOwnProp("minVar" slot) ? d["minVar" slot] : "0"
            maxv := d.HasOwnProp("maxVar" slot) ? d["maxVar" slot] : "10"
            this.ui.Update(p "Tog_" id, "IsChecked", on ? "True" : "False")
            this.ui.Update(p "OpCmb_" id, "SelectedIndex", ot - 1)
            this.ui.Update(p "Name_" id, "Text", GetLang(vn))
            this.ui.Update(p "Copy_" id, "Text", GetLang(cv))
            this.ui.Update(p "CopyTxt_" id, "Text", cv)   ; 字符纯文本框（与数值下拉共享 copyVar 数据）
            this.ui.Update(p "Min_" id, "Text", GetLang(minv))
            this.ui.Update(p "Max_" id, "Text", GetLang(maxv))
            this.ui.Update(p "SysCmb_" id, "SelectedIndex", this._IndexInLangArr(sysItems, GetLang(cv)))
        }
        this._RefreshFormalVariableVisibility(id)
        this._RefreshVariableSummary(id)
    }

    _FormalSummary(d) {
        if (d.type == GetLang("宏操作")) {
            s := GetLang(d.HasOwnProp("macroType") ? d.macroType : "按键宏") " / " GetLang(d.HasOwnProp("callType") ? d.callType : "触发")
            if (d.HasOwnProp("index") && GetLangKey(d.HasOwnProp("macroType") ? d.macroType : "按键宏") != "当前宏")
                s .= " #" d.index
            return s
        }
        if (d.type == GetLang("变量")) {
            parts := []
            loop 4 {
                slot := A_Index
                if (d.HasOwnProp("toggle" slot) && (d["toggle" slot] == 1 || d["toggle" slot] == "1")) {
                    vn := d.HasOwnProp("variable" slot) ? d["variable" slot] : "Var" slot
                    ot := d.HasOwnProp("operaType" slot) ? d["operaType" slot] : 1
                    cv := d.HasOwnProp("copyVar" slot) ? d["copyVar" slot] : ""
                    minv := d.HasOwnProp("minVar" slot) ? d["minVar" slot] : ""
                    maxv := d.HasOwnProp("maxVar" slot) ? d["maxVar" slot] : ""
                    if (ot == 2)
                        parts.Push(vn "=" minv "~" maxv)
                    else if (cv != "")
                        parts.Push(vn "=" cv)
                    else
                        parts.Push(vn)
                }
            }
            result := ""
            for index, part in parts {
                if (index > 1)
                    result .= ", "
                result .= part
            }
            return parts.Length ? result : GetLang("未配置")
        }
        if (d.type == GetLang("变量提取")) {
            extKeys := GetLangArr(["屏幕", "剪切板", "窗口"])
            idx := d.HasOwnProp("extractType") ? d.extractType : 1
            return (d.HasOwnProp("extractStr") && d.extractStr != "") ? SubStr(d.extractStr, 1, 16) : extKeys[idx]
        }
        if (d.type == GetLang("运算")) {
            loop 4 {
                if (d.HasOwnProp("opToggle" A_Index) && (d["opToggle" A_Index] == 1 || d["opToggle" A_Index] == "1"))
                    return (d.HasOwnProp("updateName" A_Index) ? d["updateName" A_Index] : "Var" A_Index) " = " SubStr(d.HasOwnProp("expression" A_Index) ? d["expression" A_Index] : "", 1, 20)
            }
            return GetLang("运算")
        }
        if (d.type == GetLang("运行")) {
            p := d.HasOwnProp("target") ? d.target : ""
            if (StrLen(p) > 28)
                p := SubStr(p, 1, 28) "..."
            return p
        }
        if (d.type == GetLang("文件读写"))
            return GetLang(d.HasOwnProp("operType") ? d.operType : "读取Excel") " / " GetLang(d.HasOwnProp("operMode") ? d.operMode : "单元格")
        if (d.type == GetLang("文本处理"))
            return GetLang(d.HasOwnProp("textOpsType") ? d.textOpsType : "文本分割")
        if (d.type == GetLang("数组"))
            return GetLang(d.HasOwnProp("arrayType") ? d.arrayType : "创建") " / " (d.HasOwnProp("arrayName") ? d.arrayName : "Arr")
        if (d.type == GetLang("RMT指令"))
            return d.HasOwnProp("rmtOp") ? d.rmtOp : GetLang("截图")
        if (d.type == GetLang("后台鼠标")) {
            mt := d.HasOwnProp("bgMouseType") ? d.bgMouseType : 1
            if (mt == 4)
                return GetLang("滚轮")
            opKeys := ["点击", "双击", "按下", "松开"]
            idx := d.HasOwnProp("bgOperateType") ? d.bgOperateType : 1
            return GetLang(opKeys[idx])
        }
        if (d.type == GetLang("后台按键")) {
            if (d.HasOwnProp("bgKeyStr") && d.bgKeyStr != "")
                return d.bgKeyStr
            typeKeys := ["按下", "松开", "点击"]
            idx := d.HasOwnProp("bgKeyType") ? d.bgKeyType : 1
            return GetLang(typeKeys[idx])
        }
        if (d.type == GetLang("窗口管理"))
            return GetLang(d.HasOwnProp("wmActionType") ? d.wmActionType : "激活窗口")
        if (d.type == GetLang("按键检测")) {
            if (d.HasOwnProp("kcKeyStr") && d.kcKeyStr != "")
                return d.kcKeyStr
            return (d.HasOwnProp("kcVarName") && d.kcVarName != "") ? d.kcVarName : GetLang("按键检测")
        }
        if (d.type == GetLang("抓图")) {
            ssKeys := ["屏幕抓图", "窗口抓图"]
            idx := d.HasOwnProp("ssType") ? d.ssType : 1
            return GetLang(ssKeys[idx])
        }
        if (d.type == GetLang("注释")) {
            c := d.HasOwnProp("commentContent") ? d.commentContent : ""
            if (StrLen(c) > 28)
                c := SubStr(c, 1, 28) "..."
            return c != "" ? c : GetLang("注释")
        }
        if (d.type == GetLang("循环")) {
            lc := d.HasOwnProp("loopCount") ? d.loopCount : 10
            cntStr := (lc == -1 || lc == "-1") ? GetLang("无限") : (GetLang("循环") " " lc)
            return cntStr " · " this._LoopBodyCmds(d).Length
        }
        return d.raw
    }
}

_GraftMacroGraphMixin(MacroGraphFormalHandlersMixin)