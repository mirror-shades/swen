const std = @import("std");
const memory = @import("./memory.zig");
const reporter = @import("./reporter.zig");
const Error = reporter.Error;
const types = @import("./types.zig");
const Token = types.Token;
const TokenTag = types.TokenTag;
const Color = types.Color;
const Vector = types.Vector;
const Text = types.Text;
const Rect = types.Rect;

const TokenTracker = struct {
    tokens: *memory.TokenArray,
    nodes: *memory.NodeArray,
    index: usize,

    pub fn init(tokens: *memory.TokenArray, nodes: *memory.NodeArray) TokenTracker {
        return TokenTracker{
            .tokens = tokens,
            .nodes = nodes,
            .index = 0,
        };
    }

    pub fn peek(self: *TokenTracker) Token {
        return self.tokens.getItem(self.index);
    }

    pub fn peek_ahead(self: *TokenTracker, dist: usize) Token {
        return self.tokens.getItem(self.index + dist);
    }

    pub fn advance(self: *TokenTracker) void {
        self.index += 1;
    }
};

pub fn parse(token_array: *memory.TokenArray, nodes: *memory.NodeArray) Error!types.Root {
    if (token_array.getLength() == 0 or token_array.getItem(0).tag != .root) {
        return reporter.throwError("expected root keyword", token_array.getItem(0).span.line, token_array.getItem(0).span.column, token_array.getItem(0).span.offset, Error.ExpectedRootKeyword);
    }
    var tracker = TokenTracker.init(token_array, nodes);
    const root_token = tracker.peek();
    tracker.advance();

    if (tracker.peek().tag != .lbrace) {
        return reporter.throwError("expected opening brace after root keyword", root_token.span.line, root_token.span.column, root_token.span.offset, Error.ExpectedLeftBrace);
    }
    tracker.advance();

    var desktop = initDesktop();
    var system = initSystem();

    var closed = false;
    while (tracker.peek().tag != .eof) {
        switch (tracker.peek().tag) {
            .desktop => {
                tracker.advance();
                desktop = try parseDesktop(&tracker);
            },
            .system => {
                tracker.advance();
                system = try parseSystem(&tracker);
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found in root parsing at line {d} column {d} offset {d} in root parsing: {t} {s}\n", .{ tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, tracker.peek().tag, tracker.peek().literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after root declaration", root_token.span.line, root_token.span.column, root_token.span.offset, Error.ExpectedRightBrace);
    }

    return types.Root{
        .desktop = desktop,
        .system = system,
    };
}

fn parseDesktop(
    tracker: *TokenTracker,
) !types.Desktop {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after desktop keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var desktop = initDesktop();
    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .surface_rect => {
                tracker.advance();
                desktop.surface_rect = try parseRectBody(tracker, Vector{ .x = 0, .y = 0 });
            },
            .nodes => {
                tracker.advance();
                const nodes_slice = try parseNodeArray(tracker, Vector{ .x = 0, .y = 0 });
                desktop.nodes = nodes_slice;
            },
            .workspaces => {
                tracker.advance();
                const workspaces_slice = try parseWorkspaceArray(tracker.tokens, tracker, token);
                desktop.workspaces = workspaces_slice;
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found in desktop parsing at line {d} column {d} offset {d} in desktop parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after desktop declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    return desktop;
}

fn parseSystem(tracker: *TokenTracker) !types.System {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after system keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var depth: usize = 1;
    while (tracker.index < tracker.tokens.getLength() and depth > 0) {
        const token = tracker.peek();
        switch (token.tag) {
            .lbrace => {
                depth += 1;
            },
            .rbrace => {
                depth -= 1;
            },
            else => {
                std.debug.print("unexpected token found in system parsing at line {d} column {d} offset {d} in system parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
            },
        }
        tracker.advance();
    }

    if (depth != 0) {
        return reporter.throwError("expected closing brace after system declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    return initSystem();
}

fn parseNodeArray(tracker: *TokenTracker, local_position: Vector) Error![]types.Node {
    if (!consumeTag(tracker, .lbracket)) {
        return reporter.throwError("expected opening bracket after nodes keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBracket);
    }

    const start_index = tracker.nodes.getLength();
    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .rect => {
                tracker.advance();
                const rect = try parseRectBody(tracker, local_position);
                tracker.nodes.push(types.Node{ .rect = rect });
            },
            .text => {
                tracker.advance();
                const text = try parseTextBody(tracker, local_position);
                tracker.nodes.push(types.Node{ .text = text });
            },
            .container => {
                tracker.advance();
                const container = try parseContainer(tracker, local_position);
                tracker.nodes.push(types.Node{ .container = container });
            },
            .rbracket => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found in node array parsing at line {d} column {d} offset {d} in node array parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing bracket after nodes declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBracket);
    }

    const all_nodes = tracker.nodes.getArray();
    return all_nodes[start_index..all_nodes.len];
}

fn parseWorkspaceArray(
    tokens: *memory.TokenArray,
    tracker: *TokenTracker,
    workspaces_token: Token,
) ![]types.Workspace {
    if (!consumeTag(tracker, .lbracket)) {
        return reporter.throwError("expected opening bracket after workspaces keyword", workspaces_token.span.line, workspaces_token.span.column, workspaces_token.span.offset, Error.ExpectedLeftBracket);
    }

    var depth: usize = 1;
    while (tracker.index < tokens.getLength() and depth > 0) {
        const token = tracker.peek();
        if (token.tag == .lbracket) {
            depth += 1;
        } else if (token.tag == .rbracket) {
            depth -= 1;
            if (depth == 0) {
                tracker.advance();
                break;
            }
        }
        tracker.advance();
    }

    if (depth != 0) {
        return reporter.throwError("expected closing bracket after workspaces declaration", workspaces_token.span.line, workspaces_token.span.column, workspaces_token.span.offset, Error.ExpectedRightBracket);
    }

    return &[_]types.Workspace{};
}

fn parseRectBody(tracker: *TokenTracker, local_position: Vector) Error!Rect {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var rect = initRect();
    rect.local_position = local_position;
    var size_set = false;
    var position_set = false;
    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            .id => {
                tracker.advance();
                if (rect.id != null) {
                    return reporter.throwError("expected only one id after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateProperty);
                }
                if (tracker.peek().tag != .string) {
                    return reporter.throwError("expected id value after id keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedIdentifier);
                }
                rect.id = tracker.peek().literal;
                tracker.advance();
            },
            .size => {
                if (size_set) {
                    return reporter.throwError("expected only one size after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateProperty);
                }
                tracker.advance();
                rect.size = try parseVector(tracker, "size");
                size_set = true;
            },
            .position => {
                if (position_set) {
                    return reporter.throwError("expected only one position after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateProperty);
                }
                tracker.advance();
                rect.position = try parseVector(tracker, "position");
                position_set = true;
            },
            .background => {
                if (rect.background != null) {
                    return reporter.throwError("expected only one background after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateProperty);
                }
                tracker.advance();
                rect.background = try parseColor(tracker);
            },
            .nodes => {
                tracker.advance();

                if (!consumeTag(tracker, .lbracket)) {
                    return reporter.throwError("expected opening bracket after nodes keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBracket);
                }

                const child_local_position = Vector{
                    .x = local_position.x + rect.position.x,
                    .y = local_position.y + rect.position.y,
                };

                const start_index = tracker.nodes.getLength();
                var closed_children = false;
                while (tracker.peek().tag != .eof) {
                    const child_token = tracker.peek();
                    switch (child_token.tag) {
                        .rect => {
                            tracker.advance();
                            const child_rect = try parseRectBody(tracker, child_local_position);
                            tracker.nodes.push(types.Node{ .rect = child_rect });
                        },
                        .text => {
                            tracker.advance();
                            const child_text = try parseTextBody(tracker, child_local_position);
                            tracker.nodes.push(types.Node{ .text = child_text });
                        },
                        .rbracket => {
                            closed_children = true;
                            tracker.advance();
                            break;
                        },
                        .container => {
                            tracker.advance();
                            const child_container = try parseContainer(tracker, child_local_position);
                            tracker.nodes.push(types.Node{ .container = child_container });
                        },
                        else => {
                            std.debug.print("unexpected token found in rect body parsing at line {d} column {d} offset {d} in rect body parsing: {t} {s}\n", .{ child_token.span.line, child_token.span.column, child_token.span.offset, child_token.tag, child_token.literal });
                            tracker.advance();
                        },
                    }
                }

                if (!closed_children) {
                    return reporter.throwError("expected closing bracket after nodes declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBracket);
                }

                const all_nodes = tracker.nodes.getArray();
                rect.children = all_nodes[start_index..all_nodes.len];
            },
            .text => {
                tracker.advance();
                const text = try parseTextBody(tracker, local_position);
                tracker.nodes.push(types.Node{ .text = text });
            },
            .container => {
                tracker.advance();
                const container = try parseContainer(tracker, local_position);
                tracker.nodes.push(types.Node{ .container = container });
            },
            else => {
                std.debug.print("unexpected token found in rect body parsing at line {d} column {d} offset {d} in rect body parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after rect declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }
    if (!size_set) {
        return reporter.throwError("expected size after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (!position_set) {
        return reporter.throwError("expected position after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }

    return rect;
}

fn parseContainer(tracker: *TokenTracker, local_position: Vector) !types.Container {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after container keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var container = types.Container{
        .id = null,
        .position = null,
        .local_position = local_position,
        .children = null,
    };

    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            .id => {
                tracker.advance();
                if (container.id != null) {
                    return reporter.throwError("expected only one id after container keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateProperty);
                }
                if (tracker.peek().tag != .string) {
                    return reporter.throwError("expected id value after id keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedIdentifier);
                }
                container.id = tracker.peek().literal;
                tracker.advance();
            },
            .position => {
                tracker.advance();
                container.position = try parseVector(tracker, "position");
            },
            .nodes => {
                tracker.advance();
                const container_position = container.position orelse {
                    return reporter.throwError("expected position before nodes in container", token.span.line, token.span.column, token.span.offset, Error.MissingProperty);
                };
                const child_local_position = Vector{
                    .x = local_position.x + container_position.x,
                    .y = local_position.y + container_position.y,
                };
                const nodes_slice = try parseNodeArray(tracker, child_local_position);
                container.children = nodes_slice;
            },
            else => {
                std.debug.print("unexpected token found at line {d} column {d} offset {d} in container parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after container declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    if (container.position == null) {
        return reporter.throwError("expected position in container node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }

    container.local_position = local_position;
    return container;
}

fn parseTextBody(tracker: *TokenTracker, local_position: Vector) !types.Text {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after text keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var text = Text{
        .id = null,
        .body = "",
        .color = Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .position = null,
        .local_position = local_position,
        .text_size = null,
    };

    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .position => {
                tracker.advance();
                text.position = try parseVector(tracker, "position");
            },
            .body => {
                tracker.advance();
                text.body = tracker.peek().literal;
                tracker.advance();
            },
            .color => {
                tracker.advance();
                text.color = try parseColor(tracker);
            },
            .text_size => {
                tracker.advance();
                text.text_size = try consumeNumber(u16, tracker, "text size");
                if (text.text_size == 0) {
                    return reporter.throwError("expected positive text size after text size keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidTextSize);
                }
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found at line {d} column {d} offset {d} in text parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after text declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    if (text.position == null) {
        return reporter.throwError("expected position in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (text.text_size == null) {
        return reporter.throwError("expected text size in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedNumber);
    }
    if (text.body.len == 0) {
        return reporter.throwError("expected text after body keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedString);
    }
    text.local_position = local_position;
    return text;
}

fn parseVector(tracker: *TokenTracker, field: []const u8) !types.Vector {
    if (!consumeTag(tracker, .lparen)) {
        return reporter.throwError("expected opening parenthesis after {s} keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftParen);
    }

    var x_buf: [32]u8 = undefined;
    const x_label = std.fmt.bufPrint(&x_buf, "{s} x", .{field}) catch field;
    const x = try consumeNumber(i32, tracker, x_label);

    if (!consumeTag(tracker, .comma)) {
        return reporter.throwError("expected comma after {s} x", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedComma);
    }

    var y_buf: [32]u8 = undefined;
    const y_label = std.fmt.bufPrint(&y_buf, "{s} y", .{field}) catch field;
    const y = try consumeNumber(i32, tracker, y_label);

    if (!consumeTag(tracker, .rparen)) {
        return reporter.throwError("expected closing parenthesis after {s} keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightParen);
    }

    return types.Vector{ .x = x, .y = y };
}

fn parseColor(tracker: *TokenTracker) !types.Color {
    if (!consumeTag(tracker, .lparen)) {
        return reporter.throwError("expected opening parenthesis after background keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftParen);
    }

    const r = try consumeNumber(u8, tracker, "background r");
    if (!consumeTag(tracker, .comma)) {
        return reporter.throwError("expected comma after background r", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedComma);
    }

    const g = try consumeNumber(u8, tracker, "background g");
    if (!consumeTag(tracker, .comma)) {
        return reporter.throwError("expected comma after background g", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedNumber);
    }

    const b = try consumeNumber(u8, tracker, "background b");
    if (!consumeTag(tracker, .comma)) {
        return reporter.throwError("expected comma after background b", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedNumber);
    }

    const a = try consumeNumber(u8, tracker, "background a");

    if (!consumeTag(tracker, .rparen)) {
        return reporter.throwError("expected closing parenthesis after background keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightParen);
    }

    return types.Color{ .r = r, .g = g, .b = b, .a = a };
}

fn parseLayout(tracker: *TokenTracker) !?types.Layout {
    if (tracker.peek().tag != .identifier) {
        return reporter.throwError("expected layout value", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedIdentifier);
    }
    const value_token = tracker.peek();
    var layout: ?types.Layout = null;
    switch (value_token.tag) {
        .grid => layout = .grid,
        .stack => layout = .stack,
        .float => layout = .float,
        .monocle => layout = .monocle,
        else => {
            return reporter.throwError("expected grid|stack|float|monocle after layout keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedIdentifier);
        },
    }
    tracker.advance();
    return layout;
}

fn consumeNumber(comptime T: type, tracker: *TokenTracker, field: []const u8) !T {
    if (tracker.peek().tag != .number) {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "expected number for {s}", .{field}) catch "expected number";
        return reporter.throwError(msg, tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedNumber);
    }
    const number_token = tracker.peek();
    const value = std.fmt.parseInt(T, number_token.literal, 10) catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "invalid number for {s}", .{field}) catch "invalid number";
        return reporter.throwError(msg, number_token.span.line, number_token.span.column, number_token.span.offset, Error.ExpectedNumber);
    };
    tracker.advance();
    return value;
}

fn consumeTag(tracker: *TokenTracker, tag: TokenTag) bool {
    if (tracker.peek().tag != tag) {
        return false;
    }
    tracker.advance();
    return true;
}

fn initDesktop() types.Desktop {
    return types.Desktop{
        .active_workspace = null,
        .surface_rect = initRect(),
        .nodes = null,
        .layout = null,
        .workspaces = null,
    };
}

fn initRect() Rect {
    return Rect{
        .id = null,
        .size = types.Vector{ .x = 0, .y = 0 },
        .local_position = types.Vector{ .x = 0, .y = 0 },
        .position = types.Vector{ .x = 0, .y = 0 },
        .background = null,
        .children = null,
    };
}

fn initSystem() types.System {
    return types.System{
        .apps = null,
    };
}
