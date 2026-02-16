const std = @import("std");
const Io = std.Io;
const ssl_mod = @import("ssl.zig");
const c = ssl_mod.c;

/// TLS-backed reader implementing Io.Reader vtable via SSL_read().
pub const TlsReader = struct {
    interface: Io.Reader,
    ssl: *c.SSL,

    pub fn init(ssl: *c.SSL, buffer: []u8) TlsReader {
        return .{
            .interface = .{
                .vtable = &.{
                    .stream = streamImpl,
                    .readVec = readVec,
                },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
            .ssl = ssl,
        };
    }

    fn streamImpl(io_r: *Io.Reader, io_w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
        const dest = limit.slice(try io_w.writableSliceGreedy(1));
        var data: [1][]u8 = .{dest};
        const n = try readVec(io_r, &data);
        io_w.advance(n);
        return n;
    }

    fn readVec(io_r: *Io.Reader, data: [][]u8) Io.Reader.Error!usize {
        const r: *TlsReader = @alignCast(@fieldParentPtr("interface", io_r));

        // Build a writable vector (same pattern as net.zig)
        var iovecs_buffer: [8][]u8 = undefined;
        const dest_n, const data_size = try io_r.writableVector(&iovecs_buffer, data);
        const dest = iovecs_buffer[0..dest_n];
        std.debug.assert(dest[0].len > 0);

        // SSL_read into the first buffer slot
        const buf = dest[0];
        const ret = c.SSL_read(r.ssl, buf.ptr, @intCast(buf.len));
        if (ret <= 0) {
            return error.EndOfStream;
        }
        const n: usize = @intCast(ret);

        if (n > data_size) {
            io_r.end += n - data_size;
            return data_size;
        }
        return n;
    }
};

/// TLS-backed writer implementing Io.Writer vtable via SSL_write().
pub const TlsWriter = struct {
    interface: Io.Writer,
    ssl: *c.SSL,

    pub fn init(ssl: *c.SSL, buffer: []u8) TlsWriter {
        return .{
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = buffer,
            },
            .ssl = ssl,
        };
    }

    fn drain(io_w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const w: *TlsWriter = @alignCast(@fieldParentPtr("interface", io_w));

        var total_written: usize = 0;

        // First, write any buffered data
        const buf = io_w.buffered();
        if (buf.len > 0) {
            var written: usize = 0;
            while (written < buf.len) {
                const ret = c.SSL_write(w.ssl, buf[written..].ptr, @intCast(buf.len - written));
                if (ret <= 0) {
                    return error.WriteFailed;
                }
                written += @intCast(ret);
            }
            total_written += written;
        }

        // Then write each data slice
        for (data[0 .. data.len - 1]) |slice| {
            var written: usize = 0;
            while (written < slice.len) {
                const ret = c.SSL_write(w.ssl, slice[written..].ptr, @intCast(slice.len - written));
                if (ret <= 0) {
                    return error.WriteFailed;
                }
                written += @intCast(ret);
            }
            total_written += written;
        }

        // Write the last slice `splat` times
        const last = data[data.len - 1];
        for (0..splat) |_| {
            var written: usize = 0;
            while (written < last.len) {
                const ret = c.SSL_write(w.ssl, last[written..].ptr, @intCast(last.len - written));
                if (ret <= 0) {
                    return error.WriteFailed;
                }
                written += @intCast(ret);
            }
            total_written += written;
        }

        return io_w.consume(total_written);
    }
};
