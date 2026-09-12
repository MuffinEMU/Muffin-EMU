# Handoff — BW-198, the GamePad-clone pad layout

Branch `ios-gamepad-clone-layout` on `kiddreads/cemu-ios-muffin`, cut from
`ios-controls-on-extras` (`e1de779b`). **Nothing in this branch is in the build.**

## State

Done and verified. The geometry, the resolver, the resolved coordinates for 15
configurations, the mockups, the spec and the browsable page all exist and agree with each
other. What has *not* happened is any change to a file the app compiles.

## What is here

| file | what it is |
|---|---|
| `GamePadGeometry.swift` | the constants and the resolver — the only file meant to move |
| `GAMEPAD_LAYOUT.md` | the spec: measurement basis, the four laws, per-device results |
| `index.html` | the same thing as a page, with a device picker. Opens by double-clicking; no server needed |
| `muffin_pad_layout.json` | resolved coordinates, all 15 configurations |
| `hardware_measurements.json` | the source measurements in px and mm |
| `hardware_measurements_check.png` | every measured circle drawn back over the source art |
| `resolve_reference.py` | the same laws in Python — the cross-check, and what drew the mockups |
| `mock_*.png` | eight configurations rendered |

## Verifying it yourself

```sh
cd docs/gamepad-layout
swiftc -typecheck GamePadGeometry.swift          # the UIKit block is canImport-excluded on macOS
python3 resolve_reference.py                     # prints the per-device table
```

The cross-check that matters — Swift against Python on every configuration and every
control — is not a committed script because it needs a `main.swift` harness; it was run
before this commit and reported **336 controls across 18 configurations, zero
discrepancies**, along with: nothing outside a safe area, no two controls overlapping
(tested with exact shapes — the d-pad as its two real arms, not the square around them),
**both clusters clearing each other by at least 0.6 D**, no control over the picture in
framed mode, every face button at or above 44 pt in landscape, both clusters level, every
picture exactly 16:9. It also exercises `DeviceMetrics` on twelve probes.

## Wiring it in

1. `git mv docs/gamepad-layout/GamePadGeometry.swift src/ios/App/`. `project.yml` pulls
   `src/ios/App` in as a group, so that is the whole of it — no project file to edit.
2. In `ControllerPad.body`, replace

   ```swift
   let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)
   ```

   with

   ```swift
   let layout = PadLayout.resolve(container: proxy.size,
                                  safeArea: proxy.frame(in: .local).inset(by: proxy.safeAreaInsets),
                                  pointsPerInch: DeviceMetrics.pointsPerInch,
                                  userScale: CGFloat(userScale))
   ```

   and position each control at `layout.controls[id]!.centre`.
3. `ControllerCustomLayout` and the drag offsets apply on top, unchanged. This only
   changes where "unmoved" is, so `ControllerLayoutSettings.reset()` needs no edit.
4. The d-pad is a `.cross`, not four circles — hit-test it with
   `PadLayout.dpadDirections(at:centre:size:)`, which is eight-way and presses two ids on
   a diagonal. Four separate button rects have no diagonal, and a Wii U d-pad has them.

## Traps

- **The ids match the bridge already**: `up/down/left/right/L3/R3/X/Y/A/B/plus/minus/L/R/ZL/ZR`.
  The pad has never been the short side — `CemuBridge.h` has taken all 16 since it was written.
- **A stick direction sent as a button press is silently discarded.** `VPADRead()` skips
  every `is_axis_mapping()` id and derives the sticks from `get_axis()`. Anything analog
  goes through `cemu_bridge_set_stick_axis` — x right-positive, y **UP**-positive, the
  console's convention, not the screen's. `STICK_L`/`STICK_R` are the clicks only.
- **Life-size depends entirely on points-per-inch**, which UIKit does not expose.
  `DeviceMetrics` resolves it from four sources — a stored calibration, an exact
  `hw.machine` match, a known panel by native pixel size, then a derivation from idiom and
  scale. Call `DeviceMetrics.current()` once at launch and **log `detail`**: it is the only
  thing that makes a wrong-sized pad diagnosable after the fact. If `source == .derived`,
  the device is new to the app — the layout is still close, and `PadCalibrationView` makes
  it exact against a bank card (ISO/IEC 7810 ID-1, 85.60 mm).
- **The cluster-gap invariant is not decorative.** `PadLayout.minimumClusterGap` is what
  keeps the two halves off each other; the width clamp that enforces it must include *both*
  edge margins. Omitting them prescribes a negative gap, which is precisely how Y ended up
  drawn on top of the d-pad's right arm in Slide Over and in portrait.
- **This branch is what GitHub Pages is serving.** Deleting or force-pushing it takes the
  page down with it.

## The target device

`iPad Pro 12.9" (2020)` — the A12Z this port is actually for — is in the table by name:
framed, life-size, a 173 × 98 mm picture against the hardware's own 137 × 77 mm. It is
also what the page's device picker opens on.

## Still open — both need Void

1. **The d-pad becomes a solid cross, and on iPads + and − both move to the right.** Both
   are the hardware being right; both are visible changes to a pad people have learned.
2. **The safe-area fix stands alone.** The shipping pad anchors to `proxy.size`, so on a
   notched iPhone in landscape the outer controls sit under the Dynamic Island. Worth
   taking whatever happens to the rest of this.

## Do not

- Re-derive the layout by eye. It is measured; `hardware_measurements.json` is the source,
  and `hardware_measurements_check.png` shows the measurements over the art. Same rule that
  produced the last rebuild.
- Push this to `main` or merge it without those two decisions being made.
