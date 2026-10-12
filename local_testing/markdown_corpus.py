#!/usr/bin/env python3
"""Random Markdown documents for comparing the reader with markdown-it-py.

The documents mix every block and inline construct the reader takes, nested
and adjacent in ways that exercise CommonMark's rules: lazy lines, loose and
tight lists, delimiter runs beside punctuation, links in emphasis and
emphasis in links, entities, escapes, raw HTML and GitHub tables.

They avoid the few places where markdown-it-py 2.2.0 and the CommonMark
reference parser, which the reader follows, disagree:

- a link that holds a picture whose text holds a link, which markdown-it
  shows as a link and the reference parser does not;
- a link left open at the very end of a paragraph, as in ``[a](``;
- destinations that markdown-it refuses as unsafe (javascript:, data:);
- percent signs and non-ASCII host names in autolinks, which markdown-it
  shows decoded;
- reference labels that differ only in non-ASCII case;
- control characters, and punctuation that Unicode added after markdown-it's
  table;
- tables inside quotes and lists, and indented lines after a table;
- lazy lines in quotes, where the two close quotes and code differently,
  and a table right after a quote or list, whose rows would be lazy lines;
- HTML blocks inside lists, which markdown-it ends at a blank line;
- emphasis whose delimiters cross a pair already matched, where markdown-it
  2.2.0 can match across it (rare in this corpus; see the test's notes);
- link reference definitions inside lists, which markdown-it counts as a
  block when it decides whether the list is loose, and the reference parser
  does not.

The reference parser reads no tables, so only the markdown-it documents have
them.
"""

from __future__ import annotations

import random

WORDS = (
    "alpha", "beta", "gamma", "delta", "word", "text", "more", "some", "x",
    "naïve", "café", "日本", "über", "emoji😀", "a1", "foo", "bar", "baz",
)
PUNCT = (".", ",", "!", "?", ";", ":", "-", "(", ")", "\"", "'", "…", "«", "»", "—")
LABELS = ("one", "Two", "three four", "five", "Six")


