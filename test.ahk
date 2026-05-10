; Created by ahk_user @ 2019
; Creates radial Mouse menu
; V2.00001
; Changes
; Add function accepts HBitmap or files
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Main\Util\Gdip_All.ahk
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=67803


; Example Code:
~mButton::
{
  G := Radial_Menu()
  G.SetSections(8)
  G.Add("Save","Images/analysis_meas_distance16.gif", 1)
  G.Add("Save2","Images/smt_flat_wall_mt.gif", 2)
  G.Add2("Save2special","Images/analysis_meas_distance16.gif", 2)
  G.SetKey("mbutton")
  G.SetKeySpecial("Ctrl")
  G.Add("Save3","Images/smt_flat_wall_mt.gif", 3)
  G.Add("Save4","Images/smt_flat_wall_mt.gif", 4)
  G.Add("Dimension","Images/dim_entity.gif", 5)
  G.Add2("Save5se","Images/fbcp_asm_image.gif", 5)
  G.Add("Save6","", 6)
  G.Add("","", 7)
  G.Add("Save8","Images/smt_flat_wall_mt.gif", 8)
  RM_result := G.Show()

  if (RM_result == "save"){
    MsgBox("You pressed save.")
  }
  else if (RM_result == "save2"){
    MsgBox("You pressed save2.")
  }
  else{
    MsgBox("The result is " RM_result)
  }
}


class Radial_Menu{
  Sections := 4
  Sect_Name := Map()
  Sect_Img := Map()
  Sect_Name2 := Map()
  Sect_Img2 := Map()
  RM_Key := "Capslock"
  RM_Key2 := ""
  
  __New(){
    This.Sections := 4
    This.RM_Key := "Capslock"
  }
  
  SetSections(Sections){
    This.Sections := Sections
  }
  SetKey(RM_Key){
    This.RM_Key := RM_Key
  }
  SetKeySpecial(RM_Key2){
    This.RM_Key2 := RM_Key2
  }
  
  Add(SectionName,SectionImg,ArcNr){
    if (This.Sections < ArcNr){
      This.Sections := ArcNr
    }
    This.Sect_Name[ArcNr] := SectionName
    This.Sect_Img[ArcNr] := SectionImg
  }
  Add2(SectionName2,SectionImg2,ArcNr){
    if (This.Sections < ArcNr){
      This.Sections := ArcNr
    }
    This.Sect_Name2[ArcNr] := SectionName2
    This.Sect_Img2[ArcNr] := SectionImg2
  }
  
