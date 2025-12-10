const std = @import("std");
const math = std.math;
const types = @import("./types.zig");
const Color = types.Color;
const Vector = types.Vector;
const Rect = types.Rect;
const memory = @import("./memory.zig");
const reporter = @import("./reporter.zig");
const Error = reporter.Error;

const default_font_postscript_name = "LiberationSans";
const default_text_size: u16 = 14;

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL2/SDL.h");
    @cInclude("pathfinder.h");
});

pub fn compose(root: types.Root, rect_buffer: *memory.RectArray) !void {
    const surface = root.desktop.surface_rect;
    if (surface.size.x <= 0 or surface.size.y <= 0) {
        return reporter.throwRuntimeError("desktop surface must have a positive size", Error.InvalidSurfaceSize);
    }

    prepareDesktopSceneData(root.desktop, rect_buffer);

    const scene = try buildScene(root.desktop, rect_buffer, surface.size);
    try renderScene(scene, surface.size, surface.background);
}

fn buildScene(desktop: types.Desktop, rect_buffer: *memory.RectArray, size: Vector) !c.PFSceneRef {
    const canvas_size = c.PFVector2F{
        .x = @floatFromInt(size.x),
        .y = @floatFromInt(size.y),
    };

    const font_context = c.PFCanvasFontContextCreateWithSystemSource();
    if (font_context == null) {
        return reporter.throwRuntimeError("failed to create canvas font context", Error.FontContextUnavailable);
    }
    defer c.PFCanvasFontContextRelease(font_context);

    const canvas = c.PFCanvasCreate(font_context, &canvas_size);
    if (canvas == null) {
        return reporter.throwRuntimeError("failed to create canvas", Error.CanvasCreateFailed);
    }
    var canvas_owned = true;
    defer if (canvas_owned) c.PFCanvasDestroy(canvas);
    try initializeCanvasTextState(canvas);

    const desktop_color = desktop.surface_rect.background orelse defaultBackgroundColor();
    try fillCanvasRect(canvas, desktop_color, makeCanvasRect(size));

    var idx: usize = rect_buffer.getLength();
    while (idx > 0) {
        idx -= 1;
        const rect = rect_buffer.getItem(idx);
        if (rect.background) |background| {
            const pf_rect = try rectToPfRect(rect);
            try fillCanvasRect(canvas, background, pf_rect);
        }
    }

    if (desktop.nodes) |nodes| {
        try drawTextNodes(canvas, nodes);
    }

    const scene = c.PFCanvasCreateScene(canvas);
    if (scene == null) {
        return reporter.throwRuntimeError("failed to create scene from canvas", Error.SceneCreateFailed);
    }
    canvas_owned = false;

    return scene;
}

