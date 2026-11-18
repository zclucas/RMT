#Requires AutoHotkey v2.0

class TimeoutPolicy {
    static DefaultMs := 5000
    static DefaultAction := "重试1次"
    static DefaultStatusVar := "OverState"
    static Actions := ["停止", "忽略", "重试1次", "重试2次", "无限重试"]
    static RetryLimits := Map("重试1次", 1, "重试2次", 2, "无限重试", -1)

    static Get(data) => data.HasOwnProp("TimeoutAction") ? data.TimeoutAction : ""
    static StatusVar(data) => data.HasOwnProp("TimeoutStatusVar") ? data.TimeoutStatusVar : ""

    static RegisterStatus(data) {
        name := this.StatusVar(data)
        if (name != "")
            MySoftData.GlobalVariMap[name] := true
    }

    static WriteStatus(data, timedOut) {
        name := this.StatusVar(data)
        if (name != "")
            MySetGlobalVariable([name], [timedOut ? 1 : 0], false)
    }

    static Stops(action) => action != "" && action != "忽略"

    static LegacyRetryAction(count) {
        if (!IsInteger(count))
            return ""
        switch Integer(count) {
            case 0: return "忽略"
            case 1: return "重试1次"
            case 2: return "重试2次"
        }
        return ""
    }

    static CanRetry(action, attempt) {
        limit := this.RetryLimits.Get(action, 0)
        return limit == -1 || attempt <= limit
    }

    static WaitBeforeRetry(cancelled) {
        loop 20 {
            if (cancelled())
                return false
            Sleep(25)
        }
        return !cancelled()
    }
}
