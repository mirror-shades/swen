const std = @import("std");
const types = @import("../core/types.zig");
const memory = @import("../core/memory.zig");
const reporter = @import("../utils/reporter.zig");

pub const TILE_SIZE: u32 = 16;
pub const MAX_SEGMENTS_PER_TILE: u32 = 256;
pub const MAX_GPU_BUFFER_SIZE: usize = 4 * 1024 * 1024;
pub const MAX_TILES_PER_FRAME: usize = 16384;
pub const MAX_IR_INSTRUCTIONS: usize = 65536;

pub const TileCoord = struct {
    x: u16,
    y: u16,

    pub fn fromPixel(px: i32, py: i32) TileCoord {
        return .{
            .x = @intCast(@max(0, @divFloor(px, @as(i32, TILE_SIZE)))),
            .y = @intCast(@max(0, @divFloor(py, @as(i32, TILE_SIZE)))),
        };
    }

    pub fn toPixelBounds(self: TileCoord) types.Bounds {
        const tile_size_i32: i32 = @intCast(TILE_SIZE);
        return .{
            .x = @as(i32, self.x) * tile_size_i32,
            .y = @as(i32, self.y) * tile_size_i32,
            .width = tile_size_i32,
            .height = tile_size_i32,
        };
    }

    pub fn eql(self: TileCoord, other: TileCoord) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn pack(self: TileCoord) u32 {
        return (@as(u32, self.y) << 16) | @as(u32, self.x);
    }
};

pub const TileId = struct {
    coord: TileCoord,
    layer: u8,

    pub fn pack(self: TileId) u64 {
        return (@as(u64, self.layer) << 32) | @as(u64, self.coord.pack());
    }
};

pub const TileClassification = enum(u8) {
    empty,
    solid,
    edge,
    clipped,
    complex,
};

pub const PaintKey = struct {
    color: types.Color,

    pub fn hash(self: PaintKey) u64 {
        return @as(u64, self.color.r) |
            (@as(u64, self.color.g) << 8) |
            (@as(u64, self.color.b) << 16) |
            (@as(u64, self.color.a) << 24);
    }

    pub fn eql(self: PaintKey, other: PaintKey) bool {
        return self.color.r == other.color.r and
            self.color.g == other.color.g and
            self.color.b == other.color.b and
            self.color.a == other.color.a;
    }
};

pub const ClipKey = struct {
    bounds: types.Bounds,

    pub fn hash(self: ClipKey) u64 {
        const x: u64 = @bitCast(@as(i64, self.bounds.x));
        const y: u64 = @bitCast(@as(i64, self.bounds.y));
        return x ^ (y << 16) ^ (@as(u64, @bitCast(@as(i64, self.bounds.width))) << 32);
    }
};

pub const Segment = struct {
    x0: i16,
    y0: i16,
    x1: i16,
    y1: i16,
    winding: i8,
    _pad: [3]u8 = .{ 0, 0, 0 },
};

pub const TileWork = struct {
    coord: TileCoord,
    classification: TileClassification,
    solid_color: types.Color,
    segment_start: u32,
    segment_count: u16,
    clip_index: u16,
    paint_index: u16,
    z_order: u16,
};

pub const DirtyRegion = struct {
    bounds: types.Bounds,
    source_node: u64,
    frame: u64,
};

pub const IRInstruction = union(enum) {
    draw_rect: struct {
        node_id: u64,
        bounds: types.Bounds,
        paint_key: PaintKey,
        corner_radius: u16 = 0,
    },

    draw_text: struct {
        node_id: u64,
        bounds: types.Bounds,
        text_ref: types.TextRef,
        paint_key: PaintKey,
        text_size: u16,
    },

    push_state,
    pop_state,

    set_transform: struct {
        matrix: types.Matrix,
    },

    begin_clip: struct {
        clip_id: u64,
        bounds: types.Bounds,
        clip_key: ClipKey,
    },

    end_clip,

    begin_cache_group: struct {
        group_id: u64,
        bounds: types.Bounds,
        content_hash: u64,
    },

    end_cache_group,

    tile_hint: struct {
        start_tile: TileCoord,
        end_tile: TileCoord,
    },

    tile_boundary: TileCoord,

    nop,
};

