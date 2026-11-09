#Requires AutoHotkey v2.0

; VIIPER localhost TCP API. 每个进程独占总线，绝不复用其他程序的设备。
; 协议参考：https://github.com/Alia5/VIIPER/tree/main/docs/api
class ViiperInput {
    static Bus := 0
    static Streams := Map()
    static Keys := Map()
    static Buttons := 0
    static Started := false

    static Connect() {
        if (!this.Started) {
            if DllCall("Ws2_32\WSAStartup", "UShort", 0x202, "Ptr", Buffer(512), "Int")
                throw Error("VIIPER: Winsock 初始化失败")
            this.Started := true
            OnExit((*) => this.Close())
        }
        s := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if (s == -1)
            throw Error("VIIPER: 无法创建连接")
        try {
            ; 只连接环回地址；非阻塞 connect + select 限制连接等待。
            flag := Buffer(4, 0), NumPut("UInt", 1, flag)
            DllCall("Ws2_32\ioctlsocket", "Ptr", s, "UInt", 0x8004667E, "Ptr", flag)
            addr := Buffer(16, 0)
            NumPut("UShort", 2, addr)
            NumPut("UShort", DllCall("Ws2_32\htons", "UShort", 3242, "UShort"), addr, 2)
            NumPut("UInt", 0x0100007F, addr, 4)
            rc := DllCall("Ws2_32\connect", "Ptr", s, "Ptr", addr, "Int", 16, "Int")
            if (rc && DllCall("Ws2_32\WSAGetLastError") != 10035)
                throw Error("VIIPER: 连接失败")
            fd := Buffer(A_PtrSize * 2, 0), tv := Buffer(8, 0)
            NumPut("UInt", 1, fd), NumPut("Ptr", s, fd, A_PtrSize)
            NumPut("Int", 1, tv)
            if (DllCall("Ws2_32\select", "Int", 0, "Ptr", 0, "Ptr", fd, "Ptr", 0, "Ptr", tv, "Int") != 1)
                throw Error("VIIPER: 本机服务未启动（127.0.0.1:3242）")
            opt := Buffer(4, 0), len := Buffer(4, 0), NumPut("Int", 4, len)
            if DllCall("Ws2_32\getsockopt", "Ptr", s, "Int", 0xFFFF, "Int", 0x1007, "Ptr", opt, "Ptr", len)
                throw Error("VIIPER: 读取连接状态失败")
            if NumGet(opt, 0, "Int")
                throw Error("VIIPER: 连接被拒绝")
            NumPut("UInt", 0, flag)
            DllCall("Ws2_32\ioctlsocket", "Ptr", s, "UInt", 0x8004667E, "Ptr", flag)
            NumPut("Int", 1500, opt)
            for option in [0x1005, 0x1006]
                DllCall("Ws2_32\setsockopt", "Ptr", s, "Int", 0xFFFF, "Int", option, "Ptr", opt, "Int", 4)
            NumPut("Int", 1, opt)
            DllCall("Ws2_32\setsockopt", "Ptr", s, "Int", 6, "Int", 1, "Ptr", opt, "Int", 4)
            return s
        } catch as err {
            DllCall("Ws2_32\closesocket", "Ptr", s)
            throw Error(err.Message "`n请安装 usbip-win2，并运行 viiper server；参见 Plugins\VIIPER\README.md。")
        }
    }

    static Write(s, data) {
        pos := 0
        while (pos < data.Size) {
            n := DllCall("Ws2_32\send", "Ptr", s, "Ptr", data.Ptr + pos, "Int", data.Size - pos, "Int", 0, "Int")
            if (n <= 0)
                throw Error("VIIPER: 发送失败，请检查本机服务并重新运行宏")
            pos += n
        }
    }

    static Text(s, command) {
        data := Buffer(StrPut(command, "UTF-8"), 0)
        StrPut(command, data, "UTF-8")
        this.Write(s, data)
    }

