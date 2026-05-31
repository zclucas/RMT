#Requires AutoHotkey v2.0

SelfCheckMissingFiles() {
    static _done := false
    if (_done)
        return
    _done := true

    version := RegExReplace(RMT_VERSION, "^(\d+\.\d+).*", "$1")
    arch := A_PtrSize == 8 ? "x64" : "x86"
    bitArch := A_PtrSize == 8 ? "64bit" : "32bit"
    tag := "v" version "_" arch
    baseUrl := "https://gh-proxy.com/https://github.com/zclucas/RMTAssets/releases/download/" tag "/"

    criticalMap := Map(
        "Plugins\RMT\RMT.dll", "RMT.dll",
        "Plugins\IbInputSimulator.dll", "IbInputSimulator.dll",
        "Audio\Start.wav", "Start.wav",
        "Audio\End.wav", "End.wav",
        "Plugins\ViGEm\ViGEmWrapper.dll", "ViGEmWrapper.dll",
        "Joy\ViGEmBus.exe", "ViGEmBus.exe",
        "Joy\Ori.png", "Ori.png",
        "Joy\Xbox按键映射.png", "Xbox.png",
        "Plugins\AHK-XAML\lib\ahk-xaml.dll", "ahk-xaml.dll",
        "Plugins\AHK-XAML\lib\WpfAnimatedGif.dll", "WpfAnimatedGif.dll",
        "Plugins\OpenCV\" arch "\RMT_OpenCV.dll", "RMT_OpenCV.dll",
        "Plugins\OpenCV\" arch "\opencv_world481.dll", "opencv_world481.dll",
        "Plugins\RapidOcr\" bitArch "\RapidOcrOnnx.dll", "RapidOcrOnnx.dll",
        "Plugins\ScreenCapture\ScreenCapture.exe", "ScreenCapture.exe",
        "Plugins\RapidOcr\ch_models\ch_PP-OCRv4_det_infer.onnx", "ch_PP-OCRv4_det_infer.onnx",
        "Plugins\RapidOcr\ch_models\ch_PP-OCRv4_rec_infer.onnx", "ch_PP-OCRv4_rec_infer.onnx",
        "Plugins\RapidOcr\ch_models\ppocr_keys_v1.txt", "ppocr_keys_v1.txt",
        "Plugins\RapidOcr\en_models\en_PP-OCRv3_det_infer.onnx", "en_PP-OCRv3_det_infer.onnx",
        "Plugins\RapidOcr\en_models\en_PP-OCRv4_rec_infer.onnx", "en_PP-OCRv4_rec_infer.onnx",
        "Plugins\RapidOcr\en_models\ppocr_keys_v1.txt", "ppocr_keys_v1_en.txt",
        "Lang\中文.txt", "chinese.txt",
        "Lang\English.txt", "English.txt",
        "Thread\Work.exe", "Work.exe",
        "index.html", "index.html")

    optionalMap := Map(
        "MinTool\PlayAudio.vbs", "PlayAudio.vbs",
        "MinTool\CountDown.exe", "CountDown.exe")

    icoFileList := ["Arr.png", "Condition.png", "Control.png", "Extract.png", "False.png",
        "FileIO.png", "GreenColor.png", "IcoPause.ico", "If.png", "IfPro.png",
        "Input.png", "Interval.png", "Key.png", "KeyCheck.png", "Loop.png",
        "LoopBody.png", "LoopCount.png", "Mouse.png", "Move.png", "MovePro.png",
        "Operation.png", "Output.png", "RedColor.png", "Run.png", "Search.png",
        "SearchPro.png", "Sub.png", "Target.png", "TextOps.png", "True.png",
        "Var.png", "WeiXin.png", "WindowManage.png", "YellowColor.png",
        "ZhiFuBao.png", "rabit.ico", "rabit.png"]

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
    if (totalMissing == 0)
        return

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
    result := MsgBox(tipMsg, "RMT 资源自检", btnStyle)
    if (result != "Yes") {
        if (missingCritical.Length > 0) {
            criticalNames := ""
            for item in missingCritical
                criticalNames .= item[2] "`n"
            MsgBox("以下关键文件缺失，软件可能无法正常运行：`n`n" criticalNames "`n`n请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
        return
    }

    pg := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox -MaximizeBox", "RMT 资源下载")
    pg.SetFont("s10")
    pg.AddText("xm y+8 w380 h28 vStatusText", "准备下载...")
    pg.AddProgress("xm w380 h20 vProgressBar Range0-" totalMissing)
    pg.SetFont("s9")
    pg.AddText("xm y+6 w380 h22 vDetailText", "")
    btnCancel := pg.AddButton("xm y+12 w100 h30", "取消下载")

    global _dlCancelled := false
    btnCancel.OnEvent("Click", (*) => (_dlCancelled := true))

    pg.Show("AutoSize Center")

    successCount := 0
    failList := []
    total := allMissing.Length

    for idx, item in allMissing {
        if (_dlCancelled)
            break

        localPath := item[1]
        assetName := item[2]
        fullPath := A_WorkingDir "\" localPath
        downloadUrl := baseUrl assetName

        pg["StatusText"].Value := "(" idx "/" total ") 正在下载：" assetName
        pg["DetailText"].Value := ""
        pg["ProgressBar"].Value := idx - 1

        downloaded := false

        if (assetName == "ico.zip") {
            zipPath := A_ScriptDir "\_rmt_temp_ico.zip"
            targetDir := A_WorkingDir "\Images\Soft"
            downloaded := DownloadAndUnzipIco(downloadUrl, zipPath, targetDir, icoFileList, &pg)
            if (downloaded == "cancel")
                break
        } else {
            SplitPath(fullPath, &outName, &outDir)
            if (outDir != "" && !DirExist(outDir))
                DirCreate(outDir)
            if (FileExist(fullPath))
                FileDelete(fullPath)

            result := DownloadAsync(downloadUrl, fullPath, 120, &pg)
            if (result == "cancel")
                break
            downloaded := (result == "ok")
        }

        if (downloaded) {
            successCount++
            pg["DetailText"].Value := "✓ 下载完成"
        } else {
            failList.Push(assetName)
            pg["DetailText"].Value := "✗ 下载失败"
        }

        pg["ProgressBar"].Value := idx
    }

    pg.Destroy()
    ToolTip()

    if (_dlCancelled) {
        stillCritical := false
        for item in missingCritical {
            fullPath := A_WorkingDir "\" item[1]
            if (!FileExist(fullPath)) {
                stillCritical := true
                break
            }
        }

        cancelMsg := "下载已取消。`n已成功下载 " successCount "/" total " 个文件。`n剩余文件将在下次启动时继续下载。"
        if (stillCritical)
            cancelMsg .= "`n`n存在关键文件未下载完成，软件可能无法正常工作。`n`n请在QQ群 837661891 或者项目仓库寻求帮助"
        MsgBox(cancelMsg, "RMT 资源自检", 64)
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
        MsgBox("下载完成：成功 " successCount "/" total "`n`n以下文件下载失败（可能是网络问题）：`n" failStr, "RMT 资源自检", iconType)

        if (stillCritical) {
            MsgBox("存在关键文件下载失败，软件可能无法正常工作。`n`n请检查网络连接后重启软件重试。`n`n如仍无法解决，请在QQ群 837661891 或者项目仓库寻求帮助", "RMT 警告", 16)
        }
    }
}

DownloadAsync(url, savePath, timeoutSec, &pgGui) {
    maxRetry := 3
    Loop maxRetry {
        if (_dlCancelled)
            return "cancel"

        if (A_Index > 1)
            pgGui["DetailText"].Value := Format("重试 ({}/{})...", A_Index - 1, maxRetry - 1)

        result := DownloadOnce(url, savePath, timeoutSec, &pgGui)
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

DownloadOnce(url, savePath, timeoutSec, &pgGui) {
    try {
        req := ComObject("Msxml2.XMLHTTP")
        req.open("GET", url, true)
        req.send()

        startTime := A_TickCount
        Loop {
            if (_dlCancelled)
                return "cancel"

            if (req.readyState == 4)
                break

            elapsed := (A_TickCount - startTime) / 1000
            if (elapsed > timeoutSec)
                return "timeout"

            pgGui["DetailText"].Value := "下载中... (" Round(elapsed, 1) "s)"
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
        pgGui["DetailText"].Value := "✗ 下载异常: " e.Message
        return "fail"
    }
}

DownloadAndUnzipIco(downloadUrl, zipPath, targetDir, expectedFiles, &pgGui) {
    try {
        if (FileExist(zipPath))
            FileDelete(zipPath)

        SplitPath(targetDir, , &parentDir)
        if (parentDir && !DirExist(parentDir))
            DirCreate(parentDir)
        if !DirExist(targetDir)
            DirCreate(targetDir)

        pgGui["StatusText"].Value := "正在下载: ico.zip"
        dlResult := DownloadAsync(downloadUrl, zipPath, 120, &pgGui)
        if (dlResult != "ok")
            return dlResult == "cancel" ? "cancel" : false

        pgGui["StatusText"].Value := "正在解压: ico.zip"
        pgGui["DetailText"].Value := ""

        shell := ComObject("Shell.Application")
        zipNamespace := shell.NameSpace(zipPath)
        destNamespace := shell.NameSpace(targetDir)
        if (!(zipNamespace && destNamespace)) {
            pgGui["DetailText"].Value := "✗ Shell.NameSpace 获取失败"
            return false
        }
        destNamespace.CopyHere(zipNamespace.Items(), 16 | 4 | 1024)

        foundCount := 0
        lastFoundCount := 0
        stableCount := 0
        stableNeed := 5
        loop 120 {
            if (_dlCancelled)
                return "cancel"
            foundCount := 0
            for fn in expectedFiles {
                if (FileExist(targetDir "\" fn))
                    foundCount++
            }
            pgGui["DetailText"].Value := "已解压 " foundCount "/" expectedFiles.Length " 个文件"
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
        pgGui["DetailText"].Value := "✗ 异常: " e.Message
        try FileDelete(zipPath)
        return false
    }
}
