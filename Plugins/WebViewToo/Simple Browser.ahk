;Environment Controls
;///////////////////////////////////////////////////////////////////////////////////////////
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Lib\WebViewToo.ahk
Gui.ProtoType.AddWebViewCtrl := WebViewCtrl
;///////////////////////////////////////////////////////////////////////////////////////////

;Main Script
;///////////////////////////////////////////////////////////////////////////////////////////
;Create Dll if script is compiled
if (A_IsCompiled) {
	WebViewCtrl.CreateFileFromResource(DllPath := ((A_PtrSize * 8) "bit\WebView2Loader.dll"), WebViewCtrl.TempDir)
}

;Define our custom settings
WebViewSettings := {
    DataDir: WebViewCtrl.TempDir,
    DllPath: A_IsCompiled ? WebViewCtrl.TempDir "\" (A_PtrSize * 8) "bit\WebView2Loader.dll" : "WebView2Loader.dll"
}

MyGui := Gui()
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.AddText("xm ym+3", "Url:")
MyGui.AddEdit("x+5 yp-3 w745 vUrlEdit", "")
MyGui.AddButton("x+5 vNavigateButton", "Go").OnEvent("Click", NavToUrl)
MyGui.AddWebViewCtrl("xm w800 h600 vWVToo", WebViewSettings)
MyGui.Show()

NavToUrl(GuiCtrlObj, *) {
    CurrGui := GuiCtrlObj.Gui
    CurrGui["WVToo"].Navigate(CurrGui["UrlEdit"].Value)
    CurrGui["UrlEdit"].Value := ""
}
;///////////////////////////////////////////////////////////////////////////////////////////

;Hotkeys
;///////////////////////////////////////////////////////////////////////////////////////////
#HotIf WinActive(MyGui.Hwnd) && (MyGui.FocusedCtrl = MyGui["UrlEdit"])
Enter::NavToUrl(MyGui["UrlEdit"])
#HotIf
;///////////////////////////////////////////////////////////////////////////////////////////

;Resources for Compiled Scripts
;///////////////////////////////////////////////////////////////////////////////////////////
;@Ahk2Exe-AddResource Lib\32bit\WebView2Loader.dll, 32bit\WebView2Loader.dll
;@Ahk2Exe-AddResource Lib\64bit\WebView2Loader.dll, 64bit\WebView2Loader.dll
;///////////////////////////////////////////////////////////////////////////////////////////
