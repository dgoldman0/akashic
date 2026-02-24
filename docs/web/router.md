# akashic-web-router

Path → handler dispatch for KDOS / Megapad-64.

Register routes with method + URL pattern + handler xt.  
Match incoming requests, extract path parameters, dispatch.

**Depends on:** `table.f`, `string.f`, `request.f`, `response.f`

```
REQUIRE web/router.f
```

---

## Layer 0 — Route Table

Each route stores: method string (addr+len), pattern string (addr+len), handler xt.  
40-byte records in a 64-slot table (via `table.f`).

### ROUTE

```
ROUTE ( method-a method-u pattern-a pattern-u xt -- )
```

Register a route. Silently drops if table is full.

```forth
: my-handler  200 RESP-STATUS S" OK" RESP-TEXT RESP-SEND ;
S" GET" S" /hello" ['] my-handler ROUTE
```

### ROUTE-GET / ROUTE-POST / ROUTE-PUT / ROUTE-DELETE

```
ROUTE-GET    ( pattern-a pattern-u xt -- )
ROUTE-POST   ( pattern-a pattern-u xt -- )
ROUTE-PUT    ( pattern-a pattern-u xt -- )
ROUTE-DELETE ( pattern-a pattern-u xt -- )
```

Convenience wrappers that supply the method string.

```forth
S" /users" ['] list-users ROUTE-GET
S" /users" ['] create-user ROUTE-POST
```

### ROUTE-COUNT

```
ROUTE-COUNT ( -- n )
```

Number of currently registered routes.

### ROUTE-CLEAR

```
ROUTE-CLEAR ( -- )
```

Remove all routes (flushes the table).

---

## Layer 1 — Path Parameters

Up to 8 captured parameters per match. Zero-copy pointers into the pattern and request path strings.

### ROUTE-PARAM

```
ROUTE-PARAM ( name-a name-u -- val-a val-u )
```

Look up a captured path parameter by name. Returns `0 0` if not found.

```forth
\ After matching /user/:id against /user/42:
S" id" ROUTE-PARAM TYPE   \ prints "42"
```

### ROUTE-PARAM?

```
ROUTE-PARAM? ( name-a name-u -- flag )
```

Test whether a parameter was captured.

---

## Layer 2 — Pattern Matching

### _ROUTE-NEXT-SEG

```
_ROUTE-NEXT-SEG ( addr len -- seg-a seg-u rest-a rest-u )
```

Split a path at the next `/`. Skips a leading `/`.

| Input        | Segment   | Rest     |
|-------------|-----------|----------|
| `"/"`       | `"" 0`    | `"" 0`   |
| `"/foo"`    | `"foo" 3` | `"" 0`   |
| `"/foo/bar"`| `"foo" 3` | `"/bar" 4`|

### _ROUTE-PATTERN-MATCH

```
_ROUTE-PATTERN-MATCH ( pat-a pat-u path-a path-u -- flag )
```

Match a full pattern against a full path, segment by segment.

- Literal segments must match exactly (via `STR-STR=`).
- `:name` segments match anything and capture the value as a parameter.
- Both must be fully exhausted for a match (no trailing segments).

```forth
S" /user/:id" S" /user/42" _ROUTE-PATTERN-MATCH   \ → -1 (true)
S" /foo"      S" /foo/bar" _ROUTE-PATTERN-MATCH   \ → 0 (false)
```

### ROUTE-MATCH

```
ROUTE-MATCH ( method-a method-u path-a path-u -- xt | 0 )
```

Find the first registered route matching the given method and path.  
Returns the handler xt, or 0 if no match.  
On a successful match, path parameters are captured and available via `ROUTE-PARAM`.

---

## Layer 3 — Dispatch

### ROUTE-DISPATCH

```
ROUTE-DISPATCH ( -- )
```

Read `REQ-METHOD` and `REQ-PATH` from the parsed request, find a matching route, and `EXECUTE` the handler. If no route matches, calls `RESP-NOT-FOUND`.

```forth
\ Typical server loop body:
\   ... RECV + REQ-PARSE ...
ROUTE-DISPATCH
```

---

## Example

```forth
REQUIRE web/router.f

: handle-index   S" Hello!" RESP-TEXT RESP-SEND ;
: handle-user    S" id" ROUTE-PARAM RESP-TEXT RESP-SEND ;
: handle-create  201 RESP-STATUS S" Created" RESP-TEXT RESP-SEND ;

S" /"         ['] handle-index  ROUTE-GET
S" /user/:id" ['] handle-user   ROUTE-GET
S" /user"     ['] handle-create ROUTE-POST

\ In accept loop:
\   sd RECV-BUF RECV  REQ-PARSE  ROUTE-DISPATCH
```

---

## Limits

| Resource         | Limit |
|-----------------|-------|
| Routes           | 64    |
| Path parameters  | 8     |
| Record size      | 40 bytes |
