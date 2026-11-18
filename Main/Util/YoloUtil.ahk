#Requires AutoHotkey v2.0

; ============================================================
; YOLO 检测指令：数据类、全局模型库、DLL 门面
;
; 分层与语音那套一致：
;   - 推理内核在 Plugins/YOLO/dll（Rust + ONNX Runtime），只认 src/RMT_Yolo.h 的合同，
;     不知道宿主怎么用结果。
;   - 本文件是 AHK 侧唯一入口：截图、调 DLL、解析结果、写变量、按需点击。
;   - Gui/YoloGui.ahk 只负责改 YoloData，不碰 DLL。
;
; 任务（检测/分割/姿态/旋转框/分类/语义/深度）由模型元数据决定，指令里不选任务，
; 但**参数和输出跟着任务走**：分类没有框和点击，深度没有目标数量，
; 姿态要多一个关键点阈值和锚点。每项任务只写自己那几个字段。
; ============================================================

class YoloData {
    SerialStr := ""
    ModelName := ""        ; 全局模型库中的模型名
    Device := "CPU"
    Region := ""           ; 屏幕区域 x1,y1,x2,y2，空=主屏全屏

    ; --- detect / segment / pose / obb
    ConfLevel := "0.25"    ; 置信度阈值 0~1
    Iou := "0.45"          ; NMS 的 IoU 阈值（加载期参数）
    MaxDet := "300"        ; 最多保留多少个目标
    Classes := ""          ; 类别过滤：名称或序号，逗号分隔，空=全部
    TargetMode := "最高置信度"
    ActionType := "无动作"
    OffsetX := "0"
    OffsetY := "0"

    ; --- pose
    KeypointConf := "0.5"  ; 关键点可信阈值
    AnchorKpt := "-1"      ; 点击锚点用第几个关键点，-1=框中心

    ; --- segment / semantic
    MinMaskRatio := "0"    ; 实例分割：掩膜面积占比下限 0~1
    MinRatio := "0.005"    ; 语义分割：类别覆盖率下限 0~1

    ; --- classify
    TopK := "5"

    ; --- depth
    SampleX := ""          ; 采样点屏幕坐标，留空=用区域平均距离
    SampleY := ""

    ; --- 输出（按任务取用）
    CountVar := ""         ; detect/segment/pose/obb：命中数量
    ClassVar := ""         ; classify/semantic：类别名
    ConfVar := ""          ; classify：置信度
    RatioVar := ""         ; semantic：覆盖率
    DepthVar := ""         ; depth：距离
    ResultVar := ""        ; 完整结果 JSON
    ErrorVar := ""         ; 失败原因
}

; 全局模型库：所有配置共用一份，避免每条指令重复填路径。
class YoloModelStore {
    static Section := "Models"
    static TaskSection := "Tasks"

    static File() {
        return ProjectRootDir "\Setting\YoloModels.toml"
    }

    static List() {
        names := []
        file := this.File()
        if !FileExist(file)
            return names
        root := Cfg_Load(file)
        if (!root.Has(this.Section))
            return names
        for name, _ in root[this.Section]
            names.Push(name)
        names := this._Sort(names)
        return names
    }

    static Get(name) {
        return CfgRead(this.File(), this.Section, name, "")
    }

    static Set(name, path) {
        CfgWrite(path, this.File(), this.Section, name)
    }

    static Delete(name) {
        CfgDelete(this.File(), this.Section, name)
    }

    ; 任务名缓存：编辑器要靠它决定显示哪些参数，不能每次都去加载模型。
    static GetTask(name) {
        return CfgRead(this.File(), this.TaskSection, name, "")
    }

    static SetTask(name, task) {
        CfgWrite(task, this.File(), this.TaskSection, name)
    }

