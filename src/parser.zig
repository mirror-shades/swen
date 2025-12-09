const std = @import("std");
const memory = @import("./memory.zig");
const types = @import("./types.zig");
const Token = types.Token;
const TokenTag = types.TokenTag;

const TokenTracker = struct {
    tokens: *memory.TokenArray,
    index: usize,

    pub fn init(tokens: *memory.TokenArray) TokenTracker {
        return TokenTracker{
            .tokens = tokens,
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

pub fn parse(token_array: *memory.TokenArray, nodes: *memory.NodeArray) !types.Root {
    if (token_array.getLength() == 0 or token_array.getItem(0).tag != .root) {
        return error.InvalidRootDeclaration;
    }
    var tracker = TokenTracker.init(token_array);
    const root_token = tracker.peek();
    tracker.advance();

    if (tracker.peek().tag != .lbrace) {
        declarationError("root", root_token, "expected opening brace after root keyword", .{});
        return error.InvalidRootDeclaration;
    }

    var desktop = initDesktop();
    var system = initSystem();

    var closed = false;
    while (tracker.peek().tag != .eof) {
        switch (tracker.peek().tag) {
            .desktop => {
                tracker.advance();
                desktop = try parseDesktop(nodes, &tracker);
            },
            .system => {
                tracker.advance();
                system = try parseSystem(nodes, &tracker);
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                tracker.advance();
            },
        }
    }

    if (!closed) {
        declarationError("root", root_token, "expected closing brace after root declaration", .{});
        return error.InvalidRootDeclaration;
    }

    return types.Root{
        .desktop = desktop,
        .system = system,
    };
}

fn parseDesktop(
    nodes: *memory.NodeArray,
    tracker: *TokenTracker,
) !types.Desktop {
    if (!consumeTag(tracker.tokens.getArray(), &tracker.index, .lbrace)) {
        declarationError("desktop", tracker.peek(), "expected opening brace after desktop keyword", .{});
        return error.InvalidDesktopDeclaration;
    }

    var desktop = initDesktop();
    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .surface_rect => {
                tracker.advance();
                desktop.surface_rect = try parseRectBody(tracker.tokens, &tracker.index, token);
            },
            .nodes => {
                tracker.advance();
                const nodes_slice = try parseNodeArray(tracker.tokens, nodes, &tracker.index, token);
                desktop.nodes = nodes_slice;
            },
            .workspaces => {
                tracker.advance();
                const workspaces_slice = try parseWorkspaceArray(tracker.tokens, &tracker.index, token);
                desktop.workspaces = workspaces_slice;
            },
            .layout => {
                tracker.advance();
                desktop.layout = try parseLayout(tracker.tokens.getArray(), &tracker.index, token);
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                tracker.advance();
            },
        }
    }

    if (!closed) {
        declarationError("desktop", tracker.peek(), "expected closing brace after desktop declaration", .{});
        return error.InvalidDesktopDeclaration;
    }

    return desktop;
}

fn parseSystem(nodes: *memory.NodeArray, tracker: *TokenTracker) !types.System {
    _ = nodes;
    if (!consumeTag(tracker.tokens.getArray(), &tracker.index, .lbrace)) {
        declarationError("system", tracker.peek(), "expected opening brace after system keyword", .{});
        return error.InvalidSystemDeclaration;
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
            else => {},
        }
        tracker.advance();
    }

    if (depth != 0) {
        declarationError("system", tracker.peek(), "expected closing brace after system declaration", .{});
        return error.InvalidSystemDeclaration;
    }

    return initSystem();
}

fn parseNodeArray(
    tokens: *memory.TokenArray,
    node_buffer: *memory.NodeArray,
    index: *usize,
    nodes_token: Token,
) ![]types.Node {
    if (!consumeTag(tokens.getArray(), index, .lbracket)) {
        declarationError("desktop", nodes_token, "expected opening bracket after nodes keyword", .{});
        return error.InvalidDesktopDeclaration;
    }

    var closed = false;
    while (index.* < tokens.getLength()) {
        const token = tokens.getItem(index.*);
        switch (token.tag) {
            .rect => {
                if (node_buffer.getLength() >= node_buffer.data.len) {
                    declarationError(
                        "desktop",
                        nodes_token,
                        "too many nodes in desktop declaration (max {d})",
                        .{node_buffer.getLength()},
                    );
                    return error.InvalidDesktopDeclaration;
                }
                index.* += 1;
                const rect = try parseRectBody(tokens, index, token);
                node_buffer.push(types.Node{ .rect = rect });
            },
            .rbracket => {
                closed = true;
                index.* += 1;
                break;
            },
            else => {
                index.* += 1;
            },
        }
    }

    if (!closed) {
        declarationError("desktop", nodes_token, "expected closing bracket after nodes declaration", .{});
        return error.InvalidDesktopDeclaration;
    }

    return node_buffer.getArray();
}

