#Requires AutoHotkey v2.0
#Include SearchProGui.ahk

class SearchAllGui extends SearchProGui {
    CommandName => "搜索All"
    IsAll => true

    SortOrders => ["上下左右", "上下右左", "下上左右", "下上右左"]

    BuildAllSortField(coord) {
        coord.Add("TextBlock").Grid_Row(2).Text(GetLang("搜索顺序：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        sort := coord.Add("ComboBox").Grid_Row(2).Grid_Column(2).Grid_ColumnSpan(3).Name("AllSortCon").Height(28).MinHeight(28)
            .VerticalAlignment("Center").VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        for label in GetLangArr(this.SortOrders)
            sort.Add("ComboBoxItem").Content(label)
    }

    BuildAllArrayField(saveRow) {
        coord := saveRow.Add("Grid").Grid_Column(2)
        coord.Cols("Auto", "8", "*")
        coord.Add("TextBlock").Text(GetLang("坐标数据：")).VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        this._AddEditCombo(coord, "AllSaveNameCon", 0, 2)
    }

    Init(cmd) {
        super.Init(cmd)
        names := []
        for name in MySoftData.GlobalArrMap
            names.Push(name)
        this._SetCombo("AllSaveNameCon", names, this.Data.AllSaveName)
        savedOrder := this.Data.AllSort == "左右优先" ? "上下左右" : this.Data.AllSort
        sortIndex := -1
        for index, order in this.SortOrders {
            if (order == savedOrder) {
                sortIndex := index - 1
                break
            }
        }
        this.ui.Update("AllSortCon", "SelectedIndex", String(sortIndex))
        if (sortIndex == -1)
            this.ui.Update("AllSortCon", "ToolTip", GetLang(savedOrder))
    }

    CheckIfValid() {
        return super.CheckIfValid() && CheckVarNameIfValid(this.ui.Query("AllSaveNameCon"))
    }

    SaveSearchData() {
        this.Data.AllSaveName := GetVarName(this.ui.Query("AllSaveNameCon"))
        sortIndex := this.ui.Query("AllSortCon>SelectedIndex")
        if (IsNumber(sortIndex) && sortIndex >= 0)
            this.Data.AllSort := this.SortOrders[Integer(sortIndex) + 1]
        this.Data.MouseActionType := "无动作"
        MySoftData.GlobalArrMap[this.Data.AllSaveName] := true
        super.SaveSearchData()
    }
}
