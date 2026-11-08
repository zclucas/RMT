#Requires AutoHotkey v2.0

; 转义插入 XAML XML 的文本。换行和标记扩展由调用方按使用位置处理。
EscapeXamlXml(value) {
    value := StrReplace(value, "&", "&amp;")
    value := StrReplace(value, "<", "&lt;")
    value := StrReplace(value, ">", "&gt;")
    return StrReplace(value, '"', "&quot;")
}
