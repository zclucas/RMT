# DataClass 数据结构（配置分析对照表）

源文件：`Main/DataClass.Ahk`  
用途：用户把配置、指令 JSON、序列号发到群里时，用本文对照字段含义。  
落盘方式见 `07-配置文件格式.md`。

约定：

- `TableItem` 里多数字段是**按宏条目对齐的数组**，下标从 1 开始，同一下标是同一条宏。
- 复杂指令不把参数写进宏字符串，只写序列号（如 `搜索3`），完整对象以 JSON 存在对应 `*File.ini`。
- `DataClass` 注释若与执行代码不一致，以执行代码为准（文中已按代码校正）。

---

## 1. TableItem — 一张页签里的全部宏

对应 `Setting/<配置名>/MacroFile.ini` 中带页签前缀的键（如 `NormalTKArr`）。

### 1.1 落盘字段（用户配置可见）

| 字段 | 含义 | 取值 |
|------|------|------|
| `SerialArr` | 每条宏自己的序列码 | 如 `1`、`Item3` |
| `TKArr` | 触发键 / 字串 | 按键名、组合键、或 `:` 开头的字串 |
| `MacroArr` | 宏指令字符串 | 逗号 / 换行 / `⫶` 分隔多条指令 |
| `HoldTimeArr` | 时间参数 | 长按=按住毫秒；双击=双击间隔毫秒；默认 500 |
| `UnorderedTriggerArr` | 组合键是否只按书写顺序注册 | `1` 只正序；`0` 正序+反序都注册 |
| `ForbidArr` | 该条宏是否禁用 | `1` 禁用，`0` 启用 |
| `LoopCountArr` | 循环次数 | `-1` 无限；`1` 一次；`n` 循环 n 次 |
| `RemarkArr` | 宏名称 / 备注 | 文本 |
| `TriggerTypeArr` | 触发类型 | `1` 按下 `2` 松开 `3` 松止 `4` 开关 `5` 长按 `6` 双击 |
| `TimingSerialArr` | 定时配置序列号 | 如 `Timing1`，内容在 `TimingFile.ini` |
| `ModeArr` | 按键模拟方式 | `1` AHK Send `2` keybd_event `3` 罗技 `4` AHI |
| `StartTipSoundArr` | 开始提示音 | `1` 无 `2` 触发提示 `3` 循环首次提示 |
| `EndTipSoundArr` | 结束提示音 | `1` 无 `2` 结束提示 `3` 循环结束提示 |
| `IcoPathArr` | 菜单宏图标路径 | 菜单/界面按钮用 |
| `FoldInfo` | 模块（折叠框）信息 | JSON，类型为 `ItemFoldInfo` |

### 1.2 运行时字段（不落盘或仅运行态）

| 字段 | 含义 |
|------|------|
| `ColorStateArr` | UI 色块：`0` 空闲 `1` 运行中 `3` 已终止 |
| `HoldKeyArr` | 当前仍按住的键，结束时按需松开 |
| `KilledArr` | 已被终止 |
| `PauseArr` | 已暂停 |
| `ActionCount` | 已执行循环次数 |
| `ToggleStateArr` / `ToggleActionArr` | 开关触发的状态与定时器 |
| `VariableMapArr` | 该条宏的内置变量（循环次数、流程控制标记等） |
| `IsWorkIndexArr` | 是否正在被 Worker 执行 |
| `GraphBranchCountArr` | 图形宏并行分支引用计数 |
| `UnderPosY` / `Index` / `SliderValue` / `OffSetPosY` | UI 布局 |
| `AllConArr` / `AllGroup` / `ConIndexMap` | UI 控件 |
| `FoldOffsetArr` / `FoldBtnArr` | 折叠框布局 |

分析配置时：**禁用看 `ForbidArr` 和 `FoldInfo.ForbidStateArr`；触发看 `TKArr` + `TriggerTypeArr`；内容看 `MacroArr`。**

---

## 2. ItemFoldInfo — 模块（折叠框）

一条模块管一组宏。菜单宏、界面宏的触发键挂在模块上，不挂在单条宏上。

