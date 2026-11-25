#Requires AutoHotkey v2.0

; 绑定已打开的 Excel 文档窗口，不启动 Excel、不自动保存工作簿。
class ControlExcel {
    static Window(hwnd, x := "", y := "") {
        if (StrLower(WinGetProcessName(hwnd)) != "excel.exe")
            return 0
        for pane in WinGetControlsHwnd(hwnd) {
            if (WinGetClass(pane) != "EXCEL7")
                continue
            if (x != "") {
                WinGetPos(&left, &top, &width, &height, "ahk_id " pane)
                if (x < left || x >= left + width || y < top || y >= top + height)
                    continue
            }
            iid := Buffer(16), ptr := 0
            DllCall("ole32\IIDFromString", "WStr", "{00020400-0000-0000-C000-000000000046}", "Ptr", iid)
            if (DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", pane, "UInt", 0xFFFFFFF0,
                "Ptr", iid, "Ptr*", &ptr, "HRESULT") >= 0 && ptr)
                return ComValue(9, ptr, 1)
        }
        return 0
    }

    static FromPoint(hwnd, x, y) {
        try {
            window := this.Window(hwnd, x, y)
            if (!window)
                return 0
            range := window.RangeFromPoint(x, y)
            cell := range.Cells.Item(1, 1)
            return ExcelControlTarget(hwnd, window, cell)
        }
        return 0
    }

    static FromElement(element) {
        if (element is ExcelControlTarget)
            return element
        try {
            type := WindowControl._Int(element, 21)
            if (type != 50029 && type != 50025 && type != 50020)
                return 0
            hwnd := WindowControl._ElementWindow(element)
            if (StrLower(WinGetProcessName(hwnd)) != "excel.exe")
                return 0
            bounds := WindowControl._Bounds(element)
            if (bounds.right <= bounds.left || bounds.bottom <= bounds.top)
                return 0
            ; 只将 Excel 单元格语义的控件交给 COM，排除功能区、整张表等区域。
            return this.FromPoint(hwnd, Floor((bounds.left + bounds.right) / 2), Floor((bounds.top + bounds.bottom) / 2))
        }
        return 0
    }

    static Find(hwnd, metadata) {
        try {
            window := this.Window(hwnd)
            if (!window)
                return 0
            book := window.ActiveSheet.Parent
            if (!(book.FullName == metadata["workbook"]))
                return 0
            sheet := book.Worksheets.Item(metadata["sheet"])
            range := sheet.Range(metadata["address"])
            if (range.Cells.CountLarge != 1)
                return 0
            return ExcelControlTarget(hwnd, window, range)
        }
        return 0
    }
}

class ExcelControlTarget {
    __New(hwnd, window, range) {
        this.hwnd := hwnd, this.window := window, this.range := range.MergeArea.Cells.Item(1, 1)
    }

    Metadata() => Map("workbook", this.range.Worksheet.Parent.FullName,
        "sheet", this.range.Worksheet.Name, "address", this.range.Address[false, false, 1])

    Name() => this.range.Worksheet.Name "!" this.range.Address[false, false, 1]

    Writable() => !(this.range.Worksheet.ProtectContents && this.range.Locked)

    Read() {
        value := this.range.Value2
        try {
            String(value)
            return {supported: true, value: value, kind: GetLang("Excel单元格"),
                category: IsNumber(value) ? "number" : "text", reason: ""}
        }
        catch
            return {supported: true, value: this.range.Text, kind: GetLang("Excel单元格"), category: "text", reason: ""}
    }

    Write(value) {
        if (!this.Writable())
            throw Error(GetLang("Excel 单元格已保护，无法修改。"))
        if (SubStr(value, 1, 1) == "=")
            this.range.Formula := value
        else
            this.range.Value2 := value
        return value
    }

    Reveal() {
        this.window.Activate()
        this.range.Worksheet.Activate()
        this.range.Application.Goto(this.range, true)
    }

    Bounds() {
        if (!(this.window.ActiveSheet.Name == this.range.Worksheet.Name))
            return {left: 0, top: 0, right: 0, bottom: 0}
        cell := this.range.MergeArea
        ; 冻结/拆分窗格分别拥有滚动原点，窗口级换算会把单元格投影到错误位置。
        loop this.window.Panes.Count {
            pane := this.window.Panes.Item(A_Index)
            if (!IsObject(this.range.Application.Intersect(cell, pane.VisibleRange)))
                continue
            return {left: pane.PointsToScreenPixelsX(cell.Left), top: pane.PointsToScreenPixelsY(cell.Top),
                right: pane.PointsToScreenPixelsX(cell.Left + cell.Width), bottom: pane.PointsToScreenPixelsY(cell.Top + cell.Height)}
        }
        return {left: 0, top: 0, right: 0, bottom: 0}
    }

    Offscreen() {
        if (!(this.window.ActiveSheet.Name == this.range.Worksheet.Name))
            return true
        try return !IsObject(this.range.Application.Intersect(this.range, this.window.VisibleRange))
        catch
            return true
    }

    Offset(pixels) {
        rows := Round(Abs(pixels) / Max(1, this.range.Height * A_ScreenDPI / 72))
        if (pixels)
            this.window.SmallScroll(pixels > 0 ? Max(1, rows) : 0, pixels < 0 ? Max(1, rows) : 0)
    }
}
