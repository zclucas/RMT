#Requires AutoHotkey v2.0

class ColorPanelGui {
    __new() {
        this.Gui := ""
        this.ColorCon := ""
        this.CoordCon := ""
        this.ColorConMap := Map()
        this.OverlayCon := ""

        this.ColorValue := "F0F0F0"
        this.CoordX := 1920
        this.CoordY := 1080

        this.RowColorNum := 11
        this.ColColorNum := 15
        this.GuiWidth := 160
        this.GuiHeight := 150

        this.SureAction := ""
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.RefreshCoord()
        this.RefreshMapImage()
    }

    AddGui() {
        this.Gui := Gui("+AlwaysOnTop +ToolWindow -Caption -Resize -DPIScale")
        this.Gui.Title := "RMT-Target"
        this.Gui.SetFont("S13 W550 Q2", MySoftData.FontType)
        this.Gui.MarginX := 0
        this.Gui.MarginY := 0
        this.Gui.BackColor := "EEAA99" ; 这个颜色必须设置，但具体是什么颜色不重要

        StartPosX := 5
        StartPosY := 5
        loop this.RowColorNum {
            RowValue := A_Index
            loop this.ColColorNum {
                ColValue := A_Index
                if (RowValue == 6 && ColValue == 8)
                    continue
                PosX := StartPosX + (ColValue - 1) * 10
                PosY := StartPosY + (RowValue - 1) * 10
                Con := this.Gui.Add("Text", Format("x{} y{} w{} h{} Background{}", PosX, PosY, 10, 10, "FF0000"), "")
                this.ColorConMap.Set(Format("{}-{}", ColValue, RowValue), Con)
            }
        }
        CenterBoxPosX := 73
        CenterBoxPosY := 53
        Con := this.Gui.Add("Text", Format("x{} y{} w{} h{} Background{}", CenterBoxPosX, CenterBoxPosY, 14, 14,
            "FFFFFF"), "")
        this.ColorConMap.Set(Format("{}-{}", 0, 0), Con)

        CenterPosX := 75
        CenterPosY := 55
        Con := this.Gui.Add("Text", Format("x{} y{} w{} h{} Background{}", CenterPosX, CenterPosY, 10, 10,
            "FFFFFF"), "")
        this.ColorConMap.Set(Format("{}-{}", 8, 6), Con)

        this.ColorCon := this.Gui.Add("Text", Format("x{} y{} w{} h{} Background{}", 5, 120, 25, 25, "FF0000"), "")
        this.CoordCon := this.Gui.Add("Text", Format("x{} y{} w{}", 35, 120, 95, "FF0000"), "1920,1080")
        Con := this.Gui.Add("Button", Format("x{} y{} w{} h{}", 130, 120, 25, 25), "X")
        Con.OnEvent("Click", this.OnClose.Bind(this))

        this.OverlayCon := this.Gui.Add("Text", "x0 y0 w" this.GuiWidth " h" this.GuiHeight " BackgroundTrans")
        this.OverlayCon.OnEvent("Click", this.GuiDrag.Bind(this))
        this.OverlayCon.OnEvent("DoubleClick", this.GuiDoubleClick.Bind(this))
        x := A_ScreenWidth - this.GuiWidth
        y := A_ScreenHeight - this.GuiWidth
        this.Gui.Show(Format("x{} y0 w{} h{}", x, this.GuiWidth, this.GuiHeight))
    }

    ; 拖动函数
    GuiDrag(*) {
        PostMessage(0xA1, 2, , , this.Gui)
    }