    ; 模型库里登记的是绝对路径或相对程序根目录的路径，这里统一成绝对路径。
    static ResolvePath(name) {
        path := Trim(this.Get(name))
        if (path == "")
            return ""
        if !RegExMatch(path, "^(?:[A-Za-z]:[\\/]|\\\\)")
            path := ProjectRootDir "\" path
        return path
    }

    static _Sort(names) {
        ; AHK 没有内置排序；模型数量很少，插入排序足够。
        loop names.Length - 1 {
            i := A_Index
            while (i >= 1 && StrCompare(names[i], names[i + 1], false) > 0) {
                tmp := names[i]
                names[i] := names[i + 1]
                names[i + 1] := tmp
                i--
            }
        }
        return names
    }
}

class Yolo {
    static ApiVersion := 2
    ; 内核实际编入的执行后端。当前发布的内核是 CPU 版，只有 CPU 可用；
    ; 其它设备要在编译内核时带上对应 EP（CUDA / DirectML / TensorRT / CoreML），
    ; 否则加载直接返回 -2。旧配置里存了别的设备名，执行时会被归到 CPU。
    static Devices := ["CPU"]
    static Actions := ["无动作", "左键单击", "左键双击", "右键单击"]
    static Targets := ["最高置信度", "最左", "最上", "面积最大"]

    ; 任务码 → 界面名。任务码来自内核 Info 的 task 字段。
    static Tasks := Map(
        "detect", "目标检测",
        "segment", "实例分割",
        "pose", "姿态估计",
        "obb", "旋转框",
        "classify", "图像分类",
        "semantic", "语义分割",
        "depth", "深度估计")

    ; 与 DLL 无关的字段：旧配置反序列化后缺字段，用它补齐默认值。
    static Fields := ["ModelName", "Device", "Region", "ConfLevel", "Iou", "MaxDet", "Classes",
        "TargetMode", "ActionType", "OffsetX", "OffsetY", "KeypointConf", "AnchorKpt",
        "MinMaskRatio", "MinRatio", "TopK", "SampleX", "SampleY",
        "CountVar", "ClassVar", "ConfVar", "RatioVar", "DepthVar", "ResultVar", "ErrorVar"]

    static _handles := Map()   ; "路径|设备|iou" → 内核句柄
    static _infos := Map()     ; "路径|设备" → 模型信息对象
    static _ready := false
    static _dllError := ""     ; 加载失败原因（会话内只诊断一次）

    ; ---------- DLL 加载 ----------

    ; 内核目录与必需文件。文件校验（SelfCheck）与编辑器共用这一份清单，
    ; 免得三处各写一份、换架构或换运行库时漏改。
    static Dir() {
        return ProjectRootDir "\Plugins\YOLO\" (A_PtrSize = 4 ? "x86" : "x64")
    }

    ; 内核用 load-dynamic 找 onnxruntime.dll，两者必须同目录成套存在。
    static Files := ["RMT_YOLO.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll"]

    ; 返回缺失文件的完整路径。只做文件系统判断，不碰界面（Worker 也 include 本文件）。
    static MissingFiles() {
        dir := this.Dir()
        missing := []
        for name in this.Files {
            path := dir "\" name
            attrs := FileExist(path)
            usable := false
            if (attrs && !InStr(attrs, "D")) {
                try usable := FileGetSize(path) > 0
            }
            if (!usable)
                missing.Push(path)
        }
        return missing
    }

    ; 补齐文件后清掉一次性诊断，让下一次调用重新加载。
    static ResetDll() {
        this._dllError := ""
        this._ready := false
    }

