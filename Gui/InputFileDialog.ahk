#Requires AutoHotkey v2.0
#Include ..\Thread\InputFilePicker.ahk

class InputFileDialog {
    closing := false
    childPID := 0

    __New(helperExe) {
        this.helperExe := helperExe
    }

    Show(title) {
        if (this.closing)
            return ""
        parent := XamlWin.ActiveOwner()
        if (parent && (!DllCall("IsWindowVisible", "Ptr", parent, "Int") || DllCall("IsIconic", "Ptr", parent, "Int")))
            parent := 0
        static sequence := 0
        pid := ProcessExist()
        name := Format("Local\RMT_Picker_{1}_{2}_{3}", pid, A_TickCount, ++sequence)
        memory := SharedMemory(name, InputFilePickerIpc.Size)
        childPID := 0
        child := 0
        try {
            StrPut(SubStr(title, 1, InputFilePickerIpc.TextCapacity - 1), memory.ptr + 4,
                InputFilePickerIpc.TextCapacity, "UTF-16")
            Run(Format('"{}" --input-file {} {} {}', this.helperExe, name, parent, pid), , , &childPID)
            this.childPID := childPID
            ; 同步句柄只指向本次启动的选择器。它退出前不会阻塞主进程的输入与 Worker 消息。
            child := DllCall("OpenProcess", "UInt", 0x100001, "Int", false, "UInt", childPID, "Ptr")
            while (!this.closing && (child
                ? DllCall("WaitForSingleObject", "Ptr", child, "UInt", 0, "UInt") = 258
                : ProcessExist(childPID)))
                Sleep(15)
            if (!this.closing && NumGet(memory.ptr, "Int") = InputFilePickerIpc.Selected)
                return StrGet(memory.ptr + 4, "UTF-16")
            return ""
        } finally {
            if (child && DllCall("WaitForSingleObject", "Ptr", child, "UInt", 0, "UInt") = 258) {
                NumPut("Int", InputFilePickerIpc.CancelRequested, memory.ptr)
                ; 先让文件选择器自行关闭。系统对话框若卡在模态循环，仅结束本次子进程。
                if (DllCall("WaitForSingleObject", "Ptr", child, "UInt", 120, "UInt") = 258) {
                    DllCall("TerminateProcess", "Ptr", child, "UInt", 0)
                    DllCall("WaitForSingleObject", "Ptr", child, "UInt", 200, "UInt")
                }
            }
            if (child)
                DllCall("CloseHandle", "Ptr", child)
            this.childPID := 0
            memory.Close()
        }
    }

    _CloseWindow() {
        this.closing := true
    }
}
