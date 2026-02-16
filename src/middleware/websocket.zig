const std = @import("std");
const Context = @import("context.zig").Context;
const HandlerFn = @import("context.zig").HandlerFn;
const Params = @import("context.zig").Params;
const Assigns = @import("context.zig").Assigns;
const Response = @import("../core/http/response.zig").Response;
const WsConnection = @import("../core/websocket/connection.zig");
const WebSocket = WsConnection.WebSocket;
const Message = WsConnection.Message;

/// Configuration for a WebSocket route handler.
pub const WsConfig = struct {
    on_open: ?*const fn (*WebSocket) void = null,
    on_message: ?*const fn (*WebSocket, Message) void = null,
    on_close: ?*const fn (*WebSocket, u16, []const u8) void = null,
};

/// Create a handler function that upgrades the connection to WebSocket.
pub fn wsHandler(comptime config: WsConfig) HandlerFn {
    const S = struct {
        fn handle(ctx: *Context) anyerror!void {
            // Validate this is a WebSocket upgrade request
            if (!ctx.request.isWebSocketUpgrade()) {
                ctx.respond(.bad_request, "text/plain; charset=utf-8", "400 Bad Request: Not a WebSocket upgrade request");
                return;
            }

            // Set 101 Switching Protocols status
            ctx.response.status = .switching_protocols;

            // Allocate a WebSocketUpgrade struct and copy params/query/assigns + handler callbacks
            const ws_upgrade = ctx.allocator.create(Response.WebSocketUpgrade) catch {
                ctx.respond(.internal_server_error, "text/plain; charset=utf-8", "500 Internal Server Error");
                return;
            };
            ws_upgrade.* = .{
                .handler = .{
                    .on_open = config.on_open,
                    .on_message = config.on_message,
                    .on_close = config.on_close,
                },
                .params = ctx.params,
                .query = ctx.query,
                .assigns = ctx.assigns,
            };

            ctx.response.ws_handler = ws_upgrade;
        }
    };
    return &S.handle;
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;
const Request = @import("../core/http/request.zig").Request;
const StatusCode = @import("../core/http/status.zig").StatusCode;

test "wsHandler returns 400 for non-upgrade request" {
    const handler = comptime wsHandler(.{});

    var req: Request = .{ .method = .GET, .path = "/ws" };
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
    try testing.expectEqual(StatusCode.bad_request, ctx.response.status);
}

test "wsHandler sets 101 and ws_handler on upgrade request" {
    const handler = comptime wsHandler(.{});

    var req: Request = .{ .method = .GET, .path = "/ws" };
    try req.headers.append(testing.allocator, "Upgrade", "websocket");
    try req.headers.append(testing.allocator, "Connection", "Upgrade");
    try req.headers.append(testing.allocator, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
    try req.headers.append(testing.allocator, "Sec-WebSocket-Version", "13");
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
    defer {
        if (ctx.response.ws_handler) |ws| {
            testing.allocator.destroy(ws);
        }
        ctx.response.deinit(testing.allocator);
    }

    try handler(&ctx);
    try testing.expectEqual(StatusCode.switching_protocols, ctx.response.status);
    try testing.expect(ctx.response.ws_handler != null);
}

test "wsHandler copies params and assigns" {
    const handler = comptime wsHandler(.{});

    var req: Request = .{ .method = .GET, .path = "/ws/lobby" };
    try req.headers.append(testing.allocator, "Upgrade", "websocket");
    try req.headers.append(testing.allocator, "Connection", "Upgrade");
    try req.headers.append(testing.allocator, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
    try req.headers.append(testing.allocator, "Sec-WebSocket-Version", "13");
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
    ctx.params.put("room", "lobby");
    ctx.assigns.put("user", "alice");

    defer {
        if (ctx.response.ws_handler) |ws| {
            testing.allocator.destroy(ws);
        }
        ctx.response.deinit(testing.allocator);
    }

    try handler(&ctx);
    const ws_upgrade = ctx.response.ws_handler.?;
    try testing.expectEqualStrings("lobby", ws_upgrade.params.get("room").?);
    try testing.expectEqualStrings("alice", ws_upgrade.assigns.get("user").?);
}
