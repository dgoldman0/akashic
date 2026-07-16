# Bounded readable-text projection

`akashic/markup/readable-text.f` projects inert UTF-8 plain text or a strict
HTML subset into caller-owned text storage. It allocates no DOM and has no
script, style, fetch, or active-content path.

```forth
REQUIRE markup/readable-text.f

source-a source-u destination-a destination-cap RTEXT-PLAIN
source-a source-u destination-a destination-cap RTEXT-HTML
```

Both operations return `( text-u status )`. The source is limited to
`RTEXT-SOURCE-MAX` (128 KiB) and must be valid UTF-8. The caller supplies the
exact output capacity; non-empty source and destination spans must not
overlap. On success, ASCII whitespace is folded to one U+0020 and trimmed,
while all other UTF-8 bytes are preserved. On failure, the returned usable
length is zero and the destination must be treated as scratch because it may
contain a partial projection.

`RTEXT-HTML` uses a 64-level tag stack. It accepts ordinary start and end
tags, quoted attributes, comments, a doctype, void elements, and self-closing
tags. It treats `script` and `style` bodies as raw text and removes those
subtrees together with `nav`, `header`, `footer`, and `aside`. Block elements
produce whitespace boundaries rather than concatenating adjacent words.

The decoder accepts `amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`, and decimal or
hexadecimal Unicode scalar references. An unknown named entity returns
`RTEXT-S-UNSUPPORTED`; malformed markup, UTF-8, numeric references, NUL,
surrogates, and out-of-range scalars return `RTEXT-S-INVALID`. Exhausting the
tag stack, source bound, or destination capacity returns
`RTEXT-S-CAPACITY`.

The status domain is `RTEXT-S-OK`, `RTEXT-S-INVALID`,
`RTEXT-S-CAPACITY`, and `RTEXT-S-UNSUPPORTED`. It is deliberately independent
of Streams or any network media-type policy. A consumer that needs a
transactional durable result should project into its own candidate and commit
only after `RTEXT-S-OK`; the Streams V1 page snapshot does exactly that.

This projector is not an HTML5 browser, DOM, sanitizer for later HTML
re-emission, accessibility tree, or proof that source content is trustworthy.
Its output is plain text under one reviewed bounded contract.

Run its deterministic contracts with:

```sh
python3 local_testing/akashic_tui.py smoke --profile readable-text-contracts
```
