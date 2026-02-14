const std = @import("std");
const Allocator = std.mem.Allocator;
const html_escape = @import("html_escape.zig");

/// A single segment of a parsed template.
pub const Segment = union(enum) {
    literal: []const u8,
    variable: []const u8,
    raw_variable: []const u8,
    conditional: Conditional,
    loop: Loop,
    comment: void,

    pub const Conditional = struct {
        condition: []const u8,
        then_body: []const Segment,
        else_body: []const Segment,
    };

    pub const Loop = struct {
        collection: []const u8,
        body: []const Segment,
    };
};

/// Parse result from an inner parse call.
const ParseResult = struct {
    segments: []const Segment,
    consumed: usize,
};

/// Compile a template string into segments at comptime.
pub fn parse(comptime source: []const u8) []const Segment {
    comptime {
        @setEvalBranchQuota(100_000);
        const result = parseInner(source, null);
        return result.segments;
    }
}

/// Recursive inner parser. When `end_marker` is set, stops at that closing tag.
fn parseInner(comptime source: []const u8, comptime end_marker: ?[]const u8) ParseResult {
    comptime {
        @setEvalBranchQuota(100_000);

        // Pass 1: count segments
        const count = countSegments(source, end_marker);

        // Pass 2: build segments
        var segments: [count.n]Segment = undefined;
        var seg_idx: usize = 0;
        var pos: usize = 0;

        while (pos < source.len) {
            // Check for end marker
            if (end_marker) |marker| {
                if (pos + marker.len <= source.len and
                    eql(source[pos .. pos + marker.len], marker))
                {
                    break;
                }
            }

            // Look for next tag
            if (findTag(source, pos)) |tag| {
                // Literal before the tag
                if (tag.start > pos) {
                    segments[seg_idx] = .{ .literal = source[pos..tag.start] };
                    seg_idx += 1;
                }

                // Process the tag
                const tag_result = processTag(source, tag);
                segments[seg_idx] = tag_result.segment;
                seg_idx += 1;
                pos = tag_result.next_pos;
            } else {
                // Rest is literal
                const end_pos = if (end_marker) |marker|
                    indexOf(source, marker, pos) orelse source.len
                else
                    source.len;
                if (end_pos > pos) {
                    segments[seg_idx] = .{ .literal = source[pos..end_pos] };
                    seg_idx += 1;
                }
                pos = end_pos;
            }
        }

        const final = segments;
        return .{
            .segments = &final,
            .consumed = if (end_marker) |marker|
                pos + marker.len
            else
                pos,
        };
    }
}

/// A located tag in the source.
const TagInfo = struct {
    start: usize, // position of first '{'
    content: []const u8, // trimmed content between delimiters
    end: usize, // position after last '}'
    is_raw: bool, // triple-brace {{{...}}}
};

/// Find the next template tag starting from `pos`.
fn findTag(comptime source: []const u8, comptime pos: usize) ?TagInfo {
    comptime {
        var i = pos;
        while (i + 1 < source.len) : (i += 1) {
            if (source[i] == '{' and source[i + 1] == '{') {
                // Triple brace?
                if (i + 2 < source.len and source[i + 2] == '{') {
                    // Find closing }}}
                    const close = indexOf(source, "}}}", i + 3) orelse
                        @compileError("Unclosed triple-brace tag");
                    return .{
                        .start = i,
                        .content = trim(source[i + 3 .. close]),
                        .end = close + 3,
                        .is_raw = true,
                    };
                }
                // Double brace
                const close = indexOf(source, "}}", i + 2) orelse
                    @compileError("Unclosed tag");
                return .{
                    .start = i,
                    .content = trim(source[i + 2 .. close]),
                    .end = close + 2,
                    .is_raw = false,
                };
            }
        }
        return null;
    }
}

/// Tag processing result.
const TagResult = struct {
    segment: Segment,
    next_pos: usize,
};

