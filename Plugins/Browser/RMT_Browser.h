#pragma once

#ifdef BROWSER_EXPORTS
#define BROWSER_API extern "C" __declspec(dllexport)
#else
#define BROWSER_API extern "C" __declspec(dllimport)
#endif

// Return Codes:
//  0: Success
// -1: General Error (Call Browser_GetLastError)
// -2: Timeout
// -3: ElementNotFound
// -4: TargetNotFound
// -5: ConnectionFailed
// -6: InvalidParam

// --- Browser & Page Lifecycle ---
BROWSER_API int Browser_Launch(const char* browserType, const char* browserPath, int headless, const char* userDataDir, int port);
// openMode: 0 = default tab, 1 = private context, 2 = new normal window.
BROWSER_API int Browser_OpenUrl(const char* browserType, const char* browserPath, int headless, const char* userDataDir, int port, const char* url, int openMode, int timeoutMs);
BROWSER_API int Browser_Connect(const char* host, int port);
BROWSER_API int Browser_ConnectWebSocket(const char* endpoint, int port);
// Connection inspection and opening in an existing session never launch a browser.
BROWSER_API int Browser_GetConnectionPort();
BROWSER_API int Browser_OpenConnectedUrl(const char* url, int openMode, int timeoutMs);
BROWSER_API int Browser_Navigate(const char* url, int timeoutMs);
BROWSER_API int Browser_Reload(int ignoreCache);
BROWSER_API int Browser_ClearCacheAndReload();
BROWSER_API int Browser_GoBack();
BROWSER_API int Browser_GoForward();
BROWSER_API int Browser_CloseTab();
BROWSER_API int Browser_CloseBrowser();

// --- Tab Management ---
// Returns JSON array of tabs: [{"index":1,"targetId":"...","title":"...","url":"...","type":"page"}]
BROWSER_API int Browser_GetTabs(char* outResult, int maxLen);
// targetRef: can be "1" (index, 1-based), targetId, or keyword in title/url
BROWSER_API int Browser_SwitchTab(const char* targetRef);
BROWSER_API int Browser_GetActiveTabId(char* outTargetId, int maxLen);
BROWSER_API int Browser_NewTab(const char* url, char* outTargetId, int maxLen);
BROWSER_API int Browser_NewTabInContext(const char* url, const char* contextId, char* outTargetId, int maxLen);
BROWSER_API int Browser_CreateContext(char* outContextId, int maxLen);
BROWSER_API int Browser_CloseContext(const char* contextId);
BROWSER_API int Browser_CloseTabByRef(const char* targetRef);

// --- Wait Conditions ---
// selectorType: "css" or "xpath"
BROWSER_API int Browser_WaitElement(const char* selector, const char* selectorType, const char* condition, int timeoutMs);
BROWSER_API int Browser_WaitText(const char* selector, const char* selectorType, const char* expectedText, int timeoutMs);
BROWSER_API int Browser_WaitPageLoad(const char* loadState, int timeoutMs); // loadState: "load", "domcontentloaded", "networkidle"

// --- DOM & Interactions ---
BROWSER_API int Browser_Click(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_DoubleClick(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_RightClick(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_Type(const char* selector, const char* selectorType, const char* text, int clearBefore, int timeoutMs);
BROWSER_API int Browser_Clear(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_Select(const char* selector, const char* selectorType, const char* value, int timeoutMs);
BROWSER_API int Browser_Check(const char* selector, const char* selectorType, int checked, int timeoutMs);
BROWSER_API int Browser_ScrollTo(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_Hover(const char* selector, const char* selectorType, int timeoutMs);
BROWSER_API int Browser_GetElementCount(const char* selector, const char* selectorType, int* outCount);
BROWSER_API int Browser_GetElementState(const char* selector, const char* selectorType, char* outResult, int maxLen);

// --- CDP Input (Mouse & Keyboard) ---
BROWSER_API int Browser_MouseMove(double x, double y);
BROWSER_API int Browser_MouseClick(double x, double y, const char* button); // button: "left", "right", "middle"
BROWSER_API int Browser_MouseWheel(double deltaX, double deltaY);
BROWSER_API int Browser_KeyPress(const char* key, int modifiers); // modifiers: 1=Alt, 2=Ctrl, 8=Shift

// --- Data Extraction & JS ---
BROWSER_API int Browser_Evaluate(const char* script, char* outResult, int maxLen, int timeoutMs);
BROWSER_API int Browser_GetText(const char* selector, const char* selectorType, char* outResult, int maxLen, int timeoutMs);
BROWSER_API int Browser_GetAttribute(const char* selector, const char* selectorType, const char* attrName, char* outResult, int maxLen, int timeoutMs);
BROWSER_API int Browser_GetHtml(const char* selector, const char* selectorType, int outerHtml, char* outResult, int maxLen, int timeoutMs);
BROWSER_API int Browser_GetUrl(char* outResult, int maxLen);
BROWSER_API int Browser_GetTitle(char* outResult, int maxLen);
BROWSER_API int Browser_CaptureScreenshot(const char* filePath, int fullPage);

// --- Storage & Cookies ---
BROWSER_API int Browser_GetCookie(const char* name, char* outResult, int maxLen);
BROWSER_API int Browser_SetCookie(const char* name, const char* value, const char* domain, const char* path);
BROWSER_API int Browser_ClearCookies();
BROWSER_API int Browser_GetStorage(const char* storageType, const char* key, char* outResult, int maxLen); // "local" / "session"
BROWSER_API int Browser_SetStorage(const char* storageType, const char* key, const char* value);

// --- Error & Diagnostics ---
BROWSER_API int Browser_GetLastError(char* outResult, int maxLen);
BROWSER_API int Browser_GetLastErrorCode();
