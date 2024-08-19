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
pub const main_log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.print("leak", .{});
    };
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    const debug = env.get("DEBUG");
    if (debug != null) {
        if (std.mem.indexOf(u8, debug.?, "true") != null) {
            log_level = .debug;
        } else {
            log_level = .info;
        }
    } else {
        log_level = .info;
    }

    // Print arguments
    main_log.debug("Arguments: ", .{});
    if (std.options.log_level == .debug) {
        for (args) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print("\n", .{});
    }

    // Call cli code
    try cli.handle(allocator, args);
}

pub const std_options = std.Options{
    .logFn = log,
};

// Custom log function
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (log_level != .debug and message_level == .debug) {
        return;
    }

    const color = switch (message_level) {
        .debug => "",
        .info => "\u{001b}[32m",
        .warn => "\u{001b}[93m",
        .err => "\u{001b}[31m",
    };

    const reset = "\u{001b}[m";

    const scope_txt = "(" ++ color ++ @tagName(scope) ++ reset ++ ") ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    const lvl_txt = switch (message_level) {
        .debug => "[DEBUG] ",
        .info => "[\u{001b}[32m+\u{001b}[m] ",
        .warn => "[\u{001b}[93m-\u{001b}[m] ",
        .err => "[\u{001b}[31mERROR\u{001b}[m] ",
    };

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(scope_txt ++ lvl_txt ++ format, args) catch return;
        bw.flush() catch return;
    }
}
