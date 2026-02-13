//! Zzz - The Zig Web Framework That Never Sleeps
//!
//! A Phoenix-inspired, batteries-included web framework written in Zig.
//! Blazing fast, memory-safe, with compile-time route resolution.

const std = @import("std");

// Core HTTP
pub const Server = @import("core/server.zig").Server;
pub const Config = @import("core/server.zig").Config;
pub const Handler = @import("core/server.zig").Handler;

pub const Request = @import("core/http/request.zig").Request;
pub const Method = @import("core/http/request.zig").Method;
pub const Response = @import("core/http/response.zig").Response;
pub const StatusCode = @import("core/http/status.zig").StatusCode;
pub const Headers = @import("core/http/headers.zig").Headers;

// HTTP Parser
pub const parser = @import("core/http/parser.zig");

// Router & Middleware
pub const Router = @import("router/router.zig").Router;
pub const Context = @import("middleware/context.zig").Context;
pub const HandlerFn = @import("middleware/context.zig").HandlerFn;
pub const Params = @import("middleware/context.zig").Params;
pub const Assigns = @import("middleware/context.zig").Assigns;

// Re-export Io for convenience
pub const Io = @import("std").Io;

/// Framework version.
pub const version = "0.1.0";

test {
    // Run all tests in submodules
    std.testing.refAllDecls(@This());
}
