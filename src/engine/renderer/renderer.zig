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

const Vertex = extern struct {
    position: [3]f32,
};

const GpuMesh = struct {
    vertex_buffer: zgpu.BufferHandle,
    vertex_count: u32,
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: *zglfw.Window,

    // Backend-owned. Do not expose outside renderer.
    gctx: ?*zgpu.GraphicsContext = null,

    camera: ?CameraData = null,
    draw_commands: std.ArrayListUnmanaged(DrawCommand) = .empty,
    debug_pipeline: zgpu.RenderPipelineHandle,
    debug_mesh: GpuMesh,

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

        const shader_src =
            \\@vertex
            \\fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
            \\    var pos = array<vec2f, 3>(
            \\        vec2f(0.0, 0.5),
            \\        vec2f(-0.5, -0.5),
            \\        vec2f(0.5, -0.5),
            \\    );
            \\    return vec4f(pos[i], 0.0, 1.0);
            \\}
            \\
            \\@fragment
            \\fn fs_main() -> @location(0) vec4f {
            \\    return vec4f(1.0, 0.3, 0.7, 1.0);
            \\}
        ;

        const shader = zgpu.createWgslShaderModule(gctx.device, shader_src, "debug_triangle");
        defer shader.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const pipeline_desc = wgpu.RenderPipelineDescriptor{
            .vertex = .{
                .module = shader,
                .entry_point = "vs_main",
                .buffer_count = 0,
                .buffers = null,
            },
            .primitive = .{
                .topology = .triangle_list,
                .front_face = .ccw,
                .cull_mode = .none,
            },
            .fragment = &wgpu.FragmentState{
                .module = shader,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };

        const pipeline_layout = gctx.createPipelineLayout(&.{});
        defer gctx.releaseResource(pipeline_layout);

        const debug_pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_desc);

        return .{
            .allocator = allocator,
            .window = window,
            .gctx = gctx,
            .debug_pipeline = debug_pipeline,
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
                .clear_value = .{
                    .r = 0.5,
                    .g = 0.08,
                    .b = 0.14,
                    .a = 1.0,
                },
            }};

            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };

            const pass = encoder.beginRenderPass(render_pass_info);

            if (gctx.lookupResource(self.debug_pipeline)) |pipeline| {
                pass.setPipeline(pipeline);
                pass.draw(3, 1, 0, 0);
            }

            pass.end();
            pass.release();
        }

        const commands = encoder.finish(null);
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
};
