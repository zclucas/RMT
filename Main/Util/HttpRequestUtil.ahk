#Requires AutoHotkey v2.0

OnHttpRequest(tableItem, cmd, index) {
    data := GetMacroCMDData(StrSplit(cmd, "_")[1])
    resolve := (text) => GetReplaceVarText(tableItem, index, text)
    cancelled := () => tableItem.Items[index].Killed
    result := HttpRequestExecute(data, resolve, cancelled)
    if (cancelled())
        return
    MySetGlobalVariable([data.StatusVar, data.ResponseVar, data.ErrorVar],
        [result.Status, result.Body, result.Error], false)
}

HttpRequestRegisterResults(data) {
    for name in [data.StatusVar, data.ResponseVar, data.ErrorVar]
        MySoftData.GlobalVariMap[name] := true
}

HttpRequestValidate(data) {
    if (!RegExMatch(data.Method, "^(GET|POST|PUT|DELETE)$"))
        throw Error("请选择 GET、POST、PUT 或 DELETE。")
    if (Trim(data.Url) == "")
        throw Error("URL 不能为空。")
    if (!IsInteger(data.TimeoutMs) || data.TimeoutMs < 1 || data.TimeoutMs > 3600000)
        throw Error("超时时间应为 1～3600000 毫秒。")
    if (!RegExMatch(data.Retries, "^\{[^{}\r\n]+\}$"))
        HttpRequestRetryCount(data.Retries)
    if (data.Method != "GET" && !RegExMatch(data.BodyType, "^(JSON|表单|原始文本)$"))
        throw Error("请选择有效的 Body 类型。")
}

HttpRequestRetryCount(value) {
    if (!IsInteger(value) || value < 0 || value > 10)
        throw Error("失败重试次数应为 0～10。")
    return Integer(value)
}

; 表单按行填写 name=value，分别进行 UTF-8 百分号编码。
HttpRequestUrlEncode(text) {
    buf := Buffer(StrPut(text, "UTF-8"))
    count := StrPut(text, buf, "UTF-8") - 1
    result := ""
    loop count {
        n := NumGet(buf, A_Index - 1, "UChar")
        result .= (n >= 65 && n <= 90) || (n >= 97 && n <= 122) || (n >= 48 && n <= 57)
            || InStr("-._~", Chr(n)) ? Chr(n) : Format("%{:02X}", n)
    }
    return result
}

HttpRequestPrepare(data, resolve) {
    HttpRequestValidate(data)
    retries := HttpRequestRetryCount(IsInteger(data.Retries) ? data.Retries : Trim(resolve(data.Retries)))
    url := Trim(resolve(data.Url))
    if (!RegExMatch(url, "i)^https?://[^/\s]+") || RegExMatch(url, "[\r\n]"))
        throw Error("URL 必须以 http:// 或 https:// 开头。")
    headers := Map()
    headers.CaseSense := false
    for line in StrSplit(data.Headers, "`n", "`r") {
        if (Trim(line) == "")
            continue
        p := InStr(line, ":")
        if (p < 2)
            throw Error("Header 请每行填写 名称: 值。")
        name := Trim(SubStr(line, 1, p - 1))
        value := Trim(resolve(SubStr(line, p + 1)))
        if (!RegExMatch(name, "^[!#$%&'*+.^_``|~0-9A-Za-z-]+$") || RegExMatch(value, "[\r\n\x00]"))
            throw Error("Header 名称无效，或值中包含换行。")
        headers[name] := value
    }
    body := ""
    if (data.Method != "GET") {
        if (data.BodyType == "表单") {
            for line in StrSplit(data.Body, "`n", "`r") {
                if (line == "")
                    continue
                p := InStr(line, "=")
                if (!p)
                    throw Error("表单请每行填写 名称=值。")
                body .= (body == "" ? "" : "&") HttpRequestUrlEncode(resolve(SubStr(line, 1, p - 1)))
                    . "=" HttpRequestUrlEncode(resolve(SubStr(line, p + 1)))
            }
        } else
            body := resolve(data.Body)
        if (!headers.Has("Content-Type"))
            headers["Content-Type"] := data.BodyType == "JSON" ? "application/json; charset=utf-8"
                : data.BodyType == "表单" ? "application/x-www-form-urlencoded; charset=utf-8" : "text/plain; charset=utf-8"
    }
    return {Url: url, Headers: headers, Body: body, Retries: retries}
}

; 每次尝试均有总时限；异步请求轮询使宏中止能及时 Abort。
; 不记录 URL/Header/Body 或 COM 异常原文，以免密钥进入日志。
HttpRequestExecute(data, resolve, cancelled := () => false) {
    result := {Status: 0, Body: "", Error: ""}
    try prepared := HttpRequestPrepare(data, resolve)
    catch as e {
        result.Error := e.Message
        return result
    }
    loop prepared.Retries + 1 {
        if (cancelled())
            return {Status: 0, Body: "", Error: "请求已取消"}
        result := {Status: 0, Body: "", Error: ""}
        request := ""
        try {
            request := ComObject("WinHttp.WinHttpRequest.5.1")
            request.SetTimeouts(data.TimeoutMs, data.TimeoutMs, data.TimeoutMs, data.TimeoutMs)
            request.Open(data.Method, prepared.Url, true)
            ; 保留 3xx 状态，避免重定向将自定义认证头转发到其它主机。
            request.Option[6] := false
            request.SetAutoLogonPolicy(2)
            for name, value in prepared.Headers
                request.SetRequestHeader(name, value)
            started := A_TickCount
            request.Send(prepared.Body)
            loop {
                if (cancelled()) {
                    request.Abort()
                    return {Status: 0, Body: "", Error: "请求已取消"}
                }
                if (A_TickCount - started >= data.TimeoutMs) {
                    request.Abort()
                    result.Error := "请求超时"
                    break
                }
                if (request.WaitForResponse(0)) {
                    result.Status := request.Status
                    result.Body := request.ResponseText
                    if (result.Status >= 400)
                        result.Error := "HTTP " result.Status
                    break
                }
                Sleep(15)
            }
        } catch as e {
            ; 仅返回数值错误码，原始消息可能含请求地址或凭据。
            result.Error := "网络请求失败"
            if (e.HasProp("Number"))
                result.Error .= " (" Format("0x{:08X}", e.Number & 0xFFFFFFFF) ")"
        } finally {
            if (IsObject(request)) {
                try request.Abort()
            }
        }
        retryable := result.Status == 0 || result.Status == 408 || result.Status == 429 || result.Status >= 500
        if (!retryable || A_Index > prepared.Retries)
            return result
        ; 短暂退避，也允许终止宏。
        loop 20 {
            if (cancelled())
                return {Status: 0, Body: "", Error: "请求已取消"}
            Sleep(25)
        }
    }
    return result
}
