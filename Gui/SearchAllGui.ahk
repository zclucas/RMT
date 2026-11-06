#Requires AutoHotkey v2.0
#Include SearchProGui.ahk

class SearchAllGui extends SearchProGui {
    CommandName => "搜索All"
    IsAll => true

    BuildAllFields(body) {
        row := body.Add("Grid").Grid_Row(5).Grid_ColumnSpan(3).Margin("0,8,0,4")
        row.Cols("86", "*", "12", "86", "*")
        row.Rows("32", "Auto")
        row.Add("TextBlock").Text(GetLang("坐标数组：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        this._AddEditCombo(row, "AllSaveNameCon", 0, 1)
        row.Add("TextBlock").Grid_Column(3).Text(GetLang("搜索顺序：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
        sort := row.Add("ComboBox").Grid_Column(4).Name("AllSortCon").Height(28).VerticalContentAlignment("Center")
        for label in GetLangArr(["左右优先", "上下优先"])
            sort.Add("ComboBoxItem").Content(label)
        row.Add("TextBlock").Grid_Row(1).Grid_ColumnSpan(5).Margin("0,4,0,0").Text(GetLang("左右优先：先左右后上下；上下优先：先上下后左右。输出 [[x,y],…]，窗口模式为客户区坐标；颜色返回每个匹配像素。"))
            .TextWrapping("Wrap").Foreground("{DynamicResource TextSub}").FontSize(11)
    }

    Init(cmd) {
        super.Init(cmd)
        names := []
        for name in MySoftData.GlobalArrMap
            names.Push(name)
        this._SetCombo("AllSaveNameCon", names, this.Data.AllSaveName)
        this.ui.Update("AllSortCon", "SelectedIndex", this.Data.AllSort == "上下优先" ? "1" : "0")
        ; All uses whole-template matching; the Pro multi-point editor is not applicable.
        this.ui.Update("ImageProcessBtn", "Visibility", "Collapsed")
    }

    CheckIfValid() {
        return super.CheckIfValid() && CheckVarNameIfValid(this.ui.Query("AllSaveNameCon"))
    }

    SaveSearchData() {
        this.Data.AllSaveName := GetVarName(this.ui.Query("AllSaveNameCon"))
        this.Data.AllSort := ["左右优先", "上下优先"][Integer(this.ui.Query("AllSortCon>SelectedIndex")) + 1]
        MySoftData.GlobalArrMap[this.Data.AllSaveName] := true
        super.SaveSearchData()
    }
}
