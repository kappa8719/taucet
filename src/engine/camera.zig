const std = @import("std");
const zm = @import("zmath");
const world = @import("world.zig");

pub const Camera = struct {
    world_origin: world.WorldPosition,
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    fov_y: f32 = std.math.pi / 3.0,
    near: f32 = 0.1,
    far: f32 = 100_000.0,

    pub fn viewMatrix(self: Camera) zm.Mat {
        // Camera-relative world means camera is at local origin.
        const eye = zm.f32x4(0, 0, 0, 1);

        const cy = @cos(self.yaw);
        const sy = @sin(self.yaw);
        const cp = @cos(self.pitch);
        const sp = @sin(self.pitch);

        const forward = zm.f32x4(sy * cp, sp, -cy * cp, 0);
        const target = eye + forward;
        const up = zm.f32x4(0, 1, 0, 0);

        return zm.lookAtRh(eye, target, up);
    }

    pub fn projectionMatrix(self: Camera, aspect: f32) zm.Mat {
        return zm.perspectiveFovRh(self.fov_y, aspect, self.near, self.far);
    }
};
