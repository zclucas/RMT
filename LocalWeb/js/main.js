// RMT 主界面 JavaScript
// 处理与 AHK 的双向通信

let currentData = {};
let currentTabIndex = 1;
let tabDataCache = {};

// 获取 ahk 宿主对象（同步方式）
function getAhkObj() {
    if (window.chrome && window.chrome.webview && window.chrome.webview.hostObjects) {
        return window.chrome.webview.hostObjects.sync.ahk;
    }
    return null;
}

// 初始化
document.addEventListener('DOMContentLoaded', function() {
    initTabs();
    loadInitialData();
});

// 初始化 Tab 点击事件
function initTabs() {
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            const index = parseInt(this.getAttribute('data-index'));
            switchTab(index);
        });
    });
}

// 加载初始数据
function loadInitialData() {
    var ahk = getAhkObj();
    if (!ahk) {
        console.log('等待 ahk 对象...');
        setTimeout(loadInitialData, 500);
        return;
    }
    try {
        var result = ahk.GetInitialData();
        console.log('GetInitialData 返回:', result);
        if (result && result.configName) {
            renderUI(result);
        } else {
            setTimeout(loadInitialData, 1000);
        }
    } catch(e) {
        console.log('GetInitialData 错误:', e.message || e);
        setTimeout(loadInitialData, 1000);
    }
}

// 渲染 UI
function renderUI(data) {
    if (!data) return;
    var ahk = getAhkObj();
    document.getElementById('configName').textContent = data.configName || '未设置';

    var formatHotkey = function(hk) {
        if (!hk) return '-';
        if (ahk && ahk.FormatHotkey) {
            try { return ahk.FormatHotkey(hk); } catch(e) {}
        }
        return hk.replace(/^!/gi, 'Alt+').replace(/^\+/gi, 'Shift+').replace(/^#/gi, 'Win+').replace(/^\^/gi, 'Ctrl+');
    };

    document.getElementById('suspendToggle').checked = data.isSuspend || false;
    document.getElementById('suspendHotkey').textContent = formatHotkey(data.suspendHotkey);
    document.getElementById('pauseToggle').checked = data.isPause || false;
    document.getElementById('pauseHotkey').textContent = formatHotkey(data.pauseHotkey);
    document.getElementById('killHotkey').textContent = formatHotkey(data.killHotkey);

    if (data.tabIndex) { switchTab(data.tabIndex); }
    if (data.tabNames && data.tabNames.length > 0) { updateTabNames(data.tabNames); }
    if (data.bgColor) { document.body.style.backgroundColor = '#' + data.bgColor; }
}

function updateTabNames(names) {
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach((tab, index) => {
        if (names[index]) { tab.textContent = names[index]; }
    });
}

// 切换 Tab
function switchTab(index) {
    if (index === currentTabIndex) return;
    currentTabIndex = index;
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
        const tabIndex = parseInt(tab.getAttribute('data-index'));
        if (tabIndex === index) { tab.classList.add('active'); }
        else { tab.classList.remove('active'); }
    });
    if (window.ahk && window.ahk.TabChange) { window.ahk.TabChange(index); }
    updateTabContent(index);
}

// 获取指定Tab的数据
function loadTabData(tabIndex) {
    var ahk = getAhkObj();
    if (!ahk || !ahk.GetMacroData) { return null; }
    try {
        var result = ahk.GetMacroData(tabIndex);
        var data = typeof result === 'string' ? JSON.parse(result) : result;
        return data;
    } catch(e) {
        console.log('GetMacroData error:', e.message || e);
        return null;
    }
}

// 更新 Tab 内容
function updateTabContent(index) {
    const content = document.getElementById('tabContent');
    const tabRenderers = {
        1: renderKeyMacroTab,
        2: renderStrMacroTab,
        3: renderMenuMacroTab,
        4: renderTimingMacroTab,
        5: renderMacroTab,
        6: renderReplaceKeyTab,
        7: renderToolTab,
        8: renderSettingTab,
        9: renderHelpTab,
        10: renderDonateTab,
        11: renderThanksTab
    };
    const renderer = tabRenderers[index];
    if (renderer) { content.innerHTML = renderer(); }
    else { content.innerHTML = '<div class="placeholder"><p>未知 Tab</p></div>'; }
}

// ========== Tab1: 按键宏 ==========
function renderKeyMacroTab() {
    return renderCommonMacroTab(1);
}

