const std = @import("std");
const Method = @import("../core/http/request.zig").Method;
const Params = @import("../middleware/context.zig").Params;
const Context = @import("../middleware/context.zig").Context;
const HandlerFn = @import("../middleware/context.zig").HandlerFn;

/// A single segment of a route pattern.
pub const Segment = union(enum) {
    static: []const u8,
    param: []const u8,
    wildcard: []const u8,
};

/// A compiled route ready for matching.
pub const CompiledRoute = struct {
    method: Method,
    segments: []const Segment,
    handler: HandlerFn,
    middleware: []const HandlerFn,
};

/// Result of a successful route match.
pub const MatchResult = struct {
    route_index: usize,
    params: Params,
};

/// Compile a route pattern string into segments at comptime.
pub fn compilePattern(comptime pattern: []const u8) []const Segment {
    comptime {
        // Root path "/" has zero segments
        if (pattern.len == 0 or (pattern.len == 1 and pattern[0] == '/')) {
            return &.{};
        }

        // Count segments first
        var count: usize = 0;
        var start: usize = 0;
        if (pattern[0] == '/') start = 1;
        var i: usize = start;
        while (i <= pattern.len) : (i += 1) {
            if (i == pattern.len or pattern[i] == '/') {
                if (i > start) count += 1;
                start = i + 1;
            }
        }

        // Build segments
        var segments: [count]Segment = undefined;
        var seg_idx: usize = 0;
        start = 0;
        if (pattern[0] == '/') start = 1;
        i = start;
        while (i <= pattern.len) : (i += 1) {
            if (i == pattern.len or pattern[i] == '/') {
                if (i > start) {
                    const part = pattern[start..i];
                    if (part[0] == ':') {
                        segments[seg_idx] = .{ .param = part[1..] };
                    } else if (part[0] == '*') {
                        segments[seg_idx] = .{ .wildcard = part[1..] };
                    } else {
                        segments[seg_idx] = .{ .static = part };
                    }
                    seg_idx += 1;
                }
                start = i + 1;
            }
        }

        const final = segments;
        return &final;
    }
}

/// Try to match a runtime path against comptime-known segments.
pub fn matchSegments(comptime segments: []const Segment, path: []const u8) ?Params {
    var params: Params = .{};

    // Normalize: strip leading slash
    var path_content = path;
    if (path_content.len > 0 and path_content[0] == '/') {
        path_content = path_content[1..];
    }
    // Strip query string
    if (std.mem.indexOfScalar(u8, path_content, '?')) |q| {
        path_content = path_content[0..q];
    }
    // Strip trailing slash
    if (path_content.len > 0 and path_content[path_content.len - 1] == '/') {
        path_content = path_content[0 .. path_content.len - 1];
    }

    // Root path (no segments) matches empty path
    if (segments.len == 0) {
        return if (path_content.len == 0) params else null;
    }

    var path_pos: usize = 0;

    inline for (segments) |segment| {
        switch (segment) {
            .wildcard => |name| {
                params.put(name, path_content[path_pos..]);
                return params;
            },
            .static => |expected| {
                const seg_end = nextSlash(path_content, path_pos);
                if (seg_end == path_pos) return null;
                const actual = path_content[path_pos..seg_end];
                if (!std.mem.eql(u8, actual, expected)) return null;
                path_pos = if (seg_end < path_content.len) seg_end + 1 else seg_end;
            },
            .param => |name| {
                const seg_end = nextSlash(path_content, path_pos);
                if (seg_end == path_pos) return null;
                params.put(name, path_content[path_pos..seg_end]);
                path_pos = if (seg_end < path_content.len) seg_end + 1 else seg_end;
            },
        }
    }

    return if (path_pos >= path_content.len) params else null;
}

/// Find the next '/' in the path starting from `start`, or return path.len.
fn nextSlash(path: []const u8, start: usize) usize {
    var i = start;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') return i;
    }
    return path.len;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "compilePattern root" {
    const segs = comptime compilePattern("/");
    try std.testing.expectEqual(@as(usize, 0), segs.len);
}

test "compilePattern static" {
    const segs = comptime compilePattern("/users/list");
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("users", segs[0].static);
    try std.testing.expectEqualStrings("list", segs[1].static);
}

test "compilePattern with param" {
    const segs = comptime compilePattern("/users/:id");
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("users", segs[0].static);
    try std.testing.expectEqualStrings("id", segs[1].param);
}

test "compilePattern with wildcard" {
    const segs = comptime compilePattern("/files/*path");
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("files", segs[0].static);
    try std.testing.expectEqualStrings("path", segs[1].wildcard);
}

test "matchSegments root path" {
    try std.testing.expect(matchSegments(comptime compilePattern("/"), "/") != null);
    try std.testing.expect(matchSegments(comptime compilePattern("/"), "/hello") == null);
}

test "matchSegments static path" {
    try std.testing.expect(matchSegments(comptime compilePattern("/users/list"), "/users/list") != null);
    try std.testing.expect(matchSegments(comptime compilePattern("/users/list"), "/users/other") == null);
    try std.testing.expect(matchSegments(comptime compilePattern("/users/list"), "/users") == null);
}

test "matchSegments with param extraction" {
    const result = matchSegments(comptime compilePattern("/users/:id"), "/users/42");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("42", result.?.get("id").?);
}

test "matchSegments with wildcard" {
    const result = matchSegments(comptime compilePattern("/files/*path"), "/files/a/b/c");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("a/b/c", result.?.get("path").?);
}

test "matchSegments strips query string" {
    const result = matchSegments(comptime compilePattern("/users/:id"), "/users/42?tab=posts");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("42", result.?.get("id").?);
}

test "matchSegments trailing slash tolerance" {
    try std.testing.expect(matchSegments(comptime compilePattern("/hello"), "/hello/") != null);
}