  Show(){
    global pToken
    SectName := ""
    CoordMode "Mouse", "Window"
    MouseGetPos &X_Center, &Y_Center
    WinGetPos &X_Win, &Y_Win,,, "A"
    R_1 := 100
    R_2 := R_1*0.2
    Offset := 2
    R_3 := R_1+Offset*2+10
    
    X_Gui := X_Center - R_3 + X_Win
    Y_Gui := Y_Center - R_3 + Y_Win
    Height_Gui := R_3*2
    Width_Gui := R_3*2
    
    Width := R_3*2
    height := R_3*2
    
    if WinExist("RM_Menu"){
      Gui("1:Destroy")
    }
    
    ; Start gdi+
    pToken := Gdip_Startup()
    If !pToken{
      MsgBox("gdiplus error!", "Gdiplus failed to start. Please ensure you have gdiplus on your system", "48 T2")
      ExitApp()
    }
    OnExit(ExitFunc)
    
    ; Create a layered window (+E0x80000 : must be used for UpdateLayeredWindow to work!) that is always on top (+AlwaysOnTop), has no taskbar entry or caption
    MyGui := Gui("-Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs", "RM_Menu")
    
    ; Show the window
    MyGui.Show("NA x" X_Gui " y" Y_Gui " w" Width_Gui " h" Height_Gui)
    
    ; Get a handle to this window we have created in order to update it later
    hwnd1 := WinExist()
    
    MouseGetPos &X_Center, &Y_Center
    ColorBackGround := "FCFCFC"
    ColorLineBackGround := "C6DFFC"
    ColorSelected := "C6DFFC"
    ColorLineSelected := "F5E5D6"
    
    pBitmap := Map()
    bWidth := Map()
    bHeight := Map()
    pBitmap2 := Map()
    bWidth2 := Map()
    bHeight2 := Map()
    X_Bitmap := Map()
    Y_Bitmap := Map()
    Points := Map()
    PointsA := Map()
    
    Loop This.Sections { ;Setting Bitmap images of sections
      SectImg := This.Sect_Img.Has(A_Index) ? This.Sect_Img[A_Index] : ""
      if (SectImg != ""){
        if FileExist(SectImg){
          pBitmap[A_Index] := Gdip_CreateBitmapFromFile(SectImg)
        }
        else {
          pBitmap[A_Index] := 0
        }
      }
      else {
        pBitmap[A_Index] := 0
      }
      
      bWidth[A_Index] := pBitmap[A_Index] ? Gdip_GetImageWidth(pBitmap[A_Index]) : 16
      bHeight[A_Index] := pBitmap[A_Index] ? Gdip_GetImageHeight(pBitmap[A_Index]) : 16
      
      SectImg2 := This.Sect_Img2.Has(A_Index) ? This.Sect_Img2[A_Index] : ""
      if (SectImg2 != ""){
        if FileExist(SectImg2){
          pBitmap2[A_Index] := Gdip_CreateBitmapFromFile(SectImg2)
        }
        else {
          pBitmap2[A_Index] := 0
        }
      }
      else {
        pBitmap2[A_Index] := 0
      }
      bWidth2[A_Index] := pBitmap2[A_Index] ? Gdip_GetImageWidth(pBitmap2[A_Index]) : 16
      bHeight2[A_Index] := pBitmap2[A_Index] ? Gdip_GetImageHeight(pBitmap2[A_Index]) : 16
    }
    
    Counter := 0
    Loop This.Sections { ;Calculating Section Points
      SectionAngle := 2*3.141592653589793/This.Sections*(A_Index-1)
      
      X_Bitmap[A_Index] := R_3+(R_1-30)*cos(SectionAngle)-8
      Y_Bitmap[A_Index] := R_3+(R_1-30)*sin(SectionAngle)-8
      
      PointsA[A_Index] := Gdip_GetPointsSection(R_3,R_3,R_1+Offset*2+10,R_1+Offset*2,This.Sections,Offset,A_Index)
      Points[A_Index] := Gdip_GetPointsSection(R_3,R_3,R_1,R_2,This.Sections,Offset,A_Index)
    }
    
    ; Setting brushes and Pens
    pBrush := Gdip_BrushCreateSolid("0xFF" ColorBackGround)
    pBrushA := Gdip_BrushCreateSolid("0xFF" ColorSelected)
    pBrushC := Gdip_BrushCreateSolid("0X01" ColorBackGround)
    pPen := Gdip_CreatePen("0xFF" ColorLineBackGround, 1)
    pPenA := Gdip_CreatePen("0xD2" ColorLineSelected, 1)
    
    RM_KeyState_D := 0
    Section_Mouse_Prev := 0
    RM_KeyState2_Prev := 0
    G := 0
    X_Mouse_P := 0
    Y_Mouse_P := 0
    
    Loop {
      RM_KeyState := GetKeyState(This.RM_Key,"P")
      RM_KeyState2 := GetKeyState(This.RM_Key2,"P")
      if !WinExist("RM_Menu"){
        Exit
      }
      if (RM_KeyState == 1){
        RM_KeyState_D := 1
      }
      if (RM_KeyState == 0 and RM_KeyState_D == 1){
        Section_Mouse := RM_GetSection(This.Sections, R_2,X_Center,Y_Center)
        if (Section_Mouse != 0){
          break
        }
        RM_KeyState_D := 0
      }
      if (GetKeyState("LButton")){
        Section_Mouse := RM_GetSection(This.Sections, R_2,X_Center,Y_Center)
        if (Section_Mouse != 0){
          break
        }
        if (Section_Mouse == 0){
          SectName := ""
          break
        }
      }
      if GetKeyState("Escape"){
        Section_Mouse := 0 
        SectName := ""
        break
      }
      
      MouseGetPos &X_Mouse, &Y_Mouse
      X_Rel := X_Mouse - X_Center
      Y_Rel := Y_Mouse - Y_Center
      Center_Distance := Sqrt(X_Rel*X_Rel+Y_Rel*Y_Rel)
      
      Section_Mouse := RM_GetSection(This.Sections, R_2,X_Center,Y_Center)
      
      if (Center_Distance > R_1){
        break
      }
      if (Section_Mouse == 0){
        ToolTip()
        SectName := ""
      }
      if (Section_Mouse > 0){
        Counter++
        SectName_N := This.Sect_Name.Has(Section_Mouse) ? This.Sect_Name[Section_Mouse] : ""
        SectName2 := This.Sect_Name2.Has(Section_Mouse) ? This.Sect_Name2[Section_Mouse] : ""
        if (GetKeyState(This.RM_Key2,"P") and SectName2 != ""){
          SectName_N := SectName2
        }
        
        if ((X_Mouse_P != X_Mouse) or (Y_Mouse_P != Y_Mouse) or SectName_N != SectName or Counter > 500) {
          SectName := SectName_N
          CoordMode "Mouse", "Window"
          MouseGetPos &X_Mouse_P, &Y_Mouse_P
          if (Counter > 500 or SectName_N != SectName){
            ToolTip(SectName)
            Counter := 0
          }
        }
      }
      if (Section_Mouse != Section_Mouse_Prev or A_Index == 1 or RM_KeyState2_Prev != RM_KeyState2){ ; Update GDIP   
        
        if (G){
          Gdip_GraphicsClear(G)
        }
        hbm := CreateDIBSection(Width, Height) ; Create a gdi bitmap with width and height of what we are going to draw into it. This is the entire drawing area for everything
        hdc := CreateCompatibleDC() ; Get a device context compatible with the screen
        obm := SelectObject(hdc, hbm) ; Select the bitmap into the device context
        G := Gdip_GraphicsFromHDC(hdc)  ; Get a pointer to the graphics of the bitmap, for use with drawing functions
        
        ; Set the smoothing mode to antialias = 4 to make shapes appear smother (only used for vector drawing and filling)
        Gdip_SetSmoothingMode(G, 4)
        Gdip_FillEllipse(G, pBrushC, R_3-R_1, R_3-R_1, 2*R_1, 2*R_1)
        
        Loop This.Sections {
          SectionAngle := 2*3.141592653589793/This.Sections*(A_Index-1)
          SectName := This.Sect_Name.Has(A_Index) ? This.Sect_Name[A_Index] : ""
          if (SectName == ""){
            continue
          }
          If (A_Index == Section_Mouse){
            Gdip_FillPolygon(G, pBrushA, Points[A_Index])
            Gdip_DrawLines(G, pPenA, Points[A_Index])
            Gdip_FillPolygon(G, pBrushA, PointsA[A_Index])
            Gdip_DrawLines(G, pPenA, PointsA[A_Index])
          } 
          else {
            Gdip_FillPolygon(G, pBrush, Points[A_Index])
            Gdip_DrawLines(G, pPen, Points[A_Index])
          }
          SectName2 := This.Sect_Name2.Has(A_Index) ? This.Sect_Name2[A_Index] : ""
          SectImg := This.Sect_Img.Has(A_Index) ? This.Sect_Img[A_Index] : ""
          if (GetKeyState(This.RM_Key2,"P") and SectName2 != ""){
            if (pBitmap2[A_Index]){
              Gdip_DrawImage(G, pBitmap2[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], 16, 16*bHeight2[A_Index]/bWidth2[A_Index], 0, 0, bWidth2[A_Index], bHeight2[A_Index])
            }
          }
          else {
            if (pBitmap[A_Index]){
              Gdip_DrawImage(G, pBitmap[A_Index], X_Bitmap[A_Index], Y_Bitmap[A_Index], 16, 16*bHeight[A_Index]/bWidth[A_Index], 0, 0, bWidth[A_Index], bHeight[A_Index])
            }
          }
          if(SectImg==""){
            Gdip_TextToGraphics(G, SectName, "vCenter x" (X_Bitmap[A_Index] -20+8) " y" (Y_Bitmap[A_Index] -20+8), "", "40", "40")
          }
        }
        
        ; Update the specified window we have created (hwnd1) with a handle to our bitmap (hdc), specifying the x,y,w,h we want it positioned on our screen
        ; So this will position our gui at (0,0) with the Width and Height specified earlier
        UpdateLayeredWindow(hwnd1, hdc, X_Gui, Y_Gui, Width, Height)
        if (hdc){
          SelectObject(hdc, obm) ; Select the object back into the hdc
          DeleteObject(hbm) ; Now the bitmap may be deleted
          DeleteDC(hdc) ; Also the device context related to the bitmap may be deleted
        }
        if (G){
          Gdip_DeleteGraphics(G) ; The graphics may now be deleted
        }
      }
      RM_KeyState2_Prev := RM_KeyState2
      Section_Mouse_Prev := Section_Mouse
    }
    
    ToolTip()
    
    if (hdc){
      SelectObject(hdc, obm) ; Select the object back into the hdc
      DeleteObject(hbm) ; Now the bitmap may be deleted
      DeleteDC(hdc) ; Also the device context related to the bitmap may be deleted
    }
    if (G){
      Gdip_DeleteGraphics(G) ; The graphics may now be deleted
    }
    
    Loop This.Sections {
      if (pBitmap[A_Index]){
        Gdip_DisposeImage(pBitmap[A_Index])
      }
      if (pBitmap2[A_Index]){
        Gdip_DisposeImage(pBitmap2[A_Index])
      }
    }
    
    Gdip_DeleteBrush(pBrushC)
    Gdip_DeleteBrush(pBrush)
    Gdip_DeleteBrush(pBrushA)
    Gdip_DeletePen(pPen)
    Gdip_DeletePen(pPenA)
    Gdip_Shutdown(pToken)
    pToken := 0
    MyGui.Destroy()
    Section_Mouse := RM_GetSection(This.Sections, R_2,X_Center,Y_Center)
    if (Section_Mouse == 0){
      SectName := ""
    }
    Return SectName
  }
}


