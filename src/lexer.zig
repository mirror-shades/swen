const std = @import("std");
const types = @import("./types.zig");
const Token = types.Token;
const memory = @import("./memory.zig");
const helpers = @import("./helpers.zig");

pub fn lex(source: []const u8, tokens: *memory.TokenArray) !void {
    var current_line: usize = 1;
    var current_column: usize = 1;
    var current_offset: usize = 0;

    var index: usize = 0;
    while (index < source.len) {
        const char = source[index];
        if (char == '\n') {
            current_line += 1;
            current_column = 1;
            index += 1;
            continue;
        } else {
            current_column += 1;
        }
        if (helpers.isNumber(char)) {
            const end_index = try makeNumber(source, index, current_line, current_column, current_offset);
            const new_token = types.makeToken(source[index..end_index], current_line, current_column, current_offset);
            tokens.push(new_token);
            index = end_index;
            current_offset = end_index;
            continue;
        }
        if (helpers.isSymbol(char)) {
            const new_token = types.makeToken(source[index .. index + 1], current_line, current_column, current_offset);
            tokens.push(new_token);
            index += 1;
            current_offset = index;
            continue;
        }
        if (helpers.isIdentifier(char)) {
            var tracker = index;
            while (tracker < source.len and !helpers.isBreakChar(source[tracker])) {
                tracker += 1;
            }
            if (tracker > index) {
                const new_token = types.makeToken(source[index..tracker], current_line, current_column, current_offset);
                tokens.push(new_token);
                index = tracker;
                continue;
            }
        }
        index += 1;
    }
    tokens.push(types.makeToken("eof", current_line, current_column, current_offset));
}

fn makeNumber(source: []const u8, index: usize, line: usize, column: usize, offset: usize) !usize {
    var is_float = false;
    var tracker = index;
    while (tracker < source.len) {
        if (source[tracker] == '.') {
            if (is_float) {
                std.debug.print("error: invalid number at line {d} column {d} offset {d}\n", .{ line, column, offset });
                std.debug.print("multiple dots in number\n", .{});
                return error.InvalidNumber;
            }
            is_float = true;
            tracker += 1;
            continue;
        } else if (helpers.isBreakChar(source[tracker])) {
            break;
        } else if (helpers.isNumber(source[tracker])) {
            tracker += 1;
        } else {
            std.debug.print("error: invalid number at line {d} column {d} offset {d}\n", .{ line, column, offset });
            std.debug.print("expected number after dot\n", .{});
            return error.InvalidNumber;
        }
    }
    return tracker;
}
