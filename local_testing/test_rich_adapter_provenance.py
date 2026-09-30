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
0 _RA-INSTANCE @ CINST.ID ! _RP-REFUSE _RP-ID @ _RA-INSTANCE @ CINST.ID !
0 _RA-INSTANCE @ CINST.GENERATION ! _RP-REFUSE _RP-GEN @ _RA-INSTANCE @ CINST.GENERATION !
0 _RA-COMP-DESC COMP.MAGIC ! _RP-REFUSE COMP-MAGIC _RA-COMP-DESC COMP.MAGIC !
-1 _RA-COMP-DESC COMP.STATE-SIZE ! _RP-REFUSE 0 _RA-COMP-DESC COMP.STATE-SIZE !
0 _RA-SLOT AHS.INST ! _RP-REFUSE _RA-INSTANCE @ _RA-SLOT AHS.INST !
\ Every mutable bank, including both snapshot halves, is protected from live ownership.
_RA-NATIVE _RA-SLOT AHS.INST ! _RP-REFUSE _RA-INSTANCE @ _RA-SLOT AHS.INST !
_RA-DIRECTORY _RA-INSTANCE @ CINST.DESC ! _RP-REFUSE
_RA-COMP-DESC _RA-INSTANCE @ CINST.DESC !
8 _RA-COMP-DESC COMP.STATE-SIZE ! _RA-NATIVE _RA-INSTANCE @ CINST.STATE ! _RP-REFUSE
0 _RA-COMP-DESC COMP.STATE-SIZE ! 0 _RA-INSTANCE @ CINST.STATE !
_RUHA-O-INSTANCE _RA-INSTANCE @ CINST.DESC ! _RP-REFUSE
_RA-COMP-DESC _RA-INSTANCE @ CINST.DESC !
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT _RP-OWNER
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
_RP-DONE
''', minimum=87, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",), marker="PROVENANCE")
