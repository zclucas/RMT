// windows.h 默认把 min/max 定义成宏，会破坏 std::min/std::max（报 C2589）
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "RMT_OpenCv.h"
#include <opencv2/opencv.hpp>
#include <windows.h>
#include <dwmapi.h>
#include <unordered_map>
#include <algorithm>
#include <cmath>
#include <climits>
#include <vector>
#include <string>
#include <memory>
#include <mutex>
#include <cstdarg>
#include <iostream>
#include <cstdio>
#include <cwchar>
#include <cstdlib>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <limits>
#include "WindowCapture.h"
#include "SearchAll.h"
#pragma comment(lib, "Dwmapi.lib")

// 兜底：某些 SDK/config 仍会在别处引入 min/max 宏
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

// 缩略图缓存结构
struct ThumbnailCache {
    HWND dstWin = nullptr;
    HTHUMBNAIL thumbnail = nullptr;
    SIZE sourceSize = { 0, 0 };
};

// 全局缓存：key = 目标窗口句柄
static std::unordered_map<int, ThumbnailCache> g_thumbnailCache;

// 捕获屏幕指定区域的函数
cv::Mat captureScreen(int x, int y, int width, int height)
{
	HDC hDesktopDC = GetDC(NULL);
	HDC hCaptureDC = CreateCompatibleDC(hDesktopDC);
	HBITMAP hBitmap = CreateCompatibleBitmap(hDesktopDC, width, height);
	HGDIOBJ oldBitmap = SelectObject(hCaptureDC, hBitmap);

	BitBlt(hCaptureDC, 0, 0, width, height, hDesktopDC, x, y, SRCCOPY | CAPTUREBLT);

	BITMAPINFOHEADER bi;
	bi.biSize = sizeof(BITMAPINFOHEADER);
	bi.biWidth = width;
	bi.biHeight = -height;  // 负值表示从上到下扫描
	bi.biPlanes = 1;
	bi.biBitCount = 32;
	bi.biCompression = BI_RGB;
	bi.biSizeImage = 0;
	bi.biXPelsPerMeter = 0;
	bi.biYPelsPerMeter = 0;
	bi.biClrUsed = 0;
	bi.biClrImportant = 0;

	cv::Mat mat(height, width, CV_8UC4);
	SelectObject(hCaptureDC, oldBitmap);
	if (GetDIBits(hCaptureDC, hBitmap, 0, height, mat.data, (BITMAPINFO*)&bi, DIB_RGB_COLORS) != height)
		mat.release();

	DeleteObject(hBitmap);
	DeleteDC(hCaptureDC);
	ReleaseDC(NULL, hDesktopDC);
	//测试：保存为PNG文件
	/*if (!mat.empty()) {
		cv::imwrite("screenshot.png", mat);
	}*/
	return mat;
}

// 获取或创建缩略图缓存（内部辅助函数）
static ThumbnailCache* GetOrCreateCache(HWND targetHwnd) {
    int key = (int)(intptr_t)targetHwnd;

    auto it = g_thumbnailCache.find(key);
    if (it != g_thumbnailCache.end()) {
        // 目标窗口已销毁，清理旧缓存重新创建
        if (!IsWindow(targetHwnd)) {
            if (it->second.thumbnail) DwmUnregisterThumbnail(it->second.thumbnail);
            if (it->second.dstWin) DestroyWindow(it->second.dstWin);
            g_thumbnailCache.erase(it);
        } else {
            return &it->second;
        }
    }

    // 创建新缓存
    const int screenX = GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    const int screenY = GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN);

    HWND dstWin = CreateWindowExW(
        WS_EX_TOOLWINDOW, L"STATIC", L"", WS_POPUP,
        screenX, screenY, 10, 10,
        nullptr, nullptr, nullptr, nullptr
    );
    if (!dstWin) return nullptr;

    HTHUMBNAIL thumbnail = nullptr;
    HRESULT hr = DwmRegisterThumbnail(dstWin, targetHwnd, &thumbnail);
    if (FAILED(hr)) {
        DestroyWindow(dstWin);
        return nullptr;
    }

    SIZE size = { 0 };
    hr = DwmQueryThumbnailSourceSize(thumbnail, &size);
    if (FAILED(hr)) {
        DwmUnregisterThumbnail(thumbnail);
        DestroyWindow(dstWin);
        return nullptr;
    }

    SetWindowPos(dstWin, nullptr, 0, 0, size.cx, size.cy,
        SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOZORDER);
    ShowWindow(dstWin, SW_SHOW);

    ThumbnailCache cache;
    cache.dstWin = dstWin;
    cache.thumbnail = thumbnail;
    cache.sourceSize = size;
    g_thumbnailCache[key] = std::move(cache);
    return &g_thumbnailCache[key];
}

// 获取窗口菜单栏高度（物理像素，无菜单栏返回 0）。
// DWM 缩略图开启 SOURCECLIENTAREAONLY 时，其“客户区”仍包含菜单栏区域，
// 而 AHK 侧 ScreenToClient 客户区坐标从菜单栏下方算起，二者相差一个菜单栏高度。
// 不补偿的话，带菜单栏的窗口（如 Everything）会把菜单栏算进截图，产生垂直偏移。
static int GetMenuBarHeight(HWND hwnd) {
    if (!GetMenu(hwnd))
        return 0;
    MENUBARINFO mbi = { sizeof(MENUBARINFO) };
    if (GetMenuBarInfo(hwnd, OBJID_MENU, 0, &mbi) && mbi.rcBar.bottom > mbi.rcBar.top)
        return mbi.rcBar.bottom - mbi.rcBar.top;
    // GetMenuBarInfo 可能因目标窗口以管理员运行而失败，回退系统标准菜单栏高度
    return GetSystemMetrics(SM_CYMENU);
}

// 后台截图（使用缓存，避免每次创建/销毁窗口）
cv::Mat captureScreen(int hwnd, int x, int y, int width, int height) {
    HWND targetHwnd = (HWND)(intptr_t)hwnd;
    if (!targetHwnd || !IsWindow(targetHwnd))
        return cv::Mat();

    // 客户区尺寸：缩略图源/目的都用客户区，与 AHK 侧 ScreenToClient 客户区坐标严格 1:1。
    // 目的若仍用整窗尺寸，客户区内容会被拉伸到整窗大小，造成残差偏移（#266 只修了裁剪区域，没修目的尺寸）。
    RECT clientRect;
    if (!GetClientRect(targetHwnd, &clientRect))
        return cv::Mat();
    const long clientW = clientRect.right - clientRect.left;
    const long clientH = clientRect.bottom - clientRect.top;
    if (clientW <= 0 || clientH <= 0)
        return cv::Mat();

    // Invalid/partially outside ROIs must not silently return the full client image.
    const long capWidth = width <= 0 ? clientW : width;
    const long capHeight = height <= 0 ? clientH : height;
    if (x < 0 || y < 0 || capWidth > clientW || capHeight > clientH
        || x > clientW - capWidth || y > clientH - capHeight)
        return cv::Mat();
    const RECT roi{ x, y, x + capWidth, y + capHeight };
    cv::Mat gpu = CaptureGpuWindow(targetHwnd, roi);
    if (!gpu.empty()) return gpu;

    // Retain the previous DWM path for unsupported systems and minimized windows.
    ThumbnailCache* cache = GetOrCreateCache(targetHwnd);
    if (!cache) return cv::Mat();
    HWND dstWin = cache->dstWin;
    HTHUMBNAIL thumbnail = cache->thumbnail;

    // 菜单栏高度补偿：DWM 客户区含菜单栏，AHK 客户区不含，源区域需从菜单栏下方开始
    const int menuH = GetMenuBarHeight(targetHwnd);

    // IsIconic 时 DWM 缩略图有内部偏移，需要补偿
    const int offset = IsIconic(targetHwnd) ? 8 : 0;

    SetWindowPos(dstWin, nullptr, 0, 0, clientW, clientH,
        SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOZORDER);

    DWM_THUMBNAIL_PROPERTIES props{};
    props.dwFlags = DWM_TNP_RECTSOURCE | DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE |
        DWM_TNP_SOURCECLIENTAREAONLY | DWM_TNP_OPACITY;
    // 客户区抓取，与 AHK 侧客户区坐标系一致，避免标题栏/边框算进截图
    props.fSourceClientAreaOnly = TRUE;
    props.fVisible = TRUE;
    props.opacity = 255;
    // 源区域跳过菜单栏：rcSource 为 DWM 客户区坐标（含菜单栏），从 menuH 处开始取 clientH 高
    props.rcSource = RECT{ 0, menuH, clientW, menuH + clientH };
    props.rcDestination = RECT{ -offset, -offset, clientW - offset, clientH - offset };

    HRESULT hr = DwmUpdateThumbnailProperties(thumbnail, &props);
    if (FAILED(hr)) return cv::Mat();

    // PrintWindow 截取映射窗口
    HDC hDC = GetWindowDC(nullptr);
    HDC cDC = CreateCompatibleDC(hDC);
    HBITMAP cBmp = CreateCompatibleBitmap(hDC, clientW, clientH);
    HGDIOBJ oldBmp = SelectObject(cDC, cBmp);

    cv::Mat result;
    BOOL bret = PrintWindow(dstWin, cDC, PW_RENDERFULLCONTENT);

    if (bret) {
        result = cv::Mat(clientH, clientW, CV_8UC4);
        BITMAPINFO bi = { 0 };
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = clientW;
        bi.bmiHeader.biHeight = -(LONG)clientH;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;

        SelectObject(cDC, oldBmp);
        if (GetDIBits(cDC, cBmp, 0, clientH, result.data, &bi, DIB_RGB_COLORS) != clientH)
            result.release();

        // 裁剪指定区域
        if (!result.empty()) {
            result = result(cv::Rect(x, y, capWidth, capHeight)).clone();
        }
    }

    SelectObject(cDC, oldBmp);
    DeleteObject(cBmp);
    DeleteDC(cDC);
    ReleaseDC(nullptr, hDC);
    return result;
}

// 计算两个矩形的交并比（IOU）
double computeIOU(const cv::Rect& rect1, const cv::Rect& rect2)
{
	// 计算交集区域
	cv::Rect intersection = rect1 & rect2;
	if (intersection.empty())
		return 0.0;

	double interArea = intersection.area();
	double unionArea = rect1.area() + rect2.area() - interArea;
	return interArea / unionArea;
}

// 非极大值抑制（NMS）算法
std::vector<cv::Rect> nonMaximumSuppression(const std::vector<cv::Rect>& rects,
	const std::vector<float>& scores,
	double scoreThreshold,
	double iouThreshold)
{
	std::vector<int> indices;
	for (int i = 0; i < scores.size(); ++i)
	{
		if (scores[i] >= scoreThreshold)
		{
			indices.push_back(i);
		}
	}

	// 按匹配分数降序排序
	std::sort(indices.begin(), indices.end(), [&](int a, int b) {
		return scores[a] > scores[b];
		});

	std::vector<bool> suppressed(indices.size(), false);
	std::vector<cv::Rect> selected;

	for (int i = 0; i < indices.size(); ++i)
	{
		if (suppressed[i])
			continue;

		int current = indices[i];
		selected.push_back(rects[current]);

		for (int j = i + 1; j < indices.size(); ++j)
		{
			if (suppressed[j])
				continue;

			int next = indices[j];
			if (computeIOU(rects[current], rects[next]) > iouThreshold)
			{
				suppressed[j] = true;
			}
		}
	}

	return selected;
}

extern "C" IMAGEFINDER_API void* __cdecl CaptureWinMat(int hwnd, int x, int y, int width, int height) {
	cv::Mat src = captureScreen(hwnd, x, y, width, height);

	if (src.empty()) {
		return nullptr;
	}

	cv::Mat* mat = new cv::Mat();

	// ⭐ 强制转 BGR（3通道）
	if (src.channels() == 4) {
		cv::cvtColor(src, *mat, cv::COLOR_BGRA2BGR);
	}
	else {
		*mat = src.clone();
	}

	// ⭐ 确保连续
	if (!mat->isContinuous()) {
		*mat = mat->clone();
	}

	return mat;
}

// 和CaptureWinMat做对比测试的导出函数
extern "C" IMAGEFINDER_API void* __cdecl CaptureScreenMat(int x, int y, int width, int height) {
	cv::Mat src = captureScreen(x, y, width, height);

	if (src.empty()) {
		return nullptr;
	}

	cv::Mat* mat = new cv::Mat();

	if (src.channels() == 4) {
		cv::cvtColor(src, *mat, cv::COLOR_BGRA2BGR);
	}
	else {
		*mat = src.clone();
	}

	if (!mat->isContinuous()) {
		*mat = mat->clone();
	}

	return mat;
}

extern "C" IMAGEFINDER_API void __cdecl ReleaseMat(void* matPtr)
{
	if (matPtr) {
		cv::Mat* mat = (cv::Mat*)matPtr;
		delete mat;
	}
}

extern "C" IMAGEFINDER_API int __cdecl SampleBuildEdgeMap(
	const unsigned char* scan, int stride, int width, int height, int alphaAware,
	unsigned char* pixels, unsigned char* directions, int* edgeCount,
	uint64_t* mass)
{
	if (!scan || !pixels || !directions || !edgeCount || !mass
		|| width <= 0 || height <= 0)
		return 0;

	const size_t w = static_cast<size_t>(width);
	const size_t h = static_cast<size_t>(height);
	if (w > std::numeric_limits<size_t>::max() / h)
		return 0;
	const size_t count = w * h;
	const long long strideMagnitude = stride < 0
		? -static_cast<long long>(stride) : static_cast<long long>(stride);
	if (strideMagnitude < static_cast<long long>(width) * 4)
		return 0;

	std::memset(pixels, 0, count);
	std::memset(directions, 0, count);
	*edgeCount = 0;
	*mass = 0;

	try
	{
		std::vector<unsigned char> gray(count, 0);
		std::vector<unsigned char> valid(alphaAware ? count : 0, 0);
		std::vector<unsigned short> raw(count, 0);
		int maxEdge = 0;

		for (int y = 0; y < height; ++y)
		{
			const unsigned char* row = scan
				+ static_cast<ptrdiff_t>(y) * stride;
			const size_t rowOffset = static_cast<size_t>(y) * w;
			for (int x = 0; x < width; ++x)
			{
				uint32_t value = 0;
				std::memcpy(&value, row + static_cast<size_t>(x) * 4, 4);
				const size_t index = rowOffset + static_cast<size_t>(x);
				gray[index] = static_cast<unsigned char>(
					((((value >> 16) & 255) * 77
						+ ((value >> 8) & 255) * 150
						+ (value & 255) * 29) >> 8));
				if (alphaAware)
					valid[index] = static_cast<unsigned char>((value >> 24) >= 128);
			}
		}

		for (int y = 1; y < height - 1; ++y)
		{
			for (int x = 1; x < width - 1; ++x)
			{
				const size_t index = static_cast<size_t>(y) * w
					+ static_cast<size_t>(x);
				if (alphaAware
					&& (!valid[index] || !valid[index - 1] || !valid[index + 1]
						|| !valid[index - w] || !valid[index + w]))
					continue;

				const int dx = static_cast<int>(gray[index + 1])
					- static_cast<int>(gray[index - 1]);
				const int dy = static_cast<int>(gray[index + w])
					- static_cast<int>(gray[index - w]);
				const int gx = std::abs(dx);
				const int gy = std::abs(dy);
				const int edge = gx + gy;
				int orientation = 0;
				if (gx * 2 < gy)
					orientation = 2;
				else if (gy * 2 < gx)
					orientation = 0;
				else
					orientation = dx * dy >= 0 ? 1 : 3;
				const int polarity = (orientation == 0 ? dx < 0
					: orientation == 2 ? dy < 0 : dx < 0) ? 1 : 0;
				raw[index] = static_cast<unsigned short>(edge);
				directions[index] = static_cast<unsigned char>(
					orientation * 2 + polarity);
				maxEdge = std::max(maxEdge, edge);
			}
		}

		const double cutoff = std::max(6.0, maxEdge * 0.08);
		if (maxEdge > cutoff)
		{
			for (int y = 1; y < height - 1; ++y)
			{
				const size_t rowOffset = static_cast<size_t>(y) * w;
				for (int x = 1; x < width - 1; ++x)
				{
					const size_t index = rowOffset + static_cast<size_t>(x);
					const unsigned short edge = raw[index];
					if (edge > cutoff)
					{
						const int value = std::min(255, static_cast<int>(
							std::lround((edge - cutoff) * 255.0
								/ (maxEdge - cutoff))));
						pixels[index] = static_cast<unsigned char>(value);
						++(*edgeCount);
						*mass += static_cast<uint64_t>(value);
					}
				}
			}
		}
		return 1;
	}
	catch (...)
	{
		std::memset(pixels, 0, count);
		std::memset(directions, 0, count);
		*edgeCount = 0;
		*mass = 0;
		return 0;
	}
}

