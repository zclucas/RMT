#Requires AutoHotkey v2.0

; =================================================================
; 语音触发配置窗口（VoiceGui）
; 为单条宏配置「语音唤醒关键词」（VoiceKeywordsArr[index]）。
; 启用/禁用由主界面的「禁用」开关控制（ForbidArr），此处不再提供开关。
; 识别与触发由 Main\Util\VoiceUtil.ahk 交给可替换的底层引擎（默认 sherpa-onnx KWS）。
; =================================================================

#Include ..\Main\Util\JsonUtil.ahk

class VoiceGui {
    __New() {
        this.Gui := ""
        this.hasGui := false      ; 窗口是否存活（Gui 对象 Destroy 后仍非空，需独立标志）
        this.tableItem := ""
        this.index := 0
        this.SureBtnAction := ""
        this.edKeywords := { Value: "" }
    }

    ; ShowGui(tableItem, index)
    ShowGui(tableItem, index, isUpdate := false) {
        if (!CheckIsItemTable(GetTableIndexByID(tableItem.ID)))
            return
        this.tableItem := tableItem
        this.index := index

        ; 读取当前关键词（对象字段，容错）
        curKeywords := ""
        item := tableItem.Items[index]
        if (item)
            curKeywords := item.VoiceKeywords

        ; 复用已存在窗口则刷新（单实例模式）
        if (this.hasGui && this.Gui != "") {
            this._LoadToFields(curKeywords)
            return
        }

        mainGui := IsObject(MainSoftData.MyGui) ? MainSoftData.MyGui.Hwnd : ""
        this.Gui := Gui("+Owner" (mainGui ? mainGui : "") " +AlwaysOnTop", GetLang("语音关键词"))
        this.Gui.SetFont("s11", "微软雅黑")

        ; 说明文案
        this.Gui.Add("Text", "w420 r2 Wrap", GetLang("说出以下关键词即可触发该宏。支持多个关键词，用英文逗号 , 分隔。"))

        ; 关键词输入
        this.Gui.Add("Text", "x16 y30", GetLang("唤醒关键词："))
        this.edKeywords := this.Gui.Add("Edit", "vEdKeywords x16 y52 w420 h120 r4", "")
        this.Gui.Add("Text", "x16 y182 cGray w420", GetLang("示例：开始攻击, 暂停, 保存进度（每个关键词之间用英文逗号分隔）"))

        ; 按钮
        this.Gui.Add("Button", "x170 y214 w90 h32 Default", GetLang("确定"))
            .OnEvent("Click", (*) => this.OnSureClick())
        this.Gui.Add("Button", "x270 y214 w90 h32", GetLang("取消"))
            .OnEvent("Click", (*) => this.Cancel())

        this._LoadToFields(curKeywords)
        this.Gui.OnEvent("Escape", (*) => this.Cancel())
        this.Gui.OnEvent("Close", (*) => this.Cancel())
        this.Gui.Show()
        this.hasGui := true
    }

    _LoadToFields(keywords) {
        this.edKeywords.Value := keywords
        this.Gui.Show()
    }

    ; 收集界面值写回模型
    _ReadFields() {
        keywords := Trim(this.edKeywords.Value)
        keywords := Trim(keywords, "，, ")
        ; 统一关键词内分隔符为英文逗号（兼容中文逗号输入）
        keywords := StrReplace(keywords, "，", ",")
        ; 清理空项与多余空格
        parts := []
        for p in StrSplit(keywords, ",") {
            p := Trim(p)
            if (p != "")
                parts.Push(p)
        }
        clean := ""
        for i, p in parts {
            if (i > 1)
                clean .= ","
            clean .= p
        }
        return clean
    }

    ; 写回表格模型（供语音引擎读取）
    _ApplyToModel(keywords) {
        global MyVoiceEngine, MyHotReloadBus
        tableItem := this.tableItem
        index := this.index
        item := tableItem.Items[index]
        if (!item)
            return
        item.VoiceKeywords := keywords
        ; 启用/禁用由主界面「禁用」开关（Forbid）控制；此处仅保证该行语音字段有效

        ; §18 热重载：广播「本行配置已变更」+ 即时落盘，VoiceEngine 订阅者空闲时重建关键词集（不阻塞 UI）
        HotReloadPublish(GetTableIndexByID(tableItem.ID), index)
    }

    OnSureClick(*) {
        this._DoSure()
    }

    _DoSure() {
        keywords := this._ReadFields()
        this._ApplyToModel(keywords)
        ; 刷新主界面表格，让关键词列立即显示新值
        if (IsSet(MyMainWin) && IsObject(MyMainWin))
            MyMainWin.RenderTab(this.tableItem)
        this.Cancel()
        if (IsObject(this.SureBtnAction))
            this.SureBtnAction.Call()
    }

    Cancel(*) {
        if (this.hasGui) {
            try this.Gui.Destroy()
            catch
                this.Gui := ""
            this.hasGui := false
        }
    }
}