const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;

// ── Bearer Token Auth ─────────────────────────────────────────────────

pub const BearerConfig = struct {
    assign_key: []const u8 = "bearer_token",
    required: bool = false,
};

/// Extracts a Bearer token from the Authorization header and stores it in assigns.
///
/// Try: `curl -H "Authorization: Bearer my-token" http://127.0.0.1:9000/auth/bearer`
pub fn bearerAuth(comptime config: BearerConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (extractBearer(ctx)) |token| {
                ctx.assign(config.assign_key, token);
            } else if (config.required) {
                ctx.respond(.unauthorized, "text/plain; charset=utf-8", "401 Unauthorized");
                ctx.response.headers.append(ctx.allocator, "WWW-Authenticate", "Bearer") catch {};
                return;
            }
            try ctx.next();
        }
    };
    return &S.handle;
}

// ── Basic Auth ────────────────────────────────────────────────────────

pub const BasicAuthConfig = struct {
    username_key: []const u8 = "auth_username",
    password_key: []const u8 = "auth_password",
    required: bool = false,
    realm: []const u8 = "Restricted",
};

/// Extracts Basic credentials from the Authorization header and stores
/// username and password in assigns.
///
/// Try: `curl -u alice:secret http://127.0.0.1:9000/auth/basic`
pub fn basicAuth(comptime config: BasicAuthConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (extractBasicCreds(ctx)) |creds| {
                ctx.assign(config.username_key, creds.username);
                ctx.assign(config.password_key, creds.password);
            } else if (config.required) {
                ctx.respond(.unauthorized, "text/plain; charset=utf-8", "401 Unauthorized");
                const header_val = comptime "Basic realm=\"" ++ config.realm ++ "\"";
                ctx.response.headers.append(ctx.allocator, "WWW-Authenticate", header_val) catch {};
                return;
            }
            try ctx.next();
        }

        const Credentials = struct {
            username: []const u8,
            password: []const u8,
        };

        fn extractBasicCreds(ctx: *Context) ?Credentials {
            const auth = ctx.request.header("Authorization") orelse return null;
            if (auth.len <= 6) return null;
            if (!std.mem.eql(u8, auth[0..6], "Basic ")) return null;
            const encoded = auth[6..];

            // Decode base64
            var decoded_buf: [256]u8 = undefined;
            const decoded_len = decodeBase64(&decoded_buf, encoded) orelse return null;
            const decoded = decoded_buf[0..decoded_len];

            // Split on ':'
            const colon = std.mem.indexOfScalar(u8, decoded, ':') orelse return null;

            // Allocate copies so they outlive this stack frame
            const username = ctx.allocator.dupe(u8, decoded[0..colon]) catch return null;
            const password = ctx.allocator.dupe(u8, decoded[colon + 1 ..]) catch return null;

            return .{ .username = username, .password = password };
        }
    };
    return &S.handle;
}

// ── JWT Auth (HMAC-SHA256) ────────────────────────────────────────────

pub const JwtConfig = struct {
    secret: []const u8,
    assign_key: []const u8 = "jwt_payload",
    required: bool = false,
};

/// Verifies a JWT (HMAC-SHA256) from the Authorization Bearer header.
/// Stores the decoded payload JSON in assigns.
///
/// Try: generate a JWT at jwt.io with your secret, then:
/// `curl -H "Authorization: Bearer <token>" http://127.0.0.1:9000/auth/jwt`
pub fn jwtAuth(comptime config: JwtConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (verifyAndExtract(ctx)) |payload| {
                ctx.assign(config.assign_key, payload);
            } else if (config.required) {
                ctx.respond(.unauthorized, "text/plain; charset=utf-8", "401 Unauthorized");
                ctx.response.headers.append(ctx.allocator, "WWW-Authenticate", "Bearer") catch {};
                return;
            }
            try ctx.next();
        }

        fn verifyAndExtract(ctx: *Context) ?[]const u8 {
            const token = extractBearer(ctx) orelse return null;

            // Split into header.payload.signature
            const first_dot = std.mem.indexOfScalar(u8, token, '.') orelse return null;
            const rest = token[first_dot + 1 ..];
            const second_dot = std.mem.indexOfScalar(u8, rest, '.') orelse return null;

            const payload_b64 = rest[0..second_dot];
            const sig_b64 = rest[second_dot + 1 ..];
            const signed_part = token[0 .. first_dot + 1 + second_dot]; // "header.payload"

            // Decode signature (SHA-256 = 32 bytes)
            var sig_buf: [32]u8 = undefined;
            const sig_len = decodeBase64(&sig_buf, sig_b64) orelse return null;
            if (sig_len != 32) return null;

            // Compute HMAC-SHA256 of signed part
            const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
            var computed: [HmacSha256.mac_length]u8 = undefined;
            HmacSha256.create(&computed, signed_part, config.secret);

            // Constant-time comparison
            if (!constantTimeEql(&computed, sig_buf[0..32])) return null;

            // Decode payload
            var payload_buf: [2048]u8 = undefined;
            const payload_len = decodeBase64(&payload_buf, payload_b64) orelse return null;

            // Allocate a copy so it outlives this stack frame
            return ctx.allocator.dupe(u8, payload_buf[0..payload_len]) catch null;
        }
    };
    return &S.handle;
}

