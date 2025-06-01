const std = @import("std");
const lua = @import("zlua");

const sig = @import("../signal.zig");

const Lua = lua.Lua;

const Connection = struct {
    signal: []const u8,
    ref: i32,
};

fn createSignalFunctions(comptime signal: []const u8) [1]lua.FnReg {
    return [_]lua.FnReg{
        .{
            .name = "Connect",
            .func = lua.wrap(struct {
                pub fn connect(L: *Lua) i32 {
                    const ref = L.ref(2) catch 0;

                    std.debug.print("signal: {s}, ref: {}\n", .{ signal, ref });

                    sig.addSignalConnection(signal, ref);

                    var connection = L.newUserdata(Connection);
                    connection.signal = signal;
                    connection.ref = ref;

                    _ = L.getField(lua.registry_index, "Connection");
                    L.setMetatable(-2);

                    return 1;
                }
            }.connect),
        }
    };
}

fn lDisconnect(L: *Lua) i32 {
    const connection = L.checkUserdata(Connection, 1, "Connection");
    sig.removeSignalConnection(connection.signal, connection.ref);
    L.unref(connection.ref);
    return 0;
}

const metatable_reg = [_]lua.FnReg{
    .{
        .name = "Disconnect",
        .func = lua.wrap(lDisconnect),
    },
};

pub fn registerLuaFunctions(L: *Lua, libraryName: [:0]const u8) void {
    L.newMetatable("Connection") catch unreachable;
    _ = L.pushStringZ("__index");
    L.pushValue(-2);
    L.setTable(-3);

    L.registerFns(null, &metatable_reg);

    L.newTable();

    _ = L.pushStringZ("RenderStart");
    L.newTable();
    L.registerFns(null, &createSignalFunctions("RenderStart"));
    L.setTable(-3);

    _ = L.pushStringZ("RenderEnd");
    L.newTable();
    L.registerFns(null, &createSignalFunctions("RenderEnd"));
    L.setTable(-3);

    _ = L.pushStringZ("KeyPressed");
    L.newTable();
    L.registerFns(null, &createSignalFunctions("KeyPressed"));
    L.setTable(-3);

    L.setGlobal(libraryName);
}
