// =====================================================================
// TranslateDll.h —— 翻译组件对外契约（C ABI）
//
// 这是「合同」，不是「实现」。
//   · 宿主（AHK 侧 TranslateEngine）只依赖这里声明的东西
//   · 换推理引擎（llama.cpp / ONNX / 其他）不得改动任何签名
//   · 只有「能力本身变了」才改签名，改了必须把 TRANSLATE_API_VERSION 加一
//
// 通用约定
//   · 调用约定固定 __cdecl。x64 只有一种约定无所谓，x86 必须显式声明，
//     宿主侧（AHK DllCall）也要显式写 CDecl，否则 32 位下栈会被弹坏。
//   · 入参字符串：const wchar_t*，UTF-16，NUL 结尾。
//   · 出参文本：wchar_t*，UTF-16，NUL 结尾；缓冲由宿主提供，DLL 不分配不释放。
//     超出 outChars-1 个字符时按字符截断，保证 NUL 结尾，并在 Stats.truncated 里置 1。
//   · 本组件是全局单例：一个进程只加载一份模型、只跑一条推理。
//     翻译指令是同步等待的，不存在并发调用；需要丢弃当前结果就调 Translate_Cancel。
//   · 模块在 DLL_PROCESS_ATTACH 时把自己钉在进程里（GetModuleHandleEx + PIN）。
//     宿主不检查返回值、或者每次调用后释放模块引用，都不会把已加载的模型弄丢——
//     这条是踩过的坑：AHK 的 DllCall 调完就放引用，引用归零即卸载，状态全没，
//     而调用方只看到「返回 0、错误为空」。
//   · DLL 不回调、不通知、不碰窗口。翻出来的文本写进变量还是贴到剪贴板，是宿主的事。
//
// 线程约定
//   · Translate_Load / Translate_Run 在同一线程内同步执行，阻塞时长由模型大小决定
//     （2B Q4 首次加载 1~2 秒，一句短文本推理 1~3 秒）。
//   · Translate_Cancel 可以从另一个线程调，用来中断正在跑的 Translate_Run。
//   · 不要在其他线程调 Translate_Unload：卸载要求当前没有推理在执行。
// =====================================================================
#ifndef TRANSLATE_DLL_H
#define TRANSLATE_DLL_H

#include <stdint.h>
#include <wchar.h>      // wchar_t（C 宿主需要；C++ 内置）

// ABI 版本：宿主可用 Translate_ApiVersion() 校验 DLL 是否与本头文件匹配。
// 历史：1 = 初版（Load / Run / Cancel）；2 = Run 支持逐次超时与结构化术语表。
#define TRANSLATE_API_VERSION 3

#if defined(_WIN32)
#  if defined(TRANSLATE_BUILD)
#    define TRANSLATE_API __declspec(dllexport)
#  else
#    define TRANSLATE_API __declspec(dllimport)
#  endif
#  define TRANSLATE_CALL __cdecl
#else
#  define TRANSLATE_API __attribute__((visibility("default")))
#  define TRANSLATE_CALL
#endif

// 加载/推理参数。structSize须等于当前sizeof(TranslateOptions)。
typedef struct TranslateOptions {
    int32_t structSize;     // sizeof(TranslateOptions)
    int32_t nCtx;           // 上下文长度，0 = 2048。翻译是单向短文本，不需要长上下文
    int32_t nThreads;       // 计算线程数，0 = 由 DLL 按 CPU 核数决定（只对 CPU 计算生效）
    int32_t maxTokens;      // 单次输出 token 上限，0 = 512
    int32_t nBatch;         // 批大小，0 = 512
    int32_t nGpuLayers;     // GPU 卸载层数：-1 = 自动（有 Vulkan/GPGPU 后端就全卸载，没有落 CPU）；
                            // 0 = 仅 CPU（不碰显存）；>0 = 卸载指定层数。
                            // 换了取值要重新 Load 才生效，登录后不可切换。
} TranslateOptions;

typedef struct TranslateGlossaryItem {
    const wchar_t* source;
    const wchar_t* target;
} TranslateGlossaryItem;

