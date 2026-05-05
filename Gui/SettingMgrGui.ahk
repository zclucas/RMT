#Requires AutoHotkey v2.0

class SettingMgrGui {
    __new() {
        this.Gui := ""

        this.SettingList := []
        this.CurSettingCon := ""
        this.OperSettingCon := ""
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }
        this.Refresh()
    }

    Refresh() {
        this.CurSettingCon.Value := MySoftData.CurSettingName
        this.SettingList := StrSplit(MySoftData.SettingArrStr, "π")
        this.OperSettingCon.Delete()
        this.OperSettingCon.Add(this.SettingList)
        this.OperSettingCon.Text := MySoftData.CurSettingName
    }

    AddGui() {
        MyGui := Gui(, GetLang("配置管理编辑器"))
        this.Gui := MyGui
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)

        PosX := 20
        PosY := 10
        MyGui.SetFont(Format("S{} W{} Q{}", 12, 600, 0))
        con := MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("所有配置："))

        PosX := 245
        con := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 5, 165), GetLang("迁入配置文件夹"))
        con.OnEvent("Click", this.OnReplaceBtnClick.Bind(this))

        PosX := 20
        PosY += 40
        MyGui.SetFont("S11 W550 Q2", MySoftData.FontType)
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("当前配置："))

        PosX += 70
        this.CurSettingCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 155), "")

        PosX := 245
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY - 5), GetLang("重命名"))
        con.OnEvent("Click", this.OnReNameBtnClick.Bind(this))

        PosX := 330
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY - 5), GetLang("配置校准"))
        con.OnEvent("Click", this.OnRepairBtnClick.Bind(this))

        PosX := 10
        PosY += 30
        MyGui.Add("GroupBox", Format("x{} y{} w400 h75", PosX, PosY), GetLang("新增配置操作"))

        PosX := 40
        PosY += 30
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("新增配置"))
        con.OnEvent("Click", this.OnAddBtnClick.Bind(this))

        PosX := 160
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("导入配置"))
        con.OnEvent("Click", this.OnUnpackBtnClick.Bind(this))

        PosX := 280
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("合并导入"))
        con.OnEvent("Click", (*) => MyConfigMergeGui.ShowGui())

        PosX := 10
        PosY += 50
        MyGui.Add("GroupBox", Format("x{} y{} w400 h150", PosX, PosY), GetLang("配置操作"))

        PosX := 70
        PosY += 30
        MyGui.Add("Text", Format("x{} y{}", PosX, PosY), GetLang("配置选项："))

        PosX += 80
        this.OperSettingCon := MyGui.Add("DropDownList", Format("x{} y{} w{} R5", PosX, PosY - 3, 200), [])

        PosX := 80
        PosY += 35
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("加载配置"))
        con.OnEvent("Click", this.OnLoadBtnClick.Bind(this))

        PosX := 260
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("删除配置"))
        con.OnEvent("Click", this.OnDelBtnClick.Bind(this))

        PosX := 80
        PosY += 40
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("使用说明"))
        con.OnEvent("Click", this.OnCourseBtnClick.Bind(this))

        PosX := 260
        con := MyGui.Add("Button", Format("x{} y{} w100", PosX, PosY), GetLang("导出配置"))
        con.OnEvent("Click", this.OnPackBtnClick.Bind(this))

        PosX := 10
        PosY += 55
        MyGui.Add("GroupBox", Format("x{} y{} w400 h75", PosX, PosY), GetLang("仓库配置"))

        PosX := 80
        PosY += 30
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY - 5), GetLang("打开仓库"))
        con.OnEvent("Click", this.OnOpenRMTSettingBtnClick.Bind(this))

        PosX := 260
        con := MyGui.Add("Button", Format("x{} y{} w80", PosX, PosY - 5), GetLang("共享上传"))
        con.OnEvent("Click", this.OnRMTUploadBtnClick.Bind(this))

        MyGui.Show(Format("w{} h{}", 420, 415))
    }

    OnReNameBtnClick(*) {
        ; 显示输入框让用户输入新文件名
        newFileName := InputBox(GetLang("请输入新的配置名："), GetLang("重命名"), "w300 h100")

        ; 检查用户是否取消输入
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild) {
            return false
        }

        NewSettingArrStr := ""
        for index, settingName in this.SettingList {
            value := MySoftData.CurSettingName == settingName ? newFileName.Value : settingName
            NewSettingArrStr .= value "π"
        }

        oldDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        newDir := A_WorkingDir "\Setting\" newFileName.Value
        DirMove(oldDir, newDir)
        NewSettingArrStr := RTrim(NewSettingArrStr, "π")
        IniWrite(NewSettingArrStr, IniFile, IniSection, "SettingArrStr")

        MySoftData.CurSettingName := newFileName.Value
        IniWrite(MySoftData.CurSettingName, IniFile, IniSection, "CurSettingName")

        SettingDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        this.OnRepairSetting(SettingDir)
        MsgBox(GetLang("重命名成功"))
        Reload()
    }

    OnReplaceBtnClick(*) {
        tipStr := Format("{}`n{}", GetLang("将清空当前软件的所有配置，并把所选文件中的配置迁移导入本软件。"), GetLang(
            "为了避免数据丢失，自动备份当前所有配置保存到软件下SettingOld中。"))
        MsgBox(tipStr)
        SelectedFolder := DirSelect(, 0, GetLang("请选择若梦兔软件下Setting配置文件。"))
        if SelectedFolder == ""  ; 用户取消了选择
            return
        SplitPath SelectedFolder, &name, &dir, &ext, &name_no_ext, &drive
        if (!InStr(name, "Setting") || name == "SettingOld") {
            MsgBox(GetLang("需要选择若梦兔软件下的Setting文件"))
            return
        }
        CurSettingDir := A_WorkingDir "\Setting"
        OldSettingDir := A_WorkingDir "\SettingOld\Setting" FormatTime(, "MM月dd日HH-mm-ss")
        if (DirExist(OldSettingDir))
            DirDelete(OldSettingDir, true)
        DirCopy(CurSettingDir, OldSettingDir, 1)
        if (DirExist(CurSettingDir))
            DirDelete(CurSettingDir, true)
        DirCopy(SelectedFolder, CurSettingDir, 1)
        try {
            loop files, CurSettingDir "\*", "D"  ; 递归子文件夹.
            {
                this.OnRepairSetting(A_LoopFilePath)
            }
        } catch as e {
            MsgBox(GetLang("迁移失败: ") e.Message, GetLang("错误"), 0x10)
            return
        }
        MySoftData.MacroTotalCount := IniRead(IniFile, "UserSettings", "MacroTotalCount", 0)
        IniWrite(true, IniFile, IniSection, "IsReload")
        MsgBox(GetLang("配置迁移成功"))
        Reload()
    }

    OnRepairBtnClick(*) {
        SettingDir := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        hasWork := this.OnRepairSetting(SettingDir)
        if (hasWork) {
            MsgBox("已校对")
            IniWrite(true, IniFile, IniSection, "IsReload")
            Reload()
        }
        else {
            tipStr := (
                Format("{}`n{}`n{}`n{}", GetLang("未发现需要修复的内容"), GetLang("重要须知："), GetLang("- 针对覆盖配置文件后，搜索图片的配置路径矫正"),
                GetLang("- 低版本配置到高版本时，进行兼容适配升级"))
            )
            MsgBox(tipStr)
        }
    }

    OnOpenRMTSettingBtnClick(*) {
        Run("https://zclucas.github.io/RMT-Setting/")
    }

    OnRMTUploadBtnClick(*) {
        IsForbid := RMT_Http.IsForbid()
        if (IsForbid) {
            MsgBox(Format("{}`n{}`n{}", GetLang("因为以下原因配置无法上传："), GetLang("服务器没有启动"), GetLang("今日上传次数太多")))
            return
        }
        selectedFile := FileSelect(1, , GetLang("选择要共享上传的 RMT 文件"), "RMT Files (*.rmt)")
        if selectedFile == ""  ; 用户取消了选择
            return

        SplitPath selectedFile, &fileName, , &fileExt, &fileNameNoExt
        ; 检查文件扩展名
        if fileExt != "rmt" {
            MsgBox(GetLang("请选择 .rmt 文件！"), GetLang("错误"), 0x10)
            return
        }

        if (fileNameNoExt == GetLang("RMT默认配置")) {
            MsgBox(GetLang("请重命名配置文件后再上传（配置名需要与功能相关）"))
            return
        }

        isVaild := this.IsValidFolderName(fileNameNoExt)
        if (!isVaild) {
            MsgBox(GetLang("配置名不符合文件目录命名规则，请修改"))
            return
        }

        FolderPackager.UploadFile(selectedFile)
    }

    OnPackBtnClick(*) {
        folderPath := A_WorkingDir "\Setting\" this.OperSettingCon.Text
        outputFile := A_Desktop "\" this.OperSettingCon.Text ".rmt"
        FolderPackager.PackFolder(folderPath, outputFile)
        MsgBox(GetLang("打包完成:") outputFile)
    }

    OnUnpackBtnClick(*) {
        ; 选择 .rmt 文件
        selectedFile := FileSelect(1, , GetLang("选择要导入的 RMT 文件"), "RMT Files (*.rmt)")
        if selectedFile == ""  ; 用户取消了选择
            return

        SplitPath selectedFile, &fileName, , &fileExt, &fileNameNoExt
        ; 检查文件扩展名
        if fileExt != "rmt" {
            MsgBox(GetLang("请选择 .rmt 文件！"), GetLang("错误"), 0x10)
            return
        }

        isVaild := this.IsValidFolderName(fileNameNoExt)
        if (!isVaild) {
            MsgBox(GetLang("配置名不符合文件目录命名规则，请修改"))
            return false
        }

        LoadType := 1   ;增加导入 覆盖导入 自增导入
        for settingName in this.SettingList {
            if (fileNameNoExt == settingName) {
                SelectType := CustomMsgBox(GetLang("配置已存在，请选择导入方式："), GetLang("配置导入选项"), GetLang("覆盖导入|自增导入|取消导入"))
                if (SelectType == 0 || SelectType == 3)
                    return

                LoadType := SelectType + 1
                break
            }
        }

        if (LoadType == 3) {    ;自增导入
            fileNameNoExt := IncrementText(this.SettingList, fileNameNoExt)
        }

        ; 设置输出文件夹路径
        outputFolder := A_WorkingDir "\Setting\" fileNameNoExt

        try {
            ; 解包文件
            FolderPackager.UnpackFile(selectedFile, outputFolder)
            this.OnRepairSetting(outputFolder)
            if (LoadType != 2) {
                MySoftData.SettingArrStr .= "π" fileNameNoExt
                IniWrite(MySoftData.SettingArrStr, IniFile, IniSection, "SettingArrStr")
            }

            MySoftData.CurSettingName := fileNameNoExt
            IniWrite(MySoftData.CurSettingName, IniFile, IniSection, "CurSettingName")
            IniWrite(true, IniFile, IniSection, "IsReload")
            MsgBox(fileNameNoExt GetLang("配置导入成功"))
            Reload()
        } catch as e {
            MsgBox(GetLang("解包失败: ") e.Message, GetLang("错误"), 0x10)
        }
    }

    OnLoadBtnClick(*) {
        MySoftData.CurSettingName := this.OperSettingCon.Text
        IniWrite(MySoftData.CurSettingName, IniFile, IniSection, "CurSettingName")
        IniWrite(true, IniFile, IniSection, "IsReload")
        Reload()
    }

    OnCourseBtnClick(*) {
        folderPath := A_WorkingDir "\Setting\" this.OperSettingCon.Text
        MyUseExplainGui.Mode := 1
        MyUseExplainGui.ShowGui(folderPath)
    }

    OnDelBtnClick(*) {
        if (this.OperSettingCon.Text == MySoftData.CurSettingName) {
            MsgBox(GetLang("不可删除当前配置"))
            return
        }

        result := MsgBox(Format(GetLang("是否删除{}配置"), this.OperSettingCon.Text), GetLang("提示"), 1)
        if (result == "Cancel")
            return

        if (DirExist(A_WorkingDir "\Setting\" this.OperSettingCon.Text)) {
            DirDelete(A_WorkingDir "\Setting\" this.OperSettingCon.Text, true)
        }
        SettingArrStr := ""
        for settingName in this.SettingList {
            if (this.OperSettingCon.Text == settingName)
                continue
            SettingArrStr .= settingName "π"
        }
        SettingArrStr := RTrim(SettingArrStr, "π")
        MySoftData.SettingArrStr := SettingArrStr
        IniWrite(MySoftData.SettingArrStr, IniFile, IniSection, "SettingArrStr")
        MsgBox(GetLang("删除配置: ") this.OperSettingCon.Text)
        this.Refresh()
    }

    OnAddBtnClick(*) {
        newFileName := InputBox(GetLang("请输入新的配置名："), GetLang("新增配置"), "w300 h100")
        ; 检查用户是否取消输入
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild) {
            return false
        }

        MySoftData.CurSettingName := newFileName.Value
        IniWrite(MySoftData.CurSettingName, IniFile, IniSection, "CurSettingName")

        MySoftData.SettingArrStr .= "π" newFileName.Value
        IniWrite(MySoftData.SettingArrStr, IniFile, IniSection, "SettingArrStr")
        MsgBox(GetLang("成功新增配置：") newFileName.Value)
        Reload()
    }

    OnCopyBtnClick(*) {
        newFileName := InputBox(GetLang("请输入新的配置名："), GetLang("复制配置"), "w300 h100")
        ; 检查用户是否取消输入
        if newFileName.Result = "Cancel" || newFileName.Value = ""
            return

        isVaild := this.CheckIfExistAndValid(newFileName.Value)
        if (!isVaild) {
            return false
        }

        MySoftData.SettingArrStr .= "π" newFileName.Value
        IniWrite(MySoftData.SettingArrStr, IniFile, IniSection, "SettingArrStr")
        SourcePath := A_WorkingDir "\Setting\" MySoftData.CurSettingName
        DestPath := A_WorkingDir "\Setting\" newFileName.Value
        DirCopy(SourcePath, DestPath, 1)
        this.OnRepairSetting(DestPath)
        MsgBox(Format(GetLang("成功复制<{}>配置到<{}>中"), MySoftData.CurSettingName, newFileName.Value))

        MySoftData.CurSettingName := newFileName.Value
        IniWrite(MySoftData.CurSettingName, IniFile, IniSection, "CurSettingName")
        Reload()
    }

    OnRepairSetting(SettringDir) {
        SplitPath SettringDir, &fileName, , &fileExt, &fileNameNoExt
        hasWork := false
        hasWork := CompatCMD(SettringDir "\MacroFile.ini") || hasWork
        hasWork := CompatSearch(SettringDir "\SearchFile.ini") || hasWork
        hasWork := CompatSearchPro(SettringDir "\SearchProFile.ini") || hasWork
        hasWork := CompatMMPro(SettringDir "\MMProFile.ini") || hasWork
        hasWork := CompatOutput(SettringDir "\OutputFile.ini") || hasWork
        hasWork := CompatRun(SettringDir "\RunFile.ini") || hasWork
        hasWork := CompatLoop(SettringDir "\LoopFile.ini") || hasWork
        hasWork := CompatSubMacro(SettringDir "\SubMacroFile.ini") || hasWork
        hasWork := CompatVariable(SettringDir "\VariableFile.ini") || hasWork
        hasWork := CompatExVariable(SettringDir "\ExVariableFile.ini") || hasWork
        hasWork := CompatCompare(SettringDir "\CompareFile.ini") || hasWork
        hasWork := CompatComparePro(SettringDir "\CompareProFile.ini") || hasWork
        hasWork := CompatOperation(SettringDir "\OperationFile.ini") || hasWork
        hasWork := CompatBGMouse(SettringDir "\BGMouseFile.ini") || hasWork
        hasWork := CompatBGKey(SettringDir "\BGKeyFile.ini") || hasWork
        hasWork := CompatTiming(SettringDir "\TimingFile.ini") || hasWork
        return hasWork
    }

    CheckIfExistAndValid(FileName) {
        isVaild := this.IsValidFolderName(FileName)
        if (!isVaild) {
            MsgBox(GetLang("配置名不符合文件目录命名规则，请修改"))
            return false
        }

        for settingName in this.SettingList {
            if (FileName == settingName) {
                MsgBox(GetLang("配置名已存在"))
                return false
            }
        }
        return true
    }

    IsValidFolderName(folderName) {
        ; 空名称不合法
        if (folderName == "") {
            return false
        }

        ; Windows 保留名称不合法（使用Map）
        reservedNames := Map(
            "CON", 1, "PRN", 1, "AUX", 1, "NUL", 1,
            "COM1", 1, "COM2", 1, "COM3", 1, "COM4", 1, "COM5", 1, "COM6", 1, "COM7", 1, "COM8", 1, "COM9", 1,
            "LPT1", 1, "LPT2", 1, "LPT3", 1, "LPT4", 1, "LPT5", 1, "LPT6", 1, "LPT7", 1, "LPT8", 1, "LPT9", 1
        )

        if (reservedNames.Has(folderName)) {
            return false
        }

        ; 检查非法字符
        illegalChars := ["\", "/", ":", "*", "?", " ", "<", ">", "|"]
        for char in illegalChars {
            if (InStr(folderName, char)) {
                return false
            }
        }

        ; 不能以空格或点结尾
        if (RegExMatch(folderName, "[ .]$")) {
            return false
        }

        ; 名称长度不能超过255个字符
        if (StrLen(folderName) > 255) {
            return false
        }

        ; 其他情况视为合法
        return true
    }
}
