#Requires AutoHotkey v2.0

; ============================================================================
; MacroGraphGui 职能拆分 —— 事件注册 / 输入交互
;
; 节点与分支事件注册、控件事件绑定、节点拖动与键盘快捷键（复制/粘贴/删除）处理。
; 方法体保持原样，this 仍为 MacroGraphGui 实例，
; 通过 _GraftMacroGraphMixin 嫁接到 MacroGraphGui.Prototype。
; ============================================================================

class MacroGraphEventsMixin {
    ; ----------------------------------------------------------------- 节点事件注册

    _RegisterNodeEvents() {
        for id, node in this.cmdNodes
            this._RegisterMyNodeEvents(id, node, false)
        ; 展开搜索/如果/如果Pro 节点的真/假/多分支节点事件
        for id in this.order {
            if (this._IsExpandedIfPro(id)) {
                count := this._IfProBranchCountFromId(id)
                loop count
                    this._RegisterProBranchEvents(id, A_Index - 1)
            } else if (this._HasVisibleBranches(id)) {
                this._RegisterBranchEvents(id, true)
                this._RegisterBranchEvents(id, false)
            }
        }
        ; 展开循环节点的外置循环体节点事件（双击进嵌套循环体编辑器）
        for id in this.order {
            if (this._IsExpandedLoop(id))
                this._RegisterLoopBodyEvents(id)
        }
    }

    ; 注册单个分支节点的事件：选中（用于双击判定）+ 展开/收起按钮。runtime=true 时为运行时注入控件补绑。
    _RegisterBranchEvents(searchId, isTrue, runtime := false) {
        brId := this._BranchId(searchId, isTrue)
        this.ui.OnEvent("Node_" brId, "SelectNode", this._OnBranchClick.Bind(this, searchId, isTrue))
        this.ui.OnEvent("Node_" brId, "CtrlSelectNode", this._OnBranchClick.Bind(this, searchId, isTrue))
        this._BindCtrl("SBExpand_" brId, "Click", this._OnBranchToggleExpand.Bind(this, searchId, isTrue), runtime)
        if (this._IsIfNodeId(searchId)) {
            this._TrackCtrl("BrFlowCmb_" brId, runtime)
            this._BindCtrl("BrFlowCmb_" brId, "SelectionChanged", this._OnBranchFlowControl.Bind(this, searchId, isTrue), runtime)
            this._BindCtrl("BrFlowCmb_" brId, "DropDownClosed", this._OnBranchFlowControl.Bind(this, searchId, isTrue), runtime)
        }
        ; 如果/搜索/搜索Pro：内联展开/折叠按钮
        this._BindCtrl("ILExpand_" brId, "Click", this._OnBranchInlineToggle.Bind(this, searchId, isTrue), runtime)
    }

    ; 注册外置循环体节点事件：选中（双击进嵌套循环体编辑器）+ 拖动刷新回环路径。
    _RegisterLoopBodyEvents(loopId, runtime := false) {
        bid := this._LoopBodyId(loopId)
        this.ui.OnEvent("Node_" bid, "SelectNode", this._OnLoopBodyClick.Bind(this, loopId))
        this.ui.OnEvent("Node_" bid, "CtrlSelectNode", this._OnLoopBodyClick.Bind(this, loopId))
        this.ui.OnEvent("Node_" bid, "DragMove", this._OnLoopBodyDrag.Bind(this, loopId))
        this._BindCtrl("LoopExtExpand_" bid, "Click", this._OnLoopChipsToggle.Bind(this, bid, "LoopExtChips_" bid, "LoopExtExpand_" bid, loopId), runtime)
        this._BindCtrl("ILExpand_" bid, "Click", this._OnLoopBodyInlineToggle.Bind(this, loopId), runtime)
    }

