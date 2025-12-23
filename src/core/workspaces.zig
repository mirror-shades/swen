const std = @import("std");
const types = @import("./types.zig");
const memory = @import("./memory.zig");

pub fn initialize_workspaces(root: *types.Root, workspace_array: *memory.WorkspaceArray) void {
    workspace_array.push(.{ .id = "main" });
    root.desktop.workspaces = workspace_array.getArray();
    root.desktop.active_workspace = workspace_array.getItem(0);
}
