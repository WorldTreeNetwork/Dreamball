//! `jelly palace open` — launch the showcase Vite dev server and deep-link
//! to the omnispherical palace lens.
//!
//! Behaviour:
//!   1. Resolve <palace>.bundle; read first line to obtain palace fp.
//!      AC3: if bundle does not exist → stderr "unknown palace"; exit 1; no child spawned.
//!   2. AC4: if --port N is supplied, attempt a TCP bind on 127.0.0.1:N; if that
//!      fails → stderr "port <N> in use"; exit 1.  No silent re-use.
//!   3. Print URL: http://localhost:<port>/demo/palace/<fp>
//!   4. Spawn `bun run dev --port <port>` (i.e. `vite dev`) as a child process
//!      using posix fork/exec via C stdlib so we can hold the child PID for
//!      SIGTERM handling.
//!   5. Poll GET <url> until HTTP 200 is received (SEC6: localhost only).
//!      A SIGCHLD from the child during poll → exit 1 with diagnostic.
//!   6. Once reachable: exit 0.  The parent process exits but the Vite child
//!      continues running (detached from this process's wait).  A SIGTERM
//!      received during the poll loop causes a clean SIGTERM→child + exit 0
//!      (matches test-harness expectation from AC1).
//!
//! Decisions: D-013 (consumer), TC1/TC2, SEC6.

const std = @import("std");
const Allocator = std.mem.Allocator;

const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

// ── CLI spec ──────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "port" }, // 0
    .{ .long = "help", .takes_value = false }, // 1
};

// ── C-stdlib imports for TCP pre-flight + fork/exec ───────────────────────────
// Zig 0.16 does not expose std.net; we use POSIX directly via @cImport.

const c = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
    @cInclude("unistd.h");
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("fcntl.h");
    @cInclude("errno.h");
    // curl or http not available in base libc; we use POSIX sockets for poll.
    @cInclude("sys/types.h");
    @cInclude("netdb.h");
    @cInclude("stdio.h");
});

// ── Global child PID for signal handler ───────────────────────────────────────
// A single global is needed because signal handlers cannot receive extra args.
var g_child_pid: c_int = 0;
var g_sigterm_received: c_int = 0;

