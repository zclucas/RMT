// =====================================================================
// VoiceDll.cpp — RMT 语音触发引擎封装
// 封装 sherpa-onnx KWS (sherpa-onnx-c-api.dll) + WASAPI 麦克风采集
// 导出简单 C 接口供 AHK DllCall 调用。
//
// 导出函数（参数均为宽字符 UTF-16，DLL 内转 UTF-8，避开 ANSI/GBK 乱码）：
//   int   Voice_Init(const wchar_t* encoder, const wchar_t* decoder,
//                     const wchar_t* joiner, const wchar_t* tokens)
//   int   Voice_SetKeywords(const wchar_t* keywords)   ; 纯汉字，| 分隔；内部 G2P 转拼音音素
//   int   Voice_SetKeywordsZh(const wchar_t* keywords) ; 同 SetKeywords（保留汉字语义名）
//   int   Voice_Start()
//   int   Voice_Stop()
//   int   Voice_GetTriggered(char* buf, int bufSize) ; 取一个命中的关键词
//   int   Voice_GetLastError(char* buf, int bufSize)
//   void  Voice_Close()
//   int   Voice_TestWav(const wchar_t* wavPath, char* out, int outSize)
//
// STT（离线语音转文字，sherpa-onnx OfflineRecognizer + paraformer）：
//   int   Stt_Init(const wchar_t* model, const wchar_t* tokens)
//   int   Stt_Begin()                        ; 开始录音（独立 WASAPI 实例，与 KWS 互不干扰）
//   int   Stt_End()                          ; 停止录音并异步解码
//   int   Stt_Cancel()                       ; 停止录音并丢弃（不解码）
//   int   Stt_GetState()                     ; 0空闲 1录音中 2解码中 3完成 4错误
//   int   Stt_GetResult(char* buf, int bufSize) ; 解码完成后取全文（UTF-8）
//   int   Stt_GetLastError(char* buf, int bufSize)
//   void  Stt_Close()
//   int   Stt_TestWav(const wchar_t* wavPath, char* out, int outSize)
//
// STT 流式（本地在线识别，sherpa-onnx OnlineRecognizer + zipformer2 CTC，不联网）：
//   int   SttStream_Init(const wchar_t* model, const wchar_t* tokens)
//   int   SttStream_Begin()                   ; 建流 + 起采集
//   int   SttStream_Poll(char* out, int outSize) ; 喂音频 + 增量解码 + 取当前文本（~150ms 调一次）
//   int   SttStream_End(int refine)           ; 收尾解码；refine!=0 时再交给离线识别器精修
//   int   SttStream_Cancel()
//   int   SttStream_GetState()                ; 0空闲 1录音中 2精修中 3完成 4错误
//   int   SttStream_GetResult(char* buf, int bufSize)
//   int   SttStream_GetLastError(char* buf, int bufSize)
//   void  SttStream_Close()
//   int   SttStream_TestWav(const wchar_t* wavPath, char* out, int outSize)
//
// 编译：MSVC x64 + 链接 sherpa-onnx-c-api.lib + WASAPI(winmm/ole32? no)
//       WASAPI 需要 avrt.lib 用于 MMCSS。COM CoInitializeEx + ole32.
// 依赖运行时：sherpa-onnx-c-api.dll + onnxruntime.dll 与最新 DLL 同目录。
// =====================================================================
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <combaseapi.h>

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <deque>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>
#include <algorithm>

#include "sherpa-onnx/c-api/c-api.h"

// ---- 汉字 -> 带声调拼音音素 内置映射表（生成物，勿手改） ----
#include "g2p_data.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "Avrt.lib")
#pragma comment(lib, "uuid.lib")

// ---------------------------------------------------------------------
// 编码辅助：宽字符 -> UTF-8 字节串（避开跨语言 ANSI/GBK 乱码）
// ---------------------------------------------------------------------
static std::string WToUtf8(const wchar_t* w) {
    if (!w) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return std::string();
    std::string out(n - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, &out[0], n, nullptr, nullptr);
    return out;
}

// ---------------------------------------------------------------------
// 汉字(码点) -> 带声调拼音音素串（G2P），二分查内置表。
// ---------------------------------------------------------------------
static const char* G2pLookup(unsigned int cp) {
    int lo = 0, hi = kG2pCount - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        unsigned int m = kG2pTable[mid].cp;
        if (m == cp) return kG2pTable[mid].phones;
        if (m < cp) lo = mid + 1; else hi = mid - 1;
    }
    return nullptr;
}

// ---------------------------------------------------------------------
// 线程安全 FIFO（存命中的关键词）
// ---------------------------------------------------------------------
class TriggerQueue {
public:
    void Push(const std::string& s) {
        std::lock_guard<std::mutex> lk(m_);
        if (q_.size() > 256) q_.pop_front();   // 上限防爆
        q_.push_back(s);
    }
    std::string Pop() {
        std::lock_guard<std::mutex> lk(m_);
        if (q_.empty()) return std::string();
        std::string s = q_.front();
        q_.pop_front();
        return s;
    }
private:
    std::mutex m_;
    std::deque<std::string> q_;
};

// ---------------------------------------------------------------------
// WASAPI 麦克风采集（16k 单声道 float）
// ---------------------------------------------------------------------
class WasapiCapture {
public:
    bool Start(int targetRate);
    void Stop();
    // 提取所有等待的采样（float, [-1,1]），供喂给 KWS。非阻塞。
    int PullSamples(std::vector<float>& out);

private:
    void CaptureLoop();
    std::atomic<bool> running_{false};
    std::thread thread_;
    IMMDevice* dev_ = nullptr;
    IAudioClient* client_ = nullptr;
    IAudioCaptureClient* capture_ = nullptr;
    int sampleRate_ = 16000;
    std::vector<float> pool_;       // 待消费采样缓冲
    std::mutex poolMx_;
    static UINT32 latencyFramesLocal;
};

