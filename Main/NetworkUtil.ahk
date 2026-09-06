#Requires AutoHotkey v2.0
#Include Util\NetworkHttpUtil.ahk

; =====================================================================
; §23 网络触发 —— NetworkServer 监听服务（Main\NetworkUtil.ahk，仅主进程）
;
; 职责（架构文档 §3 NetworkServer 类）：
;   1. 生命周期：Start / Stop / Restart / OnExit 自注册（不侵入既有退出链路）
;   2. 50ms SetTimer 轮询状态机：accept → 每连接字节缓冲 → 完整请求判定
;      → 同步校验链（自外向内短路）→ 先发响应 → SetTimer(-1) 异步派发宏
;   3. 热重载订阅与调和：订阅 MyHotReloadBus（无过滤器直通）；监听存在性由
;      「是否存在非禁用网络宏」决定（HasEnabledNetworkMacro），运行端口与设置
;      不一致则 Restart；请求时实时读内存模型
;   4. 端口冲突：bind 失败 → bindError 置位 + 日志 warn + Toast；不自动换端口、不弹模态框
;
; 线程模型：仅存在于主进程（Thread\Work.ahk 不 include 本文件）；
; SetTimer 回调内禁止 Sleep/长循环；每连接收包超时 5s 强制关闭；单连接单请求。
; 校验链顺序（架构裁定，不可调整）：方法 → 请求解析/JSON → 休眠 → 宏不存在 → 禁用 → 变量 → 触发
; 响应语义（用户拍板）：一律 HTTP 200，成功 body="OK"，出错 body=问题文本；NetworkCode 仅作内部日志标签
; 执行动作由 path 决定（用户拍板，便于扩展）：/{宏ID}=单次触发；/macro/{宏ID}/on=开启；/macro/{宏ID}/off=关闭；
;   query/body 参数仅用于变量。开关状态与热键开关触发共享同一状态机（item.ToggleState / WorkPool 占用）
; =====================================================================

class NetworkServer {