| 字段 | 含义 |
|------|------|
| `RemarkArr` | 模块备注 |
| `FrontInfoArr` | 模块前台限制。空=任意窗口。格式见「前台窗口」 |
| `IndexSpanArr` | 本模块覆盖的宏下标范围，如 `1-5`、`无-无` |
| `ForbidStateArr` | 模块禁用（禁用后该模块手动触发无效，宏操作仍可调用） |
| `FoldStateArr` | UI 是否折叠 |
| `TKTypeArr` | 模块触发类型（菜单宏用） |
| `TKArr` | 模块触发键（菜单轮盘 / 界面浮窗开关） |
| `HoldTimeArr` | 模块长按/双击时间 |
| `UnorderedTriggerArr` | 模块组合键是否只按顺序注册 |

前台窗口格式：

- 窗口信息：`标题⎖类名⎖进程名`（三项用 `⎖` 分隔，可留空）
- 句柄列表：`❖hwnd1|hwnd2`

---

## 3. ItemConInfo / MacroItemInfo

仅 UI 布局用，不出现在用户配置里。`IsTitle` 是折叠框标题行，`IsDel` 表示已删除隐藏。

---

## 4. MainConfig（MainSoftData）— 软件全局设置

对应 `Setting/MainSettings.ini` 的 `[UserSettings]`。  
字段与设置页对照见 `04-软件设置选项.md`。此处列配置键名，方便直接读 ini。

### 4.1 配置方案

| 字段 | ini 键 | 说明 |
|------|--------|------|
| `CurSettingName` | `CurSettingName` | 当前方案名，默认 `RMT默认配置` |
| `SettingArrStr` | `SettingArrStr` | 全部方案名，`π` 分隔 |
| `HasSaved` | `HasSaved` | 是否保存过（影响是否写入默认示例宏） |
| `IsReload` | `IsReload` | 重载中（定时「软件启动时」会跳过） |
| `AgreeAgreement` | `AgreeAgreement` | 已同意免责 |

### 4.2 启动与窗口

| 字段 | 默认 | 说明 |
|------|------|------|
| `IsBootStart` | false | 开机自启 |
| `IsAdminStart` | false | 管理员启动 |
| `IsMinStart` | false | 最小化到托盘启动 |
| `SoftBGColor` | `f0f0f0` | 背景色 6 位 HEX |
| `Theme` | `RMT_Light` | XAML 主题 |
| `ShowSplitLine` | false | 表格分割线 |
| `IsModalSubGui` | true | 子窗口模态 |

### 4.3 页签

`TabNameArr` / `TabSymbolArr` 固定对应：

| 索引 | 页签名 | 符号（ini 前缀） |
|------|--------|------------------|
| 1 | 按键宏 | `Normal` |
| 2 | 字串宏 | `String` |
| 3 | 菜单宏 | `Menu` |
| 4 | 界面宏 | `UI` |
| 5 | 定时宏 | `Timing` |
| 6 | 宏 | `SubMacro` |
| 7 | 按键替换 | `Replace` |
| 8 | 工具 | `Tool` |
| 9 | 设置 | `Setting` |
| 10 | 帮助 | `Help` |
| 11 | 打赏作者 | `Reward` |
| 12 | 特别感谢 | `Thank` |

### 4.4 全局热键（默认）

| 字段 | 默认 | 功能 |
|------|------|------|
| `SuspendHotkey` | `!p`（Alt+P） | 休眠 |
| `PauseHotkey` | `!i` | 暂停所有宏 |
| `KillMacroHotkey` | `!k` | 终止所有宏 |
| `ToolCheckHotKey` | `!o` | 鼠标信息 |
| `ToolRecordMacroHotKey` | `!r` | 指令录制 |
| `ToolTextFilterHotKey` | `!u` | 文本提取 |
| `ScreenShotHotKey` | `!y` | 截图 |
| `FreePasteHotKey` | `!t` | 自由贴 |

`!` = Alt，`^` = Ctrl，`+` = Shift，`#` = Win。空字符串表示未绑定。

### 4.5 数值浮动 / 多线程 / 按键

