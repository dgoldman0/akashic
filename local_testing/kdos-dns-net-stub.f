\ Deterministic offline KDOS networking vocabulary for kdos-dns contracts.
\ These words provide compile-time shape only.  They do not simulate a wire.
PROVIDED akashic-kdos-dns-net-stub

20 CONSTANT /IP-HDR
8  CONSTANT /UDP-HDR
6  CONSTANT IP-PROTO-TCP
17 CONSTANT IP-PROTO-UDP

0 CONSTANT TCPS-CLOSED
2 CONSTANT TCPS-SYN-SENT
4 CONSTANT TCPS-ESTABLISHED
5 CONSTANT TCPS-FIN-WAIT-1
7 CONSTANT TCPS-CLOSE-WAIT
9 CONSTANT TCPS-LAST-ACK
10 CONSTANT TCPS-TIME-WAIT

5816 CONSTANT /TCB
1 CONSTANT /TCP-MAX-CONN

: NW16!  ( value address -- )
    OVER 8 RSHIFT OVER C!
    1+ SWAP 255 AND SWAP C! ;

: NW16@  ( address -- value )
    DUP C@ 8 LSHIFT SWAP 1+ C@ + ;

: IP=  ( left right -- flag )
    4 SAMESTR? ;

: IP!  ( a b c d address -- )
    >R
    R@ 3 + C!
    R@ 2 + C!
    R@ 1+ C!
    R> C! ;

: IP-H.PROTO  ( header -- address ) 9 + ;
: IP-H.SRC    ( header -- address ) 12 + ;
: IP-H.DST    ( header -- address ) 16 + ;
: IP-H.DATA   ( header -- address ) /IP-HDR + ;

: UDP-H.SPORT  ( header -- address ) ;
: UDP-H.DPORT  ( header -- address ) 2 + ;
: UDP-H.LEN    ( header -- address ) 4 + ;
: UDP-H.DATA   ( header -- address ) /UDP-HDR + ;

: TCB.STATE       ( tcb -- address ) ;
: TCB.LOCAL-PORT  ( tcb -- address ) 8 + ;
: TCB.REMOTE-PORT ( tcb -- address ) 16 + ;
: TCB.REMOTE-IP   ( tcb -- address ) 24 + ;
: TCB.ISS         ( tcb -- address ) 72 + ;
: TCB.RX-COUNT    ( tcb -- address ) 5692 + ;

CREATE _kdnstub-tcbs /TCB /TCP-MAX-CONN * ALLOT
VARIABLE TCP-TCBS
_kdnstub-tcbs TCP-TCBS !

: TCB-N  ( index -- tcb )
    /TCB * TCP-TCBS @ + ;

: TCB-INIT  ( tcb -- )
    DUP /TCB 0 FILL
    TCPS-CLOSED SWAP TCB.STATE ! ;

CREATE ETH-RX-BUF 64 ALLOT
: ETH-PLD  ( frame -- address ) 14 + ;

: NEXT-HOP  ( destination -- target ) ;
: ARP-LOOKUP  ( ip -- mac-or-zero ) DROP 0 ;
: ARP-SEND-REQUEST  ( ip -- ) DROP ;
: ARP-POLL  ( -- length handled? ) 0 0 ;
: ARP-REPLY-FOR?  ( ip -- flag ) DROP 0 ;
: ARP-PARSE-REPLY  ( arp -- ) DROP ;

: IP-RECV  ( -- header length | 0 0 ) 0 0 ;
: UDP-VERIFY-CKSUM  ( src dst udp length -- flag )
    2DROP 2DROP 0 ;
: UDP-SEND  ( dst dport sport payload length -- ior )
    2DROP 2DROP DROP -1 ;

: TCP-CONNECT  ( remote-ip remote-port local-port -- tcb-or-zero )
    2DROP DROP 0 ;
: TCP-INPUT  ( ip-header ip-length -- ) 2DROP ;
: TCP-SEND-READY?  ( tcb -- flag ) DROP 0 ;
: TCP-SEND  ( tcb source length -- actual ) 2DROP DROP 0 ;
: TCP-RECV  ( tcb destination capacity -- actual ) 2DROP DROP 0 ;
: TCP-CLOSE  ( tcb -- ) TCB-INIT ;
: TCP-ABORT  ( tcb -- status ) TCB-INIT 0 ;
