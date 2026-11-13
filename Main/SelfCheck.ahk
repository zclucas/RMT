#Requires AutoHotkey v2.0

RmtAssetsReleaseTag() {
    ; 与 CI 的资源标签一致，带完整版本号：预览版与正式版资源互不覆盖。
    arch := A_PtrSize == 8 ? "x64" : "x86"
    return "v" RMT_VERSION "_" arch
}

RmtAssetsBaseUrl(tag) {
    return "https://gh-proxy.com/https://github.com/zclucas/RMTAssets/releases/download/" tag "/"
}

SelfCheckMissingFiles() {
    arch := A_PtrSize == 8 ? "x64" : "x86"
    bitArch := A_PtrSize == 8 ? "64bit" : "32bit"
    tag := RmtAssetsReleaseTag()
    baseUrl := RmtAssetsBaseUrl(tag)

    criticalFiles := [
        {path: "Plugins\RMT\RMT.dll", entry: "RMT.dll", bundle: "RMT.zip"},
        {path: "Plugins\RMT\RMT.ExcelHelper.exe", entry: "RMT.ExcelHelper.exe", bundle: "RMT.zip"},
        {path: "Plugins\IbInputSimulator.dll", entry: "IbInputSimulator.dll", bundle: "Input.zip"},
        {path: "Audio\Start.wav", entry: "Start.wav", bundle: "Audio.zip"},
        {path: "Audio\End.wav", entry: "End.wav", bundle: "Audio.zip"},
        {path: "Plugins\ViGEm\ViGEmWrapper.dll", entry: "ViGEmWrapper.dll", bundle: "ViGEm.zip"},
        {path: "Joy\ViGEmBus.exe", entry: "ViGEmBus.exe", bundle: "ViGEm.zip"},
        {path: "Joy\Xbox按键映射.png", entry: "Xbox.png", bundle: "ViGEm.zip"},
        {path: "Plugins\AHK-XAML\lib\dep\ahk-xaml.dll", entry: "ahk-xaml.dll", bundle: "Xaml.zip"},
        {path: "Plugins\AHK-XAML\lib\dep\WpfAnimatedGif\WpfAnimatedGif.dll", entry: "WpfAnimatedGif.dll", bundle: "Xaml.zip"},
        {path: "Plugins\OpenCV\" arch "\RMT_OpenCV.dll", entry: "RMT_OpenCV.dll", bundle: "OpenCV.zip"},
        {path: "Plugins\OpenCV\" arch "\opencv_world481.dll", entry: "opencv_world481.dll", bundle: "OpenCV.zip"},
        {path: "Plugins\RapidOcr\" bitArch "\RapidOcrOnnx.dll", entry: "RapidOcrOnnx.dll", bundle: "RapidOcr.zip"},
        {path: "Plugins\TesseractOcr\" arch "\tesseract50.dll", entry: "tesseract50.dll", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\" arch "\leptonica-1.82.0.dll", entry: "leptonica-1.82.0.dll", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\tessdata\chi_sim.traineddata", entry: "chi_sim.traineddata", bundle: "TesseractOcr.zip"},
        {path: "Plugins\TesseractOcr\tessdata\eng.traineddata", entry: "eng.traineddata", bundle: "TesseractOcr.zip"},
        {path: "Plugins\ScreenCapture\ScreenCapture.exe", entry: "ScreenCapture.exe", bundle: "OpenCV.zip"},
        {path: "Plugins\AhiDriver\AutoHotInterception.dll", entry: "AutoHotInterception.dll", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\" arch "\interception.dll", entry: "interception_" arch ".dll", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\install.ps1", entry: "install.ps1", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\安装卸载.bat", entry: "InstallUninstall.bat", bundle: "AhiDriver.zip"},
        {path: "Plugins\AhiDriver\installer\install-interception.exe", entry: "install-interception.exe", bundle: "AhiDriver.zip"},
        {path: "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_det.onnx", entry: "ch_PP-OCRv6_det.onnx", bundle: "RapidOcr.zip"},
        {path: "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_rec.onnx", entry: "ch_PP-OCRv6_rec.onnx", bundle: "RapidOcr.zip"},
        {path: "Plugins\RapidOcr\ch_models\ppocrv6_tiny_dict.txt", entry: "ppocrv6_tiny_dict.txt", bundle: "RapidOcr.zip"},

        {path: "Lang\English.txt", entry: "English.txt", bundle: "Lang.zip"},
        {path: "Thread\Work.exe", entry: "Work.exe", bundle: "RMT.zip"},
        {path: "index.html", entry: "index.html", bundle: "RMT.zip"},
    ]
    optionalFiles := [
        {path: "Plugins\MouseControl.dll", entry: "MouseControl.dll", bundle: "Input.zip"},
        {path: "MinTool\PlayAudio.vbs", entry: "PlayAudio.vbs", bundle: "Audio.zip"},
        {path: "Plugins\AhiDriver\installer\使用说明.txt", entry: "InstallReadme.txt", bundle: "AhiDriver.zip"},
    ]

    icoFileList := ["Wait.png", "BGKey.png", "IcoRunning.ico", "Joy.png", "DeltaMove.png", "KeyListen.png", "JoyListen.png", "SearchCombo.png", "Excel.png", "Time.png", "WaitConfirm.png", "RunPro.png",
        "Arr.png", "Condition.png", "Control.png", "FlowJump.png", "Extract.png", "False.png",
        "HttpRequest.png", "FileIO.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Key.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "Prompt.png", "Run.png", "Search.png",
        "SearchPro.png", "SearchAll.png", "MacroAction.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "WindowAdjustGear32.png",
        "ZhiFuBao.png", "AiFaDian.png", "Stripe2.png", "Stripe5.png", "rabit.ico", "rabit.png", "Comment.png", "ScreenShot.png"]

    for name in icoFileList
        criticalFiles.Push({path: "Images\Soft\" name, entry: name, bundle: "ico.zip"})

    allMissing := []
    missingCritical := 0
    missingOptional := 0
    downloads := Map()
    for groupIndex, files in [criticalFiles, optionalFiles] {
        isCritical := groupIndex == 1
        for file in files {
            file.fullPath := A_WorkingDir "\" file.path
            if (!RmtAssetMissing(file.fullPath))
                continue

            file.critical := isCritical
            allMissing.Push(file)
            if (isCritical)
                missingCritical++
            else
                missingOptional++

            url := baseUrl file.bundle
            if (!downloads.Has(url))
                downloads[url] := {name: file.bundle, files: []}
            downloads[url].files.Push(file)
        }
    }

    totalMissing := allMissing.Length
    if (totalMissing == 0) {
        RmtDialog.Info(GetLang("资源文件校验通过，未发现缺失文件"), GetLang("RMT 资源自检"), 64)
        return
    }

    fileListStr := ""
    showCount := Min(allMissing.Length, 5)
    loop showCount
        fileListStr .= "  · " allMissing[A_Index].path "`n"
    if (allMissing.Length > 5)
        fileListStr .= "  ... 等 " allMissing.Length " 个文件`n"

    detailStr := ""
    if (missingCritical > 0)
        detailStr .= "⚠ 关键文件 (" missingCritical ")`n"
    if (missingOptional > 0)
        detailStr .= "可选文件 (" missingOptional ")"
    tipMsg := "检测到 " totalMissing " 个资源文件缺失`n" detailStr "`n`n" fileListStr "`n版本：" tag "`n点击【是】从 GitHub 自动下载`n点击【否】跳过（部分功能可能不可用）"

    result := RmtDialog.Confirm(tipMsg, "RMT 资源自检")
    if (!result) {
        if (missingCritical > 0) {
            criticalNames := ""
            for file in allMissing {
                if (file.critical)
                    criticalNames .= file.path "`n"
            }
            RmtDialog.Info("以下关键文件缺失，软件可能无法正常运行：`n`n" criticalNames "`n`n请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
        return
    }

    pg := RmtProgress(GetLang("RMT 资源下载"), GetLang("准备下载"), XamlWin.ActiveOwner(), GetLang("取消下载"))
    pg.Show()
    cancelled := false
    try {
        for url, download in downloads {
            pg.Report("正在下载：" download.name, 100 * (A_Index - 1) / downloads.Count)
            result := DownloadRmtAssetBundle(url, download.files, pg)
            if (result == "cancel") {
                cancelled := true
                break
            }
        }
    } finally pg.Close()

    failed := []
    stillCritical := false
    for file in allMissing {
        if (RmtAssetMissing(file.fullPath)) {
            failed.Push(file.path)
            stillCritical := stillCritical || file.critical
        }
    }

    successCount := totalMissing - failed.Length
    if (cancelled) {
        cancelMsg := "下载已取消。`n已成功补齐 " successCount "/" totalMissing " 个文件。`n可再次点击「文件校验」继续下载。"
        if (stillCritical)
            cancelMsg .= "`n`n仍有关键文件缺失，软件可能无法正常工作。"
        RmtDialog.Info(cancelMsg, "RMT 资源自检", 64)
    } else if (failed.Length) {
        failStr := ""
        for path in failed
            failStr .= path "`n"
        RmtDialog.Info("已补齐 " successCount "/" totalMissing " 个文件。`n`n以下文件修复失败：`n" failStr,
            "RMT 资源自检", stillCritical ? 16 : 48)
    } else {
        RmtDialog.Info("已补齐 " successCount " 个资源文件。", "RMT 资源自检", 64)
    }
}

DownloadAsync(url, savePath, timeoutSec, pg) {
    maxRetry := 3
    Loop maxRetry {
        if (pg.Cancelled)
            return "cancel"

        if (A_Index > 1)
            pg.Report(Format("重试 ({}/{})...", A_Index - 1, maxRetry - 1), pg.percent)

        result := DownloadOnce(url, savePath, timeoutSec, pg)
        if (result == "ok")
            return "ok"
        if (result == "cancel")
            return "cancel"
        if (FileExist(savePath))
            FileDelete(savePath)

        if (A_Index < maxRetry)
            Sleep(1000)
    }
    return "fail"
}

DownloadOnce(url, savePath, timeoutSec, pg) {
    try {
        req := ComObject("Msxml2.XMLHTTP")
        req.open("GET", url, true)
        req.send()

        startTime := A_TickCount
        Loop {
            if (pg.Cancelled) {
                req.abort()
                return "cancel"
            }

            if (req.readyState == 4)
                break

            elapsed := (A_TickCount - startTime) / 1000
            if (elapsed > timeoutSec) {
                req.abort()
                return "timeout"
            }

            Sleep(200)
        }

        if (req.status == 200) {
            stream := ComObject("ADODB.Stream")
            stream.Type := 1
            stream.Open()
            stream.Write(req.responseBody)
            stream.SaveToFile(savePath, 2)
            stream.Close()
            return "ok"
        }
        return "fail"
    } catch as e {
        pg.Report("✗ 下载异常: " e.Message, pg.percent)
        return "fail"
    }
}

RmtAssetMissing(path) {
    attrs := FileExist(path)
    if (!attrs || InStr(attrs, "D"))
        return true
    try return FileGetSize(path) == 0
    return true
}

; 每个包下载一次，只提取本次需要补齐的条目。
DownloadRmtAssetBundle(url, files, pg) {
    static sequence := 0
    stage := A_WorkingDir "\.rmt-assets-" DllCall("GetCurrentProcessId") "-" A_TickCount "-" (++sequence)
    try {
        DirCreate(stage)
        payload := stage "\download.zip"
        result := DownloadAsync(url, payload, 120, pg)
        if (result != "ok")
            return result

        entries := ""
        for file in files
            entries .= ' "' file.entry '"'
        pg.Report("正在解压：" SubStr(url, InStr(url, "/", , -1) + 1), pg.percent)
        systemDir := A_PtrSize == 4 && A_Is64bitOS ? "\Sysnative" : "\System32"
        tar := A_WinDir systemDir "\tar.exe"
        if (RunWait('"' tar '" -xf "' payload '" -C "' stage '" --' entries, , "Hide") != 0)
            return pg.Cancelled ? "cancel" : "fail"

        for file in files {
            if (RmtAssetMissing(stage "\" file.entry))
                return "fail"
        }

        for file in files {
            if (pg.Cancelled)
                return "cancel"
            if (!RmtAssetMissing(file.fullPath))
                continue

            SplitPath(file.fullPath, , &dir)
            DirCreate(dir)
            FileMove(stage "\" file.entry, file.fullPath, true)
        }
        return "ok"
    } catch as error {
        pg.Report("资源修复失败：" error.Message, pg.percent)
        return "fail"
    } finally {
        try DirDelete(stage, true)
    }
}