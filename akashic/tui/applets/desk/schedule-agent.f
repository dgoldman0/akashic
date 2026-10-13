\ =====================================================================
\  schedule-agent.f - The Agent as the handler of Desk's schedule broker
\ =====================================================================
\  Desk's broker (schedule-broker.f) starts approved scheduled runs
\  through a handler.  DSAG-HANDLER-INIT fills one whose context is the
\  Agent's dispatcher (../agent/dispatch.f), which starts, follows and
\  cancels the runs, says whether it could start one now, lists the
\  models it can run, and says why it could not run a schedule its user
\  is asked to approve.  Each of the dispatcher's words has the stack the
\  broker gives the handler's word.
\
\  Public API:
\    DSAG-HANDLER-INIT  ( dispatch handler -- )
\ =====================================================================

PROVIDED akashic-desk-schedule-agent

REQUIRE schedule-broker.f
REQUIRE ../agent/service.f

: DSAG-HANDLER-INIT  ( dispatch handler -- )
    TUCK SBRK-HANDLER-INIT
    ['] ADISP-START OVER SBRK-H.START-XT !
    ['] ADISP-STATUS OVER SBRK-H.STATUS-XT !
    ['] ADISP-CANCEL OVER SBRK-H.CANCEL-XT !
    ['] ADISP-MODELS OVER SBRK-H.MODELS-XT !
    ['] ADISP-IDLE? OVER SBRK-H.IDLE-XT !
    ['] ADISP-VET SWAP SBRK-H.VET-XT ! ;
