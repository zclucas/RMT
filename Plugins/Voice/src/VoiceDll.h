// =====================================================================
// VoiceDll.h —— 语音组件对外契约（C ABI）
//
// 这是「合同」，不是「实现」。
//   · 宿主（AHK / C# / Python / 任何语言）只依赖这里声明的东西
//   · 换实现（换识别引擎、换采集方式、换解码策略）不得改动任何签名
//   · 只有「能力本身变了」才改签名，改了必须把 VOICE_API_VERSION 加一
//
// 通用约定
//   · 调用约定固定 __cdecl。x64 只有一种约定无所谓，x86 必须显式声明，
//     宿主侧（如 AHK DllCall）也要显式写 CDecl，否则 32 位下栈会被弹坏。
//   · 入参字符串：const wchar_t*，UTF-16，NUL 结尾。
//   · 出参字符串：char*，UTF-8，NUL 结尾；缓冲由宿主提供，DLL 不分配不释放。
//     文本超出 bufSize-1 字节时按字节截断，保证 NUL 结尾。
//   · DLL 不回调、不通知、不碰窗口：宿主自己轮询（Poll / GetState），
//     拿到文本怎么显示、怎么拼接，全是宿主的事。
//   · 同一时刻只允许一个线程调用；内部工作线程（采集 / 解码 / 模型加载）由 DLL 自己管。
//   · 阻塞情况：Init 同步加载（首次 1~3 秒）；InitAsync 立即返回；
//     其余调用都很快，唯独 End 会先等设备尾音落定（约 40ms）再做收尾解码，
//     返回时本轮文本已经定稿。
// =====================================================================
#ifndef VOICE_DLL_H
#define VOICE_DLL_H

#include <wchar.h>      // wchar_t（C 宿主需要；C++ 内置）

// ABI 版本：宿主可用 Voice_ApiVersion() 校验 DLL 是否与本头文件匹配。
// 历史：2 = 有 SttStream_InitAsync/InitState 的异步加载版；3 = 明确 cdecl + 收尾自等尾音。
#define VOICE_API_VERSION 3

#if defined(_WIN32)
#  if defined(VOICE_BUILD)
#    define VOICE_API __declspec(dllexport)
#  else
#    define VOICE_API __declspec(dllimport)
#  endif
#  define VOICE_CALL __cdecl
#else
#  define VOICE_API __attribute__((visibility("default")))
#  define VOICE_CALL
#endif

// 流式识别状态。0/1/2 为进行中，3/4 为已落定。
typedef enum {
    STT_STREAM_IDLE      = 0,   // 空闲，没有进行中的流
    STT_STREAM_RECORDING = 1,   // 正在采集 + 解码
    STT_STREAM_REFINING  = 2,   // 已停录，后台精修中（仅 End(refine=1) 会进这个状态）
    STT_STREAM_DONE      = 3,   // 已落定，可以取最终文本
    STT_STREAM_ERROR     = 4    // 出错，错误信息用 GetLastError 取
} SttStreamState;

// 模型后台加载状态（SttStream_InitState 的返回值）
typedef enum {
    STT_INIT_NONE     = 0,      // 还没开始
    STT_INIT_LOADING  = 1,      // 加载中
    STT_INIT_OK       = 2,      // 加载成功
    STT_INIT_FAILED   = 3       // 加载失败
} SttInitState;

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------
// 版本
// ---------------------------------------------------------------------
// 返回 VOICE_API_VERSION。宿主启动时可校验；不一致说明 DLL 与宿主编译期
// 假设不同（典型场景：宿主更新了但语音组件没跟着更新）。
VOICE_API int VOICE_CALL Voice_ApiVersion(void);

// ---------------------------------------------------------------------
// 关键词触发（KWS，常驻监听）
// ---------------------------------------------------------------------
// 全部路径为 UTF-16。初始化成功返回 1。
VOICE_API int VOICE_CALL Voice_Init(const wchar_t* encoder, const wchar_t* decoder,
                                    const wchar_t* joiner, const wchar_t* tokens);
// 关键词集，纯汉字，'|' 分隔；内部转拼音音素。返回是否成功。
VOICE_API int VOICE_CALL Voice_SetKeywords(const wchar_t* keywords);
VOICE_API int VOICE_CALL Voice_SetKeywordsZh(const wchar_t* keywords);

VOICE_API int VOICE_CALL Voice_Start(void);     // 开始常驻监听
VOICE_API int VOICE_CALL Voice_Stop(void);      // 停止常驻监听（不释放模型）

