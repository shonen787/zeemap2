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
    untagged,
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

    fn readLine(self: *Self, buffer: []u8) ![]u8 {
        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const bytes_read = try self.read(buffer[pos .. pos + 1]);
            if (bytes_read == 0) break;
            if (buffer[pos] == '\n') {
                return buffer[0 .. pos + 1];
            }
            pos += 1;
        }
        return buffer[0..pos];
    }

    pub fn readResponse(self: *Self, buffer: []u8) ![]u8 {
        @memset(buffer, 0);
        const bytes_read = try self.read(buffer);
        return buffer[0..bytes_read];
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

    pub fn selectMailbox(self: *Self, mailbox: []const u8) !void {
        log.info("Selecting Mailbox: {s}", .{mailbox});
        const select_cmd = try std.fmt.allocPrint(self.allocator, "SELECT {s}", .{mailbox});
        defer self.allocator.free(select_cmd);

        const response = try self.executeCommand(select_cmd);
        if (response.status != .ok) {
            log.err("Failed to select mailbox {s}", .{mailbox});
            return ImapError.CommandFailed;
        }

        log.info("Successfully selected mailbox: {s}", .{mailbox});
    }

    fn parseResponse(response: []const u8) ImapResposne {
        if (std.mem.startsWith(u8, response, "+")) {
            return ImapResposne{ .tag = "", .status = .continuation, .message = response[1..], .raw = response };
        }

        var iter = std.mem.splitAny(u8, std.mem.trim(u8, response, " \r\n"), " ");
        const tag = iter.next() orelse "";
        const status_str = iter.next() orelse "";
        const message = iter.rest();
        var status = ResponseStatus.untagged;

        if (std.mem.eql(u8, status_str, "OK")) status = ResponseStatus.ok;
        if (std.mem.eql(u8, status_str, "NO")) status = ResponseStatus.no;
        if (std.mem.eql(u8, status_str, "BAD")) status = ResponseStatus.bad;

        return ImapResposne{
            .tag = tag,
            .status = status,
            .message = message,
            .raw = response,
        };
    }

    pub fn executeCommand(self: *Self, command: []const u8) !ImapResposne {
        var buffer: [BUFFER_SIZE]u8 = undefined;
        const tag = try self.getTag();
        defer self.allocator.free(tag);

        _ = try self.write(tag);
        _ = try self.write(" ");
        _ = try self.write(command);
        _ = try self.write("\r\n");

        log.info("Client: {s}-{s}", .{ tag, command });
        self.incrementTag();

        if (std.mem.startsWith(u8, command, "SEARCH")) {
            log.info("executeCommand detected SEARCH command, returning immediately", .{});
            return ImapResposne{
                .tag = tag,
                .status = .ok,
                .message = "SEACH initiated",
                .raw = "",
            };
        }

        while (true) {
            const raw_response = try self.readLine(&buffer);
            log.info("Server: {s}", .{raw_response});
            const response = parseResponse(raw_response);

            if (std.mem.eql(u8, response.tag, tag)) {
                return response;
            }

            if (response.status == .untagged) {
                continue;
            }
        }
    }
};
