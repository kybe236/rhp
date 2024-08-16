const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const eql = std.mem.eql;

const site = "https://raw.githubusercontent.com/RusherDevelopment/rusherhack-plugins/main/README.md";

pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var configure = config.Config.init(allocator);
    defer configure.deinit();
    try configure.load(allocator);

    if (args.len < 2) {
        std.debug.print("[-] Missing plugin name\n", .{});
        return;
    }

    const pluginName = args[1];
    if (eql(u8, pluginName, "--help")) {
        std.debug.print("Usage: rhp <plugin-name>\n", .{});
        return;
    }

    try getPlugins(allocator);
}

pub fn getPlugins(allocator: std.mem.Allocator) !void {
    var scraper = Scraper.init(allocator);
    defer scraper.deinit();

    try scraper.scrape();
}

const Plugin = struct {
    name: std.ArrayList(u8),
    description: std.ArrayList(u8),
    url: std.ArrayList(u8),
    img: std.ArrayList(u8),
};

const Scraper = struct {
    allocator: std.mem.Allocator,
    plugins: ?std.ArrayList(Plugin),

    pub fn init(allocator: std.mem.Allocator) Scraper {
        return Scraper{
            .allocator = allocator,
            .plugins = null,
        };
    }

    pub fn deinit(self: *Scraper) void {
        if (self.plugins != null) {
            self.plugins.?.deinit();
        }
    }

    pub fn scrape(self: *Scraper) !void {
        std.debug.print("[+] scraping started", .{});
        var client = std.http.Client{
            .allocator = self.allocator,
        };
        defer client.deinit();

        var response = std.ArrayList(u8).init(self.allocator);
        defer response.deinit();

        const result = try client.fetch(.{
            .method = std.http.Method.GET,
            .location = .{ .url = site },
            .response_storage = .{ .dynamic = &response },
        });

        if (result.status != std.http.Status.ok) {
            std.debug.print("[-] failed to fetch plugins", .{});
            std.debug.print("[-] status code: {d}\n", .{result.status});
            return;
        }

        var lines = std.mem.splitAny(u8, response.items, "\n");
        defer lines.deinit();

        var at_start = true;
        while (true) {
            var line = lines.next();
            if (line == null) {
                continue;
            }
            line = line.?;
            if (eql(u8, line, "<!-- START PLUGINS LIST -->")) {
                at_start = false;
                continue;
            }
            if (eql(u8, line, "<!-- END PLUGINS LIST -->")) {
                break;
            }
        }
    }
};