| 字段 | 默认 | 说明 |
|------|------|------|
| `HoldFloat` | 0 | 点击持续时间浮动 % |
| `PreIntervalFloat` | 0 | 多次点击/搜索间隔浮动 % |
| `IntervalFloat` | 0 | 间隔指令浮动 % |
| `CoordXFloat` / `CoordYFloat` | 0 | 坐标浮动 px |
| `MutiThreadNum` | -1 | `-1` 动态，`0` 单线程，`n` 固定 n 线程 |
| `DynamicCorePoolSize` | 2（读盘）/ 3（类默认） | 动态模式核心池 |
| `ElasticTimeout` | 30 | 弹性 Worker 超时秒 |
| `MacroStopType` | 1 | `1` 智能终止 `2` 强制终止 |
| `KeyDownDownType` | 1 | `1` 自动松开 `2` 忽略重复按下 `3` 允许重复按下 |
| `AutoLoosenModifier` | true | 组合键触发前松开修饰键 |
| `ContinuousTrigger` | true | 按住可连续触发 |

### 4.6 其它常用

| 字段 | 默认 | 说明 |
|------|------|------|
| `ScreenShotType` | 3 | `1` 微软 `2` RMT `3` SC |
| `CheckForeground` | false | 仅前台运行宏（需宏/模块配置了前台） |
| `FontType` | 微软雅黑 | 界面字体 |
| `Lang` | 中文 | 语言 |
| `JoyType` | Xbox | 宏实际输出的虚拟手柄：Xbox / DS4 |
| `TriggerJoyType` | Xbox | 界面显示用手柄映射：Xbox / PS5 |
| `PreferredMacroEditor` | 1 | `1` 逻辑树 `2` 图形节点 |
| `SharedCopy` | false | 逻辑树显示「共享复制」 |
| `RemarkAutoType` | 2 | `1` 不生成 `2` 自动生成 `3` 覆盖生成 |
| `NoVariableTip` | true（读盘） | 变量不存在是否弹窗。类默认 false，以 ini 为准 |
| `FixedMenuWheel` | false | 轮盘固定在屏幕中下方 |
| `MenuWheelSelectMode` | 2 | `1` 点击 `2` 划线 |
| `MenuWheelShowTooltip` | false | 显示扇区名 |
| `MenuWheelScale` | 100 | 轮盘大小 50~200 |
| `UIPanelShowOnActive` | true | 窗口激活时显示浮窗 |
| `UIPanelBtnHeight/Width/FontSize/Cols` | 34 / 80 / 12 / 3 | 浮窗按钮 |
| `CMDTip` | false | 显示指令窗口 |
| `CMDLogToFile` | false | 指令日志写文件 |
| `CMDLogAutoClear` | 0 | `0` 从不 `1` 每天 `2` 每周 |
| `OCRTypeValue` | 1 | OCR 引擎 |

录制相关：`RecordKeyboard`、`RecordMouse`、`RecordJoy`、`RecordMouseTrail`（0 不录 / 1 关键点 / 2 相对位移 / 3 全量）、`RecordMouseTrailSpeed`、`RecordHoldMuti`、`RecordAutoLoosen`、`RecordJoyInterval`、`RecordShowBorder`。

---

## 5. SoftData（MySoftData）— 主进程与 Worker 共享运行态

分析配置一般不需要逐字段看。和读配置相关的：

| 字段 | 含义 |
|------|------|
| `TableInfo` | 全部页签的 `TableItem` |
| `DataFileMap` | 指令类型 → ini 文件路径 |
| `DataClassMap` | 指令类型 → 数据类 |
| `DataCacheMap` | 已读入的指令对象缓存 |
| `VariableMap` / `GlobalVariMap` | 全局变量 |
| `ArrayMap` / `GlobalArrMap` | 全局数组 |
| `TriggerKeyMap` | 已注册触发键 |
| `CMDTip` | 是否显示指令提示 |
| `CurSettingName` | 当前方案（Worker 用来拼路径） |
| `ContinueKeyMap` | 鼠标键按住连续触发的特殊处理 |
| `ContinueIntervale` | 连续触发间隔，50ms |
| `OnlyDownKeyMap` | 无松开事件的键：滚轮、亮度、None |
| `SpecialKeyMap` | 名称里带下划线的特殊键（Browser_Back 等） |

