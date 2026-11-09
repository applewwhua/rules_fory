"""Public API of rules_fory.

```python
load("@rules_fory//fory:defs.bzl", "fory_library", "cc_fory_library", "py_fory_library")
```
"""

load(
    "//fory:providers.bzl",
    _ForyCcInfo = "ForyCcInfo",
    _ForyInfo = "ForyInfo",
    _ForyPyInfo = "ForyPyInfo",
)
load("//fory/private:fory_cc_library.bzl", _cc_fory_library = "cc_fory_library")
load("//fory/private:fory_library.bzl", _fory_library = "fory_library")
load("//fory/private:fory_py_library.bzl", _py_fory_library = "py_fory_library")

ForyInfo = _ForyInfo
ForyCcInfo = _ForyCcInfo
ForyPyInfo = _ForyPyInfo

fory_library = _fory_library
cc_fory_library = _cc_fory_library
py_fory_library = _py_fory_library
