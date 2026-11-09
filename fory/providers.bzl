"""Public providers of rules_fory.

`ForyInfo` is the language independent description of a set of Fory IDL
(`.fdl`) files.  It plays the same role as `ProtoInfo` does for
`proto_library`: it carries the transitive set of schema files plus the
include roots required to resolve `import` statements.
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

ForyCcInfo = provider(
    doc = "Extra information about generated C++ (header only) sources.",
    fields = {
        "files": "depset[File]: generated header files.",
        "include_dir": "str: package relative include directory.",
    },
)

ForyPyInfo = provider(
    doc = "Extra information about generated Python modules.",
    fields = {
        "files": "depset[File]: generated `.py` files.",
        "import_path": "str: package relative directory holding the modules.",
    },
)
