// =====================================================================
// TranslateDll.cpp —— 进程内翻译（llama.cpp 静态链接）
//
// 分层：
//   本文件只做「文本 → 译文」，不碰窗口、不联网、不读配置。
//   模型放哪、什么时候加载、译文进变量还是剪贴板，都是 AHK 侧的事。
//
// 为什么共享库分发：
//   llama.cpp 构建为 llama.dll / ggml.dll / ggml-base.dll，与 TranslateDll.dll
//   同目录分发（AHK 侧 LOAD_WITH_ALTERED_SEARCH_PATH 保证依赖从本目录解析），
//   不会和 Plugins\Voice 下的 onnxruntime / sherpa 争抢同名依赖。
//   CPU 计算后端由 GGML_BACKEND_DL 拆成 ggml-cpu-<variant>.dll 运行时加载，
//   按机器指令集（SSE4.2 / AVX / AVX2…）自动挑变体，旧机器落 baseline。
//   共享是强制的：ggml-base 若静态进 TranslateDll，每个后端 DLL 会各自内嵌
//   一份 ggml-base，运行时两份 ggml 状态必崩（b12540 在 CMake 里硬性检查）。
//   这些 DLL 缺失时 Translate_Load 会明确报错，不会静默失败。
//
// 模型：
//   Index-Translate-2B（Qwen3.5 混合架构：每 4 层 full attention，其余 GatedDeltaNet）。
//   GGUF 直接用官方发布版，不做转换。
//
// 模板：
//   不用 llama_chat_apply_template —— 它只认内置模板，Qwen3.5 的 thinking 开关
//   不在其中。这里手拼 ChatML，并且**不加** /no_think：Index-Translate 是微调过的
//   翻译模型，本身不吐思考块，而 /no_think 反而会被偶发地当成正文抄进译文。
//   CleanOutput 仍保留一层剥离（思考块、/no_think、角色标记），只是兜底。
// =====================================================================
#define TRANSLATE_BUILD
#include "TranslateDll.h"

// NOMINMAX：不加的话 windows.h 会把 min/max 定义成宏，后面 std::min 直接编译不过
#define NOMINMAX
#include <windows.h>   // WideCharToMultiByte / MultiByteToWideChar / CP_UTF8

// b12540 把 llama_batch_get_one / llama_decode 标成了 deprecated，
// 但推荐的 llama_batch_ext 需要调用方自己算每个 token 的位置（含线性注意力的
// conv_state 偏移），手写容易错。这里锁死版本、继续用旧接口，升级 llama.cpp 时再切。
#pragma warning(disable: 4996)

#include "llama.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

std::mutex g_mu;                       // 串行化 Load / Run / Unload
llama_model* g_model = nullptr;
const llama_vocab* g_vocab = nullptr;
TranslateOptions g_opt{};
std::string g_lastError;
std::atomic<bool> g_cancel{false};
std::string g_backendVersion;          // "b12540" 之类，第一次 Load 时取

using Clock = std::chrono::steady_clock;

int64_t NowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        Clock::now().time_since_epoch()).count();
}

void SetError(const std::string& s) { g_lastError = s; }

std::string Utf16ToUtf8(const wchar_t* w) {
    if (!w || !*w) return std::string();
    int n = ::WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return std::string();
    std::string out(static_cast<size_t>(n), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, w, -1, &out[0], n, nullptr, nullptr);
    out.resize(static_cast<size_t>(n - 1));
    return out;
}

std::wstring Utf8ToUtf16(const std::string& s) {
    if (s.empty()) return std::wstring();
    int n = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
    if (n <= 0) return std::wstring();
    std::wstring out(static_cast<size_t>(n), L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), &out[0], n);
    return out;
}

std::string Trim(const std::string& s) {
    size_t b = 0, e = s.size();
    auto isSpace = [](unsigned char c) {
        return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
    };
    while (b < e && isSpace(static_cast<unsigned char>(s[b]))) ++b;
    while (e > b && isSpace(static_cast<unsigned char>(s[e - 1]))) --e;
    return s.substr(b, e - b);
}

// ---------------------------------------------------------------------
// prompt
// ---------------------------------------------------------------------
std::string BuildGlossaryBlock(const TranslateGlossaryItem* glossaryItems, int32_t glossaryCount) {
    std::string pairs;
    for (int32_t i = 0; glossaryItems && i < glossaryCount; ++i) {
        const auto& item = glossaryItems[i];
        if (!item.source || !item.target || !item.source[0] || !item.target[0])
            continue;
        if (!pairs.empty()) pairs += "；";
        pairs += Utf16ToUtf8(item.source) + " → " + Utf16ToUtf8(item.target);
    }
    std::string out;
    if (!pairs.empty()) out += "术语对照（必须遵守）：" + pairs + "\n";
    return out;
}

