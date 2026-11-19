"""Forth lines that take the whole heap, for tests of what a VFS does when
its cache cannot have another page.

The VFS cache takes its pages from the heap (akashic/utils/fs/vfs.f).  HOG
takes every block the heap will give, halving the request each time one is
refused, so the next page the cache asks for is refused; UNHOG gives the
blocks back.  A block holds the link to the one taken before it.
"""

HEAP_HOG_LINES = [
    "VARIABLE _HOG  0 _HOG !",
    ": HOG  ( -- )  1048576 BEGIN DUP 16 < 0= WHILE",
    "  DUP ALLOCATE IF DROP 2/ ELSE _HOG @ OVER ! _HOG ! THEN REPEAT DROP ;",
    ": UNHOG  ( -- )  BEGIN _HOG @ ?DUP WHILE DUP @ _HOG ! FREE REPEAT ;",
]
