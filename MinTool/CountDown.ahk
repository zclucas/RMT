#Requires AutoHotkey v2.0
#SingleInstance Force

; ================= CONFIG FILE =================
cfgFile := A_ScriptDir "\config.ini"

; ================= DEFAULTS =================
default := Map(
    "posX", "200",
    "posY", "200",
    "fontSize", "32",
    "textColor", "00FF00",
    "bg", "000000",
    "alpha", "180"
)

; ================= LOAD CONFIG =================
cfg := LoadConfig()

posX := Integer(cfg["posX"])
posY := Integer(cfg["posY"])
fontSize := Integer(cfg["fontSize"])
textColor := cfg["textColor"]
bg := cfg["bg"]
alpha := Integer(cfg["alpha"])

displayType := ""

; ================= MODE SWITCH =================
if (A_Args.Length > 0) {
    ; ========== TIMER MODE ==========
    total := Integer(A_Args[1])
    remaining := total

    InitTimerUI()
    Update()
    SetTimer(Update, 1000)

} else {
    ; ========== CONFIG MODE ==========
    ShowConfigUI()
}

; =========================================================
; ================ TIMER UI ================================
; =========================================================
InitTimerUI() {
    global displayType, myGui, txt, width, height
    global bg, fontSize, textColor, alpha, posX, posY, total, remaining

    if (total >= 86400) {
        displayType := "ddhhmmss"
        width := 260, height := 50
    } else if (total >= 3600) {
        displayType := "hhmmss"
        width := 200, height := 50
    } else if (total >= 60) {
        displayType := "mmss"
        width := 130, height := 50
    } else {
        displayType := "ss"
        width := 70, height := 50
    }

    myGui := Gui()
    myGui.Opt("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    myGui.BackColor := bg
    myGui.SetFont("s" fontSize " c" textColor, "Consolas")

    txt := myGui.AddText("x0 y0 w" width " h" height " Center", "")

    WinSetTransparent(alpha, myGui.Hwnd)
    A_IconHidden := 1   ;0(可见) 和 1(隐藏)
    myGui.Show("x" posX " y" posY " w" width " h" height)
}

Update() {
    global remaining, txt, displayType

    if (remaining < 0)
        ExitApp()

    txt.Text := FormatTime(remaining, displayType)
    remaining--
}

FormatTime(sec, mode) {
    h := Floor(sec / 3600)
    m := Floor(Mod(sec, 3600) / 60)
    s := Mod(sec, 60)

    switch mode {
        case "ddhhmmss":
            d := Floor(sec / 86400)
            h := Floor(Mod(sec, 86400) / 3600)
            m := Floor(Mod(sec, 3600) / 60)
            s := Mod(sec, 60)
            return Format("{:02}:{:02}:{:02}:{:02}", d, h, m, s)

        case "hhmmss":
            return Format("{:02}:{:02}:{:02}", h, m, s)

        case "mmss":
            return Format("{:02}:{:02}", Floor(sec / 60), Mod(sec, 60))

        case "ss":
            return sec
    }
}

; =========================================================
; ================ CONFIG UI ===============================
; =========================================================
ShowConfigUI() {
    global cfg, cfgFile, default

    g := Gui()
    g.Title := "倒计时配置"

    g.AddText("w200", "位置 X")
    xEdit := g.AddEdit("w200", cfg["posX"])

    g.AddText("w200", "位置 Y")
    yEdit := g.AddEdit("w200", cfg["posY"])

    g.AddText("w200", "字体大小")
    fontEdit := g.AddEdit("w200", cfg["fontSize"])

    g.AddText("w200", "文字颜色 (HEX)")
    textColorEdit := g.AddEdit("w200", cfg["textColor"])

    g.AddText("w200", "背景颜色 (HEX)")
    bgEdit := g.AddEdit("w200", cfg["bg"])

    g.AddText("w200", "透明度 (0-255)")
    alphaEdit := g.AddEdit("w200", cfg["alpha"])

    saveBtn := g.AddButton("w200", "保存")
    resetBtn := g.AddButton("w200", "重置默认")

    saveBtn.OnEvent("Click", (*) => SaveConfig(
        xEdit.Value,
        yEdit.Value,
        fontEdit.Value,
        textColorEdit.Value,
        bgEdit.Value,
        alphaEdit.Value,
        g
    ))

    resetBtn.OnEvent("Click", (*) => ResetConfig(g))

    g.Show()
}

SaveConfig(x, y, font, textColor, bg, alpha, guiObj) {
    global cfgFile

    IniWrite x, cfgFile, "ui", "posX"
    IniWrite y, cfgFile, "ui", "posY"
    IniWrite font, cfgFile, "ui", "fontSize"
    IniWrite textColor, cfgFile, "ui", "textColor"
    IniWrite bg, cfgFile, "ui", "bg"
    IniWrite alpha, cfgFile, "ui", "alpha"

    guiObj.Destroy()
    MsgBox "已保存配置"
}

ResetConfig(guiObj) {
    global cfgFile, default

    for k, v in default
        IniWrite v, cfgFile, "ui", k

    guiObj.Destroy()
    MsgBox "已重置为默认配置"
}

; =========================================================
; ================ CONFIG LOAD =============================
; =========================================================
LoadConfig() {
    global cfgFile, default

    cfg := Map()

    for k, v in default {
        try {
            val := IniRead(cfgFile, "ui", k)
            cfg[k] := val
        } catch {
            cfg[k] := v
        }
    }
    return cfg
}