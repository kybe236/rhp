const std = @import("std");
const builtin = @import("builtin");
const eql = std.mem.eql;
const plugin_l = @import("plugin");

const config_folder = "/.rhp";
const config_file = "config";
const config = std.log.scoped(.config);

/// A config struct that holds the configuration of the program
/// Intialize the struct via Config.init(allocator) and deinitialize it via Config.deinit()
/// Save the configuration to the config file via Config.save(allocator) and load it via Config.load(allocator)
/// Set a key to a value via Config.set(key, value, allocator) and get a value via Config.get(key)
///
/// Fields:
/// - mc_path: The path to the minecraft folder
/// - subnames: If the folder has subnames for instances
/// - cfg: If theres an cfg file for each instance
///
/// Save Location:
/// Windows: %APPDATA%/.rhp/config
/// Linux: $HOME/.rhp/config
/// MacOS: $HOME/.rhp/config
pub const Config = struct {
    /// The path to the minecraft folder
    /// Example:
    /// Winows:
    mc_path: std.ArrayList(u8),
    /// If the folder has subnames for instances
    /// Example:
    /// mc_path/instance_name/.minecraft
    subnames: bool,
    /// If theres an cfg file for each instance
    /// Example:
    /// mc_path/instance_name/instance.cfg
    /// or if subnames is disabled
    /// mc_path/instance.cfg
    cfg: bool,

    /// Initialize the struct with the allocator
    /// defer needs to bee called after your done using the struct
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
        // Get $HOME or %APPDATA% depending on the OS
        // Return if the OS is not supported
        var path = try GetAppdataPath(allocator);
        try path.appendSlice(config_folder);
        defer path.deinit();

        // Create the folder if it doesn't exist
        std.fs.makeDirAbsolute(path.items) catch |err| {
            if (err != std.posix.MakeDirError.PathAlreadyExists) {
                // Return if error creating folder
                config.err("Error creating config folder\n", .{});
                return err;
            }
        };
        // Open the folder with sub paths for the file
        const folder = std.fs.openDirAbsolute(path.items, .{ .access_sub_paths = true }) catch |err| { // Open the folder that already exists or got created above
            // Return if error opening folder
            config.err("Error opening config folder\n", .{});
            return err;
        };

        // Create the file with read permissions
        // Write permissions are not needed as we only read and write once
        var file = folder.createFile(config_file, .{}) catch |err| {
            if (err == std.fs.File.OpenError.PathAlreadyExists) {
                // Don't return if file already exists
                config.info("File already exists continuing\n", .{});
            }
            // Return if error creating file
            config.err("Error creating config file {s} in {s}\n", .{ config_file, path.items });
            return err;
        };
        // defer to close the file after done
        defer file.close();

        const write = file.writer(); // Get an writer to write to the file

        _ = try write.write("mc_path: ");
        _ = try write.write(self.mc_path.items);
        _ = try write.write("\n");
        _ = try write.write("subnames: ");
        _ = try write.write(if (self.subnames) "true" else "false");
        _ = try write.write("\n");
        _ = try write.write("cfg: ");
        _ = try write.write(if (self.cfg) "true" else "false");
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
        // Get $HOME or %APPDATA% depending on the OS
        var path = try GetAppdataPath(allocator);
        try path.appendSlice(config_folder);
        defer path.deinit();

        // Open the folder
        // Should not create the folder because it means it isn't configured
        var folder = std.fs.openDirAbsolute(path.items, .{}) catch |err| {
            const msg =
                \\Error opening config folder
                \\Please run with --config to configure
            ;
            // Print the error message and return the error
            config.err("{s}\n", .{msg});
            return err;
        };
        // Close the folder after done
        defer folder.close();
        config.info("Folder opened\n", .{});

        // Open the file should not create the file
        var file = folder.openFile(config_file, .{ .mode = .read_only }) catch |err| {
            const msg =
                \\Error opening config file
                \\Please run with --config to configure
            ;
            // Print the error message and return the error
            config.err("{s}\n", .{msg});
            return err;
        };
        // closing the file after done
        defer file.close();
        config.info("File openened\n", .{});

        // Read the file
        const data = try file.readToEndAlloc(allocator, 100000);
        defer allocator.free(data);

        // Get each line of the file
        var lines = std.mem.splitAny(u8, data, "\n");

        // Loop through each line
        while (lines.peek() != null) {
            const line = lines.next().?;

            // Split the line by spaces
            var parts = std.mem.splitAny(u8, line, " "); // Split the line by spaces

            // Get the key and value
            // Format: <key>: <value>
            const key = parts.next();
            const value = parts.next();

            // Check if the key or value is null
            if (key == null) {
                config.warn("Key is null\n", .{});
                continue;
            }
            if (value == null) {
                config.warn("Value is null\n", .{});
                continue;
            }

            // Check keys and set values accordingly
            if (eql(u8, key.?, "mc_path:")) {
                try self.mc_path.resize(0);
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
                // Print if its an invalid key
                config.warn("Unknown key: {s}\n", .{key.?});
            }
        }

        // Inform the user that the config was loaded
        config.info("Config loaded\n", .{});
    }

    /// Set the key to the value
    /// - key: The key to set
    /// - value: The value to set
    /// - allocator: The allocator to use
    ///
    /// Shorthands for mc_path:
    /// - Windows:
    ///    - PrismLauncher: %APPDATA%/PrismLauncher/instances
    ///    - Official: %APPDATA%/.minecraft
    /// - Linux:
    ///   - PrismLauncher: $HOME/.local/share/PrismLauncher/instances
    ///   - MultiMC: $HOME/.local/share/multimc/instances
    ///   - Official: $HOME/.minecraft
    /// - MacOS:
    ///   - PrismLauncher: $HOME/.local/share/PrismLauncher/instances
    ///   - MultiMC: $HOME/.local/share/multimc/instances
    ///   - Official: $HOME/.minecraft
    pub fn set(self: *Config, key: [:0]u8, value: [:0]u8, allocator: std.mem.Allocator) !void {
        // Check the key and set the value accordingly
        if (eql(u8, key, "mc_path")) {
            var lower_value = std.ArrayList(u8).init(allocator);
            defer lower_value.deinit();
            {
                const lower_name = try std.ascii.allocLowerString(allocator, value);
                defer allocator.free(lower_name);
                for (lower_name) |c| {
                    if (c == '\n' or c == '\r') {
                        continue;
                    }
                    try lower_value.append(c);
                }
            }
            if (eql(u8, lower_value.items, "prismlauncher")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/PrismLauncher/instances");
                        self.mc_path = env;
                        config.info("set mc_path to {s}\n", .{env.items});
                    },
                    .windows => {
                        try env.appendSlice("PrismLauncher/instances");
                        self.mc_path = env;
                        config.info("set mc_path to {s}\n", .{env.items});
                    },
                    else => {
                        config.err("OS not supported\n", .{});
                        return;
                    },
                }
            } else if (eql(u8, lower_value.items, "multimc")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.local/share/multimc/instances");
                        self.mc_path = env;
                        config.info("set mc_path to {s}\n", .{env.items});
                    },
                    .windows => {
                        config.err("MultiMC has no default path on Windows\n", .{});
                    },
                    else => {
                        config.err("OS not supported\n", .{});
                        return;
                    },
                }
            } else if (eql(u8, lower_value.items, "official")) {
                var env = try GetAppdataPath(allocator);
                switch (builtin.os.tag) {
                    .linux, .macos => {
                        try env.appendSlice("/.minecraft");
                        self.mc_path = env;
                        config.info("set mc_path to {s}\n", .{env.items});
                    },
                    .windows => {
                        try env.appendSlice("/.minecraft");
                        self.mc_path = env;
                        config.info("set mc_path to {s}\n", .{env.items});
                    },
                    else => {
                        config.err("OS not supported\n", .{});
                        return;
                    },
                }
            } else {
                try self.mc_path.resize(0);
                try self.mc_path.appendSlice(value);
                config.info("set mc_path to {s}\n", .{value});
            }
        } else if (eql(u8, key, "subnames")) {
            self.subnames = if (eql(u8, value, "true")) true else false;
            config.info("subnames set to {s}\n", .{value});
        } else if (eql(u8, key, "cfg")) {
            self.cfg = if (eql(u8, value, "true")) true else false;
            config.info("cfg set to {s}\n", .{value});
        } else {
            config.err("Unknown key: {s}\n", .{key});
        }
    }

    /// Get the value of the key
    /// - key: The key to get
    pub fn get(self: Config, key: []u8) []const u8 {
        if (std.mem.eql(u8, key, "mc_path")) {
            return self.mc_path.items;
        } else if (std.mem.eql(u8, key, "subnames")) {
            if (self.subnames) return "true" else return "false";
        } else if (std.mem.eql(u8, key, "cfg")) {
            if (self.cfg) return "true" else return "false";
        } else {
            return "Unknown key";
        }
    }
};