    ; 注册单个节点的"本类"事件（双击编辑 + 内联字段）。runtime=true 时同时向引擎补绑/补采集
    ; （运行时注入的控件不在启动期的事件/采集清单里，需用 BindEvent/Track 命令动态补上）。
    _RegisterMyNodeEvents(id, node, runtime := false) {
        ; 双击节点打开完整编辑器（节点是 Border，无原生双击，用 SelectNode 计时判定）
        ; SelectNode/CtrlSelectNode/DragMove 由引擎 EnableDrag 主动下发，仅需本地 OnEvent 接收
        this.ui.OnEvent("Node_" id, "SelectNode", this._OnNodeClick.Bind(this, id))
        this.ui.OnEvent("Node_" id, "CtrlSelectNode", this._OnNodeClick.Bind(this, id))
        this.ui.OnEvent("Node_" id, "DragMove", this._OnNodeDrag.Bind(this, id))

        d := this._Parse(node.CurCMD)
        if (d.type == GetLang("间隔")) {
            this._TrackCtrl("ITypeCmb_" id, runtime)
            this._TrackCtrl("Time_" id, runtime)
            this._TrackCtrl("Time2_" id, runtime)
            this._BindCtrl("ITypeCmb_" id, "SelectionChanged", this._OnIntervalType.Bind(this, id), runtime)
            this._BindCtrl("ITypeCmb_" id, "DropDownClosed", this._OnIntervalType.Bind(this, id), runtime)
            this._BindCtrl("Time_" id, "LostFocus", this._OnField.Bind(this, id, "time"), runtime)
            this._BindCtrl("Time_" id, "SelectionChanged", this._OnField.Bind(this, id, "time"), runtime)
            this._BindCtrl("Time2_" id, "LostFocus", this._OnField.Bind(this, id, "time2"), runtime)
            this._BindCtrl("Time2_" id, "SelectionChanged", this._OnField.Bind(this, id, "time2"), runtime)
        }
        else if (d.type == GetLang("按键")) {
            this._TrackCtrl("TypeCmb_" id, runtime)
            this._TrackCtrl("Hold_" id, runtime)
            this._TrackCtrl("Count_" id, runtime)
            this._TrackCtrl("Inter_" id, runtime)
            ; SelectionChanged 偶发读不到文本；DropDownClosed 在选中确定后再补一次，保证显隐正确
            this._BindCtrl("TypeCmb_" id, "SelectionChanged", this._OnKeyType.Bind(this, id), runtime)
            this._BindCtrl("TypeCmb_" id, "DropDownClosed", this._OnKeyType.Bind(this, id), runtime)
            this._BindCtrl("Hold_" id, "LostFocus", this._OnField.Bind(this, id, "hold"), runtime)
            this._BindCtrl("Hold_" id, "KeyDown", this._OnField.Bind(this, id, "hold"), runtime)
            this._BindCtrl("Count_" id, "LostFocus", this._OnField.Bind(this, id, "count"), runtime)
            this._BindCtrl("Count_" id, "KeyDown", this._OnField.Bind(this, id, "count"), runtime)
            this._BindCtrl("Inter_" id, "LostFocus", this._OnField.Bind(this, id, "inter"), runtime)
            this._BindCtrl("Inter_" id, "KeyDown", this._OnField.Bind(this, id, "inter"), runtime)
        }
        else if (IsMoveCmd(d.type)) {
            this._TrackCtrl("PosX_" id, runtime)
            this._TrackCtrl("PosY_" id, runtime)
            this._TrackCtrl("Speed_" id, runtime)
            this._TrackCtrl("ModeCmb_" id, runtime)
            this._BindCtrl("PosX_" id, "LostFocus", this._OnField.Bind(this, id, "posx"), runtime)
            this._BindCtrl("PosY_" id, "LostFocus", this._OnField.Bind(this, id, "posy"), runtime)
            this._BindCtrl("Speed_" id, "LostFocus", this._OnField.Bind(this, id, "speed"), runtime)
            this._BindCtrl("ModeCmb_" id, "SelectionChanged", this._OnMoveMode.Bind(this, id), runtime)
            this._BindCtrl("ModeCmb_" id, "DropDownClosed", this._OnMoveMode.Bind(this, id), runtime)
        }
        else if (IsDeltaMoveCmd(d.type)) {
            ; §20 增量移动：X/Y 偏移字段
            this._TrackCtrl("DPosX_" id, runtime)
            this._TrackCtrl("DPosY_" id, runtime)
            this._BindCtrl("DPosX_" id, "LostFocus", this._OnField.Bind(this, id, "posx"), runtime)
            this._BindCtrl("DPosX_" id, "KeyDown", this._OnField.Bind(this, id, "posx"), runtime)
            this._BindCtrl("DPosY_" id, "LostFocus", this._OnField.Bind(this, id, "posy"), runtime)
            this._BindCtrl("DPosY_" id, "KeyDown", this._OnField.Bind(this, id, "posy"), runtime)
        }
        else if (IsMoveProCmd(d.type)) {
            this._TrackCtrl("MPPosX_" id, runtime)
            this._TrackCtrl("MPPosY_" id, runtime)
            this._TrackCtrl("MPSpeed_" id, runtime)
            this._TrackCtrl("MPActionCmb_" id, runtime)
            this._TrackCtrl("MPModeCmb_" id, runtime)
            this._TrackCtrl("MPHuman_" id, runtime)
            this._TrackCtrl("MPCount_" id, runtime)
            this._TrackCtrl("MPInterval_" id, runtime)
            this._BindCtrl("MPPosX_" id, "LostFocus", this._OnMMProField.Bind(this, id, "PosVarX"), runtime)
            this._BindCtrl("MPPosX_" id, "SelectionChanged", this._OnMMProField.Bind(this, id, "PosVarX"), runtime)
            this._BindCtrl("MPPosY_" id, "LostFocus", this._OnMMProField.Bind(this, id, "PosVarY"), runtime)
            this._BindCtrl("MPPosY_" id, "SelectionChanged", this._OnMMProField.Bind(this, id, "PosVarY"), runtime)
            this._BindCtrl("MPSpeed_" id, "LostFocus", this._OnMMProField.Bind(this, id, "Speed"), runtime)
            this._BindCtrl("MPSpeed_" id, "KeyDown", this._OnMMProField.Bind(this, id, "Speed"), runtime)
            this._BindCtrl("MPActionCmb_" id, "SelectionChanged", this._OnMMProAction.Bind(this, id), runtime)
            this._BindCtrl("MPActionCmb_" id, "DropDownClosed", this._OnMMProAction.Bind(this, id), runtime)
            this._BindCtrl("MPModeCmb_" id, "SelectionChanged", this._OnMMProMode.Bind(this, id), runtime)
            this._BindCtrl("MPModeCmb_" id, "DropDownClosed", this._OnMMProMode.Bind(this, id), runtime)
            this._BindCtrl("MPHuman_" id, "Click", this._OnMMProHuman.Bind(this, id), runtime)
            this._BindCtrl("MPCount_" id, "LostFocus", this._OnMMProField.Bind(this, id, "Count"), runtime)
            this._BindCtrl("MPCount_" id, "KeyDown", this._OnMMProField.Bind(this, id, "Count"), runtime)
            this._BindCtrl("MPInterval_" id, "LostFocus", this._OnMMProField.Bind(this, id, "Interval"), runtime)
            this._BindCtrl("MPInterval_" id, "KeyDown", this._OnMMProField.Bind(this, id, "Interval"), runtime)
        }
        else if (d.type == GetLang("搜索") || d.type == GetLang("搜索Pro")) {
            isPro := (d.type == GetLang("搜索Pro"))
            this._TrackCtrl("STypeCmb_" id, runtime)
            this._TrackCtrl("SColor_" id, runtime)
            this._TrackCtrl("SText_" id, runtime)
            this._TrackCtrl("SStartX_" id, runtime)
            this._TrackCtrl("SStartY_" id, runtime)
            this._TrackCtrl("SEndX_" id, runtime)
            this._TrackCtrl("SEndY_" id, runtime)
            this._TrackCtrl("SActCmb_" id, runtime)
            ; SelectionChanged 偶发状态滞后；DropDownClosed 在选中项确定后补一次，确保类型/动作显隐刷新
            this._BindCtrl("STypeCmb_" id, "SelectionChanged", this._OnSearchType.Bind(this, id), runtime)
            this._BindCtrl("STypeCmb_" id, "DropDownClosed", this._OnSearchType.Bind(this, id), runtime)
            this._BindCtrl("SColor_" id, "LostFocus", this._OnSearchField.Bind(this, id, "SearchColor"), runtime)
            this._BindCtrl("SText_" id, "LostFocus", this._OnSearchField.Bind(this, id, "SearchText"), runtime)
            this._BindCtrl("SStartX_" id, "LostFocus", this._OnSearchField.Bind(this, id, "StartPosX"), runtime)
            this._BindCtrl("SStartY_" id, "LostFocus", this._OnSearchField.Bind(this, id, "StartPosY"), runtime)
            this._BindCtrl("SEndX_" id, "LostFocus", this._OnSearchField.Bind(this, id, "EndPosX"), runtime)
            this._BindCtrl("SEndY_" id, "LostFocus", this._OnSearchField.Bind(this, id, "EndPosY"), runtime)
            this._BindCtrl("SActCmb_" id, "SelectionChanged", this._OnSearchAction.Bind(this, id), runtime)
            this._BindCtrl("SActCmb_" id, "DropDownClosed", this._OnSearchAction.Bind(this, id), runtime)
            ; 操作按钮：截图 / 选择图片 / 定位取色器 / 框选范围
            this._BindCtrl("SShot_" id, "Click", this._OnSearchShot.Bind(this, id), runtime)
            this._BindCtrl("SPic_" id, "Click", this._OnSearchPic.Bind(this, id), runtime)
            this._BindCtrl("SPick_" id, "Click", this._OnSearchPick.Bind(this, id), runtime)
            this._BindCtrl("SArea_" id, "Click", this._OnSearchArea.Bind(this, id), runtime)
            ; 标题栏折叠/展开按钮（控制真/假分支节点显隐）
            this._BindCtrl("SFold_" id, "Click", this._OnToggleFold.Bind(this, id), runtime)
            ; 搜索Pro 专属控件：坐标可编辑下拉(补 SelectionChanged) + 更多参数 + 结果/目标点保存
            if (isPro) {
                this._BindCtrl("SStartX_" id, "SelectionChanged", this._OnSearchField.Bind(this, id, "StartPosX"), runtime)
                this._BindCtrl("SStartY_" id, "SelectionChanged", this._OnSearchField.Bind(this, id, "StartPosY"), runtime)
                this._BindCtrl("SEndX_" id, "SelectionChanged", this._OnSearchField.Bind(this, id, "EndPosX"), runtime)
                this._BindCtrl("SEndY_" id, "SelectionChanged", this._OnSearchField.Bind(this, id, "EndPosY"), runtime)
                ; 搜索图片路径可编辑：聚焦还原完整路径，失焦写回并左侧省略展示
                this._TrackCtrl("SImg_" id, runtime)
                this._BindCtrl("SImg_" id, "GotFocus", this._OnSearchImgGotFocus.Bind(this, id), runtime)
                this._BindCtrl("SImg_" id, "LostFocus", this._OnSearchImgLostFocus.Bind(this, id), runtime)
                for nm in ["SWin_", "SCount_", "SInterval_", "SClick_", "SSpeed_", "SResName_", "SResTrue_", "SResFalse_", "SCoordX_", "SCoordY_"]
                    this._TrackCtrl(nm id, runtime)
                this._TrackCtrl("SResTog_" id, runtime)
                this._TrackCtrl("SCoordTog_" id, runtime)
                this._BindCtrl("SWin_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "WinInfo"), runtime)
                this._BindCtrl("SWinEdit_" id, "Click", this._OnSearchWinEdit.Bind(this, id), runtime)
                this._BindCtrl("SCount_" id, "LostFocus", this._OnSearchCount.Bind(this, id), runtime)
                this._BindCtrl("SCount_" id, "KeyDown", this._OnSearchCount.Bind(this, id), runtime)
                this._BindCtrl("SCount_" id, "SelectionChanged", this._OnSearchCount.Bind(this, id), runtime)
                this._BindCtrl("SCount_" id, "DropDownClosed", this._OnSearchCount.Bind(this, id), runtime)
                this._BindCtrl("SInterval_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "SearchInterval"), runtime)
                this._BindCtrl("SClick_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "ClickCount"), runtime)
                this._BindCtrl("SSpeed_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "Speed"), runtime)
                ; CheckBox 用 Checked/Unchecked 更可靠；Click 兜底
                this._BindCtrl("SResTog_" id, "Checked", this._OnSearchResultToggle.Bind(this, id), runtime)
                this._BindCtrl("SResTog_" id, "Unchecked", this._OnSearchResultToggle.Bind(this, id), runtime)
                this._BindCtrl("SResTog_" id, "Click", this._OnSearchResultToggle.Bind(this, id), runtime)
                this._BindCtrl("SResName_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "ResultSaveName"), runtime)
                this._BindCtrl("SResName_" id, "SelectionChanged", this._OnSearchProField.Bind(this, id, "ResultSaveName"), runtime)
                this._BindCtrl("SResName_" id, "DropDownClosed", this._OnSearchProField.Bind(this, id, "ResultSaveName"), runtime)
                this._BindCtrl("SResTrue_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "TrueValue"), runtime)
                this._BindCtrl("SResFalse_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "FalseValue"), runtime)
                this._BindCtrl("SCoordTog_" id, "Checked", this._OnSearchCoordToggle.Bind(this, id), runtime)
                this._BindCtrl("SCoordTog_" id, "Unchecked", this._OnSearchCoordToggle.Bind(this, id), runtime)
                this._BindCtrl("SCoordTog_" id, "Click", this._OnSearchCoordToggle.Bind(this, id), runtime)
                this._BindCtrl("SCoordX_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "CoordXName"), runtime)
                this._BindCtrl("SCoordX_" id, "SelectionChanged", this._OnSearchProField.Bind(this, id, "CoordXName"), runtime)
                this._BindCtrl("SCoordY_" id, "LostFocus", this._OnSearchProField.Bind(this, id, "CoordYName"), runtime)
                this._BindCtrl("SCoordY_" id, "SelectionChanged", this._OnSearchProField.Bind(this, id, "CoordYName"), runtime)
            }
        }
        else if (d.type == GetLang("输入")) {
            this._TrackCtrl("InTypeCmb_" id, runtime)
            this._TrackCtrl("InPauseCmb_" id, runtime)
            this._TrackCtrl("InCancelCmb_" id, runtime)
            this._TrackCtrl("InSave_" id, runtime)
            this._BindCtrl("InTypeCmb_" id, "SelectionChanged", this._OnInputType.Bind(this, id), runtime)
            this._BindCtrl("InTypeCmb_" id, "DropDownClosed", this._OnInputType.Bind(this, id), runtime)
            this._BindCtrl("InPauseCmb_" id, "SelectionChanged", this._OnInputPauseType.Bind(this, id), runtime)
            this._BindCtrl("InPauseCmb_" id, "DropDownClosed", this._OnInputPauseType.Bind(this, id), runtime)
            this._BindCtrl("InCancelCmb_" id, "SelectionChanged", this._OnInputCancelType.Bind(this, id), runtime)
            this._BindCtrl("InCancelCmb_" id, "DropDownClosed", this._OnInputCancelType.Bind(this, id), runtime)
            this._BindCtrl("InSave_" id, "LostFocus", this._OnInputField.Bind(this, id, "SaveName"), runtime)
            this._BindCtrl("InSave_" id, "SelectionChanged", this._OnInputField.Bind(this, id, "SaveName"), runtime)
        }
        else if (d.type == GetLang("输出")) {
            this._TrackCtrl("OutTypeCmb_" id, runtime)
            this._TrackCtrl("OutText_" id, runtime)
            this._TrackCtrl("OutVar_" id, runtime)
            this._BindCtrl("OutTypeCmb_" id, "SelectionChanged", this._OnOutputType.Bind(this, id), runtime)
            this._BindCtrl("OutTypeCmb_" id, "DropDownClosed", this._OnOutputType.Bind(this, id), runtime)
            this._BindCtrl("OutText_" id, "LostFocus", this._OnOutputField.Bind(this, id, "Text"), runtime)
            this._BindCtrl("OutVar_" id, "LostFocus", this._OnOutputField.Bind(this, id, "VariableName"), runtime)
            this._BindCtrl("OutVar_" id, "SelectionChanged", this._OnOutputField.Bind(this, id, "VariableName"), runtime)
        }
        else if (this._IsFormalNodeType(d.type)) {
            this._RegisterFormalNodeEvents(id, d, runtime)
            ; 变量节点：标题栏展开/收起按钮
            if (d.type == GetLang("变量"))
                this._BindCtrl("SFold_" id, "Click", this._OnToggleVarFold.Bind(this, id), runtime)
            ; 运算节点：标题栏展开/收起按钮
            else if (d.type == GetLang("运算"))
                this._BindCtrl("SFold_" id, "Click", this._OnToggleOpFold.Bind(this, id), runtime)
            this._RefreshFormalNode(id, d)
        }
    }

    ; 采集控件值：本地登记（启动期清单用）；运行时再用 Track 命令通知引擎纳入状态采集
    _TrackCtrl(name, runtime) {
        this.ui.Track(name)
        if (runtime)
            this.ui.Update(name, "Track", "")
    }

    ; 绑定控件事件：本地登记回调；运行时再用 BindEvent 命令让引擎为该控件挂上真实 WPF 事件
    _BindCtrl(name, evt, cb, runtime) {
        this.ui.OnEvent(name, evt, cb)
        if (runtime)
            this.ui.Update(name, "BindEvent", evt)
    }

    ; 拖动节点时记录其逻辑坐标（DragCoords 为画布坐标，需减去画布偏移）
    _OnNodeDrag(id, state, *) {
        if (!state.Has("DragCoords") || !this.pos.Has(id) || this.graph == "")
            return
        parts := StrSplit(state["DragCoords"], ",")
        if (parts.Length >= 2) {
            this.pos[id].x := Number(parts[1]) - this.graph.offsetX
            this.pos[id].y := Number(parts[2]) - this.graph.offsetY
            ; 注：搜索节点拖动时不再联动真/假分支节点（分支可独立摆放），仅引擎自动刷新相关连线
            ; 循环节点拖动：实时刷新与外置循环体的两条回环路径（循环坐标用本次实时画布坐标）
            if (this._IsExpandedLoop(id))
                this._UpdateLoopCyclePaths(id, Number(parts[1]), Number(parts[2]))
            if (this._IsExpandedIfPro(id))
                this._ScheduleIfProPathUpdate(id, Number(parts[1]), Number(parts[2]))
            else if (this._IsExpandedSearch(id) || this._IsExpandedIf(id))
                this._SchedulePairBranchPathUpdate(id, Number(parts[1]), Number(parts[2]))
            else if (this._IsProBranchId(id)) {
                pi := this._ProBranchInfo(id)
                if (pi != "")
                    this._ScheduleIfProPathUpdate(pi.parentId)
            } else if (this._IsBranchId(id)) {
                bi := this._BranchInfo(id)
                if (bi != "" && bi.proIdx < 0)
                    this._SchedulePairBranchPathUpdate(bi.searchId)
            }
            ; 框选拖动：检查所有选中的节点，如果有展开的循环节点也在选中中，更新其路径
            ; （selectedNodes 在 this.graph 中，由 XAML_Adv_Components 管理）
            selNodes := this.graph ? this.graph.selectedNodes : ""
            if (selNodes && selNodes.Count > 1) {
                ; 框选拖动：遍历选中的节点，更新所有展开循环的路径
                for sid in selNodes {
                    if (this._IsExpandedLoop(sid)) {
                        ; 获取循环节点和循环体节点的最新坐标
                        ln := this.graph.GetNode(sid)
                        bid := this._LoopBodyId(sid)
                        bn := bid != "" ? this.graph.GetNode(bid) : ""
                        if (ln) {
                            loopX := ln.X, loopY := ln.Y
                            bodyX := bn ? bn.X : "", bodyY := bn ? bn.Y : ""
                            this._UpdateLoopCyclePaths(sid, loopX, loopY, bodyX, bodyY)
                        }
                    }
                }
            }
        }
    }

    ; 外置循环体节点拖动：实时刷新两条回环路径（循环体坐标用本次实时画布坐标）
    _OnLoopBodyDrag(loopId, state, *) {
        if (this.graph == "" || !state.Has("DragCoords"))
            return
        parts := StrSplit(state["DragCoords"], ",")
        if (parts.Length >= 2)
            this._UpdateLoopCyclePaths(loopId, "", "", Number(parts[1]), Number(parts[2]))
    }

    ; 窗口按键：Delete 删除选中项；Ctrl+C/V 复制粘贴节点
    ; 修饰键优先读事件里的 KeyModifiers（按键瞬间），避免 SetTimer 延迟后 GetKeyState 已松开
    _OnKeyDown(state, ctrl, info) {
        key := ""
        if (IsObject(info) && info.HasProp("Key"))
            key := info.Key
        else if (Type(info) == "String") {
            parts := StrSplit(info, ":")
            key := parts.Length >= 2 ? parts[2] : info
        }
        ; 忽略单独的修饰键
        if (key == "" || RegExMatch(key, "^(Left|Right)?(Ctrl|Shift|Alt|Win)$") || key == "System")
            return
        mods := (IsObject(state) && state.Has("KeyModifiers")) ? state["KeyModifiers"] : ""
        ctrlDown := (mods != "" && InStr(mods, "Ctrl")) || GetKeyState("Ctrl")
        shiftDown := (mods != "" && InStr(mods, "Shift")) || GetKeyState("Shift")
        if (key == "Delete" || key == "Back")
            this._DeleteSelected()
        else if (ctrlDown && !shiftDown && (key = "C" || key = "c"))
            this._CopySelected()
        else if (ctrlDown && !shiftDown && (key = "V" || key = "v")) {
            ; Ctrl+V：先向引擎要鼠标画布坐标（异步 PasteAt），不用右键锚点
            this._RequestPasteAtMouse(state)
        }
    }

    ; Ctrl+V 入口：优先用按键事件已带的坐标立刻粘贴；否则 Screen/GetPasteMouse 异步取点
    _RequestPasteAtMouse(state := "") {
        g := this.graph
        if (g == "" || this.ui == "" || !this.ui.wpfHwnd)
            return
        origin := this._PickPasteOriginFromState(state, true)
        if (IsObject(origin)) {
            this._pasteLockUntil := A_TickCount + 300
            this._pasteOriginOverride := origin
            this._PasteNodes(false)
            return
        }
        ; 空 state：屏幕光标换算 → 异步 PasteAt；防双发
        this._pasteAwaitTick := A_TickCount
        this._pasteLockUntil := 0
        CoordMode("Mouse", "Screen")
        MouseGetPos(&sx, &sy)
        try this.ui.Update(g.id, "ScreenToCanvas", sx "," sy)
        ; 引擎未响应时兜底（仍不用 lastRightClick）
        SetTimer(this._PasteNodesAtMouseFallback.Bind(this), -150)
    }

    _PasteNodesAtMouseFallback(*) {
        if (!this.HasOwnProp("_pasteAwaitTick") || !this._pasteAwaitTick)
            return
        ; PasteAt 已处理则清除
        if (A_TickCount - this._pasteAwaitTick > 500)
            this._pasteAwaitTick := 0
        if (!this._pasteAwaitTick)
            return
        this._pasteAwaitTick := 0
        this._PasteNodesAtMouse("")
    }

    ; 从 state 选粘贴逻辑坐标；requireLive=true 时不用选中+40/固定300
    _PickPasteOriginFromState(state, requireLive := false) {
        g := this.graph
        if (g == "")
            return ""
        cand := Map()
        if (IsObject(state)) {
            if (state.Has("PreviewKeyDown:V"))
                cand["1_PreviewKeyDown:V"] := state["PreviewKeyDown:V"]
            if (state.Has("PreviewKeyDown"))
                cand["2_PreviewKeyDown"] := state["PreviewKeyDown"]
            if (state.Has("PasteAt"))
                cand["3_PasteAt"] := state["PasteAt"]
            kLive := g.id ">CanvasMouseLive"
            if (state.Has(kLive))
                cand["4_state_" kLive] := state[kLive]
            if (state.Has("CanvasMouseLive"))
                cand["5_state_CanvasMouseLive"] := state["CanvasMouseLive"]
        }
        for name, raw in cand {
            p := this._ParseCanvasPoint(raw, g)
            if (IsObject(p))
                return p
        }
        if (requireLive)
            return ""
        if (g.selectedNodes.Count > 0) {
            for id in g.selectedNodes {
                if (this.pos.Has(id))
                    return { x: this.pos[id].x + 40, y: this.pos[id].y + 40 }
            }
        }
        return { x: 300, y: 300 }
    }

    ; 同步兜底粘贴（异步失败时）：Query / 选中旁，不用右键
    _PasteNodesAtMouse(state := "") {
        g := this.graph
        if (g == "")
            return
        origin := this._PickPasteOriginFromState(state, true)
        if (!IsObject(origin) && this.ui != "" && this.ui.wpfHwnd) {
            try {
                live := this.ui.Query(g.id ">CanvasMouseLive")
                origin := this._ParseCanvasPoint(live, g)
            } catch {
            }
        }
        if (!IsObject(origin))
            origin := this._PickPasteOriginFromState("", false)
        this._pasteOriginOverride := origin
        this._PasteNodes(false)
    }

    ; 引擎 PasteAt：画布坐标（ScreenToCanvas / 按键载荷）
    _OnPasteAt(state, *) {
        g := this.graph
        if (g == "")
            return
        if (this.HasOwnProp("_pasteLockUntil") && this._pasteLockUntil && A_TickCount < this._pasteLockUntil)
            return
        this._pasteAwaitTick := 0
        this._pasteLockUntil := A_TickCount + 300
        origin := this._PickPasteOriginFromState(state, true)
        if (!IsObject(origin)) {
            this._PasteNodesAtMouse(state)
            return
        }
        this._pasteOriginOverride := origin
        this._PasteNodes(false)
    }
}

_GraftMacroGraphMixin(MacroGraphEventsMixin)
