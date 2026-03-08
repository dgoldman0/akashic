#!/usr/bin/env python3
# ┌──────────────────────────────────────────────────────────────┐
# │ HARNESS UPDATE REQUIRED (March 2026)                         │
# │                                                              │
# │ 1. BOOT-TO-IDLE: run_forth() must call boot() on a fresh    │
# │    MegapadSystem before overwriting RAM/CPU state from the   │
# │    snapshot.  Without boot(), the C++ accelerator's MMIO     │
# │    routing (UART writes) is never wired → empty output.      │
# │    Fix: save bios_code in the snapshot tuple, then in        │
# │    run_forth(): load_binary(0, bios_code), boot(), run to    │
# │    idle, THEN overwrite mem/cpu/ext from snapshot.           │
# │                                                              │
# │ 2. NO [: ;] CLOSURES: This BIOS/KDOS does not define the    │
# │    [: ... ;] anonymous quotation words.  Replace all uses    │
# │    with named helper words and ['] ticks.                    │
# │                                                              │
# │ See test_coroutine.py for the corrected pattern.             │
# └──────────────────────────────────────────────────────────────┘
"""Test suite for Akashic STARK prover/verifier v2.5 (akashic/math/stark.f).

Tests STARK-INIT, STARK-SET-COLS, STARK-SET-AIR, STARK-TRACE!/TRACE@,
STARK-PROVE, STARK-VERIFY, and STARK-FRI-FINAL@ with Fibonacci AIR.

Depends on: sha3.f ntt.f baby-bear.f merkle.f stark-air.f stark.f
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

SHA3_F     = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
NTT_F      = os.path.join(ROOT_DIR, "akashic", "math", "ntt.f")
BB_F       = os.path.join(ROOT_DIR, "akashic", "math", "baby-bear.f")
MERKLE_F   = os.path.join(ROOT_DIR, "akashic", "math", "merkle.f")
AIR_F      = os.path.join(ROOT_DIR, "akashic", "math", "stark-air.f")
STARK_F    = os.path.join(ROOT_DIR, "akashic", "math", "stark.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
SEMA_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

Q = 2013265921

# ── Emulator helpers ─────────────────────────────────────────────────

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
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
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
    print("[*] Building snapshot: BIOS + KDOS + guard + sha3 + ntt + baby-bear + merkle + stark-air + stark ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sema_lines = _load_forth_lines(SEMA_F)
    guard_lines = _load_forth_lines(GUARD_F)
    sha3_lines = _load_forth_lines(SHA3_F)
    ntt_lines  = _load_forth_lines(NTT_F)
    bb_lines   = _load_forth_lines(BB_F)
    mk_lines   = _load_forth_lines(MERKLE_F)
    air_lines  = _load_forth_lines(AIR_F)
    stark_lines = _load_forth_lines(STARK_F)

    sys_obj = MegapadSystem(ram_size=2*1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sema_lines + guard_lines
                 + sha3_lines + ntt_lines + bb_lines
                 + mk_lines + air_lines + stark_lines)
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
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l.strip())
            print(f"  [!] {l}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors!")
        print(f"  Aborting — stark.f failed to compile cleanly.")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=800_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=2*1024*1024, ext_mem_size=16 * (1 << 20))
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

# ── Test framework ───────────────────────────────────────────────────

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
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

def check_fn(name, forth_lines, predicate, desc=""):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if predicate(clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  ({desc})")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

# =====================================================================
#  Fibonacci setup helper
# =====================================================================

FIB_AIR_SETUP = [
    '1 AIR-BEGIN',
    '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
    '  0 0 1 AIR-BOUNDARY',
    '  0 1 1 AIR-BOUNDARY',
    'AIR-END CONSTANT _TEST-FIB-AIR',
]

FIB_TRACE_FILL = [
    ': _fill-fib-trace',
    '  STARK-TRACE-ZERO',
    '  1 0 0 STARK-TRACE!',
    '  1 0 1 STARK-TRACE!',
    '  254 0 DO',
    '    0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+',
    '    0 I 2 + STARK-TRACE!',
    '  LOOP ;',
]

STARK_INIT_LINES = [
    'STARK-INIT',
] + FIB_AIR_SETUP + [
    '_TEST-FIB-AIR STARK-SET-AIR',
] + FIB_TRACE_FILL + [
    '_fill-fib-trace',
]

# =====================================================================
#  Tests
# =====================================================================

def test_stark_init():
    """STARK-INIT runs without error"""
    check("stark-init", ['STARK-INIT', '.\" INIT-OK\" CR'], "INIT-OK")

def test_set_air():
    """STARK-SET-AIR stores AIR pointer"""
    lines = [
        'STARK-INIT',
    ] + FIB_AIR_SETUP + [
        '_TEST-FIB-AIR STARK-SET-AIR',
        '.\" AIR-OK\" CR',
    ]
    check("set-air", lines, "AIR-OK")

def test_trace_write_read():
    """STARK-TRACE!/STARK-TRACE@ roundtrip"""
    check("trace-rw", [
        'STARK-INIT',
        '42 0 7 STARK-TRACE!',
        '0 7 STARK-TRACE@ . CR',
    ], "42")

def test_trace_zero():
    """STARK-TRACE-ZERO clears trace"""
    check("trace-zero", [
        'STARK-INIT',
        '123 0 5 STARK-TRACE!',
        'STARK-TRACE-ZERO',
        '0 5 STARK-TRACE@ . CR',
    ], "0")

def test_fib_trace_fill():
    """Fibonacci trace fills correctly"""
    # fib(0)=1, fib(1)=1, fib(2)=2, fib(3)=3, fib(4)=5
    lines = STARK_INIT_LINES + [
        '0 0 STARK-TRACE@ . CR',
        '0 1 STARK-TRACE@ . CR',
        '0 2 STARK-TRACE@ . CR',
        '0 3 STARK-TRACE@ . CR',
        '0 4 STARK-TRACE@ . CR',
    ]
    def pred(out):
        nums = [l.strip() for l in out.strip().split('\n') if l.strip().isdigit()]
        return nums[-5:] == ['1', '1', '2', '3', '5']
    check_fn("fib-trace-fill", lines, pred, "expected 1 1 2 3 5")

def test_prove_runs():
    """STARK-PROVE completes without crash"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '.\" PROVE-OK\" CR',
    ]
    check("prove-runs", lines, "PROVE-OK")

