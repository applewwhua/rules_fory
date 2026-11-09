"""Launcher for the `foryc` CLI of the `fory-compiler` wheel.

`fory-compiler` installs a `foryc` console script that is a thin wrapper around
`fory_compiler.cli:main`; this module reproduces it so the compiler can be
used as a regular Bazel executable (`py_binary`) instead of depending on a
host installation.
"""

import sys

from fory_compiler.cli import main

if __name__ == "__main__":
    sys.argv[0] = "foryc"
    sys.exit(main())
