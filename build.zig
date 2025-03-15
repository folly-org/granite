const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("granite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
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
    lib.addImport("raylib", raylib);
    //lib.addImport("raygui", raygui);

    // Luau (via lua_wrapper/ziglua)
    const lua = b.dependency("lua_wrapper", .{
        .target = target,
        .optimize = optimize,
        .lang = .luau,
    });

    lib.addImport("lua", lua.module("lua_wrapper"));

    // Freetype and Harfbuzz (via mach_freetype)
    const freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });

    lib.addImport("freetype", freetype_dep.module("mach-freetype"));
    lib.addImport("harfbuzz", freetype_dep.module("mach-harfbuzz"));

    const exe = b.addExecutable(.{
        .name = "granite_demo",
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("granite", lib);

    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-demo", "Run the demo");
    run_step.dependOn(&run_cmd.step);
}