Gdip_GetPointsSection(X_Center,Y_Center,R_1,R_2,Sections,Offset,Section := 1){
  Section := Section -1
  SectionAngle := 2*3.141592653589793/Sections
  R_2_Min := 4*Offset/Sin(SectionAngle)
  R_2 := R_2 > R_2_Min ? R_2 : R_2_Min
  SweepAngle := ACos((R_1*cos(SectionAngle/2)+Offset*sin(SectionAngle/2))/R_1)*2
  SweepAngle_2 := ACos((R_2*cos(SectionAngle/2)+Offset*sin(SectionAngle/2))/R_2)*2  
  
  Loop_Sections := round(R_1*SweepAngle)
  StartAngle := -SweepAngle/2 + SectionAngle*(Section)
  Points := ""
  Loop Loop_Sections {
    Angle := StartAngle + (A_Index-1)*SweepAngle/(Loop_Sections-1)
    X_Arc := round(X_Center + R_1*cos(Angle))
    Y_Arc := round(Y_Center + R_1*sin(Angle))
    if (A_Index == 1){
      Points := X_Arc "," Y_Arc
      X_Arc_Start := X_Arc
      Y_Arc_Start := Y_Arc
      continue
    }
    Points .= "|" X_Arc "," Y_Arc
  }
  
  Loop_Sections := round(R_2*SweepAngle_2)
  StartAngle_2 := SweepAngle_2/2 + SectionAngle*(Section)
  Loop Loop_Sections {
    Angle := StartAngle_2 - (A_Index-1)*SweepAngle_2/(Loop_Sections-1)
    X_Arc := round(X_Center + R_2*cos(Angle))
    Y_Arc := round(Y_Center + R_2*sin(Angle))
    Points .= "|" X_Arc "," Y_Arc
  }
  
  Points .= "|" X_Arc_Start "," Y_Arc_Start
  
  return Points
}

