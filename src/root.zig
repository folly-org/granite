const std = @import("std");
const rl = @import("raylib");
const lua = @import("lua");

const renderer = @import("./renderer.zig");
const lua_api = @import("./lua_api/api.zig");
const lua_app_api = @import("./lua_api/app.zig");
const lua_global = @import("./lua_api/global.zig");
const http = @import("./http.zig");

const Lua = lua.Lua;

pub const App = struct {
    screen_width: u32,
    screen_height: u32,
    window_name: []const u8,
    base_folder: []const u8,

    /// Initializes the app with the given parameters.
    /// 
    /// # Arguments
    /// - `allocator`: The allocator to use for the app.
    /// - `screen_width`: The width of the screen.
    /// - `screen_height`: The height of the screen.
    /// - `window_name`: The name of the window.
    /// - `base_folder`: The base folder of the app. This folder needs to contain the `core` folder and the `core/init.luau` file.
    pub fn init(screen_width: u32, screen_height: u32, window_name: []const u8, base_folder: []const u8) App {
        lua_global.setBaseDir(base_folder);
        return App{
            .screen_width = screen_width,
            .screen_height = screen_height,
            .window_name = window_name,
            .base_folder = base_folder,
        };
    }

    /// Runs the app.
    pub fn run(self: *App) anyerror!void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
        const alloc = gpa.allocator();
        defer _ = gpa.deinit();

        rl.setConfigFlags(.{
            .vsync_hint = true,
            .msaa_4x_hint = true,
            .window_highdpi = true,
        });

        rl.initWindow(self.screen_width, self.screen_height, self.window_name);
        defer rl.closeWindow();

        rl.setWindowState(.{
            .window_resizable = true,
        });

        http.init(alloc);
        defer http.deinit();

        try renderer.init(alloc);
        defer renderer.deinit();

        var L = try Lua.init(alloc);
        defer L.deinit();

        L.openLibs();
        lua_api.loadLibraries(L);

        const core_init_path = try std.fmt.allocPrintZ(alloc, "{s}/core/init.luau", .{self.base_folder});
        defer alloc.free(core_init_path);

        lua_api.doFile(L, core_init_path, null) catch |err| {
            std.debug.print("lua err: {}\n", .{err});
        };

        rl.pollInputEvents();

        while (!rl.windowShouldClose()) {
            if (lua_app_api.callMainLoop(L)) renderer.endRedraw();

            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.black);
            renderer.drawFrame();
        }
    }
};