/// Process a single tag and return the resulting segment.
fn processTag(comptime source: []const u8, comptime tag: TagInfo) TagResult {
    comptime {
        const content = tag.content;

        // Raw variable: {{{name}}}
        if (tag.is_raw) {
            return .{ .segment = .{ .raw_variable = content }, .next_pos = tag.end };
        }

        // Comment: {{! ... }}
        if (content.len > 0 and content[0] == '!') {
            return .{ .segment = .{ .comment = {} }, .next_pos = tag.end };
        }

        // Block tags: {{#if ...}}, {{#each ...}}
        if (content.len > 1 and content[0] == '#') {
            const rest = trim(content[1..]);

            if (startsWith(rest, "if ")) {
                const cond = trim(rest[3..]);
                const else_marker = "{{else}}";
                const end_marker_str = "{{/if}}";

                // Parse then-body (from tag.end to either {{else}} or {{/if}})
                const after_tag = source[tag.end..];
                const else_pos = indexOf(after_tag, else_marker, 0);
                const end_pos = indexOf(after_tag, end_marker_str, 0) orelse
                    @compileError("Unclosed {{#if}} block — missing {{/if}}");

                if (else_pos) |ep| {
                    if (ep < end_pos) {
                        // Has else branch
                        const then_result = parseInner(after_tag[0..ep], null);
                        const else_start = ep + else_marker.len;
                        const else_result = parseInner(after_tag[else_start..end_pos], null);
                        return .{
                            .segment = .{ .conditional = .{
                                .condition = cond,
                                .then_body = then_result.segments,
                                .else_body = else_result.segments,
                            } },
                            .next_pos = tag.end + end_pos + end_marker_str.len,
                        };
                    }
                }

                // No else branch
                const then_result = parseInner(after_tag[0..end_pos], null);
                const empty: [0]Segment = .{};
                return .{
                    .segment = .{ .conditional = .{
                        .condition = cond,
                        .then_body = then_result.segments,
                        .else_body = &empty,
                    } },
                    .next_pos = tag.end + end_pos + end_marker_str.len,
                };
            }

            if (startsWith(rest, "each ")) {
                const collection = trim(rest[5..]);
                const end_marker_str = "{{/each}}";

                const after_tag = source[tag.end..];
                const end_pos = indexOf(after_tag, end_marker_str, 0) orelse
                    @compileError("Unclosed {{#each}} block — missing {{/each}}");

                const body_result = parseInner(after_tag[0..end_pos], null);
                return .{
                    .segment = .{ .loop = .{
                        .collection = collection,
                        .body = body_result.segments,
                    } },
                    .next_pos = tag.end + end_pos + end_marker_str.len,
                };
            }

            @compileError("Unknown block tag: {{#" ++ rest ++ "}}");
        }

        // Variable: {{name}}
        return .{ .segment = .{ .variable = content }, .next_pos = tag.end };
    }
}

/// Count segments (pass 1) — mirrors the logic of parseInner but only counts.
const CountResult = struct { n: usize, consumed: usize };

fn countSegments(comptime source: []const u8, comptime end_marker: ?[]const u8) CountResult {
    comptime {
        var n: usize = 0;
        var pos: usize = 0;

        while (pos < source.len) {
            if (end_marker) |marker| {
                if (pos + marker.len <= source.len and
                    eql(source[pos .. pos + marker.len], marker))
                {
                    break;
                }
            }

            if (findTag(source, pos)) |tag| {
                if (tag.start > pos) n += 1; // literal
                n += 1; // the tag itself

                // For block tags, skip past the closing tag
                const content = tag.content;
                if (!tag.is_raw and content.len > 1 and content[0] == '#') {
                    const rest = trim(content[1..]);
                    if (startsWith(rest, "if ")) {
                        const after_tag = source[tag.end..];
                        const end_pos = indexOf(after_tag, "{{/if}}", 0) orelse
                            @compileError("Unclosed {{#if}} block");
                        pos = tag.end + end_pos + "{{/if}}".len;
                    } else if (startsWith(rest, "each ")) {
                        const after_tag = source[tag.end..];
                        const end_pos = indexOf(after_tag, "{{/each}}", 0) orelse
                            @compileError("Unclosed {{#each}} block");
                        pos = tag.end + end_pos + "{{/each}}".len;
                    } else {
                        @compileError("Unknown block tag");
                    }
                } else {
                    pos = tag.end;
                }
            } else {
                const end_pos = if (end_marker) |marker|
                    indexOf(source, marker, pos) orelse source.len
                else
                    source.len;
                if (end_pos > pos) n += 1;
                pos = end_pos;
            }
        }

        return .{
            .n = n,
            .consumed = if (end_marker) |marker|
                pos + marker.len
            else
                pos,
        };
    }
}

// ── Comptime string helpers ────────────────────────────────────────────

