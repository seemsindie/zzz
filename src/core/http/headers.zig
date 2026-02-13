const std = @import("std");
const Allocator = std.mem.Allocator;

/// HTTP header storage using an unmanaged ArrayList.
pub const Headers = struct {
    pub const Entry = struct {
        name: []const u8,
        value: []const u8,
    };

    entries: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *Headers, allocator: Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn append(self: *Headers, allocator: Allocator, name: []const u8, value: []const u8) !void {
        try self.entries.append(allocator, .{ .name = name, .value = value });
    }

    /// Get the first value for a header name (case-insensitive).
    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        for (self.entries.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                return entry.value;
            }
        }
        return null;
    }

    /// Get all values for a header name (case-insensitive).
    pub fn getAll(self: *const Headers, allocator: Allocator, name: []const u8) ![]const []const u8 {
        var result: std.ArrayList([]const u8) = .empty;
        for (self.entries.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                try result.append(allocator, entry.value);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// Check if a header exists (case-insensitive).
    pub fn contains(self: *const Headers, name: []const u8) bool {
        return self.get(name) != null;
    }

    pub fn count(self: *const Headers) usize {
        return self.entries.items.len;
    }

    /// Write all headers to a writer in "Name: Value\r\n" format.
    pub fn writeTo(self: *const Headers, writer: anytype) !void {
        for (self.entries.items) |entry| {
            try writer.writeAll(entry.name);
            try writer.writeAll(": ");
            try writer.writeAll(entry.value);
            try writer.writeAll("\r\n");
        }
    }
};

test "headers basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var h: Headers = .{};
    defer h.deinit(allocator);

    try h.append(allocator, "Content-Type", "text/html");
    try h.append(allocator, "X-Custom", "value1");
    try h.append(allocator, "X-Custom", "value2");

    try testing.expectEqualStrings("text/html", h.get("Content-Type").?);
    try testing.expectEqualStrings("text/html", h.get("content-type").?); // case-insensitive
    try testing.expect(h.get("Nonexistent") == null);
    try testing.expectEqual(@as(usize, 3), h.count());

    const all = try h.getAll(allocator, "X-Custom");
    defer allocator.free(all);
    try testing.expectEqual(@as(usize, 2), all.len);
}
