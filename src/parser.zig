const std = @import("std");
const memory = @import("./memory.zig");
const types = @import("./types.zig");
const Token = types.Token;
const TokenTag = types.TokenTag;
const Vector = types.Vector;

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

pub fn parse(token_array: *memory.TokenArray, nodes: *memory.NodeArray) !types.Root {
    if (token_array.getLength() == 0 or token_array.getItem(0).tag != .root) {
        return error.InvalidRootDeclaration;
    }
    var tracker = TokenTracker.init(token_array, nodes);
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
    tracker: *TokenTracker,
) !types.Desktop {
    if (!consumeTag(tracker, .lbrace)) {
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

fn parseSystem(tracker: *TokenTracker) !types.System {
    if (!consumeTag(tracker, .lbrace)) {
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

fn parseNodeArray(tracker: *TokenTracker, local_position: Vector) ![]types.Node {
    if (!consumeTag(tracker, .lbracket)) {
        declarationError("desktop", tracker.peek(), "expected opening bracket after nodes keyword", .{});
        return error.InvalidDesktopDeclaration;
    }

    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .rect => {
                tracker.advance();
                const rect = try parseRectBody(tracker, local_position);
                tracker.nodes.push(types.Node{ .rect = rect });
            },
            .rbracket => {
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
        declarationError("desktop", tracker.peek(), "expected closing bracket after nodes declaration", .{});
        return error.InvalidDesktopDeclaration;
    }

    return tracker.nodes.getArray();
}

fn parseWorkspaceArray(
    tokens: *memory.TokenArray,
    tracker: *TokenTracker,
    workspaces_token: Token,
) ![]types.Workspace {
    if (!consumeTag(tracker, .lbracket)) {
        declarationError("desktop", workspaces_token, "expected opening bracket after workspaces keyword", .{});
        return error.InvalidDesktopDeclaration;
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
        declarationError("desktop", workspaces_token, "expected closing bracket after workspaces declaration", .{});
        return error.InvalidDesktopDeclaration;
    }

    return &[_]types.Workspace{};
}

fn parseRectBody(tracker: *TokenTracker, local_position: Vector) error{ InvalidRectDeclaration, InvalidDesktopDeclaration }!types.Rect {
    if (!consumeTag(tracker, .lbrace)) {
        declarationError("rect", tracker.peek(), "expected opening brace after rect keyword", .{});
        return error.InvalidRectDeclaration;
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
                    declarationError("rect", tracker.peek(), "expected only one id after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                if (tracker.peek().tag != .identifier and tracker.peek().tag != .string) {
                    declarationError("rect", tracker.peek(), "expected id value after id keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                if (tracker.peek().tag != .identifier and tracker.peek().tag != .string) {
                    declarationError("rect", tracker.peek(), "expected identifier after id keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                rect.id = tracker.peek().literal;
                tracker.advance();
            },
            .size => {
                if (size_set) {
                    declarationError("rect", tracker.peek(), "expected only one size after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                tracker.advance();
                rect.size = try parseVector(tracker, "size");
                size_set = true;
            },
            .position => {
                if (position_set) {
                    declarationError("rect", tracker.peek(), "expected only one position after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                tracker.advance();
                rect.position = try parseVector(tracker, "position");
                position_set = true;
            },
            .background => {
                if (rect.background != null) {
                    declarationError("rect", tracker.peek(), "expected only one background after rect keyword", .{});
                    return error.InvalidRectDeclaration;
                }
                tracker.advance();
                rect.background = try parseColor(tracker);
            },
            .nodes => {
                tracker.advance();
                const child_local_position = Vector{
                    .x = local_position.x + rect.position.x,
                    .y = local_position.y + rect.position.y,
                };
                const nodes_slice = try parseNodeArray(tracker, child_local_position);
                rect.children = nodes_slice;
            },
            else => {
                tracker.advance();
            },
        }
    }

    if (!closed) {
        declarationError("rect", tracker.peek(), "expected closing brace after rect declaration", .{});
        return error.InvalidRectDeclaration;
    }
    if (!size_set) {
        declarationError("rect", tracker.peek(), "expected size after rect keyword", .{});
        return error.InvalidRectDeclaration;
    }
    if (!position_set) {
        declarationError("rect", tracker.peek(), "expected position after rect keyword", .{});
        return error.InvalidRectDeclaration;
    }

    return rect;
}

fn parseVector(tracker: *TokenTracker, field: []const u8) !types.Vector {
    if (!consumeTag(tracker, .lparen)) {
        declarationError("rect", tracker.peek(), "expected opening parenthesis after {s} keyword", .{field});
        return error.InvalidRectDeclaration;
    }

    var x_buf: [32]u8 = undefined;
    const x_label = std.fmt.bufPrint(&x_buf, "{s} x", .{field}) catch field;
    const x = try consumeNumber(i32, tracker, x_label);

    if (!consumeTag(tracker, .comma)) {
        declarationError("rect", tracker.peek(), "expected comma after {s} x", .{field});
        return error.InvalidRectDeclaration;
    }

    var y_buf: [32]u8 = undefined;
    const y_label = std.fmt.bufPrint(&y_buf, "{s} y", .{field}) catch field;
    const y = try consumeNumber(i32, tracker, y_label);

    if (!consumeTag(tracker, .rparen)) {
        declarationError("rect", tracker.peek(), "expected closing parenthesis after {s} keyword", .{field});
        return error.InvalidRectDeclaration;
    }

    return types.Vector{ .x = x, .y = y };
}

fn parseColor(tracker: *TokenTracker) !types.Color {
    if (!consumeTag(tracker, .lparen)) {
        declarationError("rect", tracker.peek(), "expected opening parenthesis after background keyword", .{});
        return error.InvalidRectDeclaration;
    }

    const r = try consumeNumber(u8, tracker, "background r");
    if (!consumeTag(tracker, .comma)) {
        declarationError("rect", tracker.peek(), "expected comma after background r", .{});
        return error.InvalidRectDeclaration;
    }

    const g = try consumeNumber(u8, tracker, "background g");
    if (!consumeTag(tracker, .comma)) {
        declarationError("rect", tracker.peek(), "expected comma after background g", .{});
        return error.InvalidRectDeclaration;
    }

    const b = try consumeNumber(u8, tracker, "background b");
    if (!consumeTag(tracker, .comma)) {
        declarationError("rect", tracker.peek(), "expected comma after background b", .{});
        return error.InvalidRectDeclaration;
    }

    const a = try consumeNumber(u8, tracker, "background a");

    if (!consumeTag(tracker, .rparen)) {
        declarationError("rect", tracker.peek(), "expected closing parenthesis after background keyword", .{});
        return error.InvalidRectDeclaration;
    }

    return types.Color{ .r = r, .g = g, .b = b, .a = a };
}

fn parseLayout(tracker: *TokenTracker) !?types.Layout {
    if (tracker.peek().tag != .identifier) {
        declarationError("desktop", tracker.peek(), "expected layout value", .{});
        return error.InvalidDesktopDeclaration;
    }
    const value_token = tracker.peek();
    var layout: ?types.Layout = null;
    switch (value_token.tag) {
        .grid => layout = .grid,
        .stack => layout = .stack,
        .float => layout = .float,
        .monocle => layout = .monocle,
        else => {
            declarationError("desktop", tracker.peek(), "expected grid|stack|float|monocle after layout keyword", .{});
            return error.InvalidDesktopDeclaration;
        },
    }
    tracker.advance();
    return layout;
}

fn consumeNumber(comptime T: type, tracker: *TokenTracker, field: []const u8) !T {
    if (tracker.peek().tag != .number) {
        declarationError("rect", tracker.peek(), "expected number for {s}", .{field});
        return error.InvalidRectDeclaration;
    }
    const number_token = tracker.peek();
    const value = std.fmt.parseInt(T, number_token.literal, 10) catch {
        std.debug.print(
            "error: invalid number for {s} at line {d} column {d}\n",
            .{ field, number_token.span.line, number_token.span.column },
        );
        return error.InvalidRectDeclaration;
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
