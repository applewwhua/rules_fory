"""Implementation of `fory_library` (the counterpart of `proto_library`)."""

load("//fory:providers.bzl", "ForyInfo")
load(
    "//fory/private:common.bzl",
    "FDL_EXTENSION",
    "FORYC_TOOLCHAIN_TYPE",
    "import_path",
    "import_root",
    "module_name",
    "source_sort_key",
)

def _fory_library_impl(ctx):
    for source in ctx.files.srcs:
        if source.extension != FDL_EXTENSION:
            fail(
                "//%s:%s: only .%s sources are supported by fory_library, got %s" %
                (ctx.label.package, ctx.label.name, FDL_EXTENSION, source.short_path),
            )

    dep_infos = [dep[ForyInfo] for dep in ctx.attr.deps]
    sources = list(ctx.files.srcs)
    transitive_sources = depset(
        direct = sources,
        transitive = [info.transitive_sources for info in dep_infos],
    )
    import_roots = depset(
        direct = ["."] + [import_root(source) for source in sources],
        transitive = [info.import_roots for info in dep_infos],
    )

    descriptor = ctx.actions.declare_file(ctx.label.name + ".fory.json")
    descriptor_content = json.encode({
        "target": str(ctx.label),
        "sources": [
            {
                "import_path": import_path(source),
                "module": module_name(source),
                "path": source.short_path,
            }
            for source in sorted(sources, key = source_sort_key)
        ],
        "deps": sorted([str(dep) for dep in ctx.attr.deps]),
        "import_roots": sorted(import_roots.to_list()),
    })

    # Validation: run the compiler for one language and throw the output away.
    # This catches syntax errors, unresolved imports and duplicate packages of
    # the schema closure even when no language binding is built.  The action
    # produces the descriptor set, so it runs whenever the target (or any
    # language binding that depends on it) is built.
    toolchain = ctx.toolchains[FORYC_TOOLCHAIN_TYPE]
    args = ctx.actions.args()
    args.add("check")
    args.add("--foryc", toolchain.foryc)
    args.add("--lang", ctx.attr.check_lang)
    args.add("--descriptor", descriptor)
    args.add("--descriptor-content", descriptor_content)
    for root in sorted(import_roots.to_list()):
        args.add("--include", root)
    for source in sorted(sources, key = source_sort_key):
        args.add("--source", "%s=%s" % (source.path, module_name(source)))

    ctx.actions.run(
        executable = ctx.executable._foryc_tool,
        arguments = [args],
        inputs = transitive_sources,
        outputs = [descriptor],
        tools = [
            ctx.attr._foryc_tool[DefaultInfo].files_to_run,
            toolchain.foryc,
        ],
        mnemonic = "ForyCheck",
        progress_message = "Checking Fory schemas of %s" % ctx.label,
    )

    return [
        DefaultInfo(files = depset([descriptor])),
        ForyInfo(
            direct_sources = depset(sources),
            transitive_sources = transitive_sources,
            import_roots = import_roots,
            descriptor_set = descriptor,
            target_label = str(ctx.label),
        ),
    ]

fory_library = rule(
    implementation = _fory_library_impl,
    doc = """\
Describes a set of Fory IDL (`.fdl`) files.

`fory_library` does not generate any language specific code; it validates the
schemas, resolves the transitive closure of `deps` and exposes a `ForyInfo`
provider which `cc_fory_library` and `py_fory_library` consume.  It is the
direct counterpart of `proto_library`.

Import statements inside `.fdl` files are resolved relative to the importing
file first and relative to the workspace root afterwards, so
`import "examples/address.fdl";` works from any package.
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".fdl"],
            allow_empty = True,
            doc = "Fory IDL files (`.fdl`) that belong to this target.",
        ),
        "deps": attr.label_list(
            providers = [ForyInfo],
            allow_empty = True,
            doc = "Other `fory_library` targets whose schemas are imported.",
        ),
        "check_lang": attr.string(
            values = ["python", "cpp"],
            default = "python",
            doc = "Language generator used to validate the schemas.",
        ),
        "_foryc_tool": attr.label(
            default = Label("//fory/tools:foryc_tool"),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [FORYC_TOOLCHAIN_TYPE],
)
