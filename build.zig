const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "swen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    exe.linkSystemLibrary("pathfinder");
    exe.linkSystemLibrary("SDL2");
    const pathfinder_include = "/tmp/pathfinder-destdir/usr/local/include/pathfinder";
    const pathfinder_lib = "/tmp/pathfinder-destdir/usr/local/lib";
    exe.addIncludePath(.{ .cwd_relative = pathfinder_include });
    exe.addLibraryPath(.{ .cwd_relative = pathfinder_lib });
    exe.root_module.addRPath(.{ .cwd_relative = pathfinder_lib });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);
}
