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
  - chain_getProof → the state tree's own proof, which a client checks
    against the state root from the response alone; a lone account's
    empty proof; a missing account's error
  - chain_getBlockProof and chain_getStateRoot → the roots and header
    fields they name, leaving no cell
  - chain_verifyProof → a proof from chain_getProof verifies as it came,
    a changed leaf, sibling or root does not, and malformed params get
    an error
"""
import hashlib, json, os, re, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)

# ── Dependency file paths (combined blockchain + net + web + rpc) ──

# Blockchain stack

# Network stack (string, url, headers shared with web)

# Web server stack (string/url/headers already above)

# JSON + RPC

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import KDOS_DIAGNOSTICS, _run_input, program_output, run_file_tests, transcript_checks, module_source_lines, megapad_module_lines

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# The mempool keeps 4096 transaction buffers of 8320 bytes in the dictionary,
# about 34 MB with their index and hashes.  KDOS gives the userland
# dictionary half of extended memory unless told otherwise, so the default
# split of 64 MiB could not hold them: ALLOT failed with "Userland
# dictionary full" and the load went on, so a later MP-ADD would copy a
# transaction over the words after the empty pool.  64 MiB with 16 MiB
# reserved for ALLOCATE leaves the dictionary about 48 MiB.
EXT_MEM_SIZE = 64 << 20
XMEM_RESERVE = 16 << 20


def _load_errors(text, lines):
    """The lines KDOS printed while loading LINES that report a refused line.

    The echo of the source is dropped first, since the source itself names
    some of these messages.
    """
    printed = program_output(text, lines)
    return [line.strip() for line in printed.split('\n')
            if ('?' in line and 'not found' in line.lower())
            or 'dictionary full' in line.lower()
            or any(item in line for item in KDOS_DIAGNOSTICS)]


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

def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = buf.append
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
    dep_lines = module_source_lines((
        "concurrency/event.f",
        "concurrency/semaphore.f",
        "concurrency/guard.f",
        "math/fp16.f",
        "math/crypto-acc.f",
        "math/sha512.f",
        "math/field.f",
        "math/sha3.f",
        "math/random.f",
        "math/ed25519.f",
        "math/sphincs-plus.f",
        "cbor/cbor.f",
        "utils/fmt.f",
        "math/merkle.f",
        "store/tx.f",
        "store/smt.f",
        "store/state.f",
        "store/block.f",
        "consensus/consensus.f",
        "store/mempool.f",
        "store/light.f",
        "utils/string.f",
        "net/url.f",
        "net/headers.f",
        "net/base64.f",
        "net/http.f",
        "net/ws.f",
        "net/gossip.f",
        "utils/datetime.f",
        "utils/table.f",
        "web/request.f",
        "web/response.f",
        "web/router.f",
        "web/server.f",
        "utils/json.f",
        "web/rpc.f",
    ))

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

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=EXT_MEM_SIZE)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + [f"{XMEM_RESERVE} U-XMEM-RESERVE!", "ENTER-USERLAND"] + megapad_module_lines("networking.f")
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    steps = _run_input(sys_obj, payload.encode(), 1_200_000_000, buf)

    text = uart_text(buf)

    if sys_obj.cpu.halted:
        tail = "\n".join(text.strip().split('\n')[-40:])
        raise AssertionError("CPU halted during compilation\n" + tail)

    errors = _load_errors(text, all_lines)
    if errors:
        tail = "\n".join(text.strip().split('\n')[-30:])
        raise AssertionError(
            f"{len(errors)} line(s) failed to load:\n" + "\n".join(errors[-10:])
            + "\n--- transcript tail ---\n" + tail)

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=200_000_000):
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=EXT_MEM_SIZE)
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
    _run_input(sys_obj, payload.encode(), max_steps, buf)
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

# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check = transcript_checks(run_forth)[0]


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


def test_proof_buffer_size():
    """[FIX A01] _RPC-PROOF is now 10240 bytes."""
    print("\n── Proof Buffer A01 ──\n")

    # Write byte 0xAB at offset 10239 (last byte) and read it back
    check("_RPC-PROOF last byte at offset 10239",
          [': _T 171 _RPC-PROOF 10239 + C! _RPC-PROOF 10239 + C@ . ; _T'],
          "171 ")


def test_rate_limiter():
    """[FIX P30] Token-bucket rate limiter."""
    print("\n── Rate Limiter P30 ──\n")

    check("_RPC-RATE-MAX = 50",
          [': _T _RPC-RATE-MAX . ; _T'], "50 ")

    check("_RPC-RATE-CHECK returns TRUE when tokens available",
          [': _T _RPC-RATE-INIT _RPC-RATE-CHECK IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    # Drain all 50 tokens, then the 51st should fail
    check("_RPC-RATE-CHECK returns FALSE after bucket exhausted",
          [': _DRAIN 50 0 DO _RPC-RATE-CHECK DROP LOOP ;',
           ': _T _RPC-RATE-INIT _DRAIN _RPC-RATE-CHECK IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    # Rate-reject sends 429
    req = rpc_request("chain_blockNumber")
    check("rate-limited request gets 429",
          [': _DRAIN 50 0 DO _RPC-RATE-CHECK DROP LOOP ;',
           ': _T _RPC-RATE-INIT _DRAIN'] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: '429' in t and 'rate limit' in t)


def test_broadcast_after_send():
    """[FIX P28] sendTransaction calls GSP-BROADCAST-TX after MP-ADD.

    We can't easily test actual broadcast (no peers), but we verify the
    code path doesn't crash.  We send a valid-looking TX and check for
    a result (tx hash) rather than an error.  If broadcast crashed, we'd
    get nothing or an error.
    
    NOTE: if TX-DECODE / MP-ADD rejects, P28 doesn't fire anyway.
    This is more of a compile-level test that the word reference exists.
    """
    print("\n── Broadcast P28 ──\n")

    # Verify GSP-BROADCAST-TX word exists (can be ticked)
    check("GSP-BROADCAST-TX is defined",
          [": _T ['] GSP-BROADCAST-TX 0<> IF 1 ELSE 0 THEN . ; _T"],
          "1 ")


# The proof and root methods answer with roots, so their tests print the
# root they expect, as hex from FMT->HEX like the response's, and the cells
# a request leaves on the stack.

_ACCOUNTS = [
    'CREATE _A 32 ALLOT  _A 32 7 FILL',
    'CREATE _B 32 ALLOT  _B 32 9 FILL',
    'CREATE _WANT 64 ALLOT',
    ': _W ST-ROOT DROP 32 _WANT FMT->HEX DROP ." want=" _WANT 64 TYPE CR ;',
]


def _handled(req):
    """Lines that send REQ through the server and print the cells it left."""
    return ([': _T DEPTH >R'] +
            ['  ' + l for l in tstr_compiled(req)] +
            ['  TA SRV-HANDLE-BUF CR ." left=" DEPTH R> - . ; _T'])


def _want(text):
    found = re.search(r'want=([0-9A-Fa-f]{64})', text)
    return found.group(1) if found else None


def _response(text):
    """The JSON-RPC response the server printed, as Python values."""
    for line in text.split('\n'):
        line = line.strip()
        if line.startswith('{"jsonrpc"'):
            return json.loads(line)
    return None


def _client_check(result):
    """Check a getProof result as a light client would, from it alone.

    The entry's hash must be the leaf, the entry must begin with the
    address and hold the balance and nonce reported, and the proof must
    climb from the leaf to the state root: each entry names a branch's bit
    position and the hash of its other child, root to leaf, and the
    address's bit there, most significant first, says which side the
    climbing hash takes.
    """
    entry = bytes.fromhex(result['entry'])
    address = bytes.fromhex(result['address'])
    leaf = hashlib.sha3_256(entry).digest()
    node = hashlib.sha3_256(b'\x00' + address + leaf).digest()
    for step in reversed(result['proof']):
        bit = step['bit']
        sibling = bytes.fromhex(step['sibling'])
        right = (address[bit >> 3] >> (7 - (bit & 7))) & 1
        pair = sibling + node if right else node + sibling
        node = hashlib.sha3_256(b'\x01' + pair).digest()
    return (len(entry) == 72
            and entry[:32] == address
            and int.from_bytes(entry[32:40], 'little') == result['balance']
            and int.from_bytes(entry[40:48], 'little') == result['nonce']
            and leaf.hex() == result['leaf'].lower()
            and node.hex() == result['stateRoot'].lower())


# Three accounts whose addresses first differ at bit 4 (07.. against 08..
# and 09..) and at bit 7 (08.. against 09..), so _B's proof has two entries.
_THREE = _ACCOUNTS + ['CREATE _C 32 ALLOT  _C 32 8 FILL',
                      '_A 1000 ST-CREATE DROP', '_B 2000 ST-CREATE DROP',
                      '_C 3000 ST-CREATE DROP']


def _get_proof(setup, address):
    """Run getProof for ADDRESS after SETUP; the transcript and result."""
    lines = setup + ['_W'] + _handled(
        rpc_request("chain_getProof", '["' + address + '"]'))
    text = run_forth(lines)
    response = _response(text)
    return text, (response or {}).get('result')


def test_get_proof():
    """chain_getProof gives the state tree's proof with the current root."""
    print("\n── chain_getProof ──\n")

    # The server and dispatcher leave no cell of their own.
    check("a blockNumber request leaves no cell",
          _handled(rpc_request("chain_blockNumber")),
          check_fn=lambda t: '"result":' in t and 'left=0 ' in t)

    text, result = _get_proof(_THREE, '09' * 32)
    assert result is not None, text[-2000:]
    assert result['stateRoot'].lower() == (_want(text) or '').lower(), result
    assert result['address'].lower() == '09' * 32, result
    assert result['balance'] == 2000 and result['nonce'] == 0, result
    assert [step['bit'] for step in result['proof']] == [4, 7], result
    assert _client_check(result), result
    assert 'left=0 ' in text, text[-600:]


