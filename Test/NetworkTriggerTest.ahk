#Requires AutoHotkey v2.0
; =====================================================================
; §23 网络触发 验收自测脚本（Test\NetworkTriggerTest.ahk，工程师手跑）
;
; 前置条件：
;   1. RMT 已启动（本脚本独立进程运行，不影响 RMT）；
;   2. 在 RMT「网络宏」表中创建 ≥1 条宏并启用，把其条目 ID 填入下方 TEST_MACRO_ID；
;      （条目 ID 可在网络宏表条目「?」说明弹窗中看到，或点击触发键列「复制链接」取路径段）
;   3. 分组执行：
;      · A 组（免操作）：直接运行本脚本；
;      · B 组（需手动切状态）：按脚本输出提示切换 RMT 状态后，把 RUN_GROUPS 改为对应组重跑。
;
; 覆盖矩阵（用户拍板简化后语义：一律 HTTP 200，成功 body="OK"，出错 body=问题文本）：
;   结果：OK / 宏不存在 / 方法不支持 / JSON 解析失败 / 非法变量名+系统变量重名 / 宏禁用 / 休眠 / 未知操作
;   动作：/{ID}=单次；/macro/{ID}/on|off=开关（幂等：重复 on/off 不重复启停，E 组验证状态机）
;   方法：GET / POST（PUT/DELETE 验证方法拒绝）；参数来源：query / JSON / 表单（仅用于变量）
;
; 输出：MsgBox 汇总 PASS/FAIL 明细；同时追加写 Log\NetworkTriggerTest.log
; =====================================================================

; ↓↓↓ 按实际环境修改 ↓↓↓
TEST_MACRO_ID := "Network.Module1.Macro1"   ;网络宏表中一条【已启用】宏的条目 ID
TEST_NORMAL_MACRO_ID := "Normal.Module1.Macro1" ;按键宏表中任一宏 ID（验证跨表拒绝安全裁定，可留空跳过）
RUN_GROUPS := "ABE"     ;A=免操作组 B=宏禁用组 D=休眠组 E=开关状态组(需宏设为无限循环)；按提示切换状态后修改
; ↑↑↑ 按实际环境修改 ↑↑↑

Host := "127.0.0.1"
Port := 16888

results := []
Check(results, name, expected, actual) {
    pass := (expected == actual)
    results.Push(Format("{1} [{2}] 期望={3} 实际={4}", pass ? "PASS" : "FAIL", name, expected, actual))
}
CheckIn(results, name, needle, body) {
    pass := InStr(body, needle) > 0
    results.Push(Format("{1} [{2}] body 应含「{3}」 实际={4}", pass ? "PASS" : "FAIL", name, needle, body))
}

