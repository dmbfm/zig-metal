//  Copyright 2022 Apple Inc.
//  Copyright 2023 Daniel Fortes.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

const std = @import("std");
const mtl = @import("zig-metal");
const appkit = mtl.extras.appkit;

const NSApplication = appkit.NSApplication;
const NSWindow = appkit.NSWindow;
const MTKView = mtl.extras.metalkit.MTKView;

const float2 = @Vector(2, f32);
const float3 = @Vector(3, f32);
const float4 = @Vector(4, f32);

const float4x4 = extern struct {
    columns: [4]float4,
};

const Math = struct {
    fn deg2rad(deg: f32) f32 {
        return deg * std.math.pi / 180.0;
    }

    fn add(a: float3, b: float3) float3 {
        return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
    }

    fn matrix_mul(a: float4x4, b: float4x4) float4x4 {
        var result: float4x4 = make_identity();

        for (0..4) |i| {
            for (0..4) |j| {
                result.columns[j][i] = 0;
                for (0..4) |k| {
                    result.columns[j][i] += a.columns[k][i] * b.columns[j][k];
                }
            }
        }

        return result;
    }

    fn matrix_from_rows(r1: float4, r2: float4, r3: float4, r4: float4) float4x4 {
        return .{ .columns = .{
            .{ r1[0], r2[0], r3[0], r4[0] },
            .{ r1[1], r2[1], r3[1], r4[1] },
            .{ r1[2], r2[2], r3[2], r4[2] },
            .{ r1[3], r2[3], r3[3], r4[3] },
        } };
    }

    fn make_identity() float4x4 {
        return .{ .columns = .{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };
    }

    fn make_perspective(fov_radians: f32, aspect: f32, znear: f32, zfar: f32) float4x4 {
        const ys = 1.0 / std.math.tan(fov_radians * 0.5);
        const xs = ys / aspect;
        const zs = zfar / (znear - zfar);

        return matrix_from_rows(
            .{ xs, 0.0, 0.0, 0.0 },
            .{ 0.0, ys, 0.0, 0.0 },
            .{ 0.0, 0.0, zs, znear * zs },
            .{ 0.0, 0.0, -1.0, 0.0 },
        );
    }

    fn make_x_rotate(angle_radians: f32) float4x4 {
        const a = angle_radians;
        const c = std.math.cos(a);
        const s = std.math.sin(a);
        return matrix_from_rows(
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, c, s, 0.0 },
            .{ 0.0, -s, c, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        );
    }

    fn make_y_rotate(angle_radians: f32) float4x4 {
        const a = angle_radians;
        const c = std.math.cos(a);
        const s = std.math.sin(a);
        return matrix_from_rows(
            .{ c, 0.0, s, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ -s, 0.0, c, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        );
    }

    fn make_z_rotate(angle_radians: f32) float4x4 {
        const a = angle_radians;
        const c = std.math.cos(a);
        const s = std.math.sin(a);
        return matrix_from_rows(
            .{ c, s, 0.0, 0.0 },
            .{ -s, c, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        );
    }

    fn make_translate(t: float3) float4x4 {
        return .{ .columns = .{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ t[0], t[1], t[2], 1.0 },
        } };
    }

    fn make_scale(s: float3) float4x4 {
        return .{ .columns = .{
            .{ s[0], 0.0, 0.0, 0.0 },
            .{ 0.0, s[1], 0.0, 0.0 },
            .{ 0.0, 0.0, s[2], 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };
    }
};

const shader_source: [*:0]const u8 =
    \\#include <metal_stdlib> 
    \\using namespace metal;
    \\
    \\struct v2f {
    \\  float4 position [[position]];
    \\  half3 color;
    \\};
    \\
    \\struct VertexData {
    \\  float3 position;
    \\};
    \\
    \\struct InstanceData {
    \\  float4x4 instance_transform;
    \\  float4 instance_color;
    \\};
    \\
    \\struct CameraData {
    \\  float4x4 perspective_transform;
    \\  float4x4 world_transform;
    \\};
    \\
    \\v2f vertex vertex_main(
    \\      device const VertexData *vertex_data [[buffer(0)]],         
    \\      device const InstanceData *instance_data [[buffer(1)]],
    \\      device const CameraData &camera_data [[buffer(2)]],
    \\      uint vertex_id [[vertex_id]],
    \\      uint instance_id [[instance_id]] 
    \\){
    \\  v2f o;
    \\  float4 pos = float4(vertex_data[vertex_id].position, 1.0);
    \\  pos = instance_data[instance_id].instance_transform * pos;
    \\  pos = camera_data.perspective_transform * camera_data.world_transform * pos;
    \\  o.position = pos;
    \\  o.color = half3(instance_data[instance_id].instance_color.rgb);
    \\  return o;
    \\} 
    \\ 
    \\half4 fragment fragment_main(v2f in [[stage_in]]) { 
    \\  return half4(in.color, 1.0); 
    \\}
    \\ 
;

const InstanceData = extern struct {
    instance_transform: float4x4,
    instance_color: float4,
};

const CameraData = extern struct {
    perspective_transform: float4x4,
    world_transform: float4x4,
};

const BlockType = mtl.extras.block.BlockLiteralUserData1(void, *mtl.MTLCommandBuffer, Renderer);

const Renderer = struct {
    device: *mtl.MTLDevice = undefined,
    command_queue: *mtl.MTLCommandQueue = undefined,
    pso: *mtl.MTLRenderPipelineState = undefined,
    depth_stencil_state: *mtl.MTLDepthStencilState = undefined,
    library: *mtl.MTLLibrary = undefined,
    vertex_data_buffer: *mtl.MTLBuffer = undefined,
    index_buffer: *mtl.MTLBuffer = undefined,
    instance_data_buffer: [max_in_flight_frames]*mtl.MTLBuffer = undefined,
    camera_data_buffer: [max_in_flight_frames]*mtl.MTLBuffer = undefined,
    angle: f32 = 0,
    frame: usize = 0,
    sema: std.Thread.Semaphore = undefined,

    const max_in_flight_frames = 6;
    const num_instances = 32;

    const Self = @This();

    pub fn init(self: *Renderer, device: *mtl.MTLDevice) void {
        self.device = device;
        self.command_queue = self.device.newCommandQueue() orelse {
            @panic("Failed to create command queue!");
        };
        self.initPipeline();
        self.initDepthStencilStates();
        self.initBuffers();

        self.sema = std.Thread.Semaphore{ .permits = max_in_flight_frames };
    }

    pub fn deinit(self: *Self) void {
        self.library.release();
        self.vertex_data_buffer.release();
        self.index_buffer.release();
        for (0..max_in_flight_frames) |i| {
            self.instance_data_buffer[i].release();
            self.camera_data_buffer[i].release();
        }
        self.pso.release();
        self.depth_stencil_state.release();
        self.command_queue.release();
        self.device.release();
    }

    fn initPipeline(self: *Self) void {
        const source_string = mtl.NSString.stringWithUTF8String(shader_source);
        var library = self.device.newLibraryWithSourceOptionsError(source_string, null, null) orelse {
            @panic("Failed to create library!");
        };

        var vertex_function = library.newFunctionWithName(mtl.NSString.stringWithUTF8String("vertex_main")) orelse {
            @panic("Failed to create vertex function");
        };
        defer vertex_function.release();

        var fragment_function = library.newFunctionWithName(mtl.NSString.stringWithUTF8String("fragment_main")) orelse {
            @panic("Failed to create fragment function");
        };
        defer fragment_function.release();

        var rpdesc: *mtl.MTLRenderPipelineDescriptor = mtl.MTLRenderPipelineDescriptor.alloc().init();
        defer rpdesc.release();

        rpdesc.setVertexFunction(vertex_function);
        rpdesc.setFragmentFunction(fragment_function);
        rpdesc.colorAttachments().objectAtIndexedSubscript(0).setPixelFormat(mtl.MTLPixelFormat.MTLPixelFormatBGRA8Unorm_sRGB);
        rpdesc.setDepthAttachmentPixelFormat(.MTLPixelFormatDepth16Unorm);

        self.pso = self.device.newRenderPipelineStateWithDescriptorError(rpdesc, null) orelse {
            @panic("Failed to create render pipeline state!");
        };

        self.library = library;
    }

    fn initDepthStencilStates(self: *Self) void {
        var desc: *mtl.MTLDepthStencilDescriptor = mtl.MTLDepthStencilDescriptor.alloc().init();
        desc.setDepthCompareFunction(.MTLCompareFunctionLess);
        desc.setDepthWriteEnabled(@intFromBool(true));

        self.depth_stencil_state = self.device.newDepthStencilStateWithDescriptor(desc) orelse {
            @panic("Failed to create depth-stencil state");
        };

        defer desc.release();
    }

    fn initBuffers(self: *Self) void {
        const s: f32 = 0.5;

        var verts = [_]float3{
            .{ -s, -s, s },
            .{ s, -s, s },
            .{ s, s, s },
            .{ -s, s, s },

            .{ -s, -s, -s },
            .{ -s, s, -s },
            .{ s, s, -s },
            .{ s, -s, -s },
        };

        var indices = [_]u16{
            0, 1, 2,
            2, 3, 0,
            1, 7, 6,
            6, 2, 1,
            7, 4, 5,
            5, 6, 7,
            4, 0, 3,
            3, 5, 4,
            3, 2, 6,
            6, 5, 3,
            4, 7, 1,
            1, 0, 4,
        };

        self.vertex_data_buffer = self.device.newBufferWithBytesLengthOptions(
            @ptrCast(verts[0..].ptr),
            @intCast(@sizeOf(@TypeOf(verts))),
            .MTLResourceCPUCacheModeDefaultCache,
        ) orelse {
            @panic("Failed to create vertex buffer");
        };

        self.index_buffer = self.device.newBufferWithBytesLengthOptions(
            @ptrCast(indices[0..].ptr),
            @intCast(@sizeOf(@TypeOf(indices))),
            .MTLResourceCPUCacheModeDefaultCache,
        ) orelse {
            @panic("Failed to create index buffer");
        };

        for (0..max_in_flight_frames) |i| {
            self.instance_data_buffer[i] = self.device.newBufferWithLengthOptions(
                @intCast(num_instances * @sizeOf(InstanceData)),
                .MTLResourceCPUCacheModeDefaultCache,
            ) orelse {
                @panic("Failed to create instance data buffer");
            };
        }

        for (0..max_in_flight_frames) |i| {
            self.camera_data_buffer[i] = self.device.newBufferWithLengthOptions(
                @intCast(@sizeOf(CameraData)),
                .MTLResourceCPUCacheModeDefaultCache,
            ) orelse {
                @panic("Failed to create instance data buffer");
            };
        }
    }

    pub fn commandBufferCompletionHandler(self: *Self, _: *mtl.MTLCommandBuffer) void {
        self.sema.post();
    }

    pub fn draw(self: *Self, view: *MTKView) void {
        self.frame = (self.frame + 1) % @as(usize, @intCast(max_in_flight_frames));
        var instance_data_buffer = self.instance_data_buffer[self.frame];

        var cmd = self.command_queue.commandBuffer() orelse {
            @panic("Failed to create command buffer!");
        };

        self.sema.wait();

        var block = BlockType.init(&commandBufferCompletionHandler, self);
        cmd.addCompletedHandler(@ptrCast(&block));

        self.angle += 0.01;

        const scl: f32 = 0.1;
        var instance_data: [*c]InstanceData = @ptrCast(@alignCast(instance_data_buffer.contents()));
        const object_position = float3{ 0, 0, -5 };

        const rt = Math.make_translate(object_position);
        const rr = Math.make_y_rotate(-self.angle);
        const rt_inv = Math.make_translate(.{ -object_position[0], -object_position[1], -object_position[2] });
        const full_object_rot = //rt * rr * rt_inv;
            Math.matrix_mul(rt, Math.matrix_mul(rr, rt_inv));

        for (0..num_instances) |i| {
            const i_div_num_instances = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_instances));
            const xoff = std.math.sin((i_div_num_instances * 2.0 - 1.0) * 2.0 * std.math.pi);
            const yoff = std.math.sin((i_div_num_instances + self.angle) * 2.0 * std.math.pi);

            const scale = Math.make_scale(.{ scl, scl, scl });
            const zrot = Math.make_z_rotate(self.angle);
            const yrot = Math.make_y_rotate(self.angle);
            const translate = Math.make_translate(Math.add(object_position, .{ xoff, yoff, 0 }));

            instance_data[i].instance_transform = Math.matrix_mul(full_object_rot, Math.matrix_mul(translate, Math.matrix_mul(yrot, Math.matrix_mul(zrot, scale))));

            const r = i_div_num_instances;
            const g = 1.0 - r;
            const b = std.math.sin(2.0 * std.math.pi * i_div_num_instances);
            instance_data[i].instance_color = .{ r, g, b, 1.0 };
        }

        var camera_data_buffer = self.camera_data_buffer[self.frame];
        var camera_data: *CameraData = @ptrCast(@alignCast(camera_data_buffer.contents()));
        camera_data.perspective_transform = Math.make_perspective(Math.deg2rad(45), 1.0, 0.03, 500.0);
        camera_data.world_transform = Math.make_identity();

        const rpd = view.currentRenderPassDescriptor() orelse {
            @panic("Failed to get current render pass descriptor!");
        };

        var enc = cmd.renderCommandEncoderWithDescriptor(rpd) orelse {
            @panic("Failed to create command encoder!");
        };

        enc.setRenderPipelineState(self.pso);
        enc.setDepthStencilState(self.depth_stencil_state);

        enc.setVertexBufferOffsetAtIndex(self.vertex_data_buffer, 0, 0);
        enc.setVertexBufferOffsetAtIndex(instance_data_buffer, 0, 1);
        enc.setVertexBufferOffsetAtIndex(camera_data_buffer, 0, 2);

        enc.setCullMode(.MTLCullModeBack);
        enc.setFrontFacingWinding(.MTLWindingClockwise);

        enc.drawIndexedPrimitivesIndexCountIndexTypeIndexBufferIndexBufferOffsetInstanceCount(
            .MTLPrimitiveTypeTriangle,
            6 * 6,
            .MTLIndexTypeUInt16,
            self.index_buffer,
            0,
            num_instances,
        );

        enc.endEncoding();

        const drawable = view.currentDrawable() orelse {
            @panic("Failed to get drawable!");
        };

        cmd.presentDrawable(drawable);
        cmd.commit();
    }
};

const MetalViewDelegate = struct {
    device: *mtl.MTLDevice = undefined,
    renderer: Renderer = .{},

    const Self = @This();

    pub fn init(device: *mtl.MTLDevice) Self {
        var result = Self{
            .device = device,
        };

        result.renderer.init(device);

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.renderer.deinit();
    }

    pub fn drawInMTKView(self: *Self, view: *MTKView) void {
        self.renderer.draw(view);
    }
};

const MyApplicationDelegate = struct {
    const Self = @This();
    window: *NSWindow = undefined,
    device: *mtl.MTLDevice = undefined,
    view: *MTKView = undefined,
    view_delegate: MetalViewDelegate = .{},

    pub fn applicationWillFinishLaunching(self: *Self, notification: *mtl.NSNotification) void {
        _ = self;
        std.log.info("will finish launching!", .{});

        var app: *NSApplication = @ptrCast(notification.object());
        app.setActivationPolicy(.ActivationPolicyRegular);
    }

    pub fn applicationDidFinishLaunching(self: *Self, notification: *mtl.NSNotification) void {
        std.log.info("did finish launching!", .{});

        const frame = mtl.CGRect{
            .origin = .{ .x = 100, .y = 100 },
            .size = .{ .width = 512, .height = 512 },
        };

        self.window = NSWindow.alloc().initWithContentRectStyleMaskBackingDefer(
            frame,
            appkit.NSWindowStyleMaskClosable | appkit.NSWindowStyleMaskTitled,
            appkit.NSBackingStoreType.BackingStoreBuffered,
            false,
        );

        self.device = mtl.MTLCreateSystemDefaultDevice() orelse {
            @panic("Failed to create device!");
        };

        self.view = MTKView.alloc().initWithFrameDevice(frame, self.device);
        self.view.setColorPixelFormat(mtl.MTLPixelFormat.MTLPixelFormatBGRA8Unorm_sRGB);
        self.view.setClearColor(mtl.MTLClearColorMake(0.1, 0.1, 0.1, 1));
        self.view.setDepthStencilPixelFormat(.MTLPixelFormatDepth16Unorm);
        self.view.setClearDepth(1.0);

        self.view_delegate = MetalViewDelegate.init(self.device);
        self.view.setDelegate(&self.view_delegate);

        self.window.setContentView(@ptrCast(self.view));
        self.window.setTitle(mtl.NSString.stringWithUTF8String("Zig Metal Sample 06: Perspective"));

        self.window.makeKeyAndOrderFront(null);

        var app: *NSApplication = @ptrCast(notification.object());
        app.activateIgnoringOtherApps(true);
    }

    pub fn applicationShouldTerminateAfterLastWindowClosed(_: *Self, _: *mtl.NSNotification) bool {
        return true;
    }

    pub fn deinit(self: *Self) void {
        self.view_delegate.deinit();
    }
};

pub fn main() !void {
    std.log.info("hello!", .{});

    var app = NSApplication.sharedApplication() orelse {
        @panic("No application!");
    };

    var delegate = MyApplicationDelegate{};

    app.setDelegate(&delegate);
    app.run();

    delegate.deinit();
}
