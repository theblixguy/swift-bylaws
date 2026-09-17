"""Run architectural rules as a cacheable Bazel build action."""

load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory_bin_action")
load("@bazel_lib//lib:paths.bzl", "to_repository_relative_path")

_COPY_TOOLCHAIN = Label("@bazel_lib//lib:copy_to_directory_toolchain_type")

def _repository_path(file):
    return to_repository_relative_path(file)

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

def _is_discovered_rule(file):
    return file.basename == "Bylaws.swift"

def _append_regular_batches(batches, files, sources_per_action):
    for start in range(0, len(files), sources_per_action):
        batches.append(files[start:start + sources_per_action])

def _parse_batches(srcs, sources_per_action):
    batches = []
    loose_files = []
    seen_paths = {}
    for target in srcs:
        files = []
        for file in sorted(target[DefaultInfo].files.to_list(), key = _repository_path):
            path = to_repository_relative_path(file)
            if path not in seen_paths:
                seen_paths[path] = True
                files.append(file)
        if len(files) == 1 and not files[0].is_directory:
            loose_files.append(files[0])
            continue
        _append_regular_batches(batches, loose_files, sources_per_action)
        loose_files = []
        regular_files = []
        for file in files:
            if file.is_directory:
                batches.append([file])
            else:
                regular_files.append(file)
        _append_regular_batches(batches, regular_files, sources_per_action)
    _append_regular_batches(batches, loose_files, sources_per_action)
    return batches

def _parse_sources(ctx):
    outputs = []
    batches = _parse_batches(ctx.attr.srcs, ctx.attr.sources_per_parse_action)
    for index, batch in enumerate(batches if batches else [[]]):
        output = ctx.actions.declare_file(
            "{}.parsed/{}.pack".format(ctx.label.name, index),
        )
        args = ctx.actions.args()
        args.add("parse-sources")
        for source in batch:
            args.add("--input", source.path)
            args.add("--path", to_repository_relative_path(source))
        args.add("--swift-language-mode", ctx.attr.swift_language_mode)
        args.add("--output", output)
        ctx.actions.run(
            executable = ctx.attr.bylaws[DefaultInfo].files_to_run,
            inputs = batch,
            outputs = [output],
            arguments = [args],
            mnemonic = "BylawsParse",
            progress_message = "Parsing Swift sources for %{label}",
        )
        outputs.append(output)
    return outputs

def _project_files(ctx):
    files = ctx.files.rules + ctx.files.data + ctx.files.baseline
    if not ctx.files.rules:
        files += [
            file
            for file in ctx.files.srcs
            if file.is_directory or _is_discovered_rule(file)
        ]
    return depset(files).to_list()

def _bylaws_lint_impl(ctx):
    if ctx.attr.sources_per_parse_action <= 0:
        fail("sources_per_parse_action must be greater than zero.")
    project = ctx.actions.declare_directory(ctx.label.name + ".sources")
    report = ctx.actions.declare_file(ctx.label.name + ".json")
    files = depset(ctx.files.srcs + ctx.files.rules + ctx.files.data + ctx.files.baseline).to_list()
    _check_input_paths(files)
    parsed_sources = _parse_sources(ctx)
    project_files = _project_files(ctx)

    copy_to_directory_bin_action(
        ctx,
        name = ctx.label.name,
        dst = project,
        copy_to_directory_bin = ctx.toolchains[_COPY_TOOLCHAIN].copy_to_directory_info.bin,
        files = project_files,
        root_paths = [],
        include_external_repositories = ["**"],
    )

    args = ctx.actions.args()
    args.add_all(["lint", "--source-only", "--format", "json"])
    args.add("--root", project.path)
    args.add("--output", report)
    args.add("--parsed-sources")
    args.add_all(parsed_sources)
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
        inputs = [project] + parsed_sources,
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
        "sources_per_parse_action": attr.int(
            default = 512,
            doc = "Maximum number of source files in one parse action.",
        ),
        "swift_language_mode": attr.string(
            default = "6",
            values = ["4", "5", "6"],
            doc = "The Swift language mode used to parse source files.",
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