    ; 返回 "" 表示可用，否则返回失败原因。
    static EnsureDll() {
        if (this._ready)
            return ""
        if (this._dllError != "")
            return this._dllError
        if (DllCall("GetModuleHandle", "Str", "RMT_YOLO.dll", "Ptr")) {
            this._ready := true
            return ""
        }

        ; 缺文件时一次报全，用户才知道要补几个，而不是补一个又撞下一个。
        missing := this.MissingFiles()
        if (missing.Length) {
            list := ""
            for path in missing
                list .= (list == "" ? "" : "、") path
            this._dllError := Format(GetLang("YOLO 插件文件缺失：{}"), list)
            return this._dllError
        }
        dir := this.Dir()
        main := dir "\RMT_YOLO.dll"

        ; 按目录解析依赖（onnxruntime 等），不改善进程全局搜索路径。
        ; 先加载依赖，失败时能区分“缺依赖”与“缺主库”。
        Loop Files, dir "\*.dll" {
            if (A_LoopFileName = "RMT_YOLO.dll")
                continue
            DllCall("LoadLibraryEx", "Str", A_LoopFileFullPath, "Ptr", 0, "UInt", 8, "Ptr")
        }
        if (!DllCall("LoadLibraryEx", "Str", main, "Ptr", 0, "UInt", 8, "Ptr")) {
            this._dllError := Format(GetLang("RMT_YOLO.dll 加载失败（错误码 {}），请确认运行库与其同目录"), A_LastError)
            return this._dllError
        }

        version := DllCall("RMT_YOLO.dll\RMT_Yolo_ApiVersion", "Cdecl Int")
        if (version != this.ApiVersion) {
            this._dllError := Format(GetLang("YOLO 内核版本不匹配（期望 {}，实际 {}），请重新安装插件"), this.ApiVersion, version)
            return this._dllError
        }
        this._ready := true
        return ""
    }

    static IsAvailable() {
        return this.EnsureDll() == ""
    }

    ; ---------- 句柄与模型信息 ----------

    ; iou 是 NMS 参数、加载后就固定了，所以纳入缓存键：改阈值会换一个句柄。
    static Acquire(path, device, iou := 0.45) {
        reason := this.EnsureDll()
        if (reason != "")
            throw Error(reason)

        key := path "|" device "|" iou
        if (this._handles.Has(key))
            return this._handles[key]

        deviceId := this._DeviceIndex(device)
        handle := 0
        rc := DllCall("RMT_YOLO.dll\RMT_Yolo_Create", "WStr", path, "Int", deviceId,
            "Float", iou, "Ptr*", &handle, "Cdecl Int")
        if (rc != 0 || !handle)
            throw Error(Format(GetLang("模型加载失败（{}）：{}"), rc, path))

        this._handles[key] := handle
        return handle
    }

    static Info(path, device, iou := 0.45) {
        key := path "|" device
        if (this._infos.Has(key))
            return this._infos[key]

        info := this._ReadInfo(this.Acquire(path, device, iou))
        this._infos[key] := info
        return info
    }

    ; 读元数据。句柄由调用方负责生命周期。
    static _ReadInfo(handle) {
        size := DllCall("RMT_YOLO.dll\RMT_Yolo_Info", "Ptr", handle, "Ptr", 0, "Int", 0, "Cdecl Int")
        if (size <= 0)
            throw Error(GetLang("读取模型信息失败。"))
        buf := Buffer(size + 1, 0)
        if (DllCall("RMT_YOLO.dll\RMT_Yolo_Info", "Ptr", handle, "Ptr", buf, "Int", buf.Size, "Cdecl Int") < 0)
            throw Error(GetLang("读取模型信息失败。"))
        return JSON.parse(StrGet(buf, "UTF-8"), , false)
    }

    ; 释放全部句柄。模型常驻内存，程序退出或切换配置时调用。
    static ReleaseAll() {
        if (!DllCall("GetModuleHandle", "Str", "RMT_YOLO.dll", "Ptr"))
            return
        for _, handle in this._handles
            DllCall("RMT_YOLO.dll\RMT_Yolo_Destroy", "Ptr", handle, "Cdecl")
        this._handles := Map()
        this._infos := Map()
    }

    ; ---------- 任务探测 ----------

