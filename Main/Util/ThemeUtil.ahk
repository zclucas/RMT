#Requires AutoHotkey v2.0

; =============================================================================
; AppThemeUtil — 统一主题调色板（窗口、节点、轮盘与运行浮层共用）
;
; 存储：MainSettings.toml [ThemeColors]
; 运行时：同步到 MainSoftData.ThemeColors，以及各消费字段（UIPanel* / CMD*）
; 通用窗口色：经 ApplyXamlTheme(..., useAppWinTheme:=true) 覆盖到 XAML Resource
;
; ---------- 扩展约定（增删改颜色 / 预设时请遵守）----------
; 1. 新增颜色项：
;    - 在 ColorDefs 增加 {Key, Group, Label}；Group/Label 用于调色板提示，不再生成分组标题
;    - 至少在默认主题（DefaultThemeKey）Preset 上写上同名属性；其它预设建议一并补齐
;    - 若该色需驱动运行时字段，在 ApplyToRuntime / ApplyWinThemeToXaml 增加映射
;    - 主题设置 UI 固定展开 14 个语义槽位为双列调色板，一般不必改 ThemeSettingGui
; 2. 删除颜色项：从 ColorDefs（及各 Preset 属性、ApplyToRuntime）移除即可；
;    旧 ini 残留键会被忽略，不影响加载
; 3. 颜色键直接使用固定的 14 个主题槽位，不迁移旧版本的颜色设置。
; 4. 缺省回退规则（兼容自定义主题与版本升级）：
;    任意路径取不到某 Key（未保存 / 预设未写 / Map 残缺）时，
;    一律使用默认主题（DefaultThemeKey）对应色，禁止用纯黑凑数（纯黑仅作开发兜底）
; 5. 自定义主题（AppTheme=Custom）：
;    以默认主题为底图，再叠加 ini 中已保存的逐项颜色；新增 Key 自动得默认色
; 6. 预设增删：只改 Presets；未知 Key 在 LoadFromToml 因 IsPresetKey 失败而回退到默认主题
; 7. ColorDefs 的 Group/Label 只描述颜色用途，不再作为主题设置页分组标题；
;    主题设置页固定显示 14 个语义槽位，修改一个槽位会同步其全部用途键。
; =============================================================================

class AppThemeUtil {
    ; Canonical theme palette. Every preset exposes these 14 slots in the same order.
    static ColorDefs := [
        {Key: "Theme_Color01", Source: "Theme_Color01", Group: "主题颜色", Label: "主色", Uses: ["操作按钮背景", "图形选中边框", "进度条", "菜单轮盘划线", "界面浮窗按钮"]},
        {Key: "Theme_Color02", Source: "Theme_Color02", Group: "主题颜色", Label: "主色悬停", Uses: ["操作按钮悬停", "输入框悬停边框"]},
        {Key: "Theme_Color03", Source: "Theme_Color03", Group: "主题颜色", Label: "浅色强调", Uses: ["输入框悬停背景", "菜单轮盘悬停填充", "指令运行背景"]},
        {Key: "Theme_Color04", Source: "Theme_Color04", Group: "主题颜色", Label: "标题背景", Uses: ["通用窗口标题", "界面浮窗标题"]},
        {Key: "Theme_Color05", Source: "Theme_Color05", Group: "主题颜色", Label: "标题文字", Uses: ["通用窗口标题文字", "界面浮窗标题文字"]},
        {Key: "Theme_Color06", Source: "Theme_Color06", Group: "主题颜色", Label: "窗口背景", Uses: ["通用窗口背景", "指令显示背景"]},
        {Key: "Theme_Color07", Source: "Theme_Color07", Group: "主题颜色", Label: "内容背景", Uses: ["输入框", "编辑框", "菜单轮盘普通填充", "界面浮窗内容"]},
        {Key: "Theme_Color08", Source: "Theme_Color08", Group: "主题颜色", Label: "普通边框", Uses: ["输入框边框", "编辑框边框", "菜单轮盘普通边框"]},
        {Key: "Theme_Color09", Source: "Theme_Color09", Group: "主题颜色", Label: "强调边框", Uses: ["内容框选边框", "窗口外框"]},
        {Key: "Theme_Color10", Source: "Theme_Color10", Group: "主题颜色", Label: "主文字", Uses: ["标签文字", "指令文字", "菜单轮盘普通文字"]},
        {Key: "Theme_Color11", Source: "Theme_Color11", Group: "主题颜色", Label: "输入文字", Uses: ["输入框文字", "编辑框文字"]},
        {Key: "Theme_Color12", Source: "Theme_Color12", Group: "主题颜色", Label: "图形线", Uses: ["图形节点网格线"]},
        {Key: "Theme_Color13", Source: "Theme_Color13", Group: "主题颜色", Label: "图形连接面", Uses: ["图形节点连接线"]},
        {Key: "Theme_Color14", Source: "Theme_Color14", Group: "主题颜色", Label: "主色文字", Uses: ["操作按钮文字", "界面浮窗按钮文字"]}
    ]

