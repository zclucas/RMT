#Requires AutoHotkey v2.0
#Include "XAML_Generator.ahk"

global AXML_METADATA

; ==============================================================================
; AXML State Manager (Reactive Proxy)
; ==============================================================================
class AXML_State {
    _data := Map()
    _bindings := Map()
    _ui := ""

    __New(initialData := {}) {
        this.DefineProp("_data", {Value: Map()})
        this.DefineProp("_bindings", {Value: Map()})
        this.DefineProp("_ui", {Value: ""})
        
        for k, v in initialData.OwnProps()
            this._data[k] := v
    }

    __Get(name, params) {
        if (name == "_data" || name == "_bindings" || name == "_ui" || name == "_computed" || name == "_depMap")
            return ""
        if this.HasOwnProp("_data") && this._data.Has(name)
            return this._data[name]
        return ""
    }

    Has(name) {
        return this.HasOwnProp("_data") && this._data.Has(name)
    }
    
    __Item[name] {
        get => this.%name%
        set => this.%name% := value
    }

    __Set(name, params, value) {
        if (name == "_data" || name == "_bindings" || name == "_ui" || name == "_computed" || name == "_depMap")
            return value
            
        if (this.HasOwnProp("_data") && this._data.Has(name) && this._data[name] == value)
            return value
            
        if (this.HasOwnProp("_data"))
            this._data[name] := value
            
        if (this.HasOwnProp("_ui") && this._ui && this.HasOwnProp("_bindings") && this._bindings.Has(name)) {
            for bindObj in this._bindings[name] {
                try {
                    this._ui.Update(bindObj.ControlName, bindObj.PropertyName, String(value))
                }
            }
        }
        
        ; Trigger dependent computed properties
        if (this.HasOwnProp("_depMap") && this._depMap.Has(name)) {
            for compName in this._depMap[name] {
                compObj := this._computed[compName]
                newVal := compObj.Fn.Call(this)
                if (this._data.Has(compName) && this._data[compName] == newVal)
                    continue
                this.%compName% := newVal
            }
        }
        
        return value
    }

    Batch(updatesObj) {
        pendingUIUpdates := []
        
        for k, v in updatesObj.OwnProps() {
            if (this.HasOwnProp("_data") && this._data.Has(k) && this._data[k] == v)
                continue
                
            if (this.HasOwnProp("_data"))
                this._data[k] := v
                
            if (this.HasOwnProp("_ui") && this._ui && this.HasOwnProp("_bindings") && this._bindings.Has(k)) {
                for bindObj in this._bindings[k] {
                    pendingUIUpdates.Push({ ControlName: bindObj.ControlName, PropertyName: bindObj.PropertyName, Value: String(v) })
                }
            }
            
            if (this.HasOwnProp("_depMap") && this._depMap.Has(k)) {
                for compName in this._depMap[k] {
                    compObj := this._computed[compName]
                    newVal := compObj.Fn.Call(this)
                    if (this._data.Has(compName) && this._data[compName] == newVal)
                        continue
                    this._data[compName] := newVal
                    
                    if (this.HasOwnProp("_ui") && this._ui && this.HasOwnProp("_bindings") && this._bindings.Has(compName)) {
                        for bindObj in this._bindings[compName] {
                            pendingUIUpdates.Push({ ControlName: bindObj.ControlName, PropertyName: bindObj.PropertyName, Value: String(newVal) })
                        }
                    }
                }
            }
        }
        
        if (pendingUIUpdates.Length > 0 && this.HasOwnProp("_ui") && this._ui && this._ui.HasMethod("BatchUpdate")) {
            this._ui.BatchUpdate(pendingUIUpdates)
        }
    }

    AddComputed(name, deps, computeFn) {
        if !this.HasOwnProp("_computed") {
            this.DefineProp("_computed", {Value: Map()})
            this.DefineProp("_depMap", {Value: Map()})
        }
        this._computed[name] := { Deps: deps, Fn: computeFn }
        
        for d in deps {
            if !this._depMap.Has(d)
                this._depMap[d] := []
            this._depMap[d].Push(name)
        }
        
        ; Initial computation
        this._data[name] := computeFn(this)
    }

    Bind(stateProp, controlName, uiProp) {
        if !this._bindings.Has(stateProp)
            this._bindings[stateProp] := []
        this._bindings[stateProp].Push({ControlName: controlName, PropertyName: uiProp})
    }
    
    SetUI(uiInstance) {
        this._ui := uiInstance
    }
}

