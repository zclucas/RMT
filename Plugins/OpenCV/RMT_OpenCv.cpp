#include "RMT_OpenCv.h"
#include <opencv2/opencv.hpp>
#include <windows.h>
#include <dwmapi.h>
#include <unordered_map>
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

// 后台截图（使用缓存，避免每次创建/销毁窗口）
cv::Mat captureScreen(int hwnd, int x, int y, int width, int height) {
    HWND targetHwnd = (HWND)(intptr_t)hwnd;
    if (!targetHwnd || !IsWindow(targetHwnd))
        return cv::Mat();

    ThumbnailCache* cache = GetOrCreateCache(targetHwnd);
    if (!cache) return cv::Mat();

    const SIZE& size = cache->sourceSize;
    HWND dstWin = cache->dstWin;
    HTHUMBNAIL thumbnail = cache->thumbnail;

    // IsIconic 时 DWM 缩略图有内部偏移，需要补偿
    const int offset = IsIconic(targetHwnd) ? 8 : 0;

    DWM_THUMBNAIL_PROPERTIES props;
    props.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE |
        DWM_TNP_SOURCECLIENTAREAONLY | DWM_TNP_OPACITY;
    // 这里必须按“客户区”抓取，以和 AHK 侧使用的窗口坐标系保持一致。
    // 否则有标题栏/边框的窗口会把非客户区算进截图，造成偏移和裁剪错误。
    props.fSourceClientAreaOnly = TRUE;
    props.fVisible = TRUE;
    props.opacity = 255;
    props.rcDestination = RECT{ -offset, -offset, size.cx - offset, size.cy - offset };

    HRESULT hr = DwmUpdateThumbnailProperties(thumbnail, &props);
    if (FAILED(hr)) return cv::Mat();

    // PrintWindow 截取映射窗口
    HDC hDC = GetWindowDC(nullptr);
    HDC cDC = CreateCompatibleDC(hDC);
    HBITMAP cBmp = CreateCompatibleBitmap(hDC, size.cx, size.cy);
    HGDIOBJ oldBmp = SelectObject(cDC, cBmp);

    cv::Mat result;
    BOOL bret = PrintWindow(dstWin, cDC, PW_RENDERFULLCONTENT);

    if (bret) {
        result = cv::Mat(size.cy, size.cx, CV_8UC4);
        BITMAPINFO bi = { 0 };
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = size.cx;
        bi.bmiHeader.biHeight = -(LONG)size.cy;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;

        GetDIBits(cDC, cBmp, 0, size.cy, result.data, &bi, DIB_RGB_COLORS);

        // 裁剪指定区域
        const long capWidth = (width <= 0) ? size.cx : width;
        const long capHeight = (height <= 0) ? size.cy : height;
        if ((x > 0 || y > 0 || capWidth < size.cx || capHeight < size.cy)
            && x >= 0 && y >= 0 && x + capWidth <= size.cx && y + capHeight <= size.cy) {
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