const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zm = @import("zmath");
const wgpu = zgpu.wgpu;

const handles = @import("handles.zig");

pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    color: [4]f32,
};

pub const MeshDesc = struct {
    vertices: []const Vertex,
    indices: []const u32,
};

pub const CameraData = struct {
    view: zm.Mat,
    projection: zm.Mat,
    world_origin_x: f64,
    world_origin_y: f64,
    world_origin_z: f64,
};

pub const DrawCommand = struct {
    mesh: handles.MeshHandle,
    material: handles.MaterialHandle = .{ .index = 0, .generation = 1 },
    // Camera-relative transform.
    transform: zm.Mat,
};

pub const FrameContext = struct {
    renderer: *Renderer,

    pub fn setCamera(self: *FrameContext, camera: CameraData) void {
        self.renderer.camera = camera;
    }

    pub fn aspectRatio(self: *FrameContext) f32 {
        return self.renderer.aspectRatio();
    }

    pub fn draw(self: *FrameContext, cmd: DrawCommand) void {
        self.renderer.draw_commands.append(self.renderer.allocator, cmd) catch unreachable;
    }
};

const depth_format = wgpu.TextureFormat.depth24_plus;

const DrawUniforms = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    light_direction: [4]f32,
};

const GpuMesh = struct {
    generation: u32,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    vertex_count: u32,
    index_count: u32,

    fn deinit(self: GpuMesh, gctx: *zgpu.GraphicsContext) void {
        gctx.releaseResource(self.index_buffer);
        gctx.releaseResource(self.vertex_buffer);
    }
};

