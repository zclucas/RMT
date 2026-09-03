#Requires AutoHotkey v2.0
#Include XInput.ahk

; ================= ViGEmBus 驱动安装检测 =================

; 是否已安装 ViGEmBus 驱动（Nefarius 虚拟手柄总线驱动）
IsViGEmInstalled() {
    ; 判断驱动是否真正可用。
    ; 卸载驱动后服务注册表项与 ImagePath 都可能残留（SCM 会把服务标记为「待删除」），
    ; 仅靠 RegRead(ImagePath) 或 FileExist(.sys) 都会误判为「已安装」。
    ; 关键信号：卸载时 SCM 会写入 DeleteFlag=1；同时 .sys 文件会被真正删除。

    ; 1) 若服务已被 SCM 标记删除（DeleteFlag 非 0），则驱动不可用
    try {
        deleteFlag := RegRead("HKLM\SYSTEM\CurrentControlSet\Services\ViGEmBus", "DeleteFlag")
        if (deleteFlag != 0) {
            JoyDebugLog(Format("IsViGEmInstalled -> false (服务已标记删除 DeleteFlag={})", deleteFlag), "vigeminstall")
            return false
        }
    } catch {
        ; DeleteFlag 不存在，继续判断 ImagePath
    }

    ; 2) 服务项必须存在，且驱动文件真实存在于 System32\drivers
    try {
        imgPath := RegRead("HKLM\SYSTEM\CurrentControlSet\Services\ViGEmBus", "ImagePath")
        ; 32 位进程访问 System32 会被 WOW64 重定向到 SysWOW64，需改用 Sysnative
        sysFile := A_WinDir "\System32\drivers\ViGEmBus.sys"
        if (A_PtrSize = 4 && FileExist(A_WinDir "\Sysnative"))
            sysFile := A_WinDir "\Sysnative\drivers\ViGEmBus.sys"
        if (!FileExist(sysFile)) {
            JoyDebugLog(Format("IsViGEmInstalled -> false (驱动文件不存在 '{}')", sysFile), "vigeminstall")
            return false
        }
        JoyDebugLog(Format("IsViGEmInstalled -> true ImagePath='{}'", imgPath), "vigeminstall")
        return true
    } catch as e {
        JoyDebugLog(Format("IsViGEmInstalled -> false ({})", e.Message), "vigeminstall")
        return false
    }
}

; 未安装 ViGEmBus 时提示；返回 true 表示用户点了「安装」并已启动安装程序
ShowViGEmInstallTip() {
    exePath := A_WorkingDir "\Joy\ViGEmBus.exe"
    JoyDebugLog(Format("ShowViGEmInstallTip enter exePath='{}' exists={}", exePath, FileExist(exePath)), "vigeminstall")
    if (!FileExist(exePath)) {
        MsgBox(GetLang("未找到 ViGEm 驱动安装程序") "`n" exePath, GetLang("提示"), 48)
        return false
    }

    chosen := ""
    tipText := GetLang("手柄功能需要使用 ViGEmBus 驱动，是否现在安装？")

    g := Gui("+AlwaysOnTop -MinimizeBox", GetLang("提示"))
    try
        g.SetFont("S10 W550 Q2", MainSoftData.FontType)
    catch
        g.SetFont("S10")
    g.Add("Text", "x20 y18 w340 h48", tipText)
    btnInstall := g.Add("Button", "x20 y78 w150 h30 Default", GetLang("安装"))
    btnCancel := g.Add("Button", "x190 y78 w150 h30", GetLang("取消"))
    btnInstall.OnEvent("Click", (*) => (chosen := "install", g.Destroy()))
    btnCancel.OnEvent("Click", (*) => (chosen := "cancel", g.Destroy()))
    g.OnEvent("Close", (*) => (chosen := "cancel", g.Destroy()))
    g.Show("w380 h125 Center")
    hwnd := g.Hwnd
    WinWaitClose("ahk_id " hwnd)

    if (chosen != "install")
        return false

    Run(exePath)
    return true
}

class ViGEmWrapper {
    static asm := 0
    static client := 0

