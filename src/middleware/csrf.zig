const std = @import("std");
const native_os = @import("builtin").os.tag;
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

/// CSRF protection middleware configuration.
pub const CsrfConfig = struct {
    /// Form field name to look for the CSRF token.
    token_field: []const u8 = "_csrf_token",
    /// HTTP header name to look for the CSRF token.
    header_name: []const u8 = "X-CSRF-Token",
    /// Key used to store/retrieve the CSRF token in session assigns.
    session_key: []const u8 = "csrf_token",
};

/// Create a CSRF protection middleware with the given config.
///
/// Must be placed *after* the session middleware in the pipeline so that
/// assigns are populated from the session store.
///
/// For safe methods (GET, HEAD, OPTIONS), the token is generated if missing
/// and stored in assigns for use in templates/responses.
///
/// For unsafe methods (POST, PUT, PATCH, DELETE), the token is validated
/// against the form field or header. Returns 403 Forbidden on mismatch.
pub fn csrf(comptime config: CsrfConfig) HandlerFn {
    const S = struct {
        var csprng: std.Random.DefaultCsprng = initCsprng();
        var seeded: bool = false;

        fn initCsprng() std.Random.DefaultCsprng {
            return std.Random.DefaultCsprng.init(.{0} ** std.Random.DefaultCsprng.secret_seed_length);
        }

        fn ensureSeeded() void {
            if (seeded) return;
            var seed: [std.Random.DefaultCsprng.secret_seed_length]u8 = undefined;
            fillEntropy(&seed);
            csprng = std.Random.DefaultCsprng.init(seed);
            seeded = true;
        }

        fn fillEntropy(buf: []u8) void {
            switch (native_os) {
                .macos, .ios, .tvos, .watchos, .visionos, .driverkit => {
                    std.c.arc4random_buf(buf.ptr, buf.len);
                },
                .linux => {
                    const linux = std.os.linux;
                    _ = linux.getrandom(buf.ptr, buf.len, 0);
                },
                else => {
                    const c = std.c;
                    var ts: c.timespec = undefined;
                    _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
                    const nanos: u64 = @intCast(@as(i128, ts.sec) * std.time.ns_per_s + ts.nsec);
                    const bytes = std.mem.asBytes(&nanos);
                    var i: usize = 0;
                    while (i < buf.len) : (i += 1) {
                        buf[i] = bytes[i % bytes.len] +% @as(u8, @truncate(i));
                    }
                },
            }
        }

        fn generateToken() [32]u8 {
            ensureSeeded();
            var raw: [16]u8 = undefined;
            csprng.fill(&raw);
            return std.fmt.bytesToHex(raw, .lower);
        }

        fn isSafeMethod(ctx: *const Context) bool {
            return switch (ctx.request.method) {
                .GET, .HEAD, .OPTIONS => true,
                else => false,
            };
        }

        fn handle(ctx: *Context) anyerror!void {
            // Get existing token from assigns (loaded by session middleware)
            var token = ctx.getAssign(config.session_key);

            if (token == null) {
                // Generate a new token and store in assigns
                const new_token = generateToken();
                // Allocate so it outlives this stack frame
                const token_str = ctx.allocator.dupe(u8, &new_token) catch {
                    try ctx.next();
                    return;
                };
                ctx.response.trackOwnedSlice(ctx.allocator, token_str);
                ctx.assign(config.session_key, token_str);
                token = token_str;
            }

            // For safe methods, just continue — token is available in assigns
            if (isSafeMethod(ctx)) {
                try ctx.next();
                return;
            }

            // For unsafe methods, validate the token
            const expected = token.?;

            // Check form field first, then header
            const submitted = ctx.formValue(config.token_field) orelse
                ctx.request.header(config.header_name) orelse {
                // No token submitted
                ctx.respond(.forbidden, "text/plain; charset=utf-8", "403 Forbidden - Missing CSRF token");
                return;
            };

            if (!std.mem.eql(u8, submitted, expected)) {
                ctx.respond(.forbidden, "text/plain; charset=utf-8", "403 Forbidden - Invalid CSRF token");
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
const Router = @import("../router/router.zig").Router;
const Response = @import("../core/http/response.zig").Response;
const body_parser = @import("body_parser.zig");

test "CSRF: GET request passes and gets token in assigns" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const token = ctx.getAssign("csrf_token") orelse "missing";
            ctx.text(.ok, token);
        }
    };
    const App = Router.define(.{
        .middleware = &.{csrf(.{})},
        .routes = &.{
            Router.get("/", H.handle),
        },
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var req: Request = .{ .method = .GET, .path = "/" };
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    // Token should be a 32-char hex string
    try std.testing.expectEqual(@as(usize, 32), resp.body.?.len);
}

test "CSRF: POST without token returns 403" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "success");
        }
    };
    const App = Router.define(.{
        .middleware = &.{csrf(.{})},
        .routes = &.{
            Router.post("/submit", H.handle),
        },
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var req: Request = .{ .method = .POST, .path = "/submit" };
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.forbidden, resp.status);
}

