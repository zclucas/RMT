#Requires AutoHotkey v2.0

SelfCheckMissingFiles() {
    ; 带 F 后缀的测试版（如 1.2F23）无对应资源 tag，不提供自动下载
    if (RegExMatch(RMT_VERSION, "i)\d+\.\d+F")) {
        RmtDialog.Info(GetLang("带 F 后缀的测试版本不支持文件校验自动下载") "`n"
            . GetLang("资源仓库仅对应正式版本 tag（如 v1.2_x64）"), GetLang("RMT 资源自检"), 64)
        return
    }

    version := RMT_VERSION  ; 使用完整版本名，不做 *.* 截断（如 1.3.5 -> tag v1.3.5_x64）
    arch := A_PtrSize == 8 ? "x64" : "x86"
    bitArch := A_PtrSize == 8 ? "64bit" : "32bit"
    tag := "v" version "_" arch
    baseUrl := "https://gh-proxy.com/https://github.com/zclucas/RMTAssets/releases/download/" tag "/"

    criticalMap := Map(
        "Plugins\RMT\RMT.dll", "RMT.dll",
        "Plugins\RMT\RMT.ExcelHelper.exe", "RMT.ExcelHelper.exe",
        "Plugins\IbInputSimulator.dll", "IbInputSimulator.dll",
        "Audio\Start.wav", "Start.wav",
        "Audio\End.wav", "End.wav",
        "Plugins\ViGEm\ViGEmWrapper.dll", "ViGEmWrapper.dll",
        "Joy\ViGEmBus.exe", "ViGEmBus.exe",
        "Joy\Xbox按键映射.png", "Xbox.png",
        "Plugins\AHK-XAML\lib\dep\ahk-xaml.dll", "ahk-xaml.dll",
        "Plugins\AHK-XAML\lib\dep\WpfAnimatedGif\WpfAnimatedGif.dll", "WpfAnimatedGif.dll",
        "Plugins\OpenCV\" arch "\RMT_OpenCV.dll", "RMT_OpenCV.dll",
        "Plugins\OpenCV\" arch "\opencv_world481.dll", "opencv_world481.dll",
        "Plugins\Voice\" arch "\VoiceDll.dll", "VoiceDll.dll",
        "Plugins\Voice\" arch "\sherpa-onnx-c-api.dll", "sherpa-onnx-c-api.dll",
        "Plugins\Voice\" arch "\onnxruntime.dll", "onnxruntime.dll",
        "Plugins\Voice\" arch "\onnxruntime_providers_shared.dll", "onnxruntime_providers_shared.dll",
        "Plugins\Voice\" arch "\vcruntime140.dll", "vcruntime140.dll",
        "Plugins\Voice\" arch "\msvcp140.dll", "msvcp140.dll",
        "Plugins\Voice\" arch "\msvcp140_1.dll", "msvcp140_1.dll",
        "Plugins\Voice\" arch "\msvcp140_2.dll", "msvcp140_2.dll",
        "Plugins\Voice\" arch "\api-ms-win-core-path-l1-1-0.dll", "api-ms-win-core-path-l1-1-0.dll",
        "Plugins\Voice\models\kws\decoder-epoch-13-avg-2-chunk-16-left-64.onnx", "kws_decoder.onnx",
        "Plugins\Voice\models\kws\encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx", "kws_encoder.int8.onnx",
        "Plugins\Voice\models\kws\joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx", "kws_joiner.int8.onnx",
        "Plugins\Voice\models\kws\tokens.txt", "kws_tokens.txt",
        "Plugins\RapidOcr\" bitArch "\RapidOcrOnnx.dll", "RapidOcrOnnx.dll",
        "Plugins\TesseractOcr\" arch "\tesseract50.dll", "tesseract50.dll",
        "Plugins\TesseractOcr\" arch "\leptonica-1.82.0.dll", "leptonica-1.82.0.dll",
        "Plugins\TesseractOcr\tessdata\chi_sim.traineddata", "chi_sim.traineddata",
        "Plugins\TesseractOcr\tessdata\eng.traineddata", "eng.traineddata",
        "Plugins\ScreenCapture\ScreenCapture.exe", "ScreenCapture.exe",
        "Plugins\AhiDriver\AutoHotInterception.dll", "AutoHotInterception.dll",
        "Plugins\AhiDriver\" arch "\interception.dll", "interception_" arch ".dll",
        "Plugins\AhiDriver\installer\install.ps1", "install.ps1",
        "Plugins\AhiDriver\installer\安装卸载.bat", "InstallUninstall.bat",
        "Plugins\AhiDriver\installer\install-interception.exe", "install-interception.exe",
        "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_det.onnx", "ch_PP-OCRv6_det.onnx",
        "Plugins\RapidOcr\ch_models\ch_PP-OCRv6_rec.onnx", "ch_PP-OCRv6_rec.onnx",
        "Plugins\RapidOcr\ch_models\ppocrv6_tiny_dict.txt", "ppocrv6_tiny_dict.txt",
        "Lang\中文.txt", "chinese.txt",
        "Lang\English.txt", "English.txt",
        "Thread\Work.exe", "Work.exe",
        "index.html", "index.html")
    if (arch == "x64")
        criticalMap["Plugins\Voice\x64\vcruntime140_1.dll"] := "vcruntime140_1.dll"

    optionalMap := Map(
        "Plugins\MouseControl.dll", "MouseControl.dll",
        "MinTool\PlayAudio.vbs", "PlayAudio.vbs",
        "Plugins\AhiDriver\installer\使用说明.txt", "InstallReadme.txt")

    icoFileList := ["Wait.png", "BGKey.png", "IcoRunning.ico", "Joy.png", "DeltaMove.png", "KeyListen.png", "JoyListen.png", "SearchCombo.png", "Excel.png", "Time.png", "WaitConfirm.png", "RunPro.png",
        "Arr.png", "Condition.png", "Control.png", "FlowJump.png", "Extract.png", "False.png",
        "HttpRequest.png", "FileIO.png", "GreenColor.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Interval.png", "Key.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "RedColor.png", "Run.png", "Search.png",
        "SearchPro.png", "SearchAll.png", "MacroAction.png", "Target.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "WindowAdjustGear32.png", "YellowColor.png",
        "ZhiFuBao.png", "AiFaDian.png", "Stripe2.png", "Stripe5.png", "rabit.ico", "rabit.png", "Comment.png", "ScreenShot.png"]

    missingCritical := []
    missingOptional := []
    needIcoZip := false
    for localPath, assetName in criticalMap {
        fullPath := A_WorkingDir "\" localPath
        if (!FileExist(fullPath))
            missingCritical.Push([localPath, assetName])
    }
    for localPath, assetName in optionalMap {
        fullPath := A_WorkingDir "\" localPath
        if (!FileExist(fullPath))
            missingOptional.Push([localPath, assetName])
    }
    icoDir := A_WorkingDir "\Images\Soft"
    for fileName in icoFileList {
        if (!FileExist(icoDir "\" fileName)) {
            needIcoZip := true
            break
        }
    }

    allMissing := []
    for item in missingCritical
        allMissing.Push(item)
    for item in missingOptional
        allMissing.Push(item)
    if (needIcoZip)
        allMissing.Push(["Images\Soft\_ico_bundle", "ico.zip"])

    totalMissing := allMissing.Length
    if (totalMissing == 0) {
        RmtDialog.Info(GetLang("资源文件校验通过，未发现缺失文件"), GetLang("RMT 资源自检"), 64)
        return
    }

    fileListStr := ""
    showCount := Min(allMissing.Length, 5)
    loop showCount
        fileListStr .= "  · " allMissing[A_Index][2] "`n"
    if (allMissing.Length > 5)
        fileListStr .= "  ... 等 " allMissing.Length " 个文件"

    detailStr := ""
    if (missingCritical.Length > 0)
        detailStr .= "⚠ 关键文件 (" missingCritical.Length ")`n"
    if (missingOptional.Length > 0)
        detailStr .= "可选文件 (" missingOptional.Length ")"
    tipMsg := "检测到 " totalMissing " 个资源文件缺失`n" detailStr "`n`n" fileListStr "`n版本：" tag "`n点击【是】从 GitHub 自动下载`n点击【否】跳过（部分功能可能不可用）"

    btnStyle := missingCritical.Length > 0 ? (4 + 256 + 48) : (4 + 256 + 64)
    result := RmtDialog.Confirm(tipMsg, "RMT 资源自检")
    if (!result) {
        if (missingCritical.Length > 0) {
            criticalNames := ""
            for item in missingCritical
                criticalNames .= item[2] "`n"
            RmtDialog.Info("以下关键文件缺失，软件可能无法正常运行：`n`n" criticalNames "`n`n请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
        return
    }

    pg := RmtProgress(GetLang("RMT 资源下载"), GetLang("准备下载"), XamlWin.ActiveOwner(), GetLang("取消下载"))
    pg.Show()
    successCount := 0
    failList := []
    total := allMissing.Length

    try {
        for idx, item in allMissing {
            if (pg.Cancelled)
                break

            localPath := item[1]
            assetName := item[2]
            fullPath := A_WorkingDir "\" localPath
            downloadUrl := baseUrl assetName

            pg.Report("(" idx "/" total ") 正在下载：" assetName, 100 * (idx - 1) / total)

            downloaded := false

            if (assetName == "ico.zip") {
                zipPath := A_ScriptDir "\_rmt_temp_ico.zip"
                targetDir := A_WorkingDir "\Images\Soft"
                downloaded := DownloadAndUnzipIco(downloadUrl, zipPath, targetDir, icoFileList, pg)
                if (downloaded == "cancel")
                    break
            } else {
                SplitPath(fullPath, &outName, &outDir)
                if (outDir != "" && !DirExist(outDir))
                    DirCreate(outDir)
                if (FileExist(fullPath))
                    FileDelete(fullPath)

                result := DownloadAsync(downloadUrl, fullPath, 120, pg)
                if (result == "cancel")
                    break
                downloaded := (result == "ok")
            }

            if (downloaded)
                successCount++
            else
                failList.Push(assetName)
        }
    } finally pg.Close()
    ToolTip()

    if (pg.Cancelled) {
        stillCritical := false
        for item in missingCritical {
            fullPath := A_WorkingDir "\" item[1]
            if (!FileExist(fullPath)) {
                stillCritical := true
                break
            }
        }

        cancelMsg := "下载已取消。`n已成功下载 " successCount "/" total " 个文件。`n可再次点击「文件校验」继续下载。"
        if (stillCritical)
            cancelMsg .= "`n`n存在关键文件未下载完成，软件可能无法正常工作。`n`n请在QQ群 837661891 或者项目仓库寻求帮助"
        RmtDialog.Info(cancelMsg, "RMT 资源自检", 64)
        return
    }

    if (failList.Length > 0) {
        failStr := ""
        stillCritical := false
        for name in failList {
            failStr .= name "`n"
            for item in missingCritical {
                if (item[2] == name)
                    stillCritical := true
            }
        }
        iconType := stillCritical ? 16 : 48
        RmtDialog.Info("下载完成：成功 " successCount "/" total "`n`n以下文件下载失败（可能是网络问题）：`n" failStr, "RMT 资源自检", iconType)

        if (stillCritical) {
            RmtDialog.Info("存在关键文件下载失败，软件可能无法正常工作。`n`n请检查网络连接后重启软件重试。`n`n如仍无法解决，请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
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

DownloadAndUnzipIco(downloadUrl, zipPath, targetDir, expectedFiles, pg) {
    try {
        if (FileExist(zipPath))
            FileDelete(zipPath)

        SplitPath(targetDir, , &parentDir)
        if (parentDir && !DirExist(parentDir))
            DirCreate(parentDir)
        if !DirExist(targetDir)
            DirCreate(targetDir)

        pg.Report("正在下载: ico.zip", pg.percent)
        dlResult := DownloadAsync(downloadUrl, zipPath, 120, pg)
        if (dlResult != "ok")
            return dlResult == "cancel" ? "cancel" : false

        pg.Report("正在解压: ico.zip", pg.percent)
        shell := ComObject("Shell.Application")
        zipNamespace := shell.NameSpace(zipPath)
        destNamespace := shell.NameSpace(targetDir)
        if (!(zipNamespace && destNamespace)) {
            pg.Report("✗ Shell.NameSpace 获取失败", pg.percent)
            return false
        }
        destNamespace.CopyHere(zipNamespace.Items(), 16 | 4 | 1024)

        foundCount := 0
        lastFoundCount := 0
        stableCount := 0
        stableNeed := 5
        loop 120 {
            if (pg.Cancelled)
                return "cancel"
            foundCount := 0
            for fn in expectedFiles {
                if (FileExist(targetDir "\" fn))
                    foundCount++
            }
            pg.Report("已解压 " foundCount "/" expectedFiles.Length " 个文件", pg.percent)
            if (foundCount == lastFoundCount && foundCount > 0) {
                stableCount++
                if (stableCount >= stableNeed)
                    break
            } else {
                stableCount := 0
                lastFoundCount := foundCount
            }
            Sleep(500)
        }

        if (foundCount < expectedFiles.Length) {
            loop Files, targetDir "\*" "D" {
                if (A_LoopFileName == "." || A_LoopFileName == "..")
                    continue
                subDir := A_LoopFileFullPath
                subCount := 0
                for fn in expectedFiles {
                    if (FileExist(subDir "\" fn)) {
                        try FileMove(subDir "\" fn, targetDir "\" fn, 1)
                        if (FileExist(targetDir "\" fn))
                            subCount++
                    }
                }
                if (subCount > 0) {
                    foundCount := 0
                    for fn in expectedFiles {
                        if (FileExist(targetDir "\" fn))
                            foundCount++
                    }
                    break
                }
            }
        }

        try FileDelete(zipPath)
        return foundCount == expectedFiles.Length
    } catch as e {
        pg.Report("✗ 异常: " e.Message, pg.percent)
        try FileDelete(zipPath)
        return false
    }
}