namespace
{
	struct SampleEdgeCandidate
	{
		int ox;
		int oy;
		double score;
		double coverage;
		double texture;
		int anchorVotes = 0;
		double anchorMargin = 0.0;
	};

	static void InsertSampleCandidate(
		std::vector<SampleEdgeCandidate>& candidates,
		const SampleEdgeCandidate& candidate,
		int radius,
		int limit)
	{
		for (auto it = candidates.begin(); it != candidates.end(); ++it)
		{
			if (std::max(std::abs(candidate.ox - it->ox),
				std::abs(candidate.oy - it->oy)) > radius)
				continue;
			if (candidate.score > it->score
				|| (candidate.score == it->score
					&& std::abs(candidate.ox) + std::abs(candidate.oy)
						>= std::abs(it->ox) + std::abs(it->oy)))
			{
				if (candidate.anchorVotes > it->anchorVotes)
				{
					it->anchorVotes = candidate.anchorVotes;
					it->anchorMargin = candidate.anchorMargin;
				}
				return;
			}
			SampleEdgeCandidate replacement = candidate;
			if (it->anchorVotes > replacement.anchorVotes)
			{
				replacement.anchorVotes = it->anchorVotes;
				replacement.anchorMargin = it->anchorMargin;
			}
			candidates.erase(it);
			const int distance = std::abs(replacement.ox) + std::abs(replacement.oy);
			auto position = candidates.begin();
			while (position != candidates.end()
				&& (position->score < replacement.score
					|| (position->score == replacement.score
						&& std::abs(position->ox) + std::abs(position->oy) <= distance)))
				++position;
			const auto index = static_cast<int>(position - candidates.begin());
			if (index < limit)
			{
				candidates.insert(position, replacement);
				if (static_cast<int>(candidates.size()) > limit)
					candidates.pop_back();
			}
			return;
			break;
		}

		const int distance = std::abs(candidate.ox) + std::abs(candidate.oy);
		auto position = candidates.begin();
		while (position != candidates.end()
			&& (position->score < candidate.score
				|| (position->score == candidate.score
					&& std::abs(position->ox) + std::abs(position->oy) <= distance)))
			++position;
		const auto index = static_cast<int>(position - candidates.begin());
		if (index < limit)
		{
			candidates.insert(position, candidate);
			if (static_cast<int>(candidates.size()) > limit)
				candidates.pop_back();
		}
	}

	static void WriteSampleCandidate(double* output, int index,
		const SampleEdgeCandidate& candidate)
	{
		double* row = output + static_cast<size_t>(index) * 5;
		row[0] = static_cast<double>(candidate.ox);
		row[1] = static_cast<double>(candidate.oy);
		row[2] = candidate.score;
		row[3] = candidate.coverage;
		row[4] = candidate.texture;
	}

	static void WriteAnchorCandidate(double* output, int index,
		const SampleEdgeCandidate& candidate)
	{
		double* row = output + static_cast<size_t>(index) * 8;
		row[0] = static_cast<double>(candidate.ox);
		row[1] = static_cast<double>(candidate.oy);
		row[2] = candidate.score;
		row[3] = candidate.coverage;
		row[4] = candidate.anchorMargin;
		row[5] = candidate.texture;
		row[6] = static_cast<double>(candidate.anchorVotes);
		row[7] = candidate.anchorMargin;
	}
}

