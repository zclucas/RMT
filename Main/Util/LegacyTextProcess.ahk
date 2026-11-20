#Requires AutoHotkey v2.0

; 1.0.9 文本处理写的是多个独立变量，另有部分模式在新版中没有对应项。
; 仅执行由旧配置保留的参数。
class LegacyTextProcess {
    static Run(Data, tableItem, index) {

        ; 获取源变量值
        sourceText := ""
        if (!TryGetTabVarValue(&sourceText, tableItem, index, Data.SourceVariable, false)) {
            return
        }

        if (sourceText == "") {
            return
        }

        NameArr := []
        ValueArr := []

        ; 处理文本
        switch Integer(Data.ProcessType) {
            case 1: ; 文本分割
                parts := this.ProcessTextSplitWithParams(sourceText, Data)
                partIndex := 1
                loop Data.ToggleArr.Length {
                    if (Data.ToggleArr[A_Index] && partIndex <= parts.Length) {
                        NameArr.Push(Data.VariableArr[A_Index])
                        ValueArr.Push(parts[partIndex])
                        partIndex++
                    }
                }

            case 2: ; 文本替换
                processedText := this.ProcessTextReplace(sourceText, Data.SearchText, Data.ReplaceText, Data.CaseSensitive, Data.UseRegex)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 3: ; 数字提取
                extractedText := this.ExtractDigits(sourceText)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, extractedText)

            case 4: ; 字母提取
                extractedText := this.ExtractAlphabets(sourceText)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, extractedText)

