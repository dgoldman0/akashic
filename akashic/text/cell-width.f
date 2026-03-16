\ =================================================================
\  cell-width.f — Unicode cell-width lookup for TUI
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CW- / _CW-
\  Depends on: (none — standalone data + lookup)
\
\  Given a Unicode codepoint, returns the number of terminal cells
\  it occupies: 0 (combining mark, control), 1 (normal), or
\  2 (wide — CJK ideographs, fullwidth forms, some emoji).
\
\  Based on Unicode 15.1 East Asian Width property + General
\  Category for zero-width characters.
\
\  Public API:
\    CW-WIDTH    ( cp -- n )    Cell width: 0, 1, or 2
\    CW-SWIDTH   ( addr u -- n ) String display width in cells
\ =================================================================

PROVIDED akashic-cell-width

REQUIRE utf8.f

\ =====================================================================
\  §1 — Zero-Width Ranges (combining marks, controls, format chars)
\ =====================================================================
\
\  Range table: pairs of (start, end) inclusive.  Sorted.
\  A codepoint in any of these ranges has width 0.

\ Each entry is 2 cells (16 bytes).  Binary search over the table.

: _CW-PAIR,  ( start end -- )  SWAP , , ;

CREATE _CW-ZERO-TBL
\ C0/C1 controls (except TAB, NL which callers handle before us)
  0x0000  0x001F  _CW-PAIR,
  0x007F  0x009F  _CW-PAIR,
\ Soft hyphen
  0x00AD  0x00AD  _CW-PAIR,
