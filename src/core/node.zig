// src/core/node.zig — Cache-aligned Node and Edge structures.
//
// Every Node is exactly 64 bytes — one cache line on x86_64 and ARM64.
// This means reading a single Node always fetches all its data in one
// memory access. Pointer chasing through the graph never triggers
// a second cache miss per node.

const std = @import("std");

/// NodeKind — tagged union discriminator.
pub const NodeKind = enum(u8) {
    axiom = 0, // First-principle, never derived
    derived = 1, // Computed from axioms via procedure
    procedural = 2, // Function handle (no static data)
    analogy = 3, // Cross-domain isomorphism anchor
};

/// Domain IDs — packed into 1 byte. Add new domains at the END.
pub const Domain = enum(u8) {
    physics = 0,
    chemistry = 1,
    biology = 2,
    mathematics = 3,
    logic = 4,
    computer_science = 5,
    economics = 6,
    psychology = 7,
    history = 8,
    philosophy = 9,
    linguistics = 10,
    astronomy = 11,
    geology = 12,
    medicine = 13,
    engineering = 14,
    political_science = 15,
    _,
};

/// Node — the fundamental unit of the entanglement graph.
/// EXACTLY 64 bytes — fits one cache line.
pub const Node = extern struct {
    id: u64, // 8B  — unique concept ID (index into NodePool)
    kind: NodeKind, // 1B  — axiom | derived | procedural | analogy
    domain: Domain, // 1B  — physics, bio, logic...
    _pad1: u8, // 1B  — explicit padding
    flags: u8, // 1B  — bitfield: hot, dirty, sealed
    first_link: u32, // 4B  — offset into EdgePool (start of edges)
    link_count: u8, // 1B  — number of outgoing edges
    _pad2: [3]u8, // 3B
    content_hash: u64, // 8B  — hash of concept name/text
    signature: u64, // 8B  — Bloom signature for fast matching
    timestamp: i64, // 8B  — last modification (for LRU)
    confidence: f32, // 4B  — meta-confidence from Doubt Engine
    _pad3: [12]u8, // 12B — pad to 64 (alignment padding for u64)
};

comptime {
    if (@sizeOf(Node) != 64) {
        @compileError("Node must be exactly 64 bytes (one cache line)");
    }
}

/// Edge — a directed entanglement link between two nodes.
/// Also 32 bytes — half a cache line, so two edges fit per line.
pub const Edge = extern struct {
    src: u32, // 4B  — source node index
    dst: u32, // 4B  — destination node index
    edge_type: EdgeType, // 1B
    weight: u8, // 1B  — 0-255, mapped from 0.0-1.0
    _pad: [2]u8, // 2B
    signature: u64, // 8B  — relation Bloom signature
    created_at: i64, // 8B
};

comptime {
    if (@sizeOf(Edge) != 32) {
        @compileError("Edge must be exactly 32 bytes");
    }
}

pub const EdgeType = enum(u8) {
    causal = 0, // A causes B
    similarity = 1, // A is similar to B
    composition = 2, // A is part of B
    derivation = 3, // A derives from B (axiom → derived)
    isomorphism = 4, // A is isomorphic to B (cross-domain)
    temporal = 5, // A precedes B in time
    complement = 6, // A complements B
    contradiction = 7, // A contradicts B
    analogy = 8, // A is analogous to B (weaker than isomorphism)
};

/// NodePool — flat array of Nodes, indexed by id.
pub const NodePool = struct {
    nodes: []Node,
    count: usize = 0,

    pub fn init(capacity: usize) !NodePool {
        const slice = try @import("allocator.zig").allocAligned(Node, capacity);
        return .{ .nodes = slice, .count = 0 };
    }

    pub fn add(self: *NodePool, node: Node) !u64 {
        if (self.count >= self.nodes.len) return error.PoolFull;
        const id = self.count;
        var n = node;
        n.id = id;
        self.nodes[id] = n;
        self.count += 1;
        return id;
    }

    pub fn get(self: *NodePool, id: u64) ?*Node {
        if (id >= self.count) return null;
        return &self.nodes[id];
    }

    pub fn getConst(self: *const NodePool, id: u64) ?*const Node {
        if (id >= self.count) return null;
        return &self.nodes[id];
    }

    /// Find all nodes whose signature overlaps the query signature
    /// by at least `threshold` bits. Writes matches into `out`.
    pub fn findBySignature(
        self: *NodePool,
        query_sig: u64,
        threshold: u8,
        out: []u64,
    ) usize {
        var n: usize = 0;
        for (0..self.count) |i| {
            const overlap = @popCount(self.nodes[i].signature & query_sig);
            if (overlap >= threshold and n < out.len) {
                out[n] = i;
                n += 1;
            }
        }
        return n;
    }
};

/// EdgePool — flat array of Edges.
pub const EdgePool = struct {
    edges: []Edge,
    count: usize = 0,

    pub fn init(capacity: usize) !EdgePool {
        const slice = try @import("allocator.zig").allocAligned(Edge, capacity);
        return .{ .edges = slice, .count = 0 };
    }

    pub fn add(self: *EdgePool, edge: Edge) !u32 {
        if (self.count >= self.edges.len) return error.PoolFull;
        const idx: u32 = @intCast(self.count);
        self.edges[idx] = edge;
        self.count += 1;
        return idx;
    }

    /// Iterate over edges starting at a given node index.
    pub fn edgesOf(self: *const EdgePool, node: *const Node) []const Edge {
        if (node.link_count == 0) return &[_]Edge{};
        const start = node.first_link;
        const end = start + @as(u32, node.link_count);
        return self.edges[start..end];
    }
};

test "Node is exactly 64 bytes" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Node));
}

test "Edge is exactly 32 bytes" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Edge));
}

test "NodePool add and get" {
    @import("allocator.zig").init();
    var pool = try NodePool.init(16);

    const n = Node{
        .id = 0,
        .kind = .axiom,
        .domain = .physics,
        ._pad1 = 0,
        .flags = 0,
        .first_link = 0,
        .link_count = 0,
        ._pad2 = .{ 0, 0, 0 },
        .content_hash = 0xdeadbeef,
        .signature = 0xaa,
        .timestamp = 0,
        .confidence = 1.0,
        ._pad3 = std.mem.zeroes([12]u8),
    };
    const id = try pool.add(n);
    try std.testing.expectEqual(@as(u64, 0), id);
    try std.testing.expectEqual(@as(usize, 1), pool.count);

    const got = pool.get(0).?;
    try std.testing.expectEqual(@as(u64, 0xdeadbeef), got.content_hash);
}
