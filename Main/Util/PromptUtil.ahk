#Requires AutoHotkey v2.0

class PromptData {
    static RegionColor := "FF8A00"
    static RegionThickness := 4

    __New() {
        this.SerialStr := ""
        this.Type := "软件弹窗"
        this.AudioMode := "系统提示音"
        this.TipMode := "文本"
        this.PasteMode := "文本"
        this.PastePosition := "鼠标位置"
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
        this.RegionMode := "显示"
        this.RegionName := ""
        this.PosX := 200
        this.PosY := 200
        this.Width := 200
        this.Height := 100
        this.Color := PromptData.RegionColor
        this.Thickness := PromptData.RegionThickness
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
        this.AudioPlayback := "后台播放"
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

; 旧版区域以起点和长度保存，新版可使用起点和终点。
PromptRangeAxis(start, end, length, resolve) {
    start := PromptInt(resolve(start), -32768, 65534)
    if (end == "")
        return [PromptInt(start, -32768, 32767), PromptInt(resolve(length), 1, 32767)]
    end := PromptInt(resolve(end), -32768, 65534)
    return [PromptInt(Min(start, end), -32768, 32767), PromptInt(Abs(end - start), 1, 32767)]
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
        data.PosX := PromptInt(resolve(data.PosX), -32768, 32767)
        data.PosY := PromptInt(resolve(data.PosY), -32768, 32767)
        if (data.CountDownMode == "显示") {
            if (CountDownKind(data) == "时长") {
                for name, limit in Map("Hour", 8760, "Min", 525600, "Sec", 31536000) {
                    if (data.HasProp(name))
                        data.%name% := PromptInt(resolve(data.%name%), 0, limit)
                }
            }
            TimeExecCountDown(tableItem, index, data)
        } else
            MyCountDownCloseByPosition(CountDownPosKey(data.PosX, data.PosY))
        return
    }
    if (data.Type == "区域高亮") {
        data.RegionName := data.HasProp("RegionName") ? Trim(replace(data.RegionName)) : ""
        if (data.HasProp("RegionMode") && data.RegionMode == "关闭") {
            request := {Type: data.Type, RegionMode: data.RegionMode, RegionName: data.RegionName}
            if (MyShowPrompt(JSON.stringify(request, 0)) == false)
                throw Error(GetLang("提示请求发送失败"))
            return
        }
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
                path := replace(data.AudioPath)
                if (data.HasProp("AudioPlayback") && data.AudioPlayback == "使用播放器")
                    PromptOpenAudioPlayer(path)
                else if (data.AudioWait == "等待结束")
                    PromptPlayAudio(path, true, tableItem, index)
                else {
                    ; 后台音频交给常驻主进程，空闲 Worker 缩容时仍可播放到结束。
                    attributes := FileExist(path)
                    if (!attributes || InStr(attributes, "D"))
                        throw ValueError(GetLang("音频文件无效") ": " path)
                    request := {Type: "音频", AudioPath: SearchImageFullPath(path)}
                    if (MyShowPrompt(JSON.stringify(request, 0)) == false)
                        throw Error(GetLang("提示请求发送失败"))
                }
        }
        return
    }
    switch data.Type {
        case "自由贴":
            if (data.HasProp("PastePosition") && (data.PasteMode == "文本" || data.PasteMode == "图片")) {
                if (data.PastePosition == "固定位置") {
                    data.PosX := PromptInt(resolve(data.PosX), -32768, 32767)
                    data.PosY := PromptInt(resolve(data.PosY), -32768, 32767)
                } else if (data.PastePosition == "鼠标位置") {
                    point := Buffer(8)
                    if (!DllCall("user32\GetCursorPos", "Ptr", point, "Int"))
                        throw OSError()
                    data.PosX := NumGet(point, 0, "Int")
                    data.PosY := NumGet(point, 4, "Int")
                }
            }
        case "临时提示":
            data.Duration := PromptInt(resolve(data.Duration), 1, 600000)
        case "区域高亮":
            x := PromptRangeAxis(data.PosX, data.HasProp("EndPosX") ? data.EndPosX : "", data.Width, resolve)
            y := PromptRangeAxis(data.PosY, data.HasProp("EndPosY") ? data.EndPosY : "", data.Height, resolve)
            data.PosX := x[1], data.Width := x[2]
            data.PosY := y[1], data.Height := y[2]
            data.Duration := PromptInt(resolve(data.Duration), 1, 600000)
            data.Color := PromptData.RegionColor
            data.Thickness := PromptData.RegionThickness
        case "屏幕边缘闪光":
            data.Thickness := PromptInt(resolve(data.Thickness), 1, 100)
            data.Color := StrReplace(Trim(replace(data.Color)), "#")
            if (!RegExMatch(data.Color, "i)^[0-9a-f]{6}$"))
                throw ValueError(GetLang("颜色使用六位十六进制 RGB"))
            data.FlashDuration := PromptInt(resolve(data.FlashDuration), 50, 5000)
            data.FlashCount := PromptInt(resolve(data.FlashCount), 1, 20)
            data.Monitors := replace(data.Monitors)
            if (data.FlashMode == "自定义")
                PromptMonitorNumbers(data.Monitors)
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

PromptPlayAudio(path, wait := false, tableItem := "", index := 0) {
    global RMT_ASM
    if (!IsObject(RMT_ASM))
        RMT_ASM := CLR_LoadLibrary(EnsureRmtDll())
    playback := RMT_ASM.CreateInstance("RMT.AudioPlayback")
    if (!IsObject(playback))
        throw Error(GetLang("后台播放失败") ": RMT.AudioPlayback")

    item := IsObject(tableItem) ? GetItemByIndex(tableItem, index) : ""
    if (IsObject(item) && item.Killed)
        return
    try playback.Start(path)
    catch as err
        throw Error(GetLang("后台播放失败") ": " path "`n" err.Message)

    loop {
        state := playback.State
        if (state == "Failed")
            throw Error(GetLang("后台播放失败") ": " path "`n" playback.ErrorMessage)
        if (state != "Opening" && (!wait || state != "Playing"))
            return
        if (IsObject(item) && item.Killed) {
            playback.Cancel()
            return
        }
        Sleep(25)
    }
}

PromptOpenAudioPlayer(path) {
    attributes := FileExist(path)
    if (!attributes || InStr(attributes, "D") || !RegExMatch(path, "i)\.(wav|mp3|wma|midi?)$"))
        throw ValueError(GetLang("音频文件无效") ": " path)

    result := DllCall("shell32\ShellExecuteW", "Ptr", 0, "Str", "open", "Str", path,
        "Ptr", 0, "Str", A_WorkingDir, "Int", 1, "Ptr")
    if (result <= 32)
        throw Error(GetLang("无法打开音频播放器") ": " path, -1, result)
}

PromptClipboardImage() {
    if (!DllCall("IsClipboardFormatAvailable", "UInt", 2))
        return ""
    static sequence := 0
    pid := DllCall("GetCurrentProcessId", "UInt")
    path := RmtCacheDir() "\RMT-Prompt-" pid "-" A_TickCount "-" (++sequence) ".png"
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
