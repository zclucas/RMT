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