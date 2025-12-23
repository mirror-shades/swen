const std = @import("std");
const lexer = @import("./parsing/lexer.zig");
const parser = @import("./parsing/parser.zig");
const printer = @import("./utils/printer.zig");
const compositor = @import("./render/compositor.zig");
const codegen = @import("./codegen/codegen.zig");
const memory = @import("./core/memory.zig");
const types = @import("./core/types.zig");

const sdl = @import("sdl");
const c = sdl.c;

pub fn main() !void {
    // Initialize SDL to get display info
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL initialization failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Get the current display mode
    var display_mode: c.SDL_DisplayMode = undefined;
    if (c.SDL_GetCurrentDisplayMode(0, &display_mode) != 0) {
        std.debug.print("Failed to get display mode: {s}\n", .{c.SDL_GetError()});
        return error.GetDisplayModeFailed;
    }

    const screen_width = display_mode.w;
    const screen_height = display_mode.h;
    std.debug.print("Detected screen size: {}x{}\n", .{ screen_width, screen_height });

    const file = "./root.swen";
    var source_buffer: [4096]u8 = undefined;
    var token_array = memory.TokenArray.init();

    var original_source = try std.fs.cwd().readFile(file, &source_buffer);

    // Simple string replacement for $ variables before parsing
    var processed_source = std.ArrayList(u8).initCapacity(std.heap.page_allocator, original_source.len + 32) catch @panic("failed to allocate");
    defer processed_source.deinit(std.heap.page_allocator);

    var i: usize = 0;
    while (i < original_source.len) {
        if (std.mem.startsWith(u8, original_source[i..], "$screen_width")) {
            var buf: [16]u8 = undefined;
            const width_str = std.fmt.bufPrint(&buf, "{}", .{screen_width}) catch "1024";
            _ = processed_source.appendSlice(std.heap.page_allocator, width_str) catch @panic("failed to append");
            i += 13; // length of "$screen_width"
        } else if (std.mem.startsWith(u8, original_source[i..], "$screen_height")) {
            var buf: [16]u8 = undefined;
            const height_str = std.fmt.bufPrint(&buf, "{}", .{screen_height}) catch "720";
            _ = processed_source.appendSlice(std.heap.page_allocator, height_str) catch @panic("failed to append");
            i += 14; // length of "$screen_height"
        } else {
            _ = processed_source.append(std.heap.page_allocator, original_source[i]) catch @panic("failed to append");
            i += 1;
        }
    }

    const source = processed_source.items;

    try lexer.lex(source, &token_array);
    for (token_array.getArray()) |token| {
        std.debug.print("token: {t} {s}\n", .{ token.tag, token.literal });
    }
    std.debug.print("\n", .{});

    var node_array = memory.NodeArray.init();
    var root = try parser.parse(&token_array, &node_array);
    printer.printAST(&root);

    std.debug.print("Using desktop size: {}x{}\n", .{ root.desktop.size.x, root.desktop.size.y });

    var ir_array = memory.IRArray.init();
    var ctx = try compositor.Compositor.init(
        root.desktop.size,
        root.desktop.background,
    );
    defer ctx.deinit();

    try codegen.generate(&root, &ir_array);

    while (ctx.running) {
        ctx.pumpEvents();
        ctx.renderIRFrame(ir_array.getArray());
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }
}
