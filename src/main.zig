const std = @import("std");
const json = std.json;
const sqlite = @import("sqlite");


pub const log_level = std.log.Level.debug;

const LogPoint = struct { cputime: u64, rpm: u32, map: f32, ego: f32, ve: f32 };

const e = error {
  WhoaError
};

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



pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "log.sql" },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .SingleThread,
    });

    var saved = try get_config(&db, gpa.allocator());
    defer saved.deinit();

    var config = saved.root.Object.get("config") orelse @panic("no config in json");
    for (config.Object.keys()) |key| {
      std.log.info("toplevel key: {s}", .{key});
    }

    const query = "SELECT cputime, rpm, \"sensor.map\", \"sensor.ego\", \"ve\" FROM points;";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    var count: u32 = 0;
    var iter = try stmt.iterator(LogPoint, .{});
    while (try iter.next(.{})) |row| {
        if (count < 50) {
            std.log.info("Time: {}, rpm: {}", .{ row.cputime, row.rpm });
        }
        count += 1;
    }
    std.log.info("Finished iterating", .{});
}
