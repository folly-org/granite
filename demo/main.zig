const std = @import("std");
const granite = @import("granite");

fn globalTest() void {
    std.debug.print("Hello from a zig function made as a lua global function!\n", .{});
}

fn libraryTestFn() void {
    std.debug.print("Hello from a zig function in a library called 'Test'!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = granite.App.init(allocator, 1280, 720, "Granite Demo", "demo");
    defer app.deinit();

    try app.registerGlobal("globalTest", globalTest);
    try app.registerLibraryFunction("Test", "libraryTestFn", libraryTestFn);

    try app.run();
}
