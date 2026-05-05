# WebViewToo

WebViewToo 是一个 AutoHotkey v2 的 WebView2 封装库，用于在 AHK 程序中嵌入 Web 控件或创建基于 HTML/CSS/JavaScript 的窗口。

## 兼容性说明

当前版本与旧版 WebViewToo API 不完全兼容。如果已有脚本直接依赖旧接口，需要按新的类结构调整。

## 主要类

- `WebViewCtrl`：在普通 AHK `Gui` 中添加一个 WebView2 控件。
- `WebViewGui`：创建完整的 WebView 窗口，适合直接用 HTML/CSS/JavaScript 构建主界面。
- `WebViewSizer`：供 `WebViewGui` 内部使用的窗口缩放辅助类，一般不需要直接调用。

## 主要变化

- `WebViewGui` 取代旧的 `WebViewToo` 类名，用于明确区分窗口和控件。
- 路由机制已重做，可以把本地文件、文本、资源映射给 WebView 页面访问。
- `EnableGlobal()` 已改为对默认 host 自动初始化；其他 host 可使用 `AllowGlobalAccessFor()`。
- `Load()` 已移除，请使用 `Navigate()`。
- `Close()` 已移除，请使用 `Hide()` 或原生 `WinClose()`。

## RMT 集成约定

- RMT 只加载 `Plugins\WebViewToo\Lib\WebViewToo.ahk` 这一套 WebView2 封装。
- 不要同时 include `Plugins\WebView2\WebView2.ahk`，否则会重复声明 `class WebView2` 并导致程序启动失败。
- WebView 前端入口位于 `WebViewApp\dist\index.html`。
- WebView2 loader 位于 `Plugins\WebViewToo\Lib\32bit` 和 `Plugins\WebViewToo\Lib\64bit`。

## 常见问题

### 提示 `class WebView2 conflicts with an existing Class`

说明项目同时加载了两份 WebView2 AHK 封装。保留 WebViewToo 的 include，移除旧 `Plugins\WebView2\WebView2.ahk` include。

### WebView 页面空白

检查：

- `WebViewApp\dist\index.html` 是否存在。
- `WebViewApp\dist\assets` 是否包含 JS/CSS 产物。
- `Plugins\WebViewToo\Lib\32bit\WebView2Loader.dll` 和 `Plugins\WebViewToo\Lib\64bit\WebView2Loader.dll` 是否存在。
- 机器是否安装 Microsoft Edge WebView2 Runtime。

### 修改前端后页面没有变化

进入 `WebViewApp` 执行：

```powershell
npm.cmd run build
```

然后确认 `WebViewApp\dist` 已更新。
