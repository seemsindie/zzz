const std = @import("std");
const native_os = @import("builtin").os.tag;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

pub const RateLimitConfig = struct {
    max_requests: u32 = 60,
    window_seconds: u32 = 60,
    key_header: []const u8 = "X-Forwarded-For",
};

/// Rate limiting middleware using a token bucket per client key.
/// Clients are identified by the configured header (default: X-Forwarded-For).
pub fn rateLimit(comptime config: RateLimitConfig) HandlerFn {
    const S = struct {
        const max_clients = 256;

        const Bucket = struct {
            key: [64]u8 = .{0} ** 64,
            key_len: usize = 0,
            tokens: u32 = config.max_requests,
            last_refill_ns: i128 = 0,
        };

        var buckets: [max_clients]Bucket = [_]Bucket{.{}} ** max_clients;
        var bucket_len: usize = 0;

        fn findBucket(key: []const u8) ?*Bucket {
            const clamped = @min(key.len, 64);
            for (buckets[0..bucket_len]) |*b| {
                if (b.key_len == clamped and std.mem.eql(u8, b.key[0..b.key_len], key[0..clamped])) {
                    return b;
                }
            }
            return null;
        }

        fn createBucket(key: []const u8) ?*Bucket {
            if (bucket_len >= max_clients) return null;
            const b = &buckets[bucket_len];
            const clamped = @min(key.len, 64);
            @memcpy(b.key[0..clamped], key[0..clamped]);
            b.key_len = clamped;
            b.tokens = config.max_requests;
            b.last_refill_ns = getMonotonicNs();
            bucket_len += 1;
            return b;
        }

        fn refillTokens(bucket: *Bucket) void {
            const now = getMonotonicNs();
            const elapsed_ns = now - bucket.last_refill_ns;
            const window_ns: i128 = @as(i128, config.window_seconds) * std.time.ns_per_s;

            if (elapsed_ns >= window_ns) {
                // Full window elapsed — refill all tokens
                bucket.tokens = config.max_requests;
                bucket.last_refill_ns = now;
            }
        }

        const window_seconds_str = blk: {
            const buf = std.fmt.comptimePrint("{d}", .{config.window_seconds});
            break :blk buf;
        };

        fn handle(ctx: *Context) anyerror!void {
            const key = ctx.request.header(config.key_header) orelse "unknown";

            var bucket = findBucket(key) orelse createBucket(key) orelse {
                try ctx.next();
                return; // store full, allow through
            };

            refillTokens(bucket);

            if (bucket.tokens > 0) {
                bucket.tokens -= 1;
                try ctx.next();
            } else {
                ctx.respond(.too_many_requests, "text/plain; charset=utf-8", "429 Too Many Requests");
                ctx.response.headers.append(ctx.allocator, "Retry-After", window_seconds_str) catch {};
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

test "rateLimit allows requests within limit" {
    // Each comptime config generates its own static buckets, so this test
    // gets an isolated set of buckets that starts empty.
    const handler = comptime rateLimit(.{ .max_requests = 2, .window_seconds = 60, .key_header = "X-Test-Key" });

    var req: Request = .{};
    defer req.deinit(std.testing.allocator);
    try req.headers.append(std.testing.allocator, "X-Test-Key", "test-client-rl");

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.respond(.ok, "text/plain; charset=utf-8", "ok");
        }
    };

    // First request — should pass
    {
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

    // Second request — should pass
    {
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

    // Third request — should be rate limited
    {
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
        try std.testing.expectEqual(StatusCode.too_many_requests, ctx.response.status);
        try std.testing.expectEqualStrings("429 Too Many Requests", ctx.response.body.?);
        try std.testing.expect(ctx.response.headers.get("Retry-After") != null);
    }
}
