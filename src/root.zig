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
pub const RouteDef = @import("router/router.zig").RouteDef;
pub const Context = @import("middleware/context.zig").Context;
pub const HandlerFn = @import("middleware/context.zig").HandlerFn;
pub const Params = @import("middleware/context.zig").Params;
pub const Assigns = @import("middleware/context.zig").Assigns;

// Built-in Middleware
pub const logger = @import("middleware/logger.zig").logger;
pub const cors = @import("middleware/cors.zig").cors;
pub const staticFiles = @import("middleware/static.zig").staticFiles;
pub const bodyParser = @import("middleware/body_parser.zig").bodyParser;

// Body Parser Types
pub const FormData = @import("middleware/body_parser.zig").FormData;
pub const ParsedBody = @import("middleware/body_parser.zig").ParsedBody;
pub const FilePart = @import("middleware/body_parser.zig").FilePart;
pub const urlDecode = @import("middleware/body_parser.zig").urlDecode;

// Session & CSRF
pub const session = @import("middleware/session.zig").session;
pub const SessionConfig = @import("middleware/session.zig").SessionConfig;
pub const csrf = @import("middleware/csrf.zig").csrf;
pub const CsrfConfig = @import("middleware/csrf.zig").CsrfConfig;

// Error Handler
pub const errorHandler = @import("middleware/error_handler.zig").errorHandler;
pub const ErrorHandlerConfig = @import("middleware/error_handler.zig").ErrorHandlerConfig;

// Gzip Compression
pub const gzipCompress = @import("middleware/compress.zig").gzipCompress;
pub const CompressConfig = @import("middleware/compress.zig").CompressConfig;

// Rate Limiting
pub const rateLimit = @import("middleware/rate_limit.zig").rateLimit;
pub const RateLimitConfig = @import("middleware/rate_limit.zig").RateLimitConfig;

// Auth Middleware
pub const bearerAuth = @import("middleware/auth.zig").bearerAuth;
pub const BearerConfig = @import("middleware/auth.zig").BearerConfig;
pub const basicAuth = @import("middleware/auth.zig").basicAuth;
pub const BasicAuthConfig = @import("middleware/auth.zig").BasicAuthConfig;
pub const jwtAuth = @import("middleware/auth.zig").jwtAuth;
pub const JwtConfig = @import("middleware/auth.zig").JwtConfig;

// Resource Helper (re-exported from Router)
pub const ResourceHandlers = Router.ResourceHandlers;

// Cookie helpers (re-exported from Context)
pub const CookieOptions = Context.CookieOptions;

// Re-export Io for convenience
pub const Io = @import("std").Io;

/// Framework version.
pub const version = "0.1.0";

test {
    // Run all tests in submodules
    std.testing.refAllDecls(@This());
}
