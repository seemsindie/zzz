const std = @import("std");
const c = std.c;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;
const StatusCode = @import("../core/http/status.zig").StatusCode;

/// Static file serving configuration.
pub const StaticConfig = struct {
    /// Directory to serve files from (relative to cwd).
    dir: []const u8 = "public",
    /// URL prefix to match. Requests starting with this prefix will be
    /// served from the directory. E.g. "/static" serves /static/css/app.css
    /// from <dir>/css/app.css.
    prefix: []const u8 = "/static",
    /// Cache-Control max-age in seconds.
    max_age: []const u8 = "3600",
};

/// Create a static file serving middleware.
pub fn staticFiles(comptime config: StaticConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            const path = ctx.request.path;

            // Check if the request path starts with the configured prefix
            if (!std.mem.startsWith(u8, path, config.prefix)) {
                return ctx.next();
            }

            // Extract the file path after the prefix
            var file_path = path[config.prefix.len..];
            if (file_path.len > 0 and file_path[0] == '/') {
                file_path = file_path[1..];
            }
            if (file_path.len == 0) {
                return ctx.next();
            }

            // Security: reject paths with ".." to prevent directory traversal
            if (containsDotDot(file_path)) {
                ctx.respond(.forbidden, "text/plain; charset=utf-8", "403 Forbidden");
                return;
            }

            // Try to open and serve the file
            if (readFile(ctx.allocator, config.dir, file_path)) |result| {
                const content_type = mimeFromPath(file_path);
                ctx.response.status = .ok;
                ctx.response.body = result.data;
                ctx.response.body_owned = true;
                ctx.response.headers.append(ctx.allocator, "Content-Type", content_type) catch {};
                ctx.response.headers.append(ctx.allocator, "Cache-Control", "public, max-age=" ++ config.max_age) catch {};

                // ETag from file size
                if (result.etag) |etag| {
                    ctx.response.trackOwnedSlice(ctx.allocator, etag);
                    ctx.response.headers.append(ctx.allocator, "ETag", etag) catch {};

                    // Check If-None-Match for 304
                    if (ctx.request.header("If-None-Match")) |client_etag| {
                        if (std.mem.eql(u8, client_etag, etag)) {
                            // Free the body we just read — client has it cached
                            ctx.allocator.free(@constCast(result.data));
                            ctx.response.body = null;
                            ctx.response.body_owned = false;
                            ctx.response.status = .not_modified;
                            return;
                        }
                    }
                }
            } else {
                // File not found — fall through to router
                return ctx.next();
            }
        }
    };
    return &S.handle;
}

const ReadResult = struct {
    data: []const u8,
    etag: ?[]const u8, // heap-allocated via the same allocator
};