手柄映射表（`JoyXboxToAhkMap`、`JoyPS5ToAhkMap`、`PhysToXboxJoyMap` 等）用于把友好名（JoyA）和物理名（Joy1）互转。配置里手柄键统一存 Xbox 友好名。

---

## 6. 指令数据类（JSON 落盘）

宏字符串里复杂指令只写序列号，例如 `搜索3`、`循环1`。  
完整对象：`Setting/<配置名>/<类型>File.ini` 的 `[UserSettings]`，键=序列号，值=JSON。

`DataFileMap` / `DataClassMap`：

| 指令名 | 文件 | 类 |
|--------|------|-----|
| 搜索 / 搜索Pro | SearchFile.ini / SearchProFile.ini | SearchData |
| 移动Pro | MMProFile.ini | MMProData |
| 输出 | OutputFile.ini | OutputData |
| 运行 / 运行Pro | RunFile.ini | RunData |
| 循环 | LoopFile.ini | LoopData |
| 宏操作 | SubMacroFile.ini | SubMacroData |
| 变量 | VariableFile.ini | VariableData |
| 变量提取 | ExVariableFile.ini | ExVariableData |
| 如果 | CompareFile.ini | CompareData |
| 如果Pro | CompareProFile.ini | CompareProData |
| 运算 | OperationFile.ini | OperationData |
| 后台鼠标 | BGMouseFile.ini | BGMouseData |
| 后台按键 | BGKeyFile.ini | BGKeyData |
| 文本处理 | TextOpsFile.ini | TextOpsData |
| Timing | TimingFile.ini | TimingData |
| 数组 | ArrayFile.ini | ArrayData |
| 输入 | InputFile.ini | InputData |
| 文件读写 | FileIOFile.ini | FileIOData |
| 窗口管理 | WindowManageFile.ini | WindowManageData |
| 按键检测 | KeyCheckFile.ini | KeyCheckData |
| 手柄检测 | JoyCheckFile.toml | KeyCheckData |
| 注释 | CommentFile.ini | CommentData |
| 抓图 | ScreenShotFile.ini | ScreenShotData |
| 图形节点 | GraphNodeFile.ini | MacroGraphNode |
| 图形开始节点 | GraphStartNodeFile.ini | MacroGraphStartNode |

**间隔、按键、移动、RMT指令** 参数直接写在宏字符串里，没有独立 ini。

### 6.1 SearchData（搜索 / 搜索Pro）

| 字段 | 含义 |
|------|------|
| `SerialStr` | 序列号 |
| `ConfigName` | 分辨率配置名，如 `1920*1080_全屏` |
| `SearchType` | `1` 屏幕图 `2` 屏幕色 `3` 屏幕文 `4` 窗口图 `5` 窗口色 `6` 窗口文 |
| `WinInfo` | 窗口信息 |
| `SearchColor` | 颜色 HEX |
| `SearchText` | 检索文本（支持正则） |
| `SearchImagePath` | 图片路径 |
| `Similar` | 相似度 50~100 |
| `OCRType` | `1` 中文 `2` 英文 |
| `SearchImageType` | `1` OpenCV `2` RMT ImageSearch |
| `StartPosX/Y` `EndPosX/Y` | 搜索矩形 |
| `SearchCount` | 搜索次数；无限时会一直搜到找到为止 |
| `SearchInterval` | 每次间隔 ms |
| `MouseActionType` | `1` 无 `2` 移动到目标 `3` 移动并点击 |
| `Speed` | 移动速度 |
| `ClickCount` | 点击次数 |
| `ConfigArr` | 多分辨率配置 |
| `TrueMacro` / `FalseMacro` | 找到 / 未找到分支指令串 |
| `ResultToggle` | 是否把成败写入变量 |
| `ResultSaveName` / `TrueValue` / `FalseValue` | 结果变量 |
| `CoordToogle` | 是否保存目标中心坐标 |
| `CoordXName` / `CoordYName` | 坐标变量名 |

耗时约 `(检索时间 + 间隔) * 实际次数 - 间隔`。鼠标动作和分支同时开始，分支前常需加间隔。

### 6.2 ScreenShotData（抓图）

