class TableItem {
    __New() {
        this.SerialArr := []    ;每个item的序列码
        this.ColorStateArr := []
        this.TKArr := []        ;触发键
        this.MacroArr := []     ;宏内容
        this.HoldTimeArr := []  ;按住时间
        this.ForbidArr := []    ;禁止
        this.LoopCountArr := [] ;循环次数
        this.RemarkArr := []    ;备注
        this.TriggerTypeArr := []   ;触发类型
        this.TimingSerialArr := []  ;定时配置序列码
        this.ModeArr := []      ;按键模式   1.send 2.拟真 3.罗技
        this.StartTipSoundArr := [] ;开始提示音 1.无   2.触发提示  3.循环首次提示
        this.EndTipSoundArr := [] ;结束提示音 1.无   2.结束提示  3.循环结束提示

        this.HoldKeyArr := []       ;记录当前按下的按键，以便结束时松开
        this.KilledArr := []        ;标记结束状态
        this.PauseArr := []         ;暂停
        this.ActionCount := []      ; 记录执行次数，用于循环次数判断
        this.ToggleStateArr := []   ; 触发键开关状态
        this.ToggleActionArr := []   ; 触发键开关Action
        this.VariableMapArr := []    ;  每条宏对应的变量映射:内置变量
        this.UnderPosY := 0         ; table的最大PosY
        this.Index := 0             ;   table的Index
        this.SliderValue := 0       ;   滑动值
        this.OffSetPosY := 0        ;   偏移值
        this.AllConArr := []        ;   table中所有的con
        this.AllGroup := []         ; table中所有的group
        this.IsWorkIndexArr := []        ;work正在执行中

        this.FoldInfo := ""          ; 折叠筐保存信息
        this.FoldOffsetArr := []    ;和初始状态的高度偏移值
        this.FoldBtnArr := []       ;折叠筐按钮
        this.ConIndexMap := Map()
    }
}

class ItemFoldInfo {
    __New() {
        this.RemarkArr := []        ;折叠框备注
        this.FrontInfoArr := []     ;折叠框前台信息
        this.IndexSpanArr := []     ;范围索引
        this.ForbidStateArr := []   ;禁用状态
        this.FoldStateArr := []    ;折叠状态

        ;菜单栏功能
        this.TKTypeArr := []    ;触发类型
        this.TKArr := []        ;触发按键，菜单栏功能
        this.HoldTimeArr := []  ;长按时间
    }
}

class MacroItemInfo {
    __New(index, itemConInfo) {
        this.index := index
        this.itemConInfo := ItemConInfo
    }
}

class ItemConInfo {
    __New(Con, tableItem, FoldIndex) {
        this.Con := Con
        this.tableItem := tableItem
        this.FoldOffsetArr := tableItem.FoldOffsetArr
        this.FoldInfo := tableItem.FoldInfo
        this.FoldIndex := FoldIndex
        this.IsTitle := false
        this.IsDel := false
        this.Con.GetPos(&PosX, &PosY)
        this.OriPosX := PosX
        this.OriPosY := PosY
        this.SelfOffsetY := 0
    }

    UpdatePos(offsetPosY) {
        try {
            if (this.IsDel) {
                this.Con.Move(this.OriPosX, -10000)
                return
            }

            isFold := this.FoldInfo.FoldStateArr[this.FoldIndex]
            if ((isFold && !this.IsTitle)) {
                this.Con.Move(this.OriPosX, -10000)
                return
            }
            PosY := 0
            for index, value in this.FoldOffsetArr {
                if (index >= this.FoldIndex)
                    break
                PosY += value
            }

            PosY := PosY + this.OriPosY + this.SelfOffsetY - offsetPosY
            this.Con.Move(this.OriPosX, PosY)
        }
    }

    DelAfterOffset(offsetY) {
        this.SelfOffsetY -= offsetY
    }

    Hide() {
        this.IsDel := true
    }
}

class Timer {
    __New(callback, period) {
        this.binding := callback
        this.period := period
        this.priority := 0
    }

    __Delete() {
        this.Off()
    }

    On() {
        funcObj := this.binding
        SetTimer funcObj, this.period, this.priority
    }

    Off() {
        funcObj := this.binding
        SetTimer funcObj, 0
    }
}

