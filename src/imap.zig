const std = @import("std");
const net = std.net;
const base64 = std.base64;
const log = std.log;

pub const ImapError = error{
    ConnectionFaile,
    AuthenticationFailed,
    CommandFailed,
    UnexpectedResponse,
    BufferTooSmall,
    TooManyTags,
};

pub const ResponseStatus = enum {
    ok,
    no,
    bad,
    continuation,
    untragged,
};

pub const EmailMessage = struct {
    uid: u32,
    subject: []const u8,
    from: []const u8,
    to: []const u8,
    date: []const u8,
    body_text: []const u8,
    body_html: []const u8,
    headers: []const u8,

    pub fn deinit(self: *EmailMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.subject);
        allocator.free(self.from);
        allocator.free(self.to);
        allocator.free(self.date);
        allocator.free(self.body_html);
        allocator.free(self.body_text);
        allocator.free(self.headers);
    }
};

pub const SearchResult = struct {
    field: []const u8,
    context: []const u8,
    position: usize,
};

pub const SearchMatch = struct {
    case_sensitive: bool = false,
    whole_words_only: bool = false,
    max_results: u32 = 50,
    context_length: u32 = 100,
};

pub const ImapResposne = struct {
    tag: []const u8,
    status: ResponseStatus,
    message: []const u8,
    raw: []const u8,
};

pub const ImapConnection = struct {
    tls_client: std.crypto.tls.Client,
    tcp_socket: std.net.Stream,
    allocator: std.mem.Allocator,
    request_id: u16,

    const Self = @This();
    const BUFFER_SIZE = 4086;
    const MAX_REQUEST_ID = 999;

    pub fn init(allocator: std.mem.Allocator, server: []const u8, port: u16) !Self {
        const tcp_socket = try net.tcpConnectToHost(allocator, server, port);
        errdefer tcp_socket.close();

        var ca_bundle = std.crypto.Certificate.Bundle{};
        defer ca_bundle.deinit(allocator);
        try ca_bundle.rescan(allocator);

        const client = try std.crypto.tls.Client.init(tcp_socket, .{ .host = .{ .explicit = server }, .ca = .{ .bundle = ca_bundle } });

        log.info("Connection Successful", .{});
        return Self{
            .tls_client = client,
            .allocator = allocator,
            .tcp_socket = tcp_socket,
            .request_id = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tcp_socket.close();
        return;
    }

    fn read(self: *Self, buffer: []u8) !usize {
        return self.tls_client.read(self.tcp_socket, buffer);
    }
    fn write(self: *Self, data: []const u8) !usize {
        return try self.tls_client.write(self.tcp_socket, data);
    }

    fn getTag(self: *Self) ![]const u8 {
        if (self.request_id > MAX_REQUEST_ID) return ImapError.TooManyTags;
        return switch (self.request_id) {
            0...9 => try std.fmt.allocPrint(self.allocator, "A00{d}", .{self.request_ID}),
            10...99 => try std.fmt.allocPrint(self.allocator, "A0{d}", .{self.request_ID}),
            100...999 => try std.fmt.allocPrint(self.allocator, "A{d}", .{self.request_ID}),
            else => unreachable,
        };
    }

    fn incrementTag(self: *Self) void {
        self.request_id += 1;
    }
};
