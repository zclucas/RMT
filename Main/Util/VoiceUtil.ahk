#Requires AutoHotkey v2.0

; =================================================================
; VoiceUtil — 语音触发监听模块（RMT）
;
; 职责：
;   1. 收集所有表中启用了语音触发的宏及其唤醒关键词
;   2. 维护 关键词 -> (tableIndex, itemIndex) 的全局映射
;   3. 通过可替换的底层引擎（默认 sherpa-onnx KWS 封装的 VoiceDll）
;      持续监听麦克风；命中关键词即调用 TriggerMacroHandler 触发对应宏
;   4. 支持运行时动态 新增/删除/修改/启用/禁用 关键词，即时生效（重建引擎实例）
;   5. 生命周期 Start/Stop/Suspend/Resume，与 RMT 休眠/暂停联动
;
; 引擎抽象：底层识别引擎是插件化的。默认使用 sherpa-onnx KeywordSpotter，
; 封装在 Plugins\Voice\VoiceDll.dll（C++，导出 Voice_* 接口）。
; 若 DLL/模型缺失则安全降级（不监听、不报错硬阻止），其余功能不受影响。
; =================================================================

; ---------- 引擎接口约定（供具体引擎实现） ----------
; VoiceEngine 需要实现：
;   Start(keywordList)     启动监听，keywordList 为 { [keyword, tableIndex, itemIndex], ... } 数组
;   Rebuild(keywordList)   运行时按新关键词集重建（停旧建新接流）
;   Stop() / Suspend() / Resume()
;   GetTriggered()         返回最近命中的 keyword（无则空），供轮询取
;   IsReady()              引擎是否可用（DLL/模型存在）
;   EnabledCount()         当前生效的关键词数量

; =================================================================
; 哨兵引擎：引擎 DLL/模型缺失时的安全占位，什么都不做
; =================================================================
class DisabledVoiceEngine {
    IsReady() {
        return false
    }
    EnabledCount() {
        return 0
    }
    Start(args := "") {
        return false
    }
    Rebuild(args := "") {
        return false
    }
    Stop() {
    }
    Suspend() {
    }
    Resume() {
    }
    GetTriggered() {
        return ""
    }
}

; =================================================================
; sherpa-onnx 封装引擎（VoiceDll.dll）
; 通过 AHK DllCall 调用 C++ 导出的 Voice_* 接口。
; 初始化参数：模型路径等从 Plugins\Voice\config 读取，或用默认约定。
; =================================================================
class SherpaVoiceEngine {
    __New() {
        this.hDll := 0
        this.engineLoaded := false      ; 模型是否已在 DLL 内加载（Voice_Init 成功）
        this.running := false           ; 采集/工作线程是否在跑
        this.suspended := false
        this.keywordList := []
        this.InitPaths()
        this._TryLoadDll()
    }

    InitPaths() {
        ; 按 AHK 进程位宽选择运行时目录：64 位 AHK → x64\，32 位 AHK → x86\
        ; （用 A_PtrSize 判断，与 SelfCheck.ahk 一致；A_Is64bit 在某些 AHK 版本会触发
        ;   "local variable never assigned" 警告，且失败时静默回落 x86 导致 DLL 加载错位）
        arch := (A_PtrSize == 8) ? "x64" : "x86"
        this.RunDir := A_WorkingDir "\Plugins\Voice\" arch
        this.DllPath := this.RunDir "\VoiceDll.dll"
        this.ModelDir := A_WorkingDir "\Plugins\Voice\models\kws"
    }