\ Combining Diacritical Marks and related blocks
  0x0300  0x036F  _CW-PAIR,    \ Combining Diacritical Marks
  0x0483  0x0489  _CW-PAIR,    \ Cyrillic combining
  0x0591  0x05BD  _CW-PAIR,    \ Hebrew combining
  0x05BF  0x05BF  _CW-PAIR,
  0x05C1  0x05C2  _CW-PAIR,
  0x05C4  0x05C5  _CW-PAIR,
  0x05C7  0x05C7  _CW-PAIR,
  0x0610  0x061A  _CW-PAIR,    \ Arabic combining
  0x064B  0x065F  _CW-PAIR,
  0x0670  0x0670  _CW-PAIR,
  0x06D6  0x06DC  _CW-PAIR,
  0x06DF  0x06E4  _CW-PAIR,
  0x06E7  0x06E8  _CW-PAIR,
  0x06EA  0x06ED  _CW-PAIR,
  0x0711  0x0711  _CW-PAIR,    \ Syriac
  0x0730  0x074A  _CW-PAIR,
  0x07A6  0x07B0  _CW-PAIR,    \ Thaana
  0x07EB  0x07F3  _CW-PAIR,    \ NKo
  0x07FD  0x07FD  _CW-PAIR,
  0x0816  0x0819  _CW-PAIR,    \ Samaritan
  0x081B  0x0823  _CW-PAIR,
  0x0825  0x0827  _CW-PAIR,
  0x0829  0x082D  _CW-PAIR,
  0x0859  0x085B  _CW-PAIR,    \ Mandaic
  0x0898  0x089F  _CW-PAIR,    \ Arabic Extended-B
  0x08CA  0x08E1  _CW-PAIR,    \ Arabic Extended-A
  0x08E3  0x0902  _CW-PAIR,
  0x093A  0x093A  _CW-PAIR,    \ Devanagari
  0x093C  0x093C  _CW-PAIR,
  0x0941  0x0948  _CW-PAIR,
  0x094D  0x094D  _CW-PAIR,
  0x0951  0x0957  _CW-PAIR,
  0x0962  0x0963  _CW-PAIR,
  0x0981  0x0981  _CW-PAIR,    \ Bengali
  0x09BC  0x09BC  _CW-PAIR,
  0x09C1  0x09C4  _CW-PAIR,
  0x09CD  0x09CD  _CW-PAIR,
  0x09E2  0x09E3  _CW-PAIR,
  0x09FE  0x09FE  _CW-PAIR,
  0x0A01  0x0A02  _CW-PAIR,    \ Gurmukhi
  0x0A3C  0x0A3C  _CW-PAIR,
  0x0A41  0x0A42  _CW-PAIR,
  0x0A47  0x0A48  _CW-PAIR,
  0x0A4B  0x0A4D  _CW-PAIR,
  0x0A51  0x0A51  _CW-PAIR,
  0x0A70  0x0A71  _CW-PAIR,
  0x0A75  0x0A75  _CW-PAIR,
  0x0A81  0x0A82  _CW-PAIR,    \ Gujarati
  0x0ABC  0x0ABC  _CW-PAIR,
  0x0AC1  0x0AC5  _CW-PAIR,
  0x0AC7  0x0AC8  _CW-PAIR,
  0x0ACD  0x0ACD  _CW-PAIR,
  0x0AE2  0x0AE3  _CW-PAIR,
  0x0AFA  0x0AFF  _CW-PAIR,
  0x0B01  0x0B01  _CW-PAIR,    \ Oriya
  0x0B3C  0x0B3C  _CW-PAIR,
  0x0B3F  0x0B3F  _CW-PAIR,
  0x0B41  0x0B44  _CW-PAIR,
  0x0B4D  0x0B4D  _CW-PAIR,
  0x0B55  0x0B56  _CW-PAIR,
  0x0B62  0x0B63  _CW-PAIR,
  0x0B82  0x0B82  _CW-PAIR,    \ Tamil
  0x0BC0  0x0BC0  _CW-PAIR,
  0x0BCD  0x0BCD  _CW-PAIR,
  0x0C00  0x0C00  _CW-PAIR,    \ Telugu
  0x0C04  0x0C04  _CW-PAIR,
  0x0C3C  0x0C3C  _CW-PAIR,
  0x0C3E  0x0C40  _CW-PAIR,
  0x0C46  0x0C48  _CW-PAIR,
  0x0C4A  0x0C4D  _CW-PAIR,
  0x0C55  0x0C56  _CW-PAIR,
  0x0C62  0x0C63  _CW-PAIR,
  0x0C81  0x0C81  _CW-PAIR,    \ Kannada
  0x0CBC  0x0CBC  _CW-PAIR,
  0x0CBF  0x0CBF  _CW-PAIR,
  0x0CC6  0x0CC6  _CW-PAIR,
  0x0CCC  0x0CCD  _CW-PAIR,
  0x0CE2  0x0CE3  _CW-PAIR,
  0x0D00  0x0D01  _CW-PAIR,    \ Malayalam
  0x0D3B  0x0D3C  _CW-PAIR,
  0x0D41  0x0D44  _CW-PAIR,
  0x0D4D  0x0D4D  _CW-PAIR,
  0x0D62  0x0D63  _CW-PAIR,
  0x0D81  0x0D81  _CW-PAIR,    \ Sinhala
  0x0DCA  0x0DCA  _CW-PAIR,
  0x0DD2  0x0DD4  _CW-PAIR,
  0x0DD6  0x0DD6  _CW-PAIR,
  0x0E31  0x0E31  _CW-PAIR,    \ Thai
  0x0E34  0x0E3A  _CW-PAIR,
  0x0E47  0x0E4E  _CW-PAIR,
  0x0EB1  0x0EB1  _CW-PAIR,    \ Lao
  0x0EB4  0x0EBC  _CW-PAIR,
  0x0EC8  0x0ECE  _CW-PAIR,
  0x0F18  0x0F19  _CW-PAIR,    \ Tibetan
  0x0F35  0x0F35  _CW-PAIR,
  0x0F37  0x0F37  _CW-PAIR,
  0x0F39  0x0F39  _CW-PAIR,
  0x0F71  0x0F7E  _CW-PAIR,
  0x0F80  0x0F84  _CW-PAIR,
  0x0F86  0x0F87  _CW-PAIR,
  0x0F8D  0x0F97  _CW-PAIR,
  0x0F99  0x0FBC  _CW-PAIR,
  0x0FC6  0x0FC6  _CW-PAIR,
  0x102D  0x1030  _CW-PAIR,    \ Myanmar
  0x1032  0x1037  _CW-PAIR,
  0x1039  0x103A  _CW-PAIR,
  0x103D  0x103E  _CW-PAIR,
  0x1058  0x1059  _CW-PAIR,
  0x105E  0x1060  _CW-PAIR,
  0x1071  0x1074  _CW-PAIR,
  0x1082  0x1082  _CW-PAIR,
  0x1085  0x1086  _CW-PAIR,
  0x108D  0x108D  _CW-PAIR,
  0x109D  0x109D  _CW-PAIR,
  0x1160  0x11FF  _CW-PAIR,    \ Hangul Jungseong + Jongseong (combining)
  0x135D  0x135F  _CW-PAIR,    \ Ethiopic combining
  0x1712  0x1714  _CW-PAIR,    \ Tagalog
  0x1732  0x1733  _CW-PAIR,    \ Hanunoo
  0x1752  0x1753  _CW-PAIR,    \ Buhid
  0x1772  0x1773  _CW-PAIR,    \ Tagbanwa
  0x17B4  0x17B5  _CW-PAIR,    \ Khmer
  0x17B7  0x17BD  _CW-PAIR,
  0x17C6  0x17C6  _CW-PAIR,
  0x17C9  0x17D3  _CW-PAIR,
  0x17DD  0x17DD  _CW-PAIR,
  0x180B  0x180F  _CW-PAIR,    \ Mongolian free variation selectors + vowel sep
  0x1885  0x1886  _CW-PAIR,    \ Mongolian combining
  0x18A9  0x18A9  _CW-PAIR,
  0x1920  0x1922  _CW-PAIR,    \ Limbu
  0x1927  0x1928  _CW-PAIR,
  0x1932  0x1932  _CW-PAIR,
  0x1939  0x193B  _CW-PAIR,
  0x1A17  0x1A18  _CW-PAIR,    \ Buginese
  0x1A1B  0x1A1B  _CW-PAIR,
  0x1A56  0x1A56  _CW-PAIR,    \ Tai Tham
  0x1A58  0x1A5E  _CW-PAIR,
  0x1A60  0x1A60  _CW-PAIR,
  0x1A62  0x1A62  _CW-PAIR,
  0x1A65  0x1A6C  _CW-PAIR,
  0x1A73  0x1A7C  _CW-PAIR,
  0x1A7F  0x1A7F  _CW-PAIR,
  0x1AB0  0x1ACE  _CW-PAIR,    \ Combining Diacritical Marks Extended
  0x1B00  0x1B03  _CW-PAIR,    \ Balinese
  0x1B34  0x1B34  _CW-PAIR,
  0x1B36  0x1B3A  _CW-PAIR,
  0x1B3C  0x1B3C  _CW-PAIR,
  0x1B42  0x1B42  _CW-PAIR,
  0x1B6B  0x1B73  _CW-PAIR,
  0x1B80  0x1B81  _CW-PAIR,    \ Sundanese
  0x1BA2  0x1BA5  _CW-PAIR,
  0x1BA8  0x1BA9  _CW-PAIR,
  0x1BAB  0x1BAD  _CW-PAIR,
  0x1BE6  0x1BE6  _CW-PAIR,    \ Batak
  0x1BE8  0x1BE9  _CW-PAIR,
  0x1BED  0x1BED  _CW-PAIR,
  0x1BEF  0x1BF1  _CW-PAIR,
  0x1C2C  0x1C33  _CW-PAIR,    \ Lepcha
  0x1C36  0x1C37  _CW-PAIR,
  0x1CD0  0x1CD2  _CW-PAIR,    \ Vedic Extensions
  0x1CD4  0x1CE0  _CW-PAIR,
  0x1CE2  0x1CE8  _CW-PAIR,
  0x1CED  0x1CED  _CW-PAIR,
  0x1CF4  0x1CF4  _CW-PAIR,
  0x1CF8  0x1CF9  _CW-PAIR,
  0x1DC0  0x1DFF  _CW-PAIR,    \ Combining Diacritical Marks Supplement
  0x200B  0x200F  _CW-PAIR,    \ Zero-width space, joiners, dir marks
  0x202A  0x202E  _CW-PAIR,    \ Bidi embedding controls
  0x2060  0x2064  _CW-PAIR,    \ Word joiner, invisible operators
  0x2066  0x206F  _CW-PAIR,    \ Bidi isolates + deprecated controls
  0x20D0  0x20F0  _CW-PAIR,    \ Combining Diacritical Marks for Symbols
  0xFE00  0xFE0F  _CW-PAIR,    \ Variation selectors (VS1–VS16)
  0xFE20  0xFE2F  _CW-PAIR,    \ Combining Half Marks
  0xFEFF  0xFEFF  _CW-PAIR,    \ BOM / zero-width no-break space
  0xFFF9  0xFFFB  _CW-PAIR,    \ Interlinear annotation anchors
  0x101FD 0x101FD _CW-PAIR,    \ Phaistos Disc combining
  0x102E0 0x102E0 _CW-PAIR,    \ Coptic Epact combining
  0x10376 0x1037A _CW-PAIR,    \ Old Permic combining
  0x10A01 0x10A03 _CW-PAIR,    \ Kharoshthi
  0x10A05 0x10A06 _CW-PAIR,
  0x10A0C 0x10A0F _CW-PAIR,
  0x10A38 0x10A3A _CW-PAIR,
  0x10A3F 0x10A3F _CW-PAIR,
  0x10AE5 0x10AE6 _CW-PAIR,    \ Manichaean
  0x10D24 0x10D27 _CW-PAIR,    \ Hanifi Rohingya
  0x10EAB 0x10EAC _CW-PAIR,    \ Yezidi
  0x10EFD 0x10EFF _CW-PAIR,    \ Arabic Extended-C
  0x10F46 0x10F50 _CW-PAIR,    \ Sogdian
  0x10F82 0x10F85 _CW-PAIR,    \ Old Uyghur
  0x11001 0x11001 _CW-PAIR,    \ Brahmi
  0x11038 0x11046 _CW-PAIR,
  0x11070 0x11070 _CW-PAIR,
  0x11073 0x11074 _CW-PAIR,
  0x1107F 0x11081 _CW-PAIR,    \ Kaithi
  0x110B3 0x110B6 _CW-PAIR,
  0x110B9 0x110BA _CW-PAIR,
  0x110C2 0x110C2 _CW-PAIR,
  0x11100 0x11102 _CW-PAIR,    \ Chakma
  0x11127 0x1112B _CW-PAIR,
  0x1112D 0x11134 _CW-PAIR,
  0x11173 0x11173 _CW-PAIR,    \ Mahajani
  0x11180 0x11181 _CW-PAIR,    \ Sharada
  0x111B6 0x111BE _CW-PAIR,
  0x111C9 0x111CC _CW-PAIR,
  0x111CF 0x111CF _CW-PAIR,
  0x1122F 0x11231 _CW-PAIR,    \ Khojki
  0x11234 0x11234 _CW-PAIR,
  0x11236 0x11237 _CW-PAIR,
  0x1123E 0x1123E _CW-PAIR,
  0x11241 0x11241 _CW-PAIR,
  0x112DF 0x112DF _CW-PAIR,    \ Khudawadi
  0x112E3 0x112EA _CW-PAIR,
  0x11300 0x11301 _CW-PAIR,    \ Grantha
  0x1133B 0x1133C _CW-PAIR,
  0x11340 0x11340 _CW-PAIR,
  0x11366 0x1136C _CW-PAIR,
  0x11370 0x11374 _CW-PAIR,
  0x11438 0x1143F _CW-PAIR,    \ Newa
  0x11442 0x11444 _CW-PAIR,
  0x11446 0x11446 _CW-PAIR,
  0x1145E 0x1145E _CW-PAIR,
  0x114B3 0x114B8 _CW-PAIR,    \ Tirhuta
  0x114BA 0x114BA _CW-PAIR,
  0x114BF 0x114C0 _CW-PAIR,
  0x114C2 0x114C3 _CW-PAIR,
  0x115B2 0x115B5 _CW-PAIR,    \ Siddham
  0x115BC 0x115BD _CW-PAIR,
  0x115BF 0x115C0 _CW-PAIR,
  0x115DC 0x115DD _CW-PAIR,
  0x11633 0x1163A _CW-PAIR,    \ Modi
  0x1163D 0x1163D _CW-PAIR,
  0x1163F 0x11640 _CW-PAIR,
  0x116AB 0x116AB _CW-PAIR,    \ Takri
  0x116AD 0x116AD _CW-PAIR,
  0x116B0 0x116B5 _CW-PAIR,
  0x116B7 0x116B7 _CW-PAIR,
  0x1171D 0x1171F _CW-PAIR,    \ Ahom
  0x11722 0x11725 _CW-PAIR,
  0x11727 0x1172B _CW-PAIR,
  0x1182F 0x11837 _CW-PAIR,    \ Dogra
  0x11839 0x1183A _CW-PAIR,
  0x1193B 0x1193C _CW-PAIR,    \ Dives Akuru
  0x1193E 0x1193E _CW-PAIR,
  0x11943 0x11943 _CW-PAIR,
  0x119D4 0x119D7 _CW-PAIR,    \ Nandinagari
  0x119DA 0x119DB _CW-PAIR,
  0x119E0 0x119E0 _CW-PAIR,
  0x11A01 0x11A0A _CW-PAIR,    \ Zanabazar Square
  0x11A33 0x11A38 _CW-PAIR,
  0x11A3B 0x11A3E _CW-PAIR,
  0x11A47 0x11A47 _CW-PAIR,
  0x11A51 0x11A56 _CW-PAIR,    \ Soyombo
  0x11A59 0x11A5B _CW-PAIR,
  0x11A8A 0x11A96 _CW-PAIR,
  0x11A98 0x11A99 _CW-PAIR,
  0x11C30 0x11C36 _CW-PAIR,    \ Bhaiksuki
  0x11C38 0x11C3D _CW-PAIR,
  0x11C3F 0x11C3F _CW-PAIR,
  0x11C92 0x11CA7 _CW-PAIR,    \ Marchen
  0x11CAA 0x11CB0 _CW-PAIR,
  0x11CB2 0x11CB3 _CW-PAIR,
  0x11CB5 0x11CB6 _CW-PAIR,
  0x11D31 0x11D36 _CW-PAIR,    \ Masaram Gondi
  0x11D3A 0x11D3A _CW-PAIR,
  0x11D3C 0x11D3D _CW-PAIR,
  0x11D3F 0x11D45 _CW-PAIR,
  0x11D47 0x11D47 _CW-PAIR,
  0x11D90 0x11D91 _CW-PAIR,    \ Gunjala Gondi
  0x11D95 0x11D95 _CW-PAIR,
  0x11D97 0x11D97 _CW-PAIR,
  0x11EF3 0x11EF4 _CW-PAIR,    \ Makasar
  0x11F00 0x11F01 _CW-PAIR,    \ Kawi
  0x11F36 0x11F3A _CW-PAIR,
  0x11F40 0x11F40 _CW-PAIR,
  0x11F42 0x11F42 _CW-PAIR,
  0x13440 0x13440 _CW-PAIR,    \ Egyptian Hieroglyphs format
  0x13447 0x13455 _CW-PAIR,
  0x16AF0 0x16AF4 _CW-PAIR,    \ Bassa Vah
  0x16B30 0x16B36 _CW-PAIR,    \ Pahawh Hmong
  0x16F4F 0x16F4F _CW-PAIR,    \ Miao
  0x16F8F 0x16F92 _CW-PAIR,
  0x16FE4 0x16FE4 _CW-PAIR,    \ Khitan combining
  0x1BC9D 0x1BC9E _CW-PAIR,    \ Duployan
  0x1CF00 0x1CF2D _CW-PAIR,    \ Znamenny Musical combining
  0x1CF30 0x1CF46 _CW-PAIR,
  0x1D167 0x1D169 _CW-PAIR,    \ Musical Symbols combining
  0x1D173 0x1D182 _CW-PAIR,
  0x1D185 0x1D18B _CW-PAIR,
  0x1D1AA 0x1D1AD _CW-PAIR,
  0x1D242 0x1D244 _CW-PAIR,    \ Combining Greek Musical
  0x1DA00 0x1DA36 _CW-PAIR,    \ Signwriting
  0x1DA3B 0x1DA6C _CW-PAIR,
  0x1DA75 0x1DA75 _CW-PAIR,
  0x1DA84 0x1DA84 _CW-PAIR,
  0x1DA9B 0x1DA9F _CW-PAIR,
  0x1DAA1 0x1DAAF _CW-PAIR,
  0xE0001 0xE0001 _CW-PAIR,    \ Language tag
  0xE0020 0xE007F _CW-PAIR,    \ Tag components
  0xE0100 0xE01EF _CW-PAIR,    \ Variation selectors supplement (VS17–VS256)
