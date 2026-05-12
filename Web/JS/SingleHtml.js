const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WEB_DIR = path.dirname(__dirname);
const ROOT_DIR = path.dirname(WEB_DIR);
const OUTPUTS = [
  path.join(ROOT_DIR, 'index.html')
];

const iconMap = {
  '软件介绍': '📘',
  '快速上手': '🚀',
  '指令手册': '📖',
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
const PAGES = mdFiles.map((f, i) => {
  const name = path.basename(f, '.md');
  return { md: f, title: name, icon: iconMap[name] || defaultIcons[i % defaultIcons.length] };
});

function readWebText(...parts) {
  return fs.readFileSync(path.join(WEB_DIR, ...parts), 'utf-8');
}

function fixImagePaths(mdContent) {
  return mdContent.replace(/!\[([^\]]*)\]\(\/RMT\/Web\/([^)]+)\)/g, '![$1]($2)');
}

function imageToBase64(relPath) {
  const fullPath = path.join(WEB_DIR, relPath);
  if (!fs.existsSync(fullPath)) return relPath;
  const buf = fs.readFileSync(fullPath);
  const ext = path.extname(fullPath).toLowerCase();
  const mimeMap = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
  const mime = mimeMap[ext] || 'application/octet-stream';
  return `data:${mime};base64,${buf.toString('base64')}`;
}

function convertImagesInHtml(html) {
  return html.replace(/src="(Images\/[^"]+)"/g, (match, src) => {
    return `src="${imageToBase64(src)}"`;
  });
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

const pageContents = PAGES.map(p => {
  let md = fs.readFileSync(path.join(WEB_DIR, p.md), 'utf-8');
  md = fixImagePaths(md);
  let htmlBody = marked.parse(md);
  htmlBody = convertImagesInHtml(htmlBody);
  return { ...p, body: htmlBody };
});

const navTabs = pageContents.map((p, i) =>
  `<button class="tab${i === 0 ? ' active' : ''}" onclick="showPage(${i})">${p.icon} ${p.title}</button>`
).join('\n        ');

const pageDivs = pageContents.map((p, i) =>
  `<div class="page${i === 0 ? '' : ' hidden'}" id="page${i}"><div class="content">${p.body}</div></div>`
).join('\n    ');

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
.nav button{text-align:left;padding:10px 14px;border:none;background:transparent;color:#b0b8c8;font-size:13.5px;border-radius:6px;cursor:pointer;transition:all .15s;white-space:nowrap}
.nav button:hover{background:#2a2a5a;color:#fff}
.nav button.active{background:#4a6cf7;color:#fff;font-weight:600;box-shadow:0 2px 8px rgba(74,108,247,.3)}
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
@media(max-width:800px){.sidebar{width:56px}.sidebar h1{font-size:11px;padding:14px 6px;text-align:center}.nav button{padding:10px 6px;font-size:11px;text-align:center}.nav button span:last-child{display:none}}
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
        ${navTabs}
      </div>
</div>
<div class="main">
  <div class="content-area" id="contentArea">
      ${pageDivs}
    </div>
</div>
<aside id="docOutline" class="doc-outline" aria-label="目录大纲"></aside>

<script>
${markedSrc}
${hljsSrc}
marked.setOptions({gfm:true,breaks:true});

function showPage(i){
  document.querySelectorAll('.page').forEach(el=>el.classList.add('hidden'));
  document.querySelectorAll('.tab').forEach(el=>el.classList.remove('active'));
  document.getElementById('page'+i).classList.remove('hidden');
  document.querySelectorAll('.tab')[i].classList.add('active');
  document.getElementById('contentArea').scrollTop=0;
  hljs.highlightAll();
}
</script>
<script>
${searchScript}
</script>
</body>
</html>`;

OUTPUTS.forEach(output => fs.writeFileSync(output, fullHtml, 'utf-8'));

const sizeKB = Math.round(fs.statSync(OUTPUTS[0]).size / 1024);
console.log('\n✅ 打包完成!');
OUTPUTS.forEach(output => console.log(`   输出文件: ${output}`));
console.log(`   文件大小: ${sizeKB} KB`);
console.log(`   包含页面: ${PAGES.length} 个`);
console.log('   双击即可在浏览器中打开，无需任何依赖\n');
