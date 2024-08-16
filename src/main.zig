const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // Deinitialize the allocator at the end
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args); // Free args after use

    // Print arguments
    std.debug.print("Arguments: ", .{});
    for (args) |arg| {
        std.debug.print("{s} ", .{arg});
    }
    std.debug.print("\n", .{});

    // Call cli code
    try cli.handle(allocator, args);
}
