#Requires AutoHotkey v2

/**
 * The WinEvent class can monitor window events for all windows or specific windows.  
 * Currently the following events are supported: `Show`, `Create`, `Close`, `Exist`, `NotExist`, `Active`, `NotActive`, `Move`, 
 * `MoveStart`, `MoveEnd`, `Minimize`, `Restore`, `Maximize`. See comments for the functions for more information.
 * 
 * All the event initiation methods have the same syntax: 
 * `WinEvent.EventType(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="")`
 *      where Callback is the function that will be called once the event happened, and Count specifies
 *      the maximum amount of callbacks. 
 * `Close` and `NotExist` additionally have the `PropertyCallback` argument as the last one, which accepts
 *      a window handle and returns property/properties of interest. Eg `Callback(hWnd) => WinGetTitle(hWnd)`
 *      This callback gets called when a matching window is created or the window title changes.
 * The function returns an event hook object that describes the hook (see descriptions down below).
 * NOTE: if all WinTitle criteria are left empty then any window will match. To match for Last Found
 *       Window, use WinExist() as WinTitle.
 * 
 * `Callback(hWnd, eventObj, dwmsEventTime)`
 *      `hWnd`         : the window handle that triggered the event
 *      `eventObj`     : the event hook object describing the hook (see the next section about "Hook object")
 *      `dwmsEventTime`: the `A_TickCount` for when the event happened
 *      `properties`   : only used for `Close` and `NotExist`: contains the latest result of `PropertyCallback`
 * If the callback returns 0 (default return value of functions) then `EventHook.Count` is decremented by one.
 * Otherwise the count is not decremented.
 * 
 * Hook object properties:
 * `EventHook.EventType`
 *      The name of the event type (Show, Close, etc)
 * `EventHook.MatchCriteria`
 *      The window matching criteria in array format `[WinTitle, WinText, ExcludeTitle, ExcludeText]`
 * `EventHook.Callback`
 *      The callback function
 * `EventHook.Count`
 *      The current count of how many times the callback may be called
 * `EventHook.Pause(NewState:=1)
 *      Pauses or unpauses the hook. 1 = pause, 0 = unpause, -1 = toggle
 * `EventHook.IsPaused`
 *      Used to get or set whether the hook is currently active or paused
 * `EventHook.TitleMatchMode`
 * `EventHook.TitleMatchModeSpeed
 * `EventHook.DetectHiddenWindows`
 * `EventHook.DetectHiddenText`
 *      Contain the corresponding values of AHK built-in variables, and are initialized to the same
 *      values as at the time of hook creation (with the exception of Create and Show, which
 *      are initialized with 1/True). 
 * 
 * Hook object methods:
 * `EventHook.Stop()`
 *      Stops the event hook
 * 
 * WinEvent methods (in addition to the event methods):
 * `WinEvent.Stop(EventType?, WinTitle:="", WinText:="", ExcludeTitle:="", ExcludeText:="")`
 *      Stops one or all event hooks.
 * `WinEvent.Pause(NewState:=1)
 *      Pauses or unpauses all event hooks. 1 = pause, 0 = unpause, -1 = toggle
 * `WinEvent.IsRegistered(EventType, WinTitle:="", WinText:="", ExcludeTitle:="", ExcludeText:="")
 *      Checks whether an event with the specified type and criteria is registered.
 * `WinEvent.IsEventTypeRegistered(EventType)`
 *      Checks whether any events for a given event type are registered.
 * 
 * WinEvent properties:
 * `WinEvent.IsPaused`
 *      Can be used to get or set the paused state of all events. 
 * 
 * NOTE: if an event is registered then the script automatically becomes persistent and the persistency
 * is not automatically removed when the events are deregistered. Additionally, when event handlers
 * are removed then a timer is set for 60 seconds to remove an internal callback pointer, which means
 * simply removing persistency from the script won't cause it to exit immediately (if there are no
 * other reasons to stay open). To exit immediately after stopping the hooks, use `ExitApp`.
 * 
 */
