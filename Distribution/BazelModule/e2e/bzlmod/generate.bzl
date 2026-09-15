"""Generated directory for the lint integration test."""

def _generated_directory_impl(ctx):
    output = ctx.actions.declare_directory("Sources/GeneratedTree")
    ctx.actions.run_shell(
        outputs = [output],
        arguments = [output.path],
        command = "mkdir -p \"$1\" && printf 'final class GeneratedTree {}\\n' > \"$1/GeneratedTree.swift\"",
    )
    return [DefaultInfo(files = depset([output]))]

generated_directory = rule(implementation = _generated_directory_impl)
