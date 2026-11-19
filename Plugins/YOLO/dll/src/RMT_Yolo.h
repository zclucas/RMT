/*
 * RMT_Yolo.h —— RMT 与 YOLO 推理内核之间唯一的 ABI 合同。
 *
 * 设计约定（与 Plugins/Voice/src/VoiceDll.h 同一套规矩）：
 *   1. 本文件只增不改。改任何已有签名都必须升 RMT_YOLO_API_VERSION，
 *      宿主用 RMT_Yolo_ApiVersion() 校验后再决定能否加载。
 *   2. 导出统一 RMT_YOLO_CALL（= __cdecl）。AHK 侧 DllCall 必须显式写 CDecl，
 *      32 位下 AHK 默认 stdcall，漏了会坏栈。
 *   3. 跨边界的字符串一律 UTF-8（char*），只有模型路径用 UTF-16（wchar_t*），
 *      因为 Windows 文件路径本身是 UTF-16，免得在 AHK 和 Rust 各转一次。
 *   4. 结构体首字段必须是 structSize，内核按它判断宿主传的是哪个版本的结构体，
 *      新版本只许在尾部追加字段。
 *   5. 内核只管推理：不截图、不碰窗口、不回调、不知道宿主怎么用结果。
 *      截图与鼠标动作是宿主的事。
 *
 * 任务不是宿主选的，而是由模型元数据决定（同一套模型文件名区分任务）。
 * 宿主读 RMT_Yolo_Info 拿到任务，再决定界面显示哪些参数、把结果写进哪些变量。
 *
 * 每个任务只认自己那份参数，也只产出自己那份结果：
 *
 *   任务       参数                                       结果字段
 *   ---------  -----------------------------------------  --------------------------------------
 *   detect     conf / maxDet                               items[box,cx,cy,w,h,conf,cls,anchor]
 *   segment    conf / maxDet / minMaskRatio                items[同上 + maskRatio]
 *   pose       conf / maxDet / keypointConf / anchorKpt    items[同上 + keypoints,anchor 按关键点]
 *   obb        conf / maxDet                               items[box,cx,cy,w,h,angle,conf,cls]
 *   classify   conf / topK                                 probs[cls,name,conf] + top1
 *   semantic   minMaskRatio                                items[cls,name,ratio,area,box,cx,cy]
 *   depth      sampleX / sampleY                           depth{min,max,mean,point}
 *
 * 类别过滤（只留某些类）是纯后处理，宿主自己做，不占内核参数：
 * 内核总是把模型能识别的东西全给出来。
 */

#ifndef RMT_YOLO_H
#define RMT_YOLO_H

#include <stdint.h>

/* 版本 2：Create 增加 iou；Options 的预留位改为任务专属参数。 */
#define RMT_YOLO_API_VERSION 2

#if defined(_WIN32)
#  define RMT_YOLO_CALL __cdecl
#  if defined(RMT_YOLO_EXPORTS)
#    define RMT_YOLO_API __declspec(dllexport)
#  else
#    define RMT_YOLO_API __declspec(dllimport)
#  endif
#else
#  define RMT_YOLO_API
#  define RMT_YOLO_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 模型任务类型。UNKNOWN 表示模型元数据里没写，宿主应按“检测”处理。 */
enum RMT_YoloTask {
    RMT_YOLO_TASK_UNKNOWN  = 0,
    RMT_YOLO_TASK_DETECT   = 1,   /* 目标检测：框 + 类别 + 置信度 */
    RMT_YOLO_TASK_SEGMENT  = 2,   /* 实例分割：框 + 掩膜面积占比 */
    RMT_YOLO_TASK_SEMANTIC = 3,   /* 语义分割：每类一块区域 + 覆盖率 + 重心 */
    RMT_YOLO_TASK_DEPTH    = 4,   /* 单目深度：整图统计 + 指定点距离 */
    RMT_YOLO_TASK_CLASSIFY = 5,   /* 整图分类：top-k 概率 */
    RMT_YOLO_TASK_POSE     = 6,   /* 姿态：框 + 关键点 */
    RMT_YOLO_TASK_OBB      = 7    /* 旋转框：带角度的框 */
};

/* 推理设备。字符串形式留给宿主，数值枚举够用且不会踩到 ABI 对齐问题。 */
enum RMT_YoloDevice {
    RMT_YOLO_DEVICE_CPU      = 0,
    RMT_YOLO_DEVICE_CUDA     = 1,
    RMT_YOLO_DEVICE_DIRECTML = 2,
    RMT_YOLO_DEVICE_TENSORRT = 3,
    RMT_YOLO_DEVICE_COREML   = 4
};

/* 返回码。正数不是错误：Run/Info 成功时返回写入的字节数（不含结尾 \0）。 */
enum RMT_YoloError {
    RMT_YOLO_OK          =  0,
    RMT_YOLO_E_INVALID   = -1,   /* 参数为空、structSize 不匹配、句柄无效 */
    RMT_YOLO_E_LOAD      = -2,   /* 模型加载失败：文件缺失、ONNX Runtime 缺失、元数据读不出 */
    RMT_YOLO_E_RUN       = -3,   /* 推理失败 */
    RMT_YOLO_E_BUFFER    = -4,   /* 输出缓冲不够，宿主加大后重调 */
    RMT_YOLO_E_IMAGE     = -5,   /* 图像尺寸/步长非法，或图像过长边超过内核上限 */
    RMT_YOLO_E_UNSUPPORT = -6    /* 该任务在当前构建里不支持（例如未启用 track 特性） */
};