    ; 尝试加载 VoiceDll。失败则进入禁用态。
    ; 先按完整路径预加载其依赖 DLL（sherpa-onnx-c-api / onnxruntime 与 VoiceDll 同目录），
    ; 把 x64\x86 目录提前纳入依赖搜索路径，避免 VoiceDll 加载时找不到依赖。
    _TryLoadDll() {
        if (!FileExist(this.DllPath))
            return false
        pluginDir := this.RunDir
        ; 依次加载依赖（顺序无关，重在把插件目录挂进搜索路径）
        for dep in ["onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-c-api.dll"] {
            dp := pluginDir "\" dep
            if (FileExist(dp)) {
                try
                    DllCall("LoadLibrary", "Str", dp, "Ptr")
            }
        }
        try {
            this.hDll := DllCall("LoadLibrary", "Str", this.DllPath, "Ptr")
            if (this.hDll != 0)
                return true
        } catch as e {
            this.lastError := "DLL加载失败: " (e.HasProp("Message") ? e.Message : "")
        }
        this.hDll := 0
        return false
    }

    IsReady() {
        return (this.hDll != 0)
        && FileExist(this.ModelDir "\decoder*.onnx")
        && FileExist(this.ModelDir "\encoder*.onnx")
        && FileExist(this.ModelDir "\joiner*.onnx")
        && FileExist(this.ModelDir "\tokens.txt")
    }

    ; 组装 keyword 集为 “|” 分隔的汉字串传 DLL
    _KeywordsToStr() {
        s := ""
        for i, entry in this.keywordList {
            if (i > 1)
                s .= "|"
            s .= entry[1]
        }
        return s
    }

    ; ---------- 生命周期 ----------
    Start(keywordList := "") {
        if (IsSet(keywordList) && keywordList != "")
            this.keywordList := keywordList
        if (!this.IsReady() || this.keywordList.Length == 0)
            return false
        ; 模型未加载或上次被 Close 过 -> 重新 Voice_Init
        if (!this.engineLoaded) {
            if (!this._CallInit())
                return false
        }
        ; 用最新关键词重建 KWS 流
        if (!this._CallKeywords())
            return false
        this.suspended := false
        ; 启动麦克风采集 + 工作线程
        if (!this.running) {
            if (!this._CallStart())
                return false
            this.running := true
        }
        return true
    }

    Rebuild(keywordList := "") {
        if (IsSet(keywordList) && keywordList != "")
            this.keywordList := keywordList
        if (this.keywordList.Length == 0) {
            this.Stop()
            return false
        }
        if (!this.IsReady())
            return false
        ; 保持采集运行，仅重建关键词流
        if (!this.engineLoaded) {
            if (!this._CallInit())
                return false
        }
        if (!this._CallKeywords())
            return false
        if (!this.running) {
            if (!this._CallStart())
                return false
            this.running := true
        }
        this.suspended := false
        return true
    }

    Stop() {
        ; 只停采集/工作线程，保留模型与关键词流（下次 Start 快速重启）
        if (this.hDll != 0 && this.running)
            this._CallStop()
        this.running := false
    }

    Suspend() {
        ; DLL 无独立 Pause：用 Stop 暂停采集（保留模型），Resume 时恢复
        if (this.running && !this.suspended && this.hDll != 0) {
            this._CallStop()
            this.running := false
        }
        this.suspended := true
    }

    Resume() {
        if (this.suspended && this.engineLoaded && this.keywordList.Length > 0) {
            if (!this.running) {
                this._CallStart()
                this.running := true
            }
            this.suspended := false
        }
    }

    GetTriggered() {
        ; Voice_GetTriggered 内部 Pop 即消费，无需单独 ConsumeTriggered
        if (!this.running || this.suspended || this.hDll == 0)
            return ""
        buf := Buffer(256)
        DllCall(this.DllPath "\Voice_GetTriggered", "Ptr", buf, "Int", 256, "Int")
        return StrGet(buf, 256, "UTF-8")
    }

    EnabledCount() {
        return this.keywordList.Length
    }

    ; ---------- DLL 内部调用 ----------
    _CallInit() {
        m := this._FindKwsModels()
        if (m == "")
            return false
        if (this.hDll == 0)
            return false
        r := DllCall(this.DllPath "\Voice_Init",
            "WStr", m.encoder, "WStr", m.decoder,
            "WStr", m.joiner, "WStr", m.tokens, "Int")
        if (r) {
            this.engineLoaded := true
            this.lastError := ""
        } else {
            this.engineLoaded := false
            this.lastError := this._GetLastError()
        }
        return r != 0
    }