const DepthTarget = struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
    width: u32,
    height: u32,

    fn deinit(self: DepthTarget, gctx: *zgpu.GraphicsContext) void {
        gctx.releaseResource(self.view);
        gctx.releaseResource(self.texture);
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: *zglfw.Window,

    // Backend-owned. Do not expose outside renderer. This is destroyed after all renderer GPU resources.
    gctx: ?*zgpu.GraphicsContext = null,

    camera: ?CameraData = null,
    draw_commands: std.ArrayListUnmanaged(DrawCommand) = .empty,
    meshes: std.ArrayListUnmanaged(?GpuMesh) = .empty,
    mesh_generations: std.ArrayListUnmanaged(u32) = .empty,

    mesh_bind_group_layout: zgpu.BindGroupLayoutHandle,
    mesh_pipeline: zgpu.RenderPipelineHandle,
    depth: ?DepthTarget = null,

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
        errdefer gctx.destroy(allocator);

        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(DrawUniforms)),
        };
        const mesh_bind_group_layout = gctx.createBindGroupLayout(&bind_group_layout_entries);
        errdefer gctx.releaseResource(mesh_bind_group_layout);

        const pipeline_layout = gctx.createPipelineLayout(&.{mesh_bind_group_layout});
        defer gctx.releaseResource(pipeline_layout);

        const shader = zgpu.createWgslShaderModule(gctx.device, mesh_shader_wgsl, "mesh_shader");
        defer shader.release();

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "color"), .shader_location = 2 },
        };
        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};
        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};
        const depth_state = wgpu.DepthStencilState{
            .format = depth_format,
            .depth_write_enabled = true,
            .depth_compare = .less,
        };
        const pipeline_desc = wgpu.RenderPipelineDescriptor{
            .vertex = .{
                .module = shader,
                .entry_point = "vs_main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = .{
                .topology = .triangle_list,
                .front_face = .ccw,
                .cull_mode = .back,
            },
            .depth_stencil = &depth_state,
            .fragment = &wgpu.FragmentState{
                .module = shader,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };
        const mesh_pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_desc);
        errdefer gctx.releaseResource(mesh_pipeline);

        var renderer = Renderer{
            .allocator = allocator,
            .window = window,
            .gctx = gctx,
            .mesh_bind_group_layout = mesh_bind_group_layout,
            .mesh_pipeline = mesh_pipeline,
        };
        errdefer renderer.deinit();

        try renderer.recreateDepthTarget();
        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        self.draw_commands.deinit(self.allocator);

        if (self.gctx) |gctx| {
            for (self.meshes.items) |mesh| {
                if (mesh) |live_mesh| live_mesh.deinit(gctx);
            }
            self.meshes.deinit(self.allocator);
            self.mesh_generations.deinit(self.allocator);

            if (self.depth) |depth| depth.deinit(gctx);
            self.depth = null;

            gctx.releaseResource(self.mesh_pipeline);
            gctx.releaseResource(self.mesh_bind_group_layout);
            gctx.destroy(self.allocator);
            self.gctx = null;
        } else {
            self.meshes.deinit(self.allocator);
            self.mesh_generations.deinit(self.allocator);
        }
    }

    pub fn aspectRatio(self: *Renderer) f32 {
        const size = self.framebufferSize();
        if (size[0] == 0 or size[1] == 0) return 1.0;
        return @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
    }

    pub fn createMesh(self: *Renderer, desc: MeshDesc) !handles.MeshHandle {
        std.debug.assert(desc.vertices.len > 0);
        std.debug.assert(desc.indices.len > 0);

        const gctx = self.gctx.?;
        const vertex_buffer = gctx.createBuffer(.{
            .label = "mesh_vertex_buffer",
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = desc.vertices.len * @sizeOf(Vertex),
        });
        errdefer gctx.releaseResource(vertex_buffer);

        const index_buffer = gctx.createBuffer(.{
            .label = "mesh_index_buffer",
            .usage = .{ .index = true, .copy_dst = true },
            .size = desc.indices.len * @sizeOf(u32),
        });
        errdefer gctx.releaseResource(index_buffer);

        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, desc.vertices);
        gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u32, desc.indices);

        for (self.meshes.items, 0..) |slot, i| {
            if (slot == null) {
                const generation = self.mesh_generations.items[i];
                self.meshes.items[i] = .{
                    .generation = generation,
                    .vertex_buffer = vertex_buffer,
                    .index_buffer = index_buffer,
                    .vertex_count = @intCast(desc.vertices.len),
                    .index_count = @intCast(desc.indices.len),
                };
                return .{ .index = @intCast(i), .generation = generation };
            }
        }

        try self.mesh_generations.append(self.allocator, 1);
        errdefer _ = self.mesh_generations.pop();

        const mesh = GpuMesh{
            .generation = 1,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = @intCast(desc.vertices.len),
            .index_count = @intCast(desc.indices.len),
        };

        try self.meshes.append(self.allocator, mesh);
        return .{ .index = @intCast(self.meshes.items.len - 1), .generation = mesh.generation };
    }

    pub fn destroyMesh(self: *Renderer, handle: handles.MeshHandle) void {
        if (self.gctx == null) return;
        const gctx = self.gctx.?;
        if (handle.index >= self.meshes.items.len) return;
        const slot = &self.meshes.items[handle.index];
        if (slot.*) |mesh| {
            if (mesh.generation != handle.generation) return;
            mesh.deinit(gctx);
            slot.* = null;
            self.mesh_generations.items[handle.index] = nextMeshGeneration(mesh.generation);
        }
    }

    pub fn beginFrame(self: *Renderer) FrameContext {
        self.draw_commands.clearRetainingCapacity();
        self.camera = null;
        return .{ .renderer = self };
    }

    pub fn endFrame(self: *Renderer) bool {
        const gctx = self.gctx orelse return false;
        const framebuffer_size = self.framebufferSize();
        if (framebuffer_size[0] == 0 or framebuffer_size[1] == 0) return true;
        self.ensureDepthTarget(framebuffer_size) catch |err| {
            std.log.err("failed to recreate depth target: {}", .{err});
            return false;
        };

        const back_buffer_view = gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const depth_view = gctx.lookupResource(self.depth.?.view).?;
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .r = 0.46, .g = 0.63, .b = 0.82, .a = 1.0 },
            }};
            const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = &depth_attachment,
            };

            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            if (gctx.lookupResource(self.mesh_pipeline)) |pipeline| {
                pass.setPipeline(pipeline);
                for (self.draw_commands.items) |cmd| {
                    self.drawMesh(pass, cmd);
                }
            }
        }

        const commands = encoder.finish(null);
        defer commands.release();

        gctx.submit(&.{commands});
        if (gctx.present() == .swap_chain_resized) {
            self.recreateDepthTarget() catch |err| {
                std.log.err("failed to recreate depth target after resize: {}", .{err});
                return false;
            };
        }
        return true;
    }

    fn drawMesh(self: *Renderer, pass: wgpu.RenderPassEncoder, cmd: DrawCommand) void {
        const gctx = self.gctx.?;
        const mesh = self.resolveMesh(cmd.mesh) orelse return;
        const camera = self.camera orelse return;

        const view_projection = zm.mul(camera.view, camera.projection);
        const mvp = zm.mul(cmd.transform, view_projection);
        const uniform_allocation = gctx.uniformsAllocate(DrawUniforms, 1);
        if (uniform_allocation.slice.len == 0) return;

        zm.storeMat(uniform_allocation.slice[0].mvp[0..], mvp);
        zm.storeMat(uniform_allocation.slice[0].model[0..], cmd.transform);
        uniform_allocation.slice[0].light_direction = .{ -0.45, -0.75, -0.35, 0.0 };

        const bind_group = gctx.createBindGroup(self.mesh_bind_group_layout, &.{.{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = uniform_allocation.offset,
            .size = @sizeOf(DrawUniforms),
        }});
        defer gctx.releaseResource(bind_group);

        pass.setBindGroup(0, gctx.lookupResource(bind_group).?, null);
        pass.setVertexBuffer(0, gctx.lookupResource(mesh.vertex_buffer).?, 0, mesh.vertex_count * @sizeOf(Vertex));
        pass.setIndexBuffer(gctx.lookupResource(mesh.index_buffer).?, .uint32, 0, mesh.index_count * @sizeOf(u32));
        pass.drawIndexed(mesh.index_count, 1, 0, 0, 0);
    }

    fn resolveMesh(self: *Renderer, handle: handles.MeshHandle) ?GpuMesh {
        if (handle.index >= self.meshes.items.len) return null;
        const mesh = self.meshes.items[handle.index] orelse return null;
        if (mesh.generation != handle.generation) return null;
        return mesh;
    }

    fn recreateDepthTarget(self: *Renderer) !void {
        const gctx = self.gctx.?;
        const framebuffer_size = self.framebufferSize();
        if (framebuffer_size[0] == 0 or framebuffer_size[1] == 0) return;

        if (self.depth) |depth| depth.deinit(gctx);
        self.depth = null;

        const texture = gctx.createTexture(.{
            .label = "depth_texture",
            .usage = .{ .render_attachment = true },
            .size = .{ .width = framebuffer_size[0], .height = framebuffer_size[1] },
            .format = depth_format,
        });
        errdefer gctx.releaseResource(texture);

        const view = gctx.createTextureView(texture, .{});
        errdefer gctx.releaseResource(view);

        self.depth = .{
            .texture = texture,
            .view = view,
            .width = framebuffer_size[0],
            .height = framebuffer_size[1],
        };
    }

    fn ensureDepthTarget(self: *Renderer, framebuffer_size: [2]u32) !void {
        if (self.depth) |depth| {
            if (depth.width == framebuffer_size[0] and depth.height == framebuffer_size[1]) return;
        }
        try self.recreateDepthTarget();
    }

    fn framebufferSize(self: *Renderer) [2]u32 {
        const size = self.window.getFramebufferSize();
        return .{
            if (size[0] > 0) @intCast(size[0]) else 0,
            if (size[1] > 0) @intCast(size[1]) else 0,
        };
    }
};

