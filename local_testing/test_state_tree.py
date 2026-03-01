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
FP32_F     = os.path.join(ROOT_DIR, "akashic", "math", "fp32.f")
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
    fp32_lines = _load_forth_lines(FP32_F)
    stree_lines = _load_forth_lines(STREE_F)

    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT',
        'CREATE _WB 4096 ALLOT',
        ': T-INIT  65536 A-XMEM ARENA-NEW ABORT" arena fail"  256 ST-DOC-NEW  DROP ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + str_lines + fp32_lines + stree_lines + test_helpers)
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
    """ST-DOC-NEW creates root, node count = 1."""
    check("init-root-exists", [
        'T-INIT',
        'ST-ROOT 0<> IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("init-node-count", [
        'T-INIT',
        'ST-NODE-COUNT . CR',
    ], '1')

    check("init-root-is-object", [
        'T-INIT',
        'ST-ROOT ST-GET-TYPE . CR',
    ], '7')

    check("init-err-clear", [
        'T-INIT',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: node alloc / free
# ---------------------------------------------------------------------------

def test_alloc_free():
    """Allocate and free nodes."""
    check("alloc-basic", [
        'T-INIT',
        '_ST-ALLOC DUP 0<> IF 1 ELSE 0 THEN . CR',
        'DROP',
    ], '1')

    check("alloc-bumps-count", [
        'T-INIT',
        '_ST-ALLOC DROP',
        'ST-NODE-COUNT . CR',
    ], '2')

    check("free-decrements-count", [
        'T-INIT',
        '_ST-ALLOC _ST-FREE-NODE',
        'ST-NODE-COUNT . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: string pool
# ---------------------------------------------------------------------------

def test_string_pool():
    """_ST-STR-COPY copies into pool and returns valid addr/len."""
    check("str-copy-len", [
        'T-INIT',
        'S" hello" _ST-STR-COPY . . CR',
    ], expected='5 ')

    # Round-trip: copy a string in, read it back byte by byte
    check("str-copy-content", [
        'T-INIT',
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
        'T-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" foo" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT SN.NCHILD @ . CR',
    ], '1')

    # Find child by name
    check("find-child-found", [
        'T-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" bar" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT S" bar" _ST-FIND-CHILD CH1 @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    # Find child — not found
    check("find-child-missing", [
        'T-INIT',
        'ST-ROOT S" nope" _ST-FIND-CHILD . CR',
    ], '0')

    # Detach child
    check("detach-child", [
        'T-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'S" baz" _ST-STR-COPY  CH1 @ SN.NAMEL !  CH1 @ SN.NAMEA !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        'CH1 @ _ST-DETACH',
        'ST-ROOT SN.NCHILD @ . CR',
    ], '0')

    # Multiple children, detach middle
    check("detach-middle", [
        'T-INIT',
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
        'T-INIT',
        '_ST-ALLOC VARIABLE CH1  CH1 !',
        '7 CH1 @ SN.TYPE !',
        'CH1 @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC DUP 7 OVER SN.TYPE ! CH1 @ _ST-APPEND-CHILD',
        'ST-NODE-COUNT .  CH1 @ _ST-DETACH  CH1 @ _ST-DESTROY  ST-NODE-COUNT . CR',
    ], '3 1')

# ---------------------------------------------------------------------------
#  Tests — Stage 1: index child (array-like)
# ---------------------------------------------------------------------------

def test_index_child():
    """_ST-INDEX-CHILD returns nth child."""
    check("index-child-0", [
        'T-INIT',
        '_ST-ALLOC VARIABLE A  A !  7 A @ SN.TYPE !',
        'S" a" _ST-STR-COPY  A @ SN.NAMEL !  A @ SN.NAMEA !',
        'A @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE B  B !  7 B @ SN.TYPE !',
        'S" b" _ST-STR-COPY  B @ SN.NAMEL !  B @ SN.NAMEA !',
        'B @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT 0 _ST-INDEX-CHILD A @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("index-child-1", [
        'T-INIT',
        '_ST-ALLOC VARIABLE A  A !  7 A @ SN.TYPE !',
        'A @ ST-ROOT _ST-APPEND-CHILD',
        '_ST-ALLOC VARIABLE B  B !  7 B @ SN.TYPE !',
        'B @ ST-ROOT _ST-APPEND-CHILD',
        'ST-ROOT 1 _ST-INDEX-CHILD B @ = IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("index-child-oob", [
        'T-INIT',
        'ST-ROOT 5 _ST-INDEX-CHILD . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 2: path-based set / get
# ---------------------------------------------------------------------------

def test_set_get_path():
    """ST-SET-PATH-INT / ST-GET-PATH etc."""
    # Set an integer at a simple path
    check("set-path-int-simple", [
        'T-INIT',
        '42 S" score" ST-SET-PATH-INT',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
        'S" score" ST-GET-PATH DUP 0<> IF ST-GET-INT . THEN CR',
    ], '42')

    # Set nested path
    check("set-path-int-nested", [
        'T-INIT',
        '100 S" ship.speed" ST-SET-PATH-INT',
        'S" ship.speed" ST-GET-PATH ST-GET-INT . CR',
    ], '100')

    # Deeply nested
    check("set-path-int-deep", [
        'T-INIT',
        '7 S" a.b.c.d" ST-SET-PATH-INT',
        'S" a.b.c.d" ST-GET-PATH ST-GET-INT . CR',
    ], '7')

    # Set boolean
    check("set-path-bool", [
        'T-INIT',
        '1 S" ship.active" ST-SET-PATH-BOOL',
        'S" ship.active" ST-GET-PATH ST-GET-BOOL . CR',
    ], '1')

    # Set null
    check("set-path-null", [
        'T-INIT',
        'S" ship.target" ST-SET-PATH-NULL',
        'S" ship.target" ST-GET-PATH ST-NULL? IF 1 ELSE 0 THEN . CR',
    ], '1')

    # Set string
    check("set-path-str", [
        'T-INIT',
        'S" warp" S" ship.drive" ST-SET-PATH-STR',
        'S" ship.drive" ST-GET-PATH DUP ST-GET-TYPE 1 = IF',
        '  ST-GET-STR TYPE CR',
        'ELSE DROP THEN',
    ], 'warp')

    # Overwrite — second set replaces first
    check("set-path-overwrite", [
        'T-INIT',
        '10 S" x" ST-SET-PATH-INT',
        '20 S" x" ST-SET-PATH-INT',
        'S" x" ST-GET-PATH ST-GET-INT . CR',
    ], '20')

    # Get non-existent path
    check("get-path-missing", [
        'T-INIT',
        'S" no.such.path" ST-GET-PATH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 2: delete path
# ---------------------------------------------------------------------------

def test_delete_path():
    """ST-DELETE-PATH removes a node and its subtree."""
    check("delete-path-simple", [
        'T-INIT',
        '42 S" score" ST-SET-PATH-INT',
        'S" score" ST-DELETE-PATH',
        'S" score" ST-GET-PATH . CR',
    ], '0')

    check("delete-path-subtree", [
        'T-INIT',
        '1 S" a.b" ST-SET-PATH-INT',
        '2 S" a.c" ST-SET-PATH-INT',
        'S" a" ST-DELETE-PATH',
        'S" a.b" ST-GET-PATH . CR',
    ], '0')

    check("delete-path-missing", [
        'T-INIT',
        'S" nope" ST-DELETE-PATH',
        'ST-OK? IF 0 ELSE ST-ERR @ . THEN CR',
    ], '1')  # ST-E-NOT-FOUND = 1

# ---------------------------------------------------------------------------
#  Tests — Stage 2: node count after operations
# ---------------------------------------------------------------------------

def test_node_count_ops():
    """Node count tracks allocs/frees through path ops."""
    check("node-count-set", [
        'T-INIT',
        '42 S" a" ST-SET-PATH-INT',
        'ST-NODE-COUNT . CR',
    ], '2')   # root + a

    check("node-count-nested", [
        'T-INIT',
        '42 S" a.b.c" ST-SET-PATH-INT',
        'ST-NODE-COUNT . CR',
    ], '4')   # root + a + b + c

    check("node-count-delete", [
        'T-INIT',
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
        'T-INIT',
        '10 S" scores" ST-ARRAY-APPEND-INT',
        '20 S" scores" ST-ARRAY-APPEND-INT',
        '30 S" scores" ST-ARRAY-APPEND-INT',
        'S" scores" ST-ARRAY-COUNT . CR',
    ], '3')

    check("array-nth-0", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 0 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '10')

    check("array-nth-1", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 1 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '20')

    check("array-remove", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        '30 S" v" ST-ARRAY-APPEND-INT',
        'S" v" 1 ST-ARRAY-REMOVE',  # remove middle (20)
        'S" v" ST-ARRAY-COUNT . CR',
    ], '2')

    check("array-append-str", [
        'T-INIT',
        'S" alice" S" names" ST-ARRAY-APPEND-STR',
        'S" bob"   S" names" ST-ARRAY-APPEND-STR',
        'S" names" 0 ST-ARRAY-NTH ST-GET-STR TYPE CR',
    ], 'alice')

    check("array-nested", [
        'T-INIT',
        '99 S" ship.crew" ST-ARRAY-APPEND-INT',
        'S" ship.crew" ST-ARRAY-COUNT . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: protected paths
# ---------------------------------------------------------------------------

def test_protected():
    """ST-PROTECTED? detects underscore prefix."""
    check("protected-yes", [
        'T-INIT',
        'S" _internal" ST-PROTECTED? IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("protected-no", [
        'T-INIT',
        'S" public" ST-PROTECTED? IF 1 ELSE 0 THEN . CR',
    ], '0')

    # Protected flag is set on node
    check("protected-flag-on-node", [
        'T-INIT',
        '42 S" _secret" ST-SET-PATH-INT',
        'S" _secret" ST-GET-PATH SN.FLAGS @ 1 AND . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: journal
# ---------------------------------------------------------------------------

def test_journal():
    """Journal: add entries, read them back."""
    check("journal-empty", [
        'T-INIT',
        'ST-JOURNAL-COUNT . CR',
    ], '0')

    check("journal-seq-starts-0", [
        'T-INIT',
        'ST-JOURNAL-SEQ . CR',
    ], '0')

    check("journal-add-one", [
        'T-INIT',
        # op=1 path-addr=0 path-len=0 old-type=0 old-val=0 new-type=2 new-val=42
        '1 0 0  0 0  2 42 ST-JOURNAL-ADD',
        'ST-JOURNAL-COUNT . CR',
    ], '1')

    check("journal-seq-increments", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        'ST-JOURNAL-SEQ . CR',
    ], '1')

    check("journal-nth-0", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '0 ST-JOURNAL-NTH 64 + @ . CR',   # new-val of most recent
    ], '99')

    check("journal-nth-1", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '1 ST-JOURNAL-NTH 64 + @ . CR',   # new-val of second most recent
    ], '42')

    check("journal-nth-oob", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '5 ST-JOURNAL-NTH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 3: type coercion on overwrite
# ---------------------------------------------------------------------------

def test_type_overwrite():
    """Setting a new type on existing node coerces correctly."""
    check("int-to-str", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'S" hello" S" x" ST-SET-PATH-STR',
        'S" x" ST-GET-PATH DUP 0<> IF ST-GET-TYPE . CR ELSE DROP THEN',
    ], '1')   # ST-T-STRING

    check("str-to-null", [
        'T-INIT',
        'S" hi" S" x" ST-SET-PATH-STR',
        'S" x" ST-SET-PATH-NULL',
        'S" x" ST-GET-PATH ST-NULL? IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("object-to-int", [
        'T-INIT',
        '1 S" a.b" ST-SET-PATH-INT',   # creates a as object
        '99 S" a" ST-SET-PATH-INT',     # overwrite a to int, destroys children
        'S" a" ST-GET-PATH ST-GET-INT . CR',
    ], '99')

    check("object-to-int-children-gone", [
        'T-INIT',
        '1 S" a.b" ST-SET-PATH-INT',
        '99 S" a" ST-SET-PATH-INT',
        'S" a.b" ST-GET-PATH . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 4: float support (FP32)
# ---------------------------------------------------------------------------

def test_float():
    """ST-SET-FLOAT / ST-GET-FLOAT / ST-SET-PATH-FLOAT using software FP32."""

    # Store and retrieve FP32-ONE (0x3F800000 = 1065353216)
    check("set-get-float-one", [
        'T-INIT',
        'FP32-ONE S" x" ST-SET-PATH-FLOAT',
        'S" x" ST-GET-PATH ST-GET-FLOAT . CR',
    ], '1065353216')

    # Verify type tag is ST-T-FLOAT (5)
    check("float-type-tag", [
        'T-INIT',
        'FP32-ONE S" speed" ST-SET-PATH-FLOAT',
        'S" speed" ST-GET-PATH ST-GET-TYPE . CR',
    ], '5')

    # FP32-TWO (0x40000000 = 1073741824) — round-trip
    check("set-get-float-two", [
        'T-INIT',
        'FP32-TWO S" val" ST-SET-PATH-FLOAT',
        'S" val" ST-GET-PATH ST-GET-FLOAT . CR',
    ], '1073741824')

    # FP32-ZERO (0x00000000) — round-trip
    check("set-get-float-zero", [
        'T-INIT',
        'FP32-ZERO S" z" ST-SET-PATH-FLOAT',
        'S" z" ST-GET-PATH ST-GET-FLOAT FP32-0= IF 1 ELSE 0 THEN . CR',
    ], '1')

    # Nested path float
    check("float-nested-path", [
        'T-INIT',
        'FP32-PI S" ship.heading" ST-SET-PATH-FLOAT',
        'S" ship.heading" ST-GET-PATH ST-GET-FLOAT . CR',
    ], '1078530011')  # 0x40490FDB

    # Convert float to int using FP32>INT
    check("float-to-int", [
        'T-INIT',
        'FP32-TWO S" x" ST-SET-PATH-FLOAT',
        'S" x" ST-GET-PATH ST-GET-FLOAT FP32>INT . CR',
    ], '2')

    # Convert int to float, store, convert back
    check("int-fp32-roundtrip", [
        'T-INIT',
        '42 INT>FP32 S" x" ST-SET-PATH-FLOAT',
        'S" x" ST-GET-PATH ST-GET-FLOAT FP32>INT . CR',
    ], '42')

    # Overwrite int with float
    check("int-to-float-overwrite", [
        'T-INIT',
        '10 S" x" ST-SET-PATH-INT',
        'FP32-ONE S" x" ST-SET-PATH-FLOAT',
        'S" x" ST-GET-PATH ST-GET-TYPE . CR',
    ], '5')   # ST-T-FLOAT

    # Overwrite float with int
    check("float-to-int-overwrite", [
        'T-INIT',
        'FP32-ONE S" x" ST-SET-PATH-FLOAT',
        '99 S" x" ST-SET-PATH-INT',
        'S" x" ST-GET-PATH ST-GET-INT . CR',
    ], '99')

    # Arithmetic: add two FP32 values, check result
    check("fp32-add-via-tree", [
        'T-INIT',
        'FP32-ONE S" a" ST-SET-PATH-FLOAT',
        'FP32-TWO S" b" ST-SET-PATH-FLOAT',
        'S" a" ST-GET-PATH ST-GET-FLOAT',
        'S" b" ST-GET-PATH ST-GET-FLOAT',
        'FP32-ADD FP32>INT . CR',
    ], '3')

    # Overwrite object-with-children to float clears children
    check("object-to-float-clears", [
        'T-INIT',
        '1 S" a.b" ST-SET-PATH-INT',
        'FP32-ONE S" a" ST-SET-PATH-FLOAT',
        'S" a.b" ST-GET-PATH . CR',        # should be 0 (not found)
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: ST-MERGE (Gap 1.1)
# ---------------------------------------------------------------------------

def test_merge():
    """ST-MERGE shallow merges source object into destination object."""

    check("merge-disjoint", [
        'T-INIT',
        '1 S" src.x" ST-SET-PATH-INT',
        '2 S" src.y" ST-SET-PATH-INT',
        '3 S" dst.z" ST-SET-PATH-INT',
        'S" src" S" dst" ST-MERGE',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
        'S" dst.x" ST-GET-PATH ST-GET-INT . CR',
        'S" dst.y" ST-GET-PATH ST-GET-INT . CR',
        'S" dst.z" ST-GET-PATH ST-GET-INT . CR',
    ], check_fn=lambda t: '1' in t and '2' in t and '3' in t)

    check("merge-overlap", [
        'T-INIT',
        '10 S" src.a" ST-SET-PATH-INT',
        '99 S" dst.a" ST-SET-PATH-INT',
        'S" src" S" dst" ST-MERGE',
        'S" dst.a" ST-GET-PATH ST-GET-INT . CR',
    ], '10')

    check("merge-into-empty", [
        'T-INIT',
        '42 S" src.val" ST-SET-PATH-INT',
        # ensure dst exists as empty object
        'S" dst" ST-NAVIGATE 0= IF',
        '  ST-ROOT S" dst" ST-T-OBJECT _ST-ENSURE-CHILD DROP',
        'THEN',
        'S" src" S" dst" ST-MERGE',
        'S" dst.val" ST-GET-PATH ST-GET-INT . CR',
    ], '42')

    check("merge-from-non-object", [
        'T-INIT',
        '42 S" src" ST-SET-PATH-INT',
        'S" dst" ST-NAVIGATE 0= IF',
        '  ST-ROOT S" dst" ST-T-OBJECT _ST-ENSURE-CHILD DROP',
        'THEN',
        'S" src" S" dst" ST-MERGE',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("merge-from-nonexistent", [
        'T-INIT',
        'S" dst" ST-NAVIGATE 0= IF',
        '  ST-ROOT S" dst" ST-T-OBJECT _ST-ENSURE-CHILD DROP',
        'THEN',
        'S" nope" S" dst" ST-MERGE',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Array insertion (Gap 1.2)
# ---------------------------------------------------------------------------

def test_array_insert():
    """ST-ARRAY-INSERT-INT / ST-ARRAY-INSERT-STR."""

    check("insert-at-beginning", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        '99 0 S" v" ST-ARRAY-INSERT-INT',
        'S" v" 0 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '99')

    check("insert-at-end", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '20 S" v" ST-ARRAY-APPEND-INT',
        '99 2 S" v" ST-ARRAY-INSERT-INT',
        'S" v" 2 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '99')

    check("insert-in-middle", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '30 S" v" ST-ARRAY-APPEND-INT',
        '20 1 S" v" ST-ARRAY-INSERT-INT',
        'S" v" 0 ST-ARRAY-NTH ST-GET-INT . S" v" 1 ST-ARRAY-NTH ST-GET-INT . S" v" 2 ST-ARRAY-NTH ST-GET-INT . CR',
    ], '10 20 30')

    check("insert-oob", [
        'T-INIT',
        '10 S" v" ST-ARRAY-APPEND-INT',
        '99 5 S" v" ST-ARRAY-INSERT-INT',
        'ST-OK? IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("insert-str-middle", [
        'T-INIT',
        'S" alice" S" n" ST-ARRAY-APPEND-STR',
        'S" charlie" S" n" ST-ARRAY-APPEND-STR',
        'S" bob" 1 S" n" ST-ARRAY-INSERT-STR',
        'S" n" 1 ST-ARRAY-NTH ST-GET-STR TYPE CR',
    ], 'bob')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Journal resize (Gap 1.3)
# ---------------------------------------------------------------------------

def test_journal_resize():
    """ST-JRNL-SIZE! resizes the journal."""

    check("jrnl-resize-basic", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '500 ST-JRNL-SIZE!',
        'ST-DOC SD.JRNL-MAX @ . CR',
    ], '500')

    check("jrnl-resize-entries-survive", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '2 0 0 0 0 2 99 ST-JOURNAL-ADD',
        '500 ST-JRNL-SIZE!',
        'ST-JOURNAL-COUNT . CR',
    ], '2')

    check("jrnl-resize-read-back", [
        'T-INIT',
        '1 0 0 0 0 2 42 ST-JOURNAL-ADD',
        '500 ST-JRNL-SIZE!',
        '0 ST-JOURNAL-NTH 64 + @ . CR',
    ], '42')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Schema validation (Gap 1.4)
# ---------------------------------------------------------------------------

def test_schema():
    """Schema validation via _schema prefix."""

    check("schema-type-ok", [
        'T-INIT',
        '42 S" user.age" ST-SET-PATH-INT',
        'S" integer" S" _schema.user.age.type" ST-SET-PATH-STR',
        'S" user.age" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-type-reject", [
        'T-INIT',
        'S" hello" S" user.age" ST-SET-PATH-STR',
        'S" integer" S" _schema.user.age.type" ST-SET-PATH-STR',
        'S" user.age" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("schema-min-ok", [
        'T-INIT',
        '10 S" x" ST-SET-PATH-INT',
        'S" integer" S" _schema.x.type" ST-SET-PATH-STR',
        '0 S" _schema.x.min" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-min-reject", [
        'T-INIT',
        '-5 S" x" ST-SET-PATH-INT',
        'S" integer" S" _schema.x.type" ST-SET-PATH-STR',
        '0 S" _schema.x.min" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("schema-max-ok", [
        'T-INIT',
        '50 S" x" ST-SET-PATH-INT',
        '100 S" _schema.x.max" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-max-reject", [
        'T-INIT',
        '200 S" x" ST-SET-PATH-INT',
        '100 S" _schema.x.max" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("schema-minlen-ok", [
        'T-INIT',
        'S" hello" S" name" ST-SET-PATH-STR',
        '2 S" _schema.name.min-length" ST-SET-PATH-INT',
        'S" name" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-minlen-reject", [
        'T-INIT',
        'S" a" S" name" ST-SET-PATH-STR',
        '3 S" _schema.name.min-length" ST-SET-PATH-INT',
        'S" name" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("schema-maxlen-ok", [
        'T-INIT',
        'S" hi" S" name" ST-SET-PATH-STR',
        '10 S" _schema.name.max-length" ST-SET-PATH-INT',
        'S" name" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-maxlen-reject", [
        'T-INIT',
        'S" toolongstring" S" name" ST-SET-PATH-STR',
        '5 S" _schema.name.max-length" ST-SET-PATH-INT',
        'S" name" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '0')

    check("schema-readonly-flag", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        '1 S" _schema.x.read-only" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE DROP',
        'S" x" ST-GET-PATH SN.FLAGS @ 2 AND 0<> IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("schema-no-constraints", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'S" x" ST-VALIDATE IF 1 ELSE 0 THEN . CR',
    ], '1')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Snapshot / Restore (Gap 1.5)
# ---------------------------------------------------------------------------

def test_snapshot():
    """ST-SNAPSHOT / ST-RESTORE."""

    check("snapshot-roundtrip", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'ST-SNAPSHOT',
        '99 S" x" ST-SET-PATH-INT',
        'ST-RESTORE',
        'S" x" ST-GET-PATH ST-GET-INT . CR',
    ], '42')

    check("snapshot-empty-tree", [
        'T-INIT',
        'ST-SNAPSHOT',
        '42 S" x" ST-SET-PATH-INT',
        'ST-RESTORE',
        'S" x" ST-GET-PATH . CR',
    ], '0')

    check("snapshot-multiple-values", [
        'T-INIT',
        '1 S" a" ST-SET-PATH-INT',
        '2 S" b" ST-SET-PATH-INT',
        'ST-SNAPSHOT',
        '99 S" a" ST-SET-PATH-INT',
        '99 S" b" ST-SET-PATH-INT',
        'ST-RESTORE',
        'S" a" ST-GET-PATH ST-GET-INT . S" b" ST-GET-PATH ST-GET-INT . CR',
    ], '1 2')

    check("snapshot-double-restore", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'ST-SNAPSHOT  VARIABLE _SA  VARIABLE _SL  _SL !  _SA !',
        '99 S" x" ST-SET-PATH-INT',
        '_SA @ _SL @ ST-RESTORE',
        'S" x" ST-GET-PATH ST-GET-INT . _SA @ _SL @ ST-RESTORE S" x" ST-GET-PATH ST-GET-INT . CR',
    ], '42 42')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Computed stubs (Gap 1.6)
# ---------------------------------------------------------------------------

def test_computed_stubs():
    """ST-COMPUTED? / ST-COMPUTED!"""

    check("computed-set-flag", [
        'T-INIT',
        'S" add(a,b)" S" result" ST-COMPUTED!',
        'S" result" ST-GET-PATH ST-COMPUTED? IF 1 ELSE 0 THEN . CR',
    ], '1')

    check("computed-normal-node", [
        'T-INIT',
        '42 S" x" ST-SET-PATH-INT',
        'S" x" ST-GET-PATH ST-COMPUTED? IF 1 ELSE 0 THEN . CR',
    ], '0')

# ---------------------------------------------------------------------------
#  Tests — Stage 5: Subscriptions (Gap 1.7)
# ---------------------------------------------------------------------------

def test_subscriptions():
    """ST-SUBSCRIBE / ST-UNSUBSCRIBE / _ST-NOTIFY."""

    check("subscribe-returns-id", [
        'T-INIT',
        "S\" test\" ' NOOP ST-SUBSCRIBE . CR",
    ], '0')

    check("subscribe-second-id", [
        'T-INIT',
        "S\" a\" ' NOOP ST-SUBSCRIBE DROP",
        "S\" b\" ' NOOP ST-SUBSCRIBE . CR",
    ], '1')

    check("notify-fires-callback", [
        'T-INIT',
        'VARIABLE _FIRED  0 _FIRED !',
        ': MY-CB  1 _FIRED ! ;',
        "S\" x\" ' MY-CB ST-SUBSCRIBE DROP",
        'S" x" _ST-NOTIFY',
        '_FIRED @ . CR',
    ], '1')

    check("notify-wrong-path-no-fire", [
        'T-INIT',
        'VARIABLE _FIRED  0 _FIRED !',
        ': MY-CB  1 _FIRED ! ;',
        "S\" x\" ' MY-CB ST-SUBSCRIBE DROP",
        'S" y" _ST-NOTIFY',
        '_FIRED @ . CR',
    ], '0')

    check("unsubscribe-no-fire", [
        'T-INIT',
        'VARIABLE _FIRED  0 _FIRED !',
        ': MY-CB  1 _FIRED ! ;',
        "S\" x\" ' MY-CB ST-SUBSCRIBE",
        'ST-UNSUBSCRIBE',
        'S" x" _ST-NOTIFY',
        '_FIRED @ . CR',
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
        ("Float (FP32)", test_float),
        ("Merge (1.1)", test_merge),
        ("Array Insert (1.2)", test_array_insert),
        ("Journal Resize (1.3)", test_journal_resize),
        ("Schema (1.4)", test_schema),
        ("Snapshot (1.5)", test_snapshot),
        ("Computed Stubs (1.6)", test_computed_stubs),
        ("Subscriptions (1.7)", test_subscriptions),
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
