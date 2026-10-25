#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\Main\Util\CryptoUtil.ahk

; 分享包加解密回归用例（纯计算，不弹窗、不写配置）
; 跑法：AutoHotkey.exe Test\CryptoRoundTripTest.ahk
; 结果一次性写入 Log\CryptoRoundTripTest.log，无控制台也能回读
;
; 注意：脚本内不要往 stdout 写（FileAppend 到 "*"）：无控制台时句柄无效会抛错弹窗

SetWorkingDir(A_ScriptDir "\..")
LOGFILE := A_ScriptDir "\..\Log\CryptoRoundTripTest.log"
OUTTXT := ""

; 未捕获错误也进日志，绝不弹窗
OnError(OnErr)
OnErr(e, mode) {
    global OUTTXT, LOGFILE
    OUTTXT .= "[OnError] " e.Message "`n" e.Stack "`n"
    FileAppend(OUTTXT, LOGFILE, "UTF-8")
    return true
}

Check(ok, message) {
    global OUTTXT
    if (!ok) {
        OUTTXT .= "FAIL " message "`n"
        throw Error(message)
    }
    OUTTXT .= "PASS " message "`n"
}

try {
    plain := Buffer(1000)
    loop 1000
        NumPut("uchar", Mod(A_Index * 7, 256), plain, A_Index - 1)

    sealed := RMTC_SealBuffer(plain, "abc123")
    Check(sealed.Size == 42 + 1008 + 32, "包体长度 = 头42 + 密文1008 + MAC32")
    Check(StrGet(sealed, 4, "cp0") == "RMTC", "包体带 RMTC 魔数")

    opened := RMTC_OpenBuffer(sealed, "abc123")
    Check(opened.Size == plain.Size, "解密长度与原文一致")
    same := true
    loop plain.Size {
        if (NumGet(opened, A_Index - 1, "uchar") != NumGet(plain, A_Index - 1, "uchar")) {
            same := false
            break
        }
    }
    Check(same, "往返内容逐字节一致")

    wrong := ""
    try
        RMTC_OpenBuffer(sealed, "abc124")
    catch as e
        wrong := e.Message
    Check(wrong != "", "错误密码被拒绝")

    tampered := Buffer(sealed.Size)
    DllCall("RtlMoveMemory", "ptr", tampered.Ptr, "ptr", sealed.Ptr, "uint", sealed.Size)
    NumPut("uchar", NumGet(tampered, 100, "uchar") ^ 0xFF, tampered, 100)
    bad := ""
    try
        RMTC_OpenBuffer(tampered, "abc123")
    catch as e
        bad := e.Message
    Check(bad != "", "篡改密文被拒绝（先验 MAC）")

    Check(RMTC_SealBuffer(plain, "") == plain, "空密码原样返回（不加密导出）")

    pkg := A_Temp "\rmt_crypto_probe.rmt"
    try FileDelete(pkg)
    f := FileOpen(pkg, "w")
    f.RawWrite(sealed, sealed.Size)
    f.Close()
    Check(RMTC_IsEncryptedFile(pkg), "落盘后能识别出加密包")
    FileDelete(pkg)

    big := Buffer(2000000, 0x5A)
    Check(RMTC_OpenBuffer(RMTC_SealBuffer(big, "pass-2MB"), "pass-2MB").Size == big.Size, "2MB 包往返正常")

    OUTTXT .= "ALL PASS`n"
} catch as e {
    OUTTXT .= "ABORT " e.Message "`n" e.Stack "`n"
}
FileAppend OUTTXT, LOGFILE, "UTF-8"
ExitApp