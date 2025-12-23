const std = @import("std");
const memory = @import("../core/memory.zig");
const types = @import("../core/types.zig");
const render_ir = @import("ir.zig");

var global_ir_buf: render_ir.IRBuffer = render_ir.IRBuffer.init();

pub fn generate(root: *types.Root, ir_array: *memory.IRArray) !void {
    if (root.desktop.active_workspace != null) {
        return error.NoActiveWorkspace;
    }

    try render_ir.lowerDesktop(&global_ir_buf, root.desktop);

    ir_array.length = 0;

    const instructions = global_ir_buf.getInstructions();
    for (instructions) |instr| {
        ir_array.push(convertInstruction(instr));
    }
}

fn convertInstruction(instr: render_ir.IRInstruction) types.Instruction {
    return switch (instr) {
        .draw_rect => |dr| .{
            .draw_rect = .{
                .node_id = dr.node_id,
                .bounds = dr.bounds,
                .color = dr.paint_key.color,
                .corner_radius = dr.corner_radius,
            },
        },
        .draw_text => |dt| .{
            .draw_text = .{
                .node_id = dt.node_id,
                .bounds = dt.bounds,
                .text = dt.text_ref,
                .color = dt.paint_key.color,
                .text_size = dt.text_size,
            },
        },
        .push_state => .push_state,
        .pop_state => .pop_state,
        .set_transform => |st| .{
            .set_transform = .{ .matrix = st.matrix },
        },
        .begin_clip => |bc| .{
            .begin_clip = .{
                .clip_id = bc.clip_id,
                .bounds = bc.bounds,
            },
        },
        .end_clip => .end_clip,
        .begin_cache_group => |bg| .{
            .begin_cache_group = .{
                .group_id = bg.group_id,
                .bounds = bg.bounds,
            },
        },
        .end_cache_group => .end_cache_group,
        // Tile-specific hints and boundaries don't have equivalents in the
        // current backend-agnostic IR; treat them as no-ops for now.
        .tile_hint, .tile_boundary, .nop => .nop,
    };
}
