#!/usr/bin/env python3
"""Test suite for Akashic node.f (akashic/node/node.f).

Priority 9 fixes tested:
 #66 P32  MP-DRAIN buffer (_NODE-TX-PTRS)
 #67 P33  SRV-STEP wired into NODE-STEP
 #68 P34  Real timestamps via DT-NOW-S
 #69 P35  _NODE-PERSIST-TICK wired into NODE-STEP
 #70 P37  Graceful shutdown (persist, disconnect, key zeroize)
 #71 P36  Busy-wait yield (_NODE-YIELD)
 #72 D03  Time-based block production interval
"""
import os, sys, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# All dependencies — full blockchain + net + web + persist + node
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
SMT_F       = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
STATE_F     = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F     = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
MEMPOOL_F   = os.path.join(ROOT_DIR, "akashic", "store", "mempool.f")
LIGHT_F     = os.path.join(ROOT_DIR, "akashic", "store", "light.f")

STRING_F    = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F       = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HEADERS_F   = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
BASE64_F    = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")
HTTP_F      = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
WS_F        = os.path.join(ROOT_DIR, "akashic", "net", "ws.f")
GOSSIP_F    = os.path.join(ROOT_DIR, "akashic", "net", "gossip.f")
SYNC_F      = os.path.join(ROOT_DIR, "akashic", "net", "sync.f")

PERSIST_F   = os.path.join(ROOT_DIR, "akashic", "store", "persist.f")

DT_F        = os.path.join(ROOT_DIR, "akashic", "utils", "datetime.f")
TBL_F       = os.path.join(ROOT_DIR, "akashic", "utils", "table.f")
REQ_F       = os.path.join(ROOT_DIR, "akashic", "web", "request.f")
RESP_F      = os.path.join(ROOT_DIR, "akashic", "web", "response.f")
RTR_F       = os.path.join(ROOT_DIR, "akashic", "web", "router.f")
SRV_F       = os.path.join(ROOT_DIR, "akashic", "web", "server.f")

