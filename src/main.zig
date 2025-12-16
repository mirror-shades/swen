const std = @import("std");
const lexer = @import("./parsing/lexer.zig");
const parser = @import("./parsing/parser.zig");
const printer = @import("./utils/printer.zig");
const compositor = @import("./render/compositor.zig");
const memory = @import("./core/memory.zig");
const types = @import("./core/types.zig");

pub fn main() !void {
    const file = "./root.swen";
    var source_buffer: [4096]u8 = undefined;
    var token_array = memory.TokenArray.init();

    const source = try std.fs.cwd().readFile(file, &source_buffer);

    std.debug.print("source file: \n\n{s}\n", .{source});

    try lexer.lex(source, &token_array);
    for (token_array.getArray()) |token| {
        std.debug.print("token: {t} {s}\n", .{ token.tag, token.literal });
    }

    var node_array = memory.NodeArray.init();
    var root = try parser.parse(&token_array, &node_array);
    printer.printAST(&root);

    var rect_array = memory.RectArray.init();
    var ctx = try compositor.Compositor.init(
        root.desktop.size,
        null, // background is now a node
    );
    defer ctx.deinit();

    // Initial scene.
    const scene = try compositor.buildSceneFromRoot(root, &rect_array);
    try ctx.setScene(scene);

    var dirty = false;
    while (ctx.running) {
        ctx.pumpEvents();

        if (dirty) {
            const new_scene = try compositor.buildSceneFromRoot(root, &rect_array);
            try ctx.setScene(new_scene);
            dirty = false;
        }

        ctx.renderFrame();
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }
}
