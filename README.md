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
├── MODULE.bazel                  # module definition + toolchain registration
├── fory/
│   ├── defs.bzl                  # public API (load from here)
│   ├── providers.bzl             # ForyInfo / ForyCcInfo / ForyPyInfo
│   ├── private/                  # rule implementations
│   │   ├── common.bzl                # naming + path helpers
│   │   ├── fory_library.bzl          # fory_library
│   │   ├── fory_codegen.bzl          # language codegen rule
│   │   ├── fory_cc_library.bzl       # cc_fory_library macro
│   │   └── fory_py_library.bzl       # py_fory_library macro
│   ├── toolchains/               # foryc toolchain + module extension
│   └── tools/                    # foryc wrapper (deterministic outputs)
├── third_party/
│   ├── fory/                     # vendored Fory 1.7.7 C++ runtime (cc_library)
│   └── pyfory/                   # vendored pyfory 1.7.7 runtime (py_library)
├── examples/                     # schemas + C++/Python round trip programs
└── tests/                        # unit / analysis / integration tests
```

## Usage

```python
# MODULE.bazel
bazel_dep(name = "rules_fory", version = "0.1.0")
```

```python
# BUILD.bazel
load("@rules_fory//fory:defs.bzl", "fory_library", "cc_fory_library", "py_fory_library")

fory_library(
    name = "person",
    srcs = ["person.fdl"],
    deps = [":address"],
)

cc_fory_library(
    name = "person_cc",
    deps = [":person"],
    runtime = "//third_party/fory:fory",   # or "@fory//:fory" from a fory module
)

py_fory_library(
    name = "person_py",
    deps = [":person"],
    runtime = "//third_party/pyfory:pyfory",
)
```

Generated C++ bindings are header only and include each other by module name
(`#include "examples_address.h"`); the directory with the headers is
published through the include path of the resulting `cc_library`.  Generated
Python modules are importable by module name (`import examples_person`)
because the module directory is added to `sys.path` via the `imports`
attribute of the resulting `py_library`.

## Example: serialization round trip

`examples` contains the schemas `address.fdl` / `person.fdl` plus two
programs that instantiate, serialize and deserialize them:

```sh
bazel run //examples:main_cc   # C++ + vendored Fory runtime
bazel run //examples:main_py   # Python + vendored pyfory runtime
```

```
person: name=Alice, age=30, address=No.1 Fory Road / Hangzhou
serialized 115 bytes: 01001c000f80ae7fe8...
deserialized: name=Alice, age=30, emails=2, city=Hangzhou
round trip ok
```

The generated bindings expose the Fory API directly:

```cpp
examples::person::Person person;
person.set_name("Alice");
auto bytes = person.to_bytes();                                   // Result<vector<uint8_t>, Error>
auto restored = examples::person::Person::from_bytes(*bytes); // Result<Person, Error>
```

```python
from examples_person import Person

person = Person(name="Alice", age=30)
data = person.to_bytes()
restored = Person.from_bytes(data)
```

## Module naming

`foryc` derives the generated file name from the `package` statement, which
Bazel cannot know during the analysis phase.  rules_fory therefore derives the
module name from the **path** of the schema and rewrites the references that
`foryc` emitted (`import` statements, `#include` directives and qualified type
annotations):

| schema path           | FDL package       | module name       |
| --------------------- | ----------------- | ----------------- |
| `examples/person.fdl` | `examples.person` | `examples_person` |

Consequences:

* every `.fdl` file must declare a unique `package` (same restriction as the
  `foryc` CLI, which generates one module per package);
* import statements are resolved relative to the importing file first and to
  the workspace root afterwards, so `import "examples/address.fdl";` works
  from any package.

## The `foryc` compiler

Code generation calls the `foryc` binary shipped by the `fory-compiler` wheel
(`pip install fory-compiler`).  The module extension in
`fory/toolchains/extensions.bzl` locates it in this order:

1. `foryc.configure(foryc = "/path/to/foryc")` in `MODULE.bazel`
2. `$FORYC` (`bazel build --repo_env=FORYC=/path/to/foryc`)
3. `which foryc`

The default toolchain is a thin launcher around the local installation.  For a
hermetic build, define your own toolchain and register it before the default
one:

```python
load("@rules_fory//fory/toolchains:foryc_toolchain.bzl", "foryc_toolchain")

foryc_toolchain(
    name = "my_foryc_impl",
    foryc = "@fory_pip//:foryc",
)

toolchain(
    name = "my_foryc",
    toolchain = ":my_foryc_impl",
    toolchain_type = "@rules_fory//fory/toolchains:foryc_toolchain_type",
)
```

## Vendored runtimes

`third_party/fory` contains the C++ runtime of Apache Fory 1.7.7
(`cpp/fory` of the upstream repository) and `third_party/pyfory` the
`pyfory` 1.7.7 wheel of CPython 3.11.  Both are exposed as plain Bazel
libraries so the examples and tests run without any system installation:

* `//third_party/fory:fory` – `cc_library` publishing `fory/...` headers
  (upstream `strip_include_prefix = "/cpp"`).
* `//third_party/pyfory:pyfory` – `py_library` publishing the `pyfory`
  package (requires the CPython 3.11 toolchain, which rules_python pins as
  default).

To upgrade, replace the trees with the sources of the new release; no BUILD
changes are required as long as the include layout is unchanged.

## Testing

```sh
bazel test //tests/...       # unit + analysis + integration tests
bazel build //examples/...   # generate C++/Python bindings
```

The suite covers the wrapper tool (module naming and rewriting), the providers
and the generated code, including runtime round trips in both languages:

* `tests/unit` – `foryc_tool.py` unit tests;
* `tests/analysis` – analysis-time checks of `ForyInfo`, `CcInfo`, `PyInfo`;
* `tests/integration` – codegen output, C++/Python runtime round trips.

## Limitations / roadmap

* Code generation supports the `python` and `cpp` generators of `foryc`
  (`.py` modules and header-only `.h` files); other languages of `foryc` are
  not wired up yet.
* FDL schemas in external repositories are supported for C++; Python import
  paths currently assume schemas of the main workspace.
* Bazel 8.x is not verified yet; the rules target Bazel 9.2.