    static Init() {
        if (this.client == 0) {
            ; dllPath := A_ScriptDir "\ViGEmWrapper.dll"
            dllPath := ViGEmDllPath

            if !FileExist(dllPath) {
                MsgBox "No se encuentra ViGEmWrapper.dll en:`n" dllPath, "Error", 16
                ExitApp
            }

            try {
                this.asm := CLR_LoadLibrary(dllPath)
            } catch as err {
                MsgBox "Error al cargar ViGEmWrapper.dll:`n" err.Message, "Error de carga", 16
                ExitApp
            }

            ; Chequeo relajado: solo verifica que no sea vacío/0
            if !this.asm {
                MsgBox "CLR_LoadLibrary devolvió vacío. Verifica dependencias (ViGEmClient.dll).", "Error", 16
                ExitApp
            }

            ; Opcional: MsgBox temporal para confirmar
            ; MsgBox "¡Cargado OK! Tipo: " Type(this.asm), "Éxito", 64

            this.client := 1
        }
    }

    static CreateInstance(cls) {
        if !this.asm {
            throw Error("ViGEmWrapper no inicializado")
        }
        try {
            return this.asm.CreateInstance_2(cls, true)  ; Usa _2 para v2 compat
        } catch as err {
            ; MsgBox "Fallo al crear instancia de " cls ":`n" err.Message, "Error", 16
            ; ExitApp
            str1 := GetLang("ViGEm创建实例失败,手柄功能无法生效")
            str2 := GetLang("请先安装Joy目录下ViGEmBus.exe后运行软件")
            MsgBox(Format("{}`n{}", str1, str2))
        }
    }
}

class ViGEmTarget {
    helperClass := ""

    __New() {
        ViGEmWrapper.Init()
        this.Instance := ViGEmWrapper.CreateInstance(this.helperClass)

        ; Chequeo suave para evitar crash si falla OkCheck
        try {
            if (this.Instance.OkCheck() != "OK") {
                MsgBox "ViGEmWrapper.dll falló en OkCheck().`nPosible problema con el driver ViGEmBus o dependencias.",
                    "Error de inicialización", 16
                ExitApp
            }
        } catch {
            ; MsgBox "No se pudo llamar a OkCheck(). El DLL cargó pero parece incompatible.", "Error OkCheck", 16
            ; ExitApp
        }
    }

    SendReport() {
        this.Instance.SendReport()
    }
}

; ────────────────────────────────────────────────
; El resto del archivo (ViGEmDS4, ViGEmXb360 y todas las clases internas)
; déjalo exactamente igual a como lo tenías antes
; ────────────────────────────────────────────────
; ... (pega aquí ViGEmDS4, ViGEmXb360, _ButtonHelper, etc.)
; DS4 (DualShock 4 for Playstation 4)
class ViGEmDS4 extends ViGEmTarget {
    helperClass := "ViGEmWrapper.Ds4"

    __New() {
        static buttons := Map("Square", 16, "Cross", 32, "Circle", 64, "Triangle", 128, "L1", 256, "R1", 512, "L2",
            1024, "R2", 2048,
            "Share", 4096, "Options", 8192, "LS", 16384, "RS", 32768)
        static specialButtons := Map("Ps", 1, "TouchPad", 2)
        static axes := Map("LX", 2, "LY", 3, "RX", 4, "RY", 5, "LT", 0, "RT", 1)

        this.Buttons := Map()
        for name, id in buttons {
            this.Buttons[name] := ViGEmDS4._ButtonHelper(this, id)
        }
        for name, id in specialButtons {
            this.Buttons[name] := ViGEmDS4._SpecialButtonHelper(this, id)
        }

        this.Axes := Map()
        for name, id in axes {
            this.Axes[name] := ViGEmDS4._AxisHelper(this, id)
        }

        this.Dpad := ViGEmDS4._DpadHelper(this)
        super.__New()
    }

    class _ButtonHelper {
        __New(parent, id) {
            this._Parent := parent
            this._Id := id
        }

        SetState(state) {
            this._Parent.Instance.SetButtonState(this._Id, state)
            this._Parent.Instance.SendReport()
            return this._Parent
        }
    }

    class _SpecialButtonHelper {
        __New(parent, id) {
            this._Parent := parent
            this._Id := id
        }

        SetState(state) {
            this._Parent.Instance.SetSpecialButtonState(this._Id, state)
            this._Parent.Instance.SendReport()
            return this._Parent
        }
    }

    class _AxisHelper {
        __New(parent, id) {
            this._Parent := parent
            this._Id := id
        }

