#Requires AutoHotkey v2.0

class RadialMenu {
  Sections := 8
  Sect_Name := Map()
  Sect_Img := Map()
  Sect_Callback := Map()
  Sect_HookFunc := Map()
  RM_Key := "Capslock"
  MacroIndex := 0

  __New() {
    this.Sections := 8
    this.RM_Key := "Capslock"
  }

  SetSections(Sections) {
    this.Sections := Sections
  }

  SetKey(RM_Key) {
    this.RM_Key := RM_Key
  }

  Add(SectionName, SectionImg, ArcNr, Callback := 0) {
    if (this.Sections < ArcNr) {
      this.Sections := ArcNr
    }
    this.Sect_Name[ArcNr] := SectionName
    this.Sect_Img[ArcNr] := SectionImg
    if (IsObject(Callback)) {
      this.Sect_Callback[ArcNr] := Callback
    }
  }

  AddHookFunc(ArcNr, HookFunc) {
    if (IsObject(HookFunc)) {
      this.Sect_HookFunc[ArcNr] := HookFunc
    }
  }

  Show() {
    menuRenderer := RadialMenuRenderer(this)
    result := menuRenderer.Show()

    if (result.Section != 0) {
      if (this.Sect_Callback.Has(result.Section)) {
        try {
          this.Sect_Callback[result.Section].Call(result.Section, result.Name)
        }
      }

      if (this.Sect_HookFunc.Has(result.Section)) {
        try {
          this.Sect_HookFunc[result.Section].Call(result.Section, result.Name)
        }
      }
    }

    return result.Name
  }
}

class RadialMenuRenderer {
  menu := 0
  pToken := 0
  
  __New(menuInstance) {
    this.menu := menuInstance
  }
  
