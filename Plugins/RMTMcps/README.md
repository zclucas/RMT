# RMT MCP（RMTMcps.exe）

已适配 RMT 1.3F2。生成的配置默认使用 UTF-8 TOML，可继续解析、校验和编辑旧 INI 配置包。

若梦兔 `.rmt` 配置的 MCP 工具说明。本目录的 `RMTMcps.exe` 是独立 stdio 服务：**不启动 RMT 主程序也能用**；启动 RMT 也不会自动拉起本服务。

| 路径 | 说明 |
|------|------|
| `RMTMcps.exe` | MCP 服务（打包产物，无需本机 Python） |
| `mcp.example.json` | Cursor / AstrBot 配置示例 |
| `README.md` | 本文件：工具清单 + 接入说明（内置 AI 读取下方标记段） |
| `workspaces/` | 解包临时区 |
| `output/` | 生成的 `.rmt` |

运行时以 MCP `tools/list` 为准；**改工具后只更新本文件（尤其标记段），不必改 `AiAssistUtil.ahk`。**

---

<!-- RMT_AI_PROMPT_BEGIN -->
## 内置 AI 能力参考（RMTMcps）

你当前**不能直接调用** `RMTMcps.exe`。下列工具名与流程用于：解释配置能力、给出可落地的操作步骤与参数建议。若用户环境已接 Cursor/AstrBot MCP，可按其工具名引导对方调用。

### 工具一览

| 工具 | 作用 |
|------|------|
| `parse_rmt` | 下载/读取 `.rmt`，解包到临时工作区，返回 `workspace_id` |
| `list_rmt_files` | 列出工作区内文件 |
| `read_rmt_file` | 读工作区某文件（可限 `max_chars`，默认约 12000） |
| `write_rmt_file` | 写/改工作区文件（易踩 INI/编码坑，优先用 `edit_rmt_macro`） |
| `explain_rmt` | 配置可读摘要（触发键、指令中文描述等） |
| `validate_rmt` | 校验合法性，返回分级问题清单 |
| `edit_rmt_macro` | 结构化增/删/改宏，或宏内单条指令，并自动复校验 |
| `generate_rmt_config` | 按 JSON 规格生成并打包 `.rmt` |
| `pack_rmt` | 已编辑工作区重新打包为 `.rmt` |
| `list_rmt_outputs` | 列出 `output` 下已有 `.rmt` |
| `export_rmt_file` | 将 output 中文件导出为 base64（大包/沙盒发送） |
| `cleanup_rmt_workspace` | 清理：`workspace_id` / `all` / `expired` |

### 推荐流程

1. **解读已有配置**：`parse_rmt(source)` → `explain_rmt(workspace_id)` 或 `read_rmt_file` → 用完可 `cleanup_rmt_workspace`
2. **从零生成**：`generate_rmt_config(spec_json)`；小包看 `delivery.base64`；过大再 `export_rmt_file`
3. **改一条宏再打包**：`parse_rmt` → `edit_rmt_macro`（看 `validation`）→ `pack_rmt`
4. **只改一条指令**：`explain_rmt` 数出指令序号 → `edit_rmt_macro(operation="update_command", command_index=N)`；
   改配置型指令的参数则用 `data_configs` 按序列码 upsert，不必重建指令
5. **只校验**：`validate_rmt(workspace_id=...)` 或 `validate_rmt(source=...)`

### 关键约定

- `setting_name` / `pack_rmt` 的 `output_name`：纯英文（字母数字下划线连字符）；中文标题放 `title`
- `module`：Symbol 或中文均可，如 `Normal` / `按键宏`、`String` / `字串宏`、`Timing` / `定时宏`
- 宏序号 `index` 与指令序号 `command_index` 都是 **1-based**
- `edit_rmt_macro` 的 `operation`：
  - 宏级 `update`（默认）/ `add` / `delete`
  - 指令级 `update_command` / `add_command` / `delete_command`，配 `command_index` 与 `changes.command`
  - 图形级 `update_graph_node` / `add_graph_node` / `delete_graph_node`，配 `changes.node` / `after` / `command`
  - **只改一条指令时别用 `update` + `commands`**：那要求复述该宏全部指令，漏写会静默丢掉原指令
    （含配置型指令的序列码引用）
- `changes_json` / `commands` 可含：`trigger_key`、`remark`、`forbid`/`enabled`、`trigger_type`（1–6 或 按下/松开/松止/开关/长按/双击）、`mode`、`hold_time`、`loop_count`、`macro` 指令串或 `commands` 数组（二者优先 commands）
- **配置型指令**（宏里只有序列码，参数在对应 `*File.toml`）：
  - `search`/`搜索`、`search_pro`/`搜索Pro` → SearchFile / SearchProFile
  - `variable`/`变量`、`ex_variable`/`变量提取` → VariableFile / ExVariableFile
  - `loop`/`循环`、`compare`/`如果`、`compare_pro`/`如果Pro`
  - `output`/`输出`、`run`/`运行`、`submacro`/`宏操作`、`operation`/`运算`
  - `mmpro`/`移动Pro`、`bg_mouse`/`后台鼠标`、`bg_key`/`后台按键`
  - `text_ops`/`文本处理`、`array`/`数组`、`input`/`输入`、`file_io`/`文件读写`
  - `window`/`窗口管理`、`key_check`/`按键检测`、`comment`/`注释`、`screenshot`/`抓图`
  - `graph_node`/`图形节点`、`graph_start`/`图形开始节点`
  - 图形宏：`{"type":"graph_start","nodes":[{"command":{"type":"key","key":"a"}},{"command":{"type":"interval","ms":40}}]}`。不写 `next` 时按顺序串成一条链；`next` 用节点 `id` 且不能形成环；`free:true` 放进 EmptyNode
  - 改已有图：`edit_rmt_macro` 的 `update_graph_node` / `add_graph_node` / `delete_graph_node`。`after` 为 `start`、`free` 或「图形节点N」；`node` 指定要改/删的节点；`command` 是新指令。删节点时自动把前后连线接上
  - 通用写法：`{"type":"loop","count":"无限","body":[...]}` 或 `{"type":"如果","conditions":[{"left":"HP","op":"小于","right":"30"}]}`。`config` 里的键名须与 RMT DataClass 一致；简写会转成对应字段（如搜索 `text`/`color`/`count:"无限"`、输出 `mode:"粘贴"`→`粘贴内容`、运行 `mode:"等待+返回值"`）。运行会按 Mode 补齐 `SaveNameArr`/`StdIn`/`Encoding`；窗口透明度写成不带 `%` 的数值（如 `"80"`）
  - 也可 `data_configs` / `search_configs` / `loop_configs` 等按序列码 upsert