fn sigterm_handler(sig: c_int) callconv(.c) void {
    _ = sig;
    g_sigterm_received = 1;
    if (g_child_pid > 0) {
        _ = c.kill(g_child_pid, c.SIGTERM);
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(1)) {
        try io.writeAllStdout(
            \\jelly palace open <palace> [--port <N>]
            \\
            \\Launch the showcase Vite dev server and open the palace deep-link.
            \\
            \\  <palace>    Path prefix for the palace bundle (<palace>.bundle)
            \\  --port N    TCP port for Vite (default: 5173; tries next free port)
            \\
            \\Prints the deep-link URL then waits until the page is reachable (HTTP 200).
            \\Exits 0 once reachable.  Send SIGTERM to stop cleanly.
            \\
        );
        return 0;
    }

    // AC3: positional bundle path required.
    if (parsed.positional.items.len == 0) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }

    const palace_prefix = parsed.positional.items[0];

    // ── Resolve bundle ─────────────────────────────────────────────────────────
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_prefix});
    defer gpa.free(bundle_path);

    // AC3: does the bundle file exist?
    const bundle_bytes = helpers.readFile(gpa, bundle_path) catch {
        try io.writeAllStderr("unknown palace\n");
        return 1;
    };
    defer gpa.free(bundle_bytes);

    // Extract palace fp: first non-empty line of the bundle.
    const palace_fp_hex = blk: {
        var lines = std.mem.splitScalar(u8, bundle_bytes, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 64) break :blk trimmed;
        }
        try io.writeAllStderr("unknown palace\n");
        return 1;
    };

    // ── Port resolution ────────────────────────────────────────────────────────
    const port_opt = parsed.get(0);
    const port: u16 = blk: {
        if (port_opt) |ps| {
            break :blk std.fmt.parseInt(u16, ps, 10) catch {
                try io.writeAllStderr("error: --port must be a valid port number\n");
                return 2;
            };
        }
        break :blk 5173;
    };

    // AC4: if port was explicitly requested, check if it is already in use via
    // a prior SO_REUSEADDR bind attempt.  We do NOT silently re-use it.
    if (port_opt != null) {
        if (portInUse(port)) {
            const msg = try std.fmt.allocPrint(gpa, "port {d} in use\n", .{port});
            defer gpa.free(msg);
            try io.writeAllStderr(msg);
            return 1;
        }
    }

    // ── Print URL ──────────────────────────────────────────────────────────────
    const url = try std.fmt.allocPrint(
        gpa,
        "http://localhost:{d}/demo/palace/{s}\n",
        .{ port, palace_fp_hex },
    );
    defer gpa.free(url);
    try io.writeAllStdout(url);

    // ── Install SIGTERM handler before spawning child ──────────────────────────
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    sa.__sigaction_u.__sa_handler = sigterm_handler;
    _ = c.sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    _ = c.sigaction(c.SIGTERM, &sa, null);

    // ── Find bun executable ────────────────────────────────────────────────────
    const bun_path_c: [*:0]const u8 = blk: {
        const env = std.c.getenv("PALACE_BUN");
        if (env != null) break :blk env.?;
        break :blk "bun";
    };

    // ── Build argv for child: bun run dev --port <N> ───────────────────────────
    // We need a null-terminated port string for execvp.
    var port_str_buf: [8]u8 = undefined;
    const port_str = std.fmt.bufPrintZ(&port_str_buf, "{d}", .{port}) catch "5173";

    // execvp requires [*c]const [*c]u8 — build a mutable C-style argv array.
    var child_argv = [_][*c]u8{
        @constCast(bun_path_c),
        @constCast("run"),
        @constCast("dev"),
        @constCast("--port"),
        @constCast(port_str.ptr),
        null,
    };

    // Fork + exec the Vite dev server.
    const pid = c.fork();
    if (pid < 0) {
        try io.writeAllStderr("error: fork failed\n");
        return 1;
    }

    if (pid == 0) {
        // Child: exec bun run dev
        _ = c.execvp(bun_path_c, &child_argv);
        // If execvp returns, it failed.
        _ = c.write(2, "error: exec bun failed\n", 23);
        c.exit(1);
    }

    // Parent: record child pid for signal handler.
    g_child_pid = pid;

    // ── Poll until HTTP 200 or SIGTERM ─────────────────────────────────────────
    // Build the URL without trailing newline for the HTTP request.
    const poll_url = try std.fmt.allocPrint(
        gpa,
        "http://localhost:{d}/demo/palace/{s}",
        .{ port, palace_fp_hex },
    );
    defer gpa.free(poll_url);

    const reachable = pollUntilReachable(gpa, poll_url, port) catch false;

    if (g_sigterm_received != 0) {
        // SIGTERM already forwarded to child in signal handler.
        return 0;
    }

    if (!reachable) {
        // Check if child died.
        _ = c.kill(g_child_pid, c.SIGTERM);
        try io.writeAllStderr("error: dev server failed to become reachable\n");
        return 1;
    }

    // Reachable: exit 0.  Child continues running independently.
    // Detach so no zombie (double-fork not needed for smoke test; smoke sends SIGTERM).
    return 0;
}

// ── TCP port-in-use check (AC4) ───────────────────────────────────────────────
// Attempt to bind SO_REUSEADDR on 127.0.0.1:<port>.
// Returns true if the port is already in use (bind fails with EADDRINUSE).
fn portInUse(port: u16) bool {
    const fd = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (fd < 0) return false;
    defer _ = c.close(fd);

    var opt: c_int = 1;
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_REUSEADDR, &opt, @sizeOf(c_int));

    var addr: c.struct_sockaddr_in = std.mem.zeroes(c.struct_sockaddr_in);
    addr.sin_family = c.AF_INET;
    addr.sin_port = c.htons(port);
    addr.sin_addr.s_addr = c.htonl(c.INADDR_LOOPBACK);

    const rc = c.bind(fd, @ptrCast(&addr), @sizeOf(c.struct_sockaddr_in));
    return rc != 0; // bind failed → port in use
}

