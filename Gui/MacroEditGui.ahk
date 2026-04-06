#Requires AutoHotkey v2.0
#Include IntervalGui.ahk
#Include KeyGui.ahk
#Include MouseMoveGui.ahk
#Include SearchGui.ahk
#Include SearchProGui.ahk
#Include RunGui.ahk
#Include CompareGui.ahk
#Include MMProGui.ahk
#Include OutputGui.ahk
#Include VariableGui.ahk
#Include SubMacroGui.ahk
#Include OperationGui.ahk
#Include BGMouseGui.ahk
#Include ExVariableGui.ahk
#Include RMTCMDGui.ahk
#Include BGKeyGui.ahk
#Include LoopGui.ahk
#Include CompareProGui.ahk
#Include CompareProEditItemGui.ahk
#Include TextOpsGui.ahk
#Include ArrayGui.ahk
#Include InputGui.ahk

class MacroEditGui {
    static Hotkeys := ["f5", "f6", "delete", "numpaddot"]

    __new() {
        WindowHotkeyManager.Register(this, MacroEditGui.Hotkeys, this.OnSoftKey.Bind(this))
        this.ParentTile := ""
        this.Gui := ""
        this.GuiMenu := ""
        this.DebugItemID := 0
        this.DebugStepNum := 0
        this.ShowSaveBtn := false
        this.SureFocusCon := ""
        this.isContextEdit := false
        this.RecordToggleCon := ""
        this.EditModeCon := ""
        this.SubMacroEditGui := ""
        this.CompareProEditItemGui := ""

        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SaveBtnCtrl := {}
        this.SubGuiMap := map()
        this.MacroTreeViewCon := ""
        this.MacroEditTextCon := ""
        this.CmdEditType := 1  ;1添加指令 2修改当前指令 3向上插入指令 4 向下插入指令
        this.CurItemID := ""  ;当前操作itemID
        this.LastItemID := "" ;最后的itemID
        this.ContextMenu := ""
        this.BranchContextMenu := ""
        this.RecordMacroCon := ""
        this.DefaultFocusCon := ""
        this.SubMacroLastIndex := 0

        this.CMDStrArr := GetLangArr(["间隔", "按键", "搜索", "搜索Pro", "移动", "移动Pro", "输入", "输出", "循环", "宏操作", "变量", "变量提取",
            "如果", "如果Pro", "运算", "运行", "数组", "文本处理", "后台鼠标", "后台按键", "RMT指令"])

        this.IconMap := Map(GetLang("间隔"), "Icon1", GetLang("按键"), "Icon2", GetLang("搜索"), "Icon3", GetLang("搜索Pro"),
        "Icon4", GetLang("移动"), "Icon5", GetLang("移动Pro"),
        "Icon6", GetLang("输出"), "Icon7", GetLang("运行"), "Icon8", GetLang("循环"), "Icon9", GetLang("宏操作"), "Icon10",
        GetLang("变量"), "Icon11", GetLang("变量提取"), "Icon12", GetLang("如果"), "Icon13", GetLang("如果Pro"),
        "Icon14", GetLang("运算"), "Icon15", GetLang("RMT指令"), "Icon16", GetLang("后台鼠标"), "Icon17", GetLang("后台按键"),
        "Icon2", GetLang("真"), "Icon18", GetLang("假"), "Icon19", GetLang("循环次数"), "Icon20", GetLang("条件"), "Icon21",
        GetLang("循环体"), "Icon22", GetLang("文本处理"), "Icon23", GetLang("数组"), "Icon24", GetLang("输入"), "Icon25")

        this.InitSubGui()
    }

    InitSubGui() {
        this.IntervalGui := IntervalGui()
        this.IntervalGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("间隔"), this.IntervalGui)