class ToolCheck {
    __New() {
        this.AlwaysOnTopCtrl := ""
        this.ToolCheckCtrl := ""
        this.ToolCheckHotKeyCtrl := ""
        this.ToolMousePosCtrl := ""
        this.ToolMouseWinPosCtrl := ""
        this.ToolProcessNameCtrl := ""
        this.ToolProcessTileCtrl := ""
        this.ToolProcessPidCtrl := ""
        this.ToolProcessClassCtrl := ""
        this.ToolProcessIdCtrl := ""
        this.ToolColorCtrl := ""
        this.ToolTextFilterHotKeyCtrl := ""
        this.ToolTextCtrl := ""
        this.ToolRecordMacroHotKeyCtrl := ""
        this.ToolCheckRecordMacroCtrl := ""
        this.ScreenShotHotKeyCtrl := ""
        this.FreePasteHotKeyCtrl := ""

        this.ScreenShotHotKey := ""
        this.FreePasteHotKey := ""
        this.ToolRecordMacroHotKey := ""
        this.IsToolRecord := false
        this.ToolTextFilterHotKey := ""
        this.IsToolCheck := false
        this.ToolCheckHotKey := ""
        this.PosStr := ""
        this.WinPosStr := ""
        this.ProcessName := ""
        this.ProcessTile := ""
        this.ProcessPid := ""
        this.ProcessClass := ""
        this.ProcessId := ""
        this.Color := ""
        this.MouseInfoTimer := ""

        this.MacroGui := ""

        this.RecordLastMousePos := []
        this.RecordLastTime := ""
        this.RecordMacroStr := ""
        this.RecordHoldKeyMap := Map()
        this.RecordSpecialKeyMap := Map(33, 0, 34, 0, 35, 0, 36, 0, 37, 0, 38, 0, 39, 0, 40, 0, 45, 0, 46, 0)
        this.RecordHoldMuti := ""
        this.RecordAutoLoosen := ""
        this.RecordKeyboard := ""
        this.RecordMouse := ""
        this.RecordMouseKeyPoint := ""  ;关键点位
        this.RecordMouseRelative := ""
        this.RecordMouseTrail := ""
        this.RecordMouseTrailLen := ""
        this.RecordMouseTrailSpeed := ""
        this.RecordMouseTrailInterval := ""
        this.RecordJoy := ""
        this.RecordJoyInterval := ""
        this.OCRTypeCtrl := ""
        this.OCRTypeValue := 1
    }
}