| 字段 | 含义 |
|------|------|
| `ScreenShotType` | `1` 屏幕 `2` 窗口 |
| `WinInfo` | 窗口抓图用 |
| `StartPosX/Y` `EndPosX/Y` | 区域 |
| `NameType` | `0` 动态名 `序列号-时间戳.png` `1` 固定名 |
| `FixedName` | 固定名（执行时补 `.png`） |
| `SavePath` | 类里有此字段，**执行不读**。实际目录固定为 `Setting/<方案>/Images/TempShot`，没写权限则 `A_Temp\RMT_TempShot\<方案>` |
| `ResultToggle` / `ResultSaveName` | 把图片完整路径写入变量 |

抓图走 OpenCV，与设置 `ScreenShotType`（微软/RMT/SC）无关。

### 6.3 CompareData（如果）

| 字段 | 含义 |
|------|------|
| `ToggleArr` | 条件开关（数量不限） |
| `NameArr` | 左值（变量名） |
| `CompareTypeArr` | `1>` `2>=` `3==` `4<=` `5<` `6` 包含 `7` 变量存在 `8` 正则 `9!=` |
| `VariableArr` | 右值 |
| `LogicalType` | `1` 且 `2` 或 |
| `TrueMacro` / `FalseMacro` | 分支 |
| `TrueControlType` / `FalseControlType` | `无` / `循环-跳过本轮` / `循环-跳出` / `分支-跳出` |
| `SaveToggle` / `SaveName` / `TrueValue` / `FalseValue` | 结果变量 |

执行顺序：**结果保存 → 分支指令 → 流程控制**。

### 6.4 CompareProData（如果Pro）

自上而下命中第一条，都不中则走默认。

| 字段 | 含义 |
|------|------|
| `VariNameArr` | 每条分支的左值列表 |
| `CompareTypeArr` | 每条分支的比较类型列表 |
| `VariableArr` | 每条分支的右值列表 |
| `LogicTypeArr` | 每条分支内部：`1` 且 `2` 或 |
| `ControlTypeArr` | 每条分支流程控制 |
| `MacroArr` | 每条分支指令 |
| `DefaultControlType` / `DefaultMacro` | 「以上都不是」 |

### 6.5 MMProData（移动Pro）

| 字段 | 含义 |
|------|------|
| `PosVarX` / `PosVarY` | 坐标，可为变量；取不到则不移动。绝对拖拽时为起始点 |
| `EndPosVarX` / `EndPosVarY` | 绝对拖拽的终止坐标，可为变量；相对拖拽不使用 |
| `ActionType` | `1` 移动 `2` 移动后单击 `3` 移动后双击 `4` 拖拽 |
| `MouseMoveMode` | `0` 绝对 `1` 相对；旧值 `2` 游戏视角已拆为「增量移动」，仅旧配置兼容执行 |
| `RefMode` / `WinInfo` | 坐标基准：`0` 屏幕 `1` 窗口；基准为窗口且绝对移动时，坐标按窗口左上角偏移 |
| `Speed` | 速度 0~100，100 为瞬移；默认 `90` |
| `Count` / `Interval` / `ConfigArr` / `IsHumanMouse` | 旧配置遗留字段，新版不再写入；`IsHumanMouse` 为拟真轨迹，缺失按 0 |

拖拽（`ActionType=4`）：绝对移动时先到起始点按下左键，再移到终止点松开；相对移动时从当前指针按 `PosVarX/Y` 偏移拖动；异常中断也会松开左键。
拟真轨迹开启时鼠标动作固定为「移动」，罗技 / AHI 按键类型下按普通轨迹移动。

### 6.6 RunData（运行 / 运行Pro）

| 字段 | 含义 |
|------|------|
| `Target` | 路径 / 网址 / 命令行 |
| `Mode` | `1` Run 不等待 `2` RunWait 取退出码 `3` 管道无等待 `4` 管道并取 stdout/stderr |
| `Option` | 窗口：对应 Hide / 普通 / Min / Max |
| `StdIn` / `SaveNameArr` | 兼容补齐字段，旧配置可能没有 |

### 6.7 OutputData（输出）

