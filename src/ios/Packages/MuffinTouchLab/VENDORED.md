# MuffinTouchLab (vendored)

[![MuffinEMU](https://img.shields.io/badge/MuffinEMU-Vendored-E5652E?style=for-the-badge&labelColor=1d1d1f)](../../../../README.md) [Back to the README](../../../../README.md)

The on-screen control schemes offered under Settings > On-screen Controls > Control style
(Zone, Float, Adaptive, Frame, Racing, Arc), with the shared pad settings every scheme reads.
Vendored from MuffinEMU-TouchLab at commit `51f1ad33f8a896011ab84f5ed4e1318124504166` on its `shared-settings` branch (not yet
on its main), copied with the same steps as `tools/export-to-muffinemu.sh`, which refuses a
commit that isn't on main. Left out on purpose: `NearestHit.swift` and its checks, which belong
to the Experimental touch work and are not in this release.

> [!WARNING]
> Do not edit these files here. Change them in MuffinEMU-TouchLab, run its checks, and
> re-export - otherwise the next export silently overwrites the change.

Checks: `swift run --package-path src/ios/Packages/MuffinTouchLab touchlab-check`