class SoftData {
    __New() {
        this.isWorker := false          ;子线程标识
        this.MacroRunningCount := 0     ;运行中的宏数量
        this.IsMacroWorking := false    ;宏正在运行
        this.IsLogitechInit := false    ;罗技按键初始化
        this.ToolTipText := ""          ;临时提示文本
        this.ToolTipEndTime := ""       ;临时提示结束时间
        this.AgreeAgreement := false    ;同意协议
        this.IsBootStart := false       ;开机自启
        this.ShowSplitLine := false     ;显示分割线
        this.HiddenTopButtonIndexes := []
        this.ColorPresetId := "rmt-green"
        this.UiScale := 1               ;WebView界面缩放
        this.FixedMenuWheel := false    ;固定菜单轮
        this.NoVariableTip := false     ;无变量提醒
        this.ScreenShotType := 3        ;截图类型
        this.MutiThreadNum := 3         ;多线程数
        this.IsSuspend := false         ;休眠
        this.SuspendHotkey := ""        ;休眠快捷键
        this.IsPause := false           ;暂停
        this.PauseHotkey := ""          ;暂停快捷键
        this.KillMacroHotkey := ""      ;终止所有宏快捷键
        this.HoldFloat := 0             ;按住时间浮动数值
        this.PreIntervalFloat := 0      ;每次间隔浮动数值
        this.IntervalFloat := 0         ;间隔指令浮动数值
        this.CoordXFloat := 0           ;坐标X浮动数值
        this.CoordYFloat := 0           ;坐标Y浮动数值
        this.SoftBGColor := ""          ;软件背景颜色
        this.IsReload := false          ;软件是否重载
        this.TableIndex := 1            ;当前显示的table索引
        this.HasSaved := false          ;是否保存
        this.MacroEditGui := ""         ;当前宏编辑器
        this.FontType := "微软雅黑"     ;当前字体
        this.FontList := []             ;所有字体类型
        this.Lang := "中文"             ;当前语言
        this.LangArr := []              ;所有语言
        this.KeyDownDownType := 1       ;按下时按下 1自动松开, 2忽略后续按下, 3允许该操作

        this.MyGui := {}                ;软件主界面GUI
        this.CurSettingName := ""       ;当前配置名称
        this.SettingArrStr := ""        ;所有配置字串
        this.CurMenuWheelIndex := -1    ;当先显示的菜单轮盘

        this.TabCtrl := {}              ;Tab组件
        this.TabPosX := 0               ;Tab位置X
        this.TabPosY := 0               ;Tab位置Y
        this.TableInfo := []            ;TableItem所有信息，每个宏的所有信息

        this.IsMinStart := false        ;最小化启动

        ;Tab所有页签
        this.TabNameArr := ["按键宏", "字串宏", "菜单宏", "定时宏", "宏", "按键替换", "工具", "设置", "帮助", "打赏作者", "特别感谢"]
        ;Tab页签对应的英文
        this.TabSymbolArr := ["Normal", "String", "Menu", "Timing", "SubMacro", "Replace", "Tool", "Setting", "Help",
            "Reward", "Thank"]

        ;特殊的按键，因为含有下划线，所有要特殊处理
        this.SpecialKeyMap := Map("Browser_Back", 0, "Browser_Forward", 0, "Browser_Refresh", 0, "Browser_Stop", 0,
            "Browser_Search", 0, "Browser_Favorites", 0, "Browser_Home", 0, "Volume_Mute", 0, "Volume_Down", 0,
            "Volume_Up", 0, "Media_Next", 0, "Media_Prev", 0, "Media_Stop", 0, "Media_Play_Pause", 0, "Launch_Mail", 0,
            "Launch_Media", 0, "Launch_App1", 0, "Launch_App2", 0, "Bright_Down", 0, "Bright_Up", 0)
        this.OnlyDownKeyMap := Map("WheelDown", 0, "WheelUp", 0, "Bright_Down", 0, "Bright_Up", 0, "None", 0)
        this.SpecialTableItem := TableItem()    ;特别的TableItem，用于编辑器模式测试指令

        ;这些按键不会重复触发按下的按键宏，特别标记特殊处理
        this.ContinueKeyMap := Map("LButton", "LButton", "~LButton", "LButton", "RButton", "RButton", "~RButton",
            "RButton", "MButton", "MButton", "~MButton", "MButton", "XButton1", "XButton1", "~XButton1", "XButton1",
            "XButton2", "XButton2", "~XButton2", "XButton2")
        this.ContinueIntervale := 50    ;连续触发间隔

        this.FileEncodingArr := ["ANSI", "GB2312", "GB18030", "BIG5", "UTF-8", "UTF-16"]

        this.DataCacheMap := Map()      ;指令缓存，减少读取文件的次数

        this.GlobalArrMap := Map()      ;UI下拉显示数组
        this.ArrayMap := Map()          ;真正的全局数组
        this.GlobalVariMap := Map()     ;UI下拉显示变量
        this.VariableMap := Map()       ;真正的全局变量
        this.DataFileMap := Map()       ;配置命令对应的文件路径
        this.DataClassMap := Map()      ;配置对应的数据类型

        ;显示指令提示配置
        this.CMDTip := false
        this.CMDTipCtrl := ""
        this.CMDPosX := A_ScreenWidth - 225 - 55    ;不知道为什么有55的偏移
        this.CMDPosY := 0
        this.CMDWidth := 225
        this.CMDHeight := 120
        this.CMDBGColor := "FFFFFF"
        this.CMDRunBGColor := "00FF00"
        this.CMDTransparency := 50
        this.CMDFontSize := "12"
        this.CMDFontColor := "000000"

        ;变量监视器窗口大小
        this.VarListenTop := false
        this.VarListenWidth := 400
        this.VarListenHeight := 420

        this.TriggerKeyMap := Map()     ;所有的按键宏，包括软件自身的快捷键
        this.SoftHotKeyArr := ["~WheelUp", "~WheelDown", "~LButton", "~Left", "~Right", "~Up", "~Down", "~Enter", "1",
            "2", "3", "4", "5", "6", "7", "8", "~F5", "~F6", "~Delete", "~NumpadDot"]
        ; this.SoftHotKeyArr := ["1", "2", "3", "4", "5", "6", "7", "8"]      ;测试时候启动

        this.SelectAreaAction := "" ;左键框选范围回调   显示框选范围       正常
        this.GetAreaAction := ""    ;左键框选范围回调   不显示框选范围      系统截图获取截图范围
        this.StartAreaPosX := ""    ;开始框选范围X坐标  记录点位，这样结束时就能直接获取点位信息
        this.StartAreaPosY := ""    ;开始框选范围Y坐标

        this.IsTogStartRecord := false  ;通过开关触发录制   区分触发形式，删除宏里面的快捷键触发的按键
        this.IsTogEndRecord := false    ;通过开关结束录制
        this.HasJoyMacro := false       ;含有手柄宏，手柄宏启动时需要初始化手柄（操作系统会提示，有点嘈）
        this.MacroTotalCount := 0   ;宏运行次数
        this.LastShowMonth := 0     ;上次显示月数

        ;手柄映射
        this.JoyXboxToAhkMap := Map(
            "JoyA", "Joy1",
            "JoyB", "Joy2",
            "JoyX", "Joy3",
            "JoyY", "Joy4",
            "JoyLB", "Joy5",
            "JoyRB", "Joy6",
            "JoyLT", "JoyZMin",
            "JoyRT", "JoyZMax",
            "JoyLS", "Joy9",
            "JoyRS", "Joy10",
            "JoyBack", "Joy7",
            "JoyStart", "Joy8",
            "JoyDpadUp", "JoyPOV_0",
            "JoyDpadRight", "JoyPOV_9000",
            "JoyDpadDown", "JoyPOV_18000",
            "JoyDpadLeft", "JoyPOV_27000",
            "JoyAxisLXMin", "JoyXMin",
            "JoyAxisLXMax", "JoyXMax",
            "JoyAxisLYMin", "JoyYMin",
            "JoyAxisLYMax", "JoyYMax",
            "JoyAxisRXMin", "JoyUMin",
            "JoyAxisRXMax", "JoyUMax",
            "JoyAxisRYMin", "JoyRMin",
            "JoyAxisRYMax", "JoyRMax"
        )
        this.JoyAhkToXboxMap := Map(
            "Joy1", "JoyA",
            "Joy2", "JoyB",
            "Joy3", "JoyX",
            "Joy4", "JoyY",
            "Joy5", "JoyLB",
            "Joy6", "JoyRB",
            "JoyZMin", "JoyLT",
            "JoyZMax", "JoyRT",
            "Joy9", "JoyLS",
            "Joy10", "JoyRS",
            "Joy7", "JoyBack",
            "Joy8", "JoyStart",
            "JoyPOV_0", "JoyDpadUp",
            "JoyPOV_9000", "JoyDpadRight",
            "JoyPOV_18000", "JoyDpadDown",
            "JoyPOV_27000", "JoyDpadLeft",
            "JoyXMin", "JoyAxisLXMin",
            "JoyXMax", "JoyAxisLXMax",
            "JoyYMin", "JoyAxisLYMin",
            "JoyYMax", "JoyAxisLYMax",
            "JoyUMin", "JoyAxisRXMin",
            "JoyUMax", "JoyAxisRXMax",
            "JoyRMin", "JoyAxisRYMin",
            "JoyRMax", "JoyAxisRYMax"
        )
    }
}

