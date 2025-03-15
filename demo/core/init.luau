local font = Renderer.Font.load("./demo/resources/Raveo-Regular.otf")

local renderedOnce = false

globalTest()
Test.libraryTestFn()

App.setMainLoop(function()
    if not renderedOnce then
        Renderer.drawText(font, "Welcome to Granite!", 100, 100, 100, {
            red = 255,
            green = 255,
            blue = 255,
            alpha = 255,
        })
        renderedOnce = true
        return true
    end
    return false
end)