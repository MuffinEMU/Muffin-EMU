# The on-screen pad, taken from the GamePad itself

BW-198. Branch `ios-gamepad-clone-layout`, cut from `ios-controls-on-extras` (`e1de779b`).

The shipping `ControllerGeometry` is measured from `IMG_3278.jpeg`, a screenshot of an
on-screen pad. This is measured from the hardware: the official Wii U GamePad front
illustration, at **0.425 mm per pixel**. That scale is not assumed - it is checked twice
against Nintendo's published dimensions and agrees both times.

| check | from the image | Nintendo |
|---|---|---|
| body width | 600 px x 0.425 = **255.0 mm** | 255 mm |
| body height | 314 px x 0.425 = **133.5 mm** | 134 mm |
| screen | 324 x 185 px = 137.7 x 78.6 mm, **158 mm diagonal** | 6.2 in = 157.5 mm |

So "life-size" below is a literal claim, not a figure of speech.

Everything is expressed in **D = one face-button diameter = 10.625 mm**, the unit
`ControllerGeometry` already uses. The body turns out to be exactly 24 D wide.

## The hardware, in D

| | D | mm | note |
|---|---|---|---|
| face button diameter | 1.000 | 10.625 | A/B/X/Y |
| Y - A half pitch | 0.960 | 10.2 | the diamond is tighter than the screenshot's 1.240 |
| X - B half pitch | 0.950 | 10.0938 |  |
| d-pad width | 2.280 | 24.225 | a solid cross, not four circles |
| d-pad height | 2.240 | 23.8 |  |
| d-pad arm width | 0.760 | 8.075 |  |
| stick dish | 1.960 | 20.825 |  |
| stick cap | 1.120 | 11.9 |  |
| stick arm length | 2.790 | 29.646 | stick centre to cluster centre |
| + / - diameter | 0.680 | 7.225 |  |
| HOME diameter | 1.040 | 11.05 |  |
| TV / POWER diameter | 0.640 | 6.8 |  |
| body | 24.000 | 255 | exactly 24 face buttons |
| screen | 12.922 | 137.3 | normalised to exactly 16:9 |

The stick arm is the strongest number in the set: **29.65 mm at 69.87 deg**, up and
outboard, and the two halves agree on it to within 0.1 mm. That is a designed
relationship, not an accident of measurement, and it is the one thing the laws below
protect ahead of everything else - it is what a thumb actually learns.

Two facts the shipping layout has differently, both of them the hardware being right:

- **The d-pad is a solid cross**, 2.280 x 2.240 D with 0.760 D arms.
- **+ and - are both on the right**, stacked under A/B/X/Y, + above -. One per side is
  a convention on-screen pads invented; the GamePad never did it.

Not measured: **L / R / ZL / ZR**. They are on the top edge and do not appear in a front
view. Their pill size is kept from the IMG_3278 measurement; their position is placed,
centred above their own stick, which is where they sit on the hardware. They are the only
placed geometry in the file and they are marked as such at their definition.

## The four laws

**1. Size.** `D = 10.625 mm expressed in points`, capped by what the height can hold.
A point is 0.166 mm on an iPhone and 0.192 mm on an iPad, so this needs points-per-inch,
which UIKit does not expose - hence the small model table in `DeviceMetrics`. The result
is the headline: **the clusters are only 61 mm tall, so life-size fits nearly everywhere.**
It is the 255 mm body that never fits, not the controls.

**2. Arrangement.** The hardware arm angle is preserved in preference to keeping the
buttons big. When the height is short, D shrinks first; only if D would fall under the
44 pt touch floor does the arm rake outboard (to a floor of 45 deg), which buys height
without changing the stick-to-cluster distance. On every shipping device, no rake is
needed.

**3. Placement.** Clusters are rigid and pinned to the safe-area edges. **The bezel
between them is the only thing that stretches.** Nothing is ever squeezed. What moves is
the low-priority hardware:

- **+ / -** keep their real slot under A/B/X/Y wherever 4.0 D of room exists below the
  cluster centre - every iPad. Where it does not - every iPhone - they move to the
  *elbow*, the empty diagonal between the stick and the cluster that a thumb already
  sweeps across, one per side.
- **TV / POWER** keep their real place on the bottom rail in framed mode and otherwise
  belong to the pause menu, not the pad.

**4. Mode.** Decided by one question: would a framed picture be at least as big as the
GamePad's own 6.2 in screen (137.3 mm)? Below that, the shell is nostalgia bought with a
smaller picture than the real hardware had, which is the wrong trade.

| mode | when | what it looks like |
|---|---|---|
| `framed` | framed picture >= 137.3 mm wide | the GamePad, bezel and all, picture in the LCD's place, nothing overlapping |
| `overlay` | below that | picture full-bleed, controls floating over its outer thirds |
| `stacked` | portrait | picture along the top, both clusters on the bottom corners |
| `shell` | external display | the picture leaves; the iPad is nothing but a GamePad |

## What every device resolves to

