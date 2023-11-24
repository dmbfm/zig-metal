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

extern fn class_addMethod(Class, SEL, *const opaque {}, [*:0]const u8) void;
extern fn objc_setAssociatedObject(
    id,
    [*:0]const u8,
    id,
    c_ulong,
) void;
// pub const NSWindowStyleMask = packed struct {
const NSWindowStyleMask = u64;
pub const NSWindowStyleMaskBorderless: u64 = 0;
pub const NSWindowStyleMaskTitled: u64 = (1 << 0);
pub const NSWindowStyleMaskClosable: u64 = (1 << 1);
pub const NSWindowStyleMaskMiniaturizable: u64 = (1 << 2);
pub const NSWindowStyleMaskResizable: u64 = (1 << 3);
pub const NSWindowStyleMaskTexturedBackground: u64 = (1 << 8);
pub const NSWindowStyleMaskUnifiedTitleAndToolbar: u64 = (1 << 12);
pub const NSWindowStyleMaskFullScreen: u64 = (1 << 14);
pub const NSWindowStyleMaskFullSizeContentView: u64 = (1 << 15);
pub const NSWindowStyleMaskUtilityWindow: u64 = (1 << 4);
pub const NSWindowStyleMaskDocModalWindow: u64 = (1 << 6);
pub const NSWindowStyleMaskNonactivatingPanel: u64 = (1 << 7);
pub const NSWindowStyleMaskHUDWindow: u64 = (1 << 13);

// };

pub const NSBackingStoreType = enum(u64) {
    BackingStoreRetained = 0,
    BackingStoreNonretained = 1,
    BackingStoreBuffered = 2,
};

pub const NSActivationPolicy = enum(u64) {
    ActivationPolicyRegular = 0,
    ActivationPolicyAccessory = 1,
    ActivationPolicyProhibited = 2,
};

pub const NSApplication = opaque {
    var sel_shared_application = CachedSelector.init("sharedApplication");
    var sel_set_delegate = CachedSelector.init("setDelegate:");
    var sel_set_activation_policy = CachedSelector.init("setActivationPolicy:");
    var sel_activate_ignoring_other_apps = CachedSelector.init("activateIgnoringOtherApps:");
    var sel_windows = CachedSelector.init("windows");
    var sel_run = CachedSelector.init("run");
    var class = CachedClass.init("NSApplication");

    const Self = @This();

    pub fn sharedApplication() ?*Self {
        return @as(*const fn (Class, SEL) callconv(.C) ?*Self, @ptrCast(&objc_msgSend))(class.get(), sel_shared_application.get());
    }

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
        const sel = gen.sel_registerName("applicationDidFinishLaunching:");
        const sel2 = gen.sel_registerName("applicationWillFinishLaunching:");
        const sel3 = gen.sel_registerName("applicationShouldTerminateAfterLastWindowClosed:");

        const Wrapper = ApplicationDelegateWrapper(DelegateType);

        comptime var hasApplicationDidFinishLaunching = false;
        comptime var hasApplicationWillFinishLaunching = false;
        comptime var hasApplicationShouldTerminateAfterLastWindowClosed = false;
        comptime {
            if (trait.hasFn("applicationDidFinishLaunching")(DelegateType)) {
                hasApplicationDidFinishLaunching = true;
            }
        }

        if (hasApplicationDidFinishLaunching) {
            class_addMethod(nsvalue_class, sel, @ptrCast(&Wrapper.applicationDidFinishLaunching), "v@:@");
        }

        comptime {
            if (trait.hasFn("applicationWillFinishLaunching")(DelegateType)) {
                hasApplicationWillFinishLaunching = true;
            }
        }

        if (hasApplicationWillFinishLaunching) {
            class_addMethod(nsvalue_class, sel2, @ptrCast(&Wrapper.applicationWillFinishLaunching), "v@:@");
        }

        comptime {
            if (trait.hasFn("applicationShouldTerminateAfterLastWindowClosed")(DelegateType)) {
                hasApplicationShouldTerminateAfterLastWindowClosed = true;
            }
        }

        if (hasApplicationShouldTerminateAfterLastWindowClosed) {
            class_addMethod(nsvalue_class, sel3, @ptrCast(&Wrapper.applicationShouldTerminateAfterLastWindowClosed), "B@:@");
        }

        objc_setAssociatedObject(@ptrCast(value), "nsapplicationdelegate_zig", @ptrCast(value), 1);
        return @as(*const fn (*Self, SEL, id) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_delegate.get(), @ptrCast(value));
    }

    pub fn setActivationPolicy(self: *Self, value: NSActivationPolicy) void {
        return @as(*const fn (*Self, SEL, NSActivationPolicy) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_activation_policy.get(), value);
    }

    pub fn activateIgnoringOtherApps(self: *Self, value: bool) void {
        return @as(*const fn (*Self, SEL, bool) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_activate_ignoring_other_apps.get(), value);
    }

    pub fn run(self: *Self) void {
        return @as(*const fn (*Self, SEL) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_run.get());
    }

    pub fn windows(self: *Self) *gen.NSArray {
        return @as(*const fn (*Self, SEL) callconv(.C) *gen.NSArray, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_windows.get());
    }

    // TODO:
    //pub fn setMainMenu()

};

