"""Run architectural rules as a cacheable Bazel build action."""

load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory_bin_action")
load("@bazel_lib//lib:paths.bzl", "to_repository_relative_path")

_COPY_TOOLCHAIN = Label("@bazel_lib//lib:copy_to_directory_toolchain_type")

def _check_input_paths(files):
    by_path = {}
    for file in files:
        path = to_repository_relative_path(file)
        if path in by_path:
            fail("bylaws_lint must have separate input paths: '{}' and '{}' both use '{}'. Rename one input before passing it to the target.".format(by_path[path].path, file.path, path))
        by_path[path] = file
    for path in by_path:
        parts = path.split("/")
        for length in range(1, len(parts)):
            parent = "/".join(parts[:length])
            if parent in by_path:
                fail("bylaws_lint must have separate input paths: '{}' is inside '{}'. Give the generated directory its own path before passing it to the target.".format(path, parent))

def _bylaws_lint_impl(ctx):
    project = ctx.actions.declare_directory(ctx.label.name + ".sources")
    report = ctx.actions.declare_file(ctx.label.name + ".json")
    files = depset(ctx.files.srcs + ctx.files.rules + ctx.files.data + ctx.files.baseline).to_list()
    _check_input_paths(files)

    copy_to_directory_bin_action(
        ctx,
        name = ctx.label.name,
        dst = project,
        copy_to_directory_bin = ctx.toolchains[_COPY_TOOLCHAIN].copy_to_directory_info.bin,
        files = files,
        root_paths = [],
        include_external_repositories = ["**"],
    )

    args = ctx.actions.args()
    args.add_all(["lint", "--source-only", "--format", "json"])
    args.add("--root", project.path)
    args.add("--output", report)
    if ctx.files.rules:
        args.add("--rules")
        args.add_all(ctx.files.rules, map_each = to_repository_relative_path)
    if ctx.file.baseline:
        args.add("--baseline", to_repository_relative_path(ctx.file.baseline))
    if ctx.attr.strict:
        args.add("--strict")
    if ctx.attr.selection_cache_size:
        args.add("--selection-cache-size", ctx.attr.selection_cache_size)

    ctx.actions.run(
        executable = ctx.attr.bylaws[DefaultInfo].files_to_run,
        inputs = [project],
        outputs = [report],
        arguments = [args],
        mnemonic = "BylawsLint",
        progress_message = "Checking architectural rules for %{label}",
    )
    return [DefaultInfo(files = depset([report]))]

bylaws_lint = rule(
    implementation = _bylaws_lint_impl,
    doc = "Checks the declared files and produces a JSON report. Enforced violations fail the build.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Source files and generated files or directories that the rules check.",
        ),
        "rules": attr.label_list(
            allow_files = [".swift"],
            doc = "Rules to run. When omitted, Bylaws discovers Bylaws.swift files among the inputs.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Other files read by the rules, such as manifests, shared rules and baselines.",
        ),
        "baseline": attr.label(
            allow_single_file = [".swift"],
            doc = "A baseline to apply instead of discovering baselines among the inputs.",
        ),
        "strict": attr.bool(
            doc = "Fail the build on advisory violations too.",
        ),
        "selection_cache_size": attr.string(
            doc = "Memory budget for retained query selections, using CLI size units such as '32MiB'. Empty uses the CLI default. Set '0' to disable selection reuse.",
        ),
        "bylaws": attr.label(
            default = Label("//:bylaws"),
            executable = True,
            cfg = "exec",
            doc = "The Bylaws executable. Defaults to the tool supplied by this module.",
        ),
    },
    toolchains = [_COPY_TOOLCHAIN],
)