  Show() {
    SectName := ""
    CoordMode "Mouse", "Screen"
    MouseGetPos &X_Center, &Y_Center
    R_1 := 172          ;轮盘外径
    R_2 := R_1 * 0.4    ;轮盘内径
    Offset := 2         ;预选偏移
    PreLen := 12        ;预选 径向宽度
    R_3 := R_1 + Offset * 2 + PreLen  ;预选半径
    R_Icon := R_1 - 45  ;图标绘制半径
    iconWid := 64
    IconHei := 64
    
    
    X_Gui := X_Center - R_3
    Y_Gui := Y_Center - R_3
    Height_Gui := R_3 * 2
    Width_Gui := R_3 * 2
    
    Width := R_3 * 2
    height := R_3 * 2
    
    if WinExist("RM_Menu") {
      Gui("1:Destroy")
    }
    
    this.pToken := Gdip_Startup()
    if !this.pToken {
      MsgBox("Gdiplus failed to start. Please ensure you have gdiplus on your system", "gdiplus error!", "16 T2")
      ExitApp()
    }
    OnExit(this.ExitFunc.Bind(this))
    
    MyGui := Gui("-Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs", "RM_Menu")
    MyGui.Show("NA x" X_Gui " y" Y_Gui " w" Width_Gui " h" Height_Gui)
    hwnd1 := WinExist()
    
    ColorBackGround := "FCFCFC"
    ColorLineBackGround := "C6DFFC"
    ColorSelected := "B8D4F8"
    ColorLineSelected := "F5E5D6"
    
    pBitmap := Map()
    bWidth := Map()
    bHeight := Map()
    X_Bitmap := Map()
    Y_Bitmap := Map()
    Points := Map()
    PointsA := Map()
    
    isGifAnim := Map()
    gifFrameCount := Map()
    gifFrameDelay := Map()
    gifCurrentFrame := Map()
    gifDimensionIDs := Map()
    gifLastFrameTime := Map()
    pGifBitmap := Map()
    gifRealW := Map()
    gifRealH := Map()
    
    Loop this.menu.Sections {
      SectImg := this.menu.Sect_Img.Has(A_Index) ? this.menu.Sect_Img[A_Index] : ""
      isGifAnim[A_Index] := false
      gifCurrentFrame[A_Index] := 0
      gifLastFrameTime[A_Index] := 0
      
      if (SectImg != "") {
        if FileExist(SectImg) {
          if (RegExMatch(SectImg, "i)\.gif$")) {
            pGifBitmap[A_Index] := Gdip_CreateBitmapFromFile(SectImg)
            if (pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
              frameCount := RM_GifGetFrameCount(pGifBitmap[A_Index], &dimensionIDs)
              if (frameCount > 1) {
                isGifAnim[A_Index] := true
                gifFrameCount[A_Index] := frameCount
                gifFrameDelay[A_Index] := RM_GifGetFrameDelay(pGifBitmap[A_Index], frameCount)
                gifDimensionIDs[A_Index] := dimensionIDs
                gifRealW[A_Index] := Gdip_GetImageWidth(pGifBitmap[A_Index])
                gifRealH[A_Index] := Gdip_GetImageHeight(pGifBitmap[A_Index])
                pBitmap[A_Index] := 0
                bWidth[A_Index] := iconWid
                bHeight[A_Index] := 50
              } else {
                pBitmap[A_Index] := pGifBitmap[A_Index]
                pGifBitmap[A_Index] := 0
                bWidth[A_Index] := Gdip_GetImageWidth(pBitmap[A_Index])
                bHeight[A_Index] := Gdip_GetImageHeight(pBitmap[A_Index])
              }
            } else {
              pBitmap[A_Index] := 0
            }
          } else {
            pBitmap[A_Index] := Gdip_CreateBitmapFromFile(SectImg)
          }
        } else {
          pBitmap[A_Index] := 0
        }
      } else {
        pBitmap[A_Index] := 0
      }
      
      if (!isGifAnim[A_Index] && pBitmap[A_Index]) {
        bWidth[A_Index] := Gdip_GetImageWidth(pBitmap[A_Index])
        bHeight[A_Index] := Gdip_GetImageHeight(pBitmap[A_Index])
      } else if (!isGifAnim[A_Index]) {
        bWidth[A_Index] := iconWid
        bHeight[A_Index] := IconHei
      }
    }
    
    Counter := 0
    Loop this.menu.Sections {
      SectionAngle := -1.5707963267948966 + 2 * 3.141592653589793 / this.menu.Sections * (A_Index - 1)

      drawnW := isGifAnim[A_Index] ? iconWid : iconWid
      drawnH := isGifAnim[A_Index] ? IconHei : (pBitmap.Has(A_Index) && pBitmap[A_Index]) ? IconHei * bHeight[A_Index] / bWidth[A_Index] : IconHei
      X_Bitmap[A_Index] := R_3 + R_Icon * Cos(SectionAngle) - drawnW / 2
      Y_Bitmap[A_Index] := R_3 + R_Icon * Sin(SectionAngle) - drawnH / 2
      
      PointsA[A_Index] := Gdip_GetPointsSection(R_3, R_3, R_1 + Offset * 2 + PreLen, R_1 + Offset * 2, this.menu.Sections, Offset, A_Index)
      Points[A_Index] := Gdip_GetPointsSection(R_3, R_3, R_1, R_2, this.menu.Sections, Offset, A_Index)
    }
    
    pBrush := Gdip_BrushCreateSolid("0xFF" ColorBackGround)
    pBrushA := Gdip_BrushCreateSolid("0xFF" ColorSelected)
    pBrushC := Gdip_BrushCreateSolid("0X01" ColorBackGround)
    pPen := Gdip_CreatePen("0xFF" ColorLineBackGround, 1)
    pPenA := Gdip_CreatePen("0xD2" ColorLineSelected, 1)
    
    RM_KeyState_D := 0
    Section_Mouse_Prev := 0
    G := 0
    X_Mouse_P := 0
    Y_Mouse_P := 0
    
    hbm := CreateDIBSection(Width, Height)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hbm)
    G := Gdip_GraphicsFromHDC(hdc)
    Gdip_SetSmoothingMode(G, 4)
    
