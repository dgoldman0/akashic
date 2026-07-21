\ =====================================================================
\  agent-access-policy.f - Desk Agent access presets and budgets
\ =====================================================================
\  Agent owns the access-profile record contract.  Desk owns these exact
\  desk.* identities, capability choices, and resource budgets.  Runtime
\  receives this policy as an injected callback; no Desk policy is compiled
\  into Agent's renderer-free service code.
\ =====================================================================

PROVIDED akashic-tui-desk-agent-access-policy

REQUIRE ../agent/service.f

: DAP-PRESET?  ( preset -- flag )
    DUP AAP-PRESET-CHAT-ONLY =
    OVER AAP-PRESET-PRACTICE-READ = OR
    SWAP AAP-PRESET-PRACTICE-ASSIST = OR ;

VARIABLE _DAP-P

: _DAP-COMMON-EXACT?  ( -- flag )
    _DAP-P @ AAP.HISTORY-ITEMS @ 12 =
    _DAP-P @ AAP.HISTORY-BYTES @ 4096 = AND
    _DAP-P @ AAP.TIME-BUDGET-MS @ 600000 = AND
    _DAP-P @ AAP.MEMORY-BUDGET @ 0= AND
    _DAP-P @ AAP.TOKEN-BUDGET @ 0= AND ;

\ A preset is authority-shaping policy, not a cosmetic label.  Pin every
\ field Desk compiles so corruption cannot retain a trusted selector while
\ changing its disclosure or capability budget.
: DAP-PROFILE-VALID?  ( profile -- flag )
    DUP _DAP-P ! AAP-VALID? 0= IF 0 EXIT THEN
    _DAP-COMMON-EXACT? 0= IF 0 EXIT THEN
    _DAP-P @ AAP.PRESET @ CASE
        AAP-PRESET-CHAT-ONLY OF
            _DAP-P @ AAP-ID$ S" desk.chat-only" STR-STR=
            _DAP-P @ AAP-LABEL$ S" Chat only" STR-STR= AND
            _DAP-P @ AAP.FLAGS @ AAP-F-CHAT-HISTORY = AND
            _DAP-P @ AAP.EFFECTS @ 0= AND
            _DAP-P @ AAP.DISPOSITION @ MAND-D-READ-ONLY = AND
            _DAP-P @ AAP.TOOL-BUDGET @ 0= AND
            _DAP-P @ AAP.DISCLOSURE-BUDGET @ 8192 = AND
        ENDOF
        AAP-PRESET-PRACTICE-READ OF
            _DAP-P @ AAP-ID$ S" desk.practice-read" STR-STR=
            _DAP-P @ AAP-LABEL$ S" Practice read only" STR-STR= AND
            _DAP-P @ AAP.FLAGS @
                AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR = AND
            _DAP-P @ AAP.EFFECTS @ CAP-E-OBSERVE = AND
            _DAP-P @ AAP.DISPOSITION @ MAND-D-READ-ONLY = AND
            _DAP-P @ AAP.TOOL-BUDGET @ 4 = AND
            _DAP-P @ AAP.DISCLOSURE-BUDGET @ 32768 = AND
        ENDOF
        AAP-PRESET-PRACTICE-ASSIST OF
            _DAP-P @ AAP-ID$ S" desk.practice-assist" STR-STR=
            _DAP-P @ AAP-LABEL$ S" Practice assist" STR-STR= AND
            _DAP-P @ AAP.FLAGS @ AAP-F-CHAT-HISTORY
                AAP-F-CONTEXT-OBSERVE OR AAP-F-REVIEW-CHANGES OR = AND
            _DAP-P @ AAP.EFFECTS @ CAP-E-OBSERVE CAP-E-NAVIGATE OR
                CAP-E-MUTATE OR CAP-E-PERSIST OR = AND
            _DAP-P @ AAP.DISPOSITION @ MAND-D-COMMIT = AND
            _DAP-P @ AAP.TOOL-BUDGET @ 8 = AND
            _DAP-P @ AAP.DISCLOSURE-BUDGET @ 49152 = AND
        ENDOF
        0 SWAP
    ENDCASE ;

