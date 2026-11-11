"""Public API of the Fory FDL rules.

The API mirrors the protobuf rule set (`rules_proto`):

| rules_fory        | protobuf equivalent |
| ----------------- | ------------------- |
| `fory_library`    | `proto_library`     |
| `cc_fory_library` | `cc_proto_library`  |
| `py_fory_library` | `py_proto_library`  |

```python
load("//:defs.bzl", "fory_library", "cc_fory_library", "py_fory_library")

fory_library(
    name = "person",
    srcs = ["person.fdl"],
    deps = [":address"],
)

cc_fory_library(
    name = "person_cc",
    deps = [":person"],
)

py_fory_library(
    name = "person_py",
    deps = [":person"],
)
```

Like `cc_proto_library`, the language rules attach an aspect to their `deps`,
so every `.fdl` file is turned into C++/Python code exactly once even when many
targets share it.

The `runtime` attribute of the language rules defaults to the runtimes of
MODULE.bazel (`@fory` for C++, `@fory_pip//pyfory` for Python) and is only
needed when a different Fory version should be used.
"""

load("//:providers.bzl", _ForyInfo = "ForyInfo")
load("//private:fory_cc_library.bzl", _cc_fory_library = "cc_fory_library")
load("//private:fory_library.bzl", _fory_library = "fory_library")
load("//private:fory_py_library.bzl", _py_fory_library = "py_fory_library")

ForyInfo = _ForyInfo

fory_library = _fory_library
cc_fory_library = _cc_fory_library
py_fory_library = _py_fory_library