            case 5: ; 中文提取
                extractedText := this.ExtractChineseChars(sourceText)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, extractedText)

            case 6: ; 去空格处理
                processedText := this.ProcessWhitespace(sourceText, Data.SplitParam)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 7: ; 大小写转换
                processedText := this.ProcessCaseConversion(sourceText, Data.SplitParam)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 8: ; URL编解码
                processedText := this.ProcessURLEncode(sourceText, Data.SplitParam)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 9: ; Base64编解码
                processedText := this.ProcessBase64(sourceText, Data.SplitParam)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 10: ; 文本统计
                statsText := this.GetTextStatistics(sourceText, Data.SplitParam)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, statsText)

            case 11: ; 固定长度分割
                length := Data.SplitParam ? Integer(Data.SplitParam) : 10
                maxCount := Data.MaxSplitCount ? Integer(Data.MaxSplitCount) : 0
                parts := this.SplitByLength(sourceText, length, maxCount)
                partIndex := 1
                loop 4 {
                    if (Data.ToggleArr[A_Index] && partIndex <= parts.Length) {
                        NameArr.Push(Data.VariableArr[A_Index])
                        ValueArr.Push(parts[partIndex])
                        partIndex++
                    }
                }

            case 12: ; 多字符分割
                delimiters := Data.SplitParam ? Data.SplitParam : ",|;"
                maxCount := Data.MaxSplitCount ? Integer(Data.MaxSplitCount) : 0
                parts := this.SplitByMultipleDelimiters(sourceText, delimiters, maxCount)
                partIndex := 1
                loop 4 {
                    if (Data.ToggleArr[A_Index] && partIndex <= parts.Length) {
                        NameArr.Push(Data.VariableArr[A_Index])
                        ValueArr.Push(parts[partIndex])
                        partIndex++
                    }
                }

            case 13: ; 行过滤
                filteredText := this.FilterLines(sourceText, Data.SearchText)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, filteredText)

            case 14: ; 去重处理
                processedText := this.RemoveDuplicates(sourceText)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 15: ; 排序处理
                processedText := this.SortText(sourceText, Data.ReverseProcess)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, processedText)

            case 16: ; 随机文本
                length := Data.SplitParam ? Integer(Data.SplitParam) : 10
                randomText := this.GenerateRandomText(length)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, randomText)

            case 17: ; 日期时间
                format := Data.SplitParam ? Data.SplitParam : "yyyy-MM-dd HH:mm:ss"
                dateTimeText := this.GetDateTime(format)
                this.SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, dateTimeText)
        }

        ; 将结果保存到变量
        if (NameArr.Length > 0) {
            loop NameArr.Length {
                MySetGlobalVariable([NameArr[A_Index]], [ValueArr[A_Index]], false)
            }
        }
    }

    ; 文本处理辅助函数
    static ReverseString(text) {
        ; 反转字符串
        reversed := ""
        for i in StrSplit(text, "") {
            reversed := i . reversed
        }
        return reversed
    }

    static ProcessTextReplace(sourceText, searchText, replaceText, caseSensitive, useRegex) {
        ; 文本替换处理
        if (useRegex) {
            ; 正则表达式替换
            flags := caseSensitive ? "" : "i"
            return RegExReplace(sourceText, (flags == "" ? "" : flags ")") searchText, replaceText)
        } else {
            ; 普通文本替换
            if (caseSensitive) {
                return StrReplace(sourceText, searchText, replaceText, true)
            } else {
                ; 大小写不敏感的替换
                return RegExReplace(sourceText, "i)" . this.RegExEscape(searchText), replaceText)
            }
        }
    }

    static RegExEscape(text) {
        ; 转义正则表达式特殊字符
        specialChars := ".^$*+?()[]\{}|"
        escaped := text
        for char in StrSplit(specialChars, "") {
            escaped := StrReplace(escaped, char, "\" char)
        }
        return escaped
    }

    static ApplyResultAction(originalValue, newValue, action) {
        ; 应用结果处理方式
        switch Integer(action) {
            case 1: ; 覆盖变量
                return newValue
            case 2: ; 追加结果
                return originalValue . newValue
            case 3: ; 前置结果
                return newValue . originalValue
            default:
                return newValue
        }
    }

    static SaveSingleResultMacro(Data, tableItem, index, &NameArr, &ValueArr, result) {
        ; 保存单个结果到第一个选中的变量
        loop 4 {
            if (Data.ToggleArr[A_Index]) {
                NameArr.Push(Data.VariableArr[A_Index])
                originalValue := ""
                TryGetTabVarValue(&originalValue, tableItem, index, Data.VariableArr[A_Index], false)
                finalValue := this.ApplyResultAction(originalValue, result, Data.ResultAction)
                ValueArr.Push(finalValue)
                break
            }
        }
    }

    static ProcessTextSplitWithParams(sourceText, Data) {
        ; 文本分割处理
        if (Data.ReverseProcess) {
            reversedText := this.ReverseString(sourceText)
            parts := StrSplit(reversedText, Data.SplitDelimiter)
            reversedParts := []
            for part in parts
                reversedParts.InsertAt(1, this.ReverseString(part))
            return reversedParts
        } else {
            return StrSplit(sourceText, Data.SplitDelimiter)
        }
    }

    static ExtractDigits(text) {
        ; 提取所有数字
        numbers := ""
        for char in StrSplit(text, "") {
            charCode := Ord(char)
            if (charCode >= Ord("0") && charCode <= Ord("9")) {
                numbers .= char
            }
        }
        return numbers
    }

    static ExtractAlphabets(text) {
        ; 提取所有字母
        letters := ""
        for char in StrSplit(text, "") {
            charCode := Ord(char)
            if ((charCode >= Ord("a") && charCode <= Ord("z")) || (charCode >= Ord("A") && charCode <= Ord("Z"))) {
                letters .= char
            }
        }
        return letters
    }

    static ExtractChineseChars(text) {
        ; 提取中文字符
        chinese := ""
        for char in StrSplit(text, "") {
            if (this.IsChineseChar(char)) {
                chinese .= char
            }
        }
        return chinese
    }

    static IsChineseChar(char) {
        ; 判断是否为中文字符
        code := Ord(char)
        return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)
    }

    static ProcessWhitespace(text, mode) {
        ; 处理空格
        switch mode {
            case "1": ; 去除前后空格
                return Trim(text)
            case "2": ; 去除所有空格
                return StrReplace(text, " ", "")
            case "3": ; 去除多余空格
                return RegExReplace(text, "\s+", " ")
            default:
                return Trim(text)
        }
    }

    static ProcessCaseConversion(text, mode) {
        ; 大小写转换
        switch mode {
            case "1": ; 全部大写
                return StrUpper(text)
            case "2": ; 全部小写
                return StrLower(text)
            case "3": ; 首字母大写
                return StrUpper(SubStr(text, 1, 1)) . StrLower(SubStr(text, 2))
            default:
                return text
        }
    }

    static ProcessURLEncode(text, mode) {
        ; URL编解码
        switch mode {
            case "1": ; URL编码
                encoded := ""
                for char in StrSplit(text, "") {
                    code := Ord(char)
                    if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || char == "-" || char == "_" || char == "." || char == "~") {
                        encoded .= char
                    } else {
                        encoded .= "%" . Format("{:02X}", code)
                    }
                }
                return encoded
            case "2": ; URL解码
                decoded := ""
                i := 1
                while (i <= StrLen(text)) {
                    char := SubStr(text, i, 1)
                    if (char == "%") {
                        hex := SubStr(text, i + 1, 2)
                        decoded .= Chr("0x" . hex)
                        i += 3
                    } else {
                        decoded .= char
                        i++
                    }
                }
                return decoded
            default:
                return text
        }
    }

    static ProcessBase64(text, mode) {
        ; Base64编解码（简化实现）
        switch mode {
            case "1": ; Base64编码
                return this.Base64Encode(text)
            case "2": ; Base64解码
                return this.Base64Decode(text)
            default:
                return text
        }
    }

    static Base64Encode(text) {
        ; 简化的Base64编码
        charset := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        encoded := ""
        i := 1
        while (i <= StrLen(text)) {
            ; 每3个字符处理一次
            b1 := Ord(SubStr(text, i, 1))
            b2 := i + 1 <= StrLen(text) ? Ord(SubStr(text, i + 1, 1)) : 0
            b3 := i + 2 <= StrLen(text) ? Ord(SubStr(text, i + 2, 1)) : 0

            combined := (b1 << 16) | (b2 << 8) | b3

            encoded .= SubStr(charset, ((combined >> 18) & 0x3F) + 1, 1)
            encoded .= SubStr(charset, ((combined >> 12) & 0x3F) + 1, 1)
            encoded .= (i + 1 <= StrLen(text)) ? SubStr(charset, ((combined >> 6) & 0x3F) + 1, 1) : "="
            encoded .= (i + 2 <= StrLen(text)) ? SubStr(charset, (combined & 0x3F) + 1, 1) : "="

            i += 3
        }
        return encoded
    }

    static Base64Decode(encoded) {
        ; 简化的Base64解码
        charset := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        decoded := ""
        i := 1
        while (i <= StrLen(encoded)) {
            char1 := SubStr(encoded, i, 1)
            char2 := SubStr(encoded, i + 1, 1)
            char3 := SubStr(encoded, i + 2, 1)
            char4 := SubStr(encoded, i + 3, 1)

            v1 := InStr(charset, char1, true) - 1
            v2 := InStr(charset, char2, true) - 1
            v3 := (char3 != "=") ? InStr(charset, char3, true) - 1 : 0
            v4 := (char4 != "=") ? InStr(charset, char4, true) - 1 : 0

            combined := (v1 << 18) | (v2 << 12) | (v3 << 6) | v4

            decoded .= Chr((combined >> 16) & 0xFF)
            if (char3 != "=") {
                decoded .= Chr((combined >> 8) & 0xFF)
            }
            if (char4 != "=") {
                decoded .= Chr(combined & 0xFF)
            }

            i += 4
        }
        return decoded
    }

    static GetTextStatistics(text, mode) {
        ; 文本统计
        switch mode {
            case "1": ; 字符数
                return StrLen(text)
            case "2": ; 单词数
                words := StrSplit(text, [" ", "`t", "`n", "`r"])
                count := 0
                for word in words {
                    if (StrLen(word) > 0) {
                        count++
                    }
                }
                return count
            case "3": ; 行数
                lines := StrSplit(text, ["`n", "`r"])
                return lines.Length
            case "4": ; 中文字符数
                count := 0
                for char in StrSplit(text, "") {
                    if (this.IsChineseChar(char)) {
                        count++
                    }
                }
                return count
            default:
                return StrLen(text)
        }
    }

    static SplitByLength(text, length, maxCount) {
        parts := []
        if (length < 1)
            return parts
        current := 1
        while (current <= StrLen(text)) {
            part := SubStr(text, current, length)
            parts.Push(part)
            current += length
            if (maxCount > 0 && parts.Length >= maxCount) {
                break
            }
        }
        return parts
    }

    static SplitByMultipleDelimiters(text, delimiters, maxCount) {
        ; 按多个分隔符分割
        delimiterList := StrSplit(delimiters, "|")
        result := [text]

        for delimiter in delimiterList {
            newResult := []
            for part in result {
                subParts := StrSplit(part, delimiter)
                for subPart in subParts {
                    newResult.Push(subPart)
                }
            }
            result := newResult
        }

        if (maxCount > 0 && result.Length > maxCount) {
            loop result.Length - maxCount {
                result[maxCount] .= delimiterList[1] . result[maxCount + A_Index]
            }
            while (result.Length > maxCount) {
                result.RemoveAt(result.Length)
            }
        }

        return result
    }

    static FilterLines(text, filter) {
        ; 过滤行
        if (!filter) {
            return text
        }

        lines := StrSplit(text, ["`n", "`r"])
        filtered := []

        for line in lines {
            if (InStr(line, filter)) {
                filtered.Push(line)
            }
        }

        resultText := ""
        for i, value in filtered {
            if (i > 1) {
                resultText .= "`n"
            }
            resultText .= value
        }
        return resultText
    }

    static RemoveDuplicates(text) {
        ; 去重处理
        lines := StrSplit(text, ["`n", "`r"])
        unique := Map()
        result := []

        for line in lines {
            key := StrLen(line) > 0 ? line : ""
            if (!unique.Has(key)) {
                unique[key] := true
                result.Push(line)
            }
        }

        resultText := ""
        for i, value in result {
            if (i > 1) {
                resultText .= "`n"
            }
            resultText .= value
        }
        return resultText
    }

    static SortText(text, reverse) {
        ; 排序处理
        lines := StrSplit(text, ["`n", "`r"])
        lines.Sort()

        if (reverse) {
            reversed := []
            loop lines.Length {
                reversed.Push(lines[lines.Length - A_Index + 1])
            }
            lines := reversed
        }

        resultText := ""
        for i, value in lines {
            if (i > 1) {
                resultText .= "`n"
            }
            resultText .= value
        }
        return resultText
    }

    static GenerateRandomText(length) {
        ; 生成随机文本
        chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        randomText := ""

        length := length > 0 ? length : 10

        Loop length {
            randomIndex := Random(1, StrLen(chars))
            randomText .= SubStr(chars, randomIndex, 1)
        }

        return randomText
    }

    static GetDateTime(format) {
        ; 获取格式化的日期时间
        now := A_Now
        if (!format) {
            format := "yyyy-MM-dd HH:mm:ss"
        }

        ; 简单的格式替换
        result := format
        result := StrReplace(result, "yyyy", FormatTime(now, "yyyy"))
        result := StrReplace(result, "MM", FormatTime(now, "MM"))
        result := StrReplace(result, "dd", FormatTime(now, "dd"))
        result := StrReplace(result, "HH", FormatTime(now, "HH"))
        result := StrReplace(result, "mm", FormatTime(now, "mm"))
        result := StrReplace(result, "ss", FormatTime(now, "ss"))

        return result
    }
}
