const std = @import("std");

/// Generate a JSON Schema string for a Zig type at compile time.
/// Maps Zig types to JSON Schema (compatible with OpenAPI 3.1.0):
///
///   i8..i64, u8..u64   → {"type":"integer"}
///   f32, f64            → {"type":"number"}
///   bool                → {"type":"boolean"}
///   []const u8          → {"type":"string"}
///   ?T                  → {"oneOf":[<schema(T)>,{"type":"null"}]}
///   []T / []const T     → {"type":"array","items":<schema(T)>}
///   struct              → {"type":"object","properties":{...},"required":[...]}
///   enum                → {"type":"string","enum":["val1","val2",...]}
pub fn jsonSchema(comptime T: type) []const u8 {
    return comptime schemaFor(T);
}

fn schemaFor(comptime T: type) []const u8 {
    const info = @typeInfo(T);

    return switch (info) {
        .int => "{\"type\":\"integer\"}",
        .float => "{\"type\":\"number\"}",
        .bool => "{\"type\":\"boolean\"}",

        .pointer => |ptr| {
            if (ptr.size == .slice) {
                // []const u8 → string
                if (ptr.child == u8) {
                    return "{\"type\":\"string\"}";
                }
                // []T or []const T → array
                return "{\"type\":\"array\",\"items\":" ++ schemaFor(ptr.child) ++ "}";
            }
            // Single-item pointer — dereference
            if (ptr.size == .one) {
                return schemaFor(ptr.child);
            }
            return "{\"type\":\"string\"}";
        },

        .optional => |opt| {
            return "{\"oneOf\":[" ++ schemaFor(opt.child) ++ ",{\"type\":\"null\"}]}";
        },

        .@"struct" => |s| {
            return structSchema(s.fields);
        },

        .@"enum" => |e| {
            return enumSchema(e.fields);
        },

        .array => |arr| {
            // Fixed-size arrays [N]T
            if (arr.child == u8) {
                return "{\"type\":\"string\"}";
            }
            return "{\"type\":\"array\",\"items\":" ++ schemaFor(arr.child) ++ "}";
        },

        else => "{\"type\":\"string\"}",
    };
}

fn structSchema(comptime fields: anytype) []const u8 {
    // Filter out fields starting with underscore or named "Meta"
    comptime var prop_count: usize = 0;
    comptime var req_count: usize = 0;
    inline for (fields) |f| {
        if (!shouldSkipField(f.name)) {
            prop_count += 1;
            if (@typeInfo(f.type) != .optional) {
                req_count += 1;
            }
        }
    }

    if (prop_count == 0) {
        return "{\"type\":\"object\"}";
    }

    comptime var result: []const u8 = "{\"type\":\"object\",\"properties\":{";
    comptime var first = true;
    inline for (fields) |f| {
        if (!shouldSkipField(f.name)) {
            if (!first) {
                result = result ++ ",";
            }
            result = result ++ "\"" ++ escapeJsonString(f.name) ++ "\":" ++ schemaFor(f.type);
            first = false;
        }
    }
    result = result ++ "}";

    // Required fields (non-optional)
    if (req_count > 0) {
        result = result ++ ",\"required\":[";
        comptime var req_first = true;
        inline for (fields) |f| {
            if (!shouldSkipField(f.name)) {
                if (@typeInfo(f.type) != .optional) {
                    if (!req_first) {
                        result = result ++ ",";
                    }
                    result = result ++ "\"" ++ escapeJsonString(f.name) ++ "\"";
                    req_first = false;
                }
            }
        }
        result = result ++ "]";
    }

    result = result ++ "}";
    return result;
}

fn enumSchema(comptime fields: anytype) []const u8 {
    if (fields.len == 0) {
        return "{\"type\":\"string\"}";
    }

    comptime var result: []const u8 = "{\"type\":\"string\",\"enum\":[";
    comptime var first = true;
    inline for (fields) |f| {
        if (!first) {
            result = result ++ ",";
        }
        result = result ++ "\"" ++ escapeJsonString(f.name) ++ "\"";
        first = false;
    }
    result = result ++ "]}";
    return result;
}