bool WasapiCapture::Start(int targetRate) {
    sampleRate_ = targetRate;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE && hr != S_FALSE) {
        return false;
    }
    IMMDeviceEnumerator* enumerator = nullptr;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) return false;

    // 默认录音设备（麦克风）
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications, &dev_);
    if (FAILED(hr)) {
        // 回退：eConsole 类别
        hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &dev_);
    }
    enumerator->Release();
    if (FAILED(hr)) return false;

    hr = dev_->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&client_));
    if (FAILED(hr)) return false;

    WAVEFORMATEX* mixFmt = nullptr;
    hr = client_->GetMixFormat(&mixFmt);
    if (FAILED(hr)) return false;

    if (mixFmt->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        // 提取样本格式信息
        WAVEFORMATEXTENSIBLE* ext = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mixFmt);
        // 强制 16k 单声道 float —— 通过共享模式，系统自动重采样
    }

    // 构造请求格式：16k 单声道 float
    WAVEFORMATEX fmt;
    fmt.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    fmt.nChannels = 1;
    fmt.nSamplesPerSec = targetRate;
    fmt.wBitsPerSample = 32;
    fmt.nBlockAlign = (fmt.wBitsPerSample / 8) * fmt.nChannels;
    fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
    fmt.cbSize = 0;

    hr = client_->Initialize(AUDCLNT_SHAREMODE_SHARED,
                             AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
                             200000, 0, &fmt, nullptr);
    if (FAILED(hr)) return false;

    REFERENCE_TIME hnsLatency = 0;
    hr = client_->GetBufferSize(&latencyFramesLocal);
    if (FAILED(hr)) return false;

    hr = client_->GetService(IID_PPV_ARGS(&capture_));
    if (FAILED(hr)) return false;

    running_ = true;
    thread_ = std::thread(&WasapiCapture::CaptureLoop, this);
    return true;
}

UINT32 WasapiCapture::latencyFramesLocal = 0;

void WasapiCapture::Stop() {
    running_ = false;
    if (thread_.joinable()) thread_.join();
    if (capture_) { capture_->Release(); capture_ = nullptr; }
    if (client_) { client_->Stop(); client_->Release(); client_ = nullptr; }
    if (dev_) { dev_->Release(); dev_ = nullptr; }
}

void WasapiCapture::CaptureLoop() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    // MMCSS 提升采集优先级
    DWORD taskIndex = 0;
    HANDLE task = AvSetMmThreadCharacteristicsW(L"Audio", &taskIndex);
    client_->Start();

    UINT32 nFrames = 0;
    while (running_) {
        UINT32 packetLen = 0;
        int32_t outFlags = 0;
        // 兼容 VISTA: GetNextPacketSize
        {
            IAudioCaptureClient* cap = capture_;
            if (!cap) break;
        }
        // 循环取所有可用的数据包（非阻塞）
        while (capture_->GetNextPacketSize(&packetLen) == S_OK && packetLen != 0) {
            BYTE* data = nullptr;
            UINT32 framesAvail = 0;
            DWORD flags = 0;
            HRESULT hr = capture_->GetBuffer(&data, &framesAvail, &flags, nullptr, nullptr);
            if (FAILED(hr)) break;
            if (framesAvail > 0 && data) {
                const float* src = reinterpret_cast<const float*>(data);
                {
                    std::lock_guard<std::mutex> lk(poolMx_);
                    pool_.insert(pool_.end(), src, src + framesAvail);
                }
            }
            capture_->ReleaseBuffer(framesAvail);
        }
        Sleep(10);
    }
    AvRevertMmThreadCharacteristics(task);
    CoUninitialize();
}

int WasapiCapture::PullSamples(std::vector<float>& out) {
    std::lock_guard<std::mutex> lk(poolMx_);
    if (pool_.empty()) return 0;
    out.swap(pool_);
    return (int)out.size();
}

// ---------------------------------------------------------------------
// 全局引擎状态
// ---------------------------------------------------------------------
static TriggerQueue g_queue;
static std::mutex g_engineMx;
static const SherpaOnnxKeywordSpotter* g_spotter = nullptr;
static const SherpaOnnxOnlineStream* g_stream = nullptr;
static std::string g_lastError;
static std::atomic<bool> g_enabled{false};
static std::atomic<bool> g_needResetStream{false};
static WasapiCapture g_capture;
static std::thread g_workThread;
static std::atomic<bool> g_workRunning{false};

static std::string g_encoder, g_decoder, g_joiner, g_tokens;
static std::string g_kwSet;   // "|" 分隔的关键词原始集

// 注意：SetErr 必须在调用者已持有 g_engineMx 时调用（非递归锁）。
// 不要在这里内部再加锁，否则同线程重复 lock 一个 std::mutex 会未定义/崩溃。
static void SetErr(const std::string& s) {
    g_lastError = s;
}

// 解码 UTF-8 串开头的一个字符，返回其 Unicode 码点并推进 pos。
// 失败(非法/越界)返回 0。
static unsigned int DecodeUtf8(const std::string& s, size_t& pos) {
    if (pos >= s.size()) return 0;
    unsigned char c = (unsigned char)s[pos];
    unsigned int cp = 0; size_t n = 0;
    if (c < 0x80) { cp = c; n = 1; }
    else if ((c >> 5) == 0x6) { cp = c & 0x1F; n = 2; }
    else if ((c >> 4) == 0xE) { cp = c & 0x0F; n = 3; }
    else if ((c >> 3) == 0x1E) { cp = c & 0x07; n = 4; }
    else return 0;
    if (pos + n > s.size()) return 0;
    for (size_t k = 1; k < n; ++k) {
        unsigned char cc = (unsigned char)s[pos + k];
        if ((cc >> 6) != 0x2) return 0;
        cp = (cp << 6) | (cc & 0x3F);
    }
    pos += n;
    return cp;
}

