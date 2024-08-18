const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const plugin = @import("plugin.zig");
const eql = std.mem.eql;
const usage =
    \\ Unknown command
    \\ Usage: pluginname
    \\ Usage: --config <set|get>
    \\  set <key> <value>
    \\  get <key>
    \\ 
;
const msg =
    \\[-] Missing key or value
    \\Usage: --config set <key> <value>
    \\key are mc_path, subnames, cfg
;

// The main function for the cli
pub fn handle(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    // --config to configure rhp
    if (args.len > 1) {
        if (eql(u8, args[1], "--config")) {
            if (args.len > 2) {
                if (eql(u8, args[2], "set")) { // --config set <key> <value>
                    var configure = Configure.init(allocator, args);
                    try configure.set();
                    configure.deinit();
                    return;
                } else if (eql(u8, args[2], "get")) { // --config get <key>
                    var configure = Configure.init(allocator, args);
                    try configure.get();
                    configure.deinit();
                    return;
                } else {
                    std.debug.print(usage, .{});
                }
            } else if (args.len == 2) {
                var configure = Configure.init(allocator, args);
                try configure.setup();
                try configure.config.save(allocator);
                configure.deinit();
            }
        } else {
            try plugin.init(allocator, args);
        }
    } else {
        std.debug.print(usage, .{});
    }
}

const Launcher = enum {
    Official,
    MultiMC,
    PrismLauncher,
    CustomPath,
};

const Configure = struct {
    allocator: std.mem.Allocator,
    args: [][:0]u8,
    config: config.Config,

    pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) Configure {
        return Configure{
            .allocator = allocator,
            .args = args,
            .config = config.Config.init(allocator),
        };
    }

    pub fn deinit(self: *Configure) void {
        self.config.deinit();
    }

    pub fn set(self: *Configure) !void {
        // --config set <key> <value>
        if (self.args.len < 5) {
            std.debug.print("{s}", .{msg});
            return;
        }
        if (self.args.len > 5) {
            std.debug.print("{s}", .{msg});
            return;
        }
        const key = self.args[3];
        const value = self.args[4];
        try self.config.set(key, value, self.allocator);
        try self.config.save(self.allocator);
    }
    pub fn get(self: *Configure) !void {
        // --config get <key>
        if (self.args.len < 4) {
            std.debug.print("[-] Missing key\n", .{});
            return;
        }
        if (self.args.len > 4) {
            std.debug.print("[-] Too many arguments\n", .{});
            return;
        }
        const key = self.args[3];
        try self.config.load(self.allocator);
        const value = self.config.get(key);
        std.debug.print("{s}: {s}\n", .{ key, value });
    }

    pub fn setup(self: *Configure) !void {
        // --config setup
        if (self.args.len > 3) {
            std.debug.print("[-] Too many arguments\n", .{});
            std.debug.print("Usage: --config setup\n", .{});
            return;
        }
        std.debug.print("[+] Setting up rhp\n", .{});
        std.debug.print("Select a launcher:\n", .{});
        std.debug.print("1. Official\n", .{});
        std.debug.print("2. MultiMC (For windows use custom path)\n", .{});
        std.debug.print("3. PrismLauncher\n", .{});
        std.debug.print("4. Custom Path\n", .{});
        std.debug.print("Enter the number of the launcher: ", .{});

        const input = try std.io.getStdIn().reader().readUntilDelimiterAlloc(self.allocator, '\n', 10000);
        defer self.allocator.free(input);
        if (input.len == 0) {
            std.debug.print("[-] Invalid input\n", .{});
            return;
        }
        const launcher = Configure.getLauncher(input);
        try self.setLauncher(launcher);
    }

    fn getLauncher(input: []const u8) Launcher {
        if (eql(u8, input, "1")) {
            return Launcher.Official;
        } else if (eql(u8, input, "2")) {
            return Launcher.MultiMC;
        } else if (eql(u8, input, "3")) {
            return Launcher.PrismLauncher;
        } else if (eql(u8, input, "4")) {
            return Launcher.CustomPath;
        } else {
            return Launcher.Official;
        }
    }

    pub fn setLauncher(self: *Configure, launcher: Launcher) !void {
        switch (launcher) {
            Launcher.Official => {
                var env = try config.GetAppdataPath(self.allocator);
                self.config.subnames = false;
                self.config.cfg = false;

                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.minecraft");
                    },
                    .windows => {
                        try env.appendSlice("/.minecraft");
                    },
                    else => {
                        std.debug.print("[-] Unsupported OS\n", .{});
                        return null;
                    },
                }
                self.config.mc_path = env;
            },
            Launcher.MultiMC => {
                var env = try config.GetAppdataPath(self.allocator);
                self.config.cfg = true;
                self.config.subnames = true;

                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/multimc");
                    },
                    .windows => {
                        std.debug.print("Use Custom path instead because theres no default: ", .{});
                    },
                    else => {
                        std.debug.print("[-] Unsupported OS\n", .{});
                        return null;
                    },
                }

                self.config.mc_path = env;
            },
            Launcher.PrismLauncher => {
                var env = try config.GetAppdataPath(self.allocator);
                self.config.cfg = true;
                self.config.subnames = true;

                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/PrismLauncher");
                    },
                    .windows => {
                        std.debug.print("Use Custom path instead because theres no default: ", .{});
                    },
                    else => {
                        std.debug.print("[-] Unsupported OS\n", .{});
                        return null;
                    },
                }

                self.config.mc_path = env;
            },
            Launcher.CustomPath => {
                std.debug.print("Enter the path to the launcher: ", .{});
                const input = try std.io.getStdIn().reader().readUntilDelimiterAlloc(self.allocator, '\n', 10000);
                defer self.allocator.free(input);
                if (input.len == 0) {
                    std.debug.print("[-] Invalid input\n", .{});
                    return;
                }
                var env = try config.GetAppdataPath(self.allocator);
                try env.appendSlice(input);
                self.config.mc_path = env;

                std.debug.print("Does your launcher use subnames? (y/n): ", .{});
                const subnames = try std.io.getStdIn().reader().readUntilDelimiterAlloc(self.allocator, '\n', 10000);
                defer self.allocator.free(subnames);
                if (subnames.len == 0) {
                    std.debug.print("[-] Invalid input\n", .{});
                    return;
                }
                if (eql(u8, subnames, "y")) {
                    self.config.subnames = true;
                } else {
                    self.config.subnames = false;
                }

                std.debug.print("Does your launcher use cfg files? (y/n): ", .{});
                const cfg = try std.io.getStdIn().reader().readUntilDelimiterAlloc(self.allocator, '\n', 10000);
                defer self.allocator.free(cfg);
                if (cfg.len == 0) {
                    std.debug.print("[-] Invalid input\n", .{});
                    return;
                }
                if (eql(u8, cfg, "y")) {
                    self.config.cfg = true;
                } else {
                    self.config.cfg = false;
                }

                std.debug.print("[+] Setup complete", .{});
            },
        }
    }
};
