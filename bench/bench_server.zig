const std = @import("std");
const zzz = @import("zzz");

const App = zzz.Router.define(.{
    .routes = &.{
        zzz.Router.get("/plaintext", plaintextHandler),
        zzz.Router.get("/json", jsonHandler),
        zzz.Router.get("/users/:id", userHandler),
    },
});

fn plaintextHandler(ctx: *zzz.Context) !void {
    ctx.text(.ok, "Hello, World!");
}

fn jsonHandler(ctx: *zzz.Context) !void {
    ctx.json(.ok,
        \\{"message":"Hello, World!"}
    );
}

fn userHandler(ctx: *zzz.Context) !void {
    const id = ctx.param("id") orelse "0";
    ctx.text(.ok, id);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var server = zzz.Server.init(allocator, .{
        .host = "127.0.0.1",
        .port = 3000,
    }, App.handler);

    try server.listen(io);
}