// 把单个关键词（UTF-8 汉字串）转成 KWS 音素格式 "音素 @词"。
// 若关键词已含 '@'（用户已给 "n ǚ ér @女儿" 音素格式），原样返回。
// 中文逐字查 G2P 内置表；无法编码返回 ""。
static std::string KeywordToPhones(const std::string& kw) {
    if (kw.find('@') != std::string::npos) return kw;   // 已是完整音素格式
    std::string phones;
    size_t pos = 0;
    while (pos < kw.size()) {
        unsigned int cp = DecodeUtf8(kw, pos);
        if (cp == 0) return std::string();
        const char* ph = G2pLookup(cp);
        if (!ph) return std::string();
        if (!phones.empty()) phones += ' ';
        phones += ph;
    }
    if (phones.empty()) return std::string();
    // 格式：音素1 音素2 ... @词 （@ 前必须有空格，sherpa KWS 按空格切 token）
    return phones + " @" + kw;
}

// 把 "关键词列表"（| 分隔，如 "女儿|法国"）转成 KWS 音素格式
// "n ǚ ér @女儿|f ǎ g uó @法国"；sherpa KWS 只需音素空格串，@ 后为命中回显文本。
static std::string BuildKeywordText(const std::string& combined) {
    std::string out;
    size_t start = 0;
    bool first = true;
    while (true) {
        size_t pos = combined.find('|', start);
        std::string kw = combined.substr(start, pos == std::string::npos ? std::string::npos : pos - start);
        // 去首尾空白
        while (!kw.empty() && (kw.front()==' '||kw.front()=='\t'||kw.front()=='\r'||kw.front()=='\n')) kw.erase(0,1);
        while (!kw.empty() && (kw.back()==' '||kw.back()=='\t'||kw.back()=='\r'||kw.back()=='\n')) kw.pop_back();
        if (!kw.empty()) {
            std::string entry = KeywordToPhones(kw);
            if (entry.empty()) {   // 有词编码失败 -> 整体构建失败
                SetErr("关键词含无法识别的字符: " + kw);
                return std::string();
            }
            if (!first) out += '|';
            out += entry;
            first = false;
        }
        if (pos == std::string::npos) break;
        start = pos + 1;
    }
    return out;
}

// 重建 stream（改关键词或首次）
static bool RebuildStreamLocked() {
    if (!g_spotter) return false;
    if (g_stream) {
        SherpaOnnxDestroyOnlineStream(g_stream);
        g_stream = nullptr;
    }
    // WithKeywords 用 "/" 分隔多个关键词
    std::string sep;
    sep.reserve(g_kwSet.size());
    for (char ch : g_kwSet) sep += (ch == '|') ? '/' : ch;
    g_stream = SherpaOnnxCreateKeywordStreamWithKeywords(g_spotter, sep.c_str());
    if (!g_stream) {
        SetErr("创建 KWS 关键词流失败");
        return false;
    }
    // 清空采集缓冲，跳过旧音频
    std::vector<float> dummy;
    g_capture.PullSamples(dummy);
    return true;
}

// 工作线程：采集 + 喂 KWS + 检测
static void WorkLoop() {
    while (g_workRunning) {
        {
            std::lock_guard<std::mutex> lk(g_engineMx);
            // 关键词已变更：在采集线程侧重建 stream（不阻塞调用方，且与解码天然串行）
            if (g_needResetStream.exchange(false)) {
                if (!RebuildStreamLocked()) {
                    // SetErr 已在 RebuildStreamLocked 内设置
                }
            }
            if (g_enabled && g_spotter && g_stream) {
                std::vector<float> samples;
                int n = g_capture.PullSamples(samples);
                if (n > 0) {
                    SherpaOnnxOnlineStreamAcceptWaveform(g_stream, 16000, samples.data(), n);
                }
                // 一次喂完所有可解码的块
                while (SherpaOnnxIsKeywordStreamReady(g_spotter, g_stream)) {
                    SherpaOnnxDecodeKeywordStream(g_spotter, g_stream);
                    const SherpaOnnxKeywordResult* r = SherpaOnnxGetKeywordResult(g_spotter, g_stream);
                    if (r && r->keyword && strlen(r->keyword) > 0) {
                        g_queue.Push(r->keyword);
                        SherpaOnnxResetKeywordStream(g_spotter, g_stream);
                        // 丢弃 reset 后残留的音频缓冲
                        std::vector<float> discard;
                        g_capture.PullSamples(discard);
                    }
                    SherpaOnnxDestroyKeywordResult(r);
                }
            }
        }
        // 锁外 Sleep：缩短持锁窗口，降低与 SetKeywords/Stop 等调用的锁竞争
        std::this_thread::sleep_for(std::chrono::milliseconds(8));
    }
}

