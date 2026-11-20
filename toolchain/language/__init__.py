"""The core of the checker for Leviathan's language (a prototype).

The checker reads Forth source the way KDOS reads it, infers each
definition's stack effect from its body, compares the result with the
definition's stack comment, and follows kinds through the data and return
stacks.  ``docs/language/checker.md`` describes what it does and what is not
built yet.
"""
