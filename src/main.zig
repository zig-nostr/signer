//! zig-nostr signer — a headless NIP-46 remote signer ("bunker").
//!
//! Keeps the user's secret key on a machine they control and signs for remote
//! clients over a relay. On startup it derives the keypair, prints the
//! `bunker://` connection token, then connects to each configured relay and
//! serves NIP-46 requests (see `serve.zig`) until stopped. Encrypted key
//! storage (NIP-49) and a per-request approval UX are the next slices; this
//! build auto-approves every request behind the connection secret.

const std = @import("std");
const nostr = @import("nostr");
const serve = @import("serve.zig");

const keys = nostr.keys;
const nip46 = nostr.nip46;
const hex = nostr.hex;

const usage =
    \\zig-nostr signer — headless NIP-46 remote signer (bunker)
    \\
    \\Configure via environment variables:
    \\  SIGNER_SECRET_KEY      64-char hex secret key (required)
    \\  SIGNER_RELAYS          comma-separated wss:// relay URLs (required)
    \\  SIGNER_CONNECT_SECRET  optional connection secret clients must echo
    \\
    \\Prints the signer's public key and the bunker:// token clients connect
    \\with, then serves NIP-46 requests over the relays until stopped.
    \\
;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    const secret_hex = getEnv("SIGNER_SECRET_KEY") orelse
        fail("set SIGNER_SECRET_KEY to a 64-char hex secret key");
    const relays_env = getEnv("SIGNER_RELAYS") orelse
        fail("set SIGNER_RELAYS to a comma-separated list of wss:// URLs");
    const conn_secret = getEnv("SIGNER_CONNECT_SECRET");

    const secret_key = hex.decodeFixed(32, secret_hex) catch
        fail("SIGNER_SECRET_KEY must be exactly 64 hex characters");

    var signer = keys.Signer.init();
    defer signer.deinit();

    const kp = signer.keyPairFromSecretKey(secret_key) catch
        fail("SIGNER_SECRET_KEY is not a valid secp256k1 secret key");

    var relays: std.ArrayList([]const u8) = .empty;
    defer relays.deinit(gpa);
    var it = std.mem.splitScalar(u8, relays_env, ',');
    while (it.next()) |raw| {
        const url = std.mem.trim(u8, raw, " \t");
        if (url.len != 0) try relays.append(gpa, url);
    }
    if (relays.items.len == 0) fail("SIGNER_RELAYS contained no relay URLs");

    const token = try nip46.buildBunkerUri(gpa, kp.public_key, relays.items, conn_secret);
    defer gpa.free(token);

    const pk_hex = try hex.encode(gpa, &kp.public_key);
    defer gpa.free(pk_hex);

    std.debug.print(
        \\zig-nostr signer (headless)
        \\  pubkey : {s}
        \\  bunker : {s}
        \\
        \\Share the bunker:// token with a client to connect. Requests are
        \\auto-approved{s}. Press Ctrl-C to stop.
        \\
    , .{ pk_hex, token, if (conn_secret == null) " (no connection secret set)" else "" });

    // Serve each relay on its own thread. Each thread owns its secp256k1
    // context and bunker, so nothing mutable is shared between them; the only
    // shared state is the read-only key material and the allocator.
    var threads: std.ArrayList(std.Thread) = .empty;
    defer threads.deinit(gpa);
    for (relays.items) |url| {
        const t = std.Thread.spawn(.{}, serveRelayForever, .{ gpa, url, secret_key, conn_secret }) catch |err| {
            std.debug.print("signer: [{s}] could not start: {s}\n", .{ url, @errorName(err) });
            continue;
        };
        try threads.append(gpa, t);
    }
    if (threads.items.len == 0) fail("could not start any relay connections");
    for (threads.items) |t| t.join();
}

/// Connects to `url` and serves requests forever, reconnecting after a short
/// delay whenever the connection drops. Runs on its own thread with its own
/// signing context, derived from the shared read-only `secret_key`.
fn serveRelayForever(
    gpa: std.mem.Allocator,
    url: []const u8,
    secret_key: [32]u8,
    conn_secret: ?[]const u8,
) void {
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var signer = keys.Signer.init();
    defer signer.deinit();
    const kp = signer.keyPairFromSecretKey(secret_key) catch {
        std.debug.print("signer: [{s}] invalid secret key\n", .{url});
        return;
    };

    var bunker = nip46.Bunker.initSingleKey(signer, kp, nip46.approveAll());
    bunker.secret = conn_secret;

    while (true) {
        serveOnce(gpa, io, url, bunker, kp) catch |err| {
            std.debug.print("signer: [{s}] {s}\n", .{ url, @errorName(err) });
        };
        std.debug.print("signer: [{s}] disconnected; reconnecting in 3s\n", .{url});
        io.sleep(std.Io.Duration.fromSeconds(3), .awake) catch {};
    }
}

/// Dials `url`, then serves requests until the connection closes.
fn serveOnce(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    bunker: nip46.Bunker,
    remote: keys.KeyPair,
) !void {
    var relay = try nostr.relay.dial(gpa, io, url);
    defer relay.deinit();
    std.debug.print("signer: [{s}] connected; listening for NIP-46 requests\n", .{url});
    try serve.serve(gpa, io, relay, bunker, remote);
}

fn getEnv(name: [*:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.span(value);
}

fn fail(message: []const u8) noreturn {
    std.debug.print("error: {s}\n\n{s}", .{ message, usage });
    std.process.exit(1);
}

test {
    // Ensure the serve loop's hermetic tests run under `zig build test`.
    _ = @import("serve.zig");
}

test "derives the pubkey and builds a bunker token" {
    const gpa = std.testing.allocator;
    var signer = keys.Signer.init();
    defer signer.deinit();

    // BIP-340 test vector: this secret key derives this x-only public key.
    const secret = try hex.decodeFixed(32, "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef");
    const kp = try signer.keyPairFromSecretKey(secret);

    const relays = [_][]const u8{"wss://relay.example.com"};
    const token = try nip46.buildBunkerUri(gpa, kp.public_key, &relays, "s3cret");
    defer gpa.free(token);

    try std.testing.expectStringStartsWith(
        token,
        "bunker://dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659?",
    );
    try std.testing.expect(std.mem.indexOf(u8, token, "secret=s3cret") != null);
}
