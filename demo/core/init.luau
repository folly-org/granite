local font = Renderer.Font.load("./demo/resources/Raveo-Regular.otf")

globalTest()
Test.libraryTestFn()

local textTbl = {}

local count = 0

local connection = Signal.RenderStart:Connect(function(delta_time)
    count += 1
    print(count, delta_time)
end)

Signal.RenderEnd:Connect(function()
    if count > 20 then
        connection:Disconnect()
        print("Disconnected")
        count = 0
    end
end)

function randomCharacters(length)
    local result = ""
    for i = 1, length do
        result = result .. string.char(math.random(1, 255))
    end
    return result
end

Signal.RenderStart:Connect(function(delta_time)
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
    Renderer.drawText(font, "FPS: " .. App.getFPS() .. " - Texts: " .. #textTbl, 100, 100 , 100, {
        red = 255,
        green = 255,
        blue = 255,
        alpha = 255,
    })
    Renderer.endRedraw()
end)

Signal.KeyPressed:Connect(function(key)
    print(key)
end)