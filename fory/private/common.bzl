"""Internal helpers shared by the rules_fory rules.

The helpers implement the naming scheme that makes the output of `foryc`
deterministic from Bazel's point of view:

* `foryc` derives the name of a generated module from the `package` statement
  of a schema (for example `package foo.bar;` becomes `foo_bar.py`).  Bazel
  however has to know the output file names during the analysis phase, where
  the content of a source file cannot be read.  rules_fory therefore derives
  the module name from the *path* of the `.fdl` file and rewrites the module
  references produced by `foryc` afterwards (see `fory/tools/foryc_tool.py`).
* The import path of a schema is its workspace relative path
  (`//a/b:c.fdl` -> `a/b/c.fdl`), which is what `foryc -I .` resolves.
"""

load("//fory:providers.bzl", "ForyInfo")

FDL_EXTENSION = "fdl"

FORYC_TOOLCHAIN_TYPE = "//fory/toolchains:foryc_toolchain_type"

FORYC_TOOL = "//fory/tools:foryc_tool"

PY_OUTPUT_DIR = "_fory_py"

CC_OUTPUT_DIR = "_fory_cc"

_ALLOWED_IDENTIFIER_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

def _sanitize(value):
    """Turns an arbitrary path into an identifier usable by Python and C++."""
    result = []
    for char in value.elems():
        if char in _ALLOWED_IDENTIFIER_CHARS:
            result.append(char)
        else:
            result.append("_")
    sanitized = "".join(result)
    if not sanitized:
        return "generated"
    if sanitized[0].isdigit():
        sanitized = "_" + sanitized
    return sanitized

def module_name(file):
    """Returns the generated module name for a `.fdl` file.

    Examples:
      `examples/fdl/address.fdl` -> `examples_fdl_address`
      `../fory_schemas/common.fdl`       -> `fory_schemas_common`
    """
    path = file.short_path
    if path.startswith("../"):
        path = path[3:]
    elif path.startswith("external/"):
        path = path[len("external/"):]

    suffix = "." + FDL_EXTENSION
    if path.endswith(suffix):
        path = path[:-len(suffix)]
    return _sanitize(path)

def import_path(file):
    """Returns the path a schema is imported by (workspace relative)."""
    path = file.short_path
    if path.startswith("../"):
        return path[3:]
    if path.startswith("external/"):
        return path[len("external/"):]
    return path

def import_root(file):
    """Returns the `-I` root that makes `import_path(file)` resolvable."""
    path = file.path
    if path.startswith("../"):
        return "../" + path[3:].partition("/")[0]
    if path.startswith("external/"):
        return "external/" + path[len("external/"):].partition("/")[0]
    return "."

def source_sort_key(file):
    return file.path

def merge_fory_infos(targets):
    """Merges the `ForyInfo` providers of `targets` into one struct."""
    infos = [target[ForyInfo] for target in targets]
    return struct(
        direct_sources = depset(transitive = [info.direct_sources for info in infos]),
        transitive_sources = depset(transitive = [info.transitive_sources for info in infos]),
        import_roots = depset(transitive = [info.import_roots for info in infos]),
        descriptor_sets = depset([info.descriptor_set for info in infos]),
    )

def module_arguments(sources):
    """Returns `PATH=MODULE` arguments for `foryc_tool.py`."""
    entries = []
    for source in sources:
        entries.append("%s=%s" % (source.path, module_name(source)))
    return entries
