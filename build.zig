const std = @import("std");

pub fn get_git_version(b: *std.Build) []const u8 {
    const cmd = b.run(&[_][]const u8{ "git", "rev-parse", "HEAD" });
    return cmd[0..6];
}

const AsmPath = struct {
    path_file: []const u8,
    file_name: []const u8,
};

pub fn nasm_to(b: *std.Build, comptime file: AsmPath, exe: *std.Build.Step.Compile) !void {
    const output = "./zig-cache/nasm/" ++ file.file_name ++ ".o";

    _ = b.run(&[_][]const u8{ "nasm", file.path_file, "-f", "elf64", "-o", output });

    exe.addObjectFile(std.Build.LazyPath{ .cwd_relative = output });
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();

    build_options.addOption(bool, "release_mode", optimize != .Debug);
    build_options.addOption([]const u8, "git_version", get_git_version(b));

    var cross =
        std.Target.Query{
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

    const limine = b.dependency("limine_zig", .{});

    const exe = b.addExecutable(.{
        .name = "zros",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = std.builtin.CodeModel.kernel,
        .linkage = .static,
        .use_llvm = true,
    });

    exe.pie = false;
    exe.want_lto = false;

    exe.linker_script = b.path("meta/linker.ld");
    exe.root_module.addImport("limine", limine.module("limine"));
    exe.root_module.addOptions("build_options", build_options);

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};

    try nasm_to(b, .{ .path_file = "./src/arch/x86/gdt/gdt.s", .file_name = "gdt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/idt/idt.s", .file_name = "idt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/idt/interrupt.s", .file_name = "interrupt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/syscall.s", .file_name = "syscall" }, exe);

    b.installArtifact(exe);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("limine", limine.module("limine"));
    exe_unit_tests.root_module.addOptions("build_options", build_options);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
