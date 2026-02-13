const std = @import("std");
const Context = @import("context.zig").Context;

// ── Types ──────────────────────────────────────────────────────────────

/// Fixed-size key-value store for parsed form fields (zero-allocation).
pub const FormData = struct {
    pub const max_fields = 32;

    entries: [max_fields]Entry = undefined,
    len: usize = 0,

    pub const Entry = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn get(self: *const FormData, name: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn put(self: *FormData, name: []const u8, value: []const u8) void {
        if (self.len < max_fields) {
            self.entries[self.len] = .{ .name = name, .value = value };
            self.len += 1;
        }
    }

    pub fn count(self: *const FormData) usize {
        return self.len;
    }
};

/// A single uploaded file from multipart form data.
pub const FilePart = struct {
    field_name: []const u8,
    filename: []const u8,
    content_type: []const u8,
    data: []const u8,
};

/// Parsed multipart data: form fields + file uploads.
pub const MultipartData = struct {
    fields: FormData = .{},
    files: [max_files]FilePart = undefined,
    file_count: usize = 0,

    const max_files = 8;

    pub fn file(self: *const MultipartData, field_name: []const u8) ?*const FilePart {
        for (self.files[0..self.file_count]) |*f| {
            if (std.mem.eql(u8, f.field_name, field_name)) return f;
        }
        return null;
    }
};

/// Tagged union of all parsed body types.
pub const ParsedBody = union(enum) {
    none,
    json: FormData,
    form: FormData,
    multipart: MultipartData,
    text: []const u8,
    binary: []const u8,
};

// ── URL Decoding ───────────────────────────────────────────────────────

/// Decode percent-encoded string. Converts %XX hex sequences and + to space.
/// Caller owns the returned memory.
pub fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '+') {
            try list.append(allocator, ' ');
            i += 1;
        } else if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hi = hexVal(encoded[i + 1]) orelse {
                try list.append(allocator, encoded[i]);
                i += 1;
                continue;
            };
            const lo = hexVal(encoded[i + 2]) orelse {
                try list.append(allocator, encoded[i]);
                i += 1;
                continue;
            };
            try list.append(allocator, (hi << 4) | lo);
            i += 3;
        } else {
            try list.append(allocator, encoded[i]);
            i += 1;
        }
    }

    return list.toOwnedSlice(allocator);
}

fn hexVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

// ── Parsers ────────────────────────────────────────────────────────────

/// Parse URL-encoded body (key=value&key2=value2) into FormData.
/// Values are raw slices into the body (not percent-decoded).
fn parseUrlEncoded(body: []const u8) FormData {
    var fd: FormData = .{};
    if (body.len == 0) return fd;

    var iter = std.mem.splitScalar(u8, body, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;
        if (fd.len >= FormData.max_fields) break;

        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            fd.put(pair[0..eq], pair[eq + 1 ..]);
        } else {
            fd.put(pair, "");
        }
    }
    return fd;
}

