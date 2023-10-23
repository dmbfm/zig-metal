const std = @import("std");

var module: *std.build.Module = undefined;

pub fn addExample(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime path: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = path ++ "/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    exe.addModule("zig-metal", module);
    exe.linkFramework("Foundation");
    exe.linkFramework("AppKit");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");

    const run_cmd = b.addRunArtifact(exe);

    const run_step = b.step("run-" ++ name, "Run the sample '" ++ name ++ "'");
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    module = b.createModule(
        .{ .source_file = .{ .path = "src/main.zig" } },
    );

    var target = b.standardTargetOptions(.{});
    var optimize = b.standardOptimizeOption(.{});

    addExample(b, target, optimize, "window", "examples/01-window");
    addExample(b, target, optimize, "primitive", "examples/02-primitive");
    addExample(b, target, optimize, "argbuffers", "examples/03-argbuffers");
    addExample(b, target, optimize, "animation", "examples/04-animation");
    addExample(b, target, optimize, "instancing", "examples/05-instancing");
    addExample(b, target, optimize, "perspective", "examples/06-perspective");
    addExample(b, target, optimize, "lighting", "examples/07-lighting");
}
