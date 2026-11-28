#Requires AutoHotkey v2.0
; Independent mascot host. GPU crash must not kill macros.
; AHK sends data/logic only; the host plays clips and draws the balloon.
; Commands: ping / say / tips / quit  (motion / expression / look_at / lipsync optional)
class L2dHost {
    static PipeName := "\\.\pipe\RMT_L2dHost"
    static Pid := 0
    static Talking := false
    static WaitTries := 0
    static StartLines := ["开始干活啦", "出发咯", "看好了哦", "交给我吧"]
    static EndLines := ["搞定啦", "休息一下", "辛苦啦", "收工了"]
    static HeadLines := ["头发要乱了", "摸头是奖励吗", "再摸要收费了", "耳朵很敏感的"]
    static BodyLines := ["不要戳那里", "有话好好说", "我在认真工作", "嗯？干什么"]

    static Dir() {
        return A_ScriptDir "\Plugins\L2dHost"
    }

    static StartIfEnabled() {
        if (MainSoftData.HasProp("ShowL2dMascot") && MainSoftData.ShowL2dMascot)
            L2dHost.Start()
    }

    static ApplyEnabled(enabled) {
        if (enabled)
            L2dHost.Start()
        else
            L2dHost.Stop()
    }

    static IsRunning() {
        return L2dHost.Pid && ProcessExist(L2dHost.Pid)
    }

    static Start() {
        if (L2dHost.Ping()) {
            L2dHost.SendTips()
            return true
        }
        cmd := L2dHost._LaunchCommand()
        if (cmd == "")
            return L2dHost._FailStart()
        workDir := L2dHost.Dir()
        if (!DirExist(workDir))
            workDir := A_ScriptDir
        try Run(cmd, workDir, "Hide", &pid)
        catch as e {
            RMTLogSys(RMT_LV_WARN, "L2dHost", e.Message)
            return L2dHost._FailStart()
        }
        L2dHost.Pid := pid
        L2dHost.WaitTries := 0
        SetTimer(L2dHostPollReady, 100)
        return true
    }

    static Stop() {
        SetTimer(L2dHostPollReady, 0)
        L2dHost.WaitTries := 0
        if (L2dHost.IsAlive())
            L2dHost.Send(Map("cmd", "quit"))
        pid := L2dHost.Pid
        L2dHost.Pid := 0
        L2dHost.Talking := false
        if (pid && ProcessExist(pid)) {
            Sleep(80)
            if (ProcessExist(pid))
                try ProcessClose(pid)
        }
    }

    static IsAlive() {
        if (L2dHost.IsRunning())
            return true
        return L2dHost.Ping()
    }

    static Motion(name) {
        talking := (name = "talk")
        if (talking == L2dHost.Talking && name != "blink" && name != "nod")
            return
        L2dHost.Talking := talking
        L2dHost.Send(Map("cmd", "motion", "name", String(name)))
    }

    static Expression(name) {
        L2dHost.Send(Map("cmd", "expression", "name", String(name)))
    }

    static LookAt(x, y) {
        L2dHost.Send(Map("cmd", "look_at", "x", Number(x), "y", Number(y)))
    }

    static LipSync(open) {
        L2dHost.Send(Map("cmd", "lipsync", "open", Number(open)))
    }

    static OnMacroWorking(working) {
        if (!MainSoftData.HasProp("ShowL2dMascot") || !MainSoftData.ShowL2dMascot)
            return
        L2dHost.SayKind(working ? "start" : "end")
    }

    static SayKind(kind) {
        keys := (kind = "start") ? L2dHost.StartLines : L2dHost.EndLines
        texts := []
        for k in keys
            texts.Push(GetLang(k))
        if (texts.Length < 1)
            return
        pick := texts[Random(1, texts.Length)]
        L2dHost.Send(Map("cmd", "say", "kind", kind, "text", pick, "ms", 4500))
    }

    static JoinLang(keys) {
        joined := ""
        for k in keys {
            t := GetLang(k)
            if (t == "")
                continue
            joined .= (joined == "" ? "" : "|") t
        }
        return joined
    }

    static SendTips() {
        L2dHost.Send(Map("cmd", "tips", "head", L2dHost.JoinLang(L2dHost.HeadLines), "body", L2dHost.JoinLang(L2dHost.BodyLines)))
    }

    static _PollReady() {
        if (L2dHost.Ping()) {
            SetTimer(L2dHostPollReady, 0)
            L2dHost.WaitTries := 0
            L2dHost.SendTips()
            return
        }
        L2dHost.WaitTries += 1
        if (L2dHost.WaitTries < 40)
            return
        SetTimer(L2dHostPollReady, 0)
        L2dHost.WaitTries := 0
        L2dHost._FailStart()
    }

    static Ping() {
        return L2dHost.Send(Map("cmd", "ping", "pid", ProcessExist()))
    }

    static Send(msg) {
        text := JSON.stringify(msg, 0) "`n"
        try {
            pipe := FileOpen(L2dHost.PipeName, "w", "UTF-8")
            if (!IsObject(pipe))
                return false
            pipe.Write(text)
            pipe.Close()
            return true
        } catch {
            return false
        }
    }

    static _FailStart() {
        pid := L2dHost.Pid
        L2dHost.Pid := 0
        if (pid && ProcessExist(pid))
            try ProcessClose(pid)
        MainSoftData.ShowL2dMascot := false
        try {
            if (IsSet(MyMainWin) && IsObject(MyMainWin))
                MyMainWin.ui.Update("ChkL2dMascot", "IsChecked", "False")
        }
        Toast.Warning(GetLang("看板娘资源未找到"), 2500)
        return false
    }

    static _HasModel(dir) {
        if (FileExist(dir "\RuoMengTu.p2lrt"))
            return true
        loop files dir "\*.p2lrt"
            return true
        return false
    }

    static _LaunchCommand() {
        dir := L2dHost.Dir()
        exe := dir "\L2dHost.exe"
        ; exe、运行库、模型要齐，缺一个就不拉起子进程，避免它弹出错误框。
        if (!FileExist(exe) || !FileExist(dir "\p2l_runtime.dll") || !L2dHost._HasModel(dir))
            return ""
        return '"' exe '" ' ProcessExist()
    }
}

L2dHostPollReady(*) {
    L2dHost._PollReady()
}
