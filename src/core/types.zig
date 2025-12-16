const std = @import("std");

const helpers = @import("../utils/helpers.zig");

pub const Vector = struct { x: i32, y: i32 };
pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };
pub const Matrix = struct { a: f32, b: f32, c: f32, d: f32, e: f32, f: f32 };

pub const Root = struct {
    desktop: Desktop,
    system: System,
};

pub const Desktop = struct {
    size: Vector,
    active_workspace: ?Workspace,
    nodes: ?[]Node,
    workspaces: ?[]Workspace,
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

pub const Rect = struct {
    id: ?[]const u8,
    size: Vector,
    position: ?Vector,
    local_position: Vector,
    background: ?Color,
    children: ?[]Node,
};

pub const Transform = struct {
    id: ?[]const u8,
    position: ?Vector,
    local_position: Vector,
    matrix: ?Matrix,
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

pub const Node = union(enum) {
    rect: Rect,
    text: Text,
    transform: Transform,
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
    body,
    color,

    // literals types
    identifier,
    string,
    int,
    float,
    boolean,
    nothing,
    array,
    object,
    matrix,

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
            if (std.mem.eql(u8, word, "transform")) {
                tag = .transform;
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
        'm' => {
            if (std.mem.eql(u8, word, "matrix")) {
                tag = .matrix;
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
        '"' => {
            tag = .string;
        },
        else => {
            tag = .identifier;
        },
    }
    return tag;
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

pub fn makeNumberToken(line: usize, column: usize, offset: usize, potential_number: []const u8) !Token {
    var is_float = false;
    for (potential_number) |char| {
        if (char == '.') {
            if (is_float) {
                return makeToken(potential_number, line, column, offset);
            }
            is_float = true;
        }
    }
    const new_token = makeToken(potential_number, line, column, offset);
    return new_token;
}

/// Stable identifier for scene nodes. Used for caching, diffing, and patch targeting.
pub const NodeId = u64;

/// Axis-aligned bounding box for dirty-rect tracking and tile scheduling.
pub const Bounds = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn intersects(self: Bounds, other: Bounds) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn union_(self: Bounds, other: Bounds) Bounds {
        const min_x = @min(self.x, other.x);
        const min_y = @min(self.y, other.y);
        const max_x = @max(self.x + self.width, other.x + other.width);
        const max_y = @max(self.y + self.height, other.y + other.height);
        return .{
            .x = min_x,
            .y = min_y,
            .width = max_x - min_x,
            .height = max_y - min_y,
        };
    }
};

/// Text reference that can be either inline (short strings) or a stable index
/// into an interned string table (for longer/repeated strings).
pub const TextRef = union(enum) {
    inline_text: struct {
        data: [64]u8,
        len: u8,
    },
    interned: u32, // index into string table
};

/// Backend-agnostic render instruction.
/// Designed for incremental/tile-based rendering with caching support.
pub const Instruction = union(enum) {
    draw_rect: struct {
        node_id: NodeId, // stable id for caching/diffing
        bounds: Bounds, // world-space AABB for dirty tracking
        color: Color,
        corner_radius: u16 = 0, // future: rounded corners
    },

    draw_text: struct {
        node_id: NodeId,
        bounds: Bounds,
        text: TextRef,
        color: Color,
        text_size: u16,
        // future: font_id, alignment, etc.
    },

    /// Push current transform/clip state onto stack.
    push_state,

    /// Pop and restore previous transform/clip state.
    pop_state,

    /// Set transform matrix (relative to current state).
    set_transform: struct {
        matrix: Matrix,
    },

    /// Begin a clip region. All subsequent draws (until matching end_clip) are clipped.
    begin_clip: struct {
        clip_id: NodeId, // for caching clip masks
        bounds: Bounds,
    },

    /// End the current clip region.
    end_clip,

    /// Hint to renderer: the following N instructions are a cacheable group.
    /// Backend can cache rasterized result keyed by group_id + content hash.
    begin_cache_group: struct {
        group_id: NodeId,
        bounds: Bounds,
    },

    end_cache_group,

    /// No-op / placeholder (useful for conditional compilation or debugging).
    nop,
};