| 字段 | 含义 |
|------|------|
| `Text` | 内容。`{变量}` 替换变量，`{ε数组名}` 替换数组 |
| `OutputType` | `发送内容` / `粘贴` / 临时提示 / 指令窗口 / 软件弹窗 / 系统语音 / 复制到剪切板 |
| `VariableName` | 部分类型用的变量名 |

### 6.8 FileIOData（文件读写）

| 字段 | 含义 |
|------|------|
| `OperType` | `读取Excel` / `写入Excel` / `读取文本文件` / `写入文本文件` |
| `Encoding` | 文本编码，默认 UTF-8 |
| `FilePath` | 路径 |
| `OperMode` | 随 OperType 变化：单元格、指定行/列、覆盖写入、追加写入等 |
| `NameOrSerial` | Excel 表名或序号（从 1） |
| `RowVar` `ColVar` `RowEndVar` `ColEndVar` | 行列，可为变量 |
| `TextRowVar` | 文本行号 |
| `Content` / `ArrName` | 写入内容或数组 |
| `SaveType` / `SaveName` | 读出保存到变量或数组 |

Excel 未打开时写入会很慢。

### 6.9 SubMacroData（宏操作）

| 字段 | 含义 |
|------|------|
| `MacroType` | `按键宏` / `字串宏` / `菜单宏` / `界面宏` / `定时宏` / `宏` / `当前宏` |
| `CallType` | `插入到当前宏` / `触发` / `暂停` / `取消暂停` / `终止` |
| `InsertCount` | 插入次数（无限循环的目标宏只插入一次） |
| `Index` | 配置时的目标宏显示序号 |
| `MacroSerial` | 运行和合并时使用的目标宏 ID |

`触发` = 并行再跑一条；`插入` = 把目标宏指令展开进当前指令流。

### 6.10 LoopData（循环）

| 字段 | 含义 |
|------|------|
| `LoopCount` | 次数 |
| `CondiType` | `1` 无 `2` 退出条件 `3` 继续条件 |
| `LogicType` | `1` 且 `2` 或 |
| `ToggleArr` `NameArr` `CompareTypeArr` `VariableArr` | 条件开关（数量不限，默认 2 条） |
| `LoopBody` | 循环体指令串 |

比较类型与「如果」相同（含正则）。

### 6.11 VariableData（变量）

| 字段 | 含义 |
|------|------|
| `IsIgnoreExist` | 变量已存在则跳过 |
| `ToggleArr` | 4 路开关 |
| `OperaTypeArr` | **以执行为准**：`1` 数值 `2` 随机 `3` 字符 `4` 系统 `5` 删除（源码注释写「4=删除」已过时） |
| `VariableArr` | 变量名 |
| `CopyVariableArr` | 数值/字符/系统的源 |
| `MinVariableArr` / `MaxVariableArr` | 随机范围 |

变量名不能为空、不能纯数字、不能含 `_`。全部是全局变量。系统变量不能赋值。

### 6.12 ExVariableData（变量提取）

| 字段 | 含义 |
|------|------|
| `ExtractStr` | 提取模板。`&x` 数字，`&c` 文本，`{变量}` 先替换 |
| `ExtractType` | 提取源：屏幕 / 剪切板 / 窗口 |
| `WinInfo` `OCRType` 范围与次数 | 同搜索 |
| `IsIgnoreExist` | 已存在则忽略 |
| `ToggleArr` / `VariableArr` | 最多 6 个结果变量 |

失败时：变量不存在则建成 `0`；已存在则不改。

### 6.13 OperationData（运算）

| 字段 | 含义 |
|------|------|
| `ToggleArr` | 4 路 |
| `UpdateNameArr` | 结果变量 |
| `ExpressionArr` | 表达式字符串（支持括号） |

运算不改表达式里原变量，只写入结果变量。

### 6.14 BGMouseData / BGKeyData

后台鼠标：`TargetTitle`（`标题⎖类名⎖进程名`）、`OperateType`（1 点击 2 双击 3 按下 4 松开）、`MouseType`（1 左 2 中 3 右 **4 滚轮**）、`PosVarX/Y`、`ScrollV`（垂直）/`ScrollH`（水平）、`ClickTime`（默认 50，仅点击/双击）。滚轮时垂直非 0 只滚垂直。命中多个 hwnd 各发一次。

