const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = @import("../core/http/request.zig").Method;
const Request = @import("../core/http/request.zig").Request;
const Response = @import("../core/http/response.zig").Response;
const StatusCode = @import("../core/http/status.zig").StatusCode;
const Context = @import("../middleware/context.zig").Context;
const HandlerFn = @import("../middleware/context.zig").HandlerFn;
const Params = @import("../middleware/context.zig").Params;
const route_mod = @import("route.zig");
const Segment = route_mod.Segment;

/// A route definition tuple used in the config DSL.
pub const RouteDef = struct {
    method: Method,
    pattern: []const u8,
    handler: HandlerFn,
    middleware: []const HandlerFn = &.{},
};

/// Router configuration.
pub const RouterConfig = struct {
    middleware: []const HandlerFn = &.{},
    routes: []const RouteDef = &.{},
};

/// The Router namespace — use `Router.define(config)` to create a routed app.
pub const Router = struct {
    // ── Route helper functions ─────────────────────────────────────────

    pub fn get(comptime pattern: []const u8, comptime handler: HandlerFn) RouteDef {
        return .{ .method = .GET, .pattern = pattern, .handler = handler };
    }

    pub fn post(comptime pattern: []const u8, comptime handler: HandlerFn) RouteDef {
        return .{ .method = .POST, .pattern = pattern, .handler = handler };
    }

    pub fn put(comptime pattern: []const u8, comptime handler: HandlerFn) RouteDef {
        return .{ .method = .PUT, .pattern = pattern, .handler = handler };
    }

    pub fn patch(comptime pattern: []const u8, comptime handler: HandlerFn) RouteDef {
        return .{ .method = .PATCH, .pattern = pattern, .handler = handler };
    }

    pub fn delete(comptime pattern: []const u8, comptime handler: HandlerFn) RouteDef {
        return .{ .method = .DELETE, .pattern = pattern, .handler = handler };
    }

    /// Group routes under a common prefix with shared middleware.
    pub fn scope(
        comptime prefix: []const u8,
        comptime mw: []const HandlerFn,
        comptime routes: []const RouteDef,
    ) []const RouteDef {
        comptime {
            var expanded: [routes.len]RouteDef = undefined;
            for (routes, 0..) |r, i| {
                expanded[i] = .{
                    .method = r.method,
                    .pattern = prefix ++ r.pattern,
                    .handler = r.handler,
                    .middleware = mw ++ r.middleware,
                };
            }
            const result = expanded;
            return &result;
        }
    }

    /// Define a router from a comptime config. Returns a type with a `handler`
    /// function matching the `Handler` signature expected by `Server`.
    pub fn define(comptime config: RouterConfig) type {
        return struct {
            /// Handler function compatible with Server's Handler type.
            pub fn handler(allocator: Allocator, req: *const Request) anyerror!Response {
                return dispatch(config, allocator, req);
            }
        };
    }
};

/// Generate a comptime chain of pipeline functions and return the entry point.
fn makePipelineEntry(comptime pipeline: []const HandlerFn) *const fn (*Context) anyerror!void {
    if (pipeline.len == 0) {
        const S = struct {
            fn noop(_: *Context) anyerror!void {}
        };
        return &S.noop;
    }
    return makePipelineStep(pipeline, 0);
}

fn makePipelineStep(comptime pipeline: []const HandlerFn, comptime index: usize) *const fn (*Context) anyerror!void {
    const S = struct {
        fn run(ctx: *Context) anyerror!void {
            // Set next_handler for ctx.next() to call
            if (index + 1 < pipeline.len) {
                ctx.next_handler = comptime makePipelineStep(pipeline, index + 1);
            } else {
                ctx.next_handler = null;
            }
            try pipeline[index](ctx);
        }
    };
    return &S.run;
}

/// Internal dispatch: inline for over routes, match, build context, run pipeline.
fn dispatch(
    comptime config: RouterConfig,
    allocator: Allocator,
    req: *const Request,
) anyerror!Response {
    const path = req.path;
    const method = req.method;

    // For HEAD requests, also match GET routes
    const also_try_get = (method == .HEAD);

    // Try each route — inline for generates comptime-specialized branches
    inline for (config.routes) |route_def| {
        const segments = comptime route_mod.compilePattern(route_def.pattern);

        if (route_def.method == method or (also_try_get and route_def.method == .GET)) {
            if (route_mod.matchSegments(segments, path)) |match_params| {
                // Build pipeline at comptime: global middleware ++ route middleware ++ handler
                const pipeline = comptime config.middleware ++ route_def.middleware ++ &[_]HandlerFn{route_def.handler};
                const entry = comptime makePipelineEntry(pipeline);

                var ctx: Context = .{
                    .request = req,
                    .response = .{},
                    .params = match_params,
                    .query = parseQuery(req.query_string),
                    .assigns = .{},
                    .allocator = allocator,
                    .next_handler = null,
                };

                entry(&ctx) catch |err| {
                    ctx.response.deinit(allocator);
                    return err;
                };

                // HEAD: clear body but keep headers
                if (method == .HEAD) {
                    ctx.response.body = null;
                }

                return ctx.response;
            }
        }
    }

    // No match — check if path matches with a different method (405)
    var path_matches = false;
    var allow_buf: [128]u8 = undefined;
    var allow_pos: usize = 0;

    inline for (config.routes) |route_def| {
        const segments = comptime route_mod.compilePattern(route_def.pattern);
        if (route_mod.matchSegments(segments, path) != null) {
            path_matches = true;
            const mname = comptime route_def.method.toString();
            if (allow_pos > 0 and allow_pos + 2 < allow_buf.len) {
                allow_buf[allow_pos] = ',';
                allow_buf[allow_pos + 1] = ' ';
                allow_pos += 2;
            }
            if (allow_pos + mname.len <= allow_buf.len) {
                @memcpy(allow_buf[allow_pos..][0..mname.len], mname);
                allow_pos += mname.len;
            }
        }
    }

    if (path_matches) {
        var resp: Response = .{ .status = .method_not_allowed };
        try resp.headers.append(allocator, "Allow", allow_buf[0..allow_pos]);
        try resp.setBody(allocator, "text/plain; charset=utf-8", "405 Method Not Allowed");
        return resp;
    }

    // 404
    return Response.text(allocator, .not_found, "404 Not Found");
}