    static Request(command) {
        s := this.Connect()
        try {
            ; add 会同步等待 USBIP 挂载，首次枚举可能超过普通输入的超时。
            timeout := Buffer(4, 0)
            NumPut("UInt", InStr(command, "/add ") ? 15000 : 1500, timeout)
            DllCall("Ws2_32\setsockopt", "Ptr", s, "Int", 0xFFFF, "Int", 0x1006, "Ptr", timeout, "Int", 4)
            this.Text(s, command)
            data := Buffer(65536, 0), pos := 0
            ; 按字节收取管理应答，避免吞掉分隔符之后的数据。
            loop 65535 {
                n := DllCall("Ws2_32\recv", "Ptr", s, "Ptr", data.Ptr + pos, "Int", 1, "Int", 0, "Int")
                if (n < 0 || (n == 0 && pos == 0))
                    throw Error("VIIPER: 服务未返回有效应答")
                ; 官方服务的请求以 NUL 结尾，应答是 JSON + LF 后关闭连接。
                ; 同时接受 NUL/EOF，兼容旧测试服务和不同版本。
                if (n == 0 || NumGet(data, pos, "UChar") == 0 || NumGet(data, pos, "UChar") == 10) {
                    reply := JSON.parse(StrGet(data, pos, "UTF-8"))
                    if (reply.Has("status"))
                        throw Error("VIIPER: " (reply.Has("detail") ? reply["detail"] : reply["status"]))
                    return reply
                }
                pos += 1
            }
            throw Error("VIIPER: 应答过长")
        } finally DllCall("Ws2_32\closesocket", "Ptr", s)
    }

    static Stream(kind) {
        if this.Streams.Has(kind)
            return this.Streams[kind]
        try {
            if (!this.Bus)
                this.Bus := this.Request("bus/create")["busId"]
            dev := this.Request('bus/' this.Bus '/add {"type":"' kind '"}')
            s := this.Connect()
            this.Streams[kind] := s
            this.Text(s, "bus/" this.Bus "/" dev["devId"])
            ; 首次创建要留出 Windows 枚举虚拟 USB 设备的时间。
            Sleep(1000)
            return s
        } catch as err {
            this.Close()
            throw err
        }
    }

    static SendReport(kind, data) {
        try {
            s := this.Stream(kind)
            pending := Buffer(4, 0)
            if DllCall("Ws2_32\ioctlsocket", "Ptr", s, "UInt", 0x4004667F, "Ptr", pending)
                throw Error("VIIPER: 读取设备连接状态失败")
            count := NumGet(pending, 0, "UInt")
            if (count) {
                feedback := Buffer(Min(count, 65536), 0)
                n := DllCall("Ws2_32\recv", "Ptr", s, "Ptr", feedback, "Int", feedback.Size, "Int", 0, "Int")
                ; 正常键盘回传仅有 LED 位（0..31）；鼠标无反馈。
                if (n <= 0 || kind != "keyboard")
                    throw Error("VIIPER: 设备流不可用，请重新运行宏")
                loop n {
                    if (NumGet(feedback, A_Index - 1, "UChar") > 31)
                        throw Error("VIIPER: 设备流握手失败，请重新运行宏")
                }
            }
            this.Write(s, data)
        } catch as err {
            this.Close()
            throw err
        }
    }

    static Close(*) {
        for kind, s in this.Streams {
            try this.Write(s, Buffer(kind == "keyboard" ? 2 : 9, 0))
            DllCall("Ws2_32\closesocket", "Ptr", s)
        }
        this.Streams.Clear(), this.Keys.Clear(), this.Buttons := 0
        bus := this.Bus, this.Bus := 0
        if (bus)
            try this.Request("bus/remove " bus)
    }

    static Usage(key) {
        ; 扫描码映射保留主键盘/小键盘及左右修饰键的区别。
        static scan := Map(
            0x01,0x29, 0x0C,0x2D, 0x0D,0x2E, 0x0E,0x2A, 0x0F,0x2B,
            0x1A,0x2F, 0x1B,0x30, 0x1C,0x28, 0x1D,0xE0, 0x27,0x33,
            0x28,0x34, 0x29,0x35, 0x2A,0xE1, 0x2B,0x31, 0x33,0x36,
            0x34,0x37, 0x35,0x38, 0x36,0xE5, 0x37,0x55, 0x38,0xE2,
            0x39,0x2C, 0x3A,0x39, 0x45,0x53, 0x46,0x47, 0x47,0x5F,
            0x48,0x60, 0x49,0x61, 0x4A,0x56, 0x4B,0x5C, 0x4C,0x5D,
            0x4D,0x5E, 0x4E,0x57, 0x4F,0x59, 0x50,0x5A, 0x51,0x5B,
            0x52,0x62, 0x53,0x63, 0x56,0x64, 0x57,0x44, 0x58,0x45,
            0x136,0xE5, 0x11C,0x58, 0x11D,0xE4, 0x135,0x54, 0x137,0x46, 0x138,0xE6,
            0x145,0x53, 0x147,0x4A, 0x148,0x52, 0x149,0x4B, 0x14B,0x50,
            0x14D,0x4F, 0x14F,0x4D, 0x150,0x51, 0x151,0x4E, 0x152,0x49,
            0x153,0x4C, 0x15B,0xE3, 0x15C,0xE7, 0x15D,0x65)
        vk := GetKeyVK(key), sc := GetKeySC(key)
        if (vk == 0x13)
            return 0x48
        ; 消费者页按键并非标准键盘页；由调用者明确回退到 AHK。
        if (vk >= 0xA6 && vk <= 0xB7)
            return 0
        if scan.Has(sc)
            return scan[sc]
        if (sc >= 2 && sc <= 11)
            return 0x1E + sc - 2
        if (sc >= 0x3B && sc <= 0x44)
            return 0x3A + sc - 0x3B
        if (vk >= 0x7C && vk <= 0x87)
            return 0x68 + vk - 0x7C
        static letters := Map(0x10,"Q",0x11,"W",0x12,"E",0x13,"R",0x14,"T",0x15,"Y",0x16,"U",0x17,"I",0x18,"O",0x19,"P",0x1E,"A",0x1F,"S",0x20,"D",0x21,"F",0x22,"G",0x23,"H",0x24,"J",0x25,"K",0x26,"L",0x2C,"Z",0x2D,"X",0x2E,"C",0x2F,"V",0x30,"B",0x31,"N",0x32,"M")
        return letters.Has(sc) ? Ord(letters[sc]) - Ord("A") + 4 : 0
    }

