#include "RMT_Browser.h"

#include <cdp/CDP.hpp>
#include <string>
#include <memory>
#include <mutex>
#include <cstring>
#include <algorithm>
#include <chrono>
#include <thread>
#include <vector>
#include <sstream>

static std::mutex g_browserMutex;
static std::unique_ptr<cdp::quick::QuickBrowser> g_browser = nullptr;
static cdp::quick::QuickPage* g_activePage = nullptr;
static std::string g_lastError = "";
static int g_lastErrorCode = 0;
static std::string g_host = "127.0.0.1";
static int g_port = 9222;

static void SetLastError(const std::string& err, int code = -1) {
    g_lastError = err;
    g_lastErrorCode = code;
}

static void CopyToOut(const std::string& str, char* outResult, int maxLen) {
    if (!outResult || maxLen <= 0) return;
    size_t copyLen = (str.length() < (size_t)(maxLen - 1)) ? str.length() : (size_t)(maxLen - 1);
    memcpy(outResult, str.data(), copyLen);
    outResult[copyLen] = '\0';
}

BROWSER_API int Browser_GetLastError(char* outResult, int maxLen) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    CopyToOut(g_lastError, outResult, maxLen);
    return 0;
}

BROWSER_API int Browser_GetLastErrorCode() {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    return g_lastErrorCode;
}

// Convert selector & selectorType into a JavaScript expression that evaluates to an Element or null
static std::string BuildElementQueryJs(const std::string& selector, const std::string& selectorType) {
    std::string sType = selectorType;
    std::transform(sType.begin(), sType.end(), sType.begin(), ::tolower);

    // Escape backslashes and single quotes
    std::string escapedSel = "";
    for (char c : selector) {
        if (c == '\\') escapedSel += "\\\\";
        else if (c == '\'') escapedSel += "\\'";
        else escapedSel += c;
    }

    if (sType == "xpath") {
        return "document.evaluate('" + escapedSel + "', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue";
    } else {
        // default CSS selector
        return "document.querySelector('" + escapedSel + "')";
    }
}

static bool AttachToFirstPage() {
    if (!g_browser) return false;
    auto pages = g_browser->pages();
    if (!pages.empty()) {
        g_activePage = pages[0];
        return true;
    }
    auto newP = g_browser->newPage("about:blank");
    if (newP.ok()) {
        g_activePage = newP.page;
        return true;
    }
    SetLastError("Failed to create/get active page", -4);
    return false;
}

static bool EnsureActivePage() {
    if (g_activePage && !g_activePage->isClosed()) return true;
    if (!g_browser) {
        auto res = cdp::quick::connect(g_host, g_port);
        if (res.ok()) {
            g_browser = std::move(res.browser);
        } else {
            auto lres = cdp::quick::launch();
            if (lres.ok()) {
                g_browser = std::move(lres.browser);
            } else {
                SetLastError("Could not connect or launch browser: " + lres.error, -5);
                return false;
            }
        }
    }
    return AttachToFirstPage();
}

