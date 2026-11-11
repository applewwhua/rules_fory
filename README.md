# rules_fory

Bazel rules for [Apache Fory](https://fory.apache.org): use Fory FDL
(`.fdl`) schemas in C++ and Python programs.

The API mirrors the protobuf rule set (`rules_proto`):

| rules_fory        | protobuf equivalent  |
| ----------------- | -------------------- |
| `fory_library`    | `proto_library`      |
| `cc_fory_library` | `cc_proto_library`   |
| `py_fory_library` | `py_proto_library`   |

Supported Bazel version: **9.2** (bzlmod only, no `WORKSPACE`).

## Directory layout

```
rules_fory/
├── MODULE.bazel              # module definition + dependencies (pip hub, @fory runtime)
├── defs.bzl                  # public API (load from here)
├── providers.bzl             # ForyInfo
├── private/                  # rule implementations
│   ├── common.bzl            # naming + path helpers, shared codegen action
│   ├── fory_library.bzl      # fory_library
│   ├── fory_cc_aspect.bzl    # per-schema C++ code generation (applied once)
│   ├── fory_py_aspect.bzl    # per-schema Python code generation (applied once)
│   ├── fory_cc_library.bzl   # cc_fory_library macro
│   ├── fory_py_library.bzl   # py_fory_library macro
│   └── requirements_lock.txt # pinned fory-compiler / pyfory wheels
├── tools/                    # foryc action driver (imports the wheel's compiler)
└── example/                  # schemas + C++/Python round trip tests
```

## Usage

```python
# MODULE.bazel
bazel_dep(name = "rules_fory", version = "0.1.0")
```

```python
# BUILD.bazel
load("@rules_fory//:defs.bzl", "fory_library", "cc_fory_library", "py_fory_library")

fory_library(
    name = "greeter",
    srcs = ["greeter.fdl"],
    import_roots = ["interfaces"],        # imports are written relative to this tree
    deps = ["//interfaces:shared"],
)

cc_fory_library(
    name = "greeter_cc",
    deps = [":greeter"],                  # the closure of deps is generated with it
)

py_fory_library(
    name = "greeter_py",
    deps = [":greeter"],
)
```

Like `cc_proto_library` / `py_proto_library`, the bindings of every schema are
generated **exactly once** (through an aspect applied to each `fory_library`
of the dependency closure), no matter how many `cc_fory_library` /
`py_fory_library` targets depend on it.

Generated C++ bindings are header only; headers mirror the `.fdl` path and are
included the way protobuf headers are
(`#include "interfaces/greeter/greeter.fory.h"`). Generated Python modules are
imported by their dotted path (`from interfaces.greeter import greeter_fory`),
like protobuf's `*_pb2` modules.

## Example

`example/` contains two schema packages (`shared`, `greeter` - `greeter`
imports `shared` through an `import_roots` search root) plus round trip tests
in both languages:

```sh
bazel test //example/...
```

The generated bindings expose the Fory API directly:

```cpp
#include "example/interfaces/greeter/greeter.fory.h"

interfaces::greeter::Greeting greeting;
greeting.set_text("hello");
auto bytes = greeting.to_bytes();            // Result<vector<uint8_t>, Error>
```

```python
from example.interfaces.greeter import greeter_fory

greeting = greeter_fory.Greeting(text="hello")
decoded = greeter_fory.Greeting.from_bytes(greeting.to_bytes())
```

## Module naming

`foryc` derives the generated file name from the `package` statement, which
Bazel cannot know during the analysis phase.  rules_fory therefore derives the
module name from the **path** of the schema (mirroring protoc) and rewrites
the references that `foryc` emitted (`import` statements, `#include`
directives and qualified type annotations):

| schema path                   | C++ header                     | Python module           |
| ----------------------------- | ------------------------------ | ----------------------- |
| `interfaces/greeter/greeter.fdl` | `interfaces/greeter/greeter.fory.h` | `interfaces.greeter.greeter_fory` |

Consequences:

* every `.fdl` file must declare a unique `package` (same restriction as the
  `foryc` CLI, which generates one module per package);
* import statements are resolved relative to the importing file first and to
  the workspace root afterwards; `import_roots` declares additional search
  roots so the `.fdl` sources stay independent of where they live in the
  workspace.

## The `foryc` compiler

Code generation imports the `foryc` implementation of the
[`fory-compiler`](https://pypi.org/project/fory-compiler/) wheel.  The wheel is
fetched from PyPI through rules_python's pip extension (pinned in
`private/requirements_lock.txt`, currently `fory-compiler==1.7.7`) and runs
in-process on the hermetic Bazel Python toolchain like every other action -
nothing has to be installed on the host.  The first build needs network access
to PyPI (and GitHub, for the `@fory` C++ runtime archive).

## Runtimes

* C++: `@fory//cpp/fory/serialization:fory_serialization`, the upstream
  Apache Fory release archive (fetched by `MODULE.bazel`, which keeps the
  upstream BUILD files - `strip_include_prefix = "/cpp"` publishes the headers
  under `fory/...`, exactly what generated code includes).  Override with the
  `runtime` attribute of `cc_fory_library`.
* Python: `@fory_pip//pyfory` from the same pip hub as the compiler.  Override
  with the `runtime` attribute of `py_fory_library`.

## Testing

```sh
bazel test //...    # C++ and Python serialization round trips
```

The example covers a cross-package import (`greeter` imports `shared`) and
verifies the generated bindings end to end in both languages.

## Limitations / roadmap

* Code generation supports the `python` and `cpp` generators of `foryc`
  (`.py` modules and header-only `.h` files); other languages of `foryc` are
  not wired up yet.
* Python import paths currently assume schemas of the main workspace.
* The generated Python modules rely on PEP 420 namespace packages; the
  `--incompatible_default_to_explicit_init_py` flag in `.bazelrc` must be
  enabled (Bazel's auto-generated `__init__.py` files would shadow the
  mirrored packages of the generated-code directories).
