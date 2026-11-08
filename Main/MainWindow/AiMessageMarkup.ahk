
    _AiMdBodyXaml(text, fg, preserveLines := false) {
        if (preserveLines)
            return this._AiPreserveLinesXaml(text, fg)
        out := ""
        for blk in this._AiParseMd(text)
            out .= this._AiMdBlockXaml(blk, fg)
        if (out == "")
            out := this._AiMdParagraph(text, fg, this._AiChatBodyFontSize(), "0,0,0,0")
        return out
    }

    ; 用户输入按原文换行展示，不按 Markdown 把相邻行拼成一段
    _AiPreserveLinesXaml(text, fg) {
        raw := this._AiNormalizeNewlines(text, false)
        fs := this._AiChatBodyFontSize()
        lh := this._AiUserPreviewLineH()
        out := ""
        for line in StrSplit(raw, "`n")
            out .= '<Paragraph Margin="0,0,0,0" LineHeight="' lh '" LineStackingStrategy="BlockLineHeight"'
                . ' FontSize="' fs '" Foreground="' fg '">' this._AiInlineXaml(line, fg) '</Paragraph>'
        if (out == "")
            out .= '<Paragraph Margin="0,0,0,0" LineHeight="' lh '" LineStackingStrategy="BlockLineHeight"'
                . ' FontSize="' fs '" Foreground="' fg '">' this._AiMdRun("", ' Foreground="' fg '"') '</Paragraph>'
        return out
    }

    _AiParseMd(text) {
        blocks := []
        raw := this._AiNormalizeNewlines(text, false)
        lines := StrSplit(raw, "`n")
        fence := Chr(96) Chr(96) Chr(96)
        i := 1
        n := lines.Length
        while (i <= n) {
            line := lines[i]
            if (Trim(line) == "") {
                i++
                continue
            }
            tline := Trim(line)
            if (SubStr(tline, 1, 3) == fence) {
                lang := Trim(SubStr(tline, 4))
                body := ""
                i++
                while (i <= n && SubStr(Trim(lines[i]), 1, 3) != fence) {
                    body .= (body == "" ? "" : "`n") lines[i]
                    i++
                }
                blocks.Push(Map("type", "code", "lang", lang, "text", body))
                i++
                continue
            }
            if (this._AiLooksTable(line) && i < n && this._AiLooksTableSep(lines[i + 1])) {
                rows := []
                while (i <= n && this._AiLooksTable(lines[i])) {
                    if (!this._AiLooksTableSep(lines[i]))
                        rows.Push(this._AiTableCells(lines[i]))
                    i++
                }
                blocks.Push(Map("type", "table", "rows", rows))
                continue
            }
            if (RegExMatch(line, "^(#{1,3})\s+(.+)$", &mh)) {
                blocks.Push(Map("type", "h", "level", StrLen(mh[1]), "text", mh[2]))
                i++
                continue
            }
            if (RegExMatch(tline, "^([-*_])\1{2,}$")) {
                blocks.Push(Map("type", "hr"))
                i++
                continue
            }
            if (RegExMatch(line, "^>\s?(.*)$", &mq)) {
                q := mq[1]
                i++
                while (i <= n && RegExMatch(lines[i], "^>\s?(.*)$", &mq2)) {
                    q .= "`n" mq2[1]
                    i++
                }
                blocks.Push(Map("type", "quote", "text", q))
                continue
            }
            if (RegExMatch(line, "^[-*+]\s+(.+)$", &mu)) {
                items := [mu[1]]
                i++
                while (i <= n && RegExMatch(lines[i], "^[-*+]\s+(.+)$", &mu2)) {
                    items.Push(mu2[1])
                    i++
                }
                blocks.Push(Map("type", "ul", "items", items))
                continue
            }
            if (RegExMatch(line, "^\d+[.)]\s+(.+)$", &mo)) {
                items := [mo[1]]
                i++
                while (i <= n && RegExMatch(lines[i], "^\d+[.)]\s+(.+)$", &mo2)) {
                    items.Push(mo2[1])
                    i++
                }
                blocks.Push(Map("type", "ol", "items", items))
                continue
            }
            para := line
            i++
            while (i <= n && !this._AiMdBreak(lines[i]) && !this._AiMdKeepLine(para, lines[i])) {
                para .= " " Trim(lines[i])
                i++
            }
            blocks.Push(Map("type", "p", "text", para))
        }
        return blocks
    }

    ; 上一行已是完整句，或下一行是路径/目标，不要拼成一段（避免「评分」被从中间折开）
    _AiMdKeepLine(prev, nextLine) {
        next := Trim(nextLine)
        if (next == "")
            return true
        if (RegExMatch(Trim(prev), "[。！？.!?」』]$"))
            return true
        if (RegExMatch(next, "^(目标：|写入失败|请到|路径：)"))
            return true
        if (RegExMatch(next, "^[A-Za-z]:[\\/]") || InStr(next, "\Desktop\") || InStr(next, "/Desktop/"))
            return true
        return false
    }

    _AiMdBreak(line) {
        if (Trim(line) == "")
            return true
        tline := Trim(line)
        fence := Chr(96) Chr(96) Chr(96)
        if (SubStr(tline, 1, 3) == fence)
            return true
        if (RegExMatch(line, "^(#{1,3})\s+"))
            return true
        if (RegExMatch(line, "^[-*+]\s+"))
            return true
        if (RegExMatch(line, "^\d+[.)]\s+"))
            return true
        if (RegExMatch(line, "^>\s?"))
            return true
        if (this._AiLooksTable(line))
            return true
        if (RegExMatch(tline, "^([-*_])\1{2,}$"))
            return true
        return false
    }

    _AiLooksTable(line) {
        return SubStr(Trim(line), 1, 1) == "|"
    }

    _AiLooksTableSep(line) {
        return RegExMatch(Trim(line), "^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$")
    }

    _AiTableCells(line) {
        s := Trim(line)
        if (SubStr(s, 1, 1) == "|")
            s := SubStr(s, 2)
        if (s != "" && SubStr(s, -1) == "|")
            s := SubStr(s, 1, StrLen(s) - 1)
        cells := []
        for part in StrSplit(s, "|")
            cells.Push(Trim(part))
        return cells
    }

    _AiMdBlockXaml(blk, fg) {
        tp := blk["type"]
        if (tp == "h") {
            fs := blk["level"] == 1 ? 16 : (blk["level"] == 2 ? 14 : 13)
            return this._AiMdParagraph(blk["text"], fg, fs, "0,2,0,6", true)
        }
        if (tp == "p")
            return this._AiMdParagraph(blk["text"], fg, this._AiChatBodyFontSize(), "0,0,0,6")
        if (tp == "hr")
            return '<BlockUIContainer><Rectangle Height="1" Fill="{DynamicResource ControlBorder}" Margin="0,8" HorizontalAlignment="Stretch"/></BlockUIContainer>'
        if (tp == "quote")
            return '<BlockUIContainer><Border BorderThickness="2,0,0,0" BorderBrush="{DynamicResource Accent}" Padding="8,2,0,2" Margin="0,2,0,8">'
                . '<TextBlock TextWrapping="Wrap" FontSize="' this._AiChatBodyFontSize() '" Foreground="' fg '" Opacity="0.9">' this._AiInlineXaml(blk["text"], fg) '</TextBlock>'
                . '</Border></BlockUIContainer>'
        if (tp == "code") {
            head := blk["lang"] != "" ? '<TextBlock Text="' this._XmlEsc(blk["lang"]) '" FontSize="' this._AiChatSmallFontSize() '" Margin="0,0,0,4" Foreground="{DynamicResource TextSub}"/>' : ""
            return '<BlockUIContainer><Border Background="{DynamicResource ListAltBg}" CornerRadius="4" Padding="8,6" Margin="0,2,0,8">'
                . '<StackPanel>' head
                . '<TextBlock Text="' this._XmlEsc(blk["text"]) '" FontFamily="Consolas, Cascadia Mono, Courier New" FontSize="' this._AiChatSmallFontSize() '"'
                . ' TextWrapping="Wrap" Foreground="{DynamicResource TextMain}" xml:space="preserve"/>'
                . '</StackPanel></Border></BlockUIContainer>'
        }
        if (tp == "ul" || tp == "ol") {
            out := ""
            idx := 1
            for it in blk["items"] {
                mark := tp == "ol" ? (idx ". ") : "• "
                out .= '<Paragraph Margin="0,1,0,1" FontSize="' this._AiChatBodyFontSize() '" Foreground="' fg '">'
                    . '<Run Text="' this._XmlEsc(mark) '"/>' this._AiInlineXaml(it, fg)
                    . '</Paragraph>'
                idx++
            }
            return out
        }
        if (tp == "table")
            return '<BlockUIContainer>' this._AiMdTableXaml(blk["rows"], fg) '</BlockUIContainer>'
        return this._AiMdParagraph(blk.Has("text") ? blk["text"] : "", fg, this._AiChatBodyFontSize(), "0,0,0,0")
    }

    _AiMdTableXaml(rows, fg) {
        if (rows.Length < 1)
            return ""
        cols := 1
        for row in rows {
            if (row.Length > cols)
                cols := row.Length
        }
        colDef := ""
        loop cols
            colDef .= '<ColumnDefinition Width="Auto"/>'
        rowDef := ""
        loop rows.Length
            rowDef .= '<RowDefinition Height="Auto"/>'
        cells := ""
        r := 0
        for row in rows {
            c := 0
            bg := r == 0 ? "{DynamicResource ControlBg}" : "Transparent"
            wt := r == 0 ? ' FontWeight="SemiBold"' : ""
            while (c < cols) {
                val := c < row.Length ? row[c + 1] : ""
                cells .= '<Border Grid.Row="' r '" Grid.Column="' c '" Background="' bg '"'
                    . ' BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,1,1" Padding="6,4">'
                    . '<TextBlock TextWrapping="Wrap" FontSize="' this._AiChatSmallFontSize() '"' wt '>' this._AiInlineXaml(val, fg) '</TextBlock>'
                    . '</Border>'
                c++
            }
            r++
        }
        return '<Border BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1,1,0,0" CornerRadius="3" Margin="0,4,0,8">'
            . '<ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">'
            . '<Grid>'
            . '<Grid.ColumnDefinitions>' colDef '</Grid.ColumnDefinitions>'
            . '<Grid.RowDefinitions>' rowDef '</Grid.RowDefinitions>'
            . cells
            . '</Grid></ScrollViewer></Border>'
    }

    _AiMdParagraph(text, fg, fs, margin, bold := false) {
        wt := bold ? ' FontWeight="SemiBold"' : ""
        return '<Paragraph Margin="' margin '" FontSize="' fs '" Foreground="' fg '"' wt '>'
            . this._AiInlineXaml(text, fg) '</Paragraph>'
    }

    _AiInlineXaml(s, fg) {
        if (s == "")
            return this._AiMdRun("", ' Foreground="' fg '"')
        out := ""
        i := 1
        len := StrLen(s)
        tick := Chr(96)
        while (i <= len) {
            ch := SubStr(s, i, 1)
            two := SubStr(s, i, 2)
            if (two == "**") {
                close := InStr(s, "**", false, i + 2)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 2, close - i - 2), ' FontWeight="SemiBold" Foreground="' fg '"')
                    i := close + 2
                    continue
                }
            }
            if (two == "~~") {
                close := InStr(s, "~~", false, i + 2)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 2, close - i - 2), ' TextDecorations="Strikethrough" Foreground="' fg '"')
                    i := close + 2
                    continue
                }
            }
            if (ch == tick) {
                close := InStr(s, tick, false, i + 1)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 1, close - i - 1), ' FontFamily="Consolas, Cascadia Mono, Courier New" Background="{DynamicResource ListAltBg}" Foreground="' fg '"')
                    i := close + 1
                    continue
                }
            }
            if (ch == "*" || ch == "_") {
                close := this._AiMdEmphClose(s, i, ch)
                if (close) {
                    out .= this._AiMdRun(SubStr(s, i + 1, close - i - 1), ' FontStyle="Italic" Foreground="' fg '"')
                    i := close + 1
                    continue
                }
            }
            if (ch == "[") {
                rest := SubStr(s, i)
                if (RegExMatch(rest, "^\[([^\]]+)\]\((rmtfile:[^)]+)\)", &ml)) {
                    out .= this._AiFileLinkXaml(ml[1], this._AiDecodeFileUrl(ml[2]))
                    i += StrLen(ml[0])
                    continue
                }
                if (RegExMatch(rest, "^\[([^\]]+)\]\(([^)]+)\)", &ml)) {
                    nav := this._AiParseNavUrl(ml[2])
                    if (IsObject(nav))
                        out .= this._AiNavLinkXaml(ml[1], nav.tab, nav.idx)
                    else
                        out .= this._AiMdRun(ml[1], ' TextDecorations="Underline" Foreground="{DynamicResource Accent}"')
                    i += StrLen(ml[0])
                    continue
                }
            }
            j := i + 1
            while (j <= len) {
                c := SubStr(s, j, 1)
                t2 := SubStr(s, j, 2)
                if (t2 == "**" || t2 == "~~" || c == tick || c == "*" || c == "_" || c == "[")
                    break
                j++
            }
            out .= this._AiMdRun(SubStr(s, i, j - i), ' Foreground="' fg '"')
            i := j
        }
        return out
    }

    ; 路径、宏指令（按键_a_点击）里的 _ / * 不当成斜体
    _AiMdEmphClose(s, i, ch) {
        if (ch == "_" && this._AiMdPathish(s))
            return 0
        prev := (i > 1) ? SubStr(s, i - 1, 1) : " "
        nxt := SubStr(s, i + 1, 1)
        if (nxt == "" || nxt == ch)
            return 0
        if (this._AiMdWordChar(prev) || this._AiMdPathChar(prev))
            return 0
        close := InStr(s, ch, false, i + 1)
        while (close) {
            inner := SubStr(s, i + 1, close - i - 1)
            after := (close < StrLen(s)) ? SubStr(s, close + 1, 1) : " "
            if (inner != "" && !this._AiMdPathChar(after) && !(ch == "_" && this._AiMdWordChar(after))
                && !InStr(inner, "\") && !InStr(inner, "/") && !InStr(inner, ":"))
                return close
            close := InStr(s, ch, false, close + 1)
        }
        return 0
    }

    _AiMdPathish(s) {
        return InStr(s, ":\") || InStr(s, ":/") || InStr(s, "\Desktop") || InStr(s, "/Desktop")
    }

    _AiMdWordChar(c) {
        return (c != "" && RegExMatch(c, "^[A-Za-z0-9]$"))
    }

    _AiMdPathChar(c) {
        return (c = "\" || c = "/" || c = ":" || c = "." || c = "-")
    }

    _AiMdRun(text, extra) {
        return '<Run' extra ' BaselineAlignment="Baseline" Text="' this._XmlEsc(text) '"/>'
    }

    _AiParseNavUrl(url) {
        url := Trim(url)
        if (RegExMatch(url, "i)^rmt://t/(\d+)/i/(\d+)/?$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^rmt:(\d+):(\d+)$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^#t(\d+)i(\d+)$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        if (RegExMatch(url, "i)^macro://(\d+)/(\d+)/?$", &m))
            return {tab: Integer(m[1]), idx: Integer(m[2])}
        return ""
    }

    _AiEncodeFileUrl(path) {
        p := StrReplace(String(path), "\", "/")
        p := StrReplace(p, "%", "%25")
        p := StrReplace(p, ")", "%29")
        p := StrReplace(p, "(", "%28")
        p := StrReplace(p, " ", "%20")
        return "rmtfile:///" p
    }

    _AiDecodeFileUrl(url) {
        p := String(url)
        p := RegExReplace(p, "^rmtfile:/+", "")
        p := StrReplace(p, "%20", " ")
        p := StrReplace(p, "%28", "(")
        p := StrReplace(p, "%29", ")")
        p := StrReplace(p, "%25", "%")
        p := StrReplace(p, "/", "\")
        return p
    }

    _AiExtractFilePaths(text) {
        paths := []
        pos := 1
        while (RegExMatch(text, "\[([^\]]+)\]\((rmtfile:[^)]+)\)", &m, pos)) {
            paths.Push(this._AiDecodeFileUrl(m[2]))
            pos += StrLen(m[0])
            if (pos < 1)
                break
        }
        return paths
    }

    _AiFileLinkXaml(label, path) {
        this._aiLinkSeq += 1
        id := this._aiLinkSeq
        btn := "AiFile_" id
        mOpen := "AiFileOpen_" id
        mDir := "AiFileDir_" id
        mAll := "AiFileAll_" id
        allPaths := IsObject(this._aiMsgFilePaths) ? this._aiMsgFilePaths.Clone() : [path]
        this._aiPendingFileActs.Push({name: btn, act: "open", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mOpen, act: "open", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mDir, act: "folder", path: path, paths: allPaths})
        this._aiPendingFileActs.Push({name: mAll, act: "folders", path: path, paths: allPaths})
        return '<InlineUIContainer BaselineAlignment="Center">'
            . '<Button Name="' btn '" Cursor="Hand" Background="Transparent" BorderThickness="0"'
            . ' Padding="0" Margin="0,0,2,0" VerticalAlignment="Center"'
            . ' ToolTip="' this._XmlEsc(path) '">'
            . '<Button.ContextMenu><ContextMenu MinWidth="160" Placement="MousePoint"'
            . ' Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" Foreground="{DynamicResource TextMain}">'
            . '<MenuItem Name="' mOpen '" Header="' this._XmlEsc(GetLang("打开")) '"/>'
            . '<MenuItem Name="' mDir '" Header="' this._XmlEsc(GetLang("打开所在文件夹")) '"/>'
            . '<MenuItem Name="' mAll '" Header="' this._XmlEsc(GetLang("打开所有文件夹")) '"/>'
            . '</ContextMenu></Button.ContextMenu>'
            . '<TextBlock Text="' this._XmlEsc(label) '" TextDecorations="Underline"'
            . ' Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '" Cursor="Hand"/>'
            . '</Button></InlineUIContainer>'
    }

    OnAiFileMenu(act, *) {
        if (!IsObject(act) || !act.HasProp("act"))
            return
        if (act.act = "open") {
            if (act.path != "" && FileExist(act.path))
                try Run('"' act.path '"')
            return
        }
        paths := (act.HasProp("paths") && Type(act.paths) = "Array") ? act.paths : [act.path]
        if (act.act = "folder")
            paths := [act.path]
        seen := Map()
        for p in paths {
            dir := ""
            SplitPath(p, , &dir)
            if (dir == "" || seen.Has(dir))
                continue
            seen[dir] := true
            if (DirExist(dir))
                try Run('explorer.exe "' dir '"')
        }
    }

    _AiNavLinkXaml(label, tab, idx) {
        this._aiLinkSeq += 1
        name := "AiNav_" this._aiLinkSeq
        this._aiPendingLinks.Push(name)
        tip := GetLang("跳转到宏配置") " T" tab " #" idx
        return '<InlineUIContainer BaselineAlignment="Center">'
            . '<Button Name="' name '" Tag="' tab "|" idx '" Cursor="Hand"'
            . ' Background="Transparent" BorderThickness="0" Padding="0" Margin="0,0,0,0"'
            . ' VerticalAlignment="Center" ToolTip="' this._XmlEsc(tip) '">'
            . '<TextBlock Text="' this._XmlEsc(label) '" TextDecorations="Underline"'
            . ' Foreground="{DynamicResource Accent}" FontSize="' this._AiChatBodyFontSize() '" Cursor="Hand"/>'
            . '</Button></InlineUIContainer>'
    }

    OnAiNavClick(name, *) {
        tag := ""
        try tag := this.ui.Query(name ">Tag")
        if (tag == "" || !InStr(tag, "|"))
            return
        parts := StrSplit(tag, "|")
        if (parts.Length < 2)
            return
        this.NavigateToMacro(Integer(parts[1]), Integer(parts[2]))
    }

    ; 跳转到指定页签下的第 index 个宏，并切到逻辑树以便查看
    NavigateToMacro(tab, index) {
        if (tab < 1 || tab > MySoftData.TableInfo.Length)
            return
        tableItem := MySoftData.TableInfo[tab]
        if (index < 1 || index > tableItem.Items.Length)
            return
        if (!this.aiAssistOpen) {
            this.aiAssistOpen := true
            this._ApplyAiPanelUi()
        }
        this.sidePanelMode := 1
        this._ApplySidePanelMode()
        sameTab := (tab == MainSoftData.TableIndex)
        this._pendingMacroNav := {tab: tab, idx: index}
        if (sameTab) {
            this._pendingMacroNav := ""
            this.SelectSideTreeItem(tab, index)
            return
        }
        if (IsObject(MainSoftData.TabCtrl))
            MainSoftData.TabCtrl.Value := tab
        else {
            o := this._tabOrder
            for i, t in o {
                if (t == tab) {
                    try this.ui.Update("TabControl", "SelectedIndex", String(i - 1))
                    break
                }
            }
        }
    }
