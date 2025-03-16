const rl = @import("raylib");
const std = @import("std");
const freetype = @import("freetype");

const fRenderer = @import("font_renderer.zig");

pub const RenderCommand = union(enum) {
    text: Text,
    rect: Rect,
    rect_outline: RectOutline,
    rect_round: RectRound,
    rect_round_outline: RectRoundOutline,
    circle: Circle,
    circle_outline: CircleOutline,

    pub const Text = struct {
        text: fRenderer.Text,
        pos: rl.Vector2,
        color: rl.Color,
        should_deinit: bool = true,
    };

    pub const Rect = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        color: rl.Color,
    };

    pub const RectOutline = struct {
        rect: rl.Rectangle,
        line_width: f32,
        color: rl.Color,
    };

    pub const RectRound = struct {
        rect: rl.Rectangle,
        roundness: f32,
        color: rl.Color,
    };

    pub const RectRoundOutline = struct {
        rect: rl.Rectangle,
        roundness: f32,
        line_width: f32,
        color: rl.Color,
    };

    pub const Circle = struct {
        x: i32,
        y: i32,
        radius: f32,
        color: rl.Color,
    };

    pub const CircleOutline = struct {
        x: i32,
        y: i32,
        radius: f32,
        color: rl.Color,
    };
};

const TextKey = struct {
    fontId: u32,
    text: u64,
    size: u32,
};

var alloc: ?std.mem.Allocator = null;

var drawCmdBuf: ?std.ArrayList(RenderCommand) = null;
var redrawCmdBuf: ?std.ArrayList(RenderCommand) = null;

var activeBuf: ?*std.ArrayList(RenderCommand) = null;
var passiveBuf: ?*std.ArrayList(RenderCommand) = null;

var textCache: ?std.AutoHashMap(TextKey, fRenderer.Text) = null;

pub fn init(allocator: std.mem.Allocator) !void {
    alloc = allocator;
    
    drawCmdBuf = std.ArrayList(RenderCommand).init(allocator);
    redrawCmdBuf = std.ArrayList(RenderCommand).init(allocator);

    passiveBuf = &(drawCmdBuf.?);
    activeBuf = &(redrawCmdBuf.?);

    textCache = std.AutoHashMap(TextKey, fRenderer.Text).init(allocator);
}

pub fn deinit() void {
    if (drawCmdBuf == null) @panic("Command buffer not initialized!");
    
    drawCmdBuf.?.deinit();
    redrawCmdBuf.?.deinit();

    fRenderer.deinitFonts();
    fRenderer.deinitAtlasMap();

    var it = textCache.?.valueIterator();
    while (it.next()) |entry| {
        entry.deinit();
    }
    textCache.?.deinit();
}

pub fn drawText(content: [*:0]const u8, x: f32, y: f32, fontId: u32, size: u32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    const text = try textCache.?.getOrPut(.{
        .fontId = fontId,
        .text = std.hash_map.hashString(std.mem.span(content)),
        .size = size,
    });
    
    if (!text.found_existing) {
        var text_obj = try fRenderer.Text.init(alloc.?);
        try text_obj.setText(fontId, std.mem.span(content), size);
        text.value_ptr.* = text_obj;
    }

    try activeBuf.?.*.append(RenderCommand {
        .text = .{
            .text = text.value_ptr.*,
            .pos = rl.Vector2.init(-x, -y),
            .color = color,
            .should_deinit = true,
        }
    });
}

pub fn drawRect(x: i32, y: i32, width: i32, height: i32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .rect = .{
            .x = x, .y = y,
            .width = width, .height = height,
            .color = color
        }
    });
}

pub fn drawRectOutline(x: f32, y: f32, width: f32, height: f32, line_width: f32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .rect_outline = .{
            .rect = rl.Rectangle.init(x, y, width, height),
            .line_width = line_width,
            .color = color
        }
    });
}

pub fn drawRectRound(x: f32, y: f32, width: f32, height: f32, roundness: f32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .rect_round = .{
            .rect = rl.Rectangle.init(x, y, width, height),
            .roundness = roundness,
            .color = color
        }
    });
}

pub fn drawRectRoundOutline(x: f32, y: f32, width: f32, height: f32, roundness: f32, line_width: f32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .rect_round_outline = .{
            .rect = rl.Rectangle.init(x, y, width, height),
            .roundness = roundness,
            .line_width = line_width,
            .color = color
        }
    });
}

pub fn drawCircle(x: i32, y: i32, radius: f32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .circle = .{
            .x = x,
            .y = y,
            .radius = radius,
            .color = color
        }
    });
}

pub fn drawCircleOutline(x: i32, y: i32, radius: f32, color: rl.Color) !void {
    if (alloc == null) @panic("Allocator not initialized!");

    try activeBuf.?.*.append(RenderCommand {
        .circle_outline = .{
            .x = x,
            .y = y,
            .radius = radius,
            .color = color
        }
    });
}

pub fn endRedraw() void {
    if (alloc == null) @panic("Allocator not initialized!");

    std.mem.swap(*std.ArrayList(RenderCommand), &(passiveBuf.?), &(activeBuf.?));

    activeBuf.?.*.clearAndFree();
}

pub fn loadFont(filename: [:0]const u8) !u32 {
    if (alloc == null) @panic("Allocator not initialized!");

    const i = try fRenderer.loadFont(filename.ptr);

    return i;
}

pub fn drawFrame() void {
    for (passiveBuf.?.*.items) |command| {
        switch (command) {
            .text => |cmd| {
                cmd.text.draw(cmd.pos, cmd.color);
            },
            .rect => |cmd| {
                rl.drawRectangle(
                    cmd.x, cmd.y,
                    cmd.width, cmd.height,
                    cmd.color
                );
            },
            .rect_outline => |cmd| {
                rl.drawRectangleLinesEx(
                    cmd.rect,
                    cmd.line_width,
                    cmd.color
                );
            },
            .rect_round => |cmd| {
                rl.drawRectangleRounded(
                    cmd.rect,
                    cmd.roundness,
                    0,
                    cmd.color
                );
            },
            .rect_round_outline => |cmd| {
                rl.drawRectangleRoundedLinesEx(
                    cmd.rect,
                    cmd.roundness,
                    0,
                    cmd.line_width,
                    cmd.color
                );
            },
            .circle => |cmd| {
                rl.drawCircle(cmd.x, cmd.y, cmd.radius, cmd.color);
            },
            .circle_outline => |cmd| {
                rl.drawCircleLines(cmd.x, cmd.y, cmd.radius, cmd.color);
            }
        }
    }
}