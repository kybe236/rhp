const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const user_sraper = @import("user-scraper.zig");
const eql = std.mem.eql;

const site = "https://raw.githubusercontent.com/RusherDevelopment/rusherhack-plugins/main/README.md";
pub var debug = false;

pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    // Initialize the configuration
    var configure = config.Config.init(allocator);
    defer configure.deinit();
    // Load the configuration
    try configure.load(allocator);

    // Check if the user gave a plugin name
    if (args.len < 2) {
        std.debug.print("[-] Missing plugin name\n", .{});
        return;
    }

    const pluginName = args[1];
    if (eql(u8, pluginName, "--help")) {
        std.debug.print("Usage: rhp <plugin-name>\n", .{});
        return;
    }

    if (args.len > 2) {
        if (eql(u8, args[2], "debug")) {
            debug = true;
        }
    }

    // Initialize the scraper
    var scraper = Scraper.init(allocator);
    defer scraper.deinit();
    try scraper.scrape();

    // Make the lower name lowercase and remove newlines
    var lowerNameArray = std.ArrayList(u8).init(allocator);
    defer lowerNameArray.deinit();
    {
        const lowerName = try std.ascii.allocLowerString(allocator, pluginName);
        defer allocator.free(lowerName);
        for (lowerName) |c| {
            if (c == '\n' or c == '\r') {
                continue;
            }
            try lowerNameArray.append(c);
        }
    }

    // If theres no plugins return
    if (scraper.plugins == null) {
        std.debug.print("[-] No plugins found\n", .{});
        return;
    }

    var names = std.mem.splitAny(u8, pluginName, " ");
    for (scraper.plugins.?.items) |plugin| {
        if (plugin.name.items.len == 0) {
            continue;
        }

        var lowerPluginNameArray = std.ArrayList(u8).init(allocator);
        defer lowerPluginNameArray.deinit();
        {
            const lowerPluginName = try std.ascii.allocLowerString(allocator, plugin.name.items);
            defer allocator.free(lowerPluginName);
            for (lowerPluginName) |c| {
                if (c == '\n' or c == '\r') {
                    continue;
                }
                try lowerPluginNameArray.append(c);
            }
        }

        // Debug stuff
        if (debug) {
            std.debug.print("[DEBUG] Comparing {s} with {s}\n", .{ lowerNameArray.items, lowerPluginNameArray.items });
        }

        // Alow 1 typo for exact match
        if (try levenshteinDistance(allocator, lowerPluginNameArray.items, lowerNameArray.items) < 2) {
            std.debug.print("[+] Exact match: {s}\n", .{plugin.name.items});
            std.debug.print("[+] Description: {s}\n", .{plugin.description.items});
            std.debug.print("[+] Creator: {s}\n", .{plugin.creator.items});
            std.debug.print("[+] Creator link: {s}\n", .{plugin.creatorLink.items});
            std.debug.print("[+] URL: {s}\n", .{plugin.url.items});

            try user_sraper.scraper(allocator, plugin);

            return;
        }
    }

    var bestMatch = std.ArrayList(u8).init(allocator);
    defer bestMatch.deinit();

    while (names.peek() != null) {
        const name = names.next().?;
        const match = try getBestMatch(allocator, name, scraper);
        try bestMatch.appendSlice(match);
        try bestMatch.appendSlice(" ");
    }

    var bestMatchStr = std.mem.splitAny(u8, bestMatch.items, " ");
    var ranks = std.ArrayList(PluginRank).init(allocator);
    defer ranks.deinit();

    std.debug.print("[+] Correcting to ", .{});
    while (bestMatchStr.peek() != null) {
        const word = bestMatchStr.next().?;

        std.debug.print("{s} ", .{word});

        for (scraper.plugins.?.items) |plugin| {
            if (ranks.items.len == 0) {
                var rank = PluginRank{
                    .plugin = plugin,
                    .ocurrences = 0,
                };
                rank.countOcurrences(word);
                try ranks.append(rank);
            } else {
                for (ranks.items) |*rank| {
                    if (eql(u8, rank.plugin.name.items, plugin.name.items)) {
                        // Here i cant call it because i need mutiple rank
                        rank.countOcurrences(word);
                        break;
                    }
                } else {
                    var rank = PluginRank{
                        .plugin = plugin,
                        .ocurrences = 0,
                    };
                    rank.countOcurrences(word);
                    try ranks.append(rank);
                }
            }
        }
    }
    std.mem.sort(PluginRank, ranks.items, {}, lessThenRank);
    std.debug.print("\n", .{});

    if (ranks.items[0].ocurrences == 0) {
        std.debug.print("[-] No plugins found\n", .{});
        return;
    }

    if (debug) {
        std.debug.print("[DEBUG] Best match: {d}\n", .{ranks.items[0].ocurrences});
    }

    std.debug.print("[+] Best match for \"{s}\" is \"{s}\"\n", .{ pluginName, ranks.items[0].plugin.name.items });
    std.debug.print("[+] Description: {s}\n", .{ranks.items[0].plugin.description.items});
    std.debug.print("[+] Creator: {s}\n", .{ranks.items[0].plugin.creator.items});
    std.debug.print("[+] Creator link: {s}\n", .{ranks.items[0].plugin.creatorLink.items});
    std.debug.print("[+] URL: {s}\n", .{ranks.items[0].plugin.url.items});

    try user_sraper.scraper(allocator, ranks.items[0].plugin);
}

