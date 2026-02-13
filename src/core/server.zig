const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http_parser = @import("http/parser.zig");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const StatusCode = @import("http/status.zig").StatusCode;

/// Handler function type: receives a request, returns a response.
pub const Handler = *const fn (Allocator, *const Request) anyerror!Response;

/// Configuration for the HTTP server.
pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8888,
};

/// HTTP server using Zig 0.16's std.Io networking.
pub const Server = struct {
    config: Config,
    handler: Handler,
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: Config, handler: Handler) Server {
        return .{
            .config = config,
            .handler = handler,
            .allocator = allocator,
        };
    }

    /// Start listening and serving requests.
    pub fn listen(self: *Server, io: Io) !void {
        const address = try Io.net.IpAddress.parseIp4(self.config.host, self.config.port);

        var server = try address.listen(io, .{
            .reuse_address = true,
            .kernel_backlog = 128,
        });
        defer server.deinit(io);

        std.log.info("Zzz server listening on {s}:{d}", .{ self.config.host, self.config.port });

        while (true) {
            var stream = server.accept(io) catch |err| {
                std.log.warn("accept error: {}", .{err});
                continue;
            };
            self.handleConnection(io, &stream);
        }
    }

    fn handleConnection(self: *Server, io: Io, stream: *Io.net.Stream) void {
        defer stream.close(io);

        // Create a reader for the stream
        var read_buf: [16384]u8 = undefined;
        var reader: Io.net.Stream.Reader = .init(stream.*, io, &read_buf);

        // Read request header byte by byte, looking for \r\n\r\n
        var req_buf: [16384]u8 = undefined;
        var total_read: usize = 0;

        while (total_read < req_buf.len) {
            const byte = reader.interface.takeByte() catch return;
            req_buf[total_read] = byte;
            total_read += 1;

            // Check if we have complete headers (\r\n\r\n)
            if (total_read >= 4 and
                req_buf[total_read - 4] == '\r' and
                req_buf[total_read - 3] == '\n' and
                req_buf[total_read - 2] == '\r' and
                req_buf[total_read - 1] == '\n')
            {
                break;
            }
        }

        if (total_read == 0) return;

        // Parse request
        const parse_result = http_parser.parse(self.allocator, req_buf[0..total_read]) catch |err| {
            std.log.debug("parse error: {}", .{err});
            self.sendError(io, stream, .bad_request);
            return;
        };
        var req = parse_result.request;
        defer req.deinit(self.allocator);

        // Read body if Content-Length is present
        if (req.contentLength()) |content_len| {
            if (content_len > 0 and content_len <= 1024 * 1024) { // 1MB limit
                const body_buf = self.allocator.alloc(u8, content_len) catch {
                    self.sendError(io, stream, .payload_too_large);
                    return;
                };
                defer self.allocator.free(body_buf);

                // Some body bytes may already be in req_buf after headers
                const already_read = total_read - parse_result.bytes_consumed;
                if (already_read > 0) {
                    const copy_len = @min(already_read, content_len);
                    @memcpy(body_buf[0..copy_len], req_buf[parse_result.bytes_consumed .. parse_result.bytes_consumed + copy_len]);
                }

                // Read remaining body bytes from stream
                const body_so_far = @min(already_read, content_len);
                if (body_so_far < content_len) {
                    reader.interface.readSliceAll(body_buf[body_so_far..content_len]) catch return;
                }
                req.body = body_buf;
            }
        }

        // Call handler
        var resp = self.handler(self.allocator, &req) catch |err| {
            std.log.err("handler error: {}", .{err});
            self.sendError(io, stream, .internal_server_error);
            return;
        };
        defer resp.deinit(self.allocator);

        // Add Connection: close header for simplicity (Phase 1)
        resp.headers.append(self.allocator, "Connection", "close") catch {};

        // Send response
        self.sendResponse(io, stream, &resp);
    }

    fn sendResponse(self: *Server, io: Io, stream: *Io.net.Stream, resp: *const Response) void {
        _ = self;
        const bytes = resp.serialize(std.heap.page_allocator) catch return;
        defer std.heap.page_allocator.free(bytes);

        var write_buf: [16384]u8 = undefined;
        var writer: Io.net.Stream.Writer = .init(stream.*, io, &write_buf);
        writer.interface.writeAll(bytes) catch return;
        writer.interface.flush() catch return;
    }

    fn sendError(self: *Server, io: Io, stream: *Io.net.Stream, status: StatusCode) void {
        var resp = Response.empty(status);
        self.sendResponse(io, stream, &resp);
    }
};
