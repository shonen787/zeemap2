const std = @import("std");
pub const EnvConfig = struct {
    username: []const u8,
    password: []const u8,
    imap_server: []const u8,
    imap_port: u16,
    const Self = @This();

    pub fn readENV(allocator: std.mem.Allocator) !EnvConfig {
        const file = try std.fs.cwd().openFile(".env", .{});
        errdefer file.close();

        const filecontents = try file.reader().readAllAlloc(allocator, 4096);
        var parsed_username: ?[]const u8 = null;
        var parsed_password: ?[]const u8 = null;
        var parsed_imap_server: ?[]const u8 = null;
        var parsed_imap_port: ?u16 = null;

        errdefer {
            if (parsed_password) |s| allocator.free(s);
            if (parsed_username) |s| allocator.free(s);
            if (parsed_imap_server) |s| allocator.free(s);
        }

        var lines = std.mem.splitAny(u8, filecontents, "\n\r");
        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, " ");
            if (trimmed_line.len == 0) continue;

            var parts = std.mem.splitAny(u8, trimmed_line, "=");
            const key = parts.next();
            const value = parts.next();

            if (key != null and value != null) {
                const key_str = std.mem.trim(u8, key.?, " ");
                const value_str = std.mem.trimLeft(u8, std.mem.trimRight(u8, value.?, " "), " ");
                if (std.mem.eql(u8, key_str, "username")) {
                    parsed_username = try allocator.dupe(u8, value_str);
                }

                if (std.mem.eql(u8, key_str, "password")) {
                    parsed_password = try allocator.dupe(u8, value_str);
                }

                if (std.mem.eql(u8, key_str, "GMAIL_IMAP_SERVER")) {
                    parsed_imap_server = try allocator.dupe(u8, value_str);
                }

                if (std.mem.eql(u8, key_str, "GMAIL_IMAP_PORT")) {
                    const temp = try allocator.dupe(u8, value_str);
                    parsed_imap_port = try std.fmt.parseInt(u16, temp, 10);
                    allocator.free(temp);
                }
            } else {}
        }

        allocator.free(filecontents);

        if (parsed_password == null) {
            if (parsed_username) |p| allocator.free(p);
            if (parsed_imap_server) |p| allocator.free(p);

            return error.PasswordConfigNotFound;
        }
        if (parsed_username == null) {
            if (parsed_imap_server) |p| allocator.free(p);
            if (parsed_password) |p| allocator.free(p);
            return error.UsernameConfigNotFound;
        }

        if (parsed_imap_port == null) {
            if (parsed_username) |p| allocator.free(p);
            if (parsed_imap_server) |p| allocator.free(p);
            if (parsed_password) |p| allocator.free(p);
            return error.ImapPortconfigNotFound;
        }
        if (parsed_imap_server == null) {
            if (parsed_username) |p| allocator.free(p);
            if (parsed_password) |p| allocator.free(p);
            return error.ImapServerConfigNotFound;
        }

        return .{ .username = parsed_username.?, .password = parsed_password.?, .imap_server = parsed_imap_server.?, .imap_port = parsed_imap_port.? };
    }
};
