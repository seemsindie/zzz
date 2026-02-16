const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

pub const HealthConfig = struct {
    path: []const u8 = "/health",
};

/// Health check middleware — responds with `{"status":"ok"}` at the configured path.
pub fn health(comptime config: HealthConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (ctx.request.method == .GET and std.mem.eql(u8, ctx.request.path, config.path)) {
                ctx.json(.ok, "{\"status\":\"ok\"}");
                return;
            }
            try ctx.next();
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "health responds at /health" {
    const handler = comptime health(.{});

    var req: Request = .{ .method = .GET, .path = "/health" };
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.ok, ctx.response.status);
    try std.testing.expectEqualStrings("{\"status\":\"ok\"}", ctx.response.body.?);
}

test "health passes through other paths" {
    const handler = comptime health(.{});

    const NextHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.text(.ok, "next");
        }
    };

    var req: Request = .{ .method = .GET, .path = "/api/users" };
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = &NextHandler.handle,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqualStrings("next", ctx.response.body.?);
}

test "health custom path" {
    const handler = comptime health(.{ .path = "/healthz" });

    var req: Request = .{ .method = .GET, .path = "/healthz" };
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.ok, ctx.response.status);
    try std.testing.expectEqualStrings("{\"status\":\"ok\"}", ctx.response.body.?);
}