    ; All runtime color keys resolve to the same canonical slot for every preset.
    static ColorAliases := Map(
        "Win_ActionBg", "Theme_Color01", "Win_ActionStroke", "Theme_Color01",
        "Win_GraphConnSel", "Theme_Color01", "Win_ProgressBar", "Theme_Color01",
        "Wheel_HoverText", "Theme_Color01", "Wheel_HoverStroke", "Theme_Color01",
        "Wheel_SwipeLineColor", "Theme_Color01", "Panel_BtnColor", "Theme_Color01",
        "Win_ActionHoverBg", "Theme_Color02", "Win_ActionHoverStroke", "Theme_Color02",
        "Win_EditHoverStroke", "Theme_Color02",
        "Win_EditHoverBg", "Theme_Color03", "Wheel_HoverFill", "Theme_Color03",
        "CMD_RunBGColor", "Theme_Color03",
        "Win_TitleBg", "Theme_Color04", "Panel_TitleBg", "Theme_Color04",
        "Win_TitleText", "Theme_Color05", "Panel_TitleText", "Theme_Color05",
        "Win_WindowBg", "Theme_Color06", "CMD_BGColor", "Theme_Color06",
        "Win_InputBg", "Theme_Color07", "Win_EditBg", "Theme_Color07",
        "Wheel_NormalFill", "Theme_Color07", "Panel_BgColor", "Theme_Color07",
        "Win_InputStroke", "Theme_Color08", "Win_EditStroke", "Theme_Color08",
        "Wheel_NormalStroke", "Theme_Color08",
        "Win_GroupStroke", "Theme_Color09",
        "Win_LabelColor", "Theme_Color10", "CMD_FontColor", "Theme_Color10",
        "Wheel_NormalText", "Theme_Color10",
        "Win_InputText", "Theme_Color11", "Win_EditText", "Theme_Color11",
        "Win_GraphLine", "Theme_Color12",
        "Win_GraphConn", "Theme_Color13",
        "Win_ActionText", "Theme_Color14", "Panel_BtnText", "Theme_Color14"
    )
    ; 颜色权威清单：UI 编辑项、ini 读写、完整 Map 均以此为准
    ; 分组顺序即主题选项页展示顺序；「通用窗口」置于菜单轮盘之上
    ; 预设只存固定的 14 个主题槽位；用途资源由 ColorAliases 映射，避免再出现可配置的旧颜色字段。
    static Presets := [
        {Key: "Default", Name: "默认",
            Theme_Color01: "#FF0078D7",
            Theme_Color02: "#FF106EBE",
            Theme_Color03: "#FFE3F2FD",
            Theme_Color04: "#FFEBEBEB",
            Theme_Color05: "#FF1A1A1A",
            Theme_Color06: "#FFF0F0F0",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFCCCCCC",
            Theme_Color09: "#FF999999",
            Theme_Color10: "#FF1A1A1A",
            Theme_Color11: "#FF1A1A1A",
            Theme_Color12: "#FF333333",
            Theme_Color13: "#FFFFFFFF",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "FrostGray", Name: "霜灰",
            Theme_Color01: "#FF475569",
            Theme_Color02: "#FF334155",
            Theme_Color03: "#FFE2E8F0",
            Theme_Color04: "#FFE2E8F0",
            Theme_Color05: "#FF1E293B",
            Theme_Color06: "#FFF8FAFC",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFCBD5E1",
            Theme_Color09: "#FF94A3B8",
            Theme_Color10: "#FF1E293B",
            Theme_Color11: "#FF1E293B",
            Theme_Color12: "#FF2E3540",
            Theme_Color13: "#FFF8FAFC",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "DarkNight", Name: "暗夜",
            Theme_Color01: "#FF4A4A4A",
            Theme_Color02: "#FF5A5A5A",
            Theme_Color03: "#FF3D3D3D",
            Theme_Color04: "#FF111111",
            Theme_Color05: "#FFE8E8E8",
            Theme_Color06: "#FF1E1E1E",
            Theme_Color07: "#FF2D2D2D",
            Theme_Color08: "#FF6E6E6E",
            Theme_Color09: "#FF666666",
            Theme_Color10: "#FFE0E0E0",
            Theme_Color11: "#FFE8E8E8",
            Theme_Color12: "#FF2A2A2A",
            Theme_Color13: "#FFE8E8E8",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "WarmSun", Name: "暖阳",
            Theme_Color01: "#FFFF8C00",
            Theme_Color02: "#FFE67E00",
            Theme_Color03: "#FFFFE4B5",
            Theme_Color04: "#FFFFE4B5",
            Theme_Color05: "#FF5C3317",
            Theme_Color06: "#FFFFF8DC",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFE8B86D",
            Theme_Color09: "#FFE8B86D",
            Theme_Color10: "#FF5C3317",
            Theme_Color11: "#FF5C3317",
            Theme_Color12: "#FF3A3228",
            Theme_Color13: "#FFFFF8DC",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "Ocean", Name: "海洋",
            Theme_Color01: "#FF1E90FF",
            Theme_Color02: "#FF187BCD",
            Theme_Color03: "#FFE0F0FF",
            Theme_Color04: "#FFD6EAF8",
            Theme_Color05: "#FF1A365D",
            Theme_Color06: "#FFF0F8FF",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FF90CAF9",
            Theme_Color09: "#FF7EB3E8",
            Theme_Color10: "#FF1A365D",
            Theme_Color11: "#FF1A365D",
            Theme_Color12: "#FF283848",
            Theme_Color13: "#FFF0F8FF",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "PinkSakura", Name: "绯樱",
            Theme_Color01: "#FFDB2777",
            Theme_Color02: "#FFBE185D",
            Theme_Color03: "#FFFFE4EC",
            Theme_Color04: "#FFFFE4EC",
            Theme_Color05: "#FF9F1239",
            Theme_Color06: "#FFFFF0F5",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFFFB6C1",
            Theme_Color09: "#FFF9A8C4",
            Theme_Color10: "#FF9F1239",
            Theme_Color11: "#FF9F1239",
            Theme_Color12: "#FF3A2830",
            Theme_Color13: "#FFFFF0F5",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "Matcha", Name: "抹茶",
            Theme_Color01: "#FF65A30D",
            Theme_Color02: "#FF4D7C0F",
            Theme_Color03: "#FFECF4D3",
            Theme_Color04: "#FFECF4D3",
            Theme_Color05: "#FF365314",
            Theme_Color06: "#FFF7FBEA",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFA3B18A",
            Theme_Color09: "#FF8FA076",
            Theme_Color10: "#FF365314",
            Theme_Color11: "#FF365314",
            Theme_Color12: "#FF2E3828",
            Theme_Color13: "#FFF7FBEA",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "Celadon", Name: "青瓷",
            Theme_Color01: "#FF0D9488",
            Theme_Color02: "#FF0F766E",
            Theme_Color03: "#FFCCFBF1",
            Theme_Color04: "#FFCCFBF1",
            Theme_Color05: "#FF134E4A",
            Theme_Color06: "#FFF0FDFA",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FF99F6E4",
            Theme_Color09: "#FF5EEAD4",
            Theme_Color10: "#FF134E4A",
            Theme_Color11: "#FF134E4A",
            Theme_Color12: "#FF283836",
            Theme_Color13: "#FFF0FDFA",
            Theme_Color14: "#FFFFFFFF"},
        {Key: "DuskPurple", Name: "暮紫",
            Theme_Color01: "#FF7C3AED",
            Theme_Color02: "#FF6D28D9",
            Theme_Color03: "#FFF3E8FF",
            Theme_Color04: "#FFF3E8FF",
            Theme_Color05: "#FF4C1D95",
            Theme_Color06: "#FFFAF5FF",
            Theme_Color07: "#FFFFFFFF",
            Theme_Color08: "#FFDDD6FE",
            Theme_Color09: "#FFC4B5FD",
            Theme_Color10: "#FF4C1D95",
            Theme_Color11: "#FF4C1D95",
            Theme_Color12: "#FF322840",
            Theme_Color13: "#FFFAF5FF",
            Theme_Color14: "#FFFFFFFF"}
    ]