HERE CONSTANT _CW-ZERO-END

\ Number of zero-width range entries
_CW-ZERO-END _CW-ZERO-TBL - 2 CELLS / CONSTANT _CW-ZERO-N

\ =====================================================================
\  §2 — Wide (double-width) Ranges
\ =====================================================================
\
\  East Asian Width = W or F, plus selected emoji ranges.

CREATE _CW-WIDE-TBL
\ CJK Misc
  0x1100  0x115F  _CW-PAIR,    \ Hangul Choseong (leading consonants)
  0x231A  0x231B  _CW-PAIR,    \ Watch, Hourglass
  0x2329  0x232A  _CW-PAIR,    \ Angle brackets (CJK compat)
  0x23E9  0x23F3  _CW-PAIR,    \ Transport/map symbols
  0x23F8  0x23FA  _CW-PAIR,
  0x25FD  0x25FE  _CW-PAIR,    \ Medium small squares
  0x2614  0x2615  _CW-PAIR,    \ Umbrella, Hot beverage
  0x2648  0x2653  _CW-PAIR,    \ Zodiac signs
  0x267F  0x267F  _CW-PAIR,    \ Wheelchair
  0x2693  0x2693  _CW-PAIR,    \ Anchor
  0x26A1  0x26A1  _CW-PAIR,    \ High voltage
  0x26AA  0x26AB  _CW-PAIR,    \ Medium circles
  0x26BD  0x26BE  _CW-PAIR,    \ Soccer, Baseball
  0x26C4  0x26C5  _CW-PAIR,    \ Snowman, Sun behind cloud
  0x26CE  0x26CE  _CW-PAIR,    \ Ophiuchus
  0x26D4  0x26D4  _CW-PAIR,    \ No entry
  0x26EA  0x26EA  _CW-PAIR,    \ Church
  0x26F2  0x26F3  _CW-PAIR,    \ Fountain, Golf
  0x26F5  0x26F5  _CW-PAIR,    \ Sailboat
  0x26FA  0x26FA  _CW-PAIR,    \ Tent
  0x26FD  0x26FD  _CW-PAIR,    \ Fuel pump
  0x2702  0x2702  _CW-PAIR,    \ Scissors
  0x2705  0x2705  _CW-PAIR,    \ Check mark
  0x2708  0x270D  _CW-PAIR,    \ Airplane..writing hand
  0x270F  0x270F  _CW-PAIR,    \ Pencil
  0x2712  0x2712  _CW-PAIR,    \ Nib
  0x2714  0x2714  _CW-PAIR,    \ Heavy check
  0x2716  0x2716  _CW-PAIR,    \ Heavy X
  0x271D  0x271D  _CW-PAIR,    \ Latin cross
  0x2721  0x2721  _CW-PAIR,    \ Star of David
  0x2728  0x2728  _CW-PAIR,    \ Sparkles
  0x2733  0x2734  _CW-PAIR,    \ Eight spoked asterisk
  0x2744  0x2744  _CW-PAIR,    \ Snowflake
  0x2747  0x2747  _CW-PAIR,    \ Sparkle
  0x274C  0x274C  _CW-PAIR,    \ Cross mark
  0x274E  0x274E  _CW-PAIR,    \ Cross mark variant
  0x2753  0x2755  _CW-PAIR,    \ Question/exclamation ornaments
  0x2757  0x2757  _CW-PAIR,    \ Heavy exclamation
  0x2763  0x2764  _CW-PAIR,    \ Heart exclamation, Heart
  0x2795  0x2797  _CW-PAIR,    \ Heavy plus/minus/divide
  0x27A1  0x27A1  _CW-PAIR,    \ Black right arrow
  0x27B0  0x27B0  _CW-PAIR,    \ Curly loop
  0x27BF  0x27BF  _CW-PAIR,    \ Double curly loop
  0x2934  0x2935  _CW-PAIR,    \ Arrow curving up/down
  0x2B05  0x2B07  _CW-PAIR,    \ Arrows left/up/down
  0x2B1B  0x2B1C  _CW-PAIR,    \ Black/white large squares
  0x2B50  0x2B50  _CW-PAIR,    \ Star
  0x2B55  0x2B55  _CW-PAIR,    \ Heavy large circle
  0x3000  0x3000  _CW-PAIR,    \ Ideographic space
  0x3001  0x303E  _CW-PAIR,    \ CJK symbols and punctuation
  0x3041  0x3096  _CW-PAIR,    \ Hiragana
  0x3099  0x30FF  _CW-PAIR,    \ Hiragana/Katakana (combining marks through end)
  0x3105  0x312F  _CW-PAIR,    \ Bopomofo
  0x3131  0x318E  _CW-PAIR,    \ Hangul Compatibility Jamo
  0x3190  0x31E3  _CW-PAIR,    \ Kanbun + CJK Strokes
  0x31F0  0x321E  _CW-PAIR,    \ Katakana Extensions + Enclosed CJK
  0x3220  0x3247  _CW-PAIR,    \ Enclosed CJK
  0x3250  0x4DBF  _CW-PAIR,    \ CJK Compat → Yijing → CJK Unified start
  0x4E00  0xA48C  _CW-PAIR,    \ CJK Unified Ideographs + Yi Syllables
  0xA490  0xA4C6  _CW-PAIR,    \ Yi Radicals
  0xA960  0xA97C  _CW-PAIR,    \ Hangul Jamo Extended-A
  0xAC00  0xD7A3  _CW-PAIR,    \ Hangul Syllables
  0xF900  0xFAFF  _CW-PAIR,    \ CJK Compatibility Ideographs
  0xFE10  0xFE19  _CW-PAIR,    \ Vertical forms
  0xFE30  0xFE6B  _CW-PAIR,    \ CJK Compatibility Forms + Small Form Variants
  0xFF01  0xFF60  _CW-PAIR,    \ Fullwidth ASCII + punctuation
  0xFFE0  0xFFE6  _CW-PAIR,    \ Fullwidth cent..won
