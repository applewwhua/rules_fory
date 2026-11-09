"""Implementation of `cc_fory_library` (the counterpart of `cc_proto_library`)."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//fory/private:fory_codegen.bzl", "fory_codegen")

def cc_fory_library(
        name,
        deps = [],
        runtime = None,
        **kwargs):
    """Generates C++ bindings for a set of `fory_library` targets.

    The result is a header only `cc_library`.  Generated headers are placed in
    a single directory that is added to the include path of the library, so a
    header can be included by its module name, e.g.

    ```
    #include "examples_person.h"
    ```

    Args:
      name: name of the resulting `cc_library`.
      deps: `fory_library` targets that should be available to the bindings.
      runtime: optional `cc_library` that provides the Fory C++ runtime
        (`fory/serialization/fory.h`).  It is added as a dependency of the
        generated library.
      **kwargs: forwarded to `cc_library` (for example `visibility`, `tags`,
        `testonly`).
    """
    gen_name = "_%s_fory_gen" % name
    fory_codegen(
        name = gen_name,
        fory_deps = deps,
        lang = "cpp",
        visibility = ["//visibility:private"],
        tags = kwargs.get("tags", []),
        testonly = kwargs.get("testonly", False),
    )

    data = list(kwargs.pop("data", [])) + [":" + gen_name]
    cc_library(
        name = name,
        hdrs = [":" + gen_name],
        includes = ["_fory_cc/" + gen_name],
        deps = [runtime] if runtime else [],
        data = data,
        **kwargs
    )