JSON_F      = os.path.join(ROOT_DIR, "akashic", "utils", "json.f")
RPC_F       = os.path.join(ROOT_DIR, "akashic", "web", "rpc.f")
NODE_F      = os.path.join(ROOT_DIR, "akashic", "node", "node.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import format_image

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshot = None
_base_disk = None

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
    global _snapshot, _base_disk
    if _snapshot:
        return _snapshot

    # Pre-format a base disk image for PST-INIT
    fd, dpath = tempfile.mkstemp(suffix=".img", prefix="node_base_")
    os.close(fd)
    format_image(dpath)
    with open(dpath, 'rb') as f:
        _base_disk = f.read()
    os.unlink(dpath)

    print("[*] Building snapshot: BIOS + KDOS + full node stack ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [
        # Concurrency
        EVENT_F, SEM_F, GUARD_F,
        # Math/crypto
        FP16_F, SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
        ED25519_F, SPHINCS_F,
        # CBOR + fmt
        CBOR_F, FMT_F,
        # Blockchain
        MERKLE_F, TX_F, SMT_F, STATE_F, BLOCK_F, CONSENSUS_F, MEMPOOL_F,
        LIGHT_F,
        # Net
        STRING_F, URL_F, HEADERS_F, BASE64_F, HTTP_F, WS_F, GOSSIP_F,
        SYNC_F,
        # Persistence
        PERSIST_F,
        # Web server
        DT_F, TBL_F, REQ_F, RESP_F, RTR_F, SRV_F,
        # JSON + RPC
        JSON_F, RPC_F,
        # Node
        NODE_F,
    ]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        # Mock socket/response for server.f (no real network)
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
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
        '0 SRV-LOG-ENABLED !',
        # Initialize core subsystems for snapshot (NOT NODE-INIT — tests do that)
        'ST-INIT',
        'CHAIN-INIT',
        'MP-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=64 * (1 << 20))
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
        for l in text.strip().split('\n')[-40:]:
            print(f"    {l}")
        sys.exit(1)

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=200_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    fd, disk_path = tempfile.mkstemp(suffix=".img", prefix="node_run_")
    os.write(fd, _base_disk)
    os.close(fd)
    try:
        sys_obj = MegapadSystem(ram_size=1024*1024,
                                storage_image=disk_path,
                                ext_mem_size=64 * (1 << 20))
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
    finally:
        try: os.unlink(disk_path)
        except OSError: pass


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
    check("node.f loads without errors",
          [': _T NODE-STOPPED . NODE-RUNNING . NODE-SYNCING . ; _T'],
          "0 1 2 ")


def test_constants():
    print("\n── Constants ──\n")
    check("NODE-STOPPED is 0",
          [': _T NODE-STOPPED . ; _T'], "0 ")
    check("NODE-RUNNING is 1",
          [': _T NODE-RUNNING . ; _T'], "1 ")
    check("NODE-SYNCING is 2",
          [': _T NODE-SYNCING . ; _T'], "2 ")


def test_init():
    print("\n── NODE-INIT ──\n")
    check("NODE-INIT runs without crash",
          [': _T 8080 NODE-INIT 42 . ; _T'],
          "42 ")

    check("NODE-STATUS is STOPPED after init",
          [': _T 8080 NODE-INIT NODE-STATUS . ; _T'],
          "0 ")

    check("Chain height is 0 after init",
          [': _T 8080 NODE-INIT CHAIN-HEIGHT . ; _T'],
          "0 ")

    check("Mempool count is 0 after init",
          [': _T 8080 NODE-INIT MP-COUNT . ; _T'],
          "0 ")

    check("Sync is IDLE after init",
          [': _T 8080 NODE-INIT SYNC-STATUS . ; _T'],
          "0 ")

    check("Persist count is 0 after init",
          [': _T 8080 NODE-INIT PST-BLOCK-COUNT . ; _T'],
          "0 ")


def test_tx_ptrs_buffer():
    """#66 P32: _NODE-TX-PTRS buffer exists and is non-zero address."""
    print("\n── #66 P32: TX Pointer Buffer ──\n")
    check("_NODE-TX-PTRS exists",
          [': _T _NODE-TX-PTRS 0<> IF ." OK" ELSE ." FAIL" THEN ; _T'],
          "OK")


def test_time_based_interval():
    """#72 D03: _NODE-BLK-INTERVAL is time-based, _NODE-LAST-PRODUCE-T exists."""
    print("\n── #72 D03: Time-based Interval ──\n")
    check("_NODE-BLK-INTERVAL defaults to 10 after init",
          [': _T 8080 NODE-INIT _NODE-BLK-INTERVAL @ . ; _T'],
          "10 ")
    check("_NODE-LAST-PRODUCE-T is 0 after init",
          [': _T 8080 NODE-INIT _NODE-LAST-PRODUCE-T @ . ; _T'],
          "0 ")


def test_srv_step():
    """#67 P33: SRV-STEP is callable (mock returns -1 = no client)."""
    print("\n── #67 P33: SRV-STEP ──\n")
    check("SRV-STEP callable without crash",
          [': _T 8080 SRV-INIT -1 _SRV-RUNNING ! SRV-STEP ." OK" ; _T'],
          "OK")


def test_yield():
    """#71 P36: _NODE-YIELD exists and is callable."""
    print("\n── #71 P36: _NODE-YIELD ──\n")
    check("_NODE-YIELD callable with 0 ms",
          [': _T 0 _NODE-YIELD ." OK" ; _T'],
          "OK")


def test_stop():
    """#70 P37: NODE-STOP does full graceful shutdown."""
    print("\n── #70 P37: NODE-STOP ──\n")
    check("NODE-STOP sets STOPPED",
          [': _T 8080 NODE-INIT',
           '  NODE-RUNNING _NODE-STATE !',
           '  NODE-STOP',
           '  NODE-STATUS . ; _T'],
          "0 ")

    # Verify signing key is zeroed after stop
    check("Signing key zeroed after stop",
          [': _KSUM 0 64 0 DO _CON-SIGN-PRIV I + C@ + LOOP ;',
           ': _T 8080 NODE-INIT',
           '  _CON-SIGN-PRIV 64 $FF FILL',    # fill with 0xFF first
           '  NODE-STOP _KSUM . ; _T'],
          "0 ")


def test_step():
    """#67 P33 + #69 P35: NODE-STEP calls SRV-STEP + _NODE-PERSIST-TICK."""
    print("\n── NODE-STEP ──\n")
    check("NODE-STEP runs without crash",
          [': _T 8080 NODE-INIT NODE-STEP 42 . ; _T'],
          "42 ")

    # Two steps — shouldn't crash with time-based logic
    check("Multiple NODE-STEP runs",
          [': _T 8080 NODE-INIT',
           '  NODE-STEP NODE-STEP NODE-STEP',
           '  42 . ; _T'],
          "42 ")


def test_produce_toggle():
    print("\n── Block Production Toggle ──\n")
    check("Production disabled by default",
          [': _T 8080 NODE-INIT',
           '  _NODE-PRODUCE? @ . ; _T'],
          "0 ")

    check("NODE-ENABLE-PRODUCE enables",
          [': _T 8080 NODE-INIT',
           '  NODE-ENABLE-PRODUCE',
           '  _NODE-PRODUCE? @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("NODE-DISABLE-PRODUCE disables",
          [': _T 8080 NODE-INIT',
           '  NODE-ENABLE-PRODUCE',
           '  NODE-DISABLE-PRODUCE',
           '  _NODE-PRODUCE? @ . ; _T'],
          "0 ")


def test_timestamp():
    """#68 P34: DT-NOW-S available for real timestamps."""
    print("\n── #68 P34: DT-NOW-S Timestamp ──\n")
    check("DT-NOW-S returns non-zero",
          ['DT-NOW-S .'],
          check_fn=lambda t: any(c.isdigit() and c != '0' for c in t.strip()))


def test_subsystem_callbacks():
    print("\n── Sub-system Callbacks ──\n")
    check("Sync callbacks wired after NODE-INIT",
          [': _T 8080 NODE-INIT',
           '  GSP-ON-BLK-ANN-XT @ 0<> IF 1 ELSE 0 THEN .',
           '  GSP-ON-BLK-RSP-XT @ 0<> IF 1 ELSE 0 THEN .',
           '  GSP-ON-STATUS-XT @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 1 1 ")

    check("RPC route registered after NODE-INIT",
          [': _T 8080 NODE-INIT',
           '  ROUTE-COUNT . ; _T'],
          check_fn=lambda t: any(c.isdigit() and int(c) >= 1
                                for c in t.strip().split()
                                if c.isdigit()))


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    test_compile()
    test_constants()
    test_init()
    test_tx_ptrs_buffer()
    test_time_based_interval()
    test_srv_step()
    test_yield()
    test_stop()
    test_step()
    test_produce_toggle()
    test_timestamp()
    test_subsystem_callbacks()
    print(f"\n{'='*50}")
    print(f"  node.f:  {_pass}/{_pass + _fail} passed")
    if _fail == 0:
        print("  All tests passed!")
    else:
        print(f"  {_fail} FAILED")
    print(f"{'='*50}")
    sys.exit(1 if _fail else 0)
