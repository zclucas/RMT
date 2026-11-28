#Requires AutoHotkey v2.0

class TimeoutPolicy {
    static RetryDelayMs := 500
    static RetryPollMs := 25
    static DefaultMs := 5000
    static DefaultAction := "重试1次"
    static DefaultStatusVar := "OverState"
    static Actions := ["停止", "忽略", "重试1次", "重试2次", "无限重试"]
    static RetryLimits := Map("重试1次", 1, "重试2次", 2, "无限重试", -1)

    static IsVariable(value) => Type(value) == "String" && RegExMatch(value, "^\{[^{}\r\n]+\}$")

    static ValidMs(value, maximum := 3600000, minimum := 1) => this.IsVariable(value)
        || (IsInteger(value) && value >= minimum && value <= maximum)

    static ResolveMs(value, resolve := "", maximum := 3600000, minimum := 1) {
        if (this.IsVariable(value)) {
            if (IsObject(resolve))
                value := resolve(value)
            else if (!TryGetVarValue(&value, SubStr(value, 2, -1), false, Map(), false))
                throw Error(GetLang("超时变量尚未赋值。"))
        }
        if (!IsInteger(value) || value < minimum || value > maximum)
            throw Error(GetLang("超时必须为有效范围内的整数毫秒。"))
        return Integer(value)
    }

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

    static CanRetry(action, attempt) {
        limit := this.RetryLimits.Get(action, 0)
        return limit == -1 || attempt <= limit
    }

    static WaitBeforeRetry(cancelled) {
        loop Ceil(this.RetryDelayMs / this.RetryPollMs) {
            if (cancelled())
                return false
            Sleep(this.RetryPollMs)
        }
        return !cancelled()
    }
}