- 可内联的指令：`key` / `joy` / `interval` / `move` / `rmt` / `raw`
  - `interval`：`{"ms":3000}` 固定；`{"min":100,"max":300}` 随机区间（**必须成对给**，只给一个会报错）
  - `move`：`移动_X_Y_速度_方式`。方式 `mode`：`绝对`/`0`、`相对`/`1`、`游戏视角`/`2`；不写方式则省略（绝对）。`relative:true` 仍等价于相对
  - `rmt`：`RMT指令_类别_指令`；`action` 为「显示菜单」时再加 `menu` 序号
  - 任意类型可加 `"disabled":true`（🚫 禁用）或 `"debug":true`（⭐ 调试起点）
- 使用说明字段：`bot_name`、`config_purpose`、`operation_instructions`，须中文且结合实际配置
- 沙盒与宿主机文件系统隔离时：不要对宿主机 `output/` 做 `cp`；用响应内 `delivery.base64` 或 `export_rmt_file`
<!-- RMT_AI_PROMPT_END -->

---

## Cursor / AstrBot 接入

1. 参考同目录 [mcp.example.json](mcp.example.json)：`command` 为 `./RMTMcps.exe`，`workspaces` / `output` 用相对路径。
2. **RMT / 与 exe 同目录启动**：工作目录设为本目录，相对路径即可。
3. **Cursor 全局** `%USERPROFILE%\.cursor\mcp.json`：可先试相对路径；若不生效再改成指向本目录的绝对路径。
4. Cursor：**Settings → MCP** 确认启用；必要时 Reload / 重启。
5. 验证：应能列出 `parse_rmt`、`pack_rmt` 等（命名空间多为 `user-rmt-mcp`，服务名 `rmt-mcp`）。

AstrBot 同理：`args` 为空数组，按需设 `env`。换机优先带整目录，相对路径不用改盘符。

### 环境变量

| 变量 | 默认（相对 exe 旁） | 含义 |
|------|---------------------|------|
| `RMT_MCP_WORK_ROOT` | `./workspaces` | 解包工作区根目录 |
| `RMT_MCP_OUTPUT_ROOT` | `./output` | 打包输出目录 |
| `RMT_MCP_TTL_HOURS` | `24` | 过期清理 TTL（小时） |

### 能力发现（外部宿主）

- 宿主启动 exe 后走 MCP `tools/list`，得到工具名、描述与参数 schema。
- 本文档供人读、Code Review、以及 **RMT 内置 AI**（读取上方标记段）离线了解能力；不必为「列工具」去启动 RMT 主程序。

---

## 工具参数详解

### parse_rmt

- **必填** `source`：HTTP(S) 链接或本地路径  
- **返回**：`workspace_id`、解包文件列表、使用说明摘要等

### list_rmt_files

- **必填** `workspace_id`

### read_rmt_file

- **必填** `workspace_id`、`relative_path`（如 `MacroFile.toml`、`使用说明&署名.txt`）
- **可选** `max_chars`（默认约 12000）

### write_rmt_file

- **必填** `workspace_id`、`relative_path`、`content`  
- 注意：直接改 INI 需处理 UTF-16、π 数组等长、FoldInfo JSON、Serial 唯一等；日常改宏优先 `edit_rmt_macro`

### explain_rmt

- **二选一**（优先 `workspace_id`）：`workspace_id` 或 `source`  
- **返回**：`total_macros`、`tab_count`、`tabs[]`（每条宏含 trigger / enabled / remark / commands 可读描述）、`datafiles`  
- 对全部配置型序列码（搜索/变量/循环/如果/输出…）会读取对应 `*File.toml`，在 `commands[].config` 给出 JSON；缺配置标 `config_missing`；嵌套 `TrueMacro`/`LoopBody`/`MacroArr`/`CurCMD` 会递归解读。图形开始节点额外给出 `graph_nodes`

### validate_rmt

- **二选一**（优先 `workspace_id`）：`workspace_id` 或 `source`  
- **校验项摘要**：调用链死循环、页签字段齐全、触发键/按键名合法、指令类型与字段数、单宏指令过多（>1000 提醒）、分隔符/序列码/FoldInfo、数组等长与折叠框覆盖、定时宏结束时间、英文语系污染、**配置型序列码与全部 DataFile 双向匹配**（宏引用了但 DataFile 缺 → `datafile_serial_missing`；DataFile 有但没人引用 → `datafile_entry_orphan`，只是 warning，不影响运行）  
- **返回**：`valid`、`summary`、`issues[]`（severity/code/message/location）、`stats`

### edit_rmt_macro

- **必填** `workspace_id`、`module`
- **可选** `index`（除 `add` 外都必填）、`changes_json`、`operation`、`command_index`
- **`changes_json` 额外支持**：`commands` 里全部配置型 type（自动写 DataFile）；`data_configs` / `search_configs` / `loop_configs` 等按序列码 upsert
- **返回**：`operation`、`module`、`macro_count`、`edited_macro`、`edited_command`（指令级操作的前后对照）、`datafiles_updated`、`validation`

`operation` 六种取值：

