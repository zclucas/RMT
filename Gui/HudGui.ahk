#Requires AutoHotkey v2.0

; =====================================================================
; 悬浮显示（HUD）：输出指令的一种输出方式
;
; 职责划分
;   本文件只提供数据与配置：显示文本、位置模式/锚点/坐标，不计算尺寸与坐标。
;   布局、定位、跟随目标窗口与拖动由引擎侧实现（HudHost.cs）。
;
; 协议
;   HUD|Bind|mode;anchor;x;y;targetHwnd;maxWidth;shmName
;   HUD|Text|<文本>                        异步合并，同帧仅渲染最后一帧
;   EVENT ...|Window|HudMoved|left,top     拖动结束回传坐标，由本文件持久化
;
; 生命周期与宏一致：宏停止或终止时关闭。
; =====================================================================

; 位置下拉标签，顺序与指令界面一致
HudPosLabels() {
    return ["窗口右上", "窗口左上", "窗口右下", "窗口左下", "窗口居中",
        "屏幕左上", "屏幕右上", "屏幕居中", "屏幕右下", "自定义"]
}

; 标签 → 引擎参数 [mode, anchor]
;   mode 2 跟随绑定窗口 / 1 整屏 / 0 固定坐标（自定义）
;   anchor 0 左上 1 左中 2 左下 3 中上 4 中心 5 中下 6 右上 7 右中 8 右下
HudPosSpec(pos) {
    switch pos {
        case "窗口左上": return [2, 0]
        case "窗口左下": return [2, 2]
        case "窗口居中": return [2, 4]
        case "窗口右下": return [2, 8]
        case "屏幕左上": return [1, 0]
        case "屏幕右上": return [1, 6]
        case "屏幕居中": return [1, 4]
        case "屏幕右下": return [1, 8]
        default:         return [2, 6]   ; 窗口右上
    }
}

class HudGui {
    __new(tableItem, itemIndex) {
        this.tableItem := tableItem
        this.itemIndex := itemIndex
        this.serialStr := ""
        this.ui := ""
        this._opened := false
        this._content := ""
        this._lastShown := ""
        this._targetHwnd := 0
        this._openTick := 0        ; Show 成功时刻；用于识别句柄长期未返回的异常窗口
        this._lastPushTick := 0    ; 上次送文本的时刻（限速）
    }