class KeyboardData {
    __New() {
        this.NodeSerial := 0
        this.KeyName := ""
        this.StartTime := 0
        this.EndTime := 0
        this.StartPos := []
        this.EndPos := []
    }

    Span() {
        return this.EndTime - this.StartTime
    }
}

class RecordNodeData {
    __New() {
        this.StartTime := 0
        this.EndTime := 0
    }

    Span() {
        return this.EndTime - this.StartTime
    }
}

class MoveData {
    __New() {
        this.EndPosX := 0
        this.EndPosY := 0
        this.NodeSerial := 0
    }
}

class SearchData {
    __New() {
        this.SerialStr := ""
        this.ConfigName := Format("{}*{}_{}", A_ScreenWidth, A_ScreenHeight, GetLang("全屏"))
        this.SearchType := 1        ;1屏幕图片  2屏幕颜色  3屏幕文本 4窗口图片 5窗口颜色 6窗口文本
        this.WinInfo := ""          ;窗口信息
        this.SearchColor := "FFFFFF"
        this.SearchText := GetLang("检索文本")
        this.SearchImagePath := ""
        this.Similar := 90 ; 图片搜索模糊匹配度100  - 50
        this.OCRType := 1   ;1中文  2英文
        this.SearchImageType := 1 ; 1 opencv 2 rmt
        this.StartPosX := 0
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
        this.SearchCount := 1
        this.SearchInterval := 1000
        this.MouseActionType := 2   ;   1无动作 2移动到目标 3移动到目标点击
        this.Speed := 90
        this.ClickCount := 1
        this.ConfigArr := []    ;配置数组，不同的分辨率
        this.TrueMacro := ""
        this.FalseMacro := ""
        this.ResultToggle := 0
        this.ResultSaveName := GetLang("搜索结果")
        this.TrueValue := 1
        this.FalseValue := 0
        this.CoordToogle := 0
        this.CoordXName := GetLang("坐标X")
        this.CoordYName := GetLang("坐标Y")
    }

}