| operation | 作用 | 需要 | 说明 |
|-----------|------|------|------|
| `update` | 改整条宏 | `index` | `changes` 给 `trigger_key` / `remark` / `commands` 等 |
| `add` | 新增宏 | — | 追加到该页签末尾，`index` 忽略 |
| `delete` | 删整条宏 | `index` | 自动前移后续宏并修 FoldInfo |
| `update_command` | 替换一条指令 | `index`、`command_index` | `changes.command` 给新指令；**只给 `disabled`/`debug` 时仅切换 🚫/⭐ 标记、保留原指令参数** |
| `add_command` | 插入一条指令 | `index` | `command_index<=0` 或超末尾则追加；否则插到该位置之前 |
| `delete_command` | 删一条指令 | `index`、`command_index` | 宏内其余指令与分隔符风格（`,` 或换行 `⫶`）保持不变 |
| `update_graph_node` | 改一个图形节点 | `index` 或 `changes.start` | `node` 为「图形节点N」；可改 `command` / `next` / `x` / `y` |
| `add_graph_node` | 新增图形节点 | 同上 | `after`：`start`（默认）、`free` 或某个节点序列码；`command` 为该节点指令 |
| `delete_graph_node` | 删除图形节点 | 同上 | 把前驱直接连到被删节点的后继，并删掉该节点配置 |

改一条指令的两个例子：

```jsonc
// 把第 2 条指令改成 100~300ms 随机等待
operation="update_command", index=1, command_index=2
changes_json={"command": {"type": "interval", "min": 100, "max": 300}}

// 只禁用第 1 条指令，不动它的参数
operation="update_command", index=1, command_index=1
changes_json={"command": {"disabled": true}}
```

配置型指令的参数存在 `*File.toml`，改参数不用重建指令，按序列码 upsert 即可：

```jsonc
operation="update", index=1
changes_json={"data_configs": {"变量1": {"CopyVariableArr": ["99", "0", "0", "0"]}}}
```

### generate_rmt_config

- **必填** `spec_json`（字符串）。核心字段示例：

```json
{
  "setting_name": "F6ClickA",
  "title": "F6连点A键10次",
  "bot_name": "小助手",
  "config_purpose": "按下F6后自动连续点击A键10次，减少重复操作。",
  "operation_instructions": "1. 在若梦兔中导入并启用本配置。\n2. 按下F6即可连续点击A键10次。",
  "macros": [
    {
      "module": "Normal",
      "trigger_key": "F6",
      "remark": "连点A",
      "forbid": false,
      "commands": [
        {"type": "key", "key": "a", "action": "点击", "duration": 100, "count": 10, "interval": 200},
        {"type": "interval", "ms": 3000}
      ]
    }
  ]
}
```

搜索 + 循环 + 输出示例：

```json
{
  "setting_name": "CfgDemo",
  "title": "配置型指令演示",
  "macros": [
    {
      "module": "Normal",
      "trigger_key": "F7",
      "commands": [
        {"type": "variable", "name": "Var1", "value": "123"},
        {"type": "output", "text": "开始", "mode": "发送内容"},
        {"type": "loop", "count": 3, "body": "按键_a_点击_50,间隔_100"},
        {
          "type": "search",
          "config": {
            "SearchType": 3,
            "SearchText": "检索文本",
            "TrueMacro": "按键_k_点击",
            "FalseMacro": "间隔_500"
          }
        }
      ]
    }
  ]
}
```

- 高级：`files.MacroFile.toml` / `files.*File.toml` / `extra_files`（显式提供 `files.MacroFile.ini` 可生成旧格式）；也可用顶层 `data_configs` 或 `loop_configs` 等
- 中文 `setting_name` 会被改写，见响应 `name_adjusted`  
- 小包响应常带 `delivery.base64` 与 `delivery.send_workflow`

### pack_rmt

- **必填** `workspace_id`  
- **可选** `output_name`（纯英文文件名，不含路径）

### list_rmt_outputs

- 无参数；列出 output 下全部 `.rmt`

### export_rmt_file

- **必填** `file_path`：`output_path` 或 output 下文件名  
- 仅当内联 `delivery.base64` 为 null（包过大）时需要

### cleanup_rmt_workspace

- **必填** `workspace_id`：具体 ID，或 `all`（清 workspaces + output 下 `.rmt`），或 `expired`（按 TTL）

---

## 指令参数速查

`commands` 数组（`generate_rmt_config`）与 `changes.command`（`edit_rmt_macro` 指令级操作）用同一套 schema。

### 内联指令：参数直接写进宏串，不落 DataFile

| type | 参数 | 生成结果 |
|------|------|----------|
| `key` | `key`、`action`（按下/松开/点击，默认点击）、`duration`=100、`count`=1、`interval`=200 | `按键_a_点击_100_10_200` |
| `interval` | `ms`（固定，也可直接写 `"100~300"`）**或** `min`+`max`（随机区间，必须成对） | `间隔_3000` / `间隔_100~300` |
| `move` | `x`、`y`、`speed`=90、`mode`（`绝对`/`相对`，或 0/1；省略=绝对） | TOML 中整数坐标生成 `移动N`；变量坐标保留内联格式 |
| `rmt` | `category`、`action`；显示菜单再加 `menu` | `RMT指令_调试_开启指令显示` / `RMT指令_宏控制_显示菜单_2` |
| `raw` | `value`：原样写入的指令串，用于本表未覆盖的写法 | 原样 |

内联与配置型指令都支持以下开关。

| 字段 | 效果 | 生成结果 |
|------|------|----------|
| `disabled: true` | 该指令被禁用，RMT 执行时跳过 | `🚫按键_a_点击_100_1_200` |
| `debug: true` | 标为调试起点 | `⭐间隔_500` |

#### 按键

`key` 可传一个键名、以 `⎖` 分隔的组合或键名数组。逗号键自动写成 RMT 的 `逗号`。同时含多个带下划线的媒体键时，生成 `KeyDataFile.toml` 中的按键配置。动作是按下、松开或点击，数字 1、2、3 分别对应这三种动作。点击时 `duration` 为按住时长，`interval` 为两次点击间的等待，单位为毫秒。`count` 是正整数次数。

显式用 `key_config` 或传 `config` 可写入按键配置。旧录制里的 `按键_JoyAxisLX:75` 可读回。新手柄动作使用下述 `joy`。

#### 手柄

