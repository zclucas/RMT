#Requires AutoHotkey v2.0
#Include UIMacroSchema.ahk

; 复制自定义面板时，把动作、参数与嵌套指令指向本次实际导出的宏。
CopySelectedUIMacroPanel(sourceDir, sourceFold, destDir, destFold, macroIDs, serials) {
    if (!IsObject(sourceFold) || !RegExMatch(sourceFold.ID, "^UI(?:_\d+)?\.[\w-]+$")
        || !RegExMatch(destFold.ID, "^UI(?:_\d+)?\.[\w-]+$"))
        return
    source := sourceDir "\UIPanelCustom_" sourceFold.ID ".json"
    if (!FileExist(source))
        return
    panel := UIMacroSchema.Parse(FileRead(source, "UTF-8"))
    if (!IsObject(panel))
        throw Error(GetLang("无效的打包文件格式") " " source)
    for ctrl in panel.controls {
        for prop in ["action", "binding"] {
            if (!ctrl.HasOwnProp(prop))
                continue
            reference := ctrl.%prop%
            if (!IsObject(reference))
                continue
            id := macroIDs.Get(reference.macroId, "")
            if (id == "") {
                ctrl.%prop% := ""
                continue
            }
            reference.macroId := id
            if (reference.HasOwnProp("serial"))
                reference.serial := serials.Get(reference.serial, reference.serial)
            if (reference.HasOwnProp("hops") && reference.hops is Array) {
                for hop in reference.hops
                    hop.serial := serials.Get(hop.serial, hop.serial)
            }
        }
    }
    dest := destDir "\UIPanelCustom_" destFold.ID ".json"
    if (!UIMacroPanelStore.SaveFile(dest, UIMacroSchema.Serialize(panel)))
        throw Error(GetLang("写入失败：") dest)
}
