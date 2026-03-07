# akashic-rpc — JSON-RPC 2.0 Interface for KDOS / Megapad-64

Single-endpoint JSON-RPC 2.0 server registered at `POST /rpc`.
Provides chain queries, transaction submission, mempool status,
and node information over the existing HTTP web server.

```forth
REQUIRE rpc.f
```

`PROVIDED akashic-rpc` — depends on `akashic-server`, `akashic-json`,
`akashic-mempool`, `akashic-state`, `akashic-block`, `akashic-fmt`,
`akashic-gossip`, `akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Error Codes](#error-codes)
- [Initialization](#initialization)
- [Method Dispatch](#method-dispatch)
- [Methods](#methods)
- [Response Format](#response-format)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Standard JSON-RPC 2.0** | Envelope with `jsonrpc`, `method`, `params`, `id` |
| **Single route** | `POST /rpc` — all methods multiplex through one handler |
| **Numeric IDs only** | ID is stored and echoed as a number |
| **Guard-wrapped** | `RPC-INIT` and `RPC-DISPATCH` are serialized |
| **Hex encoding** | Addresses and tx hashes returned as 64-char hex strings |

---

## Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `RPC-E-PARSE` | -32700 | Invalid JSON body (< 2 bytes) |
| `RPC-E-METHOD` | -32601 | Method not found |
| `RPC-E-PARAMS` | -32602 | Invalid params (e.g., bad address length) |
| `RPC-E-INTERNAL` | -32000 | Internal error (tx decode/reject) |

---

## Initialization

### RPC-INIT

```forth
RPC-INIT  ( -- )
```

Register the `/rpc` route via `ROUTE-POST`.  Call after `ROUTE-CLEAR`.

---

## Method Dispatch

### RPC-DISPATCH

```forth
RPC-DISPATCH  ( -- )
```

Called by the router on `POST /rpc`.  Parses the JSON body, extracts
`method`, `id`, and `params`, then dispatches to the matching handler.
If the body is too short (< 2 bytes), returns a parse error immediately.

---

## Methods

### chain_blockNumber

Returns the current chain height as a numeric result.

**Params:** none  
**Result:** `n` (u64)

### chain_getBalance

Returns the balance of an account by its hex-encoded address.

**Params:** `["<64-hex-char address>"]`  
**Result:** `n` (u64)  
**Error:** `RPC-E-PARAMS` if address is not exactly 64 hex chars.

### chain_sendTransaction

Submit a CBOR-encoded transaction.  Decodes hex → binary → tx struct,
adds to mempool, returns the tx hash as hex.

**Params:** `["<cbor-hex>"]`  
**Result:** `"<64-hex-char tx hash>"`  
**Error:** `RPC-E-INTERNAL` on decode failure or mempool rejection.

### mempool_status

Returns mempool statistics.

**Params:** none  
**Result:** `{"count": n}`

### node_info

Returns node-level information.

**Params:** none  
**Result:** `{"height": n, "peers": n, "mempool": n}`

---

## Response Format

All responses follow the JSON-RPC 2.0 envelope:

```json
{"jsonrpc":"2.0","id":42,"result": ...}
```

Error responses:

```json
{"jsonrpc":"2.0","id":42,"error":{"code":-32601,"message":"method not found"}}
```

The `id` field is echoed only if present in the request.

---

## Concurrency

`RPC-INIT` and `RPC-DISPATCH` are wrapped with a module-level guard
(`_rpc-guard`) via `WITH-GUARD`.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `RPC-INIT` | `( -- )` | Register `/rpc` route |
| `RPC-DISPATCH` | `( -- )` | Handle POST /rpc request |
| `RPC-E-PARSE` | `( -- -32700 )` | Parse error code |
| `RPC-E-METHOD` | `( -- -32601 )` | Method not found code |
| `RPC-E-PARAMS` | `( -- -32602 )` | Invalid params code |
| `RPC-E-INTERNAL` | `( -- -32000 )` | Internal error code |