; ================= A 组：免操作（监听开启、宏启用、未休眠） =================
if (InStr(RUN_GROUPS, "A")) {
    ; A1 GET 不存在的宏 ID → 200 + body 含「不存在」
    r := NetTest_Request("GET", Host, Port, "/NO_SUCH_MACRO_XYZ")
    Check(results, "A1 GET 未知ID → 200", 200, r.status)
    CheckIn(results, "A1b body含不存在", "不存在", r.body)

    ; A2 跨表宏 ID（按键宏表）→ 200 + body 含「不存在」（仅网络表条目可被网络触发）
    if (TEST_NORMAL_MACRO_ID != "") {
        r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_NORMAL_MACRO_ID))
        Check(results, "A2 跨表宏ID → 200", 200, r.status)
        CheckIn(results, "A2b body含不存在", "不存在", r.body)
    }

    ; A3 空路径 → 200 + body 含「不存在」
    r := NetTest_Request("GET", Host, Port, "/")
    Check(results, "A3 空路径 → 200", 200, r.status)
    CheckIn(results, "A3b body含不存在", "不存在", r.body)

    ; A4 PUT → 200 + body 含「方法」（先于存在性校验，用未知 ID 也能命中）
    r := NetTest_Request("PUT", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID))
    Check(results, "A4 PUT → 200", 200, r.status)
    CheckIn(results, "A4b body含方法", "GET/POST", r.body)

    ; A5 DELETE → 同上
    r := NetTest_Request("DELETE", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID))
    CheckIn(results, "A5 DELETE body含方法", "GET/POST", r.body)

    ; A6 POST 坏 JSON → 200 + body 含「JSON」（请求解析层先于存在性校验）
    r := NetTest_Request("POST", Host, Port, "/NO_SUCH_MACRO_XYZ", "{bad json", "application/json")
    Check(results, "A6 POST 坏JSON → 200", 200, r.status)
    CheckIn(results, "A6b body含JSON解析失败", "JSON", r.body)

    ; A7 GET 有效宏 + query 变量 → 200 + body=OK
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID) "?" NetTest_UrlEncode("窗口标题") "=" NetTest_UrlEncode("文档1") "&count=3")
    Check(results, "A7 GET query → 200", 200, r.status)
    Check(results, "A7b body=OK", "OK", r.body)

    ; A8 POST JSON → 200 + body=OK（嵌套键应被忽略不报错）
    jsonBody := '{"窗口标题":"文档1","次数":3,"enabled":true,"nested":{"a":1}}'
    r := NetTest_Request("POST", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID), jsonBody, "application/json")
    Check(results, "A8 POST JSON(含嵌套键) → 200", 200, r.status)
    Check(results, "A8b body=OK", "OK", r.body)

    ; A9 POST 表单 → 200 + body=OK
    r := NetTest_Request("POST", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID)
        , NetTest_UrlEncode("窗口标题") "=" NetTest_UrlEncode("文档2"), "application/x-www-form-urlencoded")
    Check(results, "A9 POST 表单 → 200", 200, r.status)
    Check(results, "A9b body=OK", "OK", r.body)

    ; A10 非法变量名（含空格）→ 200 + body 含「变量名非法」
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID) "?bad%20name=1")
    Check(results, "A10 非法变量名 → 200", 200, r.status)
    CheckIn(results, "A10b body含变量名非法", "变量名非法", r.body)

    ; A11 非法变量名（含连字符）→ 同上
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID) "?a-b=1")
    CheckIn(results, "A11 变量名含- body含变量名非法", "变量名非法", r.body)

    ; A12 与系统变量重名（循环次数）→ 200 + body 含「系统变量」
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID) "?" NetTest_UrlEncode("循环次数") "=5")
    Check(results, "A12 系统变量重名 → 200", 200, r.status)
    CheckIn(results, "A12b body含系统变量", "系统变量", r.body)

    ; A13 off 幂等（宏未运行时连关两次）→ 第二次必为「已处于关闭状态」
    NetTest_Request("GET", Host, Port, "/macro/" NetTest_UrlEncode(TEST_MACRO_ID) "/off")
    r := NetTest_Request("GET", Host, Port, "/macro/" NetTest_UrlEncode(TEST_MACRO_ID) "/off")
    Check(results, "A13 重复off 幂等 → 200", 200, r.status)
    Check(results, "A13b body=OK(已处于关闭状态)", "OK(已处于关闭状态)", r.body)

    ; A14 未知动作 → 200 + body 含「未知操作」
    r := NetTest_Request("GET", Host, Port, "/macro/" NetTest_UrlEncode(TEST_MACRO_ID) "/pause")
    Check(results, "A14 未知动作 → 200", 200, r.status)
    CheckIn(results, "A14b body含未知操作", "未知操作", r.body)

    ; A15 /macro/{ID} 不带动作 = 单次触发 → 200 + body=OK
    r := NetTest_Request("GET", Host, Port, "/macro/" NetTest_UrlEncode(TEST_MACRO_ID))
    Check(results, "A15 macro路径无动作=单次 → 200", 200, r.status)
    Check(results, "A15b body=OK", "OK", r.body)
}

; ================= B 组：先在 RMT 中把 TEST_MACRO_ID 条目禁用 =================
if (InStr(RUN_GROUPS, "B")) {
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID))
    Check(results, "B1 宏被禁用 → 200", 200, r.status)
    CheckIn(results, "B1b body含禁用", "禁用", r.body)
}

; ================= D 组：先按休眠快捷键使 RMT 进入休眠 =================
if (InStr(RUN_GROUPS, "D")) {
    r := NetTest_Request("GET", Host, Port, "/" NetTest_UrlEncode(TEST_MACRO_ID))
    Check(results, "D1 软件休眠 → 200", 200, r.status)
    CheckIn(results, "D1b body含休眠", "休眠", r.body)
    ; D2 休眠时监听保持存活（连接未被拒绝，能收到响应）——上面收到响应即证明
}

