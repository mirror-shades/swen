const std = @import("std");

const helpers = @import("./helpers.zig");

pub const Vector = struct { x: usize, y: usize };
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
    background: ?Color,
    children: ?[]Node,
};

pub const Text = struct {
    id: []const u8,
    body: []const u8,
    color: Color,
    position: Vector,
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
    // keywords
    root,
    desktop,
    system,
    workspaces,
    layout,
    app,
    size,
    position,
    background,
    child,
    rect,
    nodes,
    surface_rect,
    id,
    text,
    body,
    color,
    parent,
    end,
    grid,
    stack,
    float,
    monocle,

    // other token types
    identifier,
    string,
    number,
    boolean,
    nothing,
    array,
    object,
    function,
    method,
    property,
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
    eof,
};

fn get_tag(word: []const u8) !TokenTag {
    if (word[0] == 'r') {
        if (std.mem.eql(u8, word, "root")) {
            return .root;
        } else if (std.mem.eql(u8, word, "rect")) {
            return .rect;
        }
    }
    if (word[0] == 'n') {
        if (std.mem.eql(u8, word, "nodes")) {
            return .nodes;
        }
    }
    if (word[0] == 'd') {
        if (std.mem.eql(u8, word, "desktop")) {
            return .desktop;
        }
    }
    if (word[0] == 's') {
        if (std.mem.eql(u8, word, "system")) {
            return .system;
        } else if (std.mem.eql(u8, word, "stack")) {
            return .stack;
        } else if (std.mem.eql(u8, word, "size")) {
            return .size;
        } else if (std.mem.eql(u8, word, "surface_rect")) {
            return .surface_rect;
        }
    }
    if (word[0] == 'w') {
        if (std.mem.eql(u8, word, "workspaces")) {
            return .workspaces;
        }
    }
    if (word[0] == 'l') {
        if (std.mem.eql(u8, word, "layout")) {
            return .layout;
        }
    }
    if (word[0] == 'a') {
        if (std.mem.eql(u8, word, "app")) {
            return .app;
        }
    }
    if (word[0] == 'e') {
        if (std.mem.eql(u8, word, "end")) {
            return .end;
        }
    }
    if (word[0] == 'b') {
        if (std.mem.eql(u8, word, "background")) {
            return .background;
        } else if (std.mem.eql(u8, word, "body")) {
            return .body;
        }
    }
    if (word[0] == 'c') {
        if (std.mem.eql(u8, word, "child")) {
            return .child;
        } else if (std.mem.eql(u8, word, "color")) {
            return .color;
        }
    }
    if (word[0] == 'i') {
        if (std.mem.eql(u8, word, "id")) {
            return .id;
        }
    }
    if (word[0] == 't') {
        if (std.mem.eql(u8, word, "text")) {
            return .text;
        }
    }
    if (word[0] == 'p') {
        if (std.mem.eql(u8, word, "position")) {
            return .position;
        } else if (std.mem.eql(u8, word, "parent")) {
            return .parent;
        }
    }
    if (word[0] == 'g') {
        if (std.mem.eql(u8, word, "grid")) {
            return .grid;
        }
    }
    if (word[0] == 'f') {
        if (std.mem.eql(u8, word, "float")) {
            return .float;
        }
    }
    if (word[0] == 'm') {
        if (std.mem.eql(u8, word, "monocle")) {
            return .monocle;
        }
    }
    if (word[0] == '[') {
        return .lbracket;
    }
    if (word[0] == ']') {
        return .rbracket;
    }
    if (word[0] == '{') {
        return .lbrace;
    }
    if (word[0] == '}') {
        return .rbrace;
    }
    if (word[0] == '(') {
        return .lparen;
    }
    if (word[0] == ')') {
        return .rparen;
    }
    if (word[0] == ',') {
        return .comma;
    }
    if (word[0] == ':') {
        return .colon;
    }
    if (word[0] == ';') {
        return .semicolon;
    }
    if (word[0] == '.') {
        return .dot;
    }
    return .identifier;
}

pub fn makeToken(literal: []const u8, line: usize, column: usize, offset: usize) Token {
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
