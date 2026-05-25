const zm = @import("zmath");

pub const WorldPosition = struct {
    // Large-scale planet-space position.
    // Keep this in f64 on CPU.
    x: f64,
    y: f64,
    z: f64,

    pub fn sub(self: WorldPosition, origin: WorldPosition) RelativePosition {
        return .{
            .x = @floatCast(self.x - origin.x),
            .y = @floatCast(self.y - origin.y),
            .z = @floatCast(self.z - origin.z),
        };
    }
};

pub const RelativePosition = struct {
    // GPU/camera-relative position.
    // Safe to use as f32 near camera.
    x: f32,
    y: f32,
    z: f32,

    pub fn vec4(self: RelativePosition, w: f32) zm.F32x4 {
        return zm.f32x4(self.x, self.y, self.z, w);
    }
};
