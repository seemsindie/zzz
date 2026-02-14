const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
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
    max_body_size: usize = 1024 * 1024, // 1MB default
    max_header_size: usize = 16384, // 16KB default
    read_timeout_ms: u32 = 30_000, // 30s
    write_timeout_ms: u32 = 30_000, // 30s
    keepalive_timeout_ms: u32 = 65_000, // 65s
    worker_threads: u16 = 4, // 0 = single-threaded
    max_connections: u32 = 1024,
    max_requests_per_connection: u32 = 100,
    kernel_backlog: u31 = 128,
};

/// Global server reference for signal handling.
var global_server: ?*Server = null;

/// HTTP server using Zig 0.16's std.Io networking.
pub const Server = struct {
    config: Config,
    handler: Handler,
    allocator: Allocator,
    active_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    shutdown_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: Allocator, config: Config, handler: Handler) Server {
        return .{
            .config = config,
            .handler = handler,
            .allocator = allocator,
        };
    }

    /// Start listening and serving requests.
    pub fn listen(self: *Server, io: Io) !void {
        self.installSignalHandlers();

        const address = try Io.net.IpAddress.parseIp4(self.config.host, self.config.port);

        var server = try address.listen(io, .{
            .reuse_address = true,
            .kernel_backlog = self.config.kernel_backlog,
        });
        defer server.deinit(io);

        std.log.info("Zzz server listening on {s}:{d}", .{ self.config.host, self.config.port });

        while (!self.shutdown_flag.load(.acquire)) {
            var stream = server.accept(io) catch |err| {
                if (self.shutdown_flag.load(.acquire)) break;
                std.log.warn("accept error: {}", .{err});
                continue;
            };

            if (self.config.worker_threads == 0) {
                // Single-threaded mode: handle inline
                self.handleConnection(io, &stream);
            } else {
                // Multi-threaded mode: check backpressure
                if (self.active_connections.load(.acquire) >= self.config.max_connections) {
                    stream.close(io);
                    continue;
                }

                const thread = std.Thread.spawn(.{}, connectionThread, .{ self, stream, io }) catch {
                    stream.close(io);
                    continue;
                };
                thread.detach();
            }
        }

        // Graceful shutdown: drain active connections
        std.log.info("Shutting down, waiting for active connections to drain...", .{});
        self.drainConnections();
        std.log.info("Server stopped.", .{});
    }

    /// Thread entry point for multi-threaded mode.
    fn connectionThread(self: *Server, stream_val: Io.net.Stream, io: Io) void {
        _ = self.active_connections.fetchAdd(1, .release);
        defer _ = self.active_connections.fetchSub(1, .release);

        var stream = stream_val;
        self.handleConnection(io, &stream);
    }

    fn handleConnection(self: *Server, io: Io, stream: *Io.net.Stream) void {
        defer stream.close(io);

        // Set socket timeouts
        self.setSocketTimeouts(stream);

        // Create a reader for the stream (persists across keep-alive requests)
        var read_buf: [16384]u8 = undefined;
        var reader: Io.net.Stream.Reader = .init(stream.*, io, &read_buf);

        var write_buf: [16384]u8 = undefined;
        var writer: Io.net.Stream.Writer = .init(stream.*, io, &write_buf);

        var requests_served: u32 = 0;

        while (requests_served < self.config.max_requests_per_connection) {
            if (self.shutdown_flag.load(.acquire)) break;

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

            // Client closed connection
            if (total_read == 0) return;

            // Parse request
            const parse_result = http_parser.parse(self.allocator, req_buf[0..total_read]) catch |err| {
                std.log.debug("parse error: {}", .{err});
                self.sendError(io, stream, &writer, .bad_request);
                return;
            };
            var req = parse_result.request;
            defer req.deinit(self.allocator);

            // Handle 100-continue
            if (req.header("Expect")) |expect| {
                if (std.ascii.eqlIgnoreCase(expect, "100-continue")) {
                    writer.interface.writeAll("HTTP/1.1 100 Continue\r\n\r\n") catch {};
                    writer.interface.flush() catch {};
                }
            }

            // Read body
            if (req.isChunked() and req.contentLength() == null) {
                // Chunked transfer encoding
                const body_data = self.readChunkedBody(&reader, self.allocator) catch {
                    self.sendError(io, stream, &writer, .bad_request);
                    return;
                };
                if (body_data) |data| {
                    defer self.allocator.free(data);
                    req.body = data;

                    // Call handler and send response
                    self.processRequest(io, stream, &writer, &req, requests_served);
                } else {
                    self.processRequest(io, stream, &writer, &req, requests_served);
                }
            } else if (req.contentLength()) |content_len| {
                if (content_len > self.config.max_body_size) {
                    self.sendError(io, stream, &writer, .payload_too_large);
                    return;
                }
                if (content_len > 0) {
                    const body_buf = self.allocator.alloc(u8, content_len) catch {
                        self.sendError(io, stream, &writer, .payload_too_large);
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

                    self.processRequest(io, stream, &writer, &req, requests_served);
                } else {
                    self.processRequest(io, stream, &writer, &req, requests_served);
                }
            } else {
                self.processRequest(io, stream, &writer, &req, requests_served);
            }

            requests_served += 1;

            // Check if we should keep the connection alive
            const keep_alive = req.keepAlive() and
                (requests_served < self.config.max_requests_per_connection);
            if (!keep_alive) break;
        }
    }

    /// Process a parsed request: call handler, set keep-alive headers, send response.
    fn processRequest(
        self: *Server,
        io: Io,
        stream: *Io.net.Stream,
        writer: *Io.net.Stream.Writer,
        req: *Request,
        requests_served: u32,
    ) void {
        var resp = self.handler(self.allocator, req) catch |err| {
            std.log.err("handler error: {}", .{err});
            self.sendError(io, stream, writer, .internal_server_error);
            return;
        };
        defer resp.deinit(self.allocator);

        // Set response version to match request
        resp.version = req.version;

        // Set Connection header based on keep-alive status
        const keep_alive = req.keepAlive() and
            (requests_served + 1 < self.config.max_requests_per_connection);
        resp.headers.set(self.allocator, "Connection", if (keep_alive) "keep-alive" else "close") catch {};

        self.sendResponseWriter(writer, &resp);
    }

    /// Read a chunked request body, accumulating chunks until the terminating 0-length chunk.
    fn readChunkedBody(self: *Server, reader: *Io.net.Stream.Reader, allocator: Allocator) !?[]u8 {
        var body: std.ArrayList(u8) = .empty;
        errdefer body.deinit(allocator);

        while (true) {
            // Read chunk size line (hex digits followed by \r\n)
            var line_buf: [64]u8 = undefined;
            var line_len: usize = 0;

            while (line_len < line_buf.len) {
                const byte = try reader.interface.takeByte();
                if (byte == '\r') {
                    // Expect \n next
                    const lf = try reader.interface.takeByte();
                    if (lf != '\n') return error.InvalidChunkedEncoding;
                    break;
                }
                line_buf[line_len] = byte;
                line_len += 1;
            }

            if (line_len == 0) return error.InvalidChunkedEncoding;

            // Strip optional chunk extensions (after semicolon)
            var size_str = line_buf[0..line_len];
            if (std.mem.indexOf(u8, size_str, ";")) |semi| {
                size_str = line_buf[0..semi];
            }

            const chunk_size = std.fmt.parseInt(usize, size_str, 16) catch
                return error.InvalidChunkedEncoding;

            // Chunk size 0 = end of body
            if (chunk_size == 0) {
                // Read trailing \r\n after the last chunk
                _ = reader.interface.takeByte() catch {};
                _ = reader.interface.takeByte() catch {};
                break;
            }

            // Enforce max body size
            if (body.items.len + chunk_size > self.config.max_body_size) {
                return error.PayloadTooLarge;
            }

            // Read chunk data
            const start = body.items.len;
            try body.resize(allocator, start + chunk_size);
            reader.interface.readSliceAll(body.items[start..]) catch
                return error.InvalidChunkedEncoding;

            // Read trailing \r\n after chunk data
            const cr = reader.interface.takeByte() catch return error.InvalidChunkedEncoding;
            const lf = reader.interface.takeByte() catch return error.InvalidChunkedEncoding;
            if (cr != '\r' or lf != '\n') return error.InvalidChunkedEncoding;
        }

        if (body.items.len == 0) return null;
        return try body.toOwnedSlice(allocator);
    }

    fn sendResponseWriter(self: *Server, writer: *Io.net.Stream.Writer, resp: *const Response) void {
        _ = self;
        const bytes = resp.serialize(std.heap.page_allocator) catch return;
        defer std.heap.page_allocator.free(bytes);

        writer.interface.writeAll(bytes) catch return;
        writer.interface.flush() catch return;
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

    fn sendError(self: *Server, io: Io, stream: *Io.net.Stream, writer: *Io.net.Stream.Writer, status: StatusCode) void {
        _ = io;
        _ = stream;
        var resp = Response.empty(status);
        self.sendResponseWriter(writer, &resp);
    }

    /// Set socket read/write timeouts using setsockopt.
    fn setSocketTimeouts(self: *Server, stream: *Io.net.Stream) void {
        const fd = stream.socket.handle;

        if (self.config.read_timeout_ms > 0) {
            const read_tv = msToTimeval(self.config.read_timeout_ms);
            std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&read_tv)) catch {};
        }

        if (self.config.write_timeout_ms > 0) {
            const write_tv = msToTimeval(self.config.write_timeout_ms);
            std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&write_tv)) catch {};
        }
    }

    fn msToTimeval(ms: u32) std.posix.timeval {
        return .{
            .sec = @intCast(ms / 1000),
            .usec = @intCast(@as(u32, ms % 1000) * 1000),
        };
    }

    /// Install signal handlers for graceful shutdown (SIGINT, SIGTERM).
    fn installSignalHandlers(self: *Server) void {
        global_server = self;
        const act: std.posix.Sigaction = .{
            .handler = .{ .handler = signalHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &act, null);
        std.posix.sigaction(std.posix.SIG.TERM, &act, null);
    }

    /// Wait for active connections to drain (up to 10 seconds).
    fn drainConnections(self: *Server) void {
        const timeout_ns: i128 = 10 * std.time.ns_per_s;
        const start = getMonotonicNs();

        while (self.active_connections.load(.acquire) > 0) {
            if (getMonotonicNs() - start >= timeout_ns) {
                const remaining = self.active_connections.load(.acquire);
                std.log.warn("Shutdown timeout: {d} connections still active", .{remaining});
                return;
            }
            // Sleep 50ms between polls
            std.Thread.yield() catch {};
        }
    }

    fn getMonotonicNs() i128 {
        if (native_os == .linux) {
            const linux = std.os.linux;
            var ts: linux.timespec = undefined;
            _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
            return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
        } else {
            const c = std.c;
            var ts: c.timespec = undefined;
            _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
            return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
        }
    }
};

fn signalHandler(_: std.posix.SIG) callconv(.c) void {
    if (global_server) |s| s.shutdown_flag.store(true, .release);
}
