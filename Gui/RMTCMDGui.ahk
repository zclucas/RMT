#Requires AutoHotkey v2.0

class RMTCMDGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.CategoriesArr := [GetLang("全部"), GetLang("图文"), GetLang("输入控制"),
        GetLang("宏控制"), GetLang("调试"), GetLang("软件自身")]
        this.CategoriesMap := Map(
            GetLang("图文"), [
                GetLang("截图"),
                GetLang("截图提取文本"),
                GetLang("自由贴")
            ],
            GetLang("输入控制"), [
                GetLang("启用鼠标"),
                GetLang("启用键盘"),
                GetLang("启用键鼠"),
                GetLang("禁用鼠标"),
                GetLang("禁用键盘"),
                GetLang("禁用键鼠"),
                GetLang("启用鼠标加速"),
                GetLang("禁用鼠标加速")
            ],
            GetLang("宏控制"), [
                GetLang("显示菜单"),
                GetLang("关闭菜单"),
                GetLang("暂停所有宏"),
                GetLang("恢复所有宏"),
                GetLang("终止所有宏")
            ],
            GetLang("调试"), [
                GetLang("开启变量监视"),
                GetLang("关闭变量监视"),
                GetLang("开启指令显示"),
                GetLang("关闭指令显示"),
            ],
            GetLang("软件自身"), [
                GetLang("关闭软件"),
                GetLang("休眠"),
                GetLang("重载")
            ],
        )
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            if (this.OwnerHwnd != "") {
                this.Gui.Opt("+Owner" this.OwnerHwnd)
            }
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init(cmd)
        this.OnCmdChange()
    }

    Init(cmd) {
        ; 新格式: RMT指令_类别_指令 或 RMT指令_类别_指令_序号
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        if (cmdArr.Length >= 4) {
            cmdCategory := cmdArr[2]
            cmdStr := cmdArr[3]
            menuDLIndex := cmdStr == GetLang("显示菜单") && cmdArr.Length >= 5 ? cmdArr[4] : 1
        } else if (cmdArr.Length >= 3) {
            cmdCategory := cmdArr[2]
            cmdStr := cmdArr[3]
            menuDLIndex := 1
        } else {
            cmdCategory := GetLang("全部")
            cmdStr := GetLang("截图")
            menuDLIndex := 1
        }

        this.InitCategoriesMap()
        Category := cmdCategory
        CmdStrArr := this.CategoriesMap[Category]

        this.CategoryCon.Text := Category
        this.CmdTypeCon.Delete()
        this.CmdTypeCon.Add(CmdStrArr)
        this.CmdTypeCon.Text := cmdStr

        FoldInfo := MySoftData.TableInfo[3].FoldInfo
        this.MenuDLCon.Delete()
        DropDownArr := []
        loop FoldInfo.RemarkArr.Length {
            DropDownArr.Push(A_Index ". " FoldInfo.RemarkArr[A_Index])
        }
        this.MenuDLCon.Add(DropDownArr)
        this.MenuDLCon.Value := menuDLIndex
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("RMT指令编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S11 W550 Q2", MainSoftData.FontType)

        PosX := 15
        PosY := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("类别："))
        PosX += 80
        this.CategoryCon := MyGui.Add(
            "DropDownList",
            Format("x{} y{} w180 R16", PosX, PosY - 3),
            this.CategoriesArr
        )
        this.CategoryCon.OnEvent("Change", this.OnTypeChane.Bind(this))

        PosX := 15
        PosY += 40
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("指令："))
        PosX += 80
        this.CmdTypeCon := MyGui.Add("DropDownList",
            Format("x{} y{} w180 R20", PosX, PosY - 3), [])
        this.CmdTypeCon.OnEvent("Change", this.OnCmdChange.Bind(this))

        PosY += 40
        SplitPosY := PosY

        PosX := 15
        PosY := SplitPosY
        this.MenuRelateArrCon := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 90), GetLang("菜单序号："))
        this.MenuRelateArrCon.Push(con)

        PosX += 80
        this.MenuDLCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 5, 180), [])
        this.MenuRelateArrCon.Push(this.MenuDLCon)

        PosX := 100
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())

        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        pos := GetCenterPosOnActiveMonitor(300, 190)
        MyGui.Show(Format("x{} y{} w{} h{}", pos.x, pos.y, 300, 190))
    }

    OnGuiClose() {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
    }

    OnTypeChane(*) {
        Category := this.CategoryCon.Text
        CmdStrArr := this.CategoriesMap[Category]

        this.CmdTypeCon.Delete()
        this.CmdTypeCon.Add(CmdStrArr)
        this.CmdTypeCon.Value := 1
        this.OnCmdChange()
    }

    ; 操作类型 DropDownList Change 处理
    OnCmdChange(*) {
        CmdStr := this.CmdTypeCon.Text

        IsShowMenuDL := CmdStr == GetLang("显示菜单")
        for _, con in this.MenuRelateArrCon
            con.Visible := IsShowMenuDL
    }

    OnSureBtnClick() {
        if (!this.CheckIfValid())
            return

        CommandStr := this.GetCommandStr()
        this.SureBtnAction.Call(CommandStr)

        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    CheckIfValid() {
        cmd := this.CmdTypeCon.Text
        if (cmd == GetLang("禁用键鼠") || cmd == GetLang("禁用鼠标") || cmd == GetLang("禁用键盘")) {
            if (cmd == GetLang("禁用鼠标"))
                tipBody := GetLang("此操作将 立即禁用鼠标输入，您将无法通过鼠标操作计算机！")
            else if (cmd == GetLang("禁用键盘"))
                tipBody := GetLang("此操作将 立即禁用键盘输入，您将无法通过键盘操作计算机！")
            else
                tipBody := GetLang("此操作将 立即禁用键盘和鼠标输入，您将无法通过键鼠操作计算机！")
            tipStr := Format("{}`n{}`n{}`n{}`n{}", tipBody, GetLang("重要须知："), GetLang(
                "- 以管理员身份运行本软件，否则该指令无效。"), GetLang("- 务必后续执行对应的启用指令，否则输入设备将保持禁用状态！"), GetLang("是否确认禁用？"))
            title := cmd == GetLang("禁用鼠标") ? GetLang("禁用鼠标（需管理员权限）")
                : (cmd == GetLang("禁用键盘") ? GetLang("禁用键盘（需管理员权限）") : GetLang("禁用键鼠（需管理员权限）"))
            if (MsgBox(tipStr, title, "4") == "No")
                return false
        }

        if (cmd == GetLang("启用键鼠") || cmd == GetLang("启用鼠标") || cmd == GetLang("启用键盘")) {
            title := cmd == GetLang("启用鼠标") ? GetLang("启用鼠标（需管理员权限）")
                : (cmd == GetLang("启用键盘") ? GetLang("启用键盘（需管理员权限）") : GetLang("启用键鼠（需管理员权限）"))
            MsgBox(GetLang("- 必须 以管理员身份运行本软件，否则该指令无效。"), title)
        }
        return true
    }

    GetCommandStr() {
        ; CMD格式: RMT指令_类别_指令 或 RMT指令_类别_指令_序号
        CommandStr := Format("{}_{}_{}", GetLang("RMT指令"), this.CategoryCon.Text, this.CmdTypeCon.Text)
        if (this.CmdTypeCon.Text == GetLang("显示菜单")) {
            CommandStr .= "_" this.MenuDLCon.Value
        }
        return CommandStr
    }

    InitCategoriesMap() {
        if (this.CategoriesMap.Has(GetLang("全部")))
            return

        AllCmdArr := []
        for Index, Value in this.CategoriesArr {
            if (this.CategoriesMap.Has(Value)) {
                CmdStrArr := this.CategoriesMap[Value]
                AllCmdArr.Push(CmdStrArr*)
            }
        }
        this.CategoriesMap.Set(GetLang("全部"), AllCmdArr)
    }
}
