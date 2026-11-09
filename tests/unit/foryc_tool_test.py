"""Unit tests for the foryc wrapper used by the rules."""

import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path

import foryc_tool

FAKE_FORYC = """\
#!{python}
import argparse
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument("--lang")
parser.add_argument("--python_out")
parser.add_argument("--cpp_out")
parser.add_argument("-I", action="append", default=[])
parser.add_argument("files", nargs="*")
args = parser.parse_args()

out = pathlib.Path(args.python_out or args.cpp_out)
out.mkdir(parents=True, exist_ok=True)
suffix = ".py" if args.python_out else ".h"
for name in args.files:
    text = pathlib.Path(name).read_text()
    package = ""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("package "):
            package = stripped[len("package "):].rstrip(";").strip()
            break
    module = package.replace(".", "_") if package else "generated"
    if suffix == ".py":
        body = "import dep\\nvalue = dep.Thing\\n"
    else:
        body = '#include "dep.h"\\n'
    (out / (module + suffix)).write_text(body)
"""


class ParsePackageTest(unittest.TestCase):
    def test_package(self):
        self.assertEqual(foryc_tool.parse_package("package foo.bar;\n"), "foo.bar")

    def test_package_with_comment(self):
        self.assertEqual(
            foryc_tool.parse_package("// package ignored;\npackage a_b;\n"),
            "a_b",
        )

    def test_no_package(self):
        self.assertEqual(foryc_tool.parse_package("message A {}\n"), "")

    def test_foryc_module_name(self):
        self.assertEqual(foryc_tool.foryc_module_name("a.b"), "a_b")
        self.assertEqual(foryc_tool.foryc_module_name(""), "generated")


class RewriteTest(unittest.TestCase):
    def test_python_import(self):
        mapping = {"examples_fdl": "examples_fdl_address"}
        self.assertEqual(
            foryc_tool.rewrite_python("import examples_fdl\n", mapping),
            "import examples_fdl_address\n",
        )

    def test_python_from_import(self):
        mapping = {"old": "new"}
        self.assertEqual(
            foryc_tool.rewrite_python("from old import Thing\n", mapping),
            "from new import Thing\n",
        )

    def test_python_symbol_reference(self):
        mapping = {"old": "new"}
        self.assertEqual(
            foryc_tool.rewrite_python("x = old.ns.Thing\n", mapping),
            "x = new.ns.Thing\n",
        )

    def test_python_no_chained_replacement(self):
        mapping = {"a": "b", "b": "c"}
        self.assertEqual(
            foryc_tool.rewrite_python("a.one\nb.two\n", mapping),
            "b.one\nc.two\n",
        )

    def test_python_prefix_is_not_replaced(self):
        mapping = {"demo": "demo_renamed"}
        self.assertEqual(
            foryc_tool.rewrite_python("import demo_extra\ndemo.x\n", mapping),
            "import demo_extra\ndemo_renamed.x\n",
        )

    def test_python_imported_type_annotation(self):
        # foryc emits `mod.package.Type` annotations for fields that reference
        # types of another package; those must collapse to `mod.Type` because
        # the generated modules import each other by module name.
        annotations = {"demo_sub.demo.sub.": "demo_sub."}
        self.assertEqual(
            foryc_tool.rewrite_python(
                "value: demo_sub.demo.sub.Thing = None\n",
                {"demo_sub": "demo_sub"},
                annotations,
            ),
            "value: demo_sub.Thing = None\n",
        )

    def test_python_imported_type_annotation_with_mapping(self):
        annotations = {"demo_sub.demo.sub.": "demo_sub."}
        self.assertEqual(
            foryc_tool.rewrite_python(
                "value: demo_sub.demo.sub.Thing = None\n",
                {"demo_sub": "dep"},
                annotations,
            ),
            "value: dep.Thing = None\n",
        )

    def test_build_annotation_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dep.fdl"
            path.write_text("package demo.sub;\n")
            annotations = foryc_tool.build_annotation_map([(str(path), "dep")])
            self.assertEqual(annotations, {"demo_sub.demo.sub.": "demo_sub."})

    def test_cpp_include(self):
        mapping = {"examples_fdl": "examples_fdl_address"}
        self.assertEqual(
            foryc_tool.rewrite_cpp('#include "examples_fdl.h"\n', mapping),
            '#include "examples_fdl_address.h"\n',
        )


class GenerateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.foryc = self.root / "fake_foryc"
        self.foryc.write_text(FAKE_FORYC.format(python=sys.executable))
        self.foryc.chmod(self.foryc.stat().st_mode | stat.S_IEXEC)
        self.schemas = self.root / "schemas"
        self.schemas.mkdir()
        (self.schemas / "dep.fdl").write_text("package dep;\n")
        (self.schemas / "main.fdl").write_text(
            'package dep.main;\nimport "dep.fdl";\n'
        )

    def tearDown(self):
        self.tmp.cleanup()

    def _run(self, extra):
        argv = [
            "generate",
            "--foryc",
            str(self.foryc),
            "--lang",
            "python",
            "--module",
            "%s=%s" % ((self.schemas / "dep.fdl").as_posix(), "schemas_dep"),
            "--module",
            "%s=%s" % ((self.schemas / "main.fdl").as_posix(), "schemas_main"),
            "--source",
            "%s=%s" % ((self.schemas / "dep.fdl").as_posix(), "schemas_dep"),
            "--source",
            "%s=%s" % ((self.schemas / "main.fdl").as_posix(), "schemas_main"),
        ] + extra
        return foryc_tool.main(argv)

    def test_generate_renames_and_rewrites(self):
        outputs = self.root / "out"
        code = self._run([
            "--output",
            "schemas_dep=%s" % (outputs / "schemas_dep.py"),
            "--output",
            "schemas_main=%s" % (outputs / "schemas_main.py"),
        ])
        self.assertEqual(code, 0)
        dep = (outputs / "schemas_dep.py").read_text()
        main = (outputs / "schemas_main.py").read_text()
        # The fake compiler emits `import dep` for every file, so even the
        # module of the dependency gets rewritten (it is part of the map).
        self.assertIn("import schemas_dep", dep)
        self.assertIn("import schemas_dep", main)
        self.assertIn("schemas_dep.Thing", main)

    def test_duplicate_package_is_rejected(self):
        (self.schemas / "other.fdl").write_text("package dep;\n")
        code = foryc_tool.main([
            "generate",
            "--foryc",
            str(self.foryc),
            "--lang",
            "cpp",
            "--module",
            "%s=%s" % ((self.schemas / "dep.fdl").as_posix(), "schemas_dep"),
            "--module",
            "%s=%s" % ((self.schemas / "other.fdl").as_posix(), "schemas_other"),
            "--source",
            "%s=%s" % ((self.schemas / "dep.fdl").as_posix(), "schemas_dep"),
            "--output",
            "schemas_dep=%s" % (self.root / "dep.h"),
        ])
        self.assertEqual(code, 1)

    def test_missing_output_argument_is_rejected(self):
        code = self._run([
            "--output",
            "schemas_dep=%s" % (self.root / "schemas_dep.py"),
        ])
        self.assertEqual(code, 1)

    def test_check_writes_descriptor(self):
        descriptor = self.root / "checked.fory.json"
        code = foryc_tool.main([
            "check",
            "--foryc",
            str(self.foryc),
            "--lang",
            "python",
            "--descriptor",
            str(descriptor),
            "--descriptor-content",
            '{"target": "//x:y"}',
            "--source",
            "%s=%s" % ((self.schemas / "main.fdl").as_posix(), "schemas_main"),
        ])
        self.assertEqual(code, 0)
        self.assertEqual(descriptor.read_text(), '{"target": "//x:y"}')

    @unittest.skipUnless(
        shutil.which("foryc"),
        "foryc is not installed in this environment",
    )
    def test_real_foryc(self):
        real_root = self.root / "real"
        real_root.mkdir()
        (real_root / "a.fdl").write_text("package real.a;\nmessage A { string x = 1; }\n")
        code = foryc_tool.main([
            "generate",
            "--foryc",
            shutil.which("foryc"),
            "--lang",
            "python",
            "--include",
            str(real_root),
            "--module",
            "%s=%s" % ((real_root / "a.fdl").as_posix(), "real_a"),
            "--source",
            "%s=%s" % ((real_root / "a.fdl").as_posix(), "real_a"),
            "--output",
            "real_a=%s" % (real_root / "real_a.py"),
        ])
        self.assertEqual(code, 0)
        self.assertIn("class A", (real_root / "real_a.py").read_text())


if __name__ == "__main__":
    unittest.main()