def test_get_proof_lone_and_missing():
    """A lone account's proof is empty; a missing account is an error."""
    print("\n── chain_getProof lone and missing ──\n")

    lone = _ACCOUNTS + ['_A 1000 ST-CREATE DROP']
    text, result = _get_proof(lone, '07' * 32)
    assert result is not None, text[-2000:]
    assert result['proof'] == [], result
    assert _client_check(result), result
    assert 'left=0 ' in text, text[-600:]

    check("getProof for a missing account is an error and leaves no cell",
          lone + ['_W'] + _handled(
              rpc_request("chain_getProof", '["' + '09' * 32 + '"]')),
          check_fn=lambda t: ('account not found' in t and '"result"' not in t
                              and 'left=0 ' in t))


def _verify_request(*params):
    return rpc_request("chain_verifyProof",
                       json.dumps(list(params), separators=(',', ':')))


def _flip(hex_text):
    """HEX_TEXT with its first byte changed."""
    return '%02x' % (int(hex_text[:2], 16) ^ 1) + hex_text[2:]


def test_verify_proof_round_trip():
    """A proof from chain_getProof verifies through chain_verifyProof.

    The address, leaf, proof and root go back exactly as getProof gave
    them, in a run from the same state.  A changed leaf, sibling or root
    must not verify."""
    print("\n── chain_verifyProof round trip ──\n")

    text, result = _get_proof(_THREE, '09' * 32)
    assert result is not None, text[-2000:]
    address, leaf, proof, root = (result['address'], result['leaf'],
                                  result['proof'], result['stateRoot'])
    check("getProof's proof verifies as it came",
          _THREE + _handled(_verify_request(address, leaf, proof, root)),
          check_fn=lambda t: '"result":true' in t and 'left=0 ' in t)

    other_sibling = [dict(proof[0], sibling=_flip(proof[0]['sibling']))] + proof[1:]
    for name, request in (
            ("a changed leaf", _verify_request(address, _flip(leaf), proof, root)),
            ("a changed sibling", _verify_request(address, leaf, other_sibling, root)),
            ("a changed root", _verify_request(address, leaf, proof, _flip(root)))):
        check(f"{name} does not verify",
              _THREE + _handled(request),
              check_fn=lambda t: '"result":false' in t and 'left=0 ' in t)

    # A lone account's empty proof verifies against its root too.
    lone = _ACCOUNTS + ['_A 1000 ST-CREATE DROP']
    text, result = _get_proof(lone, '07' * 32)
    assert result is not None, text[-2000:]
    check("a lone account's empty proof verifies",
          lone + _handled(_verify_request(result['address'], result['leaf'],
                                          result['proof'], result['stateRoot'])),
          check_fn=lambda t: '"result":true' in t and 'left=0 ' in t)