; ==============================================================================
; AXML Parser and Binder
; ==============================================================================
class AXML {
    static ParsedData := []
    
    static GetBasename(path) {
        SplitPath(path, &name)
        return name
    }

    static LoadStringResource(dllPath, resourceName, resourceType := 10) {
        hModule := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
        if (!hModule)
            return ""
        hRes := DllCall("FindResource", "Ptr", hModule, "Str", resourceName, "Ptr", resourceType, "Ptr")
        if (!hRes) {
            DllCall("FreeLibrary", "Ptr", hModule)
            return ""
        }
        hGlob := DllCall("LoadResource", "Ptr", hModule, "Ptr", hRes, "Ptr")
        if (!hGlob) {
            DllCall("FreeLibrary", "Ptr", hModule)
            return ""
        }
        pData := DllCall("LockResource", "Ptr", hGlob, "Ptr")
        size := DllCall("SizeofResource", "Ptr", hModule, "Ptr", hRes, "UInt")
        if (!pData || size == 0) {
            DllCall("FreeLibrary", "Ptr", hModule)
            return ""
        }
        str := StrGet(pData, size, "UTF-8")
        DllCall("FreeLibrary", "Ptr", hModule)
        return str
    }

    static SerializeParsedData() {
        out := ""
        for item in AXML.ParsedData {
            out .= "---AXML-FILE---`n"
            out .= "Source: " item.Source "`n"
            out .= "---BINDINGS---`n"
            for b in item.Bindings {
                out .= b.ControlName "|" b.PropName "|" b.StateKey "`n"
            }
            out .= "---EVENTS---`n"
            for e in item.Events {
                out .= e.ControlName "|" e.EventName "|" e.FuncName "`n"
            }
        }
        return out
    }

    static DeserializeParsedData(str) {
        parsed := []
        lines := StrSplit(str, "`n", "`r")
        currentItem := ""
        currentSection := ""
        
        for line in lines {
            if (line == "")
                continue
            if (line == "---AXML-FILE---") {
                if (currentItem != "")
                    parsed.Push(currentItem)
                currentItem := { Source: "", Bindings: [], Events: [] }
                currentSection := "FILE"
                continue
            }
            if (line == "---BINDINGS---") {
                currentSection := "BINDINGS"
                continue
            }
            if (line == "---EVENTS---") {
                currentSection := "EVENTS"
                continue
            }
            
            if (currentSection == "FILE") {
                if RegExMatch(line, "^Source:\s*(.*)$", &m)
                    currentItem.Source := m[1]
            } else if (currentSection == "BINDINGS") {
                parts := StrSplit(line, "|")
                if (parts.Length >= 3)
                    currentItem.Bindings.Push({ ControlName: parts[1], PropName: parts[2], StateKey: parts[3] })
            } else if (currentSection == "EVENTS") {
                parts := StrSplit(line, "|")
                if (parts.Length >= 3)
                    currentItem.Events.Push({ ControlName: parts[1], EventName: parts[2], FuncName: parts[3] })
            }
        }
        if (currentItem != "")
            parsed.Push(currentItem)
        return parsed
    }

