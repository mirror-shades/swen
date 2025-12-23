const std = @import("std");
const types = @import("../core/types.zig");
const Color = types.Color;
const Vector = types.Vector;
const Rect = types.Rect;
const Instruction = types.Instruction;
const Bounds = types.Bounds;
const TextRef = types.TextRef;
const memory = @import("../core/memory.zig");
const reporter = @import("../utils/reporter.zig");
const Error = reporter.Error;

const sdl = @import("sdl");
const c = sdl.c;

pub const Compositor = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    running: bool = true,

    pub fn init(size: Vector, desktop_background: ?Color) !Compositor {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            return reporter.throwRuntimeError("SDL initialization failed", Error.SDLInitFailed);
        }

        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(
            "swen compositor",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            size.x,
            size.y,
            c.SDL_WINDOW_SHOWN,
        ) orelse {
            return reporter.throwRuntimeError("failed to create SDL window", Error.WindowCreateFailed);
        };
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
            return reporter.throwRuntimeError("failed to create SDL renderer", Error.RendererCreateFailed);
        };
        errdefer c.SDL_DestroyRenderer(renderer);

        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

        if (desktop_background) |bg| {
            _ = c.SDL_SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a);
        } else {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        }

        return .{
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *Compositor) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn renderScene(self: *Compositor, rects: []const Rect) !void {
        _ = c.SDL_RenderClear(self.renderer);

        for (rects) |rect| {
            try self.renderRect(rect);
        }

        c.SDL_RenderPresent(self.renderer);
    }

    pub fn drawLine(self: *Compositor, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        _ = c.SDL_RenderDrawLine(self.renderer, x1, y1, x2, y2);
    }

    pub fn drawPoint(self: *Compositor, x: i32, y: i32, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        _ = c.SDL_RenderDrawPoint(self.renderer, x, y);
    }

    pub fn drawRectOutline(self: *Compositor, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        const sdl_rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
        _ = c.SDL_RenderDrawRect(self.renderer, &sdl_rect);
    }

    pub fn drawRectFilled(self: *Compositor, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        const sdl_rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
        _ = c.SDL_RenderFillRect(self.renderer, &sdl_rect);
    }

    const Glyph = struct {
        data: [7]u8,
    };

    fn glyphForChar(ch: u8) ?Glyph {
        return switch (ch) {
            ' ' => Glyph{ .data = .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 } },
            'h' => Glyph{ .data = .{ 0b10000, 0b10000, 0b11110, 0b10010, 0b10010, 0b10010, 0b00000 } },
            'e' => Glyph{ .data = .{ 0b01110, 0b10000, 0b11110, 0b10000, 0b10000, 0b01110, 0b00000 } },
            'l' => Glyph{ .data = .{ 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b00100, 0b00000 } },
            'o' => Glyph{ .data = .{ 0b01100, 0b10010, 0b10010, 0b10010, 0b10010, 0b01100, 0b00000 } },
            'w' => Glyph{ .data = .{ 0b10001, 0b10001, 0b10101, 0b10101, 0b01010, 0b01010, 0b00000 } },
            'r' => Glyph{ .data = .{ 0b10110, 0b11001, 0b10000, 0b10000, 0b10000, 0b10000, 0b00000 } },
            'd' => Glyph{ .data = .{ 0b00010, 0b00010, 0b01110, 0b10010, 0b10010, 0b01110, 0b00000 } },
            else => null,
        };
    }

    fn drawGlyph(self: *Compositor, x: i32, y: i32, color: Color, glyph: Glyph, scale: i32) void {
        var row: usize = 0;
        while (row < glyph.data.len) : (row += 1) {
            const bits: u8 = glyph.data[row];
            var col: usize = 0;
            while (col < 5) : (col += 1) {
                const shift: u3 = @intCast(4 - col);
                const mask: u8 = @as(u8, 1) << shift;
                if ((bits & mask) != 0) {
                    const px = x + @as(i32, @intCast(col)) * scale;
                    const py = y + @as(i32, @intCast(row)) * scale;
                    self.drawRectFilled(px, py, scale, scale, color);
                }
            }
        }
    }

    fn drawText(self: *Compositor, x: i32, y: i32, color: Color, text: []const u8, text_size: u16) void {
        const base_scale: i32 = 1;
        const scale: i32 = blk: {
            if (text_size <= 8) break :blk base_scale;
            break :blk @as(i32, @intCast(text_size / 8));
        };

        var cursor_x = x;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const ch = text[i];
            if (glyphForChar(ch)) |glyph| {
                self.drawGlyph(cursor_x, y, color, glyph, scale);
                cursor_x += (5 * scale) + scale;
            } else {
                cursor_x += (5 * scale) + scale;
            }
        }
    }

    fn renderRect(self: *Compositor, rect: Rect) !void {
        if (rect.position == null) return;

        const world_x = rect.position.?.x + rect.local_position.x;
        const world_y = rect.position.?.y + rect.local_position.y;

        const sdl_rect = c.SDL_Rect{
            .x = world_x,
            .y = world_y,
            .w = rect.size.x,
            .h = rect.size.y,
        };

        if (rect.background) |background| {
            _ = c.SDL_SetRenderDrawColor(self.renderer, background.r, background.g, background.b, background.a);
            _ = c.SDL_RenderFillRect(self.renderer, &sdl_rect);
        }

        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderDrawRect(self.renderer, &sdl_rect);

        if (rect.children) |children| {
            for (children) |child| {
                switch (child) {
                    .rect => |child_rect| {
                        var modified_rect = child_rect;
                        modified_rect.local_position.x += world_x;
                        modified_rect.local_position.y += world_y;
                        try self.renderRect(modified_rect);
                    },
                    .text => |text_node| {
                        if (text_node.position) |pos| {
                            if (text_node.text_size) |size| {
                                const text_x = pos.x + text_node.local_position.x;
                                const text_y = pos.y + text_node.local_position.y;
                                self.drawText(text_x, text_y, text_node.color, text_node.body, size);
                            }
                        }
                    },
                    .transform => |transform_node| {
                        // TODO: Implement transform handling
                        _ = transform_node;
                    },
                }
            }
        }
    }

    pub fn pumpEvents(self: *Compositor) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) {
                self.running = false;
            }
        }
    }

    pub fn renderFrame(self: *Compositor, rects: []const Rect) void {
        self.renderScene(rects) catch |err| {
            std.debug.print("Render error: {}\n", .{err});
        };
    }

    pub fn renderIRFrame(self: *Compositor, ir: []const Instruction) void {
        // Ensure full clear with explicit background color
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(self.renderer);

        for (ir) |inst| {
            switch (inst) {
                .draw_rect => |dr| {
                    self.drawRectFilled(dr.bounds.x, dr.bounds.y, dr.bounds.width, dr.bounds.height, dr.color);
                },
                .draw_text => |dt| {
                    const text_slice = switch (dt.text) {
                        .inline_text => |inline_text| inline_text.data[0..inline_text.len],
                        .interned => |_| @as([]const u8, &[_]u8{}),
                    };
                    self.drawText(dt.bounds.x, dt.bounds.y, dt.color, text_slice, dt.text_size);
                },
                else => {},
            }
        }

        c.SDL_RenderPresent(self.renderer);
    }
};

