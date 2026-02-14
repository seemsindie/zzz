const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

/// Embedded zzz.js source.
const zzz_js_source = @embedFile("../js/zzz.js");

/// Configuration for the zzz.js serving middleware.
pub const ZzzJsConfig = struct {
    /// Path to serve zzz.js at (default: "/__zzz/zzz.js").
    path: []const u8 = "/__zzz/zzz.js",
    /// Cache-Control max-age in seconds (default: 86400 = 1 day).
    max_age: u32 = 86400,
};

/// Middleware that serves the embedded zzz.js client library at the configured path.
/// Non-matching requests are passed through to ctx.next().
pub fn zzzJs(comptime config: ZzzJsConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (ctx.request.method == .GET and std.mem.eql(u8, ctx.request.path, config.path)) {
                ctx.response.status = .ok;
                ctx.response.body = zzz_js_source;
                ctx.response.headers.append(ctx.allocator, "Content-Type", "application/javascript; charset=utf-8") catch {};
                ctx.response.headers.append(ctx.allocator, "Cache-Control", comptime cacheControlValue(config.max_age)) catch {};
                return;
            }
            try ctx.next();
        }

        fn cacheControlValue(comptime max_age: u32) []const u8 {
            return std.fmt.comptimePrint("public, max-age={d}", .{max_age});
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;
const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "zzzJs serves JS at /__zzz/zzz.js" {
    const handler = comptime zzzJs(.{});

    var req: Request = .{ .method = .GET, .path = "/__zzz/zzz.js" };
    defer req.deinit(testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expectEqual(StatusCode.ok, ctx.response.status);
    try testing.expect(ctx.response.body != null);
    try testing.expect(ctx.response.body.?.len > 0);
    // Should contain "Zzz" somewhere in the JS source
    try testing.expect(std.mem.indexOf(u8, ctx.response.body.?, "Zzz") != null);
    try testing.expectEqualStrings("application/javascript; charset=utf-8", ctx.response.headers.get("Content-Type").?);
    // Check cache-control
    const cc = ctx.response.headers.get("Cache-Control").?;
    try testing.expect(std.mem.indexOf(u8, cc, "public") != null);
    try testing.expect(std.mem.indexOf(u8, cc, "max-age=86400") != null);
}

test "zzzJs passes through non-matching requests" {
    const handler = comptime zzzJs(.{});

    var req: Request = .{ .method = .GET, .path = "/other" };
    defer req.deinit(testing.allocator);

    var next_called = false;
    const NextHandler = struct {
        var called: *bool = undefined;
        fn handle(_: *Context) anyerror!void {
            called.* = true;
        }
    };
    NextHandler.called = &next_called;

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = &NextHandler.handle,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expect(next_called);
}

test "zzzJs ignores POST requests to zzz.js path" {
    const handler = comptime zzzJs(.{});

    var req: Request = .{ .method = .POST, .path = "/__zzz/zzz.js" };
    defer req.deinit(testing.allocator);

    var next_called = false;
    const NextHandler = struct {
        var called: *bool = undefined;
        fn handle(_: *Context) anyerror!void {
            called.* = true;
        }
    };
    NextHandler.called = &next_called;

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = &NextHandler.handle,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expect(next_called);
}
