
    _OnLButtonDown(wParam, lParam, msg, hwnd) {
        ; P6 才接入 XAML 拖拽；此前 WPF 窗口的 WM_LBUTTONDOWN 全部忽略
        if (!this._dragEnabled)
            return
        if (!this.Gui || !WinActive("ahk_id " this.Gui.Hwnd))
            return

        hwndTV := this.MacroTreeViewCon.Hwnd
        isFromLeft := this.DragSourceMap.Has(hwnd)
        isFromTV := (hwnd == hwndTV)

        if (!isFromLeft && !isFromTV)
            return

        dragInfo := ""
        sourceItem := 0
        CoordMode("Mouse", "Screen")
        MouseGetPos(&startX, &startY)

        if (isFromLeft) {
            dragInfo := this.DragSourceMap[hwnd]
        } else {
            hitFlags := 0
            sourceItem := this.TreeViewHitTest(this.MacroTreeViewCon, startX, startY, &hitFlags)
            if (sourceItem == 0)
                return
            ; 点到展开/折叠按钮：不拦截，交给 TreeView 正常处理
            if (hitFlags & 0x0010)  ; TVHT_ONITEMBUTTON
                return

            itemText := this.MacroTreeViewCon.GetText(sourceItem)
            cleanText := CmdStripCurPos(itemText)

            ; ⎖ 開頭的是資訊/控制節點，不參與多選。
            ; 真／假／循環體／條件是可選取的容器節點。
            if (SubStr(cleanText, 1, 1) == "⎖")
                return 1

            ; Ctrl+Click / Shift+Click：進入多選模式，不啟動拖曳。
            ; 使用 Check 狀態作為可視化的多選標記。
            if (GetKeyState("Ctrl", "P") || GetKeyState("Shift", "P")) {
                if (GetKeyState("Shift", "P"))
                    this.SelectMultiRange(this.MultiSelectAnchor, sourceItem)
                else
                    this.ToggleMultiSelection(sourceItem)

                this.CurItemID := sourceItem
                this.MacroTreeViewCon.Modify(sourceItem, "Select")
                return 1
            }

            ; 一般單擊：清掉舊多選，只保留目前項目。
            this.SetSingleMultiSelection(sourceItem)
            this.CurItemID := sourceItem
            this.MacroTreeViewCon.Modify(sourceItem, "Select")

            ; 容器可以被選取，但不當成可拖曳的一般指令。
            if (this.IsContainerNode(itemText))
                return 1

            dragInfo := {name: itemText, gui: "", isMove: true, sourceItem: sourceItem}
        }

        dragStarted := false
        lastTargetItem := -1
        lastMode := 0
        plannedMode := 1
        plannedTarget := 0

        actionVerb := dragInfo.isMove ? GetLang("移动") : GetLang("拖动插入")

        while GetKeyState("LButton", "P") {
            MouseGetPos(&curX, &curY, &curWin, &curCtrlHwnd, 2)
            if (!dragStarted) {
                if (Abs(curX - startX) > 8 || Abs(curY - startY) > 8) {
                    dragStarted := true
                    ; 捕捉滑鼠到 TreeView，防止 WM_LBUTTONUP 流向編輯器造成焦點偷換
                    DllCall("SetCapture", "Ptr", hwndTV)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                }
            }
            if (dragStarted) {
                if (curCtrlHwnd == hwndTV) {
                    targetItem := this.TreeViewHitTest(this.MacroTreeViewCon, curX, curY)

                    mode := 1
                    after := 0

                    if (targetItem == 0) {
                        mode := 1
                    } else {
                        itemText := this.MacroTreeViewCon.GetText(targetItem)
                        cleanText := CmdStripCurPos(itemText)

                        if (SubStr(cleanText, 1, 1) == "⎖" || (dragInfo.isMove && targetItem == dragInfo.sourceItem)) {
                            mode := -1
                        } else if (dragInfo.isMove && this.IsDescendantOrSelf(this.MacroTreeViewCon, dragInfo.sourceItem, targetItem)) {
                            mode := -1
                        } else if (this.IsContainerNode(itemText)) {
                            mode := 5
                        } else {
                            rect := this.GetItemRect(this.MacroTreeViewCon, targetItem)
                            if (rect) {
                                pt := Buffer(8)
                                NumPut("Int", curX, pt, 0)
                                NumPut("Int", curY, pt, 4)
                                DllCall("ScreenToClient", "Ptr", hwndTV, "Ptr", pt)
                                clientY := NumGet(pt, 4, "Int")

                                midY := rect.top + (rect.bottom - rect.top) / 2
                                if (clientY < midY) {
                                    mode := 3
                                    after := 0
                                } else {
                                    mode := 4
                                    after := 1
                                }
                            } else {
                                mode := 4
                                after := 1
                            }
                        }
                    }

                    if (targetItem != lastTargetItem || mode != lastMode) {
                        lastTargetItem := targetItem
                        lastMode := mode

                        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)

                        plannedMode := mode
                        plannedTarget := targetItem

                        if (mode == -1) {
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("提示: 无法移动到此位置"))
                        } else if (mode == 1) {
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 追加到末尾"))
                        } else if (mode == 5) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 内部"))
                        } else if (mode == 3) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 上方"))
                        } else if (mode == 4) {
                            DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 1, "Ptr", targetItem)
                            itemText := this.MacroTreeViewCon.GetText(targetItem)
                            ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 插入到 ") itemText GetLang(" 下方"))
                        }
                    }
                } else if (curCtrlHwnd == this.MacroEditTextCon.Hwnd) {
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                    lastTargetItem := -1
                    lastMode := 0

                    ToolTip(actionVerb ": " dragInfo.name "`n" GetLang("目标: 文本末尾"))
                    plannedMode := 1
                    plannedTarget := 0
                } else {
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
                    DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)
                    lastTargetItem := -1
                    lastMode := 0

                    ToolTip(actionVerb ": " dragInfo.name)
                    plannedMode := -1
                }
            }
            Sleep(30)
        }

        ToolTip() ; Clear tooltip
        DllCall("ReleaseCapture")  ; 釋放滑鼠捕捉
        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x111A, "Ptr", 0, "Ptr", 0)
        DllCall("SendMessage", "Ptr", hwndTV, "UInt", 0x110B, "Ptr", 8, "Ptr", 0)

        if (isFromLeft) {
            if (!dragStarted) {
                ; 沒有拖曳：模擬正常按鈕點擊，追加到末尾
                this.OnOpenSubGui(dragInfo.gui, 1)
            } else if (plannedMode != -1) {
                ; 拖曳並在 TreeView 或 Edit 中釋放
                MouseGetPos(&releaseX, &releaseY, &releaseWin, &releaseCtrlHwnd, 2)
                if (releaseCtrlHwnd == hwndTV || releaseCtrlHwnd == this.MacroEditTextCon.Hwnd) {
                    this.CurItemID := plannedTarget
                    if (this.CurItemID != 0) {
                        this.MacroTreeViewCon.Modify(this.CurItemID, "Select")
                    }
                    this.OnOpenSubGui(dragInfo.gui, plannedMode)
                }
                ; TreeView 外釋放：什麼都不做
            }
            ; 攔截原始 WM_LBUTTONDOWN，防止按鈕的 Click 事件重複觸發
            return 1
        } else {
            ; isFromTV：TreeView 內部指令移動；未拖动时已在按下时完成选中
            if (dragStarted && plannedMode != -1) {
                MouseGetPos(&releaseX, &releaseY, &releaseWin, &releaseCtrlHwnd, 2)
                if (releaseCtrlHwnd == hwndTV) {
                    destParent := 0
                    if (plannedMode == 5) {
                        destParent := plannedTarget
                    } else if (plannedMode == 3 || plannedMode == 4) {
                        destParent := this.MacroTreeViewCon.GetParent(plannedTarget)
                    }
                    this.MoveTreeViewItem(dragInfo.sourceItem, destParent, plannedTarget, plannedMode)
                }
            }
            ; 消费消息，避免过期的 WM_LBUTTONDOWN 再交给 TreeView 破坏选中
            return 1
        }
    }

    ; TreeView 多選視覺高亮：被選中的指令整行都會突出顯示。
    _OnNotify(wParam, lParam, msg, hwnd) {
        if (!this.Gui || !this.MacroTreeViewCon || !lParam)
            return

        treeHwnd := this.MacroTreeViewCon.Hwnd
        if (!treeHwnd)
            return

        ; WM_NOTIFY / NMCUSTOMDRAW / NMTVCUSTOMDRAW
        ; 32 位與 64 位結構的對齊方式不同，這裡使用固定的正確欄位偏移。
        if (A_PtrSize == 8) {
            hdrHwndOffset := 0
            codeOffset := 16
            drawStageOffset := 24
            itemSpecOffset := 56
            clrTextOffset := 80
            clrTextBkOffset := 84
        } else {
            hdrHwndOffset := 0
            codeOffset := 8
            drawStageOffset := 12
            itemSpecOffset := 36
            clrTextOffset := 48
            clrTextBkOffset := 52
        }

        hwndFrom := NumGet(lParam, hdrHwndOffset, "Ptr")
        if (hwndFrom != treeHwnd)
            return

        code := NumGet(lParam, codeOffset, "Int")
        if (code != -12) ; NM_CUSTOMDRAW
            return

        drawStage := NumGet(lParam, drawStageOffset, "UInt")

        ; CDDS_PREPAINT：要求下一階段的 ITEMPREPAINT 通知。
        if (drawStage == 0x00000001)
            return 0x00000020 ; CDRF_NOTIFYITEMDRAW

        ; CDDS_ITEMPREPAINT：針對每個 TreeView item 設定顏色。
        if (drawStage != 0x00010001)
            return

        itemID := NumGet(lParam, itemSpecOffset, "Ptr")
        if (!itemID || !this.MultiSelectItems.Has(itemID))
            return

        ; 多選項目：整行高亮，而不是只靠 CheckBox。
        ; 使用亮藍背景 + 白色文字，滑鼠移開後仍保持。
        NumPut("UInt", 0xFFFFFF, lParam, clrTextOffset)
        NumPut("UInt", 0x2D6CDF, lParam, clrTextBkOffset)

        return 0x00000002 ; CDRF_NEWFONT
    }

    TreeViewHitTest(TVCon, mouseX, mouseY, &flags := 0) {
        hwnd := TVCon.Hwnd
        pt := Buffer(8)
        NumPut("Int", mouseX, pt, 0)
        NumPut("Int", mouseY, pt, 4)
        DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt)
        clientX := NumGet(pt, 0, "Int")
        clientY := NumGet(pt, 4, "Int")

        structSize := A_PtrSize == 8 ? 24 : 16
        tvhti := Buffer(structSize, 0)
        NumPut("Int", clientX, tvhti, 0)
        NumPut("Int", clientY, tvhti, 4)

        hItem := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x1111, "Ptr", 0, "Ptr", tvhti, "Ptr")
        flags := NumGet(tvhti, 8, "UInt")
        return hItem
    }

    IsContainerNode(itemText) {
        cleanItemText := CmdStripCurPos(itemText)
        isCondi := SubStr(cleanItemText, 1, StrLen(GetLang("条件"))) == GetLang("条件")
        return (
            cleanItemText == GetLang("真")
            || cleanItemText == GetLang("假")
            || cleanItemText == GetLang("循环体")
            || isCondi
        )
    }

    ; 真/假/循环体/条件/⎖：可选中，不可拖拽改位置（对齐 CurrentDev）
    _IsImmovableNode(itemText) {
        if (itemText == "")
            return true
        clean := CmdStripCurPos(itemText)
        if (SubStr(clean, 1, 1) == "⎖")
            return true
        return this.IsContainerNode(itemText)
    }

    ; 分栏行 Tag 为 leftId+rightId+inset+view；HitTest 另附 originY|height|originX|width|splitBtn|rowWidth
    _ResolveHit(tagSlot, coord := "") {
        hit := {id: "", slot: "", expander: false, splitBtn: "", lineX: 0, lineW: 0, lineY: -1, hasLineBox: false, rowW: 0}
        if (tagSlot == "")
            return hit
        parts := StrSplit(tagSlot, "|")
        raw := parts[1]
        hit.slot := parts.Length > 1 ? parts[2] : ""
        hit.expander := (parts.Length > 2 && parts[3] == "1")
        if (parts.Length >= 5 && IsNumber(parts[4]) && IsNumber(parts[5])) {
            originY := Number(parts[4])
            h := Number(parts[5])
            hit.lineY := (hit.slot == "top") ? originY : originY + h
        }
        if (parts.Length >= 7 && IsNumber(parts[6]) && IsNumber(parts[7])) {
            hit.lineX := Number(parts[6])
            hit.lineW := Number(parts[7])
            hit.hasLineBox := (hit.lineW > 8)
        }
        if (parts.Length >= 8 && parts[8] != "")
            hit.splitBtn := parts[8]
        if (parts.Length >= 9 && IsNumber(parts[9]))
            hit.rowW := Number(parts[9])
        hit.id := raw
        if (InStr(raw, "+")) {
            ids := StrSplit(raw, "+")
            leftId := ids[1]
            rightId := ids.Length > 1 ? ids[2] : ""
            inset := (ids.Length > 2 && IsNumber(ids[3])) ? Number(ids[3]) : 0
            view := ids.Length > 3 ? ids[4] : "both"
            x := 0
            if (coord != "" && InStr(coord, ";")) {
                xs := StrSplit(coord, ";")[1]
                if (IsNumber(xs))
                    x := Number(xs)
            }
            this._ApplySplitPairHit(&hit, leftId, rightId, inset, view, x)
        }
        return hit
    }

    _ApplySplitPairHit(&hit, leftId, rightId, inset, view, x) {
        btnW := 16
        ; 行宽由引擎在命中结果里一并给出，不用再回读整棵树的 ActualWidth
        aw := hit.rowW
        pairLeft := inset
        pairW := (aw > inset + 20) ? (aw - inset) : 320
        if (hit.hasLineBox && hit.lineW > 40 && hit.lineX <= inset + 2)
            pairW := hit.lineW - inset
        id := leftId
        if (view == "true") {
            id := leftId
            hit.lineX := pairLeft
            hit.lineW := Max(8, pairW - btnW)
            hit.hasLineBox := true
        } else if (view == "false") {
            id := rightId
            hit.lineX := pairLeft + btnW
            hit.lineW := Max(8, pairW - btnW)
            hit.hasLineBox := true
        } else {
            colW := Max(8, (pairW - btnW) / 2)
            mid := pairLeft + colW
            if (x < mid) {
                id := leftId
                hit.lineX := pairLeft
                hit.lineW := colW
            } else if (x > mid + btnW) {
                id := rightId
                hit.lineX := mid + btnW
                hit.lineW := colW
            } else {
                id := (x < mid + btnW / 2) ? leftId : rightId
                hit.hasLineBox := false
                hit.lineY := -1
            }
            if (hit.lineY >= 0)
                hit.hasLineBox := true
        }
        if (id == "")
            id := (leftId != "") ? leftId : rightId
        hit.id := id
    }

    _OnSplitViewClick(token) {
        if (token == "" || !IsObject(this.MacroTreeViewCon))
            return
        parts := StrSplit(token, ":")
        if (parts.Length < 2)
            return
        this.MacroTreeViewCon.ToggleSplitView(parts[2], parts[1])
    }

    GetItemRect(TVCon, hItem) {
        hwnd := TVCon.Hwnd
        rect := Buffer(16, 0)
        NumPut("UPtr", hItem, rect, 0)
        if DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x1104, "Ptr", 0, "Ptr", rect, "Ptr") {
            return {
                left: NumGet(rect, 0, "Int"),
                top: NumGet(rect, 4, "Int"),
                right: NumGet(rect, 8, "Int"),
                bottom: NumGet(rect, 12, "Int")
            }
        }
        return ""
    }

    MoveTreeViewItem(sourceItem, destParent, relativeToItem, mode) {
        sourceText := this.MacroTreeViewCon.GetText(sourceItem)
        if (this._IsImmovableNode(sourceText))
            return ""
        this._PushUndo()
        this.ResetDebugState()
        this.ClearMultiSelection()

        sourceIcon := this.GetCmdIconStr(sourceText)
        sourceParent := this.MacroTreeViewCon.GetParent(sourceItem)

        if (mode == 3) {
            prev := this.MacroTreeViewCon.GetPrev(relativeToItem)
            seq := prev == 0 ? "First" : prev
        } else if (mode == 4) {
            seq := relativeToItem
        } else if (mode == 5) {
            seq := "First"
        } else {
            seq := ""
        }

        newItem := this.MacroTreeViewCon.Add(sourceText, destParent, seq " " sourceIcon)
        this.TreeAddBranch(newItem, sourceText)

        this.MacroTreeViewCon.Delete(sourceItem)

        if (sourceParent != 0) {
            macroStrSource := this.GetTreeMacroStr(sourceParent)
            RealSourceItemID := this.MacroTreeViewCon.GetParent(sourceParent)
            RealSourceCommandStr := this.MacroTreeViewCon.GetText(RealSourceItemID)
            this.SaveCommandData(RealSourceCommandStr, macroStrSource, sourceParent)
        }

        if (destParent != 0) {
            macroStrDest := this.GetTreeMacroStr(destParent)
            RealDestItemID := this.MacroTreeViewCon.GetParent(destParent)
            RealDestCommandStr := this.MacroTreeViewCon.GetText(RealDestItemID)
            this.SaveCommandData(RealDestCommandStr, macroStrDest, destParent)
        }

        ; 移动已由 Add + TreeAddBranch + Delete 增量完成，不再 RefreshTree
        if (destParent != 0) {
            child := this.MacroTreeViewCon.GetChild(destParent)
            while (child) {
                if (this.MacroTreeViewCon.GetText(child) == sourceText) {
                    this.MacroTreeViewCon.Modify(child, "Select")
                    break
                }
                child := this.MacroTreeViewCon.GetNext(child)
            }
        } else {
            this.MacroTreeViewCon.Modify(newItem, "Select")
        }

        this._NotifyMacroChanged()
        return newItem
    }

    IsDescendantOrSelf(TVCon, item, potentialParent) {
        if (potentialParent == 0)
            return false
        if (potentialParent == item)
            return true
        parent := TVCon.GetParent(potentialParent)
        while (parent != 0) {
            if (parent == item)
                return true
            parent := TVCon.GetParent(parent)
        }
        return false
    }
