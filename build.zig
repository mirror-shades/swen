const std = @import("std");
const sdl = @import("sdl");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .msvc,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Generate SDL2 config for the SDL.zig SDK so no external JSON
    // file needs to be maintained manually.
    const sdl_config_path = ".build_config/sdl.json";
    {
        var cwd = std.fs.cwd();
        cwd.makePath(".build_config") catch @panic("failed to create SDL config directory");

        var file = cwd.createFile(sdl_config_path, .{ .truncate = true }) catch @panic("failed to create SDL config file");
        defer file.close();

        // Hard‑wire your Scoop SDL2 paths here.
        const json =
            "{\"x86_64-windows-msvc\":{\"include\":\"C:/Users/User/scoop/apps/sdl2/current/include\",\"libs\":\"C:/Users/User/scoop/apps/sdl2/current/lib\",\"bin\":\"C:/Users/User/scoop/apps/sdl2/current/lib\"}}";
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

    // Initialize SDL2 SDK from the `sdl` dependency, pointing it at the
    // generated config file.
    const sdk = sdl.init(b, .{ .maybe_config_path = sdl_config_path });

    // Link against SDL2 and expose the wrapper module as "sdl"
    sdk.link(exe, .dynamic, sdl.Library.SDL2);
    exe.root_module.addImport("sdl", sdk.getWrapperModule());

    exe.linkLibC();

    // Ensure SDL2.dll is available next to the executable at runtime.
    const sdl_dll: std.Build.LazyPath = .{
        .cwd_relative = "C:/Users/User/scoop/apps/sdl2/current/lib/SDL2.dll",
    };
    _ = b.addInstallFileWithDir(sdl_dll, .bin, "SDL2.dll");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);
}
