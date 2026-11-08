
    ; ---- 扩展面板尺寸（可手动改）----
    ; 默认宽度：首次展开 / 未拖过时的宽度
    _AiPanelDefaultW() {
        return 380
    }
    ; 最小宽度：再小选项和指令行会挤变形
    _AiPanelMinW() {
        return 260
    }
    ; 最大宽度：再大会过度挤压左侧宏列表
    _AiPanelMaxW() {
        return 490
    }
    ; 左边框拖拽热区宽度
    _AiPanelSplitW() {
        return 6
    }
    ; 扩展钮宽度（恒定命中区，hover 只换描边底色不变宽）
    _AiRailHoverW() {
        return 20
    }
    ; 逻辑树 / AI助手 选项宽度（与顶部页签一致）
    _AiTabW() {
        return 80
    }
    ; 左侧宏行/模块头组间距下限（面板拉最宽、左侧最窄时）
    _AiPanelGapMin() {
        return 4
    }
    ; 拖拽时左侧列表至少保留的宽度
    _AiListMinW() {
        return 420
    }
    ; 展开/收起动画时长（毫秒）
    _AiPanelAnimMs() {
        return 220
    }
    ; 对话输入框外框高度：与 AI 设置 CtrlH 一致
    _AiInputLineH() {
        return AiSettingGui.CtrlH
    }
    _AiInputRadius() {
        return 3
    }
    ; 对话区字号走 DynamicResource，避开 ScaleFontSize/ApplyFonts 的主题下限（声明 12 会被抬成 15）
    _AiChatBodyFontSize() {
        return "{DynamicResource AiChatFontSize}"
    }
    _AiChatSmallFontSize() {
        return "{DynamicResource AiChatFontSizeSmall}"
    }
    _AiChatFontFamily() {
        return (IsSet(MainSoftData) && MainSoftData.HasProp("FontType") && MainSoftData.FontType != "")
            ? MainSoftData.FontType : "微软雅黑"
    }
    ; 多行时每增一行的行距（在单行高度上叠加）
    _AiInputExtraLineH() {
        return 16
    }
    ; 对话输入框最多显示行数，超出出滚动条
    _AiInputMaxLines() {
        return 10
    }
    _AiUserPreviewLines() {
        return 3.5
    }
    _AiUserPreviewLineH() {
        return Max(18, Integer(XAMLHost.ChatBodyFontSize()) + 6)
    }
    _AiUserPreviewH() {
        pad := Integer(AiSettingGui.ContentPadL)
        return Round(this._AiUserPreviewLineH() * this._AiUserPreviewLines() + pad * 2)
    }
    _AiUserNeedsClip(text) {
        raw := this._AiNormalizeNewlines(text, false)
        lines := StrSplit(raw, "`n")
        if (lines.Length > 3)
            return true
        for line in lines {
            if (StrLen(line) > 28)
                return true
        }
        return false
    }
