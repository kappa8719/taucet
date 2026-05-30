const std = @import("std");
const zglfw = @import("zglfw");
const InputState = @import("input.zig").InputState;
const Renderer = @import("renderer/mod.zig").Renderer;

pub fn run(comptime Game: type, io: std.Io, allocator: std.mem.Allocator) !void {
    std.log.info("initializing engine", .{});

    comptime {
        if (!@hasDecl(Game, "init")) @compileError("Game must have init(Allocator, *Renderer) !Game");
        if (!@hasDecl(Game, "deinit")) @compileError("Game must have deinit(*Renderer)");
        if (!@hasDecl(Game, "update")) @compileError("Game must have update(f32, InputState) void");
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
    var last_cursor_pos = window.getCursorPos();
    var dragging = false;

    std.log.info("starting", .{});
    std.log.info("controls: WASD move, Space/C vertical, arrows or right-drag look, Shift fast, R reset, Esc quit", .{});
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        if (window.shouldClose()) break;

        // Calculate delta time
        const now = std.Io.Clock.awake.now(io);
        const elapsed = last_time.durationTo(now);
        last_time = now;

        const dt_sec: f32 = @floatFromInt(elapsed.nanoseconds);
        const dt = dt_sec / std.time.ns_per_s;

        const input = readInput(window, &last_cursor_pos, &dragging);
        if (input.quit) {
            window.setShouldClose(true);
            break;
        }

        game.update(dt, input.state);

        var frame = renderer.beginFrame();
        game.render(&frame);
        if (!renderer.endFrame()) break;
    }
}

const AppInput = struct {
    state: InputState,
    quit: bool,
};

fn readInput(window: *zglfw.Window, last_cursor_pos: *[2]f64, dragging: *bool) AppInput {
    var input: InputState = .{
        .move_forward = keyDown(window, .w),
        .move_backward = keyDown(window, .s),
        .move_left = keyDown(window, .a),
        .move_right = keyDown(window, .d),
        .move_up = keyDown(window, .space),
        .move_down = keyDown(window, .c),
        .look_left = keyDown(window, .left),
        .look_right = keyDown(window, .right),
        .look_up = keyDown(window, .up),
        .look_down = keyDown(window, .down),
        .fast = keyDown(window, .left_shift) or keyDown(window, .right_shift),
        .reset_camera = keyDown(window, .r),
    };

    const cursor_pos = window.getCursorPos();
    const right_drag = mouseDown(window, .right);
    if (right_drag and dragging.*) {
        input.look_delta_x = @floatCast(cursor_pos[0] - last_cursor_pos.*[0]);
        input.look_delta_y = @floatCast(cursor_pos[1] - last_cursor_pos.*[1]);
    }
    last_cursor_pos.* = cursor_pos;
    dragging.* = right_drag;

    return .{
        .state = input,
        .quit = keyDown(window, .escape),
    };
}

fn keyDown(window: *zglfw.Window, key: zglfw.Key) bool {
    return window.getKey(key) != .release;
}

fn mouseDown(window: *zglfw.Window, button: zglfw.MouseButton) bool {
    return window.getMouseButton(button) != .release;
}
