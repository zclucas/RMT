#Requires AutoHotkey v2.0

; =================================================================
; HotReloadBus — 配置热重载变更总线（RMT 主进程专用）
;
; 解决「编辑器改了配置 → 运行时消费端立即重建」的统一模式：
;   VoiceGui / UI宏 / 菜单宏 等编辑器在「确定」后只广播
;   Publish(tableIndex, itemIndex)，不再直接调用某个消费端
;   （避免各写各的 NotifyXXXChanged / RefreshXXX，后续新增同类组件
;    只需写一个订阅者接入总线，编辑器侧零改动）。
;
; 运行时消费端（VoiceEngine / UIMacroGui / 菜单构建…）通过
;   Subscribe(handler, filter) 注册自己的刷新回调，总线在空闲时统一派发。
;
; 关键设计：
;   1. 统一事件：Publish(tableIndex, itemIndex) — 调用方负责先更新内存模型，
;      总线只负责派发「已变更」信号，不读模型、不管保存。
;   2. 订阅者：Subscribe(handler, filter)，handler(tableIndex, itemIndex)；
;      filter(tableIndex) 谓词决定是否关心该表，省略则全收。
;   3. 合并去抖：同一空闲批次内对同一 (表,行) 的多次 Publish 合并为一次派发，
;      批量编辑不反复重建。
;   4. 空闲调度：SetTimer(-1) 延后到主线程空闲时统一派发，
;      编辑器「确定」路径只做微秒级入队，不触发同步重建，UI 不卡。
;   5. 与落盘解耦：落盘仍走主界面「应用并保存」(OnSaveSetting)，总线不管保存。
; =================================================================

class HotReloadBus {
    __New() {
        this.subscribers := []          ; [ { Filter: Func|"", Handler: Func }, ... ]
        this.pending := Map()           ; tableIndex -> Map(itemIndex -> true)；itemIndex 0 表示整表
        this._scheduled := false        ; 是否已有空闲派发任务在排队
    }

    ; Subscribe(handler, filter := "")
    ;   handler(tableIndex, itemIndex) — 消费端刷新回调
    ;   filter(tableIndex)             — 可选谓词：返回 true 才派发（按表过滤）
    Subscribe(handler, filter := "") {
        this.subscribers.Push({ Filter: filter, Handler: handler })
    }

    ; Publish(tableIndex, itemIndex := 0)
    ; 广播「某表某行配置已变更」。itemIndex 省略/0 = 整表变更。
    ; 内存模型须已由调用方更新；此调用只入队，返回极快。
    Publish(tableIndex, itemIndex := 0) {
        if (!this.pending.Has(tableIndex))
            this.pending[tableIndex] := Map()
        this.pending[tableIndex][itemIndex] := true
        if (!this._scheduled) {
            this._scheduled := true
            SetTimer((*) => this._Flush(), -1)
        }
    }

    ; 空闲时统一派发：合并本批次内所有待处理变更，逐个订阅者分发。
    _Flush() {
        this._scheduled := false
        pending := this.pending
        this.pending := Map()
        for tableIndex, items in pending {
            for sub in this.subscribers {
                ; 注意：sub.Filter/sub.Handler 是普通可调用对象存为属性，
                ; 必须用 .Call() 显式调用——用 obj.prop(args) 方法语法会额外传入 this 实参，
                ; 导致 "Too many parameters passed to function"。
                if (IsObject(sub.Filter) && !sub.Filter.Call(tableIndex))
                    continue
                for itemIndex in items {
                    try
                        sub.Handler.Call(tableIndex, itemIndex)
                    catch as e {
                        ; 单个订阅者异常不影响其余订阅者
                        try
                            RMTLogSys("Error", "HotReloadBus", "派发异常: " (e.HasProp("Message") ? e.Message : ""))
                    }
                }
            }
        }
    }
}