// ---------------------------------------------------------------------
// 导出接口
// ---------------------------------------------------------------------
extern "C" {

__declspec(dllexport) int Voice_Init(const wchar_t* encoder, const wchar_t* decoder,
                                     const wchar_t* joiner, const wchar_t* tokens) {
    std::lock_guard<std::mutex> lk(g_engineMx);
    if (g_spotter) {
        SherpaOnnxDestroyKeywordSpotter(g_spotter);
        g_spotter = nullptr;
    }
    g_encoder = WToUtf8(encoder);
    g_decoder = WToUtf8(decoder);
    g_joiner  = WToUtf8(joiner);
    g_tokens  = WToUtf8(tokens);

    if (g_encoder.empty() || g_decoder.empty() || g_joiner.empty() || g_tokens.empty()) {
        SetErr("模型路径不完整");
        return 0;
    }

    SherpaOnnxKeywordSpotterConfig c;
    memset(&c, 0, sizeof(c));
    c.feat_config.sample_rate = 16000;
    c.feat_config.feature_dim = 80;
    c.model_config.transducer.encoder = g_encoder.c_str();
    c.model_config.transducer.decoder = g_decoder.c_str();
    c.model_config.transducer.joiner  = g_joiner.c_str();
    c.model_config.tokens = g_tokens.c_str();
    c.model_config.provider = "cpu";
    c.model_config.num_threads = 2;
    c.model_config.modeling_unit = "cjkchar";
    c.max_active_paths = 4;
    c.num_trailing_blanks = 1;
    c.keywords_score = 1.0f;        // 与官方默认一致
    c.keywords_threshold = 0.25f;
    // Config 层必须提供非空 keywords_buf 占位（否则 Validate 失败）;
    // 真正的关键词由 CreateKeywordStreamWithKeywords 在每条流上提供。
    static const char placeholder[] = "b ei j ing @beijing";
    c.keywords_buf = placeholder;
    c.keywords_buf_size = (int32_t)(sizeof(placeholder) - 1);

    g_spotter = SherpaOnnxCreateKeywordSpotter(&c);
    fprintf(stderr, "[Voice] CreateKeywordSpotter => %p\n", (void*)g_spotter);
    if (!g_spotter) {
        SetErr("创建 KeywordSpotter 失败（模型加载失败）");
        return 0;
    }
    g_enabled = false;
    g_needResetStream = false;   // 全新初始化，清除挂起的重建标志
    SetErr("");
    fprintf(stderr, "[Voice] Voice_Init OK\n");
    return 1;
}

__declspec(dllexport) int Voice_SetKeywords(const wchar_t* keywords) {
    std::lock_guard<std::mutex> lk(g_engineMx);
    g_kwSet = WToUtf8(keywords);
    if (!g_spotter) return 0;
    if (g_kwSet.empty()) {
        g_enabled = false;
        if (g_stream) { SherpaOnnxDestroyOnlineStream(g_stream); g_stream = nullptr; }
        return 1;
    }
    // 转成 KWS 拼音音素分词格式（内部对纯汉字做 G2P）；Return 以 | 分隔，WithKeywords 用 /
    std::string spaced = BuildKeywordText(g_kwSet);
    if (spaced.empty()) return 0;   // 编码失败（BuildKeywordText 已 SetErr）
    g_kwSet = spaced;
    g_enabled = true;
    // 异步重建：只置标志立即返回（毫秒级重建交给 WorkLoop 在锁内执行），
    // 避免 AHK 主线程 DllCall 期间阻塞 GUI（G2P 转换本身极快，重建 stream 才耗时）。
    g_needResetStream = true;
    return 1;
}

// Voice_SetKeywordsZh：纯汉字语义接口（与 SetKeywords 同实现，BuildKeywordText 内置 G2P）。
// AHK 端用 WStr 传 UTF-16 汉字，DLL 内转 UTF-8 -> 查 G2P 表 -> 拼音音素。
__declspec(dllexport) int Voice_SetKeywordsZh(const wchar_t* keywords) {
    return Voice_SetKeywords(keywords);
}

__declspec(dllexport) int Voice_Start() {
    std::lock_guard<std::mutex> lk(g_engineMx);
    if (!g_spotter || !g_enabled) return 0;
    if (!g_capture.Start(16000)) {
        SetErr("麦克风采集启动失败");
        return 0;
    }
    if (!g_workRunning) {
        g_workRunning = true;
        g_workThread = std::thread(WorkLoop);
    }
    return 1;
}

__declspec(dllexport) int Voice_Stop() {
    {
        std::lock_guard<std::mutex> lk(g_engineMx);
        g_enabled = false;
    }
    if (g_workRunning) {
        g_workRunning = false;
        if (g_workThread.joinable()) g_workThread.join();
    }
    g_capture.Stop();
    return 1;
}

__declspec(dllexport) int Voice_GetTriggered(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    std::string s = g_queue.Pop();
    if (s.empty()) {
        buf[0] = '\0';
        return 0;
    }
    int n = std::min((int)s.size(), bufSize - 1);
    memcpy(buf, s.c_str(), n);
    buf[n] = '\0';
    return 1;
}

__declspec(dllexport) int Voice_GetLastError(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    std::lock_guard<std::mutex> lk(g_engineMx);
    int n = std::min((int)g_lastError.size(), bufSize - 1);
    memcpy(buf, g_lastError.c_str(), n);
    buf[n] = '\0';
    return g_lastError.empty() ? 0 : (int)g_lastError.size();
}

__declspec(dllexport) void Voice_Close() {
    Voice_Stop();
    std::lock_guard<std::mutex> lk(g_engineMx);
    if (g_stream) { SherpaOnnxDestroyOnlineStream(g_stream); g_stream = nullptr; }
    if (g_spotter) { SherpaOnnxDestroyKeywordSpotter(g_spotter); g_spotter = nullptr; }
}

// 离线测试：读取一个 wav 文件，喂给当前关键词语料判断是否命中。
// 供自动化验证使用（不依赖麦克风）。返回 0=无命中, 1=命中;
// 命中时把关键词拷贝到 out（编辑 256 字节）。
__declspec(dllexport) int Voice_TestWav(const wchar_t* wavPath, char* out, int outSize) {
    if (!wavPath || !out || outSize <= 0) return 0;
    out[0] = '\0';
    std::string wp = WToUtf8(wavPath);
    std::lock_guard<std::mutex> lk(g_engineMx);
    if (!g_spotter || !g_stream) return 0;

    const SherpaOnnxWave* wave = SherpaOnnxReadWave(wp.c_str());
    if (!wave) return 0;

    // 建一个独立 stream 用于本次测试（用当前关键词语料）
    std::string sep;
    for (char ch : g_kwSet) sep += (ch == '|') ? '/' : ch;
    const SherpaOnnxOnlineStream* s = SherpaOnnxCreateKeywordStreamWithKeywords(g_spotter, sep.c_str());

    int hit = 0;
    if (s) {
        // 按官方 keyword-spotter 循环：分块喂入，每块后解码到 ready 耗尽
        const int kChunk = 4000;   // 0.25 s @16k，与官方示例一致
        int readyCount = 0;
        size_t pos = 0;
        while (pos < (size_t)wave->num_samples) {
            int n = (int)std::min<size_t>((size_t)kChunk, (size_t)(wave->num_samples - pos));
            SherpaOnnxOnlineStreamAcceptWaveform(s, wave->sample_rate, wave->samples + pos, n);
            pos += n;
            while (SherpaOnnxIsKeywordStreamReady(g_spotter, s)) {
                ++readyCount;
                SherpaOnnxDecodeKeywordStream(g_spotter, s);
                const SherpaOnnxKeywordResult* r = SherpaOnnxGetKeywordResult(g_spotter, s);
                if (r && r->keyword && strlen(r->keyword) > 0) {
                    int len = std::min((int)strlen(r->keyword), outSize - 1);
                    memcpy(out, r->keyword, len);
                    out[len] = '\0';
                    hit = 1;
                }
                SherpaOnnxDestroyKeywordResult(r);
                if (hit) break;
            }
            if (hit) break;
        }
        fprintf(stderr, "[TestWav] fed=%d readyCount=%d hit=%d\n", wave->num_samples, readyCount, hit);
        SherpaOnnxDestroyOnlineStream(s);
    }
    SherpaOnnxFreeWave(wave);
    return hit;
}

// ---------------------------------------------------------------------
// STT（离线语音转文字）—— sherpa-onnx OfflineRecognizer + paraformer
// 独立于 KWS：单独的识别器 / 采集实例 / 错误串，状态机 0空闲→1录音→2解码→3完成/4错误。
// 解码在独立线程执行（Stt_End 立即返回），AHK 轮询 Stt_GetState 取结果。
// 注意：解码线程内绝不获取 g_sttMx（Stt_Init/Close 持锁 join 才不会死锁）。
// ---------------------------------------------------------------------
static std::mutex g_sttMx;
static const SherpaOnnxOfflineRecognizer* g_sttRec = nullptr;
static std::string g_sttModel, g_sttTokens;
static std::string g_sttError;
static std::string g_sttResult;
static WasapiCapture g_sttCapture;              // 独立采集实例（WASAPI 共享模式，与 KWS 并存）
static std::thread g_sttThread;
static std::atomic<int> g_sttState{0};          // 0空闲 1录音中 2解码中 3完成 4错误

static void SttSetErr(const std::string& s) { g_sttError = s; }

// 解码线程主体：一次性喂入全部采样并解码（不持锁；结果写回后再置状态保证可见性）
static void SttDecodeThread(const SherpaOnnxOfflineRecognizer* rec, std::vector<float> samples) {
    const SherpaOnnxOfflineStream* s = SherpaOnnxCreateOfflineStream(rec);
    if (!s) {
        SttSetErr("创建离线识别流失败");
        g_sttState = 4;
        return;
    }
    int32_t n = (int32_t)samples.size();
    if (n > 0)
        SherpaOnnxAcceptWaveformOffline(s, 16000, samples.data(), n);
    SherpaOnnxDecodeOfflineStream(rec, s);
    const SherpaOnnxOfflineRecognizerResult* r = SherpaOnnxGetOfflineStreamResult(s);
    if (!r) {
        SherpaOnnxDestroyOfflineStream(s);
        SttSetErr("离线解码失败");
        g_sttState = 4;
        return;
    }
    g_sttResult = (r->text ? r->text : "");
    SttSetErr("");
    SherpaOnnxDestroyOfflineRecognizerResult(r);
    SherpaOnnxDestroyOfflineStream(s);
    g_sttState = 3;
}

// 加载 paraformer 离线模型（model.int8.onnx + tokens.txt）
__declspec(dllexport) int Stt_Init(const wchar_t* model, const wchar_t* tokens) {
    std::lock_guard<std::mutex> lk(g_sttMx);
    g_sttModel  = WToUtf8(model);
    g_sttTokens = WToUtf8(tokens);
    if (g_sttModel.empty() || g_sttTokens.empty()) {
        SttSetErr("模型路径不完整");
        return 0;
    }
    // 若上一段还在解码，先等它落地（避免使用中的识别器被销毁）
    if (g_sttThread.joinable()) g_sttThread.join();
    if (g_sttRec) { SherpaOnnxDestroyOfflineRecognizer(g_sttRec); g_sttRec = nullptr; }
    SherpaOnnxOfflineRecognizerConfig c;
    memset(&c, 0, sizeof(c));
    c.feat_config.sample_rate = 16000;
    c.feat_config.feature_dim = 80;
    c.model_config.paraformer.model = g_sttModel.c_str();
    c.model_config.tokens = g_sttTokens.c_str();
    c.model_config.num_threads = 2;
    c.model_config.provider = "cpu";
    c.decoding_method = "greedy_search";   // paraformer 仅支持 greedy_search
    g_sttRec = SherpaOnnxCreateOfflineRecognizer(&c);
    fprintf(stderr, "[Stt] CreateOfflineRecognizer => %p\n", (void*)g_sttRec);
    if (!g_sttRec) {
        SttSetErr("创建离线识别器失败（模型加载失败）");
        return 0;
    }
    g_sttResult.clear();
    g_sttState = 0;
    SttSetErr("");
    return 1;
}

// 开始录音（丢弃采集缓冲中上一段的残留）
__declspec(dllexport) int Stt_Begin() {
    std::lock_guard<std::mutex> lk(g_sttMx);
    if (!g_sttRec) { SttSetErr("模型未加载"); return 0; }
    if (g_sttState == 1) return 1;
    if (g_sttState == 2) { SttSetErr("正在识别上一段录音，请稍候"); return 0; }
    std::vector<float> discard;
    g_sttCapture.PullSamples(discard);
    g_sttResult.clear();
    if (!g_sttCapture.Start(16000)) {
        SttSetErr("麦克风采集启动失败");
        return 0;
    }
    g_sttState = 1;
    return 1;
}

// 停止录音并异步开始解码（立即返回；轮询 Stt_GetState）
__declspec(dllexport) int Stt_End() {
    std::lock_guard<std::mutex> lk(g_sttMx);
    if (g_sttState != 1) return 0;
    g_sttCapture.Stop();
    std::vector<float> samples;
    g_sttCapture.PullSamples(samples);
    if (samples.empty()) {
        SttSetErr("未采集到音频");
        g_sttState = 0;
        return 0;
    }
    if (g_sttThread.joinable()) g_sttThread.join();
    g_sttState = 2;
    g_sttThread = std::thread(SttDecodeThread, g_sttRec, std::move(samples));
    return 1;
}

// 停止录音并丢弃（不解码）。解码中则不处理（返回 0，等它自然结束）。
__declspec(dllexport) int Stt_Cancel() {
    std::lock_guard<std::mutex> lk(g_sttMx);
    if (g_sttState != 1) return 0;
    g_sttCapture.Stop();
    std::vector<float> discard;
    g_sttCapture.PullSamples(discard);
    g_sttState = 0;
    return 1;
}

__declspec(dllexport) int Stt_GetState() {
    return g_sttState.load();
}

__declspec(dllexport) int Stt_GetResult(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    if (g_sttState != 3) { buf[0] = '\0'; return 0; }
    int n = std::min((int)g_sttResult.size(), bufSize - 1);
    memcpy(buf, g_sttResult.c_str(), n);
    buf[n] = '\0';
    return 1;
}

__declspec(dllexport) int Stt_GetLastError(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    int n = std::min((int)g_sttError.size(), bufSize - 1);
    memcpy(buf, g_sttError.c_str(), n);
    buf[n] = '\0';
    return g_sttError.empty() ? 0 : (int)g_sttError.size();
}

__declspec(dllexport) void Stt_Close() {
    std::lock_guard<std::mutex> lk(g_sttMx);
    if (g_sttState == 1) {
        g_sttCapture.Stop();
        std::vector<float> discard;
        g_sttCapture.PullSamples(discard);
        g_sttState = 0;
    }
    if (g_sttThread.joinable()) g_sttThread.join();
    if (g_sttRec) { SherpaOnnxDestroyOfflineRecognizer(g_sttRec); g_sttRec = nullptr; }
    g_sttResult.clear();
    SttSetErr("");
}

// 离线测试：读取一个 wav 文件做整段转写（自动化验证用，不依赖麦克风）
__declspec(dllexport) int Stt_TestWav(const wchar_t* wavPath, char* out, int outSize) {
    if (!wavPath || !out || outSize <= 0) return 0;
    out[0] = '\0';
    std::string wp = WToUtf8(wavPath);
    std::lock_guard<std::mutex> lk(g_sttMx);
    if (!g_sttRec) return 0;
    if (g_sttThread.joinable()) g_sttThread.join();
    const SherpaOnnxWave* wave = SherpaOnnxReadWave(wp.c_str());
    if (!wave) return 0;
    const SherpaOnnxOfflineStream* s = SherpaOnnxCreateOfflineStream(g_sttRec);
    int ok = 0;
    if (s) {
        SherpaOnnxAcceptWaveformOffline(s, wave->sample_rate, wave->samples, wave->num_samples);
        SherpaOnnxDecodeOfflineStream(g_sttRec, s);
        const SherpaOnnxOfflineRecognizerResult* r = SherpaOnnxGetOfflineStreamResult(s);
        if (r && r->text) {
            int len = std::min((int)strlen(r->text), outSize - 1);
            memcpy(out, r->text, len);
            out[len] = '\0';
            ok = 1;
        }
        if (r) SherpaOnnxDestroyOfflineRecognizerResult(r);
        SherpaOnnxDestroyOfflineStream(s);
    }
    SherpaOnnxFreeWave(wave);
    return ok;
}

// ---------------------------------------------------------------------
// STT 流式（本地在线识别）—— sherpa-onnx OnlineRecognizer + zipformer2 CTC
// 全程本地推理，不联网。与上面的离线 Stt_* 完全独立：独立识别器/采集实例/状态机。
// 流程：Begin 建流 + 起采集 → AHK 每 ~150ms 调 Poll（喂音频、增量解码、取当前文本）
//      → End 收尾解码；refine!=0 时把整段音频再交给离线 paraformer 精修（two-pass）
// 状态：0空闲 1录音中 2精修中 3完成 4错误
// 注意：精修线程内绝不获取 g_ssMx / g_sttMx，Init/Close 才 join。
// ---------------------------------------------------------------------
static std::mutex g_ssMx;
static const SherpaOnnxOnlineRecognizer* g_ssRec = nullptr;
static const SherpaOnnxOnlineStream* g_ssStream = nullptr;
static std::string g_ssModel, g_ssDec, g_ssJoin, g_ssTokens, g_ssBpe;
static std::string g_ssError;
static std::string g_ssResult;
static std::vector<float> g_ssSamples;      // 整段音频，供精修使用
static WasapiCapture g_ssCapture;           // 独立采集实例（与 KWS / 离线 STT 三者并存）
static std::thread g_ssThread;
static std::atomic<int> g_ssState{0};       // 0空闲 1录音中 2精修中 3完成 4错误

static void SsSetErr(const std::string& s) { g_ssError = s; }

static void DirOfUtf8(const std::string& p, std::string& outDir) {
    size_t pos = p.find_last_of("\\/");
    outDir = (pos == std::string::npos) ? std::string() : p.substr(0, pos);
}

static bool FileExistsUtf8(const std::string& p) {
    if (p.empty()) return false;
    DWORD a = GetFileAttributesA(p.c_str());
    return (a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY));
}

