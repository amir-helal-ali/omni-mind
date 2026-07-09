// src/server.zig — Multi-client TCP server for Omni-Mind.
//
// Each client connects via TCP, sends queries line-by-line,
// and receives rich answers. Multiple clients are served
// concurrently via threads.
//
// Protocol:
//   Client sends: "QUERY:user_id:text\n"
//   Server replies: "OK:length:answer\n" or "ERR:message\n"
//   Special: "STATS\n", "INGEST:domain:text\n", "BYE\n"

const std = @import("std");
const core = @import("core.zig");
const allocator = @import("core/allocator.zig");

const Server = struct {
    listener: std.net.Server,
    client_count: std.atomic.Value(u32),
    total_queries: std.atomic.Value(u64),
};

/// Start the TCP server on the given port. Blocks forever.
pub fn run(port: u16) !void {
    const addr = try std.net.Address.parseIp4("0.0.0.0", port);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();

    var server = Server{
        .listener = listener,
        .client_count = std.atomic.Value(u32).init(0),
        .total_queries = std.atomic.Value(u64).init(0),
    };

    std.log.info("Omni-Mind TCP server listening on port {d}", .{port});

    while (true) {
        const conn = listener.accept() catch |err| {
            std.log.warn("Accept failed: {}", .{err});
            continue;
        };

        const count = server.client_count.fetchAdd(1, .monotonic) + 1;
        std.log.info("Client connected from {} (active: {d})", .{ conn.address, count });

        // Spawn a thread per client.
        const thread = std.Thread.spawn(.{}, handleClient, .{ conn, &server }) catch |err| {
            std.log.err("Spawn failed: {}", .{err});
            conn.stream.close();
            _ = server.client_count.fetchSub(1, .monotonic);
            continue;
        };
        thread.detach();
    }
}

fn handleClient(conn: std.net.Server.Connection, server: *Server) void {
    defer {
        conn.stream.close();
        _ = server.client_count.fetchSub(1, .monotonic);
    }

    var buf: [8192]u8 = undefined;
    var line_buf: [8192]u8 = undefined;
    var line_len: usize = 0;

    // Send welcome message.
    const welcome = "Omni-Mind TCP Server ready. Commands: QUERY:user:text, STATS, INGEST:domain:text, BYE\n";
    _ = conn.stream.write(welcome) catch return;

    while (true) {
        const n = conn.stream.read(&buf) catch return;
        if (n == 0) return; // client disconnected

        // Accumulate into line buffer, process complete lines.
        for (buf[0..n]) |b| {
            if (b == '\n' or b == '\r') {
                if (line_len > 0) {
                    line_buf[line_len] = 0;
                    handleLine(conn.stream, line_buf[0..line_len], server);
                    line_len = 0;
                }
                continue;
            }
            if (line_len < line_buf.len - 1) {
                line_buf[line_len] = b;
                line_len += 1;
            }
        }
    }
}

fn handleLine(stream: std.net.Stream, line: []u8, server: *Server) void {
    if (std.mem.startsWith(u8, line, "QUERY:")) {
        // Format: QUERY:user_id:text
        const rest = line[6..];
        const colon = std.mem.indexOf(u8, rest, ":") orelse {
            sendErr(stream, "missing user_id");
            return;
        };
        const user_str = rest[0..colon];
        const query = rest[colon + 1 ..];
        const user_id = std.fmt.parseInt(u32, user_str, 10) catch 0;

        var ans_buf: [8192]u8 = undefined;
        var ans_slice: []u8 = ans_buf[0..];
        const answer = core.runQuery(query, &ans_slice) catch |err| {
            var err_msg: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&err_msg, "query error: {}", .{err}) catch "query error";
            sendErr(stream, msg);
            return;
        };

        _ = server.total_queries.fetchAdd(1, .monotonic);
        sendOk(stream, answer);
        _ = user_id;
    } else if (std.mem.eql(u8, line, "STATS")) {
        var stats_buf: [256]u8 = undefined;
        const stats_str = std.fmt.bufPrint(&stats_buf, "nodes={d} edges={d} axioms={d} events={d} clients={d} queries={d}", .{
            core.graph.?.stats().node_count,
            core.graph.?.stats().edge_count,
            core.store.?.count,
            core.memory.?.totalEvents(),
            server.client_count.load(.monotonic),
            server.total_queries.load(.monotonic),
        }) catch "stats error";
        sendOk(stream, stats_str);
    } else if (std.mem.startsWith(u8, line, "INGEST:")) {
        // Format: INGEST:domain:text
        const rest = line[7..];
        const colon = std.mem.indexOf(u8, rest, ":") orelse {
            sendErr(stream, "missing domain");
            return;
        };
        const domain_str = rest[0..colon];
        const text = rest[colon + 1 ..];
        const domain = std.fmt.parseInt(u8, domain_str, 10) catch 0;
        core.ingestAxiom(domain, text, 0.8) catch |err| {
            sendErr(stream, @errorName(err));
            return;
        };
        sendOk(stream, "ingested");
    } else if (std.mem.eql(u8, line, "BYE")) {
        _ = stream.write("OK:goodbye\n") catch {};
    } else {
        sendErr(stream, "unknown command");
    }
}

fn sendOk(stream: std.net.Stream, payload: []const u8) void {
    var hdr: [32]u8 = undefined;
    const hdr_str = std.fmt.bufPrint(&hdr, "OK:{d}:", .{payload.len}) catch return;
    _ = stream.write(hdr_str) catch return;
    _ = stream.write(payload) catch return;
    _ = stream.write("\n") catch return;
}

fn sendErr(stream: std.net.Stream, msg: []const u8) void {
    var buf: [256]u8 = undefined;
    const err_str = std.fmt.bufPrint(&buf, "ERR:{s}\n", .{msg}) catch "ERR:unknown\n";
    _ = stream.write(err_str) catch return;
}
