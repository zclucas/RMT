#Requires AutoHotkey v2.0

class MenuWheelModuleStyleGui {
    __new() {
        this.Gui := ""
        this.NormalFillCon := ""
        this.NormalStrokeCon := ""
        this.HoverFillCon := ""
        this.HoverStrokeCon := ""
        this.SelectedFillCon := ""
        this.SelectedStrokeCon := ""
    }

    ShowGui(moduleIndex) {
        if (this.Gui != "") {
            this.Gui.Destroy()
            this.Gui := ""
        }
        this.moduleIndex := moduleIndex
        this.AddGui()
        this.Init()
    }

    Init() {
        tableItem := MySoftData.TableInfo[3]
        arrayOffset := (this.moduleIndex - 1) * 8

        defNormalFill := "#FFFCFCFC"
        defNormalStroke := "#FFC6DFFC"
        defHoverFill := "#FFFDE8E8"
        defHoverStroke := "#FFE81123"
        defSelectedFill := "#FF0078D7"
        defSelectedStroke := "#FFFFFFFF"

        if (tableItem.HasProp("WheelNormalFillArr") && tableItem.WheelNormalFillArr.Length > arrayOffset)
            defNormalFill := tableItem.WheelNormalFillArr[arrayOffset + 1]
        if (tableItem.HasProp("WheelNormalStrokeArr") && tableItem.WheelNormalStrokeArr.Length > arrayOffset)
            defNormalStroke := tableItem.WheelNormalStrokeArr[arrayOffset + 1]
        if (tableItem.HasProp("WheelHoverFillArr") && tableItem.WheelHoverFillArr.Length > arrayOffset)
            defHoverFill := tableItem.WheelHoverFillArr[arrayOffset + 1]
        if (tableItem.HasProp("WheelHoverStrokeArr") && tableItem.WheelHoverStrokeArr.Length > arrayOffset)
            defHoverStroke := tableItem.WheelHoverStrokeArr[arrayOffset + 1]
        if (tableItem.HasProp("WheelSelectedFillArr") && tableItem.WheelSelectedFillArr.Length > arrayOffset)
            defSelectedFill := tableItem.WheelSelectedFillArr[arrayOffset + 1]
        if (tableItem.HasProp("WheelSelectedStrokeArr") && tableItem.WheelSelectedStrokeArr.Length > arrayOffset)
            defSelectedStroke := tableItem.WheelSelectedStrokeArr[arrayOffset + 1]

        this.NormalFillCon.Value := defNormalFill
        this.NormalStrokeCon.Value := defNormalStroke
        this.HoverFillCon.Value := defHoverFill
        this.HoverStrokeCon.Value := defHoverStroke
        this.SelectedFillCon.Value := defSelectedFill
        this.SelectedStrokeCon.Value := defSelectedStroke
    }

    AddGui() {
        MyGui := Gui(, GetLang("模块轮盘样式 - 模块") this.moduleIndex)
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 5
        PosY := 10
        MyGui.Add("GroupBox", Format("x{} y{} w420 h200", PosX, PosY), GetLang("普通状态"))

        PosX := 20
        PosY += 25
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("背景色："))
        PosX += 70
        this.NormalFillCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 220
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("边框色："))
        PosX += 70
        this.NormalStrokeCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 5
        PosY += 40
        MyGui.Add("GroupBox", Format("x{} y{} w420 h200", PosX, PosY), GetLang("悬停状态"))

        PosX := 20
        PosY += 25
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("背景色："))
        PosX += 70
        this.HoverFillCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 220
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("边框色："))
        PosX += 70
        this.HoverStrokeCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 5
        PosY += 40
        MyGui.Add("GroupBox", Format("x{} y{} w420 h200", PosX, PosY), GetLang("选中状态"))

        PosX := 20
        PosY += 25
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("背景色："))
        PosX += 70
        this.SelectedFillCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 220
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("边框色："))
        PosX += 70
        this.SelectedStrokeCon := MyGui.Add("Edit", Format("x{} y{} w140 h25", PosX, PosY - 3), "")

        PosX := 80
        PosY += 45
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("恢复默认"))
        con.OnEvent("Click", (*) => this.OnRevertBtnClick())

        PosX := 220
        con := MyGui.Add("Button", Format("x{} y{} w100 h40", PosX, PosY), GetLang("确定"))
        con.OnEvent("Click", (*) => this.OnSureBtnClick())

        MyGui.Show(Format("w{} h{}", 435, 360))
    }

    CheckIfValid() {
        return true
    }

    OnRevertBtnClick() {
        this.NormalFillCon.Value := "#FFFCFCFC"
        this.NormalStrokeCon.Value := "#FFC6DFFC"
        this.HoverFillCon.Value := "#FFFDE8E8"
        this.HoverStrokeCon.Value := "#FFE81123"
        this.SelectedFillCon.Value := "#FF0078D7"
        this.SelectedStrokeCon.Value := "#FFFFFFFF"
    }

    OnSureBtnClick() {
        if (!this.CheckIfValid())
            return
        this.SaveData()
        this.Gui.Hide()
    }

    SaveData() {
        tableItem := MySoftData.TableInfo[3]
        arrayOffset := (this.moduleIndex - 1) * 8

        InitArray(tableItem, "WheelNormalFillArr")
        InitArray(tableItem, "WheelNormalStrokeArr")
        InitArray(tableItem, "WheelHoverFillArr")
        InitArray(tableItem, "WheelHoverStrokeArr")
        InitArray(tableItem, "WheelSelectedFillArr")
        InitArray(tableItem, "WheelSelectedStrokeArr")

        loop 8 {
            idx := arrayOffset + A_Index
            tableItem.WheelNormalFillArr[idx] := this.NormalFillCon.Value
            tableItem.WheelNormalStrokeArr[idx] := this.NormalStrokeCon.Value
            tableItem.WheelHoverFillArr[idx] := this.HoverFillCon.Value
            tableItem.WheelHoverStrokeArr[idx] := this.HoverStrokeCon.Value
            tableItem.WheelSelectedFillArr[idx] := this.SelectedFillCon.Value
            tableItem.WheelSelectedStrokeArr[idx] := this.SelectedStrokeCon.Value
        }
    }
}
