#Requires AutoHotkey v2.0

; --- Reusable XAML Panel Manager Library ---
; Manages multi-window layout persistence, scaling, theme synchronization, DWM radius,
; and provides a high-performance snapped window follow-drag system using Win32 WinEventHooks.

class PanelManager {
    static Panels := Map()
    static MainWindow := ""
    static CurrentTheme := "Dark Mica (Win 11)"
    static IniFile := "docking_layout.ini"
    static FollowMode := false

    ; --- High-performance Drag-Follow System State ---
    static isMovingPinned := false
    static dragActiveHwnd := 0
    static dragCluster := []
    static dragStartPositions := Map()
    static dragActiveStartPos := ""
    static dragStates := Map()
    static hHook := 0
    static isMainSnappedState := false

    static Trace(msg) {
        try FileAppend(msg "`n", A_Temp "\AhkWpf\AhkTrace.log", "UTF-8")
    }

    static GetWindowRects(hwnd) {
        rx := 0, ry := 0, rw := 0, rh := 0
        try WinGetPos(&rx, &ry, &rw, &rh, "ahk_id " hwnd)

        rect := Buffer(16)
        ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
        if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16) == 0) {
            vx := NumGet(rect, 0, "Int")
            vy := NumGet(rect, 4, "Int")
            vw := NumGet(rect, 8, "Int") - vx
            vh := NumGet(rect, 12, "Int") - vy

            if (vw > 0 && vh > 0) {
                return {
                    raw: { x: rx, y: ry, w: rw, h: rh },
                    vis: { x: vx, y: vy, w: vw, h: vh },
                    offL: vx - rx,
                    offT: vy - ry,
                    offR: (rx + rw) - (vx + vw),
                    offB: (ry + rh) - (vy + vh)
                }
            }
        }

        return {
            raw: { x: rx, y: ry, w: rw, h: rh },
            vis: { x: rx, y: ry, w: rw, h: rh },
            offL: 0, offT: 0, offR: 0, offB: 0
        }
    }

    static GetGenerousSnappedPosition(hwnd, rawX, rawY, &outSnappedX, &outSnappedY) {
        outSnappedX := rawX
        outSnappedY := rawY
        
        try {
            activeId := ""
            if (hwnd == this.MainWindow) {
                activeId := "Main"
            } else {
                for id, pInfo in this.Panels {
                    if (pInfo.GuiHwnd == hwnd) {
                        activeId := id
                        break
                    }
                }
            }
            if (activeId == "")
                return false
                
            activeRects := this.GetWindowRects(hwnd)
            aVis := activeRects.vis
            
            generousThreshold := 24
            snappedX := aVis.x
            snappedY := aVis.y
            
            rects := []
            if (activeId != "Main" && WinExist("ahk_id " this.MainWindow)) {
                mRects := this.GetWindowRects(this.MainWindow)
                if (mRects.raw.x > -10000)
                    rects.Push({ x: mRects.vis.x, y: mRects.vis.y, w: mRects.vis.w, h: mRects.vis.h })
            }
            for id, pInfo in this.Panels {
                if (activeId != id && pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                    pRects := this.GetWindowRects(pInfo.GuiHwnd)
                    if (pRects.raw.x > -10000)
                        rects.Push({ x: pRects.vis.x, y: pRects.vis.y, w: pRects.vis.w, h: pRects.vis.h })
                }
            }
            
            cornerSnapped := false
            for r in rects {
                ; 1. Diagonal touching corners
                if (Abs(aVis.x - (r.x + r.w)) < generousThreshold && Abs(aVis.y - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x + r.w, snappedY := r.y + r.h, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - r.x) < generousThreshold && Abs(aVis.y - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x - aVis.w, snappedY := r.y + r.h, cornerSnapped := true
                } else if (Abs(aVis.x - (r.x + r.w)) < generousThreshold && Abs((aVis.y + aVis.h) - r.y) < generousThreshold) {
                    snappedX := r.x + r.w, snappedY := r.y - aVis.h, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - r.x) < generousThreshold && Abs((aVis.y + aVis.h) - r.y) < generousThreshold) {
                    snappedX := r.x - aVis.w, snappedY := r.y - aVis.h, cornerSnapped := true
                }
                
                ; 2. Side-to-Side touching corners (align top or bottom flush)
                else if (Abs(aVis.x - (r.x + r.w)) < generousThreshold && Abs(aVis.y - r.y) < generousThreshold) {
                    snappedX := r.x + r.w, snappedY := r.y, cornerSnapped := true
                } else if (Abs(aVis.x - (r.x + r.w)) < generousThreshold && Abs((aVis.y + aVis.h) - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x + r.w, snappedY := r.y + r.h - aVis.h, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - r.x) < generousThreshold && Abs(aVis.y - r.y) < generousThreshold) {
                    snappedX := r.x - aVis.w, snappedY := r.y, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - r.x) < generousThreshold && Abs((aVis.y + aVis.h) - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x - aVis.w, snappedY := r.y + r.h - aVis.h, cornerSnapped := true
                }
                
                ; 3. Top-to-Bottom touching corners (align left or right flush)
                else if (Abs(aVis.x - r.x) < generousThreshold && Abs(aVis.y - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x, snappedY := r.y + r.h, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - (r.x + r.w)) < generousThreshold && Abs(aVis.y - (r.y + r.h)) < generousThreshold) {
                    snappedX := r.x + r.w - aVis.w, snappedY := r.y + r.h, cornerSnapped := true
                } else if (Abs(aVis.x - r.x) < generousThreshold && Abs((aVis.y + aVis.h) - r.y) < generousThreshold) {
                    snappedX := r.x, snappedY := r.y - aVis.h, cornerSnapped := true
                } else if (Abs((aVis.x + aVis.w) - (r.x + r.w)) < generousThreshold && Abs((aVis.y + aVis.h) - r.y) < generousThreshold) {
                    snappedX := r.x + r.w - aVis.w, snappedY := r.y - aVis.h, cornerSnapped := true
                }
                
                ; 4. Parallel aligning corners
                if (!cornerSnapped) {
                    if (Abs(aVis.x - r.x) < generousThreshold && Abs(aVis.y - r.y) < generousThreshold) {
                        snappedX := r.x, snappedY := r.y, cornerSnapped := true
                    } else if (Abs((aVis.x + aVis.w) - (r.x + r.w)) < generousThreshold && Abs(aVis.y - r.y) < generousThreshold) {
                        snappedX := r.x + r.w - aVis.w, snappedY := r.y, cornerSnapped := true
                    } else if (Abs(aVis.x - r.x) < generousThreshold && Abs((aVis.y + aVis.h) - (r.y + r.h)) < generousThreshold) {
                        snappedX := r.x, snappedY := r.y + r.h - aVis.h, cornerSnapped := true
                    } else if (Abs((aVis.x + aVis.w) - (r.x + r.w)) < generousThreshold && Abs((aVis.y + aVis.h) - (r.y + r.h)) < generousThreshold) {
                        snappedX := r.x + r.w - aVis.w, snappedY := r.y + r.h - aVis.h, cornerSnapped := true
                    }
                }
                
                if (cornerSnapped)
                    break
            }
            
            if (cornerSnapped) {
                outSnappedX := snappedX - activeRects.offL
                outSnappedY := snappedY - activeRects.offT
                return true
            }
        }
        return false
    }

    static Init(mainInstance, iniPath := "") {
        this.Trace("PanelManager.Init Start Hwnd: " mainInstance.wpfHwnd)
        this.MainInstance := mainInstance
        this.MainWindow := mainInstance.wpfHwnd

        if (iniPath != "") {
            this.IniFile := iniPath
        }

        ; Initialize last known main window position
        try {
            WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
            this.lastMainX := mX
            this.lastMainY := mY
        }

        ; Timers for regular maintenance
        SetTimer(ObjBindMethod(this, "Magnetize"), 30)
        SetTimer(ObjBindMethod(this, "UpdateGlobalSnappedState"), 200)
        SetTimer(ObjBindMethod(this, "Watchdog"), 250)

        ; Register real-time WinEventHook location monitoring for pinned window follow
        this.SetupWinEventHook()

        ; Start CheckPanelMoved timer for MainWindow if it's registered in Panels
        for id, pInfo in this.Panels {
            if (pInfo.GuiHwnd == this.MainWindow) {
                SetTimer(ObjBindMethod(this, "CheckPanelMoved", id), 1000)
                break
            }
        }

        ; Show panels that were open last time
        this.Trace("PanelManager.Init before ShowPanel loop")
        for id, p in this.Panels {
            if (this.GetSavedState(id, "Visible", "0") == "1") {
                this.ShowPanel(id)
            }
        }
        this.Trace("PanelManager.Init successfully completed")
    }

    static RegisterPanel(id, title, defaultX, defaultY, defaultW, defaultH) {
        pinnedVal := this.GetSavedState(id, "Pinned", "0") == "1"
        offX := this.GetSavedState(id, "PinOffsetX", "0")
        offY := this.GetSavedState(id, "PinOffsetY", "0")
        if (offX == "" || !RegExMatch(offX, "^-?\d+$"))
            offX := "0"
        if (offY == "" || !RegExMatch(offY, "^-?\d+$"))
            offY := "0"
        this.Panels[id] := {
            Title: title,
            X: defaultX, Y: defaultY, W: defaultW, H: defaultH,
            Instance: "",
            GuiHwnd: 0,
            Snapped: this.GetSavedState(id, "Snapped", "0") == "1",
            Pinned: pinnedVal,
            PinOffsetX: Integer(offX),
            PinOffsetY: Integer(offY)
        }
    }

    static GetSavedState(id, key, defaultVal := "") {
        try return IniRead(this.IniFile, id, key, defaultVal)
        catch
            return defaultVal
    }

    static SaveState(id, key, val) {
        try IniWrite(val, this.IniFile, id, key)
    }

    ; --- Snapping and Magnetizing Logic ---

    static Magnetize() {
        try {
            static wasDown := false
            isDown := GetKeyState("LButton", "P")

            if (!isDown) {
                if (wasDown && this.dragStates.Has("LastActive")) {
                    ; The mouse was just released. Apply the final snapped state after DragMove completes.
                    lastId := this.dragStates["LastActive"]
                    if (this.dragStates.Has(lastId)) {
                        finalX := this.dragStates[lastId].x
                        finalY := this.dragStates[lastId].y
                        hwnd := lastId == "Main" ? this.MainWindow : this.Panels[lastId].GuiHwnd

                        if (hwnd) {
                            ; Apply generous corner-snapping check on mouse up
                            snappedX := 0, snappedY := 0
                            if (this.GetGenerousSnappedPosition(hwnd, finalX, finalY, &snappedX, &snappedY)) {
                                finalX := snappedX
                                finalY := snappedY
                            }

                            ; In FollowMode, apply final snaps to the entire drag cluster at once in a single transaction
                            if (this.FollowMode && this.dragActiveStartPos && this.dragCluster.Length > 1) {
                                fdx := finalX - this.dragActiveStartPos.x
                                fdy := finalY - this.dragActiveStartPos.y

                                SetTimer(ObjBindMethod(this, "ApplyFinalSnappedPositions", finalX, finalY, fdx, fdy, hwnd, this.dragCluster.Clone(), this.dragStartPositions.Clone()), -50)
                            } else {
                                ; Single window delayed snap lock to override WPF DragMove
                                SetTimer(WinMove.Bind(finalX, finalY, this.dragStates[lastId].w, this.dragStates[lastId].h, "ahk_id " hwnd), -50)
                            }
                        }
                    }

                    ; Reset dragging state
                    this.dragStates := Map()
                    this.dragActiveHwnd := 0
                    this.dragCluster := []
                    this.dragActiveStartPos := ""
                    this.dragStartPositions := Map()
                    wasDown := false
                }
                return
            }
            wasDown := true

            activeHwnd := WinExist("A")
            if !activeHwnd
                return

            ; If dragging a pinned cluster, bypass all custom snapping to prevent tearing
            if (this.dragActiveHwnd != 0 && this.dragCluster.Length > 1)
                return

            isOurs := false
            activeId := ""
            if (activeHwnd == this.MainWindow) {
                isOurs := true
                activeId := "Main"
            } else {
                for id, pInfo in this.Panels {
                    if (pInfo.GuiHwnd == activeHwnd) {
                        isOurs := true
                        activeId := id
                        break
                    }
                }
            }

            if (!isOurs)
                return

            activeRects := this.GetWindowRects(activeHwnd)
            aRaw := activeRects.raw
            aVis := activeRects.vis

            if (aRaw.x < -10000 || aRaw.y < -10000)
                return

            if (!this.dragStates.Has(activeId)) {
                this.dragStates[activeId] := { x: aRaw.x, y: aRaw.y, w: aRaw.w, h: aRaw.h }
                return
            }

            stateObj := this.dragStates[activeId]
            lastX := stateObj.x
            lastY := stateObj.y
            lastW := stateObj.w
            lastH := stateObj.h

            dx := aRaw.x - lastX
            dy := aRaw.y - lastY
            dw := aRaw.w - lastW
            dh := aRaw.h - lastH

            if (dx == 0 && dy == 0 && dw == 0 && dh == 0)
                return

            stateObj.x := aRaw.x
            stateObj.y := aRaw.y
            stateObj.w := aRaw.w
            stateObj.h := aRaw.h

            aX := aVis.x
            aY := aVis.y
            aW := aVis.w
            aH := aVis.h

            rects := []
            if (activeId != "Main" && WinExist("ahk_id " this.MainWindow)) {
                mRects := this.GetWindowRects(this.MainWindow)
                if (mRects.raw.x > -10000)
                    rects.Push({ x: mRects.vis.x, y: mRects.vis.y, w: mRects.vis.w, h: mRects.vis.h, hwnd: this.MainWindow })
            }
            for id, pInfo in this.Panels {
                if (activeId != id && pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                    pRects := this.GetWindowRects(pInfo.GuiHwnd)
                    if (pRects.raw.x > -10000)
                        rects.Push({ x: pRects.vis.x, y: pRects.vis.y, w: pRects.vis.w, h: pRects.vis.h, hwnd: pInfo.GuiHwnd })
                }
            }

            threshold := 16
            snappedX := aX
            snappedY := aY
            snappedW := aW
            snappedH := aH

            isMoving := (dx != 0 || dy != 0) && (dw == 0 && dh == 0)
            isResizingRight := (dw != 0 && dx == 0)
            isResizingLeft := (dw != 0 && dx != 0)
            isResizingBottom := (dh != 0 && dy == 0)
            isResizingTop := (dh != 0 && dy != 0)

            cornerSnapped := false
            if (isMoving) {
                ; 1. Dedicated prioritized corner snapping pass
                for r in rects {
                    ; Diagonal touching corners
                    if (Abs(aX - (r.x + r.w)) < threshold && Abs(aY - (r.y + r.h)) < threshold) {
                        snappedX := r.x + r.w, snappedY := r.y + r.h, cornerSnapped := true
                    } else if (Abs((aX + aW) - r.x) < threshold && Abs(aY - (r.y + r.h)) < threshold) {
                        snappedX := r.x - aW, snappedY := r.y + r.h, cornerSnapped := true
                    } else if (Abs(aX - (r.x + r.w)) < threshold && Abs((aY + aH) - r.y) < threshold) {
                        snappedX := r.x + r.w, snappedY := r.y - aH, cornerSnapped := true
                    } else if (Abs((aX + aW) - r.x) < threshold && Abs((aY + aH) - r.y) < threshold) {
                        snappedX := r.x - aW, snappedY := r.y - aH, cornerSnapped := true
                    }
                    
                    ; Side-to-Side touching corners (align top or bottom flush)
                    else if (Abs(aX - (r.x + r.w)) < threshold && Abs(aY - r.y) < threshold) {
                        snappedX := r.x + r.w, snappedY := r.y, cornerSnapped := true
                    } else if (Abs(aX - (r.x + r.w)) < threshold && Abs((aY + aH) - (r.y + r.h)) < threshold) {
                        snappedX := r.x + r.w, snappedY := r.y + r.h - aH, cornerSnapped := true
                    } else if (Abs((aX + aW) - r.x) < threshold && Abs(aY - r.y) < threshold) {
                        snappedX := r.x - aW, snappedY := r.y, cornerSnapped := true
                    } else if (Abs((aX + aW) - r.x) < threshold && Abs((aY + aH) - (r.y + r.h)) < threshold) {
                        snappedX := r.x - aW, snappedY := r.y + r.h - aH, cornerSnapped := true
                    }
                    
                    ; Top-to-Bottom touching corners (align left or right flush)
                    else if (Abs(aX - r.x) < threshold && Abs(aY - (r.y + r.h)) < threshold) {
                        snappedX := r.x, snappedY := r.y + r.h, cornerSnapped := true
                    } else if (Abs((aX + aW) - (r.x + r.w)) < threshold && Abs(aY - (r.y + r.h)) < threshold) {
                        snappedX := r.x + r.w - aW, snappedY := r.y + r.h, cornerSnapped := true
                    } else if (Abs(aX - r.x) < threshold && Abs((aY + aH) - r.y) < threshold) {
                        snappedX := r.x, snappedY := r.y - aH, cornerSnapped := true
                    } else if (Abs((aX + aW) - (r.x + r.w)) < threshold && Abs((aY + aH) - r.y) < threshold) {
                        snappedX := r.x + r.w - aW, snappedY := r.y - aH, cornerSnapped := true
                    }
                    
                    ; Parallel aligning corners
                    if (!cornerSnapped) {
                        if (Abs(aX - r.x) < threshold && Abs(aY - r.y) < threshold) {
                            snappedX := r.x, snappedY := r.y, cornerSnapped := true
                        } else if (Abs((aX + aW) - (r.x + r.w)) < threshold && Abs(aY - r.y) < threshold) {
                            snappedX := r.x + r.w - aW, snappedY := r.y, cornerSnapped := true
                        } else if (Abs(aX - r.x) < threshold && Abs((aY + aH) - (r.y + r.h)) < threshold) {
                            snappedX := r.x, snappedY := r.y + r.h - aH, cornerSnapped := true
                        } else if (Abs((aX + aW) - (r.x + r.w)) < threshold && Abs((aY + aH) - (r.y + r.h)) < threshold) {
                            snappedX := r.x + r.w - aW, snappedY := r.y + r.h - aH, cornerSnapped := true
                        }
                    }
                    
                    if (cornerSnapped)
                        break
                }
            }

            if (cornerSnapped) {
                ; Prioritized corner snap active, bypass all other snapping logic
            } else {
                ; Snap to screen edges (monitor work area)
                MonitorGetWorkArea(1, &mLeft, &mTop, &mRight, &mBottom)
                if (isMoving) {
                    if (Abs(aX - mLeft) < threshold)
                        snappedX := mLeft
                    else if (Abs((aX + aW) - mRight) < threshold)
                        snappedX := mRight - aW

                    if (Abs(aY - mTop) < threshold)
                        snappedY := mTop
                    else if (Abs((aY + aH) - mBottom) < threshold)
                        snappedY := mBottom - aH
                } else {
                    ; Resizing screen edge snapping
                    if (isResizingRight && Abs((aX + aW) - mRight) < threshold)
                        snappedW := mRight - aX
                    else if (isResizingLeft && Abs(aX - mLeft) < threshold) {
                        snappedX := mLeft
                        snappedW := aW + (aX - mLeft)
                    }

                    if (isResizingBottom && Abs((aY + aH) - mBottom) < threshold)
                        snappedH := mBottom - aY
                    else if (isResizingTop && Abs(aY - mTop) < threshold) {
                        snappedY := mTop
                        snappedH := aH + (aY - mTop)
                    }
                }

                ; Snap to neighbor windows
                for r in rects {
                    vOverlap := (aY < r.y + r.h) && (aY + aH > r.y)
                    hOverlap := (aX < r.x + r.w) && (aX + aW > r.x)

                    if (isMoving) {
                        if (vOverlap) {
                            if (Abs(aX - (r.x + r.w)) < threshold)
                                snappedX := r.x + r.w
                            else if (Abs((aX + aW) - r.x) < threshold)
                                snappedX := r.x - aW
                            else if (Abs(aX - r.x) < threshold)
                                snappedX := r.x
                            else if (Abs((aX + aW) - (r.x + r.w)) < threshold)
                                snappedX := r.x + r.w - aW
                        }

                        if (hOverlap) {
                            if (Abs(aY - (r.y + r.h)) < threshold)
                                snappedY := r.y + r.h
                            else if (Abs((aY + aH) - r.y) < threshold)
                                snappedY := r.y - aH
                            else if (Abs(aY - r.y) < threshold)
                                snappedY := r.y
                            else if (Abs((aY + aH) - (r.y + r.h)) < threshold)
                                snappedY := r.y + r.h - aH
                        }
                    } else {
                        ; Resizing
                        if (vOverlap) {
                            if (isResizingRight && Abs((aX + aW) - r.x) < threshold) {
                                snappedW := r.x - aX
                            } else if (isResizingRight && Abs((aX + aW) - (r.x + r.w)) < threshold) {
                                snappedW := r.x + r.w - aX
                            } else if (isResizingLeft && Abs(aX - (r.x + r.w)) < threshold) {
                                snappedX := r.x + r.w
                                snappedW := aW + (aX - snappedX)
                            } else if (isResizingLeft && Abs(aX - r.x) < threshold) {
                                snappedX := r.x
                                snappedW := aW + (aX - snappedX)
                            }
                        }

                        if (hOverlap) {
                            if (isResizingBottom && Abs((aY + aH) - r.y) < threshold) {
                                snappedH := r.y - aY
                            } else if (isResizingBottom && Abs((aY + aH) - (r.y + r.h)) < threshold) {
                                snappedH := r.y + r.h - aY
                            } else if (isResizingTop && Abs(aY - (r.y + r.h)) < threshold) {
                                snappedY := r.y + r.h
                                snappedH := aH + (aY - snappedY)
                            } else if (isResizingTop && Abs(aY - r.y) < threshold) {
                                snappedY := r.y
                                snappedH := aH + (aY - snappedY)
                            }
                        }
                    }
                }
            }

            if (isMoving && (snappedX != aX || snappedY != aY)) {
                rawSnappedX := snappedX - activeRects.offL
                rawSnappedY := snappedY - activeRects.offT
                snapDx := rawSnappedX - aRaw.x
                snapDy := rawSnappedY - aRaw.y
                WinMove(rawSnappedX, rawSnappedY, , , "ahk_id " activeHwnd)
                
                ; Warp the mouse cursor to match the snap offset and prevent WPF DragMove fighting
                if (snapDx != 0 || snapDy != 0) {
                    pt := Buffer(8)
                    if (DllCall("user32\GetCursorPos", "Ptr", pt)) {
                        mx := NumGet(pt, 0, "Int")
                        my := NumGet(pt, 4, "Int")
                        DllCall("user32\SetCursorPos", "Int", mx + snapDx, "Int", my + snapDy)
                    }
                }
                
                stateObj.x := rawSnappedX
                stateObj.y := rawSnappedY
            } else if (!isMoving && (snappedX != aX || snappedY != aY || snappedW != aW || snappedH != aH)) {
                rawSnappedX := snappedX - activeRects.offL
                rawSnappedY := snappedY - activeRects.offT
                rawSnappedW := snappedW + activeRects.offL + activeRects.offR
                rawSnappedH := snappedH + activeRects.offT + activeRects.offB
                WinMove(rawSnappedX, rawSnappedY, rawSnappedW, rawSnappedH, "ahk_id " activeHwnd)
                stateObj.x := rawSnappedX
                stateObj.y := rawSnappedY
                stateObj.w := rawSnappedW
                stateObj.h := rawSnappedH
            }

            this.dragStates["LastActive"] := activeId
        } catch {
            ; Discard any asynchronous thread-interruption errors safely
        }
    }

    static ApplyFinalPinnedPositions(hwnd, finalX, finalY) {
        this.isMovingPinned := true

        mainX := 0, mainY := 0
        if (hwnd == this.MainWindow) {
            mainX := finalX
            mainY := finalY
        } else {
            draggedId := ""
            for id, pInfo in this.Panels {
                if (pInfo.GuiHwnd == hwnd) {
                    draggedId := id
                    break
                }
            }
            if (draggedId != "") {
                pDrag := this.Panels[draggedId]
                mainX := finalX - pDrag.PinOffsetX
                mainY := finalY - pDrag.PinOffsetY
            } else {
                this.isMovingPinned := false
                return
            }
        }

        moveCount := this.dragCluster.Length
        if (moveCount > 0) {
            hdwp := DllCall("BeginDeferWindowPos", "Int", moveCount, "Ptr")
            if (hdwp) {
                for h in this.dragCluster {
                    targetX := 0, targetY := 0, targetW := 0, targetH := 0
                    if (h == this.MainWindow) {
                        targetX := mainX
                        targetY := mainY
                        WinGetPos(, , &targetW, &targetH, "ahk_id " h)
                    } else {
                        targetId := ""
                        for id, pInfo in this.Panels {
                            if (pInfo.GuiHwnd == h) {
                                targetId := id
                                break
                            }
                        }
                        if (targetId != "") {
                            pTarget := this.Panels[targetId]
                            targetX := mainX + pTarget.PinOffsetX
                            targetY := mainY + pTarget.PinOffsetY
                            WinGetPos(, , &targetW, &targetH, "ahk_id " h)
                        } else {
                            continue
                        }
                    }

                    hdwp := DllCall("DeferWindowPos",
                        "Ptr", hdwp, "Ptr", h, "Ptr", 0,
                        "Int", targetX, "Int", targetY,
                        "Int", targetW, "Int", targetH,
                        "UInt", 0x0014, ; SWP_NOZORDER | SWP_NOACTIVATE
                        "Ptr"
                    )
                }
                DllCall("EndDeferWindowPos", "Ptr", hdwp)
            }
        }

        this.isMovingPinned := false
    }

    ; --- High-performance WinEventHook and BFS-based Connected Cluster Dragging ---

    static SetupWinEventHook() {
        if (this.hHook)
            return

        cb := (hHook, ev, hw, idObj, idCh, dwThread, dwTime) => (
            this.WinEventCallback(ev, hw, idObj)
        )

        ; Hook EVENT_SYSTEM_MOVESIZESTART (0x000A) and EVENT_SYSTEM_MOVESIZEEND (0x000B) to capture absolute start/end states natively
        this.hHook := DllCall("SetWinEventHook",
            "UInt", 0x000A,
            "UInt", 0x000B,
            "Ptr", 0,
            "Ptr", CallbackCreate(cb, "F", 7),
            "UInt", 0,
            "UInt", 0,
            "UInt", 0
        )

        OnExit(ObjBindMethod(this, "CleanupWinEventHook"))
    }

    static CleanupWinEventHook(*) {
        if (this.hHook) {
            DllCall("UnhookWinEvent", "Ptr", this.hHook)
            this.hHook := 0
        }
    }

    static WinEventCallback(event, hwnd, idObject) {
        ; idObject == 0 is OBJID_WINDOW
        if (idObject != 0 || !this.FollowMode)
            return

        static EVENT_SYSTEM_MOVESIZESTART := 0x000A
        static EVENT_SYSTEM_MOVESIZEEND := 0x000B

        ; Resolve the top-level parent window GA_ROOT (2) to ensure robust cross-process child handle mapping
        rootHwnd := DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        if (!rootHwnd)
            rootHwnd := hwnd

        if (event == EVENT_SYSTEM_MOVESIZESTART) {
            ; Verify if the dragged window belongs to our workspace
            ourWindows := this.GetOurWindows()
            isOurs := false
            for h in ourWindows {
                if (h == rootHwnd) {
                    isOurs := true
                    break
                }
            }
            if (!isOurs)
                return

            cluster := this.GetPinnedCluster(rootHwnd)
            if (cluster.Length <= 1) {
                this.dragActiveHwnd := 0
                this.dragCluster := []
                return
            }

            this.dragActiveHwnd := rootHwnd
            this.dragCluster := cluster
            this.dragStartPositions := Map()
            for h in this.dragCluster {
                WinGetPos(&x, &y, &w, &hDim, "ahk_id " h)
                this.dragStartPositions[h] := { x: x, y: y, w: w, h: hDim }
            }

            WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " rootHwnd)
            this.dragActiveStartPos := { x: ax, y: ay, w: aw, h: ah }

            ; Trigger the high-speed 100 FPS coordinate tracking timer
            SetTimer(ObjBindMethod(this, "DragSyncTracker"), 10)
        }
        else if (event == EVENT_SYSTEM_MOVESIZEEND) {
            ; Immediately disable the high-speed polling timer
            SetTimer(ObjBindMethod(this, "DragSyncTracker"), 0)

            ; Query final coordinates (for both single windows and clusters)
            WinGetPos(&aX, &aY, &aW, &aH, "ahk_id " rootHwnd)
            if (aX > -10000 && aY > -10000) {
                ; Apply generous corner-snapping check on movesize loop end
                snappedX := 0, snappedY := 0
                if (this.GetGenerousSnappedPosition(rootHwnd, aX, aY, &snappedX, &snappedY)) {
                    aX := snappedX
                    aY := snappedY
                }

                if (this.dragActiveHwnd == rootHwnd && this.dragCluster.Length > 1) {
                    this.ApplyFinalPinnedPositions(rootHwnd, aX, aY)
                } else {
                    ; Single window final snap lock
                    WinMove(aX, aY, aW, aH, "ahk_id " rootHwnd)
                }

                ; Save final positions of all windows immediately to INI
                if (this.MainWindow && WinExist("ahk_id " this.MainWindow)) {
                    WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
                    if (mX > -10000 && mY > -10000) {
                        mainId := ""
                        for id, pInfo in this.Panels {
                            if (pInfo.GuiHwnd == this.MainWindow) {
                                mainId := id
                                break
                            }
                        }
                        if (mainId != "") {
                            this.Panels[mainId].X := mX
                            this.Panels[mainId].Y := mY
                            this.SaveState(mainId, "X", mX)
                            this.SaveState(mainId, "Y", mY)
                        } else {
                            IniWrite(mX, this.IniFile, "MainWindow", "X")
                            IniWrite(mY, this.IniFile, "MainWindow", "Y")
                        }
                    }
                }
                for id, pInfo in this.Panels {
                    if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                        WinGetPos(&x, &y, &w, &h, "ahk_id " pInfo.GuiHwnd)
                        if (x > -10000 && y > -10000) {
                            pInfo.X := x
                            pInfo.Y := y
                            pInfo.W := w
                            pInfo.H := h
                            this.SaveState(id, "X", x)
                            this.SaveState(id, "Y", y)
                            this.SaveState(id, "W", w)
                            this.SaveState(id, "H", h)
                        }
                    }
                }
            }

            ; Clean up all drag tracking states cleanly
            this.dragStates := Map()
            this.dragActiveHwnd := 0
            this.dragCluster := []
            this.dragActiveStartPos := ""
            this.dragStartPositions := Map()
        }
    }

    static DragSyncTracker() {
        if (this.dragActiveHwnd == 0 || !GetKeyState("LButton", "P")) {
            SetTimer(ObjBindMethod(this, "DragSyncTracker"), 0)
            return
        }

        hwnd := this.dragActiveHwnd
        WinGetPos(&aX, &aY, &aW, &aH, "ahk_id " hwnd)
        if (aX < -10000 || aY < -10000)
            return

        if (!IsObject(this.dragActiveStartPos) || aW != this.dragActiveStartPos.w || aH != this.dragActiveStartPos.h)
            return

        ; Determine implied main window position
        mainX := 0, mainY := 0
        if (hwnd == this.MainWindow) {
            mainX := aX
            mainY := aY
        } else {
            draggedId := ""
            for id, pInfo in this.Panels {
                if (pInfo.GuiHwnd == hwnd) {
                    draggedId := id
                    break
                }
            }
            if (draggedId != "") {
                pDrag := this.Panels[draggedId]
                mainX := aX - pDrag.PinOffsetX
                mainY := aY - pDrag.PinOffsetY
            } else {
                return
            }
        }

        this.isMovingPinned := true
        moveCount := this.dragCluster.Length - 1
        if (moveCount > 0) {
            hdwp := DllCall("BeginDeferWindowPos", "Int", moveCount, "Ptr")
            if (hdwp) {
                for h in this.dragCluster {
                    if (h == hwnd)
                        continue
                    
                    targetX := 0, targetY := 0
                    if (h == this.MainWindow) {
                        targetX := mainX
                        targetY := mainY
                    } else {
                        targetId := ""
                        for id, pInfo in this.Panels {
                            if (pInfo.GuiHwnd == h) {
                                targetId := id
                                break
                            }
                        }
                        if (targetId != "") {
                            pTarget := this.Panels[targetId]
                            targetX := mainX + pTarget.PinOffsetX
                            targetY := mainY + pTarget.PinOffsetY
                        } else {
                            continue
                        }
                    }

                    hdwp := DllCall("DeferWindowPos",
                        "Ptr", hdwp, "Ptr", h, "Ptr", 0,
                        "Int", targetX, "Int", targetY,
                        "Int", 0, "Int", 0,
                        "UInt", 21, ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
                        "Ptr"
                    )
                }
                DllCall("EndDeferWindowPos", "Ptr", hdwp)
            }
        }
        this.isMovingPinned := false
    }

    static GetPinnedCluster(activeHwnd) {
        if (!this.IsWindowPinned(activeHwnd)) {
            return [activeHwnd]
        }

        cluster := []
        if (this.MainWindow && WinExist("ahk_id " this.MainWindow)) {
            cluster.Push(this.MainWindow)
        }
        for id, pInfo in this.Panels {
            if (pInfo.Pinned && pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                isDup := false
                for h in cluster {
                    if (h == pInfo.GuiHwnd) {
                        isDup := true
                        break
                    }
                }
                if (!isDup)
                    cluster.Push(pInfo.GuiHwnd)
            }
        }

        hasActive := false
        for h in cluster {
            if (h == activeHwnd) {
                hasActive := true
                break
            }
        }
        if (!hasActive) {
            cluster.Push(activeHwnd)
        }

        return cluster
    }

    static GetOurWindows() {
        hwnds := []
        if (this.MainWindow && WinExist("ahk_id " this.MainWindow))
            hwnds.Push(this.MainWindow)
        for id, pInfo in this.Panels {
            if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd))
                hwnds.Push(pInfo.GuiHwnd)
        }
        return hwnds
    }

    static AreWindowsSnapped(hwnd1, hwnd2, tol := 8) {
        if (!hwnd1 || !hwnd2 || hwnd1 == hwnd2)
            return false
        if (!WinExist("ahk_id " hwnd1) || !WinExist("ahk_id " hwnd2))
            return false

        r1 := this.GetWindowRects(hwnd1).vis
        r2 := this.GetWindowRects(hwnd2).vis

        if (r1.x < -10000 || r2.x < -10000)
            return false

        vOverlap := (r1.y < r2.y + r2.h + tol) && (r1.y + r1.h > r2.y - tol)
        hOverlap := (r1.x < r2.x + r2.w + tol) && (r1.x + r1.w > r2.x - tol)

        ; Check if touching horizontally
        if (vOverlap) {
            if (Abs(r1.x + r1.w - r2.x) <= tol || Abs(r2.x + r2.w - r1.x) <= tol || Abs(r1.x - r2.x) <= tol || Abs(r1.x + r1.w - (r2.x + r2.w)) <= tol)
                return true
        }

        ; Check if touching vertically
        if (hOverlap) {
            if (Abs(r1.y + r1.h - r2.y) <= tol || Abs(r2.y + r2.h - r1.y) <= tol || Abs(r1.y - r2.y) <= tol || Abs(r1.y + r1.h - (r2.y + r2.h)) <= tol)
                return true
        }

        return false
    }

    static IsWindowPinned(hwnd) {
        if (hwnd == this.MainWindow)
            return true
        for id, pInfo in this.Panels {
            if (pInfo.GuiHwnd == hwnd) {
                return pInfo.HasProp("Pinned") ? pInfo.Pinned : false
            }
        }
        return false
    }

    static TogglePin(id) {
        if (!this.Panels.Has(id))
            return
        pInfo := this.Panels[id]

        ; Only allow pinning when snapped!
        if (!pInfo.Pinned && !pInfo.Snapped) {
            ToolTip("Can only pin when snapped!")
            SetTimer(() => ToolTip(), -2000)
            return
        }

        pInfo.Pinned := !pInfo.Pinned
        this.SaveState(id, "Pinned", pInfo.Pinned ? "1" : "0")

        if (pInfo.Pinned) {
            if (this.MainWindow && WinExist("ahk_id " this.MainWindow) && pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
                WinGetPos(&pX, &pY, , , "ahk_id " pInfo.GuiHwnd)
                pInfo.PinOffsetX := pX - mX
                pInfo.PinOffsetY := pY - mY
                this.SaveState(id, "PinOffsetX", pInfo.PinOffsetX)
                this.SaveState(id, "PinOffsetY", pInfo.PinOffsetY)
            }
            if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                WinSetStyle("-0x40000", "ahk_id " pInfo.GuiHwnd)
                try pInfo.Instance.Update("Window", "ResizeMode", "NoResize")
            }
        } else {
            if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                WinSetStyle("+0x40000", "ahk_id " pInfo.GuiHwnd)
                try pInfo.Instance.Update("Window", "ResizeMode", "CanResize")
            }
        }

        ; Dynamic icon and color update in the local title bar
        if (pInfo.Instance != "") {
            glyph := pInfo.Pinned ? Chr(0xE718) : Chr(0xE840)
            color := pInfo.Pinned ? "#FF00D2FF" : "#E0E0E0"
            btnBg := pInfo.Pinned ? "#2200D2FF" : "Transparent"
            try pInfo.Instance.Update("TxtPinIcon", "Text", glyph)
            try pInfo.Instance.Update("TxtPinIcon", "Foreground", color)
            try pInfo.Instance.Update("BtnPin", "Background", btnBg)
        }

        ; If unpinned, immediately clear it from any active drag cluster
        if (!pInfo.Pinned) {
            if (this.dragActiveHwnd == pInfo.GuiHwnd) {
                this.dragActiveHwnd := 0
                this.dragCluster := []
            }
        }

        ; Force global snap synchronization
        this.UpdateGlobalSnappedState()
    }

    static GetSnappedCluster(activeHwnd, tol := 8) {
        if (!this.IsWindowPinned(activeHwnd)) {
            return [activeHwnd]
        }

        allWindows := this.GetOurWindows()
        cluster := [activeHwnd]
        queue := [activeHwnd]
        visited := Map()
        visited[activeHwnd] := true

        while (queue.Length > 0) {
            current := queue.RemoveAt(1)
            for hwnd in allWindows {
                if (!visited.Has(hwnd)) {
                    if (this.IsWindowPinned(hwnd) && this.AreWindowsSnapped(current, hwnd, tol)) {
                        visited[hwnd] := true
                        cluster.Push(hwnd)
                        queue.Push(hwnd)
                    }
                }
            }
        }
        return cluster
    }

    ; --- Space Filling and Snap Optimization ---

    static AutoFillSpace(id) {
        if (id == "Main") {
            hwnd := this.MainWindow
        } else {
            if (!this.Panels.Has(id) || !this.Panels[id].GuiHwnd)
                return
            hwnd := this.Panels[id].GuiHwnd
        }

        if (!hwnd)
            return
        WinGetPos(&aX, &aY, &aW, &aH, "ahk_id " hwnd)

        rects := []
        if (id != "Main" && WinExist("ahk_id " this.MainWindow)) {
            WinGetPos(&x, &y, &w, &h, "ahk_id " this.MainWindow)
            rects.Push({ x: x, y: y, w: w, h: h })
        }
        for otherId, pInfo in this.Panels {
            if (otherId != id && pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                WinGetPos(&x, &y, &w, &h, "ahk_id " pInfo.GuiHwnd)
                rects.Push({ x: x, y: y, w: w, h: h })
            }
        }

        MonitorGetWorkArea(1, &mLeft, &mTop, &mRight, &mBottom)

        newLeft := mLeft
        newRight := mRight
        newTop := mTop
        newBottom := mBottom

        for r in rects {
            if (r.x + r.w <= aX && r.y < aY + aH && r.y + r.h > aY) {
                if (r.x + r.w > newLeft)
                    newLeft := r.x + r.w
            }
            if (r.x >= aX + aW && r.y < aY + aH && r.y + r.h > aY) {
                if (r.x < newRight)
                    newRight := r.x
            }
            if (r.y + r.h <= aY && r.x < aX + aW && r.x + r.w > aX) {
                if (r.y + r.h > newTop)
                    newTop := r.y + r.h
            }
            if (r.y >= aY + aH && r.x < aX + aW && r.x + r.w > aX) {
                if (r.y < newBottom)
                    newBottom := r.y
            }
        }

        WinMove(newLeft, newTop, newRight - newLeft, newBottom - newTop, "ahk_id " hwnd)
    }

    static UpdateGlobalSnappedState() {
        ; Skip snap/pinned validation completely during active drags to prevent DWM position lags from breaking the cluster
        if (this.dragActiveHwnd != 0 || GetKeyState("LButton", "P"))
            return

        allRects := []
        if (WinExist("ahk_id " this.MainWindow)) {
            mRects := this.GetWindowRects(this.MainWindow)
            if (mRects.raw.x > -10000)
                allRects.Push({ x: mRects.vis.x, y: mRects.vis.y, w: mRects.vis.w, h: mRects.vis.h, id: "Main" })
        }
        for id, pInfo in this.Panels {
            if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                pRects := this.GetWindowRects(pInfo.GuiHwnd)
                if (pRects.raw.x > -10000)
                    allRects.Push({ x: pRects.vis.x, y: pRects.vis.y, w: pRects.vis.w, h: pRects.vis.h, id: id })
            }
        }

        isMainSnapped := false
        for id, pInfo in this.Panels {
            if (!pInfo.GuiHwnd || !WinExist("ahk_id " pInfo.GuiHwnd))
                continue

            pRects := this.GetWindowRects(pInfo.GuiHwnd)
            px := pRects.vis.x
            py := pRects.vis.y
            pw := pRects.vis.w
            ph := pRects.vis.h

            if (pRects.raw.x < -10000)
                continue

            isSnapped := false
            isSnappedToMain := false
            for r in allRects {
                if (r.id == id)
                    continue

                hOverlap := (px < r.x + r.w) && (px + pw > r.x)
                vOverlap := (py < r.y + r.h) && (py + ph > r.y)

                if (vOverlap && (Abs(px - (r.x + r.w)) <= 8 || Abs((px + pw) - r.x) <= 8 || Abs(px - r.x) <= 8 || Abs((px + pw) - (r.x + r.w)) <= 8)) {
                    isSnapped := true
                    if (r.id == "Main")
                        isSnappedToMain := true
                    break
                }
                if (hOverlap && (Abs(py - (r.y + r.h)) <= 8 || Abs((py + ph) - r.y) <= 8 || Abs(py - r.y) <= 8 || Abs((py + ph) - (r.y + r.h)) <= 8)) {
                    isSnapped := true
                    if (r.id == "Main")
                        isSnappedToMain := true
                    break
                }
            }

            if (isSnappedToMain) {
                isMainSnapped := true
            }

            if (pInfo.Snapped != isSnapped) {
                pInfo.Snapped := isSnapped
                this.SaveState(id, "Snapped", isSnapped ? "1" : "0")

                radius := isSnapped ? "0" : IniRead(this.IniFile, "Global", "PanelRadius", "0")
                isTransparent := (pInfo.Instance != "" && HasProp(pInfo.Instance, "xaml") && (InStr(pInfo.Instance.xaml, 'AllowsTransparency="True"') || InStr(pInfo.Instance.xaml, 'AllowsTransparency="true"')))
                if (pInfo.GuiHwnd && !isTransparent) {
                    cornerPref := Buffer(4)
                    NumPut("Int", radius == "0" ? 1 : 0, cornerPref)
                    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", pInfo.GuiHwnd, "UInt", 33, "Ptr", cornerPref.Ptr, "UInt", 4)
                }
                pInfo.Instance.Update("Resource", "PanelRadius", "CornerRadius:" radius)
                pInfo.Instance.Update("Resource", "CloseBtnRadius", "CornerRadius:0," radius ",0,0")
            }

        }

        if (this.isMainSnappedState != isMainSnapped) {
            this.isMainSnappedState := isMainSnapped

            ; Get main window default radius
            mainRadius := isMainSnapped ? "0" : IniRead(this.IniFile, "Global", "PanelRadius", "0")

            ; Apply to DWM corner radius of the main window
            isMainTransparent := (this.MainInstance != "" && HasProp(this.MainInstance, "xaml") && (InStr(this.MainInstance.xaml, 'AllowsTransparency="True"') || InStr(this.MainInstance.xaml, 'AllowsTransparency="true"')))
            if (this.MainWindow && !isMainTransparent) {
                cornerPref := Buffer(4)
                NumPut("Int", mainRadius == "0" ? 1 : 0, cornerPref)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.MainWindow, "UInt", 33, "Ptr", cornerPref.Ptr, "UInt", 4)
            }

            ; Apply to main window resources (close button and window radius)
            if (this.MainInstance) {
                try {
                    this.MainInstance.Update("Resource", "WindowRadius", "CornerRadius:" mainRadius)
                    this.MainInstance.Update("Resource", "CloseBtnRadius", "CornerRadius:0," mainRadius ",0,0")
                }
            }
        }
    }

    ; --- Window Panel Lifecycle and UI Styling Synchronization ---

    static ShowPanel(id) {
        if (this.Panels[id].Instance != "") {
            pInfo := this.Panels[id]
            if (pInfo.GuiHwnd) {
                if (pInfo.Pinned && this.MainWindow && WinExist("ahk_id " this.MainWindow)) {
                    WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
                    x := mX + pInfo.PinOffsetX
                    y := mY + pInfo.PinOffsetY
                    WinMove(x, y, pInfo.W, pInfo.H, "ahk_id " pInfo.GuiHwnd)
                } else {
                    x := this.GetSavedState(id, "X", pInfo.X)
                    y := this.GetSavedState(id, "Y", pInfo.Y)
                    WinMove(x, y, pInfo.W, pInfo.H, "ahk_id " pInfo.GuiHwnd)
                }
            }
            WinActivate("ahk_id " this.Panels[id].GuiHwnd)
            return
        }

        pInfo := this.Panels[id]

        w := this.GetSavedState(id, "W", pInfo.W)
        h := this.GetSavedState(id, "H", pInfo.H)
        
        if (pInfo.Pinned && this.MainWindow && WinExist("ahk_id " this.MainWindow)) {
            WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
            x := mX + pInfo.PinOffsetX
            y := mY + pInfo.PinOffsetY
            pInfo.X := x
            pInfo.Y := y
            this.SaveState(id, "X", x)
            this.SaveState(id, "Y", y)
        } else {
            x := this.GetSavedState(id, "X", pInfo.X)
            y := this.GetSavedState(id, "Y", pInfo.Y)
        }

        titleHeight := "28"
        titleFont := "12"
        btnWidth := "45"

        main := XAML_Generator("Grid").Background("{DynamicResource BgColor}")
        savedScale := IniRead(this.IniFile, "Global", "Scale", "Balanced")
        scaleVal := "1.0"
        if (savedScale == "Thin")
            scaleVal := "0.9"
        else if (savedScale == "Chunky") scaleVal := "1.15"
            main.Add("Grid.LayoutTransform").Add("ScaleTransform").SetProp("x:Name", "AppScale").ScaleX(scaleVal).ScaleY(scaleVal)
        main.Rows(titleHeight, "*")

        tb := main.Add("Border").Grid_Row(0).Background("Transparent").Name("DragArea")
        tbInner := tb.Add("Grid")
        tbInner.Add("TextBlock").Text(pInfo.Title).Foreground("{DynamicResource TextMain}").FontSize(titleFont).FontWeight("SemiBold").VerticalAlignment("Center").Margin("15,0,0,0")

        BtnGroup := tbInner.Add("StackPanel").Orientation("Horizontal").HorizontalAlignment("Right")

        BtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="{DynamicResource ControlBgHover}"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'
        CloseBtnTemplate := '<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource CloseBtnRadius}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#E0FF3333"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>'

        if (this.FollowMode) {
            initialPinGlyph := pInfo.Pinned ? Chr(0xE718) : Chr(0xE840)
            initialPinColor := pInfo.Pinned ? "#FF00D2FF" : "#E0E0E0"
            initialPinBg := pInfo.Pinned ? "#2200D2FF" : "Transparent"

            pinBtn := BtnGroup.Add("Button").Name("BtnPin").WindowChrome_IsHitTestVisibleInChrome("True").Width(btnWidth).Height(titleHeight).Background(initialPinBg).Foreground("{DynamicResource TextMain}").BorderThickness(0)
            pinBtn.InjectResources(BtnTemplate)
            pinBtn.Add("TextBlock").Name("TxtPinIcon").Text(initialPinGlyph).Foreground(initialPinColor).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")
        }

        closeBtn := BtnGroup.Add("Button").Name("BtnClose").WindowChrome_IsHitTestVisibleInChrome("True").Width(btnWidth).Height(titleHeight).Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness(0)
        closeBtn.InjectResources(CloseBtnTemplate)
        closeBtn.Add("TextBlock").Text(Chr(0xE8BB)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(10).VerticalAlignment("Center").HorizontalAlignment("Center")

        body := main.Add("Border").Grid_Row(1).Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,1,0,0")

        if (id == "Terminal") {
            body.Add("ListBox").Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextSub}").FontFamily("Consolas")
                .Add("ListBoxItem").Content("> System Initialized").Parent()
                .Add("ListBoxItem").Content("> Ready for commands...").Parent()
        } else if (id == "Properties") {
            sp := body.Add("StackPanel").Margin("15")
            sp.Add("TextBlock").Text("Name:").Foreground("{DynamicResource TextSub}").Margin("0,0,0,5")
            sp.Add("TextBox").Text("Element1").Margin("0,0,0,15")
            sp.Add("TextBlock").Text("Color:").Foreground("{DynamicResource TextSub}").Margin("0,0,0,5")
            sp.Add("TextBox").Text("#FF0000").Margin("0,0,0,15")
            sp.Add("CheckBox").Content("Is Visible").Foreground("{DynamicResource TextMain}").IsChecked("True")
        } else if (id == "Toolbox") {
            tv := body.Add("TreeView").Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}").Margin("5")
            n1 := tv.Add("TreeViewItem").Header("Controls").IsExpanded("True")
            n1.Add("TreeViewItem").Header("Button")
            n1.Add("TreeViewItem").Header("TextBox")
            n1.Add("TreeViewItem").Header("CheckBox")
            n2 := tv.Add("TreeViewItem").Header("Layout").IsExpanded("True")
            n2.Add("TreeViewItem").Header("Grid")
            n2.Add("TreeViewItem").Header("StackPanel")
        }

        showInAltTab := IniRead(this.IniFile, "Global", "ShowInAltTab", "0") == "1"
        expectedOwner := showInAltTab ? 0 : this.MainWindow
        showInTaskbar := IniRead(this.IniFile, "Global", "ShowInTaskbar", "0") == "1"
        initShowInTaskbar := showInTaskbar ? "True" : "False"

        tmp := StrReplace(XAML_TEMPLATE, "%CaptionHeight%", titleHeight)
        this.Trace("Creating XAMLHost for panel: " id)
        ui := XAMLHost(StrReplace(tmp, "%app%", main.ToString()), "", expectedOwner)

        ui.xaml := StrReplace(ui.xaml, 'Width="940" Height="700"', 'Title="' pInfo.Title '" ShowInTaskbar="' initShowInTaskbar '" Width="' w '" Height="' h '" Left="' x '" Top="' y '"')
        ui.xaml := StrReplace(ui.xaml, 'WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual"')
        ui.xaml := StrReplace(ui.xaml, 'CornerRadius="{DynamicResource WindowRadius}"', 'CornerRadius="{DynamicResource PanelRadius}"')
        initialRadius := pInfo.Snapped ? "0" : IniRead(this.IniFile, "Global", "PanelRadius", "0")

        pTheme := IniRead(this.IniFile, id, "Theme", "Inherit")
        resolvedTheme := (pTheme == "Inherit") ? this.CurrentTheme : pTheme
        iniPath := FindThemesIni()
        themeData := ""
        try themeData := IniRead(iniPath, resolvedTheme)

        resourceInject := '<CornerRadius x:Key="PanelRadius">' initialRadius '</CornerRadius>'
        resourceInject .= '<CornerRadius x:Key="CloseBtnRadius">0,' initialRadius ',0,0</CornerRadius>'
        if (themeData != "") {
            Loop Parse, themeData, "`n", "`r" {
                parts := StrSplit(A_LoopField, "=", " `t", 2)
                if (parts.Length == 2 && InStr(parts[1], "Resource_") == 1) {
                    key := SubStr(parts[1], 10)
                    val := parts[2]
                    if (InStr(val, "#") == 1) {
                        ui.xaml := RegExReplace(ui.xaml, 'i)<SolidColorBrush\s+x:Key="' key '"[^>]*>')
                        resourceInject .= '<SolidColorBrush x:Key="' key '" Color="' val '"/>'
                    }
                }
            }
        }
        ui.xaml := StrReplace(ui.xaml, '%resources%', resourceInject)

        noShadows := this.GetSavedState("Global", "NoShadows", "0") == "1"
        if (noShadows) {
            ui.xaml := StrReplace(ui.xaml, 'GlassFrameThickness="-1"', 'GlassFrameThickness="0" ResizeBorderThickness="6"')
        }

        ui.OnEvent("Window", "LoadedHwnd", (state, ctrl, event) => this.OnPanelLoaded(id, ui))
        ui.OnEvent("Window", "Closing", (state, ctrl, event) => this.OnPanelClosing(id))
        if (this.FollowMode) {
            ui.OnEvent("BtnPin", "Click", (state, ctrl, event) => this.TogglePin(id))
        }

        ui.Show()

        this.Panels[id].Instance := ui
        this.SaveState(id, "Visible", "1")
    }

    static ApplyThemeToPanel(pInfo, themeName) {
        panelId := ""
        for id, p in this.Panels {
            if (p == pInfo) {
                panelId := id
                break
            }
        }
        pTheme := "Inherit"
        if (panelId != "") {
            pTheme := IniRead(this.IniFile, panelId, "Theme", "Inherit")
        }
        resolvedTheme := (pTheme == "Inherit") ? themeName : pTheme

        if (pInfo.Instance == "" || !pInfo.Instance.wpfHwnd)
            return

        try {
            updates := []
            iniPath := FindThemesIni()
            themeData := IniRead(iniPath, resolvedTheme)
            Loop Parse, themeData, "`n", "`r" {
                parts := StrSplit(A_LoopField, "=", " `t", 2)
                if (parts.Length == 2) {
                    key := parts[1]
                    val := parts[2]
                    if (key == "Window_DWM")
                        updates.Push({ ControlName: "Window", PropertyName: "DWM", Value: val })
                    else if (InStr(key, "Resource_") == 1)
                        updates.Push({ ControlName: "Resource", PropertyName: SubStr(key, 10), Value: val })
                }
            }

            radius := pInfo.Snapped ? "0" : IniRead(this.IniFile, "Global", "PanelRadius", "0")
            updates.Push({ ControlName: "Resource", PropertyName: "PanelRadius", Value: "CornerRadius:" radius })
            updates.Push({ ControlName: "Resource", PropertyName: "CloseBtnRadius", Value: "CornerRadius:0," radius ",0,0" })

            if (updates.Length > 0)
                pInfo.Instance.BatchUpdate(updates)

            pInfo.LastThemeApplied := resolvedTheme
        } catch as err {
            pInfo.LastThemeApplied := ""
            this.Trace("ApplyThemeToPanel failed: " err.Message)
        }

        radius := pInfo.Snapped ? "0" : IniRead(this.IniFile, "Global", "PanelRadius", "0")
        isTransparent := (pInfo.Instance != "" && HasProp(pInfo.Instance, "xaml") && (InStr(pInfo.Instance.xaml, 'AllowsTransparency="True"') || InStr(pInfo.Instance.xaml, 'AllowsTransparency="true"')))
        if (pInfo.GuiHwnd && !isTransparent) {
            cornerPref := Buffer(4)
            NumPut("Int", radius == "0" ? 1 : 0, cornerPref)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", pInfo.GuiHwnd, "UInt", 33, "Ptr", cornerPref.Ptr, "UInt", 4)
        }
    }

    static UpdateTheme(themeName) {
        this.CurrentTheme := themeName
        for id, pInfo in this.Panels {
            this.ApplyThemeToPanel(pInfo, themeName)
        }
    }

    static UpdateRadius(radius) {
        for id, pInfo in this.Panels {
            if (pInfo.Instance != "" && pInfo.GuiHwnd) {
                isTransparent := (HasProp(pInfo.Instance, "xaml") && (InStr(pInfo.Instance.xaml, 'AllowsTransparency="True"') || InStr(pInfo.Instance.xaml, 'AllowsTransparency="true"')))
                effectiveRadius := pInfo.Snapped ? "0" : radius
                pInfo.Instance.Update("Resource", "PanelRadius", "CornerRadius:" effectiveRadius)
                pInfo.Instance.Update("Resource", "CloseBtnRadius", "CornerRadius:0," effectiveRadius ",0,0")
                if (!isTransparent) {
                    cornerPref := Buffer(4)
                    NumPut("Int", effectiveRadius == "0" ? 1 : 0, cornerPref)
                    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", pInfo.GuiHwnd, "UInt", 33, "Ptr", cornerPref.Ptr, "UInt", 4)
                }
            }
        }
    }

    static UpdateScale(scale) {
        scaleVal := "1.0"
        if (scale == "Thin")
            scaleVal := "0.9"
        else if (scale == "Chunky") scaleVal := "1.15"
            for id, pInfo in this.Panels {
                if (pInfo.Instance != "" && pInfo.GuiHwnd) {
                    try {
                        pInfo.Instance.Update("AppScale", "ScaleX", scaleVal)
                        pInfo.Instance.Update("AppScale", "ScaleY", scaleVal)
                    }
                }
            }
    }

    static UpdateShadows(enabled) {
        valStr := enabled ? "-1" : "0"
        if (this.MainInstance) {
            isTransparent := (HasProp(this.MainInstance, "xaml") && (InStr(this.MainInstance.xaml, 'AllowsTransparency="True"') || InStr(this.MainInstance.xaml, 'AllowsTransparency="true"')))
            if (!isTransparent) {
                try this.MainInstance.Update("Window", "GlassFrameThickness", valStr)
            }
        }
        for id, pInfo in this.Panels {
            if (pInfo.Instance != "" && pInfo.GuiHwnd) {
                isTransparent := (HasProp(pInfo.Instance, "xaml") && (InStr(pInfo.Instance.xaml, 'AllowsTransparency="True"') || InStr(pInfo.Instance.xaml, 'AllowsTransparency="true"')))
                if (!isTransparent) {
                    try pInfo.Instance.Update("Window", "GlassFrameThickness", valStr)
                }
            }
        }
    }

    static ApplyPanelVisibility(id) {
        pInfo := this.Panels[id]
        if (pInfo.Instance == "" || !pInfo.GuiHwnd)
            return

        showInAltTab := IniRead(this.IniFile, "Global", "ShowInAltTab", "0") == "1"
        showInTaskbar := IniRead(this.IniFile, "Global", "ShowInTaskbar", "0") == "1"

        try {
            valStr := (showInAltTab ? "1" : "0") "," (showInTaskbar ? "1" : "0")
            pInfo.Instance.Update("Window", "ApplyVisibilityStyles", valStr)
        }
    }

    static ApplyVisibilityStyles() {
        for id, pInfo in this.Panels {
            if (pInfo.Instance != "" && pInfo.GuiHwnd) {
                this.ApplyPanelVisibility(id)
            }
        }
    }

    static OnPanelLoaded(id, ui) {
        this.Trace("OnPanelLoaded Start for: " id)
        try {
            this.Panels[id].Instance := ui
            this.Panels[id].GuiHwnd := ui.wpfHwnd

            if (this.FollowMode) {
                try {
                    WinWait("ahk_id " ui.wpfHwnd, , 2)
                    isTransparent := (HasProp(ui, "xaml") && (InStr(ui.xaml, 'AllowsTransparency="True"') || InStr(ui.xaml, 'AllowsTransparency="true"')))
                    if (!isTransparent) {
                        WinSetStyle("-0x10000", "ahk_id " ui.wpfHwnd)
                    }
                    if (this.Panels[id].Pinned) {
                        WinSetStyle("-0x40000", "ahk_id " ui.wpfHwnd)
                        try ui.Update("Window", "ResizeMode", "NoResize")
                    }
                }
            }

            showInAltTab := IniRead(this.IniFile, "Global", "ShowInAltTab", "0") == "1"
            expectedOwner := showInAltTab ? 0 : this.MainWindow
            if (ui.wpfHwnd != this.MainWindow) {
                try ui.Update("Window", "NativeOwner", String(expectedOwner))
            }

            try {
                hIcon := DllCall("user32\SendMessage", "Ptr", this.MainWindow, "UInt", 0x007F, "Ptr", 1, "Ptr", 0, "Ptr") ; WM_GETICON (ICON_BIG)
                if (!hIcon)
                    hIcon := DllCall("user32\SendMessage", "Ptr", this.MainWindow, "UInt", 0x007F, "Ptr", 0, "Ptr", 0, "Ptr")
                if (!hIcon) {
                    if (A_PtrSize == 8)
                        hIcon := DllCall("user32\GetClassLongPtr", "Ptr", this.MainWindow, "Int", -14, "Ptr") ; GCLP_HICON
                    else
                        hIcon := DllCall("user32\GetClassLong", "Ptr", this.MainWindow, "Int", -14, "Ptr")
                }
                if (hIcon)
                    ui.Update("Window", "Icon", "HICON:" hIcon)
            } catch as errIcon {
                this.Trace("Icon inheritance failed: " errIcon.Message)
            }

            try {
                ui.Update("Window", "Title", this.Panels[id].Title)
            } catch as errTitle {
                this.Trace("Title set failed: " errTitle.Message)
            }

            isTransparent := (HasProp(ui, "xaml") && (InStr(ui.xaml, 'AllowsTransparency="True"') || InStr(ui.xaml, 'AllowsTransparency="true"')))
            if (!isTransparent) {
                try {
                    noShadows := IniRead(this.IniFile, "Global", "NoShadows", "0") == "1"
                    valStr := noShadows ? "0" : "-1"
                    ui.Update("Window", "GlassFrameThickness", valStr)
                } catch as errShadows {
                    this.Trace("Shadows update failed: " errShadows.Message)
                }
            }

            try {
                this.ApplyPanelVisibility(id)
            } catch as errVis {
                this.Trace("Visibility styles failed: " errVis.Message)
            }

            try {
                this.ApplyThemeToPanel(this.Panels[id], this.CurrentTheme)
            } catch as errTheme {
                this.Trace("ApplyThemeToPanel failed: " errTheme.Message)
            }

            try {
                fn := %"UpdateBackdropEffects"%
                fn()
            } catch as errBackdrop {
                if !(errBackdrop is TargetError) {
                    this.Trace("Apply backdrop effects failed: " errBackdrop.Message)
                }
            }

            SetTimer(ObjBindMethod(this, "CheckPanelMoved", id), 1000)
            this.Trace("OnPanelLoaded End for: " id " successfully finished")
        } catch as errOuter {
            this.Trace("OnPanelLoaded CRITICAL ERROR for " id ": " errOuter.Message " at line " errOuter.Line)
        }
    }

    static CheckPanelMoved(id) {
        if (!this.Panels.Has(id) || this.Panels[id].Instance == "")
            return

        hwnd := this.Panels[id].GuiHwnd
        if (hwnd && WinExist("ahk_id " hwnd)) {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            if (x != this.Panels[id].X || y != this.Panels[id].Y || w != this.Panels[id].W || h != this.Panels[id].H) {
                this.Panels[id].X := x
                this.Panels[id].Y := y
                this.Panels[id].W := w
                this.Panels[id].H := h
                this.SaveState(id, "X", x)
                this.SaveState(id, "Y", y)
                this.SaveState(id, "W", w)
                this.SaveState(id, "H", h)
            }
        }
    }

    static Watchdog() {
        if (!this.MainWindow || !WinExist("ahk_id " this.MainWindow))
            return

        ; Query current main window position to shift closed pinned panels
        try {
            WinGetPos(&mX, &mY, , , "ahk_id " this.MainWindow)
            if (mX > -10000 && mY > -10000) { ; Ignore minimized state
                if (!this.HasProp("lastMainX") || !this.HasProp("lastMainY")) {
                    this.lastMainX := mX
                    this.lastMainY := mY
                } else {
                    dx := mX - this.lastMainX
                    dy := mY - this.lastMainY
                    if (dx != 0 || dy != 0) {
                        for id, pInfo in this.Panels {
                            if (pInfo.Pinned && (pInfo.Instance == "" || !pInfo.GuiHwnd)) {
                                pInfo.X += dx
                                pInfo.Y += dy
                                this.SaveState(id, "X", pInfo.X)
                                this.SaveState(id, "Y", pInfo.Y)
                            }
                        }
                        this.lastMainX := mX
                        this.lastMainY := mY
                    }
                }
            }
        }

        showInAltTab := IniRead(this.IniFile, "Global", "ShowInAltTab", "0") == "1"
        expectedOwner := showInAltTab ? 0 : this.MainWindow

        for id, pInfo in this.Panels {
            if (pInfo.Instance != "") {
                if (!pInfo.GuiHwnd && pInfo.Instance.wpfHwnd) {
                    pInfo.GuiHwnd := pInfo.Instance.wpfHwnd
                }

                if (pInfo.GuiHwnd && WinExist("ahk_id " pInfo.GuiHwnd)) {
                    if (pInfo.GuiHwnd != this.MainWindow) {
                        try {
                            currentOwner := DllCall("user32\GetWindow", "Ptr", pInfo.GuiHwnd, "UInt", 4, "Ptr") ; GW_OWNER = 4
                            if (currentOwner != expectedOwner) {
                                this.Trace("Watchdog: Reconnecting panel " id)
                                pInfo.Instance.Update("Window", "NativeOwner", String(expectedOwner))
                                this.ApplyPanelVisibility(id)
                            }
                        }
                    }
                }

                    pTheme := IniRead(this.IniFile, id, "Theme", "Inherit")
                    resolvedTheme := (pTheme == "Inherit") ? this.CurrentTheme : pTheme

                    if (!pInfo.HasProp("LastThemeApplied") || pInfo.LastThemeApplied != resolvedTheme) {
                        this.Trace("Watchdog: Syncing theme for panel " id)
                        this.ApplyThemeToPanel(pInfo, this.CurrentTheme)
                    }
                }
            }
        }

    static OnPanelClosing(id) {
        this.Panels[id].Instance := ""
        this.Panels[id].GuiHwnd := 0
        this.SaveState(id, "Visible", "0")
    }

    static IsActiveWindowPinned() {
        try {
            activeHwnd := WinExist("A")
            if (!activeHwnd)
                return false

            isOurs := false
            if (activeHwnd == this.MainWindow) {
                isOurs := true
            } else {
                for id, pInfo in this.Panels {
                    if (pInfo.GuiHwnd == activeHwnd) {
                        isOurs := true
                        break
                    }
                }
            }

            if (!isOurs)
                return false

            if (this.IsWindowPinned(activeHwnd)) {
                cluster := this.GetPinnedCluster(activeHwnd)
                if (cluster.Length > 1)
                    return true
            }
        }
        return false
    }
}

#HotIf PanelManager.IsActiveWindowPinned()
#Left:: return
#Right:: return
#Up:: return
#Down:: return
+#Left:: return
+#Right:: return
+#Up:: return
+#Down:: return
#HotIf