/// Read a file using C APIs (no Io required).
fn readFile(allocator: std.mem.Allocator, comptime base_dir: []const u8, rel_path: []const u8) ?ReadResult {
    // Open the base directory (comptime string literal is null-terminated)
    const dir_z: [*:0]const u8 = @ptrCast(base_dir.ptr);
    const dir_fd = c.open(dir_z, .{ .DIRECTORY = true }, @as(c.mode_t, 0));
    if (dir_fd < 0) return null;
    defer _ = c.close(dir_fd);

    // Create null-terminated copy of the runtime rel_path
    const path_buf = allocator.allocSentinel(u8, rel_path.len, 0) catch return null;
    defer allocator.free(path_buf);
    @memcpy(path_buf, rel_path);

    const fd = c.openat(dir_fd, path_buf.ptr, .{}, @as(c.mode_t, 0));
    if (fd < 0) return null;
    defer _ = c.close(fd);

    // Get file size
    var stat_buf: c.Stat = undefined;
    if (c.fstat(fd, &stat_buf) != 0) return null;
    const size: usize = @intCast(stat_buf.size);

    // Don't serve directories or empty files
    if (size == 0) return null;

    // Cap at 10MB
    if (size > 10 * 1024 * 1024) return null;

    // Allocate and read
    const buf = allocator.alloc(u8, size) catch return null;
    var total: usize = 0;
    while (total < size) {
        const n = c.read(fd, buf[total..].ptr, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }

    if (total != size) {
        allocator.free(buf);
        return null;
    }

    // Build a simple ETag from file size (heap-allocated so it outlives this function)
    const etag_str = std.fmt.allocPrint(allocator, "\"{d}\"", .{size}) catch null;

    return .{
        .data = buf,
        .etag = etag_str,
    };
}

/// Check if a path contains ".." segments (directory traversal).
pub fn containsDotDot(path: []const u8) bool {
    var i: usize = 0;
    while (i < path.len) {
        if (i + 1 < path.len and path[i] == '.' and path[i + 1] == '.') {
            // Check it's a real ".." segment (bounded by / or start/end)
            const before_ok = (i == 0) or (path[i - 1] == '/');
            const after_ok = (i + 2 >= path.len) or (path[i + 2] == '/');
            if (before_ok and after_ok) return true;
        }
        i += 1;
    }
    return false;
}

/// Map a file extension to a MIME content type.
pub fn mimeFromPath(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);

    // Text
    if (eql(ext, ".html") or eql(ext, ".htm")) return "text/html; charset=utf-8";
    if (eql(ext, ".css")) return "text/css; charset=utf-8";
    if (eql(ext, ".js") or eql(ext, ".mjs")) return "application/javascript; charset=utf-8";
    if (eql(ext, ".json")) return "application/json; charset=utf-8";
    if (eql(ext, ".xml")) return "application/xml; charset=utf-8";
    if (eql(ext, ".txt")) return "text/plain; charset=utf-8";
    if (eql(ext, ".csv")) return "text/csv; charset=utf-8";
    if (eql(ext, ".md")) return "text/markdown; charset=utf-8";

    // Images
    if (eql(ext, ".png")) return "image/png";
    if (eql(ext, ".jpg") or eql(ext, ".jpeg")) return "image/jpeg";
    if (eql(ext, ".gif")) return "image/gif";
    if (eql(ext, ".svg")) return "image/svg+xml";
    if (eql(ext, ".ico")) return "image/x-icon";
    if (eql(ext, ".webp")) return "image/webp";
    if (eql(ext, ".avif")) return "image/avif";

    // Fonts
    if (eql(ext, ".woff")) return "font/woff";
    if (eql(ext, ".woff2")) return "font/woff2";
    if (eql(ext, ".ttf")) return "font/ttf";
    if (eql(ext, ".otf")) return "font/otf";

    // Media
    if (eql(ext, ".mp3")) return "audio/mpeg";
    if (eql(ext, ".mp4")) return "video/mp4";
    if (eql(ext, ".webm")) return "video/webm";
    if (eql(ext, ".ogg")) return "audio/ogg";

    // Archives / misc
    if (eql(ext, ".pdf")) return "application/pdf";
    if (eql(ext, ".zip")) return "application/zip";
    if (eql(ext, ".gz")) return "application/gzip";
    if (eql(ext, ".wasm")) return "application/wasm";
    if (eql(ext, ".map")) return "application/json";

    return "application/octet-stream";
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "containsDotDot" {
    try std.testing.expect(containsDotDot("../etc/passwd"));
    try std.testing.expect(containsDotDot("foo/../../etc"));
    try std.testing.expect(containsDotDot(".."));
    try std.testing.expect(!containsDotDot("css/style.css"));
    try std.testing.expect(!containsDotDot("some..file.txt"));
    try std.testing.expect(!containsDotDot("foo/bar/baz"));
}

test "mimeFromPath" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", mimeFromPath("index.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", mimeFromPath("style.css"));
    try std.testing.expectEqualStrings("application/javascript; charset=utf-8", mimeFromPath("app.js"));
    try std.testing.expectEqualStrings("image/png", mimeFromPath("logo.png"));
    try std.testing.expectEqualStrings("application/octet-stream", mimeFromPath("data.bin"));
}