    ; 模型对应的任务码；读不到返回 ""。
    ; 先查模型库里的缓存，避免每次打开编辑器都加载一遍模型。
    static TaskOf(modelName) {
        modelName := Trim(String(modelName))
        if (modelName == "")
            return ""
        cached := YoloModelStore.GetTask(modelName)
        if (cached != "")
            return cached
        path := YoloModelStore.ResolvePath(modelName)
        if (path == "")
            return ""
        task := this.ProbeTask(path)
        if (task != "")
            YoloModelStore.SetTask(modelName, task)
        return task
    }

    ; 真正去加载模型读元数据。贵，只在登记模型或首次执行时调用。
    ; 用一个临时句柄读，读完立刻释放：探测用的设备/阈值未必是执行时的那套，
    ; 留在缓存里只会白占一份模型内存。
    static ProbeTask(path) {
        if (!FileExist(path) || !this.IsAvailable())
            return ""
        handle := 0
        rc := DllCall("RMT_YOLO.dll\RMT_Yolo_Create", "WStr", path, "Int", 0,
            "Float", 0.45, "Ptr*", &handle, "Cdecl Int")
        if (rc != 0 || !handle)
            return ""
        try {
            info := this._ReadInfo(handle)
        } catch {
            return ""
        } finally {
            DllCall("RMT_YOLO.dll\RMT_Yolo_Destroy", "Ptr", handle, "Cdecl")
        }
        return this._Prop(info, "task", "")
    }

    ; ---------- 执行 ----------

    static Execute(data, resolve, cancelled) {
        reason := this.EnsureDll()
        if (reason != "")
            throw Error(reason)

        data := this.Normalize(data)
        modelName := Trim(resolve(data.ModelName))
        if (modelName == "")
            throw Error(GetLang("请先在模型库里选择模型。"))
        path := YoloModelStore.ResolvePath(modelName)
        if (path == "")
            throw Error(Format(GetLang("模型「{}」不在模型库中，请重新选择。"), modelName))
        if !FileExist(path)
            throw Error(Format(GetLang("模型文件不存在：{}"), path))

        device := CmdEnumZh(data.Device, this.Devices)
        iou := this.ParseIou(resolve(data.Iou))
        info := this.Info(path, device, iou)
        task := this._Prop(info, "task", "")
        if (task == "")
            task := "detect"

        region := this.ParseRegion(resolve(data.Region))
        opts := this.BuildOptions(task, data, resolve, region)
        handle := this.Acquire(path, device, iou)

        if (cancelled())
            return ""

        raw := this.RunFrame(handle, region, opts)
        if (cancelled())
            return ""

        return this.BuildOutcome(task, raw, data, resolve, region, opts)
    }

    ; 截屏 → 推理 → 解析。输入区域是屏幕坐标，内核拿到的是区域内的图。
    static RunFrame(handle, region, opts) {
        x := region[1], y := region[2]
        width := region[3] - region[1], height := region[4] - region[2]
        if (width <= 0 || height <= 0)
            throw Error(GetLang("检测区域无效。"))

        pBitmap := Gdip_BitmapFromScreen(Format("{}|{}|{}|{}", x, y, width, height))
        if (!pBitmap)
            throw Error(GetLang("屏幕截图失败。"))

        stride := 0, scan0 := 0, bitmapData := 0
        locked := false
        try {
            if (Gdip_LockBits(pBitmap, 0, 0, width, height, &stride, &scan0, &bitmapData) != 0)
                throw Error(GetLang("读取截图数据失败。"))
            locked := true

            ; 布局见 RMT_Yolo.h：10 个 4 字节字段，共 40。
            options := Buffer(40, 0)
            NumPut("Int", 40, options, 0)              ; structSize
            NumPut("Float", opts.conf, options, 4)
            NumPut("Int", opts.maxDet, options, 8)
            NumPut("Int", opts.topK, options, 12)
            NumPut("Float", opts.keypointConf, options, 16)
            NumPut("Float", opts.minMaskRatio, options, 20)
            NumPut("Int", opts.anchorKpt, options, 24)
            NumPut("Int", opts.sampleX, options, 28)
            NumPut("Int", opts.sampleY, options, 32)
            NumPut("Int", 0, options, 36)

            ; 300 个目标的 JSON 约 60KB，1MB 足够；真不够时按返回值扩容重试一次。
            capacity := 1 << 20
            loop 2 {
                buf := Buffer(capacity, 0)
                rc := DllCall("RMT_YOLO.dll\RMT_Yolo_Run", "Ptr", handle, "Ptr", scan0,
                    "Int", width, "Int", height, "Int", stride, "Ptr", options,
                    "Ptr", buf, "Int", buf.Size, "Cdecl Int")
                if (rc >= 0)
                    return JSON.parse(StrGet(buf, "UTF-8"), , false)
                if (rc != -4)
                    throw Error(Format(GetLang("YOLO 推理失败（{}）"), rc))
                capacity *= 8
            }
            throw Error(GetLang("YOLO 推理结果过大。"))
        } finally {
            if (locked)
                Gdip_UnlockBits(pBitmap, &bitmapData)
            Gdip_DisposeImage(pBitmap)
        }
    }

