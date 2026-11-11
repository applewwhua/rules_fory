#!/usr/bin/env python3
"""Helper around the `foryc` compiler used by the Fory FDL rules.

`foryc` names generated modules after the `package` statement of the schema
(`package foo.bar;` -> `foo_bar.py` / `foo_bar.h`).  Bazel has to know the
output names during the analysis phase, where source files cannot be read, so
the rules use deterministic names derived from the *path* of the `.fdl` file
instead, mirroring protoc:

============================  =========================================
`a/b/pkg.fdl`                 `a/b/pkg.fory.h`    (like `a/b/pkg.pb.h`)
`a/b/pkg.fdl`                 `a/b/pkg_fory.py`   (like `a/b/pkg_pb2.py`)
============================  =========================================

This tool drives the `foryc` implementation of the `fory-compiler` wheel
(`fory_compiler`, resolved through the `fory_pip` hub of MODULE.bazel - the
same code as the `foryc` console script, no host installation involved) and
renames/rewrites the generated modules accordingly.

Two sub commands are provided:

``generate``
    Runs the generators for one language and writes the generated files to the
    declared output paths.  Module references inside the generated code are
    rewritten to the deterministic names.

``check``
    Validates the schemas by generating code into memory and writes a marker
    file.  Used by `fory_library`.
"""

from __future__ import annotations

import argparse
import re
import string
import sys
from pathlib import Path

from fory_compiler.cli import ImportError as ForycImportError
from fory_compiler.cli import resolve_imports
from fory_compiler.frontend.base import FrontendError
from fory_compiler.frontend.utils import parse_idl_file
from fory_compiler.generators import GENERATORS
from fory_compiler.generators.base import GeneratorOptions
from fory_compiler.ir.validator import SchemaValidator

FDL_SUFFIX = ".fdl"

#: language -> file extension of a generated module
EXTENSIONS = {
    "cpp": ".h",
    "python": ".py",
}

_ALLOWED_IDENTIFIER_CHARS = set(string.ascii_letters + string.digits + "_")


class ForycError(RuntimeError):
    """Raised for every recoverable error."""


def import_path(path) -> str:
    """Normalizes a source path to its workspace relative (import) form.

    Bazel addresses files of other repositories as `../repo/pkg/x.fdl` (or
    `external/repo/pkg/x.fdl`); the rules name their outputs without that
    prefix, so the same normalization has to be applied here.
    """
    path = str(path)
    if path.startswith("../"):
        return path[3:]
    if path.startswith("external/"):
        return path[len("external/"):]
    return path


def sanitize(segment: str) -> str:
    """Turns a path segment into a Python/C++ identifier (mirrors common.bzl)."""
    result = "".join(
        char if char in _ALLOWED_IDENTIFIER_CHARS else "_" for char in segment
    )
    if not result:
        return "generated"
    if result[0].isdigit():
        result = "_" + result
    return result


def package_of(path) -> str:
    """Returns the FDL package declared in a `.fdl` file ("" when absent)."""
    return parse_idl_file(Path(path)).package or ""


def natural_module(package: str) -> str:
    """The module name foryc derives from a package ("" -> 'generated')."""
    return package.replace(".", "_") if package else "generated"


def declared_header(path) -> str:
    """`a/b/pkg.fdl` -> `a/b/pkg.fory.h` (protoc style, like `*.pb.h`)."""
    return import_path(path)[: -len(FDL_SUFFIX)] + ".fory.h"


def declared_module(path) -> str:
    """`a/b/pkg.fdl` -> `a.b.pkg_fory` (protoc style, like `*.pb2`)."""
    segments = import_path(path)[: -len(FDL_SUFFIX)].split("/")
    return ".".join([sanitize(segment) for segment in segments[:-1]] + [sanitize(segments[-1]) + "_fory"])


def build_mapping(lang: str, closure) -> dict:
    """Maps `foryc` module names to the declared names of the closure.

    Args:
      lang: `cpp` or `python`.
      closure: every `.fdl` file of the transitive closure of the target.

    Returns:
      dict[str, str]: from the name `foryc` uses (package with dots replaced
      by underscores) to the name the rules declare.
    """
    mapping = {}
    owners = {}
    for path in closure:
        package = package_of(path)
        natural = natural_module(package)
        key = natural + EXTENSIONS[lang] if lang == "cpp" else natural
        declared = declared_header(path) if lang == "cpp" else declared_module(path)
        if key in mapping and mapping[key] != declared:
            raise ForycError(
                "the Fory package %r is declared by more than one file (%s, %s)."
                " foryc generates one module per package, so every .fdl file"
                " must declare a unique package." % (
                    package or "<none>",
                    owners[key],
                    import_path(path),
                )
            )
        mapping[key] = declared
        owners[key] = import_path(path)
    return mapping


def build_annotations(closure) -> dict:
    """Rewrite rules for qualified type annotations of imported types.

    `foryc` emits annotations like ``module.package.path.Type`` for fields
    that reference types of another package, but the generated modules import
    each other by module name, so the redundant package qualifier is dropped;
    the module rewrite below then renames the module itself.
    """
    annotations = {}
    for path in closure:
        package = package_of(path)
        if not package:
            continue
        natural = natural_module(package)
        annotations["%s.%s." % (natural, package)] = "%s." % natural
    return annotations


def _alternation(mapping) -> str:
    """Regex alternation of the mapping keys, longest first."""
    keys = [re.escape(key) for key in mapping if key]
    return "|".join(sorted(keys, key=len, reverse=True))


