const std = @import("std");
const gen = @import("gen.zig");
const trait = @import("zigtrait");

const objc_msgSend = gen.objc_msgSend;
const id = gen.id;
const Class = gen.Class;
const SEL = gen.SEL;
const IMP = gen.IMP;
const CachedSelector = gen.CachedSelector;
const CachedClass = gen.CachedClass;
const NSViewInterfaceMixin = @import("appkit.zig").NSViewInterfaceMixin;

extern fn class_addMethod(Class, SEL, *const opaque {}, [*:0]const u8) void;
extern fn objc_setAssociatedObject(
    id,
    [*:0]const u8,
    id,
    c_ulong,
) void;

fn MTKViewDelegateWrapper(comptime DelegateType: type, comptime ViewType: type) type {
    return struct {
        pub fn drawInMTKView(self: *gen.NSValue, _: SEL, view: *ViewType) callconv(.C) void {
            var delegate_instance_pointer: *DelegateType = @ptrCast(@alignCast(self.pointerValue()));
            delegate_instance_pointer.drawInMTKView(view);
        }

        pub fn drawableSizeWillChange(self: *gen.NSValue, _: SEL, view: *ViewType, size: gen.CGSize) callconv(.C) void {
            var delegate_instance_pointer: *DelegateType = @ptrCast(@alignCast(self.pointerValue()));
            delegate_instance_pointer.drawableSizeWillChange(view, size);
        }
    };
}