// ========== Tab2: 字串宏 ==========
function renderStrMacroTab() {
    return renderCommonMacroTab(2);
}

// ========== Tab3: 菜单宏 ==========
function renderMenuMacroTab() {
    return renderCommonMacroTab(3);
}

// ========== Tab4: 定时宏 ==========
function renderTimingMacroTab() {
    return renderCommonMacroTab(4);
}

// ========== Tab5: 宏 ==========
function renderMacroTab() {
    return renderCommonMacroTab(5);
}

// 通用宏Tab渲染函数
function renderCommonMacroTab(tabIndex) {
    var data = loadTabData(tabIndex);
    var tabNames = ['按键宏', '字串宏', '菜单宏', '定时宏', '宏', '按键替换'];
    var tabName = tabNames[tabIndex - 1] || '宏';

    if (!data || !data.folds || data.folds.length === 0) {
        return '<div class="tab-panel tab-' + tabName + '"><div class="empty-tip"><p>暂无' + tabName + '配置</p><p>点击"新增宏"或"新增模块"开始创建</p></div></div>';
    }

    var html = '<div class="tab-panel tab-' + tabName + '"><div class="fold-container">';

    for (var f = 0; f < data.folds.length; f++) {
        var fold = data.folds[f];
        var foldToggleIcon = fold.foldState ? '⤻' : '❛';

        html += '<div class="fold-item" data-fold-index="' + f + '">';
        html += '<div class="fold-header">';
        html += '<div class="fold-title">';
        html += '<input type="text" class="remark-input" placeholder="备注" value="' + escapeHtml(fold.remark || '') + '">';
        html += '<span class="fold-label">前台:</span>';
        html += '<input type="text" class="front-input" placeholder="前台窗口" value="' + escapeHtml(fold.frontInfo || '') + '">';
        if (tabIndex !== 3) { html += '<button class="btn-edit-front">编辑</button>'; }
        html += '</div>';
        html += '<div class="fold-actions">';
        html += '<button class="btn-add-macro">新增宏</button>';
        html += '<button class="btn-add-fold">新增模块</button>';
        html += '<button class="btn-del-fold">删除模块</button>';
        html += '<label class="checkbox-forbid">';
        html += '<input type="checkbox" ' + (fold.forbid ? 'checked' : '') + '><span>禁用</span></label>';
        html += '<button class="btn-fold-toggle">' + foldToggleIcon + '</button>';
        html += '</div></div>';

        html += fold.foldState ? '<div class="fold-content" style="display:none;">' : '<div class="fold-content">';
        html += '<div class="item-header">';
        html += '<span class="col-name">宏名称</span>';
        html += '<span class="col-trigger">触发编辑器</span>';
        html += '<span class="col-type">触发类型</span>';
        html += '<span class="col-loop">循环次数</span>';
        html += '<span class="col-setting">宏设置</span>';
        html += '<span class="col-edit">宏编辑器</span>';
        html += '</div>';

        var macros = data.macros || [];
        var indexSpan = fold.indexSpan.split('-');
        var startIdx = parseInt(indexSpan[0]);
        var endIdx = parseInt(indexSpan[1]);

        if (startIdx && endIdx) {
            for (var m = 0; m < macros.length; m++) {
                var macro = macros[m];
                if (macro.index >= startIdx && macro.index <= endIdx) {
                    html += renderMacroItemHtml(macro, f);
                }
            }
        }
        html += '</div></div>';
    }
    html += '</div></div>';
    return html;
}

// 渲染单个宏项HTML
function renderMacroItemHtml(macro, foldIndex) {
    var triggerTypeArr = ['按下', '松开', '松止', '开关', '长按'];
    var triggerType = macro.triggerType || 1;
    var html = '<div class="macro-item" data-index="' + macro.index + '" data-fold="' + foldIndex + '">';
    html += '<span class="item-color"' + (macro.color ? ' style="background:' + macro.color + '"' : '') + '></span>';
    html += '<span class="item-index">' + macro.index + '.</span>';
    html += '<input type="text" class="item-remark" placeholder="备注" value="' + escapeHtml(macro.remark || '') + '">';
    html += '<button class="item-trigger">' + escapeHtml(macro.tk || '') + '</button>';
    html += '<select class="item-type">';
    for (var t = 0; t < triggerTypeArr.length; t++) {
        html += '<option value="' + (t + 1) + '"' + (triggerType == t + 1 ? ' selected' : '') + '>' + triggerTypeArr[t] + '</option>';
    }
    html += '</select>';
    html += '<input type="text" class="item-loop" value="' + escapeHtml(macro.loopCount || '1') + '">';
    html += '<button class="item-setting">设置</button>';
    html += '<button class="item-edit">编辑</button>';
    html += '<button class="item-move-up">↑</button>';
    html += '<button class="item-move-down">↓</button>';
    html += '<label class="item-forbid"><input type="checkbox" ' + (macro.forbid ? 'checked' : '') + '><span>禁用</span></label>';
    html += '<button class="item-del">删除</button>';
    html += '</div>';
    return html;
}

