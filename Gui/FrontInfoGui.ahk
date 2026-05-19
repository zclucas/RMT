#Requires AutoHotkey v2.0

class FrontInfoGui {
    __new() {
        this.Gui := ""
        this.OwnerHwnd := ""
        this.InfoAction := () => this.RefreshMouseInfo()
        this.HideAction := ""
        this.SureAction := ""
        this.winInfoCon := ""
        this.isFront := false   ;前台不支持句柄模式
        this.InfoTogCon := ""
        this.TopTogCon := ""
        this.InfoTogArrCon := []
        this.InfoTextArrCon := []
    }

    ShowGui(winInfoCon, isFront := false) {
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

        this.isFront := isFront
        this.Init(winInfoCon)
        this.ToggleFunc(true)
    }

    Init(winInfoCon) {
        this.winInfoCon := winInfoCon
        this.TopTogCon.Value := true
        infoStr := winInfoCon.Value
        if (InStr(infoStr, "❖")) {
            idStr := StrReplace(infoStr, "❖", "")
            infoArr := ["", idStr, "", "", ""]
        }
        else {
            if (infoStr != "")
                infoArr := StrSplit(infoStr, "⎖")
            if (infoStr == "" || infoArr.Length != 3)
                infoArr := ["", "", ""]

            infoArr.InsertAt(1, "")
            infoArr.InsertAt(1, "")
        }

        loop 5 {
            this.InfoTogArrCon[A_Index].Value := infoArr[A_Index] != ""
            this.InfoTextArrCon[A_Index].Value := infoArr[A_Index]
        }

        DLVariableArr := GetGuiVarArr(4)
        this.VariCon.Delete()
        this.VariCon.Add(DLVariableArr)
        this.VariCon.Value := 1

        loop 5 {
            if (this.InfoTogArrCon[A_Index].Value) {
                this.OnTogClick(A_Index)
                break
            }
        }
    }

    AddGui() {
        MyGui := Gui(, GetLang("前台信息编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        PosX := 10
        PosY := 10

        PosX := 10
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口置顶"))
        con.OnEvent("Click", this.OnTopTogClick.Bind(this))
        this.TopTogCon := con

        PosX := 160
        con := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 30), "F1")
        con.Enabled := false
        PosX += 30
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("确定信息"))

