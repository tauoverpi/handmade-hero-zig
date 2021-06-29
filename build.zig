const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("handmade", "src/main.zig");
    exe.setTarget(.{ .os_tag = .windows });
    exe.linkage = .dynamic;
    exe.addPackagePath("win32", "third/zigwin32/win32.zig");
    exe.setBuildMode(mode);
    exe.linkSystemLibrary("user32");
    exe.enable_wine = true;
    exe.install();

    const run_cmd = b.addSystemCommand(&.{ "wine64", "zig-out/bin/handmade.exe" });
    run_cmd.step.dependOn(b.getInstallStep());
    //if (b.args) |args| {
    //   run_cmd.addArgs(args);
    //}

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
