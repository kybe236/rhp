const std = @import("std");
const builtin = @import("builtin");
const eql = std.mem.eql;

const config_folder = "/.rhp";
const config_file = "config";

pub const Config = struct {
    /// The path to the minecraft folder
    mc_path: std.ArrayList(u8),
    /// If the folder has subnames for instances
    subnames: bool,
    /// If theres an cfg file for each instance
    cfg: bool,

    /// Initialize the struct with the allocator
    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .mc_path = std.ArrayList(u8).init(allocator),
            .subnames = false,
            .cfg = false,
        };
    }

    /// Cleans up the memory of the struct
    pub fn deinit(self: *Config) void {
        self.mc_path.deinit();
    }

    /// Save the configuration of the struct to the config file
    /// Windows: %APPDATA%/.rhp/config
    /// Linux: $HOME/.rhp/config
    /// MacOS: $HOME/.rhp/config
    ///
    /// Custom Errors:
    /// - ErrorSet.HomeNotFound if $HOME is not defined
    /// - ErrorSet.AppdataNotFound if %APPDATA% is not defined
    /// - ErrorSet.OsNotSupported if the OS is not supported
    pub fn save(self: *Config, allocator: std.mem.Allocator) !void {
        var path = try GetAppdataPath(allocator);
        try path.appendSlice(config_folder);
        defer path.deinit();

        std.fs.makeDirAbsolute(path.items) catch |err| { // Create the folder and handle errors
            if (err == std.posix.MakeDirError.PathAlreadyExists) {} else {
                // Return if error creating folder
                std.debug.print("[-] Error creating config folder\n", .{});
                return err;
            }
        };
        const folder = std.fs.openDirAbsolute(path.items, .{ .access_sub_paths = true }) catch { // Open the folder that already exists or got created above
            // Return if error opening folder
            std.debug.print("[-] Error opening config folder\n", .{});
            return;
        };

        var file = folder.createFile(config_file, .{ .read = true }) catch |err| { // Create the file with relative path
            if (err == std.fs.File.OpenError.PathAlreadyExists) {
                // Don't return if file already exists
                std.debug.print("[+] File already exists continuing\n", .{});
            }
            // Return if error creating file
            std.debug.print("[-] Error creating config file {s}{s}\n", .{ path.items, config_file });
            std.debug.print("[-] Posix path: {s}\n", .{try std.posix.toPosixPath(config_file)});
            return err;
        };
        defer file.close(); // Close the file after done

        const mc_path = self.mc_path.items; // Get the mc_path as a slice

        const subnames = if (self.subnames) "true" else "false"; // if its on its: "subnames: true" else: "subnames: false"
        const cfg = if (self.cfg) "true" else "false"; // if its on its: "cfg: true" else: "cfg: false"

        const write = file.writer(); // Get an writer to write to the file

        // maybe im gona find a cleaner way
        _ = try write.write("mc_path: ");
        _ = try write.write(mc_path);
        _ = try write.write("\n");
        _ = try write.write("subnames: ");
        _ = try write.write(subnames);
        _ = try write.write("\n");
        _ = try write.write("cfg: ");
        _ = try write.write(cfg);
    }

    /// Load the configuration from the config file
    /// Windows: %APPDATA%/.rhp/config
    /// Linux: $HOME/.rhp/config
    /// MacOS: $HOME/.rhp/config
    ///
    /// Custom Errors:
    /// - ErrorSet.HomeNotFound if $HOME is not defined
    /// - ErrorSet.AppdataNotFound if %APPDATA% is not defined
    /// - ErrorSet.OsNotSupported if the OS is not supported
    pub fn load(self: *Config, allocator: std.mem.Allocator) !void {
        var path = try GetAppdataPath(allocator);
        try path.appendSlice(config_folder);
        defer path.deinit();

        // Open the folder should not create the folder
        var folder = std.fs.openDirAbsolute(path.items, .{}) catch |err| {
            std.debug.print("[-] Error opening config folder\n", .{});
            std.debug.print("[-] Please run with --config to configure\n", .{});
            return err;
        };
        defer folder.close(); // Close the folder after done
        std.debug.print("[+] Folder opened\n", .{});

        // Open the file should not create the file
        var file = folder.openFile(config_file, .{ .mode = .read_only }) catch |err| {
            std.debug.print("[-] Error opening config file\n", .{});
            std.debug.print("[-] Please run with --config to configure\n", .{});
            return err;
        };
        defer file.close(); // Close the file after done
        std.debug.print("[+] File openened\n", .{});

        const data = try file.readToEndAlloc(allocator, 100000);
        defer allocator.free(data);

        var lines = std.mem.splitAny(u8, data, "\n");

        while (lines.peek() != null) {
            const line = lines.next().?; // Get the line
            var parts = std.mem.splitAny(u8, line, " "); // Split the line by spaces

            const key = parts.next(); // Get the key
            const value = parts.next(); // Get the value

            if (key == null) {
                continue;
            }
            if (value == null) {
                continue;
            }

            if (eql(u8, key.?, "mc_path:")) {
                self.mc_path.items = "";
                try self.mc_path.appendSlice(value.?);
            } else if (eql(u8, key.?, "subnames:")) {
                if (eql(u8, value.?, "true")) {
                    self.subnames = true;
                } else {
                    self.subnames = false;
                }
            } else if (eql(u8, key.?, "cfg:")) {
                if (eql(u8, value.?, "true")) {
                    self.cfg = true;
                } else {
                    self.cfg = false;
                }
            } else {
                std.debug.print("[-] Unknown key: {s}\n", .{key.?});
            }
        }

        std.debug.print("[+] Config loaded\n", .{});
    }

    /// Set the key to the value
    /// - key: The key to set
    /// - value: The value to set
    pub fn set(self: *Config, key: [:0]u8, value: [:0]u8, allocator: std.mem.Allocator) !void {
        if (eql(u8, key, "mc_path")) {
            if (eql(u8, value, "prismlauncher")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/PrismLauncher/instances");
                        self.mc_path = env;
                    },
                    .windows => {
                        try env.appendSlice("PrismLauncher/instances");
                        self.mc_path = env;
                    },
                    else => {
                        std.debug.print("OS not supported\n", .{});
                        return;
                    },
                }
            } else if (eql(u8, value, "multimc")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/multimc/instances");
                    },
                    .windows => {
                        std.debug.print("[-] MultiMC has no default path on Windows\n", .{});
                    },
                    else => {
                        std.debug.print("OS not supported\n", .{});
                        return;
                    },
                }
            } else if (eql(u8, value, "official")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.minecraft");
                        self.mc_path = env;
                    },
                    .windows => {
                        try env.appendSlice("/.minecraft");
                        self.mc_path = env;
                    },
                    else => {
                        std.debug.print("OS not supported\n", .{});
                        return;
                    },
                }
            } else {
                self.mc_path.items = "";
                try self.mc_path.appendSlice(value);
            }
            std.debug.print("[+] mc_path set to {s}\n", .{value});
        } else if (eql(u8, key, "subnames")) {
            if (eql(u8, value, "true")) {
                self.subnames = true;
                std.debug.print("[+] subnames set to true\n", .{});
            } else {
                self.subnames = false;
                std.debug.print("[+] subnames set to false\n", .{});
            }
        } else if (eql(u8, key, "cfg")) {
            if (eql(u8, value, "true")) {
                self.cfg = true;
                std.debug.print("[+] cfg set to true\n", .{});
            } else {
                self.cfg = false;
                std.debug.print("[+] cfg set to false\n", .{});
            }
        } else {
            std.debug.print("[-] Unknown key: {s}\n", .{key});
        }
    }

    /// Get the value of the key
    /// - key: The key to get
    pub fn get(self: Config, key: []u8) []const u8 {
        if (std.mem.eql(u8, key, "mc_path")) {
            return self.mc_path.items;
        } else if (std.mem.eql(u8, key, "subnames")) {
            if (self.subnames) {
                return "true"[0..];
            } else {
                return "false"[0..];
            }
        } else if (std.mem.eql(u8, key, "cfg")) {
            if (self.cfg) {
                return "true"[0..];
            } else {
                return "false"[0..];
            }
        } else {
            return "Unknown key"[0..];
        }
    }
};

const ErrorSet = error{
    HomeNotFound,
    AppdataNotFound,
    OsNotSupported,
};

pub fn GetAppdataPath(allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var env = try std.process.getEnvMap(allocator); // Get the environment variables
    defer env.deinit(); // Deinit the environment variables

    var path = std.ArrayList(u8).init(allocator); // Initialize the path

    switch (builtin.os.tag) {
        .linux, .macos => {
            const home = env.get("HOME"); // Get the home variable
            if (home == null) { // Check if the home variable is defined
                std.debug.print("Home not found\n", .{});
                std.debug.print("Please check if $HOME is defined as it should be\n", .{});
                return ErrorSet.HomeNotFound;
            }
            try path.appendSlice(home.?);
        },
        .windows => {
            const appdata = env.get("APPDATA"); // Get the appdata variable
            if (appdata == null) { // Check if the appdata variable is defined
                std.debug.print("Appdata not found\n", .{});
                std.debug.print("Please check if %APPDATA% is defined as it should be\n", .{});
                return ErrorSet.AppdataNotFound;
            }
            try path.appendSlice(appdata.?);
        },
        else => { // If the OS is not supported
            std.debug.print("OS not supported\n", .{});
            return ErrorSet.OsNotSupported;
        },
    }

    return path;
}
