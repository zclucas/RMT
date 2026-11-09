using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace RMT
{
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.AutoDual)]
    public sealed class ExcelEditor
    {
        private enum Mode { Cell, Row, Column, RowRange, ColumnRange }

        // An unresponsive Excel call can outlive the macro. Bound the number of
        // outstanding STA threads per process, even after the caller stops waiting.
        private static int busy;
        private volatile int state;
        private volatile bool waitingForElevation;
        private int writePhase;
        private string error = "";
        private string[] result;
        private bool lookupDenied;
        private Action checkConnection;

        private sealed class ElevationRequired : Exception { }

        public bool Begin(string path, string mutexName, object sheetIdentifier,
            string mode, bool write, int row, int col, int endRow, int endCol, object[] cells)
        {
            var request = new ExcelRequest
            {
                Path = path, MutexName = mutexName, Sheet = sheetIdentifier, Mode = mode,
                Write = write, Row = row, Col = col, EndRow = endRow, EndCol = endCol, Cells = cells
            };
            if (state != 0 || Interlocked.CompareExchange(ref busy, 1, 0) != 0)
                return false;

            state = 1;
            try
            {
                var worker = new Thread(() =>
                {
                    int finalState = 2;
                    try
                    {
                        // Keep the caller's mutex object alive while the helper
                        // works. Release ownership before waiting for UAC.
                        using (var mutex = new Mutex(false, request.MutexName))
                        {
                            try
                            {
                                Execute(request, false, mutex);
                            }
                            catch (ElevationRequired)
                            {
                                CheckCancelled();
                                result = ExcelElevation.Run(request, CheckCancelled, waiting => waitingForElevation = waiting);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        error = ex.Message;
                        finalState = 3;
                    }
                    finally
                    {
                        Interlocked.Exchange(ref busy, 0);
                        state = finalState;
                    }
                });
                worker.IsBackground = true;
                worker.SetApartmentState(ApartmentState.STA);
                worker.Start();
                return true;
            }
            catch
            {
                Interlocked.Exchange(ref busy, 0);
                throw;
            }
        }

        public int GetState() { return state; }
        public bool IsWaitingForElevation() { return waitingForElevation; }
        public string GetError() { return error; }
        public string[] GetResult() { return result; }

        // The legacy AHK path shares the running-workbook lookup, then uses its
        // existing COM operations. The returned workbook belongs to the user.
        [return: MarshalAs(UnmanagedType.IDispatch)]
        public object FindOpenWorkbook(string path)
        {
            return ExcelWorkbookLookup.Find(path, CheckCancelled, out lookupDenied);
        }

        public string GetOpenWorkbookError()
        {
            return lookupDenied || ExcelWorkbookLookup.HasHigherIntegrityExcel()
                ? ExcelWorkbookLookup.AccessDenied : "";
        }

        public bool NeedsElevationForLockedWorkbook(string path)
        {
            if (ExcelWorkbookLookup.IsElevated() || GetOpenWorkbookError().Length == 0)
                return false;
            try
            {
                using (File.Open(path, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite | FileShare.Delete))
                {
                    return false;
                }
            }
            catch (IOException ex)
            {
                // A write lock held by an inaccessible Excel instance can
                // otherwise open a modal prompt in the legacy file binding.
                int code = ex.HResult;
                return code == unchecked((int)0x80070020) || code == unchecked((int)0x80070021);
            }
            catch (UnauthorizedAccessException) { return false; }
        }

        public void Cancel()
        {
            Interlocked.CompareExchange(ref writePhase, 2, 0);
        }

        private void CheckCancelled()
        {
            if (Volatile.Read(ref writePhase) == 2)
                throw new OperationCanceledException();
            if (Volatile.Read(ref writePhase) == 0 && checkConnection != null)
                checkConnection();
        }

        internal string[] ExecuteElevated(ExcelRequest request, Action checkConnection)
        {
            this.checkConnection = checkConnection;
            using (var mutex = new Mutex(false, request.MutexName))
                Execute(request, true, mutex);
            return result;
        }

        private void Execute(ExcelRequest request, bool elevatedOnly, Mutex mutex)
        {
            Mode operation = (Mode)Enum.Parse(typeof(Mode), request.Mode);
            WithWorkbook(request.Path, mutex, request.Sheet, request.Write, elevatedOnly, sheet =>
            {
                if (request.Write)
                    Write(sheet, operation, request.Row, request.Col, request.Cells);
                else
                    result = Read(sheet, operation, request.Row, request.Col, request.EndRow, request.EndCol);
            });
        }

        private void WithWorkbook(string path, Mutex mutex, object sheetIdentifier,
            bool write, bool elevatedOnly, Action<object> edit)
        {
            // Use the same workbook mutex as the AHK backend, and retain it
            // through close/quit even if the macro times out.
            bool acquired = false;
            try
            {
                for (int i = 0; i < 200 && !acquired; i++)
                {
                    CheckCancelled();
                    try { acquired = mutex.WaitOne(100); }
                    catch (AbandonedMutexException) { acquired = true; }
                }
                if (!acquired)
                    throw new IOException("无法锁定工作簿");

                CheckCancelled();
                EditWorkbook(path, sheetIdentifier, write, elevatedOnly, edit);
            }
            finally
            {
                if (acquired)
                    mutex.ReleaseMutex();
            }
        }

        private void EditWorkbook(string path, object sheetIdentifier, bool write, bool elevatedOnly, Action<object> edit)
        {
            dynamic app = null, books = null, book = null, sheets = null, sheet = null;
            bool ownsApp = false;
            try
            {
                book = ExcelWorkbookLookup.Find(path, CheckCancelled, out lookupDenied, elevatedOnly);
                if ((object)book == null)
                {
                    if (elevatedOnly)
                        throw new IOException("目标工作簿未在管理员权限的 Excel 中打开");
                    if (!File.Exists(path))
                        throw new FileNotFoundException("找不到工作簿");
                    if (NeedsElevationForLockedWorkbook(path))
                        throw new ElevationRequired();
                    var excelType = Type.GetTypeFromProgID("Excel.Application");
                    if (excelType == null)
                        throw new InvalidOperationException("需要安装 Microsoft Excel");

                    app = Activator.CreateInstance(excelType);
                    books = app.Workbooks;
                    if (app.Visible || app.UserControl || books.Count != 0)
                        throw new InvalidOperationException("无法启动独立的 Excel 实例");
                    ownsApp = true;
                    app.DisplayAlerts = false;
                    app.EnableEvents = false;
                    app.AutomationSecurity = 3; // msoAutomationSecurityForceDisable
                    CheckCancelled();
                    try
                    {
                        book = books.Open(path, 0, !write, Type.Missing, "", "", true,
                            Type.Missing, Type.Missing, true, false, Type.Missing, false);
                    }
                    catch (COMException ex)
                    {
                        if (NeedsElevationForLockedWorkbook(path))
                            throw new ElevationRequired();
                        string accessError = write ? GetOpenWorkbookError() : "";
                        if (accessError.Length != 0)
                            throw new IOException(ex.Message + Environment.NewLine + accessError, ex);
                        throw;
                    }
                }
                CheckCancelled();
                if (write && book.ReadOnly)
                {
                    if (NeedsElevationForLockedWorkbook(path))
                        throw new ElevationRequired();
                    string accessError = ownsApp ? GetOpenWorkbookError() : "";
                    throw new IOException(accessError.Length != 0
                        ? "工作簿为只读" + Environment.NewLine + accessError : "工作簿为只读");
                }

                sheets = book.Sheets;
                sheet = sheets[sheetIdentifier];
                if (!write)
                {
                    if (ownsApp)
                        app.Calculate();
                    else
                        sheet.Calculate();
                }

                // Live changes become visible immediately. Let the operation
                // finish after it starts editing cells.
                if (write && !ownsApp)
                    StartWrite();
                edit((object)sheet);
                if (write)
                {
                    if (ownsApp)
                        StartWrite();
                    book.Save();
                }
            }
            finally
            {
                Release((object)sheet);
                Release((object)sheets);
                try { if (ownsApp && (object)book != null) book.Close(false); }
                catch (COMException) { }
                finally
                {
                    Release((object)book);
                    Release((object)books);
                    try { if (ownsApp) app.Quit(); }
                    catch (COMException) { }
                    finally { Release((object)app); }
                }
            }
        }

        private void StartWrite()
        {
            CheckCancelled();
            if (Interlocked.CompareExchange(ref writePhase, 1, 0) != 0)
                throw new OperationCanceledException();
        }

        private string[] Read(dynamic sheet, Mode mode, int row, int col, int endRow, int endCol)
        {
            var values = new List<string>();
            dynamic cells = sheet.Cells;
            try
            {
                if (mode == Mode.Row || mode == Mode.Column)
                {
                    bool byRow = mode == Mode.Row;
                    int count = LineLength(sheet, byRow, row, col);
                    int empty = 0;
                    for (int i = 0; i < count; i++)
                    {
                        string value = ReadCell(cells, row + (byRow ? 0 : i), col + (byRow ? i : 0));
                        empty = value.Length == 0 ? empty + 1 : 0;
                        if (empty == 5)
                            break;
                        values.Add(value);
                    }
                    if (empty > 0)
                        values.RemoveRange(values.Count - Math.Min(empty, 4), Math.Min(empty, 4));
                }
                else
                {
                    bool byRow = mode != Mode.ColumnRange;
                    int rowCount = endRow - row + 1, colCount = endCol - col + 1;
                    for (int i = 0; i < (byRow ? rowCount : colCount); i++)
                        for (int j = 0; j < (byRow ? colCount : rowCount); j++)
                            values.Add(ReadCell(cells, row + (byRow ? i : j), col + (byRow ? j : i)));
                }
                return values.ToArray();
            }
            finally { Release((object)cells); }
        }

        private string ReadCell(dynamic cells, int row, int col)
        {
            CheckCancelled();
            dynamic cell = cells[row, col];
            dynamic area = null, first = null;
            try
            {
                if ((bool)cell.MergeCells)
                {
                    area = cell.MergeArea;
                    first = area[1, 1];
                    return (string)first.Text;
                }
                return (string)cell.Text;
            }
            finally
            {
                Release((object)first);
                Release((object)area);
                Release((object)cell);
            }
        }

        private void Write(dynamic sheet, Mode mode, int row, int col, object[] values)
        {
            dynamic cells = sheet.Cells;
            try
            {
                if (mode == Mode.Row || mode == Mode.Column)
                {
                    // For writes, Row/Column select the dimension that increments.
                    bool advanceRow = mode == Mode.Row;
                    int count = LineLength(sheet, !advanceRow, row, col);
                    for (int i = 0; i < count; i++)
                    {
                        CheckCancelled();
                        dynamic cell = cells[row + (advanceRow ? i : 0), col + (advanceRow ? 0 : i)];
                        try
                        {
                            object current = cell.Value2;
                            if (current == null || "".Equals(current))
                            {
                                cell.Value[Type.Missing] = values[2];
                                return;
                            }
                        }
                        finally { Release((object)cell); }
                    }
                    throw new IOException("没有可写入的空单元格");
                }

                for (int i = 0; i < values.Length; i += 3)
                {
                    CheckCancelled();
                    dynamic cell = cells[row + (int)values[i], col + (int)values[i + 1]];
                    try { cell.Value[Type.Missing] = values[i + 2]; }
                    finally { Release((object)cell); }
                }
            }
            finally { Release((object)cells); }
        }

        private static int LineLength(dynamic sheet, bool byRow, int row, int col)
        {
            dynamic line = byRow ? sheet.Columns : sheet.Rows;
            try { return (int)line.Count - (byRow ? col : row) + 1; }
            finally { Release((object)line); }
        }

        internal static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                Marshal.ReleaseComObject(value);
        }
    }
}