// 自动识别 BPE 词表：tokens.txt 同目录下的 bpe.model / bbpe.model
// （x-asr transducer 用 bpe.model；部分 zipformer2 CTC 用 bbpe.model）
static bool SsDetectBpe(const std::string& tokensPath, std::string& outVocab) {
    std::string dir;
    DirOfUtf8(tokensPath, dir);
    if (dir.empty()) return false;
    for (const char* name : {"bpe.model", "bbpe.model"}) {
        std::string cand = dir + "\\" + name;
        if (FileExistsUtf8(cand)) { outVocab = cand; return true; }
    }
    return false;
}

// 取当前累积文本（结果对象用完即释放）。用出参避免 extern "C" 返回 std::string（C4190）
static void SsTakeText(std::string& outText) {
    outText.clear();
    if (!g_ssRec || !g_ssStream) return;
    const SherpaOnnxOnlineRecognizerResult* r = SherpaOnnxGetOnlineStreamResult(g_ssRec, g_ssStream);
    if (!r) return;
    outText = (r->text ? r->text : "");
    SherpaOnnxDestroyOnlineRecognizerResult(r);
}

// 把就绪的 chunk 全部解码
static void SsDrain() {
    if (!g_ssRec || !g_ssStream) return;
    while (SherpaOnnxIsOnlineStreamReady(g_ssRec, g_ssStream))
        SherpaOnnxDecodeOnlineStream(g_ssRec, g_ssStream);
}

