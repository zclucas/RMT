#Requires AutoHotkey v2.0

OfficialLanguages() {
    static languages := Map("简中", {code: "zh", flag: "cn"},
        "繁體中文", {code: "zh-TW", flag: "tw", entry: "TraditionalChinese.txt"},
        "English", {code: "en", flag: "gb", entry: "English.txt"},
        "Español", {code: "es", flag: "es", entry: "Spanish.txt"},
        "Français", {code: "fr", flag: "fr", entry: "French.txt"},
        "Deutsch", {code: "de", flag: "de", entry: "Deutsch.txt"},
        "Italiano", {code: "it", flag: "it", entry: "Italiano.txt"})
    return languages
}
