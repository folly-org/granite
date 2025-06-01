const std = @import("std");
const lua = @import("zlua");

const Lua = lua.Lua;

// TODO: add some attributes, like for :Once, etc.
var signals: std.StringHashMap(std.AutoHashMapUnmanaged(i32, void)) = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    signals = std.StringHashMap(std.AutoHashMapUnmanaged(i32, void)).init(allocator);
    alloc = allocator;

    try createSignal("RenderStart");
    try createSignal("RenderEnd");

    try createSignal("KeyPressed");
}

pub fn deinit() void {
    var it = signals.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(alloc);
    }
    signals.deinit();
}

pub fn createSignal(signal: []const u8) !void {
    try signals.put(signal, .{});
}

pub fn addSignalConnection(signal: []const u8, ref: i32) void {
    if (signals.getPtr(signal)) |connections| {
        connections.put(alloc, ref, {}) catch unreachable;
    } else {
        std.debug.print("Signal not found: {s}\n", .{signal});
    }
}

pub fn removeSignalConnection(signal: []const u8, ref: i32) void {
    if (signals.getPtr(signal)) |connections| {
        _ = connections.remove(ref);
    } else {
        std.debug.print("Signal not found: {s}\n", .{signal});
    }
}

pub fn emitSignal(L: *Lua, signal: []const u8, Args: anytype) !void {
    const ArgsType = @TypeOf(Args);
    if (@typeInfo(ArgsType) != .@"struct") {
        @compileError("Args must be a struct");
    }

    if (signals.getPtr(signal)) |connections| {
        var it = connections.iterator();
        while (it.next()) |connection| {
            _ = L.rawGetIndex(lua.registry_index, connection.key_ptr.*);
            if (L.isNil(-1)) {
                std.debug.print("connection not found: {s}\n", .{signal});
                L.pop(1); // Pop the nil value
                continue;
            }

            const fields = @typeInfo(ArgsType).@"struct".fields;
            comptime var i = 0;
            inline while (i < fields.len) : (i += 1) {
                const field = fields[i];
                switch (@typeInfo(field.type)) {
                    .int => L.pushInteger(@as(i64, @intCast(@field(Args, field.name)))),
                    .float => L.pushNumber(@as(f64, @floatCast(@field(Args, field.name)))),
                    .bool => L.pushBoolean(@field(Args, field.name)),
                    .pointer => |ptr| {
                        if (ptr.size == .slice) {
                            L.pushString(@field(Args, field.name));
                        } else {
                            @compileError("Unsupported pointer type");
                        }
                    },
                    .@"enum" => {
                        const enum_value = @field(Args, field.name);
                        L.pushInteger(@intFromEnum(enum_value));
                    },
                    else => @compileError("Unsupported struct field type"),
                }
            }

            L.protectedCall(.{
                .args = fields.len,
                .results = 0,
                .msg_handler = 0,
            }) catch |err| {
                std.debug.print("Error calling signal: {s}\n", .{signal});
                std.debug.print("Error: {any}\n", .{err});
            };
        }
    } else {
        std.debug.print("Signal not found: {s}\n", .{signal});
    }
}