pub fn MTKViewInterfaceMixin(comptime Self: type, comptime class_name: [*:0]const u8) type {
    return struct {
        var class = CachedClass.init(class_name);

        pub usingnamespace NSViewInterfaceMixin(Self, class_name);

        var sel_init_with_frame_device = CachedSelector.init("initWithFrame:device:");
        pub fn initWithFrameDevice(self: *Self, frame: gen.CGRect, value: *gen.MTLDevice) *Self {
            return @as(*const fn (*Self, SEL, gen.CGRect, *gen.MTLDevice) callconv(.C) *Self, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_init_with_frame_device.get(), frame, value);
        }

        var sel_set_device = CachedSelector.init("setDevice:");
        pub fn setDevice(self: *Self, value: *gen.MTLDevice) void {
            return @as(*const fn (*Self, SEL, *gen.MTLDevice) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_device.get(), value);
        }

        var sel_device = CachedSelector.init("device");
        pub fn device(self: *Self) *gen.MTLDevice {
            return @as(*const fn (*Self, SEL) callconv(.C) *gen.MTLDevice, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_device.get());
        }

        var sel_preferredDevice = CachedSelector.init("preferredDevice");
        pub fn preferredDevice(self: *Self) *gen.MTLDevice {
            return @as(*const fn (*Self, SEL) callconv(.C) *gen.MTLDevice, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_preferredDevice.get());
        }

        var sel_set_delegate = CachedSelector.init("setDelegate:");
        //var del_value:
        pub fn setDelegate(self: *Self, del: anytype) void {
            const ti = @typeInfo(@TypeOf(del));

            const DelegateType: type = switch (ti) {
                .Pointer => |ptr| ptr.child,
                else => {
                    @compileError("'del' should be a pointer!");
                },
            };

            const value = gen.NSValue.valueWithPointer(@ptrCast(del));
            const nsvalue_class = gen.objc_lookUpClass("NSValue");
            const sel_drawInMTKView = gen.sel_registerName("drawInMTKView:");
            const sel_drawableSizeWillChange = gen.sel_registerName("mtkView:drawableSizeWillChange:");

            const Wrapper = MTKViewDelegateWrapper(DelegateType, Self);

            comptime var hasDrawInMTKView = false;
            comptime var hasDrawableSizeWillChange = false;
            comptime {
                if (trait.hasFn("drawInMTKView")(DelegateType)) {
                    hasDrawInMTKView = true;
                }
            }

            if (hasDrawInMTKView) {
                class_addMethod(nsvalue_class, sel_drawInMTKView, @ptrCast(&Wrapper.drawInMTKView), "v@:@");
            }

            comptime {
                if (trait.hasFn("drawableSizeWillChange")(DelegateType)) {
                    hasDrawableSizeWillChange = true;
                }
            }

            if (hasDrawableSizeWillChange) {
                // NOTE: assuming CGFloat is double here!
                class_addMethod(nsvalue_class, sel_drawableSizeWillChange, @ptrCast(&Wrapper.drawableSizeWillChange), "v@:@{CGSize=dd}");
            }

            objc_setAssociatedObject(@ptrCast(value), "mtkviewdelegate_zig", @ptrCast(value), 1);
            return @as(*const fn (*Self, SEL, id) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_delegate.get(), @ptrCast(value));
        }

        var sel_current_drawable = CachedSelector.init("currentDrawable");
        pub fn currentDrawable(self: *Self) ?*gen.MTLDrawable {
            return @as(*const fn (*Self, SEL) callconv(.C) ?*gen.MTLDrawable, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_current_drawable.get());
        }

        var sel_set_framebuffer_only = CachedSelector.init("setFramebufferOnly:");
        pub fn setFramebufferOnly(self: *Self, value: bool) void {
            innerSet(self, sel_set_framebuffer_only, value);
        }

        var sel_framebuffer_only = CachedSelector.init("framebufferOnly");
        pub fn framebufferOnly(self: *Self) bool {
            return innerGet(self, bool, sel_framebuffer_only);
        }

        var sel_setDepthStencilAttachmentTextureUsage = CachedSelector.init("setDepthStencilAttachmentTextureUsage:");
        pub fn setDepthStencilAttachmentTextureUsage(self: *Self, value: gen.MTLTextureUsage) void {
            return innerSet(self, sel_setDepthStencilAttachmentTextureUsage, value);
        }

        var sel_depthStencilAttachmentTextureUsage = CachedSelector.init("depthStencilAttachmentTextureUsage");
        pub fn depthStencilAttachmentTextureUsage(self: *Self) gen.MTLTextureUsage {
            return innerGet(self, gen.MTLTextureUsage, sel_setDepthStencilAttachmentTextureUsage);
        }

        var sel_setMultisampleColorAttachmentTextureUsage = CachedSelector.init("setMultisampleColorAttachmentTextureUsage:");
        pub fn setMultisampleColorAttachmentTextureUsage(self: *Self, value: gen.MTLTextureUsage) void {
            return innerSet(self, sel_setMultisampleColorAttachmentTextureUsage, value);
        }

        var sel_multisampleColorAttachmentTextureUsage = CachedSelector.init("multisampleColorAttachmentTextureUsage");
        pub fn multisampleColorAttachmentTextureUsage(self: *Self) gen.MTLTextureUsage {
            return innerGet(self, gen.MTLTextureUsage, sel_setDepthStencilAttachmentTextureUsage);
        }

        var sel_setPresentsWithTransaction = CachedSelector.init("setPresentsWithTransaction:");
        pub fn setPresentsWithTransaction(self: *Self, value: bool) void {
            return innerSet(self, sel_setPresentsWithTransaction, value);
        }

        var sel_presentsWithTransaction = CachedSelector.init("presentsWithTransaction");
        pub fn presentsWithTransaction(self: *Self) bool {
            return innerGet(self, bool, sel_presentsWithTransaction);
        }

        var sel_setColorPixelFormat = CachedSelector.init("setColorPixelFormat:");
        pub fn setColorPixelFormat(self: *Self, value: gen.MTLPixelFormat) void {
            return innerSet(self, sel_setColorPixelFormat, value);
        }

        var sel_colorPixelFormat = CachedSelector.init("colorPixelFormat");
        pub fn colorPixelFormat(self: *Self) gen.MTLPixelFormat {
            return innerGet(self, gen.MTLPixelFormat, sel_colorPixelFormat);
        }

        var sel_setDepthStencilPixelFormat = CachedSelector.init("setDepthStencilPixelFormat:");
        pub fn setDepthStencilPixelFormat(self: *Self, value: gen.MTLPixelFormat) void {
            return innerSet(self, sel_setDepthStencilPixelFormat, value);
        }

        var sel_depthStencilPixelFormat = CachedSelector.init("depthStencilPixelFormat");
        pub fn depthStencilPixelFormat(self: *Self) gen.MTLPixelFormat {
            return innerGet(self, gen.MTLPixelFormat, sel_depthStencilPixelFormat);
        }

        var sel_setSampleCount = CachedSelector.init("setSampleCount:");
        pub fn setSampleCount(self: *Self, value: u64) void {
            return innerSet(self, sel_setSampleCount, value);
        }

        var sel_sampleCount = CachedSelector.init("sampleCount");
        pub fn sampleCaount(self: *Self) u64 {
            return innerGet(self, u64, sel_sampleCount);
        }

        var sel_setClearColor = CachedSelector.init("setClearColor:");
        pub fn setClearColor(self: *Self, value: gen.MTLClearColor) void {
            return innerSet(self, sel_setClearColor, value);
        }

        var sel_clearColor = CachedSelector.init("clearColor");
        pub fn clearColor(self: *Self) gen.MTLClearColor {
            return innerGet(self, gen.MTLClearColor, sel_clearColor);
        }

        var sel_setClearDepth = CachedSelector.init("setClearDepth:");
        pub fn setClearDepth(self: *Self, value: f64) void {
            return innerSet(self, sel_setClearDepth, value);
        }

        var sel_clearDepth = CachedSelector.init("clearDepth");
        pub fn clearDepth(self: *Self) f64 {
            return innerGet(self, f64, sel_clearDepth);
        }

        var sel_setClearStencil = CachedSelector.init("setClearStencil:");
        pub fn setClearStencil(self: *Self, value: u32) void {
            return innerSet(self, sel_setClearStencil, value);
        }

        var sel_clearStencil = CachedSelector.init("clearStencil");
        pub fn clearStencil(self: *Self) u32 {
            return innerGet(self, u32, sel_clearStencil);
        }

        var sel_depthStencilTexture = CachedSelector.init("depthStencilTexture");
        pub fn depthStencilTexture(self: *Self) ?*gen.MTLTexture {
            return innerGet(self, *gen.MTLTexture, sel_depthStencilTexture);
        }

        var sel_multisampleColorTexture = CachedSelector.init("multisampleColorTexture");
        pub fn multisampleColorTexture(self: *Self) ?*gen.MTLTexture {
            return innerGet(self, *gen.MTLTexture, sel_multisampleColorTexture);
        }

        var sel_releaseDrawables = CachedSelector.init("releaseDrawables");
        pub fn releaseDrawables(self: *Self) void {
            return @as(*const fn (*Self, SEL) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_releaseDrawables.get());
        }

        var sel_currentRenderPassDescriptor = CachedSelector.init("currentRenderPassDescriptor");
        pub fn currentRenderPassDescriptor(self: *Self) ?*gen.MTLRenderPassDescriptor {
            return innerGet(self, ?*gen.MTLRenderPassDescriptor, sel_currentRenderPassDescriptor);
        }

        var sel_setPreferredFramesPerSecond = CachedSelector.init("setPreferredFramesPerSecond:");
        pub fn setPreferredFramesPerSecond(self: *Self, value: i64) void {
            return innerSet(self, sel_setPreferredFramesPerSecond, value);
        }

        var sel_preferredFramesPerSecond = CachedSelector.init("preferredFramesPerSecond");
        pub fn preferredFramesPerSecond(self: *Self) i64 {
            return innerGet(self, i64, sel_preferredFramesPerSecond);
        }

        var sel_setEnableSetNeedsDisplay = CachedSelector.init("setEnableSetNeedsDisplay:");
        pub fn setEnableSetNeedsDisplay(self: *Self, value: bool) void {
            return innerSet(self, sel_setEnableSetNeedsDisplay, value);
        }

        var sel_enableSetNeedsDisplay = CachedSelector.init("enableSetNeedsDisplay");
        pub fn enableSetNeedsDisplay(self: *Self) bool {
            return innerGet(self, bool, sel_enableSetNeedsDisplay);
        }

        var sel_setAutoresizeDrawable = CachedSelector.init("setAutoresizeDrawable:");
        pub fn setAutoresizeDrawable(self: *Self, value: bool) void {
            return innerSet(self, sel_setAutoresizeDrawable, value);
        }

        var sel_autoresizeDrawable = CachedSelector.init("autoresizeDrawable");
        pub fn autoresizeDrawable(self: *Self) bool {
            return innerGet(self, bool, sel_autoresizeDrawable);
        }

        var sel_setDrawableSize = CachedSelector.init("setDrawableSize:");
        pub fn setDrawableSize(self: *Self, value: gen.CGSize) gen.CGSize {
            return innerSet(self, sel_setDrawableSize, value);
        }

        var sel_drawableSize = CachedSelector.init("drawableSize");
        pub fn drawableSize(self: *Self) gen.CGSize {
            return innerGet(self, gen.CGSize, sel_drawableSize);
        }

        var sel_preferredDrawableSize = CachedSelector.init("preferredDrawableSize");
        pub fn preferredDrawableSize(self: *Self) gen.CGSize {
            return innerGet(self, gen.CGSize, sel_preferredDrawableSize);
        }

        var sel_setPaused = CachedSelector.init("setPaused:");
        pub fn setPaused(self: *Self, value: bool) void {
            return innerSet(self, sel_setPaused, value);
        }

        var sel_paused = CachedSelector.init("paused");
        pub fn paused(self: *Self) bool {
            return innerGet(self, bool, sel_paused);
        }

        fn innerSet(self: *Self, sel: CachedSelector, value: anytype) void {
            var s = sel;
            return @as(*const fn (*Self, SEL, @TypeOf(value)) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), s.get(), value);
        }

        fn innerGet(self: *Self, comptime T: type, sel: CachedSelector) T {
            var s = sel;
            return @as(*const fn (*Self, SEL) callconv(.C) T, @ptrCast(&objc_msgSend))(@ptrCast(self), s.get());
        }
    };
}

pub const MTKView = opaque {
    const Self = @This();
    const class_name = "MTKView";
    //var sel_debugDescription = CachedSelector.init("debugDescription");
    //var class = CachedClass.init("MTKView");
    //pub fn debugDescription() *gen.NSString {
    //    {
    //        return @as(*const fn (
    //            Class,
    //            SEL,
    //        ) callconv(.C) *gen.NSString, @ptrCast(&objc_msgSend))(
    //            class.get(),
    //            sel_debugDescription.get(),
    //        );
    //    }
    //}

    // pub usingnamespace gen.NSObjectProtocolMixin(Self, class_name);
    pub usingnamespace gen.NSObjectInterfaceMixin(Self, class_name);
    pub usingnamespace MTKViewInterfaceMixin(Self, class_name);
};
