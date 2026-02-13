const std = @import("std");
const zzz = @import("zzz");

const App = zzz.Router.define(.{
    .routes = &.{
        zzz.Router.get("/", indexHandler),
        zzz.Router.get("/hello", helloHandler),
        zzz.Router.get("/json", jsonHandler),
        zzz.Router.get("/users/:id", userHandler),
    },
});

fn indexHandler(ctx: *zzz.Context) !void {
    ctx.html(.ok,
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Zzz</title></head>
        \\<body>
        \\  <h1>Welcome to Zzz</h1>
        \\  <p>The Zig web framework that never sleeps.</p>
        \\  <ul>
        \\    <li><a href="/hello">Hello</a></li>
        \\    <li><a href="/json">JSON Example</a></li>
        \\    <li><a href="/users/42">User 42</a></li>
        \\  </ul>
        \\</body>
        \\</html>
    );
}

fn helloHandler(ctx: *zzz.Context) !void {
    ctx.text(.ok, "Hello from Zzz!");
}

fn jsonHandler(ctx: *zzz.Context) !void {
    ctx.json(.ok,
        \\{"framework": "zzz", "version": "0.1.0", "status": "awake"}
    );
}

fn userHandler(ctx: *zzz.Context) !void {
    const id = ctx.param("id") orelse "unknown";
    ctx.text(.ok, id);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var server = zzz.Server.init(allocator, .{
        .host = "127.0.0.1",
        .port = 8888,
    }, App.handler);

    try server.listen(io);
}
