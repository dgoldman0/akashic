# akashic-pdf-lexer — PDF tokens and values

The tokens and values of PDF's syntax (PDF 32000-1, section 7.2 and 7.3),
read as spans of the caller's bytes. The lexer never copies or keeps what it
reads, so a value is only as long-lived as the bytes it points into.

```forth
REQUIRE pdf/lexer.f
```

`PROVIDED akashic-pdf-lexer`. It depends on nothing.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-TOKEN` | `( a u -- a' u' ta tu type )` | The next token, and the input after it. |
| `PDF-VALUE` | `( a u -- a' u' va vu type )` | The next whole value: an array, dictionary or reference as one span. |
| `PDF-OPERAND` | `( a u -- a' u' va vu type )` | The same where no reference can be, as in a content stream or a CMap: integers stay integers without looking ahead for an `R`. |
| `PDF-INT` | `( va vu -- n )` | An integer's value, or a real's whole part. |
| `PDF-FIXED` | `( va vu -- f )` | A number times 65,536, to five fraction digits. |
| `PDF-REF@` | `( va vu -- num gen )` | A reference's object and generation numbers. |
| `PDF-NAME=` | `( va vu name-a name-u -- flag )` | Whether a name, with its slash and any `#xx` codes, is `name`. |
| `PDF-DICT@` | `( key-a key-u da du -- va vu type )` | A dictionary's value for a key, or `0 0 PDF-T-END`. |
| `PDF-ARRAY-N` | `( aa au -- n )` | How many values an array holds. |
| `PDF-ARRAY@` | `( i aa au -- va vu type )` | An array's value at index `i`, from 0, or `0 0 PDF-T-END`. |
| `PDF-STRING` | `( va vu type dst cap -- u )` | A string's bytes, at most `cap` written; `u` is its whole length. |

A name given to `PDF-NAME=` or `PDF-DICT@` has no slash.

## Types

| Type | Is |
|---|---|
| `PDF-T-END` | no more input, or no such value |
| `PDF-T-INT`, `PDF-T-REAL` | a number |
| `PDF-T-NAME` | a name, its span starting at its slash |
| `PDF-T-STRING`, `PDF-T-HEX` | a literal or hex string, with its delimiters |
| `PDF-T-ARRAY`, `PDF-T-DICT` | a whole array or dictionary (values only) |
| `PDF-T-KEYWORD` | `true`, `false`, `null`, `obj`, `R`, a content operator, `{` or `}` |
| `PDF-T-REF` | `num gen R` (values only) |
| `PDF-T-OPEN-ARRAY` ... `PDF-T-CLOSE-DICT` | `[`, `]`, `<<`, `>>` (tokens only) |
| `PDF-T-BAD` | bytes that are no token, or a value the input ends inside |

White space and comments between tokens are skipped. A literal string's
escapes, octal codes and line ends, and a hex string's white space and odd
last digit, follow section 7.3.4. An integer followed by another and `R` is a
reference; any other run of integers stays integers.

## Cost

`PDF-VALUE` and `PDF-OPERAND` pass over a whole array or dictionary byte by
byte, following only its strings, comments and nesting, without making
tokens of what lies between; the caller reads inside it only when it needs
to. `PDF-OPERAND` also spares `PDF-VALUE`'s look at the two tokens after
an integer, which can only find a reference in an object. A hex string's
digits are read through a table.

The words keep their state on the stack, so a caller may read one value
while it reads another. The few scratch variables they use hold nothing
between calls.
