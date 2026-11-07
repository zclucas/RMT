const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WEB_DIR = path.dirname(__dirname);
const ROOT_DIR = path.dirname(WEB_DIR);
const OUTPUTS = [
  path.join(ROOT_DIR, 'index.html')
];

// 这些文档按二级标题拆成独立子页，侧栏可展开收缩
const SPLIT_BY_H2 = new Set([
  '软件介绍',
  '快速上手',
  '指令手册',
  '命令行',
  '常见问题',
  '常见报错',
  '更新日志'
]);

const iconMap = {
  '软件介绍': '📘',
  '快速上手': '🚀',
  '指令手册': '📖',
  '界面宏字段绑定支持表': '🪟',
  '命令行': '💻',
  '常见问题': '❓',
  '常见报错': '⚠️',
  '开发指南': '🛠️',
  '更新日志': '📝'
};
const defaultIcons = ['📄', '📋', '📌', '🧭', '📎', '📧', '🗂️', '📎', '💡', '✓'];
const orderList = Object.keys(iconMap);
const mdFiles = fs.readdirSync(WEB_DIR).filter(f => f.endsWith('.md'));
mdFiles.sort((a, b) => {
  const na = path.basename(a, '.md'), nb = path.basename(b, '.md');
  const ia = orderList.indexOf(na), ib = orderList.indexOf(nb);
  if (ia !== -1 && ib !== -1) return ia - ib;
  if (ia !== -1) return -1;
  if (ib !== -1) return 1;
  return na.localeCompare(nb);
});
const DOC_FILES = mdFiles.map((f, i) => {
  const name = path.basename(f, '.md');
  return { md: f, title: name, icon: iconMap[name] || defaultIcons[i % defaultIcons.length] };
});

function readWebText(...parts) {
  return fs.readFileSync(path.join(WEB_DIR, ...parts), 'utf-8');
}

function fixImagePaths(mdContent) {
  return mdContent.replace(/!\[([^\]]*)\]\(\/RMT\/Web\/([^)]+)\)/g, '![$1]($2)');
}

function imageToBase64(relPath, baseDir = WEB_DIR) {
  const fullPath = path.isAbsolute(relPath) ? relPath : path.join(baseDir, relPath);
  if (!fs.existsSync(fullPath)) return '';
  const buf = fs.readFileSync(fullPath);
  const ext = path.extname(fullPath).toLowerCase();
  const mimeMap = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
  const mime = mimeMap[ext] || 'application/octet-stream';
  return `data:${mime};base64,${buf.toString('base64')}`;
}

// 与宏编辑器指令图标一致（SubGuiConfig）
const COMMAND_ICON_FILES = {
  "间隔": "Images/Soft/Interval.png",
  "按键": "Images/Soft/Key.png",
  "手柄": "Images/Soft/Joy.png",
  "搜索": "Images/Soft/Search.png",
  "搜索Pro": "Images/Soft/SearchPro.png",
  "搜索All": "Images/Soft/SearchAll.png",
  "搜索Combo": "Images/Soft/SearchCombo.png",
  "鼠标移动": "Images/Soft/Move.png",
  "鼠标移动Pro": "Images/Soft/MovePro.png",
  "增量移动": "Images/Soft/DeltaMove.png",
  "输出": "Images/Soft/Output.png",
  "运行": "Images/Soft/Run.png",
  "运行Pro": "Images/Soft/RunPro.png",
  "循环": "Images/Soft/Loop.png",
  "宏操作": "Images/Soft/MacroAction.png",
  "变量": "Images/Soft/Var.png",
  "变量提取": "Images/Soft/Extract.png",
  "如果": "Images/Soft/If.png",
  "如果Pro": "Images/Soft/IfPro.png",
  "运算": "Images/Soft/Operation.png",
  "RMT指令": "Images/Soft/rabit.png",
  "后台鼠标": "Images/Soft/Mouse.png",
  "后台按键": "Images/Soft/BGKey.png",
  "真": "Images/Soft/True.png",
  "假": "Images/Soft/False.png",
  "循环次数": "Images/Soft/LoopCount.png",
  "条件": "Images/Soft/Condition.png",
  "循环体": "Images/Soft/LoopBody.png",
  "文本处理": "Images/Soft/TextOps.png",
  "数组": "Images/Soft/Arr.png",
  "输入": "Images/Soft/Input.png",
  "文件读写": "Images/Soft/FileIO.png",
  "Excel": "Images/Soft/Excel.png",
  "流程控制": "Images/Soft/Control.png",
  "窗口管理": "Images/Soft/WindowManage.png",
  "窗口信息": "Images/Soft/WindowManage.png",
  "调整窗口": "Images/Soft/WindowAdjustGear32.png",
  "按键检测": "Images/Soft/KeyListen.png",
  "手柄检测": "Images/Soft/JoyListen.png",
  "注释": "Images/Soft/Comment.png",
  "抓图": "Images/Soft/ScreenShot.png",
  "等待": "Images/Soft/Wait.png",
  "等待确定": "Images/Soft/WaitConfirm.png",
  "时间": "Images/Soft/Time.png",
  "跳转": "Images/Soft/Control.png",
  "倒计时": "Images/Soft/Interval.png",
  "移动": "Images/Soft/Move.png",
  "移动Pro": "Images/Soft/MovePro.png",
  "组合搜索": "Images/Soft/SearchCombo.png",
  "搜索Multi": "Images/Soft/SearchCombo.png"
};