static int SampleAlignEdgeOffsetsImpl(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	const unsigned char* weights, double* output, int capacity, int* outputCount)
{
	if (!pixelsB || !directionsB || !pixelsS || !directionsS || !weights
		|| !output || !outputCount || bw < 4 || bh < 4 || sw < 4 || sh < 4
		|| capacity <= 0)
		return 0;

	*outputCount = 0;
	const int maxDimension = std::max(std::max(bw, bh), std::max(sw, sh));
	const int step = std::max(1, (maxDimension + 23) / 24);
	const int offsetStep = std::max(1, (maxDimension + 31) / 32);
	const int minArea = (std::min(bw * bh, sw * sh) + 1) / 2;
	std::vector<SampleEdgeCandidate> candidates;
	candidates.reserve(static_cast<size_t>(capacity));

	for (int oy = -(sh - 4); oy <= bh - 4; oy += offsetStep)
	{
		for (int ox = -(sw - 4); ox <= bw - 4; ox += offsetStep)
		{
			const int x0 = std::max(1, ox);
			const int x1 = std::min(bw - 1, ox + sw - 1);
			const int y0 = std::max(1, oy);
			const int y1 = std::min(bh - 1, oy + sh - 1);
			if ((x1 - x0) * (y1 - y0) < minArea)
				continue;

			int massB = 0;
			int massS = 0;
			double shared = 0.0;
			for (int y = y0; y < y1; y += step)
			{
				for (int x = x0; x < x1; x += step)
				{
					const int idxB = y * bw + x;
					const int idxS = (y - oy) * sw + x - ox;
					const unsigned char va = pixelsB[idxB];
					const unsigned char vb = pixelsS[idxS];
					massB += va;
					massS += vb;
					if (va && vb)
					{
						const int weightIndex = directionsB[idxB] * 8 + directionsS[idxS];
						shared += std::min(va, vb) * weights[weightIndex] * 0.5;
					}
				}
			}

			const int minMass = std::min(massB, massS);
			if (minMass < 24)
				continue;
			const double coverage = shared / minMass;
			const double purity = (2.0 * shared) / std::max(1, massB + massS);
			const double score = 1.0 - (coverage * 0.7 + purity * 0.3);
			const double texture = static_cast<double>(minMass)
				/ ((x1 - x0) * (y1 - y0));
			if (coverage >= 0.2)
				InsertSampleCandidate(candidates,
					{ ox, oy, score, coverage, texture },
					std::max(2, step), capacity);
		}
	}

	for (int i = 0; i < static_cast<int>(candidates.size()); ++i)
		WriteSampleCandidate(output, i, candidates[static_cast<size_t>(i)]);
	*outputCount = static_cast<int>(candidates.size());
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl SampleAlignEdgeOffsets(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	const unsigned char* weights, double* output, int capacity, int* outputCount)
{
	if (!outputCount)
		return 0;
	*outputCount = 0;
	try
	{
		return SampleAlignEdgeOffsetsImpl(pixelsB, directionsB, bw, bh,
			pixelsS, directionsS, sw, sh, weights, output, capacity, outputCount);
	}
	catch (...)
	{
		*outputCount = 0;
		return 0;
	}
}

static int SampleMatchEdgeAnchorsImpl(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	const unsigned char* weights, double* output, int capacity, int* outputCount)
{
	if (!pixelsB || !directionsB || !pixelsS || !directionsS || !weights
		|| !output || !outputCount || bw <= 0 || bh <= 0 || sw <= 0 || sh <= 0
		|| capacity <= 0)
		return 0;

	*outputCount = 0;
	const int minDimension = std::min(std::min(bw, bh), std::min(sw, sh));
	const bool sampleLargerThanBase =
		static_cast<long long>(sw) * sh > static_cast<long long>(bw) * bh;
	const int patchSide = minDimension <= 40 || sampleLargerThanBase
		? std::min(10, std::max(4, minDimension / 3))
		: std::min(8, std::max(4, minDimension / 5));
	if (std::min(std::min(bw, bh), std::min(sw, sh)) <= patchSide + 2)
		return 1;
	const int patchArea = patchSide * patchSide;
	const int minPatchMass = std::max(24, patchArea * 2);
	const int anchorStep = std::max(1, patchSide / 3);

	auto buildIntegral = [](const unsigned char* pixels, int width, int height) {
		const int stride = width + 1;
		std::vector<uint32_t> sums(static_cast<size_t>(stride) * (height + 1), 0);
		for (int y = 0; y < height; ++y)
		{
			uint32_t mass = 0;
			for (int x = 0; x < width; ++x)
			{
				mass += pixels[y * width + x];
				sums[static_cast<size_t>(y + 1) * stride + x + 1] =
					mass + sums[static_cast<size_t>(y) * stride + x + 1];
			}
		}
		return sums;
	};
	const std::vector<uint32_t> massB = buildIntegral(pixelsB, bw, bh);
	const std::vector<uint32_t> massSums = buildIntegral(pixelsS, sw, sh);
	auto patchMass = [patchSide](const std::vector<uint32_t>& sums, int width, int x, int y) {
		const int stride = width + 1;
		const size_t top = static_cast<size_t>(y) * stride + x;
		const size_t bottom = static_cast<size_t>(y + patchSide) * stride + x + patchSide;
		return sums[bottom] - sums[static_cast<size_t>(y) * stride + x + patchSide]
			- sums[static_cast<size_t>(y + patchSide) * stride + x] + sums[top];
	};

	struct RankedAnchor
	{
		int x;
		int y;
		int mass;
	};
	std::vector<RankedAnchor> ranked;
	ranked.reserve(48);
	for (int y = 1; y + patchSide < bh; y += anchorStep)
	{
		for (int x = 1; x + patchSide < bw; x += anchorStep)
		{
			const int mass = static_cast<int>(patchMass(massB, bw, x, y));
			if (mass < minPatchMass)
				continue;
			auto position = ranked.begin();
			while (position != ranked.end() && position->mass >= mass)
				++position;
			const int index = static_cast<int>(position - ranked.begin());
			if (index <= 48)
			{
				ranked.insert(position, { x, y, mass });
				if (ranked.size() > 48)
					ranked.pop_back();
			}
		}
	}

	std::vector<RankedAnchor> anchors;
	const int spacing = std::max(3, patchSide / 2);
	for (const RankedAnchor& anchor : ranked)
	{
		bool separated = true;
		for (const RankedAnchor& selected : anchors)
			if (std::max(std::abs(anchor.x - selected.x),
				std::abs(anchor.y - selected.y)) < spacing)
			{
				separated = false;
				break;
			}
		if (separated)
		{
			anchors.push_back(anchor);
			if (anchors.size() >= 8)
				break;
		}
	}

	struct AnchorVote
	{
		int ox;
		int oy;
		double score;
		double coverage;
		double margin;
		double texture;
	};
	std::vector<AnchorVote> votes;
	for (const RankedAnchor& anchor : anchors)
	{
		struct EdgePoint
		{
			int sampleIndex;
			unsigned char value;
			unsigned char directionIndex;
		};
		std::vector<EdgePoint> points;
		points.reserve(static_cast<size_t>(patchArea));
		for (int py = 0; py < patchSide; ++py)
			for (int px = 0; px < patchSide; ++px)
			{
				const int idxB = (anchor.y + py) * bw + anchor.x + px;
				const unsigned char value = pixelsB[idxB];
				if (value)
					points.push_back({ py * sw + px, value,
						static_cast<unsigned char>(directionsB[idxB] * 8) });
			}

		std::vector<SampleEdgeCandidate> matches;
		matches.reserve(3);
		for (int y = 1; y + patchSide < sh; ++y)
			for (int x = 1; x + patchSide < sw; ++x)
			{
				const int massS = static_cast<int>(patchMass(massSums, sw, x, y));
				const int minMass = std::min(anchor.mass, massS);
				if (minMass < minPatchMass)
					continue;
				double shared = 0.0;
				const int origin = y * sw + x;
				for (const EdgePoint& point : points)
				{
					const int idxS = origin + point.sampleIndex;
					const unsigned char valueS = pixelsS[idxS];
					if (valueS)
						shared += std::min(point.value, valueS)
							* weights[point.directionIndex + directionsS[idxS]] * 0.5;
				}
				const double coverage = shared / minMass;
				const double purity = (2.0 * shared) / std::max(1, anchor.mass + massS);
				const double score = 1.0 - (coverage * 0.7 + purity * 0.3);
				if (coverage >= 0.35)
					InsertSampleCandidate(matches,
						{ x, y, score, coverage, 0.0 },
						std::max(2, patchSide / 3), 3);
			}

		if (matches.empty())
			continue;
		const SampleEdgeCandidate& best = matches[0];
		const double margin = matches.size() > 1
			? matches[1].score - best.score : 1.0e15;
		if (best.score <= 0.65 && best.coverage >= 0.4
			&& margin >= std::max(0.015, best.score * 0.08))
			votes.push_back({ anchor.x - best.ox, anchor.y - best.oy, best.score,
				best.coverage, margin, static_cast<double>(anchor.mass) / patchArea });
	}

	struct VoteCluster
	{
		AnchorVote anchor;
		std::vector<AnchorVote> items;
	};
	std::vector<VoteCluster> clusters;
	for (const AnchorVote& vote : votes)
	{
		auto target = clusters.end();
		for (auto it = clusters.begin(); it != clusters.end(); ++it)
			if (std::abs(vote.ox - it->anchor.ox) <= 2
				&& std::abs(vote.oy - it->anchor.oy) <= 2)
			{
				target = it;
				break;
			}
		if (target != clusters.end())
			target->items.push_back(vote);
		else
			clusters.push_back({ vote, { vote } });
	}

	std::vector<SampleEdgeCandidate> candidates;
	candidates.reserve(static_cast<size_t>(capacity));
	for (const VoteCluster& cluster : clusters)
	{
		const int itemCount = static_cast<int>(cluster.items.size());
		double score = 0.0, coverage = 0.0, margin = 0.0, texture = 0.0;
		double sumX = 0.0, sumY = 0.0;
		for (const AnchorVote& vote : cluster.items)
		{
			score += vote.score;
			coverage += vote.coverage;
			margin += vote.margin;
			texture += vote.texture;
			sumX += vote.ox;
			sumY += vote.oy;
		}
		score /= itemCount;
		coverage /= itemCount;
		margin /= itemCount;
		texture /= itemCount;
		if ((itemCount >= 2 || (score <= 0.25 && coverage >= 0.75 && margin >= 0.12))
			&& coverage >= 0.4)
		{
			SampleEdgeCandidate candidate = {
				static_cast<int>(std::round(sumX / itemCount)),
				static_cast<int>(std::round(sumY / itemCount)),
				score, coverage, texture, itemCount, margin
			};
			InsertSampleCandidate(candidates, candidate, 2, capacity);
		}
	}

	for (int i = 0; i < static_cast<int>(candidates.size()); ++i)
		WriteAnchorCandidate(output, i, candidates[static_cast<size_t>(i)]);
	*outputCount = static_cast<int>(candidates.size());
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl SampleMatchEdgeAnchors(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	const unsigned char* weights, double* output, int capacity, int* outputCount)
{
	if (!outputCount)
		return 0;
	*outputCount = 0;
	try
	{
		return SampleMatchEdgeAnchorsImpl(pixelsB, directionsB, bw, bh,
			pixelsS, directionsS, sw, sh, weights, output, capacity, outputCount);
	}
	catch (...)
	{
		*outputCount = 0;
		return 0;
	}
}

static int SampleRefineEdgeOffsetImpl(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	int ox0, int oy0, int radius, const unsigned char* weights, double* output)
{
	if (!pixelsB || !directionsB || !pixelsS || !directionsS || !weights || !output
		|| bw <= 0 || bh <= 0 || sw <= 0 || sh <= 0 || radius < 0)
		return -1;

	const int left = std::max(0, ox0);
	const int right = std::min(bw, ox0 + sw);
	const int top = std::max(0, oy0);
	const int bottom = std::min(bh, oy0 + sh);
	if (right - left < 8 || bottom - top < 8)
		return 0;

	const int blockW = std::min(120, right - left - radius * 2);
	const int blockH = std::min(120, bottom - top - radius * 2);
	if (blockW < 8 || blockH < 8)
		return 0;
	int bx = left + (right - left - blockW) / 2;
	int by = top + (bottom - top - blockH) / 2;
	const int pixelStep = std::max(1, (std::max(blockW, blockH) + 31) / 32);
	const int sampleTotal = ((blockW + pixelStep - 1) / pixelStep)
		* ((blockH + pixelStep - 1) / pixelStep);
	const int xCandidates[3] = { bx, left + radius, right - blockW - radius };
	const int yCandidates[3] = { by, top + radius, bottom - blockH - radius };
	const double minMassRequired = std::max(24.0, sampleTotal * 0.2);
	double bestBlockScore = 1.0e15;
	for (int yi = 0; yi < 3; ++yi)
		for (int xi = 0; xi < 3; ++xi)
		{
			const int testX = xCandidates[xi];
			const int testY = yCandidates[yi];
			int massTestB = 0;
			int massTestS = 0;
			double sharedTest = 0.0;
			for (int yy = 0; yy < blockH; yy += pixelStep)
				for (int xx = 0; xx < blockW; xx += pixelStep)
				{
					const int idxB = (testY + yy) * bw + testX + xx;
					const int idxS = (testY - oy0) * sw + testX - ox0 + yy * sw + xx;
					const unsigned char va = pixelsB[idxB];
					const unsigned char vb = pixelsS[idxS];
					massTestB += va;
					massTestS += vb;
					if (va && vb)
					{
						const int weightIndex = directionsB[idxB] * 8 + directionsS[idxS];
						sharedTest += std::min(va, vb) * weights[weightIndex] * 0.5;
					}
				}
			const int minMassTest = std::min(massTestB, massTestS);
			if (minMassTest < minMassRequired)
				continue;
			const double coverageTest = sharedTest / minMassTest;
			if (coverageTest < 0.25)
				continue;
			const double purityTest = (2.0 * sharedTest) / std::max(1, massTestB + massTestS);
			const double scoreTest = 1.0 - (coverageTest * 0.7 + purityTest * 0.3);
			if (scoreTest < bestBlockScore)
			{
				bestBlockScore = scoreTest;
				bx = testX;
				by = testY;
			}
		}

	struct EdgePoint
	{
		int sampleIndex;
		unsigned char value;
		unsigned char directionIndex;
	};
	std::vector<EdgePoint> points;
	points.reserve(static_cast<size_t>(sampleTotal));
	int massB = 0;
	for (int yy = 0; yy < blockH; yy += pixelStep)
	{
		for (int xx = 0; xx < blockW; xx += pixelStep)
		{
			const int idxB = (by + yy) * bw + bx + xx;
			const unsigned char value = pixelsB[idxB];
			points.push_back({ yy * sw + xx, value,
				static_cast<unsigned char>(directionsB[idxB] * 8) });
			massB += value;
		}
	}

	double bestScore = 1.0e15;
	int bestOx = ox0;
	int bestOy = oy0;
	double bestCoverage = 0.0;
	double bestTexture = 0.0;
	bool found = false;
	for (int dy = -radius; dy <= radius; ++dy)
	{
		for (int dx = -radius; dx <= radius; ++dx)
		{
			const int ox = ox0 + dx;
			const int oy = oy0 + dy;
			int massS = 0;
			double shared = 0.0;
			const int origin = (by - oy) * sw + bx - ox;
			bool valid = true;
			for (const EdgePoint& point : points)
			{
				const int idxS = origin + point.sampleIndex;
				if (idxS < 0 || idxS >= sw * sh)
				{
					valid = false;
					break;
				}
				const unsigned char vb = pixelsS[idxS];
				massS += vb;
				if (point.value && vb)
				{
					const int weightIndex = point.directionIndex + directionsS[idxS];
					shared += std::min(point.value, vb) * weights[weightIndex] * 0.5;
				}
			}
			if (!valid)
				return -1;
			const int minMass = std::min(massB, massS);
			if (minMass < minMassRequired)
				continue;
			const double coverage = shared / minMass;
			const double purity = (2.0 * shared) / std::max(1, massB + massS);
			const double score = 1.0 - (coverage * 0.7 + purity * 0.3);
			const double texture = static_cast<double>(minMass) / sampleTotal;
			if (coverage >= 0.25 && (score < bestScore
				|| (score == bestScore
					&& std::abs(dx) + std::abs(dy)
						< std::abs(bestOx - ox0) + std::abs(bestOy - oy0))))
			{
				bestScore = score;
				bestOx = ox;
				bestOy = oy;
				bestCoverage = coverage;
				bestTexture = texture;
				found = true;
			}
		}
	}

	if (!found)
		return 0;
	output[0] = static_cast<double>(bestOx);
	output[1] = static_cast<double>(bestOy);
	output[2] = bestScore;
	output[3] = bestCoverage;
	output[4] = bestTexture;
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl SampleRefineEdgeOffset(
	const unsigned char* pixelsB, const unsigned char* directionsB, int bw, int bh,
	const unsigned char* pixelsS, const unsigned char* directionsS, int sw, int sh,
	int ox0, int oy0, int radius, const unsigned char* weights, double* output)
{
	try
	{
		return SampleRefineEdgeOffsetImpl(pixelsB, directionsB, bw, bh,
			pixelsS, directionsS, sw, sh, ox0, oy0, radius, weights, output);
	}
	catch (...)
	{
		return -1;
	}
}

// 释放所有缩略图缓存（搜图结束或切换时调用）
extern "C" IMAGEFINDER_API void __cdecl ReleaseAllCaches(void)
{
	for (auto& pair : g_thumbnailCache) {
		if (pair.second.thumbnail)
			DwmUnregisterThumbnail(pair.second.thumbnail);
		if (pair.second.dstWin)
			DestroyWindow(pair.second.dstWin);
	}
	g_thumbnailCache.clear();
}

// 保存Mat到文件
extern "C" IMAGEFINDER_API int __cdecl SaveMatToFile(void* matPtr, const char* filePath) {
	if (!matPtr || !filePath)
		return 0;

	cv::Mat* mat = (cv::Mat*)matPtr;
	if (mat->empty())
		return 0;

	try {
		return cv::imwrite(filePath, *mat) ? 1 : 0;
	}
	catch (...) {
		return 0;
	}
}

extern "C" IMAGEFINDER_API int __cdecl FindWinColor(
	const char* colorStr,
	int hwndInt,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	int* x,
	int* y)
{
	if (!colorStr || strlen(colorStr) != 6) {
		return 0;
	}

	// 限制 0~100
	if (matchThreshold < 0) matchThreshold = 0;
	if (matchThreshold > 100) matchThreshold = 100;

	// ⭐ 相似度 → 通道容差
	int tol = (int)((1.0 - matchThreshold / 100.0) * 255);

	// 解析 RRGGBB
	int r = 0, g = 0, b = 0;
	sscanf_s(colorStr, "%02x%02x%02x", &r, &g, &b);

	// 1️ 截图
	cv::Mat img = captureScreen(hwndInt, searchX, searchY, searchW, searchH);
	if (img.empty()) return 0;

	// 转 BGR
	if (img.channels() == 4) {
		cv::cvtColor(img, img, cv::COLOR_BGRA2BGR);
	}

	// 2️ 构造颜色范围
	cv::Scalar lower(
		std::max(0, b - tol),
		std::max(0, g - tol),
		std::max(0, r - tol)
	);

	cv::Scalar upper(
		std::min(255, b + tol),
		std::min(255, g + tol),
		std::min(255, r + tol)
	);

	// 3️ inRange 匹配
	cv::Mat mask;
	cv::inRange(img, lower, upper, mask);


	// 4️ 找第一个匹配点（最快方式）
	for (int row = 0; row < mask.rows; row++)
	{
		uchar* ptr = mask.ptr<uchar>(row);
		for (int col = 0; col < mask.cols; col++)
		{
			if (ptr[col] != 0)
			{
				*x = searchX + col;
				*y = searchY + row;
				return 1;
			}
		}
	}


	// 4️ 使用 findNonZero 获取点
	/*std::vector<cv::Point> points;
	cv::findNonZero(mask, points);

	if (!points.empty()) {
		*x = searchX + points[0].x;
		*y = searchY + points[0].y;
		return 1;
	}*/

	return 0;
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImage(
	const char* targetPath,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	int* x,
	int* y)
{
	if (matchThreshold > 100)
		matchThreshold = 100;
	else if (matchThreshold < 0)
		matchThreshold = 0;
	// 匹配分数阈值
	double scoreThreshold = matchThreshold / 100.0;

	// 1. 加载模板图像
	cv::Mat templateImage = cv::imread(targetPath, cv::IMREAD_UNCHANGED);
	if (templateImage.empty())
	{
		std::cerr << "Could not open or find the template image." << std::endl;
		return 0;
	}

	// 截取屏幕区域
	cv::Mat capturedImage = captureScreen(searchX, searchY, searchW, searchH);
	if (capturedImage.empty())
	{
		std::cerr << "Failed to capture screen region." << std::endl;
		return 0;
	}

	// 通道数不一致时统一（4 通道 PNG 模板 + 3 通道截屏）。
	if (templateImage.channels() != capturedImage.channels())
	{
		if (templateImage.channels() == 4 && capturedImage.channels() == 3)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGRA2BGR);
		else if (templateImage.channels() == 3 && capturedImage.channels() == 4)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGR2BGRA);
	}

	// 2. 转换为灰度图（提高处理速度）
	cv::Mat grayLarge, graySmall;
	// 旧接口固定灰度；颜色匹配由 Ex 接口的独立参数控制。
	cv::cvtColor(capturedImage, grayLarge, cv::COLOR_BGR2GRAY);
	cv::cvtColor(templateImage, graySmall, cv::COLOR_BGR2GRAY);

	// 3. 模板匹配
	cv::Mat result;
	cv::matchTemplate(grayLarge, graySmall, result, cv::TM_CCOEFF_NORMED);

	// 4. 设置阈值并查找匹配位置
	// NMS重叠阈值
	const double nmsThreshold = 0.3;

	std::vector<cv::Rect> rects;
	std::vector<float> scores;

	// 遍历所有匹配结果
	for (int y = 0; y < result.rows; y++)
	{
		for (int x = 0; x < result.cols; x++)
		{
			float score = result.at<float>(y, x);
			if (score >= scoreThreshold)
			{
				rects.push_back(cv::Rect(x, y, templateImage.cols, templateImage.rows));
				scores.push_back(score);
			}
		}
	}

	// 5. 检查是否有匹配结果
	if (rects.empty())
	{
		std::cout << "no find" << std::endl;
		return 0;
	}

	// 6. 应用非极大值抑制
	std::vector<cv::Rect> selected = nonMaximumSuppression(rects, scores, scoreThreshold, nmsThreshold);

	// 7. 检查NMS后是否有结果
	if (selected.empty())
	{
		std::cout << "not find" << std::endl;
		return 0;
	}

	cv::Rect& rect = selected.front();
	// 计算模板在屏幕上的实际中心坐标
	cv::Point topLeft(rect.x + searchX, rect.y + searchY);
	cv::Point center(topLeft.x + templateImage.cols / 2, topLeft.y + templateImage.rows / 2);

	// 打印模板在屏幕上的中心坐标
	std::cout << "Template found at center coordinates: (" << center.x << ", " << center.y << ")" << std::endl;

	// 移动鼠标到模板中心位置
	// SetCursorPos(center.x, center.y);

	*x = static_cast<int>(topLeft.x);
	*y = static_cast<int>(topLeft.y);

	return 1;
}


extern "C" IMAGEFINDER_API int __cdecl FindWinImage(
	const char* targetPath,
	int hwndInt,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	int* x,
	int* y)
{
	if (matchThreshold > 100) matchThreshold = 100;
	else if (matchThreshold < 0) matchThreshold = 0;
	double scoreThreshold = matchThreshold / 100.0;

	// 1. 加载模板图像
	cv::Mat templateImage = cv::imread(targetPath, cv::IMREAD_UNCHANGED);
	if (templateImage.empty())
	{
		std::cerr << "Could not open or find the template image." << std::endl;
		return 0;
	}

	// 2. 截取窗口区域
	cv::Mat capturedImage = captureScreen(hwndInt, searchX, searchY, searchW, searchH);
	if (capturedImage.empty())
	{
		std::cerr << "Failed to capture window region." << std::endl;
		return 0;
	}

	// 通道数统一，理由同 FindScreenImage
	if (templateImage.channels() != capturedImage.channels())
	{
		if (templateImage.channels() == 4 && capturedImage.channels() == 3)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGRA2BGR);
		else if (templateImage.channels() == 3 && capturedImage.channels() == 4)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGR2BGRA);
	}

	// 3. 旧接口固定灰度，不再根据相似度切换颜色模式。
	cv::Mat grayLarge, graySmall;
	cv::cvtColor(capturedImage, grayLarge, cv::COLOR_BGR2GRAY);
	cv::cvtColor(templateImage, graySmall, cv::COLOR_BGR2GRAY);

	// 4. 模板匹配
	cv::Mat result;
	cv::matchTemplate(grayLarge, graySmall, result, cv::TM_CCOEFF_NORMED);

	const double nmsThreshold = 0.3;
	std::vector<cv::Rect> rects;
	std::vector<float> scores;

	for (int yRow = 0; yRow < result.rows; yRow++)
	{
		for (int xCol = 0; xCol < result.cols; xCol++)
		{
			float score = result.at<float>(yRow, xCol);
			if (score >= scoreThreshold)
			{
				rects.push_back(cv::Rect(xCol, yRow, templateImage.cols, templateImage.rows));
				scores.push_back(score);
			}
		}
	}

	if (rects.empty()) return 0;

	std::vector<cv::Rect> selected = nonMaximumSuppression(rects, scores, scoreThreshold, nmsThreshold);
	if (selected.empty()) return 0;

	cv::Rect& rect = selected.front();
	cv::Point topLeft(rect.x + searchX, rect.y + searchY);
	*x = topLeft.x;
	*y = topLeft.y;
	
	return 1;
}
// =====================================================================
// 自适应匹配（跨分辨率 / 跨 DPI）
// 与旧 FindScreenImage/FindWinImage 的差别：
//   1) 不再遍历整张结果图 + NMS —— API 只返回一个点，minMaxLoc 给出的
//      就是「分数最高的那个位置」，与 NMS 后的 selected.front() 等价；
//   2) 1:1 优先，且判定口径与旧实现完全一致；1:1 没命中才往下走；
//   3) 往下走时同时看灰度图和 Sobel 梯度图：文字换了分辨率是系统重新
//      光栅化的，灰度对不上，笔画/字框的边缘结构还在；
//   4) 半分辨率粗扫用「灰度 + 边缘取大者」挑比例，再回原分辨率在候选点
//      周围按 ±6% 微调（像素取整会让密排文字整块错位）；
//   5) 缩放档位允许放宽 12% 灰度分，但要求边缘图在同一位置也对得上；
//   6) 模板带 alpha 时按不透明区域生成 mask 参与比对。
// =====================================================================

// 上次成功的比例记忆：同一个模板在循环里反复搜时，第二遍起直接命中粗扫第一档
static std::unordered_map<std::string, float> g_scaleHint;

static void toGrayMat(const cv::Mat& src, cv::Mat& dst)
{
	if (src.channels() == 1) { dst = src; return; }
	cv::cvtColor(src, dst, src.channels() == 4 ? cv::COLOR_BGRA2GRAY : cv::COLOR_BGR2GRAY);
}

// 有透明像素才建 mask；全不透明返回 false 走原路径
static bool buildAlphaMask(const cv::Mat& tpl, cv::Mat& mask)
{
	if (tpl.channels() != 4)
		return false;
	std::vector<cv::Mat> ch;
	cv::split(tpl, ch);
	double mn = 0, mx = 0;
	cv::minMaxLoc(ch[3], &mn, &mx);
	if (mn >= 250)
		return false;
	cv::threshold(ch[3], mask, 8, 255, cv::THRESH_BINARY);
	// 缩小/放大后边缘会混色，往里收一像素，避免把背景色带进比对
	if (std::min(tpl.cols, tpl.rows) >= 16)
		cv::erode(mask, mask, cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3)));
	return cv::countNonZero(mask) >= 4;
}

