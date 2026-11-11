#Requires AutoHotkey v2.0
#Include ..\Thread\InputFilePicker.ahk

class InputFileDialog {
    closing := false

    __New(helperExe) {
        this.helperExe := helperExe
    }

    Show(title) {
        if (this.closing)
            return ""
        parent := XamlWin.ActiveOwner()
        if (parent && (!DllCall("IsWindowVisible", "Ptr", parent, "Int") || DllCall("IsIconic", "Ptr", parent, "Int")))
            parent := 0
        memory := SharedMemory(InputFilePickerIpc.Size)
        child := 0
        try {
            StrPut(SubStr(title, 1, InputFilePickerIpc.TextCapacity - 1), memory.ptr + 4,
                InputFilePickerIpc.TextCapacity, "UTF-16")
            helper := LaunchWorkerProcess(this.helperExe, "--input-file " parent, memory.hMap)
            child := helper.handle
            ; 等待时保持主进程的输入与 Worker 消息处理。
            while (!this.closing && DllCall("WaitForSingleObject", "Ptr", child, "UInt", 0, "UInt") == 258)
                Sleep(15)
            if (!this.closing && NumGet(memory.ptr, "Int") = InputFilePickerIpc.Selected)
                return StrGet(memory.ptr + 4, InputFilePickerIpc.TextCapacity, "UTF-16")
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
            memory.Close()
        }
    }

    _CloseWindow() {
        this.closing := true
    }
}