fn renderScene(
    scene: c.PFSceneRef,
    size: Vector,
    desktop_background: ?Color,
) !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        return reporter.throwRuntimeError("SDL initialization failed", Error.SDLInitFailed);
    }
    defer c.SDL_Quit();

    try setGlAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    try setGlAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    try setGlAttribute(
        c.SDL_GL_CONTEXT_PROFILE_MASK,
        @as(i32, @intCast(c.SDL_GL_CONTEXT_PROFILE_CORE)),
    );
    try setGlAttribute(c.SDL_GL_DOUBLEBUFFER, 1);

    const win_width = size.x;
    const win_height = size.y;

    const window = c.SDL_CreateWindow(
        "swen compositor",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        win_width,
        win_height,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN,
    );
    if (window == null) {
        return reporter.throwRuntimeError("failed to create SDL window", Error.WindowCreateFailed);
    }
    defer c.SDL_DestroyWindow(window);

    const gl_context = c.SDL_GL_CreateContext(window);
    if (gl_context == null) {
        return reporter.throwRuntimeError("failed to create OpenGL context", Error.GLContextCreateFailed);
    }
    defer c.SDL_GL_DeleteContext(gl_context);

    if (c.SDL_GL_MakeCurrent(window, gl_context) != 0) {
        return reporter.throwRuntimeError("failed to activate OpenGL context", Error.GLContextMakeCurrentFailed);
    }

    _ = c.SDL_GL_SetSwapInterval(1);

    c.PFGLLoadWith(glFunctionLoader, null);

    var scene_owned = true;
    defer if (scene_owned) c.PFSceneDestroy(scene);

    const window_size = c.PFVector2I{
        .x = win_width,
        .y = win_height,
    };

    const dest_framebuffer = c.PFGLDestFramebufferCreateFullWindow(&window_size);
    if (dest_framebuffer == null) {
        return reporter.throwRuntimeError("failed to create destination framebuffer", Error.GLDestFramebufferCreateFailed);
    }
    var dest_owned = true;
    defer if (dest_owned) c.PFGLDestFramebufferDestroy(dest_framebuffer);

    const gl_device = c.PFGLDeviceCreate(c.PF_GL_VERSION_GL4, 0);
    if (gl_device == null) {
        return reporter.throwRuntimeError("failed to create OpenGL device", Error.GLDeviceCreateFailed);
    }
    var device_owned = true;
    defer if (device_owned) c.PFGLDeviceDestroy(gl_device);

    const resources = c.PFEmbeddedResourceLoaderCreate();
    if (resources == null) {
        return reporter.throwRuntimeError("failed to create embedded resource loader", Error.ResourceLoaderCreateFailed);
    }
    defer c.PFResourceLoaderDestroy(resources);

    var renderer_mode = c.PFRendererMode{ .level = c.PF_RENDERER_LEVEL_D3D11 };
    var renderer_options = makeRendererOptions(dest_framebuffer, desktop_background);

    const renderer = c.PFGLRendererCreate(gl_device, resources, &renderer_mode, &renderer_options);
    if (renderer == null) {
        return reporter.throwRuntimeError("failed to create renderer", Error.RendererCreateFailed);
    }
    defer c.PFGLRendererDestroy(renderer);
    dest_owned = false;
    device_owned = false;

    const build_options = c.PFBuildOptionsCreate();
    if (build_options == null) {
        return reporter.throwRuntimeError("failed to create build options", Error.BuildOptionsCreateFailed);
    }
    defer c.PFBuildOptionsDestroy(build_options);

    const scene_proxy = c.PFSceneProxyCreateFromSceneAndRayonExecutor(
        scene,
        c.PF_RENDERER_LEVEL_D3D11,
    );
    if (scene_proxy == null) {
        return reporter.throwRuntimeError("failed to create scene proxy", Error.SceneProxyCreateFailed);
    }
    defer c.PFSceneProxyDestroy(scene_proxy);
    scene_owned = false;

    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) {
                running = false;
            }
        }

        c.PFSceneProxyBuildAndRenderGL(scene_proxy, renderer, build_options);
        c.SDL_GL_SwapWindow(window);
        c.SDL_Delay(16);
    }
}

