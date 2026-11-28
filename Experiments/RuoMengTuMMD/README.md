# 若梦兔 MMD 建模候选

这是供外观评审的隔离模型候选。先确认模型，再推进舞蹈和产品入口；当前没有舞蹈、物理刚体或程序启动逻辑。

## 保留内容

- `Assets/RuoMengTu.blend`：可编辑网格、分件、表情及实验骨骼，使用的贴图均打包在文件内。
- `Assets/RuoMengTu.glb`：含骨骼、表情和内嵌贴图的模型。身体部件在导出时合并，单独保留表情网格；源文件仍保留分件。脸、皮肤、头发采用标准 `KHR_materials_unlit` 材质，减少立体光照感。
- `Assets/PMX/RuoMengTu.pmx`：MMD 导出，旁边的 `textures/` 必须一起保留。
- `Authoring/`：从固定来源重建候选的建模与导出脚本。
- `Art/`：实际使用的棕色虹膜贴图及生成提示词。
- `source-manifest.json`：来源、许可元数据及校验值。
- `rendering-profile.json`：MMD 预览建议；不同查看器的灯光和透明材质默认行为会改变观感。

RMT 入口、2D 看板娘、设置和发行包均没有引用此目录。删除整个 `Experiments/RuoMengTuMMD/` 即可移除保留的实验；`Test/` 下的本地工作文件不参与 Git 和打包。

## 比较过的建模方法

1. **许可基体＋手工衣服与立体发束**：保留干净的脸、五指和身体拓扑，按原画调整比例，重建衣服及毛发。此处保留这一方案。
2. **重建衣服＋干净脸手**：衣服轮廓更蓬松，但领口切面和局部拓扑不稳定，未纳入保留资源。
3. **重建轮廓投射到四边面网格**：试图兼顾轮廓与绑定，袖口、腋下仍有投射折边，未采用。

三种方案的临时模型、对比截图和检查输出均留在本机 `Test/ruomengtu-avatar-lab/`。球形眼球与模板闭眼拓扑不匹配的尝试也已舍弃；保留方案通过贴合眼白曲面的形态滑动实现眼神移动。

## 模型与绑定范围

双手各有五根手指，每指三节骨骼；手臂、腿分别保留上下段。另有 32 组两节发束链、每耳三节骨骼和两节尾巴骨骼。尾巴位于后背中央，正视时由身体遮住。

Blender/GLB 使用 125 根骨骼。PMX 增加中心骨骼、双足 IK 和双脚趾 IK，共 130 根骨骼。PMX 导出包含 58 个有效表情/眼神形态，四个眼神形态为 `Ruo_EyeLook_Left/Right/Up/Down`；眼神通过形态控制，不提供球形眼球旋转骨骼。

当前为实验绑定：没有头发/衣服自动物理，也没有布料碰撞。较大幅度抬腿仍可能与大衣下摆穿插，需要在模型外观确认后继续做服装修形或碰撞处理。当前外观仍需与原画继续核对，不能把本候选当作已获确认的最终角色。

## 重新生成

需要 Blender 4.2 的 Python 环境及 `pymeshio==3.0.1`。原始 VRM 由脚本从固定提交下载并校验，不随本目录再次捆绑。

在仓库根目录运行 PowerShell：

```powershell
./Experiments/RuoMengTuMMD/Authoring/Build.ps1 -BlenderPath 'C:/Program Files/Blender Foundation/Blender 4.2/blender.exe'
```

若使用已安装 `bpy 4.2` 的 Python，可改用 `-PythonPath`。若 pymeshio 位于独立目录，可传入包含 `pymeshio/` 的 `-PymeshioPath`。`-SkipPmx` 可只生成 Blender/GLB。

脚本只向仓库的 `Test/RuoMengTuMMD-Rebuild/` 写入下载文件、中间文件、模型与日志；不会覆盖这里的候选资源。确认重新生成的结果后，再替换 `Assets/` 中的保留模型。`-WorkspaceName` 可指定另一个 `Test/` 子目录名。

## 验证边界

已检查中立四视图、五指卷曲、屈肘弯膝、头胸与兔耳控制、发束控制、眨眼、眼神滑动与闭眼叠加、张嘴。另用独立 MMD 加载器检查 PMX 加载、闭眼和足 IK；没有加载 VMD 或舞蹈。

验证截图、日志、逐顶点权重与变形报告均位于 `Test/`，没有放入源码或发行资源。来源与使用条件见 `THIRD_PARTY_NOTICES.md`。
