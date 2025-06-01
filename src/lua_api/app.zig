const std = @import("std");
const lua = @import("zlua");
const rl = @import("raylib");

const Lua = lua.Lua;

fn lGetFPS(L: *Lua) i32 {
    L.pushNumber(@as(f64, @floatFromInt(rl.getFPS())));

    return 1;
}

fn lSetFPS(L: *Lua) i32 {
    const fps = L.checkInteger(1);

    rl.setTargetFPS(fps);

    return 0;
}

fn lGetWindowSize(L: *Lua) i32 {
    L.pushInteger(rl.getScreenWidth());
    L.pushInteger(rl.getScreenHeight());

    return 2;
}

const funcs = [_]lua.FnReg{
    .{ .name = "getFPS", .func = lua.wrap(lGetFPS) },
    .{ .name = "setFPS", .func = lua.wrap(lSetFPS) },
    .{ .name = "getWindowSize", .func = lua.wrap(lGetWindowSize) },
};

pub fn registerLuaFunctions(L: *Lua, libraryName: [:0]const u8) void {
    L.registerFns(libraryName, &funcs);
}