pub const FrameSnapshot = struct {
    frame_number: u64,
    viewport_width: u32,
    viewport_height: u32,

    tiles_x: u16,
    tiles_y: u16,

    instructions: []const IRInstruction,

    tile_work: []const TileWork,

    segments: []const Segment,
    paint_table: []const PaintKey,

    clip_table: []const ClipKey,
    dirty_regions: []const DirtyRegion,

    stats: FrameStats,
};

pub const FrameStats = struct {
    total_tiles: u32 = 0,
    empty_tiles: u32 = 0,
    solid_tiles: u32 = 0,
    edge_tiles: u32 = 0,
    complex_tiles: u32 = 0,
    total_segments: u32 = 0,
    cache_hits: u32 = 0,
    cache_misses: u32 = 0,
};

pub const IRBuffer = struct {
    instructions: [MAX_IR_INSTRUCTIONS]IRInstruction,
    length: usize,
    frame_number: u64,

    state_depth: u32,
    clip_stack: [32]ClipKey,
    clip_depth: u8,

    pub fn init() IRBuffer {
        return .{
            .instructions = undefined,
            .length = 0,
            .frame_number = 0,
            .state_depth = 0,
            .clip_stack = undefined,
            .clip_depth = 0,
        };
    }

    pub fn clear(self: *IRBuffer) void {
        self.length = 0;
        self.state_depth = 0;
        self.clip_depth = 0;
    }

    pub fn nextFrame(self: *IRBuffer) void {
        self.clear();
        self.frame_number += 1;
    }

    pub fn emit(self: *IRBuffer, instruction: IRInstruction) !void {
        if (self.length >= MAX_IR_INSTRUCTIONS) {
            return error.IRBufferOverflow;
        }
        self.instructions[self.length] = instruction;
        self.length += 1;
    }

    pub fn emitRect(
        self: *IRBuffer,
        node_id: u64,
        bounds: types.Bounds,
        color: types.Color,
        corner_radius: u16,
    ) !void {
        try self.emit(.{
            .draw_rect = .{
                .node_id = node_id,
                .bounds = bounds,
                .paint_key = .{ .color = color },
                .corner_radius = corner_radius,
            },
        });
    }

    pub fn emitText(
        self: *IRBuffer,
        node_id: u64,
        bounds: types.Bounds,
        text_ref: types.TextRef,
        color: types.Color,
        text_size: u16,
    ) !void {
        try self.emit(.{
            .draw_text = .{
                .node_id = node_id,
                .bounds = bounds,
                .text_ref = text_ref,
                .paint_key = .{ .color = color },
                .text_size = text_size,
            },
        });
    }

    pub fn pushState(self: *IRBuffer) !void {
        try self.emit(.push_state);
        self.state_depth += 1;
    }

    pub fn popState(self: *IRBuffer) !void {
        if (self.state_depth == 0) {
            return error.StateStackUnderflow;
        }
        try self.emit(.pop_state);
        self.state_depth -= 1;
    }

    pub fn beginClip(self: *IRBuffer, clip_id: u64, bounds: types.Bounds) !void {
        if (self.clip_depth >= 32) {
            return error.ClipStackOverflow;
        }
        const clip_key = ClipKey{ .bounds = bounds };
        self.clip_stack[self.clip_depth] = clip_key;
        self.clip_depth += 1;
        try self.emit(.{
            .begin_clip = .{
                .clip_id = clip_id,
                .bounds = bounds,
                .clip_key = clip_key,
            },
        });
    }

    pub fn endClip(self: *IRBuffer) !void {
        if (self.clip_depth == 0) {
            return error.ClipStackUnderflow;
        }
        self.clip_depth -= 1;
        try self.emit(.end_clip);
    }

    pub fn getInstructions(self: *const IRBuffer) []const IRInstruction {
        return self.instructions[0..self.length];
    }

    pub fn getCurrentClip(self: *const IRBuffer) ?ClipKey {
        if (self.clip_depth == 0) return null;
        return self.clip_stack[self.clip_depth - 1];
    }
};

