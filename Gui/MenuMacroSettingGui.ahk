#Requires AutoHotkey v2.0

class MenuMacroSettingGui {
    __new() {
        this.Gui := ""
        this.SureFocusCon := ""
        this.CurrentIndex := 0
        this.TableIndex := 0
        this.OriginalGifPath := ""
        this.StoredGifPath := ""
        this.SectorNameEdit := ""
        this.UseCustomColorCon := ""
        this.SectorNormalFillCon := ""
        this.SectorHoverFillCon := ""
        this.SectorSelectedFillCon := ""
    }

    ShowGui(tableIndex, index) {
        this.TableIndex := tableIndex
        this.CurrentIndex := index

        tableItem := MySoftData.TableInfo[tableIndex]
        if (tableItem.HasProp("GifPathArr") && tableItem.GifPathArr.Length >= index && tableItem.GifPathArr[index] != "") {
            this.StoredGifPath := tableItem.GifPathArr[index]
        } else {
            this.StoredGifPath := ""
        }
        this.OriginalGifPath := this.StoredGifPath

        sectorName := ""
        if (tableItem.RemarkArr.Length >= index)
            sectorName := tableItem.RemarkArr[index]

        useCustomColor := false
        secNormalFill := ""
        secHoverFill := ""
        secSelectedFill := ""
        if (tableItem.HasProp("SectorUseColorArr") && tableItem.SectorUseColorArr.Length >= index)
            useCustomColor := !!tableItem.SectorUseColorArr[index]
        if (tableItem.HasProp("SectorNormalFillArr") && tableItem.SectorNormalFillArr.Length >= index)
            secNormalFill := tableItem.SectorNormalFillArr[index]
        if (tableItem.HasProp("SectorHoverFillArr") && tableItem.SectorHoverFillArr.length >= index)
            secHoverFill := tableItem.SectorHoverFillArr[index]
        if (tableItem.HasProp("SectorSelectedFillArr") && tableItem.SectorSelectedFillArr.Length >= index)
            secSelectedFill := tableItem.SectorSelectedFillArr[index]

        if (this.Gui != "") {
            this.Gui.Destroy()
        }

        MyGui := Gui("", GetLang("菜单宏配置 - 扇区") index)
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        this.Gui := MyGui

        posY := 15

        MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("扇区名称:"))
        posY += 25
        this.SectorNameEdit := MyGui.Add("Edit", Format("x{} y{} w300 h27", 20, posY), sectorName)