`{"type":"joy","buttons":["A","上"],"action":"点击","duration":50,"count":2,"interval":15}` 会按组合键后松开，点击时长和间隔均为毫秒。`buttons` 也可传 `"A+上"`。短名包括 A/B/X/Y、LB/RB、LT/RT、LS/RS、Back/Start/Home/Pad 和方向键上/下/左/右/无方向。

`{"type":"joy","axes":{"LX":-80,"RT":50}}` 设置左摇杆 X 与右扳机。摇杆轴 LX/LY/RX/RY 为 -100 到 100，扳机轴 LT/RT 为 0 到 100。0 表示回中或归零。轴会保持目标值，直到同轴指令更新或 RMT 停止并释放它。可同时给 `axes` 和 `buttons`，先设轴再发按钮。

#### 移动

`{"type":"move","x":800,"y":600,"speed":90}` 移到屏幕目标点。加 `"mode":"相对"` 或 `"relative":true` 时，X/Y 是相对当前指针的像素偏移，可为负数。速度为 0 到 100 的整数，100 表示瞬间到达。移动本身只改变指针位置。

整数坐标使用 `MoveDataFile.toml`，参数为 `PosX`、`PosY`、`Speed`、`MoveMode`。变量坐标可传 `"TargetX"` 或 `"{TargetX}"`，生成旧内联格式以保留运行时变量解析。

#### 移动Pro

`move_pro` 或 `mmpro` 支持 `x`、`y`、`speed`（0 到 100）、`mode`（绝对或相对）和 `action`（移动、移动后单击、移动后双击、拖拽、A到B拖拽）。绝对模式的「拖拽」从当前指针拖到 X/Y。「A到B拖拽」从 X/Y 拖到 `end_x`、`end_y`。相对拖拽按 X/Y 偏移。坐标接受数字或变量名。

默认使用屏幕基准。给 `window` 或 `reference:"窗口"` 后，绝对坐标以窗口左上角为原点。`window` 省略时使用宏绑定窗口。`human:true` 只用于纯移动。

#### 增量移动

`{"type":"delta_move","x":20,"y":-8,"count":2,"interval":15}` 使用游戏视角相对位移，先将总偏移 X/Y 除以次数，再分步发送。此例每步为 (10, -4)，两步之间等待 15 毫秒。运行端将每步位移转换为整数。次数须为正整数，间隔须为非负整数。四个字段都可传运行时变量名，如 `"count":"{Steps}"`。

参数落在 `DeltaMoveFile.toml`，字段为 `DeltaX`、`DeltaY`、`Count`、`Interval`。旧游戏视角的生成别名仍可用。

#### 后台按键

`{"type":"bg_key","window":"记事本⎖Notepad⎖notepad.exe","keys":["LCtrl","a"],"action":"点击","duration":15,"count":2,"interval":40}` 向匹配窗口发送按键消息。组合键按数组顺序按下、逆序松开，目标窗口须支持后台消息。`window` 省略时沿用宏绑定窗口。`duration` 是按下到松开的毫秒数，`interval` 是多次点击间的毫秒数，`count` 是正整数次数。

`BGKeyFile.toml` 使用 `FrontStr`、`KeyArr`、`Type`、`ClickTime`、`ClickCount`、`ClickInterval`。使用「松开」时，在同一宏里先向相同目标按下这些键。多个匹配窗口时，建议用精确标题或句柄选择一个目标。

#### 后台鼠标

`{"type":"bg_mouse","button":"右键","action":"双击","x":20,"y":40,"duration":50}` 向窗口发送鼠标消息。X/Y 是窗口客户区坐标，支持变量。按钮可选左键、中键、右键、滚轮。按钮动作可选点击、双击、按下、松开。`duration` 是点击和双击发送松开前的毫秒数。`window` 省略时使用宏绑定窗口。

`scroll_v`、`scroll_h` 是有符号的整数滚动量，单位为滚轮格。只给 `scroll_h` 时自动使用水平滚动。两项都非零时，运行端优先发送垂直滚动。当前 RMT 仅向首个匹配窗口发滚轮消息。

#### 按键检测

`{"type":"key_check","keys":["LShift","a"],"check":"同时按下","state":"物理状态","save":"Pressed"}` 读取键盘或鼠标当前状态。检测方式还可选「有一个按下」，状态还可选「逻辑状态」。物理模式查询物理按下状态，逻辑模式也能读取普通模拟按键的状态。条件满足时把 1 写入 `save`，否则写 0。结果变量默认 `Var1`。

在 `KeyCheckFile.toml` 中对应 `KeyArr`、`CheckType`、`StateType`、`VarName`。可在后续「如果」里读取结果。

#### 手柄检测

`{"type":"joy_check","buttons":["A","上"],"check":"任一","state":"逻辑状态","save":"Pressed"}` 检测按钮或方向键。按钮可用手柄短名、RMT 内部名或 `+` 组合。用 `axes` 检测轴，例如 `{"type":"joy_check","axes":{"LX":-80,"RT":50},"check":"<=","save":"Axes"}`。每个轴使用相同的比较方式，全部满足才写入 1，否则写入 0。比较可选 `>`、`>=`、`==`、`<=`、`<`，默认 `>=`。

按钮与轴使用不同检测方式，应分为两条指令。按钮支持物理或逻辑状态；轴直接读取设备数值。摇杆阈值为 -100 到 100，扳机为 0 到 100。轴阈值在 `JoyCheckFile.toml` 的 `KeyArr` 中以 `JoyAxisLX:-80` 等形式保存。

#### 搜索

`{"type":"search","color":"#AABBCC","x1":0,"y1":0,"x2":300,"y2":200,"mouse":"无动作"}` 在屏幕范围内找颜色。也可用 `image` 指定图片路径，或用 `text` 指定要匹配的文字和正则。坐标可传数字或变量，起点不得超过终点，文本范围须有宽高。鼠标动作可选「无动作」「移动至目标」「移动至目标点击1次」「移动至目标点击2次」。

