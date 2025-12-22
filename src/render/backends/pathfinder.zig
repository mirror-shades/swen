//! Pathfinder Backend
//!
//! Bootstrap backend that consumes FrameSnapshot and renders via Pathfinder.
//! This is a transitional backend - it translates the tile-oriented IR back
//! to Pathfinder's immediate-mode canvas API.
//!
//! Once the native tile GPU backend is ready, this can be removed.

const std = @import("std");
const ir = @import("../../core/ir.zig");
const types = @import("../../core/types.zig");
const backend = @import("../backend.zig");
const reporter = @import("../../utils/reporter.zig");

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL2/SDL.h");
    @cInclude("pathfinder.h");
});

const default_font_postscript_name = "LiberationSans";

pub const PathfinderBackend = struct {
    window: *c.SDL_Window,
    gl_context: c.SDL_GLContext,
    renderer: c.PFGLRendererRef,
    resources: c.PFResourceLoaderRef,
    build_options: c.PFBuildOptionsRef,
    font_context: c.PFCanvasFontContextRef,

    viewport_width: u32,
    viewport_height: u32,

    // Stats tracking
    last_frame_stats: backend.FrameResult = .{},

    pub fn init(width: u32, height: u32, bg_color: ?types.Color) !PathfinderBackend {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            return error.SDLInitFailed;
        }
        errdefer c.SDL_Quit();

        try setGlAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        try setGlAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
        try setGlAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, @as(i32, @intCast(c.SDL_GL_CONTEXT_PROFILE_CORE)));
        try setGlAttribute(c.SDL_GL_DOUBLEBUFFER, 1);

        const window = c.SDL_CreateWindow(
            "swen compositor",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            @intCast(width),
            @intCast(height),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN,
        ) orelse return error.WindowCreateFailed;
        errdefer c.SDL_DestroyWindow(window);

        const gl_context = c.SDL_GL_CreateContext(window) orelse return error.GLContextCreateFailed;
        errdefer c.SDL_GL_DeleteContext(gl_context);

        if (c.SDL_GL_MakeCurrent(window, gl_context) != 0) {
            return error.GLContextMakeCurrentFailed;
        }

        _ = c.SDL_GL_SetSwapInterval(1);
        c.PFGLLoadWith(glFunctionLoader, null);

        const window_size = c.PFVector2I{ .x = @intCast(width), .y = @intCast(height) };
        const dest_framebuffer = c.PFGLDestFramebufferCreateFullWindow(&window_size) orelse
            return error.GLDestFramebufferCreateFailed;
        var dest_owned = true;
        defer if (dest_owned) c.PFGLDestFramebufferDestroy(dest_framebuffer);

        const gl_device = c.PFGLDeviceCreate(c.PF_GL_VERSION_GL4, 0) orelse
            return error.GLDeviceCreateFailed;
        var device_owned = true;
        defer if (device_owned) c.PFGLDeviceDestroy(gl_device);

        const resources = c.PFEmbeddedResourceLoaderCreate() orelse
            return error.ResourceLoaderCreateFailed;
        errdefer c.PFResourceLoaderDestroy(resources);

        var renderer_mode = c.PFRendererMode{ .level = c.PF_RENDERER_LEVEL_D3D11 };
        var renderer_options = makeRendererOptions(dest_framebuffer, bg_color);

        const pf_renderer = c.PFGLRendererCreate(gl_device, resources, &renderer_mode, &renderer_options) orelse
            return error.RendererCreateFailed;
        dest_owned = false;
        device_owned = false;
        errdefer c.PFGLRendererDestroy(pf_renderer);

        const build_options = c.PFBuildOptionsCreate() orelse
            return error.BuildOptionsCreateFailed;
        errdefer c.PFBuildOptionsDestroy(build_options);

        const font_context = c.PFCanvasFontContextCreateWithSystemSource() orelse
            return error.FontContextUnavailable;
        errdefer c.PFCanvasFontContextRelease(font_context);

        return .{
            .window = window,
            .gl_context = gl_context,
            .renderer = pf_renderer,
            .resources = resources,
            .build_options = build_options,
            .font_context = font_context,
            .viewport_width = width,
            .viewport_height = height,
        };
    }

    /// Submit a FrameSnapshot for rendering
    /// Pathfinder uses the IR instructions (not tiles) since it's an immediate-mode backend
    pub fn submit(self: *PathfinderBackend, snapshot: *const ir.FrameSnapshot) backend.FrameResult {
        const start_time = std.time.nanoTimestamp();

        // Create canvas for this frame
        const canvas_size = c.PFVector2F{
            .x = @floatFromInt(snapshot.viewport_width),
            .y = @floatFromInt(snapshot.viewport_height),
        };

        const canvas = c.PFCanvasCreate(self.font_context, &canvas_size) orelse {
            std.debug.print("PathfinderBackend: failed to create canvas\n", .{});
            return .{};
        };
        // Track ownership - PFCanvasCreateScene takes ownership on success
        var canvas_owned = true;
        defer if (canvas_owned) c.PFCanvasDestroy(canvas);

        // Set up default text state
        initializeCanvasTextState(canvas) catch {
            std.debug.print("PathfinderBackend: failed to initialize text state\n", .{});
        };

        // Render from IR instructions (immediate-mode backend path)
        // Note: We only render draw_rect and draw_text - transforms/state are handled
        // differently in a proper implementation. For the bootstrap backend, we
        // render geometry in IR order which is already in world coordinates.
        var draw_calls: u32 = 0;

        for (snapshot.instructions) |instr| {
            switch (instr) {
                .draw_rect => |rect| {
                    const pf_rect = c.PFRectF{
                        .origin = .{
                            .x = @floatFromInt(rect.bounds.x),
                            .y = @floatFromInt(rect.bounds.y),
                        },
                        .lower_right = .{
                            .x = @floatFromInt(rect.bounds.x + rect.bounds.width),
                            .y = @floatFromInt(rect.bounds.y + rect.bounds.height),
                        },
                    };

                    var color = c.PFColorU{
                        .r = rect.paint_key.color.r,
                        .g = rect.paint_key.color.g,
                        .b = rect.paint_key.color.b,
                        .a = rect.paint_key.color.a,
                    };

                    const fill_style = c.PFFillStyleCreateColor(&color);
                    if (fill_style != null) {
                        defer c.PFFillStyleDestroy(fill_style);
                        c.PFCanvasSetFillStyle(canvas, fill_style);
                        var rect_copy = pf_rect;
                        c.PFCanvasFillRect(canvas, &rect_copy);
                        draw_calls += 1;
                    }
                },
                .draw_text => |text| {
                    var color = c.PFColorU{
                        .r = text.paint_key.color.r,
                        .g = text.paint_key.color.g,
                        .b = text.paint_key.color.b,
                        .a = text.paint_key.color.a,
                    };

                    const fill_style = c.PFFillStyleCreateColor(&color);
                    if (fill_style != null) {
                        defer c.PFFillStyleDestroy(fill_style);
                        c.PFCanvasSetFillStyle(canvas, fill_style);
                        c.PFCanvasSetFontSize(canvas, @floatFromInt(text.text_size));

                        // Get text body from TextRef
                        // Note: inline_text data is stored by value in the instruction
                        const body: []const u8 = switch (text.text_ref) {
                            .inline_text => |inline_t| blk: {
                                // Copy to get stable pointer for the C call
                                break :blk inline_t.data[0..inline_t.len];
                            },
                            .interned => "", // TODO: lookup interned strings
                        };

                        if (body.len > 0) {
                            var pos = c.PFVector2F{
                                .x = @floatFromInt(text.bounds.x),
                                .y = @floatFromInt(text.bounds.y),
                            };
                            c.PFCanvasFillText(canvas, body.ptr, body.len, &pos);
                            draw_calls += 1;
                        }
                    }
                },
                // Skip transform/state ops - IR already has world coordinates
                // These will be properly implemented in the native tile backend
                .push_state, .pop_state, .set_transform, .begin_clip, .end_clip => {},
                .begin_cache_group, .end_cache_group, .tile_hint, .tile_boundary, .nop => {},
            }
        }

        // Build scene from canvas (scene takes ownership of canvas on success)
        const scene = c.PFCanvasCreateScene(canvas);
        if (scene == null) {
            std.debug.print("PathfinderBackend: failed to create scene\n", .{});
            return .{ .draw_calls = draw_calls };
        }
        canvas_owned = false; // Scene now owns the canvas

        // Create proxy and render
        const scene_proxy = c.PFSceneProxyCreateFromSceneAndRayonExecutor(scene, c.PF_RENDERER_LEVEL_D3D11);
        if (scene_proxy == null) {
            c.PFSceneDestroy(scene);
            return .{ .draw_calls = draw_calls };
        }
        defer c.PFSceneProxyDestroy(scene_proxy);

        // Build, render, and swap in one go (like the original compositor)
        // The swap must happen before destroying the proxy
        c.PFSceneProxyBuildAndRenderGL(scene_proxy, self.renderer, self.build_options);
        c.SDL_GL_SwapWindow(self.window);

        const end_time = std.time.nanoTimestamp();

        self.last_frame_stats = .{
            .submit_time_ns = @intCast(end_time - start_time),
            .draw_calls = draw_calls,
            .tiles_rendered = @intCast(snapshot.tile_work.len),
        };

        return self.last_frame_stats;
    }

    /// Present is now a no-op since swap happens in submit()
    /// Kept for API compatibility - real vsync/present logic would go here
    pub fn present(_: *PathfinderBackend) void {
        // Swap already happened in submit()
    }

    /// Query capabilities
    pub fn capabilities(_: *const PathfinderBackend) backend.Capabilities {
        return .{
            .tile_rendering = false, // We translate back to canvas API
            .incremental_update = false, // Full rebuild each frame
            .compute_shaders = false,
            .tile_caching = false,
            .hardware_clip = true,
        };
    }

    /// Resize viewport
    pub fn resize(self: *PathfinderBackend, width: u32, height: u32) void {
        self.viewport_width = width;
        self.viewport_height = height;
        // Note: would need to recreate framebuffer for real resize
    }

    /// Invalidate cache (no-op for Pathfinder, it rebuilds each frame anyway)
    pub fn invalidateCache(_: *PathfinderBackend) void {}

    /// Poll SDL events, returns false if quit requested
    pub fn pollEvents(_: *PathfinderBackend) bool {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) {
                return false;
            }
        }
        return true;
    }

    /// Clean up all resources
    pub fn deinit(self: *PathfinderBackend) void {
        c.PFCanvasFontContextRelease(self.font_context);
        c.PFBuildOptionsDestroy(self.build_options);
        c.PFGLRendererDestroy(self.renderer);
        c.PFResourceLoaderDestroy(self.resources);
        c.SDL_GL_DeleteContext(self.gl_context);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    // === Helpers ===

    fn setGlAttribute(attr: c.SDL_GLattr, value: i32) !void {
        if (c.SDL_GL_SetAttribute(attr, value) != 0) {
            return error.SDLGLAttributeFailed;
        }
    }

    fn glFunctionLoader(name: [*c]const u8, userdata: ?*anyopaque) callconv(.c) ?*const anyopaque {
        _ = userdata;
        return c.SDL_GL_GetProcAddress(name);
    }

    fn makeRendererOptions(dest: c.PFDestFramebufferRef, bg: ?types.Color) c.PFRendererOptions {
        // Always set a background color to ensure framebuffer is cleared
        const bg_color = bg orelse types.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
        return .{
            .dest = dest,
            .background_color = .{
                .r = @as(f32, @floatFromInt(bg_color.r)) / 255.0,
                .g = @as(f32, @floatFromInt(bg_color.g)) / 255.0,
                .b = @as(f32, @floatFromInt(bg_color.b)) / 255.0,
                .a = @as(f32, @floatFromInt(bg_color.a)) / 255.0,
            },
            .flags = c.PF_RENDERER_OPTIONS_FLAGS_HAS_BACKGROUND_COLOR,
        };
    }

    fn initializeCanvasTextState(canvas: c.PFCanvasRef) !void {
        const name_ptr: [*c]const u8 = @ptrCast(default_font_postscript_name.ptr);
        if (c.PFCanvasSetFontByPostScriptName(canvas, name_ptr, default_font_postscript_name.len) != 0) {
            return error.FontUnavailable;
        }
        c.PFCanvasSetTextAlign(canvas, c.PF_TEXT_ALIGN_LEFT);
        c.PFCanvasSetTextBaseline(canvas, c.PF_TEXT_BASELINE_TOP);
    }
};

