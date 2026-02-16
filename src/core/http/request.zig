const std = @import("std");
const Allocator = std.mem.Allocator;
const Headers = @import("headers.zig").Headers;

/// HTTP request methods.
pub const Method = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    CONNECT,
    TRACE,

    pub fn fromString(s: []const u8) !Method {
        if (std.mem.eql(u8, s, "GET")) return .GET;
        if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, s, "POST")) return .POST;
        if (std.mem.eql(u8, s, "PUT")) return .PUT;
        if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
        if (std.mem.eql(u8, s, "CONNECT")) return .CONNECT;
        if (std.mem.eql(u8, s, "TRACE")) return .TRACE;
        return error.InvalidMethod;
    }

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .HEAD => "HEAD",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .OPTIONS => "OPTIONS",
            .CONNECT => "CONNECT",
            .TRACE => "TRACE",
        };
    }
};

/// Parsed HTTP request. Holds slices into the read buffer (zero-copy for headers/path)
/// and optionally allocates for the body.
pub const Request = struct {
    method: Method = .GET,
    path: []const u8 = "/",
    query_string: ?[]const u8 = null,
    version: Version = .http_1_1,
    headers: Headers = .{},
    body: ?[]const u8 = null,
    raw_uri: []const u8 = "/",

    pub const Version = enum {
        http_1_0,
        http_1_1,

        pub fn toString(self: Version) []const u8 {
            return switch (self) {
                .http_1_0 => "HTTP/1.0",
                .http_1_1 => "HTTP/1.1",
            };
        }
    };

    pub fn deinit(self: *Request, allocator: Allocator) void {
        self.headers.deinit(allocator);
    }

    /// Get a header value (case-insensitive).
    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Check if connection should be kept alive.
    pub fn keepAlive(self: *const Request) bool {
        if (self.header("Connection")) |conn| {
            if (std.ascii.eqlIgnoreCase(conn, "close")) return false;
            if (std.ascii.eqlIgnoreCase(conn, "keep-alive")) return true;
        }
        // HTTP/1.1 defaults to keep-alive
        return self.version == .http_1_1;
    }

    /// Get Content-Length if present.
    pub fn contentLength(self: *const Request) ?usize {
        const val = self.header("Content-Length") orelse return null;
        return std.fmt.parseInt(usize, val, 10) catch null;
    }

    /// Get Content-Type if present.
    pub fn contentType(self: *const Request) ?[]const u8 {
        return self.header("Content-Type");
    }

    /// Check if Transfer-Encoding includes chunked.
    pub fn isChunked(self: *const Request) bool {
        const te = self.header("Transfer-Encoding") orelse return false;
        return std.mem.indexOf(u8, te, "chunked") != null;
    }

    /// Check if request is a WebSocket upgrade.
    pub fn isWebSocketUpgrade(self: *const Request) bool {
        const upgrade = self.header("Upgrade") orelse return false;
        const connection = self.header("Connection") orelse return false;
        return std.ascii.eqlIgnoreCase(upgrade, "websocket") and
            containsIgnoreCase(connection, "upgrade");
    }
};

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

test "method parsing" {
    try std.testing.expectEqual(Method.GET, try Method.fromString("GET"));
    try std.testing.expectEqual(Method.POST, try Method.fromString("POST"));
    try std.testing.expectError(error.InvalidMethod, Method.fromString("INVALID"));
}

test "request keep alive" {
    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    // HTTP/1.1 defaults to keep-alive
    req.version = .http_1_1;
    try std.testing.expect(req.keepAlive());

    // HTTP/1.0 defaults to close
    req.version = .http_1_0;
    try std.testing.expect(!req.keepAlive());
}