`true_commands` 和 `false_commands` 分别配置命中与未命中分支，可用指令数组或宏串。参数写入 `SearchFile.toml`。用 `search` 指定窗口、多次重试或结果变量时，MCP 自动生成搜索 Pro。传入多个 `targets` 时生成搜索 Combo。

#### 搜索 Pro

`search_pro` 支持基础搜索的参数。加 `window` 可在指定窗口客户区搜索，也可显式选择窗口图片、颜色或文本。窗口目标接受标题、`ahk_class`、`ahk_exe`、`ahk_id` 或窗口条件对象；`{"hwnd":"{Handle}"}` 可引用全局句柄变量。`similar` 控制图片或颜色的相似度，范围为 0 到 100。`count` 是正整数或「无限」，`interval` 是两次尝试之间的毫秒数。无限模式只在找到时执行成功分支。

`save` 保存搜索成败，`true_value` 和 `false_value` 默认 1 和 0。`coord_x`、`coord_y` 保存命中点，未找到时保留原值。屏幕搜索可用 `speed` 和 `click_count` 调整移动与点击，窗口搜索可用无动作、后台点击或后台双击。OpenCV 图片可用 `color_match:true` 校对颜色。识图模型、OCR 引擎和自适应缩放从 RMT 软件设置读取。

要随包携带图片，将 `image` 设为 `Images/ScreenShot/pattern.png`，再在顶层 `extra_files` 写同路径的 `{"base64":"<图片内容>"}`。RMT 导入时会解析到实际配置目录。

#### 搜索 All

`{"type":"search_all","text":"OK","save":"Points","sort":"下上右左","result":"Matched"}` 一次查找同一目标的全部命中。用 `image`、`color` 或 `text` 选择目标，可通过 `window` 改用窗口搜索。命中点保存为 `[[x1,y1],[x2,y2],…]`，窗口模式为客户区坐标，屏幕模式为屏幕坐标。未找到时 `save` 收到空数组。可另用 `result` 保存成败，值由 `true_value` 和 `false_value` 指定。

`sort` 可选上下左右、上下右左、下上左右、下上右左。前两个字决定行顺序，后两个字决定同一行中的左右顺序。搜索 All 先保存完整数组，再执行找到分支。需要操作鼠标时，可在分支中遍历坐标。图像和颜色批量搜索使用 OpenCV。当前 Dev 已修复搜索 All 和无限搜索命中后的流程中断。MCP 保留针对早期 RMT 1.3F2 构建的兼容提示。

#### 搜索 Combo

`{"type":"search_combo","targets":[{"color":"AABBCC"},{"text":"继续","window":"ahk_class Edit"}],"satisfy":1,"save":"Matched"}` 按列表顺序检查目标。每个目标可以独立设置类型、范围、窗口、相似度、颜色匹配和备注。`satisfy` 默认「所有」，也可给 1 到目标总数的整数。满足数量后，本轮停止搜索其余目标。

整体的 `count`、`interval`、`mouse`、`save`、`coord_x`、`coord_y` 和成败分支与搜索 Pro 一致。多个命中共用坐标变量时，最终留下最后写入的位置。目标保存在 `SearchComboFile.toml` 的 `SearchTargetArr` 中。

#### 输入

`kind` 可选弹窗、状态、选择、选择文件、多选。分别保存输入文本、1/0、单项文本、所选文件的完整路径或逗号连接的多项文本。用 `prompt` 显示提示，文件选择用它作标题。用 `save` 指定变量，`pause` 可选暂停当前宏或暂停所有宏。

选择和多选可用 `options:["甲","乙","丙"]`，多选默认值也可传数组。选项本身不能包含逗号或换行。`timeout_ms` 默认为 0，表示不限时。可配置 `timeout_action` 为无、用默认值、保持原值、终止当前宏或终止所有宏。关闭或取消文件选择时保留变量原值。人工确认用等待指令的「确定」类型。

#### 输出

`mode` 可选发送内容、粘贴内容、临时提示、指令窗口、软件弹窗、系统语音、复制到剪切板或字符变量。发送和粘贴写到当前焦点，复制只写入剪切板，临时提示显示在鼠标旁。软件弹窗等待关闭，指令窗口输出供调试。

`text` 支持多行，运行时展开 `{变量名}` 和 `{ε数组名}`。用 `{"type":"output","text":"完成：{Count}","save":"Message"}` 可直接写到字符变量。`OutputFile.toml` 保存 `OutputType`、`Text` 和 `VariableName`。

#### 变量

`{"type":"variable","name":"HP","op":"数值","value":100}` 赋值。数值可引用另一个变量，随机数值使用 `min`、`max`，字符按原文本保存，系统和时间从指定的内置变量取值，删除移除目标变量。时间可读取当前年、月、周、星期、日、时、分或秒。

`slots` 可同时配置多行，每行可用 `enabled:false` 跳过。目标名须非空、非纯数字且不含下划线。`ignore_existing:true` 只在变量尚未存在时赋值，删除仍会执行。

#### 变量提取

`{"type":"ex_variable","source":"剪贴板","template":"HP：&x / 名：&c","slots":["HP","Label"]}` 从文本取数字和字符。`&x` 捕获数字，`&c` 捕获文本，`{变量名}` 在匹配前展开。空模板把全部文本存进第一个位置。最多六个位置，用 `null` 跳过某个位置时，后续位置的捕获序号保持原样。

`source` 可选屏幕、剪贴板或窗口。屏幕和窗口支持 `x1`、`y1`、`x2`、`y2`；窗口用 `window` 指定目标。可用 `count` 和 `interval` 控制重试，次数可为「无限」。从未赋值的结果变量先初始化为 0，`ignore_existing:true` 保留已有值。OCR 引擎从软件设置读取。

#### 运算

`{"type":"operation","expr":"max(HP-10,0)","save":"HP"}` 计算后写回指定变量。裸变量名会转换为 RMT 的 `{变量名}` 格式。支持加减乘除、取模 `%`、乘方 `^`、括号和 `abs`、`max`、`min`、`round`、`ceil`、`floor`。多个表达式可用 `expressions` 数组，每项可配置 `expr`、`save`、`enabled`。后续行可读取前面行刚写入的结果。

