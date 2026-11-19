//! 推理封装。
//!
//! 这个文件是唯一跟 ultralytics-inference 耦合的地方：只用了 `YOLOModel::load_with_config`、
//! `predict_image`、`task/names/imgsz/num_classes/metadata` 六个入口，以及 `Results`
//! 里 `boxes / masks / keypoints / probs / obb / semantic_mask / depth` 的公开字段。
//! 升级上游库时先核对这几处，其余代码不用动。
//!
//! 任务决定参数与输出：`run` 按 `self.task` 分派到各自的填充函数，
//! 每个任务只写自己那份字段，不硬凑成统一结构（分类没有框，深度没有目标）。
//!
//! 阈值策略：加载时用极低置信度（[`LOAD_CONF`]），把过滤推迟到每帧按宿主传入的
//! conf 做。这样同一个句柄可以服务不同阈值的指令，不必为了改阈值重载模型。
//! IoU 是 NMS 阶段参数、无法逐帧改，所以由宿主把它纳入句柄缓存键。

use image::{DynamicImage, RgbaImage};
use serde_json::{json, Value};
use ultralytics_inference::results::{Keypoints, Masks, Results};
use ultralytics_inference::{Device, InferenceConfig, Task, YOLOModel};

/// 加载时使用的最低置信度，保证不会提前丢掉低分目标。
pub const LOAD_CONF: f32 = 0.01;
/// 单帧最多保留的原始目标数，宿主还可以用更小的 maxDet 再截。
pub const LOAD_MAX_DET: usize = 300;

/// 一帧的推理参数。与当前任务无关的字段填默认值即可。
#[derive(Clone, Copy)]
pub struct RunOptions {
    pub conf: f32,
    pub max_det: usize,
    pub top_k: usize,
    pub keypoint_conf: f32,
    pub min_mask_ratio: f32,
    pub anchor_kpt: i32,
    pub sample: Option<(i32, i32)>,
}

impl Default for RunOptions {
    fn default() -> Self {
        Self {
            conf: 0.25,
            max_det: LOAD_MAX_DET,
            top_k: 5,
            keypoint_conf: 0.5,
            min_mask_ratio: 0.0,
            anchor_kpt: -1,
            sample: None,
        }
    }
}

pub struct Engine {
    model: YOLOModel,
    task: Task,
    names: Vec<(usize, String)>,
    imgsz: (usize, usize),
    num_classes: usize,
    model_name: String,
}

impl Engine {
    pub fn load(path: &str, device: i32, iou: f32) -> Result<Self, String> {
        let nms_iou = if iou.is_finite() && iou > 0.0 { iou } else { 0.45 };
        let config = InferenceConfig::new()
            .with_confidence(LOAD_CONF)
            .with_iou(nms_iou)
            .with_max_det(LOAD_MAX_DET)
            // 内核不落盘标注图，省一次编码。
            .with_save(false)
            .with_device(map_device(device));

        let model = YOLOModel::load_with_config(path, config).map_err(|e| e.to_string())?;

        let mut names: Vec<(usize, String)> =
            model.names().iter().map(|(k, v)| (*k, v.clone())).collect();
        names.sort_by_key(|entry| entry.0);

        let engine = Self {
            task: model.task(),
            imgsz: model.imgsz(),
            num_classes: model.num_classes(),
            model_name: model.metadata().model_name(),
            names,
            model,
        };
        Ok(engine)
    }

    pub fn info_json(&self) -> Value {
        json!({
            "task": task_name(self.task),
            "taskId": task_id(self.task),
            "imgsz": [self.imgsz.0, self.imgsz.1],
            "nc": self.num_classes,
            "names": self.names.iter().map(|(_, n)| n.clone()).collect::<Vec<_>>(),
            "model": self.model_name,
        })
    }

