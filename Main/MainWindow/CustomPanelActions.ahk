
; ===========================================================================
; 界面宏 · 自定义界面入口（设置中心「界面宏-浮窗」卡片）
; ===========================================================================
OpenUIPanelCustomDesigner(mainWin) {
    idx := 0
    try idx := Integer(mainWin.ui.Query("UIPanelCustomFoldCon>SelectedIndex"))
    if (idx < 0)
        idx := 0
    UIMacroDesignerGui.ShowGui(idx + 1)
}

ResetUIPanelCustomSchema(mainWin) {
    global MyUIMacroGui

    idx := 0
    try idx := Integer(mainWin.ui.Query("UIPanelCustomFoldCon>SelectedIndex"))
    if (idx < 0)
        idx := 0
    foldIndex := idx + 1

    ; 存储键 = 折叠框 ID（与设计器/运行时一致）；取不到才退回数组下标
    fold := ""
    try {
        tableItem := GetTableBySymbol("UI")
        if (tableItem && tableItem.Folds.Length >= foldIndex)
            fold := tableItem.Folds[foldIndex]
    }
    foldKey := UIMacroSchema.FoldKey(fold)
    if (foldKey == "")
        foldKey := String(foldIndex)

    if (Trim(UIMacroSchema.ReadStoreByKey(foldKey)) == "") {
        MsgBox("该面板当前就是自动模式", "自定义界面", "Iconi")
        return
    }
    if (MsgBox("确定清除该面板的自定义界面？", "自定义界面", "YesNo Icon?") != "Yes")
        return

    UIMacroSchema.DeleteStoreByKey(foldKey)

    ; 立即生效：销毁面板缓存，下次触发按键按自动模式重建
    ; 带前台信息的面板 key 是 "<idx>|<hwnd>"，DestroyPanel(idx) 会静默失效，
    ; 所以走 DestroyFoldPanels（按 panelInfo.foldIndex 匹配）。
    try {
        if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.DestroyFoldPanels(foldIndex)
    }
    MsgBox("已恢复为自动模式", "自定义界面", "Iconi")
}
