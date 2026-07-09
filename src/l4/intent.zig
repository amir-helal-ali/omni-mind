// src/l4/intent.zig — Theory of Mind (Intent Parsing).
//
// Don't analyze the query literally — analyze WHY it was asked.
// Build a 5D intent vector and a user model to infer subtext.

const std = @import("std");
const allocator = @import("../core/allocator.zig");

pub const IntentVector = extern struct {
    curiosity: f32, // 0-1: exploring concepts
    decision: f32, // 0-1: needs actionable answer
    verification: f32, // 0-1: fact-checking mode
    exploration: f32, // 0-1: open-ended brainstorming
    challenge: f32, // 0-1: skeptical, probing

    pub fn default() IntentVector {
        return .{
            .curiosity = 0.5,
            .decision = 0,
            .verification = 0,
            .exploration = 0,
            .challenge = 0,
        };
    }
};

pub const Expertise = enum(u8) { novice = 0, intermediate = 1, expert = 2 };

pub const UserModel = extern struct {
    user_id: u64,
    expertise: Expertise,
    preferred_depth: u8, // 0=shallow, 1=medium, 2=deep
    preferred_tone: u8, // 0=formal, 1=friendly, 2=technical
    last_5_topics: [5]u64, // Bloom sigs
    trust_score: f32,
};

pub const SubtextHint = enum {
    actionable_recommendation,
    steelman_counter,
    evidence_first,
    technical_depth,
    balanced_overview,
};

pub const IntentParser = struct {
    users: []UserModel,

    pub fn init(cap: usize) !IntentParser {
        const u = try allocator.allocAligned(UserModel, cap);
        // Zero-init
        for (u) |*um| um.* = std.mem.zeroes(UserModel);
        return .{ .users = u };
    }

    /// Parse a query into an intent vector. Zero allocations.
    pub fn parse(self: *IntentParser, query: []const u8, user_id: u64) IntentVector {
        var iv = IntentVector.default();

        // Lexical signals — marker word detection.
        if (containsAny(query, &[_][]const u8{ "should", "must", "best", "أفضل", "يجب" })) {
            iv.decision = 0.8;
        }
        if (containsAny(query, &[_][]const u8{ "is it true", "verify", "صحيح", "تحقق" })) {
            iv.verification = 0.8;
        }
        if (containsAny(query, &[_][]const u8{ "but", "however", "لكن", "لكن ماذا" })) {
            iv.challenge = 0.7;
        }
        if (std.mem.indexOf(u8, query, "why") != null or std.mem.indexOf(u8, query, "لماذا") != null) {
            iv.curiosity = 0.9;
        }
        if (std.mem.indexOf(u8, query, "how") != null or std.mem.indexOf(u8, query, "كيف") != null) {
            iv.exploration = 0.7;
        }

        // Update user model with current topic signature.
        if (user_id < self.users.len) {
            const um = &self.users[user_id];
            shiftInU64(&um.last_5_topics, @import("../core/mmap.zig").bloomSig(query));
        }

        return iv;
    }

    /// Infer the subtext hint from intent + user model.
    pub fn inferSubtext(iv: IntentVector, um: UserModel) SubtextHint {
        if (iv.decision > 0.6) return .actionable_recommendation;
        if (iv.challenge > 0.6) return .steelman_counter;
        if (iv.verification > 0.6) return .evidence_first;
        if (um.expertise == .expert) return .technical_depth;
        return .balanced_overview;
    }
};

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.mem.indexOf(u8, haystack, n) != null) return true;
    }
    return false;
}

fn shiftInU64(arr: *[5]u64, val: u64) void {
    var i: usize = 4;
    while (i > 0) : (i -= 1) {
        arr[i] = arr[i - 1];
    }
    arr[0] = val;
}

test "intent parse decision" {
    allocator.init();
    var p = try IntentParser.init(16);
    const iv = p.parse("what should I do about X?", 0);
    try std.testing.expect(iv.decision > 0.5);
}

test "intent parse curiosity" {
    allocator.init();
    var p = try IntentParser.init(16);
    const iv = p.parse("why does gravity bend light?", 0);
    try std.testing.expect(iv.curiosity > 0.5);
}
