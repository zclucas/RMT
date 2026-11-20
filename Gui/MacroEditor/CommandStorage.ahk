
    SaveCommandData(RealCommandStr, macroStr, nodeItemID) {
        paramArr := StrSplit(RealCommandStr, "_")
        cmd := GetCommandKey(GetCmdOnlyText(paramArr[1]))
        static branchCommands := Map("搜索", true, "搜索Pro", true, "搜索All", true, "搜索Combo", true, "组合搜索", true,
            "搜索Multi", true, "抓图", true, "如果", true, "如果Pro", true, "循环", true)
        if (!branchCommands.Has(cmd))
            return

        ItemNumber := this.GetItemNumber(nodeItemID)
        Data := GetMacroCMDData(paramArr[1])
        macroStr := GetLangMacro(macroStr, 2)
        if (cmd == "循环") {
            Data.LoopBody := macroStr
        }
        else if (cmd == "如果Pro") {
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