    ; ---------- 参数 ----------

    ; 只填当前任务用得上的那几项，其余留 0 / -1 让内核取默认值。
    static BuildOptions(task, data, resolve, region) {
        opts := {conf: 0.25, maxDet: 300, topK: 5, keypointConf: 0.5,
            minMaskRatio: 0.0, anchorKpt: -1, sampleX: -1, sampleY: -1}

        if (task == "depth") {
            point := this.ParsePoint(resolve(data.SampleX), resolve(data.SampleY), region)
            if (point[1] >= 0) {
                opts.sampleX := point[1]
                opts.sampleY := point[2]
            }
            return opts
        }

        opts.conf := this.ParseConf(resolve(data.ConfLevel))

        if (task == "classify") {
            opts.topK := this.ParseInt(resolve(data.TopK), 5, 1, 20,
                GetLang("Top-K 须为 1~20 的整数。"))
            return opts
        }

        opts.maxDet := this.ParseInt(resolve(data.MaxDet), 300, 1, 1000,
            GetLang("最大目标数须为 1~1000 的整数。"))

        if (task == "pose") {
            opts.keypointConf := this.ParseRatio(resolve(data.KeypointConf),
                GetLang("关键点阈值须为 0~1 之间的数字。"))
            opts.anchorKpt := this.ParseInt(resolve(data.AnchorKpt), -1, -1, 100,
                GetLang("点击锚点须为不小于 -1 的整数。"))
        } else if (task == "segment") {
            opts.minMaskRatio := this.ParseRatio(resolve(data.MinMaskRatio),
                GetLang("比例须为 0~1 之间的数字。"))
        } else if (task == "semantic") {
            opts.minMaskRatio := this.ParseRatio(resolve(data.MinRatio),
                GetLang("比例须为 0~1 之间的数字。"))
        }
        return opts
    }

    ; ---------- 结果 ----------

