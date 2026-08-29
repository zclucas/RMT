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
        this.Gui := Gui("+AlwaysOnTop +Owner" (IsObject(MainSoftData.MyGui) ? MainSoftData.MyGui.Hwnd : ""), GetLang("表管理"))
        this.Gui.SetFont("s11", "微软雅黑")

        ; 说明
        this.Gui.Add("Text", "w480", GetLang("管理主窗口页签：可新增/重命名/删除表。删除表会同时删除其中的全部宏。"))

        ; 表列表（ListView）
        this.LV := this.Gui.Add("ListView", "w480 h280 vTableLV", ["#", GetLang("表名"), GetLang("类型"), GetLang("条目数")])
        this.LV.OnEvent("DoubleClick", (*) => this._Rename())
        this._ReloadList()

        ; 按钮行
        btnRow := this.Gui.Add("Button", "w100 h30 Default x10", GetLang("新增表")).OnEvent("Click", (*) => this._Add())
        this.Gui.Add("Button", "w100 h30 x120", GetLang("重命名")).OnEvent("Click", (*) => this._Rename())
        this.Gui.Add("Button", "w100 h30 x230", GetLang("删除表")).OnEvent("Click", (*) => this._Delete())
        this.Gui.Add("Button", "w100 h30 x340", GetLang("关闭")).OnEvent("Click", (*) => this._Close())

        this.Gui.OnEvent("Escape", (*) => this._Close())
        this.Gui.OnEvent("Close", (*) => this._Close())
        this.Gui.Show()
    }

    _ReloadList() {
        this.LV.Delete()
        for t in MySoftData.TableInfo {
            this.LV.Add("", t.Index, t.Name, t.Symbol, t.Items.Length)
        }
    }

    _Selected() {
        row := this.LV.GetNext(0, "Focused")
        if (!row)
            return ""
        return MySoftData.TableInfo[row]
    }

    _Add() {
        result := InputBox(GetLang("请输入新表名称："), GetLang("新增表"), "w300 h100", "")
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

    ; 选择新表类型：Normal/String/Menu/UI/Voice/Timing/SubMacro/Replace
    _AskSymbol() {
        m := Menu()
        defs := [["Normal", GetLang("按键宏")], ["String", GetLang("字串宏")], ["Menu", GetLang("菜单宏")],
            ["UI", GetLang("界面宏")], ["Voice", GetLang("语音宏")], ["Timing", GetLang("定时宏")],
            ["SubMacro", GetLang("宏")], ["Replace", GetLang("按键替换")]]
        result := ""
        for def in defs {
            ; 必须绑定值而非闭包捕获循环变量（AHK v2 箭头函数捕获引用，所有项会取到最后一个）
            m.Add(def[2], TableMgrGui._PickSymbol.Bind(&result, def[1]))
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
        result := InputBox(GetLang("请输入新表名称："), GetLang("重命名表"), "w300 h100", t.Name)
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
        result := MsgBox(Format(GetLang("确定删除表「{1}」及其全部 {2} 条宏吗？"), t.Name, t.Items.Length), GetLang("删除表"), 1)
        if (result == "Cancel")
            return
        RemoveTable(t.ID)
        this._ReloadList()
        ; §18 表结构变更显式落盘
        SaveAllTableItemInfo(MySoftData.TableInfo)
        OnSaveSetting()
        SafeReload()
    }

    _Close() {
        this.closed := true
        this.Gui.Destroy()
    }
}
