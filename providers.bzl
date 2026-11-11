"""Public providers of the Fory FDL rules.

`ForyInfo` is the language independent description of a set of Fory IDL
(`.fdl`) files.  It plays the same role as `ProtoInfo` does for
`proto_library`: it carries the transitive set of schema files plus the
include roots required to resolve `import` statements.

The language specific information (generated C++ headers, generated Python
modules) is attached to the same targets by the `fory_cc_aspect` /
`fory_py_aspect` aspects as `CcInfo` / `PyInfo`, exactly like the protobuf
rules do it - see `cc_fory_library` and `py_fory_library`.
"""

ForyInfo = provider(
    doc = "Describes a Fory IDL (`.fdl`) target and its transitive closure.",
    fields = {
        "direct_sources": "depset[File]: the `.fdl` files declared by this target.",
        "transitive_sources": "depset[File]: direct sources plus the closure of `deps`.",
        "import_roots": "depset[str]: `-I` roots needed to resolve imports of the closure.",
        "descriptor_set": "File: JSON description of the schema closure.",
        "target_label": "str: label of the target that produced this provider.",
    },
)
