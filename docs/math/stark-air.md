# stark-air.f — STARK AIR Constraint Descriptor

**Module:** `akashic/math/stark-air.f`
**Prefix:** `AIR-`
**Depends on:** `baby-bear.f`
**Provided:** `akashic-stark-air`
**Tests:** 28/28

## Overview

Algebraic Intermediate Representation (AIR) constraint descriptor
for STARK proof systems.  Builds a compact byte buffer describing
trace width, transition constraints, and boundary constraints.
A generic STARK prover/verifier interprets the descriptor at
runtime instead of hardcoding specific computations.

## Design Principles

| Principle | Decision |
|-----------|----------|
| Representation | Flat byte buffer — no pointers, relocatable |
| Operations | ADD, SUB, MUL over Baby Bear field |
| Multi-column | Arbitrary trace width, column indices in descriptors |
| Row offsets | Each operand can reference current, next, or further rows |
| Builder pattern | AIR-BEGIN / AIR-TRANS / AIR-BOUNDARY / AIR-END |
| Evaluation | Residual-based — returns 0 when constraint is satisfied |

## Descriptor Layout

```
Header (8 bytes):
  +0x00  u16  n_cols      number of trace columns
  +0x02  u16  n_trans     number of transition constraints
  +0x04  u16  n_bound     number of boundary constraints
  +0x06  u16  reserved

Transition entries (8 bytes each):
  +0x00  u8   type        0=ADD, 1=SUB, 2=MUL
  +0x01  u8   colA        left operand column
  +0x02  u8   offA        left operand row offset
  +0x03  u8   colB        right operand column
  +0x04  u8   offB        right operand row offset
  +0x05  u8   colR        result column
  +0x06  u8   offR        result row offset
  +0x07  u8   reserved

Boundary entries (8 bytes each):
  +0x00  u8   col         column index
  +0x01  u8   reserved
  +0x02  u16  row         row index (LE)
  +0x04  u32  value       expected value (LE, mod q)
```

## API Reference

### Constants

| Word | Value | Description |
|------|-------|-------------|
| `AIR-ADD` | 0 | Addition constraint |
| `AIR-SUB` | 1 | Subtraction constraint |
| `AIR-MUL` | 2 | Multiplication constraint |

### Builder

| Word | Stack | Description |
|------|-------|-------------|
| `AIR-BEGIN` | `( n-cols -- )` | Start building descriptor |
| `AIR-TRANS` | `( type colA offA colB offB colR offR -- )` | Add transition constraint |
| `AIR-BOUNDARY` | `( col row val -- )` | Add boundary constraint |
| `AIR-END` | `( -- air-addr )` | Finalize, allocate in dictionary |

### Queries

| Word | Stack | Description |
|------|-------|-------------|
| `AIR-N-COLS` | `( air -- n )` | Trace width |
| `AIR-N-TRANS` | `( air -- n )` | Transition constraint count |
| `AIR-N-BOUND` | `( air -- n )` | Boundary constraint count |
| `AIR-MAX-OFF` | `( air -- n )` | Maximum row offset in any constraint |

### Evaluation

| Word | Stack | Description |
|------|-------|-------------|
| `AIR-EVAL-TRANS` | `( air cols row -- residual )` | Sum of constraint residuals at row |
| `AIR-CHECK-BOUND` | `( air cols -- flag )` | TRUE if all boundaries match |

## Trace Access Convention

The `cols` parameter is a cell array of buffer base addresses.
To read `trace[col][row]`, the evaluator computes:

```
addr = cols[col] + row * 4
value = 32-bit LE read at addr
```

This matches the NTT-POLY layout used by the STARK prover (each
polynomial is 256 entries × 4 bytes = 1024 bytes).

## Usage Examples

### Fibonacci AIR (1 column)

```forth
\ trace[i+2] = trace[i] + trace[i+1]
\ trace[0] = 1, trace[1] = 1

1 AIR-BEGIN
  AIR-ADD  0 0  0 1  0 2  AIR-TRANS
  0 0 1  AIR-BOUNDARY
  0 1 1  AIR-BOUNDARY
AIR-END CONSTANT FIB-AIR
```

### Arithmetic Progression (2 columns)

```forth
\ col0[i+1] = col0[i] + col1[i]
\ col0[0] = 1, col1[0] = 3

2 AIR-BEGIN
  AIR-ADD  0 0  1 0  0 1  AIR-TRANS
  0 0 1  AIR-BOUNDARY
  1 0 3  AIR-BOUNDARY
AIR-END CONSTANT ARITH-AIR
```

### Doubling (multiplication)

```forth
\ col0[i+1] = col0[i] * col1[i]
\ col0[0] = 1, col1[0] = 2

2 AIR-BEGIN
  AIR-MUL  0 0  1 0  0 1  AIR-TRANS
  0 0 1  AIR-BOUNDARY
  1 0 2  AIR-BOUNDARY
AIR-END CONSTANT DBL-AIR
```

### Evaluating constraints

```forth
\ Check all transition rows
254 0 DO
  FIB-AIR cols I AIR-EVAL-TRANS
  0 <> IF ." BAD ROW " I . THEN
LOOP

\ Check boundary values
FIB-AIR cols AIR-CHECK-BOUND
IF ." BOUNDARIES OK" THEN
```

## Residual Semantics

`AIR-EVAL-TRANS` computes the sum of residuals for all transition
constraints at a given row:

```
residual_j = trace[colR][row+offR] - op(trace[colA][row+offA],
                                         trace[colB][row+offB])
total = sum of all residual_j  (mod q)
```

Returns 0 when all constraints are satisfied.  A nonzero return
means at least one constraint is violated.

## Quick Reference

```
AIR-ADD = 0    AIR-SUB = 1    AIR-MUL = 2
AIR-BEGIN ( n-cols -- )
AIR-TRANS ( type colA offA colB offB colR offR -- )
AIR-BOUNDARY ( col row val -- )
AIR-END ( -- air )
AIR-N-COLS ( air -- n )    AIR-N-TRANS ( air -- n )
AIR-N-BOUND ( air -- n )   AIR-MAX-OFF ( air -- n )
AIR-EVAL-TRANS ( air cols row -- residual )
AIR-CHECK-BOUND ( air cols -- flag )
```
