using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace RMT
{
    // Transport only: JSON-RPC methods, schemas and permissions stay in AHK.
    public sealed class AiMcpTransport : IDisposable
    {
        private Process _process;
        private readonly ConcurrentQueue<string> _lines = new ConcurrentQueue<string>();
        private readonly object _sync = new object();
        private string _error = "";
        private int _generation;

        public void Start(string executable, string arguments, string directory, string workRoot, string outputRoot)
        {
            Stop();
            int generation = _generation;
            var info = new ProcessStartInfo(executable, arguments ?? "") {
                WorkingDirectory = directory, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            info.EnvironmentVariables["RMT_MCP_WORK_ROOT"] = workRoot;
            info.EnvironmentVariables["RMT_MCP_OUTPUT_ROOT"] = outputRoot;
            var process = new Process { StartInfo = info };
            process.OutputDataReceived += (s, e) => {
                if (generation != _generation) return;
                if (e.Data == null) return;
                if (e.Data.Length > 1048576) { SetError("MCP response exceeds 1 MB"); return; }
                if (_lines.Count < 64) _lines.Enqueue(e.Data);
                else SetError("MCP response queue overflow");
            };
            process.ErrorDataReceived += (s, e) => { if (generation == _generation && !string.IsNullOrEmpty(e.Data)) SetError(e.Data); };
            if (!process.Start()) throw new IOException("Cannot start MCP server");
            _process = process;
            process.StandardInput.AutoFlush = true;
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
        }

        private void SetError(string error) { lock (_sync) _error = error.Length > 2000 ? error.Substring(0, 2000) : error; }
        public string Error() { lock (_sync) return _error; }
        public bool Running() { try { return _process != null && !_process.HasExited; } catch { return false; } }
        public string TakeLine() { string line; return _lines.TryDequeue(out line) ? line : ""; }
        public void Send(string json)
        {
            if (!Running()) throw new IOException("MCP server is not running");
            if (json.IndexOfAny(new[] { '\r', '\n' }) >= 0) throw new ArgumentException("MCP message must be a single JSON line");
            _process.StandardInput.WriteLine(json);
        }

        public void Stop()
        {
            System.Threading.Interlocked.Increment(ref _generation);
            var process = _process;
            _process = null;
            if (process != null) {
                try { process.StandardInput.Close(); } catch { }
                try { if (!process.WaitForExit(500)) process.Kill(); } catch { }
                process.Dispose();
            }
            string line;
            while (_lines.TryDequeue(out line)) { }
            lock (_sync) _error = "";
        }
        public void Dispose() { Stop(); }
    }
}