function getCommandNavParts(title) {
  const m = String(title || '').match(/^(\d+(?:\.\d+)?)\s+(.+)$/);
  const num = m ? m[1] : '';
  const cmdName = m ? m[2].trim() : String(title || '').trim();
  const rel = COMMAND_ICON_FILES[cmdName];
  const dataUri = rel ? imageToBase64(rel, ROOT_DIR) : '';
  const iconHtml = dataUri
    ? `<img class="tab-cmd-icon" src="${dataUri}" alt="" width="16" height="16">`
    : '';
  return { num, cmdName, iconHtml };
}

function convertImagesInHtml(html) {
  return html.replace(/src="(Images\/[^"]+)"/g, (match, src) => {
    const dataUri = imageToBase64(src, WEB_DIR);
    return dataUri ? `src="${dataUri}"` : match;
  });
}

function slugify(title) {
  return String(title || '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/[（）()【】\[\]：:、，,/\\]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

/** 按 ## 二级标题拆分；首个 ## 之前的内容丢弃（不再生成「概述」页） */
function splitMarkdownByH2(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const sections = [];
  let current = null;

  for (const line of lines) {
    const m = line.match(/^##\s+(.+)\s*$/);
    if (m) {
      if (current) sections.push(current);
      const title = m[1].trim();
      current = {
        title,
        slug: slugify(title),
        lines: [`# ${title}`, '']
      };
      continue;
    }
    if (current) current.lines.push(line);
  }
  if (current) sections.push(current);

  return sections.map((s) => ({
    title: s.title,
    slug: s.slug,
    md: s.lines.join('\n').trim()
  }));
}

function mdToHtml(md) {
  let text = fixImagePaths(md);
  let htmlBody = marked.parse(text);
  return convertImagesInHtml(htmlBody);
}

const markedSrc = readWebText('JS', 'marked.min.js');
const hljsSrc = readWebText('JS', 'highlight.min.js');
const vsCss = readWebText('CSS', 'vs.min.css');
const searchCss = readWebText('CSS', 'help-search-sidebar.css');
const searchScript = readWebText('JS', 'help-search-sidebar.js');

const ctx = vm.createContext({ ...global, exports: {}, module: { exports: {} } });
vm.runInContext(markedSrc, ctx);
const marked = ctx.exports;
marked.setOptions({ gfm: true, breaks: true });

// 扁平页面列表（与侧栏叶子节点一一对应，供搜索/跳转）
const pageList = [];
const navGroups = []; // 保持文档顺序的导航结构

for (const doc of DOC_FILES) {
  const rawMd = fs.readFileSync(path.join(WEB_DIR, doc.md), 'utf-8');
  if (SPLIT_BY_H2.has(doc.title)) {
    const parts = splitMarkdownByH2(rawMd);
    const children = [];
    for (const part of parts) {
      const route = `${doc.title}/${part.slug}`;
      const index = pageList.length;
      pageList.push({
        index,
        group: doc.title,
        groupIcon: doc.icon,
        title: part.title,
        slug: part.slug,
        route,
        body: mdToHtml(part.md)
      });
      const child = { index, title: part.title, route, num: '', cmdName: '', iconHtml: '' };
      if (doc.title === '指令手册') {
        Object.assign(child, getCommandNavParts(part.title));
        const category = part.md.match(/^所属分类：([^\r\n]+)/m);
        child.category = category ? category[1].trim() : '';
      }
      children.push(child);
    }
    navGroups.push({
      type: 'group',
      title: doc.title,
      icon: doc.icon,
      children
    });
  } else {
    const index = pageList.length;
    const route = doc.title;
    pageList.push({
      index,
      group: null,
      groupIcon: doc.icon,
      title: doc.title,
      slug: slugify(doc.title),
      route,
      body: mdToHtml(rawMd)
    });
    navGroups.push({
      type: 'leaf',
      title: doc.title,
      icon: doc.icon,
      index,
      route
    });
  }
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const navHtml = navGroups.map((g) => {
  if (g.type === 'leaf') {
    return `<button type="button" class="tab" data-index="${g.index}" data-route="${escapeHtml(g.route)}" onclick="showPage(${g.index})"><span class="tab-icon">${g.icon}</span><span class="tab-text">${escapeHtml(g.title)}</span></button>`;
  }
  let lastCategory = '';
  const kids = g.children.map((c) => {
    let categoryHtml = '';
    if (g.title === '指令手册' && c.category && c.category !== lastCategory) {
      categoryHtml = `<div class="nav-command-category">${escapeHtml(c.category)}</div>\n        `;
      lastCategory = c.category;
    }
    // 指令手册：序号 图标 名称；其它分组保持原标题
    let labelHtml = `<span class="tab-text">${escapeHtml(c.title)}</span>`;
    if (g.title === '指令手册' && (c.num || c.iconHtml)) {
      labelHtml = [
        c.num ? `<span class="tab-num">${escapeHtml(c.num)}</span>` : '',
        c.iconHtml || '',
        `<span class="tab-text">${escapeHtml(c.cmdName || c.title)}</span>`
      ].join('');
    }
    return `${categoryHtml}<button type="button" class="tab tab-sub${c.iconHtml || c.num ? ' has-cmd-icon' : ''}" data-index="${c.index}" data-route="${escapeHtml(c.route)}" data-group="${escapeHtml(g.title)}" onclick="showPage(${c.index})">${labelHtml}</button>`;
  }).join('\n        ');
  return `<div class="nav-group" data-group="${escapeHtml(g.title)}">
        <button type="button" class="nav-group-toggle" data-group="${escapeHtml(g.title)}" onclick="toggleNavGroup('${escapeHtml(g.title)}')" aria-expanded="false">
          <span class="tab-icon">${g.icon}</span><span class="tab-text">${escapeHtml(g.title)}</span><span class="nav-caret">▸</span>
        </button>
        <div class="nav-children" id="nav-group-${escapeHtml(g.title)}" hidden>
        ${kids}
        </div>
      </div>`;
}).join('\n      ');

const pageDivs = pageList.map((p, i) =>
  `<div class="page${i === 0 ? '' : ' hidden'}" id="page${i}" data-route="${escapeHtml(p.route)}" data-group="${escapeHtml(p.group || '')}"><div class="content">${p.body}</div></div>`
).join('\n    ');

const pageMetaJson = JSON.stringify(pageList.map(p => ({
  index: p.index,
  title: p.title,
  slug: p.slug,
  route: p.route,
  group: p.group
})));

const fullHtml = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RMT 帮助文档</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Microsoft YaHei","PingFang SC",Arial,sans-serif;background:#f5f7fa;color:#333;display:flex;height:100vh;overflow:hidden}
.sidebar{width:200px;background:#1a1a2e;color:#e0e0e0;display:flex;flex-direction:column;flex-shrink:0;border-right:1px solid #2a2a4a}
.sidebar h1{font-size:15px;padding:18px 16px 12px;background:#16213e;border-bottom:1px solid #2a2a4a;letter-spacing:1px}
.nav{display:flex;flex-direction:column;padding:8px 6px;gap:2px;overflow-y:auto;flex:1}
.nav button{text-align:left;padding:10px 14px;border:none;background:transparent;color:#b0b8c8;font-size:13.5px;border-radius:6px;cursor:pointer;transition:all .15s;white-space:nowrap;width:100%;display:flex;align-items:center;gap:6px}
.nav button:hover{background:#2a2a5a;color:#fff}
.nav button.active{background:#4a6cf7;color:#fff;font-weight:600;box-shadow:0 2px 8px rgba(74,108,247,.3)}
.nav-group{display:flex;flex-direction:column;gap:1px}
.nav-group-toggle{font-weight:600;color:#d7def0}
.nav-group-toggle .nav-caret{margin-left:auto;font-size:11px;opacity:.75;transition:transform .15s}
.nav-group.open .nav-group-toggle .nav-caret{transform:rotate(90deg)}
.nav-group.open .nav-group-toggle{color:#fff;background:#222b4d}
.nav-children{display:flex;flex-direction:column;gap:1px;padding:2px 0 6px 0}
.nav-children[hidden]{display:none!important}
.nav-command-category{margin:10px 10px 3px;padding:7px 2px 3px;border-top:1px solid #34405e;color:#d7def0;font-size:12px;font-weight:600;letter-spacing:.5px}
.nav-command-category:first-child{margin-top:2px;border-top:0}
.tab-sub{padding:7px 10px 7px 28px!important;font-size:12.5px!important;color:#9aa6bf}
.tab-sub.has-cmd-icon{padding-left:12px!important;gap:6px}
.tab-sub .tab-text{overflow:hidden;text-overflow:ellipsis}
.tab-num{flex-shrink:0;min-width:1.4em;font-variant-numeric:tabular-nums;opacity:.9}
.tab-cmd-icon{width:16px;height:16px;flex-shrink:0;object-fit:contain;border-radius:3px}
.tab-icon{flex-shrink:0}
.tab-text{overflow:hidden;text-overflow:ellipsis}
.main{flex:1;display:flex;flex-direction:column;overflow:hidden}
.content-area{flex:1;overflow-y:auto;padding:28px 40px;background:#fff}
.content{max-width:860px;margin:0 auto;line-height:1.85;font-size:14.5px}
.content h1{font-size:26px;color:#1a1a2e;border-bottom:3px solid #4a6cf7;padding-bottom:12px;margin-bottom:24px}
.content h2{font-size:20px;color:#2c3e70;border-bottom:1.5px solid #e0e8f5;padding-bottom:8px;margin:32px 0 16px}
.content h3{font-size:17px;color:#3a5080;margin:26px 0 12px}
.content p{margin:10px 0}
.content ul,.content ol{padding-left:24px;margin:10px 0}
.content li{margin:4px 0}
.content li>p{display:inline}
.content table{border-collapse:collapse;width:100%;margin:14px 0;font-size:13.5px}
.content th,.content td{border:1px solid #d0d8e8;padding:9px 13px;text-align:left}
.content th{background:#eaf0fe;font-weight:600;color:#2c3e70}
.content tr:nth-child(even){background:#fafbfd}
.content img{display:block;max-width:100%;height:auto;border-radius:6px;border:1px solid #e0e0e0;padding:4px;background:#fff;margin:10px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}
.content code{background:#f0f2f6;padding:2px 7px;border-radius:4px;font-size:0.92em;color:#c7254e}
.content pre{background:#f8f9fc;border:1px solid #e4e7ef;border-radius:8px;padding:16px 18px;overflow-x:auto;margin:14px 0;font-size:13.2px}
.content pre code{background:none;padding:0;color:inherit}
.content blockquote{border-left:4px solid #4a6cf7;margin:14px 0;padding:10px 18px;background:#f5f7ff;color:#556;border-radius:0 6px 6px 0}
.content hr{border:none;border-top:2px solid #eee;margin:32px 0}
.content strong{color:#1a1a2e}
.hidden{display:none!important}
@media(max-width:800px){.sidebar{width:56px}.sidebar h1{font-size:11px;padding:14px 6px;text-align:center}.nav button{padding:10px 6px;font-size:11px;text-align:center}.tab-text,.nav-caret{display:none}.tab-sub{padding-left:6px!important}.nav-children{padding-left:0}}
</style>
<style>${searchCss}</style>
<style>${vsCss}</style>
</head>
<body>
<div class="sidebar">
  <h1>🐰 RMT 文档</h1>
  <div class="sidebar-search" role="search">
    <label class="search-label" for="docSearchInput">搜索全部章节</label>
    <input id="docSearchInput" class="doc-search-input" type="search" placeholder="输入关键词" autocomplete="off">
    <button id="docSearchClear" class="doc-search-clear" type="button">清空搜索</button>
    <div class="search-options">
      <label class="search-toggle" data-tip="开启后，鼠标悬停搜索结果会临时跳到对应位置；移开后返回原阅读位置。"><input id="docSearchPreviewToggle" type="checkbox" checked> 预览</label>
      <label class="search-toggle" data-tip="开启后按 JavaScript 正则表达式搜索，例如 脚本|变量 或 \\d+。正则错误会直接提示。"><input id="docSearchRegexToggle" type="checkbox"> 正则</label>
    </div>
    <div id="docSearchStatus" class="search-status">输入关键词搜索全部章节</div>
    <div id="docSearchResults" class="search-results" aria-live="polite"></div>
  </div>
  <div class="nav">
      ${navHtml}
      </div>
</div>
<div class="main">
  <div class="content-area" id="contentArea">
      ${pageDivs}
    </div>
</div>
<aside id="docOutline" class="doc-outline is-empty" hidden aria-label="目录大纲"></aside>

<script>
${markedSrc}
${hljsSrc}
marked.setOptions({gfm:true,breaks:true});

const PAGE_META = ${pageMetaJson};

function findNavGroup(groupName){
  return Array.from(document.querySelectorAll('.nav-group')).find(function(el){
    return el.getAttribute('data-group') === groupName;
  }) || null;
}

function expandNavGroup(groupName, open){
  if(!groupName) return;
  const group = findNavGroup(groupName);
  if(!group) return;
  const children = group.querySelector('.nav-children');
  const toggle = group.querySelector('.nav-group-toggle');
  const shouldOpen = open === undefined ? !group.classList.contains('open') : !!open;
  group.classList.toggle('open', shouldOpen);
  if(children) children.hidden = !shouldOpen;
  if(toggle) toggle.setAttribute('aria-expanded', shouldOpen ? 'true' : 'false');
}

function toggleNavGroup(groupName){
  const group = findNavGroup(groupName);
  const willOpen = group && !group.classList.contains('open');
  expandNavGroup(groupName, willOpen);
  if(willOpen && group){
    const first = group.querySelector('.tab-sub');
    if(first){
      const idx = Number(first.dataset.index);
      if(!Number.isNaN(idx)) showPage(idx, false);
    }
  }
}

function findPageIndexByRoute(route){
  if(!route) return 0;
  route = decodeURIComponent(route).replace(/^#/, '').trim();
  if(!route) return 0;
  let idx = PAGE_META.findIndex(p => p.route === route);
  if(idx >= 0) return idx;
  const slash = route.indexOf('/');
  if(slash === -1){
    idx = PAGE_META.findIndex(p => p.route === route || p.title === route || p.group === route);
    if(idx >= 0) return idx;
    idx = PAGE_META.findIndex(p => p.group === route);
    return idx >= 0 ? idx : 0;
  }
  const group = route.slice(0, slash);
  const key = route.slice(slash + 1);
  idx = PAGE_META.findIndex(p => p.group === group && (p.slug === key || p.title === key));
  if(idx >= 0) return idx;
  // 指令重排后，编辑器及旧书签里的编号可能过期，优先按完整指令名定位。
  if(group === '指令手册'){
    // 别名统一为「旧名 -> 现名」：新名直接与页面标题相等，旧名经别名映射后命中，保证新编辑器与历史书签都能跳转
    const aliases = {'鼠标移动': '移动', '鼠标移动Pro': '移动Pro', '组合搜索': '搜索Combo', '搜索Multi': '搜索Combo', '时间': '倒计时', '窗口管理': '窗口信息', '流程跳转': '跳转'};
    const name = key.replace(/^\\d+(?:\\.\\d+)?[-\\s]+/, '');
    const command = aliases[name] || name;
    idx = PAGE_META.findIndex(p => p.group === group && p.title.replace(/^\\d+(?:\\.\\d+)?\\s+/, '') === command);
    if(idx >= 0) return idx;
  }
  idx = PAGE_META.findIndex(p => p.group === group && (p.slug.endsWith('-'+key) || p.title.endsWith(key) || p.title.includes(key)));
  if(idx >= 0) return idx;
  idx = PAGE_META.findIndex(p => p.group === group);
  return idx >= 0 ? idx : 0;
}

function showPage(i, updateHash){
  if(typeof updateHash === 'undefined') updateHash = true;
  if(i < 0 || i >= PAGE_META.length) i = 0;
  document.querySelectorAll('.page').forEach(el => el.classList.add('hidden'));
  document.querySelectorAll('.tab').forEach(el => el.classList.remove('active'));
  const page = document.getElementById('page'+i);
  if(page) page.classList.remove('hidden');
  const tab = document.querySelector('.tab[data-index="'+i+'"]');
  if(tab) tab.classList.add('active');
  const meta = PAGE_META[i];
  if(meta && meta.group) expandNavGroup(meta.group, true);
  const area = document.getElementById('contentArea');
  if(area) area.scrollTop = 0;
  if(typeof hljs !== 'undefined') hljs.highlightAll();
  if(updateHash && meta){
    const nextHash = '#'+meta.route;
    if(location.hash !== nextHash){
      history.replaceState(null, '', nextHash);
    }
  }
  if(typeof window.__onHelpPageChanged === 'function'){
    try{ window.__onHelpPageChanged(i); }catch(e){}
  }
}

function applyHashRoute(){
  const hash = location.hash ? location.hash.slice(1) : '';
  if(!hash){
    showPage(0, false);
    return;
  }
  showPage(findPageIndexByRoute(hash), false);
}

window.showPage = showPage;
window.toggleNavGroup = toggleNavGroup;
window.expandNavGroup = expandNavGroup;
window.findPageIndexByRoute = findPageIndexByRoute;
window.addEventListener('hashchange', applyHashRoute);
window.addEventListener('DOMContentLoaded', applyHashRoute);
applyHashRoute();
</script>
<script>
${searchScript}
</script>
</body>
</html>`;

// 直接 writeFileSync 截断已有文件时，若该文件被映射到内存（编辑器、杀毒扫描），
// Windows 返回的错误在 Node 里是 UNKNOWN(-4094)，open 直接失败。
// 先写入临时文件，再把旧文件挪走换上新文件，并短暂重试。
function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function writeOutput(output, data) {
  const dir = path.dirname(output);
  const base = path.basename(output);
  const tmp = path.join(dir, `.${base}.${process.pid}.tmp`);
  const bak = path.join(dir, `.${base}.${process.pid}.bak`);
  fs.writeFileSync(tmp, data, 'utf-8');
  let lastErr = null;
  for (let i = 0; i < 8; i++) {
    try {
      try { fs.rmSync(bak, { force: true }); } catch (e) {}
      if (fs.existsSync(output)) fs.renameSync(output, bak);
      try {
        fs.renameSync(tmp, output);
      } catch (err) {
        if (!fs.existsSync(output) && fs.existsSync(bak)) {
          try { fs.renameSync(bak, output); } catch (e) {}
        }
        throw err;
      }
      try { fs.rmSync(bak, { force: true }); } catch (e) {}
      return;
    } catch (err) {
      lastErr = err;
      const code = err && err.code;
      const retry = code === 'UNKNOWN' || code === 'EPERM' || code === 'EBUSY' || code === 'EACCES' || code === 'EEXIST';
      if (!retry || i === 7) break;
      sleepMs(150 * (i + 1));
    }
  }
  try { fs.rmSync(tmp, { force: true }); } catch (e) {}
  const detail = lastErr && lastErr.code === 'UNKNOWN'
    ? '文件可能正被其他程序占用（例如已在编辑器中打开）'
    : (lastErr && lastErr.message);
  const wrapped = new Error(`写入失败: ${output}\n${detail}`);
  wrapped.code = lastErr && lastErr.code;
  throw wrapped;
}

OUTPUTS.forEach(output => writeOutput(output, fullHtml));

const sizeKB = Math.round(fs.statSync(OUTPUTS[0]).size / 1024);
const groupCount = navGroups.filter(g => g.type === 'group').length;
console.log('\n✅ 打包完成!');
OUTPUTS.forEach(output => console.log(`   输出文件: ${output}`));
console.log(`   文件大小: ${sizeKB} KB`);
console.log(`   文档分组: ${navGroups.length}（其中可展开 ${groupCount}）`);
console.log(`   内容页面: ${pageList.length} 个`);
console.log('   直达示例: index.html#指令手册/按键');
console.log('   双击即可在浏览器中打开，无需任何依赖\n');
