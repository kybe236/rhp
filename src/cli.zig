const std = @import("std");
const config = @import("config.zig");

// The main function for the cli
pub fn handle(allocator: std.mem.Allocator, args: [][:0]u8) void {
    _ = allocator;
    _ = args;
}