const ErrorSet = error{
    HomeNotFound,
    AppdataNotFound,
    OsNotSupported,
};

/// Get the path to the appdata folder
/// Windows: %APPDATA%
/// Linux: $HOME
/// MacOS: $HOME
///
/// Custom Errors:
/// - ErrorSet.HomeNotFound if $HOME is not defined
/// - ErrorSet.AppdataNotFound if %APPDATA% is not defined
/// - ErrorSet.OsNotSupported if the OS is not supported
pub fn GetAppdataPath(allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var env = try std.process.getEnvMap(allocator); // Get the environment variables
    defer env.deinit(); // Deinit the environment variables

    var path = std.ArrayList(u8).init(allocator); // Initialize the path

    switch (builtin.os.tag) {
        .linux, .macos => {
            const home = env.get("HOME"); // Get the home variable
            if (home == null) { // Check if the home variable is defined
                const msg =
                    \\Home not found
                    \\Please check if $HOME is defined as it should be
                ;
                config.err("{s}\n", .{msg});
                return ErrorSet.HomeNotFound;
            }
            try path.appendSlice(home.?);
        },
        .windows => {
            const appdata = env.get("APPDATA"); // Get the appdata variable
            if (appdata == null) { // Check if the appdata variable is defined
                const msg =
                    \\Appdata not found
                    \\Please check if %APPDATA% is defined as it should be
                ;
                config.err("{s}\n", .{msg});
                return ErrorSet.AppdataNotFound;
            }
            try path.appendSlice(appdata.?);
        },
        else => { // If the OS is not supported
            config.err("OS not supported\n", .{});
            return ErrorSet.OsNotSupported;
        },
    }

    return path;
}
