const std = @import("std");
const imap = @import("imap.zig");
const env = @import("env.zig").EnvConfig;
const log = std.log;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const environment_config = try env.readENV(allocator);
    defer {
        allocator.free(environment_config.username);
        allocator.free(environment_config.password);
        allocator.free(environment_config.imap_server);
    }
    log.info("Connection to {s}:{d}", .{ environment_config.imap_server, environment_config.imap_port });

    var connection = imap.ImapConnection.init(allocator, environment_config.imap_server, environment_config.imap_port) catch |err| {
        log.err("Imap Connection Initilization Erro: {any}", .{err});
        return;
    };
    defer connection.deinit();
}

fn handleImapError(err: anyerror, context: []const u8) void {
    log.err("{s}: {}\n", .{ context, err });
}
