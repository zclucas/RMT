
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
    global SettingFile, SettingSection
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

    ; 旧下标文件也要能清掉（兼容迁移前保存的配置）
    legacyKey := String(foldIndex)
    hasCurrent := (FileExist(UIMacroSchema.StorePathByKey(foldKey)) != "")
    hasLegacy := (foldKey != legacyKey && FileExist(UIMacroSchema.StorePathByKey(legacyKey)) != "")

    ; v0.1 遗留：自定义界面还可能存在聚合字段 MainSoftData.UIPanelCustom 里
    ; （形状 {折叠框下标: schema}，键是**下标**不是 fold.ID）。
    ; 运行时 _GetCustomSchema 在文件缺失时会回退读它 —— 只删文件会让「已恢复为自动模式」
    ; 变成假提示，所以它也算「有可删内容」，并且要在下面一起清掉。
    legacyDict := ""
    try legacyRaw := MainSoftData.UIPanelCustom
    catch
        legacyRaw := ""
    if (Trim(String(legacyRaw)) != "") {
        legacyJson := UIMacroSchema.DecodeStore(legacyRaw)
        try legacyDict := JSON.parse(String(legacyJson), , false)
        catch
            legacyDict := ""
    }
    hasLegacyDict := (IsObject(legacyDict) && ObjHasOwnProp(legacyDict, legacyKey))

    if (!hasCurrent && !hasLegacy && !hasLegacyDict) {
        MsgBox("该面板当前就是自动模式", "自定义界面", "Iconi")
        return
    }
    if (MsgBox("确定清除该面板的自定义界面？", "自定义界面", "YesNo Icon?") != "Yes")
        return

    if (hasCurrent)
        UIMacroSchema.DeleteStoreByKey(foldKey)
    if (hasLegacy)
        UIMacroSchema.DeleteStoreByKey(legacyKey)
    if (hasLegacyDict) {
        ; 全程 try 包住：清理遗留字段失败不能影响「已恢复」主流程
        try {
            legacyDict.DeleteProp(legacyKey)
            newRaw := ""
            ; 注意：本项目对某些对象 JSON.stringify 会返回空串，
            ; 空串一律不写回，宁可留旧数据也不能把其它面板的配置抹掉。
            try newRaw := JSON.stringify(legacyDict, 0)
            catch
                newRaw := ""
            if (newRaw != "") {
                storedRaw := UIMacroSchema.EncodeStore(newRaw)
                if (storedRaw != "") {
                    MainSoftData.UIPanelCustom := storedRaw
                    CfgWrite(storedRaw, SettingFile, SettingSection, "UIPanelCustom")
                }
            }
        }
    }

    ; 立即生效：销毁面板缓存，下次触发按键按自动模式重建
    ; 带前台信息的面板 key 是 "<idx>|<hwnd>"，DestroyPanel(idx) 会静默失效，
    ; 所以走 DestroyFoldPanels（按 panelInfo.foldIndex 匹配）。
    try {
        if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.DestroyFoldPanels(foldIndex)
    }
    MsgBox("已恢复为自动模式", "自定义界面", "Iconi")
}
