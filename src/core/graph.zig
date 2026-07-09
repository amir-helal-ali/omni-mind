// src/core/graph.zig — The Entanglement Graph.
//
// Sparse graph engine using direct pointers. When Node A is updated,
// every node entangled with A reflects the change instantly via
// pointer chase — no propagation step, no recompute, O(1) updates.

const std = @import("std");
const Node = @import("node.zig").Node;
const Edge = @import("node.zig").Edge;
const EdgeType = @import("node.zig").EdgeType;
const NodePool = @import("node.zig").NodePool;
const EdgePool = @import("node.zig").EdgePool;
const Domain = @import("node.zig").Domain;
const NodeKind = @import("node.zig").NodeKind;
const bloomSig = @import("mmap.zig").bloomSig;
const allocator = @import("allocator.zig");

pub const Graph = struct {
    nodes: NodePool,
    edges: EdgePool,

    pub fn init(node_cap: usize, edge_cap: usize) !Graph {
        return .{
            .nodes = try NodePool.init(node_cap),
            .edges = try EdgePool.init(edge_cap),
        };
    }

    /// Add a new node by name (text) and kind. Returns its id.
    pub fn addNode(
        self: *Graph,
        name: []const u8,
        kind: NodeKind,
        domain: Domain,
        confidence: f32,
    ) !u64 {
        const sig = bloomSig(name);
        const hash = sig; // reuse as content hash
        const ts = std.time.timestamp();

        const node = Node{
            .id = 0,
            .kind = kind,
            .domain = domain,
            ._pad1 = 0,
            .flags = 0,
            .first_link = 0,
            .link_count = 0,
            ._pad2 = .{ 0, 0, 0 },
            .content_hash = hash,
            .signature = sig,
            .timestamp = ts,
            .confidence = confidence,
            ._pad3 = std.mem.zeroes([12]u8),
        };
        return try self.nodes.add(node);
    }

    /// Entangle two nodes with a typed edge. O(1) append.
    pub fn entangle(
        self: *Graph,
        src_id: u64,
        dst_id: u64,
        edge_type: EdgeType,
        weight: f32,
    ) !void {
        const src = self.nodes.get(src_id) orelse return error.NodeNotFound;
        _ = self.nodes.get(dst_id) orelse return error.NodeNotFound;

        const edge_idx = try self.edges.add(.{
            .src = @intCast(src_id),
            .dst = @intCast(dst_id),
            .edge_type = edge_type,
            .weight = @intFromFloat(@max(0, @min(1, weight)) * 255),
            ._pad = .{ 0, 0 },
            .signature = src.signature & self.nodes.nodes[dst_id].signature,
            .created_at = std.time.timestamp(),
        });

        // Update src's first_link if it had no links, otherwise extend.
        if (src.link_count == 0) {
            src.first_link = edge_idx;
        }
        src.link_count +|= 1;
    }

    /// Get all edges out of a node.
    pub fn edgesOf(self: *const Graph, node_id: u64) []const Edge {
        const node = self.nodes.getConst(node_id) orelse return &[_]Edge{};
        return self.edges.edgesOf(node);
    }

    /// Find neighbors of a node by edge type.
    pub fn neighbors(
        self: *const Graph,
        node_id: u64,
        edge_type: EdgeType,
        out: []u64,
    ) usize {
        const edges = self.edgesOf(node_id);
        var n: usize = 0;
        for (edges) |e| {
            if (e.edge_type == edge_type and n < out.len) {
                out[n] = e.dst;
                n += 1;
            }
        }
        return n;
    }

    /// BFS from `start` up to `max_depth` hops, collecting node ids.
    /// Used by Layer 3 (analogy tunneling) and Layer 1 (forward chaining).
    pub fn bfs(
        self: *const Graph,
        start: u64,
        max_depth: u8,
        visited: []bool,
        out: []u64,
    ) usize {
        @memset(visited, false);
        if (start >= self.nodes.count) return 0;

        var queue: [256]u64 = undefined;
        var depth_q: [256]u8 = undefined;
        var head: usize = 0;
        var tail: usize = 0;

        queue[tail] = start;
        depth_q[tail] = 0;
        tail += 1;
        visited[start] = true;

        var found: usize = 0;
        while (head < tail and found < out.len) {
            const cur = queue[head];
            const depth = depth_q[head];
            head += 1;

            if (found < out.len) {
                out[found] = cur;
                found += 1;
            }

            if (depth >= max_depth) continue;

            const edges = self.edgesOf(cur);
            for (edges) |e| {
                if (e.dst < self.nodes.count and !visited[e.dst]) {
                    visited[e.dst] = true;
                    if (tail < queue.len) {
                        queue[tail] = e.dst;
                        depth_q[tail] = depth + 1;
                        tail += 1;
                    }
                }
            }
        }
        return found;
    }

    /// Stats — used by /health endpoint.
    pub fn stats(self: *const Graph) GraphStats {
        return .{
            .node_count = self.nodes.count,
            .edge_count = self.edges.count,
            .bytes_used = allocator.bytes_used,
            .bytes_budget = allocator.CORE_BUDGET,
        };
    }
};

pub const GraphStats = struct {
    node_count: usize,
    edge_count: usize,
    bytes_used: usize,
    bytes_budget: usize,
};

test "graph add and entangle" {
    allocator.init();
    var g = try Graph.init(64, 128);

    const a = try g.addNode("gravity", .axiom, .physics, 1.0);
    const b = try g.addNode("spacetime", .axiom, .physics, 1.0);
    try g.entangle(a, b, .causal, 0.8);

    const edges = g.edgesOf(a);
    try std.testing.expectEqual(@as(usize, 1), edges.len);
    try std.testing.expectEqual(@as(u64, b), edges[0].dst);
}

test "graph BFS" {
    allocator.init();
    var g = try Graph.init(64, 128);

    const a = try g.addNode("a", .axiom, .logic, 1.0);
    const b = try g.addNode("b", .axiom, .logic, 1.0);
    const c = try g.addNode("c", .axiom, .logic, 1.0);
    try g.entangle(a, b, .derivation, 1.0);
    try g.entangle(b, c, .derivation, 1.0);

    var visited: [64]bool = undefined;
    var out: [64]u64 = undefined;
    const n = g.bfs(a, 2, &visited, &out);
    try std.testing.expect(n >= 3); // a, b, c
}
