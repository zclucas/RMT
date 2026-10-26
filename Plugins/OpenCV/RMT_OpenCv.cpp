#include "RMT_OpenCv.h"
#include <opencv2/opencv.hpp>
#include <windows.h>
#include <dwmapi.h>
#include <unordered_map>
#include <vector>
#include <string>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cwchar>
#pragma comment(lib, "Dwmapi.lib")

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
		max(0, b - tol),
		max(0, g - tol),
		max(0, r - tol)
	);

	cv::Scalar upper(
		min(255, b + tol),
		min(255, g + tol),
		min(255, r + tol)
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

// ===========================================================================
// 滤色找图
//   在常规模板匹配的基础上，允许指定若干颜色当作通配符忽略掉，
//   只比对模板中"非滤色"的像素。用于模板里混入背景色/渐变光效的场景。
//
//   为什么用 TM_SQDIFF_NORMED 而不是 CCOEFF_NORMED：
//     OpenCV 的掩码匹配（matchTemplateMask）对 6 种方法都支持，CCOEFF_NORMED
//     也在内。但它在模板有效区方差≈0 时会走 norm_templx < DBL_EPSILON 分支，
//     直接 result = Scalar::all(1)，表现为"任意位置都 100% 命中"；
//     而 SQDIFF_NORMED 的同类退化表现为 NaN，可以被检测出来并报错。
//     "滤掉大部分背景后只剩一小块纯色"恰恰是滤色功能的典型用法，
//     所以这里选可检测退化的 SQDIFF_NORMED。
//   相似度换算：similarity = (1 - sqrt(R)) * 100，与 UI 的 50~100 同量纲。
// ===========================================================================

// 上一次错误描述（宽字符，供 AHK 用 StrGet 读取）
static wchar_t g_filterLastError[512] = L"";

static void ClearFilterError()
{
	g_filterLastError[0] = L'\0';
}

static void SetFilterError(const wchar_t* fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	_vsnwprintf_s(g_filterLastError, _countof(g_filterLastError), _TRUNCATE, fmt, args);
	va_end(args);
}

extern "C" IMAGEFINDER_API const wchar_t* __cdecl GetFilterLastError()
{
	return g_filterLastError;
}

// 按 UTF-16 路径读取文件全部字节（绕过 imread 对非 ASCII 路径的限制）
static bool ReadAllBytesW(const wchar_t* path, std::vector<uchar>& out)
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

// 解析 "RRGGBB,RRGGBB" / "#RRGGBB" / "0xRRGGBB"（宽字符）
// 结果以 BGR 顺序存入 colors，与 cv::Vec3b 的内存布局一致。
static size_t ParseFilterColors(const wchar_t* text, std::vector<cv::Vec3b>& colors)
{
	colors.clear();
	if (text == nullptr)
		return 0;

	const std::wstring all(text);
	size_t pos = 0;

	while (pos <= all.size())
	{
		size_t sep = all.find_first_of(L",;| \t\r\n", pos);
		if (sep == std::wstring::npos)
			sep = all.size();

		std::wstring token = all.substr(pos, sep - pos);
		pos = sep + 1;

		// 去掉首尾空白
		const size_t b = token.find_first_not_of(L" \t");
		if (b == std::wstring::npos)
			continue;
		const size_t e = token.find_last_not_of(L" \t");
		token = token.substr(b, e - b + 1);

		if (!token.empty() && token[0] == L'#')
			token = token.substr(1);
		else if (token.size() > 2 && token[0] == L'0' && (token[1] == L'x' || token[1] == L'X'))
			token = token.substr(2);

		if (token.size() != 6)
			continue;

		wchar_t* endPtr = nullptr;
		const unsigned long packed = wcstoul(token.c_str(), &endPtr, 16);
		if (endPtr == nullptr || *endPtr != L'\0' || packed > 0xFFFFFFUL)
			continue;

		const uchar r = static_cast<uchar>((packed >> 16) & 0xFF);
		const uchar g = static_cast<uchar>((packed >> 8) & 0xFF);
		const uchar b2 = static_cast<uchar>(packed & 0xFF);
		colors.push_back(cv::Vec3b(b2, g, r));
	}

	return colors.size();
}

// ---------------------------------------------------------------------------
// 共用：颜色是否命中（每通道 |差| <= tol）
//   滤色判据必须唯一：搜索、掩膜、预览三处都用这一个函数，避免逐像素不一致。
// ---------------------------------------------------------------------------
static inline bool IsColorHit(int b, int g, int r, const cv::Vec3b& target, int tolerance)
{
	const int db = b - static_cast<int>(target[0]);
	const int dg = g - static_cast<int>(target[1]);
	const int dr = r - static_cast<int>(target[2]);
	return db >= -tolerance && db <= tolerance
		&& dg >= -tolerance && dg <= tolerance
		&& dr >= -tolerance && dr <= tolerance;
}

// ---------------------------------------------------------------------------
// 共用：构建 0/255 掩码（255=参与匹配）
//   hasAlpha 为真时，alpha<128 的像素一律剔除（支持透明 PNG 模板）
//   mode 0 = 排除：选中的颜色被忽略，其余参与（默认全参与）
//   mode 1 = 保留：只有选中的颜色参与，其余全部忽略（未选颜色时退化为全参与）
// ---------------------------------------------------------------------------
static cv::Mat BuildFilterMask(const cv::Mat& bgra, bool hasAlpha,
	const std::vector<cv::Vec3b>& colors, int tolerance, int mode)
{
	const bool keepMode = (mode == 1);
	const bool noColors = colors.empty();

	// 保留模式下一个颜色都没选时，不能把所有像素都排除掉，否则搜索必然失败
	const uchar defaultValue = (keepMode && !noColors) ? 0 : 255;
	cv::Mat mask(bgra.size(), CV_8UC1, cv::Scalar(defaultValue));

	if (keepMode && noColors)
		return mask;

	const int colorCount = static_cast<int>(colors.size());

	for (int row = 0; row < bgra.rows; ++row)
	{
		const uchar* src = bgra.ptr<uchar>(row);
		uchar* dst = mask.ptr<uchar>(row);

		for (int col = 0; col < bgra.cols; ++col)
		{
			const int b = src[col * 4 + 0];
			const int g = src[col * 4 + 1];
			const int r = src[col * 4 + 2];
			const int a = src[col * 4 + 3];

			if (hasAlpha && a < 128)
			{
				dst[col] = 0;
				continue;
			}

			for (int i = 0; i < colorCount; ++i)
			{
				if (IsColorHit(b, g, r, colors[i], tolerance))
				{
					dst[col] = keepMode ? 255 : 0;
					break;
				}
			}
		}
	}

	return mask;
}

// ---------------------------------------------------------------------------
// 共用：按 UTF-16 路径读文件并解码成 BGRA（8 位）
// ---------------------------------------------------------------------------
static bool LoadTemplateBgra(const wchar_t* path, cv::Mat& bgra, bool& hasAlpha)
{
	bgra.release();
	hasAlpha = false;

	std::vector<uchar> bytes;
	if (!ReadAllBytesW(path, bytes))
		return false;

	cv::Mat raw = cv::imdecode(bytes, cv::IMREAD_UNCHANGED);
	if (raw.empty() || raw.depth() != CV_8U)
		return false;

	const int channels = raw.channels();
	if (channels == 4)
	{
		bgra = raw;
		hasAlpha = true;
	}
	else if (channels == 3)
	{
		cv::cvtColor(raw, bgra, cv::COLOR_BGR2BGRA);
	}
	else if (channels == 1)
	{
		cv::cvtColor(raw, bgra, cv::COLOR_GRAY2BGRA);
	}
	else
	{
		return false;
	}

	return true;
}

// ---------------------------------------------------------------------------
// 按 UTF-16 路径把内存字节写成文件
// ---------------------------------------------------------------------------
static bool WriteAllBytesW(const wchar_t* path, const std::vector<uchar>& data)
{
	FILE* fp = nullptr;
	if (_wfopen_s(&fp, path, L"wb") != 0 || fp == nullptr)
		return false;

	const size_t written = fwrite(data.data(), 1, data.size(), fp);
	fclose(fp);
	return written == data.size();
}

// ---------------------------------------------------------------------------
// 掩码匹配的公共部分
//   屏幕搜索和窗口搜索只差"怎么截到那一块图"，模板准备、掩码匹配、坐标补偿
//   完全一样。抽出来共用，避免两份逻辑日后走偏。
// ---------------------------------------------------------------------------

// 准备"只保留指定颜色"的模板。返回 0 成功，否则返回错误码（g_filterLastError 已写好原因）
static int PrepareMaskedTemplate(
	const wchar_t* targetPath,
	const wchar_t* filterColors,
	int tolerance,
	int filterMode,
	int searchW,
	int searchH,
	cv::Mat& tplFull,
	cv::Mat& maskCrop,
	cv::Rect& keptBox)
{
	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(targetPath, bgra, hasAlpha))
	{
		SetFilterError(L"模板读取失败：无法打开、解码失败或不是 8 位图像 %s", targetPath);
		return -1;
	}

	std::vector<cv::Vec3b> colors;
	ParseFilterColors(filterColors, colors);

	cv::Mat mask = BuildFilterMask(bgra, hasAlpha, colors, tolerance, filterMode);

	const long long totalPixels = static_cast<long long>(bgra.cols) * bgra.rows;
	const long long validPixels = cv::countNonZero(mask);

	// 注意：这里不能按"占整张模板的比例"卡阈值。
	// 典型用法恰恰是截一张很大的背景图、只保留中间那点目标，占比可能只有千分之几，
	// 按比例卡会直接被判失败（表现为"明明配了却搜不到"）。
	// 只挡"几乎没有像素"这种明显无效的情况。
	if (totalPixels <= 0 || validPixels < 16)
	{
		SetFilterError(L"参与匹配的像素太少：%lld/%lld，请先选择保留色，或提高容差",
			validPixels, totalPixels);
		return -4;
	}

	// ---------- 模板转 BGR，并裁剪到"保留像素"的外接矩形 ----------
	cv::cvtColor(bgra, tplFull, cv::COLOR_BGRA2BGR);

	std::vector<cv::Point> keptPoints;
	cv::findNonZero(mask, keptPoints);
	if (keptPoints.empty())
	{
		SetFilterError(L"没有任何像素参与匹配，请先选择保留色");
		return -4;
	}
	keptBox = cv::boundingRect(keptPoints);

	cv::Mat tplCrop = tplFull(keptBox).clone();
	maskCrop = mask(keptBox).clone();

	if (tplCrop.cols > searchW || tplCrop.rows > searchH)
	{
		SetFilterError(L"保留区域尺寸(%dx%d)大于搜索区域(%dx%d)",
			tplCrop.cols, tplCrop.rows, searchW, searchH);
		return -2;
	}

	return 0;
}