后台按键：`FrontStr` 窗口信息、`KeyArr`、`Type`（1 按下 2 松开 3 点击）、`ClickTime`（默认 100，套 `HoldFloat`）`ClickCount` `ClickInterval`（默认 100，套 `PreIntervalFloat`）。组合键松开按相反顺序。

部分窗口无效，常需管理员。不走 `ModeArr`，不移动真实光标。

### 6.15 TimingData（定时宏）

| 字段 | 含义 |
|------|------|
| `StartStamp` | 毫秒时间戳，开始时间 |
| `EndStamp` | 毫秒时间戳，`0` 或不存在表示无结束 |
| `StampUnit` | `ms`。旧配置无此字段，读取时转换秒值 |
| `Type` | `单次` / `软件启动时` / `周期触发`。旧数字 `1` `2` `3` 仍按这个顺序对应；旧文案 `自定义` 视为周期触发 |
| `CustomInterval` | 周期数值，仅周期触发使用 |
| `CustomUnit` | `秒` `分钟` `小时` `天` `周` `月` |
| `DurationMode` | `无限制` / `固定时长`，缺省为无限制 |
| `Duration` | 固定时长的数值 |
| `DurationUnit` | 与 `CustomUnit` 相同 |

软件重载（`IsReload`）时不会再跑「软件启动时」。

### 6.16 ArrayData（数组）

| 字段 | 含义 |
|------|------|
| `Type` | `创建` `克隆` `删除` `包含` `取值` `赋值` `插入` `追加` `移除` `移除最后` `反转` `长度` |
| `Name` | 数组名 |
| `InitArr` | 创建时的初值 |
| `MainIndex` | 子索引，`0` 操作数组本身，`N` 操作第 N 项（从 1） |
| `ArgsType` / `ArgsName` | 参数 |
| `SaveType` / `SaveName` | 结果保存 |

支持二维。下标从 1。

### 6.17 RMTCMDData

类里仍有 `OperateType` 数字枚举，**执行已改为字符串**：宏里写 `RMT指令_类别_指令`。显示菜单为 `RMT指令_宏控制_显示菜单_序号`。

| 类别 | 指令 |
|------|------|
| 图文 | 截图、截图提取文本、自由贴 |
| 输入控制 | 启用/禁用 鼠标、键盘、键鼠、鼠标加速 |
| 宏控制 | 显示菜单、关闭菜单、暂停/恢复/终止所有宏 |
| 调试 | 开启/关闭变量监视、开启/关闭指令显示 |
| 软件自身 | 休眠、重载、关闭软件 |

输入控制需管理员。图文里的「截图」走设置 `ScreenShotType`，和「抓图」指令不是一条路。

### 6.18 TextOpsData（文本处理）

| 字段 | 含义 |
|------|------|
| `Type` | `文本分割` `文本提取` `文本替换` `去除空格` `大小写转换` `文本统计` `文本拼接` |
| `Name` | 源变量 |
| `ArgsType` / `ArgsName` | 分割符、定长、大小写类型等 |
| `Search` / `Replace` | 查找替换 |
| `MatchType` | `普通文本` 等 |
| `SaveType` / `SaveName` | 结果 |

### 6.19 InputData（输入）

| 字段 | 含义 |
|------|------|
| `Type` | `弹窗` `状态` `选择` `选择文件` `多选`，兼容旧 `继续` `继续&取消` |
| `PauseType` | `不暂停` `暂停当前宏` `暂停所有宏` |
| `CancelType` | `终止当前宏` `终止所有宏` |
| `SaveName` | 接收文本、状态、所选选项或文件路径的变量 |
| `Prompt` / `Options` | 提示文字和选项列表。选择文件时使用提示文字作为标题 |
| `TimeoutMs` / `TimeoutAction` | 超时毫秒数及超时后的动作，`0` 表示不限时 |
| `DefaultValue` | 选择「用默认值」时写入的内容 |

回车=真/继续，Esc=假/取消。输入弹窗打开时，Enter 触发键会被暂时禁用。

### 6.20 WindowManageData

