"""Makes a downloaded binary available to `bazel run`."""

def _prebuilt_binary_impl(ctx):
    # Bazel requires the executable to be a declared output.
    executable = ctx.actions.declare_file(
        "{}/{}".format(ctx.label.name, ctx.file.src.basename),
    )
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file.src,
        is_executable = True,
    )
    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
        runfiles = ctx.runfiles(files = [ctx.file.src, executable]),
    )]

prebuilt_binary = rule(
    doc = "Exposes a prebuilt binary as a target that `bazel run` accepts.",
    implementation = _prebuilt_binary_impl,
    executable = True,
    attrs = {
        "src": attr.label(
            doc = "The binary to run.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