// 精修线程：用离线识别器重识别整段（two-pass 的第二遍）
static void SsRefineThread(std::vector<float> samples) {
    // 直接读 g_sttRec（离线识别器），不持任何锁，避免与 Init/Close 死锁
    if (g_sttRec) {
        const SherpaOnnxOfflineStream* s = SherpaOnnxCreateOfflineStream(g_sttRec);
        if (s) {
            if (!samples.empty())
                SherpaOnnxAcceptWaveformOffline(s, 16000, samples.data(), (int32_t)samples.size());
            SherpaOnnxDecodeOfflineStream(g_sttRec, s);
            const SherpaOnnxOfflineRecognizerResult* r = SherpaOnnxGetOfflineStreamResult(s);
            if (r && r->text && strlen(r->text) > 0)
                g_ssResult = r->text;
            if (r) SherpaOnnxDestroyOfflineRecognizerResult(r);
            SherpaOnnxDestroyOfflineStream(s);
        }
    }
    g_ssState = 3;
}

// 加载流式模型。两种形态按参数自动判定：
//   · transducer：encoder + decoder + joiner 均非空（如 x-asr zipformer2 transducer）
//   · zipformer2 CTC：decoder/joiner 为空，encoder 即单个 onnx 模型路径
__declspec(dllexport) int SttStream_Init(const wchar_t* encoder, const wchar_t* decoder,
                                        const wchar_t* joiner, const wchar_t* tokens) {
    std::lock_guard<std::mutex> lk(g_ssMx);
    g_ssModel  = WToUtf8(encoder);
    g_ssDec    = WToUtf8(decoder ? decoder : L"");
    g_ssJoin   = WToUtf8(joiner  ? joiner  : L"");
    g_ssTokens = WToUtf8(tokens);
    if (g_ssModel.empty() || g_ssTokens.empty()) {
        SsSetErr("流式模型路径不完整");
        return 0;
    }
    bool isTransducer = (!g_ssDec.empty() && !g_ssJoin.empty());
    if (g_ssThread.joinable()) g_ssThread.join();
    if (g_ssStream) { SherpaOnnxDestroyOnlineStream(g_ssStream); g_ssStream = nullptr; }
    if (g_ssRec)    { SherpaOnnxDestroyOnlineRecognizer(g_ssRec); g_ssRec = nullptr; }
    SherpaOnnxOnlineRecognizerConfig c;
    memset(&c, 0, sizeof(c));
    c.feat_config.sample_rate = 16000;
    c.feat_config.feature_dim = 80;
    if (isTransducer) {
        c.model_config.transducer.encoder = g_ssModel.c_str();
        c.model_config.transducer.decoder = g_ssDec.c_str();
        c.model_config.transducer.joiner  = g_ssJoin.c_str();
    } else {
        c.model_config.zipformer2_ctc.model = g_ssModel.c_str();
    }
    c.model_config.tokens   = g_ssTokens.c_str();
    c.model_config.num_threads = 2;
    c.model_config.provider = "cpu";
    // 检测到 BPE 词表就显式启用（否则会按 cjkchar 解 tokens，输出乱码）；
    // model_type 留空 → 由 sherpa 依据模型元数据自动判定
    if (SsDetectBpe(g_ssTokens, g_ssBpe)) {
        c.model_config.modeling_unit = "bpe";
        c.model_config.bpe_vocab = g_ssBpe.c_str();
        fprintf(stderr, "[SttStream] modeling_unit=bpe, bpe_vocab=%s\n", g_ssBpe.c_str());
    }
    c.decoding_method  = "greedy_search";
    c.max_active_paths = 4;
    c.enable_endpoint  = 0;                 // 由 AHK 手动控制起止，不做自动断句
    g_ssRec = SherpaOnnxCreateOnlineRecognizer(&c);
    fprintf(stderr, "[SttStream] CreateOnlineRecognizer(%s) => %p\n",
            isTransducer ? "transducer" : "zipformer2_ctc", (void*)g_ssRec);
    if (!g_ssRec) {
        SsSetErr("创建流式识别器失败（模型加载失败）");
        return 0;
    }
    g_ssResult.clear();
    g_ssSamples.clear();
    g_ssState = 0;
    SsSetErr("");
    return 1;
}

