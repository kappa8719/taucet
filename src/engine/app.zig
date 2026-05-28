const std = @import("std");
const zglfw = @import("zglfw");
const Renderer = @import("renderer/mod.zig").Renderer;

pub fn run(comptime Game: type, io: std.Io, allocator: std.mem.Allocator) !void {
    std.log.info("initializing engine", .{});

    comptime {
        if (!@hasDecl(Game, "init")) @compileError("Game must have init(Allocator, *Renderer) !Game");
        if (!@hasDecl(Game, "deinit")) @compileError("Game must have deinit(*Renderer)");
        if (!@hasDecl(Game, "update")) @compileError("Game must have update(f32) void");
        if (!@hasDecl(Game, "render")) @compileError("Game must have render(*FrameContext) void");
    }

    std.log.info("initializing glfw", .{});
    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(.client_api, .no_api);

    std.log.info("creating window", .{});
    const window = try zglfw.Window.create(1280, 720, "taucet", null, null);
    defer window.destroy();

    std.log.info("initializing renderer", .{});
    var renderer = try Renderer.init(allocator, window);
    defer renderer.deinit();

    std.log.info("initializing game", .{});
    var game = try Game.init(allocator, &renderer);
    defer game.deinit(&renderer);

    // Capture the starting monotonic timestamp using the provided io instance
    var last_time = std.Io.Clock.awake.now(io);

    std.log.info("starting", .{});
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        if (window.shouldClose()) break;

        // Calculate delta time
        const now = std.Io.Clock.awake.now(io);
        const elapsed = last_time.durationTo(now);
        last_time = now;

        const dt_sec: f32 = @floatFromInt(elapsed.nanoseconds);
        const dt = dt_sec / std.time.ns_per_s;

        game.update(dt);

        var frame = renderer.beginFrame();
        game.render(&frame);
        if (!renderer.endFrame()) break;
    }
}
