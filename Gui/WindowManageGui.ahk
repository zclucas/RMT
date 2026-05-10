#Requires AutoHotkey v2.0

class WindowManageGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.ActionTypeCon := ""

        this.InfoTogArrCon := []
        this.InfoTextArrCon := []

        this.PosXCon := ""
        this.PosYCon := ""
        this.WidthCon := ""
        this.HeightCon := ""
        this.NewTitleCon := ""

        this.PosRelateArrCon := []
        this.SizeRelateArrCon := []
        this.TitleRelateArrCon := []

        this.TopTogCon := ""
        this.InfoAction := () => this.RefreshMouseInfo()
        this.CurWinInfoCon := ""
        this.VarConArr := []
        this.VariCon := ""
        this.VariTipCon := ""
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

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.Init(cmd)
        this.OnActionChange()
        SetTimer this.InfoAction, 100
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("窗口管理")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        actionIndex := this.Data.ActionType > 0 ? this.Data.ActionType : 1
        this.ActionTypeCon.Value := actionIndex

        infoStr := this.Data.SearchValue
        if (infoStr == "")
            infoArr := ["", "", "", ""]
        else if (InStr(infoStr, "❖"))
            infoArr := [StrReplace(infoStr, "❖", ""), "", "", ""]
        else
            infoArr := StrSplit(infoStr, "⎖")

        loop 4 {
            index := A_Index + 0
            if (index <= infoArr.Length) {
                this.InfoTogArrCon[index].Value := infoArr[index] != ""
                this.InfoTextArrCon[index].Value := infoArr[index]
            } else {
                this.InfoTogArrCon[index].Value := false
                this.InfoTextArrCon[index].Value := ""
            }
        }

        DLVariableArr := GetGuiVarArr(4)
        this.VariCon.Delete()
        this.VariCon.Add(DLVariableArr)
        this.VariCon.Value := 1
        this.OnTogClick()

        this.PosXCon.Delete()
        this.PosXCon.Add(DLVariableArr)
        this.PosXCon.Value := this.Data.PosX

        this.PosYCon.Delete()
        this.PosYCon.Add(DLVariableArr)
        this.PosYCon.Value := this.Data.PosY

        this.WidthCon.Delete()
        this.WidthCon.Add(DLVariableArr)
        this.WidthCon.Value := this.Data.Width

        this.HeightCon.Delete()
        this.HeightCon.Add(DLVariableArr)
        this.HeightCon.Value := this.Data.Height

        this.NewTitleCon.Delete()
        this.NewTitleCon.Add(DLVariableArr)
        this.NewTitleCon.Text := this.Data.NewTitle
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("窗口管理编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        PosX := 10
        PosY := 10

        PosX := 10
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口置顶"))
        con.OnEvent("Click", this.OnTogClick.Bind(this))
        this.TopTogCon := con

        PosX := 130
        con := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 30), "F1")
        con.Enabled := false
        PosX += 30
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("确定信息"))

        PosX += 80
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX, PosY - 4), "?")
        Con.OnEvent("Click", this.OnClickTypeHelpBtn.Bind(this))

        PosX += 80
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 130), "")

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("当前鼠标下窗口信息："))

        PosY += 25
        PosX := 10
        this.CurWinInfoCon := MyGui.Add("Text", Format("x{} y{} w800 h90", PosX, PosY))

        PosY += 95
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("句柄ID"))
        con.OnEvent("Click", this.OnTogClick.Bind(this))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 32
        PosX := 175
        this.VarConArr := []
        this.VariTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 150), GetLang("变量:"))
        this.VarConArr.Push(this.VariTipCon)

        PosX += 45
        this.VariCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 130), [])
        this.VarConArr.Push(this.VariCon)

        PosX += 135
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 100, 30), GetLang("追加变量值"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarValueBtn())
        this.VarConArr.Push(btnCon)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("标题"))
        con.OnEvent("Click", this.OnTogClick.Bind(this))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口类"))
        con.OnEvent("Click", this.OnTogClick.Bind(this))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("进程名"))
        con.OnEvent("Click", this.OnTogClick.Bind(this))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("操作类型："))
        PosX += 80
        this.ActionTypeCon := MyGui.Add(
            "DropDownList",
            Format("x{} y{} w200 R10", PosX, PosY - 3),
            [
                GetLang("激活窗口"),
                GetLang("最大化窗口"),
                GetLang("最小化窗口"),
                GetLang("还原窗口"),
                GetLang("关闭窗口"),
                GetLang("移动窗口"),
                GetLang("调整大小"),
                GetLang("置顶窗口"),
                GetLang("取消置顶"),
                GetLang("修改标题")
            ]
        )
        this.ActionTypeCon.OnEvent("Change", this.OnActionChange.Bind(this))

        SplitPosY := PosY + 38

        PosX := 10
        PosY := SplitPosY
        this.PosRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标X："))
        this.PosRelateArrCon.Push(con)
        PosX += 55
        this.PosXCon := MyGui.Add("ComboBox", Format("x{} y{} w150 R8", PosX, PosY - 3), [])
        this.PosRelateArrCon.Push(this.PosXCon)

        PosX := 230
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("坐标Y："))
        this.PosRelateArrCon.Push(con)
        PosX += 55
        this.PosYCon := MyGui.Add("ComboBox", Format("x{} y{} w150 R8", PosX, PosY - 3), [])
        this.PosRelateArrCon.Push(this.PosYCon)

        PosX := 10
        PosY := SplitPosY
        this.SizeRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("宽度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 55
        this.WidthCon := MyGui.Add("ComboBox", Format("x{} y{} w150 R8", PosX, PosY - 3), [])
        this.SizeRelateArrCon.Push(this.WidthCon)

        PosX := 230
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("高度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 55
        this.HeightCon := MyGui.Add("ComboBox", Format("x{} y{} w150 R8", PosX, PosY - 3), [])
        this.SizeRelateArrCon.Push(this.HeightCon)

        PosX := 10
        PosY := SplitPosY
        this.TitleRelateArrCon := []

        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("新标题："))
        this.TitleRelateArrCon.Push(con)
        PosX := 65
        this.NewTitleCon := MyGui.Add("ComboBox", Format("x{} y{} w380 R8", PosX, PosY - 3), [])
        this.TitleRelateArrCon.Push(this.NewTitleCon)

        PosY := SplitPosY + 42
        PosX := 220
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnClickSureBtn())

        Hotkey("F1", (*) => this.OnF1(), "On")

        MyGui.OnEvent("Close", (*) => this.OnClose())
        MyGui.Show(Format("w{} h{}", 520, 540))
    }

    OnActionChange(*) {
        actionType := this.ActionTypeCon.Value

        isShowPos := (actionType == 6)
        isShowSize := (actionType == 7)
        isShowTitle := (actionType == 10)

        for _, con in this.PosRelateArrCon
            con.Visible := isShowPos

        for _, con in this.SizeRelateArrCon
            con.Visible := isShowSize

        for _, con in this.TitleRelateArrCon
            con.Visible := isShowTitle
    }



    OnTogClick(*) {
        if (this.TopTogCon.Value) {
            this.Gui.Opt("+AlwaysOnTop")
        }
        else {
            this.Gui.Opt("-AlwaysOnTop")
        }

        isHwndID := this.InfoTogArrCon[1].Value
        this.InfoTextArrCon[1].Enabled := isHwndID
        loop this.VarConArr.Length {
            con := this.VarConArr[A_Index]
            con.Enabled := isHwndID
        }
        loop 4 {
            if (A_Index == 1)
                continue
            if (isHwndID) {
                this.InfoTogArrCon[A_Index].Value := false
                this.InfoTextArrCon[A_Index].Enabled := false
            }
            else {
                Enable := this.InfoTogArrCon[A_Index].Value
                this.InfoTextArrCon[A_Index].Enabled := Enable
            }
        }
    }

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("优先级：句柄ID > 标题 + 窗口类 + 进程名")
        str2 := GetLang("句柄ID支持多ID任意适配")

        str := Format("{}`n{}", str1, str2)
        MsgBox(str, GetLang("窗口信息说明"), "Owner" this.Gui.Hwnd)
    }

    OnF1() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }
            this.InfoTextArrCon[1].Value := winId
            this.InfoTextArrCon[2].Value := title
            this.InfoTextArrCon[3].Value := className
            this.InfoTextArrCon[4].Value := process
            loop 4 {
                state := A_Index != 1
                this.InfoTogArrCon[A_Index].Value := state
            }
            this.OnTogClick()
        }
    }

    RefreshMouseInfo() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            title := WinGetTitle(winId)
            className := WinGetClass(winId)
            try {
                WinPID := WinGetPID("ahk_id " winId)
                process := ProcessGetName(WinPID)
            }
            catch {
                process := ""
            }

            tipStr := Format("{}{}`n{}{}`n{}{}`n{}{}", GetLang("句柄ID："), winId, GetLang("标题："), title, GetLang("窗口类："),
            className, GetLang("进程名："),
            process)
            this.CurWinInfoCon.Value := tipStr
        }
    }

    OnClickAddVarValueBtn() {
        Symbol := this.InfoTextArrCon[1].Text == "" ? "" : "|"
        VarStr := "{" this.VariCon.Text "}"
        if (this.VariCon.Text == "") {
            MsgBox("请勿添加空字符变量", "", "Owner" this.Gui.Hwnd)
            return
        }
        if (InStr(this.InfoTextArrCon[1].Text, VarStr)) {
            MsgBox("请勿重复添加变量", "", "Owner" this.Gui.Hwnd)
            return
        }

        this.InfoTextArrCon[1].Text .= Symbol VarStr
    }

    OnClose(*) {
        Hotkey("F1", (*) => this.OnF1(), "Off")
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnClickSureBtn() {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        this.SureBtnAction.Call(CommandStr)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.OnClose()
    }

    CheckIfValid() {
        hasAnySearch := false
        if (this.InfoTogArrCon[1].Value) {
            hasAnySearch := true
            if (this.InfoTextArrCon[1].Value == "") {
                MsgBox(GetLang("勾选句柄ID后，句柄ID内容不能为空"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }
        loop 3 {
            index := A_Index + 1
            if (this.InfoTogArrCon[index].Value) {
                hasAnySearch := true
                if (this.InfoTextArrCon[index].Value == "") {
                    typeNames := [GetLang("标题"), GetLang("窗口类"), GetLang("进程名")]
                    MsgBox(Format(GetLang("勾选{}后，内容不能为空！"), typeNames[index]), "", "Owner" this.Gui.Hwnd)
                    return false
                }
            }
        }

        if (!hasAnySearch) {
            MsgBox(GetLang("至少需要勾选一个查找条件！"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        actionType := this.ActionTypeCon.Value
        if (actionType == 6) {
            posXStr := this.PosXCon.Value
            posYStr := this.PosYCon.Value
            if (!IsNumber(posXStr) || !IsNumber(posYStr)) {
                MsgBox(GetLang("坐标请输入数字！"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        if (actionType == 7) {
            widthStr := this.WidthCon.Value
            heightStr := this.HeightCon.Value
            if (!IsNumber(widthStr) || !IsNumber(heightStr)) {
                MsgBox(GetLang("宽高请输入数字！"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        if (actionType == 10) {
            if (this.NewTitleCon.Value == "") {
                MsgBox(GetLang("新标题不能为空！"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        return true
    }

    SaveData() {
        this.Data.ActionType := this.ActionTypeCon.Value

        if (this.InfoTogArrCon[1].Value) {
            searchStr := "❖" this.InfoTextArrCon[1].Value
        }
        else {
            searchStr := ""
            loop 3 {
                index := A_Index + 1
                if (this.InfoTogArrCon[index].Value) {
                    searchStr .= this.InfoTextArrCon[index].Value
                }
                if (A_Index != 3)
                    searchStr .= "⎖"
            }
        }
        this.Data.SearchValue := GetLangStr(searchStr, 2)

        posXStr := this.PosXCon.Value
        posYStr := this.PosYCon.Value
        widthStr := this.WidthCon.Value
        heightStr := this.HeightCon.Value

        this.Data.PosX := IsNumber(posXStr) ? Integer(posXStr) : 0
        this.Data.PosY := IsNumber(posYStr) ? Integer(posYStr) : 0
        this.Data.Width := IsNumber(widthStr) ? Integer(widthStr) : 0
        this.Data.Height := IsNumber(heightStr) ? Integer(heightStr) : 0
        this.Data.NewTitle := GetLangStr(this.NewTitleCon.Text, 2)
        SaveMacroCMDData(this.Data)
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }
}