VARIABLE _DAPI-PRESET
VARIABLE _DAPI-P

: DAP-PRESET!  ( preset profile -- status )
    _DAPI-P ! _DAPI-PRESET !
    _DAPI-PRESET @ DAP-PRESET? 0= IF AAP-S-INVALID EXIT THEN
    _DAPI-P @ AAP-INIT
    _DAPI-PRESET @ _DAPI-P @ AAP.PRESET !
    _DAPI-PRESET @ CASE
        AAP-PRESET-CHAT-ONLY OF
            S" desk.chat-only"
                _DAPI-P @ AAP.ID-U ! _DAPI-P @ AAP.ID-A !
            S" Chat only"
                _DAPI-P @ AAP.LABEL-U ! _DAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY _DAPI-P @ AAP.FLAGS !
            0 _DAPI-P @ AAP.EFFECTS !
            MAND-D-READ-ONLY _DAPI-P @ AAP.DISPOSITION !
            12 _DAPI-P @ AAP.HISTORY-ITEMS !
            4096 _DAPI-P @ AAP.HISTORY-BYTES !
            600000 _DAPI-P @ AAP.TIME-BUDGET-MS !
            0 _DAPI-P @ AAP.MEMORY-BUDGET !
            0 _DAPI-P @ AAP.TOKEN-BUDGET !
            0 _DAPI-P @ AAP.TOOL-BUDGET !
            8192 _DAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
        AAP-PRESET-PRACTICE-READ OF
            S" desk.practice-read"
                _DAPI-P @ AAP.ID-U ! _DAPI-P @ AAP.ID-A !
            S" Practice read only"
                _DAPI-P @ AAP.LABEL-U ! _DAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR
                _DAPI-P @ AAP.FLAGS !
            CAP-E-OBSERVE _DAPI-P @ AAP.EFFECTS !
            MAND-D-READ-ONLY _DAPI-P @ AAP.DISPOSITION !
            12 _DAPI-P @ AAP.HISTORY-ITEMS !
            4096 _DAPI-P @ AAP.HISTORY-BYTES !
            600000 _DAPI-P @ AAP.TIME-BUDGET-MS !
            0 _DAPI-P @ AAP.MEMORY-BUDGET !
            0 _DAPI-P @ AAP.TOKEN-BUDGET !
            4 _DAPI-P @ AAP.TOOL-BUDGET !
            32768 _DAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
        AAP-PRESET-PRACTICE-ASSIST OF
            S" desk.practice-assist"
                _DAPI-P @ AAP.ID-U ! _DAPI-P @ AAP.ID-A !
            S" Practice assist"
                _DAPI-P @ AAP.LABEL-U ! _DAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR
                AAP-F-REVIEW-CHANGES OR _DAPI-P @ AAP.FLAGS !
            CAP-E-OBSERVE CAP-E-NAVIGATE OR CAP-E-MUTATE OR CAP-E-PERSIST OR
                _DAPI-P @ AAP.EFFECTS !
            MAND-D-COMMIT _DAPI-P @ AAP.DISPOSITION !
            12 _DAPI-P @ AAP.HISTORY-ITEMS !
            4096 _DAPI-P @ AAP.HISTORY-BYTES !
            600000 _DAPI-P @ AAP.TIME-BUDGET-MS !
            0 _DAPI-P @ AAP.MEMORY-BUDGET !
            0 _DAPI-P @ AAP.TOKEN-BUDGET !
            8 _DAPI-P @ AAP.TOOL-BUDGET !
            49152 _DAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
    ENDCASE
    _DAPI-P @ DAP-PROFILE-VALID? IF AAP-S-OK ELSE AAP-S-INVALID THEN ;

: DAP-RUNTIME-POLICY  ( preset profile data -- status )
    DROP DAP-PRESET! ;

: DAP-RUNTIME-VALID?  ( profile data -- flag )
    DROP DAP-PROFILE-VALID? ;
