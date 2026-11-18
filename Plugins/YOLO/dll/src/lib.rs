//! RMT_YOLO.dll 的 C ABI 实现，合同见 src/RMT_Yolo.h。
//!
//! 这一层只做三件事：跨边界的类型转换、句柄生命周期、缓冲协议。
//! 任何 panic 都在这里拦下（panic 穿过 FFI 边界是未定义行为），
//! 转成 RMT_YOLO_E_* 返回给宿主。

// Cargo.toml 的 [lib] name 必须是 RMT_YOLO，产物才叫 RMT_YOLO.dll。
#![allow(non_snake_case)]

mod engine;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use image::RgbaImage;

use engine::{Engine, RunOptions};

/// 与 RMT_Yolo.h 的 RMT_YOLO_API_VERSION 必须一致，改一处就要改两处。
const API_VERSION: i32 = 2;

const OK: i32 = 0;
const E_INVALID: i32 = -1;
const E_LOAD: i32 = -2;
const E_RUN: i32 = -3;
const E_BUFFER: i32 = -4;
const E_IMAGE: i32 = -5;

/// RMT_YoloOptions 的镜像。字段顺序与头文件严格一致（全部 4 字节，共 40）。
/// 必须是 pub：它出现在导出的 RMT_Yolo_Run 签名里，私有会触发 private_interfaces。
#[repr(C)]
pub struct Options {
    struct_size: i32,
    conf: f32,
    max_det: i32,
    top_k: i32,
    keypoint_conf: f32,
    min_mask_ratio: f32,
    anchor_kpt: i32,
    sample_x: i32,
    sample_y: i32,
    reserved0: i32,
}

/// 句柄实际指向的对象。用 Box 分配、裸指针传递，Destroy 时按 Box 回收。
type Handle = *mut c_void;

struct Slot {
    /// 每帧推理都要 &mut model，同一句柄被多线程调用时必须串行。
    engine: Engine,
}

#[no_mangle]
pub extern "C" fn RMT_Yolo_ApiVersion() -> i32 {
    API_VERSION
}

#[no_mangle]
pub extern "C" fn RMT_Yolo_Create(
    model_path: *const u16,
    device: i32,
    iou: f32,
    out_handle: *mut Handle,
) -> i32 {
    if out_handle.is_null() {
        return E_INVALID;
    }
    unsafe { *out_handle = ptr::null_mut() };

    let path = match unsafe { wide_to_string(model_path) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    let result = catch_unwind(AssertUnwindSafe(|| Engine::load(&path, device, iou)));
    match result {
        Ok(Ok(engine)) => {
            let slot = Box::into_raw(Box::new(Slot { engine })) as Handle;
            unsafe { *out_handle = slot };
            OK
        }
        Ok(Err(_)) => E_LOAD,
        Err(_) => E_LOAD,
    }
}

#[no_mangle]
pub extern "C" fn RMT_Yolo_Destroy(handle: Handle) {
    if handle.is_null() {
        return;
    }
    // 宿主重复 Destroy 是宿主的问题，这里只保证单次调用是安全的。
    unsafe {
        drop(Box::from_raw(handle as *mut Slot));
    }
}

#[no_mangle]
pub extern "C" fn RMT_Yolo_Info(
    handle: Handle,
    buffer: *mut u8,
    buffer_size: i32,
) -> i32 {
    let slot = match unsafe { slot_of(handle) } {
        Some(value) => value,
        None => return E_INVALID,
    };
    let info = match catch_unwind(AssertUnwindSafe(|| slot.engine.info_json())) {
        Ok(value) => value,
        Err(_) => return E_RUN,
    };
    write_json(&info.to_string(), buffer, buffer_size)
}

#[no_mangle]
pub extern "C" fn RMT_Yolo_Run(
    handle: Handle,
    bgra: *const u8,
    width: i32,
    height: i32,
    stride: i32,
    options: *const Options,
    buffer: *mut u8,
    buffer_size: i32,
) -> i32 {
    let slot = match unsafe { slot_of(handle) } {
        Some(value) => value,
        None => return E_INVALID,
    };
    if bgra.is_null() || width <= 0 || height <= 0 || stride <= 0 {
        return E_IMAGE;
    }
    let row_bytes = match (width as usize).checked_mul(4) {
        Some(value) if value <= stride as usize => value,
        _ => return E_IMAGE,
    };
    let total = match (stride as usize).checked_mul(height as usize) {
        Some(value) => value,
        None => return E_IMAGE,
    };

    let opts = unsafe { read_options(options) };

    let pixels = unsafe { slice::from_raw_parts(bgra, total) };
    let image = match bgra_to_rgba(pixels, width as u32, height as u32, stride as usize, row_bytes) {
        Some(value) => value,
        None => return E_IMAGE,
    };

    let result = catch_unwind(AssertUnwindSafe(|| slot.engine.run(image, opts)));
    let json = match result {
        Ok(Ok(value)) => value.to_string(),
        Ok(Err(_)) => return E_RUN,
        Err(_) => return E_RUN,
    };
    write_json(&json, buffer, buffer_size)
}

unsafe fn slot_of(handle: Handle) -> Option<&'static mut Slot> {
    if handle.is_null() {
        return None;
    }
    Some(&mut *(handle as *mut Slot))
}

