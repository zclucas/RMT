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
#include <cstdlib>
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
	SelectObject(hCaptureDC, hBitmap);

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
	GetDIBits(hCaptureDC, hBitmap, 0, height, mat.data, (BITMAPINFO*)&bi, DIB_RGB_COLORS);

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

    ThumbnailCache* cache = GetOrCreateCache(targetHwnd);
    if (!cache) return cv::Mat();

    HWND dstWin = cache->dstWin;
    HTHUMBNAIL thumbnail = cache->thumbnail;

    // 客户区尺寸：缩略图源/目的都用客户区，与 AHK 侧 ScreenToClient 客户区坐标严格 1:1。
    // 目的若仍用整窗尺寸，客户区内容会被拉伸到整窗大小，造成残差偏移（#266 只修了裁剪区域，没修目的尺寸）。
    RECT clientRect;
    if (!GetClientRect(targetHwnd, &clientRect))
        return cv::Mat();
    const long clientW = clientRect.right - clientRect.left;
    const long clientH = clientRect.bottom - clientRect.top;
    if (clientW <= 0 || clientH <= 0)
        return cv::Mat();

    // 菜单栏高度补偿：DWM 客户区含菜单栏，AHK 客户区不含，源区域需从菜单栏下方开始
    const int menuH = GetMenuBarHeight(targetHwnd);

    // IsIconic 时 DWM 缩略图有内部偏移，需要补偿
    const int offset = IsIconic(targetHwnd) ? 8 : 0;

    SetWindowPos(dstWin, nullptr, 0, 0, clientW, clientH,
        SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOZORDER);

    DWM_THUMBNAIL_PROPERTIES props;
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

        GetDIBits(cDC, cBmp, 0, clientH, result.data, &bi, DIB_RGB_COLORS);

        // 裁剪指定区域
        const long capWidth = (width <= 0) ? clientW : width;
        const long capHeight = (height <= 0) ? clientH : height;
        if ((x > 0 || y > 0 || capWidth < clientW || capHeight < clientH)
            && x >= 0 && y >= 0 && x + capWidth <= clientW && y + capHeight <= clientH) {
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

	// 通道数不一致时统一（4 通道 PNG 模板 + 3 通道截屏会让 matchTemplate 直接断言失败，
	// 相似度 ≥95 不走灰度的那条分支最容易踩到）
	if (templateImage.channels() != capturedImage.channels())
	{
		if (templateImage.channels() == 4 && capturedImage.channels() == 3)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGRA2BGR);
		else if (templateImage.channels() == 3 && capturedImage.channels() == 4)
			cv::cvtColor(templateImage, templateImage, cv::COLOR_BGR2BGRA);
	}

	// 2. 转换为灰度图（提高处理速度）
	cv::Mat grayLarge, graySmall;
	// 相似度95及其以上，不做灰度处理
	if (matchThreshold >= 95)
	{
		grayLarge = capturedImage;
		graySmall = templateImage;
	}
	else
	{
		cv::cvtColor(capturedImage, grayLarge, cv::COLOR_BGR2GRAY);
		cv::cvtColor(templateImage, graySmall, cv::COLOR_BGR2GRAY);
	}

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

	// 3. 转灰度（非高分相似度）
	cv::Mat grayLarge, graySmall;
	if (matchThreshold >= 95)
	{
		grayLarge = capturedImage;
		graySmall = templateImage;
	}
	else
	{
		cv::cvtColor(capturedImage, grayLarge, cv::COLOR_BGR2GRAY);
		cv::cvtColor(templateImage, graySmall, cv::COLOR_BGR2GRAY);
	}

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
	return 3;   // 2 = 自适应匹配；3 = 加了边缘图比例判断 + 原分辨率细调
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
