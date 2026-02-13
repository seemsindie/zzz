const std = @import("std");
const c = std.c;
const Context = @import("context.zig").Context;

fn getMonotonicNs() i128 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

/// Logger middleware — logs method, path, status code, and response time.
pub fn logger(ctx: *Context) anyerror!void {
    const start = getMonotonicNs();

    try ctx.next();

    const elapsed_ns = getMonotonicNs() - start;
    const elapsed_us: u64 = @intCast(@divTrunc(elapsed_ns, 1000));

    const method = ctx.request.method.toString();
    const path = ctx.request.path;
    const status = ctx.response.status.code();

    if (elapsed_us >= 1_000_000) {
        // >= 1s, show in seconds
        std.log.info("{s} {s} -> {d} ({d}ms)", .{
            method,
            path,
            status,
            elapsed_us / 1000,
        });
    } else if (elapsed_us >= 1000) {
        // >= 1ms, show in milliseconds
        std.log.info("{s} {s} -> {d} ({d}ms)", .{
            method,
            path,
            status,
            elapsed_us / 1000,
        });
    } else {
        // < 1ms, show in microseconds
        std.log.info("{s} {s} -> {d} ({d}µs)", .{
            method,
            path,
            status,
            elapsed_us,
        });
    }
}