\ Supplementary planes
  0x16FE0 0x16FFF _CW-PAIR,    \ Ideographic Symbols / Tangut / Khitan components
  0x17000 0x187F7 _CW-PAIR,    \ Tangut
  0x18800 0x18CD5 _CW-PAIR,    \ Tangut Components + Khitan
  0x18D00 0x18D08 _CW-PAIR,    \ Tangut Supplement
  0x1AFF0 0x1AFFE _CW-PAIR,    \ Kana Extended-B
  0x1B000 0x1B122 _CW-PAIR,    \ Kana Supplement + Extended-A
  0x1B132 0x1B132 _CW-PAIR,
  0x1B150 0x1B152 _CW-PAIR,    \ Small Kana Extension
  0x1B155 0x1B155 _CW-PAIR,
  0x1B164 0x1B167 _CW-PAIR,
  0x1B170 0x1B2FB _CW-PAIR,    \ Nushu
  0x1F004 0x1F004 _CW-PAIR,    \ Mahjong tile
  0x1F0CF 0x1F0CF _CW-PAIR,    \ Playing card
  0x1F18E 0x1F18E _CW-PAIR,    \ AB button
  0x1F191 0x1F19A _CW-PAIR,    \ Squared CL..VS
  0x1F200 0x1F202 _CW-PAIR,    \ Enclosed ideographic supplement
  0x1F210 0x1F23B _CW-PAIR,
  0x1F240 0x1F248 _CW-PAIR,
  0x1F250 0x1F251 _CW-PAIR,
  0x1F260 0x1F265 _CW-PAIR,
  0x1F300 0x1F320 _CW-PAIR,    \ Misc Symbols and Pictographs (weather)
  0x1F32D 0x1F335 _CW-PAIR,    \ Food & plants
  0x1F337 0x1F37C _CW-PAIR,
  0x1F37E 0x1F393 _CW-PAIR,
  0x1F3A0 0x1F3CA _CW-PAIR,    \ Activity symbols
  0x1F3CF 0x1F3D3 _CW-PAIR,
  0x1F3E0 0x1F3F0 _CW-PAIR,    \ Buildings
  0x1F3F4 0x1F3F4 _CW-PAIR,    \ Black flag
  0x1F3F8 0x1F43E _CW-PAIR,    \ Sports..paw prints
  0x1F440 0x1F440 _CW-PAIR,    \ Eyes
  0x1F442 0x1F4FC _CW-PAIR,    \ Ear..videocassette
  0x1F4FF 0x1F53D _CW-PAIR,    \ Prayer beads..buttons
  0x1F54B 0x1F54E _CW-PAIR,    \ Kaaba..menorah..Candelabra..star crescent
  0x1F550 0x1F567 _CW-PAIR,    \ Clocks
  0x1F57A 0x1F57A _CW-PAIR,    \ Man dancing
  0x1F595 0x1F596 _CW-PAIR,    \ Middle finger, Vulcan salute
  0x1F5A4 0x1F5A4 _CW-PAIR,    \ Black heart
  0x1F5FB 0x1F64F _CW-PAIR,    \ Mount Fuji..person gestures
  0x1F680 0x1F6C5 _CW-PAIR,    \ Transport & map
  0x1F6CC 0x1F6CC _CW-PAIR,    \ Sleeping accommodation
  0x1F6D0 0x1F6D2 _CW-PAIR,    \ Place of worship..shopping cart
  0x1F6D5 0x1F6D7 _CW-PAIR,
  0x1F6DC 0x1F6DF _CW-PAIR,
  0x1F6EB 0x1F6EC _CW-PAIR,    \ Airplane departure/arrival
  0x1F6F4 0x1F6FC _CW-PAIR,    \ Scooter..roller skate
  0x1F7E0 0x1F7EB _CW-PAIR,    \ Colored circles/squares
  0x1F7F0 0x1F7F0 _CW-PAIR,
  0x1F90C 0x1F93A _CW-PAIR,    \ Hand gestures + sports
  0x1F93C 0x1F945 _CW-PAIR,
  0x1F947 0x1F9FF _CW-PAIR,    \ Awards..Nazar amulet
  0x1FA00 0x1FA53 _CW-PAIR,    \ Chess symbols
  0x1FA60 0x1FA6D _CW-PAIR,
  0x1FA70 0x1FA7C _CW-PAIR,    \ Clothing & accessories
  0x1FA80 0x1FA89 _CW-PAIR,    \ Game pieces
  0x1FA8F 0x1FAC6 _CW-PAIR,
  0x1FACE 0x1FADC _CW-PAIR,
  0x1FADF 0x1FAE9 _CW-PAIR,    \ Faces supplement
  0x1FAF0 0x1FAF8 _CW-PAIR,    \ Hand gestures supplement
  0x20000 0x2FFFD _CW-PAIR,    \ CJK Unified Ideographs Extension B–F
  0x30000 0x3FFFD _CW-PAIR,    \ CJK Extension G–I + unassigned
