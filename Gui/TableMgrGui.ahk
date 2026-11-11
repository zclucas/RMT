#Requires AutoHotkey v2.0
; ============================================================
; TableMgrGui — 动态表管理（新增/重命名/删除表）
; 新体系下表集合是动态的：Symbol 决定语义分派，Name 可改，Order 决定显示顺序。
; 表删除会连带删除该表全部条目；删除前确认。
; ============================================================

class TableMgrGui {
    static instance := ""

    static ShowGui() {
        if (IsObject(TableMgrGui.instance) && TableMgrGui.instance.closed == false)
            return
        TableMgrGui.instance := TableMgrGui()
        TableMgrGui.instance._Build()
    }

    _Build() {
        this.closed := false
        panel := XAML_Generator("StackPanel").Margin("16")
        panel.Add("TextBlock").Text(GetLang("管理主窗口页签：可新增/重命名/删除表。删除表会同时删除其中的全部宏。")).TextWrapping("Wrap").Margin("0,0,0,12")
        header := panel.Add("Grid").Margin("8,0,8,6")
        header.Cols("45", "*", "110", "80")
        for i, label in ["#", GetLang("表名"), GetLang("类型"), GetLang("条目数")]
            header.Add("TextBlock").Grid_Column(i - 1).Text(label).FontWeight("Bold")
        panel.Add("ListBox").Name("TableLV").Height(280).HorizontalContentAlignment("Stretch")
        buttons := panel.Add("StackPanel").Orientation("Horizontal").Margin("0,12,0,0")
        for i, label in [GetLang("新增表"), GetLang("重命名"), GetLang("删除表"), GetLang("关闭")]
            buttons.Add("Button").Name("TableBtn" i).Content(label).Width(100).MinHeight(30).Margin("0,0,8,0").IsCancel(i == 4 ? "True" : "False")
        this.ui := XamlWin.Create(GetLang("表管理"), panel, 560, 445)
        this.ui.OnEvent("TableLV", "MouseDoubleClick", (*) => this._Rename())
        this.ui.OnEvent("TableBtn1", "Click", (*) => this._Add())
        this.ui.OnEvent("TableBtn2", "Click", (*) => this._Rename())
        this.ui.OnEvent("TableBtn3", "Click", (*) => this._Delete())
        this.ui.OnEvent("TableBtn4", "Click", (*) => this._Close())
        this.ui.OnEvent("Window", "Closing", (*) => this._OnClosed())
        this._ReloadList()
        owner := IsObject(MainSoftData.MyGui) ? MainSoftData.MyGui.Hwnd : ""
        if (XamlWin.Open(this.ui, "", owner))
            this.Gui := {Hwnd: this.ui.wpfHwnd}
        else
            this._Close()
    }

    _ReloadList() {
        this.ui.Update("TableLV", "ClearItems", "")
        for t in MySoftData.TableInfo {
            row := XAML_Generator("Grid")
            row.Cols("45", "*", "110", "80")
            for i, value in [t.Index, t.Name, t.Symbol, t.Items.Length]
                row.Add("TextBlock").Grid_Column(i - 1).Text(String(value)).TextTrimming("CharacterEllipsis")
            this.ui.Update("TableLV", "AddXamlItem", row.ToString())
        }
    }

    _Selected() {
        selected := this.ui.Query("TableLV>SelectedIndex")
        if (!IsNumber(selected) || Integer(selected) < 0)
            return ""
        row := Integer(selected) + 1
        return row <= MySoftData.TableInfo.Length ? MySoftData.TableInfo[row] : ""
    }

    _Add() {
        result := RmtDialog.Input(GetLang("请输入新表名称："), GetLang("新增表"), "")
        if (result.Result == "Cancel" || Trim(result.Value) == "")
            return
        name := Trim(result.Value)

        ; 选择表类型（Symbol）——决定该表的语义分派
        symbol := this._AskSymbol()
        if (symbol == "")
            return

        AddTable(symbol, name)
        this._ReloadList()
        ; §18 表结构变更不依赖「应用并保存」写宏表：此处显式落盘全部表+表集合
        SaveAllTableItemInfo(MySoftData.TableInfo)
        ; 表集合变化需重建 UI：先保存再重载（SafeReload 保留配置并重启主窗口）
        OnSaveSetting()
        SafeReload()
    }

    _AskSymbol() {
        m := Menu()
        result := ""
        for def in MacroCategoryDefs() {
            ; 网络服务只绑定内置网络宏表。
            if (def[1] == "Network")
                continue
            ; 必须绑定值而非闭包捕获循环变量（AHK v2 箭头函数捕获引用，所有项会取到最后一个）
            m.Add(GetLang(def[2]), TableMgrGui._PickSymbol.Bind(&result, def[1]))
        }
        m.Show()
        return result
    }

    static _PickSymbol(&result, symbol, *) {
        result := symbol
    }

    _Rename() {
        t := this._Selected()
        if (!t)
            return
        result := RmtDialog.Input(GetLang("请输入新表名称："), GetLang("重命名表"), t.Name)
        if (result.Result == "Cancel" || Trim(result.Value) == "")
            return
        RenameTable(t.ID, Trim(result.Value))
        this._ReloadList()
        ; §18 表结构变更显式落盘
        SaveAllTableItemInfo(MySoftData.TableInfo)
        OnSaveSetting()
        SafeReload()
    }

    _Delete() {
        t := this._Selected()
        if (!t)
            return
        result := RmtDialog.Confirm(Format(GetLang("确定删除表「{1}」及其全部 {2} 条宏吗？"), t.Name, t.Items.Length), GetLang("删除表"))
        if (!result)
            return
        RemoveTable(t.ID)
        this._ReloadList()
        ; §18 表结构变更显式落盘
        SaveAllTableItemInfo(MySoftData.TableInfo)
        OnSaveSetting()
        SafeReload()
    }

    _Close() {
        if (IsObject(this.ui))
            this.ui.Update("Window", "Close", "")
        this._OnClosed()
    }

    _OnClosed() {
        this.closed := true
        this.ui := ""
        this.Gui := ""
    }
}
