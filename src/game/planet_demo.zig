const std = @import("std");
const zm = @import("zmath");
const engine = @import("engine");

pub const PlanetDemo = struct {
    allocator: std.mem.Allocator,
    camera: engine.Camera,

    planet_center: engine.WorldPosition,
    planet_radius: f64,
    orbit_angle: f32 = 0.0,
    orbit_distance: f64 = 7.0,
    orbit_height: f64 = 2.0,

    planet_mesh: engine.MeshHandle,

    pub fn init(allocator: std.mem.Allocator, renderer: *engine.Renderer) !PlanetDemo {
        const planet_mesh = try createLowPolyPlanetMesh(allocator, renderer);

        return .{
            .allocator = allocator,
            .camera = .{
                .world_origin = .{ .x = 0, .y = 2.0, .z = 7.0 },
                .near = 0.05,
                .far = 100.0,
            },
            .planet_center = .{ .x = 0, .y = 0, .z = 0 },
            .planet_radius = 2.0,
            .planet_mesh = planet_mesh,
        };
    }

    pub fn deinit(self: *PlanetDemo, renderer: *engine.Renderer) void {
        renderer.destroyMesh(self.planet_mesh);
    }

    pub fn update(self: *PlanetDemo, dt: f32) void {
        self.orbit_angle += dt * 0.35;

        self.camera.world_origin = .{
            .x = @as(f64, @floatCast(@sin(self.orbit_angle))) * self.orbit_distance,
            .y = self.orbit_height,
            .z = @as(f64, @floatCast(@cos(self.orbit_angle))) * self.orbit_distance,
        };

        const to_planet = self.planet_center.sub(self.camera.world_origin);
        const dx = to_planet.x;
        const dy = to_planet.y;
        const dz = to_planet.z;
        const len = @sqrt(dx * dx + dy * dy + dz * dz);
        self.camera.yaw = std.math.atan2(dx, -dz);
        self.camera.pitch = std.math.asin(dy / len);
    }

    pub fn render(self: *PlanetDemo, frame: *engine.FrameContext) void {
        frame.setCamera(.{
            .view = self.camera.viewMatrix(),
            .projection = self.camera.projectionMatrix(frame.aspectRatio()),
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
            .mesh = self.planet_mesh,
            .transform = model,
        });
    }
};

fn createLowPolyPlanetMesh(allocator: std.mem.Allocator, renderer: *engine.Renderer) !engine.MeshHandle {
    var vertices: std.ArrayListUnmanaged(engine.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayListUnmanaged(u32) = .empty;
    defer indices.deinit(allocator);

    const rings = 8;
    const segments = 16;
    var lat: usize = 0;
    while (lat < rings) : (lat += 1) {
        const v0 = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(rings));
        const v1 = @as(f32, @floatFromInt(lat + 1)) / @as(f32, @floatFromInt(rings));
        const theta0 = -std.math.pi / 2.0 + v0 * std.math.pi;
        const theta1 = -std.math.pi / 2.0 + v1 * std.math.pi;

        var lon: usize = 0;
        while (lon < segments) : (lon += 1) {
            const lon0 = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(segments));
            const lon1 = @as(f32, @floatFromInt(lon + 1)) / @as(f32, @floatFromInt(segments));
            const phi0 = lon0 * std.math.tau;
            const phi1 = lon1 * std.math.tau;

            const p00 = spherePoint(theta0, phi0);
            const p01 = spherePoint(theta0, phi1);
            const p10 = spherePoint(theta1, phi0);
            const p11 = spherePoint(theta1, phi1);

            if (lat != 0) try appendTriangle(allocator, &vertices, &indices, p00, p01, p10);
            if (lat + 1 != rings) try appendTriangle(allocator, &vertices, &indices, p01, p11, p10);
        }
    }

    return renderer.createMesh(.{ .vertices = vertices.items, .indices = indices.items });
}

fn spherePoint(theta: f32, phi: f32) [3]f32 {
    const c = @cos(theta);
    return .{ c * @sin(phi), @sin(theta), c * @cos(phi) };
}

fn appendTriangle(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayListUnmanaged(engine.Vertex),
    indices: *std.ArrayListUnmanaged(u32),
    a: [3]f32,
    b: [3]f32,
    c: [3]f32,
) !void {
    const normal = faceNormal(a, b, c);
    const base: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{ .position = a, .normal = normal, .color = colorForPoint(a) });
    try vertices.append(allocator, .{ .position = b, .normal = normal, .color = colorForPoint(b) });
    try vertices.append(allocator, .{ .position = c, .normal = normal, .color = colorForPoint(c) });
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2 });
}

fn faceNormal(a: [3]f32, b: [3]f32, c: [3]f32) [3]f32 {
    const ab = .{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
    const ac = .{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
    const n = .{
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    };
    const len = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    return .{ n[0] / len, n[1] / len, n[2] / len };
}

fn colorForPoint(p: [3]f32) [4]f32 {
    if (p[1] > 0.72) return .{ 0.92, 0.94, 0.87, 1.0 };
    if (p[1] < -0.62) return .{ 0.20, 0.35, 0.24, 1.0 };

    const ridge = @sin(p[0] * 8.0 + p[2] * 5.0) + @cos(p[1] * 11.0 + p[0] * 3.0);
    if (ridge > 0.72) return .{ 0.63, 0.56, 0.42, 1.0 };
    if (ridge < -0.55) return .{ 0.13, 0.34, 0.52, 1.0 };
    return .{ 0.26, 0.58, 0.31, 1.0 };
}