    ; 把内核的原始 JSON 变成“该任务要写的那几个变量”。
    static BuildOutcome(task, raw, data, resolve, region, opts) {
        out := {count: "", name: "", conf: "", ratio: "", depth: "", result: ""}

        switch task {
            case "classify":
                list := this._Prop(raw, "probs", [])
                if (IsObject(list) && list.Length) {
                    out.name := this._Prop(list[1], "name", "")
                    out.conf := this.ToText(this._Prop(list[1], "conf", ""))
                }
                out.result := JSON.stringify(raw, 0)
            case "depth":
                depth := this._Prop(raw, "depth", "")
                if (!IsObject(depth))
                    throw Error(GetLang("深度模型没有返回距离数据。"))
                if (opts.sampleX >= 0) {
                    value := this._Prop(depth, "point", "")
                    if (value == "")
                        throw Error(GetLang("采样点超出检测区域，或该点没有有效深度。"))
                    out.depth := this.ToText(value)
                } else {
                    out.depth := this.ToText(this._Prop(depth, "mean", ""))
                }
                out.result := JSON.stringify(raw, 0)
            case "semantic":
                items := this.PrepareItems(raw, data, resolve, region, true)
                if (items.Length) {
                    out.name := this._Prop(items[1], "name", "")
                    out.ratio := this.ToText(this._Prop(items[1], "ratio", ""))
                    if (CmdEnumZh(data.ActionType, this.Actions) != "无动作")
                        this.ClickTarget(items[1], data, resolve)
                }
                out.result := JSON.stringify(raw, 0)
            default:
                items := this.PrepareItems(raw, data, resolve, region, false)
                out.count := items.Length
                out.result := JSON.stringify(raw, 0)
                if (items.Length && CmdEnumZh(data.ActionType, this.Actions) != "无动作")
                    this.ClickTarget(items[1], data, resolve)
        }
        return out
    }

    ; JSON 里的双精度直接转字符串会变成 0.67720000000000002，写进变量很难看。
    static ToText(value) {
        if (!IsNumber(value))
            return String(value)
        return String(Round(value, 4))
    }

    ; 类别过滤 + 排序 + 坐标换算。byRatio 为真时按覆盖率排（语义分割没有置信度）。
    static PrepareItems(raw, data, resolve, region, byRatio) {
        source := this._Prop(raw, "items", [])
        if (!IsObject(source))
            return []
        items := []

        rules := this.ParseClasses(resolve(data.Classes))
        for item in source {
            if (rules.Length && !this.MatchClass(item, rules))
                continue
            items.Push(item)
        }

        if (byRatio) {
            items := this._SortBy(items, "ratio", true)
        } else {
            switch CmdEnumZh(data.TargetMode, this.Targets) {
                case "最左": items := this._SortBy(items, "cx", false)
                case "最上": items := this._SortBy(items, "cy", false)
                case "面积最大": items := this._SortBy(items, "_area", true)
                default: items := this._SortBy(items, "conf", true)
            }
        }

        ; 内核给的是截图区域内坐标，补上区域左上角才是屏幕坐标（点击和变量都用这个）。
        this.ShiftItems(items, region[1], region[2])
        raw.items := items
        raw.count := items.Length
        return items
    }

    static ParseClasses(text) {
        rules := []
        text := Trim(text)
        if (text == "")
            return rules
        for part in StrSplit(text, [",", "，"]) {
            part := Trim(part)
            if (part != "")
                rules.Push(part)
        }
        return rules
    }

    static MatchClass(item, rules) {
        name := this._Prop(item, "name", "")
        cls := this._Prop(item, "cls", "")
        for rule in rules {
            if (rule = String(name) || rule = String(cls))
                return true
        }
        return false
    }

    ; 把截图区域内的坐标换算成屏幕坐标：点击、结果变量都按屏幕坐标用。
    static ShiftItems(items, dx, dy) {
        if (!IsObject(items) || (dx == 0 && dy == 0))
            return
        for item in items {
            if (!IsObject(item))
                continue
            box := this._Prop(item, "box", "")
            if (IsObject(box) && box.Length >= 4) {
                box[1] += dx
                box[2] += dy
                box[3] += dx
                box[4] += dy
            }
            for pair in [["cx", dx], ["cy", dy]] {
                if (item.HasProp(pair[1]) && IsNumber(item.%pair[1]%))
                    item.%pair[1]% := item.%pair[1]% + pair[2]
            }
            anchor := this._Prop(item, "anchor", "")
            if (IsObject(anchor) && anchor.Length >= 2) {
                anchor[1] += dx
                anchor[2] += dy
            }
            keypoints := this._Prop(item, "keypoints", "")
            if (IsObject(keypoints)) {
                for point in keypoints {
                    if (IsObject(point) && point.Length >= 2) {
                        point[1] += dx
                        point[2] += dy
                    }
                }
            }
        }
    }

