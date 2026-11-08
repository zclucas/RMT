
    SaveCommandData(RealCommandStr, macroStr, nodeItemID) {
        paramArr := StrSplit(RealCommandStr, "_")
        cmd := RegExReplace(paramArr[1], "\d+")

        ; 映射表：命令 → 文件名
        fileMap := Map(
            GetLang("搜索"), SearchFile,
            GetLang("搜索Pro"), SearchProFile,
            GetLang("搜索All"), SearchAllFile,
            GetLang("搜索Combo"), SearchComboFile,
            GetLang("组合搜索"), SearchComboFile,
            GetLang("搜索Multi"), SearchComboFile,
            GetLang("抓图"), ScreenShotFile,
            GetLang("如果"), CompareFile,
            GetLang("如果Pro"), CompareProFile,
            GetLang("循环"), LoopFile
        )
        if (!fileMap.Has(cmd))
            return

        ItemNumber := this.GetItemNumber(nodeItemID)
        Data := GetMacroCMDData(paramArr[1])
        macroStr := GetLangMacro(macroStr, 2)
        if (cmd == GetLang("循环")) {
            Data.LoopBody := macroStr
        }
        else if (cmd == GetLang("如果Pro")) {
            if (ItemNumber > Data.VariNameArr.Length) {
                if (macroStr == "")
                    RmtDialog.Info("最后的分支不能删除，已清空分支指令")
                Data.DefaultMacro := Trim(macroStr)
            }
            else {
                if (macroStr == "空条件") {
                    Data.MacroArr[ItemNumber] := ""
                }
                else if (macroStr == "") {
                    Data.VariNameArr.RemoveAt(ItemNumber)
                    Data.CompareTypeArr.RemoveAt(ItemNumber)
                    Data.VariableArr.RemoveAt(ItemNumber)
                    Data.LogicTypeArr.RemoveAt(ItemNumber)
                    Data.MacroArr.RemoveAt(ItemNumber)
                }
                else {
                    Data.MacroArr[ItemNumber] := Trim(macroStr)
                }
            }
        }
        else {
            if (ItemNumber == 1)    ;真
                Data.TrueMacro := macroStr
            else
                Data.FalseMacro := macroStr
        }

        SaveMacroCMDData(Data)
    }

    GetItemNumber(nodeItemID) {
        ItemNumber := 1
        PreItemID := this.MacroTreeViewCon.GetPrev(nodeItemID)
        while (PreItemID != 0) {
            ItemNumber += 1
            PreItemID := this.MacroTreeViewCon.GetPrev(PreItemID)
        }
        return ItemNumber
    }
