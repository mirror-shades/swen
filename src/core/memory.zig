const std = @import("std");
const types = @import("./types.zig");
const Token = types.Token;
const Node = types.Node;
const Rect = types.Rect;

pub const TokenArray = struct {
    data: [4096]Token,
    length: usize,

    pub fn init() TokenArray {
        return TokenArray{
            .data = undefined,
            .length = 0,
        };
    }

    pub fn push(self: *TokenArray, data: Token) void {
        if (self.length >= self.data.len) {
            std.debug.print("error: token array is full (len={d})\n", .{self.length});
        } else {
            self.data[self.length] = data;
            self.length += 1;
        }
    }

    pub fn pop(self: *TokenArray) ?Token {
        if (self.length == 0) {
            std.debug.print("error: token array is empty (len=0)\n", .{});
            return null;
        }
        self.length -= 1;
        return self.data[self.length];
    }

    pub fn getItem(self: *TokenArray, index: usize) Token {
        if (index >= self.length) {
            std.debug.panic(
                "token array index out of bounds: len={d}, index={d}\n",
                .{ self.length, index },
            );
        }
        return self.data[index];
    }

    pub fn getLength(self: *TokenArray) usize {
        return self.length;
    }

    pub fn getArray(self: *TokenArray) []Token {
        return self.data[0..self.length];
    }
};

pub const RectArray = struct {
    data: [4096]Rect,
    length: usize,

    pub fn init() RectArray {
        return RectArray{
            .data = undefined,
            .length = 0,
        };
    }

    pub fn push(self: *RectArray, data: Rect) void {
        if (self.length >= self.data.len) {
            std.debug.print("error: rect array is full (len={d})\n", .{self.length});
        } else {
            self.data[self.length] = data;
            self.length += 1;
        }
    }

    pub fn pop(self: *RectArray) ?Rect {
        if (self.length == 0) {
            std.debug.print("error: rect array is empty (len=0)\n", .{});
            return null;
        }
        self.length -= 1;
        return self.data[self.length];
    }

    pub fn getItem(self: *RectArray, index: usize) Rect {
        if (index >= self.length) {
            std.debug.panic(
                "rect array index out of bounds: len={d}, index={d}\n",
                .{ self.length, index },
            );
        }
        return self.data[index];
    }

    pub fn getLength(self: *RectArray) usize {
        return self.length;
    }

    pub fn getArray(self: *RectArray) []Rect {
        return self.data[0..self.length];
    }
};

pub const NodeArray = struct {
    data: [4096]Node,
    length: usize,

    pub fn init() NodeArray {
        return NodeArray{
            .data = undefined,
            .length = 0,
        };
    }

    pub fn push(self: *NodeArray, data: Node) void {
        if (self.length >= self.data.len) {
            std.debug.print("error: node array is full (len={d})\n", .{self.length});
        } else {
            self.data[self.length] = data;
            self.length += 1;
        }
    }

    pub fn pop(self: *NodeArray) ?Node {
        if (self.length == 0) {
            std.debug.print("error: node array is empty (len=0)\n", .{});
            return null;
        }
        self.length -= 1;
        return self.data[self.length];
    }

    pub fn getItem(self: *NodeArray, index: usize) Node {
        if (index >= self.length) {
            std.debug.panic(
                "node array index out of bounds: len={d}, index={d}\n",
                .{ self.length, index },
            );
        }
        return self.data[index];
    }

    pub fn getLength(self: *NodeArray) usize {
        return self.length;
    }

    pub fn getArray(self: *NodeArray) []Node {
        return self.data[0..self.length];
    }
};
