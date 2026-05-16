#Requires AutoHotkey v2.0

class MenuWheelGui {
    __new() {
        this.MenuIndex := 1
    }

    ShowGui(MenuIndex) {
        PreviousActiveWindow := WinExist("A")
        this.ShowRadialMenu(MenuIndex)
        try {
            WinActivate(PreviousActiveWindow)
        }
    }

    ShowRadialMenu(MenuIndex) {
        this.MenuIndex := MenuIndex
        tableItem := MySoftData.TableInfo[3]

        menuObj := RadialMenu()
        menuObj.SetSections(8)

        loop 8 {
            macroIndex := (MenuIndex - 1) * 8 + A_Index
            remark := tableItem.RemarkArr[macroIndex]
            btnName := remark != "" ? remark : "菜单" A_Index
            ArcNr := A_Index

            gifPath := ""
            if (tableItem.HasProp("GifPathArr") && tableItem.GifPathArr.Length >= macroIndex) {
                gifPath := tableItem.GifPathArr[macroIndex]
                if (gifPath != "") {
                    fullPath := this.GetFullGifPath(gifPath)
                    if (fullPath != "" && FileExist(fullPath)) {
                        gifPath := fullPath
                    } else {
                        gifPath := ""
                    }
                }
            }

            hookFunc := this.CreateMenuHookFunc(ArcNr, MenuIndex)
            menuObj.Add(btnName, gifPath, ArcNr, 0)
            menuObj.AddHookFunc(ArcNr, hookFunc)
        }

        menuObj.Show()
    }

    GetFullGifPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\Gif\" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    CreateMenuHookFunc(ArcNr, MenuIndex) {
        return (section, name) => this.OnRadialMenuSelect(ArcNr, MenuIndex)
    }

    OnRadialMenuSelect(ArcNr, MenuIndex) {
        MySoftData.CurMenuWheelIndex := -1

        macroIndex := (MenuIndex - 1) * 8 + ArcNr
        TriggerMacroHandler(3, macroIndex)
        BindSoftHotKey()
        BindMenuHotKey()
        BindTabHotKey()
    }
}