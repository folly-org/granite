const std = @import("std");
const rl = @import("raylib");
const lua = @import("zlua");

const renderer = @import("./renderer.zig");
const lua_api = @import("./lua_api/api.zig");
const lua_global = @import("./lua_api/global.zig");
const http = @import("./http.zig");
const signal = @import("./signal.zig");

const Lua = lua.Lua;

pub const App = struct {
    allocator: std.mem.Allocator,
    screen_width: i32,
    screen_height: i32,
    window_name: [:0]const u8,
    base_folder: []const u8,
    globals: std.ArrayList(lua.FnReg),
    libraries: std.StringHashMap(std.ArrayList(lua.FnReg)),

    /// Initializes the app with the given parameters.
    /// 
    /// # Arguments
    /// - `allocator`: The allocator to use for the app.
    /// - `screen_width`: The width of the screen.
    /// - `screen_height`: The height of the screen.
    /// - `window_name`: The name of the window.
    /// - `base_folder`: The base folder of the app. This folder needs to contain the `core` folder and the `core/init.luau` file.
    pub fn init(allocator: std.mem.Allocator, screen_width: i32, screen_height: i32, window_name: [:0]const u8, base_folder: []const u8) App {
        lua_global.setBaseDir(base_folder);
        return App{
            .allocator = allocator,
            .screen_width = screen_width,
            .screen_height = screen_height,
            .window_name = window_name,
            .base_folder = base_folder,
            .globals = std.ArrayList(lua.FnReg).init(allocator),
            .libraries = std.StringHashMap(std.ArrayList(lua.FnReg)).init(allocator),
        };
    }

    /// Deinitializes the app.
    pub fn deinit(self: *App) void {
        self.globals.deinit();
        var iter = self.libraries.valueIterator();
        while (iter.next()) |library| {
            library.deinit();
        }
        self.libraries.deinit();
    }

    /// Runs the app.
    pub fn run(self: *App) anyerror!void {
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

        http.init(self.allocator);
        defer http.deinit();

        try renderer.init(self.allocator);
        defer renderer.deinit();

        var L = try Lua.init(self.allocator);
        defer L.deinit();

        try signal.init(self.allocator);
        defer signal.deinit();

        L.openLibs();
        lua_api.loadLibraries(L);
        for (self.globals.items) |global| {
            L.register(global.name, global.func.?);
        }

        var iter = self.libraries.iterator();
        while (iter.next()) |library| {
            const library_name = try self.allocator.dupeZ(u8, library.key_ptr.*);
            defer self.allocator.free(library_name);
            L.registerFns(library_name, library.value_ptr.*.items);
        }

        const core_init_path = try std.fmt.allocPrintZ(self.allocator, "{s}/core/init.luau", .{self.base_folder});
        defer self.allocator.free(core_init_path);

        lua_api.doFile(L, core_init_path, null) catch |err| {
            std.debug.print("lua err: {}\n", .{err});
        };

        rl.pollInputEvents();

        while (!rl.windowShouldClose()) {
            // Update
            var key: rl.KeyboardKey = rl.getKeyPressed();
            while (key != .null) {
                try signal.emitSignal(L, "KeyPressed", .{ key });
                key = rl.getKeyPressed();
            }

            // Render
            
            try signal.emitSignal(L,"RenderStart", .{ rl.getFrameTime() });

            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.black);
            renderer.drawFrame();

            try signal.emitSignal(L, "RenderEnd", .{});
        }
    }

    /// Registers a global function.
    /// 
    /// # Arguments
    /// - `name`: The name of the global function.
    /// - `function`: The function to register.
    pub fn registerGlobal(self: *App, name: [:0]const u8, function: anytype) !void {
        const c_function = zigFnToLuaCFn(function);
        try self.globals.append(.{ .name = name, .func = c_function });
    }

    /// Registers a library function.
    /// 
    /// # Arguments
    /// - `library_name`: The name of the library.
    /// - `name`: The name of the function.
    /// - `function`: The function to register.
    pub fn registerLibraryFunction(self: *App, library_name: []const u8, name: [:0]const u8, function: anytype) !void {
        const c_function = zigFnToLuaCFn(function);
        const library = try self.libraries.getOrPut(library_name);
        if (!library.found_existing) {
            library.value_ptr.* = std.ArrayList(lua.FnReg).init(self.allocator);
        }
        try library.value_ptr.*.append(.{ .name = name, .func = c_function });
    }
};

