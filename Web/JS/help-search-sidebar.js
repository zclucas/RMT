(function(){
  const input = document.getElementById('docSearchInput');
  const clearBtn = document.getElementById('docSearchClear');
  const previewToggle = document.getElementById('docSearchPreviewToggle');
  const regexToggle = document.getElementById('docSearchRegexToggle');
  const resultsBox = document.getElementById('docSearchResults');
  const statusBox = document.getElementById('docSearchStatus');
  const contentArea = document.getElementById('contentArea');
  const outlineBox = document.getElementById('docOutline');
  const pages = Array.from(document.querySelectorAll('.page'));
  const tabs = Array.from(document.querySelectorAll('.tab'));
  if (!input || !clearBtn || !previewToggle || !regexToggle || !resultsBox || !statusBox || !contentArea || !pages.length || typeof window.showPage !== 'function') return;

  const originalShowPage = window.showPage.bind(window);
  const pageHTML = pages.map(page => page.innerHTML);
  const pageData = pages.map((page, index) => {
    const titleEl = page.querySelector('h1,h2,h3');
    const tabText = tabs[index] ? tabs[index].textContent.replace(/\s+/g, ' ').trim() : '';
    const title = (titleEl ? titleEl.textContent : tabText || `第 ${index + 1} 页`).replace(/\s+/g, ' ').trim();
    const text = page.textContent.replace(/\s+/g, ' ').trim();
    const searchable = !(/更新日志|开发指南/.test(tabText));
    const shortTitle = tabText.includes(' ') ? tabText.slice(tabText.indexOf(' ') + 1).trim() : title;
    return { index, title, shortTitle, text, lowerText: text.toLowerCase(), searchable };
  });
  const pageSectionInfo = pages.map((page) => {
    const contentEl = page.querySelector('.content');
    if (!contentEl) return { h1Range: null, sections: [] };
    const fullText = contentEl.textContent.replace(/\s+/g, ' ').trim();
    const h1El = contentEl.querySelector('h1');
    const h2Elements = Array.from(contentEl.querySelectorAll('h2'));
    let h1Range = null;
    let searchOffset = 0;
    if (h1El) {
      const h1Text = h1El.textContent.replace(/\s+/g, ' ').trim();
      const idx = fullText.indexOf(h1Text);
      if (idx !== -1) {
        h1Range = { start: idx, end: idx + h1Text.length };
        searchOffset = h1Range.end;
      }
    }
    const sections = [];
    h2Elements.forEach((h2, i) => {
      const h2Text = h2.textContent.replace(/\s+/g, ' ').trim();
      const start = fullText.indexOf(h2Text, searchOffset);
      if (start === -1) return;
      const headingEnd = start + h2Text.length;
      searchOffset = headingEnd;
      const nextH2 = h2Elements[i + 1];
      let end;
      if (nextH2) {
        const nextText = nextH2.textContent.replace(/\s+/g, ' ').trim();
        const nextStart = fullText.indexOf(nextText, searchOffset);
        end = nextStart !== -1 ? nextStart : fullText.length;
      } else {
        end = fullText.length;
      }
      sections.push({ heading: h2Text, headingStart: start, headingEnd, sectionEnd: end });
    });
    return { h1Range, sections };
  });
  const highlightedPages = new Set();
  const maxResults = 200;
  let activePageIndex = Math.max(0, pages.findIndex(page => !page.classList.contains('hidden')));
  let previewState = null;
  let previewTimer = null;
  let suppressPreviewCancel = false;
  let focusedResult = null;

  function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function escapeHTML(value) {
    return value.replace(/[&<>"']/g, char => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    })[char]);
  }

  function buildOutline() {
    if (!outlineBox || !pages[activePageIndex]) return;
    const headings = Array.from(pages[activePageIndex].querySelectorAll('.content h2'))
      .filter(heading => heading.textContent.trim());
    outlineBox.innerHTML = '';
    const title = document.createElement('div');
    title.className = 'outline-title';
    title.textContent = '目录大纲';
    outlineBox.appendChild(title);
    if (!headings.length) {
      const empty = document.createElement('div');
      empty.className = 'outline-empty';
      empty.textContent = '当前页面没有可跳转标题';
      outlineBox.appendChild(empty);
      return;
    }
    headings.forEach((heading, index) => {
      const level = heading.tagName.toLowerCase();
      const text = heading.textContent.replace(/\s+/g, ' ').trim();
      const id = `doc-outline-${activePageIndex}-${index}`;
      heading.id = id;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `outline-link outline-${level}`;
      button.textContent = text;
      button.addEventListener('click', () => {
        outlineBox.querySelectorAll('.outline-link').forEach(item => item.classList.remove('active'));
        button.classList.add('active');
        heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
      outlineBox.appendChild(button);
    });
  }

  function restorePage(index) {
    if (!pages[index]) return;
    pages[index].innerHTML = pageHTML[index];
    highlightedPages.delete(index);
  }

  function restoreHighlights() {
    Array.from(highlightedPages).forEach(restorePage);
  }

  function getQuery() {
    return input.value.trim();
  }

  function getSearchConfig(query) {
    if (!query) return { regex: null, isRegex: regexToggle.checked };
    if (!regexToggle.checked) {
      return { regex: new RegExp(escapeRegExp(query), 'gi'), isRegex: false };
    }
    try {
      const regex = new RegExp(query, 'gi');
      const emptyMatch = regex.exec('');
      if (emptyMatch && emptyMatch[0] === '') {
        return { error: '正则表达式不能匹配空字符串' };
      }
      return { regex, isRegex: true };
    } catch (error) {
      return { error: `正则表达式无效：${error.message}` };
    }
  }

  function cloneRegex(regex) {
    return new RegExp(regex.source, regex.flags);
  }

  function findMatches(text, searchConfig) {
    const regex = cloneRegex(searchConfig.regex);
    const matches = [];
    let match;
    while ((match = regex.exec(text)) !== null) {
      if (match[0].length === 0) {
        regex.lastIndex += 1;
        continue;
      }
      matches.push({ index: match.index, text: match[0] });
    }
    return matches;
  }

  function highlightPage(index, searchConfig, activeMatchIndex = -1) {
    if (!pages[index] || !searchConfig || !searchConfig.regex) return;
    let pageMatchIndex = 0;
    const walker = document.createTreeWalker(pages[index], NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        const parent = node.parentElement;
        if (!parent || parent.closest('script,style')) return NodeFilter.FILTER_REJECT;
        return findMatches(node.nodeValue, searchConfig).length ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(node => {
      const text = node.nodeValue;
      const fragment = document.createDocumentFragment();
      let lastIndex = 0;
      let match;
      const regex = cloneRegex(searchConfig.regex);
      regex.lastIndex = 0;
      while ((match = regex.exec(text)) !== null) {
        if (match[0].length === 0) {
          regex.lastIndex += 1;
          continue;
        }
        if (match.index > lastIndex) {
          fragment.appendChild(document.createTextNode(text.slice(lastIndex, match.index)));
        }
        const mark = document.createElement('mark');
        mark.className = pageMatchIndex === activeMatchIndex ? 'doc-search-mark doc-search-active-mark' : 'doc-search-mark';
        mark.textContent = match[0];
        fragment.appendChild(mark);
        lastIndex = match.index + match[0].length;
        pageMatchIndex += 1;
      }
      if (lastIndex < text.length) {
        fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
      }
      node.parentNode.replaceChild(fragment, node);
    });
    if (nodes.length) highlightedPages.add(index);
  }

  function makeSnippet(text, matchIndex, matchText) {
    const start = Math.max(0, matchIndex - 42);
    const end = Math.min(text.length, matchIndex + matchText.length + 78);
    const prefix = start > 0 ? '...' : '';
    const suffix = end < text.length ? '...' : '';
    const before = text.slice(start, matchIndex);
    const hit = text.slice(matchIndex, matchIndex + matchText.length);
    const after = text.slice(matchIndex + matchText.length, end);
    return `${prefix}${escapeHTML(before)}<mark>${escapeHTML(hit)}</mark>${escapeHTML(after)}${suffix}`;
  }

  function scrollToMatch(pageIndex, matchIndex, isPreview) {
    const marks = pages[pageIndex].querySelectorAll('mark.doc-search-mark');
    const target = pages[pageIndex].querySelector('mark.doc-search-active-mark') || marks[Math.min(matchIndex, Math.max(0, marks.length - 1))];
    if (target) {
      target.scrollIntoView({ behavior: 'auto', block: 'center' });
    }
  }

  function getActiveSearchConfig() {
    const query = getQuery();
    const searchConfig = getSearchConfig(query);
    return query && !searchConfig.error ? searchConfig : null;
  }

  function switchPageSilently(index, activeMatchIndex = -1) {
    if (!pages[index]) return;
    const samePage = index === activePageIndex;
    activePageIndex = index;
    if (!samePage) {
      restoreHighlights();
      pages.forEach(page => page.classList.add('hidden'));
      tabs.forEach(tab => tab.classList.remove('active'));
      pages[index].classList.remove('hidden');
      if (tabs[index]) tabs[index].classList.add('active');
    }
    const searchConfig = getActiveSearchConfig();
    if (searchConfig) {
      if (samePage) {
        const marks = pages[index].querySelectorAll('mark.doc-search-mark');
        marks.forEach(m => m.classList.remove('doc-search-active-mark'));
        if (activeMatchIndex >= 0 && activeMatchIndex < marks.length) {
          marks[activeMatchIndex].classList.add('doc-search-active-mark');
        }
      } else {
        highlightPage(index, searchConfig, activeMatchIndex);
      }
    }
    buildOutline();
  }

  function goToResult(result, isPreview) {
    focusedResult = { pageIndex: result.pageIndex, pageMatchIndex: result.pageMatchIndex };
    if (isPreview) {
      switchPageSilently(result.pageIndex, result.pageMatchIndex);
    } else if (result.pageIndex === activePageIndex) {
      const marks = pages[result.pageIndex].querySelectorAll('mark.doc-search-mark');
      marks.forEach(m => m.classList.remove('doc-search-active-mark'));
      if (result.pageMatchIndex >= 0 && result.pageMatchIndex < marks.length) {
        marks[result.pageMatchIndex].classList.add('doc-search-active-mark');
      }
      buildOutline();
    } else {
      suppressPreviewCancel = false;
      window.showPage(result.pageIndex);
    }
    focusedResult = null;
    scrollToMatch(result.pageIndex, result.pageMatchIndex, isPreview);
  }

  function isSameResult(a, b) {
    return Boolean(a && b && a.pageIndex === b.pageIndex && a.pageMatchIndex === b.pageMatchIndex && a.query === b.query && a.isRegex === b.isRegex);
  }

  function clearPreviewTimer() {
    clearTimeout(previewTimer);
    previewTimer = null;
  }

  function startPreview(result) {
    if (!previewToggle.checked || previewState || getQuery() !== result.query || regexToggle.checked !== result.isRegex) return;
    clearPreviewTimer();
    previewTimer = setTimeout(() => {
      if (previewState || getQuery() !== result.query || regexToggle.checked !== result.isRegex) return;
      previewState = { pageIndex: activePageIndex, scrollTop: contentArea.scrollTop, result };
      goToResult(result, true);
      previewTimer = null;
    }, 140);
  }

  function commitPreview(result) {
    clearPreviewTimer();
    if (!isSameResult(previewState && previewState.result, result)) return false;
    previewState = null;
    activePageIndex = result.pageIndex;
    return true;
  }

  function endPreview() {
    clearPreviewTimer();
    if (!previewState) return;
    const state = previewState;
    previewState = null;
    switchPageSilently(state.pageIndex);
    contentArea.scrollTop = state.scrollTop;
    setTimeout(() => {
      contentArea.scrollTop = state.scrollTop;
    }, 0);
  }

  function renderSearchResults() {
    endPreview();
    const query = getQuery();
    resultsBox.innerHTML = '';
    restoreHighlights();
    if (!query) {
      resultsBox.classList.remove('visible');
      statusBox.textContent = '输入关键词搜索全部章节';
      buildOutline();
      return;
    }

    const searchConfig = getSearchConfig(query);
    if (searchConfig.error) {
      resultsBox.classList.add('visible');
      statusBox.textContent = searchConfig.error;
      resultsBox.innerHTML = `<div class="search-empty">${escapeHTML(searchConfig.error)}</div>`;
      buildOutline();
      return;
    }

    const rawMatches = [];
    pageData.forEach(data => {
      if (!data.searchable) return;
      const secInfo = pageSectionInfo[data.index];
      findMatches(data.text, searchConfig).forEach((match, pageMatchIndex) => {
        if (secInfo.h1Range && match.index >= secInfo.h1Range.start && match.index < secInfo.h1Range.end) return;
        let secIdx = -1, isHeading = false, secHeading = '';
        if (secInfo.sections.length) {
          for (let si = 0; si < secInfo.sections.length; si++) {
            const sec = secInfo.sections[si];
            if (match.index >= sec.headingStart && match.index < sec.sectionEnd) {
              secIdx = si;
              secHeading = sec.heading;
              isHeading = match.index < sec.headingEnd;
              break;
            }
          }
          if (secIdx === -1) return;
        }
        rawMatches.push({
          pageIndex: data.index,
          pageMatchIndex,
          sectionIndex: secIdx,
          sectionHeading: secHeading,
          isHeadingMatch: isHeading,
          query,
          isRegex: searchConfig.isRegex,
          title: data.shortTitle,
          matchIndex: match.index,
          matchText: match.text,
          text: data.text
        });
      });
    });

    const results = [];
    const seenSections = new Set();
    rawMatches.forEach(r => {
      const key = `${r.pageIndex}-${r.sectionIndex}`;
      if (!seenSections.has(key)) {
        seenSections.add(key);
        if (results.length < maxResults) results.push(r);
      }
    });

    results.sort((a, b) => {
      if (a.isHeadingMatch !== b.isHeadingMatch) return a.isHeadingMatch ? -1 : 1;
      if (a.pageIndex !== b.pageIndex) return a.pageIndex - b.pageIndex;
      return a.sectionIndex - b.sectionIndex;
    });

    const total = results.length;

    resultsBox.classList.add('visible');
    if (!total) {
      statusBox.textContent = `未找到"${query}"`;
      resultsBox.innerHTML = '<div class="search-empty">没有匹配结果</div>';
      buildOutline();
      return;
    }

    statusBox.textContent = `找到 ${total} 条结果`;
    const head = document.createElement('div');
    head.className = 'search-result-head';
    head.textContent = `搜索结果 ${total}`;
    resultsBox.appendChild(head);

    results.forEach(result => {
      const item = document.createElement('button');
      item.type = 'button';
      item.className = 'search-result-item';
      const cleanHeading = result.sectionHeading ? result.sectionHeading.replace(/^RMT（若梦兔）[-—–]?\s*/, '') : '';
      const headingLabel = cleanHeading ? ` - ${escapeHTML(cleanHeading)}` : '';
      const badge = result.isHeadingMatch ? ' <span class="search-badge">标题匹配</span>' : '';
      item.innerHTML = `<div class="search-result-title">${escapeHTML(result.title)}${headingLabel}${badge}</div><div class="search-result-snippet">${makeSnippet(result.text, result.matchIndex, result.matchText)}</div>`;
      item.addEventListener('mouseenter', () => startPreview(result));
      item.addEventListener('mouseleave', endPreview);
      item.addEventListener('focus', () => startPreview(result));
      item.addEventListener('blur', endPreview);
      item.addEventListener('click', () => {
        clearPreviewTimer();
        if (commitPreview(result)) return;
        previewState = null;
        goToResult(result, false);
      });
      resultsBox.appendChild(item);
    });

    highlightPage(activePageIndex, searchConfig);
    buildOutline();
  }

  window.showPage = function(i) {
    const index = Number(i);
    if (!Number.isInteger(index) || !pages[index]) return;
    if (previewState && !suppressPreviewCancel) previewState = null;
    activePageIndex = index;
    restoreHighlights();
    originalShowPage(index);
    const query = getQuery();
    const searchConfig = getSearchConfig(query);
    if (query && !searchConfig.error) {
      const activeMatchIndex = focusedResult && focusedResult.pageIndex === index ? focusedResult.pageMatchIndex : -1;
      highlightPage(index, searchConfig, activeMatchIndex);
    }
    buildOutline();
  };

  input.addEventListener('input', renderSearchResults);
  input.addEventListener('keydown', event => {
    if (event.key === 'Escape' && getQuery()) {
      input.value = '';
      renderSearchResults();
    }
  });
  clearBtn.addEventListener('click', () => {
    input.value = '';
    renderSearchResults();
    input.focus();
  });
  previewToggle.addEventListener('change', () => {
    if (!previewToggle.checked) endPreview();
  });
  regexToggle.addEventListener('change', renderSearchResults);

  renderSearchResults();
})();
