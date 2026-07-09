// src/l7/living.zig — Living Memory (Delta Compression).
//
// 1M interactions compressed into ~100 MB via state equations.
// We don't store text — we store "delta events" that describe
// what changed. Recall is reconstruction, not search.

const std = @import("std");
const allocator = @import("../core/allocator.zig");

pub const EventType = enum(u8) {
    axiom_accessed = 0,
    confidence_updated = 1,
    analogy_used = 2,
    synthesis_created = 3,
    failure_logged = 4,
    axiom_injected = 5,
    user_corrected = 6,
};

/// A DeltaEvent — the smallest unit of memory. 32 bytes.
pub const DeltaEvent = extern struct {
    timestamp: i64, // 8B
    user_id: u32, // 4B
    event_type: EventType, // 1B
    domain: u8, // 1B
    _pad: [2]u8, // 2B
    target_id: u32, // 4B — axiom ID, function ID, user ID...
    confidence: f32, // 4B
    payload: u32, // 4B — type-specific

};
comptime {
        if (@sizeOf(DeltaEvent) != 32) {
            @compileError("DeltaEvent must be 32 bytes");
        }
}

/// LivingMemory — ring buffer of DeltaEvents + per-user recent pointers.
pub const LivingMemory = struct {
    events: []DeltaEvent,
    capacity: usize,
    head: std.atomic.Value(u64),
    per_user_recent: [64][16]u32, // per-user last 16 event indices
    per_user_count: [64]u8, // per-user number of valid entries

    pub fn init(cap: usize) !LivingMemory {
        const evts = try allocator.allocAligned(DeltaEvent, cap);
        @memset(evts, std.mem.zeroes(DeltaEvent));
        return .{
            .events = evts,
            .capacity = cap,
            .head = std.atomic.Value(u64).init(0),
            .per_user_recent = std.mem.zeroes([64][16]u32),
            .per_user_count = std.mem.zeroes([64]u8),
        };
    }

    /// Record a delta event. Lock-free.
    pub fn record(self: *LivingMemory, ev: DeltaEvent) void {
        const idx = self.head.fetchAdd(1, .acq_rel) % self.capacity;
        self.events[idx] = ev;

        // Update per-user recent pointer.
        if (ev.user_id < 64) {
            const cnt = self.per_user_count[ev.user_id];
            shiftInU32(&self.per_user_recent[ev.user_id], @intCast(idx));
            if (cnt < 16) self.per_user_count[ev.user_id] = cnt + 1;
        }
    }

    /// Recall: replay deltas for a user + domain filter.
    pub fn recall(
        self: *const LivingMemory,
        user_id: u32,
        domain_filter: u8,
        out: []DeltaEvent,
    ) usize {
        if (user_id >= 64) return 0;
        const cnt = self.per_user_count[user_id];
        if (cnt == 0) return 0;
        var n: usize = 0;
        var i: usize = 0;
        while (i < cnt and n < out.len) : (i += 1) {
            const idx = self.per_user_recent[user_id][i];
            const ev = self.events[idx];
            if (domain_filter == 0xFF or ev.domain == domain_filter) {
                out[n] = ev;
                n += 1;
            }
        }
        return n;
    }

    /// Stats.
    pub fn totalEvents(self: *const LivingMemory) u64 {
        return self.head.load(.acquire);
    }
};

fn shiftInU32(arr: *[16]u32, val: u32) void {
    var i: usize = 15;
    while (i > 0) : (i -= 1) {
        arr[i] = arr[i - 1];
    }
    arr[0] = val;
}

test "living memory record and recall" {
    allocator.init();
    var mem = try LivingMemory.init(1024);

    mem.record(.{
        .timestamp = 1000,
        .user_id = 0,
        .event_type = .axiom_accessed,
        .domain = 0,
        ._pad = .{ 0, 0 },
        .target_id = 42,
        .confidence = 0.8,
        .payload = 0,
    });

    var out: [16]DeltaEvent = undefined;
    const n = mem.recall(0, 0xFF, &out);
    try std.testing.expect(n >= 1);
    try std.testing.expectEqual(@as(u32, 42), out[0].target_id);
}
