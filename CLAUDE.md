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
- `RMTUtil.ahk` - 核心宏执行逻辑
- `WorkPool.ahk` - 多线程任务调度
- `BindUtil.ahk` - 全局热键注册与触发处理
- `UIUtil.ahk` - 主窗口UI模板
- `AssetUtil.ahk` - 资源管理（图标、配置文件、路径）
- `TimingUtil.ahk` - 定时/计划宏处理
- `VariableUtil.ahk` - 变量管理与替换
- `Util/` - 各种工具类（JsonUtil, InputUtil, TextOpsUtil 等）

### 数据模型 (`Main/DataClass.Ahk`)
- `TableItem` - 主表格数据结构，含每个宏项的状态
- `Timer` - 定时器/计划配置
- 各类 `*Data` 类（KeyboardData, SearchData, LoopData, RunData 等）- 宏指令数据模型

### GUI模块 (`Gui/`)
- `MacroEditGui.ahk` - 主宏编辑器
- `TriggerKeyGui.ahk` - 触发按键配置
- `SearchProGui.ahk` - 图片搜索界面
- 各类 `*Gui.ahk` 文件 - 不同宏类型的编辑界面

### 插件 (`Plugins/`)
- `OpenCV/` - 图片识别
- `RapidOcr/` - 文字识别（OCR）
- `ViGEm/` - 虚拟手柄模拟
- `IbInputSimulator.ahk` - 输入模拟

### 线程Worker (`Thread/`)
- `Work.ahk` - 工作脚本，编译为 Work.exe 用于并行执行宏
- `WorkUtil.ahk` - Worker工具函数

### 国际化 (`Lang/`)
- `中文.txt` 和 `English.txt` - UI语言字符串

## 新增指令流程

详见 [Web/开发指南.md](Web/开发指南.md)：
1. 在 `AssetUtil.ahk` 的 `InitFilePath()` 中添加文件路径
2. 在 `Main/DataClass.Ahk` 中定义数据结构
3. 在 `Gui/` 目录下创建GUI（参考现有类似GUI）
4. 在 `Gui/MacroEditGui.ahk` 中添加按钮入口
5. 在 `Main/RMTUtil.ahk` 的 `OnTriggerMacroOnce()` 中添加执行逻辑