class Generator:
    """Documents for the reference parser, or, with MARKDOWN_IT, documents
    that also hold GitHub tables and avoid where markdown-it-py 2.2.0 differs
    from the reference parser."""

    def __init__(self, seed: int, *, markdown_it: bool = False) -> None:
        self.r = random.Random(seed)
        self.markdown_it = markdown_it

    def chance(self, p: float) -> bool:
        return self.r.random() < p

    def word(self) -> str:
        return self.r.choice(WORDS)

    def inline(self, depth: int = 0, picture: bool = False) -> str:
        parts = []
        for _ in range(self.r.randint(1, 6)):
            parts.append(self.atom(depth, picture))
            parts.append(self.r.choice((" ", " ", " ", "", "  ")))
        return "".join(parts).strip() or "word"

    def atom(self, depth: int, picture: bool = False) -> str:
        r = self.r
        choice = r.randint(0, 30)
        # markdown-it lets a link hold a picture that holds a link, which the
        # reference parser does not, so a picture's text holds no link.
        if picture and self.markdown_it and 15 <= choice < 21:
            choice = 0
        if depth > 2 or choice < 10:
            word = self.word()
            if self.chance(0.2):
                word += r.choice(PUNCT)
            if self.chance(0.1):
                word = r.choice(PUNCT) + word
            return word
        if choice < 13:
            mark = r.choice(("*", "_", "**", "__", "***"))
            inner = self.inline(depth + 1, picture)
            if self.chance(0.15):
                return mark + inner
            if self.chance(0.1):
                return inner + mark
            return f"{mark}{inner}{mark}"
        if choice < 15:
            ticks = r.choice(("`", "``"))
            body = r.choice(("code", " a ", "x `y` z", "  ", "a  b", "*not*"))
            if ticks == "`" and "`" in body:
                ticks = "``"
            return f"{ticks}{body}{ticks}"
        if choice < 18:
            dest = r.choice(("http://example.com/a", "b.md", "#heading", "<a b>",
                             "x(y)", "/path/to\\_file", "c%20d", "über.md", ""))
            title = r.choice(("", ' "title"', " 'title'", " (title)"))
            bang = "!" if self.chance(0.25) else ""
            text = self.inline(depth + 1, picture or bool(bang)) if self.chance(0.8) else ""
            return f"{bang}[{text}]({dest}{title})"
        if choice < 20:
            label = r.choice(LABELS)
            text = self.inline(depth + 1, picture)
            form = r.randint(0, 2)
            if form == 0:
                return f"[{text}][{label}]"
            if form == 1:
                return f"[{label}][]"
            return f"[{label}]"
        if choice < 21:
            return r.choice(("<http://a.b/c>", "<mailto:a@b.c>", "<x@y.com>",
                             "<https://e.org/p?q=1&r=2>", "<a+b:c>"))
        if choice < 22:
            return r.choice(("<span>", "</span>", "<b class=\"x\">", "<!-- c -->",
                             "<br/>", "<?pi ?>", "<a href='x'>", "<x y=z>"))
        if choice < 24:
            return r.choice(("&amp;", "&copy;", "&#35;", "&#x22;", "&nbsp;", "&foo;",
                             "&#0;", "&ngE;", "&AMP;", "&#X41;"))
        if choice < 26:
            return "\\" + r.choice("*_`[]#!<&\\.-+a")
        if choice < 27:
            return r.choice(("[", "]", "![", "*", "_", "**", "!"))
        return self.word()

    def paragraph(self) -> list[str]:
        lines = [self.inline() for _ in range(self.r.randint(1, 3))]
        if len(lines) > 1 and self.chance(0.3):
            lines[0] += self.r.choice(("  ", "\\"))
        return lines

    def block(self, depth: int, top: bool) -> list[str]:
        r = self.r
        choice = r.randint(0, 24)
        if choice < 7 or depth > 3:
            return self.paragraph()
        if choice < 9:
            level = r.randint(1, 6)
            closing = r.choice(("", "", " #", " ###", "#"))
            return ["#" * level + " " + self.inline() + closing]
        if choice < 10:
            return [self.inline(), r.choice(("===", "---", "= =", "-- -"))]
        if choice < 11:
            return [r.choice(("---", "***", "___", "- - -", "* * *"))]
        if choice < 13:
            fence = r.choice(("```", "~~~", "````"))
            info = r.choice(("", "python", "forth x", "`bad"))
            body = [r.choice(("code line", "  indented", "\ttab\there", "", "x = 1"))
                    for _ in range(r.randint(0, 3))]
            lines = [fence + info] + body
            if self.chance(0.9):
                lines.append(fence)
            return lines
        if choice < 14:
            return ["    " + r.choice(("code", "a\tb", "x")) for _ in range(r.randint(1, 3))]
        if choice < 16:
            inner = self.blocks(depth + 1, False)
            out = []
            for line in inner:
                if line and out and not self.markdown_it and self.chance(0.1):
                    out.append(line)  # a lazy line
                else:
                    out.append(("> " + line) if line else ">")
            return out
        if choice < 19:
            return self.list(depth)
        if choice < 20 and (top or not self.markdown_it):
            return [r.choice(("<div>", "<div class=\"a\">", "<!-- comment", "<table>",
                              "<pre>", "<?php", "<custom-tag>")),
                    r.choice(("text", "*not emphasis*", "more -->", "?>", "</pre>")),
                    r.choice(("</div>", "", "-->"))]
        if choice < 22 and (top or not self.markdown_it):
            label = r.choice(LABELS)
            dest = r.choice(("http://ref.example", "<ref dest>", "local.md", "/r"))
            title = r.choice(("", ' "Title"', " 'T'"))
            return [f"[{label}]: {dest}{title}"]
        if choice < 23 and top and self.markdown_it:
            columns = r.randint(1, 3)
            head = " | ".join(self.word() for _ in range(columns))
            rule = " | ".join(r.choice(("---", ":--", "--:", ":-:")) for _ in range(columns))
            if self.chance(0.5):
                head, rule = f"| {head} |", f"| {rule} |"
            rows = [" | ".join(self.word() for _ in range(columns))
                    for _ in range(r.randint(0, 2))]
            return [head, rule] + rows
        return self.paragraph()

    def list(self, depth: int) -> list[str]:
        r = self.r
        ordered = self.chance(0.4)
        start = r.choice((1, 1, 0, 3, 9, 10))
        bullet = r.choice("-+*")
        delimiter = r.choice(".)")
        out = []
        loose = self.chance(0.3)
        for number in range(start, start + r.randint(1, 4)):
            marker = f"{number}{delimiter}" if ordered else bullet
            width = len(marker) + 1
            if self.chance(0.08):
                out.append(marker)
                continue
            inner = self.blocks(depth + 1, False)
            for position, line in enumerate(inner):
                if position == 0:
                    out.append(f"{marker} {line}")
                else:
                    out.append((" " * width + line) if line else "")
            if loose:
                out.append("")
        return out

    def blocks(self, depth: int, top: bool) -> list[str]:
        out = []
        for _ in range(self.r.randint(1, 3 if depth else 6)):
            # Usually a blank line between blocks; sometimes none, so a
            # block may interrupt or continue the one before.  markdown-it
            # ends a link reference definition at its line, so a line after
            # one may start what could not interrupt a paragraph; the
            # reference parser reads the definition as a paragraph first.
            block = self.block(depth, top)
            if out and (self.chance(0.85) or (self.markdown_it and (
                    out[-1].startswith("[") or "|" in block[0]))):
                out.append("")
            out.extend(block)
        return out

    def document(self) -> str:
        lines = self.blocks(0, True)
        text = "\n".join(lines)
        if self.chance(0.7):
            text += "\n"
        return text


