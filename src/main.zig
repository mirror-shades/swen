const std = @import("std");
const lexer = @import("./parsing/lexer.zig");
const parser = @import("./parsing/parser.zig");
const printer = @import("./utils/printer.zig");
const compositor = @import("./render/compositor.zig");
const codegen = @import("./codegen/codegen.zig");
const memory = @import("./core/memory.zig");
const types = @import("./core/types.zig");

pub fn main() !void {
    const file = "./root.swen";
    var source_buffer: [4096]u8 = undefined;
    var token_array = memory.TokenArray.init();

    const source = try std.fs.cwd().readFile(file, &source_buffer);

    std.debug.print("+++++ source file: {s} +++++\n\n", .{file});
    std.debug.print("{s}\n\n", .{source});

    try lexer.lex(source, &token_array);
    std.debug.print("+++++ token array: +<insert>+\n\n", .{});
    for (token_array.getArray()) |token| {
        std.debug.print("token: {t} {s}\n", .{ token.tag, token.literal });
    }
    std.debug.print("\n", .{});

    var node_array = memory.NodeArray.init();
    var root = try parser.parse(&token_array, &node_array);
    printer.printAST(&root);

    var ir_array = memory.IRArray.init();
    var ctx = try compositor.Compositor.init(
        root.desktop.size,
        null, // background is now a node
    );
    defer ctx.deinit();

    // Lower the parsed scene into IR via the dedicated codegen
    // pipeline, which internally uses the richer render IR module.
    try codegen.generate(&root, &ir_array);

    while (ctx.running) {
        ctx.pumpEvents();

        // Render the current frame via IR; node_ids can be used for caching/diffing later.
        ctx.renderIRFrame(ir_array.getArray());
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }
}
