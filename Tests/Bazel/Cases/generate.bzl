"""Generated source inputs for the lint integration tests."""

def _overlapping_directory_impl(ctx):
    directory = ctx.actions.declare_directory("Sources")
    ctx.actions.run_shell(
        outputs = [directory],
        arguments = [directory.path],
        command = "mkdir -p \"$1\" && printf 'final class Other {}\\n' > \"$1/Model.swift\"",
    )
    return [DefaultInfo(files = depset([directory]))]

overlapping_directory = rule(implementation = _overlapping_directory_impl)

def _generated_directory_impl(ctx):
    output = ctx.actions.declare_directory("Sources/GeneratedTree")
    ctx.actions.run_shell(
        inputs = [ctx.file.src],
        outputs = [output],
        arguments = [ctx.file.src.path, output.path],
        command = "mkdir -p \"$2\" && cp \"$1\" \"$2/GeneratedTree.swift\"",
    )
    return [DefaultInfo(files = depset([output]))]

generated_directory = rule(
    implementation = _generated_directory_impl,
    attrs = {"src": attr.label(allow_single_file = True, mandatory = True)},
)
