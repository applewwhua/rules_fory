"""Internal helpers shared by the Fory FDL rules.

The helpers implement the naming scheme that makes the output of `foryc`
deterministic from Bazel's point of view:

* `foryc` derives the name of a generated module from the `package` statement
  of a schema (`package foo.bar;` becomes `foo_bar.py` / `foo_bar.h`).  Bazel
  however has to know the output file names during the analysis phase, where
  the content of a source file cannot be read.  The rules therefore derive the
  names from the *path* of the `.fdl` file and rewrite the references produced
  by `foryc` afterwards (see `tools/foryc_tool.py`).
* Names mirror protoc: `a/b/pkg.fdl` produces `a/b/pkg.fory.h` (included as
  `#include "a/b/pkg.fory.h"`, like `a/b/pkg.pb.h`) and `a/b/pkg_fory.py`
  (imported as `a.b.pkg_fory`, like `a.b.pkg_pb2`).
* The import path of a schema is its workspace relative path
  (`//a/b:c.fdl` -> `a/b/c.fdl`), which is what `foryc -I .` resolves.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//:providers.bzl", "ForyInfo")

FDL_EXTENSION = "fdl"

#: Directory (package relative) holding the generated sources of one schema
#: target, one per language.
CC_OUTPUT_DIR = "_fory_cc"

PY_OUTPUT_DIR = "_fory_py"

#: Suffix appended to the name of a schema target to build the name of its
#: generated-code targets.
CC_GEN_SUFFIX = "_fdl_headers"

PY_GEN_SUFFIX = "_fdl_modules"

FORYC_TOOL = "//tools:foryc_tool"

_IDENTIFIER_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

def _sanitize(value):
    """Turns an arbitrary path segment into a Python/C++ identifier."""
    result = []
    for char in value.elems():
        result.append(char if char in _IDENTIFIER_CHARS else "_")
    sanitized = "".join(result)
    if not sanitized:
        return "generated"
    if sanitized[0] in "0123456789":
        sanitized = "_" + sanitized
    return sanitized

def import_path(file):
    """Returns the path a schema is imported by (workspace relative).

    Args:
      file: a `.fdl` source file, possibly of another repository.

    Returns:
      The workspace relative path of the file, e.g. `a/b/pkg.fdl`.
    """
    path = file.short_path
    if path.startswith("../"):
        return path[3:]
    if path.startswith("external/"):
        return path[len("external/"):]
    return path

def _stem(file):
    path = import_path(file)
    suffix = "." + FDL_EXTENSION
    if not path.endswith(suffix):
        fail("expected a .%s file, got %s" % (FDL_EXTENSION, path))
    return path[:-len(suffix)]

def header_path(file):
    """`a/b/pkg.fdl` -> `a/b/pkg.fory.h` (protoc style, like `a/b/pkg.pb.h`)."""
    return _stem(file) + ".fory.h"

def module_segments(file):
    """`a/b/pkg.fdl` -> `["a", "b", "pkg_fory"]` (protoc style, like `*_pb2`)."""
    segments = _stem(file).split("/")
    return [_sanitize(segment) for segment in segments[:-1]] + [_sanitize(segments[-1]) + "_fory"]

def module_name(file):
    """`a/b/pkg.fdl` -> `a.b.pkg_fory` (protoc style, like `a.b.pkg_pb2`)."""
    return ".".join(module_segments(file))

def module_path(file):
    """`a/b/pkg.fdl` -> `a/b/pkg_fory.py` (protoc style, like `a/b/pkg_pb2.py`)."""
    return "/".join(module_segments(file)) + ".py"

def import_root(file):
    """Returns the `-I` root that makes `import_path(file)` resolvable.

    Args:
      file: a `.fdl` source file, possibly of another repository.

    Returns:
      The `-I` root, `.` for files of the main repository.
    """
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

def gen_dir(directory, name):
    """Package relative directory holding the generated files of one target."""
    return "%s/%s" % (directory, name)

def merge_compilation_contexts(contexts):
    """Merges a list of `CompilationContext`s into one."""
    return cc_common.create_compilation_context(
        headers = depset(transitive = [context.headers for context in contexts]),
        includes = depset(transitive = [context.includes for context in contexts]),
        quote_includes = depset(transitive = [context.quote_includes for context in contexts]),
        system_includes = depset(transitive = [context.system_includes for context in contexts]),
        defines = depset(transitive = [context.defines for context in contexts]),
        local_defines = depset(transitive = [context.local_defines for context in contexts]),
    )

def execroot_dir(file, relative):
    """Returns the execroot path of the directory that holds `file` at `relative`.

    E.g. for the generated file `<bin>/a/b/_fory_cc/x/a/b/pkg.fory.h` with
    relative path `a/b/pkg.fory.h` this yields `<bin>/a/b/_fory_cc/x`, which is
    the include root the rewritten `#include "a/b/pkg.fory.h"` needs.

    Args:
      file: a generated output file.
      relative: the path of the file inside its output directory.

    Returns:
      The execroot path of the output directory.
    """
    suffix = "/" + relative
    if not file.path.endswith(suffix):
        fail("expected %s to end with %s" % (file.path, suffix))
    return file.path[:-len(suffix)]

def runfiles_dir(ctx, file, relative):
    """Returns the runfiles relative directory that holds `file` at `relative`.

    `PyInfo.imports` uses runfiles paths, so the generated modules of the main
    repository are addressed as `<workspace>/<package>/_fory_py/<target>` and
    the ones of other repositories as `<repository>/<package>/...`.

    Args:
      ctx: the rule or aspect context the file belongs to.
      file: a generated output file.
      relative: the path of the file inside its output directory.

    Returns:
      The runfiles relative path of the output directory.
    """
    suffix = "/" + relative
    if not file.short_path.endswith(suffix):
        fail("expected %s to end with %s" % (file.short_path, suffix))
    directory = file.short_path[:-len(suffix)]
    if directory.startswith("../"):
        return directory[3:]
    if directory.startswith("external/"):
        return directory[len("external/"):]
    return ctx.workspace_name + "/" + directory

def run_codegen(ctx, lang, srcs, closure, import_roots, directory, name, output_path):
    """Declares and runs the `foryc` action of one schema target.

    Args:
      ctx: the rule or aspect context the action belongs to.
      lang: `cpp` or `python`.
      srcs: the `.fdl` files of this target; only these are generated.
      closure: every `.fdl` file of the transitive closure, used for the
        module renaming and to resolve the imports of `srcs`.
      import_roots: depset[str] of `-I` roots.
      directory: package relative output directory (`_fory_cc` / `_fory_py`).
      name: name of the generated-code target, used as sub directory.
      output_path: maps a `.fdl` file to its path inside the output directory.

    Returns:
      list[File] of the declared outputs.
    """
    ordered = sorted(srcs, key = source_sort_key)
    gen_directory = gen_dir(directory, name)
    outputs = []
    for source in ordered:
        outputs.append(ctx.actions.declare_file("%s/%s" % (gen_directory, output_path(source))))
    if not outputs:
        return outputs

    args = ctx.actions.args()
    args.add("generate")
    args.add("--lang", lang)
    for root in sorted(import_roots.to_list()):
        args.add("--include", root)
    for source in closure:
        args.add("--closure", source.path)
    for index, source in enumerate(ordered):
        args.add("--emit", "%s=%s" % (source.path, outputs[index].path))

    ctx.actions.run(
        executable = ctx.executable._foryc_tool,
        arguments = [args],
        inputs = depset(transitive = [depset(closure)]),
        outputs = outputs,
        tools = [ctx.attr._foryc_tool[DefaultInfo].files_to_run],
        mnemonic = "ForyCodegen",
        progress_message = "Generating Fory %s bindings for %s" % (lang, ctx.label),
    )
    return outputs
