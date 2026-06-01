class XAMLElement {
    __New(tag, textContent := "") {
        this._Tag := tag
        this._Props := Map()
        this._Children := []
        this._TextContent := textContent
        this._Parent := ""
        this._Defaults := Map()
        this._TrackCaller()
    }

    _TrackCaller(depth := -2) {
        if (IsSet(XAML_ENABLE_TRACING) && XAML_ENABLE_TRACING) {
            try {
                err := Error("", depth)
                SplitPath err.File, &outFile
                this._AhkFile := outFile
                this._AhkLine := err.Line
            } catch {
                this._AhkFile := ""
                this._AhkLine := ""
            }
        } else {
            this._AhkFile := ""
            this._AhkLine := ""
        }
    }

    ; Sets default properties for a specific tag within this element's scope.
    ; Children added to this element (or its descendants) will inherit these cascading properties.
    SetDefaults(tag, propsObj) {
        this._Defaults[tag] := propsObj
        return this
    }

    ; Instantly apply a map or object of properties to this specific element.
    ; Resolves shorthands: {W: 120, Fg: "White", Bold: true} → {Width: 120, Foreground: "White", FontWeight: "Bold"}
    Apply(propsObj) {
        this._TrackCaller()
        for k, v in (Type(propsObj) == "Map" ? propsObj : propsObj.OwnProps()) {
            ; Check zero-param shorthands (Bold: true, Wrap: true, Center: true, etc.)
            if (XAMLElement._ZeroParamAliases.Has(k) && v == true) {
                for pk, pv in XAMLElement._ZeroParamAliases[k]
                    this._Props[pk] := pv
                continue
            }
            ; Resolve alias
            resolved := this._ResolveAlias(k)
            propName := StrReplace(resolved, "_", ".")
            this._Props[propName] := v
        }
        return this
    }

    ; Define a named template at the root level so it can be reused anywhere
    DefineTemplate(name, templateObjOrFunc) {
        root := this
        while root._Parent
            root := root._Parent
        
        if !root.HasProp("_Templates")
            root._Templates := Map()
            
        root._Templates[name] := templateObjOrFunc
        return this
    }

    ; Apply a template. Can be a string (named template), an object of properties, or a callback function.
    Use(template) {
        this._TrackCaller()
        if (Type(template) == "String") {
            root := this
            while root._Parent
                root := root._Parent
                
            if (root.HasProp("_Templates") && root._Templates.Has(template)) {
                template := root._Templates[template]
            } else {
                throw Error("Template not found: " template)
            }
        }
        
        if HasMethod(template) {
            template(this)
        } else {
            this.Apply(template)
        }
        return this
    }

    ; Add a child element and return the child for chaining.
    ; Second parameter can be:
    ;   - A string (text content)
    ;   - A Map or Object of properties: Add("Button", {Name: "Btn", W: 120, Bg: "Red"})
    Add(tag, propsOrText := "") {
        child := XAMLElement(tag, Type(propsOrText) == "String" ? propsOrText : "")
        child._TrackCaller()
        child._Parent := this
        
        ; Collect inheritance path (from Root down to this node)
        parents := []
        curr := this
        while curr {
            parents.InsertAt(1, curr)
            curr := curr._Parent
        }
        
        ; Apply defaults top-down (CSS-style cascading)
        for p in parents {
            if p._Defaults.Has(tag) {
                defObj := p._Defaults[tag]
                if (defObj == "" || defObj == false) {
                    child._Props.Clear() ; Firewall: reset accumulated defaults
                } else {
                    for k, v in (Type(defObj) == "Map" ? defObj : defObj.OwnProps()) {
                        propName := StrReplace(k, "_", ".")
                        child._Props[propName] := v
                    }
                }
            }
        }
        
        this._Children.Push(child)

        ; Apply object properties if provided
        if (Type(propsOrText) != "String" && propsOrText != "") {
            child.Apply(propsOrText)
        }

        return child
    }

    ; Navigate back to the parent element
    Parent() {
        return this._Parent
    }

    ; Walk the parent chain to find the owning XAML_GUI instance (if any).
    ; Returns the XAML_GUI or "" if the element is not attached to one.
    _FindApp() {
        root := this
        while root._Parent
            root := root._Parent
        return root.HasOwnProp("_App") ? root._App : ""
    }

    ; Find a descendant element by its Name or x:Name
    Find(name) {
        if (this._Props.Has("Name") && this._Props["Name"] == name)
            return this
        if (this._Props.Has("x:Name") && this._Props["x:Name"] == name)
            return this
            
        for child in this._Children {
            if (found := child.Find(name))
                return found
        }
        return ""
    }

    ; ==========================================
    ; SHORTHAND ALIASES — friendly mappings for
    ; common WPF properties. Works in chaining,
    ; object-style Add(), Apply(), and AXML.
    ; ==========================================
    static _Aliases := Map(
        ; Layout shorthands (AHK2 Gui style)
        "W", "Width",
        "H", "Height",
        "HAlign", "HorizontalAlignment",
        "VAlign", "VerticalAlignment",
        "HContentAlign", "HorizontalContentAlignment",
        "VContentAlign", "VerticalContentAlignment",
        ; Color shorthands
        "Fg", "Foreground",
        "Bg", "Background",
        "Colour", "Foreground",
        "BgColour", "Background",
        "Color", "Foreground",
        "BgColor", "Background",
        "BorderColor", "BorderBrush",
        ; Spacing shorthands
        "Pad", "Padding",
        "M", "Margin",
        ; Typography shorthands
        "Size", "FontSize",
        "Weight", "FontWeight",
        "Family", "FontFamily",
        ; Visibility
        "Show", "Visibility",
        "Hidden", "Visibility",
        ; Border
        "Radius", "CornerRadius",
        "Border", "BorderThickness"
    )

    ; Zero-param shorthands — calling .Bold() sets FontWeight="Bold", etc.
    static _ZeroParamAliases := Map(
        "Bold", Map("FontWeight", "Bold"),
        "Italic", Map("FontStyle", "Italic"),
        "Wrap", Map("TextWrapping", "Wrap"),
        "NoWrap", Map("TextWrapping", "NoWrap"),
        "Center", Map("HorizontalAlignment", "Center"),
        "Left", Map("HorizontalAlignment", "Left"),
        "Right", Map("HorizontalAlignment", "Right"),
        "Stretch", Map("HorizontalAlignment", "Stretch"),
        "Top", Map("VerticalAlignment", "Top"),
        "Bottom", Map("VerticalAlignment", "Bottom"),
        "VCenter", Map("VerticalAlignment", "Center"),
        "Collapsed", Map("Visibility", "Collapsed"),
        "Clip", Map("ClipToBounds", "True"),
        "Mono", Map("FontFamily", "Cascadia Code, Consolas, Courier New")
    )

    ; Resolve a property name through the alias table.
    ; Also handles tag-aware aliases like Text → Content on Buttons.
    _ResolveAlias(name) {
        ; Check alias table first
        if (XAMLElement._Aliases.Has(name))
            return XAMLElement._Aliases[name]

        ; Tag-aware: Text() on non-TextBlock elements → Content
        if (name == "Text" && this._Tag != "TextBlock" && this._Tag != "Run" && this._Tag != "TextBox")
            return "Content"

        return name
    }

    ; Intercept unknown methods to dynamically set properties
    __Call(name, params) {
        this._TrackCaller()

        ; Check zero-param shorthands first (Bold, Italic, Wrap, Center, etc.)
        if (params.Length == 0 && XAMLElement._ZeroParamAliases.Has(name)) {
            for k, v in XAMLElement._ZeroParamAliases[name]
                this._Props[k] := v
            return this
        }

        ; Resolve aliases
        resolvedName := this._ResolveAlias(name)

        ; Convert underscores in method names to dots (e.g. Grid_Column -> Grid.Column)
        propName := StrReplace(resolvedName, "_", ".")
        
        if (params.Length == 1) {
            val := params[1]
            
            ; Auto-detect mixed Icon and Text to prevent square rendering
            if ((resolvedName == "Text" || resolvedName == "Content") && Type(val) == "String") {
                hasIcon := false
                hasText := false
                Loop Parse, val {
                    code := Ord(A_LoopField)
                    if (code >= 0xE000 && code <= 0xF8FF)
                        hasIcon := true
                    else if (code > 32)
                        hasText := true
                }
                
                if (hasIcon && hasText) {
                    runs := ""
                    currentType := -1 ; 0 = text, 1 = icon
                    currentStr := ""
                    
                    Flush := () => (
                        currentStr != "" ? (
                            safeStr := StrReplace(currentStr, "&", "&amp;"),
                            safeStr := StrReplace(safeStr, "<", "&lt;"),
                            safeStr := StrReplace(safeStr, ">", "&gt;"),
                            safeStr := StrReplace(safeStr, '"', "&quot;"),
                            safeStr := StrReplace(safeStr, "'", "&apos;"),
                            runs .= (currentType == 1) ? '<Run FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="' safeStr '"/>' : '<Run FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif" Text="' safeStr '"/>',
                            currentStr := ""
                        ) : ""
                    )
                    
                    Loop Parse, val {
                        code := Ord(A_LoopField)
                        isIcon := (code >= 0xE000 && code <= 0xF8FF)
                        
                        if (code == 32) {
                            currentStr .= A_LoopField
                            continue
                        }
                        
                        if (currentType == -1)
                            currentType := isIcon
                            
                        if (isIcon != currentType) {
                            Flush()
                            currentType := isIcon
                        }
                        currentStr .= A_LoopField
                    }
                    Flush()
                    
                    if (this._Tag != "TextBlock") {
                        this._TextContent := '<TextBlock VerticalAlignment="Center" HorizontalAlignment="Center">' runs '</TextBlock>'
                    } else {
                        this._TextContent := runs
                    }
                    return this
                }
            }
            
            this._Props[propName] := val
            return this
        } else if (params.Length == 0) {
            ; For booleans without parameters, default to "True"
            this._Props[propName] := "True"
            return this
        }
        throw Error("Method " name " requires 0 or 1 parameters.")
    }

    ; Explicitly set a property if method interception isn't ideal
    SetProp(name, value) {
        this._TrackCaller()
        this._Props[name] := value
        return this
    }

    ; ==========================================
    ; SHORTHAND BUILDERS
    ; ==========================================

    Cols(widths*) {
        cols := XAMLElement("Grid.ColumnDefinitions")
        for w in widths
            cols.Add("ColumnDefinition").Width(w)
        this._Children.InsertAt(1, cols) ; Insert layout definitions at the top
        return this
    }

    Rows(heights*) {
        rows := XAMLElement("Grid.RowDefinitions")
        for h in heights
            rows.Add("RowDefinition").Height(h)
        this._Children.InsertAt(1, rows)
        return this
    }

    ; Inject raw XAML resources into this element
    InjectResources(rawXamlString) {
        res := XAMLElement(this._Tag ".Resources")
        res._TextContent := rawXamlString
        this._Children.InsertAt(1, res)
        return this
    }

    ; Generate XAML string recursively
    ToString(indent := "") {
        attrStr := ""
        for k, v in this._Props {
            val := StrReplace(String(v), "&", "&amp;")
            val := StrReplace(val, "<", "&lt;")
            val := StrReplace(val, ">", "&gt;")
            val := StrReplace(val, '"', "&quot;")
            val := StrReplace(val, "'", "&apos;")
            val := StrReplace(val, "`r`n", "&#10;")
            val := StrReplace(val, "`n", "&#10;")
            val := StrReplace(val, "`r", "&#10;")
            attrStr .= ' ' k '="' val '"'
        }
        
        tracker := ""
        if (this.HasProp("_AhkLine") && this._AhkLine != "") {
            filePrefix := (this.HasProp("_AhkFile") && this._AhkFile != "") ? this._AhkFile ":" : ""
            tracker := "<!-- [ahk:" filePrefix this._AhkLine "] -->"
        }
        
        if (this._Children.Length == 0 && this._TextContent == "")
            return indent tracker "<" this._Tag attrStr " />`n"
        
        out := indent tracker "<" this._Tag attrStr ">"
        
        if (this._TextContent != "") {
            out .= this._TextContent
        } else {
            out .= "`n"
            for child in this._Children
                out .= child.ToString(indent "    ")
            out .= indent
        }
        out .= "</" this._Tag ">`n"
        return out
    }
}