#### 数组

`{"type":"array","op":"创建","name":"Points","init":[[10,20],[30,40]]}` 创建可嵌套数组。`ignore_existing:true` 避免覆盖同名数组。`sub_index:0` 操作整个数组，正数选择某个子数组。`index` 是子数组或整个数组中的元素位置，从 1 开始，两种下标都可引用变量。

支持创建、克隆、删除、包含、取值、赋值、插入、追加、移除、移除最后、反转和长度。`value` 是数值或变量名，`array` 指向已有数组。取值和移除类操作用 `save`、`save_type` 指定结果。包含和长度写变量，克隆和反转写数组。插入用于现有位置，末尾新增用追加。

#### 文本处理

`source` 指定原文变量。运行端找不到同名变量时使用传入的文字。`save` 指定结果名称，分割和提取保存数组，其余类型保存变量。

- 文本分割可选内容分割、定长分割或正则匹配，`args` 对应分隔符、长度或正则。
- 文本提取可选数字提取、字母提取、中文提取或正则匹配。正则放在 `args`。
- 文本替换用 `search`、`replace` 和 `match_type`。匹配方式可选普通文本或正则匹配，正则替换可用 `$1` 等捕获组。
- 去除空格默认清理前后，可通过 `args_type` 选前、后或所有空白。大小写转换可选全部大写、全部小写、首字母大写。文本统计可选字符数、单词数、行数。
- 文本拼接把 `args` 接到 `source` 后面，拼接内容支持 `{变量名}`。省略来源时只输出拼接内容。

#### 文件读写

`{"type":"file_io","oper":"读取文件","path":"{Directory}/sample.txt","oper_mode":"逐行读取","row":2,"save":"Lines"}` 从第 2 行起保存为数组。读取全部内容和指定行写入变量。行号从 1 开始，可引用变量。

写入可选覆盖写入、追加写入、追加写入-行、指定行或行号自增，内容放在 `content`，支持 `{变量名}` 和 `{ε数组名}`。路径支持变量，写入可创建文件。默认编码 UTF-8，也可指定 ANSI、GB2312、GB18030、BIG5、UTF-16 或 Windows 代码页。配置保存于 `FileIOFile.toml`。

#### Excel

`{"type":"excel","oper":"read","path":"{Directory}/orders.xlsx","sheet":"订单","row":2,"col":1,"save":"Cell"}` 读取单元格显示文本。`sheet` 可用工作表名称或从 1 开始的序号。行列从 1 开始，可引用变量。指定行、列和区域的读取结果是数组。区域用 `row_end`、`col_end` 指定结束行列，并用「指定区域-行」或「指定区域-列」确定结果方向。

写入用 `oper:"write"`。单元格、行号自增、列号自增写 `content`，区域写入用 `array` 指向现有数组。执行需要本机 Excel 自动化环境和已有工作簿。

#### 网络请求

`method` 支持 GET、POST、PUT、DELETE。URL、请求头值和请求体可引用变量。请求头用 `headers` 对象或每行一个 `名称: 值`。JSON 请求体可传对象或原始 JSON 文本，表单可传对象或每行一个 `名称=值`，也支持原始文本类型。GET 不发送请求体。

`timeout_ms` 是单次请求的毫秒上限，范围 1 到 3600000。`retries` 是 0 到 10 或 `{变量名}`。网络错误、超时及 HTTP 408、429、5xx 会重试。通过三个不同的变量 `status`、`response`、`error` 保存结果。RMT 保留原始重定向响应。

#### 间隔

`{"type":"interval","ms":500}` 等待固定毫秒，0 表示立即继续。用 `min`、`max` 设置随机范围，下限需小于上限。也可传变量名，例如 `"ms":"{Delay}"`。等待时间会受到 RMT 的间隔指令浮动设置影响。

普通用法生成 `间隔_500` 或 `间隔_100~300`。用 `interval_config`、显式 `config` 或需要保留带下划线的变量名时，参数写入 `IntervalFile.toml`。

### 配置型指令：宏串里只留序列码，参数写进 `*File.toml`

配置型指令可用英文别名或 RMT 中文名。读取旧包时，参数也可来自同名 INI 文件。
所有配置型指令共用三个字段：

| 字段 | 作用 |
|------|------|
| `serial` | 指定序列码（如 `"搜索2"`）；不给则自动分配未占用的编号 |
| `remark` | 宏串里跟在序列码后的备注，如 `搜索1_找图` |
| `config` | 原样写入 DataFile 的字段字典，键名须与 `*File.toml` 一致 |

其中 5 种有友好简写，不必知道 INI 字段名：

| type | 简写参数 | 落到 DataFile 的字段 |
|------|----------|---------------------|
| `variable` / `变量` | `name`、`value`、`operation`（数值/随机/字符/系统/时间/删除）、`min`、`max`；多行用 `slots` | `VariableArr` / `CopyVariableArr` / `OperaTypeArr` / `MinVariableArr` / `MaxVariableArr` |
| `output` / `输出` | `text`、`mode` | `Text`、`OutputType` |
| `run` / `运行` | `target`、`mode` | `Target`、`Mode` |
| `comment` / `注释` | `text` 或 `content` | `Content` |
| `loop` / `循环` | `count`、`body` | `LoopCount`、`LoopBody` |

其它参数可通过 `config` 写入 RMT 的原生字段。
不确定字段名时的可靠办法：先 `parse_rmt` 一个已有同类配置，`explain_rmt` 会在
`commands[].config` 里给出该类型的完整 JSON，照着改即可。

### 1.3F2 指令示例