    _CallKeywords() {
        if (this.hDll == 0 || !this.engineLoaded)
            return false
        ; 传纯汉字，DLL 内置 G2P 转拼音音素
        r := DllCall(this.DllPath "\Voice_SetKeywordsZh", "WStr", this._KeywordsToStr(), "Int")
        if (!r)
            this.lastError := this._GetLastError()
        return r != 0
    }

    _CallStart() {
        return DllCall(this.DllPath "\Voice_Start", "Int") != 0
    }

    _CallStop() {
        DllCall(this.DllPath "\Voice_Stop", "Int")
    }

    _GetLastError() {
        if (this.hDll == 0)
            return ""
        buf := Buffer(512)
        DllCall(this.DllPath "\Voice_GetLastError", "Ptr", buf, "Int", 512, "Int")
        return StrGet(buf, 512, "UTF-8")
    }

    ; 解析模型目录，返回 { encoder, decoder, joiner, tokens }；缺失返回 ""
    _FindKwsModels() {
        enc := this._FindFirst(this.ModelDir "\encoder*.onnx")
        dec := this._FindFirst(this.ModelDir "\decoder*.onnx")
        joi := this._FindFirst(this.ModelDir "\joiner*.onnx")
        tok := this._FindFirst(this.ModelDir "\tokens.txt")
        if (enc == "" || dec == "" || joi == "" || tok == "")
            return ""
        ; 优先 int8 encoder/joiner（体积小、官方推荐），否则用原尺寸
        encInt8 := this._FindFirst(this.ModelDir "\encoder*.int8.onnx")
        joiInt8 := this._FindFirst(this.ModelDir "\joiner*.int8.onnx")
        if (encInt8 != "") enc := encInt8
        if (joiInt8 != "") joi := joiInt8
        return { encoder: enc, decoder: dec, joiner: joi, tokens: tok }
    }

    ; 返回目录下第一个匹配 glob 的完整路径；无则 ""
    _FindFirst(p) {
        loop files, p {
            return A_LoopFileFullPath
        }
        return ""
    }
}

; =================================================================
; VoiceEngineMgr — 全局管理器（对外主入口）
; =================================================================
class VoiceEngineMgr {
    __New() {
        global MyHotReloadBus
        this.engine := ""          ; 当前对接的引擎实例
        this.timerFunc := ObjBindMethod(this, "OnPoll")
        this.running := false      ; 是否开启监听（受启用的关键词数控制）
        this.suspended := false
        this.keywordMap := Map()   ; keyword -> "tableIndex|itemIndex"
        this.enabledItems := []    ; [ [tableIndex,itemIndex], ... ]
        this._InitEngine()
        ; 注册热重载订阅：任意 item 表行配置变更 → 空闲时重建关键词集
        if (IsSet(MyHotReloadBus) && IsObject(MyHotReloadBus))
            MyHotReloadBus.Subscribe(ObjBindMethod(this, "NotifyConfigChanged"), (t) => CheckIsItemTable(t))
    }

    _InitEngine() {
        ; 优先用 sherpa 引擎；若不可用用哨兵（安全降级）
        s := SherpaVoiceEngine()
        if (s.IsReady())
            this.engine := s
        else
            this.engine := DisabledVoiceEngine()
    }

    IsSupported() {
        return this.engine.IsReady()
    }

    ; ---------- 关键词集收集（从所有表扫描） ----------
    RebuildKeywords() {
        global MySoftData
        this.keywordMap := Map()
        this.enabledItems := []
        scanList := []
        for t in MySoftData.TableInfo {
            if (!CheckIsItemTable(GetTableIndexByID(t.ID)))
                continue
            ; 启用/禁用由主界面「禁用」（Forbid）控制：禁用则跳过；关键词非空即可作为唤醒词
            for i, item in t.Items {
                if (item.Forbid)
                    continue
                kwStr := item.VoiceKeywords
                if (kwStr == "")
                    continue
                for kw in StrSplit(kwStr, ",") {
                    kw := Trim(kw)
                    if (kw == "")
                        continue
                    if (this.keywordMap.Has(kw)) {
                        ; 避免同关键词重复；仅保留第一处
                        continue
                    }
                    this.keywordMap[kw] := t.ID "|" item.ID
                    scanList.Push([kw, t.ID, item.ID])
                }
            }
        }
        if (this.running) {
            if (scanList.Length == 0) {
                this.engine.Stop()
                this.running := false
            } else {
                this.engine.Rebuild(scanList)
            }
        }
        return scanList.Length
    }