- `窗口信息` 与 `调整窗口` 共用此数据类，兼容旧 `窗口管理` 序列。
- `SearchValue` 按 `标题⎖类名⎖进程名` 匹配，可引用变量。`MatchMode` 指定 `首个`、`最后` 或 `所有`。
- `ActionType` 指定查询或调整动作。查询结果写入 `ResultVar1` 至 `ResultVar7`，匹配窗口列表将句柄数组写入 `ResultVar1`。
- 调整时按动作使用 `PosX`、`PosY`、`Width`、`Height`、`NewTitle` 等字段。`CloseProcess` 为真时结束所属进程。

### 6.20.1 WaitData（等待）

- `WaitType` 指定条件，`Interval` 为检测间隔。`TimeoutMs` 为毫秒数，`0` 表示不限时。
- `ResultSaveName` 接收 `WaitCompletedValue` 或 `WaitTimedOutValue`，默认分别为 `0` 和 `1`。
- `Conditions` 和 `ConditionLogic` 存储变量条件及且、或关系。`KeyOptions` 存储选键及检测选项。`TimeConfig` 和 `ConfirmConfig` 分别保存时间和人工确认参数。

### 6.21 KeyCheckData（按键检测 / 手柄检测）

| 字段 | 含义 |
|------|------|
| `KeyArr` | 检测的键。按键检测为键盘鼠标名；手柄检测为 `JoyA` / `JoyDpadUp` / `JoyAxisLX:80` 等 |
| `CheckType` | 按键：`1` 同时按下 `2` 有一个按下。摇杆：`1` 大于设定值 `2` 大于等于 `3` 等于 `4` 小于等于 `5` 小于 |
| `StateType` | `1` 物理（手指/罗技驱动/真实手柄） `2` 逻辑（含宏模拟） |
| `VarName` | 结果 1/0 |

按键检测存 `KeyCheckFile.toml`，手柄检测存 `JoyCheckFile.toml`，结构相同。

### 6.22 CommentData

`Content` 注释文本，执行时直接跳过。

### 6.23 KeyboardData / RecordNodeData / MoveData

录制过程用，一般不出现在用户分享的指令 JSON 里。

### 6.24 MouseWinData

运行时取鼠标下窗口。`CheckIfMatch` 用来匹配前台字符串。

### 6.25 SerialData

序列号分配器。新序列号形如 `搜索3` = 类型名 + 递增数字。

---

## 7. 图形宏节点

### MacroGraphStartNode

| 字段 | 含义 |
|------|------|
| `SerialStr` | 开始节点序列号 |
| `NodeArr` | 后继节点 SerialStr |
| `EmptyNode` | 没有前驱的空节点 |
| `X` `Y` | 画布坐标 |

### MacroGraphNode

| 字段 | 含义 |
|------|------|
| `CurCMD` | 该节点指令，默认 `间隔_50` |
| `NextNodeArr` | 后继 SerialStr |
| `X` `Y` `Folded` | 坐标与分支折叠 |
| `TrueBranchDX/DY` `FalseBranchDX/DY` 等 | 编辑器布局，不影响执行语义 |

图形宏可以并行执行分支。主进程按条目的 `GraphBranchCount` 汇总完成状态，最后由 `WorkPool.FinishGraphMacroItem` 统一收尾。

---

## 8. MsgType（进程消息）

| 值 | 含义 |
|----|------|
| `1` TASK | 主进程派任务给 Worker |
| `2` FINISH | Worker 告知任务结束 |
| `3` EVENT | 双向广播（如变量变更） |

---

## 9. 读配置时的快速对照

1. 打开 `MacroFile.ini`，按页签前缀找 `TKArr`、`TriggerTypeArr`、`ForbidArr`、`MacroArrN`。
2. 把 `MacroArr` 按逗号/换行/`⫶` 拆成指令。
3. `间隔_*` `按键_*` `移动_*` `RMT指令_*` 直接读参数。移动第四段是方式：`0` 绝对 `1` 相对 `2` 游戏视角。
4. 其它指令第一段是序列号，去对应 `*File.ini` 用序列号取 JSON，再对照本章字段。
5. 模块前台、模块禁用看 `FoldInfo` JSON。
