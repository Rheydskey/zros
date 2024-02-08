const std = @import("std");

pub fn nasm_to(asm_file: []const u8, target_path: []const u8) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var child = std.process.Child.init(&[_][]const u8{ "nasm", asm_file, "-f", "elf64", "-w+all", "-Werror", "-o", target_path }, alloc.allocator());
    _ = try child.spawnAndWait();
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    var cross =
        std.zig.CrossTarget{
        .cpu_arch = std.Target.Cpu.Arch.x86_64,
        .os_tag = .freestanding,
        .abi = std.Target.Abi.none,
    };
    const x86features = std.Target.x86.Feature;
    cross.cpu_features_add.addFeature(@intFromEnum(x86features.soft_float));
    cross.cpu_features_sub.addFeature(@intFromEnum(x86features.mmx));
    cross.cpu_features_sub.addFeature(@intFromEnum(x86features.sse));
    cross.cpu_features_sub.addFeature(@intFromEnum(x86features.sse2));
    cross.cpu_features_sub.addFeature(@intFromEnum(x86features.avx));
    cross.cpu_features_sub.addFeature(@intFromEnum(x86features.avx2));

    const target = b.resolveTargetQuery(cross);

    const exe = b.addExecutable(.{ .name = "zros", .root_source_file = .{
        .path = "src/main.zig",
    }, .target = target, .optimize = optimize, .code_model = std.builtin.CodeModel.kernel });
    exe.pie = false;
    exe.linker_script = std.Build.LazyPath{ .path = "linker.ld" };

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};

    nasm_to("./src/gdt/gdt.s", "./zig-cache/nasm/gdt.o") catch |err| {
        std.log.err("{}", .{err});
        return;
    };

    nasm_to("./src/idt/idt.s", "./zig-cache/nasm/idt.o") catch |err| {
        std.log.err("{}", .{err});
        return;
    };

    nasm_to("./src/idt/interrupt.s", "./zig-cache/nasm/interrupt.o") catch |err| {
        std.log.err("{}", .{err});
        return;
    };

    exe.addObjectFile(std.Build.LazyPath{ .path = "./zig-cache/nasm/gdt.o" });
    exe.addObjectFile(std.Build.LazyPath{ .path = "./zig-cache/nasm/idt.o" });
    exe.addObjectFile(std.Build.LazyPath{ .path = "./zig-cache/nasm/interrupt.o" });

    b.installArtifact(exe);

    const unittarget = b.resolveTargetQuery(std.zig.CrossTarget{
        .cpu_arch = std.Target.Cpu.Arch.x86_64,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.x86.cpu.znver1 },
        .os_tag = .freestanding,
        .abi = std.Target.Abi.none,
    });

    const unit_tests = b.addTest(.{ .root_source_file = .{ .path = "src/main.zig" }, .target = unittarget, .optimize = optimize });

    unit_tests.linker_script = std.Build.LazyPath{ .path = "linker.ld" };

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
