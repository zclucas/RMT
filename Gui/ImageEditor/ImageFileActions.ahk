
    ; 裁剪 / 重命名
    ; ------------------------------------------------------------------
    OnApplyCrop(*) {
        if (this.SelW < 2 || this.SelH < 2)
            return
        src := this.TemplatePath
        tmp := A_Temp "\RMT_crop_tmp.png"
        try FileDelete(tmp)
        ret := DllCall("RMT_OpenCV.dll\CropImageFile", "Str", src
            , "Int", this.SelX, "Int", this.SelY, "Int", this.SelW, "Int", this.SelH
            , "Str", tmp, "CDecl Int")
        if (ret != 1) {
            RmtDialog.Info(GetLang("裁剪失败"), GetLang("图片处理"))
            return
        }

        target := src
        ext := this._Ext(src)
        if (StrLower(ext) != ".png") {
            SplitPath(src, , &dir, , &nameNoExt)
            target := dir "\" nameNoExt ".png"
        }
        ; 先让预览和父窗口释放源文件，再删除/覆盖文件，避免 WPF 句柄导致裁剪失败。
        keptPoints := []
        keptSeeds := []
        keptSuperSeeds := []
        for point in this.Points {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptPoints.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        for point in this.SeedPoints {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptSeeds.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        for point in this.SuperSeedPoints {
            if (point.X >= this.SelX && point.Y >= this.SelY
                && point.X < this.SelX + this.SelW && point.Y < this.SelY + this.SelH)
                keptSuperSeeds.Push({X: point.X - this.SelX, Y: point.Y - this.SelY, Color: point.Color})
        }
        shiftedIgnoreOps := this._OffsetIgnoreOps(this.SelX, this.SelY)
        this._ReleaseFile()
        if (!this._MoveWithRetry(tmp, target)) {
            RmtDialog.Info(GetLang("覆盖原图失败：文件可能被占用"), GetLang("图片处理"))
            return
        }
        if (target != src)
            try FileDelete(src)

        this.TemplatePath := target
        this.Points := keptPoints
        this.SeedPoints := keptSeeds
        this.SuperSeedPoints := keptSuperSeeds
        this.IgnoreOps := shiftedIgnoreOps
        this.SuperIgnoreData := this._SerializeIgnoreData(this.IgnoreOps)
        if ((this.MatchMode == "multi" && this.Points.Length < 1)
            || (this.MatchMode == "super" && this.SuperSeedPoints.Length < 1)) {
            this.MatchMode := ""
            this.EditorMode := "original"
        }
        this.Tol := this.EditorMode == "super" ? this.SuperTolerance : this.NormalTolerance
        this.Zoom := 0
        this.OrigW := 0
        this.OrigH := 0
        this._ResetInteraction()
        ; 应用成功后收工具条、清痕迹、回初始态
        this.Mode := ""
        this.OriginalTool := ""
        this._SyncControls()
        this._ApplyModeStyle()
        this._SyncMatchModeUi()
        this._Render()

        action := this.CropAction
        if (action != "")
            action(target, this.Points, this.SeedPoints, this.SuperSeedPoints, this.SuperIgnoreData)
    }

    _OffsetIgnoreOps(offsetX, offsetY) {
        shifted := []
        for operation in this.IgnoreOps {
            points := []
            for point in operation.points
                points.Push({ x: point.x - offsetX, y: point.y - offsetY })
            shifted.Push({
                type: "stroke", erase: operation.erase, size: operation.size, points: points
            })
        }
        return shifted
    }

    ; 名字改动后才显示重命名图标按钮
    OnNameChanged(*) {
        if (!IsObject(this.ui))
            return
        text := Trim(String(this.ui.Query("NameCon>Text")))
        canRename := (this.TemplatePath != "" && text != "" && text != this._NameBase)
        try this.ui.Update("BtnRename", "IsEnabled", canRename ? "True" : "False")
        try this.ui.Update("BtnRename", "Foreground"
            , canRename ? "{DynamicResource TextMain}" : "{DynamicResource TextSub}")
    }

    OnRename(*) {
        name := Trim(String(this.ui.Query("NameCon>Text")))
        if (name == "" || this.TemplatePath == "")
            return
        SplitPath(this.TemplatePath, , &dir)
        ext := this._Ext(this.TemplatePath)
        name := this._StripExt(name)

        for bad in ["\", "/", ":", "*", "?", Chr(34), "<", ">", "|"]
            name := StrReplace(name, bad, "_")
        if (Trim(name) == "")
            return

        newPath := dir "\" name ext
        if (newPath == this.TemplatePath)
            return
        if FileExist(newPath) {
            RmtDialog.Info(GetLang("同名文件已存在"), GetLang("图片处理"))
            return
        }
        this._ReleaseFile()
        if (!this._MoveWithRetry(this.TemplatePath, newPath)) {
            RmtDialog.Info(GetLang("重命名失败：文件可能被占用"), GetLang("图片处理"))
            return
        }
        this.TemplatePath := newPath
        this._SyncControls()
        this._Render()

        action := this.CropAction
        if (action != "")
            action(newPath, this.Points, this.SeedPoints, this.SuperSeedPoints, this.SuperIgnoreData)
    }
