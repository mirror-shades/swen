const std = @import("std");
const memory = @import("../core/memory.zig");
const helpers = @import("../utils/helpers.zig");
const reporter = @import("../utils/reporter.zig");
const Error = reporter.Error;
const types = @import("../core/types.zig");
const Token = types.Token;
const Node = types.Node;
const TokenTag = types.TokenTag;
const Color = types.Color;
const Vector = types.Vector;
const Text = types.Text;
const Rect = types.Rect;

const TokenTracker = struct {
    tokens: *memory.FixedArray(Token, 4096),
    nodes: *memory.FixedArray(Node, 4096),
    index: usize,
    next_node_id: u64,

    pub fn init(tokens: *memory.FixedArray(Token, 4096), nodes: *memory.FixedArray(Node, 4096)) TokenTracker {
        return TokenTracker{
            .tokens = tokens,
            .nodes = nodes,
            .index = 0,
            .next_node_id = 1,
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

pub fn parse(token_array: *memory.FixedArray(Token, 4096), nodes: *memory.FixedArray(Node, 4096)) Error!types.Root {
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
    var has_desktop = false;
    var has_system = false;

    var closed = false;
    while (tracker.peek().tag != .eof) {
        switch (tracker.peek().tag) {
            .desktop => {
                if (has_desktop) {
                    return reporter.throwError("root node can only have one desktop child", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateNode);
                }
                tracker.advance();
                desktop = try parseDesktop(&tracker);
                has_desktop = true;
            },
            .system => {
                if (has_system) {
                    return reporter.throwError("root node can only have one system child", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.DuplicateNode);
                }
                tracker.advance();
                system = try parseSystem(&tracker);
                has_system = true;
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

    if (!has_desktop) {
        return reporter.throwError("root node must have exactly one desktop child", root_token.span.line, root_token.span.column, root_token.span.offset, Error.MissingRequiredNode);
    }

    if (!has_system) {
        return reporter.throwError("root node must have exactly one system child", root_token.span.line, root_token.span.column, root_token.span.offset, Error.MissingRequiredNode);
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
    var has_size = false;
    var has_background = false;
    var has_nodes = false;
    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .size => {
                tracker.advance();
                desktop.size = try parseVector(tracker, "size");
                has_size = true;
            },
            .background => {
                tracker.advance();
                desktop.background = try parseColor(tracker);
                has_background = true;
            },
            .nodes => {
                tracker.advance();
                const all_nodes = try parseNodeArray(tracker, Vector{ .x = 0, .y = 0 });

                var is_child: [4096]bool = [_]bool{false} ** 4096;

                for (all_nodes) |node| {
                    switch (node) {
                        .rect => |rect| {
                            if (rect.children) |children| {
                                for (children) |child| {
                                    const child_id: u64 = switch (child) {
                                        .rect => |r| r.node_id,
                                        .text => |t| t.node_id,
                                        .transform => |tr| tr.node_id,
                                    };
                                    if (child_id > 0 and child_id <= is_child.len) {
                                        is_child[child_id - 1] = true;
                                    }
                                }
                            }
                        },
                        .transform => |transform| {
                            if (transform.children) |children| {
                                for (children) |child| {
                                    const child_id: u64 = switch (child) {
                                        .rect => |r| r.node_id,
                                        .text => |t| t.node_id,
                                        .transform => |tr| tr.node_id,
                                    };
                                    if (child_id > 0 and child_id <= is_child.len) {
                                        is_child[child_id - 1] = true;
                                    }
                                }
                            }
                        },
                        else => {},
                    }
                }

                var root_count: usize = 0;
                for (all_nodes) |node| {
                    const id: u64 = switch (node) {
                        .rect => |r| r.node_id,
                        .text => |t| t.node_id,
                        .transform => |tr| tr.node_id,
                    };
                    if (id == 0) continue;
                    if (id <= is_child.len and is_child[id - 1]) continue;
                    root_count += 1;
                }

                var allocator = std.heap.page_allocator;
                const root_nodes = allocator.alloc(types.Node, root_count) catch {
                    return reporter.throwRuntimeError("failed to allocate desktop node roots", Error.SceneCreateFailed);
                };

                var idx: usize = 0;
                for (all_nodes) |node| {
                    const id: u64 = switch (node) {
                        .rect => |r| r.node_id,
                        .text => |t| t.node_id,
                        .transform => |tr| tr.node_id,
                    };
                    if (id == 0) continue;
                    if (id <= is_child.len and is_child[id - 1]) continue;
                    root_nodes[idx] = node;
                    idx += 1;
                }

                desktop.nodes = root_nodes;
                has_nodes = true;
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

    // Validate required properties
    if (!has_size) {
        return reporter.throwError("desktop node must have a size property", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (!has_background) {
        return reporter.throwError("desktop node must have a background property", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (!has_nodes) {
        return reporter.throwError("desktop node must have a nodes array", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (desktop.size.x <= 0 or desktop.size.y <= 0) {
        return reporter.throwError("desktop must have a positive size", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidSize);
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
            .transform => {
                tracker.advance();
                const transform = try parseTransform(tracker, local_position);
                tracker.nodes.push(types.Node{ .transform = transform });
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
    tracker: *TokenTracker,
    workspaces_token: Token,
) ![]types.Workspace {
    if (!consumeTag(tracker, .lbracket)) {
        return reporter.throwError("expected opening bracket after workspaces keyword", workspaces_token.span.line, workspaces_token.span.column, workspaces_token.span.offset, Error.ExpectedLeftBracket);
    }

    var workspaces = try std.ArrayList(types.Workspace).initCapacity(std.heap.page_allocator, 0);
    defer workspaces.deinit(std.heap.page_allocator);

    var closed = false;
    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .lbrace => {
                tracker.advance();
                const workspace = try parseWorkspaceObject(tracker);
                try workspaces.append(std.heap.page_allocator, workspace);
            },
            .rbracket => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found in workspace array parsing at line {d} column {d} offset {d}: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing bracket after workspaces declaration", workspaces_token.span.line, workspaces_token.span.column, workspaces_token.span.offset, Error.ExpectedRightBracket);
    }

    return try workspaces.toOwnedSlice(std.heap.page_allocator);
}

fn parseWorkspaceObject(tracker: *TokenTracker) !types.Workspace {
    var workspace: types.Workspace = undefined;
    var has_id = false;
    var closed = false;

    while (tracker.peek().tag != .eof) {
        const token = tracker.peek();
        switch (token.tag) {
            .id => {
                tracker.advance();
                if (tracker.peek().tag != .identifier) {
                    return reporter.throwError("expected identifier after id keyword in workspace", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedIdentifier);
                }
                workspace.id = tracker.peek().literal;
                tracker.advance();
                has_id = true;
            },
            .rbrace => {
                closed = true;
                tracker.advance();
                break;
            },
            else => {
                std.debug.print("unexpected token found in workspace object parsing at line {d} column {d} offset {d}: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after workspace object", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    if (!has_id) {
        return reporter.throwError("workspace object must have an id property", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }

    return workspace;
}

fn parseRectBody(tracker: *TokenTracker, local_position: Vector) Error!Rect {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after rect keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var rect = initRect();
    rect.local_position = local_position;
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
                rect.id = tracker.peek().literal;
                tracker.advance();
            },
            .size => {
                tracker.advance();
                rect.size = try parseVector(tracker, "size");
            },
            .position => {
                tracker.advance();
                rect.position = try parseVector(tracker, "position");
            },
            .background => {
                tracker.advance();
                if (tracker.peek().tag == .lparen) {
                    rect.background = try parseColor(tracker);
                } else {
                    std.debug.print("expected background value after background keyword at line {d} column {d} offset {d} in rect body parsing: {t} {s}\n", .{ tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, tracker.peek().tag, tracker.peek().literal });
                    return reporter.throwError("expected background value after background keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedColor);
                }
            },
            .nodes => {
                tracker.advance();

                if (rect.position) |position| {
                    const child_local_position = Vector{
                        .x = local_position.x + position.x,
                        .y = local_position.y + position.y,
                    };

                    // Parse all nested nodes, then filter to direct children by
                    // removing anything that appears as a child of another node
                    // in this subtree. This keeps the scene tree "pure": each
                    // node has exactly one parent.
                    const all_nodes = try parseNodeArray(tracker, child_local_position);

                    var is_child: [4096]bool = [_]bool{false} ** 4096;

                    for (all_nodes) |node| {
                        switch (node) {
                            .rect => |r| {
                                if (r.children) |children| {
                                    for (children) |child| {
                                        const child_id: u64 = switch (child) {
                                            .rect => |cr| cr.node_id,
                                            .text => |ct| ct.node_id,
                                            .transform => |ctf| ctf.node_id,
                                        };
                                        if (child_id > 0 and child_id <= is_child.len) {
                                            is_child[child_id - 1] = true;
                                        }
                                    }
                                }
                            },
                            .transform => |t| {
                                if (t.children) |children| {
                                    for (children) |child| {
                                        const child_id: u64 = switch (child) {
                                            .rect => |cr| cr.node_id,
                                            .text => |ct| ct.node_id,
                                            .transform => |ctf| ctf.node_id,
                                        };
                                        if (child_id > 0 and child_id <= is_child.len) {
                                            is_child[child_id - 1] = true;
                                        }
                                    }
                                }
                            },
                            else => {},
                        }
                    }

                    var root_count: usize = 0;
                    for (all_nodes) |node| {
                        const id: u64 = switch (node) {
                            .rect => |r| r.node_id,
                            .text => |t| t.node_id,
                            .transform => |tr| tr.node_id,
                        };
                        if (id == 0) continue;
                        if (id <= is_child.len and is_child[id - 1]) continue;
                        root_count += 1;
                    }

                    var allocator = std.heap.page_allocator;
                    const root_nodes = allocator.alloc(types.Node, root_count) catch {
                        return reporter.throwRuntimeError("failed to allocate rect children", Error.SceneCreateFailed);
                    };

                    var idx: usize = 0;
                    for (all_nodes) |node| {
                        const id: u64 = switch (node) {
                            .rect => |r| r.node_id,
                            .text => |t| t.node_id,
                            .transform => |tr| tr.node_id,
                        };
                        if (id == 0) continue;
                        if (id <= is_child.len and is_child[id - 1]) continue;
                        root_nodes[idx] = node;
                        idx += 1;
                    }

                    rect.children = root_nodes;
                } else {
                    return reporter.throwError("expected position before nodes in rect", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
                }
            },
            .text => {
                tracker.advance();
                const text = try parseTextBody(tracker, local_position);
                tracker.nodes.push(types.Node{ .text = text });
            },
            .transform => {
                tracker.advance();
                const transform = try parseTransform(tracker, local_position);
                tracker.nodes.push(types.Node{ .transform = transform });
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
    if (rect.size.x <= 0 or rect.size.y <= 0) {
        return reporter.throwError("expected positive size in rect node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidSize);
    }
    if (rect.position == null) {
        return reporter.throwError("expected position in rect node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (rect.background == null) {
        return reporter.throwError("expected background in rect node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }

    rect.node_id = tracker.next_node_id;
    tracker.next_node_id += 1;
    return rect;
}

fn parseTransform(tracker: *TokenTracker, local_position: Vector) !types.Transform {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after transform keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var transform = types.Transform{
        .node_id = 0,
        .id = null,
        .position = null,
        .local_position = local_position,
        .matrix = null,
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
                transform.id = tracker.peek().literal;
                tracker.advance();
            },
            .position => {
                tracker.advance();
                transform.position = try parseVector(tracker, "position");
            },
            .nodes => {
                tracker.advance();
                const transform_position = transform.position orelse {
                    return reporter.throwError("expected position before nodes in transform", token.span.line, token.span.column, token.span.offset, Error.MissingProperty);
                };
                const child_local_position = Vector{
                    .x = local_position.x + transform_position.x,
                    .y = local_position.y + transform_position.y,
                };
                const nodes_slice = try parseNodeArray(tracker, child_local_position);
                transform.children = nodes_slice;
            },
            .matrix => {
                tracker.advance();
                transform.matrix = try parseMatrix(tracker);
            },
            else => {
                std.debug.print("unexpected token found at line {d} column {d} offset {d} in transform parsing: {t} {s}\n", .{ token.span.line, token.span.column, token.span.offset, token.tag, token.literal });
                tracker.advance();
            },
        }
    }

    if (!closed) {
        return reporter.throwError("expected closing brace after transform declaration", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightBrace);
    }

    if (transform.position) |position| {
        if (position.x <= 0 or position.y <= 0) {
            return reporter.throwError("expected positive position in transform node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidPosition);
        }
    } else {
        return reporter.throwError("expected position in transform node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }

    transform.local_position = local_position;
    transform.node_id = tracker.next_node_id;
    tracker.next_node_id += 1;
    return transform;
}

fn parseMatrix(tracker: *TokenTracker) !types.Matrix {
    if (!consumeTag(tracker, .lparen)) {
        return reporter.throwError("expected opening parenthesis after matrix keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftParen);
    }

    var matrix = types.Matrix{ .a = 0, .b = 0, .c = 0, .d = 0, .e = 0, .f = 0 };
    for (0..6) |i| {
        switch (i) {
            0 => matrix.a = try consumeNumber(f32, tracker, "matrix a"),
            1 => matrix.b = try consumeNumber(f32, tracker, "matrix b"),
            2 => matrix.c = try consumeNumber(f32, tracker, "matrix c"),
            3 => matrix.d = try consumeNumber(f32, tracker, "matrix d"),
            4 => matrix.e = try consumeNumber(f32, tracker, "matrix e"),
            5 => matrix.f = try consumeNumber(f32, tracker, "matrix f"),
            else => {
                return reporter.throwError("expected matrix element", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidMatrix);
            },
        }
        if (i < 5 and !consumeTag(tracker, .comma)) {
            return reporter.throwError("expected comma after matrix element", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedComma);
        }
    }

    if (tracker.peek().tag == .comma) {
        tracker.advance();
    }
    if (!consumeTag(tracker, .rparen)) {
        return reporter.throwError("expected closing parenthesis after matrix", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightParen);
    }

    return matrix;
}

fn parseTextBody(tracker: *TokenTracker, local_position: Vector) !types.Text {
    if (!consumeTag(tracker, .lbrace)) {
        return reporter.throwError("expected opening brace after text keyword", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedLeftBrace);
    }

    var text = Text{
        .node_id = 0,
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

    if (text.position) |position| {
        if (position.x <= 0 or position.y <= 0) {
            return reporter.throwError("expected positive position in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidPosition);
        }
    } else {
        return reporter.throwError("expected position in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    if (text.text_size) |text_size| {
        if (text_size <= 0) {
            return reporter.throwError("expected positive text size in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.InvalidTextSize);
        }
    } else {
        return reporter.throwError("expected text size in text node", tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.MissingProperty);
    }
    text.local_position = local_position;
    text.node_id = tracker.next_node_id;
    tracker.next_node_id += 1;
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

    if (tracker.peek().tag == .comma) {
        tracker.advance();
    }

    if (!consumeTag(tracker, .rparen)) {
        const label = std.fmt.bufPrint(&y_buf, "expected closing parenthesis after {s}", .{field}) catch field;
        return reporter.throwError(label, tracker.peek().span.line, tracker.peek().span.column, tracker.peek().span.offset, Error.ExpectedRightParen);
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

    if (tracker.peek().tag == .comma) {
        tracker.advance();
    }

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
    const number_token = tracker.peek();
    const literal = number_token.literal;
    const value = switch (@typeInfo(T)) {
        .float => std.fmt.parseFloat(T, literal) catch {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "invalid number for {s}", .{field}) catch "invalid number";
            return reporter.throwError(msg, number_token.span.line, number_token.span.column, number_token.span.offset, Error.ExpectedNumber);
        },
        .int => switch (number_token.tag) {
            .float => {
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "invalid number for {s}", .{field}) catch "invalid number";
                return reporter.throwError(msg, number_token.span.line, number_token.span.column, number_token.span.offset, Error.ExpectedNumber);
            },
            else => std.fmt.parseInt(T, literal, 10) catch {
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "invalid number for {s}", .{field}) catch "invalid number";
                return reporter.throwError(msg, number_token.span.line, number_token.span.column, number_token.span.offset, Error.ExpectedNumber);
            },
        },
        else => @compileError("consumeNumber only supports integer and float types"),
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
        .size = types.Vector{ .x = 0, .y = 0 },
        .background = null,
        .nodes = null,
        .workspaces = null,
    };
}

fn initRect() Rect {
    return Rect{
        .node_id = 0,
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
