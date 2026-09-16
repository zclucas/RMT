#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\Plugins\AHK-XAML\lib\XAML_Generator.ahk
#Include ..\Main\Util\XamlWin.ahk
#Include ..\Gui\VoiceGui.ahk
#Include ..\Gui\TableMgrGui.ahk

; Test the actual migrated dialog builders without starting RMT or its macro workers.
global TestHosts := []
global MainSoftData := {FontType: "Microsoft YaHei UI", Theme: "RMT_Light", MyGui: {Hwnd: A_ScriptHwnd}}
global MySoftData := {TableInfo: [{Index: 1, ID: "one", Name: "测试 & 表", Symbol: "Voice", Items: [{VoiceKeywords: "你好， 保存"}]}, {Index: 2, ID: "two", Name: "第二表", Symbol: "Normal", Items: []}]}
global XAML_TEMPLATE := '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="940" Height="700"><Window.Resources>%resources%</Window.Resources>%app%</Window>'

class XAMLHost {
    __New(xaml, *) {
        this.xaml := xaml
        this.wpfHwnd := A_ScriptHwnd
        this.values := Map()
        this.rows := []
        TestHosts.Push(this)
    }
    static FontSize() => 15
    static VisualFontSizeDeclared(extra := 0) => 15 + extra
    static FormatFontSize(value) => value
    static GetMainViewboxScale() => 1
    static AddTitleBar(main, title, height, closeName := "", titleName := "", *) {
        titleText := main.Add("TextBlock").Grid_Row(0).Text(title).Height(height)
        if (titleName != "")
            titleText.Name(titleName)
        return {Title: titleText}
    }
    OnEvent(*) {
    }
    Update(name, property, value) {
        this.values[name ">" property] := value
        if (property == "AddXamlItem")
            this.rows.Push(value)
    }
    Query(name) {
        if (!InStr(name, ">"))
            name .= ">Text"
        return this.values.Has(name) ? this.values[name] : ""
    }
    Show() {
    }
}
GetLang(text) => text
CheckIsItemTable(*) => true
GetTableIndexByID(*) => 1
ApplyXamlTheme(*) {
}
HotReloadPublish(*) => Fail("Unexpected write")
SaveAllTableItemInfo(*) => Fail("Unexpected write")
OnSaveSetting(*) => Fail("Unexpected write")
SafeReload(*) => Fail("Unexpected reload")
AddTable(*) => Fail("Unexpected write")
RenameTable(*) => Fail("Unexpected write")
RemoveTable(*) => Fail("Unexpected write")
Fail(message) {
    throw Error(message)
}
Assert(value, message) {
    if (!value)
        Fail(message)
    FileAppend("PASS " message "`n", "*")
}

try {
    table := TableMgrGui()
    table._Build()
    table.ui.values["TableLV>SelectedIndex"] := "1"
    Assert(table._Selected().ID == "two", "table selection uses zero-based WPF index")
    table.ui.values["TableLV>SelectedIndex"] := "-1"
    Assert(table._Selected() == "", "empty table selection is safe")
    Assert(table.ui.rows.Length == 2, "table rows generated")
    voice := VoiceGui()
    voice.ShowGui(MySoftData.TableInfo[1], 1)
    Assert(InStr(voice.ui.xaml, 'Name="VoiceKeywordActions"') && InStr(voice.ui.xaml, 'Uid="ahk:Voice.Keywords.Actions"'), "voice action panel has a stable production instance id")
    Assert(InStr(voice.ui.xaml, 'Name="DialogTitle"') && !InStr(voice.ui.xaml, "RmtFluidDialogLayout"), "voice window uses standard dialog title and scaling")
    Assert(voice.ui.ownerHwnd == A_ScriptHwnd, "dialog owner is assigned before show")
    Assert(voice._ReadFields() == "你好,保存", "voice keywords read and normalized")
    voice._LoadToFields("测试, , 第二项")
    Assert(voice._ReadFields() == "测试,第二项", "voice reuse refreshes input")
    outDir := A_Temp "\RmtGMUI-check"
    DirCreate(outDir)
    for i, host in TestHosts {
        outputFile := FileOpen(outDir "\dialog-" i ".xaml", "w", "UTF-8")
        outputFile.Write(host.xaml)
        outputFile.Close()
    }
    voice.Cancel()
    table._Close()
    Assert(!voice.hasGui && table.closed, "dialog close resets reusable state")
    ExitApp(0)
} catch as e {
    FileAppend(e.Message " @ " e.Line "`n", "*")
    ExitApp(1)
}
