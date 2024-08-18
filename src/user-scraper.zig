const std = @import("std");
const config = @import("config.zig");
const plugin_l = @import("plugin.zig");

const log = std.log.scoped(.user_scraper);

pub fn scraper(allocator: std.mem.Allocator, plugin: plugin_l.Plugin) !void {
    var download = try DownloadSite.init(allocator, plugin);
    try download.scrape(allocator);
    defer download.deinit();
}

const DownloadSite = struct {
    plugin: plugin_l.Plugin,
    url: std.ArrayList(u8),
    downloadUrl: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DownloadSite) void {
        self.url.deinit();
        self.downloadUrl.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, plugin: plugin_l.Plugin) !DownloadSite {
        const self = DownloadSite{
            .plugin = plugin,
            .url = std.ArrayList(u8).init(allocator),
            .downloadUrl = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
        return self;
    }

    pub fn scrape(self: *DownloadSite, allocator: std.mem.Allocator) !void {
        try self.getTag(allocator);
        if (self.url.items.len == 0) {
            // TODO add manually compiling maybe?
            log.err("No release tag found", .{});
            return;
        }

        const tag_start = std.mem.indexOf(u8, self.url.items, "/tag/");
        if (tag_start == null) {
            log.err("No release tag found", .{});
            return;
        }
        const tag = self.url.items[tag_start.? + 5 ..];
        const stdout = std.io.getStdOut().writer();
        try stdout.print("TAG: {s}\n", .{tag});
        try stdout.print("LATEST_RELEASE: {s}\n", .{self.url.items});
        try self.getDownloadLink(allocator, tag); // works fine if this is commented out
    }

    fn getDownloadLink(self: *DownloadSite, allocator: std.mem.Allocator, tag: []const u8) !void {
        // Initialize http client
        var client = std.http.Client{
            .allocator = allocator,
        };
        defer client.deinit();

        // Response
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        self.downloadUrl.shrinkAndFree(0); // Ensure the URL is empty
        try self.downloadUrl.appendSlice(self.plugin.url.items);
        try self.downloadUrl.appendSlice("/releases/expanded_assets/");
        try self.downloadUrl.appendSlice(tag);

        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = self.downloadUrl.items },
            .response_storage = .{ .dynamic = &response },
        };

        log.info("Fetching: {s}\n", .{self.downloadUrl.items});

        // Fetch the releases page
        const result = try client.fetch(fetch_options);

        log.debug("Status: {d}\n", .{result.status});
    }

    fn getTag(self: *DownloadSite, allocator: std.mem.Allocator) !void {
        // Initialize http client
        var client = std.http.Client{
            .allocator = allocator,
        };
        defer client.deinit();

        // Response
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        // Get the releases page
        var rurl = std.ArrayList(u8).init(allocator);
        try rurl.appendSlice(self.plugin.url.items);
        try rurl.appendSlice("/releases");
        log.debug("URL: {s}\n", .{rurl.items});
        self.downloadUrl = rurl;

        // Save response to response
        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = rurl.items },
            .response_storage = .{ .dynamic = &response },
        };

        // Fetch the releases page
        const result = try client.fetch(fetch_options);

        log.debug("Result: {d}\n", .{result.status});

        // Split the response into lines
        var lines = std.mem.splitAny(u8, response.items, "\n");
        while (lines.peek() != null) {
            const line = lines.next().?;

            // Check if the line contains the tag (Big header name)
            if (std.mem.indexOf(u8, line, "<span data-view-component=\"true\" class=\"f1 text-bold d-inline mr-3\"><a href=\"") != null and
                std.mem.indexOf(u8, line, "\" data-view-component=\"true\" class=\"Link--primary Link\">") != null and
                std.mem.indexOf(u8, line, "</a></span>") != null)
            {
                log.debug("Line: {s}\n", .{line});
                const start = std.mem.indexOf(u8, line, "href=\"");
                const end = std.mem.indexOf(u8, line, "\" data-view-component=\"true\" class=\"Link--primary Link\">");
                if (start == null or end == null) {
                    continue;
                }

                var url = std.ArrayList(u8).init(allocator);
                try url.appendSlice("https://github.com");
                try url.appendSlice(line[start.? + 6 .. end.?]);

                // Deinitialize old URL if it exists
                if (self.url.items.len != 0) {
                    self.url.deinit();
                }

                self.url = url;
            }
        }
    }
};
