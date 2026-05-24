const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_zgpu = b.dependency("zgpu", .{
        .target = target,
        .optimize = optimize,
    });

    const zgpu_mod = dep_zgpu.module("root");

    const engine_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zgpu", .module = zgpu_mod },
        },
    });

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/game/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "engine", .module = engine_mod },
        },
    });

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "engine", .module = engine_mod },
            .{ .name = "game", .module = game_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "taucet",
        .root_module = main_mod,
    });

    @import("zgpu").addLibraryPathsTo(exe);
    exe.root_module.linkLibrary(dep_zgpu.artifact("zdawn"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run taucet");
    run_step.dependOn(&run_cmd.step);
}

