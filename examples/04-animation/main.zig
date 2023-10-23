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

const float2 = @Vector(3, f32);
const float3 = @Vector(3, f32);
const float4 = @Vector(3, f32);

const shader_source: [*:0]const u8 =
    \\#include <metal_stdlib> 
    \\using namespace metal;
    \\
    \\struct v2f {
    \\  float4 position [[position]];
    \\  half3 color;
    \\};
    \\
    \\
    \\struct VertexData {
    \\  device float3* positions;
    \\  device float3* colors;
    \\};
    \\
    \\
    \\struct FrameData {
    \\  float angle;
    \\};
    \\
    \\
    \\v2f vertex vertex_main(
    \\      uint vertex_id [[ vertex_id ]], 
    \\      device const VertexData *data [[buffer(0)]], 
    \\      constant FrameData *frameData [[buffer(1)]]) {
    \\  v2f o;
    \\
    \\  float a = frameData->angle;
    \\  float3x3 rot_mat = float3x3(sin(a), cos(a), 0.0, cos(a), -sin(a), 0.0, 0.0, 0.0, 1.0);
    \\  o.position = float4(rot_mat * data->positions[vertex_id], 1.0);
    \\  o.color = half3(data->colors[vertex_id]);
    \\  return o;
    \\} 
    \\ 
    \\half4 fragment fragment_main(v2f in [[stage_in]]) { 
    \\  return half4(in.color, 1.0); 
    \\}
    \\ 
    \\ 
;

const FrameData = extern struct {
    angle: f32,
};

const VertexData = extern struct {
    positions: *float3,
    colors: *float3,
};

const BlockType = mtl.extras.block.BlockLiteralUserData1(void, *mtl.MTLCommandBuffer, Renderer);

