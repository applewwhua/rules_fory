"""Implementation of `fory_library` (the counterpart of `proto_library`)."""

load("//:providers.bzl", "ForyInfo")
load(
    "//private:common.bzl",
    "FDL_EXTENSION",
    "header_path",
    "import_path",
    "import_root",
    "module_name",
    "source_sort_key",
)

def _check_import_roots(ctx):
    """Validates the `import_roots` attribute (extra import search roots)."""
    checked = []
    for root in ctx.attr.import_roots:
        segments = root.split("/")
        if (
            root.startswith("/") or
            root.endswith("/") or
            "//" in root or
            "." in segments or
            ".." in segments or
            "" in segments
        ):
            fail(
                "//%s:%s: import_roots entries must be workspace relative directory paths" % (
                    ctx.label.package,
                    ctx.label.name,
                ) + " (like `interfaces`), got %s" % root,
            )
        checked.append(root)
    return checked

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

    # Extra import search roots declared by the target: the directories the
    # `import` statements of its .fdl files are written against.  Multiple
    # roots are supported (foryc accepts repeated -I flags).
    own_import_roots = _check_import_roots(ctx)
    import_roots = depset(
        direct = ["."] +
                 own_import_roots +
                 [import_root(source) for source in sources],
        transitive = [info.import_roots for info in dep_infos],
    )

    descriptor = ctx.actions.declare_file(ctx.label.name + ".fory.json")
    descriptor_content = json.encode({
        "target": str(ctx.label),
        "own_import_roots": own_import_roots,
        "sources": [
            {
                "import_path": import_path(source),
                "header": header_path(source),
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
    args = ctx.actions.args()
    args.add("check")
    args.add("--lang", ctx.attr.check_lang)
    args.add("--descriptor", descriptor)
    args.add("--descriptor-content", descriptor_content)
    for root in sorted(import_roots.to_list()):
        args.add("--include", root)
    for source in sorted(transitive_sources.to_list(), key = source_sort_key):
        args.add("--closure", source.path)
    for source in sorted(sources, key = source_sort_key):
        args.add("--source", source.path)

    ctx.actions.run(
        executable = ctx.executable._foryc_tool,
        arguments = [args],
        inputs = transitive_sources,
        outputs = [descriptor],
        tools = [ctx.attr._foryc_tool[DefaultInfo].files_to_run],
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
`import "example/shared/shared.fdl";` works from any package.

Projects that keep their schemas in a dedicated directory tree can declare
that tree with `import_roots`: the `import` statements may then be written
relative to it (`import "shared/shared.fdl";`), keeping the `.fdl` sources
independent of where the tree lives in the workspace.  Multiple roots are
supported.
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
        "import_roots": attr.string_list(
            default = [],
            doc = """\
Workspace relative directories the `import` statements of the `.fdl` files
are written against (e.g. `["interfaces"]`).  Each entry is passed to foryc
as a `-I` search root; by default imports are resolved against the importing
file's directory and the workspace root.
""",
        ),
        "check_lang": attr.string(
            values = ["python", "cpp"],
            default = "python",
            doc = "Language generator used to validate the schemas.",
        ),
        "_foryc_tool": attr.label(
            default = Label("//tools:foryc_tool"),
            executable = True,
            cfg = "exec",
        ),
    },
)