// HTML转义
function escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

// ========== Tab6: 按键替换 ==========
function renderReplaceKeyTab() {
    return renderCommonMacroTab(6);
}

// 获取工具Tab数据
function loadToolUIData() {
    var ahk = getAhkObj();
    if (!ahk || !ahk.GetToolUIData) { return null; }
    try {
        var result = ahk.GetToolUIData();
        var data = typeof result === 'string' ? JSON.parse(result) : result;
        return data;
    } catch(e) {
        console.log('GetToolUIData error:', e.message || e);
        return null;
    }
}

// ========== Tab7: 工具 ==========
function renderToolTab() {
    var data = loadToolUIData();
    var toolCheckHotkey = data ? data.toolCheckHotkey : '未设置';
    var isToolCheck = data ? data.isToolCheck : false;
    var posStr = data ? data.posStr : '';
    var winPosStr = data ? data.winPosStr : '';
    var processTitle = data ? data.processTitle : '';
    var processName = data ? data.processName : '';
    var processClass = data ? data.processClass : '';
    var processPid = data ? data.processPid : '';
    var processId = data ? data.processId : '';
    var color = data ? data.color : '';
    var recordHotkey = data ? data.recordHotkey : '未设置';
    var isRecording = data ? data.isRecording : false;
    var textFilterHotkey = data ? data.textFilterHotkey : '未设置';
    var ocrType = data ? data.ocrType : 1;

    var html = '<div class="tab-panel tab-tool">';
    html += '<div class="tool-section">';
    html += '<div class="tool-section-title">变量监视器</div>';
    html += '<div class="tool-row"><span class="tool-label">打开监视器</span><button class="btn-tool" onclick="openTool(\'varListen\')">打开监视器</button></div>';
    html += '</div>';

    html += '<div class="tool-section">';
    html += '<div class="tool-section-title">鼠标信息</div>';
    html += '<div class="tool-row"><span class="tool-label">热键：</span><span class="tool-value hotkey">' + toolCheckHotkey + '</span>';
    html += '<label class="checkbox-inline"><input type="checkbox" ' + (isToolCheck ? 'checked' : '') + '><span>开关</span></label>';
    html += '<label class="checkbox-inline"><input type="checkbox"><span>窗口置顶</span></label></div>';
    html += '<div class="tool-row"><span class="tool-label">屏幕坐标：</span><input type="text" class="tool-input" value="' + escapeHtml(posStr) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">窗口坐标：</span><input type="text" class="tool-input" value="' + escapeHtml(winPosStr) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">进程窗口标题：</span><input type="text" class="tool-input" value="' + escapeHtml(processTitle) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">进程名：</span><input type="text" class="tool-input" value="' + escapeHtml(processName) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">进程窗口类：</span><input type="text" class="tool-input" value="' + escapeHtml(processClass) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">进程PID：</span><input type="text" class="tool-input" value="' + escapeHtml(processPid) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">句柄Id：</span><input type="text" class="tool-input" value="' + escapeHtml(processId) + '"></div>';
    html += '<div class="tool-row"><span class="tool-label">位置颜色：</span><input type="text" class="tool-input" value="' + escapeHtml(color) + '"></div>';
    html += '</div>';

    html += '<div class="tool-section">';
    html += '<div class="tool-section-title">指令录制</div>';
    html += '<div class="tool-row"><span class="tool-label">热键：</span><span class="tool-value hotkey">' + recordHotkey + '</span>';
    html += '<label class="checkbox-inline"><input type="checkbox" ' + (isRecording ? 'checked' : '') + '><span>开关</span></label></div>';
    html += '</div>';

    html += '<div class="tool-section">';
    html += '<div class="tool-section-title">图片文本提取</div>';
    html += '<div class="tool-row"><span class="tool-label">热键：</span><span class="tool-value hotkey">' + textFilterHotkey + '</span>';
    html += '<button class="btn-tool" onclick="openTool(\'screenShot\')">截图提取文本</button>';
    html += '<button class="btn-tool" onclick="openTool(\'imageOcr\')">从图片提取文本</button></div>';
    html += '<div class="tool-row"><span class="tool-label">文本识别模型：</span>';
    html += '<select class="tool-select"><option value="1"' + (ocrType == 1 ? ' selected' : '') + '>中文</option>';
    html += '<option value="2"' + (ocrType == 2 ? ' selected' : '') + '>英文</option></select></div>';
    html += '</div>';

    html += '<div class="tool-section">';
    html += '<div class="tool-section-title">快捷工具</div>';
    html += '<div class="tool-grid">';
    html += '<div class="tool-card" onclick="openTool(\'searchImg\')"><div class="tool-icon">🔍</div><div class="tool-name">图片搜索</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'searchColor\')"><div class="tool-icon">🎨</div><div class="tool-name">颜色搜索</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'run\')"><div class="tool-icon">⚡</div><div class="tool-name">运行程序</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'compare\')"><div class="tool-icon">📋</div><div class="tool-name">文本对比</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'loop\')"><div class="tool-icon">🔁</div><div class="tool-name">循环测试</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'input\')"><div class="tool-icon">⌨️</div><div class="tool-name">自定义输入</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'mouse\')"><div class="tool-icon">🖱️</div><div class="tool-name">鼠标录制</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'bgmouse\')"><div class="tool-icon">📍</div><div class="tool-name">后台鼠标</div></div>';
    html += '<div class="tool-card" onclick="openTool(\'output\')"><div class="tool-icon">💬</div><div class="tool-name">输出信息</div></div>';
    html += '</div></div>';

    html += '</div>';
    return html;
}

