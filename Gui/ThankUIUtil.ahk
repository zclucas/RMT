#Requires AutoHotkey v2.0

;打赏
AddThankUI(index) {
    MyGui := MySoftData.MyGui
    tableItem := MySoftData.TableInfo[index]
    posY := MySoftData.TabPosY + 40
    OriPosX := MySoftData.TabPosX + 15

    posX := OriPosX
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", posX, posY, 850, 60), GetLang("感谢以下开发者为项目付出的智慧与汗水（排名不分先后）："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)

    posY += 30
    posX += 10
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/GushuLily">GushuLily</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://gitee.com/bogezzb">张正波</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/yunkuangao">yun</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/boxstudy">boxstudy</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/sovaedv776">sovaedv776</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/T8numen">T8numen</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX := OriPosX
    posY += 40
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", posX, posY, 850, 85), GetLang("软件的开发离不开众多优秀开源项目的支持，特别感谢："))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)

    posY += 30
    posX += 10
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/opencv/opencv">OpenCV</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '<a href="https://github.com/thqby/ahk2_lib">ahk2_lib</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/RapidAI/RapidOCR">RapidOCR</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/evilC/AHK-CvJoyInterface">AHK-CvJoyInterface</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 150
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/Chaoses-Ib/IbInputSimulator">IbInputSimulator</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 25
    posX := OriPosX + 10
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/evilC/AHK-ViGEm-Bus">AHK-ViGEm-Bus</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 150
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/CesarHlp1/AHK-ViGEm-Bus-v2.ahk">AHK-ViGEm-Bus-v2</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 150
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/xland/ScreenCapture">ScreenCapture</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX += 150
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY),
    '<a href="https://github.com/owhs/ahk-xaml">ahk-xaml</a>')
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX := OriPosX
    posY += 40
    con := MyGui.Add("GroupBox", Format("x{} y{} w{} h{}", posX, posY, 850, 60), GetLang("感谢以下群友在社区中的活跃参与和宝贵建议：（QQ昵称）"))
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)
    tableItem.AllGroup.Push(con)

    posY += 30
    posX += 10
    con := MyGui.Add("Text", Format("x{} y{}", posX, posY), 'AYu')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '万年置伞')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '别说*不下啦')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '仰望')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), '话听')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX += 100
    con := MyGui.Add("Link", Format("x{} y{}", posX, posY), 'yun')
    tableItem.AllConArr.Push(ItemConInfo(con, tableItem, 1))

    posX := OriPosX
    posY += 50
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 850, 70),
    Format("{}", GetLang("感谢所有打赏支持若梦兔的守护者，以及参与完善 Bug 和需求文档的朋友。")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    con.Focus()
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX := OriPosX
    posY += 50
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 850, 70),
    Format("{}`n{}", GetLang("感谢每一位陪伴我们走过这段旅程的粉丝和群友们！是你们的支持与信任，让这个软件从一个小小的想法，一步步成长为今天的样子。每一次的鼓励、每一条的建议，都是我们前进的动力。"),
    GetLang("感谢你们不离不弃，与我们共同见证每一次的迭代与成长。")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    con.Focus()
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX := OriPosX
    posY += 75
    con := MyGui.Add("Text", Format("x{} y{} w{} h{}", posX, posY, 850, 70),
    Format("{}`n{}", GetLang("再次感谢所有关心、支持、帮助过这个项目的每一个人！"), GetLang("因为有你，这个项目才变得更有意义。")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    con.Focus()
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posX := OriPosX
    posY += 50
    con := MyGui.Add("Text", Format("x{} y{} w{} h30", posX + 600, posY, 200), Format("—— 若梦兔{}", GetLang("敬上")))
    con.SetFont((Format("S{} W{} Q{}", 12, 600, 0)))
    con.Focus()
    conInfo := ItemConInfo(con, tableItem, 1)
    tableItem.AllConArr.Push(conInfo)

    posY += 50
    MySoftData.TableInfo[index].underPosY := posY
}
