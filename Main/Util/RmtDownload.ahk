#Requires AutoHotkey v2.0

; GitCode 为资源主站；备用地址始终指向 GitHub 原文件。
RmtLargeAssetProxy() => "https://ghfile.geekertao.top/"
RmtModelDownloadMode() => "lfs"

RmtLargeAssetUrl(name) {
    if (name == "Index-Translate-2B.Q4_K_M.gguf") {
        switch RmtModelDownloadMode() {
            case "github":
                return RmtLargeAssetProxy() "https://github.com/zclucas/RMTAssets/releases/download/Common/" name
            case "zip":
                name .= ".zip"
        }
    }
    return "https://gitcode.com/ruomengtu/RMTAssets/releases/download/Common/" name
}

RmtIsAssetUrl(url) {
    return RegExMatch(url, "^https://(?:gitcode\.com/ruomengtu/RMTAssets|github\.com/zclucas/RMTAssets)/releases/download/[^/]+/[^/?]+$")
        || RegExMatch(url, "^https://(?:raw\.)?gitcode\.com/ruomengtu/RMTAssets/raw/main/Common/[^/?]+$")
}

RmtDownloadDirectUrl(url) {
    prefix := RmtLargeAssetProxy()
    if (InStr(url, prefix "https://github.com/zclucas/RMTAssets/releases/download/Common/") == 1)
        return SubStr(url, StrLen(prefix) + 1)
    if RegExMatch(url, "^https://gitcode\.com/ruomengtu/(RMT(?:Assets)?)/(releases/download/.+)$", &match) {
        path := match[2]
        if (path == "releases/download/Common/Index-Translate-2B.Q4_K_M.gguf.zip")
            path := SubStr(path, 1, -4)
        return "https://github.com/zclucas/" match[1] "/" path
    }
    if RegExMatch(url, "^https://(?:raw\.)?gitcode\.com/ruomengtu/RMTAssets/raw/main/Common/([^/?]+)$", &match)
        return "https://github.com/zclucas/RMTAssets/releases/download/Common/" match[1]
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
