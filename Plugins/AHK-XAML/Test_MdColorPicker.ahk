#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)

#Include lib/XAML_Host.ahk
#Include lib/XAML_Generator.ahk
#Include lib/XAML_Components.ahk
#Include lib/XAML_Dialog.ahk

global g_testResult := 0

F1:: {
    global g_testResult
    if (IsObject(g_testResult) && g_testResult.Status != "Cancel" && g_testResult.Status != "OK")
        return
    try {
        g_testResult := XColorPicker.Show({
            Title: "RMT Color Picker",
            DefaultColor: "#FF0A84FF",
            Modal: false
        })
        if (g_testResult.Status == "OK")
            MsgBox("HEX: " g_testResult.Color "`nA:" g_testResult.A " R:" g_testResult.R " G:" g_testResult.G " B:" g_testResult.B, "RMT ColorPicker", "64 T4")
    } catch as e {
        MsgBox("Error: " e.Message, "Error", "Iconx 48 T3")
    }
}

Persistent()
