const std = @import("std");

const engine = @import("engine");
const game = @import("game");

pub fn main(init: std.process.Init) !void {
    std.log.info("initializing taucet", .{});
    try engine.run(game.PlanetDemo, init.io, std.heap.page_allocator);
}
