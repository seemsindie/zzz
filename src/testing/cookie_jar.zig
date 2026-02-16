const std = @import("std");

/// Fixed-size cookie store for the test client.
/// Automatically captures Set-Cookie headers from responses and sends
/// them back on subsequent requests via the Cookie header.
/// Follows the Params/Assigns zero-allocation pattern (32 slots).
pub const CookieJar = struct {
    const max_cookies = 32;

    pub const Cookie = struct {
        name: [128]u8 = undefined,
        name_len: usize = 0,
        value: [256]u8 = undefined,
        value_len: usize = 0,
        path: [128]u8 = undefined,
        path_len: usize = 0,

        pub fn nameSlice(self: *const Cookie) []const u8 {
            return self.name[0..self.name_len];
        }

        pub fn valueSlice(self: *const Cookie) []const u8 {
            return self.value[0..self.value_len];
        }

        pub fn pathSlice(self: *const Cookie) []const u8 {
            return self.path[0..self.path_len];
        }
    };

    cookies: [max_cookies]Cookie = undefined,
    len: usize = 0,

    /// Get a cookie value by name.
    pub fn get(self: *const CookieJar, name: []const u8) ?[]const u8 {
        for (self.cookies[0..self.len]) |*cookie| {
            if (std.mem.eql(u8, cookie.nameSlice(), name)) {
                return cookie.valueSlice();
            }
        }
        return null;
    }

    /// Set or update a cookie. If the name already exists, its value is replaced.
    pub fn put(self: *CookieJar, name: []const u8, value: []const u8, path: []const u8) void {
        // Update existing
        for (self.cookies[0..self.len]) |*cookie| {
            if (std.mem.eql(u8, cookie.nameSlice(), name)) {
                self.setCookieFields(cookie, name, value, path);
                return;
            }
        }
        // Add new
        if (self.len < max_cookies) {
            self.setCookieFields(&self.cookies[self.len], name, value, path);
            self.len += 1;
        }
    }

    /// Remove a cookie by name.
    pub fn remove(self: *CookieJar, name: []const u8) void {
        var i: usize = 0;
        while (i < self.len) {
            if (std.mem.eql(u8, self.cookies[i].nameSlice(), name)) {
                // Shift remaining cookies down
                if (i + 1 < self.len) {
                    var j: usize = i;
                    while (j + 1 < self.len) : (j += 1) {
                        self.cookies[j] = self.cookies[j + 1];
                    }
                }
                self.len -= 1;
            } else {
                i += 1;
            }
        }
    }

    /// Parse Set-Cookie headers from a response and store them.
    /// Accepts the full Set-Cookie header value (e.g. "name=value; Path=/; HttpOnly").
    pub fn parseSetCookie(self: *CookieJar, header_value: []const u8) void {
        // Extract name=value from the first segment (before any ;)
        const first_semi = std.mem.indexOfScalar(u8, header_value, ';') orelse header_value.len;
        const name_value = std.mem.trim(u8, header_value[0..first_semi], " ");

        const eq = std.mem.indexOfScalar(u8, name_value, '=') orelse return;
        const name = name_value[0..eq];
        const value = name_value[eq + 1 ..];

        if (name.len == 0) return;

        // Parse path from attributes
        var path: []const u8 = "/";
        var rest = if (first_semi < header_value.len) header_value[first_semi + 1 ..] else "";
        while (rest.len > 0) {
            const next_semi = std.mem.indexOfScalar(u8, rest, ';') orelse rest.len;
            const attr = std.mem.trim(u8, rest[0..next_semi], " ");

            if (startsWithIgnoreCase(attr, "path=")) {
                path = attr[5..];
            } else if (startsWithIgnoreCase(attr, "max-age=")) {
                const age_str = attr[8..];
                if (std.mem.eql(u8, age_str, "0")) {
                    // Cookie deletion — remove it
                    self.remove(name);
                    return;
                }
            }

            rest = if (next_semi < rest.len) rest[next_semi + 1 ..] else "";
        }

        self.put(name, value, path);
    }

    /// Build the Cookie request header value for a given path.
    /// Returns the number of bytes written to `buf`.
    pub fn buildCookieHeader(self: *const CookieJar, request_path: []const u8, buf: []u8) usize {
        var pos: usize = 0;
        var first = true;

        for (self.cookies[0..self.len]) |*cookie| {
            const cookie_path = cookie.pathSlice();
            // Check if request path starts with cookie path
            if (!pathMatches(request_path, cookie_path)) continue;

            const name = cookie.nameSlice();
            const value = cookie.valueSlice();
            const sep_len: usize = if (first) 0 else 2;
            const needed = sep_len + name.len + 1 + value.len;

            if (pos + needed > buf.len) break;

            if (!first) {
                @memcpy(buf[pos..][0..2], "; ");
                pos += 2;
            }
            @memcpy(buf[pos..][0..name.len], name);
            pos += name.len;
            buf[pos] = '=';
            pos += 1;
            @memcpy(buf[pos..][0..value.len], value);
            pos += value.len;
            first = false;
        }

        return pos;
    }

    /// Clear all cookies.
    pub fn reset(self: *CookieJar) void {
        self.len = 0;
    }

    fn setCookieFields(self: *CookieJar, cookie: *Cookie, name: []const u8, value: []const u8, path: []const u8) void {
        _ = self;
        const n_len = @min(name.len, cookie.name.len);
        @memcpy(cookie.name[0..n_len], name[0..n_len]);
        cookie.name_len = n_len;

        const v_len = @min(value.len, cookie.value.len);
        @memcpy(cookie.value[0..v_len], value[0..v_len]);
        cookie.value_len = v_len;

        const p_len = @min(path.len, cookie.path.len);
        @memcpy(cookie.path[0..p_len], path[0..p_len]);
        cookie.path_len = p_len;
    }
};

