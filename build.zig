const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tls_enabled = b.option(bool, "tls", "Enable TLS/HTTPS support (requires OpenSSL)") orelse false;

    // Create a module for the TLS build option so server.zig can query it at comptime
    const tls_options = b.addOptions();
    tls_options.addOption(bool, "tls_enabled", tls_enabled);

    const mod = b.addModule("zzz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Add TLS options module
    mod.addImport("tls_options", tls_options.createModule());

    // Add TLS module (always available, guarded by comptime check in server.zig)
    const tls_mod = b.createModule(.{
        .root_source_file = b.path("src/tls/tls.zig"),
        .target = target,
    });
    mod.addImport("tls", tls_mod);

    if (tls_enabled) {
        // Link OpenSSL libraries
        mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/include" });
        mod.linkSystemLibrary("ssl", .{});
        mod.linkSystemLibrary("crypto", .{});
        mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/lib" });
        mod.link_libc = true;

        tls_mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/include" });
        tls_mod.linkSystemLibrary("ssl", .{});
        tls_mod.linkSystemLibrary("crypto", .{});
        tls_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/lib" });
        tls_mod.link_libc = true;
    }

    const exe = b.addExecutable(.{
        .name = "zzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zzz", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