// 建流 + 起采集
__declspec(dllexport) int SttStream_Begin() {
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (!g_ssRec) { SsSetErr("流式模型未加载"); return 0; }
    if (g_ssState == 1) return 1;
    if (g_ssState == 2) { SsSetErr("正在精修上一段，请稍候"); return 0; }
    if (g_ssThread.joinable()) g_ssThread.join();
    if (g_ssStream) { SherpaOnnxDestroyOnlineStream(g_ssStream); g_ssStream = nullptr; }
    g_ssStream = SherpaOnnxCreateOnlineStream(g_ssRec);
    if (!g_ssStream) { SsSetErr("创建流式识别流失败"); return 0; }
    std::vector<float> discard;
    g_ssCapture.PullSamples(discard);
    g_ssSamples.clear();
    g_ssResult.clear();
    if (!g_ssCapture.Start(16000)) {
        SherpaOnnxDestroyOnlineStream(g_ssStream);
        g_ssStream = nullptr;
        SsSetErr("麦克风采集启动失败");
        return 0;
    }
    g_ssState = 1;
    SsSetErr("");
    return 1;
}

// 录音中轮询：喂入新采集到的音频 → 增量解码 → 回写当前文本
__declspec(dllexport) int SttStream_Poll(char* out, int outSize) {
    if (!out || outSize <= 0) return 0;
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (g_ssState != 1 || !g_ssRec || !g_ssStream) { out[0] = '\0'; return 0; }
    std::vector<float> chunk;
    g_ssCapture.PullSamples(chunk);
    if (!chunk.empty()) {
        SherpaOnnxOnlineStreamAcceptWaveform(g_ssStream, 16000, chunk.data(), (int32_t)chunk.size());
        g_ssSamples.insert(g_ssSamples.end(), chunk.begin(), chunk.end());
    }
    SsDrain();
    SsTakeText(g_ssResult);
    int n = std::min((int)g_ssResult.size(), outSize - 1);
    memcpy(out, g_ssResult.c_str(), n);
    out[n] = '\0';
    return 1;
}

