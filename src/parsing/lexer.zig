const std = @import("std");
const types = @import("../core/types.zig");
const Token = types.Token;
const memory = @import("../core/memory.zig");
const helpers = @import("../utils/helpers.zig");
const reporter = @import("../utils/reporter.zig");
const Error = reporter.Error;

pub fn lex(source: []const u8, tokens: *memory.FixedArray(Token, 4096)) !void {
    var current_line: usize = 1;
    var current_column: usize = 1;
    var current_offset: usize = 0;

    var index: usize = 0;
    while (index < source.len) {
        const char = source[index];
        // Ignore carriage returns so Windows-style CRLF line endings don't interfere
        // with tokenization or number parsing.
        if (char == '\r') {
            index += 1;
            continue;
        }
        if (char == '\n') {
            current_line += 1;
            current_column = 1;
            index += 1;
            continue;
        } else {
            current_column += 1;
        }
        if (char == '-') {
            if (helpers.isNumber(source[index + 1])) {
                const end_index = try findNumber(source, index, current_line, current_column, current_offset);
                const new_token = try types.makeNumberToken(current_line, current_column, current_offset, source[index..end_index]);
                tokens.push(new_token);
                index = end_index;
                current_offset = end_index;
                continue;
            } else {
                const new_token = types.makeToken(source[index .. index + 1], current_line, current_column, current_offset);
                tokens.push(new_token);
                index += 1;
                current_offset = index;
                continue;
            }
        }
        if (char == '"') {
            const end_index = try makeString(source, index, current_line, current_column, current_offset);
            // skips the opening quote and the closing quote
            const new_token = types.makeToken(source[index + 1 .. end_index - 1], current_line, current_column, current_offset);
            tokens.push(new_token);
            index = end_index;
            current_offset = end_index;
            continue;
        }
        if (helpers.isNumber(char)) {
            const end_index = try findNumber(source, index, current_line, current_column, current_offset);
            const new_token = try types.makeNumberToken(current_line, current_column, current_offset, source[index..end_index]);
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

fn makeString(source: []const u8, index: usize, line: usize, column: usize, offset: usize) !usize {
    var tracker = index + 1;
    while (tracker < source.len) {
        if (source[tracker] == '\n') {
            return reporter.throwError("string not terminated", line, column, offset, Error.InvalidString);
        }
        if (source[tracker] == '"') {
            return tracker + 1;
        }
        tracker += 1;
    }
    return reporter.throwError("string not terminated", line, column, offset, Error.InvalidString);
}

fn findNumber(source: []const u8, index: usize, line: usize, column: usize, offset: usize) !usize {
    var is_float = false;
    var tracker = index;
    while (tracker < source.len) {
        if (source[tracker] == '.') {
            if (is_float) {
                return reporter.throwError("multiple dots in number", line, column, offset, Error.InvalidNumber);
            }
            is_float = true;
            tracker += 1;
            continue;
        } else if (helpers.isBreakChar(source[tracker])) {
            break;
        } else if (helpers.isNumber(source[tracker])) {
            tracker += 1;
        } else if (source[tracker] == '-') {
            tracker += 1;
        } else {
            return reporter.throwError("expected number after dot", line, column, offset, Error.InvalidNumber);
        }
    }
    return tracker;
}
