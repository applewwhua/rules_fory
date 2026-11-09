"""Language specific code generation for `cc_fory_library` / `py_fory_library`."""

load("//fory:providers.bzl", "ForyCcInfo", "ForyInfo", "ForyPyInfo")
load("//fory/toolchains:foryc_toolchain.bzl", "foryc_tool_inputs")
load(
    "//fory/private:common.bzl",
    "FORYC_TOOL",
    "FORYC_TOOLCHAIN_TYPE",
    "CC_OUTPUT_DIR",
    "PY_OUTPUT_DIR",
    "merge_fory_infos",
    "module_name",
    "source_sort_key",
)

_LANG_SETTINGS = {
    "cpp": struct(directory = CC_OUTPUT_DIR, extension = ".h"),
    "python": struct(directory = PY_OUTPUT_DIR, extension = ".py"),
}

def _fory_codegen_impl(ctx):
    lang = ctx.attr.lang
    settings = _LANG_SETTINGS[lang]
    toolchain = ctx.toolchains[FORYC_TOOLCHAIN_TYPE]
    info = merge_fory_infos(ctx.attr.fory_deps)

    sources = sorted(info.transitive_sources.to_list(), key = source_sort_key)
    output_dir = "%s/%s" % (settings.directory, ctx.label.name)

    outputs = []
    outputs_by_module = {}
    for source in sources:
        module = module_name(source)
        if module in outputs_by_module:
            fail(
                "//%s:%s: %s and %s map to the same generated module %r; " +
                "rename one of the files" % (
                    ctx.label.package,
                    ctx.label.name,
                    outputs_by_module[module].short_path,
                    source.short_path,
                    module,
                ),
            )
        output = ctx.actions.declare_file("%s/%s%s" % (output_dir, module, settings.extension))
        outputs.append(output)
        outputs_by_module[module] = output

    args = ctx.actions.args()
    args.add("generate")
    args.add("--foryc", toolchain.foryc)
    args.add("--lang", lang)
    for root in sorted(info.import_roots.to_list()):
        args.add("--include", root)
    for source in sources:
        entry = "%s=%s" % (source.path, module_name(source))
        args.add("--module", entry)
        args.add("--source", entry)
        args.add("--output", "%s=%s" % (module_name(source), outputs_by_module[module_name(source)].path))

    ctx.actions.run(
        executable = ctx.executable._foryc_tool,
        arguments = [args],
        inputs = depset(
            direct = sources,
            transitive = [info.descriptor_sets],
        ),
        outputs = outputs,
        tools = [
            ctx.attr._foryc_tool[DefaultInfo].files_to_run,
        ] + foryc_tool_inputs(toolchain),
        mnemonic = "ForyCodegen",
        progress_message = "Generating Fory %s bindings for %s" % (lang, ctx.label),
    )

    providers = [DefaultInfo(files = depset(outputs))]
    if lang == "cpp":
        providers.append(ForyCcInfo(files = depset(outputs), include_dir = output_dir))
    else:
        providers.append(ForyPyInfo(files = depset(outputs), import_path = output_dir))
    return providers

fory_codegen = rule(
    implementation = _fory_codegen_impl,
    doc = """\
Internal rule that generates Python or C++ sources for the complete
transitive closure of a set of `fory_library` targets.

All modules of the closure are emitted into a single directory so that the
generated files can find each other without any include path bookkeeping.
""",
    attrs = {
        "fory_deps": attr.label_list(
            providers = [ForyInfo],
            allow_empty = True,
            doc = "`fory_library` targets that should be compiled.",
        ),
        "lang": attr.string(
            values = sorted(_LANG_SETTINGS.keys()),
            mandatory = True,
            doc = "Target language, `cpp` or `python`.",
        ),
        "_foryc_tool": attr.label(
            default = Label(FORYC_TOOL),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [FORYC_TOOLCHAIN_TYPE],
)
