    _BuildStatusBar(main) {
        status := main.Add("Grid").Grid_Row(2).Grid_ColumnSpan(2).Background("{DynamicResource TitleBarColor}")
        status.Cols("*", "Auto")
        stats := status.Add("Grid").VerticalAlignment("Stretch").Margin("6,0,0,0")
        stats.Cols(104, 104, 104, "*")
        this._AddStatusMetric(stats, "StatusCpu", "CPU", 0)
        this._AddStatusMetric(stats, "StatusGpu", "GPU", 1)
        this._AddStatusMetric(stats, "StatusMemory", GetLang("内存"), 2)
        statusButtons := status.Add("StackPanel").Grid_Column(1).Orientation("Horizontal").VerticalAlignment("Center")
        statusButtons.Add("Button").Name("StatusDownloads").Content(GetLang("下载") " 0")
            .Width(82).Height(24).MinHeight(24).Padding("8,0").Margin("0,0,4,0")
        statusButtons.Add("Button").Name("StatusNotifications").Content(GetLang("通知") " 0")
            .Width(82).Height(24).MinHeight(24).Padding("8,0").Margin("0,0,8,0")

        ; ---- 底栏资源明细浮层 ----
        ; 是窗口内的子控件，不是 Popup：跟着窗口一起移动，切到别的窗口也不会消失。
        ; 位置由引擎按被钉住的指标实时算（见 AnchoredPanel.cs），这里只留一个空壳。
        detailLayer := main.Add("Grid").Grid_Row(0).Grid_RowSpan(3).Grid_Column(0).Grid_ColumnSpan(2)
            .IsHitTestVisible("False").Panel_ZIndex(30)
        detailBox := detailLayer.Add("Border").Name("StatusDetail").Visibility("Collapsed")
            .HorizontalAlignment("Left").VerticalAlignment("Bottom").MaxWidth(460)
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource OutlineStroke}")
            .BorderThickness("1").CornerRadius("4").Padding("10,7").IsHitTestVisible("False")
        detailBox.Add("TextBlock").Name("StatusDetailText").Text("").Foreground("{DynamicResource TextMain}")
            .TextWrapping("Wrap")
    }

    ; 底栏读数、资源明细、悬停与钉住都在引擎进程里（Plugins/AHK-XAML/lib/dep/src/StatusBarHost.cs）：
    ; 采样走 PDH + Toolhelp，跑在后台线程，不再经过 AHK 的定时器与批量更新。
    ; AHK 只推两样，都不涉及持久化：启动、下载/通知计数与运行中宏的标签。
    _StartStatusBar(*) {
        if (this.closed || !IsObject(this.ui))
            return
        this.ui.Update("Window", "StatusBarStart", "")
        ; 计数与标签没有变更通知，1 秒轮询一次，只在变化时推；稳态下不发任何指令
        this._statusCounterTimer := ObjBindMethod(this, "_PushStatusCounters")
        this._PushStatusCounters()
        SetTimer(this._statusCounterTimer, 1000)
    }

    ; 引擎在窗口 Closed 时自己停采样。这里不能再同步投递指令：
    ; OnWindowClosing 是从引擎的 Closing 回调里进来的，此刻 SendMessage 会和引擎互相等待。
    _StopStatusBar() {
        if (this.HasOwnProp("_statusCounterTimer"))
            SetTimer(this._statusCounterTimer, 0)
    }

    _PushStatusCounters(*) {
        if (this.closed || !IsObject(this.ui))
            return
        active := 0
        for job in RmtDownloadManager.Snapshot()
            if (job.status == "queued" || job.status == "downloading")
                active++
        counters := active "|" RmtNotifications.unread
        if (counters != (this.HasOwnProp("_statusCounterSig") ? this._statusCounterSig : "")) {
            this._statusCounterSig := counters
            this.ui.Update("Window", "StatusBarCounts", counters)
        }

        ; 宏标签随 Worker 启停变化，签名不变就不推，避免每秒一条 IPC。
        ; 载荷以 | 分项、= 分键值，标签里的同名字符会把结构拆坏，先替换掉。
        signature := ""
        for pid, label in this._StatusMacroLabels() {
            if (signature != "")
                signature .= "|"
            signature .= pid "=" StrReplace(StrReplace(label, "|", " "), "=", " ")
        }
        if (signature != (this.HasOwnProp("_statusLabelSig") ? this._statusLabelSig : "")) {
            this._statusLabelSig := signature
            this.ui.Update("Window", "StatusBarLabels", signature)
        }
    }

    ; Worker 正在跑宏时给出「宏类型-模块名-宏名」标注，pid -> 标签
    _StatusMacroLabels() {
        global MyWorkPool
        labels := Map()
        if (!IsSet(MyWorkPool) || !IsObject(MyWorkPool))
            return labels
        for index, worker in MyWorkPool.workerMap {
            if (!worker.pid || worker.tableID == "" || worker.itemID == "")
                continue
            table := GetTableByID(worker.tableID)
            if (!table)
                continue
            item := table.GetItem(worker.itemID)
            macroName := (IsObject(item) && item.Remark != "") ? item.Remark
                : (IsObject(item) && item.TK != "") ? item.TK : ""
            label := this._StatusTableTypeName(table.Symbol) "-" table.Name
            if (macroName != "")
                label .= "-" macroName
            labels[worker.pid] := label
        }
        return labels
    }

    _StatusTableTypeName(symbol) {
        for entry in MacroCategoryDefs()
            if (entry[1] == symbol)
                return GetLang(entry[2])
        return symbol
    }

    _OpenStatusDownloads(*) {
        SetTimer(() => DownloadManagerGui.Open(), -1)
    }

    _OpenStatusNotifications(*) {
        SetTimer(() => RmtNotifications.Open(), -1)
    }

    ; 底栏指标：文字与饼图作为整体点击，选中时高亮并固定明细。
    ; 选中态不用动态样式与触发器：底色是独立一层 Border，只切 Visibility。
    ; 运行时给 Background 传画刷要走反射 + 类型转换，能给 DynamicResource 的只有建窗期。
    ; 明细不在这里建：它是窗口内的锚定浮层 StatusDetail（见 MainWindowXaml），不是 Popup。
    ; 悬停/点击由引擎直接接管容器上的鼠标事件，AHK 不再绑定。
    _AddStatusMetric(parent, name, text, column) {
        box := parent.Add("Grid").Name(name "Box").Grid_Column(column).VerticalAlignment("Stretch")
            .Margin("0,0,8,0").Background("Transparent").Cursor("Hand")
        box.Add("Border").Name(name "Sel").Background("{DynamicResource Accent}").Opacity("0.22")
            .CornerRadius("4").Margin("0,3").Visibility("Collapsed").IsHitTestVisible("False")
        ; 文字与图标都不吃鼠标：命中统一落在容器上，整块区域行为一致
        row := box.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")
            .Margin("6,0").IsHitTestVisible("False")
        row.Add("TextBlock").Name(name).Text(text).Margin("0").VerticalAlignment("Center")
            .Foreground("{DynamicResource TextMain}")
        pie := row.Add("Grid").Width(18).Height(18).Margin("2,0,0,0").VerticalAlignment("Center")
        ; 整圆代表全部资源：蓝色 RMT、系统占用按负载渐变、灰色剩余资源。
        pie.Add("Ellipse").Fill("#CBD5E1")
        pie.Add("Path").Name(name "SystemPie").Fill("#22C55E")
        pie.Add("Path").Name(name "RmtPie").Fill("#3B82F6")
    }
