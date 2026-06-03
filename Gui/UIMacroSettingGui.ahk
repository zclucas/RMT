#Requires AutoHotkey v2.0

class UIMacroSettingGui {
    __new() {
        this.Gui := ""
        this.CurrentMacroIndex := 0
        this.SaveBtnAction := ""
        this.SureFocusCon := ""
        this.OriginalIconPath := ""
        this.StoredIconPath := ""
    }

    ShowGui(tableItem, macroIndex) {
        this.CurrentMacroIndex := macroIndex

        ; 读取已保存的图标路径
        if (tableItem.UIIconArr.Has(macroIndex) && tableItem.UIIconArr[macroIndex] != "") {
            this.StoredIconPath := this.GetFullIconPath(tableItem.UIIconArr[macroIndex])
        } else {
            this.StoredIconPath := ""
        }
        this.OriginalIconPath := this.StoredIconPath

        if (this.Gui != "") {
            try this.Gui.Destroy()
        }

        MyGui := Gui("", GetLang("界面宏配置 - 图标") macroIndex)
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        this.Gui := MyGui

        posY := 15

        con := MyGui.Add("Text", Format("x{} y{}", 20, posY), GetLang("图标文件:"))
        posY += 28

        this.IconPathEdit := MyGui.Add("Edit", Format("x{} y{} w220 h27", 20, posY), this.StoredIconPath)
        this.IconPathEdit.Opt("ReadOnly")

        browseBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 250, posY - 1), GetLang("选择"))
        browseBtn.OnEvent("Click", (*) => this.OnBrowseClick())
        posY += 40

        sureBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 120, posY), GetLang("确定"))
        sureBtn.OnEvent("Click", (*) => this.OnSureClick(tableItem))

        cancelBtn := MyGui.Add("Button", Format("x{} y{} w80 h29", 220, posY), GetLang("取消"))
        cancelBtn.OnEvent("Click", (*) => this.OnCancelClick())

        MyGui.OnEvent("Close", (*) => this.OnCancelClick())
        MyGui.Show("w410 h" posY + 50)
    }

    OnBrowseClick() {
        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        file := FileSelect(1, fullPath, GetLang("选择图标"), "Image Files (*.gif; *.png; *.jpg; *.jpeg)")
        if (file == "")
            return

        SplitPath file, &name, &dir, &ext, &name_no_ext, &drive
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        if (!FileExist(destDir))
            DirCreate(destDir)
        newPath := destDir "\" name

        if (file != newPath) {
            if (FileExist(newPath)) {
                fileName := this.GetUniqueFileName(file)
                newPath := destDir "\" fileName
            }
            FileCopy(file, newPath, 1)
            file := newPath
        }

        this.OriginalIconPath := file
        this.IconPathEdit.Value := file
    }

    GetFullIconPath(path) {
        if (path == "")
            return ""

        if (FileExist(path))
            return path

        fullPath := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon" path
        if (FileExist(fullPath))
            return fullPath

        return ""
    }

    OnSureClick(tableItem) {
        macroIndex := this.CurrentMacroIndex

        finalPath := ""
        if (this.OriginalIconPath != "" && FileExist(this.OriginalIconPath)) {
            finalPath := this.CopyIconToImagesFolder(this.OriginalIconPath)
        }

        if (!tableItem.HasProp("UIIconArr")) {
            tableItem.UIIconArr := []
        }
        while (tableItem.UIIconArr.Length < macroIndex) {
            tableItem.UIIconArr.Push("")
        }
        tableItem.UIIconArr[macroIndex] := finalPath

        ; 立即保存图标路径到配置文件（不触发重启）
        this.SaveData(tableItem)

        action := this.SaveBtnAction
        if (action != "")
            action()

        try this.Gui.Destroy()
        this.Gui := ""

        if (this.SureFocusCon != "")
            this.SureFocusCon.Focus()
    }

    CopyIconToImagesFolder(sourcePath) {
        iconsDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"
        if (!FileExist(iconsDir)) {
            DirCreate(iconsDir)
        }

        SplitPath sourcePath, &name, &dir, &ext, &name_no_ext, &drive
        destPath := iconsDir "\" name

        if (sourcePath == destPath) {
            return name
        }

        if (FileExist(destPath)) {
            name := this.GetUniqueFileName(sourcePath)
            destPath := iconsDir "\" name
        }

        try {
            FileCopy(sourcePath, destPath, 1)
        }

        return name
    }

    GetUniqueFileName(sourcePath) {
        SplitPath sourcePath, , , &ext, &nameNoExt
        destDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\Images\UIIcon"

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

    SaveData(tableItem) {
        macroFile := A_WorkingDir "\Setting\" MySoftData.CurSettingName "\MacroFile.ini"

        iconArrStr := ""
        loop tableItem.UIIconArr.Length {
            iconArrStr .= tableItem.UIIconArr[A_Index]
            if (tableItem.UIIconArr.Length > A_Index)
                iconArrStr .= "π"
        }

        IniWrite(iconArrStr, macroFile, "UserSettings", "UIUIIconArr")
    }

    OnCancelClick() {
        try {
            if (this.Gui != "")
                this.Gui.Destroy()
        }
        this.Gui := ""
    }
}
