#Requires AutoHotkey v2.0

class MenuMacroSettingGui {
    __new() {
        this.Gui := ""
        this.SureFocusCon := ""
        this.CurrentIndex := 0
        this.TableIndex := 0
        this.OriginalGifPath := ""
        this.StoredGifPath := ""
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

        if (this.Gui != "") {
            this.Gui.Destroy()
        }

        MyGui := Gui("", GetLang("菜单宏配置 - 扇区") index)
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        this.Gui := MyGui

        posY := 15

        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("图标文件:"))
        posY += 28

        this.GifPathEdit := MyGui.Add("Edit", Format("x{} y{} w220 h27", 20, posY), this.StoredGifPath)
        this.GifPathEdit.Opt("ReadOnly")

        browseBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 250, posY - 1), GetLang("选择"))
        browseBtn.OnEvent("Click", (*) => this.OnBrowseClick())
        posY += 40

        sureBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 120, posY), GetLang("确定"))
        sureBtn.OnEvent("Click", (*) => this.OnSureClick())

        cancelBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 220, posY), GetLang("取消"))
        cancelBtn.OnEvent("Click", (*) => this.OnCancelClick())

        MyGui.OnEvent("Close", (*) => this.OnCancelClick())
        MyGui.Show("w410 h" posY + 50)
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
