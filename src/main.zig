const std = @import("std");
const lexer = @import("./lexer.zig");
const parser = @import("./parser.zig");
const ast = @import("./ast.zig");
const compositor = @import("./compositor.zig");
pub fn main() !void {
    const file = "./root.swen";
    var source_buffer: [4096]u8 = undefined;

    const source = try std.fs.cwd().readFile(file, &source_buffer);

    std.debug.print("source file: \n\n{s}\n", .{source});

    const tokens = try lexer.lex(source);

    const root = try parser.parse(tokens);
    ast.printAST(root);

    try compositor.compose(root);
}