// 在已捕获的区域上做掩码匹配。
// 返回 1 命中 / 0 未命中 / 负数为错误；坐标已按 retained 区补偿，1:1 相对搜索区原点。
static int MatchMaskedTemplate(
	cv::Mat shot,
	const cv::Mat& tplFull,
	const cv::Mat& maskCrop,
	const cv::Rect& keptBox,
	int matchThreshold,
	int* x,
	int* y)
{
	if (shot.empty())
	{
		SetFilterError(L"截图失败：搜索区域为空");
		return -5;
	}

	if (shot.channels() == 4)
		cv::cvtColor(shot, shot, cv::COLOR_BGRA2BGR);

	cv::Mat tpl = tplFull(keptBox);

	// ---------- 掩码模板匹配 ----------
	cv::Mat result;
	try
	{
		cv::matchTemplate(shot, tpl, result, cv::TM_SQDIFF_NORMED, maskCrop);
	}
	catch (const cv::Exception& ex)
	{
		SetFilterError(L"OpenCV 匹配异常：%hs", ex.what());
		return -3;
	}

	if (result.empty() || result.type() != CV_32FC1)
	{
		SetFilterError(L"OpenCV 匹配结果异常：矩阵为空或类型不是 CV_32FC1");
		return -3;
	}

	// ---------- 收集候选 ----------
	const double scoreThreshold = matchThreshold / 100.0;
	const double maxSquaredDiff = (1.0 - scoreThreshold) * (1.0 - scoreThreshold);

	const double nmsThreshold = 0.3;
	std::vector<cv::Rect> rects;
	std::vector<float> scores;
	long long nanCells = 0;
	double bestRaw = -1.0;   // 全区域最小平方差，用于"未找到"时给出最高相似度提示
	double minRaw = 1e30;
	double maxRaw = -1e30;

	for (int row = 0; row < result.rows; ++row)
	{
		const float* line = result.ptr<float>(row);
		for (int col = 0; col < result.cols; ++col)
		{
			double raw = line[col];

			if (std::isnan(raw) || std::isinf(raw))
			{
				++nanCells;
				continue;
			}

			// TM_SQDIFF_NORMED 的归一化除法会产生 -1e-7 量级的负零附近值。
			// 完美匹配恰好落在这里，必须 clamp 到 0，不能当成非法值跳过。
			if (raw < 0.0)
				raw = 0.0;

			if (raw < minRaw) minRaw = raw;
			if (raw > maxRaw) maxRaw = raw;
			if (bestRaw < 0.0 || raw < bestRaw) bestRaw = raw;

			if (raw > maxSquaredDiff)
				continue;

			const double similarity = 1.0 - std::sqrt(raw);
			if (similarity + 1e-9 < scoreThreshold)
				continue;

			rects.push_back(cv::Rect(col, row, tpl.cols, tpl.rows));
			scores.push_back(static_cast<float>(similarity));
		}
	}

	const long long totalCells = static_cast<long long>(result.cols) * result.rows;
	if (totalCells > 0 && nanCells == totalCells)
	{
		SetFilterError(L"匹配结果全部为 NaN：模板有效区域过暗或无纹理，请减少滤色或降低容差");
		return -3;
	}

	if (rects.empty())
	{
		const double bestSimilarity = (bestRaw >= 0.0) ? (1.0 - std::sqrt(bestRaw)) * 100.0 : -1.0;
		SetFilterError(L"未找到相似度 ≥ %d%% 的目标（本区域最高 %.1f%%）",
			matchThreshold, bestSimilarity);
		return 0;
	}

	// ---------- NMS 取最高分 ----------
	std::vector<cv::Rect> selected = nonMaximumSuppression(rects, scores, scoreThreshold, nmsThreshold);
	if (selected.empty())
	{
		SetFilterError(L"未找到：候选点全部被 NMS 抑制");
		return 0;
	}

	// RMT 侧算点击点用的是「返回坐标 + 模板原尺寸/2」，
	// 而我们匹配的是裁剪后的保留区，所以这里把差值补回来，让中心对准保留区中心。
	const cv::Rect& best = selected.front();
	*x = best.x + (keptBox.width - tplFull.cols) / 2;
	*y = best.y + (keptBox.height - tplFull.rows) / 2;

	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageFilter(
	const wchar_t* targetPath,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	const wchar_t* filterColors,
	int tolerance,
	int filterMode,
	int* x,
	int* y)
{
	ClearFilterError();

	// ---------- 0. 参数校验 ----------
	if (targetPath == nullptr || x == nullptr || y == nullptr)
	{
		SetFilterError(L"参数非法：模板路径或输出坐标指针为空");
		return -6;
	}

	*x = 0;
	*y = 0;

	if (searchW <= 0 || searchH <= 0)
	{
		SetFilterError(L"参数非法：搜索区域宽高必须大于 0，实际 %dx%d", searchW, searchH);
		return -6;
	}

	if (matchThreshold < 0) matchThreshold = 0;
	else if (matchThreshold > 100) matchThreshold = 100;

	if (tolerance < 0) tolerance = 0;
	else if (tolerance > 255) tolerance = 255;

	cv::Mat tplFull, maskCrop;
	cv::Rect keptBox;
	const int prep = PrepareMaskedTemplate(targetPath, filterColors, tolerance, filterMode,
		searchW, searchH, tplFull, maskCrop, keptBox);
	if (prep != 0)
		return prep;

	// 截屏（坐标即屏幕绝对坐标，与 AHK 的 Screen 坐标一致）
	cv::Mat shot = captureScreen(searchX, searchY, searchW, searchH);
	if (shot.empty())
	{
		SetFilterError(L"屏幕截图失败：区域 %d,%d %dx%d", searchX, searchY, searchW, searchH);
		return -5;
	}

	int rx = 0, ry = 0;
	const int ret = MatchMaskedTemplate(shot, tplFull, maskCrop, keptBox, matchThreshold, &rx, &ry);
	if (ret != 1)
		return ret;

	*x = searchX + rx;
	*y = searchY + ry;
	ClearFilterError();
	return 1;
}

// 窗口版：截图换成 captureScreen(hwnd, ...)，返回坐标仍是窗口客户区坐标
// （与 FindWinImage 一致，RMT 侧不需要再加窗口原点）
extern "C" IMAGEFINDER_API int __cdecl FindWinImageFilter(
	const wchar_t* targetPath,
	int hwndInt,
	int searchX,
	int searchY,
	int searchW,
	int searchH,
	int matchThreshold,
	const wchar_t* filterColors,
	int tolerance,
	int filterMode,
	int* x,
	int* y)
{
	ClearFilterError();

	if (targetPath == nullptr || x == nullptr || y == nullptr)
	{
		SetFilterError(L"参数非法：模板路径或输出坐标指针为空");
		return -6;
	}

	*x = 0;
	*y = 0;

	if (hwndInt == 0)
	{
		SetFilterError(L"参数非法：窗口句柄为空");
		return -6;
	}

	if (searchW <= 0 || searchH <= 0)
	{
		SetFilterError(L"参数非法：搜索区域宽高必须大于 0，实际 %dx%d", searchW, searchH);
		return -6;
	}

	if (matchThreshold < 0) matchThreshold = 0;
	else if (matchThreshold > 100) matchThreshold = 100;

	if (tolerance < 0) tolerance = 0;
	else if (tolerance > 255) tolerance = 255;

	cv::Mat tplFull, maskCrop;
	cv::Rect keptBox;
	const int prep = PrepareMaskedTemplate(targetPath, filterColors, tolerance, filterMode,
		searchW, searchH, tplFull, maskCrop, keptBox);
	if (prep != 0)
		return prep;

	cv::Mat shot = captureScreen(hwndInt, searchX, searchY, searchW, searchH);
	if (shot.empty())
	{
		SetFilterError(L"窗口截图失败：窗口 %d 区域 %d,%d %dx%d", hwndInt, searchX, searchY, searchW, searchH);
		return -5;
	}

	int rx = 0, ry = 0;
	const int ret = MatchMaskedTemplate(shot, tplFull, maskCrop, keptBox, matchThreshold, &rx, &ry);
	if (ret != 1)
		return ret;

	*x = searchX + rx;
	*y = searchY + ry;
	ClearFilterError();
	return 1;
}

extern "C" IMAGEFINDER_API int __cdecl RenderFilterPreview(
	const wchar_t* tplPath,
	const wchar_t* filterColors,
	int tolerance,
	int filterMode,
	int maxW,
	int maxH,
	int viewX,
	int viewY,
	int viewW,
	int viewH,
	int rectX,
	int rectY,
	int rectW,
	int rectH,
	int showGrid,
	int zoomPercent,
	const wchar_t* outOrigPath,
	const wchar_t* outEffectPath,
	int* validPixels,
	int* totalPixels,
	int* previewW,
	int* previewH,
	int* origW,
	int* origH,
	int* bboxX,
	int* bboxY,
	int* bboxW,
	int* bboxH)
{
	ClearFilterError();

	if (tplPath == nullptr || (outOrigPath == nullptr && outEffectPath == nullptr)
		|| validPixels == nullptr || totalPixels == nullptr
		|| previewW == nullptr || previewH == nullptr
		|| origW == nullptr || origH == nullptr
		|| bboxX == nullptr || bboxY == nullptr || bboxW == nullptr || bboxH == nullptr)
	{
		SetFilterError(L"参数非法：指针为空");
		return -6;
	}

	*validPixels = 0;
	*totalPixels = 0;
	*previewW = 0;
	*previewH = 0;
	*origW = 0;
	*origH = 0;
	*bboxX = 0;
	*bboxY = 0;
	*bboxW = 0;
	*bboxH = 0;

	if (maxW < 16) maxW = 16;
	if (maxH < 16) maxH = 16;
	if (tolerance < 0) tolerance = 0;
	else if (tolerance > 255) tolerance = 255;

	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(tplPath, bgra, hasAlpha))
	{
		SetFilterError(L"模板读取失败：无法打开或不是 8 位图像 %s", tplPath);
		return -1;
	}

	std::vector<cv::Vec3b> colors;
	ParseFilterColors(filterColors, colors);

	cv::Mat mask = BuildFilterMask(bgra, hasAlpha, colors, tolerance, filterMode);

	const int total = bgra.cols * bgra.rows;
	const int valid = static_cast<int>(cv::countNonZero(mask));
	*totalPixels = total;
	*validPixels = valid;
	*origW = bgra.cols;
	*origH = bgra.rows;

	std::vector<cv::Point> keptPoints;
	cv::findNonZero(mask, keptPoints);
	if (!keptPoints.empty())
	{
		const cv::Rect box = cv::boundingRect(keptPoints);
		*bboxX = box.x;
		*bboxY = box.y;
		*bboxW = box.width;
		*bboxH = box.height;
	}

	// ---- 可视区域（取景框）----
	cv::Rect view(0, 0, bgra.cols, bgra.rows);
	if (viewW > 0 && viewH > 0)
	{
		int vw = viewW;
		int vh = viewH;
		if (vw > bgra.cols) vw = bgra.cols;
		if (vh > bgra.rows) vh = bgra.rows;

		int vx = viewX;
		int vy = viewY;
		if (vx < 0) vx = 0;
		if (vy < 0) vy = 0;
		if (vx > bgra.cols - vw) vx = bgra.cols - vw;
		if (vy > bgra.rows - vh) vy = bgra.rows - vh;

		view = cv::Rect(vx, vy, vw, vh);
	}

	cv::Mat bgraView = bgra(view);
	cv::Mat maskView = mask(view);

	cv::Mat canvasOrig, canvasEffect;
	cv::cvtColor(bgraView, canvasOrig, cv::COLOR_BGRA2BGR);
	canvasEffect = canvasOrig.clone();

	// 被过滤掉的像素画成棋盘格（而不是纯黑）：
	// 用户如果把黑色也选进保留色，纯黑背景就分不清哪块留下了、哪块被滤掉了。
	// 格子固定 8px，两种中性灰交替，与任何纯色都能区分。
	for (int row = 0; row < canvasEffect.rows; ++row)
	{
		cv::Vec3b* dst = canvasEffect.ptr<cv::Vec3b>(row);
		const uchar* m = maskView.ptr<uchar>(row);
		for (int col = 0; col < canvasEffect.cols; ++col)
		{
			if (m[col] != 0)
				continue;
			const bool odd = (((col >> 3) + (row >> 3)) & 1) != 0;
			dst[col] = odd ? cv::Vec3b(96, 96, 96) : cv::Vec3b(64, 64, 64);
		}
	}

	// ---- 1:1 取景框：按 zoomPercent 精确缩放（100% 就是 1 像素对 1 像素）----
	// 图片块尺寸 = 视口尺寸 * 缩放；比画布小时居中留边，比画布大时居中裁掉多余部分。
	double zs = (zoomPercent > 0) ? (zoomPercent / 100.0) : 1.0;

	int bw = static_cast<int>(std::lround(canvasOrig.cols * zs));
	int bh = static_cast<int>(std::lround(canvasOrig.rows * zs));
	if (bw < 1) bw = 1;
	if (bh < 1) bh = 1;

	cv::Mat blockOrig, blockEffect;
	if (bw != canvasOrig.cols || bh != canvasOrig.rows)
	{
		const int interpolation = (zs < 1.0) ? cv::INTER_AREA : cv::INTER_NEAREST;
		cv::resize(canvasOrig, blockOrig, cv::Size(bw, bh), 0, 0, interpolation);
		cv::resize(canvasEffect, blockEffect, cv::Size(bw, bh), 0, 0, interpolation);
	}
	else
	{
		blockOrig = canvasOrig;
		blockEffect = canvasEffect;
	}

	// 深色底 + 居中贴图（带裁剪）
	cv::Mat outOrig(maxH, maxW, CV_8UC3, cv::Scalar(30, 30, 30));
	cv::Mat outEffect(maxH, maxW, CV_8UC3, cv::Scalar(30, 30, 30));

	int pasteX = (maxW - bw) / 2;
	int pasteY = (maxH - bh) / 2;
	int srcX = 0;
	int srcY = 0;
	int copyW = bw;
	int copyH = bh;

	if (pasteX < 0) { srcX = -pasteX; copyW += pasteX; pasteX = 0; }
	if (pasteY < 0) { srcY = -pasteY; copyH += pasteY; pasteY = 0; }
	if (pasteX + copyW > maxW) copyW = maxW - pasteX;
	if (pasteY + copyH > maxH) copyH = maxH - pasteY;

	if (copyW > 0 && copyH > 0)
	{
		blockOrig(cv::Rect(srcX, srcY, copyW, copyH)).copyTo(outOrig(cv::Rect(pasteX, pasteY, copyW, copyH)));
		blockEffect(cv::Rect(srcX, srcY, copyW, copyH)).copyTo(outEffect(cv::Rect(pasteX, pasteY, copyW, copyH)));
	}

	*previewW = copyW;
	*previewH = copyH;

	// ---- 像素格：一格 = 一个原图像素（格宽 = zs）----
	if (showGrid && zs >= 6.0)
	{
		const cv::Scalar gridColor(70, 70, 70);
		const int cols = view.width;
		const int rows = view.height;

		for (int i = 1; i < cols; ++i)
		{
			const int gx = pasteX + static_cast<int>(std::lround(i * zs)) - srcX;
			if (gx <= 0 || gx >= maxW)
				continue;
			cv::line(outOrig, cv::Point(gx, pasteY), cv::Point(gx, pasteY + copyH - 1), gridColor, 1);
			cv::line(outEffect, cv::Point(gx, pasteY), cv::Point(gx, pasteY + copyH - 1), gridColor, 1);
		}

		for (int j = 1; j < rows; ++j)
		{
			const int gy = pasteY + static_cast<int>(std::lround(j * zs)) - srcY;
			if (gy <= 0 || gy >= maxH)
				continue;
			cv::line(outOrig, cv::Point(pasteX, gy), cv::Point(pasteX + copyW - 1, gy), gridColor, 1);
			cv::line(outEffect, cv::Point(pasteX, gy), cv::Point(pasteX + copyW - 1, gy), gridColor, 1);
		}
	}

	// ---- 选区框（裁剪用）----
	if (rectW > 0 && rectH > 0)
	{
		int rx = pasteX + static_cast<int>(std::lround((rectX - view.x) * zs)) - srcX;
		int ry = pasteY + static_cast<int>(std::lround((rectY - view.y) * zs)) - srcY;
		int rw = static_cast<int>(std::lround(rectW * zs));
		int rh = static_cast<int>(std::lround(rectH * zs));
		if (rw < 1) rw = 1;
		if (rh < 1) rh = 1;

		const cv::Rect box(rx, ry, rw, rh);
		const cv::Scalar selColor(0, 220, 255);
		cv::rectangle(outOrig, box, selColor, 1);
		cv::rectangle(outEffect, box, selColor, 1);

		// 四角手柄：让用户能在松手后继续拖动缩放选区
		const int hs = 4;
		const int xs[2] = { rx, rx + rw };
		const int ys[2] = { ry, ry + rh };
		for (int i = 0; i < 2; ++i)
		{
			for (int j = 0; j < 2; ++j)
			{
				cv::rectangle(outOrig, cv::Point(xs[i] - hs, ys[j] - hs),
					cv::Point(xs[i] + hs, ys[j] + hs), selColor, -1);
				cv::rectangle(outEffect, cv::Point(xs[i] - hs, ys[j] - hs),
					cv::Point(xs[i] + hs, ys[j] + hs), selColor, -1);
			}
		}
	}

	if (outOrigPath != nullptr)
	{
		std::vector<uchar> png;
		if (!cv::imencode(".png", outOrig, png) || png.empty())
		{
			SetFilterError(L"预览图编码失败");
			return -3;
		}
		if (!WriteAllBytesW(outOrigPath, png))
		{
			SetFilterError(L"预览图写入失败：%s", outOrigPath);
			return -3;
		}
	}

	if (outEffectPath != nullptr)
	{
		std::vector<uchar> png;
		if (!cv::imencode(".png", outEffect, png) || png.empty())
		{
			SetFilterError(L"预览图编码失败");
			return -3;
		}
		if (!WriteAllBytesW(outEffectPath, png))
		{
			SetFilterError(L"预览图写入失败：%s", outEffectPath);
			return -3;
		}
	}

	ClearFilterError();
	return 1;
}

