const std = @import("std");
const config = @import("config.zig");
const plugin_l = @import("plugin.zig");

pub fn scraper(allocator: std.mem.Allocator, plugin: plugin_l.Plugin) !void {
    const download = DownloadSite{ .plugin = plugin, .url = null };
    _ = allocator;
    _ = download;
    std.debug.print("Scraper\n", .{});
}

const DownloadSite = struct {
    plugin: plugin_l.Plugin,
    url: ?[]const u8,

    pub fn scrape(allocator: std.mem.Allocator) !void {
        var client = std.http.Client.init(allocator);
        defer client.deinit();
    }
};