// ── Helpers ───────────────────────────────────────────────────────────

/// Extract Bearer token from Authorization header.
fn extractBearer(ctx: *const Context) ?[]const u8 {
    const auth = ctx.request.header("Authorization") orelse return null;
    if (auth.len <= 7) return null;
    if (!std.mem.eql(u8, auth[0..7], "Bearer ")) return null;
    return auth[7..];
}

/// Constant-time byte comparison (prevents timing attacks).
fn constantTimeEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |x, y| {
        diff |= x ^ y;
    }
    return diff == 0;
}

/// Decode base64 (standard or URL-safe, with or without padding).
/// Returns number of decoded bytes, or null on error.
pub fn decodeBase64(dest: []u8, source: []const u8) ?usize {
    if (source.len == 0) return 0;

    var di: usize = 0;
    var accum: u32 = 0;
    var bits: u5 = 0;

    for (source) |ch| {
        if (ch == '=' or ch == '\n' or ch == '\r' or ch == ' ') continue;
        const val = b64val(ch) orelse return null;
        accum = (accum << 6) | val;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (di >= dest.len) return null;
            dest[di] = @truncate(accum >> bits);
            di += 1;
        }
    }
    return di;
}

fn b64val(ch: u8) ?u32 {
    if (ch >= 'A' and ch <= 'Z') return ch - 'A';
    if (ch >= 'a' and ch <= 'z') return ch - 'a' + 26;
    if (ch >= '0' and ch <= '9') return ch - '0' + 52;
    if (ch == '+' or ch == '-') return 62; // '+' standard, '-' URL-safe
    if (ch == '/' or ch == '_') return 63; // '/' standard, '_' URL-safe
    return null;
}

// ── Tests ─────────────────────────────────────────────────────────────

const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;
const Router = @import("../router/router.zig").Router;
const RouteDef = @import("../router/router.zig").RouteDef;

test "bearerAuth extracts Bearer token" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const token = ctx.getAssign("bearer_token") orelse "none";
            ctx.text(.ok, token);
        }
    };
    const App = Router.define(.{
        .middleware = &.{bearerAuth(.{})},
        .routes = &.{Router.get("/", H.handle)},
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var req: Request = .{ .method = .GET, .path = "/" };
    try req.headers.append(alloc, "Authorization", "Bearer my-secret-token");
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("my-secret-token", resp.body.?);
}

test "bearerAuth returns 401 when required and missing" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "should not reach");
        }
    };
    const App = Router.define(.{
        .middleware = &.{bearerAuth(.{ .required = true })},
        .routes = &.{Router.get("/", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/" };
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.unauthorized, resp.status);
    try std.testing.expect(resp.headers.get("WWW-Authenticate") != null);
}

test "bearerAuth passes through when optional and missing" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const token = ctx.getAssign("bearer_token") orelse "none";
            ctx.text(.ok, token);
        }
    };
    const App = Router.define(.{
        .middleware = &.{bearerAuth(.{ .required = false })},
        .routes = &.{Router.get("/", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/" };
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("none", resp.body.?);
}

test "basicAuth extracts username and password" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const user = ctx.getAssign("auth_username") orelse "none";
            ctx.text(.ok, user);
        }
    };
    const App = Router.define(.{
        .middleware = &.{basicAuth(.{})},
        .routes = &.{Router.get("/", H.handle)},
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var req: Request = .{ .method = .GET, .path = "/" };
    // "alice:secret" base64 = "YWxpY2U6c2VjcmV0"
    try req.headers.append(alloc, "Authorization", "Basic YWxpY2U6c2VjcmV0");
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    try std.testing.expectEqualStrings("alice", resp.body.?);
}

test "basicAuth returns 401 when required and missing" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "ok");
        }
    };
    const App = Router.define(.{
        .middleware = &.{basicAuth(.{ .required = true })},
        .routes = &.{Router.get("/", H.handle)},
    });

    var req: Request = .{ .method = .GET, .path = "/" };
    defer req.deinit(std.testing.allocator);

    var resp = try App.handler(std.testing.allocator, &req);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(StatusCode.unauthorized, resp.status);
    const www_auth = resp.headers.get("WWW-Authenticate").?;
    try std.testing.expect(std.mem.indexOf(u8, www_auth, "Basic") != null);
}

test "decodeBase64 standard" {
    var buf: [64]u8 = undefined;
    // "hello" = "aGVsbG8="
    const len = decodeBase64(&buf, "aGVsbG8=").?;
    try std.testing.expectEqualStrings("hello", buf[0..len]);
}

