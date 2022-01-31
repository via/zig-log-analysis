const std = @import("std");
const json = std.json;
const sqlite = @import("sqlite");

pub const log_level = std.log.Level.debug;
const Allocator = std.heap.c_allocator;

const LogPoint = struct { realtime: u64, rpm: u32, map: f32, ego: f32, ve: f32 };

const e = error{WhoaError};

fn get_config(db: *sqlite.Db, allocator: std.mem.Allocator) anyerror!json.ValueTree {
    _ = allocator;
    const query = "SELECT config from configs limit 1;";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const config = try stmt.one([32768:0]u8, .{}, .{});
    if (config) |c| {
        var parser = json.Parser.init(allocator, true);
        defer parser.deinit();
        const j = parser.parse(std.mem.sliceTo(&c, 0));
        return j;
    }
    return e.WhoaError;
}

const PointWindow = struct {
    const Self = @This();
    const Queue = std.TailQueue(LogPoint);
    const Alloc = std.heap.c_allocator;

    window: Queue = Queue{},
    averages: LogPoint = undefined,

    fn push(this: *Self, point: LogPoint) std.mem.Allocator.Error!void {
        var node = try std.mem.Allocator.create(Alloc, Queue.Node);
        node.data = point;
        this.window.append(node);

        var first = this.window.first.?;
        var last = this.window.last.?;
        if (last.data.realtime - first.data.realtime > 100000000) {
            this.window.remove(first);
            std.mem.Allocator.destroy(Alloc, first);
        }
    }

    fn deinit(this: *Self) void {
        while (this.window.popFirst()) |node| {
            std.mem.Allocator.destroy(Alloc, node);
        }
    }
};

pub fn main() anyerror!void {
    //    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "log.sql" },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .SingleThread,
    });

    var saved = try get_config(&db, Allocator);
    defer saved.deinit();

    var config = saved.root.Object.get("config") orelse @panic("no config in json");
    for (config.Object.keys()) |key| {
        std.log.info("toplevel key: {s}", .{key});
    }

    const query = "SELECT realtime_ns, rpm, \"sensor.map\", \"sensor.ego\", \"ve\" FROM points;";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    var window = PointWindow{};
    defer window.deinit();

    var count: u32 = 0;
    var iter = try stmt.iterator(LogPoint, .{});
    while (try iter.next(.{})) |row| {
        try window.push(row);
        count += 1;
    }
    std.log.info("Finished iterating", .{});
}