    static _SortBy(items, field, descending) {
        ; 插入排序：目标数量级在几十到几百，且结果进来时已按置信度排过，接近有序。
        loop items.Length - 1 {
            i := A_Index
            while (i >= 1 && this._Before(items[i + 1], items[i], field, descending)) {
                tmp := items[i]
                items[i] := items[i + 1]
                items[i + 1] := tmp
                i--
            }
        }
        return items
    }

    static _Before(left, right, field, descending) {
        a := this._FieldValue(left, field)
        b := this._FieldValue(right, field)
        return descending ? (a > b) : (a < b)
    }

    static _FieldValue(item, field) {
        if (field = "_area") {
            w := this._Prop(item, "w", 0)
            h := this._Prop(item, "h", 0)
            return (IsNumber(w) ? w : 0) * (IsNumber(h) ? h : 0)
        }
        value := this._Prop(item, field, 0)
        return IsNumber(value) ? value : 0
    }

    ; 优先用内核给的 anchor（姿态是选定的关键点，语义分割是重心），没有才退回框中心。
    static ClickTarget(item, data, resolve) {
        x := "", y := ""
        anchor := this._Prop(item, "anchor", "")
        if (IsObject(anchor) && anchor.Length >= 2) {
            x := anchor[1], y := anchor[2]
        } else {
            x := this._Prop(item, "cx", ""), y := this._Prop(item, "cy", "")
        }
        if (!IsNumber(x) || !IsNumber(y))
            return

        offsetX := this._IntOr(resolve(data.OffsetX), 0)
        offsetY := this._IntOr(resolve(data.OffsetY), 0)
        MouseMove(Round(x) + offsetX, Round(y) + offsetY, 0)
        switch CmdEnumZh(data.ActionType, this.Actions) {
            case "左键单击": Click
            case "左键双击": Click 2
            case "右键单击": Click "Right"
        }
    }

    ; ---------- 参数解析 ----------

    static ParseConf(text) {
        text := Trim(String(text))
        if (text == "")
            return 0.25
        if (!IsNumber(text))
            throw Error(GetLang("置信度须为 0~1 之间的数字。"))
        value := Float(text)
        if (value > 1 && value <= 100)
            value /= 100          ; 允许填 50 表示 50%
        if (value <= 0 || value > 1)
            throw Error(GetLang("置信度须为 0~1 之间的数字。"))
        return value
    }

    static ParseIou(text) {
        text := Trim(String(text))
        if (text == "")
            return 0.45
        if (!IsNumber(text))
            throw Error(GetLang("IoU 须为 0~1 之间的数字。"))
        value := Float(text)
        if (value <= 0 || value > 1)
            throw Error(GetLang("IoU 须为 0~1 之间的数字。"))
        return value
    }

    ; 0~1 的比例，允许填百分数；空值按 fallback 处理。
    static ParseRatio(text, message) {
        text := Trim(String(text))
        if (text == "")
            return 0.0
        if (!IsNumber(text))
            throw Error(message)
        value := Float(text)
        if (value > 1 && value <= 100)
            value /= 100
        if (value < 0 || value > 1)
            throw Error(message)
        return value
    }

    static ParseInt(text, fallback, min, max, message) {
        text := Trim(String(text))
        if (text == "")
            return fallback
        if (!IsInteger(text))
            throw Error(message)
        value := Integer(text)
        if (value < min || value > max)
            throw Error(message)
        return value
    }

