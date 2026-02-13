const std = @import("std");
const flate = std.compress.flate;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

pub const CompressConfig = struct {
    min_size: usize = 256, // skip compression for tiny bodies
};

/// Gzip response compression middleware. Compresses response bodies when the
/// client sends Accept-Encoding: gzip and the body exceeds the minimum size.
pub fn gzipCompress(comptime config: CompressConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            try ctx.next(); // run downstream first

            const body = ctx.response.body orelse return;
            if (body.len < config.min_size) return;

            // Check Accept-Encoding for gzip
            const accept = ctx.request.header("Accept-Encoding") orelse return;
            if (std.mem.indexOf(u8, accept, "gzip") == null) return;

            // Skip if already encoded
            if (ctx.response.headers.get("Content-Encoding") != null) return;

            // Compress: allocate output writer + window buffer
            var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.initCapacity(ctx.allocator, body.len) catch return;
            var window_buf: [flate.max_window_len]u8 = undefined;
            var compressor = flate.Compress.init(
                &aw.writer,
                &window_buf,
                .gzip,
                .default,
            ) catch return;

            // Write body through compressor
            compressor.writer.writeAll(body) catch return;
            compressor.writer.flush() catch return;

            // Get compressed bytes
            const compressed = aw.toOwnedSlice() catch return;

            // Only use if smaller
            if (compressed.len >= body.len) {
                ctx.allocator.free(compressed);
                return;
            }

            // Free old body if owned
            if (ctx.response.body_owned) {
                ctx.allocator.free(@constCast(body));
            }

            ctx.response.body = compressed;
            ctx.response.body_owned = true;
            ctx.response.headers.append(ctx.allocator, "Content-Encoding", "gzip") catch {};
            ctx.response.headers.append(ctx.allocator, "Vary", "Accept-Encoding") catch {};
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "gzipCompress compresses response body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var req: Request = .{};
    try req.headers.append(alloc, "Accept-Encoding", "gzip, deflate");

    const handler = comptime gzipCompress(.{ .min_size = 10 });

    const OkHandler = struct {
        const test_body = "Hello, this is a test body that should be long enough to trigger gzip compression. " ++
            "Repeating content helps compression ratios significantly. We need more text here to ensure " ++
            "that the compressed output is actually smaller than the original. Let's add some more words " ++
            "to make this body well above the minimum size threshold for compression to kick in. " ++
            "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.";

        fn handle(ctx: *Context) anyerror!void {
            ctx.response.status = .ok;
            ctx.response.body = test_body;
            ctx.response.headers.append(ctx.allocator, "Content-Type", "text/plain; charset=utf-8") catch {};
        }
    };

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = alloc,
        .next_handler = &OkHandler.handle,
    };

    try handler(&ctx);

    // Should have Content-Encoding: gzip
    try std.testing.expectEqualStrings("gzip", ctx.response.headers.get("Content-Encoding").?);
    // Should have Vary header
    try std.testing.expect(ctx.response.headers.get("Vary") != null);

    // Verify gzip magic bytes (0x1f, 0x8b)
    const compressed = ctx.response.body.?;
    try std.testing.expect(compressed.len >= 2);
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}

test "gzipCompress skips when no Accept-Encoding" {
    const handler = comptime gzipCompress(.{ .min_size = 10 });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.response.status = .ok;
            ctx.response.body = "This is a response body that is definitely long enough.";
            ctx.response.headers.append(ctx.allocator, "Content-Type", "text/plain; charset=utf-8") catch {};
        }
    };

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

    // Should NOT have Content-Encoding
    try std.testing.expect(ctx.response.headers.get("Content-Encoding") == null);
    // Body should be unchanged
    try std.testing.expectEqualStrings("This is a response body that is definitely long enough.", ctx.response.body.?);
}

test "gzipCompress skips small bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const handler = comptime gzipCompress(.{ .min_size = 256 });

    const OkHandler = struct {
        fn handle(ctx: *Context) anyerror!void {
            ctx.response.status = .ok;
            ctx.response.body = "small";
        }
    };

    var req: Request = .{};
    try req.headers.append(alloc, "Accept-Encoding", "gzip");

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = alloc,
        .next_handler = &OkHandler.handle,
    };

    try handler(&ctx);

    // Should NOT compress — body too small
    try std.testing.expect(ctx.response.headers.get("Content-Encoding") == null);
    try std.testing.expectEqualStrings("small", ctx.response.body.?);
}