// 一次翻译的统计信息，用于宿主日志与「翻到一半被截断」的判定。
typedef struct TranslateStats {
    int32_t promptTokens;   // prompt 的 token 数（含模板与术语表）
    int32_t outputTokens;   // 实际生成的 token 数
    int32_t elapsedMs;      // 从开始 prefill 到生成结束的毫秒数
    int32_t truncated;      // 1 = 超时、达到输出上限或写满缓冲，译文可能不完整
} TranslateStats;

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------
// 版本与状态
// ---------------------------------------------------------------------
// 返回 TRANSLATE_API_VERSION。宿主启动时校验；不一致说明 DLL 与宿主编译期假设不同。
TRANSLATE_API int TRANSLATE_CALL Translate_ApiVersion(void);

// 推理后端的版本串（如 "llama.cpp b12540"），写进 UTF-8 缓冲。
// 用于「模型能加载但输出不对」时判断是不是后端太旧。返回写入字节数。
TRANSLATE_API int TRANSLATE_CALL Translate_BackendVersion(char* buf, int32_t bufSize);

// 本机是否有可用的 GPU 推理后端（同目录下加载成功的 Vulkan 等后端里存在非 CPU 设备）。
// 1 = 有，0 = 没有。宿主用它决定界面里 GPU 选项是否可选。
// 必须在 Load 之前也能调：内部会按 DLL 所在目录加载后端，不需要先 Load。
TRANSLATE_API int TRANSLATE_CALL Translate_HasGpu(void);

// 模型是否已加载。1 = 可以调 Run。
TRANSLATE_API int TRANSLATE_CALL Translate_IsLoaded(void);

// 取最近一次失败的原因（UTF-8）。没有错误返回 0。返回写入字节数。
TRANSLATE_API int TRANSLATE_CALL Translate_LastError(char* buf, int32_t bufSize);

// ---------------------------------------------------------------------
// 模型
// ---------------------------------------------------------------------
// 同步加载 GGUF（阻塞，2B Q4 约 1~2 秒）。成功返回 1；失败返回 0，原因取 LastError。
// opt 传 NULL 用默认参数。重复调用会先卸载旧模型。
TRANSLATE_API int TRANSLATE_CALL Translate_Load(const wchar_t* ggufPath, const TranslateOptions* opt);

// 卸载模型并释放上下文。model 与 llama 后端一起释放（进程内只有这一份）。
TRANSLATE_API void TRANSLATE_CALL Translate_Unload(void);

// ---------------------------------------------------------------------
// 翻译
// ---------------------------------------------------------------------
// text     源文本（UTF-16）
// target   目标语言：语言码（zh / en / ja / ko / ru / fr / de / es …）或语言名
//          （“简体中文” / “English”），会原样写进 prompt，不做映射表
// 术语表使用结构化 glossaryItems，不解析分隔符
// glossaryItems / glossaryCount 结构化术语对照；字符串内容原样写入 prompt
// timeoutMs 单次调用的时间上限，超时按「已生成部分」返回并置 truncated
// out/outChars  译文出参，宿主提供缓冲，按 wchar_t 计数（含 NUL）
// stats    可为 NULL
//
// 返回 1 = 成功；0 = 失败（取 LastError）；-1 = 被 Cancel 中断。
// 译文不做任何加工：不去引号、不补句号。要去掉模型可能带出的思考块与解释，
// 由 DLL 内部处理（prompt 约束 + 后处理剥离），宿主拿到的是干净译文。
TRANSLATE_API int TRANSLATE_CALL Translate_Run(const wchar_t* text, const wchar_t* target,
                                               const TranslateGlossaryItem* glossaryItems,
                                               int32_t glossaryCount,
                                               int32_t timeoutMs,
                                               wchar_t* out, int32_t outChars,
                                               TranslateStats* stats);

// 中断正在执行的 Translate_Run。可跨线程调用。中断后模型停在半途，
// 下一次 Run 会从头开始（不做 KV 复用，代价可接受）。
TRANSLATE_API void TRANSLATE_CALL Translate_Cancel(void);

#ifdef __cplusplus
}
#endif

#endif // TRANSLATE_DLL_H
