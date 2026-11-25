# A guide to Akashic

Akashic is a library of Forth modules for **MegaPad**. This guide is a
*Markdown* document, which File Explorer shows as a document: headings,
lists, quotes, code and pictures, with the text wrapped to the preview.

- [Notes](notes.md), another document
- [Pictures](#pictures), just below
- [The end](#the-end)

## Pictures

![An evening sky over two hills](sunset.qoi)

The picture above is sunset.qoi, from the same folder.

## Lists

1. Select a file in File Explorer.
2. Its preview shows it the way its kind is shown.
3. A link to a file selects that file and previews it.

- A bullet
  - inside another
    - and one more

## Quotes

> A quote with **strong** words and `code` in it.
>
> - and a list inside the quote

## Code

```
: SQUARE  ( n -- n*n )  DUP * ;
9 SQUARE .
```

---

## Reading

- The wheel scrolls a document three rows a turn.
- A link to a heading, such as [Lists](#lists), scrolls to it.
- A link to a file selects that file and shows it here.

## The end

Back to [the top](#a-guide-to-akashic), or see the [example](example.f) in
Forth.
