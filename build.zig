const std = @import("std");
const sdl = @import("sdl");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const default_target: std.Target.Query = if (builtin.os.tag == .windows)
        .{ .abi = .msvc }
    else
        .{};
    const target = b.standardTargetOptions(.{ .default_target = default_target });
    const optimize = b.standardOptimizeOption(.{});

    const target_info = target.result;
    const is_windows = target_info.os.tag == .windows;

    const sdl_config_path = ".build_config/sdl.json";
    {
        var cwd = std.fs.cwd();
        cwd.makePath(".build_config") catch @panic("failed to create SDL config directory");

        var file = cwd.createFile(sdl_config_path, .{ .truncate = true }) catch @panic("failed to create SDL config file");
        defer file.close();

        const json = if (is_windows)
            "{\"x86_64-windows-msvc\":{\"include\":\"C:/Users/User/scoop/apps/sdl2/current/include\",\"libs\":\"C:/Users/User/scoop/apps/sdl2/current/lib\",\"bin\":\"C:/Users/User/scoop/apps/sdl2/current/lib\"}}"
        else
            "{\"x86_64-linux-gnu\":{\"include\":\"/usr/include/SDL2\",\"libs\":\"/usr/lib\",\"bin\":\"/usr/lib\"}}";
        file.writeAll(json) catch @panic("failed to write SDL config");
    }

    const exe = b.addExecutable(.{
        .name = "swen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const sdk = sdl.init(b, .{ .maybe_config_path = sdl_config_path });

    sdk.link(exe, .dynamic, sdl.Library.SDL2);
    exe.root_module.addImport("sdl", sdk.getWrapperModule());

    exe.linkLibC();

    if (is_windows) {
        const sdl_dll: std.Build.LazyPath = .{
            .cwd_relative = "C:/Users/User/scoop/apps/sdl2/current/lib/SDL2.dll",
        };
        const dll_install = b.addInstallFileWithDir(sdl_dll, .bin, "SDL2.dll");
        b.getInstallStep().dependOn(&dll_install.step);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);
}