// ===========================================================================
// 图片处理：把 src 的指定矩形裁出来另存为 dst
// 返回：1 成功 / -1 读取失败 / -3 写文件失败 / -6 参数非法
// ===========================================================================
extern "C" IMAGEFINDER_API int __cdecl CropImageFile(
	const wchar_t* srcPath,
	int x,
	int y,
	int w,
	int h,
	const wchar_t* dstPath)
{
	ClearFilterError();

	if (srcPath == nullptr || dstPath == nullptr)
	{
		SetFilterError(L"参数非法：路径为空");
		return -6;
	}

	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(srcPath, bgra, hasAlpha))
	{
		SetFilterError(L"读取失败：%s", srcPath);
		return -1;
	}

	if (w <= 0 || h <= 0)
	{
		SetFilterError(L"裁剪区域无效：%dx%d", w, h);
		return -6;
	}

	int cx = x, cy = y, cw = w, ch = h;
	if (cx < 0) cx = 0;
	if (cy < 0) cy = 0;
	if (cx + cw > bgra.cols) cw = bgra.cols - cx;
	if (cy + ch > bgra.rows) ch = bgra.rows - cy;
	if (cw <= 0 || ch <= 0)
	{
		SetFilterError(L"裁剪区域超出图片范围");
		return -6;
	}

	cv::Mat cropped = bgra(cv::Rect(cx, cy, cw, ch)).clone();

	std::vector<uchar> png;
	if (!cv::imencode(".png", cropped, png) || png.empty())
	{
		SetFilterError(L"裁剪结果编码失败");
		return -3;
	}
	if (!WriteAllBytesW(dstPath, png))
	{
		SetFilterError(L"裁剪结果写入失败：%s", dstPath);
		return -3;
	}

	ClearFilterError();
	return 1;
}