    static Key(key, down) {
        static buttons := Map("LButton",1,"RButton",2,"MButton",4,"XButton1",8,"XButton2",16)
        static wheels := Map("WheelUp",[1,0],"WheelDown",[-1,0],"WheelLeft",[0,-1],"WheelRight",[0,1])
        if buttons.Has(key) {
            this.Stream("mouse")
            this.Buttons := down ? this.Buttons | buttons[key] : this.Buttons & ~buttons[key]
            this.Mouse()
        } else if wheels.Has(key) {
            if (down)
                this.Mouse(0, 0, wheels[key][1], wheels[key][2])
        } else {
            usage := this.Usage(key)
            if (!usage)
                return false
            ; 设备枚举会等待；等它完成后再读取/修改共享按键状态。
            this.Stream("keyboard")
            if (down)
                this.Keys[usage] := true
            else if this.Keys.Has(usage)
                this.Keys.Delete(usage)
            mods := 0, codes := []
            for u in this.Keys {
                if (u >= 0xE0 && u <= 0xE7)
                    mods |= 1 << (u - 0xE0)
                else
                    codes.Push(u)
            }
            data := Buffer(2 + codes.Length, 0)
            NumPut("UChar", mods, "UChar", codes.Length, data)
            for i, u in codes
                NumPut("UChar", u, data, i + 1)
            this.SendReport("keyboard", data)
        }
        return true
    }

    static Mouse(x := 0, y := 0, wheel := 0, pan := 0) {
        this.Stream("mouse")
        data := Buffer(9, 0)
        NumPut("UChar", this.Buttons, "Short", x, "Short", y, "Short", wheel, "Short", pan, data)
        this.SendReport("mouse", data)
        return true
    }

    static Move(x, y, speed := 90) {
        this.Stream("mouse")
        CoordMode("Mouse", "Screen")
        steps := Max(1, Ceil(Max(Abs(x), Abs(y)) / (speed >= 100 ? 32767 : Max(1, speed))))
        px := 0, py := 0
        loop steps {
            nx := Round(x * A_Index / steps), ny := Round(y * A_Index / steps)
            this.Mouse(nx - px, ny - py)
            px := nx, py := ny
            if (speed < 100)
                Sleep(10)
        }
        return true
    }
}

SendViiperKey(key, state, tableItem, index) {
    try {
        if !ViiperInput.Key(key, state) {
            SendNormalKey(key, state, tableItem, index)
            return
        }
        bucket := GetHoldBucket(tableItem, index)
        if (state)
            TrackDown(bucket, key, "VIIPER:" ViiperInput.Bus, tableItem, index)
        else
            TrackUp(bucket, key, tableItem, index)
    } catch as err {
        ViiperInput.Close()
        throw err
    }
}

ReleaseViiperKey(key, source, tableItem, index) {
    bus := Integer(SubStr(source, 8))
    if (bus == ViiperInput.Bus)
        SendViiperKey(key, 0, tableItem, index)
    else {
        ; 主进程不能用另一个虚拟设备释放 Worker 的键，必须移除原总线。
        try ViiperInput.Request("bus/remove " bus)
        TrackUp(GetHoldBucket(tableItem, index), key, tableItem, index)
    }
}
