# RMT YOLO 推理内核

`RMT_YOLO.dll` 是「YOLO检测」指令的原生推理内核：把 Ultralytics 的 Rust 推理库
`ultralytics-inference` 包成一层 C ABI，由 `Main/Util/YoloUtil.ahk` 的 `Yolo` 类调用。
ABI 定义见 [`src/RMT_Yolo.h`](src/RMT_Yolo.h)，当前版本 2。

内核只负责推理。截图、区域裁剪、坐标偏移、类别过滤和鼠标动作都在 AHK 侧，
内核不碰窗口、不回调、也不知道结果会被怎么用。

## 文件构成

| 文件 | 作用 |
|---|---|
| `src/RMT_Yolo.h` | ABI 合同。只增不改，改签名必须升 `RMT_YOLO_API_VERSION` |
| `src/lib.rs` | 导出函数、句柄与缓冲管理，只做类型转换 |
| `src/engine.rs` | 唯一与 `ultralytics-inference` 耦合的地方 |
| `Cargo.toml` / `Cargo.lock` | 依赖与锁定版本 |
| `build.ps1` | 构建 x64 / x86，产物连同运行库一起拷到 `Plugins\YOLO\<架构>\` |

`Plugins\YOLO\<架构>\` 是运行期目录，三个文件必须成套：
`RMT_YOLO.dll`、`onnxruntime.dll`、`onnxruntime_providers_shared.dll`。
这份清单只写在 `Yolo.Files` 一处，编辑器查缺（`YoloGui._EnsurePluginFiles`）
与自检（`Main/SelfCheck.ahk` 的 `optionalFiles`）共用它。

## 任务与字段

任务由模型元数据决定，指令里不选任务；换模型就换输出。**任务不同，参数和输出也不同**，
下表是每个任务真正会用到的字段：

| 任务 | 模型 | 任务专属参数 | 任务专属结果 |
|---|---|---|---|
| detect | `yolo26n.onnx` | `conf` / `maxDet` | `items[].box / cx / cy / conf / anchor` |
| segment | `yolo26n-seg.onnx` | + `minMaskRatio` | `items[].maskRatio` |
| pose | `yolo26n-pose.onnx` | + `keypointConf` / `anchorKpt` | `items[].keypoints`、`anchor` 按关键点 |
| obb | `yolo26n-obb.onnx` | `conf` / `maxDet` | `items[].angle` + 外接 `box` |
| classify | `yolo26n-cls.onnx` | `conf` / `topK` | `top1` 与 `probs[]`（没有 items） |
| semantic | `yolo26n-sem.onnx` | `minMaskRatio` | `items[].ratio / area / box / cx / cy` |
| depth | `yolo26n-depth.onnx` | `sampleX` / `sampleY` | `depth.min / max / mean / point`（米） |

分类和深度没有目标坐标，所以没有 `count`、`items`、`anchor`。AHK 侧按任务决定
往哪些变量里写值，见 `YoloUtil.ahk` 的 `BuildOutcome`；编辑器按任务决定显示哪些参数，
见 `Gui/YoloGui.ahk` 的布局表。

## 构建

需要 Rust 1.92+ 与 MSVC 工具链（VS Build Tools 的 "Desktop development with C++"）。

```powershell
rustup target add i686-pc-windows-msvc   # x86 需要，x64 无需
.\build.ps1        # x64 → Plugins\YOLO\x64\
.\build.ps1 x86    # x86 → Plugins\YOLO\x86\
```

两个架构都实测可用。当前体积 x64 约 7.7 MB、x86 约 2.9 MB；x86 单帧 detect 约 68 ms，
比 x64 慢一档，属正常范围。

输出目录沿用 `Plugins\<插件>\<架构>\` 约定（与 OpenCV 插件一致），**不要**直接拷
`target\debug` 里的产物：那是未优化版本，推理会慢一个数量级。

## 运行库

内核用 `ort` 的 **`load-dynamic`** 方式使用 ONNX Runtime：编译期不静态链接、不下载任何
预编译包，运行时按 `LoadLibrary("onnxruntime.dll")` 找库（`ORT_DYLIB_PATH` 未设时）。
所以 `onnxruntime.dll` 必须和 `RMT_YOLO.dll` 同目录。`build.ps1` 会从
`Plugins\Voice\<架构>\` 取一份（sherpa-onnx 打包的官方 ONNX Runtime 1.27.1，
`OrtGetApiBase()->GetApi(17)` 非空，满足 `ort` 的 `ORT_API_VERSION = 17`）；
要固定或升级版本，把文件放进 `dll\deps\`，脚本优先用它。

之所以动态加载，是为了避开 `ort` 预编译包的打包方式：win-x64 清单里**没有纯 CPU 条目**，
静态链接会把 DirectML EP 一起编进来，产物硬导入 `DirectML.dll` / `d3d12.dll` / `dxgi.dll`，
白搭 17.67 MB，而本项目只用 CPU EP。改动态加载后 `RMT_YOLO.dll` 从 30.3 MB 降到 7.7 MB，
也不再依赖任何 GPU 运行库。

加载顺序由 `Yolo.EnsureDll` 负责：先按 `LOAD_WITH_ALTERED_SEARCH_PATH`（`LoadLibraryEx`
的 `0x8`）把目录里的依赖 DLL 逐个载入，再载主库并用 `RMT_Yolo_ApiVersion` 校验版本。
这样缺依赖和缺主库能分开报错，也不会改动进程的全局搜索路径。与 Voice 插件同进程时，
两者共用同一份运行库，不会重复映射。

## 模型

导出 ONNX（Ultralytics ≥ 8.4.142）：

```bash
yolo export model=yolo26n.pt format=onnx
# 走 NMS-free 端到端头，速度更快
yolo export model=yolo26n.pt format=onnx nms=False
```

放到 `Plugins\YOLO\models\`，再在 RMT 的「全局模型库」里登记一次即可复用。
登记信息在 `Setting/YoloModels.toml`，其中 `[Tasks]` 缓存每个模型的任务码，
未命中时才用临时句柄读一次元数据。模型体积大，不进发行包。

## 排查

- **提示插件文件缺失**：`Yolo.MissingFiles()` 会一次列全缺的文件。补齐后调 `Yolo.ResetDll()`
  再试，否则会话内一直返回旧的失败原因。
- **`RMT_YOLO.dll` 加载失败**：错误码来自 `A_LastError`，多半是运行库没和主库同目录，
  或文件被占用。目录里多一个来路不明的 `onnxruntime.dll` 也会走到这条。
- **内核版本不匹配**：DLL 与 `Yolo.ApiVersion` 对不上，重装插件，不要改常量。
- **设备只有 CPU**：`Yolo.Devices` 当前只有 `["CPU"]`，其它设备名会被归到 CPU。
  要用 CUDA / DirectML，得在编译内核时带上对应 EP，否则加载返回 -2。

## 许可证

RMT 整体按 **AGPL-3.0** 发布（根目录 `LICENSE`）。内核依赖的 `ultralytics-inference`
（0.0.60）同为 AGPL-3.0，与本项目的分发方式一致，不构成冲突。随包分发时满足三条即可：

- 发行包内附许可文本：`PackRMT.ps1` 的 `Copy-LegalDocs` 把根目录 `LICENSE` 与
  `DISCLAIMER.md` 拷到发行版根。
- 源码可得：本目录的 `src/`、`Cargo.toml`、`Cargo.lock` 已入库；上游 crate 源码在
  crates.io 公开可得。本目录没有修改上游源码，只是依赖。
- 保留版权声明，不删除上游许可与 NOTICE。

只有闭源分发（收费闭源版、不接受 copyleft 的分发渠道）才需要 Ultralytics 商业授权，
或改走自研推理路径（直接用 `ort` 加自己写的前后处理）。

模型权重另行注意：Ultralytics 主张用其框架训练或导出的模型同样受 AGPL 约束。
RMT 不分发模型，模型由用户自备并登记，因此不涉及；若将来随包分发权重，按同一协议公开即可。

## 性能备忘

- 单帧输入是 BGRA（Windows 截图原生排列），内核只做一次 R→B 通道交换。
- `conf` 可以逐帧改（加载时按 0.01 兜底，过滤在每帧做）；`iou` 是 NMS 参数，改它必须
  重载模型，所以它是 `Yolo` 句柄缓存键（`路径|设备|iou`）的一部分。
- 模型加载是秒级操作，句柄必须缓存，缓存与复用见 `YoloUtil.ahk`。
- 类别过滤只影响结果、不影响耗时：内核仍推理全部类别。