test "CSRF: POST with valid token via header passes" {
    // We need to first get a token, then use it in a POST.
    // Since CSRF stores tokens in assigns, and without session middleware
    // the token is generated fresh each request, we need to pre-populate assigns.
    // For this test, we use the header approach.

    const H = struct {
        fn get(ctx: *Context) !void {
            const token = ctx.getAssign("csrf_token") orelse "missing";
            ctx.text(.ok, token);
        }
        fn post(ctx: *Context) !void {
            ctx.text(.ok, "success");
        }
    };

    // Use session middleware to persist the CSRF token between requests
    const sess = @import("session.zig");
    const App = Router.define(.{
        .middleware = &.{
            sess.session(.{ .cookie_name = "csrf_test_sess" }),
            csrf(.{}),
        },
        .routes = &.{
            Router.get("/form", H.get),
            Router.post("/submit", H.post),
        },
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Step 1: GET to obtain token and session cookie
    var req1: Request = .{ .method = .GET, .path = "/form" };
    defer req1.deinit(alloc);
    var resp1 = try App.handler(alloc, &req1);
    defer resp1.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp1.status);
    const token = resp1.body.?;
    try std.testing.expectEqual(@as(usize, 32), token.len);

    // Extract session cookie
    const cookie_hdr = resp1.headers.get("Set-Cookie").?;
    const prefix = "csrf_test_sess=";
    try std.testing.expect(std.mem.startsWith(u8, cookie_hdr, prefix));
    const after_eq = cookie_hdr[prefix.len..];
    const semi = std.mem.indexOfScalar(u8, after_eq, ';') orelse after_eq.len;
    const sid = after_eq[0..semi];

    // Step 2: POST with session cookie and CSRF token in header
    var req2: Request = .{ .method = .POST, .path = "/submit" };
    var cookie_buf: [64]u8 = undefined;
    const cookie_val = std.fmt.bufPrint(&cookie_buf, "csrf_test_sess={s}", .{sid}) catch unreachable;
    try req2.headers.append(alloc, "Cookie", cookie_val);
    try req2.headers.append(alloc, "X-CSRF-Token", token);
    defer req2.deinit(alloc);
    var resp2 = try App.handler(alloc, &req2);
    defer resp2.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp2.status);
    try std.testing.expectEqualStrings("success", resp2.body.?);
}

test "CSRF: POST with invalid token returns 403" {
    const sess = @import("session.zig");
    const H = struct {
        fn get(ctx: *Context) !void {
            ctx.text(.ok, "form");
        }
        fn post(ctx: *Context) !void {
            ctx.text(.ok, "success");
        }
    };
    const App = Router.define(.{
        .middleware = &.{
            sess.session(.{ .cookie_name = "csrf_bad_sess" }),
            csrf(.{}),
        },
        .routes = &.{
            Router.get("/form", H.get),
            Router.post("/submit", H.post),
        },
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Step 1: GET to obtain session
    var req1: Request = .{ .method = .GET, .path = "/form" };
    defer req1.deinit(alloc);
    var resp1 = try App.handler(alloc, &req1);
    defer resp1.deinit(alloc);

    // Extract session cookie
    const cookie_hdr = resp1.headers.get("Set-Cookie").?;
    const prefix = "csrf_bad_sess=";
    const after_eq = cookie_hdr[prefix.len..];
    const semi = std.mem.indexOfScalar(u8, after_eq, ';') orelse after_eq.len;
    const sid = after_eq[0..semi];

    // Step 2: POST with wrong token
    var req2: Request = .{ .method = .POST, .path = "/submit" };
    var cookie_buf: [64]u8 = undefined;
    const cookie_val = std.fmt.bufPrint(&cookie_buf, "csrf_bad_sess={s}", .{sid}) catch unreachable;
    try req2.headers.append(alloc, "Cookie", cookie_val);
    try req2.headers.append(alloc, "X-CSRF-Token", "00000000000000000000000000000000");
    defer req2.deinit(alloc);
    var resp2 = try App.handler(alloc, &req2);
    defer resp2.deinit(alloc);

    try std.testing.expectEqual(StatusCode.forbidden, resp2.status);
}
