"""Implementation of `py_fory_library` (the counterpart of `py_proto_library`)."""

load("@rules_python//python:defs.bzl", "py_library")
load("//fory/private:fory_codegen.bzl", "fory_codegen")

def py_fory_library(
        name,
        deps = [],
        runtime = None,
        **kwargs):
    """Generates Python bindings for a set of `fory_library` targets.

    The generated modules are plain importable Python modules named after the
    path of the `.fdl` file, e.g. `//examples/fdl:person` generates
    `examples_fdl_person.py`.  The directory holding the modules is
    added to `sys.path` through the `imports` attribute of the resulting
    `py_library`.

    Args:
      name: name of the resulting `py_library`.
      deps: `fory_library` targets that should be available to the bindings.
      runtime: optional `py_library` that provides the `pyfory` runtime.  It is
        added as a dependency of the generated library.
      **kwargs: forwarded to `py_library` (for example `visibility`, `tags`,
        `testonly`).
    """
    gen_name = "_%s_fory_gen" % name
    fory_codegen(
        name = gen_name,
        fory_deps = deps,
        lang = "python",
        visibility = ["//visibility:private"],
        tags = kwargs.get("tags", []),
        testonly = kwargs.get("testonly", False),
    )

    py_library(
        name = name,
        srcs = [":" + gen_name],
        imports = ["_fory_py/" + gen_name],
        deps = [runtime] if runtime else [],
        **kwargs
    )
