const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");

const leakmsg =
    \\ Memory leak detected
    \\ Pls contact owner (kybe236 on dc)
    \\ Or open an issue on the repo
    \\ Please also append debug if your're running a plugin install
    \\ Thank you for your cooperation
;

pub var log_level: std.log.Level = .info;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.print("{s}\n", .{leakmsg});
    };
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    const debug = env.get("DEBUG");
    if (debug != null) {
        log_level = .debug;
    }

    // Print arguments
    std.debug.print("Arguments: ", .{});
    for (args) |arg| {
        std.debug.print("{s} ", .{arg});
    }
    std.debug.print("\n", .{});

    // Call cli code
    try cli.handle(allocator, args);
}
