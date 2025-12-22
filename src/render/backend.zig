//! Backend Abstraction Layer
//!
//! This module defines the interface between the IR layer and rendering backends.
//! Any backend (Pathfinder, native tile GPU, software rasterizer, etc.) implements
//! this interface to receive frame snapshots from the tile scheduler.
//!
//! Design goals:
//! - FrameSnapshot is the sole contract between IR and backend
//! - Backends are swappable at compile-time or runtime
//! - Backend-specific state is encapsulated
//! - IR layer remains backend-agnostic

const std = @import("std");
const ir = @import("../core/ir.zig");
const types = @import("../core/types.zig");

// ============================================================================
// Backend Interface
// ============================================================================

/// Backend capability flags - what features a backend supports
pub const Capabilities = packed struct {
    /// Supports tile-based rendering (can use TileWork directly)
    tile_rendering: bool = false,
    /// Supports incremental/dirty-rect updates
    incremental_update: bool = false,
    /// Supports GPU compute shaders
    compute_shaders: bool = false,
    /// Supports caching rendered tiles
    tile_caching: bool = false,
    /// Supports hardware scissors/clipping
    hardware_clip: bool = false,
    _padding: u3 = 0,
};

/// Statistics returned after rendering a frame
pub const FrameResult = struct {
    /// Time spent submitting work to GPU (nanoseconds)
    submit_time_ns: u64 = 0,
    /// Time spent waiting for GPU (nanoseconds)
    gpu_time_ns: u64 = 0,
    /// Number of draw calls issued
    draw_calls: u32 = 0,
    /// Number of tiles actually rendered (may be less than scheduled due to caching)
    tiles_rendered: u32 = 0,
    /// Number of tiles served from cache
    tiles_cached: u32 = 0,
    /// Peak GPU memory used (bytes)
    gpu_memory_bytes: u64 = 0,
};

/// Runtime-polymorphic backend interface (vtable-based)
/// Use this when backend selection happens at runtime.
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Submit a frame snapshot for rendering
        submit: *const fn (ptr: *anyopaque, snapshot: *const ir.FrameSnapshot) FrameResult,
        /// Present the rendered frame to the screen
        present: *const fn (ptr: *anyopaque) void,
        /// Query backend capabilities
        capabilities: *const fn (ptr: *anyopaque) Capabilities,
        /// Resize the viewport
        resize: *const fn (ptr: *anyopaque, width: u32, height: u32) void,
        /// Invalidate all cached state (e.g., on theme change)
        invalidate_cache: *const fn (ptr: *anyopaque) void,
        /// Clean up resources
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// Submit a frame snapshot for rendering
    pub fn submit(self: Backend, snapshot: *const ir.FrameSnapshot) FrameResult {
        return self.vtable.submit(self.ptr, snapshot);
    }

    /// Present the rendered frame to the screen
    pub fn present(self: Backend) void {
        self.vtable.present(self.ptr);
    }

    /// Query backend capabilities
    pub fn capabilities(self: Backend) Capabilities {
        return self.vtable.capabilities(self.ptr);
    }

    /// Resize the viewport
    pub fn resize(self: Backend, width: u32, height: u32) void {
        self.vtable.resize(self.ptr, width, height);
    }

    /// Invalidate all cached state
    pub fn invalidateCache(self: Backend) void {
        self.vtable.invalidate_cache(self.ptr);
    }

    /// Clean up resources
    pub fn deinit(self: Backend) void {
        self.vtable.deinit(self.ptr);
    }
};

// ============================================================================
// Compile-time Backend Interface
// ============================================================================

