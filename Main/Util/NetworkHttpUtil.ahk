#Requires AutoHotkey v2.0
; =====================================================================
; §23 网络触发 —— HTTP 低层工具（Main\Util\NetworkHttpUtil.ahk）
;
; 职责（架构文档 §3 NetworkHttpUtil_ 函数集）：
;   1. ws2_32.dll 封装：WSAStartup / socket(AF_INET,SOCK_STREAM) / ioctlsocket(FIONBIO 非阻塞)
;      / bind(127.0.0.1:端口) / listen(8) / accept / recv / send / closesocket / WSACleanup
;   2. 最小 HTTP/1.1 子集解析：请求行（method/path/version）、headers（Key: Value）、
;      query string、Content-Length body；响应固定 Connection: close、单连接单请求。
;      不支持 keep-alive / chunked / TLS / 长连接（P0 范围外）。
;   3. 请求参数解析：query / x-www-form-urlencoded 表单 / JSON body 扁平键值对提取。
;   4. 统一响应体构建：一律 HTTP 200 + text/plain；成功 body 为 "OK"，出错 body 为问题文本
;      （用户拍板：不用状态码区分业务结果，问题写进 body 即可）。
;   5. NetworkCode 错误码常量类（不再进入 HTTP 状态行，仅作内部日志标签，禁止散落字符串字面量）。
;
; 线程模型：所有函数仅做微秒级 CPU 操作（DllCall/字符串解析），供 NetworkServer
; 的 50ms SetTimer 轮询回调（伪线程）同步调用，内部禁止 Sleep / 消息泵 / 长循环。
; =====================================================================

; ---------------- 错误码常量（架构文档 §7-3：集中定义，禁止散落字面量） ----------------
class NetworkCode {
    static OK := "OK"
    static MACRO_NOT_FOUND := "MACRO_NOT_FOUND"
    static MACRO_FORBIDDEN := "MACRO_FORBIDDEN"
    static SUSPENDED := "SUSPENDED"
    static INVALID_VARIABLE := "INVALID_VARIABLE"
    static BAD_REQUEST := "BAD_REQUEST"
    static NETWORK_TABLE_DISABLED := "NETWORK_TABLE_DISABLED"
    static METHOD_NOT_ALLOWED := "METHOD_NOT_ALLOWED"
}

; ---------------- 请求对象 ----------------
; 由 ParseHttpRequest 构造并交由 NetworkServer 校验/消费
class HttpRequest {
    __New() {
        this.method := ""       ;大写 HTTP 方法（GET/POST/PUT/...）
        this.path := ""         ;URL path（不含 query，已去首部 "/"）
        this.macroID := ""      ;触发宏 ID（path 首段经 UrlDecode；空串=路径为空）
        this.query := Map()     ;query string 键值对（已 UrlDecode）
        this.headers := Map()   ;headers（键统一小写）
        this.body := ""         ;请求体原文（UTF-8 解码后字符串）
        this.clientIP := ""     ;来源 IP（默认 127.0.0.1）
        this.recvTick := 0      ;完整请求组装完成时刻（A_TickCount，日志用）
    }
}

; ---------------- 每连接接收状态 ----------------
; buf 为字节 Buffer（非 String）：避免 UTF-8 多字节序列跨 recv 分包被截断，
; 仅在头部终止符定位 / 请求完整时才做 UTF-8 解码（与架构类图 String 类型的偏差已在交付说明中记录）
class NetworkConnState {
    __New(socket, clientIP := "127.0.0.1") {
        this.socket := socket
        this.buf := Buffer(0)       ;已接收原始字节（增量追加）
        this.clientIP := clientIP   ;来源 IP（accept 时取自 sockaddr_in）
        this.startTick := A_TickCount   ;首字节到达时刻（单请求 5s 收包超时判定）
    }
}

; ---------------- Winsock 生命周期 ----------------

; WSAStartup(2.2)；已启动则直接返回 0。返回 0=成功，非 0=WSA 错误码
WinsockStartup() {
    static started := false
    if (started)
        return 0
    wsaData := Buffer(408)  ;WSADATA x64 实际 408 字节，多分配无害
    err := DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int")
    if (err != 0)
        return err
    started := true
    return 0
}

; WSACleanup（仅退出清理时调用；Restart 不做 Cleanup，避免影响系统内其他 Winsock 使用计数）
WinsockCleanup() {
    DllCall("ws2_32\WSACleanup", "Int")
}