const Renderer = struct {
    device: *mtl.MTLDevice = undefined,
    command_queue: *mtl.MTLCommandQueue = undefined,
    pso: *mtl.MTLRenderPipelineState = undefined,
    library: *mtl.MTLLibrary = undefined,
    vertex_positions_buffer: *mtl.MTLBuffer = undefined,
    vertex_colors_buffer: *mtl.MTLBuffer = undefined,
    arg_buffer: *mtl.MTLBuffer = undefined,
    frame_data: [max_in_flight_frames]*mtl.MTLBuffer = undefined,
    angle: f32 = 0,
    frame: usize = 0,
    sema: std.Thread.Semaphore = undefined,

    const max_in_flight_frames = 6;

    const Self = @This();

    pub fn init(self: *Renderer, device: *mtl.MTLDevice) void {
        self.device = device;
        self.command_queue = self.device.newCommandQueue() orelse {
            @panic("Failed to create command queue!");
        };
        self.initPipeline();
        self.initBuffers();
        self.initFrameData();

        self.sema = std.Thread.Semaphore{ .permits = max_in_flight_frames };
    }

    pub fn deinit(self: *Self) void {
        self.library.release();
        self.arg_buffer.release();
        self.vertex_colors_buffer.release();
        self.vertex_positions_buffer.release();
        for (&self.frame_data) |buf| {
            buf.release();
        }
        self.pso.release();
        self.command_queue.release();
        self.device.release();
    }

    fn initPipeline(self: *Self) void {
        var source_string = mtl.NSString.stringWithUTF8String(shader_source);
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

        self.pso = self.device.newRenderPipelineStateWithDescriptorError(rpdesc, null) orelse {
            @panic("Failed to create render pipeline state!");
        };

        self.library = library;
    }

    fn initBuffers(self: *Self) void {
        const num_vertices: usize = 3;

        var positions = [num_vertices]float3{
            .{ -0.8, 0.8, 0 },
            .{ 0, -0.8, 0 },
            .{ 0.8, 0.8, 0 },
        };
        var colors = [num_vertices]float3{
            .{ 1.0, 0.3, 0.2 },
            .{ 0.8, 1.0, 0.0 },
            .{ 0.8, 0.0, 1.0 },
        };

        const positions_data_size: usize = @sizeOf(@TypeOf(positions));
        const colors_data_size: usize = @sizeOf(@TypeOf(positions));

        self.vertex_positions_buffer = self.device.newBufferWithBytesLengthOptions(
            @ptrCast(positions[0..].ptr),
            @intCast(positions_data_size),
            mtl.MTLResourceOptions.MTLResourceCPUCacheModeDefaultCache,
        ) orelse {
            @panic("Failed to create vertex positions buffer");
        };

        self.vertex_colors_buffer = self.device.newBufferWithBytesLengthOptions(
            @ptrCast(colors[0..].ptr),
            @intCast(colors_data_size),
            mtl.MTLResourceOptions.MTLResourceCPUCacheModeDefaultCache,
        ) orelse {
            @panic("Failed to create vertex positions buffer");
        };

        const arg_buffer_len: usize = @sizeOf(VertexData);

        self.arg_buffer = self.device.newBufferWithLengthOptions(@intCast(arg_buffer_len), .MTLResourceCPUCacheModeDefaultCache) orelse {
            @panic("Failed to create argument buffer");
        };

        var data_ptr: *VertexData = @ptrCast(@alignCast(self.arg_buffer.contents()));
        data_ptr.positions = @ptrFromInt(@as(usize, @intCast(self.vertex_positions_buffer.gpuAddress())));
        data_ptr.colors = @ptrFromInt(@as(usize, @intCast(self.vertex_colors_buffer.gpuAddress())));
    }

    pub fn initFrameData(self: *Self) void {
        for (0..max_in_flight_frames) |i| {
            self.frame_data[i] = self.device.newBufferWithLengthOptions(@sizeOf(FrameData), .MTLResourceCPUCacheModeDefaultCache) orelse {
                @panic("Failed to create frame data!");
            };
        }
    }

    pub fn commandBufferCompletionHandler(self: *Self, _: *mtl.MTLCommandBuffer) void {
        self.sema.post();
    }

    pub fn draw(self: *Self, view: *MTKView) void {
        self.frame = (self.frame + 1) % @as(usize, @intCast(max_in_flight_frames));
        var frame_data_buffer = self.frame_data[self.frame];

        var cmd = self.command_queue.commandBuffer() orelse {
            @panic("Failed to create command buffer!");
        };

        self.sema.wait();

        var block = BlockType.init(&commandBufferCompletionHandler, self);
        cmd.addCompletedHandler(@ptrCast(&block));

        var frame_data: *FrameData = @ptrCast(@alignCast(frame_data_buffer.contents()));
        frame_data.angle += 0.0025;
        // frame_data_buffer.didModifyRange(.{ .location = 0, .length = @intCast(@sizeOf(FrameData)) });

        var rpd = view.currentRenderPassDescriptor() orelse {
            @panic("Failed to get current render pass descriptor!");
        };

        var enc = cmd.renderCommandEncoderWithDescriptor(rpd) orelse {
            @panic("Failed to create command encoder!");
        };

        enc.useResourceUsage(@ptrCast(self.vertex_positions_buffer), .MTLResourceUsageRead);
        enc.useResourceUsage(@ptrCast(self.vertex_colors_buffer), .MTLResourceUsageRead);

        enc.setRenderPipelineState(self.pso);
        enc.setVertexBufferOffsetAtIndex(self.arg_buffer, 0, 0);
        enc.setVertexBufferOffsetAtIndex(frame_data_buffer, 0, 1);
        enc.drawPrimitivesVertexStartVertexCount(.MTLPrimitiveTypeTriangle, 0, 3);

        enc.endEncoding();

        var drawable = view.currentDrawable() orelse {
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

        var frame = mtl.CGRect{
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
        self.view.setClearColor(mtl.MTLClearColorMake(1, 1, 1, 1));

        self.view_delegate = MetalViewDelegate.init(self.device);
        self.view.setDelegate(&self.view_delegate);

        self.window.setContentView(@ptrCast(self.view));
        self.window.setTitle(mtl.NSString.stringWithUTF8String("Zig Metal Sample 04: Animation"));

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
