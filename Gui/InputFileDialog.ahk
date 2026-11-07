#Requires AutoHotkey v2.0

; 每个请求使用独立的隐藏属主，销毁属主只会关闭本次文件选择。
class InputFileDialog {
    owner := ""

    Show(title) {
        this.owner := Gui()
        this.owner.Opt("+OwnDialogs")
        try return FileSelect(3, , title)
        finally this._CloseWindow()
    }

    _CloseWindow() {
        owner := this.owner
        this.owner := ""
        if (IsObject(owner))
            owner.Destroy()
    }
}
