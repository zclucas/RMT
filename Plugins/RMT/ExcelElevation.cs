using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using Microsoft.Win32.SafeHandles;

[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

namespace RMT
{
    [DataContract]
    internal sealed class ExcelRequest
    {
        [DataMember] public string Path, MutexName, Mode;
        [DataMember] public object Sheet;
        [DataMember] public bool Write;
        [DataMember] public int Row, Col, EndRow, EndCol;
        [DataMember] public object[] Cells;
    }

    internal static class ExcelElevation
    {
        internal const string HelperName = "RMT.ExcelHelper.exe";
        private const string PipePrefix = "RMT.Excel.";
        private const int MaxFrameSize = 64 * 1024 * 1024;
        private const int MaxRows = 1048576;
        private const int MaxCols = 16384;

        [DataContract]
        private sealed class Reply
        {
            [DataMember] public string Error;
            [DataMember] public string[] Values;
        }

        [DllImport("kernel32.dll")]
        private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint processId);

        [DllImport("kernel32.dll")]
        private static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint processId);

        internal static string[] Run(ExcelRequest request, Action checkCancelled, Action<bool> waitingForElevation)
        {
            string helper = Path.Combine(Path.GetDirectoryName(typeof(ExcelElevation).Assembly.Location), HelperName);
            if (!File.Exists(helper))
                throw new FileNotFoundException("缺少 Excel 提权助手，请重新编译 RMT 插件");

            // Complete serialization before requesting elevation.
            byte[] payload = Serialize(request);
            var security = new PipeSecurity();
            using (var identity = WindowsIdentity.GetCurrent())
                security.AddAccessRule(new PipeAccessRule(identity.User, PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                PipeAccessRights.ReadWrite | PipeAccessRights.Synchronize, AccessControlType.Allow));

            string pipeId = Guid.NewGuid().ToString("N");
            using (var parent = Process.GetCurrentProcess())
            using (var pipe = new NamedPipeServerStream(PipePrefix + pipeId, PipeDirection.InOut, 1,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 0, 0, security))
            {
                checkCancelled();
                Process child;
                waitingForElevation(true);
                try
                {
                    child = StartHelper(helper, pipeId, parent.Id);
                }
                catch (Win32Exception ex)
                {
                    if (ex.NativeErrorCode == 1223) // ERROR_CANCELLED
                        throw new OperationCanceledException("已取消 Excel 管理员授权", ex);
                    throw;
                }
                if (child == null)
                    throw new IOException("无法启动 Excel 提权助手");

                using (child)
                {
                    var connecting = Stopwatch.StartNew();
                    Action checkChild = () =>
                    {
                        checkCancelled();
                        if (!pipe.IsConnected && HasExited(child))
                        {
                            if (child.ExitCode == 2)
                                throw new IOException("Windows 未授予 Excel 助手管理员权限");
                            throw new IOException("Excel 提权助手未建立连接");
                        }
                        if (connecting.ElapsedMilliseconds >= 15000)
                            throw new IOException("Excel 提权助手未建立连接");
                    };
                    Wait(pipe.WaitForConnectionAsync(), checkChild);
                    uint clientPid;
                    if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle, out clientPid) || clientPid != child.Id)
                        throw new IOException("Excel 提权助手连接验证失败");
                    waitingForElevation(false);

                    checkCancelled();
                    WriteFrame(pipe, payload, checkCancelled);
                    Reply reply = ReadFrame<Reply>(pipe, checkCancelled);
                    if (!string.IsNullOrEmpty(reply.Error))
                        throw new IOException(reply.Error);
                    return reply.Values;
                }
            }
        }

        private static Process StartHelper(string helper, string pipeId, int parentPid)
        {
            return Process.Start(new ProcessStartInfo(helper,
                pipeId + " " + parentPid.ToString(CultureInfo.InvariantCulture))
            {
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = Environment.SystemDirectory,
                ErrorDialog = false
            });
        }

        private static bool HasExited(Process child)
        {
            try { return child.HasExited; }
            catch (Win32Exception ex)
            {
                if (ex.NativeErrorCode != 5) // ERROR_ACCESS_DENIED
                    throw;
                return false;
            }
        }

        [STAThread]
        private static int Main(string[] args)
        {
            Guid pipeId;
            uint parentPid;
            if (args.Length != 2 || !Guid.TryParseExact(args[0], "N", out pipeId)
                || !uint.TryParse(args[1], NumberStyles.None, CultureInfo.InvariantCulture, out parentPid))
                return 1;
            if (!ExcelWorkbookLookup.IsElevated())
                return 2;

            try
            {
                // Identification prevents the pipe server from impersonating
                // the elevated helper.
                using (var pipe = new NamedPipeClientStream(".", PipePrefix + pipeId.ToString("N"),
                    PipeDirection.InOut, PipeOptions.Asynchronous, TokenImpersonationLevel.Identification))
                {
                    pipe.Connect(10000);
                    uint serverPid;
                    if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle, out serverPid) || serverPid != parentPid)
                        return 1;

                    var transfer = Stopwatch.StartNew();
                    Action checkTransfer = () =>
                    {
                        if (transfer.ElapsedMilliseconds >= 20000)
                            throw new TimeoutException();
                    };
                    ExcelRequest request = ReadFrame<ExcelRequest>(pipe, checkTransfer);
                    // After the one request, the next read completes when the
                    // parent cancels or closes its side of the pipe.
                    var disconnected = pipe.ReadAsync(new byte[1], 0, 1);
                    byte[] reply;
                    try
                    {
                        Validate(request);
                        var values = new ExcelEditor().ExecuteElevated(request, () =>
                        {
                            if (disconnected.IsCompleted)
                                throw new OperationCanceledException();
                        });
                        reply = Serialize(new Reply { Values = values });
                    }
                    catch (Exception ex)
                    {
                        reply = Serialize(new Reply { Error = ex.Message });
                    }
                    transfer.Restart();
                    WriteFrame(pipe, reply, checkTransfer);
                }
                return 0;
            }
            catch (Exception) { return 1; }
        }

        private static void Validate(ExcelRequest request)
        {
            bool range = request.Mode == "RowRange" || request.Mode == "ColumnRange";
            bool line = request.Mode == "Row" || request.Mode == "Column";
            if ((!range && !line && request.Mode != "Cell") ||
                !Path.IsPathRooted(request.Path) ||
                !string.Equals(Path.GetFullPath(request.Path), request.Path, StringComparison.OrdinalIgnoreCase) ||
                !Regex.IsMatch(request.MutexName, @"\ALocal\\RMT\.Excel\.[0-9A-F]{32}\z") ||
                !((request.Sheet is string && ((string)request.Sheet).Length <= 255) ||
                    (request.Sheet is int && (int)request.Sheet > 0)) ||
                request.Row < 1 || request.Row > MaxRows || request.Col < 1 || request.Col > MaxCols ||
                request.EndRow < request.Row || request.EndRow > MaxRows ||
                request.EndCol < request.Col || request.EndCol > MaxCols ||
                request.Cells == null || request.Cells.Length % 3 != 0 ||
                (request.Write && !range && request.Cells.Length != 3) ||
                (!request.Write && request.Cells.Length != 0))
                throw new InvalidDataException("Excel 提权请求无效");

            for (int i = 0; i < request.Cells.Length; i += 3)
            {
                object value = request.Cells[i + 2];
                if (!(request.Cells[i] is int) || (int)request.Cells[i] < 0 ||
                    (int)request.Cells[i] > MaxRows - request.Row ||
                    !(request.Cells[i + 1] is int) || (int)request.Cells[i + 1] < 0 ||
                    (int)request.Cells[i + 1] > MaxCols - request.Col ||
                    !(value is string || value is int || value is long || value is double || value is bool))
                    throw new InvalidDataException("Excel 提权请求无效");
            }
        }

        private static byte[] Serialize<T>(T value)
        {
            using (var stream = new MemoryStream())
            {
                using (var writer = XmlDictionaryWriter.CreateBinaryWriter(stream, null, null, false))
                    new DataContractSerializer(typeof(T)).WriteObject(writer, value);
                if (stream.Length > MaxFrameSize)
                    throw new IOException("Excel 提权请求或结果过大");
                return stream.ToArray();
            }
        }

        private static T ReadFrame<T>(PipeStream pipe, Action check)
        {
            int size = BitConverter.ToInt32(ReadBytes(pipe, 4, check), 0);
            if (size <= 0 || size > MaxFrameSize)
                throw new InvalidDataException("Excel 提权请求或结果过大");
            var data = ReadBytes(pipe, size, check);
            var quotas = new XmlDictionaryReaderQuotas
            {
                MaxDepth = 16, MaxArrayLength = MaxFrameSize, MaxStringContentLength = MaxFrameSize
            };
            using (var reader = XmlDictionaryReader.CreateBinaryReader(data, quotas))
                return (T)new DataContractSerializer(typeof(T)).ReadObject(reader);
        }

        private static byte[] ReadBytes(PipeStream pipe, int length, Action check)
        {
            var data = new byte[length];
            int offset = 0;
            while (offset < length)
            {
                var read = pipe.ReadAsync(data, offset, length - offset);
                Wait(read, check);
                if (read.Result == 0)
                    throw new EndOfStreamException("Excel 提权助手连接已断开");
                offset += read.Result;
            }
            return data;
        }

        private static void WriteFrame(PipeStream pipe, byte[] data, Action check)
        {
            var header = BitConverter.GetBytes(data.Length);
            Wait(pipe.WriteAsync(header, 0, header.Length), check);
            Wait(pipe.WriteAsync(data, 0, data.Length), check);
        }

        private static void Wait(Task task, Action check)
        {
            while (!task.IsCompleted)
            {
                check();
                Thread.Sleep(25);
            }
            check();
            task.GetAwaiter().GetResult();
        }
    }
}