        PosX := 400
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX, PosY - 4), "?")
        Con.OnEvent("Click", this.OnClickTypeHelpBtn.Bind(this))

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("当前鼠标下窗口信息："))

        PosY += 25
        PosX := 10
        this.CurWinInfoCon := MyGui.Add("Text", Format("x{} y{} w800 h90", PosX, PosY))

        PosY += 95
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("运行时鼠标下窗口"))
        con.OnEvent("Click", this.OnTogClick.Bind(this, 1))
        this.InfoTogArrCon.Push(con)
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        con.Visible := false
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("句柄ID"))
        con.OnEvent("Click", this.OnTogClick.Bind(this, 2))
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
        con.OnEvent("Click", this.OnTogClick.Bind(this, 3))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("窗口类"))
        con.OnEvent("Click", this.OnTogClick.Bind(this, 4))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosY += 35
        PosX := 20
        con := MyGui.Add("Checkbox", Format("x{} y{}", PosX, PosY), GetLang("进程名"))
        con.OnEvent("Click", this.OnTogClick.Bind(this, 5))
        this.InfoTogArrCon.Push(con)
        PosX := 95
        con := MyGui.Add("Edit", Format("x{} y{} w360", PosX, PosY - 3), "")
        this.InfoTextArrCon.Push(con)

        PosX := 200
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())
        MyGui.OnEvent("Close", this.OnClose.Bind(this))
        MyGui.Show(Format("w{} h{}", 500, 430))
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

    OnClose(*) {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        if (this.HideAction != "") {
            action := this.HideAction
            action()
            this.HideAction := ""
        }
    }

    ToggleFunc(state) {
        if (state) {
            SetTimer this.InfoAction, 100
            Hotkey("F1", (*) => this.OnF1(), "On")
        }
        else {
            SetTimer this.InfoAction, 0
            Hotkey("F1", (*) => this.OnF1(), "Off")
        }
    }

    CheckIfValid() {
        if (this.InfoTextArrCon[2].Value && this.InfoTextArrCon[2].Value == "") {
            MsgBox(GetLang("勾选句柄ID后，句柄ID内容不能为空"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        if (this.InfoTextArrCon[3].Value && this.InfoTextArrCon[3].Value == "") {
            MsgBox(GetLang("勾选标题后，标题内容不能为空"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        if (this.InfoTextArrCon[4].Value && this.InfoTextArrCon[4].Value == "") {
            MsgBox(GetLang("勾选窗口类后，窗口类内容不能为空"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        if (this.InfoTextArrCon[5].Value && this.InfoTextArrCon[5].Value == "") {
            MsgBox(GetLang("勾选进程名后，进程名内容不能为空"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        if (this.isFront && this.InfoTogArrCon[2].Value) {
            if (InStr(this.InfoTextArrCon[2].Value, "{")) {
                MsgBox(GetLang("前台窗口信息句柄ID不能使用变量"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        return true
    }

    GetInfoStr() {
        if (this.InfoTogArrCon[2].Value)
            return "❖" this.InfoTextArrCon[2].Value

        Str := ""
        loop 5 {
            if (A_Index == 1 || A_Index == 2)
                continue
            if (this.InfoTogArrCon[A_Index].Value) {
                Str .= this.InfoTextArrCon[A_Index].Value
            }
            if (A_Index != 5)
                Str .= "⎖"
        }
        if (Str == "⎖⎖")
            return ""
        return Str
    }

    OnSureBtnClick() {
        isValid := this.CheckIfValid()
        if (!isValid)
            return

        this.winInfoCon.Value := this.GetInfoStr()
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
        this.OnClose()
        if (this.SureAction != "") {
            action := this.SureAction
            action()
            this.SureAction := ""
        }
    }

    OnTopTogClick(*) {
        if (this.TopTogCon.Value) {
            this.Gui.Opt("+AlwaysOnTop")
        }
        else {
            this.Gui.Opt("-AlwaysOnTop")
        }
    }

    OnTogClick(index, *) {
        isOn := this.InfoTogArrCon[index].Value
        if (!isOn)
            return

        switch (index) {
            case 1:
            {
                loop this.InfoTogArrCon.Length {
                    this.InfoTogArrCon[A_Index].Value := false
                }
                this.InfoTogArrCon[1].Value := true
                this.InfoTogArrCon[2].Value := true
                this.InfoTextArrCon[2].Value := "{" GetLang("句柄ID") "}"
                this.InfoTextArrCon[2].Enabled := false
                loop this.VarConArr.Length {
                    this.VarConArr[A_Index].Enabled := false
                }
                this.InfoTextArrCon[3].Enabled := false
                this.InfoTextArrCon[4].Enabled := false
                this.InfoTextArrCon[5].Enabled := false
            }
            case 2:
            {
                loop this.InfoTogArrCon.Length {
                    this.InfoTogArrCon[A_Index].Value := false
                }
                this.InfoTogArrCon[2].Value := true
                this.InfoTextArrCon[2].Enabled := true
                loop this.VarConArr.Length {
                    this.VarConArr[A_Index].Enabled := true
                }
                this.InfoTextArrCon[3].Enabled := false
                this.InfoTextArrCon[4].Enabled := false
                this.InfoTextArrCon[5].Enabled := false
            }
            default:
            {
                this.InfoTogArrCon[1].Value := false
                this.InfoTogArrCon[2].Value := false
                this.InfoTextArrCon[2].Enabled := false
                loop this.VarConArr.Length {
                    this.VarConArr[A_Index].Enabled := false
                }
                this.InfoTextArrCon[3].Enabled := true
                this.InfoTextArrCon[4].Enabled := true
                this.InfoTextArrCon[5].Enabled := true
            }
        }
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

            this.InfoTogArrCon[3].Value := true
            this.InfoTogArrCon[4].Value := true
            this.InfoTogArrCon[5].Value := true
            this.InfoTogArrCon[2].Value := false
            this.InfoTextArrCon[2].Enabled := false
            loop this.VarConArr.Length {
                con := this.VarConArr[A_Index]
                con.Enabled := false
            }

            this.InfoTextArrCon[2].Value := winId
            this.InfoTextArrCon[3].Value := title
            this.InfoTextArrCon[4].Value := className
            this.InfoTextArrCon[5].Value := process
            this.OnTogClick(3)
        }
    }

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("优先级：句柄ID > 标题 + 窗口类 + 进程名")
        str2 := GetLang("句柄ID支持多ID任意适配")

        str := Format("{}`n{}", str1, str2)
        MsgBox(str, GetLang("窗口信息说明"), "Owner" this.Gui.Hwnd)
    }

    OnClickAddVarValueBtn() {
        Symbol := this.InfoTextArrCon[2].Text == "" ? "" : "|"
        VarStr := "{" this.VariCon.Text "}"
        if (this.VariCon.Text == "") {
            MsgBox("请勿添加空字符变量", "", "Owner" this.Gui.Hwnd)
            return
        }
        if (InStr(this.InfoTextArrCon[2].Text, VarStr)) {
            MsgBox("请勿重复添加变量", "", "Owner" this.Gui.Hwnd)
            return
        }

        this.InfoTextArrCon[2].Text .= Symbol VarStr
    }
}
