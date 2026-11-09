"""Analysis phase tests for rules_fory (run with `bazel test`)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:defs.bzl", "CcInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("//fory:providers.bzl", "ForyInfo")
load("//fory/private:common.bzl", "module_name")

def _fory_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    info = target[ForyInfo]

    asserts.equals(env, 1, len(info.direct_sources.to_list()), "direct sources")
    asserts.equals(env, 2, len(info.transitive_sources.to_list()), "transitive sources")

    modules = sorted([module_name(source) for source in info.transitive_sources.to_list()])
    asserts.equals(
        env,
        ["examples_fdl_address", "examples_fdl_person"],
        modules,
        "module names",
    )

    import_paths = sorted([source.short_path for source in info.transitive_sources.to_list()])
    asserts.equals(
        env,
        [
            "examples/fdl/address.fdl",
            "examples/fdl/person.fdl",
        ],
        import_paths,
        "schema paths",
    )

    asserts.true(
        env,
        "." in info.import_roots.to_list(),
        "the workspace root must be an import root",
    )
    asserts.true(
        env,
        info.descriptor_set.basename.endswith(".fory.json"),
        "descriptor set name",
    )
    return analysistest.end(env)

fory_info_test = analysistest.make(_fory_info_test_impl)

def _cc_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    cc_info = target[CcInfo]

    includes = cc_info.compilation_context.includes.to_list()
    asserts.true(
        env,
        any(["examples/fdl/_fory_cc/_person_cc_fory_gen" in include for include in includes]),
        "generated include directory is missing, got %s" % includes,
    )

    # The Fory runtime headers are part of the compilation context as well
    # (through the `runtime` attribute), so only the generated ones are
    # compared here.
    headers = sorted([
        header.basename
        for header in cc_info.compilation_context.headers.to_list()
        if header.basename.startswith("examples_fdl_")
    ])
    asserts.equals(
        env,
        ["examples_fdl_address.h", "examples_fdl_person.h"],
        headers,
        "generated headers",
    )
    return analysistest.end(env)

cc_info_test = analysistest.make(_cc_info_test_impl)

def _py_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    py_info = target[PyInfo]

    imports = py_info.imports.to_list()
    asserts.true(
        env,
        any([entry.endswith("_fory_py/_person_py_fory_gen") for entry in imports]),
        "generated import directory is missing, got %s" % imports,
    )

    # `transitive_sources` also contains the vendored `pyfory` runtime.
    sources = sorted([
        source.basename
        for source in py_info.transitive_sources.to_list()
        if source.basename.startswith("examples_fdl_")
    ])
    asserts.equals(
        env,
        ["examples_fdl_address.py", "examples_fdl_person.py"],
        sources,
        "generated modules",
    )
    return analysistest.end(env)

py_info_test = analysistest.make(_py_info_test_impl)
