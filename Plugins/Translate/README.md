# Translate 插件（本地翻译）

进程内推理的翻译组件：模型是 [Index-Translate-2B](https://huggingface.co/IndexTeam/Index-Translate-2B-GGUF)（Qwen3.5 底座，Apache-2.0）的官方 GGUF。推理用 llama.cpp 构建为 `llama.dll` / `ggml.dll` / `ggml-base.dll`，与 `TranslateDll.dll` 同目录分发，不会和 `Plugins\Voice` 的 onnxruntime 共享或冲突。CPU 计算后端经 GGML_BACKEND_DL 拆成 `ggml-cpu-<variant>.dll`，按机器指令集（SSE4.2/AVX/AVX2…）运行时自动挑变体，旧机器落 baseline，不要求 AVX2。不联网、不起外部服务。

## 布局

```
src\TranslateDll.h        对外 ABI 合同（C，__cdecl，UTF-16 进出）
src\TranslateDll.cpp      封装实现：Load/Run/Cancel，prompt 构造与输出清理
x64\TranslateDll.dll      运行时产物（x64 专用，含 CPU 变体后端 ggml-cpu-*.dll）
models\*.gguf             模型（1.3 GB，git 忽略，按需下载）
third_party\              llama.cpp 源码与 CMake 构建缓存（git 忽略）
buildDll.ps1              一键构建
GetTranslateModel.ps1     单独下载模型（ModelScope 优先，HF 兜底）
```

## 为什么 x86 没有

2B Q4_K_M 权重 1.31 GB，32 位进程用户态地址空间约 2 GB，再叠 KV cache 与碎片后放不下。翻译指令只在 x64 可用；AHK 32 位下 `TranslateEngine.Available()` 返回 false，指令会给出明确错误。

## 构建

```powershell
.\buildDll.ps1                # 下载 llama.cpp 源码 + CMake 编共享库 + 编译部署
.\buildDll.ps1 -SkipModel     # 不下载模型（只改 C++ 时省 1.3 GB 下载）
.\buildDll.ps1 -SkipLlamaBuild # 复用已编好的共享库，只重编封装层
```

需要 MSVC 与 cmake/ninja（VS BuildTools 勾选「C++ CMake tools for Windows」，或独立安装）。
脚本**不调 vcvars64.bat**：它靠 `reg.exe` 探测安装，受限环境里会半途失败、表现为找不到
`cl.exe` / `rc.exe`。这里按目录直接拼 `PATH` / `INCLUDE` / `LIB`，取版本号最高的 MSVC 与
Windows SDK，结果可复现。`cmake` 用 Ninja 生成器（不是 VS 生成器，后者同样依赖注册表探测）。

llama.cpp 版本用 tag `b12540` 锁死：它的 C API 小版本间也会改签名（b12540 已把
`llama_batch_get_one` / `llama_decode` 标 deprecated，本插件暂时继续用旧接口，见
TranslateDll.cpp 顶部注释），升级前先核对 `src\TranslateDll.cpp` 用到的函数。

## 模型

| 文件 | 用途 |
| --- | --- |
| `Index-Translate-2B.Q4_K_M.gguf` | 默认档，1.31 GB，短句与日常文案 |
| `Index-Translate-9B.Q4_K_M.gguf` | 可选，约 5.9 GB，更高质量（下载后翻译指令里选 9B） |

2B 的量化档里 Q4_K_M 与官方发布口径一致；换档位改 `GetTranslateModel.ps1` 的 `-Model` 与
`TranslateCommand.EngineModels` 的映射即可。

## 推理参数

- 贪心解码（greedy），保证同样输入同样输出。
- 手拼 ChatML prompt，**不加** `/no_think`：Index-Translate 是微调过的翻译模型，本身不吐
  思考块，而这个软开关反而会被偶发地抄进译文（实测「关闭窗口前请保存文件。」后面多出一行
  `/no_think`）。`CleanOutput` 仍保留思考块、`/no_think`、`<|im_start|>` / `<|im_end|>` 的兜底剥离。
- 默认 nCtx 2048、maxTokens 512、超时 30 s；术语表走 prompt 硬约束（“原文 → 译文”）。

实测（i7 级 CPU，纯 CPU 推理，无 GPU）：2B Q4_K_M 加载约 0.65 s，一句 15~20 词的译文
0.7~0.9 s（约 18 tok/s 解码）。

## 宿主

`Main\Util\TranslateUtil.ahk` 的 `class TranslateEngine` 是唯一入口；指令实现在
`Main\Util\TranslateCommand.ahk`。DllCall 全部显式 `CDecl`。ABI 版本用
`Translate_ApiVersion()` 校验，与 `TranslateDll.h` 的 `TRANSLATE_API_VERSION` 对不上时
指令报「组件版本不匹配」。

**状态存活**：DLL 在 `DLL_PROCESS_ATTACH` 时用 `GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_PIN)`
把自己钉在进程里。原因是 AHK 的 `DllCall` 打完就放掉模块引用，引用归零即卸载——已加载的
1.3 GB 模型随之消失，而调用方只看到「返回 0、错误文本为空」。自钉住之后，宿主无论保不保
引用，模型都在。