    Loop {
      currentTime := A_TickCount
      
      needsRedraw := false
      Loop this.menu.Sections {
        if (isGifAnim.Has(A_Index) && isGifAnim[A_Index] && pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
          delay := gifFrameDelay.Has(A_Index) && gifFrameDelay[A_Index].Has(gifCurrentFrame[A_Index]) ? gifFrameDelay[A_Index][gifCurrentFrame[A_Index]] : 100
          if (currentTime - gifLastFrameTime[A_Index] >= delay) {
            gifCurrentFrame[A_Index] := Mod(gifCurrentFrame[A_Index] + 1, gifFrameCount[A_Index])
            gifLastFrameTime[A_Index] := currentTime
            needsRedraw := true
          }
        }
      }
      
      RM_KeyState := GetKeyState(this.menu.RM_Key, "P")
      if !WinExist("RM_Menu") {
        Exit
      }
      if (RM_KeyState == 1) {
        RM_KeyState_D := 1
      }
      if (RM_KeyState == 0 and RM_KeyState_D == 1) {
        MouseGetPos &X_Mouse, &Y_Mouse
        Section_Mouse := RM_GetSection(this.menu.Sections, R_2, X_Center, Y_Center, X_Mouse, Y_Mouse)
        if (Section_Mouse != 0) {
          break
        }
        RM_KeyState_D := 0
      }
      if (GetKeyState("LButton")) {
        MouseGetPos &X_Mouse, &Y_Mouse
        Section_Mouse := RM_GetSection(this.menu.Sections, R_2, X_Center, Y_Center, X_Mouse, Y_Mouse)
        if (Section_Mouse != 0) {
          break
        }
        if (Section_Mouse == 0) {
          SectName := ""
          break
        }
      }
      if GetKeyState("Escape") {
        Section_Mouse := 0 
        SectName := ""
        break
      }
      
      MouseGetPos &X_Mouse, &Y_Mouse
      X_Rel := X_Mouse - X_Center
      Y_Rel := Y_Mouse - Y_Center
      Center_Distance := Sqrt(X_Rel * X_Rel + Y_Rel * Y_Rel)
      
      Section_Mouse := RM_GetSection(this.menu.Sections, R_2, X_Center, Y_Center, X_Mouse, Y_Mouse)
      
      if (Center_Distance > R_1) {
        break
      }
      if (Section_Mouse == 0) {
        ToolTip()
        SectName := ""
      }
      if (Section_Mouse > 0) {
        Counter++
        SectName_N := this.menu.Sect_Name.Has(Section_Mouse) ? this.menu.Sect_Name[Section_Mouse] : ""
        
        if ((X_Mouse_P != X_Mouse) or (Y_Mouse_P != Y_Mouse) or SectName_N != SectName or Counter > 500) {
          SectName := SectName_N
          X_Mouse_P := X_Mouse
          Y_Mouse_P := Y_Mouse
          if (Counter > 500 or SectName_N != SectName) {
            ToolTip(SectName)
            Counter := 0
          }
        }
      }
      if (Section_Mouse != Section_Mouse_Prev or A_Index == 1 or needsRedraw) {
        Gdip_GraphicsClear(G)
        Gdip_FillEllipse(G, pBrushC, R_3 - R_1, R_3 - R_1, 2 * R_1, 2 * R_1)
        
        Loop this.menu.Sections {
          SectionAngle := -1.5707963267948966 + 2 * 3.141592653589793 / this.menu.Sections * (A_Index - 1)
          drawName := this.menu.Sect_Name.Has(A_Index) ? this.menu.Sect_Name[A_Index] : ""
          if (A_Index == Section_Mouse) {
            Gdip_FillPolygon(G, pBrushA, Points[A_Index])
            Gdip_DrawLines(G, pPenA, Points[A_Index])
            Gdip_FillPolygon(G, pBrushA, PointsA[A_Index])
            Gdip_DrawLines(G, pPenA, PointsA[A_Index])
          } else {
            Gdip_FillPolygon(G, pBrush, Points[A_Index])
            Gdip_DrawLines(G, pPen, Points[A_Index])
          }
          SectImg := this.menu.Sect_Img.Has(A_Index) ? this.menu.Sect_Img[A_Index] : ""
          if (isGifAnim.Has(A_Index) && isGifAnim[A_Index] && pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
            DllCall("gdiplus\GdipImageSelectActiveFrame", "ptr", pGifBitmap[A_Index], "ptr", gifDimensionIDs[A_Index], "int", gifCurrentFrame[A_Index])
            gw := gifRealW.Has(A_Index) ? gifRealW[A_Index] : iconWid
            gh := gifRealH.Has(A_Index) ? gifRealH[A_Index] : IconHei
            Gdip_DrawImage(G, pGifBitmap[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], iconWid, IconHei, 0, 0, gw, gh)
          } else if (pBitmap.Has(A_Index) && pBitmap[A_Index]) {
            Gdip_DrawImage(G, pBitmap[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], iconWid, IconHei * bHeight[A_Index] / bWidth[A_Index], 0, 0, bWidth[A_Index], bHeight[A_Index])
          }
          if (drawName != "") {
            if (SectImg == "") {
              Gdip_TextToGraphics(G, drawName, "vCenter x" (X_Bitmap[A_Index] - 40 + 16) " y" (Y_Bitmap[A_Index] - 40 + 16), "", "64", "64")
            }
          } else {
            Gdip_TextToGraphics(G, A_Index, "vCenter cFF888888 x" (X_Bitmap[A_Index] - 40 + 16) " y" (Y_Bitmap[A_Index] - 40 + 16), "", "64", "64")
          }
        }
        
        UpdateLayeredWindow(hwnd1, hdc, X_Gui, Y_Gui, Width, Height)
      }
      Section_Mouse_Prev := Section_Mouse
    }
    
