#Requires AutoHotkey v2.0

class WindowManageGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.RemarkCon := ""
        this.ActionTypeCon := ""
        this.SearchTypeCon := ""
        this.SearchValueCon := ""
        this.PosXCon := ""
        this.PosYCon := ""
        this.WidthCon := ""
        this.HeightCon := ""
        this.NewTitleCon := ""
        this.VariCon := ""
        this.VariTipCon := ""

        this.PosRelateArrCon := []
        this.SizeRelateArrCon := []
        this.TitleRelateArrCon := []

        this.Data := ""
    }

    ShowGui(cmd) {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        this.Init(cmd)
        this.OnActionChange()
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("窗口管理")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)

        actionIndex := this.Data.ActionType > 0 ? this.Data.ActionType : 1
        searchIndex := this.Data.SearchType > 0 ? this.Data.SearchType : 1

        this.ActionTypeCon.Value := actionIndex
        this.SearchTypeCon.Value := searchIndex
        this.SearchValueCon.Value := this.Data.SearchValue
        this.PosXCon.Value := this.Data.PosX
        this.PosYCon.Value := this.Data.PosY
        this.WidthCon.Value := this.Data.Width
        this.HeightCon.Value := this.Data.Height
        this.NewTitleCon.Value := this.Data.NewTitle

        DLVariableArr := GetGuiVarArr(2)
        this.VariCon.Delete()
        this.VariCon.Add(DLVariableArr)
        this.VariCon.Value := 1
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("窗口管理编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
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

        PosX := 320
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("查找方式："))
        PosX += 80
        this.SearchTypeCon := MyGui.Add(
            "DropDownList",
            Format("x{} y{} w200 R3", PosX, PosY - 3),
            [GetLang("标题"), GetLang("类名"), GetLang("进程名")]
        )

        PosY += 32
        PosX := 10
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("查找值："))
        PosX += 80
        this.SearchValueCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 280), "")

        PosX += 285
        btnCon := MyGui.Add("Button", Format("x{} y{}", PosX, PosY - 5), GetLang("选取"))
        btnCon.OnEvent("Click", (*) => this.OnClickPickBtn())

        PosY += 30
        PosX := 10
        this.VariTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("变量"))

        PosX += 50
        this.VariCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 100), [])

        PosX += 110
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 100, 25), GetLang("追加变量"))
        btnCon.OnEvent("Click", (*) => this.OnClickAddVarBtn())

        SplitPosY := PosY + 35

        PosX := 10
        PosY := SplitPosY
        this.PosRelateArrCon := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("坐标X："))
        this.PosRelateArrCon.Push(con)
        PosX += 60
        this.PosXCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 3, 80), "0")
        this.PosRelateArrCon.Push(this.PosXCon)
        PosX += 90
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("坐标Y："))
        this.PosRelateArrCon.Push(con)
        PosX += 60
        this.PosYCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 3, 80), "0")
        this.PosRelateArrCon.Push(this.PosYCon)

        PosX := 10
        PosY := SplitPosY
        this.SizeRelateArrCon := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("宽度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 60
        this.WidthCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 3, 80), "0")
        this.SizeRelateArrCon.Push(this.WidthCon)
        PosX += 90
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("高度："))
        this.SizeRelateArrCon.Push(con)
        PosX += 60
        this.HeightCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 3, 80), "0")
        this.SizeRelateArrCon.Push(this.HeightCon)

        PosX := 10
        PosY := SplitPosY
        this.TitleRelateArrCon := []
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 70), GetLang("新标题："))
        this.TitleRelateArrCon.Push(con)
        PosX += 75
        this.NewTitleCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 280), "")
        this.TitleRelateArrCon.Push(this.NewTitleCon)

        PosY := SplitPosY + 45
        PosX := 200
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.Gui.Hide())
        MyGui.Show(Format("w{} h{}", 520, 290))
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

    OnClickPickBtn() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY, &winId
        try {
            searchType := this.SearchTypeCon.Value
            if (searchType == 1) {
                this.SearchValueCon.Value := WinGetTitle(winId)
            }
            else if (searchType == 2) {
                this.SearchValueCon.Value := WinGetClass(winId)
            }
            else if (searchType == 3) {
                WinPID := WinGetPID("ahk_id " winId)
                this.SearchValueCon.Value := ProcessGetName(WinPID)
            }
        }
    }

    OnClickAddVarBtn() {
        if (this.VariCon.Text == "") {
            MsgBox(GetLang("请选择变量"), "", "Owner" this.Gui.Hwnd)
            return
        }
        this.SearchValueCon.Value .= "{" this.VariCon.Text "}"
    }

    OnClickSureBtn() {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        CommandStr := this.GetCommandStr()
        this.SureBtnAction.Call(CommandStr)
        this.Gui.Hide()
    }

    CheckIfValid() {
        if (this.SearchValueCon.Value == "") {
            MsgBox(GetLang("查找值不能为空！"), "", "Owner" this.Gui.Hwnd)
            return false
        }

        actionType := this.ActionTypeCon.Value
        if (actionType == 6) {
            if (!IsNumber(this.PosXCon.Value) || !IsNumber(this.PosYCon.Value)) {
                MsgBox(GetLang("坐标请输入数字！"), "", "Owner" this.Gui.Hwnd)
                return false
            }
        }

        if (actionType == 7) {
            if (!IsNumber(this.WidthCon.Value) || !IsNumber(this.HeightCon.Value)) {
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
        this.Data.SearchType := this.SearchTypeCon.Value
        this.Data.SearchValue := GetLangStr(this.SearchValueCon.Value, 2)
        this.Data.PosX := Integer(this.PosXCon.Value)
        this.Data.PosY := Integer(this.PosYCon.Value)
        this.Data.Width := Integer(this.WidthCon.Value)
        this.Data.Height := Integer(this.HeightCon.Value)
        this.Data.NewTitle := GetLangStr(this.NewTitleCon.Value, 2)
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
