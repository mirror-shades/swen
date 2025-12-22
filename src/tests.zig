//! Test entry point for all unit tests
//!
//! Import all modules with tests here so they get discovered.

const std = @import("std");

// Import modules that have tests
const ir = @import("core/ir.zig");
const backend = @import("render/backend.zig");

// Re-export the tests
test {
    std.testing.refAllDecls(@This());
    _ = ir;
    _ = backend;
}

