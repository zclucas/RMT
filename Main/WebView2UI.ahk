; WebView2 UI 管理类
; 用于替代 UIUtil.ahk 的纯 AHK GUI
class WebView2UI {
    static wv := ""
    static wvc := ""
    static gui := ""
    static messageCallback := ""
    static isInit := false

    ; 初始化 WebView2 并加载主界面
    static Init() {
        if (this.isInit)
            return

        ; 创建主窗口
        this.gui := Gui()
        this.gui.Title := "RMTv2.0"
        this.gui.SetFont("S10 W550 Q2", "微软雅黑")

        ; 读取背景色配置
        BGColor := MySoftData.SoftBGColor
        if (RegExMatch(BGColor, "^([0-9A-Fa-f]{6})$"))
            this.gui.BackColor := BGColor
        else
            this.gui.BackColor := "f0f0f0"

        MySoftData.MyGui := this.gui

        ; 显示窗口
        this.gui.Show("w1150 h650")

        ; 创建 WebView2
        try {
            this.wvc := WebView2.CreateControllerAsync(this.gui.Hwnd).await()
            this.wv := this.wvc.CoreWebView2

            ; 加载本地 HTML
            htmlPath := A_WorkingDir "\LocalWeb\main.html"
            if (FileExist(htmlPath)) {
                this.wv.Navigate(htmlPath)
            } else {
                MsgBox("找不到 HTML 文件: " htmlPath)
            }

            ; 暴露 AHK 对象给 JS
            this.wv.AddHostObjectToScript("ahk", this.GetExposedObj())

            ; 注册消息接收
            this.wv.add_WebMessageReceived(this.CreateWebMessageHandler())

            this.isInit := true
            ; 日志可用 OutputDebug
        } catch as e {
            MsgBox("WebView2 初始化失败: " e.Message)
        }
    }

    ; 创建 Web 消息处理器
    static CreateWebMessageHandler() {
        ; 使用普通函数处理 Web 消息
        handler := WebView2.Handler.Call(WebMessageHandlerInvoke, 2)
        ; 将当前实例绑定到处理器
        WebMessageHandlerInvoke.this := this
        return handler
    }

    ; 处理来自 JS 的消息
    static HandleMessage(msg) {
        try {
            action := ""
            tabIndex := 1

            try {
                data := JSON.parse(msg)
                action := data.Has("action") ? data.action : ""
                tabIndex := data.Has("index") ? data.index : 1
            } catch {
                ; 简单处理
            }

            switch action {
                case "init":
                    this.SendInitialData()
                case "suspend":
                    OnSuspendHotkey()
                case "pause":
                    OnPauseHotKey()
                case "killAll":
                    OnKillAllMacro()
                case "save":
                    OnSaveSetting()
                case "reload":
                    MenuReload()
                case "showSettingMgr":
                    MySettingMgrGui.ShowGui()
                case "showHelp":
                    Run(A_WorkingDir "\index.html")
                case "tabChange":
                    this.OnTabChanged(tabIndex)
                ; 忽略未知动作
            }
        ; 忽略解析错误
        }
    }

    ; 发送初始数据到 JS
    static SendInitialData() {
        data := {
            configName: MySoftData.CurSettingName,
            isSuspend: MySoftData.IsSuspend,
            suspendHotkey: MySoftData.SuspendHotkey,
            isPause: MySoftData.IsPause,
            pauseHotkey: MySoftData.PauseHotkey,
            killHotkey: MySoftData.KillMacroHotkey,
            tabIndex: MySoftData.TableIndex,
            tabNames: MySoftData.TabNameArr,
            fontType: MySoftData.FontType,
            bgColor: MySoftData.SoftBGColor
        }
        this.PostMessage("initData", data)
    }

    ; Tab 切换处理
    static OnTabChanged(tabIndex) {
        MySoftData.TableIndex := tabIndex
        MySoftData.TabCtrl.Value := tabIndex
        RefreshGui()
    }

    ; 向 JS 发送消息
    static PostMessage(action, data := "") {
        if (!this.wv)
            return

        msg := {action: action, data: data}
        json := JSON.stringify(msg)
        this.wv.PostWebMessageAsJson(json)
    }

    ; 保存设置（供JS调用）
    static SaveSettingWrapper() {
        OnSaveSetting()
    }