    ; 启动监听（在 RMT 入口调用一次）
    Start() {
        if (this.running)
            return
        n := this.RebuildKeywords()
        if (n == 0 || !this.engine.IsReady())
            return
        this.engine.Start(this._ScanToEngineList())
        this.running := true
        SetTimer(this.timerFunc, 150)   ; 轮询识别结果
    }

    ; 停止监听（软件退出时）
    Stop() {
        SetTimer(this.timerFunc, 0)
        this.engine.Stop()
        this.running := false
    }

    ; 与 RMT 休眠联动
    Suspend() {
        if (!this.running || this.suspended)
            return
        this.engine.Suspend()
        this.suspended := true
    }

    Resume() {
        if (!this.running || !this.suspended)
            return
        this.engine.Resume()
        this.suspended := false
    }

    ; 供 VoiceGui 在编辑后调用：立即重建关键词集
    NotifyConfigChanged(tableIndex, itemIndex) {
        ; 若该宏本次启用了语音，则确保在监听；否则若有变化就重建
        n := this.RebuildKeywords()
        if (!this.running) {
            n := this.keywordMap.Count
            if (n > 0 && this.engine.IsReady()) {
                this.engine.Start(this._ScanToEngineList())
                this.running := true
                SetTimer(this.timerFunc, 150)
            }
        }
    }

    _ScanToEngineList() {
        ; 引擎（Start/Rebuild）只消费 entry[1]（关键词）；p1/p2 为表 ID / 条目 ID 字符串，透传不使用。
        ; 注意：表身份已固定为 Symbol（如 "Voice"，不再是数字 t_xxx），不能对 p[1]/p[2] 做 Integer()。
        list := []
        for kw, loc in this.keywordMap {
            p := StrSplit(loc, "|")
            list.Push([kw, p[1], p[2]])
        }
        return list
    }

    ; 定时轮询：取最近命中关键词 → 查找映射 → 触发宏
    OnPoll() {
        global MySoftData
        if (!this.running || this.suspended)
            return
        kw := this.engine.GetTriggered()
        if (kw == "")
            return
        if (!this.keywordMap.Has(kw))
            return
        loc := this.keywordMap[kw]
        p := StrSplit(loc, "|")
        if (p.Length != 2)
            return
        tableID := p[1], itemID := p[2]
        ; 触发时做合法性复查：宏存在、未禁用（主界面禁用开关）
        tableItem := GetTableByID(tableID)
        item := GetItemGlobal(itemID)
        if (!tableItem || !item)
            return
        if (item.Forbid)
            return
        if (item.VoiceKeywords == "")
            return
        ; TriggerMacroHandler 内部用表对象定位（tableItem.Index 仅作 UI 槽位），身份=ID
        TriggerMacroHandler(GetItemTableGlobal(itemID), item)
    }
}

; ---------- 全局单例 ----------
global MyVoiceEngine := ""
InitVoiceEngine() {
    global MyVoiceEngine
    if (!IsSet(MyVoiceEngine) || !IsObject(MyVoiceEngine))
        MyVoiceEngine := VoiceEngineMgr()
    return MyVoiceEngine
}

; 工具函数：获取某宏的语音触发配置（供 GUI/其它模块读取）
GetItemVoiceKeywords(tableItem, index) {
    item := tableItem.Items[index]
    if (!item)
        return { Enable: 0, Keywords: "" }
    return { Enable: item.VoiceKeywords == "" ? 0 : 1, Keywords: item.VoiceKeywords }
}