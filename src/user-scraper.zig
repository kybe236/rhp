const std = @import("std");
const config = @import("config.zig");
const plugin_l = @import("plugin.zig");

pub fn scraper(allocator: std.mem.Allocator, plugin: plugin_l.Plugin) !void {
    var download = DownloadSite{ .plugin = plugin, .url = null };
    try download.scrape(allocator);
    std.debug.print("Scraper\n", .{});
}

const DownloadSite = struct {
    plugin: plugin_l.Plugin,
    url: ?[]const u8,

    pub fn scrape(self: *DownloadSite, allocator: std.mem.Allocator) !void {
        var client = std.http.Client{
            .allocator = allocator,
        };

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = self.plugin.url.items },
            .response_storage = .{ .dynamic = &response },
        };

        const result = try client.fetch(fetch_options);

        if (plugin_l.debug) {
            std.debug.print("Response: {}\n", .{result.status});
        }

        var lines = std.mem.splitAny(u8, response.items, "\n");
        while (lines.peek() != null) {
            const line = lines.next().?;
            std.debug.print("Line: {s}\n", .{line});
            if (std.mem.indexOf(u8, line, "<a href=\"") != null and
                std.mem.indexOf(u8, line, "\" data-view-component=\"true\" class=\"Link--primary Link\" data-turbo-frame=\"repo-content-turbo-frame\">") != null and
                std.mem.indexOf(u8, line, "</a>") != null)
            {
                const start = std.mem.indexOf(u8, line, "href=\"");
                const end = std.mem.indexOf(u8, line, "\" data-view-component=\"true\" class=\"Link--primary Link\" data-turbo-frame=\"repo-content-turbo-frame\">");
                if (start == null or end == null) {
                    continue;
                }

                const url = line[start.? + 6 .. end.?];
                if (std.mem.indexOf(u8, url, "https://") == null) {
                    continue;
                }

                if (plugin_l.debug) {
                    std.debug.print("[DEBUG] URL: {s}\n", .{url});
                }

                self.url = url;
                break;
            }
        }

        defer client.deinit();
    }
};
