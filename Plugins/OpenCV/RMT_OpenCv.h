#pragma once
#ifdef IMAGEFINDER_EXPORTS
#define IMAGEFINDER_API __declspec(dllexport)
#else
#define IMAGEFINDER_API __declspec(dllimport)
#endif

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

extern "C" IMAGEFINDER_API int __cdecl FindWinImageFilter(          // 窗口图片匹配（保留色）
    const wchar_t* targetPath,  // 图片路径
    int hwnd,                   // 窗口句柄
    int searchX,                // 搜索区域左上角X坐标（窗口客户区坐标）
    int searchY,                // 搜索区域左上角Y坐标
    int searchW,                // 搜索区域宽度
    int searchH,                // 搜索区域高度
    int matchThreshold,         // 匹配阈值
    const wchar_t* filterColors,// 保留色列表 "FF00FF,00FF00"
    int tolerance,              // 每通道容差
    int filterMode,             // 1=只保留这些颜色
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

// ---------------------------------------------------------------------------
// 滤色找图：允许把模板中的若干颜色当作通配符忽略掉，只比对剩下的像素。
// 用于"抓图时把背景色一起框进去，换个界面就找不到"的场景。
//
// 返回码：
//    1  找到（x/y 为左上角屏幕坐标）
//    0  未找到
//   -1  模板读取失败      -2  模板大于搜索区域
//   -3  OpenCV 异常        -4  有效像素不足（滤色把模板滤光）
//   -5  截图失败          -6  参数非法
// 失败原因可调 GetFilterLastError() 取（UTF-16）。
// ---------------------------------------------------------------------------
extern "C" IMAGEFINDER_API int __cdecl FindScreenImageFilter(       // 屏幕图片匹配（支持滤色）
    const wchar_t* targetPath,  // 图片路径（UTF-16，支持中文路径）
    int searchX,                // 搜索区域左上角X坐标
    int searchY,                // 搜索区域左上角Y坐标
    int searchW,                // 搜索区域宽度
    int searchH,                // 搜索区域高度
    int matchThreshold,         // 匹配阈值 0~100
    const wchar_t* filterColors,// 颜色列表 "FF00FF,00FF00"；空串表示不做颜色筛选
    int tolerance,              // 每通道容差 0~255
    int filterMode,             // 0=排除这些颜色  1=只保留这些颜色（其余不参与匹配）
    int* x,                     // 匹配到的X坐标（左上角）
    int* y);                    // 匹配到的Y坐标（左上角）

extern "C" IMAGEFINDER_API const wchar_t* __cdecl GetFilterLastError();  // 最近一次错误描述

// ---------------------------------------------------------------------------
// 滤色编辑器：渲染预览图（原图 / 掩膜 / 滤色效果），供 GUI 显示
// viewMode: 0=原图  1=掩膜(白=参与匹配, 黑=被滤掉)  2=效果(参与匹配保留原色, 其余压黑)
// 返回 1 成功；-1 读取失败；-3 编码/写文件失败；-6 参数非法
// ---------------------------------------------------------------------------
extern "C" IMAGEFINDER_API int __cdecl RenderFilterPreview(
    const wchar_t* tplPath,
    const wchar_t* filterColors,
    int tolerance,
    int filterMode,             // 0=排除  1=保留
    int maxW,                   // 单张预览图最大宽
    int maxH,                   // 单张预览图最大高
    int viewX,                  // 可视区域左上角X（原图坐标，缩放用）
    int viewY,                  // 可视区域左上角Y
    int viewW,                  // 可视区域宽（0 表示看整张图）
    int viewH,                  // 可视区域高
    int rectX,                  // 选区框X（原图坐标）；rectW<=0 表示不画
    int rectY,
    int rectW,
    int rectH,
    int showGrid,               // 1=画像素格（格宽>=6px 时才画）
    int zoomPercent,            // 缩放百分比，100 = 1 图像像素对 1 屏幕像素
    const wchar_t* outOrigPath, // 输出：原图 PNG；NULL 跳过
    const wchar_t* outEffectPath,// 输出：保留后 PNG；NULL 跳过
    int* validPixels,
    int* totalPixels,
    int* previewW,
    int* previewH,
    int* origW,
    int* origH,
    int* bboxX,
    int* bboxY,
    int* bboxW,
    int* bboxH);

// ---------------------------------------------------------------------------
// 图片处理：把 src 的指定矩形裁出来另存为 dst（PNG）
// 返回 1 成功；-1 读取失败；-3 写文件失败；-6 参数非法
// ---------------------------------------------------------------------------
extern "C" IMAGEFINDER_API int __cdecl CropImageFile(
    const wchar_t* srcPath,
    int x,
    int y,
    int w,
    int h,
    const wchar_t* dstPath);

// ---------------------------------------------------------------------------
// 滤色编辑器：按原图坐标取像素颜色（在预览图上点选颜色时用）
// 返回 1 成功；-1 读取失败；-6 坐标越界/参数非法
// ---------------------------------------------------------------------------
extern "C" IMAGEFINDER_API int __cdecl GetImagePixelAt(
    const wchar_t* tplPath,
    int x,
    int y,
    int* r,
    int* g,
    int* b);