fn pathMatches(request_path: []const u8, cookie_path: []const u8) bool {
    if (cookie_path.len == 0 or std.mem.eql(u8, cookie_path, "/")) return true;
    if (std.mem.startsWith(u8, request_path, cookie_path)) {
        // Exact match or path continues with /
        if (request_path.len == cookie_path.len) return true;
        if (request_path[cookie_path.len] == '/') return true;
    }
    return false;
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    for (haystack[0..prefix.len], prefix) |h, p| {
        if (std.ascii.toLower(h) != std.ascii.toLower(p)) return false;
    }
    return true;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "CookieJar put and get" {
    var jar: CookieJar = .{};
    jar.put("session", "abc123", "/");
    jar.put("theme", "dark", "/");

    try std.testing.expectEqualStrings("abc123", jar.get("session").?);
    try std.testing.expectEqualStrings("dark", jar.get("theme").?);
    try std.testing.expect(jar.get("missing") == null);
}

test "CookieJar put overwrites existing" {
    var jar: CookieJar = .{};
    jar.put("session", "abc", "/");
    jar.put("session", "xyz", "/");

    try std.testing.expectEqualStrings("xyz", jar.get("session").?);
    try std.testing.expectEqual(@as(usize, 1), jar.len);
}

test "CookieJar parseSetCookie basic" {
    var jar: CookieJar = .{};
    jar.parseSetCookie("session=abc123; Path=/; HttpOnly");

    try std.testing.expectEqualStrings("abc123", jar.get("session").?);
    try std.testing.expectEqual(@as(usize, 1), jar.len);
}

test "CookieJar parseSetCookie with Max-Age=0 removes cookie" {
    var jar: CookieJar = .{};
    jar.put("session", "abc123", "/");
    jar.parseSetCookie("session=; Max-Age=0; Path=/");

    try std.testing.expect(jar.get("session") == null);
    try std.testing.expectEqual(@as(usize, 0), jar.len);
}

test "CookieJar buildCookieHeader" {
    var jar: CookieJar = .{};
    jar.put("session", "abc", "/");
    jar.put("theme", "dark", "/");

    var buf: [256]u8 = undefined;
    const len = jar.buildCookieHeader("/", &buf);
    const header = buf[0..len];

    try std.testing.expect(std.mem.indexOf(u8, header, "session=abc") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "theme=dark") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "; ") != null);
}

test "CookieJar path matching" {
    var jar: CookieJar = .{};
    jar.put("global", "yes", "/");
    jar.put("admin", "yes", "/admin");

    var buf: [256]u8 = undefined;

    // / should only get global
    const len1 = jar.buildCookieHeader("/", &buf);
    const h1 = buf[0..len1];
    try std.testing.expect(std.mem.indexOf(u8, h1, "global=yes") != null);
    try std.testing.expect(std.mem.indexOf(u8, h1, "admin=yes") == null);

    // /admin should get both
    const len2 = jar.buildCookieHeader("/admin", &buf);
    const h2 = buf[0..len2];
    try std.testing.expect(std.mem.indexOf(u8, h2, "global=yes") != null);
    try std.testing.expect(std.mem.indexOf(u8, h2, "admin=yes") != null);
}

test "CookieJar reset clears all" {
    var jar: CookieJar = .{};
    jar.put("a", "1", "/");
    jar.put("b", "2", "/");
    jar.reset();

    try std.testing.expectEqual(@as(usize, 0), jar.len);
    try std.testing.expect(jar.get("a") == null);
}

test "CookieJar remove" {
    var jar: CookieJar = .{};
    jar.put("a", "1", "/");
    jar.put("b", "2", "/");
    jar.put("c", "3", "/");
    jar.remove("b");

    try std.testing.expectEqual(@as(usize, 2), jar.len);
    try std.testing.expectEqualStrings("1", jar.get("a").?);
    try std.testing.expect(jar.get("b") == null);
    try std.testing.expectEqualStrings("3", jar.get("c").?);
}
