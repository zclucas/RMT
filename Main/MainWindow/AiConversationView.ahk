
    _BuildAiAssistPanel(vg, idx) {
        wrap := vg.Add("Grid").Name("AiWrap_" idx).Grid_Column(1)
            .Width(this.aiPanelW).MinWidth(this._AiPanelMinW()).MaxWidth(this._AiPanelMaxW())
            .Visibility("Collapsed").Margin("0").Panel_ZIndex(1).ClipToBounds("True")
        panel := wrap.Add("Border").Name("AiInner_" idx).Margin("0").Padding("0")
            .Width(this.aiPanelW).HorizontalAlignment("Right")
            .Background("{DynamicResource ControlBg}")
        wrap.Add("Border").Name("AiSplit_" idx)
            .HorizontalAlignment("Left").Width(this._AiPanelSplitW())
            .Background("Transparent").Cursor("SizeWE")
            .BorderThickness("1.5,0,0,0").BorderBrush("{DynamicResource OutlineStroke}")
            .ToolTip(GetLang("拖拽调整宽度"))
        g := panel.Add("Grid")
        g.Rows("Auto", "*", "Auto")
        head := g.Add("Grid").Grid_Row(0)
        head.Rows("28", "1.5", "Auto", "1.5")
        tabW := this._AiTabW()
        opt := head.Add("Grid").Grid_Row(0).Height(28).MinHeight(28)
        opt.Cols(tabW, "Auto", tabW, "*", "Auto")
        opt.Add("Button").Name("BtnSideModeTree_" idx).Grid_Column(0).Content(GetLang("逻辑树"))
            .Style("{StaticResource RmtSideModeTab}").Width(tabW).Tag("sel-first")
        opt.Add("Rectangle").Grid_Column(1).Width(2).Fill("{DynamicResource ControlBorder}")
            .VerticalAlignment("Stretch").Margin("0,3,0,3").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
        opt.Add("Button").Name("BtnSideModeAi_" idx).Grid_Column(2).Content(GetLang("AI助手"))
            .Style("{StaticResource RmtSideModeTab}").Width(tabW).Tag("last")
        opt.Add("Button").Name("BtnSideToolsToggle_" idx).Grid_Column(4)
            .Style("{StaticResource RmtFoldToolBtn}").Width(26).Height(26).MinHeight(26)
            .Margin("0,0,6,0").VerticalAlignment("Center").HorizontalAlignment("Right")
            .Content(Chr(0xE70E)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(12)
            .ToolTip(GetLang("收起操作"))
            .Background("Transparent").BorderBrush("Transparent").BorderThickness("0")
            .Foreground("{DynamicResource TextMain}")
        head.Add("Rectangle").Grid_Row(1).Height(1.5).Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")

        toolBar := head.Add("StackPanel").Name("SideToolBar_" idx).Grid_Row(2)
            .Orientation("Horizontal").Height(30).Margin("4,4,4,4").VerticalAlignment("Center")
        this._AddSideToolBtn(toolBar, idx, "Record", Chr(0xE7C8), GetLang("指令录制"), true)
        this._AddSideToolBtn(toolBar, idx, "Expand", Chr(0xE73F), GetLang("缩放"), false)
        this._AddSideToolBtn(toolBar, idx, "Undo", Chr(0xE7A7), GetLang("撤销"), false)
        this._AddSideToolBtn(toolBar, idx, "Redo", Chr(0xE7A6), GetLang("恢复"), false)
        this._AddSideToolBtn(toolBar, idx, "Back", Chr(0xE750), GetLang("删除末尾"), false)
        this._AddSideToolSep(toolBar)
        this._AddSideToolBtn(toolBar, idx, "Debug", Chr(0xEBE8), GetLang("调试"), true)
        this._AddSideToolSep(toolBar)
        this._AddSideToolBtn(toolBar, idx, "Var", Chr(0xE7B3), GetLang("变量监视"), true)
        this._AddSideToolBtn(toolBar, idx, "CmdTip", Chr(0xE8E3), GetLang("指令显示"), true)
        this._AddSideToolBtn(toolBar, idx, "Top", Chr(0xE840), GetLang("窗口置顶"), true)

        aiToolBar := head.Add("StackPanel").Name("SideAiToolBar_" idx).Grid_Row(2)
            .Orientation("Horizontal").Height(30).Margin("4,4,4,4").VerticalAlignment("Center")
            .Visibility("Collapsed")
        this._AddSideToolBtn(aiToolBar, idx, "History", Chr(0xE81C), GetLang("对话记录"), false, "SideAiTool")
        this._AddSideToolBtn(aiToolBar, idx, "Validate", Chr(0xE9D9), GetLang("运行前校验"), false, "SideAiTool")
        this._AddSideToolBtn(aiToolBar, idx, "Settings", Chr(0xE713), GetLang("设置"), false, "SideAiTool")
        this._AddSideToolBtn(aiToolBar, idx, "Top", Chr(0xE840), GetLang("窗口置顶"), true, "SideAiTool")

        head.Add("Rectangle").Name("SideToolSplit_" idx).Grid_Row(3).Height(1.5)
            .Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True")
        head.Add("Rectangle").Name("SideAiToolSplit_" idx).Grid_Row(3).Height(1.5)
            .Fill("{DynamicResource OutlineStroke}")
            .HorizontalAlignment("Stretch").IsHitTestVisible("False")
            .SnapsToDevicePixels("True").Visibility("Collapsed")

        body := g.Add("Grid").Grid_Row(1)
        treeHost := body.Add("Grid").Name("SideTreePane_" idx).Visibility("Visible")
        lbStyle := '<Style TargetType="ListBoxItem"><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" SnapsToDevicePixels="True"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>'
        treeLb := treeHost.Add("ListBox").Name("SideTreeList_" idx)
            .BorderThickness("0").Background("Transparent").Padding("0")
            .HorizontalContentAlignment("Stretch")
            .ScrollViewer_HorizontalScrollBarVisibility("Disabled")
            .ScrollViewer_VerticalScrollBarVisibility("Auto")
            .VirtualizingPanel_IsVirtualizing("False")
            .InjectResources(lbStyle)
        treeHost.Add("Border").Name("SideDragInsertLine_" idx).Height(2)
            .HorizontalAlignment("Stretch").VerticalAlignment("Top")
            .Background("{DynamicResource Accent}").BorderThickness(0)
            .SetProp("Panel.ZIndex", "10").Visibility("Collapsed").IsHitTestVisible("False")
        ghostPop := treeHost.Add("Popup").Name("SideDragGhost_" idx).Placement("Absolute")
            .AllowsTransparency("True").IsHitTestVisible("False").IsOpen("False")
        ghostBd := ghostPop.Add("Border").CornerRadius("3").BorderThickness("1").Padding("10,5")
            .Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource Accent}").Opacity("0.94")
        ghostBd.Add("TextBlock").Name("SideDragGhostTxt_" idx).MaxWidth("280").TextTrimming("CharacterEllipsis")
            .Foreground("{DynamicResource TextMain}").FontSize("12")
        treeHost.Add("TextBlock").Name("SideTreeEmpty_" idx).Text(GetLang("暂无指令"))
            .Foreground("{DynamicResource TextSub}").FontSize(12)
            .HorizontalAlignment("Center").VerticalAlignment("Center")
            .IsHitTestVisible("False")

        if (!this._sideCtxBuilt) {
            this._sideCtxBuilt := true
            this._BuildSideTreeContextMenus(head)
        }

        aiSv := body.Add("ScrollViewer").Name("SideAiPane_" idx).Visibility("Collapsed")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        msgs := aiSv.Add("StackPanel").Name("SideAiMsgs_" idx).Margin("12,12,12,8")
        lineH := this._AiInputLineH()
        textH := lineH - 2
        maxH := lineH + (this._AiInputMaxLines() - 1) * this._AiInputExtraLineH()
        sendW := this._AiInputSendW()
        padL := AiSettingGui.ContentPadL
        r := this._AiInputRadius()
        foot := g.Add("Border").Name("SideAiFoot_" idx).Grid_Row(2).Padding("10,4,10,8").BorderThickness("0")
            .Visibility("Collapsed")
        footCol := foot.Add("StackPanel")
        ; 「正在思考」放在输入区上方（不进消息列表），避免第二次请求复用旧节点导致位置错乱
        footCol.Add("TextBlock").Name("AiThinkTxt_" idx).Text(GetLang("正在思考") "…")
            .FontSize(this._AiChatBodyFontSize()).FontStyle("Italic").Foreground("{DynamicResource TextSub}")
            .Margin("2,0,0,6").Visibility("Collapsed").IsHitTestVisible("False")
            .TextWrapping("Wrap")
        ; 不设 Height：高度由 TextBox 按内容自己撑开，外框跟着内容走
        chrome := footCol.Add("Border").Name("AiInputHost_" idx).MinHeight(lineH).MaxHeight(maxH + this._AiAttachBarH())
            .Padding(padL ",0," padL ",0")
            .Background("{DynamicResource InputBg}").BorderBrush("{DynamicResource InputStroke}")
            .BorderThickness("1").CornerRadius(String(r)).AllowDrop("True")
        chrome.Apply({SnapsToDevicePixels: "True", UseLayoutRounding: "True"})
        box := chrome.Add("Grid")
        box.Rows("Auto", "*")
        att := box.Add("StackPanel").Name("AiAttachBar_" idx).Grid_Row(0).Orientation("Horizontal")
            .Margin("0,6,4,4").Visibility("Collapsed").ClipToBounds("False")
        inner := box.Add("Grid").Grid_Row(1)
        tb := inner.Add("TextBox").Name("AiInput_" idx).Style("{StaticResource RmtAiChatBox}")
            .HorizontalAlignment("Stretch").VerticalAlignment("Stretch")
            .MinHeight(textH).MaxHeight(maxH)
            .AcceptsReturn("True").TextWrapping("Wrap").AllowDrop("False")
            .VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
            .VerticalContentAlignment("Center").Padding("0").Margin("0")
            .FontSize(this._AiChatBodyFontSize())
            .Foreground("{DynamicResource InputText}")
            .Background("Transparent").BorderThickness("0")
        this._AttachTextEditContextMenu(tb, true)
        ph := inner.Add("TextBlock").Name("AiInputPh_" idx).Text(GetLang("询问关于宏的任何问题…")).IsHitTestVisible("False")
            .VerticalAlignment("Center").HorizontalAlignment("Left").Margin("0")
            .Foreground("{DynamicResource TextSub}").Opacity("0.55")
            .FontSize(this._AiChatBodyFontSize())
        btns := inner.Add("StackPanel").Name("AiInputBtns_" idx).Orientation("Horizontal")
            .HorizontalAlignment("Right").VerticalAlignment("Center")
            .SetProp("Panel.ZIndex", "2")
        btns.Add("Button").Name("AiMic_" idx).Width(sendW).Height(sendW).MinHeight(sendW)
            .Style("{StaticResource RmtAiIconBtn}").Margin("0,0,2,0")
            .Content(Chr(0xE720)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
            .ToolTip(GetLang("语音输入"))
        btns.Add("Button").Name("AiSend_" idx).Width(sendW).Height(sendW).MinHeight(sendW)
            .Style("{StaticResource RmtAiIconBtn}").Margin("0")
            .Content(Chr(0xE724)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11)
            .ToolTip(GetLang("发送"))
    }

    ; 文本框 / 只读富文本：用 XAML ContextMenu 替换系统旧菜单
    ; AI 菜单在 Viewbox 外：只用主题字号（与输入框观感一致），不再乘 Viewbox（窗口化时会过大）
    _AttachTextEditContextMenu(el, editable) {
        if (!IsObject(el))
            return
        fs := XAMLHost.FontSize()
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? MainSoftData.FontType : "微软雅黑"
        cm := el.Add("FrameworkElement.ContextMenu").Add("ContextMenu")
            .MinWidth("140").Placement("MousePoint")
            .FontSize(String(fs)).FontFamily(ff)
        scrollStyle := IsObject(MyMacroGui) ? MyMacroGui._ContextMenuScrollStyle() : ""
        if (scrollStyle != "")
            cm.InjectResources(scrollStyle)
        if (IsObject(MyMacroGui)) {
            cm.InjectResources(MyMacroGui._MenuItemSubmenuStyle())
            MyMacroGui._ApplyCtxMenuTheme(cm)
        } else
            cm.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource InputStroke}")
                .BorderThickness("1").Foreground("{DynamicResource TextMain}")
        cm.FontSize(String(fs)).FontFamily(ff)
        if (editable) {
            cm.Add("MenuItem").Header(GetLang("剪切")).SetMarkup("Command", "Cut")
            cm.Add("MenuItem").Header(GetLang("复制")).SetMarkup("Command", "Copy")
            cm.Add("MenuItem").Header(GetLang("粘贴")).SetMarkup("Command", "Paste")
            cm.Add("Separator")
            cm.Add("MenuItem").Header(GetLang("全选")).SetMarkup("Command", "SelectAll")
        } else {
            cm.Add("MenuItem").Header(GetLang("复制")).SetMarkup("Command", "Copy")
            cm.Add("Separator")
            cm.Add("MenuItem").Header(GetLang("全选")).SetMarkup("Command", "SelectAll")
        }
    }

    _AiMsgContextMenuXaml(isUser := false, text := "") {
        fs := XAMLHost.FontSize()
        ff := (MainSoftData.HasProp("FontType") && MainSoftData.FontType != "") ? this._XmlEsc(MainSoftData.FontType) : "微软雅黑"
        extra := '<MenuItem Header="' this._XmlEsc(GetLang("全选")) '" Command="SelectAll"/>'
        if (isUser) {
            this._aiLinkSeq += 1
            name := "AiCopyAll_" this._aiLinkSeq
            if (!IsObject(this._aiPendingCopyAll))
                this._aiPendingCopyAll := []
            if (!IsObject(this._aiCopyAllText))
                this._aiCopyAllText := Map()
            this._aiPendingCopyAll.Push(name)
            this._aiCopyAllText[name] := this._AiPlainAttachLabel(text)
            extra := '<MenuItem Name="' name '" Header="' this._XmlEsc(GetLang("全部复制")) '"/>'
        }
        return '<RichTextBox.ContextMenu>'
            . '<ContextMenu MinWidth="140" Placement="MousePoint"'
            . ' FontSize="' fs '" FontFamily="' ff '"'
            . ' Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource InputStroke}"'
            . ' BorderThickness="1" Foreground="{DynamicResource TextMain}">'
            . '<MenuItem Header="' this._XmlEsc(GetLang("复制")) '" Command="Copy"/>'
            . '<Separator/>'
            . extra
            . '</ContextMenu></RichTextBox.ContextMenu>'
    }

    OnAiCopyAll(name, *) {
        txt := ""
        if (IsObject(this._aiCopyAllText) && this._aiCopyAllText.Has(name))
            txt := this._aiCopyAllText[name]
        if (txt == "")
            return
        A_Clipboard := txt
        Toast.Success(GetLang("已复制"))
    }

    _AiInputSendW() {
        return 24
    }
    _AiInputIconReserve() {
        return this._AiInputSendW() * 2 + 4
    }

    _AiAttachBarH() {
        return 52
    }

    _SeedAiMsgs() {
        if (this.aiSeeded)
            return
        this.aiSeeded := true
        t := MainSoftData.TableIndex
        if (t < 1 || !this._useVirtual.Has(t)) {
            for tab in this._useVirtual {
                t := tab
                break
            }
        }
        if (t < 1)
            return
        this._EnsureAiSeeded(t)
    }

    _EnsureAiSeeded(t := 0) {
        if (!IsObject(this._aiSeededTabs))
            this._aiSeededTabs := Map()
        if (t < 1)
            t := MainSoftData.TableIndex
        if (t < 1 || !this._useVirtual.Has(t) || this._aiSeededTabs.Has(t))
            return
        this._aiSeededTabs[t] := true
        this.aiSeeded := true
        fence := Chr(96) Chr(96) Chr(96)
        tick := Chr(96)
        ; Cursor 风格：单条助手欢迎，不做 A/B 对聊演示
        welcome := "我是 **RMT 助手**，可以帮你解读、修改和生成宏配置。`n`n"
            . "试试：`n"
            . "- 描述你想做的操作，我给出可落地的改法`n"
            . "- 粘贴或拖入文件路径，一起分析配置`n"
            . "- 用链接跳转宏项，例如 [当前页第 1 个宏](rmt:" t ":1)`n`n"
            . "支持 Markdown（标题、列表、**加粗**、" tick "代码" tick "、表格等）。"
        this._AiAppendMsg(t, false, welcome)
    }

    _AiAppendMsg(t, isUser, text) {
        stick := true
        try stick := this._AiIsStickBottom(t)
        this._aiPendingLinks := []
        this._aiPendingFileActs := []
        this._aiPendingCopyAll := []
        this._aiPendingUserCards := []
        xaml := this._AiMsgXaml(isUser, text)
        try this.ui.Update("SideAiMsgs_" t, "AddXamlItem", xaml)
        for name in this._aiPendingLinks
            this._Bind(name, "Click", ObjBindMethod(this, "OnAiNavClick", name))
        for act in this._aiPendingFileActs
            this._Bind(act.name, "Click", ObjBindMethod(this, "OnAiFileMenu", act))
        for name in this._aiPendingCopyAll
            this._Bind(name, "Click", ObjBindMethod(this, "OnAiCopyAll", name))
        for name in this._aiPendingUserCards
            this._Bind(name, "MouseLeftButtonUp", ObjBindMethod(this, "OnAiUserMsgClick", name))
        if (stick)
            this._AiScrollToEndSoon(t)
    }

    ; Cursor 风格回合：用户有边框卡片；助手正文铺开。不再标「你 / 助手」。
    _AiMsgXaml(isUser, text) {
        ns := 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
        fg := "{DynamicResource TextMain}"
        this._aiMsgFilePaths := this._AiExtractFilePaths(text)
        body := this._AiMdBodyXaml(text, fg, isUser)
        fs := this._AiChatBodyFontSize()
        ff := this._XmlEsc(this._AiChatFontFamily())
        rtbHit := ""
        rtbName := ""
        if (isUser) {
            this._aiLinkSeq += 1
            card := "AiUserMsg_" this._aiLinkSeq
            rtbName := ' Name="' card '_Body"'
            if (this._AiUserNeedsClip(text)) {
                rtbHit := ' IsHitTestVisible="False"'
                this._aiPendingUserCards.Push(card)
            }
        }
        rtb := '<RichTextBox' rtbName ' IsReadOnly="True" IsDocumentEnabled="True" BorderThickness="0"'
            . ' Background="Transparent" Padding="0" Margin="0"'
            . ' VerticalScrollBarVisibility="Disabled" HorizontalScrollBarVisibility="Disabled"'
            . ' IsUndoEnabled="False" CaretBrush="Transparent" Cursor="IBeam" Tag="PassScroll"'
            . rtbHit
            . ' FontSize="' fs '" FontFamily="' ff '" Foreground="' fg '">'
            . this._AiMsgContextMenuXaml(isUser, text)
            . '<FlowDocument PagePadding="0" TextAlignment="Left" FontSize="' fs '" FontFamily="' ff '">'
            . body
            . '</FlowDocument></RichTextBox>'
        if (isUser) {
            pad := AiSettingGui.ContentPadL
            r := this._AiInputRadius()
            clip := this._AiUserNeedsClip(text)
            extra := clip
                ? ' MaxHeight="' this._AiUserPreviewH() '" ClipToBounds="True" Cursor="Hand" ToolTip="' this._XmlEsc(GetLang("点击展开")) '"'
                : ""
            return '<Border ' ns ' Name="' card '" Margin="0,2,0,9" Padding="' pad ',' pad '" HorizontalAlignment="Stretch"'
                . ' Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputStroke}"'
                . ' BorderThickness="1" CornerRadius="' r '"' extra '>'
                . rtb
                . '</Border>'
        }
        return '<Border ' ns ' Margin="0,0,0,13" Padding="2,0,0,0" Background="Transparent" HorizontalAlignment="Stretch">'
            . rtb
            . '</Border>'
    }

    OnAiUserMsgClick(name, *) {
        if (!IsObject(this._aiUserExpanded))
            this._aiUserExpanded := Map()
        if (this._aiUserExpanded.Has(name) && this._aiUserExpanded[name])
            return
        this._aiUserExpanded[name] := true
        try this.ui.Update(name, "MaxHeight", "10000")
        try this.ui.Update(name, "Cursor", "Arrow")
        try this.ui.Update(name, "ToolTip", "")
        try this.ui.Update(name "_Body", "IsHitTestVisible", "True")
    }
