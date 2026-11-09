#!/usr/bin/env python3
"""Helper around the `foryc` compiler used by rules_fory.

`foryc` names generated modules after the `package` statement of the schema
(`package foo.bar;` -> `foo_bar.py`).  Bazel has to know the output names
during the analysis phase, where source files cannot be read, so the rules use
a deterministic name derived from the *path* of the `.fdl` file instead.  This
tool runs `foryc` and renames/rewrites the generated modules accordingly.

Two sub commands are provided:

``generate``
    Runs `foryc` for one language and writes the generated files to the
    declared output paths.  Module references inside the generated code are
    rewritten to the deterministic module names.

``check``
    Validates the schemas by running a code generation into a temporary
    directory and writes a marker file.  Used by `fory_library`.

Only the Python standard library is used so the tool can run with the
interpreter of any Python toolchain.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

#: `package foo.bar;` - a line based match is good enough for deriving module
#: names.
PACKAGE_RE = re.compile(
    r"(?m)^[ \t]*package[ \t]+([A-Za-z_][A-Za-z0-9_.]*)[ \t]*;"
)

#: language -> (foryc output flag, file extension)
LANGUAGES = {
    "cpp": ("--cpp_out", ".h"),
    "python": ("--python_out", ".py"),
}


class ForycError(RuntimeError):
    """Raised for every recoverable error."""


def parse_package(text: str) -> str:
    """Extracts the package name of an FDL document ("" when absent)."""
    match = PACKAGE_RE.search(text)
    return match.group(1) if match else ""


def parse_package_file(path) -> str:
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:  # pragma: no cover - only on broken inputs
        raise ForycError(f"cannot read {path}: {exc}") from exc
    return parse_package(text)


def foryc_module_name(package: str) -> str:
    """Maps a package name to the module name chosen by `foryc`."""
    return package.replace(".", "_") if package else "generated"


def split_assignment(value: str, flag: str):
    """Splits a `KEY=VALUE` command line argument."""
    if "=" not in value:
        raise ForycError(f"{flag} expects KEY=VALUE, got {value!r}")
    left, right = value.split("=", 1)
    return left, right


def build_module_map(entries):
    """Maps `foryc` module names to rules_fory module names.

    Args:
      entries: iterable of ``(path, module_name)`` pairs covering the complete
        transitive closure of schemas.

    Returns:
      dict[str, str] from the module name used by `foryc` (the package name
      with dots replaced by underscores) to the rules_fory module name.
    """
    mapping = {}
    owners = {}
    for path, module in entries:
        package = parse_package_file(path)
        foryc_module = foryc_module_name(package)
        previous = mapping.get(foryc_module)
        if previous is not None and previous != module:
            raise ForycError(
                "the Fory package %r is declared by more than one file (%s, %s)."
                " foryc generates one module per package, so every .fdl file"
                " must declare a unique package." % (
                    package or "<none>",
                    owners[foryc_module],
                    path,
                )
            )
        mapping[foryc_module] = module
        owners[foryc_module] = path
    return mapping


def build_annotation_map(entries):
    """Builds rewrite rules for qualified type annotations of imported types.

    `foryc` emits annotations like ``mod.package.path.Type`` for fields that
    reference types of another package, but the generated modules import each
    other by module name (``mod``), so ``mod.examples.foo.Type`` cannot be
    resolved.  The rules rewrite such annotations to ``mod.Type``.

    Args:
      entries: iterable of ``(path, module_name)`` pairs covering the complete
        transitive closure of schemas.

    Returns:
      dict[str, str] mapping ``<module>.<package>.`` prefixes to
      ``<module>.``.
    """
    annotations = {}
    for path, _ in entries:
        package = parse_package_file(path)
        if not package:
            continue
        # `foryc` names the module after the package, and qualifies imported
        # types as `<module>.<package>.<Type>`.
        foryc_module = foryc_module_name(package)
        annotations["%s.%s." % (foryc_module, package)] = "%s." % foryc_module
    return annotations


def _alternation(mapping):
    keys = [key for key in mapping if key]
    return "|".join(re.escape(key) for key in sorted(keys, key=len, reverse=True))


def rewrite_python(text: str, mapping, annotations=None) -> str:
    """Rewrites module references of generated Python code.

    Args:
      text: the generated source code.
      mapping: from `foryc` module names to rules_fory module names.
      annotations: optional dict of ``module.package.`` annotation prefixes to
        rewrite (see `build_annotation_map`); applied before the module
        mapping.
    """
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
    text = re.sub(
        r"(?<![\w.])(" + alternation + r")\.",
        lambda match: mapping[match.group(1)] + ".",
        text,
    )
    return text


def rewrite_cpp(text: str, mapping) -> str:
    """Rewrites `#include "old.h"` directives of generated C++ code."""
    alternation = _alternation(mapping)
    if not alternation:
        return text
    return re.sub(
        r'#include[ \t]+"(' + alternation + r')\.h"',
        lambda match: '#include "%s.h"' % mapping[match.group(1)],
        text,
    )


def rewrite(text: str, lang: str, mapping, annotations=None) -> str:
    if lang == "python":
        return rewrite_python(text, mapping, annotations)
    if lang == "cpp":
        return rewrite_cpp(text, mapping)
    raise ForycError(f"unsupported language {lang!r}")


def _run_foryc(command):
    if os.name == "nt" and command[0].lower().endswith(".bat"):
        completed = subprocess.run(
            subprocess.list2cmdline(command),
            shell=True,
            capture_output=True,
            text=True,
        )
    else:
        completed = subprocess.run(command, capture_output=True, text=True)

    if completed.returncode != 0:
        output = (completed.stdout or "") + (completed.stderr or "")
        raise ForycError(
            "foryc failed with exit code %d\ncommand: %s\n%s" % (
                completed.returncode,
                " ".join(command),
                output.strip(),
            )
        )
    return completed


def run_generate(args) -> int:
    output_flag, extension = LANGUAGES[args.lang]
    sources = [split_assignment(value, "--source") for value in args.source]
    modules = [split_assignment(value, "--module") for value in args.module]

    outputs = {}
    for value in args.output:
        module, path = split_assignment(value, "--output")
        if module in outputs:
            raise ForycError(f"duplicate --output for module {module!r}")
        outputs[module] = path

    entries = list(modules) + [entry for entry in sources if entry not in modules]
    mapping = build_module_map(entries)
    annotations = build_annotation_map(entries)

    for _, module in sources:
        if module not in outputs:
            raise ForycError(f"no declared output file for module {module!r}")

    with tempfile.TemporaryDirectory(prefix="rules_fory_out_") as out_dir:
        command = [args.foryc, "--lang", args.lang, output_flag, out_dir]
        for include in args.include:
            command += ["-I", include]
        command += [path for path, _ in sources]
        _run_foryc(command)

        produced = {}
        for path in Path(out_dir).rglob("*" + extension):
            produced.setdefault(path.stem, path)

        missing = []
        for source_path, module in sources:
            package = parse_package_file(source_path)
            foryc_module = foryc_module_name(package)
            generated = produced.get(foryc_module)
            if generated is None:
                missing.append(
                    "%s (package %r, expected %s%s)" % (
                        source_path,
                        package or "<none>",
                        foryc_module,
                        extension,
                    )
                )
                continue

            text = generated.read_text(encoding="utf-8")
            target = Path(outputs[module])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                rewrite(text, args.lang, mapping, annotations), encoding="utf-8"
            )

        if missing:
            raise ForycError(
                "foryc did not generate the expected files:\n  " + "\n  ".join(missing)
            )

        unused = set(produced) - {
            foryc_module_name(parse_package_file(path)) for path, _ in sources
        }
        if unused:
            print(
                "rules_fory: ignoring unexpected generated modules: %s" %
                ", ".join(sorted(unused)),
                file=sys.stderr,
            )

    return 0


def run_check(args) -> int:
    output_flag, _ = LANGUAGES[args.lang]
    sources = [split_assignment(value, "--source") for value in args.source]

    with tempfile.TemporaryDirectory(prefix="rules_fory_check_") as out_dir:
        command = [args.foryc, "--lang", args.lang, output_flag, out_dir]
        for include in args.include:
            command += ["-I", include]
        command += [path for path, _ in sources]
        _run_foryc(command)

    descriptor = Path(args.descriptor)
    descriptor.parent.mkdir(parents=True, exist_ok=True)
    descriptor.write_text(args.descriptor_content or "", encoding="utf-8")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common(subparser):
        subparser.add_argument("--foryc", required=True, help="Path to the foryc executable.")
        subparser.add_argument(
            "--lang",
            required=True,
            choices=sorted(LANGUAGES),
            help="Target language.",
        )
        subparser.add_argument(
            "--include",
            action="append",
            default=[],
            help="Import search root passed to foryc (-I). Repeatable.",
        )
        subparser.add_argument(
            "--source",
            action="append",
            default=[],
            help="PATH=MODULE of a schema that should be compiled. Repeatable.",
        )

    generate = subparsers.add_parser("generate", help="Generate code.")
    add_common(generate)
    generate.add_argument(
        "--module",
        action="append",
        default=[],
        help="PATH=MODULE for every schema of the transitive closure. Repeatable.",
    )
    generate.add_argument(
        "--output",
        action="append",
        default=[],
        help="MODULE=PATH of a declared output file. Repeatable.",
    )
    generate.set_defaults(func=run_generate)

    check = subparsers.add_parser("check", help="Validate schemas.")
    add_common(check)
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
    except ForycError as exc:
        print(f"rules_fory: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