def documents(seed: int, count: int, *, markdown_it: bool = False) -> list[str]:
    generator = Generator(seed, markdown_it=markdown_it)
    return [generator.document() for _ in range(count)]


class TableGenerator:
    """Documents built around GitHub tables, with only the simple inline text
    markdown-it-py and the reference parser read alike."""

    def __init__(self, seed: int) -> None:
        self.r = random.Random(seed)

    def cell(self) -> str:
        r = self.r
        return r.choice((
            "a", "word", "x y", "café", "`code`", "`a|b`", "a \\| b", "*em*",
            "**strong**", "[link](b.md)", "", "日本", "1", "-", ":x",
        ))

    def text(self) -> str:
        r = self.r
        return " ".join(r.choice(("alpha", "beta", "`c`", "*d*", "e | f", "[g](h)", "i"))
                        for _ in range(r.randint(1, 5)))

    def table(self) -> list[str]:
        r = self.r
        columns = r.randint(1, 4)
        edges = r.choice(("both", "both", "none", "left", "right"))

        def row(cells: list[str]) -> str:
            body = r.choice((" | ", "|", " |", "| ")).join(cells)
            if edges in ("both", "left"):
                body = "| " + body
            if edges in ("both", "right"):
                body = body + " |"
            return body

        # A header starting "- " would start a list item first.
        head = row([self.cell().lstrip("-") or "h" for _ in range(columns)])
        rule_columns = columns if self.r.random() < 0.85 else columns + r.choice((-1, 1))
        rule = row([r.choice(("---", ":--", "--:", ":-:", "-", "------"))
                    for _ in range(max(rule_columns, 1))])
        if columns == 1 and edges == "none":
            rule = r.choice(("---", "|---|", "--- |"))
        rows = [row([self.cell() for _ in range(r.randint(1, columns + 1))])
                for _ in range(r.randint(0, 3))]
        return [head, rule] + rows

    def block(self) -> list[str]:
        r = self.r
        choice = r.randint(0, 9)
        if choice < 4:
            return self.table()
        if choice < 7:
            return [self.text() for _ in range(r.randint(1, 3))]
        if choice < 8:
            return ["## " + self.text()]
        if choice < 9:
            return ["- " + self.text(), "- " + self.text()]
        return ["```", "a | b", "```"]

    def document(self) -> str:
        out: list[str] = []
        for _ in range(self.r.randint(1, 5)):
            block = self.block()
            # A table may interrupt a paragraph; other blocks are apart.
            if out and (self.r.random() < 0.75 or not out[-1].startswith(("|", "a", "b", "`", "*", "e", "[", "i"))):
                out.append("")
            out.extend(block)
        return "\n".join(out) + "\n"