def test_get_block_proof():
    """chain_getBlockProof reads every field from the block it found."""
    print("\n── chain_getBlockProof ──\n")

    req = rpc_request("chain_getBlockProof", '[0]')
    check("getBlockProof gives the genesis header's fields",
          _ACCOUNTS + ['_A 1000 ST-CREATE DROP', 'CHAIN-INIT', '_W'] +
          _handled(req),
          check_fn=lambda t: (_want(t) is not None
                              and '"height":0' in t
                              and '"prevHash":"' + '0' * 64 + '"' in t
                              and f'"stateRoot":"{_want(t)}"' in t
                              and '"timestamp":0' in t
                              and 'left=0 ' in t))


def test_get_state_root():
    """chain_getStateRoot gives the current root without a height."""
    print("\n── chain_getStateRoot ──\n")

    # The genesis block holds the empty state's root, all zeros; the
    # account created after it moves the current root.
    setup = _ACCOUNTS + ['CHAIN-INIT', '_A 1000 ST-CREATE DROP', '_W']
    check("getStateRoot without params gives the current root",
          setup + _handled(rpc_request("chain_getStateRoot")),
          check_fn=lambda t: (_want(t) is not None
                              and f'"result":"{_want(t)}"' in t
                              and 'left=0 ' in t))

    check("getStateRoot at height 0 gives the genesis root",
          setup + _handled(rpc_request("chain_getStateRoot", '[0]')),
          check_fn=lambda t: ('"result":"' + '0' * 64 + '"' in t
                              and 'left=0 ' in t))