    pub fn run(&mut self, image: RgbaImage, opts: RunOptions) -> Result<Value, String> {
        let (width, height) = image.dimensions();
        if width == 0 || height == 0 {
            return Err("图像尺寸为 0".to_string());
        }

        let dynamic = DynamicImage::ImageRgba8(image);
        let mut results = self
            .model
            .predict_image(&dynamic, String::new())
            .map_err(|e| e.to_string())?;
        let result = match results.len() {
            0 => return Err("推理没有返回结果".to_string()),
            _ => results.swap_remove(0),
        };

        let mut output = json!({
            "task": task_name(self.task),
            "taskId": task_id(self.task),
            "width": width,
            "height": height,
            "elapsedMs": elapsed_ms(&result),
        });

        match self.task {
            Task::Classify => self.fill_classify(&mut output, &result, opts),
            Task::Depth => self.fill_depth(&mut output, &result, width, height, opts),
            Task::Semantic => self.fill_semantic(&mut output, &result, width, height, opts),
            Task::Obb => self.fill_obb(&mut output, &result, opts),
            _ => self.fill_boxes(&mut output, &result, opts),
        }

        Ok(output)
    }

    /// 检测 / 分割 / 姿态：都以 boxes 为骨架，再按任务往上叠专属字段。
    fn fill_boxes(&self, output: &mut Value, result: &Results, opts: RunOptions) {
        let threshold = threshold_of(opts.conf);
        let limit = limit_of(opts.max_det);
        let mut items: Vec<Value> = Vec::new();
        // 过滤掉低分目标后，掩膜/关键点在原数组里的下标就不再等于 items 的下标，
        // 必须单独记住映射关系，否则姿态点会整体错位。
        let mut kept: Vec<usize> = Vec::new();

        if let Some(boxes) = &result.boxes {
            for i in 0..boxes.data.nrows() {
                let score = boxes.data[[i, 4]];
                if !score.is_finite() || score < threshold {
                    continue;
                }

                let mut mask_ratio_value: Option<f32> = None;
                if self.task == Task::Segment {
                    match mask_ratio(result.masks.as_ref(), i) {
                        Some(value) => {
                            if opts.min_mask_ratio > 0.0 && value < opts.min_mask_ratio {
                                continue;
                            }
                            mask_ratio_value = Some(value);
                        }
                        // 模型说是分割却没给掩膜，宁可不出结果也不要给一个空壳框。
                        None => continue,
                    }
                }

                let cls = quantize_class(boxes.data[[i, 5]], self.num_classes);
                let (x1, y1, x2, y2) = (
                    boxes.data[[i, 0]],
                    boxes.data[[i, 1]],
                    boxes.data[[i, 2]],
                    boxes.data[[i, 3]],
                );
                let (cx, cy) = ((x1 + x2) / 2.0, (y1 + y2) / 2.0);
                let mut item = json!({
                    "cls": cls,
                    "name": self.name_of(cls),
                    "conf": round(score),
                    "box": [round(x1), round(y1), round(x2), round(y2)],
                    "cx": round(cx),
                    "cy": round(cy),
                    "w": round((x2 - x1).abs()),
                    "h": round((y2 - y1).abs()),
                    "anchor": [round(cx), round(cy)],
                });
                if let Some(value) = mask_ratio_value {
                    item["maskRatio"] = json!(round(value));
                }
                items.push(item);
                kept.push(i);
            }
        }

        if self.task == Task::Pose {
            if let Some(keypoints) = &result.keypoints {
                for (pos, &src) in kept.iter().enumerate() {
                    let points = keypoint_points(keypoints, src);
                    let fallback = item_center(&items, pos);
                    let anchor = pose_anchor(&points, opts.anchor_kpt, opts.keypoint_conf)
                        .unwrap_or(fallback);
                    if let Some(item) = items.get_mut(pos) {
                        item["keypoints"] = points_to_json(&points);
                        item["anchor"] = json!([round64(anchor.0), round64(anchor.1)]);
                    }
                }
            }
        }

        sort_desc(&mut items, "conf");
        items.truncate(limit);
        output["count"] = json!(items.len());
        output["items"] = json!(items);
    }

