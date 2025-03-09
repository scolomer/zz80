const std = @import("std");
const print = std.debug.print;

const Registers = struct { hl: u16 = 0, h: *u8 = undefined, l: *u8 = undefined, de: u16 = 0, d: *u8 = undefined, e: *u8 = undefined, bc: u16 = 0, b: *u8 = undefined, c: *u8 = undefined };

const Z80Error = error{ Overflow, UnknownOpcode, Unsupported };

const Z80 = struct {
    page0: []u8,
    main_register_set: *Registers,
    alt_register_set: *Registers,
    pc: u16 = 0,
    sp: u16 = 0,
    ix: u16 = 0,
    iy: u16 = 0,

    fn init(allocator: std.mem.Allocator) !Z80 {
        return .{ .page0 = try allocator.alloc(u8, 65536), .main_register_set = try initRegisters(allocator), .alt_register_set = try initRegisters(allocator) };
    }

    fn initRegisters(allocator: std.mem.Allocator) !*Registers {
        var mrs = try allocator.create(Registers);

        const hl: [*]u8 = @ptrCast(&mrs.hl);
        mrs.l = @ptrCast(hl);
        mrs.h = @ptrCast(hl + 1);
        mrs.hl = 0;

        const de: [*]u8 = @ptrCast(&mrs.de);
        mrs.e = @ptrCast(de);
        mrs.d = @ptrCast(de + 1);
        mrs.de = 0;

        const bc: [*]u8 = @ptrCast(&mrs.bc);
        mrs.c = @ptrCast(bc);
        mrs.b = @ptrCast(bc + 1);
        mrs.bc = 0;

        return mrs;
    }

    fn load(self: *Z80, addr: u16, buf: []const u8) !void {
        if (addr + buf.len > self.page0.len) {
            return Z80Error.Overflow;
        }

        for (0..buf.len) |i| {
            self.page0[addr + i] = buf[i];
        }
    }

    fn word(h: u8, l: u8) u16 {
        return @as(u16, h) << 8 | @as(u16, l);
    }

    fn call(self: *Z80, addr: u16) !void {
        self.pc = addr;

        while (self.page0[self.pc] != 0x76) {
            switch (self.page0[self.pc]) {
                0x01 => self.ld(&self.main_register_set.bc),
                0x11 => self.ld(&self.main_register_set.de),
                0x21 => self.ld(&self.main_register_set.hl),
                0x31 => self.ld(&self.sp),
                else => return error.UnknownOpcode,
            }

            switch (self.page0[self.pc]) {
                0x01, 0x11, 0x21, 0x31 => self.pc += 3,
                else => return error.UnknownOpcode,
            }
        }
    }

    fn ld(self: *Z80, r: *u16) void {
        r.* = word(self.page0[self.pc + 2], self.page0[self.pc + 1]);
    }

    fn printRegisters(self: *Z80) void {
        print("Main register set\n", .{});
        print("-----------------\n", .{});
        print("BC=0x{x}\n", .{self.main_register_set.bc});
        print("DE=0x{x}\n", .{self.main_register_set.de});
        print("HL=0x{x}\n\n", .{self.main_register_set.hl});
        print("Special purpose registers\n", .{});
        print("-------------------------\n", .{});
        print("SP=0x{x}\n", .{self.sp});
        print("PC=0x{x}\n", .{self.pc});
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var z80 = try Z80.init(allocator);
    try z80.load(0x1234, "ABCD");

    const pgm1 = [_]u8{ 0x21, 0x23, 0x01, 0x11, 0x56, 0x04, 0x01, 0x04, 0x00, 0x76 };
    // const pgm1 = [_]u8{ 0x01, 0x23, 0x01, 0x76 };
    try z80.load(0x1000, &pgm1);
    try z80.call(0x1000);

    z80.printRegisters();

    print("{x}", .{z80.main_register_set.b.*});
}