; 创建非阻塞监听 socket 并 bind+listen。
; 返回 socket 句柄；失败返回 0 且 errMsg 给出人类可读原因（端口占用 err==10048）。
TcpListen(port, bindIP := "127.0.0.1", &errMsg := "") {
    errMsg := ""
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")   ;AF_INET, SOCK_STREAM, IPPROTO_TCP
    if (sock == 0 || sock == -1) {
        errMsg := Format("创建 socket 失败（WSAError={1}）", DllCall("ws2_32\WSAGetLastError"))
        return 0
    }
    ; FIONBIO=0x8004667E：置非阻塞（accept/recv 永不阻塞伪线程）
    mode := 1
    DllCall("ws2_32\ioctlsocket", "Ptr", sock, "Int", 0x8004667E, "Int*", &mode, "Int")
    addr := Buffer(16, 0)   ;sockaddr_in
    NumPut("UShort", 2, addr, 0)                                            ;sin_family=AF_INET
    NumPut("UShort", DllCall("ws2_32\htons", "UShort", port, "UShort"), addr, 2)    ;sin_port（网络字节序）
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", bindIP, "UInt"), addr, 4)    ;sin_addr
    if (DllCall("ws2_32\bind", "Ptr", sock, "Ptr", addr, "Int", 16, "Int") != 0) {
        err := DllCall("ws2_32\WSAGetLastError")
        DllCall("ws2_32\closesocket", "Ptr", sock)
        errMsg := (err == 10048)
            ? Format("端口 {1} 已被占用（bind 失败 WSAError=10048）", port)
            : Format("bind {2}:{1} 失败（WSAError={3}）", port, bindIP, err)
        return 0
    }
    if (DllCall("ws2_32\listen", "Ptr", sock, "Int", 8, "Int") != 0) {
        err := DllCall("ws2_32\WSAGetLastError")
        DllCall("ws2_32\closesocket", "Ptr", sock)
        errMsg := Format("listen 失败（WSAError={1}）", err)
        return 0
    }
    return sock
}

; 非阻塞 accept：无连接/出错返回 0；成功返回 client socket 并经 clientIP 输出来源 IPv4
TcpAccept(listenSocket, &clientIP := "") {
    clientIP := ""
    sa := Buffer(16, 0)
    salen := 16
    client := DllCall("ws2_32\accept", "Ptr", listenSocket, "Ptr", sa, "Int*", &salen, "Ptr")
    if (client == 0 || client == -1)
        return 0    ;WSAEWOULDBLOCK 或瞬时错误：直接返回，不阻塞轮询 tick
    ; Windows 下 accept 出的 socket 不继承非阻塞属性，须单独置 FIONBIO
    mode := 1
    DllCall("ws2_32\ioctlsocket", "Ptr", client, "Int", 0x8004667E, "Int*", &mode, "Int")
    clientIP := NumGet(sa, 4, "UChar") "." NumGet(sa, 5, "UChar") "." NumGet(sa, 6, "UChar") "." NumGet(sa, 7, "UChar")
    return client
}

; 非阻塞 recv 一块数据并追加到 conn.buf（字节级，防 UTF-8 分包截断）
; 返回 "data" | "closed"（对端关闭） | "again"（WOULDBLOCK 无数据） | "error"
TcpRecv(socket, conn) {
    chunk := Buffer(4096)
    r := DllCall("ws2_32\recv", "Ptr", socket, "Ptr", chunk, "Int", 4096, "Int", 0, "Int")
    if (r == -1) {
        err := DllCall("ws2_32\WSAGetLastError")
        return (err == 10035) ? "again" : "error"   ;10035=WSAEWOULDBLOCK
    }
    if (r == 0)
        return "closed"
    old := conn.buf
    merged := Buffer(old.Size + r)
    if (old.Size > 0) {
        DllCall("RtlMoveMemory", "Ptr", merged.Ptr, "Ptr", old.Ptr, "Ptr", old.Size)
    }
    DllCall("RtlMoveMemory", "Ptr", merged.Ptr + old.Size, "Ptr", chunk.Ptr, "Ptr", r)
    conn.buf := merged
    return "data"
}

