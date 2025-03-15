local font = Renderer.Font.load("./demo/resources/Raveo-Regular.otf")

globalTest()
Test.libraryTestFn()

local textTbl = {}

App.setMainLoop(function()
    table.insert(textTbl, {
        math.random(1, 1000),
        math.random(1, 1000),
        math.random(1, 255),
        math.random(1, 255),
        math.random(1, 255),
        math.random(1, 255),
    })
    for i,v in pairs(textTbl) do
        Renderer.drawText(font, "Welcome to Granite!", v[1], v[2], 100, {
            red = v[3],
            green = v[4],
            blue = v[5],
            alpha = v[6],
        })
    end
    print("FPS: " .. App.getFPS(), "Texts: " .. #textTbl)
    return true
end)