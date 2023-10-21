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

pub fn BlockDescriptor(comptime BlockLiteral: type) type {
    return extern struct {
        reserved: c_long = 0,
        size: c_long = @intCast(@sizeOf(BlockLiteral)),
        copy_helper: [*c]u8 = null,
        dispose_helper: [*c]u8 = null,
        signature: [*c]u8 = null,
    };
}

pub fn BlockLiteral1(comptime ReturnType: type, comptime T0: type) type {
    return extern struct {
        isa: *opaque {} = &_NSConcreteStackBlock,
        flags: c_int = 0,
        reservec: c_int = 0,
        invoke: *const fn (*Self, T0) callconv(.C) ReturnType = undefined,
        desc: *BlockDescriptor = &bd,

        const Self = @This();
        const BD = BlockDescriptor(Self);
        const bd = &BD{};
    };
}

pub fn BlockLiteral2(comptime ReturnType: type, comptime T0: type, comptime T1: type) type {
    return extern struct {
        isa: [*c]u8 = @ptrCast(&_NSConcreteStackBlock),
        flags: c_int = 0,
        reservec: c_int = 0,
        invoke: *const fn (*Self, T0, T1) callconv(.C) ReturnType = undefined,
        desc: [*c]u8 = @constCast(@ptrCast(&bd)),
        external_fn: *const fn (T0, T1) ReturnType,

        const Self = @This();
        const BD = BlockDescriptor(Self);
        const bd = &BD{};

        fn invoke(self: *Self, t0: T0, t1: T1) callconv(.C) ReturnType {
            return self.external_fn(t0, t1);
        }

        pub fn init(func: *const fn (T0, T1) ReturnType) Self {
            return .{
                .invoke = &invoke,
                .external_fn = func,
            };
        }
    };
}

pub fn BlockLiteralUserData2(comptime ReturnType: type, comptime T0: type, comptime T1: type, comptime UserData: type) type {
    return extern struct {
        isa: [*c]u8 = @ptrCast(&_NSConcreteStackBlock),
        flags: c_int = 0,
        reservec: c_int = 0,
        invoke: *const fn (*Self, T0, T1) callconv(.C) ReturnType = undefined,
        desc: [*c]u8 = @constCast(@ptrCast(&bd)),
        external_fn: *const fn (*UserData, T0, T1) ReturnType,
        user_data: *UserData,

        const Self = @This();
        const BD = BlockDescriptor(Self);
        const bd = &BD{};

        fn invoke(self: *Self, t0: T0, t1: T1) callconv(.C) ReturnType {
            return self.external_fn(self.user_data, t0, t1);
        }

        pub fn init(func: *const fn (*UserData, T0, T1) ReturnType, user_data: *UserData) Self {
            return .{
                .invoke = &invoke,
                .external_fn = func,
                .user_data = user_data,
            };
        }
    };
}

pub fn create_block_literal_2(
    comptime ReturnType: type,
    comptime T0: type,
    comptime T1: type,
    func: *const fn (T0, T1) ReturnType,
) BlockLiteralUserData2(ReturnType, T0, T1, void) {
    return BlockLiteralUserData2(ReturnType, T0, T1, void).init(func, null);
}

pub fn BlockLiteral3(comptime ReturnType: type, comptime T0: type, comptime T1: type, comptime T2: type) type {
    return extern struct {
        isa: *opaque {} = &_NSConcreteStackBlock,
        flags: c_int = 0,
        reservec: c_int = 0,
        invoke: *const fn (*Self, T0, T1, T2) callconv(.C) ReturnType = undefined,
        desc: *BlockDescriptor = &bd,

        const Self = @This();
        const BD = BlockDescriptor(Self);
        const bd = &BD{};
    };
}