// 停止录音并收尾；refine!=0 且离线模型已加载时，异步精修
__declspec(dllexport) int SttStream_End(int refine) {
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (g_ssState != 1 || !g_ssRec || !g_ssStream) return 0;
    g_ssCapture.Stop();
    std::vector<float> tail;
    g_ssCapture.PullSamples(tail);
    if (!tail.empty()) {
        SherpaOnnxOnlineStreamAcceptWaveform(g_ssStream, 16000, tail.data(), (int32_t)tail.size());
        g_ssSamples.insert(g_ssSamples.end(), tail.begin(), tail.end());
    }
    SherpaOnnxOnlineStreamInputFinished(g_ssStream);
    SsDrain();
    SsTakeText(g_ssResult);
    if (g_ssSamples.empty()) {
        SsSetErr("未采集到音频");
        g_ssState = 0;
        return 0;
    }
    if (refine && g_sttRec) {
        if (g_ssThread.joinable()) g_ssThread.join();
        g_ssState = 2;
        g_ssThread = std::thread(SsRefineThread, g_ssSamples);
    } else {
        g_ssState = 3;
    }
    return 1;
}

// 停止并丢弃
__declspec(dllexport) int SttStream_Cancel() {
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (g_ssState != 1) return 0;
    g_ssCapture.Stop();
    std::vector<float> discard;
    g_ssCapture.PullSamples(discard);
    g_ssSamples.clear();
    g_ssResult.clear();
    g_ssState = 0;
    return 1;
}

__declspec(dllexport) int SttStream_GetState() {
    return g_ssState.load();
}

__declspec(dllexport) int SttStream_GetResult(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    if (g_ssState != 3 && g_ssState != 1) { buf[0] = '\0'; return 0; }
    int n = std::min((int)g_ssResult.size(), bufSize - 1);
    memcpy(buf, g_ssResult.c_str(), n);
    buf[n] = '\0';
    return 1;
}

__declspec(dllexport) int SttStream_GetLastError(char* buf, int bufSize) {
    if (!buf || bufSize <= 0) return 0;
    int n = std::min((int)g_ssError.size(), bufSize - 1);
    memcpy(buf, g_ssError.c_str(), n);
    buf[n] = '\0';
    return g_ssError.empty() ? 0 : (int)g_ssError.size();
}

__declspec(dllexport) void SttStream_Close() {
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (g_ssState == 1) {
        g_ssCapture.Stop();
        std::vector<float> discard;
        g_ssCapture.PullSamples(discard);
        g_ssState = 0;
    }
    if (g_ssThread.joinable()) g_ssThread.join();
    if (g_ssStream) { SherpaOnnxDestroyOnlineStream(g_ssStream); g_ssStream = nullptr; }
    if (g_ssRec)    { SherpaOnnxDestroyOnlineRecognizer(g_ssRec); g_ssRec = nullptr; }
    g_ssResult.clear();
    g_ssSamples.clear();
    SsSetErr("");
}

// 离线验证：按 100ms 分片喂 wav，模拟实时上屏，最终返回全文（不依赖麦克风）
__declspec(dllexport) int SttStream_TestWav(const wchar_t* wavPath, char* out, int outSize) {
    if (!wavPath || !out || outSize <= 0) return 0;
    out[0] = '\0';
    std::string wp = WToUtf8(wavPath);
    std::lock_guard<std::mutex> lk(g_ssMx);
    if (!g_ssRec) return 0;
    const SherpaOnnxWave* wave = SherpaOnnxReadWave(wp.c_str());
    if (!wave || !wave->samples || wave->num_samples <= 0) {
        if (wave) SherpaOnnxFreeWave(wave);
        return 0;
    }
    const SherpaOnnxOnlineStream* s = SherpaOnnxCreateOnlineStream(g_ssRec);
    if (!s) { SherpaOnnxFreeWave(wave); return 0; }

    const int32_t chunk = (wave->sample_rate > 0 ? wave->sample_rate : 16000) / 10; // 100ms
    int32_t pos = 0;
    while (pos < wave->num_samples) {
        int32_t n = std::min(chunk, wave->num_samples - pos);
        SherpaOnnxOnlineStreamAcceptWaveform(s, wave->sample_rate, wave->samples + pos, n);
        pos += n;
        while (SherpaOnnxIsOnlineStreamReady(g_ssRec, s))
            SherpaOnnxDecodeOnlineStream(g_ssRec, s);
        const SherpaOnnxOnlineRecognizerResult* r = SherpaOnnxGetOnlineStreamResult(g_ssRec, s);
        if (r) {
            fprintf(stderr, "[SttStream] %.2fs => %s\n",
                    (double)pos / (double)wave->sample_rate, r->text ? r->text : "");
            SherpaOnnxDestroyOnlineRecognizerResult(r);
        }
    }
    SherpaOnnxOnlineStreamInputFinished(s);
    while (SherpaOnnxIsOnlineStreamReady(g_ssRec, s))
        SherpaOnnxDecodeOnlineStream(g_ssRec, s);

    int ok = 0;
    const SherpaOnnxOnlineRecognizerResult* r = SherpaOnnxGetOnlineStreamResult(g_ssRec, s);
    if (r && r->text) {
        int len = std::min((int)strlen(r->text), outSize - 1);
        memcpy(out, r->text, len);
        out[len] = '\0';
        ok = 1;
    }
    if (r) SherpaOnnxDestroyOnlineRecognizerResult(r);
    SherpaOnnxDestroyOnlineStream(s);
    SherpaOnnxFreeWave(wave);
    return ok;
}

} // extern "C"