- 搜索 All 用 `{"type":"search_all","image":"Images/ScreenShot/ok.png","save":"Points","sort":"上下左右"}`。也可使用 `text` 或 `color`，通过 `window` 指定窗口。OCR 引擎在 RMT 软件设置里选择。
- 网络请求用 `{"type":"http_request","method":"GET","url":"http://127.0.0.1:8080/","timeout_ms":3000,"retries":1,"status":"Status","response":"Body","error":"Error"}`。可传 `headers`、`body_type` 和 `body`。
- 等待用 `{"type":"wait","ms":100,"max_ms":300,"timeout_ms":500,"save":"TimedOut"}`。省略 `max_ms` 时等待固定毫秒。确定弹窗用 `{"type":"wait_confirm","prompt":"是否继续？","timeout_ms":3000}`，写入等待指令的 `ConfirmConfig`。时间戳和时间区间可通过 `config.TimeConfig` 配置。
- 窗口信息用 `{"type":"window_info","action":"位置与宽高","match":"首个","results":["X","Y","Width","Height"]}`。`窗口状态` 的结果依次是存在、激活、最小化、最大化、置顶、透明度和鼠标穿透。
- 调整窗口用 `{"type":"window_adjust","action":"位置和宽高","x":20,"y":40,"width":800,"height":600}`。可用 `match` 指定所有、首个或最后的匹配项。`关闭窗口` 可加 `close_process: true`。
- 倒计时用 `{"type":"countdown","seconds":10,"wait_end":true}`。游戏视角位移用 `{"type":"delta_move","x":20,"y":-5,"count":2,"interval":15}`。
- 文件选择用 `{"type":"input","kind":"选择文件","save":"FilePath","timeout_ms":5000,"timeout_action":"保持原值"}`。
- 执行前后钩子通过宏级 `pre_macro` 和 `post_macro` 传宏串或结构化指令数组。宏级 `mode: 5` 选择 VIIPER。定时宏用 `timing_serial` 引用 `data_configs` 里的 `TimingN` 项，时间戳使用毫秒，可用 `DurationMode`、`Duration` 和 `DurationUnit` 设置任务时长。

---

## 沙盒发文件

AstrBot 等沙盒与宿主机文件系统隔离，**不要**对宿主机 `output/` 做 `cp`。  
小包用响应内联的 `delivery.base64`；大包先 `export_rmt_file` 再解码写入沙盒可写目录后发送。

---

## 维护

