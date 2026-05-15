#Requires AutoHotkey v2.0

class RM_GifPlayer {
  file := ""
  hwnd := 0
  pBitmap := 0
  width := 0
  height := 0
  frameCount := 0
  frameCurrent := -1
  frameDelay := []
  dimensionIDs := 0
  isPlaying := false
  _fn := 0
  picCtrl := 0
  infoCtrl := 0
  pToken := 0
  cycle := true
  
  __New(file, picCtrl, infoCtrl, pToken, cycle := true) {
    This.file := file
    This.picCtrl := picCtrl
    This.infoCtrl := infoCtrl
    This.pToken := pToken
    This.cycle := cycle
    
    This.pBitmap := Gdip_CreateBitmapFromFile(file)
    if (!This.pBitmap) {
      return
    }
    
    w := 0
    h := 0
    DllCall("gdiplus\GdipGetImageWidth", "ptr", This.pBitmap, "uint*", &w)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", This.pBitmap, "uint*", &h)
    This.width := w
    This.height := h
    
    fdCount := 0
    DllCall("gdiplus\GdipImageGetFrameDimensionsCount", "ptr", This.pBitmap, "uint*", &fdCount)
    This.dimensionIDs := Buffer(16 * fdCount)
    DllCall("gdiplus\GdipImageGetFrameDimensionsList", "ptr", This.pBitmap, "ptr", This.dimensionIDs, "uint", fdCount)
    fc := 0
    DllCall("gdiplus\GdipImageGetFrameCount", "ptr", This.pBitmap, "ptr", This.dimensionIDs, "uint*", &fc)
    This.frameCount := fc
    This.frameCurrent := -1
    This.frameDelay := This._GetFrameDelay(This.pBitmap, This.frameCount)
    This.valid := true
    
    if (This.infoCtrl) {
      This.infoCtrl.Value := w "x" h " | " fc " frames"
    }
  }
  
  _GetFrameDelay(pImage, targetCount := 0) {
    static PropertyTagFrameDelay := 0x5100
    itemSize := 0
    DllCall("gdiplus\GdipGetPropertyItemSize", "ptr", pImage, "uint", PropertyTagFrameDelay, "uint*", &itemSize)
    
    if (itemSize < 16) {
      outArray := []
      Loop (targetCount > 0 ? targetCount : 1) {
        outArray.Push(100)
      }
      return outArray
    }
    
    item := Buffer(itemSize)
    DllCall("gdiplus\GdipGetPropertyItem", "ptr", pImage, "uint", PropertyTagFrameDelay, "uint", itemSize, "ptr", item)
    propLen := NumGet(item, 4, "UInt")
    propValPtr := NumGet(item, 8 + A_PtrSize, "Ptr")
    
    outArray := []
    rawCount := propLen // 4
    Loop (rawCount) {
      n := NumGet(propValPtr + (A_Index - 1) * 4, "UInt") * 10
      outArray.Push(n ? n : 100)
    }
    
    if (targetCount > 0 && outArray.Length < targetCount) {
      lastDelay := outArray.Length ? outArray[outArray.Length - 1] : 100
      Loop (targetCount - outArray.Length) {
        outArray.Push(lastDelay)
      }
    }
    
    return outArray.Length ? outArray : [100]
  }
  
  Play() {
    if (!This.valid || This.isPlaying)
      return
    This.isPlaying := true
    fn := ObjBindMethod(This, "_PlayNext")
    This._fn := fn
    SetTimer(fn, -1)
  }
  
  Pause() {
    This.isPlaying := false
    fn := This._fn
    if (fn) {
      SetTimer(fn, 0)
    }
  }
  
  _PlayNext() {
    This.frameCurrent := Mod(This.frameCurrent + 1, This.frameCount)
    
    DllCall("gdiplus\GdipImageSelectActiveFrame", "ptr", This.pBitmap, "ptr", This.dimensionIDs, "int", This.frameCurrent)
    
    hbm := Gdip_CreateHBITMAPFromBitmap(This.pBitmap)
    if (hbm && This.picCtrl) {
      This.picCtrl.Value := "HBITMAP:*" . hbm
      DeleteObject(hbm)
    }
    
    if (This.infoCtrl) {
      delay := This.frameDelay.Has(This.frameCurrent) ? This.frameDelay[This.frameCurrent] : 100
      This.infoCtrl.Value := This.width "x" This.height " | Frame: " (This.frameCurrent + 1) "/" This.frameCount " | " delay "ms"
    }
    
    maxFrame := This.cycle ? 0xFFFFFFFF : This.frameCount - 1
    if (This.isPlaying && This.frameCurrent < maxFrame && This._fn) {
      delay := This.frameDelay.Has(This.frameCurrent) ? This.frameDelay[This.frameCurrent] : 100
      SetTimer(This._fn, -1 * delay)
    } else if (This.cycle && This._fn) {
      delay := This.frameDelay.Has(0) ? This.frameDelay[0] : 100
      SetTimer(This._fn, -1 * delay)
    }
  }
  
  __Delete() {
    This.Pause()
    if (This.pBitmap) {
      Gdip_DisposeImage(This.pBitmap)
    }
  }
}