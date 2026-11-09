"""End to end test for `py_fory_library`.

The test depends on the generated `py_library`, which means that the directory
holding the generated modules has to end up on `sys.path` because of the
`imports` attribute of the library.
"""

import os
import py_compile
import sys
import tempfile
import unittest

_MODULE_DIR_SUFFIX = "_fory_py/_person_py_fory_gen"
_MODULES = (
    "examples_address.py",
    "examples_person.py",
)


class PythonCodegenTest(unittest.TestCase):
    def module_dir(self):
        for entry in sys.path:
            if entry.replace("\\", "/").rstrip("/").endswith(_MODULE_DIR_SUFFIX):
                return entry
        self.fail(
            "the generated module directory is not on sys.path; sys.path was %s"
            % (sys.path,)
        )

    def read(self, name):
        with open(os.path.join(self.module_dir(), name), encoding="utf-8") as handle:
            return handle.read()

    def test_modules_are_generated(self):
        directory = self.module_dir()
        for name in _MODULES:
            self.assertTrue(
                os.path.isfile(os.path.join(directory, name)),
                "%s is missing in %s" % (name, directory),
            )

    def test_imports_are_rewritten(self):
        person = self.read("examples_person.py")
        self.assertIn("import examples_address", person)
        self.assertNotIn("\nimport examples\n", person)

    def test_generated_modules_are_valid_python(self):
        directory = self.module_dir()
        with tempfile.TemporaryDirectory() as tmp:
            for name in _MODULES:
                py_compile.compile(
                    os.path.join(directory, name),
                    cfile=os.path.join(tmp, name + "c"),
                    doraise=True,
                )


if __name__ == "__main__":
    unittest.main()
