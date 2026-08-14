using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace GameInputTest
{
    [StructLayout(LayoutKind.Sequential)]
    public struct GameInputGamepadState
    {
        // Final stable layout. vt[22] on inbox GameInput.dll.
        // 5/6 axes confirmed. RY=0, Btn=0 for now.
        public float _f0;               // offset 0
        public float LeftTrigger;       // offset 4
        public float RightTrigger;      // offset 8
        public float LeftThumbstickX;   // offset 12
        public float LeftThumbstickY;   // offset 16
        public float RightThumbstickX;  // offset 20
        public float _f6;               // offset 24
        public float _f7;               // offset 28
    }

    public class ReadingData
    {
        public string DeviceId;
        public float LeftThumbstickX, LeftThumbstickY;
        public float RightThumbstickX, RightThumbstickY;
        public float LeftTrigger, RightTrigger;
        public ulong Buttons;
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

        // GameInput is event-driven: GetCurrentReading returns
        // HR=0x838A0003 (ReadingNotFound) when no readings are queued.
        // Confirmed by InputWeave.GameInput GameInputHResult.g.cs.
        const int HR_READING_NOT_FOUND = unchecked((int)0x838A0003);

        // Confirmed by InputWeave.GameInput GameInputEnums.g.cs
        const uint KIND_CONTROLLER = 14;       // axes|buttons|switches
        const uint KIND_GAMEPAD    = 262144;   // 0x40000

        IntPtr _gi;
        GetCurrentReadingFn _getReading;
        GetNextReadingFn    _getNext;

        IntPtr _rvt;
        GetDeviceFn         _rGetDevice;
        GetGamepadStateFn   _rGetGamepad;
        ReleaseFn           _rRelease;

        // Per-device state cache
        Dictionary<string, ReadingData> _deviceStates = new Dictionary<string, ReadingData>();

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

            return true;
        }

        /// <summary>Return all known device states, updated by any new readings.
        /// One line per device: devId;lx;ly;rx;ry;lt;rt;buttons</summary>
        public string PollString()
        {
            // Drain new readings — they update _deviceStates
            DrainReadings();

            if (_deviceStates.Count == 0)
                return "";

            string[] keys = new string[_deviceStates.Count];
            _deviceStates.Keys.CopyTo(keys, 0);
            string[] lines = new string[_deviceStates.Count];
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

        /// <summary>Number of known devices (even if idle)</summary>
        public int DeviceCount { get { return _deviceStates.Count; } }

        public string GetDebugInfo()
        {
            string s = "GameInput Init: OK\r\n";
            s += "IGameInput ptr: 0x" + _gi.ToString("X16") + "\r\n";
            s += "vtable layout: vt[3]=Timestamp, vt[4]=GetCurrentReading, vt[5]=GetNextReading\r\n";
            s += "IGameInputReading: vt[6]=GetDevice, vt[22]=GetGamepadState\r\n";
            s += "Devices tracked: " + _deviceStates.Count + "\r\n";

            string[] keys2 = new string[_deviceStates.Count];
            _deviceStates.Keys.CopyTo(keys2, 0);
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
            if (hr < 0 || reading == IntPtr.Zero)
                hr = _getReading(_gi, 0xFFFFFFFF, IntPtr.Zero, out reading);
            if (hr < 0 || reading == IntPtr.Zero)
                hr = _getReading(_gi, 0, IntPtr.Zero, out reading);

            if (hr < 0 || reading == IntPtr.Zero)
            {
                // No new reading — keep old diag, just update tick
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

            GameInputGamepadState state;
            if (_rGetGamepad(readingPtr, out state) < 0)
            {
                _diag += "  GetGamepadState FAILED\r\n";
                return;
            }

            string devId = device.ToString("X16");
            ReadingData rd = new ReadingData
            {
                DeviceId     = devId,
                LeftThumbstickX   = state.LeftThumbstickX,
                LeftThumbstickY   = state.LeftThumbstickY,
                RightThumbstickX  = state.RightThumbstickX,
                RightThumbstickY  = 0,
                LeftTrigger  = state.LeftTrigger,
                RightTrigger = state.RightTrigger,
                Buttons      = 0,
            };

            _diag += "  LT=" + state.LeftTrigger.ToString("F3")
                  + " RT=" + state.RightTrigger.ToString("F3")
                  + " LX=" + state.LeftThumbstickX.ToString("F3")
                  + " LY=" + state.LeftThumbstickY.ToString("F3")
                  + " RX=" + state.RightThumbstickX.ToString("F3")
                  + " RY=0" + "\r\n";

            _deviceStates[devId] = rd;
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
