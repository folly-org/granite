const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "granite",
        .root_module = lib_mod,
    });

    // Raylib (via raylib-zig)
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .opengl_version = .auto,
    });

    const raylib = raylib_dep.module("raylib");
    //const raygui = raylib_dep.module("raygui"); 
    const raylib_artifact = raylib_dep.artifact("raylib");

    lib.linkLibrary(raylib_artifact);
    lib_mod.addImport("raylib", raylib);
    //lib_mod.addImport("raygui", raygui);

    // Luau (via lua_wrapper/ziglua)
    const lua = b.dependency("lua_wrapper", .{
        .target = target,
        .optimize = optimize,
        .lang = .luau,
    });

    lib_mod.addImport("lua", lua.module("lua_wrapper"));

    // Freetype and Harfbuzz (via mach_freetype)
    const freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("freetype", freetype_dep.module("mach-freetype"));
    lib_mod.addImport("harfbuzz", freetype_dep.module("mach-harfbuzz"));

    b.installArtifact(lib);
}