    ; 采样点：屏幕坐标 → 检测区域内的像素坐标。两个都留空表示不采样。
    static ParsePoint(xText, yText, region) {
        xText := Trim(String(xText)), yText := Trim(String(yText))
        if (xText == "" && yText == "")
            return [-1, -1]
        if (!IsInteger(xText) || !IsInteger(yText))
            throw Error(GetLang("采样点须为 X、Y 两个整数。"))
        x := Integer(xText) - region[1]
        y := Integer(yText) - region[2]
        if (x < 0 || y < 0 || x >= region[3] - region[1] || y >= region[4] - region[2])
            throw Error(GetLang("采样点不在检测区域内。"))
        return [x, y]
    }

    ; 空表示主屏全屏；否则是 "x1,y1,x2,y2"，超屏部分会被夹到屏幕内。
    static ParseRegion(text) {
        text := Trim(String(text))
        left := SysGet(76), top := SysGet(77)
        right := left + SysGet(78), bottom := top + SysGet(79)
        if (text == "")
            return [left, top, right, bottom]

        coords := StrSplit(text, ",")
        if (coords.Length != 4)
            throw Error(GetLang("请先框选检测区域。"))
        for i, coord in coords {
            if (!IsInteger(Trim(coord)))
                throw Error(GetLang("检测区域坐标无效。"))
            coords[i] := Integer(Trim(coord))
        }
        if (coords[3] <= coords[1] || coords[4] <= coords[2])
            throw Error(GetLang("检测区域坐标无效。"))
        return [
            Max(coords[1], left), Max(coords[2], top),
            Min(coords[3], right), Min(coords[4], bottom)
        ]
    }

    ; ---------- 杂项 ----------

    ; 旧配置里没有任务专属字段，补齐后再用，避免读属性时抛错。
    static Normalize(data) {
        if (!IsObject(data))
            return YoloData()
        template := YoloData()
        for name in this.Fields
            if (!data.HasProp(name))
                data.%name% := template.%name%
        return data
    }

    static _Prop(obj, name, default := "") {
        if (!IsObject(obj))
            return default
        if (obj is Map)
            return obj.Has(name) ? obj[name] : default
        return obj.HasProp(name) ? obj.%name% : default
    }

    static _DeviceIndex(device) {
        switch device {
            case "CUDA": return 1
            case "DirectML": return 2
            case "TensorRT": return 3
            case "CoreML": return 4
        }
        return 0
    }

    static _IntOr(text, fallback) {
        text := Trim(String(text))
        return IsInteger(text) ? Integer(text) : fallback
    }
}

OnYolo(tableItem, cmd, index) {
    data := Yolo.Normalize(GetMacroCMDData(StrSplit(cmd, "_")[1]))
    cancelled := () => tableItem.Items[index].Killed
    if (cancelled())
        return

    out := ""
    failure := ""
    try out := Yolo.Execute(data, (text) => GetReplaceVarText(tableItem, index, text), cancelled)
    catch as e
        failure := e.Message
    if (!cancelled())
        SaveYoloResult(data, out, failure)
}

RegisterYoloVars(data) {
    data := Yolo.Normalize(data)
    for name in [data.CountVar, data.ClassVar, data.ConfVar, data.RatioVar, data.DepthVar,
        data.ResultVar, data.ErrorVar]
        if (name != "")
            MySoftData.GlobalVariMap[name] := true
}

SaveYoloResult(data, out, failure) {
    if (!IsObject(out))
        out := {count: "", name: "", conf: "", ratio: "", depth: "", result: ""}

    names := []
    values := []
    for pair in [[data.CountVar, out.count], [data.ClassVar, out.name], [data.ConfVar, out.conf],
        [data.RatioVar, out.ratio], [data.DepthVar, out.depth],
        [data.ResultVar, out.result], [data.ErrorVar, failure]] {
        if (pair[1] == "")
            continue
        names.Push(pair[1])
        values.Push(pair[2])
    }
    if (names.Length)
        MySetGlobalVariable(names, values, false)
    ; 没填错误变量时，失败要中断宏，否则用户会以为检测过但没找到。
    if (failure != "" && data.ErrorVar == "")
        throw Error(failure)
}