    ; 程序默认主题（缺键 / 废弃预设 / Custom 底图均回退到此）
    static DefaultThemeKey := "Default"

    ; ---------- 预设查找 ----------

    static GetDefaultPreset() {
        for item in AppThemeUtil.Presets {
            if (item.Key == AppThemeUtil.DefaultThemeKey)
                return item
        }
        ; 开发期保底：Presets 首项应与 DefaultThemeKey 保持一致
        return AppThemeUtil.Presets[1]
    }

    static IsPresetKey(key) {
        if (key == "Custom")
            return true
        for item in AppThemeUtil.Presets {
            if (item.Key == key)
                return true
        }
        return false
    }

    static FindPreset(key) {
        for item in AppThemeUtil.Presets {
            if (item.Key == key)
                return item
        }
        return AppThemeUtil.GetDefaultPreset()
    }

    static FindPresetByName(name) {
        for item in AppThemeUtil.Presets {
            if (item.Name == name || GetLang(item.Name) == name)
                return item
        }
        return ""
    }

    ; ColorDefs 中 Group 去重顺序（兼容旧调用；主题设置页现在使用 BuildPalette）
    static GetGroupNames() {
        names := []
        seen := Map()
        for def in AppThemeUtil.ColorDefs {
            if (!seen.Has(def.Group)) {
                seen[def.Group] := true
                names.Push(def.Group)
            }
        }
        return names
    }

    ; 将主题的 14 个语义颜色键按固定槽位顺序展开，保证不同主题的颜色 X 用途一致。
    static BuildPalette(colors) {
        complete := AppThemeUtil.BuildCompleteColorMap(colors)
        palette := []
        for defIndex, def in AppThemeUtil.ColorDefs {
            color := AppThemeUtil.ResolveColor(complete, def.Key)
            uses := def.HasProp("Uses") ? def.Uses : [def.Group " · " def.Label]
            entry := {Color: color, Keys: [def.Key], Uses: uses, DefIndex: defIndex}
            entry.SortInfo := AppThemeUtil.PaletteColorInfo(entry.Color)
            palette.Push(entry)
        }
        return palette
    }
    ; 主题色优先，白/黑/灰等低饱和通用色放在末尾；同一色相按明度、饱和度相邻排列。
    static PaletteColorInfo(color) {
        c := AppThemeUtil.NormalizeArgb(color)
        r := Integer("0x" SubStr(c, 4, 2)) / 255.0
        g := Integer("0x" SubStr(c, 6, 2)) / 255.0
        b := Integer("0x" SubStr(c, 8, 2)) / 255.0
        maxC := Max(r, g, b)
        minC := Min(r, g, b)
        delta := maxC - minC
        light := (maxC + minC) / 2.0
        if (delta == 0) {
            hue := 0.0
            sat := 0.0
        } else {
            sat := delta / (1 - Abs(2 * light - 1))
            if (maxC == r) {
                hue := 60.0 * ((g - b) / delta)
                if (hue < 0)
                    hue += 360.0
            } else if (maxC == g) {
                hue := 60.0 * ((b - r) / delta + 2)
            } else {
                hue := 60.0 * ((r - g) / delta + 4)
            }
        }
        alpha := Integer("0x" SubStr(c, 2, 2))
        return {Neutral: sat < 0.08 ? 1 : 0, Hue: hue, Light: light, Sat: sat, Alpha: alpha}
    }

    static ComparePaletteEntries(left, right) {
        a := left.SortInfo
        b := right.SortInfo
        if (a.Neutral != b.Neutral)
            return a.Neutral < b.Neutral ? -1 : 1
        if (a.Hue != b.Hue)
            return a.Hue < b.Hue ? -1 : 1
        if (a.Light != b.Light)
            return a.Light < b.Light ? -1 : 1
        if (a.Sat != b.Sat)
            return a.Sat > b.Sat ? -1 : 1
        if (a.Alpha != b.Alpha)
            return a.Alpha > b.Alpha ? -1 : 1
        if (a.DefIndex != b.DefIndex)
            return a.DefIndex < b.DefIndex ? -1 : 1
        return StrCompare(left.Color, right.Color)
    }

    static PaletteTooltip(entry) {
        if (!IsObject(entry) || !entry.HasProp("Uses") || entry.Uses.Length == 0)
            return ""
        tip := "常用位置："
        for i, useName in entry.Uses
            tip .= (i == 1 ? "" : "；") useName
        return tip
    }