    /// 旋转框：内核给的是 (cx, cy, w, h, angle)，外接轴对齐框供宿主画准星用。
    fn fill_obb(&self, output: &mut Value, result: &Results, opts: RunOptions) {
        let threshold = threshold_of(opts.conf);
        let limit = limit_of(opts.max_det);
        let mut items: Vec<Value> = Vec::new();

        if let Some(obb) = &result.obb {
            for i in 0..obb.data.nrows() {
                let score = obb.data[[i, 5]];
                if !score.is_finite() || score < threshold {
                    continue;
                }
                let cls = quantize_class(obb.data[[i, 6]], self.num_classes);
                let (cx, cy) = (obb.data[[i, 0]], obb.data[[i, 1]]);
                let (w, h) = (obb.data[[i, 2]], obb.data[[i, 3]]);
                let angle = obb.data[[i, 4]];
                // 旋转矩形的外接框：半对角线按角度投影。
                let half_w = (w * angle.cos()).abs() / 2.0 + (h * angle.sin()).abs() / 2.0;
                let half_h = (w * angle.sin()).abs() / 2.0 + (h * angle.cos()).abs() / 2.0;
                items.push(json!({
                    "cls": cls,
                    "name": self.name_of(cls),
                    "conf": round(score),
                    "box": [
                        round(cx - half_w), round(cy - half_h),
                        round(cx + half_w), round(cy + half_h)
                    ],
                    "cx": round(cx),
                    "cy": round(cy),
                    "w": round(w),
                    "h": round(h),
                    "angle": round(angle),
                    "anchor": [round(cx), round(cy)],
                }));
            }
        }

        sort_desc(&mut items, "conf");
        items.truncate(limit);
        output["count"] = json!(items.len());
        output["items"] = json!(items);
    }

    /// 语义分割没有实例：按类别聚合像素，给出覆盖率、像素数和重心（重心就是点击锚点）。
    fn fill_semantic(
        &self,
        output: &mut Value,
        result: &Results,
        width: u32,
        height: u32,
        opts: RunOptions,
    ) {
        let limit = limit_of(opts.max_det);
        let mut items: Vec<Value> = Vec::new();

        if let Some(mask) = &result.semantic_mask {
            let shape = mask.data.shape();
            let (rows, cols) = (shape[0], shape[1]);
            let mut acc = vec![RegionAcc::default(); self.num_classes.max(1)];
            for row in 0..rows {
                for col in 0..cols {
                    let cls = mask.data[[row, col]] as usize;
                    if cls >= acc.len() {
                        // SemanticMask::IGNORE 之类的无效标记
                        continue;
                    }
                    acc[cls].push(row, col);
                }
            }

            let total = (rows * cols).max(1) as f64;
            let sx = if cols > 0 { width as f64 / cols as f64 } else { 1.0 };
            let sy = if rows > 0 { height as f64 / rows as f64 } else { 1.0 };

            for (cls, region) in acc.iter().enumerate() {
                if region.count == 0 {
                    continue;
                }
                let ratio = region.count as f64 / total;
                if opts.min_mask_ratio > 0.0 && ratio < opts.min_mask_ratio as f64 {
                    continue;
                }
                let cx = region.sum_x / region.count as f64 * sx;
                let cy = region.sum_y / region.count as f64 * sy;
                items.push(json!({
                    "cls": cls,
                    "name": self.name_of(cls),
                    "ratio": round(ratio as f32),
                    "area": region.count,
                    "box": [
                        round((region.min_x as f64 * sx) as f32),
                        round((region.min_y as f64 * sy) as f32),
                        round((region.max_x as f64 * sx) as f32),
                        round((region.max_y as f64 * sy) as f32)
                    ],
                    "cx": round(cx as f32),
                    "cy": round(cy as f32),
                    "anchor": [round(cx as f32), round(cy as f32)],
                }));
            }
        }

        sort_desc(&mut items, "ratio");
        items.truncate(limit);
        output["count"] = json!(items.len());
        output["items"] = json!(items);
    }

