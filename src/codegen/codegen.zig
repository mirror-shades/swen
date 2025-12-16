const std = @import("std");
const memory = @import("../core/memory.zig");
const types = @import("../core/types.zig");

pub fn generate(root: *types.Root, ir_array: *memory.IRArray) !void {
    _ = ir_array;
    if (root.desktop.active_workspace != null) {
        return error.NoActiveWorkspace;
    }
}