fn zigFnToLuaCFn(comptime function: anytype) lua.CFn {
    const info = @typeInfo(@TypeOf(function));
    if (info != .@"fn") {
        @compileError("zigFnToLuaCFn only works with functions");
    }
    if (info.@"fn".is_var_args) {
        @compileError("Unable to create a Lua function from a variadic function");
    }

    return lua.wrap(struct {
        pub fn inner(L: *Lua) i32 {
            const args = std.meta.ArgsTuple(@TypeOf(function));
            var values: args = undefined;
    
            inline for (info.@"fn".params, 0..) |arg, i| {
                const lua_index = i + 1;
                switch (@typeInfo(arg)) {
                    .int => {
                        values[i] = @as(arg, @intCast(L.checkInteger(lua_index)));
                    },
                    .float => {
                        values[i] = @as(arg, @floatCast(L.checkNumber(lua_index)));
                    },
                    .bool => {
                        values[i] = L.toBoolean(lua_index);
                    },
                    .pointer => |ptr| {
                        if (ptr.size == .slice) {
                            values[i] = L.checkString(lua_index);
                        } else {
                            @compileError("Unsupported pointer type");
                        }
                    },
                    .optional => |opt| {
                        if (L.isNoneOrNil(lua_index)) {
                            values[i] = null;
                        } else {
                            switch (@typeInfo(opt.child)) {
                                .int => {
                                    values[i] = @as(opt.child, @intCast(L.checkInteger(lua_index)));
                                },
                                .float => {
                                    values[i] = @as(opt.child, @floatCast(L.checkNumber(lua_index)));
                                },
                                .bool => {
                                    values[i] = L.toBoolean(lua_index);
                                },
                                else => @compileError("Unsupported optional type"),
                            }
                        }
                    },
                    else => {
                        @compileError("Unsupported argument type");
                    }
                }
            }

            const return_type = info.@"fn".return_type orelse void;
            const result = @call(.auto, function, values);
            var result_count: i32 = 0;

            switch (@typeInfo(return_type)) {
                .int => {
                    L.pushInteger(@as(i64, @intCast(result)));
                    result_count = 1;
                },
                .float => {
                    L.pushNumber(@as(f64, @floatCast(result)));
                    result_count = 1;
                },
                .bool => {
                    L.pushBoolean(result);
                    result_count = 1;
                },
                .optional => |opt| {
                    if (result) |value| {
                        switch (@typeInfo(opt.child)) {
                            .int => L.pushInteger(@as(i64, @intCast(value))),
                            .float => L.pushNumber(@as(f64, @floatCast(value))),
                            .bool => L.pushBoolean(value),
                            else => @compileError("Unsupported optional return type"),
                        }
                    } else {
                        L.pushNil();
                    }
                    result_count = 1;
                },
                .@"struct" => |s| {
                    inline for (s.fields) |field| {
                        switch (@typeInfo(field.type)) {
                            .int => L.pushInteger(@as(i64, @intCast(@field(result, field.name)))),
                            .float => L.pushNumber(@as(f64, @floatCast(@field(result, field.name)))),
                            .bool => L.pushBoolean(@field(result, field.name)),
                            else => @compileError("Unsupported struct field type"),
                        }
                        result_count += 1;
                    }
                },
                .void => {},
                else => @compileError("Unsupported return type"),
            }

            return result_count;
        }
    }.inner);
}