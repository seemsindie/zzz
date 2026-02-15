const std = @import("std");
const Context = @import("../middleware/context.zig").Context;
const HandlerFn = @import("../middleware/context.zig").HandlerFn;

/// Configuration for the Swagger UI middleware.
pub const Config = struct {
    /// The comptime-generated OpenAPI spec JSON string.
    spec_json: []const u8,
    /// Path to serve the Swagger UI at (default: "/api/docs").
    path: []const u8 = "/api/docs",
    /// Swagger UI CDN version (default: "5.18.2").
    cdn_version: []const u8 = "5.18.2",
};

/// Create a Swagger UI middleware handler.
/// Serves an interactive Swagger UI page at the configured path, and the raw
/// OpenAPI JSON spec at `<path>/openapi.json`.
///
/// Usage:
///   const spec = swagger.generateSpec(.{ .title = "My API" }, routes);
///   // Add to middleware:
///   swagger.ui(.{ .spec_json = spec })
pub fn ui(comptime config: Config) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            if (ctx.request.method == .GET) {
                // Serve raw spec JSON
                if (std.mem.eql(u8, ctx.request.path, config.path ++ "/openapi.json")) {
                    ctx.response.status = .ok;
                    ctx.response.body = config.spec_json;
                    ctx.response.headers.append(ctx.allocator, "Content-Type", "application/json; charset=utf-8") catch {};
                    ctx.response.headers.append(ctx.allocator, "Cache-Control", "public, max-age=3600") catch {};
                    return;
                }

                // Serve Swagger UI HTML page
                if (std.mem.eql(u8, ctx.request.path, config.path)) {
                    ctx.response.status = .ok;
                    ctx.response.body = swagger_html;
                    ctx.response.headers.append(ctx.allocator, "Content-Type", "text/html; charset=utf-8") catch {};
                    return;
                }
            }

            // Pass through to next middleware
            try ctx.next();
        }

        const swagger_html = "<!DOCTYPE html>" ++
            "<html lang=\"en\">" ++
            "<head>" ++
            "<meta charset=\"UTF-8\">" ++
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" ++
            "<title>" ++ config.path ++ "</title>" ++
            "<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist@" ++ config.cdn_version ++ "/swagger-ui.css\">" ++
            "</head>" ++
            "<body>" ++
            "<div id=\"swagger-ui\"></div>" ++
            "<script src=\"https://unpkg.com/swagger-ui-dist@" ++ config.cdn_version ++ "/swagger-ui-bundle.js\"></script>" ++
            "<script>" ++
            "SwaggerUIBundle({url:'" ++ config.path ++ "/openapi.json',dom_id:'#swagger-ui',presets:[SwaggerUIBundle.presets.apis],layout:'BaseLayout'});" ++
            "</script>" ++
            "</body>" ++
            "</html>";
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;
const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "swagger ui serves HTML at /api/docs" {
    const handler = comptime ui(.{ .spec_json = "{}" });

    var req: Request = .{ .method = .GET, .path = "/api/docs" };
    defer req.deinit(testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expectEqual(StatusCode.ok, ctx.response.status);
    try testing.expect(ctx.response.body != null);
    try testing.expect(std.mem.indexOf(u8, ctx.response.body.?, "swagger-ui") != null);
    try testing.expectEqualStrings("text/html; charset=utf-8", ctx.response.headers.get("Content-Type").?);
}

test "swagger ui serves JSON at /api/docs/openapi.json" {
    const handler = comptime ui(.{ .spec_json = "{\"openapi\":\"3.1.0\"}" });

    var req: Request = .{ .method = .GET, .path = "/api/docs/openapi.json" };
    defer req.deinit(testing.allocator);

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = null,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expectEqual(StatusCode.ok, ctx.response.status);
    try testing.expectEqualStrings("{\"openapi\":\"3.1.0\"}", ctx.response.body.?);
    try testing.expectEqualStrings("application/json; charset=utf-8", ctx.response.headers.get("Content-Type").?);
}

test "swagger ui passes through non-matching requests" {
    const handler = comptime ui(.{ .spec_json = "{}" });

    var req: Request = .{ .method = .GET, .path = "/other" };
    defer req.deinit(testing.allocator);

    var next_called = false;
    const NextHandler = struct {
        var called: *bool = undefined;
        fn handle(_: *Context) anyerror!void {
            called.* = true;
        }
    };
    NextHandler.called = &next_called;

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = &NextHandler.handle,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expect(next_called);
}

test "swagger ui ignores POST requests" {
    const handler = comptime ui(.{ .spec_json = "{}" });

    var req: Request = .{ .method = .POST, .path = "/api/docs" };
    defer req.deinit(testing.allocator);

    var next_called = false;
    const NextHandler = struct {
        var called: *bool = undefined;
        fn handle(_: *Context) anyerror!void {
            called.* = true;
        }
    };
    NextHandler.called = &next_called;

    var ctx: Context = .{
        .request = &req,
        .response = .{},
        .params = .{},
        .query = .{},
        .assigns = .{},
        .allocator = testing.allocator,
        .next_handler = &NextHandler.handle,
    };
    defer ctx.response.deinit(testing.allocator);

    try handler(&ctx);
    try testing.expect(next_called);
}