// 取一个命中的关键词（UTF-8）。没有命中返回 0，有则返回 1。
VOICE_API int VOICE_CALL Voice_GetTriggered(char* buf, int bufSize);
VOICE_API int VOICE_CALL Voice_GetLastError(char* buf, int bufSize);
VOICE_API void VOICE_CALL Voice_Close(void);

// 离线验证：整个 wav 走一遍 KWS，把命中的词写进 out。不依赖麦克风。
VOICE_API int VOICE_CALL Voice_TestWav(const wchar_t* wavPath, char* out, int outSize);

// ---------------------------------------------------------------------
// 离线识别（Stt_*）—— 已停用，保留导出
// 整段录完再解码，延迟高，当前输入法不用；DLL 内实现仍在，日后要恢复精修可直接接。
// ---------------------------------------------------------------------
VOICE_API int VOICE_CALL Stt_Init(const wchar_t* model, const wchar_t* tokens);
VOICE_API int VOICE_CALL Stt_Begin(void);
VOICE_API int VOICE_CALL Stt_End(void);
VOICE_API int VOICE_CALL Stt_Cancel(void);
VOICE_API int VOICE_CALL Stt_GetState(void);
VOICE_API int VOICE_CALL Stt_GetResult(char* buf, int bufSize);
VOICE_API int VOICE_CALL Stt_GetLastError(char* buf, int bufSize);
VOICE_API void VOICE_CALL Stt_Close(void);
VOICE_API int VOICE_CALL Stt_TestWav(const wchar_t* wavPath, char* out, int outSize);

// ---------------------------------------------------------------------
// 流式识别（SttStream_*）—— 输入法用的是这一套
//
// 生命周期：
//     Init / InitAsync  →  Begin  →  每 40ms 左右 Poll（取当前文本）
//                       →  End(0)（返回即定稿）  →  GetResult  →  （下一轮 Begin）
//     Cancel 用于丢弃本轮。
//
// 一轮结束（End 返回 1）后文本已经定稿，直接 GetResult 即可，不需要再问状态。
// ---------------------------------------------------------------------
// 同步加载模型（阻塞，首次约 1~3 秒）。模型形态由实现判定（transducer / CTC）。
// decoder / joiner 传 NULL 或空串表示单模型形态。
VOICE_API int VOICE_CALL SttStream_Init(const wchar_t* encoder, const wchar_t* decoder,
                                        const wchar_t* joiner, const wchar_t* tokens);
// 后台线程加载，立即返回；进度用 SttStream_InitState 查。
VOICE_API int VOICE_CALL SttStream_InitAsync(const wchar_t* encoder, const wchar_t* decoder,
                                             const wchar_t* joiner, const wchar_t* tokens);
VOICE_API int VOICE_CALL SttStream_InitState(void);

// 开一轮：建流 + 起采集。成功返回 1。
VOICE_API int VOICE_CALL SttStream_Begin(void);

// 取本轮当前累积文本（整段，不是增量）。解码在 DLL 内部线程完成，本调用只是内存拷贝。
// 返回 1 表示取到（可能为空串），0 表示当前不在录音中。
VOICE_API int VOICE_CALL SttStream_Poll(char* out, int outSize);

// 收尾：先等设备缓冲里的尾音进流（约 40ms），再做完收尾解码。
// 返回 1 表示本轮已定稿；0 表示没有进行中的流或没采到音频（err）。
// refine != 0 时额外用离线模型重识别整段，那是异步的（状态先进 REFINING 再到 DONE），
// 宿主需要自己等 —— 实时输入场景传 0。
VOICE_API int VOICE_CALL SttStream_End(int refine);

// 立即停止并丢弃本轮，不解码。
VOICE_API int VOICE_CALL SttStream_Cancel(void);

VOICE_API int VOICE_CALL SttStream_GetState(void);

// 取本轮最终文本（UTF-8）。录音中或已定稿返回 1，其他状态返回 0。
VOICE_API int VOICE_CALL SttStream_GetResult(char* buf, int bufSize);
VOICE_API int VOICE_CALL SttStream_GetLastError(char* buf, int bufSize);

// 释放模型与流。可重复调用。
VOICE_API void VOICE_CALL SttStream_Close(void);

// 离线验证：按 100ms 分片喂 wav，模拟实时上屏，最终返回全文。不依赖麦克风。
VOICE_API int VOICE_CALL SttStream_TestWav(const wchar_t* wavPath, char* out, int outSize);

#ifdef __cplusplus
}   // extern "C"
#endif

#endif  // VOICE_DLL_H
