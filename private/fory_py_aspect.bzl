"""Aspect that generates the Python modules of a `fory_library` exactly once.

Counterpart of `fory_cc_aspect` for Python: the aspect returns a `PyInfo` with
the generated modules of the schema and of its own `deps`, so a shared `.fdl`
file is turned into one Python module no matter how many libraries depend on it.
"""

load("@rules_python//python:py_info.bzl", "PyInfo")
load("//:providers.bzl", "ForyInfo")
load(
    "//private:common.bzl",
    "FORYC_TOOL",
    "PY_GEN_SUFFIX",
    "PY_OUTPUT_DIR",
    "import_root",
    "module_path",
    "run_codegen",
    "runfiles_dir",
)

def _fory_py_aspect_impl(_target, ctx):
    srcs = [
        file
        for src_target in ctx.rule.attr.srcs
        for file in src_target[DefaultInfo].files.to_list()
    ]
    dep_infos = [dep[ForyInfo] for dep in ctx.rule.attr.deps]
    closure = sorted(
        depset(
            direct = srcs,
            transitive = [info.transitive_sources for info in dep_infos],
        ).to_list(),
        key = lambda file: file.path,
    )
    import_roots = depset(
        direct = ["."] +
                 # Imports may be written relative to the declared import roots.
                 list(ctx.rule.attr.import_roots) +
                 [import_root(source) for source in srcs],
        transitive = [info.import_roots for info in dep_infos],
    )

    outputs = run_codegen(
        ctx = ctx,
        lang = "python",
        srcs = srcs,
        closure = closure,
        import_roots = import_roots,
        directory = PY_OUTPUT_DIR,
        name = ctx.label.name + PY_GEN_SUFFIX,
        output_path = module_path,
    )

    dep_py_infos = [dep[PyInfo] for dep in ctx.rule.attr.deps if PyInfo in dep]

    # The generated modules mirror the .fdl paths inside their output directory
    # and are imported by their dotted path ("a.b.pkg_fory"), so that directory
    # is the import root (PyInfo.imports holds runfiles paths).
    import_dirs = [
        runfiles_dir(ctx, outputs[0], module_path(srcs[0])),
    ] if outputs else []

    return [
        PyInfo(
            transitive_sources = depset(
                direct = outputs,
                transitive = [info.transitive_sources for info in dep_py_infos],
            ),
            imports = depset(
                direct = import_dirs,
                transitive = [info.imports for info in dep_py_infos],
            ),
            uses_shared_libraries = False,
        ),
        # Aspects below the top level may only set `files` on DefaultInfo; the
        # runfiles are assembled by the aggregating `py_library`.
        DefaultInfo(files = depset(direct = outputs)),
    ]

fory_py_aspect = aspect(
    implementation = _fory_py_aspect_impl,
    doc = """\
Generates the Python module of a single `fory_library` and exposes it as PyInfo.

Applied by `py_fory_library`, which only collects the resulting PyInfo of its
dependencies - every schema is therefore generated exactly once.
""",
    attr_aspects = ["deps"],
    attrs = {
        "_foryc_tool": attr.label(
            default = Label(FORYC_TOOL),
            executable = True,
            cfg = "exec",
        ),
    },
)
