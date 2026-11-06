#pragma once
#ifdef IMAGEFINDER_EXPORTS
#define IMAGEFINDER_API __declspec(dllexport)
#else
#define IMAGEFINDER_API __declspec(dllimport)
#endif

// API 13: hwnd=0 captures the screen; otherwise coordinates are client-relative.
extern "C" IMAGEFINDER_API void* __cdecl SearchAllCapture(const wchar_t* path,
    int x, int y, int width, int height, int threshold, int colorMatch,
    int adaptive, int colorMode, unsigned int color, int hwnd);
extern "C" IMAGEFINDER_API int __cdecl SearchAllCount(void* handle);
extern "C" IMAGEFINDER_API const void* __cdecl SearchAllPoints(void* handle);
extern "C" IMAGEFINDER_API void __cdecl SearchAllRelease(void* handle);

extern "C" IMAGEFINDER_API void* __cdecl CaptureWinMat(     // 窗口截图返回Mat对象 RapidOcr需要使用
    int hwnd,                   // 窗口句柄
    int x,                      // 捕获区域左上角X坐标
    int y,                      // 捕获区域左上角Y坐标
    int width,                  // 捕获区域宽度
    int height);                // 捕获区域高度

extern "C" IMAGEFINDER_API void* __cdecl CaptureScreenMat(   // 屏幕截图返回Mat对象 (BitBlt)
    int x,                      // 捕获区域左上角X坐标
    int y,                      // 捕获区域左上角Y坐标
    int width,                  // 捕获区域宽度
    int height);                // 捕获区域高度

extern "C" IMAGEFINDER_API void __cdecl ReleaseMat(void* matPtr);   // 释放Mat对象，防止内存泄漏

extern "C" IMAGEFINDER_API void __cdecl ReleaseAllCaches(void);        // 释放所有窗口截图缓存

extern "C" IMAGEFINDER_API int __cdecl SaveMatToFile(               // 保存Mat到图片文件
    void* matPtr,               // Mat对象指针
    const char* filePath);      // 保存路径（支持png/jpg/bmp等）

extern "C" IMAGEFINDER_API int __cdecl FindWinColor(                // 窗口颜色匹配
    const char* colorStr,       // 颜色字符串，格式为"RRGGBB"
    int hwndInt,                // 窗口句柄
    int searchX,                // 搜索区域左上角X坐标
    int searchY,                // 搜索区域左上角Y坐标
    int searchW,                // 搜索区域宽度
    int searchH,                // 搜索区域高度
    int matchThreshold,         // 匹配阈值 0~100
    int* x,                     // 匹配到的X坐标
    int* y);                    // 匹配到的Y坐标

extern "C" IMAGEFINDER_API int __cdecl FindScreenImage(             // 屏幕图片匹配
    const char* targetPath,     // 图片路径
    int searchX,                // 搜索区域左上角X坐标
    int searchY,                // 搜索区域左上角Y坐标
    int searchW,                // 搜索区域宽度
    int searchH,                // 搜索区域高度
    int matchThreshold,         // 匹配阈值
    int* x,                     // 匹配到的X坐标
    int* y);                    // 匹配到的Y坐标

extern "C" IMAGEFINDER_API int __cdecl FindWinImage(                // 窗口图片匹配
    const char* targetPath,     // 图片路径
    int hwnd,                   // 窗口句柄
    int searchX,                // 搜索区域左上角X坐标
    int searchY,                // 搜索区域左上角Y坐标
    int searchW,                // 搜索区域宽度
    int searchH,                // 搜索区域高度
    int matchThreshold,         // 匹配阈值
    int* x,                     // 匹配到的X坐标
    int* y);                    // 匹配到的Y坐标

// ---- 自适应匹配与多点找图 ----
// GetApiVersion 用于让 AHK 判断 DLL 是否包含相应接口。
extern "C" IMAGEFINDER_API int __cdecl GetApiVersion();            // 12 = 独立颜色匹配参数

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageEx(const char* path,
    int sx, int sy, int sw, int sh, int threshold, int colorMatch, int adaptive, int* x, int* y);
extern "C" IMAGEFINDER_API int __cdecl FindWinImageEx(const char* path, int hwnd,
    int sx, int sy, int sw, int sh, int threshold, int colorMatch, int adaptive, int* x, int* y);

extern "C" IMAGEFINDER_API int __cdecl FindScreenImageAdaptive(     // 屏幕自适应图片匹配
    const char* targetPath,
    int searchX,
    int searchY,
    int searchW,
    int searchH,
    int matchThreshold,
    int* x,
    int* y);

extern "C" IMAGEFINDER_API int __cdecl FindWinImageAdaptive(        // 窗口自适应图片匹配
    const char* targetPath,
    int hwnd,
    int searchX,
    int searchY,
    int searchW,
    int searchH,
    int matchThreshold,
    int* x,
    int* y);

// 多点找图（原始比例）；matchThreshold 表示命中点位占比，tolerance 为每个颜色通道的容差。
// points 格式："x,y,RRGGBB;x,y,RRGGBB"，坐标相对模板左上角。
extern "C" IMAGEFINDER_API int __cdecl FindScreenImageMultiPoint(
    const wchar_t* targetPath,
    int searchX, int searchY, int searchW, int searchH,
    int matchThreshold, const wchar_t* points, int tolerance,
    int* x, int* y);

extern "C" IMAGEFINDER_API int __cdecl FindWinImageMultiPoint(
    const wchar_t* targetPath,
    int hwnd,
    int searchX, int searchY, int searchW, int searchH,
    int matchThreshold, const wchar_t* points, int tolerance,
    int* x, int* y);

// 超多点：由基准色自动选最多 256 个点粗搜候选，再以全部有效像素局部复核。
extern "C" IMAGEFINDER_API int __cdecl FindScreenImageMultiPointSuper(
    const wchar_t* targetPath,
    int searchX, int searchY, int searchW, int searchH,
    int matchThreshold, const wchar_t* seedPoints, int tolerance, const wchar_t* ignoreData,
    int* x, int* y);

extern "C" IMAGEFINDER_API int __cdecl FindWinImageMultiPointSuper(
    const wchar_t* targetPath,
    int hwnd,
    int searchX, int searchY, int searchW, int searchH,
    int matchThreshold, const wchar_t* seedPoints, int tolerance, const wchar_t* ignoreData,
    int* x, int* y);

// 使用手动选中的基准点颜色自动补齐点位；密集度范围 0~100。
extern "C" IMAGEFINDER_API int __cdecl AutoSelectImageMultiPoints(
    const wchar_t* targetPath,
    const wchar_t* existingPoints,
    int density,
    int tolerance,
    const wchar_t* ignoreData,
    wchar_t* output,
    int outputCapacity);

// 预览接口按 seedPoints 的颜色容差压暗右侧预览中的未命中像素；空点集时左右显示原图。
// seedPoints 格式："x,y,RRGGBB;x,y,RRGGBB"，tolerance 为各颜色通道的绝对差值上限。
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
    int* bboxX, int* bboxY, int* bboxW, int* bboxH);

extern "C" IMAGEFINDER_API int __cdecl CropImageFile(
    const wchar_t* srcPath, int x, int y, int w, int h,
    const wchar_t* dstPath);

extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAt(
    const wchar_t* path, int x, int y, int* r, int* g, int* b);

extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAtEx(
    const wchar_t* path, int x, int y, int* r, int* g, int* b, int* a);

extern "C" IMAGEFINDER_API const wchar_t* __cdecl GetImageLastError();
