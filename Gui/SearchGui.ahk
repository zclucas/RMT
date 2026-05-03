#Requires AutoHotkey v2.0
#Include MacroEditGui.ahk

class SearchGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.SureBtnAction := ""
        this.OwnerHwnd := ""
        this.RemarkCon := ""
        this.PosAction := () => this.RefreshMouseInfo()
        this.SetAreaAction := (x1, y1, x2, y2) => this.OnSetSearchArea(x1, y1, x2, y2)
        this.CheckClipboardAction := () => this.CheckClipboard()
        this.Data := ""
        this.MacroGui := ""
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
        MyGui := Gui(, this.ParentTile GetLang("搜索编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("快捷方式："))
        PosX += 80
        con := MyGui.Add("Hotkey", Format("x{} y{} w{} Center", PosX, PosY - 3, 70), "!l")
        con.Enabled := false

        PosX += 90
        btnCon := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 80), GetLang("执行指令"))
        btnCon.OnEvent("Click", (*) => this.TriggerMacro())

        PosX += 90
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 50), GetLang("备注："))
        PosX += 50
        this.RemarkCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY - 5, 150), "")

        PosY += 30
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
        PosY += 30
        this.MousePosCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 230, 20), GetLang("屏幕坐标：0,0"))
        PosX += 330
        this.MouseColorCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 150, 20), GetLang("鼠标颜色：FFFFFF"
        ))
        PosX += 150
        this.MouseColorTipCon := MyGui.Add("Text", Format("x{} y{} w{} Background{}", PosX, PosY, 20, "FF0000"), "")

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 100), GetLang("搜索范围："))
        PosX := 330
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索类型："))
        PosX += 80
        this.SearchTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} h{}", PosX, PosY - 3, 80, 100), GetLangArr([
            "屏幕图片", "屏幕颜色", "屏幕文本"]))
        this.SearchTypeCon.OnEvent("Change", (*) => this.OnChangeSearchType())
        this.SearchTypeCon.Value := 1
        PosX := 495
        this.ImageCon := MyGui.Add("Picture", Format("x{} y{} w{} h{}", PosX, PosY - 10, 80, 80), "")

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标X："))
        PosX += 80
        this.StartPosXCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50))
        PosX := 155
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("起始坐标Y："))
        PosX += 80
        this.StartPosYCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50))
        PosX := 330
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 2, PosY - 5, 80, 30), GetLang("截图"))
        btnCon.OnEvent("Click", (*) => this.OnImageShotBtnClick())
        this.ColorTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索颜色："))
        this.HexColorCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 120), "FFFFFF")
        PosX += 130
        this.HexColorTipCon := MyGui.Add("Text", Format("x{} y{} w{} Background{}", PosX, PosY, 20, "FF0000"), "")
        PosX := 330
        this.TextTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索文本："))
        this.TextArr.Push(this.TextTipCon)
        PosX += 80
        this.TextCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 3, 120), GetLang("检索文本"))
        this.TextArr.Push(this.TextCon)

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标X："))
        PosX += 80
        this.EndPosXCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50))
        PosX := 155
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("终止坐标Y："))
        PosX += 80
        this.EndPosYCon := MyGui.Add("Edit", Format("x{} y{} w{} Center", PosX, PosY - 5, 50))
        
        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 75), GetLang("鼠标动作："))
        PosX += 80
        this.MouseActionTypeCon := MyGui.Add("DropDownList", Format("x{} y{} w{} Center", PosX, PosY - 5, 155),
        GetLangArr(["无动作",
            "移动至目标", "移动至目标点击1次", "移动至目标点击2次"]))
        this.MouseActionTypeCon.Value := 2
        PosX := 330
        this.ImageShotBtn := btnCon
        this.ImageTipCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 80), GetLang("搜索图片："))
        PosX += 80
        this.ImagePathCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 5, 100), [])
        PosX += 100
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 7, 80, 30), GetLang("选择图片"))
        btnCon.OnEvent("Click", (*) => this.OnClickSetPicBtn())
        btnCon.Focus()
        this.ImageSelectBtn := btnCon

        PosY += 30
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 170, 25), GetLang("找到后的指令：（可选）"))
        PosX += 180
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 80, 25), GetLang("编辑指令"))
        btnCon.OnEvent("Click", (*) => this.OnEditFoundMacroBtnClick())
        PosX := 330
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 170, 25), GetLang("未找到后的指令：（可选）"))
        PosX += 180
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY - 5, 80, 25), GetLang("编辑指令"))
        btnCon.OnEvent("Click", (*) => this.OnEditUnFoundMacroBtnClick())

        PosY += 25
        PosX := 10
        this.TrueMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 280, 80), "")
        PosX := 330
        this.FalseMacroCon := MyGui.Add("Edit", Format("x{} y{} w{} h{}", PosX, PosY, 280, 80), "")

        PosY += 85
        PosX := 270
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())
        MyGui.OnEvent("Close", (*) => this.OnGuiClose())
        MyGui.Show(Format("w{} h{}", 640, 420))
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

    Init(cmd) {
        cmdArr := cmd != "" ? StrSplit(cmd, "_") : []
        this.SerialStr := cmdArr.Length >= 1 ? cmdArr[1] : GetCMDSerialStr("搜索")
        this.RemarkCon.Value := cmdArr.Length >= 2 ? cmdArr[2] : ""
        this.Data := GetMacroCMDData(this.SerialStr)
        this.DLVariableArr := GetGuiVarArr(1)
        if (!this.CheckIfDataValid())
            return

        this.SearchTypeCon.Value := this.Data.SearchType
        this.ImagePathCon.Delete()
        this.ImagePathCon.Add(GetGuiVarArr(2))
        this.ImagePathCon.Text := this.Data.SearchImagePath
        this.ImageCon.GetPos(&imagePosX, &imagePosY)
        this.ImageCon.Value := this.Data.SearchImagePath
        this.ImageCon.Move(imagePosX, imagePosY, 80, 80)
        this.HexColorCon.Value := this.Data.SearchColor
        this.TextCon.Value := this.Data.SearchText
        this.StartPosXCon.Value := this.Data.StartPosX
        this.StartPosYCon.Value := this.Data.StartPosY
        this.EndPosXCon.Value := this.Data.EndPosX
        this.EndPosYCon.Value := this.Data.EndPosY
        this.MouseActionTypeCon.Value := this.Data.MouseActionType
        this.TrueMacroCon.Value := GetLangMacro(this.Data.TrueMacro, 1)
        this.FalseMacroCon.Value := GetLangMacro(this.Data.FalseMacro, 1)
        this.OnChangeSearchType()
    }

    GetCommandStr() {
        textOnly := RegExReplace(this.Data.SerialStr, "\d+")
        numbersOnly := RegExReplace(this.Data.SerialStr, "\D+")
        CommandStr := Format("{}{}", GetLang(textOnly), numbersOnly)
        CommandStr := CorrectRemark(CommandStr, this.RemarkCon.Value)
        return CommandStr
    }

    CheckIfDataValid() {
        if (!ObjHasOwnProp(this.Data, "SearchImagePath")) {
            MsgBox(GetLang("这条指令不完整，请删除"))
            return false
        }

        if (this.Data.SearchImagePath != "" && !FileExist(this.Data.SearchImagePath)) {
            ; MsgBox(Format(GetLang("{} 图片不存在`n如果是软件位置发生改变，请点击若梦兔-配置管理-配置校准"), this.Data.SearchImagePath))
            MsgBox(Format("{} {}`n{}", this.Data.SearchImagePath, GetLang("图片不存在"), GetLang(
                "如果是软件位置发生改变，请点击若梦兔-配置管理-配置校准")))
            return false
        }
        return true
    }

    CheckIfValid() {
        if (!IsNumber(this.StartPosXCon.Value) || !IsNumber(this.StartPosYCon.Value) || !IsNumber(this.EndPosXCon.Value
        ) || !IsNumber(this.EndPosYCon.Value)) {
            MsgBox(GetLang("坐标中请输入数字"))
            return false
        }

        if (Number(this.StartPosXCon.Value) > Number(this.EndPosXCon.Value) || Number(this.StartPosYCon.Value) >
        Number(
            this.EndPosYCon.Value)) {
            MsgBox(GetLang("起始坐标不能大于终止坐标"))
            return false
        }

        ; if (!IsNumber(this.SearchCountCon.Value) || Number(this.SearchCountCon.Value) <= 0) {
        ;     MsgBox("搜索次数请输入大于0的数字")
        ;     return false
        ; }

        if (this.SearchTypeCon.Value == 1 && this.Data.SearchImagePath == "") {
            MsgBox(GetLang("请设置搜索图片"))
            return false
        }

        if (this.SearchTypeCon.Value == 1) {
            searchWidth := this.EndPosXCon.Value - this.StartPosXCon.Value
            searchHeight := this.EndPosYCon.Value - this.StartPosYCon.Value
            size := GetImageSize(this.Data.SearchImagePath)
            if (size[1] > searchWidth || size[2] > searchHeight) {
                MsgBox(GetLang("搜索范围不能小于图片大小"))
                return false
            }
        }

        if (this.SearchTypeCon.Value == 2 && !RegExMatch(this.HexColorCon.Value, "^([0-9A-Fa-f]{6})$")) {
            MsgBox(GetLang("请输入正确的颜色值"))
            return false
        }

        if (this.SearchTypeCon.Value == 3) {
            if (Number(this.StartPosXCon.Value) == Number(this.EndPosXCon.Value) ||
            Number(this.StartPosYCon.Value) == Number(this.EndPosYCon.Value)) {
                MsgBox(GetLang("搜索文本时：搜索范围中起始坐标不能和终止坐标相同"))
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
            Hotkey("F2", (*) => this.OnImageShotBtnClick(), "On")
            Hotkey("F3", (*) => this.SureColor(), "On")
        }
        else {
            SetTimer this.PosAction, 0
            Hotkey("!l", MacroAction, "Off")
            Hotkey("F1", (*) => this.OnF1(), "Off")
            Hotkey("F2", (*) => this.OnImageShotBtnClick(), "Off")
            Hotkey("F3", (*) => this.SureColor(), "Off")
        }
    }

    RefreshMouseInfo() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY
        this.MousePosCon.Value := Format("{}{},{}", GetLang("屏幕坐标："), mouseX, mouseY)

        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        this.MouseColorCon.Value := Format("{}{}", GetLang("鼠标颜色："), ColorText)
        this.MouseColorTipCon.Opt(Format("+Background0x{}", ColorText))
        this.MouseColorTipCon.Redraw()
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

    OnClickSetPicBtn() {
        path := FileSelect(1, , GetLang("选择图片"), "PNG Files (*.png)")
        this.ImagePathCon.Text := path
        this.ImageCon.Value := path
        this.Data.SearchImagePath := path
    }

    OnImageShotBtnClick() {
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
            ; 获取当前日期和时间，用于生成唯一的文件名
            CurrentDateTime := FormatTime(, "HHmmss")
            filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" CurrentDateTime ".png"
            SaveClipToBitmap(filePath)
            this.ImagePathCon.Text := filePath
            this.ImageCon.Value := filePath
            this.Data.SearchImagePath := filePath
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

    OnSureTarget(PosX, PosY, Color) {
        ColorText := StrReplace(Color, "0x", "")
        this.HexColorCon.Value := ColorText
        this.HexColor := ColorText
        this.HexColorTipCon.Visible := true
        this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Value))
        this.HexColorTipCon.Redraw()
        this.OnSetSearchArea(PosX, PosY, PosX, PosY)
    }

    OnClickTargeterBtn(*) {
        MyTargetGui.SureAction := this.OnSureTarget.Bind(this)
        MyTargetGui.ShowGui()
    }

    OnClickTargeterHelpBtn(*) {
        str := Format("{}`n{}`n{}", GetLang("1.左键拖拽改变位置"), GetLang("2.上下左右方向键微调位置"), GetLang("3.左键双击或回车键关闭取色器，同时确定点位信息"
        ))
        MsgBox(str, GetLang("定位取色器操作说明"))
    }

    OnScreenShotGetArea(x1, y1, x2, y2) {
        CurrentDateTime := FormatTime(, "HHmmss")
        filePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\ScreenShot\" CurrentDateTime ".png"

        ScreenShot(x1, y1, x2, y2, filePath)
        this.ImagePathCon.Text := filePath
        this.ImageCon.Value := filePath
        this.Data.SearchImagePath := filePath

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

    OnChangeSearchType() {
        isImage := this.SearchTypeCon.Value == 1
        isColor := this.SearchTypeCon.Value == 2
        isText := this.SearchTypeCon.Value == 3

        ; showImageTip := isImage && this.Data.SearchImagePath == ""
        showColorTip := isColor && RegExMatch(this.HexColorCon.Value, "^([0-9A-Fa-f]{6})$")

        this.ImageTipCon.Visible := isImage
        this.ImagePathCon.Visible := isImage
        this.ImageSelectBtn.Visible := isImage
        this.ImageShotBtn.Visible := isImage
        this.ImageCon.Visible := isImage

        this.HexColorCon.Visible := isColor
        this.ColorTipCon.Visible := isColor
        this.HexColorTipCon.Visible := showColorTip
        if (showColorTip) {
            this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Value))
            this.HexColorTipCon.Redraw()
        }

        loop this.TextArr.Length {
            this.TextArr[A_Index].Visible := isText
        }
        this.MousePosCon.Focus()
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
            ; TogSelectArea(true, this.SetAreaAction)
            TogGetSelectArea(true, this.SetAreaAction)
        else
            ; TogSelectArea(false)
            TogGetSelectArea(false)
    }

    OnF1() {
        this.SelectToggleCon.Value := 1
        ; TogSelectArea(true, this.SetAreaAction)
        TogGetSelectArea(true, this.F1Action)
    }

    OnSetSearchArea(x1, y1, x2, y2) {
        this.SelectToggleCon.Value := 0
        this.StartPosXCon.Value := x1
        this.StartPosYCon.Value := y1
        this.EndPosXCon.Value := x2
        this.EndPosYCon.Value := y2
    }

    SureColor() {
        CoordMode("Mouse", "Screen")
        MouseGetPos &mouseX, &mouseY

        CoordMode("Pixel", "Screen")
        Color := PixelGetColor(mouseX, mouseY, "Slow")
        ColorText := StrReplace(Color, "0x", "")
        this.HexColorCon.Value := ColorText
        this.HexColor := ColorText
        this.HexColorTipCon.Visible := true
        this.HexColorTipCon.Opt(Format("+Background0x{}", this.HexColorCon.Value))
        this.HexColorTipCon.Redraw()
        this.OnSetSearchArea(mouseX, mouseY, mouseX, mouseY)
    }

    SaveSearchData() {
        data := this.Data
        data.SearchImagePath := this.ImagePathCon.Text
        data.SearchType := this.SearchTypeCon.Value
        data.SearchColor := this.HexColorCon.Value
        data.SearchText := this.TextCon.Value
        data.StartPosX := this.StartPosXCon.Value
        data.StartPosY := this.StartPosYCon.Value
        data.EndPosX := this.EndPosXCon.Value
        data.EndPosY := this.EndPosYCon.Value
        data.MouseActionType := this.MouseActionTypeCon.Value
        data.TrueMacro := GetLangMacro(this.TrueMacroCon.Value, 2)
        data.FalseMacro := GetLangMacro(this.FalseMacroCon.Value, 2)
        SaveMacroCMDData(data)
    }
}