fn prepareDesktopSceneData(
    desktop: types.Desktop,
    rect_buffer: *memory.RectArray,
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

fn pushRectWithChildren(rect: types.Rect, rect_buffer: *memory.RectArray) void {
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

fn fillCanvasRect(canvas: c.PFCanvasRef, color: Color, pf_rect: c.PFRectF) !void {
    try setCanvasFillColor(canvas, color);
    var rect_copy = pf_rect;
    c.PFCanvasFillRect(canvas, &rect_copy);
}

fn setCanvasFillColor(canvas: c.PFCanvasRef, color: Color) !void {
    var pf_color = toPfColor(color);
    const fill_style = c.PFFillStyleCreateColor(&pf_color);
    if (fill_style == null) {
        return reporter.throwRuntimeError("failed to create fill style", Error.FillStyleCreateFailed);
    }
    defer c.PFFillStyleDestroy(fill_style);

    c.PFCanvasSetFillStyle(canvas, fill_style);
}

fn rectToPfRect(rect: Rect) !c.PFRectF {
    if (rect.position) |position| {
        const world_x = rect.local_position.x + position.x;
        const world_y = rect.local_position.y + position.y;

        const origin = c.PFVector2F{
            .x = @floatFromInt(world_x),
            .y = @floatFromInt(world_y),
        };
        const lower_right = c.PFVector2F{
            .x = @floatFromInt(world_x + rect.size.x),
            .y = @floatFromInt(world_y + rect.size.y),
        };

        return .{
            .origin = origin,
            .lower_right = lower_right,
        };
    }
    return reporter.throwRuntimeError("rect must have a position", Error.MissingProperty);
}

fn makeCanvasRect(size: Vector) c.PFRectF {
    const origin = c.PFVector2F{ .x = 0, .y = 0 };
    const lower_right = c.PFVector2F{
        .x = @floatFromInt(size.x),
        .y = @floatFromInt(size.y),
    };

    return .{
        .origin = origin,
        .lower_right = lower_right,
    };
}

fn toPfColor(color: Color) c.PFColorU {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}

fn toPfColorF(color: Color) c.PFColorF {
    return .{
        .r = @as(f32, @floatFromInt(color.r)) / 255.0,
        .g = @as(f32, @floatFromInt(color.g)) / 255.0,
        .b = @as(f32, @floatFromInt(color.b)) / 255.0,
        .a = @as(f32, @floatFromInt(color.a)) / 255.0,
    };
}

fn makeRendererOptions(
    dest: c.PFDestFramebufferRef,
    background: ?Color,
) c.PFRendererOptions {
    const bg_color = background orelse defaultBackgroundColor();
    const has_background = background != null;
    return .{
        .dest = dest,
        .background_color = toPfColorF(bg_color),
        .flags = if (has_background) c.PF_RENDERER_OPTIONS_FLAGS_HAS_BACKGROUND_COLOR else 0,
    };
}

fn setGlAttribute(attr: c.SDL_GLattr, value: i32) !void {
    if (c.SDL_GL_SetAttribute(attr, value) != 0) {
        return reporter.throwRuntimeError("failed to set SDL GL attribute", Error.SDLGLAttributeFailed);
    }
}

fn toI32(value: usize) !i32 {
    if (value > math.maxInt(i32)) {
        return reporter.throwRuntimeError("value exceeds 32-bit integer range", Error.DimensionTooLarge);
    }
    return @as(i32, @intCast(value));
}

fn glFunctionLoader(name: [*c]const u8, userdata: ?*anyopaque) callconv(.c) ?*const anyopaque {
    _ = userdata;
    return c.SDL_GL_GetProcAddress(name);
}

fn defaultBackgroundColor() Color {
    return Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
}

fn initializeCanvasTextState(canvas: c.PFCanvasRef) !void {
    try setCanvasFont(canvas, default_font_postscript_name);
    c.PFCanvasSetTextAlign(canvas, c.PF_TEXT_ALIGN_LEFT);
    c.PFCanvasSetTextBaseline(canvas, c.PF_TEXT_BASELINE_TOP);
}

fn setCanvasFont(canvas: c.PFCanvasRef, font_name: []const u8) !void {
    const name_ptr: [*c]const u8 = @ptrCast(font_name.ptr);
    const result = c.PFCanvasSetFontByPostScriptName(canvas, name_ptr, font_name.len);
    if (result != 0) {
        return reporter.throwRuntimeError("font is not available", Error.FontUnavailable);
    }
}

fn drawTextNodes(canvas: c.PFCanvasRef, nodes: []const types.Node) !void {
    for (nodes) |node| {
        switch (node) {
            .rect => |rect| {
                if (rect.children) |children| {
                    try drawTextNodes(canvas, children);
                }
            },
            .text => |text| {
                try drawSingleText(canvas, text);
            },
            .transform => |transform| {
                if (transform.children) |children| {
                    try drawTextNodes(canvas, children);
                }
            },
        }
    }
}

fn drawSingleText(canvas: c.PFCanvasRef, text: types.Text) !void {
    const world_position = textWorldPosition(text);
    const pf_position = c.PFVector2F{
        .x = @as(f32, @floatFromInt(world_position.x)),
        .y = @as(f32, @floatFromInt(world_position.y)),
    };

    const font_size_value = @as(u16, text.text_size orelse default_text_size);
    const font_size = @as(f32, @floatFromInt(font_size_value));
    c.PFCanvasSetFontSize(canvas, font_size);

    try setCanvasFillColor(canvas, text.color);

    const text_ptr: [*c]const u8 = @ptrCast(text.body.ptr);
    c.PFCanvasFillText(canvas, text_ptr, text.body.len, &pf_position);
}

fn textWorldPosition(text: types.Text) Vector {
    const pos = text.position.?;
    return .{
        .x = text.local_position.x + pos.x,
        .y = text.local_position.y + pos.y,
    };
}