    /// 整图分类：只有概率排名，没有坐标，也没有 count 的意义。
    fn fill_classify(&self, output: &mut Value, result: &Results, opts: RunOptions) {
        let threshold = threshold_of(opts.conf);
        let top_k = opts.top_k.clamp(1, 20);
        let mut list: Vec<Value> = Vec::new();

        if let Some(probs) = &result.probs {
            let mut ranked: Vec<(usize, f32)> = probs
                .data
                .iter()
                .enumerate()
                .map(|(index, score)| (index, *score))
                .collect();
            ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
            ranked.truncate(top_k);
            for (cls, score) in ranked {
                if !score.is_finite() || score < threshold {
                    continue;
                }
                list.push(json!({
                    "cls": cls,
                    "name": self.name_of(cls),
                    "conf": round(score),
                }));
            }
        }

        output["top1"] = list.first().cloned().unwrap_or(Value::Null);
        output["probs"] = json!(list);
    }

    /// 深度：整图统计 + 可选采样点。采样点用截图像素坐标（相对检测区域）。
    fn fill_depth(
        &self,
        output: &mut Value,
        result: &Results,
        width: u32,
        height: u32,
        opts: RunOptions,
    ) {
        let depth = match &result.depth {
            Some(value) => value,
            None => return,
        };
        let shape = depth.data.shape();
        let (rows, cols) = (shape[0], shape[1]);

        let mut min = f32::INFINITY;
        let mut max = f32::NEG_INFINITY;
        let mut sum = 0f64;
        let mut count = 0usize;
        for value in depth.data.iter() {
            if !value.is_finite() {
                continue;
            }
            min = min.min(*value);
            max = max.max(*value);
            sum += *value as f64;
            count += 1;
        }
        if count == 0 {
            return;
        }

        let mut entry = json!({
            "min": round(min),
            "max": round(max),
            "mean": round((sum / count as f64) as f32),
        });

        if let Some((sx, sy)) = opts.sample {
            if sx >= 0 && sy >= 0 && (sx as u32) < width && (sy as u32) < height {
                // 深度图分辨率与截图不一定一致，按比例换算到掩膜像素。
                let col = ((sx as f64) * cols as f64 / width as f64).floor() as usize;
                let row = ((sy as f64) * rows as f64 / height as f64).floor() as usize;
                let col = col.min(cols.saturating_sub(1));
                let row = row.min(rows.saturating_sub(1));
                let value = depth.data[[row, col]];
                if value.is_finite() {
                    entry["point"] = json!(round(value));
                    entry["pointX"] = json!(sx);
                    entry["pointY"] = json!(sy);
                }
            }
        }

        output["depth"] = entry;
    }

    fn name_of(&self, cls: usize) -> String {
        self.names
            .iter()
            .find(|(index, _)| *index == cls)
            .map(|(_, name)| name.clone())
            .unwrap_or_else(|| cls.to_string())
    }
}

/// 语义分割按类别累计：像素数、重心、外接框，一遍扫描全部拿到。
#[derive(Clone, Copy)]
struct RegionAcc {
    count: usize,
    sum_x: f64,
    sum_y: f64,
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
}

impl Default for RegionAcc {
    fn default() -> Self {
        Self {
            count: 0,
            sum_x: 0.0,
            sum_y: 0.0,
            min_x: usize::MAX,
            min_y: usize::MAX,
            max_x: 0,
            max_y: 0,
        }
    }
}

impl RegionAcc {
    fn push(&mut self, row: usize, col: usize) {
        self.count += 1;
        self.sum_x += col as f64;
        self.sum_y += row as f64;
        self.min_x = self.min_x.min(col);
        self.min_y = self.min_y.min(row);
        self.max_x = self.max_x.max(col);
        self.max_y = self.max_y.max(row);
    }
}

/// 实例分割单个目标的掩膜像素占比。掩膜在模型输入尺度上（含 letterbox 填充），
/// 所以这个数只适合做相对比较，不是精确的像素面积。
fn mask_ratio(masks: Option<&Masks>, index: usize) -> Option<f32> {
    let masks = masks?;
    let shape = masks.data.shape();
    if shape.len() < 3 || index >= shape[0] {
        return None;
    }
    let (rows, cols) = (shape[1], shape[2]);
    if rows == 0 || cols == 0 {
        return None;
    }
    let mut inside = 0usize;
    for row in 0..rows {
        for col in 0..cols {
            if masks.data[[index, row, col]] > 0.5 {
                inside += 1;
            }
        }
    }
    Some(inside as f32 / (rows * cols) as f32)
}

