# akashic-tui-game-camera — Camera / Viewport Controller

A 2D camera that tracks a target position within a tile-based
world.  Supports instant snap, smooth lerp follow, screen shake,
and viewport bounds clamping.  Positions are stored in fixed-point
(×256) for sub-tile precision.

```forth
REQUIRE tui/game/camera.f
```

`PROVIDED akashic-tui-game-camera` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Positioning](#positioning)
- [Follow / Snap](#follow--snap)
- [Shake](#shake)
- [Configuration](#configuration)
- [Tick](#tick)
- [Queries](#queries)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### CAM-NEW

```
( world-w world-h view-w view-h -- cam )
```

Allocate a 96-byte camera descriptor.  Stores the world bounds
and viewport dimensions.  Initial position is (0, 0), smooth
factor is 0 (instant movement).

```forth
200 150 80 25 CAM-NEW CONSTANT my-cam
```

### CAM-FREE

```
( cam -- )
```

Free the camera descriptor.

---

## Positioning

### CAM-SNAP

```
( cam x y -- )
```

Instantly set the camera to tile position (x, y).  Both the
current position and target are set, centering the viewport.
The position is converted to fixed-point (×256) and offset by
half the viewport size.

### CAM-FOLLOW

```
( cam target-x target-y -- )
```

Set the follow target.  The camera will move toward this
position on each `CAM-TICK`.  If smooth is 0, movement is
instant; otherwise, lerp interpolation is applied.

---

## Shake

### CAM-SHAKE

```
( cam amplitude duration -- )
```

Start a screen shake effect.  `amplitude` is the maximum
pixel offset, `duration` is the number of ticks the shake
lasts.  The amplitude decays linearly over the duration.

---

## Configuration

### CAM-BOUNDS!

```
( cam world-w world-h -- )
```

Update the world bounds used for clamping.

### CAM-VIEW!

```
( cam view-w view-h -- )
```

Update the viewport dimensions (e.g. after a terminal resize).

### CAM-SMOOTH!

```
( cam factor -- )
```

Set the lerp smoothing factor (0–256).  0 means instant
movement; higher values produce smoother, slower following.

---

## Tick

### CAM-TICK

```
( cam -- )
```

Advance the camera one frame.  Applies lerp toward the target
position, decays shake, and clamps to world bounds.

---

## Queries

### CAM-X

```
( cam -- x )
```

Return the current camera X position as an integer
(fixed-point ÷ 256).

### CAM-Y

```
( cam -- y )
```

Return the current camera Y position as an integer
(fixed-point ÷ 256).

---

## Descriptor Layout

96 bytes (12 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0       8  ww          World width (tiles)
 +8       8  wh          World height (tiles)
+16       8  vw          Viewport width (columns)
+24       8  vh          Viewport height (rows)
+32       8  x           Current X position (fixed-point ×256)
+40       8  y           Current Y position (fixed-point ×256)
+48       8  tx          Target X (fixed-point ×256)
+56       8  ty          Target Y (fixed-point ×256)
+64       8  smooth      Lerp factor (0 = instant, 1–256 = smooth)
+72       8  shake-amp   Shake amplitude
+80       8  shake-dur   Shake duration (ticks remaining)
+88       8  shake-seed  PRNG seed for shake offset
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CAM-NEW` | `( ww wh vw vh -- cam )` | Create camera |
| `CAM-FREE` | `( cam -- )` | Free camera |
| `CAM-SNAP` | `( cam x y -- )` | Instant position |
| `CAM-FOLLOW` | `( cam tx ty -- )` | Set follow target |
| `CAM-SHAKE` | `( cam amp dur -- )` | Start shake |
| `CAM-BOUNDS!` | `( cam ww wh -- )` | Update world bounds |
| `CAM-VIEW!` | `( cam vw vh -- )` | Update viewport |
| `CAM-SMOOTH!` | `( cam factor -- )` | Set lerp factor |
| `CAM-TICK` | `( cam -- )` | Advance one frame |
| `CAM-X` | `( cam -- x )` | Get integer X |
| `CAM-Y` | `( cam -- y )` | Get integer Y |