class XAML_Generator extends XAMLElement {
    __New(tag := "Grid") {
        super.__New(tag)
        this._TrackCaller()
    }

    Compile() {
        return this.ToString("")
    }
}

; ==============================================================================
; Inline Event Registration: .On() and .Track()
; These methods are defined via DefineProp to avoid __Call treating them as
; XAML property setters (since __Call catches all unknown method names).
; ==============================================================================

; Register one or more events on an element (chainable).
; Supports CSV: .On("Click,Focus", handler) and function names: .On("Click", "MyHandler")
XAMLElement.Prototype.DefineProp("On", { Call: _XAMLElement_On })
_XAMLElement_On(this, events, callback) {
    if !this.HasOwnProp("_Events")
        this._Events := []

    ; Support CSV: "Click,Focus" → ["Click", "Focus"]
    for evtName in StrSplit(events, ",", " ") {
        if (Trim(evtName) != "")
            this._Events.Push({ Event: Trim(evtName), Callback: callback })
    }
    return this  ; chainable
}

; Mark an element for state tracking (its value will be included in event state dumps).
XAMLElement.Prototype.DefineProp("Track", { Call: _XAMLElement_Track })
_XAMLElement_Track(this) {
    this._Tracked := true
    return this  ; chainable
}

; Register a global hotkey on an element (chainable).
; action can be:
;   - Omitted:  defaults to "Invoke" (programmatic click/toggle)
;   - A string: "Invoke", "Click", "Focus", "Blur", "Toggle"
;   - A callback: (*) => DoSomething()
; Examples:
;   .Hotkey("^+S")                         ; Ctrl+Shift+S → Invoke (click)
;   .Hotkey("^+F", "Focus")                ; Ctrl+Shift+F → Focus the element
;   .Hotkey("^+X", (*) => MsgBox("Hi"))    ; Ctrl+Shift+X → Custom callback
XAMLElement.Prototype.DefineProp("Hotkey", { Call: _XAMLElement_Hotkey })
_XAMLElement_Hotkey(this, key, action := "Invoke") {
    if !this.HasOwnProp("_Hotkeys")
        this._Hotkeys := []
    this._Hotkeys.Push({ Key: key, Action: action })
    return this  ; chainable
}