;#######################################################################

RM_GetSection(Sections, R_2,X_Center,Y_Center){
  Section_Mouse := 0
  CoordMode "Mouse", "Window"
  MouseGetPos &X_Mouse, &Y_Mouse
  X_Rel := X_Mouse - X_Center
  Y_Rel := Y_Mouse - Y_Center 
  Distance_Center := Sqrt(X_Rel*X_Rel+Y_Rel*Y_Rel)
  if (X_Rel == 0){ ; (correction to prevent X to be 0)
     X_Rel := 0.01
  }
  if (Y_Rel == 0){ ; (correction to prevent Y to be 0)
     Y_Rel := 0.01
  }
  if (Distance_Center < R_2){
    Section_Mouse := 0
    return Section_Mouse
  }
  else if (Distance_Center > R_2){
    a := X_Rel == 0 ? (Y_Rel == 0 ? 0 : Y_Rel > 0 ? 90 : 270) : atan(Y_Rel/X_Rel)*57.2957795130823209 ; 180/pi
    Angle := X_Rel < 0 ? 180 + a : a < 0 ? 360 + a : a
    Section_Mouse := 1+round(Angle/360*Sections)
    if (Section_Mouse > Sections){
      Section_Mouse := 1
    }
  }
  return Section_Mouse
}

