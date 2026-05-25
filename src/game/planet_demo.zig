const std = @import("std");
const zm = @import("zmath");
const engine = @import("engine");

pub const PlanetDemo = struct {
    allocator: std.mem.Allocator,
    camera: engine.Camera,

    planet_center: engine.WorldPosition,
    planet_radius: f64,

    fake_mesh: engine.MeshHandle,
    fake_material: engine.MaterialHandle,

    pub fn init(allocator: std.mem.Allocator) !PlanetDemo {
        return .{
            .allocator = allocator,
            .camera = .{
                .world_origin = .{
                    .x = 0,
                    .y = 6_371_000.0 + 1_000.0,
                    .z = 0,
                },
            },
            .planet_center = .{ .x = 0, .y = 0, .z = 0 },
            .planet_radius = 6_371_000.0,

            // Placeholder handles until upload API exists.
            .fake_mesh = .{ .index = 0, .generation = 1 },
            .fake_material = .{ .index = 0, .generation = 1 },
        };
    }

    pub fn deinit(self: *PlanetDemo) void {
        _ = self;
    }

    pub fn update(self: *PlanetDemo, dt: f32) void {
        self.camera.yaw += dt * 0.25;

        // Later:
        // - integrate velocity in f64 world-space
        // - rebase camera.world_origin
        // - stream planet chunks around origin
    }

    pub fn render(self: *PlanetDemo, frame: *engine.FrameContext) void {
        const aspect: f32 = 1280.0 / 720.0;

        frame.setCamera(.{
            .view = self.camera.viewMatrix(),
            .projection = self.camera.projectionMatrix(aspect),
            .world_origin_x = self.camera.world_origin.x,
            .world_origin_y = self.camera.world_origin.y,
            .world_origin_z = self.camera.world_origin.z,
        });

        const local_planet_center = self.planet_center.sub(self.camera.world_origin);

        const scale = zm.scaling(
            @floatCast(self.planet_radius),
            @floatCast(self.planet_radius),
            @floatCast(self.planet_radius),
        );

        const translate = zm.translation(
            local_planet_center.x,
            local_planet_center.y,
            local_planet_center.z,
        );

        const model = zm.mul(scale, translate);

        frame.draw(.{
            .mesh = self.fake_mesh,
            .material = self.fake_material,
            .transform = model,
        });
    }
};
