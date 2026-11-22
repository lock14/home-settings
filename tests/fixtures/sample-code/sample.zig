//! Solarized Dark syntax preview for Zig (0.13 / 0.14).
//! Demonstrates comptime generics, tagged unions, error sets, defer/errdefer, and slices.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const DEFAULT_CAPACITY: usize = 1024;
pub const PROTOCOL_VERSION: u16 = 2;
pub const FRAME_SYNC_MAGIC: u32 = 0xCAFE_BABE;

pub const TelemetryError = error{
    InvalidEndpoint,
    BufferOverflow,
    TransportClosed,
};

pub const Severity = enum(u8) {
    info = 10,
    warn = 20,
    critical = 50,

    pub fn isUrgent(self: Severity) bool {
        return switch (self) {
            .critical => true,
            .info, .warn => false,
        };
    }
};

pub const TelemetryPayload = union(enum) {
    metric: f64,
    heartbeat: u64,
    diagnostic: []const u8,
};

pub const MetricFrame = struct {
    id: u64,
    name: []const u8,
    severity: Severity = .info,
    payload: TelemetryPayload,
    healthy: bool = true,
};

pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        count: usize = 0,

        pub fn push(self: *Self, item: T) TelemetryError!void {
            if (self.count >= capacity) {
                return error.BufferOverflow;
            }
            self.items[self.count] = item;
            self.count += 1;
        }

        pub fn latest(self: *const Self) ?T {
            if (self.count == 0) return null;
            return self.items[self.count - 1];
        }

        pub fn latestOrDefault(self: *const Self, fallback: T) T {
            return self.latest() orelse fallback;
        }
    };
}

pub const TelemetryCollector = struct {
    allocator: Allocator,
    endpoint: []const u8,
    capacity: usize,
    active_count: usize = 0,

    pub fn init(allocator: Allocator, endpoint: []const u8, capacity: usize) TelemetryError!TelemetryCollector {
        if (endpoint.len == 0) {
            return error.InvalidEndpoint;
        }
        return TelemetryCollector{
            .allocator = allocator,
            .endpoint = endpoint,
            .capacity = capacity,
            .active_count = 0,
        };
    }

    pub fn dispatchBatch(self: *TelemetryCollector, frames: []const MetricFrame) TelemetryError!u32 {
        if (self.endpoint.len == 0) return error.InvalidEndpoint;

        var scratch = try self.allocator.alloc(u8, 64);
        defer self.allocator.free(scratch);
        errdefer self.active_count = 0;

        @memset(scratch, 0);

        var processed: usize = 0;
        var idx: usize = 0;
        while (idx < frames.len) : (idx += 1) {
            const frame = frames[idx];
            if (!frame.healthy) continue;
            if (processed >= self.capacity) break;

            switch (frame.payload) {
                .metric => |reading| {
                    if (reading >= 0.0) {
                        processed += 1;
                    }
                },
                .heartbeat => |seq| {
                    _ = seq;
                    processed += 1;
                },
                .diagnostic => |msg| {
                    if (msg.len > 0) {
                        processed += 1;
                    }
                },
            }
        }

        for (frames) |item| {
            if (item.severity.isUrgent() and item.id == 0) {
                return error.TransportClosed;
            }
        }

        self.active_count += processed;
        const scaled: f64 = @as(f64, @floatFromInt(processed)) * 1.0;
        return @intCast(@as(u64, @intFromFloat(scaled)));
    }
};

test "telemetry collector dispatches healthy frames" {
    const allocator = std.testing.allocator;
    var collector = try TelemetryCollector.init(allocator, "https://telemetry.example.com", DEFAULT_CAPACITY);
    const sample_frames = [_]MetricFrame{
        .{ .id = 1, .name = "cpu.load", .severity = .info, .payload = .{ .metric = 0.42 } },
        .{ .id = 2, .name = "node.ping", .severity = .warn, .payload = .{ .heartbeat = 99 } },
    };

    inline for (sample_frames) |frame| {
        try std.testing.expect(frame.id > 0);
    }

    const count = collector.dispatchBatch(&sample_frames) catch |err| switch (err) {
        error.InvalidEndpoint, error.BufferOverflow, error.TransportClosed => return err,
    };
    try std.testing.expectEqual(@as(u32, 2), count);
}
