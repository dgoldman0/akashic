#!/usr/bin/env python3
"""Reference results for akashic/numeric, computed independently of Forth.

Each function returns the exact bits a numeric kernel must produce.  The
arithmetic comes from MegaPad's exact IEEE oracle (``shared/ieee_fp.py``);
the order of operations is the one ``akashic/numeric/blas1.f`` documents and
``docs/numeric/scientific-computing-plan.md`` decision N5 defines.

Arrays are modelled by their storage: every lane of every tile of every
row, padding included, in row-major order.
"""

from __future__ import annotations

import os
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from shared import ieee_fp as fp  # noqa: E402


TILE = 64
BLOCK_TILES = 32
FP32 = 6
FP64 = 7
FORMATS = {FP32: fp.FP32, FP64: fp.FP64}
ACC = fp.FP64  # FP32 and FP64 both accumulate in binary64


@dataclass
class Array:
    """An nx-by-ny array of format ``fmt`` (6 or 7), as its storage lanes."""

    fmt: int
    nx: int
    ny: int
    lanes: list[int]

    @property
    def format(self) -> fp.Format:
        return FORMATS[self.fmt]

    @property
    def lane_bytes(self) -> int:
        return self.format.width // 8

    @property
    def tile_lanes(self) -> int:
        return TILE // self.lane_bytes

    @property
    def row_tiles(self) -> int:
        return -(-self.nx // self.tile_lanes)

    @property
    def row_lanes(self) -> int:
        return self.row_tiles * self.tile_lanes

    @property
    def tiles(self) -> int:
        return self.row_tiles * self.ny

    @property
    def nbytes(self) -> int:
        return self.tiles * TILE

    def tile(self, index: int) -> list[int]:
        start = index * self.tile_lanes
        return self.lanes[start:start + self.tile_lanes]

    def to_bytes(self) -> bytes:
        code = "<I" if self.lane_bytes == 4 else "<Q"
        return b"".join(struct.pack(code, lane) for lane in self.lanes)

    @classmethod
    def from_bytes(cls, fmt: int, nx: int, ny: int, data: bytes) -> "Array":
        shape = cls(fmt, nx, ny, [])
        code = "<I" if shape.lane_bytes == 4 else "<Q"
        count = shape.tiles * shape.tile_lanes
        shape.lanes = [
            struct.unpack_from(code, data, index * shape.lane_bytes)[0]
            for index in range(count)
        ]
        return shape

    def like(self, lanes: list[int]) -> "Array":
        return Array(self.fmt, self.nx, self.ny, lanes)


def storage_bytes(fmt: int, nx: int, ny: int) -> int:
    return Array(fmt, nx, ny, []).nbytes


def ws_bytes(arr: Array) -> int:
    """Workspace NV-WS-BYTES reports: frame, two staging tiles, partials."""

    blocks = -(-arr.tiles // BLOCK_TILES)
    return (3 + -(-blocks // 8)) * TILE


# ---------------------------------------------------------------------------
# Element-wise kernels
# ---------------------------------------------------------------------------

def add(x: Array, y: Array) -> Array:
    f = x.format
    return x.like([fp.lane_add(f, a, b) for a, b in zip(x.lanes, y.lanes)])


def sub(x: Array, y: Array) -> Array:
    f = x.format
    return x.like([fp.lane_sub(f, a, b) for a, b in zip(x.lanes, y.lanes)])


def mul(x: Array, y: Array) -> Array:
    f = x.format
    return x.like([fp.lane_mul(f, a, b) for a, b in zip(x.lanes, y.lanes)])


def scale(scalar: int, x: Array) -> Array:
    f = x.format
    return x.like([fp.lane_mul(f, a, scalar) for a in x.lanes])


def axpy(scalar: int, x: Array, y: Array) -> Array:
    """``y = RN(x * a + y)`` with one rounding (TFMA)."""

    f = x.format
    return y.like([fp.lane_fma(f, a, scalar, b) for a, b in zip(x.lanes, y.lanes)])


def fill(scalar: int, x: Array) -> Array:
    return x.like([scalar & x.format.mask] * len(x.lanes))


# ---------------------------------------------------------------------------
# Reductions
# ---------------------------------------------------------------------------

def _staged_tiles(arr: Array, pad: int) -> list[list[int]]:
    """Tiles in row-major order, lanes past nx replaced by ``pad``."""

    tiles = []
    for index in range(arr.tiles):
        lanes = list(arr.tile(index))
        first_col = (index % arr.row_tiles) * arr.tile_lanes
        for lane in range(arr.tile_lanes):
            if first_col + lane >= arr.nx:
                lanes[lane] = pad
        tiles.append(lanes)
    return tiles


def _tree(values: list[int]) -> int:
    """Canonical pairwise tree over binary64 values, padded with -0."""

    width = 1
    while width < len(values):
        width *= 2
    padded = values + [ACC.sign_bit] * (width - len(values))
    return fp.reduce_tree(ACC, padded)


def _blocked(tile_results: list[int]) -> int:
    blocks = []
    for start in range(0, len(tile_results), BLOCK_TILES):
        run = tile_results[start:start + BLOCK_TILES]
        value = run[0]
        for result in run[1:]:
            value = fp.lane_add(ACC, value, result)
        blocks.append(value)
    return blocks[0] if len(blocks) == 1 else _tree(blocks)


def _neg_zero(arr: Array) -> int:
    return arr.format.sign_bit


def _widen(arr: Array, bits: int) -> int:
    return fp.lane_convert(ACC, arr.format, bits)


def reduce_sum(x: Array) -> int:
    results = [
        fp.reduce_tree(ACC, [_widen(x, lane) for lane in tile])
        for tile in _staged_tiles(x, _neg_zero(x))
    ]
    return _blocked(results)


def reduce_sumsq(x: Array) -> int:
    f = x.format
    results = [
        fp.reduce_tree(ACC, [fp.lane_product(ACC, f, lane, lane) for lane in tile])
        for tile in _staged_tiles(x, _neg_zero(x))
    ]
    return _blocked(results)


def reduce_asum(x: Array) -> int:
    clear = x.format.mask ^ x.format.sign_bit
    results = [
        fp.reduce_tree(ACC, [_widen(x, lane & clear) for lane in tile])
        for tile in _staged_tiles(x, _neg_zero(x))
    ]
    return _blocked(results)


def reduce_dot(x: Array, y: Array) -> int:
    f = x.format
    results = [
        fp.reduce_tree(ACC, [fp.lane_product(ACC, f, a, b) for a, b in zip(tx, ty)])
        for tx, ty in zip(_staged_tiles(x, _neg_zero(x)), _staged_tiles(y, 0))
    ]
    return _blocked(results)


def _extreme(x: Array, largest: bool) -> int:
    value = None
    for tile in _staged_tiles(x, x.format.canonical_nan):
        result = _widen(x, fp.extreme_index(x.format, tile, largest)[1])
        value = result if value is None else fp.skip_nan_extreme(ACC, value, result, largest)
    return value


def reduce_max(x: Array) -> int:
    return _extreme(x, True)


def reduce_min(x: Array) -> int:
    return _extreme(x, False)


# ---------------------------------------------------------------------------
# Grid stencils (akashic/numeric/stencil2d.f)
# ---------------------------------------------------------------------------

MINUS_FOUR = {FP32: 0xC0800000, FP64: 0xC010000000000000}


@dataclass
class Boundary:
    """Ghost values beyond each side: a Dirichlet vector, or None for zero flux."""

    top: Array | None = None
    bottom: Array | None = None
    left: Array | None = None
    right: Array | None = None


def _grid_row(arr: Array, i: int) -> list[int]:
    return arr.lanes[i * arr.row_lanes:(i + 1) * arr.row_lanes]


def laplace(u: Array, bc: Boundary) -> Array:
    """``up + down``, ``+ left``, ``+ right``, then ``RN(u * -4 + t)``.

    The left and right neighbour rows are the row shifted one element, with
    the ghost value shifted in and +0 in every lane past ``nx``.
    """

    f = u.format
    width = u.row_lanes
    minus_four = MINUS_FOUR[u.fmt]
    lanes: list[int] = []
    for i in range(u.ny):
        row = _grid_row(u, i)
        if i > 0:
            up = _grid_row(u, i - 1)
        else:
            up = _grid_row(bc.top, 0) if bc.top else row
        if i < u.ny - 1:
            down = _grid_row(u, i + 1)
        else:
            down = _grid_row(bc.bottom, 0) if bc.bottom else row
        ghost_left = bc.left.lanes[i] if bc.left else row[0]
        ghost_right = bc.right.lanes[i] if bc.right else row[u.nx - 1]
        zeros = [0] * (width - u.nx)
        left = [ghost_left] + row[:u.nx - 1] + zeros
        right = row[1:u.nx] + [ghost_right] + zeros
        for j in range(width):
            t = fp.lane_add(f, up[j], down[j])
            t = fp.lane_add(f, t, left[j])
            t = fp.lane_add(f, t, right[j])
            lanes.append(fp.lane_fma(f, row[j], minus_four, t))
    return u.like(lanes)


def update(c: int, u: Array, bc: Boundary) -> Array:
    """``RN(L(u) * c + u)``: an explicit step for ``c = r``."""

    f = u.format
    lap = laplace(u, bc)
    return u.like([fp.lane_fma(f, t, c, x) for t, x in zip(lap.lanes, u.lanes)])
