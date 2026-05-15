#Requires AutoHotkey v2.0
#Include Main\Util\Gdip_All.ahk

class RadialMenuRenderer {
  menu := 0
  pToken := 0
  
  __New(menuInstance) {
    This.menu := menuInstance
  }
  
  Show() {
    SectName := ""
    CoordMode "Mouse", "Screen"
    MouseGetPos &X_Center, &Y_Center, &hwndUnderMouse
    if (hwndUnderMouse && WinExist("ahk_id " hwndUnderMouse)) {
      WinGetPos &X_Win, &Y_Win,,, "ahk_id " hwndUnderMouse
    } else {
      X_Win := 0
      Y_Win := 0
    }
    CoordMode "Mouse", "Window"
    R_1 := 100
    R_2 := R_1 * 0.2
    Offset := 2
    R_3 := R_1 + Offset * 2 + 10
    
    X_Gui := X_Center - R_3 + X_Win
    Y_Gui := Y_Center - R_3 + Y_Win
    Height_Gui := R_3 * 2
    Width_Gui := R_3 * 2
    
    Width := R_3 * 2
    height := R_3 * 2
    
    if WinExist("RM_Menu") {
      Gui("1:Destroy")
    }
    
    This.pToken := Gdip_Startup()
    if !This.pToken {
      MsgBox("Gdiplus failed to start. Please ensure you have gdiplus on your system", "gdiplus error!", "16 T2")
      ExitApp()
    }
    OnExit(This.ExitFunc.Bind(This))
    
    MyGui := Gui("-Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs", "RM_Menu")
    MyGui.Show("NA x" X_Gui " y" Y_Gui " w" Width_Gui " h" Height_Gui)
    hwnd1 := WinExist()
    
    MouseGetPos &X_Center, &Y_Center
    ColorBackGround := "FCFCFC"
    ColorLineBackGround := "C6DFFC"
    ColorSelected := "C6DFFC"
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
    
    Loop This.menu.Sections {
      SectImg := This.menu.Sect_Img.Has(A_Index) ? This.menu.Sect_Img[A_Index] : ""
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
                bWidth[A_Index] := 32
                bHeight[A_Index] := 32
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
        bWidth[A_Index] := 32
        bHeight[A_Index] := 32
      }
    }
    
