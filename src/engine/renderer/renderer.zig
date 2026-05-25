const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zm = @import("zmath");
const wgpu = zgpu.wgpu;

const handles = @import("handles.zig");

pub const CameraData = struct {
    view: zm.Mat,
    projection: zm.Mat,
    world_origin_x: f64,
    world_origin_y: f64,
    world_origin_z: f64,
};

pub const DrawCommand = struct {
    mesh: handles.MeshHandle,
    material: handles.MaterialHandle,
    // Camera-relative transform.
    transform: zm.Mat,
};

pub const FrameContext = struct {
    renderer: *Renderer,

    pub fn setCamera(self: *FrameContext, camera: CameraData) void {
        self.renderer.camera = camera;
    }

    pub fn draw(self: *FrameContext, cmd: DrawCommand) void {
        self.renderer.draw_commands.append(self.renderer.allocator, cmd) catch unreachable;
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: *zglfw.Window,

    // Backend-owned. Do not expose outside renderer.
    gctx: ?*zgpu.GraphicsContext = null,

    camera: ?CameraData = null,
    draw_commands: std.ArrayListUnmanaged(DrawCommand) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        window: *zglfw.Window,
    ) !Renderer {
        const gctx = try zgpu.GraphicsContext.create(
            allocator,
            .{
                .window = window,
                .fn_getTime = @ptrCast(&zglfw.getTime),
                .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
                .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
                .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
                .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
                .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
                .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
                .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
            },
            .{},
        );

        return .{
            .allocator = allocator,
            .window = window,
            .gctx = gctx,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.draw_commands.deinit(self.allocator);

        if (self.gctx) |gctx| {
            gctx.destroy(self.allocator);
        }
    }

    pub fn beginFrame(self: *Renderer) FrameContext {
        self.draw_commands.clearRetainingCapacity();
        return .{ .renderer = self };
    }

    pub fn endFrame(self: *Renderer) void {
        const gctx = self.gctx.?;

        const back_buffer_view = gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};

            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };

            const pass = encoder.beginRenderPass(render_pass_info);
            pass.end();
            pass.release();
        }

        const commands = encoder.finish(null);
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
};