pub const TileScheduler = struct {
    tile_work: [MAX_TILES_PER_FRAME]TileWork,
    tile_count: usize,

    segments: [MAX_TILES_PER_FRAME * 16]Segment,
    segment_count: usize,

    paint_table: [1024]PaintKey,
    paint_count: usize,

    clip_table: [256]ClipKey,
    clip_count: usize,

    dirty_regions: [256]DirtyRegion,
    dirty_count: usize,

    stats: FrameStats,

    viewport_width: u32,
    viewport_height: u32,
    tiles_x: u16,
    tiles_y: u16,

    pub fn init() TileScheduler {
        return .{
            .tile_work = undefined,
            .tile_count = 0,
            .segments = undefined,
            .segment_count = 0,
            .paint_table = undefined,
            .paint_count = 0,
            .clip_table = undefined,
            .clip_count = 0,
            .dirty_regions = undefined,
            .dirty_count = 0,
            .stats = .{},
            .viewport_width = 0,
            .viewport_height = 0,
            .tiles_x = 0,
            .tiles_y = 0,
        };
    }

    pub fn reset(self: *TileScheduler) void {
        self.tile_count = 0;
        self.segment_count = 0;
        self.paint_count = 0;
        self.clip_count = 0;
        self.dirty_count = 0;
        self.stats = .{};
    }

    pub fn setViewport(self: *TileScheduler, width: u32, height: u32) void {
        self.viewport_width = width;
        self.viewport_height = height;
        self.tiles_x = @intCast((width + TILE_SIZE - 1) / TILE_SIZE);
        self.tiles_y = @intCast((height + TILE_SIZE - 1) / TILE_SIZE);
    }

    pub fn schedule(self: *TileScheduler, ir: *const IRBuffer) !void {
        self.reset();

        try self.binInstructions(ir);

        self.sortTileWork();

        self.mergeTiles();

        self.classifyTiles();
    }

    pub fn buildSnapshot(self: *const TileScheduler, ir_buf: *const IRBuffer) FrameSnapshot {
        return .{
            .frame_number = ir_buf.frame_number,
            .viewport_width = self.viewport_width,
            .viewport_height = self.viewport_height,
            .tiles_x = self.tiles_x,
            .tiles_y = self.tiles_y,
            .instructions = ir_buf.getInstructions(),
            .tile_work = self.tile_work[0..self.tile_count],
            .segments = self.segments[0..self.segment_count],
            .paint_table = self.paint_table[0..self.paint_count],
            .clip_table = self.clip_table[0..self.clip_count],
            .dirty_regions = self.dirty_regions[0..self.dirty_count],
            .stats = self.stats,
        };
    }

    fn binInstructions(self: *TileScheduler, ir: *const IRBuffer) !void {
        for (ir.getInstructions()) |instr| {
            switch (instr) {
                .draw_rect => |rect| {
                    try self.binRect(rect.node_id, rect.bounds, rect.paint_key);
                },
                .draw_text => |text| {
                    try self.binRect(text.node_id, text.bounds, text.paint_key);
                },
                else => {},
            }
        }
    }

    fn binRect(
        self: *TileScheduler,
        node_id: u64,
        bounds: types.Bounds,
        paint_key: PaintKey,
    ) !void {
        const paint_index = try self.getOrAddPaint(paint_key);

        const start = TileCoord.fromPixel(bounds.x, bounds.y);
        const end = TileCoord.fromPixel(
            bounds.x + bounds.width - 1,
            bounds.y + bounds.height - 1,
        );

        var ty = start.y;
        while (ty <= end.y) : (ty += 1) {
            var tx = start.x;
            while (tx <= end.x) : (tx += 1) {
                const coord = TileCoord{ .x = tx, .y = ty };
                const tile_bounds = coord.toPixelBounds();

                const is_solid = bounds.x <= tile_bounds.x and
                    bounds.y <= tile_bounds.y and
                    bounds.x + bounds.width >= tile_bounds.x + tile_bounds.width and
                    bounds.y + bounds.height >= tile_bounds.y + tile_bounds.height;

                try self.addTileWork(.{
                    .coord = coord,
                    .classification = if (is_solid) .solid else .edge,
                    .solid_color = paint_key.color,
                    .segment_start = 0,
                    .segment_count = 0,
                    .clip_index = 0,
                    .paint_index = paint_index,
                    .z_order = @intCast(self.tile_count),
                });

                _ = node_id;
            }
        }
    }

    fn addTileWork(self: *TileScheduler, work: TileWork) !void {
        if (self.tile_count >= MAX_TILES_PER_FRAME) {
            return error.TileBufferOverflow;
        }
        self.tile_work[self.tile_count] = work;
        self.tile_count += 1;
    }

    fn getOrAddPaint(self: *TileScheduler, key: PaintKey) !u16 {
        // Linear search (could use hash table for large paint counts)
        for (self.paint_table[0..self.paint_count], 0..) |existing, i| {
            if (existing.eql(key)) {
                return @intCast(i);
            }
        }
        if (self.paint_count >= 1024) {
            return error.PaintTableOverflow;
        }
        const index = self.paint_count;
        self.paint_table[self.paint_count] = key;
        self.paint_count += 1;
        return @intCast(index);
    }

    fn sortTileWork(self: *TileScheduler) void {
        const tile_slice = self.tile_work[0..self.tile_count];
        std.mem.sort(TileWork, tile_slice, {}, struct {
            fn lessThan(_: void, a: TileWork, b: TileWork) bool {
                const a_key = a.coord.pack();
                const b_key = b.coord.pack();
                if (a_key != b_key) return a_key < b_key;
                return a.z_order < b.z_order;
            }
        }.lessThan);
    }

    fn mergeTiles(self: *TileScheduler) void {
        if (self.tile_count < 2) return;

        var write_idx: usize = 0;
        var read_idx: usize = 1;

        while (read_idx < self.tile_count) : (read_idx += 1) {
            const prev = &self.tile_work[write_idx];
            const curr = self.tile_work[read_idx];

            if (prev.coord.eql(curr.coord) and
                prev.classification == .solid and
                curr.classification == .solid and
                curr.solid_color.a == 255)
            {
                prev.* = curr;
            } else {
                write_idx += 1;
                if (write_idx != read_idx) {
                    self.tile_work[write_idx] = curr;
                }
            }
        }
        self.tile_count = write_idx + 1;
    }

    fn classifyTiles(self: *TileScheduler) void {
        for (self.tile_work[0..self.tile_count]) |*tile| {
            switch (tile.classification) {
                .empty => self.stats.empty_tiles += 1,
                .solid => self.stats.solid_tiles += 1,
                .edge => self.stats.edge_tiles += 1,
                .complex => self.stats.complex_tiles += 1,
                .clipped => {},
            }
        }
        self.stats.total_tiles = @intCast(self.tile_count);
        self.stats.total_segments = @intCast(self.segment_count);
    }

    pub fn markDirty(self: *TileScheduler, bounds: types.Bounds, source_node: u64, frame: u64) void {
        if (self.dirty_count >= 256) return;
        self.dirty_regions[self.dirty_count] = .{
            .bounds = bounds,
            .source_node = source_node,
            .frame = frame,
        };
        self.dirty_count += 1;
    }
};