HERE CONSTANT _CW-WIDE-END

_CW-WIDE-END _CW-WIDE-TBL - 2 CELLS / CONSTANT _CW-WIDE-N

\ =====================================================================
\  §3 — Binary Search
\ =====================================================================

\ _CW-BSEARCH ( cp tbl n -- flag )
\   Binary search over sorted (start, end) pairs.
\   Returns true if cp falls within any range.
VARIABLE _CB-LO   VARIABLE _CB-HI   VARIABLE _CB-MID

: _CW-BSEARCH  ( cp tbl n -- flag )
    DUP 0= IF 2DROP DROP 0 EXIT THEN
    1- _CB-HI !
    0 _CB-LO !                        ( cp tbl )
    BEGIN
        _CB-LO @ _CB-HI @ > IF 2DROP 0 EXIT THEN
        _CB-LO @ _CB-HI @ + 2 / _CB-MID !
        _CB-MID @ 2 CELLS * OVER +    ( cp tbl entry )
        DUP @ >R                       \ R: start
        CELL+ @                        \ end
        2 PICK R@ >= 3 PICK ROT <= AND IF
            \ cp >= start AND cp <= end → found
            R> DROP 2DROP -1 EXIT
        THEN
        2 PICK R> < IF
            \ cp < start → search lower half
            _CB-MID @ 1- _CB-HI !
        ELSE
            \ cp > end → search upper half
            _CB-MID @ 1+ _CB-LO !
        THEN
    AGAIN ;

