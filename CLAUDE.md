# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目简介

RMT（若梦兔）是一款基于 **AutoHotkey v2** 的免费开源按键宏工具，支持：
- 键盘/鼠标/手柄宏的录制与播放
- 视觉自动化（图片识别、颜色识别、文本OCR）
- 逻辑判断、流程控制、多线程执行

## 运行项目

- **调试模式**：直接双击 `RMT.ahk` 运行
- **Worker线程编译**：如果修改了 `Thread/Work.ahk`，需要通过 AutoHotkey Dash → Compile 重新编译为 Work.exe（或者删除 .exe 文件，运行时会自动重新生成）

## 项目架构

### 入口文件
- [RMT.ahk](RMT.ahk) - 主入口，负责：文件路径初始化、配置加载、UI初始化、插件初始化、定时检测、按键绑定

### 核心模块 (`Main/`)
- `GlobalUtil.ahk` - 全局变量与配置初始化
- `SelfCheck.ahk` - 文件完整性自检
- `AssetUtil.ahk` - 资源管理（图标、配置文件、路径）
- `DataClass.Ahk` - 数据结构定义（TableItem, Timer, 各类 *Data 类等）
- `RMTUtil.ahk` - 核心工具函数（保存设置、数据操作等）
- `WorkPool.ahk` - 多线程任务调度
- `BindUtil.ahk` - 全局热键注册与触发处理
- `UIUtil.ahk` - 主窗口UI模板
- `TimingUtil.ahk` - 定时/计划宏处理
- `VariableUtil.ahk` - 变量管理与替换
- `RecordUtil.ahk` - 键盘/鼠标宏录制
- `RecordJoyUtil.ahk` - 手柄宏录制
- `JoyMacro.ahk` - 手柄宏支持
- `TriggerKeyData.ahk` - 触发键数据结构
- `WindowHotkeyManager.ahk` - 窗口热键管理器
- `FolderPackager.ahk` - 文件夹打包工具
- `Util/` - 工具类目录，包含：
  - `MacroUtil.ahk` - **核心宏执行逻辑**（含 `OnTriggerMacroOnce`）
  - `MacroClipboardUtil.ahk` - 宏剪贴板操作
  - `GraphMacroUtil.ahk` - 流程图宏执行
  - `JsonUtil.ahk` - JSON解析
  - `InputUtil.ahk` - 输入工具
  - `TextOpsUtil.ahk` - 文本操作
  - `SearchUtil.ahk` - 图片搜索工具
  - `CompareUtil.ahk` - 比较工具
  - `ExcelUtil.ahk` - Excel处理
  - `FileIOUtil.ahk` - 文件读写
  - `ExpressUtil.ahk` - 表达式计算
  - `LangUtil.ahk` - 国际化工具
  - `FixCompatUtil.ahk` - 兼容性修复
  - `Gdip_All.ahk` - GDI+图像处理
  - `HumanMouse.ahk` - 人类化鼠标移动
  - `PresssKeyUtil.ahk` - 按键模拟工具
  - `ArrayUtil.ahk` - 数组工具
  - `SerialUtil.ahk` - 序列化工具
  - `RingBuffer.ahk` - 环形缓冲区
  - `SharedMemory.ahk` - 共享内存
  - `PluginUtil.ahk` - 插件管理工具
  - `ErrorHandler.ahk` - 错误处理
  - `MergeUtil.ahk` - 配置合并工具

### GUI模块 (`Gui/`)
- `MacroEditGui.ahk` - 主宏编辑器
- `MacroGraph/` - 流程图编辑器子模块（12个文件）
- `TriggerKeyGui.ahk` - 触发按键配置
- `SearchProGui.ahk` - 图片搜索界面
- 各类 `*Gui.ahk` 文件 - 不同宏类型的编辑界面（KeyGui, BGMouseGui, LoopGui, RunGui, TextOpsGui, CompareGui, UIMacroGui 等）

### 线程Worker (`Thread/`)
- `Work.ahk` - 工作脚本，编译为 Work.exe 用于并行执行宏
- `WorkUtil.ahk` - Worker工具函数
- `WrokGlobalUtil.ahk` - Worker全局配置

### 插件 (`Plugins/`)
- `OpenCV/` - 图片识别
- `RapidOcr/` - 文字识别（OCR）
- `ViGEm/` - 虚拟手柄模拟
- `AhiDriver/` - 虚拟输入驱动
- `ScreenCapture/` - 屏幕截图
- `IbInputSimulator.ahk` / `.dll` - 输入模拟
- `MouseControl.ahk` / `.dll` - 鼠标控制
- `CLR.ahk` - .NET CLR 宿主
- `RMT/` - C# 辅助库（RMT.dll, Device.cs, Http.cs）

### 国际化 (`Lang/`)
- `中文.txt` 和 `English.txt` - UI语言字符串

### 其他资源目录
- `Audio/` - 提示音（Start.wav, End.wav）
- `Images/` - 图片资源（FreePaste, Gif, ScreenShot, Soft）
- `Setting/` - 用户配置文件目录
- `MinTool/` - 小工具（CountDown倒计时, PlayAudio播放音频）
- `Log/` - 日志目录
- `Web/` - 文档（开发指南、指令手册、更新日志等）

## 新增指令流程

详见 [Web/开发指南.md](Web/开发指南.md)：
1. 在 `AssetUtil.ahk` 的 `InitFilePath()` 中添加文件路径
2. 在 `Main/DataClass.Ahk` 中定义数据结构
3. 在 `Gui/` 目录下创建GUI（参考现有类似GUI）
4. 在 `Gui/MacroEditGui.ahk` 中添加按钮入口
5. 在 `Main/Util/MacroUtil.ahk` 的 `OnTriggerMacroOnce()` 中添加执行逻辑