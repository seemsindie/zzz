const std = @import("std");
const Allocator = std.mem.Allocator;
const Request = @import("request.zig").Request;
const Method = @import("request.zig").Method;

pub const ParseError = error{
    InvalidMethod,
    InvalidRequestLine,
    InvalidHeader,
    InvalidVersion,
    HeadersTooLarge,
    UriTooLong,
    Incomplete,
    OutOfMemory,
};

pub const max_header_size = 8192;
pub const max_uri_length = 4096;
pub const max_headers_count = 100;

/// Parse an HTTP/1.1 request from a byte buffer.
/// Returns the parsed Request and the number of bytes consumed (header section + \r\n\r\n).
/// The body is NOT consumed here - the caller reads it separately based on Content-Length.
pub fn parse(allocator: Allocator, buf: []const u8) ParseError!struct { request: Request, bytes_consumed: usize } {
    // Find end of headers (\r\n\r\n). Include up to the second \r\n so all header lines are parseable.
    const header_end = findHeaderEnd(buf) orelse return error.Incomplete;
    const header_section = buf[0 .. header_end + 2]; // include one trailing \r\n

    // Parse request line
    const first_line_end = std.mem.indexOfScalar(u8, header_section, '\r') orelse return error.InvalidRequestLine;
    const request_line = header_section[0..first_line_end];

    // Method SP URI SP Version
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method_str = parts.next() orelse return error.InvalidRequestLine;
    const uri = parts.next() orelse return error.InvalidRequestLine;
    const version_str = parts.next() orelse return error.InvalidRequestLine;

    if (uri.len > max_uri_length) return error.UriTooLong;

    const method = Method.fromString(method_str) catch return error.InvalidMethod;
    const version: Request.Version = if (std.mem.eql(u8, version_str, "HTTP/1.1"))
        .http_1_1
    else if (std.mem.eql(u8, version_str, "HTTP/1.0"))
        .http_1_0
    else
        return error.InvalidVersion;

    // Split path and query string
    var path: []const u8 = uri;
    var query_string: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, uri, '?')) |qi| {
        path = uri[0..qi];
        query_string = uri[qi + 1 ..];
    }

    var req: Request = .{
        .method = method,
        .path = path,
        .query_string = query_string,
        .version = version,
        .raw_uri = uri,
    };

    // Headers start after first \r\n
    const headers_start = first_line_end + 2; // skip \r\n
    var header_data = header_section[headers_start..];
    var header_count: usize = 0;

    while (header_data.len > 0) {
        const line_end = std.mem.indexOf(u8, header_data, "\r\n") orelse break;
        const line = header_data[0..line_end];
        if (line.len == 0) break; // empty line = end of headers

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
            req.deinit(allocator);
            return error.InvalidHeader;
        };

        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        req.headers.append(allocator, name, value) catch {
            req.deinit(allocator);
            return error.OutOfMemory;
        };

        header_count += 1;
        if (header_count > max_headers_count) {
            req.deinit(allocator);
            return error.HeadersTooLarge;
        }

        header_data = header_data[line_end + 2 ..];
    }

    // bytes_consumed includes the trailing \r\n\r\n
    return .{
        .request = req,
        .bytes_consumed = header_end + 4,
    };
}

/// Find the position of the \r\n\r\n separator (returns index of first \r).
fn findHeaderEnd(buf: []const u8) ?usize {
    return std.mem.indexOf(u8, buf, "\r\n\r\n");
}

test "parse simple GET request" {
    const testing = std.testing;
    const raw =
        "GET /hello?name=world HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "User-Agent: test\r\n" ++
        "Accept: */*\r\n" ++
        "\r\n";

    const result = try parse(testing.allocator, raw);
    var req = result.request;
    defer req.deinit(testing.allocator);

    try testing.expectEqual(Method.GET, req.method);
    try testing.expectEqualStrings("/hello", req.path);
    try testing.expectEqualStrings("name=world", req.query_string.?);
    try testing.expectEqual(Request.Version.http_1_1, req.version);
    try testing.expectEqualStrings("localhost:8080", req.header("Host").?);
    try testing.expectEqualStrings("test", req.header("User-Agent").?);
    try testing.expectEqual(raw.len, result.bytes_consumed);
}

test "parse POST request" {
    const testing = std.testing;
    const raw =
        "POST /users HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 27\r\n" ++
        "\r\n";

    const result = try parse(testing.allocator, raw);
    var req = result.request;
    defer req.deinit(testing.allocator);

    try testing.expectEqual(Method.POST, req.method);
    try testing.expectEqualStrings("/users", req.path);
    try testing.expect(req.query_string == null);
    try testing.expectEqual(@as(?usize, 27), req.contentLength());
}

test "parse incomplete request" {
    const raw = "GET /hello HTTP/1.1\r\nHost: loc";
    try std.testing.expectError(error.Incomplete, parse(std.testing.allocator, raw));
}
