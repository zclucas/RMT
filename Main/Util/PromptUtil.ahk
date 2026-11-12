#Requires AutoHotkey v2.0

class PromptData {
    __New() {
        this.SerialStr := ""
        this.Type := "软件弹窗"
        this.AudioMode := "系统提示音"
        this.TipMode := "文本"
        this.PasteMode := "文本"
        this.FlashMode := "主屏"
        this.CountDownMode := "显示"
        this.Text := ""
        this.ImageSource := "文件"
        this.TextSource := "直接填写"
        this.PasteTextSource := "直接填写"
        this.ImagePath := ""
        this.AudioPath := ""
        this.Beep := "默认"
        this.Duration := 5000
        this.PasteName := ""
        this.PosX := 200
        this.PosY := 200
        this.Width := 200
        this.Height := 100
        this.Color := "FF8A00"
        this.Thickness := 4
        this.FlashDuration := 300
        this.FlashCount := 2
        this.Monitors := "1"
        this.Seconds := 10
        this.Hour := 0
        this.Min := 0
        this.Sec := 10
        this.Param1 := ""
        this.Param2 := "时长"
        this.WaitEnd := "不等待"
        this.AudioWait := "不等待"
    }
}

PromptTypes() => ["软件弹窗", "音频", "临时提示", "自由贴", "区域高亮", "屏幕边缘闪光", "倒计时"]

PromptBeepModes() => ["默认", "信息", "警告", "错误", "问题"]

PromptUsesEditor(cmd) {
    return cmd != "" && GetLangKey(GetCmdOnlyText(GetCmdStr(StrSplit(cmd, "_", , 2)[1]))) == "提示"
}

PromptInt(value, min, max) {
    if (!IsInteger(value) || value < min || value > max)
        throw ValueError(GetLang("提示参数无效") ": " value)
    return Integer(value)
}

PromptMonitorNumbers(value) {
    monitors := []
    seen := Map()
    for part in StrSplit(value, [",", "，"]) {
        number := PromptInt(Trim(part), 1, MonitorGetCount())
        if (!seen.Has(number)) {
            monitors.Push(number)
            seen[number] := true
        }
    }
    return monitors
}

OnPrompt(tableItem, cmd, index) {
    data := GetMacroCMDData(StrSplit(cmd, "_")[1]).Clone()
    replace := (value) => GetReplaceVarText(tableItem, index, value)
    resolve := (value) => TimeResolveValue(tableItem, index, value)
    if (data.Type == "倒计时") {
        if (data.CountDownMode == "关闭所有") {
            MyCountDownCloseByPosition("")
            return
        }
        if (data.CountDownMode == "显示")
            TimeExecCountDown(tableItem, index, data)
        else {
            x := PromptInt(resolve(data.PosX), -32768, 32767)
            y := PromptInt(resolve(data.PosY), -32768, 32767)
            MyCountDownCloseByPosition(CountDownPosKey(x, y))
        }
        return
    }
    data.Text := replace(data.Text)
    if (data.Type == "音频") {
        switch data.AudioMode {
            case "系统提示音":
                static sounds := Map("默认", 0, "信息", 0x40, "警告", 0x30, "错误", 0x10, "问题", 0x20)
                DllCall("user32\MessageBeep", "UInt", sounds[data.Beep])
            case "系统语音":
                voice := ComObject("SAPI.SpVoice")
                voice.Speak(data.Text, 16) ; 按纯文本朗读
            case "自定义音频":
                SoundPlay(replace(data.AudioPath), data.AudioWait == "等待结束")
        }
        return
    }
    switch data.Type {
        case "临时提示":
            data.Duration := PromptInt(resolve(data.Duration), 1, 600000)
        case "区域高亮", "屏幕边缘闪光":
            data.Thickness := PromptInt(resolve(data.Thickness), 1, 100)
            data.Color := StrReplace(Trim(replace(data.Color)), "#")
            if (!RegExMatch(data.Color, "i)^[0-9a-f]{6}$"))
                throw ValueError(GetLang("颜色使用六位十六进制 RGB"))
            if (data.Type == "区域高亮") {
                data.PosX := PromptInt(resolve(data.PosX), -32768, 32767)
                data.PosY := PromptInt(resolve(data.PosY), -32768, 32767)
                data.Width := PromptInt(resolve(data.Width), 1, 32767)
                data.Height := PromptInt(resolve(data.Height), 1, 32767)
                data.Duration := PromptInt(resolve(data.Duration), 1, 600000)
            } else {
                data.FlashDuration := PromptInt(resolve(data.FlashDuration), 50, 5000)
                data.FlashCount := PromptInt(resolve(data.FlashCount), 1, 20)
                data.Monitors := replace(data.Monitors)
                if (data.FlashMode == "自定义")
                    PromptMonitorNumbers(data.Monitors)
            }
    }
    data.PasteName := Trim(replace(data.PasteName))
    if (data.Type == "自由贴" && data.PasteMode == "文本" && data.PasteTextSource == "剪贴板图文"
        && DllCall("IsClipboardFormatAvailable", "UInt", 2)) {
        data.PasteMode := "图片"
        data.ImageSource := "剪贴板"
    }
    isText := data.Type == "自由贴" && data.PasteMode == "文本" || data.Type == "临时提示" && data.TipMode == "文本"
    source := data.Type == "自由贴" ? data.PasteTextSource : data.TextSource
    if (isText && source != "直接填写")
        data.Text := A_Clipboard
    isImage := data.Type == "自由贴" && data.PasteMode == "图片" || data.Type == "临时提示" && data.TipMode == "图片"
    data.TemporaryImage := false
    if (isImage) {
        if (data.ImageSource == "剪贴板") {
            data.ImagePath := PromptClipboardImage()
            if (data.ImagePath == "")
                return
            data.TemporaryImage := true
        } else {
            path := replace(data.ImagePath)
            attributes := FileExist(path)
            if (attributes == "" || InStr(attributes, "D"))
                throw ValueError(GetLang("找不到图片文件") ": " path)
            data.ImagePath := SearchImageFullPath(path)
        }
    }
    try {
        if (MyShowPrompt(JSON.stringify(data, 0)) == false)
            throw Error(GetLang("提示请求发送失败"))
    }
    catch {
        if (data.TemporaryImage)
            PromptReleaseImage(data.ImagePath)
        throw
    }
}

PromptClipboardImage() {
    if (!DllCall("IsClipboardFormatAvailable", "UInt", 2))
        return ""
    static sequence := 0
    pid := DllCall("GetCurrentProcessId", "UInt")
    path := A_Temp "\RMT-Prompt-" pid "-" A_TickCount "-" (++sequence) ".png"
    SaveClipToBitmap(path)
    return FileExist(path) ? path : ""
}

PromptReleaseImage(path, attempts := 5) {
    if (path == "" || !FileExist(path))
        return
    try FileDelete(path)
    catch {
        if (attempts > 0)
            SetTimer(PromptReleaseImage.Bind(path, attempts - 1), -500)
    }
}