    ; 获取暴露给 JS 的对象
    static GetExposedObj() {
        return {
            GetInitialData: WebView2UI.GetInitialDataForJS.Bind(WebView2UI),
            FormatHotkey: FormatHotkeyForJS,
            SuspendToggle: OnSuspendHotkey,
            PauseToggle: OnPauseHotKey,
            KillAllMacro: OnKillAllMacro,
            SaveSetting: WebView2UI.SaveSettingWrapper.Bind(WebView2UI),
            Reload: MenuReload,
            ShowSettingMgr: MySettingMgrGui.ShowGui.Bind(MySettingMgrGui),
            ShowHelp: ShowHelpOpen,
            TabChange: WebView2UI.OnTabChanged.Bind(WebView2UI),
            GetMacroData: WebView2UI.GetMacroData.Bind(WebView2UI),
            GetToolUIData: WebView2UI.GetToolUIData.Bind(WebView2UI)
        }
    }

    ; 格式化热键显示（AHK 符号转中文）
    static FormatHotkeyForJS(keyCombo) {
        if (!keyCombo)
            return ""
        result := keyCombo
        result := RegExReplace(result, "i)^!", "Alt+")
        result := RegExReplace(result, "i)^\+", "Shift+")
        result := RegExReplace(result, "i)^#", "Win+")
        result := RegExReplace(result, "i)^\^", "Ctrl+")
        result := RegExReplace(result, "i)<!", "Alt+")
        result := RegExReplace(result, "i)<\+", "Shift+")
        result := RegExReplace(result, "i)<#", "Win+")
        result := RegExReplace(result, "i)<\^", "Ctrl+")
        return result
    }

    ; 获取初始数据（返回 JS 对象）
    static GetInitialDataForJS() {
        return {
            configName: MySoftData.CurSettingName,
            isSuspend: MySoftData.IsSuspend,
            suspendHotkey: MySoftData.SuspendHotkey,
            isPause: MySoftData.IsPause,
            pauseHotkey: MySoftData.PauseHotkey,
            killHotkey: MySoftData.KillMacroHotkey,
            tabIndex: MySoftData.TableIndex,
            tabNames: MySoftData.TabNameArr,
            fontType: MySoftData.FontType,
            bgColor: MySoftData.SoftBGColor
        }
    }

    ; 获取 Tab 数据
    static GetTabDataForJS() {
        ; 获取当前Tab的数据
        tabIndex := MySoftData.TableIndex
        return this.GetKeyMacroTabData(tabIndex)
    }

    ; 获取通用宏Tab数据
    static GetMacroData(tabIndex) {
        ; 只有前6个Tab有类似的数据结构
        if (tabIndex < 1 || tabIndex > 6) {
            return JSON.stringify({tabIndex: tabIndex, folds: [], macros: []})
        }
        ; 调用GetKeyMacroTabData，它对所有Tab都适用
        return this.GetKeyMacroTabData(tabIndex)
    }

    ; 获取工具Tab数据
    static GetToolUIData() {
        global ToolCheckInfo
        try {
            data := {
                toolCheckHotkey: ToolCheckInfo.ToolCheckHotkey || "",
                isToolCheck: ToolCheckInfo.IsToolCheck || false,
                posStr: ToolCheckInfo.PosStr || "",
                winPosStr: ToolCheckInfo.WinPosStr || "",
                processTitle: ToolCheckInfo.ProcessTile || "",
                processName: ToolCheckInfo.ProcessName || "",
                processClass: ToolCheckInfo.ProcessClass || "",
                processPid: ToolCheckInfo.ProcessPid || "",
                processId: ToolCheckInfo.ProcessId || "",
                color: ToolCheckInfo.Color || "",
                recordHotkey: ToolCheckInfo.ToolRecordMacroHotKey || "",
                isRecording: ToolCheckInfo.IsToolRecord || false,
                textFilterHotkey: ToolCheckInfo.ToolTextFilterHotKey || "",
                ocrType: ToolCheckInfo.OCRTypeValue || 1
            }
            return JSON.stringify(data)
        } catch {
            return JSON.stringify({})
        }
    }