    __New() {
        this.listenSocket := 0          ;监听 socket 句柄（0=未监听）
        this.conns := Map()             ;clientSocket → NetworkConnState
        this.pollTimerFunc := ObjBindMethod(this, "OnPoll")
        this.running := false           ;是否处于监听中
        this.bindError := ""            ;bind 失败原因（空=无冲突）
        this.port := 0                  ;当前运行端口（0=未监听）
        this._exitRegistered := false   ;OnExit 只注册一次
        ; §17 同款热重载订阅（无过滤器直通全部变更，handler 内自行调和）
        global MyHotReloadBus
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "OnConfigChanged"))
    }

    ; ---------- 生命周期 ----------

    Start() {
        global MainSoftData
        if (this.running)
            return
        if (!this._exitRegistered) {
            OnExit(ObjBindMethod(this, "OnExitHandler"))
            this._exitRegistered := true
        }
        ; 无非禁用网络宏：不监听（条目启用后经总线调和自动启动）
        if (!this.HasEnabledNetworkMacro())
            return
        this._BindAndListen(NetworkNormalizePort(MainSoftData.NetworkPort))
    }

    ; 是否存在可被网络触发的条目（非禁用且有 ID）——决定是否需要监听
    HasEnabledNetworkMacro() {
        tableItem := GetTableBySymbol("Network")
        if (!tableItem)
            return false
        for i, item in tableItem.Items {
            if (item.ID != "" && !ParseBoolInt(item.Forbid) && !GetItemFoldForbidState(tableItem, i))
                return true
        }
        return false
    }

    Stop() {
        SetTimer(this.pollTimerFunc, 0)
        this.running := false
        for sock, conn in this.conns.Clone()
            TcpClose(sock)
        this.conns := Map()
        if (this.listenSocket) {
            TcpClose(this.listenSocket)
            this.listenSocket := 0
        }
        this.port := 0
        this.bindError := ""
    }

    Restart() {
        global MainSoftData
        prevErr := this.bindError   ;Stop 会清空 bindError，重试去重需带出旧错误
        this.Stop()
        this._BindAndListen(NetworkNormalizePort(MainSoftData.NetworkPort), prevErr)
    }

    GetBindError() {
        return this.bindError
    }

    GetPort() {
        return this.port
    }

    ; bind + listen + 启动轮询；失败走结论 1 提示路径（日志 warn + Toast，不自动换端口）
    ; Toast 去重：bindError 非空期间任意配置变更都会重试 bind，同一错误不重复弹 Toast
    _BindAndListen(port, prevErr := "") {
        if (this.running)
            return
        err := WinsockStartup()
        if (err) {
            this.bindError := "WSAStartup 失败（错误码 " err "）"
            RMTLogSysWarn("网络触发", this.bindError)
            if (this.bindError != prevErr)
                try Toast.Warning(this.bindError)
            return
        }
        errMsg := ""
        sock := TcpListen(port, "127.0.0.1", &errMsg)
        if (!sock) {
            this.bindError := errMsg
            ; P0-1：端口占用不自动顺延（URL 显式含端口，静默换端口会让已分发 URL 失效）；
            ; 仅告警，软件其余功能不受影响；用户改端口保存后经热重载调和自动重试
            RMTLogSysWarn("网络触发", "监听启动失败: " errMsg "（软件其余功能不受影响，修改端口保存后将自动重试）")
            if (errMsg != prevErr)   ;同一错误重复重试（如占用端口下每次配置变更/同步调和）不重复弹
                try Toast.Warning("网络触发监听启动失败: " errMsg)
            return
        }
        this.listenSocket := sock
        this.port := port
        this.bindError := ""
        this.running := true
        SetTimer(this.pollTimerFunc, 50)    ;50ms 轮询（与 TimingScheduler 轮询风格一致）
        RMTLogSysInfo("网络触发", "HTTP 监听已启动: http://127.0.0.1:" port)
    }

    ; ---------- 轮询状态机 ----------

    OnPoll() {
        if (!this.running)
            return
        this.Accept()
        ; P1-1（QA 第 1 轮）：单 tick 内对每连接循环 recv，直至 WOULDBLOCK / 请求完成 / 错误。
        ; 否则 4096B×50ms≈80KB/s 的吞吐配 5s 收包超时最多收 ≈400KB，
        ; 1MB 上限内的合法大 body 必被「接收请求超时」400 拒绝（与上限声明自相矛盾）。
        ; 保持单 tick 同步完成、无 Sleep；数据取空即返回，慢客户端不会拖长 tick；
        ; 单连接单 tick 最大工作量受 16KB 头 + 1MB 体上限约束，超限即 400 截断。
        for sock in this.conns.Clone() {
            loop {
                if (!this.conns.Has(sock))      ;连接已完成/被丢弃（_TryComplete 内处理），转下一连接
                    break
                conn := this.conns[sock]
                if (A_TickCount - conn.startTick > 5000) {
                    ; 单请求 5s 收包超时：截断为 400 并强制关闭
                    this._RespondAndClose(sock, NetworkCode.BAD_REQUEST, "接收请求超时（5 秒未收完整请求）")
                    break
                }
                if (!this.Recv(conn))           ;WOULDBLOCK：内核缓冲已取空，本连接本轮结束
                    break
            }
        }
    }

    ; 非阻塞 accept：本 tick 内取空所有就绪连接
    Accept() {
        loop 64 {
            clientIP := ""
            client := TcpAccept(this.listenSocket, &clientIP)
            if (!client)
                break
            this.conns[client] := NetworkConnState(client, clientIP)
        }
    }

    ; 收一块数据并判定请求完整性；完整则进入处理。
    ; 返回 true=有进展（收到数据/对端关闭/错误已丢弃），false=WOULDBLOCK（收包取空）
    Recv(conn) {
        state := TcpRecv(conn.socket, conn)
        if (state == "again")
            return false
        if (state == "error") {
            this._DropConn(conn.socket)
            return true
        }
        this._TryComplete(conn, state == "closed")
        return true
    }

    ; 判定头部终止符 + Content-Length 是否收满；isClosed=对端已半关闭（不再有数据）
    _TryComplete(conn, isClosed) {
        headerEnd := NetworkHttpFindHeaderEnd(conn.buf)
        if (headerEnd < 0) {
            if (conn.buf.Size > 16384) {
                ; 头部超限（架构 §1.5 顺序 0：BAD_REQUEST）
                this._RespondAndClose(conn.socket, NetworkCode.BAD_REQUEST, "请求头超过 16KB 限制")
                return true
            }
            if (isClosed)
                this._DropConn(conn.socket)
            return false
        }
        headBytes := headerEnd + 4
        ; 头部必为 ASCII，按 UTF-8 解码安全
        headStr := StrGet(conn.buf.Ptr, headBytes, "UTF-8")
        contentLength := 0
        if (RegExMatch(headStr, "im)^\s*Content-Length\s*:\s*(\d+)", &m))
            contentLength := Integer(m[1])
        if (contentLength > 1048576) {
            this._RespondAndClose(conn.socket, NetworkCode.BAD_REQUEST, "请求体超过 1MB 限制")
            return true
        }
        total := headBytes + contentLength
        if (conn.buf.Size < total) {
            if (isClosed) {
                ; 对端关闭但 body 未收满：body 超时/截断
                this._RespondAndClose(conn.socket, NetworkCode.BAD_REQUEST, "请求体不完整（连接提前关闭）")
                return true
            }
            return false    ;body 未收满，等下一个 tick
        }
        bodyStr := (contentLength > 0) ? StrGet(conn.buf.Ptr + headBytes, contentLength, "UTF-8") : ""
        raw := headStr . bodyStr
        req := ""
        try
            req := ParseHttpRequest(raw, conn.clientIP)
        catch as e {
            ; 请求解析层（架构 §1.5 顺序 0，先于功能门控）
            this._RespondAndClose(conn.socket, NetworkCode.BAD_REQUEST, e.Message)
            return true
        }
        req.recvTick := A_TickCount
        this.HandleComplete(req, conn.socket)
        return true
    }

    ; ---------- 校验链 + 触发 ----------

    ; 同步校验链（自外向内短路，首个命中即响应）：
    ;   方法 → ①JSON解析 → ②休眠 → ③宏不存在 → ④禁用 → ⑤变量 → ⑥触发
    ;   响应语义（用户拍板）：一律 HTTP 200，成功 body="OK"，出错 body=问题文本；
    ;   NetworkCode 仅作内部日志标签，不再进入状态行
    HandleComplete(req, sock) {
        ; 非 GET/POST（校验链最外层）
        if (req.method != "GET" && req.method != "POST") {
            this._RespondAndClose(sock, NetworkCode.METHOD_NOT_ALLOWED, "仅支持 GET/POST 方法")
            this._LogRequest(req, NetworkCode.METHOD_NOT_ALLOWED, "")
            return
        }
        ; 路径解析（请求解析层）：从 path 提取执行动作
        parseErr := this._ParseAction(req)
        if (parseErr != "") {
            this._RespondAndClose(sock, NetworkCode.BAD_REQUEST, parseErr)
            this._LogRequest(req, NetworkCode.BAD_REQUEST, "")
            return
        }
        ; 三来源合并：query 先入 → form 次之 → JSON 最后（后者覆盖前者，PRD P0-5）
        varMap := Map()
        for k, v in req.query
            varMap[k] := String(v)
        if (req.method == "POST") {
            ct := req.headers.Has("content-type") ? req.headers["content-type"] : ""
            if (InStr(ct, "json")) {
                try
                    jsonVars := ExtractFlatJsonVars(req.body)
                catch as e {
                    ; ① JSON 解析失败（请求解析层先于功能校验）
                    this._RespondAndClose(sock, NetworkCode.BAD_REQUEST, e.Message)
                    this._LogRequest(req, NetworkCode.BAD_REQUEST, "")
                    return
                }
                for k, v in jsonVars
                    varMap[k] := String(v)
            } else {
                for k, v in ParseFormBody(req.body)
                    varMap[k] := String(v)
            }
        }
        result := this.ValidateAndTrigger(req, varMap)
        if (result.code != NetworkCode.OK) {
            this._RespondAndClose(sock, result.code, result.msg)
            this._LogRequest(req, result.code, "")
            return
        }
        ; 变量写入：必须走 SetGlobalVariable(覆盖语义 ignoreExist=false)，
        ; 同步 Worker 广播与 UI 变量下拉；禁止直写 VariableMap（架构文档 §7-6）
        try
            SetGlobalVariable(result.names, result.values, false)
        catch as e {
            this._RespondAndClose(sock, NetworkCode.INVALID_VARIABLE, "变量写入失败: " e.Message)
            this._LogRequest(req, NetworkCode.INVALID_VARIABLE, "")
            return
        }
        ; ⑦ 开/关幂等判定（同步）：on 已开启不重复启动、off 已关闭不重复停止（webhook 重发安全）
        running := this.IsItemRunning(result.tableItem, result.itemID)
        if (req.action == "on" && running) {
            this._RespondAndClose(sock, NetworkCode.OK, "OK(已处于开启状态)")
            this._LogRequest(req, NetworkCode.OK, result.names)
            return
        }
        if (req.action == "off" && !running) {
            this._RespondAndClose(sock, NetworkCode.OK, "OK(已处于关闭状态)")
            this._LogRequest(req, NetworkCode.OK, result.names)
            return
        }
        ; 先发响应，再异步派发宏（调用方不等待宏执行结果，P0-6）
        respMsg := (req.action == "on") ? "OK(已开启)" : (req.action == "off") ? "OK(已关闭)" : "OK"
        TcpSendAll(sock, BuildTextResponse(respMsg))
        TcpClose(sock)
        this.conns.Delete(sock)
        this._LogRequest(req, NetworkCode.OK, result.names)
        ; SetTimer(-1)：宏派发延迟到下一个伪线程，确保响应已送达调用方
        if (req.action == "on")
            SetTimer(ObjBindMethod(this, "DispatchToggleOn", result.tableItem, result.itemID), -1)
        else if (req.action == "off")
            SetTimer(ObjBindMethod(this, "DispatchToggleOff", result.tableItem, result.itemID), -1)
        else
            SetTimer(ObjBindMethod(this, "DispatchMacro", result.tableItem, result.itemID), -1)
    }

    ; 解析执行动作（请求解析层）：req.path（已去首部"/"）→ req.macroID + req.action
    ;   "/{宏ID}"            → action=""（单次触发）
    ;   "/macro/{宏ID}"      → action=""（单次触发，与上面等价）
    ;   "/macro/{宏ID}/on"   → action="on"（开启，循环执行）
    ;   "/macro/{宏ID}/off"  → action="off"（关闭，停止执行）
    ; 返回 ""=成功，否则错误文本。保留 /macro/ 前缀是为后续动作扩展预留命名空间
    _ParseAction(req) {
        segs := StrSplit(req.path, "/")
        req.action := ""
        if (segs.Length >= 1 && segs[1] == "macro") {
            if (segs.Length < 2 || segs[2] == "")
                return "路径非法: /" req.path "（应为 /macro/{宏ID} 或 /macro/{宏ID}/on|off）"
            req.macroID := UrlDecode(segs[2])
            if (segs.Length >= 3 && segs[3] != "")
                req.action := StrLower(UrlDecode(segs[3]))
            if (segs.Length >= 4 && segs[4] != "")
                return "路径非法: /" req.path "（/macro/{宏ID} 后最多跟一个动作 on|off）"
        } else {
            req.macroID := (segs.Length >= 1) ? UrlDecode(segs[1]) : ""
        }
        if (req.action != "" && req.action != "on" && req.action != "off")
            return "未知操作: " req.action "（仅支持 on/off；不带动作=单次触发）"
        return ""
    }

    ; 校验链（休眠/宏不存在/禁用/变量）：返回 {code, msg, names, values, tableItem, itemID}
    ValidateAndTrigger(req, varMap) {
        global MainSoftData
        ; ① 软件休眠
        if (MainSoftData.IsSuspend)
            return {code: NetworkCode.SUSPENDED, msg: "软件休眠中，网络触发被拒绝"}
        ; ④ 宏 ID 不存在（安全裁定：仅查网络表 Symbol="Network"，
        ;    其他表宏即使 ID 匹配也一律拒绝——网络表是对外触发的显式 opt-in 面）
        tableItem := GetTableBySymbol("Network")
        if (!tableItem || req.macroID == "" || !tableItem.ItemMap.Has(req.macroID))
            return {code: NetworkCode.MACRO_NOT_FOUND, msg: "网络表中不存在宏 ID: " (req.macroID == "" ? "(空路径)" : req.macroID)}
        itemIndex := GetItemIndexInTable(tableItem, req.macroID)
        item := tableItem.Items[itemIndex]
        ; ⑤ 宏被禁用（条目禁用 / 所属模块禁用）
        if (!item || ParseBoolInt(item.Forbid) || GetItemFoldForbidState(tableItem, itemIndex))
            return {code: NetworkCode.MACRO_FORBIDDEN, msg: "宏已被禁用: " req.macroID}
        ; ⑥ 变量错误（需先定位到宏才有"变量"语境，故排最后）
        names := []
        values := []
        for name, value in varMap {
            if (!NetworkIsValidVarName(name))
                return {code: NetworkCode.INVALID_VARIABLE, msg: "变量名非法（仅允许字母/数字/下划线）: " name}
            if (IsSystemVarName(name))
                return {code: NetworkCode.INVALID_VARIABLE, msg: "变量名与系统变量重名: " name}
            names.Push(name)
            values.Push(String(value))
        }
        return {code: NetworkCode.OK, msg: "OK", names: names, values: values, tableItem: tableItem, itemID: req.macroID}
    }

    ; 宏派发（下一伪线程执行）：TriggerMacroHandler 内部还有统一禁用门控复检（双保险）；
    ; 宏执行期间的运行时错误不回传调用方（响应已发出），仅由既有 ErrorHandler/日志链路落日志
    DispatchMacro(tableItem, itemID) {
        try
            TriggerMacroHandler(tableItem, itemID)
        catch as e {
            RMTLogSysError("网络触发", "宏派发异常: id=" itemID " err=" e.Message)
        }
    }

    ; 条目运行状态（开关语义判定口径与 OnToggleTriggerMacro/StopMacro 一致，热键开关与网络开关共享状态）：
    ; 多线程模式看 WorkPool 占用（IsWorkIndex/HasItemWork），主进程执行看 item.ToggleState
    IsItemRunning(tableItem, itemID) {
        itemIndex := GetItemIndexInTable(tableItem, itemID)
        if (itemIndex < 1)
            return false
        item := tableItem.Items[itemIndex]
        if (!item)
            return false
        if (WorkPoolEnabled())
            return (item.IsWorkIndex && item.IsWorkIndex != 0) || MyWorkPool.HasItemWork(tableItem.ID, item.ID)
        return !!item.ToggleState
    }

    ; 开启：复用 OnToggleTriggerMacro 的启动路径（多线程=PrepareItemRun+Submit；主进程=ToggleState 置位+SetTimer 循环）
    DispatchToggleOn(tableItem, itemID) {
        try {
            itemIndex := GetItemIndexInTable(tableItem, itemID)
            if (itemIndex < 1)
                return
            OnToggleTriggerMacro(tableItem, itemIndex)
        } catch as e {
            RMTLogSysError("网络触发", "宏开启异常: id=" itemID " err=" e.Message)
        }
    }

    ; 关闭：复用 StopMacro 标准停止口（多线程=ForceStopItem；主进程=Killed 标记+复位开关状态）
    DispatchToggleOff(tableItem, itemID) {
        try
            MyStopMacro(tableItem, itemID)
        catch as e {
            RMTLogSysError("网络触发", "宏关闭异常: id=" itemID " err=" e.Message)
        }
    }

    ; ---------- 内部辅助 ----------

    ; 发送响应（一律 200，body=问题文本）+ 关闭 + 移除连接状态（conns 以 socket 为键）
    _RespondAndClose(sock, code, msg) {
        TcpSendAll(sock, BuildTextResponse(msg))
        TcpClose(sock)
        if (this.conns.Has(sock))
            this.conns.Delete(sock)
    }

    ; 无响应静默丢弃（对端异常/半开连接）
    _DropConn(sock) {
        TcpClose(sock)
        if (this.conns.Has(sock))
            this.conns.Delete(sock)
    }

    ; 运行日志埋点（时间/来源 IP/宏 ID/结果码 NetworkCode/写入变量名列表）
    _LogRequest(req, code, nameArr) {
        varStr := ""
        if (IsObject(nameArr)) {
            for i, n in nameArr
                varStr .= (i > 1 ? "," : "") n
        }
        RMTLogBusiness("网络触发", Format("{1} {2} ip={3} id={4} code={5} 变量=[{6}]"
            , req.method, req.path, req.clientIP, (req.macroID == "" ? "-" : req.macroID), code, varStr))
    }

    ; ---------- 热重载调和 ----------

    ; 总线回调（直通全部变更）：按「是否存在非禁用网络宏」+ 运行端口调和启停；
    ; 条目增删改、禁用切换都会走到这里，实时决定监听是否需要存在
    OnConfigChanged(tableIndex, itemIndex) {
        global MainSoftData
        if (!IsSet(MainSoftData) || !MainSoftData.HasProp("NetworkPort"))
            return
        ; 无可触发条目 → 停监听（不占端口）；有 → 确保运行且端口一致
        if (!this.HasEnabledNetworkMacro()) {
            if (this.running || this.bindError != "")
                this.Stop()
            return
        }
        ; NetworkNormalizePort：防御内存中残留的非法端口值（保存链路已校验，双保险防 htons 截断）
        wantPort := NetworkNormalizePort(MainSoftData.NetworkPort)
        ; 未运行 / 端口变更 / 此前 bind 失败（如端口占用）→ 重新绑定（bind 失败走结论 1 提示路径）
        if (!this.running || wantPort != this.port || this.bindError != "")
            this.Restart()
    }

    ; 退出清理：停监听 + 关连接 + WSACleanup，不侵入既有退出链路（架构 §1.2）
    OnExitHandler(exitReason, exitCode) {
        this.Stop()
        WinsockCleanup()
        return 0
    }
}