pub const IRError = reporter.Error || error{
    IRBufferOverflow,
    StateStackUnderflow,
};

pub fn lowerNode(ir_buf: *IRBuffer, node: types.Node, parent_pos: types.Vector) IRError!void {
    switch (node) {
        .rect => |rect| try lowerRect(ir_buf, rect, parent_pos),
        .text => |text| try lowerText(ir_buf, text, parent_pos),
        .transform => |transform| try lowerTransform(ir_buf, transform, parent_pos),
    }
}

fn lowerRect(ir_buf: *IRBuffer, rect: types.Rect, parent_pos: types.Vector) IRError!void {
    const world_x = rect.local_position.x + (rect.position orelse types.Vector{ .x = 0, .y = 0 }).x + parent_pos.x;
    const world_y = rect.local_position.y + (rect.position orelse types.Vector{ .x = 0, .y = 0 }).y + parent_pos.y;

    const bounds = types.Bounds{
        .x = world_x,
        .y = world_y,
        .width = rect.size.x,
        .height = rect.size.y,
    };

    if (rect.background) |bg| {
        const node_id = generateNodeId(rect.id);
        try ir_buf.emitRect(node_id, bounds, bg, 0);
    }

    if (rect.children) |children| {
        const child_pos = types.Vector{ .x = world_x, .y = world_y };
        for (children) |child| {
            try lowerNode(ir_buf, child, child_pos);
        }
    }
}

