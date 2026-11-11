#Requires AutoHotkey v2.0

; 一次性文件选择进程与主进程之间的共享区。只在本次请求中保存标题和结果路径。
class InputFilePickerIpc {
    static TextCapacity := 32768
    static Size := 4 + 32768 * 2
    static CancelRequested := -1
    static Cancelled := 1
    static Selected := 2
    static Failed := 3
}

RunInputFilePicker(parent, mappingHandle, parentHandle) {
    memory := SharedMemory(InputFilePickerIpc.Size, mappingHandle)
    if NumGet(memory.ptr, "Int") = InputFilePickerIpc.CancelRequested
        return
    title := StrGet(memory.ptr + 4, InputFilePickerIpc.TextCapacity, "UTF-16")
    SetWorkingDir(A_ScriptDir "\..")
    if (parent && !DllCall("IsWindow", "Ptr", parent, "Int"))
        parent := 0
    owner := Gui(parent ? "+ToolWindow +Owner" parent : "")
    owner.Opt("+OwnDialogs")
    placed := 0
    monitor := CheckPicker.Bind()
    SetTimer(monitor, 30)
    try {
        path := FileSelect(3, , title)
        if (path != "" && StrLen(path) < InputFilePickerIpc.TextCapacity) {
            StrPut(path, memory.ptr + 4, InputFilePickerIpc.TextCapacity, "UTF-16")
            NumPut("Int", InputFilePickerIpc.Selected, memory.ptr)
        } else {
            NumPut("Int", InputFilePickerIpc.Cancelled, memory.ptr)
        }
    } catch {
        NumPut("Int", InputFilePickerIpc.Failed, memory.ptr)
    } finally {
        SetTimer(monitor, 0)
        owner.Destroy()
        memory.Close()
    }

    CheckPicker() {
        if (DllCall("WaitForSingleObject", "ptr", parentHandle, "uint", 0, "uint") != 258)
            DllCall("TerminateProcess", "Ptr", -1, "UInt", 0)
        ; FileSelect 可能用额外的 Shell 属主。此进程只显示一个原生文件对话框。
        popup := WinExist("ahk_class #32770 ahk_pid " ProcessExist())
        if (!popup)
            return
        if NumGet(memory.ptr, "Int") = InputFilePickerIpc.CancelRequested {
            DllCall("PostMessageW", "Ptr", popup, "UInt", 0x10, "Ptr", 0, "Ptr", 0, "Int")
            return
        }
        if (parent && popup != placed) {
            try {
                WinGetPos(&x, &y, &w, &h, parent)
                WinGetPos(, , &pw, &ph, popup)
                if WinGetMinMax(parent) = -1
                    return
                cx := x + w // 2, cy := y + h // 2
                px := cx - pw // 2, py := cy - ph // 2
                loop MonitorGetCount() {
                    MonitorGet(A_Index, &ml, &mt, &mr, &mb)
                    if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
                        px := Max(l, Min(px, r - pw)), py := Max(t, Min(py, b - ph))
                        break
                    }
                }
                WinMove(px, py, , , popup)
                placed := popup
            }
        }
    }
}
