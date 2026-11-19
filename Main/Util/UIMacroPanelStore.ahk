#Requires AutoHotkey v2.0
#Include FileStamp.ahk

class UIMacroPanelStore {
    static Path(key) {
        global MySoftData
        name := "default"
        try name := MySoftData.CurSettingName
        catch
            name := "default"
        return A_WorkingDir "\Setting\" name "\UIPanelCustom_" String(key) ".json"
    }

    ; ------------------------------------------------------------------
    ; 面板定义的读取与保存
    ;
    ; 读侧缓存：文本按方案文件路径缓存，用「修改时间 + 大小」判活。原来每次读取都是一次
    ; FileExist + FileRead，而读它的路径全是热路径（按键回填、切页、就绪、写入宏），
    ; 一个绑定输入框里每敲一个字就要读一次盘。
    ;
    ; 写侧延迟：只改内存 + 标脏，由 250ms 的泵按「静默 400ms」或「最长 3s」落盘。
    ; 业务（设计器 / 设置页）只管保存，不必关心磁盘；需要立刻可见时调 FlushStore()。
    ; ------------------------------------------------------------------
    static _storeText := Map()      ; 文件路径 → 文本（含未落盘的最新内容）
    static _storeStamp := Map()     ; 文件路径 → 读取时的文件指纹
    static _storeDirty := Map()     ; 文件路径 → true：有未落盘改动
    static _storeLastWriteAt := 0
    static _storeFirstDirtyAt := 0
    static _storePumpOn := false
    static _storePumpFn := 0
    static _StoreDebounceMs := 400
    static _StoreMaxDelayMs := 3000

    static Read(key) {
        p := this.Path(key)
        ; 有未落盘改动：内存就是事实来源（磁盘还是旧内容）
        if (this._storeDirty.Has(p))
            return this._storeText.Has(p) ? this._storeText[p] : ""
        stamp := FileStamp(p)
        if (stamp != "0" && this._storeText.Has(p)
            && this._storeStamp.Has(p) && this._storeStamp[p] == stamp)
            return this._storeText[p]
        text := ""
        if (stamp != "0") {
            try text := FileRead(p, "UTF-8")
            catch
                return this._storeText.Get(p, "")
        }
        this._storeText[p] := text
        this._storeStamp[p] := stamp
        return text
    }

    ; 保存面板定义：只进内存并调度落盘，返回 true 表示已接收
    static Write(key, json, flush := false) {
        p := this.Path(key)
        this._storeText[p] := String(json)
        this._storeDirty[p] := true
        this._StoreSchedule()
        if (flush)
            return this._FlushPath(p)
        return true
    }

    ; 立即把未落盘的定义写盘；key 省略 → 全部。返回写成功的个数。
    static Flush(key := "") {
        if (!IsObject(this._storeDirty) || !this._storeDirty.Count)
            return 0
        only := key == "" ? "" : this.Path(key)
        n := 0
        for p in this._storeDirty.Clone() {
            if (only != "" && p != only)
                continue
            if (this._storeDirty.Has(p) && this._FlushPath(p))
                n += 1
        }
        return n
    }

    static FlushDir(dir) {
        for p in this._storeDirty.Clone() {
            SplitPath p, , &parent
            if (parent = dir && !this._FlushPath(p))
                throw Error(GetLang("写入失败：") p)
        }
    }

    static _FlushPath(p) {
        previous := A_IsCritical
        Critical("On")
        try {
            if (!this._storeDirty.Has(p))
                return true
            if (!this.SaveFile(p, this._storeText[p]))
                return false
            this._storeStamp[p] := FileStamp(p)
            this._storeDirty.Delete(p)
            return true
        } finally Critical(previous)
    }

    ; 导出临时目录也能同步写入，避免把临时路径挂入重试队列。
    static SaveFile(p, json) {
        tmp := p ".tmp"
        f := ""
        try {
            dir := ""
            SplitPath(p, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            f := FileOpen(tmp, "w", "UTF-8")
            f.Write(json)
            f.Close()
            FileMove(tmp, p, 1)
            return true
        } catch {
            try f.Close()
            try FileDelete(tmp)
            return false
        }
    }

    static _StoreSchedule() {
        now := A_TickCount
        this._storeLastWriteAt := now
        if (!this._storeFirstDirtyAt)
            this._storeFirstDirtyAt := now
        if (this._storePumpOn)
            return
        ; 函数引用只取一次：SetTimer 以对象识别定时器，每次新建对象等于叠加定时器。
        ; 静态方法不能直接写 `this._StorePump`（那不是函数对象），必须 ObjBindMethod，
        ; 而 ObjBindMethod 每次都返回新对象，所以缓存进 static。
        if (!this._storePumpFn)
            this._storePumpFn := ObjBindMethod(this, "_StorePump")
        this._storePumpOn := true
        SetTimer(this._storePumpFn, 250)
    }

    static _StorePump() {
        if (!this._storeDirty.Count) {
            SetTimer(this._storePumpFn, 0)
            this._storePumpOn := false
            this._storeFirstDirtyAt := 0
            return
        }
        now := A_TickCount
        idle := now - this._storeLastWriteAt
        age := this._storeFirstDirtyAt ? now - this._storeFirstDirtyAt : 999999
        if (idle < this._StoreDebounceMs && age < this._StoreMaxDelayMs)
            return
        this.Flush()
        if (!this._storeDirty.Count) {
            SetTimer(this._storePumpFn, 0)
            this._storePumpOn := false
            this._storeFirstDirtyAt := 0
        }
    }

    ; 丢弃某 key 的缓存（磁盘被别人改写、文件迁移后使用）
    static _StoreForget(p) {
        if (this._storeText.Has(p))
            this._storeText.Delete(p)
        if (this._storeStamp.Has(p))
            this._storeStamp.Delete(p)
        if (this._storeDirty.Has(p))
            this._storeDirty.Delete(p)
    }

    static Delete(key) {
        p := this.Path(key)
        if (!FileExist(p)) {
            this._StoreForget(p)
            return false
        }
        try {
            FileDelete(p)
            this._StoreForget(p)
            return true
        } catch {
            return false
        }
    }
}
