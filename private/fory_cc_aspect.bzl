"""Aspect that generates the C++ headers of a `fory_library` exactly once.

The aspect is applied to every `fory_library` that a `cc_fory_library` depends
on and returns a `CcInfo` with the headers of that schema (plus the ones of its
own `deps`).  This is how `rules_proto` implements `cc_proto_library`: the code
generation lives next to the schema, not in every consumer, so a shared `.fdl`
file is compiled once no matter how many targets depend on it.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//:providers.bzl", "ForyInfo")
load(
    "//private:common.bzl",
    "CC_GEN_SUFFIX",
    "CC_OUTPUT_DIR",
    "FORYC_TOOL",
    "execroot_dir",
    "header_path",
    "import_root",
    "merge_compilation_contexts",
    "run_codegen",
)

def _fory_cc_aspect_impl(_target, ctx):
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
        lang = "cpp",
        srcs = srcs,
        closure = closure,
        import_roots = import_roots,
        directory = CC_OUTPUT_DIR,
        name = ctx.label.name + CC_GEN_SUFFIX,
        output_path = header_path,
    )

    # Own headers plus the compilation context of the closure.  The generated
    # headers mirror the .fdl paths inside their output directory, so that
    # directory is the include root of `#include "a/b/pkg.fory.h"`.
    own = cc_common.create_compilation_context(
        headers = depset(direct = outputs),
        quote_includes = depset(
            direct = [execroot_dir(outputs[0], header_path(srcs[0]))] if outputs else [],
        ),
    )
    dep_contexts = [
        dep[CcInfo].compilation_context
        for dep in ctx.rule.attr.deps
        if CcInfo in dep
    ]
    return [
        CcInfo(compilation_context = merge_compilation_contexts([own] + dep_contexts)),
        DefaultInfo(files = depset(direct = outputs)),
    ]

fory_cc_aspect = aspect(
    implementation = _fory_cc_aspect_impl,
    doc = """\
Generates the C++ header of a single `fory_library` and exposes it as CcInfo.

Applied by `cc_fory_library`, which only collects the resulting CcInfo of its
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