; ================= E 组：开关状态机（TEST_MACRO_ID 须为「无限循环」宏，人工观察执行/停止） =================
if (InStr(RUN_GROUPS, "E")) {
    base := "/macro/" NetTest_UrlEncode(TEST_MACRO_ID)
    ; E1 先确保初始为关闭态
    r := NetTest_Request("GET", Host, Port, base "/off")
    Check(results, "E1 初始off → 200", 200, r.status)
    CheckIn(results, "E1b body含OK", "OK", r.body)
    ; E2 开启 → OK(已开启)，宏应开始循环执行（人工观察）
    r := NetTest_Request("GET", Host, Port, base "/on")
    Check(results, "E2 on → OK(已开启)", "OK(已开启)", r.body)
    ; E3 重复 on 幂等 → OK(已处于开启状态)，宏不重启（人工观察循环计数未清零）
    r := NetTest_Request("GET", Host, Port, base "/on")
    Check(results, "E3 重复on幂等 → OK(已处于开启状态)", "OK(已处于开启状态)", r.body)
    ; E4 关闭 → OK(已关闭)，宏应停止（人工观察）
    r := NetTest_Request("GET", Host, Port, base "/off")
    Check(results, "E4 off → OK(已关闭)", "OK(已关闭)", r.body)
    ; E5 重复 off 幂等
    r := NetTest_Request("GET", Host, Port, base "/off")
    Check(results, "E5 重复off幂等 → OK(已处于关闭状态)", "OK(已处于关闭状态)", r.body)
    ; E6 on 带变量 → 200 + body 含 OK（变量写入供宏循环读取，人工在变量监视器确认）
    r := NetTest_Request("GET", Host, Port, base "/on?" NetTest_UrlEncode("窗口标题") "=" NetTest_UrlEncode("文档1"))
    Check(results, "E6 on带变量 → 200", 200, r.status)
    CheckIn(results, "E6b body含OK", "OK", r.body)
    ; 收尾：关闭
    NetTest_Request("GET", Host, Port, base "/off")
}

; ================= 输出 =================
out := "网络触发自测（组=" RUN_GROUPS " 宏=" TEST_MACRO_ID "）`n`n"
passCnt := 0
for line in results {
    out .= line "`n"
    if (InStr(line, "PASS") == 1)
        passCnt++
}
out .= "`n合计: " passCnt "/" results.Length " 通过"
if (results.Length == 0)
    out := "没有可执行用例（请检查 TEST_MACRO_ID / RUN_GROUPS 配置）"

try {
    SplitPath(A_ScriptFullPath, , &logDir)
    logPath := logDir "\..\Log\NetworkTriggerTest.log"
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n" out "`n`n", logPath, "UTF-8")
}
MsgBox(out, "网络触发自测结果")
ExitApp

; =====================================================================
; 最小 HTTP 客户端（阻塞 socket，Connection: close 读到对端关闭为止）
; =====================================================================
NetTest_Request(method, host, port, path, body := "", contentType := "") {
    NetTest_WSAStartup()
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (sock == -1)
        return {status: 0, body: "socket失败"}
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("ws2_32\htons", "UShort", port, "UShort"), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", host, "UInt"), addr, 4)
    if (DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr, "Int", 16, "Int") != 0) {
        DllCall("ws2_32\closesocket", "Ptr", sock)
        return {status: -1, body: "connect失败（监听未启动？）"}
    }
    payload := method " " path " HTTP/1.1`r`nHost: " host ":" port "`r`nConnection: close`r`n"
    bodyBytes := 0
    if (body != "") {
        bodyBytes := StrPut(body, "UTF-8") - 1
        payload .= "Content-Type: " contentType "`r`nContent-Length: " bodyBytes "`r`n"
    }
    payload .= "`r`n"
    payload .= body
    size := StrPut(payload, "UTF-8") - 1
    buf := Buffer(size)
    StrPut(payload, buf, "UTF-8")
    sent := 0
    while (sent < size) {
        n := DllCall("ws2_32\send", "Ptr", sock, "Ptr", buf.Ptr + sent, "Int", size - sent, "Int", 0, "Int")
        if (n <= 0)
            break
        sent += n
    }
    response := ""
    rbuf := Buffer(8192)
    loop {
        r := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", rbuf, "Int", 8192, "Int", 0, "Int")
        if (r <= 0)
            break
        response .= StrGet(rbuf, r, "UTF-8")
    }
    DllCall("ws2_32\closesocket", "Ptr", sock)
    status := 0
    if (RegExMatch(response, "m)^HTTP/1\.\s*\d+\s+(\d+)", &m))
        status := Integer(m[1])
    bodyStart := InStr(response, "`r`n`r`n")
    respBody := bodyStart ? SubStr(response, bodyStart + 4) : ""
    return {status: status, body: respBody}
}

NetTest_WSAStartup() {
    static started := false
    if (started)
        return
    wsaData := Buffer(408)
    DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int")
    started := true
}

; UTF-8 百分号编码（自测用）
NetTest_UrlEncode(s) {
    buf := Buffer(StrPut(s, "UTF-8") - 1)
    StrPut(s, buf, "UTF-8")
    out := ""
    loop buf.Size {
        b := NumGet(buf, A_Index - 1, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b == 0x2D || b == 0x5F || b == 0x2E)
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}
