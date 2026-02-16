const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = @import("../core/http/request.zig").Method;
const TestResponse = @import("response.zig").TestResponse;
const multipart = @import("multipart.zig");
const MultipartPart = multipart.MultipartPart;

/// Builder for constructing complex test requests with a chainable API.
/// Created via `TestClient.request()`.
pub fn RequestBuilder(comptime App: type) type {
    const Client = @import("client.zig").TestClient(App);
    const HeaderEntry = Client.HeaderEntry;

    return struct {
        const Self = @This();

        client: *Client,
        method: Method,
        path: []const u8,
        query_string: ?[]const u8 = null,
        body: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        extra_headers: [8]HeaderEntry = undefined,
        extra_headers_len: usize = 0,
        // Holds multipart body if built
        owned_body: ?[]const u8 = null,

        /// Add a custom header to this request.
        pub fn header(self: *Self, name: []const u8, value: []const u8) *Self {
            if (self.extra_headers_len < 8) {
                self.extra_headers[self.extra_headers_len] = .{ .name = name, .value = value };
                self.extra_headers_len += 1;
            }
            return self;
        }

        /// Set a JSON body with application/json content type.
        pub fn jsonBody(self: *Self, json: []const u8) *Self {
            self.body = json;
            self.content_type = "application/json";
            return self;
        }

        /// Set a URL-encoded form body with application/x-www-form-urlencoded content type.
        pub fn formBody(self: *Self, form: []const u8) *Self {
            self.body = form;
            self.content_type = "application/x-www-form-urlencoded";
            return self;
        }

        /// Set a plain text body with text/plain content type.
        pub fn textBody(self: *Self, text: []const u8) *Self {
            self.body = text;
            self.content_type = "text/plain";
            return self;
        }

        /// Build and set a multipart/form-data body from parts.
        pub fn multipartBody(self: *Self, allocator: Allocator, parts: []const MultipartPart) *Self {
            const result = multipart.buildMultipartBody(allocator, parts) catch return self;
            self.body = result.body;
            self.owned_body = result.body;
            self.content_type = result.content_type;
            return self;
        }

        /// Set a query string (without the leading ?).
        pub fn query(self: *Self, qs: []const u8) *Self {
            self.query_string = qs;
            return self;
        }

        /// Send the request and return the response.
        pub fn send(self: *Self) !TestResponse {
            defer {
                if (self.owned_body) |ob| {
                    self.client.arena.allocator().free(@constCast(ob));
                }
            }
            return self.client.dispatch(
                self.method,
                self.path,
                self.query_string,
                self.body,
                self.content_type,
                self.extra_headers[0..self.extra_headers_len],
            );
        }
    };
}
