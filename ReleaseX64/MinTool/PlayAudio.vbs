Option Explicit

Dim audioFile, player, fso
Set fso = CreateObject("Scripting.FileSystemObject")
audioFile = WScript.Arguments(0)

If fso.FileExists(audioFile) Then
    Set player = CreateObject("WMPlayer.OCX")
    player.settings.autoStart = True
    player.settings.volume = 80
    player.settings.setMode "loop", False  ' 不循环播放
    player.uiMode = "none"  ' 不显示界面
    player.URL = audioFile  ' 加载音频
    
    ' 等待播放完成
    Do While player.playState <> 1  ' 1 = 停止状态
        WScript.Sleep(1000)
    Loop
    
    ' 播放完成后自动退出
    Set player = Nothing
    WScript.Quit(0)
End If