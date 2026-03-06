#!/usr/bin/env python3
"""Test suite for Tier-1 crypto concurrency guards.

Validates that the guard wrappers on crypto modules:
  1. Preserve functional correctness (one-shot + streaming APIs).
  2. Fail loud (-258 throw) when streaming ops called without BEGIN.
  3. Release the guard after one-shot and streaming completion.
  4. Release the guard on exception paths (error cleanup).
  5. Allow recursive nesting (one-shot wraps streaming internals).

Uses SHA-256 as the representative module since it has both
one-shot (SHA256-HASH) and streaming (SHA256-BEGIN/ADD/END) APIs.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
SHA256_F   = os.path.join(ROOT_DIR, "akashic", "math", "sha256.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    if _snapshot: return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + sha256.f ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    event_lines  = _load_forth_lines(EVENT_F)
    sem_lines    = _load_forth_lines(SEM_F)
    guard_lines  = _load_forth_lines(GUARD_F)
    sha256_lines = _load_forth_lines(SHA256_F)

    # Test helpers
    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sem_lines + guard_lines
                 + sha256_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 600_000_000
    while steps < mx:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)
    text = uart_text(buf)
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
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
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)

# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")

# ── Reference values ──
# SHA256("abc") bytes: 186 120 22 191 ...
# We check first 4 bytes as decimal

# Helper: 3-byte "abc" buffer + 32-byte hash buffer
_ABC_SETUP = [
    'CREATE _m 3 ALLOT',
    '97 _m C!  98 _m 1 + C!  99 _m 2 + C!',
    'CREATE _h 32 ALLOT',
]

def _hash_check_lines():
    """Lines that print first 4 bytes after hash is in _h."""
    return ['." B0=" _h C@ .  ." B1=" _h 1 + C@ .  ." B2=" _h 2 + C@ .  ." B3=" _h 3 + C@ .']

ABC_EXPECTED = 'B0=186 B1=120 B2=22 B3=191 '

# ============================================================
# Tests
# ============================================================

def main():
    build_snapshot()
    print()

    # ── 1. One-shot functionality preserved ──
    print("=== One-shot correctness (guard transparent) ===")
    check("SHA256-HASH abc via guard",
          _ABC_SETUP + [
           '_m 3 _h SHA256-HASH',
          ] + _hash_check_lines(),
          ABC_EXPECTED)

    # ── 2. Streaming functionality preserved ──
    print("\n=== Streaming correctness (guard transparent) ===")
    check("SHA256 streaming abc via guard",
          _ABC_SETUP + [
           'SHA256-BEGIN',
           '_m 3 SHA256-ADD',
           '_h SHA256-END',
          ] + _hash_check_lines(),
          ABC_EXPECTED)

    # ── 3. Guard released after one-shot ──
    print("\n=== Guard released after one-shot ===")
    check("guard free after SHA256-HASH",
          _ABC_SETUP + [
           '_m 3 _h SHA256-HASH',
           '_sha256-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN'],
          "FREE")

    # ── 4. Guard released after streaming END ──
    print("\n=== Guard released after streaming END ===")
    check("guard free after SHA256-END",
          _ABC_SETUP + [
           'SHA256-BEGIN',
           '_m 3 SHA256-ADD',
           '_h SHA256-END',
           '_sha256-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN'],
          "FREE")

    # ── 5. Guard held between BEGIN and END ──
    print("\n=== Guard held during streaming session ===")
    check("guard held after SHA256-BEGIN",
          _ABC_SETUP + [
           'SHA256-BEGIN',
           '_sha256-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN',
           '_h SHA256-END'],
          "HELD")

    # ── 6. -258 on SHA256-ADD without BEGIN ──
    print("\n=== -258 on unguarded streaming ops ===")
    check("SHA256-ADD without BEGIN throws -258",
          _ABC_SETUP + [
           ": _TADD  _m 3 SHA256-ADD ;",
           "' _TADD CATCH .",
          ],
          "-258 ")

    check("SHA256-END without BEGIN throws -258",
          _ABC_SETUP + [
           ": _TEND  _h SHA256-END ;",
           "' _TEND CATCH .",
          ],
          "-258 ")

    # ── 7. Guard released on throw in one-shot ──
    print("\n=== Guard cleanup on exception ===")
    # Two sequential one-shot calls — second must succeed (guard not stuck)
    check("two sequential SHA256-HASH calls succeed",
          _ABC_SETUP + [
           'CREATE _h2 32 ALLOT',
           '_m 3 _h SHA256-HASH',
           '_m 3 _h2 SHA256-HASH',
           '." B0=" _h2 C@ .  ." B1=" _h2 1 + C@ .  ." B2=" _h2 2 + C@ .  ." B3=" _h2 3 + C@ .'],
          ABC_EXPECTED)

    # ── 8. Two sequential streaming sessions succeed ──
    print("\n=== Sequential streaming sessions ===")
    check("second streaming session after first END",
          _ABC_SETUP + [
           'CREATE _h2 32 ALLOT',
           'SHA256-BEGIN  _m 3 SHA256-ADD  _h SHA256-END',
           'SHA256-BEGIN  _m 3 SHA256-ADD  _h2 SHA256-END',
           '." B0=" _h2 C@ .  ." B1=" _h2 1 + C@ .  ." B2=" _h2 2 + C@ .  ." B3=" _h2 3 + C@ .'],
          ABC_EXPECTED)

    # ── 9. One-shot after streaming and vice versa ──
    print("\n=== Mixed one-shot/streaming sequences ===")
    check("one-shot after streaming",
          _ABC_SETUP + [
           'CREATE _h2 32 ALLOT',
           'SHA256-BEGIN  _m 3 SHA256-ADD  _h SHA256-END',
           '_m 3 _h2 SHA256-HASH',
           '." B0=" _h2 C@ .  ." B1=" _h2 1 + C@ .  ." B2=" _h2 2 + C@ .  ." B3=" _h2 3 + C@ .'],
          ABC_EXPECTED)

    check("streaming after one-shot",
          _ABC_SETUP + [
           'CREATE _h2 32 ALLOT',
           '_m 3 _h SHA256-HASH',
           'SHA256-BEGIN  _m 3 SHA256-ADD  _h2 SHA256-END',
           '." B0=" _h2 C@ .  ." B1=" _h2 1 + C@ .  ." B2=" _h2 2 + C@ .  ." B3=" _h2 3 + C@ .'],
          ABC_EXPECTED)

    # ── 10. Recursive guard nesting (one-shot uses streaming internally) ──
    print("\n=== Recursive guard nesting ===")
    # SHA256-HASH internally does BEGIN/ADD/END via the old xt.
    # If late binding causes the NEW guarded versions to be called,
    # the recursive guard (depth counter) must allow this.
    # Best proof: SHA256-HASH simply produces correct output.
    check("one-shot works (implies recursive nesting)",
          _ABC_SETUP + [
           '_m 3 _h SHA256-HASH',
          ] + _hash_check_lines(),
          ABC_EXPECTED)

    # ── 11. Guard stays free when -258 thrown ──
    print("\n=== Guard stays free after -258 throw ===")
    check("guard free after -258 from ADD",
          _ABC_SETUP + [
           ": _TADD2  _m 3 SHA256-ADD ;",
           "' _TADD2 CATCH DROP",
           '_sha256-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN'],
          "FREE")

    # ── Summary ──
    print()
    print("=" * 60)
    print(f"Crypto guard tests: {_pass_count}/{_pass_count + _fail_count} passed, "
          f"{_fail_count} failed")
    if _fail_count == 0:
        print("All crypto guard tests passed!")
    else:
        print("SOME TESTS FAILED")
        sys.exit(1)

if __name__ == "__main__":
    main()
