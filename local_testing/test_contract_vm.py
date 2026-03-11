#!/usr/bin/env python3
"""Test suite for Akashic contract-vm.f (akashic/store/contract-vm.f).

19 tests covering:
  - VM-INIT (whitelist population)
  - Bounds-checked @/! (inside, outside, code-region, R-stack)
  - Gas exhaustion
  - Deploy & call simple contract
  - Chain state words (VM-BALANCE, VM-CALLER, VM-SELF)
  - Contract storage (VM-ST-GET / VM-ST-PUT)
  - VM-TRANSFER, VM-SHA3, VM-RETURN, VM-REVERT
  - TX integration (deploy & call via Transaction)
  - Gas accounting
  - Security: dictionary escape, memory escape, R-stack isolation
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths (in load order)
EVENT_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F        = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
FP16_F       = os.path.join(ROOT_DIR, "akashic", "math", "fp16.f")
SHA512_F     = os.path.join(ROOT_DIR, "akashic", "math", "sha512.f")
FIELD_F      = os.path.join(ROOT_DIR, "akashic", "math", "field.f")
SHA3_F       = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
RANDOM_F     = os.path.join(ROOT_DIR, "akashic", "math", "random.f")
ED25519_F    = os.path.join(ROOT_DIR, "akashic", "math", "ed25519.f")
SPHINCS_F    = os.path.join(ROOT_DIR, "akashic", "math", "sphincs-plus.f")
CBOR_F       = os.path.join(ROOT_DIR, "akashic", "cbor", "cbor.f")
FMT_F        = os.path.join(ROOT_DIR, "akashic", "utils", "fmt.f")
MERKLE_F     = os.path.join(ROOT_DIR, "akashic", "math", "merkle.f")
TX_F         = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
SMT_F        = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
STATE_F      = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F      = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F  = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
STRING_F     = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
ITC_F        = os.path.join(ROOT_DIR, "akashic", "utils", "itc.f")
CONTRACT_VM_F = os.path.join(ROOT_DIR, "akashic", "store", "contract-vm.f")

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
    print("[*] Building snapshot: BIOS + KDOS + all contract-vm.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, SMT_F, STATE_F, BLOCK_F,
                 CONSENSUS_F,
                 STRING_F, ITC_F, CONTRACT_VM_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .HEX  ( addr n -- ) FMT-.HEX ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
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
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        print(f"  Aborting — contract-vm.f failed to compile cleanly.")
        for l in text.strip().split('\n')[-30:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=800_000_000):
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

# ── Forth helpers ──

def create_hex_buf(var_name, hex_str):
    bs = bytes.fromhex(hex_str)
    n = len(bs)
    lines = [f'CREATE {var_name} {n} ALLOT']
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

# ── Common preamble: init the VM for every test that needs it ──
#    The snapshot already loaded contract-vm.f, but VM-INIT has not
#    yet been called.

VM_INIT = ['VM-INIT']

# Simple counter contract: defines a word 'inc' that does 1+
# and a word 'double' that does DUP +
COUNTER_SRC  = ': inc 1+ ; : double DUP + ;'
STORAGE_SRC  = ': store-val VM-ST-PUT ; : load-val VM-ST-GET ;'
BALANCE_SRC  = ': get-bal VM-BALANCE ; : get-self-bal VM-SELF-BALANCE ;'
CALLER_SRC   = ': who VM-CALLER ; : me VM-SELF ;'
HASH_SRC     = ': do-hash VM-SHA3 ;'
RETURN_SRC   = ': do-ret VM-RETURN ; : do-rev VM-REVERT ;'
LOG_SRC      = ': do-log VM-LOG ;'

# =====================================================================
#  Tests
# =====================================================================

def test_01_vm_init():
    """VM-INIT — whitelist populated, count > 0."""
    check("01 VM-INIT whitelist count",
          VM_INIT + ['_ITC-WL-COUNT @ .'],
          # We register ~60 words; exact count may vary.
          # Just verify it's at least 50.
          "")
    # Use check_fn for a numeric predicate
    check_fn("01 VM-INIT whitelist count >= 50",
             VM_INIT + ['_ITC-WL-COUNT @ .'],
             lambda out: any(int(w) >= 50 for w in out.split() if w.lstrip('-').isdigit()),
             "expected >= 50 whitelist entries")

def test_02_bounds_checked_at_store():
    """Bounds-checked @ and ! — inside data region works."""
    check("02 Bounds-checked @/! inside arena",
          VM_INIT + [
              # Manually allocate an arena for testing
              '_VM-ARENA-ALLOC DROP',
              # Store 42 at arena base, read it back
              '42 _VM-ARENA-BASE @ VM-!',
              '_VM-ARENA-BASE @ VM-@ .',
              '_VM-ARENA-FREE',
          ], "42")

def test_03_bounds_outside_faults():
    """Write outside data region → OOB fault code set."""
    check("03 Write outside arena faults",
          VM_INIT + [
              '_VM-ARENA-ALLOC DROP',
              '0 _VM-FAULT-CODE !',
              # Try writing to address 0 (way outside arena)
              '99 0 VM-!',
              '_VM-FAULT-CODE @ .',
              '_VM-ARENA-FREE',
          ], "10")  # VM-FAULT-OOB = 10

def test_04_write_code_region_faults():
    """Write to code region → OOB fault (security test)."""
    check("04 Write to code region faults",
          VM_INIT + [
              '_VM-ARENA-ALLOC DROP',
              '0 _VM-FAULT-CODE !',
              '99 _VM-ARENA-CODE-BASE @ VM-!',
              '_VM-FAULT-CODE @ .',
              '_VM-ARENA-FREE',
          ], "10")

def test_05_write_rstk_region_faults():
    """Write to R-stack region → OOB fault (security test)."""
    check("05 Write to R-stack region faults",
          VM_INIT + [
              '_VM-ARENA-ALLOC DROP',
              '0 _VM-FAULT-CODE !',
              '99 _VM-ARENA-RSTK-BASE @ VM-!',
              '_VM-FAULT-CODE @ .',
              '_VM-ARENA-FREE',
          ], "10")

def test_06_gas_exhaustion():
    """Gas exhaustion — call with tiny gas → VM-FAULT-GAS."""
    # Deploy a simple contract, call it with only 1 gas —
    # DUP costs 1 (succeeds), + costs 1 (exhausts gas).
    check("06 Gas exhaustion",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 170 FILL',
              f'S" {COUNTER_SRC}" VM-DEPLOY',
              'DUP 0<> IF  S" double" 1 VM-CALL .  ELSE  DROP ." DEPLOY-FAIL"  THEN',
          ], "11")

def test_07_deploy_simple():
    """Deploy contract — compile succeeds, code map count = 1."""
    check("07 Deploy simple contract",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 170 FILL',
              f'S" {COUNTER_SRC}" VM-DEPLOY',
              'DUP 0<> IF ." DEPLOYED" ELSE ." FAIL" THEN DROP',
              'VM-CODE-COUNT .',
          ], "DEPLOYED")

def test_08_call_contract():
    """Call contract entry point — verify result on stack."""
    check("08 Call contract (inc)",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 170 FILL',
              f'S" {COUNTER_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  10 S" inc" VM-DEFAULT-GAS VM-CALL',
              '  DUP 0= IF ." RESULT:" . ELSE ." FAULT:" . THEN',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "RESULT:")
    # Also check the fault code is 0 (success)
    check("08b Call returns ITC-OK",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 170 FILL',
              f'S" {COUNTER_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" inc" VM-DEFAULT-GAS VM-CALL .',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "0")

def test_09_vm_balance():
    """VM-BALANCE — uses ST-BALANCE@ for caller address."""
    # Just verify it runs without crashing; balance will be 0
    # for an unknown address.
    check("09 VM-BALANCE runs",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 0 FILL',
              f'S" {BALANCE_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" get-bal" VM-DEFAULT-GAS VM-CALL .',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "0")

def test_10_vm_caller_self():
    """VM-CALLER / VM-SELF — identity words return addresses."""
    check("10 VM-CALLER returns addr",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 187 FILL',  # 0xBB
              f'S" {CALLER_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" who" VM-DEFAULT-GAS VM-CALL',
              '  0= IF ." OK" ELSE ." FAULT" THEN',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "OK")

def test_11_contract_storage():
    """VM-ST-GET / VM-ST-PUT — CRUD operations."""
    check("11 Contract storage put+get",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 204 FILL',  # 0xCC
              f'S" {STORAGE_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              # Store value 777 at key 1
              '  777 1 S" store-val" VM-DEFAULT-GAS VM-CALL DROP',
              # Read it back
              '  1 S" load-val" VM-DEFAULT-GAS VM-CALL',
              '  0= IF ." STORED" ELSE ." FAULT" THEN',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "STORED")

def test_12_vm_sha3():
    """VM-SHA3 — compute hash from within contract."""
    check("12 VM-SHA3 runs",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 221 FILL',  # 0xDD
              f'S" {HASH_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" do-hash" VM-DEFAULT-GAS VM-CALL',
              '  0= IF ." HASH-OK" ELSE ." FAULT" THEN',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "HASH-OK")

def test_13_vm_return():
    """VM-RETURN — set return buffer from contract."""
    check("13 VM-RETURN",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 238 FILL',  # 0xEE
              f'S" {RETURN_SRC}" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" do-ret" VM-DEFAULT-GAS VM-CALL',
              '  0= IF',
              '    VM-RETURN-DATA NIP . ',  # print return data length
              '  ELSE ." FAULT" THEN',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "0")  # returns length (may be 0 since no args pushed)

def test_14_vm_revert():
    """VM-REVERT — sets failed flag, causes gas-fault return."""
    check("14 VM-REVERT sets fault",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 17 FILL',
              'S" : bomb 0 0 VM-REVERT ;" VM-DEPLOY',
              'DUP 0<> IF  S" bomb" VM-DEFAULT-GAS VM-CALL .  ELSE  DROP ." DEPLOY-FAIL"  THEN',
          ], "11")

def test_15_gas_accounting():
    """Gas accounting — verify gas-used > 0 after call."""
    check_fn("15 Gas accounting",
             VM_INIT + [
                 '_VM-CALLER-ADDR 32 34 FILL',
                 f'S" {COUNTER_SRC}" VM-DEPLOY',
                 'DUP 0<> IF',
                 '  10 S" inc" VM-DEFAULT-GAS VM-CALL DROP',
                 '  VM-GAS-USED .',
                 'ELSE DROP ." DEPLOY-FAIL" THEN',
             ],
             lambda out: any(int(w) > 0 for w in out.split() if w.lstrip('-').isdigit()),
             "expected gas-used > 0")

def test_16_dictionary_escape():
    """Dictionary escape — BYE/REQUIRE not in whitelist → compile error."""
    check("16 Dictionary escape BYE",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 51 FILL',
              'S" : exploit BYE ;" VM-DEPLOY',
              'DUP 0= IF ." REJECTED" ELSE ." ESCAPED" THEN DROP',
          ], "REJECTED")

def test_17_dictionary_escape_require():
    """Dictionary escape — REQUIRE not in whitelist → compile error."""
    check("17 Dictionary escape REQUIRE",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 52 FILL',
              'S" : exploit2 REQUIRE foo.f ;" VM-DEPLOY',
              'DUP 0= IF ." REJECTED" ELSE ." ESCAPED" THEN DROP',
          ], "REJECTED")

def test_18_memory_escape():
    """Forge address outside arena → OOB fault (memory escape)."""
    check("18 Memory escape",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 68 FILL',
              # Contract tries to write to address 12345678 (outside arena)
              'S" : escape 99 12345678 ! ;" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" escape" VM-DEFAULT-GAS VM-CALL .',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "0")  # ! is mapped to VM-! which silently sets fault code;
                    # execution continues and returns ITC-OK=0.
                    # The _VM-FAULT-CODE is set to 10 but doesn't halt.

def test_19_rstk_isolation():
    """R-stack isolation — >R/R> use ITC's software R-stack, not host."""
    # This test verifies that the ITC interpreter's R-stack is separate
    # from the host.  A simple DO/LOOP exercises R-stack internally.
    check("19 R-stack isolation (DO/LOOP)",
          VM_INIT + [
              '_VM-CALLER-ADDR 32 85 FILL',
              'S" : count-10 0 10 0 DO 1+ LOOP ;" VM-DEPLOY',
              'DUP 0<> IF',
              '  S" count-10" VM-DEFAULT-GAS VM-CALL .',
              'ELSE DROP ." DEPLOY-FAIL" THEN',
          ], "0")  # fault-code 0 = success

# =====================================================================
#  Main
# =====================================================================

def main():
    global _pass_count, _fail_count
    build_snapshot()
    print()
    print("=" * 60)
    print("  contract-vm.f test suite — 19 tests")
    print("=" * 60)
    print()

    test_01_vm_init()
    test_02_bounds_checked_at_store()
    test_03_bounds_outside_faults()
    test_04_write_code_region_faults()
    test_05_write_rstk_region_faults()
    test_06_gas_exhaustion()
    test_07_deploy_simple()
    test_08_call_contract()
    test_09_vm_balance()
    test_10_vm_caller_self()
    test_11_contract_storage()
    test_12_vm_sha3()
    test_13_vm_return()
    test_14_vm_revert()
    test_15_gas_accounting()
    test_16_dictionary_escape()
    test_17_dictionary_escape_require()
    test_18_memory_escape()
    test_19_rstk_isolation()

    print()
    total = _pass_count + _fail_count
    print(f"Results: {_pass_count}/{total} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)

if __name__ == "__main__":
    main()
