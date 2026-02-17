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

    // libc is needed unconditionally (sendFile, clock_gettime, etc.)
    mod.link_libc = true;

    // Add TLS module (always available, guarded by comptime check in server.zig)
    const tls_mod = b.createModule(.{
        .root_source_file = b.path("src/tls/tls.zig"),
        .target = target,
    });
    tls_mod.link_libc = true;
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

    // ── Shared zzz_db module for benchmarks ────────────────────────────
    const is_macos = target.result.os.tag == .macos;

    const db_options = b.addOptions();
    db_options.addOption(bool, "sqlite_enabled", true);
    db_options.addOption(bool, "postgres_enabled", false);

    const zzz_db_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "../zzz_db/src/root.zig" },
        .target = target,
    });
    zzz_db_mod.addImport("db_options", db_options.createModule());
    zzz_db_mod.linkSystemLibrary("sqlite3", .{});
    zzz_db_mod.link_libc = true;
    if (is_macos) {
        zzz_db_mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
        zzz_db_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
    }

    // ── Benchmark server ────────────────────────────────────────────────
    const bench_exe = b.addExecutable(.{
        .name = "zzz-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench_server.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "zzz", .module = mod },
                .{ .name = "zzz_db", .module = zzz_db_mod },
            },
        }),
    });
    bench_exe.root_module.linkSystemLibrary("sqlite3", .{});
    bench_exe.root_module.link_libc = true;
    if (is_macos) {
        bench_exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
        bench_exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
    }
    const install_bench = b.addInstallArtifact(bench_exe, .{});
    const bench_step = b.step("bench", "Build benchmark server (ReleaseFast)");
    bench_step.dependOn(&install_bench.step);

    // ── SQLite benchmark (standalone) ───────────────────────────────────
    const bench_sqlite_exe = b.addExecutable(.{
        .name = "zzz-bench-sqlite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench_sqlite.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "zzz_db", .module = zzz_db_mod },
            },
        }),
    });
    bench_sqlite_exe.root_module.linkSystemLibrary("sqlite3", .{});
    bench_sqlite_exe.root_module.link_libc = true;
    if (is_macos) {
        bench_sqlite_exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/include" });
        bench_sqlite_exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sqlite/lib" });
    }
    const install_bench_sqlite = b.addInstallArtifact(bench_sqlite_exe, .{});

    const bench_sqlite_step = b.step("bench-sqlite", "Build and run SQLite benchmark");
    const run_bench_sqlite = b.addRunArtifact(bench_sqlite_exe);
    bench_sqlite_step.dependOn(&run_bench_sqlite.step);

    // Also make `zig build bench` install the sqlite bench binary
    bench_step.dependOn(&install_bench_sqlite.step);

    // ── Parallel test execution ─────────────────────────────────────────
    // Split into independent test compilations so the build system can
    // compile and run them in parallel (via dependOn).
    const test_groups = .{
        .{ "test-core", "src/test_core.zig" },
        .{ "test-router", "src/test_router.zig" },
        .{ "test-middleware", "src/test_middleware.zig" },
        .{ "test-template", "src/test_template.zig" },
        .{ "test-swagger", "src/test_swagger.zig" },
        .{ "test-testing", "src/test_testing.zig" },
        .{ "test-env", "src/test_env.zig" },
        .{ "test-config", "src/test_config.zig" },
    };

    const test_step = b.step("test", "Run all tests (parallel)");

    inline for (test_groups) |group| {
        const name = group[0];
        const root = group[1];

        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(root),
                .target = target,
            }),
        });
        t.root_module.link_libc = true;

        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);

        const named_step = b.step(name, "Run " ++ name ++ " tests");
        named_step.dependOn(&run_t.step);
    }

    // exe_tests (main.zig — imports zzz module)
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);
}
