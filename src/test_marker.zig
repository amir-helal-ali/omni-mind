// Quick test: does indexOf find the Arabic marker?
const std = @import("std");

pub fn main() !void {
    const answer = "هناك شك في أن: المجال: الفيزياء. الثقة: 0.41. الزمن: 1 مللي ثانية.";
    const marker = "الثقة";

    std.debug.print("answer len: {d}\n", .{answer.len});
    std.debug.print("marker len: {d}\n", .{marker.len});

    if (std.mem.indexOf(u8, answer, marker)) |idx| {
        std.debug.print("Found marker at index {d}\n", .{idx});
        // Print bytes around the marker
        std.debug.print("answer[{d}..{d}] = ", .{ idx, idx + marker.len });
        for (answer[idx .. idx + marker.len]) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\n", .{});
    } else {
        std.debug.print("Marker NOT found\n", .{});
        // Print all bytes
        std.debug.print("answer bytes: ", .{});
        for (answer) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\n", .{});
        std.debug.print("marker bytes: ", .{});
        for (marker) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\n", .{});
    }
}
