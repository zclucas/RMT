#Requires AutoHotkey v2.0
#Include ..\Main\Util\MergeUtil.ahk

class ConfigMergeGui {
    __New() {
        this.Gui := ""
        this.TreeRoot := ""
        this.SourceType := "file"
        this.SourcePath := ""
        this.SourceName := ""
        this.ListView := ""
        this.PreviewText := ""
        this.ItemNodeMap := Map()
        this.LastCheckSnapshot := Map()
        this.IsFromRmt := false
    }

    ShowGui() {
        if (this.Gui != "") {
            this.Gui.Show()
            return
        }
        this.AddGui()
    }

    AddGui() {
        MyGui := Gui("+MinimizeBox", GetLang("配置合并导入"))
        this.Gui := MyGui
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)
        MyGui.OnEvent("Close", (*) => this.OnClose())
        MyGui.OnEvent("Escape", (*) => this.OnClose())

        PosX := 15
        PosY := 12

        MyGui.SetFont("S11 W600 Q2", MySoftData.FontType)
        MyGui.Add("GroupBox", Format("x{} y{} w690 h55", PosX, PosY), GetLang("源配置选择"))

        PosX += 15
        PosY += 22
        this.FileRadio := MyGui.Add("Radio", Format("x{} y{} w200", PosX, PosY), GetLang("从文件导入(.rmt)"))
        this.FileRadio.Value := true
        this.FileRadio.OnEvent("Click", (*) => this.OnSourceTypeChange("file"))

        PosX += 210
        this.LocalRadio := MyGui.Add("Radio", Format("x{} y{} w160", PosX, PosY), GetLang("从本地配置导入"))
        this.LocalRadio.OnEvent("Click", (*) => this.OnSourceTypeChange("local"))

        PosX := 85
        PosY += 24
        this.SelectFileBtn := MyGui.Add("Button", Format("x{} y{} w100 h26", PosX, PosY), GetLang("选择文件..."))
        this.SelectFileBtn.OnEvent("Click", (*) => this.OnSelectFile())

        PosX += 115
        this.LocalConfigDDL := MyGui.Add("DropDownList", Format("x{} y{} w180 R5 Disabled", PosX, PosY), [])
        this.LocalConfigDDL.OnEvent("Change", (*) => this.OnLocalConfigChange())

        PosX := 430
        this.LocalConfigDDL.Move(PosX, PosY)

        PosX := 15
        PosY += 40
        MyGui.SetFont("S11 W600 Q2", MySoftData.FontType)
        MyGui.Add("GroupBox", Format("x{} y{} w690 h340", PosX, PosY), GetLang("宏选择"))

        PosX += 10
        PosY += 25

        MyGui.Add("Text", Format("x{} y{}", PosX, PosY + 3), GetLang("已选择") ":")
        PosX += 50
        this.SelectedCountText := MyGui.Add("Text", Format("x{} y{} w50", PosX, PosY + 3), "0")

        PosX := 25
        PosY += 28
        headerArr := [GetLang("选择"), GetLang("宏名称"), GetLang("触发键/类型"), GetLang("备注")]

        this.ListView := MyGui.Add("ListView", Format("x{} y{} w665 h280 Checked", PosX, PosY), headerArr)
        this.ListView.ModifyCol(1, "AutoHdr Center")
        this.ListView.ModifyCol(2, "AutoHdr 240")
        this.ListView.ModifyCol(3, "AutoHdr Center")
        this.ListView.ModifyCol(4, "AutoHdr")
        this.ListView.OnEvent("Click", (*) => this.OnListViewClick())
        this.ListView.OnEvent("ItemCheck", (*) => this.OnItemCheck())

        PosX := 15
        PosY += 358
        MyGui.SetFont("S11 W600 Q2", MySoftData.FontType)
        MyGui.Add("GroupBox", Format("x{} y{} w690 h38", PosX, PosY), GetLang("导入选项"))

        PosX += 15
        PosY += 25
        MyGui.Add("Text", Format("x{} y{} w660", PosX, PosY + 3), GetLang("导入的宏将按原模块结构创建新模块"))

        PosX := 480
        PosY += 25
        this.CancelBtn := MyGui.Add("Button", Format("x{} y{} w100 h32", PosX, PosY), GetLang("取消"))
        this.CancelBtn.OnEvent("Click", (*) => this.OnClose())

        PosX -= 115
        this.ExecuteBtn := MyGui.Add("Button", Format("x{} y{} w100 h32 Default", PosX, PosY), GetLang("开始合并导入"))
        this.ExecuteBtn.OnEvent("Click", (*) => this.OnExecuteMerge())