pub fn lowerSceneToIR(
    root: types.Root,
    ir_buffer: *memory.FixedArray(Instruction, 4096),
) void {
    ir_buffer.length = 0;
    if (root.desktop.nodes) |nodes| {
        // Track which node_ids are referenced as children so we only
        // start lowering from true roots.
        var is_child: [4096]bool = [_]bool{false} ** 4096;

        for (nodes) |node| {
            switch (node) {
                .rect => |rect| {
                    if (rect.children) |children| {
                        for (children) |child| {
                            const child_id: types.NodeId = switch (child) {
                                .rect => |r| r.node_id,
                                .text => |t| t.node_id,
                                .transform => |tr| tr.node_id,
                            };
                            if (child_id > 0 and child_id <= is_child.len) {
                                is_child[child_id - 1] = true;
                            }
                        }
                    }
                },
                .transform => |transform| {
                    if (transform.children) |children| {
                        for (children) |child| {
                            const child_id: types.NodeId = switch (child) {
                                .rect => |r| r.node_id,
                                .text => |t| t.node_id,
                                .transform => |tr| tr.node_id,
                            };
                            if (child_id > 0 and child_id <= is_child.len) {
                                is_child[child_id - 1] = true;
                            }
                        }
                    }
                },
                else => {},
            }
        }

        for (nodes) |node| {
            const id: types.NodeId = switch (node) {
                .rect => |r| r.node_id,
                .text => |t| t.node_id,
                .transform => |tr| tr.node_id,
            };

            if (id > 0 and id <= is_child.len and is_child[id - 1]) {
                continue;
            }

            lowerNodeToIR(node, ir_buffer);
        }
    }
}

