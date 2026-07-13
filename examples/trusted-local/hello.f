\ hello.f - smallest useful trusted-local Desk applet
\
\ This source is deliberately ordinary Forth.  Pad's Build & Install
\ path compiles it inside the running machine, records HELLO-ENTRY as
\ the package's sole named export, then discards the build dictionary
\ region after serializing the image.

CREATE HELLO-COMP-DESC COMP-DESC ALLOT

: _HELLO-INIT  ( instance -- ) DROP ;
: _HELLO-TICK  ( instance -- ) DROP ;
: _HELLO-SHUTDOWN  ( instance -- ) DROP ;

: _HELLO-EVENT  ( event instance -- consumed? )
    2DROP 0 ;

: _HELLO-REQUEST-CLOSE  ( reason instance -- decision )
    2DROP APP-CLOSE-D-ALLOW ;

: _HELLO-PAINT  ( instance -- )
    DROP
    S" Hello from a packaged applet." 1 2 DRW-TEXT
    S" This code was compiled and installed inside Akashic." 3 2 DRW-TEXT
    S" Close with Alt+W; relaunch it from the Desk launcher." 5 2 DRW-TEXT ;

: _HELLO-COMP-SETUP  ( -- )
    HELLO-COMP-DESC COMP-DESC-INIT
    S" local.hello"
    HELLO-COMP-DESC COMP.ID-U ! HELLO-COMP-DESC COMP.ID-A !
    S" 0.1.0"
    HELLO-COMP-DESC COMP.VERSION-U ! HELLO-COMP-DESC COMP.VERSION-A !
    0 HELLO-COMP-DESC COMP.STATE-SIZE ! ;

: HELLO-ENTRY  ( app-desc -- )
    _HELLO-COMP-SETUP
    DUP APP-DESC-INIT
    HELLO-COMP-DESC          OVER APP.COMP-DESC !
    ['] _HELLO-INIT          OVER APP.INIT-XT !
    ['] _HELLO-EVENT         OVER APP.EVENT-XT !
    ['] _HELLO-TICK          OVER APP.TICK-XT !
    ['] _HELLO-PAINT         OVER APP.PAINT-XT !
    ['] _HELLO-SHUTDOWN      OVER APP.SHUTDOWN-XT !
    ['] _HELLO-REQUEST-CLOSE OVER APP.REQUEST-CLOSE-XT !
    44                       OVER APP.WIDTH !
    8                        OVER APP.HEIGHT !
    S" Hello"
    ROT DUP >R APP.TITLE-U ! R> APP.TITLE-A ! ;
