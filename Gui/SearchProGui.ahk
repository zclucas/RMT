#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk
#Include WinRuleGui.ahk

class SearchProGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.RuleMenu := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.PosAction := () => this.RefreshMouseInfo()
        this.F1Action := (x1, y1, x2, y2) => this.OnF1SetAreaAction(x1, y1, x2, y2)
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.Data := ""
        this.LastIsWin := ""    ;上次是窗口搜索类型
        this.MacroGui := ""

        this.ConfigDLArr := []
        this.WinInfoArr := []
        this.CountTogArr := []
        this.SimilarArr := []
        this.MouseSpeedArr := []
        this.MouseClickArr := []
        this.ResultTogArr := []
        this.CoordTogArr := []
        this.FalseConArr := []
        this.ImageVariArr := []
        this.ColorArr := []
        this.TextArr := []
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
        this.ToggleFunc(true)
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("搜索Pro编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{}", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 35
        PosX := 10
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 25), "F1")
        con.Enabled := false

        PosX += 30
        this.SelectToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{} h{} Left", PosX, PosY, 150, 25), GetLang(
            "左键框选搜索范围"))
        this.SelectToggleCon.OnEvent("Click", (*) => this.OnClickSelectToggle())

        PosX += 150
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 25), "F2")
        con.Enabled := false
        PosX += 30
        MyGui.Add("Text", Format("x{} y{} h{} Center", PosX, PosY + 3, 25), GetLang("截图"))

        PosX += 80
        con := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 25), "F3")
        con.Enabled := false
        PosX += 30
        MyGui.Add("Text", Format("x{} y{} h{} Center", PosX, PosY + 3, 25), GetLang("选取当前颜色"))

        PosX += 120
        Con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY - 2), GetLang("定位取色器"))
        Con.OnEvent("Click", this.OnClickTargeterBtn.Bind(this))
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX + 102, PosY - 2), "?")
        Con.OnEvent("Click", this.OnClickTargeterHelpBtn.Bind(this))

        PosX := 10
        PosY += 35
        this.MousePosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 200, 20), GetLang("屏幕坐标：0,0"))
        PosX += 200
        this.MouseWinPosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 200, 20), GetLang("窗口坐标：0,0"))
        PosX += 200
        this.MouseColorCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 200, 20), GetLang("鼠标颜色：FFFFFF"
        ))
        PosX += 140
        this.MouseColorTipCon := MyGui.Add("Text", Format("x{} y{} w{} Background{}", PosX, PosY, 20, "FF0000"), "")

        PosX := 10
        PosY += 35
        SplitPosY := PosY
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索类型："))
        PosX += 80
        this.SearchTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R6", PosX, PosY - 3, 160), GetLangArr([
            "屏幕图片", "屏幕颜色", "屏幕文本", "窗口图片", "窗口颜色", "窗口文本"]))
        this.SearchTypeCon.OnEvent("Change", (*) => this.OnChangeType())
        this.SearchTypeCon.Value := 1
        Con := MyGui.Add("Button", Format("x{} y{} w30", PosX + 165, PosY - 4), "?")
        Con.OnEvent("Click", this.OnClickTypeHelpBtn.Bind(this))

        PosX := 10
        PosY += 35
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("屏幕规格："))
        PosX += 80
        this.ConfigDLCon := MyGui.Add("DropDownList", Format("x{} y{} w{}", PosX, PosY - 3, 160), [])
        this.ConfigDLCon.OnEvent("Change", (*) => this.OnChangeConfig())
        PosX += 170
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 4, 50, 27), GetLang("编辑"))
        con.OnEvent("Click", this.OnEditScreenRule.Bind(this))
        Con := MyGui.Add("Button", Format("x{} y{} w30 h{}", PosX + 52, PosY - 4, 27), "?")
        Con.OnEvent("Click", this.OnClickWinRuleHelpBtn.Bind(this))

        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标X："))
        PosX += 80
        this.StartPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosX := 180
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标Y："))
        PosX += 80
        this.StartPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标X："))
        PosX += 80
        this.EndPosXCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosX := 180
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标Y："))
        PosX += 80
        this.EndPosYCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索次数："))
        PosX += 80
        this.SearchCountCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.SearchCountCon.OnEvent("LoseFocus", this.OnChangeType.Bind(this))
        PosX := 180
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("每次间隔："))
        this.CountTogArr.Push(con)
        PosX += 80
        con := this.SearchIntervalCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.CountTogArr.Push(con)
        PosY += 35
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("鼠标动作："))
        PosX += 80
        this.MouseActionTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 5, 160),
        GetLangArr(["无动作", "移动至目标", "移动至目标点击"]))
        this.MouseActionTypeCon.Value := 1
        this.MouseActionTypeCon.OnEvent("Change", this.OnChangeType.Bind(this))
        PosY += 35
        PosX := 10
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("移动速度："))
        this.MouseSpeedArr.Push(con)
        PosX += 80
        con := this.SpeedCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 80), "90")
        this.MouseSpeedArr.Push(con)
        PosX := 180
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 120), GetLang("点击次数："))
        this.MouseClickArr.Push(con)
        PosX += 80
        con := this.ClickCountCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 80), "1")
        this.MouseClickArr.Push(con)

        PosX := 10
        PosY += 35
        LeftMacroPosY := PosY
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 170, 20), GetLang("找到后的指令：（可选）"))
        PosX += 180
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 50, 25), GetLang("编辑"))
        btnCon.OnEvent("Click", (*) => this.OnEditFoundMacroBtnClick())
        PosY += 20
        PosX := 10
        this.TrueMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 330, 80), "")

        PosY += 90
        PosX := 10
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 330, 75), GetLang("结果保存"))

        PosY += 20
        PosX := 15
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 50
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("变量名"))
        this.ResultTogArr.Push(con)
        PosX += 130
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("真值"))
        this.ResultTogArr.Push(con)
        PosX += 85
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("假值"))
        this.ResultTogArr.Push(con)

        PosY += 25
        PosX := 20
        this.ResultToggleCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.ResultToggleCon.OnEvent("Click", this.OnChangeType.Bind(this))
        this.ResultSaveNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 30, PosY - 3, 120), [])
        this.ResultTogArr.Push(this.ResultSaveNameCon)
        this.TrueValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 155, PosY - 4, 70), 0)
        this.ResultTogArr.Push(this.TrueValueCon)
        this.FalseValueCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX + 240, PosY - 4, 70), 0)
        this.ResultTogArr.Push(this.FalseValueCon)

        PosY := SplitPosY
        PosX := 360
        con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("窗口信息:"))
        this.WinInfoArr.Push(con)
        PosX += 80
        this.WinInfoCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 3, 150), "")
        this.WinInfoArr.Push(this.WinInfoCon)
        PosX += 160
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 50, 27), GetLang("编辑"))
        btnCon.OnEvent("Click", this.OnClickWinEditBtn.Bind(this))
        this.WinInfoArr.Push(btnCon)

        PosY += 35
        PosX := 360
        Con := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("相似度(%)："))
        this.SimilarArr.Push(Con)
        PosX += 80
        this.SimilarCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 80))
        this.SimilarArr.Push(this.SimilarCon)

        ; Row2: [识别模型] [下拉] + ImageCon 原版位置(570,145)
        PosY += 35
        BasePosY := PosY
        PosX := 360
        this.SearchImageTypeTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("识别模型："))
        this.ImageVariArr.Push(this.SearchImageTypeTipCon)
        PosX += 80
        this.SearchImageTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 3, 80), [
            "OpenCV",
            "RMT识图"])
        this.ImageVariArr.Push(this.SearchImageTypeCon)
        this.ImageCon := MyGui.Add("Picture", Format("x{} y{} w{} h{}", 570, 145, 100, 100), "")
        this.ImageVariArr.Push(this.ImageCon)

        PosY += 35
        PosX := 360
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 7, 70, 30), GetLang("截图"))
        btnCon.OnEvent("Click", (*) => this.OnScreenShotBtnClick())
        this.ScreenshotBtn := btnCon
        this.ImageVariArr.Push(this.ScreenshotBtn)

        PosX += 80
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 7, 80, 30), GetLang("选择图片"))
        btnCon.OnEvent("Click", (*) => this.OnClickSetPicBtn())
        btnCon.Focus()
        this.ImageSelectBtn := btnCon
        this.ImageVariArr.Push(this.ImageSelectBtn)

        PosY := BasePosY + 70
        PosX := 360
        this.SearchImagePathTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("图片路径："))
        this.ImageVariArr.Push(this.SearchImagePathTipCon)
        PosX += 80
        this.ImagePathCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 5, 250), [])
        this.ImageVariArr.Push(this.ImagePathCon)

        ; === 颜色搜索区域（与图片重叠） ===
        PosY := BasePosY
        PosX := 360
        this.ColorLabelCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索颜色："))
        this.ColorArr.Push(this.ColorLabelCon)
        PosX += 80
        this.HexColorCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center R5", PosX, PosY - 3, 120), [])
        this.ColorArr.Push(this.HexColorCon)
        PosX += 130
        this.HexColorTipCon := MyGui.Add("Text", Format("x{} y{} w{} Background{}", PosX, PosY, 20, "FF0000"), "")
        this.ColorArr.Push(this.HexColorTipCon)

        ; === 文本搜索区域（与图片重叠） ===
        PosY := BasePosY
        PosX := 360
        this.TextTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索文本："))
        this.TextArr.Push(this.TextTipCon)
        PosX += 80
        this.TextCon := MyGui.Add("ComboBox", Format("x{} y{} w{} Center R5", PosX, PosY - 3, 120), [])
        this.TextArr.Push(this.TextCon)

        PosY := BasePosY + 35
        PosX := 360
        this.OCRLabelCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("识别模型："))
        this.TextArr.Push(this.OCRLabelCon)
        PosX += 80
        this.OCRTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 3, 120), GetLangArr([
            "中文",
            "英文"]))
        this.TextArr.Push(this.OCRTypeCon)

        PosY := Max(BasePosY + 98, LeftMacroPosY)

        PosX := 360
        con := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 170, 20), GetLang("未找到后的指令：（可选）"))
        this.FalseConArr.Push(con)
        PosX += 180
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 50, 25), GetLang("编辑"))
        btnCon.OnEvent("Click", (*) => this.OnEditUnFoundMacroBtnClick())
        this.FalseConArr.Push(btnCon)
        PosY += 20
        PosX := 360
        this.FalseMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 330, 80), "")
        this.FalseConArr.Push(this.FalseMacroCon)

        PosY += 90
        PosX := 360
        MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, 330, 75), GetLang("目标点保存"))

        PosY += 20
        PosX := 365
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("开关"))
        PosX += 45
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("坐标X变量名"))
        this.CoordTogArr.Push(con)
        PosX += 130
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("坐标Y变量名"))
        this.CoordTogArr.Push(con)

        PosY += 25
        PosX := 370
        this.CoordToogleCon := MyGui.Add("Checkbox", Format("x{} y{} w{}", PosX, PosY, 30))
        this.CoordToogleCon.OnEvent("Click", this.OnChangeType.Bind(this))
        this.CoordXNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 35, PosY - 3, 120), [])
        this.CoordTogArr.Push(this.CoordXNameCon)
        this.CoordYNameCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX + 170, PosY - 3, 120), [])
        this.CoordTogArr.Push(this.CoordYNameCon)

        PosY += 35
        PosX := 300
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 700, 600))
    }

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索Pro")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr()
        if (!this.CheckIfDataValid())
            return
        this.RefreshConfigDLArr()
        this.SearchTypeCon.Value := this.Data.SearchType
        this.SimilarCon.Value := this.Data.Similar
        this.OCRTypeCon.Value := this.Data.OCRType
        this.WinInfoCon.Value := this.Data.WinInfo
        this.SearchImageTypeCon.Value := this.Data.SearchImageType
        this.ImagePathCon.Delete()
        this.ImagePathCon.Add(this.DLVariableArr)
        this.ImagePathCon.Text := this.Data.SearchImagePath
        this.ImageCon.GetPos(&imagePosX, &imagePosY)
        this.ImageCon.Value := this.Data.SearchImagePath
        this.ImageCon.Move(imagePosX, imagePosY, 100, 100)
        this.HexColorCon.Delete()
        this.HexColorCon.Add(this.DLVariableArr)
        this.HexColorCon.Text := this.Data.SearchColor
        this.TextCon.Delete()
        this.TextCon.Add(this.DLVariableArr)
        this.TextCon.Text := this.Data.SearchText
        this.StartPosXCon.Delete()
        this.StartPosXCon.Add(this.DLVariableArr)
        this.StartPosYCon.Delete()
        this.StartPosYCon.Add(this.DLVariableArr)
        this.EndPosXCon.Delete()
        this.EndPosXCon.Add(this.DLVariableArr)
        this.EndPosYCon.Delete()
        this.EndPosYCon.Add(this.DLVariableArr)
        this.StartPosXCon.Text := this.Data.StartPosX
        this.StartPosYCon.Text := this.Data.StartPosY
        this.EndPosXCon.Text := this.Data.EndPosX
        this.EndPosYCon.Text := this.Data.EndPosY
        this.SearchCountCon.Delete()
        this.SearchCountCon.Add([GetLang("无限")])
        this.SearchCountCon.Text := this.Data.SearchCount == -1 ? GetLang("无限") : this.Data.SearchCount
        this.SearchIntervalCon.Value := this.Data.SearchInterval
        this.SpeedCon.Value := this.Data.Speed
        this.ClickCountCon.Value := this.Data.ClickCount
        this.TrueMacroCon.Value := GetLangMacro(this.Data.TrueMacro, 1)
        this.FalseMacroCon.Value := GetLangMacro(this.Data.FalseMacro, 1)
        this.ResultToggleCon.Value := this.Data.ResultToggle
        this.ResultSaveNameCon.Delete()
        this.ResultSaveNameCon.Add(this.DLVariableArr)
        this.ResultSaveNameCon.Text := this.Data.ResultSaveName
        this.TrueValueCon.Value := this.Data.TrueValue
        this.FalseValueCon.Value := this.Data.FalseValue
        this.CoordToogleCon.Value := this.Data.CoordToogle
        this.CoordXNameCon.Delete()
        this.CoordXNameCon.Add(this.DLVariableArr)
        this.CoordXNameCon.Text := this.Data.CoordXName
        this.CoordYNameCon.Delete()
        this.CoordYNameCon.Add(this.DLVariableArr)
        this.CoordYNameCon.Text := this.Data.CoordYName

        curType := this.SearchTypeCon.Value
        isWin := curType == 4 || curType == 5 || curType == 6
        this.LastIsWin := isWin
        MouseDLArr := isWin ? GetLangArr(["无动作", "后台鼠标至目标点击", "后台鼠标至目标双击"]) : GetLangArr(["无动作", "移动至目标", "移动至目标点击"])
        SetDLConValue(this.MouseActionTypeCon, MouseDLArr, GetLang("无动作"))
        this.MouseActionTypeCon.Value := this.Data.MouseActionType
        this.OnChangeType()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    OnClickWinEditBtn(*) {
        MyFrontInfoGui.HideAction := () => this.ToggleFunc(true)
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            MyFrontInfoGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            MyFrontInfoGui.OwnerHwnd := ""
        }
        MyFrontInfoGui.ShowGui(this.WinInfoCon)
    }

    RefreshConfigDLArr() {
        Arr := []
        Arr.Push(this.Data.ConfigName)
        loop this.Data.ConfigArr.Length {
            CurConfigData := this.Data.ConfigArr[A_Index]
            if (ObjHasOwnProp(CurConfigData, "ConfigName"))
                Arr.Push(CurConfigData.ConfigName)
        }
        this.ConfigDLArr := Arr

        this.ConfigDLCon.Delete()
        this.ConfigDLCon.Add(this.ConfigDLArr)
        this.ConfigDLCon.Text := this.Data.ConfigName
    }

    OnEditScreenRule(con, *) {
        if (this.RuleMenu == "") {
            this.ContextMenu := Menu()
            this.ContextMenu.Add(GetLang("修改"), (*) => this.OnRuleMenuHandler(GetLang("修改")))
            this.ContextMenu.Add(GetLang("增加"), (*) => this.OnRuleMenuHandler(GetLang("增加")))
            this.ContextMenu.Add(GetLang("删除"), (*) => this.OnRuleMenuHandler(GetLang("删除")))
        }
        con.GetPos(&x, &y)
        this.ContextMenu.Show(x, y)
    }

    OnRuleMenuHandler(Str) {
        if (Str == GetLang("修改")) {
            if (!ObjHasOwnProp(this, "WinRuleGui")) {
                this.WinRuleGui := WinRuleGui()
            }
            SureAction(width, height, remark) {
                ConfigName := Format("{}*{}", width, height)
                if (remark != "")
                    ConfigName := Format("{}*{}_{}", width, height, remark)
                if (ConfigName == this.Data.ConfigName)
                    return
                loop this.ConfigDLArr.Length {
                    if (this.ConfigDLArr[A_Index] == ConfigName) {
                        MsgBox(Format("{} 配置已存在，修改失败", ConfigName))
                        return
                    }
                }

                this.Data.ConfigName := ConfigName
                this.RefreshConfigDLArr()
                saveStr := JSON.stringify(this.Data, 0)
                IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
                MsgBox(GetLang("修改成功"))
            }
            this.WinRuleGui.SureAction := SureAction
            if (MySoftData.IsModalSubGui && this.Gui != "") {
                this.WinRuleGui.OwnerHwnd := this.Gui.Hwnd
            }
            else {
                this.WinRuleGui.OwnerHwnd := ""
            }
            this.WinRuleGui.ShowGui()
        }
        else if (Str == GetLang("增加"))
            this.OnAddConfig()
        else if (Str == GetLang("删除"))
            this.OnRemoveConfig()
    }

    OnAddConfig() {
        if (!ObjHasOwnProp(this, "WinRuleGui")) {
            this.WinRuleGui := WinRuleGui()
        }
        SureAction(width, height, remark) {
            ConfigName := Format("{}*{}", width, height)
            if (remark != "")
                ConfigName := Format("{}*{}_{}", width, height, remark)
            loop this.ConfigDLArr.Length {
                if (this.ConfigDLArr[A_Index] == ConfigName) {
                    MsgBox(Format("{} 配置已存在，无法重复添加", ConfigName))
                    return
                }
            }

            LastConfig := Object()
            LastConfig.ConfigName := this.Data.ConfigName
            LastConfig.SearchType := this.SearchTypeCon.Value
            LastConfig.SearchColor := this.HexColorCon.Text
            LastConfig.SearchText := this.TextCon.Text
            LastConfig.SearchImagePath := this.Data.SearchImagePath
            LastConfig.Similar := this.SimilarCon.Value
            LastConfig.OCRType := this.OCRTypeCon.Value
            LastConfig.SearchImageType := this.SearchImageTypeCon.Value
            LastConfig.StartPosX := this.StartPosXCon.Text
            LastConfig.StartPosY := this.StartPosYCon.Text
            LastConfig.EndPosX := this.EndPosXCon.Text
            LastConfig.EndPosY := this.EndPosYCon.Text
            LastConfig.SearchCount := this.SearchCountCon.Text == GetLang("无限") ? -1 : this.SearchCountCon.Text
            LastConfig.SearchInterval := this.SearchIntervalCon.Value
            LastConfig.MouseActionType := this.MouseActionTypeCon.Value
            LastConfig.Speed := this.SpeedCon.Value
            LastConfig.ClickCount := this.ClickCountCon.Value
            this.Data.ConfigArr.Push(LastConfig)

            this.Data.ConfigName := ConfigName
            this.RefreshConfigDLArr()
            saveStr := JSON.stringify(this.Data, 0)
            IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
            MsgBox(Format("{} 配置添加成功", ConfigName))
        }
        this.WinRuleGui.SureAction := SureAction
        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.WinRuleGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.WinRuleGui.OwnerHwnd := ""
        }
        this.WinRuleGui.ShowGui()
    }

    OnRemoveConfig() {
        if (this.ConfigDLArr.Length <= 1) {
            MsgBox("最后选项不可删除！！！")
            return
        }

        result := MsgBox(Format(GetLang("是否删除 {} 配置"), this.ConfigDLCon.Text), GetLang("提示"), 1)
        if (result == "Cancel")
            return

        ConfigData := this.Data.ConfigArr[1]
        this.Data.ConfigArr.RemoveAt(1)
        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.SearchType := ConfigData.SearchType
        this.Data.SearchColor := ConfigData.SearchColor
        this.Data.SearchText := ConfigData.SearchText
        this.Data.SearchImagePath := ConfigData.SearchImagePath
        this.Data.Similar := ConfigData.Similar
        this.Data.OCRType := ConfigData.OCRType
        this.Data.SearchImageType := ConfigData.SearchImageType
        this.Data.StartPosX := ConfigData.StartPosX
        this.Data.StartPosY := ConfigData.StartPosY
        this.Data.EndPosX := ConfigData.EndPosX
        this.Data.EndPosY := ConfigData.EndPosY
        this.Data.SearchCount := ConfigData.SearchCount
        this.Data.SearchInterval := ConfigData.SearchInterval
        this.Data.MouseActionType := ConfigData.MouseActionType
        this.Data.Speed := ConfigData.Speed
        this.Data.ClickCount := ConfigData.ClickCount
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)

        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    OnChangeConfig() {
        LastConfig := Object()
        LastConfig.ConfigName := this.Data.ConfigName
        LastConfig.SearchType := this.SearchTypeCon.Value
        LastConfig.SearchColor := this.HexColorCon.Text
        LastConfig.SearchText := this.TextCon.Text
        LastConfig.SearchImagePath := this.Data.SearchImagePath
        LastConfig.Similar := this.SimilarCon.Value
        LastConfig.OCRType := this.OCRTypeCon.Value
        LastConfig.SearchImageType := this.SearchImageTypeCon.Value
        LastConfig.StartPosX := this.StartPosXCon.Text
        LastConfig.StartPosY := this.StartPosYCon.Text
        LastConfig.EndPosX := this.EndPosXCon.Text
        LastConfig.EndPosY := this.EndPosYCon.Text
        LastConfig.SearchCount := this.SearchCountCon.Text == GetLang("无限") ? -1 : this.SearchCountCon.Text
        LastConfig.SearchInterval := this.SearchIntervalCon.Value
        LastConfig.MouseActionType := this.MouseActionTypeCon.Value
        LastConfig.Speed := this.SpeedCon.Value
        LastConfig.ClickCount := this.ClickCountCon.Value
        this.Data.ConfigArr.Push(LastConfig)

        ConfigData := ""
        loop this.ConfigDLArr.Length {
            if (this.ConfigDLCon.Text == this.Data.ConfigArr[A_Index].ConfigName) {
                ConfigData := this.Data.ConfigArr.RemoveAt(A_Index)
                break
            }
        }

        this.Data.ConfigName := ConfigData.ConfigName
        this.Data.SearchType := ConfigData.SearchType
        this.Data.SearchColor := ConfigData.SearchColor
        this.Data.SearchText := ConfigData.SearchText
        this.Data.SearchImagePath := ConfigData.SearchImagePath
        this.Data.Similar := ConfigData.Similar
        this.Data.OCRType := ConfigData.OCRType
        this.Data.SearchImageType := ConfigData.SearchImageType
        this.Data.StartPosX := ConfigData.StartPosX
        this.Data.StartPosY := ConfigData.StartPosY
        this.Data.EndPosX := ConfigData.EndPosX
        this.Data.EndPosY := ConfigData.EndPosY
        this.Data.SearchCount := ConfigData.SearchCount
        this.Data.SearchInterval := ConfigData.SearchInterval
        this.Data.MouseActionType := ConfigData.MouseActionType
        this.Data.Speed := ConfigData.Speed
        this.Data.ClickCount := ConfigData.ClickCount
        saveStr := JSON.stringify(this.Data, 0)
        IniWrite(saveStr, SearchProFile, IniSection, this.Data.SerialStr)
        CMDStr := this.GetCommandStr()
        this.Init(CMDStr)
    }

    CheckIfDataValid() {
        if (!ObjHasOwnProp(this.Data, "SearchImagePath")) {
            MsgBox(GetLang("这条指令不完整，请删除"))
            return false
        }

        if (this.Data.SearchImagePath != "" && !FileExist(this.Data.SearchImagePath)) {
            MsgBox(Format(GetLang("{} 图片不存在`n如果是软件位置发生改变，请点击若梦兔-配置管理-配置校准"), this.Data.SearchImagePath))
            return false
        }
        return true
    }

    CheckIfValid() {
        curType := this.SearchTypeCon.Value
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6

        this.Data.SearchImagePath := this.ImagePathCon.Text
        if (IsNumber(this.StartPosXCon.Text) && IsNumber(this.StartPosYCon.Text) && IsNumber(this.EndPosXCon.Text
        ) && IsNumber(this.EndPosYCon.Text)) {
            if (Number(this.StartPosXCon.Text) > Number(this.EndPosXCon.Text) || Number(this.StartPosYCon.Text) >
            Number(
                this.EndPosYCon.Text)) {
                MsgBox(GetLang("起始坐标不能大于终止坐标"))
                return false
            }
        }

        if (this.SearchCountCon.Text == GetLang("无限")) {

        }
        else if (!IsNumber(this.SearchCountCon.Text) || Number(this.SearchCountCon.Text) <= 0) {
            MsgBox(GetLang("搜索次数请输入大于0的数字"))
            return false
        }

        if (isImage && this.Data.SearchImagePath == "") {
            MsgBox(GetLang("请设置搜索图片"))
            return false
        }

        if (isImage) {
            if (IsNumber(this.StartPosXCon.Text) && IsNumber(this.StartPosYCon.Text)
            && IsNumber(this.EndPosXCon.Text) && IsNumber(this.EndPosYCon.Text)) {
                searchWidth := this.EndPosXCon.Text - this.StartPosXCon.Text
                searchHeight := this.EndPosYCon.Text - this.StartPosYCon.Text
                size := GetImageSize(this.Data.SearchImagePath)
                if (size[1] > searchWidth || size[2] > searchHeight) {
                    MsgBox(GetLang("搜索范围不能小于图片大小"))
                    return false
                }
            }
        }

        if (isText) {
            if (this.StartPosXCon.Text == this.EndPosXCon.Text) ||
            this.StartPosYCon.Text == Number(this.EndPosYCon.Text) {
                MsgBox(GetLang("搜索文本时：搜索范围中起始坐标不能和终止坐标相同"))
                return false
            }
        }

        if (isWin && this.WinInfoCon.Value == "") {
            MsgBox(GetLang("目标窗口信息不能为空"))
            return false
        }

        if (this.ResultToggleCon.Value) {
            if (!CheckVarNameIfValid(this.ResultSaveNameCon.Text))
                return false
        }

        if (this.MouseActionTypeCon.Value != 1 && !isWin) {
            if (!IsNumber(this.SpeedCon.Value) || this.SpeedCon.Value < 0 || this.SpeedCon.Value > 100) {
                MsgBox(GetLang("移动速度请输入0~100的数字"))
                return false
            }
        }

        return true
    }

    ToggleFunc(state) {
        MacroAction := (*) => this.TriggerMacro()
        if (state) {
            SetTimer this.PosAction, 100
            Hotkey("!l", MacroAction, "On")
            Hotkey("F1", (*) => this.OnF1(), "On")
            Hotkey("F2", (*) => this.OnScreenShotBtnClick(), "On")
            Hotkey("F3", (*) => this.SureColor(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
            Hotkey("F2", (*) => this.OnScreenShotBtnClick(), "Off")
            Hotkey("F3", (*) => this.SureColor(), "Off")
        }
    }

    RefreshMouseInfo() {
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos &mouseX, &mouseY
            this.MousePosCon.Value := Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY)
            PosArr := GetCurWinPos()
            this.MouseWinPosCon.Value := Format("{}{},{}", GetLang("窗口坐标："), PosArr[1], PosArr[2])
            CoordMode("Pixel", "Screen")
            Color := PixelGetColor(mouseX, mouseY, "Slow")
            ColorText := StrReplace(Color, "0x", "")
            this.MouseColorCon.Value := Format("{}{}", GetLang("鼠标颜色："), ColorText)
            this.MouseColorTipCon.Opt(Format("+Background0x{}", ColorText))
            this.MouseColorTipCon.Redraw()
        }
    }

    OnSureTarget(PosX, PosY, Color) {
        ColorText := StrReplace(Color, "0x", "")
        this.HexColorCon.Text := ColorText
        this.HexColor := ColorText
        this.HexColorTipCon.Visible := true
        this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Text))
        this.HexColorTipCon.Redraw()
        this.OnSetSearchArea(PosX, PosY, PosX, PosY)
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}",
            GetLang("1.左键拖拽改变位置"),
            GetLang("2.上下左右方向键微调位置"),
            GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnClickTypeHelpBtn(*) {
        str1 := GetLang("屏幕搜索：在屏幕搜索目标")
        str2 := GetLang("窗口搜索：在符合目标的窗口搜索目标(支持后台，最小化)")
        str3 := GetLang("tip1：图片搜索：推荐32*32px，截取目标特征即可，不要包含会变化的背景")
        str4 := GetLang("tip2：文本搜索：支持正则表达式，推荐32*32px以上和多文本，单字符识别不准")
        str5 := GetLang("tip3：SC截图后如果调整大小，搜索范围需要手动选取")
        str6 := GetLang("tip4：窗口搜索时：搜索范围需要手动选取")

        str := Format("{}`n{}`n{}`n{}`n{}`n{}", str1, str2, str3, str4, str5, str6)
        MsgBox(str, GetLang("搜索类型说明"))
    }

    OnClickWinRuleHelpBtn(*) {
        str1 := GetLang("此功能用于不同分辨率使用相同指令")
        str2 := GetLang("新设备和原设备分辨率不同时，可以增加屏幕规格选项，然后设置新的搜索目标和搜索范围进行适配")
        str3 := GetLang("tip1：个人使用请忽略这个功能选项")
        str4 := GetLang("tip2：导入他人配置时，建议新增屏幕规格后重新设置搜索目标、搜索范围")

        str := Format("{}`n{}`n{}`n{}", str1, str2, str3, str4)
        MsgBox(str, GetLang("屏幕规格功能说明"))
    }

    OnClickSureBtn() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSearchData()
        action := this.SureBtnAction
        action(this.GetCommandStr())
        this.ToggleFunc(false)

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnGuiClose() {
        this.ToggleFunc(false)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnClickSetPicBtn() {
        curPath := this.ImagePathCon.Text
        path := FileSelect(1, curPath, GetLang("选择图片"), "PNG Files (*.png)")
        if (path != "") {
            SplitPath path, &name, &dir, &ext, &name_no_ext, &drive
            newPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" name
            if (path != newPath) {
                if (FileExist(newPath)) {
                    imageSerial := GetNextImageSerial()
                    newPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
                }
                FileCopy(path, newPath)
                path := newPath
            }

            this.ImageCon.GetPos(&imagePosX, &imagePosY)
            this.ImageCon.Value := path
            this.ImageCon.Move(imagePosX, imagePosY, 100, 100)
            this.Data.SearchImagePath := path
            this.ImagePathCon.Text := path
        }
    }

    OnScreenShotBtnClick() {
        if (MySoftData.ScreenShotTypeCtrl.Value == 1) {
            SetClipboard("")  ; 清空剪贴板
            Run("ms-screenclip:")
            SetTimer(this.CheckClipboardAction, 500)  ; 每 500 毫秒检查一次剪贴板
            TogGetSelectArea(true, this.OnGetArea.Bind(this))
        }
        else if (MySoftData.ScreenShotTypeCtrl.Value == 3) {
            RunScreenCapture(this.CheckClipboardAction)
            TogGetSelectArea(true, this.OnGetArea.Bind(this))
        }
        else {
            TogSelectArea(true, this.OnScreenShotGetArea.Bind(this))
        }
    }

    CheckClipboard() {
        ; 如果剪贴板中有图像
        if DllCall("IsClipboardFormatAvailable", "uint", 8)  ; 8 是 CF_BITMAP 格式
        {
            imageSerial := GetNextImageSerial()
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
            SaveClipToBitmap(filePath)

            this.ImageCon.GetPos(&imagePosX, &imagePosY)
            this.ImageCon.Value := filePath
            this.ImageCon.Move(imagePosX, imagePosY, 100, 100)
            this.Data.SearchImagePath := filePath
            this.ImagePathCon.Text := filePath
            ; 停止监听
            SetTimer(, 0)
        }
    }

    OnGetArea(x1, y1, x2, y2) {
        AreaX1 := Max(0, x1 - 20)
        AreaX2 := Min(A_ScreenWidth, x2 + 20)
        AreaY1 := Max(0, y1 - 20)
        AreaY2 := Min(A_ScreenHeight, y2 + 20)
        this.OnSetSearchArea(AreaX1, AreaY1, AreaX2, AreaY2)
    }

    OnScreenShotGetArea(x1, y1, x2, y2) {
        imageSerial := GetNextImageSerial()
        filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" imageSerial ".png"
        ScreenShot(x1, y1, x2, y2, filePath)

        this.ImageCon.GetPos(&imagePosX, &imagePosY)
        this.ImageCon.Value := filePath
        this.ImageCon.Move(imagePosX, imagePosY, 100, 100)
        this.Data.SearchImagePath := filePath
        this.ImagePathCon.Text := filePath

        this.OnGetArea(x1, y1, x2, y2)
    }

    OnSureFoundMacroBtnClick(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.TrueMacroCon.Value := CommandStr
    }

    OnSureUnFoundMacroBtnClick(CommandStr) {
        CommandStr := GetLangMacro(CommandStr, 1)
        this.FalseMacroCon.Value := CommandStr
    }

    OnEditFoundMacroBtnClick() {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            this.MacroGui.SureFocusCon := this.MousePosCon

            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.MacroGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnSureFoundMacroBtnClick(command)
        this.MacroGui.ShowGui(this.TrueMacroCon.Value, false)
    }

    OnEditUnFoundMacroBtnClick() {
        if (this.MacroGui == "") {
            this.MacroGui := MacroEditGui()
            this.MacroGui.DLVariableArr := this.DLVariableArr
            this.MacroGui.SureFocusCon := this.MousePosCon

            ParentTile := StrReplace(this.Gui.Title, GetLang("编辑器"), "")
            this.MacroGui.ParentTile := ParentTile "-"
        }

        if (MySoftData.IsModalSubGui && this.Gui != "") {
            this.MacroGui.OwnerHwnd := this.Gui.Hwnd
        }
        else {
            this.MacroGui.OwnerHwnd := ""
        }

        this.MacroGui.SureBtnAction := (command) => this.OnSureUnFoundMacroBtnClick(command)
        this.MacroGui.ShowGui(this.FalseMacroCon.Value, false)
    }

    OnChangeType(*) {
        curType := this.SearchTypeCon.Value
        isImage := curType == 1 || curType == 4
        isColor := curType == 2 || curType == 5
        isText := curType == 3 || curType == 6
        isWin := curType == 4 || curType == 5 || curType == 6
        isInfinite := this.SearchCountCon.Text == GetLang("无限")
        showColorTip := isColor && RegExMatch(this.HexColorCon.Text, "^([0-9A-Fa-f]{6})$")

        this.SetConArrState(this.ImageVariArr, false, isImage)

        this.SetConArrState(this.ColorArr, false, isColor)
        this.HexColorTipCon.Visible := showColorTip
        if (showColorTip) {
            this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Text))
            this.HexColorTipCon.Redraw()
        }

        this.SetConArrState(this.TextArr, false, isText)
        this.MousePosCon.Focus()

        this.SetConArrState(this.SimilarArr, false, !isText)
        this.SetConArrState(this.WinInfoArr, false, isWin)
        this.SetConArrState(this.FalseConArr, true, !isInfinite)

        if (!this.LastIsWin && isWin) {
            SetDLConValue(this.MouseActionTypeCon, GetLangArr(["无动作", "后台鼠标至目标点击", "后台鼠标至目标双击"]), GetLang("无动作"))
        }
        if (this.LastIsWin && !isWin) {
            SetDLConValue(this.MouseActionTypeCon, GetLangArr(["无动作", "移动至目标", "移动至目标点击"]), GetLang("无动作"))
        }

        CountValue := this.SearchCountCon.Text == GetLang("无限") ? -1 : this.SearchCountCon.Text
        isCount := IsNumber(CountValue) && (CountValue == -1 || CountValue > 1)
        this.SetConArrState(this.CountTogArr, false, isCount)

        isMouseSpeed := this.MouseActionTypeCon.Value != 1 && !isWin
        this.SetConArrState(this.MouseSpeedArr, false, isMouseSpeed)

        isMouseClick := this.MouseActionTypeCon.Value == 3 && !isWin
        this.SetConArrState(this.MouseClickArr, false, isMouseClick)

        isSaveResult := this.ResultToggleCon.Value
        this.SetConArrState(this.ResultTogArr, true, isSaveResult)

        isCoord := this.CoordToogleCon.Value
        this.SetConArrState(this.CoordTogArr, true, isCoord)

        this.LastIsWin := isWin
    }

    SetConArrState(ConArr, isEnabled, state) {
        for Value in ConArr {
            if (isEnabled)
                Value.Enabled := state
            else
                Value.Visible := state
        }
    }

    TriggerMacro() {
        valid := this.CheckIfValid()
        if (!valid)
            return
        this.SaveSearchData()
        OnTriggerSepcialItemMacro(this.GetCommandStr())
    }

    OnClickSelectToggle() {
        state := this.SelectToggleCon.Value
        if (state == 1)
            TogSelectArea(true, this.F1Action)
        else
            TogSelectArea(false)
    }

    OnF1() {
        this.SelectToggleCon.Value := 1
        TogSelectArea(true, this.F1Action)
    }

    OnF1SetAreaAction(x1, y1, x2, y2) {
        this.SelectToggleCon.Value := 0
        curType := this.SearchTypeCon.Value
        isWin := curType == 4 || curType == 5 || curType == 6
        Point1 := isWin ? GetWinPos(x1, y1) : [x1, y1]
        Point2 := isWin ? GetWinPos(x2, y2) : [x2, y2]

        this.StartPosXCon.Text := Point1[1]
        this.StartPosYCon.Text := Point1[2]
        this.EndPosXCon.Text := Point2[1]
        this.EndPosYCon.Text := Point2[2]
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.SelectToggleCon.Value := 0
        this.StartPosXCon.Text := x1
        this.StartPosYCon.Text := y1
        this.EndPosXCon.Text := x2
        this.EndPosYCon.Text := y2
    }

    SureColor() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY

        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        this.HexColorCon.Text := ColorText
        this.HexColor := ColorText
        this.HexColorTipCon.Visible := true
        this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Text))
        this.HexColorTipCon.Redraw()
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    SaveSearchData() {
        data := this.Data
        data.SearchImagePath := this.ImagePathCon.Text
        data.Similar := this.SimilarCon.Value
        data.OCRType := this.OCRTypeCon.Value
        data.SearchImageType := this.SearchImageTypeCon.Value
        data.SearchType := this.SearchTypeCon.Value
        data.WinInfo := this.WinInfoCon.Value
        data.SearchColor := this.HexColorCon.Text
        data.SearchText := this.TextCon.Text
        data.StartPosX := this.StartPosXCon.Text
        data.StartPosY := this.StartPosYCon.Text
        data.EndPosX := this.EndPosXCon.Text
        data.EndPosY := this.EndPosYCon.Text
        data.SearchCount := this.SearchCountCon.Text == GetLang("无限") ? -1 : this.SearchCountCon.Text
        data.SearchInterval := this.SearchIntervalCon.Value
        data.MouseActionType := this.MouseActionTypeCon.Value
        data.ClickCount := this.ClickCountCon.Value
        data.Speed := this.SpeedCon.Value
        data.TrueMacro := GetLangMacro(this.TrueMacroCon.Value, 2)
        data.FalseMacro := GetLangMacro(this.FalseMacroCon.Value, 2)
        data.ResultToggle := this.ResultToggleCon.Value
        data.ResultSaveName := GetVarName(this.ResultSaveNameCon.Text)
        data.TrueValue := this.TrueValueCon.Value
        data.FalseValue := this.FalseValueCon.Value
        data.CoordToogle := this.CoordToogleCon.Value
        data.CoordXName := this.CoordXNameCon.Text
        data.CoordYName := this.CoordYNameCon.Text

        if (data.ResultToggle)
            MySoftData.GlobalVariMap[data.ResultSaveName] := true

        if (data.CoordToogle) {
            MySoftData.GlobalVariMap[data.CoordXName] := true
            MySoftData.GlobalVariMap[data.CoordYName] := true
        }

        SaveMacroCMDData(data)
    }
}