def rewrite_python(text: str, mapping, annotations=None) -> str:
    """Rewrites module references of generated Python code."""
    for prefix, target in sorted(
        (annotations or {}).items(), key=lambda item: len(item[0]), reverse=True
    ):
        text = text.replace(prefix, target)

    alternation = _alternation(mapping)
    if not alternation:
        return text

    # `import old` / `from old import ...`
    text = re.sub(
        r"(?m)^(import|from)[ \t]+(" + alternation + r")(?=[ \t]|$)",
        lambda match: "%s %s" % (match.group(1), mapping[match.group(2)]),
        text,
    )
    # `old.Symbol(...)` and `old.namespace.Symbol`
    return re.sub(
        r"(?<![\w.])(" + alternation + r")\.",
        lambda match: mapping[match.group(1)] + ".",
        text,
    )


def rewrite_cpp(text: str, mapping) -> str:
    """Rewrites `#include "old.h"` directives of generated C++ code."""
    alternation = _alternation(mapping)
    if not alternation:
        return text
    return re.sub(
        r'#include[ \t]+"(' + alternation + r')"',
        lambda match: '#include "%s"' % mapping[match.group(1)],
        text,
    )


def rewrite(text: str, lang: str, mapping, annotations=None) -> str:
    if lang == "python":
        return rewrite_python(text, mapping, annotations)
    if lang == "cpp":
        return rewrite_cpp(text, mapping)
    raise ForycError("unsupported language %r" % lang)


def import_paths(include, closure):
    """Resolves the import search roots for `foryc`.

    The roots of the schemas' repositories come first; the directories of the
    closure are added afterwards so that imports written relative to the
    imported file (`import "shared.fdl";`) resolve as well.
    """
    roots = [Path(root) for root in include] or [Path(".")]
    seen = {str(root) for root in roots}
    for path in closure:
        directory = Path(path).parent
        if str(directory) not in seen:
            seen.add(str(directory))
            roots.append(directory)
    return roots


def _render(lang: str, source, roots):
    """Generates the code of one schema; returns (content, natural file name)."""
    schema = resolve_imports(Path(source), roots)

    # Same validation as the `foryc` CLI performs before generating code.
    validator = SchemaValidator(schema, allow_nested_collections=(lang == "cpp"))
    if not validator.validate():
        for error in validator.errors:
            print("Error: %s" % error, file=sys.stderr)
        raise ForycError("the schemas of %s are invalid" % source)
    for warning in validator.warnings:
        print("Warning: %s" % warning)

    generator = GENERATORS[lang](schema, GeneratorOptions(output_dir=Path(".")))
    package = schema.package or ""
    expected = natural_module(package) + EXTENSIONS[lang]
    files = generator.generate()
    for generated in files:
        if Path(generated.path).name == expected:
            return generated.content, expected
    raise ForycError(
        "foryc produced %s for %s; expected %s" % (
            sorted(Path(generated.path).name for generated in files),
            import_path(source),
            expected,
        )
    )


def _split_assignment(value: str, flag: str):
    if "=" not in value:
        raise ForycError("%s expects KEY=VALUE, got %r" % (flag, value))
    left, right = value.split("=", 1)
    return left, right


def run_generate(args) -> int:
    mapping = build_mapping(args.lang, args.closure)
    annotations = build_annotations(args.closure) if args.lang == "python" else None
    roots = import_paths(args.include, args.closure)

    for value in args.emit:
        source, output = _split_assignment(value, "--emit")
        content, _ = _render(args.lang, source, roots)
        target = Path(output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rewrite(content, args.lang, mapping, annotations))
        print("Generated: %s" % output)
    return 0


def run_check(args) -> int:
    roots = import_paths(args.include, args.closure)
    for source in args.source:
        _render(args.lang, source, roots)

    descriptor = Path(args.descriptor)
    descriptor.parent.mkdir(parents=True, exist_ok=True)
    descriptor.write_text(args.descriptor_content or "")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common(subparser):
        subparser.add_argument(
            "--lang",
            required=True,
            choices=sorted(EXTENSIONS),
            help="Target language.",
        )
        subparser.add_argument(
            "--include",
            action="append",
            default=[],
            help="Import search root passed to foryc (-I). Repeatable.",
        )

    generate = subparsers.add_parser("generate", help="Generate code.")
    add_common(generate)
    generate.add_argument(
        "--closure",
        action="append",
        default=[],
        help="PATH of a .fdl file of the transitive closure. Repeatable.",
    )
    generate.add_argument(
        "--emit",
        action="append",
        default=[],
        help="PATH=OUTPUT of a schema that should be generated. Repeatable.",
    )
    generate.set_defaults(func=run_generate)

    check = subparsers.add_parser("check", help="Validate schemas.")
    add_common(check)
    check.add_argument(
        "--closure",
        action="append",
        default=[],
        help="PATH of a .fdl file of the transitive closure. Repeatable.",
    )
    check.add_argument(
        "--source",
        action="append",
        default=[],
        help="PATH of a .fdl file that should be validated. Repeatable.",
    )
    check.add_argument(
        "--descriptor",
        required=True,
        help="Descriptor set file to write after a successful validation.",
    )
    check.add_argument(
        "--descriptor-content",
        default="",
        help="JSON content written to the descriptor file.",
    )
    check.set_defaults(func=run_check)

    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (ForycError, ForycImportError, FrontendError, ValueError, OSError) as exc:
        print("rules_fory: error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
