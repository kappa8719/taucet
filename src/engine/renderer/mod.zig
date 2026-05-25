pub const handles = @import("handles.zig");

pub const MeshHandle = handles.MeshHandle;
pub const MaterialHandle = handles.MaterialHandle;

pub const Renderer = @import("renderer.zig").Renderer;
pub const FrameContext = @import("renderer.zig").FrameContext;
pub const DrawCommand = @import("renderer.zig").DrawCommand;
pub const CameraData = @import("renderer.zig").CameraData;