        MyGui.Show(Format("w{} h{}", 720, 678))
        this.RefreshLocalConfigList()
    }

    RefreshLocalConfigList() {
        settingList := StrSplit(MySoftData.SettingArrStr, "π")
        validSettings := []
        for name in settingList {
            if (name != MySoftData.CurSettingName)
                validSettings.Push(name)
        }
        this.LocalConfigDDL.Delete()
        this.LocalConfigDDL.Add(validSettings)
        if (validSettings.Length > 0) {
            this.LocalConfigDDL.Text := validSettings[1]
        }
    }

    OnSourceTypeChange(type) {
        this.SourceType := type
        if (type == "file") {
            this.SelectFileBtn.Enabled := true
            this.LocalConfigDDL.Enabled := false
            this.LocalConfigDDL.Value := ""
        }
        else {
            this.SelectFileBtn.Enabled := false
            this.LocalConfigDDL.Enabled := true
            if (this.LocalConfigDDL.Text != "")
                this.OnLocalConfigChange()
        }
    }

    OnSelectFile() {
        selectedFile := FileSelect(1, , GetLang("选择要合并导入的 RMT 文件"), "RMT Files (*.rmt)")
        if (selectedFile == "")
            return

        SplitPath selectedFile, &fileName, , &fileExt, &fileNameNoExt
        if (fileExt != "rmt") {
            MsgBox(GetLang("请选择 .rmt 文件！"), GetLang("错误"), 0x10)
            return
        }

        this.SourcePath := selectedFile
        this.SourceName := fileNameNoExt
        this.IsFromRmt := true

        try {
            tempDir := MergeUtil.PrepareTempFromRmt(selectedFile)
            this.LoadSourceConfig(tempDir)
        } catch as e {
            MsgBox(GetLang("解包失败: ") e.Message, GetLang("错误"), 0x10)
        }
    }

    OnLocalConfigChange() {
        configName := this.LocalConfigDDL.Text
        if (configName == "")
            return

        this.SourceName := configName
        this.SourcePath := A_WorkingDir "\Setting\" configName
        this.IsFromRmt := false

        this.LoadSourceConfig(this.SourcePath)
    }

    LoadSourceConfig(settingDir) {
        this.TreeRoot := MergeUtil.ParseSourceConfig(settingDir)
        this.PopulateListView()
    }

    PopulateListView() {
        this.ListView.Delete()
        this.ItemNodeMap := Map()

        if (!this.TreeRoot || !this.TreeRoot.Children)
            return

        row := 0
        for tabNode in this.TreeRoot.Children {
            tabRow := ++row
            tabChecked := MergeUtil.HasAnyCheckedItem(tabNode) ? "Check" : ""
            this.ListView.Add(tabChecked, "", "  " tabNode.DisplayName)
            tabNode.ListViewRow := tabRow
            tabNode.IsTabNode := true
            this.ItemNodeMap[tabRow] := tabNode

            isMenuTab := (tabNode.TabIndex == 3)

            for moduleNode in tabNode.Children {
                moduleRow := ++row
                moduleChecked := MergeUtil.HasAnyCheckedItem(moduleNode) ? "Check" : ""
                moduleIndent := isMenuTab ? "  " : "    "
                this.ListView.Add(moduleChecked, "", moduleIndent moduleNode.DisplayName)
                moduleNode.ListViewRow := moduleRow
                moduleNode.IsModuleNode := true
                this.ItemNodeMap[moduleRow] := moduleNode

                if (!isMenuTab) {
                    for itemNode in moduleNode.Children {
                        itemRow := ++row
                        checkedStr := itemNode.IsChecked ? "Check" : ""
                        triggerDisplay := itemNode.TriggerKey != "" ? itemNode.TriggerKey : GetLang("无触发键")
                        remarkDisplay := itemNode.Remark != "" ? itemNode.Remark : ""

                        this.ListView.Add(checkedStr, "", "      " itemNode.DisplayName, triggerDisplay, remarkDisplay)
                        this.ItemNodeMap[itemRow] := itemNode
                        itemNode.ListViewRow := itemRow
                    }
                }
            }

            this.RefreshAllStates()
        }
    }

    OnListViewClick() {
    }

    OnItemCheck() {
        clickedRow := this.FindChangedRow()
        if (!clickedRow)
            return

        node := this.ItemNodeMap[clickedRow]
        newState := !node.IsChecked
        node.IsChecked := newState

        if (node.Type == "Tab") {
            for moduleNode in node.Children {
                moduleNode.IsChecked := newState
                MergeUtil.SetChildrenChecked(moduleNode, newState)
            }
        }
        else if (node.Type == "Module") {
            MergeUtil.SetChildrenChecked(node, newState)
        }

        this.RefreshAllStates()
    }

    FindChangedRow() {
        for rowNum, node in this.ItemNodeMap {
            currentChecked := (this.ListView.GetNext(rowNum - 1, "C") == rowNum)
            lastChecked := this.LastCheckSnapshot.Has(rowNum) ? this.LastCheckSnapshot[rowNum] : node.IsChecked

            if (currentChecked != lastChecked)
                return rowNum
        }
        return 0
    }

    SaveCheckSnapshot() {
        this.LastCheckSnapshot := Map()
        loopCount := this.ListView.GetCount()
        loop loopCount {
            isChecked := (this.ListView.GetNext(A_Index - 1, "C") == A_Index)
            this.LastCheckSnapshot.Set(A_Index, isChecked)
        }
    }

    RefreshAllStates() {
        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Item") {
                if (node.IsChecked)
                    this.ListView.Modify(rowNum, "Check")
                else
                    this.ListView.Modify(rowNum, "-Check")
            }
        }

        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Module" && node.IsModuleNode) {
                allChecked := true
                anyChecked := false
                hasChildren := false

                for child in node.Children {
                    hasChildren := true
                    if (child.IsChecked)
                        anyChecked := true
                    else
                        allChecked := false
                }

                if (hasChildren) {
                    node.IsChecked := anyChecked
                    if (allChecked && anyChecked)
                        this.ListView.Modify(rowNum, "Check")
                    else
                        this.ListView.Modify(rowNum, "-Check")
                }
            }
        }

        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Tab" && node.IsTabNode) {
                allModulesChecked := true
                anyModuleChecked := false
                hasChildren := false

                for moduleNode in node.Children {
                    hasChildren := true
                    if (moduleNode.IsChecked)
                        anyModuleChecked := true
                    else
                        allModulesChecked := false
                }

                if (hasChildren) {
                    node.IsChecked := anyModuleChecked
                    if (allModulesChecked && anyModuleChecked)
                        this.ListView.Modify(rowNum, "Check")
                    else
                        this.ListView.Modify(rowNum, "-Check")
                }
            }
        }

        count := 0
        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Item" && node.IsChecked)
                count++
        }
        this.SelectedCountText.Text := count ""
        this.SaveCheckSnapshot()
    }

    OnExecuteMerge() {
        if (!this.TreeRoot) {
            MsgBox(GetLang("请先选择源配置"), GetLang("提示"), 0x40)
            return
        }

        checkedItems := []
        for rowNum, node in this.ItemNodeMap {
            if (node.Type == "Item" && node.IsChecked)
                checkedItems.Push(node)
        }

        if (checkedItems.Length == 0) {
            MsgBox(GetLang("请至少选择一个宏进行导入"), GetLang("提示"), 0x40)
            return
        }

        conflicts := MergeUtil.CheckConflicts(checkedItems)
        if (conflicts.Length > 0) {
            conflictSerials := []
            for c in conflicts {
                conflictSerials.Push(c.Serial " (" c.Type ")")
            }

            tipStr := GetLang("以下资源序列号与当前配置存在冲突，将自动重命名：") "`n`n"
            for serialInfo in conflictSerials {
                tipStr .= "  - " serialInfo "`n"
            }

            MsgBox(tipStr, GetLang("资源冲突提示"), 0x0)
        }

        moduleCount := MergeUtil.GetModuleCountFromItems(checkedItems)

        resultMsg := Format("{}: {}`n{}: {}`n{}: {}",
            GetLang("来源配置"), this.SourceName,
            GetLang("导入模块数"), moduleCount,
            GetLang("导入宏数"), checkedItems.Length)

        confirmResult := MsgBox(resultMsg, GetLang("确认合并导入"), 0x24 | 0x40)
        if (confirmResult != "Yes")
            return

        try {
            result := MergeUtil.ExecuteMerge(checkedItems, this.SourceName)

            successMsg := GetLang("合并导入成功") "!`n`n"
            successMsg .= Format("{}: {}`n", GetLang("创建模块数"), result.ModuleCount)
            successMsg .= Format("{}: {}`n", GetLang("导入宏数"), checkedItems.Length)
            successMsg .= Format("{}: {}", GetLang("来源配置"), result.SourceName)

            if (result.RenamedResources.Length > 0) {
                successMsg .= "`n" Format("{}: {}", GetLang("重命名资源"), result.RenamedResources.Length)
            }
            if (result.CopiedImages.Length > 0) {
                successMsg .= "`n" Format("{}: {}", GetLang("复制图片"), result.CopiedImages.Length)
            }

            MsgBox(successMsg, GetLang("成功"), 0x0)
            this.OnClose()
            OnSaveSetting()
        } catch as e {
            MsgBox(GetLang("合并导入失败: ") e.Message, GetLang("错误"), 0x10)
        }
    }

    OnClose() {
        if (this.Gui != "") {
            try {
                this.Gui.Destroy()
            }
            this.Gui := ""
        }
        MergeUtil.CleanupTemp()
    }
}