std::string BuildPrompt(const std::string& text, const std::string& target,
                        const TranslateGlossaryItem* glossaryItems, int32_t glossaryCount) {
    std::string lang = target.empty() ? std::string("简体中文") : target;
    std::string p;
    p += "<|im_start|>user\n";
    p += "把下面的内容翻译成" + lang + "。只输出译文，不要解释、不要加引号、不要重复原文、不要保留原文。\n";
    p += BuildGlossaryBlock(glossaryItems, glossaryCount);
    p += "\n";
    p += text;
    p += "<|im_end|>\n";
    p += "<|im_start|>assistant\n";
    return p;
}

// ---------------------------------------------------------------------
// 输出清理
// ---------------------------------------------------------------------
// 可能出现的东西：思考块（……）、开头的“译文：”、结尾多带的一个引号。
// 这里只做「确定是模型产物」的剥离，不去动用户自己的标点。
std::string CleanOutput(const std::string& raw) {
    std::string s = raw;

    // 1) 剥思考块：取最后一个结束标记之后的内容
    const char* kEnd[] = {"<｜end▁of▁thinking｜>", "</think"}; 
    for (const char* mark : kEnd) {
        size_t p = s.rfind(mark);
        if (p != std::string::npos) {
            p = s.find('>', p);
            if (p != std::string::npos) s = s.substr(p + 1);
        }
    }
    // 2) 撞到下一个角色标记就截断（模型偶尔会自己续写对话）
    size_t stop = s.find("<|im_start|>");
    if (stop != std::string::npos) s = s.substr(0, stop);
    stop = s.find("<|im_end|>");
    if (stop != std::string::npos) s = s.substr(0, stop);
    // /no_think 是 Qwen 系的软开关：写在 prompt 里时它偶尔会被当成正文抄进译文
    stop = s.find("/no_think");
    if (stop != std::string::npos) s = s.substr(0, stop);

    s = Trim(s);
    // 3) 去掉开头的“译文：”“翻译：”——模型很爱加
    const char* kPrefix[] = {"译文：", "译文:", "翻译：", "翻译:", "Translation:", "translation:"};
    for (const char* pre : kPrefix) {
        size_t n = std::strlen(pre);
        if (s.compare(0, n, pre) == 0) {
            s = Trim(s.substr(n));
            break;
        }
    }
    return s;
}

void UnloadLocked() {
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_vocab = nullptr;
}

// 加载本 DLL 同目录下的后端 DLL（ggml-cpu-<variant>.dll / ggml-vulkan.dll）。
// llama.cpp 默认只按主程序 exe 目录找，宿主是 RMT 主进程，找不到这批 DLL——
// 必须按本 DLL 自身路径显式加载。反复调用幂等：已注册的后端不会重复注册。
void EnsureBackendsLoaded() {
    HMODULE self = nullptr;
    wchar_t selfPath[MAX_PATH] = L"";
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&EnsureBackendsLoaded), &self);
    if (self && GetModuleFileNameW(self, selfPath, MAX_PATH) > 0) {
        std::wstring dir(selfPath);
        size_t slash = dir.find_last_of(L"\\/");
        if (slash != std::wstring::npos)
            ggml_backend_load_all_from_path(Utf16ToUtf8(dir.substr(0, slash).c_str()).c_str());
    } else {
        ggml_backend_load_all();     // 兜底：按默认搜索路径再试一次
    }
}

bool DecodeChunk(llama_context* ctx, std::vector<llama_token>& tokens, int32_t from, int32_t count) {
    llama_batch batch = llama_batch_get_one(tokens.data() + from, count);
    return llama_decode(ctx, batch) == 0;
}

} // namespace

// =====================================================================
// 模块存活
// =====================================================================
// 自己把自己钉住（PIN）：宿主可能在每次调用后立刻释放模块引用，AHK 的 DllCall
// 就是这样——它加载模块、调完、再放掉引用。引用归零时模块被卸载，本文件里
// 那份「已加载的模型」也跟着没了，但宿主只会看到「返回 0、错误文本为空」，
// 极难定位。把模块钉在进程里，生命周期就跟宿主进程一致，状态才留得住。
BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        ::DisableThreadLibraryCalls(hinst);   // 没有线程局部初始化，省掉 attach/detach 回调
        HMODULE self = nullptr;
        ::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                             reinterpret_cast<LPCWSTR>(&DllMain), &self);
    }
    return TRUE;
}

// =====================================================================
// 导出
// =====================================================================

int TRANSLATE_CALL Translate_ApiVersion(void) {
    return TRANSLATE_API_VERSION;
}