typedef void* RMT_YoloHandle;

/*
 * 每次推理的参数。与任务无关的字段留着不填即可（填 0 = 用默认值）。
 * structSize 必须填 sizeof(RMT_YoloOptions)，内核据此判断版本；
 * 未来新增字段一律追加在 reserved 之前。
 */
typedef struct RMT_YoloOptions {
    int32_t structSize;    /* 0  必须 = sizeof(RMT_YoloOptions) */
    float   conf;          /* 4  置信度下限，<=0 用 0.25。classify 用作概率下限 */
    int32_t maxDet;        /* 8  detect/segment/pose/obb 最多返回多少个，<=0 用 300 */
    int32_t topK;          /* 12 classify 返回前 k 个，<=0 用 5，内核夹到 1~20 */
    float   keypointConf;  /* 16 pose 关键点可信阈值，<=0 用 0.5（用于挑 anchor 与标记） */
    float   minMaskRatio;  /* 20 segment/semantic 掩膜面积占比下限 0~1，<=0 不过滤 */
    int32_t anchorKpt;     /* 24 pose 点击锚点用第几个关键点，<0 表示用框中心 */
    int32_t sampleX;       /* 28 depth 采样点列（相对传入图像），<0 表示不采样 */
    int32_t sampleY;       /* 32 depth 采样点行，<0 表示不采样 */
    int32_t reserved0;     /* 36 预留，填 0 */
} RMT_YoloOptions;

/* 合同版本。宿主必须先调它，返回 RMT_YOLO_API_VERSION 才继续用其它函数。 */
RMT_YOLO_API int32_t RMT_YOLO_CALL RMT_Yolo_ApiVersion(void);

/*
 * 加载模型。同一个模型路径反复加载应由宿主自己缓存句柄，内核不保证内部复用。
 *   modelPath  以 \0 结尾的 UTF-16 路径，可以是相对路径
 *   device     enum RMT_YoloDevice
 *   iou        NMS 的 IoU 阈值 <=0 用 0.45。它是加载期参数（写法烧进 NMS 配置），
 *              宿主改阈值必须重新 Create；classify/depth 用不到，传 0 即可。
 *   outHandle  成功时写入句柄，失败时写 NULL
 * 返回 RMT_YOLO_OK 或错误码。
 */
RMT_YOLO_API int32_t RMT_YOLO_CALL RMT_Yolo_Create(
    const wchar_t* modelPath,
    int32_t device,
    float iou,
    RMT_YoloHandle* outHandle);

/* 释放句柄。传 NULL 直接返回。句柄用完后必须调，否则模型常驻内存。 */
RMT_YOLO_API void RMT_YOLO_CALL RMT_Yolo_Destroy(RMT_YoloHandle handle);

/*
 * 读模型元数据（任务类型、输入尺寸、类别名），输出 UTF-8 JSON：
 *   {"task":"detect","taskId":1,"imgsz":[640,640],"nc":80,
 *    "names":["person","bicycle", ...],"model":"yolo26n"}
 * buffer 为 NULL 时只返回所需字节数，宿主可据此分配。
 * 返回写入字节数；缓冲不足返回 RMT_YOLO_E_BUFFER。
 */
RMT_YOLO_API int32_t RMT_YOLO_CALL RMT_Yolo_Info(
    RMT_YoloHandle handle,
    char* buffer,
    int32_t bufferSize);

/*
 * 跑一帧。图像是 BGRA 自顶向下（Windows 截图的原生排列），
 * stride 为每行字节数，通常 = width * 4；允许带填充。
 *
 * 输出 UTF-8 JSON。所有任务共用同一层外壳，items 只在有“目标”的任务里出现：
 *
 *   {"task":"detect","taskId":1,"width":W,"height":H,"elapsedMs":0.0,
 *    "count":N,
 *    "items":[{"cls":0,"name":"person","conf":0.91,
 *              "box":[x1,y1,x2,y2],"cx":0,"cy":0,"w":0,"h":0,
 *              "anchor":[0,0],              // 宿主点击用这个点
 *              "maskRatio":0.12,            // 仅 segment
 *              "keypoints":[[x,y,conf],...],// 仅 pose（下标 = 关键点序号）
 *              "angle":0.0,                 // 仅 obb（弧度）
 *              "ratio":0.31,"area":1234}]}  // 仅 semantic（area 为像素数）
 *
 *   {"task":"classify", ... ,"top1":{"cls":0,"name":"cat","conf":0.99},
 *    "probs":[{"cls":0,"name":"cat","conf":0.99}, ...]}
 *
 *   {"task":"depth", ... ,
 *    "depth":{"min":0.4,"max":3.2,"mean":1.8,"point":1.6,"pointX":320,"pointY":240}}
 *    point/pointX/pointY 只在 sampleX/sampleY 有效且落在图像内时出现。
 *
 * 坐标一律是原图像素坐标（已按 letterbox 反算），不是模型输入坐标。
 * 返回写入字节数；缓冲不足返回 RMT_YOLO_E_BUFFER。
 */
RMT_YOLO_API int32_t RMT_YOLO_CALL RMT_Yolo_Run(
    RMT_YoloHandle handle,
    const uint8_t* bgra,
    int32_t width,
    int32_t height,
    int32_t stride,
    const RMT_YoloOptions* options,
    char* buffer,
    int32_t bufferSize);

#ifdef __cplusplus
}
#endif

#endif /* RMT_YOLO_H */