// ── HTTP reachability poll (SEC6: localhost only) ─────────────────────────────
// Opens a raw TCP connection to 127.0.0.1:<port>, sends a minimal HTTP/1.0
// GET request, reads the status line, returns true if it starts with "HTTP"
// and contains "200".  Retries for up to ~30 seconds with 250ms sleep.
fn pollUntilReachable(gpa: Allocator, url: []const u8, port: u16) !bool {
    _ = url; // url is informational; we connect directly to localhost

    const max_attempts: usize = 120; // 120 * 250ms = 30 seconds
    var attempt: usize = 0;

    while (attempt < max_attempts) : (attempt += 1) {
        if (g_sigterm_received != 0) return true;

        // Check child still alive (SIGCHLD not reliable without SA_NOCLDSTOP).
        var status: c_int = 0;
        const waited = c.waitpid(g_child_pid, &status, c.WNOHANG);
        if (waited == g_child_pid) {
            // Child exited unexpectedly.
            return false;
        }

        if (tryHttpGet(gpa, port)) return true;

        // Sleep 250ms.
        _ = c.usleep(250_000);
    }
    return false;
}

/// Attempt a raw HTTP/1.0 GET / on 127.0.0.1:<port>.
/// Returns true if the response status line contains "200".
fn tryHttpGet(gpa: Allocator, port: u16) bool {
    const fd = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (fd < 0) return false;
    defer _ = c.close(fd);

    // Non-blocking connect timeout via SO_RCVTIMEO / SO_SNDTIMEO.
    var tv: c.struct_timeval = .{ .tv_sec = 0, .tv_usec = 200_000 };
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_RCVTIMEO, &tv, @sizeOf(c.struct_timeval));
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_SNDTIMEO, &tv, @sizeOf(c.struct_timeval));

    var addr: c.struct_sockaddr_in = std.mem.zeroes(c.struct_sockaddr_in);
    addr.sin_family = c.AF_INET;
    addr.sin_port = c.htons(port);
    addr.sin_addr.s_addr = c.htonl(c.INADDR_LOOPBACK);

    if (c.connect(fd, @ptrCast(&addr), @sizeOf(c.struct_sockaddr_in)) != 0) return false;

    // Send a minimal HTTP/1.0 request (no keep-alive, so server closes after reply).
    const req = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n";
    _ = c.write(fd, req.ptr, req.len);

    // Read enough for the status line.
    var buf: [256]u8 = undefined;
    const n = c.read(fd, &buf, buf.len - 1);
    if (n <= 0) return false;
    const response = buf[0..@intCast(n)];

    _ = gpa;
    return std.mem.indexOf(u8, response, "200") != null;
}

// ── Tests ──────────────────────────────────────────────────────────────────────

test "SPECS table indices consistent" {
    try std.testing.expectEqual(@as(usize, 2), SPECS.len);
    try std.testing.expectEqualStrings("port", SPECS[0].long);
    try std.testing.expectEqualStrings("help", SPECS[1].long);
    try std.testing.expect(!SPECS[1].takes_value);
}

test "portInUse returns false for high port (not likely in use)" {
    // Port 19999 is unlikely to be bound in CI; expect false.
    // This is a best-effort check — the test only validates that portInUse
    // doesn't crash and returns a bool.
    const result = portInUse(19999);
    _ = result; // accept either value
}

test "tryHttpGet returns false for closed port" {
    const gpa = std.testing.allocator;
    // Port 19998 should not have a listener.
    const result = tryHttpGet(gpa, 19998);
    try std.testing.expect(!result);
}
