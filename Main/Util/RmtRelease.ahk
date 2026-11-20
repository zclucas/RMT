#Requires AutoHotkey v2.0

class RmtRelease {
    static Version(value) {
        if (!RegExMatch(Trim(value), "i)^(?:RMT)?v?(\d{1,6}(?:\.\d{1,6}){1,3})(?:F(\d{1,6}))?$", &match))
            return ""
        parts := []
        for part in StrSplit(match[1], ".")
            parts.Push(Integer(part))
        while (parts.Length < 4)
            parts.Push(0)
        label := parts[1] "." parts[2]
        if (parts[3] || parts[4])
            label .= "." parts[3]
        if (parts[4])
            label .= "." parts[4]
        preview := match[2] != ""
        number := preview ? Integer(match[2]) : 0
        return {parts: parts, preview: preview, number: number, label: label (preview ? "F" number : "")}
    }

    static Compare(left, right) {
        loop 4 {
            diff := left.parts[A_Index] - right.parts[A_Index]
            if (diff)
                return diff
        }
        if (left.preview != right.preview)
            return left.preview ? -1 : 1
        return left.number - right.number
    }

    static Asset(name, url, digest := "", bytes := 0) {
        if (!RegExMatch(name, "i)^RMTv([0-9.]+(?:F\d+)?)_(x64|x86|x32)\.zip$", &match))
            return ""
        prefix := "i)^https://(?:github\.com/zclucas/RMT|gitee\.com/fateman/RMT)/releases/download/[a-z0-9._-]+/"
        if (!RegExMatch(url, prefix "[a-z0-9._-]+$") || SubStr(url, InStr(url, "/", , -1) + 1) != name)
            return ""
        version := this.Version(match[1])
        if (!IsObject(version))
            return ""
        arch := StrLower(match[2])
        return {version: version, arch: arch == "x32" ? "x86" : arch, name: name, url: url,
            digest: RegExMatch(digest, "i)^sha256:[0-9a-f]{64}$") ? SubStr(digest, 8) : "",
            bytes: IsInteger(bytes) && bytes > 0 ? Integer(bytes) : 0}
    }

    static Select(assets, current, installedArch, has64Bit, automatic, skippedStable := "", skippedPreview := "") {
        stable := "", preview := ""
        for asset in assets {
            if ((asset.arch == "x64" && !has64Bit) || this.Compare(asset.version, current) <= 0)
                continue
            if (asset.version.preview) {
                if ((!automatic || current.preview) && this.Prefer(asset, preview, installedArch))
                    preview := asset
            } else if (this.Prefer(asset, stable, installedArch))
                stable := asset
        }
        if (IsObject(stable) && stable.version.label == skippedStable)
            stable := ""
        if (IsObject(preview) && preview.version.label == skippedPreview)
            preview := ""
        if (!IsObject(stable))
            return preview
        if (IsObject(preview) && this.Compare(preview.version, stable.version) > 0)
            return preview
        return stable
    }

    static Prefer(asset, previous, arch) {
        if (!IsObject(previous))
            return true
        order := this.Compare(asset.version, previous.version)
        if (order != 0)
            return order > 0
        if (asset.arch != previous.arch)
            return asset.arch == arch
        isGitee := InStr(asset.url, "https://gitee.com/") == 1
        previousIsGitee := InStr(previous.url, "https://gitee.com/") == 1
        if (isGitee != previousIsGitee)
            return isGitee
        return asset.digest != "" && previous.digest == ""
    }
}

RmtUpdateMutex(openOnly := false) {
    name := "Local\RMT_AppUpdate"
    if (openOnly)
        return DllCall("OpenMutexW", "UInt", 0x100000, "Int", false, "Str", name, "Ptr")
    handle := DllCall("CreateMutexW", "Ptr", 0, "Int", true, "Str", name, "Ptr")
    exists := A_LastError == 183
    if (handle && exists) {
        DllCall("CloseHandle", "Ptr", handle)
        return 0
    }
    return handle
}

RmtUpdateIsRunning() {
    handle := RmtUpdateMutex(true)
    if (handle)
        DllCall("CloseHandle", "Ptr", handle)
    return !!handle
}

RmtUpdateRecoverAtStartup() {
    Loop Files A_ScriptDir "\.rmt-update-*", "D" {
        if (!RegExMatch(A_LoopFileName, "i)^\.rmt-update-[a-f0-9]{32}$")
            || !FileExist(A_LoopFileFullPath "\pending.json"))
            continue
        runner := A_LoopFileFullPath "\Update.exe"
        try Run('"' runner '" --recover', A_LoopFileFullPath)
        catch
            MsgBox("无法恢复中断的 RMT 更新。`n" A_LoopFileFullPath, "RMT", 16)
        return true
    }
    return false
}
