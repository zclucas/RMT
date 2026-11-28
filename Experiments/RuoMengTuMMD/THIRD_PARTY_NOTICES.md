# 若梦兔模型候选的来源与使用条件

本目录中的模型是修改后的角色候选，不是从零独立创作的全部网格。

## VRoid / pixiv 基体

脸部、手指、身体局部拓扑、部分原始面部贴图及表情形态来自 pixiv 的 **AvatarSample_B**，作者为 VRoid Project，版权归 pixiv Inc.。下载地址、固定提交、SHA-256 和模型内嵌元数据保存在 `source-manifest.json`。

原始文件由 pixiv 的 [ChatVRM 仓库](https://github.com/pixiv/ChatVRM/blob/b542aa00e19dccf9fc48ba340cf7eee011d2329a/public/AvatarSample_B.vrm) 提供。使用条件以官方 [VRoidPreset_A–Z 说明](https://vroid.pixiv.help/hc/en-us/articles/4402394424089-VRoidPreset-A-Z) 和原始模型内嵌声明为准。

官方允许修改贴图、参数、创作并再分发角色，同时保留对使用方式的限制。本资源**不声明为 CC0**；不得把基体数据用于角色创建服务，不得收费转售原始样例文件或其中的原始图片，也不得暗示 pixiv 为本项目背书。后续分发应继续附带本来源说明及原始使用条件链接。

内嵌 VRM 元数据另外指向 [VRM 1.0 使用许可说明](https://vrm.dev/licenses/1.0/)，其原始字段在清单中原样保留。本实验没有以仓库的代码许可证替代这些资源条件。

## 本次修改

按既有若梦兔形象重新调整比例；重建衣服、短发、兔耳、尾巴及服装细节；调整脸部及肤色；重绘棕色虹膜；增加眼神形态、发束骨骼及 MMD 控制骨骼。尾巴改到后背中央。

虹膜贴图由内置 `image_gen` 在许可基体虹膜图上修改，参考既有若梦兔原画。所用提示词见 `Art/iris.prompt.txt`。身体和脸部颜色由建模脚本烘焙，不复用基体衣服、纹身或商标图案。

衣服重建网格与重拓扑对比方案仅留在项目的 `Test/` 中，未纳入这里保留的候选，也未分发 Hunyuan 的代码或模型权重。

## 建模与导出工具

建模脚本使用 Blender Python API；PMX 序列化使用外部安装的 `pymeshio 3.0.1`（zlib 许可）。本目录不捆绑 Blender、Python、pymeshio、MMD 播放器或其运行时。建模脚本遵循仓库代码许可，第三方派生资源继续遵循上述条件。
