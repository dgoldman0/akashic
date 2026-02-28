#!/usr/bin/env python3
"""Test suite for akashic-state-tree (LIRAQ State Tree Layer 1).

Uses the Megapad-64 emulator to boot KDOS, load string + state-tree, and
exercise each public word.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
STREE_F    = os.path.join(ROOT_DIR, "akashic", "liraq", "state-tree.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers
# ---------------------------------------------------------------------------

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

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf
    )

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])

def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + string + state-tree ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    stree_lines = _load_forth_lines(STREE_F)

    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT',
        'CREATE _WB 4096 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + str_lines + stree_lines + test_helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 800_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-15:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0
    steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return uart_text(buf)


def tstr(s):
    """Build Forth lines that construct string s in _TB using TC."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


# ---------------------------------------------------------------------------
#  Test framework
# ---------------------------------------------------------------------------

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-5:]
        print(f"        got (last lines): {last}")

# ---------------------------------------------------------------------------
#  Tests — Stage 1: initialization & basic structure
# ---------------------------------------------------------------------------

def test_init():
    """ST-INIT creates root, node count = 1."""
    check("init-root-exists", [
        'ST-INIT',
        'ST-ROOT 0<> IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("init-node-count", [
        'ST-INIT',
        'ST-NODE-COUNT . CR',
    ], '1')

    check("init-root-is-object", [
        'ST-INIT',
        'ST-ROOT ST-GET-TYPE . CR',
    ], '6')

    check("init-err-clear", [
        'ST-INIT',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: node alloc / free
# ---------------------------------------------------------------------------

def test_alloc_free():
    """Allocate and free nodes."""
    check("alloc-basic", [
        'ST-INIT',
        '_ST-ALLOC DUP 0<> IF 1 ELSE 0 THEN . CR',
        'DROP',
    ], '1')

    check("alloc-bumps-count", [
        'ST-INIT',
        '_ST-ALLOC DROP',
        'ST-NODE-COUNT . CR',
    ], '2')

    check("free-decrements-count", [
        'ST-INIT',
        '_ST-ALLOC _ST-FREE-NODE',
        'ST-NODE-COUNT . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: string pool
# ---------------------------------------------------------------------------

def test_string_pool():
    """_ST-STR-COPY copies into pool and returns valid addr/len."""
    check("str-copy-len", [
        'ST-INIT',
        'S" hello" _ST-STR-COPY . . CR',
    ], expected='5 ')

    # Round-trip: copy a string in, read it back byte by byte
    check("str-copy-content", [
        'ST-INIT',
        'S" abc" _ST-STR-COPY',     # ( addr len )
        'OVER C@ .  OVER 1+ C@ .  OVER 2 + C@ .  CR',
        '2DROP',
    ], '97 98 99')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: tree structure — append, find, detach
# ---------------------------------------------------------------------------

def test_tree_structure():
    """Append child, find child, detach child."""
    # Create a child under root
    check("append-child", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" foo" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT SN.NCHILD @ . CR',
    ], '1')

    # Find child by name
    check("find-child-found", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" bar" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT S" bar" _ST-FIND-CHILD CH1 @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    # Find child — not found
    check("find-child-missing", [
        'ST-INIT',
        'ST-ROOT S" nope" _ST-FIND-CHILD . CR',
    ], '0')

    # Detach child
    check("detach-child", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" baz" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'CH1 @ _ST-DETACH',
        'ST-ROOT SN.NCHILD @ . CR',
    ], '0')

    # Multiple children, detach middle
    check("detach-middle", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE A  A !  7 A @ SN.TYPE !',
        'S" a" _ST-STR-COPY  A @ SN.NAMEL !  A @ SN.NAMEA !',
        'A @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE B  B !  7 B @ SN.TYPE !',
        'S" b" _ST-STR-COPY  B @ SN.NAMEL !  B @ SN.NAMEA !',
        'B @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE C  C !  7 C @ SN.TYPE !',
        'S" c" _ST-STR-COPY  C @ SN.NAMEL !  C @ SN.NAMEA !',
        'C @ ST-ROOT _ST-APPEND-CHILD',
        'B @ _ST-DETACH',
        'ST-ROOT SN.NCHILD @ . CR',
    ], '2')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: destroy
# ---------------------------------------------------------------------------

def test_destroy():
    """_ST-DESTROY frees subtree."""
    check("destroy-simple", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '6 CH1 @ SN.TYPE !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC DUP 6 OVER SN.TYPE ! CH1 @ _ST-APPEND-CHILD',
        'ST-NODE-COUNT .  CH1 @ _ST-DETACH  CH1 @ _ST-DESTROY  ST-NODE-COUNT . CR',
    ], '3 1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: index child (array-like)
# ---------------------------------------------------------------------------

def test_index_child():
    """_ST-INDEX-CHILD returns nth child."""
    check("index-child-0", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE A  A !  7 A @ SN.TYPE !',
        'S" a" _ST-STR-COPY  A @ SN.NAMEL !  A @ SN.NAMEA !',
        'A @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE B  B !  7 B @ SN.TYPE !',
        'S" b" _ST-STR-COPY  B @ SN.NAMEL !  B @ SN.NAMEA !',
        'B @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT 0 _ST-INDEX-CHILD A @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("index-child-1", [
        'ST-INIT',
        '_ST-ALLOC VARIABLE A  A !  7 A @ SN.TYPE !',
        'A @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE B  B !  7 B @ SN.TYPE !',
        'B @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT 1 _ST-INDEX-CHILD B @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("index-child-oob", [
        'ST-INIT',
        'ST-ROOT 5 _ST-INDEX-CHILD . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 2: path-based set / get
# ---------------------------------------------------------------------------

def test_set_get_path():
    """ST-SET-PATH-INT / ST-GET-PATH etc."""
    # Set an integer at a simple path
    check("set-path-int-simple", [
        'ST-INIT',
        '42 S" score" ST-SET-PATH-INT',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
        'S" score" ST-GET-PATH DUP 0<> IF ST-GET-INT . THEN CR',
    ], '42')

    # Set nested path
    check("set-path-int-nested", [
        'ST-INIT',
        '100 S" ship.speed" ST-SET-PATH-INT',
        'S" ship.speed" ST-GET-PATH ST-GET-INT . CR',
    ], '100')

    # Deeply nested
    check("set-path-int-deep", [
        'ST-INIT',
        '7 S" a.b.c.d" ST-SET-PATH-INT',
        'S" a.b.c.d" ST-GET-PATH ST-GET-INT . CR',
    ], '7')

    # Set boolean
    check("set-path-bool", [
        'ST-INIT',
        '1 S" ship.active" ST-SET-PATH-BOOL',
        'S" ship.active" ST-GET-PATH ST-GET-BOOL . CR',
    ], '1')

    # Set null
    check("set-path-null", [
        'ST-INIT',
        'S" ship.target" ST-SET-PATH-NULL',
        'S" ship.target" ST-GET-PATH ST-NULL? IF 1 ELSE 0 THEN . CR',
    ], '1')

    # Set string
    check("set-path-str", [
        'ST-INIT',
        'S" warp" S" ship.drive" ST-SET-PATH-STR',
        'S" ship.drive" ST-GET-PATH DUP ST-GET-TYPE 1 = IF',
        '  ST-GET-STR TYPE CR',
        'ELSE DROP THEN',
    ], 'warp')

    # Overwrite — second set replaces first
    check("set-path-overwrite", [
        'ST-INIT',
        '10 S" x" ST-SET-PATH-INT',
        '20 S" x" ST-SET-PATH-INT',
        'S" x" ST-GET-PATH ST-GET-INT . CR',
    ], '20')

    # Get non-existent path
    check("get-path-missing", [
        'ST-INIT',
        'S" no.such.path" ST-GET-PATH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 2: delete path
# ---------------------------------------------------------------------------

def test_delete_path():
    """ST-DELETE-PATH removes a node and its subtree."""
    check("delete-path-simple", [
        'ST-INIT',
        '42 S" score" ST-SET-PATH-INT',
        'S" score" ST-DELETE-PATH',
        'S" score" ST-GET-PATH . CR',
    ], '0')

    check("delete-path-subtree", [
        'ST-INIT',
        '1 S" a.b" ST-SET-PATH-INT',
        '2 S" a.c" ST-SET-PATH-INT',
        'S" a" ST-DELETE-PATH',
        'S" a.b" ST-GET-PATH . CR',
    ], '0')

    check("delete-path-missing", [
        'ST-INIT',
        'S" nope" ST-DELETE-PATH',
        'ST-OK? IF 0 ELSE ST-ERR @ . THEN CR',
    ], '1')  # ST-E-NOT-FOUND = 1

# ---------------------------------------------------------------------------
#  Tests — Stage 2: node count after operations
# ---------------------------------------------------------------------------

def test_node_count_ops():
    """Node count tracks allocs/frees through path ops."""
    check("node-count-set", [
        'ST-INIT',
        '42 S" a" ST-SET-PATH-INT',
        'ST-NODE-COUNT . CR',
    ], '2')   # root + a

    check("node-count-nested", [
        'ST-INIT',
        '42 S" a.b.c" ST-SET-PATH-INT',
        'ST-NODE-COUNT . CR',
    ], '4')   # root + a + b + c

    check("node-count-delete", [
        'ST-INIT',
        '42 S" a.b" ST-SET-PATH-INT',
        'S" a" ST-DELETE-PATH',
        'ST-NODE-COUNT . CR',
    ], '1')   # just root

# ---------------------------------------------------------------------------
#  Tests — Stage 3: arrays
# ---------------------------------------------------------------------------

def test_arrays():
    """Array mutations: append, count, nth, remove."""
    check("array-append-int", [
        'ST-INIT',
        '10 S" scores" ST-ARRAY-APPEND-INT',
        '20 S" scores" ST-ARRAY-APPEND-INT',
        '30 S" scores" ST-ARRAY-APPEND-INT',
        'S" scores" ST-ARRAY-COUNT . CR',
    ], '3')

    check("array-nth-0", [
        'ST-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 0 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '10')

    check("array-nth-1", [
        'ST-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 1 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '20')

    check("array-remove", [
        'ST-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        '30 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 1 ST-ARRAY-REMOVE',  # remove middle (20)
        'S" v" ST-ARRAY-COUNT . CR',
    ], '2')

    check("array-append-str", [
        'ST-INIT',
        'S" alice" S" names" ST-ARRAY-APPEND-STR',
        'S" bob"   S" names" ST-ARRAY-APPEND-STR',
        'S" names" 0 ST-ARRAY-NTH ST-GET-STR TYPE CR',
    ], 'alice')

    check("array-nested", [
        'ST-INIT',
        '99 S" ship.crew" ST-ARRAY-APPEND-INT',
        'S" ship.crew" ST-ARRAY-COUNT . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: protected paths
# ---------------------------------------------------------------------------

def test_protected():
    """ST-PROTECTED? detects underscore prefix."""
    check("protected-yes", [
        'ST-INIT',
        'S" _internal" ST-PROTECTED? IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("protected-no", [
        'ST-INIT',
        'S" public" ST-PROTECTED? IF 1 ELSE 0 THEN . CR',
    ], '0')

    # Protected flag is set on node
    check("protected-flag-on-node", [
        'ST-INIT',
        '42 S" _secret" ST-SET-PATH-INT',
        'S" _secret" ST-GET-PATH SN.FLAGS @ 1 AND . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: journal
# ---------------------------------------------------------------------------

def test_journal():
    """Journal: add entries, read them back."""
    check("journal-empty", [
        'ST-INIT',
        'ST-JOURNAL-COUNT . CR',
    ], '0')

    check("journal-seq-starts-0", [
        'ST-INIT',
        'ST-JOURNAL-SEQ . CR',
    ], '0')

    check("journal-add-one", [
        'ST-INIT',
        # op=1 path-addr=0 path-len=0 old-type=0 old-val=0 new-type=2 new-val=42
        '1 0 0  0 0  2 42 ST-JOURNAL-ADD',
        'ST-JOURNAL-COUNT . CR',
    ], '1')

    check("journal-seq-increments", [
        'ST-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        'ST-JOURNAL-SEQ . CR',
    ], '1')

    check("journal-nth-0", [
        'ST-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '0 ST-JOURNAL-NTH 64 + @ . CR',   # new-val of most recent
    ], '99')

    check("journal-nth-1", [
        'ST-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '1 ST-JOURNAL-NTH 64 + @ . CR',   # new-val of second most recent
    ], '42')

    check("journal-nth-oob", [
        'ST-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '5 ST-JOURNAL-NTH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: type coercion on overwrite
# ---------------------------------------------------------------------------

def test_type_overwrite():
    """Setting a new type on existing node coerces correctly."""
    check("int-to-str", [
        'ST-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'S" hello" S" x" ST-SET-PATH-STR',
        'S" x" ST-GET-PATH DUP 0<> IF ST-GET-TYPE . CR ELSE DROP THEN',
    ], '1')   # ST-T-STRING

    check("str-to-null", [
        'ST-INIT',
        'S" hi" S" x" ST-SET-PATH-STR',
        'S" x" ST-SET-PATH-NULL',
        'S" x" ST-GET-PATH ST-NULL? IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("object-to-int", [
        'ST-INIT',
        '1 S" a.b" ST-SET-PATH-INT',   # creates a as object
        '99 S" a" ST-SET-PATH-INT',     # overwrite a to int, destroys children
        'S" a" ST-GET-PATH ST-GET-INT . CR',
    ], '99')

    check("object-to-int-children-gone", [
        'ST-INIT',
        '1 S" a.b" ST-SET-PATH-INT',
        '99 S" a" ST-SET-PATH-INT',
        'S" a.b" ST-GET-PATH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

def main():
    build_snapshot()
    print()

    groups = [
        ("Initialization", test_init),
        ("Alloc/Free", test_alloc_free),
        ("String Pool", test_string_pool),
        ("Tree Structure", test_tree_structure),
        ("Destroy", test_destroy),
        ("Index Child", test_index_child),
        ("Set/Get Path", test_set_get_path),
        ("Delete Path", test_delete_path),
        ("Node Count Ops", test_node_count_ops),
        ("Arrays", test_arrays),
        ("Protected Paths", test_protected),
        ("Journal", test_journal),
        ("Type Overwrite", test_type_overwrite),
    ]

    for label, fn in groups:
        print(f"[{label}]")
        fn()
        print()

    total = _pass_count + _fail_count
    print(f"Result: {_pass_count}/{total} passed, {_fail_count} failed")
    return 0 if _fail_count == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
