#!/usr/bin/env python3
"""Test suite for Akashic rpc.f (akashic/web/rpc.f).

Tests:
  - Module compilation (loads without error)
  - chain_blockNumber → result 0
  - mempool_status → result {count:0}
  - node_info → result {height,peers,mempool}
  - Unknown method → error -32601
  - Empty body → parse error -32700
  - chain_getBalance valid address → result 0
  - chain_getBalance bad address → error -32602
  - Repeated requests (state resets)
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# ── Dependency file paths (combined blockchain + net + web + rpc) ──

# Blockchain stack
EVENT_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F       = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
FP16_F      = os.path.join(ROOT_DIR, "akashic", "math", "fp16.f")
SHA512_F    = os.path.join(ROOT_DIR, "akashic", "math", "sha512.f")
FIELD_F     = os.path.join(ROOT_DIR, "akashic", "math", "field.f")
SHA3_F      = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
RANDOM_F    = os.path.join(ROOT_DIR, "akashic", "math", "random.f")
ED25519_F   = os.path.join(ROOT_DIR, "akashic", "math", "ed25519.f")
SPHINCS_F   = os.path.join(ROOT_DIR, "akashic", "math", "sphincs-plus.f")
CBOR_F      = os.path.join(ROOT_DIR, "akashic", "cbor", "cbor.f")
FMT_F       = os.path.join(ROOT_DIR, "akashic", "utils", "fmt.f")
MERKLE_F    = os.path.join(ROOT_DIR, "akashic", "math", "merkle.f")
TX_F        = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
STATE_F     = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F     = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
MEMPOOL_F   = os.path.join(ROOT_DIR, "akashic", "store", "mempool.f")

# Network stack (string, url, headers shared with web)
STRING_F    = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F       = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HEADERS_F   = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
BASE64_F    = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")
HTTP_F      = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
WS_F        = os.path.join(ROOT_DIR, "akashic", "net", "ws.f")
GOSSIP_F    = os.path.join(ROOT_DIR, "akashic", "net", "gossip.f")

# Web server stack (string/url/headers already above)
DT_F        = os.path.join(ROOT_DIR, "akashic", "utils", "datetime.f")
TBL_F       = os.path.join(ROOT_DIR, "akashic", "utils", "table.f")
REQ_F       = os.path.join(ROOT_DIR, "akashic", "web", "request.f")
RESP_F      = os.path.join(ROOT_DIR, "akashic", "web", "response.f")
RTR_F       = os.path.join(ROOT_DIR, "akashic", "web", "router.f")
SRV_F       = os.path.join(ROOT_DIR, "akashic", "web", "server.f")

# JSON + RPC
JSON_F      = os.path.join(ROOT_DIR, "akashic", "utils", "json.f")
RPC_F       = os.path.join(ROOT_DIR, "akashic", "web", "rpc.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")


# ── Emulator helpers ──

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf)

def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc','psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
             'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
             'ivt_base','ivec_id','trap_addr','halted','idle','cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}

def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)


def build_snapshot():
    global _snapshot
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + blockchain + net + web + json + rpc ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    # Load all dependencies in correct order
    dep_lines = []
    for path in [
        # Concurrency
        EVENT_F, SEM_F, GUARD_F,
        # Crypto / math
        FP16_F, SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
        ED25519_F, SPHINCS_F,
        # CBOR + formatting
        CBOR_F, FMT_F,
        # Blockchain
        MERKLE_F, TX_F, STATE_F, BLOCK_F, CONSENSUS_F, MEMPOOL_F,
        # Net (string/url/headers shared with web)
        STRING_F, URL_F, HEADERS_F, BASE64_F, HTTP_F, WS_F, GOSSIP_F,
        # Web server
        DT_F, TBL_F, REQ_F, RESP_F, RTR_F, SRV_F,
        # JSON + RPC
        JSON_F, RPC_F,
    ]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        # String buffer for building HTTP requests
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Mock SEND for response.f — TYPE to UART
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
        # Mock socket ops for server.f — no-ops
        ': _SRV-SOCKET-MOCK  ( type -- sd ) DROP 1 ;',
        "' _SRV-SOCKET-MOCK _SRV-SOCKET-XT !",
        ': _SRV-BIND-MOCK  ( sd port -- ior ) 2DROP 0 ;',
        "' _SRV-BIND-MOCK _SRV-BIND-XT !",
        ': _SRV-LISTEN-MOCK  ( sd -- ior ) DROP 0 ;',
        "' _SRV-LISTEN-MOCK _SRV-LISTEN-XT !",
        ': _SRV-ACCEPT-MOCK  ( sd -- new-sd ) DROP -1 ;',
        "' _SRV-ACCEPT-MOCK _SRV-ACCEPT-XT !",
        ': _SRV-RECV-MOCK  ( sd addr max -- actual ) 2DROP DROP 0 ;',
        "' _SRV-RECV-MOCK _SRV-RECV-XT !",
        ': _SRV-CLOSE-MOCK  ( sd -- ) DROP ;',
        "' _SRV-CLOSE-MOCK _SRV-CLOSE-XT !",
        ': _SRV-POLL-MOCK  ( -- ) ;',
        "' _SRV-POLL-MOCK _SRV-POLL-XT !",
        ': _SRV-IDLE-MOCK  ( -- ) ;',
        "' _SRV-IDLE-MOCK _SRV-IDLE-XT !",
        # Suppress server logging
        '0 SRV-LOG-ENABLED !',
        # Initialize blockchain subsystems
        'ST-INIT',
        'MP-INIT',
        'GSP-INIT',
        # Register JSON-RPC route
        'ROUTE-CLEAR',
        'RPC-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 1_200_000_000
    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l.strip())
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        print(f"  Aborting — rpc.f failed to compile cleanly.")
        for l in text.strip().split('\n')[-40:]:
            print(f"    {l}")
        sys.exit(1)

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=100_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)


def tstr_compiled(s):
    """Build Forth lines to construct string s in _TB via TR/TC."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1:
            sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full:
        lines.append(full)
    return lines


