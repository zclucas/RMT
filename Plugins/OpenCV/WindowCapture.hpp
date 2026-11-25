#pragma once

#define _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
#include <roapi.h>
#include <d3d11.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "windowsapp.lib")

// WGC reads the composed GPU surface, including emulator child swap chains.
// Sessions are cached per hwnd and reused across capture calls; the D3D device
// is created once per WindowCapture and survives hwnd changes. ReleaseAllCaches()
// closes all cached sessions before DLL teardown, outside the loader lock.
class WindowCapture {
    using Item = winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
    using Pool = winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
    using Session = winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
    using Device = winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
    HWND hwnd_ = nullptr;
    DWORD pid_ = 0;
    winrt::com_ptr<ID3D11Device> device_;
    winrt::com_ptr<ID3D11DeviceContext> context_;
    Device runtimeDevice_{ nullptr };
    Item item_{ nullptr };
    Pool pool_{ nullptr };
    Session session_{ nullptr };
    winrt::Windows::Graphics::SizeInt32 size_{};
    cv::Mat lastFull_;  // 最近一次成功抓到的整窗 BGRA 帧（静止窗口复用）

    void Close() noexcept {
        try { if (session_) session_.Close(); } catch (...) {}
        try { if (pool_) pool_.Close(); } catch (...) {}
        session_ = nullptr;
        pool_ = nullptr;
        item_ = nullptr;
        hwnd_ = nullptr;
        lastFull_.release();
    }

public:
    ~WindowCapture() { Close(); }

    // 缓存清理入口：关闭会话/帧池，保留 D3D 设备句柄随之析构
    void Shutdown() noexcept { Close(); }

    // 预热：建会话并取首帧。给后台线程用，让"冷启动"成本不占搜索调用的时间。
    bool Warm(HWND hwnd) {
        RECT rc{};
        if (!GetClientRect(hwnd, &rc) || rc.right <= rc.left || rc.bottom <= rc.top)
            return false;
        RECT roi{ 0, 0, rc.right - rc.left, rc.bottom - rc.top };
        return !Capture(hwnd, roi).empty();
    }

    cv::Mat Capture(HWND hwnd, const RECT& roi) {
        try {
            if (!Session::IsSupported()) return {};
            if (IsIconic(hwnd)) return {};
            DWORD pid = 0;
            GetWindowThreadProcessId(hwnd, &pid);
            if (!session_ || hwnd_ != hwnd || pid_ != pid) {
                Close();
                if (!device_) {
                    winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE,
                        nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                        D3D11_SDK_VERSION, device_.put(), nullptr, context_.put()));
                    auto dxgi = device_.as<IDXGIDevice>();
                    winrt::com_ptr<IInspectable> inspectable;
                    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
                    runtimeDevice_ = inspectable.as<Device>();
                }
                auto interop = winrt::get_activation_factory<Item, IGraphicsCaptureItemInterop>();
                winrt::check_hresult(interop->CreateForWindow(hwnd,
                    winrt::guid_of<Item>(), winrt::put_abi(item_)));
                size_ = item_.Size();
                pool_ = Pool::CreateFreeThreaded(runtimeDevice_,
                    winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UIntNormalized,
                    2, size_);
                session_ = pool_.CreateCaptureSession(item_);
                try { session_.IsCursorCaptureEnabled(false); } catch (...) {}
                // Win11：尝试关闭捕获黄框。不加 RequestAccessAsync(Borderless) 前置时
                // 部分系统会抛 E_INVALIDARG（被吞掉、黄框照旧），但绝不能在调用线程上
                // 同步 .get() 等它——AHK 主线程是 STA，没有消息泵，必死锁。
                try { session_.IsBorderRequired(false); } catch (...) {}
                session_.StartCapture();
                hwnd_ = hwnd;
                pid_ = pid;
            }

