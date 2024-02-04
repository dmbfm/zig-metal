const std = @import("std");

// struct Block_literal_1 {
//     void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
//     int flags;
//     int reserved;
//     R (*invoke)(struct Block_literal_1 *, P...);
//     struct Block_descriptor_1 {
//         unsigned long int reserved;     // NULL
//         unsigned long int size;         // sizeof(struct Block_literal_1)
//         // optional helper functions
//         void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
//         void (*dispose_helper)(void *src);             // IFF (1<<25)
//         // required ABI.2010.3.16
//         const char *signature;                         // IFF (1<<30)
//     } *descriptor;
//     // imported variables
// };
//

extern const _NSConcreteStackBlock: opaque {};
extern const _NSConcreteGlobalBlock: opaque {};

pub fn BlockDescriptor(comptime BlockLiteral: type) type {
    return extern struct {
        reserved: c_ulong = 0,
        size: c_ulong = @intCast(@sizeOf(BlockLiteral)),
    };
}

pub fn BlockLiteralUserData1(comptime ReturnType: type, comptime T0: type, comptime UserData: type) type {
    return extern struct {
        isa: *anyopaque = @constCast(&_NSConcreteStackBlock),
        flags: c_int = 0,
        reserved: c_int = 0,
        invoke: *const fn (*Self, T0) callconv(.C) ReturnType = undefined,
        desc: *const BlockDescriptor(Self) = bd,
        external_fn: *const anyopaque = undefined,
        user_data: *UserData,

        const Self = @This();
        const bd = &BlockDescriptor(Self){};

        fn invoke(self: *Self, t0: T0) callconv(.C) ReturnType {
            const func: *const fn (*UserData, T0) ReturnType = @ptrCast(@alignCast(self.external_fn));
            return func(self.user_data, t0);
        }

        pub fn init(func: *const fn (*UserData, T0) ReturnType, user_data: *UserData) Self {
            return .{
                .invoke = &invoke,
                .external_fn = @ptrCast(func),
                .user_data = user_data,
            };
        }
    };
}
