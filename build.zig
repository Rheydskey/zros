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

    exe.root_module.addObjectFile(std.Build.LazyPath{ .cwd_relative = output });
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const io = std.Io.Threaded.global_single_threaded;

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

    const module = b.addModule("zros", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = std.builtin.CodeModel.kernel,
    });

    const exe = b.addExecutable(.{
        .name = "zros",
        .root_module = module,
        .linkage = .static,
        .use_llvm = true,
    });

    exe.pie = false;
    exe.lto = .none;

    // exe.bundle_compiler_rt = false;
    exe.linker_script = b.path("meta/linker.ld");
    exe.root_module.addImport("limine", limine.module("limine"));
    exe.root_module.addOptions("build_options", build_options);

    std.Io.Dir.cwd().createDir(io.io(), "./zig-cache/nasm", .default_dir) catch {};
    // std.fs.cwd().makePath("./zig-cache/nasm") catch {};

    try nasm_to(b, .{ .path_file = "./src/arch/x86/gdt/gdt.s", .file_name = "gdt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/idt/idt.s", .file_name = "idt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/idt/interrupt.s", .file_name = "interrupt" }, exe);

    try nasm_to(b, .{ .path_file = "./src/arch/x86/syscall.s", .file_name = "syscall" }, exe);

    b.installArtifact(exe);

    // ===================================

    const test_mod = b.addModule("zros_test", .{
        .root_source_file = b.path("tests/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });

    mod_tests.root_module.addImport("zros", exe.root_module);
    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // // Creates an executable that will run `test` blocks from the executable's
    // // root module. Note that test executables only test one module at a time,
    // // hence why we have to create two separate ones.
    // const test_exe_tests = b.addTest(.{
    //     .root_module = mod_tests.root_module,
    // });

    // // A run step that will run the second test executable.
    // const run_exe_tests = b.addRunArtifact(test_exe_tests);

    // // A top level step for running all tests. dependOn can be called multiple
    // // times and since the two run steps do not depend on one another, this will
    // // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);
}