    ; 色块与输入框描边相同会融为一体，依次尝试主题描边/文字色，最后使用对比色。
    static PaletteSwatchStroke(colors, fillColor) {
        fill := AppThemeUtil.NormalizeArgb(fillColor)
        stroke := AppThemeUtil.ResolveColor(colors, "Win_InputStroke")
        if (stroke != fill)
            return stroke
        for key in ["Win_GroupStroke", "Win_LabelColor", "Win_ActionStroke"] {
            candidate := AppThemeUtil.ResolveColor(colors, key)
            if (candidate != fill)
                return candidate
        }
        return AppThemeUtil.RgbLuma(fill) >= 150 ? "#FF4B5563" : "#FFE5E7EB"
    }

    static SetPaletteColor(colors, entry, newColor) {
        if (!IsObject(colors) || !IsObject(entry) || !entry.HasProp("Keys"))
            return false
        normalized := AppThemeUtil.NormalizeArgb(newColor)
        for colorKey in entry.Keys
            colors[colorKey] := normalized
        return true
    }

    ; ---------- 颜色解析与完整 Map（兼容核心）----------

    ; 默认主题上某 Key 的标准色；默认主题也未定义时才回退纯黑（应避免出现）
    static GetDefaultColor(key) {
        canonical := AppThemeUtil.CanonicalKey(key)
        slots := AppThemeUtil.GetPresetSlotMap(AppThemeUtil.GetDefaultPreset())
        if (slots.Has(canonical))
            return slots[canonical]
        return "#FF000000"
    }

    ; 从 colors Map 取色；缺键 / 空值 → 默认主题
    static ResolveColor(colors, key) {
        if (IsObject(colors) && colors.Has(key)) {
            val := colors[key]
            if (val != "")
                return AppThemeUtil.NormalizeArgb(val)
        }
        canonical := AppThemeUtil.CanonicalKey(key)
        if (IsObject(colors) && colors.Has(canonical)) {
            val := colors[canonical]
            if (val != "")
                return AppThemeUtil.NormalizeArgb(val)
        }
        return AppThemeUtil.GetDefaultColor(key)
    }

    ; 以默认主题为底，再叠加 overlay（Map 或 Preset 对象），保证含 ColorDefs 全部 Key
    ; 用于：选预设、加载自定义残缺配置、克隆后补齐新增项
    static BuildCompleteColorMap(overlay := "") {
        colors := Map()
        used := Map()
        baseSlots := AppThemeUtil.GetPresetSlotMap(AppThemeUtil.GetDefaultPreset())
        overlaySlots := (IsObject(overlay) && !(overlay is Map) && overlay.HasProp("Key"))
            ? AppThemeUtil.GetPresetSlotMap(overlay)
            : Map()
        for def in AppThemeUtil.ColorDefs {
            key := def.Key
            val := ""
            if (IsObject(overlay)) {
                if (overlay is Map) {
                    if (overlay.Has(key) && overlay[key] != "")
                        val := overlay[key]
                } else if (overlay.HasProp(key)) {
                    propVal := overlay.%key%
                    if (propVal != "")
                        val := propVal
                }
            }
            if (val == "")
                val := overlaySlots.Has(key) ? overlaySlots[key] : (baseSlots.Has(key) ? baseSlots[key] : "#FF000000")
            val := AppThemeUtil.MakeDistinctColor(val, used)
            colors[key] := val
            used[val] := true
        }
        ; ThemeColors 仅保留 Theme_Color01～Theme_Color14。
        ; 旧用途名只在 ResolveColor 时临时映射，绝不再写入主题 Map 或 INI。
        return colors
    }

    static CanonicalKey(key) {
        return AppThemeUtil.ColorAliases.Has(key) ? AppThemeUtil.ColorAliases[key] : key
    }

    static GetPresetSlotMap(preset) {
        slots := Map()
        used := Map()
        base := AppThemeUtil.GetDefaultPreset()
        for def in AppThemeUtil.ColorDefs {
            val := ""
            if (IsObject(preset) && def.HasProp("Source") && preset.HasProp(def.Source))
                val := preset.%def.Source%
            if (val == "" && IsObject(base) && base.HasProp(def.Source))
                val := base.%def.Source%
            val := AppThemeUtil.MakeDistinctColor(val, used)
            slots[def.Key] := val
            used[val] := true
        }
        return slots
    }

    ; 由预设生成完整颜色 Map（预设缺属性时补默认主题色）
    static NewColorMapFromPreset(preset) {
        return AppThemeUtil.BuildCompleteColorMap(preset)
    }

    ; 克隆并补齐：旧自定义 / 内存残缺 Map 升级后自动带上新 Key（默认主题色）
    static CloneColorMap(src) {
        return AppThemeUtil.BuildCompleteColorMap(IsObject(src) ? src : "")
    }

    ; #AARRGGBB / AARRGGBB / RRGGBB -> 6 位 RGB（供 AHK Gui.BackColor）
    static ArgbToRgb6(color) {
        s := StrReplace(color, "#")
        if (StrLen(s) >= 8)
            return SubStr(s, 3, 6)
        if (StrLen(s) == 6)
            return s
        return "000000"
    }

    static NormalizeArgb(color) {
        s := StrUpper(StrReplace(String(color), "#"))
        if (StrLen(s) == 6)
            return "#FF" s
        if (StrLen(s) == 8)
            return "#" s
        return "#FF000000"
    }

    static MakeDistinctColor(color, used) {
        candidate := AppThemeUtil.NormalizeArgb(color)
        if (!used.Has(candidate))
            return candidate
        alpha := Integer("0x" SubStr(candidate, 2, 2))
        baseR := Integer("0x" SubStr(candidate, 4, 2))
        baseG := Integer("0x" SubStr(candidate, 6, 2))
        baseB := Integer("0x" SubStr(candidate, 8, 2))
        loop 255 {
            distance := Ceil(A_Index / 2)
            if (Mod(A_Index, 2) == 1)
                distance := -distance
            r := Max(0, Min(255, baseR + distance))
            g := Max(0, Min(255, baseG + distance))
            b := Max(0, Min(255, baseB + distance))
            candidate := Format("#{:02X}{:02X}{:02X}{:02X}", alpha, r, g, b)
            if (!used.Has(candidate))
                return candidate
        }
        return Format("#FF{:02X}{:02X}{:02X}", Mod(baseR + 1, 256), Mod(baseG + 3, 256), Mod(baseB + 5, 256))
    }

