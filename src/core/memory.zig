const std = @import("std");
const types = @import("./types.zig");

pub const TokenArray = FixedArray(types.Token, 4096);
pub const NodeArray = FixedArray(types.Node, 4096);
pub const RectArray = FixedArray(types.Rect, 4096);
pub const IRArray = FixedArray(types.Instruction, 4096);

pub fn FixedArray(comptime T: type, comptime N: usize) type {
    return struct {
        data: [N]T,
        length: usize,

        pub fn init() @This() {
            return .{
                .data = undefined,
                .length = 0,
            };
        }

        pub fn push(self: *@This(), value: T) void {
            if (self.length >= self.data.len) {
                std.debug.print("error: array is full (len={d})\n", .{self.length});
                return;
            }
            self.data[self.length] = value;
            self.length += 1;
        }

        pub fn pop(self: *@This()) ?T {
            if (self.length == 0) {
                std.debug.print("error: array is empty\n", .{});
                return null;
            }
            self.length -= 1;
            return self.data[self.length];
        }

        pub fn getItem(self: *@This(), index: usize) T {
            if (index >= self.length) {
                std.debug.panic(
                    "array index out of bounds: len={d}, index={d}\n",
                    .{ self.length, index },
                );
            }
            return self.data[index];
        }

        pub fn getArray(self: *@This()) []T {
            return self.data[0..self.length];
        }

        pub fn getLength(self: *const @This()) usize {
            return self.length;
        }
    };
}