class WinEvent {
    ; A curated list of event enumerations
    static EVENT_OBJECT_CREATE         := 0x8000,
           EVENT_OBJECT_DESTROY        := 0x8001,
           EVENT_OBJECT_SHOW           := 0x8002,
           EVENT_OBJECT_FOCUS          := 0x8005,
           EVENT_OBJECT_LOCATIONCHANGE := 0x800B,
           EVENT_SYSTEM_MINIMIZESTART  := 0x0016,
           EVENT_SYSTEM_MINIMIZEEND    := 0x0017,
           EVENT_SYSTEM_MOVESIZESTART  := 0x000A,
           EVENT_SYSTEM_MOVESIZEEND    := 0x000B,
           EVENT_SYSTEM_FOREGROUND     := 0x0003,
           EVENT_OBJECT_NAMECHANGE     := 0x800C,
           EVENT_OBJECT_CLOAKED        := 0x8017,
           EVENT_OBJECT_HIDE           := 0x8003

    /**
     * When a window is shown. Usually the window is detectable with DetectHiddenWindows disabled,
     * but testing shows that some windows trigger the Show event and remain hidden for some time.
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Show(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") =>
        this("Show", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is created, but not necessarily shown. 
     * This may return hidden windows (may require DetectHiddenWindows True).
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Create(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Create", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])
    
    /**
     * When a window is destroyed, closed, or hidden (if DetectHiddenWindows is Off). This differs 
     * from `WinWaitClose` in the aspect that a window title change does not trigger the callback. 
     * Use `NotExist` to also trigger with title changes. 
     * @param {(hWnd, eventObj, dwmsEventTime, properties) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * - `properties`   : result of `PropertyCallback`
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @param {(hWnd) => Any} PropertyCallback An optional callback function that gets called once a
     * new window matching the criteria is created or happens due to a title change.
     * @returns {WinEvent} 
     */
    static Close(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="", PropertyCallback:="") => 
        this("Close", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText], PropertyCallback)

    /**
     * When a window with a specified title exists (triggered after a window is created or title is changed).
     * This may return hidden windows (may require DetectHiddenWindows True).
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Exist(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Exist", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window no longer matches the WinTitle criteria, either after being destroyed or after a title change
     * @param {(hWnd, eventObj, dwmsEventTime, properties) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * - `properties`   : the result of `PropertyCallback`
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @param {(hWnd) => Any} PropertyCallback An optional callback function that gets called once a
     * new window matching the criteria is created or happens due to a title change.
     * @returns {WinEvent} 
     */
    static NotExist(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="", PropertyCallback:="") => 
        this("NotExist", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText], PropertyCallback)

    /**
     * When a window is activated/focused
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Active(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Active", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is inactivated/unfocused
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static NotActive(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") {
        if WinTitle = "A"
            this.__WinGetCurrentTitle(&WinTitle, WinText, ExcludeTitle, ExcludeText)
        return this("NotActive", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])
    }

    /**
     * When a window is moved or resized
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Move(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Move", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is starting to be moved or resized
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static MoveStart(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("MoveStart", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window has been moved or resized
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static MoveEnd(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("MoveEnd", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is minimized
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Minimize(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Minimize", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is restored
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Restore(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Restore", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * When a window is maximized
     * @param {(hWnd, eventObj, dwmsEventTime) => Integer} Callback
     * - `hWnd`         : the window handle that triggered the event
     * - `dwmsEventTime`: the `A_TickCount` for when the event happened
     * @param {Number} Count Limits the number of times the callback will be called (eg for a one-time event set `Count` to 1).
     * @returns {WinEvent} 
     */
    static Maximize(Callback, WinTitle:="", Count:=-1, WinText:="", ExcludeTitle:="", ExcludeText:="") => 
        this("Maximize", Callback, Count, [WinTitle, WinText, ExcludeTitle, ExcludeText])

    /**
     * Stops one or all event hooks
     * @param EventType The name of the event function (eg Close).
     * If this isn't specified then all event hooks will be stopped.
     */
    static Stop(EventType?, WinTitle:="", WinText:="", ExcludeTitle:="", ExcludeText:="") {
        local MatchMap, Hook
        if !IsSet(EventType) {
            for EventType, MatchMap in this.__RegisteredEvents
                for MatchCriteria, Hook in MatchMap
                    Hook.Stop()
            this.__New()
            return
        }
        if !this.__RegisteredEvents.Has(EventType)
            return
        WinTitle := this.__DeobjectifyWinTitle(WinTitle)
        for MatchCriteria, EventObj in this.__RegisteredEvents[EventType].Clone()
            if MatchCriteria[1] = WinTitle && MatchCriteria[2] = WinText && MatchCriteria[3] = ExcludeTitle && MatchCriteria[4] = ExcludeText
                EventObj.Stop()
    }

    /**
     * Pauses or unpauses all event hooks. This can also be get/set via the `WinEvent.IsPaused` property. 
     * @param {Integer} NewState 1 = pause, 0 = unpause, -1 = toggle pause state.
     */
    static Pause(NewState := 1) => (this.IsPaused := NewState = -1 ? !this.IsPaused : NewState)

    /**
     * Checks whether an event with the specified type and criteria is registered
     * @param EventType The name of the event function (eg Close)
     */
    static IsRegistered(EventType, WinTitle:="", WinText:="", ExcludeTitle:="", ExcludeText:="") {
        if !this.__RegisteredEvents.Has(EventType)
            return 0
        WinTitle := this.__DeobjectifyWinTitle(WinTitle)
        for MatchCriteria, EventObj in this.__RegisteredEvents[EventType]
            if MatchCriteria[1] = WinTitle && MatchCriteria[2] = WinText && MatchCriteria[3] = ExcludeTitle && MatchCriteria[4] = ExcludeText
                return 1
        return 0
    }

    /**
     * Checks whether any events for a given event type are registered
     * @param EventType The name of the event function (eg Close)
     */
    static IsEventTypeRegistered(EventType) => this.__RegisteredEvents.Has(EventType)

    ; Stops the event hook, same as if the object was destroyed.
    Stop() => (this.Callback := "", this.__Delete(), this.MatchCriteria := "")

    /**
     * Pauses or unpauses the event hook. This can also be get/set via the `EventHook.IsPaused` property. 
     * @param {Integer} NewState 1 = pause, 0 = unpause, -1 = toggle pause state.
     */
    Pause(NewState := 1) => (this.IsPaused := NewState = -1 ? !this.IsPaused : NewState)

    class Hook {
        /**
         * Sets a new event hook using SetWinEventHook and returns on object describing the hook. 
         * When the object is released, the hook is also released.
         * @param {(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) => Integer} callbackFunc The function that will be called, which needs to accept 7 arguments.
         * @param {Integer} [eventMin] Optional: Specifies the event constant for the lowest event value in the range of events that are handled by the hook function.  
         *  Default is the lowest possible event value.  
         * - See more about [event constants](https://learn.microsoft.com/en-us/windows/win32/winauto/event-constants)
         * - [Msaa Events List](Https://Msdn.Microsoft.Com/En-Us/Library/Windows/Desktop/Dd318066(V=Vs.85).Aspx)
         * - [System-Level And Object-Level Events](Https://Msdn.Microsoft.Com/En-Us/Library/Windows/Desktop/Dd373657(V=Vs.85).Aspx)
         * - [Console Accessibility](Https://Msdn.Microsoft.Com/En-Us/Library/Ms971319.Aspx)
         * @param {Integer} [eventMax] Optional: Specifies the event constant for the highest event value in the range of events that are handled by the hook function.
         *  If eventMin is omitted then the default is the highest possible event value.
         *  If eventMin is specified then the default is eventMin.
         * @param {Integer|String} [winTitle=0] Optional: WinTitle of a certain window to hook to. Default is system-wide hook.
         * @param {Integer} [PID=0] Optional: process ID of the process for which threads to hook to. Default is system-wide hook.
         * @param {Integer} [flags=0] Flag values that specify the location of the hook function and of the events to be skipped.
         *  Default is `WINEVENT_OUTOFCONTEXT` = 0. 
         * @returns {WinEventHook} 
         */
        __New(callbackFunc, eventMin?, eventMax?, winTitle := 0, PID := 0, flags := 0) {
            Persistent()
            if !IsSet(eventMin)
                eventMin := 0x00000001, eventMax := IsSet(eventMax) ? eventMax : 0x7fffffff
            else if !IsSet(eventMax)
                eventMax := eventMin
            if !HasMethod(callbackFunc)
                throw ValueError("The callbackFunc argument must be a function", -1)
            this.callback := callbackFunc, this.winTitle := winTitle, this.flags := flags, this.eventMin := eventMin, this.eventMax := eventMax, this.threadId := 0
            if winTitle != 0 {
                if !(this.winTitle := WinExist(winTitle))
                    throw TargetError("Window not found", -1)
                this.threadId := DllCall("GetWindowThreadProcessId", "Int", this.winTitle, "UInt*", &PID)
            }
            this.pCallback := CallbackCreate(callbackFunc,, 7)
            , this.hHook := DllCall("SetWinEventHook", "UInt", eventMin, "UInt", eventMax, "Ptr", 0, "Ptr", this.pCallback, "UInt", this.PID := PID, "UInt", this.threadId, "UInt", flags)
        }
        __Delete() {
            DllCall("UnhookWinEvent", "Ptr", this.hHook)
            SetTimer(CallbackFree.Bind(this.pCallback), -60000) ; This needs to be done with a latency to let the message queue empty of unfired events
        }
    }

    ; ONLY INTERNAL METHODS AHEAD

    static __RequiredHooks := Map("Show", [this.EVENT_OBJECT_SHOW], "Create", [this.EVENT_OBJECT_CREATE]
        , "Close", [this.EVENT_OBJECT_CREATE, this.EVENT_OBJECT_SHOW, this.EVENT_OBJECT_NAMECHANGE, this.EVENT_OBJECT_DESTROY, this.EVENT_OBJECT_CLOAKED, this.EVENT_OBJECT_HIDE]
        , "Exist", [this.EVENT_OBJECT_CREATE, this.EVENT_OBJECT_SHOW, this.EVENT_OBJECT_NAMECHANGE]
        , "NotExist", [this.EVENT_OBJECT_CREATE, this.EVENT_OBJECT_SHOW, this.EVENT_OBJECT_NAMECHANGE, this.EVENT_OBJECT_DESTROY, this.EVENT_OBJECT_CLOAKED, this.EVENT_OBJECT_HIDE]
        , "Active", [this.EVENT_SYSTEM_FOREGROUND, this.EVENT_OBJECT_NAMECHANGE], "NotActive", [this.EVENT_SYSTEM_FOREGROUND, this.EVENT_OBJECT_NAMECHANGE]
        , "Move", [this.EVENT_OBJECT_LOCATIONCHANGE], "MoveStart", [this.EVENT_SYSTEM_MOVESIZESTART]
        , "MoveEnd", [this.EVENT_SYSTEM_MOVESIZEEND], "Minimize", [this.EVENT_SYSTEM_MINIMIZESTART]
        , "Restore", [this.EVENT_SYSTEM_MINIMIZEEND, this.EVENT_OBJECT_LOCATIONCHANGE], "Maximize", [this.EVENT_OBJECT_LOCATIONCHANGE])

    ; Internal variables: keep track of registered events (the match criteria) and registered window hooks
    static __RegisteredEvents := Map(), __Hooks := Map(), __EventQueue := [], IsPaused := 0

    static __New() {
        this.Prototype.__WinEvent := this
        this.__RegisteredEvents := Map(), this.__RegisteredEvents.CaseSense := 0, this.__RegisteredEvents.Default := Map()
        this.__Hooks := Map(), this.__Hooks.CaseSense := 0
    }
    static __Delete() {
        for key, hook in this.__Hooks
            this.__Hooks.Delete(key)
    }
    ; Extracts hWnd property from an object-type WinTitle
    static __DeobjectifyWinTitle(WinTitle) => (IsObject(WinTitle) ? WinTitle.hWnd : WinTitle)
    ; Activates all necessary window hooks for a given WinEvent type
    static __AddRequiredHooks(EventType) {
        local _, Hook
        for _, Hook in this.__RequiredHooks[EventType]
            this.__AddHook(Hook)
    }
    ; Removes (and/or decreases ref count) all necessary window hooks for a given WinEvent type
    static __RemoveRequiredHooks(EventType) {
        local _, Hook
        for _, Hook in this.__RequiredHooks[EventType]
            this.__RemoveHook(Hook)
    }
    ; Internal use: activates a new hook if not already active and increases its reference count
    static __AddHook(Hook) {
        static BoundHandleWinEvent := this.__HandleWinEvent.Bind(this)
        if !this.__Hooks.Has(Hook)
            this.__Hooks[Hook] := this.Hook(BoundHandleWinEvent, Hook), this.__Hooks[Hook].RefCount := 0
        this.__Hooks[Hook].RefCount++
    }
    ; Internal use: decreases a hooks reference count and removes it if it falls to 0
    static __RemoveHook(Hook) {
        this.__Hooks[Hook].RefCount--
        if !this.__Hooks[Hook].RefCount
            this.__Hooks.Delete(Hook)
    }
    ; Internal use: creates a new WinEvent object, which contains info about the registered event
    ; such as the type, callback function, match criteria etc.
    __New(EventType, Callback, Count, MatchCriteria, PropertyCallback:="") {
        __WinEvent := this.__WinEvent, this.EventType := EventType, this.MatchCriteria := MatchCriteria
            , this.Callback := Callback, this.Count := Count, this.IsPaused := 0
            , this.TitleMatchMode := A_TitleMatchMode, this.TitleMatchModeSpeed := A_TitleMatchModeSpeed
            , this.DetectHiddenWindows := A_DetectHiddenWindows, this.DetectHiddenText := A_DetectHiddenText
            , this.PropertyCallback := PropertyCallback, this.MatchingWinList := Map()
        MatchCriteria[1] := __WinEvent.__DeobjectifyWinTitle(MatchCriteria[1])
        this.MatchCriteria.IsBlank := (MatchCriteria[1] == "" && MatchCriteria[2] == "" && MatchCriteria[3] == "" && MatchCriteria[4] == "")
        if InStr(MatchCriteria[1], "ahk_id")
            this.MatchCriteria.ahk_id := (RegExMatch(MatchCriteria[1], "ahk_id\s*([^\s]+)", &match) ? (match[1] ? Integer(match[1]) : 0) : 0)
        else if IsInteger(MatchCriteria[1])
            this.MatchCriteria.ahk_id := MatchCriteria[1]
        else
            this.MatchCriteria.ahk_id := 0
        if EventType = "Close" || EventType = "NotExist" || EventType = "Restore" {
            for hWnd in WinGetList(MatchCriteria*)
                this.__UpdateMatchingWinList(hWnd)
        } else if EventType = "NotActive" {
            try this.__IsActive := WinActive(MatchCriteria*)
            catch
                this.__IsActive := 0
        } else if EventType = "Exist" {
            for hWnd in WinGetList(MatchCriteria*)
                this.__UpdateMatchingWinList(hWnd)
            if hWnd := WinExist(MatchCriteria*)
                __WinEvent.__AddCallbackToQueue(hWnd, this, A_TickCount)
        } else if EventType = "Create" || EventType = "Show" {
            this.DetectHiddenWindows := 1, this.DetectHiddenText := 1
        }
        if !__WinEvent.__RegisteredEvents.Has(EventType)
            __WinEvent.__RegisteredEvents[EventType] := Map()
        __WinEvent.__RegisteredEvents[EventType][MatchCriteria] := this
        __WinEvent.__AddRequiredHooks(EventType)
        __WinEvent.__EmptyEventQueue()
    }
    ; Internal use: once a WinEvent object is destroyed, deregister the match criteria and remove 
    ; the hook (if no other WinEvent objects depend on it)
    __Delete() {
        if !this.MatchCriteria
            return
        this.__WinEvent.__RemoveRequiredHooks(this.EventType)
        try this.__WinEvent.__RegisteredEvents[this.EventType].Delete(this.MatchCriteria)
    }
    ; Internal use: adds the callback function to a queue that gets emptied at the end of __HandleWinEvent.
    static __AddCallbackToQueue(hWnd, HookObj, args*) => HookObj.Callback ? this.__EventQueue.Push(HookObj.Callback.Bind(hWnd, HookObj, args*), HookObj) : 0
    ; Internal use: calls all callbacks in a new pseudo-thread
    static __EmptyEventQueue() {
        static EmptyingActive := 0
        if EmptyingActive
            return
        EmptyingActive := 1
        try {
            while this.__EventQueue.Length && (CB := this.__EventQueue.RemoveAt(1)) && (HookObj := this.__EventQueue.RemoveAt(1)) {
                if HookObj.Callback = ""
                    continue
                pCB := CallbackCreate(CB,, 0), ret := DllCall(pCB), CallbackFree(pCB) ; Call in a new pseudo-thread
                if ret=0 && --HookObj.Count = 0
                    HookObj.Stop()
            }
        } finally {
            EmptyingActive := 0
        }
    }
    ; Internal use: handles the event called by SetWinEventHook. 
    static __HandleWinEvent(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
        Critical -1
        static OBJID_WINDOW := 0, OBJID_CURSOR := 0xFFFFFFF7, INDEXID_CONTAINER := 0, EVENT_OBJECT_CREATE := 0x8000, EVENT_OBJECT_DESTROY := 0x8001
            , EVENT_OBJECT_SHOW := 0x8002, EVENT_OBJECT_FOCUS := 0x8005, EVENT_OBJECT_LOCATIONCHANGE := 0x800B, EVENT_SYSTEM_MINIMIZESTART := 0x0016
            , EVENT_SYSTEM_MINIMIZEEND := 0x0017, EVENT_SYSTEM_MOVESIZESTART := 0x000A, EVENT_SYSTEM_MOVESIZEEND := 0x000B, EVENT_SYSTEM_FOREGROUND := 0x0003
            , EVENT_OBJECT_NAMECHANGE := 0x800C, EVENT_OBJECT_CLOAKED := 0x8017, EVENT_OBJECT_HIDE := 0x8003 ; These are duplicated here for performance reasons
        if this.IsPaused
            return

        idObject := idObject << 32 >> 32, idChild := idChild << 32 >> 32, event &= 0xFFFFFFFF, idEventThread &= 0xFFFFFFFF, dwmsEventTime &= 0xFFFFFFFF ; convert to INT/UINT
        if idObject != OBJID_WINDOW || idChild != INDEXID_CONTAINER || hWnd = 0
            return

        local HookObj, MatchCriteria

        if (event = EVENT_OBJECT_DESTROY || event = EVENT_OBJECT_CLOAKED || event = EVENT_OBJECT_HIDE) {
            static WinCloseEventNames := ["Close", "NotExist"]
            for EventName in WinCloseEventNames
                for MatchCriteria, HookObj in this.__RegisteredEvents[EventName] {
                    if !HookObj.IsPaused && HookObj.MatchingWinList.Has(hWnd) && !WinExist(HookObj.DetectHiddenWindows ? hWnd : "ahk_id" hWnd)
                        this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime, HookObj.MatchingWinList[hWnd])
                    HookObj.__UpdateMatchingWinList(hWnd)
                }
            goto Cleanup
        }
        if !(hWnd = DllCall("GetAncestor", "Ptr", hWnd, "UInt", 2, "Ptr")) || (event = EVENT_SYSTEM_FOREGROUND && hWnd != DllCall("GetForegroundWindow", "ptr"))
            goto Cleanup
        if (event = EVENT_OBJECT_NAMECHANGE || event = EVENT_OBJECT_CREATE || event = EVENT_OBJECT_SHOW) {
            if (event = EVENT_OBJECT_NAMECHANGE) {
                for MatchCriteria, HookObj in this.__RegisteredEvents["NotExist"] {
                    if !HookObj.IsPaused && HookObj.MatchingWinList.Has(hWnd) && !((A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText, A_TitleMatchMode := HookObj.TitleMatchMode, A_TitleMatchModeSpeed := HookObj.TitleMatchModeSpeed, 
                        MatchCriteria.ahk_id) ? MatchCriteria.ahk_id = hWnd && WinExist(MatchCriteria*) : WinExist(MatchCriteria[1] " ahk_id " hWnd, MatchCriteria[2], MatchCriteria[3], MatchCriteria[4]))
                        this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime, HookObj.MatchingWinList[hWnd])
                }
            }
            static WindowChangeEventNames := ["Close", "NotExist", "Restore"]
            for EventName in WindowChangeEventNames {
                for MatchCriteria, HookObj in this.__RegisteredEvents[EventName]
                    HookObj.__UpdateMatchingWinList(hWnd)
            }
        }
        if (event = EVENT_OBJECT_LOCATIONCHANGE) {
            for MatchCriteria, HookObj in this.__RegisteredEvents["Maximize"] {
                if !HookObj.IsPaused && (MatchCriteria.IsBlank || ((A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText, A_TitleMatchMode := HookObj.TitleMatchMode, A_TitleMatchModeSpeed := HookObj.TitleMatchModeSpeed, 
                    MatchCriteria.ahk_id) ? MatchCriteria.ahk_id = hWnd && WinExist(MatchCriteria*) : WinExist(MatchCriteria[1] " ahk_id " hWnd, MatchCriteria[2], MatchCriteria[3], MatchCriteria[4]))) {
                    try {
                        if WinGetMinMax(hWnd) != 1
                            continue
                    } catch
                        continue
                    this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime)
                }
            }
            for MatchCriteria, HookObj in this.__RegisteredEvents["Restore"] {
                if !HookObj.IsPaused && HookObj.MatchingWinList.Has(hWnd) && HookObj.MatchingWinList[hWnd] = 1
                    && (MatchCriteria.IsBlank || ((A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText, A_TitleMatchMode := HookObj.TitleMatchMode, A_TitleMatchModeSpeed := HookObj.TitleMatchModeSpeed, 
                        MatchCriteria.ahk_id) ? MatchCriteria.ahk_id = hWnd && WinExist(MatchCriteria*) : WinExist(MatchCriteria[1] " ahk_id " hWnd, MatchCriteria[2], MatchCriteria[3], MatchCriteria[4]))) {
                    this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime)
                }
                HookObj.__UpdateMatchingWinList(hWnd)
            }
        }
        if ((event = EVENT_OBJECT_LOCATIONCHANGE && EventName := "Move")
            || (event = EVENT_OBJECT_CREATE && EventName := "Create") 
            || (event = EVENT_OBJECT_SHOW && EventName := "Show")
            || (event = EVENT_SYSTEM_MOVESIZESTART && EventName := "MoveStart")
            || (event = EVENT_SYSTEM_MOVESIZEEND && EventName := "MoveEnd")
            || (event = EVENT_SYSTEM_MINIMIZESTART && EventName := "Minimize")
            || (event = EVENT_SYSTEM_MINIMIZEEND && EventName := "Restore")
            || (event = EVENT_SYSTEM_FOREGROUND && EventName := "Active")
            || (event = EVENT_OBJECT_NAMECHANGE && hWnd = WinExist("A") && EventName := "Active")) {
            for MatchCriteria, HookObj in this.__RegisteredEvents[EventName] {
                if !HookObj.IsPaused && (MatchCriteria.IsBlank || ((A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText, A_TitleMatchMode := HookObj.TitleMatchMode, A_TitleMatchModeSpeed := HookObj.TitleMatchModeSpeed, 
                    MatchCriteria.ahk_id) ? MatchCriteria.ahk_id = hWnd && WinExist(MatchCriteria*) : WinExist(MatchCriteria[1] " ahk_id " hWnd, MatchCriteria[2], MatchCriteria[3], MatchCriteria[4])))
                    this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime)
            }
        }
        if (event = EVENT_OBJECT_CREATE || event = EVENT_OBJECT_SHOW || event = EVENT_OBJECT_NAMECHANGE) {
            for MatchCriteria, HookObj in this.__RegisteredEvents["Exist"] {
                if !HookObj.IsPaused && !HookObj.MatchingWinList.Has(hWnd) && (MatchCriteria.IsBlank || ((A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText, A_TitleMatchMode := HookObj.TitleMatchMode, A_TitleMatchModeSpeed := HookObj.TitleMatchModeSpeed, 
                    MatchCriteria.ahk_id) ? MatchCriteria.ahk_id = hWnd && WinExist(MatchCriteria*) : WinExist(MatchCriteria[1] " ahk_id " hWnd, MatchCriteria[2], MatchCriteria[3], MatchCriteria[4])))
                    this.__AddCallbackToQueue(hWnd, HookObj, dwmsEventTime)
                HookObj.__UpdateMatchingWinList(hWnd)
            }
        }
        if (event = EVENT_SYSTEM_FOREGROUND || event = EVENT_OBJECT_NAMECHANGE) {
            for MatchCriteria, HookObj in this.__RegisteredEvents["NotActive"] {
                A_DetectHiddenWindows := HookObj.DetectHiddenWindows, A_DetectHiddenText := HookObj.DetectHiddenText
                hWndActive := WinActive(MatchCriteria*)
                if !hWndActive && !HookObj.IsPaused && HookObj.__IsActive {
                    this.__AddCallbackToQueue(HookObj.__IsActive, HookObj, dwmsEventTime)
                    HookObj.__IsActive := 0
                }
                if hWndActive = hWnd
                    HookObj.__IsActive := hWnd
            }
        }
        Cleanup:
        Critical("Off")
        this.__EmptyEventQueue()
    }
    ; Internal use: keeps track of open windows that match the criteria, because matching for name
    ; class etc wouldn't work after the window is already destroyed. 
    __UpdateMatchingWinList(TriggerhWnd:=0, AddOnly:=0) {
        if !this.MatchCriteria || !TriggerhWnd
            return
        local PrevDHW := DetectHiddenWindows(this.DetectHiddenWindows), PrevDHT := DetectHiddenText(this.DetectHiddenText)
        if this.MatchCriteria.ahk_id ? TriggerhWnd == this.MatchCriteria.ahk_id : WinExist(this.MatchCriteria[1] " ahk_id " TriggerhWnd, this.MatchCriteria[2], this.MatchCriteria[3], this.MatchCriteria[4]) {
            Properties := this.MatchingWinList.Has(TriggerhWnd) ? this.MatchingWinList[TriggerhWnd] : 1
            if this.EventType = "Restore" {
                try Properties := WinGetMinMax(TriggerhWnd)
            } else if this.PropertyCallback {
                try Properties := this.PropertyCallback.Call(TriggerhWnd)
                catch
                    Properties := "ERROR"
            }
            this.MatchingWinList[TriggerhWnd] := Properties
        } else if this.MatchingWinList.Has(TriggerhWnd) && !AddOnly
            this.MatchingWinList.Delete(TriggerhWnd)
        DetectHiddenWindows(PrevDHW), DetectHiddenText(PrevDHT)
    }
    static __WinGetCurrentTitle(&WinTitle:="", WinText:="", ExcludeTitle:="", ExcludeText:="") {
        local hWnd
        if !(hWnd := WinExist(WinTitle, WinText, ExcludeTitle, ExcludeText))
            return 0
        try WinTitle := WinTitle ? WinGetTitle(hWnd) : ""
        return hWnd
    }
}