    ToolTip()
    
    if (hdc) {
      SelectObject(hdc, obm)
      DeleteObject(hbm)
      DeleteDC(hdc)
    }
    if (G) {
      Gdip_DeleteGraphics(G)
    }
    
    Loop this.menu.Sections {
      if (pBitmap.Has(A_Index) && pBitmap[A_Index]) {
        Gdip_DisposeImage(pBitmap[A_Index])
      }
      if (pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
        Gdip_DisposeImage(pGifBitmap[A_Index])
      }
    }
    
    Gdip_DeleteBrush(pBrushC)
    Gdip_DeleteBrush(pBrush)
    Gdip_DeleteBrush(pBrushA)
    Gdip_DeletePen(pPen)
    Gdip_DeletePen(pPenA)
    Gdip_Shutdown(this.pToken)
    this.pToken := 0
    MyGui.Destroy()
    MouseGetPos &X_Mouse, &Y_Mouse
    Section_Mouse := RM_GetSection(this.menu.Sections, R_2, X_Center, Y_Center, X_Mouse, Y_Mouse)
    
    finalName := ""
    if (Section_Mouse > 0 && this.menu.Sect_Name.Has(Section_Mouse)) {
      finalName := this.menu.Sect_Name[Section_Mouse]
    }
    
    return { Section: Section_Mouse, Name: finalName }
  }
  
  ExitFunc(*) {
    if (this.pToken) {
      Gdip_Shutdown(this.pToken)
    }
    return
  }
}

Gdip_GetPointsSection(X_Center, Y_Center, R_1, R_2, Sections, Offset, Section := 1) {
  Section := Section - 1
  SectionAngle := 2 * 3.141592653589793 / Sections
  R_2_Min := 4 * Offset / Sin(SectionAngle)
  R_2 := R_2 > R_2_Min ? R_2 : R_2_Min
  SweepAngle := ACos((R_1 * Cos(SectionAngle / 2) + Offset * Sin(SectionAngle / 2)) / R_1) * 2
  SweepAngle_2 := ACos((R_2 * Cos(SectionAngle / 2) + Offset * Sin(SectionAngle / 2)) / R_2) * 2  
  
  Loop_Sections := Round(R_1 * SweepAngle)
  StartAngle := -SweepAngle / 2 - 1.5707963267948966 + SectionAngle * (Section)
  Points := ""
  Loop Loop_Sections {
    Angle := StartAngle + (A_Index - 1) * SweepAngle / (Loop_Sections - 1)
    X_Arc := Round(X_Center + R_1 * Cos(Angle))
    Y_Arc := Round(Y_Center + R_1 * Sin(Angle))
    if (A_Index == 1) {
      Points := X_Arc "," Y_Arc
      X_Arc_Start := X_Arc
      Y_Arc_Start := Y_Arc
      continue
    }
    Points .= "|" X_Arc "," Y_Arc
  }
  
  Loop_Sections := Round(R_2 * SweepAngle_2)
  StartAngle_2 := SweepAngle_2 / 2 - 1.5707963267948966 + SectionAngle * (Section)
  Loop Loop_Sections {
    Angle := StartAngle_2 - (A_Index - 1) * SweepAngle_2 / (Loop_Sections - 1)
    X_Arc := Round(X_Center + R_2 * Cos(Angle))
    Y_Arc := Round(Y_Center + R_2 * Sin(Angle))
    Points .= "|" X_Arc "," Y_Arc
  }
  
  Points .= "|" X_Arc_Start "," Y_Arc_Start
  
  return Points
}

