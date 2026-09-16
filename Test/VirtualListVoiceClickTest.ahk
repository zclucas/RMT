#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\Main\VirtualListHost.ahk

global DeferredTag := ""
global DeferredCallback := ""
global VoiceCallTable := ""
global VoiceCallIndex := 0
global TimerProbeHit := false

CheckIsStringMacroTable(*) => false
CheckIsTimingMacroTable(*) => false
CheckIsMenuMacroTable(*) => false
GetTableSymbol(*) => "Voice"

OnItemVoiceTriggerSetting(tableItem, index, *) {
    global VoiceCallTable, VoiceCallIndex
    VoiceCallTable := tableItem
    VoiceCallIndex := index
}

MarkTimerProbe(*) {
    global TimerProbeHit
    TimerProbeHit := true
}

class ProbeVirtualListHost extends VirtualListHost {
    _DeferDialog(tag, fn) {
        global DeferredTag, DeferredCallback
        DeferredTag := tag
        DeferredCallback := fn
    }
}

try {
    timerHost := VirtualListHost("")
    timerHost._DeferDialog("TimerProbe", MarkTimerProbe)
    Sleep(120)
    if (!TimerProbeHit)
        throw Error("deferred dialog wrapper did not run")

    table := { Index: 3 }
    host := ProbeVirtualListHost("")
    host._EditTK(table, 7, "")
    if (DeferredTag != "VoiceTrigger" || !HasMethod(DeferredCallback, "Call"))
        throw Error("voice trigger click was not deferred")
    DeferredCallback.Call()
    if (ObjPtr(VoiceCallTable) != ObjPtr(table) || VoiceCallIndex != 7)
        throw Error("deferred voice trigger callback lost its target")
    FileAppend("PASS virtual voice trigger click is deferred`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL " e.Message " @ " e.Line "`n", "*")
    ExitApp(1)
}
