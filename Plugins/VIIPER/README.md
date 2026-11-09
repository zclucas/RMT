# VIIPER 输入后端

宏配置 → 按键类型 → **VIIPER**（Mode=5）。原来的四种类型编号不变。

## 使用前准备

1. 从 [usbip-win2 官方发布页](https://github.com/vadimgrn/usbip-win2/releases)安装 Windows 驱动，确认 `usbip.exe` 在 PATH 中。
2. 从 [VIIPER 官方发布页](https://github.com/Alia5/VIIPER/releases)下载 Windows 版本。
3. 在命令行运行 `viiper server --api.addr 127.0.0.1:3242 --usb.addr 127.0.0.1:3241`，保持服务运行。保留默认的本机自动挂载和本机免认证设置。
4. 在 RMT 的宏配置中选择 VIIPER。首次发送时会创建虚拟设备，预留一秒枚举时间；之后复用连接。

RMT 不附带或自动安装驱动、服务，不修改服务的认证配置。是否需要重启以驱动安装器提示为准。

## 支持范围

- 键盘按下、松开、点击及组合键，区分左右修饰键、主键盘和小键盘。
- 鼠标五键、纵向及横向滚轮、相对移动、移动后的点击及拖拽。
- 绝对坐标移动由 Windows 按预先计算的屏幕坐标执行。单独定位无需启动 VIIPER，点击和拖拽按键仍由虚拟鼠标发送。
- “游戏视角”沿用 RMT 原有的 `mouse_event` 行为；拟人轨迹不用于 VIIPER。
- 多媒体、浏览器及其他无法映射到键盘 HID 用法的键使用普通 AHK 发送，不属于驱动输入。

每个 RMT/Worker 进程创建自己的总线和设备。正常退出发送全松开并移除总线；主进程清理 Worker 的已记录按键时移除原总线，避免误用另一个虚拟键盘释放按键。进程被强杀且未能同步状态时，由 VIIPER 服务按默认断线超时（5 秒）移除设备。

## 排查

- 连接失败：确认 VIIPER 正在运行，API 地址为 `127.0.0.1:3242`，未强制要求本机认证。
- 能连接但无输入：查看 VIIPER 控制台中的自动挂载错误，确认 usbip-win2 驱动已安装、`usbip.exe` 可执行；服务的 API 成功应答不代表驱动挂载成功。
- 首次点击无效：Windows 首次枚举可能超过一秒，待设备完成挂载后重新运行宏。
- 服务中途停止：当前宏会报告发送错误。恢复服务后重新运行宏。
- 驱动输入可能触发 RMT 的热键，避免宏输出再次触发自身。

协议实现参考 [官方 TCP API](https://github.com/Alia5/VIIPER/blob/main/docs/api/overview.md)、[键盘](https://github.com/Alia5/VIIPER/blob/main/docs/devices/keyboard.md)和[鼠标](https://github.com/Alia5/VIIPER/blob/main/docs/devices/mouse.md)文档。当前仅接入本机默认端口的无认证 TCP API。
