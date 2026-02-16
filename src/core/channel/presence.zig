const std = @import("std");
const Socket = @import("socket.zig").Socket;
const WebSocket = @import("../websocket/connection.zig").WebSocket;

fn spinLock(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) {}
}

/// Presence tracking — tracks who's in which topic with metadata.
/// Fixed-size (max 512 entries), mutex-protected.
pub const Presence = struct {
    const max_entries = 512;

    const PresenceEntry = struct {
        ws: *WebSocket = undefined,
        topic: [128]u8 = undefined,
        topic_len: usize = 0,
        key: [64]u8 = undefined,
        key_len: usize = 0,
        meta_json: [256]u8 = undefined,
        meta_len: usize = 0,
        active: bool = false,

        fn topicSlice(self: *const PresenceEntry) []const u8 {
            return self.topic[0..self.topic_len];
        }

        fn keySlice(self: *const PresenceEntry) []const u8 {
            return self.key[0..self.key_len];
        }

        fn metaSlice(self: *const PresenceEntry) []const u8 {
            return self.meta_json[0..self.meta_len];
        }
    };

    var entries: [max_entries]PresenceEntry = blk: {
        var e: [max_entries]PresenceEntry = undefined;
        for (&e) |*entry| {
            entry.* = .{};
        }
        break :blk e;
    };
    var mutex: std.atomic.Mutex = .unlocked;

    /// Track a socket's presence in a topic with a key and metadata.
    pub fn track(socket: *Socket, topic: []const u8, key: []const u8, meta_json: []const u8) bool {
        if (topic.len > 128 or key.len > 64 or meta_json.len > 256) return false;

        spinLock(&mutex);
        defer mutex.unlock();

        // Update existing entry if same ws + topic
        for (&entries) |*entry| {
            if (entry.active and entry.ws == socket.ws and
                entry.topic_len == topic.len and
                std.mem.eql(u8, entry.topicSlice(), topic))
            {
                entry.key_len = key.len;
                @memcpy(entry.key[0..key.len], key);
                entry.meta_len = meta_json.len;
                @memcpy(entry.meta_json[0..meta_json.len], meta_json);
                return true;
            }
        }

        // Find empty slot
        for (&entries) |*entry| {
            if (!entry.active) {
                entry.active = true;
                entry.ws = socket.ws;
                entry.topic_len = topic.len;
                @memcpy(entry.topic[0..topic.len], topic);
                entry.key_len = key.len;
                @memcpy(entry.key[0..key.len], key);
                entry.meta_len = meta_json.len;
                @memcpy(entry.meta_json[0..meta_json.len], meta_json);
                return true;
            }
        }

        return false;
    }

    /// Untrack a socket's presence from a topic.
    pub fn untrack(socket: *Socket, topic: []const u8) void {
        spinLock(&mutex);
        defer mutex.unlock();

        for (&entries) |*entry| {
            if (entry.active and entry.ws == socket.ws and
                entry.topic_len == topic.len and
                std.mem.eql(u8, entry.topicSlice(), topic))
            {
                entry.active = false;
                return;
            }
        }
    }

    /// Untrack a socket from all topics (call on disconnect).
    pub fn untrackAll(socket: *Socket) void {
        spinLock(&mutex);
        defer mutex.unlock();

        for (&entries) |*entry| {
            if (entry.active and entry.ws == socket.ws) {
                entry.active = false;
            }
        }
    }

    /// List all presences for a topic as a JSON array.
    pub fn list(topic: []const u8, buf: []u8) []const u8 {
        spinLock(&mutex);
        defer mutex.unlock();

        var pos: usize = 0;
        if (pos >= buf.len) return "";
        buf[pos] = '[';
        pos += 1;

        var first = true;
        for (&entries) |*entry| {
            if (entry.active and entry.topic_len == topic.len and
                std.mem.eql(u8, entry.topicSlice(), topic))
            {
                const item = std.fmt.bufPrint(buf[pos..],
                    \\{s}{{"key":"{s}","meta":{s}}}
                , .{
                    if (first) @as([]const u8, "") else @as([]const u8, ","),
                    entry.keySlice(),
                    entry.metaSlice(),
                }) catch break;
                pos += item.len;
                first = false;
            }
        }

        if (pos < buf.len) {
            buf[pos] = ']';
            pos += 1;
        }

        return buf[0..pos];
    }

    /// Get a diff of presences for a topic as JSON: {"joins":[...],"leaves":[...]}.
    /// Currently returns current state as joins (full sync). Incremental diffs
    /// would require tracking previous state.
    pub fn diff(topic: []const u8, buf: []u8) []const u8 {
        var list_buf: [4096]u8 = undefined;
        const current = list(topic, &list_buf);

        return std.fmt.bufPrint(buf,
            \\{{"joins":{s},"leaves":[]}}
        , .{current}) catch "";
    }

    /// Reset all state (for testing).
    pub fn reset() void {
        spinLock(&mutex);
        defer mutex.unlock();
        for (&entries) |*entry| {
            entry.active = false;
        }
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;
const Params = @import("../../middleware/context.zig").Params;
const Assigns = @import("../../middleware/context.zig").Assigns;

const MockWriter = struct {
    buf: [4096]u8 = undefined,
    pos: usize = 0,

    pub fn writeAll(self: *MockWriter, data: []const u8) !void {
        if (self.pos + data.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..data.len], data);
        self.pos += data.len;
    }

    pub fn flush(_: *MockWriter) !void {}
};

const WriterVTable = @import("../websocket/connection.zig").WriterVTable;

const TestSocketPair = struct {
    ws: WebSocket,
    socket: Socket,
};

fn makeTestWs(writer: *MockWriter) WebSocket {
    const VTable = WriterVTable(MockWriter);
    return .{
        .allocator = testing.allocator,
        .closed = false,
        .params = .{},
        .query = .{},
        .assigns = .{},
        .writer_ctx = @ptrCast(writer),
        .write_fn = &VTable.writeAll,
        .flush_fn = &VTable.flush,
    };
}

test "Presence track and list" {
    Presence.reset();
    var w: MockWriter = .{};
    var ws = makeTestWs(&w);
    var sock: Socket = .{ .ws = &ws, .active = true };

    try testing.expect(Presence.track(&sock, "room:lobby", "user1", "{\"name\":\"Alice\"}"));

    var buf: [4096]u8 = undefined;
    const result = Presence.list("room:lobby", &buf);
    try testing.expect(std.mem.indexOf(u8, result, "\"key\":\"user1\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\":\"Alice\"") != null);
}

test "Presence untrack" {
    Presence.reset();
    var w: MockWriter = .{};
    var ws = makeTestWs(&w);
    var sock: Socket = .{ .ws = &ws, .active = true };

    _ = Presence.track(&sock, "room:lobby", "user1", "{}");
    Presence.untrack(&sock, "room:lobby");

    var buf: [4096]u8 = undefined;
    const result = Presence.list("room:lobby", &buf);
    try testing.expectEqualStrings("[]", result);
}

test "Presence untrackAll" {
    Presence.reset();
    var w: MockWriter = .{};
    var ws = makeTestWs(&w);
    var sock: Socket = .{ .ws = &ws, .active = true };

    _ = Presence.track(&sock, "room:lobby", "user1", "{}");
    _ = Presence.track(&sock, "room:chat", "user1", "{}");
    Presence.untrackAll(&sock);

    var buf: [4096]u8 = undefined;
    const lobby = Presence.list("room:lobby", &buf);
    try testing.expectEqualStrings("[]", lobby);
    const chat = Presence.list("room:chat", &buf);
    try testing.expectEqualStrings("[]", chat);
}