/// Parse top-level JSON string/number/bool fields into FormData.
/// Nested objects and arrays are skipped. Values are raw slices into the body.
fn parseJsonFields(body: []const u8) FormData {
    var fd: FormData = .{};
    if (body.len == 0) return fd;

    // Use a simple manual parser for top-level object fields.
    // We need to find top-level "key": value pairs where value is string, number, or bool.
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return fd;

    var i: usize = 1; // skip opening {
    while (i < trimmed.len and fd.len < FormData.max_fields) {
        // Skip whitespace
        i = skipWhitespace(trimmed, i);
        if (i >= trimmed.len or trimmed[i] == '}') break;

        // Skip comma
        if (trimmed[i] == ',') {
            i += 1;
            continue;
        }

        // Expect a quoted key
        if (trimmed[i] != '"') break;
        const key_start = i + 1;
        const key_end = findClosingQuote(trimmed, key_start) orelse break;
        const key = trimmed[key_start..key_end];
        i = key_end + 1;

        // Skip whitespace and colon
        i = skipWhitespace(trimmed, i);
        if (i >= trimmed.len or trimmed[i] != ':') break;
        i += 1;
        i = skipWhitespace(trimmed, i);
        if (i >= trimmed.len) break;

        // Parse value
        if (trimmed[i] == '"') {
            // String value — slice into the body
            const val_start = i + 1;
            const val_end = findClosingQuote(trimmed, val_start) orelse break;
            fd.put(key, trimmed[val_start..val_end]);
            i = val_end + 1;
        } else if (trimmed[i] == '{') {
            // Nested object — skip it
            i = skipNested(trimmed, i, '{', '}') orelse break;
        } else if (trimmed[i] == '[') {
            // Array — skip it
            i = skipNested(trimmed, i, '[', ']') orelse break;
        } else if (trimmed[i] == 't' or trimmed[i] == 'f' or trimmed[i] == 'n') {
            // true, false, null — extract as-is for true/false, skip null
            const val_start = i;
            while (i < trimmed.len and trimmed[i] != ',' and trimmed[i] != '}' and trimmed[i] != ' ' and trimmed[i] != '\n' and trimmed[i] != '\r' and trimmed[i] != '\t') : (i += 1) {}
            const val = trimmed[val_start..i];
            if (!std.mem.eql(u8, val, "null")) {
                fd.put(key, val);
            }
        } else {
            // Number — extract raw slice
            const val_start = i;
            while (i < trimmed.len and trimmed[i] != ',' and trimmed[i] != '}' and trimmed[i] != ' ' and trimmed[i] != '\n' and trimmed[i] != '\r' and trimmed[i] != '\t') : (i += 1) {}
            fd.put(key, trimmed[val_start..i]);
        }
    }
    return fd;
}

fn skipWhitespace(data: []const u8, start: usize) usize {
    var i = start;
    while (i < data.len and (data[i] == ' ' or data[i] == '\t' or data[i] == '\r' or data[i] == '\n')) : (i += 1) {}
    return i;
}

fn findClosingQuote(data: []const u8, start: usize) ?usize {
    var i = start;
    while (i < data.len) : (i += 1) {
        if (data[i] == '\\') {
            i += 1; // skip escaped char
            continue;
        }
        if (data[i] == '"') return i;
    }
    return null;
}

fn skipNested(data: []const u8, start: usize, open: u8, close: u8) ?usize {
    var depth: usize = 0;
    var i = start;
    var in_string = false;
    while (i < data.len) : (i += 1) {
        if (in_string) {
            if (data[i] == '\\') {
                i += 1;
                continue;
            }
            if (data[i] == '"') in_string = false;
            continue;
        }
        if (data[i] == '"') {
            in_string = true;
        } else if (data[i] == open) {
            depth += 1;
        } else if (data[i] == close) {
            depth -= 1;
            if (depth == 0) return i + 1;
        }
    }
    return null;
}

/// Extract boundary value from a Content-Type header like
/// "multipart/form-data; boundary=----WebKitFormBoundary..."
fn extractBoundary(content_type: []const u8) ?[]const u8 {
    const marker = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, marker) orelse return null;
    var boundary = content_type[idx + marker.len ..];
    if (boundary.len == 0) return null;

    // Strip optional quotes
    if (boundary[0] == '"') {
        boundary = boundary[1..];
        if (std.mem.indexOfScalar(u8, boundary, '"')) |end| {
            boundary = boundary[0..end];
        }
    }

    // Trim trailing whitespace/semicolons
    while (boundary.len > 0 and (boundary[boundary.len - 1] == ' ' or boundary[boundary.len - 1] == ';' or boundary[boundary.len - 1] == '\r' or boundary[boundary.len - 1] == '\n')) {
        boundary = boundary[0 .. boundary.len - 1];
    }

    return if (boundary.len > 0) boundary else null;
}

