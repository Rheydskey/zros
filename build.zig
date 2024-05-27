const std = @import("std");

pub fn get_git_version(b: *std.Build) []const u8 {
    const cmd = b.run(&[_][]const u8{ "git", "rev-parse", "HEAD" });
    return cmd[0..6];
}

const AsmPath = struct {
    path_file: []const u8,
    file_name: []const u8,
};

pub fn nasm_to(comptime file: AsmPath, exe: *std.Build.Step.Compile) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const output = "./zig-cache/nasm/" ++ file.file_name ++ ".o";
    var child = std.process.Child.init(&[_][]const u8{ "nasm", file.path_file, "-f", "elf64", "-o", output }, alloc.allocator());
    _ = try child.spawnAndWait();

    exe.addObjectFile(std.Build.LazyPath{ .cwd_relative = output });
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();

    build_options.addOption(bool, "release_mode", optimize != .Debug);
    build_options.addOption([]const u8, "git_version", get_git_version(b));
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

    const limine = b.dependency("limine_zig", .{});

    const exe = b.addExecutable(.{
        .name = "zros",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = std.builtin.CodeModel.kernel,
    });

    exe.linkage = .static;
    exe.pie = false;

    exe.linker_script = b.path("linker.ld");
    exe.root_module.addImport("limine", limine.module("limine"));
    exe.root_module.addOptions("build_options", build_options);

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};

    try nasm_to(.{ .path_file = "./src/gdt/gdt.s", .file_name = "gdt" }, exe);

    try nasm_to(.{ .path_file = "./src/idt/idt.s", .file_name = "idt" }, exe);

    try nasm_to(.{ .path_file = "./src/idt/interrupt.s", .file_name = "interrupt" }, exe);

    b.installArtifact(exe);
}
