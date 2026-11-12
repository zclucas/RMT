#Requires AutoHotkey v2.0

GetExpressionResult(expression, tableItem, tableIndex, &result) {
    if (IsOperationExpressionBlank(expression))
        return false

    try {
        result := EvaluateExpression(expression, (name) => ResolveOperationExpressionValue(tableItem, tableIndex, name))
        return true
    } catch {
        return false
    }
}

ResolveOperationExpressionValue(tableItem, tableIndex, name) {
    if (SubStr(name, 1, 1) == "ε" && MySoftData.ArrayMap.Has(SubStr(name, 2)))
        return MySoftData.ArrayMap[SubStr(name, 2)]
    if (TryGetTabVarValue(&value, tableItem, tableIndex, name, true, false))
        return value
    throw ValueError("表达式引用的变量不存在", , name)
}

IsOperationExpressionBlank(expression) {
    return !RegExMatch(expression, "[^\s　]")
}

TranslateOperationExpression(expression, toDisplay) {
    names := Map()
    for displayName in GetSpecialVarArr() {
        key := GetLangKey(displayName)
        if (key != displayName) {
            if (toDisplay)
                names[key] := displayName
            else
                names[displayName] := key
        }
    }
    if (names.Count == 0)
        return expression

    translated := ""
    pos := 1
    while (matchPos := RegExMatch(expression, "\{([^{}]+)\}", &ref, pos)) {
        translated .= SubStr(expression, pos, matchPos - pos) "{" names.Get(ref[1], ref[1]) "}"
        pos := matchPos + ref.Len
    }
    return translated SubStr(expression, pos)
}

class OperationExpressionSyntaxError extends ValueError {
}

; 保存时用未知值校验变量引用，仍计算其中可以确定的常量部分。
EvaluateExpression(expression, resolveValue := "", validateOnly := false, &variableCount := 0) {
    tokens := Tokenize(expression, resolveValue, validateOnly, &variableCount)
    if (tokens.Length == 0)
        return 0

    pos := 1
    result := ParseAddSub(tokens, &pos)
    if (pos <= tokens.Length)
        throw OperationExpressionSyntaxError("表达式包含多余内容")
    ; 计算过程中保留浮点精度，输出时去除浮点表示的尾差。
    if (result is Float)
        return (Abs(result) > 1.79769313486231e308) ? Format("{:.17g}", result) : Format("{:.15g}", result)
    return result
}

Tokenize(expression, resolveValue, validateOnly, &variableCount) {
    static punctuation := Map("（", "(", "）", ")", "，", ",")
    tokens := []
    variableCount := 0
    pos := 1
    length := StrLen(expression)

    while (pos <= length) {
        char := SubStr(expression, pos, 1)
        if (RegExMatch(expression, "\G[\s　]+", &spaces, pos)) {
            pos += spaces.Len
            continue
        }
        if (char == "{") {
            if (!RegExMatch(expression, "\G\{([^{}]+)\}", &ref, pos) || IsOperationExpressionBlank(ref[1]))
                throw OperationExpressionSyntaxError("表达式错误：变量引用格式不正确")
            variableCount++
            pos += ref.Len
            if (validateOnly) {
                tokens.Push("{}") ; 词法分析器保留的未知操作数
                continue
            }
            value := IsObject(resolveValue) ? resolveValue(ref[1]) : 10
            if (value is Array) {
                if (value.Length == 0)
                    throw ValueError("表达式需要数值", , ref[1])
                for index, item in value {
                    if (index > 1)
                        tokens.Push(",")
                    tokens.Push(OperationExpressionNumber(item, ref[1]))
                }
            } else {
                tokens.Push(OperationExpressionNumber(value, ref[1]))
            }
            continue
        }

        if (RegExMatch(expression, "i)\G(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?", &num, pos)) {
            tokens.Push(num[0])
            pos += num.Len
            continue
        }
        if (RegExMatch(expression, "\G[a-zA-Z_]+", &name, pos)) {
            tokens.Push(StrLower(name[0]))
            pos += name.Len
            continue
        }

        char := punctuation.Get(char, char)
        if (InStr("+-*/%^()⌊⌋,", char)) {
            tokens.Push(char)
            pos++
            continue
        }
        throw OperationExpressionSyntaxError("表达式包含无效字符", , char)
    }

    return tokens
}

OperationExpressionNumber(value, name) {
    if (!IsNumber(value))
        throw ValueError("表达式需要数值", , name)
    return ReadOperationNumber(value)
}

ReadOperationNumber(value) {
    if (value is String && RegExMatch(Trim(value), "^([+-]?)0*([1-9]\d{18,})$", &integerText)) {
        limit := (integerText[1] == "-") ? "9223372036854775808" : "9223372036854775807"
        if (integerText.Len(2) > StrLen(limit) || StrCompare(integerText[2], limit) > 0)
            return CheckOperationNumberRange(Float(value))
    }
    return CheckOperationNumberRange(Number(value))
}