const PluginRank = struct {
    plugin: Plugin,
    ocurrences: u16,

    pub fn countOcurrences(self: *PluginRank, word: []const u8) void {
        var words = std.mem.splitAny(u8, self.plugin.name.items, " ");
        while (words.peek() != null) {
            const w = words.next().?;
            if (eql(u8, w, word)) {
                self.ocurrences += 1;
            }
        }
        var words_desc = std.mem.splitAny(u8, self.plugin.description.items, " ");
        while (words_desc.peek() != null) {
            const w = words_desc.next().?;
            if (eql(u8, w, word)) {
                self.ocurrences += 1;
            }
        }
        var words_creator = std.mem.splitAny(u8, self.plugin.creator.items, " ");
        while (words_creator.peek() != null) {
            const w = words_creator.next().?;
            if (eql(u8, w, word)) {
                self.ocurrences += 1;
            }
        }
    }
};

pub fn lessThenRank(context: void, self: PluginRank, other: PluginRank) bool {
    _ = context;
    return self.ocurrences > other.ocurrences;
}

pub fn getBestMatch(allocator: std.mem.Allocator, pluginName: []const u8, scraper: Scraper) ![]const u8 {
    var rank = std.ArrayList(NameRanking).init(allocator);
    defer rank.deinit();

    const lowerPluginName = try std.ascii.allocLowerString(allocator, pluginName);
    defer allocator.free(lowerPluginName);

    for (scraper.plugins.?.items) |plugin| {
        var name_words = std.mem.splitAny(u8, plugin.name.items, " ");
        while (name_words.peek() != null) {
            const word = name_words.next().?;

            // Get distance based on lowecased words
            const lowerWord = try std.ascii.allocLowerString(allocator, word);
            defer allocator.free(lowerWord);
            const distance = try levenshteinDistance(allocator, lowerWord, lowerPluginName);
            try rank.append(NameRanking{ .word = word, .distance = distance });
        }
        var words_desc = std.mem.splitAny(u8, plugin.description.items, " ");
        while (words_desc.peek() != null) {
            const word = words_desc.next().?;

            // Get distance based on lowecased words
            const lowerWord = try std.ascii.allocLowerString(allocator, word);
            defer allocator.free(lowerWord);
            const distance = try levenshteinDistance(allocator, lowerWord, lowerPluginName);
            try rank.append(NameRanking{ .word = word, .distance = distance });
        }

        var creator_words = std.mem.splitAny(u8, plugin.creator.items, " ");
        while (creator_words.peek() != null) {
            const word = creator_words.next().?;

            // Get distance based on lowecased words
            const lowerWord = try std.ascii.allocLowerString(allocator, word);
            defer allocator.free(lowerWord);
            const distance = try levenshteinDistance(allocator, lowerWord, lowerPluginName);
            try rank.append(NameRanking{ .word = word, .distance = distance });
        }
    }

    std.mem.sort(NameRanking, rank.items, {}, lessThen);
    return rank.items[0].word;
}

pub fn lessThen(context: void, self: NameRanking, other: NameRanking) bool {
    _ = context;
    return self.distance < other.distance;
}

const NameRanking = struct {
    word: []const u8,
    distance: u16,
};

