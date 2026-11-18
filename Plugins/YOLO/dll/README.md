# RMT YOLO 推理内核

把 Ultralytics 官方 Rust 推理库（`ultralytics-inference`）包装成 RMT 能直接 `DllCall` 的
`RMT_YOLO.dll`。对外合同见 [`src/RMT_Yolo.h`](src/RMT_Yolo.h)，宿主侧封装见
`Main/Util/YoloUtil.ahk`。

## 任务覆盖

从 YOLO26 起，同一套 ONNX 模型可以覆盖全部任务，内核按模型元数据自动识别，
宿主不需要选任务。**任务不同，参数和输出也不同**，下表是每个任务真正会用到的字段：

| 任务 | 模型 | 任务专属参数 | 任务专属结果 |
|---|---|---|---|
| detect | `yolo26n.onnx` | `conf` / `maxDet` | `items[].box / cx / cy / conf / anchor` |
| segment | `yolo26n-seg.onnx` | + `minMaskRatio` | `items[].maskRatio` |
| pose | `yolo26n-pose.onnx` | + `keypointConf` / `anchorKpt` | `items[].keypoints`、`anchor` 按关键点 |
| obb | `yolo26n-obb.onnx` | `conf` / `maxDet` | `items[].angle` + 外接 `box` |
| classify | `yolo26n-cls.onnx` | `conf` / `topK` | `top1` 与 `probs[]`（没有 items） |
| semantic | `yolo26n-sem.onnx` | `minMaskRatio` | `items[].ratio / area / box / cx / cy` |
| depth | `yolo26n-depth.onnx` | `sampleX` / `sampleY` | `depth.min / max / mean / point`（米） |

分类与深度没有目标坐标，所以没有 `count`、`items`、`anchor` 这些字段；宿主侧也是
按任务决定写哪几个变量（见 `Main/Util/YoloUtil.ahk` 的 `BuildOutcome`）。

## 构建

需要 Rust 1.92+ 与 MSVC 工具链（VS Build Tools 的 "Desktop development with C++"）。

```powershell
rustup target add i686-pc-windows-msvc   # x86 需要，x64 无需
.\build.ps1        # x64 → Plugins\YOLO\x64\   ← 64 位宿主从这里加载
.\build.ps1 x86    # x86 → Plugins\YOLO\x86\   ← 32 位宿主从这里加载
```

两个架构都实测可用（`load-dynamic` 之后不再受 `ort` 预编译包「只有 x64/ARM64」的限制，
32 位运行库取自 `Plugins\Voice\x86\`）。x86 版内核 2.9 MB，单帧 detect 约 68 ms，
比 x64 慢一档，属正常范围。

输出目录与 OpenCV 插件同一约定（`Plugins\<插件>\<架构>\`），**不要**直接拷
`target\debug` 里的产物：那是未优化版本，推理会慢一个数量级。

### 运行库（重要）

内核用 `ort` 的 **`load-dynamic`** 方式使用 ONNX Runtime：编译期不静态链接、不下载任何
预编译包，运行时按 `LoadLibrary("onnxruntime.dll")` 找库（`ORT_DYLIB_PATH` 未设时）。
所以 `onnxruntime.dll` 必须与 `RMT_YOLO.dll` 同目录，构建脚本会从
`Plugins\Voice\<架构>\` 自动取一份（sherpa-onnx 打包的官方 ONNX Runtime 1.27.1，
`OrtGetApiBase()->GetApi(17)` 非空，满足 `ort` 的 `ORT_API_VERSION = 17`）。
想固定/升级版本就把文件放进 `dll\deps\`，脚本优先用它。

这样做是为了避开 `ort` 预编译包的打包方式：win-x64 清单里**没有纯 CPU 条目**，静态链接
会把 DirectML EP 一起编进来，产物硬导入 `DirectML.dll` / `d3d12.dll` / `dxgi.dll`，
白搭 17.67 MB；本项目只用 CPU EP，不需要它。改动态加载后 `RMT_YOLO.dll` 从 30.3 MB
降到 7.7 MB，且不再依赖任何 GPU 运行库。

宿主用 `LoadLibraryEx(..., LOAD_WITH_ALTERED_SEARCH_PATH)` 先加载目录内所有 DLL，
`ort` 随后 `LoadLibrary("onnxruntime.dll")` 会命中已加载的模块；与 Voice 插件同进程时
两者共用同一份运行库，不会重复映射。

## 模型

导出 ONNX（Ultralytics ≥ 8.4.142）：

```bash
yolo export model=yolo26n.pt format=onnx
# 走 NMS-free 端到端头，速度更快
yolo export model=yolo26n.pt format=onnx nms=False
```

放到 `Plugins/YOLO/models/`，再在 RMT 的「全局模型库」里登记一次即可复用。

## 许可证（重要）

`ultralytics-inference` 是 **AGPL-3.0**（商用另有 Ultralytics Enterprise License）。
AGPL 是强传染性协议：把本 DLL 随 RMT 一起分发，会被要求整个作品按 AGPL 开源。
如果 RMT 是闭源或非 AGPL 分发，必须购买 Ultralytics 商业授权，或改用
自行训练的模型 + 自研推理路径。OpenCV 那种 Apache-2.0 的处理方式在这里不适用。

## 性能备忘

- 单帧输入是 BGRA（Windows 截图原生排列），内核只做一次 R→B 通道交换。
- `conf` 可以逐帧改（加载时按 0.01 兜底，过滤在每帧做）；`iou` 是 NMS 参数，
  改它必须重载模型，所以宿主的句柄缓存键里包含 iou。
- 模型加载是秒级操作，宿主必须缓存句柄。`Main/Util/YoloUtil.ahk` 里有实现。