    ;双击确定关闭
    GuiDoubleClick(*) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        this.Gui.Hide()
        MyTargetGui.Gui.Hide()
        if (this.SureAction == "")
            return
        action := this.SureAction
        colorStr := Format("{:06X}", this.ColorValue)
        action(this.CoordX, this.CoordY, colorStr)
    }

    OnClose(*) {
        this.Gui.Hide()
        MyTargetGui.Gui.Hide()
    }

    OnEnterUp(*) {
        if (this.Gui == "")
            return
        style := WinGetStyle(this.Gui.Hwnd)
        isVisible := (style & 0x10000000)  ; 0x10000000 = WS_VISIBLE
        if (!isVisible)
            return

        this.Gui.Hide()
        MyTargetGui.Gui.Hide()
        if (this.SureAction == "")
            return
        action := this.SureAction
        colorStr := Format("{:06X}", this.ColorValue)
        action(this.CoordX, this.CoordY,colorStr)
    }

    RefreshCoord() {
        MyTargetGui.Gui.GetPos(&x, &y, &w, &h)

        this.CoordX := x - 1
        this.CoordY := y - 1
        this.CoordCon.Text := Format("{},{}", this.CoordX, this.CoordY)
    }

    RefreshMapImage() {
        MyTargetGui.Gui.GetPos(&x, &y, &w, &h)
        MyTargetGui.Gui.Move(-1000, -1000)
        ColorValueMap := GetPixelColorMap(x - 1, y - 1, this.RowColorNum, this.ColColorNum)
        MyTargetGui.Gui.Move(x, y)

        CoordMode("Pixel", "Screen")

        loop this.RowColorNum {
            RowValue := A_Index
            loop this.ColColorNum {
                ColValue := A_Index
                Key := Format("{}-{}", ColValue, RowValue)
                Con := this.ColorConMap[Key]
                ColorValue := ColorValueMap[Key]
                Con.Opt("Background" ColorValue)
                Con.Redraw()
            }
        }

        Key := Format("{}-{}", Integer((this.ColColorNum + 1) / 2), Integer((this.RowColorNum + 1) / 2))
        this.ColorValue := ColorValueMap[Key]
        this.ColorCon.Opt("Background" this.ColorValue)
        this.ColorCon.Redraw()

        CenterBoxKey := Format("{}-{}", 0, 0)
        CenterBoxCon := this.ColorConMap[CenterBoxKey]
        ColorValue := this.GetInvertedColor(this.ColorValue)
        CenterBoxCon.Opt("Background" ColorValue)
        CenterBoxCon.Redraw()
    }

    GetInvertedColor(color) {
        ; 去除可能的前缀（如0x）
        if (SubStr(color, 1, 2) = "0x") {
            color := SubStr(color, 3)
        }

        ; 确保颜色值是6位十六进制
        if (StrLen(color) = 6) {
            ; 将十六进制转换为RGB分量
            red := Integer("0x" SubStr(color, 1, 2))
            green := Integer("0x" SubStr(color, 3, 2))
            blue := Integer("0x" SubStr(color, 5, 2))

            ; 计算反色
            invertedRed := 255 - red
            invertedGreen := 255 - green
            invertedBlue := 255 - blue

            ; 将RGB分量转换回十六进制
            invertedColor := Format("0x{:02X}{:02X}{:02X}", invertedRed, invertedGreen, invertedBlue)

            return invertedColor
        }
        return "0xFFFFFF"
    }

    ; 静态便捷方法：弹出颜色选择器，返回选中的颜色（#RRGGBB格式），取消返回空字符串
    static PickColor(defaultColor := "") {
        picker := ColorPanelGui()
        if (defaultColor != "" && RegExMatch(defaultColor, "^#?([0-9A-Fa-f]{6})$", &m))
            picker.ColorValue := Integer("0x" m[1])
        result := ""
        picker.SureAction := (x, y, color) => result := "#" color
        ; 确保目标窗口已创建并显示，否则 RefreshCoord/RefreshMapImage 会报错
        if (MyTargetGui.Gui == "")
            MyTargetGui.AddGui()
        MyTargetGui.Gui.Show()
        picker.ShowGui()
        ; 等待用户选择或关闭（最多等待60秒）
        loop 600 {
            if (result != "")
                return result
            Sleep(100)
        }
        return ""
    }
}