pub const Plugin = struct {
    name: std.ArrayList(u8),
    description: std.ArrayList(u8),
    url: std.ArrayList(u8),
    creator: std.ArrayList(u8),
    creatorLink: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Plugin {
        return Plugin{
            .name = std.ArrayList(u8).init(allocator),
            .description = std.ArrayList(u8).init(allocator),
            .url = std.ArrayList(u8).init(allocator),
            .creator = std.ArrayList(u8).init(allocator),
            .creatorLink = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Plugin) void {
        self.name.deinit();
        self.description.deinit();
        self.url.deinit();
        self.creator.deinit();
        self.creatorLink.deinit();
    }
};

const Scraper = struct {
    allocator: std.mem.Allocator,
    plugins: ?std.ArrayList(Plugin),

    pub fn init(allocator: std.mem.Allocator) Scraper {
        return Scraper{
            .allocator = allocator,
            .plugins = std.ArrayList(Plugin).init(allocator),
        };
    }

    pub fn deinit(self: *Scraper) void {
        if (self.plugins != null) {
            for (self.plugins.?.items) |plugin| {
                plugin.creator.deinit();
                plugin.creatorLink.deinit();
                plugin.description.deinit();
                plugin.name.deinit();
                plugin.url.deinit();
            }
            self.plugins.?.deinit();
        }
    }

    pub fn scrape(self: *Scraper) !void {
        std.debug.print("[+] scraping started\n", .{});
        // Create a client
        var client = std.http.Client{
            .allocator = self.allocator,
        };
        defer client.deinit();

        // Buffer for the response (README.md)
        var response = std.ArrayList(u8).init(self.allocator);
        defer response.deinit();

        // Fetch the site
        const result = try client.fetch(.{
            .method = std.http.Method.GET,
            .location = .{ .url = site },
            .response_storage = .{ .dynamic = &response },
        });

        if (debug) {
            std.debug.print("[DEBUG] Response status: {d}\n", .{result.status});
        }

        if (result.status != std.http.Status.ok) {
            std.debug.print("[-] failed to fetch plugins", .{});
            std.debug.print("[-] status code: {d}\n", .{result.status});
            return;
        }

        var lines = std.mem.splitAny(u8, response.items, "\n");

        var plugin_lines = std.ArrayList(u8).init(self.allocator);
        defer plugin_lines.deinit();

        var at_start = true;
        while (lines.peek() != null) {
            const line = lines.next().?;
            if (eql(u8, line, "<!-- START PLUGINS LIST -->")) {
                at_start = false;
                continue;
            }
            if (at_start) {
                continue;
            }
            if (eql(u8, line, "<!-- END PLUGINS LIST -->")) {
                break;
            }
            try plugin_lines.appendSlice(line);
            try plugin_lines.appendSlice("\n");
        }
        std.debug.print("[+] found {d} plugins\n", .{1 + std.mem.count(u8, plugin_lines.items, "---")});

        var entries = std.mem.splitSequence(u8, plugin_lines.items, "---");

        while (entries.peek() != null) {
            const plugin = entries.next();
            if (plugin == null) {
                break;
            }

            var name: ?[]const u8 = null;
            var githubLink: ?[]const u8 = null;
            var creator: ?[]const u8 = null;
            var creatorLink: ?[]const u8 = null;
            var description: ?[]const u8 = null;

            var plugin_lin = std.mem.splitAny(u8, plugin.?, "\n");

            while (plugin_lin.peek() != null) {
                var line = plugin_lin.next();
                if (line == null) {
                    break;
                }
                if (line.?.len == 0) {
                    continue;
                }

                if (std.mem.startsWith(u8, line.?, "### [")) {
                    const nameStart = std.mem.indexOf(u8, line.?, "[");
                    const nameEnd = std.mem.indexOf(u8, line.?, "](https://");

                    if (nameStart != null and nameEnd != null and nameStart.? < nameEnd.?) {
                        name = line.?[nameStart.? + 1 .. nameEnd.?];
                    }

                    const linkStart = std.mem.indexOf(u8, line.?, "https://");
                    const linkEnd = std.mem.indexOf(u8, line.?, ") <br>");

                    if (linkStart != null and linkEnd != null and linkStart.? < linkEnd.?) {
                        githubLink = line.?[linkStart.?..linkEnd.?];
                    }
                } else if (std.mem.startsWith(u8, line.?, "**Creator**: ")) {
                    const creatorStart = std.mem.indexOf(u8, line.?, "> [");
                    const creatorEnd = std.mem.indexOf(u8, line.?, "](https://");
                    if (creatorStart != null and creatorEnd != null and creatorStart.? < creatorEnd.?) {
                        creator = line.?[creatorStart.? + 3 .. creatorEnd.?];
                    }
                    const creatorLinkStart = std.mem.indexOf(u8, line.?, "](https://");
                    const creatorLinkEnd = std.mem.indexOf(u8, line.?, ")");
                    if (creatorLinkStart != null and creatorLinkEnd != null and creatorLinkStart.? < creatorLinkEnd.?) {
                        creatorLink = line.?[creatorLinkStart.? + 2 .. creatorLinkEnd.?];
                    }
                } else if (std.mem.indexOf(u8, line.?, "<details>") != null or
                    std.mem.indexOf(u8, line.?, "</details>") != null or
                    std.mem.indexOf(u8, line.?, "<summary>") != null or
                    std.mem.indexOf(u8, line.?, "</summary>") != null or
                    std.mem.indexOf(u8, line.?, "<p align=\"center\">") != null or
                    std.mem.indexOf(u8, line.?, "</p>") != null or
                    std.mem.indexOf(u8, line.?, "<img src=") != null or
                    std.mem.indexOf(u8, line.?, "</a>") != null or
                    std.mem.indexOf(u8, line.?, "<a href=") != null)
                {
                    continue;
                } else if (line.?.len > 1) {
                    description = line.?;
                }
            }

            // Automatically report missing information
            if (name == null or githubLink == null or creator == null or description == null or creatorLink == null) {
                std.debug.print("--------------------------------------\n", .{});
                std.debug.print("[-] Detected missing information\n", .{});
                std.debug.print("[-] Please contact maintainer\n", .{});
                if (name == null) {
                    std.debug.print("[-] Missing name\n", .{});
                }
                if (githubLink == null) {
                    std.debug.print("[-] Missing github link\n", .{});
                }
                if (creator == null) {
                    std.debug.print("[-] Missing creator\n", .{});
                }
                if (description == null) {
                    std.debug.print("[-] Missing description\n", .{});
                }
                if (creatorLink == null) {
                    std.debug.print("[-] Missing creator link\n", .{});
                }
                std.debug.print("[+] Printing known information about missing plugin\n", .{});
                if (name != null) {
                    std.debug.print("[-] Name: {s}\n", .{name.?});
                }
                if (githubLink != null) {
                    std.debug.print("[-] Github link: {s}\n", .{githubLink.?});
                }
                if (creator != null) {
                    std.debug.print("[-] Creator: {s}\n", .{creator.?});
                }
                if (description != null) {
                    std.debug.print("[-] Description: {s}\n", .{description.?});
                }
                if (creatorLink != null) {
                    std.debug.print("[-] Creator link: {s}\n", .{creatorLink.?});
                }
                std.debug.print("--------------------------------------\n", .{});
            }

            var plugin_struct = Plugin{
                .name = std.ArrayList(u8).init(self.allocator),
                .description = std.ArrayList(u8).init(self.allocator),
                .url = std.ArrayList(u8).init(self.allocator),
                .creator = std.ArrayList(u8).init(self.allocator),
                .creatorLink = std.ArrayList(u8).init(self.allocator),
            };

            if (name != null) {
                try plugin_struct.name.appendSlice(name.?);
            }
            if (githubLink != null) {
                try plugin_struct.url.appendSlice(githubLink.?);
            }
            if (creator != null) {
                try plugin_struct.creator.appendSlice(creator.?);
            }
            if (description != null) {
                try plugin_struct.description.appendSlice(description.?);
            }
            if (creatorLink != null) {
                try plugin_struct.creatorLink.appendSlice(creatorLink.?);
            }

            if (debug) {
                std.debug.print("[DEBUG] Plugin name: {s}\n", .{plugin_struct.name.items});
                std.debug.print("[DEBUG] Plugin description: {s}\n", .{plugin_struct.description.items});
                std.debug.print("[DEBUG] Plugin creator: {s}\n", .{plugin_struct.creator.items});
                std.debug.print("[DEBUG] Plugin creatorLink: {s}\n", .{plugin_struct.creatorLink.items});
                std.debug.print("[DEBUG] Plugin URL: {s}\n", .{plugin_struct.url.items});
            }

            try self.plugins.?.append(plugin_struct);
        }
    }
};

inline fn idx(i: usize, j: usize, cols: usize) usize {
    return i * cols + j;
}

pub fn levenshteinDistance(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !u16 {
    const n = a.len;
    const m = b.len;
    const table = try allocator.alloc(u8, n * m);
    defer allocator.free(table);
    table[0] = 0;

    for (0..n) |i| {
        for (0..m) |j| {
            table[idx(i, j, m)] = @min(
                (if (i == 0)
                    @as(u8, @truncate(j))
                else
                    table[idx(i - 1, j, m)]) + 1,
                (if (j == 0)
                    @as(u8, @truncate(i))
                else
                    table[idx(i, j - 1, m)]) + 1,
                (if (i == 0)
                    @as(u8, @truncate(j))
                else if (j == 0)
                    @as(u8, @truncate(i))
                else
                    table[idx(i - 1, j - 1, m)]) +
                    @intFromBool(a[i] != b[j]),
            );
        }
    }
    return table[table.len - 1];
}
