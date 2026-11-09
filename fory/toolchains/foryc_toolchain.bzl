"""Toolchain that exposes the `foryc` compiler to the rules."""

def _foryc_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            foryc = ctx.file.foryc,
            version_file = ctx.file.version_file,
        ),
    ]

foryc_toolchain = rule(
    implementation = _foryc_toolchain_impl,
    doc = """\
Defines the `foryc` binary that is used for code generation.

Most users do not need to declare this rule themselves: rules_fory registers a
default toolchain that resolves `foryc` from `$FORYC` or from `$PATH` (see
`//fory/toolchains:extensions.bzl`).  Declare it manually together with
`toolchain()` and `register_toolchains()` to pin a hermetic compiler.
""",
    attrs = {
        "foryc": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "Executable `foryc` compiler.",
        ),
        "version_file": attr.label(
            allow_single_file = True,
            cfg = "exec",
            doc = "Optional file describing the compiler version.",
        ),
    },
)