/// Parse multipart/form-data body into MultipartData.
fn parseMultipart(body: []const u8, content_type: []const u8) MultipartData {
    var md: MultipartData = .{};
    const boundary = extractBoundary(content_type) orelse return md;

    // Build the delimiter: "--" + boundary
    var delim_buf: [256]u8 = undefined;
    if (boundary.len + 2 > delim_buf.len) return md;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    @memcpy(delim_buf[2 .. 2 + boundary.len], boundary);
    const delim = delim_buf[0 .. 2 + boundary.len];

    // Split body on delimiter
    var iter = std.mem.splitSequence(u8, body, delim);
    _ = iter.next(); // preamble before first boundary — discard

    while (iter.next()) |part| {
        // Skip closing boundary marker ("--\r\n" or "--")
        if (part.len >= 2 and part[0] == '-' and part[1] == '-') continue;

        // Each part starts with \r\n, then headers, then \r\n\r\n, then data
        const trimmed_part = if (part.len >= 2 and part[0] == '\r' and part[1] == '\n')
            part[2..]
        else
            part;

        // Find header/body separator
        const header_end = std.mem.indexOf(u8, trimmed_part, "\r\n\r\n") orelse continue;
        const headers_section = trimmed_part[0..header_end];
        var data = trimmed_part[header_end + 4 ..];

        // Trim trailing \r\n from data (before next boundary)
        if (data.len >= 2 and data[data.len - 2] == '\r' and data[data.len - 1] == '\n') {
            data = data[0 .. data.len - 2];
        }

        // Parse Content-Disposition
        var field_name: ?[]const u8 = null;
        var filename: ?[]const u8 = null;
        var part_content_type: []const u8 = "application/octet-stream";

        var header_iter = std.mem.splitSequence(u8, headers_section, "\r\n");
        while (header_iter.next()) |header_line| {
            if (std.ascii.startsWithIgnoreCase(header_line, "content-disposition:")) {
                const val = header_line["content-disposition:".len..];
                field_name = extractHeaderParam(val, "name");
                filename = extractHeaderParam(val, "filename");
            } else if (std.ascii.startsWithIgnoreCase(header_line, "content-type:")) {
                part_content_type = std.mem.trim(u8, header_line["content-type:".len..], " \t");
            }
        }

        const name = field_name orelse continue;

        if (filename) |fname| {
            // File upload
            if (md.file_count < MultipartData.max_files) {
                md.files[md.file_count] = .{
                    .field_name = name,
                    .filename = fname,
                    .content_type = part_content_type,
                    .data = data,
                };
                md.file_count += 1;
            }
        } else {
            // Regular form field
            md.fields.put(name, data);
        }
    }
    return md;
}