    ; 获取按键宏Tab数据
    static GetKeyMacroTabData(tabIndex := 1) {
        try {
            tableItem := MySoftData.TableInfo[tabIndex]
            FoldInfo := tableItem.FoldInfo

            ; 构建基础数据
            result := {
                tabIndex: tabIndex,
                tabName: MySoftData.TabNameArr[tabIndex],
                folds: [],
                macros: []
            }

            ; 检查FoldInfo是否存在
            if (!FoldInfo || !IsObject(FoldInfo)) {
                ; 返回JSON字符串
                return JSON.stringify(result)
            }

            ; 遍历所有折叠模块
            loop FoldInfo.IndexSpanArr.Length {
                foldIndex := A_Index

                ; 构建fold数据 - 使用原始值
                remark := ""
                frontInfo := ""
                try {
                    remark := FoldInfo.RemarkArr[foldIndex]
                }
                try {
                    frontInfo := FoldInfo.FrontInfoArr[foldIndex]
                }
                foldData := {
                    remark: remark,
                    frontInfo: frontInfo,
                    forbid: FoldInfo.ForbidStateArr[foldIndex],
                    foldState: FoldInfo.FoldStateArr[foldIndex],
                    indexSpan: FoldInfo.IndexSpanArr[foldIndex],
                    tkType: FoldInfo.TKTypeArr[foldIndex],
                    tk: FoldInfo.TKArr[foldIndex],
                    holdTime: FoldInfo.HoldTimeArr[foldIndex]
                }
                result.folds.Push(foldData)

                ; 获取该模块下的宏列表
                IndexSpanStr := FoldInfo.IndexSpanArr[foldIndex]
                hasValidIndex := IndexSpanStr && InStr(IndexSpanStr, "-")
                if (hasValidIndex) {
                    IndexSpan := StrSplit(IndexSpanStr, "-")
                    if (IsInteger(IndexSpan[1]) && IsInteger(IndexSpan[2])) {
                        startIdx := Integer(IndexSpan[1])
                        endIdx := Integer(IndexSpan[2])

                        loop endIdx - startIdx + 1 {
                            itemIndex := startIdx + A_Index - 1
                            if (itemIndex > tableItem.TKArr.Length)
                                continue

                            ; 格式化触发键显示
                            tkValue := tableItem.TKArr[itemIndex]
                            if (tkValue == "")
                                tkValue := "编辑"

                            ; 格式化循环次数
                            loopValue := tableItem.LoopCountArr[itemIndex]
                            if (loopValue == -1)
                                loopValue := "无限"
                            else
                                loopValue := String(loopValue)

                            ; 获取颜色状态
                            colorState := tableItem.ColorStateArr[itemIndex]
                            color := ""
                            if (colorState == 1)
                                color := "#4caf50"
                            else if (colorState == 2)
                                color := "#ff9800"
                            else if (colorState == 3)
                                color := "#f44336"

                            macroData := {
                                index: itemIndex,
                                remark: tableItem.RemarkArr[itemIndex] || "",
                                tk: tkValue,
                                triggerType: tableItem.TriggerTypeArr[itemIndex] || 1,
                                loopCount: loopValue,
                                forbid: tableItem.ForbidArr[itemIndex] || false,
                                color: color,
                                mode: tableItem.ModeArr[itemIndex] || 1
                            }
                            result.macros.Push(macroData)
                        }
                    }
                }
            }

            ; 返回JSON字符串
            return JSON.stringify(result)
        } catch as e {
            OutputDebug("GetKeyMacroTabData error: " e.Message)
            return JSON.stringify({
                tabIndex: tabIndex,
                tabName: MySoftData.TabNameArr[tabIndex],
                folds: [],
                macros: []
            })
        }
    }

    ; 刷新 GUI（供外部调用）
    static Refresh() {
        if (this.gui) {
            RefreshGui()
            this.SendInitialData()
        }
    }

    ; 显示窗口
    static Show() {
        if (this.gui) {
            this.gui.Show()
        }
    }

    ; 隐藏窗口
    static Hide() {
        if (this.gui) {
            this.gui.Hide()
        }
    }

    ; 窗口位置变化时同步
    static OnWindowMove(x, y, w, h) {
        IniWrite(x "π" y, IniFile, IniSection, "LastWinPos")
    }
}

; Web 消息处理函数（非类的静态方法，供 WebView2.Handler.Call 调用）
WebMessageHandlerInvoke(interface, args) {
    try {
        msg := args.WebMessageAsJson
        WebView2UI.HandleMessage(msg)
    } catch as e {
        ; 处理消息失败
    }
    return 0
}

; 帮助打开函数
ShowHelpOpen() {
    Run(A_WorkingDir "\index.html")
}

; 格式化热键显示（JS调用）
FormatHotkeyForJS(keyCombo) {
    if (!keyCombo)
        return ""
    result := keyCombo
    result := RegExReplace(result, "i)^!", "Alt+")
    result := RegExReplace(result, "i)^\+", "Shift+")
    result := RegExReplace(result, "i)^#", "Win+")
    result := RegExReplace(result, "i)^\^", "Ctrl+")
    result := RegExReplace(result, "i)<!", "Alt+")
    result := RegExReplace(result, "i)<\+", "Shift+")
    result := RegExReplace(result, "i)<#", "Win+")
    result := RegExReplace(result, "i)<\^", "Ctrl+")
    return result
}