fn eql(comptime a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

fn indexOf(comptime haystack: []const u8, comptime needle: []const u8, comptime start: usize) ?usize {
    if (needle.len == 0) return start;
    if (start + needle.len > haystack.len) return null;
    var i = start;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eql(haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn startsWith(comptime s: []const u8, comptime prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return eql(s[0..prefix.len], prefix);
}

fn trim(comptime s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) {
        start += 1;
    }
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n' or s[end - 1] == '\r')) {
        end -= 1;
    }
    return s[start..end];
}

// ── Public API ─────────────────────────────────────────────────────────

/// Compile a template at comptime and return a type with a `render` method.
///
/// Usage:
/// ```
/// const tmpl = zzz.template(@embedFile("templates/index.html.zzz"));
///
/// fn handler(ctx: *zzz.Context) !void {
///     try ctx.render(tmpl, .ok, .{ .title = "Hello" });
/// }
/// ```
pub fn template(comptime source: []const u8) type {
    const segments = comptime parse(source);
    return struct {
        pub fn render(allocator: Allocator, data: anytype) ![]const u8 {
            var buf: std.ArrayList(u8) = .empty;
            errdefer buf.deinit(allocator);
            try renderSegments(segments, data, &buf, allocator);
            return buf.toOwnedSlice(allocator);
        }
    };
}

/// Walk the comptime segment tree at runtime, rendering into a buffer.
fn renderSegments(comptime segments: []const Segment, data: anytype, buf: *std.ArrayList(u8), allocator: Allocator) !void {
    inline for (segments) |seg| {
        switch (seg) {
            .literal => |text| {
                try buf.appendSlice(allocator, text);
            },
            .variable => |path| {
                const value = resolveField(data, path);
                const str = coerceToString(value);
                try html_escape.appendEscaped(buf, allocator, str);
            },
            .raw_variable => |path| {
                const value = resolveField(data, path);
                const str = coerceToString(value);
                try buf.appendSlice(allocator, str);
            },
            .conditional => |cond| {
                const truthy = resolveBool(data, cond.condition);
                if (truthy) {
                    try renderSegments(cond.then_body, data, buf, allocator);
                } else {
                    try renderSegments(cond.else_body, data, buf, allocator);
                }
            },
            .loop => |lp| {
                const slice = resolveSlice(data, lp.collection);
                for (slice) |item| {
                    try renderSegments(lp.body, item, buf, allocator);
                }
            },
            .comment => {},
        }
    }
}

// ── Field resolution ───────────────────────────────────────────────────

/// Resolve a dotted field path on a struct at comptime.
/// E.g. resolveField(data, "user.name") → @field(@field(data, "user"), "name")
inline fn resolveField(data: anytype, comptime path: []const u8) @TypeOf(resolveFieldType(data, path)) {
    const dot = comptime indexOf(path, ".", 0);
    if (comptime dot) |d| {
        return resolveField(@field(data, path[0..d]), path[d + 1 ..]);
    } else {
        return @field(data, path);
    }
}

/// Helper to let the compiler infer the resolved type for the return annotation.
inline fn resolveFieldType(data: anytype, comptime path: []const u8) @TypeOf(blk: {
    const dot = comptime indexOf(path, ".", 0);
    if (comptime dot) |d| {
        break :blk resolveFieldType(@field(data, path[0..d]), path[d + 1 ..]);
    } else {
        break :blk @field(data, path);
    }
}) {
    const dot = comptime indexOf(path, ".", 0);
    if (comptime dot) |d| {
        return resolveFieldType(@field(data, path[0..d]), path[d + 1 ..]);
    } else {
        return @field(data, path);
    }
}

/// Resolve a field to a bool for conditionals.
/// Supports: bool, ?T (null → false), slices (empty → false).
inline fn resolveBool(data: anytype, comptime path: []const u8) bool {
    const value = resolveField(data, path);
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (T == bool) return value;

    if (info == .optional) {
        return value != null;
    }

    // Slice: non-empty is truthy
    if (info == .pointer and info.pointer.size == .slice) {
        return value.len > 0;
    }

    // Fallback: any non-void value is truthy
    return true;
}

/// Resolve a field to a slice for iteration.
inline fn resolveSlice(data: anytype, comptime path: []const u8) ResolveSliceReturn(@TypeOf(resolveField(data, path))) {
    const value = resolveField(data, path);
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Already a slice
    if (info == .pointer and info.pointer.size == .slice) {
        return value;
    }

    // Pointer to array
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return @as([]const child_info.array.child, value);
        }
    }

    @compileError("{{#each " ++ path ++ "}} requires a slice or pointer-to-array field");
}

fn ResolveSliceReturn(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .slice) {
        return T;
    }
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return []const child_info.array.child;
        }
    }
    @compileError("{{#each}} requires a slice or pointer-to-array field, got " ++ @typeName(T));
}