fn lowerText(ir_buf: *IRBuffer, text: types.Text, parent_pos: types.Vector) IRError!void {
    const pos = text.position orelse types.Vector{ .x = 0, .y = 0 };
    const world_x = text.local_position.x + pos.x + parent_pos.x;
    const world_y = text.local_position.y + pos.y + parent_pos.y;

    const text_size: i32 = @intCast(text.text_size orelse 14);
    const estimated_width: i32 = @intCast(text.body.len * @as(usize, @intCast(text_size)) / 2);

    const bounds = types.Bounds{
        .x = world_x,
        .y = world_y,
        .width = estimated_width,
        .height = text_size,
    };

    const node_id = generateNodeId(text.id);
    const text_ref = makeTextRef(text.body);

    try ir_buf.emitText(node_id, bounds, text_ref, text.color, text.text_size orelse 14);
}

fn lowerTransform(ir_buf: *IRBuffer, transform: types.Transform, parent_pos: types.Vector) IRError!void {
    if (transform.matrix) |matrix| {
        try ir_buf.pushState();
        try ir_buf.emit(.{ .set_transform = .{ .matrix = matrix } });
    }

    if (transform.children) |children| {
        for (children) |child| {
            try lowerNode(ir_buf, child, parent_pos);
        }
    }

    if (transform.matrix != null) {
        try ir_buf.popState();
    }
}

pub fn lowerDesktop(ir_buf: *IRBuffer, desktop: types.Desktop) IRError!void {
    ir_buf.nextFrame();

    if (desktop.nodes) |nodes| {
        const root_pos = types.Vector{ .x = 0, .y = 0 };
        for (nodes) |node| {
            try lowerNode(ir_buf, node, root_pos);
        }
    }
}

fn generateNodeId(id_opt: ?[]const u8) u64 {
    if (id_opt) |id| {
        var hash: u64 = 5381;
        for (id) |c| {
            hash = ((hash << 5) +% hash) +% c;
        }
        return hash;
    }
    return 0;
}

fn makeTextRef(body: []const u8) types.TextRef {
    if (body.len <= 64) {
        var inline_data: [64]u8 = undefined;
        @memcpy(inline_data[0..body.len], body);
        return .{
            .inline_text = .{
                .data = inline_data,
                .len = @intCast(body.len),
            },
        };
    }
    // For longer text, would intern into a string table
    // For now, fallback to inline with truncation
    var inline_data: [64]u8 = undefined;
    @memcpy(inline_data[0..64], body[0..64]);
    return .{
        .inline_text = .{
            .data = inline_data,
            .len = 64,
        },
    };
}

pub const GPUTileWork = extern struct {
    tile_x: u16,
    tile_y: u16,
    classification: u8,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    color: [4]u8,
    segment_start: u32,
    segment_count: u32,
    paint_index: u16,
    clip_index: u16,
};

pub const GPUSegment = extern struct {
    x0: i16,
    y0: i16,
    x1: i16,
    y1: i16,
    winding: i8,
    _pad: [3]u8 = .{ 0, 0, 0 },
};

pub fn tileWorkToGPU(work: TileWork) GPUTileWork {
    return .{
        .tile_x = work.coord.x,
        .tile_y = work.coord.y,
        .classification = @intFromEnum(work.classification),
        .color = .{ work.solid_color.r, work.solid_color.g, work.solid_color.b, work.solid_color.a },
        .segment_start = work.segment_start,
        .segment_count = work.segment_count,
        .paint_index = work.paint_index,
        .clip_index = work.clip_index,
    };
}