fn lowerNodeToIR(
    node: types.Node,
    ir_buffer: *memory.FixedArray(Instruction, 4096),
) void {
    switch (node) {
        .rect => |rect| {
            lowerRectToIR(rect, ir_buffer);
        },
        .text => |text| {
            lowerTextToIR(text, ir_buffer);
        },
        .transform => |transform| {
            if (transform.children) |children| {
                for (children) |child| {
                    lowerNodeToIR(child, ir_buffer);
                }
            }
        },
    }
}

fn lowerRectToIR(
    rect: types.Rect,
    ir_buffer: *memory.FixedArray(Instruction, 4096),
) void {
    const base_pos = rect.position orelse Vector{ .x = 0, .y = 0 };
    const world_x = base_pos.x + rect.local_position.x;
    const world_y = base_pos.y + rect.local_position.y;

    const bounds = Bounds{
        .x = world_x,
        .y = world_y,
        .width = rect.size.x,
        .height = rect.size.y,
    };

    const color = rect.background orelse Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    ir_buffer.push(Instruction{
        .draw_rect = .{
            .node_id = rect.node_id,
            .bounds = bounds,
            .color = color,
            .corner_radius = 0,
        },
    });

    if (rect.children) |children| {
        for (children) |child| {
            lowerNodeToIR(child, ir_buffer);
        }
    }
}

fn lowerTextToIR(
    text: types.Text,
    ir_buffer: *memory.FixedArray(Instruction, 4096),
) void {
    const pos = text.position orelse Vector{ .x = 0, .y = 0 };
    const world_x = pos.x + text.local_position.x;
    const world_y = pos.y + text.local_position.y;

    const size = text.text_size orelse 12;
    const scale: i32 = if (size <= 8) 1 else @as(i32, @intCast(size / 8));
    const width = @as(i32, @intCast(text.body.len)) * (5 * scale + scale);
    const height = 7 * scale;

    const bounds = Bounds{
        .x = world_x,
        .y = world_y,
        .width = width,
        .height = height,
    };

    var text_ref = TextRef{ .inline_text = .{ .data = undefined, .len = 0 } };
    const max_copy = @min(text.body.len, text_ref.inline_text.data.len);
    std.mem.copyForwards(u8, text_ref.inline_text.data[0..max_copy], text.body[0..max_copy]);
    text_ref.inline_text.len = @as(u8, @intCast(max_copy));

    ir_buffer.push(Instruction{
        .draw_text = .{
            .node_id = text.node_id,
            .bounds = bounds,
            .text = text_ref,
            .color = text.color,
            .text_size = size,
        },
    });
}

pub fn collectRectsFromRoot(
    root: types.Root,
    rect_buffer: *memory.FixedArray(Rect, 4096),
) !void {
    const size = root.desktop.size;
    if (size.x <= 0 or size.y <= 0) {
        return reporter.throwRuntimeError("desktop must have a positive size", Error.InvalidSurfaceSize);
    }

    rect_buffer.length = 0;
    collectDesktopRects(root.desktop, rect_buffer);
}

fn collectDesktopRects(
    desktop: types.Desktop,
    rect_buffer: *memory.FixedArray(Rect, 4096),
) void {
    if (desktop.nodes) |nodes| {
        for (nodes) |node| {
            switch (node) {
                .rect => |rect| {
                    pushRectWithChildren(rect, rect_buffer);
                },
                else => {},
            }
        }
    }
}

fn pushRectWithChildren(
    rect: types.Rect,
    rect_buffer: *memory.FixedArray(Rect, 4096),
) void {
    rect_buffer.push(rect);

    if (rect.children) |children| {
        for (children) |child_node| {
            switch (child_node) {
                .rect => |child_rect| {
                    pushRectWithChildren(child_rect, rect_buffer);
                },
                else => {},
            }
        }
    }
}