// ===========================================================================
// 滤色编辑器专用：按原图坐标取像素颜色（用于在预览图上点选颜色）
// 返回：1 成功 / -1 读取失败 / -6 坐标越界
// ===========================================================================
extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAt(
	const wchar_t* tplPath,
	int x,
	int y,
	int* r,
	int* g,
	int* b)
{
	ClearFilterError();

	if (tplPath == nullptr || r == nullptr || g == nullptr || b == nullptr)
	{
		SetFilterError(L"参数非法：指针为空");
		return -6;
	}

	*r = 0;
	*g = 0;
	*b = 0;

	cv::Mat bgra;
	bool hasAlpha = false;
	if (!LoadTemplateBgra(tplPath, bgra, hasAlpha))
	{
		SetFilterError(L"模板读取失败：%s", tplPath);
		return -1;
	}

	if (x < 0 || y < 0 || x >= bgra.cols || y >= bgra.rows)
	{
		SetFilterError(L"坐标越界：(%d,%d) 超出 %dx%d", x, y, bgra.cols, bgra.rows);
		return -6;
	}

	// 注意：bgra 是 4 通道，必须按字节偏移取，不能用 Vec3b 索引（步长会按 3 算）
	const uchar* rowPtr = bgra.ptr<uchar>(y);
	*b = rowPtr[x * 4 + 0];
	*g = rowPtr[x * 4 + 1];
	*r = rowPtr[x * 4 + 2];

	return 1;
}