    _Item() {
        if (!IsObject(this.tableItem) || this.itemIndex < 1 || this.itemIndex > this.tableItem.Items.Length)
            return ""
        return this.tableItem.Items[this.itemIndex]
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    IsOpen() {
        ; 不能用 Hwnd() 判断：Show() 后窗口异步创建，wpfHwnd 此刻仍为 0，
        ; 会误判为未打开并触发反复重建。
        return this._opened && IsObject(this.ui)
    }

    ; ---------------------------------------------------------------
    ; 显示 / 更新
    ; ---------------------------------------------------------------
    Show(serialStr, content) {
        item := this._Item()
        if (!IsObject(item) || content == "") {
            this.Close()
            return
        }
        this.serialStr := serialStr
        ; 统一换行为 \n，Worker 侧文本可能含 \r
        this._content := StrReplace(StrReplace(content, "`r`n", "`n"), "`r", "`n")

        if (!this._opened) {
            this._lastShown := this._content
            this._Open(item)
            return
        }
        if (this._content == this._lastShown)
            return
        this._lastShown := this._content
        ; 仅发送文本；尺寸、锚点与跟随由引擎处理
        try this.ui.Update("HUD", "Text", this._content)
    }

    ; 窗口存在时仅更新文本，不查表、不建窗，可在 Worker 事件回调中直接调用。
    ; 返回 false 表示当前无可用窗口，调用方需走建窗流程。
    UpdateContent(content) {
        if (!this._opened || !IsObject(this.ui))
            return false

        hwnd := this.Hwnd()
        ; LoadedHwnd 丢失时引擎不返回句柄，其后的 Update 会进入 _updateQueue，
        ; 而该队列只在 LoadedHwnd 时冲刷，内容永远无法发出，窗口停留在首帧。
        ; 超时仍无句柄即视为无效窗口，关闭后由调用方重建。
        if (!hwnd && this._openTick && A_TickCount - this._openTick > 1500) {
            this.Close()
            return false
        }
        ; 句柄就绪后登记到 Worker 槽尾表：Worker 每帧查表，命中即直接向引擎投递，
        ; 该路径不经过主线程。
        if (hwnd)
            this._PublishHwnd(hwnd)

        c := StrReplace(StrReplace(content, "`r`n", "`n"), "`r", "`n")
        ; 内容未变化时跳过，省去一次跨进程往返
        if (c == this._lastShown)
            return true
        ; 限速约 60Hz：宏每秒可产生数百帧，引擎侧重排/重绘次数由此闸门决定。
        now := A_TickCount
        ; 阈值取 8ms：A_TickCount 精度为 15.6ms，阈值设 16ms 会丢弃间隔 15ms 的帧，
        ; 使实际帧率减半。节拍上限由 HudFlushPending 控制。
        if (this._lastPushTick && now - this._lastPushTick < 8)
            return true
        this._lastPushTick := now
        this._lastShown := c
        this._content := c

        ; 引擎侧的 HUD 文本走 0x004A（WM_COPYDATA）同步投递：WndProc 只更新
        ; PendingText，渲染由帧末合并完成，单次开销为一次字符串拷贝。
        try this.ui.Update("HUD", "Text", c)
        return true
    }

    ; 把引擎窗口句柄登记到所属 Worker 的 RMT_HUD 槽尾表，供 Worker 直连投递。
    ; 表布局：+65024 UInt32 项数；+65032 起每项 16 字节（serial / pad / hwnd）。
    ; 槽与 Worker 一一对应，基址由 ReadWorkerHud 在首次收到该指令的帧时登记到
    ; MyHudSlotMap；hwnd 传 0 表示摘除该项。
    _PublishHwnd(hwnd) {
        global MyHudSlotMap
        if (!IsSet(MyHudSlotMap) || !MyHudSlotMap.Has(this.serialStr))
            return
        p := MyHudSlotMap[this.serialStr]
        if (!p)
            return
        try key := Integer(this.serialStr)
        catch
            return
        count := NumGet(p, 65024, "UInt")
        if (count > 35)
            count := 35
        loop count {
            off := 65032 + (A_Index - 1) * 16
            if (NumGet(p, off, "UInt") != key)
                continue
            if (hwnd) {
                NumPut("Ptr", hwnd, p, off + 8)
            } else {
                ; 摘除：末项前移补位，避免项数只增不减
                last := 65032 + (count - 1) * 16
                if (off != last) {
                    NumPut("UInt", NumGet(p, last, "UInt"), p, off)
                    NumPut("Ptr", NumGet(p, last + 8, "Ptr"), p, off + 8)
                }
                NumPut("UInt", count - 1, p, 65024)
            }
            return
        }
        if (!hwnd)
            return
        off := 65032 + count * 16
        NumPut("UInt", key, p, off)
        NumPut("UInt", 0, p, off + 4)
        NumPut("Ptr", hwnd, p, off + 8)
        NumPut("UInt", count + 1, p, 65024)
    }

    _Open(item) {
        global MainSoftData
        data := this._Data()
        colors := MainSoftData.ThemeColors
        this._targetHwnd := this._ResolveTarget(item)

        ; 窗口重建：旧句柄指向已销毁的窗口，先摘除再等新句柄登记

        win := XAML_Generator("Window")
        win.SetProp("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        win.SetProp("xmlns:x", "http://schemas.microsoft.com/winfx/2006/xaml")
        win.WindowStyle("None").AllowsTransparency("True").Background("Transparent")
        win.ShowInTaskbar("False").Topmost("True").ResizeMode("NoResize")
        win.ShowActivated("False").WindowStartupLocation("Manual")
        ; 不设置宽高：尺寸由引擎按 SizeToContent 计算，写死会锁住布局

        ; Name="DragArea" 为引擎约定的拖动热区（引擎自行跟随鼠标，不使用 DragMove）
        border := win.Add("Border").Name("DragArea")
        border.CornerRadius(6).BorderThickness(1).Padding("14,8")
        border.Background(AppThemeUtil.ResolveColor(colors, "Win_InputBg"))
        border.BorderBrush(AppThemeUtil.ResolveColor(colors, "Win_InputStroke"))

        ; 换行、省略与对齐由引擎处理，此处只设置外观（字体、颜色）
        border.Add("TextBlock").Name("HudText")
            .Foreground(AppThemeUtil.ResolveColor(colors, "Win_InputText"))
            .FontFamily(MainSoftData.FontType)
            .FontSize(XAMLHost.FontSize(4))

        this.ui := XAMLHost(win.ToString(), "", 0)
        this.ui.skipFontScale := true
        ; 拖动结束由引擎回传坐标，此处仅负责持久化
        this.ui.OnEvent("Window", "HudMoved", ObjBindMethod(this, "_OnMoved"))
        ; 句柄未返回时 Update 进入队列，在 LoadedHwnd 时与首批更新合并为一次投递
        try this.ui.Update("HUD", "Bind", this._BindSpec(data))
        try this.ui.Update("HUD", "Text", this._content)

        try this.ui.Show()
        catch as err {
            this._opened := false
            this.ui := ""
            RMTLogSys(RMT_LV_ERROR, "HudGui", Format("悬浮窗建窗失败: {1}（行 {2}）", err.Message, err.Line))
            return
        }
        this._opened := true
        this._openTick := A_TickCount

        ; NOACTIVATE | TOOLWINDOW：不抢占焦点、不进入 Alt+Tab。
        ; 不得包含 TRANSPARENT(0x20)，否则窗口不接收鼠标消息，拖动失效。
        try WinSetExStyle("+0x08000080", "ahk_id " this.Hwnd())
    }

    ; 位置配置转引擎参数串，第 7 段为文本槽名称
    _BindSpec(data) {
        maxWidth := 420
        ; 第 7 段（文本槽名）留空：Worker 直连改走 WM_COPYDATA，引擎不再挂接共享内存
        if (IsObject(data) && data.HudPos == "自定义")
            return "0;0;" this._Int(data.HudX, 0) ";" this._Int(data.HudY, 0) ";0;" maxWidth ";"
        pos := (IsObject(data) && data.HudPos != "") ? data.HudPos : "窗口右上"
        spec := HudPosSpec(pos)
        return spec[1] ";" spec[2] ";0;0;" this._targetHwnd ";" maxWidth ";"
    }

    ; 拖动结束回调：坐标为 DIP，可直接作为下次的固定坐标
    _OnMoved(state, ctrlName, eventName) {
        v := state.Has("HudMoved") ? state["HudMoved"] : ""
        if (v == "")
            return
        parts := StrSplit(v, ",")
        if (parts.Length < 2)
            return
        this._SaveFreePos(Integer(parts[1]), Integer(parts[2]))
    }

    _SaveFreePos(x, y) {
        data := this._Data()
        if (!IsObject(data))
            return
        if (data.HudPos == "自定义" && data.HudX == x && data.HudY == y)
            return
        data.HudPos := "自定义"
        data.HudX := x
        data.HudY := y
        try SaveMacroCMDData(data)
    }

    Close() {
        ; 先摘除槽尾表项：窗口销毁后，Worker 查不到句柄会回退主进程路径并触发重建
        this._PublishHwnd(0)
        if (IsObject(this.ui))
            try this.ui.Update("Window", "Close", "")
        this.ui := ""
        this._opened := false
        this._openTick := 0
        this._lastShown := ""
    }

    _Data() {
        if (this.serialStr == "")
            return ""
        try {
            return GetMacroCMDData(this.serialStr)
        } catch {
            return ""
        }
    }

    _ResolveTarget(item) {
        try {
            winInfo := ResolveBindWindow(this.tableItem, this.itemIndex, "{宏设置窗口绑定}")
            if (winInfo == "")
                return 0
            hwnds := GetHwndList(winInfo)
            hwnd := hwnds.Length ? hwnds[1] : 0
            if (hwnd && !WinExist("ahk_id " hwnd))
                return 0
            return hwnd
        } catch {
            return 0
        }
    }

    _Int(v, def) {
        if (IsInteger(v))
            return v
        if (IsNumber(v))
            return Integer(v)
        return def
    }
}

; =====================================================================
; 生命周期
; =====================================================================
global MyHudMap := Map()

; ---------------------------------------------------------------
; 活动窗口表：serial（指令序列码）→ HudGui 实例。
;
; 读槽为事件驱动，无轮询定时器：Worker 写槽 → PostMessage 通知 → OnWorkerToMaster
; 首先读槽。投递队列满时该通知可能失败，两侧各有兜底：Worker 侧保留 pending
; 下一帧重试；主进程侧任一 Worker 消息到达都先读槽。故通知丢失不会使窗口停更。
; ---------------------------------------------------------------

; ---------------------------------------------------------------
; 更新入口，可从 Worker 消息回调中调用
;
; 不在回调中直接建窗：建窗为同步 IPC，多宏同时启动会相互阻塞。
; 先记入待处理表，在消息空闲时批量执行（与 CountDown 做法一致）。
; 同一指令的多次更新只保留最后一次，天然合并。
; ---------------------------------------------------------------
global HudPending := Map()
global HudFlushScheduled := false
global HudLastFlush := 0

HudQueueUpdate(serialStr, content, tID, iID) {
    global HudPending, HudFlushScheduled, HudLastFlush
    serialStr := String(serialStr)
    if (serialStr == "")
        return

    HudPending[serialStr] := { content: content, tID: tID, iID: iID }
    if (HudFlushScheduled)
        return

    ; 节拍 16ms（约 60Hz）：显示帧率上限，宏产生再快也只取最后一帧。
    ; 早期取 30ms 是为降低 SetTimer 插队频率；共享内存通道下单帧成本约 0.15ms，
    ; 16ms 不构成可感知开销。
    HudFlushScheduled := true
    wait := 16 - (A_TickCount - HudLastFlush)
    if (wait < 1)
        wait := 1
    SetTimer(HudFlushPending, -wait)
}

HudFlushPending() {
    global HudPending, HudFlushScheduled, MySoftData, MyHudMap, HudLastFlush
    HudFlushScheduled := false
    HudLastFlush := A_TickCount
    if (HudPending.Count == 0)
        return

    batch := HudPending
    HudPending := Map()

    for serialStr, item in batch {
        ; 稳态路径：窗口已存在，仅发送文本，跳过查表与状态判断。
        ; UpdateContent 内含内容比对与限速，返回 false 表示需重建窗口。
        if (MyHudMap.Has(serialStr)) {
            hud := MyHudMap[serialStr]
            if (IsObject(hud) && hud.UpdateContent(item.content))
                continue
        }

        tableItem := item.tID == "" ? MySoftData.SpecialTableItem : GetTableByID(String(item.tID))
        if (!IsObject(tableItem))
            continue
        itemIndex := GetItemIndexInTable(tableItem, String(item.iID))
        if (itemIndex < 1)
            continue

        ; 宏已停止或终止时不建窗：槽中可能残留最后一帧，会生成游离窗口。
        ; 编辑器测试执行（SpecialTableItem）不经过状态机，单独放行。
        if (tableItem != MySoftData.SpecialTableItem) {
            it := tableItem.Items[itemIndex]
            if (IsObject(it) && it.ColorState != 1 && it.ColorState != 2)
                continue
        }

        HudShow(tableItem, itemIndex, serialStr, item.content)
    }
}

; 每类失败最多记录两次，避免重复日志掩盖其他告警
HudDiagOnce(key) {
    static seen := Map()
    c := seen.Has(key) ? seen[key] : 0
    if (c >= 2)
        return
    seen[key] := c + 1
    try RMTLogSys(RMT_LV_WARN, "HUD", "更新回退: " key)
}

; key 取指令序列码（全局唯一）：一条「输出→悬浮显示」指令对应一个窗口。
; 早期使用「表ID|条目ID」，条目 ID 由 index 反查，index 偏差会造成 key 冲突，
; 使后建的宏复用已有窗口，表现为新宏不显示、原窗口内容被改写。
HudShow(tableItem, itemIndex, serialStr, content) {
    global MyHudMap
    key := String(serialStr)
    if (key == "")
        return
    hud := MyHudMap.Has(key) ? MyHudMap[key] : ""
    if (!IsObject(hud) || !hud.IsOpen()) {
        hud := HudGui(tableItem, itemIndex)
        MyHudMap[key] := hud
    }
    try {
        hud.Show(serialStr, content)
    } catch as err {
        RMTLogSys(RMT_LV_ERROR, "HudShow", Format("悬浮窗显示失败: {1}（行 {2}）", err.Message, err.Line))
    }
}

; 按「表 + 条目」关闭；一个宏可含多条悬浮指令，逐个处理
HudStopItem(tableItem, itemIndex) {
    global MyHudMap
    keys := []
    for key, hud in MyHudMap {
        if (hud.tableItem == tableItem && hud.itemIndex == itemIndex)
            keys.Push(key)
    }
    for key in keys {
        try MyHudMap[key].Close()
        MyHudMap.Delete(key)
    }
}

HudStopAll() {
    global MyHudMap
    for key, hud in MyHudMap {
        try hud.Close()
    }
    MyHudMap := Map()
}