; 发送完整响应（UTF-8 字节）。非阻塞 send 可能部分发送/WOULDBLOCK：循环补发直到完毕。
; 响应体极小（<1KB）且走回环接口，瞬时必完成；上限 1000 次防死循环。
TcpSendAll(socket, data) {
    size := StrPut(data, "UTF-8") - 1
    if (size <= 0)
        return true
    buf := Buffer(size)
    StrPut(data, buf, "UTF-8")
    sent := 0
    loop 1000 {
        n := DllCall("ws2_32\send", "Ptr", socket, "Ptr", buf.Ptr + sent, "Int", size - sent, "Int", 0, "Int")
        if (n == -1) {
            if (DllCall("ws2_32\WSAGetLastError") == 10035)
                continue
            return false
        }
        sent += n
        if (sent >= size)
            return true
    }
    return false
}

; 关闭 socket（0/-1 静默忽略，可重复调用）
TcpClose(socket) {
    if (socket != 0 && socket != -1)
        DllCall("ws2_32\closesocket", "Ptr", socket)
}

; ---------------- 请求解析 ----------------

; 在字节 Buffer 中定位头部终止符 "\r\n\r\n"（0 基偏移）；未找到返回 -1
NetworkHttpFindHeaderEnd(buf) {
    size := buf.Size
    if (size < 4)
        return -1
    loop size - 3 {
        if (NumGet(buf, A_Index - 1, "UChar") == 0x0D && NumGet(buf, A_Index, "UChar") == 0x0A
            && NumGet(buf, A_Index + 1, "UChar") == 0x0D && NumGet(buf, A_Index + 2, "UChar") == 0x0A)
            return A_Index - 1
    }
    return -1
}

; 解析完整请求字符串（头部 ASCII + body UTF-8）。
; 解析失败（请求行非法/header 残缺）抛 Error(NetworkCode.BAD_REQUEST, , 人类可读原因)。
; Content-Length 与实际 body 长度的比对由 NetworkServer 收包层保证（收满才调用本函数）。
ParseHttpRequest(raw, clientIP) {
    headerEnd := InStr(raw, "`r`n`r`n")
    if (!headerEnd)
        throw Error(NetworkCode.BAD_REQUEST, , "请求缺少头部终止符")
    headerPart := SubStr(raw, 1, headerEnd - 1)
    body := SubStr(raw, headerEnd + 4)
    if (StrLen(headerPart) > 16384)
        throw Error(NetworkCode.BAD_REQUEST, , "请求头超过 16KB 限制")

    lines := StrSplit(headerPart, "`r`n")
    if (lines.Length < 1)
        throw Error(NetworkCode.BAD_REQUEST, , "空请求")
    reqLine := Trim(lines[1])
    parts := StrSplit(reqLine, " ")
    if (parts.Length != 3)
        throw Error(NetworkCode.BAD_REQUEST, , "请求行非法: " reqLine)
    method := StrUpper(parts[1])
    target := parts[2]
    version := parts[3]
    if (method == "" || !RegExMatch(method, "^[A-Z]+$"))
        throw Error(NetworkCode.BAD_REQUEST, , "请求方法非法: " method)
    if (InStr(version, "HTTP/") != 1)
        throw Error(NetworkCode.BAD_REQUEST, , "HTTP 版本非法: " version)

    ; target = "/{宏ID}?k=v" → path + query
    qPos := InStr(target, "?")
    if (qPos) {
        pathRaw := SubStr(target, 1, qPos - 1)
        queryStr := SubStr(target, qPos + 1)
    } else {
        pathRaw := target
        queryStr := ""
    }
    path := (SubStr(pathRaw, 1, 1) == "/") ? SubStr(pathRaw, 2) : pathRaw
    macroID := UrlDecode(path)
    ; 多级路径（含 "/"）不可能是合法宏 ID，交由 ItemMap 查找自然 404，此处不特判

    req := HttpRequest()
    req.method := method
    req.path := path
    req.macroID := macroID
    req.query := ParseQueryStr(queryStr)
    req.body := body
    req.clientIP := clientIP == "" ? "127.0.0.1" : clientIP
    for i, line in lines {
        if (i == 1)
            continue
        if (Trim(line) == "")
            continue
        cPos := InStr(line, ":")
        if (!cPos)
            continue
        req.headers[StrLower(Trim(SubStr(line, 1, cPos - 1)))] := Trim(SubStr(line, cPos + 1))
    }
    return req
}

; query string 解析（k=v&k2=v2；无值 k 允许；k 为空跳过）
ParseQueryStr(str) {
    result := Map()
    for seg in StrSplit(str, "&") {
        if (seg == "")
            continue
        eq := InStr(seg, "=")
        if (eq) {
            k := UrlDecode(SubStr(seg, 1, eq - 1))
            v := UrlDecode(SubStr(seg, eq + 1))
        } else {
            k := UrlDecode(seg)
            v := ""
        }
        if (k != "")
            result[k] := v
    }
    return result
}