fn ApplicationDelegateWrapper(comptime DelegateType: type) type {
    return struct {
        pub fn applicationDidFinishLaunching(self: *gen.NSValue, _: SEL, notification: *gen.NSNotification) callconv(.C) void {
            var delegate_instance_pointer: *DelegateType = @ptrCast(@alignCast(self.pointerValue()));

            delegate_instance_pointer.applicationDidFinishLaunching(notification);
        }

        pub fn applicationWillFinishLaunching(self: *gen.NSValue, _: SEL, notification: *gen.NSNotification) callconv(.C) void {
            var delegate_instance_pointer: *DelegateType = @ptrCast(@alignCast(self.pointerValue()));

            delegate_instance_pointer.applicationWillFinishLaunching(notification);
        }

        pub fn applicationShouldTerminateAfterLastWindowClosed(self: *gen.NSValue, _: SEL, notification: *gen.NSNotification) callconv(.C) bool {
            var delegate_instance_pointer: *DelegateType = @ptrCast(@alignCast(self.pointerValue()));

            return delegate_instance_pointer.applicationShouldTerminateAfterLastWindowClosed(notification);
        }
    };
}

pub const NSWindow = opaque {
    var class = CachedClass.init("NSWindow");
    var sel_initWithContentRectStyleMaskBackingDefer =
        CachedSelector.init("initWithContentRect:styleMask:backing:defer:");
    var sel_set_content_view = CachedSelector.init("setContentView:");
    var sel_make_key_and_order_front = CachedSelector.init("makeKeyAndOrderFront:");
    var sel_set_title = CachedSelector.init("setTitle:");
    var sel_close = CachedSelector.init("close");

    const Self = @This();
    pub usingnamespace gen.NSObjectProtocolMixin(Self, "NSWindow");
    pub usingnamespace gen.NSObjectInterfaceMixin(Self, "NSWindow");

    pub fn initWithContentRectStyleMaskBackingDefer(
        self: *Self,
        content_rect: gen.CGRect,
        style_mask: NSWindowStyleMask,
        backing: NSBackingStoreType,
        _defer: bool,
    ) *Self {
        return @as(*const fn (*Self, SEL, gen.CGRect, NSWindowStyleMask, NSBackingStoreType, bool) callconv(.C) *Self, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_initWithContentRectStyleMaskBackingDefer.get(), content_rect, style_mask, backing, _defer);
    }

    pub fn setContentView(self: *Self, content_view: id) void {
        return @as(*const fn (*Self, SEL, id) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_content_view.get(), content_view);
    }

    pub fn makeKeyAndOrderFront(self: *Self, sender: ?id) void {
        return @as(*const fn (*Self, SEL, ?id) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_make_key_and_order_front.get(), sender);
    }

    pub fn setTitle(self: *Self, title: *gen.NSString) void {
        return @as(*const fn (*Self, SEL, *gen.NSString) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_set_title.get(), title);
    }

    pub fn close(self: *Self) void {
        return @as(*const fn (*Self, SEL) callconv(.C) void, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_close.get());
    }
};

pub fn NSViewInterfaceMixin(comptime Self: type, comptime class_name: [*:0]const u8) type {
    return struct {
        var sel_init_with_frame = CachedSelector.init("initWithFrame:");
        var class = CachedClass.init(class_name);

        pub fn initWithFrame(self: *Self, frame: gen.CGRect) *Self {
            return @as(*const fn (*Self, SEL, gen.CGRect) callconv(.C) *Self, @ptrCast(&objc_msgSend))(@ptrCast(self), sel_init_with_frame.get(), frame);
        }
    };
}