test "decodeBase64 URL-safe no padding" {
    var buf: [64]u8 = undefined;
    // "hello world" = "aGVsbG8gd29ybGQ" (URL-safe, no padding)
    const len = decodeBase64(&buf, "aGVsbG8gd29ybGQ").?;
    try std.testing.expectEqualStrings("hello world", buf[0..len]);
}

test "jwtAuth verifies valid HMAC-SHA256 token" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const payload = ctx.getAssign("jwt_payload") orelse "none";
            ctx.text(.ok, payload);
        }
    };
    const secret = "test-secret";
    const App = Router.define(.{
        .middleware = &.{jwtAuth(.{ .secret = secret })},
        .routes = &.{Router.get("/", H.handle)},
    });

    // Build a valid JWT: header.payload.signature
    // Header: {"alg":"HS256","typ":"JWT"} => base64url
    // Payload: {"sub":"1234"} => base64url
    const header_b64 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
    const payload_b64 = "eyJzdWIiOiIxMjM0In0";
    const signed_part = header_b64 ++ "." ++ payload_b64;

    // Compute HMAC-SHA256 signature
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signed_part, secret);

    // base64url-encode the signature (no padding)
    var sig_b64: [64]u8 = undefined;
    const sig_len = encodeBase64Url(&sig_b64, &mac);

    var token_buf: [512]u8 = undefined;
    const token = std.fmt.bufPrint(&token_buf, "{s}.{s}", .{ signed_part, sig_b64[0..sig_len] }) catch unreachable;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var auth_buf: [600]u8 = undefined;
    const auth_header = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{token}) catch unreachable;

    var req: Request = .{ .method = .GET, .path = "/" };
    try req.headers.append(alloc, "Authorization", auth_header);
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.ok, resp.status);
    // Payload should be decoded JSON
    try std.testing.expectEqualStrings("{\"sub\":\"1234\"}", resp.body.?);
}

test "jwtAuth rejects invalid signature" {
    const H = struct {
        fn handle(ctx: *Context) !void {
            const payload = ctx.getAssign("jwt_payload") orelse "none";
            ctx.text(.ok, payload);
        }
    };
    const App = Router.define(.{
        .middleware = &.{jwtAuth(.{ .secret = "correct-secret", .required = true })},
        .routes = &.{Router.get("/", H.handle)},
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Token signed with wrong secret
    const header_b64 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
    const payload_b64 = "eyJzdWIiOiIxMjM0In0";
    const signed_part = header_b64 ++ "." ++ payload_b64;

    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signed_part, "wrong-secret");

    var sig_b64: [64]u8 = undefined;
    const sig_len = encodeBase64Url(&sig_b64, &mac);

    var token_buf: [512]u8 = undefined;
    const token = std.fmt.bufPrint(&token_buf, "{s}.{s}", .{ signed_part, sig_b64[0..sig_len] }) catch unreachable;

    var auth_buf: [600]u8 = undefined;
    const auth_header = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{token}) catch unreachable;

    var req: Request = .{ .method = .GET, .path = "/" };
    try req.headers.append(alloc, "Authorization", auth_header);
    defer req.deinit(alloc);

    var resp = try App.handler(alloc, &req);
    defer resp.deinit(alloc);

    try std.testing.expectEqual(StatusCode.unauthorized, resp.status);
}

/// Base64url-encode (no padding) — test helper only.
fn encodeBase64Url(dest: []u8, source: []const u8) usize {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    var di: usize = 0;
    var i: usize = 0;
    while (i + 3 <= source.len) {
        const b0: u32 = source[i];
        const b1: u32 = source[i + 1];
        const b2: u32 = source[i + 2];
        const triple = (b0 << 16) | (b1 << 8) | b2;
        dest[di] = alphabet[@intCast(triple >> 18)];
        dest[di + 1] = alphabet[@intCast((triple >> 12) & 0x3f)];
        dest[di + 2] = alphabet[@intCast((triple >> 6) & 0x3f)];
        dest[di + 3] = alphabet[@intCast(triple & 0x3f)];
        di += 4;
        i += 3;
    }
    const remaining = source.len - i;
    if (remaining == 1) {
        const b0: u32 = source[i];
        dest[di] = alphabet[@intCast(b0 >> 2)];
        dest[di + 1] = alphabet[@intCast((b0 & 0x3) << 4)];
        di += 2;
    } else if (remaining == 2) {
        const b0: u32 = source[i];
        const b1: u32 = source[i + 1];
        dest[di] = alphabet[@intCast(b0 >> 2)];
        dest[di + 1] = alphabet[@intCast(((b0 & 0x3) << 4) | (b1 >> 4))];
        dest[di + 2] = alphabet[@intCast((b1 & 0xf) << 2)];
        di += 3;
    }
    return di;
}