        posY += 35
        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("图标文件:"))
        posY += 28

        this.GifPathEdit := MyGui.Add("Edit", Format("x{} y{} w220 h27", 20, posY), this.StoredGifPath)
        this.GifPathEdit.Opt("ReadOnly")

        browseBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 250, posY - 1), GetLang("选择"))
        browseBtn.OnEvent("Click", (*) => this.OnBrowseClick())
        posY += 40

        MyGui.Add("GroupBox", Format("x{} y{} w370 h95", 15, posY), GetLang("自定义颜色（覆盖模块默认值）"))
        posY += 22

        this.UseCustomColorCon := MyGui.Add("Checkbox", Format("x{} y{} w200", 25, posY), GetLang("启用自定义颜色"))
        this.UseCustomColorCon.Value := useCustomColor
        this.UseCustomColorCon.OnEvent("Click", (*) => this.OnCustomColorToggle())

        posY += 30
        MyGui.Add("Text", Format("x{} y{}", 25, posY), GetLang("普通背景:"))
        this.SectorNormalFillCon := MyGui.Add("Edit", Format("x{} y{} w100 h25", 105, posY - 3), secNormalFill)

        MyGui.Add("Text", Format("x{} y{}", 220, posY), GetLang("悬停背景:"))
        this.SectorHoverFillCon := MyGui.Add("Edit", Format("x{} y{} w100 h25", 295, posY - 3), secHoverFill)

        posY += 28
        MyGui.Add("Text", Format("x{} y{}", 25, posY), GetLang("选中背景:"))
        this.SectorSelectedFillCon := MyGui.Add("Edit", Format("x{} y{} w100 h25", 105, posY - 3), secSelectedFill)

        this.OnCustomColorToggle()

        posY += 45

        sureBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 120, posY), GetLang("确定"))
        sureBtn.OnEvent("Click", (*) => this.OnSureClick())

        cancelBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 220, posY), GetLang("取消"))
        cancelBtn.OnEvent("Click", (*) => this.OnCancelClick())

        MyGui.OnEvent("Close", (*) => this.OnCancelClick())
        MyGui.Show("w410 h" posY + 50)
    }

    OnCustomColorToggle() {
        enabled := !!this.UseCustomColorCon.Value
        this.SectorNormalFillCon.Enabled := enabled
        this.SectorHoverFillCon.Enabled := enabled
        this.SectorSelectedFillCon.Enabled := enabled
    }

    OnBrowseClick() {
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\Gif\"
        file := FileSelect(1, fullPath, GetLang("选择GIF"), "Img Files (*.gif; *.png; .jpg)")
        if (file == "")
            return

        this.OriginalGifPath := file
        this.GifPathEdit.Value := file
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

    OnSureClick() {
        tableItem := MySoftData.TableInfo[this.TableIndex]
        idx := this.CurrentIndex

        while (tableItem.RemarkArr.Length < idx) {
            tableItem.RemarkArr.Push("")
        }
        tableItem.RemarkArr[idx] := this.SectorNameEdit.Value

        finalPath := ""
        if (this.OriginalGifPath != "" && FileExist(this.OriginalGifPath)) {
            finalPath := this.CopyGifToImagesFolder(this.OriginalGifPath)
        }

        if (!tableItem.HasProp("GifPathArr")) {
            tableItem.GifPathArr := []
        }
        while (tableItem.GifPathArr.Length < idx) {
            tableItem.GifPathArr.Push("")
        }
        tableItem.GifPathArr[idx] := finalPath

        InitArray(tableItem, "SectorUseColorArr")
        InitArray(tableItem, "SectorNormalFillArr")
        InitArray(tableItem, "SectorHoverFillArr")
        InitArray(tableItem, "SectorSelectedFillArr")

        while (tableItem.SectorUseColorArr.Length < idx)
            tableItem.SectorUseColorArr.Push("")
        while (tableItem.SectorNormalFillArr.Length < idx)
            tableItem.SectorNormalFillArr.Push("")
        while (tableItem.SectorHoverFillArr.Length < idx)
            tableItem.SectorHoverFillArr.Push("")
        while (tableItem.SectorSelectedFillArr.Length < idx)
            tableItem.SectorSelectedFillArr.Push("")

        tableItem.SectorUseColorArr[idx] := this.UseCustomColorCon.Value
        tableItem.SectorNormalFillArr[idx] := this.SectorNormalFillCon.Value
        tableItem.SectorHoverFillArr[idx] := this.SectorHoverFillCon.Value
        tableItem.SectorSelectedFillArr[idx] := this.SectorSelectedFillCon.Value

        this.Gui.Destroy()
    }

    CopyGifToImagesFolder(sourcePath) {
        gifsDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\Gif"
        if (!FileExist(gifsDir)) {
            DirCreate(gifsDir)
        }

        fileName := this.GetUniqueFileName(sourcePath)
        destPath := gifsDir "\" fileName

        if (sourcePath == destPath) {
            return fileName
        }

        try {
            FileCopy(sourcePath, destPath, 1)
        }

        return fileName
    }

    GetUniqueFileName(sourcePath) {
        SplitPath sourcePath, , , &ext, &nameNoExt
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\Gif"

        if (!FileExist(destDir "\" nameNoExt "." ext)) {
            return nameNoExt "." ext
        }

        counter := 1
        while (true) {
            newName := nameNoExt "_" counter "." ext
            if (!FileExist(destDir "\" newName)) {
                return newName
            }
            counter++
        }
    }

    OnCancelClick() {
        this.Gui.Destroy()
    }
}
