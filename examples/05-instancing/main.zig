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
    \\v2f vertex vertex_main(
    \\      device const VertexData *vertex_data [[buffer(0)]],         
    \\      device const InstanceData *instance_data [[buffer(1)]],
    \\      uint vertex_id [[vertex_id]],
    \\      uint instance_id [[instance_id]] 
    \\  ){
    \\  v2f o;
    \\
    \\  float4 pos = float4(vertex_data[vertex_id].position, 1.0);
    \\  o.position = instance_data[instance_id].instance_transform * pos;
    \\  o.color = half3(instance_data[instance_id].instance_color.rgb);
    \\  return o;
    \\} 
    \\ 
    \\half4 fragment fragment_main(v2f in [[stage_in]]) { 
    \\  return half4(in.color, 1.0); 
    \\}
    \\ 
    \\ 
;

const InstanceData = extern struct {
    instance_transform: float4x4,
    instance_color: float4,
};

const BlockType = mtl.extras.block.BlockLiteralUserData1(void, *mtl.MTLCommandBuffer, Renderer);

const Renderer = struct {
    device: *mtl.MTLDevice = undefined,
    command_queue: *mtl.MTLCommandQueue = undefined,
    pso: *mtl.MTLRenderPipelineState = undefined,
    library: *mtl.MTLLibrary = undefined,
    vertex_data_buffer: *mtl.MTLBuffer = undefined,
    instance_data_buffer: [max_in_flight_frames]*mtl.MTLBuffer = undefined,
    index_buffer: *mtl.MTLBuffer = undefined,
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
        self.initBuffers();

        self.sema = std.Thread.Semaphore{ .permits = max_in_flight_frames };
    }

    pub fn deinit(self: *Self) void {
        self.library.release();
        self.vertex_data_buffer.release();
        self.index_buffer.release();
        for (0..max_in_flight_frames) |i| {
            self.instance_data_buffer[i].release();
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
        const s: f32 = 0.5;

        var verts = [_]float3{
            .{ -s, -s, s },
            .{ s, -s, s },
            .{ s, s, s },
            .{ -s, s, s },
        };

        var indices = [_]u16{
            0, 1, 2, 2, 3, 0,
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
        for (0..num_instances) |i| {
            const i_div_num_instances = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_instances));
            const xoff = std.math.sin((i_div_num_instances * 2.0 - 1.0) * 2.0 * std.math.pi);
            const yoff = std.math.sin((i_div_num_instances + self.angle) * 2.0 * std.math.pi);

            const sin = std.math.sin(self.angle);
            const cos = std.math.cos(self.angle);
            instance_data[i].instance_transform = .{
                .columns = .{
                    .{ scl * sin, scl * cos, 0, 0 },
                    .{ scl * cos, -scl * sin, 0, 0 },
                    .{ 0, 0, scl, 0 },
                    .{ xoff, yoff, 0, 1 },
                },
            };

            const r = i_div_num_instances;
            const g = 1.0 - r;
            const b = std.math.sin(2.0 * std.math.pi * i_div_num_instances);
            instance_data[i].instance_color = .{ r, g, b, 1.0 };
        }

        var rpd = view.currentRenderPassDescriptor() orelse {
            @panic("Failed to get current render pass descriptor!");
        };

        var enc = cmd.renderCommandEncoderWithDescriptor(rpd) orelse {
            @panic("Failed to create command encoder!");
        };

        enc.setRenderPipelineState(self.pso);
        enc.setVertexBufferOffsetAtIndex(self.vertex_data_buffer, 0, 0);
        enc.setVertexBufferOffsetAtIndex(instance_data_buffer, 0, 1);
        enc.drawIndexedPrimitivesIndexCountIndexTypeIndexBufferIndexBufferOffsetInstanceCount(
            .MTLPrimitiveTypeTriangle,
            6,
            .MTLIndexTypeUInt16,
            self.index_buffer,
            0,
            num_instances,
        );

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
        self.window.setTitle(mtl.NSString.stringWithUTF8String("Zig Metal Sample 05: Instancing"));

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