RM_GetSection(Sections, R_2, X_Center, Y_Center, X_Mouse, Y_Mouse) {
  Section_Mouse := 0
  X_Rel := X_Mouse - X_Center
  Y_Rel := Y_Mouse - Y_Center 
  Distance_Center := Sqrt(X_Rel * X_Rel + Y_Rel * Y_Rel)
  if (X_Rel == 0) {
     X_Rel := 0.01
  }
  if (Y_Rel == 0) {
     Y_Rel := 0.01
  }
  if (Distance_Center < R_2) {
    Section_Mouse := 0
    return Section_Mouse
  } else if (Distance_Center > R_2) {
    a := X_Rel == 0 ? (Y_Rel == 0 ? 0 : Y_Rel > 0 ? 90 : 270) : ATan(Y_Rel / X_Rel) * 57.2957795130823209
    Angle := X_Rel < 0 ? 180 + a : a < 0 ? 360 + a : a
    MouseAngle := Mod(Angle + 90, 360)
    MinDist := 999
    Section_Mouse := 1
    Loop Sections {
      CenterAngle := 360 * (A_Index - 1) / Sections
      Dist := Abs(MouseAngle - CenterAngle)
      if (Dist > 180)
        Dist := 360 - Dist
      if (Dist < MinDist) {
        MinDist := Dist
        Section_Mouse := A_Index
      }
    }
  }
  return Section_Mouse
}

RM_GifGetFrameCount(pBitmap, &dimensionIDs) {
  frameDimensions := 0
  count := 0
  DllCall("gdiplus\GdipImageGetFrameDimensionsCount", "ptr", pBitmap, "uint*", &frameDimensions)
  dimIDs := Buffer(16 * frameDimensions)
  DllCall("gdiplus\GdipImageGetFrameDimensionsList", "ptr", pBitmap, "ptr", dimIDs, "uint", frameDimensions)
  DllCall("gdiplus\GdipImageGetFrameCount", "ptr", pBitmap, "ptr", dimIDs, "uint*", &count)
  dimensionIDs := dimIDs
  return count
}

RM_GifGetFrameDelay(pBitmap, targetCount := 0) {
  static PropertyTagFrameDelay := 0x5100
  itemSize := 0
  DllCall("gdiplus\GdipGetPropertyItemSize", "ptr", pBitmap, "uint", PropertyTagFrameDelay, "uint*", &itemSize)
  
  if (itemSize < 16) {
    outArray := []
    Loop (targetCount > 0 ? targetCount : 1) {
      outArray.Push(100)
    }
    return outArray
  }
  
  item := Buffer(itemSize)
  DllCall("gdiplus\GdipGetPropertyItem", "ptr", pBitmap, "uint", PropertyTagFrameDelay, "uint", itemSize, "ptr", item)
  propLen := NumGet(item, 4, "UInt")
  propValPtr := NumGet(item, 8 + A_PtrSize, "Ptr")
  
  frameDelay := []
  rawCount := propLen // 4
  Loop (rawCount) {
    n := NumGet(propValPtr + (A_Index - 1) * 4, "UInt") * 10
    frameDelay.Push(n ? n : 100)
  }
  
  if (targetCount > 0 && frameDelay.Length < targetCount) {
    lastDelay := frameDelay.Length ? frameDelay[frameDelay.Length - 1] : 100
    Loop (targetCount - frameDelay.Length) {
      frameDelay.Push(lastDelay)
    }
  }
  
  return frameDelay.Length ? frameDelay : [100]
}