    static MapGet(colors, key, defaultVal) {
        if (IsObject(colors) && colors.Has(key) && colors[key] != "")
            return colors[key]
        return defaultVal
    }

    ; ---------- 运行时同步 ----------

    ; 将 ThemeColors 同步到各运行时字段（缺键走 ResolveColor → 默认主题）
    static ApplyToRuntime(colors) {
        if (!IsObject(colors))
            colors := Map()
        ; BuildComplete 只读取固定的 14 个主题槽位，并重新生成运行时别名。
        colors := AppThemeUtil.BuildCompleteColorMap(colors)

        MainSoftData.UIPanelTitleBg := AppThemeUtil.ResolveColor(colors, "Panel_TitleBg")
        MainSoftData.UIPanelTitleText := AppThemeUtil.ResolveColor(colors, "Panel_TitleText")
        MainSoftData.UIPanelBtnColor := AppThemeUtil.ResolveColor(colors, "Panel_BtnColor")

        ; 按钮文本由固定的主题槽位提供。
        MainSoftData.UIPanelBtnText := AppThemeUtil.ResolveColor(colors, "Panel_BtnText")
        MainSoftData.UIPanelFontColor := MainSoftData.UIPanelBtnText  ; 兼容旧字段名

        MainSoftData.UIPanelBgColor := AppThemeUtil.ResolveColor(colors, "Panel_BgColor")
        MainSoftData.CMDFontColor := AppThemeUtil.ArgbToRgb6(AppThemeUtil.ResolveColor(colors, "CMD_FontColor"))
        MainSoftData.CMDBGColor := AppThemeUtil.ArgbToRgb6(AppThemeUtil.ResolveColor(colors, "CMD_BGColor"))
        MainSoftData.CMDRunBGColor := AppThemeUtil.ArgbToRgb6(AppThemeUtil.ResolveColor(colors, "CMD_RunBGColor"))
    }

    static ApplyPreset(key) {
        preset := AppThemeUtil.FindPreset(key)
        MainSoftData.AppTheme := preset.Key
        MainSoftData.ThemeColors := AppThemeUtil.NewColorMapFromPreset(preset)
        AppThemeUtil.ApplyToRuntime(MainSoftData.ThemeColors)
    }

    ; ---------- toml 读写 ----------

    static LoadFromToml() {
        section := "ThemeColors"
        themeKey := CfgRead(SettingFile, section, "AppTheme", AppThemeUtil.DefaultThemeKey)
        ; 空值、未知 Key → 默认主题
        if (themeKey == "" || !AppThemeUtil.IsPresetKey(themeKey))
            themeKey := AppThemeUtil.DefaultThemeKey
        MainSoftData.AppTheme := themeKey

        ; Custom：底图=默认主题；具名预设：底图=该预设（缺属性仍补默认主题）
        baseKey := (themeKey == "Custom") ? AppThemeUtil.DefaultThemeKey : themeKey
        colors := AppThemeUtil.NewColorMapFromPreset(AppThemeUtil.FindPreset(baseKey))

        ; 逐项覆盖：ini 有值才覆盖；新增 ColorDefs Key 在 ini 中不存在时保留底图色
        for def in AppThemeUtil.ColorDefs {
            saved := CfgRead(SettingFile, section, def.Key, "")
            if (saved != "")
                colors[def.Key] := AppThemeUtil.NormalizeArgb(saved)
        }

        colors := AppThemeUtil.CloneColorMap(colors)
        MainSoftData.ThemeColors := colors
        AppThemeUtil.ApplyToRuntime(colors)
    }

    static SaveToToml() {
        section := "ThemeColors"
        ; 保存前补齐，避免漏写新增 Key
        MainSoftData.ThemeColors := AppThemeUtil.CloneColorMap(MainSoftData.ThemeColors)
        CfgWrite(MainSoftData.AppTheme, SettingFile, section, "AppTheme")
        for def in AppThemeUtil.ColorDefs {
            val := AppThemeUtil.ResolveColor(MainSoftData.ThemeColors, def.Key)
            CfgWrite(val, SettingFile, section, def.Key)
        }
        ; 其他界面设置仍写入原有配置段；主题颜色只写入 14 个 Theme_Color 槽位。
        CfgWrite(MainSoftData.AppTheme, SettingFile, SettingSection, "AppTheme")
        if (MainSoftData.HasProp("FontSize"))
            CfgWrite(MainSoftData.FontSize, SettingFile, SettingSection, "FontSize")
    }

    ; 轮盘取色：ThemeColors → 默认主题；defaultVal 仅作额外兜底（调用方可省略）
    static GetWheelColor(name, defaultVal := "") {
        key := "Wheel_" name
        if (IsObject(MainSoftData.ThemeColors)
            && (MainSoftData.ThemeColors.Has(key) || MainSoftData.ThemeColors.Has(AppThemeUtil.CanonicalKey(key))))
            return AppThemeUtil.ResolveColor(MainSoftData.ThemeColors, key)
        warm := AppThemeUtil.GetDefaultColor(key)
        if (warm != "#FF000000")
            return warm
        return (defaultVal != "") ? defaultVal : warm
    }