class CompareData {
    __New() {
        this.ToggleArr := [1, 0, 0, 0]
        this.NameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CompareTypeArr := [1, 1, 1, 1]  ;1大于 2大于等于 3等于 4小于等 5小于 6字符包含 7存在变量 8正则匹配
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.TrueControlType := "无"   ;流程控制：1无 2循环-跳过本轮 3循环-跳出 4分支-跳出
        this.FalseControlType := "无"   ;流程控制：1无 2循环-跳过本轮 3循环-跳出 4分支-跳出
        this.TrueMacro := ""
        this.FalseMacro := ""
        this.SaveToggle := 0
        this.SaveName := GetLang("结果")
        this.TrueValue := 1
        this.FalseValue := 0
        this.LogicalType := 1
    }
}

class CompareProData {
    __New() {
        this.VariNameArr := [["Var1"], ["Var2"]]
        this.CompareTypeArr := [[3], [3]]  ;1大于 2大于等于 3等于 4小于等 5小于 6字符包含 7存在变量
        this.VariableArr := [[1], [2]]
        this.LogicTypeArr := [1, 2]
        this.ControlTypeArr := ["无", "无"]
        this.MacroArr := ["按键_a_点击_100", "按键_b_点击_100"]
        this.DefaultControlType := "无"
        this.DefaultMacro := "按键_c_点击_100"
    }

    ;用于逻辑树展示
    static GetCondiStr(Data, itemIndex) {
        CommandStr := ""
        symbolStr := Data.LogicTypeArr[itemIndex] == 1 ? GetLang("且") : GetLang("或")
        CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])

        loop Data.VariNameArr[itemIndex].Length {
            VariName := GetLang(Data.VariNameArr[itemIndex][A_Index])
            TypeStr := CompareTypeStrArr[Data.CompareTypeArr[itemIndex][A_Index]]
            Variable := GetLang(Data.VariableArr[itemIndex][A_Index])

            if (Data.CompareTypeArr[itemIndex][A_Index] != 7)
                CommandStr .= VariName " " TypeStr " " Variable " " symbolStr " "
            else
                CommandStr .= VariName " " TypeStr " " symbolStr " "
        }
        CommandStr := Trim(CommandStr, " ")
        CommandStr := Trim(CommandStr, symbolStr)
        CommandStr := Trim(CommandStr, " ")
        return CommandStr
    }
}

class MMProData {
    __New() {
        this.SerialStr := ""
        this.ConfigName := Format("{}*{}_{}", A_ScreenWidth, A_ScreenHeight, GetLang("全屏"))
        this.ConfigArr := []
        this.PosVarX := 100
        this.PosVarY := 100
        this.ActionType := 1          ;鼠标动作 1移动 2移动点击1次 3移动点击2次
        this.IsRelative := 0         ;相对位移
        this.IsGameView := 0        ;游戏视角
        this.Speed := 90           ;移动速度
        this.Count := 1
        this.Interval := 1000
    }
}

class RunData {
    __New() {
        this.SerialStr := ""
        this.RunPath := ""
        this.BackPlay := false
    }
}

class OutputData {
    __New() {
        this.SerialStr := ""
        this.Text := GetLang("将要输出的文本")
        this.OutputType := "发送内容"   ;sendtest  粘贴   粘贴
    }
}

