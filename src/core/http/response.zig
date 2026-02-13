const std = @import("std");
const Allocator = std.mem.Allocator;
const StatusCode = @import("status.zig").StatusCode;
const Headers = @import("headers.zig").Headers;

/// HTTP response builder.
pub const Response = struct {
    status: StatusCode = .ok,
    headers: Headers = .{},
    body: ?[]const u8 = null,

    pub fn deinit(self: *Response, allocator: Allocator) void {
        self.headers.deinit(allocator);
    }

    /// Set the response body with content type.
    pub fn setBody(self: *Response, allocator: Allocator, content_type: []const u8, body: []const u8) !void {
        self.body = body;
        try self.headers.append(allocator, "Content-Type", content_type);
    }

    // -- Convenience builders --

    /// Send a plain text response.
    pub fn text(allocator: Allocator, status: StatusCode, body: []const u8) !Response {
        var resp: Response = .{ .status = status };
        try resp.setBody(allocator, "text/plain; charset=utf-8", body);
        return resp;
    }

    /// Send an HTML response.
    pub fn html(allocator: Allocator, status: StatusCode, body: []const u8) !Response {
        var resp: Response = .{ .status = status };
        try resp.setBody(allocator, "text/html; charset=utf-8", body);
        return resp;
    }

    /// Send a JSON response.
    pub fn json(allocator: Allocator, status: StatusCode, body: []const u8) !Response {
        var resp: Response = .{ .status = status };
        try resp.setBody(allocator, "application/json; charset=utf-8", body);
        return resp;
    }

    /// Send a redirect response.
    pub fn redirect(allocator: Allocator, location: []const u8, permanent: bool) !Response {
        var resp: Response = .{
            .status = if (permanent) .moved_permanently else .found,
        };
        try resp.headers.append(allocator, "Location", location);
        return resp;
    }

    /// Send an empty response with just a status code.
    pub fn empty(status: StatusCode) Response {
        return .{ .status = status };
    }

    // -- Serialization --

    /// Serialize the full HTTP response to a byte slice (allocates).
    pub fn serialize(self: *const Response, allocator: Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        // Status line
        try buf.appendSlice(allocator, "HTTP/1.1 ");
        try appendInt(&buf, allocator, self.status.code());
        try buf.appendSlice(allocator, " ");
        try buf.appendSlice(allocator, self.status.phrase());
        try buf.appendSlice(allocator, "\r\n");

        // Content-Length header
        if (self.body) |body| {
            try buf.appendSlice(allocator, "Content-Length: ");
            try appendInt(&buf, allocator, body.len);
            try buf.appendSlice(allocator, "\r\n");
        } else {
            try buf.appendSlice(allocator, "Content-Length: 0\r\n");
        }

        // Server header
        try buf.appendSlice(allocator, "Server: Zzz/0.1.0\r\n");

        // User headers
        for (self.headers.entries.items) |entry| {
            try buf.appendSlice(allocator, entry.name);
            try buf.appendSlice(allocator, ": ");
            try buf.appendSlice(allocator, entry.value);
            try buf.appendSlice(allocator, "\r\n");
        }

        // End of headers
        try buf.appendSlice(allocator, "\r\n");

        // Body
        if (self.body) |body| {
            try buf.appendSlice(allocator, body);
        }

        return buf.toOwnedSlice(allocator);
    }
};

fn appendInt(buf: *std.ArrayList(u8), allocator: Allocator, value: anytype) !void {
    var tmp: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch return;
    try buf.appendSlice(allocator, result);
}

test "response text" {
    const testing = std.testing;
    var resp = try Response.text(testing.allocator, .ok, "Hello, World!");
    defer resp.deinit(testing.allocator);

    try testing.expectEqual(StatusCode.ok, resp.status);
    try testing.expectEqualStrings("Hello, World!", resp.body.?);
    try testing.expectEqualStrings("text/plain; charset=utf-8", resp.headers.get("Content-Type").?);
}

test "response serialization" {
    const testing = std.testing;
    var resp = try Response.text(testing.allocator, .ok, "Hi");
    defer resp.deinit(testing.allocator);

    const bytes = try resp.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    try testing.expect(std.mem.indexOf(u8, bytes, "HTTP/1.1 200 OK\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "Content-Length: 2\r\n") != null);
    try testing.expect(std.mem.endsWith(u8, bytes, "Hi"));
}
