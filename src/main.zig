const std = @import("std");
const lexer = @import("./lexer.zig");
const parser = @import("./parser.zig");
const ast = @import("./ast.zig");
const compositor = @import("./compositor.zig");
const memory = @import("./memory.zig");
pub fn main() !void {
    const file = "./root.swen";
    var source_buffer: [4096]u8 = undefined;
    var token_array = memory.TokenArray.init();

    const source = try std.fs.cwd().readFile(file, &source_buffer);

    std.debug.print("source file: \n\n{s}\n", .{source});

    try lexer.lex(source, &token_array);

    var node_array = memory.NodeArray.init();
    var root = try parser.parse(&token_array, &node_array);
    ast.printAST(&root);

    var rect_array = memory.RectArray.init();
    try compositor.compose(root, &rect_array);
}