        this.KeyGui := KeyGui()
        this.KeyGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("按键"), this.KeyGui)

        this.MoveMoveGui := MouseMoveGui()
        this.MoveMoveGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("移动"), this.MoveMoveGui)

        this.SearchGui := SearchGui()
        this.SearchGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("搜索"), this.SearchGui)

        this.SearchProGui := SearchProGui()
        this.SearchProGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("搜索Pro"), this.SearchProGui)

        this.RunGui := RunGui()
        this.RunGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("运行"), this.RunGui)

        this.CompareGui := CompareGui()
        this.CompareGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("如果"), this.CompareGui)

        this.CompareProGui := CompareProGui()
        this.CompareProGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("如果Pro"), this.CompareProGui)

        this.MMProGui := MMProGui()
        this.MMProGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("移动Pro"), this.MMProGui)

        this.OutputGui := OutputGui()
        this.OutputGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("输出"), this.OutputGui)

        this.VariableGui := VariableGui()
        this.VariableGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("变量"), this.VariableGui)

        this.ExVariableGui := ExVariableGui()
        this.ExVariableGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("变量提取"), this.ExVariableGui)

        this.TextOpsGui := TextOpsGui()
        this.TextOpsGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("文本处理"), this.TextOpsGui)

        this.ArrayGui := ArrayGui()
        this.ArrayGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("数组"), this.ArrayGui)

        this.SubMacroGui := SubMacroGui()
        this.SubMacroGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("宏操作"), this.SubMacroGui)

        this.LoopGui := LoopGui()
        this.LoopGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("循环"), this.LoopGui)

        this.OperationGui := OperationGui()
        this.OperationGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("运算"), this.OperationGui)

        this.BGMouseGui := BGMouseGui()
        this.BGMouseGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("后台鼠标"), this.BGMouseGui)

        this.BGKeyGui := BGKeyGui()
        this.BGKeyGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("后台按键"), this.BGKeyGui)

        this.RMTCMDGui := RMTCMDGui()
        this.RMTCMDGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("RMT指令"), this.RMTCMDGui)

        this.InputGui := InputGui()
        this.InputGui.SureBtnAction := (CommandStr) => this.OnSubGuiSureBtnClick(CommandStr)
        this.SubGuiMap.Set(GetLang("输入"), this.InputGui)
    }

    ShowGui(CommandStr, ShowSaveBtn) {
        global MySoftData
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
            ImageListID := IL_Create(25)
            this.MacroTreeViewCon.SetImageList(ImageListID)
            IL_Add(ImageListID, "Images\Soft\Interval.png")
            IL_Add(ImageListID, "Images\Soft\Key.png")
            IL_Add(ImageListID, "Images\Soft\Search.png")
            IL_Add(ImageListID, "Images\Soft\SearchPro.png")
            IL_Add(ImageListID, "Images\Soft\Move.png")
            IL_Add(ImageListID, "Images\Soft\MovePro.png")
            IL_Add(ImageListID, "Images\Soft\Output.png")
            IL_Add(ImageListID, "Images\Soft\Run.png")
            IL_Add(ImageListID, "Images\Soft\Loop.png")
            IL_Add(ImageListID, "Images\Soft\Sub.png")
            IL_Add(ImageListID, "Images\Soft\Var.png")
            IL_Add(ImageListID, "Images\Soft\Extract.png")
            IL_Add(ImageListID, "Images\Soft\If.png")
            IL_Add(ImageListID, "Images\Soft\IfPro.png")
            IL_Add(ImageListID, "Images\Soft\Operation.png")
            IL_Add(ImageListID, "Images\Soft\rabit.png")
            IL_Add(ImageListID, "Images\Soft\Mouse.png")
            IL_Add(ImageListID, "Images\Soft\True.png")
            IL_Add(ImageListID, "Images\Soft\False.png")
            IL_Add(ImageListID, "Images\Soft\LoopCount.png")
            IL_Add(ImageListID, "Images\Soft\Condition.png")
            IL_Add(ImageListID, "Images\Soft\LoopBody.png")
            IL_Add(ImageListID, "Images\Soft\TextOps.png")      ;todo 还没正式化
            IL_Add(ImageListID, "Images\Soft\Arr.png")            ;todo 还没正式化
            IL_Add(ImageListID, "Images\Soft\Input.png")            ;todo 还没正式化
        }

        MySoftData.RecordToggleCon := this.RecordMacroCon
        MySoftData.MacroEditGui := this
        this.DebugStepNum := 0
        this.InitGuiMenu()
        this.Init(CommandStr, ShowSaveBtn)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("宏指令编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosY := 10
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 170, 530), GetLang("指令选项"))

        PosY += 20
        PosX := 15
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("间隔"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.IntervalGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("按键"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.KeyGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("搜索"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.SearchGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("搜索Pro"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.SearchProGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("移动"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.MoveMoveGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("移动Pro"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.MMProGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("输入"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.InputGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("输出"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.OutputGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("循环"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.LoopGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("宏操作"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.SubMacroGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("变量"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.VariableGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("变量提取"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.ExVariableGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("如果"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.CompareGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("如果Pro"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.CompareProGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("运算"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.OperationGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("运行"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.RunGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("数组"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.ArrayGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("文本处理"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.TextOpsGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("后台鼠标"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.BGMouseGui))

        PosX += 85
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("后台按键"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.BGKeyGui))

        PosX := 15
        PosY += 40
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 30, 75), GetLang("RMT指令"))
        btnCon.SetFont((Format("S{} W{} Q{}", 11, 400, 5)))
        btnCon.OnEvent("Click", (*) => this.OnOpenSubGui(this.RMTCMDGui))

        PosX := 200
        PosY := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("编辑模式："))
        PosX += 70
        this.EditModeCon := MyGui.Add("DropDownList", Format("x{} y{} w80", PosX, PosY - 3), GetLangArr(["逻辑树", "文本"]))
        this.EditModeCon.Value := 1
        this.EditModeCon.OnEvent("Change", this.OnChangeEditMode.Bind(this))

        PosX := 400
        this.RecordMacroCon := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("指令录制"))
        this.RecordMacroCon.Value := false
        this.RecordMacroCon.OnEvent("Click", this.OnClickRecordTog.Bind(this))
        PosX += 85
        isHotKey := CheckIsNormalHotKey(ToolCheckInfo.ToolRecordMacroHotKey)
        CtrlType := isHotKey ? "Hotkey" : "Text"
        con := MyGui.Add(CtrlType, Format("x{} y{} w{}", posX, posY - 3, 130), ToolCheckInfo.ToolRecordMacroHotKey
        )
        con.Enabled := false

        PosX := 190
        PosY += 25
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 720, 460), GetLang("当前宏指令"))
        PosY += 20
        this.MacroTreeViewCon := MyGui.Add("TreeView", Format("x{} y{} w{} h{}", PosX + 5, PosY, 705, 435),
        "")
        this.MacroTreeViewCon.OnEvent("ContextMenu", this.ShowContextMenu.Bind(this))  ; 右键菜单事件
        this.MacroTreeViewCon.OnEvent("DoubleClick", this.OnDoubleClick.Bind(this))  ; 双击编辑指令

        this.MacroEditTextCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX + 5, PosY, 705, 435), "")
        this.MacroEditTextCon.Visible := false

        PosX := 190
        PosY := 500
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("退格"))
        btnCon.OnEvent("Click", (*) => this.Backspace())

        PosX += 150
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("清空指令"))
        btnCon.OnEvent("Click", (*) => this.ClearStr())

        PosX += 150
        btnCon := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnSureBtnClick())

        PosX += 150
        this.SaveBtnCtrl := MyGui.Add("Button", Format("x{} y{} h{} w{} center", PosX, PosY, 40, 100), GetLang("应用并保存"))
        this.SaveBtnCtrl.OnEvent("Click", (*) => this.OnSaveBtnClick())

        MyGui.Show(Format("w{} h{}", 920, 570))
    }

    InitGuiMenu() {
        if (this.GuiMenu != "")
            return

        ; 创建菜单栏
        MyMenuBar := MenuBar()

        ; === 文件菜单 ===
        ExeMenu := Menu()
        ExeMenu.Add(GetLang("运行(F5)"), this.MenuHandler.Bind(this))
        ExeMenu.Add(GetLang("单步运行(F6)"), this.MenuHandler.Bind(this))
        ExeMenu.Add(GetLang("终止"), this.MenuHandler.Bind(this))

        ; === 编辑菜单 ===
        this.ToolMenu := Menu()
        this.ToolMenu.Add(GetLang("变量监视"), this.MenuHandler.Bind(this))
        this.ToolMenu.Add(GetLang("指令显示"), this.MenuHandler.Bind(this))
        this.ToolMenu.Add(GetLang("窗口置顶"), this.MenuHandler.Bind(this))

        ; === 添加到菜单栏 ===
        MyMenuBar.Add(GetLang("调试"), ExeMenu)
        MyMenuBar.Add(GetLang("工具"), this.ToolMenu)

        if (MyVarListenGui.Gui != "") {
            style := WinGetStyle(MyVarListenGui.Gui)
            isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
            if (isVisible)
                this.ToolMenu.Check(GetLang("变量监视"))
        }

        if (MyCMDTipGui.Gui != "") {
            style := WinGetStyle(MyCMDTipGui.Gui)
            isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
            if (isVisible)
                this.ToolMenu.Check(GetLang("指令显示"))
        }

        exStyle := DllCall("GetWindowLongPtr", "Ptr", this.Gui.Hwnd, "Int", -20, "UInt") ; GWL_EXSTYLE = -20
        isTop := (exStyle & 0x00000008)
        if (isTop) {
            this.ToolMenu.Check(GetLang("窗口置顶"))
        }

        this.Gui.MenuBar := MyMenuBar
    }

    Init(MacroStr, ShowSaveBtn) {
        MacroStr := GetLangMacro(MacroStr, 1)
        this.ShowSaveBtn := ShowSaveBtn
        this.SubMacroLastIndex := 0
        this.SaveBtnCtrl.Visible := this.ShowSaveBtn
        this.InitTreeView(MacroStr)
        this.InitMacroText(MacroStr)

        firstItem := this.MacroTreeViewCon.GetNext(0)
        this.MacroTreeViewCon.Focus()
        this.MacroTreeViewCon.Modify(firstItem, "Check")
    }

    Backspace() {
        if (this.EditModeCon.Value == 1) {
            if (this.MacroTreeViewCon.GetCount() == 0)
                return
            preItemID := this.MacroTreeViewCon.GetPrev(this.LastItemID)
            this.MacroTreeViewCon.Delete(this.LastItemID)
            this.LastItemID := preItemID
        }
        else {
            MacroStr := this.GetMacroStr()
            cmdArr := SplitMacro(MacroStr)
            if (cmdArr.Length > 0)
                cmdArr.Pop()
            MacroStr := GetMacroStrByCmdArr(cmdArr)

            ; 回到替换前的滑动值
            firstVisible := SendMessage(0xCE, 0, 0, this.MacroEditTextCon) ; EM_GETFIRSTVISIBLELINE = 0xCE
            this.InitMacroText(MacroStr)
            SendMessage(0xB6, 0, firstVisible, this.MacroEditTextCon) ; EM_LINESCROLL = 0xB6
        }
    }

    ClearStr() {
        this.MacroTreeViewCon.Delete()
        this.MacroEditTextCon.Value := ""
    }

    OnChangeEditMode(*) {
        MacroStr := this.GetMacroStr()
        this.MacroTreeViewCon.Visible := this.EditModeCon.Value == 1
        this.MacroEditTextCon.Visible := this.EditModeCon.Value == 2

        if (this.EditModeCon.Value == 1) {
            this.InitTreeView(MacroStr)
        }
        else if (this.EditModeCon.Value == 2) {
            this.InitMacroText(MacroStr)
        }
    }

    OnClickRecordTog(*) {
        MySoftData.RecordToggleCon := this.RecordMacroCon
        MySoftData.MacroEditGui := this
        OnHotToolRecordMacro(true)
    }

    OnSaveBtnClick() {
        macroStr := this.GetMacroStr()
        macroStr := GetLangMacro(macroStr, 2)
        action := this.SureBtnAction
        action(macroStr)

        this.SureBtnAction := ""
        this.Gui.Hide()

        action := this.SaveBtnAction
        action()
        this.SureFocusCon.Focus()
    }

    OnSureBtnClick() {
        macroStr := this.GetMacroStr()
        macroStr := GetLangMacro(macroStr, 2)
        action := this.SureBtnAction
        action(macroStr)

        this.SureBtnAction := ""
        this.Gui.Hide()
        this.SureFocusCon.Focus()
    }

    GetMacroStr() {
        MacroStr := ""
        if (this.MacroTreeViewCon.Visible) {
            MacroStr := this.GetTreeMacroStr(0)
        }
        else if (this.MacroEditTextCon.Visible) {
            MacroStr := this.MacroEditTextCon.Value
        }
        return MacroStr
    }

    InitMacroText(MacroStr) {
        this.MacroEditTextCon.Visible := this.EditModeCon.Value == 2

        content := RegExReplace(MacroStr, "[,，⫶]", "`n")
        this.MacroEditTextCon.Value := content
    }

    ShowContextMenu(ctrl, item, isRightClick, x, y) {
        if (item == 0)
            return

        if (this.ContextMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("编辑"), (*) => this.ContentMenuHandler(GetLang("编辑")))
            this.ContextMenu.IsSkip := true
            this.ContextMenu.Add(GetLang("跳过指令"), (*) => this.ContentMenuHandler("Skip"))
            this.ContextMenu.IsDebug := true
            this.ContextMenu.Add(GetLang("调试起点"), (*) => this.ContentMenuHandler("Debug"))
            this.ContextMenu.Add(GetLang("指令上移"), (*) => this.ContentMenuHandler(GetLang("指令上移")))
            this.ContextMenu.Add(GetLang("指令下移"), (*) => this.ContentMenuHandler(GetLang("指令下移")))

            this.ContextMenu.Add()  ; 分隔线
            subMenu := Menu()
            for value in this.CMDStrArr {
                subMenu.Add(value, this.ContentMenuHandler.Bind(this, "Pre_" value))
            }
            this.ContextMenu.Add(GetLang("上方插入"), subMenu)  ; 将子菜单添加到主菜单
            subMenu := Menu()
            for value in this.CMDStrArr {
                subMenu.Add(value, this.ContentMenuHandler.Bind(this, "Next_" value))
            }
            this.ContextMenu.Add(GetLang("下方插入"), subMenu)  ; 将子菜单添加到主菜单

            this.ContextMenu.Add()  ; 分隔线
            this.ContextMenu.Add(GetLang("共享复制"), (*) => this.ContentMenuHandler(GetLang("共享复制")))
            this.ContextMenu.Add(GetLang("完全复制"), (*) => this.ContentMenuHandler(GetLang("完全复制")))
            this.ContextMenu.Add(GetLang("上方粘贴"), (*) => this.ContentMenuHandler(GetLang("上方粘贴")))
            this.ContextMenu.Add(GetLang("下方粘贴"), (*) => this.ContentMenuHandler(GetLang("下方粘贴")))

            this.ContextMenu.Add()  ; 分隔线
            this.ContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
        }

        if (this.BranchContextMenu == "") {
            this.BranchContextMenu := Menu()

            subMenu := Menu()
            for value in this.CMDStrArr {
                subMenu.Add(value, this.ContentMenuHandler.Bind(this, "Add_" value))
            }
            this.BranchContextMenu.Add(GetLang("添加指令"), subMenu)  ; 将子菜单添加到主菜单

            this.BranchContextMenu.Add()  ; 分隔线
            this.BranchContextMenu.Add(GetLang("删除"), (*) => this.ContentMenuHandler(GetLang("删除")))
        }

        this.CurItemID := item
        this.MacroTreeViewCon.Modify(this.CurItemID, "Select")
        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        isCondi := SubStr(itemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        if (itemText == "" || SubStr(itemText, 1, 1) == "⎖")
            return
        else if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体") || isCondi) {
            this.BranchContextMenu.Show(x, y)
        }
        else {
            CurSkipMenuText := this.ContextMenu.IsSkip ? GetLang("跳过指令") : GetLang("取消跳过")
            SkipMenuText := SubStr(itemText, 1, 2) == "🚫" ? GetLang("取消跳过") : GetLang("跳过指令")
            if (CurSkipMenuText != SkipMenuText) {
                this.ContextMenu.Rename(CurSkipMenuText, SkipMenuText)
                this.ContextMenu.IsSkip := !this.ContextMenu.IsSkip
            }

            CurDebugMenuText := this.ContextMenu.IsDebug ? GetLang("调试起点") : GetLang("取消调试起点")
            DebugMenuText := SubStr(itemText, 1, 1) == "⭐" ? GetLang("取消调试起点") : GetLang("调试起点")
            if (CurDebugMenuText != DebugMenuText) {
                this.ContextMenu.Rename(CurDebugMenuText, DebugMenuText)
                this.ContextMenu.IsDebug := !this.ContextMenu.IsDebug
            }

            this.ContextMenu.Show(x, y)
        }
    }

    OnSoftKey(key, isDown) {
        if (!IsObject(this.Gui))
            return

        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible || !isDown)
            return

        if (key == "f5")
            this.MenuHandler(GetLang("运行(F5)"))
        if (key == "f6")
            this.MenuHandler(GetLang("单步运行(F6)"))
        if (key == "delete" || key == "numpaddot") {
            try {
                focusedHwnd := DllCall("GetFocus", "Ptr")
                if (focusedHwnd = this.MacroTreeViewCon.hwnd) {
                    selectedItem := this.MacroTreeViewCon.GetSelection()
                    if (selectedItem != 0) {
                        this.CurItemID := selectedItem
                        this.OnDeleteCmd()
                    }
                }
            }
        }
    }

    OnDoubleClick(ctrl, item) {
        if (item == 0)
            return

        itemText := this.MacroTreeViewCon.GetText(item)
        if (itemText == "" || SubStr(itemText, 1, 1) == "⎖")
            return

        this.CurItemID := item
        if (itemText == GetLang("真") || itemText == GetLang("假") || itemText == GetLang("循环体")) {
            if (this.SubMacroEditGui == "")
                this.SubMacroEditGui := MacroEditGui()

            macroStr := this.GetTreeMacroStr(this.CurItemID)
            this.SubMacroEditGui.SureBtnAction := this.OnSubNodeEdit.Bind(this, this.CurItemID)
            this.SubMacroEditGui.SureFocusCon := this.MacroTreeViewCon
            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.SubMacroEditGui.ParentTile := ParentTile "-"

            this.SubMacroEditGui.ShowGui(macroStr, false)
            return
        }
        else if (SubStr(itemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")) {
            if (this.CompareProEditItemGui == "")
                this.CompareProEditItemGui := CompareProEditItemGui()
            this.CompareProEditItemGui.IsSubMacroEdit := true
            this.CompareProEditItemGui.SureBtnAction := this.OnSubNodeEdit.Bind(this, this.CurItemID)

            ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
            CommndStr := this.MacroTreeViewCon.GetText(ParentID)
            ItemNumber := this.GetItemNumber(this.CurItemID)
            this.CompareProEditItemGui.MacroEditShowGui(CommndStr, ItemNumber)
            return
        }

        paramsArr := StrSplit(itemText, "_")
        cmd := GetCmdOnlyText(paramsArr[1])
        subGui := this.SubGuiMap[cmd]
        this.OnOpenSubGui(subGui, 2)
    }

    MenuHandler(cmdNextStr, *) {
        switch cmdNextStr {
            case GetLang("变量监视"):
            {
                if (MyVarListenGui.Gui != "") {
                    style := WinGetStyle(MyVarListenGui.Gui)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        this.ToolMenu.Uncheck(GetLang("变量监视"))
                        MyVarListenGui.Gui.Hide()
                        return
                    }
                }
                this.ToolMenu.Check(GetLang("变量监视"))
                MyVarListenGui.ShowGui()
            }
            case GetLang("指令显示"):
            {
                if (MyCMDTipGui.Gui != "") {
                    style := WinGetStyle(MyCMDTipGui.Gui)
                    isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
                    if (isVisible) {
                        MySoftData.CMDTip := false
                        SetCMDTipValue(false)
                        this.ToolMenu.Uncheck(GetLang("指令显示"))
                        MyCMDTipGui.Gui.Hide()
                        return
                    }
                }
                MySoftData.CMDTip := true
                SetCMDTipValue(true)
                MyCMDTipGui.ShowGui(GetLang("开启指令显示"))
                this.ToolMenu.Check(GetLang("指令显示"))
            }
            case GetLang("窗口置顶"):
            {
                WinSetAlwaysOnTop(-1, this.Gui)
                this.ToolMenu.ToggleCheck(GetLang("窗口置顶"))
            }
            case GetLang("运行(F5)"):
            {
                MacroStr := this.GetMacroStr()
                MacroStr := GetLangMacro(macroStr, 2)
                ResArr := StrSplit(MacroStr, "⭐", 2)
                MacroStr := ResArr.Length > 1 ? ResArr[2] : MacroStr
                MyCMDTipGui.Clear()
                OnTriggerSepcialItemMacro(MacroStr)
                MsgBox(GetLang("调试运行结束"), "", "Owner" this.Gui.Hwnd)
            }
            case GetLang("单步运行(F6)"):
            {
                tableItem := MySoftData.SpecialTableItem
                if (tableItem.ColorStateArr[1] == 1) {
                    return
                }

                if (this.DebugItemID == 0) {
                    MyCMDTipGui.Clear()
                    this.DebugItemID := this.MacroTreeViewCon.GetNext(this.DebugItemID)
                }
                CurCMD := this.MacroTreeViewCon.GetText(this.DebugItemID)
                CurCMD := StrReplace(CurCMD, "⭐", "")
                CurLangCMD := GetLangMacro(CurCMD, 2)
                OnTriggerSepcialItemMacro(CurLangCMD)
                this.MacroTreeViewCon.Modify(this.DebugItemID, , CurCMD)
                loop {
                    if (this.DebugItemID == this.LastItemID) {
                        this.DebugItemID := 0
                        MsgBox(GetLang("单步运行结束"), "", "Owner" this.Gui.Hwnd)
                        return
                    }
                    this.DebugItemID := this.MacroTreeViewCon.GetNext(this.DebugItemID)
                    cmdNextStr := this.MacroTreeViewCon.GetText(this.DebugItemID)
                    if (SubStr(cmdNextStr, 1, 2) == "🚫") {
                        continue
                    }
                    break
                }
                cmdNextStr := StrReplace(cmdNextStr, "⭐", "")
                cmdNextStr := "⭐" cmdNextStr
                this.MacroTreeViewCon.Modify(this.DebugItemID, , cmdNextStr)
            }
            case GetLang("终止"):
            {
                this.DebugStepNum := 0
                this.DebugItemID := 0
                KillSingleTableMacro(MySoftData.SpecialTableItem)
                MyCMDTipGui.AddCMD(GetLang("终止"))
            }
        }
    }

    ContentMenuHandler(cmdStr, *) {
        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        paramsArr := StrSplit(cmdStr, "_")
        if (paramsArr.Length == 2) {
            modeType := paramsArr[1] == "Pre" ? 3 : paramsArr[1] == "Next" ? 4 : 5
            this.CmdEditType := modeType
            subGui := this.SubGuiMap[paramsArr[2]]
            this.OnOpenSubGui(subGui, modeType)
            return
        }

        switch cmdStr {
            case GetLang("编辑"):
            {
                paramsArr := StrSplit(itemText, "_")
                cmd := GetCmdOnlyText(paramsArr[1])
                subGui := this.SubGuiMap[cmd]
                this.OnOpenSubGui(subGui, 2)
            }
            case "Skip":
            {
                if (SubStr(itemText, 1, 1) == "⭐") {
                    MsgBox(GetLang("调试起点不能跳过"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                IsToSkip := SubStr(itemText, 1, 2) != "🚫"
                CommandStr := IsToSkip ? "🚫" itemText : SubStr(itemText, 3)
                this.OnModifyCmd(CommandStr)
            }
            case "Debug":
                if (SubStr(itemText, 1, 2) == "🚫") {
                    MsgBox(GetLang("跳过指令不可设置为调试起点"), "", "Owner" this.Gui.Hwnd)
                    return
                }
                IsToDebug := SubStr(itemText, 1, 1) != "⭐"
                CommandStr := IsToDebug ? "⭐" itemText : SubStr(itemText, 2)
                this.DebugItemID := this.CurItemID
                this.OnModifyCmd(CommandStr)
            case GetLang("指令上移"):
            {
                this.OnPreMoveCmd()
            }
            case GetLang("指令下移"):
            {
                this.OnNextMoveCmd()
            }
            case GetLang("共享复制"):
            {
                A_Clipboard := itemText
            }
            case GetLang("完全复制"):
            {
                A_Clipboard := FullCopyCmd(itemText)
            }
            case GetLang("上方粘贴"):
            {
                this.OnPreInsertCmd(A_Clipboard)
            }
            case GetLang("下方粘贴"):
            {
                this.OnNextInsertCmd(A_Clipboard)
            }
            case GetLang("删除"):
            {
                this.OnDeleteCmd()
            }
        }
    }

    InitTreeView(MacroStr) {
        this.MacroTreeViewCon.Visible := this.EditModeCon.Value == 1
        cmdArr := SplitMacro(MacroStr)
        this.MacroTreeViewCon.Opt("-Redraw")
        this.MacroTreeViewCon.Delete()
        this.LastItemID := 0
        isSetDebug := false
        for cmdStr in cmdArr {
            iconStr := this.GetCmdIconStr(cmdStr)
            root := this.MacroTreeViewCon.Add(cmdStr, 0, iconStr)
            this.LastItemID := root
            this.TreeAddBranch(root, cmdStr)
            if (!isSetDebug && SubStr(cmdStr, 1, 1) == "⭐") {
                isSetDebug := true
                this.DebugItemID := root
            }
        }
        this.MacroTreeViewCon.Opt("+Redraw")
    }

    RefreshTree(itemID) {
        CommandStr := this.MacroTreeViewCon.GetText(itemID)
        paramsArr := StrSplit(CommandStr, "_")

        subItem := this.MacroTreeViewCon.GetChild(itemID)
        while (subItem) {
            this.MacroTreeViewCon.Delete(subItem)
            subItem := this.MacroTreeViewCon.GetChild(itemID)
        }
        this.TreeAddBranch(itemID, CommandStr)
        this.TreeExpand(itemID, 2)
    }

    TreeAddBranch(root, cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        IsSkip := SubStr(paramArr[1], 1, 2) == "🚫"
        IsSearchPro := InStr(paramArr[1], GetLang("搜索Pro"))
        IsSearch := InStr(paramArr[1], GetLang("搜索")) && !IsSearchPro
        IsIfPro := InStr(paramArr[1], GetLang("如果Pro"))
        IsIf := InStr(paramArr[1], GetLang("如果")) && !IsIfPro
        IsLoop := InStr(paramArr[1], GetLang("循环"))
        Cmd := GetCmdOnlyText(paramArr[1])
        SerialStr := GetCmdStr(paramArr[1])
        if (IsSkip)
            return
        if (!IsSearch && !IsSearchPro && !IsIf && !IsLoop && !IsIfPro)
            return

        ParentID := this.MacroTreeViewCon.GetParent(root)
        while (ParentID != 0) {
            itemText := this.MacroTreeViewCon.GetText(ParentID)
            itemParamArr := StrSplit(itemText, "_")
            ParentID := this.MacroTreeViewCon.GetParent(ParentID)
            if (itemParamArr[1] == paramArr[1])
                return
        }

        Data := GetMacroCMDData(SerialStr)
        if (IsIf || IsSearch || IsSearchPro) {
            TrueMacro := GetLangMacro(Data.TrueMacro, 1)
            FalseMacro := GetLangMacro(Data.FalseMacro, 1)

            iconStr := this.GetCmdIconStr(GetLang("真"))
            trueRoot := this.MacroTreeViewCon.Add(GetLang("真"), root, iconStr)
            this.TreeAddSubTree(trueRoot, TrueMacro)

            iconStr := this.GetCmdIconStr(GetLang("假"))
            falseRoot := this.MacroTreeViewCon.Add(GetLang("假"), root, iconStr)
            this.TreeAddSubTree(falseRoot, FalseMacro)
        }
        else if (IsLoop) {
            iconStr := this.GetCmdIconStr(GetLang("循环次数"))
            countStr := Data.LoopCount == -1 ? GetLang("无限") : Data.LoopCount
            CountRoot := this.MacroTreeViewCon.Add(Format("{}:{}", GetLang("⎖循环次数"), countStr), root, iconStr)

            if (Data.CondiType != 1) {
                iconStr := this.GetCmdIconStr(GetLang("条件"))
                CondiStr := Data.CondiType == 2 ? GetLang("⎖继续条件：") : GetLang("⎖退出条件：")
                ItemStr := CondiStr . LoopData.GetCondiStr(Data)
                CondiRoot := this.MacroTreeViewCon.Add(ItemStr, root, iconStr)
            }

            iconStr := this.GetCmdIconStr(GetLang("循环体"))
            BodyRoot := this.MacroTreeViewCon.Add(GetLang("循环体"), root, iconStr)
            LoopBody := GetLangMacro(Data.LoopBody, 1)
            this.TreeAddSubTree(BodyRoot, LoopBody)
        }
        else if (IsIfPro) {
            iconStr := this.GetCmdIconStr(GetLang("条件"))
            loop Data.VariNameArr.Length {
                CondiStr := GetLang("条件：") CompareProData.GetCondiStr(Data, A_Index)
                CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
                MacroStr := GetLangMacro(Data.MacroArr[A_Index], 1)
                this.TreeAddSubTree(CondiRoot, MacroStr)
            }

            CondiStr := GetLang("条件：以上都不是")
            CondiRoot := this.MacroTreeViewCon.Add(CondiStr, root, iconStr)
            DefaultMacro := GetLangMacro(Data.DefaultMacro, 1)
            this.TreeAddSubTree(CondiRoot, DefaultMacro)
        }
    }

    TreeAddSubTree(root, CommandStr) {
        if (CommandStr == "")
            return

        cmdArr := SplitMacro(CommandStr)
        for cmdStr in cmdArr {
            iconStr := this.GetCmdIconStr(cmdStr)
            subRoot := this.MacroTreeViewCon.Add(cmdStr, root, iconStr)
            this.TreeAddBranch(subRoot, cmdStr)
        }
    }

    ;打开子指令编辑器 modeType 1:默认行尾追加 2:编辑修改 3:上方插入 4:下方插入 5:真假节点添加
    OnOpenSubGui(subGui, modeType := 1) {
        this.CmdEditType := modeType
        if ObjHasOwnProp(subGui, "ParentTile") {
            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            subGui.ParentTile := ParentTile "-"
        }

        if (modeType == 2) {
            ItemText := this.MacroTreeViewCon.GetText(this.CurItemID)
            CommandStr := GetCmdStr(ItemText)
            subGui.ShowGui(CommandStr)
            return
        }
        subGui.ShowGui("")
    }

    ;确定子指令编辑器
    OnSubGuiSureBtnClick(CommandStr) {
        if (this.CmdEditType == 1) {
            this.OnAddCmd(CommandStr)
        }
        else if (this.CmdEditType == 2) {
            this.OnModifyCmd(CommandStr)
        }
        else if (this.CmdEditType == 3) {
            this.OnPreInsertCmd(CommandStr)
        }
        else if (this.CmdEditType == 4) {
            this.OnNextInsertCmd(CommandStr)
        }
        else if (this.CmdEditType == 5) {
            this.OnSubNodeAddCmd(CommandStr)
        }
        MySoftData.RecordToggleCon := this.RecordMacroCon
        MySoftData.MacroEditGui := this
    }

    ;添加指令
    OnAddCmd(CommandStr) {
        if (this.EditModeCon.Value == 1) {
            iconStr := this.GetCmdIconStr(CommandStr)
            root := this.MacroTreeViewCon.Add(CommandStr, 0, iconStr)
            this.TreeAddBranch(root, CommandStr)
            this.LastItemID := root
        }
        else {
            MacroStr := this.GetMacroStr()
            MacroStr .= "`n" CommandStr
            cmdArr := SplitMacro(MacroStr)
            MacroStr := GetMacroStrByCmdArr(cmdArr)

            ; 回到替换前的滑动值
            firstVisible := SendMessage(0xCE, 0, 0, this.MacroEditTextCon) ; EM_GETFIRSTVISIBLELINE = 0xCE
            this.InitMacroText(MacroStr)
            SendMessage(0xB6, 0, firstVisible, this.MacroEditTextCon) ; EM_LINESCROLL = 0xB6
        }
    }

    ;修改指令
    OnModifyCmd(CommandStr) {
        this.MacroTreeViewCon.Modify(this.CurItemID, , CommandStr)
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        if (ParentID == 0) {
            this.RefreshTree(this.CurItemID)
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this.RefreshTree(RealItemID)
    }

    OnPreMoveCmd() {
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        if (PreItemID == 0) {
            MsgBox(GetLang("已经是第一个指令了，无法上移"))
            return
        }
        this.OnSwitchCmd(PreItemID, this.CurItemID)
    }

    OnNextMoveCmd() {
        NextItemID := this.MacroTreeViewCon.GetNext(this.CurItemID)
        if (NextItemID == 0) {
            MsgBox(GetLang("已经是最后的指令了，无法下移"))
            return
        }
        this.OnSwitchCmd(this.CurItemID, NextItemID)
    }

    OnSwitchCmd(ItemAID, ItemBID) {
        LastItemID := this.MacroTreeViewCon.GetPrev(ItemAID)
        ParentID := this.MacroTreeViewCon.GetParent(ItemAID)
        NewACmdStr := this.MacroTreeViewCon.GetText(ItemBID)
        NewBCmdStr := this.MacroTreeViewCon.GetText(ItemAID)
        NewAIconStr := this.GetCmdIconStr(NewACmdStr)
        NewBIconStr := this.GetCmdIconStr(NewBCmdStr)

        this.MacroTreeViewCon.Delete(ItemAID)
        this.MacroTreeViewCon.Delete(ItemBID)
        SortArg := LastItemID == 0 ? "First" : LastItemID
        NewItemAID := this.MacroTreeViewCon.Add(NewACmdStr, ParentID, SortArg " " NewAIconStr)
        NewItemBID := this.MacroTreeViewCon.Add(NewBCmdStr, ParentID, NewItemAID " " NewBIconStr)
        this.TreeAddBranch(NewItemAID, NewACmdStr)
        this.TreeAddBranch(NewItemBID, NewBCmdStr)
        if (ParentID == 0) {
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)

        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this.RefreshTree(RealItemID)
    }

    OnDeleteCmd() {
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        if (ParentID == 0) {
            this.MacroTreeViewCon.Delete(this.CurItemID)
            return
        }

        itemText := this.MacroTreeViewCon.GetText(this.CurItemID)
        NodeItemID := this.CurItemID
        RealItemID := ParentID
        macroStr := ""
        isTrueOrFalse := itemText == GetLang("真") || itemText == GetLang("假")
        isLoopBody := itemText == GetLang("循环体")
        isCondi := SubStr(itemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        if (!(isTrueOrFalse || isLoopBody || isCondi)) {
            this.MacroTreeViewCon.Delete(this.CurItemID)
            NodeItemID := ParentID
            RealItemID := this.MacroTreeViewCon.GetParent(NodeItemID)
            macroStr := this.GetTreeMacroStr(NodeItemID)

            NodeItemText := this.MacroTreeViewCon.GetText(NodeItemID)
            isCondi := SubStr(NodeItemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
            macroStr := macroStr == "" && isCondi ? " " : macroStr
        }
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, NodeItemID)
        this.RefreshTree(RealItemID)
    }

    ;插入指令
    OnPreInsertCmd(CommandStr) {
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        PreItemID := this.MacroTreeViewCon.GetPrev(this.CurItemID)
        Seq := PreItemID == 0 ? "First" : PreItemID
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(CommandStr, ParentID, Seq " " iconStr)
        if (ParentID == 0) {
            this.TreeAddBranch(newItemID, CommandStr)
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this.RefreshTree(RealItemID)
    }

    ;插入指令
    OnNextInsertCmd(CommandStr) {
        ParentID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(CommandStr, ParentID, this.CurItemID " " iconStr)
        if (this.CurItemID == this.LastItemID)
            this.LastItemID := newItemID

        if (ParentID == 0) {
            this.TreeAddBranch(newItemID, CommandStr)
            return
        }

        macroStr := this.GetTreeMacroStr(ParentID)
        RealItemID := this.MacroTreeViewCon.GetParent(ParentID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, ParentID)
        this.RefreshTree(RealItemID)
    }

    OnSubNodeAddCmd(CommandStr) {
        iconStr := this.GetCmdIconStr(CommandStr)
        newItemID := this.MacroTreeViewCon.Add(CommandStr, this.CurItemID, iconStr)
        macroStr := this.GetTreeMacroStr(this.CurItemID)

        RealItemID := this.MacroTreeViewCon.GetParent(this.CurItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        this.SaveCommandData(RealCommandStr, macroStr, this.CurItemID)
        this.RefreshTree(RealItemID)
    }

    OnSubNodeEdit(nodeItemID, macroStr) {
        RealItemID := this.MacroTreeViewCon.GetParent(nodeItemID)
        RealCommandStr := this.MacroTreeViewCon.GetText(RealItemID)
        macroStr := macroStr == "" ? " " : macroStr
        this.SaveCommandData(RealCommandStr, macroStr, nodeItemID)
        this.RefreshTree(RealItemID)
    }

    TreeExpand(ItemID, Num) {
        if (Num == 0)
            return

        rootItemID := this.MacroTreeViewCon.GetChild(ItemID)
        while (rootItemID) {
            this.MacroTreeViewCon.Modify(rootItemID, "Expand")
            this.TreeExpand(rootItemID, Num - 1)
            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
    }

    GetTreeMacroStr(ItemID) {
        macroStr := ""
        rootItemID := this.MacroTreeViewCon.GetChild(ItemID)
        while (rootItemID) {
            cmdStr := this.MacroTreeViewCon.GetText(rootItemID)
            macroStr .= cmdStr ","
            rootItemID := this.MacroTreeViewCon.GetNext(rootItemID)
        }
        macroStr := Trim(macroStr, ",")
        return macroStr
    }

    GetCmdIconStr(cmdStr) {
        paramArr := StrSplit(cmdStr, "_")
        paramArr[1] := GetCmdStr(paramArr[1])

        textOnly := RegExReplace(paramArr[1], "\d+")
        if (this.IconMap.Has(textOnly)) {
            return this.IconMap.Get(textOnly)
        }
        return ""
    }

    SaveCommandData(RealCommandStr, macroStr, nodeItemID) {
        paramArr := StrSplit(RealCommandStr, "_")
        cmd := RegExReplace(paramArr[1], "\d+")

        ; 映射表：命令 → 文件名
        fileMap := Map(
            GetLang("搜索"), SearchFile,
            GetLang("搜索Pro"), SearchProFile,
            GetLang("如果"), CompareFile,
            GetLang("如果Pro"), CompareProFile,
            GetLang("循环"), LoopFile
        )
        if (!fileMap.Has(cmd))
            return

        ItemNumber := this.GetItemNumber(nodeItemID)
        Data := GetMacroCMDData(paramArr[1])
        macroStr := GetLangMacro(macroStr, 2)
        if (cmd == GetLang("循环")) {
            Data.LoopBody := macroStr
        }
        else if (cmd == GetLang("如果Pro")) {
            if (ItemNumber > Data.VariNameArr.Length) {
                if (macroStr == "")
                    MsgBox("最后的分支不能删除，已清空分支指令")
                Data.DefaultMacro := Trim(macroStr)
            }
            else {
                if (macroStr == "") {
                    Data.VariNameArr.RemoveAt(ItemNumber)
                    Data.CompareTypeArr.RemoveAt(ItemNumber)
                    Data.VariableArr.RemoveAt(ItemNumber)
                    Data.LogicTypeArr.RemoveAt(ItemNumber)
                    Data.MacroArr.RemoveAt(ItemNumber)
                }
                else {
                    Data.MacroArr[ItemNumber] := Trim(macroStr)
                }
            }
        }
        else {
            if (ItemNumber == 1)    ;真
                Data.TrueMacro := macroStr
            else
                Data.FalseMacro := macroStr
        }

        SaveMacroCMDData(Data)
    }

    GetItemNumber(nodeItemID) {
        ItemNumber := 1
        PreItemID := this.MacroTreeViewCon.GetPrev(nodeItemID)
        while (PreItemID != 0) {
            ItemNumber += 1
            PreItemID := this.MacroTreeViewCon.GetPrev(PreItemID)
        }
        return ItemNumber
    }
}
