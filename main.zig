const std = @import("std");
const print = std.debug.print;

const Registers = struct { hl: u16 = 0, h: *u8 = undefined, l: *u8 = undefined, de: u16 = 0, d: *u8 = undefined, e: *u8 = undefined, bc: u16 = 0, b: *u8 = undefined, c: *u8 = undefined, af: u16 = 0, a: *u8 = undefined, f: *u8 = undefined };

const Z80Error = error{ Overflow, UnknownOpcode, Unsupported };

pub const Z80 = struct {
    const c_mask: u8 = 0b00000001;
    const n_mask: u8 = 0b00000010;
    const pv_msk: u8 = 0b00000100;
    const h_mask: u8 = 0b00010000;
    const z_mask: u8 = 0b01000000;
    const s_mask: u8 = 0b10000000;

    page0: []u8,
    main_register_set: *Registers,
    alt_register_set: *Registers,
    pc: u16 = 0,
    sp: u16 = 0,
    ix: u16 = 0,
    iy: u16 = 0,

    pub fn init(allocator: std.mem.Allocator) !Z80 {
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

        const af: [*]u8 = @ptrCast(&mrs.af);
        mrs.f = @ptrCast(af);
        mrs.a = @ptrCast(af + 1);
        mrs.af = 0;

        return mrs;
    }

    pub fn load(self: *Z80, addr: u16, buf: []const u8) !void {
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

    pub fn call(self: *Z80, addr: u16) !void {
        self.pc = addr;

        while (self.page0[self.pc] != 0x76) {
            switch (self.page0[self.pc]) {
                0x01 => self.ld(&self.main_register_set.bc),
                0x11 => self.ld(&self.main_register_set.de),
                0x21 => self.ld(&self.main_register_set.hl),
                0x31 => self.ld(&self.sp),
                0xED => {
                    switch (self.page0[self.pc + 1]) {
                        0xB0 => self.ldir(),
                        else => return error.UnknownOpcode,
                    }
                },
                0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E => self.ldu8(),
                0x40...0x45, 0x47...0x4D, 0x4F...0x55, 0x57...0x5D, 0x5F...0x65, 0x67...0x6D, 0x6F => self.ldr(),
                0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x7E => self.ldrihl(),
                else => return error.UnknownOpcode,
            }
        }
    }

    fn ld(self: *Z80, r: *u16) void {
        r.* = word(self.page0[self.pc + 2], self.page0[self.pc + 1]);
        self.pc += 3;
    }

    fn ldu8(self: *Z80) void {
        const mrs = self.main_register_set;
        const pr: [8]*u8 = .{ mrs.b, mrs.c, mrs.d, mrs.e, mrs.h, mrs.l, undefined, mrs.a };
        const r = pr[self.page0[self.pc] >> 3];
        r.* = self.page0[self.pc + 1];
        self.pc += 2;
    }

    fn ldr(self: *Z80) void {
        const op = self.page0[self.pc];

        const mrs = self.main_register_set;
        const prf: [8]*u8 = .{ mrs.b, mrs.c, mrs.d, mrs.e, mrs.f, mrs.l, undefined, mrs.a };
        const rf = prf[op & 0b111];
        const prt: [8]*u8 = .{ mrs.b, mrs.c, mrs.d, mrs.e, mrs.h, mrs.l, undefined, mrs.a };
        const rt = prt[(op >> 3) & 0b111];
        rt.* = rf.*;
        self.pc += 1;
    }

    fn ldrihl(self: *Z80) void {
        const op = self.page0[self.pc];
        const mrs = self.main_register_set;
        const prt: [8]*u8 = .{ mrs.b, mrs.c, mrs.d, mrs.e, mrs.h, mrs.l, undefined, mrs.a };
        const rt = prt[(op >> 3) & 0b111];
        rt.* = self.page0[mrs.hl];
        self.pc += 1;
    }

    fn ldir(self: *Z80) void {
        var r = self.main_register_set;

        while (true) {
            self.page0[r.de] = self.page0[r.hl];
            r.de += 1;
            r.hl += 1;
            r.bc -= 1;
            if (r.bc == 0) break;
        }
        self.resetH();
        self.pc += 2;
    }

    fn resetH(self: *Z80) void {
        self.main_register_set.h.* &= ~h_mask;
    }

    pub fn printRegisters(self: *Z80) void {
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

test "Test LD rr,nn" {
    var z = try Z80.init(std.heap.page_allocator);
    const pgm1 = [_]u8{ 0x21, 0x23, 0x01, 0x11, 0x56, 0x04, 0x01, 0x04, 0x00, 0x76 };
    try z.load(0x1000, &pgm1);
    try z.call(0x1000);

    try std.testing.expectEqual(0x123, z.main_register_set.hl);
    try std.testing.expectEqual(0x456, z.main_register_set.de);
    try std.testing.expectEqual(4, z.main_register_set.bc);
}

test "Test LD r,n" {
    var z = try Z80.init(std.heap.page_allocator);
    const pgm1 = [_]u8{ 0x3E, 0x01, 0x06, 0x02, 0x0E, 0x03, 0x16, 0x04, 0x1E, 0x05, 0x26, 0x06, 0x2E, 0x07, 0x76 };
    try z.load(0x1000, &pgm1);
    try z.call(0x1000);

    try std.testing.expectEqual(0x1, z.main_register_set.a.*);
    try std.testing.expectEqual(0x2, z.main_register_set.b.*);
    try std.testing.expectEqual(0x3, z.main_register_set.c.*);
    try std.testing.expectEqual(0x4, z.main_register_set.d.*);
    try std.testing.expectEqual(0x5, z.main_register_set.e.*);
    try std.testing.expectEqual(0x6, z.main_register_set.h.*);
    try std.testing.expectEqual(0x7, z.main_register_set.l.*);
}

test "Test LD r,r" {
    var z = try Z80.init(std.heap.page_allocator);
    const pgm1 = [_]u8{ 0x47, 0x48, 0x51, 0x5A, 0x63, 0x6B, 0x76 };
    try z.load(0x1000, &pgm1);

    z.main_register_set.a.* = 0x89;
    try z.call(0x1000);

    try std.testing.expectEqual(0x89, z.main_register_set.b.*);
    try std.testing.expectEqual(0x89, z.main_register_set.c.*);
    try std.testing.expectEqual(0x89, z.main_register_set.d.*);
    try std.testing.expectEqual(0x89, z.main_register_set.e.*);
    try std.testing.expectEqual(0x89, z.main_register_set.h.*);
    try std.testing.expectEqual(0x89, z.main_register_set.l.*);
}

test "Test LD r,(hl)" {
    var z = try Z80.init(std.heap.page_allocator);
    const pgm1 = [_]u8{ 0x4E, 0x76 };
    try z.load(0x1000, &pgm1);

    z.page0[0x75A1] = 0x58;
    z.main_register_set.hl = 0x75A1;

    try z.call(0x1000);
    try std.testing.expectEqual(0x58, z.main_register_set.c.*);
}

test "Test LDIR" {
    var z = try Z80.init(std.heap.page_allocator);
    const pgm1 = [_]u8{ 0x21, 0x34, 0x12, 0x11, 0x67, 0x45, 0x01, 0x04, 0x00, 0xED, 0xB0, 0x76 };
    try z.load(0x1234, "ABCD");
    try z.load(0x1000, &pgm1);

    try z.call(0x1000);

    try std.testing.expectEqualStrings("ABCD", z.page0[0x4567..0x456B]);
}