def table_documents(seed: int, count: int) -> list[str]:
    generator = TableGenerator(seed)
    return [generator.document() for _ in range(count)]


# Documents written by hand for constructs random ones seldom reach.
HANDWRITTEN = (
    "",
    "\n\n\n",
    "one line",
    "a\r\nb\r\n\r\nc\rd\r",
    "\ttab start\n\n-\tlist\n\n>\tquote\n\n    \tcode\n",
    "Title\n=====\n\nSub\n---\n\n# a #\n## b ##   \n### \\#\n####### seven\n#no\n",
    "* * *\n- - -\n___\n---a\n",
    "```\nunclosed fence\n\n  still code",
    "~~~ info ~~~\n~~~\n\n``` a`b\n```\n\n````\n```\n````\n",
    "    a\n\n\n    b\n  \n",
    "<div>\nhtml *here*\n\n*emphasis*\n\n<!-- a\n\nb -->\n\n<?x y ?>\n\n<!DOCTYPE html>\n\n<![CDATA[\nz\n]]>\n\n<script>\nq\n</script>\nafter\n\n<custom-x a=\"1\">\n\n<del>*x*</del>\n",
    "[r]: /url 'Title'\n[R]: /other\n\n[r] [R] [x][r] [r][] ![r]\n",
    "[a]:\n/next-line\n\"title\"\n\n[a]\n",
    "[bad]: /url title\n\n[bad]\n",
    "Setext after refs:\n[q]: /q\n===\n\n[q]\n",
    "- a\n- b\n\n- c\n\n1. one\n1. two\n\n3) three\n4) four\n\n10. ten\n11. eleven\n",
    "- a\n  - b\n    - c\n      - d\n\n  e\n",
    "> a\n> > b\n> > > c\nlazy\n\n> - x\n>   y\nz\n",
    "* \n  item after blank marker\n\n*\n\n-\n  x\n",
    "&amp; &copy; &Dcaron; &#35; &#x1F600; &#0; &#1234567; &nbsp;&nbsp;x &bogus; &ThisIsNotDefined;\n",
    "\\*not\\* \\_ \\# \\\\ \\a \\\n\\`x\\`\n",
    "a  \nb\\\nc   \nd\n",
    "`` ` `` ` `` ` ``x`` `  ` `a\nb`\n",
    "*a* _b_ **c** __d__ ***e*** _a_b_ *a*b* foo*bar* __a_b__ a**b**c\n",
    "*[link* here](u)* [a *b](c)* **[x](y)**\n",
    "<http://a.b/c?d=e&f> <a@b.cd> <ftp://x> <not a link> <a+b-c.d:e>\n",
    "<span title=\"a\nb\">x</span> <a/> <b><!-- c --></b> <?p ?> <!X y>\n",
    "![alt *em*](p.qoi)\n\n![](empty.qoi)\n\n![a](b) ![c](d)\n\n[![badge](b.png)](u)\n\n# ![h](i)\n",
    "[a](<b c> \"t\") [a](b 't') [a](b (t)) [a]( b ) [a](<>) [a]() [a](\\(x\\))\n",
    "Ünïcødé *ẞtraße* “quotes” — dash… 日本語 😀 «guillemets»\n",
    "line\twith\ttabs\n\n```\n\ta\tb\n  \tc\n```\n",
)