def rpc_request(method, params=None, id_val=1):
    """Build a full HTTP POST /rpc request with JSON-RPC body."""
    body = '{"jsonrpc":"2.0","method":"' + method + '"'
    if id_val is not None:
        body += ',"id":' + str(id_val)
    if params is not None:
        body += ',"params":' + params
    body += '}'
    req = (f'POST /rpc HTTP/1.1\r\n'
           f'Host: test\r\n'
           f'Content-Type: application/json\r\n'
           f'Content-Length: {len(body)}\r\n'
           f'\r\n{body}')
    return req


# ── Test framework ──

_pass = 0; _fail = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        _pass += 1; print(f"  PASS  {name}")
    else:
        _fail += 1; print(f"  FAIL  {name}")
        if expected:
            print(f"        expected: {expected!r}")
        print(f"        got (last 5 lines):")
        for ln in clean.split('\n')[-5:]:
            print(f"          {ln}")


# =====================================================================
#  Tests
# =====================================================================

def test_compile():
    print("\n── Compile Check ──\n")

    check("rpc.f loads without errors",
          [': _T RPC-E-PARSE . RPC-E-METHOD . RPC-E-PARAMS . ; _T'],
          check_fn=lambda t: "-32700" in t and "-32601" in t and "-32602" in t)


def test_block_number():
    print("\n── chain_blockNumber ──\n")

    req = rpc_request("chain_blockNumber")
    check("chain_blockNumber returns height 0",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"result":0' in t and '"jsonrpc":"2.0"' in t)


def test_mempool_status():
    print("\n── mempool_status ──\n")

    req = rpc_request("mempool_status")
    check("mempool_status returns count 0",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"count":0' in t and '"result"' in t)


def test_node_info():
    print("\n── node_info ──\n")

    req = rpc_request("node_info")
    check("node_info returns height/peers/mempool",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: ('"height":0' in t and
                              '"peers":0' in t and
                              '"mempool":0' in t))


def test_unknown_method():
    print("\n── Unknown Method ──\n")

    req = rpc_request("bogus_method")
    check("unknown method returns error -32601",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '-32601' in t and 'method not found' in t)


def test_parse_error():
    print("\n── Parse Error (empty body) ──\n")

    # Minimal POST with empty body
    req = 'POST /rpc HTTP/1.1\r\nHost: test\r\nContent-Length: 0\r\n\r\n'
    check("empty body returns parse error -32700",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '-32700' in t and 'parse error' in t)


def test_get_balance():
    print("\n── chain_getBalance ──\n")

    # Valid 64-hex-char address (all zeros)
    addr = '0' * 64
    req = rpc_request("chain_getBalance", f'["{addr}"]')
    check("getBalance with valid address returns 0",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"result":0' in t and '"id":1' in t)

    # Invalid address (too short)
    req2 = rpc_request("chain_getBalance", '["abc123"]')
    check("getBalance with bad address returns error -32602",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '-32602' in t and '64 hex' in t)


def test_id_echo():
    print("\n── ID Echo ──\n")

    req = rpc_request("chain_blockNumber", id_val=42)
    check("id 42 is echoed in response",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"id":42' in t)

    req2 = rpc_request("chain_blockNumber", id_val=None)
    check("request without id omits id in response",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"id"' not in t and '"result":0' in t)


def test_repeated_requests():
    print("\n── Repeated Requests ──\n")

    req1 = rpc_request("chain_blockNumber", id_val=1)
    req2 = rpc_request("mempool_status", id_val=2)
    check("two sequential RPC requests both produce output",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req1)] +
          ['  TA SRV-HANDLE-BUF'] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '"id":1' in t and '"id":2' in t)


def test_http_200():
    print("\n── HTTP 200 Status ──\n")

    req = rpc_request("chain_blockNumber")
    check("response has HTTP 200 OK status line",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '200 OK' in t)

    check("response has application/json content-type",
          [': _T'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: 'application/json' in t)


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    test_compile()
    test_block_number()
    test_mempool_status()
    test_node_info()
    test_unknown_method()
    test_parse_error()
    test_get_balance()
    test_id_echo()
    test_repeated_requests()
    test_http_200()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail else 0)