static cv::Mat resizeMat(const cv::Mat& src, double s, bool maskMode)
{
	cv::Mat out;
	int w = std::max(1, (int)std::lround(src.cols * s));
	int h = std::max(1, (int)std::lround(src.rows * s));
	if (w == src.cols && h == src.rows)
		return src;
	int interp = maskMode ? cv::INTER_NEAREST : (s < 1.0 ? cv::INTER_AREA : cv::INTER_LINEAR);
	cv::resize(src, out, cv::Size(w, h), 0, 0, interp);
	return out;
}

// 梯度幅值图：文字/细笔画模板在不同分辨率下是系统按矢量重新光栅化的，
// 灰度对不上，但笔画走向、字框位置这些边缘结构还在，用它做比例判断更稳
static cv::Mat toEdgeMat(const cv::Mat& gray)
{
	cv::Mat g, gx, gy, ax, ay, mag;
	cv::GaussianBlur(gray, g, cv::Size(3, 3), 0);
	cv::Sobel(g, gx, CV_16S, 1, 0, 3);
	cv::Sobel(g, gy, CV_16S, 0, 1, 3);
	cv::convertScaleAbs(gx, ax);
	cv::convertScaleAbs(gy, ay);
	cv::addWeighted(ax, 0.5, ay, 0.5, 0, mag);
	return mag;
}

// 单次匹配：只取最高分点（等价于旧实现「全图扫描 + NMS 取分数第一」）
static double matchBest(const cv::Mat& img, const cv::Mat& tpl, const cv::Mat& mask, cv::Point* loc)
{
	if (tpl.cols > img.cols || tpl.rows > img.rows)
		return -1.0;
	cv::Mat result;
	if (!mask.empty())
		cv::matchTemplate(img, tpl, result, cv::TM_CCORR_NORMED, mask);
	else
		cv::matchTemplate(img, tpl, result, cv::TM_CCOEFF_NORMED);
	cv::patchNaNs(result, 0.0);   // 纯色区域会算出 NaN/Inf，不清掉会让 minMaxLoc 结果失控
	double mn = 0, mx = -1;
	cv::Point mxLoc(0, 0);
	cv::minMaxLoc(result, &mn, &mx, nullptr, &mxLoc);
	if (loc) *loc = mxLoc;
	return mx;
}

// mask 命中后再核一次：只统计不透明像素的平均灰度差，挡住纯色模板分数虚高
static bool maskVerify(const cv::Mat& img, const cv::Mat& tpl, const cv::Mat& mask, cv::Point pt, int tol)
{
	if (pt.x < 0 || pt.y < 0 || pt.x + tpl.cols > img.cols || pt.y + tpl.rows > img.rows)
		return false;
	cv::Mat patch = img(cv::Rect(pt.x, pt.y, tpl.cols, tpl.rows));
	cv::Mat diff;
	cv::absdiff(patch, tpl, diff);
	double sum = 0;
	int n = 0;
	for (int yy = 0; yy < diff.rows; ++yy)
	{
		const uchar* d = diff.ptr<uchar>(yy);
		const uchar* m = mask.ptr<uchar>(yy);
		for (int xx = 0; xx < diff.cols; ++xx)
		{
			if (m[xx])
			{
				sum += d[xx];
				++n;
			}
		}
	}
	if (n == 0)
		return false;
	return (sum / n) <= tol;
}

// 缩放档位的命中判定：
// 灰度分够阈值 = 严格命中，口径和改之前完全一样；
// 否则才放宽（缩放后字型重新光栅化，灰度分会掉一截），但要求边缘图在同一位置也对得上，
// 避免糊到「同字体、差一个字」的模板上去。1:1 档位不放宽。
static bool acceptScaled(double scGray, double scEdge, cv::Point ptG, cv::Point ptE,
	double scale, double thr, bool okStrict, bool okLoose)
{
	if (scGray >= thr)
		return okStrict;
	if (std::fabs(scale - 1.0) < 0.005)
		return false;
	if (scGray >= thr - 0.12 && scEdge >= 0.55 && okLoose)
		return std::abs(ptG.x - ptE.x) <= 4 && std::abs(ptG.y - ptE.y) <= 4;
	return false;
}

// 核心：返回模板左上角在 captured 内的坐标（未加 searchX/searchY，由调用方加）
static int findImageAdaptiveCore(const cv::Mat& captured, const cv::Mat& tpl, int matchThreshold,
	const char* cacheKey, cv::Point* outPt)
{
	double thr = matchThreshold / 100.0;
	cv::Mat grayImg, tplGray, mask;
	toGrayMat(captured, grayImg);
	toGrayMat(tpl, tplGray);
	bool useMask = buildAlphaMask(tpl, mask);
	int tol = (int)std::max(12.0, (100 - matchThreshold) * 3.0);

	// 比例候选：1:1 → 上次成功过的比例 → 常见档位（100/125/150% DPI 及其反向）
	std::vector<double> scales;
	scales.push_back(1.0);
	auto pushScale = [&](double s) {
		if (s <= 0.05)
			return;
		for (size_t i = 0; i < scales.size(); ++i)
			if (std::fabs(scales[i] - s) < 0.02)
				return;
		int w = (int)std::lround(tplGray.cols * s);
		int h = (int)std::lround(tplGray.rows * s);
		if (w < 4 || h < 4 || w > grayImg.cols || h > grayImg.rows)
			return;
		scales.push_back(s);
	};
	if (cacheKey && cacheKey[0])
	{
		auto it = g_scaleHint.find(cacheKey);
		if (it != g_scaleHint.end())
			pushScale(it->second);
	}
	const double ladder[] = { 1.25, 0.8, 1.5, 0.6667, 1.75, 0.5714, 2.0, 0.5 };
	for (double s : ladder)
		pushScale(s);

	// ① 1:1 快速路径：和改之前一次匹配的成本相同
	{
		cv::Point pt;
		double sc = matchBest(grayImg, tplGray, mask, &pt);
		if (sc >= thr && (!useMask || maskVerify(grayImg, tplGray, mask, pt, tol)))
		{
			*outPt = pt;
			return 1;
		}
	}

	// 1:1 没命中才付边缘图这份开销
	cv::Mat edgeImg = toEdgeMat(grayImg);
	cv::Mat tplEdge = toEdgeMat(tplGray);
	if (useMask)
		cv::bitwise_and(tplEdge, tplEdge, tplEdge, mask);   // 透明区不算边缘，免得 alpha 边界造出假边缘

	// ② 半分辨率粗扫：灰度与边缘各扫一遍取大者，只用来挑比例，不判阈值
	//    （缩小后分数会掉，不能拿来判定；文字类模板靠边缘这条路才挑得准）
	bool coarseDone = false;
	double bestScale = 1.0;
	cv::Point bestPt(0, 0);
	if (std::min(tplGray.cols, tplGray.rows) >= 24 && grayImg.cols >= 160 && grayImg.rows >= 160)
	{
		cv::Mat half, halfEdge;
		cv::resize(grayImg, half, cv::Size(grayImg.cols / 2, grayImg.rows / 2), 0, 0, cv::INTER_AREA);
		cv::resize(edgeImg, halfEdge, cv::Size(grayImg.cols / 2, grayImg.rows / 2), 0, 0, cv::INTER_AREA);
		double bestScore = -1;
		for (size_t i = 1; i < scales.size(); ++i)
		{
			cv::Mat th = resizeMat(tplGray, scales[i] * 0.5, false);
			cv::Mat eh = resizeMat(tplEdge, scales[i] * 0.5, false);
			cv::Mat mh = useMask ? resizeMat(mask, scales[i] * 0.5, true) : cv::Mat();
			if (th.cols > half.cols || th.rows > half.rows)
				continue;
			cv::Point ptG, ptE;
			double scG = matchBest(half, th, mh, &ptG);
			double scE = matchBest(halfEdge, eh, cv::Mat(), &ptE);
			double sc = std::max(scG, scE);
			if (sc > bestScore)
			{
				bestScore = sc;
				bestScale = scales[i];
				bestPt = (scE > scG) ? ptE : ptG;
				coarseDone = true;
			}
		}
	}

	// ③ 回原分辨率细调：候选点周围一小块里对比例做小步微调
	//    档位比例本身对（比如正好 125%），可像素取整会让整块模板一点点错位，
	//    密排文字对这种错位最敏感，所以要在附近再扫一遍 ±6%
	if (coarseDone)
	{
		cv::Mat tf0 = resizeMat(tplGray, bestScale, false);
		int cx = bestPt.x * 2, cy = bestPt.y * 2;
		int margin = 8 + std::max(tf0.cols, tf0.rows) / 16;
		int rx = std::max(0, cx - margin), ry = std::max(0, cy - margin);
		int rw = std::min(grayImg.cols - rx, tf0.cols + margin * 2);
		int rh = std::min(grayImg.rows - ry, tf0.rows + margin * 2);
		if (rw >= tf0.cols && rh >= tf0.rows)
		{
			// clone 一次：matchTemplate 对非连续 ROI 不稳，候选窗口很小，拷贝代价可以忽略
			cv::Rect roiRect(rx, ry, rw, rh);
			cv::Mat roi = grayImg(roiRect).clone();
			cv::Mat roiE = edgeImg(roiRect).clone();
			const double fine[] = { 1.0, 0.97, 1.03, 0.94, 1.06 };
			double bestSG = -2, bestSE = -2, winScale = bestScale;
			cv::Point winPG(0, 0), winPE(0, 0);
			bool winStrict = true, winLoose = true;
			for (double k : fine)
			{
				double s = bestScale * k;
				cv::Mat tf = resizeMat(tplGray, s, false);
				cv::Mat ef = resizeMat(tplEdge, s, false);
				cv::Mat mf = useMask ? resizeMat(mask, s, true) : cv::Mat();
				if (tf.cols > roi.cols || tf.rows > roi.rows)
					continue;
				cv::Point pG, pE;
				double sg = matchBest(roi, tf, mf, &pG);
				double se = matchBest(roiE, ef, cv::Mat(), &pE);
				if (sg > bestSG)
				{
					bestSG = sg;
					bestSE = se;
					winScale = s;
					winPG = pG;
					winPE = pE;
					winStrict = !useMask || maskVerify(roi, tf, mf, pG, tol);
					winLoose = !useMask || maskVerify(roi, tf, mf, pG, tol * 2);
				}
			}
			if (bestSG > -1 && acceptScaled(bestSG, bestSE, winPG, winPE, winScale, thr, winStrict, winLoose))
			{
				if (cacheKey && cacheKey[0])
					g_scaleHint[cacheKey] = (float)winScale;
				*outPt = cv::Point(rx + winPG.x, ry + winPG.y);
				return 1;
			}
		}
	}

	// ④ 兜底：逐档在原图上直接试（粗扫因模板太小被跳过、或候选点被复核否掉时走这里）
	//    小模板多半是文字截图，只试相近档位，1.75/2.0 这种离谱比例本来也不该出现
	size_t tryCount = scales.size();
	if (std::min(tplGray.cols, tplGray.rows) < 24 && tryCount > 5)
		tryCount = 5;
	for (size_t i = 1; i < tryCount; ++i)
	{
		cv::Mat tf = resizeMat(tplGray, scales[i], false);
		cv::Mat mf = useMask ? resizeMat(mask, scales[i], true) : cv::Mat();
		cv::Point pG, pE;
		double sg = matchBest(grayImg, tf, mf, &pG);
		if (sg < thr - 0.12)
			continue;                       // 灰度差太远，边缘也不必再算了
		double se = matchBest(edgeImg, resizeMat(tplEdge, scales[i], false), cv::Mat(), &pE);
		bool okStrict = !useMask || maskVerify(grayImg, tf, mf, pG, tol);
		bool okLoose = !useMask || maskVerify(grayImg, tf, mf, pG, tol * 2);
		if (acceptScaled(sg, se, pG, pE, scales[i], thr, okStrict, okLoose))
		{
			if (cacheKey && cacheKey[0])
				g_scaleHint[cacheKey] = (float)scales[i];
			*outPt = pG;
			return 1;
		}
	}
	return 0;
}

extern "C" IMAGEFINDER_API int __cdecl GetApiVersion()
{
	return 13;  // 13 = 批量屏幕/窗口搜索，单结果默认先左右后上下
}

