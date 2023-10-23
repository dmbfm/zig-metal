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

const Renderer = struct {
    device: *mtl.MTLDevice = undefined,
    command_queue: *mtl.MTLCommandQueue = undefined,

    const Self = @This();

    pub fn init(self: *Renderer, device: *mtl.MTLDevice) void {
        self.device = device;
        self.command_queue = self.device.newCommandQueue() orelse {
            @panic("Failed to create command queue!");
        };
    }

    pub fn deinit(self: *Self) void {
        self.command_queue.release();
        self.device.release();
    }

    pub fn draw(self: *Self, view: *MTKView) void {
        var cmd = self.command_queue.commandBuffer() orelse {
            @panic("Failed to create command buffer!");
        };

        var rpd = view.currentRenderPassDescriptor() orelse {
            @panic("Failed to get current render pass descriptor!");
        };

        var enc = cmd.renderCommandEncoderWithDescriptor(rpd) orelse {
            @panic("Failed to create command encoder!");
        };

        var drawable = view.currentDrawable() orelse {
            @panic("Failed to get drawable!");
        };

        enc.endEncoding();
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
            .BackingStoreBuffered,
            false,
        );

        self.device = mtl.MTLCreateSystemDefaultDevice() orelse {
            @panic("Failed to create device!");
        };

        self.view = MTKView.alloc().initWithFrameDevice(frame, self.device);
        self.view.setColorPixelFormat(mtl.MTLPixelFormat.MTLPixelFormatBGRA8Unorm_sRGB);
        self.view.setClearColor(mtl.MTLClearColorMake(1, 0, 0, 1));

        self.view_delegate = MetalViewDelegate.init(self.device);
        self.view.setDelegate(&self.view_delegate);

        self.window.setContentView(@ptrCast(self.view));
        self.window.setTitle(mtl.NSString.stringWithUTF8String("Zig Metal Sample 01: Window"));

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