def test_verify_honest():
    """Honest Fibonacci proof verifies TRUE"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("verify-honest", lines, "VERIFY-TRUE")

def test_fri_final_nonzero():
    """FRI final constant is nonzero"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        'STARK-FRI-FINAL@ . CR',
    ]
    def pred(out):
        for l in out.strip().split('\n'):
            l = l.strip()
            if l.lstrip('-').isdigit() and l != '0':
                return True
        return False
    check_fn("fri-final-nonzero", lines, pred, "final should be nonzero")

def test_tamper_trace_reject():
    """Tampering with trace after prove causes verify to fail"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '999 0 10 STARK-TRACE!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-trace-reject", lines, "VERIFY-FALSE")

def test_tamper_coeff_reject():
    """Tampering with trace coefficients causes verify to fail"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        # Corrupt a coefficient byte directly
        '0 5  0 _SK-TCOEFF-ADDR  NTT-COEFF!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-coeff-reject", lines, "VERIFY-FALSE")

def test_prove_twice_deterministic():
    """Proving twice gives same FRI final value"""
    lines = STARK_INIT_LINES + [
        'VARIABLE _T-VAL1',
        'STARK-PROVE',
        'STARK-FRI-FINAL@ _T-VAL1 !',
        '_fill-fib-trace',
        'STARK-PROVE',
        'STARK-FRI-FINAL@ _T-VAL1 @ = IF ." DETERM-OK" ELSE ." DETERM-FAIL" THEN CR',
    ]
    check("prove-deterministic", lines, "DETERM-OK")

