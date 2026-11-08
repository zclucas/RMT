
    ; 重置调试状态（清空位置/→标记 + 清空步入栈 + 关闭拦截钩子 + 清控制标志）
    ResetDebugState() {
        this.DebugItemID := 0
        this.ClearCurrentPosition()
        if (IsObject(this.DebugStack))
            this.DebugStack := []
        this._CloseDebugHook()
        this._ClearFlags()
    }

    ; 标记当前位置（纯指针：只改节点字段 + Cur_ 图标可见性，绝不写文本，解 G1）
    MarkCurrentPosition(itemID) {
        ; 先清除旧位置
        if (this.CurrentItemID && this.CurrentItemID != itemID) {
            try this.MacroTreeViewCon.SetCurrentPos(this.CurrentItemID, false)
            catch {
                ; 旧项可能已失效或适配器不支持，忽略
            }
        }
        ; 在新项上标记（🚫 禁用 / ⎖ 容器配置项不作位置标记）
        try {
            text := this.MacroTreeViewCon.GetText(itemID)
            cleanText := CmdStripCurPos(CmdStripDebug(text))
            if (SubStr(cleanText, 1, 2) != "🚫" && SubStr(cleanText, 1, 1) != "⎖")
                this.MacroTreeViewCon.SetCurrentPos(itemID, true)
        } catch {
            ; 忽略
        }
        this.CurrentItemID := itemID
    }

    ; 清除当前位置标记（纯指针）
    ClearCurrentPosition() {
        if (!this.CurrentItemID)
            return
        try this.MacroTreeViewCon.SetCurrentPos(this.CurrentItemID, false)
        catch {
            ; 忽略
        }
        this.CurrentItemID := 0
    }

    ; ==================== 调试步入内核（全容器步入 + 断点，v2 §12） ====================

    ; 惰性建立调试拦截钩子（主进程调试期非空；Worker 不实例化本类 → 恒不存在）
    _EnsureDebugHook() {
        if (!MySoftData.HasProp("DebugHook"))
            MySoftData.DebugHook := { active: false, recorded: false, containerId: 0, kind: "", branchField: "", hitIndex: -1, controlType: "" }
        return MySoftData.DebugHook
    }

    ; 关闭钩子（清激活标志；保留结构供下次复用）
    _CloseDebugHook() {
        if (MySoftData.HasProp("DebugHook") && IsObject(MySoftData.DebugHook))
            MySoftData.DebugHook.active := false
    }

    ; 落位：设 DebugItemID 并标 →（纯指针，不写文本）
    _Goto(itemID) {
        this.DebugItemID := itemID
        this.MarkCurrentPosition(itemID)
    }

    ; 节点文本：去 →/▶/⭐（保留 🚫/⎖，供 _IsSkippable 判定）
    _RawText(id) {
        t := ""
        try t := this.MacroTreeViewCon.GetText(id)
        return CmdStripCurPos(CmdStripDebug(t))
    }

    ; 节点文本：完全清洗（去 →/▶/⭐/🚫/⎖/空格），供分支容器名比较
    _CleanText(id) {
        t := this._RawText(id)
        while (t != "") {
            ch := SubStr(t, 1, 1)
            if (ch == "🚫" || ch == "⎖" || ch == " ")
                t := SubStr(t, 2)
            else
                break
        }
        return t
    }

    _IsSkipRow(t) => SubStr(t, 1, 2) == "🚫"

    _IsCfgRow(t) => SubStr(t, 1, 1) == "⎖"

    _IsSkippable(t) => (this._IsSkipRow(t) || this._IsCfgRow(t))

    ; 单步执行用的 scratch 条目（SpecialTableItem；空表返回 ""）
    _SpecialItem() {
        ti := MySoftData.SpecialTableItem
        if (!IsObject(ti) || ti.Items.Length < 1)
            return ""
        return ti.Items[1]
    }

    ; 读取三控制标志（缺失键按 false 兜底，不抛错）
    _Flags() {
        item := this._SpecialItem()
        brk := false, skip := false, brch := false
        if (item && IsObject(item.VariableMap)) {
            if (item.VariableMap.Has("循环-跳出"))
                brk := !!item.VariableMap["循环-跳出"]
            if (item.VariableMap.Has("循环-跳过本轮"))
                skip := !!item.VariableMap["循环-跳过本轮"]
            if (item.VariableMap.Has("分支-跳出"))
                brch := !!item.VariableMap["分支-跳出"]
        }
        return { brk: brk, skip: skip, brch: brch }
    }

    ; 清三控制标志（仅清已有键，绝不新增/写坏 VariableMap）
    _ClearFlags() {
        item := this._SpecialItem()
        if (!item || !IsObject(item.VariableMap))
            return
        if (item.VariableMap.Has("分支-跳出"))
            item.VariableMap["分支-跳出"] := false
        if (item.VariableMap.Has("循环-跳过本轮"))
            item.VariableMap["循环-跳过本轮"] := false
        if (item.VariableMap.Has("循环-跳出"))
            item.VariableMap["循环-跳出"] := false
    }

    ; 安全取同级下一条（异常 → 0）
    _SafeGetNext(id) {
        try
            return this.MacroTreeViewCon.GetNext(id)
        catch
            return 0
    }

    ; 由容器命令节点 + 钩子回报的命中分支，定位「分支容器节点」。
    ; 注：钩子 hitIndex 为 1 基（守卫直传 A_Index），故此处条件序号按 1 基计数。
    _FindBranchChild(containerID, kind, hitIndex, branchField) {
        childID := 0
        try childID := this.MacroTreeViewCon.GetChild(containerID)
        catch
            return 0
        condIdx := 0
        lastCond := 0
        condPrefix := GetLang("条件")
        while (childID) {
            t := this._CleanText(childID)
            if (kind == "If" || kind == "Search" || kind == "SearchAll" || kind == "SearchPro" || kind == "SearchCombo" || kind == "SearchMulti") {
                if (branchField == "TrueMacro" && t == GetLang("真"))
                    return childID
                if (branchField == "FalseMacro" && t == GetLang("假"))
                    return childID
            }
            else if (kind == "Loop") {
                if (t == GetLang("循环体"))
                    return childID
            }
            else if (kind == "IfPro") {
                if (condPrefix != "" && SubStr(t, 1, StrLen(condPrefix)) == condPrefix) {
                    condIdx += 1
                    if (branchField == "DefaultMacro")
                        lastCond := childID
                    else if (condIdx == hitIndex)
                        return childID
                }
            }
            try childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
        if (kind == "IfPro" && branchField == "DefaultMacro")
            return lastCond
        return 0
    }

    ; 取某分支容器的「首个可执行子节点」（跳过 🚫/⎖；空 → 0）
    _FirstExecChild(parentID) {
        child := 0
        try child := this.MacroTreeViewCon.GetChild(parentID)
        catch
            return 0
        while (child) {
            if (!this._IsSkippable(this._RawText(child)))
                return child
            try child := this.MacroTreeViewCon.GetNext(child)
            catch
                break
        }
        return 0
    }

    ; 钩子命中 → 压帧 + 下潜（F6 阶段4，hook.recorded==true 时调用）
    _EnterBranchFromHook() {
        try {
            hook := MySoftData.DebugHook
            containerId := hook.containerId
            kind := hook.kind
            branchNodeId := this._FindBranchChild(containerId, kind, hook.hitIndex, hook.branchField)
            if (!branchNodeId) {
                ; H3：找不到分支节点 = 动态内容（宏操作插入串/子宏调用/图形宏）的容器被守卫拦截，
                ; 树上无对应分支可下潜。降级：视为已处理继续推进，不再 EndDebugRun（静默中止会话）。
                ; ⚠️ 分支体未执行（守卫已吞），与真实运行存在差异——Toast 明示。
                this._ClearFlags()
                Toast.Show(GetLang("该分支不支持单步，已跳过"))
                return this.AdvanceToNext()
            }
            loopCount := 0
            infinite := false
            ; N11：取「命令名」（首段）用于 GetMacroCMDData，与 OnLoop 的 StrSplit(cmd,"_")[1] 惯例一致；
            ; 绝不用 BpSig（身份签名）当命令名 —— 旧格式「循环_5」经 BpSig 会得到含 `_` 的整串而抛错。
            cmdName := StrSplit(GetCmdStr(this._CleanText(containerId)), "_")[1]
            if (kind == "Loop") {
                Data := GetMacroCMDData(cmdName)
                if (Data.LoopCount == -1)
                    infinite := true
                else {
                    v := ""
                    hasValue := TryGetTabVarValue(&v, MySoftData.SpecialTableItem, 1, Data.LoopCount)
                    loopCount := hasValue ? Integer(v) : 0
                }
            }
            frame := { containerId: containerId, kind: kind, serial: cmdName, branchNodeId: branchNodeId, branchField: hook.branchField, controlType: hook.controlType, iterIndex: (kind == "Loop") ? 1 : 0, loopCount: loopCount, infinite: infinite, returnNextId: this._SafeGetNext(containerId) }
            ; 自动展开父容器 + 分支容器，保证 → 可见（v1 §3.6）
            try this.MacroTreeViewCon.Modify(containerId, "Expand")
            try this.MacroTreeViewCon.Modify(branchNodeId, "Expand")
            this.DebugStack.Push(frame)
            ; 循环帧：镜像 OnLoop 在体执行前设置「循环次数」，供体内指令读取
            if (kind == "Loop") {
                item := this._SpecialItem()
                if (item && IsObject(item.VariableMap) && item.VariableMap.Has("循环次数"))
                    item.VariableMap["循环次数"] := frame.iterIndex
            }
            ; N1：镜像 OnLoop「写 循环次数:=A_Index → 判本轮条件 → 不通过整轮 break」
            ; （MacroUtil:868-870/:898-900，无限循环分支 :869 同样每轮判）——条件首轮即假时
            ; 真身体一次不进，调试也不得潜入（旧实现无条件直潜 → 恒多跑 1 轮体）。
            ; 判定必须放在 Push+写 循环次数 之后（条件可引用 {循环次数}，与 H1 同理）。
            if (kind == "Loop" && !this._EvalLoopCondition(frame)) {
                this.DebugStack.Pop()
                return this._ResumeAfterFrame(frame)
            }
            first := this._FirstExecChild(branchNodeId)
            if (!first)                                 ; 空分支体 → 立即结算（解 G4）
                return this.CompleteTopFrame()
            this._Goto(first)
        } catch {
            this._ClearFlags()
            this.EndDebugRun()
        }
    }

    ; 帧结算：某帧分支体已执行到末尾（GetNext==0）时调用。
    ; 语义 = 运行时「容器执行完毕 → HandleControlType 设标志 → 所在块 for 逐层消费」的复刻。
    CompleteTopFrame() {
        try {
            if (this.DebugStack.Length == 0) {
                this.EndDebugRun()
                return
            }
            frame := this.DebugStack.Pop()
            ; (1) 镜像 HandleControlType：分支体跑完后设本帧分支 ControlType
            ;     （Loop 帧 controlType 恒为 "" → no-op，与 OnLoop 不调 HandleControlType 一致）
            if (frame.controlType != "" && frame.controlType != "无")
                HandleControlType(MySoftData.SpecialTableItem, 1, frame.controlType)
            ; (2) 读取三标志
            f := this._Flags()
            ; (3) 判定优先级：循环-跳出 > 循环-跳过本轮 > 分支-跳出 > 无
            if (f.brk) {
                this._ClearFlags()
                return this._PopToNearestLoop()
            }
            if (f.skip) {
                this._ClearFlags()
                return this._SkipToNearestLoopIteration()
            }
            if (f.brch) {
                this._ClearFlags()
                return this.CompleteTopFrame()
            }
            ; (4) 无控制标志 → 正常回落。
            ;     Loop 帧 → 进入下一轮（计数/条件判定在 _NextLoopIteration 内）
            this._ClearFlags()
            if (frame.kind == "Loop")
                return this._NextLoopIteration(frame)
            return this._ResumeAfterFrame(frame)
        } catch {
            this._ClearFlags()
            this.EndDebugRun()
        }
    }

    ; 循环-跳出：弹出至最近 Loop 帧（含），去其 returnNextId；无则继续结算父帧
    _PopToNearestLoop() {
        loop {
            if (this.DebugStack.Length == 0) {
                this.EndDebugRun()
                return
            }
            f := this.DebugStack.Pop()
            if (f.kind == "Loop") {
                if (f.returnNextId) {
                    this._Goto(f.returnNextId)
                    return
                }
                return this.CompleteTopFrame()
            }
            ; M1：真实传播途中，中间容器完成仍执行其 HandleControlType（OnCompare:686-687 等）；
            ; 调试弹帧须镜像，否则隔层控制类型（如 分支-跳出）永久丢失
            if (f.controlType != "" && f.controlType != "无")
                HandleControlType(MySoftData.SpecialTableItem, 1, f.controlType)
            ; N3（QA ISSUE-1）：合法消费点（CompleteTopFrame/H2）都在调用本助手前读+清标志，
            ; 此处是唯一「无消费点」的裸置位——真身中该标志由紧邻块级 for 立即消费
            ; （MacroUtil:94-96），弹帧 unwind 本身就是那次消费的镜像 → 置位后立即清除，
            ; 严禁残留到下一帧结算（否则跨帧 unwind 会多弹一层/误终止循环）。
            this._ClearFlags()
        }
    }

    ; 循环-跳过本轮：弹出至最近 Loop 帧（含），进入其下一轮。
    _SkipToNearestLoopIteration() {
        loop {
            if (this.DebugStack.Length == 0) {
                this.EndDebugRun()
                return
            }
            f := this.DebugStack.Pop()
            if (f.kind == "Loop")
                return this._NextLoopIteration(f)
            ; M1：同 _PopToNearestLoop，镜像中间容器的 HandleControlType
            if (f.controlType != "" && f.controlType != "无")
                HandleControlType(MySoftData.SpecialTableItem, 1, f.controlType)
            ; N3：同 _PopToNearestLoop——置位后立即清除，防止残留污染下一帧结算
            this._ClearFlags()
        }
    }

    ; 正常回落：回「容器所在块」的下一条；容器是该块末尾 → 结算父帧
    _ResumeAfterFrame(frame) {
        if (frame.returnNextId) {
            this._Goto(frame.returnNextId)
            return
        }
        return this.CompleteTopFrame()
    }

    ; 循环下一轮：严格镜像真身 OnLoop（MacroUtil:896-919）的轮内次序——
    ;   ①计数边界：loop Value 至多 Value 轮，第 N+1 轮不存在 → 不写「循环次数」、不判条件，直接回落
    ;   ②先写 循环次数:=candidate（H1 修复：真身每轮「先写 A_Index → 再判条件」，
    ;     条件引用 {循环次数} 时必须看到本轮序号；旧实现先判后写 → 恒多跑一轮）
    ;   ③判条件（复用真身 GetLoopState）；失败 → 停在 candidate（真身失败轮同样保留该值，L1 同步对齐）
    ;   ④通过 → iterIndex:=candidate、重新压帧、下潜执行本轮体
    ; 必须重新 Push(frame)：本帧在 CompleteTopFrame 中已被弹出，若不再入栈，
    ; 体末再次 CompleteTopFrame 会误 Pop 父帧。
    _NextLoopIteration(frame) {
        candidate := frame.iterIndex + 1
        if (!frame.infinite && candidate > frame.loopCount)
            return this._ResumeAfterFrame(frame)
        item := this._SpecialItem()
        if (item && IsObject(item.VariableMap) && item.VariableMap.Has("循环次数"))
            item.VariableMap["循环次数"] := candidate
        if (!this._EvalLoopCondition(frame))
            return this._ResumeAfterFrame(frame)
        frame.iterIndex := candidate
        this.DebugStack.Push(frame)          ; 重新入栈：本帧继续追踪下一轮
        first := this._FirstExecChild(frame.branchNodeId)
        if (!first) {                        ; 体结构异常/无内容 → 安全回落，勿递归 CompleteTopFrame
            this.DebugStack.Pop()
            return this._ResumeAfterFrame(frame)
        }
        this._Goto(first)
    }

    ; 重判循环条件：复用运行时 GetLoopState（MacroUtil.ahk，一行不改）
    ; 被 _NextLoopIteration 调用；cmd 传 frame.serial（命令名首段）、index 恒为 1，
    ; 与 OnLoop 内 GetLoopState(tableItem, cmd, index, Data) 等价。
    _EvalLoopCondition(frame) {
        try {
            Data := GetMacroCMDData(frame.serial)
            return GetLoopState(MySoftData.SpecialTableItem, frame.serial, 1, Data)
        } catch {
            return false
        }
    }

    ; 结束调试运行：清状态 + 非模态提示（解 G12，不用模态 MsgBox）
    EndDebugRun() {
        this.ResetDebugState()
        Toast.Show(GetLang("单步运行结束"))
    }

    ; 「继续」(F5)：到下一断点；无断点 → 跑到宏结束（IDE 语义，删去旧 F7 的零断点早退）。
    ; F1：起始/上次停留节点即使本身是断点，也先执行一步 —— 否则连按会在同一断点原地复停。
    ; 走步入引擎逐条执行；maxSteps 兜底防止异常宏卡死。
    ContinueRun() {
        tableItem := MySoftData.SpecialTableItem
        if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState == 1)
            return
        maxSteps := 100000
        steps := 0
        deadline := A_TickCount + 120000            ; V2：2 分钟硬上限（继续=跑到断点，批量执行请用 Ctrl+F5）
        ; 无会话 → 定位起点（=IDE F5 启动）
        if (this.DebugItemID == 0) {
            MyCMDTipGui.Hide()
            id := this.FindDebugStartItem()
            if (!id)
                id := this.MacroTreeViewCon.GetNext(0)
            if (!id) {
                Toast.Show(GetLang("无可运行指令"))
                return
            }
            this._Goto(id)
        }
        this._ClearFlags()                          ; V3：清上次运行残留控制标志（Kill 强杀时 OnLoop 未消费 → 脏标志误读）
        this.DoDebugStep()                          ; F1：先执行一步保进度
        loop {
            if (++steps > maxSteps) {
                this.ResetDebugState()
                Toast.Show(GetLang("调试步骤过多，已退出"))
                return
            }
            if (A_TickCount > deadline) {           ; V2：时间兜底（无人值守冻结逃生）
                this.ResetDebugState()
                Toast.Show(GetLang("调试运行超时，已退出"))
                return
            }
            cur := this.DebugItemID
            if (!cur)                               ; 宏结束（EndDebugRun 已清态）
                return
            if (this._IsSkippable(this._RawText(cur))) {   ; 不可执行项 → 只推进
                this.AdvanceToNext()
                continue
            }
            if (this.MacroTreeViewCon.IsBreakPoint(cur))   ; 新抵达断点 → 停在此（下次执行）
                return
            this.DoDebugStep()                      ; 继续执行一步（容器则步入）
        }
    }

    ; 步入（F11）：进入容器分支（=旧 F6 语义，零算法改动）
    StepInto() {
        this.DoDebugStep(true)
    }

    ; 步进（F10）：不进入容器，整体真实执行（into=false → 不给 hook 置 active，容器整段运行）
    StepOver() {
        this.DoDebugStep(false)
    }

    ; 步出（Shift+F11）：跑完/离开当前帧再停（字面帧退出，Q-B）。into=false：不调试嵌套容器内部。
    StepOut() {
        tableItem := MySoftData.SpecialTableItem
        if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState == 1)
            return
        if (this.DebugItemID == 0) {
            Toast.Show(GetLang("请先开始调试"))
            return
        }
        depth := this.DebugStack.Length
        if (depth == 0) {                           ; 顶层无帧可出
            Toast.Show(GetLang("已在顶层，运行到结束"))
            return this.ContinueRun()
        }
        maxSteps := 100000
        steps := 0
        deadline := A_TickCount + 120000            ; V2：时间兜底（无限循环步出防冻结）
        loop {
            if (++steps > maxSteps) {
                this.ResetDebugState()
                Toast.Show(GetLang("调试步骤过多，已退出"))
                return
            }
            if (A_TickCount > deadline) {
                this.ResetDebugState()
                Toast.Show(GetLang("调试运行超时，已退出"))
                return
            }
            this.DoDebugStep(false)                 ; 只关心当前帧何时结束
            if (this.DebugStack.Length < depth)     ; 已离开当前帧 → 停
                return
            if (this.DebugItemID == 0)              ; 宏结束（EndDebugRun 已清态）
                return
        }
    }

    ; 运行到光标处（Ctrl+F10）：跑到 CurItemID；到达即停（不执行目标，等价 IDE 停在该行前）
    RunToCursor() {
        tableItem := MySoftData.SpecialTableItem
        if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState == 1)
            return
        target := this.CurItemID
        if (!target) {
            Toast.Show(GetLang("请先选中要运行的指令"))
            return
        }
        try t := this.MacroTreeViewCon.GetText(target)
        catch {
            Toast.Show(GetLang("目标指令已失效"))
            return
        }
        if (t == "") {                              ; V1：死 id 适配器返回 "" 不抛错 → 显式判死
            Toast.Show(GetLang("目标指令已失效"))
            return
        }
        ; 🚫/⎖ 永被跳过 → 预拒绝（不启动）
        if (SubStr(t, 1, 2) == "🚫" || SubStr(t, 1, 1) == "⎖") {
            Toast.Show(GetLang("该指令不可作为运行目标"))
            return
        }
        ; 无会话 → 定位起点
        if (this.DebugItemID == 0) {
            MyCMDTipGui.Hide()
            id := this.FindDebugStartItem()
            if (!id)
                id := this.MacroTreeViewCon.GetNext(0)
            if (!id) {
                Toast.Show(GetLang("无可运行指令"))
                return
            }
            this._Goto(id)
        }
        this._ClearFlags()                          ; V3：同 ContinueRun，清残留控制标志
        if (this.DebugItemID == target) {           ; Q-D：原地不动
            Toast.Show(GetLang("已停在光标处"))
            return
        }
        maxSteps := 100000
        steps := 0
        deadline := A_TickCount + 120000            ; V2：时间兜底
        loop {
            if (++steps > maxSteps) {
                this.ResetDebugState()
                Toast.Show(GetLang("调试步骤过多，已退出"))
                return
            }
            if (A_TickCount > deadline) {
                this.ResetDebugState()
                Toast.Show(GetLang("调试运行超时，已退出"))
                return
            }
            cur := this.DebugItemID
            if (!cur) {                             ; 宏结束/跨分支/被删
                Toast.Show(GetLang("未到达光标处，已运行到结束"))
                return
            }
            if (this._IsSkippable(this._RawText(cur))) {   ; 不可执行项 → 只推进
                this.AdvanceToNext()
                continue
            }
            if (cur == target)                      ; ★到达即停（不执行）
                return
            this.DoDebugStep()                      ; 步入语义：保证分支内目标可达
        }
    }

    ; 深度遍历整棵逻辑树，收集带断点（debugBp）节点的命令签名，规范化为 ",sig1,sig2,"
    GetTreeBreakpoints() {
        sigs := []
        this._CollectBpSigs(0, &sigs)
        if (sigs.Length == 0)
            return ""
        out := ","
        for s in sigs
            out .= s ","
        return out
    }

    _CollectBpSigs(itemID, &sigs) {
        try
            childID := this.MacroTreeViewCon.GetChild(itemID)
        catch
            return
        while (childID) {
            t := this._RawText(childID)
            if (t != "" && SubStr(t, 1, 1) != "⎖" && this.MacroTreeViewCon.IsBreakPoint(childID)) {
                sig := BpSig(t)
                if (sig != "" && !this._BpSigIn(sigs, sig))
                    sigs.Push(sig)
            }
            this._CollectBpSigs(childID, &sigs)
            try
                childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
    }

    _BpSigIn(sigs, sig) {
        for s in sigs
            if (s == sig)
                return true
        return false
    }

    ; 树重建后按断点串重放标记（签名即身份；命中则置节点 debugBp）
    _ApplyBreakpoints(bpStr) {
        if (bpStr == "")
            return
        this._ApplyBpRecurse(0, bpStr)
    }

    _ApplyBpRecurse(itemID, bpStr) {
        try
            childID := this.MacroTreeViewCon.GetChild(itemID)
        catch
            return
        while (childID) {
            t := this._RawText(childID)
            if (t != "" && SubStr(t, 1, 1) != "⎖") {
                sig := BpSig(t)
                if (sig != "" && BpStrHas(bpStr, sig))
                    this.MacroTreeViewCon.SetBreakPoint(childID, true)
            }
            this._ApplyBpRecurse(childID, bpStr)
            try
                childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
    }

    ; 断点变更：刷新本地缓存 + 通知宿主写回（侧栏宿主 → _WriteSideTreeBreakpoints）
    _NotifyBpChanged() {
        bpStr := this.GetTreeBreakpoints()
        this._bpStr := bpStr
        if (IsObject(this.OnBpChanged))
            try this.OnBpChanged.Call(bpStr)
    }

    ; 单步一次：定位 → 跳过不可执行 → 执行一步（into 语义见阶段3）→ 推进
    ; into=true（步入 F11）：容器被钩子拦截 → 下潜分支
    ; into=false（步进 F10 / 步出 / 继续内部推进）：不给 hook 置 active → 容器整体真实执行（天然 Step Over）
    DoDebugStep(into := true) {
        tableItem := MySoftData.SpecialTableItem
        if (tableItem.Items.Length >= 1 && tableItem.Items[1].ColorState == 1)
            return
        ; 阶段1: 定位（首次或终止后，查找⭐起点或第一项）
        if (this.DebugItemID == 0) {
            MyCMDTipGui.Hide()
            this.DebugItemID := this.FindDebugStartItem()
            if (!this.DebugItemID)
                this.DebugItemID := this.MacroTreeViewCon.GetNext(0)
            this._ClearFlags()                      ; V3：清上次运行残留控制标志
        }
        if (!this.DebugItemID)
            return
        try
            CurCMD := this.MacroTreeViewCon.GetText(this.DebugItemID)
        catch {
            this.EndDebugRun()
            return
        }
        if (CurCMD == "") {                         ; V1：死 id 适配器返回 "" 不抛错 → 显式判死
            this.EndDebugRun()
            return
        }
        ; 阶段2: 跳过不可执行项（🚫禁用和⎖容器配置），自动推进不消耗步数
        while (SubStr(CurCMD, 1, 2) == "🚫" || SubStr(CurCMD, 1, 1) == "⎖") {
            this.AdvanceToNext()
            if (!this.DebugItemID)
                return
            try
                CurCMD := this.MacroTreeViewCon.GetText(this.DebugItemID)
            catch {
                this.EndDebugRun()
                return
            }
            if (CurCMD == "") {                     ; V1：死 id 判死（同上）
                this.EndDebugRun()
                return
            }
        }
        ; 阶段3: 标记当前位置 → 激活钩子（active=into）→ 执行单条
        this.MarkCurrentPosition(this.DebugItemID)
        hook := ""
        try {
            ; F8：钩子建立/激活一并纳入 try，避免 _EnsureDebugHook 异常外抛
            hook := this._EnsureDebugHook()
            if (IsObject(hook)) {
                hook.recorded := false            ; ★每步复位，杜绝上一步残留
                hook.containerId := this.DebugItemID
                hook.active := into               ; true=步入；false=步进（不拦截→整体执行）
            }
            CleanCMD := CmdStripCurPos(CmdStripDebug(CurCMD))
            ; 还原格式化的手柄键名后执行
            CleanCMD := MySoftData.ParseCmdJoyDisplay(CleanCMD)
            CurLangCMD := GetLangMacro(CleanCMD, 2)
            OnTriggerSepcialItemMacro(CurLangCMD, true)
        } catch {
            ; 兜底契约：异常即关钩子 + 清标志 + 退出调试（宁可退出，绝不继续不一致状态）
            if (IsObject(hook))
                hook.active := false
            this._ClearFlags()
            this.ResetDebugState()
            Toast.Show(GetLang("调试状态异常，已退出调试"))
            return
        }
        if (IsObject(hook))
            hook.active := false
        ; 单步执行跳转后立即按调试栈结算，避免先执行本应跳过的同级指令。
        flags := this._Flags()
        if (flags.brk || flags.skip || flags.brch) {
            this._ClearFlags()
            if (flags.brk)
                return this._PopToNearestLoop()
            if (flags.skip)
                return this._SkipToNearestLoopIteration()
            return this.CompleteTopFrame()
        }
        ; 阶段4: 按 hook.recorded 分叉——容器被拦截则步入，否则推进到下一项
        if (IsObject(hook) && hook.recorded) {
            this._EnterBranchFromHook()
            return
        }
        this.AdvanceToNext()
    }

    ; 推进到下一个可执行位置；同级耗尽时结算栈顶帧（栈空则结束）
    AdvanceToNext() {
        ; V1：当前节点已被删除（死 id）时 GetNext 会误判「体末」→ 显式判死退出
        try {
            if (this.MacroTreeViewCon.GetText(this.DebugItemID) == "") {
                this.EndDebugRun()
                return
            }
        } catch {
            this.EndDebugRun()
            return
        }
        try
            nextID := this.MacroTreeViewCon.GetNext(this.DebugItemID)
        catch {
            this.EndDebugRun()
            return
        }
        if (nextID) {
            this.DebugItemID := nextID
            this.MarkCurrentPosition(nextID)
            return
        }
        this.CompleteTopFrame()
    }

    ; 递归遍历整个TreeView（含子分支），查找带⭐的调试起点项
    FindDebugStartItem(startID := 0) {
        itemID := this.MacroTreeViewCon.GetNext(startID)
        while (itemID) {
            try
                text := this.MacroTreeViewCon.GetText(itemID)
            catch {
                try
                    itemID := this.MacroTreeViewCon.GetNext(itemID)
                catch
                    break
                continue
            }
            ; 当前项就是调试起点
            if (CmdIsDebug(text))
                return itemID
            ; 递归检查子分支（支持任意层级嵌套）
            found := this._FindStarInChildren(itemID)
            if (found)
                return found
            try
                itemID := this.MacroTreeViewCon.GetNext(itemID)
            catch
                break
        }
        return 0
    }

    ; 在指定节点的所有后代中递归查找⭐
    _FindStarInChildren(parentID) {
        try
            childID := this.MacroTreeViewCon.GetChild(parentID)
        catch
            return 0
        while (childID) {
            try
                childText := this.MacroTreeViewCon.GetText(childID)
            catch {
                try
                    childID := this.MacroTreeViewCon.GetNext(childID)
                catch
                    break
                continue
            }
            if (CmdIsDebug(childText))
                return childID
            ; 递归深入子节点的子节点
            deeper := this._FindStarInChildren(childID)
            if (deeper)
                return deeper
            try
                childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
        return 0
    }

    ; 解 G10：清除整树中除 keepItemID 外的所有调试起点标记（▶/⭐），保证起点全局唯一
    ClearOtherDebugStarts(keepItemID) {
        ; 守卫：keepItemID 为空/0 时不清（避免「清空全部 ▶ 且不回设」的边界）
        if (!keepItemID)
            return
        this._ClearDebugStartsInChildren(0, keepItemID)
    }

    ; 递归清除 parentID 子树内所有节点的调试起点标记（保留 keepItemID 自身）
    _ClearDebugStartsInChildren(parentID, keepItemID) {
        try
            childID := this.MacroTreeViewCon.GetChild(parentID)
        catch
            return
        while (childID) {
            try {
                text := this.MacroTreeViewCon.GetText(childID)
                if (childID != keepItemID && text != "" && CmdIsDebug(text))
                    this.MacroTreeViewCon.Modify(childID, , CmdStripDebug(text))
            } catch {
                ; 单节点异常不阻断整树遍历
            }
            this._ClearDebugStartsInChildren(childID, keepItemID)
            try
                childID := this.MacroTreeViewCon.GetNext(childID)
            catch
                break
        }
    }