class FileIOData {
    __New() {
        this.SerialStr := ""
        this.OperType := "读取Excel"    ;1读取Excel 2写入Excel 3读取文本文件 4写入文本文件
        this.Encoding := "UTF-8"        ;文本文件编码格式
        this.FilePath := ""

        ;读取Excel      "单元格", "指定行", "指定列", "指定区域-行", "指定区域-列"
        ;写入Excel      单元格    行号自增  列号自增  指定区域-行    指定区域-列
        ;读取文本文件   读取全部内容, 逐行读取, 指定行
        ;写入文本文件   "覆盖写入", "追加写入", "追加写入-行", "指定行", "行号自增"
        this.OperMode := "单元格"
        this.NameOrSerial := 1
        this.RowVar := 1
        this.ColVar := 1
        this.RowEndVar := 1
        this.ColEndVar := 1

        this.TextRowVar := 1        ;文本文件指令行号

        this.Content := "写入的内容" ;单元格时的写入内容
        this.ArrName := "Arr"       ;写入区域时的数组

        this.SaveType := "变量"     ;保存类型  变量或数组
        this.SaveName := "Data"
    }
}

class SubMacroData {
    __New() {
        this.SerialStr := ""
        this.MacroType := "按键宏"
        this.CallType := "触发"
        this.InsertCount := 1
        this.Index := 1
        this.MacroSerial := "-1"
    }
}

class LoopData {
    __New() {
        this.SerialStr := ""
        this.LoopCount := 10    ;循环次数
        this.CondiType := 1     ;条件类型 1：无 2：退出条件 3：继续条件
        this.LogicType := 1     ;逻辑关系  1：且    2：或
        this.ToggleArr := [1, 0, 0, 0]
        this.NameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CompareTypeArr := [1, 1, 1, 1]  ;1大于 2大于等于 3等于 4小于等 5小于 6字符包含 7存在变量
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.LoopBody := ""     ;循环体
    }

    ;用于逻辑树展示
    static GetCondiStr(Data) {
        CommandStr := ""
        symbolStr := Data.LogicType == 1 ? GetLang("且") : GetLang("或")
        CompareTypeStrArr := GetLangArr(["大于", "大于等于", "等于", "小于等于",
            "小于", "字符包含", "变量存在", "正则匹配"])

        loop 4 {
            if (!Data.ToggleArr[A_Index])
                continue

            VariName := GetLang(Data.NameArr[A_Index])
            TypeStr := CompareTypeStrArr[Data.CompareTypeArr[A_Index]]
            Variable := GetLang(Data.VariableArr[A_Index])
            if (Data.CompareTypeArr[A_Index] != 7)
                CommandStr .= VariName " " TypeStr " " Variable " " symbolStr " "
            else
                CommandStr .= VariName " " TypeStr " " symbolStr " "
        }

        CommandStr := Trim(CommandStr, " ")
        CommandStr := Trim(CommandStr, symbolStr)
        CommandStr := Trim(CommandStr, " ")
        return CommandStr
    }
}

class VariableData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.ToggleArr := [1, 0, 0, 0]
        this.OperaTypeArr := [1, 1, 1, 1]   ;1赋值 2随机 3字符 4删除
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4"]
        this.CopyVariableArr := ["1", "0", "0", "0"]
        this.MinVariableArr := ["0", "0", "0", "0"]
        this.MaxVariableArr := ["10", "10", "10", "10"]
    }
}

class ExVariableData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.ToggleArr := [1, 0, 0, 0, 0, 0]
        this.VariableArr := ["Var1", "Var2", "Var3", "Var4", "Var5", "Var6"]
        this.ExtractStr := ""
        this.ExtractType := 1
        this.WinInfo := ""
        this.OCRType := 1
        this.StartPosX := 0
        this.StartPosY := 0
        this.EndPosX := A_ScreenWidth
        this.EndPosY := A_ScreenHeight
        this.SearchCount := 1
        this.SearchInterval := 1000
    }
}

class OperationData {
    __New() {
        this.SerialStr := ""
        this.ToggleArr := [1, 0, 0, 0]
        this.UpdateNameArr := ["Var1", "Var2", "Var3", "Var4"]
        this.ExpressionArr := ["", "", "", ""]    ;完整表达式字符串（用于支持括号和整体编辑）
    }
}

class BGMouseData {
    __New() {
        this.SerialStr := ""
        this.TargetTitle := ""
        this.OperateType := 1 ;点击 双击 按下 松开
        this.MouseType := 1 ;左键 中键 右键
        this.PosVarX := 100
        this.PosVarY := 100
        this.ScrollV := 1 ;水平滚动
        this.ScrollH := 0 ; 垂直滚动
        this.ClickTime := 50 ;点击时间跨度
    }
}