/// Compile-time polymorphic backend wrapper.
/// Use this when backend is known at compile time for zero-overhead abstraction.
///
/// Any backend type must implement:
/// - submit(snapshot: *const ir.FrameSnapshot) FrameResult
/// - present() void
/// - capabilities() Capabilities
/// - resize(width: u32, height: u32) void
/// - invalidateCache() void
/// - deinit() void
pub fn Renderer(comptime BackendImpl: type) type {
    return struct {
        backend: BackendImpl,
        ir_buffer: ir.IRBuffer,
        scheduler: ir.TileScheduler,

        const Self = @This();

        pub fn init(backend: BackendImpl) Self {
            return .{
                .backend = backend,
                .ir_buffer = ir.IRBuffer.init(),
                .scheduler = ir.TileScheduler.init(),
            };
        }

        /// Full render pipeline: lower scene → schedule tiles → submit to backend
        pub fn renderDesktop(self: *Self, desktop: types.Desktop) !FrameResult {
            // Step 1: Lower scene tree to IR
            try ir.lowerDesktop(&self.ir_buffer, desktop);

            // Step 2: Schedule tiles
            self.scheduler.setViewport(
                @intCast(desktop.size.x),
                @intCast(desktop.size.y),
            );
            try self.scheduler.schedule(&self.ir_buffer);

            // Step 3: Build snapshot and submit to backend
            const snapshot = self.scheduler.buildSnapshot(&self.ir_buffer);
            return self.backend.submit(&snapshot);
        }

        /// Present the rendered frame
        pub fn present(self: *Self) void {
            self.backend.present();
        }

        /// Get backend capabilities
        pub fn capabilities(self: *const Self) Capabilities {
            return self.backend.capabilities();
        }

        /// Resize viewport
        pub fn resize(self: *Self, width: u32, height: u32) void {
            self.backend.resize(width, height);
        }

        /// Clean up
        pub fn deinit(self: *Self) void {
            self.backend.deinit();
        }
    };
}

// ============================================================================
// Backend Registration / Factory (for runtime selection)
// ============================================================================

pub const BackendType = enum {
    pathfinder,
    tile_gpu,
    // Future: software, vulkan, metal, etc.
};

/// Create a backend by type (runtime selection)
/// Returns error if backend is not available/compiled in.
pub fn createBackend(
    backend_type: BackendType,
    width: u32,
    height: u32,
    window_handle: ?*anyopaque,
) !Backend {
    _ = width;
    _ = height;
    _ = window_handle;
    switch (backend_type) {
        .pathfinder => {
            // TODO: return pathfinder backend
            return error.BackendNotImplemented;
        },
        .tile_gpu => {
            // TODO: return native tile GPU backend
            return error.BackendNotImplemented;
        },
    }
}

// ============================================================================
// Null Backend (for testing)
// ============================================================================

/// A no-op backend for testing the IR pipeline without GPU
pub const NullBackend = struct {
    frame_count: u64 = 0,

    pub fn submit(self: *NullBackend, snapshot: *const ir.FrameSnapshot) FrameResult {
        self.frame_count += 1;
        return .{
            .tiles_rendered = @intCast(snapshot.tile_work.len),
            .draw_calls = 1,
        };
    }

    pub fn present(_: *NullBackend) void {}

    pub fn capabilities(_: *NullBackend) Capabilities {
        return .{};
    }

    pub fn resize(_: *NullBackend, _: u32, _: u32) void {}

    pub fn invalidateCache(_: *NullBackend) void {}

    pub fn deinit(_: *NullBackend) void {}

    /// Convert to runtime Backend interface
    pub fn toBackend(self: *NullBackend) Backend {
        return .{
            .ptr = self,
            .vtable = &.{
                .submit = @ptrCast(&submit),
                .present = @ptrCast(&present),
                .capabilities = @ptrCast(&capabilities),
                .resize = @ptrCast(&resize),
                .invalidate_cache = @ptrCast(&invalidateCache),
                .deinit = @ptrCast(&deinit),
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "NullBackend with Renderer" {
    const backend = NullBackend{};
    var renderer = Renderer(NullBackend).init(backend);
    defer renderer.deinit();

    // Test that the pipeline compiles and runs
    const desktop = types.Desktop{
        .size = .{ .x = 800, .y = 600 },
        .active_workspace = null,
        .nodes = null,
        .workspaces = null,
    };

    const result = try renderer.renderDesktop(desktop);
    try std.testing.expect(result.draw_calls == 1);
}