    static ParseFile(filePath, generatorParent, stateObj := "") {
        if (A_IsCompiled) {
            if (IsSet(AXML_METADATA) && AXML_METADATA != "") {
                parsed := AXML.DeserializeParsedData(AXML_METADATA)
                for item in parsed {
                    if (AXML.GetBasename(item.Source) == AXML.GetBasename(filePath)) {
                        return { Bindings: item.Bindings, Events: item.Events }
                    }
                }
            }
            
            dllName := ""
            if (generatorParent && generatorParent.HasMethod("_FindApp")) {
                app := generatorParent._FindApp()
                if (app && app.HasMethod("GetBundleDllName")) {
                    dllName := app.GetBundleDllName()
                }
            }
            if (dllName == "") {
                if (IsSet(CUSTOM_DLL_BUNDLE_NAME) && CUSTOM_DLL_BUNDLE_NAME != "")
                    dllName := CUSTOM_DLL_BUNDLE_NAME
                else {
                    SplitPath(A_ScriptName, , , , &nameNoExt)
                    dllName := nameNoExt "_bundled.dll"
                }
            }
            
            dllPath := FileExist(A_ScriptDir "\" dllName) ? (A_ScriptDir "\" dllName) : dllName
            
            axmlData := AXML.LoadStringResource(dllPath, "app_payload.axml", 10)
            if (axmlData != "") {
                parsed := AXML.DeserializeParsedData(axmlData)
                for item in parsed {
                    if (AXML.GetBasename(item.Source) == AXML.GetBasename(filePath)) {
                        return { Bindings: item.Bindings, Events: item.Events }
                    }
                }
            }
            return { Bindings: [], Events: [] }
        }

        content := FileRead(filePath, "UTF-8")
        SplitPath(filePath, &outFileName)
        return this.ParseString(content, generatorParent, stateObj, outFileName)
    }

    static ParseString(content, generatorParent, stateObj := "", sourceFile := "Inline AXML") {
        lines := StrSplit(content, "`n", "`r")
        astResult := this.BuildAST(lines, sourceFile)
        
        if (IsSet(XAML_AXML_DEBUG_MODE) && XAML_AXML_DEBUG_MODE) {
            try {
                dumpStr := "AST Nodes:`n" this.DumpNode(astResult.Nodes) "`n`nTemplates:`n" this.DumpNode(astResult.Templates)
                FileDelete(A_Temp "\AXML_AST_Debug.txt")
                FileAppend(dumpStr, A_Temp "\AXML_AST_Debug.txt")
                Run("notepad.exe " A_Temp "\AXML_AST_Debug.txt")
            }
        }
        
        bindings := []
        events := []
        this.RenderAST(astResult.Nodes, astResult.Templates, generatorParent, stateObj, bindings, events, sourceFile)
        
        if (!A_IsCompiled) {
            AXML.ParsedData.Push({ Source: sourceFile, Bindings: bindings, Events: events })
        }
        
        return { Bindings: bindings, Events: events }
    }
    
    static BindAll(ui, axmlResult, stateObj := "") {
        if (stateObj && stateObj.HasMethod("SetUI")) {
            stateObj.SetUI(ui)
        }
        
        for b in axmlResult.Bindings {
            if (stateObj && stateObj.HasMethod("Bind")) {
                stateObj.Bind(b.StateKey, b.ControlName, b.PropName)
            }
        }
        
        for e in axmlResult.Events {
            fn := ""
            if (SubStr(e.FuncName, 1, 2) == "=>") {
                inlineCode := Trim(SubStr(e.FuncName, 3))
                fn := AXML.CreateClosure(inlineCode)
            } else {
                try {
                    fn := %e.FuncName%
                } catch {
                    
                 }
            }
            
            if (fn != "" && (Type(fn) == "Func" || Type(fn) == "Closure" || Type(fn) == "BoundFunc")) {
                ui.OnEvent(e.ControlName, e.EventName, fn)
            } else {
                OutputDebug("[AXML WARNING] Markup requests " e.EventName " handler '" e.FuncName "' for '" e.ControlName "' but it is missing or invalid in AHK. Skipping.`n")
            }
        }
    }

    static CreateClosure(code) {
        return (state, ctrl, event) => AXML.Execute(code, state, ctrl, event)
    }

    static Execute(code, state, ctrl, event) {
        if RegExMatch(code, "^XDialog\.Show\(\{\s*(.*?)\s*\}\)$", &match) {
            propsStr := match[1]
            obj := {}
            pos := 1
            while RegExMatch(propsStr, '([a-zA-Z0-9_]+)\s*:\s*"([^"]*)"', &p, pos) {
                obj.%p[1]% := p[2]
                pos := p.Pos(0) + p.Len(0)
            }
            try {
                % "XDialog" %.Show(obj)
            } catch {
                MsgBox("XDialog class not found. Make sure to #Include XAML_Dialog.ahk")
            }
            return
        }
        if RegExMatch(code, '^MsgBox\("(.*?)"\)$', &match) {
            MsgBox(match[1])
            return
        }
        OutputDebug(" execution failed/unsupported for: " code "`n")
    }
    
    ; --------------------------------------------------------------------------
    ; Internal Helpers
    ; --------------------------------------------------------------------------
    
    static DumpNode(node, indent := 0) {
        if (Type(node) == "Array") {
            out := ""
            for child in node
                out .= this.DumpNode(child, indent)
            return out
        }
        if (Type(node) == "Map") {
            out := ""
            for k, v in node
                out .= this.DumpNode(v, indent)
            return out
        }
        
        pad := ""
        Loop indent
            pad .= "  "
            
        out := pad "[" ((node.HasProp("IsLoop") && node.IsLoop) ? "@For " node.LoopStart ".." node.LoopEnd " as " node.LoopVar : node.Type) "]"
        if (node.HasProp("Name") && node.Name != "")
            out .= " Name: " node.Name
        if (node.HasProp("SourceLine"))
            out .= " Line: " node.SourceLine
        out .= "`n"
        
        for k, v in node.Properties
            out .= pad "  - Prop: " k " = " v "`n"
            
        if (node.HasProp("Events") && node.Events) {
            for k, v in node.Events
                out .= pad "  - Event: " k " = " v "`n"
        }
            
        for child in node.Children
            out .= this.DumpNode(child, indent + 1)
            
        return out
    }
    
    static BuildAST(lines, sourceFile := "Inline AXML") {
        rootNode := { Children: [] }
        stack := [{ Indent: -1, Node: rootNode }]
        
        for index, line in lines {
            if (Trim(line) == "" || SubStr(Trim(line), 1, 1) == "#" || SubStr(Trim(line), 1, 1) == ";" || SubStr(Trim(line), 1, 2) == "//" || SubStr(Trim(line), 1, 2) == "/*")
                continue
            
            indent := 0
            while (SubStr(line, indent + 1, 1) == " " || SubStr(line, indent + 1, 1) == "`t")
                indent++
            
            cleanLine := Trim(line)
            
            ; Determine if it's a Loop definition: @For [start]..[end] as [var]:
            if RegExMatch(cleanLine, "^@For\s+([0-9]+)\.\.([0-9]+)\s+as\s+([a-zA-Z0-9_]+):$", &match) {
                newNode := { IsTemplate: false, IsLoop: true, LoopStart: Integer(match[1]), LoopEnd: Integer(match[2]), LoopVar: match[3], Type: "@For", Name: "", Properties: Map(), Events: Map(), Children: [], SourceLine: index }
                
                while (stack.Length > 0 && stack[stack.Length].Indent >= indent)
                    stack.Pop()
                
                parent := stack[stack.Length].Node
                parent.Children.Push(newNode)
                
                stack.Push({ Indent: indent, Node: newNode })
                continue
            }
            
            ; Determine if it's a Node definition: [@Template] Type (Name):
            else if RegExMatch(cleanLine, "^(@Template\s+)?([a-zA-Z0-9_\.]+)(?:\s*\(([^)]+)\))?:$", &match) {
                isTemplate := (Trim(match[1]) == "@Template")
                typeName := match[2]
                nodeName := match[3]
                
                newNode := { IsTemplate: isTemplate, IsLoop: false, Type: typeName, Name: nodeName, Properties: Map(), Events: Map(), Children: [], SourceLine: index }
                
                while (stack.Length > 0 && stack[stack.Length].Indent >= indent)
                    stack.Pop()
                
                parent := stack[stack.Length].Node
                parent.Children.Push(newNode)
                
                stack.Push({ Indent: indent, Node: newNode })
            } 
            ; Or a property: PropName: Value
            else if RegExMatch(cleanLine, "^([a-zA-Z0-9_\.]+):\s*(.*)$", &match) {
                propName := StrReplace(match[1], "_", ".")
                propValue := match[2]
                
                if RegExMatch(propValue, '^"(.*)"$', &quoteMatch)
                    propValue := quoteMatch[1]
                
                ; Decode HTML hex entities like &#xE756; to native characters
                while RegExMatch(propValue, "&#x([0-9A-Fa-f]+);", &em) {
                    propValue := StrReplace(propValue, em[0], Chr("0x" em[1]))
                }
                    
                currentNode := stack[stack.Length].Node
                
                if (SubStr(propName, 1, 2) == "On") {
                    currentNode.Events[propName] := propValue
                } else {
                    currentNode.Properties[propName] := propValue
                }
            } else {
                if (IsSet(XAMLHost)) {
                    errDetails := "Invalid AXML Syntax on line " index ":`n" cleanLine "`n`nA valid line must either be a Node definition (e.g. 'Button:') or a Property (e.g. 'Content: `"Click Me`"')."
                    hasRetry := (IsSet(XAML_DIAGNOSTICS_ENABLED) && XAML_DIAGNOSTICS_ENABLED)
                    action := XAMLHost.ShowErrorDialog("AXML Compile Error", "AXML Parsing Error in " sourceFile "!", index "|  " cleanLine, errDetails, hasRetry)
                    if (action == "skip_element" || action == "skip_property") {
                        continue
                    } else {
                        ExitApp()
                    }
                } else {
                    MsgBox("AXML Parsing Error in " sourceFile " at line " index ":`n" cleanLine, "AXML Error", "Iconx")
                    ExitApp()
                }
            }
        }
        
        ; Separate templates from main tree
        templates := Map()
        finalNodes := []
        for child in rootNode.Children {
            if (child.IsTemplate)
                templates[child.Type] := child
            else
                finalNodes.Push(child)
        }
        
        return { Nodes: finalNodes, Templates: templates }
    }

    static CloneNode(node, propOverrides) {
        cloned := { IsTemplate: false, IsLoop: (node.HasProp("IsLoop") && node.IsLoop), Type: node.Type, Name: "", Properties: Map(), Events: Map(), Children: [] }
        
        if (cloned.IsLoop) {
            cloned.LoopStart := node.LoopStart
            cloned.LoopEnd := node.LoopEnd
            cloned.LoopVar := node.LoopVar
        }
        if (node.HasProp("SourceLine"))
            cloned.SourceLine := node.SourceLine
            
        if (node.Name != "") {
            newName := node.Name
            for overrideKey, overrideVal in propOverrides {
                newName := StrReplace(newName, "{{" overrideKey "}}", overrideVal)
            }
            cloned.Name := newName
        }
        
        ; Replace variables in properties like {{Icon}}
        for k, v in node.Properties {
            newVal := v
            for overrideKey, overrideVal in propOverrides {
                newVal := StrReplace(newVal, "{{" overrideKey "}}", overrideVal)
            }
            cloned.Properties[k] := newVal
        }
        
        if (node.HasProp("Events") && node.Events) {
            for k, v in node.Events {
                cloned.Events[k] := v
            }
        }
        
        for child in node.Children {
            cloned.Children.Push(this.CloneNode(child, propOverrides))
        }
        
        return cloned
    }

    static RenderAST(astNodes, templates, parentGenerator, stateObj, bindings, events, sourceFile := "Inline AXML") {
        for node in astNodes {
            ; Check if this node is an @For loop
            if (node.HasProp("IsLoop") && node.IsLoop) {
                loopCount := node.LoopEnd - node.LoopStart + 1
                Loop loopCount {
                    currentIndex := node.LoopStart + A_Index - 1
                    for child in node.Children {
                        cloned := this.CloneNode(child, Map(node.LoopVar, String(currentIndex)))
                        this.RenderAST([cloned], templates, parentGenerator, stateObj, bindings, events, sourceFile)
                    }
                }
                continue
            }
            
            ; Check if this node is invoking a template
            if (templates.Has(node.Type)) {
                templateDef := templates[node.Type]
                
                if (templateDef.Children.Length > 0) {
                    instantiatedNode := this.CloneNode(templateDef.Children[1], node.Properties)
                    if (node.Name != "")
                        instantiatedNode.Name := node.Name
                        
                    ; Render the cloned node instead
                    this.RenderAST([instantiatedNode], templates, parentGenerator, stateObj, bindings, events, sourceFile)
                }
                continue
            }
            
            el := parentGenerator.Add(node.Type)
            if (node.HasProp("SourceLine") && (!IsSet(XAML_ENABLE_TRACING) || XAML_ENABLE_TRACING)) {
                el._AhkFile := sourceFile
                el._AhkLine := node.SourceLine
            }
            
            if (node.Name != "")
                el.SetProp("x:Name", node.Name)
                
             for propName, propVal in node.Properties {
                if (SubStr(propVal, 1, 1) == "$") {
                    stateKey := SubStr(propVal, 2)
                    
                    if (node.Name == "") {
                        AXML._idCounter := (AXML.HasOwnProp("_idCounter") ? AXML._idCounter + 1 : 1)
                        node.Name := "AXML_" node.Type "_" AXML._idCounter
                        el.SetProp("x:Name", node.Name)
                    }
                    
                    bindings.Push({ ControlName: node.Name, PropName: propName, StateKey: stateKey })
                    
                    if (stateObj && stateObj._data.Has(stateKey))
                        propVal := String(stateObj._data[stateKey])
                    else
                        propVal := ""
                }
                if (propVal == "")
                    continue
                if (propName == "Cols" || propName == "ColumnDefinitions" || propName == "ColDefs") {
                    colsArr := StrSplit(propVal, ",")
                    for index, val in colsArr
                        colsArr[index] := Trim(val)
                    el.Cols(colsArr*)
                } else if (propName == "Rows" || propName == "RowDefinitions" || propName == "RowDefs") {
                    rowsArr := StrSplit(propVal, ",")
                    for index, val in rowsArr
                        rowsArr[index] := Trim(val)
                    el.Rows(rowsArr*)
                } else if (propName == "BeginStoryboard" || propName == "BringIntoView") {
                    ; Pseudo-properties used only for UI updates via bindings, do not write them to static XAML
                    continue
                } else {
                    el.SetProp(propName, propVal)
                }
            }
            
            if (node.HasProp("Events") && node.Events) {
                for evtName, fnName in node.Events {
                    if (node.Name == "") {
                        AXML._idCounter := (AXML.HasOwnProp("_idCounter") ? AXML._idCounter + 1 : 1)
                        node.Name := "AXML_" node.Type "_" AXML._idCounter
                        el.SetProp("x:Name", node.Name)
                    }
                    realEvtName := SubStr(evtName, 3) ; Strip "On"
                    events.Push({ ControlName: node.Name, EventName: realEvtName, FuncName: fnName })
                }
            }
            
            if (node.Children.Length > 0) {
                this.RenderAST(node.Children, templates, el, stateObj, bindings, events, sourceFile)
            }
        }
    }

    static SerializeAST(nodes, templates := "") {
        out := ""
        if (templates && Type(templates) == "Map") {
            for tName, tNode in templates {
                out .= AXML.SerializeNode(tNode, 0) "`n"
            }
        }
        for node in nodes {
            out .= AXML.SerializeNode(node, 0)
        }
        return out
    }

    static SerializeNode(node, indent) {
        pad := ""
        Loop indent
            pad .= "  "

        out := ""
        if (node.HasProp("IsLoop") && node.IsLoop) {
            out .= pad "@For " node.LoopStart ".." node.LoopEnd " as " node.LoopVar ":`n"
        } else {
            prefix := (node.HasProp("IsTemplate") && node.IsTemplate) ? "@Template " : ""
            isGenerated := (node.HasProp("isGeneratedName") && node.isGeneratedName)
            nameSuffix := (node.HasProp("Name") && node.Name != "" && !isGenerated) ? " (" node.Name ")" : ""
            out .= pad prefix node.Type nameSuffix ":`n"
        }

        ; Properties
        for k, v in node.Properties {
            propName := StrReplace(k, ".", "_")
            if (SubStr(v, 1, 1) == "$" || IsNumber(v)) {
                out .= pad "  " propName ": " v "`n"
            } else {
                escapedVal := StrReplace(v, '"', '\"')
                out .= pad "  " propName ": `"" escapedVal "`"`n"
            }
        }

        ; Events
        if (node.HasProp("Events") && node.Events) {
            for k, v in node.Events {
                out .= pad "  " k ": " v "`n"
            }
        }

        ; Children
        for child in node.Children {
            out .= AXML.SerializeNode(child, indent + 1)
        }

        return out
    }

    static SaveBackup(filePath, content) {
        if (!IsSet(XAML_DESIGNER_BACKUPS_ENABLED) || !XAML_DESIGNER_BACKUPS_ENABLED)
            return

        SplitPath(filePath, &name, &dir)
        backupsDir := (dir != "" ? dir : A_ScriptDir) "\.backups"
        if !DirExist(backupsDir) {
            try {
                DirCreate(backupsDir)
            } catch {
                return
            }
        }

        timestamp := FormatTime(, "yyyyMMddHHmmss")
        backupPath := backupsDir "\" name "." timestamp ".axml"
        
        try {
            if FileExist(backupPath)
                FileDelete(backupPath)
            FileAppend(content, backupPath, "UTF-8")
        } catch {
            return
        }

        maxBackups := (IsSet(XAML_DESIGNER_MAX_BACKUPS) ? XAML_DESIGNER_MAX_BACKUPS : 50)
        backupFiles := []
        loop Files backupsDir "\" name ".*.axml" {
            backupFiles.Push(A_LoopFileFullPath)
        }

        if (backupFiles.Length > maxBackups) {
            fileList := ""
            for file in backupFiles
                fileList .= file "`n"
            fileList := RTrim(fileList, "`n")
            fileList := Sort(fileList)
            sortedFiles := StrSplit(fileList, "`n")
            
            deleteCount := sortedFiles.Length - maxBackups
            Loop deleteCount {
                try {
                    FileDelete(sortedFiles[A_Index])
                }
            }
        }
    }
}