unsafe fn read_options(options: *const Options) -> RunOptions {
    let mut opts = RunOptions::default();
    if options.is_null() {
        return opts;
    }
    let head = &*options;
    // structSize 用来判断宿主传的是哪一版结构体；不认识就按默认值跑，不报错。
    if head.struct_size != std::mem::size_of::<Options>() as i32 {
        return opts;
    }
    opts.conf = if head.conf.is_finite() && head.conf > 0.0 {
        head.conf
    } else {
        0.25
    };
    opts.max_det = if head.max_det > 0 {
        head.max_det as usize
    } else {
        300
    };
    opts.top_k = if head.top_k > 0 {
        head.top_k as usize
    } else {
        5
    };
    opts.keypoint_conf = if head.keypoint_conf.is_finite()
        && head.keypoint_conf > 0.0
        && head.keypoint_conf <= 1.0
    {
        head.keypoint_conf
    } else {
        0.5
    };
    opts.min_mask_ratio = if head.min_mask_ratio.is_finite()
        && head.min_mask_ratio > 0.0
        && head.min_mask_ratio <= 1.0
    {
        head.min_mask_ratio
    } else {
        0.0
    };
    opts.anchor_kpt = head.anchor_kpt;
    opts.sample = if head.sample_x >= 0 && head.sample_y >= 0 {
        Some((head.sample_x, head.sample_y))
    } else {
        None
    };
    opts
}

unsafe fn wide_to_string(ptr: *const u16) -> Result<String, i32> {
    if ptr.is_null() {
        return Err(E_INVALID);
    }
    let mut len = 0usize;
    while *ptr.add(len) != 0 {
        len += 1;
        if len > 32767 {
            return Err(E_INVALID);
        }
    }
    if len == 0 {
        return Err(E_INVALID);
    }
    String::from_utf16(slice::from_raw_parts(ptr, len)).map_err(|_| E_INVALID)
}

/// BGRA 自顶向下 → RGBA。Windows 截图给的就是这个排列，只换 R/B 两个通道。
fn bgra_to_rgba(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: usize,
    row_bytes: usize,
) -> Option<RgbaImage> {
    let mut out = vec![0u8; width as usize * height as usize * 4];
    for y in 0..height as usize {
        let src = y.checked_mul(stride)?;
        let row = pixels.get(src..src + row_bytes)?;
        let dst = y * width as usize * 4;
        for (index, pixel) in row.chunks_exact(4).enumerate() {
            let offset = dst + index * 4;
            out[offset] = pixel[2];
            out[offset + 1] = pixel[1];
            out[offset + 2] = pixel[0];
            out[offset + 3] = 0xFF;
        }
    }
    RgbaImage::from_raw(width, height, out)
}

/// buffer 为 NULL 时只回报所需字节数（含结尾 \0），宿主据此分配后重调。
fn write_json(text: &str, buffer: *mut u8, buffer_size: i32) -> i32 {
    let bytes = text.as_bytes();
    let needed = bytes.len() + 1;
    if buffer.is_null() || buffer_size <= 0 {
        return needed as i32;
    }
    if (buffer_size as usize) < needed {
        return E_BUFFER;
    }
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }
    bytes.len() as i32
}
