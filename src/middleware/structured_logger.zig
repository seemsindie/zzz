const std = @import("std");
const native_os = @import("builtin").os.tag;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "err",
        };
    }

    pub fn enabled(self: LogLevel, min: LogLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(min);
    }
};

pub const LogFormat = enum {
    text,
    json,
};

pub const StructuredLoggerConfig = struct {
    level: LogLevel = .info,
    format: LogFormat = .text,
};

/// Structured logging middleware — logs method, path, status, duration, and request ID.
/// Supports text and JSON output formats with configurable log levels.
pub fn structuredLogger(comptime config: StructuredLoggerConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            const start = getMonotonicNs();

            try ctx.next();

            const elapsed_ns = getMonotonicNs() - start;
            const elapsed_us: u64 = @intCast(@divTrunc(elapsed_ns, 1000));

            const status = ctx.response.status.code();
            const log_level: LogLevel = if (status >= 500)
                .err
            else if (status >= 400)
                .warn
            else
                .info;

            if (!log_level.enabled(config.level)) return;

            const method = ctx.request.method.toString();
            const path = ctx.request.path;
            const request_id = ctx.getAssign("request_id");

            var buf: [1024]u8 = undefined;

            switch (config.format) {
                .text => {
                    if (request_id) |rid| {
                        const msg = std.fmt.bufPrint(&buf, "[{s}] {s} {s} -> {d} ({d}us) [{s}]", .{
                            log_level.toString(),
                            method,
                            path,
                            status,
                            elapsed_us,
                            rid,
                        }) catch return;
                        std.log.info("{s}", .{msg});
                    } else {
                        const msg = std.fmt.bufPrint(&buf, "[{s}] {s} {s} -> {d} ({d}us)", .{
                            log_level.toString(),
                            method,
                            path,
                            status,
                            elapsed_us,
                        }) catch return;
                        std.log.info("{s}", .{msg});
                    }
                },
                .json => {
                    if (request_id) |rid| {
                        const msg = std.fmt.bufPrint(&buf, "{{\"level\":\"{s}\",\"method\":\"{s}\",\"path\":\"{s}\",\"status\":{d},\"duration_us\":{d},\"request_id\":\"{s}\"}}", .{
                            log_level.toString(),
                            method,
                            path,
                            status,
                            elapsed_us,
                            rid,
                        }) catch return;
                        std.log.info("{s}", .{msg});
                    } else {
                        const msg = std.fmt.bufPrint(&buf, "{{\"level\":\"{s}\",\"method\":\"{s}\",\"path\":\"{s}\",\"status\":{d},\"duration_us\":{d}}}", .{
                            log_level.toString(),
                            method,
                            path,
                            status,
                            elapsed_us,
                        }) catch return;
                        std.log.info("{s}", .{msg});
                    }
                },
            }
        }
    };
    return &S.handle;
}

fn getMonotonicNs() i128 {
    if (native_os == .linux) {
        const linux = std.os.linux;
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
        return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
    } else {
        const c = std.c;
        var ts: c.timespec = undefined;
        _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
        return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "structuredLogger text mode runs without crash" {
    const handler = comptime structuredLogger(.{ .format = .text });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.text(.ok, "ok");
        }
    };

    var req: Request = .{ .method = .GET, .path = "/test" };
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
}

test "structuredLogger json mode runs without crash" {
    const handler = comptime structuredLogger(.{ .format = .json });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.text(.ok, "ok");
        }
    };

    var req: Request = .{ .method = .POST, .path = "/api/data" };
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
}

test "structuredLogger respects log level filtering" {
    // Set min level to err — info-level logs (200 status) should be silently skipped
    const handler = comptime structuredLogger(.{ .level = .err });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.text(.ok, "ok");
        }
    };

    var req: Request = .{ .method = .GET, .path = "/" };
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

    // Should not crash; the info-level log is just skipped
    try handler(&ctx);
    try std.testing.expectEqual(StatusCode.ok, ctx.response.status);
}
