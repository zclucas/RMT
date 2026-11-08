
    InitCommandConfigs() {
        ; 指令名称：移动、移动Pro、增量移动（原游戏视角）
        this.CMDStrArr := GetLangArr(["间隔", "按键", "手柄", "搜索", "搜索Pro", "搜索All", "搜索Combo", "移动", "移动Pro", "增量移动", "输入", "输出", "循环", "宏操作", "变量", "变量提取",
            "如果", "如果Pro", "运算", "运行", "运行Pro", "文件读写", "Excel", "网络请求", "文本处理", "数组", "RMT指令", "后台鼠标", "后台按键", "窗口信息", "调整窗口", "按键检测", "手柄检测", "等待", "倒计时", "注释", "抓图", "跳转"])

        this.CMDIconFileArr := ["Images\Soft\Interval.png", "Images\Soft\Key.png", "Images\Soft\Joy.png",
            "Images\Soft\Search.png", "Images\Soft\SearchPro.png", "Images\Soft\SearchAll.png", "Images\Soft\SearchCombo.png",
            "Images\Soft\Move.png", "Images\Soft\MovePro.png", "Images\Soft\DeltaMove.png",
            "Images\Soft\Input.png", "Images\Soft\Output.png",
            "Images\Soft\Loop.png", "Images\Soft\MacroAction.png",
            "Images\Soft\Var.png", "Images\Soft\Extract.png",
            "Images\Soft\If.png", "Images\Soft\IfPro.png",
            "Images\Soft\Operation.png", "Images\Soft\Run.png", "Images\Soft\RunPro.png",
            "Images\Soft\FileIO.png", "Images\Soft\Excel.png", "Images\Soft\HttpRequest.png", "Images\Soft\TextOps.png",
            "Images\Soft\Arr.png", "Images\Soft\rabit.png",
            "Images\Soft\Mouse.png", "Images\Soft\BGKey.png",
            "Images\Soft\WindowManage.png", "Images\Soft\WindowAdjustGear32.png", "Images\Soft\KeyListen.png", "Images\Soft\JoyListen.png",
            "Images\Soft\Wait.png",
            "Images\Soft\Interval.png", "Images\Soft\Comment.png", "Images\Soft\ScreenShot.png", "Images\Soft\FlowJump.png"]

        this.IconMap := Map(GetLang("间隔"), "Icon1", GetLang("按键"), "Icon2", GetLang("手柄"), "Icon38", GetLang("搜索"), "Icon3",
        GetLang("搜索Pro"), "Icon4", GetLang("搜索All"), "IconSearchAll", GetLang("搜索Combo"), "Icon39", GetLang("移动"), "Icon5", GetLang("移动Pro"), "Icon6", GetLang("增量移动"), "Icon34", GetLang("输出"), "Icon7",
        GetLang("运行"), "Icon8", GetLang("运行Pro"), "Icon40", GetLang("循环"), "Icon9", GetLang("宏操作"), "Icon10", GetLang("变量"), "Icon11",
        GetLang("变量提取"), "Icon12", GetLang("如果"), "Icon13", GetLang("如果Pro"), "Icon14", GetLang("运算"), "Icon15",
        GetLang("RMT指令"), "Icon16", GetLang("后台鼠标"), "Icon17", GetLang("后台按键"), "Icon18", GetLang("真"), "Icon19",
        GetLang("假"), "Icon20", GetLang("循环次数"), "Icon21", GetLang("条件"), "Icon22", GetLang("循环体"), "Icon23",
        GetLang("文本处理"), "Icon24", GetLang("数组"), "Icon25", GetLang("输入"), "Icon26", GetLang("文件读写"), "Icon27", GetLang("Excel"), "Icon41", GetLang("网络请求"), "IconHttpRequest",
        GetLang("流程控制"), "Icon28", GetLang("窗口管理"), "Icon29", GetLang("窗口信息"), "Icon29", GetLang("调整窗口"), "IconWindowAdjust", GetLang("按键检测"), "Icon30", GetLang("手柄检测"), "Icon42", GetLang("跳转"), "Icon43", GetLang("流程跳转"), "Icon43", GetLang("注释"), "Icon31",
        GetLang("抓图"), "Icon32", GetLang("等待"), "Icon33", GetLang("等待确定"), "Icon36", GetLang("时间"), "Icon35", GetLang("倒计时"), "Icon37")

        ; IconN → 图标文件（顺序与原 IL_Add 一致）
        this.IconFileByNumber := Map(
            "Icon1", "Images\Soft\Interval.png", "Icon2", "Images\Soft\Key.png",
            "Icon3", "Images\Soft\Search.png", "Icon4", "Images\Soft\SearchPro.png",
            "Icon5", "Images\Soft\Move.png", "Icon6", "Images\Soft\MovePro.png",
            "Icon7", "Images\Soft\Output.png", "Icon8", "Images\Soft\Run.png",
            "Icon9", "Images\Soft\Loop.png", "Icon10", "Images\Soft\MacroAction.png",
            "Icon11", "Images\Soft\Var.png", "Icon12", "Images\Soft\Extract.png",
            "Icon13", "Images\Soft\If.png", "Icon14", "Images\Soft\IfPro.png",
            "Icon15", "Images\Soft\Operation.png", "Icon16", "Images\Soft\rabit.png",
            "Icon17", "Images\Soft\Mouse.png", "Icon18", "Images\Soft\BGKey.png",
            "Icon19", "Images\Soft\True.png", "Icon20", "Images\Soft\False.png",
            "Icon21", "Images\Soft\LoopCount.png", "Icon22", "Images\Soft\Condition.png",
            "Icon23", "Images\Soft\LoopBody.png", "Icon24", "Images\Soft\TextOps.png",
            "Icon25", "Images\Soft\Arr.png", "Icon26", "Images\Soft\Input.png",
            "Icon27", "Images\Soft\FileIO.png", "Icon28", "Images\Soft\Control.png",
            "IconWindowAdjust", "Images\Soft\WindowAdjustGear32.png", "Icon29", "Images\Soft\WindowManage.png", "Icon30", "Images\Soft\KeyListen.png",
            "Icon31", "Images\Soft\Comment.png", "Icon32", "Images\Soft\ScreenShot.png",
            "Icon33", "Images\Soft\Wait.png", "Icon34", "Images\Soft\DeltaMove.png", "Icon35", "Images\Soft\Time.png",
            "Icon36", "Images\Soft\WaitConfirm.png", "Icon37", "Images\Soft\Interval.png",
            "Icon38", "Images\Soft\Joy.png",
            "IconSearchAll", "Images\Soft\SearchAll.png",
            "Icon39", "Images\Soft\SearchCombo.png",
            "Icon40", "Images\Soft\RunPro.png",
            "IconHttpRequest", "Images\Soft\HttpRequest.png",
            "Icon41", "Images\Soft\Excel.png",
            "Icon42", "Images\Soft\JoyListen.png",
            "Icon43", "Images\Soft\FlowJump.png")

        ; 指令名 → 图标文件（XAML 树节点 Image.Source 用）
        this.CmdIconFileMap := Map()
        this.IconMap[GetLang("鼠标移动")] := "Icon5"
        this.IconMap[GetLang("鼠标移动Pro")] := "Icon6"
        for name, iconN in this.IconMap
            this.CmdIconFileMap[name] := this.IconFileByNumber.Get(iconN, "")
    }

    InitSubGuiConfigs() {
        this.SubGuiConfig := [
            {class: IntervalGui, name: "间隔", icon: "Images\Soft\Interval.png", propName: "IntervalGui"},
            {class: KeyGui, name: "按键", icon: "Images\Soft\Key.png", propName: "KeyGui"},
            {class: JoyGui, name: "手柄", icon: "Images\Soft\Joy.png", propName: "JoyGui"},
            {class: SearchGui, name: "搜索", icon: "Images\Soft\Search.png", propName: "SearchGui"},
            {class: SearchProGui, name: "搜索Pro", icon: "Images\Soft\SearchPro.png", propName: "SearchProGui"},
            {class: SearchAllGui, name: "搜索All", icon: "Images\Soft\SearchAll.png", propName: "SearchAllGui"},
            {class: SearchComboGui, name: "搜索Combo", icon: "Images\Soft\SearchCombo.png", propName: "SearchComboGui"},
            {class: MouseMoveGui, name: "移动", icon: "Images\Soft\Move.png", propName: "MouseMoveGui"},
            {class: MMProGui, name: "移动Pro", icon: "Images\Soft\MovePro.png", propName: "MMProGui"},
            {class: DeltaMoveGui, name: "增量移动", icon: "Images\Soft\DeltaMove.png", propName: "DeltaMoveGui"},
            {class: InputGui, name: "输入", icon: "Images\Soft\Input.png", propName: "InputGui"},
            {class: OutputGui, name: "输出", icon: "Images\Soft\Output.png", propName: "OutputGui"},
            {class: LoopGui, name: "循环", icon: "Images\Soft\Loop.png", propName: "LoopGui"},
            {class: SubMacroGui, name: "宏操作", icon: "Images\Soft\MacroAction.png", propName: "SubMacroGui"},
            {class: VariableGui, name: "变量", icon: "Images\Soft\Var.png", propName: "VariableGui"},
            {class: ExVariableGui, name: "变量提取", icon: "Images\Soft\Extract.png", propName: "ExVariableGui"},
            {class: CompareGui, name: "如果", icon: "Images\Soft\If.png", propName: "CompareGui"},
            {class: CompareProGui, name: "如果Pro", icon: "Images\Soft\IfPro.png", propName: "CompareProGui"},
            {class: OperationGui, name: "运算", icon: "Images\Soft\Operation.png", propName: "OperationGui"},
            {class: RunGui, name: "运行", icon: "Images\Soft\Run.png", propName: "RunGui"},
            {class: RunProGui, name: "运行Pro", icon: "Images\Soft\RunPro.png", propName: "RunProGui"},
            {class: HttpRequestGui, name: "网络请求", icon: "Images\Soft\HttpRequest.png", propName: "HttpRequestGui"},
            {class: FileIOGui, name: "文件读写", icon: "Images\Soft\FileIO.png", propName: "FileIOGui"},
            {class: FileIOGui, name: "Excel", icon: "Images\Soft\Excel.png", propName: "ExcelGui"},
            {class: TextOpsGui, name: "文本处理", icon: "Images\Soft\TextOps.png", propName: "TextOpsGui"},
            {class: ArrayGui, name: "数组", icon: "Images\Soft\Arr.png", propName: "ArrayGui"},
            {class: RMTCMDGui, name: "RMT指令", icon: "Images\Soft\rabit.png", propName: "RMTCMDGui"},
            {class: BGMouseGui, name: "后台鼠标", icon: "Images\Soft\Mouse.png", propName: "BGMouseGui"},
            {class: BGKeyGui, name: "后台按键", icon: "Images\Soft\BGKey.png", propName: "BGKeyGui"},
            {class: WindowManageGui, name: "窗口信息", icon: "Images\Soft\WindowManage.png", propName: "WindowInfoGui"},
            {class: WindowManageGui, name: "调整窗口", icon: "Images\Soft\WindowAdjustGear32.png", propName: "WindowAdjustGui"},
            {class: WindowManageGui, name: "窗口管理", icon: "Images\Soft\WindowManage.png", propName: "WindowManageGui"},
            {class: KeyCheckGui, name: "按键检测", icon: "Images\Soft\KeyListen.png", propName: "KeyCheckGui"},
            {class: JoyCheckGui, name: "手柄检测", icon: "Images\Soft\JoyListen.png", propName: "JoyCheckGui"},
            {class: WaitGui, name: "等待", icon: "Images\Soft\Wait.png", propName: "WaitGui"},
            {class: TimeGui, name: "时间", icon: "Images\Soft\Time.png", propName: "TimeGui"},
            {class: FlowJumpGui, name: "跳转", icon: "Images\Soft\FlowJump.png", propName: "FlowJumpGui"},
            {class: CommentGui, name: "注释", icon: "Images\Soft\Comment.png", propName: "CommentGui"},
            {class: ScreenShotGui, name: "抓图", icon: "Images\Soft\ScreenShot.png", propName: "ScreenShotGui"}
        ]
    }

    InitSubGui() {
        for config in this.SubGuiConfig {
            guiClass := config.class
            guiInstance := guiClass()
            if (config.name == "Excel" || config.name == "窗口信息" || config.name == "调整窗口")
                guiInstance.CmdKey := config.name
            guiInstance.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
            this.SubGuiMap.Set(GetLang(config.name), guiInstance)
            if (config.name == "移动" || config.name == "移动Pro")
                this.SubGuiMap.Set(GetLang("鼠标" config.name), guiInstance)
            this.%config.propName% := guiInstance
        }
        this.SubGuiMap[GetLang("等待确定")] := this.WaitGui
    }

    _BindCountDownToTimeGui() {
        if (!ObjHasOwnProp(this, "TimeGui") || !IsObject(this.TimeGui))
            return
        this.CountDownGui := CountDownGui()
        this.CountDownGui.SureBtnAction := (cmd) => this.OnSubGuiSureBtnClick(cmd)
        try this.SubGuiMap.Set(GetLang("倒计时"), this.CountDownGui)
    }
