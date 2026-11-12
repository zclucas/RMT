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
        this.DLVariableArr := GetGuiVarArr(6)   ; 6-可运算变量
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
        ; 计算当前表达式的结果
        if (!IsObject(this.ui))
            return
        expr := this.ui.Query("ExpressionCon")
        if (expr == "") {
            RmtDialog.Info(GetLang("表达式不能为空"))
            return
        }

        ; 先校验表达式语法
        if (!this.CheckExpressionSyntax(expr)) {
            return
        }

        try {
            result := this.EvaluateWithPlaceholderValues(expr, &variableCount)
            if (variableCount > 0)
                RmtDialog.Info(Format("{}：{}{}", GetLang("假定所有变量均为10，计算结果"), result, "`n" GetLang("提示：实际运行时会使用真实的变量值")))
            else
                RmtDialog.Info(Format(GetLang("计算结果：{}"), result))
        } catch Error as e {
            RmtDialog.Info(Format(GetLang("表达式语法错误：{}"), e.Message))
        }
    }

    EvaluateWithPlaceholderValues(expression, &variableCount := 0) {
        return EvaluateExpression(RegExReplace(expression, "\{[^{}]+\}", "10", &variableCount))
    }

    OnClickSureBtn(state := "", ctrl := "", event := "") {
        if (this.SureBtnAction == "")
            return

        ; 获取表达式
        expression := IsObject(this.ui) ? this.ui.Query("ExpressionCon") : ""

        ; 校验表达式语法（仅当表达式不为空且非基础值时）
        if (expression != "") {
            ; 先进行基本语法检查
            if (!this.CheckExpressionSyntax(expression)) {
                return
            }

            ; 尝试计算测试表达式，校验语法
            try {
                this.EvaluateWithPlaceholderValues(expression)
            } catch Error as e {
                RmtDialog.Info(Format(GetLang("表达式语法错误：{}"), e.Message))
                return
            }
        }

        action := this.SureBtnAction
        action(this.Index, expression)
        this._CloseWindow()
    }

    ; 检查表达式基本语法
    CheckExpressionSyntax(expr) {
        errorMsg := ""

        ; ========== 步骤1：单独校验所有{...}变量结构（在删除空格之前）==========
        varPattern := "\{[^{}]*\}" ; 匹配所有{...}结构（不包含嵌套的{}）
        if RegExMatch(expr, varPattern, &varMatch, 1) {
            loop {
                ; 提取当前匹配的变量整体（如{ var }）
                varWhole := varMatch[0]
                ; 提取大括号内的原始内容（去掉首尾{和}）
                varContentRaw := SubStr(varWhole, 2, -1)

                ; 校验1：变量内容不能为空（包括只有空格的情况）
                varContentTrim := Trim(varContentRaw)
                if (varContentTrim = "") {
                    RmtDialog.Info(GetLang("表达式错误：变量内容不能为空"))
                    return false
                }
                ; 校验2：变量内容（去空格后）不能包含{}
                if InStr(varContentTrim, "{") || InStr(varContentTrim, "}") {
                    RmtDialog.Info(GetLang("表达式错误：变量内容不能包含{}"))
                    return false
                }
                ; 校验3：变量内容不能包含任何空白符（包括空格/制表符等）
                if RegExMatch(varContentRaw, "\s") {
                    RmtDialog.Info(GetLang("表达式错误：变量内容不能包含空白符"))
                    return false
                }

                ; 继续匹配下一个变量（直到无匹配）
                if !RegExMatch(expr, varPattern, &varMatch, varMatch.Pos + varMatch.Len)
                    break
            }
        }

        ; ========== 步骤2：过滤空格，校验字符集（含数值处理函数名与逗号）==========
        cleanExpr := StrReplace(expr, " ")
        cleanExpr := StrReplace(cleanExpr, "　", "")
        cleanExpr := StrReplace(cleanExpr, "（", "(")
        cleanExpr := StrReplace(cleanExpr, "）", ")")
        cleanExpr := StrReplace(cleanExpr, "，", ",")

        ; 仅允许已知函数名
        checkFn := RegExReplace(cleanExpr, "\{[^{}]+\}", "")
        pos := 1
        loop {
            if !RegExMatch(checkFn, "([a-zA-Z_]+)\(", &fnMatch, pos)
                break
            fname := StrLower(fnMatch[1])
            if (fname != "abs" && fname != "max" && fname != "min" && fname != "round" && fname != "ceil" && fname != "floor") {
                RmtDialog.Info(Format(GetLang("表达式错误：不支持的函数 {}"), fnMatch[1]))
                return false
            }
            pos := fnMatch.Pos + fnMatch.Len
        }

        validPattern := "^(?:\{[^{}]+\}|-?\d+\.\d+|-?\d+|[+\-*/%^()⌊⌋,]|[a-zA-Z_])+$"
        if !RegExMatch(cleanExpr, validPattern) {
            RmtDialog.Info(GetLang("表达式包含非法字符或格式错误"))
            return false
        }

        ; ========== 步骤3：校验括号 / 取整括号是否匹配 ==========
        openCount := 0, closeCount := 0
        floorOpen := 0, floorClose := 0
        for k, char in StrSplit(cleanExpr) {
            if char = "("
                openCount++
            else if char = ")"
                closeCount++
            else if char = "⌊"
                floorOpen++
            else if char = "⌋"
                floorClose++
            if closeCount > openCount {
                RmtDialog.Info(GetLang("表达式错误：括号不匹配"))
                return false
            }
            if floorClose > floorOpen {
                RmtDialog.Info(GetLang("表达式错误：取整括号不匹配"))
                return false
            }
        }
        if openCount != closeCount {
            RmtDialog.Info(GetLang("表达式错误：括号不匹配"))
            return false
        }
        if floorOpen != floorClose {
            RmtDialog.Info(GetLang("表达式错误：取整括号不匹配"))
            return false
        }

        ; ========== 步骤4：校验表达式首尾是否为非法运算符 ==========
        firstChar := SubStr(cleanExpr, 1, 1)
        lastChar := SubStr(cleanExpr, -1)
        invalidStart := "+*/%^," ; 负号(-)、括号、函数名、⌊ 允许开头
        invalidEnd := "+-*/%^⌊," ; 运算符与 ⌊、逗号不允许结尾
        if (InStr(invalidStart, firstChar)) {
            RmtDialog.Info(GetLang("表达式错误：不能以运算符开头"))
            return false
        }
        if (InStr(invalidEnd, lastChar)) {
            RmtDialog.Info(GetLang("表达式错误：不能以运算符结尾"))
            return false
        }

        ; ========== 步骤5：校验连续运算符（允许+-、--作为负数，不允许其他连续）==========
        ; 匹配连续的运算符（2个或更多），排除 +-、-+、--（负数的情况）
        ; 但也要排除变量后的情况：{var}+5 这种不校验
        exprWithoutVar := RegExReplace(cleanExpr, "\{[^{}]+\}", "Var") ; 去掉变量后再检查
        if RegExMatch(exprWithoutVar, "[+\-*/%^]{2,}", &opMatch) {
            matched := opMatch[0]
            ; 允许 +-、-+、--（负数或正数前缀）
            if (matched != "+-" && matched != "-+" && matched != "--") {
                RmtDialog.Info(GetLang("表达式错误：存在连续运算符") matched)
                return false
            }
        }

        ; ========== 步骤6：校验空括号 ==========
        if RegExMatch(cleanExpr, "\(\)") {
            RmtDialog.Info(GetLang("表达式错误：空括号"))
            return false
        }

        ; ========== 步骤7：校验括号内为空或仅有运算符 ==========
        ; 检查括号内是否为空或仅有空格/运算符
        if RegExMatch(cleanExpr, "\([+\-*/%^]*\)", &emptyParenMatch) {
            if (emptyParenMatch[0] != "()") {
                RmtDialog.Info(GetLang("表达式错误：括号内内容无效"))
                return false
            }
        }

        ; ========== 步骤8：校验除零风险 ==========
        ; 检查 /0 或 /(表达式) 的情况
        if RegExMatch(cleanExpr, "/0(?![\d.])") {
            RmtDialog.Info(GetLang("表达式错误：除数不能为零"))
            return false
        }
        ; 检查 /(数字) 且数字为0的情况（简单检测）
        if RegExMatch(cleanExpr, "/\(([^()]*)\)", &divParen) {
            parenContent := divParen[1]
            ; 如果括号内是明确的0
            if (parenContent == "0" || parenContent == "+0" || parenContent == "-0") {
                RmtDialog.Info(GetLang("表达式错误：除数不能为零"))
                return false
            }
        }

        ; ========== 步骤9：校验乘方运算符周围的负数 ==========
        ; 负数的非整数次方（如(-2)^0.5）会导致NaN错误，不支持
        ; 匹配 (-数字)^(小数) 的情况，但排除 .0、.00 等整数形式
        ; 正则解释：\( + (-数字) + \) + \^ + (数字开头) + \. + (非零数字 + 任意数字)
        ; 这样 (-2)^3.0 不会匹配，但 (-2)^0.5 会匹配
        if RegExMatch(cleanExpr, "\(-[^)]*\)\^\d*\.[1-9]\d*") {
            RmtDialog.Info(GetLang("表达式错误：不支持负数的非整数次方运算"))
            return false
        }

        return true
    }
}