RM_BuildRM(RM_Name){
  RM_File_Settings := A_ScriptDir "\RM_Settings.ini"
  Sections := IniRead(RM_File_Settings, RM_Name, "Sections", 8)
  G := Radial_Menu()
  Loop Sections {
    RM_B_Name := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_Name", "Name")
    if (RM_B_Name == "Default"){
      continue
    }
    RM_B_img := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_img", " ")
    RM_B_Script := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_Script", " ")
    RM_B_Script := StrReplace(RM_B_Script, "<br>", "`n")
    
    G.Add(RM_B_Name,RM_B_img,A_Index)
  }
  G.SetSections(Sections)
  Result := G.Show()
  Loop Sections {
    if (Result == RM_B_Name and RM_B_Script != ""){
      Script := RM_B_Script
      Function := RegExMatch(Script,"([^\(]*)\((.*)\)","$1")
      Var := RegExMatch(Script,"([^\(]*)\((.*)\)","$1")
      %Function%(Var)
    }
  }
  return Result
}

RM_MenuSettings(RM_Name){
  RM_File_Settings := A_ScriptDir "\RM_Settings.ini"
  Sections := IniRead(RM_File_Settings, RM_Name, "Sections", 8)
  G := Radial_Menu()
  Loop Sections {
    RM_B_Name := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_Name", "Name")
    if (RM_B_Name == "Default"){
      continue
    }
    RM_B_img := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_img", " ")
    RM_B_Script := IniRead(RM_File_Settings, RM_Name, "RM_B" A_Index "_Script", " ")
    RM_B_Script := StrReplace(RM_B_Script, "<br>", "`n")
    G.Add(RM_B_Name, RM_B_img , A_Index)
  }
  G.SetSections(Sections)
  Result := G.Show()
  Loop Sections {
    if (RM_B_Name and RM_B_Script){
      if (Result == RM_B_Name){
        return RM_B_Script 
      }
    }
  }
  return Result
}

ExitFunc(*){
  global pToken
  ; gdi+ may now be shutdown on exiting the program
  if (pToken){
    Gdip_Shutdown(pToken)
  }
  return
}