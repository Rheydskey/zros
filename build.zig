const std = @import("std");

const AsmPath = struct {
    path_file: []const u8,
    file_name: []const u8,
};

pub fn nasm_to(comptime file: AsmPath, exe: *std.Build.Step.Compile) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const output = "./zig-cache/nasm/" ++ file.file_name ++ ".o";
    var child = std.process.Child.init(&[_][]const u8{ "nasm", file.path_file, "-f", "elf64", "-w+all", "-Werror", "-o", output }, alloc.allocator());
    _ = try child.spawnAndWait();

    exe.addObjectFile(std.Build.LazyPath{ .path = output });
}

pub fn build(b: *std.Build) !void {
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

    const limine = b.dependency("limine", .{});

    const exe = b.addExecutable(.{ .name = "zros", .root_source_file = .{
        .path = "src/main.zig",
    }, .target = target, .optimize = optimize, .code_model = std.builtin.CodeModel.kernel });
    exe.pie = false;
    exe.linker_script = std.Build.LazyPath{ .path = "linker.ld" };
    exe.root_module.addImport("limine", limine.module("limine"));

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};

    try nasm_to(.{ .path_file = "./src/gdt/gdt.s", .file_name = "gdt" }, exe);

    try nasm_to(.{ .path_file = "./src/idt/idt.s", .file_name = "idt" }, exe);

    try nasm_to(.{ .path_file = "./src/idt/interrupt.s", .file_name = "interrupt" }, exe);

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