        SetState(state) {
            local converted
            ; 扳机（ID 0=LT / 1=RT）用 0-255 直接量；摇杆（ID 2-5）走 ConvertAxis（0-100 → 0-255，中心 128）
            if (this._Id = 0 || this._Id = 1) {
                converted := Round(state)
                if (converted < 0)
                    converted := 0
                if (converted > 255)
                    converted := 255
            } else {
                converted := this.ConvertAxis(state)
            }
            this._Parent.Instance.SetAxisState(this._Id, converted)
            this._Parent.Instance.SendReport()
            return this._Parent
        }

        ConvertAxis(state) {
            return Round(state * 2.55)
        }
    }

    class _DpadHelper {
        __New(parent) {
            this._Parent := parent
            this._Id := 0
        }

        SetState(state) {
            static dPadDirections := Map("Up", 0, "UpRight", 1, "Right", 2, "DownRight", 3, "Down", 4, "DownLeft", 5,
                "Left", 6, "UpLeft", 7, "None", 8)
            this._Parent.Instance.SetDpadState(dPadDirections[state])
            this._Parent.Instance.SendReport()
            return this._Parent
        }
    }
}

; Xb360
class ViGEmXb360 extends ViGEmTarget {
    helperClass := "ViGEmWrapper.Xb360"

    __New() {
        static buttons := Map("A", 4096, "B", 8192, "X", 16384, "Y", 32768, "LB", 256, "RB", 512, "LS", 64, "RS", 128,
            "Back", 32, "Start", 16, "Xbox", 1024)
        static axes := Map("LX", 2, "LY", 3, "RX", 4, "RY", 5, "LT", 0, "RT", 1)

        this.Buttons := Map()
        for name, id in buttons {
            this.Buttons[name] := ViGEmXb360._ButtonHelper(this, id)
        }

        this.Axes := Map()
        for name, id in axes {
            this.Axes[name] := ViGEmXb360._AxisHelper(this, id)
        }

        this.Dpad := ViGEmXb360._DpadHelper(this)

        super.__New()
    }

    class _ButtonHelper {
        __New(parent, id) {
            this._Parent := parent
            this._Id := id
        }

        SetState(state) {
            this._Parent.Instance.SetButtonState(this._Id, state)
            this._Parent.Instance.SendReport()
            return this._Parent
        }
    }

    class _AxisHelper {
        __New(parent, id) {
            this._Parent := parent
            this._Id := id
        }

        SetState(state) {
            local converted

            ; Detectar si es trigger (IDs 0 = LT, 1 = RT)
            if (this._Id = 0 || this._Id = 1) {
                ; Gatillos: rango directo 0-255
                converted := Round(state)           ; si state es 0-100 o 0-255
                if (converted < 0)
                    converted := 0
                if (converted > 255)
                    converted := 255
            } else {
                ; Sticks: rango -32768 a 32767
                converted := Round((state * 655.36) - 32768)
                if (converted == 32768)
                    converted := 32767
            }

            this._Parent.Instance.SetAxisState(this._Id, converted)
            this._Parent.Instance.SendReport()
        }
    }

    class _DpadHelper {
        _DpadStates := Map(1, 0, 8, 0, 2, 0, 4, 0)

        __New(parent) {
            this._Parent := parent
        }

        SetState(state) {
            static dpadDirections := Map(
                "None", Map(1, 0, 8, 0, 2, 0, 4, 0),
                "Up", Map(1, 1, 8, 0, 2, 0, 4, 0),
                "UpRight", Map(1, 1, 8, 1, 2, 0, 4, 0),
                "Right", Map(1, 0, 8, 1, 2, 0, 4, 0),
                "DownRight", Map(1, 0, 8, 1, 2, 1, 4, 0),
                "Down", Map(1, 0, 8, 0, 2, 1, 4, 0),
                "DownLeft", Map(1, 0, 8, 0, 2, 1, 4, 1),
                "Left", Map(1, 0, 8, 0, 2, 0, 4, 1),
                "UpLeft", Map(1, 1, 8, 0, 2, 0, 4, 1)
            )
            newStates := dpadDirections[state]
            for id, newState in newStates {
                oldState := this._DpadStates[id]
                if (oldState != newState) {
                    this._DpadStates[id] := newState
                    this._Parent.Instance.SetButtonState(id, newState)
                }
                this._Parent.SendReport()
            }
        }
    }
}
