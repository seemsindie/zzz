const std = @import("std");
const Allocator = std.mem.Allocator;

/// Append HTML-escaped text to a buffer. Escapes &, <, >, ", '.
pub fn appendEscaped(buf: *std.ArrayList(u8), allocator: Allocator, input: []const u8) !void {
    var start: usize = 0;
    for (input, 0..) |ch, i| {
        const entity: ?[]const u8 = switch (ch) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&#x27;",
            else => null,
        };
        if (entity) |ent| {
            if (i > start) try buf.appendSlice(allocator, input[start..i]);
            try buf.appendSlice(allocator, ent);
            start = i + 1;
        }
    }
    if (start < input.len) try buf.appendSlice(allocator, input[start..]);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "empty string" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscaped(&buf, std.testing.allocator, "");
    try std.testing.expectEqualStrings("", buf.items);
}

test "no special chars" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscaped(&buf, std.testing.allocator, "hello world");
    try std.testing.expectEqualStrings("hello world", buf.items);
}

test "all special chars" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscaped(&buf, std.testing.allocator, "&<>\"'");
    try std.testing.expectEqualStrings("&amp;&lt;&gt;&quot;&#x27;", buf.items);
}

test "mixed content" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscaped(&buf, std.testing.allocator, "<script>alert('xss')</script>");
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;", buf.items);
}
