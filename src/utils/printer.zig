const std = @import("std");
const helpers = @import("./helpers.zig");
const types = @import("../core/types.zig");
const iVector = types.iVector;
const uVector = types.uVector;
const memory = @import("../core/memory.zig");

pub fn printAST(root: *types.Root) void {
    printIndent(0);
    std.debug.print("Root\n", .{});
    printDesktop(root.desktop, 1);
    printSystem(root.system, 1);
}

fn printDesktop(desktop: types.Desktop, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("Desktop\n", .{});
    printVector("size", desktop.size, indent_level + 1);

    if (desktop.active_workspace != null) {
        printIndent(indent_level + 1);
        std.debug.print("active_workspace:\n", .{});
        printWorkspace(desktop.active_workspace.?, indent_level + 2);
    }
    if (desktop.nodes) |nodes| {
        printNodes("nodes", nodes, indent_level + 1);
    }
    if (desktop.workspaces) |workspaces| {
        printWorkspaceSlice("workspaces", workspaces, indent_level + 1);
    }
}

fn printSystem(system: types.System, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("System\n", .{});
    printAppsSlice("apps", system.apps, indent_level + 1);
}

fn printWorkspaceSlice(label: []const u8, workspaces: []const types.Workspace, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("{s}:\n", .{label});
    if (workspaces.len == 0) {
        printIndent(indent_level + 1);
        std.debug.print("(empty)\n", .{});
        return;
    }
    for (workspaces, 0..) |workspace, index| {
        printIndent(indent_level + 1);
        std.debug.print("Workspace[{d}]\n", .{index});
        printWorkspace(workspace, indent_level + 2);
    }
}

fn printWorkspace(workspace: types.Workspace, indent_level: usize) void {
    printAppsSlice("apps", workspace.apps, indent_level);
}

fn printAppsSlice(label: []const u8, apps: ?[]const types.App, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("{s}:\n", .{label});
    if (apps == null or apps.?.len == 0) {
        printIndent(indent_level + 1);
        std.debug.print("(empty)\n", .{});
        return;
    }
    for (apps.?, 0..) |app, index| {
        printIndent(indent_level + 1);
        std.debug.print("App[{d}] \"{s}\"\n", .{ index, app.id });
        printApp(app, indent_level + 2);
    }
}

fn printApp(app: types.App, indent_level: usize) void {
    printVector("size", app.size, indent_level);
    printVector("position", app.position, indent_level);
    printColor("background", app.background, indent_level);
    printNodes("children", app.children, indent_level);
}

fn printRect(rect: types.Rect, indent_level: usize) void {
    if (rect.id) |id| {
        printIndent(indent_level);
        std.debug.print("id: {s}\n", .{id});
    }
    printOptionalVector("size", rect.size, indent_level);
    printOptionalVector("position", rect.position, indent_level);
    printOptionalColor("background", rect.background, indent_level);
    if (rect.children) |children| {
        printNodes("children", children, indent_level);
    }
}

fn printText(text: types.Text, indent_level: usize) void {
    if (text.id) |id| {
        printIndent(indent_level);
        std.debug.print("id: {s}\n", .{id});
    }
    printIndent(indent_level);
    std.debug.print("body: \"{s}\"\n", .{text.body});
    printColor("color", text.color, indent_level);
    if (text.position) |position| {
        printVector("position", position, indent_level);
    }
    if (text.text_size) |text_size| {
        printIndent(indent_level);
        std.debug.print("text size: {d}\n", .{text_size});
    }
}

fn printTransform(transform: types.Transform, indent_level: usize) void {
    if (transform.id) |id| {
        printIndent(indent_level);
        std.debug.print("id: {s}\n", .{id});
    }
    printOptionalVector("position", transform.position, indent_level);
    if (transform.children) |children| {
        printNodes("children", children, indent_level);
    }
}

fn printNodes(label: []const u8, nodes: []const types.Node, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("{s}:\n", .{label});
    if (nodes.len == 0) {
        printIndent(indent_level + 1);
        std.debug.print("(empty)\n", .{});
        return;
    }
    for (nodes, 0..) |node, index| {
        printIndent(indent_level + 1);
        std.debug.print("Node[{d}] {s}\n", .{ index, @tagName(node) });
        switch (node) {
            .rect => |rect| {
                printRect(rect, indent_level + 2);
            },
            .text => |text| {
                printText(text, indent_level + 2);
            },
            .transform => |transform| {
                printTransform(transform, indent_level + 2);
            },
        }
    }
}

fn printVector(label: []const u8, vector: types.Vector, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("{s}: ({d}, {d})\n", .{ label, vector.x, vector.y });
}

fn printOptionalVector(label: []const u8, maybe_vector: ?types.Vector, indent_level: usize) void {
    if (maybe_vector) |vector| {
        printVector(label, vector, indent_level);
    }
}

fn printColor(label: []const u8, color: types.Color, indent_level: usize) void {
    printIndent(indent_level);
    std.debug.print("{s}: rgba({d}, {d}, {d}, {d})\n", .{ label, color.r, color.g, color.b, color.a });
}

fn printOptionalColor(label: []const u8, maybe_color: ?types.Color, indent_level: usize) void {
    if (maybe_color) |color| {
        printColor(label, color, indent_level);
    }
}

fn printIndent(indent_level: usize) void {
    for (0..indent_level) |_| {
        std.debug.print("  ", .{});
    }
}
