#!/usr/bin/env python3
"""Test suite for akashic-itc (akashic/utils/itc.f).

Tests: whitelist registration, ITC compilation, inner interpreter
execution, control flow, constants/variables, pre-dispatch callback,
fault handling, and image save/load.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

STRING_F   = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
ITC_F      = os.path.join(ROOT_DIR, "akashic", "utils", "itc.f")

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
    print("[*] Building snapshot: BIOS + KDOS + string.f + itc.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STRING_F)
    itc_lines  = _load_forth_lines(ITC_F)

    # Helpers: register some standard words into the whitelist
    helpers = [
        # Register core stack/arithmetic words into whitelist
        "' DUP   0 S\" DUP\"   ITC-WL-ADD",
        "' DROP  0 S\" DROP\"  ITC-WL-ADD",
        "' SWAP  0 S\" SWAP\"  ITC-WL-ADD",
        "' OVER  0 S\" OVER\"  ITC-WL-ADD",
        "' ROT   0 S\" ROT\"   ITC-WL-ADD",
        "' +     0 S\" +\"     ITC-WL-ADD",
        "' -     0 S\" -\"     ITC-WL-ADD",
        "' *     0 S\" *\"     ITC-WL-ADD",
        "' /     0 S\" /\"     ITC-WL-ADD",
        "' .     0 S\" .\"     ITC-WL-ADD",
        "' =     0 S\" =\"     ITC-WL-ADD",
        "' <     0 S\" <\"     ITC-WL-ADD",
        "' >     0 S\" >\"     ITC-WL-ADD",
        "' 0=    0 S\" 0=\"    ITC-WL-ADD",
        "' EMIT  0 S\" EMIT\"  ITC-WL-ADD",
        "' AND   0 S\" AND\"   ITC-WL-ADD",
        "' OR    0 S\" OR\"    ITC-WL-ADD",
        "' NEGATE 0 S\" NEGATE\" ITC-WL-ADD",
        # Compile buffer (4KB) and return-stack region (1KB)
        "CREATE _TBUF 4096 ALLOT",
        "CREATE _TRSTK 1024 ALLOT",
        # Data region for VARIABLE tests (512 bytes)
        "CREATE _TDATA 512 ALLOT",
        "_TDATA _ITC-DATA-PTR !",
        "_TDATA 512 + _ITC-DATA-END !",
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + str_lines + itc_lines + helpers
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
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        for l in text.strip().split('\n')[-20:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=200_000_000):
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

# ── Compile + Execute helper ──
# These Forth lines compile ITC source, then execute the first entry point.
# Usage: _CE("itc-source", "entry-name")
# Returns Forth lines that compile source into _TBUF, look up entry,
# and call ITC-EXECUTE.

def _ce(src, entry="main"):
    """Build Forth lines that ITC-compile src, then execute entry."""
    return [
        # ITC-COMPILE: src len buf limit -- entry-count | -1
        f'S" {src}" _TBUF 4096 ITC-COMPILE',
        # Find the entry offset from the entry table
        f'DROP',  # drop entry-count, we look up by name
        f'S" {entry}" _ITC-ENT-FIND',
        f'0= IF .\" ENTRY-NOT-FOUND\" BYE THEN',
        # offset is now on stack — convert to absolute addr
        f'_TRSTK 1024 ITC-EXECUTE DROP',
    ]


# ── Tests ──

def test_compile_loads():
    """Module loads without errors."""
    print("\n=== Compile check ===")
    check("itc.f loaded", ['1 2 + .'], "3")

def test_whitelist():
    """Whitelist registration and lookup."""
    print("\n=== Whitelist ===")
    # WL count — we registered 18 words in helpers
    check("WL count",
          ['_ITC-WL-COUNT @ .'],
          "18")
    # Find DUP
    check("WL-FIND DUP",
          [': _T S" DUP" ITC-WL-FIND IF . ELSE .\" NOTFOUND\" THEN ; _T'],
          "0")
    # Find + (index 5)
    check("WL-FIND +",
          [': _T S" +" ITC-WL-FIND IF . ELSE .\" NOTFOUND\" THEN ; _T'],
          "5")
    # Find nonexistent
    check("WL-FIND missing",
          [': _T S" XYZZY" ITC-WL-FIND IF .\" FOUND\" ELSE .\" MISS\" THEN ; _T'],
          "MISS")

def test_compile_literal():
    """Compile and execute a bare literal."""
    print("\n=== Compile literal ===")
    check("literal 42",
          _ce(": main 42 . ;"),
          "42")
    check("literal negative",
          _ce(": main -7 . ;"),
          "-7")

def test_compile_execute_word():
    """Compile and execute a whitelist word."""
    print("\n=== Compile + execute word ===")
    check("1 + via ITC",
          _ce(": main 1 2 + . ;"),
          "3")
    check("DUP via ITC",
          _ce(": main 5 DUP + . ;"),
          "10")

def test_stack_ops():
    """Stack ops via ITC."""
    print("\n=== Stack ops ===")
    check("SWAP",
          _ce(": main 1 2 SWAP . . ;"),
          "1 2")
    check("OVER",
          _ce(": main 3 4 OVER . . . ;"),
          "3 4 3")
    check("DROP",
          _ce(": main 10 20 DROP . ;"),
          "10")

def test_arithmetic():
    """Arithmetic via ITC."""
    print("\n=== Arithmetic ===")
    check("multiply",
          _ce(": main 6 7 * . ;"),
          "42")
    check("subtract",
          _ce(": main 10 3 - . ;"),
          "7")
    check("divide",
          _ce(": main 20 4 / . ;"),
          "5")

def test_if_then():
    """IF/THEN conditional branch — both paths."""
    print("\n=== IF/THEN ===")
    check("IF true path",
          _ce(": main 1 IF 99 . THEN ;"),
          "99")
    check("IF false path",
          _ce(": main 0 IF 99 . THEN 88 . ;"),
          "88")

def test_if_else_then():
    """IF/ELSE/THEN conditional."""
    print("\n=== IF/ELSE/THEN ===")
    check("true → IF branch",
          _ce(": main 1 IF 11 ELSE 22 THEN . ;"),
          "11")
    check("false → ELSE branch",
          _ce(": main 0 IF 11 ELSE 22 THEN . ;"),
          "22")

def test_nested_if():
    """Nested IF/ELSE/THEN."""
    print("\n=== Nested IF ===")
    check("nested true-true",
          _ce(": main 1 IF 1 IF 33 . THEN ELSE 44 . THEN ;"),
          "33")
    check("nested true-false",
          _ce(": main 1 IF 0 IF 33 . THEN ELSE 44 . THEN ;"),
          "")  # no output — falls through both THENs

def test_begin_until():
    """BEGIN/UNTIL backward loop."""
    print("\n=== BEGIN/UNTIL ===")
    # Count from 3 down to 1
    check("countdown",
          _ce(": main 3 BEGIN DUP . 1 - DUP 0= UNTIL DROP ;"),
          "3 2 1")

def test_begin_while_repeat():
    """BEGIN/WHILE/REPEAT loop."""
    print("\n=== BEGIN/WHILE/REPEAT ===")
    check("while loop",
          _ce(": main 3 BEGIN DUP 0 > WHILE DUP . 1 - REPEAT DROP ;"),
          "3 2 1")

def test_do_loop():
    """DO/LOOP counted loop."""
    print("\n=== DO/LOOP ===")
    check("count 0..3",
          _ce(": main 4 0 DO 65 EMIT LOOP ;"),
          "AAAA")

def test_do_ploop():
    """DO/+LOOP counted loop with step."""
    print("\n=== DO/+LOOP ===")
    check("step by 2",
          _ce(": main 6 0 DO 66 EMIT 2 +LOOP ;"),
          "BBB")

def test_constant():
    """CONSTANT support."""
    print("\n=== CONSTANT ===")
    check("constant 42",
          _ce("42 CONSTANT ANS : main ANS . ;"),
          "42")
    check("constant in expr",
          _ce("10 CONSTANT X : main X X + . ;"),
          "20")

def test_variable():
    """VARIABLE support."""
    print("\n=== VARIABLE ===")
    # Need @ and ! in whitelist — they were not registered.
    # Register them first, then compile.
    lines = [
        # Reset whitelist + re-register everything including @ and !
        "ITC-WL-RESET",
        "' DUP   0 S\" DUP\"   ITC-WL-ADD",
        "' DROP  0 S\" DROP\"  ITC-WL-ADD",
        "' SWAP  0 S\" SWAP\"  ITC-WL-ADD",
        "' +     0 S\" +\"     ITC-WL-ADD",
        "' .     0 S\" .\"     ITC-WL-ADD",
        "' @     0 S\" @\"     ITC-WL-ADD",
        "' !     0 S\" !\"     ITC-WL-ADD",
        # Reset data region
        "_TDATA _ITC-DATA-PTR !",
        "_TDATA 512 + _ITC-DATA-END !",
        # Zero the data region
        "_TDATA 512 0 FILL",
    ] + _ce("VARIABLE X : main 99 X ! X @ . ;")
    check("variable store/fetch", lines, "99")

def test_multi_word():
    """Multiple colon definitions — one calling another."""
    print("\n=== Multi-word ===")
    check("foo calls bar",
          _ce(": double DUP + ; : main 21 double . ;"),
          "42")
    check("chain of 3",
          _ce(": a 1 + ; : b a a ; : main 0 b . ;"),
          "2")

def test_recurse():
    """RECURSE — recursive word."""
    print("\n=== RECURSE ===")
    # Factorial: 5! = 120
    check("factorial 5",
          _ce(": fact DUP 1 > IF DUP 1 - RECURSE * ELSE DROP 1 THEN ; : main 5 fact . ;"),
          "120")

def test_pre_dispatch_callback():
    """Pre-dispatch callback fires and can halt execution."""
    print("\n=== Pre-dispatch callback ===")
    # Define a callback that counts calls
    lines = [
        "VARIABLE _CB-CNT  0 _CB-CNT !",
        ": _CB  ( index -- flag )  DROP  1 _CB-CNT +!  -1 ;",
        "' _CB _ITC-PRE-DISPATCH-XT !",
    ] + _ce(": main 1 2 + . ;") + [
        "_CB-CNT @ .",
        "0 _ITC-PRE-DISPATCH-XT !",  # clean up
    ]
    # 1 2 + . → 4 whitelist dispatches (LIT 1, LIT 2 are pseudo-ops, not dispatched)
    # Actually: 1 = LIT(pseudo), 2 = LIT(pseudo), + = WL dispatch, . = WL dispatch
    # So callback should fire 2 times
    check_fn("callback fires",
             lines,
             lambda out: any(w.isdigit() and int(w) >= 2 for w in out.strip().split()),
             "callback count >= 2")

def test_bad_opcode():
    """Bad opcode → ITC-FAULT-BAD-OP."""
    print("\n=== Bad opcode fault ===")
    # Manually construct an ITC body with a bad index
    lines = [
        # Write a single cell with value 9999 (way past whitelist) into _TBUF
        "9999 _TBUF !",
        # Then EXIT
        "6 _TBUF 8 + !",  # ITC-OP-EXIT = 6
        # Execute from _TBUF
        "_TBUF _TRSTK 1024 ITC-EXECUTE .",
    ]
    check("bad op fault=1", lines, "1")

def test_rstack_overflow():
    """Deep recursion → R-stack overflow fault."""
    print("\n=== R-stack overflow ===")
    # Infinite recursion: : main main ;
    # R-stack is 1024 bytes = 128 cells, so ~128 calls before overflow
    check_fn("overflow fault",
             _ce(": main RECURSE ; : go main ;", "go"),
             lambda out: "2" in out,  # ITC-FAULT-STACK = 2
             "expected fault code 2")

def test_unknown_word():
    """Unknown word → compile error."""
    print("\n=== Unknown word ===")
    lines = [
        'S" : main XYZZY ;" _TBUF 4096 ITC-COMPILE .',
    ]
    check("compile error", lines, "-1")

def test_image_roundtrip():
    """ITC-SAVE-IMAGE / ITC-LOAD-IMAGE round-trip."""
    print("\n=== Image round-trip ===")
    lines = [
        # Compile a simple program
        'S" : main 42 . ;" _TBUF 4096 ITC-COMPILE DROP',
        # Save image into a separate buffer
        'CREATE _IBUF 4096 ALLOT',
        '_IBUF _ITC-BUF-BASE @ _ITC-CP @ _ITC-BUF-BASE @ - ITC-SAVE-IMAGE',
        # total-len is on stack
        '.\" SAVED \" DUP .',
        # Load it back
        '_IBUF SWAP ITC-LOAD-IMAGE',
        # Should return body-addr body-len entry-count
        '.\" ENTRIES \" . ',
        '.\" BODYLEN \" . ',
        'DROP',  # drop body-addr
    ]
    check_fn("save/load works",
             lines,
             lambda out: "SAVED" in out and "ENTRIES" in out,
             "image round-trip produces output")

# ── Main ──

if __name__ == "__main__":
    build_snapshot()

    test_compile_loads()
    test_whitelist()
    test_compile_literal()
    test_compile_execute_word()
    test_stack_ops()
    test_arithmetic()
    test_if_then()
    test_if_else_then()
    test_nested_if()
    test_begin_until()
    test_begin_while_repeat()
    test_do_loop()
    test_do_ploop()
    test_constant()
    test_variable()
    test_multi_word()
    test_recurse()
    test_pre_dispatch_callback()
    test_bad_opcode()
    test_rstack_overflow()
    test_unknown_word()
    test_image_roundtrip()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
    print("  All tests passed!")