/// Parse a query string into Params. E.g. "foo=bar&baz=qux"
fn parseQuery(query_string: ?[]const u8) Params {
    var params: Params = .{};
    const qs = query_string orelse return params;
    if (qs.len == 0) return params;

    var pos: usize = 0;
    while (pos < qs.len) {
        const amp = std.mem.indexOfScalarPos(u8, qs, pos, '&') orelse qs.len;
        const pair = qs[pos..amp];
        pos = amp + 1;

        if (pair.len == 0) continue;

        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            params.put(pair[0..eq], pair[eq + 1 ..]);
        } else {
            params.put(pair, "");
        }
    }
    return params;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Router.define basic routing" {
    const testing = std.testing;

    const IndexHandler = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "index");
        }
    };
    const HelloHandler = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "hello");
        }
    };
    const UserHandler = struct {
        fn handle(ctx: *Context) !void {
            const id = ctx.param("id") orelse "unknown";
            ctx.text(.ok, id);
        }
    };

    const App = Router.define(.{
        .routes = &.{
            Router.get("/", IndexHandler.handle),
            Router.get("/hello", HelloHandler.handle),
            Router.get("/users/:id", UserHandler.handle),
            Router.post("/users", HelloHandler.handle),
        },
    });

    // GET /
    {
        var req: Request = .{ .method = .GET, .path = "/" };
        defer req.deinit(testing.allocator);
        var resp = try App.handler(testing.allocator, &req);
        defer resp.deinit(testing.allocator);
        try testing.expectEqual(StatusCode.ok, resp.status);
        try testing.expectEqualStrings("index", resp.body.?);
    }

    // GET /hello
    {
        var req: Request = .{ .method = .GET, .path = "/hello" };
        defer req.deinit(testing.allocator);
        var resp = try App.handler(testing.allocator, &req);
        defer resp.deinit(testing.allocator);
        try testing.expectEqualStrings("hello", resp.body.?);
    }

    // GET /users/42 — param extraction
    {
        var req: Request = .{ .method = .GET, .path = "/users/42" };
        defer req.deinit(testing.allocator);
        var resp = try App.handler(testing.allocator, &req);
        defer resp.deinit(testing.allocator);
        try testing.expectEqualStrings("42", resp.body.?);
    }

    // GET /missing — 404
    {
        var req: Request = .{ .method = .GET, .path = "/missing" };
        defer req.deinit(testing.allocator);
        var resp = try App.handler(testing.allocator, &req);
        defer resp.deinit(testing.allocator);
        try testing.expectEqual(StatusCode.not_found, resp.status);
    }

    // POST /hello — 405
    {
        var req: Request = .{ .method = .POST, .path = "/hello" };
        defer req.deinit(testing.allocator);
        var resp = try App.handler(testing.allocator, &req);
        defer resp.deinit(testing.allocator);
        try testing.expectEqual(StatusCode.method_not_allowed, resp.status);
        try testing.expect(resp.headers.get("Allow") != null);
    }
}

test "Router.define HEAD returns no body" {
    const testing = std.testing;

    const H = struct {
        fn handle(ctx: *Context) !void {
            ctx.text(.ok, "body content");
        }
    };

    const App = Router.define(.{
        .routes = &.{
            Router.get("/hello", H.handle),
        },
    });

    var req: Request = .{ .method = .HEAD, .path = "/hello" };
    defer req.deinit(testing.allocator);
    var resp = try App.handler(testing.allocator, &req);
    defer resp.deinit(testing.allocator);
    try testing.expectEqual(StatusCode.ok, resp.status);
    try testing.expect(resp.body == null);
}

test "Router.define middleware pipeline" {
    const testing = std.testing;

    const AuthMiddleware = struct {
        fn handle(ctx: *Context) !void {
            ctx.assign("auth", "true");
            try ctx.next();
        }
    };
    const H = struct {
        fn handle(ctx: *Context) !void {
            const auth = ctx.getAssign("auth") orelse "false";
            ctx.text(.ok, auth);
        }
    };

    const App = Router.define(.{
        .middleware = &.{AuthMiddleware.handle},
        .routes = &.{
            Router.get("/", H.handle),
        },
    });

    var req: Request = .{ .method = .GET, .path = "/" };
    defer req.deinit(testing.allocator);
    var resp = try App.handler(testing.allocator, &req);
    defer resp.deinit(testing.allocator);
    try testing.expectEqualStrings("true", resp.body.?);
}

test "parseQuery" {
    const q = parseQuery("foo=bar&baz=qux&empty=");
    try std.testing.expectEqualStrings("bar", q.get("foo").?);
    try std.testing.expectEqualStrings("qux", q.get("baz").?);
    try std.testing.expectEqualStrings("", q.get("empty").?);
    try std.testing.expect(q.get("missing") == null);
}
