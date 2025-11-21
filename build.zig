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
        .opengl_version = .auto,
    });

    const raylib = raylib_dep.module("raylib");
    //const raygui = raylib_dep.module("raygui"); 
    const raylib_artifact = raylib_dep.artifact("raylib");

    lib.linkLibrary(raylib_artifact);
    lib.addImport("raylib", raylib);
    //lib.addImport("raygui", raygui);

    // Luau (via zlua)
    const lua = b.dependency("zlua", .{
        .lang = .luau,
    });

    lib.addImport("zlua", lua.module("zlua"));

    // Freetype and Harfbuzz (via mach_freetype)
    const freetype_dep = b.dependency("mach_freetype", .{});

    lib.addImport("freetype", freetype_dep.module("mach-freetype"));
    lib.addImport("harfbuzz", freetype_dep.module("mach-harfbuzz"));

    // Demo Executable

    const demo_module = b.addModule("granite_demo", .{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_module.addImport("granite", lib);

    const exe = b.addExecutable(.{
        .name = "granite_demo",
        .root_module = demo_module,
    });
    b.installArtifact(exe);

    // Zig Check Executable
    const exe_check = b.addExecutable(.{
        .name = "granite_check",
        .root_module = demo_module,
    });

    // Run Demo Command
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-demo", "Run the demo");
    run_step.dependOn(&run_cmd.step);

    // Check Command
    const check = b.step("check", "Check if demo (and granite) compiles");
    check.dependOn(&exe_check.step);
}
