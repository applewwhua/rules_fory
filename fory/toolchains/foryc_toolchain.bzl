"""Toolchain that exposes the `foryc` compiler to the rules."""

def _foryc_toolchain_impl(ctx):
    # A compiler may be a plain file (locally installed `foryc` launcher) or an
    # executable rule such as a `py_binary` that wraps the `fory-compiler`
    # wheel.  In the latter case the runfiles of the compiler are needed to
    # run the generated launcher inside the sandbox.
    info = ctx.attr.foryc[DefaultInfo]
    files_to_run = info.files_to_run
    executable = files_to_run.executable if files_to_run else None

    if executable:
        foryc = executable
        foryc_runfiles = files_to_run
    else:
        files = info.files.to_list()
        if len(files) != 1:
            fail("%s must produce a single `foryc` executable, got %d files." % (
                ctx.attr.foryc.label,
                len(files),
            ))
        foryc = files[0]
        foryc_runfiles = None

    return [
        platform_common.ToolchainInfo(
            foryc = foryc,
            foryc_runfiles = foryc_runfiles,
            version_file = ctx.file.version_file,
        ),
    ]

def foryc_tool_inputs(toolchain):
    """Returns the action inputs required to run `toolchain.foryc`."""
    inputs = [toolchain.foryc]
    if toolchain.foryc_runfiles:
        inputs.append(toolchain.foryc_runfiles)
    return inputs

foryc_toolchain = rule(
    implementation = _foryc_toolchain_impl,
    doc = """\
Defines the `foryc` binary that is used for code generation.

Most users do not need to declare this rule themselves: rules_fory registers a
default toolchain that runs the `foryc` shipped by the pinned `fory-compiler`
wheel (`//fory/toolchains:foryc_pip_toolchain`).  A locally installed compiler is
available through `//fory/toolchains:local_foryc_toolchain`, which resolves `foryc` from
`foryc.configure(foryc = ...)`, `$FORYC` or `$PATH` (see
`//fory/toolchains:extensions.bzl`).  Declare this rule manually together with
`toolchain()` and `register_toolchains()` to pin a different compiler.
""",
    attrs = {
        "foryc": attr.label(
            mandatory = True,
            cfg = "exec",
            allow_files = True,
            doc = "Executable `foryc` compiler (a file or an executable rule).",
        ),
        "version_file": attr.label(
            allow_single_file = True,
            cfg = "exec",
            doc = "Optional file describing the compiler version.",
        ),
    },
)
