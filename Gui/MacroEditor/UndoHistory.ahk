
    ; ==================== §1 撤销/重做 ====================

    ; 捕获当前完整编辑状态：根宏串（树或文本）+ 树上所有命令的 Data 深快照。
    ; 命令参数存在以序列号为键的 Data 对象里（含 搜索/如果/循环 等分支内容），
    ; 仅存根宏串无法还原分支，因此必须连 Data 一起快照。
    _CaptureUndoSnapshot() {
        snap := {root: "", data: Map()}
        if (this.EditModeCon.Value == 1) {
            snap.root := this.GetTreeMacroStr(0)
        }
        else {
            snap.root := this.MacroEditTextCon.Value
        }
        this._CollectSnapshotData(0, snap.data)
        return snap
    }

    ; 递归收集树上全部命令节点的 Data JSON（含嵌套分支内的命令）
    ; 注意：dataMap 不能声明为 ByRef——调用处传的是 snap.data（对象属性，非变量引用），
    ; Map 本身是引用类型，去 ByRef 后对 Map 的写入依旧原地生效。
    _CollectSnapshotData(itemID, dataMap) {
        childID := this.MacroTreeViewCon.GetChild(itemID)
        while (childID) {
            text := this.MacroTreeViewCon.GetText(childID)
            if (text != "" && SubStr(text, 1, 1) != "⎖") {
                cmdStr := MySoftData.ParseCmdJoyDisplay(text)
                ; N11：取「命令名」（首段），非身份签名；与 OnLoop 的 StrSplit(cmd,"_")[1] 取 Data 惯例一致
                cmdName := StrSplit(GetCmdStr(CmdStripCurPos(cmdStr)), "_")[1]
                if (cmdName != "" && !dataMap.Has(cmdName)) {
                    try {
                        Data := GetMacroCMDData(cmdName)
                        dataMap[cmdName] := JSON.stringify(Data, 0)
                    }
                }
                this._CollectSnapshotData(childID, dataMap)
            }
            childID := this.MacroTreeViewCon.GetNext(childID)
        }
    }

    ; 入栈前状态快照（上限 100 条，超出丢最旧）；批量组合操作期间静默
    _PushUndo() {
        if (this._undoBatch > 0)
            return
        snap := this._CaptureUndoSnapshot()
        this._undoStack.Push(snap)
        if (this._undoStack.Length > 100)
            this._undoStack.RemoveAt(1)
        this._redoStack := []
        this._SyncUndoBtns()
    }

    Undo() {
        if (this._undoStack.Length == 0)
            return
        this._redoStack.Push(this._CaptureUndoSnapshot())
        snap := this._undoStack.Pop()
        this._RestoreSnapshot(snap)
        this._SyncUndoBtns()
    }

    Redo() {
        if (this._redoStack.Length == 0)
            return
        this._undoStack.Push(this._CaptureUndoSnapshot())
        snap := this._redoStack.Pop()
        this._RestoreSnapshot(snap)
        this._SyncUndoBtns()
    }

    ; 撤销/重做可用性同步到按钮（简单起见仅刷新 IsEnabled）
    _SyncUndoBtns() {
        if (!IsObject(this.ui))
            return
        try this.ui.Update("BtnUndo", "IsEnabled", this._undoStack.Length > 0 ? "True" : "False")
        try this.ui.Update("BtnRedo", "IsEnabled", this._redoStack.Length > 0 ? "True" : "False")
    }

    ; 恢复快照：先写回各命令 Data（缓存+文件），再重建树/文本
    _RestoreSnapshot(snap) {
        for serial, json in snap.data {
            try this._RestoreCmdData(serial, json)
        }
        if (this.EditModeCon.Value == 1) {
            this.InitTreeView(snap.root)
            this.ClearMultiSelection()
            this.CurItemID := 0
            if (IsObject(this.MacroTreeViewCon) && this.MacroTreeViewCon.HasMethod("Unselect"))
                this.MacroTreeViewCon.Unselect()
        }
        else {
            this.InitMacroText(snap.root)
        }
    }

    ; 把某命令的 Data 快照写回数据文件并清缓存（与 SaveMacroCMDData 同链路）
    ; 注意：快照 serial 来自显示文本（英文模式可能是 "Key004"），
    ; 但数据文件键恒为中文序列码（"按键004"，GetCMDSerialStr 内部 GetLangKey 转回），
    ; 落盘与清缓存都必须用规范化键 cmdKey+序号。
    _RestoreCmdData(serial, json) {
        dummy := ""
        SplitSerialTextAndNumbers(serial, &textOnly, &dummy)
        cmdKey := GetLangKey(textOnly)
        if (!MySoftData.DataFileMap.Has(cmdKey))
            return
        file := MySoftData.DataFileMap[cmdKey]
        normalized := cmdKey . dummy
        CfgWrite(json, file, SettingSection, normalized)
        if (MySoftData.DataCacheMap.Has(normalized))
            MySoftData.DataCacheMap.Delete(normalized)
        if (serial != normalized && MySoftData.DataCacheMap.Has(serial))
            MySoftData.DataCacheMap.Delete(serial)
    }

    ; 一组用户操作只记一次撤销（如整段粘贴、图形转线性）
    _BeginUndoBatch() {
        this._undoBatch += 1
    }

    _EndUndoBatch() {
        if (this._undoBatch > 0)
            this._undoBatch -= 1
        if (this._undoBatch == 0 && this._sideMode && this._pendingSideNotify)
            this._NotifyMacroChanged()
    }