; x-www-form-urlencoded 表单体解析（与 query 同规则）
ParseFormBody(body) {
    return ParseQueryStr(body)
}

; JSON body 扁平键值对提取（P0 仅扁平 KV）：
;   - String/Integer/Float → String() 收编为文本值（数值/布尔先按字符串收编，PRD P0-5）
;   - 嵌套 Object/Map/Array → 整键忽略 + 记日志（不做 a.b 展平，架构结论 3）
;   - 顶层非对象（如数组）→ 全部忽略并记日志
; body 非法 JSON → 抛 Error(NetworkCode.BAD_REQUEST)（由调用方转 400 BAD_REQUEST 响应）
ExtractFlatJsonVars(body) {
    result := Map()
    trimmed := LTrim(body, " `t`r`n")
    if (trimmed == "")
        return result
    try
        obj := JSON.parse(trimmed)
    catch as e {
        throw Error(NetworkCode.BAD_REQUEST, , "JSON body 解析失败: " e.Message)
    }
    if (!IsObject(obj)) {
        RMTLogSysInfo("网络触发", "JSON body 顶层不是对象，已忽略全部键")
        return result
    }
    for k, v in (Type(obj) = "Map" ? obj : obj.OwnProps()) {
        vt := Type(v)
        if (vt = "Object" || vt = "Map" || vt = "Array") {
            RMTLogSysInfo("网络触发", "忽略嵌套键: " k)
            continue
        }
        result[String(k)] := String(v)
    }
    return result
}

; ---------------- 编解码 / 校验辅助 ----------------

; URL 解码：%XX（支持连续多字节 UTF-8 序列）+ '+' → 空格
UrlDecode(str) {
    str := StrReplace(str, "+", " ")
    if !InStr(str, "%")
        return str
    out := ""
    seg := ""       ;累积连续 %XX 字节（可能是多字节 UTF-8 序列，须整段解码）
    i := 1
    len := StrLen(str)
    while (i <= len) {
        c := SubStr(str, i, 1)
        if (c == "%") {
            hex := SubStr(str, i + 1, 2)
            if (RegExMatch(hex, "^[0-9A-Fa-f]{2}$")) {
                seg .= Chr("0x" hex)
                i += 3
                continue
            }
        }
        if (seg != "") {
            out .= NetworkHttpDecodeUtf8Bytes(seg)
            seg := ""
        }
        out .= c
        i++
    }
    if (seg != "")
        out .= NetworkHttpDecodeUtf8Bytes(seg)
    return out
}

; 单字节字符串（每字符 0~255）→ 按 UTF-8 解码
NetworkHttpDecodeUtf8Bytes(byteStr) {
    n := StrLen(byteStr)
    if (n == 0)
        return ""
    buf := Buffer(n)
    Loop n
        NumPut("UChar", Ord(SubStr(byteStr, A_Index, 1)) & 0xFF, buf, A_Index - 1)
    return StrGet(buf, "UTF-8")
}

; 变量名合法性：仅允许字母/数字/下划线（PRD P0-5）
NetworkIsValidVarName(name) {
    return RegExMatch(name, "^[A-Za-z0-9_]+$") != 0
}

; ---------- 端口工具（P2-1：保存校验与启动钳制共用）----------
; 注意：NetworkIsValidPort / NetworkNormalizePort 定义在 AssetUtil.ahk（主进程与 Worker
; 共同 include 的文件）；本文件仅主进程 include，放这里会导致 Worker 加载 AssetUtil 时
; 函数名无法解析（AHK #Warn: appears to never be assigned a value）。

; 系统变量重名判定：对照 GetSystemVarArr()（本地化显示名）与 GetLangKey() 键名两套（架构文档 §7-6）
IsSystemVarName(name) {
    for v in GetSystemVarArr() {
        if (name == v || name == GetLangKey(v))
            return true
    }
    return false
}

; 构建统一文本响应：一律 HTTP 200，成功 body 为 "OK"，出错 body 为问题文本；
; Connection: close 单连接单请求（用户拍板：业务结果不用状态码区分）
BuildTextResponse(msg := "OK") {
    body := msg
    bodyLen := StrPut(body, "UTF-8") - 1
    head := "HTTP/1.1 200 OK`r`n"
        . "Content-Type: text/plain; charset=utf-8`r`n"
        . "Content-Length: " bodyLen "`r`n"
        . "Connection: close`r`n`r`n"
    return head . body
}