CheckOperationNumberRange(value) {
    if (value is Float && !(Abs(value) <= 1.7976931348623157e308))
        throw ValueError("表达式结果超出数值范围")
    return value
}

ParseAddSub(tokens, &pos) {
    value := ParseMulDiv(tokens, &pos)
    while (pos <= tokens.Length && InStr("+-", tokens[pos])) {
        op := tokens[pos++]
        next := ParseMulDiv(tokens, &pos)
        if (value == "" || next == "") {
            value := ""
            continue
        }
        result := (op == "+") ? value + next : value - next
        decreases := (op == "+") ? next < 0 : next > 0
        if (result is Integer && next != 0 && (result < value) != decreases)
            result := (op == "+") ? Float(value) + next : Float(value) - next
        value := CheckOperationNumberRange(result)
    }
    return value
}

ParseMulDiv(tokens, &pos) {
    value := ParseUnary(tokens, &pos)
    while (pos <= tokens.Length && InStr("*/%", tokens[pos])) {
        op := tokens[pos++]
        next := ParseUnary(tokens, &pos)
        if (next == 0 && op != "*")
            throw ValueError("表达式错误：除数不能为零")
        if (value == "" || next == "") {
            value := ""
            continue
        }
        switch op {
            case "*":
                result := value * next
                ; 整数乘积溢出时用浮点计算，避免回绕成无关数值。
                if (result is Integer && next != 0 && (next == -1 ? value != 0 && result == value : result // next != value))
                    result := Float(value) * next
                value := result
            case "/": value /= next
            case "%": value := Mod(value, next)
        }
        CheckOperationNumberRange(value)
    }
    return value
}

ParseUnary(tokens, &pos) {
    if (pos <= tokens.Length && InStr("+-", tokens[pos])) {
        sign := tokens[pos++]
        value := ParseUnary(tokens, &pos)
        if (value == "" || sign == "+")
            return value
        if (value is Float && value == 9223372036854775808.0)
            return Integer(-value)
        negated := -value
        return (value < 0 && negated < 0) ? -Float(value) : negated
    }
    return ParsePower(tokens, &pos)
}

ParsePower(tokens, &pos) {
    value := ParseAtom(tokens, &pos)
    if (pos <= tokens.Length && tokens[pos] == "^") {
        pos++
        exponent := ParseUnary(tokens, &pos)
        if (value == "" || exponent == "")
            return ""
        if (exponent == 1)
            return value
        approximate := CheckOperationNumberRange(Float(value) ** exponent)
        if (value is Integer && exponent is Integer && exponent >= 0
            && approximate >= -9223372036854775808.0 && approximate < 9223372036854775808.0)
            return value ** exponent
        return approximate
    }
    return value
}

ParseAtom(tokens, &pos) {
    if (pos > tokens.Length)
        throw OperationExpressionSyntaxError("表达式缺少操作数")
    token := tokens[pos++]

    if (IsNumber(token))
        return ReadOperationNumber(token)
    if (token == "{}")
        return ""

    if (token == "abs" || token == "max" || token == "min" || token == "round" || token == "ceil" || token == "floor")
        return ParseFuncCall(tokens, &pos, token)

    if (token == "(" || token == "⌊") {
        value := ParseAddSub(tokens, &pos)
        closing := (token == "(") ? ")" : "⌋"
        if (pos > tokens.Length || tokens[pos] != closing)
            throw OperationExpressionSyntaxError("表达式缺少右括号", , closing)
        pos++
        return (value != "" && token == "⌊") ? Round(value) : value
    }

    throw OperationExpressionSyntaxError("表达式包含无效操作数", , token)
}

ParseFuncCall(tokens, &pos, name) {
    if (pos > tokens.Length || tokens[pos] != "(")
        throw OperationExpressionSyntaxError("函数缺少左括号", , name)
    pos++

    args := [ParseAddSub(tokens, &pos)]
    while (pos <= tokens.Length && tokens[pos] == ",") {
        pos++
        args.Push(ParseAddSub(tokens, &pos))
    }
    if (pos > tokens.Length || tokens[pos] != ")")
        throw OperationExpressionSyntaxError("函数缺少右括号", , name)
    pos++

    if (args.Length > 1 && name != "max" && name != "min" && !(name == "round" && args.Length == 2))
        throw OperationExpressionSyntaxError("表达式错误：函数参数数量不正确", , name)
    for value in args {
        if (value == "")
            return ""
    }

    switch name {
        case "abs":
            return Abs(args[1])
        case "round":
            return RoundOperationNumber(args*)
        case "ceil":
            return Ceil(args[1])
        case "floor":
            return Floor(args[1])
        case "max":
            return Max(args*)
        case "min":
            return Min(args*)
    }
}

RoundOperationNumber(value, decimals := 0) {
    if (decimals != Integer(decimals))
        throw ValueError("表达式错误：小数位数必须为整数")
    ; 指定的位数比浮点精度更细时，直接保留原数。
    if (value == 0 || (decimals > 0 && Log(Abs(value)) + decimals >= 15))
        return value
    return ReadOperationNumber(Round(value, decimals))
}