    ; 将「通用窗口」色写入已打开的 XAML 窗口 Resource（及标题栏 DragArea）
    ; colors 可传编辑中的草稿 Map；省略则用 MainSoftData.ThemeColors
    static ApplyWinThemeToXaml(ui, colors := "") {
        if (!IsObject(ui))
            return
        if (!IsObject(colors))
            colors := IsObject(MainSoftData.ThemeColors) ? MainSoftData.ThemeColors : Map()
        colors := AppThemeUtil.BuildCompleteColorMap(colors)

        titleBg := AppThemeUtil.ResolveColor(colors, "Win_TitleBg")
        titleText := AppThemeUtil.ResolveColor(colors, "Win_TitleText")
        windowBg := AppThemeUtil.ResolveColor(colors, "Win_WindowBg")
        groupStroke := AppThemeUtil.ResolveColor(colors, "Win_GroupStroke")
        graphLine := AppThemeUtil.ResolveColor(colors, "Win_GraphLine")
        graphConn := AppThemeUtil.ResolveColor(colors, "Win_GraphConn")
        graphConnSel := AppThemeUtil.ResolveColor(colors, "Win_GraphConnSel")
        labelColor := AppThemeUtil.ResolveColor(colors, "Win_LabelColor")
        textSub := AppThemeUtil.WithAlpha(labelColor, "99")
        inputBg := AppThemeUtil.ResolveColor(colors, "Win_InputBg")
        inputStroke := AppThemeUtil.ResolveColor(colors, "Win_InputStroke")
        inputText := AppThemeUtil.ResolveColor(colors, "Win_InputText")
        editBg := AppThemeUtil.ResolveColor(colors, "Win_EditBg")
        editStroke := AppThemeUtil.ResolveColor(colors, "Win_EditStroke")
        editText := AppThemeUtil.ResolveColor(colors, "Win_EditText")
        editHoverBg := AppThemeUtil.ResolveColor(colors, "Win_EditHoverBg")
        editHoverStroke := AppThemeUtil.ResolveColor(colors, "Win_EditHoverStroke")
        actionBg := AppThemeUtil.ResolveColor(colors, "Win_ActionBg")
        actionStroke := AppThemeUtil.ResolveColor(colors, "Win_ActionStroke")
        actionText := AppThemeUtil.ResolveColor(colors, "Win_ActionText")
        actionHoverBg := AppThemeUtil.ResolveColor(colors, "Win_ActionHoverBg")
        actionHoverStroke := AppThemeUtil.ResolveColor(colors, "Win_ActionHoverStroke")
        progress := AppThemeUtil.ResolveColor(colors, "Win_ProgressBar")
        ; 页签选中背景：主题强调色低透明度（各主题自动适配，见主窗口 tabItemStyle 的 TabSelBg）
        tabSelBg := AppThemeUtil.WithAlpha(progress, "80")
        btnPressBg := AppThemeUtil.AdjustRgbBrightness(groupStroke, 0.90)
        actionPressBg := AppThemeUtil.AdjustRgbBrightness(actionHoverBg, 0.92)
        ; 主界面主要轮廓描边：与「配置管理」按钮 hover 背景同色（ControlBorder / GroupStroke）
        outlineStroke := groupStroke

        ; 合并为一次 BatchUpdate：~28 条资源逐条 Update 是 28 次同步 IPC 往返（拖慢开窗）
        if (ui.HasMethod("BatchUpdate")) {
            batch := [
                {ControlName: "Resource", PropertyName: "TitleBarColor", Value: titleBg},
                {ControlName: "Resource", PropertyName: "TitleBarForeground", Value: titleText},
                {ControlName: "Resource", PropertyName: "BgColor", Value: windowBg},
                {ControlName: "Resource", PropertyName: "TextMain", Value: labelColor},
                {ControlName: "Resource", PropertyName: "TextSub", Value: textSub},
                {ControlName: "Resource", PropertyName: "ControlBg", Value: windowBg},
                {ControlName: "Resource", PropertyName: "ControlBorder", Value: groupStroke},
                {ControlName: "Resource", PropertyName: "GroupStroke", Value: groupStroke},
                {ControlName: "Resource", PropertyName: "GraphLine", Value: graphLine},
                {ControlName: "Resource", PropertyName: "GraphConn", Value: graphConn},
                {ControlName: "Resource", PropertyName: "GraphConnSel", Value: graphConnSel},
                {ControlName: "Resource", PropertyName: "InputBg", Value: inputBg},
                {ControlName: "Resource", PropertyName: "InputStroke", Value: inputStroke},
                {ControlName: "Resource", PropertyName: "InputText", Value: inputText},
                {ControlName: "Resource", PropertyName: "EditBg", Value: editBg},
                {ControlName: "Resource", PropertyName: "EditStroke", Value: editStroke},
                {ControlName: "Resource", PropertyName: "EditText", Value: editText},
                {ControlName: "Resource", PropertyName: "EditHoverBg", Value: editHoverBg},
                {ControlName: "Resource", PropertyName: "EditHoverStroke", Value: editHoverStroke},
                {ControlName: "Resource", PropertyName: "ActionBg", Value: actionBg},
                {ControlName: "Resource", PropertyName: "ActionStroke", Value: actionStroke},
                {ControlName: "Resource", PropertyName: "ActionText", Value: actionText},
                {ControlName: "Resource", PropertyName: "ActionHoverBg", Value: actionHoverBg},
                {ControlName: "Resource", PropertyName: "ActionHoverStroke", Value: actionHoverStroke},
                {ControlName: "Resource", PropertyName: "Accent", Value: progress},
                {ControlName: "Resource", PropertyName: "ProgressBar", Value: progress},
                ; 页签选中背景（主窗口 tabItemStyle 用）
                {ControlName: "Resource", PropertyName: "TabSelBg", Value: tabSelBg},
                {ControlName: "Resource", PropertyName: "BtnPressBg", Value: btnPressBg},
                {ControlName: "Resource", PropertyName: "ActionPressBg", Value: actionPressBg},
                {ControlName: "Resource", PropertyName: "OutlineStroke", Value: outlineStroke},
                ; 下拉弹出层与输入框同色，避免浅色底 + 深色主题文字导致看不清
                {ControlName: "Resource", PropertyName: "DropdownBg", Value: windowBg},
                ; 列表斑马纹：取标题色 RGB，降低透明度，随主题变化
                {ControlName: "Resource", PropertyName: "ListAltBg", Value: AppThemeUtil.MakeListAltBg(titleBg)},
                {ControlName: "Resource", PropertyName: "ListRowAltBg", Value: AppThemeUtil.MakeListRowAltBg(windowBg, actionBg)},
                {ControlName: "Resource", PropertyName: "ListRowForbidBg", Value: AppThemeUtil.MakeListRowForbidBg(windowBg, actionBg)},
                {ControlName: "Resource", PropertyName: "FoldHeaderBg", Value: AppThemeUtil.MakeFoldHeaderBg(windowBg, titleBg)},
                {ControlName: "Resource", PropertyName: "FoldAltBg", Value: AppThemeUtil.MakeFoldAltBg(windowBg, actionBg)},
                {ControlName: "Resource", PropertyName: "FoldDivider", Value: AppThemeUtil.WithAlpha(groupStroke, "55")},
                {ControlName: "DragArea", PropertyName: "Background", Value: titleBg},
                {ControlName: "Window", PropertyName: "Background", Value: windowBg}
            ]
            ui.BatchUpdate(batch)
        } else {
            try ui.Update("Resource", "TitleBarColor", titleBg)
            try ui.Update("Resource", "TitleBarForeground", titleText)
            try ui.Update("Resource", "BgColor", windowBg)
            try ui.Update("Resource", "TextMain", labelColor)
            try ui.Update("Resource", "TextSub", textSub)
            try ui.Update("Resource", "ControlBg", windowBg)
            try ui.Update("Resource", "ControlBorder", groupStroke)
            try ui.Update("Resource", "GroupStroke", groupStroke)
            try ui.Update("Resource", "GraphLine", graphLine)
            try ui.Update("Resource", "GraphConn", graphConn)
            try ui.Update("Resource", "GraphConnSel", graphConnSel)
            try ui.Update("Resource", "InputBg", inputBg)
            try ui.Update("Resource", "InputStroke", inputStroke)
            try ui.Update("Resource", "InputText", inputText)
            try ui.Update("Resource", "EditBg", editBg)
            try ui.Update("Resource", "EditStroke", editStroke)
            try ui.Update("Resource", "EditText", editText)
            try ui.Update("Resource", "EditHoverBg", editHoverBg)
            try ui.Update("Resource", "EditHoverStroke", editHoverStroke)
            try ui.Update("Resource", "ActionBg", actionBg)
            try ui.Update("Resource", "ActionStroke", actionStroke)
            try ui.Update("Resource", "ActionText", actionText)
            try ui.Update("Resource", "ActionHoverBg", actionHoverBg)
            try ui.Update("Resource", "ActionHoverStroke", actionHoverStroke)
            try ui.Update("Resource", "Accent", progress)
            try ui.Update("Resource", "ProgressBar", progress)
            ; 页签选中背景（主窗口 tabItemStyle 用）
            try ui.Update("Resource", "TabSelBg", tabSelBg)
            try ui.Update("Resource", "BtnPressBg", btnPressBg)
            try ui.Update("Resource", "ActionPressBg", actionPressBg)
            try ui.Update("Resource", "OutlineStroke", outlineStroke)
            ; 下拉弹出层与输入框同色，避免浅色底 + 深色主题文字导致看不清
            try ui.Update("Resource", "DropdownBg", windowBg)
            ; 列表斑马纹：取标题色 RGB，降低透明度，随主题变化
            try ui.Update("Resource", "ListAltBg", AppThemeUtil.MakeListAltBg(titleBg))
            try ui.Update("Resource", "ListRowAltBg", AppThemeUtil.MakeListRowAltBg(windowBg, actionBg))
            try ui.Update("Resource", "ListRowForbidBg", AppThemeUtil.MakeListRowForbidBg(windowBg, actionBg))
            try ui.Update("Resource", "FoldHeaderBg", AppThemeUtil.MakeFoldHeaderBg(windowBg, titleBg))
            try ui.Update("Resource", "FoldAltBg", AppThemeUtil.MakeFoldAltBg(windowBg, actionBg))
            try ui.Update("Resource", "FoldDivider", AppThemeUtil.WithAlpha(groupStroke, "55"))
            try ui.Update("DragArea", "Background", titleBg)
            try ui.Update("Window", "Background", windowBg)
        }
    }