- **源码仓库中的发行文档模板是 `Release.README.md`**：增删工具、改参数说明、改 `RMT_AI_PROMPT` 标记段时，先改该文件，再同步到 `Release\README.md`（以及已拷贝的 `Dev\Plugins\RMTMcps\README.md`）。
- `.\build.ps1` 打包时会自动把 `Release.README.md`、`mcp.example.json` 复制进 `Release\`。
- 重新打包 exe 后：替换本目录 `RMTMcps.exe`，并核对本文（尤其 `RMT_AI_PROMPT` 标记段）是否仍一致。**无需改 AHK。**
- 内置 AI 只注入标记段；改标记段时注意控制长度（避免撑爆每次对话的 system prompt）。
- Python 源码可独立维护于其它目录；本目录只放 **exe + 配置示例 + 本文档**。


#### 等待

- `type: "wait"` 默认等毫秒。用 `ms` 指定固定时长，用 `ms` 加 `max_ms` 指定随机区间，两者可以引用 `{变量}`。时长、时刻、时间戳通过 `TimeConfig.Param1/Param2` 传入；时间区间可用 `start/end`、`time_kind`、`wait_outside` 和 `mismatch` 指定起止、时刻或时间戳、是否等待离开区间及未满足时的动作。原生字段 `Param1/Param2/Param5/WaitOutside/Param4` 也可用。
- 变量等待用 `conditions` 数组和 `logic`，每行指定 `variable`、`operator`、`value`。按下或松开等待用 `keys`、`device`、`check`、`state`；手柄轴阈值可写成 `LX:10`。
- 文件、窗口、进程等待用 `target`，进程可用 `process_target_type: "PID"`。屏幕变化使用原生起止坐标。鼠标移动、鼠标停止移动及剪切板变化无需目标。
- `interval` 是轮询周期，`timeout_ms: 0` 表示无超时。可用 `save` 保存状态。启用超时时，`completed_value` 和 `timed_out_value` 自定义结果；关闭超时时，完成值为 0。`wait_confirm` 用 `prompt`、`timeout_action` 及 `ConfirmConfig` 配置确认窗和暂停或终止作用范围。


#### 循环

- `type: "loop"` 的 `count` 接受非负整数、变量、`"无限"` 或 `-1`。`body` 和 `loop_commands` 均可写成子指令数组。
- `condi` 可选无、继续条件和退出条件，对应旧编号 1、2、3。进入每轮时先更新「循环次数」再检查条件。继续条件成立才执行，退出条件成立就结束，变量取值失败也会结束。
- `conditions` 的每行接受 `left`、`op`、`right` 和可选 `enabled`，`logic` 选且或。支持比较、包含、存在和正则匹配。无限循环可以用跳转结束。


#### 跳转

- `type: "jump"` 用 `action` 选循环跳过本轮（`continue`）、循环跳出（`break`）或分支跳出（`exit_branch`）。也接受原生中文动作名，保存为 `流程跳转_动作`。
- 循环动作作用于最近一层循环。可在该循环下的条件或搜索分支中触发。分支跳出结束当前执行的子指令序列，图形节点中会停止沿本节点继续走。


#### 如果

- `type: "compare"` 或 `"if"`。每个条件可指定 `left`、`op`、`right` 及 `enabled`。`logic` 为且或，条件支持数值比较、等于、不等于、字符包含、变量存在和正则。变量可写裸名或 `{变量}`。
- 用 `true_commands` 和 `false_commands` 设置真假分支，可分别留空。用 `save`、`true_value`、`false_value` 指定结果变量和两个值，结果先于分支写入。旧版控制字段仍可读取，新宏可在分支里使用跳转。
- 常规比较需要能取到左值，数值比较还需要能取到右值。取值失败会跳过本条指令。需要判断变量缺失时使用「变量存在」，并把后续动作放在假分支。


#### 如果 Pro

- `type: "compare_pro"` 的 `branches` 按优先级排序。每条分支提供 `conditions`、`logic`、`commands`，判断字段与「如果」一致。首个满足的分支获选，即使其指令为空。
- 所有比较都能完成且均未匹配时执行 `default_commands`。缺少必需变量时会结束本条判断。解析保留空分支的数组位置。
- 已有原生配置可继续提供各个分支数组。只传 `branch_commands` 会使用示例条件，生成业务宏时可以用 `branches` 为每个分支明确写出条件。

图形节点执行条件、搜索分支或循环体后，当前 Dev 会继续执行直接后继。解析和校验仍会提示早期 RMT 1.3F2 可能跳过这些连线。校验也会定位导入图中的环、缺失目标和无效连线。


#### 倒计时

- `type: "countdown"` 默认按时长。用 `seconds` 写总秒数，或用 `hours`、`minutes`、`second_part` 分开设置，支持变量。用 `kind: "clock"` 指定时刻，用 `kind: "timestamp"` 指定时间戳，两者都用 `target` 设置目标。
- `x/y` 是屏幕坐标。同一位置的新浮层替换旧浮层。默认显示后继续，`wait_end: true` 可生成仍受 RMT 支持的旧式等待行为。仅需阻塞时也可以使用独立「等待」指令。
- 已过期的绝对时间戳和 0 秒时长不会显示。按时钟时间倒数时，若今天该时刻已过，RMT 会顺延到次日。


#### 运行

- `type: "run"` 的 `target` 接受路径、网址和命令行。用双引号包住包含空格的可执行路径，并可用 `{变量}` 在运行时替换；字面花括号使用 `/{` 和 `/}`。
- 简版使用默认窗口，启动后继续。若在旧的 `run` 简写中指定高级模式或窗口选项，MCP 会自动生成「运行 Pro」。


#### 运行 Pro

- `type: "run_pro"` 的 `target` 与简版相同。用 `window` 选择后台、默认、最小化、最大化。
- `mode` 支持 `start`（不等待）、`wait`（等待并保存退出码）、`stdin`（发送标准输入后继续）和 `capture`（等待并保存退出码、标准输出、标准错误）。可使用对应中文模式名。
- `stdin` 文本可引用变量。通过 `encoding` 设置编码，或使用 `{"In":"UTF-8","Out":"CP936","Err":"UTF-8"}` 分别指定。用 `save` 设置结果变量，顺序为退出码、标准输出、标准错误。当前 Dev 已修复 UTF-16 输入末尾字节和跨块多字节字符，MCP 保留针对早期构建的编码提示。


#### 宏操作

- `type: "submacro"` 用 `macro_type` 选当前宏、中文页签名或页签标识。用 `index` 指定页签中从 1 开始的目标。生成同一配置中的宏时会绑定条目 ID，也可通过 `macro_serial` 直接指定 ID。
- `call` 支持 `insert`（同步插入）、`trigger`（另起并行宏）、`pause`、`resume`、`stop`。只有插入使用 `insert_count`，可填次数或变量。目标为当前宏时使用正在执行的条目。MCP 新增条目时会避开仍被引用的旧 ID，防止删除后误调用同序号的新宏。
- 校验会指出缺失的目标 ID，以及宏操作在分支或图形节点中形成的调用环。暂停、恢复和终止属于控制操作。


#### 窗口信息

- `type: "window_info"` 的 `window` 接受标题、`ahk_class` / `ahk_exe` 条件、`ahk_id` 或 `{"title":"标题","class":"类名","process":"程序.exe"}`、`{"hwnd":[123,456]}`。省略时使用宏绑定，亦可引用含 RMT 窗口条件的变量。
- `action` 支持位置与宽高、标题类名句柄、进程信息、窗口状态、匹配窗口列表。`match` 选择首个或最后；窗口列表还可选所有，默认所有。常规条件按窗口层叠顺序匹配可见窗口。
- `results` 可按界面字段顺序填写变量数组，也可按字段名指定，例如 `{"存在":"Exists","透明度":"Alpha"}`。空名称会跳过该字段。列表查询输出句柄数组，未命中为空数组。窗口状态未命中时「存在」为 0。


#### 调整窗口

- `type: "window_adjust"` 使用与窗口信息相同的 `window`，`match` 可选首个、最后或所有。可执行窗口激活、关闭、显示状态、移动、尺寸、置顶、穿透、标题和透明度操作。
- `x/y` 是绝对屏幕坐标或相对位移。宽高用 `width/height`，须为正整数。坐标和尺寸可引用变量。`title` 设置新标题，`opacity` 为 0～100，可写 `"80%"` 或变量。
- `close_process: true` 只对关闭窗口生效，会结束匹配窗口所属进程。


#### RMT 指令

- `type: "rmt"` 或 `"rmt_config"`，用 `action` 选择图文、输入控制、宏控制、调试或软件自身的动作，可同时指定 `category`。
- 显示菜单用 `menu` 选择从 1 开始的菜单序号。`rmt` 生成兼容内联格式，`rmt_config` 生成当前 Dev 支持的配置型菜单指令。
- 禁用模块或取消禁用模块使用 `module`（页签标识）和 `fold_id`（例如 `Normal.Module1`）。当前 Dev 已修复模块操作参数位置，校验保留针对早期构建的提示。


#### 抓图

- `type: "screenshot"` 支持屏幕和窗口。用 `source` 指定类型，或用 `window` 指定窗口。窗口模式只抓首个匹配窗口，坐标以客户区为基准；屏幕模式使用屏幕坐标。
- 用 `x1/y1/x2/y2` 设置区域，可填整数或 `{变量}`。终点须大于起点。用 `name` 指定固定文件名，重复执行会覆盖同名 PNG；用 `fixed: false` 生成唯一名称。
- 用 `save` 保存实际路径。RMT 使用 OpenCV，通常写入方案的 `Images/TempShot`，无法创建该目录时回退到用户临时目录。


#### 注释

- `type: "comment"` 用 `content` 或 `text` 写正文，可含多行、逗号和特殊符号。正文保存在 `CommentFile.toml`，解析时完整返回。
- 指令串附带前 20 个字符的摘要，长内容加省略号。摘要会过滤宏分隔符和执行标记。RMT 运行到注释时继续下一条指令。