    Counter := 0
    Loop This.menu.Sections {
      SectionAngle := 2 * 3.141592653589793 / This.menu.Sections * (A_Index - 1)
      
      X_Bitmap[A_Index] := R_3 + (R_1 - 30) * Cos(SectionAngle) - 16
      Y_Bitmap[A_Index] := R_3 + (R_1 - 30) * Sin(SectionAngle) - 16
      
      PointsA[A_Index] := Gdip_GetPointsSection(R_3, R_3, R_1 + Offset * 2 + 10, R_1 + Offset * 2, This.menu.Sections, Offset, A_Index)
      Points[A_Index] := Gdip_GetPointsSection(R_3, R_3, R_1, R_2, This.menu.Sections, Offset, A_Index)
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
    
    Loop {
      currentTime := A_TickCount
      
      needsRedraw := false
      Loop This.menu.Sections {
        if (isGifAnim.Has(A_Index) && isGifAnim[A_Index] && pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
          delay := gifFrameDelay.Has(A_Index) && gifFrameDelay[A_Index].Has(gifCurrentFrame[A_Index]) ? gifFrameDelay[A_Index][gifCurrentFrame[A_Index]] : 100
          if (currentTime - gifLastFrameTime[A_Index] >= delay) {
            gifCurrentFrame[A_Index] := Mod(gifCurrentFrame[A_Index] + 1, gifFrameCount[A_Index])
            gifLastFrameTime[A_Index] := currentTime
            needsRedraw := true
          }
        }
      }
      
      RM_KeyState := GetKeyState(This.menu.RM_Key, "P")
      if !WinExist("RM_Menu") {
        Exit
      }
      if (RM_KeyState == 1) {
        RM_KeyState_D := 1
      }
      if (RM_KeyState == 0 and RM_KeyState_D == 1) {
        Section_Mouse := RM_GetSection(This.menu.Sections, R_2, X_Center, Y_Center)
        if (Section_Mouse != 0) {
          break
        }
        RM_KeyState_D := 0
      }
      if (GetKeyState("LButton")) {
        Section_Mouse := RM_GetSection(This.menu.Sections, R_2, X_Center, Y_Center)
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
      
      Section_Mouse := RM_GetSection(This.menu.Sections, R_2, X_Center, Y_Center)
      
      if (Center_Distance > R_1) {
        break
      }
      if (Section_Mouse == 0) {
        ToolTip()
        SectName := ""
      }
      if (Section_Mouse > 0) {
        Counter++
        SectName_N := This.menu.Sect_Name.Has(Section_Mouse) ? This.menu.Sect_Name[Section_Mouse] : ""
        
        if ((X_Mouse_P != X_Mouse) or (Y_Mouse_P != Y_Mouse) or SectName_N != SectName or Counter > 500) {
          SectName := SectName_N
          CoordMode "Mouse", "Window"
          MouseGetPos &X_Mouse_P, &Y_Mouse_P
          if (Counter > 500 or SectName_N != SectName) {
            ToolTip(SectName)
            Counter := 0
          }
        }
      }
      if (Section_Mouse != Section_Mouse_Prev or A_Index == 1 or needsRedraw) {
        if (G) {
          Gdip_GraphicsClear(G)
        }
        hbm := CreateDIBSection(Width, Height)
        hdc := CreateCompatibleDC()
        obm := SelectObject(hdc, hbm)
        G := Gdip_GraphicsFromHDC(hdc)
        
        Gdip_SetSmoothingMode(G, 4)
        Gdip_FillEllipse(G, pBrushC, R_3 - R_1, R_3 - R_1, 2 * R_1, 2 * R_1)
        
        Loop This.menu.Sections {
          SectionAngle := 2 * 3.141592653589793 / This.menu.Sections * (A_Index - 1)
          SectName := This.menu.Sect_Name.Has(A_Index) ? This.menu.Sect_Name[A_Index] : ""
          if (A_Index == Section_Mouse) {
            Gdip_FillPolygon(G, pBrushA, Points[A_Index])
            Gdip_DrawLines(G, pPenA, Points[A_Index])
            Gdip_FillPolygon(G, pBrushA, PointsA[A_Index])
            Gdip_DrawLines(G, pPenA, PointsA[A_Index])
          } else {
            Gdip_FillPolygon(G, pBrush, Points[A_Index])
            Gdip_DrawLines(G, pPen, Points[A_Index])
          }
          SectImg := This.menu.Sect_Img.Has(A_Index) ? This.menu.Sect_Img[A_Index] : ""
          if (isGifAnim.Has(A_Index) && isGifAnim[A_Index] && pGifBitmap.Has(A_Index) && pGifBitmap[A_Index]) {
            DllCall("gdiplus\GdipImageSelectActiveFrame", "ptr", pGifBitmap[A_Index], "ptr", gifDimensionIDs[A_Index], "int", gifCurrentFrame[A_Index])
            gw := gifRealW.Has(A_Index) ? gifRealW[A_Index] : 32
            gh := gifRealH.Has(A_Index) ? gifRealH[A_Index] : 32
            Gdip_DrawImage(G, pGifBitmap[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], 32, 32, 0, 0, gw, gh)
          } else if (pBitmap.Has(A_Index) && pBitmap[A_Index]) {
            Gdip_DrawImage(G, pBitmap[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], 32, 32 * bHeight[A_Index] / bWidth[A_Index], 0, 0, bWidth[A_Index], bHeight[A_Index])
          }
          if (SectName != "") {
            if (SectImg == "") {
              Gdip_TextToGraphics(G, SectName, "vCenter x" (X_Bitmap[A_Index] - 40 + 16) " y" (Y_Bitmap[A_Index] - 40 + 16), "", "64", "64")
            }
          } else {
            Gdip_TextToGraphics(G, A_Index, "vCenter cFF888888 x" (X_Bitmap[A_Index] - 40 + 16) " y" (Y_Bitmap[A_Index] - 40 + 16), "", "64", "64")
          }
        }
        
        UpdateLayeredWindow(hwnd1, hdc, X_Gui, Y_Gui, Width, Height)
        if (hdc) {
          SelectObject(hdc, obm)
          DeleteObject(hbm)
          DeleteDC(hdc)
        }
        if (G) {
          Gdip_DeleteGraphics(G)
        }
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
    
    Loop This.menu.Sections {
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
    Gdip_Shutdown(This.pToken)
    This.pToken := 0
    MyGui.Destroy()
    Section_Mouse := RM_GetSection(This.menu.Sections, R_2, X_Center, Y_Center)
    
    finalName := ""
    if (Section_Mouse > 0 && This.menu.Sect_Name.Has(Section_Mouse)) {
      finalName := This.menu.Sect_Name[Section_Mouse]
    }
    
    return { Section: Section_Mouse, Name: finalName }
  }
  
  ExitFunc(*) {
    if (This.pToken) {
      Gdip_Shutdown(This.pToken)
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
  StartAngle := -SweepAngle / 2 + SectionAngle * (Section)
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
  StartAngle_2 := SweepAngle_2 / 2 + SectionAngle * (Section)
  Loop Loop_Sections {
    Angle := StartAngle_2 - (A_Index - 1) * SweepAngle_2 / (Loop_Sections - 1)
    X_Arc := Round(X_Center + R_2 * Cos(Angle))
    Y_Arc := Round(Y_Center + R_2 * Sin(Angle))
    Points .= "|" X_Arc "," Y_Arc
  }
  
  Points .= "|" X_Arc_Start "," Y_Arc_Start
  
  return Points
}

RM_GetSection(Sections, R_2, X_Center, Y_Center) {
  Section_Mouse := 0
  CoordMode "Mouse", "Window"
  MouseGetPos &X_Mouse, &Y_Mouse
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
    Section_Mouse := 1 + Round(Angle / 360 * Sections)
    if (Section_Mouse > Sections) {
      Section_Mouse := 1
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