/// Extract a named parameter value from a header value string.
/// E.g. extractHeaderParam(` form-data; name="field1"`, "name") => "field1"
fn extractHeaderParam(header_val: []const u8, param_name: []const u8) ?[]const u8 {
    // Search for param_name= or param_name="
    var search_buf: [64]u8 = undefined;
    if (param_name.len + 1 > search_buf.len) return null;
    @memcpy(search_buf[0..param_name.len], param_name);
    search_buf[param_name.len] = '=';
    const search = search_buf[0 .. param_name.len + 1];

    const idx = std.mem.indexOf(u8, header_val, search) orelse return null;
    var rest = header_val[idx + search.len ..];
    rest = std.mem.trimStart(u8, rest, " \t");

    if (rest.len == 0) return null;

    if (rest[0] == '"') {
        // Quoted value
        rest = rest[1..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return rest;
        return rest[0..end];
    } else {
        // Unquoted value — up to ; or end
        var end: usize = 0;
        while (end < rest.len and rest[end] != ';' and rest[end] != ' ' and rest[end] != '\r' and rest[end] != '\n') : (end += 1) {}
        return if (end > 0) rest[0..end] else null;
    }
}

// ── Middleware ──────────────────────────────────────────────────────────

/// Body parser middleware. Parses request body based on Content-Type into
/// `ctx.parsed_body`. Handles JSON, URL-encoded forms, multipart/form-data,
/// text, and raw binary.
pub fn bodyParser(ctx: *Context) !void {
    if (ctx.request.body) |body| {
        if (body.len > 0) {
            const ct = ctx.request.contentType() orelse "";

            if (startsWithIgnoreCase(ct, "application/json")) {
                ctx.parsed_body = .{ .json = parseJsonFields(body) };
            } else if (startsWithIgnoreCase(ct, "application/x-www-form-urlencoded")) {
                ctx.parsed_body = .{ .form = parseUrlEncoded(body) };
            } else if (startsWithIgnoreCase(ct, "multipart/form-data")) {
                ctx.parsed_body = .{ .multipart = parseMultipart(body, ct) };
            } else if (startsWithIgnoreCase(ct, "text/")) {
                ctx.parsed_body = .{ .text = body };
            } else {
                ctx.parsed_body = .{ .binary = body };
            }
        }
    }
    try ctx.next();
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "parseUrlEncoded: basic pairs" {
    const fd = parseUrlEncoded("name=zig&lang=systems");
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("zig", fd.get("name").?);
    try std.testing.expectEqualStrings("systems", fd.get("lang").?);
}

test "parseUrlEncoded: empty value" {
    const fd = parseUrlEncoded("key=&other=val");
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("", fd.get("key").?);
    try std.testing.expectEqualStrings("val", fd.get("other").?);
}

test "parseUrlEncoded: no equals" {
    const fd = parseUrlEncoded("standalone&key=val");
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("", fd.get("standalone").?);
    try std.testing.expectEqualStrings("val", fd.get("key").?);
}

test "parseUrlEncoded: multiple same-name keys" {
    const fd = parseUrlEncoded("tag=a&tag=b&tag=c");
    try std.testing.expectEqual(@as(usize, 3), fd.count());
    // get returns first match
    try std.testing.expectEqualStrings("a", fd.get("tag").?);
}

test "parseUrlEncoded: empty body" {
    const fd = parseUrlEncoded("");
    try std.testing.expectEqual(@as(usize, 0), fd.count());
}

test "parseJsonFields: strings" {
    const fd = parseJsonFields(
        \\{"name":"zig","lang":"systems"}
    );
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("zig", fd.get("name").?);
    try std.testing.expectEqualStrings("systems", fd.get("lang").?);
}

test "parseJsonFields: numbers" {
    const fd = parseJsonFields(
        \\{"ver":1,"pi":3.14}
    );
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("1", fd.get("ver").?);
    try std.testing.expectEqualStrings("3.14", fd.get("pi").?);
}

test "parseJsonFields: booleans" {
    const fd = parseJsonFields(
        \\{"active":true,"deleted":false}
    );
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("true", fd.get("active").?);
    try std.testing.expectEqualStrings("false", fd.get("deleted").?);
}

test "parseJsonFields: nested objects skipped" {
    const fd = parseJsonFields(
        \\{"name":"zig","meta":{"v":1},"ok":true}
    );
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("zig", fd.get("name").?);
    try std.testing.expectEqualStrings("true", fd.get("ok").?);
    try std.testing.expect(fd.get("meta") == null);
}

test "parseJsonFields: arrays skipped" {
    const fd = parseJsonFields(
        \\{"name":"zig","tags":["fast","safe"]}
    );
    try std.testing.expectEqual(@as(usize, 1), fd.count());
    try std.testing.expectEqualStrings("zig", fd.get("name").?);
    try std.testing.expect(fd.get("tags") == null);
}

test "parseJsonFields: null skipped" {
    const fd = parseJsonFields(
        \\{"name":"zig","deleted":null}
    );
    try std.testing.expectEqual(@as(usize, 1), fd.count());
    try std.testing.expectEqualStrings("zig", fd.get("name").?);
    try std.testing.expect(fd.get("deleted") == null);
}

test "parseMultipart: fields only" {
    const body = "--boundary\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--boundary\r\nContent-Disposition: form-data; name=\"field2\"\r\n\r\nvalue2\r\n--boundary--\r\n";
    const md = parseMultipart(body, "multipart/form-data; boundary=boundary");
    try std.testing.expectEqual(@as(usize, 2), md.fields.count());
    try std.testing.expectEqualStrings("value1", md.fields.get("field1").?);
    try std.testing.expectEqualStrings("value2", md.fields.get("field2").?);
    try std.testing.expectEqual(@as(usize, 0), md.file_count);
}

test "parseMultipart: files only" {
    const body = "--boundary\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nFILEDATA\r\n--boundary--\r\n";
    const md = parseMultipart(body, "multipart/form-data; boundary=boundary");
    try std.testing.expectEqual(@as(usize, 0), md.fields.count());
    try std.testing.expectEqual(@as(usize, 1), md.file_count);
    const f = md.file("avatar").?;
    try std.testing.expectEqualStrings("avatar", f.field_name);
    try std.testing.expectEqualStrings("photo.jpg", f.filename);
    try std.testing.expectEqualStrings("image/jpeg", f.content_type);
    try std.testing.expectEqualStrings("FILEDATA", f.data);
}

test "parseMultipart: mixed fields and files" {
    const body = "--boundary\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nzig\r\n--boundary\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"readme.txt\"\r\nContent-Type: text/plain\r\n\r\nhello world\r\n--boundary--\r\n";
    const md = parseMultipart(body, "multipart/form-data; boundary=boundary");
    try std.testing.expectEqual(@as(usize, 1), md.fields.count());
    try std.testing.expectEqualStrings("zig", md.fields.get("name").?);
    try std.testing.expectEqual(@as(usize, 1), md.file_count);
    const f = md.file("doc").?;
    try std.testing.expectEqualStrings("readme.txt", f.filename);
    try std.testing.expectEqualStrings("hello world", f.data);
}

test "urlDecode: percent encoding" {
    const result = try urlDecode(std.testing.allocator, "hello%20world%21");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello world!", result);
}

test "urlDecode: plus to space" {
    const result = try urlDecode(std.testing.allocator, "hello+world");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "urlDecode: passthrough" {
    const result = try urlDecode(std.testing.allocator, "abc123");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("abc123", result);
}

test "urlDecode: mixed encoding" {
    const result = try urlDecode(std.testing.allocator, "a%2Fb%3Dc+d");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("a/b=c d", result);
}

test "urlDecode: invalid percent sequence" {
    const result = try urlDecode(std.testing.allocator, "100%XY done");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("100%XY done", result);
}

test "urlDecode: trailing percent" {
    const result = try urlDecode(std.testing.allocator, "trail%");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("trail%", result);
}

test "extractBoundary: basic" {
    const b = extractBoundary("multipart/form-data; boundary=abc123");
    try std.testing.expectEqualStrings("abc123", b.?);
}

test "extractBoundary: quoted" {
    const b = extractBoundary("multipart/form-data; boundary=\"abc123\"");
    try std.testing.expectEqualStrings("abc123", b.?);
}

test "extractBoundary: missing" {
    try std.testing.expect(extractBoundary("multipart/form-data") == null);
}

test "extractBoundary: empty value" {
    try std.testing.expect(extractBoundary("multipart/form-data; boundary=") == null);
}

test "FormData: put and get" {
    var fd: FormData = .{};
    fd.put("key1", "val1");
    fd.put("key2", "val2");
    try std.testing.expectEqual(@as(usize, 2), fd.count());
    try std.testing.expectEqualStrings("val1", fd.get("key1").?);
    try std.testing.expectEqualStrings("val2", fd.get("key2").?);
    try std.testing.expect(fd.get("missing") == null);
}

test "FormData: overflow ignored" {
    var fd: FormData = .{};
    for (0..FormData.max_fields + 5) |i| {
        _ = i;
        fd.put("k", "v");
    }
    try std.testing.expectEqual(FormData.max_fields, fd.count());
}
