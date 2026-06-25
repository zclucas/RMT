#Requires AutoHotkey v2.0
#Include "XAML_GUI.ahk"
#Include "XAML_Config.ahk"
#Include "XAML_Components.ahk"

global XAML_DevTools_Instance := ""

class XAML_DevTools {
    static ShowFor(targetHost) {
        global XAML_DevTools_Instance
        if (IsSet(XAML_DevTools_Instance) && XAML_DevTools_Instance != "") {
            try {
                WinActivate("ahk_id " XAML_DevTools_Instance.app.host.wpfHwnd)
                return
            }
        }
        XAML_DevTools_Instance := XAML_DevTools(targetHost)
    }

    __New(targetGui) {
        this.targetGui := targetGui
        this.target := targetGui.host
        global XAML_DevTools_Instance := this

        this.hashToName := Map()
        this.hashToUid := Map()
        this.pipelineLogs := []
        this.boundCommitSelection := ObjBindMethod(this, "CommitSelection")

        ; Cache filter states locally to avoid expensive synchronous IPC queries
        this.activeTab := "0"
        this.filterAlpha := true
        this.filterGroup := true
        this.filterLocal := false
        this.filterValid := false
        this.filterEdit := false
        this.searchQ := ""
        this.searchEventQ := ""
        this.preset := "All"
        this.hideDevTools := true

        ; Register event callbacks on target host's background engine
        this.target.OnEvent("Engine", "DevToolsTree", ObjBindMethod(this, "OnTreeReceived"))
        this.target.OnEvent("Engine", "DevToolsProps", ObjBindMethod(this, "OnPropsReceived"))

        this.app := XAML_GUI("Developer Tools - " this.target.id, Map("Sidebar", true, "TitleBarHeight", 45, "CloseAction", "None", "ForceDynamic", true))

        ; Setup theme and list defaults
        this.app.X.InjectResources('
        (
            <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="{DynamicResource TextMain}" />
                <Setter Property="Padding" Value="2" />
            </Style>
            <Style TargetType="Button">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="Foreground" Value="{DynamicResource TextSub}"/>
                <Setter Property="BorderBrush" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Padding" Value="10,4"/>
                <Setter Property="Height" Value="25"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#1AFFFFFF"/>
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#2AFFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
            <Style TargetType="ToggleButton">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="Foreground" Value="{DynamicResource TextSub}"/>
                <Setter Property="BorderBrush" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Padding" Value="10,4"/>
                <Setter Property="Height" Value="25"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ToggleButton">
                            <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="{TemplateBinding Padding}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsChecked" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#1D2A3A"/>
                                    <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
                                    <Setter Property="FontWeight" Value="SemiBold"/>
                                </Trigger>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#1AFFFFFF"/>
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
            <Style TargetType="CheckBox">
                <Setter Property="Foreground" Value="{DynamicResource TextSub}"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="CheckBox">
                            <BulletDecorator Background="Transparent" SnapsToDevicePixels="true">
                                <BulletDecorator.Bullet>
                                    <Grid>
                                        <Border x:Name="border" Width="14" Height="14" CornerRadius="2" BorderThickness="1" BorderBrush="#555555" Background="#222222" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        <Path x:Name="checkMark" Data="M 2,5 L 5,8 L 10,2" Stroke="White" StrokeThickness="2" Visibility="Collapsed" SnapsToDevicePixels="true" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Grid>
                                </BulletDecorator.Bullet>
                                <ContentPresenter Margin="6,0,0,0" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                            </BulletDecorator>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsChecked" Value="true">
                                    <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                                    <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                                    <Setter TargetName="border" Property="Background" Value="{DynamicResource Accent}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                                </Trigger>
                                <Trigger Property="IsMouseOver" Value="true">
                                    <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
            <Style TargetType="TabControl">
                <Setter Property="BorderThickness" Value="0,1,0,0" />
                <Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}" />
                <Setter Property="Background" Value="Transparent" />
                <Setter Property="Padding" Value="0" />
            </Style>
            <Style TargetType="TabItem">
                <Setter Property="HeaderTemplate">
                    <Setter.Value>
                        <DataTemplate>
                            <ContentPresenter Content="{TemplateBinding Content}" Margin="10,5,10,5"/>
                        </DataTemplate>
                    </Setter.Value>
                </Setter>
                <Setter Property="Background" Value="Transparent" />
                <Setter Property="Foreground" Value="{DynamicResource TextSub}" />
                <Setter Property="BorderThickness" Value="0" />
                <Setter Property="Cursor" Value="Hand" />
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="TabItem">
                            <Border x:Name="Border" Background="{TemplateBinding Background}" BorderThickness="0,0,0,2" BorderBrush="Transparent" SnapsToDevicePixels="true">
                                <ContentPresenter x:Name="ContentSite" ContentSource="Header" RecognizesAccessKey="True" HorizontalAlignment="Center" VerticalAlignment="Center" SnapsToDevicePixels="true"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsSelected" Value="true">
                                    <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource Accent}" />
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}" />
                                    <Setter Property="FontWeight" Value="SemiBold" />
                                </Trigger>
                                <Trigger Property="IsMouseOver" Value="true">
                                    <Setter Property="Foreground" Value="{DynamicResource TextMain}" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
        )')

        this.app.AddTab("Elements", ObjBindMethod(this, "BuildElementsTab"))
        this.app.AddTab("Pipeline", ObjBindMethod(this, "BuildPipelineTab"))
        this.app.AddTab("Console", ObjBindMethod(this, "BuildConsoleTab"))

        this.app.Compile()

        ; Replicate parent window theme
        if (targetGui.HasProp("currentThemeName") && targetGui.currentThemeName != "") {
            try this.app.ThemeChanged(Map("ComboTheme", targetGui.currentThemeName), "ComboTheme", "")
        }

        ; Wire events on DevTools own compiled window
        this.app.host.OnEvent("BtnRefreshTree", "Click", ObjBindMethod(this, "RequestTree"))
        this.app.host.OnEvent("BtnInspect", "Click", ObjBindMethod(this, "OnInspectToggle"))

        ; Explicitly track required DevTools controls for event state dumps
        this.app.host.Track("TreeElements")
        this.app.host.Track("LogPipeline")
        this.app.host.Track("BtnTogglePipelineDetails")
        this.app.host.Track("BtnFilterDevTools")
        this.app.host.Track("BtnFilterAlpha")
        this.app.host.Track("BtnFilterGroup")
        this.app.host.Track("BtnFilterLocal")
        this.app.host.Track("BtnFilterValid")
        this.app.host.Track("BtnFilterEdit")
        this.app.host.Track("TxtPropSearch")
        this.app.host.Track("TxtEventSearch")
        this.app.host.Track("ComboPresets")

        ; Listen for global events from the target application (sent from background engine)
        this.targetGui.host.OnEvent("AppWindow", "InspectPicked", ObjBindMethod(this, "OnInspectPicked"))

        this.app.host.OnEvent("TreeElements", "SelectedItemChanged", ObjBindMethod(this, "OnElementSelected"))
        this.app.host.OnEvent("BtnConsoleRun", "Click", ObjBindMethod(this, "OnConsoleRun"))
        this.app.host.OnEvent("BtnClearPipeline", "Click", ObjBindMethod(this, "OnClearPipeline"))
        this.app.host.OnEvent("LogPipeline", "SelectionChanged", ObjBindMethod(this, "OnPipelineSelected"))
        this.app.host.OnEvent("BtnTogglePipelineDetails", "Click", ObjBindMethod(this, "OnTogglePipelineDetails"))
        this.app.host.OnEvent("BtnFilterDevTools", "Click", ObjBindMethod(this, "OnFilterDevToolsChanged"))
        this.app.host.OnEvent("BtnClearConsole", "Click", (*) => this.app.host.Update("LogConsole", "Text", ""))

        this.app.host.Track("PropsTabs")
        this.app.host.OnEvent("PropsTabs", "SelectionChanged", ObjBindMethod(this, "OnPropsTabChanged"))

        this.app.host.OnEvent("BtnFilterAlpha", "Click", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("BtnFilterGroup", "Click", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("BtnFilterLocal", "Click", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("BtnFilterValid", "Click", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("BtnFilterEdit", "Click", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("TxtPropSearch", "TextChanged", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("TxtEventSearch", "TextChanged", ObjBindMethod(this, "OnPropFilterChanged"))
        this.app.host.OnEvent("ComboPresets", "SelectionChanged", ObjBindMethod(this, "OnPropFilterChanged"))

        this.app.host.OnEvent("Window", "Closed", ObjBindMethod(this, "OnClosed"))

        this.app.Show()

        ; Initial request
        this.RequestTree()
    }

    BuildElementsTab(tab) {
        grid := tab.Add("Grid")
        grid.Cols("2*", "5", "1*")

        leftPanel := grid.Add("Grid").Grid_Column(0)
        leftPanel.Rows("Auto", "*")

        toolbar := leftPanel.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,8")
        toolbar.Add("Button").Name("BtnRefreshTree").Content("Refresh Tree").Margin("0,0,5,0")
        toolbar.Add("ToggleButton").Name("BtnInspect").Content("Inspect")

        leftPanel.Add("Border").Grid_Row(1).Use("CardPanel").Add("TreeView").Name("TreeElements").Background("Transparent").BorderThickness(0)

        grid.Add("GridSplitter").Grid_Column(1).Width(5).HorizontalAlignment("Center").Background("Transparent")

        rightPanel := grid.Add("Grid").Grid_Column(2)
        rightPanel.Rows("Auto", "*")

        topRight := rightPanel.Add("Grid").Grid_Row(0)
        topRight.Cols("*", "Auto")
        topRight.Add("TextBlock").Name("TxtSelectedElement").Text("Select an element").FontWeight("Bold").FontSize(14).Margin("0,0,0,10").Foreground("{DynamicResource TextMain}")

        innerTab := rightPanel.Add("TabControl").Name("PropsTabs").Grid_Row(1).Background("Transparent").BorderThickness("0,1,0,0").BorderBrush("{DynamicResource ControlBorder}")

        ; Styles tab
        tabStyles := innerTab.Add("TabItem").Header("Styles")
        svStyles := tabStyles.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Margin("0,10,0,0")
        this.propsPanelStyles := svStyles.Add("StackPanel").Name("PanelPropsStyles").Margin("0,10,0,10")

        ; Computed tab
        tabComputed := innerTab.Add("TabItem").Header("Computed")
        svComputed := tabComputed.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Margin("0,10,0,0")
        this.propsPanelComputed := svComputed.Add("StackPanel").Name("PanelPropsComputed").Margin("0,10,0,10")

        ; Properties tab
        tabProps := innerTab.Add("TabItem").Header("Properties")
        propsGrid := tabProps.Add("Grid").Margin("0,10,0,0")
        propsGrid.Rows("Auto", "*")

        propsFiltersPanel := propsGrid.Add("Grid").Grid_Row(0).Margin("0,0,0,5")
        propsFiltersPanel.Rows("Auto", "Auto")

        toolbarProps := propsFiltersPanel.Add("WrapPanel").Orientation("Horizontal").Margin("0,0,0,5")

        ; Filter popover trigger
        filterBtn := toolbarProps.Add("ToggleButton").Name("BtnPropsFilters").Content("Filter Options ▾").Width(110).Height(24).ToolTip("Toggle Property Filters").Margin("0,0,5,0")

        ; Create a popover stacked with checkboxes
        pop := filterBtn.AddRichPopover()
        pop.MinWidth(220)

        sp := pop.Add("StackPanel")
        sp.Add("TextBlock").Text("Filter Properties").FontWeight("Bold").FontSize(12).Margin("0,0,0,10").Foreground("{DynamicResource TextMain}")
        sp.Add("CheckBox").Name("BtnFilterAlpha").Content("Sort Alphabetically (A-Z)").Margin("0,4,0,4").IsChecked("True")
        sp.Add("CheckBox").Name("BtnFilterGroup").Content("Group by Category").Margin("0,4,0,4").IsChecked("True")
        sp.Add("CheckBox").Name("BtnFilterLocal").Content("Show Local Properties Only").Margin("0,4,0,4")
        sp.Add("CheckBox").Name("BtnFilterValid").Content("Hide Empty / Null Values").Margin("0,4,0,4")
        sp.Add("CheckBox").Name("BtnFilterEdit").Content("Show Writeable Only (R/W)").Margin("0,4,0,4")

        cb := toolbarProps.Add("ComboBox").Name("ComboPresets").Width(100).Height(24).Margin("0,0,5,0").Foreground("{DynamicResource TextMain}").Background("{DynamicResource ControlBg}")
        cb.Add("ComboBoxItem").Content("All").IsSelected("True")
        cb.Add("ComboBoxItem").Content("Events")
        cb.Add("ComboBoxItem").Content("Mouse & Keys")
        cb.Add("ComboBoxItem").Content("Layout")
        cb.Add("ComboBoxItem").Content("Theme")
        cb.Add("ComboBoxItem").Content("Scroll")

        searchGrid := propsFiltersPanel.Add("Grid").Grid_Row(1).Margin("0,0,0,10")
        searchGrid.Cols("*", "Auto")
        searchGrid.Add("TextBox").Name("TxtPropSearch").Height(24).Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("4,2").ToolTip("Search Properties...").SetProp("Tag", "Search properties...")

        svProps := propsGrid.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto")
        this.propsPanel := svProps.Add("StackPanel").Name("PanelProps").Margin("0,10,0,10")

        ; Events tab
        tabEvents := innerTab.Add("TabItem").Header("Events")
        eventsGrid := tabEvents.Add("Grid").Margin("0,10,0,0")
        eventsGrid.Rows("Auto", "*")

        eventsSearchGrid := eventsGrid.Add("Grid").Grid_Row(0).Margin("0,0,0,10")
        eventsSearchGrid.Add("TextBox").Name("TxtEventSearch").Height(24).Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("4,2").ToolTip("Search Events...").SetProp("Tag", "Search events...")

        svEvents := eventsGrid.Add("ScrollViewer").Grid_Row(1).VerticalScrollBarVisibility("Auto")
        this.propsPanelEvents := svEvents.Add("StackPanel").Name("PanelPropsEvents").Margin("0,10,0,10")
    }

    BuildPipelineTab(tab) {
        grid := tab.Add("Grid")
        grid.Rows("Auto", "*")

        toolbar := grid.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,8")
        toolbar.Add("Button").Name("BtnClearPipeline").Content("Clear Log").Margin("0,0,5,0")
        toolbar.Add("ToggleButton").Name("BtnTogglePipelineDetails").Content("Show Details").IsChecked("True").Margin("0,0,10,0")
        toolbar.Add("CheckBox").Name("BtnFilterDevTools").Content("Hide DevTools Traffic").IsChecked("True").VerticalAlignment("Center")

        mainGrid := grid.Add("Grid").Grid_Row(1)
        mainGrid.Cols("*", "Auto", "Auto")

        leftBorder := mainGrid.Add("Border").Grid_Column(0).Use("CardPanel")
        logLb := leftBorder.Add("ListBox").Name("LogPipeline").Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}").Padding("0").SetProp("ScrollViewer.HorizontalScrollBarVisibility", "Disabled").SetProp("SelectedValuePath", "Tag")
        logLb.InjectResources('<Style TargetType="ListBoxItem"><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="BorderThickness" Value="0"/></Style>')

        mainGrid.Add("GridSplitter").Name("PipelineSplitter").Grid_Column(1).Width(5).HorizontalAlignment("Center").Background("Transparent")

        rightBorder := mainGrid.Add("Border").Name("PipelineDetails").Grid_Column(2).Width(400).Use("CardPanel").Margin("5,0,0,0")

        ; TabControl in the right details panel
        detailsTabCtrl := rightBorder.Add("TabControl").Name("PipelineDetailsTabs").Background("Transparent").BorderThickness("0,1,0,0").BorderBrush("{DynamicResource ControlBorder}")

        ; Headers Tab
        tabHeaders := detailsTabCtrl.Add("TabItem").Header("Headers")
        svHeaders := tabHeaders.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Margin("0,10,0,0")
        this.pipelineHeadersPanel := svHeaders.Add("StackPanel").Name("PanelPipelineHeaders").Margin("5,10,5,10")

        ; Payload Tab
        tabPayload := detailsTabCtrl.Add("TabItem").Header("Payload")
        svPayload := tabPayload.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Margin("0,10,0,0")
        this.pipelinePayloadPanel := svPayload.Add("StackPanel").Name("PanelPipelinePayload").Margin("5,10,5,10")

        ; Preview Tab
        tabPreview := detailsTabCtrl.Add("TabItem").Header("Preview")
        svPreview := tabPreview.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Margin("0,10,0,0")
        this.pipelinePreviewPanel := svPreview.Add("StackPanel").Name("PanelPipelinePreview").Margin("5,10,5,10")
    }

    BuildConsoleTab(tab) {
        grid := tab.Add("Grid")
        grid.Rows("Auto", "*", "Auto")
        toolbar := grid.Add("StackPanel").Orientation("Horizontal").Margin("0,0,0,8")
        toolbar.Add("Button").Name("BtnClearConsole").Content("Clear")

        grid.Add("Border").Grid_Row(1).Use("CardPanel").Margin("0,0,0,10").Add("TextBox").Name("LogConsole").Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}").IsReadOnly("True").VerticalScrollBarVisibility("Auto").TextWrapping("Wrap").FontFamily("Consolas")

        inputGrid := grid.Add("Grid").Grid_Row(2)
        inputGrid.Cols("*", "Auto")
        inputGrid.Add("TextBox").Name("InputConsole").FontFamily("Consolas").Height(30)
        inputGrid.Add("Button").Name("BtnConsoleRun").Grid_Column(1).Content("Run").Width(80).Margin("10,0,0,0")
    }

    RequestTree(*) {
        this.target.Update("DEVTOOLS", "GetTree", "")
    }

    OnTreeReceived(state, ctrl, event) {
        rawTree := state["DevToolsTree"]
        if (rawTree == "")
            return

        this.hashToName := Map()
        this.hashToUid := Map()
        lines := StrSplit(rawTree, "`n", "`r")
        xml := ""
        openLevels := []
        itemCount := 0

        for index, line in lines {
            if (line == "")
                continue

            parts := StrSplit(line, "|")
            if (parts.Length < 7)
                continue

            level := Integer(parts[1])
            type := parts[2]
            name := parts[3]
            size := parts[4] "x" parts[5]
            visibility := parts[6]
            hash := parts[7]

            this.hashToName[hash] := name

            displayName := type
            if (name != "")
                displayName .= " (" name ")"
            displayName .= "  [" size "]"

            uid := parts.Length >= 8 ? parts[8] : ""
            this.hashToUid[hash] := uid
            if (uid != "")
                displayName .= " [Line: " uid "]"

            displayName := StrReplace(displayName, '"', "&quot;")
            displayName := StrReplace(displayName, '<', "&lt;")
            displayName := StrReplace(displayName, '>', "&gt;")

            ; Close any open items that are at a level >= the current level
            while (openLevels.Length > 0 && openLevels[openLevels.Length] >= level) {
                openLevels.Pop()
                xml .= "</TreeViewItem>`n"
            }

            itemCount++
            if (itemCount == 1) {
                xml .= '<TreeViewItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Header="' displayName '" Tag="' hash '" IsExpanded="True">'
            } else {
                xml .= '<TreeViewItem Header="' displayName '" Tag="' hash '" IsExpanded="False">`n'
            }

            openLevels.Push(level)
        }

        ; Close any remaining open items
        while (openLevels.Length > 0) {
            openLevels.Pop()
            xml .= "</TreeViewItem>`n"
        }

        this.app.host.Update("TreeElements", "ClearItems", "")
        this.app.host.Update("TreeElements", "AddXamlItem", xml)

        if (this.HasProp("selectedHash") && this.selectedHash != "") {
            this.app.host.Update("TreeElements", "SelectByTag", this.selectedHash)
        }
    }

    OnElementSelected(state, ctrl, event) {
        selectedHash := state["TreeElements"]
        if (selectedHash == "")
            return

        this.selectedHash := selectedHash

        ; Debounce properties fetching and highlighting by 80ms to keep keyboard navigation silky smooth
        SetTimer(this.boundCommitSelection, -80)
    }

    CommitSelection() {
        if (!this.HasProp("selectedHash") || this.selectedHash == "")
            return

        this.target.Update("DEVTOOLS", "Highlight", this.selectedHash)
        this.target.Update("DEVTOOLS", "GetProps", this.selectedHash)
    }

    OnPropsReceived(state, ctrl, event) {
        rawProps := state["DevToolsProps"]
        if (rawProps == "")
            return

        lines := StrSplit(rawProps, "`n", "`r")
        if (lines.Length == 0)
            return

        elementName := lines[1]
        this.app.host.Update("TxtSelectedElement", "Text", "Element: " elementName)

        this.currentProps := []

        loop lines.Length {
            if (A_Index == 1 || lines[A_Index] == "")
                continue

            line := lines[A_Index]

            parts := StrSplit(line, "|", , 4)
            if (parts.Length < 4)
                continue

            category := parts[1]
            isLocal := parts[2] == "1"
            isReadOnly := parts[3] == "1"
            rest := parts[4]

            pos := InStr(rest, "=")
            if !pos
                continue

            leftPart := SubStr(rest, 1, pos - 1)
            rightPart := SubStr(rest, pos + 1)

            colPos := InStr(leftPart, ":")
            if !colPos
                continue

            propType := SubStr(leftPart, 1, colPos - 1)
            propName := SubStr(leftPart, colPos + 1)

            ; Decode value values escaped by C# bridge
            propVal := rightPart
            propVal := StrReplace(propVal, "&#x7C;", "|")
            propVal := StrReplace(propVal, "&#x3D;", "=")
            propVal := StrReplace(propVal, "&#x0A;", "`n")
            propVal := StrReplace(propVal, "&#x0D;", "`r")

            ; Translate NaN on width/height to "Auto"
            lname := StrLower(propName)
            if (propVal == "NaN" && (InStr(lname, "width") || InStr(lname, "height"))) {
                propVal := "Auto"
            }

            this.currentProps.Push({
                Cat: category,
                Local: isLocal,
                ReadOnly: isReadOnly,
                Type: propType,
                Name: propName,
                Val: propVal
            })
        }

        this.RenderProps()
    }

    OnPropFilterChanged(state, ctrl, event) {
        if (!state.Has(event) && !state.Has(ctrl))
            return
        val := state.Has(event) ? state[event] : state[ctrl]
        if (ctrl == "BtnFilterAlpha")
            this.filterAlpha := (val == "True")
        else if (ctrl == "BtnFilterGroup")
            this.filterGroup := (val == "True")
        else if (ctrl == "BtnFilterLocal")
            this.filterLocal := (val == "True")
        else if (ctrl == "BtnFilterValid")
            this.filterValid := (val == "True")
        else if (ctrl == "BtnFilterEdit")
            this.filterEdit := (val == "True")
        else if (ctrl == "TxtPropSearch")
            this.searchQ := StrLower(val)
        else if (ctrl == "TxtEventSearch")
            this.searchEventQ := StrLower(val)
        else if (ctrl == "ComboPresets")
            this.preset := val

        this.RenderProps()
    }

    GetPropVal(name, defaultVal := "0") {
        if (!this.HasProp("currentProps"))
            return defaultVal
        for p in this.currentProps {
            if (p.Name == name)
                return p.Val
        }
        return defaultVal
    }

    ParseThickness(val) {
        if (val == "null" || val == "" || val == "NaN")
            return { Left: "0", Top: "0", Right: "0", Bottom: "0" }

        parts := StrSplit(val, ",")
        if (parts.Length == 1) {
            v := Trim(parts[1])
            if (v == "")
                v := "0"
            return { Left: v, Top: v, Right: v, Bottom: v }
        } else if (parts.Length == 2) {
            h := Trim(parts[1])
            v := Trim(parts[2])
            return { Left: h, Right: h, Top: v, Bottom: v }
        } else if (parts.Length == 4) {
            return { Left: Trim(parts[1]), Top: Trim(parts[2]), Right: Trim(parts[3]), Bottom: Trim(parts[4]) }
        }
        return { Left: "0", Top: "0", Right: "0", Bottom: "0" }
    }

    EscapeXml(str) {
        str := StrReplace(str, "&", "&amp;")
        str := StrReplace(str, '"', "&quot;")
        str := StrReplace(str, "<", "&lt;")
        str := StrReplace(str, ">", "&gt;")
        if (SubStr(str, 1, 1) = "{") {
            str := "{}" . str
        }
        return str
    }

    OnPropsTabChanged(state, ctrl, event) {
        if (!state.Has(event) && !state.Has(ctrl))
            return
        val := state.Has(event) ? state[event] : state[ctrl]
        this.activeTab := val
        this.RenderProps()
    }

    RenderProps() {
        if (!this.HasProp("currentProps"))
            return

        activeTab := this.activeTab
        alpha := this.filterAlpha
        group := this.filterGroup
        filterLocal := this.filterLocal
        valid := this.filterValid
        editOnly := this.filterEdit
        searchQ := this.searchQ
        preset := this.preset

        props := []
        for p in this.currentProps
            props.Push(p)

        if (alpha) {
            ; Simple bubble sort for AHK
            n := props.Length
            loop n - 1 {
                i := A_Index
                loop n - i {
                    j := A_Index
                    if (StrCompare(props[j].Name, props[j + 1].Name) > 0) {
                        temp := props[j]
                        props[j] := props[j + 1]
                        props[j + 1] := temp
                    }
                }
            }
        }

        if (activeTab == "0") {
            this.app.host.Update("PanelPropsStyles", "ClearItems", "")
            ; --- 1. RENDER STYLES TAB ---
            stylesXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="5,10,5,10">'

            ; Local styles block
            stylesXml .= '<TextBlock Text="element.style {" Foreground="#DCDCAA" FontFamily="Consolas" FontSize="12" FontWeight="Bold" Margin="0,0,0,5"/>'
            localStyleCount := 0
            for p in props {
                if (p.Cat == "Style" && p.Local) {
                    localStyleCount++
                    displayName := this.EscapeXml(p.Name)
                    displayVal := this.EscapeXml(p.Val)

                    opacity := p.ReadOnly ? "0.45" : "1.0"
                    roComment := p.ReadOnly ? '  <Run Text="  /* read-only */" Foreground="#6A9955" FontStyle="Italic"/>' : ''

                    stylesXml .= Format('
                    ( LTrim
                        <Grid Margin="15,2,5,2" Opacity="{5}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="•" Foreground="#666666" Margin="0,0,8,0" FontFamily="Consolas" FontSize="11.5" />
                        <TextBlock Grid.Column="1" FontFamily="Consolas" FontSize="11.5" TextWrapping="Wrap" ToolTip="{4}">
                        <Run Text="{1}" Foreground="#4EC9B0" />
                        <Run Text=": " Foreground="#CCCCCC" />
                        <Run Text="{2}" Foreground="#CE9178" />
                        <Run Text=";" Foreground="#CCCCCC" />
                        {3}
                        </TextBlock>
                        </Grid>
                    )', displayName, displayVal, roComment, p.Type, opacity)
                }
            }

            if (localStyleCount == 0) {
                stylesXml .= '<TextBlock Text="  /* no local styles applied */" Foreground="#6A9955" FontFamily="Consolas" FontSize="11.5" FontStyle="Italic" Margin="15,2,5,2"/>'
            }
            stylesXml .= '<TextBlock Text="}" Foreground="#DCDCAA" FontFamily="Consolas" FontSize="12" FontWeight="Bold" Margin="0,5,0,15"/>'

            ; Inherited styles block
            stylesXml .= '<TextBlock Text="Style (Inherited / Resources) {" Foreground="#DCDCAA" FontFamily="Consolas" FontSize="12" FontWeight="Bold" Margin="0,0,0,5"/>'
            inheritedStyleCount := 0
            for p in props {
                if (p.Cat == "Style" && !p.Local) {
                    inheritedStyleCount++
                    displayName := this.EscapeXml(p.Name)
                    displayVal := this.EscapeXml(p.Val)

                    opacity := p.ReadOnly ? "0.45" : "1.0"
                    roComment := p.ReadOnly ? '  <Run Text="  /* read-only */" Foreground="#6A9955" FontStyle="Italic"/>' : ''

                    stylesXml .= Format('
                    ( LTrim
                        <Grid Margin="15,2,5,2" Opacity="{5}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="•" Foreground="#666666" Margin="0,0,8,0" FontFamily="Consolas" FontSize="11.5" />
                        <TextBlock Grid.Column="1" FontFamily="Consolas" FontSize="11.5" TextWrapping="Wrap" ToolTip="{4}">
                        <Run Text="{1}" Foreground="#9CDCFE" />
                        <Run Text=": " Foreground="#CCCCCC" />
                        <Run Text="{2}" Foreground="#CE9178" />
                        <Run Text=";" Foreground="#CCCCCC" />
                        {3}
                        </TextBlock>
                        </Grid>
                    )', displayName, displayVal, roComment, p.Type, opacity)
                }
            }

            if (inheritedStyleCount == 0) {
                stylesXml .= '<TextBlock Text="  /* no inherited styles */" Foreground="#6A9955" FontFamily="Consolas" FontSize="11.5" FontStyle="Italic" Margin="15,2,5,2"/>'
            }
            stylesXml .= '<TextBlock Text="}" Foreground="#DCDCAA" FontFamily="Consolas" FontSize="12" FontWeight="Bold" Margin="0,5,0,0"/>'
            stylesXml .= '</StackPanel>'

            this.app.host.Update("PanelPropsStyles", "AddXamlItem", stylesXml)
        } else if (activeTab == "1") {
            this.app.host.Update("PanelPropsComputed", "ClearItems", "")
            ; --- 2. RENDER COMPUTED BOX MODEL TAB ---
            marginThick := this.ParseThickness(this.GetPropVal("Margin", "0"))
            paddingThick := this.ParseThickness(this.GetPropVal("Padding", "0"))
            borderThick := this.ParseThickness(this.GetPropVal("BorderThickness", "0"))

            actW := this.GetPropVal("ActualWidth", "-")
            actH := this.GetPropVal("ActualHeight", "-")
            if (actW != "-") {
                try actW := Round(Number(actW))
            }
            if (actH != "-") {
                try actH := Round(Number(actH))
            }

            compXml := '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" HorizontalAlignment="Center" Margin="5,15,5,15" Background="Transparent">'
            compXml .= '<Border Background="#F9CC9D" CornerRadius="2" BorderThickness="1" BorderBrush="#E5B98A" Padding="4">'
            compXml .= '<Grid><TextBlock Text="margin" Foreground="#555555" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="2,0,0,0"/>'
            compXml .= '<StackPanel Orientation="Vertical">'
            compXml .= '<TextBlock Text="' marginThick.Top '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            compXml .= '<TextBlock Grid.Column="0" Text="' marginThick.Left '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="2,0,10,0"/>'

            ; Border Box
            compXml .= '<Border Grid.Column="1" Background="#FDE89C" CornerRadius="2" BorderThickness="1" BorderBrush="#E5D38A" Padding="4">'
            compXml .= '<Grid><TextBlock Text="border" Foreground="#555555" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="2,0,0,0"/>'
            compXml .= '<StackPanel Orientation="Vertical">'
            compXml .= '<TextBlock Text="' borderThick.Top '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            compXml .= '<TextBlock Grid.Column="0" Text="' borderThick.Left '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="2,0,10,0"/>'

            ; Padding Box
            compXml .= '<Border Grid.Column="1" Background="#C3E88D" CornerRadius="2" BorderThickness="1" BorderBrush="#B2D381" Padding="4">'
            compXml .= '<Grid><TextBlock Text="padding" Foreground="#555555" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="2,0,0,0"/>'
            compXml .= '<StackPanel Orientation="Vertical">'
            compXml .= '<TextBlock Text="' paddingThick.Top '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>'
            compXml .= '<TextBlock Grid.Column="0" Text="' paddingThick.Left '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="2,0,10,0"/>'

            ; Content Box
            compXml .= '<Border Grid.Column="1" Background="#A6D3F9" CornerRadius="2" BorderThickness="1" BorderBrush="#94BEE2" Padding="15,6">'
            compXml .= '<TextBlock Text="' actW ' × ' actH '" Foreground="#222222" FontSize="10.5" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
            compXml .= '</Border>'

            compXml .= '<TextBlock Grid.Column="2" Text="' paddingThick.Right '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="10,0,2,0"/>'
            compXml .= '</Grid>'
            compXml .= '<TextBlock Text="' paddingThick.Bottom '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '</StackPanel></Grid></Border>'

            compXml .= '<TextBlock Grid.Column="2" Text="' borderThick.Right '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="10,0,2,0"/>'
            compXml .= '</Grid>'
            compXml .= '<TextBlock Text="' borderThick.Bottom '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '</StackPanel></Grid></Border>'

            compXml .= '<TextBlock Grid.Column="2" Text="' marginThick.Right '" Foreground="#444444" FontSize="10" VerticalAlignment="Center" Margin="10,0,2,0"/>'
            compXml .= '</Grid>'
            compXml .= '<TextBlock Text="' marginThick.Bottom '" Foreground="#444444" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,2"/>'
            compXml .= '</StackPanel></Grid></Border>'
            compXml .= '</Grid>'

            layoutXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,15,0,0">'
            layoutXml .= '<TextBlock Text="Computed Layout Properties" Foreground="{DynamicResource TextSub}" FontWeight="Bold" FontSize="11" Margin="5,0,0,10"/>'

            layoutIndex := 0
            for p in props {
                lname := StrLower(p.Name)
                if (InStr(lname, "margin") || InStr(lname, "padding") || InStr(lname, "align") || InStr(lname, "width") || InStr(lname, "height") || InStr(lname, "grid.") || InStr(lname, "canvas.") || InStr(lname, "row") || InStr(lname, "column") || InStr(lname, "thickness") || InStr(lname, "visibility") || InStr(lname, "dock")) {

                    layoutIndex++
                    displayName := this.EscapeXml(p.Name)
                    displayVal := this.EscapeXml(p.Val)

                    labelColor := p.Local ? "#4EC9B0" : "#9CDCFE"
                    bgColor := (Mod(layoutIndex, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                    opacity := p.ReadOnly ? "0.45" : "1.0"

                    layoutXml .= Format('
                    ( LTrim
                        <Grid Margin="0" Background="{6}" Opacity="{7}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="140" />
                        <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="{1}" Foreground="{4}" FontWeight="Normal" VerticalAlignment="Center" Margin="5,4,5,4" ToolTip="{2} (Local: {5})" TextTrimming="CharacterEllipsis" />
                        <TextBox Grid.Column="1" Text="{3}" Background="Transparent" Foreground="#CCCCCC" BorderThickness="0" Padding="5,4" IsReadOnly="True" />
                        </Grid>
                    )', displayName, p.Type, displayVal, labelColor, p.Local ? "Yes" : "No", bgColor, opacity)
                }
            }
            layoutXml .= '</StackPanel>'

            this.app.host.Update("PanelPropsComputed", "AddXamlItem", compXml)
            this.app.host.Update("PanelPropsComputed", "AddXamlItem", layoutXml)
        } else if (activeTab == "2") {
            this.app.host.Update("PanelProps", "ClearItems", "")
            ; --- 3. RENDER ALL PROPERTIES TAB ---
            xml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'

            groups := Map()
            if (group) {
                groups["Style"] := []
                groups["Properties"] := []
                groups["Events"] := []
                groups["Other"] := []
            } else {
                groups["All"] := []
            }

            for p in props {
                if (filterLocal && !p.Local)
                    continue
                if (editOnly && p.ReadOnly)
                    continue
                if (valid && (p.Val == "null" || p.Val == ""))
                    continue

                if (searchQ != "") {
                    if (!InStr(StrLower(p.Name), searchQ) && !InStr(StrLower(p.Val), searchQ))
                        continue
                }

                if (preset != "" && preset != "All") {
                    lname := StrLower(p.Name)
                    match := false
                    if (preset == "Mouse & Keys" && (InStr(lname, "mouse") || InStr(lname, "key") || InStr(lname, "click") || InStr(lname, "focus")))
                        match := true
                    else if (preset == "Layout" && (InStr(lname, "margin") || InStr(lname, "padding") || InStr(lname, "align") || InStr(lname, "width") || InStr(lname, "height") || InStr(lname, "size")))
                        match := true
                    else if (preset == "Theme" && (InStr(lname, "background") || InStr(lname, "foreground") || InStr(lname, "brush") || InStr(lname, "color") || InStr(lname, "border") || InStr(lname, "opacity") || InStr(lname, "fill") || InStr(lname, "stroke")))
                        match := true
                    else if (preset == "Scroll" && InStr(lname, "scroll"))
                        match := true
                    else if (preset == "Text" && (InStr(lname, "font") || InStr(lname, "text")))
                        match := true
                    else if (preset == "Events" && p.Cat == "Events")
                        match := true

                    if (!match)
                        continue
                }

                cat := group ? p.Cat : "All"
                if (!groups.Has(cat))
                    groups[cat] := []
                groups[cat].Push(p)
            }

            for cat, list in groups {
                if (list.Length == 0)
                    continue

                if (group) {
                    xml .= '<Expander IsExpanded="True" Margin="0,2,0,0"><Expander.Header><TextBlock Text="' cat '" Foreground="#E6E6E6" FontWeight="Bold" Margin="0"/></Expander.Header><StackPanel Margin="0,2,0,5">'
                }

                for index, p in list {
                    displayName := this.EscapeXml(p.Name)
                    displayVal := this.EscapeXml(p.Val)

                    labelColor := p.Local ? "#4EC9B0" : "#9CDCFE"
                    bgColor := (Mod(index, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                    opacity := p.ReadOnly ? "0.45" : "1.0"

                    xml .= Format('
                    ( LTrim
                        <Grid Margin="0" Background="{6}" Opacity="{7}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="140" />
                        <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="{1}" Foreground="{4}" FontWeight="Normal" VerticalAlignment="Center" Margin="5,4,5,4" ToolTip="{2} (Local: {5})" TextTrimming="CharacterEllipsis" />
                        <TextBox Grid.Column="1" Text="{3}" Background="Transparent" Foreground="#CCCCCC" BorderThickness="0" Padding="5,4" IsReadOnly="True" />
                        </Grid>
                    )', displayName, p.Type, displayVal, labelColor, p.Local ? "Yes" : "No", bgColor, opacity)
                }

                if (group) {
                    xml .= '</StackPanel></Expander>'
                }
            }

            xml .= '</StackPanel>'

            this.app.host.Update("PanelProps", "AddXamlItem", xml)
        } else if (activeTab == "3") {
            this.app.host.Update("PanelPropsEvents", "ClearItems", "")
            ; --- 4. RENDER EVENTS TAB ---
            eventSearchQ := this.searchEventQ
            eventsXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'

            eventIndex := 0
            for p in props {
                if (p.Cat == "Events") {
                    if (eventSearchQ != "") {
                        if (!InStr(StrLower(p.Name), eventSearchQ) && !InStr(StrLower(p.Val), eventSearchQ))
                            continue
                    }

                    eventIndex++
                    displayName := this.EscapeXml(p.Name)
                    displayVal := this.EscapeXml(p.Val)

                    ; Check if target has AHK event callback registered
                    ctrlName := ""
                    if (this.HasProp("selectedHash") && this.selectedHash != "" && this.hashToName.Has(this.selectedHash)) {
                        ctrlName := this.hashToName[this.selectedHash]
                    }

                    isHooked := false
                    hookedText := "—"
                    if (ctrlName != "" && this.target.events.Has(ctrlName) && this.target.events[ctrlName].Has(p.Name)) {
                        evtList := this.target.events[ctrlName][p.Name]
                        if (evtList.Length > 0) {
                            isHooked := true
                            cb := evtList[1].Callback
                            cbName := this.GetCallbackName(cb)

                            if (cbName == "(inline)") {
                                uid := this.hashToUid.Has(this.selectedHash) ? this.hashToUid[this.selectedHash] : ""
                                sourceCode := this.GetCallbackSource(uid, p.Name)
                                if (sourceCode != "") {
                                    cbName := sourceCode
                                }
                            }

                            hookedText := "Hooked: " . cbName
                        }
                    }

                    labelColor := isHooked ? "#A6E3A1" : "#888888" ; Green if hooked, Muted gray if not
                    opacity := isHooked ? "1.0" : "0.55"
                    bgColor := (Mod(eventIndex, 2) == 0) ? "#0AFFFFFF" : "Transparent"

                    eventsXml .= Format('
                    ( LTrim
                        <Grid Margin="0" Background="{4}" Opacity="{5}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="160" />
                        <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="{2}" Foreground="{3}" FontWeight="SemiBold" VerticalAlignment="Center" Margin="5,4,5,4" ToolTip="{2}" TextTrimming="CharacterEllipsis" />
                        <TextBox Grid.Column="1" Text="{1}" Background="Transparent" Foreground="#CCCCCC" BorderThickness="0" Padding="5,4" IsReadOnly="True" />
                        </Grid>
                    )', this.EscapeXml(hookedText), displayName, labelColor, bgColor, opacity)
                }
            }

            if (eventIndex == 0) {
                eventsXml .= '<TextBlock Text="No events registered." Foreground="{DynamicResource TextSub}" Margin="5,10,0,0" FontStyle="Italic"/>'
            }

            eventsXml .= '</StackPanel>'

            this.app.host.Update("PanelPropsEvents", "AddXamlItem", eventsXml)
        }
    }

    LogIPC(dir, payload) {
        ts := FormatTime(, "HH:mm:ss") "." A_MSec
        dirIcon := (dir == "IN") ? "<-" : "->"

        ; Save raw message with timestamp for details look up
        rawMsg := ts . " " . dirIcon . " " . payload
        this.pipelineLogs.Push(rawMsg)

        ; Check if we should filter this message
        hideDevTools := this.hideDevTools

        lines := StrSplit(payload, "`n", "`r")
        firstLine := lines[1]

        isDevToolsMsg := false
        if (SubStr(firstLine, 1, 6) == "EVENT|") {
            parts := StrSplit(firstLine, "|", , 5)
            ctrlName := parts.Length >= 3 ? parts[3] : ""
            eventName := parts.Length >= 4 ? parts[4] : ""
            if (ctrlName == "Engine" && (eventName == "DevToolsTree" || eventName == "DevToolsProps"))
                isDevToolsMsg := true
            else if (ctrlName == "AppWindow" && eventName == "InspectPicked")
                isDevToolsMsg := true
        } else {
            parts := StrSplit(firstLine, "|", , 3)
            ctrlName := parts.Length >= 1 ? parts[1] : ""
            eventName := parts.Length >= 2 ? parts[2] : ""
            if (ctrlName == "DEVTOOLS")
                isDevToolsMsg := true
        }

        if (hideDevTools && isDevToolsMsg)
            return

        msgParts := this.ParseIPCMessage(payload, dir)

        ; Trigger tracing
        trigger := ""
        if (dir == "IN") {
            isDevTools := (msgParts.Ctrl == "Engine" && (msgParts.Event == "DevToolsTree" || msgParts.Event == "DevToolsProps")) || (msgParts.Ctrl == "AppWindow" && msgParts.Event == "InspectPicked")
            if (!isDevTools) {
                this.lastEventTrace := "EVENT [" . msgParts.Ctrl . " : " . msgParts.Event . "]"
                this.lastEventTime := A_TickCount
            }
        } else if (dir == "OUT") {
            if (this.HasProp("lastEventTrace") && this.lastEventTrace != "" && A_TickCount - this.lastEventTime < 800) {
                trigger := this.lastEventTrace
            }
        }

        xaml := this.BuildLogItemXaml(ts, dir, msgParts.Type, msgParts.Ctrl, msgParts.Event, msgParts.Size, msgParts.Val, trigger, this.pipelineLogs.Length)
        this.app.host.Update("LogPipeline", "AddXamlItem", xaml)
    }

    OnFilterDevToolsChanged(state, ctrl, event) {
        if (!state.Has(event) && !state.Has(ctrl))
            return
        val := state.Has(event) ? state[event] : state[ctrl]
        this.hideDevTools := (val == "True")
        this.RenderPipelineList()
    }

    RenderPipelineList() {
        this.app.host.Update("LogPipeline", "ClearItems", "")
        
        hideDevTools := this.hideDevTools

        lastEventInLoop := ""

        for rawMsg in this.pipelineLogs {
            pos := InStr(rawMsg, " ")
            if (!pos)
                continue
            ts := SubStr(rawMsg, 1, pos - 1)

            rest := SubStr(rawMsg, pos + 1)
            posDir := InStr(rest, " ")
            if (!posDir)
                continue
            dirIcon := SubStr(rest, 1, posDir - 1)
            payload := SubStr(rest, posDir + 1)
            dir := (dirIcon == "<-") ? "IN" : "OUT"

            lines := StrSplit(payload, "`n", "`r")
            firstLine := lines[1]

            isDevToolsMsg := false
            if (SubStr(firstLine, 1, 6) == "EVENT|") {
                parts := StrSplit(firstLine, "|", , 5)
                ctrlName := parts.Length >= 3 ? parts[3] : ""
                eventName := parts.Length >= 4 ? parts[4] : ""
                if (ctrlName == "Engine" && (eventName == "DevToolsTree" || eventName == "DevToolsProps"))
                    isDevToolsMsg := true
                else if (ctrlName == "AppWindow" && eventName == "InspectPicked")
                    isDevToolsMsg := true
            } else {
                parts := StrSplit(firstLine, "|", , 3)
                ctrlName := parts.Length >= 1 ? parts[1] : ""
                eventName := parts.Length >= 2 ? parts[2] : ""
                if (ctrlName == "DEVTOOLS")
                    isDevToolsMsg := true
            }

            if (hideDevTools && isDevToolsMsg)
                continue

            msgParts := this.ParseIPCMessage(payload, dir)

            trigger := ""
            if (dir == "OUT") {
                if (lastEventInLoop != "") {
                    trigger := lastEventInLoop
                }
            } else {
                isDevTools := (msgParts.Ctrl == "Engine" && (msgParts.Event == "DevToolsTree" || msgParts.Event == "DevToolsProps")) || (msgParts.Ctrl == "AppWindow" && msgParts.Event == "InspectPicked")
                if (!isDevTools) {
                    lastEventInLoop := "EVENT [" . msgParts.Ctrl . " : " . msgParts.Event . "]"
                } else {
                    lastEventInLoop := ""
                }
            }
            logIndex := A_Index

            xaml := this.BuildLogItemXaml(ts, dir, msgParts.Type, msgParts.Ctrl, msgParts.Event, msgParts.Size, msgParts.Val, trigger, logIndex)
            this.app.host.Update("LogPipeline", "AddXamlItem", xaml)
        }
    }

    GetCallbackName(cb) {
        if (Type(cb) == "String")
            return cb
        name := ""
        try {
            if (HasProp(cb, "Name"))
                name := cb.Name
        }
        try {
            if (name == "")
                name := cb.Name
        }
        if (name == "") {
            t := Type(cb)
            if (t == "Func")
                return "(inline)"
            if (t == "BoundFunc")
                return "(bound)"
            return t
        }
        return name
    }

    GetCallbackSource(uid, eventName) {
        if (uid == "")
            return ""
        pos := InStr(uid, ":")
        if (!pos)
            return ""
        filename := SubStr(uid, 1, pos - 1)
        lineNum := Integer(SubStr(uid, pos + 1))

        filePath := A_ScriptDir . "\" . filename
        if (!FileExist(filePath)) {
            filePath := A_WorkingDir . "\" . filename
            if (!FileExist(filePath)) {
                filePath := A_ScriptDir . "\examples\basic\" . filename
                if (!FileExist(filePath))
                    return ""
            }
        }

        try {
            fileContent := FileRead(filePath)
            lines := StrSplit(fileContent, "`n", "`r")

            startLine := lineNum
            endLine := Min(lines.Length, lineNum + 8)

            fullBlock := ""
            loop endLine - startLine + 1 {
                currIdx := startLine + A_Index - 1
                fullBlock .= lines[currIdx] . "`n"
            }

            pattern := "i)\.On\(\s*[" . Chr(34) . Chr(39) . "]" . eventName . "[" . Chr(34) . Chr(39) . "]\s*,\s*(.*)"
            if (RegExMatch(fullBlock, pattern, &match)) {
                rest := match[1]

                parenCount := 1
                callbackStr := ""
                loop Parse, rest {
                    char := A_LoopField
                    if (char == "(")
                        parenCount++
                    else if (char == ")") {
                        parenCount--
                        if (parenCount == 0)
                            break
                    }
                    callbackStr .= char
                }
                return Trim(callbackStr)
            }
        }
        return ""
    }

    OnTogglePipelineDetails(state, ctrl, event) {
        isChecked := state.Has("BtnTogglePipelineDetails") && state["BtnTogglePipelineDetails"] == "True"
        if (isChecked) {
            this.app.host.Update("PipelineDetails", "Visibility", "Visible")
            this.app.host.Update("PipelineSplitter", "Visibility", "Visible")
        } else {
            this.app.host.Update("PipelineDetails", "Visibility", "Collapsed")
            this.app.host.Update("PipelineSplitter", "Visibility", "Collapsed")
        }
    }

    ParseIPCMessage(payload, dir) {
        isEvent := false
        type := ""
        ctrlName := ""
        eventName := ""
        pLoadDec := ""
        winId := ""
        stateMap := Map()

        if (SubStr(payload, 1, 6) == "EVENT|") {
            isEvent := true
            parts := StrSplit(payload, "|", , 5)
            type := parts[1]
            winId := parts.Length >= 2 ? parts[2] : ""
            ctrlName := parts.Length >= 3 ? parts[3] : ""
            
            if (parts.Length >= 5) {
                eventName := parts[4]
                pLoad := parts[5]
                
                ; Clean trailing newlines that might be appended by bridge packaging
                if (SubStr(pLoad, -1) == "`n") {
                    pLoad := SubStr(pLoad, 1, -1)
                }
                if (SubStr(pLoad, -1) == "`r") {
                    pLoad := SubStr(pLoad, 1, -1)
                }
                
                pLoadDec := XAMLHost.DecodeValue(pLoad)
                pLoadDec := StrReplace(pLoadDec, "&#x7C;", "|")
                pLoadDec := StrReplace(pLoadDec, "&#x3D;", "=")
                pLoadDec := StrReplace(pLoadDec, "&#x0A;", "`n")
                pLoadDec := StrReplace(pLoadDec, "&#x0D;", "`r")
            } else if (parts.Length == 4) {
                ; No custom payload, but might have state map
                rest := parts[4]
                subParts := StrSplit(rest, "`n", "`r")
                eventName := subParts[1]
                
                loop subParts.Length {
                    if (A_Index == 1 || subParts[A_Index] == "")
                        continue
                    line := subParts[A_Index]
                    posEq := InStr(line, "=")
                    if (posEq) {
                        k := SubStr(line, 1, posEq - 1)
                        valEnc := SubStr(line, posEq + 1)
                        valDec := XAMLHost.DecodeValue(valEnc)
                        stateMap[k] := valDec
                    }
                }
            }
        } else {
            ; Outgoing or Query command
            parts := StrSplit(payload, "|", , 3)
            type := (dir == "OUT") ? "Command (Update)" : "Query"
            ctrlName := parts.Length >= 1 ? parts[1] : ""
            eventName := parts.Length >= 2 ? parts[2] : ""
            pLoad := parts.Length >= 3 ? parts[3] : ""
            
            if (pLoad != "") {
                if (SubStr(pLoad, -1) == "`n") {
                    pLoad := SubStr(pLoad, 1, -1)
                }
                if (SubStr(pLoad, -1) == "`r") {
                    pLoad := SubStr(pLoad, 1, -1)
                }
                pLoadDec := (dir == "OUT") ? pLoad : XAMLHost.DecodeValue(pLoad)
                pLoadDec := StrReplace(pLoadDec, "&#x7C;", "|")
                pLoadDec := StrReplace(pLoadDec, "&#x3D;", "=")
                pLoadDec := StrReplace(pLoadDec, "&#x0A;", "`n")
                pLoadDec := StrReplace(pLoadDec, "&#x0D;", "`r")
            }
        }
        
        ; Calculate beautiful display tags
        sizeText := ""
        valText := ""
        
        if (isEvent) {
            if (pLoadDec != "") {
                len := StrLen(pLoadDec)
                if (len > 1000) {
                    sizeText := "📦 [" . Round(len / 1024, 1) . " KB]"
                } else if (len > 0) {
                    sizeText := "📦 [" . len . " ch]"
                }
            } else if (stateMap.Count > 0) {
                sizeText := "📦 [" . stateMap.Count . " state vars]"
            }
        } else {
            if (pLoadDec != "") {
                if (StrLen(pLoadDec) < 40 && !InStr(pLoadDec, "`n")) {
                    valText := pLoadDec
                } else {
                    sizeText := "📦 [" . StrLen(pLoadDec) . " ch]"
                }
            }
        }
        
        return {
            Type: type,
            Ctrl: ctrlName,
            Event: eventName,
            WinId: winId,
            PayloadDec: pLoadDec,
            StateMap: stateMap,
            Size: sizeText,
            Val: valText
        }
    }

    BuildLogItemXaml(ts, dir, type, ctrlName, eventName, sizeText, valText, triggerText := "", logIndex := 0) {
        bgColor := "Transparent"
        badgeBg := "#222222"
        badgeFg := "#888888"
        badgeBorder := "#444444"
        badgeText := "MSG"
        
        arrowIcon := "→"
        arrowColor := "#0A84FF"
        
        if (dir == "IN") {
            arrowIcon := "←"
            arrowColor := "#32D74B"
        }
        
        if (type == "EVENT") {
            badgeBg := "#1A3322"
            badgeFg := "#32D74B"
            badgeBorder := "#285A35"
            badgeText := "EVENT"
        } else if (type == "Command (Update)") {
            badgeBg := "#102A45"
            badgeFg := "#0A84FF"
            badgeBorder := "#1F4E79"
            badgeText := "UPDATE"
        } else if (type == "Query") {
            badgeBg := "#352310"
            badgeFg := "#FF9F0A"
            badgeBorder := "#63421A"
            badgeText := "QUERY"
        } else if (ctrlName == "DEVTOOLS" || ctrlName == "Engine") {
            badgeBg := "#2A2A2A"
            badgeFg := "#AAAAAA"
            badgeBorder := "#3F3F3F"
            badgeText := "DEVTOOLS"
        }
        
        summaryText := ""
        if (type == "EVENT") {
            summaryText := ctrlName . " : " . eventName
            if (sizeText != "") {
                summaryText .= "  " . sizeText
            }
        } else {
            summaryText := ctrlName . " [" . eventName . "]"
            if (valText != "") {
                summaryText .= " = " . valText
            }
        }
        
        summaryTextEsc := this.EscapeXml(summaryText)
        tsEsc := this.EscapeXml(ts)
        triggerTextEsc := this.EscapeXml(triggerText)
        
        triggerBlock := ""
        if (triggerTextEsc != "") {
            triggerBlock := '<TextBlock Text="↳ caused by ' . triggerTextEsc . '" Foreground="#6A9955" FontSize="10.5" FontStyle="Italic" Margin="0,3,0,0"/>'
        }
        
        xaml := '<ListBoxItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Tag="' . logIndex . '">'
        xaml .= '<Border Background="Transparent" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="0,0,0,1" Padding="8,6" HorizontalAlignment="Stretch">'
        xaml .= '<Grid>'
        xaml .= '<Grid.ColumnDefinitions>'
        xaml .= '<ColumnDefinition Width="85"/>'
        xaml .= '<ColumnDefinition Width="25"/>'
        xaml .= '<ColumnDefinition Width="75"/>'
        xaml .= '<ColumnDefinition Width="*"/>'
        xaml .= '</Grid.ColumnDefinitions>'
        xaml .= '<TextBlock Grid.Column="0" Text="' . tsEsc . '" Foreground="#888888" FontFamily="Consolas" FontSize="11" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
        xaml .= '<TextBlock Grid.Column="1" Text="' . arrowIcon . '" Foreground="' . arrowColor . '" FontSize="14" FontWeight="Bold" VerticalAlignment="Center" HorizontalAlignment="Center"/>'
        xaml .= '<Border Grid.Column="2" Background="' . badgeBg . '" BorderBrush="' . badgeBorder . '" BorderThickness="1" CornerRadius="4" Padding="4,2" HorizontalAlignment="Center" VerticalAlignment="Center">'
        xaml .= '<TextBlock Text="' . badgeText . '" Foreground="' . badgeFg . '" FontSize="9.5" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Segoe UI"/>'
        xaml .= '</Border>'
        xaml .= '<StackPanel Grid.Column="3" Margin="8,0,0,0" VerticalAlignment="Center">'
        xaml .= '<TextBlock Text="' . summaryTextEsc . '" Foreground="{DynamicResource TextMain}" FontSize="11.5" FontFamily="Consolas" TextWrapping="Wrap"/>'
        xaml .= triggerBlock
        xaml .= '</StackPanel>'
        xaml .= '</Grid>'
        xaml .= '</Border>'
        xaml .= '</ListBoxItem>'
        
        return xaml
    }

    SummarizePayload(dir, payload) {
        lines := StrSplit(payload, "`n", "`r")
        firstLine := lines[1]
        
        if (SubStr(firstLine, 1, 6) == "EVENT|") {
            parts := StrSplit(firstLine, "|", , 5)
            ctrlName := parts.Length >= 3 ? parts[3] : ""
            eventName := parts.Length >= 4 ? parts[4] : ""
            
            summary := "EVENT [" . ctrlName . " : " . eventName . "]"
            
            customPayload := parts.Length >= 5 ? parts[5] : ""
            stateCount := lines.Length - 1
            if (lines[lines.Length] == "") {
                stateCount := Max(0, stateCount - 1)
            }
            
            if (customPayload != "") {
                pLoadDec := XAMLHost.DecodeValue(customPayload)
                len := StrLen(pLoadDec)
                if (len > 1000) {
                    summary .= " 📦 [" . Round(len / 1024, 1) . " KB]"
                } else if (len > 0) {
                    summary .= " 📦 [" . len . " ch]"
                }
            } else if (stateCount > 0) {
                summary .= " 📦 [" . stateCount . " state vars]"
            }
            return summary
        } else {
            parts := StrSplit(firstLine, "|", , 3)
            ctrlName := parts.Length >= 1 ? parts[1] : ""
            eventName := parts.Length >= 2 ? parts[2] : ""
            summary := ctrlName . " [" . eventName . "]"
            
            customPayload := parts.Length >= 3 ? parts[3] : ""
            if (customPayload != "") {
                pLoadDec := (dir == "OUT") ? customPayload : XAMLHost.DecodeValue(customPayload)
                if (pLoadDec != "") {
                    if (StrLen(pLoadDec) < 40) {
                        summary .= " = " . pLoadDec
                    } else {
                        summary .= " 📦 [" . StrLen(pLoadDec) . " ch]"
                    }
                }
            }
            return summary
        }
    }

    OnClearPipeline(*) {
        this.pipelineLogs := []
        this.app.host.Update("LogPipeline", "ClearItems", "")
        this.app.host.Update("PanelPipelineHeaders", "ClearItems", "")
        this.app.host.Update("PanelPipelinePayload", "ClearItems", "")
        this.app.host.Update("PanelPipelinePreview", "ClearItems", "")
    }

    OnPipelineSelected(state, ctrl, event) {
        val := state.Has(event) ? state[event] : (state.Has(ctrl) ? state[ctrl] : "")
        if (val == "")
            return

        ; Extract from "System.Windows.Controls.ListBoxItem: 14" if needed
        pos := InStr(val, " ")
        if (pos) {
            val := SubStr(val, pos + 1)
        }

        if (!IsInteger(val))
            return

        idx := Integer(val)
        if (idx > 0 && idx <= this.pipelineLogs.Length) {
            rawMsg := this.pipelineLogs[idx]
            this.RenderPipelineDetails(rawMsg)
        }
    }

    RenderPipelineDetails(rawMsg) {
        this.app.host.Update("PanelPipelineHeaders", "ClearItems", "")
        this.app.host.Update("PanelPipelinePayload", "ClearItems", "")
        this.app.host.Update("PanelPipelinePreview", "ClearItems", "")

        pos := InStr(rawMsg, " ")
        if (!pos)
            return
        ts := SubStr(rawMsg, 1, pos - 1)

        rest := SubStr(rawMsg, pos + 1)
        posDir := InStr(rest, " ")
        if (!posDir)
            return
        dirIcon := SubStr(rest, 1, posDir - 1)
        dir := (dirIcon == "<-") ? "IN" : "OUT"

        payload := SubStr(rest, posDir + 1)

        msgParts := this.ParseIPCMessage(payload, dir)
        type := msgParts.Type
        ctrlName := msgParts.Ctrl
        eventName := msgParts.Event
        winId := msgParts.WinId
        pLoadDec := msgParts.PayloadDec
        stateMap := msgParts.StateMap

        ; --- A. RENDER HEADERS TAB ---
        headersXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        headersXml .= '<TextBlock Text="General Info" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'

        generalItems := [
            { Key: "Timestamp", Val: ts }, 
            { Key: "Direction", Val: (dirIcon == "<-") ? "Incoming (<-)" : "Outgoing (->)" }, 
            { Key: "Type", Val: type }, 
            { Key: "Control Name", Val: ctrlName }, 
            { Key: "Event / Property", Val: eventName }
        ]
        if (winId != "") {
            generalItems.Push({ Key: "Window ID", Val: winId })
        }

        for idx, item in generalItems {
            bgColor := (Mod(idx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
            headersXml .= Format('
            ( LTrim
                <Grid Margin="0" Background="{3}">
                <Grid.ColumnDefinitions>
                <ColumnDefinition Width="130" />
                <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <TextBlock Text="{1}" Foreground="{DynamicResource TextSub}" FontWeight="Normal" VerticalAlignment="Center" Margin="5,4,5,4" />
                <TextBox Grid.Column="1" Text="{2}" Background="Transparent" Foreground="#CCCCCC" BorderThickness="0" Padding="5,4" IsReadOnly="True" />
                </Grid>
            )', this.EscapeXml(item.Key), this.EscapeXml(item.Val), bgColor)
        }
        headersXml .= '</StackPanel>'
        this.app.host.Update("PanelPipelineHeaders", "AddXamlItem", headersXml)

        ; --- B. RENDER RAW PAYLOAD TAB ---
        payloadXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        
        pText := ""
        if (pLoadDec != "") {
            pText := pLoadDec
        } else if (stateMap.Count > 0) {
            for k, v in stateMap {
                pText .= k . " = " . v . "`r`n"
            }
        }
        
        if (pText == "") {
            payloadXml .= '<TextBlock Text="No payload data." Foreground="{DynamicResource TextSub}" FontStyle="Italic" Margin="5,10,0,0" />'
            payloadXml .= '</StackPanel>'
            this.app.host.Update("PanelPipelinePayload", "AddXamlItem", payloadXml)
        } else {
            payloadXml .= '<TextBlock Text="Raw Payload" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            payloadXml .= '<TextBox xml:space="preserve" Background="Transparent" Foreground="#CCCCCC" BorderThickness="0" Padding="5" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="11">' . this.EscapeXml(pText) . '</TextBox>'
            payloadXml .= '</StackPanel>'
            this.app.host.Update("PanelPipelinePayload", "AddXamlItem", payloadXml)
        }

        ; --- C. RENDER PREVIEW TAB ---
        previewXml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'

        hasPreview := false

        if (eventName == "DevToolsTree" && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Parsed Visual Tree Table" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'

            previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
            previewXml .= '<Grid>'
            previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'

            previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="35"/><ColumnDefinition Width="100"/><ColumnDefinition Width="70"/><ColumnDefinition Width="100"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            previewXml .= '<TextBlock Text="Lvl" FontWeight="Bold" Margin="4" Grid.Column="0" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Type" FontWeight="Bold" Margin="4" Grid.Column="1" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Name" FontWeight="Bold" Margin="4" Grid.Column="2" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Size" FontWeight="Bold" Margin="4" Grid.Column="3" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Visibility" FontWeight="Bold" Margin="4" Grid.Column="4" Foreground="#CCCCCC"/>'
            previewXml .= '</Grid>'

            previewXml .= '<StackPanel Grid.Row="1">'

            tLines := StrSplit(pLoadDec, "`n", "`r")
            tIdx := 0
            for line in tLines {
                if (line == "")
                    continue
                parts := StrSplit(line, "|")
                if (parts.Length < 7)
                    continue
                tIdx++
                if (tIdx > 30) {
                    previewXml .= '<TextBlock Text="... and ' (tLines.Length - 30) ' more elements" FontStyle="Italic" Foreground="{DynamicResource TextSub}" Margin="5,4" />'
                    break
                }

                level := parts[1]
                type := parts[2]
                name := parts[3]
                size := parts[4] "x" parts[5]
                visibility := parts[6]

                bgColor := (Mod(tIdx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                previewXml .= Format('
                ( LTrim
                    <Grid Background="{6}">
                    <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="35"/>
                    <ColumnDefinition Width="100"/>
                    <ColumnDefinition Width="70"/>
                    <ColumnDefinition Width="100"/>
                    <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="{1}" Margin="4" FontSize="11" Foreground="#CCCCCC" />
                    <TextBlock Grid.Column="1" Text="{2}" Margin="4" FontSize="11" Foreground="#A6E3A1" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="2" Text="{3}" Margin="4" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="3" Text="{4}" Margin="4" FontSize="11" Foreground="#CCCCCC" />
                    <TextBlock Grid.Column="4" Text="{5}" Margin="4" FontSize="11" Foreground="{DynamicResource TextSub}" TextTrimming="CharacterEllipsis" />
                    </Grid>
                )', level, this.EscapeXml(type), this.EscapeXml(name), size, visibility, bgColor)
            }
            previewXml .= '</StackPanel></Grid></Border>'
        }
        else if (eventName == "DevToolsProps" && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Parsed Properties Table" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'

            previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
            previewXml .= '<Grid>'
            previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'

            previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/><ColumnDefinition Width="35"/><ColumnDefinition Width="35"/></Grid.ColumnDefinitions>'
            previewXml .= '<TextBlock Text="Property" FontWeight="Bold" Margin="4" Grid.Column="0" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Value" FontWeight="Bold" Margin="4" Grid.Column="1" Foreground="#CCCCCC"/>'
            previewXml .= '<TextBlock Text="Loc" FontWeight="Bold" Margin="4" Grid.Column="2" Foreground="#CCCCCC" HorizontalAlignment="Center"/>'
            previewXml .= '<TextBlock Text="RO" FontWeight="Bold" Margin="4" Grid.Column="3" Foreground="#CCCCCC" HorizontalAlignment="Center"/>'
            previewXml .= '</Grid>'

            previewXml .= '<StackPanel Grid.Row="1">'

            tLines := StrSplit(pLoadDec, "`n", "`r")
            tIdx := 0
            for idx, line in tLines {
                if (idx == 1 || line == "")
                    continue
                parts := StrSplit(line, "|", , 4)
                if (parts.Length < 4)
                    continue
                category := parts[1]
                isLocal := parts[2] == "1" ? "L" : "-"
                isReadOnly := parts[3] == "1" ? "R" : "-"
                rest := parts[4]

                posEq := InStr(rest, "=")
                if (!posEq)
                    continue
                leftPart := SubStr(rest, 1, posEq - 1)
                propVal := SubStr(rest, posEq + 1)

                posCol := InStr(leftPart, ":")
                if (!posCol)
                    continue
                propName := SubStr(leftPart, posCol + 1)

                tIdx++
                if (tIdx > 40) {
                    previewXml .= '<TextBlock Text="... and ' (tLines.Length - 40) ' more properties" FontStyle="Italic" Foreground="{DynamicResource TextSub}" Margin="5,4" />'
                    break
                }

                bgColor := (Mod(tIdx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                previewXml .= Format('
                ( LTrim
                    <Grid Background="{5}">
                    <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="150"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="35"/>
                    <ColumnDefinition Width="35"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="{1}" Margin="4" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="1" Text="{2}" Margin="4" FontSize="11" Foreground="#CE9178" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="2" Text="{3}" Margin="4" FontSize="11" Foreground="#CCCCCC" HorizontalAlignment="Center" />
                    <TextBlock Grid.Column="3" Text="{4}" Margin="4" FontSize="11" Foreground="#CCCCCC" HorizontalAlignment="Center" />
                    </Grid>
                )', this.EscapeXml(propName), this.EscapeXml(propVal), isLocal, isReadOnly, bgColor)
            }

            previewXml .= '</StackPanel></Grid></Border>'
        }
        else if (stateMap.Count > 0) {
            hasPreview := true
            previewXml .= '<TextBlock Text="Event State Dump (Tracked Controls)" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'

            previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
            previewXml .= '<Grid>'
            previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'

            previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            previewXml .= '<TextBlock Text="Tracked Control" FontWeight="Bold" Margin="6" Grid.Column="0" Foreground="#E5C07B"/>'
            previewXml .= '<TextBlock Text="Current Value" FontWeight="Bold" Margin="6" Grid.Column="1" Foreground="#E5C07B"/>'
            previewXml .= '</Grid>'

            previewXml .= '<StackPanel Grid.Row="1">'

            tIdx := 0
            for k, v in stateMap {
                tIdx++
                bgColor := (Mod(tIdx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                previewXml .= Format('
                ( LTrim
                    <Grid Background="{3}">
                    <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="150"/>
                    <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="{1}" Margin="6" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" FontWeight="SemiBold" />
                    <TextBlock Grid.Column="1" Text="{2}" Margin="6" FontSize="11" Foreground="#CE9178" TextWrapping="Wrap" />
                    </Grid>
                )', this.EscapeXml(k), this.EscapeXml(v), bgColor)
            }

            previewXml .= '</StackPanel></Grid></Border>'
        }
        else if ((eventName == "Drop" || eventName == "FileDrop") && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Dropped Files" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            previewXml .= '<StackPanel>'
            files := StrSplit(pLoadDec, "|")
            for idx, file in files {
                if (file == "")
                    continue
                bgColor := (Mod(idx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                previewXml .= Format('
                ( LTrim
                    <Grid Background="{2}" Margin="0,2">
                    <Grid.ColumnDefinitions>
                    <Grid.ColumnDefinition Width="Auto"/>
                    <Grid.ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="📄" Margin="6" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="1" Text="{1}" Margin="6" FontSize="11" Foreground="#CCCCCC" VerticalAlignment="Center" TextWrapping="Wrap"/>
                    </Grid>
                )', this.EscapeXml(file), bgColor)
            }
            previewXml .= '</StackPanel>'
        }
        else if (eventName == "WebMessageReceived" && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Web Message (JSON)" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            
            formattedJson := pLoadDec
            formattedJson := StrReplace(formattedJson, ',"', ',`n  "')
            formattedJson := StrReplace(formattedJson, '{"', '{`n  "')
            formattedJson := StrReplace(formattedJson, '"}', '"`n}')
            
            previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}" Padding="8">'
            previewXml .= '<TextBox xml:space="preserve" Background="Transparent" Foreground="#A6E3A1" BorderThickness="0" FontFamily="Consolas" FontSize="11" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap">' . this.EscapeXml(formattedJson) . '</TextBox>'
            previewXml .= '</Border>'
        }
        else if (eventName == "CaretChanged" && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Caret Position" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            parts := StrSplit(pLoadDec, ",")
            if (parts.Length >= 3) {
                line := parts[1]
                col := parts[2]
                offset := parts[3]
                
                previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}" Padding="10">'
                previewXml .= '<Grid>'
                previewXml .= '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                
                previewXml .= '<StackPanel Grid.Column="0" HorizontalAlignment="Center">'
                previewXml .= '<TextBlock Text="Line" Foreground="{DynamicResource TextSub}" FontSize="10" HorizontalAlignment="Center"/>'
                previewXml .= '<TextBlock Text="' line '" Foreground="#A6E3A1" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>'
                previewXml .= '</StackPanel>'
                
                previewXml .= '<StackPanel Grid.Column="1" HorizontalAlignment="Center">'
                previewXml .= '<TextBlock Text="Column" Foreground="{DynamicResource TextSub}" FontSize="10" HorizontalAlignment="Center"/>'
                previewXml .= '<TextBlock Text="' col '" Foreground="#9CDCFE" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>'
                previewXml .= '</StackPanel>'
                
                previewXml .= '<StackPanel Grid.Column="2" HorizontalAlignment="Center">'
                previewXml .= '<TextBlock Text="Character Offset" Foreground="{DynamicResource TextSub}" FontSize="10" HorizontalAlignment="Center"/>'
                previewXml .= '<TextBlock Text="' offset '" Foreground="#CE9178" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>'
                previewXml .= '</StackPanel>'
                
                previewXml .= '</Grid></Border>'
            }
        }
        else if (eventName == "WordCount" && pLoadDec != "") {
            hasPreview := true
            previewXml .= '<TextBlock Text="Document Statistics" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            parts := StrSplit(pLoadDec, ",")
            if (parts.Length >= 2) {
                words := parts[1]
                chars := parts[2]
                
                previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}" Padding="10">'
                previewXml .= '<Grid>'
                previewXml .= '<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                
                previewXml .= '<StackPanel Grid.Column="0" HorizontalAlignment="Center">'
                previewXml .= '<TextBlock Text="Words" Foreground="{DynamicResource TextSub}" FontSize="10" HorizontalAlignment="Center"/>'
                previewXml .= '<TextBlock Text="' words '" Foreground="#A6E3A1" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>'
                previewXml .= '</StackPanel>'
                
                previewXml .= '<StackPanel Grid.Column="1" HorizontalAlignment="Center">'
                previewXml .= '<TextBlock Text="Characters" Foreground="{DynamicResource TextSub}" FontSize="10" HorizontalAlignment="Center"/>'
                previewXml .= '<TextBlock Text="' chars '" Foreground="#9CDCFE" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>'
                previewXml .= '</StackPanel>'
                
                previewXml .= '</Grid></Border>'
            }
        }
        else if (eventName == "AddXamlItem" && InStr(pLoadDec, "<Grid")) {
            hasPreview := true
            
            ; Parse the outer Grid attributes
            gridAttrs := Map()
            if (RegExMatch(pLoadDec, "^<Grid\s+([^>]+)>", &mGrid)) {
                attrList := mGrid[1]
                posAttr := 1
                while (posAttr := RegExMatch(attrList, '(\S+)="([^"]*)"', &mAttr, posAttr)) {
                    k := mAttr[1]
                    v := mAttr[2]
                    if (k != "xmlns" && k != "Uid" && k != "x:Uid") {
                        gridAttrs[k] := v
                    }
                    posAttr += mAttr.Len
                }
            }

            previewXml .= '<TextBlock Text="Parsed Grid Row Cells" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
            
            ; Parse the TextBlocks inside the XAML grid
            cells := []
            pos := 1
            while (pos := RegExMatch(pLoadDec, "<(\w+)[^>]*>", &match, pos)) {
                el := match[0]
                tag := match[1]
                
                ; Skip definition tags
                if (InStr(tag, "Definition") || InStr(tag, "Column") || InStr(tag, "Row")) {
                    pos += match.Len
                    continue
                }
                
                text := ""
                col := -1
                
                if (RegExMatch(el, 'i)Text="([^"]*)"', &mText))
                    text := mText[1]
                else if (RegExMatch(el, 'i)Content="([^"]*)"', &mContent))
                    text := mContent[1]
                
                if (RegExMatch(el, 'i)Grid\.Column="([^"]*)"', &mCol))
                    col := Integer(mCol[1])
                
                if (col >= 0 || text != "") {
                    cells.Push({ Col: (col >= 0 ? col : 0), Text: text, Tag: tag })
                }
                pos += match.Len
            }

            ; Sort cells by column index
            if (cells.Length > 1) {
                Loop cells.Length - 1 {
                    i := A_Index
                    Loop cells.Length - i {
                        j := A_Index + i
                        if (cells[i].Col > cells[j].Col) {
                            temp := cells[i]
                            cells[i] := cells[j]
                            cells[j] := temp
                        }
                    }
                }
            }

            if (cells.Length > 0) {
                previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}" Margin="0,0,0,15" Padding="10">'
                previewXml .= '<Grid>'
                previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
                
                colsDef := ""
                headerRow := ""
                valRow := ""
                
                tIdx := 0
                for cell in cells {
                    tIdx++
                    colsDef .= '<ColumnDefinition Width="*"/>'
                    headerRow .= Format('<Border Grid.Row="0" Grid.Column="{1}" Background="{DynamicResource SidebarBg}" Padding="6,4" BorderThickness="0,0,1,1" BorderBrush="{DynamicResource ControlBorder}"><TextBlock Text="Col {2} ({3})" FontWeight="SemiBold" FontSize="11" Foreground="{DynamicResource TextSub}" HorizontalAlignment="Center"/></Border>', tIdx - 1, cell.Col, cell.Tag)
                    valRow .= Format('<Border Grid.Row="1" Grid.Column="{1}" Padding="8,6" BorderThickness="0,0,1,0" BorderBrush="{DynamicResource ControlBorder}"><TextBlock Text="{2}" FontSize="12" Foreground="{DynamicResource TextMain}" HorizontalAlignment="Center" TextWrapping="Wrap" TextTrimming="CharacterEllipsis"/></Border>', tIdx - 1, this.EscapeXml(cell.Text))
                }
                
                previewXml .= '<Grid.ColumnDefinitions>' colsDef '</Grid.ColumnDefinitions>'
                previewXml .= headerRow
                previewXml .= valRow
                previewXml .= '</Grid></Border>'
            }

            if (gridAttrs.Count > 0) {
                previewXml .= '<TextBlock Text="Parsed Grid Container Properties" Foreground="#E5C07B" FontWeight="Bold" FontSize="11.5" Margin="0,0,0,6" />'
                previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
                previewXml .= '<Grid>'
                previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'
                
                previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                previewXml .= '<TextBlock Text="Attribute" FontWeight="Bold" Margin="6" Grid.Column="0" Foreground="#CCCCCC"/>'
                previewXml .= '<TextBlock Text="Value" FontWeight="Bold" Margin="6" Grid.Column="1" Foreground="#CCCCCC"/>'
                previewXml .= '</Grid>'
                
                previewXml .= '<StackPanel Grid.Row="1">'
                tIdx := 0
                for k, v in gridAttrs {
                    tIdx++
                    bgColor := (Mod(tIdx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                    previewXml .= Format('
                    ( LTrim
                        <Grid Background="{3}">
                        <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="{1}" Margin="6" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" />
                        <TextBlock Grid.Column="1" Text="{2}" Margin="6" FontSize="11" Foreground="#CE9178" TextWrapping="Wrap" />
                        </Grid>
                    )', this.EscapeXml(k), this.EscapeXml(v), bgColor)
                }
                previewXml .= '</StackPanel></Grid></Border>'
            }
        }

        if (!hasPreview) {
            if (pLoadDec != "" && InStr(pLoadDec, "|")) {
                ; Parse as batched updates
                updates := []
                lines := StrSplit(pLoadDec, "`n", "`r")
                firstVal := lines.Length >= 1 ? lines[1] : ""
                if (ctrlName != "" || eventName != "") {
                    updates.Push({ Control: ctrlName, Property: eventName, Value: firstVal })
                }
                
                loop lines.Length {
                    if (A_Index == 1)
                        continue
                    line := lines[A_Index]
                    if (line == "")
                        continue
                    
                    parts := StrSplit(line, "|", , 3)
                    if (parts.Length >= 2) {
                        cName := parts[1]
                        pName := parts[2]
                        val := parts.Length >= 3 ? parts[3] : ""
                        updates.Push({ Control: cName, Property: pName, Value: val })
                    } else {
                        updates.Push({ Control: "", Property: "", Value: line })
                    }
                }
                
                if (updates.Length > 0) {
                    hasPreview := true
                    previewXml .= '<TextBlock Text="Parsed Batched Updates" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
                    previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
                    previewXml .= '<Grid>'
                    previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'
                    
                    previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                    previewXml .= '<TextBlock Text="Control" FontWeight="Bold" Margin="4" Grid.Column="0" Foreground="#CCCCCC"/>'
                    previewXml .= '<TextBlock Text="Property" FontWeight="Bold" Margin="4" Grid.Column="1" Foreground="#CCCCCC"/>'
                    previewXml .= '<TextBlock Text="Value" FontWeight="Bold" Margin="4" Grid.Column="2" Foreground="#CCCCCC"/>'
                    previewXml .= '</Grid>'
                    
                    previewXml .= '<StackPanel Grid.Row="1">'
                    
                    tIdx := 0
                    for idx, upd in updates {
                        tIdx++
                        if (tIdx > 100) {
                            previewXml .= '<TextBlock Text="... and ' (updates.Length - 100) ' more updates" FontStyle="Italic" Foreground="{DynamicResource TextSub}" Margin="5,4" />'
                            break
                        }
                        
                        bgColor := (Mod(tIdx, 2) == 0) ? "#0AFFFFFF" : "Transparent"
                        previewXml .= Format('
                        ( LTrim
                            <Grid Background="{4}">
                            <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="180"/>
                            <ColumnDefinition Width="110"/>
                            <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="{1}" Margin="4" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" />
                            <TextBlock Grid.Column="1" Text="{2}" Margin="4" FontSize="11" Foreground="#A6E3A1" TextTrimming="CharacterEllipsis" />
                            <TextBlock Grid.Column="2" Text="{3}" Margin="4" FontSize="11" Foreground="#CE9178" TextWrapping="Wrap" />
                            </Grid>
                        )', this.EscapeXml(upd.Control), this.EscapeXml(upd.Property), this.EscapeXml(upd.Value), bgColor)
                    }
                    
                    previewXml .= '</StackPanel></Grid></Border>'
                }
            } else if (ctrlName != "" || eventName != "") {
                ; Parse as a single property update / event
                hasPreview := true
                previewXml .= '<TextBlock Text="Parsed Update / Event" Foreground="#E5C07B" FontWeight="Bold" FontSize="12.5" Margin="0,0,0,8" />'
                previewXml .= '<Border BorderThickness="1" BorderBrush="{DynamicResource ControlBorder}" CornerRadius="4" Background="{DynamicResource ControlBg}">'
                previewXml .= '<Grid>'
                previewXml .= '<Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>'
                
                previewXml .= '<Grid Background="{DynamicResource SidebarBg}"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
                previewXml .= '<TextBlock Text="Control" FontWeight="Bold" Margin="4" Grid.Column="0" Foreground="#CCCCCC"/>'
                previewXml .= '<TextBlock Text="Property / Event" FontWeight="Bold" Margin="4" Grid.Column="1" Foreground="#CCCCCC"/>'
                previewXml .= '<TextBlock Text="Value" FontWeight="Bold" Margin="4" Grid.Column="2" Foreground="#CCCCCC"/>'
                previewXml .= '</Grid>'
                
                previewXml .= '<StackPanel Grid.Row="1">'
                previewXml .= Format('
                ( LTrim
                    <Grid Background="Transparent">
                    <Grid.ColumnDefinitions>
                    <Grid.ColumnDefinition Width="150"/>
                    <Grid.ColumnDefinition Width="120"/>
                    <Grid.ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="{1}" Margin="4" FontSize="11" Foreground="#9CDCFE" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="1" Text="{2}" Margin="4" FontSize="11" Foreground="#A6E3A1" TextTrimming="CharacterEllipsis" />
                    <TextBlock Grid.Column="2" Text="{3}" Margin="4" FontSize="11" Foreground="#CE9178" TextWrapping="Wrap" />
                    </Grid>
                )', this.EscapeXml(ctrlName), this.EscapeXml(eventName), this.EscapeXml(pLoadDec))
                previewXml .= '</StackPanel></Grid></Border>'
            }
        }

        if (!hasPreview) {
            previewXml .= '<TextBlock Text="No preview available for this event type." Foreground="{DynamicResource TextSub}" FontStyle="Italic" Margin="5,10,0,0" />'
        }

        previewXml .= '</StackPanel>'
        this.app.host.Update("PanelPipelinePreview", "AddXamlItem", previewXml)
    }

    OnConsoleRun(*) {
        cmd := this.app.host.Query("InputConsole")
        if (cmd == "")
            return

        this.app.host.Update("InputConsole", "Text", "")
        this.LogConsole(">> " cmd)

        ; Console evaluator logic
        if (SubStr(cmd, 1, 1) == "/") {
            ; Elements direct edit: /Background Red
            if (!this.HasProp("selectedHash") || this.selectedHash == "") {
                this.LogConsole("Error: No element selected in Tree view.")
                return
            }

            parts := StrSplit(SubStr(cmd, 2), " ", , 2)
            if (parts.Length < 2) {
                this.LogConsole("Usage: /Property Value  (e.g., /Background Red)")
                return
            }

            propName := parts[1]
            propVal := parts[2]

            this.target.Update(this.selectedHash, propName, propVal)
            this.LogConsole("Applied property update: " propName " = " propVal)

            ; Refresh properties list
            SetTimer(() => this.target.Update("DEVTOOLS", "GetProps", this.selectedHash), -200)
        }
        else if (SubStr(cmd, 1, 6) == "query ") {
            ctrlName := Trim(SubStr(cmd, 7))
            if (ctrlName == "")
                return
            try {
                res := this.target.Query(ctrlName)
                if (Type(res) == "Map") {
                    out := "Map:`n"
                    for k, v in res
                        out .= "  " k " = " v "`n"
                    this.LogConsole(Trim(out, "`n"))
                } else {
                    this.LogConsole("= " res)
                }
            } catch as err {
                this.LogConsole("Query failed: " err.Message)
            }
        }
        else {
            this.LogConsole("Unknown command. Supported:")
            this.LogConsole("  /Property Value - Write a property to the selected element (e.g. /Background Red)")
            this.LogConsole("  query Name      - Read a control's current value (e.g. query TxtName)")
            this.LogConsole("  query *         - Read all tracked values")
        }
    }

    LogConsole(text) {
        current := this.app.host.Query("LogConsole")
        this.app.host.Update("LogConsole", "Text", (current != "" ? current "`n" : "") text)
    }

    OnInspectToggle(state, ctrl, event) {
        isChecked := state["BtnInspect"] == "True"
        this.targetGui.host.Update("AppWindow", "InspectMode", isChecked ? "1" : "0")
    }

    OnInspectPicked(state, ctrl, event) {
        hash := state.Has("InspectPicked") ? state["InspectPicked"] : ""
        if (hash == "")
            return
        this.app.host.Update("BtnInspect", "IsChecked", "False")

        ; Try to expand the tree item via C# (will add support to Bridge)
        this.app.host.Update("TreeElements", "SelectByTag", hash)
    }

    OnClosed(*) {
        try this.target.Update("DEVTOOLS", "Highlight", "")
        global XAML_DevTools_Instance := ""
    }
}