# WebViewToo
Allows for use of the WebView2 Framework within AHK to create Web Controls and Web-based GUIs

## NOTE: THIS UPDATE IS NOT BACKWARDS COMPATIBLE.
- If you have current scripts using this library, you will need to update your scripts.

### Major Changes
- The class has been split into three parts.
  - The `WebViewCtrl` class can be used to add a new WebView2 Control to a standard AHK GUI.
  - The `WebViewGui` class can be used to create fully functional Web-based windows.
    - This class replaces the `WebViewToo` class. This name change was made to make a more clear distinction between a `WebViewCtrl` and `WebViewGui`.
  - The `WebViewSizer` class should not be explicitly used, this is used by the `WebViewGui` class.
    - This class replaces the `Border` class that was added in the last update. 
- Navigation routing has been overhauled to provider a smoother end-user process.
	
### Minor Changes
- The `Close()` method has been removed, you should now use the `Hide()` method or `WinClose()` function directly.
- The `EnableGlobal()` method is now automatically intialized for your default host (`.localhost` by default).
  - To enable it for other hosts you can now use the `AllowGlobalAccessFor()` method.
- The `Load()` method has been removed, you should now use `Navigate()`
- Several GUI related methods and properties for `WebViewGui` have been removed as the class now properly extends native GUIs.
  - These include `Minimize()`, `Maximize()`, `Opt()`, `BackColor`, `Name`, etc.
  - NOTE: These still work, they just no longer needed to be defined.
### Bug Fixes
- Fixed window displaying as a small grey box during creation on single-monitor setups.