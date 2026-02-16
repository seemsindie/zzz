const std = @import("std");
const native_os = @import("builtin").os.tag;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;
const Method = @import("../core/http/request.zig").Method;

pub const TelemetryEvent = union(enum) {
    request_start: RequestStart,
    request_end: RequestEnd,

    pub const RequestStart = struct {
        method: Method,
        path: []const u8,
        timestamp_ns: i128,
    };

    pub const RequestEnd = struct {
        method: Method,
        path: []const u8,
        status: u16,
        duration_ns: i128,
        timestamp_ns: i128,
    };
};

pub const TelemetryConfig = struct {
    on_event: *const fn (TelemetryEvent) void,
};

/// Telemetry middleware — fires lifecycle events for request start and end.
pub fn telemetry(comptime config: TelemetryConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            const start = getMonotonicNs();

            config.on_event(.{ .request_start = .{
                .method = ctx.request.method,
                .path = ctx.request.path,
                .timestamp_ns = start,
            } });

            try ctx.next();

            const end = getMonotonicNs();

            config.on_event(.{ .request_end = .{
                .method = ctx.request.method,
                .path = ctx.request.path,
                .status = ctx.response.status.code(),
                .duration_ns = end - start,
                .timestamp_ns = end,
            } });
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

const TestRecorder = struct {
    var start_count: u32 = 0;
    var end_count: u32 = 0;
    var last_status: u16 = 0;
    var last_method: Method = .GET;

    fn record(event: TelemetryEvent) void {
        switch (event) {
            .request_start => |e| {
                start_count += 1;
                last_method = e.method;
            },
            .request_end => |e| {
                end_count += 1;
                last_status = e.status;
            },
        }
    }

    fn reset() void {
        start_count = 0;
        end_count = 0;
        last_status = 0;
        last_method = .GET;
    }
};

test "telemetry fires both events" {
    TestRecorder.reset();

    const handler = comptime telemetry(.{ .on_event = &TestRecorder.record });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.text(.ok, "ok");
        }
    };

    var req: Request = .{ .method = .POST, .path = "/api/test" };
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

    try std.testing.expectEqual(@as(u32, 1), TestRecorder.start_count);
    try std.testing.expectEqual(@as(u32, 1), TestRecorder.end_count);
    try std.testing.expectEqual(@as(u16, 200), TestRecorder.last_status);
    try std.testing.expectEqual(Method.POST, TestRecorder.last_method);
}
