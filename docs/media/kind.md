# akashic-media-kind — what kind of thing a file is

```forth
REQUIRE media/kind.f
```

`MEDIA-KIND ( prefix-a prefix-u name-a name-u -- kind )` looks at a file's
first bytes, then its name. A caller passes at most `MEDIA-SNIFF-BYTES`
(512) first bytes, or the whole file when it is shorter. A viewer uses the
kind to choose how to show a file, and to say what a file is even when it
cannot show it yet. `MEDIA-KIND-NAME ( kind -- a u )` is what to call a kind
in a viewer, such as "QOI picture".

## Rules, in order

1. **Signatures.** Each kind with one is decided by its first bytes alone,
   so a misnamed picture is still a picture.

   | Kind | Signature |
   |---|---|
   | `MEDIA-K-QOI` | `qoif` |
   | `MEDIA-K-PNG` | `89 50 4E 47 0D 0A 1A 0A` |
   | `MEDIA-K-JPEG` | `FF D8 FF` |
   | `MEDIA-K-GIF` | `GIF87a` or `GIF89a` |
   | `MEDIA-K-WAV` | `RIFF`, four bytes, `WAVE` |
   | `MEDIA-K-BMP` | `BM` with a known header size (12, 40, 52, 56, 108 or 124) at offset 14 |

2. **Text.** Valid UTF-8 with no NUL is text. A character the end of the
   prefix cut off does not count against it; a byte that never starts a
   character does. An empty file is text.
3. **HTML.** Text that starts, after a byte order mark and white space, with
   `<!doctype html` or `<html` in any case, or text whose name ends in
   `.html` or `.htm` in any case, is `MEDIA-K-HTML`.
4. **Markdown.** Other text whose name ends in `.md` or `.markdown` in any
   case is `MEDIA-K-MARKDOWN`. Otherwise it is `MEDIA-K-TEXT`.
5. Anything else is `MEDIA-K-BINARY`.