// ========== Tab8: 设置 ==========
function renderSettingTab() {
    return '<div class="tab-panel tab-setting">' +
        '<div class="settings-section"><div class="settings-section-title">常规设置</div>' +
        '<div class="settings-item"><span class="item-label">启动时自动运行</span><span class="item-value"><input type="checkbox" checked></span></div>' +
        '<div class="settings-item"><span class="item-label">启动后自动休眠</span><span class="item-value"><input type="checkbox"></span></div>' +
        '<div class="settings-item"><span class="item-label">启动后最小化</span><span class="item-value"><input type="checkbox"></span></div></div>' +
        '<div class="settings-section"><div class="settings-section-title">热键设置</div>' +
        '<div class="settings-item"><span class="item-label">休眠切换</span><span class="item-value">F9</span></div>' +
        '<div class="settings-item"><span class="item-label">暂停切换</span><span class="item-value">F10</span></div>' +
        '<div class="settings-item"><span class="item-label">终止所有宏</span><span class="item-value">F11</span></div></div>' +
        '<div class="settings-section"><div class="settings-section-title">输出设置</div>' +
        '<div class="settings-item"><span class="item-label">显示执行提示</span><span class="item-value"><input type="checkbox" checked></span></div>' +
        '<div class="settings-item"><span class="item-label">显示执行时间</span><span class="item-value"><input type="checkbox" checked></span></div>' +
        '<div class="settings-item"><span class="item-label">提示音</span><span class="item-value"><input type="checkbox" checked></span></div></div>' +
        '<div class="settings-section"><div class="settings-section-title">高级设置</div>' +
        '<div class="settings-item"><span class="item-label">线程数</span><span class="item-value">3</span></div>' +
        '<div class="settings-item"><span class="item-label">最大循环次数</span><span class="item-value">9999</span></div></div>' +
        '</div>';
}

