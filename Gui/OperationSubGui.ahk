#Requires AutoHotkey v2.0

; =====================================================================
; 运算子编辑器 —— XAML 迁移版（嵌套编辑器）
; 公开接口保持：ShowGui(Index, ExpressStr) / AddGui() / Gui / SureBtnAction
;   / OwnerHwnd / ParentTile / Index
; 调用方：Gui/OperationGui.ahk:229-245、Gui/MacroGraph/MacroGraphFormal.ahk:569-582
; =====================================================================

class OperationSubGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.ui := ""
        this.OwnerHwnd := ""
        this.SureBtnAction := ""
        this.Index := 0
        this.DLVariableArr := []
        this._closed := true
        ; 运算符：符号 / 控件名 / hover 提示
        this._OpBtnPairs := [
            ["+", "BtnOpAdd", "+（加）"], ["-", "BtnOpSub", "-（减）"], ["*", "BtnOpMul", "*（乘）"],
            ["/", "BtnOpDiv", "/（除）"], ["%", "BtnOpMod", "%（取余）"],
            ["^", "BtnOpPow", "^（乘方）"], ["(", "BtnOpLParen", "(（左括号）"], [")", "BtnOpRParen", ")（右括号）"]]
        ; 数值处理：Fluent/符号 / 控件名 / 函数名 / hover / 双参 / 字体
        fluent := "Segoe Fluent Icons, Segoe MDL2 Assets"
        symbol := "Segoe UI Symbol, Segoe UI, " fluent
        this._NumProcPairs := [
            ["≈", "BtnNumRound", "round", "四舍五入取整", false, symbol],
            [Chr(0xE74A), "BtnNumCeil", "ceil", "向上取整", false, fluent],
            [Chr(0xE74B), "BtnNumFloor", "floor", "向下取整", false, fluent],
            ["|x|", "BtnNumAbs", "abs", "绝对值", false, "Segoe UI, " fluent],
            [GetLang("最大值"), "BtnNumMax", "max", "最大值", true, ""],
            [GetLang("最小值"), "BtnNumMin", "min", "最小值", true, ""]]
    }

    Hwnd() {
        return (IsObject(this.ui) && this.ui.HasProp("wpfHwnd")) ? this.ui.wpfHwnd : 0
    }

    _EscapeXml(s) => EscapeXamlXml(s)

    ShowGui(Index, ExpressStr) {
        global MySoftData
        if (IsObject(this.ui) && !this._closed)   ; XAML 窗口不支持隐藏复用：关旧重建
            this._CloseWindow()
        this._BuildAndShow()
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
        }
        this.Init(Index, ExpressStr)
        if (!XamlWin.Open(this.ui, "", XamlWin.Owner(this)))
            this._closed := true
    }

    ; 兼容接口：原生 AddGui() 创建并显示窗口（MacroGraphFormal.ahk:577 直接调用）。
    ; XAML 版只负责建窗（数据为空），随后 ShowGui 关旧重建并填充数据。
    AddGui() {
        if (IsObject(this.ui) && !this._closed)
            return
        this._BuildAndShow()
        XamlWin.Open(this.ui, "", XamlWin.Owner(this))
    }

    _BuildAndShow() {
        global MySoftData
        this._closed := false
        title := this.ParentTile GetLang("表达式")
        this._title := title
        titleHeight := "30"
        okStyle := FrontInfoGui._OkBtnHoverStyle()

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}").TextElement_FontSize(XAMLHost.FontSize())
        main.Rows(titleHeight, "*")

        ; === 标题栏 ===
        chrome := XAMLHost.AddTitleBar(main, title, titleHeight)

        ; === 内容 ===
        body := main.Add("StackPanel").Grid_Row(1).Margin("10,6,10,6")

        ; 当前运算表达式（可编辑）+ 右侧清空
        body.Add("TextBlock").Text(GetLang("当前运算表达式（可编辑）")).Foreground("{DynamicResource TextMain}").FontSize("12")
        exprRow := body.Add("Grid").Margin("0,4,0,0")
        exprRow.Cols("*", "6", "26")
        exprRow.Add("TextBox").Name("ExpressionCon").Grid_Column(0).Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("4,0").FontSize("11")
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        clearExpr := exprRow.Add("Button").Name("BtnClearExpr").Grid_Column(2).Width(26).Height(26).MinHeight(26)
            .Content(Chr(0xE74D)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12")
            .Cursor("Hand").ToolTip(GetLang("清空")).Padding("0")
            .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        clearExpr.InjectResources(FrontInfoGui._ToolBtnHoverStyle())

        ; 变量：下拉框 + 添加（紧挨表达式下方）
        varRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,8,0,0")
        varRow.Add("TextBlock").Text(GetLang("变量：")).VerticalAlignment("Center").Foreground("{DynamicResource TextMain}").FontSize("12")
        varRow.Add("ComboBox").Name("OperaVariableCon").Width(150).Height(26).MinHeight(26).Margin("8,0,0,0")
            .VerticalContentAlignment("Center").FontSize("11")
            .Foreground("{DynamicResource InputText}").Background("{DynamicResource InputBg}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        addVarBtn := varRow.Add("Button").Name("BtnAddVariable").Content(GetLang("添加")).Width(52).Height(26).MinHeight(26).Margin("8,0,0,0").Cursor("Hand")
            .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
            .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
        addVarBtn.InjectResources(FrontInfoGui._ToolBtnHoverStyle())

        ; 运算符：单行正方形按钮
        body.Add("TextBlock").Text(GetLang("运算符")).Margin("0,8,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        opRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        for pair in this._OpBtnPairs {
            opRow.Add("Button").Name(pair[2]).Content(pair[1]).Width(30).Height(30).MinHeight(30).Margin("0,0,6,0")
                .Cursor("Hand").ToolTip(GetLang(pair[3])).Padding("0")
                .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
                .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
        }

        ; 数值处理：符号按钮；最大值/最小值用文本
        body.Add("TextBlock").Text(GetLang("数值处理")).Margin("0,8,0,0").Foreground("{DynamicResource TextMain}").FontSize("12")
        numRow := body.Add("StackPanel").Orientation("Horizontal").Margin("0,4,0,0")
        for pair in this._NumProcPairs {
            isText := (pair[2] == "BtnNumMax" || pair[2] == "BtnNumMin")
            btn := numRow.Add("Button").Name(pair[2]).Content(pair[1]).Height(30).MinHeight(30).Margin("0,0,6,0")
                .Cursor("Hand").ToolTip(GetLang(pair[4])).Padding(isText ? "8,0" : "0")
                .HorizontalContentAlignment("Center").VerticalContentAlignment("Center")
                .Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
                .BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")
            if (isText)
                btn.FontSize("11")
            else
                btn.Width(30).FontFamily(pair[6]).FontSize("13")
        }

        ; 底部：计算结果（与确定同款）+ 确定，间距 50px
        btnRow := body.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").Margin("0,10,0,0")
        calcBtn := btnRow.Add("Button").Name("BtnCalcResult").Content(GetLang("计算结果"))
            .Width(100).Height(32).MinHeight(32).Margin("0,0,50,0").Cursor("Hand")
            .Background("{DynamicResource ActionBg}").Foreground("{DynamicResource ActionText}")
            .BorderBrush("{DynamicResource ActionStroke}").BorderThickness("1").FontSize(13).FontWeight("Bold")
        calcBtn.InjectResources(okStyle)
        AddCmdOkBtn(btnRow, "BtnSure")

        ; === 创建 XAMLHost ===
        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", this.OwnerHwnd)
        this.Gui := this.ui   ; 兼容访问器：外部仅做空判断（MacroGraphFormal.ahk:576）
        this.ui.xaml := StrReplace(this.ui.xaml, 'Width="940" Height="700"', 'Title="' this._EscapeXml(title) '" Width="400" Height="300"')
        this.ui.xaml := StrReplace(this.ui.xaml, 'FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif"', 'FontFamily="' MainSoftData.FontType '"')
        this.ui.xaml := StrReplace(this.ui.xaml, '%resources%', '')

        ; === 事件 ===
        this.ui.OnEvent("Window", "Closing", ObjBindMethod(this, "OnWindowClosing"))
        this.ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnWindowLoad"))
        this.ui.OnEvent("BtnClosePanel", "Click", ObjBindMethod(this, "OnCancelClick"))
        for pair in this._OpBtnPairs
            this.ui.OnEvent(pair[2], "Click", this.OnClickOperatorBtn.Bind(this, pair[1]))
        for pair in this._NumProcPairs
            this.ui.OnEvent(pair[2], "Click", this.OnClickNumProcBtn.Bind(this, pair[3], pair[5]))
        this.ui.OnEvent("BtnClearExpr", "Click", ObjBindMethod(this, "OnClearExprClick"))
        this.ui.OnEvent("BtnAddVariable", "Click", ObjBindMethod(this, "OnVariableChanged"))
        this.ui.OnEvent("BtnCalcResult", "Click", ObjBindMethod(this, "OnCalculateResultBtnClick"))
        this.ui.OnEvent("BtnSure", "Click", ObjBindMethod(this, "OnClickSureBtn"))
    }

    Init(Index, ExpressStr) {
        this.DLVariableArr := GetGuiVarArr("number")
        this.Index := Index

        ; 初始化变量列表下拉框（每次打开都重建，等价原生 Delete+Add+Text）
        this.ui.Update("OperaVariableCon", "ClearItems", "")
        for item in this.DLVariableArr {
            if (item == "")
                continue
            this.ui.Update("OperaVariableCon", "AddItem", item)
        }
        if (this.DLVariableArr.Length > 0)
            this.ui.Update("OperaVariableCon", "Text", this.DLVariableArr[1])
        ; 设置表达式（每次打开都要设置）
        this.ui.Update("ExpressionCon", "Text", ExpressStr)
        ; 聚焦表达式输入框（原生聚焦“当前运算表达式”标签，等价迁移为聚焦可编辑框）
        try this.ui.Update("ExpressionCon", "Focus", "True")
    }

    OnWindowLoad(state, ctrl, event) {
        XamlWin.OnLoadTheme(this.ui)
    }

    OnWindowClosing(state, ctrl, event) {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        this.ui := ""
        this.Gui := ""
        this._closed := true
    }

    OnCancelClick(state, ctrl, event) {
        this._CloseWindow()
    }

    _CloseWindow() {
        if (this.OwnerHwnd != "" && MainSoftData.IsModalSubGui) {
            try SafeGuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
        }
        if (IsObject(this.ui)) {
            try this.ui.Update("Window", "Close", "")
        }
        this.ui := ""
        this.Gui := ""
        this._closed := true
    }

    OnClickOperatorBtn(Symbol, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        expr := this.ui.Query("ExpressionCon")
        this.ui.Update("ExpressionCon", "Text", expr Symbol)
    }

    ; 数值处理：用函数包裹当前表达式；max/min 第二参默认 10
    OnClickNumProcBtn(fnName, dualArg, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        expr := this.ui.Query("ExpressionCon")
        if (expr == "")
            expr := "0"
        if (dualArg)
            this.ui.Update("ExpressionCon", "Text", fnName "(" expr ",10)")
        else
            this.ui.Update("ExpressionCon", "Text", fnName "(" expr ")")
    }

    OnClearExprClick(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        this.ui.Update("ExpressionCon", "Text", "")
        try this.ui.Update("ExpressionCon", "Focus", "True")
    }

    OnVariableChanged(state := "", ctrl := "", event := "") {
        ; 当用户选择变量时，自动添加到表达式
        if (!IsObject(this.ui))
            return
        VarName := this.ui.Query("OperaVariableCon")
        if (VarName != "") {
            currentExpr := this.ui.Query("ExpressionCon")
            this.ui.Update("ExpressionCon", "Text", currentExpr "{" VarName "}")
        }
    }

    OnCalculateResultBtnClick(state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui))
            return
        expression := this.ui.Query("ExpressionCon")
        if (IsOperationExpressionBlank(expression)) {
            RmtDialog.Info(GetLang("表达式不能为空"))
            return
        }

        variableCount := 0
        try {
            result := EvaluateExpression(expression, , true, &variableCount)
            if (variableCount > 0) {
                result := EvaluateExpression(expression)
                RmtDialog.Info(Format("{}：{}", GetLang("假定所有变量均为10，计算结果"), result) "`n"
                    GetLang("提示：实际运行时会使用真实的变量值"))
            } else {
                RmtDialog.Info(Format(GetLang("计算结果：{}"), result))
            }
        } catch OperationExpressionSyntaxError as e {
            RmtDialog.Info(Format(GetLang("表达式语法错误：{}"), GetLang(e.Message)))
        } catch Error as e {
            if (variableCount > 0)
                RmtDialog.Info(Format(GetLang("假定所有变量均为10，无法计算：{}"), GetLang(e.Message)) "`n"
                    GetLang("提示：实际运行时会使用真实的变量值"))
            else
                RmtDialog.Info(Format(GetLang("表达式计算失败：{}"), GetLang(e.Message)))
        }
    }

    OnClickSureBtn(state := "", ctrl := "", event := "") {
        if (this.SureBtnAction == "")
            return

        expression := IsObject(this.ui) ? this.ui.Query("ExpressionCon") : ""
        try {
            EvaluateExpression(expression, , true)
        } catch Error as e {
            message := (e is OperationExpressionSyntaxError) ? "表达式语法错误：{}" : "表达式计算失败：{}"
            RmtDialog.Info(Format(GetLang(message), GetLang(e.Message)))
            return
        }

        action := this.SureBtnAction
        action(this.Index, expression)
        this._CloseWindow()
    }
}
