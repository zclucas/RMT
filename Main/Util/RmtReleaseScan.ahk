#Requires AutoHotkey v2.0
#Include RmtDownload.ahk

class RmtReleaseScan {
    static Request(url, deadline) {
        if (A_TickCount >= deadline)
            throw Error("Release check timed out.")
        req := ComObject("Msxml2.ServerXMLHTTP.6.0")
        req.setTimeouts(4500, 4500, 4500, 6500)
        req.open("GET", url, true)
        req.setRequestHeader("User-Agent", "RMT-Updater")
        req.send()
        deadline := Min(deadline, A_TickCount + 8500)
        while (req.readyState != 4) {
            if (A_TickCount >= deadline) {
                req.abort()
                throw Error(url)
            }
            Sleep(45)
        }
        if (req.status != 200)
            throw Error("HTTP " req.status " · " url)
        return req.responseText
    }

    static ParseApi(text) {
        releases := JSON.parse(text, , false)
        if (!(releases is Array))
            throw ValueError("Invalid releases response")
        assets := []
        for release in releases {
            if (!release.HasProp("assets") || (release.HasProp("draft") && release.draft))
                continue
            for info in release.assets {
                asset := RmtRelease.Asset(info.name, info.browser_download_url,
                    info.HasProp("digest") ? info.digest : "", info.HasProp("size") ? info.size : 0)
                if (IsObject(asset))
                    assets.Push(asset)
            }
        }
        return assets
    }

    static GitHubHtml(current, deadline) {
        base := "https://github.com"
        repo := "/zclucas/RMT/releases/"
        html := this.Request(base repo, deadline)
        assets := []
        found := false
        pos := 1
        while (pos := RegExMatch(html, 'i)/zclucas/RMT/releases/expanded_assets/([a-z0-9._-]+)"', &match, pos)) {
            pos += match.Len
            found := true
            version := RmtRelease.Version(match[1])
            if (IsObject(version) && RmtRelease.Compare(version, current) <= 0)
                continue
            if (!IsObject(version) && match[1] != "RMT-Pre")
                continue
            links := this.Request(base repo "expanded_assets/" match[1], deadline)
            offset := 1
            while (offset := RegExMatch(links, 'i)href="(/zclucas/RMT/releases/download/[a-z0-9._-]+/([a-z0-9._-]+))"', &link, offset)) {
                offset += link.Len
                asset := RmtRelease.Asset(link[2], base link[1])
                if (IsObject(asset))
                    assets.Push(asset)
            }
        }
        if (!found)
            throw Error("GitHub Releases")
        return assets
    }

    static FetchReleases(current) {
        assets := []
        errors := []
        sources := 0
        try {
            assets.Push(this.ParseApi(this.Request("https://api.gitcode.com/api/v5/repos/ruomengtu/RMT/releases?direction=desc&page=1&per_page=100", A_TickCount + 8500))*)
            sources++
        } catch as err
            errors.Push(err.Message)

        gitHubDeadline := A_TickCount + 21000
        try {
            assets.Push(this.ParseApi(this.Request("https://api.github.com/repos/zclucas/RMT/releases?per_page=30", gitHubDeadline))*)
            sources++
        } catch as err {
            try {
                assets.Push(this.GitHubHtml(current, gitHubDeadline)*)
                sources++
            } catch as htmlErr
                errors.Push(err.Message "`n" htmlErr.Message)
        }
        if (!sources) {
            detail := ""
            for message in errors
                detail .= (detail == "" ? "" : "`n") message
            throw Error(detail)
        }
        ; 同一包保留 GitHub 的大小和摘要，优先使用 GitCode 附件。
        github := Map()
        for asset in assets {
            if InStr(asset.url, "https://github.com/") == 1
                github[asset.url] := asset
        }
        for asset in assets {
            backup := RmtDownloadDirectUrl(asset.url)
            if (backup != "" && github.Has(backup)) {
                if (github[backup].digest != "")
                    asset.digest := github[backup].digest
                if (github[backup].bytes)
                    asset.bytes := github[backup].bytes
            }
        }
        return assets
    }
}
