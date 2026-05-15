#Requires AutoHotkey v2.0
#SingleInstance Force
#Include RadialMenuRenderer.ahk
#Include RM_GifPlayer.ahk

~mButton::
^mButton::
{
  G := Radial_Menu()
  G.SetSections(8)
  G.SetKey("mbutton")
  
  G.Add("Save", "test.gif", 1, (*) => MsgBox("You pressed save."))
  G.Add("Save2", "Images/smt_flat_wall_mt.gif", 2, (*) => MsgBox("You pressed save2."))
  G.Add("Save3", "Images/smt_flat_wall_mt.gif", 3, (*) => MsgBox("You pressed save3."))
  G.Add("Save4", "Images/smt_flat_wall_mt.gif", 4, (*) => MsgBox("You pressed save4."))
  G.Add("Dimension", "Images/dim_entity.gif", 5, (*) => MsgBox("You pressed Dimension."))
  G.Add("Save6", "Images/smt_flat_wall_mt.gif", 6, (*) => MsgBox("You pressed save6."))
  G.Add("Button7", "", 7, (*) => MsgBox("You pressed Button7."))
  G.Add("Save8", "Images/smt_flat_wall_mt.gif", 8, (*) => MsgBox("You pressed save8."))
  
  G.Show()
}

class Radial_Menu {
  Sections := 8
  Sect_Name := Map()
  Sect_Img := Map()
  Sect_Callback := Map()
  RM_Key := "Capslock"
  
  __New() {
    This.Sections := 8
    This.RM_Key := "Capslock"
  }
  
  SetSections(Sections) {
    This.Sections := Sections
  }
  
  SetKey(RM_Key) {
    This.RM_Key := RM_Key
  }
  
  Add(SectionName, SectionImg, ArcNr, Callback := 0) {
    if (This.Sections < ArcNr) {
      This.Sections := ArcNr
    }
    This.Sect_Name[ArcNr] := SectionName
    This.Sect_Img[ArcNr] := SectionImg
    if (IsObject(Callback)) {
      This.Sect_Callback[ArcNr] := Callback
    }
  }
  
  Show() {
    renderer := RadialMenuRenderer(This)
    result := renderer.Show()
    
    if (result.Section != 0 && This.Sect_Callback.Has(result.Section)) {
      try {
        This.Sect_Callback[result.Section].Call(result.Section, result.Name)
      }
    }
    
    return result.Name
  }
}