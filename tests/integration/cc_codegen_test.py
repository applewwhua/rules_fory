"""End to end test for `cc_fory_library`.

The generated headers are checked through the runfiles of the `filegroup`
exposed by the example package.
"""

import os
import unittest

from python.runfiles import runfiles

_HEADER_DIR = "examples/_fory_cc/_person_cc_fory_gen"


class CcCodegenTest(unittest.TestCase):
    def setUp(self):
        self.runfiles = runfiles.Create()
        self.workspace = os.environ.get("TEST_WORKSPACE") or "rules_fory"

    def read_header(self, name):
        path = self.runfiles.Rlocation(
            "%s/%s/%s" % (self.workspace, _HEADER_DIR, name)
        )
        self.assertTrue(path and os.path.isfile(path), "%s is missing" % name)
        with open(path, encoding="utf-8") as handle:
            return handle.read()

    def test_headers_are_generated(self):
        address = self.read_header("examples_address.h")
        person = self.read_header("examples_person.h")
        self.assertIn("class Address", address)
        self.assertIn("class Person", person)

    def test_includes_are_rewritten(self):
        person = self.read_header("examples_person.h")
        self.assertIn('#include "examples_address.h"', person)
        self.assertNotIn('#include "examples.h"', person)

    def test_runtime_include_is_kept(self):
        person = self.read_header("examples_person.h")
        self.assertIn('#include "fory/serialization/fory.h"', person)

    def test_namespaces_are_untouched(self):
        person = self.read_header("examples_person.h")
        self.assertIn("namespace examples::person", person)


if __name__ == "__main__":
    unittest.main()