BROWSER_API int Browser_Connect(const char* host, int port) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        g_host = (host && host[0] != '\0') ? host : "127.0.0.1";
        g_port = (port > 0) ? port : 9222;

        auto res = cdp::quick::connect(g_host, g_port);
        if (!res.ok()) {
            SetLastError("Connect failed: " + res.error, -5);
            return -5;
        }

        g_browser = std::move(res.browser);
        if (!AttachToFirstPage()) {
            return -4;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Launch(const char* browserType, const char* browserPath, int headless, const char* userDataDir, int port) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (g_browser) {
            g_activePage = nullptr;
            g_browser = nullptr;
        }

        g_port = (port > 0) ? port : 9222;
        cdp::ChromeLaunchOptions opts;
        opts.headless = (headless != 0);
        opts.debuggingPort = g_port;
        opts.host = "127.0.0.1";

        std::string bType = browserType ? browserType : "";
        std::transform(bType.begin(), bType.end(), bType.begin(), ::tolower);

        if (bType.find("edge") != std::string::npos || bType.find("msedge") != std::string::npos) {
            opts.preferredChannel = cdp::ChromeChannel::Edge;
        } else if (bType.find("chromium") != std::string::npos) {
            opts.preferredChannel = cdp::ChromeChannel::Chromium;
        } else if (bType.find("canary") != std::string::npos) {
            opts.preferredChannel = cdp::ChromeChannel::Canary;
        } else if (bType.find("beta") != std::string::npos) {
            opts.preferredChannel = cdp::ChromeChannel::Beta;
        } else if (browserPath && browserPath[0] != '\0') {
            opts.preferredChannel = cdp::ChromeChannel::Custom;
            opts.customChromePath = browserPath;
        } else {
            opts.preferredChannel = cdp::ChromeChannel::Stable;
        }

        if (browserPath && browserPath[0] != '\0') {
            opts.customChromePath = browserPath;
        }
        if (userDataDir && userDataDir[0] != '\0') {
            opts.userDataDir = userDataDir;
            opts.useTempProfile = false;
        }

        auto res = cdp::quick::launch(opts);
        if (!res.ok()) {
            SetLastError("Launch browser failed: " + res.error, -5);
            return -5;
        }

        g_browser = std::move(res.browser);
        if (!AttachToFirstPage()) {
            return -4;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Navigate(const char* url, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!url || url[0] == '\0') {
            SetLastError("URL cannot be empty", -6);
            return -6;
        }

        int to = (timeoutMs > 0) ? timeoutMs : 30000;
        if (!g_activePage->navigate(url, to)) {
            SetLastError(g_activePage->lastError().empty() ? "Navigation failed" : g_activePage->lastError(), -2);
            return -2;
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Reload(int ignoreCache) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!g_activePage->reload(ignoreCache != 0)) {
            SetLastError(g_activePage->lastError().empty() ? "Reload failed" : g_activePage->lastError(), -1);
            return -1;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GoBack() {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!g_activePage->back()) {
            SetLastError(g_activePage->lastError().empty() ? "GoBack failed" : g_activePage->lastError(), -1);
            return -1;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GoForward() {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!g_activePage->forward()) {
            SetLastError(g_activePage->lastError().empty() ? "GoForward failed" : g_activePage->lastError(), -1);
            return -1;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_CloseTab() {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (g_activePage) {
            g_activePage->close();
            g_activePage = nullptr;
        }
        if (g_browser) {
            auto pages = g_browser->pages();
            if (!pages.empty()) {
                g_activePage = pages[0];
            }
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_CloseBrowser() {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        g_activePage = nullptr;
        if (g_browser) {
            g_browser = nullptr;
        }
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

// --- Tab Management ---

BROWSER_API int Browser_GetTabs(char* outResult, int maxLen) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!g_browser) {
            if (!EnsureActivePage()) return -1;
        }

        auto targets = g_browser->listPages();
        std::ostringstream ss;
        ss << "[";
        for (size_t i = 0; i < targets.size(); ++i) {
            const auto& t = targets[i];
            if (i > 0) ss << ",";
            ss << "{";
            ss << "\"index\":" << (i + 1) << ",";
            ss << "\"targetId\":\"" << t.id << "\",";
            ss << "\"title\":\"";
            for (char c : t.title) {
                if (c == '"' || c == '\\') ss << '\\';
                ss << c;
            }
            ss << "\",";
            ss << "\"url\":\"";
            for (char c : t.url) {
                if (c == '"' || c == '\\') ss << '\\';
                ss << c;
            }
            ss << "\",";
            ss << "\"type\":\"" << t.type << "\"";
            ss << "}";
        }
        ss << "]";

        CopyToOut(ss.str(), outResult, maxLen);
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_SwitchTab(const char* targetRef) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!g_browser) {
            if (!EnsureActivePage()) return -1;
        }
        if (!targetRef || targetRef[0] == '\0') {
            SetLastError("Target reference cannot be empty", -6);
            return -6;
        }

        std::string ref = targetRef;
        auto targets = g_browser->listPages();
        if (targets.empty()) {
            SetLastError("No pages found", -4);
            return -4;
        }

        // 1. Check if ref is a 1-based index (digits)
        bool isNumber = true;
        for (char c : ref) {
            if (!isdigit(static_cast<unsigned char>(c))) {
                isNumber = false;
                break;
            }
        }

        if (isNumber) {
            int idx = std::stoi(ref) - 1; // 1-based to 0-based
            if (idx >= 0 && idx < (int)targets.size()) {
                auto pres = g_browser->connectToPage(targets[idx]);
                if (pres.ok()) {
                    g_activePage = pres.page;
                    g_activePage->bringToFront();
                    SetLastError("", 0);
                    return 0;
                }
            }
        }

        // 2. Match exact targetId
        for (const auto& t : targets) {
            if (t.id == ref) {
                auto pres = g_browser->connectToPage(t);
                if (pres.ok()) {
                    g_activePage = pres.page;
                    g_activePage->bringToFront();
                    SetLastError("", 0);
                    return 0;
                }
            }
        }

        // 3. Match substring in title or url
        std::string refLower = ref;
        std::transform(refLower.begin(), refLower.end(), refLower.begin(), ::tolower);
        for (const auto& t : targets) {
            std::string titleLower = t.title;
            std::string urlLower = t.url;
            std::transform(titleLower.begin(), titleLower.end(), titleLower.begin(), ::tolower);
            std::transform(urlLower.begin(), urlLower.end(), urlLower.begin(), ::tolower);

            if (titleLower.find(refLower) != std::string::npos || urlLower.find(refLower) != std::string::npos) {
                auto pres = g_browser->connectToPage(t);
                if (pres.ok()) {
                    g_activePage = pres.page;
                    g_activePage->bringToFront();
                    SetLastError("", 0);
                    return 0;
                }
            }
        }

        SetLastError("Target tab not found: " + ref, -4);
        return -4;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_NewTab(const char* url, char* outTargetId, int maxLen) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!g_browser) {
            if (!EnsureActivePage()) return -1;
        }

        std::string targetUrl = (url && url[0] != '\0') ? url : "about:blank";
        auto pres = g_browser->newPage(targetUrl);
        if (!pres.ok()) {
            SetLastError("Failed to create new tab: " + pres.error, -1);
            return -1;
        }

        g_activePage = pres.page;
        g_activePage->bringToFront();
        CopyToOut(g_activePage->targetId(), outTargetId, maxLen);
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_CloseTabByRef(const char* targetRef) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!g_browser) {
            if (!EnsureActivePage()) return -1;
        }
        if (!targetRef || targetRef[0] == '\0') {
            return Browser_CloseTab();
        }

        std::string ref = targetRef;
        auto targets = g_browser->listPages();

        int targetIdx = -1;
        bool isNumber = true;
        for (char c : ref) {
            if (!isdigit(static_cast<unsigned char>(c))) {
                isNumber = false;
                break;
            }
        }

        if (isNumber) {
            int idx = std::stoi(ref) - 1;
            if (idx >= 0 && idx < (int)targets.size()) targetIdx = idx;
        }

        if (targetIdx == -1) {
            for (size_t i = 0; i < targets.size(); ++i) {
                if (targets[i].id == ref) {
                    targetIdx = (int)i;
                    break;
                }
            }
        }

        if (targetIdx >= 0) {
            auto pres = g_browser->connectToPage(targets[targetIdx]);
            if (pres.ok()) {
                pres.page->close();
                if (g_activePage == pres.page) {
                    g_activePage = nullptr;
                    auto remaining = g_browser->pages();
                    if (!remaining.empty()) g_activePage = remaining[0];
                }
                SetLastError("", 0);
                return 0;
            }
        }

        SetLastError("Tab not found: " + ref, -4);
        return -4;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

// --- Wait Conditions ---

BROWSER_API int Browser_WaitElement(const char* selector, const char* selectorType, const char* condition, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string cond = condition ? condition : "appear";
        std::transform(cond.begin(), cond.end(), cond.begin(), ::tolower);
        std::string sType = selectorType ? selectorType : "css";

        int totalTimeout = (timeoutMs > 0) ? timeoutMs : 10000;
        int intervalMs = 100;
        auto start = std::chrono::steady_clock::now();

        std::string queryElem = BuildElementQueryJs(selector, sType);

        while (true) {
            std::string checkJs = "";
            if (cond == "appear") {
                checkJs = "(() => { return (" + queryElem + ") !== null; })()";
            } else if (cond == "disappear") {
                checkJs = "(() => { const el = " + queryElem + "; return el === null || el.offsetParent === null; })()";
            } else if (cond == "visible") {
                checkJs = "(() => { const el = " + queryElem + "; return el !== null && (el.offsetWidth > 0 || el.offsetHeight > 0 || el.getClientRects().length > 0); })()";
            } else {
                checkJs = "(() => { return (" + queryElem + ") !== null; })()";
            }

            std::string res = g_activePage->evalString(checkJs);
            if (res == "true") {
                SetLastError("", 0);
                return 0;
            }

            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
            if (elapsed >= totalTimeout) {
                SetLastError("Timeout waiting for element condition: " + cond, -2);
                return -2;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(intervalMs));
        }
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_WaitText(const char* selector, const char* selectorType, const char* expectedText, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!expectedText) {
            SetLastError("Expected text cannot be null", -6);
            return -6;
        }

        std::string expTxt = expectedText;
        std::string escapedText = "";
        for (char c : expTxt) {
            if (c == '\\') escapedText += "\\\\";
            else if (c == '\'') escapedText += "\\'";
            else escapedText += c;
        }

        std::string sel = selector ? selector : "";
        std::string sType = selectorType ? selectorType : "css";
        int totalTimeout = (timeoutMs > 0) ? timeoutMs : 10000;
        int intervalMs = 100;
        auto start = std::chrono::steady_clock::now();

        std::string checkJs;
        if (sel.empty()) {
            checkJs = "(() => { return document.body ? document.body.innerText.includes('" + escapedText + "') : false; })()";
        } else {
            std::string queryElem = BuildElementQueryJs(sel, sType);
            checkJs = "(() => { const el = " + queryElem + "; return el ? (el.innerText || el.textContent || '').includes('" + escapedText + "') : false; })()";
        }

        while (true) {
            std::string res = g_activePage->evalString(checkJs);
            if (res == "true") {
                SetLastError("", 0);
                return 0;
            }

            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
            if (elapsed >= totalTimeout) {
                SetLastError("Timeout waiting for text: " + expTxt, -2);
                return -2;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(intervalMs));
        }
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_WaitPageLoad(const char* loadState, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        int totalTimeout = (timeoutMs > 0) ? timeoutMs : 30000;

        std::string state = loadState ? loadState : "load";
        std::transform(state.begin(), state.end(), state.begin(), ::tolower);

        if (state == "networkidle") {
            if (g_activePage->waitNetworkIdle(500, totalTimeout)) {
                SetLastError("", 0);
                return 0;
            } else {
                SetLastError("Timeout waiting for network idle", -2);
                return -2;
            }
        }

        auto start = std::chrono::steady_clock::now();
        while (true) {
            std::string readyState = g_activePage->evalString("document.readyState");
            if (state == "domcontentloaded") {
                if (readyState == "interactive" || readyState == "complete") {
                    SetLastError("", 0);
                    return 0;
                }
            } else { // default "load" -> "complete"
                if (readyState == "complete") {
                    SetLastError("", 0);
                    return 0;
                }
            }

            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
            if (elapsed >= totalTimeout) {
                SetLastError("Timeout waiting for page readyState: " + state, -2);
                return -2;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

// --- DOM & Interactions ---

BROWSER_API int Browser_Click(const char* selector, const char* selectorType, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        // If pure CSS, use built-in click
        if (sType == "css" || sType == "") {
            if (!g_activePage->click(selector, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Click failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            // XPath or customized dispatch
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string jsClick = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.scrollIntoView({block:'center'}); el.click(); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsClick);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for click: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Type(const char* selector, const char* selectorType, const char* text, int clearBefore, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;
        std::string txt = text ? text : "";

        if (sType == "css" || sType == "") {
            if (clearBefore) {
                g_activePage->clear(selector, waitMs);
            }
            if (!g_activePage->type(selector, txt, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Type failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            // XPath
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string escapedTxt = "";
            for (char c : txt) {
                if (c == '\\') escapedTxt += "\\\\";
                else if (c == '\'') escapedTxt += "\\'";
                else escapedTxt += c;
            }

            std::string jsType = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.focus(); "
                + (clearBefore ? "el.value = ''; " : "")
                + "el.value = (el.value || '') + '" + escapedTxt + "'; el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsType);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for type: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Clear(const char* selector, const char* selectorType, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        if (sType == "css" || sType == "") {
            if (!g_activePage->clear(selector, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Clear failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string jsClear = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.focus(); el.value = ''; el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsClear);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for clear: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Select(const char* selector, const char* selectorType, const char* value, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string val = value ? value : "";
        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        if (sType == "css" || sType == "") {
            if (!g_activePage->select(selector, val, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Select failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string escapedVal = "";
            for (char c : val) {
                if (c == '\\') escapedVal += "\\\\";
                else if (c == '\'') escapedVal += "\\'";
                else escapedVal += c;
            }
            std::string jsSelect = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.value = '" + escapedVal + "'; el.dispatchEvent(new Event('change', {bubbles:true})); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsSelect);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for select: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Check(const char* selector, const char* selectorType, int checked, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        if (sType == "css" || sType == "") {
            if (!g_activePage->check(selector, checked != 0, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Check failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string jsCheck = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.checked = " + (checked ? "true" : "false") + "; el.dispatchEvent(new Event('change', {bubbles:true})); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsCheck);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for check: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_ScrollTo(const char* selector, const char* selectorType, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        if (sType == "css" || sType == "") {
            if (!g_activePage->scrollTo(selector, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "ScrollTo failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string jsScroll = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.scrollIntoView({behavior:'smooth', block:'center'}); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsScroll);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for scroll: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_Hover(const char* selector, const char* selectorType, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        int waitMs = (timeoutMs > 0) ? timeoutMs : 5000;

        if (sType == "css" || sType == "") {
            if (!g_activePage->hover(selector, waitMs)) {
                SetLastError(g_activePage->lastError().empty() ? "Hover failed" : g_activePage->lastError(), -3);
                return -3;
            }
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string jsHover = "(() => { const el = " + queryElem + "; if(!el) return 'NOT_FOUND'; el.dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); return 'OK'; })()";
            std::string res = g_activePage->evalString(jsHover);
            if (res == "NOT_FOUND") {
                SetLastError("Element not found for hover: " + std::string(selector), -3);
                return -3;
            }
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetElementCount(const char* selector, const char* selectorType, int* outCount) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!outCount) return -6;
        *outCount = 0;

        if (!selector || selector[0] == '\0') {
            SetLastError("Selector cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        if (sType == "css" || sType == "") {
            *outCount = g_activePage->count(selector);
        } else {
            std::string escapedSel = "";
            for (char c : std::string(selector)) {
                if (c == '\\') escapedSel += "\\\\";
                else if (c == '\'') escapedSel += "\\'";
                else escapedSel += c;
            }
            std::string jsCount = "(() => { const res = document.evaluate('" + escapedSel + "', document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null); return res.snapshotLength; })()";
            std::string cntStr = g_activePage->evalString(jsCount);
            *outCount = (!cntStr.empty()) ? std::atoi(cntStr.c_str()) : 0;
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

// --- Data Extraction & JS ---

BROWSER_API int Browser_Evaluate(const char* script, char* outResult, int maxLen, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!script || script[0] == '\0') {
            SetLastError("Script cannot be empty", -6);
            return -6;
        }

        std::string resStr = g_activePage->evalString(script);
        CopyToOut(resStr, outResult, maxLen);
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetText(const char* selector, const char* selectorType, char* outResult, int maxLen, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        std::string sel = selector ? selector : "";
        std::string sType = selectorType ? selectorType : "css";

        if (sel.empty()) {
            std::string txt = g_activePage->text();
            CopyToOut(txt, outResult, maxLen);
        } else if (sType == "css" || sType == "") {
            std::string txt = g_activePage->text(sel);
            CopyToOut(txt, outResult, maxLen);
        } else {
            std::string queryElem = BuildElementQueryJs(sel, sType);
            std::string jsGet = "(() => { const el = " + queryElem + "; return el ? (el.innerText || el.textContent || '') : ''; })()";
            std::string txt = g_activePage->evalString(jsGet);
            CopyToOut(txt, outResult, maxLen);
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetAttribute(const char* selector, const char* selectorType, const char* attrName, char* outResult, int maxLen, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!selector || selector[0] == '\0' || !attrName || attrName[0] == '\0') {
            SetLastError("Selector and Attribute Name cannot be empty", -6);
            return -6;
        }

        std::string sType = selectorType ? selectorType : "css";
        if (sType == "css" || sType == "") {
            std::string val = g_activePage->attribute(selector, attrName);
            CopyToOut(val, outResult, maxLen);
        } else {
            std::string queryElem = BuildElementQueryJs(selector, sType);
            std::string escapedAttr = "";
            for (char c : std::string(attrName)) {
                if (c == '\\') escapedAttr += "\\\\";
                else if (c == '\'') escapedAttr += "\\'";
                else escapedAttr += c;
            }
            std::string jsAttr = "(() => { const el = " + queryElem + "; return el ? (el.getAttribute('" + escapedAttr + "') || '') : ''; })()";
            std::string val = g_activePage->evalString(jsAttr);
            CopyToOut(val, outResult, maxLen);
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetHtml(const char* selector, const char* selectorType, int outerHtml, char* outResult, int maxLen, int timeoutMs) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        std::string sel = selector ? selector : "";
        std::string sType = selectorType ? selectorType : "css";

        if (sel.empty()) {
            std::string h = g_activePage->html();
            CopyToOut(h, outResult, maxLen);
        } else {
            std::string queryElem = BuildElementQueryJs(sel, sType);
            std::string prop = outerHtml ? "outerHTML" : "innerHTML";
            std::string jsHtml = "(() => { const el = " + queryElem + "; return el ? (el." + prop + " || '') : ''; })()";
            std::string h = g_activePage->evalString(jsHtml);
            CopyToOut(h, outResult, maxLen);
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetUrl(char* outResult, int maxLen) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        std::string u = g_activePage->url();
        CopyToOut(u, outResult, maxLen);
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_GetTitle(char* outResult, int maxLen) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        std::string t = g_activePage->title();
        CopyToOut(t, outResult, maxLen);
        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}

BROWSER_API int Browser_CaptureScreenshot(const char* filePath, int fullPage) {
    std::lock_guard<std::mutex> lock(g_browserMutex);
    try {
        if (!EnsureActivePage()) return -1;
        if (!filePath || filePath[0] == '\0') {
            SetLastError("File path cannot be empty", -6);
            return -6;
        }

        bool ok = false;
        if (fullPage) {
            ok = g_activePage->screenshotFullPage(filePath);
        } else {
            ok = g_activePage->screenshot(filePath);
        }

        if (!ok) {
            SetLastError("Screenshot capture failed: " + g_activePage->lastError(), -1);
            return -1;
        }

        SetLastError("", 0);
        return 0;
    } catch (const std::exception& e) {
        SetLastError(e.what(), -1);
        return -1;
    }
}