    ; 列表交替行背景：标题色半透明（不同主题呈现不同色调）
    static MakeListAltBg(baseColor) {
        c := AppThemeUtil.NormalizeArgb(baseColor)  ; #AARRGGBB
        return "#40" SubStr(c, 4)                   ; ~25% 不透明度
    }

    ; 把 overlay 按 amt(0~1) 混进底色，得到不透明色（斑马纹/模块头跟主题色走）
    static BlendRgb(baseColor, overlayColor, amt) {
        amt := Max(0.0, Min(1.0, Float(amt)))
        b := AppThemeUtil.NormalizeArgb(baseColor)
        o := AppThemeUtil.NormalizeArgb(overlayColor)
        br := Integer("0x" SubStr(b, 4, 2)), bg := Integer("0x" SubStr(b, 6, 2)), bb := Integer("0x" SubStr(b, 8, 2))
        or_ := Integer("0x" SubStr(o, 4, 2)), og := Integer("0x" SubStr(o, 6, 2)), ob := Integer("0x" SubStr(o, 8, 2))
        r := Min(255, Max(0, Round(br * (1 - amt) + or_ * amt)))
        g := Min(255, Max(0, Round(bg * (1 - amt) + og * amt)))
        b2 := Min(255, Max(0, Round(bb * (1 - amt) + ob * amt)))
        return Format("#FF{:02X}{:02X}{:02X}", r, g, b2)
    }

    ; 禁用/跳过：同色轻微下沉，不铺灰块；内容变淡靠 Opacity
    static MakeListRowForbidBg(windowBg, actionBg) {
        factor := (AppThemeUtil.RgbLuma(windowBg) >= 140) ? 0.94 : 0.86
        return AppThemeUtil.AdjustRgbBrightness(windowBg, factor)
    }

