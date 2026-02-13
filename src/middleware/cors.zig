const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

/// CORS middleware configuration.
pub const CorsConfig = struct {
    /// Allowed origins. Use "*" for any origin.
    allow_origins: []const []const u8 = &.{"*"},
    /// Allowed HTTP methods.
    allow_methods: []const u8 = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
    /// Allowed request headers.
    allow_headers: []const u8 = "Content-Type, Authorization, Accept",
    /// Headers exposed to the browser.
    expose_headers: []const u8 = "",
    /// Whether to include credentials (cookies, auth).
    allow_credentials: bool = false,
    /// Max age for preflight cache (seconds).
    max_age: []const u8 = "86400",
};

/// Create a CORS middleware with the given config.
/// Returns a HandlerFn that can be used in the middleware pipeline.
pub fn cors(comptime config: CorsConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            const origin = ctx.request.header("Origin");

            // Add CORS headers if Origin is present
            if (origin) |req_origin| {
                const is_wildcard = comptime isWildcardOrigin(config.allow_origins);

                const allowed = is_wildcard or originAllowed(config.allow_origins, req_origin);
                if (allowed) {
                    // Wildcard without credentials: use "*". Otherwise: mirror the origin.
                    const origin_value = if (is_wildcard and !config.allow_credentials) "*" else req_origin;
                    ctx.response.headers.append(ctx.allocator, "Access-Control-Allow-Origin", origin_value) catch {};

                    if (config.allow_credentials) {
                        ctx.response.headers.append(ctx.allocator, "Access-Control-Allow-Credentials", "true") catch {};
                    }

                    if (config.expose_headers.len > 0) {
                        ctx.response.headers.append(ctx.allocator, "Access-Control-Expose-Headers", config.expose_headers) catch {};
                    }

                    ctx.response.headers.append(ctx.allocator, "Vary", "Origin") catch {};
                }
            }

            // Handle preflight OPTIONS requests
            if (ctx.request.method == .OPTIONS) {
                if (ctx.request.header("Access-Control-Request-Method") != null) {
                    ctx.response.headers.append(ctx.allocator, "Access-Control-Allow-Methods", config.allow_methods) catch {};
                    ctx.response.headers.append(ctx.allocator, "Access-Control-Allow-Headers", config.allow_headers) catch {};
                    ctx.response.headers.append(ctx.allocator, "Access-Control-Max-Age", config.max_age) catch {};
                    ctx.response.status = .no_content;
                    // Don't call next — preflight is fully handled
                    return;
                }
            }

            try ctx.next();
        }
    };
    return &S.handle;
}

fn isWildcardOrigin(comptime origins: []const []const u8) bool {
    inline for (origins) |o| {
        if (comptime std.mem.eql(u8, o, "*")) return true;
    }
    return false;
}

fn originAllowed(comptime origins: []const []const u8, origin: []const u8) bool {
    inline for (origins) |allowed| {
        if (comptime std.mem.eql(u8, allowed, "*")) return true;
        if (std.mem.eql(u8, allowed, origin)) return true;
    }
    return false;
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;
const Router = @import("../router/router.zig").Router;
const Response = @import("../core/http/response.zig").Response;

test "CORS adds headers on requests with Origin" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "ok");
        }
    };
    const App = Router.define(.{
        .middleware = &.{cors(.{})},
        .routes = &.{
            Router.get("/api", H.handle),
        },
    });

    var req: Request = .{ .method = .GET, .path = "/api" };
    try req.headers.append(std.testing.allocator, "Origin", "http://example.com");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("*", resp.headers.get("Access-Control-Allow-Origin").?);
}

test "CORS preflight returns 204 with correct headers" {
    const Noop = struct {
        fn handle(_: *Context) !void {}
    };
    const App = Router.define(.{
        .middleware = &.{cors(.{})},
        .routes = &.{
            Router.get("/api", Noop.handle),
            // Explicit OPTIONS route so preflight reaches the middleware
            Router.options("/api", Noop.handle),
        },
    });

    var req: Request = .{ .method = .OPTIONS, .path = "/api" };
    try req.headers.append(std.testing.allocator, "Origin", "http://example.com");
    try req.headers.append(std.testing.allocator, "Access-Control-Request-Method", "POST");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.no_content, resp.status);
    try std.testing.expectEqualStrings("*", resp.headers.get("Access-Control-Allow-Origin").?);
    try std.testing.expect(resp.headers.get("Access-Control-Allow-Methods") != null);
    try std.testing.expect(resp.headers.get("Access-Control-Max-Age") != null);
}

test "CORS with specific origins rejects unknown origin" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "ok");
        }
    };
    const App = Router.define(.{
        .middleware = &.{cors(.{ .allow_origins = &.{"http://allowed.com"} })},
        .routes = &.{
            Router.get("/api", H.handle),
        },
    });

    var req: Request = .{ .method = .GET, .path = "/api" };
    try req.headers.append(std.testing.allocator, "Origin", "http://evil.com");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    // Should NOT have CORS headers since origin isn't allowed
    try std.testing.expect(resp.headers.get("Access-Control-Allow-Origin") == null);
}

test "CORS with specific origins allows matching origin" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "ok");
        }
    };
    const App = Router.define(.{
        .middleware = &.{cors(.{ .allow_origins = &.{"http://allowed.com"} })},
        .routes = &.{
            Router.get("/api", H.handle),
        },
    });

    var req: Request = .{ .method = .GET, .path = "/api" };
    try req.headers.append(std.testing.allocator, "Origin", "http://allowed.com");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("http://allowed.com", resp.headers.get("Access-Control-Allow-Origin").?);
}

test "CORS no headers when no Origin in request" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "ok");
        }
    };
    const App = Router.define(.{
        .middleware = &.{cors(.{})},
        .routes = &.{
            Router.get("/api", H.handle),
        },
    });

    var req: Request = .{ .method = .GET, .path = "/api" };
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    // No Origin header in request -> no CORS headers in response
    try std.testing.expect(resp.headers.get("Access-Control-Allow-Origin") == null);
}