def test_empty_trace_reject():
    """All-zero trace should fail verification"""
    lines = [
        'STARK-INIT',
    ] + FIB_AIR_SETUP + [
        '_TEST-FIB-AIR STARK-SET-AIR',
        'STARK-TRACE-ZERO',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("empty-trace-reject", lines, "VERIFY-FALSE")

def test_wrong_boundary_reject():
    """Wrong boundary values in AIR cause verify to fail"""
    lines = [
        'STARK-INIT',
        # Build AIR with wrong boundary: trace[0] should be 99
        '1 AIR-BEGIN',
        '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
        '  0 0 99 AIR-BOUNDARY',
        '  0 1 1 AIR-BOUNDARY',
        'AIR-END CONSTANT _BAD-AIR',
        '_BAD-AIR STARK-SET-AIR',
    ] + FIB_TRACE_FILL + [
        '_fill-fib-trace',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("wrong-boundary-reject", lines, "VERIFY-FALSE")

def test_fri_fold_consistency():
    """FRI final is a valid field element (nonzero)"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        'STARK-FRI-FINAL@ . CR',
    ]
    def pred(out):
        for l in out.strip().split('\n'):
            l = l.strip()
            if l.lstrip('-').isdigit() and l != '0':
                return True
        return False
    check_fn("fri-fold-consistency", lines, pred, "should be nonzero")

def test_tamper_fri_reject():
    """Tampering with FRI buffer causes verify to reject"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        # Corrupt a byte in FRI round 0
        '255 0 _SK-FRI-ROUND-ADDR C!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-fri-reject", lines, "VERIFY-FALSE")

def test_tamper_qcoeff_reject():
    """Tampering with quotient coefficients causes verify to reject"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '12345 0 _SK-QCOEFF NTT-COEFF!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-qcoeff-reject", lines, "VERIFY-FALSE")

def test_tamper_troot_reject():
    """Tampering with stored trace root causes verify to reject"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '255 _SK-TROOT C!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-troot-reject", lines, "VERIFY-FALSE")

def test_tamper_qroot_reject():
    """Tampering with stored quotient root causes verify to reject"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '255 _SK-QROOT C!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-qroot-reject", lines, "VERIFY-FALSE")

def test_tamper_fri_final_reject():
    """Tampering with FRI final value causes verify to reject"""
    lines = STARK_INIT_LINES + [
        'STARK-PROVE',
        '99999 _SK-FRI-FINAL !',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("tamper-fri-final-reject", lines, "VERIFY-FALSE")

def test_different_fib_seeds():
    """Fibonacci with seeds (2,3) proves and verifies"""
    lines = [
        'STARK-INIT',
        '1 AIR-BEGIN',
        '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
        '  0 0 2 AIR-BOUNDARY',
        '  0 1 3 AIR-BOUNDARY',
        'AIR-END CONSTANT _FIB23-AIR',
        '_FIB23-AIR STARK-SET-AIR',
        'STARK-TRACE-ZERO',
        '2 0 0 STARK-TRACE!',
        '3 0 1 STARK-TRACE!',
        ': _fill23',
        '  254 0 DO',
        '    0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+',
        '    0 I 2 + STARK-TRACE!',
        '  LOOP ;',
        '_fill23',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("fib-seeds-2-3", lines, "VERIFY-TRUE")

def test_large_fib_seeds():
    """Fibonacci with large seeds near q proves and verifies"""
    lines = [
        'STARK-INIT',
        '1 AIR-BEGIN',
        '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
        '  0 0 2013265900 AIR-BOUNDARY',
        '  0 1 2013265910 AIR-BOUNDARY',
        'AIR-END CONSTANT _FIGLG-AIR',
        '_FIGLG-AIR STARK-SET-AIR',
        'STARK-TRACE-ZERO',
        '2013265900 0 0 STARK-TRACE!',
        '2013265910 0 1 STARK-TRACE!',
        ': _filllg',
        '  254 0 DO',
        '    0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+',
        '    0 I 2 + STARK-TRACE!',
        '  LOOP ;',
        '_filllg',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("fib-large-seeds", lines, "VERIFY-TRUE")

def test_large_seeds_tamper_reject():
    """Large-seed Fibonacci with wrong boundary rejects"""
    lines = [
        'STARK-INIT',
        '1 AIR-BEGIN',
        '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
        '  0 0 2013265900 AIR-BOUNDARY',
        '  0 1 777 AIR-BOUNDARY',
        'AIR-END CONSTANT _FIGTMP-AIR',
        '_FIGTMP-AIR STARK-SET-AIR',
        'STARK-TRACE-ZERO',
        '2013265900 0 0 STARK-TRACE!',
        '2013265910 0 1 STARK-TRACE!',
        ': _filltmp',
        '  254 0 DO',
        '    0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+',
        '    0 I 2 + STARK-TRACE!',
        '  LOOP ;',
        '_filltmp',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("large-seeds-tamper-reject", lines, "VERIFY-FALSE")

def test_omega_is_primitive():
    """omega^256 == 1 and omega^128 != 1"""
    lines = [
        'STARK-INIT',
        '_SK-OMEGA @ 256 BB-POW . CR',
        '_SK-OMEGA @ 128 BB-POW 1 <> IF .\" PRIM-OK\" ELSE .\" PRIM-FAIL\" THEN CR',
    ]
    def pred(out):
        return '1' in out and 'PRIM-OK' in out
    check_fn("omega-primitive", lines, pred, "omega^256=1, omega^128!=1")

def test_k256_not_one():
    """k^256 != 1 (coset is disjoint from trace domain)"""
    lines = [
        'STARK-INIT',
        '_SK-K256 @ 1 <> IF .\" K-OK\" ELSE .\" K-FAIL\" THEN CR',
    ]
    check("k256-not-one", lines, "K-OK")

def test_zinv_correct():
    """zinv * (k^256 - 1) == 1"""
    lines = [
        'STARK-INIT',
        '_SK-ZINV @ _SK-K256 @ 1 BB- BB* . CR',
    ]
    check("zinv-correct", lines, "1")

def test_coset_eval_roundtrip():
    """Coset-eval then coset-inv recovers original coefficients"""
    lines = STARK_INIT_LINES + [
        'VARIABLE _T-SAVED',
        # Interpolate trace to coefficients
        '0 _SK-TRACE-ADDR 0 _SK-TCOEFF-ADDR NTT-POLY-COPY',
        '0 _SK-TCOEFF-ADDR NTT-INVERSE',
        # Save coeff[5] before roundtrip
        '5 0 _SK-TCOEFF-ADDR NTT-COEFF@ _T-SAVED !',
        # Roundtrip: coset eval then inv
        '0 _SK-TCOEFF-ADDR _SK-TMP1 _SK-COSET-EVAL',
        '_SK-TMP1 _SK-COSET-INV',
        # Compare coeff[5]
        '5 _SK-TMP1 NTT-COEFF@ _T-SAVED @ = IF ." RT-OK" ELSE ." RT-FAIL" THEN CR',
    ]
    check("coset-roundtrip", lines, "RT-OK")

def test_merkle_trace_root_stable():
    """Merkle trace root is deterministic across two commits"""
    lines = STARK_INIT_LINES + [
        '0 _SK-TRACE-ADDR 0 _SK-TCOEFF-ADDR NTT-POLY-COPY',
        '0 _SK-TCOEFF-ADDR NTT-INVERSE',
        '0 _SK-TCOEFF-ADDR 0 _SK-MTREE-ADDR _SK-MERKLE-COMMIT',
        'CREATE _r1 32 ALLOT',
        '0 _SK-MTREE-ADDR MERKLE-ROOT _r1 32 CMOVE',
        # Recommit
        '0 _SK-TCOEFF-ADDR 0 _SK-MTREE-ADDR _SK-MERKLE-COMMIT',
        '0 _SK-MTREE-ADDR MERKLE-ROOT _r1 SHA3-256-COMPARE',
        'IF .\" ROOT-STABLE\" ELSE .\" ROOT-CHANGED\" THEN CR',
    ]
    check("merkle-root-stable", lines, "ROOT-STABLE")

def test_transition_constraint_row0():
    """AIR-EVAL-TRANS returns 0 on honest Fibonacci trace row 0"""
    lines = STARK_INIT_LINES + [
        # Set up ceval from raw trace (not coset)
        '0 _SK-TRACE-ADDR 0 _SK-CEVAL-ADDR 1024 CMOVE',
        '0 _SK-CEVAL-ADDR DUP 1024 + 16 CMOVE',
        '0 _SK-CEVAL-ADDR _SK-COLS !',
        '_TEST-FIB-AIR _SK-COLS 0 AIR-EVAL-TRANS . CR',
    ]
    check("trans-row0-zero", lines, "0")

def test_transition_constraint_row100():
    """AIR-EVAL-TRANS returns 0 on honest trace row 100"""
    lines = STARK_INIT_LINES + [
        '0 _SK-TRACE-ADDR 0 _SK-CEVAL-ADDR 1024 CMOVE',
        '0 _SK-CEVAL-ADDR DUP 1024 + 16 CMOVE',
        '0 _SK-CEVAL-ADDR _SK-COLS !',
        '_TEST-FIB-AIR _SK-COLS 100 AIR-EVAL-TRANS . CR',
    ]
    check("trans-row100-zero", lines, "0")

def test_boundary_check_honest():
    """AIR-CHECK-BOUND returns TRUE on honest trace"""
    lines = STARK_INIT_LINES + [
        '0 _SK-TRACE-ADDR 0 _SK-CEVAL-ADDR 1024 CMOVE',
        '0 _SK-CEVAL-ADDR _SK-COLS !',
        '_TEST-FIB-AIR _SK-COLS AIR-CHECK-BOUND',
        'IF .\" BOUND-OK\" ELSE .\" BOUND-FAIL\" THEN CR',
    ]
    check("boundary-honest", lines, "BOUND-OK")

def test_fiat_shamir_deterministic():
    """Same trace root produces same alpha/beta challenges"""
    lines = STARK_INIT_LINES + [
        'VARIABLE _T-A1  VARIABLE _T-B1',
        'STARK-PROVE',
        '_SK-BCHAL @ _T-A1 !  _SK-BCHAL 8 + @ _T-B1 !',
        '_fill-fib-trace STARK-PROVE',
        '_SK-BCHAL @ _T-A1 @ =  _SK-BCHAL 8 + @ _T-B1 @ =  AND',
        'IF .\" FS-DET\" ELSE .\" FS-DIFF\" THEN CR',
    ]
    check("fiat-shamir-det", lines, "FS-DET")

def test_verify_idempotent():
    """Calling STARK-VERIFY twice gives same result"""
    lines = STARK_INIT_LINES + [
        'VARIABLE _T-V1',
        'STARK-PROVE',
        'STARK-VERIFY _T-V1 !',
        'STARK-VERIFY _T-V1 @ =',
        'IF .\" IDEMP-OK\" ELSE .\" IDEMP-FAIL\" THEN CR',
    ]
    check("verify-idempotent", lines, "IDEMP-OK")

# =====================================================================
#  Multi-column tests (Phase 4.5)
# =====================================================================

def test_set_cols():
    """STARK-SET-COLS stores column count"""
    check("set-cols", [
        'STARK-INIT',
        '3 STARK-SET-COLS',
        '_SK-NCOLS @ . CR',
    ], "3")

def test_set_cols_clamp_low():
    """STARK-SET-COLS clamps 0 to 1"""
    check("set-cols-clamp-lo", [
        'STARK-INIT',
        '0 STARK-SET-COLS',
        '_SK-NCOLS @ . CR',
    ], "1")

def test_set_cols_clamp_high():
    """STARK-SET-COLS clamps 99 to 8"""
    check("set-cols-clamp-hi", [
        'STARK-INIT',
        '99 STARK-SET-COLS',
        '_SK-NCOLS @ . CR',
    ], "8")

def test_multicol_trace_rw():
    """Write/read from different columns"""
    lines = [
        'STARK-INIT',
        '2 STARK-SET-COLS',
        '42 0 5 STARK-TRACE!',
        '99 1 5 STARK-TRACE!',
        '0 5 STARK-TRACE@ . CR',
        '1 5 STARK-TRACE@ . CR',
    ]
    def pred(out):
        nums = [l.strip() for l in out.strip().split('\n') if l.strip().isdigit()]
        return '42' in nums and '99' in nums
    check_fn("multicol-trace-rw", lines, pred, "expected 42 and 99")

def test_multicol_trace_zero():
    """STARK-TRACE-ZERO clears all active columns"""
    lines = [
        'STARK-INIT',
        '2 STARK-SET-COLS',
        '42 0 5 STARK-TRACE!',
        '99 1 5 STARK-TRACE!',
        'STARK-TRACE-ZERO',
        '0 5 STARK-TRACE@ . CR',
        '1 5 STARK-TRACE@ . CR',
    ]
    def pred(out):
        nums = [l.strip() for l in out.strip().split('\n') if l.strip() == '0']
        return len(nums) >= 2
    check_fn("multicol-trace-zero", lines, pred, "both cols should be 0")

TWO_COL_AIR_SETUP = [
    '2 AIR-BEGIN',
    # col0: Fibonacci  col0[i] + col0[i+1] = col0[i+2]
    '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
    # col1: running sum  col1[i] + col0[i] = col1[i+1]
    '  AIR-ADD 1 0  0 0  1 1  AIR-TRANS',
    # Boundaries: col0[0]=1, col0[1]=1, col1[0]=0
    '  0 0 1 AIR-BOUNDARY',
    '  0 1 1 AIR-BOUNDARY',
    '  1 0 0 AIR-BOUNDARY',
    'AIR-END CONSTANT _2COL-AIR',
]

TWO_COL_TRACE_FILL = [
    ': _fill-2col',
    '  STARK-TRACE-ZERO',
    # Col 0: Fibonacci
    '  1 0 0 STARK-TRACE!',
    '  1 0 1 STARK-TRACE!',
    '  254 0 DO',
    '    0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+',
    '    0 I 2 + STARK-TRACE!',
    '  LOOP',
    # Col 1: running sum  col1[i+1] = col1[i] + col0[i]
    '  0 1 0 STARK-TRACE!',
    '  255 0 DO',
    '    1 I STARK-TRACE@ 0 I STARK-TRACE@ BB+',
    '    1 I 1 + STARK-TRACE!',
    '  LOOP ;',
]

TWO_COL_INIT = [
    'STARK-INIT',
    '2 STARK-SET-COLS',
] + TWO_COL_AIR_SETUP + [
    '_2COL-AIR STARK-SET-AIR',
] + TWO_COL_TRACE_FILL + [
    '_fill-2col',
]

def test_2col_prove_verify():
    """2-column Fibonacci+RunningSum proves and verifies"""
    lines = TWO_COL_INIT + [
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("2col-prove-verify", lines, "VERIFY-TRUE")

def test_2col_tamper_col0_reject():
    """Tampering col0 after prove → reject"""
    lines = TWO_COL_INIT + [
        'STARK-PROVE',
        '999 0 10 STARK-TRACE!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("2col-tamper-col0", lines, "VERIFY-FALSE")

def test_2col_tamper_col1_reject():
    """Tampering col1 after prove → reject"""
    lines = TWO_COL_INIT + [
        'STARK-PROVE',
        '999 1 10 STARK-TRACE!',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("2col-tamper-col1", lines, "VERIFY-FALSE")

def test_2col_wrong_col1_boundary():
    """Wrong boundary on col1 → reject"""
    lines = [
        'STARK-INIT',
        '2 STARK-SET-COLS',
        '2 AIR-BEGIN',
        '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
        '  AIR-ADD 1 0  0 0  1 1  AIR-TRANS',
        '  0 0 1 AIR-BOUNDARY',
        '  0 1 1 AIR-BOUNDARY',
        '  1 0 999 AIR-BOUNDARY',     # wrong: col1[0] should be 0
        'AIR-END CONSTANT _2COL-BAD',
        '_2COL-BAD STARK-SET-AIR',
    ] + TWO_COL_TRACE_FILL + [
        '_fill-2col',
        'STARK-PROVE',
        'STARK-VERIFY',
        'IF .\" VERIFY-TRUE\" ELSE .\" VERIFY-FALSE\" THEN CR',
    ]
    check("2col-wrong-bound", lines, "VERIFY-FALSE")

def test_2col_deterministic():
    """2-column proof is deterministic"""
    lines = TWO_COL_INIT + [
        'VARIABLE _T-V2COL',
        'STARK-PROVE',
        'STARK-FRI-FINAL@ _T-V2COL !',
        '_fill-2col',
        'STARK-PROVE',
        'STARK-FRI-FINAL@ _T-V2COL @ = IF .\" DET-OK\" ELSE .\" DET-FAIL\" THEN CR',
    ]
    check("2col-deterministic", lines, "DET-OK")

# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    tests = [
        test_stark_init,
        test_set_air,
        test_trace_write_read,
        test_trace_zero,
        test_fib_trace_fill,
        test_prove_runs,
        test_verify_honest,
        test_fri_final_nonzero,
        test_tamper_trace_reject,
        test_tamper_coeff_reject,
        test_prove_twice_deterministic,
        test_empty_trace_reject,
        test_wrong_boundary_reject,
        test_fri_fold_consistency,
        # Tamper rejection suite
        test_tamper_fri_reject,
        test_tamper_qcoeff_reject,
        test_tamper_troot_reject,
        test_tamper_qroot_reject,
        test_tamper_fri_final_reject,
        # Different seed / domain tests
        test_different_fib_seeds,
        test_large_fib_seeds,
        test_large_seeds_tamper_reject,
        # Domain parameter validation
        test_omega_is_primitive,
        test_k256_not_one,
        test_zinv_correct,
        # Internal machinery
        test_coset_eval_roundtrip,
        test_merkle_trace_root_stable,
        test_transition_constraint_row0,
        test_transition_constraint_row100,
        test_boundary_check_honest,
        test_fiat_shamir_deterministic,
        test_verify_idempotent,
        # Multi-column (Phase 4.5)
        test_set_cols,
        test_set_cols_clamp_low,
        test_set_cols_clamp_high,
        test_multicol_trace_rw,
        test_multicol_trace_zero,
        test_2col_prove_verify,
        test_2col_tamper_col0_reject,
        test_2col_tamper_col1_reject,
        test_2col_wrong_col1_boundary,
        test_2col_deterministic,
    ]

    print(f"\nRunning {len(tests)} tests...\n")
    for t in tests:
        t()

    total = _pass_count + _fail_count
    print(f"\n{_pass_count}/{total} passed", end="")
    if _fail_count:
        print(f", {_fail_count} FAILED")
    else:
        print(", All tests passed!")
    sys.exit(1 if _fail_count else 0)
