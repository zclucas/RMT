#Requires AutoHotkey v2.0

; Common 大文件通过分片同步到 Gitee；旧附件仍可回退 GitHub。
RmtLargeAssetProxy() => "https://ghfile.geekertao.top/"

RmtLargeAssetUrl(name) {
    return "https://gitee.com/fateman/RMTAssets/releases/download/Common/" name
}

RmtIsAssetUrl(url) {
    return RegExMatch(url, "^https://(?:gitee\.com/fateman|github\.com/zclucas)/RMTAssets/releases/download/[^/]+/[^/?]+$")
}

RmtDownloadDirectUrl(url) {
    prefix := RmtLargeAssetProxy()
    if (InStr(url, prefix "https://github.com/zclucas/RMTAssets/releases/download/Common/") == 1)
        return SubStr(url, StrLen(prefix) + 1)
    if RegExMatch(url, "^https://gitee\.com/fateman/(RMT(?:Assets)?/releases/download/.+)$", &match)
        return "https://github.com/zclucas/" match[1]
    return ""
}

RmtDownloadAlternative(url, received, total, elapsedMs) {
    ; 取至少 3 秒的样本，以已收到字节的平均速度估算剩余时间。
    if (elapsedMs < 3000 || received <= 0 || received >= total)
        return ""
    return elapsedMs * (total - received) / received > 3600000 ? RmtDownloadDirectUrl(url) : ""
}

RmtDownloadContentLength(path) {
    try {
        headers := FileRead(path, "UTF-8")
        ; 只读最后一组响应头，避免使用重定向或代理连接响应的长度。
        if (RegExMatch(headers, "m)^HTTP/\S+ 200[^\r\n]*\R((?:[^\r\n]+\R)*)\R\z", &response)
            && RegExMatch(response[1], "im)^Content-Length:[ \t]*(\d+)", &length))
            return Integer(length[1])
    }
    return 0
}
