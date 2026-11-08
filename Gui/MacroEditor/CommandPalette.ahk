
    ; ==================== §13 左侧指令面板（分类+收藏） ====================

    ; 从 INI 读收藏集与分类展开状态
    _LoadCmdPanelState() {
        this._favSet := Map()
        ; 默认收藏用「移动」，旧名称收藏映射到当前名称。
        favStr := CfgRead(SettingFile, SettingSection, "CmdFav", "间隔,按键,搜索,移动")
        for name in StrSplit(favStr, ",") {
            name := Trim(name)
            if (name == "鼠标移动" || name == "鼠标移动Pro")
                name := StrReplace(name, "鼠标", "")
            if (name != "")
                this._favSet[name] := true
        }
        this._catExpand := Map()
        catStr := CfgRead(SettingFile, SettingSection, "CmdCatState", "")
        for seg in StrSplit(catStr, ",") {
            pair := StrSplit(seg, "=")
            if (pair.Length == 2 && Trim(pair[1]) != "")
                this._catExpand[Trim(pair[1])] := Trim(pair[2]) == "1"
        }
        this._favOpen := CfgRead(SettingFile, SettingSection, "CmdFavOpen", "1") != "0"
    }

    ; 收藏集落盘（即时）
    _SaveFavState() {
        arr := []
        for config in this.SubGuiConfig
            if (this._favSet.Has(config.name))
                arr.Push(config.name)
        s := ""
        for i, name in arr
            s .= (i > 1 ? "," : "") name
        CfgWrite(s, SettingFile, SettingSection, "CmdFav")
    }

    ; 分类展开状态落盘（即时）
    _SaveCatState() {
        pairs := []
        for idx, cat in this.CmdCategory
            pairs.Push(cat.name "=" (this._catExpand.Get(cat.name, true) ? "1" : "0"))
        s := ""
        for i, p in pairs
            s .= (i > 1 ? "," : "") p
        CfgWrite(s, SettingFile, SettingSection, "CmdCatState")
        CfgWrite(this._favOpen ? "1" : "0", SettingFile, SettingSection, "CmdFavOpen")
    }

    ; 按中文指令名找 SubGuiConfig；找不到返回 ""
    _CmdConfigOf(cmdName) {
        for config in this.SubGuiConfig
            if (config.name == cmdName)
                return config
        return ""
    }

    ; 左侧列表列宽：折叠 | 间距 | Fluent | 间距 | 文本。指令图标左缘 = Fluent 左缘
    _CmdListCol() {
        return { padL: 6, arrowW: 18, iconW: 18, gap: 6, rowIcon: 16 }
    }

    _CmdRowPadLeft() {
        c := this._CmdListCol()
        return Integer(c.padL + c.arrowW + c.gap)
    }

    ; 构建一行指令：图标 + 名称（收藏改右键，无星标）
    _AddCmdRowBtn(row, config, cmdBtnName, padLeft := "") {
        if (padLeft == "")
            padLeft := this._CmdRowPadLeft()
        c := this._CmdListCol()
        b := row.Add("Button").Name(cmdBtnName).Height(28).MinHeight(28).Margin("0,1")
            .HorizontalAlignment("Stretch").Cursor("Hand")
            .Style("{StaticResource RmtCmdRowBtn}")
            .Padding(padLeft ",0,6,0")
            .HorizontalContentAlignment("Left").VerticalContentAlignment("Center")
        sp := b.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center")
        sp.Add("Image").Source(StrReplace(A_WorkingDir "\" config.icon, "\", "/")).Width(c.rowIcon).Height(c.rowIcon).Margin("0,0," c.gap ",0")
        sp.Add("TextBlock").Text(GetLang(config.name)).FontSize(XAMLHost.MacroBodyFontSize()).VerticalAlignment("Center")
            .TextTrimming("CharacterEllipsis").Foreground("{DynamicResource TextMain}")
    }

    _AddCmdSectionHead(parent, btnName, arrowName, countName, iconGlyph, title, expanded, count, extraMargin := "0") {
        c := this._CmdListCol()
        btn := parent.Add("Button").Name(btnName).Style("{StaticResource RmtCatHeadBtn}")
            .HorizontalAlignment("Stretch").Height(32).MinHeight(32).Cursor("Hand")
            .HorizontalContentAlignment("Left").Margin(extraMargin).ClipToBounds("False")
        g := btn.Add("Grid").HorizontalAlignment("Stretch").ClipToBounds("False")
        g.Cols(String(c.arrowW), String(c.gap), String(c.iconW), String(c.gap), "*", "Auto")
        iconFs := XAMLHost.FormatFontSize(XAMLHost.FontSize() + 2)
        g.Add("TextBlock").Name(arrowName).Grid_Column(0).Text(expanded ? Chr(0xE70D) : Chr(0xE76C))
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(iconFs)
            .Width(c.arrowW).Height(c.arrowW)
            .VerticalAlignment("Center").HorizontalAlignment("Center").TextAlignment("Center")
            .Padding("0").Margin("0")
            .Foreground("{DynamicResource TextMain}")
        g.Add("TextBlock").Grid_Column(2).Text(iconGlyph)
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(iconFs)
            .Width(c.iconW).Height(c.iconW)
            .VerticalAlignment("Center").HorizontalAlignment("Center").TextAlignment("Center")
            .Padding("0").Margin("0")
            .Foreground("{DynamicResource TextMain}")
        g.Add("TextBlock").Grid_Column(4).Text(title).FontSize(XAMLHost.MacroBodyFontSize()).FontWeight("Normal")
            .VerticalAlignment("Center").Foreground("{DynamicResource TextMain}")
            .TextTrimming("CharacterEllipsis")
        g.Add("TextBlock").Name(countName).Grid_Column(5).Text(String(count)).FontSize(10)
            .VerticalAlignment("Center").Margin("8,0,2,0").Foreground("{DynamicResource TextSub}")
        return btn
    }

    ; 构建左侧面板：筛选 + 收藏框 + 分类（可折叠，状态记忆）
    _BuildCmdPanel(left) {
        this._LoadCmdPanelState()
        box := left.Add("Grid")
        box.Rows("Auto", "*")

        filterHost := box.Add("Grid").Grid_Row(0).Margin("0,0,6,8")
        filterHost.Add("TextBox").Name("CmdFilter").Height(26).MinHeight(26)
            .VerticalContentAlignment("Center").Padding("8,0")
            .FontSize(XAMLHost.MacroBodyFontSize())
            .Background("{DynamicResource InputBg}").Foreground("{DynamicResource InputText}")
            .BorderBrush("{DynamicResource InputStroke}").BorderThickness("1")
        filterHost.Add("TextBlock").Name("CmdFilterHint").Text(GetLang("筛选指令"))
            .IsHitTestVisible("False").VerticalAlignment("Center").Margin("10,0,0,0")
            .Foreground("{DynamicResource TextSub}").FontSize(XAMLHost.MacroBodyFontSize())

        sv := box.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto")
            .HorizontalScrollBarVisibility("Disabled").Padding("0").Margin("0")
            .Style("{StaticResource RmtThemedScrollViewer}")
        panel := sv.Add("StackPanel").Margin("0,0,6,6")

        favCnt := 0
        for config in this.SubGuiConfig
            if (this._favSet.Has(config.name))
                favCnt++

        favBlock := panel.Add("Border").Background("{DynamicResource EditHoverBg}")
            .BorderBrush("{DynamicResource OutlineStroke}").BorderThickness("1").CornerRadius("4")
            .Padding("0,4,2,6").Margin("0,0,0,8")
        favInner := favBlock.Add("StackPanel")
        this._AddCmdSectionHead(favInner, "FavToggle", "FavArrow", "FavCount", Chr(0xE734), GetLang("收藏"), this._favOpen, favCnt)
        favPanel := favInner.Add("StackPanel").Name("CmdFavPanel").Visibility(this._favOpen ? "Visible" : "Collapsed")
        for config in this.SubGuiConfig {
            isFav := this._favSet.Has(config.name)
            row := favPanel.Add("Grid").Name("FavRow_" config.propName).HorizontalAlignment("Stretch")
                .Visibility(isFav ? "Visible" : "Collapsed")
            this._AddCmdRowBtn(row, config, "CmdBtnFav_" config.propName)
        }
        favInner.Add("TextBlock").Name("FavEmptyHint").FontSize(XAMLHost.MacroBodyFontSize()).Margin("6,4,4,2")
            .Foreground("{DynamicResource TextSub}")
            .Text(GetLang("右键指令即可加入收藏"))
            .Visibility((this._favOpen && favCnt == 0) ? "Visible" : "Collapsed")

        for idx, cat in this.CmdCategory {
            expanded := this._catExpand.Get(cat.name, true)
            this._AddCmdSectionHead(panel, "CatToggle_" idx, "CatArrow_" idx, "CatCount_" idx, cat.icon, GetLang(cat.name), expanded, cat.cmds.Length, "0,4,0,2")
                .Background("{DynamicResource Accent}")
            catPanel := panel.Add("StackPanel").Name("CatPanel_" idx).Visibility(expanded ? "Visible" : "Collapsed")
            for cmdName in cat.cmds {
                config := this._CmdConfigOf(cmdName)
                if (config == "")
                    continue
                row := catPanel.Add("Grid").Name("CmdRowCat_" config.propName).HorizontalAlignment("Stretch")
                this._AddCmdRowBtn(row, config, "CmdBtn_" config.propName)
            }
        }
    }

    ; 右键收藏 / 取消收藏
    _OnToggleFav(propName, state := "", ctrl := "", event := "") {
        if (!IsObject(this.ui) || propName == "")
            return
        for config in this.SubGuiConfig {
            if (config.propName != propName)
                continue
            isFav := !this._favSet.Has(config.name)
            if (isFav)
                this._favSet[config.name] := true
            else
                this._favSet.Delete(config.name)
            this._SaveFavState()
            this._ApplyCmdFilter()
            return
        }
    }

    _OnToggleFavSection(*) {
        if (!IsObject(this.ui))
            return
        this._favOpen := !this._favOpen
        try this.ui.Update("FavArrow", "Text", this._favOpen ? Chr(0xE70D) : Chr(0xE76C))
        try this.ui.Update("CmdFavPanel", "Visibility", this._favOpen ? "Visible" : "Collapsed")
        this._SaveCatState()
        this._ApplyCmdFilter()
    }

    ; 分类标题点击：折叠/展开该分类并保存
    _OnToggleCat(idx, state, ctrl, event) {
        if (!IsObject(this.ui) || idx < 1 || idx > this.CmdCategory.Length)
            return
        cat := this.CmdCategory[idx]
        expanded := !this._catExpand.Get(cat.name, true)
        this._catExpand[cat.name] := expanded
        try this.ui.Update("CatPanel_" idx, "Visibility", expanded ? "Visible" : "Collapsed")
        try this.ui.Update("CatArrow_" idx, "Text", expanded ? Chr(0xE70D) : Chr(0xE76C))
        this._SaveCatState()
        this._ApplyCmdFilter()
    }

    _OnCmdFilterChanged(state, ctrl := "", event := "") {
        q := ""
        if (IsObject(state) && state.Has("CmdFilter"))
            q := state["CmdFilter"]
        else if (IsObject(this.ui))
            q := this.ui.Query("CmdFilter")
        this._ApplyCmdFilter(q)
    }

    _CmdFilterMatch(name, q) {
        if (q == "")
            return true
        return InStr(name, q) || InStr(GetLang(name), q)
    }

    _ApplyCmdFilter(q := unset) {
        if (!IsObject(this.ui))
            return
        if (!IsSet(q))
            q := this.ui.Query("CmdFilter")
        q := Trim(String(q))
        try this.ui.Update("CmdFilterHint", "Visibility", q == "" ? "Visible" : "Collapsed")

        favVisible := 0
        for config in this.SubGuiConfig {
            match := this._CmdFilterMatch(config.name, q)
            isFav := this._favSet.Has(config.name)
            showFav := isFav && match
            try this.ui.Update("FavRow_" config.propName, "Visibility", showFav ? "Visible" : "Collapsed")
            if (showFav)
                favVisible++
            try this.ui.Update("CmdRowCat_" config.propName, "Visibility", match ? "Visible" : "Collapsed")
        }
        try this.ui.Update("FavCount", "Text", String(favVisible))
        emptyTxt := q != "" ? GetLang("无匹配收藏") : GetLang("右键指令即可加入收藏")
        try this.ui.Update("FavEmptyHint", "Text", emptyTxt)
        try this.ui.Update("FavEmptyHint", "Visibility", (this._favOpen && favVisible == 0) ? "Visible" : "Collapsed")
        try this.ui.Update("CmdFavPanel", "Visibility", this._favOpen ? "Visible" : "Collapsed")

        for idx, cat in this.CmdCategory {
            cnt := 0
            for cmdName in cat.cmds {
                if (this._CmdFilterMatch(cmdName, q))
                    cnt++
            }
            showCat := cnt > 0
            expanded := this._catExpand.Get(cat.name, true)
            try this.ui.Update("CatToggle_" idx, "Visibility", showCat ? "Visible" : "Collapsed")
            try this.ui.Update("CatPanel_" idx, "Visibility", (showCat && expanded) ? "Visible" : "Collapsed")
            try this.ui.Update("CatCount_" idx, "Text", String(cnt))
        }
    }

    _OnCmdRowRightClick(propName, *) {
        if (!IsObject(this.ui) || propName == "")
            return
        this._ctxFavProp := propName
        isFav := false
        for config in this.SubGuiConfig {
            if (config.propName == propName) {
                isFav := this._favSet.Has(config.name)
                break
            }
        }
        try this.ui.Update("MenuFavToggle", "Header", isFav ? GetLang("取消收藏") : GetLang("收藏"))
        try this.ui.Update("CmdFavCM", "IsOpen", "True")
    }

    _OnMenuFavToggle(*) {
        this._OnToggleFav(this._ctxFavProp)
    }