    ; 宏行斑马：浅粉（比窗口白粉略深），混入少量操作色
    static MakeListRowAltBg(windowBg, actionBg) {
        c := AppThemeUtil.BlendRgb(windowBg, actionBg, 0.04)
        if (AppThemeUtil.RgbLuma(c) >= AppThemeUtil.RgbLuma(windowBg) - 3)
            c := AppThemeUtil.AdjustRgbBrightness(windowBg, 0.98)
        return c
    }

    ; 模块斑马：混入操作色，比宏行更深一档，无分割线时也能分清
    static MakeFoldAltBg(windowBg, actionBg) {
        c := AppThemeUtil.BlendRgb(windowBg, actionBg, 0.22)
        if (AppThemeUtil.RgbLuma(c) >= AppThemeUtil.RgbLuma(windowBg) - 8)
            c := AppThemeUtil.AdjustRgbBrightness(windowBg, 0.88)
        return c
    }

    static RgbLuma(color) {
        c := AppThemeUtil.NormalizeArgb(color)
        r := Integer("0x" SubStr(c, 4, 2)), g := Integer("0x" SubStr(c, 6, 2)), b := Integer("0x" SubStr(c, 8, 2))
        return Round(0.299 * r + 0.587 * g + 0.114 * b)
    }

    ; 模块头与偶数宏行同色（ControlBg / 窗口底），奇数行才用斑马纹加深
    static MakeFoldHeaderBg(windowBg, titleBg) {
        return windowBg
    }

    ; 按 factor 缩放 RGB（factor<1 略加深，用于按钮按下背景）
    static AdjustRgbBrightness(color, factor := 1.0) {
        c := AppThemeUtil.NormalizeArgb(color)  ; #AARRGGBB
        r := Min(255, Max(0, Round(Integer("0x" SubStr(c, 4, 2)) * factor)))
        g := Min(255, Max(0, Round(Integer("0x" SubStr(c, 6, 2)) * factor)))
        b := Min(255, Max(0, Round(Integer("0x" SubStr(c, 8, 2)) * factor)))
        return Format("#FF{:02X}{:02X}{:02X}", r, g, b)
    }

    ; #AARRGGBB 颜色上叠加透明度：alphaHex 为两位十六进制（"40"≈25%）
    static WithAlpha(color, alphaHex) {
        c := AppThemeUtil.NormalizeArgb(color)      ; #AARRGGBB
        return "#" alphaHex SubStr(c, 4)
    }

    ; 刷新已打开的全部 XAML 窗口（主题确定后主界面、编辑窗、设置窗等）
    static RefreshAllOpenWindows() {
        colors := IsObject(MainSoftData.ThemeColors) ? MainSoftData.ThemeColors : Map()
        try {
            if (IsSet(XAMLHost) && XAMLHost.HasOwnProp("_instances")) {
                for , host in XAMLHost._instances {
                    if (!IsObject(host) || !host.HasProp("wpfHwnd") || !host.wpfHwnd)
                        continue
                    if (!DllCall("user32\IsWindow", "Ptr", host.wpfHwnd, "Int"))
                        continue
                    AppThemeUtil.ApplyWinThemeToXaml(host, colors)
                }
            }
        }
        AppThemeUtil.RefreshOpenSettingWindows()
        if (IsSet(MacroGraphGui) && IsObject(MacroGraphGui))
            try MacroGraphGui.RefreshOpenThemes()
        if (IsSet(MyUIMacroGui) && IsObject(MyUIMacroGui))
            MyUIMacroGui.ApplyThemeColors()
        if (IsSet(MyCMDTipGui) && IsObject(MyCMDTipGui))
            MyCMDTipGui.ApplyThemeColors()
        if (IsSet(MyMenuWheel) && IsObject(MyMenuWheel))
            MyMenuWheel.ApplyThemeColors()
    }

    ; 刷新已打开的通用窗口类设置界面（主题保存后同步）
    ; 用类名字符串动态解析：Worker 未 Include 这些 Gui，直接写类名会触发 #Warn / 编译失败
    static RefreshOpenSettingWindows() {
        classNames := ["HotkeySettingGui", "ToolRecordSettingGui", "MenuWheelGlobalSettingGui",
            "UIMacroPanelSettingGui", "CMDTipSettingGui", "ThemeSettingGui",
            "TimingGui", "MenuMacroSettingGui", "UIMacroSettingGui"]
        for name in classNames {
            try {
                if (!IsSet(%name%))
                    continue
                cls := %name%
                if (!IsObject(cls) || !cls.HasOwnProp("instances"))
                    continue
                for , inst in cls.instances {
                    if (!inst.closed && IsObject(inst.ui))
                        AppThemeUtil.ApplyWinThemeToXaml(inst.ui)
                }
            }
        }
        ; 变量监视器 / 变量修改（非 instances 模式）
        try {
            if (IsSet(MyVarListenGui) && IsObject(MyVarListenGui)
                && !MyVarListenGui.closed && IsObject(MyVarListenGui.ui))
                AppThemeUtil.ApplyWinThemeToXaml(MyVarListenGui.ui)
        }
        try {
            if (IsSet(MyVarListenGui) && IsObject(MyVarListenGui)
                && IsObject(MyVarListenGui.ModifyGui)
                && !MyVarListenGui.ModifyGui.closed && IsObject(MyVarListenGui.ModifyGui.ui))
                AppThemeUtil.ApplyWinThemeToXaml(MyVarListenGui.ModifyGui.ui)
        }
    }

    ; 已收缩：各窗标题栏铬钮请用 Style="{StaticResource TitleBarCloseButton}"（XAML_Host 补丁也会强制套上）。
    ; 本方法仅作旧 InjectResources 兼容，视觉与 TitleBarCloseButton 相同。
    static TitleCloseBtnStyle() {
        return '<Style TargetType="Button"><Setter Property="VerticalAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="border" Property="Background" Value="{DynamicResource BtnPressBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
    }
}