int TRANSLATE_CALL Translate_BackendVersion(char* buf, int32_t bufSize) {
    if (!buf || bufSize <= 0) return 0;
    std::string v = g_backendVersion.empty() ? std::string("llama.cpp (unknown)") : g_backendVersion;
    int n = static_cast<int>(std::min<size_t>(v.size(), static_cast<size_t>(bufSize - 1)));
    std::memcpy(buf, v.data(), static_cast<size_t>(n));
    buf[n] = '\0';
    return n;
}

int TRANSLATE_CALL Translate_IsLoaded(void) {
    return g_model != nullptr ? 1 : 0;
}

int TRANSLATE_CALL Translate_HasGpu(void) {
    EnsureBackendsLoaded();
    const size_t n = ggml_backend_dev_count();
    for (size_t i = 0; i < n; ++i) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (dev && ggml_backend_dev_type(dev) != GGML_BACKEND_DEVICE_TYPE_CPU)
            return 1;
    }
    return 0;
}

int TRANSLATE_CALL Translate_LastError(char* buf, int32_t bufSize) {
    if (!buf || bufSize <= 0) return 0;
    int n = static_cast<int>(std::min<size_t>(g_lastError.size(), static_cast<size_t>(bufSize - 1)));
    if (n > 0) std::memcpy(buf, g_lastError.data(), static_cast<size_t>(n));
    buf[n] = '\0';
    return n;
}

int TRANSLATE_CALL Translate_Load(const wchar_t* ggufPath, const TranslateOptions* opt) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_lastError.clear();

    if (!ggufPath || !*ggufPath) {
        SetError("模型路径为空");
        return 0;
    }
    std::string path = Utf16ToUtf8(ggufPath);

    // 可省略参数使用当前默认值；传入参数时必须符合当前ABI。
    std::memset(&g_opt, 0, sizeof(g_opt));
    g_opt.nCtx = 2048;
    g_opt.maxTokens = 512;
    g_opt.nBatch = 512;
    g_opt.nGpuLayers = -1;   // 自动：有 Vulkan GPU 全卸载，没有落 CPU
    if (opt) {
        if (opt->structSize != static_cast<int32_t>(sizeof(TranslateOptions))) {
            SetError("翻译组件参数版本不匹配");
            return 0;
        }
        g_opt = *opt;
        if (g_opt.nCtx <= 0) g_opt.nCtx = 2048;
        if (g_opt.maxTokens <= 0) g_opt.maxTokens = 512;
        if (g_opt.nBatch <= 0) g_opt.nBatch = 512;
    }

    UnloadLocked();

    EnsureBackendsLoaded();
    if (!ggml_backend_reg_by_name("CPU")) {
        SetError("CPU 后端 DLL 缺失：请保证 ggml-cpu-*.dll 与 TranslateDll.dll 在同一目录（翻译组件不完整，请重新下载）");
        return 0;
    }

    llama_backend_init();

    llama_model_params mp = llama_model_default_params();
    mp.load_mode = LLAMA_LOAD_MODE_MMAP;   // 1.3 GB 模型靠 mmap 加载，首次约 1~2 秒
    mp.n_gpu_layers = g_opt.nGpuLayers;    // -1 = 自动卸载到 Vulkan GPU；无 GPU 时 llama 自己落 CPU

    g_model = llama_model_load_from_file(path.c_str(), mp);
    if (!g_model) {
        SetError("模型加载失败（文件损坏或版本不支持）: " + path);
        return 0;
    }
    g_vocab = llama_model_get_vocab(g_model);
    if (!g_vocab) {
        SetError("模型词表读取失败");
        UnloadLocked();
        return 0;
    }

    if (g_backendVersion.empty()) {
        const char* ver = llama_version();     // 形如 "b12540 (xxxxxxx)"
        g_backendVersion = std::string("llama.cpp ") + (ver ? ver : "unknown");
    }
    return 1;
}

void TRANSLATE_CALL Translate_Unload(void) {
    std::lock_guard<std::mutex> lock(g_mu);
    UnloadLocked();
    llama_backend_free();
}

void TRANSLATE_CALL Translate_Cancel(void) {
    g_cancel.store(true);
}

