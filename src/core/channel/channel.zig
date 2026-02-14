const std = @import("std");
const Socket = @import("socket.zig").Socket;

/// Result of a channel join attempt.
pub const JoinResult = enum { ok, @"error" };

/// An event handler binding: maps an event name to a handler function.
pub const EventHandler = struct {
    event: []const u8,
    handler: *const fn (*Socket, []const u8, []const u8, []const u8) void,
    // handler(socket, topic, event, payload_json)
};

/// Default join handler — always allows joining.
fn defaultJoin(_: *Socket, _: []const u8, _: []const u8) JoinResult {
    return .ok;
}

/// A channel definition: topic pattern + join/leave/event handlers.
pub const ChannelDef = struct {
    topic_pattern: []const u8, // "room:*" or "notifications"
    join: *const fn (*Socket, []const u8, []const u8) JoinResult = &defaultJoin,
    // join(socket, topic, payload_json) -> JoinResult
    leave: ?*const fn (*Socket, []const u8) void = null,
    // leave(socket, topic)
    handlers: []const EventHandler = &.{},
};

/// Check if a topic matches a channel pattern.
/// "room:*" matches anything starting with "room:"
/// "notifications" matches only "notifications"
pub fn topicMatchesPattern(comptime pattern: []const u8, topic: []const u8) bool {
    if (comptime std.mem.endsWith(u8, pattern, ":*")) {
        const prefix = comptime pattern[0 .. pattern.len - 1]; // "room:"
        return topic.len >= prefix.len and std.mem.eql(u8, topic[0..prefix.len], prefix);
    } else {
        return std.mem.eql(u8, topic, pattern);
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "topicMatchesPattern exact match" {
    try testing.expect(topicMatchesPattern("notifications", "notifications"));
    try testing.expect(!topicMatchesPattern("notifications", "other"));
    try testing.expect(!topicMatchesPattern("notifications", "notifications:extra"));
}

test "topicMatchesPattern wildcard match" {
    try testing.expect(topicMatchesPattern("room:*", "room:lobby"));
    try testing.expect(topicMatchesPattern("room:*", "room:123"));
    try testing.expect(topicMatchesPattern("room:*", "room:"));
    try testing.expect(!topicMatchesPattern("room:*", "other:lobby"));
    try testing.expect(!topicMatchesPattern("room:*", "room"));
}

test "topicMatchesPattern no match" {
    try testing.expect(!topicMatchesPattern("room:*", "chat:lobby"));
    try testing.expect(!topicMatchesPattern("exact", "exact2"));
    try testing.expect(!topicMatchesPattern("exact", "exac"));
}
