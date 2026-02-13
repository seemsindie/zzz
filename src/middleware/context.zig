const std = @import("std");
const Allocator = std.mem.Allocator;
const Request = @import("../core/http/request.zig").Request;
const Response = @import("../core/http/response.zig").Response;
const StatusCode = @import("../core/http/status.zig").StatusCode;
const body_parser = @import("body_parser.zig");
const ParsedBody = body_parser.ParsedBody;
const FilePart = body_parser.FilePart;

/// Handler function type for middleware and route handlers.
/// Defined outside Context to avoid dependency loop.
pub const HandlerFn = *const fn (*Context) anyerror!void;

/// Fixed-size key-value store for path parameters (zero-allocation).
pub const Params = struct {
    const max_params = 8;

    entries: [max_params]Entry = undefined,
    len: usize = 0,

    const Entry = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn get(self: *const Params, name: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn put(self: *Params, name: []const u8, value: []const u8) void {
        if (self.len < max_params) {
            self.entries[self.len] = .{ .name = name, .value = value };
            self.len += 1;
        }
    }
};

/// Fixed-size key-value store for middleware data (zero-allocation).
pub const Assigns = struct {
    const max_assigns = 16;

    entries: [max_assigns]Entry = undefined,
    len: usize = 0,

    const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn get(self: *const Assigns, key: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.mem.eql(u8, entry.key, key)) return entry.value;
        }
        return null;
    }

    pub fn put(self: *Assigns, key: []const u8, value: []const u8) void {
        // Overwrite if key exists
        for (self.entries[0..self.len]) |*entry| {
            if (std.mem.eql(u8, entry.key, key)) {
                entry.value = value;
                return;
            }
        }
        if (self.len < max_assigns) {
            self.entries[self.len] = .{ .key = key, .value = value };
            self.len += 1;
        }
    }
};

/// Context flows through the middleware/handler chain.
/// The pipeline is not stored directly to avoid a type dependency loop.
/// Instead, `next_handler` and `pipeline_state` provide an opaque trampoline.
pub const Context = struct {
    request: *const Request,
    response: Response,
    params: Params,
    query: Params,
    assigns: Assigns,
    parsed_body: ParsedBody = .none,
    allocator: Allocator,
    /// Opaque trampoline: calls the next handler in the pipeline.
    next_handler: ?*const fn (*Context) anyerror!void,

    /// Call the next handler in the pipeline.
    pub fn next(self: *Context) anyerror!void {
        if (self.next_handler) |handler| {
            try handler(self);
        }
    }

    /// Unified param lookup: path params → body form fields → query params.
    pub fn param(self: *const Context, name: []const u8) ?[]const u8 {
        if (self.params.get(name)) |v| return v;
        if (self.bodyField(name)) |v| return v;
        return self.query.get(name);
    }

    /// Get a path parameter by name (path params only).
    pub fn pathParam(self: *const Context, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    /// Get a form field value from the parsed body (URL-encoded, JSON, or multipart fields).
    pub fn formValue(self: *const Context, name: []const u8) ?[]const u8 {
        return self.bodyField(name);
    }

    /// Get the raw JSON body string (only if Content-Type was application/json).
    pub fn jsonBody(self: *const Context) ?[]const u8 {
        return switch (self.parsed_body) {
            .json => self.request.body,
            else => null,
        };
    }

    /// Get the raw request body bytes regardless of content type.
    pub fn rawBody(self: *const Context) ?[]const u8 {
        return self.request.body;
    }

    /// Get an uploaded file by field name (multipart only).
    pub fn file(self: *const Context, field_name: []const u8) ?*const FilePart {
        return switch (self.parsed_body) {
            .multipart => |*md| md.file(field_name),
            else => null,
        };
    }

    /// Internal: look up a field from any parsed body type that has form data.
    fn bodyField(self: *const Context, name: []const u8) ?[]const u8 {
        return switch (self.parsed_body) {
            .json => |*fd| fd.get(name),
            .form => |*fd| fd.get(name),
            .multipart => |*md| md.fields.get(name),
            else => null,
        };
    }

    /// Store a value in assigns.
    pub fn assign(self: *Context, key: []const u8, value: []const u8) void {
        self.assigns.put(key, value);
    }

    /// Get a value from assigns.
    pub fn getAssign(self: *const Context, key: []const u8) ?[]const u8 {
        return self.assigns.get(key);
    }

    /// Set response fields directly.
    pub fn respond(self: *Context, status: StatusCode, content_type: []const u8, body: []const u8) void {
        self.response.status = status;
        self.response.body = body;
        self.response.headers.append(self.allocator, "Content-Type", content_type) catch {};
    }

    /// Convenience: JSON response.
    pub fn json(self: *Context, status: StatusCode, body: []const u8) void {
        self.respond(status, "application/json; charset=utf-8", body);
    }

    /// Convenience: HTML response.
    pub fn html(self: *Context, status: StatusCode, body: []const u8) void {
        self.respond(status, "text/html; charset=utf-8", body);
    }

    /// Convenience: plain text response.
    pub fn text(self: *Context, status: StatusCode, body: []const u8) void {
        self.respond(status, "text/plain; charset=utf-8", body);
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "Params get and put" {
    var p: Params = .{};
    p.put("id", "42");
    p.put("name", "alice");

    try std.testing.expectEqualStrings("42", p.get("id").?);
    try std.testing.expectEqualStrings("alice", p.get("name").?);
    try std.testing.expect(p.get("missing") == null);
}

test "Assigns get, put, overwrite" {
    var a: Assigns = .{};
    a.put("user_id", "1");
    try std.testing.expectEqualStrings("1", a.get("user_id").?);

    // Overwrite
    a.put("user_id", "2");
    try std.testing.expectEqualStrings("2", a.get("user_id").?);
    try std.testing.expectEqual(@as(usize, 1), a.len);
}

test "Context respond sets fields" {
    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(std.testing.allocator);

    ctx.text(.ok, "hello");
    try std.testing.expectEqual(StatusCode.ok, ctx.response.status);
    try std.testing.expectEqualStrings("hello", ctx.response.body.?);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", ctx.response.headers.get("Content-Type").?);
}

test "Context unified param: path > body > query" {
    var req: Request = .{};
    defer req.deinit(std.testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = std.testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(std.testing.allocator);

    // Set up path param
    ctx.params.put("id", "path-42");
    // Set up query param
    ctx.query.put("page", "3");
    ctx.query.put("id", "query-99");
    // Set up body form data
    ctx.parsed_body = .{ .form = blk: {
        var fd: body_parser.FormData = .{};
        fd.put("email", "test@example.com");
        fd.put("id", "body-7");
        break :blk fd;
    } };

    // Path param wins over body and query
    try std.testing.expectEqualStrings("path-42", ctx.param("id").?);
    // Body field accessible
    try std.testing.expectEqualStrings("test@example.com", ctx.param("email").?);
    // Query param accessible
    try std.testing.expectEqualStrings("3", ctx.param("page").?);
    // Missing param
    try std.testing.expect(ctx.param("missing") == null);

    // Specific accessors
    try std.testing.expectEqualStrings("path-42", ctx.pathParam("id").?);
    try std.testing.expectEqualStrings("test@example.com", ctx.formValue("email").?);
    try std.testing.expect(ctx.jsonBody() == null);
    try std.testing.expect(ctx.rawBody() == null);
}
