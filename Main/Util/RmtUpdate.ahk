#Requires AutoHotkey v2.0
#Include RmtRelease.ahk

class RmtUpdate {
    static Scan := ""
    static Available := ""
    static CheckResult := ""
    static Offering := false

    static Check(automatic := false, owner := 0) {
        if (this.Offering)
            return
        if (IsObject(this.Scan)) {
            if (!automatic) {
                this.Scan.Manual := true
                this.Scan.Owner := owner
            }
            return
        }
        if (!automatic && IsObject(this.Available)) {
            this.ShowAvailable(owner)
            return
        }

        stage := ""
        try {
            helper := A_ScriptDir "\Thread\Update.exe"
            if (FileExist(helper))
                command := '"' helper '"'
            else if (!A_IsCompiled)
                command := '"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\Thread\Update.ahk"'
            else
                throw Error(GetLang("无法启动更新程序。"))

            stage := this.NewStage()
            Run(command ' --check "' stage '" "' RMT_VERSION '"', A_ScriptDir, "Hide", &pid)
            handle := DllCall("OpenProcess", "UInt", 0x100000, "Int", false, "UInt", pid, "Ptr")
            timer := this.Poll.Bind(this)
            this.Scan := {Stage: stage, Pid: pid, Handle: handle, Timer: timer, Manual: !automatic, Owner: owner,
                Deadline: A_TickCount + 40000}
            static cleanup := ObjBindMethod(RmtUpdate, "DiscardScan")
            OnExit(cleanup)
            this.SyncHelp()
            SetTimer(timer, 140)
        } catch as err {
            if (stage != "")
                try DirDelete(stage, true)
            this.ReportCheckError(err.Message, !automatic, owner)
        }
    }

    static Poll(*) {
        scan := this.Scan
        if (!IsObject(scan))
            return
        waiting := scan.Handle ? DllCall("WaitForSingleObject", "Ptr", scan.Handle, "UInt", 0, "UInt") == 258
            : ProcessExist(scan.Pid)
        if (waiting && A_TickCount < scan.Deadline)
            return
        this.EndScan(scan)
        try {
            if (waiting)
                throw Error("Release check timed out.")
            response := JSON.parse(FileRead(scan.Stage "\result.json", "UTF-8"), , false)
            if (response.error != "")
                throw Error(response.error)
            current := RmtRelease.Version(RMT_VERSION)
            arch := A_PtrSize == 8 ? "x64" : "x86"
            asset := RmtRelease.Select(response.assets, current, arch, A_Is64bitOS, !scan.Manual,
                CfgRead(SettingFile, SettingSection, "RmtSkippedStableVersion", ""),
                CfgRead(SettingFile, SettingSection, "RmtSkippedPreviewVersion", ""))
            ; 跳过的版本仍显示在帮助页。
            latest := IsObject(asset) ? asset : RmtRelease.Select(response.assets, current, arch, A_Is64bitOS, !scan.Manual)
            this.CheckResult := IsObject(latest) ? latest : "current"
            this.Available := asset
            this.SyncHelp()
            if (IsObject(asset))
                this.ShowAvailable(scan.Owner)
        } catch as err
            this.ReportCheckError(err.Message, scan.Manual, scan.Owner)
        finally
            try DirDelete(scan.Stage, true)
    }

    static EndScan(scan) {
        SetTimer(scan.Timer, 0)
        if (scan.Handle)
            DllCall("CloseHandle", "Ptr", scan.Handle)
        this.Scan := ""
    }

    static DiscardScan(*) {
        if (IsObject(this.Scan)) {
            scan := this.Scan
            this.EndScan(scan)
            try DirDelete(scan.Stage, true)
        }
    }

    static HelpStatus() {
        if (IsObject(this.Scan))
            return GetLang("正在检查发行版本…")
        result := this.CheckResult
        if (IsObject(result))
            return Format(GetLang("有新版本 {}"), "RMTv" result.version.label)
        if (result == "current")
            return GetLang("已是最新版本")
        if (result == "failed")
            return GetLang("检查更新失败")
        return ""
    }

    static SyncHelp() {
        status := this.HelpStatus()
        try MyMainWin.ui.BatchUpdate([
            {ControlName: "HelpUpdateDot", PropertyName: "Visibility", Value: IsObject(this.Available) ? "Visible" : "Collapsed"},
            {ControlName: "HelpUpdateStatus", PropertyName: "Text", Value: status},
            {ControlName: "HelpUpdateStatus", PropertyName: "Visibility", Value: status != "" ? "Visible" : "Collapsed"}])
    }

    static ReportCheckError(detail, show, owner) {
        this.CheckResult := "failed"
        this.SyncHelp()
        this.ReportError(detail, show, owner)
    }

    static ShowAvailable(owner) {
        this.Offering := true
        try this.Offer(RmtRelease.Version(RMT_VERSION), this.Available, A_PtrSize == 8 ? "x64" : "x86", owner)
        catch as err
            this.ReportError(err.Message, true, owner)
        finally this.Offering := false
    }

    static ReportError(detail, show, owner) {
        RMTLogSys(RMT_LV_WARN, "Update", detail)
        if (show)
            RmtDialog.Info(GetLang("检查或启动更新失败。") "`n" detail, GetLang("检查更新"), owner)
    }

