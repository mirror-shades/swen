const std = @import("std");

const helpers = @import("./helpers.zig");

pub const Vector = struct { x: i32, y: i32 };
pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };

pub const Root = struct {
    desktop: Desktop,
    system: System,
};

pub const Desktop = struct {
    surface_rect: Rect,
    active_workspace: ?Workspace,
    layout: ?Layout,
    nodes: ?[]Node,
    workspaces: ?[]Workspace,
};

pub const Layout = enum {
    grid,
    stack,
    float,
    monocle,
};

pub const Workspace = struct {
    apps: ?[]App,
};

pub const System = struct {
    apps: ?[]App,
};

pub const App = struct {
    id: []const u8,
    size: Vector,
    position: Vector,
    background: Color,
    children: []Node,
};

pub const NodeTag = enum {
    rect,
    text,
};

pub const Rect = struct {
    id: ?[]const u8,
    size: Vector,
    position: Vector,
    local_position: Vector,
    background: ?Color,
    children: ?[]Node,
};

pub const Text = struct {
    id: ?[]const u8,
    body: []const u8,
    color: Color,
    position: ?Vector,
    local_position: Vector,
    text_size: ?u16,
};

pub const Node = union(NodeTag) {
    rect: Rect,
    text: Text,
};

const Span = struct {
    line: usize,
    column: usize,
    offset: usize,
};

pub const Token = struct {
    literal: []const u8,
    tag: TokenTag,
    span: Span,
};

pub const TokenTag = enum {
    // root nodes
    root,
    desktop,
    system,

    // node types
    rect,
    text,
    container,
    wayland_surface,
    transform,
    clip,

    // properties
    workspaces,
    app,
    nodes,
    id,
    size,
    text_size,
    position,
    background,
    surface_rect,
    body,
    color,

    // literals types
    identifier,
    string,
    number,
    boolean,
    nothing,
    array,
    object,

    // symbols
    rbrace,
    lbrace,
    rbracket,
    lbracket,
    rparen,
    lparen,
    comma,
    colon,
    semicolon,
    dot,

    // special
    eof,
};

fn get_tag(word: []const u8) !TokenTag {
    const first_char = word[0];
    var tag: TokenTag = .identifier;
    switch (first_char) {
        'a' => {
            if (std.mem.eql(u8, word, "app")) {
                tag = .app;
            }
        },
        'b' => {
            if (std.mem.eql(u8, word, "background")) {
                tag = .background;
            } else if (std.mem.eql(u8, word, "body")) {
                tag = .body;
            }
        },
        'c' => {
            if (std.mem.eql(u8, word, "container")) {
                tag = .container;
            } else if (std.mem.eql(u8, word, "clip")) {
                tag = .clip;
            } else if (std.mem.eql(u8, word, "color")) {
                tag = .color;
            }
        },
        'd' => {
            if (std.mem.eql(u8, word, "desktop")) {
                tag = .desktop;
            }
        },
        'i' => {
            if (std.mem.eql(u8, word, "id")) {
                tag = .id;
            }
        },
        'n' => {
            if (std.mem.eql(u8, word, "nodes")) {
                tag = .nodes;
            }
        },
        'p' => {
            if (std.mem.eql(u8, word, "position")) {
                tag = .position;
            }
        },
        'r' => {
            if (std.mem.eql(u8, word, "root")) {
                tag = .root;
            } else if (std.mem.eql(u8, word, "rect")) {
                tag = .rect;
            }
        },
        's' => {
            if (std.mem.eql(u8, word, "system")) {
                tag = .system;
            } else if (std.mem.eql(u8, word, "size")) {
                tag = .size;
            } else if (std.mem.eql(u8, word, "surface_rect")) {
                tag = .surface_rect;
            }
        },
        'w' => {
            if (std.mem.eql(u8, word, "workspaces")) {
                tag = .workspaces;
            } else if (std.mem.eql(u8, word, "wayland_surface")) {
                tag = .wayland_surface;
            }
        },
        't' => {
            if (std.mem.eql(u8, word, "text")) {
                tag = .text;
            } else if (std.mem.eql(u8, word, "transform")) {
                tag = .transform;
            } else if (std.mem.eql(u8, word, "text_size")) {
                tag = .text_size;
            }
        },
        '[' => {
            tag = .lbracket;
        },
        ']' => {
            tag = .rbracket;
        },
        '{' => {
            tag = .lbrace;
        },
        '}' => {
            tag = .rbrace;
        },
        '(' => {
            tag = .lparen;
        },
        ')' => {
            tag = .rparen;
        },
        ',' => {
            tag = .comma;
        },
        ':' => {
            tag = .colon;
        },
        ';' => {
            tag = .semicolon;
        },
        '.' => {
            tag = .dot;
        },
        else => {
            tag = .identifier;
        },
    }
    return tag;
}

pub fn makeToken(literal: []const u8, line: usize, column: usize, offset: usize) Token {
    if (literal[0] == '-') {
        if (helpers.isNumber(literal[1])) {
            return Token{
                .literal = literal,
                .tag = .number,
                .span = Span{
                    .line = line,
                    .column = column,
                    .offset = offset,
                },
            };
        } else {
            return Token{
                .literal = literal,
                .tag = .identifier,
                .span = Span{
                    .line = line,
                    .column = column,
                    .offset = offset,
                },
            };
        }
    }
    if (helpers.isSymbol(literal[0])) {
        return Token{
            .literal = literal,
            .tag = try get_tag(literal),
            .span = Span{
                .line = line,
                .column = column,
                .offset = offset,
            },
        };
    } else if (helpers.isNumber(literal[0])) {
        return Token{
            .literal = literal,
            .tag = .number,
            .span = Span{
                .line = line,
                .column = column,
                .offset = offset,
            },
        };
    } else {
        const tag = try get_tag(literal);
        return Token{
            .literal = literal,
            .tag = tag,
            .span = Span{
                .line = line,
                .column = column,
                .offset = offset,
            },
        };
    }
}
