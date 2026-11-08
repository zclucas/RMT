
    _ParseIgnoreData(text) {
        operations := []
        if (text == "")
            return operations
        if (StrLen(text) > 4 * 1024 * 1024)
            return ""

        totalPoints := 0
        for token in StrSplit(text, ";") {
            fields := StrSplit(token, ":")
            if (fields.Length > 0 && fields[1] == "R")
                continue

            if (fields.Length != 3 || (fields[1] != "B" && fields[1] != "E")
                || !this._IsIgnoreInteger(fields[2]) || fields[3] == "")
                return ""
            size := Integer(fields[2])
            if (size < 1 || size > 3)
                return ""
            points := []
            for pointText in StrSplit(fields[3], "|") {
                pointFields := StrSplit(pointText, ",")
                if (pointFields.Length != 2 || !this._IsIgnoreInteger(pointFields[1])
                    || !this._IsIgnoreInteger(pointFields[2]))
                    return ""
                points.Push({ x: Integer(pointFields[1]), y: Integer(pointFields[2]) })
                if (++totalPoints > 1000000)
                    return ""
            }
            operations.Push({
                type: "stroke", erase: fields[1] == "E", size: size, points: points
            })
            if (operations.Length > 100000)
                return ""
        }
        return operations
    }

    _IsIgnoreInteger(value) {
        value := String(value)
        if (StrLen(value) > 8 || !RegExMatch(value, "^-?\d+$"))
            return false
        try number := Integer(value)
        catch
            return false
        return number >= -1000000 && number <= 1000000
    }

    _SerializeIgnoreData(operations) {
        text := ""
        for operation in operations {
            token := ""
            if (operation.type == "stroke" && IsObject(operation.points)
                && operation.points.Length > 0) {
                pointsText := ""
                for point in operation.points
                    pointsText .= (pointsText == "" ? "" : "|") . Integer(point.x) "," Integer(point.y)
                token := (operation.erase ? "E:" : "B:") Integer(operation.size) ":" pointsText
            }
            if (token != "")
                text .= (text == "" ? "" : ";") token
        }
        return text
    }

    _IgnoreImagePoint(canvasPoint) {
        if (!IsObject(canvasPoint) || this.Zoom <= 0 || this.OrigW <= 0 || this.OrigH <= 0)
            return ""
        imagePoint := this._ToImageFloat(canvasPoint.x, canvasPoint.y)
        if (imagePoint.x < 0 || imagePoint.y < 0
            || imagePoint.x >= this.OrigW || imagePoint.y >= this.OrigH)
            return ""
        return { x: Floor(imagePoint.x), y: Floor(imagePoint.y) }
    }

    OnRightMove(state, ctrl, event) {
        ; 原图页：涂抹走笔迹，其余交给框选/平移
        if (this.EditorMode == "original") {
            if (this.EraseTool == "") {
                if (this.Mode == "crop")
                    this._UpdateCropCursor(this._XY(state, "R"))
                this.OnMove("R", state, ctrl, event)
            }
            return
        }
        ; 匹配页：没开蒙版/橡皮时，拖动 = 平移画布
        if (this.EditorMode == "multi" || this.IgnoreTool == "")
            this.OnMove("R", state, ctrl, event)
    }

    OnIgnoreDown(state, ctrl, event) {
        ; 点位工具优先：选点时不应该触发蒙版涂抹
        if (this.EditorMode == "original") {
            if (this.EraseTool != "")
                this._EraseDown(state)
            else
                this.OnDown("R", state, ctrl, event)
            return
        }
        ; 超多点没开蒙版/橡皮时，按下同样走平移（选色工具的点击由 OnUp 处理）
        if (this.EditorMode == "multi" || this.IgnoreTool == "") {
            this.OnDown("R", state, ctrl, event)
            return
        }
        canvasPoint := this._XY(state, "R")
        imagePoint := this._IgnoreImagePoint(canvasPoint)
        if (!IsObject(imagePoint))
            return

        this.IgnoreDragging := true
        this.IgnoreCurrentOp := {
            type: "stroke", erase: this.IgnoreTool == "eraser",
            size: this.IgnoreBrushSize, points: [imagePoint]
        }
        this._CancelIgnoreOverlay()
        SetTimer(this._ignoreStrokeTimer, 16)
        SetTimer(this._ignoreOverlayTimer, 30)
        this._RefreshIgnoreOverlay()
    }

    _PollIgnoreStroke(*) {
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        canvasPoint := this._RightCanvasPoint()
        imagePoint := this._IgnoreImagePoint(canvasPoint)
        if (IsObject(imagePoint))
            this._AppendIgnorePoint(imagePoint)
        if (!(DllCall("GetAsyncKeyState", "Int", 0x01, "Short") & 0x8000)) {
            this._FinishIgnoreStroke()
        }
    }

    OnIgnoreUp(state, ctrl, event) {
        if (this.EditorMode == "original") {
            if (this.EraseTool != "") {
                if (!this.EraseDragging || !IsObject(this.EraseCurrentOp))
                    return
                imagePoint := this._IgnoreImagePoint(this._XY(state, "R"))
                if (IsObject(imagePoint))
                    this._AppendErasePoint(imagePoint)
                this._FinishEraseStroke()
            } else {
                this.OnUp("R", state, ctrl, event)
            }
            return
        }
        if (this.EditorMode == "multi" || this.IgnoreTool == "") {
            this.OnUp("R", state, ctrl, event)
            return
        }
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        imagePoint := this._IgnoreImagePoint(this._XY(state, "R"))
        if (IsObject(imagePoint))
            this._AppendIgnorePoint(imagePoint)
        this._FinishIgnoreStroke()
    }

    _AppendIgnorePoint(imagePoint) {
        points := this.IgnoreCurrentOp.points
        last := points[points.Length]
        dx := imagePoint.x - last.x
        dy := imagePoint.y - last.y
        steps := Max(Abs(dx), Abs(dy))
        loop steps {
            x := Round(last.x + dx * A_Index / steps)
            y := Round(last.y + dy * A_Index / steps)
            point := { x: x, y: y }
            previous := points[points.Length]
            if (previous.x != x || previous.y != y)
                points.Push(point)
        }
    }

    _FinishIgnoreStroke() {
        if (!this.IgnoreDragging || !IsObject(this.IgnoreCurrentOp))
            return
        SetTimer(this._ignoreStrokeTimer, 0)
        this._CancelIgnoreOverlay()
        operation := this.IgnoreCurrentOp
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        if (operation.points.Length < 1)
            return
        this._PushIgnoreUndo()
        this.IgnoreOps.Push(operation)
        this.SuperIgnoreData := this._SerializeIgnoreData(this.IgnoreOps)
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
    }

    OnIgnoreTool(requestedTool, *) {
        if (this.EditorMode != "super")
            return
        if (this.IgnoreDragging)
            this._FinishIgnoreStroke()
        SetTimer(this._ignoreStrokeTimer, 0)
        this.IgnoreTool := this.IgnoreTool == requestedTool ? "" : requestedTool
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        ; 与基准点互斥：选蒙版就退出选色
        if (this.IgnoreTool != "" && this.PointTool != "") {
            this.PointTool := ""
            this._SyncPointToolControls()
        }
        this._SyncIgnoreControls()
        this._RefreshIgnoreOverlay()
    }

    OnIgnoreSizeSlider(state, ctrl, event) {
        v := (IsObject(state) && state.Has("IgnoreSizeSlider")) ? state["IgnoreSizeSlider"] : ""
        if (!IsNumber(v))
            return
        this.IgnoreBrushSize := Max(1, Min(8, Integer(v)))
        try this.ui.Update("IgnoreSizeVal", "Text", String(this.IgnoreBrushSize))
    }

    _PushIgnoreUndo() {
        this.IgnoreUndo.Push(this._SerializeIgnoreData(this.IgnoreOps))
        if (this.IgnoreUndo.Length > 20)
            this.IgnoreUndo.RemoveAt(1)
    }

    _RestoreIgnoreData(data) {
        operations := this._ParseIgnoreData(data)
        if (!IsObject(operations))
            return false
        this.IgnoreOps := operations
        this.SuperIgnoreData := this._SerializeIgnoreData(operations)
        this.IgnoreDragging := false
        this.IgnoreCurrentOp := ""
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
        return true
    }

    OnIgnoreUndo(*) {
        if (this.IgnoreUndo.Length < 1)
            return
        previous := this.IgnoreUndo.Pop()
        this._RestoreIgnoreData(previous)
    }


    OnIgnoreClear(*) {
        if (this.IgnoreOps.Length < 1)
            return
        this._PushIgnoreUndo()
        this.IgnoreOps := []
        this.SuperIgnoreData := ""
        this._RefreshIgnoreOverlay()
        this._SyncIgnoreControls()
    }