/// Coerce a value to a string for output.
inline fn coerceToString(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8) return value;
    if (T == []u8) return value;

    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        const child = @typeInfo(info.pointer.child);
        if (child == .array and child.array.child == u8) {
            return value;
        }
    }

    @compileError("Template variable must be []const u8, got " ++ @typeName(T));
}

// ── Tests ──────────────────────────────────────────────────────────────

test "literal only" {
    const T = template("Hello, world!");
    const result = try T.render(std.testing.allocator, .{});
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Hello, world!", result);
}

test "variable interpolation" {
    const T = template("Hello, {{name}}!");
    const result = try T.render(std.testing.allocator, .{ .name = "World" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "variable HTML escaping" {
    const T = template("{{content}}");
    const result = try T.render(std.testing.allocator, .{ .content = "<script>alert('xss')</script>" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;", result);
}

test "raw variable no escaping" {
    const T = template("{{{content}}}");
    const result = try T.render(std.testing.allocator, .{ .content = "<b>bold</b>" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("<b>bold</b>", result);
}

test "comment produces no output" {
    const T = template("before{{! this is a comment }}after");
    const result = try T.render(std.testing.allocator, .{});
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("beforeafter", result);
}

test "conditional true branch" {
    const T = template("{{#if show}}visible{{/if}}");
    const result = try T.render(std.testing.allocator, .{ .show = true });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("visible", result);
}

test "conditional false branch" {
    const T = template("{{#if show}}visible{{/if}}");
    const result = try T.render(std.testing.allocator, .{ .show = false });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "conditional with else" {
    const T = template("{{#if logged_in}}welcome{{else}}login{{/if}}");
    const result_t = try T.render(std.testing.allocator, .{ .logged_in = true });
    defer std.testing.allocator.free(result_t);
    try std.testing.expectEqualStrings("welcome", result_t);

    const result_f = try T.render(std.testing.allocator, .{ .logged_in = false });
    defer std.testing.allocator.free(result_f);
    try std.testing.expectEqualStrings("login", result_f);
}

test "loop iteration" {
    const Item = struct { name: []const u8 };
    const items = [_]Item{
        .{ .name = "Alice" },
        .{ .name = "Bob" },
    };
    const T = template("{{#each items}}{{name}} {{/each}}");
    const result = try T.render(std.testing.allocator, .{ .items = @as([]const Item, &items) });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Alice Bob ", result);
}

test "dot notation" {
    const T = template("{{user.name}}");
    const result = try T.render(std.testing.allocator, .{ .user = .{ .name = "Alice" } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Alice", result);
}

test "optional truthiness" {
    const T = template("{{#if maybe}}yes{{else}}no{{/if}}");
    const result_some = try T.render(std.testing.allocator, .{ .maybe = @as(?[]const u8, "hi") });
    defer std.testing.allocator.free(result_some);
    try std.testing.expectEqualStrings("yes", result_some);

    const result_null = try T.render(std.testing.allocator, .{ .maybe = @as(?[]const u8, null) });
    defer std.testing.allocator.free(result_null);
    try std.testing.expectEqualStrings("no", result_null);
}

test "slice truthiness" {
    const Item = struct { x: []const u8 };
    const empty: []const Item = &.{};
    const T = template("{{#if items}}has items{{else}}empty{{/if}}");

    const result_empty = try T.render(std.testing.allocator, .{ .items = empty });
    defer std.testing.allocator.free(result_empty);
    try std.testing.expectEqualStrings("empty", result_empty);

    const items = [_]Item{.{ .x = "a" }};
    const result_full = try T.render(std.testing.allocator, .{ .items = @as([]const Item, &items) });
    defer std.testing.allocator.free(result_full);
    try std.testing.expectEqualStrings("has items", result_full);
}

test "full template" {
    const Route = struct { href: []const u8, label: []const u8 };
    const routes = [_]Route{
        .{ .href = "/about", .label = "About" },
        .{ .href = "/api", .label = "API" },
    };
    const T = template(
        \\<h1>{{title}}</h1>
        \\<p>Hello, {{name}}!</p>
        \\{{#if show_routes}}<ul>
        \\{{#each routes}}<li><a href="{{href}}">{{label}}</a></li>
        \\{{/each}}</ul>{{/if}}
    );
    const result = try T.render(std.testing.allocator, .{
        .title = "Test",
        .name = "World",
        .show_routes = true,
        .routes = @as([]const Route, &routes),
    });
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<h1>Test</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello, World!") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/about") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "API") != null);
}
