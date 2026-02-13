/// HTTP status codes and reason phrases.
pub const StatusCode = enum(u16) {
    // 1xx Informational
    @"continue" = 100,
    switching_protocols = 101,

    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    reset_content = 205,
    partial_content = 206,

    // 3xx Redirection
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    temporary_redirect = 307,
    permanent_redirect = 308,

    // 4xx Client Errors
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    request_timeout = 408,
    conflict = 409,
    gone = 410,
    length_required = 411,
    payload_too_large = 413,
    uri_too_long = 414,
    unsupported_media_type = 415,
    too_many_requests = 429,
    request_header_fields_too_large = 431,

    // 5xx Server Errors
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,

    _,

    pub fn phrase(self: StatusCode) []const u8 {
        return switch (self) {
            .@"continue" => "Continue",
            .switching_protocols => "Switching Protocols",
            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .no_content => "No Content",
            .reset_content => "Reset Content",
            .partial_content => "Partial Content",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .see_other => "See Other",
            .not_modified => "Not Modified",
            .temporary_redirect => "Temporary Redirect",
            .permanent_redirect => "Permanent Redirect",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .not_acceptable => "Not Acceptable",
            .request_timeout => "Request Timeout",
            .conflict => "Conflict",
            .gone => "Gone",
            .length_required => "Length Required",
            .payload_too_large => "Payload Too Large",
            .uri_too_long => "URI Too Long",
            .unsupported_media_type => "Unsupported Media Type",
            .too_many_requests => "Too Many Requests",
            .request_header_fields_too_large => "Request Header Fields Too Large",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
            .gateway_timeout => "Gateway Timeout",
            _ => "Unknown",
        };
    }

    pub fn code(self: StatusCode) u16 {
        return @intFromEnum(self);
    }
};

test "status code phrases" {
    const std = @import("std");
    try std.testing.expectEqualStrings("OK", StatusCode.ok.phrase());
    try std.testing.expectEqual(@as(u16, 200), StatusCode.ok.code());
    try std.testing.expectEqualStrings("Not Found", StatusCode.not_found.phrase());
    try std.testing.expectEqual(@as(u16, 404), StatusCode.not_found.code());
}