def test_verify_proof_params():
    """chain_verifyProof refuses malformed params and leaves no cell."""
    print("\n── chain_verifyProof params ──\n")

    good = {'bit': 3, 'sibling': '44' * 32}
    for name, request, message in (
            ("a short address", _verify_request('11' * 31, '22' * 32, [good], '33' * 32),
             "address must be 64 hex chars"),
            ("a short leaf", _verify_request('11' * 32, '22', [good], '33' * 32),
             "leaf must be 64 hex chars"),
            ("a proof that is no array", _verify_request('11' * 32, '22' * 32, '44' * 32, '33' * 32),
             "proof must be an array"),
            ("an entry without its sibling", _verify_request('11' * 32, '22' * 32, [{'bit': 3}], '33' * 32),
             "proof must be an array"),
            ("a short root", _verify_request('11' * 32, '22' * 32, [good], '33'),
             "root must be 64 hex chars")):
        check(f"{name} is refused",
              _handled(request),
              check_fn=lambda t, m=message: ('-32602' in t and m in t
                                             and 'left=0 ' in t))

    # A well-formed proof that does not reach the root reads every param.
    check("a well-formed proof is read and answered",
          _handled(_verify_request('11' * 32, '22' * 32, [good], '33' * 32)) + [
              ': _V ." len=" _RPC-VP-LEN @ . ." bit=" _RPC-PROOF @ .',
              '  ." sibling=" _RPC-PROOF 8 + C@ . ." leaf=" _RPC-LEAF C@ .',
              '  ." root=" _RPC-ROOT C@ . ; _V'],
          check_fn=lambda t: ('"result":false' in t and 'left=0 ' in t
                              and 'len=1 bit=3 sibling=68 leaf=34 root=51 ' in t))


# =====================================================================
#  Main
# =====================================================================


if __name__ == "__main__":
    run_file_tests(__file__)
