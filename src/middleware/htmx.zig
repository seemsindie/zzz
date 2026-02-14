const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

/// Configuration for htmx middleware.
pub const HtmxConfig = struct {
    /// Automatically set assigns for htmx request headers.
    set_assigns: bool = true,
};

/// Create an htmx middleware that auto-detects htmx requests and sets assigns.
///
/// When `set_assigns` is true (default), the following assigns are set:
/// - `is_htmx`: "true" or "false"
/// - `htmx_target`: value of HX-Target header (if present)
/// - `htmx_trigger`: value of HX-Trigger header (if present)
pub fn htmx(comptime config: HtmxConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (config.set_assigns) {
                const is_htmx = ctx.request.header("HX-Request") != null;
                ctx.assign("is_htmx", if (is_htmx) "true" else "false");
                if (ctx.request.header("HX-Target")) |t| ctx.assign("htmx_target", t);
                if (ctx.request.header("HX-Trigger")) |t| ctx.assign("htmx_trigger", t);
            }
            try ctx.next();
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const Router = @import("../router/router.zig").Router;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "htmx middleware sets is_htmx assign to true for htmx requests" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const is_htmx = ctx.getAssign("is_htmx") orelse "missing";
            ctx.text(.ok, is_htmx);
        }
    };
    const App = Router.define(.{
        .middleware = &.{htmx(.{})},
        .routes = &.{Router.get("/test", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/test" };
    try req.headers.append(std.testing.allocator, "HX-Request", "true");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("true", resp.body.?);
}

test "htmx middleware sets is_htmx assign to false for normal requests" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const is_htmx = ctx.getAssign("is_htmx") orelse "missing";
            ctx.text(.ok, is_htmx);
        }
    };
    const App = Router.define(.{
        .middleware = &.{htmx(.{})},
        .routes = &.{Router.get("/test", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/test" };
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("false", resp.body.?);
}

test "htmx middleware sets htmx_target and htmx_trigger assigns" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const target = ctx.getAssign("htmx_target") orelse "none";
            const trigger = ctx.getAssign("htmx_trigger") orelse "none";
            var buf: [128]u8 = undefined;
            const body = std.fmt.bufPrint(&buf, "{s}|{s}", .{ target, trigger }) catch "error";
            ctx.text(.ok, body);
        }
    };
    const App = Router.define(.{
        .middleware = &.{htmx(.{})},
        .routes = &.{Router.get("/test", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/test" };
    try req.headers.append(std.testing.allocator, "HX-Request", "true");
    try req.headers.append(std.testing.allocator, "HX-Target", "#content");
    try req.headers.append(std.testing.allocator, "HX-Trigger", "btn-load");
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("#content|btn-load", resp.body.?);
}