// Ex 接口保留旧导出 ABI；颜色模式沿用原彩色模板的相似度算法，
// 不允许灰度/边缘回退绕过颜色检查。未勾选时沿用灰度匹配。
static int findImageExplicitCore(const cv::Mat& captured, const cv::Mat& tpl,
	int threshold, bool colorMatch, bool adaptive, const char* key, cv::Point* pt)
{
    if (captured.empty() || tpl.empty()) return 0;
    auto positions = rmt_search_all::images(captured, tpl,
        std::max(0, std::min(100, threshold)), colorMatch, adaptive, true);
    if (positions.empty()) return 0;
    *pt = *std::min_element(positions.begin(), positions.end(), [](const cv::Point& a, const cv::Point& b) {
        return a.y != b.y ? a.y < b.y : a.x < b.x;
    });
    return 1;
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageEx(const char* path,
	int sx, int sy, int sw, int sh, int threshold, int colorMatch, int adaptive, int* x, int* y)
{
	if (!path || !x || !y || sw <= 0 || sh <= 0) return 0;
	try {
		cv::Mat tpl = cv::imread(path, cv::IMREAD_UNCHANGED);
		cv::Mat image = captureScreen(sx, sy, sw, sh);
		cv::Point pt;
		if (!findImageExplicitCore(image, tpl, threshold, colorMatch != 0, adaptive != 0, path, &pt)) return 0;
		*x = sx + pt.x; *y = sy + pt.y; return 1;
	} catch (const cv::Exception&) { return 0; }
}

extern "C" IMAGEFINDER_API int __cdecl FindWinImageEx(const char* path, int hwnd,
	int sx, int sy, int sw, int sh, int threshold, int colorMatch, int adaptive, int* x, int* y)
{
	if (!path || !x || !y || sw <= 0 || sh <= 0) return 0;
	try {
		cv::Mat tpl = cv::imread(path, cv::IMREAD_UNCHANGED);
		cv::Mat image = captureScreen(hwnd, sx, sy, sw, sh);
		cv::Point pt;
		if (!findImageExplicitCore(image, tpl, threshold, colorMatch != 0, adaptive != 0, path, &pt)) return 0;
		*x = sx + pt.x; *y = sy + pt.y; return 1;
	} catch (const cv::Exception&) { return 0; }
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageAdaptive(
	const char* targetPath,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	int* x,
	int* y)
{
	if (matchThreshold > 100) matchThreshold = 100;
	else if (matchThreshold < 0) matchThreshold = 0;

	cv::Mat tpl = cv::imread(targetPath, cv::IMREAD_UNCHANGED);
	if (tpl.empty())
		return 0;
	cv::Mat captured = captureScreen(searchX, searchY, searchW, searchH);
	if (captured.empty())
		return 0;

	cv::Point pt;
	if (!findImageAdaptiveCore(captured, tpl, matchThreshold, targetPath, &pt))
		return 0;
	*x = pt.x + searchX;
	*y = pt.y + searchY;
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl FindWinImageAdaptive(
	const char* targetPath,
	int hwndInt,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	int* x,
	int* y)
{
	if (matchThreshold > 100) matchThreshold = 100;
	else if (matchThreshold < 0) matchThreshold = 0;

	cv::Mat tpl = cv::imread(targetPath, cv::IMREAD_UNCHANGED);
	if (tpl.empty())
		return 0;
	cv::Mat captured = captureScreen(hwndInt, searchX, searchY, searchW, searchH);
	if (captured.empty())
		return 0;

	cv::Point pt;
	if (!findImageAdaptiveCore(captured, tpl, matchThreshold, targetPath, &pt))
		return 0;
	*x = pt.x + searchX;
	*y = pt.y + searchY;
	return 1;
}

namespace
{
thread_local wchar_t g_imageLastError[512] = L"";

void ClearImageError()
{
	g_imageLastError[0] = L'\0';
}

void SetImageError(const wchar_t* fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	_vsnwprintf_s(g_imageLastError, _countof(g_imageLastError), _TRUNCATE, fmt, args);
	va_end(args);
}

bool ReadAllBytesW(const wchar_t* path, std::vector<uchar>& out)
{
	out.clear();
	if (path == nullptr || path[0] == L'\0')
		return false;

	FILE* fp = nullptr;
	if (_wfopen_s(&fp, path, L"rb") != 0 || fp == nullptr)
		return false;
	if (fseek(fp, 0, SEEK_END) != 0)
	{
		fclose(fp);
		return false;
	}

	const long size = ftell(fp);
	if (size <= 0)
	{
		fclose(fp);
		return false;
	}
	rewind(fp);
	out.resize(static_cast<size_t>(size));
	const size_t read = fread(out.data(), 1, out.size(), fp);
	fclose(fp);
	if (read != out.size())
	{
		out.clear();
		return false;
	}
	return true;
}

bool LoadTemplateBgra(const wchar_t* path, cv::Mat& bgra, bool& hasAlpha)
{
	bgra.release();
	hasAlpha = false;
	std::vector<uchar> bytes;
	if (!ReadAllBytesW(path, bytes))
		return false;

	try
	{
		cv::Mat raw = cv::imdecode(bytes, cv::IMREAD_UNCHANGED);
		if (raw.empty() || raw.depth() != CV_8U)
		return false;
		switch (raw.channels())
		{
		case 4:
			bgra = raw;
			hasAlpha = true;
			break;
		case 3:
			cv::cvtColor(raw, bgra, cv::COLOR_BGR2BGRA);
			break;
		case 1:
			cv::cvtColor(raw, bgra, cv::COLOR_GRAY2BGRA);
			break;
		default:
			return false;
		}
	}
	catch (const cv::Exception&)
	{
		bgra.release();
		hasAlpha = false;
		return false;
	}
	return true;
}

bool WriteAllBytesW(const wchar_t* path, const std::vector<uchar>& data)
{
	if (path == nullptr || path[0] == L'\0')
		return false;
	FILE* fp = nullptr;
	if (_wfopen_s(&fp, path, L"wb") != 0 || fp == nullptr)
		return false;
	const size_t written = fwrite(data.data(), 1, data.size(), fp);
	fclose(fp);
	return written == data.size();
}

bool WritePreview(const wchar_t* path, const cv::Mat& image)
{
	if (path == nullptr || path[0] == L'\0')
		return true;
	std::vector<uchar> png;
	if (!cv::imencode(".png", image, png) || png.empty())
	{
		SetImageError(L"预览图编码失败");
		return false;
	}
	if (!WriteAllBytesW(path, png))
	{
		SetImageError(L"预览图写入失败：%s", path);
		return false;
	}
	return true;
}
}

static bool ApplySeedColorPreview(cv::Mat& scaled, const cv::Mat& sourceView,
	const wchar_t* seedPointText, int tolerance, int zoomPercent);

extern "C" IMAGEFINDER_API const wchar_t* __cdecl GetImageLastError()
{
	return g_imageLastError;
}

extern "C" IMAGEFINDER_API int __cdecl RenderImagePreview(
	const wchar_t* targetPath,
	int maxW, int maxH,
	int viewX, int viewY, int viewW, int viewH,
	int rectX, int rectY, int rectW, int rectH,
	int showGrid, int zoomPercent,
	const wchar_t* seedPoints, int tolerance,
	const wchar_t* outOrigPath, const wchar_t* outPreviewPath,
	int* validPixels, int* totalPixels,
	int* previewW, int* previewH, int* origW, int* origH,
	int* bboxX, int* bboxY, int* bboxW, int* bboxH)
{
	ClearImageError();
	if (targetPath == nullptr || validPixels == nullptr || totalPixels == nullptr
		|| previewW == nullptr || previewH == nullptr || origW == nullptr || origH == nullptr
		|| bboxX == nullptr || bboxY == nullptr || bboxW == nullptr || bboxH == nullptr
		|| (outOrigPath == nullptr && outPreviewPath == nullptr))
	{
		SetImageError(L"参数非法：指针为空");
		return -6;
	}

	*validPixels = *totalPixels = *previewW = *previewH = 0;
	*origW = *origH = *bboxX = *bboxY = *bboxW = *bboxH = 0;
	maxW = std::max(16, maxW);
	maxH = std::max(16, maxH);

	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(targetPath, bgra, hasAlpha))
	{
		SetImageError(L"模板读取失败：无法打开、解码失败或不是 8 位图像 %s", targetPath);
		return -1;
	}

	*origW = bgra.cols;
	*origH = bgra.rows;
	*totalPixels = bgra.cols * bgra.rows;
	if (hasAlpha)
	{
		*validPixels = 0;
		for (int y = 0; y < bgra.rows; ++y)
		{
			const uchar* row = bgra.ptr<uchar>(y);
			for (int x = 0; x < bgra.cols; ++x)
				if (row[x * 4 + 3] > 0)
					++*validPixels;
		}
	}
	else
	{
		*validPixels = *totalPixels;
	}
	*bboxX = 0;
	*bboxY = 0;
	*bboxW = bgra.cols;
	*bboxH = bgra.rows;

	cv::Rect view(0, 0, bgra.cols, bgra.rows);
	if (viewW > 0 && viewH > 0)
	{
		view.width = std::min(viewW, bgra.cols);
		view.height = std::min(viewH, bgra.rows);
		view.x = std::max(0, std::min(viewX, bgra.cols - view.width));
		view.y = std::max(0, std::min(viewY, bgra.rows - view.height));
	}

	const double zoom = std::max(0.01, zoomPercent / 100.0);
	const int scaledW = std::max(1, static_cast<int>(std::lround(view.width * zoom)));
	const int scaledH = std::max(1, static_cast<int>(std::lround(view.height * zoom)));
	const cv::Mat sourceView = bgra(view);
	cv::Mat scaled;
	const int interpolation = zoom < 1.0 ? cv::INTER_AREA : cv::INTER_NEAREST;
	cv::resize(sourceView, scaled, cv::Size(scaledW, scaledH), 0, 0, interpolation);
	const cv::Mat originalScaled = scaled.clone();
	if (!ApplySeedColorPreview(scaled, sourceView, seedPoints, tolerance, zoomPercent))
		return -4;

	cv::Mat canvas(maxH, maxW, CV_8UC4, cv::Scalar(30, 30, 30, 255));
	cv::Mat previewCanvas(maxH, maxW, CV_8UC4, cv::Scalar(30, 30, 30, 255));
	int pasteX = (maxW - scaledW) / 2;
	int pasteY = (maxH - scaledH) / 2;
	int srcX = std::max(0, -pasteX);
	int srcY = std::max(0, -pasteY);
	pasteX = std::max(0, pasteX);
	pasteY = std::max(0, pasteY);
	const int copyW = std::min(scaledW - srcX, maxW - pasteX);
	const int copyH = std::min(scaledH - srcY, maxH - pasteY);
	if (copyW > 0 && copyH > 0)
	{
		const cv::Rect sourceRect(srcX, srcY, copyW, copyH);
		const cv::Rect targetRect(pasteX, pasteY, copyW, copyH);
		originalScaled(sourceRect).copyTo(canvas(targetRect));
		scaled(sourceRect).copyTo(previewCanvas(targetRect));
	}
	*previewW = copyW;
	*previewH = copyH;

	auto drawDecorations = [&](cv::Mat& target)
	{
		if (showGrid && zoom >= 6.0)
		{
			for (int i = 1; i < view.width; ++i)
			{
				const int gx = pasteX + static_cast<int>(std::lround(i * zoom)) - srcX;
				if (gx > 0 && gx < maxW)
					cv::line(target, cv::Point(gx, pasteY), cv::Point(gx, pasteY + copyH - 1), cv::Scalar(70, 70, 70, 255), 1);
			}
			for (int i = 1; i < view.height; ++i)
			{
				const int gy = pasteY + static_cast<int>(std::lround(i * zoom)) - srcY;
				if (gy > 0 && gy < maxH)
					cv::line(target, cv::Point(pasteX, gy), cv::Point(pasteX + copyW - 1, gy), cv::Scalar(70, 70, 70, 255), 1);
			}
		}

		if (rectW > 0 && rectH > 0)
		{
			const int rx = pasteX + static_cast<int>(std::lround((rectX - view.x) * zoom)) - srcX;
			const int ry = pasteY + static_cast<int>(std::lround((rectY - view.y) * zoom)) - srcY;
			const int rw = std::max(1, static_cast<int>(std::lround(rectW * zoom)));
			const int rh = std::max(1, static_cast<int>(std::lround(rectH * zoom)));
			cv::rectangle(target, cv::Rect(rx, ry, rw, rh), cv::Scalar(0, 220, 255, 255), 1);
			const int handleSize = 4;
			for (int dx : { 0, rw })
				for (int dy : { 0, rh })
					cv::rectangle(target, cv::Point(rx + dx - handleSize, ry + dy - handleSize),
						cv::Point(rx + dx + handleSize, ry + dy + handleSize), cv::Scalar(0, 220, 255, 255), -1);
		}
	};

	drawDecorations(canvas);
	drawDecorations(previewCanvas);

	if (!WritePreview(outOrigPath, canvas) || !WritePreview(outPreviewPath, previewCanvas))
		return -3;
	ClearImageError();
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl CropImageFile(
	const wchar_t* srcPath, int x, int y, int w, int h, const wchar_t* dstPath)
{
	ClearImageError();
	if (srcPath == nullptr || dstPath == nullptr)
	{
		SetImageError(L"参数非法：路径为空");
		return -6;
	}
	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(srcPath, bgra, hasAlpha))
	{
		SetImageError(L"读取失败：%s", srcPath);
		return -1;
	}
	if (w <= 0 || h <= 0 || x < 0 || y < 0 || x >= bgra.cols || y >= bgra.rows)
	{
		SetImageError(L"裁剪区域无效：(%d,%d) %dx%d", x, y, w, h);
		return -6;
	}
	const int cropW = std::min(w, bgra.cols - x);
	const int cropH = std::min(h, bgra.rows - y);
	cv::Mat cropped = bgra(cv::Rect(x, y, cropW, cropH)).clone();
	std::vector<uchar> png;
	if (!cv::imencode(".png", cropped, png) || png.empty())
	{
		SetImageError(L"裁剪结果编码失败");
		return -3;
	}
	if (!WriteAllBytesW(dstPath, png))
	{
		SetImageError(L"裁剪结果写入失败：%s", dstPath);
		return -3;
	}
	ClearImageError();
	return 1;
}

static int GetImagePixel(const wchar_t* path, int x, int y,
	int* r, int* g, int* b, int* a)
{
	ClearImageError();
	if (path == nullptr || r == nullptr || g == nullptr || b == nullptr)
	{
		SetImageError(L"参数非法：指针为空");
		return -6;
	}
	*r = *g = *b = 0;
	if (a != nullptr)
		*a = 255;
	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(path, bgra, hasAlpha))
	{
		SetImageError(L"模板读取失败：%s", path);
		return -1;
	}
	if (x < 0 || y < 0 || x >= bgra.cols || y >= bgra.rows)
	{
		SetImageError(L"坐标越界：(%d,%d) 超出 %dx%d", x, y, bgra.cols, bgra.rows);
		return -6;
	}
	const uchar* pixel = bgra.ptr<uchar>(y) + x * 4;
	*b = pixel[0];
	*g = pixel[1];
	*r = pixel[2];
	if (a != nullptr)
		*a = pixel[3];
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAt(
	const wchar_t* path, int x, int y, int* r, int* g, int* b)
{
	return GetImagePixel(path, x, y, r, g, b, nullptr);
}

extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAtEx(
	const wchar_t* path, int x, int y, int* r, int* g, int* b, int* a)
{
	if (a == nullptr)
	{
		ClearImageError();
		SetImageError(L"参数非法：Alpha 指针为空");
		return -6;
	}
	return GetImagePixel(path, x, y, r, g, b, a);
}

// 多点找图：只采样用户选中的模板点，避免对整张模板做逐像素比较。
// points 格式为 "x,y,RRGGBB;x,y,RRGGBB"，坐标相对模板左上角。
// ===========================================================================
struct MultiPointSample
{
	int x;
	int y;
	cv::Vec3b bgr;
};

static bool ParseMultiPointData(const wchar_t* text, std::vector<MultiPointSample>& points)
{
	points.clear();
	if (text == nullptr || text[0] == L'\0')
		return false;

	const std::wstring all(text);
	size_t pos = 0;
	while (pos < all.size())
	{
		const size_t end = all.find(L';', pos);
		const std::wstring token = all.substr(pos, end == std::wstring::npos ? end : end - pos);
		const size_t comma1 = token.find(L',');
		const size_t comma2 = comma1 == std::wstring::npos ? comma1 : token.find(L',', comma1 + 1);
		if (comma1 == std::wstring::npos || comma2 == std::wstring::npos
			|| token.find(L',', comma2 + 1) != std::wstring::npos)
			return false;

		const std::wstring xs = token.substr(0, comma1);
		const std::wstring ys = token.substr(comma1 + 1, comma2 - comma1 - 1);
		const std::wstring color = token.substr(comma2 + 1);
		wchar_t* parseEnd = nullptr;
		const long px = wcstol(xs.c_str(), &parseEnd, 10);
		if (parseEnd == xs.c_str() || *parseEnd != L'\0' || px < 0)
			return false;
		const long py = wcstol(ys.c_str(), &parseEnd, 10);
		if (parseEnd == ys.c_str() || *parseEnd != L'\0' || py < 0)
			return false;
		if (color.size() != 6 || points.size() >= 256)
			return false;
		for (wchar_t ch : color)
			if (!((ch >= L'0' && ch <= L'9') || (ch >= L'a' && ch <= L'f') || (ch >= L'A' && ch <= L'F')))
				return false;

		wchar_t* colorEnd = nullptr;
		const unsigned long rgb = wcstoul(color.c_str(), &colorEnd, 16);
		if (colorEnd == color.c_str() || *colorEnd != L'\0' || rgb > 0xFFFFFFUL)
			return false;

		points.push_back({
			static_cast<int>(px),
			static_cast<int>(py),
			cv::Vec3b(
				static_cast<uchar>(rgb & 0xFF),
				static_cast<uchar>((rgb >> 8) & 0xFF),
				static_cast<uchar>((rgb >> 16) & 0xFF))
		});
		if (end == std::wstring::npos)
			break;
		pos = end + 1;
	}

    return !points.empty();
}

static bool IsMultiPointColorHit(const uchar* pixel, const cv::Vec3b& target, int tolerance)
{
	return std::abs(static_cast<int>(pixel[0]) - static_cast<int>(target[0])) <= tolerance
		&& std::abs(static_cast<int>(pixel[1]) - static_cast<int>(target[1])) <= tolerance
		&& std::abs(static_cast<int>(pixel[2]) - static_cast<int>(target[2])) <= tolerance;
}

static int FindImageMultiPointCore(const wchar_t* targetPath, const cv::Mat& shot,
	int matchThreshold, const wchar_t* pointText, int tolerance, int* x, int* y)
{
	cv::Mat tpl;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(targetPath, tpl, hasAlpha))
	{
		SetImageError(L"模板读取失败：%s", targetPath);
		return -1;
	}

	std::vector<MultiPointSample> points;
	if (!ParseMultiPointData(pointText, points))
	{
		SetImageError(L"多点数据无效：至少选择 1 个点，最多 256 个点");
		return -4;
	}
	for (const MultiPointSample& point : points)
	{
		if (point.x < 0 || point.y < 0 || point.x >= tpl.cols || point.y >= tpl.rows)
		{
			SetImageError(L"多点坐标越界：(%d,%d) 超出模板 %dx%d", point.x, point.y, tpl.cols, tpl.rows);
			return -4;
		}
		if (hasAlpha && tpl.ptr<uchar>(point.y)[point.x * 4 + 3] < 128)
		{
			SetImageError(L"多点不能落在透明区域：(%d,%d)", point.x, point.y);
			return -4;
		}
	}

	if (shot.empty())
	{
		SetImageError(L"截图失败：搜索区域为空");
		return -5;
	}
	if (tpl.cols > shot.cols || tpl.rows > shot.rows)
	{
		SetImageError(L"模板尺寸(%dx%d)大于搜索区域(%dx%d)", tpl.cols, tpl.rows, shot.cols, shot.rows);
		return -2;
	}

	matchThreshold = std::max(0, std::min(100, matchThreshold));
	tolerance = std::max(0, std::min(255, tolerance));
	const int required = std::max(1, static_cast<int>(std::ceil(points.size() * matchThreshold / 100.0)));
	const int maxX = shot.cols - tpl.cols;
	const int maxY = shot.rows - tpl.rows;
	int bestHits = 0;
	int bestX = 0;
	int bestY = 0;
	const size_t anchorCount = points.size() - static_cast<size_t>(required) + 1;
	const size_t firstAnchor = (anchorCount == 1) ? 0 : points.size() - anchorCount;

	for (int row = 0; row <= maxY; ++row)
	{
		for (int col = 0; col <= maxX; ++col)
		{
			// A valid candidate can miss N-required points, so at least one of
			// N-required+1 anchors must hit. A single fixed anchor loses valid matches.
			bool anchorHit = false;
			for (size_t i = 0; i < anchorCount; ++i)
			{
				const MultiPointSample& anchor = points[firstAnchor + i];
				const uchar* anchorPixel = shot.ptr<uchar>(row + anchor.y) + (col + anchor.x) * 4;
				if (IsMultiPointColorHit(anchorPixel, anchor.bgr, tolerance))
				{
					anchorHit = true;
					break;
				}
			}
			if (!anchorHit)
				continue;

			int hits = 0;
			for (size_t i = 0; i < points.size(); ++i)
			{
				const MultiPointSample& point = points[i];
				const uchar* pixel = shot.ptr<uchar>(row + point.y) + (col + point.x) * 4;
				if (IsMultiPointColorHit(pixel, point.bgr, tolerance))
					++hits;
			}
			if (hits > bestHits)
			{
				bestHits = hits;
				bestX = col;
				bestY = row;
				if (bestHits >= required)
					break;
			}
		}
		if (bestHits >= required)
			break;
	}

	if (bestHits < required)
	{
		SetImageError(L"多点未命中：命中 %d/%d 点，要求至少 %d 点", bestHits,
			static_cast<int>(points.size()), required);
		return 0;
	}
	*x = bestX;
	*y = bestY;
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageMultiPoint(
	const wchar_t* targetPath, int searchX, int searchY, int searchW, int searchH,
	int matchThreshold, const wchar_t* points, int tolerance, int* x, int* y)
{
	ClearImageError();
	if (targetPath == nullptr || x == nullptr || y == nullptr || searchW <= 0 || searchH <= 0)
	{
		SetImageError(L"参数非法：模板路径、坐标指针和搜索区域必须有效");
		return -6;
	}
	*x = 0;
	*y = 0;
	try
	{
		cv::Mat shot = captureScreen(searchX, searchY, searchW, searchH);
		const int ret = FindImageMultiPointCore(targetPath, shot, matchThreshold, points, tolerance, x, y);
		if (ret == 1)
		{
			*x += searchX;
			*y += searchY;
			ClearImageError();
		}
		return ret;
	}
	catch (const cv::Exception& ex)
	{
		SetImageError(L"OpenCV 多点匹配异常：%hs", ex.what());
		return -3;
	}
	catch (...)
	{
		SetImageError(L"多点匹配异常");
		return -3;
	}
}

extern "C" IMAGEFINDER_API int __cdecl FindWinImageMultiPoint(
	const wchar_t* targetPath, int hwnd, int searchX, int searchY, int searchW, int searchH,
	int matchThreshold, const wchar_t* points, int tolerance, int* x, int* y)
{
	ClearImageError();
	if (targetPath == nullptr || x == nullptr || y == nullptr || hwnd == 0 || searchW <= 0 || searchH <= 0)
	{
		SetImageError(L"参数非法：模板路径、窗口句柄、坐标指针和搜索区域必须有效");
		return -6;
	}
	*x = 0;
	*y = 0;
	try
	{
		cv::Mat shot = captureScreen(hwnd, searchX, searchY, searchW, searchH);
		const int ret = FindImageMultiPointCore(targetPath, shot, matchThreshold, points, tolerance, x, y);
		if (ret == 1)
		{
			*x += searchX;
			*y += searchY;
			ClearImageError();
		}
		return ret;
	}
	catch (const cv::Exception& ex)
	{
		SetImageError(L"OpenCV 窗口多点匹配异常：%hs", ex.what());
		return -3;
	}
	catch (...)
	{
		SetImageError(L"窗口多点匹配异常");
		return -3;
	}
}

namespace
{
struct EffectivePixel
{
	int x;
	int y;
	cv::Vec3b bgr;
};

struct SuperMultiPointTemplate
{
	int width = 0;
	int height = 0;
	std::vector<EffectivePixel> pixels;
	std::vector<MultiPointSample> coarsePoints;
};

struct SuperIgnoreOperation
{
	wchar_t type = L'\0';
	int size = 1;
	int x = 0;
	int y = 0;
	int width = 0;
	int height = 0;
	std::vector<cv::Point> points;
};

static bool ParseIgnoreCoordinate(const std::wstring& text, int& value)
{
	if (text.empty())
		return false;
	wchar_t* end = nullptr;
	const long parsed = wcstol(text.c_str(), &end, 10);
	if (end == text.c_str() || *end != L'\0' || parsed < -1000000 || parsed > 1000000)
		return false;
	value = static_cast<int>(parsed);
	return true;
}

static bool ParseSuperIgnoreData(const wchar_t* text, std::vector<SuperIgnoreOperation>& operations)
{
	operations.clear();
	if (text == nullptr || text[0] == L'\0')
		return true;

	const std::wstring all(text);
	if (all.size() > 4u * 1024u * 1024u)
		return false;

	size_t totalPathPoints = 0;
	size_t pos = 0;
	while (pos < all.size())
	{
		const size_t end = all.find(L';', pos);
		const std::wstring token = all.substr(pos,
			end == std::wstring::npos ? end : end - pos);
		std::vector<std::wstring> fields;
		size_t fieldPos = 0;
		while (fieldPos <= token.size())
		{
			const size_t separator = token.find(L':', fieldPos);
			fields.push_back(token.substr(fieldPos,
				separator == std::wstring::npos ? separator : separator - fieldPos));
			if (separator == std::wstring::npos)
				break;
			fieldPos = separator + 1;
		}

		SuperIgnoreOperation operation;
		if (fields.size() == 5 && fields[0] == L"R")
		{
			operation.type = L'R';
			if (!ParseIgnoreCoordinate(fields[1], operation.x)
				|| !ParseIgnoreCoordinate(fields[2], operation.y)
				|| !ParseIgnoreCoordinate(fields[3], operation.width)
				|| !ParseIgnoreCoordinate(fields[4], operation.height)
				|| operation.width <= 0 || operation.height <= 0)
				return false;
		}
		else if (fields.size() == 3 && (fields[0] == L"B" || fields[0] == L"E"))
		{
			operation.type = fields[0][0];
			if (!ParseIgnoreCoordinate(fields[1], operation.size)
				|| operation.size < 1 || operation.size > 3 || fields[2].empty())
				return false;

			size_t pointPos = 0;
			while (pointPos <= fields[2].size())
			{
				const size_t pointEnd = fields[2].find(L'|', pointPos);
				const std::wstring pointText = fields[2].substr(pointPos,
					pointEnd == std::wstring::npos ? pointEnd : pointEnd - pointPos);
				const size_t comma = pointText.find(L',');
				if (comma == std::wstring::npos
					|| pointText.find(L',', comma + 1) != std::wstring::npos)
					return false;

				int x = 0, y = 0;
				if (!ParseIgnoreCoordinate(pointText.substr(0, comma), x)
					|| !ParseIgnoreCoordinate(pointText.substr(comma + 1), y))
					return false;
				operation.points.emplace_back(x, y);
				if (++totalPathPoints > 1000000)
					return false;
				if (pointEnd == std::wstring::npos)
					break;
				pointPos = pointEnd + 1;
			}
		}
		else
		{
			return false;
		}

		operations.push_back(std::move(operation));
		if (operations.size() > 100000)
			return false;
		if (end == std::wstring::npos)
			break;
		pos = end + 1;
	}
	return true;
}

static cv::Mat BuildSuperIgnoreMask(int width, int height,
	const std::vector<SuperIgnoreOperation>& operations)
{
	if (operations.empty())
		return {};

	cv::Mat mask(height, width, CV_8UC1, cv::Scalar(0));
	const cv::Rect bounds(0, 0, width, height);
	for (const SuperIgnoreOperation& operation : operations)
	{
		if (operation.type == L'R')
		{
			const long long right = static_cast<long long>(operation.x) + operation.width;
			const long long bottom = static_cast<long long>(operation.y) + operation.height;
			const int left = std::max(0, operation.x);
			const int top = std::max(0, operation.y);
			const int clippedRight = static_cast<int>(std::min<long long>(width, right));
			const int clippedBottom = static_cast<int>(std::min<long long>(height, bottom));
			if (clippedRight > left && clippedBottom > top)
			{
				const cv::Rect region(left, top, clippedRight - left, clippedBottom - top);
				mask(region) = cv::Scalar(255);
			}
			continue;
		}

		const uchar value = operation.type == L'E' ? 0 : 255;
		for (size_t i = 0; i < operation.points.size(); ++i)
		{
			const cv::Point& point = operation.points[i];
			if (i == 0)
			{
				const int left = point.x - operation.size / 2;
				const int top = point.y - operation.size / 2;
				const cv::Rect stamp(left, top, operation.size, operation.size);
				const cv::Rect clipped = stamp & bounds;
				if (clipped.area() > 0)
					mask(clipped) = cv::Scalar(value);
			}
			else
			{
				cv::line(mask, operation.points[i - 1], point, cv::Scalar(value),
					operation.size, cv::LINE_8);
			}
		}
	}
	return mask;
}

struct SuperMultiPointCacheEntry
{
	std::wstring path;
	std::wstring seeds;
	std::wstring ignoreData;
	int tolerance = 0;
	ULONGLONG fileSize = 0;
	FILETIME lastWrite = {};
	ULONGLONG lastUse = 0;
	size_t bytes = 0;
	std::shared_ptr<const SuperMultiPointTemplate> data;
};

std::mutex g_superMultiPointCacheMutex;
std::vector<SuperMultiPointCacheEntry> g_superMultiPointCache;
ULONGLONG g_superMultiPointCacheTick = 0;
size_t g_superMultiPointCacheBytes = 0;
constexpr size_t kSuperMultiPointCacheCapacity = 8;
constexpr size_t kSuperMultiPointCacheByteLimit = 512u * 1024u * 1024u;

static bool GetSuperMultiPointFileStamp(const wchar_t* path, ULONGLONG& fileSize, FILETIME& lastWrite)
{
	WIN32_FILE_ATTRIBUTE_DATA data = {};
	if (path == nullptr || !GetFileAttributesExW(path, GetFileExInfoStandard, &data))
		return false;
	fileSize = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
	lastWrite = data.ftLastWriteTime;
	return true;
}

static bool SameSuperMultiPointFileStamp(const SuperMultiPointCacheEntry& entry,
	ULONGLONG fileSize, const FILETIME& lastWrite)
{
	return entry.fileSize == fileSize && CompareFileTime(&entry.lastWrite, &lastWrite) == 0;
}

static size_t GetSuperMultiPointTemplateBytes(const SuperMultiPointTemplate& data)
{
	return sizeof(data)
		+ data.pixels.capacity() * sizeof(EffectivePixel)
		+ data.coarsePoints.capacity() * sizeof(MultiPointSample);
}

static std::shared_ptr<const SuperMultiPointTemplate> BuildSuperMultiPointTemplate(
	const wchar_t* targetPath, const wchar_t* seedPointText, int tolerance,
	const wchar_t* ignoreData)
{
	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(targetPath, bgra, hasAlpha))
	{
		SetImageError(L"模板读取失败：%s", targetPath);
		return nullptr;
	}

	std::vector<MultiPointSample> seeds;
	if (!ParseMultiPointData(seedPointText, seeds))
	{
		SetImageError(L"超多点基准点数据无效");
		return nullptr;
	}
	for (const MultiPointSample& seed : seeds)
	{
		if (seed.x < 0 || seed.y < 0 || seed.x >= bgra.cols || seed.y >= bgra.rows)
		{
			SetImageError(L"基准点坐标越界：(%d,%d) 超出模板 %dx%d",
				seed.x, seed.y, bgra.cols, bgra.rows);
			return nullptr;
		}
		if (hasAlpha && bgra.ptr<uchar>(seed.y)[seed.x * 4 + 3] < 128)
		{
			SetImageError(L"基准点不能落在透明区域：(%d,%d)", seed.x, seed.y);
			return nullptr;
		}
	}

	std::vector<SuperIgnoreOperation> ignoreOperations;
	if (!ParseSuperIgnoreData(ignoreData, ignoreOperations))
	{
		SetImageError(L"超多点忽略蒙版数据无效");
		return nullptr;
	}
	const cv::Mat ignoreMask = BuildSuperIgnoreMask(bgra.cols, bgra.rows, ignoreOperations);

	auto result = std::make_shared<SuperMultiPointTemplate>();
	result->width = bgra.cols;
	result->height = bgra.rows;
	std::vector<EffectivePixel> effective;
	for (int y = 0; y < bgra.rows; ++y)
	{
		const uchar* row = bgra.ptr<uchar>(y);
		for (int x = 0; x < bgra.cols; ++x)
		{
			const uchar* pixel = row + x * 4;
			if (hasAlpha && pixel[3] < 128)
				continue;
			if (!ignoreMask.empty() && ignoreMask.ptr<uchar>(y)[x] != 0)
				continue;

			bool included = false;
			for (const MultiPointSample& seed : seeds)
			{
				if (IsMultiPointColorHit(pixel, seed.bgr, tolerance))
				{
					included = true;
					break;
				}
			}
			if (!included)
				continue;

			effective.push_back({ x, y, cv::Vec3b(pixel[0], pixel[1], pixel[2]) });
		}
	}

	if (effective.empty())
	{
		SetImageError(L"模板中没有符合基准颜色容差的有效像素");
		return nullptr;
	}

	result->pixels = std::move(effective);
	constexpr size_t kColorBucketCount = 1u << 15;
	std::vector<size_t> colorCounts(kColorBucketCount, 0);
	for (const EffectivePixel& pixel : result->pixels)
	{
		const cv::Vec3b& color = pixel.bgr;
		const size_t bucket = (static_cast<size_t>(color[0] >> 3) << 10)
			| (static_cast<size_t>(color[1] >> 3) << 5)
			| static_cast<size_t>(color[2] >> 3);
		++colorCounts[bucket];
	}

	auto colorBucket = [](const cv::Vec3b& color) -> size_t
	{
		return (static_cast<size_t>(color[0] >> 3) << 10)
			| (static_cast<size_t>(color[1] >> 3) << 5)
			| static_cast<size_t>(color[2] >> 3);
	};
	std::stable_sort(result->pixels.begin(), result->pixels.end(),
		[&colorCounts, &colorBucket](const EffectivePixel& a, const EffectivePixel& b)
		{
			return colorCounts[colorBucket(a.bgr)] < colorCounts[colorBucket(b.bgr)];
		});

	std::vector<wchar_t> output(16384, L'\0');
	const int count = AutoSelectImageMultiPoints(
		targetPath, seedPointText, 100, tolerance, ignoreData, output.data(),
		static_cast<int>(output.size()));
	if (count <= 0 || count > 256
		|| !ParseMultiPointData(output.data(), result->coarsePoints))
	{
		if (count >= 0)
			SetImageError(L"超多点自动选点失败");
		return nullptr;
	}

	return result;
}

static std::shared_ptr<const SuperMultiPointTemplate> GetSuperMultiPointTemplate(
	const wchar_t* targetPath, const wchar_t* seedPointText, int tolerance,
	const wchar_t* ignoreData)
{
	const std::wstring path = targetPath ? targetPath : L"";
	const std::wstring seeds = seedPointText ? seedPointText : L"";
	const std::wstring ignored = ignoreData ? ignoreData : L"";
	ULONGLONG fileSize = 0;
	FILETIME lastWrite = {};
	const bool hasStamp = GetSuperMultiPointFileStamp(targetPath, fileSize, lastWrite);

	if (hasStamp)
	{
		std::lock_guard<std::mutex> lock(g_superMultiPointCacheMutex);
		for (SuperMultiPointCacheEntry& entry : g_superMultiPointCache)
		{
			if (entry.path == path && entry.seeds == seeds && entry.ignoreData == ignored
				&& entry.tolerance == tolerance
				&& SameSuperMultiPointFileStamp(entry, fileSize, lastWrite))
			{
				entry.lastUse = ++g_superMultiPointCacheTick;
				return entry.data;
			}
		}
	}

	std::shared_ptr<const SuperMultiPointTemplate> built =
		BuildSuperMultiPointTemplate(targetPath, seedPointText, tolerance, ignoreData);
	if (!built || !hasStamp)
		return built;
	const size_t builtBytes = GetSuperMultiPointTemplateBytes(*built);
	if (builtBytes > kSuperMultiPointCacheByteLimit)
		return built;

	std::lock_guard<std::mutex> lock(g_superMultiPointCacheMutex);
	for (SuperMultiPointCacheEntry& entry : g_superMultiPointCache)
	{
		if (entry.path == path && entry.seeds == seeds && entry.ignoreData == ignored
			&& entry.tolerance == tolerance
			&& SameSuperMultiPointFileStamp(entry, fileSize, lastWrite))
		{
			entry.lastUse = ++g_superMultiPointCacheTick;
			return entry.data;
		}
	}
	while (!g_superMultiPointCache.empty()
		&& (g_superMultiPointCache.size() >= kSuperMultiPointCacheCapacity
			|| g_superMultiPointCacheBytes > kSuperMultiPointCacheByteLimit - builtBytes))
	{
		const auto oldest = std::min_element(g_superMultiPointCache.begin(), g_superMultiPointCache.end(),
			[](const SuperMultiPointCacheEntry& a, const SuperMultiPointCacheEntry& b)
			{
				return a.lastUse < b.lastUse;
			});
		if (oldest != g_superMultiPointCache.end())
		{
			g_superMultiPointCacheBytes -= oldest->bytes;
			g_superMultiPointCache.erase(oldest);
		}
	}
	g_superMultiPointCache.push_back({
		path, seeds, ignored, tolerance,
		fileSize, lastWrite, ++g_superMultiPointCacheTick, builtBytes, built
	});
	g_superMultiPointCacheBytes += builtBytes;
	return built;
}

static bool HasRequiredEffectivePixelHits(const cv::Mat& shotBgr,
	const std::vector<EffectivePixel>& pixels, int x, int y,
	int tolerance, int required)
{
	int hits = 0;
	for (size_t i = 0; i < pixels.size(); ++i)
	{
		const EffectivePixel& point = pixels[i];
		const uchar* pixel = shotBgr.ptr<uchar>(y + point.y) + (x + point.x) * 3;
		if (IsMultiPointColorHit(pixel, point.bgr, tolerance))
			++hits;
		if (hits >= required)
			return true;
		if (hits + static_cast<int>(pixels.size() - i - 1) < required)
			return false;
	}
	return false;
}

static int FindImageMultiPointSuperCore(const wchar_t* targetPath, const cv::Mat& shot,
	int matchThreshold, const wchar_t* seedPointText, int tolerance,
	const wchar_t* ignoreData, int* x, int* y)
{
	matchThreshold = std::max(0, std::min(100, matchThreshold));
	tolerance = std::max(0, std::min(255, tolerance));
	const auto target = GetSuperMultiPointTemplate(targetPath, seedPointText, tolerance, ignoreData);
	if (!target)
		return -4;
	if (shot.empty())
	{
		SetImageError(L"截图失败：搜索区域为空");
		return -5;
	}
	if (target->width > shot.cols || target->height > shot.rows)
	{
		SetImageError(L"模板尺寸(%dx%d)大于搜索区域(%dx%d)",
			target->width, target->height, shot.cols, shot.rows);
		return -2;
	}

	cv::Mat shotBgr;
	if (shot.channels() == 4)
		cv::cvtColor(shot, shotBgr, cv::COLOR_BGRA2BGR);
	else if (shot.channels() == 3)
		shotBgr = shot;
	else
	{
		SetImageError(L"截图格式无效：需要 BGR 或 BGRA");
		return -5;
	}

	const std::vector<MultiPointSample>& points = target->coarsePoints;
	const size_t pointCount = points.size();
	if (pointCount == 0 || pointCount > 256)
	{
		SetImageError(L"超多点自动点位无效");
		return -4;
	}

	const size_t pixelCount = target->pixels.size();
	const int required = std::max(1, static_cast<int>(
		std::ceil(static_cast<double>(pixelCount) * matchThreshold / 100.0)));
	const int coarseThreshold = std::max(1, matchThreshold - 10);
	const int coarseRequired = std::max(1, static_cast<int>(
		std::ceil(static_cast<double>(pointCount) * coarseThreshold / 100.0)));
	const size_t anchorCount = pointCount - static_cast<size_t>(coarseRequired) + 1;
	const size_t firstAnchor = pointCount - anchorCount;
	const int candidateCols = shot.cols - target->width + 1;
	const int candidateRows = shot.rows - target->height + 1;
	cv::Mat tested(candidateRows, candidateCols, CV_8UC1, cv::Scalar(0));
	constexpr int kRefineRadius = 2;

	for (int row = 0; row < candidateRows; ++row)
	{
		for (int col = 0; col < candidateCols; ++col)
		{
			bool anchorHit = false;
			for (size_t i = firstAnchor; i < pointCount; ++i)
			{
				const MultiPointSample& point = points[i];
				const uchar* pixel = shotBgr.ptr<uchar>(row + point.y) + (col + point.x) * 3;
				if (IsMultiPointColorHit(pixel, point.bgr, tolerance))
				{
					anchorHit = true;
					break;
				}
			}
			if (!anchorHit)
				continue;

			int hits = 0;
			for (size_t i = 0; i < pointCount; ++i)
			{
				const MultiPointSample& point = points[i];
				const uchar* pixel = shotBgr.ptr<uchar>(row + point.y) + (col + point.x) * 3;
				if (IsMultiPointColorHit(pixel, point.bgr, tolerance))
					++hits;
				if (hits + static_cast<int>(pointCount - i - 1) < coarseRequired)
					break;
			}
			if (hits < coarseRequired)
				continue;

			const int left = std::max(0, col - kRefineRadius);
			const int top = std::max(0, row - kRefineRadius);
			const int right = std::min(candidateCols, col + kRefineRadius + 1);
			const int bottom = std::min(candidateRows, row + kRefineRadius + 1);
			for (int verifyY = top; verifyY < bottom; ++verifyY)
			{
				uchar* testedRow = tested.ptr<uchar>(verifyY);
				for (int verifyX = left; verifyX < right; ++verifyX)
				{
					if (testedRow[verifyX] != 0)
						continue;
					testedRow[verifyX] = 255;
					if (HasRequiredEffectivePixelHits(shotBgr, target->pixels,
						verifyX, verifyY, tolerance, required))
					{
						*x = verifyX;
						*y = verifyY;
						return 1;
					}
				}
			}
		}
	}

	SetImageError(L"超多点未命中：有效像素 %d，要求至少命中 %d",
		static_cast<int>(pixelCount), required);
	return 0;
}
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageMultiPointSuper(
	const wchar_t* targetPath, int searchX, int searchY, int searchW, int searchH,
	int matchThreshold, const wchar_t* seedPoints, int tolerance,
	const wchar_t* ignoreData, int* x, int* y)
{
	ClearImageError();
	if (targetPath == nullptr || x == nullptr || y == nullptr || searchW <= 0 || searchH <= 0)
	{
		SetImageError(L"参数非法：模板路径、坐标指针和搜索区域必须有效");
		return -6;
	}
	*x = 0;
	*y = 0;
	try
	{
		const cv::Mat shot = captureScreen(searchX, searchY, searchW, searchH);
		const int ret = FindImageMultiPointSuperCore(
			targetPath, shot, matchThreshold, seedPoints, tolerance, ignoreData, x, y);
		if (ret == 1)
		{
			*x += searchX;
			*y += searchY;
			ClearImageError();
		}
		return ret;
	}
	catch (const cv::Exception& ex)
	{
		SetImageError(L"OpenCV 超多点匹配异常：%hs", ex.what());
		return -3;
	}
	catch (...)
	{
		SetImageError(L"超多点匹配异常");
		return -3;
	}
}

extern "C" IMAGEFINDER_API int __cdecl FindWinImageMultiPointSuper(
	const wchar_t* targetPath, int hwnd, int searchX, int searchY, int searchW, int searchH,
	int matchThreshold, const wchar_t* seedPoints, int tolerance,
	const wchar_t* ignoreData, int* x, int* y)
{
	ClearImageError();
	if (targetPath == nullptr || x == nullptr || y == nullptr || hwnd == 0
		|| searchW <= 0 || searchH <= 0)
	{
		SetImageError(L"参数非法：模板路径、窗口句柄、坐标指针和搜索区域必须有效");
		return -6;
	}
	*x = 0;
	*y = 0;
	try
	{
		const cv::Mat shot = captureScreen(hwnd, searchX, searchY, searchW, searchH);
		const int ret = FindImageMultiPointSuperCore(
			targetPath, shot, matchThreshold, seedPoints, tolerance, ignoreData, x, y);
		if (ret == 1)
		{
			*x += searchX;
			*y += searchY;
			ClearImageError();
		}
		return ret;
	}
	catch (const cv::Exception& ex)
	{
		SetImageError(L"OpenCV 窗口超多点匹配异常：%hs", ex.what());
		return -3;
	}
	catch (...)
	{
		SetImageError(L"窗口超多点匹配异常");
		return -3;
	}
}

namespace
{
struct AutoPointCandidate
{
	MultiPointSample point;
	int group = -1;
	int colorFrequency = 0;
	int localGradient = 0;
};

static bool BetterAutoPoint(const AutoPointCandidate& a, const AutoPointCandidate& b)
{
	if (a.colorFrequency != b.colorFrequency)
		return a.colorFrequency < b.colorFrequency;
	if (a.localGradient != b.localGradient)
		return a.localGradient < b.localGradient;
	if (a.point.y != b.point.y)
		return a.point.y < b.point.y;
	return a.point.x < b.point.x;
}

static int CountColorsWithinTolerance(const cv::Vec3b& color, int tolerance,
	const std::vector<int>& prefix, int prefixSide)
{
	const int binCount = prefixSide - 1;
	int low[3], high[3];
	for (int channel = 0; channel < 3; ++channel)
	{
		low[channel] = std::max(0, static_cast<int>(color[channel]) - tolerance) / 4;
		high[channel] = std::min(binCount - 1,
			std::min(255, static_cast<int>(color[channel]) + tolerance) / 4);
	}
	auto at = [prefixSide, &prefix](int r, int g, int b) -> int
	{
		return prefix[(static_cast<size_t>(r) * prefixSide + g) * prefixSide + b];
	};
	const int x0 = low[2], x1 = high[2] + 1;
	const int y0 = low[1], y1 = high[1] + 1;
	const int z0 = low[0], z1 = high[0] + 1;
	return at(x1, y1, z1) - at(x0, y1, z1) - at(x1, y0, z1) - at(x1, y1, z0)
		+ at(x0, y0, z1) + at(x0, y1, z0) + at(x1, y0, z0) - at(x0, y0, z0);
}

static bool IsOpaquePixel(const cv::Mat& tpl, bool hasAlpha, int x, int y)
{
	return !hasAlpha || tpl.ptr<uchar>(y)[x * 4 + 3] >= 128;
}

static int LocalColorGradient(const cv::Mat& tpl, bool hasAlpha, int x, int y,
	int left, int top, int right, int bottom)
{
	const uchar* center = tpl.ptr<uchar>(y) + x * 4;
	int total = 0;
	int samples = 0;
	for (int dy = -1; dy <= 1; ++dy)
	{
		for (int dx = -1; dx <= 1; ++dx)
		{
			if (dx == 0 && dy == 0)
				continue;
			const int nx = x + dx, ny = y + dy;
			if (nx < left || nx >= right || ny < top || ny >= bottom
				|| !IsOpaquePixel(tpl, hasAlpha, nx, ny))
				continue;
			const uchar* neighbor = tpl.ptr<uchar>(ny) + nx * 4;
			total += std::abs(static_cast<int>(center[0]) - neighbor[0])
				+ std::abs(static_cast<int>(center[1]) - neighbor[1])
				+ std::abs(static_cast<int>(center[2]) - neighbor[2]);
			++samples;
		}
	}
	return samples > 0 ? total / (samples * 3) : 255;
}

static bool IsFarEnoughFromPoints(const MultiPointSample& candidate,
	const std::vector<MultiPointSample>& points, int minSpacingSquared)
{
	for (const MultiPointSample& point : points)
	{
		const long long dx = static_cast<long long>(candidate.x) - point.x;
		const long long dy = static_cast<long long>(candidate.y) - point.y;
		if (dx * dx + dy * dy < minSpacingSquared)
			return false;
	}
	return true;
}

// 返回像素最接近的基准颜色组。这里直接逐像素比较，不生成整张 mask。
static int MatchSeedColor(const cv::Vec3b& color,
	const std::vector<MultiPointSample>& seeds, int tolerance, int* distance)
{
	int bestGroup = -1;
	int bestDistance = INT_MAX;
	for (size_t i = 0; i < seeds.size(); ++i)
	{
		const int db = std::abs(static_cast<int>(color[0]) - static_cast<int>(seeds[i].bgr[0]));
		const int dg = std::abs(static_cast<int>(color[1]) - static_cast<int>(seeds[i].bgr[1]));
		const int dr = std::abs(static_cast<int>(color[2]) - static_cast<int>(seeds[i].bgr[2]));
		if (db > tolerance || dg > tolerance || dr > tolerance)
			continue;
		const int currentDistance = db * db + dg * dg + dr * dr;
		if (currentDistance < bestDistance)
		{
			bestDistance = currentDistance;
			bestGroup = static_cast<int>(i);
		}
	}
	if (distance != nullptr)
		*distance = (bestGroup >= 0) ? bestDistance : INT_MAX;
	return bestGroup;
}

static std::wstring SerializeMultiPoints(const std::vector<MultiPointSample>& points)
{
	std::wstring text;
	for (const MultiPointSample& point : points)
	{
		wchar_t item[64] = {};
		swprintf_s(item, _countof(item), L"%d,%d,%02X%02X%02X",
			point.x, point.y, point.bgr[2], point.bgr[1], point.bgr[0]);
		if (!text.empty())
			text += L';';
		text += item;
	}
	return text;
}
}

static bool ApplySeedColorPreview(cv::Mat& scaled, const cv::Mat& sourceView,
	const wchar_t* seedPointText, int tolerance, int zoomPercent)
{
	if (seedPointText == nullptr || seedPointText[0] == L'\0')
		return true;

	std::vector<MultiPointSample> seeds;
	if (!ParseMultiPointData(seedPointText, seeds))
	{
		SetImageError(L"预览基准点数据无效");
		return false;
	}

	tolerance = std::max(0, std::min(255, tolerance));
	std::vector<cv::Vec3b> seedColors;
	seedColors.reserve(seeds.size());
	for (const MultiPointSample& seed : seeds)
	{
		const bool alreadyAdded = std::any_of(seedColors.begin(), seedColors.end(),
			[&seed](const cv::Vec3b& color)
			{
				return color[0] == seed.bgr[0] && color[1] == seed.bgr[1] && color[2] == seed.bgr[2];
			});
		if (!alreadyAdded)
			seedColors.push_back(seed.bgr);
	}

	cv::Mat mask(sourceView.rows, sourceView.cols, CV_8UC1, cv::Scalar(0));
	for (int y = 0; y < sourceView.rows; ++y)
	{
		const uchar* src = sourceView.ptr<uchar>(y);
		uchar* maskRow = mask.ptr<uchar>(y);
		for (int x = 0; x < sourceView.cols; ++x)
		{
			const uchar* pixel = src + x * 4;
			if (pixel[3] < 128)
				continue;
			for (const cv::Vec3b& seedColor : seedColors)
			{
				if (std::abs(static_cast<int>(pixel[0]) - seedColor[0]) <= tolerance
					&& std::abs(static_cast<int>(pixel[1]) - seedColor[1]) <= tolerance
					&& std::abs(static_cast<int>(pixel[2]) - seedColor[2]) <= tolerance)
				{
					maskRow[x] = 255;
					break;
				}
			}
		}
	}

	cv::Mat scaledMask;
	const int interpolation = zoomPercent < 100 ? cv::INTER_AREA : cv::INTER_NEAREST;
	cv::resize(mask, scaledMask, scaled.size(), 0, 0, interpolation);
	for (int y = 0; y < scaled.rows; ++y)
	{
		uchar* pixels = scaled.ptr<uchar>(y);
		const uchar* maskRow = scaledMask.ptr<uchar>(y);
		for (int x = 0; x < scaled.cols; ++x)
		{
			const double brightness = 0.28 + 0.72 * (maskRow[x] / 255.0);
			uchar* pixel = pixels + x * 4;
			pixel[0] = cv::saturate_cast<uchar>(pixel[0] * brightness);
			pixel[1] = cv::saturate_cast<uchar>(pixel[1] * brightness);
			pixel[2] = cv::saturate_cast<uchar>(pixel[2] * brightness);
		}
	}
	return true;
}

extern "C" IMAGEFINDER_API int __cdecl AutoSelectImageMultiPoints(
	const wchar_t* targetPath, const wchar_t* existingPoints, int density,
	int tolerance, const wchar_t* ignoreData, wchar_t* output, int outputCapacity)
{
	ClearImageError();
	if (targetPath == nullptr || output == nullptr || outputCapacity <= 1)
	{
		SetImageError(L"参数非法：模板路径或输出缓冲区无效");
		return -6;
	}
	output[0] = L'\0';
	density = std::max(0, std::min(100, density));
	tolerance = std::max(0, std::min(255, tolerance));

	try
	{
		cv::Mat tpl;
		bool hasAlpha = false;
		if (!LoadTemplateBgra(targetPath, tpl, hasAlpha))
		{
			SetImageError(L"模板读取失败：%s", targetPath);
			return -1;
		}

		std::vector<SuperIgnoreOperation> ignoreOperations;
		if (!ParseSuperIgnoreData(ignoreData, ignoreOperations))
		{
			SetImageError(L"忽略蒙版数据无效");
			return -4;
		}
		const cv::Mat ignoreMask = BuildSuperIgnoreMask(tpl.cols, tpl.rows, ignoreOperations);

		std::vector<MultiPointSample> selected;
		if (existingPoints != nullptr && existingPoints[0] != L'\0'
			&& !ParseMultiPointData(existingPoints, selected))
		{
			SetImageError(L"已有多点数据格式无效");
			return -4;
		}
		if (selected.empty())
		{
			SetImageError(L"自动选点前请先选择一个基准点");
			return -4;
		}
		for (const MultiPointSample& point : selected)
		{
			if (point.x < 0 || point.y < 0 || point.x >= tpl.cols || point.y >= tpl.rows)
			{
				SetImageError(L"已有点位越界：(%d,%d)", point.x, point.y);
				return -4;
			}
			if (!IsOpaquePixel(tpl, hasAlpha, point.x, point.y))
			{
				SetImageError(L"已有点位落在透明区域：(%d,%d)", point.x, point.y);
				return -4;
			}
		}

		const std::vector<MultiPointSample> seedColors = selected;
		selected.erase(std::remove_if(selected.begin(), selected.end(),
			[&ignoreMask](const MultiPointSample& point)
			{
				return !ignoreMask.empty() && ignoreMask.ptr<uchar>(point.y)[point.x] != 0;
			}), selected.end());

		const int seedCount = static_cast<int>(seedColors.size());
		int left = tpl.cols, top = tpl.rows, right = 0, bottom = 0;
		std::vector<int> groupCounts(static_cast<size_t>(seedCount), 0);
		constexpr int colorBinCount = 64;
		constexpr int colorPrefixSide = colorBinCount + 1;
		std::vector<int> histogram(static_cast<size_t>(colorBinCount) * colorBinCount * colorBinCount, 0);
		int eligiblePixels = 0;

		// 第一遍只统计各基准颜色组和有效区域，不建立 mask。
		for (int y = 0; y < tpl.rows; ++y)
		{
			const uchar* row = tpl.ptr<uchar>(y);
			for (int x = 0; x < tpl.cols; ++x)
			{
				const uchar* pixel = row + x * 4;
				if (hasAlpha && pixel[3] < 128)
					continue;
				if (!ignoreMask.empty() && ignoreMask.ptr<uchar>(y)[x] != 0)
					continue;
				const cv::Vec3b color(pixel[0], pixel[1], pixel[2]);
				const int group = MatchSeedColor(color, seedColors, tolerance, nullptr);
				if (group >= 0)
				{
					++groupCounts[static_cast<size_t>(group)];
					++eligiblePixels;
					left = std::min(left, x);
					top = std::min(top, y);
					right = std::max(right, x + 1);
					bottom = std::max(bottom, y + 1);
				}
				if (!hasAlpha || pixel[3] >= 128)
				{
					const int b = pixel[0] / 4, g = pixel[1] / 4, r = pixel[2] / 4;
					++histogram[(static_cast<size_t>(r) * colorBinCount + g) * colorBinCount + b];
				}
			}
		}

		if (eligiblePixels <= 0 || right <= left || bottom <= top)
		{
			SetImageError(L"模板中没有落在任一基准颜色容差内的像素");
			return -4;
		}

		if (density == 100 && eligiblePixels <= 256)
		{
			std::vector<MultiPointSample> allEligible;
			allEligible.reserve(static_cast<size_t>(eligiblePixels));
			for (int y = 0; y < tpl.rows; ++y)
			{
				const uchar* row = tpl.ptr<uchar>(y);
				for (int x = 0; x < tpl.cols; ++x)
				{
					const uchar* pixel = row + x * 4;
					if (hasAlpha && pixel[3] < 128)
						continue;
					if (!ignoreMask.empty() && ignoreMask.ptr<uchar>(y)[x] != 0)
						continue;
					const cv::Vec3b color(pixel[0], pixel[1], pixel[2]);
					if (MatchSeedColor(color, seedColors, tolerance, nullptr) >= 0)
						allEligible.push_back({ x, y, color });
				}
			}
			const std::wstring serialized = SerializeMultiPoints(allEligible);
			if (serialized.size() + 1 > static_cast<size_t>(outputCapacity))
			{
				SetImageError(L"输出缓冲区不足");
				return -6;
			}
			wcscpy_s(output, outputCapacity, serialized.c_str());
			ClearImageError();
			return static_cast<int>(allEligible.size());
		}

		// 颜色频率前缀表只用于候选排序，不是参与筛选或搜索的像素 mask。
		std::vector<int> colorPrefix(static_cast<size_t>(colorPrefixSide)
			* colorPrefixSide * colorPrefixSide, 0);
		auto prefixAt = [&colorPrefix, colorPrefixSide](int r, int g, int b) -> int&
		{
			return colorPrefix[(static_cast<size_t>(r) * colorPrefixSide + g) * colorPrefixSide + b];
		};
		for (int r = 1; r <= colorBinCount; ++r)
		{
			for (int g = 1; g <= colorBinCount; ++g)
			{
				for (int b = 1; b <= colorBinCount; ++b)
				{
					const int value = histogram[(static_cast<size_t>(r - 1) * colorBinCount + (g - 1))
						* colorBinCount + (b - 1)];
					prefixAt(r, g, b) = value + prefixAt(r - 1, g, b) + prefixAt(r, g - 1, b)
						+ prefixAt(r, g, b - 1) - prefixAt(r - 1, g - 1, b)
						- prefixAt(r - 1, g, b - 1) - prefixAt(r, g - 1, b - 1)
						+ prefixAt(r - 1, g - 1, b - 1);
				}
			}
		}

		const int width = right - left, height = bottom - top;
		const int area = std::max(1, width * height);
		const int maxPointCount = std::max(static_cast<int>(selected.size()),
			std::min(256, eligiblePixels));
		const int targetCount = static_cast<int>(selected.size())
			+ static_cast<int>(std::round((maxPointCount - selected.size()) * density / 100.0));
		if (static_cast<int>(selected.size()) >= targetCount)
		{
			const std::wstring serialized = SerializeMultiPoints(selected);
			if (serialized.size() + 1 > static_cast<size_t>(outputCapacity))
			{
				SetImageError(L"输出缓冲区不足");
				return -6;
			}
			wcscpy_s(output, outputCapacity, serialized.c_str());
			ClearImageError();
			return static_cast<int>(selected.size());
		}

		const double desiredSpacing = std::sqrt(static_cast<double>(area)
			/ std::max(1, targetCount)) * (0.45 + (100 - density) / 220.0);
		const int minSpacing = std::max(1, static_cast<int>(std::round(desiredSpacing)));
		int gridCols = static_cast<int>(std::ceil(std::sqrt(targetCount
			* (static_cast<double>(width) / std::max(1, height)))));
		gridCols = std::max(1, std::min(targetCount, gridCols));
		const int gridRows = std::max(1, static_cast<int>(std::ceil(
			static_cast<double>(targetCount) / gridCols)));
		const int cells = gridCols * gridRows;
		const int sampleStep = std::max(1, static_cast<int>(std::ceil(
			std::sqrt(static_cast<double>(area) / 1500000.0))));
		const size_t candidatesPerCell = static_cast<size_t>(std::max(8,
			std::min(24, targetCount / 3 + 4)));
		std::vector<std::vector<AutoPointCandidate>> buckets(
			static_cast<size_t>(seedCount) * cells);

		// 第二遍仍然只逐像素比较基准色；候选按颜色组和空间单元保存。
		for (int y = top; y < bottom; y += sampleStep)
		{
			const uchar* row = tpl.ptr<uchar>(y);
			for (int x = left; x < right; x += sampleStep)
			{
				const uchar* pixel = row + x * 4;
				if (hasAlpha && pixel[3] < 128)
					continue;
				if (!ignoreMask.empty() && ignoreMask.ptr<uchar>(y)[x] != 0)
					continue;
				const cv::Vec3b color(pixel[0], pixel[1], pixel[2]);
				const int group = MatchSeedColor(color, seedColors, tolerance, nullptr);
				if (group < 0)
					continue;
				const int cellX = std::min(gridCols - 1, (x - left) * gridCols / width);
				const int cellY = std::min(gridRows - 1, (y - top) * gridRows / height);
				const int cell = cellY * gridCols + cellX;
				AutoPointCandidate candidate = {
					{ x, y, color }, group, groupCounts[static_cast<size_t>(group)],
					LocalColorGradient(tpl, hasAlpha, x, y, left, top, right, bottom)
				};
				candidate.colorFrequency = CountColorsWithinTolerance(color, tolerance,
					colorPrefix, colorPrefixSide);
				auto& bucket = buckets[static_cast<size_t>(group) * cells + cell];
				auto position = std::lower_bound(bucket.begin(), bucket.end(), candidate, BetterAutoPoint);
				if (position != bucket.end() || bucket.size() < candidatesPerCell)
				{
					bucket.insert(position, candidate);
					if (bucket.size() > candidatesPerCell)
						bucket.pop_back();
				}
			}
		}

		for (int group = 0; group < seedCount; ++group)
		{
			for (int cell = 0; cell < cells; ++cell)
			{
				auto& bucket = buckets[static_cast<size_t>(group) * cells + cell];
				std::sort(bucket.begin(), bucket.end(), BetterAutoPoint);
			}
		}

		int extra = targetCount - static_cast<int>(selected.size());
		std::vector<int> quotas(static_cast<size_t>(seedCount), 0);
		std::vector<double> fractions(static_cast<size_t>(seedCount), 0.0);
		int quotaTotal = 0;
		for (int group = 0; group < seedCount; ++group)
		{
			if (groupCounts[static_cast<size_t>(group)] <= 0)
				continue;
			const double exact = extra * static_cast<double>(groupCounts[static_cast<size_t>(group)])
				/ std::max(1, eligiblePixels);
			quotas[static_cast<size_t>(group)] = static_cast<int>(std::floor(exact));
			fractions[static_cast<size_t>(group)] = exact - quotas[static_cast<size_t>(group)];
			quotaTotal += quotas[static_cast<size_t>(group)];
		}
		while (quotaTotal < extra)
		{
			int bestGroup = -1;
			for (int group = 0; group < seedCount; ++group)
				if (groupCounts[static_cast<size_t>(group)] > 0
					&& (bestGroup < 0 || fractions[static_cast<size_t>(group)] > fractions[static_cast<size_t>(bestGroup)]))
					bestGroup = group;
			if (bestGroup < 0)
				break;
			++quotas[static_cast<size_t>(bestGroup)];
			fractions[static_cast<size_t>(bestGroup)] = 0.0;
			++quotaTotal;
		}
		// 只要还有足够的新增点，保证每个颜色组至少拿到一个自动点。
		if (extra >= seedCount)
		{
			for (int group = 0; group < seedCount; ++group)
			{
				if (groupCounts[static_cast<size_t>(group)] <= 0 || quotas[static_cast<size_t>(group)] > 0)
					continue;
				int donor = -1;
				for (int other = 0; other < seedCount; ++other)
					if (quotas[static_cast<size_t>(other)] > 1
						&& (donor < 0 || quotas[static_cast<size_t>(other)] > quotas[static_cast<size_t>(donor)]))
						donor = other;
				if (donor < 0)
					break;
				--quotas[static_cast<size_t>(donor)];
				++quotas[static_cast<size_t>(group)];
			}
		}

		// 轮流遍历空间单元和颜色组，避免高评分候选集中在同一片区域。
		auto selectWithSpacing = [&](int spacing, bool respectQuotas) {
			bool anyAdded = false;
			bool passAdded = true;
			while (passAdded && static_cast<int>(selected.size()) < targetCount)
			{
				passAdded = false;
				for (int cell = 0; cell < cells && static_cast<int>(selected.size()) < targetCount; ++cell)
				{
					for (int group = 0; group < seedCount && static_cast<int>(selected.size()) < targetCount; ++group)
					{
						int& quota = quotas[static_cast<size_t>(group)];
						if (groupCounts[static_cast<size_t>(group)] <= 0
							|| (respectQuotas && quota <= 0))
							continue;

						auto& bucket = buckets[static_cast<size_t>(group) * cells + cell];
						for (const AutoPointCandidate& candidate : bucket)
						{
							if (!IsFarEnoughFromPoints(candidate.point, selected, spacing * spacing))
								continue;
							selected.push_back(candidate.point);
							if (respectQuotas)
								--quota;
							passAdded = true;
							anyAdded = true;
							break;
						}
					}
				}
			}
			return anyAdded;
		};
		selectWithSpacing(minSpacing, true);
		selectWithSpacing(std::max(1, minSpacing / 2), true);
		selectWithSpacing(1, true);
		if (static_cast<int>(selected.size()) < targetCount)
			selectWithSpacing(1, false);

		const std::wstring serialized = SerializeMultiPoints(selected);
		if (serialized.size() + 1 > static_cast<size_t>(outputCapacity))
		{
			SetImageError(L"输出缓冲区不足");
			return -6;
		}
		wcscpy_s(output, outputCapacity, serialized.c_str());
		ClearImageError();
		return static_cast<int>(selected.size());
	}
	catch (const cv::Exception& ex)
	{
		SetImageError(L"OpenCV 自动选点异常：%hs", ex.what());
		return -3;
	}
	catch (...)
	{
		SetImageError(L"自动选点异常");
		return -3;
	}
}
