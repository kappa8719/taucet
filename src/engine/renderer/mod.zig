pub const handles = @import("handles.zig");

pub const MeshHandle = handles.MeshHandle;
pub const MaterialHandle = handles.MaterialHandle;

pub const renderer = @import("renderer.zig");
pub const Renderer = renderer.Renderer;
pub const FrameContext = renderer.FrameContext;
pub const DrawCommand = renderer.DrawCommand;
pub const CameraData = renderer.CameraData;
pub const Vertex = renderer.Vertex;
pub const MeshDesc = renderer.MeshDesc;
