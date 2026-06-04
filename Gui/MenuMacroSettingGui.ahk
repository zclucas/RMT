#Requires AutoHotkey v2.0

class MenuMacroSettingGui {
    __new() {
        this.Gui := ""
        this.SureFocusCon := ""
        this.CurrentIndex := 0
        this.TableIndex := 0
        this.OriginalIcoPath := ""
        this.StoredIcoPath := ""
    }

    ShowGui(tableIndex, index) {
        this.TableIndex := tableIndex
        this.CurrentIndex := index

        tableItem := MySoftData.TableInfo[tableIndex]
        this.StoredIcoPath := this.GetFullIcoPath(tableItem.IcoPathArr[index])

        this.OriginalIcoPath := this.StoredIcoPath

        if (this.Gui != "") {
            this.Gui.Destroy()
        }

        MyGui := Gui("", GetLang("菜单宏配置 - 扇区") index)
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        this.Gui := MyGui

        posY := 15

        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("图标文件:"))
        posY += 28

        this.IcoPathEdit := MyGui.Add("Edit", Format("x{} y{} w220 h27", 20, posY), this.StoredIcoPath)
        this.IcoPathEdit.Opt("ReadOnly")

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
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\MenuIcon\"
        file := FileSelect(1, fullPath, GetLang("选择图标"), "Image Files (*.gif; *.png; *.jpg; *.jpeg)")
        if (file == "")
            return

        SplitPath file, &name, &dir, &ext, &name_no_ext, &drive
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\MenuIcon"
        newPath := destDir "\" name

        if (file != newPath) {
            if (!FileExist(destDir))
                DirCreate(destDir)
            if (FileExist(newPath)) {
                fileName := this.GetUniqueFileName(file)
                newPath := destDir "\" fileName
            }
            FileCopy(file, newPath, 1)
            file := newPath
        }

        this.OriginalIcoPath := file
        this.IcoPathEdit.Value := file
    }

     GetFullIcoPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\MenuIcon\" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    OnSureClick() {
        tableItem := MySoftData.TableInfo[this.TableIndex]
        idx := this.CurrentIndex

        finalPath := ""
        if (this.OriginalIcoPath != "" && FileExist(this.OriginalIcoPath)) {
            finalPath := this.CopyIcoToImagesFolder(this.OriginalIcoPath)
        }

        while (tableItem.IcoPathArr.Length < idx) {
            tableItem.IcoPathArr.Push("")
        }
        tableItem.IcoPathArr[idx] := finalPath

        this.Gui.Destroy()
    }

    CopyIcoToImagesFolder(sourcePath) {
        iconsDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\MenuIcon"
        if (!FileExist(iconsDir)) {
            DirCreate(iconsDir)
        }

        SplitPath sourcePath, &name, &dir, &ext, &name_no_ext, &drive
        destPath := iconsDir "\" name

        if (sourcePath == destPath) {
            return sourcePath
        }

        if (FileExist(destPath)) {
            name := this.GetUniqueFileName(sourcePath)
            destPath := iconsDir "\" name
        }

        try {
            FileCopy(sourcePath, destPath, 1)
        }

        return destPath
    }

    GetUniqueFileName(sourcePath) {
        SplitPath sourcePath, , , &ext, &nameNoExt
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\MenuIcon"

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