    static NewStage() {
        stage := A_ScriptDir "\Cache\RMT-Update-" ProcessExist() "-" A_TickCount "-" Random(100000, 999999)
        DirCreate(stage)
        return stage
    }

    static Offer(current, asset, arch, owner) {
        upgrade := asset.version.preview
            ? (current.preview ? GetLang("发现新的测试版 {}。是否更新？") : GetLang("发现新的测试版 {}。可下载整包体验。"))
            : (current.preview ? GetLang("正式版 {} 已发布。是否从测试版更新？") : GetLang("发现新的正式版 {}。是否更新？"))
        helper := A_ScriptDir "\Thread\Update.exe"
        canReplace := !(asset.version.preview && !current.preview) && asset.arch == arch && A_IsCompiled && FileExist(helper)
        hint := asset.version.preview && !current.preview ? GetLang("正式版切换测试版时仅可下载整包。")
            : asset.arch != arch ? GetLang("该发行包的架构与当前程序不同。")
            : GetLang("当前程序无法执行替换更新。")
        options := {Checkbox: GetLang("此版本不再更新"), Checked: false, Disabled: canReplace ? 0 : 1, DisabledHint: hint}
        replaceText := GetLang("替换更新")
        downloadText := GetLang("下载整包")
        message := Format(upgrade, "RMTv" asset.version.label " (" asset.arch ")")
            . "`n" Format(GetLang("当前版本 {}"), "RMTv" current.label)
        result := RmtDialog._Show(message, GetLang("软件更新"), [replaceText, downloadText, GetLang("取消")],
            Chr(0xE9CE), "{DynamicResource Accent}", owner, options)
        if (options.Checked) {
            CfgWrite(asset.version.label, SettingFile, SettingSection,
                asset.version.preview ? "RmtSkippedPreviewVersion" : "RmtSkippedStableVersion")
            CfgFlushAll()
            this.Available := ""
            this.SyncHelp()
        }
        if (result == replaceText && canReplace)
            this.Start(helper, asset, "", true)
        else if (result == downloadText) {
            path := FileSelect("S", A_MyDocuments "\" asset.name, GetLang("下载整包"), "ZIP (*.zip)")
            if (path != "") {
                if (!RegExMatch(path, "i)\.zip$"))
                    path .= ".zip"
                overwrite := !!FileExist(path)
                if (overwrite && !RmtDialog.Confirm(GetLang("文件已存在，是否覆盖？"), GetLang("下载整包"), owner))
                    return
                if (FileExist(helper))
                    this.Start(helper, asset, path, false, overwrite)
                else
                    this.DownloadInApp(asset, path, owner, overwrite)
            }
        }
    }

    static DownloadInApp(asset, path, owner, overwrite) {
        temp := path ".rmt-part-" ProcessExist() "-" A_TickCount
        try {
            result := RmtProgress.Run(GetLang("下载整包"), GetLang("正在下载更新包…"),
                (pg) => DownloadAsync(asset.url, temp, 1800, pg), owner)
            if (result != "ok" || (asset.bytes && FileGetSize(temp) != asset.bytes))
                throw Error(GetLang("下载失败"))
            FileMove(temp, path, overwrite)
            RmtDialog.Info(GetLang("更新包已保存。") "`n" path, GetLang("下载整包"), owner)
        } finally {
            if (FileExist(temp))
                try FileDelete(temp)
        }
    }

    static Start(helper, asset, path, replace, overwrite := false) {
        stage := this.NewStage()
        pid := 0
        try {
            texts := Map("软件更新", GetLang("软件更新"), "等待 RMT 退出…", GetLang("等待 RMT 退出…"),
                "正在下载更新包…", GetLang("正在下载更新包…"), "备用下载地址", GetLang("备用下载地址"),
                "正在验证更新包…", GetLang("正在验证更新包…"),
                "正在解压更新包…", GetLang("正在解压更新包…"), "正在替换程序文件…", GetLang("正在替换程序文件…"),
                "正在恢复原程序…", GetLang("正在恢复原程序…"), "更新失败。", GetLang("更新失败。"),
                "更新包已保存。", GetLang("更新包已保存。"), "更新已完成，无法自动启动 RMT。", GetLang("更新已完成，无法自动启动 RMT。"))
            enginePid := 0
            if (replace && XAMLHost.daemonHwnd)
                try enginePid := WinGetPID("ahk_id " XAMLHost.daemonHwnd)
            job := {parent: ProcessExist(), engine: enginePid, root: A_ScriptDir, original: A_ScriptFullPath,
                mode: replace ? "replace" : "download", path: path, overwrite: overwrite, name: asset.name, url: asset.url,
                digest: asset.digest, bytes: asset.bytes, arch: asset.arch, texts: texts}
            FileAppend(JSON.stringify(job, 0), stage "\job.json", "UTF-8")
            runner := stage "\Update.exe"
            FileCopy(helper, runner)
            Run('"' runner '"', stage, , &pid)
            start := A_TickCount
            while (!FileExist(stage "\ready")) {
                if (!ProcessExist(pid) || A_TickCount - start >= 8000)
                    throw Error(GetLang("无法启动更新程序。"))
                Sleep(40)
            }
            if (replace)
                ExitApp()
        } catch {
            if (pid && ProcessExist(pid)) {
                try FileAppend("", stage "\cancel")
            } else
                try DirDelete(stage, true)
            throw
        }
    }
}
