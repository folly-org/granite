const std = @import("std");
const lua = @import("zlua");
const rl = @import("raylib");

const api = @import("api.zig");
const http = @import("../http.zig");

const Lua = lua.Lua;

var base_dir: ?[]const u8 = null;

pub fn setBaseDir(dir: []const u8) void {
    base_dir = dir;
}

// TODO: use this function to import fonts
fn lRequire(L: *Lua) i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const path: [:0]const u8 = L.checkString(1);
    if (path.len == 0) return 0;

    if (!std.mem.eql(u8, path[0..1], "@")) { // require in cwd
        var info: lua.DebugInfo = undefined;

        L.getInfo(1, .{ .s = true }, &info);

        const full_src_path = alloc.dupeZ(u8, info.source) catch return 0;
        defer alloc.free(full_src_path);

        const dir = std.fs.path.dirname(full_src_path).?;

        const full_path = std.fmt.allocPrintSentinel(alloc, "{s}/{s}/{s}.luau", .{ base_dir.?, dir, path }, 0) catch |err| return api.make_lua_err("allocPrintZ full_path cwd", err);
        defer alloc.free(full_path);

        api.doFile(L, full_path, .{ .args = 0, .results = 1, .msg_handler = 0 }) catch |err| return api.make_lua_err("dofile cwd", err);

        return 1;
    }

    const full_path = std.fmt.allocPrintSentinel(alloc, "{s}/{s}.luau", .{ base_dir.?, path[1..] }, 0) catch |err| return api.make_lua_err("allocPrintZ full_path @", err);
    defer alloc.free(full_path);

    api.doFile(L, full_path, .{ .args = 0, .results = 1, .msg_handler = 0 }) catch |err| return api.make_lua_err("dofile @", err);

    return 1;
}

fn lWait(L: *Lua) i32 {
    std.Thread.sleep(@as(u64, @intFromFloat((L.optNumber(1) orelse rl.getFrameTime()) * std.time.ns_per_s)));

    return 0;
}

fn lFetch(L: *Lua) i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const url = std.Uri.parse(L.checkString(1)) catch return api.make_lua_err("invalid url", error.InvalidUri);
    if (L.isNoneOrNil(2)) {
        return 0;
    }

    _ = L.getField(2, "method");
    var method: std.http.Method = std.meta.stringToEnum(std.http.Method, L.checkString(-1)) orelse return api.make_lua_err("invalid method", error.InvalidMethod);
    L.pop(1);

    _ = L.getField(2, "headers");

    L.pushNil();
    var is_ua_set = false;
    var headers = std.ArrayList(std.http.Header).empty;
    while (L.next(-2)) {
        const key = L.checkString(-2);
        const value = L.checkString(-1);
        if (std.ascii.eqlIgnoreCase(key, "user-agent")) {
            is_ua_set = true;
        }
        headers.append(alloc, .{ .name = key, .value = value }) catch return api.make_lua_err("fetch headers", error.OutOfMemory);
        L.pop(1);
    }
    defer headers.deinit(alloc);
    L.pop(1);

    _ = L.getField(2, "body");
    const body: ?[:0]const u8 = if (L.isNoneOrNil(-1)) null else L.checkString(-1);
    if (body == null) {
        method = .GET;
    }
    L.pop(1);

    var writer = std.Io.Writer.Allocating.init(alloc);
    defer writer.deinit();

    const redirect_behavior: std.http.Client.Request.RedirectBehavior = if (body == null) @enumFromInt(3) else .unhandled;

    var req = std.http.Client.request(http.getClient(), method, url, .{
        //.server_header_buffer = &server_header_buffer,
        .headers = .{ 
            .user_agent = if (is_ua_set) .omit else .default, 
            .authorization = .omit
        },
        .extra_headers = headers.items,
        .redirect_behavior = redirect_behavior,
    }) catch return api.make_lua_err("failed to fetch", error.FetchFailed);
    defer req.deinit();

    if (body) |payload| {
        req.transfer_encoding = .{ .content_length = payload.len };
        var body_req = req.sendBody(&.{}) catch return api.make_lua_err("failed to send body", error.SendBodyFailed);
        body_req.writer.writeAll(payload) catch return api.make_lua_err("failed to write body", error.WriteBodyFailed);
        body_req.end() catch return api.make_lua_err("failed to end body", error.EndBodyFailed);
    }

    const redirect_buffer: []u8 = if (redirect_behavior == .unhandled) &.{} else alloc.alloc(u8, 8 * 1024) catch return api.make_lua_err("failed to alloc redirect buffer", error.OutOfMemory);
    defer alloc.free(redirect_buffer);

    var response = req.receiveHead(redirect_buffer) catch return api.make_lua_err("failed to receive head", error.ReceiveHeadFailed);

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => alloc.alloc(u8, std.compress.zstd.default_window_len) catch return api.make_lua_err("failed to alloc decompress buffer", error.OutOfMemory),
        .deflate, .gzip => alloc.alloc(u8, std.compress.flate.max_window_len) catch return api.make_lua_err("failed to alloc decompress buffer", error.OutOfMemory),
        .compress => return api.make_lua_err("unsupported compression method", error.UnsupportedCompressionMethod),
    };
    defer alloc.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    L.newTable();

    _ = L.pushString("status");
    _ = L.pushInteger(@intFromEnum(response.head.status));
    L.setTable(-3);

    _ = L.pushString("body");
    _ = L.pushString(reader.buffered());
    L.setTable(-3);

    _ = L.pushString("headers");
    L.newTable();

    var header_iter = std.http.HeaderIterator.init(response.head.bytes);
    while (header_iter.next()) |header| {
        _ = L.pushString(header.name);
        _ = L.pushString(header.value);
        L.setTable(-3);
    }

    L.setTable(-3);

    return 1;
}

const funcs = [_]lua.FnReg{
    .{ .name = "require", .func = lua.wrap(lRequire) },
    .{ .name = "wait", .func = lua.wrap(lWait) },
    .{ .name = "fetch", .func = lua.wrap(lFetch) },
};

pub fn registerLuaFunctions(L: *Lua, libraryName: [:0]const u8) void {
    _ = libraryName;

    for (funcs) |func| {
        L.register(func.name, func.func.?);
    }
}
