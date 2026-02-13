const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

pub const ErrorHandlerConfig = struct {
    show_details: bool = false, // show error name in response (dev mode)
};

/// Global error handler middleware. Catches errors from downstream handlers
/// and returns a 500 response instead of propagating the error.
pub fn errorHandler(comptime config: ErrorHandlerConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.next() catch |err| {
                ctx.response.status = .internal_server_error;
                ctx.response.body = if (config.show_details)
                    @errorName(err)
                else
                    "500 Internal Server Error";
                ctx.response.headers.append(ctx.allocator, "Content-Type", "text/plain; charset=utf-8") catch {};
                return; // swallow the error — we've handled it
            };
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "errorHandler catches errors and returns 500" {
    const FailingHandler = struct {
        fn handle(_: *Context) anyerror!void {
            return error.SomeError;
        }
    };

    // Build a minimal pipeline: errorHandler -> failingHandler
    const handler = comptime errorHandler(.{});

    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = &FailingHandler.handle,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.internal_server_error, ctx.response.status);
    try std.testing.expectEqualStrings("500 Internal Server Error", ctx.response.body.?);
}

test "errorHandler show_details reveals error name" {
    const FailingHandler = struct {
        fn handle(_: *Context) anyerror!void {
            return error.DatabaseTimeout;
        }
    };

    const handler = comptime errorHandler(.{ .show_details = true });

    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = &FailingHandler.handle,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.internal_server_error, ctx.response.status);
    try std.testing.expectEqualStrings("DatabaseTimeout", ctx.response.body.?);
}

test "errorHandler passes through on success" {
    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.respond(.ok, "text/plain; charset=utf-8", "all good");
        }
    };

    const handler = comptime errorHandler(.{});

    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = &OkHandler.handle,
    };
    defer ctx.response.deinit(std.testing.allocator);

    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.ok, ctx.response.status);
    try std.testing.expectEqualStrings("all good", ctx.response.body.?);
}