// ========== Tab9: 帮助 ==========
function renderHelpTab() {
    return '<div class="tab-panel tab-help"><div class="help-content">' +
        '<div class="help-section"><h3>快速入门</h3><p>欢迎使用 RMT 若梦兔按键宏！本软件可以帮助您自动化键盘鼠标操作。</p><p><strong>基本操作：</strong></p>' +
        '<p>1. 点击"新增宏"创建新的宏</p><p>2. 设置触发按键和触发类型</p><p>3. 编写宏指令内容</p><p>4. 保存配置并启用</p></div>' +
        '<div class="help-section"><h3>触发类型</h3><p><strong>按下</strong> - 按住按键时执行</p><p><strong>松开</strong> - 松开按键时执行</p>' +
        '<p><strong>松止</strong> - 松开按键后开始计时执行</p><p><strong>开关</strong> - 按一下执行，再按一下停止</p><p><strong>长按</strong> - 按住一定时间后执行</p></div>' +
        '<div class="help-section"><h3>常用指令</h3><p><strong>键盘指令：</strong></p><div class="help-code">KeyPress a; 按下 a 键\nKeyDown a; 按住 a 键\nKeyUp a; 松开 a 键</div>' +
        '<p><strong>鼠标指令：</strong></p><div class="help-code">Click 100, 200; 点击坐标\nMove 100, 200; 移动鼠标\nWheelDown; 向下滚动</div>' +
        '<p><strong>延时指令：</strong></p><div class="help-code">Sleep 1000; 延时 1 秒</div></div>' +
        '<div class="help-section"><h3>注意事项</h3><p>1. 使用前台窗口限定可以避免宏在不需要的窗口触发</p><p>2. 建议先在测试窗口验证宏功能</p><p>3. 如果宏无法执行，检查是否被休眠或暂停</p></div>' +
        '</div></div>';
}

// ========== Tab10: 打赏 ==========
function renderDonateTab() {
    return '<div class="tab-panel tab-donate"><div class="donate-card">' +
        '<div class="donate-icon">❤️</div><h2>支持 RMT</h2>' +
        '<p>如果您觉得 RMT 若梦兔按键宏对您有帮助，欢迎打赏支持作者的开发和维护工作！</p>' +
        '<div class="donate-qr"><img src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMDAiIGhlaWdodD0iMjAwIj48cmVjdCB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgZmlsbD0iI2YwZjBmMCIvPjx0ZXh0IHg9IjUwJSIgeT0iNTAlIiBkb21pbmFudC1iYXNlbGluZT0ibWlkZGxlIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjIwIiBmaWxsPSIjMzMzIj7lvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKHlvIDlj5HmqKEKPC90ZXh0Pjwvc3ZnPg==" alt="打赏二维码"></div>' +
        '<p>扫码打赏，金额随意，感谢支持！</p></div></div>';
}

// ========== Tab11: 感谢 ==========
function renderThanksTab() {
    return '<div class="tab-panel tab-thanks"><div class="thanks-card">' +
        '<div class="thanks-icon">🙏</div><h2>感谢名单</h2>' +
        '<p>感谢以下朋友对 RMT 的支持和赞助！</p>' +
        '<div class="thanks-list"><div class="thanks-item">😀 朋友A</div><div class="thanks-item">😀 朋友B</div><div class="thanks-item">😀 朋友C</div></div>' +
        '<p style="margin-top: 30px;">感谢大家的陪伴与支持！</p></div></div>';
}

// ========== 工具函数 ==========
function onSuspendChange() {
    if (window.ahk && window.ahk.SuspendToggle) { window.ahk.SuspendToggle(); }
}
function onPauseChange() {
    if (window.ahk && window.ahk.PauseToggle) { window.ahk.PauseToggle(); }
}
function killAllMacro() {
    var ahk = getAhkObj();
    if (ahk) { ahk.KillAllMacro(); }
}
function saveSetting() {
    var ahk = getAhkObj();
    if (ahk && ahk.SaveSetting) {
        try { ahk.SaveSetting(); console.log('保存成功'); updateTabContent(currentTabIndex); }
        catch(e) { console.log('保存失败:', e.message || e); }
    }
}
function reloadApp() {
    var ahk = getAhkObj();
    if (ahk) { ahk.Reload(); }
}
function openSettingMgr() {
    var ahk = getAhkObj();
    if (ahk) { ahk.ShowSettingMgr(); }
}
function openTool(toolName) {
    var ahk = getAhkObj();
    if (ahk && ahk.OpenTool) { ahk.OpenTool(toolName); }
}
function showHelp() {
    var ahk = getAhkObj();
    if (ahk) { ahk.ShowHelp(); }
    else { window.location.href = 'index.html'; }
}
function onAHKMessage(msg) {
    console.log('收到 AHK 消息:', msg);
    if (msg.action === 'initData' && msg.data) { renderUI(msg.data); }
    else if (msg.action === 'tabChanged' && msg.data) { switchTab(msg.data.tabIndex); }
}
window.onAHKMessage = onAHKMessage;
