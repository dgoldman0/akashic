"""Actual CINST/AHOST/UIDL source provenance and frozen whole-document reuse."""

from test_data_graphics_series import run_series
from test_uidl_collection_snapshot import _ruha_constructor_program


def _program():
    lines = _ruha_constructor_program()
    lines = lines[lines.index("VARIABLE _RA-FAILS"):]
    stop = lines.index("2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines = lines[:stop]
    lines = [line.replace("_RA-CTX @ UCTX-CLEAR _RA-CTX @ UCTX-RESTORE", "_RA-CTX @ UCTX-CLEAR")
             .replace("CREATE _RA-HOST 16 ALLOT", "CREATE _RA-HOST AHOST-SIZE ALLOT")
             .replace("CREATE _RA-SLOT 48 ALLOT", "CREATE _RA-SLOT AHS-SIZE ALLOT")
             .replace("_RA-HOST 16 0 FILL _RA-SLOT 48 0 FILL",
                      "_RA-HOST AHOST-INIT _RA-SLOT AHS-SIZE 0 FILL AHS-S-RUNNING _RA-SLOT AHS.STATE !")
             .replace("_RA-SLOT _RA-HOST !", "_RA-SLOT _RA-HOST AHOST.HEAD !")
             for line in lines]
    return "\n".join(lines) + r'''
VARIABLE _RP-ID VARIABLE _RP-GEN VARIABLE _RP-DIR VARIABLE _RP-OTHER
\ RUHA's own banks, in the block it took from its memory source.
: _RA-NATIVE ( -- a ) _RA-ADAPTER _RUHA-A.SNAP-NATIVE-A @ ;
: _RA-DIRECTORY ( -- a ) _RA-ADAPTER _RUHA-A.SNAP-DIRECTORY-A @ ;
CREATE _RP-COPY 247 ALLOT
: _RP-SAVED _RP-COPY 7 + -8 AND ;
: _RP-OWNER
    _RA-DIR-A @ RUHA-DOCUMENT-OWNER-ID@ _RA-SLOT AHS.INST @ CINST.ID @ = _RA-ASSERT
    _RA-DIR-A @ RUHA-DOCUMENT-OWNER-GENERATION@
        _RA-SLOT AHS.INST @ CINST.GENERATION @ = _RA-ASSERT ;
: _RP-DONE _RA-STACK _RA-FAILS @ 0= IF ." PROVENANCE PASS " ELSE ." PROVENANCE FAIL " THEN
    _RA-CHECKS @ . _RA-FAILS @ . CR ;
_RP-OWNER
_RA-INSTANCE @ CINST.ID @ _RP-ID ! _RA-INSTANCE @ CINST.GENERATION @ _RP-GEN !
_RA-DIR-A @ _RP-DIR ! _RA-DIR-A @ _RP-SAVED RUHA-DOCUMENT-SIZE MOVE
'''


def test_live_instance_tuple_freezes_and_prevents_stale_prior_reuse():
    run_series(_program() + r'''
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
_RA-DIR-A @ RUHA-DOCUMENT-SIZE _RP-SAVED RUHA-DOCUMENT-SIZE COMPARE 0= _RA-ASSERT
\ Genuine replacement preserves the slot and UCTX but changes component identity.
_RA-COMP-DESC CINST-NEW 0= _RA-ASSERT DUP _RP-OTHER ! _RA-SLOT AHS.INST !
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 3 = _RA-ASSERT
_RA-DIR-A @ RUHA-DOCUMENT-OWNER-ID@ _RP-ID @ <> _RA-ASSERT
\ Generation alone also defeats prior reuse, including copied source bytes.
77 _RP-OTHER @ CINST.GENERATION !
4 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-DIR-A @ RUHA-DOCUMENT-OWNER-GENERATION@ 77 = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 4 = _RA-ASSERT
\ Prior frozen tuple corruption cannot contaminate live source identity.
999 _RA-DIR-A @ _RUHA-D.OWNER-ID !
5 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 5 = _RA-ASSERT
\ Directory-only fallback carries the same actual provenance.
: _RP-OVERLAY RGN-ROOT 35 0 0 DRW-CHAR ; ' _RP-OVERLAY DRW-OVERLAY
6 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 0= _RA-ASSERT
_RP-DONE
''', minimum=72, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_invalid_or_aliased_instance_authority_refuses_before_bank_mutation():
    run_series(_program() + r'''
CREATE _RP-ADAPTER-SAVED RUHA-SIZE 7 + ALLOT
: _RP-AS _RP-ADAPTER-SAVED 7 + -8 AND ;
_RA-ADAPTER _RP-AS RUHA-SIZE MOVE
SCR-DRAW-COMPLETE
: _RP-REFUSE
    2 _RA-ADAPTER RUHA-SNAPSHOT-FOR@ RUHA-S-INVALID = _RA-ASSERT 0= _RA-ASSERT
    _RA-ADAPTER RUHA-SIZE _RP-AS RUHA-SIZE COMPARE 0= _RA-ASSERT
    _RP-DIR @ RUHA-DOCUMENT-SIZE _RP-SAVED RUHA-DOCUMENT-SIZE COMPARE 0= _RA-ASSERT ;
\ The owner's identity is checked on every draw, in normal mode too.
0 _RA-INSTANCE @ CINST.ID ! _RP-REFUSE _RP-ID @ _RA-INSTANCE @ CINST.ID !
0 _RA-INSTANCE @ CINST.GENERATION ! _RP-REFUSE _RP-GEN @ _RA-INSTANCE @ CINST.GENERATION !
0 _RA-COMP-DESC COMP.MAGIC ! _RP-REFUSE COMP-MAGIC _RA-COMP-DESC COMP.MAGIC !
-1 _RA-COMP-DESC COMP.STATE-SIZE ! _RP-REFUSE 0 _RA-COMP-DESC COMP.STATE-SIZE !
0 _RA-SLOT AHS.INST ! _RP-REFUSE _RA-INSTANCE @ _RA-SLOT AHS.INST !
\ Every mutable bank, including both snapshot halves, is protected from live
\ ownership: a draw proves it again with every-frame checks on.
-1 CHK-EVERY-FRAME !
_RA-NATIVE _RA-SLOT AHS.INST ! _RP-REFUSE _RA-INSTANCE @ _RA-SLOT AHS.INST !
_RA-DIRECTORY _RA-INSTANCE @ CINST.DESC ! _RP-REFUSE
_RA-COMP-DESC _RA-INSTANCE @ CINST.DESC !
8 _RA-COMP-DESC COMP.STATE-SIZE ! _RA-NATIVE _RA-INSTANCE @ CINST.STATE ! _RP-REFUSE
0 _RA-COMP-DESC COMP.STATE-SIZE ! 0 _RA-INSTANCE @ CINST.STATE !
_RUHA-O-INSTANCE _RA-INSTANCE @ CINST.DESC ! _RP-REFUSE
_RA-COMP-DESC _RA-INSTANCE @ CINST.DESC !
0 CHK-EVERY-FRAME !
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
_RP-DONE
''', minimum=87, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_safe_mode_captures_an_unchanged_document_afresh():
    run_series(_program() + r'''
\ In normal mode an unchanged document's slices are reused, and the content
\ epoch stays.
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
\ Safe mode captures every document afresh on every draw, so the epoch
\ moves with each one although nothing changed.
CHK-WHY-BOOT CHK-SAFE-ON
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 3 = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT
4 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 4 = _RA-ASSERT
_RP-DONE
''', minimum=50, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_every_frame_checks_validate_a_stored_slice_before_reuse():
    run_series(_program() + r'''
\ A byte that is not UTF-8 in the stored collection slice, written after
\ its capture.  With every-frame checks on, the snapshot module's full
\ validation refuses the slice before reuse, and the document is captured
\ afresh from its widget.
-1 CHK-EVERY-FRAME !
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ DROP 255 SWAP C!
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 2 = _RA-ASSERT
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@
    S" aggregate alpha" STR-STR= _RA-ASSERT
\ The refused slice is named as damaged (check-mode.f).
CHK-DAMAGE S" the snapshot adapter's stored slices" STR-STR= _RA-ASSERT
CHK-DAMAGE-COUNT @ 1 = _RA-ASSERT
\ In normal mode only the slice's bounds are checked, and it is reused as
\ stored: the trade normal mode makes, which safe mode does not.
0 CHK-EVERY-FRAME !
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ DROP 255 SWAP C!
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 2 = _RA-ASSERT
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ DROP C@ 255 = _RA-ASSERT
CHK-DAMAGE-COUNT @ 1 = _RA-ASSERT
_RP-DONE
''', minimum=56, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_normal_mode_draws_check_the_owner_not_where_its_storage_lies():
    run_series(_program() + r'''
\ An owner whose state lies in RUHA's own native bank.  With every-frame
\ checks on, a draw proves the owner's storage apart from RUHA's banks again
\ and refuses it; in normal mode, where that proof is made when the owner
\ attaches, a draw checks only that the owner is a live one.
8 _RA-COMP-DESC COMP.STATE-SIZE ! _RA-NATIVE _RA-INSTANCE @ CINST.STATE !
-1 CHK-EVERY-FRAME !
2 _RA-QUERY _RA-STATUS @ RUHA-S-INVALID = _RA-ASSERT
\ The failed proof names RUHA's banks as damaged (check-mode.f).
CHK-DAMAGE S" the snapshot adapter's banks" STR-STR= _RA-ASSERT
CHK-DAMAGE-COUNT @ 1 = _RA-ASSERT
0 CHK-EVERY-FRAME !
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
\ The owner's identity is still checked, in both modes, and a stale
\ identity names nothing.
0 _RA-INSTANCE @ CINST.GENERATION !
4 _RA-QUERY _RA-STATUS @ RUHA-S-INVALID = _RA-ASSERT
-1 CHK-EVERY-FRAME !
5 _RA-QUERY _RA-STATUS @ RUHA-S-INVALID = _RA-ASSERT
0 CHK-EVERY-FRAME !
CHK-DAMAGE-COUNT @ 1 = _RA-ASSERT
_RP-GEN @ _RA-INSTANCE @ CINST.GENERATION !
0 _RA-COMP-DESC COMP.STATE-SIZE ! 0 _RA-INSTANCE @ CINST.STATE !
_RP-DONE
''', minimum=54, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_a_failed_proof_at_attach_turns_safe_mode_on():
    run_series(_program() + r'''
_RA-SLOT AHS.UCTX @ ASHELL-CTX-SWITCH
\ An owner that does not name itself is refused at attach, and that is
\ state: safe mode stays off.
0 _RA-INSTANCE @ CINST.GENERATION !
_RA-SLOT _RA-ADAPTER _RUHA-ATTACH RUHA-S-INVALID = _RA-ASSERT DROP
CHK-SAFE? 0= _RA-ASSERT CHK-DAMAGE-COUNT @ 0= _RA-ASSERT
_RP-GEN @ _RA-INSTANCE @ CINST.GENERATION !
\ An owner whose state lies in RUHA's own bank fails the proof made when it
\ attaches, which only a bug can cause: safe mode turns on for the rest of
\ the session and names RUHA's banks (check-mode.f).
8 _RA-COMP-DESC COMP.STATE-SIZE ! _RA-NATIVE _RA-INSTANCE @ CINST.STATE !
_RA-SLOT _RA-ADAPTER _RUHA-ATTACH RUHA-S-INVALID = _RA-ASSERT DROP
CHK-SAFE-MODE @ CHK-WHY-ANOMALY = _RA-ASSERT
CHK-DAMAGE S" the snapshot adapter's banks" STR-STR= _RA-ASSERT
0 _RA-COMP-DESC COMP.STATE-SIZE ! 0 _RA-INSTANCE @ CINST.STATE !
_RP-DONE
''', minimum=48, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")


def test_shadow_check_matches_reuse_and_catches_a_stale_reused_slice():
    run_series(_program() + r'''
-1 FSHD-ON ! FSHD-RESET
\ An unchanged draw reuses the document, which the full capture takes live:
\ the header and all thirteen spans agree.
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
FSHD-CHECKS @ 14 = _RA-ASSERT FSHD-MISMATCHES @ 0= _RA-ASSERT
FSHD-SKIPPED @ 0= _RA-ASSERT
\ A reused slice that no longer matches its widget is a difference, in the
\ collection values, the fifth span.
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ DROP 98 SWAP C!
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
FSHD-MISMATCHES @ 1 = _RA-ASSERT
FSHD-FIRST-STAGE @ FSHD-STAGE-SNAPSHOT = _RA-ASSERT
FSHD-FIRST-ITEM @ 5 = _RA-ASSERT
\ The published snapshot is the reused one, as it is with the check off.
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ DROP C@ 98 = _RA-ASSERT
0 FSHD-ON !
_RP-DONE
''', minimum=57, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")