/// 姿态关键点第 index 个实例 → [(x, y, conf)]，下标即关键点序号（COCO 顺序）。
fn keypoint_points(keypoints: &Keypoints, index: usize) -> Vec<(f64, f64, f64)> {
    let shape = keypoints.data.shape();
    if shape.len() < 3 || index >= shape[0] {
        return Vec::new();
    }
    let channels = shape[2];
    let mut points = Vec::with_capacity(shape[1]);
    for k in 0..shape[1] {
        let x = keypoints.data[[index, k, 0]] as f64;
        let y = keypoints.data[[index, k, 1]] as f64;
        let conf = if channels >= 3 {
            keypoints.data[[index, k, 2]] as f64
        } else {
            1.0
        };
        points.push((x, y, conf));
    }
    points
}

fn points_to_json(points: &[(f64, f64, f64)]) -> Value {
    Value::Array(
        points
            .iter()
            .map(|(x, y, c)| json!([round64(*x), round64(*y), round64(*c)]))
            .collect(),
    )
}

/// 指定了关键点序号且该点可信时用它当锚点；否则退回框中心。
fn pose_anchor(points: &[(f64, f64, f64)], anchor_kpt: i32, min_conf: f32) -> Option<(f64, f64)> {
    if anchor_kpt < 0 {
        return None;
    }
    let (x, y, conf) = *points.get(anchor_kpt as usize)?;
    if conf < min_conf as f64 {
        return None;
    }
    Some((x, y))
}

fn item_center(items: &[Value], index: usize) -> (f64, f64) {
    let cx = items
        .get(index)
        .and_then(|item| item.get("cx"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let cy = items
        .get(index)
        .and_then(|item| item.get("cy"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    (cx, cy)
}

fn elapsed_ms(result: &Results) -> f64 {
    let speed = &result.speed;
    [speed.preprocess, speed.inference, speed.postprocess]
        .into_iter()
        .flatten()
        .sum::<f64>()
}

fn threshold_of(conf: f32) -> f32 {
    if conf.is_finite() && conf > 0.0 {
        conf
    } else {
        0.25
    }
}

fn limit_of(max_det: usize) -> usize {
    if max_det > 0 {
        max_det
    } else {
        LOAD_MAX_DET
    }
}

fn sort_desc(items: &mut [Value], key: &str) {
    items.sort_by(|a, b| {
        let left = a.get(key).and_then(Value::as_f64).unwrap_or(0.0);
        let right = b.get(key).and_then(Value::as_f64).unwrap_or(0.0);
        right
            .partial_cmp(&left)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
}

/// 类别索引可能是浮点，也可能是负数（脏数据），统一夹到合法区间。
fn quantize_class(value: f32, classes: usize) -> usize {
    if !value.is_finite() || value < 0.0 {
        return 0;
    }
    let index = value as usize;
    if classes > 0 && index >= classes {
        classes - 1
    } else {
        index
    }
}

/// 保留 4 位小数，避免 JSON 里出现一长串浮点噪声。
fn round(value: f32) -> f64 {
    if !value.is_finite() {
        return 0.0;
    }
    round64(value as f64)
}

fn round64(value: f64) -> f64 {
    if !value.is_finite() {
        return 0.0;
    }
    (value * 10000.0).round() / 10000.0
}

fn map_device(device: i32) -> Device {
    match device {
        1 => Device::Cuda(0),
        2 => Device::DirectMl(0),
        3 => Device::TensorRt(0),
        4 => Device::CoreMl,
        _ => Device::Cpu,
    }
}

pub fn task_name(task: Task) -> &'static str {
    match task {
        Task::Detect => "detect",
        Task::Segment => "segment",
        Task::Semantic => "semantic",
        Task::Depth => "depth",
        Task::Classify => "classify",
        Task::Pose => "pose",
        Task::Obb => "obb",
    }
}

fn task_id(task: Task) -> i32 {
    match task {
        Task::Detect => 1,
        Task::Segment => 2,
        Task::Semantic => 3,
        Task::Depth => 4,
        Task::Classify => 5,
        Task::Pose => 6,
        Task::Obb => 7,
    }
}