| device | mode | D (pt) | vs life-size | button | +/- | picture (pt) | picture (mm) |
|---|---|---|---|---|---|---|---|
| iPhone SE (3rd gen) | `overlay` | 55.0 | 81% | 8.6 mm | elbow | 666.7x375 | 103.9 x 58.4 |
| iPhone 13 mini | `overlay` | 49.7 | 75% | 8.0 mm | elbow | 602.7x339 | 96.5 x 54.3 |
| iPhone 15 / 16 | `overlay` | 54.5 | 85% | 9.0 mm | elbow | 661.3x372 | 109.6 x 61.6 |
| iPhone 16 Pro | `overlay` | 55.8 | 87% | 9.2 mm | elbow | 677.3x381 | 112.2 x 63.1 |
| iPhone 16 Pro Max | `overlay` | 61.4 | 96% | 10.2 mm | elbow | 744.9x419 | 123.4 x 69.4 |
| iPad mini (A17 Pro) | `overlay` | 68.2 | 100% | 10.6 mm | hardware | 1133x637.3 | 176.6 x 99.3 |
| iPad (A16) / Air 11" | `framed` | 55.2 | 100% | 10.6 mm | hardware | 715x402.2 | 137.6 x 77.4 |
| iPad Pro 11" (M4) | `framed` | 55.2 | 100% | 10.6 mm | hardware | 745x419.1 | 143.4 x 80.6 |
| iPad Air 13" | `framed` | 55.2 | 100% | 10.6 mm | hardware | 901x506.8 | 173.4 x 97.5 |
| iPad Pro 13" (M4) | `framed` | 55.2 | 100% | 10.6 mm | hardware | 911x512.4 | 175.3 x 98.6 |
| iPad Pro 11" Split View 1/2 | `stacked` | 51.9 | 94% | 10.0 mm | hardware | 583x327.9 | 112.2 x 63.1 |
| iPad Pro 11" Slide Over | `stacked` | 49.2 | 89% | 9.5 mm | hardware | 375x210.9 | 72.2 x 40.6 |
| iPad Pro 13" portrait | `stacked` | 55.2 | 100% | 10.6 mm | hardware | 1032x580.5 | 198.6 x 111.7 |
| iPhone 16 Pro Max portrait | `stacked` | 57.7 | 90% | 9.6 mm | hardware | 440x247.5 | 72.9 x 41 |
| iPad Pro 13" + external display | `shell` | 55.2 | 100% | 10.6 mm | hardware | 911x512.4 | 175.3 x 98.6 |

Reading that table:

- **Every iPad is life-size**, including the mini - a 1:1 physical replica of the GamePad's
  controls, with + and - in their real place.
- **iPad Pro 13 in framed mode gives a 175 mm picture** against the hardware's 137 mm. It
  is a GamePad with a screen 28% bigger than the real one and controls that are exactly
  the right size. If a bigger iPad is ever the target, this is the mode to show people.
- **iPhones land at 81-96% of life-size**, all well clear of the 44 pt floor, none of them
  needing the rake. The iPhone 16 Pro Max is within 4% of a real GamePad.
- **The iPad mini is the one interesting call**: it has the height for hardware +/- but
  not the width for a framed picture, so it gets life-size controls floating over a
  full-bleed 177 mm picture. Framing it would have cost 90 mm of picture to gain a bezel.

Full resolved coordinates for every control on every configuration above are in
`muffin_pad_layout.json`; the hardware measurements they derive from are in
`hardware_measurements.json`, with `hardware_measurements_check.png` showing every
measured circle drawn back over the source art.

## Files

| file | what it is |
|---|---|
| `GamePadGeometry.swift` | the constants and the resolver. Typechecks clean; **not in the build** - `src/ios/project.yml` pulls `src/ios/App` in as a group, so moving it there is the whole of wiring it in |
| `index.html` | the same thing as a browsable page with a device picker - opens by double-clicking, no server needed |
| `HANDOFF.md` | what the next person needs: how to verify it, how to wire it in, and the traps |
| `resolve_reference.py` | the same four laws in Python, which generated the mockups |
| `mock_*.png` | what each configuration looks like |
| `muffin_pad_layout.json` | resolved coordinates, all 15 configurations |
| `hardware_measurements.json` | the source measurements, in pixels and mm |

The Swift and the Python were checked against each other on **every configuration and
every control**: 278 controls across 15 configurations, comparing mode, unit, +/- placement,
picture rect, and each control's centre and size. **Zero discrepancies**, so the mockups are
a true picture of what the Swift produces. The same pass asserts that nothing lands outside
a safe area, that no two controls overlap, that nothing covers the picture in framed mode,
that every face button is at or above 44 pt, that both clusters stay level, and that every
picture is exactly 16:9.

## Two things to decide

1. **The d-pad becomes a cross and the iPad +/- both move right.** Both are the hardware
   being right, and both are visible changes to a pad people have already learned. Worth
   a settings toggle if either turns out to be unpopular.
2. **The shipping pad anchors to `proxy.size`, not the safe area**, so on every notched
   iPhone in landscape the outer controls sit under the Dynamic Island. The resolver here
   takes a safe rect instead. That is a bug fix that stands on its own, independent of
   whether any of the rest of this lands.