class BGKeyData {
    __New() {
        this.SerialStr := ""
        this.FrontStr := ""
        this.KeyArr := []
        this.Type := 1  ;1按下 2松开 3点击
        this.ClickTime := 100
        this.ClickCount := 1
        this.ClickInterval := 100
    }
}

class TimingData {
    __New() {
        this.SerialStr := ""
        this.StartTime := A_Now
        this.EndTime := ""
        this.Type := 1  ;1单次 2每小时 3每天 4每周 5每月 6自定义
        this.CustomInterval := "10"
        this.CustomUnit := 2            ; 1: 秒 2: 分钟 3: 小時 4: 天 5: 週
        this.NextTriggerTime := ""
    }
}

class ArrayData {
    __New() {
        this.SerialStr := ""
        this.IsIgnoreExist := 0
        this.Type := "创建"
        this.Name := "Arr"
        this.InitArr := [1, 2, 3, 4, 5, 6, 7, 8, 9]
        this.MainIndex := 0
        this.ArgsIndex := 1
        this.ArgsType := "变量或值"
        this.ArgsName := "Var1"
        this.SaveType := "变量"
        this.SaveName := "Data"
    }
}

class RMTCMDData {
    __New() {
        this.SerialStr := ""
        this.OperateType := 1 ; 1截图 2截图中提取文本 3自由贴 4开启指令显示 5关闭指令显示 6启用键鼠 7禁用键鼠 8休眠 9终止所有宏 10重载
    }
}

class TextOpsData {
    __New() {
        this.SerialStr := ""
        this.Type := "文本分割" ; 1: 文本分割 2: 文本替换
        this.Name := "TextVar" ; 文本来源变量名
        this.ArgsType := "全部大写" ;参数类型
        this.ArgsName := ","        ;参数变量名或文本
        this.Search := "" ; 查找文本
        this.Replace := "" ; 替换文本
        this.SaveType := "变量"     ;保存类型  变量或数组
        this.SaveName := "Data"     ;保存的变量名或数组名
    }
}

class MouseWinData {
    __New() {
        this.WinId := ""
        this.WinTitle := ""
        this.WinClass := ""
        this.WinProcess := ""
        this.HasError := false
    }

    UpdateInfo() {
        this.HasError := false
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            this.WinId := winId
            this.WinTitle := WinGetTitle(winId)
            this.WinClass := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                this.WinProcess := ProcessGetName(WinPID)
            }
            catch {
                this.WinProcess := ""
            }
        }
        catch as e {
            this.HasError := true
        }
    }

    CheckIfMatch(FrontInfoStr, isUpdate := false) {
        if (isUpdate)
            this.UpdateInfo()

        if (FrontInfoStr == "" || this.HasError)
            return false

        if (InStr(FrontInfoStr, "❖")) {
            FrontInfoStr := StrReplace(FrontInfoStr, "❖")
            hwndList := StrSplit(FrontInfoStr, "|")
            for index, hwnd in hwndList {
                if (this.WinId == hwnd)
                    return true
            }
            return false
        }

        infoArr := StrSplit(FrontInfoStr, "⎖")
        if (infoArr.Length != 3)
            return false

        title := infoArr[1]
        className := infoArr[2]
        process := infoArr[3]

        if (title != "" && !InStr(this.WinTitle, title, "Off"))
            return false

        if (className != "" && className != this.WinClass)
            return false

        if (process != "" && process != this.WinProcess)
            return false

        return true
    }
}

class SerialData {
    __New(Str) {
        this.Str := Str
        this.NumMap := Map()
        this.CurNum := 1
    }

    Refresh() {
        if (this.NumMap.Has(this.CurNum)) {
            this.NumMap.Delete(this.CurNum)
            this.CurNum++
            this.Refresh()
        }
    }
}

class InputData {
    __New() {
        this.SerialStr := ""
        this.Type := "弹窗"                 ;弹窗 状态 继续 继续&取消
        this.PauseType := "暂停当前宏"      ;交互时：不暂停 暂停当前宏  暂停所有宏
        this.CancelType := "终止当前宏"     ;取消时  终止当前宏  终止所有宏
        this.SaveName := "Data"             ;保存的变量名或数组名
    }
}
