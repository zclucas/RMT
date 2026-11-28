#Requires AutoHotkey v2.0

class AiMcp {
    static client := ""
    static path := ""
    static seq := 0
    static schemas := Map()
    static cancelled := false
    static exitBound := false
    static root := ""

    static Stop(*) {
        this.cancelled := true
        if (IsObject(this.client))
            try this.client.Stop()
        this.client := "", this.path := "", this.schemas := Map()
    }

    static Enabled() => MainSoftData.HasOwnProp("AiMcpEnabled") && MainSoftData.AiMcpEnabled

    static Ensure() {
        if (!this.Enabled())
            throw Error("MCP当前停用；旧服务暂停期间改用原生指令生成。可在AI设置启用已修复的MCP服务。")
        if (!AiAssist.CanRun())
            throw Error("启动MCP服务需要完全访问权限。")
        path := MainSoftData.HasOwnProp("AiMcpServerPath") ? MainSoftData.AiMcpServerPath : ""
        if (Trim(path) == "")
            path := A_WorkingDir "\Plugins\RMTMcps\RMTMcps.exe"
        path := AiAssist._ResolveUserPath(path, true)
        if (!FileExist(path) || !RegExMatch(path,"i)\.exe$"))
            throw Error("MCP服务程序不存在，请在设置中指定可用exe。")
        if (IsObject(this.client) && this.path == path && this.client.Running())
            return
        this.Stop()
        this.cancelled := false
        this.client := RMT_ASM.CreateInstance("RMT.AiMcpTransport")
        this.path := path
        SplitPath(path, , &directory)
        root := this.root != "" ? this.root : A_WorkingDir "\Cache\AI\MCP"
        DirCreate(root "\workspaces"), DirCreate(root "\output")
        this.client.Start(path,"",directory,root "\workspaces",root "\output")
        try {
            result := this.Request("initialize",Map("protocolVersion","2024-11-05","capabilities",Map(),"clientInfo",Map("name","RMT-AI","version",RMT_VERSION)),10000)
            if (!result.Has("capabilities") || !result["capabilities"].Has("tools"))
                throw Error("MCP服务未提供指令生成工具。")
            this.client.Send(JSON.stringify(Map("jsonrpc","2.0","method","notifications/initialized"),0))
            this.schemas := Map()
            cursor := ""
            loop 10 {
                page := this.Request("tools/list",cursor == "" ? Map() : Map("cursor",cursor),10000)
                for tool in page.Get("tools",[])
                    this.schemas[tool["name"]] := tool
                cursor := page.Get("nextCursor","")
                if (cursor == "")
                    break
            }
            if (cursor != "")
                throw Error("MCP工具列表过大，请缩小服务范围。")
            if (!this.exitBound) {
                OnExit(ObjBindMethod(this,"Stop"))
                this.exitBound := true
            }
        } catch as e {
            this.Stop()
            throw e
        }
    }

    static Request(method, parameters, timeout := 30000) {
        this.seq += 1
        id := this.seq
        this.client.Send(JSON.stringify(Map("jsonrpc","2.0","id",id,"method",method,"params",parameters),0))
        deadline := A_TickCount + timeout
        loop {
            if (this.cancelled || !AiAssist.CanRun())
                throw Error("MCP请求已取消或权限已撤销。")
            line := String(this.client.TakeLine())
            if (line != "") {
                try packet := JSON.parse(line)
                catch
                    continue
                if (Type(packet) != "Map")
                    continue
                if (packet.Has("method")) {
                    if (packet.Has("id"))
                        this.client.Send(JSON.stringify(Map("jsonrpc","2.0","id",packet["id"],"error",Map("code",-32601,"message","Unsupported server request")),0))
                    continue
                }
                if (packet.Get("id",-1) != id)
                    continue
                if (packet.Has("error"))
                    throw Error("MCP请求失败：" JSON.stringify(packet["error"],0))
                if (!packet.Has("result"))
                    throw Error("MCP响应缺少result。")
                return packet["result"]
            }
            if (!this.client.Running())
                throw Error("MCP服务已退出：" this.client.Error())
            if (A_TickCount >= deadline) {
                this.Stop()
                throw Error("MCP请求超时；请改用原生指令生成。")
            }
            Sleep(20)
        }
    }

    static Describe(*) {
        try {
            this.Ensure()
            return JSON.stringify(Map("ok",JSON.true,"available",JSON.true,"tools",this.schemas,
                "guidance","生成配置优先使用本服务。生成结果必须validate_rmt并检查目标指令字段；不理想时改用instruction_schema/create_instruction。单次电脑任务使用execute_instruction，不生成配置。"),0)
        } catch as e {
            return JSON.stringify(Map("ok",JSON.true,"available",JSON.false,"reason",e.Message,"fallback_tools",["instruction_schema","create_instruction"]),0)
        }
    }

    static Call(args) {
        if (!AiAssist.CanWrite())
            throw Error("MCP生成配置需要写入权限。")
        this.Ensure()
        name := args["name"]
        if (!this.schemas.Has(name))
            throw Error("MCP工具不存在，请先mcp_tools查询实际schema。")
        parameters := args.Get("arguments",Map())
        if (Type(parameters) != "Map")
            throw Error("arguments必须是JSON对象。")
        if (!AiAssist._NeedApproval("MCP工具：" name "`n" JSON.stringify(parameters,0)))
            throw Error("用户拒绝审批。")
        result := this.Request("tools/call",Map("name",name,"arguments",parameters))
        return JSON.stringify(Map("ok",result.Get("isError",false) ? JSON.false : JSON.true,"mcp_result",result,
            "guidance","检查生成结果与validation；参数或效果不理想时修正参数，或使用instruction_schema/create_instruction生成对应原生指令。"),0)
    }
}