fn nextMeshGeneration(generation: u32) u32 {
    const next = generation +% 1;
    return if (next == 0) 1 else next;
}

const mesh_shader_wgsl =
    \\struct DrawUniforms {
    \\    mvp: mat4x4<f32>,
    \\    model: mat4x4<f32>,
    \\    light_direction: vec4<f32>,
    \\};
    \\
    \\@group(0) @binding(0)
    \\var<uniform> draw: DrawUniforms;
    \\
    \\struct VertexIn {
    \\    @location(0) position: vec3<f32>,
    \\    @location(1) normal: vec3<f32>,
    \\    @location(2) color: vec4<f32>,
    \\};
    \\
    \\struct VertexOut {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) normal: vec3<f32>,
    \\    @location(1) color: vec4<f32>,
    \\};
    \\
    \\@vertex
    \\fn vs_main(input: VertexIn) -> VertexOut {
    \\    var out: VertexOut;
    \\    out.position = vec4<f32>(input.position, 1.0) * draw.mvp;
    \\    out.normal = normalize((vec4<f32>(input.normal, 0.0) * draw.model).xyz);
    \\    out.color = input.color;
    \\    return out;
    \\}
    \\
    \\@fragment
    \\fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    \\    let normal = normalize(input.normal);
    \\    let light = normalize(-draw.light_direction.xyz);
    \\    let diffuse = max(dot(normal, light), 0.0);
    \\    let shade = 0.35 + diffuse * 0.65;
    \\    return vec4<f32>(input.color.rgb * shade, input.color.a);
    \\}
;
