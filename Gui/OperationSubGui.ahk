#Requires AutoHotkey v2.0

class OperationSubGui {
    __new() {
        this.ParentTile := ""
        this.Gui := ""
        this.OwnerHwnd := ""
        this.SureBtnAction := ""
        this.FocusCon := ""
        this.Index := 0
        this.ExpressionCon := ""
        this.OperaVariableCon := ""  ; 恢复下拉框
    }

    ShowGui(Index, ExpressStr) {
        if (this.Gui != "") {
            if (this.OwnerHwnd != "") {
                this.Gui.Opt("+Owner" this.OwnerHwnd)
            }
            this.Gui.Show()
        }
        else {
            this.AddGui()
        }

        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("+Disabled")
            }
        }

        this.DLVariableArr := GetGuiVarArr(6)
        this.Index := Index

        ; 初始化变量列表下拉框
        this.OperaVariableCon.Delete()
        this.OperaVariableCon.Add(this.DLVariableArr)
        this.OperaVariableCon.Text := this.DLVariableArr[1]
        this.ExpressionCon.Value := ExpressStr
        this.FocusCon.Focus()
    }

    AddGui() {
        MyGui := Gui(, this.ParentTile GetLang("运算编辑器"))
        this.Gui := MyGui
        if (this.OwnerHwnd != "") {
            MyGui.Opt("+Owner" this.OwnerHwnd)
        }
        MyGui.SetFont("S10 W550 Q2", MySoftData.FontType)

        PosX := 10
        PosY := 10
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 400), Format("{}`n{}", GetLang(
            "运算符：+（加）、-（减）、*（乘）、（/）除、（%）取余"), GetLang("^（乘方）、()（括号）")))

        PosX := 10
        PosY += 40
        this.FocusCon := MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 300, 20), GetLang("当前运算表达式（可编辑）"))
        PosY += 20
        this.ExpressionCon := MyGui.Add("Edit", Format("x{} y{} w{}", PosX, PosY, 350), "")
        this.ExpressionCon.Enabled := true  ; 改为可编辑

        PosX := 10
        PosY += 30
        MyGui.Add("Text", Format("x{} y{} w{} h{}", PosX, PosY, 300, 20), GetLang("操作运算符"))
        PosX := 10
        PosY += 20
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 50, 30), "+")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("+"))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 60, PosY, 50, 30), "-")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("-"))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 120, PosY, 50, 30), "*")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("*"))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 180, PosY, 50, 30), "/")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("/"))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 240, PosY, 50, 30), "%")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("%"))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 300, PosY, 50, 30), "^")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("^"))

        PosY += 40
        PosX := 10
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 50, 30), "(")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn("("))
        con := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 60, PosY, 50, 30), ")")
        con.OnEvent("Click", (*) => this.OnClickOperatorBtn(")"))

        PosY += 45
        PosX := 10
        MyGui.Add("Text", Format("x{} y{} w{}", PosX, PosY, 120), GetLang("变量："))
        PosX += 50
        this.OperaVariableCon := MyGui.Add("ComboBox", Format("x{} y{} w{} R5", PosX, PosY - 2, 150), [])
        PosX += 155
        Con := MyGui.Add("Button", Format("x{} y{} w{}", PosX, PosY - 4, 50), GetLang("添加"))
        Con.OnEvent("Click", (*) => this.OnVariableChanged())

        PosY += 45
        PosX := 25
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX, PosY, 100, 40), GetLang("计算结果"))
        btnCon.OnEvent("Click", (*) => this.OnCalculateResultBtnClick())
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 110, PosY, 100, 40), GetLang("退格"))
        btnCon.OnEvent("Click", (*) => this.OnBackspaceBtnClick())
        btnCon := MyGui.Add("Button", Format("x{} y{} w{} h{}", PosX + 220, PosY, 100, 40), GetLang("确定"))
        btnCon.OnEvent("Click", (*) => this.OnClickSureBtn())

        MyGui.OnEvent("Close", (*) => this.OnClose())
        MyGui.Show(Format("w{} h{}", 370, 310))
    }

    OnClose(*) {
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
    }

    OnClickOperatorBtn(Symbol) {
        ; 所有运算符直接添加到表达式
        this.ExpressionCon.Value := this.ExpressionCon.Value Symbol
    }

    OnVariableChanged() {
        ; 当用户选择变量时，自动添加到表达式
        VarName := this.OperaVariableCon.Text
        if (VarName != "") {
            ; 如果当前表达式不为空且不是运算符，添加一个空格
            currentExpr := this.ExpressionCon.Value
            if (currentExpr != "" && !InStr("+-*/%^().", SubStr(currentExpr, -1))) {
                this.ExpressionCon.Value := currentExpr "{" VarName "}"
            } else {
                this.ExpressionCon.Value := currentExpr "{" VarName "}"
            }
        }
    }

    OnBackspaceBtnClick() {
        ; 获取当前表达式
        expr := this.ExpressionCon.Value
        if (expr == "")
            return

        ; 删除最后一个字符
        this.ExpressionCon.Value := SubStr(expr, 1, -1)
    }

    OnCalculateResultBtnClick() {
        ; 计算当前表达式的结果
        expr := this.ExpressionCon.Value
        if (expr == "") {
            MsgBox(GetLang("表达式不能为空"))
            return
        }

        ; 先校验表达式语法
        if (!this.CheckExpressionSyntax(expr)) {
            return
        }

        ; 检查是否包含变量（使用{...}格式）
        hasVariable := RegExMatch(expr, "\{[^{}]+\}")

        ; 如果有变量，先将其替换为假定值（10）
        if (hasVariable) {
            ; 获取所有变量名（{变量名}格式）
            VarNames := []
            pos := 1
            loop {
                match := RegExMatch(expr, "\{([^{}]+)\}", &varMatch, pos)
                if (!match)
                    break
                VarName := varMatch[0]  ; 完整的 {变量名}
                ; 避免重复添加
                found := false
                for v in VarNames {
                    if (v == VarName) {
                        found := true
                        break
                    }
                }
                if (!found)
                    VarNames.Push(VarName)
                pos := varMatch.Pos + varMatch.Len
            }

            ; 替换变量为假定值10
            testExpr := expr
            for VarName in VarNames {
                testExpr := StrReplace(testExpr, VarName, "10")
            }

            ; 计算包含变量的表达式
            try {
                result := EvaluateExpression(testExpr)
                MsgBox(Format("{}：{}{}", GetLang("假定所有变量均为10，计算结果"), result, "`n" GetLang("提示：实际运行时会使用真实的变量值")))
            } catch Error as e {
                MsgBox(Format(GetLang("表达式语法错误：{}"), e.Message))
            }
        } else {
            ; 没有变量，直接计算
            try {
                result := EvaluateExpression(expr)
                MsgBox(Format(GetLang("计算结果：{}"), result))
            } catch Error as e {
                MsgBox(Format(GetLang("表达式语法错误：{}"), e.Message))
            }
        }
    }

    OnClickSureBtn() {
        if (this.SureBtnAction == "")
            return

        ; 获取表达式
        expression := this.ExpressionCon.Value

        ; 校验表达式语法（仅当表达式不为空且非基础值时）
        if (expression != "") {
            ; 先进行基本语法检查
            if (!this.CheckExpressionSyntax(expression)) {
                return
            }

            ; 提取所有变量名（{变量名}格式）
            VarNames := []
            pos := 1
            loop {
                match := RegExMatch(expression, "\{([a-zA-Z一-龥][a-zA-Z0-9一-龥]*)\}", &VarName, pos)
                if (!match)
                    break
                ; 避免重复添加
                found := false
                for v in VarNames {
                    if (v == VarName[0]) {
                        found := true
                        break
                    }
                }
                if (!found)
                    VarNames.Push(VarName[0])
                pos := match + StrLen(VarName[0])
            }

            ; 替换所有变量为假定值10
            testExpr := expression
            for VarName in VarNames {
                testExpr := StrReplace(testExpr, "{" VarName "}", "10")
            }

            ; 尝试计算测试表达式，校验语法
            try {
                EvaluateExpression(testExpr)
            } catch Error as e {
                MsgBox(Format(GetLang("表达式语法错误：{}"), e.Message))
                return
            }
        }

        action := this.SureBtnAction
        action(this.Index, expression)
        if (this.OwnerHwnd != "" && MySoftData.IsModalSubGui) {
            try {
                GuiFromHwnd(this.OwnerHwnd).Opt("-Disabled")
            }
        }
        this.Gui.Hide()
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
                    MsgBox(GetLang("表达式错误：变量内容不能为空"))
                    return false
                }
                ; 校验2：变量内容（去空格后）不能包含{}
                if InStr(varContentTrim, "{") || InStr(varContentTrim, "}") {
                    MsgBox(GetLang("表达式错误：变量内容不能包含{}"))
                    return false
                }
                ; 校验3：变量内容不能包含任何空白符（包括空格/制表符等）
                if RegExMatch(varContentRaw, "\s") {
                    MsgBox(GetLang("表达式错误：变量内容不能包含空白符"))
                    return false
                }

                ; 继续匹配下一个变量（直到无匹配）
                if !RegExMatch(expr, varPattern, &varMatch, varMatch.Pos + varMatch.Len)
                    break
            }
        }

        ; ========== 步骤2：过滤所有空格，校验数字/运算符/括号 ==========
        cleanExpr := StrReplace(expr, " ") ; 过滤所有空格（包括大括号内外）

        ; 正则拆解：
        ; 1. \{[^{}]+\}  → 匹配{包裹的变量（已提前校验，此处仅占位）
        ; 2. -?\d+\.\d+  → 匹配严格数论小数（5.0、0.5、-3.14）
        ; 3. -?\d+       → 匹配整数（5、-8、0）
        ; 4. [+\-*/%^()] → 匹配运算符和括号
        validPattern := "^(?:\{[^{}]+\}|-?\d+\.\d+|-?\d+|[+\-*/%^()])+$"
        if !RegExMatch(cleanExpr, validPattern) {
            MsgBox(GetLang("表达式包含非法字符或格式错误"))
            return false
        }

        ; ========== 步骤3：校验括号是否匹配 ==========
        openCount := 0, closeCount := 0
        for k, char in StrSplit(cleanExpr) {
            if char = "("
                openCount++
            else if char = ")"
                closeCount++
            ; 若右括号数量提前超过左括号，直接判定非法
            if closeCount > openCount {
                MsgBox(GetLang("表达式错误：括号不匹配"))
                return false
            }
        }
        if openCount != closeCount {
            MsgBox(GetLang("表达式错误：括号不匹配"))
            return false
        }

        ; ========== 步骤4：校验表达式首尾是否为非法运算符 ==========
        firstChar := SubStr(cleanExpr, 1, 1)
        lastChar := SubStr(cleanExpr, -1)
        invalidStart := "+*/%^" ; 负号(-)和括号(允许开头
        invalidEnd := "+-*/%^" ; 所有运算符和括号(都不允许结尾
        if (InStr(invalidStart, firstChar)) {
            MsgBox(GetLang("表达式错误：不能以运算符开头"))
            return false
        }
        if (InStr(invalidEnd, lastChar)) {
            MsgBox(GetLang("表达式错误：不能以运算符结尾"))
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
                MsgBox(GetLang("表达式错误：存在连续运算符") matched)
                return false
            }
        }

        ; ========== 步骤6：校验空括号 ==========
        if RegExMatch(cleanExpr, "\(\)") {
            MsgBox(GetLang("表达式错误：空括号"))
            return false
        }

        ; ========== 步骤7：校验括号内为空或仅有运算符 ==========
        ; 检查括号内是否为空或仅有空格/运算符
        if RegExMatch(cleanExpr, "\([+\-*/%^]*\)", &emptyParenMatch) {
            if (emptyParenMatch[0] != "()") {
                MsgBox(GetLang("表达式错误：括号内内容无效"))
                return false
            }
        }

        ; ========== 步骤8：校验除零风险 ==========
        ; 检查 /0 或 /(表达式) 的情况
        if RegExMatch(cleanExpr, "/0(?![\d.])") {
            MsgBox(GetLang("表达式错误：除数不能为零"))
            return false
        }
        ; 检查 /(数字) 且数字为0的情况（简单检测）
        if RegExMatch(cleanExpr, "/\(([^()]*)\)", &divParen) {
            parenContent := divParen[1]
            ; 如果括号内是明确的0
            if (parenContent == "0" || parenContent == "+0" || parenContent == "-0") {
                MsgBox(GetLang("表达式错误：除数不能为零"))
                return false
            }
        }

        ; ========== 步骤9：校验乘方运算符周围的负数 ==========
        ; 负数的非整数次方（如(-2)^0.5）会导致NaN错误，不支持
        ; 匹配 (-数字)^(小数) 的情况，但排除 .0、.00 等整数形式
        ; 正则解释：\( + (-数字) + \) + \^ + (数字开头) + \. + (非零数字 + 任意数字)
        ; 这样 (-2)^3.0 不会匹配，但 (-2)^0.5 会匹配
        if RegExMatch(cleanExpr, "\(-[^)]*\)\^\d*\.[1-9]\d*") {
            MsgBox(GetLang("表达式错误：不支持负数的非整数次方运算"))
            return false
        }

        return true
    }
}
