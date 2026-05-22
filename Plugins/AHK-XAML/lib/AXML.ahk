#Requires AutoHotkey v2.0
#Include "XAML_Generator.ahk"

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
    
    static ParseFile(filePath, generatorParent, stateObj := "") {
        content := FileRead(filePath, "UTF-8")
        return this.ParseString(content, generatorParent, stateObj)
    }

    static ParseString(content, generatorParent, stateObj := "") {
        lines := StrSplit(content, "`n", "`r")
        astResult := this.BuildAST(lines)
        bindings := []
        events := []
        this.RenderAST(astResult.Nodes, astResult.Templates, generatorParent, stateObj, bindings, events)
        
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
    
    static BuildAST(lines) {
        rootNode := { Children: [] }
        stack := [{ Indent: -1, Node: rootNode }]
        
        for index, line in lines {
            if (Trim(line) == "" || SubStr(Trim(line), 1, 1) == "#")
                continue
            
            indent := 0
            while (SubStr(line, indent + 1, 1) == " ")
                indent++
            
            cleanLine := Trim(line)
            
            ; Determine if it's a Node definition: [@Template] Type (Name):
            if RegExMatch(cleanLine, "^(@Template\s+)?([a-zA-Z0-9_\.]+)(?:\s*\(([^)]+)\))?:$", &match) {
                isTemplate := (Trim(match[1]) == "@Template")
                typeName := match[2]
                nodeName := match[3]
                
                newNode := { IsTemplate: isTemplate, Type: typeName, Name: nodeName, Properties: Map(), Events: Map(), Children: [] }
                
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
        cloned := { IsTemplate: false, Type: node.Type, Name: node.Name, Properties: Map(), Events: Map(), Children: [] }
        
        ; Replace variables in properties like {{Icon}}
        for k, v in node.Properties {
            newVal := v
            for overrideKey, overrideVal in propOverrides {
                newVal := StrReplace(newVal, "{{" overrideKey "}}", overrideVal)
            }
            cloned.Properties[k] := newVal
        }
        
        for k, v in node.Events {
            cloned.Events[k] := v
        }
        
        for child in node.Children {
            cloned.Children.Push(this.CloneNode(child, propOverrides))
        }
        
        return cloned
    }

    static RenderAST(astNodes, templates, parentGenerator, stateObj, bindings, events) {
        for node in astNodes {
            ; Check if this node is invoking a template
            if (templates.Has(node.Type)) {
                templateDef := templates[node.Type]
                
                ; Clone the template's first child (the root of the template definition)
                ; Wait, a template is defined like:
                ; @Template SettingCard:
                ;   Border:
                ;     ...
                ; So the template's Children[1] is the actual root element.
                if (templateDef.Children.Length > 0) {
                    instantiatedNode := this.CloneNode(templateDef.Children[1], node.Properties)
                    if (node.Name != "")
                        instantiatedNode.Name := node.Name
                        
                    ; Render the cloned node instead
                    this.RenderAST([instantiatedNode], templates, parentGenerator, stateObj, bindings, events)
                }
                continue
            }
            
            el := ""
            el := parentGenerator.Add(node.Type)
            if (node.Name != "")
                el.SetProp("x:Name", node.Name)
                
            for propName, propVal in node.Properties {
                if (SubStr(propVal, 1, 1) == "$") {
                    stateKey := SubStr(propVal, 2)
                    
                    if (node.Name == "") {
                        node.Name := "AXML_" node.Type "_" A_TickCount "_" A_Index
                        el.SetProp("x:Name", node.Name)
                    }
                    
                    bindings.Push({ ControlName: node.Name, PropName: propName, StateKey: stateKey })
                    
                    if (stateObj && stateObj._data.Has(stateKey))
                        propVal := String(stateObj._data[stateKey])
                    else
                        propVal := ""
                }
                if (propName == "Cols") {
                    colsArr := StrSplit(propVal, ",")
                    for index, val in colsArr
                        colsArr[index] := Trim(val)
                    el.Cols(colsArr*)
                } else if (propName == "Rows") {
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
            
            for evtName, fnName in node.Events {
                if (node.Name == "") {
                    node.Name := "AXML_" node.Type "_" A_TickCount "_" A_Index
                    el.SetProp("x:Name", node.Name)
                }
                realEvtName := SubStr(evtName, 3) ; Strip "On"
                events.Push({ ControlName: node.Name, EventName: realEvtName, FuncName: fnName })
            }
            
            if (node.Children.Length > 0) {
                this.RenderAST(node.Children, templates, el, stateObj, bindings, events)
            }
        }
    }
}