            // Free-threaded pool needs no UI message pump. Bound all frame waits.
            // 静止窗口不产新帧：有上一帧时只短等 10ms，等不到就复用上一帧——
            // 内容没变，上一帧就是当前画面；没有上一帧（首帧）最多等 250ms。
            const ULONGLONG deadline = GetTickCount64() + (lastFull_.empty() ? 250 : 10);
            do {
                auto frame = pool_.TryGetNextFrame();
                if (!frame) { Sleep(2); continue; }
                // Prefer the newest queued frame when the caller searches slowly.
                for (int i = 0; i < 2; ++i) {
                    auto newer = pool_.TryGetNextFrame();
                    if (!newer) break;
                    frame.Close();
                    frame = std::move(newer);
                }
                const auto content = frame.ContentSize();
                if (content.Width != size_.Width || content.Height != size_.Height) {
                    frame.Close();
                    lastFull_.release();
                    size_ = content;
                    if (size_.Width <= 0 || size_.Height <= 0) return {};
                    pool_.Recreate(runtimeDevice_,
                        winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UIntNormalized,
                        2, size_);
                    continue;
                }
                // 整帧读回缓存：静止窗口的后续调用不再依赖新帧
                auto access = frame.Surface().as<Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
                winrt::com_ptr<ID3D11Texture2D> texture;
                winrt::check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
                D3D11_TEXTURE2D_DESC desc{};
                texture->GetDesc(&desc);
                desc.Usage = D3D11_USAGE_STAGING;
                desc.BindFlags = 0;
                desc.MiscFlags = 0;
                desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                winrt::com_ptr<ID3D11Texture2D> staging;
                winrt::check_hresult(device_->CreateTexture2D(&desc, nullptr, staging.put()));
                context_->CopyResource(staging.get(), texture.get());
                D3D11_MAPPED_SUBRESOURCE mapped{};
                winrt::check_hresult(context_->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
                try {
                    lastFull_ = cv::Mat(static_cast<int>(desc.Height), static_cast<int>(desc.Width),
                        CV_8UC4, mapped.pData, mapped.RowPitch).clone();
                } catch (...) { context_->Unmap(staging.get(), 0); throw; }
                context_->Unmap(staging.get(), 0);
                frame.Close();
                break;
            } while (GetTickCount64() < deadline);

            if (lastFull_.empty())
                return {};

            // 几何校验放在取帧之后：静止窗口复用上一帧时窗口可能已被移动，
            // ROI 原点要用当前窗口位置重算。Never scale a frame to fit.
            RECT bounds{};
            if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                &bounds, sizeof(bounds)))) return {};
            if (bounds.right - bounds.left != lastFull_.cols || bounds.bottom - bounds.top != lastFull_.rows) {
                if (!GetWindowRect(hwnd, &bounds) || bounds.right - bounds.left != lastFull_.cols
                    || bounds.bottom - bounds.top != lastFull_.rows) return {};
            }
            POINT origin{};
            if (!ClientToScreen(hwnd, &origin)) return {};
            const int left = origin.x - bounds.left + roi.left;
            const int top = origin.y - bounds.top + roi.top;
            const int width = roi.right - roi.left, height = roi.bottom - roi.top;
            if (left < 0 || top < 0 || left + width > lastFull_.cols || top + height > lastFull_.rows)
                return {};
            return lastFull_(cv::Rect(left, top, width, height)).clone();
        } catch (...) {
            Close();
        }
        return {};
    }
};

// 进程级 MTA：会话跨调用存活时，若 RoInitialize/RoUninitialize 配对到零，
// MTA 会被拆掉、存活的 WinRT 对象可能失效，故只初始化一次、随进程结束回收。
static bool EnsureWinrtApartment() {
    static const HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    return SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
}

// 会话缓存：key = 目标窗口句柄。复用后单次抓取只剩整帧 Copy+Map。
// 会话跨宏调用常驻（LRU 上限封顶），冷启动成本由后台预热线程承担：
// 首次调用某窗口时本次走 DWM 兜底，同时开线程建会话取首帧，下次调用即为热缓存。
static std::mutex g_wgcCacheMutex;
static std::unordered_map<int, std::unique_ptr<WindowCapture>> g_wgcCache;
static std::unordered_set<int> g_wgcWarming;      // 预热中的 hwnd（防重复开线程）
static std::vector<int> g_wgcLru;                 // front=最旧，back=最新
constexpr size_t kWgcCacheCapacity = 6;

static void TouchWgcKey(int key) {
    for (auto it = g_wgcLru.begin(); it != g_wgcLru.end(); ++it)
        if (*it == key) { g_wgcLru.erase(it); break; }
    g_wgcLru.push_back(key);
}

static void EvictWgcIfNeeded() {
    while (g_wgcCache.size() > kWgcCacheCapacity && !g_wgcLru.empty()) {
        const int oldest = g_wgcLru.front();
        g_wgcLru.erase(g_wgcLru.begin());
        g_wgcCache.erase(oldest);
    }
}

static cv::Mat CaptureGpuWindow(HWND hwnd, const RECT& roi) {
    if (!hwnd || !IsWindow(hwnd) || !EnsureWinrtApartment())
        return {};

    std::lock_guard<std::mutex> lock(g_wgcCacheMutex);
    const int key = (int)(intptr_t)hwnd;
    auto it = g_wgcCache.find(key);
    if (it != g_wgcCache.end() && !IsWindow(hwnd)) {
        // 目标窗口已销毁，丢弃旧会话
        g_wgcCache.erase(it);
        it = g_wgcCache.end();
    }

    if (it == g_wgcCache.end()) {
        // 冷启动：本次调用不等待（交给 DWM 兜底），后台预热会话供后续复用
        if (g_wgcWarming.insert(key).second) {
            std::thread([hwnd, key]() {
                HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
                bool ok = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
                auto capture = ok ? std::make_unique<WindowCapture>() : nullptr;
                bool warmed = capture && capture->Warm(hwnd);
                std::lock_guard<std::mutex> lock2(g_wgcCacheMutex);
                g_wgcWarming.erase(key);
                if (warmed && IsWindow(hwnd)) {
                    g_wgcCache[key] = std::move(capture);
                    TouchWgcKey(key);
                    EvictWgcIfNeeded();
                }
            }).detach();
        }
        return {};
    }
    TouchWgcKey(key);
    return it->second->Capture(hwnd, roi);
}