fn parseWorkspaceArray(
    tokens: *memory.TokenArray,
    index: *usize,
    workspaces_token: Token,
) ![]types.Workspace {
    if (!consumeTag(tokens.getArray(), index, .lbracket)) {
        declarationError("desktop", workspaces_token, "expected opening bracket after workspaces keyword", .{});
        return error.InvalidDesktopDeclaration;
    }

    var depth: usize = 1;
    while (index.* < tokens.getLength() and depth > 0) {
        const token = tokens.getItem(index.*);
        if (token.tag == .lbracket) {
            depth += 1;
        } else if (token.tag == .rbracket) {
            depth -= 1;
            if (depth == 0) {
                index.* += 1;
                break;
            }
        }
        index.* += 1;
    }

    if (depth != 0) {
        declarationError("desktop", workspaces_token, "expected closing bracket after workspaces declaration", .{});
        return error.InvalidDesktopDeclaration;
    }

    return &[_]types.Workspace{};
}

fn parseRectBody(tokens: *memory.TokenArray, index: *usize, rect_token: Token) !types.Rect {
    if (!consumeTag(tokens.getArray(), index, .lbrace)) {
        declarationError("rect", rect_token, "expected opening brace after rect keyword", .{});
        return error.InvalidRectDeclaration;
    }

    var rect = initRect();
    var size_set = false;
    var position_set = false;
    var closed = false;
    while (index.* < tokens.getLength()) {
        const token = tokens.getItem(index.*);
        switch (token.tag) {
            .rbrace => {
                closed = true;
                index.* += 1;
                break;
            },
            .id => {
                index.* += 1;
                if (rect.id != null) {
                    declarationError("rect", rect_token, "expected only one id after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                if (index.* >= tokens.getLength()) {
                    declarationError("rect", rect_token, "expected id value after id keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                const value_token = tokens.getItem(index.*);
                if (value_token.tag != .identifier and value_token.tag != .string) {
                    declarationError("rect", rect_token, "expected identifier after id keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                rect.id = value_token.literal;
                index.* += 1;
            },
            .size => {
                if (size_set) {
                    declarationError("rect", rect_token, "expected only one size after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                index.* += 1;
                rect.size = try parseVector(tokens.getArray(), index, rect_token, "size");
                size_set = true;
            },
            .position => {
                if (position_set) {
                    declarationError("rect", rect_token, "expected only one position after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                index.* += 1;
                rect.position = try parseVector(tokens.getArray(), index, rect_token, "position");
                position_set = true;
            },
            .background => {
                if (rect.background != null) {
                    declarationError("rect", rect_token, "expected only one background after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                index.* += 1;
                rect.background = try parseColor(tokens.getArray(), index, rect_token);
            },
            else => {
                index.* += 1;
            },
        }
    }

    if (!closed) {
        declarationError("rect", rect_token, "expected closing brace after rect declaration", .{});
        return error.InvalidRectDeclaration;
    }
    if (!size_set) {
        declarationError("rect", rect_token, "expected size after rect keyword", .{});
        return error.InvalidRectDeclaration;
    }
    if (!position_set) {
        declarationError("rect", rect_token, "expected position after rect keyword", .{});
        return error.InvalidRectDeclaration;
    }

    return rect;
}

fn parseVector(tokens: []const Token, index: *usize, rect_token: Token, field: []const u8) !types.Vector {
    if (!consumeTag(tokens, index, .lparen)) {
        declarationError("rect", rect_token, "expected opening parenthesis after {s} keyword", .{field});
        return error.InvalidRectDeclaration;
    }

    var x_buf: [32]u8 = undefined;
    const x_label = std.fmt.bufPrint(&x_buf, "{s} x", .{field}) catch field;
    const x = try consumeNumber(usize, tokens, index, rect_token, x_label);

    if (!consumeTag(tokens, index, .comma)) {
        declarationError("rect", rect_token, "expected comma after {s} x", .{field});
        return error.InvalidRectDeclaration;
    }

    var y_buf: [32]u8 = undefined;
    const y_label = std.fmt.bufPrint(&y_buf, "{s} y", .{field}) catch field;
    const y = try consumeNumber(usize, tokens, index, rect_token, y_label);

    if (!consumeTag(tokens, index, .rparen)) {
        declarationError("rect", rect_token, "expected closing parenthesis after {s} keyword", .{field});
        return error.InvalidRectDeclaration;
    }

    return types.Vector{ .x = x, .y = y };
}

fn parseColor(tokens: []const Token, index: *usize, rect_token: Token) !types.Color {
    if (!consumeTag(tokens, index, .lparen)) {
        declarationError("rect", rect_token, "expected opening parenthesis after background keyword", .{});
        return error.InvalidRectDeclaration;
    }

    const r = try consumeNumber(u8, tokens, index, rect_token, "background r");
    if (!consumeTag(tokens, index, .comma)) {
        declarationError("rect", rect_token, "expected comma after background r", .{});
        return error.InvalidRectDeclaration;
    }

    const g = try consumeNumber(u8, tokens, index, rect_token, "background g");
    if (!consumeTag(tokens, index, .comma)) {
        declarationError("rect", rect_token, "expected comma after background g", .{});
        return error.InvalidRectDeclaration;
    }

    const b = try consumeNumber(u8, tokens, index, rect_token, "background b");
    if (!consumeTag(tokens, index, .comma)) {
        declarationError("rect", rect_token, "expected comma after background b", .{});
        return error.InvalidRectDeclaration;
    }

    const a = try consumeNumber(u8, tokens, index, rect_token, "background a");

    if (!consumeTag(tokens, index, .rparen)) {
        declarationError("rect", rect_token, "expected closing parenthesis after background keyword", .{});
        return error.InvalidRectDeclaration;
    }

    return types.Color{ .r = r, .g = g, .b = b, .a = a };
}

fn parseLayout(tokens: []const Token, index: *usize, layout_token: Token) !?types.Layout {
    if (index.* >= tokens.len) {
        declarationError("desktop", layout_token, "expected layout value", .{});
        return error.InvalidDesktopDeclaration;
    }
    const value_token = tokens[index.*];
    var layout: ?types.Layout = null;
    switch (value_token.tag) {
        .grid => layout = .grid,
        .stack => layout = .stack,
        .float => layout = .float,
        .monocle => layout = .monocle,
        else => {
            declarationError("desktop", layout_token, "expected grid|stack|float|monocle after layout keyword", .{});
            return error.InvalidDesktopDeclaration;
        },
    }
    index.* += 1;
    return layout;
}

fn consumeNumber(comptime T: type, tokens: []const Token, index: *usize, rect_token: Token, field: []const u8) !T {
    if (index.* >= tokens.len or tokens[index.*].tag != .number) {
        declarationError("rect", rect_token, "expected number for {s}", .{field});
        return error.InvalidRectDeclaration;
    }
    const number_token = tokens[index.*];
    const value = std.fmt.parseInt(T, number_token.literal, 10) catch {
        std.debug.print(
            "error: invalid number for {s} at line {d} column {d}\n",
            .{ field, number_token.span.line, number_token.span.column },
        );
        return error.InvalidRectDeclaration;
    };
    index.* += 1;
    return value;
}

fn consumeTag(tokens: []const Token, index: *usize, tag: TokenTag) bool {
    if (index.* >= tokens.len or tokens[index.*].tag != tag) {
        return false;
    }
    index.* += 1;
    return true;
}

fn declarationError(label: []const u8, token: Token, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(
        "error: invalid {s} declaration at line {d} column {d} offset {d}\n",
        .{ label, token.span.line, token.span.column, token.span.offset },
    );
    std.debug.print(fmt ++ "\n", args);
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

fn initRect() types.Rect {
    return types.Rect{
        .id = null,
        .size = types.Vector{ .x = 0, .y = 0 },
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
