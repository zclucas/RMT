using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace GameInputTest
{
    [StructLayout(LayoutKind.Sequential)]
    public struct GameInputGamepadState
    {
        // NOTE: keep this struct at 32 bytes (8 x 4). GetGamepadState (vt[22])
        // is marshalled as an `out struct`; shrinking the struct breaks the call
        // (returns a bogus float-like code). Empirically 32 bytes works.
        //   off0  buttons(int32 bitmask)   off4  LeftTrigger
        //   off8  RightTrigger             off12 LeftThumbstickX
        //   off16 LeftThumbstickY          off20 RightThumbstickX
        //   off24 RightThumbstickY         off28 _pad
        public int    buttons;            // offset 0 (bitmask, see GameInputGamepadButtons)
        public float  LeftTrigger;        // offset 4
        public float  RightTrigger;       // offset 8
        public float  LeftThumbstickX;    // offset 12
        public float  LeftThumbstickY;    // offset 16
        public float  RightThumbstickX;   // offset 20
        public float  RightThumbstickY;   // offset 24
        public float  _pad;               // offset 28 (keep 32-byte size)
    }

    public class ReadingData
    {
        public string DeviceId;
        public float LeftThumbstickX, LeftThumbstickY;
        public float RightThumbstickX, RightThumbstickY;
        public float LeftTrigger, RightTrigger;
        public ulong Buttons;
        // Vendor / product identity (from IGameInputDevice::GetDeviceInfo), used
        // to tell a real pad from a virtual (ViGEm) controller. 0 when unknown.
        public ushort VendorId;
        public ushort ProductId;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GameInputCreateDelegate(out IntPtr ppGameInput);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetCurrentReadingFn(IntPtr self, uint kind, IntPtr device, out IntPtr reading);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetNextReadingFn(IntPtr self, IntPtr refReading, uint kind, IntPtr device, out IntPtr reading);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetDeviceFn(IntPtr self, out IntPtr device);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetGamepadStateFn(IntPtr self, out GameInputGamepadState state);

    // IGameInputDevice::GetDeviceInfo — returns GameInputDeviceInfo const*
    // (a direct pointer held by the IGameInput instance; caller does NOT free it).
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate IntPtr GetDeviceInfoFn(IntPtr self);

    // IGameInput::SetFocusPolicy — void(this, GameInputFocusPolicy)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate void SetFocusPolicyFn(IntPtr self, uint policy);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate uint ReleaseFn(IntPtr self);

    public class GameInputWrapper : IDisposable
    {
        // ---- Confirmed vtable indices (tested on Win11, GameInput.dll inbox) ----
        // IGameInput (after IUnknown at 0-2):
        //   [3]=GetCurrentTimestamp, [4]=GetCurrentReading, [5]=GetNextReading
        // IGameInputReading (after IUnknown at 0-2):
        //   [6]=GetDevice, [22]=GetGamepadState
        //   vt[3] is NOT GetInputKind on inbox GameInput.dll — skip kind check
        const int VTABLE_READING_GET_CURRENT = 4;
        const int VTABLE_READING_GET_NEXT    = 5;

        const int VTABLE_READING_GET_DEVICE     = 6;
        const int VTABLE_READING_GET_GAMEPAD    = 22;

        // IGameInputDevice (after IUnknown at 0-2): vt[3]=GetDeviceInfo (verified
        // against local SDK GameInput.h, whose vt6/vt22 for the reading object
        // exactly match the confirmed inbox-dll indices used above).
        const int VTABLE_DEVICE_GET_INFO = 3;

        // IGameInput vtable: SetFocusPolicy (verified against the same layout that
        // places GetCurrentTimestamp=3 / GetCurrentReading=4 / GetNextReading=5).
        const int VTABLE_SET_FOCUS_POLICY = 21;

        // GameInputFocusPolicy (GameInputFocusPolicy.h)
        // 0x40 = GameInputEnableBackgroundInput — keep delivering gamepad input
        // to this process even when it is not the foreground / focused window.
        const uint FOCUS_ENABLE_BACKGROUND_INPUT = 0x00000040;

        // GameInput is event-driven: GetCurrentReading returns
        // HR=0x838A0003 (ReadingNotFound) when no readings are queued.
        // Confirmed by InputWeave.GameInput GameInputHResult.g.cs.
        const int HR_READING_NOT_FOUND = unchecked((int)0x838A0003);

        // ---- GameInputGamepadButtons bit -> XInput wButtons bit ----
        // GameInput (bit index): Menu=0 View=1 A=2 B=3 X=4 Y=5
        //   DPadUp=6 DPadDown=7 DPadLeft=8 DPadRight=9 LB=10 RB=11 LS=12 RS=13
        // XInput wButtons (standard XINPUT_GAMEPAD_*):
        //   DPadUp=0 DPadDown=1 DPadLeft=2 DPadRight=3 Start=4 Back=5
        //   LS=6 RS=7 LB=8 RB=9 A=12 B=13 X=14 Y=15
        // (GameInput Menu=Start, View=Back)
        // NOTE: kept as plain parallel arrays (no ValueTuple) so this compiles
        // under the classic .NET Framework CSharpCodeProvider (C#5) used by CLR.ahk.
        static readonly int[] GI_BITS = { 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 12, 13, 10, 11 };
        static readonly int[] XI_BITS = { 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };

        // Confirmed by InputWeave.GameInput GameInputEnums.g.cs
        const uint KIND_CONTROLLER = 14;       // axes|buttons|switches
        const uint KIND_GAMEPAD    = 262144;   // 0x40000

        IntPtr _gi;
        GetCurrentReadingFn _getReading;
        GetNextReadingFn    _getNext;
        SetFocusPolicyFn    _setFocusPolicy;

        IntPtr _rvt;
        GetDeviceFn         _rGetDevice;
        GetGamepadStateFn   _rGetGamepad;
        ReleaseFn           _rRelease;

        IntPtr _dvt;
        GetDeviceInfoFn     _dGetInfo;

        // Per-device state cache
        Dictionary<string, ReadingData> _deviceStates = new Dictionary<string, ReadingData>();

        // ---- Anti-loopback: run-time exclusion of virtual (ViGEm) devices ----
        // Identity of a virtual controller is NOT its VID/PID (varies per user/run);
        // it is "the device that appears after we start auto-excluding". The caller
        // snapshots the currently-known real controllers (they emit readings and are
        // tracked already), then any NEW device that shows up from then on must be
        // the loopback of our own ViG output -> excluded so readers never see it.
        // NOTE: List<T> (mscorlib/System) is used instead of HashSet<T> (System.Core),
        // because CLR_CompileCS (classic CSharpCodeProvider, C#5) only auto-references
        // mscorlib + System by default — HashSet<T> lives in System.Core and would
        // fail with CS0246. Device counts are tiny (<10), so O(n) Contains is fine.
        readonly List<string> _excluded    = new List<string>();
        readonly List<string> _baseline    = new List<string>();
        bool _autoExcludeNew = false;

        // Add only if not already present (List.Add would otherwise allow dupes).
        void AddExcluded(string devId)
        {
            if (!string.IsNullOrEmpty(devId) && !_excluded.Contains(devId))
                _excluded.Add(devId);
        }

        // Diagnostic: last DrainReadings results
        string _diag = "Waiting for gamepad input... (press a button)\r\n";
        public string GetDiag() { return _diag; }

        public bool Init()
        {
            IntPtr hMod = LoadLibraryW("GameInput.dll");
            if (hMod == IntPtr.Zero) return false;

            IntPtr pCreate = GetProcAddressA(hMod, "GameInputCreate");
            if (pCreate == IntPtr.Zero) return false;

            GameInputCreateDelegate create = (GameInputCreateDelegate)
                Marshal.GetDelegateForFunctionPointer(pCreate, typeof(GameInputCreateDelegate));

            int hr = create(out _gi);
            if (hr < 0 || _gi == IntPtr.Zero) return false;

            IntPtr vt = Marshal.ReadIntPtr(_gi);
            _getReading = (GetCurrentReadingFn)Resolve(vt, VTABLE_READING_GET_CURRENT, typeof(GetCurrentReadingFn));
            _getNext    = (GetNextReadingFn)   Resolve(vt, VTABLE_READING_GET_NEXT,    typeof(GetNextReadingFn));
            _setFocusPolicy = (SetFocusPolicyFn)Resolve(vt, VTABLE_SET_FOCUS_POLICY,   typeof(SetFocusPolicyFn));

            // Deliver gamepad input even when our window is not focused (background).
            // Without this, GameInput drops readings once another window takes focus.
            _setFocusPolicy(_gi, FOCUS_ENABLE_BACKGROUND_INPUT);

            return true;
        }

        /// <summary>Return all known device states, updated by any new readings.
        /// One line per device: devId;lx;ly;rx;ry;lt;rt;buttons</summary>
        public string PollString()
        {
            // Drain new readings — they update _deviceStates
            DrainReadings();

            string[] keys = VisibleDeviceIds();
            if (keys.Length == 0)
                return "";
            string[] lines = new string[keys.Length];
            for (int i = 0; i < keys.Length; i++)
            {
                ReadingData r = _deviceStates[keys[i]];
                lines[i] = string.Format(
                    System.Globalization.CultureInfo.InvariantCulture,
                    "{0};{1:R};{2:R};{3:R};{4:R};{5:R};{6:R};{7}",
                    r.DeviceId, r.LeftThumbstickX, r.LeftThumbstickY,
                    r.RightThumbstickX, r.RightThumbstickY,
                    r.LeftTrigger, r.RightTrigger, r.Buttons);
            }
            return string.Join("\n", lines);
        }

        /// <summary>Number of visible (non-excluded) devices. When nothing is excluded
        /// this equals the total tracked. Callers that just want "is a real pad there"
        /// (GI_HasDevice) should read this, since excluded virtual devices do not count.</summary>
        public int DeviceCount { get { return VisibleDeviceIds().Length; } }

        // ---- Anti-loopback public API (run-time identity, NOT VID/PID) ----

        /// <summary>All currently tracked device ids (real + virtual), regardless of
        /// exclusion — useful to snapshot "what is connected right now".</summary>
        public string[] KnownDeviceIds()
        {
            string[] keys = new string[_deviceStates.Count];
            _deviceStates.Keys.CopyTo(keys, 0);
            return keys;
        }
        public int TrackedCount { get { return _deviceStates.Count; } }

        /// <summary>Device ids currently hidden as virtual (loopback).</summary>
        public string[] ExcludedDeviceIds()
        {
            string[] keys = new string[_excluded.Count];
            _excluded.CopyTo(keys, 0);
            return keys;
        }
        public int ExcludedCount { get { return _excluded.Count; } }

        /// <summary>Explicitly mark one devId as virtual so every reader skips it.</summary>
        public void ExcludeDeviceId(string devId)
        {
            AddExcluded(devId);
        }

        /// <summary>Un-mark a devId previously excluded (e.g. a real pad was re-plugged).</summary>
        public void UnExcludeDeviceId(string devId)
        {
            if (devId != null) _excluded.Remove(devId);
        }

        /// <summary>Forget all exclusions.</summary>
        public void ClearExcluded() { _excluded.Clear(); }

        /// <summary>
        /// Turn on anti-loopback: snapshot every currently-known device (these are the
        /// real physical controllers — they emit readings and are already tracked), then
        /// from now on ANY newly-appearing device is our own ViG virtual output and gets
        /// auto-excluded from all readers. Call this after the real pad(s) produced at
        /// least one reading but BEFORE our ViG output starts emitting.
        /// </summary>
        public void AutoExcludeNewFromHere()
        {
            _baseline.Clear();
            foreach (string k in _deviceStates.Keys)
                _baseline.Add(k);
            _autoExcludeNew = true;
        }

        /// <summary>Turn off anti-loopback auto-exclusion (clear baseline, keep manual).</summary>
        public void DisableAutoExclude()
        {
            _autoExcludeNew = false;
            _baseline.Clear();
        }

        public bool AutoExcludeEnabled { get { return _autoExcludeNew; } }

        // Filtered key list used by every reader so excluded (virtual) devices vanish.
        string[] VisibleDeviceIds()
        {
            if (_excluded.Count == 0)
            {
                string[] all = new string[_deviceStates.Count];
                _deviceStates.Keys.CopyTo(all, 0);
                return all;
            }
            List<string> vis = new List<string>();
            foreach (KeyValuePair<string, ReadingData> kv in _deviceStates)
                if (!_excluded.Contains(kv.Key))
                    vis.Add(kv.Key);
            return vis.ToArray();
        }

        /// <summary>
        /// Drain new readings and return per-device state in RMT-compatible XInput
        /// layout. One line per device:
        ///   devId;wButtons;bLeftTrigger;bRightTrigger;sThumbLX;sThumbLY;sThumbRX;sThumbRY;vid;pid
        /// where wButtons uses standard XInput wButtons bits and sticks are in the
        /// XInput range (-32768..32767), triggers in 0..255. vid/pid (appended,
        /// 0 = unknown) identify the device; a virtual ViGEm pad shows a distinct
        /// vid/pid vs a physical controller so callers can filter it out.
        /// RMT's existing XInput-diff recording logic reads fields 1..8 and is
        /// unaffected by the two appended fields.
        /// </summary>
        public string PollXboxString()
        {
            DrainReadings();
            string[] keys = VisibleDeviceIds();
            if (keys.Length == 0)
                return "";
            string[] lines = new string[keys.Length];
            for (int i = 0; i < keys.Length; i++)
            {
                ReadingData r = _deviceStates[keys[i]];
                int wb = ToXinputButtons(r.Buttons);
                byte lt = ClampByte(r.LeftTrigger);
                byte rt = ClampByte(r.RightTrigger);
                short lx = ClampShort(r.LeftThumbstickX);
                short ly = ClampShort(r.LeftThumbstickY);
                short rx = ClampShort(r.RightThumbstickX);
                short ry = ClampShort(r.RightThumbstickY);
                lines[i] = string.Format(
                    System.Globalization.CultureInfo.InvariantCulture,
                    "{0};{1};{2};{3};{4};{5};{6};{7};{8};{9}",
                    r.DeviceId, wb, lt, rt, lx, ly, rx, ry,
                    r.VendorId, r.ProductId);
            }
            return string.Join("\n", lines);
        }

        // Translate a GameInput button bitmask (low bits per GI_BITS) into the
        // equivalent standard XInput wButtons bitmask.
        static int ToXinputButtons(ulong gi)
        {
            int xi = 0;
            for (int i = 0; i < GI_BITS.Length; i++)
            {
                if (((gi >> GI_BITS[i]) & 1) != 0)
                    xi |= (1 << XI_BITS[i]);
            }
            return xi;
        }

        static byte ClampByte(float v)
        {
            if (v <= 0f) return 0;
            if (v >= 1f) return 255;
            return (byte)Math.Round(v * 255.0);
        }

        static short ClampShort(float v)
        {
            if (v <= -1f) return short.MinValue;
            if (v >= 1f) return short.MaxValue;
            return (short)Math.Round(v * 32767.0);
        }


        public string GetDebugInfo()
        {
            string s = "GameInput Init: OK\r\n";
            s += "IGameInput ptr: 0x" + _gi.ToString("X16") + "\r\n";
            s += "vtable layout: vt[3]=Timestamp, vt[4]=GetCurrentReading, vt[5]=GetNextReading\r\n";
            s += "IGameInputReading: vt[6]=GetDevice, vt[22]=GetGamepadState\r\n";
            s += "Devices tracked: " + _deviceStates.Count
               + " (visible=" + VisibleDeviceIds().Length
               + ", excluded=" + _excluded.Count
               + ", autoExcludeNew=" + (_autoExcludeNew ? "on" : "off") + ")\r\n";

            string[] keys2 = VisibleDeviceIds();
            for (int i = 0; i < keys2.Length; i++)
            {
                ReadingData r = _deviceStates[keys2[i]];
                s += "  " + r.DeviceId + ": LX=" + r.LeftThumbstickX.ToString("F2")
                   + " LY=" + r.LeftThumbstickY.ToString("F2")
                   + " RX=" + r.RightThumbstickX.ToString("F2")
                   + " RY=" + r.RightThumbstickY.ToString("F2")
                   + " LT=" + r.LeftTrigger.ToString("F2")
                   + " RT=" + r.RightTrigger.ToString("F2")
                   + " Btn=0x" + r.Buttons.ToString("X") + "\r\n";
            }
            return s;
        }

        public void Dispose()
        {
            if (_gi != IntPtr.Zero) { ReleaseComPtr(_gi); _gi = IntPtr.Zero; }
        }

        // --- Private ---

        public string Ping() { return "pong|" + _deviceStates.Count; }

        int _diagTick = 0;
        void DrainReadings()
        {
            IntPtr reading;
            int hr;

            _diagTick++;
            // Only show full diag when something changes
            string prefix = "[" + _diagTick + "] ";

            hr = _getReading(_gi, KIND_GAMEPAD, IntPtr.Zero, out reading);
            if (hr < 0 || reading == IntPtr.Zero)
                hr = _getReading(_gi, KIND_CONTROLLER, IntPtr.Zero, out reading);

            // 注意：不要再往 0xFFFFFFFF(全部类型) / 0(无过滤) 放宽。
            // 一旦放宽，键盘/鼠标产生的 reading 也会被 ProcessOneReading 无条件登记进
            // _deviceStates：它们的 gamepad 状态恒为 0，且会挤在列表首位，
            // 导致 AHK 侧 states[1] 取到键盘而不是手柄（真轴采样读到全 0）。
            // 没有手柄 reading 时直接返回，保留旧状态。
            if (hr < 0 || reading == IntPtr.Zero)
            {
                // No gamepad/controller reading — keep old diag, just update tick
                return;
            }

            _diag = prefix + "GOT READING rd=0x" + reading.ToString("X")
                  + " HR=0x" + hr.ToString("X8") + "\r\n";

            while (hr >= 0 && reading != IntPtr.Zero)
            {
                ProcessOneReading(reading);

                IntPtr next;
                hr = _getNext(_gi, reading, KIND_GAMEPAD, IntPtr.Zero, out next);
                if (hr < 0)
                    hr = _getNext(_gi, reading, KIND_CONTROLLER, IntPtr.Zero, out next);
                ReleaseComPtr(reading);
                reading = next;
            }
        }

        void ProcessOneReading(IntPtr readingPtr)
        {
            CacheReadingVtable(readingPtr);

            IntPtr device;
            if (_rGetDevice(readingPtr, out device) < 0)
            {
                _diag += "  GetDevice FAILED\r\n";
                return;
            }
            _diag += "  GetDevice=0x" + device.ToString("X16") + "\r\n";

            ushort vid = 0, pid = 0;
            GetDeviceVidPid(device, out vid, out pid);

            GameInputGamepadState state;
            int hrGs = _rGetGamepad(readingPtr, out state);
            // Note: on this dll GetGamepadState can return 0xBF800001 (= -1.0f as
            // an int) even though it has already filled `state` correctly (dump
            // showed RY=-1.000 while hr was 0xBF800001). So do NOT treat a
            // negative return as failure — trust the populated state.
            _diag += "  GetGamepadState hr=0x" + ((uint)hrGs).ToString("X8") + "\r\n";

            string devId = device.ToString("X16");
            ReadingData rd = new ReadingData
            {
                DeviceId     = devId,
                LeftThumbstickX   = state.LeftThumbstickX,
                LeftThumbstickY   = state.LeftThumbstickY,
                RightThumbstickX  = state.RightThumbstickX,
                RightThumbstickY  = state.RightThumbstickY,   // off24, was hardcoded 0
                LeftTrigger  = state.LeftTrigger,
                RightTrigger = state.RightTrigger,
                Buttons      = (ulong)(uint)state.buttons,    // off0 bitmask
                VendorId     = vid,
                ProductId    = pid,
            };

            _diag += "  LT=" + state.LeftTrigger.ToString("F3")
                  + " RT=" + state.RightTrigger.ToString("F3")
                  + " LX=" + state.LeftThumbstickX.ToString("F3")
                  + " LY=" + state.LeftThumbstickY.ToString("F3")
                  + " RX=" + state.RightThumbstickX.ToString("F3")
                  + " RY=" + state.RightThumbstickY.ToString("F3")
                  + " Btn=0x" + ((uint)state.buttons).ToString("X") + "\r\n";

            _deviceStates[devId] = rd;

            // Anti-loopback: if auto-exclusion is on and this device was NOT part of
            // the physical baseline snapshot, it is our own ViG virtual output -> hide
            // it from every reader (PollString/PollXboxString/DeviceCount/GetDebugInfo).
            if (_autoExcludeNew && !_baseline.Contains(devId))
                AddExcluded(devId);
        }

        void CacheReadingVtable(IntPtr readingPtr)
        {
            IntPtr vt = Marshal.ReadIntPtr(readingPtr);
            if (vt == _rvt) return;
            _rvt = vt;
            _rGetDevice  = (GetDeviceFn)        Resolve(vt, VTABLE_READING_GET_DEVICE,  typeof(GetDeviceFn));
            _rGetGamepad = (GetGamepadStateFn)  Resolve(vt, VTABLE_READING_GET_GAMEPAD, typeof(GetGamepadStateFn));
            _rRelease    = (ReleaseFn)          Resolve(vt, 2,                           typeof(ReleaseFn));
        }

        // Read vendorId/productId off IGameInputDevice::GetDeviceInfo.
        // GameInputDeviceInfo (v3, matches inbox dll / SDK 10.0.26100.0):
        //   off0  uint32  infoSize
        //   off4  uint16  vendorId
        //   off6  uint16  productId
        // GetDeviceInfo returns a const pointer owned by IGameInput (do not free).
        // Any step failing yields vid=pid=0 (treated as "unknown") — never throws.
        void GetDeviceVidPid(IntPtr device, out ushort vid, out ushort pid)
        {
            vid = 0;
            pid = 0;
            if (device == IntPtr.Zero)
                return;
            try
            {
                IntPtr vt = Marshal.ReadIntPtr(device);
                if (vt != _dvt)
                {
                    _dvt = vt;
                    _dGetInfo = (GetDeviceInfoFn)Resolve(vt, VTABLE_DEVICE_GET_INFO, typeof(GetDeviceInfoFn));
                }
                if (_dGetInfo == null)
                    return;
                IntPtr info = _dGetInfo(device);
                if (info == IntPtr.Zero)
                    return;
                vid = (ushort)Marshal.ReadInt16(info, 4);
                pid = (ushort)Marshal.ReadInt16(info, 6);
            }
            catch
            {
                // VID/PID are best-effort; never let a bad read break input flow.
                vid = 0;
                pid = 0;
            }
        }

        static Delegate Resolve(IntPtr vtable, int index, Type t)
        {
            IntPtr fp = Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(fp, t);
        }

        static void ReleaseComPtr(IntPtr ptr)
        {
            if (ptr == IntPtr.Zero) return;
            IntPtr vt = Marshal.ReadIntPtr(ptr);
            IntPtr fp = Marshal.ReadIntPtr(vt, 2 * IntPtr.Size);
            ReleaseFn r = (ReleaseFn)Marshal.GetDelegateForFunctionPointer(fp, typeof(ReleaseFn));
            r(ptr);
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "LoadLibraryW")]
        static extern IntPtr LoadLibraryW(string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, EntryPoint = "GetProcAddress")]
        static extern IntPtr GetProcAddressA(IntPtr hModule, string procName);
    }
}
