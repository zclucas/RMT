#Requires AutoHotkey v2.0

; 仅用于用户要求保留配置的任务；单次操作不经过此入口。
class AiInstructionBuilder {
    static runs := Map()
    static sequence := 0

    static Run(args) {
        if (!AiAssist.CanRun())
            throw Error("执行已有配置需要完全访问。")
        table := AiAssist._ResolveTable(args["tab"])
        index := Integer(args["index"])
        if (index < 1 || index > table.Items.Length)
            throw Error("宏序号不存在。")
        item := table.Items[index]
        if (args["config_name"] != MySoftData.CurSettingName || args["item_id"] != item.ID
            || args["expected_macro"] != item.Macro || args["expected_pre_macro"] != item.PreMacro || args["expected_post_macro"] != item.PostMacro)
            throw Error("配置或宏已改变，请重新read_macro核对。")
        if (MainSoftData.IsSuspend || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(table,index))
            throw Error("软件休眠或该宏已禁用，请先由用户确认运行状态。")
        if (!WorkPoolEnabled())
            throw Error("配置执行需要工作进程就绪；单次任务请使用execute_instruction。")
        if (item.HasOwnProp("Stopping") || item.ColorState || MyWorkPool.HasItemWork(table.ID,item.ID))
            throw Error("该宏正在执行、暂停或停止，请先检查运行状态。")
        validation := JSON.parse(AiMacroValidation.Run(args))
        if (validation["error_count"] || !validation["complete"])
            return JSON.stringify(Map("ok",JSON.false,"error","静态检查未通过，先修复配置。","validation",validation),0)
        if (!AiAssist._NeedApproval("执行现有宏：" item.Remark "`n" item.Macro))
            throw Error("用户拒绝审批。")
        ; 审批窗口可重入，启动前再次核对目标和正文。
        if (!AiAssist.CanRun() || args["config_name"] != MySoftData.CurSettingName
            || GetItemIndexInTable(table,item.ID) != index || args["expected_macro"] != item.Macro
            || args["expected_pre_macro"] != item.PreMacro || args["expected_post_macro"] != item.PostMacro
            || MainSoftData.IsSuspend || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(table,index)
            || item.ColorState || MyWorkPool.HasItemWork(table.ID,item.ID))
            throw Error("运行条件已变化，请重新读取宏。")
        ; 配置写入有防抖，工具可能在同一轮立即运行；先落盘并按FIFO通知Worker刷新。
        CfgFlushDir(AiAssist._WorkspaceRoot() "\Setting\" MySoftData.CurSettingName)
        MyWorkPool.BroadcastConfigRefresh()
        this.sequence += 1
        id := "ai-run-" this.sequence
        this.runs[id] := {config:MySoftData.CurSettingName,table:table.ID,item:item.ID,started:A_TickCount,errors:[]}
        try TriggerMacroHandler(table,index,"AI配置执行")
        catch as e {
            this.runs.Delete(id)
            throw e
        }
        if (this.runs.Count > 30) {
            for oldest in this.runs {
                this.runs.Delete(oldest)
                break
            }
        }
        return JSON.stringify(Map("ok",JSON.true,"run_id",id,"status","submitted","validation",validation,
            "guidance","已提交现有宏，请macro_run_status检查运行状态，再用截图、读取文件或变量监视核实目标；提交不代表完成。"),0)
    }

    static RecordError(tableID,itemID,message,level,context := "") {
        latest := ""
        for id,run in this.runs {
            if (run.config == MySoftData.CurSettingName && run.table == tableID && run.item == itemID)
                latest := run
        }
        if (IsObject(latest) && latest.errors.Length < 20)
            latest.errors.Push(Map("message",SubStr(message,1,4000),"level",level,"context",context))
    }

    static Status(args) {
        if (!AiAssist.CanRun())
            throw Error("查询配置执行需要完全访问。")
        id := args["run_id"]
        if (!this.runs.Has(id))
            throw Error("运行记录不存在或已过期。")
        run := this.runs[id]
        wait := AiDirectControl.Int(args,"wait_ms",0,0,30000)
        deadline := A_TickCount + wait
        loop {
            if (!AiAssist.CanRun() || run.config != MySoftData.CurSettingName)
                throw Error("权限或配置已改变，无法继续核对原运行状态。")
            table := GetTableByID(run.table)
            index := table ? GetItemIndexInTable(table,run.item) : 0
            if (!index)
                throw Error("原宏已删除。")
            item := table.Items[index]
            active := item.ColorState || (WorkPoolEnabled() && MyWorkPool.HasItemWork(table.ID,item.ID))
            if (!active || A_TickCount >= deadline)
                break
            cancelled := false
            try cancelled := MyMainWin._AiCancelRequested(MyMainWin._aiChatTab)
            if (cancelled)
                throw Error("状态等待已取消；已有宏是否仍运行请核对。")
            Sleep(Min(100,Max(1,deadline-A_TickCount)))
        }
        return JSON.stringify(Map("ok",JSON.true,"run_id",id,"status",active ? "active" : "idle",
            "elapsed_ms",A_TickCount-run.started,"color_state",item.ColorState,"killed",item.Killed ? JSON.true : JSON.false,
            "errors",run.errors,"error_count",run.errors.Length,"verified",JSON.false,"wait_timed_out",active && wait ? JSON.true : JSON.false,
            "guidance","先检查errors和实际输出；报错或效果不符时read_macro_step→preview_macro_step_edit→apply_macro_step_edit调整参数，再校验运行。idle不代表成功。"),0)
    }
    static Schema(args) {
        name := args.Get("kind", "")
        if (name == "") {
            names := []
            for kind in MySoftData.DataClassMap {
                if (kind != "图形节点" && kind != "图形开始节点")
                    names.Push(kind)
            }
            return JSON.stringify(Map("ok",JSON.true,"config_name",MySoftData.CurSettingName,"kinds",names,
                "guidance","用户要生成配置时，先查询mcp_tools；不可用或生成不理想再使用本工具。按kind查询完整默认字段，create_instruction保存后用返回的command组装宏，不编造序列码。"),0)
        }
        name := this.Kind(name)
        data := MySoftData.DataClassMap[name]()
        defaults := Map()
        for field,value in data.OwnProps() {
            if (field != "SerialStr")
                defaults[field] := value
        }
        return JSON.stringify(Map("ok",JSON.true,"kind",name,"config_name",MySoftData.CurSettingName,"defaults",defaults,"choices",this.Choices(name),"field_help",this.FieldHelp(name),
            "guidance","data只覆盖需要的原生字段。分支中的指令引用须已存在或由create_instruction返回。创建后validate_macro检查配置，不自动执行。"
                (AiMacroEdit.IsSearch(name) ? "配置搜图引擎和自适应跟随软件全局设置，旧SearchImageType/Adaptive字段不能覆盖全局；切换文本搜索可改SearchType/OcrEngine。单次找图可直接选择backend。" : "")),0)
    }

    static FieldHelp(name) {
        help := AiDirectNative.FieldHelp(name)
        help["window_binding"] := "WinInfo或SearchValue窗口绑定：已知HWND用十进制字符串；按标题/类名/进程匹配用 标题⎖类名⎖进程名（三段，未知段留空）。不要把普通标题或ahk_id字符串当绑定。"
        switch name {
            case "移动Pro":
                help["coordinates"] := "绝对移动+屏幕基准：屏幕像素。窗口基准：相对窗口外框左上角（包含标题栏，不是客户区）。A到B拖拽用PosVarX/Y为起点、EndPosVarX/Y为终点；移动后单击会完成点击。"
            case "Excel","文件读写":
                help["excel"] := "OperType=写入Excel/读取Excel；单元格模式用FilePath、NameOrSerial（工作表名或1起序号）、RowVar、ColVar，写入Content，读取SaveName。指定区域用RowEndVar/ColEndVar、ArrName或SaveName，数组模式读回数组。"
            case "抓图":
                help["output"] := "抓图指令自动保存到当前配置Images目录；ResultSaveName是输出文件路径变量，并非自定义文件名。读取该变量验证真实文件，勿猜路径。窗口抓图需WinInfo，坐标按客户区；屏幕抓图为屏幕像素。"
            case "AI判断":
                help["judgment"] := "Options每行标签|返回值，至少两行；ResultVar接收结果。Source=屏幕内容是图像判断，屏幕文字是OCR文本判断；Region为x1,y1,x2,y2。模型不支持图像时改文字来源并注明依据。失败不会默认为否。"
            case "窗口操作","窗口信息":
                help["query"] := "ActionType按choices。SearchValue是window_binding格式。操作可先激活/移动窗口；信息字段按WindowInfoFields顺序写ResultVar1..。移动窗口用PosX/PosY。"
            case "搜索","搜索Pro","搜索All","搜索Combo":
                help["search"] := "屏幕坐标使用StartPosX/Y、EndPosX/Y；窗口搜索按客户区坐标并提供WinInfo。SearchCount限次数，SearchInterval为毫秒。ResultToggle=1把TrueValue/FalseValue写ResultSaveName；CoordToogle=1输出CoordXName/CoordYName。默认不点击。"
                help["targets"] := "SearchTargetArr为空时使用顶层搜索字段；多目标时为每个目标填写相同单目标字段。找图使用SearchImagePath，找文字使用SearchText（正则）。未命中应调整范围/Similar/次数/间隔，或切换SearchType/OcrEngine后再运行。"
        }
        return help
    }

    static Kind(name) {
        name := GetCommandKey(String(name))
        ; 直接操作目录使用「手柄」，持久化仍复用现有按键指令。
        if (name == "手柄")
            name := "按键"
        if (!MySoftData.DataClassMap.Has(name) || !MySoftData.DataFileMap.Has(name) || name == "图形节点" || name == "图形开始节点")
            throw Error("不支持该配置类型，请查询instruction_schema：" name)
        return name
    }

    static Patch(data, changes, depth := 0) {
        if (Type(changes) != "Map" || depth > 8)
            throw Error("data必须是参数对象，嵌套最多8层。")
        for key,value in changes {
            if (key == "SerialStr" || !data.HasOwnProp(key))
                throw Error("未知配置字段：" key)
            original := data.%key%
            if (Type(value) == "Map") {
                if (!IsObject(original) || Type(original) == "Array")
                    throw Error("参数类型不匹配：" key)
                this.Patch(original,value,depth+1)
            } else {
                if (IsObject(value) && !IsObject(original))
                    throw Error("参数类型不匹配：" key)
                if (IsObject(original) && Type(original) != Type(value))
                    throw Error("参数类型不匹配：" key)
                if (Type(value) == "Array" && value.Length > 1000)
                    throw Error("数组最多1000项：" key)
                data.%key% := value
            }
        }
    }

    static Choices(name) {
        choices := AiDirectNative.Choices(name)
        if (name == "移动Pro") {
            choices["ActionType"] := ["移动","移动后单击","移动后双击","A到B拖拽","拖拽"]
            choices["MouseMoveMode"] := ["绝对移动","相对移动"]
            choices["RefMode"] := ["屏幕","窗口"]
        }
        if (name == "窗口操作" || name == "窗口信息") {
            choices["ActionType"] := []
            for group in WindowCommandActions(name) {
                for action in WindowGroupActions(GetLangKey(group))
                    choices["ActionType"].Push(action)
            }
        }
        if (name == "AI判断")
            choices["Source"] := AiDecision.Sources
        if (name == "抓图")
            choices["ScreenShotType"] := ["屏幕抓图","窗口抓图"]
        if (name == "文件读写" || name == "Excel") {
            choices["OperType"] := ["读取文件","写入文件","读取Excel","写入Excel"]
            choices["OperMode"] := ["读取全部内容","逐行读取","指定行","覆盖写入","追加写入","追加写入-行","行号自增","单元格","指定列","列号自增","指定区域-行","指定区域-列"]
        }
        if (AiMacroEdit.IsSearch(name)) {
            choices["SearchType"] := ["屏幕图片","屏幕颜色","屏幕文本","窗口图片","窗口颜色","窗口文本"]
            choices["OcrEngine"] := ["","RapidOCR","Tesseract OCR"]
            choices["ColorMatch"] := [0,1]
        }
        return choices
    }

    static Validate(name,data) {
        AiDirectNative.ValidateContext(name,data)
        values := JSON.parse(JSON.stringify(data,0))
        for field,choices in this.Choices(name) {
            if (!values.Has(field))
                continue
            found := false
            for choice in choices {
                if (values[field] == choice) {
                    found := true
                    break
                }
            }
            if (!found)
                throw Error(field "取值无效，请按instruction_schema的choices调整。")
        }
        AiMacroEdit.CheckParams(name,values)
        ValidateCommandVariableNames(name,data)
    }

    static Create(args) {
        if (!AiAssist.CanWrite())
            throw Error("生成指令配置需要写入权限。")
        config := MySoftData.CurSettingName
        if (args.Get("config_name","") != config)
            throw Error("配置已切换，请重新查询instruction_schema确认目标。")
        name := this.Kind(args["kind"])
        data := MySoftData.DataClassMap[name]()
        this.Patch(data,args["data"])
        AiDirectNative.ContextDefaults(name,data,args["data"])
        ; 把参数数组内的 JSON 对象还原为原生指令对象。
        data := JSON.parse(JSON.stringify(data,0), ,false)
        NormalizeCommandData(name,data)
        this.Validate(name,data)
        file := MySoftData.DataFileMap[name]
        if (!AiAssist._NeedApproval("生成「" name "」指令配置（不执行）`n" JSON.stringify(data,0)))
            throw Error("用户拒绝审批。")
        if (!AiAssist.CanWrite() || config != MySoftData.CurSettingName || file != MySoftData.DataFileMap[name])
            throw Error("配置已切换，请重新生成。")
        ; 未挂到宏上的记录也应保留，不能只凭内存编号覆盖已有配置。
        if (!SerialMap.Has(name))
            SerialMap[name] := SerialData(name)
        while (CfgRead(file,SettingSection,name SerialMap[name].CurNum,"") != "")
            SerialMap[name].CurNum += 1
        serial := AllocateCommandSerial(name)
        data.SerialStr := serial
        try {
            SaveMacroCMDData(data)
            Cfg_FlushFile(file)
        }
        catch as e {
            try CfgDelete(file,SettingSection,serial)
            throw e
        }
        return JSON.stringify(Map("ok",JSON.true,"backend","native","config_name",config,"command",serial,"data",data,
            "executed",JSON.false,"guidance","指令参数已保存。用返回的command加入用户指定宏，随后validate_macro；只有用户要求运行配置时才run_macro。单次任务仍用execute_instruction。"),0)
    }
}
