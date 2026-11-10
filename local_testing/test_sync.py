#!/usr/bin/env python3
"""Test suite for Akashic sync.f (akashic/net/sync.f).

Tests:
  - Module compilation
  - Constants (SYNC-IDLE, SYNC-ACTIVE, SYNC-STALLED)
  - SYNC-INIT resets state + wires callbacks
  - Announcement triggers ACTIVE + target tracking
  - Announcement ignored if already at height
  - Status handler same behavior as announcement
  - Multiple announcements: higher target wins
  - Retry limit → STALLED
  - SYNC-RESET → IDLE
  - SYNC-STEP when IDLE → no-op
  - SYNC-STEP deferred request flag
  - SYNC-PROGRESS query
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)

# Dependency file paths (combined blockchain + net)

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import run_file_tests, transcript_checks, module_source_lines, megapad_module_lines

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
    print("[*] Building snapshot: BIOS + KDOS + blockchain + net + sync ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

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
        "utils/string.f",
        "net/url.f",
        "net/headers.f",
        "net/base64.f",
        "net/http.f",
        "net/ws.f",
        "net/gossip.f",
        "net/sync.f",
    ))

    helpers = [
        # Init blockchain subsystems
        'ST-INIT',
        'MP-INIT',
        'GSP-INIT',
        'SYNC-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"] + megapad_module_lines("networking.f")
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 900_000_000
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


def run_forth(lines, max_steps=100_000_000):
    if _snapshot is None:
        build_snapshot()
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

# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check = transcript_checks(run_forth)[0]


# =====================================================================
#  Tests
# =====================================================================

def test_compile():
    print("\n── Compile Check ──\n")
    check("sync.f loads without errors",
          [': _T SYNC-IDLE . SYNC-ACTIVE . SYNC-STALLED . ; _T'],
          "0 1 2 ")


def test_constants():
    print("\n── Constants ──\n")
    check("SYNC-IDLE is 0",
          [': _T SYNC-IDLE . ; _T'], "0 ")
    check("SYNC-ACTIVE is 1",
          [': _T SYNC-ACTIVE . ; _T'], "1 ")
    check("SYNC-STALLED is 2",
          [': _T SYNC-STALLED . ; _T'], "2 ")


def test_init():
    print("\n── SYNC-INIT ──\n")
    check("SYNC-STATUS starts IDLE after INIT",
          [': _T SYNC-INIT SYNC-STATUS . ; _T'], "0 ")
    check("SYNC-TARGET starts 0",
          [': _T SYNC-INIT SYNC-TARGET . ; _T'], "0 ")
    check("SYNC-PEER starts -1",
          [': _T SYNC-INIT SYNC-PEER . ; _T'], "-1 ")
    check("SYNC-PROGRESS shows 0 0",
          [': _T SYNC-INIT SYNC-PROGRESS . . ; _T'],
          check_fn=lambda t: "0 " in t)


def test_announcement():
    print("\n── Announcement Handling ──\n")
    # Simulate: peer 3 announces height 5 (we're at 0)
    check("Announcement triggers ACTIVE",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           '  SYNC-STATUS . SYNC-TARGET . SYNC-PEER . ; _T'],
          "1 5 3 ")

    # Announce height <= our height → ignored
    check("Announcement at current height ignored",
          [': _T SYNC-INIT',
           '  0 2 _SYNC-ON-ANN',
           '  SYNC-STATUS . ; _T'],
          "0 ")

    # Higher announcement updates target while syncing
    check("Higher announcement updates target",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           '  10 7 _SYNC-ON-ANN',
           '  SYNC-TARGET . SYNC-PEER . ; _T'],
          "10 7 ")

    # Lower announcement while syncing is ignored
    check("Lower announcement during sync ignored",
          [': _T SYNC-INIT',
           '  10 3 _SYNC-ON-ANN',
           '  5 7 _SYNC-ON-ANN',
           '  SYNC-TARGET . SYNC-PEER . ; _T'],
          "10 3 ")


def test_status_handler():
    print("\n── Status Handler ──\n")
    check("Status triggers ACTIVE like announcement",
          [': _T SYNC-INIT',
           '  8 2 _SYNC-ON-STATUS',
           '  SYNC-STATUS . SYNC-TARGET . ; _T'],
          "1 8 ")


def test_need_req_flag():
    print("\n── Deferred Request Flag ──\n")
    check("Announcement sets deferred request flag",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           '  _SYNC-NEED-REQ @ . ; _T'],
          "-1 ")

    # SYNC-STEP when IDLE does nothing
    check("SYNC-STEP when IDLE is no-op",
          [': _T SYNC-INIT SYNC-STEP',
           '  SYNC-STATUS . ; _T'],
          "0 ")


def test_retry_stall():
    print("\n── Retry / Stall ──\n")
    # Simulate 5 consecutive decode failures → STALLED
    check("5 failures → STALLED",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           # Feed 5 garbage responses (0-length triggers decode fail)
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  SYNC-STATUS . ; _T'],
          "2 ")

    # 4 failures don't stall (still active with deferred request)
    check("4 failures stay ACTIVE",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  SYNC-STATUS . ; _T'],
          "1 ")


def test_reset():
    print("\n── SYNC-RESET ──\n")
    check("SYNC-RESET after stall goes to IDLE",
          [': _T SYNC-INIT',
           '  5 3 _SYNC-ON-ANN',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  0 0 _SYNC-ON-RSP',
           '  SYNC-STATUS .',            # should be 2 (STALLED)
           '  SYNC-RESET',
           '  SYNC-STATUS . ; _T'],      # should be 0 (IDLE)
          "2 0 ")


def test_response_when_idle():
    print("\n── Response When Not Syncing ──\n")
    check("Response while IDLE is dropped",
          [': _T SYNC-INIT',
           '  0 0 _SYNC-ON-RSP',
           '  SYNC-STATUS . ; _T'],
          "0 ")


def test_callbacks_wired():
    print("\n── Callback Wiring ──\n")
    # Verify callbacks are set by checking the XT variables
    check("GSP-ON-BLK-ANN-XT is set",
          [': _T SYNC-INIT',
           "  GSP-ON-BLK-ANN-XT @ 0<> IF 1 ELSE 0 THEN . ; _T"],
          "1 ")
    check("GSP-ON-BLK-RSP-XT is set",
          [': _T SYNC-INIT',
           "  GSP-ON-BLK-RSP-XT @ 0<> IF 1 ELSE 0 THEN . ; _T"],
          "1 ")
    check("GSP-ON-STATUS-XT is set",
          [': _T SYNC-INIT',
           "  GSP-ON-STATUS-XT @ 0<> IF 1 ELSE 0 THEN . ; _T"],
          "1 ")


def test_fallback_constants():
    """[FIX C03] Fallback peer selection constants."""
    print("\n── Fallback Constants (C03) ──\n")

    check("_SYNC-MAX-FALLBACK=3",
          [': _T _SYNC-MAX-FALLBACK . ; _T'], "3 ")

    check("_SYNC-FALLBACKS starts at 0",
          [': _T SYNC-INIT _SYNC-FALLBACKS @ . ; _T'], "0 ")


def test_next_peer_no_active():
    """[FIX C03] _SYNC-NEXT-PEER with no active peers returns -1."""
    print("\n── _SYNC-NEXT-PEER (C03) ──\n")

    check("_SYNC-NEXT-PEER no active → -1",
          [': _T SYNC-INIT _SYNC-NEXT-PEER . ; _T'],
          "-1 ")


def test_next_peer_with_active():
    """[FIX C03] _SYNC-NEXT-PEER finds an active peer."""
    print("\n── _SYNC-NEXT-PEER active (C03) ──\n")

    # Mark peer 5 as active, current peer is 3
    check("_SYNC-NEXT-PEER finds active peer 5",
          [': _T SYNC-INIT 3 _SYNC-PEER !',
           '  1 _GSP-ACTIVE 5 + C!',
           '  _SYNC-NEXT-PEER .',
           '  0 _GSP-ACTIVE 5 + C! ; _T'],
          "5 ")


def test_try_fallback_limit():
    """[FIX C03] _SYNC-TRY-FALLBACK refuses when limit reached."""
    print("\n── _SYNC-TRY-FALLBACK limit (C03) ──\n")

    check("_SYNC-TRY-FALLBACK at limit → 0",
          [': _T SYNC-INIT',
           '  _SYNC-MAX-FALLBACK _SYNC-FALLBACKS !',
           '  _SYNC-TRY-FALLBACK . ; _T'],
          "0 ")


def test_try_fallback_no_peers():
    """[FIX C03] _SYNC-TRY-FALLBACK with no active peers returns 0."""
    print("\n── _SYNC-TRY-FALLBACK no peers (C03) ──\n")

    check("_SYNC-TRY-FALLBACK no peers → 0",
          [': _T SYNC-INIT 0 _SYNC-FALLBACKS !',
           '  _SYNC-TRY-FALLBACK . ; _T'],
          "0 ")


def test_try_fallback_success():
    """[FIX C03] _SYNC-TRY-FALLBACK switches peer when available."""
    print("\n── _SYNC-TRY-FALLBACK success (C03) ──\n")

    # Mark peer 7 active, start syncing from peer 2, then fallback
    check("_SYNC-TRY-FALLBACK switches to peer 7",
          [': _T SYNC-INIT',
           '  5 2 _SYNC-ON-ANN',
           '  1 _GSP-ACTIVE 7 + C!',
           '  _SYNC-TRY-FALLBACK .',
           '  SYNC-PEER .',
           '  _SYNC-FALLBACKS @ .',
           '  0 _GSP-ACTIVE 7 + C! ; _T'],
          "-1 7 1 ")

    # Fallback resets retry counter
    check("_SYNC-TRY-FALLBACK resets retries",
          [': _T SYNC-INIT',
           '  5 2 _SYNC-ON-ANN',
           '  3 _SYNC-RETRIES !',
           '  1 _GSP-ACTIVE 7 + C!',
           '  _SYNC-TRY-FALLBACK DROP',
           '  _SYNC-RETRIES @ .',
           '  0 _GSP-ACTIVE 7 + C! ; _T'],
          "0 ")


# =====================================================================
#  Main
# =====================================================================


if __name__ == "__main__":
    run_file_tests(__file__)
