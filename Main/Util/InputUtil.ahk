#Requires AutoHotkey v2.0

InputPopUp(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    isHide := false
    InputBoxSureAction(Content) {
        MySetGlobalVariable([Data.SaveName], [Content], false)
    }
    InputBoxHideAction() {
        isHide := true
    }
    Label := GetLang("变量名：") Data.SaveName
    Content := ""
    if (MySoftData.VariableMap.Has(Data.SaveName))
        Content := MySoftData.VariableMap[Data.SaveName]

    MyInputGui.SureAction := InputBoxSureAction
    MyInputGui.HideAction := InputBoxHideAction
    MyInputGui.ShowGui(Label, Content)
    while (!isHide) {
        Sleep(200)
    }
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputStateValue(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    isHide := false
    InputBoxTrueAction() {
        MySetGlobalVariable([Data.SaveName], [1], false)
    }
    InputBoxFalseAction() {
        MySetGlobalVariable([Data.SaveName], [0], false)
    }
    InputBoxHideAciton() {
        isHide := true
    }
    MyInputBtnGui.TrueAction := InputBoxTrueAction
    MyInputBtnGui.FalseAction := InputBoxFalseAction
    MyInputBtnGui.HideAction := InputBoxHideAciton
    MyInputBtnGui.ShowGui(1)
    while (!isHide) {
        Sleep(200)
    }
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputContinue(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    isHide := false
    InputBtnHideAciton() {
        isHide := true
    }
    MyInputBtnGui.HideAction := InputBtnHideAciton
    MyInputBtnGui.ShowGui(2)
    while (!isHide) {
        Sleep(200)
    }
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}

InputContinueAndCencel(Data, tableItem, index) {
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_暂停所有宏")

    isHide := false
    InputBtnCancelAciton() {
        if (Data.CancelType == "终止当前宏")
            MyStopMacro(tableItem.Index, index)
        if (Data.CancelType == "终止所有宏")
            MyExcuteRMTCMDAction("RMT指令_宏控制_终止所有宏")
    }
    InputBtnHideAciton() {
        isHide := true
    }
    MyInputBtnGui.CancelAction := InputBtnCancelAciton
    MyInputBtnGui.HideAction := InputBtnHideAciton
    MyInputBtnGui.ShowGui(3)
    while (!isHide) {
        Sleep(200)
    }
    if (Data.PauseType == "暂停所有宏")
        MyExcuteRMTCMDAction("RMT指令_宏控制_恢复所有宏")
}