int TRANSLATE_CALL Translate_Run(const wchar_t* text, const wchar_t* target,
                                 const TranslateGlossaryItem* glossaryItems, int32_t glossaryCount,
                                 int32_t timeoutMs, wchar_t* out, int32_t outChars, TranslateStats* stats) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_lastError.clear();
    g_cancel.store(false);
    if (stats) std::memset(stats, 0, sizeof(TranslateStats));

    if (!out || outChars <= 1) {
        SetError("输出缓冲无效");
        return 0;
    }
    if (glossaryCount < 0 || glossaryCount > 4096 || (glossaryCount > 0 && !glossaryItems)) {
        SetError("术语表参数无效");
        return 0;
    }
    out[0] = L'\0';
    if (!g_model || !g_vocab) {
        SetError("模型未加载");
        return 0;
    }
    std::string src = Utf16ToUtf8(text);
    if (Trim(src).empty()) {
        SetError("源文本为空");
        return 0;
    }

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = static_cast<uint32_t>(g_opt.nCtx);
    cp.n_batch = static_cast<uint32_t>(g_opt.nBatch);
    cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;   // 后端支持就开，prefill/decode 都提速
    cp.n_threads = g_opt.nThreads > 0 ? g_opt.nThreads : 0;   // 0 = llama 自己按核数定
    cp.n_threads_batch = cp.n_threads;

    llama_context* ctx = llama_init_from_model(g_model, cp);
    if (!ctx) {
        SetError("推理上下文创建失败（内存不足？）");
        return 0;
    }

    int rc = 1;
    std::string generated;
    int64_t t0 = NowMs();
    const int32_t runTimeoutMs = timeoutMs > 0 ? timeoutMs : 30000;

    auto tokens_free = [&]() { llama_free(ctx); };

    // ---- tokenize ----
    std::string prompt = BuildPrompt(src, Utf16ToUtf8(target),
                                     glossaryItems, glossaryCount);
    const int n_max = static_cast<int>(prompt.size()) + 32;
    std::vector<llama_token> tokens(static_cast<size_t>(n_max));
    int n = llama_tokenize(g_vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                           tokens.data(), n_max, /*add_special=*/true, /*parse_special=*/true);
    if (n < 0) {
        tokens_free();
        SetError("文本分词失败");
        return 0;
    }
    tokens.resize(static_cast<size_t>(n));
    if (stats) stats->promptTokens = n;

    if (n >= g_opt.nCtx - 16) {
        tokens_free();
        SetError("文本过长，超过模型上下文（" + std::to_string(g_opt.nCtx) + " token）");
        return 0;
    }

    // ---- prefill ----
    {
        int32_t i = 0;
        while (i < n) {
            int32_t chunk = std::min<int32_t>(g_opt.nBatch, n - i);
            if (!DecodeChunk(ctx, tokens, i, chunk)) {
                tokens_free();
                SetError("prefill 失败");
                return 0;
            }
            i += chunk;
            if (g_cancel.load()) { rc = -1; break; }
        }
    }

    // ---- decode ----
    if (rc == 1) {
        llama_sampler* smpl = llama_sampler_init_greedy();   // 翻译要可复现：温度 0
        if (!smpl) {
            tokens_free();
            SetError("采样器创建失败");
            return 0;
        }
        int produced = 0;
        std::string piece;
        piece.resize(256);
        while (produced < g_opt.maxTokens) {
            if (g_cancel.load()) { rc = -1; break; }
            if (NowMs() - t0 > runTimeoutMs) {
                if (stats) stats->truncated = 1;
                break;
            }
            llama_token tok = llama_sampler_sample(smpl, ctx, -1);
            if (llama_vocab_is_eog(g_vocab, tok)) break;

            int32_t pn = llama_token_to_piece(g_vocab, tok, &piece[0], static_cast<int32_t>(piece.size()),
                                              /*lstrip=*/0, /*special=*/false);
            if (pn < 0) {
                piece.resize(static_cast<size_t>(-pn));
                pn = llama_token_to_piece(g_vocab, tok, &piece[0], static_cast<int32_t>(piece.size()), 0, false);
            }
            if (pn > 0) generated.append(piece.data(), static_cast<size_t>(pn));

            // 撞到角色标记就收工，没必要再让模型续写
            if (generated.find("<|im_end|>") != std::string::npos ||
                generated.find("<|im_start|>") != std::string::npos)
                break;

            std::vector<llama_token> one{tok};
            if (!DecodeChunk(ctx, one, 0, 1)) {
                rc = 0;
                SetError("decode 失败");
                break;
            }
            ++produced;
            if (stats) stats->outputTokens = produced;
        }
        llama_sampler_free(smpl);
        if (produced >= g_opt.maxTokens && stats) stats->truncated = 1;
    }

    tokens_free();
    if (stats) stats->elapsedMs = static_cast<int32_t>(NowMs() - t0);
    if (rc != 1) return rc;

    std::string result = CleanOutput(generated);
    if (result.empty()) {
        // 超时且一个 token 都没出来时，说「没有产出内容」会让人以为是模型问题
        if (stats && stats->truncated)
            return 1;
        SetError("模型没有产出内容");
        return 0;
    }
    std::wstring w = Utf8ToUtf16(result);
    int32_t cap = outChars - 1;
    if (static_cast<int32_t>(w.size()) > cap) {
        w.resize(static_cast<size_t>(cap));
        if (stats) stats->truncated = 1;
    }
    std::memcpy(out, w.c_str(), (w.size() + 1) * sizeof(wchar_t));
    return 1;
}
