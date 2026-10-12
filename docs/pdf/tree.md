# akashic-pdf-tree — PDF number trees and name trees

A number tree (PDF 32000-1, section 7.9.7) maps integers to values, a name
tree (section 7.9.6) strings to values. A structure's parent tree and a
document's page labels are number trees; its named destinations are a name
tree. `pdf/struct.f` and `pdf/navigate.f` look keys up through this module.

```forth
REQUIRE pdf/tree.f
```

`PROVIDED akashic-pdf-tree`. It depends on `pdf/lexer.f`, `pdf/filter.f` and
`pdf/file.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-NUMS@` | `( key va vu type file -- obj va' vu' type' status )` | `key`'s value in the number tree whose root is the value `va vu`. |
| `PDF-NAMES@` | `( ka ku va vu type file -- obj va' vu' type' status )` | The value of the key whose bytes are `ka ku` in the name tree whose root is `va vu`. |

The result has `PDF-RESOLVE`'s shape: the object holding the value, to give
back with `PDF-OBJ-FREE`, or 0 when the root holds it inline; the value, or
`0 0 PDF-T-END` for a key the tree does not hold; and a status, `PDF-S-OK`,
or `PDF-S-MEMORY` when the key was not found and memory was refused on the
way.

## The walk

The root is followed through a reference. A node holds its pairs of keys
and values in `/Nums` or `/Names`, or its kids, whose `/Limits` hold the
least and greatest keys below them; each array may itself lie behind a
reference. From a node with `/Kids`, the walk reads the kids in order and
goes down into the first whose limits hold the key. In a node with pairs
it searches all of them, so a key is found even when a writer left the
keys out of order. A name tree's keys are strings, read as their bytes and
compared byte by byte.

A node or kid that cannot be read holds no keys. The walk goes down
through no more nodes than the file has objects, so a tree that loops
ends.

## Cost

A lookup reads the root, one kid at each level up to the one whose limits
hold the key, and the pairs of one leaf, decoding each name tree key it
compares. Memory for decoded keys comes from the file's memory source and is
given back after each lookup. One call runs at a time.
