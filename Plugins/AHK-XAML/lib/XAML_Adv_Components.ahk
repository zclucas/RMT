#Requires AutoHotkey v2.0
#Include "XAML_Host.ahk"
#Include "XAML_Dialog.ahk"
#Include "XAML_Generator.ahk"
#Include "XAML_Components.ahk"

; ==============================================================================
; COMMAND BAR
; ==============================================================================

class XCommandBar {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "CmdBar_" XCommandBar.Count()

        this.container := parentXAML.Add("Border").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").Padding("4")
        this.sp := this.container.Add("StackPanel").Orientation("Horizontal").Name(this.id)
    }

    AddButton(iconHex, text, callbackName := "", tooltip := "") {
        btn := this.sp.Add("Button").Margin("2,0").Padding("8,4")
        btn.InjectResources('<Style TargetType="Button"><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="#15FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')
        if (tooltip != "")
            btn.ToolTip(tooltip)

        sp := btn.Add("StackPanel").Orientation("Horizontal").Margin("4,2")
        sp.Add("TextBlock").Text(iconHex).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14).VerticalAlignment("Center").Margin("0,0,6,0")
        sp.Add("TextBlock").Text(text).VerticalAlignment("Center").FontSize(12)

        if (callbackName != "")
            btn.Name(callbackName)

        return btn
    }

    AddSeparator() {
        this.sp.Add("Rectangle").Width(1).Fill("{DynamicResource ControlBorder}").Margin("4,4,4,4").VerticalAlignment("Stretch")
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("CommandBar", { Call: _CommandBar })
_CommandBar(this, name := "") {
    comp := XCommandBar(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; RICH POPOVER (Extension)
; ==============================================================================

XAMLElement.Prototype.DefineProp("AddRichPopover", { Call: _AddRichPopoverAdv })
_AddRichPopoverAdv(this) {
    if !this._Props.Has("Name") && !this._Props.Has("x:Name")
        this.Name("PopoverTrigger_" XMenuBar.Count())

    name := this._Props.Has("Name") ? this._Props["Name"] : this._Props["x:Name"]

    parent := this._Parent
    popup := parent.Add("Popup")
        .SetProp("IsOpen", "{Binding IsChecked, ElementName=" name ", Mode=TwoWay}")
        .SetProp("StaysOpen", "False")
        .SetProp("PlacementTarget", "{Binding ElementName=" name "}")
        .SetProp("Placement", "Bottom")
        .SetProp("AllowsTransparency", "True")
        .SetProp("PopupAnimation", "Fade")
        .SetProp("VerticalOffset", "4")

    border := popup.Add("Border")
        .Background("{DynamicResource DropdownBg}")
        .BorderBrush("{DynamicResource ControlBorder}")
        .BorderThickness("1")
        .CornerRadius("6")
        .Padding("10")
        .Margin("4")

    border.Add("Border.Effect").Add("DropShadowEffect").BlurRadius("15").ShadowDepth("4").Opacity("0.3").Direction("270")

    border.DefineProp("Add", { Call: _PopoverBorder_Add })
    return border
}

; ==============================================================================
; MENU BAR
; ==============================================================================

class XMenuBar {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "MenuBar_" XMenuBar.Count()
        this.container := parentXAML.Add("Menu").Name(this.id)

        ; Inject beautiful styles for Menu, MenuItem, and Separator
        this.container.InjectResources('
        (
            <Style TargetType="Menu">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                <Setter Property="Padding" Value="2,4"/>
            </Style>
            <Style TargetType="Separator">
                <Setter Property="Background" Value="{DynamicResource ControlBorder}"/>
                <Setter Property="Height" Value="1"/>
                <Setter Property="Margin" Value="4,4"/>
            </Style>
            <Style TargetType="MenuItem">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                <Setter Property="Padding" Value="8,5"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="MenuItem">
                            <Border x:Name="BgBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" SnapsToDevicePixels="True">
                                <Grid>
                                    <Border x:Name="ActiveIndicator" Width="3" Background="{DynamicResource Accent}" HorizontalAlignment="Left" VerticalAlignment="Stretch" Margin="0,6" CornerRadius="1.5" Visibility="Collapsed" Panel.ZIndex="10"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" SharedSizeGroup="Icon"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto" SharedSizeGroup="Shortcut"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        
                                        <ContentPresenter x:Name="Icon" ContentSource="Icon" Margin="10,0,6,0" VerticalAlignment="Center"/>
                                        
                                        <ContentPresenter Grid.Column="1" x:Name="HeaderHost" ContentSource="Header" RecognizesAccessKey="True" Margin="8,3,15,3" VerticalAlignment="Center"/>
                                        
                                        <TextBlock Grid.Column="2" x:Name="GestureText" Text="{TemplateBinding InputGestureText}" Margin="10,0,10,0" VerticalAlignment="Center" Foreground="{DynamicResource TextSub}" FontSize="11"/>
                                        
                                        <Path Grid.Column="3" x:Name="Arrow" Data="M 0,0 L 3,3 L 0,6 Z" Fill="{DynamicResource TextSub}" Margin="6,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                                        
                                        <Popup x:Name="PART_Popup" AllowsTransparency="True" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}" Placement="Bottom" Focusable="False" PopupAnimation="Fade">
                                            <Border Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="6" Padding="4">
                                                <Border.Effect>
                                                    <DropShadowEffect BlurRadius="15" ShadowDepth="4" Opacity="0.3" Direction="270" Color="Black"/>
                                                </Border.Effect>
                                                <ScrollViewer x:Name="SubMenuScrollViewer" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Cycle" KeyboardNavigation.TabNavigation="Cycle" Grid.IsSharedSizeScope="True"/>
                                                </ScrollViewer>
                                            </Border>
                                        </Popup>
                                    </Grid>
                                </Grid>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="Role" Value="TopLevelHeader">
                                    <Setter TargetName="Arrow" Property="Visibility" Value="Collapsed"/>
                                    <Setter TargetName="PART_Popup" Property="Placement" Value="Bottom"/>
                                    <Setter Property="Padding" Value="10,5"/>
                                </Trigger>
                                <Trigger Property="Role" Value="SubmenuHeader">
                                    <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
                                    <Setter TargetName="PART_Popup" Property="Placement" Value="Right"/>
                                </Trigger>
                                <Trigger Property="Role" Value="SubmenuItem">
                                    <Setter TargetName="Arrow" Property="Visibility" Value="Collapsed"/>
                                </Trigger>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#15FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsHighlighted" Value="True">
                                    <Setter Property="Background" Value="#15FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsSubmenuOpen" Value="True">
                                    <Setter Property="Background" Value="#25FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsChecked" Value="True">
                                    <Setter TargetName="ActiveIndicator" Property="Visibility" Value="Visible"/>
                                    <Setter Property="Background" Value="#10FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter Property="Opacity" Value="0.5"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
        )')
    }

    AddMenu(label) {
        item := this.container.Add("MenuItem").Header(label)
        return XMenuPopup(item)
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

class XMenuPopup {
    __New(menuItemElement) {
        this.container := menuItemElement
    }

    AddItem(label, iconHex := "", actionName := "", hotkeyText := "") {
        item := this.container.Add("MenuItem").Header(label)

        if (iconHex != "") {
            item.Add("MenuItem.Icon").Add("TextBlock")
                .Text(iconHex)
                .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
                .FontSize(14)
                .VerticalAlignment("Center")
                .Foreground("{DynamicResource TextSub}")
        }

        if (hotkeyText != "") {
            item.InputGestureText(hotkeyText)
        }

        if (actionName != "") {
            item.Name(actionName)
        }

        return item
    }

    AddSeparator() {
        this.container.Add("Separator")
    }
}

XAMLElement.Prototype.DefineProp("MenuBar", { Call: _MenuBar })
_MenuBar(this, name := "") {
    comp := XMenuBar(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; NAVIGATION VIEW (Sidebar Router)
; ==============================================================================

class XNavigationView {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "NavView_" XNavigationView.Count()
        this.pages := []
        this.ui := ""

        this.grid := parentXAML.Add("Grid").Name(this.id)
        this.grid.Cols("250", "*")

        ; Sidebar
        this.sidebarBorder := this.grid.Add("Border").Grid_Column(0).Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,1,0")
        this.sidebarGrid := this.sidebarBorder.Add("Grid")
        this.sidebarGrid.Rows("Auto", "*", "Auto")

        ; Header (Logo/Title) - Optional placeholder
        this.header := this.sidebarGrid.Add("StackPanel").Grid_Row(0).Margin("15,20,15,10")

        ; Top Items
        this.topList := this.sidebarGrid.Add("StackPanel").Grid_Row(1).Margin("10,0")

        ; Bottom Items
        this.bottomList := this.sidebarGrid.Add("StackPanel").Grid_Row(2).Margin("10,0,10,15")

        ; Main Content Area
        this.contentBorder := this.grid.Add("Border").Grid_Column(1).Background("Transparent").Padding("20")
        this.contentGrid := this.contentBorder.Add("Grid").Name(this.id "_Content")
    }

    AddPage(title, iconHex, contentXAMLObj, isBottom := false) {
        idx := this.pages.Length + 1
        pageId := this.id "_Page_" idx
        btnId := this.id "_Btn_" idx

        contentXAMLObj.Grid_Column(0).Grid_Row(0).Name(pageId).Visibility("Collapsed")
        contentXAMLObj._Parent := this.contentGrid
        this.contentGrid._Children.Push(contentXAMLObj)

        targetList := isBottom ? this.bottomList : this.topList
        btn := targetList.Add("RadioButton").Name(btnId).GroupName(this.id "_NavGroup").Margin("0,2").Cursor("Hand")

        btn.InjectResources('<Style TargetType="RadioButton"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{DynamicResource TextMain}"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton"><Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border x:Name="indicator" Width="3" Height="16" CornerRadius="1.5" Background="{DynamicResource Accent}" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="2,0,0,0" Opacity="0"/><ContentPresenter Grid.Column="1" Margin="12,10"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="#10FFFFFF"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="bg" Property="Background" Value="#1AFFFFFF"/><Setter TargetName="indicator" Property="Opacity" Value="1"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        sp := btn.Add("StackPanel").Orientation("Horizontal")
        sp.Add("TextBlock").Text(iconHex).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(16).VerticalAlignment("Center").Margin("0,0,15,0").Width("20").TextAlignment("Center")
        sp.Add("TextBlock").Text(title).VerticalAlignment("Center").FontSize(14)

        pageObj := { Title: title, PageId: pageId, BtnId: btnId }
        this.pages.Push(pageObj)

        if (idx == 1) {
            btn.IsChecked("True")
            contentXAMLObj.Visibility("Visible")
        }

        return pageObj
    }

    Bind(ui) {
        this.ui := ui
        for page in this.pages {
            ui.OnEvent(page.BtnId, "Checked", ObjBindMethod(this, "OnNavChange", page.PageId))
        }
    }

    OnNavChange(pageId, state, ctrl, event) {
        for page in this.pages {
            if (page.PageId == pageId)
                this.ui.Update(page.PageId, "Visibility", "Visible")
            else
                this.ui.Update(page.PageId, "Visibility", "Collapsed")
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("NavigationView", { Call: _NavigationView })
_NavigationView(this, name := "") {
    comp := XNavigationView(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; KANBAN BOARD
; ==============================================================================

class XKanbanBoard {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "Kanban_" XKanbanBoard.Count()
        this.columns := []
        this.ui := ""

        this.sv := parentXAML.Add("ScrollViewer").HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Disabled")
        this.boardSp := this.sv.Add("StackPanel").Orientation("Horizontal").Name(this.id)
    }

    AddColumn(title, accentColor := "#0078D7") {
        colIdx := this.columns.Length + 1
        colId := this.id "_Col_" colIdx
        addBtnId := this.id "_Add_" colIdx
        countId := this.id "_Count_" colIdx

        bdr := this.boardSp.Add("Border").Background("{DynamicResource SidebarColor}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("12").Width("280").Margin("0,0,12,0")
        grid := bdr.Add("Grid").Margin("14")
        grid.Rows("Auto", "*", "Auto")

        headerGrid := grid.Add("Grid").Grid_Row(0).Margin("0,0,0,14")
        headerGrid.Cols("Auto", "*", "Auto")
        headerGrid.Add("Border").Width("8").Height("8").CornerRadius("4").Background(accentColor).Margin("0,0,10,0").VerticalAlignment("Center")
        headerGrid.Add("TextBlock").Text(title).Grid_Column(1).FontWeight("SemiBold").FontSize("13").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center")
        countBdr := headerGrid.Add("Border").Grid_Column(2).Background("{DynamicResource DropdownBg}").CornerRadius("10").Padding("8,2")
        countBdr.Add("TextBlock").Name(countId).Text("0").Foreground("{DynamicResource TextSub}").FontSize("11")

        lb := grid.Add("ListBox").Name(colId).Grid_Row(1).Background("Transparent").BorderThickness("0").ScrollViewer_HorizontalScrollBarVisibility("Disabled").Padding("0").Foreground("{DynamicResource TextMain}")

        lb.InjectResources('<Style TargetType="ListBoxItem"><Setter Property="Margin" Value="0,0,0,6"/><Setter Property="Padding" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="bd" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="6" Padding="12,10" Cursor="Hand"><Border.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.2" Direction="270" Color="Black"/></Border.Effect><ContentPresenter TextElement.Foreground="{DynamicResource TextMain}"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="bd" Property="Background" Value="{DynamicResource ControlBg}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="' accentColor '"/><Setter TargetName="bd" Property="Background" Value="{DynamicResource ControlBg}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        ; Add Card button
        addBtn := grid.Add("Button").Name(addBtnId).Grid_Row(2).Margin("0,8,0,0").Background("Transparent").Foreground("{DynamicResource TextSub}").BorderThickness("0").Cursor("Hand").HorizontalAlignment("Stretch")
        addBtn.InjectResources('<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="Transparent" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="6" Padding="8,7"><TextBlock Text="+ Add Card" HorizontalAlignment="Center" Foreground="{DynamicResource TextSub}" FontSize="12"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource ControlBg}"/><Setter TargetName="bg" Property="BorderBrush" Value="' accentColor '"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        colObj := { Title: title, Id: colId, AddBtnId: addBtnId, CountId: countId, ListBox: lb, Data: [], Color: accentColor, Index: colIdx }
        this.columns.Push(colObj)
        return colObj
    }

    AddCard(colIndex, cardText) {
        if (colIndex > 0 && colIndex <= this.columns.Length) {
            col := this.columns[colIndex]
            col.ListBox.Add("ListBoxItem").Content(cardText)
            col.Data.Push(cardText)
        }
    }

    Bind(ui) {
        this.ui := ui
        for col in this.columns {
            ui.Track(col.Id)
            ui.OnEvent(col.Id, "SelectionChanged", ObjBindMethod(this, "OnCardSelected", col.Id))
            ui.OnEvent(col.AddBtnId, "Click", ObjBindMethod(this, "OnAddCard", A_Index))
            ui.OnEvent(col.Id, "ItemDropped", ObjBindMethod(this, "OnItemDropped", A_Index))
        }
        ; Delay count update to ensure WPF names are registered
        SetTimer(ObjBindMethod(this, "UpdateCounts"), -300)
    }

    UpdateCounts() {
        for col in this.columns {
            if (this.ui)
                this.ui.Update(col.CountId, "Text", String(col.Data.Length))
        }
    }

    OnCardSelected(colId, state, ctrl, event) {
        if !state.Has(colId)
            return
        this.selectedCard := state[colId]
        this.selectedCol := colId
        this.selectedColIdx := 0
        for col in this.columns {
            if (col.Id == colId) {
                this.selectedColIdx := A_Index
                break
            }
        }
    }

    OnAddCard(colIdx, state, ctrl, event) {
        col := this.columns[colIdx]
        ib := InputBox("Enter card text:", "Add Card to " col.Title, "w300 h130")
        if (ib.Result == "OK" && ib.Value != "") {
            this.ui.Update(col.Id, "AddItem", ib.Value)
            col.Data.Push(ib.Value)
            this.UpdateCounts()
        }
    }

    MoveSelectedTo(targetIdx) {
        if (!this.HasProp("selectedCard") || this.selectedCard == "" || !this.HasProp("selectedColIdx") || this.selectedColIdx == 0)
            return
        if (this.selectedColIdx == targetIdx)
            return
        cardText := this.selectedCard
        dstCol := this.columns[targetIdx]
        srcCol := this.columns[this.selectedColIdx]

        removed := false
        newData := []
        for item in srcCol.Data {
            if (!removed && item == cardText) {
                removed := true
                continue
            }
            newData.Push(item)
        }
        srcCol.Data := newData
        dstCol.Data.Push(cardText)

        this.ui.Update(srcCol.Id, "ClearItems", "")
        for item in srcCol.Data
            this.ui.Update(srcCol.Id, "AddItem", item)

        this.ui.Update(dstCol.Id, "ClearItems", "")
        for item in dstCol.Data
            this.ui.Update(dstCol.Id, "AddItem", item)

        this.selectedCard := ""
        this.selectedColIdx := 0
        this.UpdateCounts()
    }

    OnItemDropped(dstColIdx, state, ctrl, event) {
        if !state.Has("ItemDropped")
            return
        parts := StrSplit(state["ItemDropped"], "|", , 2)
        if (parts.Length < 2)
            return

        srcColId := parts[1]
        cardText := parts[2]

        srcColIdx := 0
        for col in this.columns {
            if (col.Id == srcColId) {
                srcColIdx := A_Index
                break
            }
        }

        if (srcColIdx == 0 || srcColIdx == dstColIdx)
            return

        srcCol := this.columns[srcColIdx]
        dstCol := this.columns[dstColIdx]

        ; Find the exact index to remove to avoid removing duplicates
        removed := false
        newData := []
        for item in srcCol.Data {
            if (!removed && item == cardText) {
                removed := true
                continue
            }
            newData.Push(item)
        }
        srcCol.Data := newData

        ; Add to destination data
        dstCol.Data.Push(cardText)

        ; Rebuild UI completely to ensure sync
        this.ui.Update(srcCol.Id, "ClearItems", "")
        for item in srcCol.Data
            this.ui.Update(srcCol.Id, "AddItem", item)

        this.ui.Update(dstCol.Id, "ClearItems", "")
        for item in dstCol.Data
            this.ui.Update(dstCol.Id, "AddItem", item)

        this.UpdateCounts()
    }

    EnableDrag(ui?) {
        if !IsSet(ui) {
            this._dragEnabled := true
            return this
        }
        for col in this.columns {
            ui.Update(col.Id, "EnableListBoxDragDrop", "")
        }
    }
    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("KanbanBoard", { Call: _KanbanBoard })
_KanbanBoard(this, name := "") {
    comp := XKanbanBoard(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}


; ==============================================================================
; NODE GRAPH / VISUAL SCRIPTER
; ==============================================================================

class XNodeGraph {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "NodeGraph_" XNodeGraph.Count()
        this.ui := ""
        this.nodes := []
        this.connections := []
        this.selectedNodes := Map()

        this.bdr := parentXAML.Add("Border").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("8").ClipToBounds("True")

        this.bdr.InjectResources('<DrawingBrush x:Key="GridPattern" Viewport="0,0,100,100" ViewportUnits="Absolute" TileMode="Tile"><DrawingBrush.Drawing><DrawingGroup><GeometryDrawing Brush="#01000000"><GeometryDrawing.Geometry><RectangleGeometry Rect="0,0,100,100"/></GeometryDrawing.Geometry></GeometryDrawing><GeometryDrawing Geometry="M0,20 L100,20 M0,40 L100,40 M0,60 L100,60 M0,80 L100,80 M20,0 L20,100 M40,0 L40,100 M60,0 L60,100 M80,0 L80,100"><GeometryDrawing.Pen><Pen Brush="{DynamicResource ControlBorder}" Thickness="0.3"/></GeometryDrawing.Pen></GeometryDrawing><GeometryDrawing Geometry="M0,100 L100,100 M100,0 L100,100"><GeometryDrawing.Pen><Pen Brush="{DynamicResource ControlBorder}" Thickness="1.5"/></GeometryDrawing.Pen></GeometryDrawing></DrawingGroup></DrawingBrush.Drawing></DrawingBrush>')

        cm := this.bdr.Add("FrameworkElement.ContextMenu").Add("ContextMenu").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).Foreground("{DynamicResource TextMain}")
        cm.Add("MenuItem").Name(this.id "_BtnNewNode").Header("Add Process Node")
        cm.Add("MenuItem").Name(this.id "_BtnNewInput").Header("Add Input Node")
        cm.Add("MenuItem").Name(this.id "_BtnNewOutput").Header("Add Output Node")
        cm.Add("MenuItem").Name(this.id "_BtnNewMultiProcess").Header("Add Multi-Port Process Node")

        this.offsetX := 10000
        this.offsetY := 10000
        this.canvas := this.bdr.Add("Canvas").Name(this.id).Background("Transparent").Width("20000").Height("20000").Margin("-" this.offsetX ",-" this.offsetY ",0,0")
        this.canvas.Add("Rectangle").Fill("{DynamicResource GridPattern}").Width("20000").Height("20000").IsHitTestVisible("False")
    }

    AddNode(id, title, x, y, nodeType := "Process") {
        x += this.offsetX
        y += this.offsetY
        node := this.canvas.Add("Border").Name("Node_" id).Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").Width("160").SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y))
        node.Add("Border.Effect").Add("DropShadowEffect").BlurRadius("8").ShadowDepth("2").Opacity("0.4").Direction("270").SetProp('Color', "Black")

        grid := node.Add("Grid")
        grid.Rows("30", "*")

        ; Color-coded header by type
        headerColor := nodeType == "Input" ? "#2E5A2E" : (nodeType == "Output" ? "#5A2E2E" : "#3E3E50")
        header := grid.Add("Border").Name(this.id "_Header_" id).Grid_Row(0).Cursor("SizeAll").Background(headerColor).CornerRadius("5,5,0,0")
        headerGrid := header.Add("Grid")
        headerGrid.Cols("*", "Auto")
        headerGrid.Add("TextBlock").Text(title).Foreground("White").FontWeight("Bold").FontSize("11").VerticalAlignment("Center").Margin("10,0")
        headerGrid.Add("TextBlock").Text(nodeType).Grid_Column(1).Foreground("#DDDDDD").FontSize("9").VerticalAlignment("Center").Margin("0,0,8,0")

        body := grid.Add("StackPanel").Grid_Row(1).Margin("10,6,10,8")
        bodyTb := body.Add("TextBlock").Foreground("#999").FontSize("10")
        if (nodeType == "Input") {
            bodyTb.Add("Run").Text(Chr(0xE8B5)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            bodyTb.Add("Run").Text("  Source")
        } else if (nodeType == "Output") {
            bodyTb.Add("Run").Text(Chr(0xE898)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            bodyTb.Add("Run").Text("  Sink")
        } else {
            bodyTb.Add("Run").Text(Chr(0xE943)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
            bodyTb.Add("Run").Text("  Transform")
        }

        ; Port indicators - Input port (left side)
        if (nodeType != "Input") {
            inPort := this.canvas.Add("Ellipse").Width("10").Height("10").Fill("#4CAF50").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x - 5)).SetProp("Canvas.Top", String(y + 30)).Name("Port_In_" id).IsHitTestVisible("True").Cursor("Hand")
        }
        ; Output port (right side)
        if (nodeType != "Output") {
            outPort := this.canvas.Add("Ellipse").Width("10").Height("10").Fill("#FF5722").Stroke("#333").StrokeThickness("1").SetProp("Canvas.Left", String(x + 155)).SetProp("Canvas.Top", String(y + 30)).Name("Port_Out_" id).IsHitTestVisible("True").Cursor("Hand")
        }

        nodeObj := { Id: id, Title: title, X: x, Y: y, UI: node, Body: body, W: 160, H: 60, Type: nodeType }
        this.nodes.Push(nodeObj)
        return nodeObj
    }

    GetNode(id) {
        for n in this.nodes {
            if (n.Id == id)
                return n
        }
        return ""
    }

    AddConnection(fromId, toId) {
        pathId := this.id "_Path_" fromId "_" toId

        ; Prevent duplicate links visually
        for conn in this.connections {
            if (conn.From == fromId && conn.To == toId) {
                if (this.ui) {
                    this.ui.Update(pathId, "Visibility", "Visible")
                    this.UpdatePath(fromId, toId, pathId)
                }
                return
            }
        }

        pathEl := this.canvas.Add("Path").Name(pathId).Stroke("#60A0FF").StrokeThickness("2.5").Opacity("0.8").SetProp("Panel.ZIndex", "5")
        conn := { From: fromId, To: toId, PathId: pathId, PathEl: pathEl, Selected: false }
        this.connections.Push(conn)

        if (this.ui) {
            ; UI is already loaded, we must push this new element to WPF dynamically
            xamlStr := pathEl.ToString()
            xamlStr := StrReplace(xamlStr, "<Path ", "<Path xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" ")
            this.ui.Update(this.id, "AddXamlItem", xamlStr)
            this.ui.Update(pathId, "Visibility", "Visible")
            this.UpdatePath(fromId, toId, pathId)
            this.ui.OnEvent(pathId, "MouseLeftButtonDown", ObjBindMethod(this, "OnPathClicked", pathId))
        } else {
            ; UI is building, just push the initial data directly
            this.UpdatePath(fromId, toId, pathId, true, pathEl)
        }
    }

    UpdatePath(fromId, toId, pathId, initial := false, pathEl := "") {
        n1 := this.GetNode(fromId)
        n2 := this.GetNode(toId)
        if (!n1 || !n2)
            return

        ; Connect from output port (right) to input port (left)
        startX := n1.X + n1.W + 5
        startY := n1.Y + 35
        endX := n2.X - 5
        endY := n2.Y + 35

        ; Bezier control point offset scales with distance
        dx := Abs(endX - startX) * 0.5
        if (dx < 40)
            dx := 40
        ctrl1X := startX + dx
        ctrl1Y := startY
        ctrl2X := endX - dx
        ctrl2Y := endY

        geom := Format("M{},{} C{},{} {},{} {},{}", startX, startY, ctrl1X, ctrl1Y, ctrl2X, ctrl2Y, endX, endY)
        if (initial && pathEl != "") {
            ; Set initial Data string on the Path element directly at XAML build time
            pathEl.SetProp("Data", geom)
        } else if (this.ui)
            this.ui.Update(pathId, "Data", geom)
    }

    Bind(ui) {
        this.ui := ui
        ui.OnEvent(this.id "_BtnNewNode", "Click", ObjBindMethod(this, "OnNewNode", "Process"))
        ui.OnEvent(this.id "_BtnNewInput", "Click", ObjBindMethod(this, "OnNewNode", "Input"))
        ui.OnEvent(this.id "_BtnNewOutput", "Click", ObjBindMethod(this, "OnNewNode", "Output"))
        ui.OnEvent(this.id "_BtnNewMultiProcess", "Click", ObjBindMethod(this, "OnNewNode", "MultiProcess"))

        ; Enable C#-side drag on each node border, listen for DragMove events
        for node in this.nodes {
            ui.OnEvent("Node_" node.Id, "DragMove", ObjBindMethod(this, "OnNodeMoved", node.Id))
            ui.OnEvent("Node_" node.Id, "SelectNode", ObjBindMethod(this, "OnSelectNode", node.Id))
            ui.OnEvent("Node_" node.Id, "CtrlSelectNode", ObjBindMethod(this, "OnCtrlSelectNode", node.Id))
        }

        ; Canvas events for Selection and Connection
        ui.OnEvent(this.id, "SelectionBox", ObjBindMethod(this, "OnSelectionBox"))
        ui.OnEvent(this.id, "CtrlSelectionBox", ObjBindMethod(this, "OnCtrlSelectionBox"))
        ui.OnEvent(this.id, "ClearSelection", ObjBindMethod(this, "OnClearSelection"))
        ui.OnEvent(this.id, "ConnectPorts", ObjBindMethod(this, "OnConnectPorts"))
        ui.OnEvent(this.id, "DeleteConnection", ObjBindMethod(this, "OnDeleteConnection"))
        ui.OnEvent(this.id, "ContextMenuOpened", ObjBindMethod(this, "OnContextMenuOpened"))

        ; Initial draw of connections
        for conn in this.connections
            this.UpdatePath(conn.From, conn.To, conn.PathId)
    }

    ; Called after UI is ready to enable drag on each node.
    ; Call with no args to flag for auto-enable during Compile().
    EnableDrag(ui?, snap := true) {
        if !IsSet(ui) {
            this._dragEnabled := true
            return this
        }
        ; Enable zoom and pan on the canvas
        ui.Update(this.id, "EnableZoomPan", "")
        mode := snap ? "grid=20" : ""
        for node in this.nodes {
            ui.Update("Node_" node.Id, "EnableDrag", mode)
        }
    }

    SetGridSnap(ui, enable) {
        mode := enable ? "grid=20" : ""
        for node in this.nodes {
            ui.Update("Node_" node.Id, "EnableDrag", mode)
        }
    }

    OnContextMenuOpened(state, ctrl, event) {
        if !state.Has("ContextMenuOpened")
            return
        parts := StrSplit(state["ContextMenuOpened"], ",")
        if (parts.Length == 2) {
            this.lastRightClickX := Number(parts[1])
            this.lastRightClickY := Number(parts[2])
        }
    }

    OnNewNode(nodeType, state, ctrl, event) {
        idx := this.nodes.Length + 1
        newId := this.id "_Node" idx
        headerBg := nodeType == "Input" ? "#2E5A2E" : (nodeType == "Output" ? "#5A2E2E" : (nodeType == "MultiProcess" ? "#8A2BE2" : "#3E3E50"))
        label := nodeType == "Input" ? "Source" : (nodeType == "Output" ? "Sink" : "Transform")

        x := this.HasProp("lastRightClickX") ? this.lastRightClickX : this.offsetX + 200
        y := this.HasProp("lastRightClickY") ? this.lastRightClickY : this.offsetY + 200

        ; Port visual logic
        inPortXAML := ""
        outPortXAML := ""
        if (nodeType != "Input") {
            if (nodeType == "MultiProcess") {
                inPortXAML := '<Ellipse Name="Port_In_' newId '" Width="10" Height="10" Fill="#4CAF50" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x - 5) '" Canvas.Top="' (y + 20) '" IsHitTestVisible="True" Cursor="Hand"/><Ellipse Name="Port_In2_' newId '" Width="10" Height="10" Fill="#4CAF50" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x - 5) '" Canvas.Top="' (y + 40) '" IsHitTestVisible="True" Cursor="Hand"/>'
            } else {
                inPortXAML := '<Ellipse Name="Port_In_' newId '" Width="10" Height="10" Fill="#4CAF50" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x - 5) '" Canvas.Top="' (y + 30) '" IsHitTestVisible="True" Cursor="Hand"/>'
            }
        }
        if (nodeType != "Output") {
            if (nodeType == "MultiProcess") {
                outPortXAML := '<Ellipse Name="Port_Out_' newId '" Width="10" Height="10" Fill="#FF5722" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x + 155) '" Canvas.Top="' (y + 20) '" IsHitTestVisible="True" Cursor="Hand"/><Ellipse Name="Port_Out2_' newId '" Width="10" Height="10" Fill="#FF5722" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x + 155) '" Canvas.Top="' (y + 40) '" IsHitTestVisible="True" Cursor="Hand"/>'
            } else {
                outPortXAML := '<Ellipse Name="Port_Out_' newId '" Width="10" Height="10" Fill="#FF5722" Stroke="#333" StrokeThickness="1" Canvas.Left="' (x + 155) '" Canvas.Top="' (y + 30) '" IsHitTestVisible="True" Cursor="Hand"/>'
            }
        }

        ; Build raw XAML string with proper namespace for injection
        xamlStr := '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="Node_' newId '" Background="{DynamicResource DropdownBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="6" Width="160" Canvas.Left="' x '" Canvas.Top="' y '"><Border.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="2" Opacity="0.4" Direction="270" Color="Black"/></Border.Effect><Grid><Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Grid.Row="0" Background="' headerBg '" CornerRadius="5,5,0,0" Cursor="SizeAll"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="' nodeType ' ' idx '" Foreground="White" FontWeight="Bold" FontSize="11" VerticalAlignment="Center" Margin="10,0"/><TextBlock Grid.Column="1" Text="' nodeType '" Foreground="#DDDDDD" FontSize="9" VerticalAlignment="Center" Margin="0,0,8,0"/></Grid></Border><StackPanel Grid.Row="1" Margin="10,6,10,8"><TextBlock Text="' label '" Foreground="{DynamicResource TextSub}" FontSize="10"/></StackPanel></Grid></Border>'
        this.ui.Update(this.id, "AddXamlItem", xamlStr)

        pos := 1
        while (pos := RegExMatch(inPortXAML, "<Ellipse.*?\/>", &match, pos)) {
            xml := StrReplace(match[0], "<Ellipse ", "<Ellipse xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" ")
            this.ui.Update(this.id, "AddXamlItem", xml)
            pos += match.Len
        }

        pos := 1
        while (pos := RegExMatch(outPortXAML, "<Ellipse.*?\/>", &match, pos)) {
            xml := StrReplace(match[0], "<Ellipse ", "<Ellipse xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" ")
            this.ui.Update(this.id, "AddXamlItem", xml)
            pos += match.Len
        }

        nodeObj := { Id: newId, Title: nodeType " " idx, X: x, Y: y, W: 160, H: 60, Type: nodeType }
        this.nodes.Push(nodeObj)

        SetTimer(() => this.ui.Update("Node_" newId, "EnableDrag", "grid=20"), -200)
        this.ui.OnEvent("Node_" newId, "DragMove", ObjBindMethod(this, "OnNodeMoved", newId))
        this.ui.OnEvent("Node_" newId, "SelectNode", ObjBindMethod(this, "OnSelectNode", newId))
        this.ui.OnEvent("Node_" newId, "CtrlSelectNode", ObjBindMethod(this, "OnCtrlSelectNode", newId))
    }

    OnNodeMoved(nodeId, state, ctrl, event) {
        if !state.Has("DragCoords")
            return
        parts := StrSplit(state["DragCoords"], ",")
        if (parts.Length >= 2) {
            node := this.GetNode(nodeId)
            if (node) {
                dx := Number(parts[1]) - node.X
                dy := Number(parts[2]) - node.Y

                ; If this node is part of a selection, move all selected nodes together
                if (this.selectedNodes.Has(nodeId)) {
                    for sid in this.selectedNodes {
                        snode := this.GetNode(sid)
                        if (snode && sid != nodeId) {
                            snode.X += dx
                            snode.Y += dy
                            this.ui.Update("Node_" sid, "SetPosition", String(snode.X) "," String(snode.Y))
                            this.UpdateNodePorts(snode)
                        }
                    }
                }

                node.X := Number(parts[1])
                node.Y := Number(parts[2])
                this.UpdateNodePorts(node)
            }
        }
    }

    UpdateNodePorts(node) {
        nodeId := node.Id
        ; Move port indicators
        if (node.Type != "Input") {
            if (node.Type == "MultiProcess") {
                this.ui.Update("Port_In_" nodeId, "SetPosition", String(node.X - 5) "," String(node.Y + 20))
                this.ui.Update("Port_In2_" nodeId, "SetPosition", String(node.X - 5) "," String(node.Y + 40))
            } else {
                this.ui.Update("Port_In_" nodeId, "SetPosition", String(node.X - 5) "," String(node.Y + 30))
            }
        }
        if (node.Type != "Output") {
            if (node.Type == "MultiProcess") {
                this.ui.Update("Port_Out_" nodeId, "SetPosition", String(node.X + 155) "," String(node.Y + 20))
                this.ui.Update("Port_Out2_" nodeId, "SetPosition", String(node.X + 155) "," String(node.Y + 40))
            } else {
                this.ui.Update("Port_Out_" nodeId, "SetPosition", String(node.X + 155) "," String(node.Y + 30))
            }
        }
        ; Update connection paths
        for conn in this.connections {
            if (conn.From == nodeId || conn.To == nodeId)
                this.UpdatePath(conn.From, conn.To, conn.PathId)
        }
    }

    OnSelectNode(nodeId, state, ctrl, event) {
        if (this.selectedNodes.Has(nodeId) && this.selectedNodes.Count > 1) {
            ; keep selection for dragging
            return
        }
        this.selectedNodes.Clear()
        for node in this.nodes
            this.ui.Update("Node_" node.Id, "BorderBrush", "{DynamicResource ControlBorder}")
        this.selectedNodes[nodeId] := true
        this.ui.Update("Node_" nodeId, "BorderBrush", "#60A0FF")
    }

    OnCtrlSelectNode(nodeId, state, ctrl, event) {
        if (this.selectedNodes.Has(nodeId)) {
            this.selectedNodes.Delete(nodeId)
            this.ui.Update("Node_" nodeId, "BorderBrush", "{DynamicResource ControlBorder}")
        } else {
            this.selectedNodes[nodeId] := true
            this.ui.Update("Node_" nodeId, "BorderBrush", "#60A0FF")
        }
    }

    OnSelectionBox(state, ctrl, event) {
        if !state.Has("SelectionBox")
            return
        selectedStr := state["SelectionBox"]
        this.selectedNodes.Clear()

        ; Reset all borders
        for node in this.nodes
            this.ui.Update("Node_" node.Id, "BorderBrush", "{DynamicResource ControlBorder}")

        ; Set highlighted borders
        if (selectedStr != "") {
            for selId in StrSplit(selectedStr, ",") {
                this.selectedNodes[selId] := true
                this.ui.Update("Node_" selId, "BorderBrush", "#60A0FF")
            }
        }
    }

    OnCtrlSelectionBox(state, ctrl, event) {
        if !state.Has("CtrlSelectionBox")
            return
        selectedStr := state["CtrlSelectionBox"]
        if (selectedStr != "") {
            for selId in StrSplit(selectedStr, ",") {
                this.selectedNodes[selId] := true
                this.ui.Update("Node_" selId, "BorderBrush", "#60A0FF")
            }
        }
    }

    OnDeleteConnection(state, ctrl, event) {
        if !state.Has("DeleteConnection")
            return
        pathId := state["DeleteConnection"]
        ; Remove from tracking and UI
        for i, conn in this.connections {
            if (conn.PathId == pathId) {
                this.connections.RemoveAt(i)
                this.ui.Update(pathId, "Visibility", "Collapsed")
                break
            }
        }
    }

    OnClearSelection(state, ctrl, event) {
        this.selectedNodes.Clear()
        for node in this.nodes
            this.ui.Update("Node_" node.Id, "BorderBrush", "{DynamicResource ControlBorder}")

        ; Clear connection path selections
        for conn in this.connections {
            if (conn.Selected) {
                conn.Selected := false
                this.ui.Update(conn.PathId, "Stroke", "#60A0FF")
            }
        }
    }

    OnConnectPorts(state, ctrl, event) {
        if !state.Has("ConnectPorts")
            return
        parts := StrSplit(state["ConnectPorts"], ",")
        if (parts.Length == 2) {
            ; Parse port names like Port_Out_Node1, Port_In_Node2
            fromPort := parts[1]
            toPort := parts[2]

            ; Ensure we are connecting an Out to an In
            if (InStr(fromPort, "Port_In") && InStr(toPort, "Port_Out")) {
                temp := fromPort
                fromPort := toPort
                toPort := temp
            }

            if (InStr(fromPort, "Port_Out") && InStr(toPort, "Port_In")) {
                fromId := RegExReplace(fromPort, "^Port_(Out|In)2?_", "")
                toId := RegExReplace(toPort, "^Port_(Out|In)2?_", "")

                if (fromId != toId) {
                    this.AddConnection(fromId, toId)
                    if (this.ui) {
                        pathId := this.id "_Path_" fromId "_" toId
                        this.ui.OnEvent(pathId, "MouseLeftButtonDown", ObjBindMethod(this, "OnPathClicked", pathId))
                    }
                }
            }
        }
    }

    OnPathClicked(pathId, state, ctrl, event) {
        for conn in this.connections {
            if (conn.PathId == pathId) {
                conn.Selected := true
                this.ui.Update(pathId, "Stroke", "White")
            } else {
                conn.Selected := false
                this.ui.Update(conn.PathId, "Stroke", "#60A0FF")
            }
        }
    }

    DeleteSelectedConnections() {
        newConns := []
        for conn in this.connections {
            if (conn.Selected) {
                this.ui.Update(conn.PathId, "Visibility", "Collapsed")
            } else {
                newConns.Push(conn)
            }
        }
        this.connections := newConns
    }

    SaveState(filename) {
        if FileExist(filename)
            FileDelete(filename)
        FileAppend("[Nodes]`n", filename)
        for node in this.nodes {
            FileAppend(node.Id "=" node.X "," node.Y "`n", filename)
        }
        FileAppend("`n[Links]`n", filename)
        for conn in this.connections {
            FileAppend(conn.From "->" conn.To "`n", filename)
        }
        MsgBox("Node graph state saved!", "Saved", "Iconi T2")
    }

    LoadState(filename, ui) {
        if !FileExist(filename) {
            MsgBox("No saved state found.", "Load Error", "Iconx")
            return
        }

        ; Mark all current connections as inactive
        for conn in this.connections {
            conn.Active := false
        }

        stateText := FileRead(filename)
        mode := "Nodes"

        Loop Parse, stateText, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line == "")
                continue
            if (SubStr(line, 1, 1) == "[" && SubStr(line, -1) == "]") {
                mode := SubStr(line, 2, StrLen(line) - 2)
                continue
            }

            if (mode == "Nodes" || mode == "") {
                parts := StrSplit(line, "=")
                if (parts.Length == 2) {
                    nodeId := Trim(parts[1])
                    coords := StrSplit(parts[2], ",")
                    if (coords.Length == 2) {
                        node := this.GetNode(nodeId)
                        if (node) {
                            node.X := Number(coords[1])
                            node.Y := Number(coords[2])
                            ui.Update("Node_" nodeId, "SetPosition", String(node.X) "," String(node.Y))
                            this.UpdateNodePorts(node)

                            ; Explicitly re-enable drag and attach events for restored nodes
                            ui.Update("Node_" nodeId, "EnableDrag", "grid=20")
                            ui.OnEvent("Node_" nodeId, "DragMove", ObjBindMethod(this, "OnNodeMoved", nodeId))
                            ui.OnEvent("Node_" nodeId, "SelectNode", ObjBindMethod(this, "OnSelectNode", nodeId))
                            ui.OnEvent("Node_" nodeId, "CtrlSelectNode", ObjBindMethod(this, "OnCtrlSelectNode", nodeId))
                        }
                    }
                }
            } else if (mode == "Links") {
                parts := StrSplit(line, "->")
                if (parts.Length == 2) {
                    fromId := Trim(parts[1])
                    toId := Trim(parts[2])
                    this.AddConnection(fromId, toId)

                    ; Ensure it's marked active
                    for conn in this.connections {
                        if (conn.From == fromId && conn.To == toId) {
                            conn.Active := true
                        }
                    }
                }
            }
        }

        ; Collapse inactive connections and clean up array
        newConns := []
        for conn in this.connections {
            if (conn.HasOwnProp("Active") && !conn.Active) {
                ui.Update(conn.PathId, "Visibility", "Collapsed")
            } else {
                newConns.Push(conn)
            }
        }
        this.connections := newConns
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("NodeGraph", { Call: _NodeGraph })
_NodeGraph(this, name := "") {
    comp := XNodeGraph(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}


; ==============================================================================
; MARKDOWN RENDERER
; ==============================================================================

XAMLElement.Prototype.DefineProp("MarkdownRenderer", { Call: _MarkdownRenderer })
_MarkdownRenderer(this, markdownText) {
    sp := this.Add("StackPanel")

    Loop Parse, markdownText, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line == "") {
            sp.Add("TextBlock").Height("10")
            continue
        }

        if (SubStr(line, 1, 3) == "###") {
            sp.Add("TextBlock").Text(Trim(SubStr(line, 4))).FontSize("16").FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,15,0,5")
        } else if (SubStr(line, 1, 2) == "##") {
            sp.Add("TextBlock").Text(Trim(SubStr(line, 3))).FontSize("20").FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,20,0,5")
        } else if (SubStr(line, 1, 1) == "#") {
            sp.Add("TextBlock").Text(Trim(SubStr(line, 2))).FontSize("26").FontWeight("Bold").Foreground("{DynamicResource TextMain}").Margin("0,25,0,10")
        } else if (SubStr(line, 1, 2) == "- ") {
            bull := sp.Add("StackPanel").Orientation("Horizontal").Margin("15,2,0,2")
            bull.Add("TextBlock").Text("•").Foreground("{DynamicResource Accent}").Margin("0,0,8,0")
            bull.Add("TextBlock").Text(Trim(SubStr(line, 3))).Foreground("{DynamicResource TextSub}").TextWrapping("Wrap")
        } else {
            if (InStr(line, "**")) {
                tb := sp.Add("TextBlock").TextWrapping("Wrap").Foreground("{DynamicResource TextSub}").Margin("0,0,0,10")
                parts := StrSplit(line, "**")
                for idx, part in parts {
                    if (Mod(idx, 2) == 0) {
                        tb.Add("Run").Text(part).FontWeight("Bold").Foreground("{DynamicResource TextMain}")
                    } else {
                        tb.Add("Run").Text(part)
                    }
                }
            } else {
                sp.Add("TextBlock").Text(line).TextWrapping("Wrap").Foreground("{DynamicResource TextSub}").Margin("0,0,0,10")
            }
        }
    }
    return sp
}


; ==============================================================================
; SPARKLINE
; ==============================================================================

XAMLElement.Prototype.DefineProp("Sparkline", { Call: _Sparkline })
_Sparkline(this, dataPoints, width := 100, height := 30, color := "#32D74B", type := "Line") {
    maxVal := -999999
    minVal := 999999
    for pt in dataPoints {
        if (pt > maxVal)
            maxVal := pt
        if (pt < minVal)
            minVal := pt
    }

    range := maxVal - minVal
    if (range == 0)
        range := 1

    count := dataPoints.Length

    if (type == "Bar") {
        cv := this.Add("Canvas").Width(String(width)).Height(String(height)).ClipToBounds("True")
        barW := (width / count) * 0.8
        for idx, pt in dataPoints {
            barH := ((pt - minVal) / range) * height
            if (barH < 1)
                barH := 1
            x := (idx - 1) * (width / count) + ((width / count) * 0.1)
            y := height - barH
            cv.Add("Border").Background(color).Width(String(barW)).Height(String(barH)).SetProp("Canvas.Left", String(x)).SetProp("Canvas.Top", String(y)).CornerRadius("2")
        }
        return cv
    }

    ptsStr := ""
    for idx, pt in dataPoints {
        x := (idx - 1) * (width / (count - 1))
        y := height - (((pt - minVal) / range) * height)
        ptsStr .= Round(x, 2) "," Round(y, 2) " "
    }

    if (type == "Area") {
        ptsStr := "0," height " " ptsStr " " width "," height
        return this.Add("Polygon").Points(Trim(ptsStr)).Fill(color).Opacity("0.5").Stroke(color).StrokeThickness("1").Width(String(width)).Height(String(height))
    }

    poly := this.Add("Polyline").Points(Trim(ptsStr)).Stroke(color).StrokeThickness("2").Width(String(width)).Height(String(height))
    return poly
}


; ==============================================================================
; MEDIA PLAYER WRAPPER
; ==============================================================================

class XMediaPlayerEx {
    __New(parentXAML, videoUri := "", name := "") {
        this.id := name != "" ? name : "Media_" XMediaPlayerEx.Count()

        this.grid := parentXAML.Add("Grid").Name(this.id "_MainGrid").Background("Black").ClipToBounds("True")

        this.media := this.grid.Add("MediaElement").Name(this.id).LoadedBehavior("Manual").UnloadedBehavior("Stop").Stretch("Uniform")
        if (videoUri != "")
            this.media.Source(videoUri)

        this.spinner := this.grid.Add("ProgressBar").Name(this.id "_Spinner").Style("{StaticResource ProgressRing}").Width("40").Height("40").IsIndeterminate("True").Visibility("Collapsed")

        ; No-media label
        this.grid.Add("TextBlock").Name(this.id "_NoMedia").Text("Drop or load media to play").Foreground("#666").FontSize("12").HorizontalAlignment("Center").VerticalAlignment("Center")

        this.controlsOverlay := this.grid.Add("Grid").VerticalAlignment("Bottom").Background("#CC000000").Height("60")
        this.controlsOverlay.Name(this.id "_Controls")

        this.controlsOverlay.Rows("*", "Auto")

        ; Timeline slider on top row
        this.timeline := this.controlsOverlay.Add("Slider").Name(this.id "_Timeline").Grid_Row(0).VerticalAlignment("Center").Margin("10,0").Maximum("100")

        ; Button row
        btnGrid := this.controlsOverlay.Add("Grid").Grid_Row(1).Margin("5,0,5,5")
        btnGrid.Cols("Auto", "Auto", "Auto", "Auto", "*", "Auto", "80")

        this.btnPlay := btnGrid.Add("Button").Name(this.id "_BtnPlay").Grid_Column(0).Background("Transparent").Foreground("White").BorderThickness("0").Cursor("Hand").Width("30").Height("30")
        this.btnPlay.Add("TextBlock").Text(Chr(0xE768)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("14").VerticalAlignment("Center").HorizontalAlignment("Center")

        btnStop := btnGrid.Add("Button").Name(this.id "_BtnStop").Grid_Column(1).Background("Transparent").Foreground("White").BorderThickness("0").Cursor("Hand").Width("30").Height("30")
        btnStop.Add("TextBlock").Text(Chr(0xE71A)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").VerticalAlignment("Center").HorizontalAlignment("Center")

        this.btnLoad := btnGrid.Add("Button").Name(this.id "_BtnLoad").Grid_Column(2).Background("Transparent").Foreground("White").BorderThickness("0").Cursor("Hand").Width("30").Height("30").ToolTip("Load File")
        this.btnLoad.Add("TextBlock").Text(Chr(0xE8E5)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").VerticalAlignment("Center").HorizontalAlignment("Center")

        btnUrl := btnGrid.Add("Button").Name(this.id "_BtnUrl").Grid_Column(3).Background("Transparent").Foreground("White").BorderThickness("0").Cursor("Hand").Width("30").Height("30").ToolTip("Open URL")
        btnUrl.Add("TextBlock").Text(Chr(0xE774)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("12").VerticalAlignment("Center").HorizontalAlignment("Center")

        ; Volume
        volSp := btnGrid.Add("StackPanel").Orientation("Horizontal").Grid_Column(5).VerticalAlignment("Center")
        volSp.Add("TextBlock").Text(Chr(0xE767)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("White").VerticalAlignment("Center").Margin("0,0,5,0").FontSize("12")
        this.volume := volSp.Add("Slider").Name(this.id "_Volume").Width("60").Value("50").Maximum("100")
    }

    Bind(ui) {
        this.ui := ui
        this.isPlaying := false
        ui.OnEvent(this.id "_BtnPlay", "Click", ObjBindMethod(this, "TogglePlay"))
        ui.OnEvent(this.id "_BtnStop", "Click", ObjBindMethod(this, "StopMedia"))
        ui.OnEvent(this.id "_BtnLoad", "Click", ObjBindMethod(this, "LoadMedia"))
        ui.OnEvent(this.id "_BtnUrl", "Click", ObjBindMethod(this, "LoadUrl"))
        ui.OnEvent(this.id "_Volume", "ValueChanged", ObjBindMethod(this, "ChangeVolume"))
        ; NOTE: Timeline seeking is handled entirely in C# via StartPositionTimer to avoid IPC loops
    }

    ChangeVolume(state, ctrl, event) {
        if state.Has(this.id "_Volume") {
            vol := Number(state[this.id "_Volume"]) / 100
            this.ui.Update(this.id, "Volume", String(vol))
        }
    }

    StartPlaying(source) {
        this.ui.Update(this.id "_Spinner", "Visibility", "Visible")
        this.ui.Update(this.id "_NoMedia", "Visibility", "Collapsed")
        this.ui.Update(this.id, "Source", source)
        this.ui.Update(this.id, "Play", "")
        ; Start position tracking timer on C# side
        this.ui.Update(this.id, "StartPositionTimer", this.id "_Timeline")
        this.isPlaying := true
        this.ui.Update(this.id "_BtnPlay", "Content", Chr(0xE769))
        SetTimer(() => this.ui.Update(this.id "_Spinner", "Visibility", "Collapsed"), -2000)
    }

    LoadMedia(state, ctrl, event) {
        file := FileSelect(3, "", "Select Media", "Media Files (*.mp4; *.avi; *.mkv; *.wmv; *.webm; *.mp3; *.wav; *.flac)")
        if (file)
            this.StartPlaying(file)
    }

    LoadUrl(state, ctrl, event) {
        ib := InputBox("Enter media URL (http/https/rtsp):", "Open URL Stream", "w400 h130")
        if (ib.Result == "OK" && ib.Value != "")
            this.StartPlaying(ib.Value)
    }

    TogglePlay(state, ctrl, event) {
        this.isPlaying := !this.isPlaying
        if (this.isPlaying) {
            this.ui.Update(this.id, "Play", "")
            this.ui.Update(this.id "_BtnPlay", "Content", Chr(0xE769))
        } else {
            this.ui.Update(this.id, "Pause", "")
            this.ui.Update(this.id "_BtnPlay", "Content", Chr(0xE768))
        }
    }

    StopMedia(state, ctrl, event) {
        this.ui.Update(this.id, "Stop", "")
        this.isPlaying := false
        this.ui.Update(this.id "_BtnPlay", "Content", Chr(0xE768))
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("MediaPlayerEx", { Call: _MediaPlayerEx })
_MediaPlayerEx(this, videoUri := "", name := "") {
    comp := XMediaPlayerEx(this, videoUri, name)
    _AutoRegisterComponent(this, comp)
    return comp
}


; ==============================================================================
; IMAGE CROPPER
; ==============================================================================

class XImageCropper {
    __New(parentXAML, imageUri := "", name := "") {
        this.id := name != "" ? name : "Cropper_" XImageCropper.Count()

        this.grid := parentXAML.Add("Grid").ClipToBounds("True")

        this.img := this.grid.Add("Image").Name(this.id "_Img").Stretch("Uniform")
        if (imageUri != "")
            this.img.Source(imageUri)

        ; Semi-transparent overlay
        this.grid.Add("Border").Name(this.id "_Overlay").Background("#80000000").IsHitTestVisible("False")

        ; Crop selection canvas
        this.canvas := this.grid.Add("Canvas").Name(this.id "_Canvas").Background("Transparent").ClipToBounds("True")

        ; Crop box (draggable via C# EnableDrag)
        this.cropBox := this.canvas.Add("Border").Name(this.id "_Box").BorderBrush("{DynamicResource Accent}").BorderThickness("2").Background("#01FFFFFF").Width("150").Height("150").SetProp("Canvas.Left", "30").SetProp("Canvas.Top", "20").Cursor("SizeAll")

        ; Corner handles
        cropGrid := this.cropBox.Add("Grid")
        this.hNW := cropGrid.Add("Border").Name(this.id "_HNW").Width("12").Height("12").Background("White").HorizontalAlignment("Left").VerticalAlignment("Top").Margin("-6,-6,0,0").Cursor("SizeNWSE").CornerRadius("6")
        this.hSE := cropGrid.Add("Border").Name(this.id "_HSE").Width("12").Height("12").Background("White").HorizontalAlignment("Right").VerticalAlignment("Bottom").Margin("0,0,-6,-6").Cursor("SizeNWSE").CornerRadius("6")

        ; Load button overlay
        loadBtn := this.canvas.Add("Button").Name(this.id "_BtnLoad").Content("Load Image").SetProp("Canvas.Left", "75").SetProp("Canvas.Top", "85").Background("{DynamicResource ControlBg}").Foreground("{DynamicResource TextMain}").Padding("10,5").Cursor("Hand").BorderThickness("1").BorderBrush("{DynamicResource ControlBorder}")
    }

    Bind(ui) {
        this.ui := ui
        ; Enable C#-side drag on the crop box
        ui.OnEvent(this.id "_Box", "DragMove", ObjBindMethod(this, "OnBoxMoved"))
        ui.OnEvent(this.id "_BtnLoad", "Click", ObjBindMethod(this, "OnLoadImage"))
    }

    ; Called after Window is Loaded to enable drag + resize.
    ; Call with no args to flag for auto-enable during Compile().
    EnableDrag(ui?) {
        if !IsSet(ui) {
            this._dragEnabled := true
            return this
        }
        ui.Update(this.id "_Box", "EnableDrag", "crop")
    }

    OnBoxMoved(state, ctrl, event) {
        ; DragMove sends coordinates; we just let C# handle the visual
    }

    OnLoadImage(state, ctrl, event) {
        file := FileSelect(3, "", "Select Image", "Image Files (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
        if (file) {
            this.ui.Update(this.id "_Img", "Source", file)
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("ImageCropper", { Call: _ImageCropper })
_ImageCropper(this, imageUri := "", name := "") {
    comp := XImageCropper(this, imageUri, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; WEB VIEWER
; ==============================================================================

class XWebViewer {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "WebViewer_" XWebViewer.Count()

        this.bgColor := "transparent"
        this.gridType := "None"
        this.currentFile := ""

        this.grid := parentXAML.Add("Grid").ClipToBounds("True")

        this.bdr := this.grid.Add("Border").Background("{DynamicResource DropdownBg}").BorderThickness("1").BorderBrush("{DynamicResource ControlBorder}").CornerRadius("8").ClipToBounds("True")

        this.innerGrid := this.bdr.Add("Grid")

        this.browser := this.innerGrid.Add("WebBrowser").Name(this.id).Visibility("Collapsed")

        this.dropZone := this.innerGrid.Add("Border").Name(this.id "_Drop").Background("Transparent").AllowDrop("True").Cursor("Hand")

        this.sp := this.dropZone.Add("StackPanel").VerticalAlignment("Center").HorizontalAlignment("Center").IsHitTestVisible("False")
        this.sp.Add("TextBlock").Text(Chr(0xEB9F)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("48").Foreground("{DynamicResource Accent}").HorizontalAlignment("Center").Margin("0,0,0,10")
        this.sp.Add("TextBlock").Name(this.id "_DropText").Text("Drag & Drop or Click to Load (SVG, HTML, PDF, Images)").Foreground("{DynamicResource TextSub}").FontSize("14").HorizontalAlignment("Center")

        this.fileCache := Map()
    }

    Bind(ui) {
        this.ui := ui
        ui.OnEvent(this.id "_Drop", "Drop", ObjBindMethod(this, "OnDrop"))
        ui.OnEvent(this.id "_Drop", "MouseLeftButtonDown", ObjBindMethod(this, "OnClick"))
    }

    OnClick(state, ctrl, event) {
        file := FileSelect(3, "", "Select File", "Web/Image Files (*.svg; *.html; *.htm; *.pdf; *.jpg; *.png; *.gif)")
        if (file) {
            this.LoadFile(file)
        }
    }

    _B64Decode(str) {
        DllCall("crypt32\CryptStringToBinary", "str", str, "uint", 0, "uint", 1, "ptr", 0, "uint*", &size := 0, "ptr", 0, "ptr", 0)
        buf := Buffer(size)
        DllCall("crypt32\CryptStringToBinary", "str", str, "uint", 0, "uint", 1, "ptr", buf, "uint*", &size, "ptr", 0, "ptr", 0)
        return StrGet(buf, "UTF-8")
    }

    _B64Encode(str) {
        buf := Buffer(StrPut(str, "UTF-8"))
        StrPut(str, buf, "UTF-8")
        size := buf.Size - 1 ; exclude null terminator
        DllCall("crypt32\CryptBinaryToString", "ptr", buf, "uint", size, "uint", 0x40000001, "ptr", 0, "uint*", &req := 0) ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
        strBuf := Buffer(req * 2)
        DllCall("crypt32\CryptBinaryToString", "ptr", buf, "uint", size, "uint", 0x40000001, "ptr", strBuf, "uint*", &req)
        return StrGet(strBuf, "UTF-16")
    }

    OnDrop(state, ctrl, event) {
        if !state.Has("Drop")
            return

        fileList := this._B64Decode(state["Drop"])
        files := StrSplit(fileList, "|")
        if (files.Length == 0)
            return

        file := files[1]
        SplitPath(file, , , &ext)
        if !(ext ~= "i)^(svg|html|htm|pdf|jpg|jpeg|png|gif)$") {
            MsgBox("Please drop a valid web or image file.", "Invalid File", "Iconx")
            return
        }

        this.LoadFile(file)
    }

    LoadFile(file) {
        this.currentFile := file
        this.ui.Update(this.id "_Drop", "Visibility", "Collapsed")
        this.ui.Update(this.id, "Visibility", "Visible")
        this.ui.Update("BtnWebReplace", "Visibility", "Visible")

        SplitPath(file, , , &ext)
        if (StrLower(ext) == "svg") {
            if (!this.fileCache.Has(file)) {
                svgContent := FileRead(file, "UTF-8")
                this.fileCache[file] := svgContent
            }
            this.Render()
        } else {
            ; Just navigate directly
            this.ui.Update(this.id, "Source", "file:///" StrReplace(file, "\", "/"))
        }
    }

    SetBackground(color, baseColor := "") {
        cssColor := color
        if (StrLen(color) == 9) {
            a := Format("{:i}", "0x" SubStr(color, 2, 2)) / 255
            r := Format("{:i}", "0x" SubStr(color, 4, 2))
            g := Format("{:i}", "0x" SubStr(color, 6, 2))
            b := Format("{:i}", "0x" SubStr(color, 8, 2))
            cssColor := "rgba(" r "," g "," b "," a ")"
        }
        this.bgColor := cssColor
        if (baseColor != "")
            this.baseColor := baseColor
        if (this.currentFile != "")
            this.Render()
    }

    SetGrid(type) {
        this.gridType := type
        if (this.currentFile != "")
            this.Render()
    }

    Render() {
        if (this.currentFile == "")
            return

        SplitPath(this.currentFile, , , &ext)
        if (StrLower(ext) != "svg")
            return

        svgContent := this.fileCache[this.currentFile]

        bgBase := this.HasProp("baseColor") && this.baseColor != "" ? this.baseColor : "#1E1E1E"
        bgStyle := "background-color: " bgBase ";"

        bgImg := ""
        bgSize := ""

        if (this.gridType == "Light") {
            bgImg .= "linear-gradient(to right, rgba(0,0,0,0.1) 1px, transparent 1px), linear-gradient(to bottom, rgba(0,0,0,0.1) 1px, transparent 1px), "
            bgSize .= "20px 20px, 20px 20px, "
        } else if (this.gridType == "Dark") {
            bgImg .= "linear-gradient(to right, rgba(255,255,255,0.15) 1px, transparent 1px), linear-gradient(to bottom, rgba(255,255,255,0.15) 1px, transparent 1px), "
            bgSize .= "20px 20px, 20px 20px, "
        }

        bgImg .= "linear-gradient(" this.bgColor ", " this.bgColor ")"
        bgSize .= "auto"

        bgStyle .= " background-image: " bgImg "; background-size: " bgSize ";"

        html := "<!DOCTYPE html><html><head><meta http-equiv='X-UA-Compatible' content='IE=edge'/><style>body { margin: 0; overflow: hidden; display: flex; align-items: center; justify-content: center; height: 100vh; " bgStyle " } svg { max-width: 100%; max-height: 100%; }</style></head><body>" svgContent "</body></html>"

        b64Html := this._B64Encode(html)
        this.ui.Update(this.id, "NavigateToString", b64Html)
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("WebViewer", { Call: _WebViewer })
_WebViewer(this, name := "") {
    comp := XWebViewer(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; IMAGE VIEWER
; ==============================================================================

class XImageViewer {
    __New(parentXAML, name := "") {
        this.parent := parentXAML
        this.id := name != "" ? name : "ImgViewer_" XImageViewer.Count()

        this.grid := parentXAML.Add("Grid").ClipToBounds("True")
        this.bdr := this.grid.Add("Border").Background("{DynamicResource DropdownBg}").BorderThickness("1").BorderBrush("{DynamicResource ControlBorder}").CornerRadius("8").ClipToBounds("True")

        this.innerGrid := this.bdr.Add("Grid")

        ; Checkerboard background for transparency
        this.innerGrid.InjectResources('<DrawingBrush x:Key="Checkerboard" Viewport="0,0,20,20" ViewportUnits="Absolute" TileMode="Tile"><DrawingBrush.Drawing><DrawingGroup><GeometryDrawing Brush="#1AFFFFFF"><GeometryDrawing.Geometry><GeometryGroup><RectangleGeometry Rect="0,0,10,10"/><RectangleGeometry Rect="10,10,10,10"/></GeometryGroup></GeometryDrawing.Geometry></GeometryDrawing><GeometryDrawing Brush="#00FFFFFF"><GeometryDrawing.Geometry><GeometryGroup><RectangleGeometry Rect="10,0,10,10"/><RectangleGeometry Rect="0,10,10,10"/></GeometryGroup></GeometryDrawing.Geometry></GeometryDrawing></DrawingGroup></DrawingBrush.Drawing></DrawingBrush>')

        this.checkerBg := this.innerGrid.Add("Border").Background("{DynamicResource Checkerboard}")

        this.img := this.innerGrid.Add("Image").Name(this.id).Stretch("Uniform").Visibility("Collapsed")

        this.dropZone := this.innerGrid.Add("Border").Name(this.id "_Drop").Background("Transparent").AllowDrop("True").Cursor("Hand")

        this.sp := this.dropZone.Add("StackPanel").VerticalAlignment("Center").HorizontalAlignment("Center").IsHitTestVisible("False")
        this.sp.Add("TextBlock").Text(Chr(0xEB9F)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("48").Foreground("{DynamicResource Accent}").HorizontalAlignment("Center").Margin("0,0,0,10")
        this.sp.Add("TextBlock").Name(this.id "_DropText").Text("Drag & Drop or Click to Load Image").Foreground("{DynamicResource TextSub}").FontSize("14").HorizontalAlignment("Center")
    }

    Bind(ui) {
        this.ui := ui
        ui.OnEvent(this.id "_Drop", "Drop", ObjBindMethod(this, "OnDrop"))
        ui.OnEvent(this.id "_Drop", "MouseLeftButtonDown", ObjBindMethod(this, "OnClick"))
    }

    OnClick(state, ctrl, event) {
        file := FileSelect(3, "", "Select Image", "Image Files (*.jpg; *.jpeg; *.png; *.webp; *.gif; *.bmp)")
        if (file) {
            this.LoadImage(file)
        }
    }

    _B64Decode(str) {
        DllCall("crypt32\CryptStringToBinary", "str", str, "uint", 0, "uint", 1, "ptr", 0, "uint*", &size := 0, "ptr", 0, "ptr", 0)
        buf := Buffer(size)
        DllCall("crypt32\CryptStringToBinary", "str", str, "uint", 0, "uint", 1, "ptr", buf, "uint*", &size, "ptr", 0, "ptr", 0)
        return StrGet(buf, "UTF-8")
    }

    OnDrop(state, ctrl, event) {
        if !state.Has("Drop")
            return

        fileList := this._B64Decode(state["Drop"])
        files := StrSplit(fileList, "|")
        if (files.Length == 0)
            return

        file := files[1]
        SplitPath(file, , , &ext)
        if !(ext ~= "i)^(jpg|jpeg|png|webp|gif|bmp|ico)$") {
            MsgBox("Please drop a valid image file.", "Invalid File", "Iconx")
            return
        }

        this.LoadImage(file)
    }

    LoadImage(file) {
        this.ui.Update(this.id "_Drop", "Visibility", "Collapsed")
        this.ui.Update(this.id, "Visibility", "Visible")
        this.ui.Update("BtnImgReplace", "Visibility", "Visible")
        if (SubStr(file, 1, 6) == "HICON:") {
            this.ui.Update(this.id, "Source", file)
        } else {
            this.ui.Update(this.id, "Source", "file:///" StrReplace(file, "\", "/"))
        }
    }


    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("ImageViewer", { Call: _ImageViewer })
_ImageViewer(this, name := "") {
    comp := XImageViewer(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; XClock Component
; ==============================================================================

class XClock {
    lastTickTime := ""

    __New(parentXAML, name := "") {
        this.parent := parentXAML
        this.id := name != "" ? name : "Clock_" XClock.Count()

        this.isEditMode := false
        this.isVisible := false ; Default to false on startup (starts on page 1)
        this.timerFn := ObjBindMethod(this, "Tick")

        ; Main glassmorphic container
        this.grid := parentXAML.Add("Grid").Name(this.id "_Grid").Margin("0")
        this.grid.ClipToBounds("True")

        ; Background glow effect
        glowCanvas := this.grid.Add("Canvas")
        glowCanvas.Add("Ellipse").Width("300").Height("300").Fill("{DynamicResource Accent}").Opacity("0.1").Margin("-50,-50,0,0").Add("Ellipse.Effect").Add("BlurEffect").SetProp('Radius', "80")

        ; Main Card
        card := this.grid.Add("Border").Use("CardPanel").Padding("30").Background("#10FFFFFF")

        this.contentGrid := card.Add("Grid")

        ; Live Mode UI
        this.liveUi := this.contentGrid.Add("StackPanel").Name(this.id "_LiveUI").Orientation("Horizontal").HorizontalAlignment("Center").VerticalAlignment("Center")

        this.hourTxt := this.liveUi.Add("TextBlock").Name(this.id "_Hour").Text("00").FontSize("72").FontWeight("Light").Foreground("{DynamicResource TextMain}")
        this.liveUi.Add("TextBlock").Text(":").FontSize("72").FontWeight("Light").Foreground("{DynamicResource Accent}").Margin("5,-5,5,0")
        this.minTxt := this.liveUi.Add("TextBlock").Name(this.id "_Min").Text("00").FontSize("72").FontWeight("Light").Foreground("{DynamicResource TextMain}")
        this.liveUi.Add("TextBlock").Text(":").FontSize("72").FontWeight("Light").Foreground("{DynamicResource Accent}").Margin("5,-5,5,0").Opacity("0.5")
        this.secTxt := this.liveUi.Add("TextBlock").Name(this.id "_Sec").Text("00").FontSize("72").FontWeight("Light").Foreground("{DynamicResource TextSub}")

        this.amPmTxt := this.liveUi.Add("TextBlock").Name(this.id "_AmPm").Text("AM").FontSize("24").FontWeight("Bold").Foreground("{DynamicResource TextSub}").VerticalAlignment("Bottom").Margin("15,0,0,15")

        ; Edit Mode UI
        this.editUi := this.contentGrid.Add("Grid").Name(this.id "_EditUI").Visibility("Collapsed").HorizontalAlignment("Center").VerticalAlignment("Center")
        this.editUi.Cols("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto")

        this.hourCombo := this.editUi.Add("ComboBox").Name(this.id "_HourEdit").Width("80").Height("60").FontSize("32").Grid_Column(0).VerticalAlignment("Center")
        Loop 12
            this.hourCombo.Add("ComboBoxItem").Content(Format("{:02}", A_Index))

        this.editUi.Add("TextBlock").Text(":").FontSize("48").FontWeight("Light").Foreground("{DynamicResource TextSub}").Margin("10,0,10,0").Grid_Column(1).VerticalAlignment("Center")

        this.minCombo := this.editUi.Add("ComboBox").Name(this.id "_MinEdit").Width("80").Height("60").FontSize("32").Grid_Column(2).VerticalAlignment("Center")
        Loop 60
            this.minCombo.Add("ComboBoxItem").Content(Format("{:02}", A_Index - 1))

        this.editUi.Add("TextBlock").Text(":").FontSize("48").FontWeight("Light").Foreground("{DynamicResource TextSub}").Margin("10,0,10,0").Grid_Column(3).VerticalAlignment("Center")

        this.secCombo := this.editUi.Add("ComboBox").Name(this.id "_SecEdit").Width("80").Height("60").FontSize("32").Grid_Column(4).VerticalAlignment("Center")
        Loop 60
            this.secCombo.Add("ComboBoxItem").Content(Format("{:02}", A_Index - 1))

        this.amPmCombo := this.editUi.Add("ComboBox").Name(this.id "_AmPmEdit").Width("80").Height("60").FontSize("24").Margin("20,0,0,0").Grid_Column(5).VerticalAlignment("Center")
        this.amPmCombo.Add("ComboBoxItem").Content("AM")
        this.amPmCombo.Add("ComboBoxItem").Content("PM")
    }

    Bind(ui) {
        this.ui := ui
        ui.Track(this.id "_HourEdit")
        ui.Track(this.id "_MinEdit")
        ui.Track(this.id "_SecEdit")
        ui.Track(this.id "_AmPmEdit")
        ui.OnEvent(this.id "_Grid", "IsVisibleChanged", ObjBindMethod(this, "OnVisibilityChanged"))
        ui.OnEvent("Window", "Activated", ObjBindMethod(this, "OnWindowActivated"))
        ui.OnEvent("Window", "Deactivated", ObjBindMethod(this, "OnWindowDeactivated"))
        ui.OnEvent("Window", "StateChanged", ObjBindMethod(this, "OnWindowStateChanged"))
    }

    OnVisibilityChanged(state, ctrl, event) {
        if (state.Has("IsVisibleChanged")) {
            this.isVisible := (state["IsVisibleChanged"] == "True")
        } else {
            try {
                val := this.ui.Query(this.id "_Grid>IsVisible")
                this.isVisible := (val == "True")
            } catch {
                return
            }
        }

        if (this.isVisible && !this.IsWindowMinimized() && WinActive("ahk_id " this.ui.wpfHwnd)) {
            this.Start()
        } else {
            this.Stop()
        }
    }

    IsWindowMinimized() {
        if (!this.ui || !this.ui.wpfHwnd)
            return false
        try {
            return WinGetMinMax("ahk_id " this.ui.wpfHwnd) == -1
        }
        return false
    }

    OnWindowActivated(state, ctrl, event) {
        if (this.isVisible && !this.IsWindowMinimized()) {
            this.Start()
        }
    }

    OnWindowDeactivated(state, ctrl, event) {
        this.Stop()
    }

    OnWindowStateChanged(state, ctrl, event) {
        ws := state.Has("StateChanged") ? state["StateChanged"] : ""
        if (ws == "Minimized") {
            this.Stop()
        } else if (this.isVisible && WinActive("ahk_id " this.ui.wpfHwnd)) {
            this.Start()
        }
    }

    Start() {
        if (!this.isVisible)
            return
        if (this.lastTickTime != "")
            return
        SetTimer(this.timerFn, 1000)
        this.lastTickTime := A_TickCount
        this.Tick()
    }

    Stop() {
        SetTimer(this.timerFn, 0)
        this.lastTickTime := ""
    }

    Tick() {
        if (this.isEditMode)
            return

        ; 1. Suspend updates if host window is minimized or not active (e.g. clicked to another window)
        if (!WinExist("ahk_id " this.ui.wpfHwnd) || !WinActive("ahk_id " this.ui.wpfHwnd))
            return

        ; 2. Double-check visibility local flag to prevent illegal ticks
        if (!this.isVisible)
            return

        timeStr := ""
        if (this.HasProp("baseTime") && this.baseTime != "") {
            elapsed := 1
            if (this.HasProp("lastTickTime") && this.lastTickTime != "") {
                elapsed := Round((A_TickCount - this.lastTickTime) / 1000)
                if (elapsed <= 0)
                    elapsed := 1
            }
            this.baseTime := DateAdd(this.baseTime, elapsed, "Seconds")
            timeStr := FormatTime(this.baseTime, "h:mm:ss:tt")
        } else {
            timeStr := FormatTime(, "h:mm:ss:tt")
        }
        this.lastTickTime := A_TickCount

        parts := StrSplit(timeStr, ":")

        this.ui.Update(this.id "_Hour", "Text", Format("{:02}", parts[1]))
        this.ui.Update(this.id "_Min", "Text", parts[2])
        this.ui.Update(this.id "_Sec", "Text", parts[3])
        this.ui.Update(this.id "_AmPm", "Text", parts[4])
    }

    SetEditMode(enable, state := "") {
        this.isEditMode := enable
        if (enable) {
            this.Stop()
            this.ui.Update(this.id "_LiveUI", "Visibility", "Collapsed")
            this.ui.Update(this.id "_EditUI", "Visibility", "Visible")

            timeStr := ""
            if (this.HasProp("baseTime") && this.baseTime != "")
                timeStr := FormatTime(this.baseTime, "h:mm:ss:tt")
            else
                timeStr := FormatTime(, "h:mm:ss:tt")

            parts := StrSplit(timeStr, ":")
            this.ui.Update(this.id "_HourEdit", "SelectedIndex", String(parts[1] - 1))
            this.ui.Update(this.id "_MinEdit", "SelectedIndex", String(parts[2]))
            this.ui.Update(this.id "_SecEdit", "SelectedIndex", String(parts[3]))
            this.ui.Update(this.id "_AmPmEdit", "SelectedIndex", parts[4] == "AM" ? "0" : "1")
        } else {
            if (state != "" && state.Has(this.id "_HourEdit")) {
                hStr := state[this.id "_HourEdit"]
                mStr := state[this.id "_MinEdit"]
                sStr := state[this.id "_SecEdit"]
                ap := state[this.id "_AmPmEdit"]

                if (hStr != "" && mStr != "" && sStr != "" && ap != "") {
                    h := Integer(hStr)
                    m := Integer(mStr)
                    s := Integer(sStr)

                    ; Convert to 24h format for AHK timestamp
                    h24 := h
                    if (ap == "PM" && h24 < 12)
                        h24 += 12
                    if (ap == "AM" && h24 == 12)
                        h24 := 0

                    curDate := FormatTime(, "yyyyMMdd")
                    this.baseTime := curDate Format("{:02}{:02}{:02}", h24, m, s)
                }
            }

            this.ui.Update(this.id "_EditUI", "Visibility", "Collapsed")
            this.ui.Update(this.id "_LiveUI", "Visibility", "Visible")
            this.Start()
        }
    }


    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("Clock", { Call: _Clock })
_Clock(this, name := "") {
    comp := XClock(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; CODE EDITOR (Layered Syntax Highlighter)
; ==============================================================================

class XCodeEditor {
    static Count := 0

    __New(parentXAML, initialCode := "") {
        XCodeEditor.Count++
        this.id := "CodeEditor_" XCodeEditor.Count
        this.parent := parentXAML

        ; Main container
        this.bdr := parentXAML.Add("Border").Name(this.id "_Bdr").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).Background("{DynamicResource ControlBg}")

        ; Layer grid
        this.grid := this.bdr.Add("Grid").Margin("0")

        ; Inner grid to handle universal padding, bypassing template discrepancies
        this.gridInner := this.grid.Add("Grid").Margin("15")

        ; Background layer: RichTextBox for syntax highlighting (Read-Only)
        this.rtb := this.gridInner.Add("RichTextBox").Name(this.id "_RTB").IsReadOnly("True").Focusable("False")
            .FontFamily("Consolas").FontSize("14").Background("Transparent").BorderThickness("0").Padding("0").Foreground("{DynamicResource TextMain}")

        ; Foreground layer: TextBox for typing (Transparent text/bg)
        this.tb := this.gridInner.Add("TextBox").Name(this.id).AcceptsReturn("True").AcceptsTab("True")
            .FontFamily("Consolas").FontSize("14").Background("Transparent").Foreground("Transparent").CaretBrush("{DynamicResource Accent}").BorderThickness("0").Padding("0").VerticalContentAlignment("Top")

        ; Suggestion popup (docked at bottom right)
        this.suggestBdr := this.grid.Add("Border").Name(this.id "_SuggestUI").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).CornerRadius(6).HorizontalAlignment("Right").VerticalAlignment("Bottom").Margin("20").Visibility("Collapsed").Padding("10,5")
        sSp := this.suggestBdr.Add("StackPanel").Orientation("Horizontal")
        sSp.Add("TextBlock").Text("💡").Margin("0,0,8,0").VerticalAlignment("Center")
        sSp.Add("TextBlock").Name(this.id "_SuggestTxt").Foreground("{DynamicResource TextMain}").FontFamily("Consolas").FontWeight("Bold").VerticalAlignment("Center")
        sSp.Add("TextBlock").Text("[Tab]").Foreground("{DynamicResource TextSub}").FontSize("11").Margin("15,0,0,0").VerticalAlignment("Center")

        if (initialCode != "")
            this.tb.Text(initialCode)

        this.suggestDict := ["MsgBox", "FormatTime", "StrSplit", "DllCall", "RegExMatch", "SetTimer", "FileSelect", "WinActivate"]
        this.currentSuggestion := ""
        this.currentWordLen := 0
        this.initialCode := initialCode
        this.isTyping := false

        this.ui := ""
        this.parseTimer := ObjBindMethod(this, "ExecuteParse")
    }

    Bind(ui) {
        this.ui := ui
        ui.Track(this.id)
        ui.Track(this.id "_CaretIndex") ; Uses the new bridge tracker

        ui.OnEvent(this.id, "TextChanged", ObjBindMethod(this, "OnTextChanged"))
        ui.OnEvent(this.id, "PreviewKeyDown", ObjBindMethod(this, "OnKeyDown"))

        ; Initial parse
        this.lastRaw := ""
        this.lastState := Map(this.id, this.initialCode, this.id "_CaretIndex", "0")

        ; Initial boot timer
        SetTimer(this.parseTimer, -50)
    }

    OnTextChanged(state, ctrl, event) {
        this.lastState := state

        if (!this.isTyping) {
            this.isTyping := true
            this.ui.Update(this.id, "Foreground", "{DynamicResource TextMain}")
        }

        ; Debounce rendering by 250ms to completely eliminate typing lag
        SetTimer(this.parseTimer, -250)
    }

    OnKeyDown(state, ctrl, event) {
        if (!IsObject(event) || !event.HasProp("Key"))
            return

        key := event.Key

        if (!this.isTyping) {
            this.isTyping := true
            this.ui.Update(this.id, "Foreground", "{DynamicResource TextMain}")
        }

        ; Delay parsing if they are actively typing keys
        SetTimer(this.parseTimer, -250)
    }

    ExecuteParse() {
        if (!this.ui || !this.lastState.Has(this.id) || !this.lastState.Has(this.id "_CaretIndex")) {
            return
        }

        ; Asynchronous boot check: WPF initializes asynchronously, so we must wait for the handle.
        if (!this.ui.HasProp("wpfHwnd") || !this.ui.wpfHwnd) {
            return
        }

        ; Request the latest tracked state synchronously
        text := this.lastState[this.id]

        ; Evaluate Auto-Suggest
        caret := Integer(this.lastState[this.id "_CaretIndex"])
        leftPart := SubStr(text, 1, caret)
        if (RegExMatch(leftPart, "([a-zA-Z_]\w*)$", &match)) {
            word := match[1]
            found := ""
            if (StrLen(word) >= 2) {
                for sugg in this.suggestDict {
                    if (SubStr(sugg, 1, StrLen(word)) == word && StrLen(sugg) > StrLen(word)) {
                        found := sugg
                        break
                    }
                }
            }

            if (found != "") {
                this.currentSuggestion := found
                this.currentWordLen := StrLen(word)
                this.ui.Update(this.id "_SuggestTxt", "Text", found)
                this.ui.Update(this.id "_SuggestUI", "Visibility", "Visible")
            } else {
                this.HideSuggestion()
            }
        } else {
            this.HideSuggestion()
        }

        if (text == this.lastRaw && this.lastRaw != "")
            return

        this.lastRaw := text

        ; Start building FlowDocument
        doc := "<FlowDocument Foreground=`"#E0E0E0`" xml:space=`"preserve`" xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" PagePadding=`"0`" LineHeight=`"16.296875`">"
        doc .= "<Paragraph Margin=`"0`">"

        ; Define basic AHK/JS regex syntax rules
        pos := 1
        len := StrLen(text)

        while (pos <= len) {
            ; Find next token
            nextType := ""
            nextMatch := ""
            nextPos := len + 1

            ; Comment //
            if (RegExMatch(text, "(?m)//.*$", &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "Comment"
            }
            ; Comment ;
            if (RegExMatch(text, "(?m);.*$", &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "Comment"
            }
            ; String "..." or '...'
            quotePattern := "([" Chr(34) Chr(39) "]).*?\1"
            if (RegExMatch(text, quotePattern, &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "String"
            }
            ; Number
            if (RegExMatch(text, "\b\d+(\.\d+)?\b", &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "Number"
            }
            ; Keywords
            if (RegExMatch(text, "\b(if|else|return|function|class|while|for|loop|global|static|var|let|const|true|false)\b", &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "Keyword"
            }
            ; Functions
            if (RegExMatch(text, "\b[a-zA-Z_]\w*(?=\()", &m, pos) && m.Pos(0) < nextPos) {
                nextPos := m.Pos(0), nextMatch := m[0], nextType := "Function"
            }

            if (nextPos > pos) {
                ; Add unformatted text before the match (or the entire remainder if no match)
                unformatted := SubStr(text, pos, nextPos - pos)
                doc .= this.EscapeRun(unformatted, "")
            }

            if (nextMatch != "") {
                color := ""
                fontWeight := "Normal"
                if (nextType == "Comment")
                    color := "#40A84F" ; Green
                else if (nextType == "String")
                    color := "#FF9F0A" ; Orange
                else if (nextType == "Number")
                    color := "#32D74B" ; Light Green
                else if (nextType == "Keyword") {
                    color := "#BF5AF2" ; Purple
                    fontWeight := "Bold"
                } else if (nextType == "Function") {
                    color := "#0A84FF" ; Blue
                }

                doc .= this.EscapeRun(nextMatch, color, fontWeight)
                pos := nextPos + StrLen(nextMatch)
            } else {
                ; We already appended the remainder in the (nextPos > pos) block above
                break
            }
        }

        doc .= "</Paragraph></FlowDocument>"

        ; Inject the document
        this.ui.Update(this.id "_RTB", "Document", doc)

        ; Reveal the syntax highlighting
        if (this.isTyping) {
            this.isTyping := false
            this.ui.Update(this.id, "Foreground", "Transparent")
        }
    }

    HideSuggestion() {
        this.currentSuggestion := ""
        this.currentWordLen := 0
        this.ui.Update(this.id "_SuggestUI", "Visibility", "Collapsed")
    }

    EscapeRun(txt, colorBrush, weight := "Normal") {
        if (txt == "")
            return ""

        ; Replace literal newlines with <LineBreak/>
        txt := StrReplace(txt, "&", "&amp;")
        txt := StrReplace(txt, "<", "&lt;")
        txt := StrReplace(txt, ">", "&gt;")

        parts := StrSplit(txt, "`n", "`r")
        out := ""
        Loop parts.Length {
            if (parts[A_Index] != "") {
                run := "<Run FontWeight=`"" weight "`""
                if (colorBrush != "") {
                    if (SubStr(colorBrush, 1, 1) == "{")
                        run .= " Foreground=`"" colorBrush "`""
                    else
                        run .= " Foreground=`"" colorBrush "`""
                }
                run .= ">" parts[A_Index] "</Run>"
                out .= run
            }
            if (A_Index < parts.Length)
                out .= "<LineBreak/>"
        }
        return out
    }
}

XAMLElement.Prototype.DefineProp("CodeEditor", { Call: _CodeEditorAdvanced })
_CodeEditorAdvanced(this, initialCode := "") {
    comp := XCodeEditor(this, initialCode)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; PROPERTY GRID / INSPECTOR
; ==============================================================================

class XPropertyGrid {
    __New(parentXAML, dataObj, name := "") {
        this.id := name != "" ? name : "PropGrid_" XPropertyGrid.Count()
        this.dataObj := dataObj
        this.bindings := Map()

        this.bdr := parentXAML.Add("Border").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6")
        this.sv := this.bdr.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").Padding("10")
        this.sp := this.sv.Add("StackPanel").Name(this.id)

        this.Render()
    }

    Render() {
        this.RenderItems(this.dataObj, this.sp, "")
    }

    RenderItems(obj, parentSp, prefix) {
        isMap := (Type(obj) == "Map")

        if (isMap) {
            for key, val in obj {
                this.RenderSingleItem(key, val, parentSp, prefix)
            }
        } else {
            for key, val in obj.OwnProps() {
                this.RenderSingleItem(key, val, parentSp, prefix)
            }
        }
    }

    RenderSingleItem(key, val, parentSp, prefix) {
        fullKey := prefix == "" ? String(key) : prefix "." String(key)
        valType := Type(val)

        if (valType == "Map" || valType == "Object") {
            catBorder := parentSp.Add("Border").Background("#10FFFFFF").CornerRadius("4").Padding("8,4").Margin("0,10,0,5")
            catBorder.Add("TextBlock").Text(String(key)).Foreground("{DynamicResource Accent}").FontWeight("Bold").FontSize("12")

            subSp := parentSp.Add("StackPanel").Margin("10,0,0,0")
            this.RenderItems(val, subSp, fullKey)
            return
        }

        itemGrid := parentSp.Add("Grid").Margin("0,4,0,4")
        itemGrid.Cols("2*", "3*")

        itemGrid.Add("TextBlock").Text(String(key)).Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").Grid_Column(0).Margin("0,0,10,0").TextWrapping("Wrap")

        ctrlId := this.id "_" StrReplace(fullKey, ".", "_")
        this.bindings[ctrlId] := { Key: fullKey, Type: valType, Original: val }

        if (valType == "Integer" && (val == 0 || val == 1) && (String(key) ~= "i)^(is|has|enable|show|use|allow)")) {
            valType := "Boolean"
            this.bindings[ctrlId].Type := "Boolean"
        }

        if (valType == "Boolean" || (valType == "Integer" && (val == 0 || val == 1) && (valType != "String"))) {
            chk := itemGrid.Add("CheckBox").Name(ctrlId).Style("{StaticResource ToggleSwitch}").Grid_Column(1).HorizontalAlignment("Right")
            if (val)
                chk.IsChecked("True")
            this.bindings[ctrlId].Type := "Boolean"
        } else if (valType == "Integer" || valType == "Float") {
            itemGrid.Add("TextBox").Name(ctrlId).Text(String(val)).Grid_Column(1).VerticalAlignment("Center").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").HorizontalContentAlignment("Right")
        } else {
            itemGrid.Add("TextBox").Name(ctrlId).Text(String(val)).Grid_Column(1).VerticalAlignment("Center").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}")
        }
    }

    Bind(ui) {
        this.ui := ui
        for ctrlId, info in this.bindings {
            ui.Track(ctrlId)

            if (info.Type == "Boolean") {
                ui.OnEvent(ctrlId, "Checked", ObjBindMethod(this, "OnValueChanged", ctrlId))
                ui.OnEvent(ctrlId, "Unchecked", ObjBindMethod(this, "OnValueChanged", ctrlId))
            } else {
                ui.OnEvent(ctrlId, "TextChanged", ObjBindMethod(this, "OnValueChanged", ctrlId))
            }
        }
    }

    OnValueChanged(ctrlId, state, ctrl, event) {
        if !state.Has(ctrlId)
            return

        info := this.bindings[ctrlId]
        newVal := state[ctrlId]

        if (info.Type == "Integer") {
            newVal := IsInteger(newVal) ? Integer(newVal) : (newVal == "True" ? 1 : (newVal == "False" ? 0 : 0))
        } else if (info.Type == "Float") {
            newVal := IsFloat(newVal) ? Float(newVal) : 0.0
        } else if (info.Type == "Boolean") {
            newVal := (newVal == "True" || newVal == "1")
        }

        this.UpdateObjectValue(this.dataObj, info.Key, newVal)
    }

    UpdateObjectValue(obj, fullKey, val) {
        parts := StrSplit(fullKey, ".")
        current := obj
        Loop parts.Length - 1 {
            k := parts[A_Index]
            isMap := (Type(current) == "Map")
            if (isMap)
                current := current[k]
            else
                current := current.%k%
        }

        lastK := parts[parts.Length]
        if (Type(current) == "Map")
            current[lastK] := val
        else
            current.%lastK% := val
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("PropertyGrid", { Call: _PropertyGrid })
_PropertyGrid(this, dataObj, name := "") {
    comp := XPropertyGrid(this, dataObj, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; DIFF VIEWER
; ==============================================================================

class XDiffViewer {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "DiffViewer_" XDiffViewer.Count()
        this.ui := ""

        this.bdr := parentXAML.Add("Border").Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").CornerRadius("6").ClipToBounds("True")
        this.grid := this.bdr.Add("Grid")
        this.grid.Rows("Auto", "*")

        ; Header / Toolbar
        header := this.grid.Add("Border").Grid_Row(0).Background("#10FFFFFF").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,0,1").Padding("8")
        hSp := header.Add("StackPanel").Orientation("Horizontal")

        this.btnInline := hSp.Add("RadioButton").Name(this.id "_BtnInline").Content("Inline").Style("{StaticResource SegmentedBtn}").IsChecked("True").GroupName(this.id "_ViewMode").BorderThickness("0,0,1,0")
        this.btnSide := hSp.Add("RadioButton").Name(this.id "_BtnSide").Content("Side-by-Side").Style("{StaticResource SegmentedBtn}").GroupName(this.id "_ViewMode").BorderThickness("0")

        ; Content Area
        this.sv := this.grid.Add("ScrollViewer").Grid_Row(1).HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Auto").Padding("0,5,0,5")
        this.contentGrid := this.sv.Add("Grid").Name(this.id "_Content")
    }

    Bind(ui) {
        this.ui := ui
        ui.OnEvent(this.id "_BtnInline", "Checked", ObjBindMethod(this, "RenderInline"))
        ui.OnEvent(this.id "_BtnSide", "Checked", ObjBindMethod(this, "RenderSideBySide"))
        ui.OnEvent("Window", "LoadedHwnd", ObjBindMethod(this, "OnLoad"))
    }

    OnLoad(state := "", ctrl := "", event := "") {
        if (this.HasProp("diffData") && this.diffData) {
            ; Check which toggle is active to render correctly
            if (state.Has(this.id "_BtnSide") && state[this.id "_BtnSide"] == "True")
                this.RenderSideBySide()
            else
                this.RenderInline()
        }
    }

    SetDiff(text1, text2) {
        this.text1 := text1
        this.text2 := text2
        this.diffData := this.ComputeDiff(text1, text2)

        if (this.HasProp("ui") && this.ui) {
            this.RenderInline()
        }
    }

    ComputeDiff(text1, text2) {
        lines1 := StrSplit(StrReplace(text1, "`r"), "`n")
        lines2 := StrSplit(StrReplace(text2, "`r"), "`n")

        diff := []
        i := 1, j := 1

        while (i <= lines1.Length || j <= lines2.Length) {
            if (i > lines1.Length) {
                diff.Push({ Type: "+", Text: lines2[j], L1: "", L2: j })
                j++
                continue
            }
            if (j > lines2.Length) {
                diff.Push({ Type: "-", Text: lines1[i], L1: i, L2: "" })
                i++
                continue
            }
            if (lines1[i] == lines2[j]) {
                diff.Push({ Type: "=", Text: lines1[i], L1: i, L2: j })
                i++
                j++
                continue
            }

            resynced := false
            Loop 10 {
                k := A_Index
                if (i + k <= lines1.Length && lines1[i + k] == lines2[j]) {
                    Loop k {
                        diff.Push({ Type: "-", Text: lines1[i], L1: i, L2: "" })
                        i++
                    }
                    resynced := true
                    break
                }
                if (j + k <= lines2.Length && lines1[i] == lines2[j + k]) {
                    Loop k {
                        diff.Push({ Type: "+", Text: lines2[j], L1: "", L2: j })
                        j++
                    }
                    resynced := true
                    break
                }
            }

            if (!resynced) {
                diff.Push({ Type: "-", Text: lines1[i], L1: i, L2: "" })
                i++
                diff.Push({ Type: "+", Text: lines2[j], L1: "", L2: j })
                j++
            }
        }
        return diff
    }

    EscapeXml(txt) {
        txt := StrReplace(txt, "&", "&amp;")
        txt := StrReplace(txt, "<", "&lt;")
        txt := StrReplace(txt, ">", "&gt;")
        return txt == "" ? " " : txt
    }

    RenderInline(state := "", ctrl := "", event := "") {
        if (!this.HasProp("diffData") || !this.diffData)
            return

        xaml := '<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        for d in this.diffData {
            bg := d.Type == "+" ? "#2032D74B" : (d.Type == "-" ? "#20FF3333" : "Transparent")
            fg := d.Type == "+" ? "#32D74B" : (d.Type == "-" ? "#FF3333" : "{DynamicResource TextMain}")
            sign := d.Type == "=" ? " " : d.Type

            lineXaml := '<Border Background="' bg '" BorderBrush="Transparent" BorderThickness="0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="40"/><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
            lineXaml .= '<TextBlock Grid.Column="0" Text="' d.L1 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/>'
            lineXaml .= '<TextBlock Grid.Column="1" Text="' d.L2 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/>'
            lineXaml .= '<TextBlock Grid.Column="2" Text="' sign '" Foreground="' fg '" FontSize="12" FontFamily="Consolas" FontWeight="Bold" TextAlignment="Center"/>'

            txt := this.EscapeXml(d.Text)
            lineXaml .= '<TextBlock Grid.Column="3" Text="' txt '" Foreground="' fg '" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'
            xaml .= lineXaml
        }
        xaml .= '</StackPanel>'

        if (this.HasProp("ui") && this.ui) {
            this.ui.Update(this.id "_Content", "ClearItems", "")
            this.ui.Update(this.id "_Content", "AddXamlItem", xaml)
        }
    }

    RenderSideBySide(state := "", ctrl := "", event := "") {
        if (!this.HasProp("diffData") || !this.diffData)
            return

        xaml := '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="1"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0">'

        leftSp := ""
        rightSp := ""

        i := 1
        while (i <= this.diffData.Length) {
            d := this.diffData[i]
            txt := this.EscapeXml(d.Text)

            if (d.Type == "=") {
                leftSp .= '<Border Background="Transparent"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d.L1 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt '" Foreground="{DynamicResource TextMain}" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'

                rightSp .= '<Border Background="Transparent"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d.L2 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt '" Foreground="{DynamicResource TextMain}" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'
                i++
            } else if (d.Type == "-") {
                if (i < this.diffData.Length && this.diffData[i + 1].Type == "+") {
                    d2 := this.diffData[i + 1]
                    txt2 := this.EscapeXml(d2.Text)

                    leftSp .= '<Border Background="#20FF3333"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d.L1 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt '" Foreground="#FF3333" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'

                    rightSp .= '<Border Background="#2032D74B"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d2.L2 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt2 '" Foreground="#32D74B" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'
                    i += 2
                } else {
                    leftSp .= '<Border Background="#20FF3333"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d.L1 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt '" Foreground="#FF3333" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'

                    rightSp .= '<Border Background="#10FF3333"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text=" " FontSize="12" FontFamily="Consolas"/></Grid></Border>'
                    i++
                }
            } else if (d.Type == "+") {
                leftSp .= '<Border Background="#1032D74B"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text=" " FontSize="12" FontFamily="Consolas"/></Grid></Border>'

                rightSp .= '<Border Background="#2032D74B"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="' d.L2 '" Foreground="{DynamicResource TextSub}" FontSize="12" FontFamily="Consolas" TextAlignment="Right" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' txt '" Foreground="#32D74B" FontSize="12" FontFamily="Consolas" TextWrapping="NoWrap"/></Grid></Border>'
                i++
            }
        }

        xaml .= leftSp '</StackPanel><Rectangle Grid.Column="1" Fill="{DynamicResource ControlBorder}"/><StackPanel Grid.Column="2">' rightSp '</StackPanel></Grid>'

        if (this.HasProp("ui") && this.ui) {
            this.ui.Update(this.id "_Content", "ClearItems", "")
            this.ui.Update(this.id "_Content", "AddXamlItem", xaml)
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("DiffViewer", { Call: _DiffViewer })
_DiffViewer(this, name := "") {
    comp := XDiffViewer(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

class XWebView extends XAMLElement {
    __New(parent, id := "") {
        if (!XAML_ENABLE_WEBVIEW)
            throw Error("WebView is disabled. Set XAML_ENABLE_WEBVIEW := true in XAML_Config.ahk to use it.")

        if (id == "")
            id := "WebView_" XWebView.Count()
        super.__New("Grid")
        this.SetProp("xmlns:wv2", "clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf")
        this.Name(id)
        this.id := id
        this._Parent := parent
        parent._Children.Push(this)

        this.Rows("Auto", "*")

        tb := this.Add("Border").Grid_Row(0).Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,0,1").Padding("10")
        sp := tb.Add("StackPanel").Orientation("Horizontal")

        this.btnBackId := this.id "_BtnBack"
        this.btnBack := sp.Add("Button").Name(this.btnBackId).Style("{StaticResource IconButton}").Width("32").Height("32").Margin("0,0,5,0").ToolTip("Back")
        this.btnBack.Add("TextBlock").Text(Chr(0xE72B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(16).HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0")

        this.btnFwdId := this.id "_BtnFwd"
        this.btnFwd := sp.Add("Button").Name(this.btnFwdId).Style("{StaticResource IconButton}").Width("32").Height("32").Margin("0,0,10,0").ToolTip("Forward")
        this.btnFwd.Add("TextBlock").Text(Chr(0xE72A)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(16).HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0")

        this.btnRefreshId := this.id "_BtnRefresh"
        this.btnRefresh := sp.Add("Button").Name(this.btnRefreshId).Style("{StaticResource IconButton}").Width("32").Height("32").Margin("0,0,10,0").ToolTip("Refresh")
        this.btnRefresh.Add("TextBlock").Text(Chr(0xE72C)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(16).HorizontalAlignment("Center").VerticalAlignment("Center").Margin("0")

        this.txtUrlId := this.id "_TxtUrl"
        this.txtUrl := sp.Add("TextBox").Name(this.txtUrlId).Width("400").Margin("0,0,10,0").VerticalAlignment("Center").Text("https://google.com/")

        this.btnGoId := this.id "_BtnGo"
        this.btnGo := sp.Add("Button").Name(this.btnGoId).Background("{DynamicResource Accent}").Foreground("White").BorderThickness("0").Padding("15,6").Content("Go").Margin("0,0,10,0")

        this.btnDevToolsId := this.id "_BtnDevTools"
        this.btnDevTools := sp.Add("Button").Name(this.btnDevToolsId).Background("#10FFFFFF").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("15,6").Content("DevTools").Margin("0,0,10,0")

        this.btnAddJsBtnId := this.id "_BtnAddJsBtn"
        this.btnAddJsBtn := sp.Add("Button").Name(this.btnAddJsBtnId).Background("#10FFFFFF").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("15,6").Content("Add JS Button").Margin("0,0,10,0")

        this.btnInjectId := this.id "_BtnInject"
        this.btnInject := sp.Add("Button").Name(this.btnInjectId).Background("#10FFFFFF").Foreground("{DynamicResource TextMain}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Padding("15,6").Content("Inject JS")

        this.wvName := this.id "_WV"
        wv := this.Add("wv2:WebView2").Name(this.wvName).Grid_Row(1).SetProp("Source", "https://google.com/")

        this.OnMessageCallback := ""
    }

    Bind(ui) {
        this.ui := ui
        ui.Track(this.txtUrlId)
        ui.OnEvent(this.btnGoId, "Click", ObjBindMethod(this, "OnGoClick"))
        ui.OnEvent(this.btnBackId, "Click", (*) => ui.Update(this.wvName, "GoBack", ""))
        ui.OnEvent(this.btnFwdId, "Click", (*) => ui.Update(this.wvName, "GoForward", ""))
        ui.OnEvent(this.btnRefreshId, "Click", (*) => ui.Update(this.wvName, "Refresh", ""))
        ui.OnEvent(this.btnDevToolsId, "Click", (*) => ui.Update(this.wvName, "OpenDevTools", ""))
        ui.OnEvent(this.btnAddJsBtnId, "Click", ObjBindMethod(this, "OnAddJsBtnClick"))
        ui.OnEvent(this.btnInjectId, "Click", ObjBindMethod(this, "OnInjectClick"))

        ui.OnEvent(this.wvName, "NavigationCompleted", ObjBindMethod(this, "OnNavCompleted"))
        ui.OnEvent(this.wvName, "WebMessageReceived", ObjBindMethod(this, "OnWebMessage"))

        ; Enable Return key to trigger Go
        ui.OnEvent(this.txtUrlId, "KeyDown:Return", ObjBindMethod(this, "OnGoClick"))
    }

    OnGoClick(state, ctrl, event) {
        url := state.Has(this.txtUrlId) ? state[this.txtUrlId] : ""
        if (url != "") {
            if (!InStr(url, "http://") && !InStr(url, "https://") && !InStr(url, "file://"))
                url := "https://" url
            this.Navigate(url)
        }
    }

    OnInjectClick(state, ctrl, event) {
        js := "console.log('Inject JS triggered!'); alert('hello world');"
        this.ExecuteJS(js)
    }

    OnAddJsBtnClick(state, ctrl, event) {
        js := "let btn = document.createElement('button'); btn.innerText = 'Send Message to AHK'; btn.style.position = 'fixed'; btn.style.top = '20px'; btn.style.right = '20px'; btn.style.zIndex = 999999; btn.style.padding = '15px'; btn.style.fontSize = '16px'; btn.style.background = '#0078D7'; btn.style.color = 'white'; btn.style.border = 'none'; btn.style.borderRadius = '5px'; btn.style.cursor = 'pointer'; btn.onclick = () => window.chrome.webview.postMessage('Button clicked from inside the webpage!'); document.body.appendChild(btn);"
        this.ExecuteJS(js)
    }

    OnNavCompleted(state, ctrl, event) {
        if (state.Has("NavigationCompleted")) {
            url := state["NavigationCompleted"]
            if (url != "")
                this.ui.Update(this.txtUrlId, "Text", url)
        }
    }

    OnWebMessage(state, ctrl, event) {
        if (state.Has("WebMessageReceived")) {
            msg := state["WebMessageReceived"]
            if (this.OnMessageCallback) {
                cb := this.OnMessageCallback
                cb(msg)
            }
        }
    }

    Navigate(url) {
        if (this.HasProp("ui") && this.ui)
            this.ui.Update(this.wvName, "Navigate", url)
    }

    ExecuteJS(js) {
        if (this.HasProp("ui") && this.ui)
            this.ui.Update(this.wvName, "ExecuteScript", XAMLHost.Base64Encode(js))
    }

    PostMessage(msg) {
        if (this.HasProp("ui") && this.ui)
            this.ui.Update(this.wvName, "PostWebMessage", msg)
    }

    OnMessage(callback) {
        this.OnMessageCallback := callback
        return this
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("WebView", { Call: _WebView })
_WebView(this, name := "") {
    comp := XWebView(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; XFlyout Component
; ==============================================================================

class XFlyout {
    __New(id, side := "Left", mode := "Push", size := 240, dimBg := false) {
        this.id := id
        this.side := side
        this.mode := mode
        this.size := size
        this.dimBg := dimBg
        this.stateName := "Flyout_" id "_State"
        this.containerName := "Flyout_" id "_Container"
    }

    Build(parent) {
        ; Create a hidden ToggleButton to track state
        parent.Add("ToggleButton").Name(this.stateName).Visibility("Collapsed")

        isVertical := (this.side == "Left" || this.side == "Right")
        targetProp := isVertical ? "Width" : "Height"

        if (this.dimBg) {
            this.scrimName := this.id "_ScrimBtn"
            this.scrim := parent.Add("Button").Name(this.scrimName).Background("#A0000000").SetProp("Panel.ZIndex", "98").Opacity("0").Cursor("Arrow")
            this.scrim.Add("Button.Template").Add("ControlTemplate").TargetType("Button").Add("Border").Background("{TemplateBinding Background}")

            this.scrim.Grid_RowSpan("99").Grid_ColumnSpan("99")

            scrimStyle := this.scrim.Add("Button.Style").Add("Style").TargetType("Button")
            scrimStyle.Add("Setter").Property("IsHitTestVisible").Value("False")

            triggers := scrimStyle.Add("Style.Triggers")
            dt := triggers.Add("DataTrigger").Binding("{Binding IsChecked, ElementName=" this.stateName "}").Value("True")
            dt.Add("Setter").Property("IsHitTestVisible").Value("True")

            enterActions := dt.Add("DataTrigger.EnterActions").Add("BeginStoryboard").Add("Storyboard")
            enterActions.Add("DoubleAnimation").Storyboard_TargetProperty("Opacity").To("1").Duration("0:0:0.2")

            exitActions := dt.Add("DataTrigger.ExitActions").Add("BeginStoryboard").Add("Storyboard")
            exitActions.Add("DoubleAnimation").Storyboard_TargetProperty("Opacity").To("0").Duration("0:0:0.2")
        }

        ; Container border
        this.container := parent.Add("Border").Name(this.containerName).Background("{DynamicResource SidebarColor}").BorderBrush("{DynamicResource ControlBorder}")

        if (InStr(this.mode, "Overlay")) {
            this.container.BorderThickness("0")
            this.container.ClipToBounds("False")

            ; Add a beautiful drop shadow for overlays
            this.container.Add("Border.Effect").Add("DropShadowEffect").BlurRadius("30").ShadowDepth("0").Opacity("0.4").SetProp('Color', "Black")
        } else {
            this.container.ClipToBounds("True")
            if (this.side == "Right")
                this.container.BorderThickness("1,0,0,0")
            else if (this.side == "Left")
                this.container.BorderThickness("0,0,1,0")
            else if (this.side == "Top")
                this.container.BorderThickness("0,0,0,1")
            else if (this.side == "Bottom")
                this.container.BorderThickness("0,1,0,0")
        }

        isVertical := (this.side == "Left" || this.side == "Right")
        targetProp := isVertical ? "Width" : "Height"

        if (this.mode == "PopPush" || this.mode == "PopOverlay") {
            style := this.container.Add("Border.Style").Add("Style").TargetType("Border")
            style.Add("Setter").Property(targetProp).Value("0")

            trigger := style.Add("Style.Triggers").Add("DataTrigger").Binding("{Binding IsChecked, ElementName=" this.stateName "}").Value("True")
            trigger.Add("Setter").Property(targetProp).Value(String(this.size))

            if (InStr(this.mode, "Overlay")) {
                this.ApplyOverlayLayout(isVertical)
            }
        } else {
            ; Push or Overlay (Animated)
            style := this.container.Add("Border.Style").Add("Style").TargetType("Border")

            if (this.mode == "Overlay") {
                this.container.SetProp(targetProp, String(this.size))

                ; Base Transform
                transform := style.Add("Style.Resources").Add("TranslateTransform").SetProp("x:Key", "SlideTransform")
                if (this.side == "Left")
                    transform.X(String(-(this.size + 50)))
                else if (this.side == "Right")
                    transform.X(String(this.size + 50))
                else if (this.side == "Top")
                    transform.Y(String(-(this.size + 50)))
                else if (this.side == "Bottom")
                    transform.Y(String(this.size + 50))

                style.Add("Setter").Property("RenderTransform").Value("{StaticResource SlideTransform}")

                this.ApplyOverlayLayout(isVertical)
                this.BuildOverlayAnimations(style, isVertical)
            } else {
                ; Push Mode
                style.Add("Setter").Property(targetProp).Value("0")
                this.BuildPushAnimations(style, targetProp)
            }
        }

        ; Auto-register with XAML_GUI for auto-bind during Compile()
        _AutoRegisterComponent(parent, this)

        return this.container
    }

    ApplyOverlayLayout(isVertical) {
        this.container.SetProp("Panel.ZIndex", "100")
        if (this.side == "Left")
            this.container.HorizontalAlignment("Left")
        else if (this.side == "Right")
            this.container.HorizontalAlignment("Right")
        else if (this.side == "Top")
            this.container.VerticalAlignment("Top")
        else if (this.side == "Bottom")
            this.container.VerticalAlignment("Bottom")

        ; To allow Overlay to work within Grids, we must span
        this.container.Grid_RowSpan("99")
        this.container.Grid_ColumnSpan("99")
    }

    BuildPushAnimations(style, targetProp) {
        triggers := style.Add("Style.Triggers")
        dt := triggers.Add("DataTrigger").Binding("{Binding IsChecked, ElementName=" this.stateName "}").Value("True")

        enterActions := dt.Add("DataTrigger.EnterActions").Add("BeginStoryboard").Add("Storyboard")
        enterActions.Add("DoubleAnimation").Storyboard_TargetProperty(targetProp).To(String(this.size)).Duration("0:0:0.2").DecelerationRatio("0.8")

        exitActions := dt.Add("DataTrigger.ExitActions").Add("BeginStoryboard").Add("Storyboard")
        exitActions.Add("DoubleAnimation").Storyboard_TargetProperty(targetProp).To("0").Duration("0:0:0.2").DecelerationRatio("0.8")
    }

    BuildOverlayAnimations(style, isVertical) {
        triggers := style.Add("Style.Triggers")
        dt := triggers.Add("DataTrigger").Binding("{Binding IsChecked, ElementName=" this.stateName "}").Value("True")

        propName := isVertical ? "X" : "Y"

        enterActions := dt.Add("DataTrigger.EnterActions").Add("BeginStoryboard").Add("Storyboard")
        enterActions.Add("DoubleAnimation").Storyboard_TargetProperty("RenderTransform.(TranslateTransform." propName ")").To("0").Duration("0:0:0.2").DecelerationRatio("0.8")

        exitActions := dt.Add("DataTrigger.ExitActions").Add("BeginStoryboard").Add("Storyboard")
        toVal := ""
        if (this.side == "Left")
            toVal := String(-(this.size + 50))
        else if (this.side == "Right")
            toVal := String(this.size + 50)
        else if (this.side == "Top")
            toVal := String(-(this.size + 50))
        else if (this.side == "Bottom")
            toVal := String(this.size + 50)

        exitActions.Add("DoubleAnimation").Storyboard_TargetProperty("RenderTransform.(TranslateTransform." propName ")").To(toVal).Duration("0:0:0.2").DecelerationRatio("0.8")
    }

    ; Set a hotkey that toggles this flyout. Stored and applied during auto-bind.
    Hotkey(hotkeyStr) {
        this._hotkey := hotkeyStr
        return this
    }

    Bind(ui, hotkeyStr := "") {
        ; Guard against double-bind (e.g., when owned by XCommandPalette)
        if (this.HasOwnProp("_bound") && this._bound)
            return
        this._bound := true
        this.ui := ui
        ui.Track(this.stateName)
        if (this.HasProp("scrimName")) {
            ui.OnEvent(this.scrimName, "Click", (*) => this.Toggle())
        }
        ; Use stored hotkey if no explicit one provided
        if (hotkeyStr == "" && this.HasOwnProp("_hotkey") && this._hotkey != "")
            hotkeyStr := this._hotkey
        if (hotkeyStr != "") {
            Hotkey(hotkeyStr, (*) => this.Toggle(), "On")
        }
    }

    Toggle() {
        if (this.HasProp("ui") && this.ui)
            this.ui.Update(this.stateName, "Invoke", "1")
    }

    SetState(state, isOpen) {
        if (!this.HasProp("ui") || !this.ui)
            return

        currentState := state.Has(this.stateName) ? (state[this.stateName] == "True") : false
        if (currentState != isOpen) {
            this.ui.Update(this.stateName, "Invoke", "1")
        }
    }

    IsOpen(ui) {
        return ui.state.Has(this.stateName) ? (ui.state[this.stateName] == "True") : false
    }
}

; ==============================================================================
; COMMAND PALETTE (Robust, Feature-Rich VS Code-Style)
; ==============================================================================

class XCommandPalette {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "CmdPalette_" XCommandPalette.Count()
        this.commands := Map()        ; id => { label, icon, shortcut, category, callback }
        this.commandOrder := []       ; Ordered list of command IDs
        this.homeCommands := []       ; IDs shown on home screen
        this.recentCommands := []     ; Last executed commands (most recent first)
        this.maxRecent := 5
        this.modes := Map()           ; prefix => { label, filterFn }
        this.customDataSource := ""   ; External data source function
        this.ui := ""
        this.isOpen := false
        this.selectedIndex := -1      ; Currently highlighted result (-1 = none)
        this.currentResults := []     ; Array of { id, label } for current visible results
        this.escHotkeyBound := false
        this.navHotkeyBound := false

        ; --- Build the Flyout ---
        this.flyout := XFlyout(this.id, "Top", "Overlay", 380, true)
        this.flyout.Build(parentXAML).HorizontalAlignment("Center").Margin("0,10,0,0").CornerRadius("8")
        this.flyout.container.Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Width("620")

        mainGrid := this.flyout.container.Add("Grid")
        mainGrid.Rows("Auto", "Auto", "*")

        ; Search Box with icon
        searchBorder := mainGrid.Add("Border").Grid_Row(0).Background("{DynamicResource ControlBg}").BorderBrush("{DynamicResource Accent}").BorderThickness("0,0,0,2").Padding("0")
        searchGrid := searchBorder.Add("Grid")
        searchGrid.Cols("Auto", "*")
        searchGrid.Add("TextBlock").Text(Chr(0xE721)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("{DynamicResource Accent}").FontSize(14).VerticalAlignment("Center").Margin("14,0,0,0").IsHitTestVisible("False")
        this.searchBox := searchGrid.Add("TextBox").Name(this.id "_Search").Grid_Column(1).Text("").Background("Transparent").Foreground("{DynamicResource TextMain}").BorderThickness("0").Padding("10,12").FontSize(14).CaretBrush("{DynamicResource Accent}")

        ; Category Label
        this.listTitle := mainGrid.Add("TextBlock").Name(this.id "_Title").Grid_Row(1).Text("recently used").Foreground("{DynamicResource TextSub}").FontSize(10).FontWeight("SemiBold").Margin("14,8,14,4").Opacity("0.7")

        ; Scrollable results area
        scroll := mainGrid.Add("ScrollViewer").Grid_Row(2).VerticalScrollBarVisibility("Auto").MaxHeight("300")
        this.resultsSp := scroll.Add("StackPanel").Name(this.id "_Results").Margin("6,0,6,6")

        ; --- Register built-in help mode ---
        this.AddMode("?", "Help", ObjBindMethod(this, "GetHelpItems"))
    }

    ; =========================================================================
    ; COMMAND REGISTRATION
    ; =========================================================================

    AddCommand(id, label, opts := "") {
        cmd := { id: id, label: label, icon: "", shortcut: "", category: "", callback: "" }
        if (IsObject(opts)) {
            if (opts.HasProp("Icon"))
                cmd.icon := opts.Icon
            if (opts.HasProp("Shortcut"))
                cmd.shortcut := opts.Shortcut
            if (opts.HasProp("Category"))
                cmd.category := opts.Category
            if (opts.HasProp("Callback"))
                cmd.callback := opts.Callback
        }
        this.commands[id] := cmd
        this.commandOrder.Push(id)
    }

    SetHomeCommands(idsArray) {
        this.homeCommands := idsArray
    }

    AddMode(prefix, label, filterFn) {
        this.modes[prefix] := { label: label, filterFn: filterFn }
    }

    SetDataSource(filterFn) {
        this.customDataSource := filterFn
    }

    ; =========================================================================
    ; BINDING & LIFECYCLE
    ; =========================================================================

    ; Set a hotkey that opens this palette. Stored and applied during auto-bind.
    Hotkey(hotkeyStr) {
        this._hotkey := hotkeyStr
        return this
    }

    Bind(uiObj, hotkeyStr := "") {
        this.ui := uiObj
        this.flyout.Bind(uiObj, "")  ; Don't use flyout's hotkey — we manage our own

        ; Track the flyout state toggle to detect open/close
        uiObj.OnEvent(this.flyout.stateName, "Click", ObjBindMethod(this, "OnFlyoutStateChanged"))
        uiObj.Track(this.flyout.stateName)

        ; Text changes drive filtering
        uiObj.OnEvent(this.id "_Search", "TextChanged", ObjBindMethod(this, "OnSearchChanged"))

        ; Use stored hotkey if no explicit one provided
        if (hotkeyStr == "" && this.HasOwnProp("_hotkey") && this._hotkey != "")
            hotkeyStr := this._hotkey
        ; Register the global hotkey to open
        if (hotkeyStr != "") {
            this.openHotkey := hotkeyStr
            Hotkey(hotkeyStr, (*) => this.Open(), "On")
        }
    }

    ; =========================================================================
    ; OPEN / CLOSE
    ; =========================================================================

    Open() {
        if (!this.ui)
            return
        if (this.isOpen) {
            this.Close()
            return
        }
        this.isOpen := true
        this.selectedIndex := -1

        ; Open the flyout
        this.flyout.Toggle()

        ; Focus the search box and show home screen
        SetTimer(ObjBindMethod(this, "PostOpen"), -50)
    }

    PostOpen() {
        this.ui.Update(this.id "_Search", "Text", "")
        this.ui.Update(this.id "_Search", "Focus", "True")
        this.ShowHome()
        this.BindKeyboardNav()
    }

    Close() {
        if (!this.isOpen || !this.ui)
            return
        this.isOpen := false
        this.selectedIndex := -1

        ; Close flyout
        this.flyout.Toggle()

        ; Reset
        this.ui.Update(this.id "_Search", "Text", "")
        this.UnbindKeyboardNav()
    }

    OnFlyoutStateChanged(state, ctrl, event) {
        if (!state.Has(this.flyout.stateName))
            return
        nowOpen := state[this.flyout.stateName] == "True"
        if (nowOpen && !this.isOpen) {
            ; Opened via scrim click-through or external toggle
            this.isOpen := true
            SetTimer(ObjBindMethod(this, "PostOpen"), -50)
        } else if (!nowOpen && this.isOpen) {
            ; Closed via scrim click
            this.isOpen := false
            this.selectedIndex := -1
            this.ui.Update(this.id "_Search", "Text", "")
            this.UnbindKeyboardNav()
        }
    }

    ; =========================================================================
    ; KEYBOARD NAVIGATION
    ; =========================================================================

    CheckHotkeyContext(*) {
        return this.isOpen && WinActive("ahk_id " this.ui.wpfHwnd)
    }

    BindKeyboardNav() {
        if (this.navHotkeyBound)
            return
        this.navHotkeyBound := true

        if (!this.HasProp("hotkeyContextFn"))
            this.hotkeyContextFn := ObjBindMethod(this, "CheckHotkeyContext")

        HotIf this.hotkeyContextFn
        Hotkey "Escape", ObjBindMethod(this, "OnEscape"), "On"
        Hotkey "Up", ObjBindMethod(this, "OnArrowUp"), "On"
        Hotkey "Down", ObjBindMethod(this, "OnArrowDown"), "On"
        Hotkey "Enter", ObjBindMethod(this, "OnEnter"), "On"
        Hotkey "Home", ObjBindMethod(this, "OnHomeKey"), "On"
        Hotkey "End", ObjBindMethod(this, "OnEndKey"), "On"
        HotIf
    }

    UnbindKeyboardNav() {
        if (!this.navHotkeyBound)
            return
        this.navHotkeyBound := false

        if (this.HasProp("hotkeyContextFn")) {
            try {
                HotIf this.hotkeyContextFn
                Hotkey "Escape", "Off"
                Hotkey "Up", "Off"
                Hotkey "Down", "Off"
                Hotkey "Enter", "Off"
                Hotkey "Home", "Off"
                Hotkey "End", "Off"
                HotIf
            }
        }
    }

    OnEscape(*) {
        if (!this.isOpen)
            return
        ; If there's text, clear it first (goes back to home)
        currentText := ""
        try {
            ; We can't read state synchronously, so just close
            this.Close()
        }
    }

    OnArrowUp(*) {
        if (!this.isOpen || this.currentResults.Length == 0)
            return
        if (this.selectedIndex <= 0)
            this.selectedIndex := this.currentResults.Length - 1
        else
            this.selectedIndex--
        this.HighlightSelected()
        ; Keep focus on search box
        this.ui.Update(this.id "_Search", "Focus", "True")
    }

    OnArrowDown(*) {
        if (!this.isOpen || this.currentResults.Length == 0)
            return
        if (this.selectedIndex >= this.currentResults.Length - 1)
            this.selectedIndex := 0
        else
            this.selectedIndex++
        this.HighlightSelected()
        ; Keep focus on search box
        this.ui.Update(this.id "_Search", "Focus", "True")
    }

    OnEnter(*) {
        if (!this.isOpen)
            return
        if (this.selectedIndex >= 0 && this.selectedIndex < this.currentResults.Length) {
            result := this.currentResults[this.selectedIndex + 1]
            this.ExecuteCommand(result.id)
        } else if (this.currentResults.Length > 0) {
            ; Execute first result if nothing explicitly selected
            result := this.currentResults[1]
            this.ExecuteCommand(result.id)
        }
    }

    OnHomeKey(*) {
        if (!this.isOpen || this.currentResults.Length == 0)
            return
        this.selectedIndex := 0
        this.HighlightSelected()
        this.ui.Update(this.id "_Search", "Focus", "True")
    }

    OnEndKey(*) {
        if (!this.isOpen || this.currentResults.Length == 0)
            return
        this.selectedIndex := this.currentResults.Length - 1
        this.HighlightSelected()
        this.ui.Update(this.id "_Search", "Focus", "True")
    }

    ; =========================================================================
    ; SEARCH & FILTERING
    ; =========================================================================

    OnSearchChanged(state, ctrl, event) {
        if (!this.ui || !state.Has(ctrl))
            return
        query := state[ctrl]

        ; Always move caret to end
        this.ui.Update(this.id "_Search", "CaretIndex", "9999")

        this.FilterAndRender(query)
    }

    FilterAndRender(query) {
        rawQuery := Trim(query)
        this.currentResults := []
        this.selectedIndex := 0
        titleText := ""
        resultItems := []

        ; Check for mode prefix
        if (rawQuery == "") {
            ; HOME SCREEN
            titleText := "recently used"
            if (this.recentCommands.Length > 0) {
                for id in this.recentCommands {
                    if (this.commands.Has(id))
                        resultItems.Push(this.commands[id])
                }
            } else {
                for id in this.homeCommands {
                    if (this.commands.Has(id))
                        resultItems.Push(this.commands[id])
                }
            }
        } else {
            ; Check mode prefixes
            prefix := SubStr(rawQuery, 1, 1)
            handled := false

            if (this.modes.Has(prefix)) {
                mode := this.modes[prefix]
                titleText := mode.label
                searchTerm := Trim(SubStr(rawQuery, 2))
                resultItems := mode.filterFn.Call(searchTerm)
                handled := true
            }

            if (!handled) {
                if (prefix == ">") {
                    ; Command mode
                    titleText := "commands"
                    searchTerm := Trim(SubStr(rawQuery, 2))
                    resultItems := this.FilterCommands(searchTerm)
                } else {
                    ; General search (no prefix)
                    titleText := "search results"
                    resultItems := this.FilterCommands(rawQuery)
                }
            }
        }

        ; Use custom data source if set
        if (this.customDataSource != "" && rawQuery != "") {
            try {
                customResults := this.customDataSource.Call(rawQuery)
                if (IsObject(customResults)) {
                    for item in customResults
                        resultItems.Push(item)
                }
            }
        }

        ; Render
        this.RenderResults(titleText, resultItems)
    }

    FilterCommands(searchTerm) {
        results := []
        if (searchTerm == "") {
            ; Show all commands
            for id in this.commandOrder {
                if (this.commands.Has(id))
                    results.Push(this.commands[id])
            }
        } else {
            ; Fuzzy-ish filter: case-insensitive substring match
            for id in this.commandOrder {
                if (!this.commands.Has(id))
                    continue
                cmd := this.commands[id]
                if (InStr(cmd.label, searchTerm))
                    results.Push(cmd)
            }
        }
        return results
    }

    GetHelpItems(searchTerm := "") {
        help := []
        help.Push({ id: "_help_commands", label: "Type > to search commands", icon: Chr(0xE756), shortcut: "", category: "help", callback: "" })
        help.Push({ id: "_help_search", label: "Type to search across all commands", icon: Chr(0xE721), shortcut: "", category: "help", callback: "" })
        help.Push({ id: "_help_navigate", label: "Use ↑↓ arrows to navigate, Enter to select", icon: Chr(0xE76C), shortcut: "", category: "help", callback: "" })
        help.Push({ id: "_help_escape", label: "Press Escape to close the palette", icon: Chr(0xE7E8), shortcut: "Esc", category: "help", callback: "" })
        help.Push({ id: "_help_home", label: "Clear the input to return to home screen", icon: Chr(0xE80F), shortcut: "", category: "help", callback: "" })
        if (searchTerm != "") {
            filtered := []
            for item in help {
                if (InStr(item.label, searchTerm))
                    filtered.Push(item)
            }
            return filtered
        }
        return help
    }

    ShowHome() {
        this.FilterAndRender("")
    }

    ; =========================================================================
    ; RENDERING
    ; =========================================================================

    RenderResults(titleText, items) {
        if (!this.ui)
            return

        this.ui.Update(this.id "_Title", "Text", titleText)

        ; Clear existing results
        this.ui.Update(this.id "_Results", "ClearItems", "")

        this.currentResults := []
        for item in items {
            this.currentResults.Push(item)
        }

        if (!this.HasProp("renderCount"))
            this.renderCount := 0
        this.renderCount++

        ; Dynamically inject result buttons
        idx := 0
        for item in this.currentResults {
            idx++
            btnId := this.id "_Btn_" this.renderCount "_" idx
            isHighlighted := (idx - 1 == this.selectedIndex)

            ; Build icon text
            iconText := item.icon != "" ? item.icon : Chr(0xE756)  ; Default: command icon
            shortcutText := item.HasProp("shortcut") ? item.shortcut : ""
            if (!IsObject(shortcutText))
                shortcutText := String(shortcutText)

            ; Build XAML for the result item
            highlightBg := isHighlighted ? "{DynamicResource ControlBorder}" : "Transparent"

            shortcutBlock := ""
            if (shortcutText != "") {
                shortcutBlock := '<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">'
                for keyPart in StrSplit(shortcutText, "+") {
                    shortcutBlock .= '<Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource ControlBorder}" BorderThickness="1" CornerRadius="3" Padding="4,2" Margin="2,0"><TextBlock Text="' Trim(keyPart) '" Foreground="{DynamicResource TextSub}" FontSize="10" FontFamily="Segoe UI" FontWeight="SemiBold"/></Border>'
                }
                shortcutBlock .= '</StackPanel>'
            }

            xamlStr := '<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="' btnId '" Background="' highlightBg '" BorderThickness="0" HorizontalContentAlignment="Stretch" Cursor="Hand" Margin="0,1"><Button.Template><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,7"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource ControlBorder}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Grid.Column="0" Text="' iconText '" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" FontSize="14" VerticalAlignment="Center" Margin="0,0,10,0"/><TextBlock Grid.Column="1" Text="' item.label '" Foreground="{DynamicResource TextMain}" FontSize="13" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>' shortcutBlock '</Grid></Button>'

            this.ui.Update(this.id "_Results", "AddXamlItem", xamlStr)

            ; Bind click event for this button
            this.ui.Update(btnId, "BindEvent", "Click")
            boundId := item.id
            this.ui.OnEvent(btnId, "Click", ((cmdId, *) => this.ExecuteCommand(cmdId)).Bind(boundId))
        }
    }

    HighlightSelected() {
        if (!this.ui || this.currentResults.Length == 0)
            return

        ; Update backgrounds: selected gets highlight, others transparent
        idx := 0
        for item in this.currentResults {
            idx++
            btnId := this.id "_Btn_" this.renderCount "_" idx
            isHighlighted := (idx - 1 == this.selectedIndex)
            bg := isHighlighted ? "{DynamicResource SolidBorder}" : "Transparent"
            this.ui.Update(btnId, "Background", bg)

            ; Scroll the highlighted item into view
            if (isHighlighted)
                this.ui.Update(btnId, "BringIntoView", "")
        }
    }

    ; =========================================================================
    ; COMMAND EXECUTION
    ; =========================================================================

    ExecuteCommand(id) {
        if (!this.ui)
            return

        ; Skip help items (they're informational only)
        if (SubStr(id, 1, 6) == "_help_") {
            ; For help items: insert the suggested prefix into the search box
            if (id == "_help_commands") {
                this.ui.Update(this.id "_Search", "Text", ">")
                this.ui.Update(this.id "_Search", "Focus", "True")
                this.ui.Update(this.id "_Search", "CaretIndex", "9999")
                return
            }
            return
        }

        ; Track in recent history
        this.AddToRecent(id)

        ; Close palette
        this.Close()

        ; Fire per-command callback if set
        if (this.commands.Has(id) && this.commands[id].callback) {
            try this.commands[id].callback.Call(id)
            return
        }

        ; Fire global callback
        if (HasMethod(this, "OnCommandSelected"))
            this.OnCommandSelected(id)
    }

    AddToRecent(id) {
        ; Remove if already in recent
        newRecent := []
        for rid in this.recentCommands {
            if (rid != id)
                newRecent.Push(rid)
        }
        ; Prepend
        newRecent.InsertAt(1, id)
        ; Trim to max
        if (newRecent.Length > this.maxRecent)
            newRecent.RemoveAt(this.maxRecent + 1)
        this.recentCommands := newRecent
    }

    ; =========================================================================
    ; UTILITY
    ; =========================================================================

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("CommandPalette", { Call: _CommandPalette })
_CommandPalette(this, name := "") {
    comp := XCommandPalette(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; CAROUSEL / MOSAIC
; ==============================================================================

class XCarousel {
    __New(parentXAML, name := "") {
        this.id := name != "" ? name : "Carousel_" XCarousel.Count()
        this.cards := []
        this.ui := ""

        this.sv := parentXAML.Add("ScrollViewer").HorizontalScrollBarVisibility("Auto").VerticalScrollBarVisibility("Disabled").Padding("0,0,0,10").Tag("PassScroll")
        this.sp := this.sv.Add("StackPanel").Orientation("Horizontal").Name(this.id)
    }

    AddCard(title, subtitle, imageUrl := "", width := "160", height := "200") {
        idx := this.cards.Length + 1
        cardId := this.id "_Card_" idx

        ; Outer container with animation support on hover
        bdr := this.sp.Add("Button").Name(cardId).Width(width).Height(height).Margin("0,0,20,0").Cursor("Hand").Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").HorizontalContentAlignment("Stretch").VerticalContentAlignment("Stretch")

        bdr.InjectResources('<Style TargetType="Button"><Setter Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="1" ScaleY="1" CenterX="' (width / 2) '" CenterY="' (height / 2) '"/></Setter.Value></Setter><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="#15FFFFFF"/><Setter TargetName="bg" Property="BorderBrush" Value="#40FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')

        grid := bdr.Add("Grid")
        grid.Rows("*", "Auto")

        ; Image area
        imgBdr := grid.Add("Border").Grid_Row(0).CornerRadius("8,8,0,0").ClipToBounds("True")
        if (imageUrl != "") {
            imgBdr.Add("Image").Source(imageUrl).Stretch("UniformToFill")
        } else {
            ; Fallback gradient
            imgBdr.Background("#1A1A1A")
            imgBdr.Add("TextBlock").Text(Chr(0xE8D6)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("40").Foreground("#444").HorizontalAlignment("Center").VerticalAlignment("Center")
        }

        ; Text area
        textBdr := grid.Add("Border").Grid_Row(1).Background("Transparent").Padding("12,10")
        textSp := textBdr.Add("StackPanel")
        textSp.Add("TextBlock").Text(title).Foreground("{DynamicResource TextMain}").FontWeight("SemiBold").FontSize("14").TextTrimming("CharacterEllipsis").Margin("0,0,0,4")
        textSp.Add("TextBlock").Text(subtitle).Foreground("{DynamicResource TextSub}").FontSize("12").TextTrimming("CharacterEllipsis")

        cardObj := { Title: title, Id: cardId, Index: idx }
        this.cards.Push(cardObj)
        return cardObj
    }

    Bind(ui) {
        this.ui := ui
        for card in this.cards {
            ui.Update(card.Id, "BindEvent", "MouseLeftButtonUp")
            ui.OnEvent(card.Id, "MouseLeftButtonUp", ObjBindMethod(this, "OnCardClicked", card.Id))
        }
    }

    OnCardClicked(cardId, state, ctrl, event) {
        if (HasMethod(this, "OnCardSelected")) {
            for card in this.cards {
                if (card.Id == cardId) {
                    this.OnCardSelected(card.Id, card.Title)
                    break
                }
            }
        }
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("Carousel", { Call: _Carousel })
_Carousel(this, name := "") {
    comp := XCarousel(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; AUTO-REGISTRATION HELPER
; ==============================================================================
; Walks up the element tree to find the XAML_GUI and registers the component.
; Called by all factory methods above.
_AutoRegisterComponent(parentElement, component) {
    try {
        app := parentElement._FindApp()
        if (app != "" && app.HasMethod("RegisterComponent"))
            app.RegisterComponent(component)
    }
}

; ==============================================================================
; AVALONEDIT IDE COMPONENT (Requires XAML_ENABLE_AVALONEDIT := true)
; ==============================================================================
; A robust code editor powered by ICSharpCode.AvalonEdit with:
; - Syntax highlighting for 15+ languages
; - Line numbers, code folding, current line highlighting
; - Autocomplete with WPF-styled popups
; - Find/Replace (Ctrl+F built-in)
; - 6 built-in themes (dark, light, monokai, one-dark, dracula, solarized-dark)
; - LSP-compatible hooks (OnSuggest, OnHover, OnDefinition)
;
; Usage:
;   editor := panel.AvalonEditor("MyIDE", { Language: "cs", Theme: "dark" })
;   editor.Bind(ui)
;   editor.SetText(code)
; ==============================================================================
class XAvalonEditor {
    static Count := 0

    __New(parentXAML, name := "", opts := "") {
        if (!IsSet(XAML_ENABLE_AVALONEDIT) || !XAML_ENABLE_AVALONEDIT)
            throw Error("AvalonEdit is disabled. Set XAML_ENABLE_AVALONEDIT := true in XAML_Config.ahk to use it.")

        XAvalonEditor.Count++
        this.id := name != "" ? name : "AvalonEditor_" XAvalonEditor.Count
        this.parent := parentXAML

        ; Parse options
        this.language := IsObject(opts) && opts.HasProp("Language") ? opts.Language : "cs"
        this.theme := IsObject(opts) && opts.HasProp("Theme") ? opts.Theme : "dark"
        this._lineNumbers := IsObject(opts) && opts.HasProp("ShowLineNumbers") ? opts.ShowLineNumbers : true
        this._showFolding := IsObject(opts) && opts.HasProp("ShowFolding") ? opts.ShowFolding : true
        this._wordWrap := IsObject(opts) && opts.HasProp("WordWrap") ? opts.WordWrap : false
        this.tabWidth := IsObject(opts) && opts.HasProp("TabWidth") ? opts.TabWidth : 4
        this.fontSize := IsObject(opts) && opts.HasProp("FontSize") ? opts.FontSize : 14
        this._readOnly := IsObject(opts) && opts.HasProp("ReadOnly") ? opts.ReadOnly : false

        ; Create a ContentControl that will host the AvalonEdit TextEditor created in C#
        this.host := parentXAML.Add("ContentControl").Name(this.id)
            .HorizontalContentAlignment("Stretch").VerticalContentAlignment("Stretch")

        this.ui := ""
        this._onSuggest := ""
        this._onHover := ""
        this._onDefinition := ""
        this._onTextChanged := ""
        this._onCaretChanged := ""
    }

    Bind(ui) {
        this.ui := ui

        ; Initialize the AvalonEdit control in C# via the AE_Init command
        ui.Update(this.id, "AE_Init", this.theme)

        ; Apply initial settings
        if (this.language != "")
            ui.Update(this.id, "AE_SetLanguage", this.language)
        if (this.tabWidth != 4)
            ui.Update(this.id, "AE_TabSize", String(this.tabWidth))
        if (this.fontSize != 14)
            ui.Update(this.id, "AE_FontSize", String(this.fontSize))
        if (!this._lineNumbers)
            ui.Update(this.id, "AE_ShowLineNumbers", "false")
        if (this._wordWrap)
            ui.Update(this.id, "AE_WordWrap", "true")
        if (this._readOnly)
            ui.Update(this.id, "AE_ReadOnly", "true")

        ; Wire events
        ui.OnEvent(this.id, "TextChanged", ObjBindMethod(this, "_OnTextChangedEvent"))
        ui.OnEvent(this.id, "CaretChanged", ObjBindMethod(this, "_OnCaretChangedEvent"))
    }

    ; --- Content Management ---
    SetText(code) {
        if (!this.ui)
            return
        b64 := this._Base64Encode(code)
        this.ui.Update(this.id, "AE_SetText", b64)
    }

    AppendText(code) {
        if (!this.ui)
            return
        b64 := this._Base64Encode(code)
        this.ui.Update(this.id, "AE_AppendText", b64)
    }

    InsertText(text) {
        if (!this.ui)
            return
        b64 := this._Base64Encode(text)
        this.ui.Update(this.id, "AE_InsertText", b64)
    }

    GetText() {
        if (!this.ui)
            return ""
        this.ui.Update(this.id, "AE_GetText", "")
        ; Returns via TextContent event — caller should listen
    }

    ; --- Language & Theme ---
    SetLanguage(lang) {
        if (!this.ui)
            return
        this.language := lang
        this.ui.Update(this.id, "AE_SetLanguage", lang)
    }

    SetTheme(theme) {
        if (!this.ui)
            return
        this.theme := theme
        this.ui.Update(this.id, "AE_SetTheme", theme)
    }

    ; --- Navigation ---
    GotoLine(line) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_GotoLine", String(line))
    }

    GotoOffset(offset) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_GotoOffset", String(offset))
    }

    Select(start, length) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_Select", start "," length)
    }

    HighlightLine(line) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_HighlightLine", String(line))
    }

    ; --- Editor Options ---
    SetFontSize(size) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_FontSize", String(size))
    }

    SetFontFamily(family) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_FontFamily", family)
    }

    ShowLineNumbers(show := true) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_ShowLineNumbers", show ? "true" : "false")
    }

    SetWordWrap(wrap := true) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_WordWrap", wrap ? "true" : "false")
    }

    SetReadOnly(readOnly := true) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_ReadOnly", readOnly ? "true" : "false")
    }

    SetTabSize(size) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_TabSize", String(size))
    }

    ; --- Folding ---
    UpdateFolding() {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_SetFolding", "")
    }

    FoldAll() {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_FoldAll", "")
    }

    UnfoldAll() {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_UnfoldAll", "")
    }

    ; --- Find / Replace ---
    Find(query := "") {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_Find", query)
    }

    ReplaceAll(find, replace) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "AE_ReplaceAll", find "|||" replace)
    }

    ; --- Autocomplete ---
    ShowCompletion(items) {
        if (!this.ui)
            return
        ; items is an Array of strings or "text|description" pairs
        text := ""
        for item in items {
            text .= item "`n"
        }
        b64 := this._Base64Encode(text)
        this.ui.Update(this.id, "AE_ShowCompletion", b64)
    }

    ; --- LSP-Compatible Hooks ---
    ; Set these to callback functions to enable LSP-like features
    OnSuggest {
        get => this._onSuggest
        set => this._onSuggest := value
    }
    OnHover {
        get => this._onHover
        set => this._onHover := value
    }
    OnDefinition {
        get => this._onDefinition
        set => this._onDefinition := value
    }
    OnTextChanged {
        get => this._onTextChanged
        set => this._onTextChanged := value
    }
    OnCaretChanged {
        get => this._onCaretChanged
        set => this._onCaretChanged := value
    }

    ; --- Event Handlers ---
    _OnTextChangedEvent(state, ctrl, event) {
        if (this._onTextChanged) {
            fn := this._onTextChanged
            fn(this, state, event)
        }
    }

    _OnCaretChangedEvent(state, ctrl, event) {
        if (this._onCaretChanged) {
            fn := this._onCaretChanged
            val := state.Has(event) ? state[event] : ""
            fn(this, state, val)
        }
    }

    ; --- Utilities ---
    _Base64Encode(str) {
        buf := Buffer(StrPut(str, "UTF-8") - 1)
        StrPut(str, buf, "UTF-8")
        size := 0
        DllCall("Crypt32\CryptBinaryToStringA", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &size)
        out := Buffer(size)
        DllCall("Crypt32\CryptBinaryToStringA", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", out.Ptr, "UInt*", &size)
        return StrGet(out, "CP0")
    }
}

XAMLElement.Prototype.DefineProp("AvalonEditor", { Call: _AvalonEditor })
_AvalonEditor(this, name := "", opts := "") {
    comp := XAvalonEditor(this, name, opts)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; DOCUMENT EDITOR COMPONENT (Requires XAML_ENABLE_DOCUMENT := true)
; ==============================================================================
; An Office 365-inspired rich document editor with:
; - Comprehensive formatting toolbar (Bold, Italic, Underline, Strikethrough,
;   Font Family, Font Size, Font Color, Highlight, Alignment, Lists, Indent)
; - DOCX and DOC file import/export
; - Table and image insertion
; - Find/Replace
; - Undo/Redo
; - Word count
; - Zoom control
;
; Usage:
;   editor := panel.DocumentEditor("DocEdit")
;   editor.Bind(ui)
;   editor.Open("C:\path\to\document.docx")
; ==============================================================================
class XDocumentEditor {
    static Count := 0

    __New(parentXAML, name := "") {
        if (!IsSet(XAML_ENABLE_DOCUMENT) || !XAML_ENABLE_DOCUMENT)
            throw Error("Document Editor is disabled. Set XAML_ENABLE_DOCUMENT := true in XAML_Config.ahk to use it.")

        XDocumentEditor.Count++
        this.id := name != "" ? name : "DocEditor_" XDocumentEditor.Count
        this.parent := parentXAML
        this.filePath := ""
        this.zoom := 100
        this.ui := ""
        this.currentTheme := "Normal"

        ; Build the full Office 365-style UI
        this.container := parentXAML.Add("Grid").Name(this.id "_Container").Tag("Normal")

        ; Inject styling resources into container
        styles := '
        (
            <Style TargetType="Button">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                <Setter Property="HorizontalContentAlignment" Value="Center"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Margin="{TemplateBinding Padding}"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bg" Property="Background" Value="#15FFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
                <Style.Triggers>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Dark">
                        <Setter Property="Foreground" Value="#E0E0E0"/>
                    </DataTrigger>
                </Style.Triggers>
            </Style>
            <Style TargetType="ToggleButton">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                <Setter Property="HorizontalContentAlignment" Value="Center"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ToggleButton">
                            <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Margin="{TemplateBinding Padding}"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bg" Property="Background" Value="#15FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsChecked" Value="True">
                                    <Setter TargetName="bg" Property="Background" Value="#25FFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
                <Style.Triggers>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Dark">
                        <Setter Property="Foreground" Value="#E0E0E0"/>
                    </DataTrigger>
                </Style.Triggers>
            </Style>
            <Style x:Key="[[ID]]_PageStyle" TargetType="Border">
                <Setter Property="Background" Value="White"/>
                <Setter Property="BorderBrush" Value="#CCCCCC"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="MinHeight" Value="1056"/>
                <Setter Property="Width" Value="816"/>
                <Setter Property="HorizontalAlignment" Value="Center"/>
                <Style.Triggers>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Theme">
                        <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
                        <Setter Property="BorderBrush" Value="{DynamicResource ControlBorder}"/>
                    </DataTrigger>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Dark">
                        <Setter Property="Background" Value="#1A1A1A"/>
                        <Setter Property="BorderBrush" Value="#2A2A2A"/>
                    </DataTrigger>
                </Style.Triggers>
            </Style>
            <Style x:Key="[[ID]]_RtfStyle" TargetType="RichTextBox">
                <Setter Property="Foreground" Value="Black"/>
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="BorderThickness" Value="0"/>
                <Setter Property="Padding" Value="0"/>
                <Setter Property="Margin" Value="-1,0"/>
                <Setter Property="TextOptions.TextFormattingMode" Value="Ideal"/>
                <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
                <Setter Property="TextOptions.TextHintingMode" Value="Fixed"/>
                <Setter Property="RenderOptions.ClearTypeHint" Value="Enabled"/>
                <Setter Property="UseLayoutRounding" Value="True"/>
                <Style.Triggers>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Theme">
                        <Setter Property="Foreground" Value="{DynamicResource TextMain}"/>
                    </DataTrigger>
                    <DataTrigger Binding="{Binding Tag, ElementName=[[ID]]_Container}" Value="Dark">
                        <Setter Property="Foreground" Value="#E0E0E0"/>
                    </DataTrigger>
                </Style.Triggers>
            </Style>
        )'
        styles := StrReplace(styles, "[[ID]]", this.id)
        this.container.InjectResources(styles)

        this.container.Rows("Auto", "*", "Auto") ; Toolbar, Editor, Status Bar
        ; === TOOLBAR (Google Docs-style) ===
        toolbarBg := this.container.Add("Border").Name(this.id "_ToolbarBg").Grid_Row(0).Background("{DynamicResource BgColor}").Padding("12,4,12,6")
        toolbarInner := toolbarBg.Add("Border").Name(this.id "_ToolbarInner").Background("{DynamicResource SidebarColor}").CornerRadius("6").Padding("6,4").BorderBrush("{DynamicResource ControlBorder}").BorderThickness(1).ClipToBounds("True")

        toolbarGrid := toolbarInner.Add("Grid")
        toolbarGrid.Cols("*", "Auto", "Auto")

        toolbarWrap := toolbarGrid.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center").Grid_Column(0).ClipToBounds("True")

        ; File group — E8A5=Page, E838=OpenLocal, E74E=Save, E28F=SaveCopy
        this._TBtn(toolbarWrap, this.id "_BtnNew", Chr(0xE8A5), "New")
        this._TBtn(toolbarWrap, this.id "_BtnOpen", Chr(0xE838), "Open")
        this._TBtn(toolbarWrap, this.id "_BtnSave", Chr(0xE74E), "Save")
        this._TBtn(toolbarWrap, this.id "_BtnSaveAs", Chr(0xEA35), "Save As")
        this._AddToolbarSep(toolbarWrap)

        ; Undo/Redo — E7A7=Undo, E7A6=Redo
        this._TBtn(toolbarWrap, this.id "_BtnUndo", Chr(0xE7A7), "Undo")
        this._TBtn(toolbarWrap, this.id "_BtnRedo", Chr(0xE7A6), "Redo")
        this._AddToolbarSep(toolbarWrap)

        ; Style dropdown
        styleCb := toolbarWrap.Add("ComboBox").Name(this.id "_StyleSelect").Width(110).Height(30).VerticalAlignment("Center").Margin("4,0")
        styleCb.Add("ComboBoxItem").Content("Body Text").Tag("Body")
        styleCb.Add("ComboBoxItem").Content("Header 1").Tag("H1")
        styleCb.Add("ComboBoxItem").Content("Header 2").Tag("H2")
        styleCb.Add("ComboBoxItem").Content("Header 3").Tag("H3")
        styleCb.Add("ComboBoxItem").Content("Header 4").Tag("H4")
        styleCb.Add("ComboBoxItem").Content("Header 5").Tag("H5")
        styleCb.Add("ComboBoxItem").Content("Header 6").Tag("H6")
        styleCb.SelectedIndex(0)

        ; Font family combo (IsEditable allows displaying fonts not in the list, IsReadOnly prevents arbitrary typing)
        fontCb := toolbarWrap.Add("ComboBox").Name(this.id "_FontFamily").Width(220).Height(30).VerticalAlignment("Center").Margin("4,0").IsEditable("True").MaxDropDownHeight(500)

        fallbackItem := fontCb.Add("ComboBoxItem").Name(this.id "_FallbackFont").Visibility("Collapsed").Tag("Unknown")
        fbSp := fallbackItem.Add("StackPanel").Orientation("Horizontal")
        fbSp.Add("TextBlock").Text(Chr(0xE7BA)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Foreground("Red").Margin("0,0,4,0").VerticalAlignment("Center").ToolTip("Font not installed locally")
        fbSp.Add("TextBlock").Name(this.id "_FallbackFontText").Text("Unknown").VerticalAlignment("Center").FontStyle("Italic")

        systemFonts := XDocumentEditor._GetSystemFonts()
        for f in systemFonts {
            fontCb.Add("ComboBoxItem").Content(f).FontFamily(f).FontSize(14).Tag(f)
        }
        defaultIdx := 0
        for idx, f in systemFonts {
            if (f = "Segoe UI") {
                defaultIdx := idx - 1
                break
            }
        }
        fontCb.SelectedIndex(defaultIdx)

        ; Font size combo
        sizeCb := toolbarWrap.Add("ComboBox").Name(this.id "_FontSize").Width(65).Height(30).VerticalAlignment("Center").Margin("4,0")
        for s in ["8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "36", "48", "72"]
            sizeCb.Add("ComboBoxItem").Content(s)
        sizeCb.SelectedIndex(5) ; default 14

        this._AddToolbarSep(toolbarWrap)

        ; Primary text formatting — B/I/U
        this._TTextBtn(toolbarWrap, this.id "_BtnBold", "B", "Bold", "Bold", "Normal")
        this._TTextBtn(toolbarWrap, this.id "_BtnItalic", "I", "Italic", "Normal", "Italic")
        this._TTextBtn(toolbarWrap, this.id "_BtnUnderline", "U", "Underline", "Normal", "Normal")

        ; Font Color Picker (Primary)
        fontColorBtn := this._TTextToggleBtn(toolbarWrap, this.id "_BtnFontColor", "A", "Font Color", "Bold", "Normal")
        this.fontColorPicker := fontColorBtn.ColorPickerPopover("#FFFF0000").OnChange(ObjBindMethod(this, "_OnLiveColor", "FontColor"))
        this._AddToolbarSep(toolbarWrap)

        ; Primary alignment buttons (wrapped for responsive visibility)
        alignGrp := toolbarWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_ToolbarAlignGrp")
        this._TBtn(alignGrp, this.id "_BtnAlignL2", Chr(0xE8E4), "Align Left")
        this._TBtn(alignGrp, this.id "_BtnAlignC2", Chr(0xE8E3), "Align Center")
        this._TBtn(alignGrp, this.id "_BtnAlignR2", Chr(0xE8E2), "Align Right")
        this._AddToolbarSep(alignGrp)

        ; Primary list buttons (wrapped for responsive visibility)
        listGrp := toolbarWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_ToolbarListGrp")
        this._TBtn(listGrp, this.id "_BtnBullet2", Chr(0xE8FD), "Bullet List")
        this._TBtn(listGrp, this.id "_BtnNumber2", Chr(0xE9D5), "Numbered List")
        this._AddToolbarSep(listGrp)

        ; Primary insert shortcuts (wrapped for responsive visibility)
        insertGrp := toolbarWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_ToolbarInsertGrp")
        this._TBtn(insertGrp, this.id "_BtnImage2", Chr(0xEB9F), "Insert Image")
        this._TBtn(insertGrp, this.id "_BtnLink2", Chr(0xE71B), "Insert Hyperlink")
        this._AddToolbarSep(insertGrp)

        ; === RIGHT-SIDE TOOLBAR (always visible) ===
        toolbarRight := toolbarGrid.Add("StackPanel").Orientation("Horizontal").VerticalAlignment("Center").Grid_Column(1)

        this.outlineBtn := this._TToggleBtn(toolbarRight, this.id "_BtnOutline", Chr(0xE81E), "Document Outline")

        ; "More options" popover containing secondary/insert tools
        moreBtn := this._TToggleBtn(toolbarRight, this.id "_BtnMore", Chr(0xE712), "More Formatting Options")
        morePopover := moreBtn.AddRichPopover()
        morePopover.MinWidth(420).Padding("16")

        moreSp := morePopover.Add("StackPanel")

        ; --- Text Formatting Section ---
        moreSp.Add("TextBlock").Text("TEXT FORMATTING").FontWeight("Bold").FontSize(10).Foreground("{DynamicResource TextSub}").Margin("0,0,0,8")
        moreTextWrap := moreSp.Add("WrapPanel").Orientation("Horizontal").Margin("0,0,0,8")

        ; Highlight Color
        highlightBtn := this._TToggleBtn(moreTextWrap, this.id "_BtnHighlight", Chr(0xE7E6), "Highlight")
        this.highlightPicker := highlightBtn.ColorPickerPopover("#FFFFFF00").OnChange(ObjBindMethod(this, "_OnLiveColor", "Highlight"))

        this._TBtn(moreTextWrap, this.id "_BtnClear", Chr(0xECC9), "Clear Formatting")
        this._AddToolbarSep(moreTextWrap)

        ; Strikethrough
        this._TTextBtn(moreTextWrap, this.id "_BtnStrike", "S", "Strikethrough", "Normal", "Normal")
        ; Superscript/Subscript
        this._TTextBtn(moreTextWrap, this.id "_BtnSuper", "x²", "Superscript", "Normal", "Normal")
        this._TTextBtn(moreTextWrap, this.id "_BtnSub", "x₂", "Subscript", "Normal", "Normal")

        ; --- Alignment Section ---
        moreSp.Add("Border").Height(1).Background("{DynamicResource ControlBorder}").Margin("0,4,0,8")
        moreSp.Add("TextBlock").Text("ALIGNMENT / LISTS").FontWeight("Bold").FontSize(10).Foreground("{DynamicResource TextSub}").Margin("0,0,0,8")
        moreAlignWrap := moreSp.Add("WrapPanel").Orientation("Horizontal").Margin("0,0,0,8")

        ; Alignment (duplicates from main toolbar)
        popAlignGrp := moreAlignWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_PopoverAlignGrp").Visibility("Collapsed")
        this._TBtn(popAlignGrp, this.id "_BtnAlignL", Chr(0xE8E4), "Align Left")
        this._TBtn(popAlignGrp, this.id "_BtnAlignC", Chr(0xE8E3), "Align Center")
        this._TBtn(popAlignGrp, this.id "_BtnAlignR", Chr(0xE8E2), "Align Right")

        ; Unique to popover
        this._TTextBtn(moreAlignWrap, this.id "_BtnAlignJ", "☰", "Justify", "Normal", "Normal")
        this._AddToolbarSep(moreAlignWrap)

        ; Lists (duplicates)
        popListGrp := moreAlignWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_PopoverListGrp").Visibility("Collapsed")
        this._TBtn(popListGrp, this.id "_BtnBullet", Chr(0xE8FD), "Bullet List")
        this._TBtn(popListGrp, this.id "_BtnNumber", Chr(0xE9D5), "Numbered List")

        ; Unique to popover
        this._TBtn(moreAlignWrap, this.id "_BtnIndent", Chr(0xE7FD), "Increase Indent")
        this._TBtn(moreAlignWrap, this.id "_BtnOutdent", Chr(0xE7FC), "Decrease Indent")

        ; --- Insert Section ---
        moreSp.Add("Border").Height(1).Background("{DynamicResource ControlBorder}").Margin("0,4,0,8")
        moreSp.Add("TextBlock").Text("INSERT").FontWeight("Bold").FontSize(10).Foreground("{DynamicResource TextSub}").Margin("0,0,0,8")
        moreInsertWrap := moreSp.Add("WrapPanel").Orientation("Horizontal").Margin("0,0,0,8")

        this._TBtn(moreInsertWrap, this.id "_BtnTable", Chr(0xE8A4), "Insert Table (3x3)")

        ; Insert (duplicates)
        popInsertGrp := moreInsertWrap.Add("StackPanel").Orientation("Horizontal").Name(this.id "_PopoverInsertGrp").Visibility("Collapsed")
        this._TBtn(popInsertGrp, this.id "_BtnImage", Chr(0xEB9F), "Insert Image")
        this._TBtn(popInsertGrp, this.id "_BtnLink", Chr(0xE71B), "Insert Hyperlink")

        ; Unique to popover
        this._TTextBtn(moreInsertWrap, this.id "_BtnHR", "—", "Insert Horizontal Rule", "Normal", "Normal")
        this._TBtn(moreInsertWrap, this.id "_BtnFind", Chr(0xE721), "Find")

        ; --- Table Tools Section ---
        moreSp.Add("Border").Height(1).Background("{DynamicResource ControlBorder}").Margin("0,4,0,8")
        moreSp.Add("TextBlock").Text("TABLE TOOLS").FontWeight("Bold").FontSize(10).Foreground("{DynamicResource TextSub}").Margin("0,0,0,8")
        moreTableWrap := moreSp.Add("WrapPanel").Orientation("Horizontal")

        ; Table tools
        cellBgBtn := this._TTextToggleBtn(moreTableWrap, this.id "_BtnCellColor", "Cell Bg", "Table Cell Background Color", "Normal", "Normal")
        this.cellBgPicker := cellBgBtn.ColorPickerPopover("#FFFFFFFF").OnChange(ObjBindMethod(this, "_OnLiveColor", "TableCellBackground"))

        this._TTextBtn(moreTableWrap, this.id "_BtnMergeCells", "Merge " Chr(0x2192), "Merge Table Cells Horizontally", "Normal", "Normal")
        this._AddToolbarSep(moreTableWrap)
        this._TTextBtn(moreTableWrap, this.id "_BtnAddRowBelow", Chr(0xE710) " Row+", "Add Row Below", "Normal", "Normal")
        this._TTextBtn(moreTableWrap, this.id "_BtnAddRowAbove", Chr(0xE710) " Row^", "Add Row Above", "Normal", "Normal")
        this._TTextBtn(moreTableWrap, this.id "_BtnAddColRight", Chr(0xE710) " Col+", "Add Column Right", "Normal", "Normal")
        this._AddToolbarSep(moreTableWrap)
        this._TTextBtn(moreTableWrap, this.id "_BtnDelRow", Chr(0xE74D) " Row", "Delete Row", "Normal", "Normal")
        this._TTextBtn(moreTableWrap, this.id "_BtnDelCol", Chr(0xE74D) " Col", "Delete Column", "Normal", "Normal")

        ; Chevron toggle button to collapse/expand menu bar (Google Docs style)
        this.toggleMenuBtn := toolbarGrid.Add("ToggleButton").Name(this.id "_BtnToggleMenu").Grid_Column(2)
            .Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextSub}")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(11).Width("30").Height("28")
            .Cursor("Hand").Focusable("False").Margin("4,0").VerticalAlignment("Center")
            .Content(Chr(0xE70E)).ToolTip("Hide Menu Bar") ; Default is Chevron Up

        ; === EDITOR AREA (Google Docs-style centered page on canvas) ===
        editorWrapper := this.container.Add("Grid").Name(this.id "_EditorWrapper").Grid_Row(1).Background("{DynamicResource DropdownBg}")
        editorWrapper.Cols("Auto", "*")

        this.outlinePane := editorWrapper.Add("Border").Name(this.id "_OutlinePane").Grid_Column(0).Width(280).Background("{DynamicResource SidebarColor}").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,0,1,0").Visibility("Collapsed")

        outlinePanel := this.outlinePane.Add("StackPanel").Margin("16")
        outlinePanel.Add("TextBlock").Text("DOCUMENT OUTLINE").FontWeight("Bold").FontSize(11).Foreground("{DynamicResource TextSub}").Margin("0,0,0,16")
        outlineSv := outlinePanel.Add("ScrollViewer").VerticalScrollBarVisibility("Auto")
        this.outlineSp := outlineSv.Add("StackPanel").Name(this.id "_OutlineContainer")
        this.outlineSp.Add("TextBlock").Text("No headings in this document.").Foreground("{DynamicResource TextSub}").FontSize(12).FontStyle("Italic").Margin("0,4")

        editorCanvas := editorWrapper.Add("Border").Grid_Column(1)
        editorSv := editorCanvas.Add("ScrollViewer").VerticalScrollBarVisibility("Auto").HorizontalScrollBarVisibility("Disabled")
        editorCenter := editorSv.Add("Grid").HorizontalAlignment("Center").Margin("0,30,0,60")
        pageBorder := editorCenter.Add("Border").Name(this.id "_PageBorder").Style("{StaticResource " this.id "_PageStyle}")

        this.rtb := pageBorder.Add("RichTextBox").Name(this.id).FontFamily("Segoe UI").FontSize(14)
            .AcceptsReturn("True").VerticalScrollBarVisibility("Disabled").HorizontalScrollBarVisibility("Disabled")
            .Style("{StaticResource " this.id "_RtfStyle}").IsInactiveSelectionHighlightEnabled("True")
            .IsDocumentEnabled("False")

        ; === STATUS BAR ===
        statusBg := this.container.Add("Border").Name(this.id "_StatusBg").Grid_Row(2).Background("{DynamicResource ControlBg}").Height(28).BorderBrush("{DynamicResource ControlBorder}").BorderThickness("0,1,0,0")
        statusGrid := statusBg.Add("Grid")
        statusGrid.Cols("Auto", "*", "Auto")

        statusLeft := statusGrid.Add("StackPanel").Orientation("Horizontal").Grid_Column(0).Margin("15,0")
        statusLeft.Add("TextBlock").Name(this.id "_WordCount").Text("Words: 0").Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Center")

        statusCenter := statusGrid.Add("StackPanel").Orientation("Horizontal").Name(this.id "_StatusPageNav").Grid_Column(1).HorizontalAlignment("Center").Visibility("Collapsed")
        this._TBtn(statusCenter, this.id "_BtnPrevPage", Chr(0xE76B), "Previous Page")
        statusCenter.Add("TextBlock").Name(this.id "_PageNumberText").Text("Page 1 of 1").Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Center").Margin("8,0")
        this._TBtn(statusCenter, this.id "_BtnNextPage", Chr(0xE76C), "Next Page")

        statusRight := statusGrid.Add("StackPanel").Orientation("Horizontal").Grid_Column(2).Margin("0,0,15,0").Visibility("Collapsed")
        this._TBtn(statusRight, this.id "_BtnZoomOut", Chr(0xE71F), "Zoom Out")
        statusRight.Add("TextBlock").Name(this.id "_ZoomLevel").Text("100%").Foreground("{DynamicResource TextSub}").FontSize(12).VerticalAlignment("Center").Margin("8,0")
        this._TBtn(statusRight, this.id "_BtnZoomIn", Chr(0xE710), "Zoom In")

        ; === FIND & REPLACE PANEL ===
        this.findPanel := this.container.Add("Border").Name(this.id "_FindPanel")
            .Grid_Row("1").HorizontalAlignment("Right").VerticalAlignment("Top").Margin("0,10,25,0")
            .Background("{DynamicResource DropdownBg}").BorderBrush("{DynamicResource ControlBorder}")
            .BorderThickness(1).CornerRadius(6).Padding("16").Visibility("Collapsed")
            .SetProp("Panel.ZIndex", "50")

        this.findPanel.Add("Border.Effect").Add("DropShadowEffect").BlurRadius(20).ShadowDepth(4).Opacity(0.15)

        findSp := this.findPanel.Add("StackPanel").Width(280)

        ; Header
        findHeader := findSp.Add("Grid").Margin("0,0,0,12")
        findHeader.Cols("*", "Auto")
        findHeader.Add("TextBlock").Text("Find and Replace").FontWeight("Bold").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center")
        closeBtn := findHeader.Add("Button").Name(this.id "_BtnCloseFind").Content(Chr(0xE711)).Grid_Column(1)
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Background("Transparent").BorderThickness(0)
            .Foreground("{DynamicResource TextSub}").Cursor("Hand").Padding("4,2")

        ; Find Input row
        findSp.Add("TextBlock").Text("Find").Foreground("{DynamicResource TextSub}").FontSize(11).Margin("0,0,0,4")
        findSp.Add("TextBox").Name(this.id "_FindInput").Padding("8,6").Margin("0,0,0,12").Background("{DynamicResource DropdownBg}")

        ; Replace Input row
        findSp.Add("TextBlock").Text("Replace with").Foreground("{DynamicResource TextSub}").FontSize(11).Margin("0,0,0,4")
        findSp.Add("TextBox").Name(this.id "_ReplaceInput").Padding("8,6").Margin("0,0,0,16").Background("{DynamicResource DropdownBg}")

        ; Preview Replace Checkbox
        findSp.Add("CheckBox").Name(this.id "_PreviewCheckbox").Content("Preview Replace").Margin("0,0,0,4").Foreground("{DynamicResource TextSub}").FontSize(11).Cursor("Hand")
        ; Match Case Checkbox (unchecked = case insensitive by default)
        findSp.Add("CheckBox").Name(this.id "_MatchCaseCheckbox").Content("Match Case").Margin("0,0,0,12").Foreground("{DynamicResource TextSub}").FontSize(11).Cursor("Hand")

        ; Buttons
        btnGrid := findSp.Add("Grid").Name(this.id "_NormalActionGrid")
        btnGrid.Cols("Auto", "*", "Auto")

        findBtns := btnGrid.Add("StackPanel").Orientation("Horizontal").Grid_Column(0)
        findBtns.Add("Button").Name(this.id "_BtnFindPrev").Content(Chr(0xE74A)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Padding("8,6").Margin("0,0,4,0").ToolTip("Find Previous").Background("Transparent").BorderThickness(1).Cursor("Hand")
        findBtns.Add("Button").Name(this.id "_BtnFindNext").Content(Chr(0xE74B)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").Padding("8,6").Margin("0,0,0,0").ToolTip("Find Next").Background("Transparent").BorderThickness(1).Cursor("Hand")

        replBtns := btnGrid.Add("StackPanel").Orientation("Horizontal").Grid_Column(2).HorizontalAlignment("Right")
        replBtns.Add("Button").Name(this.id "_BtnReplace").Content("Replace").Padding("12,6").Margin("0,0,4,0").Background("Transparent").BorderThickness(1).Cursor("Hand")
        replBtns.Add("Button").Name(this.id "_BtnReplaceAll").Content("All").Padding("12,6").Background("Transparent").BorderThickness(1).Cursor("Hand")

        btnGrid.Add("TextBlock").Name(this.id "_MatchCount").Text("").Grid_Column(1).VerticalAlignment("Center").HorizontalAlignment("Center").Foreground("{DynamicResource TextSub}").FontSize(11)

        ; Preview panel (Confirm / Cancel)
        previewPanel := findSp.Add("StackPanel").Name(this.id "_PreviewPanel").Visibility("Collapsed").Margin("0,12,0,0")
        previewPanel.Add("Border").Height(1).Background("{DynamicResource ControlBorder}").Margin("0,0,0,12")
        previewPanel.Add("TextBlock").Text("Preview Mode Active").FontWeight("Bold").Foreground("{DynamicResource Accent}").Margin("0,0,0,4").FontSize(11)
        previewPanel.Add("TextBlock").Text("Confirm or Cancel the replacement:").Foreground("{DynamicResource TextSub}").Margin("0,0,0,12").FontSize(11)

        pBtnGrid := previewPanel.Add("Grid")
        pBtnGrid.Cols("*", "Auto")

        pConfirmBtn := pBtnGrid.Add("Button").Name(this.id "_BtnConfirmReplace").Content("Confirm").Padding("12,6").HorizontalAlignment("Left").Background("{DynamicResource Accent}").Foreground("White").BorderThickness(0).Cursor("Hand")
        pCancelBtn := pBtnGrid.Add("Button").Name(this.id "_BtnCancelReplace").Content("Cancel").Padding("12,6").Grid_Column(1).HorizontalAlignment("Right").Background("Transparent").BorderThickness(1).Cursor("Hand")
    }

    _TBtn(parent, name, content, tooltip) {
        btn := parent.Add("Button").Name(name).Content(content)
            .Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            .Padding("8,4").Margin("1,0").Cursor("Hand").ToolTip(tooltip).Focusable("False")
        return btn
    }

    _TTextBtn(parent, name, content, tooltip, fontWeight := "Normal", fontStyle := "Normal") {
        btn := parent.Add("Button").Name(name).Content(content)
            .Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}")
            .FontFamily("Segoe UI").FontSize(13)
            .Padding("8,4").Margin("1,0").Cursor("Hand").ToolTip(tooltip).Focusable("False")
            .FontWeight(fontWeight).FontStyle(fontStyle)
        return btn
    }

    _TToggleBtn(parent, name, iconChar, tooltip) {
        btn := parent.Add("ToggleButton").Name(name).Content(iconChar)
            .Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}")
            .FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize(14)
            .Padding("8,4").Margin("1,0").Cursor("Hand").ToolTip(tooltip).Focusable("False")
        return btn
    }

    _TTextToggleBtn(parent, name, content, tooltip, fontWeight := "Normal", fontStyle := "Normal") {
        btn := parent.Add("ToggleButton").Name(name).Content(content)
            .Background("Transparent").BorderThickness(0).Foreground("{DynamicResource TextMain}")
            .FontFamily("Segoe UI").FontSize(13)
            .Padding("8,4").Margin("1,0").Cursor("Hand").ToolTip(tooltip).Focusable("False")
            .FontWeight(fontWeight).FontStyle(fontStyle)
        return btn
    }

    _AddToolbarSep(parent) {
        parent.Add("Border").Width(1).Height(20).Background("{DynamicResource ControlBorder}").Margin("6,0").VerticalAlignment("Center")
    }

    Bind(ui) {
        if (this.HasOwnProp("_bound") && this._bound)
            return
        this._bound := true
        this.ui := ui

        ; Wire toolbar button events
        ui.OnEvent(this.id "_BtnNew", "Click", (*) => this._Cmd("NewDocument"))
        ui.OnEvent(this.id "_BtnOpen", "Click", (*) => this._OpenFile())
        ui.OnEvent(this.id "_BtnSave", "Click", (*) => this._SaveFile())
        ui.OnEvent(this.id "_BtnSaveAs", "Click", (*) => this._SaveFileAs())
        ui.OnEvent(this.id "_BtnUndo", "Click", (*) => this._Cmd("Undo"))
        ui.OnEvent(this.id "_BtnRedo", "Click", (*) => this._Cmd("Redo"))

        ; Formatting
        ui.OnEvent(this.id "_BtnBold", "Click", (*) => this._Format("Bold"))
        ui.OnEvent(this.id "_BtnItalic", "Click", (*) => this._Format("Italic"))
        ui.OnEvent(this.id "_BtnUnderline", "Click", (*) => this._Format("Underline"))
        ui.OnEvent(this.id "_BtnStrike", "Click", (*) => this._Format("Strikethrough"))
        ui.OnEvent(this.id "_BtnSuper", "Click", (*) => this._Format("Superscript"))
        ui.OnEvent(this.id "_BtnSub", "Click", (*) => this._Format("Subscript"))
        ui.OnEvent(this.id "_BtnClear", "Click", (*) => this._Format("ClearFormatting"))

        ; Alignment (popover)
        ui.OnEvent(this.id "_BtnAlignL", "Click", (*) => this._Format("AlignLeft"))
        ui.OnEvent(this.id "_BtnAlignC", "Click", (*) => this._Format("AlignCenter"))
        ui.OnEvent(this.id "_BtnAlignR", "Click", (*) => this._Format("AlignRight"))
        ui.OnEvent(this.id "_BtnAlignJ", "Click", (*) => this._Format("AlignJustify"))

        ; Alignment (primary toolbar)
        ui.OnEvent(this.id "_BtnAlignL2", "Click", (*) => this._Format("AlignLeft"))
        ui.OnEvent(this.id "_BtnAlignC2", "Click", (*) => this._Format("AlignCenter"))
        ui.OnEvent(this.id "_BtnAlignR2", "Click", (*) => this._Format("AlignRight"))

        ; Lists and indent (popover)
        ui.OnEvent(this.id "_BtnBullet", "Click", (*) => this._Format("BulletList"))
        ui.OnEvent(this.id "_BtnNumber", "Click", (*) => this._Format("NumberList"))
        ui.OnEvent(this.id "_BtnIndent", "Click", (*) => this._Format("IncreaseIndent"))
        ui.OnEvent(this.id "_BtnOutdent", "Click", (*) => this._Format("DecreaseIndent"))

        ; Lists (primary toolbar)
        ui.OnEvent(this.id "_BtnBullet2", "Click", (*) => this._Format("BulletList"))
        ui.OnEvent(this.id "_BtnNumber2", "Click", (*) => this._Format("NumberList"))

        ; Font color / highlight are now handled by live popovers directly via OnChange

        ; Insert (popover)
        ui.OnEvent(this.id "_BtnTable", "Click", (*) => this._Cmd("InsertTable", "3,3"))
        ui.OnEvent(this.id "_BtnImage", "Click", (*) => this._InsertImage())
        ui.OnEvent(this.id "_BtnLink", "Click", (*) => this._InsertLinkDialog())
        ui.OnEvent(this.id "_BtnHR", "Click", (*) => this._Cmd("InsertHR"))

        ; Insert (primary toolbar)
        ui.OnEvent(this.id "_BtnImage2", "Click", (*) => this._InsertImage())
        ui.OnEvent(this.id "_BtnLink2", "Click", (*) => this._InsertLinkDialog())

        ; Find
        ui.OnEvent(this.id "_BtnFind", "Click", (*) => this._FindDialog())

        ; Font family change
        ui.Track(this.id "_FontFamily")
        ui.OnEvent(this.id "_FontFamily", "SelectionChanged", ObjBindMethod(this, "_OnFontFamilyChanged"))

        ; Font size change
        ui.Track(this.id "_FontSize")
        ui.OnEvent(this.id "_FontSize", "SelectionChanged", ObjBindMethod(this, "_OnFontSizeChanged"))

        ; Zoom
        ui.OnEvent(this.id "_BtnZoomIn", "Click", (*) => this._SetZoom(this.zoom + 10))
        ui.OnEvent(this.id "_BtnZoomOut", "Click", (*) => this._SetZoom(this.zoom - 10))

        ; Toggle Menu Bar
        ui.OnEvent(this.id "_BtnToggleMenu", "Click", ObjBindMethod(this, "_OnToggleMenu"))

        ; Document events
        ui.OnEvent(this.id, "DocumentLoaded", ObjBindMethod(this, "_OnDocLoaded"))
        ui.OnEvent(this.id, "DocumentSaved", ObjBindMethod(this, "_OnDocSaved"))
        ui.OnEvent(this.id, "DocumentError", ObjBindMethod(this, "_OnDocError"))
        ui.OnEvent(this.id, "WordCount", ObjBindMethod(this, "_OnWordCount"))

        ui.OnEvent(this.id "_BtnOutline", "Click", ObjBindMethod(this, "_OnOutlineToggle"))
        ui.OnEvent(this.id "_BtnMergeCells", "Click", (*) => this._Format("TableMergeRight"))
        ui.OnEvent(this.id "_BtnAddRowBelow", "Click", (*) => this._Format("TableAddRowBelow"))
        ui.OnEvent(this.id "_BtnAddRowAbove", "Click", (*) => this._Format("TableAddRowAbove"))
        ui.OnEvent(this.id "_BtnAddColRight", "Click", (*) => this._Format("TableAddColumnRight"))
        ui.OnEvent(this.id "_BtnDelRow", "Click", (*) => this._Format("TableDeleteRow"))
        ui.OnEvent(this.id "_BtnDelCol", "Click", (*) => this._Format("TableDeleteColumn"))

        ; Find & Replace panel events
        ui.Track(this.id "_FindInput")
        ui.Track(this.id "_ReplaceInput")
        ui.Track(this.id "_PreviewCheckbox")
        ui.Track(this.id "_MatchCaseCheckbox")
        ui.OnEvent(this.id "_BtnCloseFind", "Click", (*) => this._CloseFindDialog())
        ui.OnEvent(this.id "_BtnFindNext", "Click", (state, *) => this._FindAction("Next", state))
        ui.OnEvent(this.id "_BtnFindPrev", "Click", (state, *) => this._FindAction("Prev", state))
        ui.OnEvent(this.id "_BtnReplace", "Click", (state, *) => this._FindAction("Replace", state))
        ui.OnEvent(this.id "_BtnReplaceAll", "Click", (state, *) => this._FindAction("ReplaceAll", state))
        ui.OnEvent(this.id "_BtnConfirmReplace", "Click", (state, *) => this._FindAction("ConfirmReplace", state))
        ui.OnEvent(this.id "_BtnCancelReplace", "Click", (state, *) => this._FindAction("CancelReplace", state))
        ui.OnEvent(this.id "_FindInput", "TextChanged", (state, *) => this._OnFindTextChanged(state)).Limit(4)

        ; Live preview: checkbox toggle + replace text change
        ui.OnEvent(this.id "_PreviewCheckbox", "Checked", (state, *) => this._UpdateLivePreview(state))
        ui.OnEvent(this.id "_PreviewCheckbox", "Unchecked", (state, *) => this._UpdateLivePreview(state))
        ui.OnEvent(this.id "_ReplaceInput", "TextChanged", (state, *) => this._OnReplaceTextChanged(state)).Limit(4)

        ; Format matching events
        ui.OnEvent(this.id "_StyleSelect", "SelectionChanged", (state, ctrl, event) => this._OnStyleChanged(state))
        ui.OnEvent(this.id, "SelectionFormat", ObjBindMethod(this, "_OnSelectionFormat"))

        ; Initialize new document
        ui.Update(this.id, "Doc_NewDocument", "")

        ; Setup responsive toolbar — groups hidden in reverse priority order when toolbar narrows
        ; Insert first (least priority), then lists, then alignment (most priority = hidden last)
        ui.Update(this.id, "Doc_SetupToolbarResponsive",
            this.id "_ToolbarInsertGrp|" this.id "_PopoverInsertGrp,"
            this.id "_ToolbarListGrp|" this.id "_PopoverListGrp,"
            this.id "_ToolbarAlignGrp|" this.id "_PopoverAlignGrp")
    }

    ; --- Public API ---
    Open(filePath) {
        if (!this.ui)
            return

        originalPath := filePath
        isDoc := (LTrim(String(SubStr(filePath, -3)), ".") = "doc")

        if (isDoc) {
            try {
                wordApp := ComObject("Word.Application")
                wordApp.Visible := false
                wordDoc := wordApp.Documents.Open(filePath)

                tempDir := A_Temp "\AhkDocEditor"
                if !DirExist(tempDir)
                    DirCreate(tempDir)

                tempPath := tempDir "\temp_converted_" A_TickCount ".docx"
                wordDoc.SaveAs2(tempPath, 12) ; 12 = wdFormatXMLDocument (docx)
                wordDoc.Close(false)
                wordApp.Quit()

                filePath := tempPath
            } catch {
                ; Fallback to bridge
            }
        }

        this.filePath := originalPath
        this.ui.Update(this.id, "Doc_Import", filePath)
        ; Re-apply dark mode if it was active (new document replaces all elements)
        if (this.currentTheme == "Dark") {
            this.ui.Update(this.id, "Doc_ApplyDarkMode", "")
        }
    }

    Save(filePath := "") {
        if (!this.ui)
            return
        if (filePath == "" && this.filePath != "")
            filePath := this.filePath
        if (filePath == "")
            return this._SaveFileAs()

        originalPath := filePath
        isDoc := (LTrim(String(SubStr(filePath, -3)), ".") = "doc")

        if (isDoc) {
            tempDir := A_Temp "\AhkDocEditor"
            if !DirExist(tempDir)
                DirCreate(tempDir)
            tempPath := tempDir "\temp_save_" A_TickCount ".docx"

            this.filePath := tempPath
            wasDark := this.currentTheme == "Dark"
            if (wasDark)
                this.ui.Update(this.id, "Doc_RestoreColors", "")
            this.ui.Update(this.id, "Doc_Export", tempPath)
            if (wasDark)
                this.ui.Update(this.id, "Doc_ApplyDarkMode", "")

            try {
                wordApp := ComObject("Word.Application")
                wordApp.Visible := false
                wordDoc := wordApp.Documents.Open(tempPath)
                wordDoc.SaveAs2(originalPath, 0) ; 0 = wdFormatDocument (.doc)
                wordDoc.Close(false)
                wordApp.Quit()

                try FileDelete(tempPath)
            } catch as err {
                MsgBox("Failed to save as .doc: " err.Message, "Document Editor")
            }

            this.filePath := originalPath
        } else {
            this.filePath := filePath
            wasDark := this.currentTheme == "Dark"
            if (wasDark)
                this.ui.Update(this.id, "Doc_RestoreColors", "")
            this.ui.Update(this.id, "Doc_Export", filePath)
            if (wasDark)
                this.ui.Update(this.id, "Doc_ApplyDarkMode", "")
        }
    }

    NewDocument() {
        if (!this.ui)
            return
        this.filePath := ""
        this.ui.Update(this.id, "Doc_NewDocument", "")
    }

    InsertTable(rows := 3, cols := 3) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_InsertTable", rows "," cols)
    }

    InsertImage(path) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_InsertImage", path)
    }

    FindText(query) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_Find", query)
    }

    ReplaceAll(find, replace) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_ReplaceAll", find "|||" replace)
    }

    QueryDOM(selector) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_QueryDOM", selector)
    }

    HighlightStyle(styleId, colorName := "Yellow") {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_HighlightStyle", styleId "|" colorName)
    }

    AuditLinks() {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_AuditLinks", "")
    }

    RewriteLinks(mapping) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_RewriteLinks", mapping)
    }

    CompileTemplate(payload) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_CompileTemplate", payload)
    }

    StandardizeFont(fromFont, toFont) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_StandardizeFont", fromFont "|" toFont)
    }

    GetWordCount() {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_GetWordCount", "")
    }

    SetZoom(percent) {
        this._SetZoom(percent)
    }

    ; --- Internal ---
    _Cmd(cmd, val := "") {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_" cmd, val)
    }

    _Format(fmt) {
        if (!this.ui)
            return
        this.ui.Update(this.id, "Doc_Format", fmt)
    }

    _SetZoom(percent) {
        if (!this.ui)
            return
        this.zoom := Max(25, Min(400, percent))
        this.ui.Update(this.id, "Doc_Zoom", String(this.zoom))
        this.ui.Update(this.id "_ZoomLevel", "Text", this.zoom "%")
    }

    _OpenFile() {
        filePath := FileSelect(1, , "Open Document", "Document Files (*.docx; *.doc; *.rtf; *.txt)")
        if (filePath != "")
            this.Open(filePath)
    }

    _SaveFile() {
        if (this.filePath != "")
            this.Save(this.filePath)
        else
            this._SaveFileAs()
    }

    _SaveFileAs() {
        filePath := FileSelect("S", , "Save Document", "Word Document (*.docx)|Rich Text (*.rtf)|Plain Text (*.txt)")
        if (filePath != "") {
            if (!InStr(filePath, "."))
                filePath .= ".docx"
            this.Save(filePath)
        }
    }

    _InsertImage() {
        filePath := FileSelect(1, , "Insert Image", "Image Files (*.png; *.jpg; *.bmp; *.gif)")
        if (filePath != "")
            this.InsertImage(filePath)
    }

    _FindDialog() {
        if (this.ui) {
            this.ui.Update(this.id "_FindPanel", "Visibility", "Visible")
            this.ui.Update(this.id "_FindInput", "Focus", "1")
        }
    }

    _ReplaceDialog() {
        if (this.ui) {
            this.ui.Update(this.id "_FindPanel", "Visibility", "Visible")
            this.ui.Update(this.id "_ReplaceInput", "Focus", "1")
        }
    }

    _FindAction(action, state := "") {
        if (!this.ui)
            return

        findText := ""
        replText := ""
        isPreview := false
        matchCase := false

        if (IsObject(state)) {
            findText := state.Has(this.id "_FindInput") ? state[this.id "_FindInput"] : ""
            replText := state.Has(this.id "_ReplaceInput") ? state[this.id "_ReplaceInput"] : ""
            isPreview := state.Has(this.id "_PreviewCheckbox") ? (state[this.id "_PreviewCheckbox"] == "True") : false
            matchCase := state.Has(this.id "_MatchCaseCheckbox") ? (state[this.id "_MatchCaseCheckbox"] == "True") : false
        }

        mcFlag := matchCase ? "1" : "0"

        if (action == "ConfirmReplace") {
            this._Cmd("ConfirmReplace", "")
            this.ui.Update(this.id "_PreviewPanel", "Visibility", "Collapsed")
            this.ui.Update(this.id "_NormalActionGrid", "IsEnabled", "True")
            this.ui.Update(this.id "_PreviewCheckbox", "IsChecked", "False")
            this._Cmd("HighlightFinds", findText "|||MC:" mcFlag)
            return
        }

        if (action == "CancelReplace") {
            this._Cmd("CancelReplace", "")
            this.ui.Update(this.id "_PreviewPanel", "Visibility", "Collapsed")
            this.ui.Update(this.id "_NormalActionGrid", "IsEnabled", "True")
            this.ui.Update(this.id "_PreviewCheckbox", "IsChecked", "False")
            this._Cmd("HighlightFinds", findText "|||MC:" mcFlag)
            return
        }

        if (findText == "")
            return

        if (action == "Next") {
            this._Cmd("FindNext", findText "|||MC:" mcFlag)
        } else if (action == "Prev") {
            this._Cmd("FindPrevious", findText "|||MC:" mcFlag)
        } else if (action == "Replace") {
            ; Single replace — always destructive (no preview for single)
            this._Cmd("ReplaceCurrent", findText "|||" replText "|||0|||MC:" mcFlag)
        } else if (action == "ReplaceAll") {
            ; If preview is already showing, this is a confirm
            ; Otherwise do a destructive replace-all
            this._Cmd("ReplaceAll", findText "|||" replText "|||0|||MC:" mcFlag)
        }
    }

    ; --- Live Preview Logic ---
    _UpdateLivePreview(state) {
        if (!this.ui)
            return

        findText := state.Has(this.id "_FindInput") ? state[this.id "_FindInput"] : ""
        replText := state.Has(this.id "_ReplaceInput") ? state[this.id "_ReplaceInput"] : ""
        isPreview := state.Has(this.id "_PreviewCheckbox") ? (state[this.id "_PreviewCheckbox"] == "True") : false
        matchCase := state.Has(this.id "_MatchCaseCheckbox") ? (state[this.id "_MatchCaseCheckbox"] == "True") : false
        mcFlag := matchCase ? "1" : "0"

        if (isPreview && findText != "" && replText != "") {
            ; Cancel any existing preview first (revert to original), then re-apply
            this._Cmd("CancelReplace", "")
            ; Apply preview: backup RTF + replace all
            this._Cmd("ReplaceAll", findText "|||" replText "|||1|||MC:" mcFlag)
            ; Show confirm/cancel panel, disable normal buttons
            this.ui.Update(this.id "_PreviewPanel", "Visibility", "Visible")
            this.ui.Update(this.id "_NormalActionGrid", "IsEnabled", "False")
        } else {
            ; Not previewing — revert if we were
            this._Cmd("CancelReplace", "")
            this.ui.Update(this.id "_PreviewPanel", "Visibility", "Collapsed")
            this.ui.Update(this.id "_NormalActionGrid", "IsEnabled", "True")
            ; Re-apply highlights
            this._Cmd("HighlightFinds", findText "|||MC:" mcFlag)
        }
    }

    _OnFindTextChanged(state) {
        if (!this.ui)
            return
        findText := state.Has(this.id "_FindInput") ? state[this.id "_FindInput"] : ""
        isPreview := state.Has(this.id "_PreviewCheckbox") ? (state[this.id "_PreviewCheckbox"] == "True") : false
        matchCase := state.Has(this.id "_MatchCaseCheckbox") ? (state[this.id "_MatchCaseCheckbox"] == "True") : false
        mcFlag := matchCase ? "1" : "0"

        if (isPreview) {
            ; Live preview is active — update it
            this._UpdateLivePreview(state)
        } else {
            ; Normal highlighting only
            this._Cmd("HighlightFinds", findText "|||MC:" mcFlag)
        }
    }

    _OnReplaceTextChanged(state) {
        if (!this.ui)
            return
        isPreview := state.Has(this.id "_PreviewCheckbox") ? (state[this.id "_PreviewCheckbox"] == "True") : false
        if (isPreview) {
            this._UpdateLivePreview(state)
        }
    }

    _CloseFindDialog() {
        if (!this.ui)
            return
        this.ui.Update(this.id "_FindPanel", "Visibility", "Collapsed")
        this._Cmd("HighlightFinds", "")
        this._Cmd("CancelReplace", "")
        this.ui.Update(this.id "_PreviewPanel", "Visibility", "Collapsed")
        this.ui.Update(this.id "_NormalActionGrid", "IsEnabled", "True")
        this.ui.Update(this.id "_PreviewCheckbox", "IsChecked", "False")
    }

    _InsertLinkDialog() {
        opts := this._GetOwnerThemeOpts()
        opts.Title := "Insert Hyperlink"
        opts.Message := "Enter the URL for the link:"
        opts.InputText := "https://"
        opts.Icon := Chr(0xE71B)
        opts.Buttons := ["Insert", "Cancel"]
        opts.Owner := this.ui ? this.ui.wpfHwnd : 0
        opts.Modal := true
        res := XDialog.Show(opts)
        if (res.Button == "Insert" && res.Input != "" && res.Input != "https://")
            this._Cmd("InsertLink", res.Input)
    }
    _SelectAll() {
        this._Cmd("SelectAll")
    }

    _InsertTableDialog() {
        opts := this._GetOwnerThemeOpts()
        opts.Title := "Insert Table"
        opts.Message := "Enter rows and columns separated by a comma (e.g. 3,3):"
        opts.InputText := "3,3"
        opts.Icon := Chr(0xE719)
        opts.Buttons := ["Insert", "Cancel"]
        opts.Owner := this.ui ? this.ui.wpfHwnd : 0
        opts.Modal := true
        res := XDialog.Show(opts)
        if (res.Button == "Insert" && res.Input != "")
            this._Cmd("InsertTable", res.Input)
    }

    _InsertHR() {
        this._Cmd("InsertHR")
    }

    _GetOwnerThemeOpts() {
        opts := {}
        try {
            _app := this.parent._FindApp()
            if (_app != "" && _app.HasOwnProp("currentThemeName") && _app.currentThemeName != "")
                opts.Theme := _app.currentThemeName
            if (_app != "" && _app.HasOwnProp("currentIniPath") && _app.currentIniPath != "")
                opts.IniPath := _app.currentIniPath
        }
        return opts
    }

    _OnLiveColor(formatCmd, hexColor) {
        this._Format(formatCmd "|" hexColor)
    }

    _PickColor(formatCmd) {
        defaultColor := formatCmd == "Highlight" ? "#FFFFFF00" : "#FFFF0000"
        prompt := formatCmd == "Highlight" ? "Enter highlight color (hex e.g. #FFFF00):" : "Enter font color (hex e.g. #FF0000):"
        opts := this._GetOwnerThemeOpts()
        opts.Title := "Choose Color"
        opts.Message := prompt
        opts.InputText := defaultColor
        opts.Icon := Chr(0xE790)
        opts.Buttons := ["Apply", "Cancel"]
        opts.Owner := this.ui ? this.ui.wpfHwnd : 0
        opts.Modal := true
        res := XDialog.Show(opts)
        if (res.Button == "Apply" && res.Input != "")
            this._Format(formatCmd "|" res.Input)
    }

    _OnFontFamilyChanged(state, ctrl, event) {
        if (state.Has(this.id "_FontFamily")) {
            val := state[this.id "_FontFamily"]
            if (SubStr(val, 1, 2) == "⚠ ") {
                val := SubStr(val, 3)
            } else if (SubStr(val, 1, 4) == "[!] ") {
                val := SubStr(val, 5)
            }
            if (this.HasProp("expectedFormatState") && this.expectedFormatState.Has("Font") && this.expectedFormatState["Font"] == val) {
                this.expectedFormatState.Delete("Font")
                return
            }
            this._Format("FontFamily|" val)
        }
    }

    _OnFontSizeChanged(state, ctrl, event) {
        if (state.Has(this.id "_FontSize")) {
            val := state[this.id "_FontSize"]
            if (this.HasProp("expectedFormatState") && this.expectedFormatState.Has("Size") && this.expectedFormatState["Size"] == val) {
                this.expectedFormatState.Delete("Size")
                return
            }
            this._Format("FontSize|" val)
        }
    }

    _OnDocLoaded(state, ctrl, event) {
        this.GetWordCount()
    }

    _OnDocSaved(state, ctrl, event) {
        ; Could show a notification
    }

    _OnOutlineToggle(ctrl, event, *) {
        isChecked := this.ui.Query(this.id "_BtnOutline")
        this.ui.Update(this.id "_OutlinePane", "Visibility", isChecked == "True" ? "Visible" : "Collapsed")
        if (isChecked == "True")
            this._Cmd("GetOutline")
    }

    _OnToggleMenu(ctrl, event, *) {
        isChecked := this.ui.Query(this.id "_BtnToggleMenu")
        if (isChecked == "True") {
            this.ui.Update(this.id "_MenuBar", "Visibility", "Collapsed")
            this.ui.Update(this.id "_BtnToggleMenu", "Content", Chr(0xE70D))
            this.ui.Update(this.id "_BtnToggleMenu", "ToolTip", "Show Menu Bar")
        } else {
            this.ui.Update(this.id "_MenuBar", "Visibility", "Visible")
            this.ui.Update(this.id "_BtnToggleMenu", "Content", Chr(0xE70E))
            this.ui.Update(this.id "_BtnToggleMenu", "ToolTip", "Hide Menu Bar")
        }
    }

    _OnDocError(state, ctrl, event) {
        errMsg := state.Has("DocumentError") ? state["DocumentError"] : "Unknown document loading error."
        opts := {
            Title: "Document Load Error",
            Message: "Failed to open document:`n`n" errMsg,
            Icon: Chr(0xE783),
            Buttons: ["OK"],
            Owner: this.ui ? this.ui.wpfHwnd : 0,
            Modal: true
        }
        if (this.ui && this.ui.HasOwnProp("currentThemeName") && this.ui.currentThemeName != "")
            opts.Theme := this.ui.currentThemeName
        XDialog.Show(opts)
    }

    _OnWordCount(state, ctrl, event) {
        if (!this.ui)
            return
        ; event data is "words,chars"
        data := state.Has("WordCount") ? state["WordCount"] : ""
        if (data != "") {
            parts := StrSplit(data, ",")
            if (parts.Length >= 2)
                this.ui.Update(this.id "_WordCount", "Text", "Words: " parts[1] " | Characters: " parts[2])
        }
    }

    SetDocumentTheme(mode) {
        if (!this.ui)
            return
        ; Restore colors if we were in dark mode
        if (this.currentTheme == "Dark" && mode != "Dark") {
            this.ui.Update(this.id, "Doc_RestoreColors", "")
        }
        this.currentTheme := mode
        this.ui.Update(this.id "_Container", "Tag", mode)

        ; Explicitly update PageBorder and all background elements to match the selected theme
        if (mode == "Dark") {
            this.ui.Update(this.id "_EditorWrapper", "Background", "#121212")
            this.ui.Update(this.id "_PageBorder", "Background", "#1E1E1E")
            this.ui.Update(this.id "_PageBorder", "BorderBrush", "#333333")

            ; Status Bar theme matching
            this.ui.Update(this.id "_StatusBg", "Background", "#252526")
            this.ui.Update(this.id "_StatusBg", "BorderBrush", "#3F3F46")
            this.ui.Update(this.id "_WordCount", "Foreground", "#999999")
            this.ui.Update(this.id "_ZoomLevel", "Foreground", "#999999")

            ; Toolbar theme matching
            this.ui.Update(this.id "_ToolbarBg", "Background", "#1E1E1E")
            this.ui.Update(this.id "_ToolbarInner", "Background", "#2D2D2D")
            this.ui.Update(this.id "_ToolbarInner", "BorderBrush", "#3F3F46")

            ; ComboBox theming
            this.ui.Update(this.id "_StyleSelect", "Background", "#3F3F46")
            this.ui.Update(this.id "_StyleSelect", "Foreground", "#E0E0E0")
            this.ui.Update(this.id "_StyleSelect", "BorderBrush", "#555555")
            this.ui.Update(this.id "_FontFamily", "Background", "#3F3F46")
            this.ui.Update(this.id "_FontFamily", "Foreground", "#E0E0E0")
            this.ui.Update(this.id "_FontFamily", "BorderBrush", "#555555")
            this.ui.Update(this.id "_FontSize", "Background", "#3F3F46")
            this.ui.Update(this.id "_FontSize", "Foreground", "#E0E0E0")
            this.ui.Update(this.id "_FontSize", "BorderBrush", "#555555")

            ; Outline pane
            this.ui.Update(this.id "_OutlinePane", "Background", "#252526")
            this.ui.Update(this.id "_OutlinePane", "BorderBrush", "#3F3F46")

            ; Find & Replace panel
            this.ui.Update(this.id "_FindPanel", "Background", "#252526")
            this.ui.Update(this.id "_FindPanel", "BorderBrush", "#3F3F46")

            this.ui.Update(this.id, "Doc_ApplyDarkMode", "")
        } else if (mode == "Theme") {
            this.ui.Update(this.id "_EditorWrapper", "Background", "{DynamicResource DropdownBg}")
            this.ui.Update(this.id "_PageBorder", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_PageBorder", "BorderBrush", "{DynamicResource ControlBorder}")

            ; Status Bar theme matching
            this.ui.Update(this.id "_StatusBg", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_StatusBg", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_WordCount", "Foreground", "{DynamicResource TextSub}")
            this.ui.Update(this.id "_ZoomLevel", "Foreground", "{DynamicResource TextSub}")

            ; Toolbar theme matching
            this.ui.Update(this.id "_ToolbarBg", "Background", "{DynamicResource BgColor}")
            this.ui.Update(this.id "_ToolbarInner", "Background", "{DynamicResource SidebarColor}")
            this.ui.Update(this.id "_ToolbarInner", "BorderBrush", "{DynamicResource ControlBorder}")

            ; ComboBox theming
            this.ui.Update(this.id "_StyleSelect", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_StyleSelect", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_StyleSelect", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_FontFamily", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_FontFamily", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_FontFamily", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_FontSize", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_FontSize", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_FontSize", "BorderBrush", "{DynamicResource ControlBorder}")

            ; Outline pane
            this.ui.Update(this.id "_OutlinePane", "Background", "{DynamicResource SidebarColor}")
            this.ui.Update(this.id "_OutlinePane", "BorderBrush", "{DynamicResource ControlBorder}")

            ; Find & Replace panel
            this.ui.Update(this.id "_FindPanel", "Background", "{DynamicResource DropdownBg}")
            this.ui.Update(this.id "_FindPanel", "BorderBrush", "{DynamicResource ControlBorder}")
        } else {
            this.ui.Update(this.id "_EditorWrapper", "Background", "{DynamicResource DropdownBg}")
            this.ui.Update(this.id "_PageBorder", "Background", "White")
            this.ui.Update(this.id "_PageBorder", "BorderBrush", "#E0E0E0")

            ; Status Bar theme matching
            this.ui.Update(this.id "_StatusBg", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_StatusBg", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_WordCount", "Foreground", "{DynamicResource TextSub}")
            this.ui.Update(this.id "_ZoomLevel", "Foreground", "{DynamicResource TextSub}")

            ; Toolbar theme matching
            this.ui.Update(this.id "_ToolbarBg", "Background", "{DynamicResource BgColor}")
            this.ui.Update(this.id "_ToolbarInner", "Background", "{DynamicResource SidebarColor}")
            this.ui.Update(this.id "_ToolbarInner", "BorderBrush", "{DynamicResource ControlBorder}")

            ; ComboBox theming
            this.ui.Update(this.id "_StyleSelect", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_StyleSelect", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_StyleSelect", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_FontFamily", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_FontFamily", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_FontFamily", "BorderBrush", "{DynamicResource ControlBorder}")
            this.ui.Update(this.id "_FontSize", "Background", "{DynamicResource ControlBg}")
            this.ui.Update(this.id "_FontSize", "Foreground", "{DynamicResource TextMain}")
            this.ui.Update(this.id "_FontSize", "BorderBrush", "{DynamicResource ControlBorder}")

            ; Outline pane
            this.ui.Update(this.id "_OutlinePane", "Background", "{DynamicResource SidebarColor}")
            this.ui.Update(this.id "_OutlinePane", "BorderBrush", "{DynamicResource ControlBorder}")

            ; Find & Replace panel
            this.ui.Update(this.id "_FindPanel", "Background", "{DynamicResource DropdownBg}")
            this.ui.Update(this.id "_FindPanel", "BorderBrush", "{DynamicResource ControlBorder}")
        }

        ; Force spacers to redraw in Paper mode using the new theme colors
        this.ui.Update(this.id, "Doc_UpdateSpacers", mode)
    }

    SetPageView(mode) {
        if (!this.ui)
            return
        ; Delegate to C# bridge which handles FlowDocumentReader switching
        ; Modes: "Feed" (default RichTextBox), "Paper" (paginated), "TwoUp" (2-page side-by-side)
        this.ui.Update(this.id, "Doc_SetPageView", mode)
    }

    _OnStyleChanged(state) {
        if (!state.Has(this.id "_StyleSelect"))
            return
        selectedTag := state[this.id "_StyleSelect"]
        if (this.HasProp("expectedFormatState") && this.expectedFormatState.Has("Style") && this.expectedFormatState["Style"] == selectedTag) {
            this.expectedFormatState.Delete("Style")
            return
        }
        if (selectedTag != "") {
            this._Cmd("FormatStyle", selectedTag)
        }
    }

    _OnSelectionFormat(state, ctrl, event) {
        if (!state.Has("SelectionFormat"))
            return
        fmt := state["SelectionFormat"]

        if (!this.HasProp("expectedFormatState"))
            this.expectedFormatState := Map()

        ; Expected format: B:1,I:0,U:0,S:0,Size:14,Style:Body
        for prop in StrSplit(fmt, ",") {
            kv := StrSplit(prop, ":")
            if (kv.Length < 2)
                continue
            key := kv[1], val := kv[2]

            if (key == "B")
                this.ui.Update(this.id "_BtnBold", "IsChecked", val == "1" ? "True" : "False")
            else if (key == "I")
                this.ui.Update(this.id "_BtnItalic", "IsChecked", val == "1" ? "True" : "False")
            else if (key == "U")
                this.ui.Update(this.id "_BtnUnderline", "IsChecked", val == "1" ? "True" : "False")
            else if (key == "S")
                this.ui.Update(this.id "_BtnStrike", "IsChecked", val == "1" ? "True" : "False")
            else if (key == "Style") {
                idx := (val == "H1") ? 1 : ((val == "H2") ? 2 : ((val == "H3") ? 3 : ((val == "H4") ? 4 : ((val == "H5") ? 5 : ((val == "H6") ? 6 : 0)))))
                this.expectedFormatState["Style"] := val
                this.ui.Update(this.id "_StyleSelect", "SelectedIndex", idx)
            } else if (key == "Size") {
                this.expectedFormatState["Size"] := val
                sizeArr := ["8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "36", "48", "72"]
                for i, s in sizeArr {
                    if (s == val) {
                        this.ui.Update(this.id "_FontSize", "SelectedIndex", i - 1)
                        break
                    }
                }
            } else if (key == "Font") {
                ; C# prefixes font name with ! if not installed in WPF
                isInstalled := true
                if (SubStr(val, 1, 1) = "!") {
                    val := SubStr(val, 2)
                    isInstalled := false
                }
                this.expectedFormatState["Font"] := val

                if (isInstalled) {
                    this.ui.Update(this.id "_FontFamily", "Text", val)
                    this.ui.Update(this.id "_FallbackFont", "Visibility", "Collapsed")
                } else {
                    this.ui.Update(this.id "_FallbackFontText", "Text", val)
                    this.ui.Update(this.id "_FallbackFont", "Tag", val)
                    this.ui.Update(this.id "_FallbackFont", "Visibility", "Visible")
                    this.ui.Update(this.id "_FontFamily", "SelectedIndex", "0")
                    this.ui.Update(this.id "_FontFamily", "Text", "⚠ " val)
                }
            }
        }
    }

    static _GetSystemFonts() {
        fonts := Map()
        for hive in ["HKLM", "HKCU"] {
            Loop Reg, hive "\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" {
                name := A_LoopRegName
                name := RegExReplace(name, "\s*\((TrueType|OpenType|PostScript|Type 1|Vector|Stroke)\)$", "")
                name := RegExReplace(name, "\s+(Bold|Italic|Regular|Semibold|Semi-Bold|Light|Extra\s*Light|Medium|Black|Condensed|Oblique|Bold\s+Italic|Italic\s+Bold|Demibold|Heavy|Nord)\b", "")
                name := Trim(name)
                if (name != "") {
                    if InStr(name, "&") {
                        for subName in StrSplit(name, "&") {
                            trimmedSub := Trim(subName)
                            if (trimmedSub != "")
                                fonts[trimmedSub] := true
                        }
                    } else {
                        fonts[name] := true
                    }
                }
            }
        }
        common := ["Segoe UI", "Arial", "Calibri", "Cambria", "Consolas", "Courier New", "Georgia", "Impact", "Lucida Console", "Segoe Fluent Icons", "Segoe MDL2 Assets", "Times New Roman", "Trebuchet MS", "Verdana", "Webdings", "Wingdings"]
        for c in common {
            fonts[c] := true
        }
        sorted := []
        for f, _ in fonts {
            sorted.Push(f)
        }
        fontStr := ""
        for f in sorted {
            fontStr .= f "`n"
        }
        fontStr := Sort(Trim(fontStr, "`n"))
        return StrSplit(fontStr, "`n")
    }
}

XAMLElement.Prototype.DefineProp("DocumentEditor", { Call: _DocumentEditor })
_DocumentEditor(this, name := "") {
    comp := XDocumentEditor(this, name)
    _AutoRegisterComponent(this, comp)
    return comp
}

; ==============================================================================
; COLOR PICKER POPOVER (Live updating)
; ==============================================================================

class XColorPickerLive {
    __New(popoverContainer, defaultColor) {
        this.id := "ColorPicker_" XColorPickerLive.Count()
        this.container := popoverContainer
        this.container.MinWidth(300)
        this.container.Padding("10")

        main := this.container.Add("StackPanel").Name(this.id)

        ; Preset Colors Row
        presetColors := [
            ["#000000", "#434343", "#666666", "#999999", "#b7b7b7", "#cccccc", "#d9d9d9", "#efefef", "#f3f3f3", "#ffffff"],
            ["#980000", "#ff0000", "#ff9900", "#ffff00", "#00ff00", "#00ffff", "#4a86e8", "#0000ff", "#9900ff", "#ff00ff"],
            ["#e6b8af", "#f4cccc", "#fce5cd", "#fff2cc", "#d9ead3", "#d0e0e3", "#c9daf8", "#cfe2f3", "#d9d2e9", "#ead1dc"],
            ["#cc4125", "#e06666", "#f6b26b", "#ffd966", "#93c47d", "#76a5af", "#6d9eeb", "#9fc5e8", "#b4a7d6", "#d5a6bd"],
            ["#a61c00", "#cc0000", "#e69138", "#f1c232", "#6aa84f", "#45818e", "#3c78d8", "#3d85c6", "#674ea7", "#a64d79"],
            ["#5b0f00", "#660000", "#783f04", "#7f6000", "#274e13", "#134f5c", "#1c4587", "#073763", "#20124d", "#4c1130"]
        ]

        presetGrid := main.Add("Grid").Margin("0,0,0,10")
        presetGrid.Cols("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "Auto")
        presetGrid.Rows("Auto", "Auto", "Auto", "Auto", "Auto", "Auto")

        this.presetNames := []
        for r, rowColors in presetColors {
            for c, hex in rowColors {
                pName := this.id "_Preset_" r "_" c
                this.presetNames.Push({ Name: pName, Hex: hex })
                btn := presetGrid.Add("Button").Name(pName).Grid_Row(r - 1).Grid_Column(c - 1).Width("24").Height("24").Margin("2").Background(hex).BorderThickness("1").BorderBrush("{DynamicResource ControlBorder}").Cursor("Hand").Focusable("False")
                btn.InjectResources('<Style TargetType="Button"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="BorderBrush" Value="{DynamicResource Accent}"/><Setter TargetName="bg" Property="BorderThickness" Value="2"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>')
            }
        }

        toggleAdvanced := main.Add("ToggleButton").Name(this.id "_ToggleAdvanced").Content("Advanced Color Tools").Background("Transparent").BorderThickness("0").Foreground("{DynamicResource TextSub}").FontSize("11").Margin("0,0,0,10").Cursor("Hand").Focusable("False").HorizontalAlignment("Center")

        advancedPanel := main.Add("StackPanel").Name(this.id "_AdvancedPanel").Visibility("Collapsed")

        ; Sliders Row
        sliderGrid := advancedPanel.Add("Grid").Margin("0,0,0,10")
        sliderGrid.Cols("Auto", "*", "Auto")

        sliderGrid.Add("Border").Width("32").Height("32").CornerRadius("16").Background("#15FFFFFF").BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1").Grid_Column(0).Margin("0,0,10,0").Add("TextBlock").Text(Chr(0xE891)).FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets").FontSize("14").Foreground("{DynamicResource TextMain}").VerticalAlignment("Center").HorizontalAlignment("Center")

        sliders := sliderGrid.Add("StackPanel").Grid_Column(1).VerticalAlignment("Center").Margin("0,0,10,0")

        hueBg := sliders.Add("Border").Height("8").CornerRadius("4").Margin("0,0,0,10").IsHitTestVisible("False").Add("Border.Background").Add("LinearGradientBrush").StartPoint("0,0").EndPoint("1,0")
        hueBg.Add("GradientStop").SetProp('Color', "#FFFF0000").Offset("0")
        hueBg.Add("GradientStop").SetProp('Color', "#FFFFFF00").Offset("0.16")
        hueBg.Add("GradientStop").SetProp('Color', "#FF00FF00").Offset("0.33")
        hueBg.Add("GradientStop").SetProp('Color', "#FF00FFFF").Offset("0.5")
        hueBg.Add("GradientStop").SetProp('Color', "#FF0000FF").Offset("0.66")
        hueBg.Add("GradientStop").SetProp('Color', "#FFFF00FF").Offset("0.83")
        hueBg.Add("GradientStop").SetProp('Color', "#FFFF0000").Offset("1")
        sliders.Add("Slider").Name(this.id "_HueSlider").Minimum("0").Maximum("360").Value("0").Margin("0,-20,0,0")
            .ThumbShape("Line").ThumbWidth(8).ThumbHeight(20).ThumbColor("#FFFFFF").ThumbBorderColor("#FF222222").ThumbBorderThickness(1.5).ThumbCornerRadius(1.5).ThumbShadow(true)
            .TrackHeight(32).TrackColor("Transparent").TrackBg("Transparent")

        alphaBg := sliders.Add("Border").Height("8").CornerRadius("4").Background("Transparent").ClipToBounds("True").IsHitTestVisible("False")
        alphaFill := alphaBg.Add("Rectangle").Name(this.id "_AlphaFillRect").Fill("White")
        mask := alphaFill.Add("Rectangle.OpacityMask").Add("LinearGradientBrush").StartPoint("0,0").EndPoint("1,0")
        mask.Add("GradientStop").SetProp('Color', "Transparent").Offset("0")
        mask.Add("GradientStop").SetProp('Color', "White").Offset("1")

        sliders.Add("Slider").Name(this.id "_AlphaSlider").Minimum("0").Maximum("255").Value("255").Margin("0,-20,0,0")
            .ThumbShape("Line").ThumbWidth(8).ThumbHeight(20).ThumbColor("#FFFFFF").ThumbBorderColor("#FF222222").ThumbBorderThickness(1.5).ThumbCornerRadius(1.5).ThumbShadow(true)
            .TrackHeight(32).TrackColor("Transparent").TrackBg("Transparent")

        sliderGrid.Add("Border").Name(this.id "_ColorPreview").Grid_Column(2).Width("32").Height("32").CornerRadius("16").Background(defaultColor).BorderBrush("{DynamicResource ControlBorder}").BorderThickness("1")

        ; Inputs Row
        inGrid := advancedPanel.Add("Grid")
        inGrid.Cols("Auto", "10", "Auto")
        inGrid.Rows("Auto", "5", "Auto")

        inGrid.Add("TextBlock").Text("HEX").Foreground("{DynamicResource TextSub}").FontSize("10").Grid_Row(0).Grid_Column(0)

        spLbl := inGrid.Add("StackPanel").Grid_Row(0).Grid_Column(2).Orientation("Horizontal")
        spLbl.Add("TextBlock").Text("RGB").Foreground("{DynamicResource TextSub}").FontSize("10").Margin("0,0,4,0")

        inGrid.Add("TextBox").Name(this.id "_HexInput").Text(defaultColor).Width("80").Height("26").Padding("6,4").Grid_Row(2).Grid_Column(0)

        rgbSp := inGrid.Add("StackPanel").Grid_Row(2).Grid_Column(2).Orientation("Horizontal")
        rgbSp.Add("TextBlock").Text("R:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,2,0")
        rgbSp.Add("TextBox").Name(this.id "_RInput").Text("255").Width("30").Height("26").Padding("2,4").Margin("0,0,6,0").HorizontalContentAlignment("Center")
        rgbSp.Add("TextBlock").Text("G:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,2,0")
        rgbSp.Add("TextBox").Name(this.id "_GInput").Text("0").Width("30").Height("26").Padding("2,4").Margin("0,0,6,0").HorizontalContentAlignment("Center")
        rgbSp.Add("TextBlock").Text("B:").Foreground("{DynamicResource TextSub}").FontSize("11").VerticalAlignment("Center").Margin("0,0,2,0")
        rgbSp.Add("TextBox").Name(this.id "_BInput").Text("0").Width("30").Height("26").Padding("2,4").HorizontalContentAlignment("Center")

        this.ui := ""
        this._defaultColor := defaultColor
        this.stateObj := { Color: defaultColor, Hue: 0.0, Alpha: 255, R: 0, G: 0, B: 0 }
        this._changeCb := ""
    }

    OnChange(callback) {
        this._changeCb := callback
        return this
    }

    Bind(host) {
        this.ui := host

        host.OnEvent(this.id "_ToggleAdvanced", "Click", ObjBindMethod(this, "_OnToggleAdvanced"))

        for p in this.presetNames {
            host.OnEvent(p.Name, "Click", ObjBindMethod(this, "_OnPresetClick", p.Hex))
        }

        host.OnEvent(this.id "_HueSlider", "ValueChanged", ObjBindMethod(this, "_OnSliderChange")).Limit(60, false)
        host.OnEvent(this.id "_AlphaSlider", "ValueChanged", ObjBindMethod(this, "_OnSliderChange")).Limit(60, false)

        host.OnEvent(this.id "_RInput", "TextChanged", ObjBindMethod(this, "_OnRGBChange"))
        host.OnEvent(this.id "_GInput", "TextChanged", ObjBindMethod(this, "_OnRGBChange"))
        host.OnEvent(this.id "_BInput", "TextChanged", ObjBindMethod(this, "_OnRGBChange"))
        host.OnEvent(this.id "_HexInput", "TextChanged", ObjBindMethod(this, "_OnHexChange"))
    }

    _OnToggleAdvanced(state, ctrl, event) {
        isVisible := state[this.id "_ToggleAdvanced"] == "True"
        this.ui.Update(this.id "_AdvancedPanel", "Visibility", isVisible ? "Visible" : "Collapsed")
    }

    _OnPresetClick(hex, state, ctrl, event) {
        this.ui.Update(this.id "_HexInput", "Text", hex) ; Will trigger _OnHexChange
    }

    _OnSliderChange(state, ctrl, event) {
        if (!state.Has(this.id "_HueSlider") || !state.Has(this.id "_AlphaSlider"))
            return

        this.stateObj.Hue := Float(state[this.id "_HueSlider"])
        this.stateObj.Alpha := Integer(state[this.id "_AlphaSlider"])

        r := 0, g := 0, b := 0
        this._HSVtoRGB(this.stateObj.Hue, 1.0, 1.0, &r, &g, &b)
        this.stateObj.R := r
        this.stateObj.G := g
        this.stateObj.B := b

        this._UpdateUIFromState()
    }

    _OnRGBChange(state, ctrl, event) {
        if (!state.Has(this.id "_RInput") || !state.Has(this.id "_GInput") || !state.Has(this.id "_BInput"))
            return

        this.stateObj.R := Max(0, Min(255, Integer(state[this.id "_RInput"])))
        this.stateObj.G := Max(0, Min(255, Integer(state[this.id "_GInput"])))
        this.stateObj.B := Max(0, Min(255, Integer(state[this.id "_BInput"])))

        ; Estimate Hue from RGB
        h := 0.0, s := 0.0, v := 0.0
        this._RGBtoHSV(this.stateObj.R, this.stateObj.G, this.stateObj.B, &h, &s, &v)
        this.stateObj.Hue := h

        this._UpdateUIFromState()
    }

    _OnHexChange(state, ctrl, event) {
        if (!state.Has(this.id "_HexInput"))
            return

        hex := StrReplace(state[this.id "_HexInput"], "#")
        if (StrLen(hex) == 6) {
            this.stateObj.Alpha := 255
            this.stateObj.R := Integer("0x" SubStr(hex, 1, 2))
            this.stateObj.G := Integer("0x" SubStr(hex, 3, 2))
            this.stateObj.B := Integer("0x" SubStr(hex, 5, 2))
        } else if (StrLen(hex) == 8) {
            this.stateObj.Alpha := Integer("0x" SubStr(hex, 1, 2))
            this.stateObj.R := Integer("0x" SubStr(hex, 3, 2))
            this.stateObj.G := Integer("0x" SubStr(hex, 5, 2))
            this.stateObj.B := Integer("0x" SubStr(hex, 7, 2))
        } else {
            return
        }

        h := 0.0, s := 0.0, v := 0.0
        this._RGBtoHSV(this.stateObj.R, this.stateObj.G, this.stateObj.B, &h, &s, &v)
        this.stateObj.Hue := h

        this._UpdateUIFromState()
    }

    _UpdateUIFromState() {
        hex := Format("#{:02X}{:02X}{:02X}{:02X}", this.stateObj.Alpha, this.stateObj.R, this.stateObj.G, this.stateObj.B)
        this.stateObj.Color := hex

        updates := []
        updates.Push({ ControlName: this.id "_ColorPreview", PropertyName: "Background", Value: hex })
        updates.Push({ ControlName: this.id "_HexInput", PropertyName: "Text", Value: hex })
        updates.Push({ ControlName: this.id "_RInput", PropertyName: "Text", Value: this.stateObj.R })
        updates.Push({ ControlName: this.id "_GInput", PropertyName: "Text", Value: this.stateObj.G })
        updates.Push({ ControlName: this.id "_BInput", PropertyName: "Text", Value: this.stateObj.B })

        baseHex := Format("#FF{:02X}{:02X}{:02X}", this.stateObj.R, this.stateObj.G, this.stateObj.B)
        updates.Push({ ControlName: this.id "_AlphaFillRect", PropertyName: "Fill", Value: baseHex })

        this.ui.BatchUpdate(updates)

        if (this._changeCb != "") {
            cb := this._changeCb
            cb(hex)
        }
    }

    _HSVtoRGB(h, s, v, &r, &g, &b) {
        c := v * s
        x := c * (1 - Abs(Mod(h / 60.0, 2) - 1))
        m := v - c

        r1 := 0, g1 := 0, b1 := 0
        if (h >= 0 && h < 60) {
            r1 := c, g1 := x, b1 := 0
        } else if (h >= 60 && h < 120) {
            r1 := x, g1 := c, b1 := 0
        } else if (h >= 120 && h < 180) {
            r1 := 0, g1 := c, b1 := x
        } else if (h >= 180 && h < 240) {
            r1 := 0, g1 := x, b1 := c
        } else if (h >= 240 && h < 300) {
            r1 := x, g1 := 0, b1 := c
        } else {
            r1 := c, g1 := 0, b1 := x
        }

        r := Integer((r1 + m) * 255)
        g := Integer((g1 + m) * 255)
        b := Integer((b1 + m) * 255)
    }

    _RGBtoHSV(r, g, b, &h, &s, &v) {
        rNorm := r / 255.0
        gNorm := g / 255.0
        bNorm := b / 255.0

        cmax := Max(rNorm, gNorm, bNorm)
        cmin := Min(rNorm, gNorm, bNorm)
        diff := cmax - cmin

        if (cmax == cmin)
            h := 0
        else if (cmax == rNorm)
            h := Mod((60 * ((gNorm - bNorm) / diff) + 360), 360)
        else if (cmax == gNorm)
            h := Mod((60 * ((bNorm - rNorm) / diff) + 120), 360)
        else if (cmax == bNorm)
            h := Mod((60 * ((rNorm - gNorm) / diff) + 240), 360)

        if (cmax == 0)
            s := 0
        else
            s := (diff / cmax)

        v := cmax
    }

    static Count() {
        static counter := 0
        return ++counter
    }
}

XAMLElement.Prototype.DefineProp("ColorPickerPopover", { Call: _ColorPickerPopover })
_ColorPickerPopover(this, defaultColor := "#FF0A84FF") {
    popover := this.AddRichPopover()
    comp := XColorPickerLive(popover, defaultColor)
    _AutoRegisterComponent(this, comp)
    return comp
}