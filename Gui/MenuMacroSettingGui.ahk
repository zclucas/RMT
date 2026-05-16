#Requires AutoHotkey v2.0

class MenuMacroSettingGui {
    __new() {
        this.Gui := ""
        this.SureBtnAction := ""
        this.SaveBtnAction := ""
        this.SureFocusCon := ""
        this.CurrentIndex := 0
        this.TableIndex := 0
        this.OriginalGifPath := ""
        this.StoredGifPath := ""
        this.GifPlayer := ""
        this.PreviewCon := ""
        this.pToken := 0
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

        this.pToken := Gdip_Startup()

        MyGui := Gui("", GetLang("菜单宏配置"))
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        this.Gui := MyGui

        posY := 20

        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("GIF文件:"))
        posY += 30

        this.GifPathEdit := MyGui.Add("Edit", Format("x{} y{} w300 h27", 20, posY), this.StoredGifPath)
        this.GifPathEdit.Opt("ReadOnly")
        
        browseBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 330, posY - 1), GetLang("浏览"))
        browseBtn.OnEvent("Click", (*) => this.OnBrowseClick())
        posY += 35

        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("预览:"))
        posY += 20

        this.PreviewCon := MyGui.Add("Picture", Format("x{} y{} w300 h200 BackgroundDDDDDD", 20, posY), "")
        this.PreviewCon.Opt("0x2000000")
        
        if (this.StoredGifPath != "") {
            fullPath := this.GetFullGifPath(this.StoredGifPath)
            if (FileExist(fullPath)) {
                this.ShowGifPreview(fullPath)
            }
        }

        posY += 210

        sureBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 100, posY), GetLang("确定"))
        sureBtn.OnEvent("Click", (*) => this.OnSureClick())
        
        cancelBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 200, posY), GetLang("取消"))
        cancelBtn.OnEvent("Click", (*) => this.OnCancelClick())

        MyGui.OnEvent("Close", (*) => this.OnCancelClick())
        MyGui.Show("w420 h" posY + 50)
    }

    OnBrowseClick() {
        file := FileSelect(1, , GetLang("选择GIF"), "GIF Files (*.gif)")
        if (file == "")
            return

        this.OriginalGifPath := file
        this.GifPathEdit.Value := file
        
        if (FileExist(file)) {
            this.ShowGifPreview(file)
        }
    }

    ShowGifPreview(path) {
        if (this.GifPlayer != "") {
            try {
                this.GifPlayer.Pause()
            }
        }

        if (path != "" && FileExist(path)) {
            this.GifPlayer := RM_GifPlayer(path, this.PreviewCon, "", this.pToken)
            this.GifPlayer.Play()
        }
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
        
        finalPath := ""
        if (this.OriginalGifPath != "" && FileExist(this.OriginalGifPath)) {
            finalPath := this.CopyGifToImagesFolder(this.OriginalGifPath)
        }
        
        if (!tableItem.HasProp("GifPathArr")) {
            tableItem.GifPathArr := []
        }
        while (tableItem.GifPathArr.Length < this.CurrentIndex) {
            tableItem.GifPathArr.Push("")
        }
        tableItem.GifPathArr[this.CurrentIndex] := finalPath

        if (this.SaveBtnAction != "") {
            this.SaveBtnAction()
        }
        
        this.Cleanup()
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
        this.Cleanup()
        this.Gui.Destroy()
    }

    Cleanup() {
        if (this.GifPlayer != "") {
            try {
                this.GifPlayer.Pause()
            }
        }
        if (this.pToken != 0) {
            Gdip_Shutdown(this.pToken)
            this.pToken := 0
        }
    }
}