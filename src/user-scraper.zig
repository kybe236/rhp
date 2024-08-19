const std = @import("std");
const config = @import("config.zig");
const plugin_l = @import("plugin.zig");

const log = std.log.scoped(.user_scraper);

pub fn scraper(allocator: std.mem.Allocator, plugin: plugin_l.Plugin, config_a: config.Config) !void {
    var download = try DownloadSite.init(allocator, plugin);
    defer download.deinit();

    download.config = config_a;
    try download.scrape(allocator);
}

const Asset = struct {
    name: std.ArrayList(u8),
    url: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Asset) void {
        self.name.deinit();
        self.url.deinit();
    }

    pub fn init(allocator: std.mem.Allocator) Asset {
        const self = Asset{
            .name = std.ArrayList(u8).init(allocator),
            .url = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
        return self;
    }
};

const DownloadSite = struct {
    plugin: plugin_l.Plugin,
    url: std.ArrayList(u8),
    downloadUrl: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    assets: std.ArrayList(u8),
    config: ?config.Config,

    pub fn deinit(self: *DownloadSite) void {
        self.url.deinit();
        self.downloadUrl.deinit();
        self.assets.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, plugin: plugin_l.Plugin) !DownloadSite {
        const self = DownloadSite{
            .plugin = plugin,
            .url = std.ArrayList(u8).init(allocator),
            .downloadUrl = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .assets = std.ArrayList(u8).init(allocator),
            .config = null,
        };
        return self;
    }

    pub fn scrape(self: *DownloadSite, allocator: std.mem.Allocator) !void {
        try self.getTag(allocator);
        if (self.url.items.len == 0) {
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
        try self.getDownloadLink(allocator, tag);

        var assets = std.mem.splitAny(u8, self.assets.items, " ");
        var assets_list = std.ArrayList(Asset).init(allocator);
        defer assets_list.deinit();

        var i: u32 = 0;
        while (assets.next()) |asset| {
            i += 1;
            if (asset.len == 0) {
                continue;
            }

            // Create asset struct
            var asset_struct = Asset.init(allocator);

            // append the url
            try asset_struct.url.appendSlice(asset);

            // get the least /
            // Example asset:
            //                                                                         | here
            // https://github.com/John200410/rusherhack-spotify/releases/download/1.1.7/rusherhack-spotify-1.1.7.jar
            const start = std.mem.lastIndexOf(u8, asset, "/");
            if (start == null) {
                continue;
            }

            // append the name
            try asset_struct.name.appendSlice(asset[start.? + 1 ..]);

            try stdout.print("ASSET {d} ({s}): {s}\n", .{ i, asset[start.? + 1 ..], asset });

            try assets_list.append(asset_struct);
        }
        defer {
            for (assets_list.items) |*asset| {
                asset.*.deinit();
            }
        }

        try stdout.print("Select the asset to download:\n-> ", .{});

        const stdin = std.io.getStdIn().reader();
        const inp = try stdin.readUntilDelimiterAlloc(allocator, '\n', 100);
        defer allocator.free(inp);

        if (inp.len == 0) {
            log.err("No input provided", .{});
            return;
        }

        const selection = try std.fmt.parseInt(u32, inp, 10);

        std.debug.print("Asset number: {d}\n", .{selection});

        if (selection >= assets_list.items.len or selection < 0) {
            log.err("Invalid asset number provided", .{});
            return;
        }

        const asset = assets_list.items[selection - 1];

        log.debug("Downloading asset: {s}\n", .{asset.name.items});

        try self.downloadAsset(allocator, asset);
    }

    fn downloadAsset(self: *DownloadSite, allocator: std.mem.Allocator, asset: Asset) !void {
        // Initialize http client
        log.debug("Downloading asset: {s}\n", .{asset.name.items});
        log.debug("URL: {s}\n", .{asset.url.items});

        // Get the http client
        var client = std.http.Client{
            .allocator = allocator,
        };
        defer client.deinit();

        // Initialize response buffer
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        // Fetch options for a GET request
        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = asset.url.items },
            .response_storage = .{ .dynamic = &response },
            .method = .GET,
        };
        // The response code is saved
        const result = try client.fetch(fetch_options);
        log.debug("Status: {d}\n", .{result.status});

        var path = std.ArrayList(u8).init(allocator);
        defer path.deinit();
        try path.appendSlice(self.config.?.mc_path.items);

        if (self.config.?.subnames) {
            // Add instances to the path
            log.info("Enter the instance name: ", .{});

            const stdin = std.io.getStdIn().reader();
            const instance_name = try stdin.readUntilDelimiterAlloc(allocator, '\n', 100);
            defer allocator.free(instance_name);

            try path.appendSlice("/");
            try path.appendSlice(instance_name);

            // Patching the config
            if (self.config.?.cfg) {
                var config_path = std.ArrayList(u8).init(allocator);
                defer config_path.deinit();

                try config_path.appendSlice(path.items);
                try config_path.appendSlice("/instance.cfg");

                log.info("Config path: {s}\n", .{config_path.items});

                // Open the file
                var file = try std.fs.openFileAbsolute(config_path.items, .{ .mode = .read_write });
                defer file.close();

                const contents = try file.readToEndAlloc(allocator, 10000);
                defer allocator.free(contents);

                if (std.mem.indexOf(u8, contents, "-Drusherhack.enablePlugins=true") != null) {
                    log.info("Plugin support is already enabled\n", .{});
                } else {
                    log.info("Plugin support is not enabled\n", .{});
                    const msg =
                        \\WARNING: DO NOT ENABLE PLUGINS IF YOU DO NOT KNOW WHAT YOU ARE DOING.
                        \\*Plugins are currently only able to be loaded in developer mode.
                        \\IF YOU DONT KNOW WHAT YOU ARE DOING, DO NOT ENABLE PLUGINS.
                        \\*Eventually in rusherhack v2.1 there will be an in-game plugin manager and repository for verified plugins.
                        \\Would you like to enable plugins? (y/n): 
                    ;
                    const stdout = std.io.getStdOut().writer();
                    try stdout.print("\u{001b}[31m{s}\n-> \u{001b}[m", .{msg});
                    const answer = try stdin.readUntilDelimiterAlloc(allocator, '\n', 100);
                    defer allocator.free(answer);

                    if (answer.len == 0) {
                        log.err("No input provided", .{});
                        return;
                    }

                    if (answer[0] != 'y') {
                        log.info("Plugin support not enabled\n", .{});
                        return;
                    }

                    const start = std.mem.indexOf(u8, contents, "JvmArgs=");
                    if (start == null) {
                        try file.writeAll("-Drusherhack.enablePlugins=true");
                    } else {
                        const end = std.mem.indexOf(u8, contents[start.?..], "\n");

                        if (start == null or end == null) {
                            log.err("No JVM arguments found.\nIf you use official disable cfg in the config", .{});
                            return;
                        }

                        log.debug("Contents: {s}\n", .{contents[start.? .. end.? + start.?]});

                        var jvm_line = std.ArrayList(u8).init(allocator);
                        defer jvm_line.deinit();
                        try jvm_line.appendSlice(contents[start.? .. end.? + start.?]);
                        if (jvm_line.items.len == 0) {
                            log.err("No JVM arguments found", .{});
                            return;
                        }
                        if (std.mem.containsAtLeast(u8, jvm_line.items, 2, "\"")) {
                            const start_index = std.mem.indexOf(u8, jvm_line.items, "\"");
                            const end_index = std.mem.lastIndexOf(u8, jvm_line.items, "\"");
                            if (start_index == null or end_index == null) {
                                return;
                            }
                            if (end_index.? == start_index.? + 1) {
                                log.info("No JVM arguments found adding plugin argument to end", .{});
                                jvm_line.shrinkAndFree(jvm_line.items.len - 1);
                                try jvm_line.appendSlice("-Drusherhack.enablePlugins=true\"");
                            } else {
                                log.info("Multiple JVM arguments found adding plugin argument to end", .{});
                                jvm_line.shrinkAndFree(jvm_line.items.len - 1);
                                try jvm_line.appendSlice(" -Drusherhack.enablePlugins=true\"");
                            }
                        } else {
                            log.info("No JVM argument found adding plugin argument", .{});
                            try jvm_line.appendSlice("\"-Drusherhack.enablePlugins=true\"");
                        }

                        var new_contents = std.ArrayList(u8).init(allocator);
                        defer new_contents.deinit();

                        try new_contents.appendSlice(contents[0..start.?]);
                        try new_contents.appendSlice(jvm_line.items);
                        try new_contents.appendSlice(contents[end.? + start.? ..]);

                        log.debug("New contents: {s}\n", .{new_contents.items});

                        try file.seekTo(0);
                        try file.writeAll(new_contents.items);
                    }
                }
            }
            try path.appendSlice("/.minecraft/");
        }

        try path.appendSlice("/rusherhack/plugins/");
        // create folder "plugins" if it doesn't exist
        std.fs.makeDirAbsolute(path.items) catch |err| {
            if (err == std.fs.Dir.MakeError.PathAlreadyExists) {
                log.info("Folder already exists\n", .{});
            } else {
                log.err("Failed to create folder: {s}\n", .{path.items});
                return err;
            }
        };

        var folder = try std.fs.openDirAbsolute(path.items, .{ .access_sub_paths = true });
        defer folder.close();
        log.info("Saving to: {s}{s}\n", .{ path.items, asset.name.items });
        var out = try folder.createFile(asset.name.items, .{});
        defer out.close();

        try out.writeAll(response.items);
        log.info("Downloaded asset: {s}\n", .{asset.name.items});
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

        log.debug("Fetching: {s}\n", .{self.downloadUrl.items});

        // Fetch the releases page
        const result = try client.fetch(fetch_options);

        log.debug("Status: {d}\n", .{result.status});

        // Split the response into lines
        var lines = std.mem.splitAny(u8, response.items, "\n");

        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "href=\"") != null) {
                const start = std.mem.indexOf(u8, line, "href=\"");
                const end = std.mem.indexOf(u8, line, "\" rel=\"nofollow\"");
                if (start == null or end == null) {
                    continue;
                }

                try self.assets.appendSlice("https://github.com");
                try self.assets.appendSlice(line[start.? + 6 .. end.?]);
                try self.assets.appendSlice(" ");
            }
        }
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
                break;
            }
        }
    }
};
