const std = @import("std");

pub const Error = error{
    ExpectedRootKeyword,
    ExpectedLeftBrace,
    ExpectedRightBrace,
    ExpectedLeftBracket,
    ExpectedRightBracket,
    ExpectedLeftParen,
    ExpectedRightParen,
    ExpectedComma,
    ExpectedNumber,
    ExpectedIdentifier,
    ExpectedString,
    DuplicateProperty,
    MissingProperty,
    InvalidTextSize,
    InvalidNumber,
    InvalidString,
    InvalidSize,
    InvalidPosition,
    InvalidBackground,
    ExpectedColor,
    InvalidMatrix,
    DuplicateNode,
    MissingRequiredNode,
    OutOfMemory,
    // runtime
    InvalidSurfaceSize,
    FontUnavailable,
    FontContextUnavailable,
    CanvasCreateFailed,
    FillStyleCreateFailed,
    SceneCreateFailed,
    SDLInitFailed,
    SDLGLAttributeFailed,
    WindowCreateFailed,
    GLContextCreateFailed,
    GLContextMakeCurrentFailed,
    GLDestFramebufferCreateFailed,
    GLDeviceCreateFailed,
    ResourceLoaderCreateFailed,
    RendererCreateFailed,
    BuildOptionsCreateFailed,
    SceneProxyCreateFailed,
};

pub fn throwError(
    issue: []const u8,
    line: usize,
    column: usize,
    offset: usize,
    thrown_error: Error,
) Error {
    std.debug.print("error: {s}\n", .{issue});
    std.debug.print("\t at line {d} column {d} offset {d}\n", .{ line, column, offset });
    return thrown_error;
}

pub fn throwRuntimeError(issue: []const u8, thrown_error: Error) Error {
    std.debug.print("runtime error: {s}\n", .{issue});
    return thrown_error;
}