\ =====================================================================
\  §4 — Public API
\ =====================================================================

\ CW-WIDTH ( cp -- n )
\   Return 0, 1, or 2 cells for a Unicode codepoint.
: CW-WIDTH  ( cp -- n )
    \ Fast path: ASCII printable → 1
    DUP 0x20 >= OVER 0x7E <= AND IF DROP 1 EXIT THEN
    \ Check zero-width
    DUP _CW-ZERO-TBL _CW-ZERO-N _CW-BSEARCH IF DROP 0 EXIT THEN
    \ Check wide
    DUP _CW-WIDE-TBL _CW-WIDE-N _CW-BSEARCH IF DROP 2 EXIT THEN
    \ Default: 1 cell
    DROP 1 ;

\ CW-SWIDTH ( addr u -- n )
\   Display width of a UTF-8 string in terminal cells.
: CW-SWIDTH  ( addr u -- n )
    0 >R                               ( addr u  R: width )
    BEGIN DUP 0 > WHILE
        UTF8-DECODE                    ( cp addr' len' )
        ROT CW-WIDTH R> + >R          ( addr' len'  R: width' )
    REPEAT
    2DROP R> ;

\ =====================================================================
\  §5 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _cw-guard

' CW-WIDTH   CONSTANT _cw-width-xt
' CW-SWIDTH  CONSTANT _cw-swidth-xt

: CW-WIDTH   _cw-width-xt  _cw-guard WITH-GUARD ;
: CW-SWIDTH  _cw-swidth-xt _cw-guard WITH-GUARD ;
[THEN] [THEN]
