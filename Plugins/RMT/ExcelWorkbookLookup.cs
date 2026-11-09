using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace RMT
{
    internal static class ExcelWorkbookLookup
    {
        internal const string AccessDenied = "若目标工作簿在管理员权限的 Excel 中打开，请以管理员身份运行 RMT 后重试。";
        private const int ComAccessDenied = unchecked((int)0x80070005);
        private const uint NativeObjectModel = unchecked((uint)-16);
        private static readonly Guid DispatchId = new Guid("00020400-0000-0000-C000-000000000046");

        private delegate bool WindowCallback(IntPtr window, IntPtr data);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(WindowCallback callback, IntPtr data);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr data);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder name, int length);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam,
            IntPtr lParam, uint flags, uint timeout, out IntPtr result);

        [DllImport("oleacc.dll")]
        private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId,
            ref Guid interfaceId, [MarshalAs(UnmanagedType.IDispatch)] out object accessible);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll")]
        private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("advapi32.dll")]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

        [DllImport("advapi32.dll")]
        private static extern bool GetTokenInformation(IntPtr token, int informationClass,
            IntPtr buffer, int length, out int required);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthority(IntPtr sid, int index);

        // UIPI can hide elevated Excel windows entirely. Use process integrity
        // levels when reporting a failed attempt to open a writable workbook.
        internal static bool HasHigherIntegrityExcel()
        {
            int currentLevel = IntegrityLevel(GetCurrentProcess());
            if (currentLevel <= 0 || currentLevel >= 0x3000)
                return false;

            int session;
            using (var current = Process.GetCurrentProcess())
                session = current.SessionId;

            foreach (var excel in Process.GetProcessesByName("EXCEL"))
            {
                using (excel)
                {
                    try
                    {
                        if (excel.SessionId != session)
                            continue;
                        IntPtr process = OpenProcess(0x1000, false, excel.Id); // PROCESS_QUERY_LIMITED_INFORMATION
                        if (process == IntPtr.Zero)
                            continue;
                        try
                        {
                            if (IntegrityLevel(process) > currentLevel)
                                return true;
                        }
                        finally { CloseHandle(process); }
                    }
                    catch (InvalidOperationException) { }
                    catch (Win32Exception) { }
                }
            }
            return false;
        }

        private static int IntegrityLevel(IntPtr process)
        {
            IntPtr token;
            if (!OpenProcessToken(process, 8, out token)) // TOKEN_QUERY
                return 0;
            try
            {
                int length;
                GetTokenInformation(token, 25, IntPtr.Zero, 0, out length); // TokenIntegrityLevel
                if (length == 0)
                    return 0;
                IntPtr buffer = Marshal.AllocHGlobal(length);
                try
                {
                    if (!GetTokenInformation(token, 25, buffer, length, out length))
                        return 0;
                    IntPtr sid = Marshal.ReadIntPtr(buffer);
                    int index = Marshal.ReadByte(GetSidSubAuthorityCount(sid)) - 1;
                    return Marshal.ReadInt32(GetSidSubAuthority(sid, index));
                }
                finally { Marshal.FreeHGlobal(buffer); }
            }
            finally { CloseHandle(token); }
        }

        internal static bool IsElevated()
        {
            return IntegrityLevel(GetCurrentProcess()) >= 0x3000;
        }

        private static bool IsElevatedExcel(uint pid)
        {
            try
            {
                using (var candidate = Process.GetProcessById((int)pid))
                {
                    if (!candidate.ProcessName.Equals("EXCEL", StringComparison.OrdinalIgnoreCase))
                        return false;
                }
                IntPtr process = OpenProcess(0x1000, false, (int)pid);
                if (process == IntPtr.Zero)
                    return false;
                try { return IntegrityLevel(process) >= 0x3000; }
                finally { CloseHandle(process); }
            }
            catch (ArgumentException) { return false; }
            catch (InvalidOperationException) { return false; }
            catch (Win32Exception) { return false; }
        }

        internal static object Find(string path, Action checkCancelled, out bool denied, bool elevatedOnly = false)
        {
            denied = false;
            var panes = new List<IntPtr>();
            var className = new StringBuilder(32);
            EnumWindows((window, data) =>
            {
                if (!HasClass(window, className, "XLMAIN"))
                    return true;
                EnumChildWindows(window, (child, childData) =>
                {
                    if (HasClass(child, className, "EXCEL7"))
                        panes.Add(child);
                    return true;
                }, IntPtr.Zero);
                return true;
            }, IntPtr.Zero);

            var visited = new HashSet<uint>();
            foreach (IntPtr pane in panes)
            {
                checkCancelled();
                uint pid;
                if (GetWindowThreadProcessId(pane, out pid) == 0 || visited.Contains(pid))
                    continue;
                if (elevatedOnly && !IsElevatedExcel(pid))
                {
                    visited.Add(pid);
                    continue;
                }

                // Avoid asking an unresponsive Excel window for its COM object.
                IntPtr ignored;
                if (SendMessageTimeout(pane, 0, IntPtr.Zero, IntPtr.Zero, 2, 100, out ignored) == IntPtr.Zero)
                {
                    denied |= Marshal.GetLastWin32Error() == 5;
                    continue;
                }

                object windowObject;
                Guid iid = DispatchId;
                int hr = AccessibleObjectFromWindow(pane, NativeObjectModel, ref iid, out windowObject);
                if (hr != 0)
                {
                    denied |= hr == ComAccessDenied;
                    continue;
                }
                try
                {
                    object workbook = FindInWindow(windowObject, path, checkCancelled);
                    if (workbook != null)
                        return workbook;
                    visited.Add(pid);
                }
                catch (COMException ex) { denied |= ex.ErrorCode == ComAccessDenied; }
                finally { ExcelEditor.Release(windowObject); }
            }
            return null;
        }

        private static object FindInWindow(dynamic window, string path, Action checkCancelled)
        {
            dynamic app = null, books = null;
            try
            {
                app = window.Application;
                books = app.Workbooks;
                int count = books.Count;
                for (int i = 1; i <= count; i++)
                {
                    checkCancelled();
                    dynamic book = books[i];
                    bool matches = false;
                    try
                    {
                        matches = string.Equals((string)book.FullName, path, StringComparison.OrdinalIgnoreCase);
                        if (matches)
                            return book;
                    }
                    finally
                    {
                        if (!matches)
                            ExcelEditor.Release((object)book);
                    }
                }
                return null;
            }
            finally
            {
                ExcelEditor.Release((object)books);
                ExcelEditor.Release((object)app);
            }
        }

        private static bool HasClass(IntPtr window, StringBuilder name, string expected)
        {
            return GetClassName(window, name, name.Capacity) != 0 && name.ToString() == expected;
        }
    }
}