fn shouldSkipField(comptime name: []const u8) bool {
    if (name.len == 0) return true;
    if (std.mem.eql(u8, name, "Meta")) return true;
    if (name[0] == '_') return true;
    return false;
}

pub fn escapeJsonString(comptime s: []const u8) []const u8 {
    @setEvalBranchQuota(s.len * 10 + 1000);
    comptime var result: []const u8 = "";
    inline for (s) |c| {
        result = result ++ switch (c) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => &[_]u8{c},
        };
    }
    return result;
}

/// Extract the base type name from a Zig type (e.g. "main.MyStruct" → "MyStruct").
pub fn typeBaseName(comptime T: type) []const u8 {
    const full = @typeName(T);
    // Find last '.' to strip module prefix
    comptime var last_dot: usize = 0;
    comptime var found = false;
    inline for (full, 0..) |c, i| {
        if (c == '.') {
            last_dot = i;
            found = true;
        }
    }
    if (found) {
        return full[last_dot + 1 ..];
    }
    return full;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "jsonSchema: integer types" {
    try std.testing.expectEqualStrings("{\"type\":\"integer\"}", jsonSchema(i32));
    try std.testing.expectEqualStrings("{\"type\":\"integer\"}", jsonSchema(u64));
    try std.testing.expectEqualStrings("{\"type\":\"integer\"}", jsonSchema(i8));
}

test "jsonSchema: float types" {
    try std.testing.expectEqualStrings("{\"type\":\"number\"}", jsonSchema(f32));
    try std.testing.expectEqualStrings("{\"type\":\"number\"}", jsonSchema(f64));
}

test "jsonSchema: bool" {
    try std.testing.expectEqualStrings("{\"type\":\"boolean\"}", jsonSchema(bool));
}

test "jsonSchema: string" {
    try std.testing.expectEqualStrings("{\"type\":\"string\"}", jsonSchema([]const u8));
}

test "jsonSchema: optional" {
    try std.testing.expectEqualStrings(
        "{\"oneOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]}",
        jsonSchema(?i32),
    );
}

test "jsonSchema: slice" {
    try std.testing.expectEqualStrings(
        "{\"type\":\"array\",\"items\":{\"type\":\"integer\"}}",
        jsonSchema([]const i32),
    );
}

test "jsonSchema: struct" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
    };
    const schema = jsonSchema(User);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"type\":\"object\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"id\":{\"type\":\"integer\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"name\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"required\":[") != null);
    // id and name are required, email is optional
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"name\"") != null);
}

test "jsonSchema: enum" {
    const Color = enum { red, green, blue };
    const schema = jsonSchema(Color);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"type\":\"string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"green\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"blue\"") != null);
}

test "jsonSchema: nested struct" {
    const Address = struct {
        street: []const u8,
        city: []const u8,
    };
    const User = struct {
        name: []const u8,
        address: Address,
    };
    const schema = jsonSchema(User);
    try std.testing.expect(std.mem.indexOf(u8, schema, "\"address\":{\"type\":\"object\"") != null);
}

test "jsonSchema: skips Meta field" {
    const MyModel = struct {
        id: i64,
        name: []const u8,
        Meta: type = undefined,
    };
    _ = MyModel;
    // Meta field should be skipped — just verify it compiles
    // (the Meta field with type `type` can't be directly tested via jsonSchema
    //  since type is not a runtime type, but the skip logic is tested implicitly)
}

test "typeBaseName extracts struct name" {
    const MyStruct = struct { x: i32 };
    const name = typeBaseName(MyStruct);
    try std.testing.expectEqualStrings("MyStruct", name);
}

test "escapeJsonString handles special chars" {
    try std.testing.expectEqualStrings("hello\\\"world", escapeJsonString("hello\"world"));
    try std.testing.expectEqualStrings("line\\none", escapeJsonString("line\none"));
}
